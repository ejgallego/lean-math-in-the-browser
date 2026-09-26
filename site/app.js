// The page: sends n to the worker, shows the counts, the criterion and what can be concluded.
const worker = new Worker('./worker.js', { type: 'module' });
let siguiente = 0;
const pendientes = new Map();
worker.onmessage = ({ data }) => { const p = pendientes.get(data.id); pendientes.delete(data.id); p(data); };
const llama = (fn, arg) => new Promise((ok) => { const id = ++siguiente; pendientes.set(id, ok); worker.postMessage({ id, fn, arg }); });

const $ = (s) => document.querySelector(s);
const LIMITE = 10_000_000;

async function decide() {
  const n = Number($('#n').value);
  if (!Number.isInteger(n) || n < 1 || n > LIMITE) { $('#out').textContent = `Enter a whole number from 1 to ${LIMITE.toLocaleString('en')}.`; return; }
  $('#out').textContent = 'Computing in Lean…';
  const r = await llama('Tunnell.tunnell', n);
  if (r.error) { $('#out').textContent = 'Error: ' + r.error; return; }
  const v = r.value;
  const [f, s] = v.parity === 'odd' ? ['A', 'B'] : ['C', 'D'];
  const forms = v.parity === 'odd'
    ? [`2x² + y² + 32z² = ${n}`, `2x² + y² + 8z² = ${n}`]
    : [`4x² + y² + 32z² = ${n / 2}`, `4x² + y² + 8z² = ${n / 2}`];
  $('#out').innerHTML = '';
  const add = (tag, text, cls) => { const e = document.createElement(tag); e.textContent = text; if (cls) e.className = cls; $('#out').append(e); return e; };
  add('p', `${f} = #{${forms[0]}} = ${v.first}`, 'mono');
  add('p', `${s} = #{${forms[1]}} = ${v.second}`, 'mono');
  add('p', `2·${f} ${v.criterion ? '=' : '≠'} ${s}`, 'mono');
  add('p', v.verdict, v.squarefree ? (v.criterion ? 'cond' : 'no') : 'note');
  add('p', `computed by the Lean function Tunnell.tunnell in ${r.ms.toFixed(0)} ms, in this browser`, 'small');
}

async function lista() {
  const m = Number($('#m').value);
  if (!Number.isInteger(m) || m < 1 || m > 5000) { $('#lista').textContent = 'Enter a limit from 1 to 5000.'; return; }
  $('#lista').textContent = 'Computing in Lean…';
  const r = await llama('Tunnell.congruentUpTo', m);
  if (r.error) { $('#lista').textContent = 'Error: ' + r.error; return; }
  const xs = r.value.map(Number);
  $('#lista').textContent = `${xs.length} squarefree n ≤ ${m} satisfy the criterion (congruent if BSD holds), ${r.ms.toFixed(0)} ms:\n` + xs.join(', ');
}

$('#go').addEventListener('click', decide);
$('#n').addEventListener('keydown', (e) => { if (e.key === 'Enter') decide(); });
$('#golist').addEventListener('click', lista);
