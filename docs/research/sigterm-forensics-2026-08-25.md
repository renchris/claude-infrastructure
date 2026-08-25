# SIGTERM forensics — who killed pid 50399, and why nothing said so

**Date:** 2026-08-25 · **Repo:** `claude-infrastructure` · **Incident brief:** `reso-web-app/docs/research/RECYCLE_SIGTERM_INCIDENT_2026-08-25.md` (bba4977, local-only, read-only to this session)

## Verdict, in one line each

| # | Question | Answer |
|---|---|---|
| 1 | Who SIGTERM'd pid 50399 at 21:42:25Z? | **NOT DETERMINABLE, and provably so** — no store on this box records signal provenance. Exhaustion list below. |
| 1b | Who SIGTERM'd pid 1522 at 21:28:26Z? | **NAMED, with a first-person confession**: session `8b247f6d` ran `pkill -f "cc-await-ping"`. |
| 2 | Why was the death silent? | The alert path is gated on the dead lead owning a **team**. A Dynamic Workflow is not a team. Fixed. |
| 3 | Did pane 30's shell never appear, or did the detector miss it? | **The detector missed it.** The shell appeared at 21:37:13Z; the watcher gave up at 21:46:16Z. |
| 4 | The two `fire-cv-tooling` custody debts | Pane 48 **abandoned** (its peer was killed 18 s after birth). Pane 49 **stays open** — it is alive and working. |

## The brief's central premise is refuted: there was no death cluster

The brief reasoned from *"three session deaths in seven minutes is one cause, not three."* Two of the three were not deaths.

| Session | Logged as | What the transcript actually shows |
|---|---|---|
| `7404858f` 21:35:37Z | `CRASH / abrupt-unknown` | **A clean operator close.** The operator typed *"Good to close or no?"* at 21:34:38; it answered *"✅ Good to close"* at 21:35:13; 12 Stop hooks completed at 21:35:21; `sessions.log` records `reason=prompt_input_exit`. |
| `af5b3de0` 21:37:30Z | `CRASH / abrupt-unknown` | **Its own `--recycle` typed `/exit` into it.** Final transcript records are `<command-name>/exit</command-name>` → `Goodbye!` at 21:37:12.760. `sessions.log`: `reason=prompt_input_exit`. |
| `d075006b` 21:42:25Z | `CRASH / external-sigterm` | **Genuine.** Committed `2b970b9` at 21:42:01, last `tool_result` 21:42:14.687, subagents still running. Killed healthy and mid-work. |

**Why two clean exits were logged as crashes** — and this is a real bug, not a labelling quibble. `lead-crash-watchdog.sh` absolves a death by looking up a teardown marker **by sid**. Pane 30's marker was written with an empty one:

```json
{"key_kind":"pane","pane":"30","sid":"","mode":"recycle","ts":"2026-08-25T21:36:06Z"}
```

`cc_sid_for_pane` returned empty (the matching `handoffs.jsonl` row already says `"basis":"unresolved"`), so the lookup misses and the classifier falls to its `unsure ⇒ CRASH` bias. The two teardowns in the same window that *did* write sid-keyed twins (panes 25, 47) were both classified `RECYCLE / clean-exit` correctly. So `abrupt-unknown` here means *"the marker was unreadable"*, not *"the session died abruptly"* — a lookup miss rendered as a finding (MEMORY.md `lookup-miss-is-not-absence`).

**Consequence for the investigation:** there is exactly ONE unexplained death, not three. Any theory built to explain a cluster was explaining noise.

## Deliverable 1a — the 21:28:26Z kill is NAMED (a fourth death the brief did not have)

`external-sigterm` has occurred **exactly twice in the entire history** of `claude-crashes.jsonl`, both on 2026-08-25. The brief had the second. The first is fully solved:

```
21:28:08Z  handoffs.jsonl   self-retire-peer pane=48        ← fire-cv-tooling armed
21:27:56Z  close-record     pid 1522 starts
21:28:23Z  bash-execution   [8b247f6d] pkill -f "cc-await-ping" 2>/dev/null; ...
21:28:26Z  close-record     pid 1522 ends — exit 143, signal 15
```

The perpetrator wrote it down itself, 77 seconds later, in its own transcript:

> *"Confirmed — I killed the session I'd just fired. `pkill -f "cc-await-ping"` matched the CV session's argv, because `--notify-back` appends a back-channel trailer containing that string."*

**The mechanism, verified live rather than inferred.** `pkill -f` matches the whole command line, and a *fired* session carries its entire brief in argv. Measured on this box during this investigation:

```
pid=4774  comm=…/node_modules/.bin/claude  argvlen=5921  contains "cc-await-ping": YES
```

Live `claude` processes fall into two populations: **fired peers** (argv 5.9–9.8 KB, the whole brief, matching `cc-await-ping` because the standard back-channel trailer contains that literal string) and **recycled/plain panes** (argv 132–181 B, flags only). `pkill -f "cc-await-ping"` selects the entire fired-peer fleet.

This also closes an open backlog row filed three minutes later under `wake-path-sigterm`, which recorded an unattributable `si_pid=13097` that *"binds to no session beat."* That pid is this `pkill`.

**Why it cannot explain 21:42:25Z**: `d075006b` was a *recycled* pane, so its argv was the 132–181 B form. No brief-text pattern can reach it. The two kills are genuinely different events.

## Deliverable 1b — 21:42:25Z: NOT DETERMINABLE, and here is what was exhausted

**The single most important correction to the brief.** The brief reads `ppid 50321` as *"the launching zsh."* It is not. `bin/cc-close-attrib` runs the binary as a backgrounded `exec`'d brace-group and installs:

```bash
177: _forward() { [[ -n "$child" ]] && kill -"$1" "$child" 2>/dev/null || true; }
179: trap '_forward TERM' TERM
```

So `pid` in the close record is the claude child and `ppid` is **the wrapper itself** (`$$`). The wrapper forwards TERM to claude and stays alive to reap and record. That single fact explains every observed symptom at once — claude exits 143, the close record still gets written, the pane's zsh is untouched, no pane close — and it **redirects the entire search**: the process that had to be *selected* was a `bash` running `cc-close-attrib`, not a `claude`. Every classifier on this box that selects on `^bash$` therefore has a path to a live session.

It is also **attribution-silent by construction**: the record names the victim and can never name the sender.

### Exhaustion list

