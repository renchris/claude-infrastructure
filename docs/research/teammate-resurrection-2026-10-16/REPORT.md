# Teammate resurrection, 2026-10-16: why web-next16 did not close, and the fix

Subject: teammate `web-next16`, session `5423f92a-9089-4690-8c85-28ffc4018768`, team `session-3cbb68e5`,
account dir `~/.claude-secondary`, cwd `wt-pool-5`, first in kitty pane 217, now an orphan (pid 57630, pane 220).
Repo HEAD `f6b1fbff2`. Times are CDT (UTC-5) unless they end in `Z`. Per-seam evidence is in `slots/A-*.md` to
`slots/E-*.md`. The two candidate designs are in `slots/design-*.md`. Every file:line below was re-read at HEAD for this
report. "Measured" names the command that produced a number. "Inferred" and "UNVERIFIED" mean what they say.

## 1. Answer first

web-next16 had two chances to end cleanly, and the second one worked. At 18:19 its TeammateIdle reaper
(`hooks/teammate-auto-shutdown.sh`) hit its 5 s hook timeout and was cancelled. Each run walks about 18k project
dirs with `find` 3-5 times to find a transcript path that the payload already carries, so the finished member
stayed up. At 18:24 the in-place upgrade drainer (`lr-upgrade.sh`) claimed it even though it was already on the
target binary. The census compares binary paths as strings. The vendor starts teammates through the resolved
`claude.exe`, while the target is the `.bin/claude` symlink to that same file. While the drainer's proof window was
still open, the lead sent `shutdown_request`. The member approved at 18:25:40.8 and the lead closed pane 217: that
was the graceful close. The drainer then read that death as a failed relaunch and passed the session to
`cc-resume-debt settle`. Settle reopened a debt that had already been paid and relaunched the session in a NEW window
through `boot-resume-launch.sh` and `reso-resume-one`, neither of which can carry team flags. The result is an
orphan outside its team that will idle forever. The composer junk is kitty's boot-probe replies echoed onto the
input row, because `reso-resume-one` never got the no-echo guard that `lr-fire-resume.sh` has had since `2b1cdfcc8`.

## 2. Verified timeline (CDT)

The brief said the model never answered the shutdown_request. That is wrong. The approval is in the lead's
transcript (slot C), and the vendor did not persist the member's approving turn in the member's own transcript.

| CDT | Event | Evidence (store: quoted) |
|---|---|---|
| 18:19:34 | Member's last turn ends; the reaper's last log line | `~/.claude/logs/teammate-lifecycle.log:33303` "↳ web-next16: worktree …/wt-pool-5 is SHARED by 7 members — gating on it, removal refused" |
| 18:19:39 | Reaper cancelled at its timeout | member transcript line 177: `"hook_cancelled","hookName":"TeammateIdle",…"durationMs":5030,"timedOut":true,"timeoutMs":5000` |
| 18:24:05 | Drainer claims the idle member (request `5423f92a-1792192942-auto`, `poller-auto`) | `~/.reso/limit-recover/upgrade/5423f92a-20261016T232405Z/events.jsonl`: `"stage":"claim" … outcome=ok … load1=21.15` |
| 18:24:13 | Census disposition `upgrade-teammate` (same binlabel and model on both sides) | events.jsonl `"stage":"census" … dur_s=8`; `upgrade-state/5423f92a-….json`: `"from":{"bin":".claude-293","model":"claude-opus-5-5"}`, `"target":{"binlabel":".claude-293","model":"claude-opus-5-5"}` |
| 18:24:39 | Debt #1 opened by handoff-fire before /exit | `~/.claude/autonomy/resume-debt/577d9d5d….jsonl`: open 23:24:39Z "handoff-fire --recycle: recycle of pane 217 (resume-launcher, same sid…" |
| 18:24:48 | Old pid 15617 torn down; watcher types the launcher (twice: 18:24:48, 18:24:51) | `claude-crashes.jsonl:5826` `"pid":15617,"class":"RECYCLE","cause":"deliberate-teardown"`; `handoffs.jsonl:960-961` `recycle-type-attempt` |
| 18:24:51-52 | lr-fire-resume takes the launch lock and spawns pid 80169 with team flags | `recon/launch.log:384` "1792193091 … lr-fire-resume taken pid=78755"; events.jsonl `relaunch-typed`/`expect` "spawning claude-opus-5-5/high on .claude-secondary" |
| 18:24:54 | Watchdog registers 80169 as a teammate | `lead-crash-watchdog.log:62503` "pid=80169 tty=ttys027 pane=217 teammate=web-next16@session-3cbb68e5" |
| 18:25:15-17 | Recycle engaged; debt #1 discharged | `handoffs.jsonl:962` `"class":"recycle-engaged","engaged":true,"target_pane":"217"`; custody: return 23:25:17Z "recycle engaged in pane 217" |
| 18:25:37-38 | Lead sends shutdown_request; it is recorded in the member transcript | slot C (lead transcript 6261c2ab: SendMessage `shutdown_request` "WEB-14 verified on origin/next16"); member transcript line 192, `"timestamp":"2026-10-16T23:25:38.198Z"` |
| 18:25:40.800 | Member APPROVES | lead transcript record 436 (slot C notes :38): `shutdown_approved` … `"timestamp":"2026-10-16T23:25:40.800Z"` plus `teammate_terminated` "web-next16 has shut down." |
| 18:25:41.667 | Lead's it2-kitty close passes its last guard for window 217 | `kitty-pane-actions.jsonl:157` `"wid":217,"verdict":"safe-not-last","caller":"it2-kitty"` |
| 18:25:43-45 | Session ends; pid 80169 exits 0 on HUP | `sessions.log:129255` "Session ended sid=5423f92a… reason=other"; `close-records/80169-1792193092.json` `"ended_at":"2026-10-16T23:25:45Z","exit_code":0,"sig_reached_wrapper":"HUP"` |
| 18:26:00 | Watchdog classifies the death as a retirement | `claude-crashes.jsonl:5827` `"pid":80169,"class":"RECYCLE","cause":"retired-teammate"`; `lead-crash-watchdog.log:62510` |
| 18:26:10 | Fire stage ends with no proof | events.jsonl `"stage":"fire","detail":"outcome=ok dur_s=114"`. Inferred: `lru_proven` (`lr-upgrade.sh:1975-1984`) runs 3 holds of 15 s with 5 s gaps (55 s). 18:25:15 + 55 s = 18:26:10. Why the first hold failed while 80169 was alive is UNVERIFIED |
| 18:26:10-20 | Step 6: relaunch at the shell refused, pane gone | `relaunch-at-shell.1.log` "verdict: REFUSED:pane:absent" |
| 18:26:20 | `settle` reopens a debt "(no prior debt)" | custody: open 23:26:20Z "settle (no prior debt)"; `resume-debt/meta/5423f92a-….json` "opened by settle (no prior debt)"@1792193180; `launch.log:385-386` cc-resume-debt taken / boot-resume-launch inherited |
| 18:26:23-24 | NEW os-window; reso-resume-one takes the lock | `pane-spawns.jsonl:4964` `"surface":"os-window","caller":"boot-resume-launch.sh","chain":"lr-reset-poller.sh>boot-resume-launch.sh"`; `launch.log:387` reso-resume-one taken pid=56454 |
| 18:26:27 | Orphan pid 57630 registered with no team identity | `lead-crash-watchdog.log:62517` "pid=57630 tty=ttys027 pane=220" (no `teammate=`) |
| 18:26:52 | Debt #2 proven; drive verdict `upgraded` | meta "proven LIVE by cc-find"@1792193212; `upgrade-drain.log:3522` "217 5423f92a upgraded relaunched in a NEW window by cc-resume-debt (pane 217 left at a shell; --relaunch-at-shell REFUSED:pane:absent …" |
| 18:27:06 | The lead's own liveness check cannot see the orphan | slot C (lead transcript): `pgrep -f "agent-id web-next16@"` gives "web-next16 removed" |

