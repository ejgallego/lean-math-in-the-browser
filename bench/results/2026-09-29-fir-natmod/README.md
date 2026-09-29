# Frozen FIR natural-remainder candidate evidence

This snapshot supports the [29 September FIR update](../../../docs/FIR-UPDATE-20260929.md).
It compares the isolated FIR `faee469e5` remainder candidate with the
[pre-negation multiplication baseline](../2026-09-28-fir-mul/README.md).

- [paired.json](paired.json): 240 checked old/new timings, including 61- and 127-bit primality and full-suite controls.
- [comparison-isprime.json](comparison-isprime.json) and [comparison-mertens.json](comparison-mertens.json): separate 50-result five-backend campaigns.
- [fir-checks.json](fir-checks.json): all 40 inputs qualified in this run; 1,279-bit primality finished only narrowly below the 30-second limit.
- [identity-audit.json](identity-audit.json): the clean exact-commit rebuild is byte-identical to FIR root's frozen package for all ten Wasm artifacts. The original [root manifest](root-frozen-manifest.json) and local [rebuilt manifest](fir-manifest.json) are both retained.
- `prime61-*`, `prime127-*`, and `mertens1m-*`: independent phase runs, raw Node CPU profiles, and summaries validated against exact Wasm function offsets.
- `artifacts/` and `source/`: descriptors, emitted LCNF, function inventories, build identities and the evaluated resident arithmetic source. The producer licence is preserved in the [earlier snapshot](../2026-09-28-fir-mul/source/LICENSE).

[summary.json](summary.json) derives medians from the raw runs. [files.json](files.json)
records byte counts, original capture paths and SHA-256 digests. Captured JSON
contains machine-specific paths for provenance; binaries and producer trees
remain local. Sampling percentages are attribution, not speedup estimates.
