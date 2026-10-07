# Historical token implementations / 历史代币模板

These five previously published snapshots remain available for existing-token verification. They are not the factories/templates offered for current new V1/V2 launches. Updating this repository does not migrate existing tokens or remove old contracts from the chain.

- [Standard 68D18a58](standard-68d18a58/contracts/TokenSale.sol) — [BscScan](https://bscscan.com/address/0x68D18a58e97C20c849d7E5cc8d68bcb3c61a8242#code).
- [Tax d7308A6a](tax-d7308a6a/contracts/tax/ADDTaxToken.sol) — [BscScan](https://bscscan.com/address/0xd7308A6a87BB5d4fe7bdC1fA1b150885d8408bDD#code).
- [Standard EB452C3c](standard-eb452c3c/contracts/TokenSale.sol) — [BscScan](https://bscscan.com/address/0xEB452C3cf25cDa5d170F0265801a69263840b92d#code).
- [Standard d8876858](standard-d8876858/contracts/TokenSale.sol) — [BscScan](https://bscscan.com/address/0xd88768583A93B87D8231F7846965F1F123baf579#code).
- [Tax 44507482](tax-44507482/contracts/tax/ADDTaxToken.sol) — [BscScan](https://bscscan.com/address/0x4450748235A2180B78e82ED6238F918c1ACF9684#code).

Each directory preserves its original Solidity source bytes, isolated compiler input, ABI and recorded bytecode evidence. The two bundles moved from the old `current/` directory keep their original classification in `publicationStatusAtArchive`; their publication status is now `historical`. Never compile historical sources together with current source dependencies.

历史源码保留当时的业务规则、字段、注释与编译资料，仅用于对应旧代币核查。不要用新 V1/V2 的规则解释旧模板。旧质押 V1 已停用新建入口，不能误称为现行 V2；本历史目录收录的是此前已公开的五份代币模板，不是所有历史平台实现。

For current production roles, start with the [root index](../README.md) and [deployment list](../docs/DEPLOYMENTS.md).
