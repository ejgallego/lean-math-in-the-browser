# Three more FIR workload profiles, 28 September 2026

The frozen post-multiplication FIR package has three different remaining costs:
`primeCount(1,000,000)` spends time crossing out and counting boxed Boolean
array entries; `collatzRecord(100,000)` spends time in the small-natural step
loop and its release helper; `lifePopulation(100)` spends most sampled time
in neighbor counting, including index arithmetic and array reads. The phase captures
place the usable call overwhelmingly inside Wasm. These profiles identify
targets for experiments, not measured speedups.

This is the exact Lean 4.34.1 producer
`340f4612ac622aa39d6a870528f96d6b827d97b8` from the
[frozen manifest](../bench/results/2026-09-28-fir-mul/fir-manifest.json).
The [evidence inventory](../bench/results/2026-09-28-fir-next-three/inventory.json)
retains hashes for 39 captured files and seven checkout sources. The earlier
[five-backend campaign](FIR-MULTIPLICATION-20260928.md#five-backends-fresh-comparison)
measured FIR medians of 37.36, 108.43 and 74.22 ms for these headline cases,
respectively 2.79×, 1.98× and 1.88× C/Wasm and 17.37×, 4.56× and 8.03×
hand-written JavaScript. Those uninstrumented campaign results are the
comparison baseline; the fresh phase and CPU captures below are diagnostic
and are not pooled with it.

## Boundaries and phase runs

Each fresh Node process instantiated one zero-import Wasm artifact, performed
one warmup, and then ran checked calls serially. `marshal` encodes the natural
input and synchronizes the host frontier; `execute` invokes only the Wasm entry;
`decode` refreshes the host view and copies the typed result (both natural
fields for Collatz); `cleanup` rewinds the arena and clears host bookkeeping.
The independently timed total includes all four boundaries. Every warmup and
measured result passed the independent SHA-256 case check; every measured call
returned to its warm arena frontier. Numbers below are medians in milliseconds
from the **unprofiled phase runs**. Separately computed phase medians must not
be added to recover the total median.

| Case | Calls | Marshal | Raw Wasm | Decode | Cleanup | Total | Warm → peak frontier |
|---|---:|---:|---:|---:|---:|---:|---:|
| Prime count, 100,000 | 12 | 0.011 | 5.099 | 0.014 | 0.003 | 5.135 | 1,024 → 801,104 B |
| Prime count, 1,000,000 | 12 | 0.012 | 30.445 | 0.022 | 0.007 | 30.486 | 1,024 → 8,001,224 B |
| Collatz record, 10,000 | 10 | 0.007 | 9.376 | 0.032 | 0.003 | 9.428 | 1,024 → 1,072 B |
| Collatz record, 100,000 | 10 | 0.010 | 110.193 | 0.063 | 0.006 | 110.290 | 1,024 → 1,072 B |
| Life population, 30 | 12 | 0.004 | 20.426 | 0.003 | 0.002 | 20.441 | 4,289,168 → 4,354,768 B |
| Life population, 100 | 12 | 0.008 | 57.104 | 0.009 | 0.003 | 57.136 | 4,289,168 → 4,354,768 B |

The per-call arena frontier delta is not total allocation traffic or live
retained memory. Life's warm frontier reflects the cache-aware arena floor
after warmup; the recorded peak is the captured frontier high point after
execution. See the
[prime](../bench/results/2026-09-28-fir-next-three/prime1m-phases/run.json),
[Collatz](../bench/results/2026-09-28-fir-next-three/collatz100k-phases/run.json)
and [Life](../bench/results/2026-09-28-fir-next-three/life100-phases/run.json)
phase files for all rows and command identities.

## CPU attribution and exact symbols

Separate Node inspector captures request a 1,000 µs sample interval over the
measured call loop after warmup. The summarizer assigns each observed time
delta to its ending sample, clips at profile end, and uses all attributed
sample time as the denominator. Self buckets are disjoint; inclusive callers
overlap and must never be summed. Each indexed Wasm frame maps to the **same
captured release binary's** function inventory, and its V8 column equals that
function's encoded body start. There was exactly one sampled Wasm module per
capture, no imports, and no unresolved indexed frames. The root-only Wasm
fraction shows where a resolved leaf lacks usable caller ancestry. A resolved
function body does not identify which of its instructions is costly.

| Capture | Calls | Samples | Resolved Wasm self | Root-only Wasm | Main inclusive path |
|---|---:|---:|---:|---:|---|
| Prime count, 100,000 | 100 | 299 | 93.2% | 1.9% | `Bench.countTrue` 44.8%; `Bench.crossOut` 34.1% |
| Prime count, 1,000,000 | 70 | 2,496 | 99.1% | 1.2% | `Bench.crossOut` 46.9%; `Bench.countTrue` 38.2% |
| Collatz record, 10,000 | 30 | 255 | 93.2% | 2.2% | `Bench.collatzSteps` 66.2%; `fir_release_0` 39.5% |
| Collatz record, 100,000 | 20 | 2,019 | 99.0% | 2.7% | `Bench.collatzSteps` 78.9%; `fir_release_0` 38.1% |
| Life population, 30 | 50 | 972 | 97.7% | 0% | `Bench.neighbours` 87.0% |
| Life population, 100 | 30 | 1,844 | 99.0% | 0.1% | `Bench.neighbours` 88.8% |

Here the root-only percentages are shares of attributed sample time, not counts
of samples. The smaller prime and Collatz captures have fewer than 300 samples;
use them as coarse corroboration, not precise percentage estimates.

At one million, prime counting spends 24.6% **self** in `Bench.crossOut` and
22.5% self in `fir_ext_Array_set!`; 22.2% of the capture is the observed
`crossOut → Array.set!` path. `Bench.countTrue` takes 38.2% inclusively, with
10.4% self in `fir_unbox_uint8`, 7.5% in `fir_box_uint8` under that caller,
5.9% in `Array.get!Internal` under it and 8.3% self in `countTrue` itself.
These shares overlap only where the caller relationship is stated. The
[source benchmark](../Bench.lean) crosses out multiples in an `Array Bool` and
then counts `true` entries. Its captured
[LCNF](../bench/results/2026-09-28-fir-next-three/artifacts/primeCount/primeCount.wasm.lcnf)
shows `Array.set!` in `crossOut`, and `box` → `Array.get!Internal` → `unbox`
in `countTrue`; the [array emitter](../bench/results/2026-09-28-fir-next-three/source/ResidentArray.lean)
and [scalar boxing emitter](../bench/results/2026-09-28-fir-next-three/source/ResidentScalarBox.lean)
are the captured producer sources. The [raw profile](../bench/results/2026-09-28-fir-next-three/prime1m-sample/cpu.cpuprofile)
and [exact-symbol summary](../bench/results/2026-09-28-fir-next-three/prime1m-sample/summary-final.json)
retain the caller paths. The sampled `crossOut`, `Array.set!` and `countTrue`
bodies are function indices 0, 58 and 2 at byte offsets 593, 13,798 and
1,892 in the captured module.

The scalar source makes an important distinction: `boxUInt8Function` constructs
a tagged immediate, not a heap allocation. Its `retypeRaw` helper saves, writes,
reads and restores a scratch memory word; unboxing also validates the tag and
range. The profile supports investigating these normal conversion paths, not
describing the boxing share as allocation cost.

At 100,000, Collatz spends 59.3% **self** in `Bench.collatzSteps` and 38.1%
self in `fir_release_0`; 19.6% of the whole capture is the observed
`collatzSteps → fir_release_0` path and 15.8% is
`collatzBest → fir_release_0`. The `collatzSteps` inclusive share is 78.9%.
The [LCNF](../bench/results/2026-09-28-fir-next-three/artifacts/collatzRecord/collatzRecord.wasm.lcnf)
retains `% 2`, `3*n + 1`, shift right on even values, the fuel decrement and
several `dec` operations per recursive step; `collatzBest` calls it once for
each candidate. The [release emitter](../bench/results/2026-09-28-fir-next-three/source/ResidentRelease.lean)
explains the generated release wrappers and tagged-value checks. Function
indices 0 and 18 start at byte offsets 519 and 5,009 in the captured module.
The [raw profile](../bench/results/2026-09-28-fir-next-three/collatz100k-sample/cpu.cpuprofile)
and [summary](../bench/results/2026-09-28-fir-next-three/collatz100k-sample/summary-final.json)
show the measured paths. The tiny warm-to-peak frontier delta and absence of
sampled generic natural remainder are consistent with an immediate-heavy path;
they do not prove the representation of every intermediate value or isolate
the cost of an individual arithmetic operation inside `collatzSteps`.

At 100 generations, Life spends 76.9% **self** in
`Bench.neighbours._lam_0`, 12.8% self in `Bench.neighbours` and 5.8% self in
`Bench.stepCells`. `Bench.neighbours` accounts for 88.8% inclusively. The
[LCNF](../bench/results/2026-09-28-fir-next-three/artifacts/lifePopulation/lifePopulation.wasm.lcnf)
calls the lambda eight times per cell; each call computes two wrapped
coordinates and an array read. The lambda is function index 0, byte offset
746, in the captured module. The `Array.set!` inclusive share is only 1.3%,
so output array writes are a smaller target for this workload. The
[raw profile](../bench/results/2026-09-28-fir-next-three/life100-sample/cpu.cpuprofile)
and [summary](../bench/results/2026-09-28-fir-next-three/life100-sample/summary-final.json)
preserve the path. No source-level sample separates `% 64`, additions,
boxing, or inlined array reads inside the lambda; those require finer
instruction-level evidence before assigning individual costs.

## Ranked general experiments

1. **Specialize the normal Boolean-array path, starting with the prime sieve.**
   In the FIR array and scalar boxing emitters, test a checked, semantics-
   preserving fast path for tagged Boolean reads and writes at known-valid
   indices, including the common in-place update case. Keep the existing
   out-of-bounds, sharing, ownership and malformed-value behavior. Compare
   `primeCount` at both sizes and array-heavy controls, then reprofile
   `Array.set!`, `countTrue` and boxing. The 22.5% set self share and 38.2%
   count subtree make this the strongest next target for the largest JS gap;
   their total is **not** a predicted saving.
2. **Reduce repeated checked releases and immediate-Nat work in loops.**
   Use `collatzRecord` as the representative case to inspect why the generated
   `fir_release_0` wrapper gets 38.1% self, including the `collatzSteps` and
   `collatzBest` callers. Test type/ownership propagation or guarded release
   elision for provable tagged values; keep heap-reference checks and arbitrary
   Nat correctness. Inspect the `collatzSteps` body at instruction level before
   changing arithmetic, since its 59.3% self share combines several operations.
   Reprofile both Collatz sizes and check `primeCount`, where release has 4.1%
   self share, for a possible shared benefit.
3. **Simplify fixed-range neighbor indexing in the normal lowering path.**
   Investigate constant power-of-two modulo, repeated coordinate arithmetic,
   and bounds handling in the eight calls to the Life neighbor lambda. Compare
   the same Lean source before and after a compiler experiment, then use a
   separately labeled source-level direct-index experiment only to measure
   algorithm/representation headroom. Reprofile the lambda and both Life sizes;
   no current profile identifies one instruction as the dominant cost.

These targets complement the prior [generic natural remainder and signed
negation report](FIR-REMAINING-HOTSPOTS-20260928.md). The generic remainder
symbol is present in Collatz and Life modules but receives no samples in these
headline captures; `Int.neg` is irrelevant here. The `fir_release_0` and array
paths provide the useful overlap among these three cases. The JavaScript
[baseline](../bench/js-baseline-revised.mjs) uses a `Uint8Array` for the sieve
and Life grid and tight number loops for Collatz; Lean uses `Array Bool` and
`Nat` with checked operations. Life's JS loop also indexes neighbors directly
instead of making eight generated lambda calls. Thus the JS ratios include
algorithm expression and representation differences as well as backend
overhead. This does not establish that helper-call overhead itself dominates
Life: V8 may inline work into the sampled function. C/Wasm and native compile
the same Lean benchmark source and offer
closer controls, but remain different runtimes and optimization pipelines.

## Reproduction and limits

Run the commands serially from this client checkout. The profiler accepts
only output directories under the producer's `.deps` and refuses a dirty or
different producer. Substitute the workload, size and count as shown in the
[captured runs](../bench/results/2026-09-28-fir-next-three/README.md):

```sh
MANIFEST=.deps/fir-producer-mul-340f4612/.deps/math-browser-fir/_build/campaign.KBIKlN/manifest.json
BASE=.deps/fir-producer-mul-340f4612/.deps/math-browser-fir/_profiles
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-prime1m-phases" phases primeCount 1000000 12
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-prime1m-sample" sample primeCount 1000000 70
node bench/backends/summarize-fir-profile.mjs "$BASE/repro-prime1m-sample"
```

Node 24.21.0 / V8 13.6.233.17-node.53 on Linux x64 and a Ryzen AI 9 HX
370 produced these captures. Processes ran serially; frequency, thermal state,
background load and V8 tier state beyond one warmup were uncontrolled. CPU
sampling includes result checks and inspector overhead, so use sample shares
for ranking and ownership rather than elapsed comparisons. These are Node
calls, not browser qualification. All exact package, descriptor, emitted LCNF,
function inventory, client and host hashes were checked before and after each
run; the [inventory](../bench/results/2026-09-28-fir-next-three/inventory.json)
also checks published copies. No FIR implementation or package was rebuilt.
