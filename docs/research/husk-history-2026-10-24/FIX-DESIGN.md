# Husk-pane long-term fix — design (2026-10-24)

Scope (frozen): when a fleet session exits cleanly, its last close says "Good to close: yes" and its own paths are clean, its pane closes, or is held truthfully and closes itself once safe. This holds whatever sibling dirt the shared cwd holds, the session is never painted resume, and the four hard invariants still hold. Nothing else is in scope.

Inputs:
- `merged.md`, the 26 skeptic breaks, CENSUS.md, and Track A `docs/research/husk-pane-close-2026-10-24/REPORT.md` (on origin/main).
- Every `file:line` was re-read at HEAD `fa9cadc24` of `.worktrees/husk-skill-and-fix`.
- That worktree is 16 commits behind origin/main. Among the W1 files only `scripts/handoff-fire.sh` differs from origin/main: its lines after 5330 shift by +25, so `:11831` becomes `:11856`.
  - Measured: `git rev-list --count HEAD..origin/main`, and `git diff HEAD origin/main -- scripts/handoff-fire.sh | grep '^@@'`.

Labels: **[M]** measured, with the command given; **[C]** measured by the census, Track A or a skeptic, and cited; **[E]** estimated, with the method given.

---

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (this field decides whose context pays):

| wave | locus | why |
|---|---|---|
| **W1, the GOAL wave** | **T**: in-session teammates on the implementing successor | The successor implements with Agent Teams. W1's units are written against one contract, `tests/pane-289-replay.bats`, which composes the runner, guard, verdict lib, closer, painter, sweep, watchdog and watcher. They must merge into one branch and land as one /ship, so one lead has to reconcile them as they arrive. |
| W2: every fleet launch rooted in the runner | S, a dispatched session | Default. Disjoint launch-site files. The brief is §4 W2. |
| W3: standing census | S | Default. The brief is §4 W3. |
| W4: candidates | S, one per item, only past the Follow-On Gate | Default. |

**Task size.** Each W1 unit targets 40-150K output tokens (about 30-75 min and 3-6 files). It carries one task and stays within ≤150 brief lines, a reading list of ≤5 files, and ≤500 changed LOC including tests. W2 and W3 are one unit each.

**W1 teammate split.** No file is owned by two teammates. Line ranges are at HEAD; add +25 to any `handoff-fire.sh` range after 5330 once the branch is rebased.

| unit | owns (writes) | LOC [E: sketch sizes] | reading list (≤5, pre-grepped) | blockedBy |
|---|---|---|---|---|
| **T0 replay** | `tests/helpers/fixture-289.bash` (new), `tests/pane-289-replay.bats` (new) | tests +380 | this §5; `tests/cc-pane-runner-exit75-closes.bats:1-70`; `tests/handoff-selfclose.bats:1-80`; `tests/cc-pane-close.bats:1-80`; `tests/cc-husk-sweep.bats:1-100` | — |
| **T1 runner** | `bin/cc-pane-runner`; `tests/cc-pane-runner-hold.bats` (new); pins in `tests/cc-pane-runner-exit75-closes.bats`, `tests/cc-pane-runner-no-command-closes.bats`, `tests/pane-close-from-inside.bats` | code +120/−80, tests +240 | `bin/cc-pane-runner:40-110,150-200,250-450,540-646`; `lib/pane-recycle-pending.sh:1-60`; `bin/kitty-fullscreen-guard:1-120,840-960`; §4 W1a | T0 |
| **T2 guard** | `bin/kitty-fullscreen-guard`, `lib/kitty-fs-kitten.py`, `tests/kitty-fullscreen-guard.bats` | code +38, tests +90 | guard `:1-160,240-270,460-480,740-800,900-1019`; kitten `:60-110`; `tests/kitty-fullscreen-guard.bats:1-60,300-345` | T0 |
| **T3 verdict lib** | `lib/pane-end.sh` (new); `hooks/lib/session-writes.sh` (`:596-660` only); `tests/pane-end.bats` (new) | code +130/−1, tests +170 | `hooks/lib/session-writes.sh:1-60,296-300,502-660`; `lib/pane-custody.sh:1-80`; `bin/cc-pane-close:342-395`; `bin/cc-husk-sweep:441-520`; `hooks/lead-crash-watchdog.sh:1664-1710` | T0 |
| **T4 closer + painter + skill** | `bin/cc-pane-close`, `bin/cc-pane-verdict`, `skills/husk-pane/SKILL.md`; `tests/cc-pane-close.bats`, `tests/cc-pane-close-background.bats`, `tests/cc-pane-close-never-launched.bats`, `tests/cc-pane-verdict.bats` | code −60/+35, docs −45/+15, pins ~50 | `bin/cc-pane-close:60-110,170-200,300-560`; `bin/cc-pane-verdict:1-176`; `lib/pane-end.sh` (T3); `skills/husk-pane/SKILL.md:60-134` | T3 merged |
| **T5 sweep + watchdog** | `bin/cc-husk-sweep`; `hooks/lead-crash-watchdog.sh` (`:1600-1720`, `:1900-2060` only); `tests/cc-husk-sweep.bats`, `tests/cc-husk-sweep-identity.bats`, `tests/cc-husk-sweep-lineage.bats`, `tests/lead-crash-pane-verdict.bats` | code −110/+30, pins ~50 | `bin/cc-husk-sweep:1-80,200-220,440-625`; watchdog `:1600-1720,1900-2060`; `lib/pane-end.sh` (T3) | T3 merged |
| **T6 watcher** | `scripts/handoff-fire.sh` (`:1870-1880`, `:6680-6735`, `:11645-11925` only); `bin/it2-kitty` (comments `:86-89`, `:1663-1667`); new arms in `tests/handoff-selfclose.bats` | code +22, tests +70 | those ranges; `tests/handoff-selfclose.bats:1-80` | T0 |
| **T7 launch returns** | `scripts/limit-recover/lr-fire-resume.sh` (`:2225-2305`), `bin/reso-resume-one` (`:1098-1218`), `lib/pane-successor.sh` (`:205-245`); `tests/lr-fire-resume-close-attrib.bats`, `tests/reso-resume-one.bats`, `tests/pane-successor.bats` | code +16, tests +80 | those ranges; `bin/cc-close-attrib:586-626`; `tests/lr-fire-resume-close-attrib.bats:1-60` | T0 |

**Spawn and merge order.**
1. T0 runs alone. It proves its arms RED on the fa9cadc24 artifact (§5) and is merged.
2. T1, T2, T3, T6 and T7 run in parallel.
3. T3 is merged. T4 and T5 then run.
4. The lead integrates: the full replay is GREEN, every gate below passes, then one /ship.

**Branches and worktrees.**
- The wave branch is `husk-skill-and-fix`, in this worktree. First run `git rebase origin/main`.
- For each teammate: `git worktree add ../husk-w1-<name> -b husk-w1-<name> husk-skill-and-fix`, made after T0 is merged.
- Give the worktree path in the teammate's brief. Never pass `isolation` next to `name`.
- Teammates commit only their own files. The lead merges branches with `--no-ff` in the order above.

**Lead context budget and succession point.**
- The lead reserves at least 50% of its window for leading.
- It reads reports of ≤40 lines, `git diff --stat` and TAP plan lines, never full teammate diffs.
- **Succession point:** once W1 has landed, deploy has converged and the replay is GREEN on origin/main, the lead fires W2 and W3 as S sessions (`handoff-fire.sh --prompt-file … --worktree … --goal '<end state> — proven by <command>'`). It then recycles (`handoff-fire.sh --recycle`) or ends with the Session Close Protocol. W2 and W3 never run in the lead's context.

