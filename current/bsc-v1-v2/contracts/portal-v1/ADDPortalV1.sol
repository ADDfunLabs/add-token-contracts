// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDPortalRecoveryV1.sol";
import "./ADDPortalTradeModuleV1.sol";

/// @title ADD Portal v1 candidate: variable inventory and surplus-only recovery.
/// @notice Standard reference target is 4 BNB. Custom targets start at 1 BNB.
///         Half of the admitted inventory is sold at a fixed ratio; the original
///         other half and actual reserves are added to V2 when unsold sale units
///         fall STRICTLY BELOW 1% of the original admitted inventory.
/// @dev With even inventory this means strictly more than 98% of the sale half
///      is sold. The full reference target need not be reached. No proxy or upgrade
///      route exists. Existing v13 tokens/factories are not migrated by deployment.
contract ADDPortalV1 is ADDPortalRecoveryV1 {
    address public immutable tradeModule;
    error InvalidTradeModule();

    constructor(address owner_,address router_,address feeRecipient_,bool customEnabled,address tradeModule_)
        ADDPortalRecoveryV1(owner_,router_,feeRecipient_,customEnabled) {
        if (tradeModule_.code.length == 0 || ADDPortalTradeModuleV1(payable(tradeModule_)).router() != router_
            || ADDPortalTradeModuleV1(payable(tradeModule_)).DEPLOYMENT_VERSION() != 1) revert InvalidTradeModule();
        tradeModule = tradeModule_;
    }

    /// @dev Fixed selector dispatch, NOT an upgradeable proxy or an arbitrary-call
    ///      facility. The implementation enforces nonReentrant in the same ledger
    ///      storage. Deployment must verify the audited module bytecode, not just ABI.
    function buy(address,uint256,uint256) external payable returns (uint256) { _delegateTrade(); }
    function sell(address,uint256,uint256,uint256) external returns (uint256) { _delegateTrade(); }
    function _delegateTrade() private {
        address implementation = tradeModule;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr,0,calldatasize())
            let success := delegatecall(gas(),implementation,ptr,calldatasize(),0,0)
            returndatacopy(ptr,0,returndatasize())
            switch success
            case 0 { revert(ptr,returndatasize()) }
            default { return(ptr,returndatasize()) }
        }
    }
    /// @dev Called only by the fixed trade module executing in Portal's context.
    function executeAfterBuy(address token) external {
        if (msg.sender != address(this)) revert OnlySelf();
        _afterBuy(token);
    }

    function _graduationEligible(Pool storage p) internal view override returns (bool) {
        // Avoid a rounded-down threshold: for tiny/odd inventories compare the
        // exact ratio. Admission caps half at uint112, so multiplication is safe.
        return (p.saleAllocation - p.sold) * 100 < p.initialInventory;
    }
}
