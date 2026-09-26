// The benchmark in a module Web Worker: runs bench-core.js and reports progress and results.
import { correr } from './bench-core.js';

self.onmessage = async ({ data }) => {
  const r = await correr(data, (p) => self.postMessage({ progreso: p }));
  self.postMessage({ fin: true, ...r });
};
