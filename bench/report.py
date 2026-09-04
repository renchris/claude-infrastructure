#!/usr/bin/env python3
"""Render one run's findings under one app's profile — the harness's actual output.

§8: a plain CLI that writes a JSON findings file and an annotated image the agent
can `Read`, not an MCP server. An MCP tool CAN return image content, but image
data is charged against `MAX_MCP_OUTPUT_TOKENS` and the `maxResultSizeChars`
escape hatch explicitly has no effect on tools returning images — so an MCP image
tool has exactly one lever, a session-global env var. A CLI chooses its own
output resolution and stays inside the Read ladder by construction.

This is where the per-app weighting becomes visible. The same corpus, the same
findings, three different reports: a family EXCLUDED on the landing app is absent
with its reason stated, a family ABSTAINED on the management app is present as an
open question rather than a verdict, and the order differs because consequence
differs. Nothing here re-measures anything, and nothing here produces a score.

Usage: python3 report.py <corpus-dir> [--app <profile>] [--page <name>]
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib

import profiles

SEV = {"high": "!!", "medium": " !", "low": "  "}


def main(corpus: pathlib.Path, app: str, only: str | None) -> None:
    profile = profiles.get(app)
    layers = {}
    for name in ("findings_dom.json", "findings_xcheck.json"):
        f = corpus / name
        if f.exists():
            for page, fs in json.loads(f.read_text()).items():
                layers.setdefault(page, []).extend(fs)
    plan_f = corpus / "route-plan.json"
    plan = json.loads(plan_f.read_text()) if plan_f.exists() else {"pages": {}}
    # A plan built under another app's lens describes another app's decisions.
    # Reading it anyway would attribute the management profile's abstentions to
    # the landing profile's report, silently and plausibly -- the exact shape of
    # error this whole substrate is written against. Cheaper to notice: the plan
    # already records the app it was built for.
    if plan.get("pages") and plan.get("app") != app:
        print(
            f"  ⚠️  route-plan.json was built for {plan.get('app')!r}, not {app!r}; "
            f"its queue is not this profile's. Re-run: python3 route.py {corpus} "
            f"--app {app}"
        )
        plan = {"pages": {}}

    control = {(f["rule"], f["target"]) for f in layers.get("clean", [])}
    out = {"app": app, "intent": profile["intent"], "pages": {}}

    print(f"REVIEW  {app} [{profile['intent']}]")
    print(f"  {profile['why']}")
    for fam, (state, reason) in profile["admit"].items():
        print(f"  {state.upper():8} family {fam}: {reason[:120]}")
    tm = profile["token_map"]
    print(
        f"  token map: {tm['state']}" + (f" — {tm['note']}" if tm.get("note") else "")
    )
    print()

    for page in sorted(layers):
        if only and page != only:
            continue
        ranked = profiles.apply(profile, layers[page])
        # Subtract the control, always. A finding that also appears on a page with
        # no defect is a property of the rule, not of this page.
        ranked = [
            f
            for f in ranked
            if (f["rule"], f["target"]) not in control or page == "clean"
        ]
        asserted = [f for f in ranked if f.get("verdict", "FAIL") == "FAIL"]
        open_q = [f for f in ranked if f.get("verdict") == "INDETERMINATE"]
        jobs = plan.get("pages", {}).get(page, [])
        out["pages"][page] = {
            "asserted": asserted,
            "open": open_q,
            "vision_jobs": len(jobs),
        }
        if not (asserted or open_q):
            continue
        print(f"{page}")
        for f in asserted:
            print(
                f"  {SEV.get(f['severity'], '  ')} [{f['family']}·{f['rule']}] {f['detail'][:96]}"
            )
        for f in open_q:
            print(f"   ? [{f['family']}·{f['rule']}] UNVERIFIED: {f['detail'][:88]}")
        if jobs:
            asks = collections.Counter(
                k["asks"]
                for j in jobs
                for k in j.get("focus", [])
                if isinstance(k.get("asks"), str)
            )
            print(
                f"     → {len(jobs)} vision call(s) queued"
                + (f", carrying {dict(asks)}" if asks else "")
            )

    dest = corpus / f"report-{app}.json"
    dest.write_text(json.dumps(out, indent=1))
    n_a = sum(len(p["asserted"]) for p in out["pages"].values())
    n_o = sum(len(p["open"]) for p in out["pages"].values())
    # Counts, never a score. §6's Cut list bans any score, grade, rank or rating,
    # and "N findings" summed into a page quality number is exactly how one
    # arrives without anyone deciding to build it.
    print(f"\n{n_a} asserted · {n_o} open question(s) · {dest.name}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "corpus", type=pathlib.Path, nargs="?", default=pathlib.Path("corpus/out")
    )
    ap.add_argument("--app", default=profiles.DEFAULT)
    ap.add_argument("--page")
    a = ap.parse_args()
    main(a.corpus.resolve(), a.app, a.page)
