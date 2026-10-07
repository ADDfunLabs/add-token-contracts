// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDPortalLedgerV1.sol";
import "./ADDPortalConversionV1.sol";

/// @notice Candidate migration mechanics, independent of the graduation trigger.
/// @dev The concrete eligibility policy is deliberately a separate override. This
///      abstract module is NOT a deployable Portal or an authorization to graduate.
abstract contract ADDPortalLiquidityV1 is ADDPortalLedgerV1 {
    using SafeERC20 for IERC20Minimal;
    ADDPortalConversionV1 public immutable recoveryConverter;
    error NotReadyToGraduate();
    error InvalidLiquidity();
    error InsufficientMigrationGas();
    event GraduationFailed(address indexed token,bytes4 reasonSelector);
    event Graduated(address indexed token,address indexed pair,address quoteAsset,
        uint256 tokensAdded,uint256 quoteAdded,uint256 lpBurned,uint256 unsoldRetained);

    // Original quoteAsset/quoteTarget remain the immutable fundraising denomination.
    // These fields record the actual successful settlement, which may be different.
    struct Settlement { address quoteAsset; uint256 quoteAmount; }
    mapping(address => Settlement) public graduationSettlement;

    constructor(address owner_,address router_,address feeRecipient_,bool customEnabled)
        ADDPortalLedgerV1(owner_,router_,feeRecipient_,customEnabled) {
        recoveryConverter = new ADDPortalConversionV1(router_);
    }

    function canGraduate(address token) public view returns (bool) {
        Pool storage p = pools[token];
        return (p.phase == Phase.Active || p.phase == Phase.GraduationFailed)
            && p.reserve > 0 && _graduationEligible(p);
    }

    /// @notice Anyone may pay gas to finish an eligible pool; callers cannot choose
    ///      the amounts, recipient, pair or price and receive no assets or bounty.
    function graduate(address token) external nonReentrant {
        if (!canGraduate(token)) revert NotReadyToGraduate();
        _attemptGraduation(token);
    }

    function _afterBuy(address token) internal {
        if (canGraduate(token)) _attemptGraduation(token);
    }

    /// @dev Only entered by a guarded buy/graduate via this contract's self-call.
    ///      A separate call frame lets migration roll back WITHOUT undoing the final
    ///      purchase, its token delivery, fee, and excess-payment refund.
    function executeGraduation(address token) external {
        if (msg.sender != address(this)) revert OnlySelf();
        if (!canGraduate(token)) revert NotReadyToGraduate();
        _graduate(token);
    }

    function _attemptGraduation(address token) internal {
        bytes memory payload = abi.encodeCall(this.executeGraduation,(token));
        // Keep gas for recording failure and the outer ledger's backing checks.
        // Do not copy arbitrary revert bytes from untrusted external token hooks.
        uint256 available = gasleft();
        if (available < 250000) revert InsufficientMigrationGas();
        uint256 forwarded = available - 150000;
        bool success;
        bytes4 reason;
        assembly ("memory-safe") {
            success := call(forwarded,address(),0,add(payload,32),mload(payload),0,0)
            if iszero(success) {
                let scratch := mload(0x40)
                mstore(scratch,0)
                if gt(returndatasize(),3) { returndatacopy(scratch,0,4) }
                reason := mload(scratch)
            }
        }
        if (!success) {
            pools[token].phase = Phase.GraduationFailed;
            emit GraduationFailed(token,reason);
        }
        // A failed attempt is not proof of permanent failure: it may be transient
        // or gas-related. Anyone may retry the original pair using graduate().
    }

    function _graduate(address token) internal {
        Pool storage p = pools[token];
        _assertPoolBacking(token);
        uint256 reserve = p.reserve;
        address quoteAsset = p.quoteAsset;
        _requireEmptyPair(p.pair,token,quoteAsset);
        _beginGraduation(token,p.pair);
        if (quoteAsset == address(0)) _wrapNative(reserve);
        _supplyLiquidity(token,quoteAsset,reserve);
    }

    function _requireEmptyPair(address pair,address token,address quoteAsset) internal view {
        address asset = quoteAsset == address(0) ? wrappedNative : quoteAsset;
        // Arbitrary external tokens can trade before admission or permit somebody
        // to initialize this pair early. Never donate customer reserves to existing
        // LP owners. Such a token is NOT compatible with this migration protocol.
        recoveryConverter.assertEmptyPair(token,asset,pair);
    }

    /// @dev Called inside the same atomic frame as conversion and LP minting.
    ///      Only this project's obligations are released; every failure restores them.
    function _beginGraduation(address token,address pair) internal {
        Pool storage p = pools[token];
        uint256 reserve = p.reserve;
        p.phase = Phase.Migrating;
        p.pair = pair;
        p.reserve = 0;
        // Release only THIS sale's obligations. Unsold sale units physically stay
        // in Portal as surplus; the original LP half alone goes to the pair.
        protectedERC20[token] -= p.liquidityAllocation + p.saleAllocation - p.sold;
        if (p.quoteAsset == address(0)) totalNativeReserved -= reserve;
        else protectedERC20[p.quoteAsset] -= reserve;
        if (p.lifecycleHooks) IADDPortalTokenHooksV1(token).onPortalMigrationStart(pair);
    }

    function _wrapNative(uint256 amount) internal {
        uint256 beforeWrapped = IERC20Minimal(wrappedNative).balanceOf(address(this));
        IADDWrappedNativeV1(wrappedNative).deposit{value:amount}();
        if (IERC20Minimal(wrappedNative).balanceOf(address(this)) != beforeWrapped + amount) revert UnsupportedTransfer();
    }

    /// @dev For native settlement, caller has already wrapped this project's BNB.
    ///      Recheck the pair after all hooks/swaps, before delivering any LP assets.
    function _supplyLiquidity(address token,address quoteAsset,uint256 reserve) internal {
        Pool storage p = pools[token];
        address asset = quoteAsset == address(0) ? wrappedNative : quoteAsset;
        uint256 lpInventory = p.liquidityAllocation;
        this.executeApproval(asset,address(recoveryConverter),reserve);
        this.executeApproval(token,address(recoveryConverter),lpInventory);
        uint256 liquidity = recoveryConverter.mintLiquidity(token,asset,p.pair,lpInventory,reserve);
        this.executeApproval(asset,address(recoveryConverter),0);
        this.executeApproval(token,address(recoveryConverter),0);
        p.phase = Phase.Graduated;
        graduationSettlement[token] = Settlement(quoteAsset,reserve);
        if (p.lifecycleHooks) IADDPortalTokenHooksV1(token).onPortalGraduation();
        _assertPoolBacking(token);
        if (IERC20Minimal(asset).balanceOf(address(this)) < protectedERC20[asset]) revert InsufficientBacking();
        emit Graduated(token,p.pair,quoteAsset,lpInventory,reserve,liquidity,p.saleAllocation-p.sold);
    }

    function _graduationEligible(Pool storage p) internal view virtual returns (bool);
}
