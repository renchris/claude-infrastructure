# Husk panes: runtime evidence and filed state (logs, backlog, decisions, memory)

Slice: runtime logs under `~/.claude/logs`, the backlog and decisions under `~/.claude/autonomy`,
memory, lessons and rules. Read-only. Everything here was measured on 2026-10-24 (local, CDT;
log timestamps are UTC, so the pane 289 rows dated `2026-10-25T00:..Z` happened on the evening of
10-24 local time). Weeks start on Monday (UTC). Pane ids get reused after each kitty restart, so
counts are keyed on (pane, UTC day) unless the text says otherwise.

## 0. Sources and what each one records

| log | rows (`wc -l`) | span | what it records |
|---|---|---|---|
| `close-attrib.jsonl` | 1256 | 2026-08-07 .. 2026-10-24T23:53Z | One row per close attempt from `handoff-fire.sh self-close` (in-session) and `restore-focus-or-fail`. `verdict` = closed / closed-rcN / STILL-PRESENT-rcN / unverified-rc124 |
| `pane-close.jsonl` | 402 | 2026-10-01T16:39Z .. 2026-10-25T01:33Z | One row per post-exit `bin/cc-pane-close` verdict (`refused`, `would-close`, `closed-kitty-unreaped`, ...) with a `reason` |
| `pane-close-retry.log` | 25949 | 2026-10-01T08:51Z .. now | Drainer (`scripts/pane-close-retry.sh`) text log. Kinds: `self-close`, `teammate`, `recycle`, `husk` (the `husk` kind first appears 2026-10-23) |
| `pane-say.jsonl` | 1243 | 2026-10-19T12:46Z .. now | Banners painted into panes (`cc-pane-runner`, `cc-pane-verdict`, `lead-crash-watchdog`, `lr-fire-resume`) |
| `husk-sweep.jsonl` | 8 | 2026-10-21T17:03Z only | Only records `--resume` actions (8 × `resumed`). Read-only `cc-husk-sweep` verdicts such as pane 289's "COLLECTED" are **not logged** |
| `pane-close-drainer.err.log` | 33 rows | — | All 33 rows: `pane-close-retry.sh: line 415: printf: write error: Broken pipe` |

`rg -l -i husk ~/.claude/logs` also hits bash-commands/bash-execution, sessions.log, cc-wake.jsonl,
handoffs.jsonl, teammate-lifecycle.log and others. Those are command echoes, not close outcomes,
and I did not count them.

## 1. Recurrence over time (measured)

### 1a. In-session self-close outcomes (`close-attrib.jsonl`)

Command: `jq -r '(.ts|strptime(..)|mktime|strftime("%Y-W%W")) as $w | [$w,.verdict]' | sort | uniq -c`.

| week (Mon) | closed | closed-rcN (closed, but reported nonzero) | STILL-PRESENT rc67 | rc1 | rc70 (fs guard) | rc124 / rc3 / unverified-rc124 |
|---|---|---|---|---|---|---|
| 08-03 | 193 | 8 | 0 | 0 | 0 | 3 + 2 rc3 |
| 08-10 | 160 | 4 | 4 | 2 | 0 | 0 |
| 08-17 | 118 | 0 | 0 | 0 | 0 | 0 |
| 08-24 | 19 | 0 | 0 | 0 | 0 | 0 |
| 08-31 | 41 | 0 | 8 | 0 | 0 | 0 |
| 09-07 | 226 | 4 | 4 | 0 | 0 | 0 |
| 09-14 | 90 | 0 | 0 | 0 | 0 | 0 |
| 09-21 | 124 | 0 | 0 | 0 | 0 | 1 |
| 09-28 | 116 | 1 | 4 | 0 | 0 | 0 |
| 10-05 | 2 | 2 | 8 | 0 | 0 | 1 + 5 unverified |
| 10-12 | 6 | 8 | 4 | 12 | 1 | 0 |
| 10-19 | 23 | 28 | 4 | 4 | 9 | 7 unverified + 1 closed-rc124 |

The same data as distinct failed incidents (pane+day whose self-close left the pane STILL-PRESENT
or unverified). Command: `sort -u -k1,2` over the failed rows, then bucketed by week:

