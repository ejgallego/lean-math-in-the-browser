# FIR rebenchmark, 29 September 2026

**Current FIR main improves 61- and 127-bit Miller–Rabin by about 1.3–1.4×
over the last accepted client build, but primality remains far behind native,
JavaScript and C/Wasm.** Mertens improves more modestly against that same
baseline. A separate, isolated remainder candidate confirms that removing
unused quotient work helps primality; current main also contains the earlier
small-`Int` negation change and other runtime changes, so their effects must
not be attributed to remainder alone.

The current producer is clean FIR `94de4678b44d0d940436247543f38c156b6f611c`
on the exact **Lean 4.34.1** compiler. It uses the same mathematical sources,
ordinary interface and unit capture, checker and client adapters as the
[previous accepted producer](FIR-INT-NEG-20260928.md), `05e0febe5`. The
[identity audit](../bench/results/2026-09-29-fir-main/identity-audit.json)
checks those identities; all ten generated Wasm packages changed. This is a
regular-FIR Node evaluation. The client source, VIR package, C package and JS
implementation did not change.

## Qualification and matched changes

Current main qualifies **39/40 inputs** under the unchanged 30-second call
limit. The sole unqualified input is 1,279-bit primality; no completed result
mismatches and warm arena rewinds pass. The [full matched run](../bench/results/2026-09-29-fir-main/paired.json)
contains **240 checked timed observations**, including 61- and 127-bit
primality and the ten headline controls. Load was high and changing in that
run, so the following key figures use [lower-load focused repeats](../bench/results/2026-09-29-fir-main/README.md)
of ten alternating old/new pairs per input:

| Input | Previous FIR → current main median | Speedup |
|---|---:|---:|
| Miller–Rabin, 61 bits | 24.086 → 18.230 ms | 1.32× |
| Miller–Rabin, 127 bits | 88.960 → 64.611 ms | 1.38× |
| Mertens, 100,000 | 44.363 → 40.547 ms | 1.09× |
| Mertens, 1,000,000 | 634.062 → 595.472 ms | 1.07× |

In the same lower-load format, Collatz(100,000) improves **97.133 →
82.792 ms (1.17×)**; primeCount(1,000,000) is essentially flat at
**34.040 → 34.166 ms**. Life(100) is a repeatable slowdown:
**58.455 → 67.916 ms** and, in a second matched run,
**60.602 → 69.843 ms** (about 15% longer). These are measured client
observations, not an attribution to a specific FIR commit. All focused timed
results pass independent output hashes and warm-frontier checks.

## Five backends, current main

The table uses a separate fresh campaign of ten balanced five-engine orders,
with **500 checked measured results**. The native, JS, VIR and C/Wasm packages
are the frozen baselines. Cells show median milliseconds followed by **FIR
time / column time**; above one means FIR takes longer. This campaign started
with one-minute load about 3, versus about 23 in the [first complete run](../bench/results/2026-09-29-fir-main/comparison-high-load.json).
Both raw campaigns are retained, but their medians are not pooled.

<!-- BEGIN BACKEND TABLE -->
| workload / input | Native | JavaScript | VIR | FIR | C/Wasm |
|---|---:|---:|---:|---:|---:|
| Tunnell / 1,000,003 | 10.257<br>(1.11×) | 1.945<br>(5.87×) | 751.763<br>(0.0152×) | 11.408<br>(1×) | 9.434<br>(1.21×) |
| Collatz / 100,000 | 43.344<br>(2.15×) | 21.388<br>(4.36×) | 5,565.760<br>(0.0168×) | 93.309<br>(1×) | 63.122<br>(1.48×) |
| prime sieve / 1,000,000 | 10.556<br>(2.94×) | 2.067<br>(15×) | 1,337.386<br>(0.0232×) | 31.084<br>(1×) | 12.414<br>(2.5×) |
| Mertens / 1,000,000 | 36.822<br>(14.9×) | 29.257<br>(18.7×) | 4,055.868<br>(0.135×) | 548.383<br>(1×) | 58.539<br>(9.37×) |
| partitions / 3,000 | 14.872<br>(1.67×) | 4.533<br>(5.5×) | 149.485<br>(0.167×) | 24.909<br>(1×) | 15.198<br>(1.64×) |
| fib, decimal / 10,000 | 1.826<br>(0.144×) | 0.1183<br>(2.22×) | 2.732<br>(0.096×) | 0.2622<br>(1×) | 5.811<br>(0.0451×) |
| fibBits / 10,000 | 0.0292<br>(5.22×) | 0.0620<br>(2.46×) | 0.2111<br>(0.723×) | 0.1526<br>(1×) | 0.1126<br>(1.35×) |
| partitionsBits / 3,000 | 14.510<br>(1.64×) | 4.419<br>(5.39×) | 153.959<br>(0.155×) | 23.799<br>(1×) | 15.444<br>(1.54×) |
| Miller–Rabin / 127 bits | 0.6360<br>(116×) | 0.5897<br>(126×) | 3.339<br>(22.2×) | 74.059<br>(1×) | 1.402<br>(52.8×) |
| Life / 100 | 34.587<br>(2.07×) | 7.814<br>(9.18×) | 3,489.372<br>(0.0206×) | 71.753<br>(1×) | 33.532<br>(2.14×) |
<!-- END BACKEND TABLE -->

