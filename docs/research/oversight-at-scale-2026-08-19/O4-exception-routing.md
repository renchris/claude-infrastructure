# O4 — THE INTERRUPT PATH: does it work, and does it survive 30 units?

**Date:** 2026-08-19 · **Box:** MacBookPro18,2 M1 Max / Darwin 24.6.0 · **Binary:** CC 2.1.220
(`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`) · **Tree:** `9709c99d3`
**Axis question:** at 30+ units the operator cannot poll — they must be PULLED IN, and only when it
matters. Does our INTERRUPT path work, and does it survive scale?
**Method:** read-only on the live fleet. No pane, session, or process was signalled, torn down, or
typed into. No live `settings.json` / `.claude.json` / `accounts.json` was edited.
**Builds on (not re-derived):** `docs/research/orchestration-units-2026-08-19.md` (`4a3bd3373`).

---

## 1. Verdict

**Our interrupt path is one ambient chime plus a durable mailbox, and both get LOUDER and LESS
informative as units grow — there is no rank anywhere in the system, so at 30 units every interrupt
arrives at exactly the same volume as every other.**

1. The only always-on push is the audio chime, and it is **71% noise by construction** (1,691 of
   2,383 alerts are "a session finished", which needs nothing). It peaked at **235 alerts in one
   hour** at today's ~15 units.
2. The only channel that can reach the operator **away from the desk** — `push-critical.sh` →
   Pushover, wired into 4 hook slots — is **INERT**: `PUSHOVER_TOKEN`/`PUSHOVER_USER` are unset
   everywhere, so it `exit 0`s at line 22 on every fire.
3. The durable side is a landfill: **1,172 / 1,172 escalation records unseen**, **14,941 unacked
   mailbox lines**, and the two mechanisms that would drain them — `escalation-watch.sh` and
   `bin/cc-inbox-guard` — are wired to **zero** hook events and **zero** launchd jobs.
4. **7.8% of permission blocks already wait over an hour** (max 22.6 h), and ~**21.5% of all session
   wall-time** is spent blocked on a human. Both are per-unit rates: they double when units double.
5. **Nothing ranks.** Not one of the eleven channels carries a priority/severity field. The one
   ladder we own (`⛔>📤>🔧>📦>🚀>👤>✅`) is per-session and rendered in that session's own pane.

---

## 2. The channel inventory — trigger · transport · reliability · failure mode

`SEE` = tells state without going to look · `INT` = pulls the operator in · `STOP` = halts/redirects
· `AUD` = reconstructable after the fact. ✅ = does it · ◐ = partial · ✗ = does not.