Epochs were converted with `TZ=America/Chicago date -r` (measured).

## 3. Root causes per seam

The causal chain is E, then A, then C, then B. D is a separate defect that shows up only on the resurrected pane.

### A. Upgrade eligibility: the census claimed a member that was already current
- `scripts/limit-recover/lr-upgrade.sh:686` decides `current` with `[ "$bin" = "$target_bin" ]`. That is a string
  compare. The target is `~/.claude-293/node_modules/.bin/claude`, which resolves to `…/bin/claude.exe` (measured:
  `readlink -f`). The vendor starts pane teammates with argv[0] set to that resolved `claude.exe`
  (`docs/research/team-inplace-upgrade-2026-09-23/q2-teammate-relaunch.md:73`). So every vendor-spawned member
  reads `upgrade-teammate`. The same compare appears at `:448` (`lru_lead_block`, which can hold a lead in
  `lead-awaits-teammates` forever) and at `:1965` (`lru_resumed_on`).
- The refill (`:3109-3131`, filter `:3123`) and `lru_auto_enqueue` (`:3151-3176`, filter `:3164`) queue every
  `upgrade-teammate` row on their own, with no regard for the lead.
- Scale (measured by slot A, jq over 18 `upgrade-state/*.json`): 12 records were driven. All were teammates with the
  same binlabel and model on both sides. 9 ended `upgraded` and 3 `stranded`.
- Guards that missed:
  - `lru_teammate_block` (`:420-438`) holds a member only when its identity is incomplete, it has no member row, or
    an UNREAD `shutdown_request` is in its inbox. It ran once at census (18:24:13), 84 s before the request existed.
  - `lru_st_eligible` (`:2134-2143`) looks only at record age and backoff.
  - The recon fence answers whether the reconciler owns a session, not whether a lead owns it
    (`verdict=act reason=not-owned`).
  - `team_held` is a lead-only flag (`:2643-2649`) and is 0 for every teammate by construction.

### B. Resume-debt resurrection: a team-blind relaunch of a session that had already been paid for
- Trigger, `lr-upgrade.sh:2710-2719`. After the fire stage ends unproven, step 6 reads "no `--resume` process now"
  as "the relaunch failed". It then calls `lru_relaunch_gated` (refused: pane absent), then `lru_settle_verdict`
  (`:2012-2020`), then `lru_settle` (`:1993-2004`), then `cc-resume-debt settle`. It never asks why a member's
  relaunched process ended.
- Amplifier, `bin/cc-resume-debt:681-683` (`_settle`). Because `_active` at `:126` admits only
  `open|retrying|escalated`, a `proven` debt counts as "no prior debt". `_open` (`:277-323`) overwrites debt #1's
  history. `_step "$1" 1` (`:664`) skips the grace period. `_relaunch` (`:464-517`) then runs the launcher with only
  account, cwd and sid (`:507`), so team flags cannot travel.
- No relaunch actor (`bin/cc-resume-debt`, `scripts/boot-resume-launch.sh:289-339`, `bin/reso-resume-one`) asks
  whether the session is an Agent Teams member. The repo's own comment (`lr-upgrade.sh:383-385`) says a member
  resumed without its flags "comes back as a plain session, outside the team".
- Guards that missed:
  - `scripts/boot-resume.sh:710-830` skip-retired lives only in the orchestrator, and the vendor shutdown path
    writes no teardown marker.
  - `hooks/lead-crash-watchdog.sh:534-539` `retired_teammate` fired correctly at 18:26:00, but nothing reads its
    row.
  - `bin/cc-husk-sweep:338-342` `is_teammate` has the right policy but lives only in that tool.
  - The fence and H(sid) checks (`cc-resume-debt:469`, `:473`) answer whether someone else is holding the session,
    and "no" is correct for a dead session.

### C. Pane close and shutdown handling: the close was legitimate, and the defect is the race behind it
- The member approved and the lead's normal teardown closed the pane: the `it2 session close` arm of
  `bin/it2-kitty` (fullscreen guard `:1489-1494`, `kt close-window` `:1503`), then HUP. Control pairs on the same
  team show the same 0.7-0.9 s approval-to-close gap (`kitty-pane-actions.jsonl:158`, `:160`).
- The race: the fire stage stayed open about 55 s after the watcher verified engagement. The lead's shutdown landed
  inside that window. Sibling `web-small` (538db399) was recycled by the same drainer, but its fire closed before its
  shutdown, and it was not resurrected (slot C).
- Guards that missed:
  - The member-row and shutdown checks (`lr-upgrade.sh:427`, `:432-437`) are evaluated only at census (`:699`).
  - The vendor drains the inbox on delivery. Measured with `ls -la` and `jq` on
    `~/.claude-secondary/teams/session-3cbb68e5/inboxes/*.json`: every file is 2 bytes, `[]`. So
    `teammate-shutdown-pending` can only fire before delivery.

### D. Composer junk: echo left on in reso-resume-one
- `bin/reso-resume-one` starts `expect` at `:798`, spawns claude at `:830`, and runs the first `expect{}` with
  `set timeout 240` (`:799`). The pane tty stays cooked with `echo` and `echoctl` on.
