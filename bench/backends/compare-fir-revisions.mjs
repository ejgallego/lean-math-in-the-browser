// Matched old/new FIR package comparison; no builds, profiling or phase clocks.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join, dirname } from 'node:path';
import os from 'node:os';
import { CASOS } from '../casos.mjs';
import { createFirClient, textResult } from './fir-client.mjs';

const [oldManifest, oldChecks, newManifest, newChecks, output] = process.argv.slice(2);
assert.ok(output, 'usage: node compare-fir-revisions.mjs OLD_MANIFEST OLD_CHECKS NEW_MANIFEST NEW_CHECKS OUTPUT');
assert.ok(!existsSync(output), 'output already exists');
const hash = value => createHash('sha256').update(value).digest('hex');
const digest = path => hash(readFileSync(path));
const json = path => JSON.parse(readFileSync(path));
const files = [new URL(import.meta.url), new URL('./fir-client.mjs', import.meta.url),
  new URL('../casos.mjs', import.meta.url)];
const variants = Object.fromEntries([
  ['baseline', oldManifest, oldChecks], ['candidate', newManifest, newChecks],
].map(([name, path, checksPath]) => {
  const manifest = json(path), checks = json(checksPath);
  assert.ok(['passed', 'incomplete'].includes(checks.status));
  assert.equal(checks.manifestSha256, digest(path));
  assert.equal(checks.adapterSha256, digest(new URL('./fir-client.mjs', import.meta.url)));
  assert.equal(checks.referencesSha256, digest(new URL('../casos.mjs', import.meta.url)));
  files.push(path, checksPath);
  for (const item of manifest.artifacts) {
    assert.equal(digest(item.path), item.sha256);
    assert.equal(digest(item.path + '.json'), item.descriptorSha256);
    const identity = join(dirname(item.path), 'build-identity.json');
    assert.equal(digest(identity), item.buildIdentitySha256);
    assert.equal(json(identity).producer, manifest.producerCommit);
    files.push(item.path, item.path + '.json', identity);
  }
  for (const name of ['concrete-host.mjs', 'module-client.mjs'])
    files.push(join(manifest.producer, 'integration/talos/artifact', name));
  return [name, { manifest, checks }];
}));
const selection = [
  ['tunnell', 1000003], ['collatzRecord', 100000], ['primeCount', 1000000],
  ['mertens', 1000000], ['partitions', 3000], ['fib', 10000], ['fibBits', 10000],
  ['partitionsBits', 3000], ['isPrime', 127], ['lifePopulation', 100], ['fibBits', 100000],
];
const orders = Array.from({ length: 10 }, (_, i) => i % 2
  ? ['candidate', 'baseline'] : ['baseline', 'candidate']);
const report = { status: 'running', started: new Date().toISOString(),
  command: [process.execPath, ...process.execArgv, ...process.argv.slice(1)],
  node: process.version, v8: process.versions.v8, cpu: os.cpus()[0].model,
  platform: `${os.platform()} ${os.release()} ${os.arch()}`, loadBefore: os.loadavg(),
  producers: Object.fromEntries(Object.entries(variants).map(([name, v]) => [name, v.manifest.producerCommit])),
  files: files.map(path => ({ path: String(path), sha256: digest(path) })), selection, orders,
  policy: 'Ten rounds alternating AB/BA, one warmup per retained instance per input. Same source/adapter and Lean 4.34.1. Results and warm frontier checked outside timer. No builds or other client benchmarks concurrent.',
  boundary: 'FIR adapter call, result text and arena rewind. Startup excluded. No sampler or phase clocks.',
  caveats: 'Node only; uncontrolled background load, affinity, clock frequency and temperature. Descriptive medians, not confidence intervals.',
  warmups: [], rows: [] };
const save = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
save();
try {
  for (const [w, x] of selection) {
    const reference = CASOS.find(c => c.w === w && c.x === x); assert.ok(reference);
    const clients = {};
    for (const [name, { manifest, checks }] of Object.entries(variants)) {
      const qualified = checks.rows.filter(r => r.workload === w && r.x === x);
      assert.equal(qualified.length, 2); assert.ok(qualified.every(r => r.status === 'passed'));
      const artifact = manifest.artifacts.find(a => a.workload === w); assert.ok(artifact);
      clients[name] = await createFirClient(manifest.producer, artifact.path, w);
    }
    const invoke = engine => {
      const start = performance.now();
      const { value, memory } = clients[engine].call(reference.arg);
      const text = textResult(w, value);
      const ms = performance.now() - start;
      assert.equal(hash(text), reference.esperado, `${engine}/${w}/${x}`);
      assert.ok(Number.isFinite(ms) && ms >= 0);
      return { w, x, engine, ms, memory, valueSha256: hash(text) };
    };
    for (const name of orders[0]) report.warmups.push(invoke(name));
    for (const [round, order] of orders.entries()) for (const engine of order) {
      const result = invoke(engine);
      assert.equal(result.memory.frontierAfter, result.memory.frontierBefore, 'warm rewind');
      report.rows.push({ ...result, round, order }); save();
    }
    console.log(`${w}/${x}: 20 matched results checked`);
  }
  for (const [i, path] of files.entries()) assert.equal(digest(path), report.files[i].sha256);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { report.finished = new Date().toISOString(); report.loadAfter = os.loadavg(); save(); }
