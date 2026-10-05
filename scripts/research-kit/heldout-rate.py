#!/usr/bin/env python3
"""heldout-rate.py — one rater labels the router's sealed held-out set (REPORT.md §10 open item 13;
wave B1 of docs/plans/RESEARCH_PROGRAM_BUILD.md).

  heldout-rate.py --vendor openai|anthropic|frontier|google [--set v1|v2] [--batch N] [--model ID]
                  [--timeout S] [--dry-run]

It reads the sealed set (heldout.py's rater-sheet, never written to disk here), asks ONE vendor CLI
through the courier's own resolution and call path (lib/courier.py `resolve`, `call`: the binary by
absolute path, read-only modes, the responding model id read back), in an empty temporary directory,
to give each prompt one route label, and records the answers with heldout.py's `label` verb under
the rater name `<vendor>:<responding model>`. The route definitions are the classifier's own
(router.py ROUTE_DEFINITIONS), so the gold labels and the router answer the same question.

Two raters of two different vendor FAMILIES are required (heldout.evaluate counts an item only when
two raters agree); this refuses a second rater from a family that already labeled. --dry-run prints
the counts of what would be sent and calls nothing. It never prints a prompt.

--set names the sealed set (default: the newest one, as heldout.py reads it). --batch N sends the sheet
N prompts per call, same brief each time, because one reply cannot carry several hundred labels;
a batch whose reply skips a prompt is asked again once, and nothing is recorded unless every batch
came back whole and from one model.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "lib"))
sys.path.insert(0, str(HERE))
import courier  # noqa: E402
import heldout  # noqa: E402
import kit  # noqa: E402
from router import ROUTE_DEFINITIONS  # noqa: E402

BRIEF = """You are labeling operator prompts for a router test. For EACH prompt below, choose exactly one
label from this list:
{defs}

Return ONLY JSON lines, one per prompt, in the input order, each exactly {{"id": "<id>", "label": "<label>"}}.
No commentary, no code fence.

PROMPTS (JSON lines, id and prompt):
{sheet}
"""


def extract(reply: str, ids: List[str]) -> Dict[str, str]:
    got: Dict[str, str] = {}
    for m in re.finditer(r"\{[^{}]*\}", reply or ""):
        try:
            d = json.loads(m.group(0))
        except ValueError:
            continue
        if isinstance(d, dict) and d.get("id") in ids and d.get("label") in heldout.ROUTES:
            got.setdefault(d["id"], d["label"])
    return got


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="heldout-rate.py")
    ap.add_argument("--vendor", required=True, choices=kit.VENDORS)
    ap.add_argument("--model")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--set", choices=heldout.SETS)
    ap.add_argument("--batch", type=int, default=0, help="prompts per call; 0 sends one sheet")
    a = ap.parse_args(argv)
    try:
        name = a.set or heldout.current_set()
        data = heldout.load(name)
        family = kit.VENDOR_FAMILY[a.vendor]
        prior = sorted({r for i in data["items"] for r in i["labels"]})
        if any(r.split(":", 1)[0] in [v for v, f in kit.VENDOR_FAMILY.items() if f == family] for r in prior):
            raise kit.KitError(
                f"a {family}-family rater already labeled ({', '.join(prior)}); the second rater must be "
                "another vendor family"
            )
        ids = [i["id"] for i in data["items"]]
        step = a.batch if a.batch > 0 else max(len(ids), 1)
        batches = [data["items"][n:n + step] for n in range(0, len(ids), step)]
        if a.dry_run:
            print(f"would send {len(ids)} prompt(s) of set {name} to {a.vendor} in {len(batches)} call(s); "
                  f"raters so far: {', '.join(prior) or 'none'}")
            return 0
        binary, how = courier.resolve(a.vendor)
        if not binary:
            raise kit.KitError(f"no {a.vendor} CLI ({how}); run `probe-run.sh doctor`")
        got: Dict[str, str] = {}
        models = set()
        for batch in batches:
            sheet = "".join(json.dumps({"id": i["id"], "prompt": i["prompt"]}) + "\n" for i in batch)
            want = [i["id"] for i in batch]
            # A reply that skips a prompt is asked again once, whole and with the same brief; a
            # batch's labels are taken from one reply, never pieced together from two.
            for attempt in (1, 2):
                work = Path(tempfile.mkdtemp(prefix="cc-heldout-rate-"))
                try:
                    r = courier.call("router-heldout", a.vendor, binary,
                                     BRIEF.format(defs=ROUTE_DEFINITIONS, sheet=sheet), a.model, work, a.timeout)
                finally:
                    shutil.rmtree(work, ignore_errors=True)
                if r["error"]:
                    raise kit.KitError(f"{a.vendor} rater failed: {r['error']}; nothing recorded")
                models.add((r["model_ids"] or [a.model or "unknown"])[0])
                part = extract(r["reply"], want)
                if len(part) == len(want) or attempt == 2:
                    got.update(part)
                    break
        if len(models) > 1:
            raise kit.KitError(f"{len(models)} models answered ({', '.join(sorted(models))}); nothing recorded")
        model = next(iter(models))
        if a.model and model != a.model:
            raise kit.KitError(f"asked for {a.model}, {model} responded; nothing recorded")
        if len(got) < len(ids):
            raise kit.KitError(f"{a.vendor} labeled {len(got)} of {len(ids)} prompt(s); nothing recorded")
        rater = f"{a.vendor}:{model}"
        tmp = Path(tempfile.mkstemp(prefix="cc-heldout-labels-")[1])
        try:
            tmp.write_text("".join(json.dumps({"id": k, "label": v}) + "\n" for k, v in got.items()))
            return heldout.main(["--set", name, "label", "--rater", rater, "--labels", str(tmp)])
        finally:
            tmp.unlink()
    except kit.KitError as e:
        print(f"heldout-rate.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
