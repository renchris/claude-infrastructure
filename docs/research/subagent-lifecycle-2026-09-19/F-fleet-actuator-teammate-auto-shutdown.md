# F — The TeammateIdle closer: decision tree, outcome census, latency, refusal verdicts

Source read-only at `~/Development/.worktrees/wt-research-subagent-lifecycle-2026-09-19` (= `origin/main`,
`adff31b2f`, 0 ahead / 0 behind). Log `~/.claude/logs/teammate-lifecycle.log` — 29,768 lines,
2026-04-03 → 2026-09-19, **100% of lines classified, 0 residual** (classifier
`/private/tmp/.../scratchpad/census.py`). Raw per-episode data: `F-close-latency.csv` beside this file.

**Live-layer parity checked first.** `~/.claude/hooks/teammate-auto-shutdown.sh` and
`~/.claude/scripts/reap-guard.sh` are per-file symlinks into the shared checkout and are
**byte-identical to `origin/main`** (md5 `f6af1cb2bb2c2bdc44af1dc528243bbd`). The hook is registered in
both `~/.claude/settings.json` and `~/.claude-quaternary/settings.json` as
`TeammateIdle → ~/.claude/hooks/teammate-auto-shutdown.sh`, **`timeout: 5`**. So every verdict below is
about running code, not about a landed-but-inert file.

## Headline

| | |
|---|---|
| Gates that can DEFER | 6 (3 bounded by `MAX_DEFERS`, **3 unbounded**) |
| Gates that SURFACE (deliberate never-close) | 2 |
| Gate that REAPs | 1 — `reap-guard decide` rc 0 (`reap-guard.sh:235`) |
| Reaps that passed every gate, 14 d | 177 |
| …of which the pane actually closed | **98 (55.4%)** |
| …refused by the identity pin (rc 66) | 38 (21.5%) — **every one of them "payload from kitty ls is unreadable"** |
| …refused by the composer guard (rc 67) | 30 (16.9%) — **every one of them composer state `UNKNOWN`, never `NON-EMPTY`** |
| …hook died inside its 5 s budget | 11 (6.2%) |
| Does `MAX_DEFERS` discharge into a reap? | **Not on the dirty-tree axis — structurally it cannot.** On a shared cwd it discharges into SURFACE (155 times since the 2026-08-01 fix). The off-by-one IS fixed: last `(3/3)` line 2026-08-01 23:22:21, zero since. |
| Median time first-observable-event → `✓ closed pane`, 30 d | **5 s** (p75 188 s, p90 872 s, p95 2,893 s, max 13,361 s) |
| (team, member) pairs that fired ≥1 and never closed, 30 d | **17 of 218 (7.8%)** |

**The one sentence.** D1 of `TEAMMATE_SELFCLOSE_INVESTIGATION.md` is confirmed on mechanism and
obsolete on blast radius — the dirty-tree `MAX_DEFERS` backstop still cannot discharge (reap-guard
re-convicts one gate later), but the 2026-08-03/04 per-file attribution made that path rare (363
"NOT my dirt" exonerations vs 74 "IS my dirt" in 30 d), and **the binding constraint has moved from the
GATES to the ACTUATOR**: in the last 14 days the gates said REAP 177 times and the pane closed 98 times.

---

## (i) The ordered gate list, with file:line

Top-level control flow of `hooks/teammate-auto-shutdown.sh` (1,325 lines). Execution order = file order.
"D" = can defer, "S" = can surface (log + damped desk page, never closes), "R" = can reap.

