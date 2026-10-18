# A9 — Beyond startup: the per-turn hook surface (latency, recurring token cost, silent drops)

Axis A9 of the 2026-10-18 startup-hooks study. Read-only: no hook was executed. Window: the 411 main
transcripts in `/tmp/startup-hooks-census-files.txt`, records with timestamp ≥ 2026-10-16T06:10Z
(48.0 h, through 2026-10-18T06:11Z). Machine load during the window ~500 (≈50/core), `uptime`
at 06:10Z read 496 / 500 / 535 [M].

## 0. Headline

1. **The per-turn surface costs about 3× as many model tokens as SessionStart, and most of it repeats text the model already has.**
   - UserPromptSubmit additionalContext was 2.66 M chars in 48 h, against 1.38 M chars of SessionStart additionalContext [M, §2.1].
   - 83% of the UPS chars (2.21 M) were injected on machine prompts (task-notifications, peer wakes), not on prompts the operator typed [M, §2.3].
   - The biggest item is one text, the mailbox-drain "wake path / your /goal WAS SKIPPED" block: 839 injections, 1.22 M chars, 73% of them byte-identical (digits normalised) to a copy already in the same context [M].
2. **Two staged-but-never-applied settings migrations account for a large part of the waste.**
   - 0012 would register `mailbox-wake-arm.sh` on Stop with asyncRewake. It has been staged since 2026-08-16 (`~/.claude/autonomy/migrations/staged/0012-mailbox-wake-arm-stop-rearm.json`).
   - The token-efficiency fix that makes the WAKE FLOOR stand down (`hooks/session-continue.sh:688`) keys on that registration, so the fix has been inert the whole time.
   - Result: 180 WAKE FLOOR forced turns in 48 h (263 k chars of block reasons) plus the per-prompt "no watcher armed" nags [M].
3. **One new definite silent drop of peer mail, with a one-line fix.**
   - `mailbox-drain.sh post-tool` is also registered on PostToolUseFailure, but it always answers `hookEventName: "PostToolUse"` (`hooks/mailbox-drain.sh:183`).
   - Claude Code rejects that output ("Hook returned incorrect event name"), and the drain has already committed `.seen` (`:922-929`).
   - So the mail is marked delivered and is never seen by the model. 13 drops in 48 h [M], including a lane's "DONE" ping to its lead (§4.2).
4. **Per-turn hook kills are invisible in the terminal.**
   - In the running binary (2.1.293), the `hook_cancelled` renderer returns null for every event except a timed-out UserPromptSubmit [M, §4.1].
   - In 48 h, 1,595 Stop, 127 PreToolUse, 50 TeammateIdle and 89 PostToolUse hook cancels left no operator-visible trace [M].
   - Among them are 186 completion-assert, 503 session-continue and 34 validate-bash runs. Those gates failed open.
5. **Latency per turn** [M, proxies, §3]:
   - Agent spawns wait p50 4.1 s / p90 5.6 s in their PreToolUse chain (agent-teams-enforce p50 2.8 s, 36% killed at 5 s).
   - Bash calls: p50 0.12 s, p95 1.05 s, p99 4.9 s.
   - Typed prompts wait p50 1.6 s / p90 4.8 s on UserPromptSubmit.
   - Stops run p50 6.4 s / p90 10.4 s. That is a lower bound from the slowest recorded hook per Stop.

## 1. Method

### 1.1 Inventory

`jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "*") as $m | .hooks[] | [$e,$m,(.timeout|tostring),(if .async then "async" elif .asyncRewake then "asyncRewake" else "sync" end),.command] | @tsv' ~/.claude/settings.json`

These are the per-turn events. All are sync. "null" means no timeout is declared, so the harness default applies (600 s for command hooks per vendor docs, cited in `docs/research/exhaustive-drive-2026-09-08/A12-upstream-features.md:56`).

