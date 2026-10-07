// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./IADDPortalV1.sol";
import "./ADDFixedPriceMathV1.sol";
import "../openzeppelin/SafeERC20.sol";

/// @notice Immutable, read-only pricing module automatically deployed with Portal.
/// @dev Never holds, approves or transfers funds. Only the Portal ledger supplies
///      authoritative inventory/state; this module performs the existing V1 maths.
contract ADDPortalQuoterV1 {
    address public immutable router;
    address public immutable wrappedNative;
    address public immutable dexFactory;
    error InvalidTarget();
    error UnsupportedAsset();
    error InvalidPair();
    error InvalidAmount();
    error SlippageExceeded();
    constructor(address router_) {
        router = router_;
        wrappedNative = IADDV2RouterV1(router_).WETH();
        dexFactory = IADDV2RouterV1(router_).factory();
    }
    function validateQuoteAsset(address asset) public view returns (uint8 decimals_) {
        if (asset.code.length == 0 || asset == wrappedNative) revert UnsupportedAsset();
        (bool ok,bytes memory data) = asset.staticcall{gas:30000}(abi.encodeWithSignature("decimals()"));
        if (!ok || data.length != 32 || abi.decode(data,(uint256)) > 36) revert UnsupportedAsset();
        decimals_ = uint8(abi.decode(data,(uint256)));
        address pair = IADDV2FactoryV1(dexFactory).getPair(asset,wrappedNative);
        if (pair.code.length == 0) revert InvalidPair();
        address a = IADDV2PairV1(pair).token0();
        address b = IADDV2PairV1(pair).token1();
        if (!((a == asset && b == wrappedNative) || (b == asset && a == wrappedNative))) revert InvalidPair();
        (uint112 r0,uint112 r1,) = IADDV2PairV1(pair).getReserves();
        if (r0 == 0 || r1 == 0) revert UnsupportedAsset();
    }
    function quoteGraduationTarget(address asset,uint256 targetBNB) external view returns (uint256 target,uint8 decimals_) {
        if (targetBNB < 1 ether) revert InvalidTarget();
        if (asset == address(0)) return (targetBNB,18);
        decimals_ = validateQuoteAsset(asset);
        uint256 quoted = IADDV2RouterV1(router).getAmountsOut(targetBNB,_path(asset,true))[1];
        if (quoted == 0) revert InvalidTarget();
        uint256 unit = 10 ** uint256(decimals_);
        target = FullMath.mulDivUp(quoted,1,unit) * unit;
    }
    function quoteBuy(uint256 payment,uint256 remaining,uint256 saleAllocation,uint256 quoteTarget,address asset)
        external view returns (uint256 tokens,uint256 principal,uint256 nativeUsed,uint256 fee,uint256 refund)
    {
        if (asset == address(0)) {
            (tokens,principal,fee,refund) = ADDFixedPriceMathV1.quoteNativeBuy(payment,remaining,saleAllocation,quoteTarget);
            nativeUsed = principal;
        } else {
            if (payment == 0 || remaining == 0) return (0,0,0,0,payment);
            uint256 budget = payment - payment / 100;
            uint256 quoted = IADDV2RouterV1(router).getAmountsOut(budget,_path(asset,true))[1];
            uint256 remainingCost = ADDFixedPriceMathV1.costUp(remaining,saleAllocation,quoteTarget);
            tokens = quoted >= remainingCost ? remaining : FullMath.mulDiv(quoted,saleAllocation,quoteTarget);
            if (tokens == 0) return (0,0,0,0,payment);
            principal = ADDFixedPriceMathV1.costUp(tokens,saleAllocation,quoteTarget);
            nativeUsed = IADDV2RouterV1(router).getAmountsIn(principal,_path(asset,true))[0];
            if (nativeUsed > budget) revert SlippageExceeded();
            fee = nativeUsed == budget ? payment / 100 : nativeUsed / 99;
            refund = payment - nativeUsed - fee;
        }
    }
    function quoteSell(uint256 amount,uint256 saleAllocation,uint256 quoteTarget,address asset)
        external view returns (uint256 principal,uint256 gross,uint256 fee,uint256 net)
    {
        principal = ADDFixedPriceMathV1.valueDown(amount,saleAllocation,quoteTarget);
        if (principal == 0) revert InvalidAmount();
        gross = asset == address(0) ? principal : IADDV2RouterV1(router).getAmountsOut(principal,_path(asset,false))[1];
        fee = gross / 100;
        net = gross - fee;
    }
    function _path(address asset,bool buying) internal view returns (address[] memory route) {
        route = new address[](2);
        route[0] = buying ? wrappedNative : asset;
        route[1] = buying ? asset : wrappedNative;
    }
}
