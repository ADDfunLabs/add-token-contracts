# Source and bytecode verification

## Current V1/V2 release

The source closure under `current/bsc-v1-v2/contracts/` is 26 production files. The 14 isolated inputs contain only the dependencies required by their targets. Each input was compiled and its ABI, complete creation bytecode and runtime template compared to the archived deployment build for the matching V1 or V2 deployment. All 17 protocol-role records and both per-token tax swap receiver records passed.

This matters for `viaIR`: compiling an arbitrary combined collection can change generated code. Do not replace the per-target inputs with one merged input or mix historical dependencies. This release's isolated inputs reproduce the deployed target templates; no old or test contracts are needed as background compilation context.

The compiler is exactly `0.8.20+commit.a1b79de6`, optimizer enabled with 200 runs, viaIR true, EVM paris. `manifest.json` freezes the extracted sources and input hashes. Each `deployments/*.json` records its qualified contract name, ABI path, constructor arguments, ABI-encoded constructor arguments, creation/template SHA-256, immutable offsets and public values, and full runtime SHA-256/keccak256.

Some constructors capture `msg.sender`. Standard, automatic-tax and dividend template constructors therefore have **no ABI arguments**, although their runtime contains the factory address as `initializationFactory`. Staking V2 pool templates take the initialization factory as an explicit constructor argument. Quoters and the recovery converter take the router; the converter also captures its deploying Portal. Applying a zero placeholder or supplying a factory argument to an argumentless constructor is incorrect.

The recorded runtime observation is a read-only chain check at the block or time specified in the records. Substituting the recorded immutable values into the matching compiler output reproduced the entire runtime, including its Solidity metadata, for all 17 protocol addresses and both per-token receivers. `sourceVerification` separately records browser publication status; successful compilation alone never means browser verification succeeded.

## Offline checks

~~~sh
npm ci --ignore-scripts
npm run verify
npm run verify:release
~~~

The verifier checks the exact dependency closure and source contents, compiler-input hashes, compiler settings, ABI, creation/template bytecode, immutable locations and values, constructor encoding and complete substituted runtime. Historical bundles retain their own sources and verification records. The compiler outputs are cached in memory only for this run; inputs shared by different deployed roles are compiled once.

`verify:release` adds a check that every current role's recorded explorer status is `verified`. This is a publication-record check, not a new explorer request. Neither command imports a wallet, reads credentials, uses RPC, signs, deploys or pays anything. The archive has no private deployment scripts.

## Fresh independent checks

Use your own BSC node, first confirm chain ID 56, and read the recorded address's `eth_getCode` at a common confirmed block. Hash the complete returned bytes with keccak256 and compare to `runtimeCodeHash`. Read the immutable getters at that same block and compare their public bindings; check the block hash again after reading to detect a reorganization. Public BscScan links are listed in [DEPLOYMENTS.md](DEPLOYMENTS.md).

Source matching does not establish whether an arbitrary user token is official. Token and pool instances are immutable EIP-1167 clones. Their runtime must refer to the expected implementation; their initialization/factory/Portal bindings and official membership must also be checked. Parameters and balances live in each clone, not in the template address. This repository does not enumerate every instance.

PancakeSwap's router is an external dependency with its own verified source. It is referenced by address, not republished as ADD-owned code. Historical snapshots are evidence for their specific old deployments and do not implement current V1/V2 rules.

## Verification boundaries

This is reproducible source publication, not an independent security audit. Repository updates do not alter deployed code. Immutable code still has the owner operations documented in the source, and arbitrary rebasing, transfer-taxed, malicious or restricted assets can have behavior beyond standard ERC20 assumptions.

The lockfile pins `solc` 0.8.20 and `js-sha3` 0.8.0. The compiler wrapper's temporary-file dependency is overridden to `tmp` 0.2.7; bytecode reproduction confirms that this dependency update does not change the target output.
