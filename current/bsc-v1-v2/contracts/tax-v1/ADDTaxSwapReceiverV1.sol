// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../openzeppelin/SafeERC20.sol";

/// @notice V2 output transit only. A V2 pair forbids its token0/token1 as swap recipients,
///         so tax-token -> quote swaps cannot send their output directly to the tax token.
/// @dev No tax/accounting decisions, approvals, owner, arbitrary recipient or upgrade.
///      The factory creates one receiver per token; only that token may collect to itself.
contract ADDTaxSwapReceiverV1 {
    using SafeERC20 for IERC20Minimal;
    address public immutable token;
    constructor(address token_) { require(token_.code.length > 0, "Invalid token"); token = token_; }
    function collect(address asset, uint256 amount) external {
        require(msg.sender == token, "Only bound token");
        IERC20Minimal(asset).safeTransfer(token, amount);
    }
}
