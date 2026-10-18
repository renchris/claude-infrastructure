# A6 — Claude Code harness mechanics for SessionStart (2026-10-18)

Axis A6 of the 9-axis startup-hooks study. Read-only. No hook was executed. Sources: the official
docs (fetched today as markdown), the CHANGELOG 2.1.100 → 2.1.302, a read-only `strings` read of
the 2.1.293 binary the fleet runs, and the 411 main transcripts from the last 2 days.

## 0. Verdict

1. **On 2.1.293 the harness hides a timed-out SessionStart hook from both the operator and the
   model.** The terminal renderer draws a `hook_cancelled` row **only for `UserPromptSubmit`**
   (`if(l.hookEvent!=="UserPromptSubmit"||!l.timedOut){return null}`). The model-context mapper
   maps `hook_cancelled` to `[]`. So the 2026-10-18 05:49Z incident was silent because the harness
   is built that way, not because of a misconfiguration. Nothing in the CHANGELOG up to 2.1.302
   adds a SessionStart timeout notice: 2.1.280 improved it for UserPromptSubmit only. **Making
   these timeouts loud has to be our own code.** The two channels that can do it at zero tokens
   are a sync top-level `systemMessage` (only while the hook is still alive) and the statusline,
   which renders all the time and costs 0 tokens.
2. **Latency: the first model response waits for the slowest sync SessionStart hook. All sync
   hooks run in parallel, so the wait is the max of their spans, not the sum.** Measured over 383
   sessions: none got its first assistant record before the startup hook batch finished. In 366
   of 383 (96%) the prompt arrived at launch (agent-spawned sessions), so the batch span is
   added directly to time-to-first-token: p50 5.6 s, p90 9.7 s, max 23.1 s. The dispatcher is the
   critical path in almost every batch. The harness has no setting that makes a sync hook
   non-blocking. You can only shorten the critical path, or move output that only the operator
   reads to a surface that does not block.
3. **A sync hook whose timeout is shorter than a sibling's buys no latency, only drops.**
   35 of 53 cancellations of dod-persist, mailbox-drain and desk-brief-inject happened while the
   batch was still running, a median of 3.0 s longer (p90 5.0 s). The session waited anyway, and
   the output was thrown away.
4. **Token channels as the binary implements them:** sync top-level `systemMessage` costs 0 model
   tokens and renders as `SessionStart:startup says: …`. `additionalContext` is billed. A
   SessionStart hook that prints JSON records `hook_success.content=""`, so it is not billed twice.
   An async hook's `systemMessage` and `additionalContext` become hidden model content on the next
   turn. An async hook's **stderr goes nowhere**: 57 of 57 SessionStart async responses in 2 days
   carried only stderr, and none of it reached the operator or the model.
5. **The brief's version premise is wrong.** The fleet runs **2.1.293**, not 2.1.183: 372 of 409
   transcripts that carry a version are on 2.1.293, 34 on 2.1.291, 2 on 2.1.296, 1 on 2.1.284.
   37 live processes run `~/.claude-293/node_modules/.bin/claude`. The current docs describe
   2.1.302, so every feature below is checked against 293.

## 1. Method

| Step | Command (read-only) |
|---|---|
| Docs | `curl -sL https://code.claude.com/docs/en/hooks.md` (273,668 B), `/hooks-guide.md`, `/statusline.md`, `/plugins/mods/{reference,overview,events}.md` → `/tmp/a6-dl/` |
| CHANGELOG | `curl -sL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` (top entry 2.1.302); awk-tagged each line with its version and kept the hook-related lines from 2.1.100 on |
| Binary | `strings -n 8 ~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe > /tmp/a6-dl/cc293.strings`, then `rg -o` on attachment-render and model-normalisation code |
| Fleet version | `jq -r 'select(.version)\|.version'` on the first 30 lines of each census transcript; `ps -axo command` |
| Census | `python3 -I docs/research/startup-hooks-2026-10-18/a6_census.py /tmp/startup-hooks-census-files.txt` |
| First-turn wait | `python3 -I docs/research/startup-hooks-2026-10-18/a6_firstturn.py /tmp/startup-hooks-census-files.txt`, plus an inline variant (§2 row 4b) |
| Incident | `jq` on `~/.claude-quaternary/projects/…/5759497b-….jsonl` |

Known bias, inherited from the brief: `hook_success` with `durationMs` is recorded only when a hook
prints. Every sync hook in our SessionStart set prints JSON on most runs (404 of 410 dispatcher runs
have a record), so the startup batch end is well observed.

## 2. Measurements

