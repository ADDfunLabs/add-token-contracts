// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDPortalLiquidityV1.sol";
import "./ADDPortalConversionV1.sol";

/// @notice Owner-directed recovery of a paused, failed graduation. No funds can
///         be sent to the owner: settlement is either burned LP or holder refunds.
/// @dev The owner chooses the replacement quote asset and signs its output quote.
///      This is a meaningful trust assumption. A 5% execution tolerance is NOT an
///      oracle or a guarantee of economic value for an arbitrary ERC20. Review the
///      asset and its liquidity independently; ordinary spot quotes can be manipulated.
abstract contract ADDPortalRecoveryV1 is ADDPortalLiquidityV1 {
    using SafeERC20 for IERC20Minimal;
    uint256 public constant RECOVERY_SLIPPAGE_BPS = 500;
    // Original unsold sale allocation + LP allocation stay protected during refunds.
    mapping(address => uint256) public refundInventory;

    error NotFailedGraduation();
    error InvalidRecoveryAsset();
    error RecoveryQuoteChanged();
    error RefundsNotEnabled();
    error OnlyRecoveryConverter();

    event AlternativeGraduation(address indexed token,address indexed oldQuoteAsset,
        address indexed newQuoteAsset,address pair,uint256 amountIn,uint256 amountOut,uint256 minimumOut);
    event RefundsEnabled(address indexed token,address indexed quoteAsset,uint256 tokensOutstanding,uint256 reserve);
    event Refunded(address indexed token,address indexed holder,address quoteAsset,uint256 tokensReturned,uint256 assetsReturned);
    event RefundsCompleted(address indexed token,uint256 unissuedTokensBurned);

    constructor(address owner_,address router_,address feeRecipient_,bool customEnabled)
        ADDPortalLiquidityV1(owner_,router_,feeRecipient_,customEnabled) {}

    /// @notice Preview a full-reserve exact-input conversion using the fixed router.
    ///         Zero replacement address means BNB/WBNB settlement. The signed amountIn
    ///         binds the owner transaction to the reviewed project reserve.
    function quoteAlternativeGraduation(address token,address newQuoteAsset) public view
        returns (uint256 amountIn,uint256 expectedOut,uint256 minimumOut,address[] memory path)
    {
        _requireFailed(token);
        Pool storage p = pools[token];
        if (newQuoteAsset == p.quoteAsset || newQuoteAsset == token || newQuoteAsset == wrappedNative)
            revert InvalidRecoveryAsset();
        if (newQuoteAsset != address(0)) _validateQuote(newQuoteAsset);
        amountIn = p.reserve;
        (expectedOut,minimumOut,path) = recoveryConverter.quote(p.quoteAsset,newQuoteAsset,amountIn);
    }

    /// @notice Spend only this failed project's ENTIRE reserve, receive the chosen
    ///         asset, then pair ALL actual output with the original LP token half.
    ///         No additional ADD platform fee. Router fees and price impact apply.
    /// @param quotedOut Output reviewed off-chain and signed by the owner. Never zero.
    /// @dev The effective minimum is the stricter of 95% of the signed quote and
    ///      95% of the current router quote. Raising slippage above 5% is impossible.
    ///      All conversion, hooks, bookkeeping and LP minting share one transaction:
    ///      ANY failure restores the original asset/reserve, approval and paused state.
    function graduateWithAlternativeAsset(address token,address newQuoteAsset,
        uint256 expectedReserve,uint256 quotedOut,uint256 deadline) external onlyOwner nonReentrant
    {
        if (block.timestamp > deadline) revert TradeExpired();
        if (quotedOut == 0) revert InvalidAmount();
        _requireFailed(token);
        if (pools[token].reserve != expectedReserve) revert RecoveryQuoteChanged();
        (uint256 received,uint256 minimumOut) = recoveryConverter.graduateAlternative(token,newQuoteAsset,expectedReserve,quotedOut,deadline);
        Pool storage p = pools[token];
        emit AlternativeGraduation(token,p.quoteAsset,newQuoteAsset,p.pair,expectedReserve,received,minimumOut);
    }

    /// @dev Fixed helper callback within the owner entry's reentrancy lock.
    ///      Verify the proposed pair belongs to the immutable factory, then release
    ///      only this project's reserve and approve exactly that amount to the helper.
    function executeRecoveryStart(address token,address pair,uint256 reserve) external {
        if (msg.sender != address(recoveryConverter)) revert OnlyRecoveryConverter();
        _requireFailed(token);
        if (pools[token].reserve != reserve) revert RecoveryQuoteChanged();
        _assertPoolBacking(token);
        Pool storage p = pools[token];
        address oldQuoteAsset = p.quoteAsset;
        address a = IADDV2PairV1(pair).token0();
        address b = IADDV2PairV1(pair).token1();
        address outputAsset = a == token ? b : a;
        if (IADDV2FactoryV1(dexFactory).getPair(token,outputAsset) != pair) revert InvalidPair();
        _requireEmptyPair(pair,token,outputAsset);
        _beginGraduation(token,pair);
        if (oldQuoteAsset == address(0)) _wrapNative(reserve);
        address input = oldQuoteAsset == address(0) ? wrappedNative : oldQuoteAsset;
        this.executeApproval(input,address(recoveryConverter),reserve);
    }

    function executeRecoveryFinish(address token,address newQuoteAsset,uint256 received) external {
        if (msg.sender != address(recoveryConverter)) revert OnlyRecoveryConverter();
        Pool storage p = pools[token];
        if (p.phase != Phase.Migrating) revert NotFailedGraduation();
        address input = p.quoteAsset == address(0) ? wrappedNative : p.quoteAsset;
        this.executeApproval(input,address(recoveryConverter),0);
        if (IERC20Minimal(input).balanceOf(address(this)) < protectedERC20[input]) revert InsufficientBacking();
        _supplyLiquidity(token,newQuoteAsset,received);
    }

    function _requireFailed(address token) internal view {
        if (pools[token].phase != Phase.GraduationFailed || !canGraduate(token)) revert NotFailedGraduation();
    }

    /// @notice Irreversibly abandon graduation and allow holder-initiated refunds.
    ///         Owner cannot choose refund recipients, withdraw backing, resume sales,
    ///         or switch assets after this decision. Owner action is required; there
    ///         is no automatic timeout, so availability depends on owner cooperation.
    function enableRefunds(address token) external onlyOwner nonReentrant {
        _requireFailed(token);
        _assertPoolBacking(token);
        Pool storage p = pools[token];
        refundInventory[token] = p.saleAllocation + p.liquidityAllocation - p.sold;
        p.phase = Phase.RefundOnly;
        if (p.lifecycleHooks) IADDPortalTokenHooksV1(token).onPortalRefundStart();
        emit RefundsEnabled(token,p.quoteAsset,p.sold,p.reserve);
    }

    /// @notice Pro-rata ORIGINAL quote-asset units, not a new BNB conversion.
    ///         Past trading fees are not refundable; no new fee is charged. The
    ///         last outstanding claim receives rounding dust so no reserve is stranded.
    function quoteRefund(address token,uint256 amount) public view returns (uint256 assets) {
        Pool storage p = pools[token];
        if (p.phase != Phase.RefundOnly) revert RefundsNotEnabled();
        if (amount == 0 || amount > p.sold) revert InvalidAmount();
        assets = amount == p.sold ? p.reserve : FullMath.mulDiv(p.reserve,amount,p.sold);
        if (assets == 0) revert InvalidAmount();
    }

    /// @notice Holder approves and returns fungible tokens, receiving their share
    ///         directly. Returned tokens go to dead to prevent repeat claims. This
    ///         is not a historical-wallet reimbursement: a transferee can redeem.
    function refund(address token,uint256 amount,uint256 minimumAssets,uint256 deadline)
        external nonReentrant returns (uint256 assets)
    {
        if (block.timestamp > deadline) revert TradeExpired();
        _assertPoolBacking(token);
        assets = quoteRefund(token,amount);
        if (assets < minimumAssets) revert SlippageExceeded();
        Pool storage p = pools[token];
        p.sold -= amount;
        p.reserve -= assets;
        if (p.quoteAsset == address(0)) totalNativeReserved -= assets;
        else protectedERC20[p.quoteAsset] -= assets;
        _exactPull(token,msg.sender,amount);
        _exactTransfer(token,LP_BURN_ADDRESS,amount);
        if (p.quoteAsset == address(0)) _send(msg.sender,assets);
        else _exactTransfer(p.quoteAsset,msg.sender,assets);
        emit Refunded(token,msg.sender,p.quoteAsset,amount,assets);
        if (p.sold == 0) {
            uint256 inventory = refundInventory[token];
            refundInventory[token] = 0;
            p.phase = Phase.Refunded;
            protectedERC20[token] -= inventory;
            // Unissued project inventory cannot be recirculated by the owner during
            // refunds. Dispose of it only when all outstanding claims are settled.
            if (inventory != 0) _exactTransfer(token,LP_BURN_ADDRESS,inventory);
            if (p.lifecycleHooks) IADDPortalTokenHooksV1(token).onPortalRefundComplete();
            emit RefundsCompleted(token,inventory);
        }
        _assertPoolBacking(token);
    }
}
