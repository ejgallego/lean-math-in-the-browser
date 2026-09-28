# FIR small-integer negation evidence

This snapshot supports the [small-negation follow-up](../../../docs/FIR-INT-NEG-20260928.md).
The old producer, qualification and packages are retained in the
[multiplication snapshot](../2026-09-28-fir-mul/README.md).

- [paired.json](paired.json): 40 checked old/new observations at Mertens 100,000 and 1,000,000.
- [comparison.json](comparison.json): 50 checked observations across five backends at Mertens 1,000,000.
- [fir-checks.json](fir-checks.json): 39 qualified inputs; 1,279-bit primality timed out.
- [summary.json](summary.json): derived medians and phase timings.
- [identity-audit.json](identity-audit.json): clean producer commits, matching compiler, capture, checker and host identities; nine unchanged Wasm packages.
- [fir-manifest.json](fir-manifest.json), [preparation.json](preparation.json), and `artifacts/mertens/`: new package identity, descriptor, LCNF and function inventory.
- `intneg-mertens*-phases/` and `intneg-mertens*-sample/`: separate phase clocks and raw CPU profiles with exact-symbol summaries.
- `source/`: evaluated resident numeric implementation and its licence.

[files.json](files.json) gives byte counts and SHA-256 digests. The captured JSON
contains original absolute paths for provenance; those paths are not portable.
Compiled binaries and full producer trees remain local. Verify the published
table from this snapshot with:

```sh
python3 bench/render-report-table.py --check \
  --data bench/results/2026-09-28-fir-intneg/comparison.json \
  --inventory bench/results/2026-09-28-fir-intneg/files.json \
  --report docs/FIR-INT-NEG-20260928.md
```
