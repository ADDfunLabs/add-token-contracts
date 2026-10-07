// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../openzeppelin/SafeERC20.sol";
import "../openzeppelin/ReentrancyGuard.sol";
import "../FullMath.sol";
import "./ADDTaxTypes.sol";

/// @title ADD fixed-budget dividend rounds / 固定预算、分批轮询分红
/// @notice One round fixes its reward index and registry endpoint; later deposits wait for the next round.
/// @dev No owner, sweep or payout redirection. NEW deployments only.
///      Balance + totalClaimed == totalFunded, absent unsolicited transfers/rebases.
///      Transfers settle OLD shares before installing new shares: earned rewards do not travel with sold tokens.
///      Flap share/debt accounting was reviewed; this bounded on-chain round scheduler is ADD-specific.
contract ADDTaxDividend is ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;
    uint256 private constant SCALE=1e36;
    uint256 public constant MAX_BATCH_ADDRESSES=50;
    uint256 public constant PAYOUT_GAS=140_000;
    uint256 private constant LOOP_RESERVE=70_000;
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
    mapping(address=>Account) public accounts;

    // Append-only: never swap/remove an entry under a live cursor. New entries wait for the next round.
    // Former holders remain visitable because accrued credits survive falling below the holding threshold.
    address[] private holders;
    mapping(address=>bool) private registered;
    uint256 public roundId;
    uint256 public roundCursor;
    uint256 public roundEnd;
    uint256 public roundBudget;
    uint256 public roundShares;
    uint256 public queuedRewards;
    bool public roundActive;
    bool public retryNeeded;

    event RewardsFunded(address indexed sender,uint256 amount);
    event RewardClaimed(address indexed account,uint256 amount,bool nativeBNB);
    event HolderRegistered(address indexed holder,uint256 index);
    event RoundStarted(uint256 indexed id,uint256 budget,uint256 shares,uint256 end,uint256 index);
    /// @dev paid can include previously failed credits; it is not just expenditure of the current fresh budget.
    event RoundProgress(uint256 indexed id,uint256 cursor,uint256 checked,uint256 paid);
    event RoundCompleted(uint256 indexed id,uint256 queuedForNextRound,bool retryPending);
    event PayoutDeferred(uint256 indexed id,address indexed holder,uint256 amount);

    constructor() { initialized=true; }
    /// @dev A quote/reward token callback during an earlier processor stage must not sneak in another sweep,
    ///      close a round, or deposit a new budget before the one scheduled batch. The fixed processor remains
    ///      allowed to fund and process; isolated payFromBatch is protected separately by only-self and its lock.
    modifier outsideAutomaticCallback() {
        address processor=IADDTaxModules(token).taxProcessor();
        require(processor==address(0) || msg.sender==processor || !IADDTaxAutomaticState(processor).automaticActive(),"Automatic tax processing");
        _;
    }
    function initialize(address token_,address reward,address wrapped,bool native_,uint256 minimum) external {
        require(!initialized,"Already initialized"); initialized=true;
        require(token_.code.length>0 && reward.code.length>0 && wrapped.code.length>0,"Invalid dividend assets");
        token=token_; rewardToken=reward; wrappedNative=wrapped; nativeReward=native_; minimumHolding=minimum;
        require(!native_ || reward==wrapped,"Invalid native reward");
    }
    function holderCount() external view returns(uint256) { return holders.length; }
    function holderAt(uint256 index) external view returns(address) { return holders[index]; }

    /// @dev 512-bit multiplication plus per-holder fractional carry; SCALE exceeds the fixed 1e27 share supply.
    function _settle(address holder) internal {
        Account storage a=accounts[holder]; uint256 delta=rewardPerShare-a.index;
        uint256 fraction=mulmod(a.share,delta,SCALE)+a.fraction;
        a.credit+=FullMath.mulDiv(a.share,delta,SCALE)+fraction/SCALE;
        a.fraction=fraction%SCALE; a.index=rewardPerShare;
    }
    /// @notice Synchronous, token-only share update, also used during self-token dividend payouts.
    /// @dev Intentionally not nonReentrant: self-reward transfers must update shares while payout holds its lock.
    ///      Never silently skip/defer a balance decrease: doing so would let a seller retain dividend rights.
    function setShare(address holder,uint256 balance) external {
        require(msg.sender==token,"Only token"); _settle(holder);
        Account storage a=accounts[holder]; uint256 next=balance>=minimumHolding?balance:0;
        totalShares=totalShares-a.share+next; a.share=next;
        if(next>0 && !registered[holder]) {
            registered[holder]=true; holders.push(holder); emit HolderRegistered(holder,holders.length-1);
        }
    }
    function claimable(address holder) public view returns(uint256) {
        Account memory a=accounts[holder]; uint256 delta=rewardPerShare-a.index;
        return a.credit+FullMath.mulDiv(a.share,delta,SCALE)+(mulmod(a.share,delta,SCALE)+a.fraction)/SCALE;
    }

    /// @notice Credit the ACTUAL incoming ERC20 amount. Mid-round deposits never change the active reward index.
    /// @dev queuedRewards is consumed once when a new index is installed. Existing claims are never re-budgeted.
    ///      No eligible shares and no round: funding reverts and stays retryable at the processor.
    function depositRewards(uint256 amount) external outsideAutomaticCallback nonReentrant returns(uint256 received) {
        require(IADDTaxLifecycle(token).liquidityAdded(),"Not graduated");
        require(amount>0 && (totalShares>0 || roundActive),"No eligible shares or amount");
        uint256 beforeBalance=IERC20Minimal(rewardToken).balanceOf(address(this));
        IERC20Minimal(rewardToken).safeTransferFrom(msg.sender,address(this),amount);
        received=IERC20Minimal(rewardToken).balanceOf(address(this))-beforeBalance;
        require(received>0,"Reward too small"); queuedRewards+=received; totalFunded+=received;
        emit RewardsFunded(msg.sender,received);
        if(!roundActive) _startRound();
    }
    /// @dev O(1) snapshot. Later setShare settles each old share at this fixed index before changing it.
    ///      Registry length is frozen too: new holders cannot extend a running round indefinitely.
    ///      A zero-budget retry sweep pays only retained credits, including after every holder sold.
    function _startRound() private returns(bool) {
        if(roundActive || holders.length==0) return false;
        uint256 budget=queuedRewards;
        if(budget>0 && totalShares>0) {
            uint256 increment=FullMath.mulDiv(budget,SCALE,totalShares);
            if(increment==0) return false;
            rewardPerShare+=increment; queuedRewards=0;
        } else {
            if(!retryNeeded) return false;
            budget=0; // Queued funds stay intact until some holder qualifies for a funded round.
        }
        roundActive=true; retryNeeded=false; roundId++; roundCursor=0; roundEnd=holders.length;
        roundBudget=budget; roundShares=totalShares;
        emit RoundStarted(roundId,budget,roundShares,roundEnd,rewardPerShare); return true;
    }

    /// @notice Permissionless FIFO sweep; at most 50 entries CHECKED, including zero-credit and failed entries.
    /// @param maxAddresses Values above 50 are clamped; zero is a no-op.
    /// @param gasBudget Voluntary budget in addition to hard per-recipient call limits.
    /// @dev Never starts another round after finishing one in the same call. Cursor advances before the isolated
    ///      payout call, so failure restores the credit/payment but not the outer cursor. Old credits remain owed.
    ///      BNB is attempted first, with WBNB fallback for incompatible recipients.
    function process(uint256 maxAddresses,uint256 gasBudget) external outsideAutomaticCallback nonReentrant returns(uint256 checked,uint256 paid) {
        if(maxAddresses==0 || gasBudget==0) return (0,0);
        if(!roundActive && !_startRound()) return (0,0);
        uint256 limit=maxAddresses>MAX_BATCH_ADDRESSES?MAX_BATCH_ADDRESSES:maxAddresses;
        uint256 startGas=gasleft(); uint256 beforeClaimed=totalClaimed;
        uint256 attemptBudget=(nativeReward?2:1)*PAYOUT_GAS+LOOP_RESERVE;
        while(checked<limit && roundCursor<roundEnd) {
            uint256 spent=startGas-gasleft();
            if(gasleft()<=attemptBudget || spent>=gasBudget || gasBudget-spent<attemptBudget) break;
            address holder=holders[roundCursor++]; checked++;
            uint256 due=claimable(holder); if(due==0) continue;
            bool ok=_attempt(holder,nativeReward);
            if(!ok && nativeReward) ok=_attempt(holder,false);
            if(!ok) { retryNeeded=true; emit PayoutDeferred(roundId,holder,due); }
        }
        paid=totalClaimed-beforeClaimed; emit RoundProgress(roundId,roundCursor,checked,paid);
        if(roundCursor==roundEnd) { roundActive=false; emit RoundCompleted(roundId,queuedRewards,retryNeeded); }
    }
    function _attempt(address holder,bool unwrapBNB) private returns(bool ok) {
        bytes memory data=abi.encodeWithSelector(this.payFromBatch.selector,holder,unwrapBNB);
        uint256 allowance=PAYOUT_GAS;
        // Do not copy returndata: hostile token/receiver revert data cannot exhaust the parent's memory.
        assembly ("memory-safe") { ok:=call(allowance,address(),0,add(data,32),mload(data),0,0) }
    }
    /// @dev External only for an atomic rollback boundary. Parent process already holds nonReentrant.
    function payFromBatch(address holder,bool unwrapBNB) external returns(uint256) {
        require(msg.sender==address(this),"Only dividend batch"); return _claim(holder,unwrapBNB);
    }
    /// @notice Direct claims remain possible, including after selling below the minimum.
    function claim(bool unwrapBNB) external outsideAutomaticCallback nonReentrant returns(uint256) { return _claim(msg.sender,unwrapBNB); }
    function claimFor(address holder) external outsideAutomaticCallback nonReentrant returns(uint256) { return _claim(holder,false); }
    function _claim(address holder,bool unwrapBNB) internal returns(uint256 amount) {
        require(!unwrapBNB || nativeReward,"Reward is not native BNB");
        _settle(holder); Account storage a=accounts[holder]; amount=a.credit;
        if(amount==0) return 0;
        a.credit=0; totalClaimed+=amount; // A failed external payment atomically rolls these effects back.
        if(unwrapBNB) {
            IADDTaxWrapped(wrappedNative).withdraw(amount);
            (bool ok,)=payable(holder).call{value:amount,gas:30_000}(""); require(ok,"BNB payout failed");
        } else {
            IERC20Minimal asset=IERC20Minimal(rewardToken);
            uint256 beforeBalance=asset.balanceOf(address(this));
            asset.safeTransfer(holder,amount);
            uint256 afterBalance=asset.balanceOf(address(this));
            // Recipient-side transfer fees may reduce net receipt. A fee charged ON TOP to this sender
            // must not spend other holders' liabilities or queued rounds: roll back this payment instead.
            require(beforeBalance>=afterBalance && beforeBalance-afterBalance==amount,"Unexpected reward debit");
        }
        emit RewardClaimed(holder,amount,unwrapBNB);
    }
    receive() external payable { require(msg.sender==wrappedNative,"Only wrapped native"); }
}
