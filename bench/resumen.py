"""The numbers quoted in docs/REPORT-ORIGINAL.md, computed from bench/out/*.json (run after the campaigns).

Run: python bench/resumen.py
"""
import json
import os
import statistics as st

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def lee(p):
    with open(os.path.join(R, p), encoding="utf-8") as h:
        return json.load(h)


node, nat = lee("bench/out/node.json"), lee("bench/out/nativo.json")
filas = [f for f in node["filas"] + nat["filas"] if "ms" in f]
errores = [f for f in node["filas"] + nat["filas"] if "error" in f]
med = {(f["w"], f["x"], f["motor"]): st.median(f["ms"]) for f in filas}
print(f"engine comparison: {len(filas)} timed rows, {len(errores)} with a wrong value; "
      f"cold start import {node['importMs']:.0f} ms + runtime {node['coldMs']:.0f} ms")

print("\nlargest size measured by all three engines:")
for w in sorted({f["w"] for f in filas}):
    xs = [x for (ww, x, m) in med if ww == w and m == "nativo" and (w, x, "wasm") in med and (w, x, "js") in med]
    x = max(xs)
    n, a, j = med[(w, x, "nativo")], med[(w, x, "wasm")], med[(w, x, "js")]
    print(f"  {w:15} x={x:<9} native {n:10.3f}  wasm {a:10.1f}  js {j:9.3f}  | wasm/native {a / n:7.1f}  js/native {j / n:7.3f}  wasm/js {a / j:7.0f}")

rel = [med[(w, x, "wasm")] / med[(w, x, "nativo")] for (w, x, m) in med if m == "wasm" and (w, x, "nativo") in med and med[(w, x, "nativo")] > 0.05]
print(f"\nwasm/native over all cases with native > 0.05 ms: median {st.median(rel):.0f}, range {min(rel):.1f}-{max(rel):.0f} (n={len(rel)})")

nav = {p: lee(f"bench/out/navegador-{p}.json") for p in ("normal-worker", "normal-principal", "lenta-principal")}
for p, d in nav.items():
    print(f"\nChrome {p}: errors {d['errores']}; rows {len(d['filas'])}, wrong values {sum('error' in f for f in d['filas'])}")
    print(f"  cold start {json.dumps({k: round(v, 1) for k, v in d['frio'].items()})}; total {sum(d['frio'].values()):.0f} ms")
    print(f"  main thread: {json.dumps({k: round(v, 3) for k, v in d['hiloPrincipal'].items()})}")
    print(f"  real page: first answer {d['pagina']['primeraRespuestaMs']} ms after navigation, n=10^6+3 in {d['pagina']['n1e6Ms']} ms")

mc = lambda d: {(f["w"], f["x"], f["motor"]): st.median(f["ms"]) for f in d["filas"] if "ms" in f}
ew, ep, mp = mc(nav["normal-worker"]), mc(nav["normal-principal"]), mc(nav["lenta-principal"])
r1 = [mp[k] / ep[k] for k in ep if k in mp and ep[k] > 5]
r2 = [ep[k] / ew[k] for k in ew if k in ep and ew[k] > 5]
print(f"\nslowed/normal CPU on the main thread: median {st.median(r1):.2f} (range {min(r1):.2f}-{max(r1):.2f}, n={len(r1)})")
print(f"main thread/worker at normal CPU speed: median {st.median(r2):.2f} (range {min(r2):.2f}-{max(r2):.2f}, n={len(r2)})")
cr = [(ew[(w, x, 'wasm')] / ew[(w, x, 'js')], med[(w, x, 'wasm')] / med[(w, x, 'js')]) for (w, x, m) in ew
      if m == "wasm" and (w, x, "js") in ew and (w, x, "js") in med and ew[(w, x, "js")] > 0.5 and med[(w, x, "js")] > 0.5]
print(f"wasm/js in Chrome vs in Node (same case, n={len(cr)}): Chrome median {st.median(c for c, _ in cr):.0f}, Node median {st.median(n for _, n in cr):.0f}")
