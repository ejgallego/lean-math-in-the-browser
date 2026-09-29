# Lean math in the browser

Classical computations written in Lean, checked against independent references,
and compared across native Lean, handwritten JavaScript,
[lean-vir](https://github.com/ejgallego/lean-vir), regular FIR and C/Emscripten
through [FIR tooling](https://github.com/ejgallego/lean-fir).

This fork extends [Joel Canary's original experiment](https://github.com/joelcanary/lean-math-in-the-browser).
It is an experimental test bed, not a library or a production performance claim.
The original mathematical programs, deployed browser demo and historical report
are preserved.

**Start with the [consolidated report](docs/REPORT.md)** for the original
review, then read the [current FIR rebenchmark](docs/FIR-UPDATE-20260929.md).
Each has one five-backend table with milliseconds and FIR-relative ratios.
The [original report](docs/REPORT-ORIGINAL.md) retains the author's browser
experiments and charts.

The review confirms substantial VIR slowdowns without finding a major client
integration mistake. FIR improves selected loop/array workloads by roughly
5–67× over VIR in the initial campaign, but remains behind native/JS there.
The resulting large-integer investigation led to FIR's new multiplication:
the [follow-up evaluation](docs/FIR-MULTIPLICATION-20260928.md) measures
377–1,021× gains on the two selected fibBits sizes, with fresh backend ratios
and 39/40 qualified inputs. Miller–Rabin remains slow.
The [remaining-hotspot profiles](docs/FIR-REMAINING-HOTSPOTS-20260928.md)
identify generic remainder and signed-integer handling as the next targets.
The [small-negation follow-up](docs/FIR-INT-NEG-20260928.md) validates FIR's
new path: Mertens improves 1.31× at one million, though it remains 10.4× slower
than the C/Wasm baseline there.
The [sieve, Collatz and Life profiles](docs/FIR-NEXT-THREE-PROFILES-20260928.md)
cover the next three candidates and their distinct runtime costs.
The [current-main rebenchmark](docs/FIR-UPDATE-20260929.md) validates the
new remainder path: 61/127-bit primality improves about 1.3–1.4×, yet 127-bit
FIR still takes 52.8× C/Wasm time; a repeated Life slowdown also needs review.
The C/Wasm baseline helps distinguish interpreter costs from arithmetic and
output conversion. These follow-up timings are Node measurements on one host;
browser/Worker validation remains separate.

The [evidence snapshot](bench/results/2026-09-28/README.md) includes all 500
checked timing observations, qualification outcomes and sampled profiles.
Detailed build and timing policy is in the
[4.34.1 methodology](docs/EVALUATION-4341-20260928.md); the
[VIR audit](docs/VIR-USAGE-AUDIT-20260928.md) and
[FIR arithmetic profile](docs/FIR-FIBBITS-PROFILE-20260928.md) support the diagnosis.

## Where this comes from

In September 2026 someone asked on the Lean Zulip, in
[*DOM Manipulation in Lean*](https://leanprover.zulipchat.com/#narrow/channel/113488-general/topic/DOM.20Manipulation.20in.20Lean)
(#general), what the options were for manipulating a web page from Lean. The replies pointed
to ProofWidgets4 for an HTML model and to lean-vir, which runs Lean IR through an interpreter compiled to
WebAssembly; one of lean-vir's authors added that its DOM bindings are still expected to
change, but that *pure* Lean programs running in WebAssembly are a much more stable surface.

That last remark is what this repository tests, out of curiosity: take small pure Lean
programs of the kind a mathematician would write, run them in a browser, and check — as
carefully as we can — that they give the right answers, what it costs, and what breaks. It
started with one function (Tunnell's criterion for congruent numbers) and grew into a small
benchmark of eight workloads.

## What is here

- [Tunnell.lean](Tunnell.lean) and [Bench.lean](Bench.lean): the mathematical
  programs and small kernel-checked examples, using core Lean without Mathlib.
- [Main.lean](Main.lean): native command-line execution and timing.
- [site/](site/): the original Tunnell browser demo, running in a Web Worker.
- [bench/](bench/): independent Python references, JS implementations,
  measurement scripts and [backend recipes](bench/backends/README.md).
- [tests/](tests/): differential tests for the original application.
- [docs/REPORT.md](docs/REPORT.md): the current report; other documents supply
  methodology, profiling details and historical experiments.

## Build and check

Lean **4.34.1** is selected by `lean-toolchain`; lean-vir remains pinned in
`lakefile.lean`. Build the client and generate current VIR packages:

```sh
lake build tunnell_cli
lake build +Tunnell:vir +Bench:vir
mkdir -p tests/out
node bench/backends/check-client.mjs tests/out/client-checks.json
```

The last command checks all 40 inputs across native Lean, the revised JS
baseline and newly generated VIR packages. It uses the committed VIR runtime
and requires a fresh output filename. Builds also run the small kernel checks.
FIR and C/Wasm need a separate producer/runtime setup; follow the
[backend recipes](bench/backends/README.md).

To inspect the published comparison without compiling or benchmarking:

```sh
python3 bench/render-report-table.py --check
```

To run the original browser demo:

```sh
python3 bench/servir.py
# Open http://127.0.0.1:8125/site/
```

The demo uses the committed historical SDK/package assets. Generating new
packages in `.lake/build/` does not replace those assets or qualify a new
browser deployment. The [original report](docs/REPORT-ORIGINAL.md#appendix-how-every-number-was-produced)
records its original measurement commands.

The original Tunnell differential suite can be rerun with:

```sh
lake build tunnell_cli
mkdir -p tests/out
.lake/build/bin/tunnell_cli 1 10000 > tests/out/nativo.txt
.lake/build/bin/tunnell_cli --ns $(cat tests/azar.txt) > tests/out/nativo-azar.txt
python3 tests/referencia_rapida.py 1 10000 > tests/out/python.txt
python3 tests/referencia_rapida.py --ns $(cat tests/azar.txt) > tests/out/python-azar.txt
node tests/pruebas.mjs
```

## Licences and attribution

This repository: Apache License 2.0 ([LICENSE](LICENSE)). `site/lean-vir/` is the
lean-vir browser SDK, © Lean FRO LLC, Apache License 2.0
([SDK licence](site/lean-vir/LICENSE)). `b003273.txt` is from the OEIS (CC BY-SA 4.0).

The original experiment and its AI-assistance attribution are preserved in the
[original report](docs/REPORT-ORIGINAL.md). The follow-up investigation and
consolidation were prepared with assistance from Codex.