| # | Quantity | Value | Tag / command |
|---|---|---|---|
| 1 | Fleet CC version | 2.1.293 (372/409), 2.1.291 (34), 2.1.296 (2), 2.1.284 (1) | [M] version tally loop above |
| 2 | Are the sync SessionStart hooks parallel? Spread of inferred start times (ts − durationMs) within one batch | p50 2 ms, p90 39 ms, max 810 ms over 403 batches | [M] a6_census.py §2 |
| 2b | Incident: start of dod-persist, mailbox-drain and the dispatcher | all 05:49:48.158–.159Z (ends 56.481 − 8.323, 58.210 − 10.051, 01.703 − 13.544) | [M] jq on the incident transcript |
| 3 | Does the first response wait for the batch? | 0 of 383 sessions had an assistant record before the startup batch ended. In 94 the user record came first (prompt typed or queued early), and the assistant still came 1.16 s (min) / 4.2 s (median) after the batch ended | [M] a6_firstturn.py + inline check |
| 4 | Prompt supplied at or near launch (first prompt < 30 s after the batch started) | 366/383 (96%). Gap from batch end to prompt record: p50 0.043 s, p90 0.507 s | [M] a6_firstturn.py |
| 4b | Startup batch span for those sessions = added first-turn latency | p50 5.58 s, p90 9.72 s, max 23.14 s | [M] a6_firstturn.py |
| 5 | Dispatcher durationMs by source | startup n=382 p50 5.5 s, p90 9.7 s, max 21.7 s · resume n=27 p50 7.1 s, p90 9.3 s · clear n=1 6.0 s | [M] inline python (sibling-slack script) |
| 6 | SessionStart `hook_cancelled`, 2 days | mailbox-drain 34, dod-persist 18, dispatcher 6, desk-brief-inject 1, setup-task-symlinks 1, foreign project hooks 4. By source: startup 62, resume 1, fork 1 | [M] a6_census.py §1 |
| 7 | Cancel overshoot (durationMs − timeoutMs) | mailbox-drain p50 0.59 s, p90 5.05 s, max 9.4 s · dod-persist p50 1.88 s, p90 9.41 s, max 25.2 s · dispatcher p50 1.54 s, p90 3.87 s, max 9.7 s | [M] a6_census.py §1 |
| 8 | Sibling cancellations (dod/mailbox/desk) while the batch was still running | 35/53. Slack from cancel to batch end: p50 3.03 s, p90 5.01 s, max 6.19 s | [M] inline python |
| 9 | SessionStart `async_hook_response` | 57 total, 57 with stderr, 0 with a non-empty `response`, 0 non-zero exit. Top stderr: pre-session-validate "2.1.114 failed --version check" ×24; session-register "line 614 … Killed: 9" ×7+ | [M] a6_census.py §3 |
| 10 | SessionStart additionalContext | 409 records, mean 3,657 chars, p50 2,467, max 9,473 per record. Largest single hook part 5,936 (no part reached the 10,000 cap or the dispatcher's 9,500 cap) | [M] a6_census.py §5; jq part-length loop |
| 11 | SessionStart systemMessage | 429 records, mean 2,170 chars, max 2,854 | [M] a6_census.py §5 |
| 12 | Our SessionStart hooks billed through `hook_success.content` (plain-text stdout) | 0. Every own hook prints JSON (content ""). Only foreign project hooks print plain text | [M] jq tally over the census |
| 13 | Hooks that read `.source` (startup/resume/clear/compact/fork) | 1 of 13 (accounts-board.sh). None of the other 12 tailor their output by source | [M] `rg -c` over hooks/*.sh |
| 14 | SessionStart sources seen | startup ~392, resume ~36, fork 1, clear 1, compact 0 | [M] a6_census.py §5 (batches with a systemMessage) |

[E] Token estimate: 3,657 chars ≈ 914 tokens per start (chars ÷ 4). It is billed again on every
resume, because that context is still in the transcript and gets added once more.

## 3. Harness facts, question by question

### Q1. Do hooks in one event run in parallel? **Yes.**
- Docs: "All matching hooks run in parallel. If you define the same handler in more than one
  settings file, it runs once." (hooks.md, Common fields preamble).
- Measured [§2 rows 2, 2b]: all four matcher-less groups start within ms of each other. A group is
  only a settings container, not a sequence. The five config dirs symlink to one settings.json, so
  deduplication is moot here.
- Consequence: the first-turn wait is the max of the sync hook spans. Splitting or merging sync
  hooks changes how failures look, not latency. Only shortening the slowest one changes latency.

### Q2. Does session start wait for sync SessionStart hooks? **The prompt box no; the first response yes.**
- Docs (hooks.md, SessionStart): "SessionStart hooks run in the background. You can type right away,
  and a conversation you resumed appears without waiting for the hooks. Claude's first response still
  waits for the hooks to finish, so their context reaches Claude." Also: "a prompt you send while
  SessionStart hooks are still running doesn't reach Claude until they finish… press `Esc` to take
  the prompt back."
- CHANGELOG: 2.1.47 "deferring SessionStart hook execution, reducing time-to-interactive by ~500ms";
  2.1.268 "`--continue` / `--resume`: the conversation appears immediately instead of waiting for
  SessionStart hooks"; 2.1.271 "the spinner says so with elapsed time, and Esc cancels a prompt
  waiting on a SessionStart hook". All of these are in 2.1.293. The binary has the spinner string
  `"Running SessionStart hooks…"`.
- Measured [§2 rows 3–4b]: 0 of 383 first responses came before the batch ended. 96% of sessions
  get their prompt at launch, so for nearly every session the batch span is the time-to-first-token
  penalty.
- `/clear` runs SessionStart hooks in the background. The binary passes them through a deferred
  `b((e)=>JY(o,"clear",…))`. Docs: "If you run `/clear` or switch to another conversation while
  background hooks are still running, nothing they return applies to the session." This is a
  harness-level silent drop (D9). Its frequency is low: 1 clear in 2 days.
- Prior art agrees: `docs/research/startup-2026-08-16/measure-sessionstart-hooks.md:30` ("BLOCK the
  first API dispatch", `sleep 25` → +22.5 s) and `:148` (an asyncRewake hook costs 0 ms on the
  critical path).

### Q3. What happens on timeout? **Cancelled, output discarded, and invisible on SessionStart.**
- Docs (hooks.md, Timeouts): "Claude Code cancels a `command`, `http`, or `mcp_tool` hook that
  reaches its timeout, discarding the hook's output." No SessionStart notice is documented. The
  only timeout notices in the docs are the `onFailure: "block"` one and the UserPromptSubmit one.
- Binary, 2.1.293. Render branch:
  `case"hook_cancelled":{if(l.hookEvent!=="UserPromptSubmit"||!l.timedOut){return null} … " timed out" … " — output discarded. Raise the hook's \"timeout\" to allow more time."`
  The model mapper table includes `hook_cancelled:()=>[]`, `hook_non_blocking_error:()=>[]`,
  `hook_system_message:()=>[]`. **Result: a SessionStart timeout leaves a transcript record and,
  only under `--debug`, a debug line (`Hook ${name} [${cmd}] timed out after ${ms}ms`). Nothing
  else.**
- Partial stdout does not survive. Printing early and then being killed still loses everything
  ("discarding the hook's output"). The only way to keep output is to exit before the timeout.
- Overshoot [§2 row 7]: the recorded span runs past `timeoutMs` (dispatcher p50 +1.5 s,
  dod-persist max +25 s), and the first turn waits through it. Cause not established; see open
  questions.
- CHANGELOG 2.1.296 (fleet is below it): "`--debug` output for hooks: command hooks on … SessionStart
  … now log their command, plugin, outcome and duration when they finish". This is diagnostics only;
  it still does not render anything.

### Q4. Per-hook output caps
- Docs (hooks.md, JSON output): "A hook's `additionalContext`, `systemMessage`, and
  `initialUserMessage` strings, and its plain stdout, are capped at 10,000 characters … each string on
  its own, even when several hooks run for the same event … Over the limit: Claude Code saves the
  output to a file … and replaces it with the file path and a preview of up to the first 2,000
  characters … this cap has no setting … Claude Code doesn't ask Claude to read the file." Introduced
  in 2.1.89.
- So the cap is per hook per field. Folding hooks into one dispatcher puts all their context under
  one 10,000-char budget. Separate registrations would each get their own. That is the reason
  `session-start-dispatch.sh:11-13` keeps dod-persist, desk-brief and mailbox-drain separate. An
  overflow is a silent truncation at harness level (D5). Not hit in 2 days: the largest part was
  5,936 [§2 row 10].

### Q5. async vs asyncRewake, and where async output goes
- `async` (docs): "Once an async hook is running in the background, Claude Code doesn't enforce
  `timeout` on it." So the `timeout` values on pre-session-validate (10), lead-crash-watchdog (10),
  session-register (5), live-session-registry (5) and net-context-stamp (5) **do nothing**. Output:
  "delivers the `additionalContext` and `systemMessage` fields … to Claude on the next conversation
  turn. Unlike a synchronous hook's `systemMessage`, neither field is shown to you." Notices only
  appear in verbose mode.
- Binary: the `async_hook_response` mapper pushes `systemMessage` and `additionalContext` as
  `isMeta` user content and nothing else. **stderr and exitCode are not forwarded anywhere.** The
  terminal row for async responses filters out SessionStart unless verbose. Measured: 57/57
  responses carried stderr only, delivered nowhere [§2 row 9]. The claim in the brief and in
  `session-start-dispatch.sh:14-15` that an async hook's systemMessage reaches the model and the
  terminal hides it is **confirmed** by docs and binary.
- `asyncRewake` (docs): "runs in the background and wakes Claude on exit code 2. The hook's stderr,
  or stdout if stderr is empty, is shown to Claude as a system reminder"; "Claude Code still enforces
  `timeout` on a hook you run with `asyncRewake`"; "an `asyncRewake` hook that exits with code 2 wakes
  Claude immediately even when the session is idle". The reader is the **model**, not the operator.
  CHANGELOG 2.1.287 fixed repeated wakes when the script is missing; 293 has the fix.
- Headless (`-p`): async hooks still running at teardown are cancelled. The binary gate dispatches
  asyncRewake synchronously when not interactive (prior art `measure-sessionstart-hooks.md:148-156`).
- 2.1.295, above the fleet: "async SessionStart hook's unchanged context being added to the
  conversation again on every resume" and "async hook's JSON output being ignored when it is printed
  over several lines". **Neither affects us**, because our async SessionStart hooks print no JSON
  (0 non-empty responses).

### Q6. Exit codes on SessionStart (the other way to be loud)
- Docs exit-2 table: `SessionStart | No | Shows stderr to user only`. Also "Claude Code renders the
  exit code 2 stderr in the transcript as a `<hook name> hook error` notice … Claude doesn't see it"
  (CHANGELOG 2.1.199 fixed it being hidden).
- Other non-zero exit with plain or no stdout: a non-blocking error notice carrying the first stderr
  line. The binary renders `hook_non_blocking_error` for every event except Stop/SubagentStop.
- A JSON object plus a non-zero exit counts as **success** and the exit code is ignored, so a JSON
  hook cannot be loud through its exit code. Use `systemMessage`.
- Exit 0: "Claude never sees stderr from a hook that exits 0."

### Q7. Render channels and token cost, from the binary
| Channel | Operator | Model | Source |
|---|---|---|---|
| sync top-level `systemMessage` | rendered: `<hookName> says: <content>` | **0 tokens** (`hook_system_message:()=>[]`) | binary render + mapper; `accounts-board.sh:5-21` (R5b probe) |
| `hookSpecificOutput.systemMessage` | ignored | — | `accounts-board.sh:12-13` |
| `additionalContext` (sync) | not shown | billed, re-billed on every resume | docs; census |
| plain-text stdout (sync) | not shown | billed as `"<hookName> hook success: <stdout>"` | binary `case"hook_success"` mapper |
| JSON stdout (sync) | — | `hook_success.content=""`, so not billed twice | [M] §2 row 12 |
| async `systemMessage` / `additionalContext` | hidden | billed, next turn | docs + binary |
| async stderr / exit code | hidden | dropped | binary + [M] §2 row 9 |
| exit 2 / other non-zero with plain stdout | "hook error" notice | not seen | docs + binary |
| `hook_cancelled` (timeout) | **hidden** (UPS only) | **dropped** | binary |

## 4. Feature inventory: what changes the design space

| Feature | In 2.1.293? | Lever | Applies here? | Source |
|---|---|---|---|---|
| Per-source matchers `startup/resume/clear/compact/fork` | yes (`fork` since 2.1.214) | latency + tokens on resume/clear | **Yes.** 12 of 13 hooks ignore `.source` [§2 row 13]. On resume the old context is still in the transcript and gets re-added; the dispatcher spends p50 7.1 s on resume | hooks.md SessionStart table |
| `statusMessage` | yes (schema string `"Custom status message to display in spinner while hook runs"`) | fault visibility (names the hook being waited on) | minor; needs settings edit; whether it overrides `Running SessionStart hooks…` is unverified | hooks.md Common fields; binary |
| `once` | yes | — | **No.** "Only honored for hooks declared in skill frontmatter; ignored in settings files" | hooks.md Common fields |
| `type: prompt` / `agent` | yes | — | **No.** SessionStart allows only command and mcp_tool (2.1.142: "use a command-type hook instead") | hooks.md; CHANGELOG 2.1.142 |
| `type: http` | yes | would avoid a fork | **No.** Not allowed on SessionStart ("Only `type: "command"` and `type: "mcp_tool"`") | hooks.md |
| `type: mcp_tool` | yes | in-server, no fork | weak. Blocking events wait for the server to connect (2.1.281), which adds to first-turn latency | hooks.md; CHANGELOG 2.1.281/2.1.284 |
| exec form `args` | yes (2.1.207) | skips one `/bin/sh -c` layer per hook | small: saves 1 exec per hook × ~11 sync+async SessionStart hooks; no `~` expansion; settings edit | hooks.md Exec form |
| `onFailure: "block"` | **no** (2.1.295) | — | no. It gates blocking actions; SessionStart cannot block | hooks.md; CHANGELOG 2.1.295 |
| `suppressOutput` | yes | — | "Has no effect" | hooks.md JSON output |
| `continue:false` | yes | — | harmful: stops the session | hooks.md |
| `initialUserMessage` | yes | — | `-p` only | hooks.md SessionStart decision control |
| `sessionTitle` / `watchPaths` / `reloadSkills` | yes (2.1.152) | — | **Latent drop.** The dispatcher merge keeps only `additionalContext` and `systemMessage` (`session-start-dispatch.sh:84`), so any child emitting these would be silently dropped | hooks.md; dispatcher |
| `CLAUDE_ENV_FILE` | yes | none for tokens or latency | no current use (0 hooks). Each line runs before **every** Bash call, so it is a per-call cost, not a startup win | hooks.md CLAUDE_ENV_FILE |
| SessionStart input `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd` on resume | yes (2.1.251) | operator-visible cost banner on resume, 0 tokens through systemMessage | optional | hooks.md SessionStart input |
| **Mods (in-process function hooks)** | **yes** (terminal 2.1.287+; reference "as of v2.1.290") | latency (no fork), 0 tokens, a **non-blocking operator surface** (AbovePrompt band, pane, `$.ui.notice/toast`), loud failure (`.catch` with `next.error.kind = "timeout"`) | **Pilot candidate** for the accounts board and a startup-fault banner. `session.start` fires "once … before the first prompt … Not after /clear, /resume"; hook limit 10 s; API churns release by release (2.1.288–2.1.302) | mods/reference.md Session, Limits; mods/overview.md:97; mods/events.md:317 |
| `--debug` per-hook "Hooks:" lines for SessionStart | **no** (2.1.296) | diagnosis | upgrade-gated | CHANGELOG 2.1.296; hooks.md Debug hooks |
| Prompt typed during SessionStart vanishes on `←` | bug in 2.1.293, fixed 2.1.296 | fault tolerance | a harness silent prompt drop while hooks run (D10) | CHANGELOG 2.1.296 |
| Statusline (`refreshInterval`, multi-line, gets `session_id` + `transcript_path`) | yes | **0-token, persistent, non-blocking operator surface** | **Yes**: the only always-on channel that can report a hook the harness already killed | statusline.md:69, :154, :162, :200-203 |

## 5. Drop-path inventory (harness and dispatcher boundary)

| ID | Path | Loud today? | 2-day count | Evidence |
|---|---|---|---|---|
| D1 | sync SessionStart hook hits its harness timeout → `hook_cancelled` | **no** (terminal null, model []) | 64 (60 own) | §2 row 6; binary |
| D2 | dispatcher watchdog kills a child at 9 s; its output is dropped with no record | **no** | ≥107/410 runs > 9 s (brief census) | `session-start-dispatch.sh:61-68` |
| D3 | dispatcher skips a missing or non-executable child | **no** | unknown (no record) | `session-start-dispatch.sh:55` |
| D4 | dispatcher cuts merged context at CAP from the end | **no** | 0 (latent) | `session-start-dispatch.sh:88`; §2 row 10 |
| D5 | harness 10k per-field overflow → file plus 2k preview, model not told to read it | **no** | 0 (latent) | hooks.md JSON output |
| D6 | async hook stderr / exit code | **no** (dropped) | 57/57 | binary; §2 row 9 |
| D7 | async hook systemMessage shown to model only | by design | 0 (none emit) | docs; binary |
| D8 | dispatcher drops child `sessionTitle/watchPaths/reloadSkills/initialUserMessage` | **no** | 0 (latent) | `session-start-dispatch.sh:84` |
| D9 | `/clear` or a conversation switch while background SessionStart hooks run → output not applied | **no** | rare | hooks.md SessionStart |
| D10 | 2.1.293: prompt sent during SessionStart vanishes when `←` backgrounds the session | **no** | unknown | CHANGELOG 2.1.296 |
| D11 | dispatcher exits 0 silently when jq is missing or no child printed | **no** | unknown | `session-start-dispatch.sh:29,70-72` |
| D12 | children's stderr discarded; dispatcher `exec 2>/dev/null` | by design (exit-0 semantics) | — | `session-start-dispatch.sh:33,56` |

## 6. Recommendations

Ranked by drop paths closed per unit of effort. None of them throttles, caps, kills or demotes
session work.

### R1. Have the dispatcher name every child it kills, skips or truncates in its `systemMessage` (closes D2, D3, D4, D11)
- Where: `hooks/session-start-dispatch.sh:55` (skip), `:65` (watchdog: record which pids it
  killed, e.g. touch `$T/k$i`), `:88` (record which children's context fell past CAP), `:70`
  (no-jq path: `printf` a static JSON `systemMessage` instead of exiting silently). Append one line
  per event, e.g. `⚠ startup: accounts-board.sh killed at 9s — output lost. Recover: /accounts`.
  The recovery text comes from a small per-child table in the dispatcher. Also append per-child
  durations to a ledger (`~/.claude/logs/ssd-children.jsonl`). Today there is no per-child timing
  anywhere, so later axes could not attribute the 26% overrun.
- Impact: closes 4 dispatcher-internal silent paths (≥107 events/2 d for D2). 0 tokens (the
  systemMessage maps to `[]`), 0 ms (it is written during a merge that already runs).
- Effort S · Risk low. Keep the line short. systemMessage has the same 10k cap, so the board is safe.
  · Settings edit: no · **Conviction 85**

### R2. Statusline startup-fault segment: the only always-on 0-token channel that outlives a harness kill (closes D1, backstops R1)
- The harness renders nothing for a SessionStart `hook_cancelled`, and a killed hook cannot speak.
  Something that runs **after** the kill has to report it. `~/.claude/statusline.sh` (repo
  `statusline.sh`, identical; 680 lines) receives `session_id` and `transcript_path`
  (statusline.md:200-203) and runs off the startup critical path
  (`docs/research/startup-2026-08-16/measure-statusline-tui.md:345`).
- Design: per session, until the first assistant record exists, scan only the transcript head with
  one bounded read (`head -n 400 | rg -m5 '"hook_cancelled".*"SessionStart'`). Cache the verdict in
  `/tmp/cc-ssfault-$session_id` (`clean` or the fault line). Afterwards a refresh costs one `[ -s ]`
  test, which is a builtin and needs no fork. Render, e.g., `⚠ startup: session-start-dispatch.sh
  timed out 13.5s/12s — board+context lost · run /accounts; ask Claude to re-read the desk brief`.
  Also render the R1 ledger lines.
- Impact: every SessionStart timeout becomes operator-visible and attributable to a named hook with
  a prescribed recovery: 60 own events in 2 d. 0 tokens, 0 first-turn ms. One extra `rg` per session
  until verdict [E: one fork per session versus ~0.3–1.1 refreshes/s machine-wide,
  `D-hooks-statusline.md`].
- Effort S–M · Risk low (statusline already reads per-session state; bound the head read) ·
  Settings edit: no · **Conviction 75**

### R3. Dispatcher hard exit deadline below the harness timeout, with a raised outer timeout as backstop only (turns D1-for-dispatcher, 6 per 2 d, into a named partial)
- Printing early does not help (Q3: output discarded on cancel). The dispatcher must **exit** before
  the harness timer fires. Measure elapsed time from the dispatcher's own start (`SECONDS`). At a
  hard deadline (e.g. 10 s, which leaves margin for the measured p50 +1.5 s cancel overshoot), stop
  waiting, merge what exists, add the R1 lines for the unfinished children, and exit.
- Then recommend raising the dispatcher registration `timeout` 12 → 15 (**settings.json, operator
  c10**). The internal deadline governs the normal case, so p50 latency is unchanged. The outer
  timeout only catches a wedged dispatcher.
- Impact: the 6 whole-output losses (board plus all context) become partial outputs that name the
  late child. First-turn tail is unchanged or better: the cap moves from 12 s + overshoot to ~10 s.
- Effort S · Risk: a hard deadline drops slow children loudly instead of losing everything silently
  · Settings edit: yes, for the backstop only · **Conviction 70**

### R4. Align sibling sync timeouts with the batch critical path (dod-persist, mailbox-drain, desk-brief-inject 5 → 10 s) (closes most of 53 D1 events)
- Harness fact (Q1, Q2): the first response waits for the max of parallel sync spans. A 5 s timeout
  next to a dispatcher that runs to 9–12 s saves nothing in those batches and drops the output.
  Measured: 35/53 cancellations happened with the batch still running for p50 3.0 s, p90 5.0 s more
  [§2 row 8].
- Impact: up to 35 of 53 cancellations in 2 d would have cost 0 extra ms. The other 18 (fast
  dispatcher) could add up to 5 s in that batch. mailbox-drain is emit-then-commit
  (`hooks/mailbox-drain.sh:277-283`), so its timeouts delay mail, they do not lose it. dod-persist
  and desk-brief output is lost for the session.
- Effort S · Risk: a slower tail in batches where the dispatcher is fast. Pair with R3 so 10 s is
  the batch ceiling · Settings edit: **yes (c10)** · **Conviction 65**

### R5. Stop relying on async stderr to warn anyone; fix pre-session-validate (closes D6)
- `hooks/pre-session-validate.sh:6-8` says it "emits a stderr warning so the user knows". As an
  async hook (exit 0) that stderr is dropped: 57/57. It has also been raising false alarms. It
  validates `~/.claude-versions/current → 2.1.114` (`ls -la ~/.claude-versions/current`), while the
  fleet runs `~/.claude-293` (24 "no working version" lines in 2 d, nobody saw them). It still forks
  a `--version` of a 236 MB binary on every session start.
- Fix: retarget it at the real pin or retire it (the pin is owned by the MANIFEST and activation
  scripts). Then route real faults to the R1/R2 ledger, or to `asyncRewake` with exit 2 so the model
  is woken. That costs tokens only on failure. General rule: **an async hook has no operator-visible
  channel.**
- Effort S · Risk low · Settings edit: only if switching to asyncRewake (c10) · **Conviction 70**

### R6. Make the dispatcher source-aware: on `resume` (and `fork`), re-render the board but do not re-inject context the transcript already holds
- 12 of 13 hooks ignore `.source`. On resume, the previous startup context is still in the
  conversation and the harness adds a fresh copy. The dispatcher spends p50 7.1 s on resume
  (n=27/2 d) before the first resumed response.
- Do it inside the dispatcher (read `.source` once, export `CC_SSD_SOURCE`, children opt in), so no
  settings edit is needed. Changing content (mail, recycle packet, board) still runs. Static
  orientation context is skipped.
- Impact [E]: ~900 tokens per resume (3,657 chars ÷ 4) × ~18 resumes/day, and part of the 7.1 s
  resume wait. Small fleet-wide, but free.
- Effort S–M · Risk: a child that must re-assert on resume gets skipped. Gate per child, default
  keep · Settings edit: no (alternative: matcher `startup|clear|compact` on G4, c10) ·
  **Conviction 55**

### R7. Take children the first turn does not need off the dispatcher's wait (latency)
- The harness offers no non-blocking sync hook. The first-turn wait equals the dispatcher's slowest
  waited child. Children whose output only the operator reads, or only matters on failure, can be
  launched detached (setsid, no wait), report through the R1 ledger, and get rendered by R2.
  Children whose context the model needs on turn 1 stay waited.
- Impact: dispatcher span drops to the max of the context-producing children. The size of the saving
  depends on per-child timings that no log has today (R1 adds that log). Up to the p50 5.5 s / p90
  9.7 s span [M] is at stake.
- Effort M · Risk: the board moves from a scrollback banner to the statusline or a mod. That is an
  operator-UX change · Settings edit: no · **Conviction 50**

### R8. Forward or refuse the extra SessionStart fields in the dispatcher merge (closes D8)
- `session-start-dispatch.sh:84` keeps only `additionalContext` and `systemMessage`. Forward
  `sessionTitle`, `watchPaths` and `reloadSkills` (union or last-wins), or add a test asserting no
  child emits them and R1-flag any that does.
- Effort S · Risk low · Settings edit: no · **Conviction 50**

### R9. Pilot a mod for the accounts board and a startup-fault banner (design-space change)
- Mods (terminal 2.1.287+, fleet on 2.1.293) run in-process with no fork. They can draw an
  AbovePrompt band or pane, or call `$.ui.notice`, at 0 tokens and **without blocking the first
  turn**. `.catch` gets `next.error.kind === "timeout"`, so the failure is loud by construction. A
  band reading `/tmp/claude-accounts-board.txt` through `$.fs.read`, refreshed by `$.clock.every`,
  would take the board off the dispatcher completely.
- Risks: API churn (≈100 mod-related CHANGELOG lines in 2.1.287–2.1.302), SGR board rendering versus
  mod `Text` elements (`docs/lessons/sessionstart-systemmessage-accepts-sgr.md`), a new plugin
  surface to install and audit, and `session.start` does not fire after /clear or /resume.
- Effort M–L · Settings edit: plugin install (operator) · **Conviction 35**

### R10. Upgrade note (input to the MANIFEST audit, not a directive)
- 2.1.296 adds per-hook SessionStart debug lines (outcome and duration for every hook, including
  timeouts) and fixes D10, the vanishing prompt. 2.1.295 fixes async multi-line JSON. None of them
  renders SessionStart timeouts, so R1 and R2 are needed on any version. **Conviction 50.**

### R11. `statusMessage` on the dispatcher registration (minor)
- Example: `"statusMessage": "startup: board · recycle · desk context"`, so the spinner names what
  the operator is waiting on. Unverified whether it replaces `Running SessionStart hooks…` on
  SessionStart. Settings c10 · Effort S · **Conviction 30**

### Rejected, with reason
- **Make the banner hooks async**: their systemMessage would go to the model and be hidden from
  the operator (Q5; matches `session-start-dispatch.sh:14-15`).
- **`once`**: skill frontmatter only. **prompt/agent/http hooks**: not allowed on SessionStart.
  **`suppressOutput`**: no effect. **`onFailure`**: not on 293 and does not apply to SessionStart.
- **`CLAUDE_ENV_FILE` as a token lever**: it is shell preamble for each Bash call, not context.
- **Split the dispatcher back into separate registrations**: no latency gain (max of parallel), and
  a slow child's loss becomes harness-silent instead of nameable by the dispatcher (R1).

## 7. Open questions
1. **Cancel overshoot** (dispatcher p50 +1.5 s, dod-persist max +25 s): is the harness timer late
   (event-loop starvation at load ~52/core), or does it wait for the stdout pipe to close after
   SIGTERM while grandchildren hold it? The binary read did not settle whether the hook's process
   group or only its pid is signalled. If it is the pipe, `exec`-ing the final stage or a TERM trap
   that kills the hook's own group would cut first-turn tail latency.
2. Does `statusMessage` override the generic `Running SessionStart hooks…` spinner? It is in the 293
   schema; the render path is unverified.
3. Does a mod's `session.start` hook block the first turn (it is documented as "before the first
   prompt", 10 s limit), or only the mod's own UI? This decides whether R9 is latency-neutral.
4. Per-child dispatcher timings do not exist anywhere. R7's payoff cannot be sized until R1's ledger
   records them (other axes may hold estimates).
5. Why do 0 batches show source `compact` in 2 days? Auto-compact may be off, or sessions end before
   it fires. If compaction is re-enabled, the context hooks would re-inject on compact, which is
   correct, and the board would re-render, which is wasted.
6. Statusline exposure: are the agent-spawned sessions (96% of starts) ever looked at through their
   statusline? If not, R2 covers the operator's own panes and R1's systemMessage covers the
   scrollback. A desk-level sweep over the transcripts (`hook_cancelled` on SessionStart) would be
   the fleet-wide backstop.

## Sources
- https://code.claude.com/docs/en/hooks (fetched 2026-10-18 as `hooks.md`): Common fields, Command
  hook fields, Exit code output, Timeouts, JSON output (10,000-char cap), SessionStart, Run hooks in
  the background, Debug hooks.
- https://code.claude.com/docs/en/hooks-guide, https://code.claude.com/docs/en/statusline,
  https://code.claude.com/docs/en/plugins/mods/reference, …/mods/overview, …/mods/events
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (entries cited by
  version: 2.1.47, 2.1.89, 2.1.142, 2.1.152, 2.1.199, 2.1.207, 2.1.214, 2.1.251, 2.1.268, 2.1.271,
  2.1.280, 2.1.281, 2.1.285, 2.1.287, 2.1.292, 2.1.295, 2.1.296)
- Binary: `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (strings, read-only)
- Local: `hooks/session-start-dispatch.sh`, `hooks/accounts-board.sh:1-21`,
  `hooks/pre-session-validate.sh:1-18,122,154`, `hooks/mailbox-drain.sh:13-17,277-283`,
  `docs/research/startup-2026-08-16/measure-sessionstart-hooks.md:30,148`,
  `docs/research/function-hooks-91870-2026-09-03.md` (whose 30% estimate that function hooks ship
  within 12 months is superseded: they shipped as mods in 2.1.287),
  `docs/research/load-root-cause-2026-10-17/D-hooks-statusline.md`
- Helper scripts: `docs/research/startup-hooks-2026-10-18/a6_census.py`, `a6_firstturn.py`