| # | Channel | Trigger | Transport | SEE/INT/STOP/AUD | Rank? | Measured state today | Failure mode |
|---|---|---|---|---|---|---|---|
| 1 | **Permission prompt** (harness) | tool needs approval | modal in the unit's own pane | ✗/◐/✅/✗ | ✗ | 1,543 events / 20 d; p50 wait **37 s**, p90 **1,696 s**, max **81,411 s** | invisible unless that pane is on screen; **blocks the unit indefinitely** |
| 2 | **`hooks/notify.sh`** (chime) | Notification + PermissionRequest | macOS sound + NotificationCenter | ✗/✅/✗/◐ | ◐ (4 sounds by TYPE, not urgency) | 2,383 alerts / 5.3 d = **18.7/h**, peak **235/h**; **71% `complete`** | fires for work needing nothing; 2 s debounce is per-session so N units = N chimes |
| 3 | **`hooks/push-critical.sh`** (Pushover) | `permission_prompt`, `elicitation_dialog`, `idle_prompt` | phone push, `priority=1` | ✗/✅/✗/✗ | ✅ (the ONLY priority field in the system) | **INERT** — `PUSHOVER_TOKEN`/`USER` unset → `exit 0` | silent: exits 0, logs nothing, indistinguishable from "nothing happened" |
| 4 | **`hooks/cc-permission-beacon.sh`** | `PermissionRequest` | `/tmp/cc-permission-pending/<sid>.json` + durable archive | ✅/✗/✗/✅ | ✗ | live dir **empty** (nothing blocked now); archive **1,543 records** | keyed on **session only** — no agent field, so it names the container, never the sub-unit |
| 5 | **`com.claude.lead-supervisor`** | polls the beacon dir | page → mailbox | ✗/◐/✗/✅ | ✗ | **running** (pid 82511) | its page lands in the mailbox — see #6 |
| 6 | **`bin/cc-notify` + `hooks/mailbox-drain.sh`** | any peer/daemon send | file inbox, drained at SessionStart/UserPromptSubmit/PostToolUse | ◐/◐/✗/✅ | ✗ (flat line format, no class field) | 590 boxes, **17,495 lines, 14,941 unacked** across **309** boxes | reaches the **model**, not the operator; a dead box accepts writes forever |
| 7 | **`hooks/mailbox-wake-arm.sh`** (asyncRewake) | `SessionStart` only | harness synthesises a turn | ✗/✗(agent-facing)/✗/✗ | ✗ | wired on **SessionStart only**; migration `0012` (Stop re-arm) **NOT applied** | watcher is one-shot ⇒ session goes deaf after its first ping until a human types |
| 8 | **`bin/cc-await-ping`** (`--notify-back`) | armed background Bash | polls inbox, exit rides task-completion | ✗/✗(agent-facing)/✗/◐ | ✗ | **467 `WAKE-PATH-DOWN` events / 11 d ≈ 42/day**, 9 today | external group-SIGTERM kills it; **its own loss-notice is written into the mailbox it just stopped watching** |
| 9 | **`hooks/operator-readout.sh`** | Stop, write-turns | `systemMessage` in **that unit's own pane** | ◐/✗/✗/✅ | ✅ but **per-unit only** | renders on demand (`--render`) | pure pull: if the operator is not looking at that pane, it never happened |
| 10 | **`bin/cc-blockers`** | operator runs it | stdout table | ✅/✗/✗/✅ | ◐ (groups by KIND, no cross-kind order) | **16 alarms right now**; `capacity-alarm` FAILING after 6,490 runs | pull-only; renders **infrastructure** state, never "unit N needs you" |
| 11 | **kitty tab bar / statusline** | continuous | terminal chrome | ✅/✗/✗/✗ | ✗ | tab labels carry pane counts (task #147 done) | ambient count, no state; cannot distinguish 30 working from 30 blocked |
| — | **`hooks/escalation-watch.sh`** — the designed "GUARANTEED READER that cannot be dead" | `SessionStart` (per its header) | `additionalContext` | — | — | **registered on ZERO events in all 5 config dirs** | the pull lane for 5 dead-letter stores does not run |
| — | **`bin/cc-inbox-guard`** — the "fail-loud backstop" named in `mailbox-drain.sh` | — | — | — | — | **no launchd plist, no hook, no cron** — every reference is a comment/test/manifest | the backstop under the mailbox does not exist as a running thing |

**Commands behind the cells** (each was run; output is in §2a):

```bash
# hook wiring, per event, live (repeated for all 5 config dirs)
jq -r '.hooks | to_entries[] | "\(.key): \([.value[].hooks[].command] | join(" | "))"' ~/.claude/settings.json
jq -r '.hooks.Notification[] | "matcher=\(.matcher // "*") -> \([.hooks[].command]|join(" ; "))"' ~/.claude/settings.json
for d in ~/.claude ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do \
  jq -r '[.hooks|to_entries[]|select((.value|tostring)|test("escalation-watch"))|.key]|join(",")' $d/settings.json; done

# push-critical inertness, positive-controlled by RUNNING it
/bin/zsh -lc 'echo "${PUSHOVER_TOKEN:+SET}${PUSHOVER_TOKEN:-UNSET}"'          # → UNSET
echo '{"session_id":"probe","message":"probe","cwd":"/tmp"}' | bash hooks/push-critical.sh; echo rc=$?   # → rc=0, no output

# chime rate + composition
L="${TMPDIR%/}/cc-notify/claude-notify.log"
sed -E 's/^([A-Za-z]{3} [0-9]{1,2} [A-Za-z]{3} [0-9]{4}).*/\1/' "$L" | sort | uniq -c
grep -o "for [a-z]*" "$L" | sort | uniq -c | sort -rn
grep "16 Aug 2026" "$L" | grep -oE "[0-9]{2}:[0-9]{2}:[0-9]{2}" | cut -d: -f1 | sort | uniq -c | sort -rn | head -1

# mailbox strand
cd ~/.claude/mailbox && ls *.md | wc -l && cat *.md | wc -l     # 590 boxes / 17,495 lines
#   unacked computed per box as (lines in <k>.md) − (int in <k>.acked); script: scratchpad/…

# escalation landfill
bin/cc-escalations list | tail -n +2 | wc -l                     # 1172
bin/cc-escalations list | tail -n +2 | awk '$NF=="no"' | wc -l   # 1172
grep -h '"tool":"autonomy-sweep"' ~/.claude/autonomy/idl.jsonl | tail -1
#   → new_pages:268 new_alarms:767 new_pushfailed:77 new_handoff_alarms:31 open_decisions:24
```

### 2a. The three numbers that decide the axis

**(a) The ambient channel is 71% noise and already saturates.**

| metric | value | source |
|---|---|---|
| alerts logged | **2,383** over Aug 13 22:45 → Aug 19 06:21 (5.32 d = 127.6 h) | `claude-notify.log` |
| mean rate | **18.7 / h** | 2383 ÷ 127.6 |
| **peak hour** | **235** (Sun Aug 16, 14:00) — one every **15 s** | `grep "16 Aug 2026" … \| cut -d: -f1 \| uniq -c` |
| second peak | 141 (15:00 same day); 120 today at 02:00 | same |
| composition | **1,691 `complete`** (71.0%) · **677 `permission`** (28.4%) · **15 `question`** (0.6%) | `grep -o "for [a-z]*"` |
| distinct sessions chiming | 137 | `grep -o "\[[0-9a-f]\{8\} "` |

`complete` is *"a unit stopped"* — never an action. So the actionable fraction of the only
always-on push channel is **29%**, MEASURED. `hooks/notify.sh:35-53` already suppresses `complete`
for **background team assignees** (`agent_is_assignee`); every pane session still chimes.

**(b) Permission blocks: the operator is FAST when they see it, and absent when they don't.**

`~/.claude/autonomy/permission-archive/*.jsonl`, n = **1,543**, 2026-07-31 → 2026-08-19, fleet-wide
(the archive path is fixed under `$HOME/.claude/autonomy/`, so it spans all 5 config dirs).

| percentile | `waited_s` | in words |
|---|---|---|
| p50 | **37 s** | answered essentially at once |
| p75 | 258 s | 4 min |
| p90 | **1,696 s** | 28 min |
| p95 | 9,190 s | 2.6 h |
| max | **81,411 s** | **22.6 h** |
| mean | 1,810 s | 30 min |

> 600 s: **262** (17.0%) · > 1,800 s: **151** (9.8%) · > 3,600 s: **120 (7.8%)**.
Tool split: `Bash` 1,471 · `AskUserQuestion` 70 · `WebFetch` 1 · `Monitor` 1.
Resolution: `PostToolUse` 1,524 · `SessionEnd` 14 · `Stop` 5.

The distribution is **bimodal, not long-tailed**: a block the operator *sees* is cleared in under a
minute; a block they do not see is cleared in hours or when the session dies. That is exactly the
shape of a channel with no ranking and no remote reach — nothing distinguishes the two cases except
whether a human happened to be looking at that pane.

**(c) The durable side is a landfill, and its two drains are unwired.**

| store | size | unseen | command |
|---|---|---|---|
| mailbox boxes | 590 files / **17,495 lines** | **14,941 unacked** across **309** boxes | per-box `md` lines − `.acked` cursor |
| — top box `D40A5752…` | 9,156 lines | **8,294 unacked**, last write 2026-07-31 | `tail -2` shows `⛔ PERMISSION-PENDING … blocked 1843s` and `⚠️ SUPERVISOR SELF-CHECK` |
| — by kind (unacked) | — | supervisor-death 10,554 · **permission 1,001** · desk-sweep 750 · supervisor-selfcheck 265 · handoff-ping 41 | classifier over unacked lines |
| — still growing | 172 unacked lines since Aug 14; 8 today | — | date histogram |
| `cc-escalations list` | **1,172 rows** | **1,172 (100%) `SEEN=no`** | `bin/cc-escalations list` |
| — by class | announce-alarm 691 · page 275 · push-failed 77 · announce-degrade 76 · handoff-orphan 30 · mail-deadletter 22 · close-failed 1 | oldest 19 d | same |
| `autonomy-sweep` self-report (today 13:04Z) | — | `new_pages:268 new_alarms:767 new_pushfailed:77 new_handoff_alarms:31 open_decisions:24` | `grep '"tool":"autonomy-sweep"' idl.jsonl \| tail -1` |
| `.watching` markers (wake-path liveness claims) | **347** | p50 age **8.2 days**, max 20 d; only 45 fresher than 10 min | `stat -f %m` over `~/.claude/mailbox/*.watching` |

The mailbox is where **every daemon page ends up** — including `⛔ PERMISSION-PENDING — session
af826ffc… blocked 1843s on a permission prompt … Nothing in-session can answer`. That page is
sitting, unread, in a box whose owning pane died on 2026-07-31.

---

## 3. Known breakages — verified at HEAD, today

| Task | Claim | Verdict today | Evidence |
|---|---|---|---|
| **#127** `cc-await-ping` dies exit 144, wake path silently disarms | **OPEN — and the row's own analysis is refuted.** `docs/research/await-ping-exit-144-2026-08-07.md` correctly killed the "25-minute reap" premise (144 = external process-GROUP SIGTERM, not SIGURG, not a harness reap). But the **phenomenon recurs at 42/day.** | **467 `WAKE-PATH-DOWN` lines** in the mailbox, 2026-08-09 → 2026-08-19 (peak 104 on Aug 16; **9 today**). Emitter: `bin/cc-await-ping:525`. Command: `grep -h WAKE-PATH-DOWN ~/.claude/mailbox/*.md \| wc -l` |
| | **The recovery notice travels the broken channel.** `cc-await-ping:525` writes the WAKE-PATH-DOWN line **into the very inbox whose watcher just died** — so the notice that "you are now deaf" is delivered by the mechanism that stopped working. | The line is present in boxes, unacked, alongside the mail it was supposed to announce. (This is the repo's own `recovery-notice-must-not-travel-the-broken-channel` law, re-instantiated.) |
| **#66** `cc-notify` writes the PANE box, the drain reads the SESSION box | **FIXED at HEAD; the task row is STALE.** The 2026-08-09 **COVERAGE FOLD** in `hooks/mailbox-drain.sh:180-200` migrates the own-pane box into the session box at **every** boundary (was SessionStart-only), and the PostToolUse pre-gate spans both key spaces. Read-side by deliberate design ("agreement is not the invariant, COVERAGE is"). | `sed -n '180,200p' hooks/mailbox-drain.sh`; live layer is a symlink into this checkout (`ls -la ~/.claude/hooks/mailbox-drain.sh`), so HEAD **is** live. |
| **#141** kitty mailbox keys reused across restarts | **OPEN, and larger than the row states.** kitty pane ids are small integers and are recycled. **496 of 1,304 mailbox keys (38%) have carried more than one session**; **481 of those are integer keys**. Pane key `48` has carried **68 distinct sessions**; `131` → 39; `700` → 32. **230 of 590 live boxes are integer-keyed.** | `~/.claude/mailbox/.alias/*` trail, counting distinct session ids per key. Mitigated (not closed) by the session-keyed box + tenancy gate in `hooks/lib/mailbox-pending.sh:552-594`; the residual risk is **misdelivery to the new tenant**, not merely loss. |
| **#121** `cc-notify`'s `.forward` chain routes around its own desk-is-down guard | **CONFIRMED FIXED.** `bin/cc-notify:1230-1263` applies the forward chain to the reroute target and emits three distinct honest verdicts — including *"the `desk` role still points at THIS dead address … the triager itself is down"* — rather than claiming a reroute. | `grep -n "reroute" bin/cc-notify` |

### 3a. Two breakages this axis found that are not on any row

| Finding | Evidence | Why it is an interrupt-path defect |
|---|---|---|
| **The remote channel does not exist.** `hooks/push-critical.sh` is registered on `Notification` for `permission_prompt`, `elicitation_dialog` (×2) and `idle_prompt` in **all 5** config dirs — and `PUSHOVER_TOKEN`/`PUSHOVER_USER` are unset in `~/.zshenv`, `~/.zshrc`, `~/.zprofile`, and in a login shell. It exits 0 at line 22-23 on every fire. | positive-controlled by RUNNING it: `echo '{…}' \| bash hooks/push-critical.sh` → `rc=0`, zero output. | It is the **only** channel that reaches the operator away from the machine, and the only one carrying a **priority** field. Its absence means every interrupt requires the human to be at the desk, looking. |
| **The Stop re-arm of the wake path was written, tested, and never applied.** `migrations/0012-mailbox-wake-arm-stop-rearm.sh` exists in-tree with a 21/21 bats suite and a P-W2a–d probe. Its own `migration-verify` fails against the live settings. | `jq -e '[.hooks.Stop[].hooks[]? \| select(.command=="~/.claude/hooks/mailbox-wake-arm.sh")] \| length>=1 and all(.[]; .asyncRewake==true)' ~/.claude/settings.json` → **rc 1**. Only `SessionStart` carries it, in all 5 dirs. | The migration's own header states the consequence: *"the watcher is ONE-SHOT by design… a long-lived session is DEAF from the moment its birth watcher is spent until a human types."* That is the live state. |
| **Both mailbox backstops are unreachable.** `hooks/escalation-watch.sh` (self-described "GUARANTEED READER … the pull lane that cannot be dead") is on **0** hook events in **5/5** config dirs. `bin/cc-inbox-guard` (the "fail-loud backstop" cited by `mailbox-drain.sh`, `session-continue.sh`, `completion-push.sh`) has **no** launchd plist and **no** hook registration — all 10 in-tree references are comments, tests, or manifests. | `grep -c escalation-watch ~/.claude*/settings.json` → 0,0,0,0,0 (control: `grep -c mailbox-drain` → 3). `grep -rl cc-inbox-guard ~/Library/LaunchAgents/` → empty (control: `lead-supervisor` → 1 plist). | The 1,172 unseen escalations are unseen **because nothing is reading them** — not because the operator ignored them. |

---

## 4. Scale behaviour — the interrupt rate at 15 and at 30 units

### 4a. The denominator

Session-hours, computed from first→last timestamp of every transcript touched in the last 8 days,
across all **four** account stores (per `transcript-corpus-spans-four-account-stores`: a one-root
census reads ~26%):

```bash
# scratchpad/sesshours.py — glob ~/.claude{,-secondary,-tertiary,-quaternary}/projects/*/*.jsonl,
# first line with a .timestamp → last line with a .timestamp; 610 parsed, 20 skipped
```

| day | sessions | session-hours | day | sessions | session-hours |
|---|---|---|---|---|---|
| 08-09 | 1 | 11.5 | 08-15 | 39 | 91.9 |
| 08-10 | 4 | 54.4 | 08-16 | 45 | **383.5** |
| 08-11 | 120 | 155.7 | 08-17 | 152 | **482.6** |
| 08-12 | 90 | 166.1 | 08-18 | 44 | 115.8 |
| 08-13 | 28 | 224.2 | 08-19 (partial) | 50 | 20.4 |
| 08-14 | 37 | 119.4 | **Σ 08-09..08-19** | **610** | **1,825.5** |

### 4b. The rate

Permission blocks in the same 11-day window: 61+121+75+150+34+10+28+231+34+18+19 = **781**.

> **0.428 permission interrupts per session-hour** (781 ÷ 1,825.5) — MEASURED, fleet-wide.

| units | permission interrupts / h | one every | audio alerts / h (mean · peak-hour) | blocked units at any instant |
|---|---|---|---|---|
| **15** (fleet median pane count) | **6.4** | 9.4 min | 18.7 · 235 | **3.2** |
| **30** | **12.8** | **4.7 min** | 37.4 · ~470 | **6.5** |
| 50 (observed max, n=517) | 21.4 | 2.8 min | 62 · ~780 | 10.8 |

The "blocked units at any instant" column is the one that matters and it is not a projection — it is
Little's law over two measured quantities: mean `waited_s` = 1,810 s × 0.428 blocks/session-hour =
**774 s of blocked time per session-hour = 21.5% of all unit wall-clock**. At 30 units, **6.5 of them
are, on average, sitting frozen waiting for a human at any given moment**, and 7.8% of those blocks
will last more than an hour.

### 4c. Does the channel still carry information?

Applying the repo's own alarm-polarity law (`alarm-polarity-and-attention-budget`: *count NOT-success,
budget per CLASS, an always-firing alarm says as much as one that cannot fire*):

| | 15 units | 30 units | Usable? |
|---|---|---|---|
| audio alerts / h, mean | 18.7 | 37.4 | **no** — a sound every 96 s that is 71% "nothing to do" |
| audio alerts / h, measured peak | **235** | ~470 | **no** — one every 15 s is a tone, not an alarm |
| actionable share of the audio channel | **29%** | 29% | **no** — the operator cannot tell which 29% without going to look |
| permission interrupts / h | 6.4 | 12.8 | **borderline → no** — 12.8/h needing a *decision* each is a full-time job |
| remote (phone) interrupts / h | **0** | **0** | **no** — the channel is inert; away from the desk the rate is structurally zero |
| durable escalations surfaced / h | **0** | **0** | **no** — 1,172 records, 0 read, both readers unwired |

**The channel has already crossed from signal to stream at 15.** The 235-alert hour is the proof:
the operator cannot have triaged 235 alerts in an hour, so at that point the channel had already
become something to tune out — which is the failure mode the axis brief names as *worse than none*,
because the 8% of blocks that then wait more than an hour are indistinguishable from the 71% that
needed nothing.

---

## 5. Triage — is anything ranked?

**No cross-unit ranking exists anywhere.** Exhaustive, MEASURED:

| Where a rank could live | Present? | Evidence |
|---|---|---|
| `cc-notify` send API | **✗** — no `--priority`/`--urgent`/`--severity` flag | `grep -n '\-\-priority\|--urgent\|--severity' bin/cc-notify` → empty |
| mailbox line format | **✗** — `"<ISO> [<from>] <message>"`, one flat line, no class field | `bin/cc-notify` header § TRANSPORT |
| `mailbox-drain.sh` | **✗** — FIFO with a per-drain cap (`CC_POSTTOOL_DRAIN_MAX_LINES`=20); order is arrival order, "the remainder is deferred" | `hooks/mailbox-drain.sh` header |
| `notify.sh` | **◐** — 4 sounds map to 4 *event types* (`Funk`=permission, `Blow`=question, `Purr`=complete). A type is not an urgency, and there is no queue — sounds overlap and are lost | `sed -n '219,240p' hooks/notify.sh` |
| `push-critical.sh` | **✅ `priority=1`** — the only true priority field in the system — **and it is inert** | §3a |
| `cc-blockers` | **◐** — groups by KIND (land-pipeline, fleet); no ordering *across* kinds, and it renders **infrastructure**, never "unit N needs you". Pull-only. | live run: 1 land alarm + 15 fleet labels; zero rows about a session |
| `operator-readout.sh` / `wrap-ledger.sh` | **✅ a real ladder** `⛔>📤>🔧>📦>🚀>👤>✅` — **but per-session**, rendered as `systemMessage` in that unit's own pane at its own Stop | `hooks/operator-readout.sh` |
| CC's **own** registry `~/.claude*/sessions/<pid>.json` | **✅ ships the field we lack** — `status` ∈ {`idle`,`busy`,`shell`} plus **`waitingFor`** | `jq -c '{pid,name,status,waitingFor}' ~/.claude*/sessions/*.json` → 11 distinct rows, all `busy`/`shell`/`idle`, `waitingFor` absent (nothing blocked at census time) |
| …read by anything of ours? | **✗ — zero consumers of `waitingFor`** | `grep -rIl waitingFor bin/ hooks/ scripts/` → **empty**. Positive control against the minified bundle: `LC_ALL=C strings -a -n 6 …/claude.exe \| grep -c waitingFor` → **5** hits, incl. `topDialogWaitingFor`, `waitingFor:typeof a.waitingFor===`, and `"permission prompt"` ×47. The field is real and the harness writes it; nothing of ours looks. |
| `cc-permission-beacon` record | **✗ no agent field** — keys are `{session_id, ts, tool_name, tool_input, cwd, waited_s, resolved_by}` | `cat *.jsonl \| jq -r 'keys\|join(",")' \| sort -u` → 2 shapes, neither with an agent/unit id |

**The consequence, stated as the axis demands it:** the system has a rank *per unit* (the rung ladder)
and a rank *for infrastructure* (`cc-blockers` kinds), and **nothing that orders one unit against
another**. At 15 units the operator supplies the missing comparator themselves by walking panes. At
30 that is 30 pane-visits per sweep, so the comparator disappears — and undifferentiated interrupts
at that rate are, exactly as the brief says, the same as no interrupts.

A ranking substrate already exists and is unused twice over: the harness's `waitingFor` (zero of our
consumers read it) and Pushover's `priority` (the one carrier is inert). **The hole is not missing
capability; it is missing wiring.**

