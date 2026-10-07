# ADD Protocol Contracts — BSC

Production Solidity sources for ADD.fun on **BNB Smart Chain, chain ID 56**: the immutable Portal V1, its trade and settlement helpers, issuance factories, standard and automatic-tax token templates, claim dividends, and staking V2.

[中文](README.zh-CN.md) · [Website](https://add.fun/) · [Deployment addresses](docs/DEPLOYMENTS.md) · [Verification](docs/VERIFICATION.md) · [SDK](https://github.com/ADDfunLabs/add-sdk)

## Current source release

The [current V1/V2 directory](current/bsc-v1-v2/) contains **26 production source files and dependencies**, **14 isolated compiler inputs**, and the ABI and reproducibility metadata for **17 deployed protocol roles plus two per-token tax swap receivers**. See [manifest.json](manifest.json) for exact addresses, source hashes and runtime hashes. The [source guide](docs/SOURCE-GUIDE.md) explains how to find the implementation behind a token, dividend or mining-pool instance.

- [Portal V1](current/bsc-v1-v2/contracts/portal-v1/ADDPortalV1.sol): [0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b](https://bscscan.com/address/0x933bc9fe78c9beaedc5a82bd24b5359d01e8fd7b#code). Access, inventory accounting, graduation, recovery and quoting dependencies are included.
- [Trade module V1](current/bsc-v1-v2/contracts/portal-v1/ADDPortalTradeModuleV1.sol): [0x98541696049c8d93b8d679ad61ff1ec6d7253ed1](https://bscscan.com/address/0x98541696049c8d93b8d679ad61ff1ec6d7253ed1#code). It is fixed in the Portal constructor; it is not an upgrade hook.
- [Standard factory and token V1](current/bsc-v1-v2/contracts/portal-v1/ADDVariableFactoryV1.sol): configurable supply, zero token transfer tax, fixed EIP-1167 clones.
- [Automatic-tax factory and token V1](current/bsc-v1-v2/contracts/tax-v1/ADDAutoTaxTokenV1.sol): marketing, burn, dividends and added liquidity. The price guard and swap receiver are included.
- [Claim dividend V1](current/bsc-v1-v2/contracts/tax-v1/ADDClaimDividendV1.sol): a separate ledger per dividend-enabled token; holder rewards are claimed explicitly.
- [Standalone staking V2](current/bsc-v1-v2/contracts/staking-v2/ADDStakingFactoryV2.sol): prepaid or recurring rewards, with per-deposit principal withdrawal rules.
- [Tax-funded staking V2](current/bsc-v1-v2/contracts/staking-v2/ADDStakingTaxFactoryV2.sol): creates a tax token together with its staking pool. Its marketing allocation funds the pool; ordinary holder dividends remain separate.

The publication version **2.0.0** is an archive version, independent of Solidity contract and SDK versions. Current designation is as of **2026-10-07**. The five previously published token bundles are preserved in [historical/](historical/README.md); existing clones are not migrated by this repository update.

The publication checks recorded verified BscScan source for all 17 protocol roles and both tax receivers, plus implementation links for 9 website tokens, 2 dividend contracts and 2 mining pools. See the timestamped results in the [source guide](docs/SOURCE-GUIDE.md).

## Launch and tax rules

The Portal prices a launch from the tokens it actually receives: half is offered for sale and half is reserved for V2 liquidity. The ordinary BSC V1 target is a fixed **4 BNB** constant; this deployed version has no default-target setter. The owner can enable or disable the custom-target entry, where creators may choose a target of at least **1 BNB**. Those switches do not reprice admitted launches. BNB, USDT and supported custom fundraising assets are supported; buyers pay BNB and the Portal settles into the configured asset.

Internal buys and sells charge the platform's **1% trading fee**. When the unsold allocation becomes strictly less than 1% of the admitted inventory, graduation uses the actual reserve and liquidity allocation. Excess payment on the final purchase is refunded to the buyer. Graduation and tax-added LP are sent to the dead address.

If adding liquidity fails, the completed purchase is preserved and the launch pauses. Anyone can retry graduation. The owner can convert the protected reserve to an alternative pair asset with a 5% execution floor, or irreversibly enable proportional holder refunds in the original reserve asset. That execution floor does not guarantee the economic value of an owner-selected asset. Previous trading fees are not refunded.

Automatic token taxes start after graduation. Buy and sell rates and four allocations are fixed at creation. Wallet transfers are untaxed; transfers into or out of recognized V2 pools, including manual liquidity changes, may be taxed. Buys accumulate tax tokens; eligible sells and permissionless processing calls process earlier accumulated tax. Processing has a supply-based threshold that halves annually, bounded batch size and price/liquidity guards, so payouts need not occur on every trade.

Marketing is paid in the actual pair asset; BNB pairs attempt native BNB and can fall back to WBNB. Burn allocations move tokens to the dead address without reducing `totalSupply`. Dividends can use native BNB, the issued token or a selected reward token. `claimFor` handles one holder and always pays that holder; there is no all-holder batch payout in this version.

## Staking V2

Standalone pools support prepaid rewards with an optional halving schedule, or recurring 1–360 day cycles. Tax-funded pools use recurring cycles and recognize new rewards during stake, claim or sync calls. Mid-cycle additions are spread over the remaining active time; new funding after completion starts the next cycle. No stakers pauses the reward clock. Previously earned, unclaimed rewards remain accounted for across cycles.

Principal can be flexible, locked until a cliff, or unlocked in equal installments. Every deposit has its own start time; later deposits do not extend earlier locks. Reward claims deduct a **1% maintenance fee in the reward asset**, payable to the fixed ADD fee recipient. Principal withdrawals have no platform fee. Pools have no owner, upgrade mechanism or administrative sweep of protected principal/rewards.

Tax-funded staking is distinct from ordinary holder dividends. It directs the entire marketing allocation into the linked pool. Staking assets may be the token itself, its V2 LP or a selected asset. After fallback graduation, the final quote asset and LP can be corrected before the first stake; the binding is fixed once staking starts. A pool does not automatically redistribute unrelated dividend assets attached to its staking token.

## Reproduce and inspect

Requires Node.js 22 or 24 and npm:

~~~sh
npm ci --ignore-scripts
npm run verify
npm run verify:release
~~~

Both commands are offline and never connect a wallet or send a transaction. The verifier compiles each isolated input with locked **Solidity 0.8.20**, optimizer **200**, **viaIR**, EVM **paris**; checks source hashes, ABI, creation bytecode, immutable locations and values, and the full substituted runtime including metadata. `verify:release` additionally requires every current role's recorded explorer source status to be verified. Read the [verification guide](docs/VERIFICATION.md) before treating a publication record as a fresh chain check.

## Scope, permissions and license

This release includes ADD's production implementations and their dependencies. It excludes the website, backend, private deployment tools/configuration, credentials, undeployed external mechanisms and ETH development. [PancakeSwap V2's router](https://bscscan.com/address/0x10ED43C718714eb63d5aA57B78B54704E256024E#code) is an external protocol dependency, not ADD-owned code.

The Portal is immutable but has owner management: factory admission, entry switches, fee recipient, recovery choices, surplus-only withdrawals and two-step ownership transfer. The owner cannot change the ordinary 4 BNB target or reprice admitted launches. Protected launch inventories and reserves cannot be swept. Fixed token/pool clones are not upgradeable proxies. Review [SECURITY.md](SECURITY.md) and the surrounding contracts; source/bytecode verification is not an independent security audit or a guarantee for arbitrary ERC20 assets.

MIT, with source SPDX identifiers and [third-party notices](THIRD_PARTY_NOTICES.md) preserved. The local `openzeppelin/` utilities are not represented as upstream audited OpenZeppelin releases. The license does not grant ADD brand rights or endorsement. This repository is a source archive, not a one-click deployment kit.

[Documentation](https://add.fun/docs/en/) · [SDK docs](https://add.fun/sdk/) · [Brand assets](https://github.com/ADDfunLabs/add-sdk/tree/main/assets/brand) · [X](https://x.com/ADDfunLabs) · [Telegram](https://t.me/ADD_FU)
