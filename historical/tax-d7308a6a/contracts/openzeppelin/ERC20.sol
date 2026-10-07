// SPDX-License-Identifier: MIT
    /// @dev LOCAL IMPLEMENTATION: folder naming/API similarity does not establish OpenZeppelin provenance.
    /// @dev Include this exact source in review. No upstream audit or version equivalence is asserted.
pragma solidity ^0.8.20;

/**
 * Local, self-contained ERC20 implementation (OZ v5-style).
 * Includes IERC20, IERC20Metadata, Context, and ERC20 with _update hook,
 * plus increaseAllowance/decreaseAllowance helpers.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external pure returns (uint8);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * ERC20 with OZ v5-style internal hook `_update(from, to, value)`.
 * - 18 decimals fixed
 * - name/symbol set by constructor or the derived token's one-time initializer
 * - includes increaseAllowance / decreaseAllowance helpers
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;

    uint8 private constant _DECIMALS = 18;

    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory name_, string memory symbol_) {
        _initializeMetadata(name_, symbol_);
    }

    /// @dev Internal only. Derived clone tokens must enforce a one-time, authorized initialization gate.
    function _initializeMetadata(string memory name_, string memory symbol_) internal {
        _name = name_;
        _symbol = symbol_;
    }

    /*//////////////////////////////////////////////////////////////
                               METADATA
    //////////////////////////////////////////////////////////////*/

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure virtual override returns (uint8) {
        return _DECIMALS;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC20 VIEWS
    //////////////////////////////////////////////////////////////*/

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSFERS
    //////////////////////////////////////////////////////////////*/

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL CORE
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, uint256 value) internal virtual {
        require(from != address(0), "ERC20: transfer from zero");
        require(to != address(0),   "ERC20: transfer to zero");
        _update(from, to, value);
    }

    /**
     * Core accounting hook (OZ v5 style):
     * - (from == 0)  => mint
     * - (to == 0)    => burn
     * - otherwise    => transfer
     *
     * Can be overridden in derived contracts to add gating logic BEFORE calling super._update.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // mint
            _totalSupply += value;
            _balances[to] += value;
            emit Transfer(address(0), to, value);
        } else if (to == address(0)) {
            // burn
            uint256 fromBal = _balances[from];
            require(fromBal >= value, "ERC20: burn exceeds balance");
            unchecked {
                _balances[from] = fromBal - value;
            }
            _totalSupply -= value;
            emit Transfer(from, address(0), value);
        } else {
            // transfer
            uint256 fromBal = _balances[from];
            require(fromBal >= value, "ERC20: transfer exceeds balance");
            unchecked {
                _balances[from] = fromBal - value;
                _balances[to] += value;
            }
            emit Transfer(from, to, value);
        }
    }

    function _mint(address to, uint256 value) internal virtual {
        require(to != address(0), "ERC20: mint to zero");
        _update(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal virtual {
        require(from != address(0), "ERC20: burn from zero");
        _update(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal virtual {
        require(owner != address(0), "ERC20: approve from zero");
        require(spender != address(0), "ERC20: approve to zero");
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender];
        // Every spender, including Portal, must have enough allowance. An infinite approval
        // only skips decrementing the allowance; it never skips the sufficiency check.
        require(currentAllowance >= value, "ERC20: insufficient allowance");
        if (currentAllowance != type(uint256).max) {
            unchecked {
                _allowances[owner][spender] = currentAllowance - value;
            }
        }
    }
}
