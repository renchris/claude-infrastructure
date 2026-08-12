---
status: open
---

# MASTER: convergence deadlock — trunk advances and the live layer does not

**Condition key:** `master-convergence-deadlock` · **Live members 2026-08-12:** 82 (55 open · 27 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-convergence-deadlock" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Twenty-plus members are literally the same sentence with a different sha:
*"converge the live layer — deploy-live REFUSES, no GREEN tree descends live HEAD."* They are all one
causal chain: `tests/autonomy-sweep.bats` hangs → `postland-verify` stamps no GREEN tree →
`deploy-live.sh` is fail-closed on a GREEN stamp → `~/.claude` runs older bytes → every landed fix in
this repo is inert. Measured 104 commits behind across eight correct analyses that landed and changed
nothing. Fix the head of the chain once and most of this group closes as a consequence.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **C1 · unhang the verifier** | **S** | a GREEN `postland-verify` stamp exists on a tree descending live HEAD | — |
| **C2 · converge** | **L** (lead-inline) | `bash scripts/deploy-live.sh` advances; live lag inside budget | C1 |
| **C3 · refusal taxonomy** | **S** | every `deploy-live` refusal names a cause a caller can act on | — (parallel) |
| **C4 · the per-sha generator** | **S** | one condition-keyed row per failing suite, not one per sha | — (parallel) |
| **C5 · close the chain** | **L** | the ~20 duplicate converge rows closed against the landed converge | C2 |

**C2 and C5 are lead-inline:** C2 is one command whose verdict must be read in the context that
requested it, and C5 is a loop over one store with no code to write.

**Lead context budget:** ≥50% held for adjudicating whether a refusal is a bug or a correct
fail-closed. **Succession point:** after C2 — the unhang and the converge are one context; the
taxonomy work is another.

## Sub-waves

### C1 · The head of the chain (filed as `35190812890d`)
W0 of the parent plan resized the fold's bound for the QoS band it actually runs in and measured the
probe block 94.1 s → 26.0 s, i.e. ~77 min → ~21 min across 49 tests. **Whether that is sufficient is
unproven** — the verifier's own `run_s` is the arbiter. Read
`ls -t ~/.claude/autonomy/postland/stamps | head -3` first; if a GREEN stamp already descends live
HEAD, C1 is done and C2 is one command.

⚠️ **A timeout that is ALWAYS hit is not a bound, it is a fixed cost.** Before sizing any bound in
this wave, measure whether the subject *completes* — the two cases respond oppositely to raising it.

### C2 · Converge, and read the ADD budget correctly
`bash scripts/deploy-live.sh`. Note the asymmetry the ledger encodes: an EDITED file rides its
per-file symlink and merely runs an older version (a real budget), but a file the landed diff **ADDS**
is *absent* — no link, and every consumer guard on it (`[ -f x ] && . x`) is a silent skip. So
`LIVE_ADDS > 0` breaches at a lag of 1.

### C3 · The refusal taxonomy
`deploy-live.sh`'s ff-only refusal names two causes, rules both out, then punts to a hand read — the
third cause is unnamed. `cc-blockers`' `deploy-wedged NO-GREEN-AHEAD` is unbudgeted, so it fires
through the benign in-budget state and carries no information. Both are alarm-polarity defects.

### C4 · The generator behind the pile
`postland` files ONE backlog row PER SHA for the same failing suite, so one defect mints N rows —
this is why the group is 82 and not 20. The cure is a condition-keyed row (the mechanism
`cc-backlog add --condition` exists for exactly this).

### C5 · Close the chain
Once a converge lands, most "converge the live layer onto <sha>" rows are discharged by it. Close
each with the converged sha as evidence — and verify the live layer BY CONTENT (the deployed file's
bytes), never by a commit count.

## Definition of done
`scripts/wrap-ledger.sh` reports the live layer inside its converge budget with `LIVE_ADDS=0`, a GREEN
stamp exists for the current trunk, and every member row is closed against that converge or carries a
named structural reason it cannot be.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 82 rows on this condition
  (35 pre-existing from the 2026-08-09 triage, 10 more by its verdict replay, the rest semantic).
