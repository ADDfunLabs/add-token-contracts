// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../openzeppelin/SafeERC20.sol";
import "../openzeppelin/ReentrancyGuard.sol";
import "../FullMath.sol";

interface IADDClaimTaxTokenV1 {
    function liquidityAdded() external view returns (bool);
    function automaticProcessing() external view returns (bool);
}
interface IADDClaimWrappedV1 { function withdraw(uint256 amount) external; }

/// @title ADD 专属领取式分红 / per-token claim ledger, candidate V1
/// @notice 每个启用分红的代币独立部署；奖励入账时分配权益，持有人自行领取。
/// @dev No owner, upgrade, sweep, receiver change, or balance-based claim-time snapshot.
///      The factory binds one token and one reward asset once. Never share this ledger
///      between launch tokens. Rebasing rewards and sender-extra-fee rewards are unsupported.
contract ADDClaimDividendV1 is ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;
    // Portal V1 inventory is bounded by uint112 per half, well below this scale.
    uint256 private constant SCALE = 1e36;
    address public immutable initializationFactory;
    bool private initialized;
    address public token;
    address public rewardToken;
    address public wrappedNative;
    bool public nativeReward;
    uint256 public minimumHolding;
    uint256 public totalShares;
    uint256 public rewardPerShare;
    uint256 public totalFunded;
    uint256 public totalClaimed;
    struct Account { uint256 share; uint256 index; uint256 credit; uint256 fraction; }
    mapping(address => Account) public accounts;

    event RewardsDeposited(uint256 actualReceived, uint256 eligibleShares, uint256 index);
    event ShareUpdated(address indexed holder, uint256 share);
    event RewardClaimed(address indexed holder, uint256 amount, bool nativePayment);

    constructor() { initializationFactory = msg.sender; initialized = true; }

    /// @dev Implementation is locked. Only its deploying factory can initialize clones.
    function initialize(address token_, address reward_, address wrapped_, bool native_, uint256 minimum) external {
        require(msg.sender == initializationFactory && !initialized, "Dividend initialization forbidden");
        require(token_.code.length > 0 && reward_.code.length > 0 && wrapped_.code.length > 0, "Invalid dividend assets");
        require(minimum >= 10_000 ether && (!native_ || reward_ == wrapped_), "Invalid dividend parameters");
        initialized = true;
        token = token_; rewardToken = reward_; wrappedNative = wrapped_;
        nativeReward = native_; minimumHolding = minimum;
    }

    /// @dev Prevent reward-asset callbacks from claiming midway through automatic conversion.
    ///      setShare deliberately remains callable by the token during a self-token claim.
    modifier outsideProcessing() {
        require(!IADDClaimTaxTokenV1(token).automaticProcessing(), "Tax processing active"); _;
    }

    function _settle(address holder) private {
        Account storage a = accounts[holder];
        uint256 delta = rewardPerShare - a.index;
        uint256 fraction = mulmod(a.share, delta, SCALE) + a.fraction;
        a.credit += FullMath.mulDiv(a.share, delta, SCALE) + fraction / SCALE;
        a.fraction = fraction % SCALE; a.index = rewardPerShare;
    }

    /// @notice 先结算旧持仓，再更新份额；卖出不会丢掉已记账的奖励。
    /// @dev Token-only, O(1), no recipient calls. Must never silently skip decreases.
    ///      Infrastructure/pairs must be passed zero by the bound token.
    function setShare(address holder, uint256 balance) external {
        require(msg.sender == token, "Only bound token");
        _settle(holder);
        Account storage a = accounts[holder];
        uint256 next = balance >= minimumHolding ? balance : 0;
        totalShares = totalShares - a.share + next; a.share = next;
        emit ShareUpdated(holder, next);
    }

    function claimable(address holder) public view returns (uint256) {
        Account memory a = accounts[holder]; uint256 delta = rewardPerShare - a.index;
        return a.credit + FullMath.mulDiv(a.share, delta, SCALE)
            + (mulmod(a.share, delta, SCALE) + a.fraction) / SCALE;
    }

    /// @notice Only the bound tax token funds rewards; ordinary transfers are donations,
    ///         not deposits, and cannot steal or reallocate another holder's entitlement.
    /// @dev Actual balance delta is credited. Funding with zero eligible shares reverts,
    ///      leaving funds pending at the tax token. No loops or payout rounds run here.
    function depositRewards(uint256 amount) external nonReentrant returns (uint256 received) {
        require(msg.sender == token, "Only bound token");
        require(IADDClaimTaxTokenV1(token).liquidityAdded(), "Not graduated");
        require(amount > 0 && totalShares > 0, "No eligible shares or amount");
        uint256 shares = totalShares;
        uint256 beforeBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
        IERC20Minimal(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        received = IERC20Minimal(rewardToken).balanceOf(address(this)) - beforeBalance;
        require(totalShares == shares, "Shares changed during funding");
        uint256 increment = FullMath.mulDiv(received, SCALE, shares);
        require(increment > 0, "Reward too small");
        rewardPerShare += increment; totalFunded += received;
        emit RewardsDeposited(received, shares, rewardPerShare);
    }

    /// @notice DApp 领取入口。unwrapNative=true 仅用于原生币奖励；false 领取 WBNB/ERC20。
    function claim(bool unwrapNative) external outsideProcessing nonReentrant returns (uint256) {
        return _claim(msg.sender, unwrapNative);
    }

    /// @notice Anyone can pay gas for a holder; rewards always go to that holder.
    function claimFor(address holder) external outsideProcessing nonReentrant returns (uint256) {
        return _claim(holder, false);
    }

    function _claim(address holder, bool unwrapNative) private returns (uint256 amount) {
        require(!unwrapNative || nativeReward, "Not native reward");
        _settle(holder); Account storage a = accounts[holder]; amount = a.credit;
        if (amount == 0) return 0;
        a.credit = 0; totalClaimed += amount;
        uint256 beforeBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
        if (unwrapNative) {
            IADDClaimWrappedV1(wrappedNative).withdraw(amount);
            (bool ok,) = payable(holder).call{value: amount}("");
            require(ok, "Native reward rejected");
        } else IERC20Minimal(rewardToken).safeTransfer(holder, amount);
        uint256 afterBalance = IERC20Minimal(rewardToken).balanceOf(address(this));
        // Reject sender-side extra fees. Failed payments revert credit AND asset movement.
        require(beforeBalance >= afterBalance && beforeBalance - afterBalance == amount, "Unexpected reward debit");
        emit RewardClaimed(holder, amount, unwrapNative);
    }

    receive() external payable { require(msg.sender == wrappedNative, "Only wrapped native"); }
}
