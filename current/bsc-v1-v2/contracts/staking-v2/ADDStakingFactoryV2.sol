// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ADDStakingPoolV2.sol";

/// @title ADD immutable staking pool factory V2
/// @notice 无 owner、手续费修改或升级权限；每个矿池独立保管本金与预付奖励。
/// @dev The immutable implementation is an EIP-1167 clone target, NOT an upgradeable
///      proxy. Creation transfers caller-owned rewards then initializes atomically.
contract ADDStakingFactoryV2 is ReentrancyGuard {
    using SafeERC20 for IERC20Minimal;
    address public immutable wrappedNative;
    uint256 public constant VERSION = 2;
    address public immutable implementation;
    mapping(address => bool) public isPool;
    address[] private pools;
    mapping(address => address[]) private creatorPools;
    struct CreateParams {
        ADDStakingPoolV2.PrincipalLock principalLock;
        address rewardToken;
        address stakingAsset; // address(0) native, reward token itself, USDT, or custom ERC20.
        uint256 rewardAmount;
        uint256 minimumReceived;
        uint256 durationSeconds;
        uint256 halvingIntervalSeconds; // Both zero = disabled.
        uint8 halvingCount;
    }
    event PoolCreated(address indexed pool, address indexed creator, address indexed rewardToken,
        address stakingAsset, uint256 requested, uint256 received, uint256 durationSeconds,
        uint256 halvingIntervalSeconds, uint8 halvingCount);

    constructor(address wrappedNative_) {
        require(wrappedNative_.code.length > 0, "Invalid native wrapper");
        wrappedNative = wrappedNative_;
        implementation = address(new ADDStakingPoolV2(address(this)));
    }

    /// @notice 先向工厂授权矿币。募集/内盘/毕业与本工厂无关联，无需 Portal 登记。
    function createPool(CreateParams calldata p) external nonReentrant returns (address pool) {
        require(p.rewardToken.code.length > 0 && p.rewardAmount > 0, "Invalid rewards");
        bytes memory creation = abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation, hex"5af43d82803e903d91602b57fd5bf3");
        assembly ("memory-safe") { pool := create(0, add(creation, 32), mload(creation)) }
        require(pool != address(0), "Clone creation failed");
        ADDStakingPoolV2(payable(pool)).configurePrincipalLock(p.principalLock);
        uint256 beforeBalance = IERC20Minimal(p.rewardToken).balanceOf(pool);
        IERC20Minimal(p.rewardToken).safeTransferFrom(msg.sender, pool, p.rewardAmount);
        uint256 received = IERC20Minimal(p.rewardToken).balanceOf(pool) - beforeBalance;
        require(received >= p.minimumReceived, "Insufficient initial rewards");
        ADDStakingPoolV2(payable(pool)).initialize(msg.sender, p.rewardToken, p.stakingAsset,
            wrappedNative, received, p.durationSeconds, p.halvingIntervalSeconds, p.halvingCount);
        isPool[pool] = true; pools.push(pool); creatorPools[msg.sender].push(pool);
        emit PoolCreated(pool, msg.sender, p.rewardToken, p.stakingAsset, p.rewardAmount, received,
            p.durationSeconds, p.halvingIntervalSeconds, p.halvingCount);
    }

    function poolCount() external view returns (uint256) { return pools.length; }
    function poolAt(uint256 index) external view returns (address) { return pools[index]; }
    function creatorPoolCount(address creator) external view returns (uint256) { return creatorPools[creator].length; }
    struct CycleParams {
        ADDStakingPoolV2.PrincipalLock principalLock;
        address rewardAsset; // zero = BNB; ERC20 otherwise.
        address stakingAsset;
        uint16 cycleDays;
        uint256 initialRewardAmount; // zero allowed: wait for tax income.
        uint256 minimumReceived;
    }
    event CyclePoolCreated(address indexed pool, address indexed creator, address indexed rewardAsset,
        address stakingAsset, uint16 cycleDays, uint256 initialRewards);

    function createCyclePool(CycleParams calldata p) external payable nonReentrant returns (address pool) {
        require(p.rewardAsset == address(0) ? msg.value == p.initialRewardAmount : msg.value == 0, "Wrong initial native value");
        bytes memory creation = abi.encodePacked(hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            implementation, hex"5af43d82803e903d91602b57fd5bf3");
        assembly ("memory-safe") { pool := create(0, add(creation, 32), mload(creation)) }
        require(pool != address(0), "Clone creation failed");
        ADDStakingPoolV2(payable(pool)).configurePrincipalLock(p.principalLock);
        ADDStakingPoolV2 mining = ADDStakingPoolV2(payable(pool));
        mining.initializeCycle(msg.sender, p.rewardAsset, p.stakingAsset, wrappedNative, p.cycleDays);
        uint256 received;
        if (p.initialRewardAmount != 0) {
            if (p.rewardAsset == address(0)) received = mining.fundCycle{value:msg.value}(msg.value, p.minimumReceived);
            else {
                uint256 beforeBalance = IERC20Minimal(p.rewardAsset).balanceOf(pool);
                IERC20Minimal(p.rewardAsset).safeTransferFrom(msg.sender, pool, p.initialRewardAmount);
                received = IERC20Minimal(p.rewardAsset).balanceOf(pool) - beforeBalance;
                require(received > 0 && received <= mining.MAX_AMOUNT(), "Invalid initial cycle funding");
                mining.checkpoint();
            }
        }
        require(received >= p.minimumReceived, "Insufficient initial rewards");
        isPool[pool] = true; pools.push(pool); creatorPools[msg.sender].push(pool);
        emit CyclePoolCreated(pool,msg.sender,p.rewardAsset,p.stakingAsset,p.cycleDays,received);
    }
    function getPools(uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _page(pools, offset, limit);
    }
    function getCreatorPools(address creator, uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _page(creatorPools[creator], offset, limit);
    }
    function _page(address[] storage source, uint256 offset, uint256 limit) private view returns (address[] memory result) {
        require(limit <= 100, "Page limit exceeds 100");
        uint256 size = offset >= source.length ? 0 : source.length - offset;
        if (size > limit) size = limit;
        result = new address[](size);
        for (uint256 i; i < size; ++i) result[i] = source[offset + i];
    }
}
