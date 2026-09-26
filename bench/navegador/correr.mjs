// Drives headless Chrome through CDP for the browser part of the benchmark.
//   node bench/navegador/correr.mjs <perfil> [base]
//   perfil: "normal" (no throttling) or "lenta" (CPU slowed 4x by Chrome, with a small emulated viewport)
//   base:   where the repository root is served (default http://127.0.0.1:8125/)
//   hilo:   'worker' (default, as on the real page) or 'principal' (main thread: the only place where
//           CDP's CPU throttling applies; verified: set on the page or on the worker's own session, it
//           leaves a dedicated worker at full speed)
// Writes bench/out/navegador-<perfil>.json: the harness results plus, for the real page (site/),
// the time from navigation to the first answer (n = 157) and to the answer for n = 10^6 + 3.
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const perfil = process.argv[2] || 'normal';
const hilo = process.argv[4] || 'worker';   // 'worker' or 'principal'
const BASE = process.argv[3] || 'http://127.0.0.1:8125/';
// the Chrome or Chromium executable to drive (no default path: set CHROME=/path/to/chrome)
const CHROME = process.env.CHROME;
if (!CHROME) { console.error('set CHROME to the path of a Chrome or Chromium executable'); process.exit(2); }
const ch = spawn(CHROME, ['--headless=new', '--remote-debugging-port=9338', `--user-data-dir=${mkdtempSync(join(tmpdir(), 'b-'))}`, '--no-first-run', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms)); let t;
for (let i = 0; i < 60; i++) { try { t = await (await fetch('http://127.0.0.1:9338/json')).json(); if (t.length) break; } catch {} await sleep(250); }
const ws = new WebSocket(t.find((x) => x.type === 'page').webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
let id = 0; const P = {}; const errores = [];
const trabajadores = [];
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && P[m.id]) { P[m.id](m); delete P[m.id]; }
  if (m.method === 'Target.attachedToTarget' && perfil === 'lenta') {
    const sid = m.params.sessionId; trabajadores.push(m.params.targetInfo.type);
    // CDP CPU throttling set on the page does not reach dedicated workers: set it on the worker's own session
    ws.send(JSON.stringify({ id: ++id, sessionId: sid, method: 'Emulation.setCPUThrottlingRate', params: { rate: 4 } }));
    ws.send(JSON.stringify({ id: ++id, sessionId: sid, method: 'Runtime.runIfWaitingForDebugger' }));
  }
  if (m.method === 'Target.attachedToTarget' && perfil !== 'lenta') ws.send(JSON.stringify({ id: ++id, sessionId: m.params.sessionId, method: 'Runtime.runIfWaitingForDebugger' }));
  if (m.method === 'Runtime.exceptionThrown') errores.push(m.params.exceptionDetails.exception?.description?.slice(0, 200) || m.params.exceptionDetails.text);
  if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') errores.push(m.params.entry.text.slice(0, 200)); };
const c = (m, p = {}) => new Promise((r) => { const i = ++id; P[i] = r; ws.send(JSON.stringify({ id: i, method: m, params: p })); });
const ev = async (x, timeout = 3600000) => (await c('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true, timeout })).result?.result?.value;
await c('Runtime.enable'); await c('Log.enable'); await c('Network.enable');
await c('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
await c('Network.setCacheDisabled', { cacheDisabled: true });
if (perfil === 'lenta') {
  await c('Emulation.setCPUThrottlingRate', { rate: 4 });
  await c('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 3, mobile: true });
}

// 1. the real page: navigation -> first answers
await c('Page.enable');
const tNav = Date.now();
await c('Page.navigate', { url: BASE + 'site/' });
const espera = async (n, limite) => {
  await ev(`document.querySelector('#n').value='${n}'; document.querySelector('#go').click()`);
  const t0 = Date.now();
  while (Date.now() - t0 < limite) { if (/in \d+ ms/.test(await ev(`document.querySelector('#out').innerText`))) return Date.now(); await sleep(25); }
  return NaN;
};
for (let i = 0; i < 200 && !(await ev(`!!document.querySelector('#go')`)); i++) await sleep(25);
const tPrimera = await espera(157, 60000);
const tGrande0 = Date.now(); const tGrande = await espera(1000003, 600000);
const pagina = { primeraRespuestaMs: tPrimera - tNav, n1e6Ms: tGrande - tGrande0 };
console.log(perfil, 'real page:', JSON.stringify(pagina));

// 2. the harness: every case in both engines, main-thread responsiveness measured meanwhile
await c('Page.navigate', { url: BASE + 'bench/navegador/' }); await sleep(1500);
const MAX = { tunnell: 100003, collatzRecord: 10000, primeCount: 1000000, mertens: 100000, partitions: 1000, fib: 100000, fibBits: 1000000, partitionsBits: 3000, isPrime: 1279, lifePopulation: 30 };
const res = await ev(`window.__arranca(${JSON.stringify({ max: MAX, reps: 5, hilo })})`);
const out = { perfil, pagina, ...res, errores, trabajadoresAcelerados: trabajadores };
mkdirSync(new URL('../out/', import.meta.url), { recursive: true });
writeFileSync(new URL(`../out/navegador-${perfil}-${hilo}.json`, import.meta.url), JSON.stringify(out, null, 1));
console.log(perfil, 'cold start:', JSON.stringify(res.frio), '| main thread:', JSON.stringify(res.hiloPrincipal), '| rows:', res.filas?.length, '| errors:', JSON.stringify(errores));
ws.close(); ch.kill();
