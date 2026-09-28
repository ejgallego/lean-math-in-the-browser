# FIR small-integer negation follow-up, 28 September 2026

**The newly accepted FIR small-`Int` negation path improves Mertens, but generic
remainder remains a substantial cost.** At 100,000, the matched median falls
from 48.186 to 30.581 ms (**1.58× faster**); at 1,000,000, from 684.456 to
522.074 ms (**1.31× faster**). This is a client validation of FIR
`05e0febe5fdd3c947e31d1ae661c73d36cfcb80e` against the previous accepted
multiplication producer `340f4612ac622aa39d6a870528f96d6b827d97b8`.
The [previous evaluation](FIR-MULTIPLICATION-20260928.md) explains the larger
Fibonacci improvement; the [hotspot report](FIR-REMAINING-HOTSPOTS-20260928.md)
motivated this negation change.

Both producers use the exact same Lean **4.34.1** compiler, mathematical sources,
ordinary interface and unit capture settings, checker, diagnostic host and
module client. The C loader is byte-identical. The [identity audit](../bench/results/2026-09-28-fir-intneg/identity-audit.json)
records these checks. Of ten rebuilt Wasm packages, **only Mertens changes**;
the other nine binaries are byte-identical. Its package grows by 187 bytes
(21,895 → 22,082). The separate FIR remainder work was not included.

## Qualification and matched timings

The new packages qualify **39 of 40 inputs** under the unchanged 30-second
per-call limit. The sole unqualified input is 1,279-bit primality; all completed
results match their independent references and the warm arena checks pass.
The [raw qualification](../bench/results/2026-09-28-fir-intneg/fir-checks.json)
retains the timeout rather than treating it as a successful result.

The [matched run](../bench/results/2026-09-28-fir-intneg/paired.json) uses ten
alternating AB/BA rounds for each of the two Mertens inputs, after one warmup
per retained instance. All **40 measured results** pass reference hashes.
Its useful-call boundary includes FIR marshalling, result conversion and arena
rewind; startup and correctness hashing are outside the timer. The change is
therefore measurable at both sizes, while the larger input still costs over
half a second in this matched run.

## Five backends at Mertens(1,000,000)

A separate, freshly timed campaign uses ten balanced five-engine orders and
checks all **50 measured results**. The native, JS, VIR and C/Wasm packages
are the frozen earlier baselines; the FIR package is the new one. Each cell is
median milliseconds followed by **FIR time / that column's time**. A ratio
above one means FIR takes longer.

<!-- BEGIN BACKEND TABLE -->
| workload / input | Native | JavaScript | VIR | FIR | C/Wasm |
|---|---:|---:|---:|---:|---:|
| Mertens / 1,000,000 | 38.491<br>(12.8×) | 29.792<br>(16.5×) | 3,625.408<br>(0.136×) | 492.939<br>(1×) | 47.261<br>(10.4×) |
<!-- END BACKEND TABLE -->

FIR is about **7.35× faster than VIR**, but still takes **10.4× C/Wasm**, **12.8×
native**, and **16.5× JS** time for this selected input. These are comparisons
of complete client calls with the differing libraries, representations and
conversion boundaries documented in the [methodology](EVALUATION-4341-20260928.md#measurement-policy).
The five-backend FIR median (492.939 ms) is from its own campaign and should
not be pooled with the matched median (522.074 ms). Native samples vary from
23.133 to 51.534 ms, so the ratios are descriptive, not precision claims.

## What remains hot

Fresh [phase runs](../bench/results/2026-09-28-fir-intneg/README.md) put the
median raw Wasm execute phase at 57.323 ms for 100,000 (eight calls) and
480.116 ms for 1,000,000 (five calls); marshalling, decoding and cleanup are
small at these sizes. They are separate diagnostic captures, not the matched
speedup evidence.

The [new million-input CPU profile](../bench/results/2026-09-28-fir-intneg/intneg-mertens1m-sample/summary-final.json)
contains 1,551 samples, with all indexed Wasm frames validated against the
exact emitted function inventory and body offsets. Its observed inclusive
stack shares are **18.73%** for `fir_big_numeric_integer_combine`, **11.06%** for
`fir_big_ext_Int_neg`, and **24.60%** for `fir_nat_mod_generic`. In the
[previous separate capture](../bench/results/2026-09-28-fir-hotspots/mertens1m-sample/summary-final.json),
the corresponding shares were 40.70%, 29.84% and 19.03%. The altered mix is
consistent with a faster small-negation path; sample percentages across these
different captures are *not* a speedup estimate. About 4.47% of new sampled
time is root-only Wasm with no caller ancestry, so inclusive shares are bounded
observations. Generic remainder is now the largest of these three paths at
one million and remains the next FIR runtime experiment.

## Reproduce and inspect

The [evidence snapshot](../bench/results/2026-09-28-fir-intneg/README.md)
preserves all raw observations, qualifications, package identities, source and
profiles with a SHA-256 inventory. Rebuild regular FIR at the two clean commits
with the [backend recipes](../bench/backends/README.md), then run:

```sh
node bench/backends/check-fir-suite.mjs NEW_MANIFEST FRESH_CHECKS
node bench/backends/compare-fir-revisions.mjs OLD_MANIFEST OLD_CHECKS NEW_MANIFEST FRESH_CHECKS FRESH_PAIRED --workload mertens
node bench/backends/compare-all.mjs NEW_MANIFEST FRESH_CHECKS C_MANIFEST C_CHECKS FRESH_COMPARISON --workload mertens
```

These Node 24.21.0 / V8 13.6.233.17-node.53 measurements ran serially on one
Ryzen AI 9 HX 370 host. Background load, affinity, clocks and temperature were
uncontrolled; one warmup does not establish fully stabilized V8 tiering. This
is a regular-FIR Node result, not browser/Worker qualification. No client
mathematical programs, VIR package, C package or JS implementation changed.
