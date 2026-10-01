#!/usr/bin/env python3
"""heldout-rate.py — one rater labels the router's sealed held-out set (REPORT.md §10 open item 13;
wave B1 of docs/plans/RESEARCH_PROGRAM_BUILD.md).

  heldout-rate.py --vendor openai|anthropic|frontier|google [--model ID] [--timeout S] [--dry-run]

It reads the sealed set (heldout.py's rater-sheet, never written to disk here), asks ONE vendor CLI
through the courier's own resolution and call path (lib/courier.py `resolve`, `call`: the binary by
absolute path, read-only modes, the responding model id read back), in an empty temporary directory,
to give each prompt one route label, and records the answers with heldout.py's `label` verb under
the rater name `<vendor>:<responding model>`. The route definitions are the classifier's own
(router.py ROUTE_DEFINITIONS), so the gold labels and the router answer the same question.

Two raters of two different vendor FAMILIES are required (heldout.evaluate counts an item only when
two raters agree); this refuses a second rater from a family that already labeled. --dry-run prints
the counts of what would be sent and calls nothing. It never prints a prompt.
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
    a = ap.parse_args(argv)
    try:
        data = heldout.load()
        family = kit.VENDOR_FAMILY[a.vendor]
        prior = sorted({r for i in data["items"] for r in i["labels"]})
        if any(r.split(":", 1)[0] in [v for v, f in kit.VENDOR_FAMILY.items() if f == family] for r in prior):
            raise kit.KitError(
                f"a {family}-family rater already labeled ({', '.join(prior)}); the second rater must be "
                "another vendor family"
            )
        sheet = "".join(json.dumps({"id": i["id"], "prompt": i["prompt"]}) + "\n" for i in data["items"])
        ids = [i["id"] for i in data["items"]]
        if a.dry_run:
            print(f"would send {len(ids)} prompt(s) to {a.vendor}; raters so far: {', '.join(prior) or 'none'}")
            return 0
        binary, how = courier.resolve(a.vendor)
        if not binary:
            raise kit.KitError(f"no {a.vendor} CLI ({how}); run `probe-run.sh doctor`")
        work = Path(tempfile.mkdtemp(prefix="cc-heldout-rate-"))
        try:
            r = courier.call("router-heldout", a.vendor, binary,
                             BRIEF.format(defs=ROUTE_DEFINITIONS, sheet=sheet), a.model, work, a.timeout)
        finally:
            shutil.rmtree(work, ignore_errors=True)
        if r["error"]:
            raise kit.KitError(f"{a.vendor} rater failed: {r['error']}")
        model = (r["model_ids"] or [a.model or "unknown"])[0]
        if a.model and model != a.model:
            raise kit.KitError(f"asked for {a.model}, {model} responded; nothing recorded")
        got = extract(r["reply"], ids)
        if len(got) < len(ids):
            raise kit.KitError(f"{a.vendor} labeled {len(got)} of {len(ids)} prompt(s); nothing recorded")
        rater = f"{a.vendor}:{model}"
        tmp = Path(tempfile.mkstemp(prefix="cc-heldout-labels-")[1])
        try:
            tmp.write_text("".join(json.dumps({"id": k, "label": v}) + "\n" for k, v in got.items()))
            return heldout.main(["label", "--rater", rater, "--labels", str(tmp)])
        finally:
            tmp.unlink()
    except kit.KitError as e:
        print(f"heldout-rate.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