At Mertens(1,000,000), FIR is about **7.4× faster than VIR** but still takes
**9.37× C/Wasm**, **14.9× native** and **18.7× JS** time. At 127-bit primality,
FIR remains **52.8× C/Wasm**, **116× native**, **126× JS** and **22.2× VIR**.
These are complete client-call comparisons across different libraries and
representations, with the [methodology's timing boundaries](EVALUATION-4341-20260928.md#measurement-policy).
Host load, frequency, thermals and V8 tiering beyond one warmup are not
controlled; the ratios are descriptive medians, not confidence intervals.

## Isolating the natural-remainder change

FIR root supplied a frozen `faee469e5` package whose only changed emission
source relative to the pre-negation multiplication producer is
`ResidentNatArithmetic.lean`: a canonical-zero correction plus omission of
quotient construction on the generic remainder path. A clean rebuild at that
exact commit is **byte-identical across all ten Wasm packages** to root's
frozen package; see the [candidate identity audit](../bench/results/2026-09-29-fir-natmod/identity-audit.json).

Against the pre-negation FIR package, the isolated candidate's
[240-result matched run](../bench/results/2026-09-29-fir-natmod/paired.json)
improves Miller–Rabin **1.32× at 61 bits** and **1.37× at 127 bits**, and
Mertens(1,000,000) **1.08×**. The other large controls are near flat. Separate
five-backend runs put this candidate at **78.414 ms (51.9× C/Wasm)** for
127-bit primality and **686.712 ms (14.4× C/Wasm)** for Mertens(1,000,000).
Its qualification passed all **40/40** inputs on this run, but the two
1,279-bit calls took **29.64 and 29.46 seconds**, too close to the limit to
declare that timeout reliably solved. Current main timed out on that input
under different host load. The qualification difference is not attributed to
code without a controlled repeat.

A direct matched candidate→current-main comparison finds primality essentially
unchanged (**1.05×** at 61 bits, **1.00×** at 127 bits), while Mertens gains
**1.64×** at 100,000 and **1.46×** at 1,000,000. Current main includes other
array, release, scalar and call-site changes as well as small-`Int` negation;
these direct figures measure the combined change.

## Remaining runtime costs and Life follow-up

In the [old 127-bit profile](../bench/results/2026-09-28-fir-hotspots/prime127-sample/summary-final.json),
`fir_nat_mod_generic` accounted for 92.7% of observed inclusive stack time.
The exact-symbol fresh captures put it at **52.5%** in the isolated candidate
and **52.3%** in current main. The candidate's 61-bit capture gives 51.8%.
The sampled shares are from separate processes, not speedup estimates, and
they may omit caller ancestry; current main's 127-bit capture has 1.15%
root-only Wasm sampled time. New 127-bit self-time still includes natural
validation, sum writing, allocation and decrement. Generic remainder remains
the largest directly identified primality subtree, despite the meaningful
quotient-work reduction.

At Mertens(1,000,000), current main's fresh inclusive shares are **19.9%**
generic remainder, **13.1%** `Int.neg` and **17.8%** integer combination; the
fresh phase run puts virtually all usable-call time inside raw Wasm. Those
paths still merit optimization, though their inclusive shares overlap and
do not predict additive savings.

Life's fresh raw-Wasm phase median is **67.095 ms**. The sampled neighbor
lambda remains about **76.4% self time**, close to the old 76.9%; the profile
does not localize the slowdown within its compiled calls. A deterministic
[Wasm body audit](../bench/results/2026-09-29-fir-main/life-body-audit.json)
shows the neighbor lambda's encoded body is byte-identical, while
`Bench.stepCells` grows from **1,737 to 3,079 bytes** and seven other bodies
change. The accepted Array.set! inline path is a plausible contributor, but
this evidence does not isolate a single commit or instruction. FIR root should
investigate the repeatable Life timing regression separately from the confirmed
remainder and Mertens gains.

The [main evidence snapshot](../bench/results/2026-09-29-fir-main/README.md)
and [isolated-candidate snapshot](../bench/results/2026-09-29-fir-natmod/README.md)
retain every raw timing, check, CPU profile, package identity and SHA-256
inventory used here. All experiments were serial Node 24.21.0 / V8
13.6.233.17-node.53 runs on the same Ryzen AI 9 HX 370 host. They do not
qualify browser/Worker behavior.