| Event | Hooks (timeout s) | Fires per |
|---|---|---|
| UserPromptSubmit (7) | handed-off-session-guard 5 · cache-expiry-warning 5 · memory-nudge 5 · handoff-intent-nudge 5 · research-precognition-nudge 10 · session-beat prompt 5 · mailbox-drain prompt 5 | prompt (typed AND machine) |
| PreToolUse Bash (11) + `*` (1) | smart-bash-allowlist 5 · curl-gate-scope 5 · validate-bash 10 · git-worktree-guard 10 · keychain-guard null · rm-safe-allowlist 5 · ship-rail-push-allow 5 · qos-rewrite 10 · coldcompile-admit 10 · pr-gate null · research-block (`*`) 5 | Bash call: 12 processes |
| PreToolUse Write/Edit (4) | backup-before-write 10 · check-edit-boundary 10 · plan-agent-teams-default 5 · workflow-script-edit-allow 5 | +research-block |
| PreToolUse Agent (2) | agent-teams-enforce 5 · frontier-spawn-gate 5 | +research-block |
| PreToolUse other | enforce-email-formatting.py 10 (ms365 send/list/get) · cc-unattended-ask-guard 5 (AskUserQuestion) · web-entrypoint-ladder null (WebFetch/WebSearch) | |
| PostToolUse matcher-less (3) | teammate-checkpoint 10 · cc-permission-beacon clear 5 · mailbox-drain post-tool 5 | EVERY tool call |
| PostToolUse Bash (5) | log-bash 5 · waiting-recycle null · relay-verbatim 5 · memory-index-drain 10 (also Write/Edit) · bash-output-offload 10 | Bash: 8 processes post |
| PostToolUse Write/Edit (4+1) | post-file-edit 30 · plan-index-update 5 · validate-plan-structure 10 · plan-version-commit 10 · memory-index-drain 10 | Edit: 8 post |
| PostToolUse other | task-mutation-index 5 · plan-pin-session 5 · mail-images-auto null | |
| PostToolUseFailure (3) | log-bash 5 (Bash) · **mailbox-drain post-tool null** · cc-permission-beacon clear null | failed tool call |
| PostToolBatch | post-tool-batch 10 | batch |
| Stop (13) | notify complete 5 · cache-expiry-tracker 5 · teammate-checkpoint 10 · session-continue 5 · anti-deference-nudge 5 · completion-assert 5 · dispatch-assert 10 · boundary-handoff 5 · operator-readout 10 · session-beat stop 5 · goal-inert-watch 5 · handoff-claim-assert 10 · cc-permission-beacon clear 5 | Stop |
| SubagentStop | **none registered** (migration 0014 staged, not applied) | |
| Notification | notify.sh 5 + push-critical 6 (permission_prompt, elicitation_dialog); push-critical 6 (idle_prompt) | |
| PreCompact | `date >> sessions.log` 5 (auto, manual) · dod-persist 10 (auto) | |
| TeammateIdle | teammate-auto-shutdown 5 | |
| PermissionRequest (6) | notify ×3, cc-permission-beacon write, workflow-script-edit-allow, rm-prompt-preempt 10 | |

So a Bash call starts 20 hook processes (12 pre + 8 post), an Edit starts 13, and any other tool at least 4.

### 1.2 Helper scripts (all read-only, in this directory)

| Script | What it measures |
|---|---|
| `a9-turn-hook-census.py` | per (event, command): hook_success count, durationMs p50/p90/p99/max, cancels/timedOut, additionalContext / systemMessage / blocking-error chars, non-blocking errors; event-level hook_additional_context and hook_system_message totals; normalisers (prompts, tool_use by name) |
| `a9-ups-repeat.py` | model-facing hook text by category, REPEAT share (same category + digit-normalised body already injected in this transcript since the last compact boundary), and the split by triggering prompt kind (machine / human / queued-other) |
| `a9-repeat-by-cmd.py` | the same repeat measure for PreToolUse/PostToolUse, attributed to the command via hook_success stdout |
| `a9-chain-latency.py` | PreToolUse chain wall-time proxy per tool (last PreToolUse attachment ts − tool_use record ts); Stop: max hook durationMs per Stop |
| `a9-ups-latency.py` | UserPromptSubmit chain proxy (UPS attachment ts − prompt record ts) |

Run: `python3 -I <script> /tmp/startup-hooks-census-files.txt 2026-10-16T06:10:00Z`.

**Known biases** (these bound every number below):
- (a) CC records `hook_success` with durationMs only when the hook printed. So duration percentiles cover printing runs only. For mostly-silent hooks, cancels/48h is the only unbiased metric (memory `stop-hook-history-durations-are-biased-to-printers`).
- (b) No `hook_success` record exists for any UserPromptSubmit hook in this corpus (0 rows). UPS text is only visible as event-level `hook_additional_context`, so it is attributed to hooks by its text signature (§2.2).
- (c) Chain proxies use CC's attachment write time. They are only measurable when some hook in the chain printed: 7,174 of 17,835 Bash calls (40%).
- (d) Chars → tokens: no tokenizer was run. Tokens are given as a range, chars/4 to chars/2.6. The 2.6 figure is the /context ratio measured in `docs/research/token-efficiency-2026-09-23/BASELINE.md` for CLAUDE.md text.

