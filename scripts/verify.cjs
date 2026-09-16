// Offline verification only. No RPC, credentials, wallet, signing or deployment.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const solc = require('solc');
const root = path.resolve(__dirname, '..');
const read = p => fs.readFileSync(path.join(root, p));
const json = p => JSON.parse(read(p));
const hash = b => createHash('sha256').update(b).digest('hex');
const manifest = json('manifest.json');
assert.equal(manifest.chainId, 56);
assert.equal(manifest.contracts.length, 5);
assert(solc.version().startsWith('0.8.20+commit.a1b79de6.'), 'Wrong compiler');
const directories = new Set();
for (const entry of manifest.contracts) {
  const dir = entry.directory;
  assert(/^(current|historical)\/[a-z0-9-]+$/.test(dir), 'Invalid bundle path');
  assert(!directories.has(dir), 'Duplicate bundle');
  directories.add(dir);
  const meta = json(dir + '/metadata.json');
  const inputBytes = read(dir + '/standard-input.json');
  const input = JSON.parse(inputBytes);
  assert.equal(meta.chainId, manifest.chainId);
  assert.equal(meta.address, entry.address);
  assert.equal(meta.status, entry.status);
  assert.equal(meta.contractName, entry.contractName);
  assert.equal(meta.runtimeCodeHash, entry.runtimeCodeHash);
  assert.equal(meta.compilerVersion, 'v0.8.20+commit.a1b79de6');
  assert.equal(hash(inputBytes), meta.standardInputSha256);
  assert.equal(input.language, 'Solidity');
  assert.deepEqual(input.settings.optimizer, { enabled: true, runs: 200 });
  assert.equal(input.settings.viaIR, true);
  assert.equal(input.settings.evmVersion, 'paris');
  assert.deepEqual(meta.sources.map(s => s.path).sort(), Object.keys(input.sources).sort());
  for (const source of meta.sources) {
    assert(/^contracts\/(?:[A-Za-z0-9_]+\/)*[A-Za-z0-9_]+\.sol$/.test(source.path));
    const bytes = read(dir + '/' + source.path);
    assert.equal(hash(bytes), source.sha256, 'Source hash mismatch: ' + source.path);
    assert.equal(bytes.toString('utf8'), input.sources[source.path].content);
  }
  const result = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (result.errors || []).filter(e => e.severity === 'error');
  assert.equal(errors.length, 0, errors.map(e => e.formattedMessage).join('\n'));
  const [unit, name] = meta.contractName.split(':');
  const contract = result.contracts[unit][name];
  assert.deepEqual(contract.abi, json(dir + '/abi.json'), 'ABI mismatch');
  assert.equal(hash(Buffer.from(contract.evm.bytecode.object, 'hex')), meta.creationSha256);
  const template = contract.evm.deployedBytecode.object;
  assert.equal(hash(Buffer.from(template, 'hex')), meta.runtimeTemplateSha256);
  const refs = contract.evm.deployedBytecode.immutableReferences || {};
  assert.deepEqual(refs, meta.immutableReferences);
  assert.deepEqual(Object.keys(refs).sort(), Object.keys(meta.immutableValues).sort());
  assert(/^0x[0-9a-fA-F]{40}$/.test(meta.initializationAuthority));
  const expected = meta.initializationAuthority.slice(2).toLowerCase().padStart(64, '0');
  let runtime = template;
  for (const [astId, locations] of Object.entries(refs)) {
    assert.equal(meta.immutableValues[astId], '0x' + expected);
    for (const ref of locations) {
      assert.equal(ref.length, 32);
      assert(ref.start >= 0 && (ref.start + ref.length) * 2 <= template.length);
      runtime = runtime.slice(0, ref.start * 2) + expected + runtime.slice((ref.start + ref.length) * 2);
    }
  }
  assert.equal(hash(Buffer.from(runtime, 'hex')), meta.runtimeSha256, 'Runtime mismatch');
  console.log('Verified: ' + dir + ' — ' + meta.address);
}
console.log('All 5 source bundles reproduce the recorded ABI and bytecode. Offline check; no chain reads or transactions.');
