'use strict';
// Offline only: no RPC, keys, signatures, transactions or deployment.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {createHash}=require('node:crypto'),{keccak256}=require('js-sha3'),solc=require('solc');
const root=path.resolve(__dirname,'..'),cache=new Map();
function read(p){assert(typeof p==='string'&&!path.isAbsolute(p)&&!p.includes('\\')&&!p.split('/').includes('..'),'Unsafe path');const file=path.resolve(root,p);assert(file.startsWith(root+path.sep));assert(fs.realpathSync(file).startsWith(root+path.sep));return fs.readFileSync(file);}
const json=p=>JSON.parse(read(p)),sha=b=>createHash('sha256').update(b).digest('hex'),codeHash=h=>'0x'+keccak256(Buffer.from(h,'hex'));
const manifest=json('manifest.json');assert.equal(manifest.schemaVersion,2);assert.equal(manifest.chainId,56);
assert(solc.version().startsWith('0.8.20+commit.a1b79de6.'),'Wrong compiler');
function compile(p){if(cache.has(p))return cache.get(p);const bytes=read(p),input=JSON.parse(bytes);assert.equal(input.language,'Solidity');assert.deepEqual(input.settings.optimizer,{enabled:true,runs:200});assert.equal(input.settings.viaIR,true);assert.equal(input.settings.evmVersion,'paris');const result=JSON.parse(solc.compile(JSON.stringify(input)));const errors=(result.errors||[]).filter(e=>e.severity==='error');assert.equal(errors.length,0,errors.map(e=>e.formattedMessage).join('\n'));const value={bytes,input,result};cache.set(p,value);return value;}
const source=manifest.sourceBundle,files=new Map(source.sourceFiles.map(s=>[s.path,s]));assert.equal(files.size,26);assert.equal(source.compilationInputs.length,14);const inputSources=new Set();
for(const [name,f]of files){assert(/^contracts\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_]+\.sol$/.test(name));assert.equal(sha(read(source.directory+'/'+name)),f.sha256,'Production source hash: '+name);}
for(const inputRecord of source.compilationInputs){const bytes=read(source.directory+'/'+inputRecord.path),input=JSON.parse(bytes);assert.equal(sha(bytes),inputRecord.sha256,'Compiler input hash');assert.equal(Object.keys(input.sources).length,inputRecord.sources);for(const [name,s]of Object.entries(input.sources)){assert(files.has(name),'Unlisted source/context: '+name);assert.equal(s.content,read(source.directory+'/'+name).toString('utf8'),'Input differs from readable source');inputSources.add(name);}}
assert.deepEqual([...inputSources].sort(),[...files.keys()].sort(),'Complete production dependency closure');
const addresses=new Set();let current=0,historical=0,helpers=0;
assert.equal(manifest.additionalContracts.length,2);
for(const entry of [...manifest.contracts,...manifest.additionalContracts]){
 assert(/^0x[0-9a-fA-F]{40}$/.test(entry.address));assert(!addresses.has(entry.address.toLowerCase()),'Duplicate address');addresses.add(entry.address.toLowerCase());
 const dir=entry.directory;assert(/^(?:current|historical)\/[a-z0-9-]+$/.test(dir),'Invalid bundle path');
 const m=json(dir+'/'+(entry.metadata||'metadata.json'));assert.equal(m.chainId,manifest.chainId);assert.equal(m.address.toLowerCase(),entry.address.toLowerCase());assert.equal(m.status,entry.status);assert.equal(m.contractName,entry.contractName);assert.equal(m.runtimeCodeHash,entry.runtimeCodeHash);assert.equal(m.compilerVersion,'v0.8.20+commit.a1b79de6');
 const {bytes,input,result}=compile(dir+'/'+(m.input||'standard-input.json'));assert.equal(sha(bytes),m.standardInputSha256);
 if(entry.status==='current'){
  if(entry.category==='per-token-helper'){helpers++;assert.equal(m.boundToken,entry.boundToken);}else current++;
  assert.equal(m.role,entry.role);assert.equal(dir,source.directory);assert(source.compilationInputs.some(i=>i.path===m.input));
  if(process.argv.includes('--require-published')){
   assert.equal(m.sourceVerification.status,'verified','BscScan source verification incomplete: '+entry.role);
   assert.deepEqual(m.sourceVerification,entry.sourceVerification);
   const record=json(m.sourceVerification.evidence).results.find(r=>r.address.toLowerCase()===entry.address.toLowerCase());assert(record,'Missing source verification evidence');assert.equal(record.status,'verified');assert.equal(record.runtimeHash,entry.runtimeCodeHash);
  }
 }else{
  historical++;assert.equal(entry.status,'historical');assert.deepEqual(m.sources.map(s=>s.path).sort(),Object.keys(input.sources).sort());
  for(const s of m.sources){const b=read(dir+'/'+s.path);assert.equal(sha(b),s.sha256,'Historical source hash');assert.equal(b.toString('utf8'),input.sources[s.path].content);}
 }
 const [unit,name]=m.contractName.split(':'),c=result.contracts[unit][name];assert.deepEqual(c.abi,json(dir+'/'+(m.abi||'abi.json')),'ABI mismatch');
 assert.equal(sha(Buffer.from(c.evm.bytecode.object,'hex')),m.creationSha256,'Creation bytecode');let runtime=c.evm.deployedBytecode.object;assert.equal(sha(Buffer.from(runtime,'hex')),m.runtimeTemplateSha256,'Runtime template');
 const refs=c.evm.deployedBytecode.immutableReferences||{};assert.deepEqual(refs,m.immutableReferences);assert.deepEqual(Object.keys(refs).sort(),Object.keys(m.immutableValues).sort());
 for(const [id,locations]of Object.entries(refs)){
  const value=m.immutableValues[id];assert(/^0x[0-9a-f]{64}$/.test(value),'Invalid immutable word');
  if(entry.status==='current'){const binding=m.immutableBindings[id];assert(typeof binding.name==='string'&&/^0x[0-9a-f]{40}$/.test(binding.address));assert.equal(value,'0x'+binding.address.slice(2).padStart(64,'0'));}
  else assert.equal(value,'0x'+m.initializationAuthority.slice(2).toLowerCase().padStart(64,'0'));
  for(const loc of locations){assert.equal(loc.length,32);assert(loc.start>=0&&(loc.start+loc.length)*2<=runtime.length);runtime=runtime.slice(0,loc.start*2)+value.slice(2)+runtime.slice((loc.start+loc.length)*2);}
 }
 assert.equal(sha(Buffer.from(runtime,'hex')),m.runtimeSha256,'Runtime SHA256');assert.equal(codeHash(runtime),entry.runtimeCodeHash,'Complete deployed runtime keccak256');
 if(entry.status==='current'){
  const constructor=c.abi.find(a=>a.type==='constructor'),types=(constructor?.inputs||[]).map(a=>a.type);assert.deepEqual(types,m.constructor.types);assert.equal(types.length,m.constructor.args.length);
  const encoded=m.constructor.args.map((v,i)=>{if(types[i]==='address'){assert(/^0x[0-9a-fA-F]{40}$/.test(v));return v.slice(2).toLowerCase().padStart(64,'0');}assert.equal(types[i],'bool');assert.equal(typeof v,'boolean');return (v?'1':'0').padStart(64,'0');}).join('');assert.equal(encoded,m.constructor.encodedArguments);assert.equal(runtime.length/2,m.runtimeBytes);
 }
 console.log('Verified offline: '+(entry.role||dir)+' '+entry.address);
}
assert.equal(current,17);assert.equal(historical,5);assert.equal(helpers,2);
for(const key of ['core','websiteInstances','perTokenHelpers']){const v=manifest.verification[key];assert.equal(sha(read(v.evidence)),v.sha256,'Verification evidence hash');}
const clones=json(manifest.verification.websiteInstances.evidence);assert.equal(clones.chainId,56);assert.equal(clones.results.length,13);for(const c of clones.results){assert.equal(c.status,'verified');assert.equal(c.sourceVerified,true);assert.equal(c.proxyLinked,true);assert(addresses.has(c.implementation.toLowerCase()),'Instance implementation not published');}
console.log(`Reproduced ${current} current roles, ${helpers} per-token helpers and ${historical} historical bundles with ${cache.size} isolated inputs. Recorded 13 linked clone checks. No chain reads or transactions.`);
