// SPDX-License-Identifier: MIT
    /// @dev LOCAL IMPLEMENTATION: folder naming/API similarity does not establish OpenZeppelin provenance.
    /// @dev Include this exact source in review. No upstream audit or version equivalence is asserted.
pragma solidity ^0.8.20;

/**
 * Local Address + SafeERC20 utilities.
 * SafeERC20 supports tokens that:
 *  - return true/false
 *  - return nothing
 *  - revert on failure
 */

library Address {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function functionCall(address target, bytes memory data, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage)
        internal
        returns (bytes memory)
    {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function verifyCallResult(bool success, bytes memory returndata, string memory errorMessage)
        internal
        pure
        returns (bytes memory)
    {
        if (success) return returndata;
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}

/* Minimal interface used by SafeERC20 */
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from,address to,uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

library SafeERC20 {
    error SafeERC20FailedOperation(address token);
    error SafeERC20NonContract(address token);

    function safeTransfer(IERC20Minimal token, address to, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Minimal token, address from, address to, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20Minimal token, address spender, uint256 value) internal {
        _callOptionalReturn(address(token), abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    /**
     * Supports:
     *  - tokens that return (bool)
     *  - tokens that return nothing
     *  - revert on failure
     */
    function _callOptionalReturn(address token, bytes memory data) private {
        if (token.code.length == 0) revert SafeERC20NonContract(token);
        (bool success, bytes memory returndata) = token.call(data);
        if (!success) {
            if (returndata.length == 0) revert SafeERC20FailedOperation(token);
            assembly ("memory-safe") { revert(add(returndata, 32), mload(returndata)) }
        }
        if (returndata.length > 0) {
            // Tokens that return a boolean must not be false
            if (!abi.decode(returndata, (bool))) revert SafeERC20FailedOperation(token);
        }
    }
}
