// Resolve only the exact frozen Wasm artifact, checking V8's function byte offsets.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const [directory, outputName = 'summary.json'] = process.argv.slice(2);
assert.ok(directory, 'usage: node bench/backends/summarize-fir-profile.mjs RUN_DIR [OUTPUT_NAME]');
assert.ok(/^[A-Za-z0-9_.-]+\.json$/.test(outputName));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const run = JSON.parse(readFileSync(join(directory, 'run.json')));
assert.equal(run.status, 'passed'); assert.equal(run.mode, 'sample');
const raw = readFileSync(join(directory, 'cpu.cpuprofile'));
assert.equal(hash(raw), run.profileSha256);
const profile = JSON.parse(raw);
const wasm = readFileSync(run.artifact.path);
assert.equal(hash(wasm), run.artifact.sha256);
const inventoryPath = run.artifact.path + '.functions.json';
const inventoryBytes = readFileSync(inventoryPath);
assert.equal(hash(inventoryBytes), run.files.find(f => f.path === inventoryPath).sha256);
const inventory = JSON.parse(inventoryBytes);
assert.equal(wasm.length, inventory.artifact.byteLength);
assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(wasm)), []);
assert.equal(inventory.artifact.functionImports, 0);
let cursor = 8;
const uleb = () => {
  let value = 0, shift = 0;
  for (;;) {
    assert.ok(cursor < wasm.length && shift < 35);
    const byte = wasm[cursor++]; value += (byte & 127) * 2 ** shift;
    if (byte < 128) return value;
    shift += 7;
  }
};
const bodies = [];
while (cursor < wasm.length) {
  const section = wasm[cursor++], size = uleb(), end = cursor + size;
  assert.ok(end <= wasm.length);
  if (section === 10) {
    const count = uleb(); assert.equal(count, inventory.functions.length);
    for (let i = 0; i < count; i++) {
      const size = uleb(), start = cursor; cursor += size;
      bodies.push({ index: i, name: inventory.functions[i], start, end: cursor, bytes: size });
    }
    assert.equal(cursor, end);
  }
  cursor = end;
}
assert.equal(bodies.length, inventory.artifact.definedFunctions);
const nodes = new Map(profile.nodes.map(n => [n.id, n]));
const parents = new Map();
for (const n of nodes.values()) for (const child of n.children ?? []) {
  assert.ok(!parents.has(child)); parents.set(child, n.id);
}
const wasmUrls = new Set(), labels = new Map(), resolved = new Map(), trampolines = new Set();
for (const n of nodes.values()) {
  const f = n.callFrame;
  if (f.url.startsWith('wasm://')) {
    wasmUrls.add(f.url);
    if (f.functionName.startsWith('js-to-wasm:')) {
      labels.set(n.id, f.functionName); trampolines.add(n.id); continue;
    }
    const match = /^wasm-function\[(\d+)\]$/.exec(f.functionName);
    assert.ok(match, `unrecognized Wasm frame ${f.functionName}`);
    const index = Number(match[1]), body = bodies[index]; assert.ok(body);
    assert.equal(f.columnNumber, body.start, `function ${index} offset differs`);
    labels.set(n.id, body.name); resolved.set(index, body);
  } else labels.set(n.id, f.functionName || `<anonymous@${f.url}:${f.lineNumber + 1}>`);
}
assert.equal(wasmUrls.size, 1, 'expected exactly one sampled Wasm module');
assert.equal(profile.samples.length, profile.timeDeltas.length);
const self = new Map(), inclusive = new Map(), stacks = new Map(), buckets = new Map();
const rootOnlyWasm = new Map();
const add = (map, key, weight) => map.set(key, (map.get(key) ?? 0) + weight);
let time = profile.startTime, sampledUs = 0;
for (let i = 0; i < profile.samples.length; i++) {
  const delta = profile.timeDeltas[i]; assert.ok(delta >= 0);
  // Attribute the interval ending at each observed sample to that sample.
  // Clip at profile.endTime; leave the unobserved tail explicitly unassigned.
  const weight = Math.max(0, Math.min(time + delta, profile.endTime) - time);
  time += delta; sampledUs += weight;
  const id = profile.samples[i], node = nodes.get(id); assert.ok(node);
  const name = labels.get(id); add(self, name, weight);
  if (node.callFrame.url.startsWith('wasm://') && !trampolines.has(id)
      && labels.get(parents.get(id)) === '(root)') add(rootOnlyWasm, name, weight);
  const bucket = trampolines.has(id) ? 'JS/Wasm trampoline'
    : node.callFrame.url.startsWith('wasm://') ? 'resolved Wasm'
    : name === '(garbage collector)' ? 'V8 GC' : name === '(idle)' ? 'V8 idle'
    : name.startsWith('(') ? 'V8 other' : 'JavaScript';
  add(buckets, bucket, weight);
  const chain = [];
  for (let current = id; current !== undefined; current = parents.get(current)) chain.push(labels.get(current));
  for (const label of new Set(chain)) add(inclusive, label, weight);
  // Retain full call trees in the raw profile; show the multiplication subtree here.
  const mul = chain.indexOf('fir_nat_mul_generic');
  if (mul >= 0) add(stacks, chain.slice(0, mul + 1).reverse().join(' → '), weight);
}
const sorted = map => [...map].sort((a,b) => b[1]-a[1]).map(([name, us]) => ({ name, ms: us/1000, percent: us/sampledUs*100 }));
const summary = { input: run.input, repetitions: run.reps,
  artifactSha256: run.artifact.sha256, inventorySha256: hash(inventoryBytes), profileSha256: hash(raw),
  summarizerSha256: hash(readFileSync(new URL(import.meta.url))),
  mapping: { wasmUrl: [...wasmUrls][0], definedFunctions: bodies.length, resolvedFunctions: resolved.size,
    trampolineNodes: trampolines.size,
    evidence: 'Single Wasm module; exact artifact/inventory hashes; every indexed Wasm frame and V8 column offset matches its encoded function body start. JS/Wasm trampolines are classified separately.',
    functions: [...resolved.values()].sort((a,b) => a.index-b.index) },
  weighting: 'Observed timeDeltas in microseconds; preceding interval assigned to ending sample, clipped at profile end. Inclusive symbols counted once per stack; never sum inclusive rows. No phase slicing or clock-origin assumptions.',
  samples: profile.samples.length, requestedIntervalUs: run.sampling.intervalUs,
  profileDurationMs: (profile.endTime-profile.startTime)/1000, attributedMs: sampledUs/1000,
  unobservedTailMs: Math.max(0, profile.endTime-time)/1000,
  callerCoverage: { rootOnlyWasm: sorted(rootOnlyWasm),
    rootOnlyWasmPercent: [...rootOnlyWasm.values()].reduce((a,b) => a+b, 0)/sampledUs*100,
    caveat: 'Root-only Wasm samples have resolved leaf symbols but no usable caller ancestry. Inclusive multiplication share is the observed stack share, not a claim of complete unwinding.' },
  buckets: sorted(buckets), self: sorted(self), inclusive: sorted(inclusive), multiplicationStacks: sorted(stacks) };
writeFileSync(join(directory, outputName), JSON.stringify(summary, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ input: run.input, samples: summary.samples, mapping: summary.mapping.evidence,
  buckets: summary.buckets, self: summary.self.slice(0, 12), inclusive: summary.inclusive.filter(r => r.name.startsWith('fir_')).slice(0, 8),
  multiplicationStacks: summary.multiplicationStacks.slice(0, 6) }, null, 2));