---

## 6. What I could NOT measure, and why

1. **macOS NotificationCenter coalescing at 30 units.** Whether the OS collapses, drops, or queues
   >200 banners/hour, and how many survive Focus/DND. Measuring it requires *firing* real
   notifications from live sessions — a write to the live fleet, which the method rules forbid. The
   chime-rate numbers above are what `notify.sh` **emitted**; how many the operator **perceived** is
   unmeasured, and is a strictly smaller number.
2. **Whether the operator heard any of it.** Audio output device, volume, Focus mode and headphone
   state are not recorded anywhere. The 2,383 alerts are emissions, not receipts.
3. **Whether a Dynamic Workflow `agent()` can raise an interrupt at all.** The settled research
   (`orchestration-units-2026-08-19.md`) measured 9 Workflow agents minting **0** `agent-tool` ledger
   rows. Deciding whether one of them hitting a permission prompt reaches `PermissionRequest` would
   require **running** a workflow that trips a gate — a live spawn, out of scope for a read-only
   axis. What IS measured: the beacon record carries **no agent field**, so even if the event fires,
   the record names the pane session, not the sub-unit. At 30 units of which the majority are
   paneless, that is a rank-and-locate failure regardless of the answer.
4. **The sender of the `WAKE-PATH-DOWN` SIGTERMs.** 467 events, no surviving `si_pid`. The recorder
   recipe in `await-ping-exit-144-2026-08-07.md` §2 would name it, but it must be armed *before* the
   next kill. Correlating against `cc-reaper`/recycle timestamps was not attempted here.