| # | Gate | file:line | Bounded by `MAX_DEFERS`? | Class |
|---|---|---|---|---|
| 0 | Kill switch `TEAMMATE_SHUTDOWN_DISABLED=1` | `:58-60` | — | silent exit, no log line |
| 1 | Worktree resolution, 5 legs: env/manifest → team-config members → **member-name worktree** → `/tmp/wt-*-<m>` glob → **team-config `cwd` (gate-only, never removable)** | `:611`, `:638`, `:667`, `:743-757`, `:760-787` | — | sets `WORKTREE`, `WORKTREE_OWNED` |
| 1b | **Shared-cwd detection** — `jq` counts members recording the same `cwd`; >1 ⇒ `WORKTREE_OWNED=false`, "removal refused" | `:784` | — | info (gates still run) |
| 2 | **`.teammate-busy` cooperative marker** | `:791-794` | **NO — unbounded** | D |
| 3 | **Dirty tree** — `git status --porcelain \| grep .` (drained, not `-q`; the SIGPIPE inversion band is documented at `:806-818` with per-size measurements) | `:815` read, `:886` log | YES | D |
| 3b | **Own-footprint attribution** on a shared cwd — `session_dirty_mine` from `hooks/lib/session-writes.sh`; rc 1 clears, rc 0 ⇒ `dirty-mine`, rc 2 ⇒ `unknown` (fail-closed) | `:821-870`; logs `:862` (not mine) / `:865` (mine) | — | modifies gate 3, computes `TREE_VERDICT` |
| 4 | **Tool-in-flight** — reads the teammate's own transcript for an outstanding `tool_use` | `:904-908` | **NO — unbounded by design** (`:899-901`) | D |
| 5 | **`reap-guard decide`** (the one REAP authority) with `--tree-scope owned\|shared --tree-verdict clean\|dirty-mine\|unknown --session-id` | call `:983`; spawn-time resolution `:918-950` | mixed (below) | D / **R** |
| 5a | rc 11 on a shared cwd = own-footprint hold; rc 10 = WHO/WHEN hold; rc 2 = usage error (named separately at `:990-993`) | `:985-988` | YES (shared only) | D |
| 5b | `MAX_DEFERS` reached on a shared cwd ⇒ **SURFACE, never close** | `:996-999` | — | **S** |
| 5c | rc≠0 on an **owned** cwd ⇒ defer, **no counter increment, no surface, no bound** | `:1001-1003` | **NO — unbounded** | D |
| 5d | reap-guard not executable ⇒ WARN + continue (degraded) | `:1012` | — | info — **0 occurrences ever** |
| 6 | **Fail-closed on unresolved `WORKTREE`** — a close with zero gates evaluated must be impossible | `:1027` defer, `:1031` SURFACE | YES | D / **S** |
| — | counter cleared, **reap committed** → `Auto-shutdown idle teammate:` | `:1042`, `:1045` | — | the log's reap marker |
| 7 | **Checkpoint** via `teammate-checkpoint.sh`, asserted **on the artifact** (`refs/wip/<m>/LAST` exists), not the exit code | `:1049-1071` | — | never blocks |
| 8 | **Fallback `/tmp` patch** if the tree is dirty (belt-and-suspenders) | `:1073-1095` | — | never blocks |
| 9 | Pane-id resolution: `config.json.tmuxPaneId` across **every** `~/.claude*/teams` root, then implicit-team env method | `:1098-1135` | — | — |
| 10 | **Operator-adoption hold** (second belt; reap-guard R-d is the first) — `ci_last_interactive_epoch`; rc 2 "unreadable" holds; lib absent ⇒ `_beat_or_hold` (`:492-510`) | `:1136-1233`; logs `:1203`, `:1218`, `:505` | — | **S** (holds + pages, never closes) — **0 occurrences ever** |
| 11 | PPID-forensic (log only, no kill) | `:1235` | — | info |
| 12 | `{"continue": false}` on stdout — stops the teammate's turn | `:1238` | — | — |
| 13 | **`pin_term_verdict`** — resolves `CC_TERM` *while still attached*, because the detached close is reparented to launchd and `cc-in-kitty`'s ancestry walk would then answer "not kitty" | `:1271-1285` | — | the fix for "no teammate pane closed since 2026-07-25" |
| 14 | **Detached close** after `sleep $CLOSE_GRACE_S` (3 s) → `close_and_log` → `it2 session close -f -s <pane>` (+ kitty identity pins) | `:1288-1306`; `close_and_log` `:267-329` | — | **the actuator** |
| 15 | **Worktree removal**, gated on `WORKTREE_OWNED` — `--force` discards uncommitted work, so a shared tree is never destroyed | `:1310-1319` removed, `:1321` kept | — | — |

`reap-guard.sh`'s own ladder, in its order (`cmd_decide` at `:126`): R-a birth grace `:152-155` (300 s
default, `:60`) → `.teammate-busy` `:159` → dirty tree, scope-split `:163-180` (shared ⇒ `dirty-mine`
`:169` / `unattributable` `:172`, both rc **11**) → R-b effect-read `:186-200` (the whole-tree commit
clause is **deleted** on a shared cwd, `:103-112`) → R-d operator adoption `:205-232`
(`adoption-unresolvable` `:214`, `adoption-unreadable` `:222`, `operator-adopted` `:228`) → **REAP**
`:234-235`. Exit-code contract at `:15-20`: 0 REAP, 10 WHO/WHEN defer, 11 shared-tree own-footprint
defer, 2 usage error.

**Answering the brief's gate list directly:** birth-grace lives in reap-guard (`:152`), not in the
hook; there is no separate "shared-cwd gate" — sharing is a *modifier* that (a) makes removal refuse
(`hook:784`, `hook:1321`) and (b) swaps the whole-tree cleanliness question for per-file attribution
(`hook:821-870` → `reap-guard:163-180`); the operator-adoption hold exists **twice**, once in
reap-guard (R-d, fires) and once in the hook (`:1136-1233`, has never fired).

---

## (ii) Outcome census — classes derived from the log, not guessed

Distinct line shapes enumerated with `awk`/`sort`/`uniq`, then grouped; classifier reports 0
unclassified lines. Windows: 30 d = from 2026-08-20, 14 d = from 2026-09-05.

