# VIR usage audit, 2026-09-28

The reviewed client uses VIR appropriately for these workloads. We found no
major integration antipattern or supported runtime/host setting that would
remove the observed slowdown. This conclusion covers the pinned SDK and the
tested Node workloads; it is not an exhaustive optimization search.

## Artifact and integration checks

Client revision: `34badae5f242e8e9943eb592e73cbce45597d9b9`.
VIR dependency: `cdba5cac11eb3ee9867b8039c05f66da4e4cfaf5`.
All 30 bundled JavaScript files match the dependency's `web/src` files byte
for byte. All three Bench package members match the local Lean 4.34.0 rebuild.
The shipped release Wasm SHA-256 is
`c0aed82731f2448b1dd1867d322050a3cf99ee5e7e68437efae428356e9eadca`.

| possible source of avoidable cost | finding |
|---|---|
| rebuilding/reloading on every call | [Worker](../site/worker.js) retains one initialization promise and runtime; [Node harness](../bench/medir-node.mjs) and [browser harness](../bench/navegador/bench-core.js) load outside steady-state timers |
| fine-grained JS/Lean crossings | one exported call runs the whole workload |
| repeated SDK name resolution | [`call`](../site/lean-vir/js/runtime/core.js) uses a dictionary; resolved call slots and object call plans are cached |
| interpreting primitive arithmetic in Lean | generated package report lists 19 native externs, including Nat arithmetic, Array operations and Int operations; no missing registrations |
| expensive JavaScript host callbacks | all ten exports are pure; manifest has zero host imports; measured host time is zero |
| JSON fallback for exported values | these calls use the resolved object ABI |
| recreating the underlying interpreter | the pinned shim retains `g_package_interpreter` across calls |
| accidentally selecting a debug build | client requests the release artifact; pinned build recipe defaults to `-O3`, `-DNDEBUG`, Release |

The build defaults describe the pinned recipe, not an independently recovered
compiler command for the distributed binary. All experiments use its exact
bytes. The shim and recipe are under the dependency's
`wasm/upstream_shim/interpreter/persistent_ir_interpreter.cpp` and
`scripts/build-upstream-probe.sh`.

`LEAN_DEFAULT_INTERPRETER_PREFER_NATIVE=false` is a producer build setting,
not a client SDK option. It does not mean that the package's native externs
are absent. Selecting a preference cannot supply compiled implementations of
the client's exported Lean functions. Likewise, common JS host bindings do
not override `Nat.mul`: host bindings implement declared host imports, and
this package declares none. No supported SDK switch for GMP or alternative
big-integer arithmetic was found. Such a replacement requires runtime or
package/boundary work and its own correctness/performance evaluation.

## Phase experiment

[`bench/audit-vir.mjs`](../bench/audit-vir.mjs) retains one runtime, warms each
entry, then checks every result of three `callTimed` calls against the original
independent reference hashes. All 30 measured results pass. The resolved slot
and cached object plan remain stable. Largest reference inputs are used,
except decimal Fibonacci at 100,000; the earlier million-input diagnostic is
already retained in the [research record](RESEARCH-20260928.md).

Node 24.21.0 / V8 13.6.233.17-node.53, Linux x64, Ryzen AI 9 HX 370.
Median milliseconds below are diagnostic phase measurements, not an
uninstrumented backend comparison. Each column is computed independently.

| workload / input | marshal | execute | decode | total |
|---|---:|---:|---:|---:|
| Tunnell / 1,000,003 | 0.043 | 759.689 | 0.164 | 759.926 |
| Collatz / 100,000 | 0.052 | 5,706.600 | 0.089 | 5,706.805 |
| primeCount / 1,000,000 | 0.044 | 1,241.779 | 0.035 | 1,241.940 |
| Mertens / 1,000,000 | 0.054 | 4,398.444 | 0.051 | 4,398.644 |
| partitions / 3,000 | 0.038 | 168.956 | 0.050 | 169.082 |
| fib / 100,000 | 0.063 | 5.451 | 302.724 | 308.301 |
| fibBits / 1,000,000 | 0.039 | 536.980 | 0.034 | 537.106 |
| partitionsBits / 3,000 | 0.043 | 173.817 | 0.033 | 173.942 |
| isPrime / 1,279 bits | 0.093 | 231.619 | 0.022 | 231.799 |
| Life / 100 | 0.048 | 4,193.916 | 0.038 | 4,194.046 |

Execution accounts for more than 99.9% of summed call time for every selected
case except decimal Fibonacci. Nat decoding calls `vir_obj_nat_decimal` in
Wasm through [`readObjectDecimal`](../site/lean-vir/js/runtime/object-values.js).
Thus “decode” includes compiled arithmetic for conversion, not just copying
text in JavaScript. The author's `fibBits` variant already avoids this cost.

## Generated methods versus named calls

