"""build_bundles.py - the sanitized reviewer bundles for the A3 replay (REPORT §3.8 'Isolation').

For each usable held-out plan, two working directories are exported from the repo AT THE FREEZE SHA with
`git archive` (read-only on the source repo; no checkout, no worktree):
  <out>/<id>/full/   plan/ + research/ (the paths the plan cited at the freeze) + FRAME_CHECKLIST.md
  <out>/<id>/plan/   plan/ only
Left out: every later commit, the hole history, ledgers written after the freeze, .claude/ and CLAUDE.md.
Seeds (seeds/<id>.json, if present) are applied to the plan copy in both bundles; an anchor that is not found
verbatim exactly once voids that seed (recorded, never guessed).

usage: python3 build_bundles.py <history_dir> <heldout_dir> <seeds_dir> <out_dir>
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tarfile

SKIP_PARTS = {
    ".claude",
    "CLAUDE.md",
    "AGENTS.md",
    "KNOWN-GAPS.md",
    "critique",
    "node_modules",
    ".git",
}


def export(repo, sha, paths, dest):
    """git archive <sha> -- <paths> into dest; paths that do not exist at sha are skipped one by one"""
    os.makedirs(dest, exist_ok=True)
    got = []
    for p in paths:
        p = p.strip().rstrip("/")
        if not p or p.startswith("/") or ".." in p:
            continue
        r = subprocess.run(
            ["git", "-C", repo, "archive", "--format=tar", sha, "--", p],
            capture_output=True,
        )
        if r.returncode != 0:
            continue
        with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tf:
            members = [
                m
                for m in tf.getmembers()
                if not (set(m.name.split("/")) & SKIP_PARTS) and m.size < 2_000_000
            ]
            tf.extractall(dest, members=members)
        got.append(p)
    return got


def apply_seeds(plan_dir, seeds):
    applied = []
    for sd in seeds:
        anchor, repl = sd.get("anchor", ""), sd.get("replacement", "")
        hits = []
        for root, _, files in os.walk(plan_dir):
            for fn in files:
                fp = os.path.join(root, fn)
                try:
                    txt = open(fp).read()
                except (UnicodeDecodeError, OSError):
                    continue
                if txt.count(anchor) == 1:
                    hits.append((fp, txt))
        ok = len(anchor) >= 40 and len(hits) == 1
        if ok:
            fp, txt = hits[0]
            open(fp, "w").write(txt.replace(anchor, repl))
        applied.append(
            dict(sd, applied=ok, void=None if ok else "anchor-not-unique-or-short")
        )
    return applied


def main(hist_dir, heldout_dir, seeds_dir, out_dir):
    for fn in sorted(os.listdir(hist_dir)):
        if not fn.endswith(".json"):
            continue
        h = json.load(open(os.path.join(hist_dir, fn)))
        if not h.get("usable"):
            continue
        pid, repo, sha = h["id"], h["repo"], h["freeze_sha"]
        plan_paths = h.get("bundle_plan_paths") or [h["path"].split()[0]]
        root = os.path.join(out_dir, pid)
        shutil.rmtree(root, ignore_errors=True)
        manifest = dict(id=pid, repo=repo, freeze_sha=sha)
        seeds = []
        sp = os.path.join(seeds_dir, fn)
        if os.path.exists(sp):
            seeds = json.load(open(sp))
        for strat in ("full", "plan"):
            d = os.path.join(root, strat)
            manifest[strat + "_plan"] = export(
                repo, sha, plan_paths, os.path.join(d, "plan")
            )
            if strat == "full":
                cited = [p for p in h.get("cited_paths", []) if p not in plan_paths]
                manifest["full_research"] = export(
                    repo, sha, cited, os.path.join(d, "research")
                )
                ho = json.load(open(os.path.join(heldout_dir, fn)))
                with open(os.path.join(d, "FRAME_CHECKLIST.md"), "w") as fh:
                    fh.write(
                        "# Frame axis checklist (held out: rows citing only this plan's holes removed)\n\n"
                    )
                    for r in ho["fac_kept"]:
                        fh.write("- %s: %s\n" % (r["fac"], r["axis"]))
            if seeds:
                manifest[strat + "_seeds"] = apply_seeds(os.path.join(d, "plan"), seeds)
        json.dump(manifest, open(os.path.join(root, "manifest.json"), "w"), indent=1)
        print(
            "%-32s plan=%d research=%d seeds=%s"
            % (
                pid,
                len(manifest["full_plan"]),
                len(manifest.get("full_research", [])),
                sum(1 for s in manifest.get("full_seeds", []) if s["applied"]),
            )
        )


if __name__ == "__main__":
    main(*sys.argv[1:5])
