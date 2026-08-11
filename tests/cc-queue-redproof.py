#!/usr/bin/env python3
"""RED-proof the cc-queue suite: prove each assertion CAN fail, and fails for the RIGHT reason.

A green suite proves nothing on its own — this repo's recorded failure mode is the vacuous pass. So
for every load-bearing behaviour in bin/cc-queue this script sabotages the REAL artifact (never a
hand-written approximation, which passes vacuously) and requires the NAMED test that claims to check
it to flip to `not ok`.

Two disciplines carried over from scripts/banner-gate-redproof.py:

  * BY NAME, not by count — requiring merely "some test failed" lets an unrelated collapse
    counterfeit the proof. Each case names the substring of the test it must break.
  * ANCHOR EXACTLY ONCE — a mutation whose anchor matches 0 times is a silent no-op that reports as
    "survived"; one matching 2+ times sabotages more than it claims. Both are rejected outright.

    tests/cc-queue-redproof.py           # all cases
    tests/cc-queue-redproof.py --list    # just the case names

Exit 0 = every mutation was caught by the test that claims to catch it.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUBJECT = ROOT / "bin" / "cc-queue"

# (case name, literal anchor in bin/cc-queue, replacement, substring of the test that MUST flip)
CASES: list[tuple[str, str, str, str]] = [
    (
        "heartbeat-check-removed",
        "[ -e \"$PERMPEND_DIR/.beacon-alive\" ] || { printf 'inert'; return; }",
        ":",
        "heartbeat MISSING is still INERT",
    ),
    (
        # NOT the `-d` line alone: with the heartbeat check present, deleting it is UNOBSERVABLE
        # (rm -rf takes the directory AND the heartbeat with it), so that mutation proves nothing —
        # it targets a redundant defence-in-depth guard rather than the behaviour. Mutate the verdict.
        "beacon-world-always-reports-live",
        "beacon_world(){   # inert | live\n",
        "beacon_world(){   # inert | live\n  printf 'live'; return\n",
        "ABSENT beacon dir renders INERT",
    ),
    (
        "activity-bound-to-telemetry-ts",
        "if $m == null then $cold else ($now - $m) end",
        "($now - .tel_ts)",
        "FRESH telemetry ts does NOT make a cold session look working",
    ),
    (
        "liveness-ignores-pid-ownership",
        "alive: (.pid > 0 and ($alive[(.pid|tostring)] // false))",
        "alive: (.pid > 0)",
        "liveness requires the COMMAND to match",
    ),
    (
        "unresolved-transcript-reads-as-warm",
        "if $m == null then $cold else ($now - $m) end",
        "if $m == null then 0 else ($now - $m) end",
        "UNRESOLVABLE transcript is COLD",
    ),
    (
        "blocked-no-longer-sorts-first",
        'if .state=="blocked" then 0 ',
        'if .state=="blocked" then 9 ',
        "blocked sorts first",
    ),
    (
        "blocked-rows-get-capped",
        'to_entries | map(select(.value.state=="blocked"))',
        'to_entries | map(select(.value.state=="blocked")) | .[0:1]',
        "blocked rows are NEVER capped",
    ),
    (
        "cap-stops-announcing-what-it-withheld",
        "… $(( n - OPT_LIMIT )) more not shown",
        "",
        "ANNOUNCES the withheld count",
    ),
    (
        "enrich-marker-dropped",
        " [enrich:none]",
        "",
        "marked enrich:none",
    ),
    (
        "blocked-command-detail-dropped",
        '($i.command // "")',
        '("")',
        "EXACT blocked command",
    ),
    (
        "account-label-not-normalised",
        '| sub("^claude-";"") | if . == "claude" or . == "" then "primary" else . end',
        "",
        "account label is normalised",
    ),
    (
        "check-passes-while-inert",
        "[ \"$bw\" = live ] || { printf 'cc-queue: BEACON INERT — cannot certify (hook has never run)\\n' >&2; return 2; }",
        ":",
        "--check exits 2 (never 0) when the beacon is INERT",
    ),
    (
        # The dangerous failure is not "attach errors" — it is attach silently focusing the WRONG
        # pane when the requested row has none (a headless agent). Prove that cannot pass.
        "paneless-row-focuses-someone-elses-pane",
        'if [ -z "$pane" ]; then',
        "if false; then",
        "NO registered pane fails loudly",
    ),
    (
        "attach-ignores-the-requested-row",
        'sid="$(printf \'%s\' "$rows" | jq -r --argjson n "$want" \'.[$n-1].sid // empty\')"',
        "sid=\"$(printf '%s' \"$rows\" | jq -r '.[-1].sid // empty')\"",
        "focuses the pane registered for THAT row",
    ),
    (
        "malformed-source-takes-out-the-run",
        'out="$(jq -c "$filt" "$f" 2>/dev/null)" || continue',
        "continue",
        "malformed telemetry file does not hide the other rows",
    ),
]


def run_suite(subject_dir: Path) -> str:
    """Run the bats suite against a tree whose bin/cc-queue may be mutated. Returns TAP output."""
    proc = subprocess.run(
        ["bats", str(subject_dir / "tests" / "cc-queue.bats")],
        capture_output=True,
        text=True,
        cwd=subject_dir,
    )
    return proc.stdout + proc.stderr


def failed_tests(tap: str) -> list[str]:
    return [ln for ln in tap.splitlines() if ln.startswith("not ok")]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print case names and exit")
    ap.add_argument(
        "--check-anchors",
        action="store_true",
        help="assert every anchor still matches the subject EXACTLY once; no bats run",
    )
    args = ap.parse_args()

    if args.list:
        for name, *_ in CASES:
            print(name)
        return 0

    src = SUBJECT.read_text()

    # --check-anchors: the half of this harness that is cheap enough to be part of the normal test
    # contract (tests/anti-vacuity-contract.bats runs it). The full proof needs a bats run per case and
    # stays an explicit invocation; this needs none, and it is the mode that catches the ROT.
    #
    # An anchor is a literal line of the subject that a load-bearing assertion depends on. It going
    # to 0 matches means the subject changed out from under the proof — which is exactly when the
    # suite's claim about that behaviour may have quietly become vacuous, and precisely the case
    # "run it manually sometime" never covers. Going to 2+ means the mutation would sabotage more
    # than it claims. Both are unsound, and both used to be discoverable only by running the whole
    # thing by hand.
    if args.check_anchors:
        bad = 0
        for name, anchor, _repl, _must_break in CASES:
            hits = src.count(anchor)
            if hits != 1:
                print(
                    f"  {name:<40} ANCHOR MATCHED {hits}x (must be exactly 1) — case is unsound"
                )
                bad += 1
        if bad:
            print(
                f"cc-queue-redproof --check-anchors: FAIL — {bad} of {len(CASES)} anchors no longer "
                f"match {SUBJECT.name} exactly once. The proof is stale: re-anchor it, or the "
                f"assertions it backs are unproven."
            )
            return 1
        print(
            f"cc-queue-redproof --check-anchors: {len(CASES)}/{len(CASES)} anchors live in {SUBJECT.name}"
        )
        return 0

    with tempfile.TemporaryDirectory() as td:
        work = Path(td) / "tree"
        shutil.copytree(ROOT / "bin", work / "bin")
        shutil.copytree(ROOT / "tests", work / "tests")
        subject = work / "bin" / "cc-queue"

        baseline = run_suite(work)
        if failed_tests(baseline) or "1.." not in baseline:
            print(
                "ABORT: baseline is not green — a RED-proof against a red baseline proves nothing."
            )
            print(baseline[-2000:])
            return 1
        n_assertions = len([l for l in baseline.splitlines() if re.match(r"^ok \d", l)])
        print(f"baseline: GREEN ({n_assertions} assertions)\n")

        bad = 0
        for name, anchor, repl, must_break in CASES:
            hits = src.count(anchor)
            if hits != 1:
                print(
                    f"  {name:<40} ANCHOR MATCHED {hits}x (must be exactly 1) — case is unsound"
                )
                bad += 1
                continue
            subject.write_text(src.replace(anchor, repl))
            subject.chmod(0o755)
            tap = run_suite(work)
            broke = failed_tests(tap)
            if not broke:
                print(
                    f"  {name:<40} ✗ SURVIVED — nothing caught it (the claim is VACUOUS)"
                )
                bad += 1
            elif not any(must_break in ln for ln in broke):
                names = "; ".join(ln[:70] for ln in broke[:2])
                print(
                    f"  {name:<40} ✗ WRONG TEST flipped (wanted '{must_break}') — got: {names}"
                )
                bad += 1
            else:
                print(
                    f"  {name:<40} ✓ caught by '{must_break}' ({len(broke)} test(s) red)"
                )
            subject.write_text(src)  # restore before the next case

        print()
        if bad:
            print(f"RED-PROOF: INCOMPLETE — {bad}/{len(CASES)} case(s) unproven.")
            return 1
        print(
            f"RED-PROOF: all {len(CASES)} mutations caught by the test that claims them."
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
