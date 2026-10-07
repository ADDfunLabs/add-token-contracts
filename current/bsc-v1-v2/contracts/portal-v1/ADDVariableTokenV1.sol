// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../openzeppelin/ERC20.sol";

/// @notice Candidate zero-transfer-tax template with per-creation supply.
/// @dev Immutable EIP-1167 implementation; no owner, mint, tax or upgrade setter.
///      The local ERC20 implementation must be included in the audit scope.
contract ADDVariableTokenV1 is ERC20 {
    address public immutable initializationFactory;
    address public portal;
    address public pair;
    uint256 public initialSupply;
    enum Phase { AwaitingAdmission, Active, Migrating, Graduated, RefundOnly, Refunded }
    Phase public phase;
    bool private initialized;
    bool private minted;

    error OnlyFactory();
    error OnlyPortal();
    error InvalidLifecycle();
    error InvalidToken();
    error PoolTransfersLocked();
    error UsePortalToSell();

    event PhaseChanged(Phase phase);

    constructor() ERC20("", "") {
        initializationFactory = msg.sender;
        initialized = true; // Lock the implementation; clones have fresh storage.
    }

    function portalTokenVersion() external pure returns (uint256) { return 1; }

    /// @notice Mint the creator-selected amount exactly once, directly to Portal.
    function initialize(string calldata name_,string calldata symbol_,address portal_,uint256 supply) external {
        if (msg.sender != initializationFactory) revert OnlyFactory();
        if (initialized || portal_.code.length == 0 || supply < 2
            || bytes(name_).length == 0 || bytes(name_).length > 128
            || bytes(symbol_).length == 0 || bytes(symbol_).length > 32) revert InvalidToken();
        initialized = true;
        portal = portal_;
        initialSupply = supply;
        _initializeMetadata(name_,symbol_);
        _mint(portal_,supply);
    }

    modifier onlyPortal() {
        if (msg.sender != portal) revert OnlyPortal();
        _;
    }

    function onPortalAdmission(address pair_) external onlyPortal {
        if (!initialized || phase != Phase.AwaitingAdmission || pair_.code.length == 0) revert InvalidLifecycle();
        pair = pair_;
        phase = Phase.Active;
        emit PhaseChanged(phase);
    }

    /// @notice Portal supplies the verified final pair, including owner-authorized
    ///         alternative-asset graduation. This change rolls back if migration fails.
    function onPortalMigrationStart(address pair_) external onlyPortal {
        if (phase != Phase.Active || pair_.code.length == 0) revert InvalidLifecycle();
        pair = pair_;
        phase = Phase.Migrating;
        emit PhaseChanged(phase);
    }

    function onPortalGraduation() external onlyPortal {
        if (phase != Phase.Migrating) revert InvalidLifecycle();
        phase = Phase.Graduated;
        emit PhaseChanged(phase);
    }

    function onPortalRefundStart() external onlyPortal {
        if (phase != Phase.Active) revert InvalidLifecycle();
        phase = Phase.RefundOnly;
        emit PhaseChanged(phase);
    }

    function onPortalRefundComplete() external onlyPortal {
        if (phase != Phase.RefundOnly) revert InvalidLifecycle();
        phase = Phase.Refunded;
        emit PhaseChanged(phase);
    }

    /// @dev Conventional V2/V3 detection is a heuristic, not a universal prohibition
    ///      of third-party markets (constructors and custom vaults can evade it).
    ///      Fixed output buffers prevent adversarial getters causing return-data bombs.
    function isRestrictedPool(address account) public view returns (bool) {
        if (account == pair && account != address(0)) return true;
        if (account == portal || account.code.length == 0) return false;
        return _referencesToken(account,0x0dfe1681) || _referencesToken(account,0xd21220a7);
    }

    function _referencesToken(address account,uint32 selector) private view returns (bool matches) {
        uint256 token = uint160(address(this));
        assembly ("memory-safe") {
            let scratch := mload(0x40)
            mstore(scratch,shl(224,selector))
            let ok := staticcall(12000,account,scratch,4,scratch,32)
            matches := and(and(ok,eq(returndatasize(),32)),eq(mload(scratch),token))
        }
    }

    function _update(address from,address to,uint256 amount) internal override {
        if (from == address(0)) {
            if (!initialized || minted || msg.sender != initializationFactory
                || to != portal || amount != initialSupply) revert InvalidToken();
            minted = true;
        } else {
            if (to == address(0) || to == address(this)) revert InvalidToken();
            if (to == portal && msg.sender != portal) revert UsePortalToSell();
            if (phase == Phase.AwaitingAdmission) revert InvalidLifecycle();
            if ((phase == Phase.Active || phase == Phase.RefundOnly || phase == Phase.Refunded)
                && (isRestrictedPool(from) || isRestrictedPool(to))) revert PoolTransfersLocked();
            if (phase == Phase.Migrating && (from != portal || to != pair)) revert InvalidLifecycle();
        }
        super._update(from,to,amount);
    }
}
