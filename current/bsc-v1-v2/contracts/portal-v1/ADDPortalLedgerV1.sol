// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDPortalAccessV1.sol";
import "./ADDPortalQuoterV1.sol";
import "./IADDPortalV1.sol";
import "../openzeppelin/SafeERC20.sol";
import "../openzeppelin/ReentrancyGuard.sol";

/// @title Variable-inventory, multi-asset fixed-price ledger for candidate Portal v1.
/// @notice Each admission snapshots actual UNENCUMBERED token inventory once.
///         Subsequent donations never alter price, inventory allocation, or progress.
/// @dev Owner withdrawals are surplus-only, including during active fundraising.
///      There is deliberately NO emergency path capable of withdrawing backing.
abstract contract ADDPortalLedgerV1 is ADDPortalAccessV1, ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;
    uint256 public constant DEPLOYMENT_VERSION = 1;
    uint256 public constant DEFAULT_TARGET_BNB = 4 ether;
    uint256 public constant MIN_TARGET_BNB = 1 ether;
    address public constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Append states to preserve the original public numeric values (Graduated=3).
    enum Phase { Unlisted, Active, Migrating, Graduated, GraduationFailed, RefundOnly, Refunded }
    struct Pool {
        address factory; // Zero for an explicit owner listing of an external token.
        address creator;
        address quoteAsset;
        address pair;
        uint256 initialInventory;
        uint256 saleAllocation;
        uint256 liquidityAllocation;
        uint256 sold;
        uint256 reserve; // Quote-asset units, NOT necessarily BNB wei.
        uint256 targetBNB;
        uint256 quoteTarget;
        uint8 quoteDecimals;
        bool customTarget;
        bool lifecycleHooks;
        Phase phase;
    }
    struct BuyQuote {
        uint256 tokens;
        uint256 principal; // Quote-asset contribution.
        uint256 nativeUsed; // BNB consumed to acquire principal, excluding ADD fee.
        uint256 fee;
        uint256 refund;
    }

    ADDPortalQuoterV1 public immutable quoteHelper;
    address public immutable router;
    address public immutable dexFactory;
    address public immutable wrappedNative;
    address public feeRecipient;
    bool public customTargetsEnabled;
    /// @notice Separate owner opt-in. Solidity initializes this to false regardless
    ///         of the constructor's custom-target setting. Never gates existing pools.
    bool public externalDepositsEnabled;
    mapping(address => Pool) internal pools;
    uint256 public totalNativeReserved;
    // Aggregate obligations in EACH ERC20, including both launch inventory AND
    // reserves of OTHER pools using that ERC20 as their quote asset. Never subtract
    // only one role when listing an external token or recovering a surplus.
    mapping(address => uint256) public protectedERC20;

    error InvalidAdmission();
    error AlreadyListed();
    error UnexpectedInventory();
    error InvalidTarget();
    error CustomTargetsClosed();
    error ExternalDepositsClosed();
    error QuoteChanged();
    error UnsupportedAsset();
    error PoolAlreadyInitialized();
    error InvalidPair();
    error PoolNotActive();
    error TradeExpired();
    error InvalidAmount();
    error SlippageExceeded();
    error UnsupportedTransfer();
    error InsufficientBacking();
    error InsufficientSurplus();
    error NativeTransferFailed();
    error InvalidRecipient();
    error OnlySelf();

    event PoolRegistered(address indexed token,address indexed factory,address indexed creator,address quoteAsset,
        address pair,uint256 inventory,uint256 saleAllocation,uint256 liquidityAllocation,uint256 targetBNB,uint256 quoteTarget,bool customTarget,string metadataURI);
    event Buy(address indexed token,address indexed buyer,uint256 payment,uint256 tokens,uint256 quotePrincipal,uint256 nativePrincipal,uint256 fee,uint256 refund);
    event Sell(address indexed token,address indexed seller,uint256 tokens,uint256 quotePrincipal,uint256 nativeGross,uint256 fee,uint256 nativeNet);
    event CustomTargetsEnabled(bool enabled);
    event ExternalDepositsEnabled(bool enabled);
    event ExternalDepositListed(address indexed token,address indexed caller,uint256 inventory);
    event FeeRecipientChanged(address indexed previousRecipient,address indexed newRecipient);
    event SurplusWithdrawn(address indexed asset,address indexed recipient,uint256 requestedAmount);

    constructor(address initialOwner,address router_,address feeRecipient_,bool customEnabled)
        ADDPortalAccessV1(initialOwner)
    {
        if (router_.code.length == 0) revert UnsupportedAsset();
        address dex = IADDV2RouterV1(router_).factory();
        address wrapped = IADDV2RouterV1(router_).WETH();
        if (dex.code.length == 0 || wrapped.code.length == 0) revert UnsupportedAsset();
        router = router_;
        quoteHelper = new ADDPortalQuoterV1(router_);
        dexFactory = dex;
        wrappedNative = wrapped;
        _validRecipient(feeRecipient_);
        feeRecipient = feeRecipient_;
        customTargetsEnabled = customEnabled;
    }

    /// @notice Direct BNB deposits are unassigned surplus, never a buy or reserve top-up.
    /// @dev Router conversion proceeds also arrive here; the caller's guarded swap
    ///      accounts only for its observed delta, not the Portal's aggregate balance.
    receive() external payable {}

    function getPool(address token) external view returns (Pool memory) { return pools[token]; }

    function setCustomTargetsEnabled(bool enabled) external onlyOwner {
        customTargetsEnabled = enabled;
        emit CustomTargetsEnabled(enabled);
    }

    /// @notice Open/close permissionless external deposits. This is an explicit
    ///         exception to factory-only automatic admission; review external tokens
    ///         independently of factory-issued tokens in indexers and website UI.
    function setExternalDepositsEnabled(bool enabled) external onlyOwner {
        externalDepositsEnabled = enabled;
        emit ExternalDepositsEnabled(enabled);
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        _validRecipient(recipient);
        emit FeeRecipientChanged(feeRecipient, recipient);
        feeRecipient = recipient;
    }

    function _validateFactory(address factory) internal view override {
        if (IADDTokenFactoryV1(factory).portal() != address(this)
            || IADDTokenFactoryV1(factory).portalFactoryVersion() != 1) revert InvalidFactory();
    }

    /// @notice Called by an approved factory after creation and the token deposit.
    /// @dev Existing v13 factories do NOT implement this admission interface and
    ///      cannot be silently attached. New factory creation must be atomic.
    function registerFactoryToken(ADDAdmissionV1 calldata a) external nonReentrant {
        _requireFactory(msg.sender);
        if (!IADDTokenFactoryV1(msg.sender).isCreatedToken(a.token)
            || IADDTokenFactoryV1(msg.sender).creatorOf(a.token) != a.creator) revert InvalidAdmission();
        _admit(a, msg.sender, true);
    }

    /// @notice Owner explicitly starts a sale for already-deposited external tokens.
    /// @dev Merely transferring an ERC20 does not authorize it. The expected balance
    ///      binds this transaction to the owner's review and defeats donation-based
    ///      silent repricing before inclusion. No optional token hooks are trusted here.
    function registerExternalToken(ADDAdmissionV1 calldata a) external onlyOwner nonReentrant {
        if (a.lifecycleHooks) revert InvalidAdmission();
        _admit(a, address(0), true);
    }

    /// @notice Once explicitly opened by the owner, an external contract or wallet
    ///      may approve, deposit its own tokens, and start a sale atomically. No
    ///      prior factory allowlisting or second owner transaction is required.
    /// @dev Never adopts pre-existing unsolicited deposits or another pool's quote
    ///      reserves. Only the exact newly received amount forms this pool's 50/50
    ///      inventory. Standard/custom targets and all transfer checks still apply.
    function depositAndRegisterExternalToken(ADDExternalLaunchV1 calldata a) external nonReentrant {
        if (!externalDepositsEnabled) revert ExternalDepositsClosed();
        if (block.timestamp > a.deadline) revert TradeExpired();
        if (a.token.code.length == 0 || a.amount < 2) revert InvalidAdmission();
        if (pools[a.token].phase != Phase.Unlisted) revert AlreadyListed();
        if (IERC20Minimal(a.token).balanceOf(address(this)) < protectedERC20[a.token]) revert InsufficientBacking();
        _exactPull(a.token,msg.sender,a.amount);
        _admit(ADDAdmissionV1(a.token,msg.sender,a.quoteAsset,a.amount,a.targetBNB,a.quoteTarget,
            a.deadline,a.customTarget,false,a.metadataURI),address(0),false);
        emit ExternalDepositListed(a.token,msg.sender,a.amount);
    }

    function _admit(ADDAdmissionV1 memory a,address originFactory,bool useAllUnencumbered) internal {
        if (block.timestamp > a.deadline) revert TradeExpired();
        if (a.token.code.length == 0 || a.token == wrappedNative || a.token == a.quoteAsset
            || a.creator == address(0) || a.tokenDeposit < 2 || bytes(a.metadataURI).length > 2048) revert InvalidAdmission();
        if (pools[a.token].phase != Phase.Unlisted) revert AlreadyListed();
        if (a.customTarget) { if (!customTargetsEnabled) revert CustomTargetsClosed(); }
        else if (a.targetBNB != DEFAULT_TARGET_BNB) revert InvalidTarget();
        (uint256 target,uint8 decimals_) = quoteGraduationTarget(a.quoteAsset,a.targetBNB);
        if (target != a.quoteTarget) revert QuoteChanged();
        uint256 available = availableTokenSurplus(a.token);
        if (available < a.tokenDeposit || (useAllUnencumbered && available != a.tokenDeposit)) revert UnexpectedInventory();
        uint256 half = a.tokenDeposit / 2;
        // V2 reserves are uint112. These are protocol arithmetic limits, not a
        // configurable business cap. Reject impossible migrations at admission.
        if (half > type(uint112).max || target > type(uint112).max) revert InvalidAmount();
        address pairAsset = a.quoteAsset == address(0) ? wrappedNative : a.quoteAsset;
        address pair = IADDV2FactoryV1(dexFactory).getPair(a.token,pairAsset);
        if (pair == address(0)) pair = IADDV2FactoryV1(dexFactory).createPair(a.token,pairAsset);
        _checkPair(pair,a.token,pairAsset);
        if (IADDV2PairV1(pair).totalSupply() != 0) revert PoolAlreadyInitialized();
        pools[a.token] = Pool(originFactory,a.creator,a.quoteAsset,pair,a.tokenDeposit,half,half,0,0,
            a.targetBNB,target,decimals_,a.customTarget,a.lifecycleHooks,Phase.Active);
        // For odd deposits, one indivisible base unit is surplus; both halves are equal.
        protectedERC20[a.token] += 2 * half;
        if (a.lifecycleHooks) {
            if (IADDPortalTokenHooksV1(a.token).portal() != address(this)
                || IADDPortalTokenHooksV1(a.token).portalTokenVersion() != 1) revert InvalidAdmission();
            IADDPortalTokenHooksV1(a.token).onPortalAdmission(pair);
        }
        _assertPoolBacking(a.token);
        emit PoolRegistered(a.token,originFactory,a.creator,a.quoteAsset,pair,a.tokenDeposit,half,half,
            a.targetBNB,target,a.customTarget,a.metadataURI);
    }

    /// @notice Convert a BNB reference target to a fixed, whole quote-asset target.
    /// @dev The caller signs the returned value into admission. Current pool quotes
    ///      are NOT an oracle for economic value and remain subject to DEX movement.
    function quoteGraduationTarget(address asset,uint256 targetBNB) public view returns (uint256 target,uint8 decimals_) {
        return quoteHelper.quoteGraduationTarget(asset,targetBNB);
    }

    function _validateQuote(address asset) internal view returns (uint8) {
        return quoteHelper.validateQuoteAsset(asset);
    }

    function quoteBuy(address token,uint256 payment) public view returns (BuyQuote memory q) {
        Pool storage p = pools[token];
        if (p.phase != Phase.Active) revert PoolNotActive();
        (q.tokens,q.principal,q.nativeUsed,q.fee,q.refund) = quoteHelper.quoteBuy(
            payment,p.saleAllocation-p.sold,p.saleAllocation,p.quoteTarget,p.quoteAsset);
    }

    function quoteSell(address token,uint256 amount) public view returns (uint256 principal,uint256 gross,uint256 fee,uint256 net) {
        Pool storage p = pools[token];
        if (p.phase != Phase.Active) revert PoolNotActive();
        if (amount == 0 || amount > p.sold) revert InvalidAmount();
        return quoteHelper.quoteSell(amount,p.saleAllocation,p.quoteTarget,p.quoteAsset);
    }

    function availableNativeSurplus() public view returns (uint256) {
        return address(this).balance > totalNativeReserved ? address(this).balance - totalNativeReserved : 0;
    }
    function availableTokenSurplus(address token) public view returns (uint256) {
        uint256 balance = IERC20Minimal(token).balanceOf(address(this));
        return balance > protectedERC20[token] ? balance - protectedERC20[token] : 0;
    }
    function withdrawBNB(address payable recipient,uint256 amount) external onlyOwner nonReentrant {
        _validRecipient(recipient);
        if (amount == 0 || amount > availableNativeSurplus()) revert InsufficientSurplus();
        _send(recipient,amount);
        if (address(this).balance < totalNativeReserved) revert InsufficientBacking();
        emit SurplusWithdrawn(address(0),recipient,amount);
    }
    /// @dev Recovery of an unknown token need not guarantee the recipient's exact
    ///      net amount, but even a transfer fee cannot consume protected inventory.
    function withdrawToken(address token,address recipient,uint256 amount) external onlyOwner nonReentrant {
        _validRecipient(recipient);
        if (amount == 0 || amount > availableTokenSurplus(token)) revert InsufficientSurplus();
        IERC20Minimal(token).safeTransfer(recipient,amount);
        if (IERC20Minimal(token).balanceOf(address(this)) < protectedERC20[token]) revert InsufficientBacking();
        emit SurplusWithdrawn(token,recipient,amount);
    }

    function _assertPoolBacking(address token) internal view {
        this.assertPoolBacking(token);
    }
    /// @notice Read-only coverage check shared by every guarded settlement flow.
    function assertPoolBacking(address token) external view {
        if (address(this).balance < totalNativeReserved
            || IERC20Minimal(token).balanceOf(address(this)) < protectedERC20[token]) revert InsufficientBacking();
        address asset = pools[token].quoteAsset;
        if (asset != address(0) && IERC20Minimal(asset).balanceOf(address(this)) < protectedERC20[asset]) revert InsufficientBacking();
    }
    function _checkPair(address pair,address a,address b) internal view {
        if (pair.code.length == 0) revert InvalidPair();
        address t0 = IADDV2PairV1(pair).token0();
        address t1 = IADDV2PairV1(pair).token1();
        if (!((t0 == a && t1 == b) || (t0 == b && t1 == a))) revert InvalidPair();
    }
    function _path(address asset,bool buying) internal view returns (address[] memory route) {
        route = new address[](2);
        route[0] = buying ? wrappedNative : asset;
        route[1] = buying ? asset : wrappedNative;
    }
    function _approve(address asset,uint256 amount) internal {
        this.executeApproval(asset,router,amount);
    }
    /// @dev Self-only primitives execute inside a nonReentrant outer operation.
    ///      The shared bodies avoid duplicating token-call validation in runtime code.
    function executeApproval(address asset,address spender,uint256 amount) external {
        if (msg.sender != address(this)) revert OnlySelf();
        IERC20Minimal(asset).safeApprove(spender,0);
        if (amount != 0) IERC20Minimal(asset).safeApprove(spender,amount);
    }
    function _exactTransfer(address asset,address recipient,uint256 amount) internal {
        this.executeExactTransfer(asset,recipient,amount);
    }
    function executeExactTransfer(address asset,address recipient,uint256 amount) external {
        if (msg.sender != address(this)) revert OnlySelf();
        uint256 fromBefore = IERC20Minimal(asset).balanceOf(address(this));
        uint256 toBefore = IERC20Minimal(asset).balanceOf(recipient);
        IERC20Minimal(asset).safeTransfer(recipient,amount);
        if (IERC20Minimal(asset).balanceOf(address(this)) + amount != fromBefore
            || IERC20Minimal(asset).balanceOf(recipient) != toBefore + amount) revert UnsupportedTransfer();
    }
    function _exactPull(address asset,address sender,uint256 amount) internal {
        this.executeExactPull(asset,sender,amount);
    }
    function executeExactPull(address asset,address sender,uint256 amount) external {
        if (msg.sender != address(this)) revert OnlySelf();
        uint256 beforeBalance = IERC20Minimal(asset).balanceOf(address(this));
        IERC20Minimal(asset).safeTransferFrom(sender,address(this),amount);
        if (IERC20Minimal(asset).balanceOf(address(this)) != beforeBalance + amount) revert UnsupportedTransfer();
    }
    function _send(address recipient,uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = payable(recipient).call{value:amount}("");
        if (!ok) revert NativeTransferFailed();
    }
    function _validRecipient(address recipient) internal view {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
    }
}
