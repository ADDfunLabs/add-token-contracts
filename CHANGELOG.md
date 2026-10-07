# Changelog

## source-v2.0.0 — 2026-10-07

- Public production source closure for the current BSC Portal V1, fixed trading module and helpers, variable-supply standard factory/token, automatic tax, claim dividends, and standalone/linked staking V2.
- 26 production Solidity files, 14 exact isolated compiler inputs and ABI/constructor/immutable/runtime records for 17 deployed protocol roles and two per-token tax swap receivers. No platform frontend/backend, credentials or private deployment tooling.
- Previous five token implementation bundles preserved as historical snapshots. No change to deployed contracts or existing token balances.
- Verifier checks full runtime keccak256 and supports a release gate for recorded BscScan verification status.
- Public read-only verification summaries cover the protocol roles and website token, dividend and mining-pool clone associations; the source guide maps instances to current or historical implementations.
- Documentation correction: deployed BSC V1 uses a fixed 4 BNB ordinary target and has no default-target setter. Its owner can switch custom-target admission, not change that constant. Historical/ETH default-setting permissions do not apply; no contract source, address or archive version changed.

## source-v1.0.0 — 2026-09-16

- Initial public source archive: two current token implementations and three historical implementations.
- Exact already-verified sources and dependencies, Standard JSON inputs, ABIs, compiler/chain verification metadata, and an offline reproduction script.
- English and Chinese entry points, license and third-party attribution.
- No changes to deployed code, platform configuration, token balances or SDK v0.1.0.

The source archive version is independent of platform deployment versions and SDK versions.
