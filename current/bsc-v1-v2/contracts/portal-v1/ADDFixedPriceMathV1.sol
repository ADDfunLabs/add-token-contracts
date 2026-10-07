// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../FullMath.sol";

/// @notice Fixed-ratio arithmetic for variable inventory. All amounts are integers
///         in the corresponding asset's smallest units, never display prices.
library ADDFixedPriceMathV1 {
    /// @return tokens Token units bought, capped at the remaining sale allocation.
    /// @return principal Native units backing those tokens (rounded upward).
    /// @return fee The existing ADD 1% fee on the actual gross settled amount.
    /// @return refund Unused native payment; always returned to the buyer.
    /// @dev Retain v13 rounding when the full budget is used. Variable, potentially
    ///      tiny allocations may leave a rounding refund even before the last buy:
    ///      in that case charge only on actual settlement, never on returned money.
    function quoteNativeBuy(uint256 payment, uint256 remaining, uint256 allocation, uint256 target)
        internal pure returns (uint256 tokens, uint256 principal, uint256 fee, uint256 refund)
    {
        if (payment == 0 || remaining == 0) return (0, 0, 0, payment);
        fee = payment / 100;
        uint256 spendable = payment - fee;
        uint256 cost = FullMath.mulDivUp(remaining, target, allocation);
        if (spendable >= cost) {
            tokens = remaining;
            principal = cost;
        } else {
            tokens = FullMath.mulDiv(spendable, allocation, target);
            principal = FullMath.mulDivUp(tokens, target, allocation);
        }
        if (principal < spendable) fee = principal / 99;
        if (tokens == 0) fee = 0;
        refund = payment - principal - fee;
    }

    /// @notice Required backing for issued token units, using exact rational math.
    function costUp(uint256 tokens, uint256 allocation, uint256 target) internal pure returns (uint256) {
        return FullMath.mulDivUp(tokens, target, allocation);
    }

    /// @notice Asset amount returned on sale, before the existing BNB-denominated fee.
    function valueDown(uint256 tokens, uint256 allocation, uint256 target) internal pure returns (uint256) {
        return FullMath.mulDiv(tokens, target, allocation);
    }
}
