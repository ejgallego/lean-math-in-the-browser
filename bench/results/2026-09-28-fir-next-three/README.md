# Next three FIR profiles: evidence

This snapshot supports the [prime-count, Collatz and Life report](../../../docs/FIR-NEXT-THREE-PROFILES-20260928.md).
Each workload has a headline and smaller reference size. Every size has an
unprofiled phase run and a separate CPU sample run; all 12 runs passed result
hash and warm-arena-rewind checks.

| Workload | Headline phase/sample | Smaller phase/sample |
|---|---|---|
| Prime count | `prime1m-*` (12/70 calls) | `prime100k-*` (12/100) |
| Collatz record | `collatz100k-*` (10/20) | `collatz10k-*` (10/30) |
| Life population | `life100-*` (12/30) | `life30-*` (12/50) |

Each `*-sample` directory contains `run.json`, the raw `cpu.cpuprofile`, and
the exact-symbol `summary-final.json`. `artifacts/` holds each workload's
descriptor, function inventory, emitted LCNF and build identity. `source/`
holds exact producer copies of the array, scalar-boxing and release emitters.
[inventory.json](inventory.json) records SHA-256 hashes for 39 captured files
and seven source identities. The [manifest](../2026-09-28-fir-mul/fir-manifest.json)
and original Wasm hashes are retained in the prior multiplication snapshot;
no binary or complete build tree is copied here.

The inventory's `files` paths are relative to this directory. `sources` paths
are relative to the client checkout at capture time. Paths within raw runs
refer to the original machine and serve as provenance rather than portable
reproduction paths. Run commands for each size are recorded in those files;
the report gives a bounded serial reproduction example.