We compared `vir.call(entry.entry, arg)` with the documented
`vir.exportsByName[entry.jsName](arg)`. Each campaign uses four AB/BA pairs,
eight timed batches per method/input, one warmup per method and the same
retained runtime. Small inputs use batches of 25; million-input cases use one.
All 1,232 timed return values per campaign pass reference hashes, checked
outside the batch timer. These are ordinary calls without phase clocks.

| workload / input | campaign 1 named / generated ms | campaign 2 named / generated ms |
|---|---:|---:|
| primeCount / 1,000 | 1.0692 / 1.3468 | 0.9377 / 0.9363 |
| primeCount / 1,000,000 | 1,306.726 / 1,266.155 | 1,344.770 / 1,370.249 |
| fibBits / 1,000 | 0.0261 / 0.0243 | 0.0292 / 0.0288 |
| fibBits / 1,000,000 | 438.146 / 437.849 | 483.805 / 489.872 |
| Tunnell / 1,003 | 0.9950 / 0.9979 | 1.0724 / 1.0767 |

The large-input differences change direction between campaigns. Small
Fibonacci shows a sub-microsecond to few-microsecond median difference, but
short batches and outliers limit inference. For example, one repeat-campaign
pair has an 80.78% apparent reduction that is not representative of the other
pairs. No observations were removed. Generated methods are a supported API
choice, but these results do not support a material large-workload speedup.
Background load, CPU affinity and governor were uncontrolled; this is not a
statistical equivalence claim.

## Profiles of the exact release binary

[`bench/profile-vir.mjs`](../bench/profile-vir.mjs) executes the original release
binary and obtains names from a retained debug companion at
`~/lean/vir/build/reviews/pr202-landing/mounted/vir-upstream.dev.wasm`.
Its SHA-256 is
`0d8a696d616bd9edfca45a47ec282f9edaaa094c369a42e0123c29f487ba788b`.
Every non-custom binary section matches the release byte for byte. No
instrumented or rebuilt executable is substituted. All indexed Wasm frames
are matched by function index and code-body byte offset; names are demangled
with `c++filt`.

Separate Node inspector captures request 1,000 µs sampling after one warmup:
three sieve calls and five fibBits calls at 1,000,000. All results pass. The
window includes validation and profiler bookkeeping, excludes initialization,
and is not used for headline timings. Shares use actual `timeDeltas`, assigning
the preceding interval to its ending sample and clipping at profile end.

| sieve symbol, abbreviated | self-time share |
|---|---:|
| interpreter `call` | 31.18% |
| interpreter `eval_body` | 23.03% |
| symbol-cache hash-table `find<lean::name>` | 20.70% |
| interpreter `eval_expr` | 7.15% |
| `lean_name_eq` | 3.98% |
| `box_t` | 2.75% |
| value-vector `resize` | 2.35% |
| interpreter `lookup_symbol` | 2.15% |

The sieve capture has 3,469 samples, 99.31% resolved Wasm self time and 30
resolved body symbols. Wasm leaves attached directly to the root account for
1.23% of sampled time: their ancestry is unavailable, but leaf attribution
remains usable. An unobserved 0.983 ms tail is left unassigned.

The fibBits capture has 2,276 samples and 25 resolved body symbols.
**`lean::mpn_mul` accounts for 98.87% of total sampled self time.** The rest is
mostly profiler bookkeeping; no root-only Wasm leaves were observed, and the
unassigned tail is 0.954 ms. Interpreter frames are also present above this
routine, so inclusive interpreter time must not be described as dispatch
overhead. The sample establishes the multiplication hotspot, not its exact
algorithm or the reason for the full native/Wasm gap.

These profiles support separate upstream investigations: interpreter dispatch
and symbol lookup for the sieve; compiled arithmetic for large Fibonacci;
decimal conversion for large returned Nats. Client-side name lookup is not
the symbol-cache lookup seen inside the sieve profile.

## Reproduction and retained evidence

The [published audit evidence](../bench/results/2026-09-28/vir-audit/) contains
`static.json`, a copied `Bench.report.md`, phase samples, both API comparisons,
and two `profile-*/` directories with summaries and raw CPU profiles. Captured
paths refer to the original machine. Records include hashes, commands, host
versions and load observations. No client build or second client benchmark ran
alongside these campaigns. The complete runtime/debug companions remain local.

Run from the repository root into fresh output directories:

```sh
node bench/audit-vir.mjs phases tests/out/research/fresh-phases
node bench/audit-vir.mjs methods tests/out/research/fresh-methods
node bench/profile-vir.mjs /path/to/matching/vir-upstream.dev.wasm \
  tests/out/research/fresh-profile primeCount 1000000 3
node bench/profile-vir.mjs /path/to/matching/vir-upstream.dev.wasm \
  tests/out/research/fresh-profile-fibbits fibBits 1000000 5
```

The symbol companion is a local retained artifact, not part of this client
repository. The profiler refuses a companion with different executable
sections. The API and phase experiments require no debug companion.
