// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./IADDPortalV1.sol";
import "./ADDVariableTokenV1.sol";
import "../openzeppelin/ReentrancyGuard.sol";

/// @notice Reference v1-compatible zero-tax factory. Portal's owner must approve it.
/// @dev Factory and clone implementation are non-upgradeable. Creator-bound salts
///      preserve ADD's 1111 suffix while keeping token creation/admission atomic.
contract ADDVariableFactoryV1 is ReentrancyGuard {
    address public immutable portal;
    address public immutable implementation;
    mapping(address => bool) public isCreatedToken;
    mapping(address => address) public creatorOf;
    bytes2 public constant tokenAddressSuffix = 0x1111;

    struct Launch {
        string name;
        string symbol;
        uint256 supply; // 18-decimal token base units; NOT a hard-coded billion.
        bytes32 salt; // First 20 bytes = creator; remaining 12 = vanity nonce.
        address expectedAddress;
        address quoteAsset;
        uint256 targetBNB;
        uint256 quoteTarget;
        uint256 deadline;
        bool customTarget;
        string metadataURI;
    }
    error InvalidPortal();
    error InvalidPreparedAddress();
    event TokenCreated(address indexed token,address indexed creator,uint256 supply);

    constructor(address portal_) {
        if (portal_.code.length == 0) revert InvalidPortal();
        portal = portal_;
        implementation = address(new ADDVariableTokenV1());
    }
    function portalFactoryVersion() external pure returns (uint256) { return 1; }

    /// @dev EIP-1167 55-byte init code, followed by an inert Portal domain. The
    ///      runtime always delegates to the same implementation (not upgradeable).
    function creationCode() public view returns (bytes memory) {
        return abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",implementation,
            hex"5af43d82803e903d91602b57fd5bf3",portal);
    }
    function getDeploymentInfo() external view returns (address,bytes32,bytes2) {
        return (address(this),keccak256(creationCode()),tokenAddressSuffix);
    }
    function predictToken(bytes32 salt) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),salt,keccak256(creationCode()))))));
    }

    /// @notice Supply, target and quote are signed creation inputs. No first buy is
    ///      hidden in creation: clients issue a separate Portal.buy after admission.
    function createToken(Launch calldata p) external nonReentrant returns (address token) {
        token = predictToken(p.salt);
        if (address(bytes20(p.salt)) != msg.sender || token != p.expectedAddress
            || uint16(uint160(token)) != uint16(tokenAddressSuffix)) revert InvalidPreparedAddress();
        bytes memory code = creationCode();
        bytes32 salt = p.salt;
        address created;
        assembly ("memory-safe") { created := create2(0,add(code,32),mload(code),salt) }
        if (created == address(0) || created != token) revert InvalidPreparedAddress();
        ADDVariableTokenV1(token).initialize(p.name,p.symbol,portal,p.supply);
        isCreatedToken[token] = true;
        creatorOf[token] = msg.sender;
        IADDPortalAdmissionV1(portal).registerFactoryToken(ADDAdmissionV1(
            token,msg.sender,p.quoteAsset,p.supply,p.targetBNB,p.quoteTarget,p.deadline,
            p.customTarget,true,p.metadataURI));
        emit TokenCreated(token,msg.sender,p.supply);
    }
}