| Outcome class (emitting file:line) | all | 30 d | 14 d |
|---|---:|---:|---:|
| **REAP** gates passed — `Auto-shutdown idle teammate:` (`hook:1045`) | 16,268 | 333 | 177 |
| DEFER dirty-tree (`hook:886`) | 549 | 48 | 11 |
| DEFER reap-guard rc≠0 on SHARED cwd (`hook:987`) | 274 | 132 | 70 |
| DEFER reap-guard on SHARED cwd, pre-rc-split form (<2026-08-04) | 171 | 0 | 0 |
| DEFER WORKTREE unresolved (`hook:1027`) | 186 | 8 | 7 |
| DEFER reap-guard on OWNED cwd — **unbounded** (`hook:1001`) | 250 | 7 | 7 |
| DEFER `.teammate-busy` — **unbounded** (`hook:792`) | 42 | 12 | 12 |
| DEFER tool-in-flight — **unbounded** (`hook:906`) | 22 | 18 | 18 |
| **SURFACE** shared-cwd never reaps (`hook:996`) | 450 | 91 | 66 |
| **SURFACE** WORKTREE unresolved (`hook:1031`) | 96 | 9 | 9 |
| CLOSE `✓ closed pane`, absence-verified (`hook:307`) | 1,269 | 210 | 98 |
| CLOSE `~ already gone` (`hook:310`) | 265 | 1 | **0** |
| CLOSE `~ close_pane non-zero, likely-ok` (legacy) | 8 | 0 | 0 |
| CLOSE `✗ pane close FAILED (rc=…)` (`hook:320`) | 211 | 46 | 30 |
| CLOSE `✗ identity pin REFUSED` rc 66 (`hook:284`) | 189 | 65 | 43 |
| CLOSE `✗ actuator LIED, pane still present` (`hook:302`) | **0** | 0 | 0 |
| CLOSE `! no pane id resolved` (`hook:1306`) | 133 | **0** | 0 |
| HOLD operator-adopted (`hook:1218`) | **0** | 0 | 0 |
| HOLD who-oracle UNREADABLE (`hook:1203`) | **0** | 0 | 0 |
| HOLD presence UNPROVABLE / beat (`hook:505`) | **0** | 0 | 0 |
| WARN spawn-time UNRESOLVED (`hook:948`) | **0** | 0 | 0 |
| WARN reap-guard not executable (`hook:1012`) | **0** | 0 | 0 |
| info PPID-forensic (`hook:1235`) | 2,083 | 327 | 172 |
| info shared cwd → removal refused (`hook:784`) | 2,882 | 591 | 307 |
| info attribution: **NOT** my dirt (`hook:862`) | 822 | 363 | 231 |
| info attribution: **IS** my dirt (`hook:865`) | 463 | 74 | 13 |
| info pane via env (`hook:1132`) / via tty (`hook:1303`) | 2 / **0** | 0 | 0 |
| info checkpoint ref written (`hook:1067`) | 748 | 216 | 109 |
| info nothing to checkpoint (`hook:1069`) | 417 | 113 | 65 |
| info fallback `/tmp` patch (`hook:1094`) | 523 | 201 | 106 |
| info desk page suppressed (damped) | 307 | 89 | 69 |
| info worktree KEPT (shared) (`hook:1321`) | 940 | 288 | 137 |
| info worktree REMOVED (`hook:1318`) | 176 | 26 | 26 |
| legacy `Cleaned worktree:` (pre-2026-06 hook) | 22 | 0 | 0 |
| **TOTAL** | **29,768** | **3,268** | **1,783** |

🚨 **All-time is a mixed population and must not be quoted as one machine.** April 2026 alone is
13,976 lines / **13,921 reap lines / 0 `PPID-forensic` / 0 `✓ closed pane`** — the retired
`kill -TERM $PPID` era described in the hook header (`:29-35`). 47% of the log is a mechanism that no
longer exists. Use the 30 d / 14 d columns for any statement about today.

**Second, independent source — reap-guard's own decision records** (`~/.claude/reap-guard`, written by
`emit_record` `reap-guard.sh:81-90`; 2,177 files, 0 unparseable). This is not derived from the log:

| decision / reason_kind | all | 30 d | 14 d |
|---|---:|---:|---:|
| REAP / `shared-no-refs` (`reap-guard.sh:198`) | 764 | **254** | 126 |
| DEFER / `grace-held` (R-a, `:154`) | 698 | **213** | 140 |
| REAP / `finished` (`:234`) | 268 | 97 | 69 |
| DEFER / `dirty-tree-mine` (`:169`) | 191 | 27 | 5 |
| DEFER / `operator-adopted` (R-d, `:228`) | 106 | 5 | 2 |
| DEFER / `dirty-tree` (owned scope, `:176`) | 79 | **0** | 0 |
| DEFER / `no-products` (R-b, `:194`) | 71 | **0** | 0 |
| DEFER / `dirty-tree-unattributable` (`:172`) | **0** | 0 | 0 |
| DEFER / `adoption-unresolvable` (`:214`) / `adoption-unreadable` (`:222`) | **0** | 0 | 0 |

