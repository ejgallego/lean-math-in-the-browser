# FIR current-main rebenchmark evidence

This snapshot supports the [29 September FIR update](../../../docs/FIR-UPDATE-20260929.md).
Current FIR main is `94de4678b` on Lean 4.34.1. The earlier accepted
[small-negation snapshot](../2026-09-28-fir-intneg/README.md) is the matched
baseline; the separate [remainder candidate snapshot](../2026-09-29-fir-natmod/README.md)
keeps its attribution independent.

- [comparison.json](comparison.json): the lower-load 500-result five-backend campaign used for the report's single table. [comparison-high-load.json](comparison-high-load.json) retains the first complete 500-result campaign for sensitivity assessment.
- [paired.json](paired.json): 240 checked full-suite old/new results, including 61- and 127-bit primality. [paired-isprime.json](paired-isprime.json) and [paired-mertens.json](paired-mertens.json) are lower-load focused repeats.
- [paired-vs-natmod-isprime.json](paired-vs-natmod-isprime.json) and [paired-vs-natmod-mertens.json](paired-vs-natmod-mertens.json): direct matched comparisons with the frozen isolated remainder package.
- `paired-collatzRecord.json`, `paired-primeCount.json`, `paired-lifePopulation.json`, and `paired-life-repeat.json`: lower-load control checks. Life's repeated slowdown is accompanied by a [deterministic Wasm body audit](life-body-audit.json).
- [fir-checks.json](fir-checks.json): 39/40 qualified inputs; 1,279-bit primality exceeded 30 seconds.
- [identity-audit.json](identity-audit.json), [fir-manifest.json](fir-manifest.json), [preparation.json](preparation.json), `artifacts/`, and `source/`: exact producer, staged-source, host and package evidence. The producer licence is preserved in the [earlier snapshot](../2026-09-28-fir-mul/source/LICENSE).
- `prime61-*`, `prime127-*`, `mertens1m-*`, and `life100-*`: separate phase runs, raw Node CPU profiles, and summaries with exact Wasm symbol/offset checks.

[summary.json](summary.json) derives medians from raw observations. [files.json](files.json)
records byte counts, original capture paths and SHA-256 digests. Captured paths
are machine-specific provenance; compiled binaries and producer trees remain
local. Recheck the published table without benchmarking:

```sh
python3 bench/render-report-table.py --check \
  --data bench/results/2026-09-29-fir-main/comparison.json \
  --inventory bench/results/2026-09-29-fir-main/files.json \
  --report docs/FIR-UPDATE-20260929.md
```
