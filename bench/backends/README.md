# FIR backend preparation

The active experiment now builds regular FIR and C/Emscripten packages on
Lean 4.34.1. The original rc2 evaluation is preserved separately. The current
isolated producer is `.deps/fir-producer-4341`, based on upstream `a09c113d1`
with only its Lean pin changed, at local commit `4ae9445c3`.

Preparation with `--with-emscripten` uses the producer's selected-compiler
identity API. The C staging also removes the unnecessary `public import Lean`
from source copies; all mathematical definitions and kernel checks remain.
The facade uses Lean's module system. Both changes avoid compiler-library
initializers without replacing them with stubs. The original client and
regular FIR source imports remain unchanged.

```sh
python3 bench/backends/prepare.py /absolute/frozen-fir-worktree --with-emscripten
bash bench/backends/build-fir.sh /absolute/frozen-fir-worktree
# Requires that producer's matching unthreaded Emscripten runtime setup.
bash bench/backends/build-emscripten.sh /absolute/frozen-fir-worktree
node bench/backends/check-emscripten-suite.mjs PRODUCER C_MANIFEST C_CHECKS
node bench/backends/check-client.mjs FRESH_CLIENT_CHECKS
node bench/backends/compare-all.mjs FIR_MANIFEST FIR_CHECKS C_MANIFEST C_CHECKS FRESH_OUTPUT
```

`emscripten-client.mjs` uses FIR's digest-verifying loader, copies UTF-8 results
before release and reacquires the heap view after calls that may grow memory.
Its checker exercises every input in forward/reverse order with immediate
repeats, in a terminable worker. The default per-call limit is 30 seconds.
Timed-out cases remain explicitly unqualified. `compare-all.mjs` uses the same
ten selected inputs as the earlier FIR comparison and ten orders balancing
engine position and within-round predecessor pairs. All measured results are
checked. It uses newly built VIR packages with the original bundled VIR Wasm,
and `js-baseline-revised.mjs` removes the partitionsBits decimal round trip.
It leaves the original JS baseline and deployed packages intact.

## Original regular FIR evaluation

Use a clean, isolated FIR worktree. Preparation defaults to FIR alone and
refuses an existing staging directory:

```sh
python3 bench/backends/prepare.py /absolute/fir-worktree
bash bench/backends/build-fir.sh /absolute/fir-worktree
node bench/backends/check-fir-suite.mjs /path/to/campaign/manifest.json /fresh/checks.json
node bench/backends/compare-fir.mjs /path/to/campaign/manifest.json /path/to/checks.json /fresh/comparison.json
```

`build-fir.sh` prints a campaign manifest and accepts optional workload names.
It builds ordinary Lean interfaces, then uses FIR's existing
`compileEntriesFinalCapturedInternalized` API for each original Bench entry.
This captures final LCNF, internalizes its source dependencies and links the
resident runtime. All ten entries build with **zero Wasm imports** at producer
`14be5c08bca91177fe033d13001a6bafeca22c19`. Outputs are 11.7–25.5 kB each.
These are local raw candidates, not released browser packages.

Preparation removes only `meta import Vir.Attributes` and the `[vir_export]`
registrations from copies of `Tunnell.lean` and `Bench.lean`. Mathematical
bodies, module boundaries and kernel checks remain intact. Original and staged
hashes are in `PREPARATION.json`. Builds require the same clean producer commit
and unchanged staged mathematical sources. Each attempt records actual emitter
and harness hashes, compiler identity, logs, base Wasm, linked Wasm, descriptor,
LCNF and function inventory. No compiled client artifacts cross Lean versions.

The Node adapter in `fir-client.mjs` uses the frozen producer's diagnostic
`ConcreteHost` for input/output marshalling; Wasm itself imports nothing.
It copies results before `fir_heap_rewind`, accepts the producer's monotonic
cache floor, and synchronizes the host allocation cursor after rewind. The
physical decoders are specific to this captured ABI, not a stable SDK.