Two readings this store gives that the log cannot: **(1) the dominant REAP path today is
`shared-no-refs` — 254 of 351 reaps in 30 d (72%)**, i.e. the accepted residual named at
`reap-guard.sh:196-200` ("produced-nothing is reaped like produced-nothing-durable") is not a corner
case, it is the modal path. **(2) The birth grace (`grace-held`, 213/30 d) is now the single most
frequent defer of any kind, ahead of every tree-based one** — reap-guard is mostly answering "too
young", not "still dirty".

*Reconciliation caveat, stated rather than hidden:* 245 reap-guard DEFER records in 30 d vs 139
reap-guard defer log lines + 91 SURFACE lines = 230. The record store stamps UTC (`iso()`
`reap-guard.sh:78`) and the log stamps local; the residual (~15) is consistent with the window edge,
but I did not prove it and reap-guard has 8 other callers in-tree
(`hooks/teammate-checkpoint.sh`, `scripts/never-stuck-gate.sh`, `scripts/reaper-safety-gate.sh`,
`bin/cc-teardown-safety-gate.sh`, …), any of which could contribute records.

---

## (iii) Latency and the never-closed population

Episodes are keyed `(team, member)` and **split on a 6 h idle gap** — without the split, a recycled
member name manufactured a 907 h "latency". `F-close-latency.csv` has one row per episode (3,548 rows)
with both latency definitions, the fire/defer/surface counts, the failure events, and the last
defer/surface reason.

Two latencies are reported because the hook logs its reap marker **after every gate** (`:1045`):

- **gate-pass → `✓ closed pane`** measures only the actuator: median **4 s** in every window, p95 5-6 s.
  That is `CLOSE_GRACE_S=3` (`:77`) plus the `it2` round-trip. It carries no information about holding.
- **first observable event → `✓ closed pane`** is the number that answers "how long did the pane stand":

| window | n | min | p25 | med | p75 | p90 | p95 | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all-time | 1,269 | 0 s | 4 s | 4 s | 5 s | 188 s | 776 s | 13,361 s (3.7 h) |
| **30 d** | 210 | 0 s | 4 s | **5 s** | 188 s | 872 s | 2,893 s | 13,361 s |
| **14 d** | 98 | 0 s | 4 s | **5 s** | 6 s | 261 s | 448 s | 4,090 s (1.1 h) |

Bucketed, 30 d: `<10 s` 140 · `10-60 s` 6 · `1-5 m` 21 · `5-30 m` 27 · `30 m-2 h` 9 · `2-12 h` 7.
The distribution is bimodal by construction: a member that trips no gate closes in 4-5 s; a member that
defers waits for the *next* `TeammateIdle`, whose period is set by the teammate's own turn cadence, not
by the hook.

**Never-closed population.**

| window | (team,member) pairs that fired ≥1 | of those, never a `✓ close` | % |
|---|---:|---:|---:|
| all-time | 2,014 | **796** | 39.5% |
| 30 d | 218 | **17** | 7.8% |
| 14 d | 106 | **12** | 11.3% |

Reasons, per never-closed episode:

| reason | all | 30 d | 14 d |
|---|---:|---:|---:|
| gate-passed, then **no close-path line at all** (hook killed inside its 5 s budget, or the detached subshell died) | 715 | 14 | 8 |
| `rc=67` composer-guard refusal as the terminal state | 71 | 7 | 7 |
| `! no pane id resolved` | 55 | 0 | 0 |
| `rc=1` / `rc=4` actuator errors | 12 | 0 | 0 |
| still deferring, no terminal event | 10 | 0 | 0 |
| SURFACE as the terminal state | 1 | 0 | 0 |

🚨 **`rc=66` does not appear here, and that is a finding, not an omission.** Every identity-pin refusal
is retried on the member's *next* `TeammateIdle`, and in the log every rc-66 episode eventually
reaches a `✓ closed pane`. rc 66 costs a round of latency; rc 67 is the one that sticks.

The 715 all-time "no close-path line" are almost entirely April's retired mechanism. In the current
regime the leak is small but real and I can localise it: in 30 d, **333 reaps → 327 reached
`PPID-forensic` (`:1235`) → 322 produced a close verdict.** So ~11 invocations (3.3%) die between the
reap decision and the actuator — the checkpoint at `:1049-1071` plus `jq` over every team root is the
only unbounded work between them, and the harness kills the hook at `timeout: 5`.

