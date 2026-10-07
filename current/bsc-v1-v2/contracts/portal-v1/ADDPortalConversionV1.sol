// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./IADDPortalV1.sol";
import "../FullMath.sol";
import "../openzeppelin/SafeERC20.sol";

interface IADDRecoveryHostV1 {
    function quoteAlternativeGraduation(address token,address asset) external view returns (uint256,uint256,uint256,address[] memory);
    function executeRecoveryStart(address token,address pair,uint256 reserve) external;
    function executeRecoveryFinish(address token,address asset,uint256 received) external;
    function protectedERC20(address asset) external view returns (uint256);
}

/// @notice Fixed, non-upgradeable conversion helper deployed by one Portal.
/// @dev No owner, arbitrary spender/recipient, delegatecall, or asset-withdrawal
///      method. Only its immutable Portal can convert; output always returns there.
///      Separating this implementation keeps Portal below the EIP-170 code limit.
contract ADDPortalConversionV1 {
    using SafeERC20 for IERC20Minimal;
    address public immutable portal;
    address public immutable router;
    address public immutable wrappedNative;
    uint256 public constant SLIPPAGE_BPS = 500;
    error InvalidConversion();
    error InvalidTransfer();
    error InvalidLiquidity();
    error PoolAlreadyInitialized();

    function assertEmptyPair(address token,address asset,address pair) external view {
        if (pair.code.length == 0 || IADDV2FactoryV1(IADDV2RouterV1(router).factory()).getPair(token,asset) != pair)
            revert InvalidLiquidity();
        if (IADDV2PairV1(pair).totalSupply() != 0) revert PoolAlreadyInitialized();
    }

    /// @notice Direct, first-liquidity mint on behalf of the immutable Portal.
    /// @dev Pulls exactly approved amounts straight into the canonical pair. Checks
    ///      balances, reserves and LP recipient; donations/sync without LP are allowed.
    function mintLiquidity(address token,address asset,address pair,uint256 tokenAmount,uint256 quoteAmount)
        external returns (uint256 liquidity)
    {
        if (msg.sender != portal) revert InvalidConversion();
        if (IADDV2FactoryV1(IADDV2RouterV1(router).factory()).getPair(token,asset) != pair) revert InvalidLiquidity();
        IADDV2PairV1 market = IADDV2PairV1(pair);
        if (market.totalSupply() != 0) revert PoolAlreadyInitialized();
        uint256 t = IERC20Minimal(token).balanceOf(pair);
        uint256 q = IERC20Minimal(asset).balanceOf(pair);
        if (quoteAmount == 0 || tokenAmount > type(uint112).max || quoteAmount > type(uint112).max
            || t > type(uint112).max-tokenAmount || q > type(uint112).max-quoteAmount) revert InvalidLiquidity();
        uint256 portalT = IERC20Minimal(token).balanceOf(portal);
        uint256 portalQ = IERC20Minimal(asset).balanceOf(portal);
        IERC20Minimal(asset).safeTransferFrom(portal,pair,quoteAmount);
        IERC20Minimal(token).safeTransferFrom(portal,pair,tokenAmount);
        address dead = 0x000000000000000000000000000000000000dEaD;
        uint256 lpBefore = market.balanceOf(dead);
        liquidity = market.mint(dead);
        if (liquidity == 0 || market.balanceOf(dead) != lpBefore+liquidity
            || IERC20Minimal(token).balanceOf(pair) != t+tokenAmount || IERC20Minimal(asset).balanceOf(pair) != q+quoteAmount
            || IERC20Minimal(token).balanceOf(portal)+tokenAmount != portalT
            || IERC20Minimal(asset).balanceOf(portal)+quoteAmount != portalQ) revert InvalidLiquidity();
        (uint112 r0,uint112 r1,) = market.getReserves();
        bool first = market.token0() == token;
        if (uint256(first?r0:r1) != t+tokenAmount || uint256(first?r1:r0) != q+quoteAmount) revert InvalidLiquidity();
    }

    constructor(address router_) {
        portal = msg.sender;
        router = router_;
        wrappedNative = IADDV2RouterV1(router_).WETH();
    }

    function minimumOut(uint256 quoted) public pure returns (uint256) {
        return FullMath.mulDivUp(quoted,9500,10000);
    }

    function quote(address from,address to,uint256 amount) public view
        returns (uint256 expected,uint256 minimum,address[] memory path)
    {
        from = from == address(0) ? wrappedNative : from;
        to = to == address(0) ? wrappedNative : to;
        if (from == to || amount == 0) revert InvalidConversion();
        path = new address[](from == wrappedNative || to == wrappedNative ? 2 : 3);
        path[0] = from;
        if (path.length == 3) path[1] = wrappedNative;
        path[path.length-1] = to;
        uint256[] memory amounts = IADDV2RouterV1(router).getAmountsOut(amount,path);
        if (amounts.length != path.length || amounts[0] != amount) revert InvalidConversion();
        expected = amounts[amounts.length-1];
        if (expected == 0) revert InvalidConversion();
        minimum = minimumOut(expected);
    }

    /// @dev Portal wraps BNB before approving this helper. Exact balance deltas on
    ///      BOTH custody transfers and output reject taxed/rebasing assets. Any
    ///      unrelated helper dust is preserved. Approvals are cleared on success
    ///      and restored by transaction rollback on failure.
    function convert(address from,address to,uint256 amount,uint256 signedMinimum,uint256 deadline)
        external returns (uint256 received,uint256 effectiveMinimum)
    {
        if (msg.sender != portal || signedMinimum == 0 || block.timestamp > deadline) revert InvalidConversion();
        return _convert(from,to,amount,signedMinimum,deadline);
    }

    /// @dev The Portal's owner-only, nonReentrant entry is the sole caller. Host
    ///      callbacks accept only this immutable engine. No user-selectable host,
    ///      router, spender, recipient, or arbitrary external call exists.
    function graduateAlternative(address token,address newAsset,uint256 expectedReserve,uint256 signedQuote,uint256 deadline)
        external returns (uint256 received,uint256 effectiveMinimum)
    {
        if (msg.sender != portal || signedQuote == 0 || block.timestamp > deadline) revert InvalidConversion();
        IADDRecoveryHostV1 host = IADDRecoveryHostV1(portal);
        (uint256 reserve,,uint256 minimum,address[] memory path) = host.quoteAlternativeGraduation(token,newAsset);
        if (reserve != expectedReserve) revert InvalidConversion();
        uint256 signedMinimum = minimumOut(signedQuote);
        if (signedMinimum > minimum) minimum = signedMinimum;
        address factory = IADDV2RouterV1(router).factory();
        address output = path[path.length-1];
        address pair = IADDV2FactoryV1(factory).getPair(token,output);
        if (pair == address(0)) pair = IADDV2FactoryV1(factory).createPair(token,output);
        uint256 outputBefore = IERC20Minimal(output).balanceOf(portal);
        if (outputBefore < host.protectedERC20(output)) revert InvalidTransfer();
        host.executeRecoveryStart(token,pair,reserve);
        (received,effectiveMinimum) = _convert(path[0],output,reserve,minimum,deadline);
        host.executeRecoveryFinish(token,newAsset,received);
        if (IERC20Minimal(output).balanceOf(portal) != outputBefore) revert InvalidTransfer();
    }

    function _convert(address from,address to,uint256 amount,uint256 signedMinimum,uint256 deadline)
        internal returns (uint256 received,uint256 effectiveMinimum)
    {
        (,uint256 currentMinimum,address[] memory path) = quote(from,to,amount);
        effectiveMinimum = signedMinimum > currentMinimum ? signedMinimum : currentMinimum;
        IERC20Minimal input = IERC20Minimal(path[0]);
        IERC20Minimal output = IERC20Minimal(path[path.length-1]);
        uint256 inputBefore = input.balanceOf(address(this));
        uint256 portalBefore = input.balanceOf(portal);
        uint256 outputBefore = output.balanceOf(portal);
        input.safeTransferFrom(portal,address(this),amount);
        if (input.balanceOf(address(this)) != inputBefore + amount || input.balanceOf(portal) + amount != portalBefore)
            revert InvalidTransfer();
        input.safeApprove(router,0);
        input.safeApprove(router,amount);
        uint256[] memory amounts = IADDV2RouterV1(router).swapExactTokensForTokens(amount,effectiveMinimum,path,portal,deadline);
        input.safeApprove(router,0);
        received = output.balanceOf(portal) - outputBefore;
        if (received < effectiveMinimum || amounts.length != path.length || amounts[0] != amount
            || amounts[amounts.length-1] != received || input.balanceOf(address(this)) != inputBefore
            || input.balanceOf(portal) + amount != portalBefore) revert InvalidTransfer();
    }
}
