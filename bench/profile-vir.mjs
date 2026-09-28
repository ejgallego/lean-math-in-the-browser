// Profile the shipped release binary; borrow symbols only after full section parity.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { Session } from 'node:inspector/promises';
import os from 'node:os';
import { createVirRuntime } from '../site/lean-vir/js/vir-runtime-node.js';
import { CASOS } from './casos.mjs';

const [debugPath, output, w, inputArg, repsArg] = process.argv.slice(2);
const x = Number(inputArg), reps = Number(repsArg);
assert.ok(debugPath && output && ['primeCount', 'fibBits'].includes(w));
assert.ok(Number.isSafeInteger(reps) && reps > 0 && reps <= 30);
const c = CASOS.find(c => c.w === w && c.x === x); assert.ok(c);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const read = p => readFileSync(new URL('../' + p, import.meta.url));
function parse(bytes) {
  let p = 8;
  const uint = () => { let n = 0, s = 0; for (;;) {
    assert.ok(p < bytes.length && s < 35); const v = bytes[p++]; n += (v & 127) * 2 ** s;
    if (v < 128) return n; s += 7;
  } };
  const string = () => { const n = uint(), value = bytes.subarray(p,p+n).toString('utf8'); p += n; return value; };
  const sections = [], names = new Map(), bodies = [];
  while (p < bytes.length) {
    const start = p, id = bytes[p++], length = uint(), end = p + length;
    assert.ok(end <= bytes.length);
    if (id !== 0) sections.push(bytes.subarray(start,end));
    if (id === 0 && string() === 'name') {
      while (p < end) {
        const sub = bytes[p++], size = uint(), subEnd = p + size;
        if (sub === 1) { const count = uint(); for (let i=0;i<count;i++) names.set(uint(),string()); }
        p = subEnd;
      }
    }
    if (id === 10) {
      const count = uint();
      for (let i=0;i<count;i++) { const size = uint(); bodies.push(p); p += size; }
      assert.equal(p,end);
    }
    p = end;
  }
  return { sections, names, bodies };
}
const release = read('site/lean-vir/wasm/vir-upstream.wasm'), debug = readFileSync(debugPath);
const r = parse(release), d = parse(debug);
assert.deepEqual(r.sections,d.sections,'debug companion differs in executable sections');
const module = new WebAssembly.Module(release);
const imports = WebAssembly.Module.imports(module).filter(i => i.kind === 'function').length;
const entries = [...d.names];
const demangled = execFileSync('c++filt', { input: entries.map(e=>e[1]).join('\n')+'\n', encoding:'utf8', maxBuffer:8<<20 }).trimEnd().split('\n');
assert.equal(entries.length,demangled.length);
const names = new Map(entries.map(([index],i)=>[index,demangled[i]]));
const pkgs = ['bench/pkg/Bench.parts/0.irpkg','bench/pkg/Bench.parts/1.irpkg','bench/pkg/Bench.irpkg'];
const identityFiles = ['site/lean-vir/js/runtime/core.js','site/lean-vir/js/runtime/object-values.js',
  'site/lean-vir/js/runtime/host-state.js','site/lean-vir/js/vir-runtime.js','site/lean-vir/js/vir-runtime-node.js',
  'bench/casos.mjs','Bench.lean',...pkgs];
const report = { status:'running', w, x, reps, warmups:1, started:new Date().toISOString(),
  command:[process.execPath,...process.execArgv,...process.argv.slice(1)], node:process.version,v8:process.versions.v8,
  cpu:os.cpus()[0].model,loadBefore:os.loadavg(),releaseSha256:hash(release),debugSha256:hash(debug),debugPath,
  symbols: { nonCustomSectionsIdentical:true, nonCustomSha256:hash(Buffer.concat(r.sections)), names:names.size,
    method:'Function names from debug name section, c++filt demangling; code-section byte offsets checked against original release.' },
  intervalUs:1000,scope:'Main isolate, whole measured call loop plus validation and profiler bookkeeping; instantiate/warmup excluded.',
  inputs:Object.fromEntries(identityFiles.map(p=>[p,hash(read(p))])),harnessSha256:hash(readFileSync(new URL(import.meta.url))),rows:[] };
