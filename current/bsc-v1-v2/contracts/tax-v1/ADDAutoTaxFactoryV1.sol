// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./ADDAutoTaxTokenV1.sol";

interface IADDAutoTaxPortalV1 { function router() external view returns (address); }

/// @notice New-V1 factory glue. Owner registers THIS factory in Portal once.
/// @dev Immutable implementations, no factory owner or upgrade path. A launch with
///      zero dividend allocation creates no dividend ledger. A positive allocation
///      creates one dedicated ledger atomically; failed admission rolls everything back.
contract ADDAutoTaxFactoryV1 is ReentrancyGuard {
    address public immutable portal;
    address public immutable router;
    address public immutable implementation;
    address public immutable dividendImplementation;
    bytes2 public constant tokenAddressSuffix = 0x1111;
    mapping(address => bool) public isCreatedToken;
    mapping(address => address) public creatorOf;
    mapping(address => address) public dividendOf;
    struct Launch {
        string name; string symbol; uint256 supply; bytes32 salt; address expectedAddress;
        address quoteAsset; uint256 targetBNB; uint256 quoteTarget; uint256 deadline;
        bool customTarget; string metadataURI;
    }
    event TokenCreated(address indexed token, address indexed creator, address indexed dividend, uint256 supply);
    constructor(address portal_) {
        require(portal_.code.length > 0,"Invalid Portal");
        portal = portal_; router = IADDAutoTaxPortalV1(portal_).router();
        require(router.code.length > 0,"Invalid router");
        implementation = address(new ADDAutoTaxTokenV1());
        dividendImplementation = address(new ADDClaimDividendV1());
    }
    function portalFactoryVersion() external pure returns (uint256) { return 1; }
    function creationCode() public view returns (bytes memory) {
        return abi.encodePacked(ADDTaxClones.code(implementation),portal);
    }
    function getDeploymentInfo() external view returns (address,bytes32,bytes2) {
        return (address(this),keccak256(creationCode()),tokenAddressSuffix);
    }
    function predictToken(bytes32 salt) public view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),salt,keccak256(creationCode()))))));
    }
    function createToken(Launch calldata p, ADDAutoTaxTokenV1.Config calldata c) external nonReentrant returns (address token) {
        require(block.timestamp <= p.deadline,"Launch expired");
        token = predictToken(p.salt);
        require(address(bytes20(p.salt)) == msg.sender && token == p.expectedAddress
            && uint16(uint160(token)) == uint16(tokenAddressSuffix),"Invalid prepared address");
        bytes memory code = creationCode(); bytes32 salt = p.salt; address created;
        assembly ("memory-safe") { created := create2(0,add(code,32),mload(code),salt) }
        require(created != address(0) && created == token,"Token creation failed");
        address ledger;
        if (c.dividendBps > 0) {
            ledger = ADDTaxClones.clone(dividendImplementation);
            address wrapped = IADDTaxRouter(router).WETH();
            address reward = c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Native ? wrapped
                : c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Self ? token : c.rewardToken;
            ADDClaimDividendV1(payable(ledger)).initialize(token,reward,wrapped,
                c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Native,c.minimumHolding);
        }
        address receiver = address(new ADDTaxSwapReceiverV1(token));
        ADDAutoTaxTokenV1(payable(token)).initialize(p.name,p.symbol,portal,router,p.supply,ledger,receiver,c);
        isCreatedToken[token] = true; creatorOf[token] = msg.sender; dividendOf[token] = ledger;
        IADDPortalAdmissionV1(portal).registerFactoryToken(ADDAdmissionV1(token,msg.sender,p.quoteAsset,p.supply,
            p.targetBNB,p.quoteTarget,p.deadline,p.customTarget,true,p.metadataURI));
        emit TokenCreated(token,msg.sender,ledger,p.supply);
    }
}
