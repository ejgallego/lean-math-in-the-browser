# FIR fibBits attribution, 2026-09-28

The dominant cost is FIR's generic resident Nat multiplication, implemented
as repeated whole-number doubling and addition. Its addition and limb-access
helpers dominate sampled self-time. This establishes a concrete target for
the next investigation; no arithmetic implementation was changed here.

## Frozen workload

- Source: original `Bench.fibBits`, with unchanged mathematical definitions.
- Producer: `14be5c08bca91177fe033d13001a6bafeca22c19`, clean detached worktree.
- Lean: 4.34.0-rc2, `6a10ac8c22beadecabdbb0919c2b50214762f91d`.
- Wasm: 14,448 bytes, zero imports, SHA-256
  `7b1353b299e9e84663bd3edea96192b285bc61400894756d61a772a227bbc869`.
- Engine: Node 24.21.0, V8 13.6.233.17-node.53, Linux x64, Ryzen AI 9 HX 370.
- Inputs: 10,000 and 100,000. Expected log2 results: 6,941 and 69,423.

The existing package was reused without rebuilding, rewriting, adding names,
or changing its executable sections. The original diagnostic adapter is
unchanged. A separate profiling driver reproduces its Nat marshalling and
cache-aware heap reclamation with explicit phase clocks. Each run records
artifact, descriptor, inventory, LCNF, harness, host and reference hashes.

## Phase measurements

Each fresh process instantiates once, runs one warmup, then retains the instance
for five calls at 10,000 or three calls at 100,000. All warmup and measured
results pass the independent reference hash. No sampler runs in this phase
campaign. The added phase clocks make these diagnostic timings, separate from
the earlier balanced backend comparison.

| input | marshal median | raw Wasm median | decode median | cleanup median | independently timed total median |
|---|---:|---:|---:|---:|---:|
| 10,000 | 0.0138 ms | 83.118 ms | 0.0547 ms | 0.0101 ms | 83.186 ms |
| 100,000 | 0.0156 ms | 8,230.124 ms | 0.0445 ms | 0.0088 ms | 8,230.194 ms |

Raw Wasm occupies **99.896%** and **99.9991%** of summed call time respectively.
Marshal includes argument construction and host/frontier synchronization;
decode includes view refresh and copying the small Nat as decimal text;
cleanup includes arena rewind and host bookkeeping. Hash validation is outside
the timers. Phase medians are independently computed, not summed into a total.