The suite checks all reference cases in increasing and decreasing order, each
with an immediate repeat. Every result is hash-checked against the independent
Python-generated cases, repeats are compared structurally, and warm calls must
return to their allocation checkpoint. Calls run in terminable Node workers;
`FIR_CHECK_TIMEOUT_MS` defaults to 30000. A timeout records an unqualified case,
restarts the instance, and allows remaining inputs to run. Inspect report
`status`: `incomplete` is not a full qualification pass. The first campaign
qualified 37/40 inputs (148 successful calls); fib/fibBits at one million and
1,279-bit isPrime timed out. No completed result mismatched.

`compare-fir.mjs` selects the largest qualified case per workload whose
screening samples are all below one second. It rotates through all six engine
orders, preserves raw samples, and checks each measured result outside the
timer. FIR includes diagnostic marshalling and arena rewind; native includes
Lean decimal formatting; VIR includes SDK decoding. Startup is excluded.
FIR uses Lean 4.34.0-rc2 while native/VIR use 4.34.0. These are exploratory Node
measurements, not a same-toolchain compiler comparison or browser qualification.

For frozen-package phase timing and sampled attribution, use `profile-fir.mjs`
and `summarize-fir-profile.mjs`. The [fibBits profile report](../../docs/FIR-FIBBITS-PROFILE-20260928.md)
contains bounded reproduction commands, exact symbol-resolution checks and
the multiplication/addition hotspot findings. These diagnostics do not rebuild
or modify the packages.

The original module-wise replay issue is preserved as a diagnostic path:

```sh
FIR_MATH_SOURCE_VIEW=postponed FIR_MATH_CAPTURE=module \
  bash bench/backends/build-fir.sh /absolute/fir-worktree primeCount fibBits
```

Both entries fail at `Tunnell.isqrt` because Bench replay lacks its imported
LCNF signature. Synthetic-unit capture over postponed interfaces also lacks
signatures (`Bench.countTrue` / `Bench.fib`). Ordinary interfaces plus unit
capture work without producer edits or source flattening. The module-aware
API may still deserve a producer-level fix for multi-module postponed inputs.

The earlier direct Tunnell artifact uses module capture and passes all Verdict
fields against VIR for n=1..400, plus counts/flags against Python. Its dedicated
`check-fir-tunnell.mjs` supports that artifact and the ordinary-interface
Bench.tunnell package, which also passes 400 full-Verdict comparisons on a
retained instance. The Nat-only checker
is a small-case diagnostic; use the full suite for broader qualification.

## Earlier C/Emscripten preparation (historical blocker)

The original frozen producer at `14be5c08b` could not build the C baseline.
The following describes that historical attempt; the 4.34.1 path above resolves
the version and initializer issues.

The C project prepares a `UInt32 × Nat → String` facade and a sequential C
bridge. Workload IDs follow `MathBench.lean`; results match `Main.workload`.
The bridge accepts canonical decimal Nat input, transfers its ownership to
Lean, retains the returned String until release, and exposes its UTF-8 bytes.
The adapter must copy output before release and reacquire `HEAPU8`
after calls that may grow memory. Compilation/initialization and input/result
conversion must be timed separately from computation. This facade includes
decimal formatting; `fibBits` and `partitionsBits` format only the small log2
result. It is not an unformatted big-integer API.

The Emscripten recipe uses the producer's existing verified module builder,
unthreaded runtime profile, and exact runtime/frontend pin checks. It never
overrides the producer toolchain. FIR main at `14be5c08b` has frontend
`v4.34.0-rc2`, while its Emscripten runtime pin remains `4.33.0` at
`d8b18978322de05a8f3dba51ef03cf5461676c17`; the preflight therefore stops before
compilation. A matching accepted producer/runtime is needed before this
recipe can produce a qualified package. The original client is on `v4.34.0`,
so even the symbolic FIR candidate has an explicit toolchain difference.

The generated C also retains `initialize_Lean` / `runtime_initialize_Lean`
calls from the original public Lean imports. The generic builder currently
links only the runtime, Init and Std archives. Resolve this library/import
boundary explicitly after pin alignment; the recipe has not passed a Wasm
link and does not replace these initializers with stubs.

FIR's `setup-emscripten.sh` selects `USE_GMP=OFF`. Compiling via C/Emscripten
may remove interpreter costs, but this profile does not by itself give the
browser the native executable's GMP arithmetic implementation.
