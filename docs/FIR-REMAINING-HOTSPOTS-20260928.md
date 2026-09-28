# FIR's remaining primality and Mertens costs, 28 September 2026

The frozen post-multiplication FIR package has two distinct hot paths. At the
127-bit Miller–Rabin input, **92.7% of sampled time is under generic natural
remainder**. At Mertens(1,000,000), **40.7% is under generic signed integer
combination**, including 29.8% under integer negation, while natural remainder
accounts for another 19.0%. The phase runs place almost all usable-call time
inside raw Wasm. These are attribution results, not measured optimization gains.

The [next three profiles](FIR-NEXT-THREE-PROFILES-20260928.md) extend this
investigation to the prime sieve, Collatz and Life, identifying array/scalar
helpers, release checks and generated neighbor-counting code as further targets.

The package is the clean FIR producer
`340f4612ac622aa39d6a870528f96d6b827d97b8`, built with Lean 4.34.1 from
the [frozen manifest](../bench/results/2026-09-28-fir-mul/fir-manifest.json).
Its exact package hashes, emitted LCNF hashes, client scripts, raw runs, CPU
captures and SHA-256 inventory are in the
[evidence snapshot](../bench/results/2026-09-28-fir-hotspots/inventory.json).
The previous [five-backend campaign](FIR-MULTIPLICATION-20260928.md#five-backends-fresh-comparison)
measured FIR medians of 113.447 ms for 127-bit primality and 828.345 ms for
Mertens(1,000,000), respectively 71× and 14.9× the C/Wasm medians. The runs
below diagnose those packages in fresh processes; they are not pooled with the
five-backend comparison.

## Usable-call boundaries and phase evidence

Each fresh Node process instantiates the exact zero-import Wasm package, makes
one warmup call, then performs checked calls serially. `marshal` encodes the
natural input and synchronizes the host frontier; `execute` calls only the Wasm
entry; `decode` copies the typed result; `cleanup` rewinds the cache-aware arena
and resets host bookkeeping. The independently timed total includes these four
boundaries. Every result passes the independent case SHA-256 check; every measured
call returns to its warm frontier. Table cells are medians in milliseconds from
the unprofiled phase runs. Phase medians should not be added to reconstruct the
total median.

| Workload | Calls | Marshal | Raw Wasm | Decode | Cleanup | Total | Warm → peak frontier |
|---|---:|---:|---:|---:|---:|---:|---:|
| isPrime, 61 bits | 10 | 0.058 | 24.078 | 0.029 | 0.008 | 24.149 | 8,648 → 11,517,776 B |
| isPrime, 127 bits | 8 | 0.060 | 113.720 | 0.031 | 0.007 | 113.830 | 9,504 → 13,979,536 B |
| Mertens, 100,000 | 8 | 0.011 | 83.434 | 0.077 | 0.005 | 83.543 | 1,601,144 → 10,615,504 B |
| Mertens, 1,000,000 | 5 | 0.011 | 856.010 | 0.033 | 0.006 | 856.061 | 16,001,264 → 82,345,984 B |

The after-call frontier equals the warm frontier in every measured row. Peak
minus warm frontier is the increase in the arena frontier during the call,
not total allocation traffic, memory capacity or live retained bytes. See the raw
[127-bit phase run](../bench/results/2026-09-28-fir-hotspots/prime127-phases/run.json)
and [million-term phase run](../bench/results/2026-09-28-fir-hotspots/mertens1m-phases/run.json)
for all observations and command identities; the smaller cases sit beside them.

## Sampled attribution

Separate Node inspector CPU profiles use a requested 1,000 μs interval over the
measured call loop after warmup. The summarizer attributes each observed delta
to its ending sample, clips at profile end, and divides all percentages by
attributed sample time. Self percentages form disjoint buckets; inclusive
figures below overlap and must not be summed. Every sampled indexed Wasm frame
maps to the *same captured binary's* function inventory, with V8 column number
equal to the encoded body start. This establishes symbol identity for the
sampled module; it does not make sampling deterministic or identify instruction
level costs within a helper.

| Capture | Samples | Resolved Wasm self bucket | Root-only Wasm time | Main inclusive path |
|---|---:|---:|---:|---|
| isPrime 61 bits, 100 calls | 1,514 | 97.9% | 0.8% | `fir_nat_mod_generic` 91.7% |
| isPrime 127 bits, 20 calls | 2,061 | 99.0% | 1.1% | `fir_nat_mod_generic` 92.7% |
| Mertens 100,000, 25 calls | 1,393 | 97.8% | 7.3% | `fir_big_numeric_integer_combine` 51.2% |
| Mertens 1,000,000, 3 calls | 2,228 | 96.8% | 6.6% | `fir_big_numeric_integer_combine` 40.7% |

At 127 bits, the remainder helper's **self** share is 15.6%. Its observed
descendants include natural validation (15.7% self), sum writing (10.8%),
magnitude access, allocation and reference decrement. The generic multiplication
helper has only 0.2% self share in this profile. The 61-bit capture again places
91.7% inclusively under remainder, so the ranking does not depend on the single
127-bit size. `Bench.powMod` is the source caller: each square or conditional
product in [the benchmark](../Bench.lean) is reduced modulo `n`. The emitted
[LCNF](../bench/results/2026-09-28-fir-hotspots/artifacts/isPrime.wasm.lcnf)
confirms `Nat.mul` followed by `Nat.mod` in that loop. The 127-bit raw profile
and exact-symbol [summary](../bench/results/2026-09-28-fir-hotspots/prime127-sample/summary-final.json)
retain caller paths and all self buckets.

The producer's [ResidentNatArithmetic.lean](../bench/results/2026-09-28-fir-mul/source/ResidentNatArithmetic.lean) defines
`genericDivStep` as a binary long-division step: double a natural remainder and
quotient, add the incoming bit, compare against the divisor, and conditionally
subtract. `genericDivBody` runs that step per input bit for both division and
remainder; `modFinish` then releases the quotient. Thus the remainder path
constructs a quotient it never returns. The sampled descendants are consistent
with repeated generic number construction and validation at this source path. They do not count
allocations or prove a particular replacement algorithm will be faster.

At Mertens(1,000,000), the inclusive `integer_combine` share is 40.7%; its
`Int.neg` caller is 29.8% of the *whole capture* and overlaps that share.
Integer validation within `integer_combine` alone contributes 10.7% of the
whole capture. `Bench.muPrime` accounts for 62.8% inclusively and executes
`-a[j]!` for multiples of each prime. The emitted
[LCNF](../bench/results/2026-09-28-fir-hotspots/artifacts/mertens.wasm.lcnf)
confirms this exact array read → `Int.neg` → array set path. The producer's
[ResidentBigNumeric.lean](../bench/results/2026-09-28/fir-profile/source/ResidentBigNumeric.lean) implements `Int.neg` by calling
`integerCombine` with zero and an inverted right sign; that helper validates
both integers, obtains counts and signs, then takes generic sum or difference
paths. This provides a concrete reason to test a direct negation path for the
small signed values in the sieve. The captured profiles do not establish how
often each representation occurs, and they do not show array copying: the
inclusive `Array.set!` share is only 1.6% at one million. The exact-symbol
[Mertens summary](../bench/results/2026-09-28-fir-hotspots/mertens1m-sample/summary-final.json)
and CPU capture preserve the evidence.

Mertens also spends 19.0% inclusively under `fir_nat_mod_generic` at one million,
versus 4.7% at 100,000. Its `muPrime` loop tests `j % (p*p) == 0` for each update.
At one million, `Bench.sumFrom` accounts for 15.2% inclusively and the array
borrowed read for 5.5%; these are separate possible follow-ups. The remainder
share at one million is substantial but smaller than the signed-integer path.
The 1,000,000 capture contains 2.4% V8 GC self bucket and 0.8% JavaScript; the
phase result still places the usable-call time in raw Wasm.

## Ranked next experiments

1. **Generic natural remainder, owned by FIR Wasm emission.** In
   `Fir/Wasm/Emit/ResidentNatArithmetic.lean`, first test a remainder-specific
   step that omits quotient construction, then replace per-bit whole-natural
   double/compare/subtract/allocate work with a limb-oriented remainder path or
   reuse owned scratch. Retain the zero-divisor,
   immediate and mixed-representation contracts and exact quotient/remainder
   semantics. Rebuild a candidate package and compare 61/127-bit primality and
   the existing Fibonacci/partition controls in an order-balanced run. A fresh
   profile should show the remainder subtree shrinking. This is the strongest
   single target: 92.7% observed inclusive share on the headline case.
2. **Signed immediate negation, owned by FIR big-numeric emission.** In
   `Fir/Wasm/Emit/ResidentBigNumeric.lean`, test a direct `Int.neg` path for
   canonical immediate positive/negative values, with the generic path for heap
   values. Check `Int.neg`, `Int.add`, and result canonicalization across both
   signs and representation boundaries. Compare Mertens at 100,000 and one
   million and reprofile `integer_combine`; the expected first signal is less
   `Int.neg`-owned validation/comparison. Broader `integerCombine` immediate
   handling may then address the `sumFrom` tail. The profile supports a target,
   not a claim that all 40.7% can be removed.
3. **Mertens remainder use, jointly workload and runtime scoped.** After the
   generic remainder experiment, inspect `j % (p*p)` for divisors above the
   immediate range and for `p*p > N`. A benchmark-source guard when `p*p > N`
   is mathematically plausible because `j ≤ N`, but it changes the workload
   and must be evaluated separately from a backend fix. Check exact Mertens
   outputs and native/JS/C parity before interpreting any new speedup.

No candidate implementation or rebuild is part of this report. The benchmark's
own Miller–Rabin comment states an exactness range below approximately
`3.3 × 10^24`; the 127-bit test input is beyond that documented guarantee.
Its checked `true` result validates this specific case against the independent
reference hash, not universal primality correctness. The 1,279-bit case was
deliberately excluded because the established bound is 30 seconds per call.

## Reproduction and limits

From this client checkout, with the producer and frozen manifest still present,
run the phase and sample commands serially. The output must be a new directory
under the producer's `.deps`:

```sh
MANIFEST=.deps/fir-producer-mul-340f4612/.deps/math-browser-fir/_build/campaign.KBIKlN/manifest.json
BASE=.deps/fir-producer-mul-340f4612/.deps/math-browser-fir/_profiles
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-prime127-phases" phases isPrime 127 8
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-prime127-sample" sample isPrime 127 20
node bench/backends/summarize-fir-profile.mjs "$BASE/repro-prime127-sample"
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-mertens1m-phases" phases mertens 1000000 5
timeout 30s node bench/backends/profile-fir.mjs "$MANIFEST" "$BASE/repro-mertens1m-sample" sample mertens 1000000 3
node bench/backends/summarize-fir-profile.mjs "$BASE/repro-mertens1m-sample"
```

Use 61 bits and 100,000 as the smaller checks (`10/100` and `8/25`
phase/sample repetitions). The profiler records and checks artifact, descriptor,
build-identity, emitted LCNF and source hashes before and after execution. The
[inventory](../bench/results/2026-09-28-fir-hotspots/inventory.json) checks
the retained capture files and source identities; no binary is copied into the
snapshot. Node 24.21.0 / V8 13.6.233.17-node.53 on Linux x64 and a Ryzen AI 9
HX 370 produced the captures. Processes ran serially; frequency, thermal state,
background load and V8 tier state beyond one warmup were uncontrolled. The CPU
profiles add inspector overhead and include result-hash checks, so use them for
ranking and ownership only. They are not the timing medians or a browser
qualification.