| Candidate | Excluded by |
|---|---|
| `cc-reaper` garbage sweep | Its own log. Sweeps ran 21:18:48Z and 21:57:35Z; the `garbage:` arm ran 21:19:10–21:19:18 and again 21:57:48. **No line in the window.** Independently: its kill-time re-check requires `ucomm` to match `^bash$`/`^zsh$`, which a `claude` cannot. *(The brief exonerated it from the wrong counter — `sweep end: … 0 reaped` is the session arm; `garbage: N TERMed` is a separate one that does kill.)* |
| `bin/cc-teardown` | Never invoked on 2026-08-25. Newest decision record is `20260825T122551Z`. Also would have closed the pane; the pane stayed open. |
| `scripts/gate-cleanup.sh:188` | Last real invocation 04:02Z. Also `never_signal` (`:119`) excludes any command line containing `/node_modules/.bin/claude`, which covers both the binary and the wrapper. |
| `scripts/capacity-ramp.sh:170` | **Never invoked all day** (only this session's own reads appear in `bash-execution.log`), and its pidfile `/tmp/cc-ramp-pids.txt` does not exist. |
| `handoff-fire.sh` | Never signals a claude. It types `/exit` (⇒ exit 0, not 143) and kills only its own detached watcher, seconds after arming — no pid-reuse window. |
| A pattern or process-group kill | Exit **143** is a signal to the process alone; `cc-await-ping:606` records that a group TERM measures **144** here. And there were **no co-victims**: 50399 is the only claude entering an exit handler in 21:42:20–35, unlike the 21:28 `pkill`, which took three watchers with it. |
| Any agent Bash-tool kill | `bash-execution.log` and `bash-commands.log` 21:40–21:43 contain no `kill`/`pkill`/`teardown`/`gate-cleanup` from any session. |
| Memory / jetsam | `mem_free_pct 90`, headroom 28–34 GB, `swap_used_mb 0.00`, compressor at 0.55 % of limit, **zero jetsam kills in 2.9 M unified-log lines**. macOS pressure sends SIGKILL (9) regardless. |
| An operator keystroke | `cc-beats` last `operatorT` = 21:39:31, before the `/goal` was armed. |
| A pane close | `cc-close-attrib` forwards HUP as 129; the record says 143. |
| A scheduled job | The 113 s / 295 s gaps are between *watchdog detection* stamps; detection lag is 7/17/25 s, so true gaps are 103 s and 312 s. `browser-spin-guard.log` stamps the 300 s family's real phase (21:28:03, 21:33:06, 21:38:07, 21:43:07) — deaths land at +23/+144/+186/+258 s, no alignment. `com.claude.team-orphan-reaper` and `com.claude.desk-invariant` are **not loaded**. `lead-supervisor` reaps by writing a ledger row, never by signalling. |
| The macOS unified log | Logs no `kill()` syscall. 2.9 M lines swept for the window; nothing names 50399 or 50321 as a signal target. |

### Why no store could have held the answer

Signal provenance on macOS is available **only inside the receiving process, at delivery**, via `siginfo_t.si_pid` — and it is gone the instant the handler returns. Two consequences:

1. `cc-close-attrib` already has a TERM handler (`_forward`) and it is the one place `si_pid` was in scope. It does not read it. **That is the missing store**, and it is exactly why the 21:28 sender IS known: `cc-await-ping` captures `si_pid` in its handler, which is how `si_pid=13097` got recorded at all.
2. `cc-close-attrib:160` hardcodes `BIN_ARGV` to **the first 3 elements**, so both victims recorded an innocent-looking `["…/claude","--permission-mode","auto"]` while omitting the very trailer that `pkill -f` matches. The record that exists to attribute a death discards the field that identifies its victim class.

**The honest verdict: the sender of the 21:42:25Z SIGTERM cannot be recovered after the fact, by anyone, from what this box stored.** The next occurrence is recoverable only if the capture is added at kill time.

### One live defect found while excluding cc-reaper (real, unfired here)

`_gs_verify_kill` (`bin/cc-reaper:555-575`) re-identifies a candidate by comparing a **120-character argv prefix**. For the `stuck-wrapper` class — which targets `cc-close-attrib` **by name** (`:649`) — that prefix is byte-identical across every wrapper on the box, so the check cannot distinguish a dead session's wrapper from a live one that inherited its pid. The 2026-08-16 comment above it says the `ucomm` re-check was "a tautology" for `^bash$` classes; the argv signature that replaced it is a tautology for this class too. Not the cause here (the arm did not run in the window), but the same shape as the "SIGTERM-143 land bleed" that comment was written about. **Filed, not fixed — out of this session's frozen scope.**

## Deliverable 2 — an external death now reaches the operator

**What was wrong.** The watchdog had the correct verdict — `class=CRASH cause=external-sigterm` — 25 s after the kill. Two reasons it went nowhere:

1. The only alert on the path is an `osascript display notification`: transient, dismissed by the next one, carrying 8 characters of sid and nothing about what was lost.
2. Everything louder — `CRASH_REPORT.md`, `shutdown_request`s, the `/dev/tty` bell — sits behind a scan for **team configs naming this session as lead**. A Dynamic Workflow's agents are in-process subagents and own no team config, so the lead took the `no teams affected` early return. **The loudest case on the box was structurally unreachable.**

And a SIGTERM'd `claude` leaves its parent shell alive, so the pane renders *exactly* like a deliberate `/exit` — same `Resume this session with:` line, same prompt. There is no pixel on screen that distinguishes the two.

**The fix** (`hooks/lead-crash-watchdog.sh`): `surface_death()`, called **above the team scan**, pages a live sibling through `cc-notify --role` — the fleet's own durable transport (an inbox line survives until read; `--role` re-resolves at send time so a recycled pane is followed). Polarity is CRASH-only: recycles are 28 of 32 rows on the incident day, and paging those would train the operator to ignore the channel. Bounded, fail-open, kill-switchable (`CC_DEATH_PAGE=0`), stubbed in tests via `CC_DEATH_PAGER`.

**Replayed against the real incident transcript:**

```
SESSION DEATH — d075006b-c432-4e11-83e9-c9e22f1c442d was KILLED by an external SIGTERM
(exit 143, signal 15) — it did NOT exit. Lost: /goal=live, in-flight workflow dir(s)=1.
Its pane is still open at a live shell and looks EXACTLY like a clean /exit, so nothing on
screen says this happened. Evidence: ~/.claude/logs/claude-crashes.jsonl (pid 50399)
+ ~/.claude/logs/close-records/50399-*.json
```

`/goal=live` and `workflow dir(s)=1` are read from the real transcript and the real `wf_123589b7-7fa` — not fixtures.

One subtlety worth keeping: `goal-state.sh` returns rc 1 for *both* "unreadable" and "never armed a goal". The page separates them itself (a readable transcript with no `goal_status` record is the positive finding `none`), so an abstention is never laundered into a finding. The state vocabulary is read out of the lib (`goal-state.sh:99` — `failed`/`cleared`/`live`); guessing it cost one red test, because the obvious spelling for an achieved goal is `met` and the lib emits `cleared`.

**Tests:** `tests/lead-crash-surface.bats`, 12/12, including a red-proof control that executes `git show HEAD:hooks/lead-crash-watchdog.sh` and asserts the pre-fix file cannot page.

## Deliverable 3 — `recycle-dead`: the detector failed, and it should escalate

**The question the brief asked has a definite answer, and it is not the one the log implies.**

Pane 30's session was `af5b3de0` (bound three ways: `teardown/30.json` `mode:recycle` at 21:36:06Z; the `history.jsonl` submission below carries `sessionId af5b3de0`; `handoffs.jsonl` `recycle-intent target_pane=30` at 21:36:05Z). Its `/exit` was submitted **corrupted** — a kitty shell-probe token was prepended to the payload:

```json
{"display": ": ktv-74927-1-26859; /exit", "timestamp": 1787693767554,
 "sessionId": "af5b3de0-c30a-43fe-b7e5-b99b64bd5591"}      ← 21:36:07Z
```

A clean retry landed 65 s later and the session exited normally: `sessions.log` records `Session ended sid=af5b3de0 reason=prompt_input_exit` at **21:37:13Z**.

**So a shell existed in pane 30 from 21:37:13Z.** The watcher declared `never reached a confirmed shell in 600s (verdict: unknown)` at **21:46:16Z** — nine minutes later. The shell was there; the detector never saw it.

**Why.** `pane_cc_state` (`handoff-fire.sh:2861-2905`) returns one of `cc` / `shell` / `unknown`, and `unknown` comes from **seven** branches — `:2863, 2874, 2884, 2890, 2892, 2898, 2903`. Every one means *"this pane could not be READ"*; not one means *"there is no shell here."* `:2898` is the widest: **any** process in the pane's foreground process group whose `comm` is not in the shell whitelist forces `unknown`. So the ledger's `unknown` cannot, by construction, distinguish "no shell appeared" from "a shell appeared and I could not certify it" — and the watcher's own message, *"never reached a confirmed shell"*, states the weaker fact correctly while reading as the stronger one.

**Ruling: yes, it must escalate — and the case is stronger than "it was silent", because its two siblings were not.** `recycle-dead` is emitted from **three** sites, and only one of them was quiet:

| Site | Condition | Pre-fix behaviour |
|---|---|---|
| `:5513` | relaunch write failed twice | ledger row + `hf_alarm recycle-relaunch-failed` |
| `:5591` | relaunched but never engaged | ledger row + `goal_unreachable` + `hf_alarm recycle-dead` |
| **`:5483`** | **never reached a confirmed shell** | **ledger row ONLY** |

`:5483` is the site pane 30 hit, and it is the one where the pane ends up holding **no claude at all** — the `/exit` has landed, the predecessor is gone, and the relaunch was never typed. The quietest arm was the one with the worst outcome.

*(This corrects a claim I made mid-investigation and had to retract: "recycle-dead only emitted a ledger row" is false for the class — two of three sites already escalated. It cost a vacuous test: a red-proof control keyed on `hf_alarm recycle-dead` **skipped as "HEAD already carries the fix"**, because `:5591` already contains that exact string. The control's span was the whole file while its subject was one arm of it, so a sibling's fix silently certified this one. The control now keys on `:5483`'s own wording and additionally drives the pre-fix file to its terminal refusal to prove the alarm store stays empty.)*

**Shipped** (`scripts/handoff-fire.sh:5483`): `hf_alarm recycle-dead …` naming the consequence, the manual relaunch command, and — when the verdict is `unknown` — labelling it explicitly as *an abstention, not a finding*. The refusal itself is unchanged and stays fail-safe: typing a relaunch onto a pane that might still hold a live session is the one outcome worse than a stranded pane. A `HF_RECYCLE_SHELL_WAIT_S` seam (default **600**, unchanged) makes the terminal arm executable in a test; it can only make the watcher give up sooner, never type onto an unconfirmed pane.

**Tests:** `tests/handoff-recycle-dead-escalates.bats`, 7/7 (6 pass + 1 correctly-skipped control).

**Two adjacent bugs found here, filed not fixed** (both outside the frozen scope, both with a named owner):
- The kitty shell-probe token leaking into a submitted composer payload — same family as the two `goal-arm verdict:"mangled"` records at 21:30:18 and 21:31:31.
- `cc_sid_for_pane` returning empty for pane 30, which is what made two clean exits classify as crashes.

## Deliverable 4 — custody

| Pane | Disposition | Why |
|---|---|---|
| **48** | `abandon` | Its peer (pid 1522) was killed by the `pkill -f "cc-await-ping"` **18 s after birth** and did no work. The fire was superseded by the re-fire onto pane 49 at 21:30:16Z. There is nothing to collect; the debt can never be returned. |
| **49** | **stays open** | The session is **alive and working** — `cv-tooling-49`, claude-quaternary, 43 m at time of check, pid 4774 in state `S+`. A `return` would assert a collection that has not happened and a `abandon` would assert a supersession that has not happened. *Awaiting ARMED is the legitimate non-close state.* |

Note for whoever holds this: pane 49's debt was opened by `d075006b`, which is dead — so **the creditor no longer exists**. The peer's self-close will attempt to discharge into a session that is gone.

## What this session did NOT do

- Did not fix `cc-close-attrib`'s missing `si_pid` capture — that is the one change that would make the next occurrence solvable, and it is the top recommendation below, but it is a new mechanism outside the frozen scope.
- Did not fix `cc-reaper`'s 120-char argv signature, the kitty probe-token leak, or `cc_sid_for_pane`.
- Did not touch `reso-web-app` (read-only), and killed, closed or recycled no pane.

## The one recommendation

**Capture `si_pid` in `cc-close-attrib`'s `_forward()` TERM trap and write it into the close record.** It is ~3 lines, it is the only place the fact is ever in scope, and it converts this class of incident from unsolvable-after-the-fact to solved-at-the-time. The 21:28 kill is named today for exactly one reason: `cc-await-ping` already does this.
