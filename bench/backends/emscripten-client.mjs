import assert from 'node:assert/strict';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';

export const workloads = ['tunnell', 'collatzRecord', 'primeCount', 'mertens',
  'partitions', 'fib', 'fibBits', 'partitionsBits', 'isPrime', 'lifePopulation'];

export async function createEmscriptenClient(producer, manifest) {
  const { loadEmscriptenModule } = await import(pathToFileURL(join(resolve(producer),
    'integration/lcnf-c-wasm/emscripten-loader.mjs')));
  const loaded = await loadEmscriptenModule(pathToFileURL(resolve(manifest)));
  assert.equal(loaded.manifest.build.runtimeProfile, 'unthreaded');
  const e = loaded.exports, encoder = new TextEncoder(), decoder = new TextDecoder('utf-8', { fatal: true });
  return {
    manifest: loaded.manifest,
    call(workload, input) {
      const id = workloads.indexOf(workload), text = String(input);
      assert.ok(id >= 0 && /^(0|[1-9][0-9]*)$/.test(text));
      const bytes = encoder.encode(text);
      const ptr = e.fir_math_input_alloc(bytes.length) >>> 0;
      assert.ok(ptr > 0, 'input allocation failed');
      try {
        loaded.module.HEAPU8.set(bytes, ptr);
        assert.equal(e.fir_math_run(id, bytes.length), 0, 'evaluation failed');
        const result = e.fir_math_result_ptr() >>> 0, size = e.fir_math_result_len() >>> 0;
        const heap = loaded.module.HEAPU8; // reacquire after possible memory growth
        assert.ok(result > 0 && result + size <= heap.length);
        return decoder.decode(heap.subarray(result, result + size));
      } finally { e.fir_math_release(); }
    },
    dispose() { e.fir_math_release(); },
  };
}
