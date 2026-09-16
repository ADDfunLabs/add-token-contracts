# ADD Token Contracts

Public, reproducible source archive for the **ADD.fun token implementations on BNB Smart Chain (chain ID 56)**.

[中文](README.zh-CN.md) · [Website](https://add.fun/) · [How ADD works](https://github.com/ADDfunLabs/add-sdk/blob/main/docs/how-add-works.md) · [SDK](https://github.com/ADDfunLabs/add-sdk) · [Verification guide](docs/VERIFICATION.md)

## Current implementations

These are **implementation addresses**, not the address of a token to buy. Individual ADD tokens are fixed EIP-1167 clones with their own balances, settings and Portal binding. The implementation is not an upgradeable proxy.

- **Standard token (0% transfer tax):** [TokenSale.sol](current/standard/contracts/TokenSale.sol) — [0x68D18a58e97C20c849d7E5cc8d68bcb3c61a8242 on BscScan](https://bscscan.com/address/0x68D18a58e97C20c849d7E5cc8d68bcb3c61a8242#code).
- **Post-graduation tax token:** [ADDTaxToken.sol](current/tax/contracts/tax/ADDTaxToken.sol) — [0xd7308A6a87BB5d4fe7bdC1fA1b150885d8408bDD on BscScan](https://bscscan.com/address/0xd7308A6a87BB5d4fe7bdC1fA1b150885d8408bDD#code).

“Current” describes the active templates checked on **2026-09-16**. Older tokens retain their original implementation; see the [historical index](historical/README.md).

## What the token code covers

- Fixed initial supply of 1 billion tokens, 18 decimals, with one-time authorized initialization.
- Per-token fundraising target and asset, launch phases and a permanent token-level authority transition to the dead address after graduation.
- Standard ERC20 transfers without a transfer tax. The separate Portal still charges its launch trading fee.
- Tax token settings fixed during creation: separate buy/sell tax rates, with taxes active after graduation. Wallet-to-wallet transfers are untaxed; recognized V2 pool transfers include manual liquidity additions/removals. Protocol tax-module transfers are exempt.
- Included tax dependencies expose configuration and dividend share/round accounting. Processing uses separately deployed modules.

ADD uses a fixed launch exchange rate denominated in the selected fundraising asset. The platform currently defaults to a **1 BNB target**, allows custom targets and lets the Portal owner change the default for future creations. Existing token targets do not change. The default setting and trade settlement live in the Portal/registry, not a hardcoded global default in this token archive. Non-BNB conversion and post-graduation market prices can move.

## Scope

Each bundle contains the exact token source and dependencies already disclosed by its verified BscScan publication, the compiler Standard JSON input, ABI and verification metadata. Source contents, comments and compiler unit paths are preserved, including historical names and internal documentation references.

This archive **does not contain the whole ADD platform**: Portal/registry/factory implementations, separate tax-processor implementation, frontend, backend, internal deployment tooling and credentials are outside this release. Interface declarations needed to compile a token are included; an interface is not the implementation it calls. The undeployed external “Burn Reward BNB” mechanism is not included.

The included `contracts/openzeppelin/` files are local implementations, not a claim of upstream OpenZeppelin provenance or audit coverage. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Reproduce the build

Requires Node.js 22 or 24 and npm:

~~~sh
npm ci --ignore-scripts
npm run verify
~~~

The verifier compiles all five isolated bundles with **Solidity 0.8.20**, optimizer **200 runs**, **viaIR**, EVM **paris**. It checks source hashes, extracted sources against Standard JSON, ABI, creation bytecode and runtime bytecode after applying the recorded constructor-bound immutable values. It runs offline after dependencies are installed and does not connect a wallet or broadcast transactions. See the [verification guide](docs/VERIFICATION.md) to distinguish this check from a fresh chain verification.

## Permissions and limitations

Source verification establishes source/bytecode correspondence; it is not an independent security audit or a safety guarantee. Token-level authority ending at graduation does not remove the Portal owner's separate management and emergency recovery powers. Review the [public permissions disclosure](https://add.fun/docs/en/permissions/) and the surrounding contracts before integration. This repository is an implementation archive, not a stand-alone launchpad deployment kit.

## License and official links

MIT for the published code and documentation, with existing third-party notices preserved. The license does not grant rights to the ADD name or logo or imply endorsement. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

[Official documentation](https://add.fun/docs/en/) · [SDK docs](https://add.fun/sdk/) · [Brand assets](https://github.com/ADDfunLabs/add-sdk/tree/main/assets/brand) · [X](https://x.com/ADDfunLabs) · [Telegram](https://t.me/ADD_FU)
