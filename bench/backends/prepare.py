"""Stage the mathematical sources for FIR without changing the VIR client.

python3 bench/backends/prepare.py /absolute/isolated/fir-worktree [--with-emscripten]
Outputs belong to the producer worktree's ignored .deps directory.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

CLIENT = Path(__file__).resolve().parents[2]
TEMPLATES = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def without_vir(data):
    """Remove only VIR registration, preserving every mathematical definition."""
    text = data.decode()
    marker = "meta import Vir.Attributes\n"
    if text.count(marker) != 1:
        raise ValueError("expected exactly one VIR metadata import")
    text = text.replace(marker, "")
    text, count = re.subn(r"^attribute \[vir_export\][^\n]*(?:\n  [^\n]+)*\n?", "", text, flags=re.M)
    if count != 1:
        raise ValueError("expected exactly one VIR export registration")
    return text.encode()


def prepare(producer, with_emscripten=False):
    producer = producer.resolve(strict=True)
    if git(producer, "status", "--porcelain"):
        raise ValueError("use a clean, frozen FIR producer worktree")
    toolchain = (producer / "lean-toolchain").read_text().strip()
    fir = producer / ".deps/math-browser-fir"
    c = producer / ".deps/math-browser-c"
    roots = [fir, c] if with_emscripten else [fir]
    emscripten = {"status": "deferred-by-user"}
    if with_emscripten:
        pins = (producer / "integration/lcnf-c-wasm/toolchain-pins.sh").read_text()
        if "fir_lcnf_c_parse_lean_identity()" in pins:
            compiler = subprocess.check_output(["elan", "run", toolchain, "lean", "--version"], text=True).strip()
            identity = subprocess.check_output([
                "bash", "-c", 'set -eu; source "$1"; fir_lcnf_c_parse_lean_identity "$2"; '
                'printf "%s\\n%s\\n" "$FIR_LCNF_C_LEAN_VERSION" "$FIR_LCNF_C_LEAN_COMMIT"',
                "identity", str(producer / "integration/lcnf-c-wasm/toolchain-pins.sh"), compiler], text=True)
            runtime_version, runtime_commit = identity.strip().splitlines()
        else:
            runtime_version = re.search(r'FIR_LCNF_C_LEAN_VERSION="([^"]+)"', pins)[1]
            runtime_commit = re.search(r'FIR_LCNF_C_LEAN_COMMIT="([^"]+)"', pins)[1]
        emsdk_version = re.search(r'FIR_LCNF_C_EMSDK_VERSION="([^"]+)"', pins)[1]
        emscripten = {"runtimeLeanVersion": runtime_version, "runtimeLeanCommit": runtime_commit,
                     "emsdkVersion": emsdk_version,
                     "status": "ready-for-runtime-preflight" if toolchain == f"leanprover/lean4:v{runtime_version}" else "blocked-frontend-runtime-mismatch"}
    for root in roots:
        if root.exists():
            raise ValueError(f"staging directory already exists: {root}")
    for root in roots:
        root.mkdir(parents=True, exist_ok=False)
        (root / ".deps/tmp").mkdir(parents=True)
        (root / "lean-toolchain").write_text(toolchain + "\n")
    sources = []
    for name in ["Tunnell.lean", "Bench.lean"]:
        original = (CLIENT / name).read_bytes()
        staged = without_vir(original)
        sources.append({"path": name, "originalSha256": digest(original), "stagedSha256": digest(staged)})
        for root in roots:
            root_source = staged
            if root == c:
                # The default Init import supplies this program's runtime needs.
                # Keep all definitions and kernel checks; compilation verifies closure.
                if staged.count(b"public import Lean\n") != 1:
                    raise ValueError("expected one public Lean import")
                root_source = staged.replace(b"public import Lean\n", b"")
                sources[-1]["cStagedSha256"] = digest(root_source)
            (root / name).write_bytes(root_source)
    (fir / "lakefile.lean").write_text('''import Lake
open Lake DSL
package MathBrowserFir
require Fir from "../.."
lean_lib MathSource where
  roots := #[`Tunnell, `Bench]
''')
    (fir / "Emit.lean").write_bytes((TEMPLATES / "Emit.lean").read_bytes())
    template_names = ["prepare.py", "Emit.lean", "build-fir.sh", "emit-fir.mjs"]
    if with_emscripten:
        (c / "lakefile.lean").write_text("import Lake\nopen Lake DSL\npackage MathBrowserC\nlean_lib MathSource where\n  roots := #[`Tunnell, `Bench, `MathBench]\n")
        for name in ["MathBench.lean", "bridge.c"]:
            (c / name).write_bytes((TEMPLATES / name).read_bytes())
        template_names += ["MathBench.lean", "bridge.c", "build-emscripten.sh"]
    metadata = {
        "schema": "lean-math-backend-preparation/v1",
        "clientCommit": git(CLIENT, "rev-parse", "HEAD"),
        "producerCommit": git(producer, "rev-parse", "HEAD"),
        "producerToolchain": toolchain,
        "clientToolchain": (CLIENT / "lean-toolchain").read_text().strip(),
        "sources": sources,
        "transformation": "Remove meta import Vir.Attributes and attribute [vir_export] commands only; retain all definitions and kernel checks.",
        "cTransformation": "Additionally remove the unnecessary public import Lean; preserve all definitions and kernel checks, using the default Init import." if with_emscripten else None,
        "templates": {name: digest((TEMPLATES / name).read_bytes()) for name in template_names},
        "emscripten": emscripten,
        "qualification": "Prepared sources only; no claim of generated or validated Wasm packages.",
    }
    for root in roots:
        (root / "PREPARATION.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps({"fir": str(fir), "emscripten": str(c) if with_emscripten else None, "preflight": metadata["emscripten"]}, indent=2))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("producer", type=Path)
    parser.add_argument("--with-emscripten", action="store_true")
    args = parser.parse_args()
    prepare(args.producer, args.with_emscripten)
