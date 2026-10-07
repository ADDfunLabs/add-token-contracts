// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../TokenSale.sol";
import "./ADDTaxDividend.sol";

/// @notice ADD fixed-price launch token with immutable, post-graduation Pancake V2 pool-transfer taxes.
/// @dev Wallet transfers are untaxed. V2 pool transfers also include third-party liquidity adds/removes;
/// standard ERC20 transfers cannot reliably distinguish those from swaps. Protocol processor LP transfers are exempt.
contract ADDTaxToken is TokenSale {
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;
    address public taxProcessor;
    address public dividend;
    address public dexFactory;
    bool private taxInitialized;
    bool private automaticProcessing;
    uint256 public constant AUTO_CALL_GAS=5_000_000;
    uint256 private constant TRADE_GAS_RESERVE=300_000;
    event TradeTax(address indexed from,address indexed to,uint256 amount);
    event AutomaticProcessingDeferred();
    function initializeTax(ADDTaxTypes.Config calldata c,address processor,address dividend_,address router_) external {
        require(msg.sender==initializationAuthority() && !taxInitialized, "Tax initialization forbidden");
        require(processor.code.length>0 && dividend_.code.length>0, "Invalid tax modules");
        ADDTaxTypes.validate(c); taxInitialized=true;
        buyTaxBps=c.buyTaxBps; sellTaxBps=c.sellTaxBps; taxProcessor=processor; dividend=dividend_;
        dexFactory=IADDTaxRouter(router_).factory(); require(dexFactory.code.length>0,"Invalid DEX factory");
    }
    function _afterLaunchInitialization() internal view override { require(taxInitialized,"Tax not configured"); }
    /// @dev Bounded reads avoid copying arbitrary returndata from wallet contracts. Only configured V2 factory pairs qualify.
    function _addressGetter(address target,bytes memory input) private view returns(address value) {
        bool ok; uint256 result; uint256 size;
        assembly ("memory-safe") {
            let p:=mload(0x40)
            ok:=staticcall(20000,target,add(input,32),mload(input),p,32)
            size:=returndatasize()
            result:=mload(p)
        }
        if(ok && size==32 && result<=type(uint160).max) value=address(uint160(result));
    }
    function isTaxPool(address account) public view returns(bool) {
        if(account==pairAddress && account!=address(0)) return true;
        if(account.code.length==0 || account==factory || account==taxProcessor || account==dividend) return false;
        address a=_addressGetter(account,abi.encodeWithSignature("token0()"));
        address b=_addressGetter(account,abi.encodeWithSignature("token1()"));
        if(a!=address(this) && b!=address(this)) return false;
        return _addressGetter(dexFactory,abi.encodeWithSignature("getPair(address,address)",a,b))==account;
    }
    function _syncShare(address account) private {
        if(account==address(0)) return;
        bool excluded=account==LP_BURN_ADDRESS || account==address(this) || account==factory ||
            account==router || account==taxProcessor || account==dividend || isTaxPool(account);
        // A future CREATE2 pair address may have received tokens before it acquired code.
        // Reconcile its old share to zero when a pool transfer is observed, retaining already accrued credit.
        ADDTaxDividend(payable(dividend)).setShare(account,excluded?0:balanceOf(account));
    }
    function _update(address from,address to,uint256 value) internal override {
        // A dividend receiver may be a contract. During the hook only the two fixed modules may send this
        // token; a receiver cannot recursively trade/transfer it and interfere with the original pool input.
        if(automaticProcessing) require(from==taxProcessor || from==dividend,"Nested transfer during tax processing");
        uint256 tax;
        if(from!=address(0) && phase==Phase.DEX && from!=taxProcessor && from!=dividend && to!=taxProcessor && to!=dividend) {
            bool fromPool=isTaxPool(from); bool toPool=isTaxPool(to);
            if(value>0 && toPool && !fromPool) _triggerTaxes();
            uint256 rate=fromPool?buyTaxBps:toPool?sellTaxBps:0;
            tax=FullMath.mulDiv(value,rate,10_000);
        }
        if(tax>0) { super._update(from,taxProcessor,tax); emit TradeTax(from,to,tax); }
        super._update(from,to,value-tax);
        if(dividend!=address(0)) { _syncShare(from); if(to!=from) _syncShare(to); }
    }
    /// @dev Mirrors the safe V2 timing used by Flap: process OLD taxes before a sell's pool balance changes.
    ///      Never invoked on buy outputs or pool-to-pool hops (the source pair may hold its lock).
    ///      A deterministic floor is essential: catch-and-skip on low gas would let eth_estimateGas find a cheap
    ///      transaction which NEVER processes rewards. The higher gas LIMIT is reserved, not all charged.
    ///      After the floor, bounded stage failures do not invalidate the underlying trade. User minOut still applies.
    function _triggerTaxes() private {
        require(gasleft()>=AUTO_CALL_GAS+AUTO_CALL_GAS/63+TRADE_GAS_RESERVE,"Tax trade gas limit too low");
        automaticProcessing=true;
        address target=taxProcessor; bytes memory data=abi.encodeWithSignature("onTrade()"); bool ok;
        uint256 allowance=AUTO_CALL_GAS;
        // Do not copy failure data; the caller keeps gas to finish tax deduction, transfer and share updates.
        assembly ("memory-safe") { ok:=call(allowance,target,0,add(data,32),mload(data),0,0) }
        automaticProcessing=false; if(!ok) emit AutomaticProcessingDeferred();
    }
}
