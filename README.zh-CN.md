# ADD 代币合约源码

ADD.fun 在 **BNB Smart Chain 主网（56）** 已公开验证的代币实现源码与编译资料。

[English](README.md) · [官网](https://add.fun/) · [工作原理](https://github.com/ADDfunLabs/add-sdk/blob/main/docs/how-add-works.zh-CN.md) · [SDK](https://github.com/ADDfunLabs/add-sdk) · [编译核验说明](docs/VERIFICATION.md)

## 当前使用的模板

以下地址是**代币实现模板地址**，不是用来购买的项目代币地址。用户创建的代币是固定的 EIP-1167 克隆，分别拥有自己的余额、参数和 Portal 绑定，不是可升级代理。

- **标准 0 转账税代币：** [TokenSale.sol](current/standard/contracts/TokenSale.sol)，[BscScan 源码](https://bscscan.com/address/0x68D18a58e97C20c849d7E5cc8d68bcb3c61a8242#code)。
- **毕业后税收代币：** [ADDTaxToken.sol](current/tax/contracts/tax/ADDTaxToken.sol)，[BscScan 源码](https://bscscan.com/address/0xd7308A6a87BB5d4fe7bdC1fA1b150885d8408bDD#code)。

当前/历史分类以 **2026-09-16** 核对结果为准。旧代币继续使用原实现，不迁移；另有 [3 份历史模板](historical/README.md)供核查。

## 主要规则

- 一次性初始化发行 10 亿枚，精度 18 位；逐币记录募集资产、目标和发行阶段。
- 内盘相对募集资产固定兑换比例。平台当前默认目标为 **1 BNB**，支持自定义目标；Portal 业主可修改以后新建项目的默认值，已有项目目标不变。默认值与交易结算由 Portal/登记器管理，不是此仓库中全局写死的常量。
- 标准代币不收转账税，内盘交易仍按 Portal 规则收取平台税。非 BNB 兑换与毕业后的市场价格可能波动。
- 税收代币的买入税、卖出税创建时分别设定并固定，毕业后生效；钱包互转免税，识别的 V2 池进出会收税，包括用户手动加减池，平台税款模块转账豁免。
- 收录分红份额和轮次等必要依赖，税款处理另由独立模块执行。

## 公开范围

只收录这五份模板在 BscScan 已公开的源码及其依赖，附 Standard JSON 编译输入、ABI、地址和校验记录。原始注释、源码路径和历史字段名保持不变。源码里的内部审计文件引用不表示这些内部文件也在此仓库。

不包含平台 Portal、登记器、工厂实现、独立税款处理器实现、前后端、部署工具、配置或凭据；必要接口声明不等于对应实现源码。尚未部署的“销毁奖励BNB”外部机制未公开在此仓库。

`contracts/openzeppelin/` 为本地实现，目录名字不代表上游原版或继承上游审计结果。许可与归属见 [第三方说明](THIRD_PARTY_NOTICES.md)。

## 本地编译核验

安装 Node.js 22 或 24 后，在此仓库运行：

~~~sh
npm ci --ignore-scripts
npm run verify
~~~

使用锁定的 Solidity 0.8.20、optimizer 200、viaIR、paris，分别编译五份资料。检查源码哈希、可读源码与 JSON 一致性、ABI、创建字节码，以及填入记录的构造时 immutable 值后的运行字节码。安装依赖后可离线运行，不连接钱包、不部署或发交易。

发布前已另行读取 BscScan 源码和链上代码；离线脚本仅重现这次记录，不代表每次运行都会重新查链。细节见 [核验说明](docs/VERIFICATION.md)。

公开验证不等于独立安全审计。代币毕业后权限转黑洞，不会消除 Portal 自身业主的管理和紧急提取权限；请结合 [平台权限披露](https://add.fun/docs/)阅读。本仓库不是完整平台的一键部署包。

代码和文档按 MIT 许可，保留第三方署名；不授予 ADD 品牌/商标使用权或官方背书。
