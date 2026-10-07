// SPDX-License-Identifier: MIT
    /// @dev LOCAL IMPLEMENTATION: folder naming/API similarity does not establish OpenZeppelin provenance.
    /// @dev Include this exact source in review. No upstream audit or version equivalence is asserted.
pragma solidity ^0.8.20;

/**
 * Local ReentrancyGuard (OZ compatible).
 * Usage:
 *   function foo() external nonReentrant { ... }
 */
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}
