#!/usr/bin/env python3
"""The design-review CLI: one command, three artifacts, no MCP server.

    python3 review.py <corpus-dir> --profile reso-management

Writes, per run:
    review.json           every finding, weighted and ranked by the profile
    annotated/<page>.png  the frame with each finding boxed and numbered
    vlm_queue.json        the residue, cropped -- see route.py
    queue/<page>/*.png    the crops themselves

A CLI rather than an MCP tool, and the reason is measured rather than aesthetic.
An MCP tool CAN return image content to Claude Code, but that image is charged
against MAX_MCP_OUTPUT_TOKENS (default 25,000) and the anthropic/maxResultSizeChars
escape hatch explicitly has no effect on tools returning image content -- so an MCP
image tool has exactly one lever, and it is a session-global environment variable.
A CLI that writes PNGs and lets the agent `Read` the ones it wants chooses its own
output resolution per artifact and stays inside the Read ladder by construction.
Fewer moving parts, and it is already the fleet's habit.

The annotated PNG exists because a findings list is not reviewable. Nine findings
named by CSS path is a page of text that a reader has to re-project onto a layout
they cannot see; the same nine drawn on the frame is one glance. The numbering is
the join: box N on the image is finding N in review.json, so the two artifacts are
one artifact read two ways.

THIS COMMAND NEVER CALLS A MODEL. It runs the deterministic layer, runs the pixel
cross-check, applies the app's weighting, and prepares the residue. The June 2026
campaign ratified that taste stays human and that gates adjudicate correctness and
coverage only -- so the vision queue is an input to a person or an agent, and there
is deliberately no `--judge` flag for a later session to reach for.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image, ImageDraw

import detect_dom
import detect_xcheck
import profiles
import route

# Severity -> outline. Chosen to survive a greyscale screenshot and a red/green
# colour vision deficiency: the pairing is hue AND width, never hue alone.
INK = {
    "high": ((220, 38, 38), 3),
    "medium": ((217, 119, 6), 2),
    "low": ((37, 99, 235), 2),
}


def annotate(
    shot: pathlib.Path, snap: dict, findings: list[dict], dest: pathlib.Path
) -> int:
    """Draw each finding on the frame, numbered to match review.json.

    A finding whose element is not in the snapshot is skipped rather than drawn at
    the origin -- a box at 0,0 reads as a real finding about the page's top-left
    corner, which is the kind of confident-wrong artifact this whole bench exists
    to avoid. The count returned is what was actually drawn, so the caller can say
    so when it differs from the number of findings.
    """
    by_path = {e["path"]: e for e in snap["elements"]}
    img = Image.open(shot).convert("RGB")
    scale = img.width / snap["scroll"]["w"]
    d = ImageDraw.Draw(img)
    drawn = 0
    # Two rules firing on one element is the normal case, not the exception --
    # `spacing-gap` trips both spacing-rhythm and grid-violation on the same card.
    # Without this the second label is painted over the first and the image says
    # one finding where the JSON says two, which is the annotated frame lying
    # about the artifact it is supposed to be an index into.
    seen: dict[str, int] = {}
    for i, f in enumerate(findings, 1):
        el = by_path.get(f["target"])
        if el is None:
            continue
        r = el["rect"]
        box = [
            r["x"] * scale - 2,
            r["y"] * scale - 2,
            r["right"] * scale + 2,
            r["bottom"] * scale + 2,
        ]
        colour, width = INK.get(f.get("severity", "medium"), INK["medium"])
        d.rectangle(box, outline=colour, width=width)
        label = f"{i}"
        rank = seen.get(f["target"], 0)
        seen[f["target"]] = rank + 1
        tx = box[0] + rank * 22
        ty = max(0.0, box[1] - 13)
        d.rectangle([tx, ty, tx + 8 * len(label) + 6, ty + 13], fill=colour)
        d.text((tx + 3, ty + 2), label, fill=(255, 255, 255))
        drawn += 1
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    return drawn


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("corpus", type=pathlib.Path)
    ap.add_argument("--profile", default="default")
    ap.add_argument("--out", type=pathlib.Path, default=None)
    ap.add_argument(
        "--top", type=int, default=5, help="findings printed per page (all are written)"
    )
    a = ap.parse_args(argv[1:])

    corpus = a.corpus.resolve()
    outdir = (a.out or corpus).resolve()
    if not (corpus / "manifest.json").exists():
        print(f"review: no manifest under {corpus}")
        return 2
    profile = profiles.get(a.profile)
    tokens = json.loads((corpus / "manifest.json").read_text())["tokens"]
    outdir.mkdir(parents=True, exist_ok=True)

    report: dict[str, list[dict]] = {}
    routed = []
    for snap_p in sorted((corpus / "snapshots").glob("*.json")):
        shot = corpus / "shots" / f"{snap_p.stem}.png"
        snap = json.loads(snap_p.read_text())
        dom = detect_dom.find(snap, tokens)
        xch = detect_xcheck.check(snap, shot) if shot.exists() else []
        ranked = profiles.apply(profile, dom + xch)
        report[snap_p.stem] = ranked
        if shot.exists():
            annotate(shot, snap, ranked, outdir / "annotated" / f"{snap_p.stem}.png")
            routed.append(
                route.route_page(
                    snap_p.stem,
                    snap,
                    shot,
                    profiles.apply(profile, dom),
                    profiles.apply(profile, xch),
                    profile,
                    outdir,
                )
            )

    (outdir / "review.json").write_text(
        json.dumps({"profile": a.profile, "pages": report}, indent=1)
    )
    (outdir / "vlm_queue.json").write_text(
        json.dumps(
            {
                "profile": a.profile,
                "budget_per_page": profile["queue"],
                "pages": routed,
            },
            indent=1,
            default=str,
        )
    )

    print(f"profile {a.profile} -> {profile['app']}")
    supp = profiles.suppressed_rules(profile)
    if supp:
        print(f"  suppressed for this app: {', '.join(supp)}")
    for page, fs in sorted(report.items()):
        print(f"\n{page}  {len(fs)} finding(s)")
        for i, f in enumerate(fs[: a.top], 1):
            print(f"  {i:2d}. [{f['priority']:4.1f}] {f['rule']:24} {f['detail'][:88]}")
        if len(fs) > a.top:
            print(f"      ... {len(fs) - a.top} more in review.json")
    n_q = sum(len(r["queued"]) for r in routed)
    n_res = sum(len(r["resolved"]) for r in routed)
    print(
        f"\nrouter: {n_res} abstention(s) answered by the cross-check, "
        f"{n_q} job(s) queued for a vision pass"
    )
    print(
        f"artifacts: {outdir / 'review.json'}, {outdir / 'annotated'}, {outdir / 'queue'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
