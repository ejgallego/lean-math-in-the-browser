// Qualification of one raw Nat -> Nat package; fresh instance per reference case.
// This diagnostic host is not the eventual timed browser adapter.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { CASOS } from '../casos.mjs';
if (process.argv.length !== 5) throw Error('usage: node bench/backends/check-fir-nat.mjs FIR_ROOT ARTIFACT.wasm WORKLOAD');
const [producer, artifact, workload] = process.argv.slice(2).map((s,i) => i < 2 ? resolve(s) : s);
assert.ok(['primeCount', 'fibBits', 'partitionsBits', 'fib', 'partitions', 'lifePopulation'].includes(workload));
const importProducer = p => import(pathToFileURL(resolve(producer, p)));
const { ConcreteHost } = await importProducer('integration/talos/artifact/concrete-host.mjs');
const { instantiateModuleArtifact } = await importProducer('integration/talos/artifact/module-client.mjs');
const manifest = JSON.parse(readFileSync(artifact + '.json'));
const bytes = readFileSync(artifact);
assert.equal(manifest.sourceEntry, 'Bench.' + workload);
assert.deepEqual(manifest.params, ['tobject']);
assert.equal(manifest.result, 'tobject');
assert.deepEqual(manifest.imports, []);
assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
// Start with the smallest independently checked case; expand after frontier qualification.
const c = CASOS.find(c => c.w === workload);
assert.ok(c);
const host = new ConcreteHost([], undefined, undefined, manifest.closureDispatch, manifest.closureDescriptors);
const { entry } = await instantiateModuleArtifact({ bytes, manifest, host });
const arg = host.allocateNatural(BigInt(c.arg));
host.synchronizeResidentFrontierBeforeImport();
const raw = entry(arg) >>> 0;
host.synchronizeResidentFrontierBeforeImport();
const value = String((raw & 1) ? BigInt(raw >>> 1) : host.readNatural(raw));
assert.equal(createHash('sha256').update(value).digest('hex'), c.esperado);
console.log(JSON.stringify({ status: 'passed', workload, arg: c.arg, value,
  artifactSha256: createHash('sha256').update(bytes).digest('hex'),
  scope: 'smallest reference case, fresh instance; not a benchmark or retained-lifetime qualification' }));