mkdirSync(output,{recursive:false});
const save = () => writeFileSync(join(output,'run.json'),JSON.stringify(report,null,2)+'\n'); save();
const vir = await createVirRuntime({wasmModule:module,irPackageSet:pkgs.map(read)});
const validate = value => assert.equal(hash(String(value)),c.esperado);
const session = new Session();
try {
  validate(vir.call('Bench.'+w,c.arg));
  session.connect(); await session.post('Profiler.enable');
  await session.post('Profiler.setSamplingInterval',{interval:1000}); await session.post('Profiler.start');
  for (let i=0;i<reps;i++) {
    const start=performance.now(),value=vir.call('Bench.'+w,c.arg),ms=performance.now()-start;
    validate(value); report.rows.push({repetition:i,ms,valueSha256:hash(String(value))});
  }
  const {profile}=await session.post('Profiler.stop');
  const raw=JSON.stringify(profile)+'\n';writeFileSync(join(output,'cpu.cpuprofile'),raw);report.profileSha256=hash(raw);
  const nodes=new Map(profile.nodes.map(n=>[n.id,n])),parents=new Map(),labels=new Map(),urls=new Set();
  const mapped=new Map(),trampolines=new Set();
  for (const n of nodes.values()) {
    for (const child of n.children??[]) parents.set(child,n.id);
    const f=n.callFrame;
    if (!f.url.startsWith('wasm://')) {labels.set(n.id,f.functionName||`<anonymous@${f.url}>`);continue;}
    urls.add(f.url);
    if (f.functionName.startsWith('js-to-wasm:')) {labels.set(n.id,f.functionName);trampolines.add(n.id);continue;}
    const match=/^wasm-function\[(\d+)\]$/.exec(f.functionName);assert.ok(match);
    const index=Number(match[1]);assert.ok(names.has(index));assert.equal(f.columnNumber,r.bodies[index-imports]);
    labels.set(n.id,names.get(index));mapped.set(index,{index,name:names.get(index),offset:f.columnNumber});
  }
  assert.equal(urls.size,1);assert.equal(profile.samples.length,profile.timeDeltas.length);
  const self=new Map(),inclusive=new Map(),rootOnly=new Map(),buckets=new Map();
  const add=(m,k,v)=>m.set(k,(m.get(k)??0)+v);let clock=profile.startTime,total=0;
  for (let i=0;i<profile.samples.length;i++) {
    const delta=profile.timeDeltas[i];assert.ok(delta>=0);
    const us=Math.max(0,Math.min(clock+delta,profile.endTime)-clock);clock+=delta;total+=us;
    const id=profile.samples[i],n=nodes.get(id),label=labels.get(id);add(self,label,us);
    const wasm=n.callFrame.url.startsWith('wasm://');
    add(buckets,trampolines.has(id)?'trampoline':wasm?'resolved Wasm':label==='(garbage collector)'?'V8 GC':label==='(idle)'?'V8 idle':'JS/V8 other',us);
    if(wasm&&labels.get(parents.get(id))==='(root)')add(rootOnly,label,us);
    const chain=new Set();for(let a=id;a!==undefined;a=parents.get(a))chain.add(labels.get(a));
    for(const label of chain)add(inclusive,label,us);
  }
  const sorted=m=>[...m].sort((a,b)=>b[1]-a[1]).map(([name,us])=>({name,ms:us/1000,percent:us/total*100}));
  report.summary={samples:profile.samples.length,attributedMs:total/1000,unobservedTailMs:Math.max(0,profile.endTime-clock)/1000,
    weighting:'Actual timeDeltas, preceding interval assigned to ending sample, clipped to end. Inclusive symbols once per stack; inclusive rows overlap.',
    mappedFunctions:[...mapped.values()],buckets:sorted(buckets),self:sorted(self),inclusive:sorted(inclusive),rootOnlyWasm:sorted(rootOnly)};
  for(const p of identityFiles)assert.equal(hash(read(p)),report.inputs[p]);
  report.status='passed';
} catch(error) {report.status='failed';report.error=String(error);throw error;}
finally {session.disconnect();vir.dispose();report.finished=new Date().toISOString();report.loadAfter=os.loadavg();save();}
console.log(JSON.stringify({w,x,status:report.status,samples:report.summary.samples,self:report.summary.self.slice(0,10)},null,2));
