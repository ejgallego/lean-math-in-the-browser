// Full Verdict differential: direct Tunnell uses fresh instances; Bench uses retained calls.
// The physical decoder is specific to this captured Verdict layout, not a stable ABI.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createVirRuntime } from '../../site/lean-vir/js/vir-runtime-node.js';
import { createFirClient } from './fir-client.mjs';
const [producerArg, artifactArg, limitArg = '400'] = process.argv.slice(2);
if (!producerArg || !artifactArg || process.argv.length > 5) throw Error('usage: node bench/backends/check-fir-tunnell.mjs FIR_ROOT ARTIFACT.wasm [limit]');
const producer = resolve(producerArg), artifact = resolve(artifactArg), limit = Number(limitArg);
assert.ok(Number.isSafeInteger(limit) && limit > 0 && limit <= 10000);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const read = p => readFileSync(new URL('../../' + p, import.meta.url));
const { ConcreteHost } = await import(pathToFileURL(join(producer, 'integration/talos/artifact/concrete-host.mjs')));
const { instantiateModuleArtifact } = await import(pathToFileURL(join(producer, 'integration/talos/artifact/module-client.mjs')));
const bytes = readFileSync(artifact);
const manifest = JSON.parse(readFileSync(artifact + '.json'));
assert.ok(['Tunnell.tunnell', 'Bench.tunnell'].includes(manifest.sourceEntry));
assert.ok(!existsSync(artifact + '.checks.json'), 'output already exists');
const retained = manifest.sourceEntry === 'Bench.tunnell'
  ? await createFirClient(producer, artifact, 'tunnell') : undefined;
assert.deepEqual(manifest.params, ['tobject']);
assert.equal(manifest.result, 'object');
assert.deepEqual(manifest.imports, []);
assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
const vir = await createVirRuntime({ wasmBytes: read('site/lean-vir/wasm/vir-upstream.wasm'), irPackageSet: [read('site/tunnell.irpkg')] });
const pythonBytes = read('tests/out/python.txt');
const python = new Map(pythonBytes.toString().trim().split('\n').map(line => {
  const [n, first, second, criterion, squarefree] = line.split(/\s+/);
  return [Number(n), { first, second, criterion: criterion === 'true', squarefree: squarefree === 'true' }];
}));
for (let n = 1; n <= limit; n++) {
  let actual;
  if (retained) {
    actual = retained.call(n).value;
  } else {
  const host = new ConcreteHost([], undefined, undefined, manifest.closureDispatch, manifest.closureDescriptors);
  const { entry } = await instantiateModuleArtifact({ bytes, manifest, host });
  const argument = host.allocateNatural(BigInt(n));
  host.synchronizeResidentFrontierBeforeImport();
  const result = entry(argument) >>> 0;
  host.synchronizeResidentFrontierBeforeImport();
  const header = host.readHeader(result);
  assert.equal(header.kind, 1); assert.equal(header.aux0, 0); assert.equal(header.aux1, 5); assert.equal(header.aux2, 0);
  // Captured constructor has five object slots and two UInt8 fields.
  const field = i => host.readWordSlot(result + 32 + 8 * i);
  const nat = raw => String(raw & 1 ? BigInt(raw >>> 1) : host.readNatural(raw));
  actual = {
    n: nat(field(0)), parity: host.readString(field(1)), first: nat(field(2)),
    second: nat(field(3)), verdict: host.readString(field(4)),
    squarefree: host.view.getUint8(result + 72) !== 0,
    criterion: host.view.getUint8(result + 73) !== 0,
  };
  }
  const expected = vir.call('Tunnell.tunnell', n);
  assert.deepEqual(actual, expected, `FIR/VIR mismatch at n=${n}`);
  const reference = python.get(n); assert.ok(reference);
  for (const key of ['first', 'second', 'criterion', 'squarefree']) assert.equal(actual[key], reference[key], `FIR/Python ${key} mismatch at n=${n}`);
}
const report = { status: 'passed', count: limit, first: 1, last: limit,
  artifactSha256: hash(bytes), descriptorSha256: hash(readFileSync(artifact + '.json')),
  pythonReferenceSha256: hash(pythonBytes), virPackageSha256: hash(read('site/tunnell.irpkg')),
  virRuntimeSha256: hash(read('site/lean-vir/wasm/vir-upstream.wasm')),
  harnessSha256: hash(readFileSync(new URL(import.meta.url))), node: process.version,
  adapterSha256: retained ? hash(readFileSync(new URL('./fir-client.mjs', import.meta.url))) : null,
  scope: `${retained ? 'Retained instance with per-call rewind' : 'Fresh instance per input'}; all Verdict fields vs VIR, counts/flags vs Python. Not browser qualification.`,
};
writeFileSync(artifact + '.checks.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
console.log(report);
