// Focused attribution of the frozen fibBits package. Does not regenerate Wasm.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, join, relative, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Session } from 'node:inspector/promises';
import os from 'node:os';
import { CASOS } from '../casos.mjs';

const [manifestArg, outputArg, mode, inputArg, repsArg] = process.argv.slice(2);
assert.ok(manifestArg && outputArg && ['phases', 'sample'].includes(mode),
  'usage: node bench/backends/profile-fir.mjs MANIFEST OUT_DIR phases|sample INPUT REPS');
const n = Number(inputArg), reps = Number(repsArg);
assert.ok([10000, 100000].includes(n));
assert.ok(Number.isSafeInteger(reps) && reps > 0 && reps <= 100);
const hash = data => createHash('sha256').update(data).digest('hex');
const manifest = JSON.parse(readFileSync(manifestArg));
const artifact = manifest.artifacts.find(a => a.workload === 'fibBits');
assert.ok(artifact);
const producer = resolve(manifest.producer), out = resolve(outputArg);
const underDeps = relative(join(producer, '.deps'), out);
assert.ok(underDeps && !underDeps.startsWith('..') && !underDeps.startsWith('/'), 'use producer-local .deps output');
const git = args => execFileSync('git', args, { cwd: producer, encoding: 'utf8' }).trim();
assert.equal(git(['status', '--porcelain']), '', 'producer must be clean');
const identityPath = join(dirname(artifact.path), 'build-identity.json');
const build = JSON.parse(readFileSync(identityPath));
assert.equal(git(['rev-parse', 'HEAD']), build.producer);
assert.equal(hash(readFileSync(identityPath)), artifact.buildIdentitySha256);
assert.equal(hash(readFileSync(artifact.path)), artifact.sha256);
assert.equal(hash(readFileSync(artifact.path + '.json')), artifact.descriptorSha256);
const reference = CASOS.find(c => c.w === 'fibBits' && c.arg === n);
assert.ok(reference);
const paths = [artifact.path, artifact.path + '.json', artifact.path + '.functions.json', artifact.path + '.lcnf',
  identityPath, new URL(import.meta.url), new URL('./fir-client.mjs', import.meta.url),
  new URL('../casos.mjs', import.meta.url), join(producer, 'integration/talos/artifact/concrete-host.mjs'),
  join(producer, 'integration/talos/artifact/module-client.mjs')];
const report = { status: 'running', mode, input: n, reps, warmups: 1,
  started: new Date().toISOString(), command: [process.execPath, ...process.execArgv, ...process.argv.slice(1)],
  node: process.version, v8: process.versions.v8, cpu: os.cpus()[0].model,
  platform: `${os.platform()} ${os.release()} ${os.arch()}`, loadBefore: os.loadavg(),
  producerCommit: build.producer, lean: build.lean, artifact, expectedSha256: reference.esperado,
  manifestSha256: hash(readFileSync(manifestArg)),
  files: paths.map(path => ({ path: String(path), sha256: hash(readFileSync(path)) })),
  sampling: mode === 'sample' ? { api: 'Node inspector Profiler', intervalUs: 1000,
    scope: 'Main Node isolate, measured call loop including validation, excluding instantiation and warmup' } : null,
  boundary: 'marshal = Nat encoding and host frontier sync; execute = raw Wasm entry only; decode = view refresh and Nat-to-decimal copy; cleanup = cache-aware rewind and host bookkeeping. Total independently timed. Correctness hash and warm-frontier checks outside total.',
  rows: [] };
mkdirSync(out, { recursive: false });
const save = () => writeFileSync(join(out, 'run.json'), JSON.stringify(report, null, 2) + '\n');
save();
const { ConcreteHost } = await import(pathToFileURL(join(producer, 'integration/talos/artifact/concrete-host.mjs')));
const { instantiateModuleArtifact } = await import(pathToFileURL(join(producer, 'integration/talos/artifact/module-client.mjs')));
const bytes = readFileSync(artifact.path);
const descriptor = JSON.parse(readFileSync(artifact.path + '.json'));
assert.equal(descriptor.sourceEntry, 'Bench.fibBits');
assert.deepEqual(descriptor.params, ['tobject']); assert.equal(descriptor.result, 'tobject');
assert.deepEqual(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
assert.deepEqual(descriptor.imports, []);
const host = new ConcreteHost([], undefined, undefined, descriptor.closureDispatch, descriptor.closureDescriptors);
const { instance, entry } = await instantiateModuleArtifact({ bytes, manifest: descriptor, host });
const exports = instance.exports;
function call() {
  const t0 = performance.now();
  const before = exports.fir_heap_frontier() >>> 0;
  let value, raw, peak, t1, t2, t3, t4;
  try {
    const argument = host.allocateNatural(BigInt(n));
    host.synchronizeResidentFrontierBeforeImport();
    t1 = performance.now();
    raw = entry(argument) >>> 0;
    t2 = performance.now();
    host.synchronizeResidentFrontierBeforeImport();
    value = String(raw & 1 ? BigInt(raw >>> 1) : host.readNatural(raw));
    t3 = performance.now();
    peak = exports.fir_heap_frontier() >>> 0;
  } finally {
    exports.fir_heap_rewind(before);
    host.heapCursor = exports.fir_heap_frontier() >>> 0;
    host.addressLocations.clear(); host.descriptors.clear(); host.nextLocation = 0;
    t4 = performance.now();
  }
  const after = exports.fir_heap_frontier() >>> 0;
  assert.equal(hash(value), reference.esperado);
  assert.ok(after >= before);
  return { value, raw, marshalMs: t1-t0, executeMs: t2-t1, decodeMs: t3-t2,
    cleanupMs: t4-t3, totalMs: t4-t0, memory: { before, peak, after, bytes: exports.memory.buffer.byteLength } };
}
let session;
try {
  report.warmup = call();
  if (mode === 'sample') {
    session = new Session(); session.connect();
    await session.post('Profiler.enable');
    await session.post('Profiler.setSamplingInterval', { interval: 1000 });
    await session.post('Profiler.start');
  }
  for (let i = 0; i < reps; i++) {
    const row = call(); assert.equal(row.memory.after, row.memory.before, 'warm scratch was not reclaimed');
    report.rows.push({ repetition: i, ...row });
  }
  if (session) {
    const { profile } = await session.post('Profiler.stop');
    const profileText = JSON.stringify(profile);
    writeFileSync(join(out, 'cpu.cpuprofile'), profileText + '\n');
    report.profileSha256 = hash(profileText + '\n');
  }
  for (const [i, path] of paths.entries()) assert.equal(hash(readFileSync(path)), report.files[i].sha256);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally {
  session?.disconnect(); report.finished = new Date().toISOString(); report.loadAfter = os.loadavg(); save();
}
console.log(JSON.stringify({ status: report.status, mode, input: n, rows: report.rows, output: out }, null, 2));