- Claude Code 2.1.293's boot probe (XTVERSION, `CSI ? u`, DA1) is answered by kitty onto the outer tty, and the line
  discipline echoes the replies as caret text `^[P>|kitty(0.48.2)^[\^[[?5u^[[?62;52;c`.
- The drain at `:915-963` removes the bytes from the input queue but cannot erase the paint.
- The cure exists only in `scripts/limit-recover/lr-fire-resume.sh:1045-1046, :1066-1076, :1649, :1654` (commit
  `2b1cdfcc8`).
- Guards that missed: the parity test `tests/lr-fire-resume-reply-drain.bats:33, :87-103` diffs only the
  `lr-reply-drain` span, and the echo guard sits outside it. The control: the same session's earlier in-place
  relaunch went through `lr-fire-resume` and read "READY-QUIET … the composer reads EMPTY" at 23:25:00Z.

### E. Idle-hook timeout: why it did not close itself
- `hooks/teammate-auto-shutdown.sh:584-593` `_find_transcript` runs `find <root> -maxdepth 2 -name <sid>.jsonl | head
  -1`. Callers are `:677`, `:1077` and `:1431` (and `:1435` with another sid).
- `scripts/reap-guard.sh:115-124` `rg_find_transcript` does the same, at `:182` and `:250`.
- `head -1` does not stop `find`, and `~/.claude/projects` is searched first, so it always misses in full for a
  secondary-account member. Measured by slot E with `ls | wc -l`: 18,070 and 18,085 subdirs per store. Measured by
  slot E: 22.6-27.2 s per lookup at load 373-410. Incident load1 was about 21 (events.jsonl).
- The payload's `transcript_path` is never read (`:788-791`). Nothing checks elapsed time. The run died after its
  `:1007` log line and before reap-guard wrote a record.
- The budget is `"timeout": 5` (`settings-templates/settings.example.json:640-645`; the live `~/.claude/settings.json`
  is the operator's).
- Estimated by slot E (python over teammate-lifecycle.log): 314 of 407 shared-cwd runs since 2026-10-01 end at the
  `:1007` line.
- Guards that missed:
  - The detached close (`:1533-1568`) is never reached.
  - `tas_bounded` (`:140-161`) covers only it2 forks.
  - A timeout kill writes no `pcq_add` retry row (`:1130-1151`).
  - 71 bats tests in `tests/teammate-auto-shutdown.bats` assert no cost bound.

## 4. The fix

**Principle.** An Agent Teams member belongs to its lead.
- No actuator brings a member back through a path that cannot carry its team identity.
- No actuator re-types a member whose lead has dropped it, ordered it retired, or replaced it.
- A mover's debt is paid by proof, and a death after that proof is not the mover's close.
- Every relaunch decision about membership rests on what the closer saw: the closed process's argv. When no closer
  recorded that, it falls back to the repo's one teammate test (`lr-predicate.sh is-teammate-head`,
  `lr_predicate.py:411`).

### 4.1 Refuter holes rated medium or higher, and how each is closed

| Hole | Sev | Closed by |
|---|---|---|
| R2-H1: a plain-argv session whose head reads "member" (the live orphan, an adopted ex-member) is closed by a mover and then silently abandoned by the launcher gate | high | Closers record membership from argv (`--member yes/no`; steps 3f, 4, 8c, 9). The launcher honours `no` and skips the head test (step 5). Abandon happens only when `member=yes`. A member head with no hint ESCALATES once with a runnable `CC_RESUME_TEAMMATE_GUARD=off` line (step 4e), so it is never silent. |
| R1-H1, R2-H3, R3-H1: once the inbox is drained, retirement is invisible; the belt could re-type the member; the notice told the lead to re-spawn it | medium | (a) `teammate-retired` from the watchdog's existing `cause=retired-teammate` row, read from the store with a bounded wait (steps 1b, 1c, 3b). (b) An exec-time member-row and successor check inside `lr-fire-resume.sh` covers the watcher's re-type, `--relaunch-at-shell` and hand runs of `launch.sh` (step 8). (c) The lead notice is sent only when no retirement evidence exists, as plain information with no command (step 3h). |
| R1-H2: a session that ended on purpose after a proven relaunch is resurrected by `settle` | medium | `settle --since <fire epoch>` returns 5 instead of reopening a debt proven after that epoch (step 4c). lr-upgrade then reads the watchdog verdict: CRASH reopens (today's recovery), RECYCLE does not, and no verdict within 45 s reopens (today's behaviour) (step 3g). The handoff-fire SURFACE GONE half is REJECTED: there the debt is unpaid because no relaunch ever ran, the mover's own /exit is the close the custody contract (`cc-resume-debt:5-10`) says to undo, and there is no incident evidence of operator-intent closes on that path. |
| R2-H2: the member row is matched by name only, so a same-name successor reads as "still owned" | medium | `lr_agent_id_holders` (step 2): a live `claude`/`claude.exe` other than ours that carries the same `--agent-id` makes `teammate-superseded`. It is checked at census, before fire, in the belt, in the teammate arm and at exec (steps 3b, 8). A `joinedAt` compare was rejected because whether a resumed member rewrites its row's `joinedAt` is UNVERIFIED, so it could misread our own rejoin as a successor. |

Low holes adopted, because they are bugs in the design's own new code or cost one line:
- R1-H3: lr-fire-resume refuses a team-blind resume of a member (step 8). The design's "one door" claim was false.
- R1-H5 and R3-H3: the reso-resume-one belt sits outside the fence block, releases the fence before the refusal,
  and treats rc 2 as held (step 6).
- R1-H7: a 32 KB head and a 2.1.293-shaped fixture.
- R2-H4: the process read happens after the verdict wait.
- R3-H4: `lru_settle` really returns 4.
- R3-H5: quoted `head -c`.
- R3-H6: a single-store glob.
- R3-H7: a 4 s budget plus calibration (step 13).
- R3-H8: hermetic replay setup.
- R3-H9: covered by R2-H1.
- R3-H10: T12 fixture.

R1-H6 and R3-H2 are covered by step 8. Left open: R1-H4 and R2-H5 (section 6).

### 4.2 Implementation steps (in order)

**PHASE 1: no resurrection, no false verdict**

