# BSC production contract address index / BSC 现行合约地址索引

Network: BNB Smart Chain mainnet, chain ID **56**. This index records the 17 protocol roles in the V1/V2 source publication. Addresses do not change when another token or mining pool is created.

网络：BNB Smart Chain 主网，链 ID **56**。本索引记录公开包中的 17 个 V1/V2 角色；后续创建的代币、分红合约和矿池另有自己的地址。

The [manifest](../manifest.json) lists every runtime hash. Each role links to deployment metadata containing the original compiler input, ABI, constructor arguments, and immutable bindings. Browser verification is recorded separately in `sourceVerification`; an offline match alone does not imply that BscScan has accepted the source.

[manifest](../manifest.json) 记录每个角色的运行时代码哈希；下方部署元数据记录原编译输入、ABI、构造参数和不可变量绑定。浏览器验证结果单独见 `sourceVerification`，离线复现通过不等于浏览器已经验证。

## Portal trade module V1 / Portal 交易模块 V1

- Role / 角色：`tradeModule`
- Address / 地址：[`0x98541696049c8d93b8d679ad61ff1ec6d7253ed1`](https://bscscan.com/address/0x98541696049c8d93b8d679ad61ff1ec6d7253ed1#code)
- Source / 源码：[ADDPortalTradeModuleV1](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalTradeModuleV1.sol)
- Deployment record / 部署记录：[deployments/tradeModule.json](../current/bsc-v1-v2/deployments/tradeModule.json)
- Constructor arguments / 构造参数：address: `0x10ED43C718714eb63d5aA57B78B54704E256024E`

## Main Portal V1 / 主 Portal V1

- Role / 角色：`portal`
- Address / 地址：[`0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b`](https://bscscan.com/address/0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b#code)
- Source / 源码：[ADDPortalV1](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalV1.sol)
- Deployment record / 部署记录：[deployments/portal.json](../current/bsc-v1-v2/deployments/portal.json)
- Constructor arguments / 构造参数：address: `0x100Ce91060CB9C9381949364F3304Fa350F13adD`, address: `0x10ED43C718714eb63d5aA57B78B54704E256024E`, address: `0xCb1D21591759E67E93D5054CaEbb5e972229DADd`, bool: `true`, address: `0x98541696049c8D93B8d679ad61FF1Ec6D7253Ed1`

## Variable-supply zero-transfer-tax factory V1 / 可变发行量零转账税工厂 V1

- Role / 角色：`standardFactory`
- Address / 地址：[`0xeca7b035890d44a6b8da97d932509baaade2b71c`](https://bscscan.com/address/0xeca7b035890d44a6b8da97d932509baaade2b71c#code)
- Source / 源码：[ADDVariableFactoryV1](../current/bsc-v1-v2/contracts/portal-v1/ADDVariableFactoryV1.sol)
- Deployment record / 部署记录：[deployments/standardFactory.json](../current/bsc-v1-v2/deployments/standardFactory.json)
- Constructor arguments / 构造参数：address: `0x933BC9fe78c9BEAEdC5a82Bd24B5359d01E8FD7B`

## Automatic-tax factory V1 / 自动税收工厂 V1

- Role / 角色：`taxFactory`
- Address / 地址：[`0x05b37ad7b5ec4af77eeb9527d49b078223bfa911`](https://bscscan.com/address/0x05b37ad7b5ec4af77eeb9527d49b078223bfa911#code)
- Source / 源码：[ADDAutoTaxFactoryV1](../current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxFactoryV1.sol)
- Deployment record / 部署记录：[deployments/taxFactory.json](../current/bsc-v1-v2/deployments/taxFactory.json)
- Constructor arguments / 构造参数：address: `0x933BC9fe78c9BEAEdC5a82Bd24B5359d01E8FD7B`

## Trade module quote helper / 交易模块报价辅助合约

- Role / 角色：`tradeQuoter`
- Address / 地址：[`0x1c0720483ef21f0e5da8fa0daec27eeedbe50f92`](https://bscscan.com/address/0x1c0720483ef21f0e5da8fa0daec27eeedbe50f92#code)
- Source / 源码：[ADDPortalQuoterV1](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalQuoterV1.sol)
- Deployment record / 部署记录：[deployments/tradeQuoter.json](../current/bsc-v1-v2/deployments/tradeQuoter.json)
- Constructor arguments / 构造参数：address: `0x10ED43C718714eb63d5aA57B78B54704E256024E`

## Portal quote helper / Portal 报价辅助合约

- Role / 角色：`quoter`
- Address / 地址：[`0x0d334b708273ff378a6c2905d9020ce20d739904`](https://bscscan.com/address/0x0d334b708273ff378a6c2905d9020ce20d739904#code)
- Source / 源码：[ADDPortalQuoterV1](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalQuoterV1.sol)
- Deployment record / 部署记录：[deployments/quoter.json](../current/bsc-v1-v2/deployments/quoter.json)
- Constructor arguments / 构造参数：address: `0x10ED43C718714eb63d5aA57B78B54704E256024E`

## Graduation recovery converter / 备用毕业兑换辅助合约

- Role / 角色：`converter`
- Address / 地址：[`0x9542794b73b25afd390b5ca07d628083c7d40456`](https://bscscan.com/address/0x9542794b73b25afd390b5ca07d628083c7d40456#code)
- Source / 源码：[ADDPortalConversionV1](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalConversionV1.sol)
- Deployment record / 部署记录：[deployments/converter.json](../current/bsc-v1-v2/deployments/converter.json)
- Constructor arguments / 构造参数：address: `0x10ED43C718714eb63d5aA57B78B54704E256024E`

## Zero-transfer-tax token template / 零转账税代币模板

- Role / 角色：`standardImplementation`
- Address / 地址：[`0x5ac337ab6815595bd3dd924b3003ce83d694bd3d`](https://bscscan.com/address/0x5ac337ab6815595bd3dd924b3003ce83d694bd3d#code)
- Source / 源码：[ADDVariableTokenV1](../current/bsc-v1-v2/contracts/portal-v1/ADDVariableTokenV1.sol)
- Deployment record / 部署记录：[deployments/standardImplementation.json](../current/bsc-v1-v2/deployments/standardImplementation.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Automatic-tax token template for the standalone tax factory / 普通税币工厂的自动税币模板

- Role / 角色：`taxImplementation`
- Address / 地址：[`0xdcd0644fa951dbaee331b9067eb02a8df06fe501`](https://bscscan.com/address/0xdcd0644fa951dbaee331b9067eb02a8df06fe501#code)
- Source / 源码：[ADDAutoTaxTokenV1](../current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxTokenV1.sol)
- Deployment record / 部署记录：[deployments/taxImplementation.json](../current/bsc-v1-v2/deployments/taxImplementation.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Automatic-tax token template for the mining-linked factory / 税入矿池工厂的自动税币模板

- Role / 角色：`staking.taxImplementation`
- Address / 地址：[`0x5fde8257c86d3a955243aa436ad0057618d606ff`](https://bscscan.com/address/0x5fde8257c86d3a955243aa436ad0057618d606ff#code)
- Source / 源码：[ADDAutoTaxTokenV1](../current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxTokenV1.sol)
- Deployment record / 部署记录：[deployments/staking-taxImplementation.json](../current/bsc-v1-v2/deployments/staking-taxImplementation.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Holder dividend template for the standalone tax factory / 普通税币工厂的持币分红模板

- Role / 角色：`dividendImplementation`
- Address / 地址：[`0xeb9c271f2cfe38d4430e2dac7a97e6bee1f79ae6`](https://bscscan.com/address/0xeb9c271f2cfe38d4430e2dac7a97e6bee1f79ae6#code)
- Source / 源码：[ADDClaimDividendV1](../current/bsc-v1-v2/contracts/tax-v1/ADDClaimDividendV1.sol)
- Deployment record / 部署记录：[deployments/dividendImplementation.json](../current/bsc-v1-v2/deployments/dividendImplementation.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Holder dividend template for the mining-linked factory / 税入矿池工厂的持币分红模板

- Role / 角色：`staking.dividendImplementation`
- Address / 地址：[`0xcfac91521f319a41b358b166170cb3206b573c85`](https://bscscan.com/address/0xcfac91521f319a41b358b166170cb3206b573c85#code)
- Source / 源码：[ADDClaimDividendV1](../current/bsc-v1-v2/contracts/tax-v1/ADDClaimDividendV1.sol)
- Deployment record / 部署记录：[deployments/staking-dividendImplementation.json](../current/bsc-v1-v2/deployments/staking-dividendImplementation.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Standalone staking factory V2 / 独立质押矿池工厂 V2

- Role / 角色：`staking.standaloneFactory`
- Address / 地址：[`0x97b96f82b56ebbc8f2bac6697d0728d3ad91b815`](https://bscscan.com/address/0x97b96f82b56ebbc8f2bac6697d0728d3ad91b815#code)
- Source / 源码：[ADDStakingFactoryV2](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingFactoryV2.sol)
- Deployment record / 部署记录：[deployments/staking-standaloneFactory.json](../current/bsc-v1-v2/deployments/staking-standaloneFactory.json)
- Constructor arguments / 构造参数：address: `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`

## Staking pool template deployer V2 / 质押矿池模板部署辅助合约 V2

- Role / 角色：`staking.poolDeployer`
- Address / 地址：[`0xcb81518be6e16c4c78b740e1c0032c0fe28fc441`](https://bscscan.com/address/0xcb81518be6e16c4c78b740e1c0032c0fe28fc441#code)
- Source / 源码：[ADDStakingPoolDeployerV2](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingPoolDeployerV2.sol)
- Deployment record / 部署记录：[deployments/staking-poolDeployer.json](../current/bsc-v1-v2/deployments/staking-poolDeployer.json)
- Constructor arguments / 构造参数：none / 无（空参数）

## Tax-to-mining token factory V2 / 税入矿池联动代币工厂 V2

- Role / 角色：`staking.taxFactory`
- Address / 地址：[`0x51f37e77138318e2596614d079f6bdea49d2ffbb`](https://bscscan.com/address/0x51f37e77138318e2596614d079f6bdea49d2ffbb#code)
- Source / 源码：[ADDStakingTaxFactoryV2](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingTaxFactoryV2.sol)
- Deployment record / 部署记录：[deployments/staking-taxFactory.json](../current/bsc-v1-v2/deployments/staking-taxFactory.json)
- Constructor arguments / 构造参数：address: `0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b`, address: `0xCB81518Be6E16c4c78b740E1c0032c0fE28fc441`

## Standalone staking pool template V2 / 独立质押矿池模板 V2

- Role / 角色：`staking.standaloneImplementation`
- Address / 地址：[`0x1907299ac3ac84b01c802ce3e778827edc667183`](https://bscscan.com/address/0x1907299ac3ac84b01c802ce3e778827edc667183#code)
- Source / 源码：[ADDStakingPoolV2](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingPoolV2.sol)
- Deployment record / 部署记录：[deployments/staking-standaloneImplementation.json](../current/bsc-v1-v2/deployments/staking-standaloneImplementation.json)
- Constructor arguments / 构造参数：address: `0x97B96F82b56EBbC8f2Bac6697D0728d3AD91B815`

## Tax-to-mining cyclic pool template V2 / 税入矿池循环矿池模板 V2

- Role / 角色：`staking.taxPoolImplementation`
- Address / 地址：[`0x0ae9d3aa1faa6e10810d859f1302d0b9c5ab1100`](https://bscscan.com/address/0x0ae9d3aa1faa6e10810d859f1302d0b9c5ab1100#code)
- Source / 源码：[ADDStakingPoolV2](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingPoolV2.sol)
- Deployment record / 部署记录：[deployments/staking-taxPoolImplementation.json](../current/bsc-v1-v2/deployments/staking-taxPoolImplementation.json)
- Constructor arguments / 构造参数：address: `0x51f37e77138318E2596614D079F6bdeA49D2FFbb`

## Per-token tax swap receivers / 每币税款兑换接收辅助

These two deployed helpers share [ADDTaxSwapReceiverV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDTaxSwapReceiverV1.sol). Each constructor takes the bound token address. The token immutable is also recorded in its deployment metadata; only that token can collect funds back to itself.

以下两个辅助使用同一份 [ADDTaxSwapReceiverV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDTaxSwapReceiverV1.sol)，构造参数为绑定的代币地址。部署资料记录相同的不可变绑定；只有这个代币可将资金取回代币合约自身。

- Receiver / 接收辅助：[0x98d3b670097c17e54c48dd3d656e6d110611031f](https://bscscan.com/address/0x98d3b670097c17e54c48dd3d656e6d110611031f#code)；bound token / 绑定代币：`0x65d282fadc0283d537001b43d8c08b69eabc1111`；[deployment metadata / 部署资料](../current/bsc-v1-v2/deployments/swapReceiver-65d282fa.json).
- Receiver / 接收辅助：[0xe507652db3ae86b6604577758cee688f56e3daa3](https://bscscan.com/address/0xe507652db3ae86b6604577758cee688f56e3daa3#code)；bound token / 绑定代币：`0x43f1c54d705ae27f8baf70a091da31d38e241111`；[deployment metadata / 部署资料](../current/bsc-v1-v2/deployments/swapReceiver-43f1c54d.json).

## Templates and cloned instances / 模板与克隆实例

Factories create EIP-1167 instances for tokens, dividends, and staking pools. The implementation address is the template, not the user instance. A clone needs its own on-chain implementation link checked; token-specific rates, recipients, reward assets, lock rules, and supply are initialized instance state, not constructor arguments of the template.

工厂创建的代币、分红合约、质押矿池使用 EIP-1167 克隆实例。模板地址不是用户实例地址；需核对每个克隆实际指向的实现。代币税率、接收方、奖励币、锁仓规则、发行量属于创建时初始化的实例状态，不是模板构造参数。

The two `ADDPortalQuoterV1` instances have the same bytecode but separate role addresses. The duplicate token/dividend/staking-pool templates use the same Solidity implementation with different immutable factory bindings. Keep their deployment metadata separate.

两份 `ADDPortalQuoterV1` 实例代码一致但角色地址不同。重复出现的代币、分红、矿池模板使用相同 Solidity 实现，但不可变工厂绑定不同，必须保留各自的部署元数据。

## External DEX dependency / 外部 DEX 依赖

PancakeSwap V2 Router is an external, separately maintained contract. ADD calls it for quote-asset conversion and graduation liquidity. Its code is not rebranded as ADD protocol source.

PancakeSwap V2 Router 是外部独立维护的合约，ADD 调用它兑换配对资产及毕业添加流动性，其源码不作为 ADD 自建协议源码发布。

- Router：[`0x10ed43c718714eb63d5aa57b78b54704e256024e`](https://bscscan.com/address/0x10ed43c718714eb63d5aa57b78b54704e256024e#code)
- V2 Factory：[`0xca143ce32fe78f1f7019d7d551a6402fc5350c73`](https://bscscan.com/address/0xca143ce32fe78f1f7019d7d551a6402fc5350c73#code)
- Wrapped BNB：[`0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c`](https://bscscan.com/address/0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c#code)

Older token templates are listed under [historical](../historical/README.md). Staking V1 is retired and is not part of this current V2 deployment index.

旧代币模板见 [historical](../historical/README.md)。质押 V1 已退役，不属于此现行 V2 地址索引。
