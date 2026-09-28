// Qualification only: worker-bounded repeated calls, all independent reference cases.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { CASOS } from '../casos.mjs';
import { createEmscriptenClient } from './emscripten-client.mjs';

if (!isMainThread) {
  const client = await createEmscriptenClient(workerData.producer, workerData.manifest);
  parentPort.on('message', ({w, arg}) => {
    try {
      const start = performance.now(), text = client.call(w, arg);
      parentPort.postMessage({ text, ms: performance.now() - start });
    } catch (error) { parentPort.postMessage({ error: String(error) }); }
  });
  parentPort.postMessage({ ready: true });
} else {
  const [producer, manifest, output] = process.argv.slice(2);
  assert.ok(output, 'usage: node check-emscripten-suite.mjs PRODUCER MANIFEST OUTPUT');
  assert.ok(!existsSync(output));
  const hash = value => createHash('sha256').update(value).digest('hex');
  const timeoutMs = Number(process.env.CHECK_TIMEOUT_MS ?? 30000);
  assert.ok(Number.isSafeInteger(timeoutMs) && timeoutMs > 0);
  const report = { status: 'running', producer, manifest, timeoutMs,
    started: new Date().toISOString(), node: process.version,
    manifestSha256: hash(readFileSync(manifest)),
    harnessSha256: hash(readFileSync(new URL(import.meta.url))),
    adapterSha256: hash(readFileSync(new URL('./emscripten-client.mjs', import.meta.url))),
    referencesSha256: hash(readFileSync(new URL('../casos.mjs', import.meta.url))),
    policy: 'Forward and reverse case order, each with an immediate repeat; retained instance; every result checked. Screening timings only.', rows: [] };
  const save = () => writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  let worker;
  const receive = send => new Promise((resolve, reject) => {
    const cleanup = () => { clearTimeout(timer); worker.off('message', message); worker.off('error', fail); worker.off('exit', exited); };
    const message = value => { cleanup(); value.error ? reject(Error(value.error)) : resolve(value); };
    const fail = error => { cleanup(); reject(error); };
    const exited = code => fail(Error('worker exited ' + code));
    const timer = setTimeout(() => { cleanup(); resolve({ timeout: true }); }, timeoutMs);
    worker.once('message', message); worker.once('error', fail); worker.once('exit', exited); send?.();
  });
  const skipped = new Set(); save();
  try {
    for (const [pass, cases] of [CASOS, CASOS.toReversed()].entries()) {
      for (const c of cases) {
        const key = `${c.w}/${c.x}`;
        if (skipped.has(key)) continue;
        if (!worker) {
          worker = new Worker(new URL(import.meta.url), { workerData: { producer, manifest } });
          assert.deepEqual(await receive(), { ready: true });
        }
        for (let repetition = 0; repetition < 2; repetition++) {
          const result = await receive(() => worker.postMessage(c));
          if (result.timeout) {
            report.rows.push({ w: c.w, x: c.x, pass, repetition, status: 'timeout' });
            skipped.add(key); await worker.terminate(); worker = undefined; save(); break;
          }
          assert.equal(hash(result.text), c.esperado, key);
          report.rows.push({ w: c.w, x: c.x, pass, repetition, status: 'passed', ms: result.ms, sha256: hash(result.text) });
          save();
        }
        console.log(`${key}: ${skipped.has(key) ? 'timeout' : 'checked twice'} (pass ${pass})`);
      }
    }
    assert.equal(hash(readFileSync(manifest)), report.manifestSha256);
    report.status = skipped.size ? 'incomplete' : 'passed';
  } catch (error) { report.status = 'failed'; report.error = String(error); throw error; }
  finally { await worker?.terminate(); report.finished = new Date().toISOString(); save(); }
}