**Step 1. `scripts/limit-recover/lr-lib.sh`, new functions after `lr_holder_count` (`:625`).**
- 1a. `lr_team_member <sid> [cfg] [cwd]`. rc 0 = member (prints the transcript), 1 = not a member or no
  transcript, 2 = undecided. Behaviour:
  - Lookup: first the exact `$cfg/projects/<slug>/<sid>.jsonl` (`slug=$(printf %s "$cwd" | LC_ALL=C sed
    's/[^a-zA-Z0-9]/-/g')`, the spelling at `hooks/lib/peer-owned.sh:957`). On a miss, glob only
    `$cfg/projects/*/<sid>.jsonl`. When cfg is empty, glob over `lr_config_dirs` (`:26`).
  - `hd="$(head -c "${LR_TEAM_HEAD_BYTES:-32768}" "$t")"`. If `"agentName"` is absent, return 1 with no python.
  - Otherwise run `LR_HEAD_BYTES="${LR_TEAM_HEAD_BYTES:-32768}" /bin/bash "$LR_LIB_DIR/lr-predicate.sh"
    is-teammate-head "$t"`. A non-zero rc gives 2, `"teammate":true` gives 0, and anything else gives 1.
  - bash 3.2-safe: no `case`+`continue` inside `$( )`.
- 1b. `lr_member_row <cfg> <team> <name>`. rc 0 when `teams/<team>/config.json` lists `.name == name`, 1 when the
  file or the row is absent, 2 when jq is missing. The name goes in through `env`, as at `lr-upgrade.sh:427`. This
  becomes the ONE copy of that jq.
- 1c. `lr_death_after <sid> <since-iso-Z>`. Reads
  `tail -n "${LR_CRASH_TAIL:-4000}" "${CC_CRASH_LOG:-$HOME/.claude/logs/claude-crashes.jsonl}"` with
  `jq -r --arg s --arg t 'select(.sid==$s and .ts>=$t)|"\(.ts) \(.pid) \(.class) \(.cause)"'`. rc 0 = rows printed
  (oldest first), 1 = none, 2 = unreadable.
- 1d. `lr_death_wait <sid> <since> <old-pid> <run-dir>`. It waits only when `<run>/events.jsonl` has a
  `state=="relaunch-typed" and stage=="expect"` row with `ts >= since` (our launcher spawned a claude) AND
  `lr_death_after` has no row whose pid is not `<old-pid>`. It polls every 5 s for up to
  `LR_DEATH_VERDICT_WAIT_S` (45). The watchdog polls every 30 s (`lead-crash-watchdog.sh:2121`), and its row for
  80169 landed 15 s after the death.

**Step 2. `scripts/limit-recover/lr-team.sh`.** Add `lr_agent_id_holders <agent-id> [snapshot] [exclude-pids]`. It
prints the count of live, non-zombie processes whose argv[0] basename is `claude` or `claude.exe` and whose argv
carries the adjacent tokens `--agent-id <id>`. Use the `_LR_TEAM_AWK` discipline (`:34-39`): the id goes in through
ENVIRON, never argv. Process-only, so it stays inside the file's charter (`:7-11`). The argv[0] rule excludes
`cc-close-attrib`, `expect`, and the `bash lr-fire-resume.sh … --extra-args --agent-id …` lines that also carry the
id.

**Step 3. `scripts/limit-recover/lr-upgrade.sh`.**
- 3a. Add `lru_same_bin() { [ "$1" = "$2" ] || [ "$1" -ef "$2" ]; }` beside `lru_flag` (`:229`). Use it at `:686`
  (`elif lru_same_bin "$bin" "$target_bin" && [ "$model" = "$tgt" ]`), at `:448` (`if ! lru_same_bin "$b" "$4" ||
  …`) and at `:1965` (`lru_same_bin "${a%% *}" "$2" || continue`). Missing paths make `-ef` false, so the
  string compare still decides the `/opt/cc` fixtures.
- 3b. `lru_teammate_block` (`:420-438`) takes `<argv> <cfg> [sid] [since] [exclude-pids]`:
  - The `:427` jq is replaced by `lr_member_row` and still gives `teammate-no-team`. The inbox check stays.
  - New: `lr_agent_id_holders "$id" "" "$exclude"` > 0 gives `teammate-superseded`.
  - New, when `since` is set: any `lr_death_after` row with cause `retired-teammate` (any pid, because the OLD pid
    approving a shutdown counts) gives `teammate-retired`.
  - The census call (`:699`) passes `"$sid" "" "$pid"`.
  - Every value starts with `teammate-`, so `lru_class_of` (`:2093`) puts it in the uncharged wait class.
- 3c. `lru_auto_admits <disp> <pid> <rows> <snap>`, above `lru_refill` (`:3109`). It returns 0 for `upgrade` and
  `upgrade-lead`. For `upgrade-teammate` it returns 0 only when the census row whose sid equals the member's
  `--parent-session-id` reads `lead-awaits-teammates`; the awk pattern goes in through ENVIRON.
  - Both loops (`:3122-3123`, `:3163-3164`) read `read -r p s _ _ tgt _ _ _ _ pid d` and call
    `lru_auto_admits "$d" "$pid" "$rows" "$snap" || continue`.
  - Take one `lru_snapshot` per pass, and only when an `upgrade-teammate` row exists.
  - Update the comments at `:395-397` and `:3142-3149`.
- 3d. In `_lru_drive_run`, just before `lru_step "$sid" fire` (`:2654`):
  - `lru_st_put` `.fire_ts` (`date -u +%FT%TZ`) and `.fire_epoch`.
  - For role=teammate: `d="$(lru_teammate_block "$targs" "$cfg" "$sid" "" "$pid")"`. If it is non-empty, restore the
    hold, then `lru_result … skipped "$d (re-checked before fire) - nothing typed"` and return 3.
- 3e. Belt in `lru_relaunch_gated`, after the WHY chain (`:2239-2242`) and before `:2243`. When WHY is empty and
  role=teammate:
  - Run `lr_death_wait "$sid" "$(lru_st_get "$sid" .fire_ts)" "$(lru_st_get "$sid" .old.pid)" "$run"`.
  - Then `d="$(lru_teammate_block "$targs" "$cfg" "$sid" "<fire_ts>" "$(lr_resume_procs "$sid" | tr '\n' ' ')")"`.
  - If `d` is non-empty, set `LRU_RELAUNCH_WHY="teammate not fit to relaunch ($d) - nothing typed"`.
  - The existing tail (`:2275-2276`, team restore, return 1) is unchanged.
- 3f. `lru_settle` (`:1993-2004`) takes `$4=since epoch` and runs
  `lru_rd settle --sid "$1" --member no ${4:+--since "$4"}`. Only plain sessions and leads reach it. New arms:
  - `4)`: `LRU_SETTLE_WHY="not live: not relaunched ($3); cc-resume-debt abandoned the debt (see $LRU_RD_LOG)"`,
    return 4.
  - `5)`: `LRU_SETTLE_WHY="proven after this move"`, return 5.
  - The switch drive's call (`:1779`) maps both through its `*)` arm unchanged. It passes no since, so 5 cannot
    occur there.
