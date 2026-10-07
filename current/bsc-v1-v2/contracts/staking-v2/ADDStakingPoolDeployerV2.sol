// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDStakingPoolV2.sol";

/// @notice Stateless construction helper; keeps the combined tax/mining factory below
///         the EIP-3860 initcode limit. No registry, owner, upgrade or fund handling.
contract ADDStakingPoolDeployerV2 {
    function deployImplementation() external returns (address) {
        return address(new ADDStakingPoolV2(msg.sender));
    }
}