### 1.3 Normalisers [M, a9-turn-hook-census.py]

- 2,208 string user prompts. 1,504 of them are '<'-prefixed machine prompts, and more machine prompts arrive as `queued_command` attachments.
- 23,236 tool calls: Bash 17,835 · Edit 2,196 · Read 1,245 · Write 647 · SendMessage 287 · Agent 258.
- About 1,640 Stops carried at least one hook record (`a9-chain-latency.py`).

## 2. Recurring token cost

### 2.1 Totals by channel, 48 h [M, a9-turn-hook-census.py, event-level records]

| Channel (reaches the model?) | records | chars | per day | tokens/day [E] |
|---|---|---|---|---|
| UserPromptSubmit additionalContext (yes) | 2,104 | 2,659,663 | 1.33 M | 330–510 k |
| PostToolUse additionalContext (yes) | ~480 | ~445 k | 0.22 M | 55–85 k |
| PreToolUse additionalContext (yes) | ~130 | ~134 k | 0.07 M | 17–26 k |
| Stop block reasons, `hook_blocking_error` (yes, **sent twice**: upstream #96909, `docs/research/token-efficiency-2026-09-23/REPORT.md` row 22) | 671 | ~565 k (Stop 563 k + 5 PostToolUse plan-structure blocks) | 0.28 M ×2 | 140–215 k |
| *for scale:* SessionStart additionalContext | 366 | 1,380,356 | 0.69 M | 170–265 k |
| Stop / UPS / PostToolUse `hook_system_message` (terminal only, 0 model tokens) | 1,757 | 1.48 M | — | 0 |

Per-turn model-facing total: about 2.2 M chars/day, roughly 3× SessionStart.
- Each injected block also stays in the context and is re-read (cache read) on every later API call until compaction. The fresh-token figures above are therefore a floor on billed cost.
- Each Stop block also forces one more model turn, which costs one full prefix read.

### 2.2 UserPromptSubmit text by producer [M, `a9-ups-repeat.py`; attribution by text signature]

| Producer (signature) | n | chars | repeat share | on machine prompts |
|---|---|---|---|---|
| mailbox-drain prompt: wake nag + goal-inert crumb ("🚨 YOUR /goal WAS SKIPPED…", `hooks/mailbox-drain.sh:576-591`) | 839 | 1,221,764 | **73%** (886,772 chars) | 833 / 839 |
| memory-nudge periodic "MEMORY INDEX BUDGET … MEMORY CHECK" (`hooks/memory-nudge.sh:790`, `:870`) | 132 | 525,982 | 48% | 118 / 132 |
| mailbox-drain prompt: peer-mail delivery | 193 | 358,330 | 2% | 188 / 193 |
| research-kit router "RESEARCH PROGRAM …" (`scripts/research-kit/router.py:1004`) | 161 | 138,324 | 0% | 3 / 161 |
| handoff-intent-nudge "HANDOFF-INTENT PARITY" | 146 | 118,990 | 15% | 13 / 146 |
| mailbox-drain: parked-watcher (`:533-538`) | 70 | 103,936 | 0% | queued |
| mailbox-drain: "no watcher armed" (`:559-560`) | 371 | 94,234 | 84% | 315 / 371 |
| research-precognition "RESEARCH-INTENT PRE-COGNITION" | 97 | 67,124 | 64% | 63 / 97 |
| mailbox-drain: goal-live-no-arm (`:554-555`) | 44 | 29,832 | 0% | 43 / 44 |
| cache-expiry-warning | 60 | 18,955 | 65% | 36 / 60 |

Readings:
- **The goal-inert crumb is the single largest recurring cost, and it is mostly noise.**
  - It is re-read from a file on every prompt for up to 6 h (`CC_GOAL_INERT_CRUMB_TTL_S`, default 21600, `:582`), and nothing dedupes it.
  - The header argues "SELF-LIMITING, not damped" (`:507-509`), but that self-limit is the condition clearing. While a long gate job runs in the background, the condition does not clear.
  - The sampled crumb's "deferring task" was a legitimate `uv run … pytest … && make check` gate run. The text tells the model to kill "the one that is a parker". So it repeats 1.3–1.4 k chars of advice that does not apply, on each task-notification, and that notification is the background task itself reporting.
- **memory-nudge counts every prompt, machine prompts included, toward its 12-prompt interval** (`hooks/memory-nudge.sh:146-154`).
  - So a session receiving task-notifications hits the periodic slot often.
  - The budget text is ~3.8–4.2 k chars even when the index is at 2,142 / 25,000 (9%). Most of it is fixed procedure: the UNITS note, FILING, the WHERE rules.
- The peer-mail wrapper carries ~700 chars of fixed text per delivery: the "📣 ACKNOWLEDGE IN CHAT" instruction plus the footer. 366 deliveries × ~700 ≈ 256 k chars per 48 h [E, from one sampled delivery's layout]. The message bodies themselves are needed.

### 2.3 Machine vs typed prompts [M, `a9-ups-repeat.py`]

UPS injections split by triggering prompt kind:
- machine: 1,607 injections, 2,206,767 chars
- human: 385, 318,867
- queued-other: 118, 142,957

**83% of UPS model-facing text rides on machine prompts.** At those boundaries the model is processing a background-task result, not a request from the operator.

### 2.4 PreToolUse / PostToolUse text [M, `a9-repeat-by-cmd.py`]

| Command | n | chars | repeat |
|---|---|---|---|
| PostToolUse mailbox-drain post-tool (peer mail) | 168 | 354,640 | 4% |
| PreToolUse plan-agent-teams-default ("PLAN DEFAULTS … Phase 0", "EXECUTION LOCUS …") | 67 | 75,648 | 30% |
| PreToolUse backup-before-write ("PLAN GUARD: … PLAN UPDATE RULES", "OVERWRITE GUARD") | 52 | 33,911 | 8% (the rules part is constant, keyed per file name) |
| PostToolUse relay-verbatim | 25 | 9,730 | 28% |
| PreToolUse agent-teams-enforce | 24 | 9,667 | 0% |
| CC-authored "PostToolUse hook modified … (likely a formatter)" after post-file-edit.sh reformats | ~250 | ~70 k | — |

These are small next to UPS. relay-verbatim already has an `if`-filter migration staged (0066, `docs/research/load-root-cause-2026-10-17/X18-if-probe.md`).

### 2.5 Stop block reasons [M, census + clustering of `hook_blocking_error`]

| Hook / reason class | n | chars | avg |
|---|---|---|---|
| session-continue "🔔 WAKE FLOOR" | 180 | 262,910 | 1,460 |
| completion-assert "your close reads as done…" | 92 | 69,604 | 756 |
| completion-assert "Origin-session close contr…" | 28 | 55,852 | 1,994 |
| session-continue "🔧 Loose ends remain" | 76 | 47,866 | 629 |
| session-continue "📦 SHIP FLOOR" | 58 | 36,031 | 621 |
| anti-deference-nudge (opaque-id, deference, category) | ~65 | ~46 k | ~700 |

Each block costs its chars twice (#96909) and forces one model turn.
- The 180 WAKE FLOOR turns exist only because migration 0012 is still staged: `hooks/session-continue.sh:652-691` abstains whenever mailbox-wake-arm is registered on Stop with asyncRewake.
- The token-efficiency study had already measured 342 of 381 WAKE FLOOR turns as waste-likely (OPPORTUNITIES row 20).

## 3. Latency per turn

| Chain | Proxy [M] | Source |
|---|---|---|
| PreToolUse, Agent | n=233: p50 4,104 ms · p75 5,210 · p90 5,597 · p95 6,131 · p99 9,269; Σ 1,009 s / 48 h | `a9-chain-latency.py` |
| PreToolUse, Bash | n=7,174 (40% coverage): p50 120 · p75 285 · p90 618 · p95 1,049 · p99 4,944 · max 98,555; Σ 3,046 s measured, ~7,500 s / 48 h over all 17,835 calls [E, ÷0.40 coverage, assuming unmeasured calls are similar] | same |
| PreToolUse, Edit / Write | p50 222 / 201 · p95 2,223 / 976 | same |
| UserPromptSubmit, typed prompts | n=382: p50 1,628 · p75 3,175 · p90 4,792 · p95 6,184 · p99 12,373 | `a9-ups-latency.py` (the machine-prompt proxy includes queue wait, so it is not used) |
| Stop (slowest recorded hook per Stop, a lower bound) | n=1,640: p50 6,362 · p75 10,138 · p90 10,420 · p95 10,574 · p99 11,332; Σ ≥ 11,087 s / 48 h | `a9-chain-latency.py` |

Hooks behind those numbers (printing runs only) [M, census]:
- **agent-teams-enforce**: p50 2,775 / p90 4,537 ms, and **84 of 233 Agent calls killed at 5 s (36%)**.
  - The cost is the capacity / lineage / duplicate-worker census (`hooks/agent-teams-enforce.sh:236-300`, `cc_capacity_admit` in `scripts/lib/capacity-admit.sh`), on top of ~10 separate `jq` parses of `$INPUT` (`:39-45`, `:177`, `:179`, `:280`, `:432-433`, `:545`, `:591`).
- **validate-bash**: p50 479, p99 7,340 ms; 34 killed at 10 s.
- **smart-bash-allowlist**: p50 109, p99 1,763 ms; 3 killed.
- **operator-readout (Stop)**: p50 3,702, p90 6,825 ms; **686 killed of ~1,498 runs (46%)** at load ~500. Waves 4/4b/4c fixed it at load ≤ 90 (`docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md` Wave 4c tables); at load ~500 it still loses half its runs.
- **session-continue (Stop)**: p50 1,679 ms; **503 killed**.
- **goal-inert-watch**: p50 1,100 ms.
- **teammate-auto-shutdown (TeammateIdle)**: p50 1,270 ms; **50 killed of 108**.
- **post-file-edit (PostToolUse)**: p99 7,436, max 13,212 ms (timeout 30).
- **memory-index-drain**: p50 1,647 ms (8 printing runs).

UPS cancels (these are the only kills CC does render) [M]: mailbox-drain prompt 34 · memory-nudge 15 · research-precognition 3 · cache-expiry-warning 1. The Wave 1 work had driven these to 0 at load 520-680 on 10-12; they are back at a lower rate.

## 4. Silent-drop paths

### 4.1 What the operator sees when a per-turn hook is killed

Read from the binary that the live sessions run. Transcript `version` fields show 2.1.293 / 2.1.291; processes run `~/.claude-293/node_modules/.bin/claude`.

`rg -a -o 'case"hook_cancelled":\{if\(l.hookEvent!=="UserPromptSubmit".{0,700}' $(readlink -f ~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe)`
→ `case"hook_cancelled":{if(l.hookEvent!=="UserPromptSubmit"||!l.timedOut){return null} … " timed out … — output discarded. Raise the hook's \"timeout\" …"`

`case"hook_non_blocking_error":{if(l.hookEvent==="Stop"||l.hookEvent==="SubagentStop"){return null} … [hookName," hook error"] …`

So:
- A timed-out UserPromptSubmit hook is rendered, with its command.
- **Every other event's kill renders nothing.**
- A non-blocking error renders as "<hookName> hook error" except on Stop / SubagentStop.

The 2.1.260 reading in `docs/research/exhaustive-drive-2026-09-08/A01-stop-hook-timeout-decay.md:31-36` still holds on 2.1.293.

### 4.2 Drop paths, measured over 48 h [M, census; `jq … select(.attachment.type=="hook_cancelled")`]

| # | Path | Count / 48 h | What is lost | Visible? |
|---|---|---|---|---|
| D1 | **mailbox-drain post-tool on PostToolUseFailure returns `hookEventName:"PostToolUse"`** (`hooks/mailbox-drain.sh:183`, emits `:922-923`, commits `.seen` `:927-929`) | **13** | The peer message itself: CC rejects the whole JSON, but `.seen` is already committed. The next Stop's `mailbox_promote_acked` makes it consumed. Traced: "From r13-RB … sent 22:18" (dropped 2026-10-17T04:05:32Z in session dfdeb01c and 04:05:33Z in b02c91f3) and "lane P · DONE —" (dropped 2026-10-14T04:09:13Z in b351c528). None of the three surfaced again in those transcripts. | Operator sees a red "PostToolUseFailure:Bash hook error" line holding the rejected JSON. The model sees nothing. |
| D2 | Stop gates killed | completion-assert 186 · session-continue 503 · boundary-handoff 123 · anti-deference 21 · dispatch-assert 10 · handoff-claim-assert 4 | A block verdict. The gate fails open; the 10-15 replays found 7 of 8 kills "would have answered block" (`LOAD_AND_PROMPT_HOOK_TIMEOUTS.md` completion-assert second pass) | **No** |
| D3 | Stop renderers killed | operator-readout 686 · goal-inert-watch 29 · notify complete 5 | The operator board / the goal-inert notice / the desktop notification | **No** |
| D4 | Stop side-effects killed | teammate-checkpoint 8 · session-beat stop 1 | A WIP checkpoint (data safety); the turn beat that cc-await-ping's arm baseline reads | **No** |
| D5 | PreToolUse gates killed | agent-teams-enforce 84 · validate-bash 34 · research-block 4 · smart-bash-allowlist 3 · 2 tmp test scripts | Admission / safety verdicts: the tool ran ungated (allowlist: falls back to prompting) | **No** |
| D6 | TeammateIdle killed | teammate-auto-shutdown 50 | The idle teammate is not shut down | **No** |
| D7 | PostToolUse / PostToolUseFailure **aborted, no `command`, `timedOut` null** | 80 + 9 (PostToolUse:Bash 55, :Edit 18, …) | Unknown: CC does not record which hook was aborted. An attribution gap on CC's side | **No** |
| D8 | UPS hooks killed | 53 | Their text; mail is safe (emit-then-commit, `:276-285`) | Yes, CC renders it |

Total invisible per-turn kills: 1,842 / 48 h, roughly 920 a day [M, sum of D2–D7: 847 + 720 + 9 + 127 + 50 + 89].

## 5. Recommendations

Every recommendation keeps live work untouched: no throttling, capping, killing or demoting of
sessions. "c10" means a settings.json edit that only the operator may apply.

### R1 — mailbox-drain answers with the event it was called for (closes D1) · S · no settings · conviction 95
- **Change** `hooks/mailbox-drain.sh:181-185`:
  - Take `EVENT` from the stdin payload's `hook_event_name` when it is one of PostToolUse / PostToolUseFailure / UserPromptSubmit / SessionStart. The hook already parses stdin once (the WP4 one-jq parse), so add the field to that parse.
  - Fall back to the MODE mapping otherwise.
  - The emits at `:623` and `:922` then echo the right name.
- **Belt and braces**: if CC rejects an output that was already printed, the commit at `:927` still happens. Making the event name right removes the only measured rejection cause.
- **Test**: a bats case feeds a PostToolUseFailure payload with pending mail and asserts `hookSpecificOutput.hookEventName=="PostToolUseFailure"`. A mutant restoring the constant must fail it.
- **Impact**: 13 peer-message drops / 48 h → 0.
- **Risk**: very low.

### R2 — the wake nag and goal-inert crumb become state-change notices, not per-prompt repeats · S–M · no settings · conviction 85
- **Change** `hooks/mailbox-drain.sh:576-591` (crumb), `:526-539` (parked watcher), `:559-560` (no watcher):
  - Emit the full text once per (session id, state key). The state key is the crumb's mtime + deferrer count for the crumb, the watcher pid for the parked watcher, and a per-session "unwatched since" stamp for the nag.
  - Store the marker beside the existing `.goalnudge/` markers (`:546-552`, which already do this for the goal-live nudge). Stamp only after an emit has printed (`_goalnudge_stamp`'s rule, `:597-601`).
  - On later prompts with the same state, emit nothing on machine prompts. On typed prompts, emit at most a one-line pointer (≤120 chars, e.g. `🚨 goal still skipped — see the earlier 🚨 notice; fix: cc-await-ping --stand-down`).
  - Re-emit the full text after a compact boundary, which the hook can detect from the transcript offset it already keeps for `goal_live_condition`.
  - Cut the crumb's `cause` (the full background command line) to 120 chars.
- **Impact**: about 0.89 M chars / 48 h of measured repeats, ≈ 110–170 k tokens/day fresh [E: 886,772 chars ÷ 2 days ÷ 2.6–4]. The re-read of each repeat on later calls comes on top.
- **Risk**:
  - The model acts on a single notice less reliably than on a repeated one. Mitigate by keeping the typed-prompt pointer and re-emitting after compaction.
  - Measure with the existing IDL rows: goal-inert crumbs cleared within N turns, before and after.

### R3 — apply staged migration 0012 (mailbox-wake-arm on Stop, asyncRewake) · S · **c10 settings edit (operator)** · conviction 80
- **Why**:
  - It has been staged since 2026-08-16 (`~/.claude/autonomy/migrations/staged/0012-mailbox-wake-arm-stop-rearm.json`).
  - The WAKE FLOOR abstain at `hooks/session-continue.sh:688` and the per-prompt "no watcher armed" nag both exist because no Stop-time arm is registered.
  - The semantics were probed (P-W2a–d, `migrations/0012-mailbox-wake-arm-stop-rearm.sh:20-33`), and the duplicate-watcher edge (P-W2c) is handled by the claim guard in `hooks/mailbox-wake-arm.sh`.
- **Impact**:
  - −180 forced model turns / 48 h and −263 k chars of WAKE FLOOR reasons, sent twice, so ≈ 65–100 k tokens/day of reason text [E].
  - Plus one full prefix read per avoided turn.
  - Plus most of the 371 "no watcher armed" UPS nags (94 k chars).
- **Risk**:
  - A Stop-time background watcher defers /goal evaluation. That is the reason the model-armed path must be `--idle-scoped` under a goal.
  - The 0012 text says an asyncRewake hook "is not a background Bash task, so it does not suspend /goal evaluation" (`session-continue.sh:684-685`). Re-verify this on 2.1.293 before applying (§6 Q1).

### R4 — memory-nudge: count typed prompts only, budget line only near the cap, procedure by pointer · S · no settings · conviction 75
- **Change** `hooks/memory-nudge.sh`:
  - Skip the counter increment for '<'-prefixed prompts (`:146-150`; the same predicate the shadow classifier uses at `:62`).
  - Print `BUDGET_CTX` (`:790`) only when TOTAL ≥ 80% of LIMIT or LINES ≥ 80% of LINE_LIMIT. It is already raised on overflow.
  - Replace the ~2.5 k chars of fixed procedure in `NUDGE` (`:870`: the WHERE / FILING / UNITS rules) with a one-line pointer to a doc or skill that holds it verbatim.
- **Impact**: 471 k of 526 k chars / 48 h were on machine prompts. Expected cut 0.4–0.5 M chars / 48 h ≈ 50–95 k tokens/day [E].
- **Risk**: fewer periodic memory saves. Compare IDL `fired` rows and memory-file creation rate over a week. `scripts/idl-expected-fires.tsv` must be updated in the same commit (WP3 note).

### R5 — make every per-turn kill loud, attributed and prescribed: a cancel relay · M · no settings · conviction 80
- **Problem**: CC writes `hook_cancelled` / `hook_non_blocking_error` records with the command, timeout and duration into the session's own transcript, but renders almost none of them (§4.1).
- **Change**: add a reader that runs at existing boundaries. Fold it into an existing hook rather than adding one; `session-beat.sh prompt` already detaches its work, which suits this.
  - Keep a per-transcript byte-offset cursor. This is the same incremental pattern as `goal_live_condition`'s offset (WP4).
  - Grep only the new bytes for `"hook_cancelled"|"hook_non_blocking_error"`.
  - Then:
    1. Append each record to a fleet ledger `~/.claude/state/hook-kills.jsonl` (session, event, command, timeoutMs, durationMs, ts).
    2. Print ONE operator-facing **top-level `systemMessage`** line at the next UserPromptSubmit. That channel is rendered in the terminal and costs 0 model tokens (it is how peer-mail headlines already render, 333 UPS systemMessages in 48 h). Example: `⚠ 3 hooks killed since your last prompt: completion-assert.sh (Stop, 5 s) ×2 — your last close was NOT checked; operator-readout.sh (Stop, 10 s) — board skipped.`
    3. Add model-facing additionalContext only when the dropped verdict changes what the model should do. completion-assert or session-continue killed → one line: "the close gate did not run on your last stop; re-check the close against the ledger". Renderers and side-effect hooks never get model text.
  - The prescriptions live in a small table keyed by command, so each line names its recovery.
  - The SessionStart dispatcher and the accounts board can show the ledger's last-24 h count per hook.
- **Impact**: closes the invisibility of D2–D7, about 920 kills a day, with attribution. D7 stays unattributed (no command recorded); report it as "N PostToolUse hooks aborted (CC did not say which)".
- **Risk**: low. It reads only new transcript bytes, and a missed record is reported at the next boundary instead.

### R6 — a deadline-aware hook wrapper: speak before the harness kills you · M · no settings · conviction 70
- **Change**: add a lib, e.g. `hooks/lib/hook-deadline.sh`, that a sync hook sources first.
  - It runs the body in a background subshell writing to a temp file, and waits until `timeout − 1 s`. Use bash 3.2-safe integer `read -t` on a FIFO, never `sleep` loops that fork.
  - On deadline it prints a named, loud fallback instead of being SIGKILLed mid-write:
    - Renderers: an operator systemMessage "<hook> deferred under load (Ns) — will show at next boundary". The detached body keeps running under its own longer deadline and leaves its finished output in a per-session pending file, which the next boundary prints.
    - Gates: the R5 ledger row plus the model line.
- **Pilots**: operator-readout (46% killed) and teammate-auto-shutdown (46%).
- **Impact**: turns D3 / D6 kills into late delivery, not loss. It also caps the Stop chain's critical path at the deadline.
- **Risk**: medium. Detached work must stay single-flight per session; keep the existing memo / single-flight keys.

### R7 — move Stop *advisory gates* off the critical path with asyncRewake · M · **c10 settings edit** · conviction 55
- **Change**: register completion-assert, anti-deference-nudge, boundary-handoff, dispatch-assert and handoff-claim-assert as `asyncRewake: true`, with an internal deadline (e.g. 60 s) and single-flight per session.
  - A block becomes `exit 2` + reason on stderr, which P-W2b proved synthesizes a wake turn carrying it.
  - An allow becomes `exit 0`.
  - The block already renders after the misleading close (`docs/research/close-verdict-first-2026-10-10/REPORT.md` R1), so what the operator sees barely changes.
  - The verdict arrives late instead of being killed at 5 s: 344 gate kills / 48 h.
- **Impact**: −344 gate kills / 48 h. The Stop chain loses five of its 13 hooks.
- **Risk**: medium.
  - The 10-11 DESIGN rejected `async: true` for heavy hooks ("no enforced timeout, runs pile up"). The internal deadline plus single-flight answer that, but it must be proven.
  - Re-probe the asyncRewake Stop semantics on 2.1.293.
  - Keep session-continue sync, because its block is the drive mechanism.

### R8 — Agent spawn latency: stop re-deriving the census inside the 5 s gate · M · no settings · conviction 60
- **Change** in agent-teams-enforce:
  - Read the payload with one `jq @tsv` instead of ~10 jq forks (`:39-45` …).
  - Have `cc_capacity_admit` read a fresh-enough sample (≤ 15 s) from an already-running sampler (`scripts/capacity-alarm.sh` writes `capacity-alarm.jsonl`) before computing its own.
  - No policy change: same terms, same thresholds.
- **Impact**: the Agent PreToolUse chain is p50 4.1 s today. Removing the census from the critical path should bring it under 1 s [E], and stops 36% of spawns bypassing the gate unseen.
- **Risk**: the gate will then actually decide on calls that today fail open, so refusals may rise. That is the gate's existing policy, not a new throttle, but the operator should know (§6 Q3).

### R9 — validate-bash kills (34 / 48 h) need a slow-path trace · S (measure) · no settings · conviction 50
- **Problem**: this is the one deny gate in the Bash chain that is killed regularly.
- **Change**: replay the 34 cancelled calls with `cutreplay.py`, which already exists, to find the slow rule, the same way Wave 4b did.
- **Impact**: closes the ungated-Bash path (D5).
- **Risk**: none (measurement).

### R10 — small trims · S · conviction 60
- **plan-agent-teams-default / backup-before-write**: the constant "PLAN DEFAULTS" / "PLAN UPDATE RULES" text once per (session, plan file); 30% / 8% repeats today.
- **The peer-mail "ACKNOWLEDGE IN CHAT" instruction** (~700 chars per delivery): once per context; later deliveries carry a ≤80-char reminder (≈ 0.25 M chars / 48 h [E]).
- **research-kit router**: emit nothing when the route is "other: normal handling" (47 of 161 sampled lines are that class).
- **TeammateIdle timeout 5 → 20** (c10): the teammate is already idle, so a longer bound costs nobody latency. Measured 46% kill rate.

## 6. Open questions

1. Does an asyncRewake hook on **Stop** suspend /goal evaluation on 2.1.293? R3's premise (`session-continue.sh:684-685`) was probed on 2.1.233. CC's goal skip keys on "non-terminal background Bash", and an asyncRewake hook is not a Bash task, but this needs a re-probe before the operator applies 0012.
2. Why has 0012 stayed staged for two months? It may have been held on purpose (no decision row was found in this pass). The same question applies to 0014 (SubagentStop) and 0066 (`if` filters).
3. If agent-teams-enforce becomes fast (R8), it will refuse spawns it currently lets through by timing out. Is that acceptable under the "never throttle live work" constraint, or should the capacity term be re-ruled?
4. D7: which PostToolUse hooks are the 89 aborted runs? CC records no command. An upstream ask (include `command` on abort-cancel records) is the only attribution path.
5. UPS chain latency for machine prompts cannot be read from timestamps (queued_command is written at enqueue). A per-hook start/end stamp written by the hooks themselves would give it.
6. Durations of silent hooks (most Stop gates, most PreToolUse gates) are not measurable from transcripts. R5's ledger gives kill counts. A per-hook `EPOCHREALTIME` stamp in the IDL rows would give true percentiles.
