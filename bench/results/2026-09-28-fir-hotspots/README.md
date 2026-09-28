# Remaining FIR hotspots: evidence

This snapshot supports the [primality and Mertens profile report](../../../docs/FIR-REMAINING-HOTSPOTS-20260928.md).
Four workloads/sizes each have an unprofiled phase run and a separate CPU
profile. All eight runs validate results and warm arena rewinds.

- `prime61-*`, `prime127-*`: 61-bit and 127-bit Miller–Rabin inputs.
- `mertens100k-*`, `mertens1m-*`: Mertens at 100,000 and 1,000,000.
- Each sample directory contains the run, raw CPU profile and exact-symbol summary.
- `artifacts/` contains the two workloads' LCNF, descriptors and function inventories.
- [inventory.json](inventory.json) records 22 captured files and nine source identities.

The frozen [manifest](../2026-09-28-fir-mul/fir-manifest.json) and build identities
are preserved in the multiplication snapshot. The cited
[Nat arithmetic](../2026-09-28-fir-mul/source/ResidentNatArithmetic.lean) and
[big numeric source](../2026-09-28/fir-profile/source/ResidentBigNumeric.lean)
already have byte-identical copies in prior snapshots; their hashes match this
inventory. No producer binaries or full build tree are included.

`files` paths in the inventory are relative to this directory; `sources` paths
are relative to the client checkout at capture time. Paths within raw runs
refer to the original machine. They are retained as provenance, not portable
reproduction paths. See the report for serial, bounded reproduction commands.
