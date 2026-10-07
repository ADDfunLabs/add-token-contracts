// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../openzeppelin/SafeERC20.sol";
import "../openzeppelin/ReentrancyGuard.sol";
import "../FullMath.sol";

interface IADDStakingWrappedV2 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
interface IADDStakingTaxSourceV2 {
    function phase() external view returns (uint8);
    function initializationFactory() external view returns (address);
    function wrappedNative() external view returns (address);
    function quoteToken() external view returns (address);
    function pair() external view returns (address);
}

/// @title ADD permissionless staking / claim mining pool V2: independent principal vesting
/// @notice 独立矿池，无 owner、升级、暂停、改费率、提走本金或奖励的管理入口。
/// @dev Rewards are funded assets, never minted: prepaid ERC20 or recurring ERC20/BNB.
///      address(0) stakingAsset means native
///      coin wrapped by the factory's immutable wrapper. Same-token principal and
///      reward reserves are separate liabilities. No holder loops or automatic payouts.
///      Rebasing/reflection assets and sender-extra-fee tokens are NOT supported.
contract ADDStakingPoolV2 is ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;

    address public constant FEE_RECIPIENT = 0xCb1D21591759E67E93D5054CaEbb5e972229DADd;
    uint256 public constant FEE_BPS = 100;
    uint256 public constant MAX_AMOUNT = type(uint112).max;
    uint256 public constant MAX_DURATION = 3650 days;
    uint8 public constant MAX_HALVINGS = 32;
    uint256 private constant SCALE = 1e36;
    // Integer time weights represent all 32 halvings exactly, with no rate-to-zero.
    uint256 private constant WEIGHT = 1 << 32;

    address public immutable initializationFactory;
    bool public initialized;
    uint256 public constant VERSION = 2;
    uint256 public constant MAX_POSITIONS = 64;
    enum WithdrawalMode { Flexible, Cliff, Batches }
    struct PrincipalLock { WithdrawalMode mode; uint16 initialDays; uint16 intervalDays; uint16 batches; }
    struct Position { uint112 deposited; uint112 withdrawn; uint64 startedAt; }
    struct UnlockView { uint256 withdrawable; uint256 locked; uint256 nextUnlockAt; uint256 livePositions; }
    PrincipalLock public principalLock;
    bool public lockConfigured;
    mapping(address => Position[]) private positions;
    event PrincipalLockConfigured(WithdrawalMode mode, uint16 initialDays, uint16 intervalDays, uint16 batches);
    event StakePositionOpened(address indexed holder, uint256 indexed slot, uint256 received, uint256 startedAt);

    /// @notice 工厂在同一创建交易中、初始化之前写入一次；之后任何人均不可改锁仓规则。
    /// @dev Principal uses wall-clock days, independently of the reward clock (which
    ///      pauses with no stakers). A later deposit never resets an earlier deposit.
    function configurePrincipalLock(PrincipalLock calldata p) external {
        require(msg.sender == initializationFactory && !initialized && !lockConfigured, "Lock configuration forbidden");
        if (p.mode == WithdrawalMode.Flexible) {
            require(p.initialDays == 0 && p.intervalDays == 0 && p.batches == 0, "Invalid flexible lock");
        } else if (p.mode == WithdrawalMode.Cliff) {
            require(p.initialDays >= 1 && p.initialDays <= 3650 && p.intervalDays == 0 && p.batches == 1, "Invalid cliff lock");
        } else {
            require(p.initialDays <= 3650 && p.intervalDays >= 1 && p.batches >= 2 && p.batches <= 365, "Invalid batch lock");
            require(uint256(p.initialDays) + uint256(p.intervalDays) * (p.batches - 1) <= 3650, "Lock exceeds 3650 days");
        }
        principalLock = p; lockConfigured = true;
        emit PrincipalLockConfigured(p.mode, p.initialDays, p.intervalDays, p.batches);
    }

    function _openPosition(address holder, uint256 received) private {
        if (principalLock.mode == WithdrawalMode.Flexible) return;
        Position[] storage list = positions[holder]; uint256 slot = list.length;
        for (uint256 i; i < list.length; ++i) {
            if (list[i].withdrawn == list[i].deposited) { slot = i; break; }
        }
        require(slot < MAX_POSITIONS, "Withdraw old positions before adding more");
        Position memory p = Position(uint112(received), 0, uint64(block.timestamp));
        if (slot == list.length) list.push(p); else list[slot] = p;
        emit StakePositionOpened(holder, slot, received, block.timestamp);
    }

    /// @dev Use cumulative floor(principal * releasedBatches / batches), not a
    ///      rounded per-batch amount. The final batch always unlocks every last unit.
    function _unlocked(Position memory p) private view returns (uint256 vested, uint256 next) {
        if (p.withdrawn == p.deposited) return (p.deposited, 0);
        uint256 first = uint256(p.startedAt) + uint256(principalLock.initialDays) * 1 days;
        if (block.timestamp < first) return (0, first);
        if (principalLock.mode == WithdrawalMode.Cliff) return (p.deposited, 0);
        uint256 interval = uint256(principalLock.intervalDays) * 1 days;
        uint256 released = 1 + (block.timestamp - first) / interval;
        uint256 count = principalLock.batches;
        if (released >= count) return (p.deposited, 0);
        vested = uint256(p.deposited) * released / count;
        // With tiny deposits some batches round to zero; report the next boundary
        // that actually releases another base unit, not a misleading zero release.
        uint256 nextBatch = ((vested + 1) * count + p.deposited - 1) / p.deposited;
        next = first + (nextBatch - 1) * interval;
    }

    function getUnlockInfo(address holder) external view returns (UnlockView memory v) {
        if (principalLock.mode == WithdrawalMode.Flexible) { v.withdrawable = accounts[holder].staked; return v; }
        Position[] storage list = positions[holder];
        for (uint256 i; i < list.length; ++i) {
            Position memory p = list[i]; if (p.deposited == p.withdrawn) continue;
            (uint256 vested, uint256 next) = _unlocked(p);
            v.withdrawable += vested - p.withdrawn; v.locked += p.deposited - vested; ++v.livePositions;
            if (next != 0 && (v.nextUnlockAt == 0 || next < v.nextUnlockAt)) v.nextUnlockAt = next;
        }
    }

    /// @notice 返回稳定槽位的存款记录；取完后槽位可复用，以事件追溯旧记录。
    function getPositions(address holder, uint256 offset, uint256 limit) external view returns (Position[] memory result) {
        require(limit <= MAX_POSITIONS, "Page limit exceeds 64");
        Position[] storage list = positions[holder]; uint256 n = offset >= list.length ? 0 : list.length - offset;
        if (n > limit) n = limit; result = new Position[](n);
        for (uint256 i; i < n; ++i) result[i] = list[offset + i];
    }

    function _consumeUnlocked(address holder, uint256 amount) private {
        if (principalLock.mode == WithdrawalMode.Flexible) return;
        Position[] storage list = positions[holder]; uint256 remaining = amount;
        for (uint256 i; i < list.length && remaining != 0; ++i) {
            Position storage p = list[i]; (uint256 vested,) = _unlocked(p);
            uint256 available = vested - p.withdrawn;
            uint256 take = available < remaining ? available : remaining;
            p.withdrawn += uint112(take); remaining -= take;
        }
        // The whole transaction reverts, including any partially consumed slots.
        require(remaining == 0, "Principal is still locked");
    }
    address public creator; // Informational only. It grants NO special permissions.
    address public rewardToken;
    address public stakingAsset;
    address public stakingToken;
    address public wrappedNative;
    uint256 public createdAt;
    uint256 public initialDuration;
    uint256 public halvingInterval;
    uint8 public halvingCount;
    bool public cycling;
    bool public nativeReward;
    address public linkedToken;
    bool public linkedActivated;
    uint8 public linkedStakeMode; // 0 self token; 1 final V2 LP; 2 custom (zero = native).
    address public linkedCustomStake;
    uint256 public cycleNumber;
    uint256 public cycleBudget;
    uint256 public cycleStartActive;
    uint256 public cycleStartEmitted;

    uint256 public totalStaked;
    uint256 public totalFunded;
    uint256 public totalGrossClaimed;
    uint256 public totalFeesPaid;
    uint256 public lastUpdate;
    // Emission = numerator * weighted active seconds / denominator, carrying fractions.
    uint256 public rateNumerator;
    uint256 public rateDenominator;

    struct Ledger {
        uint256 remaining;
        uint256 emissionFraction;
        uint256 activeElapsed;
        uint256 emitted;
        uint256 index;
        uint256 indexRemainder;
    }
    Ledger private ledger;
    struct Account {
        uint256 staked;
        uint256 index;
        uint256 credit;
        uint256 fraction;
        uint256 grossClaimed;
    }
    mapping(address => Account) public accounts;
    enum FundingMode { Extend, Recalculate }

    struct ScheduleView {
        uint256 remainingRewards;
        uint256 emittedRewards;
        uint256 grossClaimed;
        uint256 fundedRewards;
        uint256 stakedSupply;
        uint256 activeElapsedSeconds;
        uint256 remainingActiveSeconds;
        uint256 estimatedEndTime;
        uint256 currentRateNumerator;
        uint256 currentRateDenominator;
        uint256 currentRewardsPerMinute;
        uint256 nextHalvingInActiveSeconds;
        uint256 halvingsApplied;
        bool pausedForNoStakers;
        bool finished;
    }
    struct AccountView {
        uint256 staked;
        uint256 totalStake;
        uint256 shareBps;
        uint256 earnedGross;
        uint256 claimFee;
        uint256 claimNet;
        uint256 claimedGross;
        uint256 paidFees;
    }
    struct FundingView {
        uint256 assumedReceived;
        uint256 remainingRewardsAfter;
        uint256 remainingActiveSeconds;
        uint256 estimatedEndTime;
        uint256 currentRewardsPerMinute;
    }

    event Staked(address indexed holder, uint256 requested, uint256 received);
    event Withdrawn(address indexed holder, address indexed receiver, uint256 amount, bool unwrapped);
    event RewardsAdded(address indexed funder, uint256 requested, uint256 received, FundingMode mode,
        uint256 numerator, uint256 denominator, uint256 remainingActiveSeconds);
    event RewardClaimed(address indexed holder, address indexed receiver, uint256 gross, uint256 fee);
    event Checkpoint(uint256 emittedNow, uint256 activeElapsed, uint256 remainingRewards);
    event LinkedPoolActivated(address indexed token, address rewardAsset, address stakingAsset);
    event CycleStarted(uint256 indexed cycle, uint256 rewards, uint256 durationSeconds);
    event RewardsDetected(uint256 indexed cycle, uint256 amount, uint256 remainingSeconds);

    constructor(address factory_) {
        require(factory_ != address(0), "Invalid initialization factory");
        initializationFactory = factory_; initialized = true;
    }
    modifier ready() { require(initialized && rewardToken != address(0), "Pool not initialized"); _; }
    modifier activateLinked() {
        if (linkedToken != address(0) && !linkedActivated) _activateLinked();
        _;
    }

    /// @dev The implementation is locked; clones can be initialized once only by their
    ///      deploying factory, after that factory transfers actual initial rewards.
    function initialize(address creator_, address reward_, address stake_, address wrapped_,
        uint256 received, uint256 duration, uint256 interval, uint8 halvings) external {
        require(msg.sender == initializationFactory && !initialized && lockConfigured, "Initialization forbidden");
        require(creator_ != address(0) && reward_.code.length > 0 && wrapped_.code.length > 0,
            "Invalid assets");
        require(stake_ == address(0) || stake_.code.length > 0, "Invalid stake asset");
        require(received > 0 && received <= MAX_AMOUNT && duration > 0 && duration <= MAX_DURATION,
            "Invalid funding or duration");
        require((halvings == 0 && interval == 0) ||
            (halvings > 0 && halvings <= MAX_HALVINGS && interval > 0 && interval <= MAX_DURATION),
            "Invalid halving plan");
        require(IERC20Minimal(reward_).balanceOf(address(this)) >= received, "Unfunded pool");
        initialized = true; creator = creator_; rewardToken = reward_; stakingAsset = stake_;
        wrappedNative = wrapped_; stakingToken = stake_ == address(0) ? wrapped_ : stake_;
        initialDuration = duration; halvingInterval = interval; halvingCount = halvings;
        createdAt = block.timestamp; lastUpdate = block.timestamp;
        totalFunded = received; ledger.remaining = received;
        rateNumerator = received; rateDenominator = duration * WEIGHT;
        _remainingTime(ledger); // Validate the finite time horizon, including all halvings.
    }

    /// @notice 独立循环池允许零首存：等待后续税款，周期1～360天，不减半。
    function initializeCycle(address creator_, address rewardAsset_, address stake_, address wrapped_, uint16 days_)
        external {
        _initializeCycleBase(creator_, wrapped_, days_);
        require(rewardAsset_ == address(0) || rewardAsset_.code.length > 0, "Invalid reward asset");
        require(stake_ == address(0) || stake_.code.length > 0, "Invalid stake asset");
        nativeReward = rewardAsset_ == address(0);
        rewardToken = nativeReward ? wrapped_ : rewardAsset_;
        stakingAsset = stake_; stakingToken = stake_ == address(0) ? wrapped_ : stake_;
    }

    /// @dev Bind and display the known quote/LP at creation. Staking remains gated until
    ///      graduation; a recovery graduation may correct these addresses ONCE before
    ///      any principal or reward liability exists. No owner can set arbitrary assets.
    function initializeLinkedCycle(address creator_, address token_, address wrapped_, uint16 days_,
        uint8 stakeMode_, address customStake_) external {
        _initializeCycleBase(creator_, wrapped_, days_);
        require(token_.code.length > 0 && IADDStakingTaxSourceV2(token_).initializationFactory() == msg.sender,
            "Wrong linked token factory");
        require(stakeMode_ <= 2 && (stakeMode_ == 2 || customStake_ == address(0)), "Invalid staking choice");
        require(stakeMode_ != 2 || customStake_ == address(0) || customStake_.code.length > 0, "Invalid custom stake");
        linkedToken = token_; linkedStakeMode = stakeMode_; linkedCustomStake = customStake_;
        _bindLinkedAssets();
    }

    function _initializeCycleBase(address creator_, address wrapped_, uint16 days_) private {
        require(msg.sender == initializationFactory && !initialized && lockConfigured, "Initialization forbidden");
        require(creator_ != address(0) && wrapped_.code.length > 0, "Invalid cycle assets");
        require(days_ >= 1 && days_ <= 360, "Cycle must be 1 to 360 days");
        initialized = true; cycling = true; creator = creator_; wrappedNative = wrapped_;
        initialDuration = uint256(days_) * 1 days;
        rateDenominator = initialDuration * WEIGHT;
        createdAt = block.timestamp; lastUpdate = block.timestamp;
    }

    function _activateLinked() private {
        IADDStakingTaxSourceV2 source = IADDStakingTaxSourceV2(linkedToken);
        require(source.phase() == 3, "Mining awaits graduation");
        require(totalStaked == 0 && totalFunded == 0 && ledger.emitted == 0, "Linked assets already in use");
        _bindLinkedAssets(); linkedActivated = true; lastUpdate = block.timestamp;
        emit LinkedPoolActivated(linkedToken, nativeReward ? address(0) : rewardToken, stakingAsset);
    }

    function _bindLinkedAssets() private {
        IADDStakingTaxSourceV2 source = IADDStakingTaxSourceV2(linkedToken);
        require(source.wrappedNative() == wrappedNative, "Wrong linked wrapper");
        address reward = source.quoteToken(); address market = source.pair();
        require(reward.code.length > 0 && market.code.length > 0, "Invalid final market");
        rewardToken = reward; nativeReward = reward == wrappedNative;
        stakingAsset = linkedStakeMode == 0 ? linkedToken : linkedStakeMode == 1 ? market : linkedCustomStake;
        stakingToken = stakingAsset == address(0) ? wrappedNative : stakingAsset;
    }

    /// @dev At most 33 iterations regardless of time since last update. After the chosen
    ///      final halving, the last rate persists until the prepaid budget is exhausted.
    function _weightAt(uint256 elapsed) private view returns (uint256 weight, uint256 next) {
        uint256 n = halvingInterval == 0 ? 0 : elapsed / halvingInterval;
        if (n >= halvingCount) return (WEIGHT >> halvingCount, type(uint256).max);
        return (WEIGHT >> n, (n + 1) * halvingInterval);
    }

    function _work(uint256 start, uint256 seconds_) private view returns (uint256 result) {
        while (seconds_ != 0) {
            (uint256 weight, uint256 boundary) = _weightAt(start);
            uint256 span = seconds_;
            if (boundary != type(uint256).max && span > boundary - start) span = boundary - start;
            result += span * weight; start += span; seconds_ -= span;
        }
    }

    function _secondsForWork(uint256 start, uint256 work) private view returns (uint256 result) {
        while (work != 0) {
            (uint256 weight, uint256 boundary) = _weightAt(start);
            uint256 needed = (work - 1) / weight + 1;
            if (boundary == type(uint256).max || needed <= boundary - start) {
                result += needed; break;
            }
            uint256 span = boundary - start;
            result += span; work -= span * weight; start = boundary;
        }
    }

    function _remainingTime(Ledger memory p) private view returns (uint256 result) {
        return _remainingTimeAtRate(p, rateNumerator, rateDenominator);
    }

    function _remainingTimeAtRate(Ledger memory p, uint256 numerator, uint256 denominator)
        private view returns (uint256 result) {
        if (p.remaining == 0) return 0;
        // remaining <= 112 bits, denominator <= 96 bits. Products fit uint256.
        uint256 needed = p.remaining * denominator - p.emissionFraction;
        uint256 weightedSeconds = (needed - 1) / numerator + 1;
        result = _secondsForWork(p.activeElapsed, weightedSeconds);
        require(result <= type(uint64).max - p.activeElapsed, "Schedule too long");
    }

    /// @dev Empty pools do not consume mining time. The pool freezes at the exact
    ///      exhaustion second, rather than advancing the halving clock during downtime.
    function _preview() private view returns (Ledger memory p) {
        p = ledger;
        if (totalStaked == 0 || p.remaining == 0) return p;
        uint256 dt = block.timestamp - lastUpdate;
        uint256 left = _remainingTime(p);
        uint256 emitted;
        if (dt >= left) {
            dt = left; emitted = p.remaining; p.emissionFraction = 0;
        } else {
            uint256 scaled = _work(p.activeElapsed, dt) * rateNumerator + p.emissionFraction;
            emitted = scaled / rateDenominator; p.emissionFraction = scaled % rateDenominator;
        }
        p.activeElapsed += dt; p.remaining -= emitted; p.emitted += emitted;
        // Remainder carry prevents frequent checkpoints from destroying accrued dust.
        // After stake changes, less than one base unit of aggregate fractional dust can
        // pass to the next stake set. It never expands the funded liability.
        uint256 indexedRewards = emitted * SCALE + p.indexRemainder;
        p.index += indexedRewards / totalStaked; p.indexRemainder = indexedRewards % totalStaked;
    }

    function _checkpoint(bool syncRewards, uint256 nativePrincipal) private {
        Ledger memory p = _preview();
        if (p.emitted != ledger.emitted) emit Checkpoint(p.emitted - ledger.emitted, p.activeElapsed, p.remaining);
        ledger = p; lastUpdate = block.timestamp;
        if (cycling && syncRewards) _syncRewards(nativePrincipal);
    }

    function checkpoint() external nonReentrant activateLinked ready { _checkpoint(true, 0); }

    /// @dev Only genuinely unaccounted surplus is new revenue. Existing principal,
    ///      unclaimed rewards and rounding reserves must never be counted a second time.
    ///      Native staking msg.value is excluded until credited as PRINCIPAL by stake().
    function _syncRewards(uint256 nativePrincipal) private {
        if (nativeReward) {
            uint256 nativeSurplus = address(this).balance - nativePrincipal;
            if (nativeSurplus != 0) IADDStakingWrappedV2(wrappedNative).deposit{value:nativeSurplus}();
        }
        uint256 balance = IERC20Minimal(rewardToken).balanceOf(address(this));
        uint256 protected = protectedBalance(rewardToken);
        require(balance >= protected, "Insolvent reward asset");
        uint256 received = balance - protected;
        // Excess beyond the lifetime arithmetic cap must not let a donation freeze claims.
        uint256 capacity = MAX_AMOUNT - totalFunded;
        if (received > capacity) received = capacity;
        if (received == 0) return;
        uint256 left = _remainingTime(ledger);
        if (left == 0) {
            left = initialDuration; cycleNumber++;
            cycleBudget = 0; cycleStartActive = ledger.activeElapsed; cycleStartEmitted = ledger.emitted;
            emit CycleStarted(cycleNumber, received, left);
        }
        totalFunded += received; ledger.remaining += received; cycleBudget += received;
        rateNumerator = ledger.remaining; rateDenominator = left * WEIGHT;
        ledger.emissionFraction = 0;
        _remainingTime(ledger);
        emit RewardsDetected(cycleNumber, received, left);
    }

    /// @notice 显式支付循环奖励；普通ERC20转账/BNB转账也可，质押/领取时自动识别。
    function fundCycle(uint256 amount, uint256 minimumReceived) external payable nonReentrant activateLinked ready
        returns (uint256 received) {
        require(cycling && amount > 0, "Not cycle funding");
        require(nativeReward ? msg.value == amount : msg.value == 0, "Wrong funding native value");
        _checkpoint(true, msg.value);
        uint256 beforeBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
        if (nativeReward) IADDStakingWrappedV2(wrappedNative).deposit{value:msg.value}();
        else IERC20Minimal(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        received = IERC20Minimal(rewardToken).balanceOf(address(this)) - beforeBalance;
        require(received > 0 && received >= minimumReceived, "Insufficient rewards received");
        require(received <= MAX_AMOUNT - totalFunded, "Funding cap exceeded");
        _syncRewards(0);
    }

    function _settle(address holder) private {
        Account storage a = accounts[holder];
        uint256 delta = ledger.index - a.index;
        uint256 fraction = mulmod(a.staked, delta, SCALE) + a.fraction;
        a.credit += FullMath.mulDiv(a.staked, delta, SCALE) + fraction / SCALE;
        a.fraction = fraction % SCALE; a.index = ledger.index;
    }

    /// @notice ERC20 先授权本矿池，BNB 传入同额 msg.value；到账多少记录多少本金。
    function stake(uint256 amount, uint256 minimumReceived) external payable nonReentrant activateLinked ready returns (uint256 received) {
        require(amount > 0, "Zero stake");
        require(stakingAsset == address(0) ? msg.value == amount : msg.value == 0, "Wrong native value");
        _checkpoint(true, msg.value); _settle(msg.sender);
        uint256 beforeBalance = IERC20Minimal(stakingToken).balanceOf(address(this));
        if (stakingAsset == address(0)) {
            require(msg.value == amount, "Wrong native value");
            IADDStakingWrappedV2(wrappedNative).deposit{value: amount}();
        } else {
            require(msg.value == 0, "Unexpected native value");
            IERC20Minimal(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        }
        received = IERC20Minimal(stakingToken).balanceOf(address(this)) - beforeBalance;
        require(received > 0 && received >= minimumReceived, "Insufficient stake received");
        require(totalStaked + received <= MAX_AMOUNT, "Stake cap exceeded");
        _openPosition(msg.sender, received);
        totalStaked += received; accounts[msg.sender].staked += received;
        _requireSolvent(stakingToken);
        emit Staked(msg.sender, amount, received);
    }

    /// @notice 取回已解锁本金，独立于领取奖励；native 池可选择 BNB 或 WBNB。
    function withdraw(uint256 amount, address payable receiver, bool unwrapNative) external ready nonReentrant {
        _validReceiver(receiver); require(amount > 0 && amount <= accounts[msg.sender].staked, "Invalid withdrawal");
        require(!unwrapNative || stakingAsset == address(0), "Not a native stake pool");
        // Principal exit deliberately does not depend on detecting new reward transfers.
        _checkpoint(false, 0); _settle(msg.sender);
        _consumeUnlocked(msg.sender, amount);
        accounts[msg.sender].staked -= amount; totalStaked -= amount;
        if (unwrapNative) {
            uint256 beforeBalance = IERC20Minimal(stakingToken).balanceOf(address(this));
            IADDStakingWrappedV2(wrappedNative).withdraw(amount);
            require(IERC20Minimal(stakingToken).balanceOf(address(this)) == beforeBalance - amount, "Unexpected asset debit");
            (bool ok,) = receiver.call{value: amount}(""); require(ok, "Native payment failed");
        } else {
            _payExact(stakingToken, receiver, amount);
        }
        _requireSolvent(stakingToken);
        emit Withdrawn(msg.sender, receiver, amount, unwrapNative);
    }

    /// @notice 任何人支付矿币追加。Extend 保持当前减半曲线、延长时间；Recalculate
    ///         保持当前预计结束时点、重算后续速度；已经产生的奖励绝不重新分配。
    /// @dev Recalculate is unavailable after exhaustion (there is no remaining time).
    ///      Extend can restart an exhausted pool at its previous rate/halving position.
    function addRewards(uint256 amount, uint256 minimumReceived, FundingMode mode)
        external ready nonReentrant returns (uint256 received) {
        require(!cycling, "Use fundCycle for cyclic rewards");
        require(amount > 0, "Zero rewards"); _checkpoint(false, 0);
        uint256 left = _remainingTime(ledger);
        require(mode != FundingMode.Recalculate || left != 0, "No remaining mining time");
        uint256 beforeBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
        IERC20Minimal(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        received = IERC20Minimal(rewardToken).balanceOf(address(this)) - beforeBalance;
        require(received > 0 && received >= minimumReceived, "Insufficient rewards received");
        require(totalFunded + received <= MAX_AMOUNT, "Funding cap exceeded");
        totalFunded += received; ledger.remaining += received;
        if (mode == FundingMode.Recalculate) {
            rateNumerator = ledger.remaining;
            rateDenominator = _work(ledger.activeElapsed, left);
            ledger.emissionFraction = 0;
        }
        uint256 newLeft = _remainingTime(ledger);
        _requireSolvent(rewardToken);
        emit RewardsAdded(msg.sender, amount, received, mode, rateNumerator, rateDenominator, newLeft);
    }

    /// @dev Charge floor(lifetimeGross/100), retaining fractional fee across claims so
    ///      splitting one account's claims cannot bypass the 1% fee through rounding.
    function claim(address receiver) external nonReentrant activateLinked ready returns (uint256 net) {
        return _claim(receiver, true);
    }

    /// @notice BNB奖励可选择接收WBNB，平台维护费仍以BNB支付。
    function claimWrapped(address receiver) external nonReentrant activateLinked ready returns (uint256 net) {
        return _claim(receiver, false);
    }

    function _claim(address receiver, bool unwrapReward) private returns (uint256 net) {
        _validReceiver(receiver); _checkpoint(true, 0); _settle(msg.sender);
        Account storage a = accounts[msg.sender]; uint256 gross = a.credit;
        if (gross == 0) return 0;
        uint256 fee = (a.grossClaimed + gross) / 100 - a.grossClaimed / 100;
        a.credit = 0; a.grossClaimed += gross; totalGrossClaimed += gross; totalFeesPaid += fee;
        require(totalGrossClaimed <= ledger.emitted, "Reward liability exceeded");
        net = gross - fee;
        if (nativeReward) {
            uint256 unwrapped = fee + (unwrapReward ? net : 0);
            if (unwrapped != 0) {
                uint256 beforeBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
                IADDStakingWrappedV2(wrappedNative).withdraw(unwrapped);
                require(IERC20Minimal(rewardToken).balanceOf(address(this)) == beforeBalance - unwrapped, "Unexpected asset debit");
            }
            if (fee != 0) _sendNative(FEE_RECIPIENT, fee);
            if (net != 0) {
                if (unwrapReward) _sendNative(receiver, net);
                else _payExact(rewardToken, receiver, net);
            }
        } else {
            if (fee != 0) _payExact(rewardToken, FEE_RECIPIENT, fee);
            if (net != 0) _payExact(rewardToken, receiver, net);
        }
        _requireSolvent(rewardToken);
        emit RewardClaimed(msg.sender, receiver, gross, fee);
    }

    function _sendNative(address receiver, uint256 amount) private {
        (bool ok,) = payable(receiver).call{value:amount}(""); require(ok, "Native payment failed");
    }

    function _validReceiver(address receiver) private view {
        require(receiver != address(0) && receiver != address(this), "Invalid receiver");
    }

    function _payExact(address asset, address receiver, uint256 amount) private {
        uint256 beforeBalance = IERC20Minimal(asset).balanceOf(address(this));
        IERC20Minimal(asset).safeTransfer(receiver, amount);
        require(IERC20Minimal(asset).balanceOf(address(this)) == beforeBalance - amount, "Unexpected asset debit");
    }

    /// @notice Protected amount includes all not-yet-claimed reward dust; no administrator
    ///         can recover it. Direct transfers are never principal; matching-asset
    ///         surplus becomes rewards only for cycling pools, at the next sync.
    function protectedBalance(address asset) public view returns (uint256 amount) {
        if (asset == stakingToken) amount = totalStaked;
        if (asset == rewardToken) amount += totalFunded - totalGrossClaimed;
    }

    function _requireSolvent(address asset) private view {
        require(IERC20Minimal(asset).balanceOf(address(this)) >= protectedBalance(asset), "Insolvent asset");
    }

    function getSchedule() external view ready returns (ScheduleView memory s) {
        Ledger memory p = _preview(); uint256 left = _remainingTime(p);
        (uint256 weight, uint256 next) = _weightAt(p.activeElapsed);
        s = ScheduleView(p.remaining, p.emitted, totalGrossClaimed, totalFunded, totalStaked,
            p.activeElapsed, left, left == 0 ? 0 : block.timestamp + left,
            rateNumerator * weight, rateDenominator,
            FullMath.mulDiv(rateNumerator, weight * 60, rateDenominator),
            next == type(uint256).max ? 0 : next - p.activeElapsed,
            halvingInterval == 0 ? 0 : p.activeElapsed / halvingInterval,
            totalStaked == 0 && left != 0, left == 0);
        if (s.halvingsApplied > halvingCount) s.halvingsApplied = halvingCount;
    }

    function getAccount(address holder) external view ready returns (AccountView memory v) {
        Ledger memory p = _preview(); Account memory a = accounts[holder];
        uint256 delta = p.index - a.index;
        uint256 gross = a.credit + FullMath.mulDiv(a.staked, delta, SCALE)
            + (mulmod(a.staked, delta, SCALE) + a.fraction) / SCALE;
        uint256 fee = (a.grossClaimed + gross) / 100 - a.grossClaimed / 100;
        return AccountView(a.staked, totalStaked, totalStaked == 0 ? 0 : FullMath.mulDiv(a.staked, 10000, totalStaked),
            gross, fee, gross - fee, a.grossClaimed, a.grossClaimed / 100);
    }

    /// @notice 追加确认页预览。received 是预计实际到账量；代币自身转账税及交易打包
    ///         时间可能使实际结果不同，应同时使用 minimumReceived 防止少到账。
    function previewAddRewards(uint256 received, FundingMode mode) external view ready returns (FundingView memory v) {
        require(!cycling, "Use cycle information");
        require(received > 0 && totalFunded + received <= MAX_AMOUNT, "Invalid additional funding");
        Ledger memory p = _preview(); uint256 left = _remainingTime(p);
        require(mode != FundingMode.Recalculate || left != 0, "No remaining mining time");
        p.remaining += received;
        uint256 numerator = rateNumerator; uint256 denominator = rateDenominator;
        if (mode == FundingMode.Recalculate) {
            numerator = p.remaining; denominator = _work(p.activeElapsed, left); p.emissionFraction = 0;
        }
        uint256 newLeft = _remainingTimeAtRate(p, numerator, denominator);
        (uint256 weight,) = _weightAt(p.activeElapsed);
        return FundingView(received, p.remaining, newLeft, block.timestamp + newLeft,
            FullMath.mulDiv(numerator, weight * 60, denominator));
    }

    /// @notice 循环统计可归零，但全局已赚未领取权益从不清零。
    function getCycleInfo() external view returns (uint256 number, uint256 duration, uint256 budget,
        uint256 emittedThisCycle, uint256 elapsedThisCycle, uint256 pendingUnrecognized, bool awaitingGraduation) {
        awaitingGraduation = linkedToken != address(0) && !linkedActivated;
        Ledger memory p = _preview();
        number = cycleNumber; duration = initialDuration; budget = cycleBudget;
        emittedThisCycle = p.emitted - cycleStartEmitted; elapsedThisCycle = p.activeElapsed - cycleStartActive;
        if (rewardToken != address(0)) {
            uint256 balance = IERC20Minimal(rewardToken).balanceOf(address(this));
            uint256 protected = protectedBalance(rewardToken);
            pendingUnrecognized = balance > protected ? balance - protected : 0;
            if (nativeReward) pendingUnrecognized += address(this).balance;
        }
    }

    // Keep this cheap: the existing tax token forwards marketing BNB with 30,000 gas.
    // Wrapping, balance detection and accounting happen on a later user interaction.
    receive() external payable {
        require(msg.sender == wrappedNative || nativeReward || linkedToken != address(0), "Use stake for native coin");
    }
}
