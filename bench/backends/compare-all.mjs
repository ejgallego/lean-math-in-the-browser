// Same-campaign backend comparison with checked outputs and balanced engine order.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve, dirname, join } from 'node:path';
import os from 'node:os';
import { CASOS } from '../casos.mjs';
import * as JS from '../js-baseline-revised.mjs';
import { createFirClient, textResult } from './fir-client.mjs';
import { createEmscriptenClient } from './emscripten-client.mjs';
import { createVirRuntime } from '../../site/lean-vir/js/vir-runtime-node.js';

const [manifestArg, firChecksArg, cManifestArg, cChecksArg, outputArg, option, chosenWorkload] = process.argv.slice(2);
assert.ok(outputArg && (option === undefined || option === '--workload' && chosenWorkload),
  'usage: node compare-all.mjs FIR_MANIFEST FIR_CHECKS C_MANIFEST C_CHECKS OUTPUT [--workload NAME]');
assert.ok(!existsSync(outputArg));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const digest = path => hash(readFileSync(path));
const json = path => JSON.parse(readFileSync(path));
const root = new URL('../../', import.meta.url).pathname;
const firManifest = json(manifestArg), firChecks = json(firChecksArg), cChecks = json(cChecksArg);
assert.ok(['passed', 'incomplete'].includes(firChecks.status));
assert.ok(['passed', 'incomplete'].includes(cChecks.status));
assert.equal(firChecks.manifestSha256, digest(manifestArg));
assert.equal(cChecks.manifestSha256, digest(cManifestArg));
assert.equal(firChecks.adapterSha256, digest(new URL('./fir-client.mjs', import.meta.url)));
assert.equal(cChecks.adapterSha256, digest(new URL('./emscripten-client.mjs', import.meta.url)));
const cli = join(root, '.lake/build/bin/tunnell_cli');
const pkgRoot = join(root, '.lake/build/vir/module-sets');
const pkgs = ['Bench.parts/0.irpkg', 'Bench.parts/1.irpkg', 'Bench.irpkg'].map(p => join(pkgRoot, p));
const recursiveFiles = p => readdirSync(p, { withFileTypes: true }).flatMap(e =>
  e.isDirectory() ? recursiveFiles(join(p, e.name)) : [join(p, e.name)]);
const files = [manifestArg, firChecksArg, cManifestArg, cChecksArg, cli, ...pkgs,
  ...['lean-toolchain', 'lake-manifest.json', 'Tunnell.lean', 'Bench.lean', 'Main.lean',
    'bench/casos.mjs', 'bench/js-baseline-revised.mjs', 'site/lean-vir/wasm/vir-upstream.wasm',
    'bench/backends/compare-all.mjs', 'bench/backends/fir-client.mjs', 'bench/backends/emscripten-client.mjs'].map(p => join(root, p)),
  ...recursiveFiles(join(root, 'site/lean-vir/js')),
  join(firManifest.producer, 'integration/lcnf-c-wasm/emscripten-loader.mjs')];
const cm = json(cManifestArg);
for (const a of Object.values(cm.artifacts)) files.push(join(dirname(resolve(cManifestArg)), a.file));
for (const item of firManifest.artifacts) {
  assert.equal(digest(item.path), item.sha256);
  assert.equal(digest(item.path + '.json'), item.descriptorSha256);
  files.push(item.path, item.path + '.json', join(dirname(item.path), 'build-identity.json'));
}
const engines = ['native', 'js', 'vir', 'fir', 'cwasm'];
// Odd-size Williams design: cyclic relabelings of one row and their reverses.
const base = [0, 1, 4, 2, 3];
const orders = Array.from({ length: 5 }, (_, offset) => base.map(i => engines[(i + offset) % 5]));
orders.push(...orders.map(row => row.toReversed()));
for (const e of engines) for (let position = 0; position < 5; position++)
  assert.equal(orders.filter(row => row[position] === e).length, 2);
for (const a of engines) for (const b of engines) if (a !== b)
  assert.equal(orders.reduce((n,row) => n + row.filter((e,i) => i > 0 && row[i-1] === a && e === b).length, 0), 2);
const fullSelection = { tunnell: 1000003, collatzRecord: 100000, primeCount: 1000000,
  mertens: 1000000, partitions: 3000, fib: 10000, fibBits: 10000,
  partitionsBits: 3000, isPrime: 127, lifePopulation: 100 };
