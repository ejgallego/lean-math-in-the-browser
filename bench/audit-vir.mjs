// Audit the shipped VIR API without changing SDK, Wasm, packages or Lean code.
// timeout 180s node bench/audit-vir.mjs phases|methods FRESH_OUTPUT_DIR
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import { createVirRuntime } from '../site/lean-vir/js/vir-runtime-node.js';
import { CASOS } from './casos.mjs';

const [mode, outputArg] = process.argv.slice(2);
assert.ok(['phases', 'methods'].includes(mode) && outputArg,
  'usage: node bench/audit-vir.mjs phases|methods FRESH_OUTPUT_DIR');
const root = fileURLToPath(new URL('../', import.meta.url)), output = resolve(outputArg);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const read = p => readFileSync(join(root, p));
function files(dir) {
  return readdirSync(join(root, dir), { withFileTypes: true }).flatMap(e =>
    e.isDirectory() ? files(join(dir, e.name)) : [join(dir, e.name)]);
}
const pkgs = ['bench/pkg/Bench.parts/0.irpkg', 'bench/pkg/Bench.parts/1.irpkg', 'bench/pkg/Bench.irpkg'];
const inputs = ['site/lean-vir/wasm/vir-upstream.wasm', ...files('site/lean-vir/js'), ...pkgs,
  'bench/pkg/Bench.irpkg-set.json', 'Tunnell.lean', 'Bench.lean', 'Main.lean', 'lean-toolchain',
  'lake-manifest.json', 'bench/casos.mjs', 'bench/audit-vir.mjs'];
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const report = { status: 'running', mode, started: new Date().toISOString(),
  command: [process.execPath, ...process.execArgv, ...process.argv.slice(1)],
  node: process.version, v8: process.versions.v8, cpu: os.cpus()[0].model,
  platform: `${os.platform()} ${os.release()} ${os.arch()}`, loadBefore: os.loadavg(),
  clientCommit: git('rev-parse', 'HEAD'), dirtyStatus: git('status', '--porcelain'),
  trackedDiffSha256: hash(git('diff', 'HEAD')), inputs: Object.fromEntries(inputs.map(p => [p, hash(read(p))])),
  policy: mode === 'phases'
    ? 'Diagnostic callTimed: one warmup plus three measured calls per workload. Largest reference input except decimal fib at 100000; earlier million-input decode campaign retained separately. Every result hash checked outside callTimed.'
    : 'Ordinary calls, no callTimed instrumentation. Named call vs documented exportsByName method, same runtime. Four AB/BA pairs; one warmup per method. Small inputs batch 25 calls, large inputs one. Every returned value checked outside each timed batch.',
  rows: [] };
mkdirSync(output, { recursive: false });
const save = () => writeFileSync(join(output, 'run.json'), JSON.stringify(report, null, 2) + '\n');
save();
const vir = await createVirRuntime({ wasmBytes: read(inputs[0]), irPackageSet: pkgs.map(read) });
report.manifest = vir.interfaceManifest;
assert.equal(report.manifest.hostImports.length, 0);
assert.ok(report.manifest.exports.every(e => e.effect === 'pure'));
const text = (w,v) => w === 'tunnell' ? `${v.first} ${v.second} ${v.criterion}`
  : w === 'collatzRecord' ? `${v.fst} ${v.snd}` : String(v);
const validate = (c,value) => assert.equal(hash(text(c.w,value)), c.esperado, `${c.w}/${c.x}`);
const cacheState = entry => {
  const cache = vir.entryCallCache.get(entry);
  return { exportIndex: cache.exportIndex, callSlot: cache.callSlot ?? null,
    hasObjectPlan: cache.objectCallPlan !== undefined && cache.objectCallPlan !== null };
};
try {
  if (mode === 'phases') {
    report.cache = [];
    for (const w of [...new Set(CASOS.map(c => c.w))]) {
      const c = w === 'fib' ? CASOS.find(c => c.w === w && c.x === 100000) : CASOS.filter(c => c.w === w).at(-1);
      const name = 'Bench.' + c.w, arg = c.w === 'isPrime' ? BigInt(c.arg) : c.arg;
      const entry = vir.findManifestEntry(name), before = cacheState(entry);
      validate(c, vir.call(name, arg));
      const warmed = cacheState(entry);
      assert.ok(warmed.callSlot > 0 && warmed.hasObjectPlan);
      for (let repetition = 0; repetition < 3; repetition++) {
        const { value, timings } = vir.callTimed(name, arg);
        validate(c, value); assert.equal(timings.hostMs, 0);
        assert.deepEqual(cacheState(entry), warmed);
        report.rows.push({ w: c.w, x: c.x, repetition, timings, valueSha256: hash(text(c.w,value)) });
        save();
      }
      report.cache.push({ entry: name, before, warmed, after: cacheState(entry) });
      save(); console.log(`${c.w}/${c.x}: all phases checked; slot ${warmed.callSlot} reused; JS host time 0`);
    }
  } else {
    const selection = [['primeCount', 1000], ['primeCount', 1000000], ['fibBits', 1000], ['fibBits', 1000000], ['tunnell', 1003]];
    for (const [w,x] of selection) {
      const c = CASOS.find(c => c.w === w && c.x === x); assert.ok(c);
      const entry = vir.findManifestEntry('Bench.' + w);
      const generated = vir.exportsByName[entry.jsName]; assert.equal(typeof generated, 'function');
      const invoke = { named: () => vir.call(entry.entry, c.arg), generated: () => generated(c.arg) };
      for (const method of ['named', 'generated']) validate(c, invoke[method]());
      const batchSize = x >= 1000000 ? 1 : 25;
      for (let pair = 0; pair < 4; pair++) {
        for (const [pass, order] of [['named', 'generated'], ['generated', 'named']].entries()) {
          for (const method of order) {
            const values = new Array(batchSize);
            const start = performance.now();
            for (let i = 0; i < batchSize; i++) values[i] = invoke[method]();
            const elapsedMs = performance.now() - start;
            for (const value of values) validate(c, value);
            report.rows.push({ w, x, pair, pass, order, method, batchSize, elapsedMs, perCallMs: elapsedMs/batchSize, status: 'passed' });
            save();
          }
        }
      }
      console.log(`${w}/${x}: named/generated AB/BA complete, every result checked`);
    }
  }
  for (const p of inputs) assert.equal(hash(read(p)), report.inputs[p], `${p} changed`);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { vir.dispose(); report.finished = new Date().toISOString(); report.loadAfter = os.loadavg(); save(); }
