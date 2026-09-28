# FIR multiplication evaluation evidence

This snapshot supports the [multiplication follow-up](../../../docs/FIR-MULTIPLICATION-20260928.md).
It contains 28 captured files, about 500 KiB, plus this index and `files.json`.

- [paired.json](paired.json): 220 checked old/new observations, with ten AB/BA rounds per input.
- [comparison.json](comparison.json): 500 fresh observations across five backends.
- [fir-checks.json](fir-checks.json): 39 qualified inputs; 1,279-bit primality remains timed out.
- [summary.json](summary.json): derived medians, ranges and ratios bound to both campaigns by SHA-256.
- [identity-audit.json](identity-audit.json): clean exact producer commits, matching compiler and capture settings, checker and loader identities.
- [fir-manifest.json](fir-manifest.json), [preparation.json](preparation.json), and `artifacts/`: package and source identities, plus fibBits descriptor, LCNF and function inventory.
- `new-*-phases/` and `new-100k-sample/`: separate diagnostic timing and the raw CPU profile with its checked symbol summary.
- `source/`: evaluated resident multiplication implementation and licence.

[files.json](files.json) records source paths, byte counts and SHA-256 digests.
Source paths in these byte-for-byte copies refer to the original machine; they
are provenance, not portable execution paths. Binaries and full producer trees
remain local. The old packages and qualification records remain in the
[initial snapshot](../2026-09-28/README.md); none were replaced.

Verify the table without running benchmarks:

```sh
python3 bench/render-report-table.py --check \
  --data bench/results/2026-09-28-fir-mul/comparison.json \
  --inventory bench/results/2026-09-28-fir-mul/files.json \
  --report docs/FIR-MULTIPLICATION-20260928.md
```
