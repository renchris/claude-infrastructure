# A5 — Silent-drop fault tree for SessionStart hooks

Axis A5 of the 2026-10-18 startup-hooks study. The question: by what paths can a startup hook's output or effect vanish without the operator seeing it? For each path: how often it fired, whether any record of it exists, and the loud replacement it should get (an operator-visible line naming the hook, a durable ledger row, and a recovery command).

This was a read-only study. No hook script was executed. The only things run were transcript and log reads, static reads of the hooks, `rg` over the installed Claude Code 2.1.293 binary, and three one-line `/bin/bash` trap-semantics probes that ran no hook code (§3, P13).

## 0. Headline

- **28.9 % of session starts (107 of 370 in the last 48 h) lost something, and none of those losses was shown to the operator.** [M] `python3 -I a5_drop_census.py --since 2026-10-16T06:18:00Z` gives `[UNION] 107 of 370`. That count is 42 starts with at least one harness timeout kill plus 84 dispatcher runs that reached the 9 s child bound, with 19 starts in both groups.
- **Claude Code renders `hook_cancelled` only for UserPromptSubmit.** For SessionStart the renderer returns `null`, so a timed-out startup hook leaves no trace in the terminal. Source: the 2.1.293 binary, `case"hook_cancelled":{if(l.hookEvent!=="UserPromptSubmit"||!l.timedOut){return null}…"timed out … — output discarded. Raise the hook's "timeout" to allow more time."`. [M] `rg -a -o '.{0,400}case"hook_cancelled".{0,500}' ~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`. This is why the 05:49Z incident looked like "nothing happened".
- **Async hooks have no operator-visible channel at all.** Their stdout, stderr and exit code are written only to the transcript JSONL. Only `response.systemMessage` and `hookSpecificOutput.additionalContext` go anywhere, and both go to the **model** (as isMeta user messages, delivered with the next turn's attachments). The terminal filters out SessionStart async responses unless the verbose/transcript flag is on. [M] same binary, `case"async_hook_response":{…systemMessage…g.push(Re({content:GT(b),isMeta:!0}))…` and the render filter `z=(Wo)=>h||M&&Wo.hookEvent!=="SessionStart"`.
- **The always-on alarm nobody sees: `pre-session-validate.sh` checks a binary the fleet never launches.** It runs `--version` against `~/.claude-versions/current`, which points to 2.1.114, but `_claude_pinned` launches `~/.claude-293/node_modules/.bin/claude`. Under load it times out at 2 s and logs "no working version" on 21 of 370 starts (5.7 %). Its log holds 582 "failed/broken" lines. The hook also has an `ln -sfn` rollback actuator that a load-induced false negative could fire.
- **Three "stamp-before-delivery" defects.** A one-shot marker is written even though the payload can still be discarded afterwards, which makes the loss permanent (recycle-failed-inject, the accounts-board deadline banner, the mailbox-drain goal nudge).
- **A kill that the ledger records as success.** Under `/bin/bash` 3.2, an EXIT trap that fires after SIGTERM sees `$? = 0`. So `session-index-start.sh`'s IDL row records a killed run as `passed exit:0`. [M] §3 P13.

## 1. Method

| Step | Command (read-only) |
|---|---|
| Census of all SessionStart attachments in the 411 main transcripts, cut to the last 48 h (records ≥ 2026-10-16T06:18Z; older records in long-lived transcripts are excluded), grouped per SessionStart event by `toolUseID` | `python3 -I docs/research/startup-hooks-2026-10-18/a5_drop_census.py --since 2026-10-16T06:18:00Z` (helper written for this axis; output reproduced in §2) |
| Render and model-routing rules | `rg -a -o` over `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (the binary the 38 running sessions use: `ps -axo args \| rg '^/Users/chrisren/' \| awk '{print $1}' \| sort \| uniq -c`). The incident transcript records `"version":"2.1.293"`. |
| Incident view | `jq` over `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-….jsonl` |
| Per-child presence in dispatcher output | `rg` + inline `python3 -I` over dispatcher `hook_success` stdout (§2.3) |
| Duration histogram | `jq … .attachment.durationMs \| awk` 0.5 s bins (§2.3) |
| Side ledgers | `~/.claude/logs/pre-session-validate.log`, `~/.claude/logs/lead-crash-watchdog.log`, `~/.claude/autonomy/idl.jsonl` |
| Trap semantics | `timeout -s TERM 1 /bin/bash -c 'trap "echo trap-rc=\$?" EXIT; sleep 3'` (no hook code) |

Known biases:
1. `hook_success` is recorded only when a hook prints, so a silent success and "killed before printing" look the same for **async** hooks. A sync hook's kill *is* recorded, as `hook_cancelled`.
2. `async_hook_response` records exist only when the async hook produced output. All 53 in the window had non-empty stderr.
3. Load averaged about 52 per core throughout. Every rate below is a high-load rate.

## 2. Measurements (48 h, 370 SessionStart events)

### 2.1 Event mix
[M] census: `{'startup': 355, 'resume': 14, 'clear': 1}`. There were **0 `compact` events**, so the "skipped on compact" paths did not fire in this window.

### 2.2 Harness timeout kills (`hook_cancelled`, every one `timedOut: true`)

| hook | registration | cancels / 48 h | cancelled durationMs p50 / max | rendered? |
|---|---|---|---|---|
| mailbox-drain.sh session-start | 5 s sync | **31** | 5,592 / 14,413 | no |
| dod-persist.sh | 5 s sync | **18** | 6,884 / 30,180 | no |
| session-start-dispatch.sh | 12 s sync | **6** | 13,544 / 21,723 | no |
| desk-brief-inject.sh | 5 s sync | 1 | 13,368 | no |
| (project hook) mcp-auth-guard.sh | 30 s | 1 | 33,183 | no |

[M] census `[P1]`. 42 of 370 events (11.4 %) had at least one. 0 `hook_non_blocking_error` / `hook_error_during_execution` records (`[P5]`).

The harness enforces its own timer late under load. Cancels land at 1.1–6× the registration, and successes are recorded past their timeout too: mailbox-drain success max 14,674 ms against 5,000 ms, dod-persist 8,002 ms against 5,000 ms (census per-hook table). So a timeout bounds neither latency nor output.

### 2.3 Dispatcher internal drops

- 364 dispatcher successes. durationMs p50 5,298 · p75 8,634 · p90 9,624 · p95 9,967 · p99 10,937 · max 15,603. [M] census `[P2]`.
- **84 of 364 at or above 9,000 ms.** The 0.5 s histogram shows a pile-up at the bound: the 9.0 s bin has 38 runs and the 9.5 s bin 29, against 6 and 9 in the 8.0 s and 8.5 s bins. [M] `jq -r '…durationMs' | awk '{b=int($1/500)*0.5…}'`. [E] Taking about 8 runs per bin as baseline, roughly 50–65 runs had a child killed by the 9 s watchdog.
- **Which child was killed is unknowable from any record.** In 83 of the 84 runs at or above 9 s, every child that always prints was present: session-start.sh (`MCP:`), setup-plan (`Plans:`), setup-task (`Tasks:`), frontier (`Frontier:`), accounts-board (`CLAUDE MAX`). The one exception was a missing `MCP:` line. So the victims are conditional-output children (recycle-failed-inject, activation-watch, escalation-watch, session-index-start, config-mirror-assert), and their absence looks exactly like "nothing to say". [M] inline per-child presence script (§1).
- The accounts board was in the systemMessage of **364 of 364** dispatcher successes, all in the fresh band (0 stale, unavailable, withheld or empty). [M] `jq … test("STALE by") …`. **The board was lost only when the whole dispatcher was harness-killed: 6 times in 48 h.**
- 9,500-char cap: **0 hits**. The merged context max was 650 chars, p50 616 (`[P3]`). The path is latent.
- Raw child JSON leaked into context (malformed child output): **0** (`[P10]`). Events with no dispatcher record: **0** (`[P9]`).

### 2.4 Harness 10,000-char cap
**0 hits in 48 h** (`[P4]`; dod-persist max 5,936, budget `CC_DOD_INJECT_MAX_CHARS` 6000 at `hooks/dod-persist.sh:303`). Without the time cut the census finds 3 dod-persist records of 35,344 chars, all from 2026-10-01 before the budget fix (`9aa483e9….jsonl`). Over the cap, Claude Code swaps the context for a `<persisted-output>` 2,000-char preview of the head (`hooks/dod-persist.sh:249-253`; `docs/research/claude-api-audit-2026-10-04/shard-hooks-a.md:8`). The operator sees nothing either way.

### 2.5 Async hooks
53 `async_hook_response` records, all exit 0, all with stderr. [M] census `[P6-P8]` and `xargs -0 rg … | jq -r '.attachment.stderr' | sort | uniq -c`:
- 21 from `[pre-session-validate] WARNING: …/2.1.114 failed --version check` + `ERROR: no working version`.
- 32 from `session-register.sh: line 614: <pid> Killed: 9 ( sleep "$P8_TIMEOUT"; kill -9 "$_w" … )`. This is bash's job notice for the watchdog being reaped on the success path, i.e. noise.
- 0 routed to the model (none carried systemMessage or additionalContext).
- Delivery lag (record timestamp minus event start): p50 8.0 s · p90 54.2 s · max 387.1 s. In the incident the validate stderr was attached 6 min 27 s after start, at the first prompt (05:49:5x → 05:56:23Z).
- Async kills: **no record type exists.** No async SessionStart hook has a `hook_cancelled` in the window. Not measurable from transcripts.
- Side ledger as a proxy: `lead-crash-watchdog.log` has 389 `registered session=` and 389 `spawned watchdog daemon` lines in the 48 h window, with 0 sessions registered but not spawned. [M] `awk` window + `comm -23`. This register/spawn pair is the model of a detectable async hook.

### 2.6 The incident, as the operator saw it
Transcript `5759497b…`: three `hook_cancelled` records (dod-persist 8,323/5,000 ms, mailbox-drain 10,051/5,000 ms, dispatcher 13,544/12,000 ms), no `hook_system_message`, no `hook_additional_context`. Per the render rule in §0, all three return `null`, so the operator's terminal showed **no SessionStart output at all**. There was no board, no DoD, no mail and no explanation. Those three records in the JSONL are the only evidence. [M] `jq -c 'select(.attachment!=null) | {…}'`.

## 3. The fault tree

Columns: **freq** = 48 h, 370 events [M] unless marked. **Record?** = where any durable trace lives. **Operator sees?** = rendered in the terminal.

| # | Path | Code | Freq (48 h) | Record? | Operator sees? | Content lost | Loud replacement (§4 has the design) |
|---|---|---|---|---|---|---|---|
| P1 | **Harness timeout kill of a sync hook** | harness; registrations in settings.json | 56 cancels in 42 events | transcript `hook_cancelled` (command, durationMs, timeoutMs) | **No** (render returns null for SessionStart) | dod-persist: the frozen DoD is **not injected for the whole session** (no retry; it runs only at SessionStart/PreCompact). mailbox-drain: mail *deferred*, not lost (emit-then-commit, `mailbox-drain.sh:277-284, 922-930`). desk-brief: desk role brief lost. dispatcher: see P3 | Post-hoc reporter (§4.2) + retry at first prompt for model-needed payloads (§4.3) |
| P2 | **Dispatcher child killed at the 9 s bound** | `session-start-dispatch.sh:65` (`kill -TERM -- -$p`), output file dropped | [E] about 50–65 of 364 runs (84 at or above 9 s) | **none**; the victim is unattributable (§2.3) | No | unknown by construction: a conditional child's warning, or its side effect cut short | In-band drop line in the dispatcher systemMessage + per-child IDL row (§4.1) |
| P3 | **Whole dispatcher killed by the harness** | `:92` prints only at the very end; harness discards stdout on abort | 6 | transcript `hook_cancelled` | No | **all 10 children**, including the accounts board (systemMessage) and the recycle-failed recovery packet | Persist-on-kill: dispatcher TERM trap saves its finished children's outputs + post-hoc reporter (§4.2) |
| P4 | Dispatcher 9,500-char cap, cut from the end with no marker | `:88` `$c[:$cap]` | 0 (max 650) | none | No | the tail child's context | Cut on a child boundary, append `[cut: <children>]`, name them in the drop line (§4.1) |
| P5 | Harness 10,000-char cap → 2 KB preview | harness | 0 (3 before the fix) | transcript (`<persisted-output>`) | No | everything past 2 KB | dod-persist: keep a hard ceiling under 10 k even for the always-kept newest capture (`dod-persist.sh:257-259` allows an over-budget newest unit). Dispatcher: the in-band line already covers it |
| P6 | **Child stderr discarded** | `:33` `exec 2>/dev/null`, `:56` `2>/dev/null` | not measurable (by design) | none | No | every child diagnostic, e.g. `mailbox-drain.sh:930` ".seen commit failed" when run directly (it is a sync hook whose stderr is kept in the transcript but not rendered) | Diagnostics go to the IDL row, never to stderr (the lesson "fail-loud into a log nobody reads is silent", `.claude/rules/agent-operating-lessons-situational.md:7`) |
| P7 | jq missing → silent fail-open | dispatcher `:70`; `dod-persist.sh:395`; `mailbox-drain.sh:77`; `recycle-failed-inject.sh` top; most children | 0 (jq at `/opt/homebrew/bin/jq`) | none | No | every JSON hook at once | The dispatcher prints a **static, hand-written** `{"systemMessage":"⚠ startup: jq not on PATH — 10 startup hooks produced nothing …"}` (no jq needed). Each standalone hook does the same in one `printf` |
| P8 | Malformed child JSON → injected as plain context (misroute, not a drop) | `:82-85` (`try fromjson catch null` → `{c: .}`) | 0 | none | No (a would-be banner lands in model context: tokens) | the banner, plus tokens spent on raw JSON | Treat stdout starting with `{` that fails to parse as malformed: drop it from context and name the child in the drop line. Fix hand-built JSON at `setup-task-symlinks.sh:196` and `setup-plan-symlinks.sh:94` (`echo "{\"…\":\"$CONTEXT\"}"`) to `jq -nc --arg` |
| P9 | jq merge failure → whole output empty | `:91` `\|\| OUT=""` | 0 | none | No | all 10 children | Fall back to emitting only the children whose stdout already parses, plus a drop line |
| P10 | Child not executable / dangling live-layer symlink → skipped | `:55` `[ -x ] \|\| continue` | 0 (10 of 10 children resolve: `readlink ~/.claude/hooks/<c>`) | none | No | that child | Name it in the drop line ("missing child: X — re-link: converge") |
| P11 | `mktemp` failure → exit 0 | `:46` | 0 | none | No | all 10 | Static `printf` systemMessage, as in P7 |
| P12 | **Stamp-before-delivery** (a one-shot marker written before the payload is accepted) | `recycle-failed-inject.sh:52` print → `:55-56` stamp `injected_at`; `accounts-board.sh:122` writes the deadline-banner latch **before** `:123` prints it; `mailbox-drain.sh:924-925` stamps the once-per-goal nudge right after `printf` | latent: 1 packet on disk since 2026-10-09; the banner latches daily | the stamp itself (falsely says delivered) | No | recycle recovery order (marked injected, never seen); deadline banner for the day; /goal nudge for that goal | Move the commit to after acceptance: children write commit actions to `$T/commit.NN`, and the dispatcher runs them only after its own `printf` succeeded and immediately before `exit 0`. Hooks outside the dispatcher confirm at the next boundary (the mailbox `.seen`→`.acked` pattern) |
| P13 | **IDL EXIT trap records a SIGTERM kill as success** | `session-index-start.sh:17` (`_sis_rc=$?; … passed`); every `hooks/lib/idl-log.sh` user that relies on the EXIT trap only | 385 rows `passed exit:0` in 48 h; how many were kills is unknowable | IDL (wrong) | No | the kill itself | Add `trap '…; exit 143' TERM` so the EXIT trap sees 143. [M] `timeout -s TERM 1 /bin/bash -c 'trap "echo trap-rc=\$?" EXIT; sleep 3'` → `trap-rc=0`; adding `trap "echo got-TERM; exit 143" TERM` → `exit-trap-rc=143` |
| P14 | **Async hook output** (stdout/stderr/exit code) | harness | 53 records, all invisible | transcript only | **No** (filtered unless verbose) | pre-session-validate's "no working version" (21); register noise (32) | Async hooks write IDL rows; any operator-facing finding is surfaced through §4.2/§4.4, never through stderr |
| P15 | Async systemMessage → model, not terminal | harness (confirmed in binary; the claim at `session-start-dispatch.sh:14-15` holds) | 0 (no async hook emits one) | transcript | No (and costs tokens) | — | Keep the rule: banner hooks stay sync. Add a lint: an async-registered hook must never print `systemMessage` |
| P16 | Async hook killed at its timeout | harness | **not measurable**: no record type | none (lead-crash-watchdog has its own pair: 389/389) | No | e.g. session-register's registration (internal bound 20 s at `session-register.sh:42` vs a 5 s registration) | START/END row pair per async hook (the lead-crash-watchdog pattern) |
| P17 | **pre-session-validate: wrong target + 2 s load-calibrated probe + silent rollback actuator** | `pre-session-validate.sh:115` (`timeout 2 … --version`), `:152-155` (ERROR + `exit 0`, "let the session continue and die loudly"; it never dies, because it is not the running binary), `:159` `ln -sfn` | 21 / 370 starts (5.7 %); 582 failed/broken lines in its log; daily counts on 10-16, 10-17, 10-18: 13, 10, 5 | its own log + transcript stderr | No | a permanently firing alarm nobody sees, plus a rollback that could re-point `current` on a false negative | Retire it from SessionStart, or re-target it to the running binary. The hook runs *inside* a session of that binary, which already proves `--version` works. Route findings to IDL + board, never stderr |
| P18 | `\|\| true` / `2>/dev/null` swallow sites, exit 0 after an internal error | 5–25 sites per hook (rg count: session-start.sh 25, live-session-registry 21, activation-watch 20, setup-task-symlinks 20, mailbox-wake-arm 13, config-mirror-assert 12, net-context-stamp 10, desk-brief 9, setup-plan 9, session-index-start 6, escalation-watch 5) | n/a | only where an IDL row exists (desk-brief-inject, session-index-start, escalation-watch writes .jsonl) | No | varies | Not every swallow needs a row. The rule: a swallow on the **payload path** (the step that produces what the session or operator is owed) must leave an IDL disposition; a swallow on best-effort side paths may stay silent |
| P19 | Producer staleness (accounts board, keepwarm) | `accounts-board.sh:33-47, 172-188` | 0 stale of 364 | the board's own age line | **Yes**, a loud age band + `producer_state` recovery | — | **Already correct.** This is the reference pattern for the rest (names the producer, names the action) |
| P20 | Skipped on `source=compact` (accounts-board `:132`, by design) | | 0 compact events | n/a | n/a | nothing owed | Keep. It is a deliberate abstention, not a drop |
| P21 | Async delivery lag (a correct async message arrives minutes late) | harness | p90 54 s, max 387 s | transcript | — | timeliness | Do not use async for anything time-sensitive or operator-facing |
| P22 | Harness timer slip (kills and successes land well past the registration) | harness | dispatcher kill max 21.7 s vs 12 s; dod-persist kill max 30.2 s vs 5 s | transcript | No | latency, and the bound no longer bounds | Input for the latency axes. For A5 it means "timeout = time-to-drop" is not a safe assumption, so the post-hoc reporter must wait for the record rather than for a wall-clock |
| P23 | Hook prints nothing → no record (success indistinguishable from a no-op or a never-ran) | harness | structural | none | — | observability | Per-start summary row (§4.4) gives a denominator independent of printing |

Not a silent drop, but worth noting: **mailbox-drain under P1 is a deferral.** The window stays pending and re-delivers at the next boundary (`mailbox-drain.sh:283-284`). One residual window can lose mail: if the harness timer fires after `mailbox_commit_seen` (`:929`) but before the process exits (trap `mailbox_drain_release`), the output is discarded and the cursor has already advanced. [E] By inspection, that window is one lock and write plus the EXIT trap, milliseconds wide but not zero. The goal-nudge stamp at `:925` sits *before* the commit and adds a `find -delete` fork (`:600`), which widens the general emit→exit window.

## 4. Design: loud on drop, silent on success

Constraints:
- Do not throttle, cap, kill or demote any live work.
- Spend 0 model tokens on anything the model does not need.
- Every drop is named, ledgered and given a recovery.
- "An alarm that always fires says nothing" (`docs/lessons/a-rubric-that-saturates-has-not-ranked-anything.md:55` → alarm-polarity-and-attention-budget): healthy starts print nothing new.

### 4.1 Tier 1, in-band: the dispatcher reports its own drops (covers P2, P4, P7–P11)
The dispatcher already knows everything it drops. Change it to record and say so.
- The watchdog subshell writes `$T/k<NN>` before it TERMs child NN (`:65`). After `wait`, each child gets `{name, killed, ms, bytes, json_ok}`.
- The merge (`:79-91`) gains a `$drops` array. If it is non-empty, append **one line** to the top-level `systemMessage` (0 tokens; it renders):
  `⚠ startup · dropped: activation-watch (killed at 9s, output unknown) · config-mirror-assert (malformed JSON) — cc-startup-health 5759497b`
  If nothing dropped, nothing is added (silent on success).
- Cap (`:88`): cut on a child boundary, never mid-child, and name the cut children in the same line.
- jq absent or `mktemp` failure: a static `printf '{"systemMessage":"⚠ startup: jq not on PATH — 10 startup hooks produced nothing. Check: command -v jq"}\n'`. No jq is needed to write a constant.
- One IDL row per **dropped** child: `{"hook":"session-start-dispatch","disposition":"dropped","reason":"child-bound:activation-watch","sid":…,"ms":9000}`, through the existing `hooks/lib/idl-log.sh` writer (jq-encoded, append-only). Healthy children write nothing extra; the denominator row is in §4.4.
- Cost [E]: one marker-file stat per child plus the existing single jq call. Well under 10 ms of the run.

### 4.2 Tier 2, post-hoc: harness-level kills (covers P1, P3, P16)
No hook can see a sibling's harness kill inside the same SessionStart event: the groups run concurrently, and the harness writes `hook_cancelled` only after its (slipping) timer fires. So this tier has to run after the fact.
1. **START/END sentinels.** Each sync SessionStart hook (dispatcher, dod-persist, mailbox-drain, desk-brief-inject) appends `START` at entry and `END <bytes>` just before its final `printf`, to `~/.claude/logs/startup-health/<sid>.tsv`. These are one-line `printf >>` writes with O_APPEND. A `START` without an `END` means killed, whatever the signal.
2. **Persist-on-kill (dispatcher).** `trap 'save_partial; exit 143' TERM` writes the outputs of the children that *had* finished to `<sid>.lost.json`: the board, the recycle packet, the frontier line. Then nothing the dispatcher gathered is truly lost, only undelivered. If the harness uses SIGKILL (open question 1), the START-without-END sentinel still catches it.
3. **Reporter.** The dispatcher spawns a detached `startup-health-report <sid> <transcript_path> <t0>` (all fds closed, as `session-register.sh:644` already does). It waits for the session's SessionStart records (poll the transcript tail until every START has a matching `hook_success`/`hook_cancelled`, or until 60 s), then:
   - writes one IDL row per drop (`reason: harness-timeout:<hook>:<durationMs>/<timeoutMs>`);
   - writes `<sid>.flag` holding the one-line summary;
   - writes nothing at all on success.
4. **Surfacing the flag (0 tokens).**
   - (a) A `statusline.sh` segment that stats `<sid>.flag` (one `[ -f ]` per render) and shows `⚠ startup: 3 dropped — cc-startup-health`. It clears when the operator runs the recovery command, or after 15 min.
   - (b) Optionally, the first UserPromptSubmit boundary emits the same line once as a top-level `systemMessage`. `hook_system_message` renders as `<hookName> says: …` per the binary, but that it costs 0 tokens for UserPromptSubmit is unprobed (open question 2).
5. **Recovery command** `cc-startup-health [sid]` (read-only):
   - prints the lost systemMessage(s) to the terminal from `<sid>.lost.json` (the board);
   - lists each drop with its own prescription (table below);
   - prints the transcript evidence (`hook_cancelled` command, durationMs, timeoutMs).

| Dropped | Prescription printed (and auto-action, if any) |
|---|---|
| accounts board (dispatcher killed) | shown from `<sid>.lost.json`; live: `claude-accounts` |
| dod-persist | auto: re-injected at first prompt (§4.3); manual: `~/.claude/hooks/dod-persist.sh get` (read-only) |
| mailbox-drain | "deferred, not lost: re-delivers at next boundary"; read now: `cc-mail` |
| desk-brief-inject | auto: re-injected at first prompt (§4.3) |
| recycle-failed packet | auto: re-injected at first prompt (the packet stays un-stamped, because §5 R4 moves the stamp) |
| conditional dispatcher child | re-run it standalone with the saved payload under a generous bound, and print only its systemMessage (idempotent children only: activation-watch, escalation-watch, config-mirror-assert, frontier-status) |

### 4.3 Retry for model-needed payloads (P1: dod-persist, desk-brief-inject, recycle packet)
Content the model needs cannot be zero-token, but it must not vanish either. At the **first UserPromptSubmit** after a start whose flag names one of these hooks, re-run that hook's SessionStart *render* path and emit its additionalContext once. All three render paths are pure reads, apart from the recycle stamp that §5 R4 moves. The model then gets the DoD a turn late instead of never. In the 48 h window, 18 sessions started with no DoD.

### 4.4 Ledger and fleet detector
- **Ledger:** the existing IDL `~/.claude/autonomy/idl.jsonl` with `{ts, hook, sid, disposition, reason}` rows (`hooks/lib/idl-log.sh`). Readers already tolerate malformed lines and count them. New dispositions:
  - `dropped`: lost, needs action;
  - `deferred`: auto-retry pending;
  - `recovered`: the retry delivered.

  Plus **one `startup-health` summary row per start**, written by the reporter off the critical path: `{hook:"startup-health", disposition:"ok"|"dropped", reason:"<n> dropped", source, ms_max}`. That row is the denominator printing-gated transcripts cannot give (bias 1).
- **Detector:** a rule in `scripts/idl-abstain-alarm.sh`, or a sibling `scripts/startup-health-alarm.sh` run by the keepwarm producer. It is silent unless one of these holds:
  - (i) a `dropped` model-needed payload with no `recovered` row within its session;
  - (ii) a hook's drop share over a rolling 6 h is ≥ 2× its trailing 7-day share **and** ≥ 5 % with n ≥ 20;
  - (iii) a never-seen `(hook, reason-kind)` pair.

  When it trips, it renders **one line on the accounts board** (already shown at every start, 0 tokens). This is a fleet line, not a per-session one.
- **Alarm polarity.** Today about 29 % of starts would light the per-session line. That is too often to stay meaningful, so:
  - `deferred` items render nothing unless their retry fails;
  - the line names hooks and recoveries, never just a count;
  - the detector's thresholds are relative to the trailing baseline, so the sustained load-era rate does not page every night.

  The real cure for frequency is the latency work in the other axes. This tier only makes sure that what still drops is seen.

## 5. Recommendations

| id | Change | Impact | Effort | Risk | settings.json? | Conviction |
|---|---|---|---|---|---|---|
| R1 | Tier-1 in-band drop line + per-dropped-child IDL row in `session-start-dispatch.sh` (§4.1): kill markers at `:65`, drop list in the merge at `:79-91`, child-boundary cap at `:88`, static jq-less/mktemp fallback at `:46/:70`, malformed-JSON detection at `:82-85` | Makes the [E] ~50–65 child kills per 48 h (P2) and latent P4/P7–P11 loud and attributable; 0 tokens; < 10 ms [E] | S–M | Low: output-only change; must keep exit 0 and the single JSON object | No | 85 |
| R2 | Tier-2 sentinels + dispatcher TERM-trap persist-on-kill + detached reporter + `cc-startup-health` (§4.2) | Covers P1/P3: 56 harness cancels in 42 starts per 48 h become named and recoverable; the board survives a dispatcher kill (6 per 48 h) as a recovery file | M | Medium: one detached process per start (a sleep/poll, negligible CPU [E]); transcript tail read once | No (statusline.sh is a file, not settings) | 70 |
| R3 | First-prompt retry of model-needed payloads (dod-persist, desk-brief, recycle packet) when §4.2 flags them (§4.3) | 18 sessions per 48 h currently run with no DoD → DoD a turn late; tokens unchanged (same content, once) | M | Medium: must be exactly-once (stamp on `recovered` after emit-then-commit); adds a stat to the first prompt | **Yes, if a new UserPromptSubmit hook is registered (c10, operator-only)**; No if folded into an existing UPS hook (`session-beat.sh prompt`) | 70 |
| R4 | Fix stamp-before-delivery: dispatcher runs children's commit actions after its own `printf` (`recycle-failed-inject.sh:55-56`, `accounts-board.sh:122`); `mailbox-drain.sh:925` stamp moves after `:929` commit, and its `find -delete` (`:600`) goes off the emit→exit path | Closes 3 permanent-loss paths (P12) | S | Low | No | 80 |
| R5 | Retire `pre-session-validate.sh` from SessionStart, or re-target it to the running binary (resolve via `CC_HOOK_PARENT_PID`'s executable) and drop the 2 s `--version` spawn; remove or guard the `ln -sfn` actuator so a load false-negative cannot re-point `current` | Ends an alarm firing on 5.7 % of starts that nobody sees (P17); removes a `node --version` spawn per start ([E] 0.1–2 s CPU under load); removes a latent mis-rollback | S | Low: the binary it validates is not the one launched (`_claude_pinned` `_bin=$HOME/.claude-293/…`) | **Yes, to deregister (c10)**; No, to neuter in-file | 85 |
| R6 | IDL kill-honesty: `trap '…; exit 143' TERM` alongside every EXIT-trap IDL writer (`session-index-start.sh:17`; add it once in `hooks/lib/idl-log.sh` `idl_init`) | Kills recorded as `failed exit:143` instead of `passed exit:0` (P13); makes R1/R8 data trustworthy | S | Low: the TERM trap must still exit promptly | No | 80 |
| R7 | Async hygiene: async hooks write IDL rows, never stderr (P14/P16); silence the session-register job notice by wrapping `:608-614` in `{ …; } 2>/dev/null`; add a START/END pair to session-register like lead-crash-watchdog's register/spawn pair | Removes 32 noise records per 48 h that would swamp any stderr-based alarm; makes async kills measurable (now 0 records possible) | S | Low | No | 65 |
| R8 | Fleet detector + per-start summary row (§4.4), rendered as one accounts-board line when it trips | Fleet-level visibility with silence on baseline; denominator independent of printing | M | Low–medium: thresholds need a week of baseline before arming (shadow mode first) | No | 65 |
| R9 | Replace hand-built JSON (`setup-task-symlinks.sh:196`, `setup-plan-symlinks.sh:94`) with `jq -nc --arg`; the dispatcher stops injecting unparseable `{…}` as context | Closes P8 (0 fires; latent misroute plus tokens) | S | Low | No | 60 |
| R10 | dod-persist hard ceiling: the always-kept newest unit is clipped (with a "full text: <store path>" pointer) so the injection can never exceed 10,000 | Closes P5 for its only historical offender | S | Low | No | 55 |
| R11 | Upstream: ask Claude Code to render SessionStart (all events) timeouts like UserPromptSubmit's "timed out — output discarded" line | Would close P1's visibility at the source, for free | S (issue) | None | No | 60 (adoption uncertain) |

**What I would not do:** shorten timeouts or kill more aggressively to "avoid" drops. That trades a silent drop for a different one and breaks the operator's no-throttle constraint.

## 6. Open questions

1. Which signal does the harness use on a hook timeout? JTe maps `SIGTERM → 144` (`#w(e,n){…n==="SIGTERM"?144:1…}`), which suggests SIGTERM, but I did not confirm the kill call. If it is SIGKILL, R2's TERM-trap persist never runs and only the START/END sentinel catches the kill.
2. Is a UserPromptSubmit top-level `systemMessage` 0-token, as R5b proved for SessionStart? It renders (`hook_system_message` → `<hookName> says: …`), but the model-routing path was not probed for UPS. Probe it before choosing §4.2(4b) over the statusline.
3. Which conditional child is the 9 s victim (P2)? R1 answers this within a day of landing. Static candidates: activation-watch, escalation-watch, config-mirror-assert, recycle-failed-inject. session-index-start's IDL cannot exonerate itself until R6 lands (P13).
4. Does an async hook killed at its timeout produce any transcript record at all? None were seen in the window, and there is no positive control. A one-off probe hook with `sleep` past its async timeout in a scratch config dir would settle it.
5. Is `~/.claude-versions` still used by any launch path (e.g. launchd-launched `claude -p`)? If not, R5 can delete the hook outright rather than re-target it.
6. A3's per-child attribution (`a3_dispatch_census.py`) overlaps §2.3. Reconcile the "≥ 9 s ⇒ child killed" proxy with the histogram estimate here (84 at or above 9 s vs [E] about 50–65 excess at the bound).

## 7. Reproduce

```
python3 -I docs/research/startup-hooks-2026-10-18/a5_drop_census.py --since 2026-10-16T06:18:00Z
B=~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe
rg -a -o '.{0,400}case"hook_cancelled".{0,500}' "$B" | head -c 3000
rg -a -o '.{0,300}"async_hook_response".{0,700}' "$B" | head -c 9000
rg -c 'failed|broken' ~/.claude/logs/pre-session-validate.log
timeout -s TERM 1 /bin/bash -c 'trap "echo trap-rc=\$?" EXIT; sleep 3'
```

## Skeptic verdicts

Adversarial re-check, 2026-10-18 ~13:20Z. Read-only: no hook was executed. Re-run: the binary `rg -a` reads, the census, the IDL, the logs and the trap probe.

**Reproduction caveat (applies to every number above).** `/tmp/startup-hooks-census-files.txt` has gone stale. Since it was built, limit-recover moved sessions between config dirs. 9 of the 411 listed paths no longer exist, and other moved sessions left a stub at the old path. Example: `e52f1f63…jsonl` is 2,442 B in `.claude-quaternary` (0 cancels) and 497,376 B in `.claude-secondary` (9 `hook_cancelled`). Running §7 as written undercounts: 358 events, 47 cancels. Picking the largest copy of each basename across `~/.claude*/projects/<dir>/` and fixing the window to [2026-10-16T06:18Z, 2026-10-18T06:18Z) reproduces A5 exactly [M: inline python over the rebuilt list]: 370 events; 42 with a cancel; mailbox-drain 31, dod-persist 18, dispatcher 6, desk-brief 1; 364 dispatcher successes, 84 of them ≥ 9,000 ms; 53 async records (32 register, 21 validate); histogram bins 8.0/8.5/9.0/9.5 s = 6/9/38/29. The incident transcript is now at `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-….jsonl`.

**Deviation from the brief.** Scratch files were written under /tmp: `a5skeptic-files.txt`, `a5skeptic-files2.txt`, `a5skeptic-census.txt`, `a5skeptic-census2.txt`, and `a5sk_cancels.py`. The last was written with a heredoc, which the brief bans. None is tracked, and nothing else was written.

| id | verdict | severity | the gist |
|---|---|---|---|
| A5-F1 | amended | minor | Render rule and incident confirmed. The reporter design has three flaws (below) |
| A5-F2 | amended | major | "Unattributable" is wrong. 82 of the 84 bound runs are on the 3 isolated-projects accounts, so the victim is config-mirror-assert (as A2/A3 found). The kill estimate is about 80, not 50–65. The drop line would fire on ~45 % of starts on those accounts |
| A5-F3 | amended | minor | Claim confirmed. Prevention (emit before the deadline) should come before recovery files. The board can be regenerated |
| A5-F4 | amended | minor | Confirmed: 18 cancels. [E] about 15 of them actually owed a DoD. The UPS retry can read the transcript itself |
| A5-F5 | amended | minor | Lines confirmed. "Closes" should read "narrows". The recycle path is live: 3 packets on 2026-10-18 |
| A5-F6 | amended | minor | The rollback is currently unreachable (both fallbacks are MANIFEST-skip). Retiring the hook also drops the model guard, which has a latent symlink clobber |
| A5-F7 | amended | minor | Mechanism reproduced. "Unknowable" is overstated. The fix belongs at the call site, not in `idl_init` |
| A5-F8 | amended | minor | Routing confirmed. "No record for an async kill" is a static inference, not probed. Async records carry no `command` |
| A5-F9 | amended | minor | Relative-only thresholds absorb the sustained load-era rate. The statusline clear is time-based |
| A5-F10 | confirmed | none | Lines and counts as stated |

### A5-F1 — amended (minor)
- **Reproduced.** The 2.1.293 binary contains `case"hook_cancelled":{if(l.hookEvent!=="UserPromptSubmit"||!l.timedOut){return null}…`. The aborted branch yields only `hook_cancelled`, and stdout goes to `jc(...)` telemetry, not to context. The incident transcript has the 3 cancels (05:49:56/58, 05:50:01Z) and no SessionStart `hook_system_message` or `hook_additional_context` until the 13:17Z resume. Counts are exact on the stub-resolved list.
- **What is wrong with the recommendation.**
  1. A detached poller per start runs against the prior ruling in `docs/research/load-hook-timeouts-2026-10-11/DESIGN.md:231` ("every daemon is new load. Prefer lazy caches checked with builtin `-nt`") and `:173`, which replaces per-session pollers. `statusline.sh` already receives `transcript_path` and `session_id` (`statusline.sh:97-98`) and re-renders continuously. A once-per-sid scan of the transcript head for `hook_cancelled`, cached with `-nt`, needs no new process. So would the first UPS hook.
  2. The END sentinel is written only before the final `printf`. Abstain paths would then read as kills. The one desk-brief cancel (54b18e51, cancel recorded 04:12:42Z at 13,368 ms) had already logged IDL `abstained no-role-file` at 04:12:37Z, so nothing was lost. Every exit path must write `END 0`, and a cancel must be classified as a loss only when something was owed.
  3. The statusline flag clears itself after 15 min. That breaks the lesson "Clear must match occurrence" (`.claude/rules/agent-operating-lessons-situational.md:196`): a flag can die unread. Clear it on acknowledgment (running `cc-startup-health`) or at the session's next start.
- The upstream request stands.

### A5-F2 — amended (major)
- **Reproduced.** Histogram exact. The kill is at `session-start-dispatch.sh:65`. Split by account [M: inline python, dispatcher `hook_success` ≥ 9,000 ms by transcript config dir]:

  | account | runs | ≥ 9 s |
  |---|---|---|
  | `.claude` + next | 183 | 2 |
  | quaternary | 62 | 30 |
  | secondary | 71 | 38 |
  | tertiary | 48 | 14 |

- **The victim is attributable.** The pile-up sits on exactly the accounts whose isolate set runs `_cc_sync_memory_mirror` over ~18.9k slugs. A2 (M3/M4) and A3 (§2.3–2.5: mirror warning present in 190/284 runs under 8 s against 2/101 at ≥ 9 s; a read-only replica takes 7.6–8.8 s) both name `config-mirror-assert.sh`. So "nothing records which child" is true, but "unattributable" is false.
- **The estimate.** Non-isolated runs reach the bound about 1 % of the time, so [E] about 80 of the 84 bound runs are kills, not 50–65.
- **Partial output is not dropped.** A child killed mid-print leaves partial output in `$T/oNN`, and `:79-91` merges it. Malformed partial JSON then becomes plain context through `:82-85`.
- **Alarm polarity.** The proposed drop line would name config-mirror-assert on about 45 % of starts on 3 accounts. That is the always-firing alarm A5 §4.4 warns against. Land A2-F1/A3-R1 (precompute config-mirror) first, or alongside it. Or adopt A3-R4 (late children continue and get a ledger row), so the expected victim becomes "late", not "dropped".
- **Tests.** `tests/session-start-dispatch.bats:79` asserts a context of exactly 9,500 chars, so a child-boundary cut breaks it.

### A5-F3 — amended (minor)
- **Confirmed.** The single print is at `:92`, and the aborted branch discards stdout. 6 cancels: 12,261, 13,544, 15,622, 15,872 and 21,723 ms from my list, plus e52f1f63 at 12,352 per A3. The board was present in 364/364 successes.
- **Amendments.**
  - The board can be regenerated (`claude-accounts`) and re-renders at every start. The payload that cannot be regenerated is the recycle packet, and F5 plus next-boundary confirmation protects it better than a `.lost.json`.
  - Prevention should come first: emit by a deadline measured from process start (A3-R4), so the dispatcher has printed and exited well before 12 s.
  - Persist-on-kill depends on the harness signal, which is still unconfirmed. The value of R2 lies mostly in naming the loss.

### A5-F4 — amended (minor)
- **Confirmed.** `jq .hooks` shows `dod-persist.sh` only on SessionStart (5 s) and PreCompact (10 s). `mailbox-drain.sh prompt` is on UserPromptSubmit, so mail comes back at the first prompt. The `:922-930` order is as cited. 18 dod-persist cancels, all on `startup`.
- **How many owed a DoD.** [E] dod-persist printed on about 85 % of non-cancelled starts (census rerun: 304 printing records over 357 non-cancelled starts), so about 15 of the 18 sessions lost a DoD. "18 sessions" is an upper bound.
- **No reporter needed.** The retry does not need the F1 reporter's flag. A UPS hook already has `transcript_path` and can look for the session's own `hook_cancelled` (command `dod-persist.sh`) once.
- **Settings.** The edit is needed only for a new UPS registration (c10). Folding the retry into `session-beat.sh prompt` needs none.
- `dod-persist.sh get` exists (`:378-391`), so the recovery command is valid.

### A5-F5 — amended (minor)
- **Confirmed lines.**
  - recycle-failed-inject: prints at `:52`, stamps at `:55-56`.
  - accounts-board: the latch is written at `:122`. At `:123` the banner goes into the `DL_BANNER=$(…)` capture at `:134`. The real emit is `emit` at `:85`. The defect stands.
  - mailbox-drain: `printf` at `:924`, stamp at `:925`, `find -delete` at `:600`.
- **Live, not latent.** Three packets were injected on 2026-10-18 at 08:34:24, 12:50:07 and 13:17:38Z (b102f5af, 2ee922eb, 5759497b). All three reached the model (`hook_additional_context` contains "RECYCLE FAILED"). Each dispatcher ran 9,181–9,391 ms, 2.6–2.8 s under the harness kill [M: jq over the three transcripts].
- **"Closes" overstated.** Running the commits after the dispatcher's own `printf` only narrows the window, because the harness discards stdout that was fully written if it aborts before exit. Only a next-boundary confirmation closes it: the transcript shows the attachment, or a `.seen`→`.acked`-style promotion.
- **Same class.** `desk-brief-inject.sh:121-126` logs IDL `fired injected` after the print and before exit, a false-delivered ledger row if the harness cancels there.

### A5-F6 — amended (minor)
- **Reproduced.** The launcher is `~/.zshrc:502` `_bin="$HOME/.claude-293/node_modules/.bin/claude"`, and `~/.claude-versions/current` points to 2.1.114. 21/370 starts had the stderr [M]. The log holds 25 "no working fallback" lines in the 48 h window [M: awk on local timestamps]. `rg -c 'failed|broken'` now gives 585, over the whole log back to 2026-04-17, not the window.
- **Rollback unreachable today.** The log at 2026-10-18 06:12:56 reads "fallback skip 2.1.183 (MANIFEST status=skip)" and "fallback skip 2.1.113". So every failed probe ends at `:152-155`, and `ln -sfn` (`:159`) is reachable only if a new non-skip version dir appears.
- **Retiring the hook also retires the model-portability guard.** That guard is `:39-74`: a python3 spawn on every start, which fired 99 times, the last on 2026-09-27. It carries a latent silent hazard: `os.replace(tmp, p)` on `$CLAUDE_CONFIG_DIR/settings.json`, which is a symlink to `~/.claude/settings.json` on 4 of 5 config dirs. A replace there would silently de-link that account. Handle the guard explicitly, and do not delete it by accident.
- "Under load" is inferred, not measured: no load join was done. The intermittent pass pattern is consistent with it.

### A5-F7 — amended (minor)
- **Reproduced.** `/bin/bash` 3.2.57: `trap-rc=0`, and with a TERM trap `exit-trap-rc=143`. 387 `passed exit:0` rows in the window [M: `gzip -dc idl.jsonl.20261016T081034Z.gz idl.jsonl.20261018T105203Z.gz | rg session-index-start`]. The live `idl.jsonl` was rotated at 10:52Z, so the reproduction needs the archives.
- **Not unknowable.** A3 (§2.3, `a3_child_timing.py`) estimated it from IDL row timestamps against the dispatcher start: only 4 of 90 slow runs had session-index-start near the bound.
- **Wrong fix site.** `idl_init` is documented as having no side effects (`hooks/lib/idl-log.sh:65-77`) and has 15 users. Only `session-index-start.sh:17` derives its disposition from `$?` in an EXIT trap. One user, `goal-inert-watch.sh`, has its own TERM/INT trap, which a library-installed trap would collide with. Fix the call site.
- F2 does not depend on this: its drop list comes from the watchdog markers.

### A5-F8 — amended (minor)
- **Confirmed.**
  - `case"async_hook_response"` pushes only `systemMessage` and `additionalContext`, as isMeta. The render filter `(Wo)=>h||M&&Wo.hookEvent!=="SessionStart"` holds.
  - 53 records [M]. Lag p50 8.3 s, p90 54.2 s, max 387.1 s on the rerun.
  - lead-crash-watchdog: 388 registered and 388 spawned in the window, 0 unpaired [M: awk].
- **Not probed.** "An async kill produces no record type" is inferred from static reading only. The binary skips an attachment on an empty response ("produced no response payload — skipping attachment"), and its shutdown sweep reports `cancelled` only to `jc` telemetry. A5's own open question 4 still stands.
- **Missed attribution gap.** No `async_hook_response` record carries a `command` field: 0 of 53 [M]. The keys are exitCode, hookEvent, hookName, processId, response, stderr, stdout and type. Attribution rests on stderr text.
- **Unverified fix.** The `{ …; } 2>/dev/null` fix for session-register `:608-614` is untested. bash can print the job notice at a later notification point outside the group. Prove it in `tests/session-register-bg-fork.bats`.
- **Small operator impact.** Removing the 32 notices is near zero for the operator (the records are never shown and never sent to the model).

### A5-F9 — amended (minor)
- **Confirmed.** The lesson citation (`docs/lessons/a-rubric-that-saturates-has-not-ranked-anything.md:54-55`) and `scripts/idl-abstain-alarm.sh` both exist.
- **Amendments.**
  1. Rule (ii) is relative only (≥ 2× the trailing 7-day share). A sustained load-era drop rate becomes its own baseline and goes quiet while about 23 % of starts still lose a child. Add an absolute floor per hook for owed payloads, beyond rule (i).
  2. The per-start summary row should come from the lazy reader (statusline or first UPS), not a new detached process (DESIGN.md:231).
  3. The "29 %" counts every ≥ 9 s run as a loss. It is an upper bound: a killed config-mirror-assert that had nothing to say loses only side effects.
  4. The statusline clear must match the occurrence (F1 point 3).

### A5-F10 — confirmed (none)
- `setup-task-symlinks.sh:196` and `setup-plan-symlinks.sh:94` build JSON with `echo`. `session-start-dispatch.sh:82-85` sends unparseable output to plain context. `dod-persist.sh:257-259` always keeps the newest capture, so the 6,000 budget at `:303` is not a hard ceiling.
- 0 leaks and 0 cap hits on the rerun.
- A child killed mid-print (F2) is a live trigger for the same misroute.

### Missed by this axis
1. Attribution of the 9 s victim, which two sibling axes measured: config-mirror-assert on the isolated-projects accounts (82/84 [M]).
2. A harness cancel is not a loss. The desk-brief cancel was an IDL abstain, and the IDL can already classify some cancels.
3. Project-scope SessionStart hooks are killed silently too: a `bash -c '…unblock-sweep…'` one-liner, 3 cancels at a 20 s timeout (23–32 s), is missing from the §2.2 table.
4. asyncRewake (`mailbox-wake-arm.sh`, 14,400 s) is not enumerated, though the brief named it. A spent or killed watcher is re-armed at Stop, and mailbox-drain detects the missing arm (`:411-519`), but only as model context, never shown to the operator.
5. Async records carry no `command`.
6. The pre-session-validate model guard: a python3 spawn every start and a latent symlink clobber.
7. Partial output of a killed child is merged, not dropped.
8. desk-brief's post-print IDL `fired` row.
9. The recycle path is live: 3 packets on 2026-10-18.
10. §7 Reproduce does not reproduce as written, because of moved transcripts and stubs. The IDL was rotated, so the 385/387 count needs the `.gz` archives.
