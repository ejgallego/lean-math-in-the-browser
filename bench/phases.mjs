// Diagnostic VIR phase attribution, separate from uninstrumented headline runs.
// node bench/phases.mjs <fresh-output.json> [Fibonacci input, default 1000000]
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createVirRuntime } from '../site/lean-vir/js/vir-runtime-node.js';
import { CASOS } from './casos.mjs';
if (process.argv.length < 3 || process.argv.length > 4) throw Error('usage: node bench/phases.mjs <fresh-output.json> [n]');
const n = Number(process.argv[3] ?? 1000000);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const paths = ['site/lean-vir/wasm/vir-upstream.wasm', 'bench/pkg/Bench.parts/0.irpkg', 'bench/pkg/Bench.parts/1.irpkg', 'bench/pkg/Bench.irpkg'];
const bytes = paths.map(p => readFileSync(new URL('../' + p, import.meta.url)));
const vir = await createVirRuntime({ wasmBytes: bytes[0], irPackageSet: bytes.slice(1) });
const rows = [];
for (const w of ['fibBits', 'fib']) {
  const c = CASOS.find(c => c.w === w && c.arg === n);
  if (!c) throw Error('Input has no independent reference hash');
  const check = value => { if (hash(String(value)) !== c.esperado) throw Error(`${w} result mismatch`); };
  check(vir.call('Bench.' + w, n));
  for (let i = 0; i < 3; i++) {
    const { value, timings } = vir.callTimed('Bench.' + w, n);
    check(value); rows.push({ w, n, repetition: i, timings, valueSha256: hash(String(value)) });
  }
}
writeFileSync(process.argv[2], JSON.stringify({ schema: 'lean-math-vir-phases/v1',
  diagnostic: true, node: process.version, captured: new Date().toISOString(),
  artifacts: Object.fromEntries(paths.map((p,i) => [p, hash(bytes[i])])),
  harnessSha256: hash(readFileSync(new URL(import.meta.url))),
  timingImplementationSha256: hash(readFileSync(new URL('../site/lean-vir/js/runtime/call-timing.js', import.meta.url))),
  casesSha256: hash(readFileSync(new URL('./casos.mjs', import.meta.url))),
  warmups: 1, repetitions: 3, validation: 'Every result checked, outside the timed call.', rows,
}, null, 2) + '\n', { flag: 'wx' });
console.log(process.argv[2]);
