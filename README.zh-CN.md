# ADD 平台合约源码 — BSC

公开 ADD.fun 在 **BNB Smart Chain 主网（56）** 当前使用的 Solidity 合约：不可升级的 Portal V1、交易与结算辅助、发行工厂、零税与自动税代币、领取式分红、质押 V2。

[English](README.md) · [官网](https://add.fun/) · [部署地址](docs/DEPLOYMENTS.md) · [编译核验](docs/VERIFICATION.md) · [SDK](https://github.com/ADDfunLabs/add-sdk)

## 当前公开内容

[current/bsc-v1-v2/](current/bsc-v1-v2/) 收录 **26 份生产 Solidity 源码和依赖、14 份独立编译输入、17 个实际部署协议角色及两个每币税款兑换接收辅助合约的 ABI 和复现资料**。完整地址、文件哈希与运行字节码哈希见 [manifest.json](manifest.json)。[源码获取指南](docs/SOURCE-GUIDE.md) 说明如何由代币、分红、矿池实例找到对应实现。

- [Portal V1 主池](current/bsc-v1-v2/contracts/portal-v1/ADDPortalV1.sol)：[0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b](https://bscscan.com/address/0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b#code)，包含权限、库存账本、毕业、恢复和报价依赖。
- [固定交易模块 V1](current/bsc-v1-v2/contracts/portal-v1/ADDPortalTradeModuleV1.sol)：[0x98541696049c8d93b8d679ad61ff1ec6d7253ed1](https://bscscan.com/address/0x98541696049c8d93b8d679ad61ff1ec6d7253ed1#code)，在 Portal 构造时固定，不是升级入口。
- [零税工厂与代币 V1](current/bsc-v1-v2/contracts/portal-v1/ADDVariableFactoryV1.sol)：可填写发行量，固定克隆，不收代币转账税。
- [自动税收 V1](current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxTokenV1.sol)：营销、销毁、普通分红和加池；包含工厂、价格保护和兑换中转器。
- [领取式分红 V1](current/bsc-v1-v2/contracts/tax-v1/ADDClaimDividendV1.sol)：有普通分红的代币各自拥有一个独立账本，持有人自行领取。
- [独立质押 V2](current/bsc-v1-v2/contracts/staking-v2/ADDStakingFactoryV2.sol)：预付或循环奖励、本金逐笔锁仓与解锁。
- [税入矿池 V2](current/bsc-v1-v2/contracts/staking-v2/ADDStakingTaxFactoryV2.sol)：创建税币时一起生成矿池，营销份额转入矿池；普通持币分红仍是独立功能。

资料发布版本 **2.0.0** 与链上合约版本、SDK 版本分别编号。当前分类以 **2026-10-07** 为准。之前公开的五份代币模板保留在 [historical/](historical/README.md)，不会因更新仓库而迁移旧代币。

本次记录确认 17 个协议角色、两个税款接收辅助的 BscScan 源码验证完成，官网 9 个代币、2 个分红合约、2 个矿池的实现关联也已核对。附核对时间的公开结果见[源码获取指南](docs/SOURCE-GUIDE.md)。

## 发行与税收

Portal 按实际收到的代币数量定价：一半募集，一半预留加 V2 流动池。BSC V1 普通入口的参考目标固定为 **4 BNB** 常量，本次已部署版本没有修改默认目标的函数。业主可开关自定义目标入口；开启时，创建者可选择至少 **1 BNB** 的目标。入口开关不会重新定价已登记项目。募集资产可选 BNB、USDT 或支持的自定义资产；用户支付 BNB，Portal 按规定兑换与结算募集资产。

内盘买卖收 **1% 平台交易费**。剩余募集代币严格小于本次到账总量的 1% 时触发毕业，使用实际募集资金和预留代币加池。最后一笔超额付款退回买家。毕业 LP 和税收新增 LP 转入黑洞。

加池失败时保留已成交买入并暂停内盘。任何钱包可以重试；业主可选择备用资产，将受保护募集资金按 5% 执行保护整笔兑换后加池，或永久开启持有人按比例交币领取原募集资产的退款。5% 保护不是对业主选择资产经济价值的保证；已收历史交易费不退。

代币买卖税毕业后生效，创建时设定的税率和四项分配固定。钱包互转免代币税；识别交易池进出会收税，手动加减池也可能涉及税。买入积累税币，符合条件的卖出或任何钱包手动处理会处理此前累计税币。累计门槛按发行量计算、每年减半；还有单次处理上限与价格、流动性保护，因此不是每笔交易都立即支付税款。

营销支付实际配对资产，BNB 配对优先付 BNB、失败可退回 WBNB 形式。销毁份额转黑洞，不减少 `totalSupply`。普通分红可用 BNB、本币或指定代币；`claimFor` 每次处理一个持有人，收款人只能是该持有人，这版没有全员批量自动分红。

## 质押 V2

独立矿池支持预付奖励、可选减半计划，或 1～360 天循环奖励。税入矿池使用循环方式；质押、领取或同步时识别新增奖励，中途到账摊入本轮剩余有效时间，结束后有新奖励再开下一轮。无人质押时暂停奖励计时，跨轮仍保留以前已产生但未领取的奖励。

本金规则可选随时取回、到期解锁、等额分批解锁。每笔质押独立开始计时，追加不延长之前本金锁仓。领取奖励扣 **1% 同奖励资产维护费**，支付固定 ADD 收费地址；取回本金不收平台费。矿池无业主、升级或管理员提取受保护本金和奖励的入口。

税入矿池与普通持币分红分开记账：营销份额全部进入同步创建的矿池，质押可选本币、对应 V2 LP 或指定资产。备用毕业改变配对时，首次质押前可校正为最终配对资产和 LP；开始质押后绑定固定。矿池只分配指定奖励，不自动转发质押代币携带的其他币种分红。

## 编译与核验

安装 Node.js 22 或 24 后执行：

~~~sh
npm ci --ignore-scripts
npm run verify
npm run verify:release
~~~

命令只在本地编译，不连接钱包，不签名，不发交易。固定 Solidity 0.8.20、optimizer 200、viaIR、paris，按独立输入检查源码、ABI、创建字节码、immutable 位置与绑定值，以及包含 metadata 的完整运行字节码。`verify:release` 还要求所有现行角色记录的浏览器源码状态为已验证。离线复现与重新查链的区别见 [核验说明](docs/VERIFICATION.md)。

## 范围、权限与许可

公开范围包括 ADD 当前生产合约及依赖，不包含网站、后台、私密部署工具/配置、凭据、未部署外部机制或 ETH 开发内容。[PancakeSwap V2 路由](https://bscscan.com/address/0x10ED43C718714eb63d5aA57B78B54704E256024E#code)属于外部协议，不是 ADD 自有合约。

Portal 不可升级，但业主可登记工厂、控制入口、修改收费地址、选择毕业失败恢复方案、仅提取未用于募集的多余资产，并两步转移业主。业主不能修改普通入口固定的 4 BNB 目标，也不能重新定价已登记项目。不能提走受保护库存和募集资金。固定模板克隆不是可升级代理。源码验证不等于第三方独立安全审计，也不能保证任意特殊 ERC20 都兼容；请结合 [SECURITY.md](SECURITY.md)与完整逻辑检查。

按 MIT 许可，保留原 SPDX 与[第三方署名](THIRD_PARTY_NOTICES.md)。`openzeppelin/` 是本地实现，目录名不代表上游原版或继承上游审计。许可不授予 ADD 商标使用权或官方背书。本仓库是源码资料，不是一键部署包。
