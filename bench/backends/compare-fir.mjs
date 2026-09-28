// Exploratory same-machine comparison; six balanced orders, every timed result checked.
// FIR uses a diagnostic marshalling adapter. Native/FIR have different Lean pins.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import os from 'node:os';
import { CASOS } from '../casos.mjs';
import { createFirClient, textResult } from './fir-client.mjs';
import { createVirRuntime } from '../../site/lean-vir/js/vir-runtime-node.js';

const [manifestArg, checksArg, outputArg] = process.argv.slice(2);
if (!outputArg) throw Error('usage: node bench/backends/compare-fir.mjs MANIFEST.json CHECKS.json OUTPUT.json');
assert.ok(!existsSync(outputArg));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const read = p => readFileSync(new URL('../../' + p, import.meta.url));
const manifest = JSON.parse(readFileSync(manifestArg));
const checks = JSON.parse(readFileSync(checksArg));
assert.ok(['passed', 'incomplete'].includes(checks.status));
assert.equal(checks.manifestSha256, hash(readFileSync(manifestArg)));
assert.equal(checks.adapterSha256, hash(readFileSync(new URL('./fir-client.mjs', import.meta.url))));
const cli = new URL('../../.lake/build/bin/tunnell_cli', import.meta.url).pathname;
const files = ['lean-toolchain', 'Bench.lean', 'Tunnell.lean', 'Main.lean', 'bench/casos.mjs',
  'site/lean-vir/js/vir-runtime-node.js', 'site/lean-vir/js/vir-runtime.js',
  'site/lean-vir/wasm/vir-upstream.wasm', 'bench/pkg/Bench.parts/0.irpkg',
  'bench/pkg/Bench.parts/1.irpkg', 'bench/pkg/Bench.irpkg'];
const report = { status: 'running', started: new Date().toISOString(), node: process.version, v8: process.versions.v8,
  cpu: os.cpus()[0].model, platform: `${os.platform()} ${os.release()} ${os.arch()}`, loadBefore: os.loadavg(),
  producer: manifest.producer, manifestSha256: hash(readFileSync(manifestArg)), checksSha256: hash(readFileSync(checksArg)),
  harnessSha256: hash(readFileSync(new URL(import.meta.url))), adapterSha256: checks.adapterSha256,
  inputs: Object.fromEntries(files.map(p => [p, hash(read(p))])), nativeSha256: hash(readFileSync(cli)),
  selection: 'Largest qualified input per workload with every diagnostic first-call sample below 1000ms; selection is exploratory.',
  boundary: 'FIR/VIR call + copied/decoded result + common text formatting; FIR includes diagnostic host checks and cache-aware rewind. Native in-process function+Lean formatting, one warmup in each fresh process. Initialization/compile/load excluded. Every measured value hash checked outside timer.',
  caveats: 'FIR Lean 4.34.0-rc2 versus native/VIR 4.34.0. No affinity/governor control. Node only; diagnostic FIR adapter. Six engine orders balance positions; native is re-warmed per sample.', rows: [] };
const save = () => writeFileSync(outputArg, JSON.stringify(report, null, 2) + '\n');
save();
const vir = await createVirRuntime({ wasmBytes: read('site/lean-vir/wasm/vir-upstream.wasm'),
  irPackageSet: [read('bench/pkg/Bench.parts/0.irpkg'), read('bench/pkg/Bench.parts/1.irpkg'), read('bench/pkg/Bench.irpkg')] });
const orders = [['fir', 'vir', 'native'], ['vir', 'native', 'fir'], ['native', 'fir', 'vir'],
  ['native', 'vir', 'fir'], ['fir', 'native', 'vir'], ['vir', 'fir', 'native']];
try {
  for (const item of manifest.artifacts) {
    assert.equal(hash(readFileSync(item.path)), item.sha256);
    assert.equal(hash(readFileSync(item.path + '.json')), item.descriptorSha256);
    const cases = CASOS.filter(c => c.w === item.workload && (() => {
      const rows = checks.rows.filter(r => r.workload === c.w && r.x === c.x);
      return rows.length === 2 && rows.every(r => r.status === 'passed' && r.elapsedMs < 1000);
    })());
    const c = cases.at(-1); assert.ok(c, `no qualified selection for ${item.workload}`);
    const fir = await createFirClient(manifest.producer, item.path, c.w);
    const arg = c.w === 'isPrime' ? BigInt(c.arg) : c.arg;
    const invoke = engine => {
      if (engine === 'native') {
        const lines = execFileSync(cli, ['--time', c.w, String(c.arg), '2'], { encoding: 'utf8', timeout: 30000 }).trim().split('\n');
        assert.equal(lines.length, 3);
        return { text: lines[0], ms: Number(lines[2]) / 1e6 };
      }
      const start = performance.now();
      const value = engine === 'fir' ? fir.call(c.arg).value : vir.call('Bench.' + c.w, arg);
      const text = textResult(c.w, value);
      return { text, ms: performance.now() - start };
    };
    for (const engine of ['fir', 'vir']) assert.equal(hash(invoke(engine).text), c.esperado);
    for (const [round, order] of orders.entries()) {
      for (const engine of order) {
        const result = invoke(engine);
        assert.equal(hash(result.text), c.esperado, `${engine}/${c.w}/${c.x}`);
        report.rows.push({ workload: c.w, x: c.x, engine, round, order, ms: result.ms, status: 'passed' });
        save();
      }
    }
    const med = engine => {
      const xs = report.rows.filter(r => r.workload === c.w && r.engine === engine).map(r => r.ms).sort((a,b) => a-b);
      return ((xs[2] + xs[3]) / 2).toFixed(3);
    };
    console.log(`${c.w}/${c.x}: native ${med('native')} ms; FIR ${med('fir')} ms; VIR ${med('vir')} ms`);
  }
  for (const p of files) assert.equal(hash(read(p)), report.inputs[p]);
  assert.equal(hash(readFileSync(cli)), report.nativeSha256);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { report.finished = new Date().toISOString(); report.loadAfter = os.loadavg(); save(); }
