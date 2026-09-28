# FIR multiplication follow-up, 28 September 2026

**The new generic multiplication substantially fixes the Fibonacci regression.**
In a fresh matched old/new comparison, decimal fib(10,000) improves **168×**,
fibBits(10,000) **377×**, and fibBits(100,000) **1,021×**. The loop and partition
controls remain within roughly 3% of their baseline medians. Miller–Rabin at
127 bits improves only 1.41× and remains a separate performance problem.

This evaluates FIR `340f4612ac622aa39d6a870528f96d6b827d97b8`, accepted by FIR
root after its integration gates, against the previous client producer
`4ae9445c3eb7a2ff72fec9a87d769c976f9ab11a`. Both use the same exact **Lean 4.34.1**
compiler, ordinary interfaces, unit capture and unchanged mathematical sources.
Only resident multiplication implementation files differ in production Wasm
source; the diagnostic host and module loader are byte-identical. The
[identity audit](../bench/results/2026-09-28-fir-mul/identity-audit.json) verifies
clean producer commits, compiler/capture identities, checker identity and hosts.
The [initial report](REPORT.md) retains the earlier campaign as historical evidence.

## Qualification and matched improvement

Fresh packages qualify **39/40 inputs**, with **156 successful checked calls**
across forward/reverse order and immediate repeats. The only unqualified input
is 1,279-bit primality, which exceeds the unchanged 30-second bound. No completed
result mismatches. All ten packages retain zero Wasm imports; warm arena rewinds
pass. Raw artifact sizes increase by 471–472 bytes (fibBits: 14,448 → 14,919).

Both million-term Fibonacci cases now complete: fibBits takes about 410 ms and
decimal fib about 520 ms in the qualification run. Those are diagnostic calls,
not ten-sample medians or matched timeout speedups. Both timed out previously.

The [matched comparison](../bench/results/2026-09-28-fir-mul/paired.json) alternates
AB/BA for ten rounds per input, after one warmup per retained instance. All
**220 timed results** pass independent hashes. Old/new median usable-call times:

- fib(10,000), decimal: **61.826 → 0.367 ms** (168×).
- fibBits(10,000): **49.869 → 0.132 ms** (377×).
- fibBits(100,000): **4,484.985 → 4.395 ms** (1,021×).
- Miller–Rabin, 127 bits: **133.189 → 94.409 ms** (1.41×).

At fibBits(100,000), peak arena frontier falls from **14,313,600 to 90,112 bytes**;
the persistent frontier remains 1,072 bytes. These are arena observations,
not allocation-event counts or a measurement of live objects.

## Five backends, fresh comparison

The following is a separate, freshly timed five-backend campaign using the new
FIR packages and the frozen native/JS/VIR/C-Wasm baselines. The C loader is
byte-identical across the two producer checkouts and checks its package digests.
Ten Williams-design orders balance engine position and within-round predecessor
pairs. All **500 measured results** pass. This table does not mix the historical
timings with new samples; the old/new speedups above use their own matched run.

**Cells show median milliseconds, then FIR time / column time.** Above 1 means
FIR takes longer; below 1 means FIR is faster.

<!-- BEGIN BACKEND TABLE -->
| workload / input | Native | JavaScript | VIR | FIR | C/Wasm |
|---|---:|---:|---:|---:|---:|
| Tunnell / 1,000,003 | 10.163<br>(1.05×) | 1.949<br>(5.45×) | 765.410<br>(0.0139×) | 10.628<br>(1×) | 10.056<br>(1.06×) |
| Collatz / 100,000 | 36.458<br>(2.97×) | 23.753<br>(4.56×) | 5,903.834<br>(0.0184×) | 108.431<br>(1×) | 54.686<br>(1.98×) |
| prime sieve / 1,000,000 | 12.364<br>(3.02×) | 2.150<br>(17.4×) | 1,440.821<br>(0.0259×) | 37.360<br>(1×) | 13.394<br>(2.79×) |
| Mertens / 1,000,000 | 38.070<br>(21.8×) | 30.295<br>(27.3×) | 4,029.435<br>(0.206×) | 828.345<br>(1×) | 55.565<br>(14.9×) |
| partitions / 3,000 | 17.926<br>(1.59×) | 5.211<br>(5.48×) | 177.988<br>(0.161×) | 28.571<br>(1×) | 16.402<br>(1.74×) |
| fib, decimal / 10,000 | 2.195<br>(0.175×) | 0.1264<br>(3.03×) | 3.430<br>(0.112×) | 0.3833<br>(1×) | 6.837<br>(0.0561×) |
| fibBits / 10,000 | 0.0170<br>(12×) | 0.0836<br>(2.44×) | 0.2540<br>(0.805×) | 0.2044<br>(1×) | 0.1391<br>(1.47×) |
| partitionsBits / 3,000 | 16.356<br>(1.64×) | 5.052<br>(5.3×) | 170.641<br>(0.157×) | 26.776<br>(1×) | 15.599<br>(1.72×) |
| Miller–Rabin / 127 bits | 0.6878<br>(165×) | 0.6447<br>(176×) | 3.503<br>(32.4×) | 113.447<br>(1×) | 1.598<br>(71×) |
| Life / 100 | 47.570<br>(1.56×) | 9.239<br>(8.03×) | 4,111.668<br>(0.0181×) | 74.220<br>(1×) | 39.489<br>(1.88×) |
<!-- END BACKEND TABLE -->

