// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDTaxTypes.sol";
import "../FullMath.sol";
import "../openzeppelin/SafeERC20.sol";

interface IADDTaxPair {
    function token0() external view returns(address);
    function getReserves() external view returns(uint112,uint112,uint32);
    function price0CumulativeLast() external view returns(uint256);
    function price1CumulativeLast() external view returns(uint256);
}
interface IADDTaxPairFactory { function getPair(address,address) external view returns(address); }

/// @notice V2 cumulative-price guard for automatic tax conversions; not a price oracle for user trades.
/// @dev Uses the V2 counterfactual cumulative algorithm, including intentional uint32/uint256 wraparound.
///      A new/idle market needs two observations 5–30 minutes apart. Missing/stale data defers processing.
///      This bounds spot deviation/size/slippage; it cannot eliminate sustained manipulation or MEV.
library ADDTaxPriceGuard {
    uint256 internal constant Q112=2**112;
    uint32 internal constant WINDOW=300;
    uint32 internal constant MAX_AGE=1800;
    struct Observation {
        uint256 cumulative0; uint256 cumulative1;
        uint224 average0; uint224 average1;
        uint32 timestamp; uint32 averageAt;
        bool initialized; bool ready;
    }
    struct State { mapping(address=>Observation) observations; }

    function pairFor(address router,address input,address output) internal view returns(address pair) {
        pair=IADDTaxPairFactory(IADDTaxRouter(router).factory()).getPair(input,output);
        require(pair.code.length>0,"Auto pair unavailable");
    }
    function reserves(address pair,address input,address output) internal view returns(uint256 rin,uint256 rout,bool forward) {
        (uint112 r0,uint112 r1,)=IADDTaxPair(pair).getReserves();
        forward=IADDTaxPair(pair).token0()==input; (rin,rout)=forward?(uint256(r0),uint256(r1)):(uint256(r1),uint256(r0));
        require(rin>0 && rout>0,"Auto empty pool");
        // An in-flight multi-hop swap or manual LP deposit can already have sent the OTHER asset to the pool.
        // Never consume that input in our own swap or use an un-synced donation as an observation.
        require(IERC20Minimal(input).balanceOf(pair)==rin && IERC20Minimal(output).balanceOf(pair)==rout,"Auto pool busy");
    }
    function observe(State storage self,address router,address input,address output) internal {
        address pair=pairFor(router,input,output);
        reserves(pair,input,output);
        (uint112 r0,uint112 r1,uint32 updated)=IADDTaxPair(pair).getReserves();
        uint256 c0=IADDTaxPair(pair).price0CumulativeLast(); uint256 c1=IADDTaxPair(pair).price1CumulativeLast();
        uint32 now32=uint32(block.timestamp);
        unchecked {
            uint32 elapsed=now32-updated;
            c0+=uint256((uint224(r1)<<112)/r0)*elapsed;
            c1+=uint256((uint224(r0)<<112)/r1)*elapsed;
        }
        Observation storage o=self.observations[pair]; uint32 age;
        unchecked { age=now32-o.timestamp; }
        if(!o.initialized || age>MAX_AGE) {
            o.initialized=true; o.ready=false; o.average0=0; o.average1=0; o.averageAt=0;
        } else if(age>=WINDOW) {
            unchecked { o.average0=uint224((c0-o.cumulative0)/age); o.average1=uint224((c1-o.cumulative1)/age); }
            o.averageAt=now32; o.ready=true;
        } else return; // Do not let frequent trades continually restart the observation window.
        o.timestamp=now32; o.cumulative0=c0; o.cumulative1=c1;
    }
    function checkedPrice(State storage self,address router,address input,address output)
        internal view returns(uint256 rin,uint256 rout,uint256 average) {
        address pair=pairFor(router,input,output); bool forward;
        (rin,rout,forward)=reserves(pair,input,output);
        Observation storage o=self.observations[pair]; uint32 age;
        unchecked { age=uint32(block.timestamp)-o.averageAt; }
        require(o.ready && age<=MAX_AGE,"Auto price warming or stale");
        average=forward?o.average0:o.average1; require(average>0,"Auto zero price");
        uint256 spot=FullMath.mulDiv(rout,Q112,rin);
        require(spot>=FullMath.mulDiv(average,9500,10000) && spot<=FullMath.mulDiv(average,10500,10000),"Auto price deviation");
    }
    /// @dev Cap EACH route hop at 0.1% of input reserve. Reverse spot conversion of downstream capacity is
    ///      conservative because V2 fees/price impact reduce actual intermediate output. No unlimited backlog swap.
    function quote(State storage self,address router,address[] memory path,uint256 requested)
        internal view returns(uint256 amount,uint256 minimum) {
        uint256 capacity=type(uint256).max;
        for(uint256 i=path.length-1;i>0;i--) {
            (uint256 rin,uint256 rout,)=checkedPrice(self,router,path[i-1],path[i]);
            uint256 cap=rin/1000;
            if(capacity!=type(uint256).max) {
                uint256 upstream=FullMath.mulDiv(capacity,rin,rout); if(upstream<cap) cap=upstream;
            }
            capacity=cap;
        }
        amount=requested<capacity?requested:capacity; require(amount>0,"Auto amount too small");
        uint256 expected=amount;
        for(uint256 i;i+1<path.length;i++) {
            (,,uint256 average)=checkedPrice(self,router,path[i],path[i+1]);
            expected=FullMath.mulDiv(FullMath.mulDiv(expected,average,Q112),9975,10000);
        }
        uint256[] memory spot=IADDTaxRouter(router).getAmountsOut(amount,path);
        uint256 spotOut=spot[spot.length-1];
        // Both the established time average and current quote impose a NON-ZERO 3% bound.
        minimum=FullMath.mulDiv(expected>spotOut?expected:spotOut,9700,10000);
        require(minimum>0 && spotOut>=minimum,"Auto minimum unavailable");
    }
}
