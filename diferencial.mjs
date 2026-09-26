// Differential test: Tunnell.lean, run through lean-vir (Lean's IR interpreter compiled to
// WebAssembly), against the independent brute-force reference (referencia.json, produced by
// referencia.py and cross-checked there against OEIS A003273).
//
// Run: node diferencial.mjs   (after `python referencia.py 400`)
import { readFileSync } from 'node:fs';
import { createVirRuntime } from './site/lean-vir/js/vir-runtime-node.js';

const vir = await createVirRuntime({
  wasmBytes: readFileSync('site/lean-vir/wasm/vir-upstream.wasm'),
  irPackageSet: [readFileSync('site/tunnell.irpkg')],
});

const ref = JSON.parse(readFileSync('referencia.json', 'utf8'));
let malos = 0;
const t0 = performance.now();
for (const r of ref) {
  const v = vir.call('Tunnell.tunnell', r.n);
  const iguales = Number(v.first) === r.first && Number(v.second) === r.second &&
    v.criterion === r.criterion && v.squarefree === r.squarefree;
  if (!iguales) { malos++; if (malos <= 5) console.log('DIFIERE', r.n, v, r); }
}
const ms = performance.now() - t0;
console.log(`n = 1..${ref.length}: ${ref.length - malos} iguales, ${malos} distintos (${ms.toFixed(0)} ms, ${(ms / ref.length).toFixed(2)} ms por n)`);

// the list of congruent numbers (under BSD) up to 400, computed in one call, against OEIS
const oeis = readFileSync('b003273.txt', 'utf8').split('\n').filter((l) => l.trim() && !l.startsWith('#')).map((l) => Number(l.split(/\s+/)[1]));
const sqf = (n) => { for (let p = 2; p * p <= n; p++) if (n % (p * p) === 0) return false; return n > 0; };
const lista = vir.call('Tunnell.congruentUpTo', 400).map(Number);
const esperada = oeis.filter((n) => n <= 400 && sqf(n));
console.log(`congruentUpTo(400): ${lista.length} numbers, equal to the squarefree terms of OEIS A003273: ${JSON.stringify(lista) === JSON.stringify(esperada)}`);

// larger n: time and one known value each side
for (const n of [157, 1000003, 9999991]) {
  const t = performance.now();
  const v = vir.call('Tunnell.tunnell', n);
  console.log(`n = ${n}: first ${v.first}, second ${v.second}, criterion ${v.criterion}, ${(performance.now() - t).toFixed(0)} ms -> ${v.verdict}`);
}
process.exit(malos ? 1 : 0);