**Gates** (each unit, then the lead on the merged branch):
1. Syntax: `/bin/bash -n` on every changed shell file, and `python3 -m py_compile bin/kitty-fullscreen-guard lib/kitty-fs-kitten.py`.
2. Each touched suite runs alone under /bin/bash 3.2: `env PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v bats)")" bats tests/<suite>.bats`.
   - Assert the `1..N` plan line. A cc-bats deferral is not a result.
   - T3 also runs `tests/completion-assert*.bats` and `tests/session-continue*.bats`, because the shared lib changes under them.
3. Bare `shellcheck <changed files>`, which is the gate's literal form (`scripts/ship-land.sh:3545`).
4. `bash scripts/test-hermeticity-lint.sh`, `bash scripts/test-afunix-path-lint.sh`, and `python3 scripts/bats-assert-liveness-fix.py` on each changed suite.
5. The cross-closer lint (§4 W1b) must be empty.
6. Every negative assertion is a final `run …; [ "$status" -eq 1 ]`, never a mid-test `!`.

**Landing and converge.**
- Land with the project-local /ship, `bash scripts/ship-land.sh`, run bare as its own Bash call and never wrapped in a timeout. Read its verdict, including the smoke line: LANDED means landed, not tested.
- Verify by content: `git ls-tree origin/main -- <paths>`, plus an empty `git diff origin/main -- <paths>`.
- Converge: `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`.

**Follow-On Gate.** A wave after W1 starts only when the previous wave has landed and converged and its suites are GREEN on origin/main.
- W2 and W3 are mandatory and pass by definition: W2 completes the GOAL for launch sites that are not runner-rooted, and W3 is a Done criterion.
- Each W4 item also needs at least 7 days of W3 rows showing its trigger is non-zero, or the operator ruling it names.

**Every brief bans these by name, with the reason** (nobody can answer a permission prompt):
- heredoc file edits through Bash;
- bare `git stash`, `rm -r` and `git reset --hard`;
- any kitty, `it2` or `kitty @` call against the live terminal, and closing, killing or resuming any live pane.

Tests use stubs and fixtures only. Every brief also carries "stop on issue, message the lead".

---

## 1 Why the class recurs

- A pane's end of life is a relay among about 12 actors. Each reads a different subject: transcript text, whole-cwd dirt, custody, kitty state, another tool's stdout. Each fails closed to the same resting state, a kept shell (CENSUS.md:20-40, §3 :68-88).
- Each fix added or narrowed one actor: 430 matching trunk commits; 52 closer-file commits since 09-15 [C CENSUS §4a].
- No shared predicate exists, so a lesson never carries to the next actor (CENSUS.md:36-40).
- Pane 289 shows the whole class in one sample. Its runner turned a temporary refused-fs into a permanent shell. Then four re-judges applied four rule sets, and the last painter won with "resume … stopped mid-task" (REPORT.md §2.2, :46-62).
- Since 10-16 one cause dominates: stock kitty's guard refusing a sole pane in a fullscreen window. It accounts for 22 of 28 runner keeps [C CENSUS.md:58-64]. That makes "hold, then close when safe" the operative mechanism, not "retry the RPC".
- Track A, §2.3 (REPORT.md:63-77): seven shell tails plus three `|| exec zsh -i` wrappers make the shell the default.

## 2 The invariant

**Pane states.** The runner writes one of these into `tail` of `~/.claude/run/pane-exit/<wid>.json`:

| state | `tail` | ended by |
|---|---|---|
| RUNNING | none for this launch | the session |
| CLOSED | `closed` | the runner's `exit 0`, after a guard rc 0 or 4, a clear `--any-fs` read, or a dead `KITTY_PID` |
| HELD | `hold:fs` / `hold:unreadable` | the runner, after two safe reads at least 10 s apart; or the operator's Cmd-W; or kitty itself gone |
| KEPT | `keep:<r>`, r ∈ crash, recycle, kill-switch, not-a-session, no-guard, no-recycle-lib, fallback | the operator, the crash/resume path, or a typed relaunch |

A bare shell over a dead fleet session that is not `keep:*` is an anomaly. W3 counts it.