5. **Per-day interrupt rates are noisy by construction.** Session-hours are attributed to a session's
   **start** day while permission events are dated at occurrence, so a long session started Sunday
   inflates Sunday and deflates Monday. Only the **11-day aggregate** (0.428/session-hour) is used
   for any conclusion.
6. **`hooks/notify.sh`'s log rotates** — it begins Aug 13 22:45, so the chime series is 5.3 days, not
   the 20 days the permission archive covers. Rates are computed against the shorter window.

---

## 7. The design constraint this axis imposes

> **For 30 units to be overseeable by one person, the interrupt path must satisfy five properties.
> Our path currently satisfies zero of them.**

**C1 — RANKED AT THE SOURCE, on a scale with a fixed budget.** Every interrupt must carry a class
that says *how long it may wait* (now / this hour / this day / never), and the classes must be
budgeted per hour, not per unit — otherwise the volume is a linear function of fan-out and the
operator's attention is not. Concretely: a `--class` on `cc-notify`, a class field in the mailbox
line, and a consumer of the harness's own `waitingFor` (which is free — the harness already writes
it, and `grep -rIl waitingFor bin/ hooks/ scripts/` returns nothing).
*Today:* the only priority field in the system belongs to the one inert channel.

**C2 — ONE QUEUE, NOT ELEVEN CHANNELS.** The operator must have exactly one place that answers
*"which unit needs me next?"*, ordered, with the top item nameable in one line. Eleven channels with
no common ordering is the same as no channel, and it is why 1,172 escalations can be 100% unseen
while a chime fires every 96 seconds.
*Today:* `cc-blockers` is the closest thing and it renders infrastructure, not units.

