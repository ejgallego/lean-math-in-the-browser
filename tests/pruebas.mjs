// The WebAssembly build (lean-vir) against everything independent we have.
//
//   1. native Lean (the same code, compiled to machine code)   n = 1..N, and random large n
//   2. a second Python reference (isqrt per (x, z), no Lean)    n = 1..N, and random large n
//   3. OEIS A003273: the squarefree n that pass the criterion are exactly its terms (n <= 9,999)
//   4. the parity theorem of the Lax archive (lax-712553, Lax712553.TunnellParity.even_card_solutions):
//      for even a, c and odd n the number of solutions is even -> A, B (n odd) and C, D (n = 2m,
//      m odd) are all even
//   5. congruentUpTo(N) is the filtered list, in one call
//   6. edge inputs (0, 1, a square, a large prime)
//
// Inputs (written by CI or by hand):  tests/out/nativo.txt, tests/out/python.txt  (n = 1..N)
//                                     tests/out/nativo-azar.txt, tests/out/python-azar.txt
// Run: node tests/pruebas.mjs
import { readFileSync, existsSync } from 'node:fs';
import { createVirRuntime } from '../site/lean-vir/js/vir-runtime-node.js';

const R = new URL('../', import.meta.url);
const lee = (p) => readFileSync(new URL(p, R));
let fallos = 0, pruebas = 0;
const ok = (nombre, cond, detalle = '') => { pruebas++; if (!cond) fallos++; console.log(`${cond ? '  ok  ' : '  FAIL'} ${nombre}${!cond && detalle ? '  -- ' + detalle : ''}`); };

const vir = await createVirRuntime({ wasmBytes: lee('site/lean-vir/wasm/vir-upstream.wasm'), irPackageSet: [lee('site/tunnell.irpkg')] });
const wasm = (n) => { const v = vir.call('Tunnell.tunnell', n); return { n, first: Number(v.first), second: Number(v.second), criterion: v.criterion, squarefree: v.squarefree, verdict: v.verdict }; };
const parse = (txt) => new Map(txt.trim().split('\n').map((l) => { const [n, f, s, c, q] = l.trim().split(/\s+/); return [Number(n), { first: Number(f), second: Number(s), criterion: c === 'true', squarefree: q === 'true' }]; }));
const igual = (a, b) => a.first === b.first && a.second === b.second && a.criterion === b.criterion && a.squarefree === b.squarefree;

console.log('LEAN MATH IN THE BROWSER: THE WEBASSEMBLY BUILD AGAINST INDEPENDENT REFERENCES');
const nativo = parse(lee('tests/out/nativo.txt').toString());   // written by CI: tunnell_cli 1 10000
const python = parse(lee('tests/out/python.txt').toString());
const N = Math.max(...nativo.keys());
const t0 = performance.now();
const res = new Map();
for (let n = 1; n <= N; n++) res.set(n, wasm(n));
const ms = performance.now() - t0;
const difN = [...res].filter(([n, v]) => !igual(v, nativo.get(n))).map(([n]) => n);
const difP = [...res].filter(([n, v]) => !igual(v, python.get(n))).map(([n]) => n);
ok(`n = 1..${N}: WebAssembly = native Lean on every n (${(ms / 1000).toFixed(1)} s in WebAssembly)`, nativo.size === N && difN.length === 0, difN.slice(0, 5).join(','));
ok(`n = 1..${N}: WebAssembly = independent Python count on every n`, python.size === N && difP.length === 0, difP.slice(0, 5).join(','));

const oeis = new Set(lee('b003273.txt').toString().split('\n').filter((l) => l.trim() && !l.startsWith('#')).map((l) => Number(l.trim().split(/\s+/)[1])));
const hasta = Math.min(N, 9999);
const malosO = [];
for (let n = 1; n <= hasta; n++) { const v = res.get(n); if (v.squarefree && v.criterion !== oeis.has(n)) malosO.push(n); }
const cuantos = [...res.values()].filter((v) => v.n <= hasta && v.squarefree).length;
ok(`the ${cuantos} squarefree n <= ${hasta}: criterion holds exactly on the terms of OEIS A003273`, malosO.length === 0, malosO.slice(0, 5).join(','));

const malosPar = [];
for (let n = 1; n <= N; n++) {
  const v = res.get(n);
  const aplica = n % 2 === 1 || (n / 2) % 2 === 1;   // n odd, or n = 2m with m odd
  if (aplica && (v.first % 2 || v.second % 2)) malosPar.push(n);
}
ok('parity theorem of lax-712553: A, B (n odd) and C, D (n = 2m, m odd) are even for every such n', malosPar.length === 0, malosPar.slice(0, 5).join(','));

const lista = vir.call('Tunnell.congruentUpTo', N).map(Number);
const esperada = [...res.values()].filter((v) => v.squarefree && v.criterion).map((v) => v.n);
ok(`congruentUpTo(${N}) in one call = the ${esperada.length} n found one by one`, JSON.stringify(lista) === JSON.stringify(esperada));

if (existsSync(new URL('tests/out/nativo-azar.txt', R))) {
  const na = parse(lee('tests/out/nativo-azar.txt').toString()), pa = parse(lee('tests/out/python-azar.txt').toString());
  const t1 = performance.now();
  const dif = [...na.keys()].filter((n) => !igual(wasm(n), na.get(n)) || !igual(na.get(n), pa.get(n)));
  ok(`${na.size} random n from 10^4 to 2*10^6: WebAssembly = native = Python (${((performance.now() - t1) / 1000).toFixed(1)} s)`, na.size > 0 && na.size === pa.size && dif.length === 0, dif.slice(0, 5).join(','));
}

ok('n = 0 is refused, not counted', wasm(0).verdict === 'n must be positive');
ok('n = 1: not congruent, unconditionally (Fermat)', !wasm(1).criterion && /NOT congruent/.test(wasm(1).verdict));
ok('n = 4 (a square) is reported as not squarefree', !wasm(4).squarefree && /not squarefree/.test(wasm(4).verdict));
ok('n = 157: criterion holds (congruent under BSD, with a famously large triangle)', wasm(157).criterion && /Birch-Swinnerton-Dyer/.test(wasm(157).verdict));

console.log(fallos ? `\n${fallos} of ${pruebas} FAILED` : `\nall ${pruebas} passed`);
process.exit(fallos ? 1 : 0);
