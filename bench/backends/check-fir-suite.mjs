import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { CASOS } from '../casos.mjs';
import { createFirClient, textResult } from './fir-client.mjs';

if (!isMainThread) {
  const client = await createFirClient(workerData.producer, workerData.path, workerData.workload);
  parentPort.on('message', input => {
    try {
      const before = performance.now();
      const result = client.call(input);
      parentPort.postMessage({ ...result, elapsedMs: performance.now() - before });
    } catch (error) { parentPort.postMessage({ error: String(error) }); }
  });
  parentPort.postMessage({ ready: true });
} else {
const [manifestArg, outputArg] = process.argv.slice(2);
if (!manifestArg || !outputArg) throw Error('usage: node bench/backends/check-fir-suite.mjs MANIFEST.json OUTPUT.json');
assert.ok(!existsSync(outputArg), 'output already exists');
const manifest = JSON.parse(readFileSync(manifestArg));
const timeoutMs = Number(process.env.FIR_CHECK_TIMEOUT_MS ?? 30000);
assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
for (const item of manifest.artifacts) {
  assert.equal(hash(readFileSync(item.path)), item.sha256);
  assert.equal(hash(readFileSync(item.path + '.json')), item.descriptorSha256);
}
const report = { status: 'running', timeoutMs, node: process.version, manifestSha256: hash(readFileSync(manifestArg)),
  harnessSha256: hash(readFileSync(new URL(import.meta.url))),
  adapterSha256: hash(readFileSync(new URL('./fir-client.mjs', import.meta.url))),
  referencesSha256: hash(readFileSync(new URL('../casos.mjs', import.meta.url))), rows: [] };
const save = () => writeFileSync(outputArg, JSON.stringify(report, null, 2) + '\n');
save();
let worker;
async function receive(send) {
  return await new Promise((resolve, reject) => {
    const cleanup = () => { clearTimeout(timer); worker.off('message', message); worker.off('error', fail); worker.off('exit', exited); };
    const message = value => { cleanup(); value.error ? reject(Error(value.error)) : resolve(value); };
    const fail = error => { cleanup(); reject(error); };
    const exited = code => fail(Error(`worker exited ${code}`));
    const timer = setTimeout(() => { cleanup(); resolve({ timeout: true }); }, timeoutMs);
    worker.once('message', message); worker.once('error', fail); worker.once('exit', exited);
    send?.();
  });
}
try {
  for (const item of manifest.artifacts) {
    const cases = CASOS.filter(c => c.w === item.workload);
    assert.ok(cases.length);
    const timedOut = new Set();
    for (const c of [...cases, ...cases.toReversed()]) {
      if (timedOut.has(c.x)) continue;
      if (!worker) {
        worker = new Worker(new URL(import.meta.url), { workerData: { producer: manifest.producer, ...item } });
        assert.deepEqual(await receive(), { ready: true });
      }
      const result = await receive(() => worker.postMessage(c.arg));
      if (result.timeout) {
        report.rows.push({ workload: c.w, x: c.x, status: 'timeout', timeoutMs });
        timedOut.add(c.x); await worker.terminate(); worker = undefined;
        save(); console.log(`${c.w}/${c.x}: timeout after ${timeoutMs} ms; unqualified`); continue;
      }
      assert.equal(hash(textResult(c.w, result.value)), c.esperado, `${c.w}/${c.x}`);
      const repeated = await receive(() => worker.postMessage(c.arg));
      assert.ok(!repeated.timeout, 'warm call timed out');
      assert.deepEqual(repeated.value, result.value);
      assert.equal(repeated.memory.frontierAfter, repeated.memory.frontierBefore, 'warm rewind');
      report.rows.push({ workload: c.w, x: c.x, elapsedMs: result.elapsedMs, memory: result.memory, warm: repeated.memory, status: 'passed' });
      save();
      console.log(`${c.w}/${c.x}: pass (${result.elapsedMs.toFixed(2)} ms diagnostic, ${result.memory.bytes} memory bytes)`);
    }
    await worker?.terminate(); worker = undefined;
  }
  report.status = report.rows.some(r => r.status === 'timeout') ? 'incomplete' : 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
finally { await worker?.terminate(); save(); }
}
