# SYNTHESIS — exhaustive-drive wave, 2026-09-08

Role: synthesis over A01–A12, their 19 skeptic passes, CRITIC.md and LEAD-NOTES.md (31 files, 8,188
lines, all read in full). Read-only; this is the only file written. Every number below names the report
that holds it — `(A05)` = axis report, `(A05-sk)` / `(A05-sk2)` = its skeptic passes, `(CRITIC)`,
`(LEAD)` = LEAD-NOTES, `(SYN)` = a check this synthesis ran itself (commands in Appendix C). Convictions
are given as `axis → skeptic → synthesis`. `implement_now` = conviction ≥ 90 **and** no operator-only
gate. The A06 and A09 skeptic verdicts exist on disk nowhere but here (CRITIC U1); they are reproduced
in Appendices A and B so every citation to them is checkable.

---

## 1. Verdict — where sessions idle with drivable work left, and what is missing

**The wave was aimed at the Stop, and the Stop is where ≤ 24 % of sessions end.** Of 108 dead
main-chain sessions today, 26 (24 %) reached a clean Stop; 61 (56 %) retired themselves inside a Bash
call — `handoff-fire.sh self-close` 43, `--recycle` 7, `drain-recycle-fire.sh` 11 — and ~22 died on an
ordinary command, 22 of them carrying a > 300 s permission prompt (CRITIC §0). The twelve Stop hooks,
`/goal`, the caps, the close-shape contracts and the SAFE-TO-CLOSE certificate never run on a
self-close, and the self-close path checks a dirty tree and nothing else — not unlanded commits, not
the frozen-DoD remainder, not an open ⛔ (CRITIC §0.2; `handoff-fire.sh:6995-7010`, SYN). **The
terminal close of 56 % of today's sessions is audited by nothing.** Every per-Stop figure in this wave
is therefore a rate over the minority population, and the two largest measured idle channels are not
closes at all.

### 1a. The channels, by measured monthly count

