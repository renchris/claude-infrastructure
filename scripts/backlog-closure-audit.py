#!/usr/bin/env python3
"""backlog-closure-audit.py — find backlog rows closed `done` on evidence that does not hold.

FULLY DETERMINISTIC. No model, no key, no vendor. The oracle is git.

WHY THIS IS NOT AN LLM JOB. The dossier docs/research/union-alpha-drain-2026-09-17/
ranked a "false-closure audit" as the best candidate for rented bulk inference. Measured,
82.4% of `done` evidence strings carry a sha-shaped token a REGEX extracts, and the
adjudicator was always `git merge-base --is-ancestor`. The model was only ever being asked
to pull a sha out of free text.

🚨 WHY STAGE 1 ALONE IS WORSE THAN NOTHING. "Not an ancestor of trunk" is NOT "never
landed". A land rebases, which rewrites the commit object, so the content reaches trunk
under a different sha and `--is-ancestor` says no. Measured on this repo: a naive stage-1
pass flags ~39% of resolvable shas. Reporting those as false closures would itself be a
mass false closure — the exact defect this tool exists to find. So every non-ancestor goes
to STAGE 2, which asks the only question that actually matters:

    is this commit's CONTENT on trunk?

compared blob-by-blob over the paths the commit touched. And shas that do not resolve in
this repo at all are NEVER SCORED — they are another repo's, and absence here is not
evidence (`absent-from-trunk-has-two-opposite-causes`).

Verdicts, in decreasing confidence that the row is honest:

  on-trunk        >=1 cited sha is an ancestor of trunk
  content-landed  not an ancestor, but every path it touched matches trunk byte-for-byte
  partial         some paths match trunk, some do not — worth a human glance
  SUSPECT         resolves here, not an ancestor, and its content is NOT on trunk
  foreign         no cited sha resolves in this repo — NOT SCORED
  no-sha          evidence cites no sha — NOT SCORED (many such rows claim no landing)
"""

from __future__ import annotations

import argparse, json, re, subprocess, sys
from pathlib import Path

SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
DEFAULT_STORE = Path.home() / ".claude/autonomy/backlog.jsonl"


def git(*args: str, repo: str) -> tuple[int, str]:
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return p.returncode, p.stdout


def load_done(store: Path) -> list[dict]:
    rows, bad = [], 0
    for line in store.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            bad += 1        # a parse failure is REPORTED, never silently skipped
            continue
        if r.get("event") == "done" and r.get("evidence"):
            rows.append(r)
    if bad:
        print(f"  note: {bad} unparseable line(s) in the store", file=sys.stderr)
    return rows


def resolve_all(shas: list[str], repo: str) -> dict[str, str]:
    """One batch call instead of N forks. Maps each CITED sha -> its full oid.

    🚨 `--batch-check` echoes the RESOLVED 40-char oid for a hit, not the abbreviated
    string you fed it. Building a set from its output and then testing `cited in set`
    therefore fails for every abbreviation — which is almost all of them, since evidence
    strings cite short shas. That bug reported 310 of 400 rows as another repo's work.
    It outputs exactly one line per input, IN ORDER, so zip the two instead."""
    if not shas:
        return {}
    p = subprocess.run(["git", "-C", repo, "cat-file", "--batch-check"],
                       input="\n".join(shas) + "\n", capture_output=True, text=True)
    lines = p.stdout.splitlines()
    if len(lines) != len(shas):
        print(f"  WARN: batch-check returned {len(lines)} lines for {len(shas)} inputs"
              f" — refusing to zip a misaligned mapping", file=sys.stderr)
        return {}
    out = {}
    for cited, line in zip(shas, lines):
        f = line.split()
        if len(f) >= 2 and f[1] == "commit":
            out[cited] = f[0]
    return out


