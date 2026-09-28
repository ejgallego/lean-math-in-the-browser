#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 ]]; then
  echo "usage: bash bench/backends/build-fir.sh /absolute/fir-producer [workload ...]" >&2
  exit 2
fi
producer="$(cd "$1" && pwd)"
client_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shift
project="$producer/.deps/math-browser-fir"
export TMPDIR="$project/.deps/tmp"
cd "$producer"
LAKE_CACHE_DIR="$(bash scripts/fir-lake-cache-path.sh)"
export LAKE_CACHE_DIR
export LAKE_ARTIFACT_CACHE=true LAKE_RESTORE_ARTIFACTS=true
lake build +Fir.Wasm.Emit.ResidentLinker
if [[ $# == 0 ]]; then
  set -- tunnell collatzRecord primeCount mertens partitions fib fibBits partitionsBits isPrime lifePopulation
fi
node "$client_scripts/emit-fir.mjs" "$producer" "$@"