- 3g. `lru_settle_verdict` (`:2012-2020`):
  - First line: `[ "$(lru_st_get "$1" .role)" = teammate ] && { lru_teammate_settle "$@"; return; }`.
  - It passes `.fire_epoch` as since. Arm `4)` gives `skipped`, which maps to `notlive` (`:2090`, `:2110`), never
    `stranded` (`:2140`).
  - Arm `5)`: run `lr_death_wait`, then take the newest `lr_death_after` row whose pid is not `.old.pid`.
    - `CRASH` re-calls `lru_settle` WITHOUT since, which is today's recovery, and maps its rc.
    - `RECYCLE` gives `skipped "not live: relaunched on the target and proven by cc-resume-debt, then ended
      <class>/<cause> at <ts>; a death after its proof is not this move's close - not reopened"`.
    - No row re-calls `lru_settle` without since, with the note "death unclassified after 45 s".
- 3h. `lru_teammate_settle` and `lru_notify_lead`, placed above `lru_settle_verdict`. Never calls `lru_settle`. It
  reads `.team_args`, `.cfg`, `.run`, `.fire_ts` and `.old.pid`, runs `lr_death_wait`, then:
  1. `d=lru_teammate_block(… since=fire_ts, exclude=lr_resume_procs)`. If `d` is non-empty:
     `lru_rd abandon --sid --why "teammate retired during the upgrade ($d)"` (a no-op on a proven debt), then
     `skipped "not live: teammate <name>@<team> retired by its lead during the upgrade ($d); nothing relaunched"`.
     No notice.
  2. `lr_resume_procs "$sid"` is non-empty: `skipped "teammate <name>@<team>: --resume process runs but was never
     proven LIVE ($3); not settled"`. The debt is kept, and this is the fault class, charged and bounded.
  3. Otherwise: abandon, then `skipped "not live: teammate <name>@<team> ended during the upgrade and was not
     relaunched ($3); a new-window resume cannot carry its team identity - its lead owns its recovery"`, plus
     `lru_notify_lead`. That function resolves the `--parent-session-id` pane through `$LRU_CCFIND_BIN` (`$1==sid
     && $6=="LIVE"`, as `:2172-2173` does) and sends ONE informational line with no command and no "re-spawn"
     wording. If the lead is not LIVE, or cc-notify exits 3, it sends nothing. Whether cc-notify accepts a kitty
     window id is UNVERIFIED.
- 3i. `lru_mint_launcher` (`:1828-1906`): for every role except `teammate`, write
  `export CC_RESUME_TEAMMATE_GUARD=checked`, because the census read that argv and found no `--agent-id`.

**Step 4. `bin/cc-resume-debt`.**
- 4a. Args (`:769-788`): `--member yes|no` (open, settle; any other value is `_die` 2) and `--since EPOCH` (settle,
  digits only). Update the usage text (`:754-760`) and the EXIT CODES block (`:40-42`: add `5 settle: already
  proven after --since`).
- 4b. `_open` (`:277-323`): write `member` (from `--member`, otherwise carried from a non-active prior meta). When
  a non-active prior meta exists, copy its last 20 events into `.prior_events`.
- 4c. `_settle` (`:676-683`): before reopening, if `SINCE` is set, the meta is `proven`, and its last proven event's
  epoch is `>= SINCE`, `_note` and return 5. If it is `abandoned` at or after SINCE, return 4. Without `--since`,
  behaviour is unchanged.
- 4d. `_relaunch` (`:507`): add `CC_RESUME_MEMBER_HINT="$(_get "$1" member)"` to the launcher env prefix. After
  `lr_recon_act_done` (`:512`), when `rc=7` and `member=yes`, call `_abandon "$1" "not relaunched: an Agent Teams
  member - its lead owns it; a new-window resume cannot carry its team identity (launcher exit 7)"` and return 1.
  Any other rc-7 falls through to the existing `relaunch_rc` record, and the next `_step` escalates.
- 4e. `_escalate` (`:610-616`): when `relaunch_rc=7`, prefix `run` with `CC_RESUME_TEAMMATE_GUARD=off ` and add to
  the title: "its transcript reads as an Agent Teams member and no closer recorded how it last ran; resume by hand
  only if it was adopted outside its team".
- 4f. Add to the STATE MACHINE header (`:27-35`): "open, launcher exit 7 + member=yes → abandoned; exit 7 otherwise
  → escalated".

**Step 5. `scripts/boot-resume-launch.sh`.**
- Move `brl_cfg_for` (`:412-419`) above `:289`.
- Add question 4 after the H(sid) `case` (`:328-335`) and before `:339`, unless `CC_RESUME_TEAMMATE_GUARD` is
  `off` or `checked`:
  - Hint `no`: skip.
  - Hint `yes`: print "…closed as an Agent Teams member…" and exit 7.
  - Hint empty: call `lr_team_member "$sid" "$(brl_cfg_for "$acct")" "$cwd"`. rc 0: print the refusal naming the
    transcript, exit 7. rc 2: exit 5. Function undefined: print a loud line and continue.
- `--check-only` inherits question 4, and the fence trap (`:320`) releases the lock on exit 7.
- Add `'CC_RESUME_TEAMMATE_GUARD=checked'` to `CMD` (`:203`, next to `CC_ADMIT_DONE=1`).
- Header: `--check-only` text (`:16-17`), Exit list (`:24-30`: "7 never ours: an Agent Teams member"), and the block
  comment (`:290-297`).

**Step 6. `bin/reso-resume-one`.**
- Factor the `_RRO_LR` resolution (`:637-647`) so that it runs whether or not `CC_RESUME_FENCE` is on.
- After the fence block's `fi` (`:679`), unless `CC_RESUME_TEAMMATE_GUARD` is `off` or `checked`, call
  `lr_team_member "$sid" "$cfg" "$wt"`:
  - rc 0: `rr_fence_release`, print "NOT LAUNCHING <sid> - an Agent Teams member (<transcript>) …", then
    `rr_refused_exit 7`. `exec` skips the EXIT trap (`:624-627`), so the fence must be released first.
  - rc 2: `rr_fence_release`, then `exit 5`.

**Step 7. `scripts/boot-resume.sh`.** Change `5)` to `5|7)` at `:1140` and `:1301`. Extend the `resume_held`
comment (`:1041-1042`) and the page text (`:1456`) with "or an Agent Teams member its lead owns".