| week | incidents | breakdown |
|---|---|---|
| 08-03 | 5 | rc124 ×3, rc3 ×2 |
| 08-10 | 3 | rc1 ×2, rc67 ×1 |
| 08-31 | 2 | rc67 |
| 09-07 | 1 | rc67 |
| 09-21 | 1 | rc124 |
| 09-28 | 1 | rc67 |
| 10-05 | 5 | rc124 ×1, rc67 ×2, unverified-rc124 ×2 |
| 10-12 | 5 | rc1 ×3, rc67 ×1, rc70 ×1 |
| 10-19 | **13** | **rc70 ×9**, unverified-rc124 ×2, rc1 ×1, rc67 ×1 |

- **rc70 first appears 2026-10-16T22:20:35Z (pane 210).** That is the day after `62372906a`
  (2026-10-15, "fullscreen guard on the autonomous closers") and the same day as `1211646fb`
  (2026-10-16, "exit 70 on a refused-fs close; self-close pages husk-fs without retrying").
  Since then it is the largest single failure class: 10 rc70 incidents (panes 210, 149, 363, 476,
  54, 56, 165, 280, 282, 289). Pane-days since 10-16T22, keyed on the first verdict per
  (pane, day) (measured, `sort -u -k1,2`): 61 closed, 10 rc70, 2 unverified-rc124, 1 rc1, 1 rc67.
  So about 14 of 75 self-closing pane-days failed, and about 71% of those failures were rc70.
- Weekly `closed` volume fell from 90–226 a week (Aug–Sep) to 2–23 a week from 10-05 on.
  `close-attrib` logs only the in-session `self-close` path. An estimate, not measured: after
  `74baff1ee` (2026-10-01, "a clean claude exit closes the pane unless a recycle is pending")
  most panes close through `cc-pane-runner` close-on-exit, which does not write `close-attrib`.
  The denominator for husks therefore moved to a log that only exists from 10-19 (`pane-say`).

### 1b. Post-exit closer refusals (`pane-close.jsonl`, `bin/cc-pane-close`)

Categories come from a jq regex over `.reason` (a filter file in /tmp). Rows per week:

| week | category | rows |
|---|---|---|
| 09-28 | would-close 9 · no-registration 8 · nothing-to-close 5 · failed 3 · claude-running 3 · no-window-proc 3 · closed-kitty-unreaped 2 · different-window 1 · no-transcript 1 | 35 |
| 10-05 | no-intent-to-end ("nothing says session X meant to end") | 2 |
| 10-12 | no-registration 24 · no-intent-to-end 10 · rc-down+fullscreen 2 · different-window 1 · no-transcript 1 | 38 |
| 10-19 | **launch-never-started-unnamed 257** · rc-down+fullscreen 21 · **fs-guard(last-pane) 17** · would-close 15 · **dirty-cwd 9** · closed-kitty-unreaped 7 · no-intent-to-end 1 | 327 |

Since 2026-10-15, rows and distinct panes per category:

| category | rows | distinct panes |
|---|---|---|
| launch-never-started, kitty does not name the window | 257 | 30 (10-21 ×5, 10-22 ×16, 10-23 ×9) |
| no session registration in this kitty's lifetime | 24 | 22 (10-17 ×7, 10-18 ×15) |
| kitty remote control down + a fullscreen window | 23 | 11 |
| fullscreen guard: last pane of a fullscreen OS window | 17 | 3 (165, 280, 282) |
| would-close | 15 | 5 |
| nothing says the session meant to end | 11 | 9 |
| **cwd holds N uncommitted change(s)** | 9 | **1 (pane 289 only)** |
| closed-kitty-unreaped | 7 | 7 |

The dirty-cwd gate (gate 4, `bin/cc-pane-close:508-511`) has existed since `d150099dd`
(2026-10-01). Its first and only refusals were the 9 on pane 289. It blocks even when gate 3 has
already found "its last close said Good to close: yes" (`bin/cc-pane-close:497` sets `why`,
then `:509-511` still refuses on any dirt). The dirt check counts
`git -C "$cwd" status --porcelain` for the **whole cwd**, not the session's own paths.

### 1c. Drainer (`pane-close-retry.log`)

Distinct panes per week by row kind (python over the log):

