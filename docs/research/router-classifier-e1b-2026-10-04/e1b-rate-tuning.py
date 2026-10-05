#!/usr/bin/env python3
"""One rater labels the router TUNING set (never the sealed set), with heldout-rate.py's own brief,
courier path and route definitions. Writes {idx, label} rows to --out."""
import json, shutil, sys, tempfile
from pathlib import Path
KIT = Path(str(__import__("pathlib").Path(__file__).resolve().parents[3] / "scripts/research-kit"))
sys.path.insert(0, str(KIT / "lib")); sys.path.insert(0, str(KIT))
import courier, importlib.util
spec = importlib.util.spec_from_file_location("hr", KIT / "heldout-rate.py"); hr = importlib.util.module_from_spec(spec); spec.loader.exec_module(hr)
vendor, out = sys.argv[1], Path(sys.argv[2])
rows = [json.loads(l) for l in open(Path.home() / ".claude/autonomy/research/router-heldout/tuning.jsonl")]
ids = [f"t{i:03d}" for i in range(len(rows))]
sheet = "".join(json.dumps({"id": k, "prompt": r["prompt"]}) + "\n" for k, r in zip(ids, rows))
binary, how = courier.resolve(vendor)
work = Path(tempfile.mkdtemp(prefix="cc-tuning-rate-"))
try:
    r = courier.call("router-tuning", vendor, binary, hr.BRIEF.format(defs=hr.ROUTE_DEFINITIONS, sheet=sheet), None, work, 1800)
finally:
    shutil.rmtree(work, ignore_errors=True)
if r["error"]:
    sys.exit(f"{vendor}: {r['error']}")
got = hr.extract(r["reply"], ids)
model = (r["model_ids"] or ["unknown"])[0]
out.write_text("".join(json.dumps({"id": k, "label": got[k], "rater": f"{vendor}:{model}"}) + "\n" for k in ids if k in got))
print(f"{vendor}:{model} labeled {len(got)}/{len(ids)} wall {r['wall_s']}")
