// Preserve the published timing procedure and retain its inputs and machine identity.
// node bench/reproduce.mjs tests/out/research/<fresh-run-name>
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpus, platform, release, arch, loadavg } from 'node:os';
import { readFileSync, writeFileSync, mkdirSync, createWriteStream } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.argv.length !== 3) throw Error('usage: node bench/reproduce.mjs <fresh-output-directory>');
const out = resolve(process.argv[2]);
mkdirSync(out, { recursive: false }); // Never overwrite a previous campaign.
const command = (bin, args) => execFileSync(bin, args, { cwd: root, encoding: 'utf8' }).trim();
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const inputs = [
  'Tunnell.lean', 'Bench.lean', 'Main.lean', 'lean-toolchain', 'lake-manifest.json',
  'bench/reproduce.mjs', 'bench/medir-node.mjs', 'bench/medir-nativo.mjs',
  'bench/js-baseline.mjs', 'bench/casos.mjs', 'bench/generar_casos.py', 'bench/referencias.py',
  '.lake/build/bin/tunnell_cli', 'site/lean-vir/wasm/vir-upstream.wasm',
  'bench/pkg/Bench.irpkg-set.json', 'bench/pkg/Bench.irpkg',
  'bench/pkg/Bench.parts/0.irpkg', 'bench/pkg/Bench.parts/1.irpkg',
  ...command('git', ['ls-files', 'site/lean-vir/js']).split('\n'),
];
const hashes = () => Object.fromEntries(inputs.map(p => [p, hash(readFileSync(resolve(root, p)))]));
const metadata = {
  schema: 'lean-math-reproduction/v1', started: new Date().toISOString(),
  commit: command('git', ['rev-parse', 'HEAD']), status: command('git', ['status', '--short']),
  trackedDiffSha256: hash(command('git', ['diff', 'HEAD'])),
  node: process.version, v8: process.versions.v8, lean: command('lean', ['--version']),
  host: { platform: platform(), release: release(), arch: arch(), cpu: cpus()[0]?.model,
    logicalCpus: cpus().length, loadBefore: loadavg() },
  method: 'Original native harness followed by original Node harness; original warmup/repetition policies; not order-balanced.',
  validation: 'Original Node harness validates warmup only; native harness validates the final result. Timed samples are not individually validated.',
  inputHashes: hashes(), commands: [], statusResult: 'running',
};
const save = () => writeFileSync(resolve(out, 'identity.json'), JSON.stringify(metadata, null, 2) + '\n');
save();
async function run(script) {
  const log = createWriteStream(resolve(out, script.split('/').at(-1) + '.log'));
  const entry = { argv: [process.execPath, script], started: new Date().toISOString() };
  metadata.commands.push(entry); save();
  console.log('Running', script, '→', out);
  const child = spawn(process.execPath, [script], { cwd: root, env: { ...process.env, BENCH_OUT_DIR: out }, stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.pipe(log, { end: false }); child.stderr.pipe(log, { end: false });
  try {
    await new Promise((ok, fail) => {
      child.on('error', fail);
      child.on('close', (code, signal) => { entry.exitCode = code; entry.signal = signal; code === 0 ? ok() : fail(Error(`${script} failed: ${code ?? signal}`)); });
    });
  } finally {
    log.end(); entry.finished = new Date().toISOString(); save();
  }
}
try {
  await run('bench/medir-nativo.mjs');
  await run('bench/medir-node.mjs');
  const rows = ['nativo.json', 'node.json'].flatMap(p => JSON.parse(readFileSync(resolve(out, p))).filas);
  if (rows.length !== 120 || rows.some(r => r.error || !r.ms?.length || r.ms.some(t => !Number.isFinite(t) || t < 0))) throw Error('Incomplete or failed benchmark rows');
  if (JSON.stringify(hashes()) !== JSON.stringify(metadata.inputHashes)) throw Error('Inputs changed during the campaign');
  metadata.statusResult = 'passed'; metadata.rows = rows.length;
} catch (e) {
  metadata.statusResult = 'failed'; metadata.error = String(e); process.exitCode = 1;
} finally {
  metadata.finished = new Date().toISOString(); metadata.host.loadAfter = loadavg(); save();
  console.log(metadata.statusResult, resolve(out, 'identity.json'));
}
