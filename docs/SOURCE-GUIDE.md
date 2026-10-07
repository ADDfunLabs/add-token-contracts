# Finding ADD contract source / ADD 合约源码获取指南

This repository publishes the deployed BSC protocol contracts and dependencies. It does not publish the ADD website, backend or private deployment configuration. Start with the [address index](DEPLOYMENTS.md) and [manifest](../manifest.json).

本仓库公开已经部署的 BSC 协议合约及其依赖，不包含网站前后端或私密部署配置。先看[地址索引](DEPLOYMENTS.md)与[发布清单](../manifest.json)。

## Portal, trading and factories / Portal、交易与工厂

- Main launch and asset-accounting entry / 募集、资金记账主入口：[ADDPortalV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalV1.sol).
- Internal buy/sell module / 内盘买卖模块：[ADDPortalTradeModuleV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalTradeModuleV1.sol).
- Graduation liquidity / 毕业添加流动性：[ADDPortalLiquidityV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalLiquidityV1.sol).
- Failed-graduation recovery and holder exit / 毕业失败恢复与持有人退出：[ADDPortalRecoveryV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDPortalRecoveryV1.sol).
- Standard issuance / 标准发行：[ADDVariableFactoryV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDVariableFactoryV1.sol).
- Ordinary tax issuance / 普通税币发行：[ADDAutoTaxFactoryV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxFactoryV1.sol).
- Tax-to-staking issuance / 税入矿池联动发行：[ADDStakingTaxFactoryV2.sol](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingTaxFactoryV2.sol).
- Standalone mining / 独立质押矿池：[ADDStakingFactoryV2.sol](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingFactoryV2.sol).

Read imports and inherited contracts together. The trade module runs only through its bound Portal; deploying or calling an isolated helper does not reproduce the complete platform.

审阅时需要一并阅读导入和继承的源码。交易模块只通过所绑定的 Portal 运行，单独部署或调用某个辅助合约不等于完整平台。

## Token, dividend and mining instances / 代币、分红与矿池实例

1. Open the instance address on BscScan's **Contract** tab. For ADD's EIP-1167 instances, inspect the implementation address and the explorer's implementation-source link.
2. Match that implementation address with a role in [manifest.json](../manifest.json). Current V1/V2 source is in `current/bsc-v1-v2`; previously published token templates are under `historical`.
3. Read the full source closure and its ABI. Instance initialization stores the creator's parameters; these are not the constructor arguments of the template. Use the instance's read methods and events to inspect the actual rate, assets, recipients, supply and lock rules.
4. For exact reproduction of an implementation, use the compiler input and immutable factory binding named by its own deployment metadata, rather than another address using the same Solidity file.

1. 打开实例地址的 BscScan **Contract** 页。ADD 的 EIP-1167 实例需要核对实际实现地址以及浏览器关联的实现源码。
2. 用实现地址匹配 [manifest.json](../manifest.json) 中的角色。现行 V1/V2 源码在 `current/bsc-v1-v2`，之前已公开的代币模板在 `historical`。
3. 阅读完整依赖和 ABI。创建者参数通过实例初始化保存，不是模板构造参数；实际税率、资产、收款方、发行量及锁仓规则需通过实例的只读方法和事件核对。
4. 复现模板代码时，使用该地址部署元数据指定的编译输入和不可变工厂绑定，不能拿同一 Solidity 文件的另一个部署地址代替。

Relevant current implementations / 现行实现入口：

- [ADDVariableTokenV1.sol](../current/bsc-v1-v2/contracts/portal-v1/ADDVariableTokenV1.sol)：zero token transfer tax / 零转账税代币。
- [ADDAutoTaxTokenV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxTokenV1.sol)：post-graduation pool tax and processing / 毕业后流动池收税与处理。
- [ADDClaimDividendV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDClaimDividendV1.sol)：ordinary holder dividends, one-holder claims / 普通持币分红，逐持有人领取。
- [ADDStakingPoolV2.sol](../current/bsc-v1-v2/contracts/staking-v2/ADDStakingPoolV2.sol)：staked-principal and reward accounting / 质押本金与奖励记账。
- [ADDTaxSwapReceiverV1.sol](../current/bsc-v1-v2/contracts/tax-v1/ADDTaxSwapReceiverV1.sol)：a per-token quote-output transit helper, bound to one token / 每币配对资产兑换中转，固定绑定一个代币。

Tax-funded staking directs the marketing allocation to the linked pool. It does not replace the separate ordinary holder-dividend ledger. A receiver only lets its bound token collect an asset back to itself; it does not choose tax recipients or administer funds.

税入矿池把营销份额转入联动矿池，不替代独立的普通持币分红记账。兑换接收辅助只允许固定绑定的代币取回资产到该代币自身，不决定税款收款人，也没有资金管理权限。

## Recorded explorer checks / 已记录的浏览器核对

- [Protocol-role results](verification/bsc-core-20261007.json) / [协议角色结果](verification/bsc-core-20261007.json).
- [Website token, dividend and mining clone results](verification/bsc-website-instances-20261007.json) / [官网代币、分红、矿池克隆结果](verification/bsc-website-instances-20261007.json).
- [Per-token tax receiver results](verification/bsc-tax-receivers-20261007.json) / [每币税款接收辅助结果](verification/bsc-tax-receivers-20261007.json).

The 2026-10-07 checks confirmed published source for all 17 protocol roles and both per-token receivers, and the implementation/runtime association for 9 website tokens, 2 dividends and 2 mining pools. The final receiver check completed at **2026-10-07 10:31 UTC**; per-address timestamps remain in the records.

2026-10-07 的核对确认 17 个协议角色、两个每币接收辅助的源码均已公开验证，以及官网 9 个代币、2 个分红合约、2 个矿池的实现及运行代码关联。最后一次接收辅助核对完成于 **2026-10-07 18:31 北京时间**，各地址的具体时间保留在记录内。

These are timestamped public verification records, not a continuous monitor or an independent security audit. A later newly created token or mining pool is not included automatically. BscScan source publication and clone association do not mean an EIP-1167 implementation can be upgraded: these clone targets are fixed in their runtime bytecode.

这些是附有核对时间的公开记录，不是持续监控或第三方独立安全审计。之后新建的代币、矿池不会自动纳入这份结果。浏览器源码公开和克隆关联也不代表 EIP-1167 实例可升级：这些实例的实现目标固定写在运行字节码里。

For independent verification, see [VERIFICATION.md](VERIFICATION.md). For earlier template versions, see [historical](../historical/README.md).

独立复现步骤见 [VERIFICATION.md](VERIFICATION.md)，旧模板见 [historical](../historical/README.md)。