| week | self-close | teammate | recycle | husk |
|---|---|---|---|---|
| 09-28 | 10 | 22 | 3 | — |
| 10-05 | 9 | 12 | 6 | — |
| 10-12 | 15 | 84 | 7 | — |
| 10-19 | 24 | 92 | 1 | 12 |

- Log volume is mostly holding noise: 22875 of 25949 rows are `self-close pane=N already paged — held
  for handoff-fire` (measured, `uniq -c`). Self-close rows for panes 70, 78, 85–89, 111 and 128 were
  held from 2026-10-12T00:01Z until `dropped: the row predates the running kitty` at
  2026-10-23T10:23Z–11:23Z, which is 11 days. The fix that dropped them was `85b1d7131` (2026-10-22).
- `husk` rows (from 10-23, after `5d0be0366` "a kept pane is a durable husk row") give these final
  dispositions: closer exceeded its 60 s bound 18, held for the operator (⌘W) 15, pane gone 6,
  CLOSED 5, fullscreen-last-pane paged 2, hold released 2, tty typed in → operator owns it 1.
- **rc124 closer timeouts** ("cc-pane-close rc=124 with no output", "closer exceeded its 60s
  bound"): pane 145 ×1, 146 ×1, 165 ×5 (10-23), 280 ×4, 282 ×2 (10-24), **289 ×12** (10-25Z).

### 1d. Pane 289 (session 7555024a), the 2026-10-24 incident, as logged

| UTC | source | event |
|---|---|---|
| 23:53:36Z | pane-say `cc-pane-verdict` | DONE "✓ done" |
| 23:53:38Z | close-attrib | self-close id 289 → `STILL-PRESENT-rc70` |
| 23:53Z | pane-say `cc-pane-runner` | "claude4 exited 0 — guard: kitty-fullscreen-guard: refused" |
| 23:55:00Z | pane-say | CANTTELL "◆ check 7555024a" |
| 00:00:13Z | pane-close / retry attempt 1 | REFUSED — `/Users/chrisren/Development/personal holds 138 uncommitted change(s)` |
| 00:00:14Z | pane-say | **RESUME "⛔ resume 7555024a"** |
| 00:00–01:38Z | retry attempts 1–21 | 9 × dirty-cwd rc=1, **12 × rc=124 (closer exceeded its 60 s bound)**, interleaved: rc=1 at attempts 1,2,3,5,6,11,16,18,20; rc=124 at 4,7–10,12–15,17,19,21 |
| 01:45:55Z | retry | `its tty was typed in since — the operator owns it; row removed, never closed` |

Three tools gave three verdicts for one pane within 7 minutes: DONE, then CANTTELL, then RESUME.
A fourth, `cc-husk-sweep`, said COLLECTED. More than half of the 21 "refusals" were the closer
timing out, not the dirt gate. The drainer then gave up because the operator typed into the
pane, so it was never closed.

### 1e. Banners and kept panes (`pane-say.jsonl`, from 10-19 only)

- `cc-pane-verdict` paints: NOTHING 16, DONE 16, CANTTELL 12, RESUME 1 (pane 289). Pane 165 got 14
  paints on 10-23 with 8 DONE ↔ CANTTELL changes (13:01Z DONE, 13:30Z CANTTELL, 14:39Z DONE,
  15:16Z CANTTELL, … 20:52Z DONE). Its 4 CANTTELL paints fall on the same day as its 5 rc124
  closer timeouts; I did not join them row by row.
  `bin/cc-pane-verdict:83-90` maps anything unclassed, including an empty or timed-out closer
  answer, to CANTTELL.
- Panes kept open by `cc-pane-runner` close-on-exit since 10-20: 28 distinct panes (by `sort -u` on
  pane). 22 of them were "last pane of a fullscreen window" or "guard: kitty-fullscreen-guard"
  (149, 170, 363, 476, 54, 56, 42, 50, 63, 72, 81, 82, 80, 90, 88, 89, 106, 133, 165, 280, 282, 289)
  and 6 were "kitty didn't answer" (135, 139, 144–147 on 10-23).
- `lead-crash-watchdog`: "pane kept" 23, "ended, reason unknown" 20, both peaking at 13 each on 10-22.

### 1f. Distinct husk panes since 2026-10-15 (estimated)

Method: the union of (pane, UTC day) over three sets. Set A is close-attrib failures. Set B is
`cc-pane-runner` kept panes. Set C is pane-close refusals in the launch-never-started,
no-registration and rc-down classes.

- A (18): 55, 80, 181, 201, 210 (10-16); 16 (10-19); 149, 170 (10-20); 363, 476 (10-21); 54, 56, 42, 18 (10-22); 165 (10-23); 280, 282, 289 (10-24).
- B adds 17: 50, 63, 72, 81, 82, 80@22, 88, 89, 90, 106 (10-22); 133, 135, 139, 144, 145, 146, 147 (10-23).
- C adds about 40 more: 22 no-registration panes on 10-17/18 after the 10-15 kitty crash, plus
  launch-never-started panes 26–32 (10-21) and 48, 51, 101–109 (10-22).

Estimate: **about 35 husk incidents on the self-close and close-on-exit paths since 10-15**, plus
about 40 abandoned or never-started panes that the post-exit closer refused to touch.
**Dominant reasons since 10-15:** for sessions that meant to end, the fullscreen last-pane
guard (rc70 / "last pane of a fullscreen window", 22+ panes). For panes with no session, the
closer could not name the window, or there was no registration in this kitty's lifetime
(281 rows, 52 panes). Dirty cwd caused exactly 1 pane (289). Closer rc124 timeouts hit 6 panes.

## 2. Backlog and decisions (filed state)

`rg -i husk ~/.claude/autonomy/backlog.jsonl` matched 58 event rows across 32 ids. The backlog is
event-sourced; the table folds the events per id. Every row is now `done`, so **no husk item is
open** in the backlog.

| id | filed | last event | what (truncated) |
|---|---|---|---|
| 3c046b111919 | 07-26 | done (08-09) | self-close hangs forever in completion-push → cc-announce (no timeout) |
| b2787f38dd80 | 07-26 | done (08-10) | iTerm2 restart; its flaky Python-API socket "produced the husk-pane class" |
| 4dd560d16754 | 07-31 | done | self-close leaves a HUSK pane, records a false 'claude exited' (session c5f80b8b) |
| 71909cbeee08 | 07-31 | done (08-09) | self-close targets the WRONG pane id (corrects 4dd560d16754) |
| c5d25ebe630b | 08-10 | done | remote-driven --close-source targets the invoking pane |
| 42f9772d4b67 | 08-10 | done | close husk pane 72 (session 21fe99e4 transplanted to next4) |
| c6c40a57820e | 08-16 | done | pane 115 husk: transplanted, but its teammate still live |
| 6f4573454230 | 09-08 | done | cc-teardown recorded as CRASH; page prescribes a harmful resume |
| 5dbca0071e85 | 09-19 | done | close kitty window 150, tombstoned husk of 7f533f05 |
| 45cc39bf65c3 / dbb994e2878e / 3e77c9754261 | 09-20 | done | close husk panes 110/126/150 left by the 09-19 transplant wave |
| e9bea40e7af8 | 09-20 | done | self-close REMOTE-PANE-RESOLVER-UNAVAILABLE cannot tell a dead socket from a slow one |
| 3d9943ec9e87 | 09-20 | done (09-23) | cc-limited has no HUSK disposition |
| 8ae45c330924 | 10-01 | done | re-land fix/husk-pane-closers |
| 21ba8983cd4a | 10-01 | done | fire pane-lifecycle fix session: seven self-close/recycle/husk-verdict fixes |
| f5f9ff77284c | 10-01 | done | close husk panes 55/69/76 (refused to the agent by the auto-mode classifier) |
| 4a2e950efe4f | 10-01 | done | restart kitty to restore remote control |
| 09123f46c397 / 474190a6c22f | 10-10 | done | lr-stranded-husk resume and re-land |
| 884fc029b2f7 / 13b99f7c3910 | 10-18 / 10-20 | done | stranded husk 3e929a81, premise refuted |
| e9b218ff00bf | 10-21 | done | allowlist cc-husk-sweep for agents |
| 3dde5e53312f | 10-23 | done | close dead panes 85, 42, 101 and resume lead 666022fd ("auto mode refuses pane closes") |

The rest of the 32 ids (1da6ceee8079, 0477dc8cff91, 233f363c97e4, ed54373d639b, 15f2e8125671,
f4863408f038, 169ff02be19a, cdbfe751ccc5) mention husk only in passing.

Other backlog ids since 09-25 that mention self-close or pane-close: 41eb932032dd (09-28, close
idle pane 882), ba25097a6337 (09-29), c21494feb3dc and 31a031a38e75 (10-15/16, restore the
kitty-crash sessions), 661a8652d2f6 (10-16, trial of the background-Space close on the patched
kitty). All are done.

Four operator items were filed to have a human close panes because the agent was refused:
f5f9ff77284c, 4a2e950efe4f, e9b218ff00bf and 3dde5e53312f.

Decisions (`rg -l -i` husk / self-close / fullscreen / bare shell in `~/.claude/autonomy/decisions`):

| id | created | status | question → ruling |
|---|---|---|---|
| cbab9581db20 | 09-19 | actioned | LR relaunch refused by the load check leaves a husk → refuted by the filer (self-inflicted `CC_ADMIT_LOAD_TERM=off` split) |
| 742d8713ad01 | 09-21 | actioned | resurrect two limit-blocked sessions → resolved by research |
| 337e100f5c71 | 10-01 | actioned | close a self-started plain terminal on /exit? → keep off; fleet panes close from inside (`74baff1ee`) |
| 0a8ffe58562a | 10-01 | actioned | adopt patched kitty at the next reboot → swap armed (`eec8e995f`, patch 858ab7ce5) |
| a41897063971 | 10-15 | actioned | report the two kitty bugs upstream → kovidgoyal/kitty#10671, #10672 |
| **e3920969aba9** | 10-16 | actioned | "Until the patched kitty build is running … should agents be allowed to close the last pane of a fullscreen kitty window? … blocking it left 3 dead panes over 29 hours" → operator: **keep blocking agent last-pane closes on stock kitty**; relax only under the patched-marker + onscreen condition |
| a172a41d0d79 | 10-21 | actioned | macOS upgrade → wait; keep rebooting on the forecast (full-screen Spaces and kernel leak unfixed) |
| 96215788a791 | 10-19 | actioned | close idle session 9f6593c5 → self-closed pane 19 |

`~/.claude/autonomy/kitty-restart-pending` no longer exists (ls: no such file), and the guard
was still refusing on 10-24 (pane-close rows for 280 and 282 say "refused-fs"). So the
precondition in e3920969aba9 is still unmet. This is inferred from the logs: whether the patched
build is running was not probed.

## 3. Memory, lessons and rules that name husk / self-close / pane-close

`rg -l -i -e husk -e self-close -e pane-close` returned 54 files; 9 of them are archived memory
indexes and are skipped. One line each:

**Memory** (`~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/`)
- `feedback-resume-husks-yourself.md`: resume killed-session husk panes yourself with cc-husk-sweep (allowlisted); never hand the operator the resume line.
- `dead-session-verdict-belongs-in-the-pane.md`: a killed session's pane looks byte-identical to a clean /exit. Paint the verdict into the pane (write to its tty) and escalate when the recipient is the victim.
- `panic-recreates-pane-orphans-fired-stamp.md`: a panic or resume-from-summary recreates the pane under a new UUID, which orphans the fired-peer self-close stamp. Self-close then fails for a legitimately fired peer.
- `transplanted-session-loses-dispatch-identity.md`: a transplanted or resumed session has no ITERM_SESSION_ID and no registry row, so it can neither --recycle nor self-close. Register the pane.
- `probe-that-acts-on-absence-must-confirm-presence.md`: a probe whose negative fires an action must positively confirm the safe state; `ps -t` is blind under nested ptys.
- `lookup-miss-is-not-absence.md`: an agent name searched in a pane-id list can only miss, and that miss shipped as exit 0 "already gone".
- `remediation-perturbs-its-own-population.md`: 8 closes reflowed the remaining panes into a width where the fix went blind.
- `new-enum-member-falls-into-fail-closed-default.md`: a new verdict state mis-advertises through every derivation keyed on the enum, and a fail-closed default hides it.
- `absolution-tokens-and-two-phase-teardown.md`: a marker that absolves a death must name its subject; a two-phase teardown must retry phase 2 or it manufactures crash-lookalikes.
- `background-work-has-three-launch-shapes.md`: an "is it still working?" check must see background Bash, timed-out-to-background Bash and Monitor.
- `shutdown-request-is-not-an-actuator.md`: an idle agent never answers shutdown_request; TaskStop is the actuator, and a clean git status is not a liveness check.
- `desk-worker-lifecycle-triage.md`, `desk-spawned-session-lifecycle-discipline.md`, `implicit-team-lifecycle-discipline.md`: lifecycle and triage discipline for fired, desk and teammate sessions (the reaper is the deterministic safety net).
- `clean-worktree-cannot-distinguish-never-worked-from-landed.md`: a clean 0-ahead worktree signals landed work; discriminate on the trunk.
- `argv-is-sampling-cwd-is-durable.md`, `pgrep-f-matches-agent-briefs.md`, `bounding-external-calls.md`, `liveness-proxy-cannot-be-output-age.md`, `gate-composition-two-halves-one-subject.md`, `gate-exemption-is-not-permission.md`, `metric-zero-by-refusing-gate.md`, `inventory-before-building.md`, `dispatcher-verdict-is-not-the-fired-sessions-state.md`, `durable-path-in-a-generated-launcher-executes-the-live-layer.md`, `deployed-copy-as-parsed-contract.md`, `instrument-must-have-an-as-built-mode.md`, `session-crash-per-session-bloat.md`, `redundant-session-gc-by-content.md`, `bare-provenance-token-names-absence-not-actor.md`, `authorization-is-not-transitive-over-peer-mail.md`, `gate-never-ran-vs-gate-red.md`, `pty-probe-slash-command-writes-shared-user-settings.md`, `tmux-panes-inherit-server-iterm-session-id.md`: general gate, probe and liveness rules whose worked example was a self-close or husk case.

`gate-composition-two-halves-one-subject.md` is the one most directly broken by pane 289's gate 4.
Its rule is that both predicates must be pinned to the same subject. Gate 3 (intent) is keyed on
the session; gate 4 (dirt) is keyed on the whole cwd.

**Lessons** (`docs/lessons/`)
- `a-mid-turn-brief-is-invisible-to-the-fired-peer-detector.md`: self-close --terminal refused a genuinely fired peer as an ORIGIN session (2026-09-10).
- `remote-pane-identity-is-the-targets-not-the-drivers.md`: resolve the target pane, not the driver's ancestry; the misread left tombstoned husks (09-10 ×3, 09-14 ×2, 09-19 ×4).
- `two-causes-one-rc-ask-a-lower-layer.md`: one rc (REMOTE-PANE-RESOLVER-UNAVAILABLE) had two causes behind self-close --source-pane refusing husks 110/126; ask a lower layer.
- `a-transient-fault-is-explained-by-whatever-was-standing.md`: a transient remote-control fault got attributed to whatever was standing (row dbb994e2878e).
- `peer-filed-operator-steps-belong-to-the-firer.md`: the self-close orphan inventory had the same blindness as peer-filed operator steps.
- `as-specified-as-built.md`, `launcher-runs-the-live-layer.md`: measure as built; a generated launcher runs the live layer.

**Rules** (`.claude/rules/`)
- `agent-operating-lessons-situational.md:11` (2026-09-09): a session killed by SIGTERM prints the ordinary "Resume this session" text; the dead-session verdict belongs in the pane (points at the memory file above).

## 4. Chronological table

| when | source | what was asked / claimed | root cause (as filed) | change (sha) | recurred? |
|---|---|---|---|---|---|
| 2026-07-25 | commit 4cd42ec45 | self-close must not orphan a live team nor leave a husk pane | team orphaning | 4cd42ec45 | yes, husk rows from 08-03 (close-attrib rc124 ×3, rc3 ×2) |
| 2026-07-26 | backlog 3c046b111919 | self-close hangs forever in completion-push | no timeout on cc-announce | done 08-09 | timeouts recur as rc124 (09-21, 10-05, 10-22) |
| 2026-07-31 | backlog 4dd560d16754 → 71909cbeee08 | self-close leaves a husk and records a false exit | wrong pane id targeted | 5515ac089 (08-08), fe7b675ad (08-07) | yes, rc1/rc67 08-10 |
| 2026-08-10 | backlog c5d25ebe630b, 42f9772d4b67; commits 65c612e05, 0a94736ca | transplant leaves a husk; the husk at 100% of its window could not run its own close | the source pane is not closed by a transplant | 65c612e05, 0a94736ca | yes, 09-19/20 transplant wave (110, 126, 150) |
| 2026-09-04 | commit 570c20375 | find every pane at a bare shell over a dead session | husks only detectable by sweep | 570c20375 (cc-husk-sweep born) | — |
| 2026-09-08 | memory dead-session-verdict-belongs-in-the-pane; commit 810ee9be3 | paint the death verdict into the pane | a killed pane looks like a clean /exit | 810ee9be3 | the paint itself later disagreed with other tools (10-23, 10-24) |
| 2026-09-19..22 | backlog 5dbca0071e85, 45cc39bf65c3, dbb994e2878e, 3e77c9754261, e9bea40e7af8 | close husks 110/126/150; resolver cannot tell dead from slow | driver-ancestry identity; slow vs dead socket | 08bdf357d, 90eda0040 | yes |
| 2026-09-30 | commit 55a2a049e (docs/research/husk-panes-2026-09-30.md) | husk census after the reboot | several | 7eb551b39, 476712b2f, f57055245 | yes |
| 2026-10-01 | backlog 21ba8983cd4a, f5f9ff77284c, 4a2e950efe4f; decision 337e100f5c71; commits d150099dd, 74baff1ee, 107755b5b, bd39fb7c7 | seven self-close/recycle/husk-verdict fixes; cc-pane-close born **with gate 4 (dirty cwd)**; runner closes on a clean exit | deaf kitty remote control; no post-exit closer | d150099dd, 74baff1ee | yes: pane-close refusals 09-28 week 35 rows, 10-12 week 38 rows |
| 2026-10-10 | backlog 09123f46c397, 474190a6c22f; commits e67a156e4, d30f1f3ad | lr-stranded-husk: five causes | limit-recover leaves husks | 30ecec45d, 2158f14ad | yes, 884fc029b2f7 on 10-18 (premise refuted 10-20) |
| 2026-10-15 | decision a41897063971; commit 62372906a | kitty crash; **fullscreen guard added to the autonomous closers** | closing the last pane of a fullscreen window crashed kitty | 62372906a | **opened a new husk class** |
| 2026-10-16 | decision e3920969aba9; commit 1211646fb | keep blocking agent last-pane closes on stock kitty ("blocking it left 3 dead panes over 29 hours") | deliberate trade: crash risk vs husk | 1211646fb (exit 70, page husk-fs, no retry) | **yes: rc70 ×10 (10-16..10-24), runner fs-kept ×22 panes** |
| 2026-10-17..18 | pane-close.jsonl | 22 panes refused "no session registration in this kitty's lifetime" | registrations lost across the 10-15 kitty crash | 85b1d7131 (10-22, drop old-kitty rows) | rows held 11 days (retry log 10-12 → 10-23) |
| 2026-10-19 | commit 54acfdb98 | "truthful lr-aware banners and a closer that can close the overnight husks" | | 54acfdb98, e11666b4c, a0a41b5d1 | yes, 10-22 peak (13 kept panes) |
| 2026-10-21 | backlog e9b218ff00bf; husk-sweep.jsonl | allowlist cc-husk-sweep; 8 panes resumed 17:03Z | husks after a mass SIGTERM (docs/research/husk-mass-sigterm-2026-10-21.md) | d7d5df709 | — |
| 2026-10-22 | commits 99acf1d9f, d82aa7860, 5d0be0366, c820e86f1, 2c94cf6d8 | **cc-pane-verdict born** (one writer for a dead pane's title); self-close hands an uncloseable pane to the closer; a kept pane becomes a durable husk row | several painters disagreed | as listed | yes: pane 165 changes state 8 times across 14 paints on 10-23; pane 289 three states in 7 min |
| 2026-10-23 | backlog 3dde5e53312f; commits 957279537, 4cb749ceb, 3f1a77b71, 03696fdd5, 0375891ac | background closer blind to kitty; operator-only husk holds honestly; drainer bounded | closer cannot see kitty from launchd; no operator-only state | as listed | yes: 280, 282 (fs), 289 (dirty + rc124) on 10-24 |
| 2026-10-24 23:53Z | close-attrib, pane-close, pane-say, retry log | pane 289: session said "Good to close: yes"; rc70; 9 dirty refusals + 12 rc124 timeouts; painted ⛔ RESUME; dropped as "operator owns it" | gate 4 keyed on the whole cwd, not the session; verdict maps dirt → RESUME regardless of intent; closer times out at 60 s | none yet | — |

## 5. Why it keeps coming back (evidence-backed)

1. **Each fix closes one refusal class and a new gate opens another.** The dominant failure
   rotated in the logs. In Aug–Sep it was rc124/rc67/rc1 (deaf terminal, wrong pane). In the week
   of 10-12 it was no-registration. Since 10-16 it has been rc70, the fullscreen guard added
   deliberately by `62372906a` and `1211646fb` and kept by ruling e3920969aba9. The ruling itself
   priced it: "blocking it left 3 dead panes over 29 hours". Pane 289's blocker, gate 4, had sat
   latent since `d150099dd` and fired for the first time on 10-24. The closers accumulate
   fail-closed gates, and each one is correct alone but makes the husk the default outcome.
2. **Gates are keyed on different subjects.** Gate 3 asks whether the session meant to end, and
   that is session-scoped. Gate 4 asks whether the cwd is dirty, and that is scoped to the whole
   repo (`cc-pane-close:497` vs `:510-511`). A session in a shared, permanently dirty directory
   (`~/Development/personal`, 138 entries) can never be closed, whatever it declared. Memory
   `gate-composition-two-halves-one-subject.md` names this trap.
3. **Several independent verdict writers disagree, and the paint follows whichever ran last.**
   For pane 289 the in-pane title went DONE → CANTTELL → RESUME within 7 minutes while
   cc-husk-sweep said COLLECTED. Pane 165 changed between DONE and CANTTELL 8 times across 14 paints on 10-23.
   `cc-pane-verdict --recompute` derives the state by substring-matching the closer's latest
   output (`bin/cc-pane-verdict:83-90`). A timeout (rc124, no output) becomes CANTTELL and dirt
   becomes RESUME, even after the session wrote "Good to close: yes".
4. **The closer is slow or hangs and nothing counts that as its own failure class.** 12 of pane
   289's 21 attempts and 25 rows across 6 panes since 10-23 are `rc=124`, "closer exceeded its 60s
   bound" (retry log). Timeouts have recurred since August (close-attrib rc124 08-03, 09-21,
   10-05, 10-22).
5. **Each fix is verified on the incident's panes, not on the population.** The backlog shows 32
   husk ids, every one `done`, yet incidents rose to 13 in the week of 10-19 (close-attrib). Four
   items asked the operator to close panes by hand because agents were refused (f5f9ff77284c,
   4a2e950efe4f, e9b218ff00bf, 3dde5e53312f). There is no standing metric: nothing counts husk
   panes per day, and `husk-sweep.jsonl` logs only resumes (8 rows, all 10-21).
6. **Telemetry moved under the fixes, which hides regressions.** `close-attrib` "closed" volume fell
   from about 120 a week to 2–23 a week after `74baff1ee` moved most closes into `cc-pane-runner`
   (estimated cause). The runner's outcomes are only visible from 10-19 in `pane-say.jsonl`. The
   drainer log is 88% "already paged — held" noise (22875/25949 rows); self-close rows sat held for
   11 days until `85b1d7131`, and `pane-close-drainer.err.log` holds 33 Broken-pipe writes.
7. **Upstream conditions that make husks are still present.** They are stock kitty with the
   fullscreen crash (patched build not confirmed running; decision e3920969aba9's precondition is
   unmet as of 10-24 refused-fs rows), deaf kitty remote control (rc-down+fullscreen 23 rows /
   11 panes), and kitty crashes or restarts that drop registrations (22 no-registration panes on
   10-17/18). The closers treat these as reasons to refuse, so each upstream fault turns into a
   husk instead of a close.
