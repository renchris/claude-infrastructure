#!/usr/bin/env python3
"""Ranked hook-layer cuts with savings per 14 d, derived from measure/hooks_cost.json,
measure/hooks_repeat_rate.json and measure/hooks_sessionstart_audit.json.
Every saving is ESTIMATED = (measured $ of the touched slice) x (removable fraction, method named).
Writes measure/hooks_cuts.json.
"""

import collections
import json
import re

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
C = json.load(open(f"{BASE}/measure/hooks_cost.json"))
R = json.load(open(f"{BASE}/measure/hooks_repeat_rate.json"))
A = json.load(open(f"{BASE}/measure/hooks_sessionstart_audit.json"))
S = json.load(open(f"{BASE}/data/hooks_forced_samples.json"))
I = C["injections"]
W = {"reformat_close", "short_probe", "poll_rearm", "nothing"}


def inj(k, ev=None):
    v = I[k]
    if ev:
        return v["usd_by_event"].get(ev, 0), v["usd55_by_event"].get(ev, 0)
    return v["usd"], v["usd_at_opus55"]


def forced_waste(hook, reason_rx=None):
    u = u55 = n = 0.0
    fr = C["forced"][hook]
    ratio = fr["usd_at_opus55"] / fr["usd"]
    for s in S:
        if s["hooks"][0] != hook or s["cls"] not in W:
            continue
        if reason_rx and not re.search(reason_rx, s["reasons"][0]):
            continue
        u += s["usd"]
        n += 1
    return u, u * ratio, n


cuts = []


def add(rank_key, layer, what, base, frac, method, risk, cat, validate, rollback):
    cuts.append(
        dict(
            layer=layer,
            change=what,
            base_usd_14d=round(base[0], 2),
            base_usd_14d_at_opus55=round(base[1], 2),
            removable_fraction=round(frac, 2),
            est_saving_usd_14d=round(base[0] * frac, 1),
            est_saving_usd_14d_at_opus55=round(base[1] * frac, 1),
            method=method,
            quality_risk=risk,
            category=cat,
            validate=validate,
            rollback=rollback,
        )
    )


