// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../openzeppelin/ERC20.sol";
import "../tax/ADDTaxPriceGuard.sol";
import "../portal-v1/IADDPortalV1.sol";
import "./ADDClaimDividendV1.sol";
import "./ADDTaxSwapReceiverV1.sol";

/// @title ADD 自动税收代币 / post-graduation tax token, candidate V1
/// @notice 营销、销毁、自动加池均在本合约；仅启用分红时绑定独立领取合约。
/// @dev New Portal V1 only, not the historical v13 ABI. No owner, tax setter, mint,
///      sweep or upgrade entry. Graduation/refund hooks can ONLY come from bound Portal.
///      Buy/sell means transfers involving verified pairs of the configured V2 factory;
///      manual liquidity adds/removes cannot reliably be distinguished from swaps.
contract ADDAutoTaxTokenV1 is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;
    using ADDTaxPriceGuard for ADDTaxPriceGuard.State;
    enum RewardMode { Native, Token, Self }
    enum Phase { AwaitingAdmission, Active, Migrating, Graduated, RefundOnly, Refunded }
    struct Config {
        uint16 buyTaxBps; uint16 sellTaxBps;
        uint16 marketingBps; uint16 burnBps; uint16 dividendBps; uint16 liquidityBps;
        address marketingWallet;
        RewardMode rewardMode; address rewardToken; uint256 minimumHolding;
    }

    error OnlyPortal();
    error OnlyAutomaticStage();
    error PoolTransfersLocked();
    error TokenInitializationForbidden();
    error InvalidLaunch();
    error InvalidMetadata();
    error InvalidIntegerTax();
    error InvalidAllocation();
    error InvalidMarketingWallet();
    error InvalidRewardAsset();
    error InvalidDividendConfig();
    error UnexpectedDividendLedger();
    error InvalidDEX();
    error WrongDividendBinding();
    error InvalidAdmissionPhase();
    error InvalidMigrationPhase();
    error InvalidGraduationPhase();
    error InvalidRefundPhase();
    error InvalidRefundCompletion();
    error InvalidPair();
    error WrongPairToken();
    error WrongPairFactory();
    error PoolCannotReceiveMarketing();
    error MintForbidden();
    error InvalidTransfer();
    error UsePortalToSell();
    error NotAdmitted();
    error MigrationTransferOnly();
    error NestedTaxTransfer();
    error TaxTradeGasLimitTooLow();
    error NotGraduated();
    error TaxProcessingGasLimitTooLow();
    error EmptySplit();
    error SwapNeedsMinimum();
    error UnexpectedSwapDebit();
    error InsufficientSwapOutput();
    error RoundedSwapCapacity();
    error InvalidRewardFunding();
    error LPAmountTooSmall();
    error InvalidLPConsumption();
    error LPNotBurned();
    error NotNativeQuote();
    error MarketingNativeRejected();
    error UnexpectedMarketingDebit();
    error OnlyWrappedNative();

    address public immutable initializationFactory;
    address public constant DEAD = address(0xdead);
    uint256 public constant AUTO_CALL_GAS = 3_200_000;
    uint256 private constant TRADE_GAS_RESERVE = 300_000;
    bool private initialized;
    bool private minted;
    bool public automaticProcessing;
    address public portal;
    address public router;
    address public dexFactory;
    address public wrappedNative;
    address public pair;
    address public quoteToken;
    address public dividend;
    address public swapReceiver;
    address public rewardAsset;
    uint256 public initialSupply;
    uint256 public graduatedAt;
    uint256 public maximumProcessAmount;
    Phase public phase;
    Config public config;
    ADDTaxPriceGuard.State private prices;

    // Separate liabilities: balanceOf(this) includes unsplit tax, retained LP tokens,
    // and self-token dividends. Quote balances must never be recycled as fresh tax.
    uint256 public pendingMarketing;
    uint256 public pendingDividendQuote;
    uint256 public pendingSelfReward;
    uint256 public pendingLPToken;
    uint256 public pendingLPQuote;
    uint256 public totalBurned;
    uint256 public totalLiquidity;

    event PhaseChanged(Phase phase);
    event TradeTax(address indexed from, address indexed to, uint256 amount);
    event TaxProcessed(uint256 tokens, uint256 burned, uint256 quoteReceived);
    event MarketingPaid(address indexed wallet, uint256 amount, bool nativePayment);
    event LiquidityBurned(uint256 tokenAmount, uint256 quoteAmount, uint256 lpAmount);
    event AutomaticStage(bytes4 indexed selector, bool success);
    event AutomaticProcessingDeferred();

    constructor() ERC20("", "") { initializationFactory = msg.sender; initialized = true; }
    modifier onlyPortal() { if (msg.sender != portal) revert OnlyPortal(); _; }
    modifier onlySelf() { if (msg.sender != address(this)) revert OnlyAutomaticStage(); _; }
    function portalTokenVersion() external pure returns (uint256) { return 1; }
    function liquidityAdded() external view returns (bool) { return phase == Phase.Graduated; }

    /// @notice 累计处理门槛从成功毕业时起，每满365天减半；不足一年不减。
    /// @dev Derive from the fixed initial supply, never totalSupply/burned balances.
    ///      Read-only: no keeper transaction, owner setter, or reset on processing.
    ///      Shifts >=256 safely produce zero; clamp to one smallest token unit.
    ///      The per-batch maximumProcessAmount and dividend minimum do not halve.
    function processingThreshold() public view returns (uint256 amount) {
        amount = initialSupply / 100_000;
        uint256 start = graduatedAt;
        // Written once from a successful earlier transaction: start <= block.timestamp.
        if (start != 0) { unchecked { amount >>= (block.timestamp - start) / 365 days; } }
        if (amount == 0) amount = 1;
    }

    /// @notice Parameters are fixed for the life of this token. Amounts use 18 decimals;
    ///         percentages are integer percentages encoded in basis points (1% = 100).
    function initialize(string calldata name_, string calldata symbol_, address portal_, address router_,
        uint256 supply, address dividend_, address receiver_, Config calldata c) external {
        if (!(msg.sender == initializationFactory && !initialized)) revert TokenInitializationForbidden();
        if (!(portal_.code.length > 0 && router_.code.length > 0 && supply >= 2
            && supply / 2 <= type(uint112).max)) revert InvalidLaunch();
        if (!(bytes(name_).length > 0 && bytes(name_).length <= 128
            && bytes(symbol_).length > 0 && bytes(symbol_).length <= 32)) revert InvalidMetadata();
        if (!(c.buyTaxBps <= 1000 && c.sellTaxBps <= 1000 && c.buyTaxBps + c.sellTaxBps > 0
            && c.buyTaxBps % 100 == 0 && c.sellTaxBps % 100 == 0)) revert InvalidIntegerTax();
        if (!(uint256(c.marketingBps) + c.burnBps + c.dividendBps + c.liquidityBps == 10000
            && c.marketingBps % 100 == 0 && c.burnBps % 100 == 0
            && c.dividendBps % 100 == 0 && c.liquidityBps % 100 == 0)) revert InvalidAllocation();
        if (!(c.marketingBps == 0 || (c.marketingWallet != address(0) && c.marketingWallet != DEAD
            && c.marketingWallet != address(this) && c.marketingWallet != portal_
            && c.marketingWallet != router_ && c.marketingWallet != dividend_ && c.marketingWallet != receiver_))) revert InvalidMarketingWallet();
        if (!(c.rewardMode == RewardMode.Token ? c.rewardToken.code.length > 0
            && c.rewardToken != address(this) : c.rewardToken == address(0))) revert InvalidRewardAsset();
        if (c.dividendBps > 0) {
            if (!(dividend_.code.length > 0 && c.minimumHolding >= 10_000 ether
                && c.minimumHolding <= supply)) revert InvalidDividendConfig();
        } else if (!(dividend_ == address(0))) revert UnexpectedDividendLedger();
        initialized = true; portal = portal_; router = router_; initialSupply = supply;
        dexFactory = IADDTaxRouter(router_).factory(); wrappedNative = IADDTaxRouter(router_).WETH();
        if (!(dexFactory.code.length > 0 && wrappedNative.code.length > 0)) revert InvalidDEX();
        dividend = dividend_; config = c;
        swapReceiver = receiver_;
        rewardAsset = c.rewardMode == RewardMode.Native ? wrappedNative
            : c.rewardMode == RewardMode.Self ? address(this) : c.rewardToken;
        if (dividend_ != address(0)) {
            ADDClaimDividendV1 ledger = ADDClaimDividendV1(payable(dividend_));
            if (!(ledger.token() == address(this) && ledger.rewardToken() == rewardAsset
                && ledger.minimumHolding() == c.minimumHolding)) revert WrongDividendBinding();
        }
        // Relative to actual supply, not the retired fixed one-billion supply.
        maximumProcessAmount = supply / 10_000;
        if (maximumProcessAmount == 0) maximumProcessAmount = 1;
        _initializeMetadata(name_, symbol_); _mint(portal_, supply);
    }

    function onPortalAdmission(address pair_) external onlyPortal {
        if (!(phase == Phase.AwaitingAdmission && initialized)) revert InvalidAdmissionPhase();
        _bindPair(pair_); phase = Phase.Active; emit PhaseChanged(phase);
    }
    function onPortalMigrationStart(address pair_) external onlyPortal {
        if (!(phase == Phase.Active)) revert InvalidMigrationPhase();
        // Alternative-asset graduation supplies the actual final pair. Hook and
        // quote binding roll back together if graduation fails.
        _bindPair(pair_); phase = Phase.Migrating; emit PhaseChanged(phase);
    }
    function onPortalGraduation() external onlyPortal {
        if (!(phase == Phase.Migrating)) revert InvalidGraduationPhase();
        graduatedAt = block.timestamp;
        phase = Phase.Graduated; emit PhaseChanged(phase);
        // Warm the automatic price observation after LP reserves are installed.
        _observe(address(this), quoteToken);
    }
    function onPortalRefundStart() external onlyPortal {
        if (!(phase == Phase.Active)) revert InvalidRefundPhase();
        phase = Phase.RefundOnly; emit PhaseChanged(phase);
    }
    function onPortalRefundComplete() external onlyPortal {
        if (!(phase == Phase.RefundOnly)) revert InvalidRefundCompletion();
        phase = Phase.Refunded; emit PhaseChanged(phase);
    }
    function _bindPair(address market) private {
        if (!(market.code.length > 0)) revert InvalidPair();
        address a = _addressGetter(market, abi.encodeWithSignature("token0()"));
        address b = _addressGetter(market, abi.encodeWithSignature("token1()"));
        if (!(a == address(this) || b == address(this))) revert WrongPairToken();
        if (!(_addressGetter(dexFactory, abi.encodeWithSignature("getPair(address,address)", a, b)) == market)) revert WrongPairFactory();
        if (!(config.marketingBps == 0 || config.marketingWallet != market)) revert PoolCannotReceiveMarketing();
        pair = market; quoteToken = a == address(this) ? b : a;
    }
    function _addressGetter(address target, bytes memory input) private view returns (address value) {
        bool ok; uint256 result; uint256 size;
        assembly ("memory-safe") {
            let p := mload(0x40)
            ok := staticcall(20000, target, add(input,32), mload(input), p, 32)
            size := returndatasize()
            result := mload(p)
        }
        if (ok && size == 32 && result <= type(uint160).max) value = address(uint160(result));
    }
    function isTaxPool(address account) public view returns (bool) {
        if (account == pair && account != address(0)) return true;
        if (account.code.length == 0 || account == portal || account == address(this) || account == dividend) return false;
        address a = _addressGetter(account, abi.encodeWithSignature("token0()"));
        address b = _addressGetter(account, abi.encodeWithSignature("token1()"));
        if (a != address(this) && b != address(this)) return false;
        return _addressGetter(dexFactory, abi.encodeWithSignature("getPair(address,address)", a, b)) == account;
    }
    /// @dev Conventional pool detection before graduation is a heuristic, not a
    ///      universal ban on third-party custom contracts or constructor transfers.
    function _restrictedPool(address account) private view returns (bool) {
        if (account == pair && account != address(0)) return true;
        if (account == portal || account.code.length == 0) return false;
        return _addressGetter(account, abi.encodeWithSignature("token0()")) == address(this)
            || _addressGetter(account, abi.encodeWithSignature("token1()")) == address(this);
    }
    function _syncShare(address account) private {
        if (dividend == address(0) || account == address(0)) return;
        bool excluded = account == DEAD || account == address(this) || account == portal
            || account == router || account == dividend || account == swapReceiver || isTaxPool(account);
        ADDClaimDividendV1(payable(dividend)).setShare(account, excluded ? 0 : balanceOf(account));
    }
    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0)) {
            if (!(initialized && !minted && msg.sender == initializationFactory
                && to == portal && amount == initialSupply)) revert MintForbidden(); minted = true;
        } else {
            if (!(to != address(0) && balanceOf(from) >= amount)) revert InvalidTransfer();
            if (!(to != portal || msg.sender == portal)) revert UsePortalToSell();
            if (!(phase != Phase.AwaitingAdmission)) revert NotAdmitted();
            if (phase == Phase.Active || phase == Phase.RefundOnly || phase == Phase.Refunded)
                if (_restrictedPool(from) || _restrictedPool(to)) revert PoolTransfersLocked();
            if (phase == Phase.Migrating) if (!(from == portal && to == pair)) revert MigrationTransferOnly();
            // Native marketing/reward callbacks cannot recursively trade while
            // OLD tax is being processed ahead of the original seller's input.
            if (automaticProcessing) if (!(from == address(this) || from == dividend)) revert NestedTaxTransfer();
        }
        uint256 tax;
        if (from != address(0) && phase == Phase.Graduated && from != address(this)
            && from != dividend && to != address(this) && to != dividend) {
            bool fromPool = isTaxPool(from); bool toPool = isTaxPool(to);
            if (amount > 0 && toPool && !fromPool) _triggerTaxes();
            tax = FullMath.mulDiv(amount, fromPool ? config.buyTaxBps : toPool ? config.sellTaxBps : 0, 10000);
        }
        if (tax > 0) { super._update(from, address(this), tax); emit TradeTax(from, to, tax); }
        super._update(from, to, amount-tax);
        _syncShare(from); if (to != from) _syncShare(to);
    }
    function unprocessedTokens() public view returns (uint256) {
        return balanceOf(address(this)) - pendingLPToken - pendingSelfReward;
    }
    function _triggerTaxes() private {
        if (unprocessedTokens() == 0 && pendingMarketing == 0 && pendingDividendQuote == 0
            && pendingSelfReward == 0 && pendingLPToken == 0 && pendingLPQuote == 0) return;
        if (!(gasleft() >= AUTO_CALL_GAS + AUTO_CALL_GAS/63 + TRADE_GAS_RESERVE)) revert TaxTradeGasLimitTooLow();
        bytes memory data = abi.encodeWithSelector(this.processTaxes.selector); bool ok;
        uint256 allowance_ = AUTO_CALL_GAS;
        assembly ("memory-safe") { ok := call(allowance_, address(), 0, add(data,32), mload(data), 0, 0) }
        if (!ok) emit AutomaticProcessingDeferred();
    }

    /// @notice Permissionless retry, same bounded pipeline as sell-triggered processing.
    ///         Caller cannot set paths, minimum outputs, amounts or payout receivers.
    function processTaxes() external nonReentrant {
        if (!(phase == Phase.Graduated)) revert NotGraduated();
        if (!(gasleft() >= 3_100_000)) revert TaxProcessingGasLimitTooLow();
        automaticProcessing = true;
        _observe(address(this), quoteToken);
        if (config.dividendBps > 0 && config.rewardMode != RewardMode.Self && rewardAsset != quoteToken) {
            if (quoteToken != wrappedNative && rewardAsset != wrappedNative) {
                _observe(quoteToken, wrappedNative); _observe(wrappedNative, rewardAsset);
            } else _observe(quoteToken, rewardAsset);
        }
        _stage(abi.encodeWithSelector(this.autoTax.selector), 600_000);
        if (dividend != address(0)) _stage(abi.encodeWithSelector(this.autoFund.selector), 900_000);
        _stage(abi.encodeWithSelector(this.autoLiquidity.selector), 450_000);
        bool paid = _stage(abi.encodeWithSelector(this.autoMarketing.selector, quoteToken == wrappedNative), 100_000);
        if (!paid && quoteToken == wrappedNative) _stage(abi.encodeWithSelector(this.autoMarketing.selector, false), 70_000);
        automaticProcessing = false;
    }
    function _stage(bytes memory data, uint256 allowance_) private returns (bool ok) {
        assembly ("memory-safe") { ok := call(allowance_, address(), 0, add(data,32), mload(data), 0, 0) }
        bytes4 selector; assembly ("memory-safe") { selector := mload(add(data,32)) }
        emit AutomaticStage(selector, ok);
    }
    function _observe(address input, address output) private {
        _stage(abi.encodeWithSelector(this.observePair.selector, input, output), 140_000);
    }
    function observePair(address input, address output) external onlySelf { prices.observe(router, input, output); }

    function _split(uint256 amount, uint256[4] memory weights) private pure returns (uint256[4] memory parts) {
        uint256 denominator; uint256 first = 4; uint256 used;
        for (uint256 i; i < 4; i++) { denominator += weights[i]; if (first == 4 && weights[i] > 0) first = i; }
        if (!(denominator > 0)) revert EmptySplit();
        for (uint256 i; i < 4; i++) { parts[i] = FullMath.mulDiv(amount, weights[i], denominator); used += parts[i]; }
        parts[first] += amount-used;
    }
    function _parts(uint256 amount) private view returns (uint256[4] memory) {
        return _split(amount, [uint256(config.marketingBps), uint256(config.burnBps), uint256(config.dividendBps), uint256(config.liquidityBps)]);
    }
    function _salePortion(uint256 amount) private view returns (uint256) {
        uint256[4] memory p = _parts(amount);
        return p[0] + (config.rewardMode == RewardMode.Self ? 0 : p[2]) + p[3] - p[3]/2;
    }
    function _swap(uint256 amount, uint256 minimum, address[] memory path) private returns (uint256 received) {
        if (!(amount > 0 && minimum > 0)) revert SwapNeedsMinimum();
        IERC20Minimal input = IERC20Minimal(path[0]); IERC20Minimal output = IERC20Minimal(path[path.length-1]);
        uint256 beforeInput = input.balanceOf(address(this)); uint256 beforeOutput = output.balanceOf(address(this));
        uint256 beforeTransit = output.balanceOf(swapReceiver);
        input.safeApprove(router,0); input.safeApprove(router,amount);
        // V2 INVALID_TO disallows address(this) as the recipient of our own-token swap.
        // Only the fresh balance delta is collected; pre-existing donations are not allocated.
        IADDTaxRouter(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(amount,minimum,path,swapReceiver,block.timestamp);
        ADDTaxSwapReceiverV1(swapReceiver).collect(address(output),output.balanceOf(swapReceiver)-beforeTransit);
        input.safeApprove(router,0);
        if (!(beforeInput - input.balanceOf(address(this)) == amount)) revert UnexpectedSwapDebit();
        received = output.balanceOf(address(this)) - beforeOutput;
        if (!(received >= minimum)) revert InsufficientSwapOutput();
    }
    /// @dev Each stage executes in a rollback-isolated self call. Failures retain
    ///      allocations and do not silently mark rewards paid or burn user reserves.
    function autoTax() external onlySelf {
        uint256 amount = unprocessedTokens(); if (amount < processingThreshold()) return;
        if (amount > maximumProcessAmount) amount = maximumProcessAmount;
        uint256 sale = _salePortion(amount); uint256 minimum;
        address[] memory path = new address[](2); path[0] = address(this); path[1] = quoteToken;
        if (sale > 0) {
            (uint256 bounded,) = prices.quote(router,path,sale);
            if (bounded < sale) amount = FullMath.mulDiv(amount,bounded,sale);
            sale = _salePortion(amount);
            (bounded,minimum) = prices.quote(router,path,sale);
            if (!(bounded == sale)) revert RoundedSwapCapacity();
        }
        uint256[4] memory p = _parts(amount);
        if (p[1] > 0) { totalBurned += p[1]; _transfer(address(this),DEAD,p[1]); }
        uint256 rewardSale = p[2];
        if (config.rewardMode == RewardMode.Self) { pendingSelfReward += p[2]; rewardSale = 0; }
        uint256 keepLP = p[3]/2; uint256 sellLP = p[3]-keepLP; pendingLPToken += keepLP;
        uint256 received;
        if (sale > 0) {
            received = _swap(sale,minimum,path);
            uint256[4] memory q = _split(received,[p[0],rewardSale,sellLP,uint256(0)]);
            pendingMarketing += q[0]; pendingDividendQuote += q[1]; pendingLPQuote += q[2];
        }
        emit TaxProcessed(amount,p[1],received);
    }
    function autoFund() external onlySelf {
        uint256 amount = config.rewardMode == RewardMode.Self ? pendingSelfReward : pendingDividendQuote;
        if (amount == 0) return;
        uint256 output = amount; uint256 minimum = amount;
        if (config.rewardMode == RewardMode.Self) pendingSelfReward -= amount;
        else {
            if (rewardAsset != quoteToken) {
                bool via = quoteToken != wrappedNative && rewardAsset != wrappedNative;
                address[] memory path = new address[](via ? 3 : 2); path[0] = quoteToken; path[path.length-1] = rewardAsset;
                if (via) path[1] = wrappedNative;
                (amount,minimum) = prices.quote(router,path,amount);
                output = _swap(amount,minimum,path);
            }
            pendingDividendQuote -= amount;
        }
        IERC20Minimal asset = IERC20Minimal(rewardAsset);
        uint256 beforeBalance = asset.balanceOf(address(this));
        asset.safeApprove(dividend,0); asset.safeApprove(dividend,output);
        uint256 received = ADDClaimDividendV1(payable(dividend)).depositRewards(output);
        asset.safeApprove(dividend,0);
        if (!(beforeBalance - asset.balanceOf(address(this)) == output && received >= minimum)) revert InvalidRewardFunding();
    }
    function autoLiquidity() external onlySelf {
        if (pendingLPToken == 0 || pendingLPQuote == 0) return;
        (uint256 rt,uint256 rq,) = prices.checkedPrice(router,address(this),quoteToken);
        uint256 t = pendingLPToken;
        if (t > maximumProcessAmount) t = maximumProcessAmount;
        if (t > rt/1000) t = rt/1000;
        uint256 q = FullMath.mulDiv(t,rq,rt);
        if (q > pendingLPQuote) { q = pendingLPQuote; t = FullMath.mulDiv(q,rt,rq); }
        uint256 minT = FullMath.mulDiv(t,9700,10000); uint256 minQ = FullMath.mulDiv(q,9700,10000);
        if (!(minT > 0 && minQ > 0)) revert LPAmountTooSmall();
        uint256 beforeLP = IERC20Minimal(pair).balanceOf(DEAD);
        uint256 beforeT = balanceOf(address(this)); uint256 beforeQ = IERC20Minimal(quoteToken).balanceOf(address(this));
        _approve(address(this),router,t);
        IERC20Minimal(quoteToken).safeApprove(router,0); IERC20Minimal(quoteToken).safeApprove(router,q);
        (uint256 usedT,uint256 usedQ,uint256 lp) = IADDTaxRouter(router).addLiquidity(address(this),quoteToken,t,q,minT,minQ,DEAD,block.timestamp);
        _approve(address(this),router,0); IERC20Minimal(quoteToken).safeApprove(router,0);
        if (!(usedT >= minT && usedT <= t && usedQ >= minQ && usedQ <= q
            && beforeT-balanceOf(address(this)) == usedT
            && beforeQ-IERC20Minimal(quoteToken).balanceOf(address(this)) == usedQ)) revert InvalidLPConsumption();
        if (!(lp > 0 && IERC20Minimal(pair).balanceOf(DEAD) >= beforeLP+lp)) revert LPNotBurned();
        pendingLPToken -= usedT; pendingLPQuote -= usedQ; totalLiquidity += lp;
        emit LiquidityBurned(usedT,usedQ,lp);
    }
    function autoMarketing(bool unwrapNative) external onlySelf {
        uint256 amount = pendingMarketing; if (amount == 0) return; pendingMarketing = 0;
        if (unwrapNative) {
            if (!(quoteToken == wrappedNative)) revert NotNativeQuote();
            IADDClaimWrappedV1(wrappedNative).withdraw(amount);
            (bool ok,) = payable(config.marketingWallet).call{value:amount,gas:30000}("");
            if (!(ok)) revert MarketingNativeRejected();
        } else {
            uint256 beforeBalance = IERC20Minimal(quoteToken).balanceOf(address(this));
            IERC20Minimal(quoteToken).safeTransfer(config.marketingWallet,amount);
            if (!(beforeBalance-IERC20Minimal(quoteToken).balanceOf(address(this)) == amount)) revert UnexpectedMarketingDebit();
        }
        emit MarketingPaid(config.marketingWallet,amount,unwrapNative);
    }
    receive() external payable { if (!(msg.sender == wrappedNative)) revert OnlyWrappedNative(); }
}
