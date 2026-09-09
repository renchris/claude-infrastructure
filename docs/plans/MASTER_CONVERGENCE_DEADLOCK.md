---
status: complete
---

# MASTER: convergence deadlock — trunk advances and the live layer does not

**Condition key:** `master-convergence-deadlock` · **Live members 2026-08-12 (measured after the apply):** 89 (56 open · 33 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-convergence-deadlock" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort.** Twenty-plus members are literally the same sentence with a different sha:
*"converge the live layer — deploy-live REFUSES, no GREEN tree descends live HEAD."* They are all one
causal chain: `tests/autonomy-sweep.bats` hangs → `postland-verify` stamps no GREEN tree →
`deploy-live.sh` is fail-closed on a GREEN stamp → `~/.claude` runs older bytes → every landed fix in
this repo is inert. Measured 104 commits behind across eight correct analyses that landed and changed
nothing. Fix the head of the chain once and most of this group closes as a consequence.

## Phase 0 · Agent Team Orchestration

**Status**: DONE — the waves below all landed; kept verbatim as the record of how they were scoped.

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

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

**Status**: DONE — row `35190812890d` closed REFUTED on all three clauses (drain recycle #207, 2026-08-24).
W0 of the parent plan resized the fold's bound for the QoS band it actually runs in and measured the
probe block 94.1 s → 26.0 s, i.e. ~77 min → ~21 min across 49 tests. **Whether that is sufficient is
unproven** — the verifier's own `run_s` is the arbiter. Read
`ls -t ~/.claude/autonomy/postland/stamps | head -3` first; if a GREEN stamp already descends live
HEAD, C1 is done and C2 is one command.

⚠️ **A timeout that is ALWAYS hit is not a bound, it is a fixed cost.** Before sizing any bound in
this wave, measure whether the subject *completes* — the two cases respond oppositely to raising it.

### C2 · Converge, and read the ADD budget correctly

**Status**: DONE — `LIVE_ADDS` is measured from the converger's last DELIVERED sha (`LIVE_ADDS_BASE=advance`) and breaches at a lag of 1.
`bash scripts/deploy-live.sh`. Note the asymmetry the ledger encodes: an EDITED file rides its
per-file symlink and merely runs an older version (a real budget), but a file the landed diff **ADDS**
is *absent* — no link, and every consumer guard on it (`[ -f x ] && . x`) is a silent skip. So
`LIVE_ADDS > 0` breaches at a lag of 1.

### C3 · The refusal taxonomy

**Status**: DONE — `scripts/deploy-live.sh` carries the T1/T1H/T2/T3 ladder, and names the CULPRIT rather than punting to a hand read.
`deploy-live.sh`'s ff-only refusal names two causes, rules both out, then punts to a hand read — the
third cause is unnamed. `cc-blockers`' `deploy-wedged NO-GREEN-AHEAD` is unbudgeted, so it fires
through the benign in-budget state and carries no information. Both are alarm-polarity defects.

### C4 · The generator behind the pile

**Status**: DONE — `scripts/postland-verify.sh:860` `cond_slug()` derives a condition key per failing suite and joins rows with `cc-backlog link --condition` (`:925`), which dedupes without deleting the second row's content.
`postland` files ONE backlog row PER SHA for the same failing suite, so one defect mints N rows —
this is why the group is 82 and not 20. The cure is a condition-keyed row (the mechanism
`cc-backlog add --condition` exists for exactly this).

### C5 · Close the chain

**Status**: DONE — 101 of 106 members closed; 4 blocked on named operator gates; the 1 remaining open row was mis-conditioned and re-keyed off this condition (see the status log).
Once a converge lands, most "converge the live layer onto <sha>" rows are discharged by it. Close
each with the converged sha as evidence — and verify the live layer BY CONTENT (the deployed file's
bytes), never by a commit count.

## Definition of done
`scripts/wrap-ledger.sh` reports the live layer inside its converge budget with `LIVE_ADDS=0`, a GREEN
stamp exists for the current trunk, and every member row is closed against that converge or carries a
named structural reason it cannot be.

**Adjudicated 2026-09-09 — two of the three clauses are MET, and the third was refuted by this plan's
own cure.** Kept above verbatim; this is the reading, not a rewrite.

| Clause | Verdict 2026-09-09 | Measurement |
|---|---|---|
| live layer inside its converge budget, `LIVE_ADDS=0` | **MET** | `wrap-ledger.sh --machine`: `LIVE_LAG=17` `LIVE_ADDS=0` `LIVE_ADDS_BASE=advance` `MIG_FAILED=0`; `deploy-live --dry-run` (fetching, NOT `--offline`) reads *"lag 17 commit(s) / 3h26m, inside the degrade budget (25 / 6h)"* |
| a GREEN stamp exists for the current trunk | **REFUTED AS A DoD CLAUSE** — see below | no stamp for trunk tree `1b2770ba` or live tree `f4ed8d7a`; newest green on trunk is `24c598bac1c7` at depth 480, an ANCESTOR of live HEAD |
| every member row closed, or a named structural reason | **MET** | 106 members: 101 done · 4 blocked on named operator gates (a policy decision, a C10 live-layer delete, a real-TTY mint, a value fork) · 1 re-keyed off this condition as mis-filed |

**Why clause 2 cannot be a DoD clause, and why that is the cure working rather than failing.** The
clause asks the live layer to wait for a green tree on the CURRENT trunk. `deploy-live.sh:20-24` had
already measured why that deadlocks by construction — a green-only tier makes the green pointer
permanently lag trunk, and the moment any other writer advances live HEAD past it (per-file symlinks,
so *every* land does) the target is history and the lane refuses forever: 534 identical refusals, 276
launchd runs all exit 1, 91 commits stale, zero pages. The T1/T1H/T2/T3 ladder is the answer to
exactly this, and it is why the live layer converges today with no trunk-green in sight. **A DoD that
demands the state the cure was built to stop requiring is a deadlock restated as an acceptance test.**
The operative criterion is the one the ladder actually offers: *the live layer converges inside its
budget, and every refusal names a cause a caller can act on.* Both hold.

**The live residue, measured, and it is NOT this chain.** T1 (the *verified* tier) has been dark since
2026-09-04, and the cause is verifier STARVATION, not a red trunk — so it does not reopen the deadlock,
because T2 keeps converging on absence-of-red. Measured over `~/.claude/autonomy/postland/stamps`
(n=590; POS control "since 1970" = 590, NEG control "since 2099" = 0):

| | 08-27 → 09-03 | 09-04 → 09-09 |
|---|---|---|
| stamps | 73 (green 33 · cut 36 · red 4) | 35 (**green 0** · red 29 · cut 6) |
| `run_s` p50 | 3,180 s | **11,274 s** (3.5×) |
| `retries` p50 / max | 2 / 10 | **12 / 28** (6×) |
| `env.load` p50 / max | 15.8 / 43.0 | 21.8 / **140.5** |

The two leading suites in the post-09-04 `failing[]` lists **pass in isolation on this trunk**:
`tests/handoff-fire-completion-push.bats` 11/11 and `tests/idle-slope-sweep.bats` 16/16, both with
their `1..N` plan line present (a filtered TAP result with no plan line is not a pass —
`bin/cc-bats` refuses a run at 2 concurrent roots and load ≥ 2.0 and emits nothing on exit 0).
A red produced by a starved corpus is a FALSE red: it convicts trunk on evidence about contention,
and under the ladder's own stamp semantics (`red ⇒ ineligible, walk back one`) it costs T2 a commit
it should have accepted. That is a defect in the verifier's error channel, owned by its own row —
not by this condition, whose members are all closed.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 82 rows on this condition
  (35 pre-existing from the 2026-08-09 triage, 10 more by its verdict replay, the rest semantic).
- **2026-09-09 — CLOSED.** The deadlock is cured and the chain is drained; see § Definition of done
  for the clause-by-clause adjudication. Three things were settled that the plan could not have known
  when it was written:
  1. **The DoD's green-stamp clause is the deadlock restated as an acceptance test**, and the ladder
     in `deploy-live.sh` is what replaced it. Kept in the file, marked refuted, not deleted.
  2. **`d6d7edef60a3` was mis-conditioned onto this key and is re-keyed** to
     `handoff-fire-payload-gate-coverage`. It is a real, unfixed coverage hole in `handoff-fire`'s
     payload gates (`--recycle` runs neither `payload_pane_id_gate` nor `payload_lint_gate`) with
     nothing to do with the live layer; it stayed the last "open member" of a condition it never
     belonged to, which is how a drained group keeps re-presenting as unfinished. **A condition key
     is a claim about a shared CAUSE — a row that shares only a filing moment makes the group's own
     closure unreachable.**
  3. **The verifier's error channel now carries a false-red arm**, filed with its receipt as its own
     row. The measured separator is one-armed and says so: `retries >= 5` flags 29 of 33 post-09-04
     reds and **0 of 33** greens (green `retries` max out at 4; reds reach 28). That proves *greens
     never starve*, which is **not** the converse — nothing here can tell a starved red from a
     genuinely-broken tree that also retried, so the data can convict and cannot acquit. Turning a
     starved `red` into an eligible `cut` therefore loosens a fail-closed deploy gate on a proxy
     whose other arm is unmeasured, and that is the operator's call, not an implementation detail.
