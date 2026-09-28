# Evidence snapshot, 2026-09-28

These are byte-for-byte copies of the records behind the
[consolidated report](../../../docs/REPORT.md). They travel with the fork;
reading the results does not require the original machine or ignored worktrees.
The 41 captured files total about 1 MiB, excluding this index and README.

- [4.34.1 comparison](4341/comparison.json): all 500 observations, engine orders,
  timing policy, host identity, source/artifact hashes and package metadata.
- [Derived summary](4341/summary.json): medians, selected ratios and min/max
  sample ranges, bound to the comparison by SHA-256.
- [Client checks](4341/client-checks.json), [FIR checks](4341/fir-checks.json),
  [C/Wasm checks](4341/emscripten-checks.json): successful checks and explicit
  timeouts, including inputs larger than those selected for the comparison.
- [Preparation](4341/preparation.json), [FIR manifest](4341/fir-manifest.json),
  [C/Wasm manifest](4341/c-manifest.json): producer identity and build inputs.
- [VIR audit](vir-audit/): phase samples, both API comparisons, matched-symbol
  CPU profiles and their summaries.
- [FIR profile](fir-profile/): phase samples, raw CPU profiles, summaries,
  captured LCNF, function inventory and the two cited FIR source modules
  for the multiplication diagnosis (with their Apache-2.0 licence).
- [Original reproduction](original-reproduction/) and
  [earlier FIR comparison](fir-original/): historical campaigns, kept separate
  from the 4.34.1 comparison.

[files.json](files.json) records each captured file's source location, size and
SHA-256. Paths and command lines inside the records refer to the original
machine and are retained unchanged as provenance. They are not portable paths
to execute from a fresh clone. Executables, runtime libraries, debug-symbol
companions, full producer worktrees and most build logs are not included.
This is a reviewable measurement snapshot, not a self-contained binary release.

From the repository root, verify the published table without running benchmarks:

```sh
python3 bench/render-report-table.py --check
```

For a fresh evaluation, see the [backend recipes](../../backends/README.md).
Never replace this snapshot with samples from another run; preserve a new
campaign in a separate directory.