**Step 8. `scripts/limit-recover/lr-fire-resume.sh`.** Add `lr_member_guard` and call it on the line after
`lr_launch_guard` (`:1036`). Source `lr-team.sh` from `$_LRF_DIR`.
- 8a. `EXTRA_ARGS` carries `--agent-id` (a team relaunch). Parse id, name and team.
  - `lr_member_row "$cfg" "$team" "$name"` rc 1 gives `lr_relaunch_rc 12 "teammate <id>: no member row - its lead
    dropped it"`, then `exit 12`.
  - `lr_agent_id_holders "$id"` > 0 gives rc 12 with "superseded".
  - rc 2 (no jq) proceeds with a loud line.
- 8b. No `--agent-id`, and `CC_RESUME_TEAMMATE_GUARD` is neither `off` nor `checked`: `lr_team_member "$SID" "$cfg"
  "$WT"` rc 0 gives `lr_relaunch_rc 12 "team-blind resume of an Agent Teams member"`, then `exit 12`. rc 2
  proceeds loudly; the poller already skips rc 2 at `lr-reset-poller.sh:872-877`.
- 8c. Update the header usage and exit codes (10 lock, 11 holder, 12 member).

**Step 9. `scripts/handoff-fire.sh`.**
- Add `HF_SA_MEMBER=""` at `:566`.
- In `hf_same_account_evidence`, after `args` is read (`:3772`), set `HF_SA_MEMBER=yes` if the argv has
  `--agent-id`, else `no`.
- At the debt open (`:18231`), pass `${HF_SA_MEMBER:+--member "$HF_SA_MEMBER"}`.
- Self-recycles pass nothing. They fall back to the head test, and an rc 7 there escalates rather than abandoning.

**PHASE 2: composer junk**

**Step 10. `scripts/limit-recover/lr-fire-resume.sh:1066-1076`.** Wrap the existing block in
`  # >>> lr-tty-quiet  (byte-identical in lr-fire-resume.sh AND bin/reso-resume-one; tests/lr-fire-resume-reply-drain.bats diffs it)`
and `  # <<< lr-tty-quiet`. Make the comment generic, with no `lr_screen` mention and NO apostrophes. The code
does not change.

**Step 11. `bin/reso-resume-one`.**
- Insert the identical span after the `set prompt` lines (`:828-829`), before `spawn` (`:830`).
- Insert `if {$lr_tty_orig ne ""} { catch {exec /bin/stty $lr_tty_orig <@ stdin 2>/dev/null} }` immediately
  before `set lr_keep [lr_drain_user]` (`:963`).
- In bash, add `rr_tty_saved=""; [ -t 0 ] && rr_tty_saved="$(stty -g 2>/dev/null)"` before `expect -c` (`:798`), and
  `[ -z "$rr_tty_saved" ] || stty "$rr_tty_saved" 2>/dev/null || true` right after `rr_rc=$?` (`:975`).
- Any apostrophe in Tcl text breaks every resume (`:815`).

**PHASE 3: the self-close the user asked about**

**Step 12. `hooks/teammate-auto-shutdown.sh`.**
- Add `TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')` at `:788-791`.
- `_find_transcript` (`:584-593`) returns it when `sid == SESSION_ID`, the file exists, and its basename is
  `$sid.jsonl`. Otherwise it searches `$CLAUDE_CONFIG_DIR/projects` first, then the other roots, with
  `find "$r" -maxdepth 2 -name "$sid.jsonl" -print -quit`.
- Pass `${TRANSCRIPT_PATH:+--transcript "$TRANSCRIPT_PATH"}` to reap-guard at `:1205`.
- Add `_budget_or_defer <gate>` before `:1128`, `:1205`, `:1287` and `:1399`. When
  `SECONDS >= ${TAS_BUDGET_S:-4}`, it logs "defer <name>: BUDGET exhausted at <gate> after Ns - nothing closed",
  calls `_queue_member_retry budget-exhausted:<gate>` (factored out of `:1138-1150`), and exits 0 without
  `{"continue":false}`.
- Log each gate's elapsed seconds on the existing lines, so the budget can be calibrated from a day of real runs.

**Step 13. `scripts/reap-guard.sh`.**
- Add `--transcript) tp="${2:?}"; shift 2 ;;` in `cmd_decide` (`:150-160`).
- After `:173`, seed `tj` from it when its basename is `$sid.jsonl` and the file exists.
- `:182` becomes `[ -n "$tj" ] || tj="$(rg_find_transcript …)"`.
- `rg_find_transcript` (`:119`) uses `-print -quit`.

## 5. Tests to add (bats, hermetic, run serially)

Every new suite or case pins `HOME` to `$BATS_TEST_TMPDIR`, `CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off` and
`CC_CRASH_LOG`, as `tests/lr-recon-fence-callsites.bats:26-31` does. It pins each spawned tool's own seams
(`CC_RESUME_ONE_BIN`, `CC_RESUME_DEBT_RELAUNCH="/bin/bash $REPO/scripts/boot-resume-launch.sh"`, `LR_RECON_ROOT`,
`CC_REGISTRY_DIR`). Tests run launchd-path code under `/bin/bash` 3.2.

- `tests/teammate-resurrection-replay.bats` (NEW). It runs the real `cc-resume-debt`, `boot-resume-launch.sh`,
  `lr-lib.sh` and `lr-predicate.sh`; `kitty` and `reso-resume-one` are recorder stubs.
  - "REPLAY 2026-10-16 5423f92a: a member debt proven at T and re-settled opens no window." The fixture transcript
    is in the measured 2.1.293 shape: header records, attachment records with `agentName`/`teamName`, the first
    user record past 8 KB, then the `<\teammate-message>` shutdown_request with no assistant record after it. Debt
    #1 is opened `--member yes` and discharged. Assert: settle rc 4, no kitty argv, state `abandoned` with "Agent
    Teams member", no backlog or notify call, no pending-launch marker.
  - Control: "the same chain with the member records stripped relaunches in a NEW window".
  - "plain-argv member head (`--member no`) is relaunched" (R2-H1).
  - "no hint + member head escalates once with a `CC_RESUME_TEAMMATE_GUARD=off` run line" (R2-H1).