Total-time ranges were 65.89–86.37 ms and 8,140.34–8,377.42 ms. Background load
was uncontrolled (the 100,000 run's one-minute load rose from 4.26 to 7.37).
No client build or second client benchmark ran concurrently. These absolute
times differ from the earlier campaign and must not be treated as a regression
or used as a before/after comparison.

All measured calls rewind to the same 1,072-byte persistent frontier. Peak
frontiers are 165,952 and 14,313,600 bytes; retained linear-memory capacities
are 196,608 and 14,352,384 bytes. These are arena frontier/capacity observations,
not allocation-event totals or live-object measurements. They do not imply a
retention leak.

## Sampled attribution

Separate processes use Node's inspector CPU profiler with a requested 1,000 µs
sampling interval, after one unprofiled warmup. The captures contain 20 calls at
10,000 and two calls at 100,000. All results and warm-call rewind checks pass.
Profiler start/stop bookkeeping and outside-timer validation are included in
the profile window; startup, module loading and the warmup are excluded.

| observation | 10,000 | 100,000 |
|---|---:|---:|
| samples | 1,379 | 11,529 |
| resolved Wasm self-time share | 98.37% | 99.83% |
| `fir_nat_mul_generic`, inclusive observed stack share | 88.35% | 92.26% |
| `fir_big_ext_Nat_add`, inclusive observed stack share | 83.64% | 86.95% |
| Wasm leaf samples with missing caller ancestry | 10.01% | 7.57% |

Inclusive rows overlap and must not be added. The remaining profile self-time
is JavaScript, predominantly the inspector's `post` bookkeeping; no V8 GC or
idle samples were observed. Sampling durations are weighted by actual recorded
`timeDeltas`, assigning each preceding interval to its ending sample and
clipping at the profile end. Unobserved tails of 0.486 and 1.038 ms remain
unassigned. No cross-clock phase slicing is used.

Top **self-time** shares at 100,000, using all attributed profile time as the
denominator:

| symbol | self share |
|---|---:|
| `fir_big_numeric_magnitude_high` | 28.31% |
| `fir_big_numeric_write_sum_from` | 17.79% |
| `fir_big_ext_Nat_add` | 14.50% |
| `fir_big_numeric_magnitude_low` | 12.34% |
| `fir_big_numeric_natural_high` | 11.31% |
| `fir_big_numeric_natural_low` | 9.00% |
| `fir_big_numeric_natural_count` | 4.34% |
| `fir_nat_mul_generic` | 1.92% |

Directly attributed allocator/recycler/numeric-allocation/refcount self-time
totals about 0.15% at 100,000 (1.43% at 10,000). That does not quantify indirect
allocation/cache costs. The profile supports prioritizing the arithmetic and
limb traversal path ahead of direct allocator or reference-count execution.

## Exact symbol resolution and caller limits

The artifact has 59 defined functions and zero imported functions. Its
emitter-final inventory names functions in Wasm definition order. For every
indexed Wasm frame, the summarizer checks both the function index and V8's
reported byte offset against the actual binary code section's function-body
start. All 17 observed body symbols resolve in each capture; one Wasm module
is present. JS-to-Wasm trampolines are handled separately.

Some V8 samples attach a resolved limb-access leaf directly to the profile root.
Their leaf attribution is usable, but their caller ancestry is unavailable.
The 92.26% multiplication share is therefore the *observed inclusive stack
share*, not a claim of perfect unwinding. The raw profiles and summaries retain
these samples explicitly. Self-time in an optimized frame can include inlined
work; no claim is made about an exact machine instruction or which carry-scan
instructions V8 inlined into `Nat.add`.

## Mapping to LCNF and producer source

The captured LCNF preserves fast-doubling Fibonacci:

```text
Bench.fibBits → Bench.fib → Bench.fibPair
  Nat.mul 2 b
  Nat.mul a (2*b-a)
  Nat.mul a a
  Nat.mul b b
```

The corresponding sampled resident path is:

```text
fir_ext_Nat_mul → fir_nat_mul_generic
  → fir_big_ext_Nat_add
    → fir_big_numeric_write_sum_from
      → fir_big_numeric_magnitude_{low,high}
        → fir_big_numeric_natural_{count,low,high}
```

Source evidence refers to the frozen producer, not its advancing main branch:

- [LCNF](../bench/results/2026-09-28/fir-profile/artifact/fibBits.wasm.lcnf)
  retains the four `Nat.mul` operations and the final `Nat.log2`.
- [ResidentNatArithmetic.lean](../bench/results/2026-09-28/fir-profile/source/ResidentNatArithmetic.lean),
  lines 297–372: `genericMulBit` conditionally adds the addend to the result and
  doubles the addend for every multiplier bit. The outer loop visits two
  32-bit parts per 64-bit limb, selecting the operand with fewer limbs as the
  multiplier. Lines 210–236 route both operations through resident `Nat.add`
  and release the replaced temporary.
- [ResidentBigNumeric.lean](../bench/results/2026-09-28/fir-profile/source/ResidentBigNumeric.lean),
  lines 1583–1607: the non-immediate addition path validates operands, determines
  the result size with a carry scan, allocates/recycles a result object, and
  writes the sum. Lines 814–869 define the scan and write loops. Lines 521–554
  implement the generic magnitude accessors, including count/bounds and
  Nat/Int-flavor dispatch.

Thus each generic multiplication repeatedly traverses growing multi-limb
values through general addition/accessor helpers. The samples identify where
this work executes, and the source explains why multiplication invokes so much
addition. This is sufficient attribution for step 1. It is not yet evidence
for a particular replacement algorithm's speedup or a compiler correctness bug.

## Reproduction and evidence

Run from the client repository root, using a fresh directory for each command:

```sh
manifest=.deps/fir-producer/.deps/math-browser-fir/_build/suite-ordinary-unit.json
profiles=.deps/fir-producer/.deps/math-browser-fir/_profiles
mkdir -p "$profiles"
timeout 90s node bench/backends/profile-fir.mjs "$manifest" "$profiles/my-10k-phases" phases 10000 5
timeout 90s node bench/backends/profile-fir.mjs "$manifest" "$profiles/my-100k-phases" phases 100000 3
timeout 90s node bench/backends/profile-fir.mjs "$manifest" "$profiles/my-10k-sample" sample 10000 20
timeout 90s node bench/backends/profile-fir.mjs "$manifest" "$profiles/my-100k-sample" sample 100000 2
node bench/backends/summarize-fir-profile.mjs "$profiles/my-10k-sample"
node bench/backends/summarize-fir-profile.mjs "$profiles/my-100k-sample"
```

The external timeout bounds a stuck Wasm call; an interrupted run remains
`running` in its partial report and cannot pass the summarizer's completed-run
check. Profiling does not regenerate packages or require a Lake build.

Published evidence snapshots (the producer worktree and runtime binary remain local):

- [10,000 phase samples](../bench/results/2026-09-28/fir-profile/fibbits-10k-phases/run.json)
- [100,000 phase samples](../bench/results/2026-09-28/fir-profile/fibbits-100k-phases/run.json)
- [10,000 raw CPU profile](../bench/results/2026-09-28/fir-profile/fibbits-10k-sample/cpu.cpuprofile)
  and [summary](../bench/results/2026-09-28/fir-profile/fibbits-10k-sample/summary-v2.json)
- [100,000 raw CPU profile](../bench/results/2026-09-28/fir-profile/fibbits-100k-sample/cpu.cpuprofile)
  and [summary](../bench/results/2026-09-28/fir-profile/fibbits-100k-sample/summary-v2.json)

The two profiling scripts and this report are the deliverable. No FIR runtime,
source workload, existing adapter or package bytes changed. A focused
multiplication reproducer and implementation experiments belong to the next step.
