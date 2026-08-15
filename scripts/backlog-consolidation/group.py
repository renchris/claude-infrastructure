#!/usr/bin/env python3
"""Group ungrouped live backlog rows into wave-sized MASTER efforts — semantically.

WHY THIS EXISTS, AND WHY IT IS NOT DEDUPLICATION. The pile is ~93-95% genuinely
distinct work (three independent methods converged on a duplicate surplus of 28-38
rows, 5-7%, recoverable once). So shrinking the ROW COUNT is not the lever. The
binding constraint is SESSION COUNT against a load-bound box, and cc-backlog's
CONDITION LEASE is the mechanism that moves it: N rows sharing one condition cost
ONE session, because a claim on any of them refuses its live siblings. Measured
2026-08-12 before this ran — 129 of 545 live rows carried a condition, in 37 groups
of which 29 were n=1, i.e. about 8 real groups and ~416 one-session-each rows.

WHY THE KEY IS A HAND-WRITTEN TAXONOMY AND NOT A COMPUTED ONE. The mechanical key
(cc-backlog dups --mode mechanical, written by backlog-consolidation-trigger.sh
--fold) is the right tool for rows that are the SAME SENTENCE about the same
subject, and it is deliberately narrow because its own largest "cluster" of 14 was
NINE different stranded worktrees — folding those would have joined eight unrelated
pieces of work and, because the lease feeds the claim guard, REFUSED dispatch on all
nine. A key cannot tell "one effort wearing N rows" from "N efforts wearing one
sentence". A person can, once, per subsystem — so the judgment lives in TAXONOMY
below, as an ordered table of regexes over the row's own words, and every rule
carries the reason it exists.

WHAT MAKES THE COARSE GROUPING HONEST HERE, WHEN THE MECHANICAL ONE WAS NOT. A
master effort is not "one row's worth of work" — it is a WAVE, and it ships with a
plan file carrying its own Phase 0 wave table (docs/plans/master-*.md). One session
claims the condition, reads that roadmap, and fans out INSIDE itself. So joining
nine stranded worktrees under master-stranded-work is correct precisely because a
roadmap exists that sweeps all nine; joining them with no plan behind them, as the
sha key would have, is what refuses dispatch and delivers nothing.

TWO POPULATIONS ARE EXCLUDED, and the second one is a hazard, not a nicety:
  * a row that ALREADY carries a condition is never re-keyed (link refuses without
    --force, and this writer never passes it). The mechanical fold is more specific
    than any rule here, so where both would act, its answer stands.
  * a row that is CLAIMED-and-live is never joined. The lease is symmetric: linking
    a held row into a group makes every sibling in that group unclaimable for as
    long as the holder lives. Grouping is meant to stop duplicate dispatch, not to
    freeze a whole subsystem behind one worker.

CONSERVATION IS ASSERTED, NOT ASSUMED — same contract as the mechanical fold. A
`link` record carries no status arm, so the live count, the open count and the ID
SET must all be identical before and after. The id set is the load-bearing half: a
count reads unchanged after a sibling closes one row and opens another.

Dry by default. --apply writes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter

# ── THE TAXONOMY ────────────────────────────────────────────────────────────────
# ORDERED: first match wins. Order encodes precedence, and two precedences are
# deliberate and measured:
#
#  1. OPERATOR-GATED COMES FIRST. A row whose next step is a credential, a GUI
#     click, a physical act or a value judgment cannot be worked by any agent
#     session at all, whatever subsystem it is about. Routing it by subsystem puts
#     it in a wave that can only ever skip it; routing it by WHO CAN ACT collapses
#     the whole pile into one operator batch, which is what the close-time `👤`
#     rung and cc-do already render. Measured: this is the largest single family
#     after the re-lands.
#
#     THIS RULE IS NOW THE BACKFILL, NOT THE PRODUCER (2026-08-15, O3 of
#     docs/plans/MASTER_OPERATOR_GATED.md). `cc-backlog block --needs` keys the
#     row into master-operator-gated at FILING time — non-force, so it only ever
#     fills an EMPTY condition — which means every row minted since carries the
#     membership before any sweep can see it and this rule matches nothing new.
#     It stays for the rows filed BEFORE that landed, and as the record of why a
#     regex here was always the weaker instrument: it is strictly recovering a
#     fact the FILER already had. It lands `--needs "collect the live output of
#     X"` correctly on the imperative and misses `--needs "the operator must
#     paste the key"` entirely, routing it by subsystem into a wave that can only
#     skip it — the burn-a-slot-to-discover-it-cannot-act the plan file exists to
#     stop. Enforcement belongs at the chokepoint; this is the sweep it replaced.
#  2. THE REPO OUTRANKS THE SUBSYSTEM, so the project test comes SECOND. A
#     reso-management-app row reading "pnpm lint is RED on origin/main" is a reso
#     effort, not a claude-infrastructure verification effort: the tree it edits
#     decides which wave can work it, and no claude-infrastructure session has that
#     checkout. Ordering these rules last was the first version of this file and it
#     measured the cost — the subsystem regexes stole 43 of reso's 57 rows into
#     waves that could not have touched them. Only the operator gate above outranks
#     the repo, and for the same reason it outranks the subsystem: who can act at
#     all is prior to which tree it happens in.
#
# Each entry: (master, regex over the row's own words, why this rule exists).
TAXONOMY: list[tuple[str, str, str]] = [
    # ── 1 · who can act ────────────────────────────────────────────────────────
    (
        "master-operator-gated",
        r"^(decide|decide:|rule on|rule the|rule by eye|pick a|pick the|approve|ratify|"
        r"confirm with|sign in to|mint a|mint the|revoke|install the|open https|"
        r"set the|set turso|pre-grant|activate the interactive|run e\d|run docs/activation|"
        r"file apple feedback|collect the live|arm the|turn on the|re-link|link any)\b"
        r"|\bRULING\b|\bserver-side ruleset\b|\bGitHub (App|server-side)\b",
        "verb-initial imperative addressed to the operator: a decision, a credential, "
        "a GUI-only step or a physical act. No agent session can discharge it.",
    ),
    (
        "master-operator-gated",
        r"\b(needs? (a )?real tty|human-gated|web-only|GUI-only|judgment call|"
        r"NOT agent-actionable|one consent click|needs one consent|"
        r"needs the operator|operator-only|by hand \(|BY HAND\b)",
        "self-declared operator gate in the row's own words — the filer already "
        "measured that the step is not agent-reachable.",
    ),
    # ── 2 · which tree (one SLUG, but the lease is per-project) ────────────────
    # ONE slug covers both product repos, and that is a mechanism decision rather
    # than a tidiness one: cc-backlog keys a condition id on project+condition and
    # the sibling lease selects on `(.project) == $p` (bin/cc-backlog:1819), so this
    # single slug resolves to ONE INDEPENDENT LEASE GROUP PER PROJECT. A reso wave
    # and a doc_classifier wave can therefore run concurrently without either
    # refusing the other, while the store still reports one effort per repo. Two
    # slugs would buy exactly the same isolation and cost an extra effort against a
    # DoD that asks for a count countable on two hands.
    (
        "master-product-repos",
        r"^__project__:(reso|reso-management-app|reso-qa-runner|doc_classifier|"
        r"lakehouse-lecture|agent-build-hackathon)$",
        "a product repo's own backlog — a different tree, a different gate, and in "
        "reso's case a land that bills a real deploy. Per-project lease (see above), "
        "so this is one wave per repo, not one wave for all of them.",
    ),
    # ── 3 · claude-infrastructure subsystems ───────────────────────────────────
    (
        "master-stranded-work",
        r"(^re-land\b|\bSTRANDED\b|\bstranded (patch|commit|work)|"
        r"\bunlanded\b|\bcommits unlanded\b|\bsettle wt-|\bland branch\b|"
        r"\bmerge branch wt-|\bre-land\b)",
        "value sitting on a branch or in a worktree that never reached trunk. One "
        "sweep session re-lands them; 65+ rows, all one mechanism (ship-land exited "
        "5/6/143 and its auto-recovery did not finish the job).",
    ),
    (
        "master-convergence-deadlock",
        r"(deploy-live|\blive layer\b|live ~/\.claude|~/\.claude layer|\bconverge\b|"
        r"\bNO-GREEN-AHEAD\b|GREEN (stamp|tree|verifier)|no GREEN|postland[- ]verify|"
        r"\bpostland\b|deploy-parity|LIVE_ADDS|🚀 rung|wrap-ledger|"
        r"shared checkout .*(behind|stale)|stale bytes|deploy-wedged)",
        "the landed-but-not-live deadlock: trunk advances, the enforcing ~/.claude "
        "layer does not, because deploy-live is fail-closed on a GREEN stamp the "
        "verifier cannot produce. Nothing in ~/.claude can advance until it clears.",
    ),
    (
        "master-verification-integrity",
        r"(\blint\b|-lint\.sh|\bratchet\b|\bgate[_ -]red\b|\bland[- ]gate\b|"
        r"ship-land|\bbats\b|\btests?/|\bselftest\b|hermetic|\bred-proof\b|"
        r"\bvacuous\b|\bassertion(s)? (are|is) |dead-assertion|\bfixture\b|"
        r"\bpositive control\b|\bmutant\b|\bcorpus\b|\bCI\b|\bshellcheck\b|"
        r"\btypecheck\b|\bpnpm lint\b|eslint|"
        r"asserted by NOTHING|has NO gate|\bno gate\b|gate-select|\bTSV\b|comm-split)",
        "the instruments that decide red/green are themselves wrong: a lint blind to "
        "its own class, a gate collapsing could-not-run into red, a fixture that "
        "passes pre-fix. Every other wave's verification rides on these.",
    ),
    (
        "master-fire-gate",
        r"(cc-dispatch|\bdispatch(er|ed)?\b|\bfire[- ]gate\b|handoff-fire|\bfired? \b|"
        r"\bclaim\b|\blease\b|\bvenue\b|venuePlan|off-box|\bcloud\b|\bcc-cloud\b|"
        r"\bcapacity\b|\badmission\b|\badmit\b|\bceiling\b|\bconcurrenc|\bquota cliff\b|"
        r"\bspawn (gate|site|path)|Agent-tool spawn|\bwave-overflow\b|cc-eligible|"
        # NOT a bare \bbrief\b: it stole "restore the 5 guardrail hooks that
        # .claude-next alone is missing", whose headline merely used the word. Only
        # a brief that is the SUBJECT (stale, dispatched, composed) is this wave.
        r"(stale|dispatched) brief|\bbrief (is|reads)\b|cc-wave-plan)",
        "the spawn economy: what fires, where it runs, and what refuses it. This is "
        "the wave the operator feels — a refusal on their own handoff path.",
    ),
    (
        "master-session-lifecycle",
        r"(\brecycle\b|\bsuccession\b|\bsuccessor\b|self-close|self-retire|\bhandoff\b|"
        r"\bgoal\b|goal-inert|\bkeepalive\b|\bcustody\b|Stop-hook|stop hook|"
        r"session-continue|\bwrap\b|close-integrity|\bidle\b|context[- ](economy|recycle)|"
        r"\bcc-notify\b|\bmailbox\b|\binbox\b|\bcc-announce\b|dead-letter|"
        r"cross-session mail|\bcomms\b|two-way mail|\bcc-await-ping\b|\bengagement\b|"
        r"resume-sessions|reso-resume|\btranscript\b|\bcompact\b|"
        r"SessionStart|\bcc-bus\b|cc-roles)",
        "a session's own lifecycle and the channel between sessions: born, engaged, "
        "recycled, retired, and heard from. Fail-silent by nature — the whole family "
        "is 'it did not happen and nothing said so'.",
    ),
    (
        "master-fleet-footprint",
        r"(\bworktree(s)?\b|worktree-gc|\bpane(s)?\b|\bcc-pane\b|\bit2\b|\bkitty\b|"
        r"\bcc-reaper\b|\breap(ed|s|er)?\b|\bteardown\b|\borphan(ed)?\b|\bsprawl\b|"
        r"\bGC\b|\bgc\.auto\b|\bdisk\b|node_modules|\bRSS\b|\bmemory headroom\b|"
        r"\bdev-server\b|devserver|\btask-store\b|~/\.claude/tasks|\bhusk\b|"
        r"\bkernel panic\b|\bcompressor\b|\bjetsam\b|window-census|"
        r"\bsentinel\b|self-burst)",
        "what the fleet leaves on the box: panes, worktrees, processes, disk. The "
        "operator's machine is the shared resource every other wave spends.",
    ),
    (
        "master-account-facts",
        # NOT a bare \btoken\b or \bmodel\b. `token` stole a row about the zsh layer
        # rewriting a bare TOKEN in Bash-tool command text, and `model` collides with
        # this repo's own phrase "share the state model". Both are the generic-word
        # class the HEAD_CHARS note above describes: scoping the window shrinks the
        # blast radius, it does not make a one-word pattern specific.
        r"(\baccount(s)?\b|claude-accounts|\bnext[234]\b|\bauth\b|\blogin\b|\brelogin\b|"
        r"\boauth\b|\bkeychain\b|\brouter\b|\brouting\b|start[- ]latency|"
        r"\b(auth|API|bearer|setup|OAuth|refresh)[ -]token\b|"
        r"\bmodel-config\b|\bmodel (routing|pin|tier)\b|"
        r"\bproviders?\.json\b|\bMCP\b|\bmotion-plus\b|\bFable\b|"
        r"\bbinary advance\b|\bcodex\b|\bgpt-\d|"
        r"\bprovider|\bOpus \d|\bre-tier\b)",
        "which account, which model, which provider, and whether it can still "
        "authenticate. Every routing decision in the fleet reads these facts.",
    ),
    (
        "master-enforcing-store",
        r"(settings\.json|settings\.local\.json|\bmigration\b|\bactivation\b|"
        r"\bregister hooks?/|\bhook(s)?[- ](set|chain|parity)\b|\bhooks/|"
        r"MEMORY\.md|memory[- ]index|CLAUDE\.md|\bskills?\b|\bcommands?/|"
        r"\bconfig (drift|dirs|repair)\b|\b\.claude-next\b|install\.sh|\blaunchd\b|"
        r"\bplist\b|\bLaunchAgent\b|\bgit (config|init\.)|\.zshrc|com\.claude\.|"
        r"\bpermission(s)? (audit|gate)\b|\bhook layer\b|\bguardrail\b|"
        r"\basyncRewake\b|staged migration|memory-econ|"
        # THE WORK LEDGER IS AN ENFORCING STORE TOO, and that is why this rule owns
        # the backlog's own hygiene rather than a separate eleventh master. The
        # repo's standing lesson is that docs/plans ADVISE and only a store BINDS —
        # and cc-backlog is the store that makes a FINDING binding. A row about a
        # disproved premise, an un-attachable falsifier, or a fold that mis-reads an
        # event is the same defect class as a hook that was never registered: the
        # conclusion exists and nothing enforces it.
        r"\bDISPROOF\b|PREMISE (PARTLY )?REFUTED|EVIDENCE FOR OPEN ITEM|"
        r"\bfalsifier\b|cc-backlog|cc-value|cc-premise|backlog items?\b|"
        r"plan-open items)",
        "a conclusion only counts where it is ENFORCED — settings.json, a launchd "
        "plist, a PATH entry, a registered hook, and the work ledger itself. Docs "
        "and plans advise; these bind.",
    ),
]

_COMPILED = [(m, re.compile(p, re.I), why) for m, p, why in TAXONOMY]

# Every master this taxonomy can emit, in taxonomy order, de-duplicated. The plan
# file for each one is what W4 executes, so a master with no plan file is a wave
# nobody can run — asserted by tests/backlog-grouping.bats.
MASTERS: list[str] = list(dict.fromkeys(m for m, _, _ in TAXONOMY))


# THE MATCH WINDOW, and it is the single most important number in this file.
#
# A backlog "title" here is not a title, it is a PARAGRAPH: measured over the 418
# ungrouped live rows, p50 = 299 characters, p90 = 1251, max = 2558. Matching a
# generic word anywhere in 1251 characters is not classification, it is a lottery —
# and the first version of this file lost it four separate ways, every one of them
# an incidental mention rather than a wrong judgment:
#
#   * `token`     matched a row whose subject was ATTACHING EVIDENCE to a sibling,
#                 because "token" appeared in its closing sentence  → master-account-facts
#   * `codex`     matched a lint-rung row via a docs/plans/CODEX* path in its dodRef
#   * `by hand`   matched "19 skills live in ~/.claude/skills…"     → master-operator-gated
#   * `human-gated` matched the MEMORY.md-over-budget row, which is ordinary agent
#                 work that merely NOTES that one half of its remedy is gated
#
# All four are agent-workable rows routed into waves that could not work them. The
# fix is not a longer denylist of words — it is to ask the question where the answer
# actually lives: A ROW'S DISPOSITION IS IN ITS OPENING CLAUSE, and the tail is
# context, citation and measurement. So every rule matches against the HEADLINE
# (the first HEAD_CHARS of the title) plus the two identifier fields, never the
# whole paragraph.
#
# THE RECALL COST WAS REAL, AND IT WAS PAID DELIBERATELY. This comment first read
# "recall cost, measured: 0 rows" — written before the measurement, and the
# measurement refuted it: narrowing the window took the residue from 14 rows to 31,
# because a paragraph-long title really does name its subsystem late sometimes.
# What closed the gap was not widening the window back but writing the FAMILIES the
# residue exposed (the ledger-hygiene family, the banner rulings, the plan-open
# `advance <PLAN>` rows), which took it to 3. That is the trade this file wants:
# narrow window plus explicit families beats wide window plus incidental hits,
# because a missed row lands in a residue a human reads, while a wrongly-matched
# row lands in a wave that cannot work it and nobody looks again.
HEAD_CHARS = 120


def row_text(row: dict) -> str:
    """The row's OWN WORDS, in the order a reader would weigh them.

    title first and always; then dodRef and source, which is what makes the
    `plan-open` family classifiable at all — those rows are titled "advance <PLAN
    NAME>" and the plan path is the only token that says which subsystem they are.
    `evidence` and `needs` are deliberately EXCLUDED: they are the longest fields,
    they quote other rows verbatim (a needs line naming three sibling ids drags
    their vocabulary in), and a classifier keyed on them would group by who was
    cited rather than by what the work is.

    UNDERSCORES BECOME SPACES, and this is the correction that made the plan-open
    family classifiable at all. `_` is a WORD character, so `\bROUTER\b` does not
    match inside `START_LATENCY_ROUTER` — and the whole `advance <PLAN NAME>`
    population is titled in SCREAMING_SNAKE, as are the dodRef paths
    (docs/plans/SESSION_LIFECYCLE_V2.md). Measured: every plan-open row fell
    through to the residue for this reason alone, including four whose subsystem is
    named unambiguously in their own title.
    """
    head = str(row.get("title") or "")[:HEAD_CHARS]
    raw = " ".join([head, str(row.get("dodRef") or ""), str(row.get("source") or "")])
    return raw.replace("_", " ").strip()


def classify(row: dict) -> tuple[str | None, str | None]:
    """→ (master, rule-why) or (None, None) for the residue.

    The project test is spelled as a pseudo-token (`__project__:<name>`) rather
    than a separate field on the rule, so the whole taxonomy stays ONE ordered
    list with one matching rule. A second matching mechanism is a second thing to
    keep in agreement with the first.
    """
    text = row_text(row)
    proj = f"__project__:{row.get('project') or ''}"
    for master, rx, why in _COMPILED:
        if rx.search(text) or rx.search(proj):
            return master, why
    return None, None


# ── the store, read through its one owner ───────────────────────────────────────
LIVE = ("open", "blocked", "claimed")


def backlog_bin(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("CC_BACKLOG_BIN")
    if env:
        return env
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    local = os.path.join(here, "bin", "cc-backlog")
    return local if os.path.exists(local) else "cc-backlog"


def read_store(bin_path: str) -> list[dict]:
    """The FOLD, never the raw ledger — cc-backlog owns what an item's state is."""
    p = subprocess.run(
        [bin_path, "list", "--all", "--json"], capture_output=True, text=True
    )
    if p.returncode != 0:
        print(
            f"group.py: cc-backlog list failed rc={p.returncode}: "
            f"{p.stderr.strip()[:200]}",
            file=sys.stderr,
        )
        return []
    try:
        return json.loads(p.stdout or "[]")
    except json.JSONDecodeError as exc:
        print(f"group.py: cc-backlog list emitted non-JSON: {exc}", file=sys.stderr)
        return []


