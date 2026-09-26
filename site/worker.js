// Runs Tunnell.lean off the main thread: lean-vir (Lean's IR interpreter compiled to WebAssembly)
// loads the generated package once and answers one call per message.
import { createVirRuntimeFactory } from './lean-vir/js/vir-runtime.js';
import { createCommonHostBindings, createConsoleHostBindings } from './lean-vir/js/vir-host-bindings.js';

const listo = (async () => {
  const [wasm, pkg] = await Promise.all([
    fetch('./lean-vir/wasm/vir-upstream.wasm').then((r) => r.arrayBuffer()),
    fetch('./tunnell.irpkg').then((r) => r.arrayBuffer()),
  ]);
  const factory = createVirRuntimeFactory({
    wasmBytes: new Uint8Array(wasm),
    defaultHostBindings: () => ({ ...createCommonHostBindings(), ...createConsoleHostBindings() }),
  });
  return factory.createRuntime({ irPackageSet: [new Uint8Array(pkg)] });
})();

self.onmessage = async ({ data }) => {
  try {
    const vir = await listo;
    const t0 = performance.now();
    const value = vir.call(data.fn, data.arg);
    self.postMessage({ id: data.id, value, ms: performance.now() - t0 });
  } catch (e) {
    self.postMessage({ id: data.id, error: String(e && e.message || e) });
  }
};
