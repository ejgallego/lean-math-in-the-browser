// Invoked by build-fir.sh after the producer's compiler dependencies are ready.
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, openSync, closeSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
const [producerArg, ...workloads] = process.argv.slice(2);
const producer = resolve(producerArg);
const project = join(producer, '.deps/math-browser-fir');
const allowed = ['tunnell-direct', 'tunnell', 'collatzRecord', 'primeCount', 'mertens', 'partitions', 'fib', 'fibBits', 'partitionsBits', 'isPrime', 'lifePopulation'];
if (!workloads.length || workloads.some(w => !allowed.includes(w))) throw Error('Expected known workloads');
const hash = p => createHash('sha256').update(readFileSync(p)).digest('hex');
const git = args => execFileSync('git', args, { cwd: producer, encoding: 'utf8' }).trim();
const preparation = JSON.parse(readFileSync(join(project, 'PREPARATION.json')));
if (git(['status', '--porcelain']) || git(['rev-parse', 'HEAD']) !== preparation.producerCommit)
  throw Error('Producer must remain clean and frozen at the preparation commit');
for (const input of preparation.sources) {
  if (hash(join(project, input.path)) !== input.stagedSha256) throw Error('Staged source changed: ' + input.path);
}
const captureMode = process.env.FIR_MATH_CAPTURE ?? 'unit';
if (!['module', 'unit'].includes(captureMode)) throw Error('Unknown capture mode');
const capture = args => execFileSync('lake', args, { cwd: producer, encoding: 'utf8' }).trim();
const lean = capture(['env', 'which', 'lean']);
let leanPath = capture(['env', 'printenv', 'LEAN_PATH']);
const { buildPostponedSourceView } = await import(pathToFileURL(join(producer, 'integration/package-tools/postponed-source-view.mjs')));
const sourceView = process.env.FIR_MATH_SOURCE_VIEW ?? 'ordinary';
if (!['postponed', 'ordinary'].includes(sourceView)) throw Error('Unknown source view');
const outputRoot = join(project, '.deps', sourceView);
mkdirSync(outputRoot, { recursive: true });
for (const moduleName of ['Tunnell', 'Bench']) {
  if (sourceView === 'postponed') {
    const result = buildPostponedSourceView({ lean, leanPath, moduleName, outputRoot,
      packageName: 'MathBrowserFir', sourceFile: join(project, moduleName + '.lean') });
    leanPath = result.leanPath;
  } else {
    // Ordinary compiler signatures are required by the synthetic-unit API.
    // Use a new output directory so read-only Lean artifacts are never overwritten.
    const dir = mkdtempSync(join(outputRoot, moduleName + '.'));
    const setup = join(dir, 'setup.json');
    writeFileSync(setup, JSON.stringify({ plugins: [], package: 'MathBrowserFir',
      options: {}, name: moduleName, isModule: true, importArts: {}, dynlibs: [] }));
    execFileSync(lean, [join(project, moduleName + '.lean'), '-o', join(dir, moduleName + '.olean'), '--setup', setup],
      { cwd: project, env: { ...process.env, LEAN_PATH: leanPath }, stdio: 'inherit' });
    leanPath = dir + ':' + leanPath;
  }
}
mkdirSync(join(project, '_build'), { recursive: true });
const campaign = mkdtempSync(join(project, '_build', 'campaign.'));
const manifest = { producer, producerCommit: preparation.producerCommit, sourceView, capture: captureMode, artifacts: [], failures: [] };
for (const workload of workloads) {
  const out = mkdtempSync(join(project, '_build', workload + '.'));
  const log = openSync(join(out, 'build.log'), 'w');
  const result = spawnSync(lean, [join(project, 'Emit.lean')], {
    cwd: project, stdio: ['ignore', log, log],
    env: { ...process.env, LEAN_PATH: leanPath, FIR_MATH_CAPTURE: captureMode, FIR_MATH_ENTRY: workload === 'tunnell-direct' ? 'Tunnell.tunnell' : 'Bench.' + workload,
      FIR_MATH_OUT: join(out, workload + '.wasm') },
  });
  closeSync(log);
  writeFileSync(join(out, 'build-identity.json'), JSON.stringify({
    workload, sourceView, capture: captureMode, exitCode: result.status, signal: result.signal, error: String(result.error ?? ''),
    producer: execFileSync('git', ['rev-parse', 'HEAD'], { cwd: producer, encoding: 'utf8' }).trim(),
    lean: execFileSync(lean, ['--version'], { encoding: 'utf8' }).trim(),
    inputs: Object.fromEntries(['Tunnell.lean', 'Bench.lean', 'Emit.lean', 'PREPARATION.json'].map(p => [p, hash(join(project,p))])),
    harnessSha256: hash(new URL(import.meta.url)),
  }, null, 2) + '\n');
  writeFileSync(join(out, 'exit-code'), String(result.status ?? result.signal) + '\n');
  console.log(`${workload}: exit ${result.status}; ${out}`);
  if (result.status !== 0) {
    console.error(readFileSync(join(out, 'build.log'), 'utf8')); process.exitCode = 1;
    manifest.failures.push({ workload, path: out, exitCode: result.status });
  } else {
    const path = join(out, workload + '.wasm');
    manifest.artifacts.push({ workload, path, sha256: hash(path), descriptorSha256: hash(path + '.json'),
      buildIdentitySha256: hash(join(out, 'build-identity.json')), bytes: readFileSync(path).length });
  }
  writeFileSync(join(campaign, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
}
console.log('Manifest: ' + join(campaign, 'manifest.json'));