**Currently stranded:** 38 members whose last defer (since 2026-08-20) has no follow-up event of any
kind — e.g. `lint-window-id (2/3): dirty tree` at 2026-09-19 10:59:41, `hooks-3 (2/3)` 2026-09-17,
`A1-openrouter (1/3) rc 10` 2026-09-16. A defer is not a scheduled retry: if the lead marks the member
`isActive:false`, the harness stops emitting `TeammateIdle` and the counter sits pinned forever — the
failure mode the `:872-882` comment measured (73 of 188 counters pinned at 3) and fixed the *cap* for,
but not the *no-more-events* half.

---

## (iv) Does `MAX_DEFERS` discharge into a reap?

**The off-by-one IS fixed and the fix is visible.** `(3/3)` lines: 79 total, first 2026-04-21, **last
2026-08-01 23:22:21, zero after**. That is the `DEFER_COUNT + 1 < MAX_DEFERS` change (`:872-884`,
mirrored at `:985` and `:1024`). Post-fix, events 1-2 defer and event 3 acts in the same invocation.

**What event 3 does depends on the axis, and only one of the two can end in a close:**

| last defer seen for a member → next event, within 24 h | all | since 2026-08-01 |
|---|---:|---:|
| `defer (2/3)` → **SURFACE** (pane never closes) | 155 | **155** |
| `defer (2/3)` → **reap line** (gates passed) | 55 | 53 |
| `defer (1/3)` → reap line | 53 | 50 |
| `defer (3/3)` → SURFACE | 29 | 1 |
| `defer (3/3)` → reap line | 4 | **0** |

🚨 **The dirty-tree `MAX_DEFERS` backstop cannot discharge into a reap while the tree is still dirty,
and this is structural, not a bug in the counter.** At event 3 rule 3 falls through *without*
incrementing (`:883`), then `reap-guard decide` runs (`:983`) and asks its **own** dirty question
(`reap-guard.sh:163-180`) — returning 11 on a shared tree with `dirty-mine`, or 10 on an owned tree.
On a shared tree `DEFER_COUNT` is still 2, so `:994` evaluates `2+1 < 3` false and the hook **SURFACEs**
(`:996`). On an **owned** tree it takes `:1001`, an unbounded defer with no counter and no surface.
Either way the cap hands the decision to a gate that re-answers the same question. **D1 of
`TEAMMATE_SELFCLOSE_INVESTIGATION.md` is therefore verified as written** — with one correction: it is
not that "the round-2 reap-guard defers again", it is that reap-guard defers on *every* round,
including the one the cap was supposed to force through.

The 53 post-fix `(2/3) → reap` cases are consistent with the tree having **become clean** (or
attribution clearing it) between events, not with the cap forcing anything: reap-guard would have
refused a still-dirty tree one gate later, and there is no log line in which it did not.

**Where the cap does work:** the `WORKTREE unresolved` axis (`:1015-1039`) has no second opinion below
it, so its cap discharges cleanly into SURFACE — 29 of the 33 `(3/3) → SURFACE` cases are
`WORKTREE unresolved`, and the post-fix form fires 9 times in 30 d.

---

## (v) Per-refusal-class verdict

Rule applied: **real hazard today** = a case exists now where removing the gate loses work or kills a
live conversation; **premise already handled** = another landed gate answers the same question first,
so this one is arithmetically unreachable or redundant; **catch-all** = fires on a class it cannot
discriminate, i.e. it refuses on *absence of evidence* without an arm that can ever acquit.

