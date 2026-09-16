# Reproducing and checking the publication

## Publication checks

Every bundle was independently checked before publication:

1. Fetch the publicly verified Standard JSON source from BscScan/Etherscan for chain 56; compare every source content string and all code-generation settings to the saved publication input.
2. Recompile with `solc 0.8.20+commit.a1b79de6`, optimizer enabled/200 runs, viaIR true, EVM paris. BscScan may request extra documentation/metadata outputs; both output selections are recorded and do not change code-generation settings.
3. Read the template's bytecode and `initializationAuthority()` at one finalized BSC block. The constructor stores its deployer as an immutable. Apply that public address at the compiler-reported immutable locations and compare the **entire** runtime bytecode, including compiler metadata, to the chain.
4. Confirm the block hash has not changed. Record block number/hash, address, UTC check time, runtime keccak256, SHA-256 hashes, immutable locations and values in `metadata.json`.

Empty `constructorArguments` is correct: these template constructors have no externally supplied arguments. Their immutable authority comes from constructor `msg.sender`, so a zero-placeholder runtime would not match the deployment.

## Offline verification

`npm ci --ignore-scripts && npm run verify` uses the lockfile and then compiles all five bundles offline. It checks:

- Compiler version and manifest entries.
- Exact Standard JSON file hash; all extracted source files and their SHA-256 hashes, without newline conversion.
- Compiled ABI, creation bytecode, runtime template, immutable locations and substituted-runtime SHA-256.

The offline verifier uses the values recorded at publication. It does **not** query BscScan or a node, establish that the manifest itself is trusted, check a user's clone address, or audit protocol behavior. A newly deployed copy would have a different initialization authority unless deployed by the same authorized factory.

To make a fresh independent chain check, use your own BSC node at the recorded block, obtain `eth_getCode` for each implementation address, hash the returned bytes and compare to `runtimeCodeHash`. You can also inspect the linked BscScan verified source. No account secrets are required for the offline check.

The lockfile overrides the compiler wrapper's temporary-file dependency to tmp 0.2.7 to address known path-traversal advisories. The solc compiler itself stays exactly 0.8.20; the bytecode reproduction check confirms that this dependency update does not change the compiled contracts.

## Scope of reproducibility

The address in a bundle is an implementation. Individual EIP-1167 token clones refer to an implementation, while their metadata, parameters and balances live in each clone's storage. Matching an implementation is only one part of checking a token.

This repository intentionally preserves exact token dependency sources, not the full Hardhat build-info or unrelated platform contracts. The tax bundle imports dividend/configuration sources, but it does not provide all externally called module implementations. Source comments may refer to internal files outside this archive.

This is a source publication with reproducible build evidence, **not an independent security audit**. The public platform [permission disclosure](https://add.fun/docs/en/permissions/) applies separately.