The old hundreds-fold C/Wasm gap on fibBits has closed. Decimal Fibonacci now
also beats native and C/Wasm at this input, while native remains much faster
when only the small log2 result is returned. These boundaries include output
conversion; this does not imply FIR has universally faster arithmetic than native.
Miller–Rabin still takes 71× C/Wasm time, and Mertens 14.9×. Multiplication alone
does not resolve these other gaps.

Small timings are sensitive to warmup and scheduling: FIR fibBits samples in
this campaign range from **0.144 to 0.386 ms**. The table reports descriptive
medians, not equivalence or confidence intervals. Do not pool this campaign's
0.204 ms median with the matched run's 0.132 ms.

## Profile: the intended path changed

The [fresh profile](../bench/results/2026-09-28-fir-mul/new-100k-sample/summary.json)
uses 100 calls to fibBits(100,000), after one warmup, and contains 524 samples.
Every indexed Wasm frame resolves against the exact emitted function inventory
and binary body offset; no root-only Wasm samples lack caller ancestry here.
Resolved Wasm accounts for 94.53% of attributed time; profiler bookkeeping is
included in the remaining window.

The new `fir_nat_mul_generic` has **92.71% self-time**. Its implementation is
now base-2^32 schoolbook accumulation within the unchanged 64-bit limb layout.
`fir_big_ext_Nat_add` has only **1.09% observed inclusive stack share**, versus
86.95% in the old profile. Multiplication remains the dominant arithmetic, but
the repeated whole-number addition and generic limb traversal have disappeared
as the main execution path. The profiles are separate attribution captures,
not a timing speedup calculation. Shorter captures have less sampling precision.

Fresh phase runs also pass, with raw-Wasm medians 0.216 ms at 10,000 and
8.267 ms at 100,000. They include phase clocks, start in separate processes,
and are diagnostic rather than the headline timing runs. One warmup does not
establish a fully stabilized V8 tier. Further multiplication algorithms or
specialized squaring remain hypotheses; Miller–Rabin needs its own profile
before attributing its remaining cost to division, remainder or another helper.

## Evidence, limits and reproduction

[Evidence snapshot](../bench/results/2026-09-28-fir-mul/README.md): raw timings,
checks, profiles, package identities, source and SHA-256 inventory. Preparation
and timing reuse the existing client harnesses. No workload definitions, VIR
SDK, C packages or JavaScript baseline changed. FIR source changes are already
accepted by its owner; this is consumer validation, not a new refinement proof
or a browser qualification.

Node 24.21.0 / V8 13.6.233.17-node.53, Linux x64, Ryzen AI 9 HX 370. Builds and
client benchmark processes ran serially. Other machine load, affinity, frequency
and thermals were uncontrolled: one-minute load was 1.90 → 2.14 during the paired
run, 2.05 → 3.21 during the five-backend run. Retained Wasm/JS instances get one
warmup; native runs a fresh process per sample, timing its second call internally.
Usable-call boundaries and library/representation differences remain as described
in the [original methodology](EVALUATION-4341-20260928.md#measurement-policy).

Use a fresh, clean producer at the candidate commit and follow the
[build recipes](../bench/backends/README.md). Then:

```sh
node bench/backends/check-fir-suite.mjs NEW_MANIFEST NEW_CHECKS
node bench/backends/compare-fir-revisions.mjs OLD_MANIFEST OLD_CHECKS NEW_MANIFEST NEW_CHECKS FRESH_PAIRED_OUTPUT
node bench/backends/compare-all.mjs NEW_MANIFEST NEW_CHECKS C_MANIFEST C_CHECKS FRESH_BACKEND_OUTPUT
```

Run these serially and preserve timeouts. The profile commands in the
[original attribution report](FIR-FIBBITS-PROFILE-20260928.md#reproduction-and-evidence)
also accept the new manifest; use 100 repetitions for the new 100,000 sample
capture, with output under the new producer's `.deps/` and a fresh directory.