assert.ok(!chosenWorkload || Object.hasOwn(fullSelection, chosenWorkload), `unknown workload: ${chosenWorkload}`);
const selection = chosenWorkload ? { [chosenWorkload]: fullSelection[chosenWorkload] } : fullSelection;
const report = { status: 'running', started: new Date().toISOString(),
  command: [process.execPath, ...process.execArgv, ...process.argv.slice(1)],
  node: process.version, v8: process.versions.v8, cpu: os.cpus()[0].model,
  platform: `${os.platform()} ${os.release()} ${os.arch()}`, loadBefore: os.loadavg(),
  producer: firManifest.producer, producerCommit: firManifest.producerCommit,
  inputs: Object.fromEntries(files.map(p => [resolve(p), digest(p)])), selection, orders,
  policy: 'Same inputs as earlier balanced FIR comparison; require current qualification. Ten orders balance each position and within-round predecessor pair. One warmup per retained JS/Wasm instance; native one warmup in each fresh process. All measured results checked outside timers.',
  boundary: 'JS/FIR/VIR/C-Wasm call through adapter plus text result and cleanup. Native in-process Lean computation and formatting (second of two calls). Startup excluded. C-Wasm includes decimal argument parsing; native/VIR/FIR input handling differs. No phase clocks or sampler.',
  caveats: 'Native, FIR, C-Wasm and new VIR packages use Lean 4.34.1; VIR runtime binary remains the original bundled artifact. Diagnostic FIR adapter. No CPU affinity/governor/background-load control. Node only. JS typed arrays and BigInt differ from Lean representations.',
  rows: [] };
const save = () => writeFileSync(outputArg, JSON.stringify(report, null, 2) + '\n'); save();
const vir = await createVirRuntime({ wasmBytes: readFileSync(join(root, 'site/lean-vir/wasm/vir-upstream.wasm')), irPackageSet: pkgs.map(p => readFileSync(p)) });
report.virPackageMetadata = vir.interfaceManifest.metadata;
const cwasm = await createEmscriptenClient(firManifest.producer, cManifestArg);
try {
  for (const item of firManifest.artifacts.filter(a => Object.hasOwn(selection, a.workload))) {
    const w = item.workload, x = selection[w];
    const c = CASOS.find(c => c.w === w && c.x === x); assert.ok(c);
    const fq = firChecks.rows.filter(r => r.workload === w && r.x === x);
    assert.equal(fq.length, 2); assert.ok(fq.every(r => r.status === 'passed'));
    const cq = cChecks.rows.filter(r => r.w === w && r.x === x);
    assert.equal(cq.length, 4); assert.ok(cq.every(r => r.status === 'passed'));
    const fir = await createFirClient(firManifest.producer, item.path, w);
    const arg = w === 'isPrime' ? BigInt(c.arg) : c.arg;
    const invoke = engine => {
      if (engine === 'native') {
        const lines = execFileSync(cli, ['--time', w, String(c.arg), '2'], { encoding: 'utf8', timeout: 30000 }).trim().split('\n');
        assert.equal(lines.length, 3);
        return { text: lines[0], ms: Number(lines[2]) / 1e6 };
      }
      const start = performance.now();
      const text = engine === 'js' ? JS[w](arg) : engine === 'cwasm' ? cwasm.call(w, c.arg)
        : textResult(w, engine === 'fir' ? fir.call(c.arg).value : vir.call('Bench.' + w, arg));
      return { text, ms: performance.now() - start };
    };
    for (const engine of ['js', 'vir', 'fir', 'cwasm']) assert.equal(hash(invoke(engine).text), c.esperado);
    for (const [round, order] of orders.entries()) {
      for (const engine of order) {
        const result = invoke(engine); assert.equal(hash(result.text), c.esperado, `${engine}/${w}/${x}`);
        assert.ok(Number.isFinite(result.ms) && result.ms >= 0);
        report.rows.push({ w, x, engine, round, order, ms: result.ms, valueSha256: hash(result.text) }); save();
      }
    }
    console.log(`${w}/${x}: 50 measured results checked`);
  }
  for (const [p, expected] of Object.entries(report.inputs)) assert.equal(digest(p), expected, p);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { cwasm.dispose(); vir.dispose(); report.finished = new Date().toISOString(); report.loadAfter = os.loadavg(); save(); }
