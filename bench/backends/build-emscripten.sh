#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 1 ]]; then
  echo "usage: bash bench/backends/build-emscripten.sh /absolute/fir-producer" >&2
  exit 2
fi
producer="$(cd "$1" && pwd)"
source "$producer/integration/lcnf-c-wasm/toolchain-pins.sh"
actual="$(cat "$producer/lean-toolchain")"
if declare -F fir_lcnf_c_parse_lean_identity >/dev/null; then
  fir_lcnf_c_parse_lean_identity "$(elan run "$actual" lean --version)"
fi
expected="leanprover/lean4:v$FIR_LCNF_C_LEAN_VERSION"
if [[ "$actual" != "$expected" ]]; then
  echo "Blocked: FIR frontend is $actual; its Emscripten runtime pins $expected ($FIR_LCNF_C_LEAN_COMMIT)." >&2
  echo "Use an accepted producer with matching frontend/runtime pins; this script does not override them." >&2
  exit 2
fi
project="$producer/.deps/math-browser-c"
export TMPDIR="$project/.deps/tmp"
python3 - "$producer" "$project" <<'PY'
import hashlib, json, pathlib, subprocess, sys
producer, project = map(pathlib.Path, sys.argv[1:])
metadata = json.loads((project / 'PREPARATION.json').read_text())
git = lambda *args: subprocess.check_output(['git', '-C', str(producer), *args], text=True).strip()
assert not git('status', '--porcelain'), 'producer must remain clean'
assert git('rev-parse', 'HEAD') == metadata['producerCommit'], 'producer changed'
for source in metadata['sources']:
    actual = hashlib.sha256((project / source['path']).read_bytes()).hexdigest()
    assert actual == source.get('cStagedSha256', source['stagedSha256']), source['path']
PY
cd "$producer"
LAKE_CACHE_DIR="$(bash scripts/fir-lake-cache-path.sh)"
export LAKE_CACHE_DIR
export LAKE_ARTIFACT_CACHE=true LAKE_RESTORE_ARTIFACTS=true
lake -d "$project" build +MathBench:c
export LEAN_PATH="$(lake -d "$project" env printenv LEAN_PATH)"
bash integration/lcnf-c-wasm/build-emscripten.sh \
  --runtime-profile unthreaded --root "$project" \
  --out-dir "$project/_build/package" --name math-browser \
  --extra-c-source "$project/.lake/build/ir/Tunnell.c" \
  --extra-c-source "$project/.lake/build/ir/Bench.c" \
  --extra-c-source "$project/bridge.c" --heap-view \
  --export fir_math_input_alloc --export fir_math_run \
  --export fir_math_result_ptr --export fir_math_result_len \
  --export fir_math_release "$project/MathBench.lean"
