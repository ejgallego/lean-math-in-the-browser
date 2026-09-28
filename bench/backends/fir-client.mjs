// Diagnostic Node adapter for this producer's concrete ABI, not a stable SDK.
// No host operations are imported by the generated Wasm. ConcreteHost is used
// only to marshal input and copy results before cache-aware arena reclamation.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const textResult = (w, value) => w === 'tunnell'
  ? `${value.first} ${value.second} ${value.criterion}`
  : w === 'collatzRecord' ? `${value.fst} ${value.snd}` : String(value);

export async function createFirClient(producer, artifact, workload) {
  const { ConcreteHost } = await import(pathToFileURL(resolve(producer,
    'integration/talos/artifact/concrete-host.mjs')));
  const { instantiateModuleArtifact } = await import(pathToFileURL(resolve(producer,
    'integration/talos/artifact/module-client.mjs')));
  const bytes = readFileSync(artifact);
  const manifest = JSON.parse(readFileSync(artifact + '.json'));
  assert.equal(manifest.sourceEntry, 'Bench.' + workload);
  assert.deepEqual(manifest.params, ['tobject']);
  assert.equal(manifest.result, ['tunnell', 'collatzRecord'].includes(workload)
    ? 'object' : workload === 'isPrime' ? 'uint8' : 'tobject');
  assert.deepEqual(manifest.imports, []);
  assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
  const host = new ConcreteHost([], undefined, undefined, manifest.closureDispatch, manifest.closureDescriptors);
  const { instance, entry } = await instantiateModuleArtifact({ bytes, manifest, host });
  const exports = instance.exports;
  assert.equal(typeof exports.fir_heap_rewind, 'function');
  const nat = word => String(word & 1 ? BigInt(word >>> 1) : host.readNatural(word));
  const decode = raw => {
    if (workload === 'isPrime') { assert.ok(raw === 0 || raw === 1); return raw !== 0; }
    if (workload === 'mertens') {
      const value = (raw & 1) || host.readHeader(raw).kind === 5
        ? BigInt.asIntN(32, host.taggedPayload(raw)) : host.readInteger(raw);
      return String(value);
    }
    if (!['tunnell', 'collatzRecord'].includes(workload)) return nat(raw);
    const header = host.readHeader(raw);
    assert.equal(header.kind, 1); assert.equal(header.aux0, 0); assert.equal(header.aux2, 0);
    const field = i => host.readWordSlot(raw + 32 + 8 * i);
    if (workload === 'collatzRecord') {
      assert.equal(header.aux1, 2);
      return { fst: nat(field(0)), snd: nat(field(1)) };
    }
    assert.equal(header.aux1, 5);
    return { n: nat(field(0)), parity: host.readString(field(1)), first: nat(field(2)),
      second: nat(field(3)), verdict: host.readString(field(4)),
      squarefree: host.view.getUint8(raw + 72) !== 0,
      criterion: host.view.getUint8(raw + 73) !== 0 };
  };
  return {
    call(input) {
      const frontierBefore = exports.fir_heap_frontier() >>> 0;
      let peakFrontier;
      let value;
      try {
        const n = BigInt(input); assert.ok(n >= 0n);
        const argument = host.allocateNatural(n);
        host.synchronizeResidentFrontierBeforeImport();
        const raw = entry(argument) >>> 0;
        host.synchronizeResidentFrontierBeforeImport();
        peakFrontier = exports.fir_heap_frontier() >>> 0;
        value = decode(raw);
      } finally {
        exports.fir_heap_rewind(frontierBefore);
        const frontierAfter = exports.fir_heap_frontier() >>> 0;
        assert.ok(frontierAfter >= frontierBefore, 'cache floor moved backwards');
        // The host has no retained roots; all returned data was copied above.
        host.heapCursor = frontierAfter;
        host.addressLocations.clear(); host.descriptors.clear(); host.nextLocation = 0;
      }
      return { value, memory: { frontierBefore, peakFrontier,
        frontierAfter: exports.fir_heap_frontier() >>> 0,
        bytes: exports.memory.buffer.byteLength } };
    },
  };
}
