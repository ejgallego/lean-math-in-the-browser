// Main thread of the harness: starts the worker and, while it computes, measures how responsive this
// thread stays: frames delivered (requestAnimationFrame) and long tasks (> 50 ms) observed.
const estado = document.getElementById('estado');
window.__arranca = (config) => new Promise((ok) => {
  const largas = [];
  try { new PerformanceObserver((l) => largas.push(...l.getEntries().map((e) => e.duration))).observe({ type: 'longtask', buffered: false }); } catch (e) {}
  // the largest gap between two delivered frames is the longest the page stayed frozen; unlike the
  // long-task observer (whose entries arrive after a blocked thread frees up) it cannot be missed
  let frames = 0, corriendo = true, ultimo = performance.now(), hueco = 0;
  const t0 = performance.now();
  const cuenta = (now) => { if (!corriendo) return; frames++; hueco = Math.max(hueco, now - ultimo); ultimo = now; requestAnimationFrame(cuenta); };
  requestAnimationFrame(cuenta);
  if (config.hilo === 'principal') {
    // the same code on the main thread: what the page would do without a Worker (and the only place
    // where CDP's CPU throttling applies, so this is how the slowed-CPU profile is measured)
    import('./bench-core.js').then(({ correr }) => correr(config, (x) => { estado.textContent = x; })).then((r) => {
      corriendo = false;
      const s = (performance.now() - t0) / 1000;
      window.__res = { ...r, hilo: 'principal', hiloPrincipal: { segundos: s, fps: frames / s, huecoMaxMs: Math.max(hueco, performance.now() - ultimo) } };
      ok(window.__res);
    });
    return;
  }
  const w = new Worker('./bench-worker.js', { type: 'module' });
  w.onmessage = ({ data }) => {
    if (data.progreso) { estado.textContent = data.progreso; return; }
    corriendo = false;
    const s = (performance.now() - t0) / 1000;
    window.__res = { ...data, hilo: 'worker', hiloPrincipal: { segundos: s, fps: frames / s, huecoMaxMs: Math.max(hueco, performance.now() - ultimo) } };
    ok(window.__res);
  };
  w.onerror = (e) => { corriendo = false; window.__res = { error: e.message }; ok(window.__res); };
  w.postMessage(config);
});
