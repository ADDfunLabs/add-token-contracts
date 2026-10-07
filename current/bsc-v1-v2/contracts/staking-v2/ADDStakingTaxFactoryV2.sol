// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../tax-v1/ADDAutoTaxFactoryV1.sol";
import "./ADDStakingPoolDeployerV2.sol";

/// @notice ADD 新税收发行入口：一笔交易创建代币和无owner循环矿池。
/// @dev The inherited ordinary createToken path remains available. This is a NEW
///      factory candidate, not an upgrade of the already-deployed factory. Portal
///      must register this address before it can launch tokens. Mining starts only
///      after graduation and uses the final quote/LP, including recovery graduation.
contract ADDStakingTaxFactoryV2 is ADDAutoTaxFactoryV1 {
    address public immutable stakingImplementation;
    mapping(address => address) public stakingOf;
    mapping(address => bool) public isStakingPool;
    address[] private stakingPools;
    mapping(address => address[]) private creatorStakingPools;
    struct StakingConfig { ADDStakingPoolV2.PrincipalLock principalLock; uint16 cycleDays; uint8 stakeMode; address customStake; }
    event TokenStakingCreated(address indexed token, address indexed pool, address indexed creator,
        uint16 cycleDays, uint8 stakeMode, address customStake);

    /// @dev Deploy ADDStakingPoolDeployerV2 first and verify its compiled bytecode.
    ///      The helper merely constructs an implementation whose initialization authority
    ///      is this factory. There are no later calls or trust/upgrade permissions to it.
    constructor(address portal_, address poolDeployer_) ADDAutoTaxFactoryV1(portal_) {
        require(poolDeployer_.code.length > 0, "Invalid staking deployer");
        address deployed = ADDStakingPoolDeployerV2(poolDeployer_).deployImplementation();
        require(deployed.code.length > 0 && ADDStakingPoolV2(payable(deployed)).initializationFactory() == address(this),
            "Wrong staking implementation");
        stakingImplementation = deployed;
    }

    function createTokenWithStaking(Launch calldata p, ADDAutoTaxTokenV1.Config calldata requested,
        StakingConfig calldata s) external nonReentrant returns (address token, address miningPool) {
        require(block.timestamp <= p.deadline, "Launch expired");
        require(requested.marketingBps > 0, "Mining needs marketing allocation");
        token = predictToken(p.salt);
        require(address(bytes20(p.salt)) == msg.sender && token == p.expectedAddress
            && uint16(uint160(token)) == uint16(tokenAddressSuffix), "Invalid prepared address");
        bytes memory code = creationCode(); bytes32 salt = p.salt; address created;
        assembly ("memory-safe") { created := create2(0,add(code,32),mload(code),salt) }
        require(created == token && created != address(0), "Token creation failed");

        address wrapped = IADDTaxRouter(router).WETH();
        miningPool = ADDTaxClones.clone(stakingImplementation);
        ADDStakingPoolV2(payable(miningPool)).configurePrincipalLock(s.principalLock);
        ADDAutoTaxTokenV1.Config memory c = requested;
        c.marketingWallet = miningPool; // The marketing share is the mining income.

        address dividend;
        if (c.dividendBps > 0) {
            dividend = ADDTaxClones.clone(dividendImplementation);
            address reward = c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Native ? wrapped
                : c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Self ? token : c.rewardToken;
            ADDClaimDividendV1(payable(dividend)).initialize(token,reward,wrapped,
                c.rewardMode == ADDAutoTaxTokenV1.RewardMode.Native,c.minimumHolding);
        }
        address receiver = address(new ADDTaxSwapReceiverV1(token));
        ADDAutoTaxTokenV1(payable(token)).initialize(p.name,p.symbol,portal,router,p.supply,dividend,receiver,c);
        isCreatedToken[token] = true; creatorOf[token] = msg.sender; dividendOf[token] = dividend;
        stakingOf[token] = miningPool; isStakingPool[miningPool] = true;
        stakingPools.push(miningPool); creatorStakingPools[msg.sender].push(miningPool);
        IADDPortalAdmissionV1(portal).registerFactoryToken(ADDAdmissionV1(token,msg.sender,p.quoteAsset,p.supply,
            p.targetBNB,p.quoteTarget,p.deadline,p.customTarget,true,p.metadataURI));
        ADDStakingPoolV2(payable(miningPool)).initializeLinkedCycle(msg.sender,token,wrapped,
            s.cycleDays,s.stakeMode,s.customStake);
        emit TokenCreated(token,msg.sender,dividend,p.supply);
        emit TokenStakingCreated(token,miningPool,msg.sender,s.cycleDays,s.stakeMode,s.customStake);
    }

    function stakingPoolCount() external view returns (uint256) { return stakingPools.length; }
    function getStakingPools(address creator_, uint256 offset, uint256 limit) external view returns (address[] memory result) {
        require(limit <= 100, "Page limit exceeds 100");
        address[] storage source = creator_ == address(0) ? stakingPools : creatorStakingPools[creator_];
        uint256 size = offset >= source.length ? 0 : source.length-offset;
        if(size > limit) size = limit;
        result = new address[](size);
        for(uint256 i; i<size; ++i) result[i]=source[offset+i];
    }
}
