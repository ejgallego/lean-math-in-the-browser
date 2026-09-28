// Validate the migrated client and revised JS baseline, independently of timings.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { CASOS } from '../casos.mjs';
import * as JS from '../js-baseline-revised.mjs';
import { createVirRuntime } from '../../site/lean-vir/js/vir-runtime-node.js';
import { textResult } from './fir-client.mjs';

const [output] = process.argv.slice(2); assert.ok(output && !existsSync(output));
const root = new URL('../../', import.meta.url).pathname;
const files = ['lean-toolchain', '.lake/build/bin/tunnell_cli', 'bench/js-baseline-revised.mjs',
  'bench/casos.mjs', 'bench/backends/check-client.mjs', 'site/lean-vir/wasm/vir-upstream.wasm',
  ...['Bench.parts/0.irpkg', 'Bench.parts/1.irpkg', 'Bench.irpkg'].map(p => '.lake/build/vir/module-sets/' + p)];
const hash = b => createHash('sha256').update(b).digest('hex');
const read = p => readFileSync(root + p);
const report = { status: 'running', started: new Date().toISOString(), node: process.version,
  inputs: Object.fromEntries(files.map(p => [p, hash(read(p))])), rows: [] };
const save = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n'); save();
const vir = await createVirRuntime({ wasmBytes: read(files[5]), irPackageSet: files.slice(6).map(read) });
report.manifest = vir.interfaceManifest;
try {
  for (const c of CASOS) {
    const arg = c.w === 'isPrime' ? BigInt(c.arg) : c.arg;
    const values = {
      native: execFileSync(root + '.lake/build/bin/tunnell_cli', ['--eval', c.w, String(c.arg)], { encoding: 'utf8', timeout: 60000, maxBuffer: 1 << 24 }).trim(),
      js: JS[c.w](arg),
      vir: textResult(c.w, vir.call('Bench.' + c.w, arg)),
    };
    for (const [engine, value] of Object.entries(values)) {
      assert.equal(hash(value), c.esperado, `${engine}/${c.w}/${c.x}`);
      report.rows.push({ w: c.w, x: c.x, engine, status: 'passed', sha256: hash(value) });
    }
    save(); console.log(`${c.w}/${c.x}: native, revised JS and rebuilt VIR package pass`);
  }
  for (const [p, h] of Object.entries(report.inputs)) assert.equal(hash(read(p)), h);
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { vir.dispose(); report.finished = new Date().toISOString(); save(); }
