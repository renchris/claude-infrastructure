# A10 — Idle visibility: SKEPTIC pass

Wave exhaustive-drive 2026-09-08. Read-only. Every number is measured by me unless marked *inferred*;
the command is beside it. Population is stated per number. The axis report is
`A10-idle-visibility.md` beside this file.

## Verdict in one line

The axis's data is real and reproduces (27 / 25 / 19 / 2 coverage; 50 / 0 ledger fields; 29 open
class-C packets; 23 permpend pages today), but three of its seven recommendations are built on
mechanisms that cannot fire where it puts them: the beat's `lstart` is written in the ambient
timezone so the specified `TZ=UTC` compare classifies **0 of 51** live beats as alive; the Stop-hook
render point (operator-readout, wrap-ledger) is structurally blind to the mid-turn permission wedge
that is the axis's own headline incident; and the two "jq-on-PATH" panes have `/usr/bin/jq` on PATH
and are simply resumed sessions carrying a pre-resume beat.

## Numbers re-run

| claim | axis | re-run | command / population | holds |
|---|---|---|---|---|
| live claude pids / beat / telemetry / neither | 27 / 25 / 19 / 2 | 27 / 25 / 19 / 2 | `bash /tmp/a10-cov.sh`; all 27 are tty-attached interactive sessions (`ps -eo pid,ppid,tty,command`), so the axis's "includes launcher shims" caveat is wrong in the axis's favour | yes |
| live panes BUSY / IDLE | 13 / 6 (n=19) | 6 / 13 (n=19) | `bash /tmp/a10-beats.sh` — a snapshot; population = telemetry pids alive, i.e. keyed on the store the axis calls blind | snapshot only |
| honest-BUSY transcript age ≤252 s (11/12) | max 252 s | live: 523 s (n=6); 24 h corpus: **412** tool calls with a 300–900 s tool_use→tool_result gap, **57** ≥900 s | `scratchpad/gaps.py` over 165 transcripts modified in 24 h, 15,736 tool calls, 4 roots deduped by realpath | **no** |
| open class-C packets | 28 | 29 | `bin/cc-decide list --open --class C --json \| jq length`; raw scan agrees (29 open C, 3 vetoed C, 57 actioned C of 189 files) | drifted +1 |
| author session alive | 1 of 28 | **3 of 29** by beat pid, 2 of 29 by telemetry pid | raw scan; the axis's `a10-dec4.sh` tested liveness ONLY via `/tmp/cc-telemetry` — the store it says misses 30% | direction holds, number wrong |
| packets attachable by `subject_project` | implied all 27 | **13 of 29** carry any of subject_project/project/cwd; `f91a9701ed21` carries none (keys: class,created,default_if_no_veto,id,options,recommendation,route_around_taken,session_pane_uuid,session_sid,staged_artifact_path,status,veto_deadline,what_plain) | jq over decisions/*.json | **no** |
| permission wedge 2,888 s | measured | beacon gone (`/tmp/cc-permission-pending/` holds only `.beacon-alive`); page file `c520f71a….permpend.notified` mtime 16:24 confirms a permpend page at that time | ls | *inferred* now |
| permpend pages today / all-time | 23 / 114 | 23 / 114 | `find ~/.claude/autonomy/pages -name '*.permpend.notified' …` | yes |
| trend 8/14/22/23 "rising sharply" | Sep 5–8 | full series **13, 12, 8, 14, 22, 23** (Sep 3–8) | same find + stat per day | start-point artifact |
| wrap-ledger fields / busy | 50 / 0 | 50 / 0 | `timeout 90 bash scripts/wrap-ledger.sh --machine` | yes |
| PUSHOVER unset | 0 | 0 env, 0 .zshenv, 0 .zshrc; `push-critical.sh:21-22` exits | env, grep | yes |
| tab-title/badge writers | 0 | 0; wider grep (`]0; ]2; set-tab-title it2setkeylabel`) adds only `.zshrc:271` `]1337;SetProfile`, not a title | grep | yes |
| enum at 156692984; idle notif at 181200749 | as quoted | as quoted | `tail -c +OFF claude.exe \| head -c 520` | yes |
| `notificationType:"…"` literal emitters | 14+ | agent_needs_input 1, agent_completed 1, worker_permission_prompt 2, idle_prompt 1, permission_prompt 1, push_notification 1, computer_use_* 2, auth_success 2, elicitation_response 6, elicitation_complete 3, **elicitation_url_dialog 0** | `grep -a -o -E 'notificationType:"[a-z_]+"' \| sort \| uniq -c` | 3 of 4 verified |
| Notification hooks fire for any type | implied | **verified**: `tC()` builds `{hook_event_name:"Notification",message,title,notification_type:E}` and dispatches with `matchQuery:E` | offset context of `hook_event_name:"Notification"` | yes |
| cited lines: wrap-ledger.sh:900 join · :754-760 fail-open · cc-await-ping:535 / :954 · statusline.sh:55-61 / :149-155 · operator-readout.sh:18-27 / :1380-1394 (TTL at :316 = 900) · lead-supervisor.sh:337 send_page, :102 PAGE_TO_FILE=cc-roles/desk (=330) · gate-cleanup.sh:69-92 helpers | | all present as described | sed -n | yes |
| beat lstart vs `TZ=UTC ps -o lstart` | spec says compare under UTC | **match_utc = 0 / 51, match_ambient = 22 / 51** live beats (beat pid answers kill -0); shell TZ unset, zone CDT | loop over cc-beats/*.json | **spec fails** |
| the 2 beat-less pids are jq-on-PATH | *inferred by axis* | PATH of 66521 and 53431 = `~/.aftman/bin:~/.cargo/bin:/usr/bin:/bin:/usr/sbin:/sbin`; **`/usr/bin/jq` exists** (root, 1,492,240 B). Both are `--resume 609597db…` / `--resume 3c4bdc06…` on `.claude-secondary`; their beat files exist with pre-resume pids (33933 lstart Aug 27; 68348 lstart Sep 3), beat t 2026-08-30 / 2026-09-06, and the transcripts' last user line is at those same times — no turn boundary since resume | `ps -E -o command=`, `ls /usr/bin/jq`, jq on beats, jq on transcripts | **no** |
| interrupt leaves kind=prompt stuck | not considered | 152 beats written today; 1 transcript ends on `[Request interrupted by user`, its beat is `stop` | loop | no hazard in sample |
| operator-readout / wrap-ledger host events | Stop | operator-readout: **Stop only**; wrap-ledger: 10 hook callers, all Stop-chain libs, plus /wrap; `cc-permission-beacon.sh write` on **PermissionRequest**, `clear` on Stop/PostToolUse/PostToolUseFailure/SessionEnd | jq over settings.json hooks | see R3/R4 |

## Per-recommendation verdicts

**R1 — `hooks/lib/session-busy.sh` on the beat, BUSY = kind==prompt ∧ kill -0 ∧ `TZ=UTC` lstart match.**
REFUTED AS SPECIFIED. `session-beat.sh:82` runs `ps -o lstart=` with no TZ pin, so the beat carries
ambient-zone text; the memory rule the axis cites (`process-start-time-renders-in-ambient-timezone`)
says pin **both** sides, and only the read side is pinned here. Measured: 0 / 51 match under UTC.
Every live session would classify GONE — the axis's own "must never render BUSY" arm — which is the
silent direction. Comparing under ambient zone works today (22 / 51; the other 29 are recycled pids,
exactly the false-BUSY the leg exists to catch) and breaks on the next DST flip. Second defect: for
the OWN session the field is a gate keyed on its own signal — at Stop `session-beat.sh stop` runs in
parallel with the readers, so kind is racy; from `/wrap` mid-turn it is always `prompt`. Third: a
resumed session carries its pre-resume beat until its first prompt (2 of 27 live, measured), and
reads GONE while alive. The fleet-view use (a reader asking about ANOTHER sid) survives once the TZ
is fixed on the write side. Fail direction as written: silent. Adjusted conviction 60 (fleet view,
with a write-side `TZ=UTC` pin or a recorded zone); ~0 for own-session use.

**R2 — reorder backlog a3eaa0dc1be2 so the beat-based Q1 sensor is step 1.**
NOT REFUTED. The Q1/Q2 conflation is a real reading of D8 ("asked in the wake-path session, no close
was happening"), and demoting a SIGKILL-selector refactor out of step 1 is sound on its own. It
inherits R1's TZ and resume defects, so step 1 is "fix the beat writer", not "read the beat". Fail
direction: under-build, status quo. Adjusted conviction 80.

**R3 — wrap-ledger machine fields BUSY/BUSY_STATE/PERMPEND… from the beat.**
REFUTED for the beat-derived and PERMPEND fields; holds only for `sb_busy_jobs` (Q2). wrap-ledger is
consumed by 10 Stop-chain hooks and by `/wrap`. At Stop the own beat is being rewritten to `stop` by a
parallel hook (race → nondeterministic); in `/wrap` kind is always `prompt` (constant → zero bits,
the alarm-polarity rule). `PERMPEND` for the own session at Stop is definitionally 0 because
`cc-permission-beacon.sh clear` is itself a Stop hook. The only own-session fact with information is
the descendant-job scan. Fail direction: a constant or racy field is noise a renderer will one day
trust. Adjusted conviction 35 (for BUSY_JOBS/BUSY_SAMPLE only).

**R4 — operator-readout renders BUSY-SUSPECT (kind==prompt ∧ transcript age > 900 s) unconditionally.**
REFUTED. (a) Host: operator-readout is registered on Stop only. The headline incident — a pane parked
on a permission modal mid-turn — never reaches Stop, so the own-pane render is unreachable; a
cross-pane render would fire at every OTHER pane's close for the whole 48 minutes (level, not edge,
into the wrong pane). (b) Threshold: "900 s sits 3.5× above the honest-BUSY population" was sized on
12 panes at one instant. Over 24 h and 15,736 tool calls: 412 gaps in 300–900 s, 57 ≥ 900 s (55 Bash,
1 Write, 1 AskUserQuestion; histogram 900–1800: 16, 1800–3600: 14, 3600–7200: 8, >7200: 19), and 0
of the 57 tool_results carry deny/interrupt text — the ≥900 s band is long foreground Bash runs and
crash/resume gaps, with permission waits indistinguishable inside it. A transcript-age rule fires
~57×/day fleet-wide and cannot name the cause. The discriminator that CAN — the PermissionRequest
beacon — already exists and already pages (23 today); the defect is delivery, not detection. Fail
direction as proposed: fires on legitimate long runs (the axis concedes) AND is silent for the case
it was built for. Adjusted conviction 25.

**R5 — register agent_needs_input / worker_permission_prompt / agent_completed / elicitation_url_dialog.**
NOT REFUTED, narrowed. The dispatch path is verified in the binary: `tC()` posts every `tv()`
notification to hooks as `notification_type:E` with `matchQuery:E`, so a matcher on these strings
fires. Three of the four have literal emitters (`agent_needs_input` from the agent band machine on
`blocked`; `agent_completed` on `completed` but suppressed when `S.selfDriving` or `outcome==="stopped"`;
`worker_permission_prompt` for tool and network permission). `elicitation_url_dialog` has 0 literal
emitters — enum-only until shown otherwise. Value is contingent: the only human-facing sink,
push-critical.sh, is inert (PUSHOVER unset, 51-day packet), so registering matchers routes into a
dead channel unless wired to notify.sh/beacon paths. Fail direction: more chimes, especially
`agent_completed` for non-self-driving assignees. Adjusted conviction 78.

**R6 — pull-surface pane roster (cc-where sibling) composing beacon + class-C by sid + 👤 by session.**
NOT REFUTED, corrected. Beat coverage and cc-where addressing hold. Corrections: attach-by-project
reaches at most 13 of 29 open class-C packets (16 carry no project/cwd field at all;
`session_pane_uuid` is present and is the better re-attach key while the pane lives); author-liveness
is 3 of 29 by beat, not 1 of 28, because the axis's census read liveness from the telemetry store it
had just called blind. `cc-backlog` rows carry a `session` key, so per-session 👤 composition is
feasible (measured keys). The natural owner already exists and was not considered: lead-supervisor
enumerates the fleet from `TEL_DIR=/tmp/cc-telemetry` (`lead-supervisor.sh:97`) — its own
`self-check BLIND live=27 enum=22 delta=5` is precisely the telemetry blindness the axis measured,
and switching its enumeration to the beat store is the smallest change that makes the existing
pager see every pane. Fail direction: unread if standalone. Adjusted conviction 75.

**R7 — repair jq-on-PATH in session-beat.sh.**
REFUTED on diagnosis. Both uncovered pids have `/usr/bin` on PATH and `/usr/bin/jq` is installed, so
`command -v jq` succeeds and the beat does not no-op. Their beat files exist under the `--resume`
sid with pre-resume pids and no user line since; they are resumed sessions idle at the input box
with no turn boundary since resume. The PATH probe is harmless (fast path on a box with jq) but
fixes nothing measured; the real gap is that a resume writes no beat — a `SessionStart` beat, or a
SessionStart-time pid/lstart refresh, is the fix. Fail direction of the proposed change: none;
fail direction of leaving the real gap: a resumed pane reads GONE (silent) until its first prompt.
Adjusted conviction 20 as written; ~85 for the SessionStart beat.

## What the axis missed that its question required

1. **The Stop chain cannot see the state the axis is trying to render.** A pane wedged on a
   permission modal is mid-turn; no Stop hook runs for it. Every "render it at the close" proposal
   (R3, R4) is unreachable for the incident pane. The hosts that DO fire in that state exist:
   `cc-permission-beacon.sh write` on PermissionRequest, `notify.sh permission` + `push-critical.sh`
   on Notification, and lead-supervisor's permpend page at t+2 min. The loop is closed at detection
   and open at delivery — the axis measured this in §5 and then recommended detection.
2. **Write-side TZ pin.** `session-beat.sh:82` records ambient-zone `lstart`; 0 / 51 match under UTC.
3. **Resume writes no beat.** A resumed session carries a dead pid until its first prompt (2 / 27 live).
4. **Own-signal gating.** A session reading its own beat kind at Stop races the hook that rewrites it.
5. **Threshold sized on a snapshot, not the corpus.** 412 tool calls/day sit in the 300–900 s band
   and 57 exceed 900 s; the beacon, not transcript age, is the discriminator.
6. **The supervisor's blindness is the telemetry key.** `lead-supervisor.sh:97` enumerates from
   `/tmp/cc-telemetry`; the axis quotes its BLIND self-check as corroboration and never proposes
   re-keying it on the beat store — the one-line change that makes an existing pager fleet-complete.
7. **Liveness census keyed on the blind store**, and `subject_project` present on 13 / 29 packets.
8. **Trend start-point.** The full permpend series is 13, 12, 8, 14, 22, 23; "8 → 23" begins at the minimum.
9. **The beat's `who` field is unused.** BUSY-under-auto-drive vs BUSY-under-operator is exactly the
   "needs you" distinction the roster wants, and it is already in the JSON.
10. **`agent_completed` is suppressed for self-driving agents** and `elicitation_url_dialog` has no
    literal emitter — R5's four is three.

## Commands (all read-only; scratch in the session scratchpad)

- coverage: `bash /tmp/a10-cov.sh`; inventory: `ps -eo pid=,ppid=,tty=,command= | awk '{c=$4; sub(/.*\//,"",c); if (c ~ /^claude/) print}'`
- TZ test: loop over `~/.claude/cc-beats/*.json` comparing `.lstart` to `ps -o lstart=` and `TZ=UTC ps -o lstart=`
- gaps: `python3 scratchpad/gaps.py 900` (tool_use→tool_result deltas, transcripts mtime < 24 h, 4 roots, realpath-deduped)
- decisions: `bin/cc-decide list --open --class C --json | jq length`; raw `jq` over `~/.claude/autonomy/decisions/*.json`
- binary: `LC_ALL=C /usr/bin/grep -a -b -o -F '<literal>' claude.exe` then `tail -c +OFF | head -c 460`
- PATH of a pid: `ps -E -o command= -p <pid> | tr ' ' '\n' | grep '^PATH='`
