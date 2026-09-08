#!/usr/bin/env python3
"""branch-adjudicate.py — decide whether an unlanded branch's work reached the trunk
in REWORKED form, or is genuinely absent.

── THE GAP THIS FILLS ────────────────────────────────────────────────────────────────────────
scripts/branch-prune-landed.sh proves landedness by PATCH EQUIVALENCE and refuses everything
else, calling it "real stranded work". That refusal is correct as far as it goes and it is also
where branches ACCUMULATE: a branch whose work landed RE-DERIVED — rewritten by hand on trunk
rather than cherry-picked — has no patch-equivalent commit, so the pruner holds it forever and a
reader who trusts the same signal concludes landed work was lost. Measured 2026-09-08 in this
repo: 251 non-backup local branches carried unique commits, 160 of them touching only paths the
trunk had since rewritten, and the item asking for their triage (cc-backlog 806277b4eb8b) had
seen that population grow from 61 to 160 in 23 days while nothing adjudicated it.

── WHY SYMBOLS, AND NOT LINES ───────────────────────────────────────────────────────────────
Two weaker tests were built first and both were REFUTED by their own controls, which is why this
one is written the way it is:

  v1  "is this added line in the trunk tree today"      12 of 66 known-patch-landed branches
                                                        read ABSENT. It cannot tell "never
                                                        landed" from "landed, then trunk edited
                                                        past it".
  v2  "did this added line EVER exist on trunk"          Both controls passed, and it still
                                                        convicted cloud-g5-create at ratio 0.04
                                                        while every deliverable that branch
                                                        names — scripts/lib/cloud-create.sh,
                                                        tests/cloud-create-lib.bats — sits on
                                                        trunk. A re-derived land keeps NO line.

What survives a rework is the SYMBOL a change introduces: the file it adds, the function it
defines, the flag it spells, the constant it names. cloud-g5-create's `cc_create_normalise`
landed as `cc_cloud_normalise`; the rename is visible, the capability is not lost. So a symbol
found on trunk is evidence the work arrived; a symbol found NOWHERE is the candidate loss, and
because it is NAMED, a human verdict on it costs one grep rather than a diff read.

This test does not settle a rename by itself — `cc_create_normalise` is absent from trunk under
that spelling. It NARROWS: 160 branches to 45, and 45 to 38 distinct missing-symbol signatures,
each of which a reader can adjudicate against trunk by name. It is a triage instrument, not an
oracle, and the residue it hands over is meant to be read.

── WHAT IT CANNOT SEE (stated so no caller over-reads a LANDED-REWORKED) ────────────────────
A change that introduces NO new symbol — a reordering, a bound changed from 30 to 300, a fixed
comparison operator, a deleted line — is invisible here and will read LANDED-REWORKED on a
branch that in fact holds it. That is a property of the unit, not a bug to be tuned away: a
verdict from this script bounds SYMBOL-shaped loss and nothing else, and `--self-check` proves
only that the instrument discriminates, never that a branch is safe to delete. This script
never deletes anything.

Usage:
  scripts/branch-adjudicate.py [--trunk origin/main] [--json] [--verdict V] [--include-backups]
  scripts/branch-adjudicate.py --self-check      # controls on a synthetic repo; rc 1 if refuted
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

# A symbol must be long enough that finding it on trunk is evidence rather than coincidence.
TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]{3,}")
RE_FUNC = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_-]{3,})\s*\(\)\s*\{?")
RE_PYDEF = re.compile(r"^\s*(?:def|class)\s+([A-Za-z_][A-Za-z0-9_]{3,})")
RE_FLAG = re.compile(r"--([a-z][a-z0-9-]{3,})")
RE_CONST = re.compile(r"^\s*(?:readonly\s+|export\s+|local\s+)?([A-Z][A-Z0-9_]{4,})=")

# Branches whose NAME declares them a snapshot. A backup is not evidence of loss.
BACKUP_NAME = re.compile(r"(^backup/|backup|[-.]bak$|prerebase|pre-rebase|prereset)", re.I)

MOSTLY_LANDED_FLOOR = 0.85


def run(repo: str, *args: str, timeout: int = 240) -> str:
    """Git stdout as text, DECODED LENIENTLY.

    `text=True` alone raises UnicodeDecodeError on the first non-UTF-8 byte, and a repo that
    tracks one PNG is enough: the scan died on `git show` of a binary blob after reading 2,000
    files, having printed nothing at all. A tool whose whole job is to census a tree may not be
    stopped by one byte in it, so decode with replacement and let the symbol regexes find
    nothing in the noise."""
    try:
        proc = subprocess.run(["git", "-C", repo, *args], capture_output=True,
                              timeout=timeout)
        return proc.stdout.decode("utf-8", errors="replace")
    except (subprocess.TimeoutExpired, OSError):
        return ""


def symbols(text: str) -> set[str]:
    out: set[str] = set()
    for line in text.split("\n"):
        for rx in (RE_FUNC, RE_PYDEF, RE_CONST):
            m = rx.match(line)
            if m:
                out.add(m.group(1))
        for m in RE_FLAG.finditer(line):
            out.add(m.group(1))
    return out


def trunk_universe(repo: str, trunk: str) -> tuple[set[str], set[str], set[str]]:
    """Every token, path and basename the trunk carries. Read from the trunk's own blobs, never
    from a working tree, so a dirty checkout cannot change a verdict."""
    paths = {p for p in run(repo, "ls-tree", "-r", "--name-only", trunk).split("\n") if p}
    tokens: set[str] = set()
    for p in paths:
        blob = run(repo, "show", f"{trunk}:{p}", timeout=60)
        if blob:
            tokens.update(m.group(0) for m in TOKEN.finditer(blob))
    return tokens, paths, {os.path.basename(p) for p in paths}


def adjudicate(repo: str, trunk: str, branch: str, universe, held: set[str] | None = None) -> dict:
    tokens, paths, basenames = universe
    if held and branch in held:
        return dict(branch=branch, verdict="HELD-WORKTREE", n_intro=0, n_missing=0,
                    ratio=1.0, missing_symbols=[], missing_paths=[])
    mb = run(repo, "merge-base", trunk, branch).strip()
    if not mb:
        return dict(branch=branch, verdict="NO-MERGE-BASE", n_intro=0, n_missing=0,
                    ratio=0.0, missing_symbols=[], missing_paths=[])

    ahead = run(repo, "rev-list", "--count", f"{trunk}..{branch}").strip()
    if ahead == "0":
        return dict(branch=branch, verdict="ANCESTOR-LANDED", n_intro=0, n_missing=0,
                    ratio=1.0, missing_symbols=[], missing_paths=[])

    cherry = run(repo, "cherry", trunk, branch)
    if cherry and not any(l.startswith("+") for l in cherry.split("\n")):
        # Every commit has a patch-equivalent upstream. branch-prune-landed.sh already proves
        # this class; report it so a caller can see the two instruments agree.
        return dict(branch=branch, verdict="PATCH-LANDED", n_intro=0, n_missing=0,
                    ratio=1.0, missing_symbols=[], missing_paths=[])

    added, modified = [], []
    for line in run(repo, "diff", "--name-status", f"{mb}..{branch}").split("\n"):
        if not line.strip():
            continue
        parts = line.split("\t")
        status, path = parts[0], parts[-1]
        if status.startswith("A"):
            added.append(path)
        elif status.startswith(("M", "R")):
            modified.append(path)

    # A file the branch ADDS that trunk has under neither its path nor its basename is a whole
    # deliverable that never arrived -- a stronger signal than any count of symbols.
    missing_paths = [p for p in added
                     if p not in paths and os.path.basename(p) not in basenames]

    introduced: set[str] = set()
    for p in added + modified:
        new = symbols(run(repo, "show", f"{branch}:{p}", timeout=60))
        old = symbols(run(repo, "show", f"{mb}:{p}", timeout=60)) if p in modified else set()
        introduced |= new - old

    missing = sorted(s for s in introduced if s not in tokens)
    total = len(introduced)
    ratio = 1.0 if total == 0 else (total - len(missing)) / total

    if missing_paths:
        verdict = "ABSENT-FILE"
    elif total == 0:
        verdict = "NO-SYMBOLS"
    elif not missing:
        verdict = "LANDED-REWORKED"
    elif ratio >= MOSTLY_LANDED_FLOOR:
        verdict = "MOSTLY-LANDED"
    else:
        verdict = "ABSENT-SYMBOLS"

    return dict(branch=branch, verdict=verdict, n_intro=total, n_missing=len(missing),
                ratio=round(ratio, 4), missing_symbols=missing[:40],
                missing_paths=missing_paths[:20])


def worktree_held(repo: str) -> set[str]:
    """Branches a live worktree has checked out.

    THIS IS A REFUSAL, NOT A STATISTIC. A branch under a worktree is somebody's bench: it is
    in-flight or deliberately parked, and its absence from trunk is expected rather than lost.
    The wave that produced this script found the case the hard way -- `drain/lane-infra` read as
    the one genuine RECOVER in 38 signatures, and its tip was NINE HOURS OLD with a live worktree
    holding it. Cherry-picking it would have duplicated a peer's open work, which is a worse
    outcome than the loss the scan was hunting. Adjudicate what nobody is holding."""
    held: set[str] = set()
    for line in run(repo, "worktree", "list", "--porcelain").split("\n"):
        if line.startswith("branch "):
            held.add(line.split(None, 1)[1].strip().replace("refs/heads/", "", 1))
    return held


def local_branches(repo: str, include_backups: bool, trunk: str) -> list[str]:
    refs = [b for b in run(repo, "for-each-ref", "--format=%(refname:short)",
                           "refs/heads").split("\n") if b]
    # The trunk is not a candidate for its own adjudication. `--trunk origin/main` names a
    # remote-tracking ref, so strip the remote to find the local branch that shadows it.
    trunk_local = trunk.split("/", 1)[1] if "/" in trunk else trunk
    refs = [b for b in refs if b != trunk_local]
    if include_backups:
        return refs
    return [b for b in refs if not BACKUP_NAME.search(b)]


# ── CONTROLS ────────────────────────────────────────────────────────────────────────────────
# Built on a SYNTHETIC repo, never on this one's live branches: a control re-derived from the
# live population changes under it and cannot fail the same way twice (repo memory:
# control-population-must-be-stable). Two poles, and the POSITIVE one is the load-bearing half --
# an instrument that convicts nothing would pass the negative control alone.
def self_check() -> int:
    with tempfile.TemporaryDirectory() as td:
        repo = os.path.join(td, "r")
        os.makedirs(repo)

        def g(*a):
            subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, check=False)

        def write(path, body):
            full = os.path.join(repo, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as fh:
                fh.write(body)

        env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@e",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@e"}
        os.environ.update(env)
        g("init", "-q", "-b", "main")
        write("base.sh", "#!/bin/sh\nBASE_CONST=1\n")
        g("add", "-A"); g("commit", "-q", "-m", "base")

        # POSITIVE: work that reached the trunk RE-DERIVED. The branch spells the capability one
        # way; main spells it another, keeping the symbols and sharing not one line of context.
        # A line-identity test convicts this branch. This one must not.
        g("checkout", "-q", "-b", "landed-reworked")
        write("feature.sh", "#!/bin/sh\nFEATURE_LIMIT=10\nfeature_apply() { echo apply; }\n")
        g("add", "-A"); g("commit", "-q", "-m", "feat: apply")
        g("checkout", "-q", "main")
        write("feature.sh",
              "#!/bin/sh\n# rewritten on trunk, different bytes, same capability\n"
              "FEATURE_LIMIT=20\nfeature_apply() { printf 'apply\\n'; }\n")
        g("add", "-A"); g("commit", "-q", "-m", "feat: apply, re-derived")

        # NEGATIVE: work that never arrived, in both shapes the classifier claims to catch --
        # a symbol trunk has never seen, and a whole file trunk does not carry.
        g("checkout", "-q", "-b", "genuinely-absent", "main")
        write("orphan.sh", "#!/bin/sh\nORPHAN_TIMEOUT=5\norphan_reap() { echo reap; }\n")
        g("add", "-A"); g("commit", "-q", "-m", "feat: orphan")
        g("checkout", "-q", "main")

        universe = trunk_universe(repo, "main")
        pos = adjudicate(repo, "main", "landed-reworked", universe)
        neg = adjudicate(repo, "main", "genuinely-absent", universe)

        ok = True
        if pos["verdict"] not in ("LANDED-REWORKED", "PATCH-LANDED", "ANCESTOR-LANDED"):
            print(f"REFUTED positive control: re-derived work read {pos['verdict']} "
                  f"(missing={pos['missing_symbols']}) — the instrument convicts landed work",
                  file=sys.stderr)
            ok = False
        if neg["verdict"] not in ("ABSENT-FILE", "ABSENT-SYMBOLS"):
            print(f"REFUTED negative control: absent work read {neg['verdict']} "
                  "— the instrument cannot see loss", file=sys.stderr)
            ok = False
        if ok:
            print(f"self-check ok: positive={pos['verdict']} negative={neg['verdict']}")
        return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--trunk", default="origin/main")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--verdict", default="", help="only report this verdict")
    ap.add_argument("--include-backups", action="store_true")
    ap.add_argument("--self-check", action="store_true")
    a = ap.parse_args()

    if a.self_check:
        return self_check()

    repo = os.path.abspath(a.repo)
    if not run(repo, "rev-parse", "--git-dir").strip():
        print("branch-adjudicate: not a git repo", file=sys.stderr)
        return 2
    if not run(repo, "rev-parse", "--verify", "--quiet", a.trunk).strip():
        print(f"branch-adjudicate: no such trunk ref: {a.trunk}", file=sys.stderr)
        return 2

    universe = trunk_universe(repo, a.trunk)
    held = worktree_held(repo)
    rows = [adjudicate(repo, a.trunk, b, universe, held)
            for b in local_branches(repo, a.include_backups, a.trunk)]
    if a.verdict:
        rows = [r for r in rows if r["verdict"] == a.verdict]

    if a.json:
        print(json.dumps(rows, indent=1))
    else:
        print("branch\tverdict\tn_intro\tn_missing\tratio\tmissing")
        for r in sorted(rows, key=lambda x: (x["ratio"], -x["n_missing"])):
            print(f"{r['branch']}\t{r['verdict']}\t{r['n_intro']}\t{r['n_missing']}"
                  f"\t{r['ratio']}\t{','.join(r['missing_symbols'][:8])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