| # | Refusal class | 30 d | Verdict |
|---|---|---:|---|
| 1 | `.teammate-busy` marker (`hook:792`) | 12 | **Real hazard, cheap.** It is the only *cooperative* channel a teammate has to say "I am mid-multi-turn work"; nothing else in the ladder can be asserted by the member itself. Unbounded, which is correct for a signal the member can retract. Removing it: a teammate doing a long tool-free reasoning stretch with a clean tree is `shared-no-refs`-REAPed (the modal path, 254/30 d) mid-work. |
| 2 | Dirty tree (`hook:886`) | 48 | **Real hazard, but it is now the *attribution* that is load-bearing, not the whole-tree read.** In 30 d: 363 "NOT my dirt" exonerations vs 74 "IS my dirt". Removing the whole-tree read would be nearly free *today*; removing the attribution (`:821-870`) restores the 2026-08-03 failure it was built for — all five members of `session-ba3d4b59` deferring on a sibling's dirt (`:829-830`). Keep both: on an **owned** tree the whole-tree read IS this member's answer, and 13 members in 14 d were still held by `dirty-mine`. |
| 3 | Tool-in-flight (`hook:906`) | 18 | **Real hazard, and it is the only gate that reads positive evidence of LIFE.** Deliberately unbounded (`:899-901`) and deliberately independent of `$WORKTREE`, so it is the *only* gate covering a worktree-less teammate. 18 fires in 30 d, all in 14 d — it is live now, not historical. Removing it: a member mid-`tool_use` with a clean tree and no refs is exactly the `shared-no-refs` REAP profile; its turn is killed by `{"continue": false}` mid-call. |
| 4 | reap-guard R-a birth grace (`reap-guard.sh:152`) | 213 records | **Real hazard, and the highest-volume defer on the box.** 300 s. Note the coupled fault this survived: when spawn-time fell back to `date +%s`, 83% of decisions read "age 0 s" and the fleet reaped nothing for nine days (`hook:919-931`) — the grace is safe only because `joinedAt` now resolves it (0 `spawn-time UNRESOLVED` warnings ever). |
| 5 | reap-guard R-b effect-read `no-products` (`:194`) | **0** | **Premise already handled — on the shared path, deliberately and in-tree.** `has_products`' commit clause is vacuous on a shared cwd (`:95-101`), so `:188-199` drops the leg entirely and R-a carries the just-born case on the axis that actually measures youth. 0 records in 30 d because ~72% of decisions are `shared`. It is *not* dead code: it still fires on an owned tree, where its 71 all-time records live. **Do not delete** — removing it on the owned path reaps a member that produced nothing since spawn on a tree that looks finished. |
| 6 | reap-guard dirty-tree `unattributable` (`:172`) | **0** | **Fail-closed arm that has never fired — keep, with a named residual.** It is the rc-2 ("cannot attribute") half of the own-footprint question, and its 0-count is *evidence that the transcript path is healthy*, not that the arm is useless. The alarm-polarity risk is real (an arm that never fires carries no information), but the removal cost is asymmetric: without it, an unreadable transcript on a shared dirty tree reads as "a sibling's dirt" and the member is reaped over its own uncommitted work. |
| 7 | reap-guard R-d operator adoption (`:228`) | 5 records | **Real hazard, and the only WHO-gate that actually fires.** 106 all-time. This is the 2026-07-24 reaper incident class. |
| 8 | **The hook's own operator-adoption belt (`hook:1136-1233`)** | **0 ever** | **⚠ Unreachable in practice — and the log proves it, not an inference.** `⚑ operator-adopted:` (`:1218`), `⚑ who-oracle UNREADABLE` (`:1203`) and `⚑ presence UNPROVABLE` (`:505`) have **zero occurrences across 29,768 lines and six months**. Every "operator-adopted" string in the log comes from reap-guard's defer text or the SURFACE cause string. Reason: this belt sits *after* `:983`, and reap-guard's R-d answers the same question with the same hold window (`CC_CLASSIFY_INTERACTIVE_HOLD_S`, 21,600 s, read by both at `hook:72` and `reap-guard.sh:64`) from the same transcript — so the only world where belt 2 can speak is one where reap-guard did **not** run, i.e. `$WORKTREE` empty (which `:1015-1039` already refuses) or reap-guard non-executable (`hook:1012`, 0 occurrences ever). **This is NOT a recommendation to delete it** — see the adversarial pass; it is a recommendation to stop counting it as an active belt and to give it a deliberate liveness test, because a guard whose 0-count is indistinguishable from a broken one is the exact shape of `alarm-polarity-and-attention-budget`. |
| 9 | Fail-closed on unresolved `WORKTREE` (`hook:1027/:1031`) | 8 D + 9 S | **Real hazard, and the only gate protecting against an *ungated* close.** Every other gate is conditioned on `-n "$WORKTREE"`, so without this one a resolution miss silently no-ops all of them AND skips the checkpoint. Its cap discharges correctly (into SURFACE, which is the right terminal state for "no gate could run"). |
| 10 | SURFACE on shared-cwd after `MAX_DEFERS` (`hook:996`) | 91 | **Real hazard *and* an admitted dead end.** Its own remedy line says there is no spawn-side fix (`isolation:"worktree"` demotes to a paneless subagent, `:990-995`), so the only resolutions are "the member commits its own dirt" or "a human closes the pane". 91 fires in 30 d, 66 in 14 d, with the page damped to ~2/h. This is where the closer gives up. |
| 11 | **Identity pin, rc 66 (`hook:284` ← `it2-kitty:1224-1227`)** | 65 | **CATCH-ALL — and I reproduced the mechanism on the live binary.** 189/189 lines carry the identical stderr: `payload from kitty ls is unreadable`. Measured just now, read-only: `kitty @ --to $KITTY_LISTEN_ON ls --match id:99999999` returns **rc 1 with 0 bytes on stdout** and "No matching windows" on stderr. `identity_ok`'s python (`it2-kitty:637-643`) then hits `json.load` on empty input and reports "unreadable". **So an already-closed pane is indistinguishable from a wrong-window pin, and the guard reports the safe-sounding one.** The hazard it was built for is real (a kitty window id is a per-process counter and *was* observed closing an unrelated live window — `hook:169-184`), so the pin must stay. What is a catch-all is the *collapse of two states into one verdict*: the fix is a positive `no-matching-window` discrimination in `identity_ok` that returns "gone", not "unverifiable". Cost of leaving it: 65 spurious refusals in 30 d, each one round of `TeammateIdle` of extra pane residency, and a permanently depressed `✓ closed pane` health metric — which `scripts/teammate-reap-alarm.sh:148` reads as *the* health signal. |
| 12 | **Composer guard, rc 67 (`it2-kitty:1245-1257`)** | 46 total FAILED, of which **32 are rc 67** | **CATCH-ALL, and the worst one, because it is self-reinforcing.** 166/166 rc-67 lines carry composer state **`UNKNOWN`** — *never* `NON-EMPTY`. `UNKNOWN` is explicitly the "could not read the composer" branch (`it2-kitty:1249-1254`), not the "holds unsent text" branch. I matched 26 of these refusals to the snapshot the guard took at that instant (`~/.claude/logs/composer-snapshots`); the two I read (`20260908T062422Z-win542.txt`, `20260908T194115Z-win587.txt`) show **teammate panes reflowed to ~2 and ~14 columns**, one of them painting the hook's own `stopReason` text and an `@adj-cloud-refs ──` footer. That is precisely the failure `it2-kitty:891-900` already documents as measured on 2026-08-10 ("the LABEL EATS GLYPHS… seven of fifteen panes flipped into that state as the first eight closed… the bug HIDES ITSELF until the layout moves") — the `thresh = max(20, cols//2)` floor is unreachable below ~40 columns. **The loop:** each successful close reflows the survivors narrower → more survivors read `UNKNOWN` → more refusals → more survivors. It is the only refusal class that is terminal (7 of 12 never-closed episodes in 14 d). |
| 13 | `! no pane id resolved` (`hook:1306`) | **0 in 30 d** | **Premise already handled.** 133 all-time, all before 2026-08-20 — fixed by the `TEAM_ROOTS` scan over every `~/.claude*/teams` root (`hook:79-101`). Keep the arm (it is the honest terminal state when both resolution paths miss), but it is no longer a live failure class. The tty-method fallback beneath it (`hook:1300-1304`) has fired **0 times ever** — the env method at `:1132` fired twice. |
| 14 | `✗ close reported rc=0 but pane STILL PRESENT` (`hook:302`) | **0 ever** | **Real hazard, correctly built, never triggered.** `pane_present` (`:238-244`) is three-valued — an unreadable enumeration returns 2 and keeps the ✓ rather than manufacturing a failure. 0 occurrences means the actuator has not lied; it does not mean the check is idle. |