def content_on_trunk(sha: str, repo: str, trunk: str) -> tuple[str, int, int]:
    """STAGE 2. Compare every path the commit touched against trunk, blob-by-blob."""
    rc, out = git("diff-tree", "--no-commit-id", "--name-only", "-r", sha, repo=repo)
    paths = [p for p in out.splitlines() if p.strip()]
    if not paths:
        return "empty", 0, 0
    match = miss = 0
    for path in paths:
        rc_a, blob_a = git("rev-parse", f"{sha}:{path}", repo=repo)
        rc_b, blob_b = git("rev-parse", f"{trunk}:{path}", repo=repo)
        if rc_a != 0:
            continue                       # deleted by this commit; not evidence either way
        if rc_b == 0 and blob_a.strip() == blob_b.strip():
            match += 1
        else:
            miss += 1
    if miss == 0 and match:
        return "content-landed", match, miss
    if match and miss:
        return "partial", match, miss
    return "SUSPECT", match, miss


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=str(Path.home() / "Development/claude-infrastructure"))
    ap.add_argument("--trunk", default="origin/main")
    ap.add_argument("--store", type=Path, default=DEFAULT_STORE)
    ap.add_argument("--limit", type=int, default=0, help="audit only the N most recent rows")
    ap.add_argument("--json", type=Path, help="write full per-row results here")
    ap.add_argument("--show", type=int, default=12, help="how many SUSPECT rows to print")
    args = ap.parse_args()

    rows = load_done(args.store)
    if args.limit:
        rows = rows[-args.limit:]
    print(f"done rows with evidence: {len(rows)}", file=sys.stderr)

    every = sorted({h for r in rows for h in SHA.findall(r["evidence"])
                    if not h.isdigit()})
    known = resolve_all(every, args.repo)      # cited(abbrev) -> full oid
    print(f"sha candidates: {len(every)}  resolve here: {len(known)}", file=sys.stderr)

    # Ancestry is asked ONCE per distinct sha, not once per row.
    anc: dict[str, bool] = {}
    for h, full in known.items():
        anc[h] = subprocess.run(["git", "-C", args.repo, "merge-base", "--is-ancestor",
                                 full, args.trunk], capture_output=True).returncode == 0
    print(f"  of those, ancestors of {args.trunk}: {sum(anc.values())}", file=sys.stderr)

    stage2: dict[str, tuple[str, int, int]] = {}
    results, tally = [], {}
    for r in rows:
        cited = [h for h in SHA.findall(r["evidence"]) if not h.isdigit()]
        mine = [h for h in cited if h in known]
        if not cited:
            v, detail = "no-sha", ""
        elif not mine:
            v, detail = "foreign", f"{len(cited)} sha(s), none resolve here"
        elif any(anc[h] for h in mine):
            v, detail = "on-trunk", ""
        else:
            best, detail = "SUSPECT", ""
            for h in mine:
                if h not in stage2:
                    stage2[h] = content_on_trunk(known[h], args.repo, args.trunk)
                verdict, m, x = stage2[h]
                if verdict == "content-landed":
                    best, detail = "content-landed", f"{h} {m} path(s) match trunk"; break
                if verdict == "partial" and best == "SUSPECT":
                    best, detail = "partial", f"{h} {m} match / {x} differ"
                elif best == "SUSPECT":
                    detail = f"{h} {x} path(s) absent or different on trunk"
            v = best
        tally[v] = tally.get(v, 0) + 1
        results.append({"id": r.get("id"), "ts": r.get("ts"), "verdict": v,
                        "detail": detail, "evidence": r["evidence"][:220]})

    print("\n=== VERDICTS ===")
    for k in ("on-trunk", "content-landed", "partial", "SUSPECT", "foreign", "no-sha"):
        if k in tally:
            scored = k in ("on-trunk", "content-landed", "partial", "SUSPECT")
            print(f"  {k:16} {tally[k]:>5}{'' if scored else '   (not scored)'}")
    scored_n = sum(tally.get(k, 0) for k in
                   ("on-trunk", "content-landed", "partial", "SUSPECT"))
    if scored_n:
        s = tally.get("SUSPECT", 0)
        print(f"\n  scored rows: {scored_n}   SUSPECT: {s} ({100*s/scored_n:.1f}% of scored)")

    sus = [r for r in results if r["verdict"] == "SUSPECT"]
    if sus:
        print(f"\n=== SUSPECT rows (first {min(args.show,len(sus))} of {len(sus)}) ===")
        for r in sus[:args.show]:
            print(f"\n  {r['id']}  {r['ts']}")
            print(f"    {r['detail']}")
            print(f"    evidence: {r['evidence'][:150]}")

    if args.json:
        args.json.write_text(json.dumps(results, indent=1), encoding="utf-8")
        print(f"\nfull results -> {args.json}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
