# W0 of LIMIT_RECOVER_FLEET_V2: measurements, fixtures, rig assets (2026-09-29)

Every number below was measured this session; each item names the file holding its command and raw
output. Throwaway sessions ran on CC 2.1.284 (the fleet's binary: 16 of 17 live claude processes)
under `.claude-next`, in kitty windows this session created in an OS window titled `lr-w0`, all
closed afterwards. No live pane was typed into.

| # | measured value | what it sets |
|---|---|---|
| 1 | first Enter accepted in 30/30 drill panes, sent ≤ 0.62 s after paint; bundles: first Enter lost in 4/13, re-sends accepted at 32-43 s | `LR_RECR_SCHEDULE=5,15,30,45` |
| 2 | a no-prompt `--resume` wrote 17 records (+32 KB) within 7 s of launch, then nothing to 660 s | `RECOVERY_IDLE_SEATS=active` |
| 3 | `pane_bgwork_key`: key `2` without the env; rc 1 and no key with `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`. Detector hit 11/20 live panes | watcher never answers with the env set; detector needs an at-rest gate and a watcher exclusion |
| 4 | `cc-kitty-socket` resolves `unix:/tmp/kitty-<pid>` under `env -i PATH=/usr/bin:/bin` (rc 0); `kitten` is not on that PATH | launchd uses the `/tmp` glob path and the absolute `kitten` |
| 5 | goal armed at a usage-limit death: 12 sessions, 0 cleared, 0 re-armed by tooling | no goal re-arm on the same-uuid path |
| 6 | 65 fixture rows (50 real, 15 synthetic) in 14 files: 13 real incidents plus a synthetic set | W3's `lr_recon.phase` fixture suite |
| 7 | 10 screen frames, 9 JSONL record shapes | W5 rig stub |
| 8 | resumed run `wf_efe43f63-ce7`: 646 slots, first dangling slot at index 633, 0 completed slots after it | the prefix rule as briefed is refuted for this run; the measured rule is below |

## 1. Readiness to accept Enter → `LR_RECR_SCHEDULE=5,15,30,45`

Detail and both populations: `m1-readiness.md`. Bundles: `raw/m1-bundle-readiness.{py,txt}`. Drill:
`raw/m1-drill.py`, `raw/m1-drill-runs.txt`.

**Bundles (25 verified).** 13 runs recorded a paint:
- The first Enter was accepted in 9 of the 13 and lost in 4.
- All 4 lost ones were accepted on the single re-send, sent 32, 34, 36 and 43 s after the first Enter.
- paint→user record: p50 1.5 s, p90 36.7 s.

These times are censored: the old code re-sent only once, at about 30 s, so the data can't show whether an earlier re-send would have worked.

**Drill.** 10 concurrent relaunches per run at load1 35-62 on 10 cores. Three valid runs: plain drafts on ~0.4 MB transcripts, plain drafts on ~1.0 MB transcripts, and a 265-char slash command shaped like the real `/limit-recover ingest … run:<token>` prompt.
- **First Enter:** 30 of 30 were accepted. Each was sent 0.02-0.62 s after the draft painted (p50 0.18 s in the slash-command run).
- **Composer vs transcript:** an accepted Enter clears the composer in under 2 s. Its user record reaches the transcript 1.6-11.1 s later, because UserPromptSubmit hooks run first.
- **Consequence:** a transcript-only check misreads a slow write as a lost Enter. The draft still sitting in the composer (DRAFT-MINE) is the real evidence.
- **Relaunch→paint:** 7-10 s on small transcripts, 14-16 s on 1 MB ones, 20-25 s in the slash-command run.

**Why this schedule.** Every re-send is already gated on DRAFT-MINE, so a re-send costs nothing:
- An accepted Enter leaves the composer within 2 s, so DRAFT-MINE at +5 s proves the Enter was lost.
- Pressing Enter on our own draft can only submit it.
- 5 s recovers a lost Enter about 30 s sooner than today's first re-send.
- 45 s still covers the latest acceptance seen in the bundles (43 s).

The drill did not reproduce the bundles' lost Enters. They ran on older binaries, typed through expect, and moved across accounts. The drill rules out readiness, transcript size, concurrency and slash-command input as the cause on 2.1.284.

## 2. No-prompt `claude --resume` → `RECOVERY_IDLE_SEATS=active`

Raw: `raw/m2-no-prompt-resume.txt`. Sampler: `raw/m2-sample.sh`.

Throwaway session 73cc276b, resumed with no prompt:
- **Before:** 109 lines.
- **By +15 s:** 126 lines (+17 records, +32,262 bytes). The mtime moved at +7 s.
- **Afterwards:** unchanged through +660 s.
- **What the 17 records were:** 10 `hook_success` attachments, 2 `hook_system_message`, 1 `hook_additional_context`, 2 `queue-operation`, 1 `bridge-session`, and 1 `user` record. The user record has `promptSource: system`, `origin.kind: task-notification`: it is the stopped background shell from the previous exit, re-delivered.
- **No assistant turn followed.**

So a moved idle session writes its transcript at boot. `claude-accounts` then counts it as WORKING (`k_work`, `KWORK_WINDOW_MIN` = 10) for the next 10 minutes. Placement must therefore count an idle move as an active seat, or the next sweep will disagree with the plan.

Side effect: a relaunch re-delivers pending task-notifications as user records. That is the mechanism behind the four false `SWITCHED` results in item 6, where the notification's turn swallowed our prompt as a `queued_command` attachment.

## 3. The background-work dialog, and the background-shell detector

Frames: `tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284*.txt`. Verdicts: `raw/m3-bgwork-key.{sh,txt}`, which runs `pane_bgwork_dialog` and `pane_bgwork_choice`, the two checks `pane_bgwork_key` (`handoff-fire.sh:3350`) applies to the screen.

**The dialog.** A throwaway session held a `run_in_background` `sleep`, then `/exit` was typed.
- **Without the env:** the menu is `1. Exit and stop tasks · 2. Move to background and exit · 3. Stay`. The dialog is detected and `pane_bgwork_key` returns **`2`**.
- **With `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`:** the menu is `1. Exit and stop tasks · 2. Stay`. The dialog is detected, but the choice returns rc 1, so `pane_bgwork_key` returns **rc 1 with no key**. The watcher cannot answer.
- **Hazard:** index `2` now means **Stay**. Any path that types a fixed `2` instead of reading the label would park the pane. `pane_bgwork_choice` is label-anchored and safe.
- **Cursor default:** the cursor starts on option 1, "Exit and stop tasks". An unguarded Enter kills the job.

**Detector census.** Read-only, `ps` plus `<cfg>/sessions/*.json`. Script and output: `raw/m3-bgshell-census.{py,txt}`.
- **The Bash tool's shell:** it is `/bin/zsh -c source …/shell-snapshots/snapshot-zsh-….sh …`, a direct child of claude, with the job under it.
- **Hits:** 11 of 20 live claude processes.
  - 6 hold only a parked `cc-await-ping` watcher.
  - 4 hold real work: a `ship-land`, a `bats` run, `curl`, and a `sleep` beside a watcher.
  - 1 is an in-flight foreground call (this session's own), so the detector needs an at-rest gate.
- **Misses:** 9 of 20.
- **The naive rule "any shell child"** adds 4 false positives out of 20. Those children are hook scripts (`mailbox-wake-arm.sh`, a long-lived `bash` child). So the detector must key on the `shell-snapshots` `-c` form, not on "a shell".

For the operator decision on background work: a watcher-only shell is not work in flight, but it still raises the dialog. Excluding a shell whose only child is `cc-await-ping` would stop 6 of 20 panes being held as HOLD-BGWORK.

## 4. Launchd socket discovery

Raw: `raw/m4-socket-discovery.txt`.
- **`env -i PATH=/usr/bin:/bin bin/cc-kitty-socket`:** prints `unix:/tmp/kitty-<pid>`, rc 0, with and without HOME. It uses the `/tmp/kitty-*` glob plus the `/bin/ps` check that the process is kitty, which is the only path available with no `KITTY_LISTEN_ON`.
- **`--all` (the W2c flag):** today it is silently ignored. It prints the same single line with rc 0, so W2c must make it a real flag and not trust today's rc.
- **`command -v kitten kitty` under `env -i`:** rc 1. The absolute `/Applications/kitty.app/Contents/MacOS/kitten @ --to unix:/tmp/kitty-<pid> ls` works, enumerating 17 windows in 5 OS windows.
- **Owners of `/tmp/kitty-*`:**
  - one socket, held by kitty (user-owned);
  - two symlinks to kitty source checkouts, `kitty-482` and `kitty-dev`;
  - a compile log.
  The `-S` test skips all three non-sockets.
- **A second kitty pid** is a zombie child of the first (`<defunct>`) and owns no socket.

## 5. `/goal` across a limit

Detail: `m5-goal-across-limit.md`. Scan: `raw/m5-goal-scan.{py,txt}`, over 5,604 transcripts since 2026-09-01.
- 12 sessions had a goal armed at a usage-limit death; 0 were cleared at the death.
- 5 show the same goal (same condition hash) evaluated afterwards, 4 of them after resuming under another account.
- 9 were resumed; for all 9, Claude Code's restore-on-resume rule holds (the last `goal_status` is `met:false`).
- 0 were re-armed by tooling.

The brief's premise was wrong: `blocking_limit` is the context-window wall, not the usage limit.
- **What clears the goal:** `blocking_limit`, `prompt_too_long` and `rapid_refill_breaker`.
- **A usage-limit death** is an `api_error` with `quotaLimits`. On 2.1.280 it *pauses* the goal until a message is sent after the reset.

What this sets for the daemon:
- Resume the full session (never `--summary`).
- Carry the whole `.jsonl`.
- Send the prompt after the reset.
- Snapshot the goal (`goal_snapshot`) only on a path that mints a new uuid.

## 6. `derive_phase` fixtures

The schema is `tests/fixtures/lr-recon/README.md`; the rows are `tests/fixtures/lr-recon/phase-*.json`. Per-file phase lists: `raw/m6-fixture-sources-part{1,2}.txt`.

**Counts.** 65 rows in 14 files: 50 real, 15 synthetic. The 13 real incidents:
- 09-19: the next4 five-attempt cohort.
- 09-24: 3d42fa49.
- 09-27: panes 751 and 815, and the switches of panes 810, 812, 814 and 782.
- 09-28: panes 405 and 906.
- 09-29: panes 946 and 947, and the 04:17 four-pane cohort.

The 14th file is `synthetic/required-rows`. Every W3 required row is present, and the 751/815 rows carry `must_not_be: ["ENGAGED"]`.

**Findings W3 must absorb:**
- **(a) Split submit tokens.** The paste wrapper splits the submit token across `</pasted_content>` in 3d42fa49 and in 3 of the 4 04:17 panes. 3d42fa49's `FAILED:submit` was false: the session worked. Token matching must tolerate the split.
- **(b) A gap in the table.** A moment exists that the §4.2 table does not name: `.handed-off` exists, the source is dead, the watcher is live, and nothing holds the session. It lasts about 5-10 s in every 09-29 move (row 947-c) and derives PRE-MOVE, so only the §4.3 live-process rule stops a re-plan. A dead source with the launcher still booting (09-19) is the same gap.
- **(c) 405/906 derive PRE-MOVE, not EXITED.** Those strands were same-account upgrades, which leave no lock or `.handed-off`.
- **(d) The parked-menu row follows the brief.** It expects HOLD-MENU, but a literal top-to-bottom read of the table reaches RELAUNCHED at row 7 first. W3 must order the parked-menu check ahead of row 7.

## 7. Rig assets

**`tests/fixtures/lr-recon/screens/`** (scrubbed, cut to the TUI region):
- `composer-empty-2.1.284.txt`, `composer-draft-2.1.284.txt`, `composer-resumed-2.1.284.txt`
- `composer-empty-2.1.114.txt`
- `bgwork-dialog-2.1.284.txt` and `bgwork-dialog-2.1.284-agent-view-off.txt`
- `resume-picker-2.1.284.txt`
- `trust-dialog-2.1.284.txt`
- `settings-error-dialog-2.1.114.txt`
- `resume-return-menu-2.1.284.RECONSTRUCTED.txt`

The resume-return menu could not be captured. It is flag-gated: `tengu_gleaming_fair` is false and `tengu_gleaming_fair_reuse` is true on this account. With the reuse flag, the menu shows only when a precomputed summary is ready, and is otherwise skipped silently. The frame is therefore rebuilt from the 2.1.284 binary's own strings:
- the prompt: `This session is X old and Y tokens`;
- option 1: `Resume from summary (recommended)`;
- option 2: `Resume full session as-is`;
- option 3: `Don't ask me again`.

**`tests/fixtures/lr-recon/jsonl/`** (provenance in `raw/m7-jsonl-shapes.txt`):
- `death-quota-limits.jsonl` (five_hour) and `death-quota-limits-seven-day.jsonl`
- `user-prompt.jsonl`
- `assistant-turn.jsonl`
- `api-error-529.jsonl`
- `authentication-failed.jsonl` and `authentication-failed-not-logged-in.jsonl`
- `stub-after-handoff.jsonl`
- `system-informational-retired-source.jsonl`

The limit text is now `You've hit your session limit · resets 1:30am (<tz>)`.

**Facts the rig and W2 need:**
- **The READY phrase.** The 2.1.284 footer reads `manual mode on` or `auto mode on`, never `for shortcuts`, while 2.1.114 shows `? for shortcuts`.
- **Replayed prompts look like the composer.** A resumed transcript replays past prompts with the composer glyph `❯`. A paint check must key on the `❯` row between two rules, not on `^❯`; the unanchored check fired falsely at 1 s.
- **2.1.114 stalls on today's settings.** On today's shared `settings.json`, **2.1.114 parks at an invalid-settings dialog** (unknown hook event `PostToolBatch`; the cursor defaults to "Exit and fix manually"). A relaunch onto 2.1.114 would stall there, and a blind Enter would exit.

## 8. Dynamic Workflow resume: the prefix rule, measured

Fixture: `tests/fixtures/lr-recon/workflow-prefix-7c395da7.json`. Commands and output: `raw/m8-workflow-prefix.txt`.

The brief's rule was: *a plain `resumeFromRunId` re-spends every completed slot that sits after the first dangling one*. For session 7c395da7's resumed run `wf_efe43f63-ce7`, that rule does not hold.
- **Where the dangling slots were:** the 13 dangling slots (judge, write, draft and critic, which died on the usage limit) were the **last** 13 in call order, indices 633-645. 0 completed slots sat after them.
- **What was actually re-spent:** the resume issued the 608 verify slots in a different order. The original order had followed the order in which the find agents finished.
- **Cache hits:** only the 8 slots whose call index did not change hit the cache. Every verify slot the resume reached missed it.
- **Cost:** 13 agents were re-spawned (originally slots 458-470; counted from the journal's `started` records, not the ~24 the session estimated) before a TaskStop. 595 more were queued to miss.

So the rule the ingest check must enforce is this: **a resume re-uses a completed slot only if that slot is called at the same call index; any completed slot whose index shifts is re-spent.** Call order that depends on completion order (fan-out driven by `pipeline` or by completion) makes every downstream index shift. The check therefore compares call order, not dangling position.

`lr-audit` has two gaps here:
- It cannot open the source account's `.jsonl.handed-off`, because full mode ignores `--transcript`.
- It prints no call index. The index came from `workflowProgress[].index` in the pre-move run summary, and that order matches the journal's start order.