---

## Adversarial self-pass

Three hypotheses I formed, then tested against disk rather than asserting.

**H1 — "the `/tmp` fallback patch is a work-loss hazard, because `/tmp` evaporates on reboot."**
**REFUTED.** Per-invocation pairing over all 16,268 reap blocks: **`PATCH-BUT-NO-CHECKPOINT-REF` = 0**.
The patch is written only when `git status --porcelain` is non-empty (`:1082`), and a non-empty status
is exactly the condition under which `teammate-checkpoint.sh` writes `refs/wip/<m>/LAST`. The `/tmp`
patch is therefore never the sole record of a member's work — it is a genuine belt-and-suspenders, and
the "belt and suspenders shared one failure mode" concern the comment at `:1076-1081` raises was about
the *SIGPIPE inversion*, which the drained `grep .` closes on both.

**H2 — "rc 66 and rc 67 have the same root cause (an absent window), so both are benign."**
**HALF REFUTED, and the half that survives is the important one.** rc 66 is absent-window (probe above).
rc 67 is **not**: the composer guard runs *after* `identity_ok`, so a pane that reaches it passed the
pin and therefore exists in `kitty @ ls` — confirmed by the non-empty snapshots. They are two different
defects that happen to share a symptom. Reporting them as one would have prescribed the wrong fix for
the terminal class.

**H3 — "the hook's 5 s `timeout` is causing the missing close-path lines."**
**SUPPORTED, NOT PROVEN.** In 30 d the funnel is 333 reaps → 327 `PPID-forensic` → 322 close verdicts,
so 6 invocations die before `:1235` and 5 more before the detached block speaks. The work between
`:1045` and `:1235` is a `teammate-checkpoint.sh` fork, a `for-each-ref`, a `git status`, a `git diff
HEAD`, and a `jq` per team root — unbounded, inside a 5 s budget. I did **not** instrument the hook to
measure its wall time (that would mean writing to a live fleet path), so the attribution is inference
from the funnel shape, not measurement. An alternative I considered and could not exclude: the
detached subshell is killed with its process group when the harness reaps a timed-out hook, which
would produce the same 5-line gap.

**For every "redundant" verdict above, the concrete case removal would lose (as the brief requires):**