**C3 — THE CHANNEL MUST BE ABLE TO STAY SILENT.** Suppression must be the default and speech the
exception, with the actionable fraction as the design target, not a byproduct. `escalation-watch.sh`
already states the correct law in its own header — *"ZERO unseen records ⇒ ZERO output. That is the
contract, not an optimisation"* — and it is registered on zero events. A channel that is 71% "a unit
finished" trains the operator to ignore the 29% that is "a unit is frozen".
*Today:* the always-on channel fires for the state that requires nothing.

**C4 — REACH MUST NOT DEPEND ON THE OPERATOR'S POSTURE.** At 30 units, "the operator is looking at
that pane" is a 1-in-30 event. Every interrupt above the lowest class must have a transport that
works when nobody is at the machine — and it must **fail loudly**, not `exit 0`. A break-through
channel that is silently inert is strictly worse than no channel, because the whole design was built
assuming it works.
*Today:* `push-critical.sh` is wired into 4 slots and returns rc 0 with no output, forever.

**C5 — NO INTERRUPT PATH MAY DEPEND ON THE THING IT REPORTS ON.** Three live instances: the wake-path
loss notice is written into the inbox whose watcher just died (467×); the supervisor's
`PERMISSION-PENDING` page is delivered by mailbox into a box whose pane is dead (8,294 lines); the
"guaranteed reader" for the dead-letter stores is itself unregistered. Every one of these is the same
error — the recovery channel is a subset of the broken one — and each converts a *loud* failure into
a *silent* one.
*Today:* three of our five durable paths have this shape.

**Corollary — the cheapest correct move is wiring, not building.** Two of the five properties are one
config change each: apply `migrations/0012` (C5, the Stop re-arm that is already written and tested),
export the two Pushover variables (C4, the only priority carrier we own), and register
`escalation-watch.sh` on `SessionStart` (C3, the pull lane whose contract is already right). The two
that need real design are C1 (a class on every send) and C2 (one ordered queue) — and C1's substrate
already exists in the harness's `waitingFor`, which nothing of ours has ever read.
