# Lean math in the browser: VIR, FIR and compiled Wasm

A follow-up to [Joel Canary's original experiment](REPORT-ORIGINAL.md),
28 September 2026. The original work supplies the mathematical programs,
independent references and browser experiments. This review reproduces its
performance findings, audits the VIR integration and adds FIR and C/Emscripten
comparisons for the author and runtime maintainers.

**Update:** the [subsequent multiplication evaluation](FIR-MULTIPLICATION-20260928.md)
tests FIR's response to the large-integer hotspot below. This initial campaign
is retained as the baseline; the follow-up has fresh timings and backend ratios.

**The reported slowdown is real, and we found no major VIR integration
mistake or unused SDK setting that explains it away.** FIR removes much of
the cost on loops and arrays, but remains behind native Lean and handwritten
JS. The initially evaluated large-integer implementation has substantial regressions.
Compiled Wasm supplies a useful baseline and still has numeric and output
conversion costs of its own.

## Five backends, one comparison

The mathematical definitions are unchanged. Native Lean, regular FIR and the
C/Emscripten build use **Lean 4.34.1**; the newly generated VIR packages run on
the original bundled VIR runtime. That retained runtime version difference is
explicit and all 40 VIR reference inputs pass. All ten regular FIR artifacts
are byte-identical to the earlier rc2 builds.

The measurements below come from **one campaign**, on a Ryzen AI 9 HX 370,
Linux x64, Node 24.21.0 / V8 13.6.233.17-node.53. Ten engine orders balance
positions and within-round predecessor pairs. All **500 measured results**
pass their independent reference hashes. Startup is excluded.

**Each cell is median milliseconds, with FIR's time divided by that column's
time in parentheses.** Above 1 means FIR takes longer; below 1 means FIR is
faster. The ratio direction is the same everywhere. For example, the sieve's
native cell means 9.413 ms natively and FIR taking 3.91× as long. Its VIR cell
means FIR takes 0.0323× VIR's time, or about 31× faster. Ratios use unrounded
medians; FIR's own ratio is always 1.

<!-- BEGIN BACKEND TABLE -->
| workload / input | Native | JavaScript | VIR | FIR | C/Wasm |
|---|---:|---:|---:|---:|---:|
| Tunnell / 1,000,003 | 6.419<br>(1.86×) | 2.211<br>(5.39×) | 794.804<br>(0.015×) | 11.930<br>(1×) | 10.817<br>(1.1×) |
| Collatz / 100,000 | 39.756<br>(2.46×) | 19.310<br>(5.07×) | 5,399.278<br>(0.0181×) | 97.812<br>(1×) | 50.220<br>(1.95×) |
| prime sieve / 1,000,000 | 9.413<br>(3.91×) | 1.917<br>(19.2×) | 1,138.685<br>(0.0323×) | 36.784<br>(1×) | 11.984<br>(3.07×) |
| Mertens / 1,000,000 | 35.077<br>(20.6×) | 25.960<br>(27.8×) | 3,647.482<br>(0.198×) | 722.557<br>(1×) | 47.465<br>(15.2×) |
| partitions / 3,000 | 13.527<br>(1.64×) | 3.767<br>(5.9×) | 135.336<br>(0.164×) | 22.239<br>(1×) | 13.171<br>(1.69×) |
| fib, decimal / 10,000 | 2.926<br>(17.4×) | 0.1139<br>(446×) | 2.673<br>(19×) | 50.835<br>(1×) | 5.569<br>(9.13×) |
| fibBits / 10,000 | 0.0294<br>(1,890×) | 0.0856<br>(649×) | 0.2560<br>(217×) | 55.572<br>(1×) | 0.1229<br>(452×) |
| partitionsBits / 3,000 | 14.426<br>(1.52×) | 3.997<br>(5.47×) | 137.102<br>(0.16×) | 21.884<br>(1×) | 13.385<br>(1.63×) |
| Miller–Rabin / 127 bits | 0.6433<br>(221×) | 0.6176<br>(231×) | 3.271<br>(43.5×) | 142.432<br>(1×) | 1.542<br>(92.4×) |
| Life / 100 | 33.953<br>(1.75×) | 4.365<br>(13.6×) | 3,490.221<br>(0.017×) | 59.367<br>(1×) | 32.100<br>(1.85×) |
<!-- END BACKEND TABLE -->

Here **VIR** is Lean's IR interpreter compiled to Wasm; **FIR** is the regular
FIR-generated Wasm backend; **C/Wasm** is Lean-generated C compiled with
Emscripten through FIR's tooling. **Native** is compiled Lean; **JavaScript**
is the handwritten implementation using typed arrays and BigInt. `fibBits`
and `partitionsBits` return floor(log₂(result)), avoiding a huge decimal output.
The primality input is identified by its bit length; Life uses 100 generations
on the original 64×64 torus.

FIR improves over VIR by about **5–67×** on the selected loop/array workloads:
Tunnell, Collatz, primeCount, Mertens and Life.
Those gains still leave it at **1.7–20.6× native time** and **5.1–27.8× JS time**
on those workloads. Mertens exposes a particularly large remaining gap.
C/Wasm is close to native on several cases; FIR takes about 1.1× its time on
Tunnell, 3.1× on the sieve and 15.2× on Mertens.

Large integers give a different result. At fibBits(10,000), FIR takes about
452× C/Wasm time. Fibonacci and Miller–Rabin regress even relative to VIR.
C/Wasm does not win every case either: decimal fib(10,000) takes 5.57 ms
versus VIR's 2.67 ms. Compiling away interpreter dispatch does not by itself
fix multiplication or decimal conversion.

## Did the client leave an optimization unused?

The [VIR integration audit](VIR-USAGE-AUDIT-20260928.md) found appropriate
usage for these workloads:

- The runtime and packages are retained, with initialization outside steady
  timers. One exported call performs each complete computation.
- Resolved call slots and object marshalling plans are cached; the underlying
  interpreter session is retained. These calls use the object ABI.
- Nat arithmetic, Array operations and Int operations already use compiled
  native externs. The package declares no JavaScript host imports.
- No supported SDK switch supplies compiled client functions or substitutes
  GMP. Adding common host bindings does not override Nat arithmetic.

Two balanced comparisons of named calls against generated SDK methods found
no consistent large-input benefit. Tiny fibBits calls showed sub-microsecond
to few-microsecond median differences. There is no evidence here for a client
API change that would remove the large slowdowns. Source-level representation
or algorithm changes remain possible separate experiments.

## Three costs worth separating

The first local campaign reproduced the broad native/VIR pattern, including
large loop/array slowdowns, without reproducing every original ratio. Its
[historical measurements](RESEARCH-20260928.md#same-machine-results) remain
separate from the table above; hardware, engine versions and measurement
policies differ.

**Interpreter execution.** For the million-input sieve, a profile of the exact
bundled release binary attributes 31.18% self time to interpreter `call`,
23.03% to `eval_body`, 20.70% to symbol-cache lookup and 7.15% to `eval_expr`.
Internal dispatch/evaluation and lookup are concrete runtime targets. This
symbol-cache lookup is distinct from the client's cached SDK name lookup.

**Compiled arithmetic.** For fibBits(1,000,000), **98.87% of sampled self time**
is in compiled `lean::mpn_mul`. Calling the entire difference “interpreter
overhead” would hide the dominant work. Separately, the
[FIR profile](FIR-FIBBITS-PROFILE-20260928.md) finds repeated doubling/addition
in its generic multiplication path, with addition and limb-access helpers
dominating self time. That profile applies to the identical Wasm bytes rebuilt
with 4.34.1. Miller–Rabin has not been separately profiled.

**Output conversion.** Earlier VIR phase medians for decimal F(1,000,000)
were roughly **424 ms executing and 23,943 ms decoding**. Nat decoding invokes
a Wasm decimal-conversion routine, so this includes arithmetic rather than
merely copying text in JS. Native formatting also took about ten seconds in
that campaign. The author's small-result variants already make the right
distinction. If an application needs the decimal digits, that cost remains
part of its workload.

The profiles are diagnostics, not additional timing rows. Symbols were checked
against the measured artifacts. Some sampled caller ancestry is unavailable;
self-time in optimized frames may include inlined work. These findings identify
costs, not a proved speedup for a proposed replacement.

## Coverage and limits

Native, revised JS and rebuilt VIR packages pass all **40 reference inputs**.
Regular FIR qualifies **37/40**, with 30-second per-call timeouts on million-input
fib/fibBits and 1,279-bit primality. C/Wasm qualifies **39/40**; only the huge
decimal Fibonacci result times out. Retained-instance checks include immediate
repeats and forward/reverse input orders. No completed result mismatched.
Timeouts remain unqualified outcomes, not estimated runtimes. The table keeps
the same selected inputs as the earlier FIR campaign; the larger timeouts
are disclosed rather than silently omitted.

JS and Wasm use retained instances with one explicit warmup. Each native
sample is the second in-process call in a fresh process, with process startup
excluded. FIR includes its diagnostic adapter and heap rewind; VIR includes
SDK decoding; C/Wasm includes argument parsing, computation/formatting, text
copying and release. Native and JS include result formatting. These boundaries
are similar but not identical. The C/Wasm runtime uses `USE_GMP=OFF`.

Background load, CPU affinity, frequency and thermal state were uncontrolled.
JS representations and arithmetic libraries differ from Lean's. Ratios compare
implementations, not a universal interpreter penalty. The new experiments are
**Node-only**: the original browser/Worker, cold-start, throttling and frame-gap
claims have not been rerun, and the new adapters are not browser-qualified.

Two methodology corrections belong with the results. The original harnesses
checked Node/browser warmup values and the native final value, rather than
every timed repetition as the original report states. The new comparison
checks every measured result. Also, original JS `partitionsBits` converted to
decimal and back; the separate revised baseline retains the BigInt internally
and passes every reference case. Original programs, baseline and report are
preserved. These corrections do not discount the original performance finding.

## Evidence, reproduction and next work

The [checked-in evidence snapshot](../bench/results/2026-09-28/README.md)
contains raw samples, correctness outcomes, profiles and artifact identities.
The table is generated from the 500 observations, not transcribed by hand:

```sh
python3 bench/render-report-table.py --check
```

The [4.34.1 methodology](EVALUATION-4341-20260928.md) documents exact builds,
qualification and timing boundaries. [Backend recipes](../bench/backends/README.md)
explain how to run a new campaign. Binaries, full runtime trees and debug
companions are not shipped with the evidence; paths inside captured records
refer to the original machine.

The next application-facing step is browser/Worker qualification. Runtime
work can independently target interpreter dispatch/lookup, FIR multiplication
and decimal conversion. Evaluate changes against frozen packages with fresh
correctness checks and balanced timings; the existing evidence does not yet
establish their prospective speedups.