def plan_for(
    items: list[dict],
) -> tuple[list[tuple[str, str, str]], list[dict], list[dict]]:
    """→ (plan, residue, skipped-because-claimed).

    plan is [(id, master, why)] for rows this writer may join.
    """
    # THESE THREE SKIPS ARE A PRE-FILTER, NOT THE ENFORCEMENT — and the distinction is measured, not
    # stylistic. Mutation-testing this function found that deleting the already-conditioned skip left
    # the whole suite GREEN, because link.py applies the same predicate downstream and `cc-backlog
    # link` itself refuses a re-key with rc 4. So there are three copies of one rule and only the
    # last two can actually refuse a write. That is the shape this repo pins as a defect when the
    # pre-filter is allowed to be the STRONGER of the two (memory: cost-gate-must-be-strictly-weaker):
    # a fast path that shadows its own predicate hides whether the predicate still works.
    #
    # Kept anyway, deliberately: skipping here is what makes `--json` and the residue count HONEST
    # (a row link.py would refuse must not be reported as "would link"), and it keeps the dry run
    # truthful without a write. What follows from that is a testing obligation rather than a code
    # change — the per-site tests for these rules live against link.py, the writer that enforces
    # them, and tests/backlog-grouping.bats says so at each one.
    plan: list[tuple[str, str, str]] = []
    residue: list[dict] = []
    held: list[dict] = []
    for row in items:
        if row.get("status") not in LIVE:
            continue
        if row.get("condition"):
            continue  # never re-key: the mechanical fold and any human hand win
        if row.get("status") == "claimed":
            held.append(row)  # THE LEASE HAZARD — see the module docstring
            continue
        master, why = classify(row)
        if master:
            plan.append((row["id"], master, why or ""))
        else:
            residue.append(row)
    return plan, residue, held


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument(
        "--apply", action="store_true", help="write the links (default: dry)"
    )
    ap.add_argument("--json", action="store_true", help="machine-readable summary")
    ap.add_argument("--bin", default=None, help="path to cc-backlog (tests)")
    ap.add_argument(
        "--residue", action="store_true", help="print the unclassified rows in full"
    )
    args = ap.parse_args()

    bin_path = backlog_bin(args.bin)
    items = read_store(bin_path)
    if not items:
        print("group.py: empty or unreadable store — nothing to group", file=sys.stderr)
        return 0

    plan, residue, held = plan_for(items)
    live_rows = [i for i in items if i.get("status") in LIVE]
    already = [i for i in live_rows if i.get("condition")]
    by_master = Counter(m for _, m, _ in plan)
    # The effort count after this run: every master that will carry >=1 row, plus
    # every condition group that already exists. Reported honestly rather than as
    # the master count alone — a reader counting groups in the store sees both.
    existing_groups = sorted({i["condition"] for i in already})
    after_masters = sorted(
        set(by_master) | {g for g in existing_groups if g.startswith("master-")}
    )

    if args.json:
        print(
            json.dumps(
                {
                    "live": len(live_rows),
                    "grouped_before": len(already),
                    "ungrouped_before": len(live_rows) - len(already),
                    "would_link": len(plan),
                    "ungrouped_after": len(residue) + len(held),
                    "residue": len(residue),
                    "claimed_skipped": len(held),
                    "masters": {k: v for k, v in sorted(by_master.items())},
                    "master_efforts_after": len(after_masters),
                    "condition_groups_before": len(existing_groups),
                    "applied": bool(args.apply),
                },
                indent=1,
            )
        )
    else:
        print(
            f"live {len(live_rows)} · grouped {len(already)} · ungrouped "
            f"{len(live_rows) - len(already)} → would link {len(plan)}"
        )
        for m, n in sorted(by_master.items(), key=lambda kv: -kv[1]):
            print(f"  {n:4d} -> {m}")
        print(
            f"  residue {len(residue)} unclassified · {len(held)} claimed "
            f"(left alone: joining a held row freezes its whole group)"
        )
        print(f"  master efforts after this run: {len(after_masters)}")
        if args.residue:
            print(
                "\nRESIDUE — no rule matched (these are the ones a human must look at):"
            )
            for r in residue:
                print(f"  {r['id']} [{r.get('status')}] {(r.get('title') or '')[:96]}")

    if not args.apply:
        if not args.json:
            print("  … DRY RUN — nothing written. Pass --apply to write the links.")
        return 0

    # THE WRITE GOES THROUGH link.py, which is this file's whole relationship with
    # it: this file CLASSIFIES and that one WRITES. Two reasons, and the second is
    # the one that made it worth a subprocess:
    #   1. ONE WRITER means one place asserting conservation, one place holding the
    #      three skip rules, and one place a test has to red-prove. A second writer
    #      here would be a sibling auditor of the same population, which is this
    #      repo's most repeated defect (memory: sibling-auditors-must-share-the-
    #      state-model).
    #   2. link.py is the script W2 exists to rescue — untracked, no caller, one
    #      `git clean` from gone. Tracking it while routing around it would have
    #      left it exactly as inert as it was found, with the added lie of looking
    #      maintained.
    writer = os.path.join(os.path.dirname(os.path.abspath(__file__)), "link.py")
    payload = json.dumps([[iid, master] for iid, master, _ in plan])
    p = subprocess.run(
        [sys.executable, writer, "--plan", "-", "--run", "--bin", bin_path],
        input=payload,
        capture_output=True,
        text=True,
    )
    sys.stdout.write(p.stdout)
    sys.stderr.write(p.stderr)
    return p.returncode


if __name__ == "__main__":
    sys.exit(main())