# F: forced turns
b = forced_waste("session-continue.sh", r"^🔧")
add(
    0,
    "Stop hook session-continue.sh (agent-armed 🔧 step)",
    "Do not re-block when the armed step is a WAIT whose completion already wakes the session (background Bash/Monitor/workflow "
    "live, or cc-await-ping armed), and never re-block with a reason identical to the last one when the forced turn in between "
    "wrote nothing (hysteresis). Keeps every block that leads to real work.",
    b[:2],
    0.6,
    f"MEASURED waste-likely forced turns under 🔧 ({b[2]:.0f} turns: re-format close / 1-2 response probes / re-arm / "
    "nothing, classifier hand-validated on a seeded sample) x 0.6 (ESTIMATED share that are waits or identical re-blocks)",
    "medium",
    "flag",
    "A/B via env flag on the hook: forced turns/context, $ per completed task, and count of sessions that "
    "went idle with 🔧 work left (must not rise)",
    "unset the flag",
)
b = forced_waste("/goal prompt hook (Claude Code built-in)")
add(
    0,
    "/goal (Claude Code built-in prompt Stop hook) + goal-inert-watch.sh",
    "Detect a goal whose evaluator keeps answering 'waiting on the operator' (N>=3 consecutive goal blocks whose forced turn "
    "wrote nothing) and surface ONE operator notice + recommend /goal clear, instead of letting it block every Stop.",
    b[:2],
    0.8,
    f"MEASURED waste-likely goal-forced turns ({b[2]:.0f} in 18 contexts; e.g. 'No drag.' state probes) x 0.8",
    "low",
    "propose",
    "count goal-forced turns per context before/after; operator-facing notice rate",
    "remove the watch branch",
)
b = forced_waste("session-continue.sh", r"^🔔")
add(
    0,
    "Stop hook session-continue.sh (🔔 WAKE FLOOR) + mailbox-wake-arm.sh",
    "Arm the inbox wake path mechanically (the asyncRewake SessionStart hook already exists) instead of blocking the model "
    "to arm cc-await-ping; stop blocking on a missing wake path.",
    b[:2],
    0.9,
    f"MEASURED: {b[2]:.0f} of 381 WAKE-FLOOR forced turns are re-arm/probe/nothing; x 0.9",
    "low",
    "flag",
    "sessions that miss peer mail (cc-notify reason=) must not rise; WAKE-FLOOR forced turns -> ~0",
    "revert the flag",
)
# I: injections
add(
    0,
    "Stop reasons (all Stop hooks; Claude Code sends each reason TWICE)",
    "Shorten every Stop block reason to <=200 chars (verdict + the one next step + a pointer to the full text in a file); "
    "report the double send (meta 'Stop hook feedback' + rendered hook_blocking_error) upstream.",
    (
        sum(
            I[k]["usd"]
            for k in [
                "session-continue.sh",
                "completion-assert.sh",
                "anti-deference-nudge.sh",
                "boundary-handoff.sh",
                "dispatch-assert.sh",
            ]
        ),
        sum(
            I[k]["usd_at_opus55"]
            for k in [
                "session-continue.sh",
                "completion-assert.sh",
                "anti-deference-nudge.sh",
                "boundary-handoff.sh",
                "dispatch-assert.sh",
            ]
        ),
    ),
    0.65,
    "MEASURED persistence $ of both copies; median reason 560-1,250 chars -> 200 = ~0.65 removable (ESTIMATED)",
    "medium",
    "flag",
    "forced-turn class mix and completion rate unchanged; reasons still name the next step",
    "revert text",
)
add(
    0,
    "SessionStart config-mirror-assert.sh",
    "Replace the FORKED name list (median 216 names, 90% settings.json.bak-* backups; 363 of 950 over the 10k persist cap) "
    "with a count + a path to the full list; filter backups out of FORKED.",
    inj("config-mirror-assert.sh"),
    0.95,
    "MEASURED $; element median 5,713 chars -> ~250 (ESTIMATED 0.95)",
    "low",
    "direct",
    "SessionStart chars per main context; the mirror check still runs and still pages on a real shadow",
    "git revert",
)
add(
    0,
    "UserPromptSubmit mailbox-drain.sh (🔔 wake-path nag)",
    "Emit the 'No inbox wake path armed' nag only when its state changes within a context (82% of 2,827 are repeats).",
    inj("mailbox-drain.sh [wake-path nag]"),
    R["mailbox-drain.sh [wake-path nag]"]["repeat_chars_share"],
    "MEASURED $ x MEASURED within-context repeat share (scripts/hooks_repeat_rate.py)",
    "low",
    "flag",
    "repeat share -> 0; watcher-arm rate unchanged",
    "revert",
)
add(
    0,
    "SessionStart dod-persist.sh (frozen DoD re-injection)",
    "Inject a DoD only when its capture belongs to this session's lineage (own sid or recorded predecessor); otherwise inject "
    "nothing. Today the repo-keyed store shows 'THE CURRENT CONTRACT' = the newest capture from ANY session: 43 contracts over "
    "683 injections, one shown to 248 sessions; first-prompt keyword match 9/535, hand check 7/8 unrelated; 608 of 683 are "
    "2,000-char previews of 16-100 KB files.",
    inj("dod-persist.sh"),
    0.95,
    "MEASURED $ x ESTIMATED 0.95 (share of injections not in the session's lineage)",
    "low (removes misdirection)",
    "flag",
    "completion-assert/wrap-ledger verdicts unchanged (they read the file, not the "
    "injection); count of sessions whose close cites a foreign scope",
    "revert",
)
add(
    0,
    "UserPromptSubmit memory-nudge.sh (MEMORY INDEX BUDGET, 2.7k chars/prompt)",
    "Emit once per context and on change; shrink to the number + the command.",
    inj("memory-nudge.sh"),
    0.8,
    f"MEASURED $; repeat share {R['memory-nudge.sh']['repeat_share']} + shrink 2.7k->~300 chars (ESTIMATED 0.8)",
    "low",
    "flag",
    "MEMORY.md stays under cap (the nudge's purpose)",
    "revert",
)
per = [
    "handoff-intent-nudge.sh",
    "research-precognition-nudge.sh",
    "cache-expiry-warning.sh",
    "agent-teams-enforce.sh",
    "plan-agent-teams-default.sh",
    "backup-before-write.sh",
]
add(
    0,
    "Per-prompt / per-tool nudges (" + ", ".join(per) + ")",
    "Dedupe within a context: emit a nudge only when its digit-normalized text differs from one already in the context.",
    (sum(I[k]["usd"] for k in per), sum(I[k]["usd_at_opus55"] for k in per)),
    sum(I[k]["usd"] * R[k]["repeat_chars_share"] for k in per)
    / sum(I[k]["usd"] for k in per),
    "MEASURED $ x MEASURED per-script within-context repeat share",
    "low",
    "flag",
    "behaviours the nudges target (team spawns, research fan-out) unchanged",
    "revert",
)
add(
    0,
    "SessionStart mailbox-drain.sh (peer mail re-forwarded at session start)",
    "At SessionStart drop forwarded messages whose ORIGIN is >24 h old (median origin age 163 h; 293/604 >7 d) and show a "
    "count + the listing command instead.",
    inj("mailbox-drain.sh [peer mail]", "hook_additional_context:SessionStart"),
    A["mail"]["origin_older_than_24h"] / A["mail"]["messages"],
    "MEASURED $ x MEASURED share of messages >24 h old at origin",
    "low",
    "flag",
    "no fresh (<24h) message dropped; cc-notify still lists all",
    "revert",
)
add(
    0,
    "SessionStart one-liners (session-index-start, setup-task/plan-symlinks, session-start MCP line, activation-watch, frontier-status)",
    "Drop the zero-information session-index line ('Recent: [today] (no summary) x3') and merge the rest into one line.",
    (
        sum(
            I[k]["usd"]
            for k in [
                "session-index-start.sh",
                "setup-task-symlinks.sh",
                "setup-plan-symlinks.sh",
                "session-start.sh",
                "activation-watch.sh",
                "frontier-status.sh",
            ]
        ),
        sum(
            I[k]["usd_at_opus55"]
            for k in [
                "session-index-start.sh",
                "setup-task-symlinks.sh",
                "setup-plan-symlinks.sh",
                "session-start.sh",
                "activation-watch.sh",
                "frontier-status.sh",
            ]
        ),
    ),
    0.4,
    "MEASURED $ x ESTIMATED 0.4",
    "low",
    "direct",
    "SessionStart chars per context",
    "git revert",
)
cuts.sort(key=lambda c: -c["est_saving_usd_14d"])
for i, c in enumerate(cuts, 1):
    c["rank"] = i
json.dump(cuts, open(f"{BASE}/measure/hooks_cuts.json", "w"), indent=1)
tot = sum(c["est_saving_usd_14d"] for c in cuts)
tot55 = sum(c["est_saving_usd_14d_at_opus55"] for c in cuts)
for c in cuts:
    print(
        f"{c['rank']:2d} {c['category']:8s} {c['est_saving_usd_14d']:7.1f} {c['est_saving_usd_14d_at_opus55']:6.1f} {c['quality_risk']:26s} {c['layer'][:70]}"
    )
print("total", round(tot), round(tot55))