- `tests/lr-upgrade.bats`:
  - T12 [RED] binary identity: a teammate whose argv[0] is `<tmp>/.claude-293/…/bin/claude.exe` while the target
    `.bin/claude` symlinks to it reads `current`. Its lead, given an OFF-target `--model`, reads `upgrade-lead`, not
    `lead-awaits-teammates`. A member on another version dir's `claude.exe` still reads `upgrade-teammate`. Mutant:
    revert `:686`.
  - T13 [RED] ownership: `--auto-enqueue` and the refill queue an `upgrade-teammate` row only under a
    `lead-awaits-teammates` parent; a plain `upgrade` row is the control.
  - T14: a member row removed between census and fire is skipped "teammate-no-team (re-checked before fire)", the
    hf stub never runs, and the class is wait.
  - T15: a second live `claude` carrying the same `--agent-id` makes the census `teammate-superseded`.
- `tests/lr-upgrade-settle.bats`:
  - S3d: plain session, settle rc 4 gives `not live:`, terminal `not-live`, never `stranded`.
  - S3e [RED]: member row gone means no `--relaunch-at-shell`, no `settle`, `abandon` logged, "retired by its lead".
  - S3f: owned, no process: exactly one cc-notify line to the lead's LIVE pane, and the message contains neither
    `launch.sh` nor `re-spawn`. No line when the lead is not LIVE.
  - S3g [RED] (R1-H1/R2-H3/R3-H1): row still present, inbox `[]`, and a `CC_CRASH_LOG` row `retired-teammate` after
    `fire_ts` gives "retired", no notify and no shell re-type. A variant writes the row 10 s late and asserts the
    bounded wait catches it.
  - S3h (R2-H2): a same-id successor process in the ps fixture means retired, no re-type.
  - S3i/S3j/S3k (R1-H2): plain session, cc-resume-debt stub returns 5. RECYCLE clean-exit gives not-live and no
    second settle. CRASH gives a second settle without `--since`. No row within `LR_DEATH_VERDICT_WAIT_S=1` gives a
    second settle.
- `tests/lr-upgrade-custody.bats`: "REPLAY web-next16 [RED]: hf stub returns 0 after deleting the member row and
  dropping the pid; the drive ends not-live; hf never sees `--relaunch-at-shell`; the rd stub sees `abandon`, never
  `settle`".
- `tests/cc-resume-debt.bats`:
  - Relaunch rc 7 with `member=yes` abandons: settle rc 4, no backlog, no mail. Control: the existing "relaunch rc≠0
    escalates" at `:134`.
  - rc 7 with no member escalates with a `CC_RESUME_TEAMMATE_GUARD=off` run line.
  - `settle --since` on a debt proven after since returns 5 and runs no launcher. `:281` stays green.
  - `member` is carried across a reopen, and `prior_events` is kept.
  - The launcher stub records `CC_RESUME_MEMBER_HINT`.
  - Bad `--member` value gives rc 2.
- `tests/lr-lib.bats`:
  - `lr_team_member`: the 2.1.293 head shape is a member through the exact slug with no glob (a PATH-stub `find`
    and a glob counter); a lead head and a plain head are not; no transcript gives 1; key present with the
    predicate unrunnable gives 2; runs under `/bin/bash`.
  - `lr_death_after`: since filter and pid column.
  - `lr_death_wait`: returns at once when no `relaunch-typed` row exists.
  - `lr_member_row`: present, absent, no file.
- `tests/lr-team.bats`: `lr_agent_id_holders` counts only `claude`/`claude.exe` argv[0]; excludes listed pids; is
  not matched by a `bash lr-fire-resume.sh … --agent-id X` or `expect` line; is not matched by itself.
- `tests/lr-recon-fence-callsites.bats` and `tests/boot-resume-launch.bats`:
  - Q4 hint=yes exits 7 without reading the transcript, and the lock is released.
  - Hint=no launches a member head.
  - Empty hint with a member head exits 7, and `--check-only` exits 7.
  - Undecided exits 5. Guard off and guard checked launch.
  - Plain head control.
  - `--dry-run` CMD carries `CC_RESUME_TEAMMATE_GUARD=checked`. Update any CMD-pinning case.
- `tests/reso-resume-one.bats`:
  - TEAMMATE: a member head exits 7, spawns nothing, and leaves no `locks/<sid>.launch`.
  - `CC_RESUME_FENCE=off` still refuses.
  - `checked` and `off` spawn.
  - rc 2 exits 5.
  - RED-PROOF no echo before interact: port of `tests/lr-fire-resume-submit.bats:637-655` through
    `CC_RESUME_NO_INTERACT`, sampling `stty -a` 1 s in, requires `-echo`.
- `tests/lr-fire-resume-submit.bats`:
  - A team relaunch with the member row gone gives `relaunch.rc`=12 and no spawn.
  - A same-id live holder gives 12.
  - A team-blind member head with no guard gives 12; with `checked` it spawns.
- `tests/lr-fire-resume-reply-drain.bats`: the `lr-tty-quiet` span is non-empty and identical in both launchers,
  comes before the first `spawn`, and is undone on the line immediately before `set lr_keep [lr_drain_user]`.
- `tests/boot-resume.bats`: `--check-only` rc 7 is counted held, never failed.
- `tests/handoff-recycle-same-account.bats`: the debt open carries `--member yes` with `--team-member-id`, and
  `--member no` for a plain remote pid.
- `tests/teammate-auto-shutdown.bats`:
  - With `transcript_path` in the payload, the transcript lives outside `CC_CLASSIFY_PROJECT_ROOTS` and a
    PATH-stub `find` counts 0 `-name <sid>.jsonl` calls.
  - A path naming another sid is ignored.
  - `TAS_BUDGET_S=0` logs "BUDGET exhausted at", emits no `{"continue":false}`, exits 0, and leaves a
    pane-close-queue row.
- `tests/reap-guard.bats`: `decide --transcript` resolves R-a' and R-d without a root scan; another sid's path is
  ignored.

These must stay green: lr-upgrade T1-T3 and T7; lr-upgrade-settle S2, S3a, S3b and S9c; cc-resume-debt `:134` and
`:281`; `tests/boot-resume-skip-retired.bats`.

## 6. Out of scope and residuals

- **The live orphan pid 57630 (pane 220) is left alone; ending it is the operator's call.** Its argv has no
  `--agent-id` and it is on the target binary, so after step 3a the census reads it `current`.
- **Deliberate behaviour change.** A member that crashed while its lead was alive is no longer resumed team-blind.
  That resume always produced an orphan. The lead learns of it only on the lr-upgrade path.
- **R1-H4 (low).** `bin/cc-husk-sweep:338-342` keeps its whole-file `teamName` grep. Follow-up: OR it with
  `lr_team_member`, so the repo has one teammate test.