- Row 5 (`no-products`, 0 records/30 d): remove it and an **owned**-worktree member that is past the
  300 s grace, has committed nothing since spawn, and has a clean tree is reaped as "finished". Its 71
  all-time records are exactly that population. Redundancy is *scope-conditional*, and the scope flag
  is passed per call (`hook:980`).
- Row 8 (the hook's adoption belt, 0 fires ever): remove it and the *only* remaining who-gate for a
  teammate is reap-guard R-d, which is gated on `-n "$WORKTREE"` (`hook:975`). A worktree-less teammate
  would then reach `close_and_log` with **no** WHO check at all — the exact fail-open the `:1163-1177`
  comment says was measured on the incident fixture (a real operator prompt 950 s old, pane closed).
  The belt is unreachable *today* because `:1015-1039` refuses worktree-less members first; that
  refusal and this belt protect the same hole from two sides, and deleting either one makes the other
  load-bearing alone.
- Row 13 (`no pane id`, 0 in 30 d): remove it and the detached block's `else` branch falls off the end
  silently — the member's pane stays open with *no log line at all*, which is the one outcome
  `teammate-reap-alarm.sh` explicitly names as its blind spot (`:51`, "six real closes this instrument
  could not see").

**What a hostile reviewer would say I still have not checked, named rather than papered over:**

1. **I never established the denominator of TeammateIdle *invocations*.** The hook writes nothing on
   the kill-switch path (`:58-60`) and nothing when it exits before any gate logs, so "gates passed
   333 times in 30 d" has no measured "out of N fires". Every rate in this document is conditioned on
   an invocation that reached a log line.
2. **Team attribution for close lines is inferred.** `✓ closed pane <id> (<member>)` carries no team;
   I carry forward the last team seen for that member. A member name reused across two teams within
   6 h would mis-key. 30 d has 276 pairs and I did not audit for name collisions.
3. **`teammate-reap-alarm.sh` cites stale line numbers** — it points at `teammate-auto-shutdown.sh:837`
   for the reap line (now `:1045`) and `:620-:823` for the defers (now `:784-1039`). The *behaviour*
   it keys on (`grep "✓ closed pane"`, `grep -E "\] defer |⚑ SURFACE "`) is string-based and still
   correct, so this is citation rot, not a broken alarm — but it means the alarm's own comments no
   longer navigate to what they describe.
4. **I did not run `reap-guard.sh --selftest`** (it writes fixtures and exports env; the brief's
   read-only boundary made the cost/benefit clear), so every claim about reap-guard's exit codes is
   read from source + corroborated by the 2,177 records, not executed.
5. **The 38 "stranded" members are inferred from log silence.** Silence after a defer is consistent
   with *both* "the harness stopped emitting TeammateIdle" and "the pane was closed by some other
   actuator (`cc-teardown`, an operator, session end)". I did not check live panes — that would mean
   enumerating the fleet, and `kitty @ ls` against live teammate panes was outside what I was willing
   to do beyond the single absent-id probe.

---

## What is empirical vs inferred

| Claim | Basis |
|---|---|
| Every count in §(ii), §(iii) | **Empirical** — full-log classification, 0 unclassified |
| reap-guard decision distribution | **Empirical** — 2,177 JSON records, independent of the log |
| `(3/3)` ends 2026-08-01 23:22:21 | **Empirical** |
| `kitty @ ls --match id:<absent>` ⇒ rc 1, 0 bytes stdout | **Empirical** — probe run on the live kitty (pid 73832) this session |
| rc 67 panes were live and narrow | **Empirical** — 26 refusals matched to snapshots; 2 snapshots read |
| 644 of 844 composer snapshots are 0 bytes | **Empirical** — but **not attributable to this hook**: `it2-kitty` has other callers, and the 26 I could match to teammate rc-67 lines are all non-empty |
| Dirty-tree `MAX_DEFERS` cannot discharge into a reap | **Inferred from control flow** (`:883` → `:983` → `reap-guard.sh:163-180`), corroborated by 0 post-fix `(3/3) → reap` transitions |
| The 53 post-fix `(2/3) → reap` cases are trees that went clean | **Inferred** — the log records no tree state at event 3 |
| 5 s hook budget causes the 11/333 missing close verdicts | **Inferred** (H3 above) |
| Belt 8 is unreachable because reap-guard answers first | **Inferred from control flow**, corroborated by 0 fires in 29,768 lines |

## Re-derive

```bash
python3 /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/census.py   # §(ii)
python3 /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/final.py     # §(iii) + F-close-latency.csv
python3 /private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/e442434c-1a96-4c04-b06e-ac89c2f9891a/scratchpad/discharge.py # §(iv)
```

Those live in a session scratchpad and will not survive; the CSV beside this file is the durable
artifact. Re-run with `LC_ALL=C.UTF-8` — the default locale makes `sort` fail on this log with
"Illegal byte sequence".