| # | Channel (where the work is left) | Measured count (population, window) | Source | Mechanism missing | Status-quo fails |
|---|---|---|---|---|---|
| 1 | **Permission freeze** — a live session wedged mid-turn on a harness prompt | 3,046–3,053 prompts / **1,172–1,176 session-hours** blocked per 30 d (permission-archive; point estimate ~1,040 h after 84–89 % attribution); chronic **11–270 h/day** over 18 d; today 22–23 sessions / 83–85 h in 13.4–13.7 h; 45 of 49 freeze episodes had **zero** transcript activity; **99.3 %** of prompts were eventually GRANTED; the 11 overnight blocks (5.8–7.9 h) were batch-approved 12:57–12:58Z | A05 §1, A05-sk2 rows 1–3, A09 P1, A09-sk R2 | An OWNER for the prompt when the operator is absent. Detector exists (beacon); pager exists but its escalation ladder is landed-not-running (0 `permission_pending_escalate` in 5,155 records; daemon pid 31716 predates the checkout advance); the only human-facing channel (`push-critical.sh`) exits at :21-22 for want of Pushover credentials — decision `f91a9701ed21`, 51 days old | **Silent** — no Stop ever happens; every Stop-keyed arm is blind by construction |
| 2 | **Self-close / recycle with no ledger gate** | **61 of 108** dead sessions today (56 %); ~1,800/30 d **inferred** from one day | CRITIC §0 | A ledger stamp/gate on `handoff-fire self-close` and `--recycle` (the dirty-tree refusal at `:7003` is the template) | **Silent** |
| 3 | **A close that states a verified finding, names the fix, and stops** — clean ledger, no tell, no store | A02: ~890 idle closes / 30 d, band [484, 1,278]; skeptic-corrected **~550–700** (24 % of the denominator are non-closes; hand-read TRUE 29–35 % not 44 %); **permanence unmeasured** — both spot-checked items were harvested within 1–2 d (R-5 fixed `c7b2d45090` +1 d; `d0afa40677ef` closed +2 d) | A02 §3, A02-sk | A store for prose findings, or proof none is needed: the one arm built for this (`dispatch-assert` NAME_TELL) reaches **0.24 %** of close texts; every store-keyed arm is honestly silent because the ledger IS clean | Silent — but the size of the permanent loss is unknown; measure before building |
| 4 | **Capacity serialization** — a refused spawn is re-venued onto the lead's context | **20 of 20** refused Agent spawns today, **6 of 6** sessions, 0 filed, 0 retried; 3 of 6 sessions never got a budget release; refusals began 09-05 (0 in 159 evaluations 08-29→09-04) | A11 §2, A11-sk, A11-sk2 | A spool with an owner-side discharge; and `handoff-fire`'s own active-concurrency term is **blind on 48/48** production admits (source inside a `$( )`, `:5152` vs `:5360`) while the box ran 9–16 mid-turn against a ceiling of 8 | Silent on the plan (no store records the degradation), **open** on the box |
| 5 | **Mechanical 🔧 arm inert** — auto mode instructs `sed`/heredoc edits; `session-writes.sh:143` reads only Edit/Write tool records | `armed:mechanical-dirty` **2 of 672–826** evaluations (0.24–0.30 %); **82–88 %** of writer sessions are Bash-only (307/64/1 today); 4,521 of 11,869 Bash write idioms today target repo paths; `ship-floor-not-mine` 92–133 events / 11 d, ~70 % of them this oracle gap | A07 §6, A07-sk, A07-sk2, A09 P2 | Bash-write attribution — but the file's own header rejects the naive fix as the #105 false-conviction class | Silent (the discipline carries the load: 293–429 `cli-set` arms) |
| 6 | **Stop hooks killed at their budget** | **4,839–4,941** Stop-hook timeouts / 30 d; `completion-assert` **11.6 %** of closes (≈41 % of closes that reach the ledger); `operator-readout` 24.2 %; `session-continue` 2.9 % (but **15 %** of today's kills); daily rate **rose 0–6 % → 74–88 %** over three weeks as `backlog.jsonl` tripled | A01 §4, A01-sk, A01-sk2 | Bounded store reads on the ✅ path — the hot terms are `cc-backlog list --blocked` + `--all` + `cc-decide list` (4.4 of 5.7 s; 7.5 of 8.6 s), not lineage depth (0.17 s) and not transcript size (kill rate is flat-to-falling in MB); the memo's 750 ms single-flight ladder never fires (5 concurrent computes, ×1.6 each); `_bounded()` is a no-op for the **7/25** live sessions whose PATH lacks `/opt/homebrew/bin` | **Silent** — a killed Stop hook writes no IDL row, and the 2.1.260 renderer returns `null` for Stop on both `hook_cancelled` and `hook_error_during_execution` |
| 7 | **Task store unread, tools off** | 293 open items / 58 lists, **85 % > 30 d**, oldest 228 d; `TASKS.md` 102 KB with **0** consumers; `CLAUDE_CODE_ENABLE_TODO_TOOLS` unset in 5/5 settings.json; no migration exists; the tracking row `ebe84950e98a` closed 22:14Z with nothing replacing it | A03 §d, CRITIC C12 | The flip (one c10 migration), a `TaskCreated` attribution sidecar, a **lineage**-scoped reader | Silent — step 2 of the operator's workflow has no tracker |
| 8 | **`/goal` is a terminator, not a drive loop** | 434 of 641–642 runs never evaluated (67.7 %) — but **371 of 434 (85.5 %) had no Stop after arming**; 238 (55 %) self-closed/recycled inside a tool call; given a Stop the evaluator ran **68.9 %** of the time; **136 of 152** met goals carry exactly one evaluation; **375–449** `goal-unreadable` abstains are our own `grep | jq` under `pipefail` bug (54 of 56 transcripts contain zero `goal_status`) | A04 §2–3, A04-sk pass 2, CRITIC §0.3 | Nothing upstream: `--recycle` already inherits the goal (`handoff-fire.sh:4676-4684`, `CC_RECYCLE_GOAL_INHERIT=1`); fix the pipefail bug; stop treating `--goal` as the keep-working lever | Mixed — the bug is loud-mislabelled on the safe state |
| 9 | **Decisions with no live author** | 28–29 open class-C packets, median 13 d, p90 50, max 51; **1–3** authors alive ⇒ ⛔ unreachable for **96 %**; 220 blocked backlog rows p50 20.9 d, **143–146** via the ungated `needs` door, **0 of 348–355** live rows carry a conviction or receipt | A10 §5, A06 §3, A10-sk | An owner/re-attach rule for orphaned packets (Operator Decision 5) | Silent — they render as one counted `◆` line labelled "not blocking this close" |

**Not leaks (measured, and worth not re-litigating):** the kill switch (**1 abstain in 530 live Stops**,
0.19 %; today 0 of 477 sessions carry a kill phrase in their last genuine message — A08-sk, A07-sk2);
the caps (0 `CLAUDE_CONTINUE_MAX` trips / 11 d; harness cap **4–6 genuine hits / 30 d**, and its counter
**resets on every tool-use turn**, binary @164412526, so it catches only a text-only wedge — A07, A07-sk,
A12-sk2); transcript size (kill rate 15.5/100 closes < 1 MB, 0.0 ≥ 64 MB — A01 §4.2); config-dir drift
(Stop = 12 hooks in all four accounts — A12-sk2, though the fleet is **not** otherwise identical:
100/94/95/94 hooks, 21/20/20/20 events); the exemptions (narrow, recorded, defended in source — A07 §5).

### 1b. Corrections to the wave brief's premises (carry these, not the brief's wording)

| Premise in the brief | Correction | Source |
|---|---|---|
| "The IDL holds only 13 hours" | 8 gz archives exist from 2026-08-29T09:28Z — **11 days**; six axes censused the live file and called it "the IDL". A 4 KB `autonomy-sweep` record aborts `jq` at line 844,016, truncating any `jq` census (86,122 hook records tolerant vs 58,950 via jq) | CRITIC M5, A07-sk2 M1 |
| "`ENABLE_STOP_REVIEW="0"` — unknown feature, deliberately off?" | Not a binary variable (0/0/0 in 2.1.219/220/260) — it is the **security-guidance plugin's** Stop-review gate (`security_reminder_hook.py:162,:1910`), set deliberately on 2026-07-29 (backlog `022683ab85f3`: multi-agent worktrees break its diff review). Plugin installed, **not in `enabledPlugins`** of any account, log ends 07-30. Inert today, load-bearing the moment the plugin is enabled (a Stop hook with the 600 s default timeout). **Keep the line.** | A12-sk2, CRITIC C10 |
| "Task tools gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` or `tengu_rosy_wren`" | Correct, and the remote flag is **absent** from all five GrowthBook caches ⇒ the env var is the only lever; `$HOME/.claude.json` is stale since 08-11 — read the config-dir copy | A12-sk, A12-sk2 |
| "Dynamic Workflows are usually the optimal method" (operator's step 3) | Workflow is offered to **260/260** main sessions and to headless `-p`; **not** to research subagents; a Workflow unit costs **1.699 pp** vs **0.875 pp** for a dispatched session (workflows-vs-teams §3c); outcome quality **unmeasured** | A06 §4, LEAD §5, CRITIC M4 |
| "A goal dies with its session, so a recycle must re-arm it" (CLAUDE.md:185) | Dies with the **process**; **inherited by `--recycle`** when the condition passes pre-arm validation (`handoff-fire.sh:4676-4684`); **restored by `--resume`** (`tengu_goal_restored_on_resume`); **auto-cleared** at the context wall / auth / billing / model-not-found | CRITIC U7, A04 §1.4 |
| "`CLAUDE_CONTINUE_MAX` bounds runaway" (CLAUDE.md:502, :888) | Bounds only the mechanical arm (`CC_MECH_MAX × CLAUDE_CONTINUE_MAX`); a compliant re-arm zeroes the agent-armed counter (`session-continue.sh:117`); measured chains of 311/236/220 blocks; the harness cap resets on tool use | A07 §3, A07-sk |
| "`timeout` is available to hooks" (implicit in `_bounded`) | `timeout` is **homebrew-only**; 7 of 25 live claude processes (incl. the wave lead) lack `/opt/homebrew/bin` on PATH; `jq` is `/usr/bin/jq` and present everywhere | CRITIC M6 |
| "901 closes vs 469 evaluations — unexplained" | Still unexplained; three offered explanations do **not** reproduce (A01's exact identity; LEAD's 2.1.220 attribution — 17 closes / 16 rows; A09's `agent-*` files — already excluded by `measure-closes.py:265`). Re-measured 2.1.260: 632 closes / 542 rows, a 14 % deficit spread thinly | CRITIC C5 |

---

## 2. Ranked changes

### 2A. Implement now (conviction ≥ 90, agent-drivable; the c10 migration is STAGED by the agent and RUN by the operator via `cc-do` — a 👤 step, not a decision)

| Rank | What | Axis | Conviction (axis → skeptic → syn) | Effort | Files | Fails toward |
|---|---|---|---|---|---|---|
| 1 | **Fix the `grep \| jq` pipefail inversion in `goal_liveness` / `goal_live_condition`** — neutralise grep's no-match status while keeping a distinct rc for "grep ok, jq failed"; add `goal-unreadable` to `_default_blind`; correct `goal-inert-watch.sh`'s header to the 2.1.260 gate (`d2n(taskRegistry.all())`, the 30-min check-in, the auto-clear classes) | A04 R1, R5 | 97 → 95 → **96** | S | `hooks/lib/goal-state.sh:38,84` · `scripts/idl-abstain-alarm.sh:117-119` · `hooks/goal-inert-watch.sh:4-20,177` · `tests/goal-state*.bats` | Correctness. The fire path never reached this branch, so it cannot nag more; the one regression to forbid is laundering a corrupt transcript into `absent` (keep the rc split) |
| 2 | **Log `confirm_rc` on the `mechanical-assignee` exemption (:846) and log the mechanical arm's kill-switch return (:826)** — 47 releases / 11 d are unattributable; the :826 return is the reason kill-switch harm on writers cannot be measured | A07 R5 | 95 → 95 → **95** | S | `hooks/session-continue.sh:826,846` · `tests/session-continue.bats` | None — instrumentation |
| 3 | **CLAUDE.md corrections, one lead-inline pass** (Edit, never Write; then sync the real-file live copy): (i) `:577` `📦-in-reso` → "📦 in a repo whose OWN CLAUDE.md says landing spends money" (A08 E6, 93 → 95); (ii) `:185` goal sentence → the corrected lifecycle in §1b (A04 R6 + CRITIC U7, 90); (iii) `:502` and `:888` `CLAUDE_CONTINUE_MAX` claim → the §1b wording incl. "the harness cap resets on tool use" (A07 R6, 90 → 90); (iv) `:813` "the one decision you need" → "the decision(s) you need" — `wrap-ledger` already counts BLOCKED as plural and S6 already mandates naming each (A08 E3 residue, 92); (v) `:532` E0 row: "`yield` governs the READOUT, never identified work; a read-only turn that names drivable work runs the Follow-On Gate first — no arm sees this case without a lexical tell" (A08 E1, 92 → 72 → 90 with the skeptic's correction); (vi) new short section **Shared Task List (All Projects)** naming `TaskCreate/TaskUpdate/TaskList`, the store, the list id, the gate, and "the plan doc's task table is the list where the tools are absent" (A03 R2 + A08 E5, 92/85 → 90 — the operator asked for step 2 by name); (vii) § Agent Teams: "`--goal` can act only at an intermediate Stop of a fired session, never at its terminal self-close" (CRITIC §0.3/C13, 90) | A08, A04, A07, A03, CRITIC | **92** (bundle) | S | `CLAUDE.md` · `/Users/chrisren/.claude/CLAUDE.md` (real file, byte-identical today — A08) | Prose only. Each item REPLACES a false sentence; net resident-context growth is one section (vi) |
| 4 | **Stop the test-fixture leak into the live IDL**: `tests/completion-assert.bats` pins `COMPLETION_IDL` (line 17) but drives `session-continue` 16 times with `CONTINUE_IDL`/`CC_IDL` unpinned — 312 rows with sid `dbl-1/3/4` landed in the live store at 08:55Z, 156 of the 605 `fired continue` records | A07-sk2 M2, SYN | — → 90 → **92** | S | `tests/completion-assert.bats` (setup) | None — test hygiene; the same leak was fixed twice before for other files (`tests/session-continue.bats:27-39`) |
| 5 | **Self-close / `--recycle` ledger STAMP (annotate, never refuse)**: run `scripts/wrap-ledger.sh --machine` for the retiring sid inside `handoff-fire self-close` and `--recycle`, and write `RUNG · REMAINDER · unlanded count · goal condition` into the successor brief and the custody row. The REFUSE variant is research item B1 | CRITIC C-R1 | 88 → **92** (annotate-only) | M | `scripts/handoff-fire.sh` (self-close block `:6995-7010` is the template; `--recycle` brief composer) · `tests/handoff-fire-*.bats` | Noise in the successor brief. Cannot strand a pane; on `SID` unresolvable it warns and proceeds (A11-sk's two-verdicts trap) |
| 6 | **Stage migration `0022` (`# migration-class: c10`) + file its `cc-backlog needs --run` row**: (a) `"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1"` in the `env` block of all **five** config dirs (pattern `0021-fleet-hook-parity.sh:98`; four separate inodes measured); (b) register `TaskCreated → hooks/task-created-attrib.sh` — new hook writing `~/.claude/tasks/<listId>/.owners/<taskId>` = `<session_id>\t<ts>\t<cwd>`, **`exit 0` unconditionally** (a blocking `TaskCreated` deletes the task — binary @164041274); (c) register `StopFailure → hooks/session-beat.sh stop` (no beat writer runs on a StopFailure, so `kind=prompt` sticks on a live pid — 9 markers / 5 sids today, 2 read falsely BUSY); (d) note the numbering collision (two files are `0021-*`). **Do not** touch `CLAUDE_CODE_ENABLE_TASKS` (it is a kill switch) | A03 R1, R3; A10-sk2; CRITIC C-R4 | 96/94 → 92/90 → **92** | S | `migrations/0022-todo-tools-taskcreated-stopfailure-beat.sh` · `hooks/task-created-attrib.sh` · `tests/` | Noise: four deferred tool names (+26 tokens measured), one sidecar file per task, one more beat write. Cannot silence anything. The RUN is the operator's (👤, `cc-do`) |
| 7 | **Un-blind `handoff-fire`'s active-concurrency term**: call the already-sourced `_cc_admit_load_presence` (`capacity-admit.sh:457-476`) before the term at `:5355-5362`, or source `spawn-presence.sh` at top level; add a red-proof asserting `blind:` never contains `active` on a production admit, run **without** `CC_FIRE_ACTIVE_OVERRIDE` (the suite sets it to 0 in `setup`, line 84, so the live branch has never been under test) | A11 R3 | 95 → 90/93 → **90** | S | `scripts/handoff-fire.sh:4995-5011,5152,5355-5362` · `tests/handoff-fire-capacity-gate.bats:84` | **Closed** — fires refuse when > 8 sessions are mid-turn, the polarity the Agent gate has shown for six days (0 refusals in 159 evaluations before 09-05). Dispatcher fires already retry every tick; only interactive `/handoff` fires get the deny message, exactly as the Agent gate treats them today. Same file as rank 5 → same session |
| 8 | **Make `wrap-ledger`'s `_bounded()` bind**: probe `/opt/homebrew/bin/timeout`, `gtimeout`, `/usr/local/bin/timeout` before the unbounded fallback at `:713-715` | A01-sk, CRITIC M6 | — → — → **90** | S | `scripts/wrap-ledger.sh:713-715` | A store read over its 5 s bound is killed → `SRC=error` → the ledger already renders unknown (fail-open, its own house rule) |
| 9 | **Pin `TZ=UTC` on BOTH sides of the beat's `(pid,lstart)` identity in one commit**: writer `hooks/session-beat.sh:82` and reader `scripts/lib/spawn-presence.sh:362` are both ambient today (0/51 match under UTC, 22/51 ambient — breaks at the next DST flip); `cc-await-ping:871` already pins its own two samples and never compares to the stored field | A10-sk1 R1, SYN | — → 60 → **90** (both sides together) | S | `hooks/session-beat.sh:82` · `scripts/lib/spawn-presence.sh:362` · tests | During rollout an old ambient beat mismatches a UTC reader until that session's next turn → `cc_sp_active` undercounts for minutes (errs OPEN on the gate for one turn). Mitigate: reader accepts either rendering for one release |
| 10 | **Enrich capped IDL records** with `arm`/`rung`/`facts` (`completion-assert.sh:1079`, `anti-deference-nudge.sh:350`) — 106 cap trips / 19 sids in 11 d are unsighted; the hand-read heaviest capped session's closes were honest ⛔ | A07 R4 (instrumentation half) | 80 → 90 → **90** | S | `hooks/completion-assert.sh:1075-1081` · `hooks/anti-deference-nudge.sh:350` | None — instrumentation. Do **not** mint a backlog row from a Stop hook (the class gate refuses it; cheap-entrance-no-exit) |
| 11 | **Split fixture fires out of `dispatch-fires.log`**: `selftest()` pins `CC_DISPATCH_IDL`/`SPAWN_BIN`/`PAGES_DIR` (`bin/cc-dispatch:3504-3508`) but not `CC_DISPATCH_FIRE_LOG`; 36 of today's 91 "fires" and all 12 `rc=7 no pane anchor resolved` are selftest stubs (`:3495`, `STUB_SPAWN_RC=7`) | A11-sk2 | — → 90 → **90** | S | `bin/cc-dispatch` (`selftest()`) | None — a census could no longer count fixtures as production (real failure rate today is 65 %, dominant cause INC-4 autosubmit race, not anchors) |
| 12 | **`no-capacity` must not be mintable on instrument blindness**: `cc-backlog:1752` reads "routes nowhere" literally; `claude-accounts --rank general` returns `no routable account … concurrency-unmeasured` (DATA_UNAVAILABLE, exit 3 by design, `bin/claude-accounts:2988-2994,3355-3361`) under exactly the load that produces refusals. Require rc 0 + `none` | A11-sk2 R7 | — → 80 → **90** | S | `bin/cc-backlog:1752` (`valid_why_not_now`) | Toward DRIVE (the class gets harder to mint) — the house's preferred polarity |
| 13 | **Make the permpend escalation ladder actually run**: add a version-asserting self-restart to `lead-supervisor.sh` (compare the running script's sha to the on-disk file each tick; exit so launchd `KeepAlive` restarts it), and file `cc-backlog needs --run "launchctl kickstart -k gui/$(id -u)/com.claude.lead-supervisor"` for the one-time kick (the classifier denies acting on a live process — memory rule). Commit `10348ff6a` (14:45Z) landed the ladder; daemon pid 31716 started 15:17Z before the checkout advanced; **0** `permission_pending_escalate` in 5,155 records; 114/114 notice markers bare-ts; 11 sessions sat 5.7–7.9 h with one notice each | A05-sk, A05-sk2, CRITIC C9 | — → — → **90** | S | `scripts/lead-supervisor.sh` · needs row | A restart mid-sweep drops one 30 s sweep; KeepAlive restores within the tick. Do **not** add A10's BUSY-SUSPECT — a fourth pager on the same event with no shared damping key |
| 14 | **Ship the session-termination census as an instrument** (`scripts/measure-terminations.py`, sibling of `measure-closes.py`): per dead main-chain session, terminal class ∈ {Stop, self-close, recycle, drain-recycle, frozen(permission), killed, api-error}, joined to beat liveness and the permission archive; **consumer named**: `scripts/idl-abstain-alarm.sh` prints the denominators beside every "% of Stops" | CRITIC C-R7 | 88 → **90** (consumer named) | M | `scripts/measure-terminations.py` (new) · `scripts/idl-abstain-alarm.sh` (after rank 1 lands — shared file) | Another counted line — mitigated by the named consumer; without it, delete the script |
| 15 | **File `tengu_propose_goal` as `not-yet-true` with a self-retracting falsifier**: `jq '.cachedGrowthBookFeatures.tengu_propose_goal' ~/.claude-tertiary/.claude.json` (config-dir copy; `$HOME/.claude.json` is stale since 08-11). `ProposeGoal` (`ask_user:false` when the user's own words stated the outcome) is the one upstream feature that implements the operator's ask; default-off server flag; override API stubbed; 0 uses in 6,140 transcripts | A12 R6 | 92 → 88/90 → **90** | S | `cc-backlog add` (one command) | Waiting on a remote flag; the falsifier retracts the row when Anthropic flips it |

### 2B. Research-then-implement (< 90 after this wave, **not** the operator's — each names the measurement that moves it)

| # | What | Axis | Conv. | Effort | Files | Blocked on (the drivable measurement) | Fails toward |
|---|---|---|---|---|---|---|---|
| B1 | Self-close **REFUSAL** on `📦` / `⛔` / `REMAINDER≠0` (on top of rank 5's stamp); annotate-only on `📤`/`--recycle` | CRITIC C-R1 | 88 | M | `scripts/handoff-fire.sh` | Run `wrap-ledger --machine` in the cwds of the last ~20 self-closed sids (from rank 14's census): if < 10 % would refuse, land refuse; else stay annotate | Refusing a legitimate retire (loud, pane stays open with the reason) |
| B2 | **Fold snapshot for `cc-backlog list` / one-`jq`-pass for `wrap-ledger`'s three store reads** — the Stop-path hot term (4.4 of 5.7 s; 7.5 of 8.6 s); store +371–697 rows/day; `cmd_compact` rewrites via `mv` under a lock (SYN), so key on the FILE's (size, mtime), never the directory's. **Gate for every row-minting recommendation (C7)** | A01-sk, A01-sk2, CRITIC C7 | 85 | M | `bin/cc-backlog` · `scripts/wrap-ledger.sh:726,813,888` | Prototype both designs; byte-diff `--machine` output over the live store for every rung; verify compaction invalidates the key | Stale fold if a rewrite keeps size+mtime (compaction shrinks; appends grow — measure) |
| B3 | Single-flight memo wait bounded by the winner's real cost (`wrap-ledger.sh:418-428`: 750 ms ladder vs 2–10 s compute ⇒ all five consumers compute, ×1.6 each) | A01-sk1 | 80 | S | `scripts/wrap-ledger.sh:418-428` | B2 first — the compute may shrink under the ladder | A slow winner slows everyone (they all compute today) |
| B4 | **Harvest-latency audit**: for each idle close that named drivable work, does the finding appear in a later commit/row within N days? 0/2 permanent in spot checks. Decides whether ANY peer-drain producer (A02 R4) is worth building | A02-sk | 85 | S/M | `scripts/measure-closes.py` sibling | — (this IS the measurement) | Building a ~24 rows/day producer for re-derivation cost that may be small |
| B5 | `session-writes.sh` **Bash-write attribution — extraction half only** (rc semantics unchanged): tightest idiom set (`sed -i`, `>`/`>>` to a path, heredoc to a path, `tee` without `-a`), one bats mutant per idiom | A07 R2, A09 R3, backlog `ed54373d639b` | 70 | M | `hooks/lib/session-writes.sh` · `tests/session-writes.bats` | Sibling-misattribution census over today's transcripts: does any idiom name a path this session did not author (`git checkout -- <sibling's file>`, `tee -a`)? | #105-class false conviction the innocent session cannot clear |
| B6 | **`settings.local.json` promoter**: 95 rules in the shared checkout + 207 across 21 worktrees, 77 % exact literals that can never match twice, gitignored, deleted by `worktree-gc`; propose prefix rules into the committed project `.claude/settings.json` (repo work) for prefixes appearing ≥ 3× as exact approvals; never touch ask/deny; weigh the user layer's `Bash(python3:*)` escape hatch | CRITIC C-R2 (M3), A12-sk2 | 85 | S/M | new `scripts/permission-promoter.sh` · `.claude/settings.json` | The census (≥3× prefixes; add `.worktreeinclude` for the local file) | Allow-widening without an operator read (the 2026-08-20 lesson) |
| B7 | **Lineage-scoped `OPEN_TASKS_MINE`** (tasks created by this sid or any predecessor in `~/.claude/autonomy/dod/lineage.tsv`, still open) → 🔧 at `FILED_MINE`'s rank; session scope dies at succession, list scope fires forever on 66 stale items | A03 R4, CRITIC C8 | 80 | M | `scripts/wrap-ledger.sh` · `hooks/completion-assert.sh` | Rank 6 RUN by the operator (no tasks exist to count today) + 48 h of the term behind `--machine` before folding into 🔧 | Silence at succession (session) vs always-fires (list) — lineage is the middle |
| B8 | Re-key `lead-supervisor`'s fleet enumeration on the beat store with the `(pid,lstart)` leg (telemetry blind to ~30 %: `live=27 enum=22`; beat covers 25/27; but 1,411 of 1,427 `prompt` beats have dead pids) | A10-sk1 R6, A10-sk2 | 80 | S | `scripts/lead-supervisor.sh:97` | Rank 9 (TZ pin) + a tombstone GC/filter for `~/.claude/cc-beats` | False BUSY from dead-pid beats if the liveness leg is skipped |
| B9 | **SessionStart beat refresh** for resumed sessions (2/27 live carry a pre-resume pid and read GONE until their first prompt) | A10-sk1 R7 | 85 | S | `hooks/session-beat.sh` · migration `0022` (SessionStart entry) | Decide new `kind` vs pid/lstart refresh; can ride rank 6's migration | None measured |
| B10 | Refused-spawn spool with **owner-side discharge** (the owner clears the entry at its next Stop via `session-continue`; promote to backlog `--condition … --falsifier …` only when the owner dies) — 20/20 refused briefs were done inline today, so a desk-side re-offer would be 100 % duplicates | A11 R1/R2 as re-designed by A11-sk | 70 | M | `hooks/agent-teams-enforce.sh:226-243` · `hooks/session-continue.sh` | Rank 7 first; then design the discharge verb | Nagging on finished-inline work (alarm-polarity) |
| B11 | Capacity budget keyed on `(caller, sid)` with a TTL, global counter as outer bound — the global no-TTL counter carried 2.6 h across sessions and starved 3 of 6 refused sessions of any release | A11-sk R4 | 70 | S | `scripts/lib/capacity-admit.sh:82-83,360,564` | Design against the reserve terms sharing the same file (A11 open q5) | Per-sid key alone ⇒ N leads each get a release into a saturated box |
| B12 | `cc-backlog research <id>` — the blocked→open edge (lease, read-only brief via `handoff-fire`, `unblock` on N > 90). Note: `cc-dispatch` also requires `project ∈ dispatch-projects.conf` (36/220 blocked rows can never fire), 148/220 sit in `master-operator-gated`, and the first probed row's premise was already dead | A06 R2, A06-sk | 60 | M | `bin/cc-backlog` · `scripts/handoff-fire.sh` | B2 + rank 7 landed; then run the EXISTING `unblock` premise re-read over the 8 hand-verified candidates and count dead premises (`2fa274cbeb00` already dead) — revalidation is the cheaper first edge | Spending quota on the ~15 % C10 stratum research cannot move |
| B13 | Decider hygiene: normalise `git -C <path>` before **both** `allowed_segment` and `crosses_fence`; `mktemp` as an arg-guarded branch (`mktemp`, `-d`, `-t X` only) | A05 R1/R2 | 75 | S | `hooks/lib/smart-bash-allowlist.py:359,906` · `tests/smart-bash-allowlist-narrow.bats` | None — but value is **12.9 h / 30 d** through the live `decide()` (not ~260 h): ride any future decider change | Allow, bounded to read-only subcommands |
| B14 | Read `.last_assistant_message` from the Stop payload in the four scanning hooks; fallback on ABSENCE, never on EMPTY | A01 R4 | 72 | S | `hooks/completion-assert.sh:220-225` · `anti-deference-nudge.sh:145-148` · `dispatch-assert.sh:123,132` · `session-continue.sh:267` | None (hygiene; ~0 kills) — presence on Stop is inferred from the schema, never captured on this box | Abstaining on `""` where it should speak |
| B15 | `hook_cancelled` reader as a **counted** `wrap-ledger` term — never a certificate veto until the clean-path kill rate is < 5 % (53.5 % of completion-assert kills co-occur with an operator-readout kill, so there is no certificate to refuse half the time; same-Stop reads race the writer) | A01 R2 | 65 | S | `scripts/wrap-ledger.sh` · `hooks/lib/idl-log.sh` | B2 (brings the clean-path kill rate down) | An alarm on the busiest legitimate path |
| B16 | Bound `goal-inert-watch`'s transcript scan from the last ARM record (5 kills / 30 d at 90–120 MB; 2 of the 5 were at 7–9 MB and are load, not size) | A01 R5 | 65 | S | `hooks/lib/goal-state.sh:38,84` · `hooks/goal-inert-watch.sh:208-215` | None — do it when touching the file (rank 1 touches it; keep the arm-bounded semantics) | Clipping the arm marker ⇒ a healthy eval count over an unjudged goal |
| B17 | Find the producer of the 4 KB `autonomy-sweep` IDL record that aborts `jq` at line 844,016 — every `jq` census over the archive is silently truncated (parse failures are verdicts) | A07-sk2 M1 | 80 | S | `scripts/autonomy-sweep.sh` (likely) | Identify the record + its writer | A truncated census read as complete |
| B18 | One honest ledger bit from `background_tasks`/`session_crons` — "a cron/backgrounded task WILL wake this session" (IDLE-ARMED vs IDLE-DEAF), read only in a Stop hook, never in `/wrap`, never a block; **not** a D8 substitute (`goal-inert-watch.sh:50-67`: the field is a backgrounded-only view) | A12 R5 salvage | 60 | S | `hooks/session-continue.sh` or `operator-readout.sh` | Decide the consumer | An empty list rendered as "idle" while a foreground gate runs |
| B19 | Register the **three** real Notification matchers (`agent_needs_input`, `worker_permission_prompt`, `agent_completed`; `elicitation_url_dialog` has no emitter) — zero value until a human channel exists | A10 R5 | 78 | S | migration (c10) · `hooks/notify.sh` | Operator Decision 2 (Pushover) | More chimes into a dead channel |
| B20 | **Workflow vs subagent-wave outcome A/B** on one conviction-moving question (cost is known: 1.699 vs 0.875 pp/unit; quality is not) | CRITIC M4 | 75 | M | `docs/research/` | — (this IS the measurement; ties to Operator Decision 6) | Adopting a 1.5–1.7× premium on an unmeasured premise |
| B21 | Re-derive the closes-vs-evaluations deficit with **one** definition of "close" (main-chain `end_turn`), per binary version, per hook, separating end_turns that are not Stop events from IDL write failures | CRITIC C5 | 85 | S | `scripts/measure-closes.py` | — (this IS the measurement) | Attributing a 14 % deficit to the wrong cause again |
| B22 | Record the `ENABLE_STOP_REVIEW` reason where the env block cannot (`migrations/README.md`, an "env lines with a reason" list pointing at `022683ab85f3` and the 07-29 doc) | A12-sk2, CRITIC C10 | 85 | S | `migrations/README.md` | None | A future session deleting a deliberate safety |

### 2C. Refuted or dropped (named, with the reason — not co-equal with driven)

| Recommendation | Verdict | Why |
|---|---|---|
| A01 R1 `dod_lineage_ancestors` rewrite | drop (15–25) | 0.17 s standalone, 0.38 of 5.7 s in a timestamped trace; the depth model was inverted (root = fewest ancestors) — A01-sk, A01-sk2 |
| A01 R3 blanket timeout raise 10→30 / 5→20 | drop (50–55) | Rests on 14.3 s that did not reproduce (2.15–2.55 s; LEAD 1.6–2.1 s); the cost is store-growth-driven so a fixed raise decays; a 15 s raise only as a companion to B2 + rank 8 |
| A01 R6 pre-filter on operator-readout | drop (20–30) | On 🔧/📦 every store read is already `SRC=skip`; on ✅ the stores ARE the predicate; a pre-filter silences the operator's only steps surface |
| A02 R1 store-or-silence gate at terminal close | drop (25) | Arm (i) is a lexicon; arm (ii) IS `dispatch-assert.sh:162 discharged_since`; on 300 transcripts silent+write closes split 75 live-reply : 44 idle : 42 EOF — a Stop hook nags live conversations ~1:1 |
| A02 R2 bind line-1-rung on silent origin closes | drop (35) | Origin F4 is 167 not 566 (47 noise; 54 with an Edit/Write tool); same ~1:1 nag; the honest alternative is to state the exemption |
| A02 R4 peer-findings drain producer | drop → B4 (20–40) | Flagship receipt false (R-5 fixed +1 d on `origin/main`; grepped a 30-line file over lines 79–102 in a checkout frozen 08-16); 0/2 permanent loss |
| A03 R6 concurrency probe · R7 close `ebe84950e98a` · R8 `_cc_tlid` rewrite | done · done · drop (40) | Allocator locked (`bXn` proper-lockfile + `.highwatermark`; ids 1–6 across two `-p` sessions, nothing lost — LEAD §4); row closed 22:14Z; `handoff-fire` sets no `CLAUDE_CODE_TASK_LIST_ID` — a pass-through there is the lever, not a shell-profile edit |
| A04 R3 "session-continue is the primary drive lever" | drop the claim (55) | Rests on fire COUNTS (239 continue / 13 h) with no measured outcome of a forced turn; both levers are Stop-time and 59 % of goal-armed sessions never reached a Stop. Keep only the `--goal`-is-a-terminator reframe (rank 3 vii) |
| A04 R4 shorten the `--goal` template | refuted (10) | Given a Stop, template 69.5 % vs freehand 68.0 %; the raw gap is entirely no-Stop-occasion (68.4 % vs 17.4 %) |
| A05 R3 `load_fence` split · R4 `VAR=$(mktemp)` tracking | refuted (20 · 20) | The deny list holds a **wildcard** rule for absolute-path recursive `rm` (the `/*`-suffixed sibling of the exact `rm -rf /` rule — A05-sk) that the axis never read; the harness itself denies a recursive rm under `/tmp`; only 174/399 `rm -rf "$VAR"` are mktemp-assigned and a generous R1+R2+R4 gains 2 commands / 12.9 h through `decide()` |
| A05 R5 proposals file on the supervisor tick · R7 classifier prose | drop (50 · 10) | The daemon does not pick up landed code (rank 13 first) and the product is ~13 h; the `is_error` text is the same category-free "Blocked by classifier" string |
| A06 R1 `cc-backlog conviction <id>` verb · R3 `--kind` on `needs` · R4 brief paragraph | drop (55 · 45 · 35) | A re-run `add` with the same project+title+`--source needs` already folds `conviction`+`receipt` onto the row (`:986,3536-3539,2032-2052`) and N > 90 is refused at `:1782` by design; `--kind other --why` is the any-string escape (`gate-on-presence-is-cleared-by-any-string`), `.by` is empty on 143/146 needs rows so a hard refusal lands on machine callers as silent loss; landed prose changes nothing |
| A07 R1 kill-switch regex / brief exclusion · R3 cap re-key · R4 backlog row on cap trip | drop (55 · 30 · —) | Live effect **1/530 Stops**; brief-shaped matches are TERMINAL so a terminal-only regex removes none; excluding the brief reverses `session-continue.sh:250-260`'s recorded design; capped and driven sessions are disjoint in 11 d of IDL and the heaviest capped session's closes were honest ⛔; `cc-backlog add`'s class gate refuses a hook-minted row |
| A08 E2 measured kill-switch clause · E4 verification-ban clarification · E8 name `cc-permission-audit` | drop (55 · 40 · 30) | 27/38 matches live in `subagents/agent-*.jsonl` the hook never reads (readable population 8/11; the discipline sentence alone earns no resident context at 0.19 %/Stop); 0 observed citations of :358 in 610 transcripts; the tool WAS run and its `approved 0 · unknown 3359` is a join-key artifact |
| A09 R5 `idl_init` reorder · R6 `measure-closes` fix · R4 `filedBy` backfill + queue rung | drop (10 · 5 · 15/30) | The only pre-`idl_init` exit is the FATAL lib load; `measure-closes.py:265` already skips sidechain records; `filedBy` is stamped prospectively since 09-06 (82/85 adds today) and a backfilled sid names a dead session |
| A10 R1 `session-busy.sh` as specified · R3 own-session BUSY fields · R4 BUSY-SUSPECT · R7 jq PATH | drop (55 · 35 · 25–80 · 20) | 0/51 UTC match (→ rank 9); StopFailure false-BUSY (→ rank 6c); in-process subagents read false-IDLE on the lead; own-session `kind` is racy at Stop and constant in `/wrap`; the incident pane is mid-turn and never reaches a Stop hook, and `lead-supervisor` already pages STALL?/PERMISSION-PENDING (→ rank 13, B8); `jq` is `/usr/bin/jq` — the two beat-less pids are resumed sessions (→ B9) |
| A11 R4 breach-sized budget formula · R5 `SPAWN_DEFERRED_MINE` · R6 reserved headless anchor | drop (35 · 40–45 · 20–30) | `max(1, 2·ceiling − active)` yields budget 1 at a 2× breach — the inverse of its intent (→ B11); the term would have held 🔧 over six closes whose spooled briefs were all executed inline; all 12 `rc=7` were selftest stubs and `resolve_headless_anchor()` + the desk role already exist (→ rank 11) |
| A12 R1 delete `ENABLE_STOP_REVIEW` · R2 `SubagentStop` advisory `additionalContext` · R7 import ScheduleWakeup prose | **refuted** (15 · 30 · 25) | It is the security-guidance plugin's gate, set deliberately (→ B22); registration is already staged as `migrations/0014-*` (c10, row `296cc04bc3fd`) and `hooks/subagent-stop.sh:39-41` is test-pinned to emit NOTHING (the documented loop incident); `CLAUDE.md:162` and `commands/handoff.md:616` already carry the event-driven discipline |

### 2D. Non-actions to keep (each states its polarity)

Do **not** widen `dispatch-assert` NAME_TELL (85; a denylist of spellings) · do **not** add a lexical
"decision" arm (85; 30 % prose precision — the write-time `--conviction/--receipt` gate is the right
shape) · do **not** build a prose detector for the un-filed "needs more investigation" close (90; starve
it by making filing cheaper than prose, never detect it) · do **not** route capacity overflow to cloud
(75; 23/346 eligible and 0/15 refused axes — `cc-eligible` is a spelling denylist, but the independent
argument stands) · do **not** raise `CC_ADMIT_ACTIVE_CEILING` before a working-vs-awaiting sensor (80;
the count charges an awaiting lead) · do **not** add a `no-capacity` filing path (80; 0 rows use it — and
rank 12 hardens the class) · do **not** adopt an agent-type Stop hook now (78–80; `dontAsk` ⇒ deny, no
structured output ⇒ `cancelled` ⇒ the stop proceeds silently; the project layer already carries the
allow rules and the user layer's `Bash(python3:*)` is a universal escape, so the limit is a Haiku judge
not finding the evidence, and no local instrument exists) · leave `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` at 8
and never set it to 0 (90; `Vd>0` guards the bound) · do **not** declare a `type:"prompt"` Stop hook
while `/goal` stands (88; a second tool-less evaluation per Stop on one block budget) · do **not**
narrow the exemptions (80; `ship-floor-not-mine` is ~70 % the oracle gap of B5, not an exemption
defect) · do **not** add `Bash(prefix:*)` rules for the top clusters (85; the slow stratum is 69.2 %
pre-gated and not rule-shaped; auto mode drops the bare forms the clusters need).

**Strike from A06:** "capacity is measurably not the constraint — 0 capacity refusals in 903 fires" was
read off the gate A11 proved blind on 48/48 admits (CRITIC C1). **Strike from A02:** the R-5 "still
unfixed 17 days" receipt (CRITIC U2/A02-sk).

---

## 3. Operator decisions — the residue after this research (answer-first; each carries its number, two measured options, and why it is below 90)

**OD1 — Who answers a permission prompt when you are asleep?** *Recommendation: run
`hooks/model-permission-decider.py` in SHADOW mode for 7 days over the archive's slow stratum, then
ENFORCE only for the compound test-fixture class (`cd <wt> && python3 - <<'PY'`, `T=$(mktemp -d)`),
never for anything on your `permissions.ask` list. Conviction 60.*
Measured: ~1,040–1,176 session-hours blocked per 30 d, chronic 11–270 h/day (A05, A09-sk); 99.3 % of
prompts were eventually granted (A09-sk); the 11 overnight blocks (00:07–02:11 CDT, 5.8–7.9 h) were all
granted in one batch at 12:57Z — including a `git reset --hard origin/main` that sits on your ask list
(A05-sk, A09-sk); 43.7 % of blocking commands and 69.2 % of the slow stratum carry a construct no allow
rule reaches (A05, A05-sk2); the live static decider clears 5.4 % of prompts and 0.3 % of the hours (A05).
Option (a): the decider as owner — bounded freeze, but a PreToolUse `allow` bypasses the permission
system (measured on 2.1.220: it sailed past the working-dir guard — `model-permission-decider.py:39-41`),
and hook-`allow` vs deny-rule precedence is asserted both ways by house docs and measured by neither on
2.1.260 (A05-sk). Option (b): you stay the owner and the fix is delivery (OD2 + rank 13) — the freeze is
then bounded by your wake-up latency, not by hours. Kill-and-refire is refuted: it replays the same brief
into the same prompt (A09-sk). *Below 90 because* the Manual-Command-Delivery rule sorts by blast radius
= your consent, and auto-granting is the one action that removes the human from the loop by design.

**OD2 — Pushover credentials, or another channel that reaches a human.** *Recommendation: provide
`PUSHOVER_TOKEN`/`PUSHOVER_USER` (decision `f91a9701ed21`, open since 2026-07-18 — 51 days). Conviction 80.*
Measured: `push-critical.sh` exits at :21-22 on the unset variable, and it is the only hook on the
`idle_prompt` and `permission_prompt` matchers that reaches a human; 23 permpend pages/day route to the
desk SESSION (pane 330), not to you; the human-facing channel delivered 0 pages today (A10 §5). Option
(a): Pushover — one credential, then B19's three matchers become useful. Option (b): the local-display
`osascript` fallback already exists — but the freezes begin at 00:07–02:11 when you are not at the box.
*Below 90 because* it is a credential, which is yours by definition.

**OD3 — Ratify the C10 rescope: "operator can revert" for reversible `env`/hook additions, "operator
runs" kept for `permissions.allow/deny` and shell profiles.** *Recommendation: ratify the split.
Conviction 70.* Measured: `migrations/README.md:72` records the rescope as unratified; migration `0014`
(SubagentStop) has been staged since 08-17 (row `296cc04bc3fd`); this plan stages one more (`0022`); step
7's allowlist half is triple-blocked (soft_deny Self-Modification · CLAUDE.md:907 · class c10 — A08 §1).
Option (a): ratify for env+hooks — the pending migrations land autonomously, each carrying its own
revert. Option (b): keep operator-runs — every settings change waits in `cc-do`, and the median wait for
an operator-owned row is 20.9 days (A06). *Below 90 because* "never script your own authorization" and
the classifier's Self-Modification soft-deny are the consent boundary you drew; moving it is yours.

**OD4 — The default research-subagent count.** *Recommendation: align `CLAUDE.md:228` to "N=10, anchor
band 8–12" (the skill, `/research`, and the live `UserPromptSubmit` hook have all said 10 since 2026-07-17;
this wave ran 12, inside the band). Conviction 75.* Option (a) as above; option (b) change the three
downstream surfaces to 12. No cheap measurement separates them (A08 E7, A08-sk). Low stakes; listed only
because four load-bearing surfaces hold two numbers.

**OD5 — Who owns an orphaned class-C decision packet?** *Recommendation: re-attach by
`session_pane_uuid` while the pane lives, else by project (13 of 29 carry a project field), and render
them in the OPERATOR block / a pane roster — never as a stranger's ⛔. Conviction 65.* Measured: 28–29
open class-C, median 13 d, p90 50 d, 1–3 authors alive; `wrap-ledger.sh:900` joins ⛔ on
`.session_sid == $SID`, so 96 % can never render ⛔ again (A10, A10-sk1). Option (a) as above; option
(b) age-out via the packets' own `veto_deadline` / `default_if_no_veto` fields. *Below 90 because*
whether a question a dead session asked may block a live session's close is a policy call.

**OD6 — Dynamic Workflows as the default venue for step-3 research.** *Recommendation: keep dispatched
sessions / subagent waves as the research default until B20 measures outcome quality; a Workflow unit
costs 1.699 pp vs 0.875 pp (workflows-vs-teams §3c, quoted by A06), is offered to 260/260 main sessions
and headless `-p` but NOT to research subagents, so it cannot be the escalation target from the venue
the fleet uses for research. Conviction 75.* Option (a) as above; option (b) adopt the premise now and
pay the 1.5–1.7× premium. *Below 90 because* the premise is yours and the only thing that would refute
it (quality) is unmeasured — B20 is the drivable step and we will run it.

**Not decisions (👤 steps already filed or filed by this plan, run via `cc-do`):** migration `0014`
(SubagentStop registration, staged since 08-17) · migration `0022` (rank 6) · the one-time
`launchctl kickstart -k gui/$(id -u)/com.claude.lead-supervisor` (rank 13).

---

## 4. Phase 0 — wave plan for the implement-now set

**Execution locus per wave:** **S** (dispatched session via `scripts/handoff-fire.sh --worktree … --goal …`) for
every implementation wave; **L** (lead-inline) only for Wave 0's CLAUDE.md edits, per the rule. The
lead holds ≥ 50 % of its window for adjudicating returns; succession point = after Wave 1 returns land,
before Wave 2 fires. Note rank 7 changes the fire gate's polarity: once it lands, `handoff-fire` refuses
when > 8 sessions are mid-turn — fire Wave 2 sized to that ceiling (it is the intended behaviour).

| Wave | Items (rank) | Locus | Files touched (disjoint within the wave) | Depends on |
|---|---|---|---|---|
| **W0** | 3 (CLAUDE.md corrections i–vii) + sync `~/.claude/CLAUDE.md` | **L** | `CLAUDE.md`, `/Users/chrisren/.claude/CLAUDE.md` | nothing |
| **W1a** | 1 (pipefail fix + `_default_blind` + header facts) | S | `hooks/lib/goal-state.sh`, `hooks/goal-inert-watch.sh`, `scripts/idl-abstain-alarm.sh`, `tests/goal-state*.bats` | nothing |
| **W1b** | 7 (un-blind active term + red-proof) then 5 (self-close/recycle ledger STAMP) — same file, sequential commits in one session | S | `scripts/handoff-fire.sh`, `tests/handoff-fire-capacity-gate.bats`, `tests/handoff-fire-*.bats` | nothing |
| **W1c** | 2 (confirm_rc + :826 log), 10 (capped-record enrichment), 4 (bats IDL pin), 8 (`_bounded` PATH probe) | S | `hooks/session-continue.sh`, `hooks/completion-assert.sh`, `hooks/anti-deference-nudge.sh`, `tests/completion-assert.bats`, `tests/session-continue.bats`, `scripts/wrap-ledger.sh:713-715` | nothing |
| **W1d** | 11 (`CC_DISPATCH_FIRE_LOG` in selftest), 12 (`no-capacity` DATA_UNAVAILABLE guard), 15 (file `tengu_propose_goal` row) | S | `bin/cc-dispatch`, `bin/cc-backlog:1752`, one `cc-backlog add` | nothing |
| **W1e** | 9 (TZ=UTC on both beat sides, grace for both renderings) | S | `hooks/session-beat.sh:82`, `scripts/lib/spawn-presence.sh:362`, tests | nothing |
| **W1f** | 6 (stage migration `0022` + write `hooks/task-created-attrib.sh` + `cc-backlog needs --run` row) | S | `migrations/0022-*.sh`, `hooks/task-created-attrib.sh`, tests | nothing (the RUN is 👤) |
| **W1g** | 13 (version-asserting self-restart + needs row for the kickstart) | S | `scripts/lead-supervisor.sh`, one `cc-backlog needs` | nothing |
| **W2** | 14 (termination census + alarm denominator line); research items B1, B2, B4, B5-census, B6-census, B17, B21 as read-only sessions returning a number each | S | `scripts/measure-terminations.py`, `scripts/idl-abstain-alarm.sh` (after W1a), `docs/research/exhaustive-drive-2026-09-08/` | W1a (shared `idl-abstain-alarm.sh`); W1c (rank 8 before any `wrap-ledger` timing) |
| **W3** | whichever of B1, B2/B3, B5, B6, B7, B8/B9, B10/B11, B12 crossed 90 on W2's numbers; B7 additionally needs the operator to have run `0022` | S | per item | W2 returns; W1b (rank 7) before B10/B12; W1e (rank 9) before B8 |

Every W1 session is independent and self-verifiable (its own bats suite); fire all seven in ONE message.
Each `--goal`: one measurable end state (the named test green + the commit landed via the project
`/ship`), the check that proves it (the bats command printed), the constraint (touch only the files
listed). W1 sessions must not run `cc-await-ping` backgrounded if a `/goal` is live in the firing pane
(CLAUDE.md § Agent Teams).

---

## 5. Rulings on the critic's contradictions

| # | Ruling |
|---|---|
| C1 | A11 wins. A06's "capacity is not the constraint" is struck; A06 R2 (→ B12) lands only after rank 7 and B2 |
| C2 | A11 wins. "The dispatcher fires it itself" is false for 36/220 rows (`dispatch-projects.conf`) and lands into a lane with a 65 % real-fire failure rate (INC-4 race dominant, not anchors) |
| C3 | Settled by A07-sk pass 1's binary read (@164412526): the harness counter resets on `next_turn` after tool use, so the cap of 8 catches only a text-only wedge; 311-block working chains and 4–6 genuine cap hits are both true. A12 R4 stands; the wording lands in rank 3 (iii) |
| C4 | The IDL abstain count is the oracle (1/530); no regex change, no brief exclusion, no measured-clause in CLAUDE.md (the discipline sentence does not earn resident context at 0.19 %/Stop) |
| C5 | Unresolved; B21 re-derives with one "close" definition. Not a rotation-boundary identity, not 2.1.220, not `agent-*` files |
| C6 | 14.3 s is retracted; the true Stop-path hot terms are the three store folds on the ✅ path; A03-sk's argument that OPEN_TASKS_MINE is unobservable at Stop inherits the retracted number |
| C7 | No row-minting recommendation lands before B2 (none is in the implement-now set) |
| C8 | Lineage-scoped `OPEN_TASKS_MINE` (B7), keyed on `~/.claude/autonomy/dod/lineage.tsv` — neither session-amnesiac nor always-on |
| C9 | Fix the existing pager (rank 13's version assert + B8's beat-store enumeration); no fourth alarm |
| C10 | Keep `ENABLE_STOP_REVIEW="0"`; document it (B22). The plugin's Stop hook is not live (not in `enabledPlugins`) |
| C11 | `cc-permission-audit` was run; its zero is the `join-key-never-populated` artifact; A08 E8 dropped |
| C12 | Rank 6 re-files step 2's tracker as a staged migration + a `needs` row with `--run` |
| C13 | Both half right: `--goal` acts only at intermediate Stops of a fired session and never at its self-close (rank 3 vii); `goal-condition-best-practice-2026-08-09.md`'s "default" argument survives for the intermediate Stops |

---

## Appendix A — A06 skeptic verdicts (from the lead's JSON; not on disk before this file)

| Rec | Refuted | Adjusted | Why (condensed) | Rechecked command |
|---|---|---|---|---|
| R1 `cc-backlog conviction <id>` | yes | 55 | The write path exists: a re-run `add` with the same project+title+`--source needs` hits the same id (`mk_id`, :986) and the update arm at :2032-2052 folds `conviction`+`receipt`; N > 90 is refused at :1782 by design ("implement it, do not file it") — the correct N > 90 exit is `unblock`. 0/348 rows carry a conviction because no session tried the existing path | `jq '[.[]\|select((.conviction//null)!=null)]\|length' open.json => 0; sed -n '3536,3539p;986p;1782p;2032,2052p' bin/cc-backlog` |
| R2 `cc-backlog research <id>` | no | 60 | Edge and dispatcher real (launchctl pid 72372, 300 s backstop); `unblock` already re-reads the premise (:3122-3151). But the fire predicate is `status=="open"` AND `project ∈ dispatch-projects.conf` (:1857) — 36/220 blocked rows can never fire; "read-only brief" has no mechanism (`grep -nE 'read-only\|--no-write' handoff-fire.sh` → 0); 148/220 sit in `master-operator-gated`; row `2fa274cbeb00`'s premise is already dead | `sed -n '1853,1859p' bin/cc-dispatch; grep -vE '^\s*#' scripts/dispatch-projects.conf; launchctl list \| grep dispatcher => 72372` |
| R3 `--kind` on `needs` + widen UNCONVICTED | yes | 45 | `--kind other --why` is the any-string escape (memory rule, 2026-09-05); the set already misses live traffic (5 of 10 post-epoch rows are one re-land template, 1 is permission prompts); `.by` is empty on 143/146 needs-blocked rows and `cmd_reap` files `block --needs` internally — a hard refusal lands on machines as silent loss. The "99.5 % unreachable" framing uses the wrong denominator (the gate is epoch+filedBy scoped by design; 0 of 10 post-epoch rows reachable) | `jq -r '.[]\|select(.status=="blocked" and (.ts//"")>="2026-09-08T17:00:00Z")\|…' => 10 rows; jq '[.[]\|select(.status=="blocked" and .source=="needs")\|(.by//"-")]\|group_by(.)' => 143 empty` |
| R4 brief paragraph in cc-dispatch | yes | 35 | Number holds (0 hits) but landed prose changes nothing (memory: conclusion-must-reach-the-enforcing-store); a rider on R2, not a row | `grep -niE 'conviction\|research exhaustively\|90%\|needs-human' bin/cc-dispatch \| wc -l => 0` |
| R5 no prose detector | no | 90 | Holds: 30 % prose precision (lead-measured), `bin/cc-decide:56-57` forbids the shape-classifier, completion-assert 4.14 s @ 69 MB vs 5 s. Starving depends on R2 being cheaper than filing | `grep -n 'literal emission\|shape-classifier' bin/cc-decide => :56-57` |
| R6 headless Workflow probe | no | 70 | 1,602 transcripts since 09-01; 260/260 tool-definition files offered Workflow; 22 sessions invoked it; 4 under `.worktrees/wt-*`; binary carries `allow_workflows` org-policy and `disableWorkflows` strings. Orthogonal to the rail (handoff-fire fires interactive panes) and the cost table argues against Workflows | `xargs -0 -n 100 -P 6 /usr/bin/grep -l -F -f pat-wf.txt < files.nul \| wc -l => 22; comm -12 wfdef.txt bashdef.txt \| wc -l => 260 of 260` |

Missed by A06 (skeptic): the `condition` field (206/220 blocked rows carry one; 148 in
`master-operator-gated`); the existing revalidation lane (`falsify|validated|freshness|reclaim`,
`backlog-ratchet.sh`, `unblock`'s premise re-read); the project-conf term; the re-run-add update arm; the
`needs` producer census (`.by` empty 143/146); the missing `permission-denied` kind; hourly-perishable
numbers (355→348 rows, 143→146, 7→10, 31→33 packets, 21→22 sessions, 1,494→1,602 transcripts); the
dispatcher's liveness was inferred; headless-Workflow is orthogonal; the 0-capacity refusal claim never
ran its positive control (the `capacity` gate appears in 267 evaluated rows — a real zero).

## Appendix B — A09 skeptic verdicts (from the lead's JSON; not on disk before this file)

| Rec | Refuted | Adjusted | Why (condensed) | Rechecked command |
|---|---|---|---|---|
| R5 move `idl_init` above exemption gates | yes | 10 | `idl_init` is at `completion-assert.sh:132`; the only exit above it is the FATAL `_ilib` source at :130 (anti-deference would hit it too and it recorded for all 6 sids); `abstain()` (`idl-log.sh:84`) logs before every exit. The 6 silent sids are real but the missing arms are exactly the two that run wrap-ledger/git (sid `4cef9278`: 5 anti-def, 5 dispatch, 5 goal-inert, 0 completion-assert, 0 session-continue) — fits a 5 s kill under load. An ENTRY stamp would observe it (~70); the reorder is a no-op | `grep -nE '\bexit\b' hooks/completion-assert.sh \| awk -F: '$1<132' => only :130; grep -nE 'abstain\s*\(\)' hooks/lib/*.sh => idl-log.sh:84` |
| R6 exclude `agent-*` in `measure-closes.py` | yes | 5 | Already in the file: `:265-266` skips `isSidechain==true`, and `agent-*` transcripts are 100 % `isSidechain:true` (198/198, 228/228, 84/84). The denominator effect is larger than measured: 144 of 267 today's transcripts > 50 KB are `agent-*` | `grep -nE 'isSidechain\|agent' scripts/measure-closes.py => :265` |
| R2 give the permission freeze an owner | no | 85 | 5,159 records / 23 sids; per-(sid,since) split: 45 of 49 freeze spans have ZERO assistant/user records inside (85.1 h). No actuator: beacon emits no decision (:34), sweep only pages/reaps, decider registered 0× in 5 dirs, the 4 PermissionRequest hooks are 3× notify.sh + beacon. Archive: chronic 11–270 h/day (09-06: 270 h / 28 sessions); 3,826/3,853 (99.3 %) resolved via PostToolUse = GRANTED; the 11 overnight freezes (00:07–02:11 CDT) all granted 12:57:50–12:58:19Z incl. a `git reset --hard origin/main`. Kill-and-refire is refuted as an owner (replays the same brief into the same prompt). Decider ~60 pending ratification | `jq -rc 'select(.kind=="permission_pending")\|[.sid,.since,.ts,.age_s]' idl.jsonl \| awk (max per sid,since) => 49 spans; cat permission-archive/*.jsonl \| jq '[(.ts\|todate[0:10]),.waited_s,.resolved_by]'` |
| R4 backfill `filedBy` + drivable-now rung | yes | 15 | 299/346 open rows lack `filedBy`, but `add` stamps it prospectively since 09-06 (09-06 35/39, 09-07 25/33, 09-08 82/85; 0/55 on 09-04) — a historical STOCK; `FILED_MINE` is `.filedBy == $SID` for the CURRENT session so a backfilled dead sid can never become a 🔧; 153/346 open rows are `source: needs` (operator-only) so agent-drivable stock ≤ 193; a standing-pile rung fires at every close forever | `cc-backlog list --open --json \| jq 'length' => 346; jq '[.[]\|select(has("filedBy")\|not)]\|length' => 299; sed -n 788,792p scripts/wrap-ledger.sh` |
| R3 PostToolUse(Bash) porcelain delta ∩ command-text literals | no | 60 | Diagnosis confirmed by re-execution (`armed:mechanical-dirty` 2 of 826; `session_writes_paths` rc 1 on sid `1cb6d3b7` with 6 `sed -i` commands and 0 Edit/Write; the demo only works under bash — under zsh the function is absent, rc 127); defaultMode auto in 5/5. The snapshot adds a per-Bash-call `git status` on a box at load 16–22 where the ledger arms already die at their 5 s cap; the literal intersection misses `sed -i` on `$T/…`, `cat > "$f"`, globs. A hook-free extension of `session-writes.sh` reading Bash tool_use text is the safer form | `jq -rc 'select(.hook=="session-continue")\|.disposition+":"+(.reason//"-")' idl.jsonl \| sort \| uniq -c => armed:mechanical-dirty 2 of 826` |
| R1 decompose compound Bash, allow only mktemp-sandboxed segments | no | 65 | Facts hold (0 of 339/338/338/338 allow rules carry a shell operator; 4 surviving whitelist rules; the 11 prompts released at 12:57Z are the compound-fixture shape + one `git reset --hard` + one `add && commit`). Requires tracking `T=$(mktemp -d); cd $T && …` chains — the class that produced the retired rules; the 99.3 % grant rate belongs in the decision packet | `for d in …: jq -r '.permissions.allow[]' $d/settings.json \| grep -cE '&&\|;\|<<\|\|' => 0; sed -n 8,20p hooks/smart-bash-allowlist.sh` |

Missed by A09 (skeptic): the permission-archive it named and did not open (chronic; 99.3 % granted);
the overnight-onset pattern (kill-and-refire loops); R5's mechanism never checked against the code;
`measure-closes.py:265`; `filedBy` prospective since 09-06; the "never reached a Stop" tautology (a
frozen session has no Stop by definition; all 23 pending sids have `waiting-recycle` rows); R3's cost
lands in the breached budget; the bash-only reproduction command; `ENABLE_STOP_REVIEW` left unresolved.

## Appendix C — the checks this synthesis ran (SYN), read-only

```
# beat lstart: writer and reader are both ambient; cc-await-ping pins its own samples
grep -n 'lstart' hooks/session-beat.sh                     # :82 ps -o lstart= (no TZ)
grep -n 'lstart\|TZ=' scripts/lib/spawn-presence.sh         # :362 ps -o pid=,lstart= (no TZ)
grep -n 'lstart\|TZ=UTC' bin/cc-await-ping                  # :865-871 TZ=UTC on BOTH of its samples
grep -rln 'cc-beats' hooks bin scripts                      # cc-await-ping cc-cloud cc-beat.sh session-beat.sh spawn-presence.sh
# migrations: two files carry 0021 → next is 0022
ls migrations/ | tail -8
# supervisor: plist label com.claude.lead-supervisor; no version/sha self-check in lead-supervisor.sh
grep -n 'Label' ~/Library/LaunchAgents/com.claude.lead-supervisor.plist
grep -n 'sha256\|self-restart\|version' scripts/lead-supervisor.sh   # :531,:979,:997 only (unrelated)
# backlog.jsonl: append-only writers (>>) plus cmd_compact (:5168) rewriting via mv under _bl_compact_lock (:1088)
grep -n 'compact\|mv -f\|>> "\$BACKLOG' bin/cc-backlog; wc -lc ~/.claude/autonomy/backlog.jsonl   # 18,586 rows / 7,013,480 B
# wrap-ledger store reads and the _bounded wrapper
grep -n '_bounded\|cc-backlog list\|cc-decide list' scripts/wrap-ledger.sh   # :713 def; :726 --blocked; :813 --all; :888 cc-decide
# self-close refusal template
sed -n '6995,7010p' scripts/handoff-fire.sh                 # sc_git status --porcelain --untracked-files=no; exit 1 unless --dirty-owner successor / --allow-dirty
# the IDL fixture leak: which bats file writes dbl-* sids
grep -rln 'dbl-1\|dbl-3\|dbl-4' tests/ hooks/tests/         # tests/completion-assert.bats
grep -n 'CC_IDL\|CONTINUE_IDL\|COMPLETION_IDL' tests/completion-assert.bats   # only COMPLETION_IDL (:17)
grep -c 'session-continue' tests/completion-assert.bats     # 16
```