- **R2-H5 (low).** Members whose lead or team is gone are held at boot-resume and named on the page line, not
  resumed. Restoring them needs an operator ruling.
- **A successor re-spawned but not yet running when we re-check** is not detected (R2-H2 remainder).
- **Not explained:** why `lru_proven`'s first hold failed while 80169 was alive. The registry-lag hypothesis is
  from slot C. Also not explained: the double `recycle-type-attempt` (`handoffs.jsonl:960-961`) and the
  ttys023/ttys027 discrepancy.
- **Vendor behaviour, not fixed here.** CC 2.1.293 does not persist a member's approving turn. Future guards must key
  on the lead-side `shutdown_approved` or the watchdog row, never on a missing assistant record.
- **`scripts/lib/composer-intent.sh` (`:27`, `:69-71`)** still classifies the ECHOCTL paint form as DRAFT (slot D
  belt).
- **The settings.json TeammateIdle timeout** (5 s) belongs to the operator. Raising it to 10-15 s after Phase 3 is
  a reasonable option. On its own it is a band-aid.
- **Unverified inputs:**
  - The dead pid 15617's argv[0] is inferred as `claude.exe`.
  - TeammateIdle on 2.1.293 carrying `transcript_path` is UNVERIFIED locally; the `-print -quit` fallback covers its
    absence.
  - Exit 7 from boot-resume-launch reads as a plain failure in `lr_recon` act.py and cc-do. act.py never sends
    teammates.
- **Size (estimated by summing the steps):** about 900 lines including tests (the design's 640 plus the
  amendments).

## 7. Implementation brief (a fresh session can run this directly)

```
GOAL  Implement section 4.2 of docs/research/teammate-resurrection-2026-10-16/REPORT.md, in order, in a new worktree
      from origin/main. Read .claude/rules/*.md first. Read every cited range before editing; line numbers are at f6b1fbff2.
FORBIDDEN (live state): never run lr-upgrade.sh drives, cc-resume-debt open/settle/sweep, boot-resume*.sh,
      reso-resume-one, lr-fire-resume.sh, handoff-fire.sh or kitty @ against the real fleet; no kill; never touch pid 57630.
      No git stash, no reset --hard, no heredoc file edits; use the Edit tool.
ORDER (one commit per phase; each phase lands on its own)
 P1  1  scripts/limit-recover/lr-lib.sh        lr_team_member, lr_member_row, lr_death_after, lr_death_wait
     2  scripts/limit-recover/lr-team.sh       lr_agent_id_holders (argv[0] claude|claude.exe, id via ENVIRON)
     3  scripts/limit-recover/lr-upgrade.sh    lru_same_bin (:686 :448 :1965); lru_teammate_block args+superseded+
                                               retired; lru_auto_admits (:3123 :3164); fire_ts + pre-fire recheck (:2654);
                                               belt (:2242); lru_settle 4/5 + --member no + --since; lru_settle_verdict
                                               teammate arm + rc 5 death verdict; lru_teammate_settle; lru_notify_lead
                                               (informational, no command); launch.sh exports GUARD=checked for non-teammates
     4  bin/cc-resume-debt                     --member, --since; _open member+prior_events; _settle rc 5;
                                               _relaunch hint env + rc7 abandon only if member=yes; _escalate GUARD=off line
     5  scripts/boot-resume-launch.sh          question 4 (hint yes/no/empty), exit 7, CMD GUARD=checked, header
     6  bin/reso-resume-one                    belt outside fence; rr_fence_release before rr_refused_exit 7; rc2 -> 5
     7  scripts/boot-resume.sh                 5|7) at :1140 :1301; comment + page text
     8  scripts/limit-recover/lr-fire-resume.sh lr_member_guard after lr_launch_guard (:1036), exit/relaunch.rc 12
     9  scripts/handoff-fire.sh                HF_SA_MEMBER set at :3772, passed at :18231
 P2 10  lr-fire-resume.sh :1066-1076           wrap in >>> lr-tty-quiet / <<< lr-tty-quiet (no apostrophes)
    11  bin/reso-resume-one                    span before :830; restore before :963; bash save :798 / restore :975
 P3 12  hooks/teammate-auto-shutdown.sh        transcript_path; -print -quit; --transcript to reap-guard; budget defer
    13  scripts/reap-guard.sh                  --transcript flag; seed tj; -print -quit
TESTS  write each [RED] case first and watch it fail on HEAD, then implement; files and cases are in REPORT.md section 5.
GATES (after each phase; nothing counts until all pass)
  - /bin/bash -n <every touched #!/bin/bash file>          (bash 3.2 parse; heredoc-paren trap)
  - shellcheck <every touched .sh / bash file>             BARE, exactly as ship-land.sh:3493 runs it; annotate any
                                                           finding with a reasoned disable, never -S or -x
  - bash scripts/test-hermeticity-lint.sh                  (land gate ratchet) on the new and touched suites
  - bats, one file at a time, serially (no --jobs: parallel is absent), and for each check `1..N` == ok + not ok:
      P1 tests/lr-lib.bats tests/lr-team.bats tests/lr-upgrade.bats tests/lr-upgrade-settle.bats
         tests/lr-upgrade-custody.bats tests/cc-resume-debt.bats tests/boot-resume-launch.bats
         tests/lr-recon-fence-callsites.bats tests/reso-resume-one.bats tests/boot-resume.bats
         tests/boot-resume-skip-retired.bats tests/lr-fire-resume-submit.bats
         tests/handoff-recycle-same-account.bats tests/handoff-fire-recycle-custody.bats
         tests/teammate-resurrection-replay.bats
      P2 tests/lr-fire-resume-reply-drain.bats tests/reso-resume-one.bats tests/lr-fire-resume-submit.bats
      P3 tests/teammate-auto-shutdown.bats tests/reap-guard.bats
  - self-checks, fixture HOME only: bin/cc-resume-debt --help (shows --member/--since);
    scripts/boot-resume-launch.sh --dry-run next2 /tmp/x <fixture sid> (CMD shows GUARD=checked);
    scripts/reap-guard.sh decide --transcript <fixture> ... (no root scan)
  - mutants: revert :686 -> T12 red; lru_auto_admits always 0 -> T13 red; delete the belt and the teammate arm
    -> S3e red; delete Q4 -> replay red; delete the tty-quiet span -> RED-PROOF red.
LAND  through the repo's /ship, unwrapped (never put it under your own timeout). Read its verdict and smoke line,
      then run the suites above yourself: LANDED does not mean tested.
REPORT  per phase: files changed, each suite's plan and pass count, which mutants went red, and anything UNVERIFIED that
        stayed open.
```
