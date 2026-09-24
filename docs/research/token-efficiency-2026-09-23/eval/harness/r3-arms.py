#!/usr/bin/env python3
"""r3-arms.py — build round 3's F1 bisect arms under $GATE_ROOT/arms (see GATE.md § Round 3).

Round 2's re-gate (GATE.md § R3) failed slim on turns (+13.7%) and tool errors (+24.6%). Reading the
transcripts named two mechanisms, and each arm below targets one:

  r3ptr     slim with the full file's two skill POINTERS in place of slim's two load IMPERATIVES:
            slim's "Load the plan-conventions skill before you create or edit a plan…" paragraph is
            replaced by the full file's Plan Document Conventions paragraph (rules inline, skill as a
            pointer), and slim's "…load it before asking the user to run anything" line by the full
            file's "Full rule → the manual-command-delivery skill." Slim loaded plan-conventions in 5/5
            T04 runs and manual-command-delivery in 4/5 T03 runs; full loaded neither in any run.
  r3ledger  slim with the close ledger at the path that exists in every repo
            (`~/.claude/scripts/wrap-ledger.sh`) instead of the repo-relative `scripts/wrap-ledger.sh`.
            About 26 of slim's 43 non-zero exits were probes for that relative path (`ls
            scripts/wrap-ledger.sh`, `ls scripts`), against 3 in full; only claude-infrastructure has it.
  r3both    both.
  r3refuse  r3both plus one Safety line: a permission refusal is an answer, so do not re-issue the
            command split, reworded or through `git -C`. Added after r3both left T04/T19 high: slim's
            excess there tracked push attempts, re-spelling a push the permission check had refused
            until one got through, where full handed the push back after the first refusal.

Source arms: $GATE_ROOT/arms/{full,slim}, copied from the re-gate's frozen arms. Then
probe.sh <arm> <task> <first-rep> <last-rep> <config-dir>, reps above the gate's 1-10."""

import os, shutil

A = os.path.join(os.environ.get("GATE_ROOT", "/tmp/tokeff-r3"), "arms")
full = open(f"{A}/full/CLAUDE.md").read().splitlines(keepends=True)
slim = open(f"{A}/slim/CLAUDE.md").read()


def line_of(lines, prefix):
    return next(l for l in lines if l.startswith(prefix))


def one(t, old, new):
    assert t.count(old) == 1, old[:60]
    return t.replace(old, new)


def ptr(t):
    slim_plans = line_of(
        t.splitlines(keepends=True), "Load the plan-conventions skill before"
    )
    t = one(
        t, slim_plans, line_of(full, "Plan/design/roadmap docs accumulate decisions")
    )
    return one(
        t,
        "The manual-command-delivery skill holds the full rule; load it before asking the user to run anything.",
        "Full rule → the **manual-command-delivery** skill.",
    )


def ledger(t):
    assert "`scripts/wrap-ledger.sh" in t
    return t.replace("`scripts/wrap-ledger.sh", "`~/.claude/scripts/wrap-ledger.sh")


REFUSE = (
    "- A permission refusal (a command that needs approval, an auto-mode deny) is an answer for that action. "
    "Do not re-issue it split, reworded or through another path such as `git -C`; stop and hand it back as "
    "the one command to run.\n"
)


def refuse(t):
    anchor = line_of(
        t.splitlines(keepends=True), "- Do not `git add -f` gitignored paths."
    )
    return one(t, anchor, anchor + REFUSE)


for name, fns in {
    "r3ptr": [ptr],
    "r3ledger": [ledger],
    "r3both": [ptr, ledger],
    "r3refuse": [ptr, ledger, refuse],
}.items():
    t = slim
    for f in fns:
        t = f(t)
    d = f"{A}/{name}"
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(f"{A}/slim", d)
    open(f"{d}/CLAUDE.md", "w").write(t)
    print(f"{name}: {len(t)} chars (slim {len(slim)})")
