#!/usr/bin/env python3
"""Render a report's single table from preserved checked observations.

python3 bench/render-report-table.py          # print Markdown
python3 bench/render-report-table.py --check  # verify the table in docs/REPORT.md
"""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "bench/results/2026-09-28/4341/comparison.json"
ENGINES = ["native", "js", "vir", "fir", "cwasm"]
LABELS = {"tunnell": "Tunnell", "collatzRecord": "Collatz", "primeCount": "prime sieve",
          "mertens": "Mertens", "partitions": "partitions", "fib": "fib, decimal",
          "fibBits": "fibBits", "partitionsBits": "partitionsBits",
          "isPrime": "Miller–Rabin", "lifePopulation": "Life"}
START = "<!-- BEGIN BACKEND TABLE -->"
END = "<!-- END BACKEND TABLE -->"


def render(data_path=DATA, inventory_path=None):
    data_path = data_path.resolve()
    inventory_path = (inventory_path or data_path.parents[1] / "files.json").resolve()
    raw = data_path.read_bytes()
    inventory = json.loads(inventory_path.read_text())
    relative = str(data_path.relative_to(inventory_path.parent))
    entry = next(f for f in inventory["files"] if f["path"] == relative)
    assert hashlib.sha256(raw).hexdigest() == entry["sha256"], "evidence digest mismatch"
    data = json.loads(raw)
    assert data["status"] == "passed" and len(data["rows"]) == 50 * len(data["selection"])
    references = (ROOT / "bench/casos.mjs").read_text().split("=", 1)[1].strip().removesuffix(";")
    references = {(c["w"], c["x"]): c["esperado"] for c in json.loads(references)}
    lines = ["| workload / input | Native | JavaScript | VIR | FIR | C/Wasm |",
             "|---|---:|---:|---:|---:|---:|"]
    for w, x in data["selection"].items():
        rows = [r for r in data["rows"] if r["w"] == w and r["x"] == x]
        assert len(rows) == 50
        values = {}
        for engine in ENGINES:
            selected = [r for r in rows if r["engine"] == engine]
            assert sorted(r["round"] for r in selected) == list(range(10))
            assert all(r["valueSha256"] == references[w, x] for r in selected)
            values[engine] = median(r["ms"] for r in selected)
        label = f"{LABELS[w]} / {x:,}" + (" bits" if w == "isPrime" else "")
        cells = []
        for engine in ENGINES:
            value = values[engine]
            time = f"{value:,.3f}" if value >= 1 else f"{value:.4f}"
            ratio = float(f"{values['fir'] / value:.3g}")
            ratio = f"{ratio:,.0f}" if ratio >= 1000 else f"{ratio:g}"
            cells.append(f"{time}<br>({ratio}×)")
        lines.append("| " + label + " | " + " | ".join(cells) + " |")
    return "\n".join(lines)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--data", type=Path, default=DATA)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--report", type=Path, default=ROOT / "docs/REPORT.md")
    args = parser.parse_args()
    table = render(args.data, args.inventory)
    if args.check:
        report = args.report.read_text()
        assert report.count(START) == report.count(END) == 1
        assert report.split(START, 1)[1].split(END, 1)[0].strip() == table, "report table differs from evidence"
        print(f"Report table matches all {len(json.loads(args.data.read_text())['rows'])} checked observations.")
    else:
        print(table)