**Session verdict: one function, `pe_verdict` (lib/pane-end.sh).** The closer, sweep, watchdog and (through the closer's token) the painter all use it. The first matching row wins:

| # | facts | STATE |
|---|---|---|
| 1 | custody discharged (return/abandon) since the session start | COLLECTED |
| 1b | **no transcript, or a transcript with zero records, and end=clean** (pane 304, added 2026-10-25) | DONE: the session never received a turn, so nothing in the cwd can be its own work. With end=crash or unknown: CANTTELL |
| 2 | Agent-Teams member | DONE if `pe_work team` ∈ {clean, -}, else CANTTELL |
| 3 | last close `yes`, or a self-close stamp since start | DONE if `pe_work <mode>` ∈ {clean, -}; else, if end=crash, OWNED (custody open) or RESUME; else CANTTELL |
| 4 | end=crash | OWNED if custody is open, else RESUME |
| 5 | anything else (close `no` or `-` on a clean or unknown end) | CANTTELL |

Definitions:
- **end:**
  - `crash` if the crash-log class (passed in, or the latest row for the sid) is CRASH;
  - `clean` if it is RECYCLE;
  - with no row: `crash` for a fresh exit record with rc ∉ {0, 75}, `clean` for rc ∈ {0, 75};
  - otherwise `unknown`.
- **mode:** `own` when end=clean. `strict` when end is crash or unknown.
- **`pe_work own`:** the session's Edit/Write-recorded paths that are dirty, then its own unlanded commits.
- **`pe_work strict`:** whole-cwd porcelain (HEAD's gate 4), then its own unlanded commits.
- **`pe_work team`:** whole-cwd porcelain only (HEAD's gate 4).

Tie-break: for a crash, unprovable work resolves toward keeping and resuming. For a clean end it resolves toward triage, never toward resume.

**Hard invariants, and the mechanism that holds each:**

1. **Never empty the last pane of a native-fullscreen window.**
   - Every runner exit follows one of: a guard rc 0 that counted the window's pending removals (W1c identity claims); rc 4; two clear `--any-fs` reads; or a dead `KITTY_PID`.
   - From the moment the command returns, INT, QUIT, TSTP, TERM and HUP are SIG_IGN. Any unplanned exit runs the EXIT trap, which execs a shell.
   - A guard that cannot answer (rc ∉ {0, 3, 4}) escapes to `keep:fallback`.
2. **Never close a pane with a live job.** The runner decides only after its command returned, as HEAD does (`bin/cc-pane-runner:576-578`). For outside closers, `cc-pane-close` gate 2 (`:447-487`) refuses any non-shell process in the tree; a held runner's `sleep` or guard child counts.
3. **Never resume a finished session.**
   - RESUME requires end=crash (§2 rows 3-4). A clean or unknown end never yields RESUME.
   - `cc-husk-sweep --resume` types only RESUME rows; `--all` adds DONE and UNKNOWN.
   - The painter renders the closer's computed state, never a substring of its reason.
4. **A crashed session with its own uncommitted work is kept and resumed.**
   - `keep:crash` is unchanged (`_kept_line`, `:358-375`).
   - A known or unknown crash takes `strict`, which is whole-cwd porcelain, the same as HEAD's gate 4.
   - The successor loop now carries the successor's real exit status to the runner. At HEAD it returns 0, so a crashed successor's runner pane closes [M, §3 D14].

## 3 Decision log

| id | contested point | choice | why |
|---|---|---|---|
| D1 | where the hold runs | in the runner's own process (merged D1) | The runner is the window's process. `_launch` never returns (`:546-580`), so nothing is re-read from disk. Signal survival was measured [C merged §7 hold probe]. |
| D2 | when signals are ignored | from the command's return: `_guarded` right after `_rc=$?` (`:572/:574`) and on entry to `_no_command` (`:614`). `_fallback` (`:100`) resets them with `trap -` before exec. | **break 4.** HEAD's `_close_pane` guard call (`:329`) runs with default dispositions, so a ^C there ends the window unguarded [C skeptic `drive_gate.py`: INT/QUIT/TERM/HUP kill it]. |
| D3 | an orphaned or deaf hold | ignore HUP; exit when `kill -0 $KITTY_PID` fails; on a `kitten-failed` read, ask `--any-fs --kitty-pid $KITTY_PID`, and a clear read counts as safe | **break 6.** A held runner ignores HUP, so HEAD's no-socket SIGHUP close (`bin/cc-pane-close:530-539`) cannot reach it. The same no-socket proof the closer accepts is 2 lines in the hold. |
| D4 | who stands down for a runner pane | only the self-close watcher, which reads `tail`. **No name rules** in the watchdog, drainer or sweep. | **break 26.** During a hold the foreground holds `sleep` or the guard. That is not a shell to `pane_procs_are_shells` (`hooks/lead-crash-watchdog.sh:1640-1647`) or to closer gate 2. A held pane is a clean exit, so `pe_verdict` can never give it RESUME. Residual: a watchdog paint landing in a bash-only instant (estimated at milliseconds per 5-300 s poll) can overwrite the hold paint. It cannot close a sole fullscreen pane (the guard) and cannot paint RESUME. |
| D5 | how the watcher reads the decision | `hf_pane_exit_tail` waits for a record with `ts ≥ _sc_t0` **and** a `tail` key, polling 1 s up to 20 s. It polls only when `CC_PANE_RUNNER_OWNS_CLOSE` equals the pane id. | **break 23.** The record is written before the decision (`:577-578`), so a test on `ts` alone races the runner's `_gate` (≤5 s kitten timeout). |
| D6 | rollback | `git revert` of the W1 commits. No new env or file switch. | An env var cannot reach kitty-spawned panes (`bin/kitty-fullscreen-guard:75-77`). The existing kill switches remain: `CC_PANE_CLOSE_ON_EXIT=0` and `CC_KITTY_FS_GUARD=off`. |
| D7 | concurrent "not last" answers | **identity claims, counted against the snapshot.** The kitten also returns `pane_wids`, one per window group. Under `flock` on `claims-<kitty pid>.json`, the guard computes remaining = (`pane_wids` − self − other wids told safe within 30 s). It is safe-not-last iff remaining ≥ 1, and only then writes its own claim. Remaining = 0 takes the existing last-pane path (FS read). There is no `refused-inflight`, no `--peek`, no retry loop and no count-based release. | **breaks 1, 25.** Count-based release is unsound when a join or two removals overlap [C skeptic `claim_model.py`: both sequences leave 0 panes; reproduced]. Counting relative to the snapshot is sound for stale snapshots too: a gone wid is neither listed nor counted, and a claimed wid is excluded until its TTL ends. Dropping `--peek` and `refused-inflight` deletes the runner's retry, the mislabel to `unreadable`, and the rollback hazard of an unknown flag. Cost: a `--dry-run` claim blocks a sibling's close for ≤30 s, failing closed. |
| D8 | one decision function | `lib/pane-end.sh`: `pe_facts`, `pe_end`, `pe_work`, `pe_verdict` (§2). It replaces the three close readers (`bin/cc-pane-close:342` `transcript_facts`, `bin/cc-husk-sweep:452` `facts_of`, `hooks/lead-crash-watchdog.sh:1677` `pane_last_close`), the three dirt subjects (`cc-pane-close:510`, `cc-husk-sweep:508-515`, `lead-crash-watchdog.sh:1664-1671`), the closer's own custody and stamp readers (`bin/cc-pane-close:368`, `:381`), and `verdict_of` (`cc-husk-sweep:516`). Pane process state stays the runner's `tail`. | **breaks 16, 21, 14.** This is census §6 item 2. One predicate computes strictness once. Custody uses the one reader, `lib/pane-custody.sh` (its own header says it is "the ONE reader"). |
| D9 | strict mode | strict = HEAD's whole-cwd porcelain. It is triggered by end ∈ {crash, unknown} or by a team member. `dirt_unreachable_by_session` is **not** used. | **breaks 2, 3, 9, 10, 13.** Mtime can be set: `git mv` and `cp -p` of an old file pass the per-path proof [M `bash /tmp/husk-fix-design/skeptic-safety/mtime-probe.sh`: `session_dirty_mine rc=1`, `dirt_unreachable_by_session rc=0 predates=1`]. RECYCLE causes are not crashes [M `jq -r 'select(.ts >= "2026-10-01") \| .class' ~/.claude/logs/claude-crashes.jsonl \| sort \| uniq -c`: 416 CRASH, 1659 RECYCLE]. A strict false keep costs a husk, not work. Clean-exit residual: a successor's uncommitted handed-off work, or Bash-only writes after a stale yes, can close the pane. The files stay on disk (the `session-writes.sh:45-53` doctrine). |
| D10 | unlanded | `session_unlanded_mine` diffs `"$trunk"...HEAD`, three dots (`hooks/lib/session-writes.sh:630`). Trunk resolves through origin/HEAD, then origin/main, then origin/master (`scripts/bats-shellcheck-lint.sh:565-569`); if none resolves, the step is skipped. | **breaks 8, 12.** Two dots read a behind-only checkout as unlanded [M `bash …/skeptic-decision/p1-behind.sh`: ahead 0, behind 1, rc 0 two-dot, three-dot empty]. Of 201 repos, 32 lack origin/HEAD [M `bash …/p4-originhead.sh`]. This also fixes the false "mine" in completion-assert (`:863`) and session-continue (`:1238`). |
| D11 | what the painter paints after a closer refusal | gate-3/4, guard and remote-down refusals end in `[state=<DONE\|RESUME\|CANTTELL\|OWNED:<pane>>]`. `--recompute` reads that token. Delete the substring map at `bin/cc-pane-verdict:85-90`, including the `UNSAVED` sed. Keep the closer's verb lines (`:84`, DONE), the never-launched rule (`:79-82`, NOTHING) and the guard-row mapping (`:71-78`). No token means CANTTELL. | merged D9, plus census §6 item 2: the painter renders, it does not decide. |
| D12 | what `--resume` types | RESUME rows only. `--all` adds DONE and UNKNOWN. OWNED is never resumed. Rewrite the header's "UNKNOWN is resumed" (`bin/cc-husk-sweep:42-45`). | **breaks 11, 14, 24.** These cases were resumed at HEAD (`:609`): yes with a removed cwd (`-`), yes with a peer-edited own file, and a yes visible only in a thinking block. A crash still reaches RESUME through §2 row 4. |
| D13 | runner-rooted panes whose command never returns | in W1. lr waits for claude's status (copy `bin/reso-resume-one:1108-1110` after `interact` at `lr-fire-resume.sh:2235`). Under ownership, lr (`:2250-2304`) and reso (`:1133-1216`) claim a staged successor with keep=0, or `exit "$rc"`. Ownership = `CC_PANE_RUNNER_OWNS_CLOSE` equals `$KITTY_WINDOW_ID` (runner `:569` exports the window id, not `1`). | **break 17.** lr panes are runner-rooted (`scripts/limit-recover/lr-lib.sh:1339-1341`) but exec their own shell (`:2304`): 6 husks since 10-19, 5 after yes [C REPORT §3]. |
| D14 | the staged successor in a runner pane | **keep the HEAD path:** `bin/cc-close-attrib:600-626` claims the stage and execs it with keep=0, inside the runner's command. Fix the loop so it ends with the last successor's status (`lib/pane-successor.sh:214-229` and the `_tail` at `:239-240`). | **break 22, its main claim rejected.** The staged path never reaches a `keep:recycle` shell; only a typed relaunch does (W2.5). New finding while checking it: the loop ends in `unset`, so its status is 0 [M `bash /tmp/husk-fix-design/editor-probe/loop-rc.sh`: successor returns 143, loop returns 0]. A crashed successor's runner pane therefore closes at HEAD, which breaks invariant 4. |
| D15 | the census population | W3 counts fleet registrations (watchdog `registered session=… pane=N` in this kitty's lifetime) whose window foreground is only shells, then sub-classes them by `tail`. `keep:fallback` and "no record" are counted. | **break 18.** A record-keyed census cannot see lr, reso, boot-resume or layout roots. |
| D16 | an unknown verdict (`pe_work` → `unknown`) | It is at risk. The closer refuses and states CANTTELL, or RESUME on a crash. The sweep gives UNKNOWN or RESUME. | **break 21.** |
| D17 | the husk-pane skill (`97c85f68d`) | rewrite it to defer to `cc-pane-close` and `pe_verdict`. Delete its own decision table (`SKILL.md:86-96`) and manual close path (`:106-124`). Its repaint passes the refusal's `--guard`. | **break 20.** `:68` becomes false after W1b, and `:126-127` paints "closing now" on a pane that just failed to close. |
| D18 | dropped from the merged design | `--peek`; `refused-inflight`; the three runner-name stand-downs (merged `:322-324`); `dirt_unreachable_by_session` in W1b; teammate rc 143/137 → close; a HELD sweep verdict | each is a moving part whose job is done another way (D4, D7, D9) |

**Skeptic breaks: 25 accepted (3 of them in part), 1 rejected.**

| # | sev | verdict | landed as |
|---|---|---|---|
| 1 | high | accept | D7, with identity counted against the snapshot; tests G2 (inverse) and G5 (join) |
| 2 | high | accept | D9: unknown end → strict; arm I2n |
| 3 | med | accept | D9: strict = porcelain; arm I4 |
| 4 | med | accept | D2; arm A1g |
| 5 | med | accept | hold escapes on rc ∉ {0, 3, 4}; the `--peek` cause is gone (D7); arm A1e |
| 6 | low | accept | D3 (`--any-fs` in the hold); arm A1u |
| 7 | low | accept | `_end` removes `_armed` first; arm A1a |
| 8 | high | accept | D10; arm B5b |
| 9 | high | accept | §2 end: class first, RECYCLE = clean; arm B8 |
| 10 | high | accept | same predicate in every caller; arm I2n |
| 11 | med | accept | yes + own dirt → CANTTELL/UNKNOWN; the closer says "in files session X wrote"; arm B7 |
| 12 | med | accept | D10 ladder; arm B5c |
| 13 | low | accept (in part) | resolved by D9 for crashes; the clean-exit residual is documented, and no lineage code is added |
| 14 | low | accept | D8 one reader with the stamp, D12; arm B9 |
| 15 | low | accept | §5 pins every spawned seam, including `CC_PANE_CLOSE_*`; I2 asserts the record was read |
| 16 | high | accept (in part) | D8. Pane process state stays the runner's `tail`, not in the function. Actor table in §4. |
| 17 | high | accept | D13 is in W1 |
| 18 | high | accept | D15 |
| 19 | high | accept | Phase 0 |
| 20 | med | accept | D17 |
| 21 | med | accept | D8 and D16 |
| 22 | med | **reject** | Its premise is wrong for staged successors (D14). Flipping `cc_pane_successor_exec`'s default would change operator shells (D2 ruling). Kept: the corrected lint allowlist (W2) and the loop status fix it led to. |
| 23 | med | accept | D5; arm A2d |
| 24 | med | accept | D12; arm B6 |
| 25 | low | accept | D7 makes it moot. A move inside one OS window keeps its claim ≤30 s, which fails closed. |
| 26 | low | accept | D4 |

## 4 Waves

**Actors before and after** (12 at HEAD, CENSUS §1):

| actor | HEAD decides with | after W1 | after W2 |
|---|---|---|---|
| runner | rc; a refusal becomes a shell | rc, then close, hold or a recorded keep | every fleet launch rooted here |
| self-close watcher | an RPC close, then husk-fs alarm and row | stands down on `closed`/`hold:*` | = |
| watchdog | its own close/work readers | `pe_verdict` | = |
| cc-pane-close | gates 3+4 with its own readers | `pe_verdict` | = |
| cc-pane-verdict `--recompute` | substring map | renders the closer's token | = |
| cc-husk-sweep | its own readers; UNKNOWN typed | `pe_verdict`; types RESUME only | typed resume through the runner |
| guard | stateless count | identity claims | = |
| lr / reso tails | exec a shell | return rc under the runner | `rr_close_on_clean_exit` deleted |
| husk-pane skill | own table, manual close | defers to closer and verdict | = |
| drainer, zshexit, boot-resume, custody-deathwatch | unchanged | unchanged | W4 candidates |

Four independent "is it finished?" deciders become one.

### W1 — the GOAL wave (lands alone; RED→GREEN on `tests/pane-289-replay.bats`)

Size [E: sketch line counts]: code about +390 / −265, tests about +1,000 new plus about 150 pin lines. Rollback: revert the W1 commits.

**W1a runner (T1)**: `bin/cc-pane-runner`.
- Replace `_close_on_exit` (`:257-278`) and `_close_pane` (`:283-349`) with `_guarded`, `_exit_policy`, `_gate`, `_end`, `_hold`, `_hold_class`, `_hold_paint`, `_hold_done`, `_escape` and `_pane_exit_tail`.
- Delete the `guard-fullscreen`/`guard-unreadable` husk rows (`:332`, `:337`) and the "accepted cost is a husk" doctrine (`:300-304`). Rewrite `:46-63`.
- `_pane_exit_record` (`:426-443`) keeps its fields in globals. `_pane_exit_tail` rewrites the record atomically, adding `"tail"`.
- `:569`: `export CC_PANE_RUNNER_OWNS_CLOSE="${KITTY_WINDOW_ID:-1}"`.
- `:576-579` becomes `_guarded; …; _exit_policy …; _end …`.
- `_no_command` (`:614-623`) calls `_guarded`, sets `_TAIL=close` (or `keep:kill-switch`), then `_PV_STATE=NOTHING _end …`. It must be `set -u`-clean.

Load-bearing sketch (bash 3.2; nothing runs in a subshell):
```bash
_guarded() { trap '' INT QUIT TSTP TERM HUP; trap '_escape' EXIT; }        # from the command's return (D2)
# _fallback() gains, as its first line:  trap - INT QUIT TSTP TERM HUP EXIT
_gate() { # → _TAIL
  _recycle_lib || { _TAIL=keep:no-recycle-lib; return; }
  cc_pane_recycle_pending "${KITTY_WINDOW_ID:-}" && { _TAIL=keep:recycle; return; }
  { [ -n "${KITTY_WINDOW_ID:-}" ] && [ "${CC_KITTY_FS_GUARD:-}" != off ]; } || { _TAIL=closed; return; }
  _guard_bin || { _TAIL=keep:no-guard; return; }
  local o rc=0; o="$(cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-runner 2>&1)" || rc=$?
  case "$rc" in 0|4) _TAIL=closed ;; 3) case "$o" in *"refused (refused-fs)"*) _TAIL=hold:fs ;; *) _TAIL=hold:unreadable ;; esac ;; *) _TAIL=keep:no-guard ;; esac
}
_end() { # never returns
  [ -n "${_armed:-}" ] && rm -f "$_armed" 2>/dev/null          # break 7
  [ "$_TAIL" = close ] && _gate
  _pane_exit_tail "$_TAIL"
  case "$_TAIL" in
    closed) _DONE=1; exit 0 ;;
    hold:*) _hold "${_TAIL#hold:}" ;;
    keep:crash) _kept_line "$1" "$2" "${3:-0}" "${4:-true}" ;;
    keep:no-guard|keep:no-recycle-lib) _say warn "pane kept, not closed" "${_TAIL#keep:}"; _husk_row "${_TAIL#keep:}" what="$1" ;;
  esac
  _fallback ""
}
_hold() { # exit 0 only once removing this pane cannot empty a fullscreen window
  local c="$1" s="${CC_PANE_HOLD_STEP_S:-5}" w ok=0 n=0 rc o cap
  _hold_paint "$c"; w="$s"
  while :; do
    /bin/sleep "$w"; n=$((n + 1))
    if [ -n "${KITTY_PID:-}" ] && ! kill -0 "$KITTY_PID" 2>/dev/null; then _hold_done; fi
    if [ -n "${CC_PANE_HOLD_MAX_POLLS:-}" ] && [ "$n" -gt "$CC_PANE_HOLD_MAX_POLLS" ]; then exit 1; fi
    rc=0; o="$(cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-hold 2>&1)" || rc=$?
    if [ "$rc" = 3 ] && [ -n "${KITTY_PID:-}" ]; then case "$o" in *kitten-failed*)   # D3
      rc=0; cc_run "$_GUARD" --any-fs --kitty-pid "$KITTY_PID" --tool cc-pane-hold >/dev/null 2>&1 || rc=3 ;; esac; fi
    case "$rc" in
      0|4) ok=$((ok + 1)); [ "$ok" -ge 2 ] && _hold_done; w=$((2 * s)) ;;
      3)   ok=0; case "$o" in *"refused (refused-fs)"*) _hold_class fs ;; *) _hold_class unreadable ;; esac
           cap=$((12 * s)); [ "$c" = unreadable ] && cap=$((60 * s)); w=$((w * 2)); [ "$w" -gt "$cap" ] && w="$cap"; [ "$w" -gt 0 ] || w="$s" ;;
      *)   exit 1 ;;                                              # break 5 → _escape
    esac
  done
}
_hold_done() { _DONE=1; _pane_exit_tail closed; exit 0; }
_escape()    { [ "${_DONE:-0}" = 1 ] && return; _pane_exit_tail keep:fallback; _husk_row runner-escape; _fallback "the runner ended unexpectedly"; }
```
`_exit_policy`, `_hold_class` and `_hold_paint` are as in merged.md:332-339 and :383-385; the paint passes `--guard held`.

Tests:
- New `tests/cc-pane-runner-hold.bats`: arms A1, A1b, A1x, A1k, A1u, A1e, A1a, A1g and A1t, as in §5 but as unit forms.
- Pin inversions:
  - `tests/pane-close-from-inside.bats:186-192`;
  - `tests/cc-pane-runner-no-command-closes.bats:52,81,89,99,112`;
  - `tests/cc-pane-runner-exit75-closes.bats:59,63,103,136,138`. A refusal now holds and then closes on the sequence `3,0,0`; "kept" moves to the `MAX_POLLS` escape case; `:59` record keys gain `tail`.
- Structural lint inside the hold suite: exactly one `exec "${SHELL` in the runner (`_fallback`), and every post-launch `_fallback` is preceded by a `keep:` tail write.
- Mutants: release on the first safe read (A1b); traps set only inside `_hold` (A1g); no `kill -0` (A1k); no rc escape (A1e).

**W1b one verdict (T3 lib, then T4 and T5 consumers).**
- `lib/pane-end.sh` (new, sourced, bash 3.2, `set -u`-clean). It sources `lib/pane-custody.sh` and `hooks/lib/session-writes.sh` from beside itself, falling back to the live layer. Seams: `CC_PANE_EXIT_DIR`, `CC_CRASH_LOG`, `CC_FIRED_DIR`, `CC_PE_READ_TIMEOUT_S` (default 30), plus pane-custody's `CC_CUSTODY_DIR`.
  - `pe_facts <tp>` → `team␟close␟cwd`. One bounded python pass over assistant **text** blocks; a cut read gives `-`.
  - `pe_end <sid> <pane> <since> [class]` → `crash|clean|unknown` (§2).
  - `pe_work <tp> <dir> <own|strict|team>` → `-|clean|dirty:N|unlanded:N|unknown`. A clean tree skips the transcript parse (`GIT_OPTIONAL_LOCKS=0`).
  - `pe_verdict <sid> <tp> <pane> [since] [class]` → `STATE␟why␟work␟close␟end␟owner␟cwd`. `since` defaults to `cc_transcript_start_epoch`.
- `hooks/lib/session-writes.sh:630`: change `..` to `...`.
- **cc-pane-close (T4):**
  - Delete `transcript_facts` (`:342-366`), `custody_ruled_done` (`:368-380`) and `self_closed` (`:381-390`).
  - Gate 3+4 (`:489-512`) becomes one `pe_verdict` call. COLLECTED or DONE goes on to the guard. Anything else refuses with the reason plus `[state=…]`.
  - The `no transcript for session` refusal (`:494`) no longer ends the gate: an absent or zero-record transcript goes to `pe_verdict` row 1b (pane 304). `pe_facts` returns `team=0 close=- cwd=<registration cwd>` and a `records=0` marker for it; T3 owns that branch, T4 the call site.
  - Keep the never-launched, `moved_live` and STRANDED arms as identity pre-checks.
  - Export `CC_PANE_EXIT_DIR="$EXITDIR" CC_FIRED_DIR="$FIRED"` before the call.
  - Reason texts: "N uncommitted change(s) in files session X wrote"; "N uncommitted change(s), and session X did not end cleanly, so every change counts"; "commits touching files session X wrote are not on <trunk>"; "session X's own writes cannot be read".
- **cc-pane-verdict (T4):**
  - Replace the STATE map at `:83-90` with the token read (D11).
  - Add a `held)` guard row: "closes itself when its window gains a pane · Cmd-W now".
- **cc-husk-sweep (T5):**
  - Delete `facts_of` (`:452-505`), `work_of` (`:508-515`) and `verdict_of` (`:516-519`).
  - `:555-569` becomes `pe_verdict` with `CC_CRASH_LOG="$CRASH"`. Mapping: COLLECTED → COLLECTED, DONE → DONE, RESUME → RESUME, CANTTELL → UNKNOWN, OWNED → `OWNED→<pane>` (never resumed).
  - `:609` plans RESUME, or DONE and UNKNOWN with `--all` (D12). Rewrite the header at `:42-54`.
- **Watchdog (T5):**
  - Delete `pane_work_state` (`:1664-1671`) and `pane_last_close` (`:1677-1711`).
  - `:1932` reads `work`, `close` and `st` from `pe_verdict "$sid" "$tpath" "$LEAD_PANE" "" "$class"`.
  - The `RECYCLE:*` (`:1995-2004`) and `*)` (`:2005-2030`) arms take `pvs` from `st`; their text rows stay.
  - The retired-* and moved-live arms are unchanged.
- **Skill (T4):** D17.
- **Cross-closer lint:** `git grep -nE 'status --porcelain|origin/main\.\.HEAD' -- bin/cc-pane-close bin/cc-husk-sweep hooks/lead-crash-watchdog.sh bin/cc-pane-verdict` must be empty. It shows 5 hits at HEAD [M, that command].
- **Pin edits:**
  - In `tests/lead-crash-pane-verdict.bats:39` and `tests/cc-husk-sweep.bats:93-100`, the fixture transcript records a `Write` of its dirty file, so the dirt stays the session's own.
  - `tests/cc-pane-verdict.bats:77`: "unsaved" changes to CANTTELL; `:75` is the control.
  - `tests/cc-pane-close*.bats`: custody stubs move from `CC_PANE_CLOSE_CUSTODY_BIN` to `CC_CUSTODY_DIR` store files.
  - Pre-grepped hits [M `git grep -c -F`]: "nothing says session" in 3 suites; `verdict":"UNKNOWN` in 3; `guard-unreadable` in 4.
- **Tests:** `tests/pane-end.bats` covers every row of the §2 table, each mode, the trunk ladder and three dots.
  - Mutants: two dots (B5b); trunk = origin/HEAD only (B5c); strict ignores class (I2n); strict uses the per-path proof (I4); team not strict (I3); RECYCLE read as a crash (B8).

**W1c guard claims (T2).**
- `lib/kitty-fs-kitten.py:93-111` (the `describe()` reply): add `"pane_wids"`, one id per window group, counted exactly as `_panes()` counts them.
- `bin/kitty-fullscreen-guard` `decide()` (`:761-762`): when scope is `pane` and `last_for.pane is False`, call `claim_gate(info, wid)` (D7). Its effect:
  - a missing `pane_wids`, or one whose length differs from `panes_in_os_window`, gives `claim:"unavailable"` and HEAD semantics;
  - an `OSError` gives `claim:"error"` and HEAD semantics;
  - remaining = 0 falls through to the last-pane path.
- The verdict row (`log_row` at `:967-995`) gains `pending` and `claim`. Update the EXIT CODES docstring.
- Tests in `tests/kitty-fullscreen-guard.bats`, using the stub kitten and the fake-boss harness at `:319-339`:
  - G1: A is safe and claims; B, from the same snapshot, takes the last-pane path and gets `refused-fs`.
  - G2: the count dropped because C left. A claims. B, holding a stale snapshot of 3, is refused.
  - G3: a claim older than 30 s is ignored.
  - G4: a wid's own claim never blocks itself.
  - G5: the skeptic's join sequence: D is refused.
  - G6: no `pane_wids` gives HEAD semantics.
  - G7: an unwritable claims file gives `claim:"error"`.
  - G8: the kitten's `pane_wids` length equals `panes_in_os_window` with an overlay group.
- Mutants: no claim check (G1); count-based release (G2, G5); TTL ignored (G3).

**W1d watcher (T6)**: `scripts/handoff-fire.sh`.
- Set `_sc_t0=$(date +%s)` at watcher entry (`:11648`).
- New `hf_pane_exit_tail PANE T0 MAXS` beside `hf_pane_exit_record` (`:6693`). It waits for the `tail` key (D5).
- After `_close_ok=0 _close_rc=0` (`:11831`): if ownership equals the pane and the tail is `closed` or `hold:*`, set `_close_ok=1`, print "pane N belongs to its cc-pane-runner (tail)", and skip the loop. The failure arm (`:11861-11920`) is then skipped; the successor focus still runs.
- In the comments at `:1872-1878` and `:11816-11822`, and `bin/it2-kitty:86-89` and `:1663-1667`: "a fixed fact" becomes "a condition that clears when the window gains a pane or leaves fullscreen; a runner pane holds and closes itself".
- Arms A2, A2s and A2d (§5). Mutants: stand-down removed (A2); accepting a tail-less record (A2d).

**W1e launch returns (T7).**
- `lr-fire-resume.sh:2235`: after `interact`, add `if {[catch {wait} w]} {exit 1}; if {[llength $w] > 4} {exit 1}; exit [lindex $w 3]`.
- Under ownership:
  - `:2273` passes keep=0;
  - before `:2283`, `exit "$lr_rc"`.
- `bin/reso-resume-one`, under ownership: after `:1135`, skip `rr_close_on_clean_exit` (`:1183`), pass keep=0 at `:1210` (`rr_successor_take_exec`), then `exit "$rr_rc"`.
- `lib/pane-successor.sh`: the loop keeps `__ccs_rc` after each `source`. With keep=0 its `_tail` becomes `exit "${__ccs_rc:-0}"`; keep=1 is unchanged (D14).
- Tests:
  - a SIGTERM'd stub makes `lr_rc` ≠ 0;
  - lr and reso exit with the session's rc under ownership and keep a shell when typed;
  - the loop returns 143 for a 143 successor.
- Mutants: no `wait`; no ownership test (an operator launch closes); dropping `__ccs_rc` (S1).

### W2 — every fleet launch rooted in the runner (S; net deletion)

- W2.4: replace the `zsh -ic "$CMD || exec zsh -i"` roots with the runner argv shape (`scripts/handoff-fire.sh:1326-1327`). The roots are at `scripts/boot-resume-launch.sh:258` and `bin/cc-resume-layout.sh:1053`, `:1359`.
  - Retire the doctrine at `boot-resume-launch.sh:240-249`.
  - The lr `argv` fallback (`lr-lib.sh:1342-1345`) refuses rather than launching bare.
- W2.5: typed relaunches become `exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash "$R"`. The builders are `hf_resume_cmd_set` (`scripts/handoff-fire.sh:3776`) and the sweep's typed resume (`bin/cc-husk-sweep:619-628`).
- W2.6: the fleet argv at `bin/kitty-split-launch.sh:146-149` goes through the runner.
- W2.7: delete `rr_close_on_clean_exit` (`bin/reso-resume-one:1136-1186`).
- Lint: `git grep -nE '\|\| exec zsh -i|exec "\$\{SHELL' -- bin scripts lib` gives 10 hits at HEAD [M]. After W2, the allowlist is:
  - `cc-pane-runner:104`;
  - `kitty-split-cwd.sh:38`;
  - `reso-resume-one:236` and `:1216` (typed);
  - `lr-fire-resume.sh:2304` (typed);
  - `pane-successor.sh:240` and `:341`.

  Run the lint against the real tree (break 22).
- Tests: invert the survivability pins `tests/kitty-recovery-launch.bats:467`, `:493` and `tests/handoff-recycle-pane-survives.bats`.
- Size [E: merged W2 minus the parts moved to W1]: about +30 / −150. Rollback: revert.

### W3 — the standing census (S)

- New `scripts/pane-census.sh`, called by `scripts/pane-close-retry.sh` before its empty-queue exit (`:63-64`). It is bounded to 20 s and its rc is ignored.
- Population (D15): panes registered in this kitty's lifetime that `kitty @ ls` (via `bin/cc-kitty-socket`) still lists.
- Classes:
  - `running`: claude in the foreground;
  - `held`: a runner in the foreground with `hold:*` (age from the record);
  - `deciding`: a runner with no tail;
  - `kept[r]`: shells only, with `keep:r`;
  - `unexplained`: shells only, with any other tail, `keep:fallback`, or no record when the pane was fired (`cc-fired/<pane>.json`) or runner-launched;
  - `operator`: neither of those, until D2 is ruled.
- One row per tick to `~/.claude/logs/pane-census.jsonl`.
- Page once per (kitty pid, pane) when a pane is `unexplained` 2 ticks running, and when a hold is older than 6 h.
- rc 124 becomes its own class (`pane-close-retry.sh:310-313`). Read `first_ts` before `pcq_remove` (`:279`).
- Size [E]: +80 code, +60 tests.

### W4 — candidates (S each, past the Follow-On Gate)

- W4a: placement ranks held windows first (`scripts/lib/pane-placement.sh:115`).
- W4b: a final-turn close reader inside `pe_facts`, which removes the stale-yes residual.
- W4c: the Cmd-W confirm dialog reads "held" (`bin/kitty-confirm-close:250-290`).
- W4d: boot-resume retires on `prompt_input_exit` (`scripts/boot-resume.sh:783`).
- W4e: custody-deathwatch triage text (`:394`).
- W4f: an atomic close-if-not-last in the kitten, which would replace the claims.
- W4g: delete the watcher's husk-fs arm (`handoff-fire.sh:11899-11918`) and the drainer's operator hold (`pane-close-retry.sh:282-288`, `:315-318`) once W3 shows 0 `unexplained`/`unrooted` fleet husks for 7 days and D2 is ruled.

## 5 `tests/pane-289-replay.bats` spec

**Fixture** `tests/helpers/fixture-289.bash`. The subject root is `REPO="${CC_REPLAY_REPO:-$BATS_TEST_DIRNAME/..}"`.

Pinned seams. Every spawned program's own spellings are pinned [M `grep -o '\${CC_…' <subject>`]:

| subject | seams |
|---|---|
| runner | `HOME=$T/home`, `CC_PANE_EXIT_DIR`, `CC_PANE_CLOSE_QUEUE_DIR`, `CC_SAY_LOG`, `CC_PANE_RUNNER_TTY` (a file), `CC_PANE_VERDICT_KITTY_BIN` (a logging stub), `CC_PANE_VERDICT_DIR`, `CC_KITTY_FS_GUARD` (the guard stub), `CC_REGISTRY_DIR`, `CC_BEAT_DIR`, `CC_PANE_WEDGE_WATCH=0`, `CC_PANE_SUCCESSOR_DIR`, `CC_TERM_KITTY_TO`, `KITTY_WINDOW_ID=289`, `KITTY_PID=$$`, `SHELL=$T/bin/fakeshell` (touches `$T/shell-ran`, exits 7), `PATH=$T/bin:/usr/bin:/bin` (a `git` wrapper logs to `$T/git.log`) |
| closer | `CC_PANE_CLOSE_{EXIT_DIR,FIRED_DIR,WATCHDOG_LOG,STORES,PS_BIN,KILL_BIN,IT2,KITTY_PID,LOG,HANDOFFS_LOG,FIND_BIN,SETTLE_S,REAP_S}`, `CC_CUSTODY_DIR`, `CC_CRASH_LOG` |
| sweep | `CC_HUSK_{PANES_JSON,PS_FILE,CRASH_LOG,WATCHDOG_LOG,STORES,IT2,LOG,HANDOFFS_LOG,KITTY_START_EPOCH,LIVE_SIDS,SESSIONS,CUSTODY_LIB,LR_LIB}` |
| watchdog | `CC_PANE_VERDICT_{TTY_PROCS,SETTLE_S=0,DEV,CWD,PANE,TTY,CFG}`, `CC_ROLES_DIR` |
| watcher | the harness of `tests/handoff-selfclose.bats` |

**World:**
- `$T/personal` is a `git init -b master` checkout with no remote. It has a dozen committed files, including the session's own `reso-walkthrough/short/C-scenes/NOTES.md` and `scene.py`.
- Sibling dirt under `deadlines/items/`: 2 modified and 3 untracked files, `touch -t` 1 h before the session, plus 1 file stamped after the exit.
- Transcript `7555024a-….jsonl`:
  - a user record with `cwd`;
  - an `Edit` of NOTES.md and a `Write` of scene.py, each with a tool_result;
  - the text "Good to close: yes";
  - a final self-close `Bash` with no tool_result.
- Watchdog log: `registered session=7555024a… pid=7000 tty=ttys046 pane=289`.
- Crash log: `{"sid":…,"class":"RECYCLE","cause":"clean-exit"}`.
- Exit record: `{rc:0, claude_started:true, ts}`.
- No custody row.
- Guard stub: reads `$T/guard-seq` (`rc<TAB>stderr`, with the last line repeating) and `$T/anyfs-seq` for `--any-fs`, and logs argv to `$T/guard-log`. Its refusal line is HEAD's real text.
- `claude` stub: touches `$CC_PANE_STARTED_FILE` and exits `$CLAUDE_RC`.

**GOAL arms** (RED on fa9cadc24, GREEN after W1):

| arm | run | asserts after | HEAD symptom |
|---|---|---|---|
| A1 hold, then close | seq `3fs,3fs,0,0`, `STEP_S=0` | status 0; no `shell-ran`; 4 guard calls, the first with HEAD's argv and the rest with `--tool cc-pane-hold`; `tail=closed`; the paint shows DONE plus the `held` row; `say.jsonl` and tty never contain RESUME, "resume" or "stopped mid-task"; no queue row; no `git.log` | status 7, `shell-ran`, husk row `guard-fullscreen` |
| A1g signal during the gate | the guard stub sleeps 3 s; TERM, then INT, to the process group | the runner survives and holds | killed |
| A2 watcher | `__selfclose 289`, `CC_PANE_RUNNER_OWNS_CLOSE=289`, tail `hold:fs`, it2 close rc 70 | no `session close`; no alarm; no row | husk-fs alarm and row |
| A2d delayed tail | the record gains `tail` 3 s after the watcher starts | as A2 | as A2 |
| B1 closer | `cc-pane-close --pane 289 --dry-run`, zsh-only tree, guard rc 0 | `WOULD CLOSE … Good to close: yes` | `REFUSED … 6 uncommitted` |
| B1fs | as B1, guard refused-fs | `refused-fs … [state=DONE]`, no "uncommitted" | gate 4 first |
| B2 painter | `--recompute --closer-out '<HEAD's 138-change refusal>'` | CANTTELL; no "stopped mid-task", "unsaved" or `--resume` | RESUME |
| B3 sweep | `--json`, then a custody `return` | `"work":"clean","verdict":"DONE"`, then COLLECTED; `--resume --yes` types nothing | dirty → RESUME |
| B4 watchdog | `--pane-verdict … RECYCLE clean-exit`, procs `Ss+ -zsh` | `pvs=DONE` | CANTTELL |
| B5 / B5b | a sibling commit ahead (deadlines/ only) / the checkout behind origin by a sibling commit touching NOTES.md | sweep clean/DONE; watchdog DONE | unlanded → RESUME / CANTTELL |
| B6 | the cwd removed after landing | DONE; nothing typed | UNKNOWN, typed |
| B7 | a peer edits NOTES.md after the exit | no RESUME anywhere; sweep UNKNOWN, not typed; the closer says "in files session 7555024a wrote" | RESUME, typed |
| B8 | crash row `RECYCLE deliberate-teardown` | DONE | RESUME |
| B9 | the yes only in a thinking block, plus a self-close stamp | sweep DONE; not typed | UNKNOWN, typed |
| B10 pane 304 | a registration for sid `d0d00017…` with NO transcript in any store (and a variant with a 0-record `.jsonl`), crash row `RECYCLE clean-exit`, exit record rc 0, sibling dirt in the cwd | closer `WOULD CLOSE` (row 1b); painter not RESUME; sweep DONE/COLLECTED, nothing typed | closer `REFUSED — no transcript for session` (33× live), painter CANTTELL |
| L1 | the extracted lr tail under `script(1)`, `lr_rc=0`, ownership | exits 0; no `shell-ran` (skips without `script`) | execs the shell |
| S1 | runner plus `cc_pane_successor_exec <claimed> 0`, with a successor returning 143 | status 7, `tail=keep:crash`, the guard never asked | rc 0, pane closed |

**Equivalence guards** (GREEN on HEAD and after; each named mutant turns its guard red):

| arm | facts | asserts | mutant |
|---|---|---|---|
| I1 | NOTES.md dirty (recorded Edit), `CLAUDE_RC=143`, crash row CRASH | `keep:crash` (after W1), guard not called, closer REFUSED, sweep RESUME | crash routed to the hold |
| I2 | stale yes, then a Bash-only own write; crash row CRASH; exit record rc 143 | closer REFUSED (a precondition asserts it read the record via `CC_PANE_CLOSE_EXIT_DIR`); sweep RESUME | strict ignores class |
| I2n | I2 with no exit record (a non-runner pane) | closer REFUSED | as I2 |
| I3 | teammate (C2 shape), no recorded writes, an untracked file | REFUSED; no `session close` | team not strict |
| I4 | a crash; the own work is a `git mv` of an old file | REFUSED | strict uses the per-path proof |
| B5c | no origin/HEAD symref; an own unpushed commit | sweep not DONE; watchdog not DONE | trunk = origin/HEAD only |
| C1 | no yes; rc 143 | shell kept; guard not asked; never held | crash routed to the hold |
| D composed | after A1: `env -i HOME=$HOME PATH=/usr/bin:/bin /bin/bash scripts/pane-close-retry.sh` with logging stubs | closer and recompute stubs never called | a husk row written on hold |

The unit arms (A1b, A1x, A1k, A1u, A1e, A1a, A1t, A2s, G1-G8) live in each unit's own suite.

**RED-on-HEAD proof.**
1. `PRE=$(mktemp -d) && git archive fa9cadc24 bin lib hooks scripts skills | tar -x -C "$PRE"`.
2. `CC_REPLAY_REPO="$PRE" bats tests/pane-289-replay.bats`: every GOAL arm is `not ok` with its HEAD symptom, and every guard is `ok`.
3. On the fix branch, `bats tests/pane-289-replay.bats`: all are `ok`.
4. Paste both TAP outputs, including `1..N`, into the W1 commit message.

Each mutant is run once by hand on a scratch copy whose unmutated control passes first.

## 6 Done criteria

1. The replay is RED on the fa9cadc24 artifact and GREEN on the landed tree, with both plan lines printed (§5).
2. Every touched suite is GREEN under /bin/bash 3.2 with `1..N` asserted, and every ratchet passes (Phase 0 gates).
3. The cross-closer lint is empty.
4. W1, W2 and W3 have landed (verified by content) and converged (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`).
5. **The standing metric** (census §6 item 7): `~/.claude/logs/pane-census.jsonl` shows `unexplained` max 0 and no hold older than 6 h for **7 consecutive days**. A non-zero day pages and re-opens the work.
   - Before W1 every shells-only fleet pane counts, which gives the baseline. The retrospective baseline is in `kitty-pane-actions.jsonl` and `pane-say.jsonl` [C CENSUS §4e].
   - A field proof on one pane does not count.

## 7 Out of scope / operator decisions

| item | position | conviction |
|---|---|---|
| D1: placement of lone fired peers into fullscreen OS windows (`fd34d855d`) against guard ruling e3920969aba9 (`fsfix:false` on 977/977 rows [C]) | The hold makes these panes truthful and self-closing, not instant. The operator rules on placement or the kitty build; W4a shortens holds meanwhile. | 70% that W4a is worth doing even after D1 |
| D2: operator-opened windows close on `/exit` (ruling 337e100f5c71) | Out of scope. Such panes are `operator` in W3, and `pane-successor.sh` defaults stay. | 65% that the operator wants the contract applied |
| `--resume` types RESUME only (D12), changing the sweep's documented doctrine | adopted | 75% |
| close=`no` on a clean end → CANTTELL rather than RESUME (§2 row 5), since recycle, handoff and transplant usually explain a deliberate end | adopted | 65% |
| OWNED is never auto-resumed by the sweep (the watchdog already says "not yours to resume") | adopted | 60% |
| a session-written end-of-life record (census §6 item 1) | out of scope; `pe_verdict` reads the same facts without a new writer | 55% that it is ever needed |
| stale yes (W4b) | follow-on | 55% |
| atomic close-if-not-last in the kitten (W4f) | investigate only; it depends on kitty's main-loop behaviour | 40% feasible |
| per-path mtime proof for crash keeps | rejected (D9) | 80% |
| runner-name stand-downs, `--peek`, `refused-inflight` | dropped (D4, D7) | 75% |

## 8 Addenda after the workflow

- **2026-10-25, pane 304** (reported by track A's lead, pane 307). Session `d0d00017` registered at 20:32, wrote zero transcript records, and exited via `prompt_input_exit` (the watchdog class was RECYCLE/clean-exit, 0 KB). `cc-pane-close` refused it 33 times with "no transcript for session", the painter showed CANTTELL and the sweep said COLLECTED. The lead closed it by hand; it was shell-only, in a 4-pane window. Under W1 the runner already closes a clean rc-0 exit without reading a transcript, so the gap is only on the outside-closer path. Added: `pe_verdict` row 1b, the closer change under W1b, and replay arm B10. A session that never received a turn has nothing to lose.
- **Provenance.** Two independent designs, `design/design-minimal.md` and `design/design-faithful.md`, were merged by a judge (`design/merged.md`). Three skeptics then attacked the merge (safety, decision correctness, scope), and a final editor accepted or rejected each of their 26 breaks (§3). This ran as workflow `wf_d5bf822e-78d` in session 06457213. The decision-correctness skeptic's first run hung on a heredoc permission prompt; it was re-run with the heredoc banned.
