// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Ownership and enumerable factory admission for the candidate ADD Portal v1.
/// @notice Removing a factory revokes FUTURE admissions only. A derived Portal must
///         never gate an already admitted token's buys/sells on its factory membership.
/// @dev This is a standalone, non-upgradeable module. There is no delegatecall,
///      implementation slot, renounce-owner function, or automatic token admission.
abstract contract ADDPortalAccessV1 {
    error OnlyOwner();
    error OnlyPendingOwner();
    error InvalidOwner();
    error InvalidFactory();
    error FactoryAlreadySupported();
    error FactoryNotSupported();

    address public owner;
    address public pendingOwner;
    address[] private supportedFactories;
    // Index + 1; zero denotes absence. Swap-and-pop does not preserve list order.
    mapping(address => uint256) private factoryIndex;
    mapping(address => bytes32) public factoryCodeHash;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferCancelled(address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FactoryAdded(address indexed factory, bytes32 codeHash);
    event FactoryRemoved(address indexed factory);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address initialOwner) {
        if (initialOwner == address(0) || initialOwner == address(this)) revert InvalidOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Propose a successor; ownership stays with the current owner until acceptance.
    /// @dev The successor may be an EOA or multisig. No private key is required by this contract.
    function transferOwnership(address successor) external onlyOwner {
        if (successor == address(0) || successor == address(this) || successor == owner) revert InvalidOwner();
        pendingOwner = successor;
        emit OwnershipTransferStarted(owner, successor);
    }

    function cancelOwnershipTransfer() external onlyOwner {
        address cancelled = pendingOwner;
        delete pendingOwner;
        emit OwnershipTransferCancelled(cancelled);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner || pendingOwner == address(0)) revert OnlyPendingOwner();
        address previous = owner;
        owner = msg.sender;
        delete pendingOwner;
        emit OwnershipTransferred(previous, msg.sender);
    }

    /// @notice Approve a reviewed factory for future admission calls.
    /// @dev Code existence/hash pinning is NOT proof of safe factory behavior. In
    ///      particular an upgradeable factory can change logic without changing its
    ///      proxy code hash. Ownership is explicitly trusted to review admissions.
    function addFactory(address factory) external onlyOwner {
        if (factory == address(this) || factory.code.length == 0) revert InvalidFactory();
        if (factoryIndex[factory] != 0) revert FactoryAlreadySupported();
        _validateFactory(factory);
        supportedFactories.push(factory);
        factoryIndex[factory] = supportedFactories.length;
        factoryCodeHash[factory] = factory.codehash;
        emit FactoryAdded(factory, factory.codehash);
    }

    /// @notice Remove permission to add NEW pools; existing pools are not deleted or repriced.
    function removeFactory(address factory) external onlyOwner {
        uint256 slot = factoryIndex[factory];
        if (slot == 0) revert FactoryNotSupported();
        uint256 last = supportedFactories.length;
        if (slot != last) {
            address moved = supportedFactories[last - 1];
            supportedFactories[slot - 1] = moved;
            factoryIndex[moved] = slot;
        }
        supportedFactories.pop();
        delete factoryIndex[factory];
        delete factoryCodeHash[factory];
        emit FactoryRemoved(factory);
    }

    function isFactorySupported(address factory) public view returns (bool) {
        return factoryIndex[factory] != 0;
    }

    /// @notice Enumerate all currently approved addresses. Order changes on removal.
    function getSupportedFactories() external view returns (address[] memory) {
        return supportedFactories;
    }

    function supportedFactoryCount() external view returns (uint256) {
        return supportedFactories.length;
    }

    function _requireFactory(address factory) internal view {
        if (!isFactorySupported(factory) || factory.codehash != factoryCodeHash[factory]) revert FactoryNotSupported();
    }

    /// @dev The concrete Portal checks the factory's interface version and Portal binding here.
    function _validateFactory(address factory) internal view virtual;
}
