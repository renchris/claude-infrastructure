# A4 — Tokens: what SessionStart hooks put into model context, and what can go to zero

Axis A4 of the 2026-10-18 startup-hooks study. Read-only: no hook was executed. Only one helper script
was authored: `a4_tokens_census.py`, in this directory.

## Answer first

- **SessionStart hooks inject a mean of 3,622 chars per session start (p50 2,467, p90 6,798, max 9,473),
  about 1,450 tokens** [M census below; tokens E at 2.5 chars/token]. Over the last 48 h that is
  ~186 starts/day, or ~270k tokens/day written into context. Each of those tokens is then re-read on
  every later request of the session.
- **One hook is 74% of it.** `dod-persist.sh` contributes 2,677 of the 3,622 chars per start. When it
  injects a contract, **80% of that block (4,183 of 5,212 chars) is a "history" body.** The hook's own
  frame calls that body "prior CONTEXT, NOT additional binding scope".
- **That history is also misdirecting.** 120 TrueMemory plan sessions in the `tm2-plan` worktree were
  told that a FLEET_V2 contract "binds you". The lineage rule treats the main checkout as a recorded
  predecessor, so every capture ever written there is admitted.
- **Four of the dispatcher's one-liners carry no information in nearly every session:**
  - Frontier line, 270 chars: restates CLAUDE.md:130-145, and holes=0 in 404/404.
  - MCP line, 69 chars: the probe found servers connected in 406/406.
  - Tasks line, 94 chars: "0 active" in 358/406.
  - Plans line: 135 chars of fixed help text in 407/407.
- **mailbox-drain's no-mail "No inbox wake path armed" nag fires at 270 of 413 starts.** In 263 of 269
  checked sessions it was a race: `mailbox-wake-arm.sh` arms the watcher mechanically in the same
  SessionStart, and the drain at the first prompt found it armed.
- **Fixing these six items removes ≈2,970 chars (≈1,190 tokens) per start, an 82% cut**
  [E, derived from M counts]. That is ≈221k tokens/day written and, at the measured ~90 re-reads per
  item, ≈20M cache-read tokens/day [E]. None of the fixes needs a settings.json edit, and none touches
  live session work.
- **Precondition for the "silent when healthy" rows: the dispatcher must report killed children
  loudly.** Today a killed child is dropped with no record (session-start-dispatch.sh:61-68). If a line
  only appears when something is wrong, a killed child then looks exactly like a healthy silent one.
- **Startup hook context is small next to the static startup context.** Hooks are ~3.6k chars out of
  ~140k chars of startup attachments: instructions 94.9k, skill listing 27.5k, deferred tools 10.8k,
  agent listing 5.3k, MCP instructions 2.8k [M]. The hook work is still worth doing, because hooks are
  the part this repo controls per session, and they are where the misdirection is.

## 1. Method

**Corpus.** `/tmp/startup-hooks-census-files.txt`: 411 main transcripts modified in the last 2 days
(subagents excluded).

**Census script.** `docs/research/startup-hooks-2026-10-18/a4_tokens_census.py`, run as
`python3 -I a4_tokens_census.py > /tmp/a4-census.json`. It writes per-event JSON to stdout and the
tables to stderr. It works as follows:

- **Grouping into events.** One SessionStart event is one `toolUseID`, shared by its
  `hook_success` / `hook_cancelled` / `hook_system_message` records. The merged
  `hook_additional_context` record has `toolUseID:"SessionStart"` and follows immediately, so it is
  attached to the event just before it. Result: **413 events** (startup 383, resume 28, clear 1, fork 1).
  409 of them carry context.
- **What the model is billed for** is `hook_additional_context.content[]`, one element per hook.
  Claude Code 2.1.293 renders it as `${hookName} hook additional context: ${content.join("\n")}` in a meta
  message. [M] `rg -a -o 'hook_additional_context:\(e\)=>.{0,120}'` on
  `~/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe`; that binary runs 38 of the live
  `claude` processes, per `ps -axo command=`.
- **Per-hook attribution** matches each element against the `additionalContext` parsed from that event's
  `hook_success.stdout`. Where that record is missing it falls back to the hook's signature.
- **Per-child attribution inside the dispatcher.** Children are merged with `"\n"`
  (session-start-dispatch.sh:79-91). Each line is classified by the first-line signature I read in each
  child's emit code:

  | signature | child |
  |---|---|
  | `MCP: ` / `WARNING: CLAUDE_CODE_EFFORT_LEVEL` | session-start.sh:419-427, 464-471 |
  | `Plans: ` | setup-plan-symlinks.sh:94 |
  | `Tasks: ` | setup-task-symlinks.sh:190-196 |
  | `Frontier: ` | frontier-status.sh:35-39 |
  | `Session index` | session-index-start.sh:37-62 |
  | `RECYCLE FAILED` | recycle-failed-inject.sh:49-52 |

  activation-watch, escalation-watch, accounts-board and config-mirror-assert emit only a top-level
  `systemMessage`, which costs 0 tokens (activation-watch.sh:111-117, escalation-watch.sh:65-72,
  accounts-board.sh:84-85, config-mirror-assert.sh:104-111).
- **Unattributed bytes:** 1 element, 2,084 chars. It is a pre-budget 2026-10-01 dod-persist
  `<persisted-output>` preview, so it is historical.

**Conversions and rates.**

- **Chars to tokens: 2.5** [E]. This ratio was fitted in docs/research/token-efficiency-2026-09-23/measure/hooks.md:75-77.
  Emoji and box glyphs tokenize denser, so tokens are an estimate throughout.
- **Re-read multiplier: ≈80-96 later responses per SessionStart item** [M in that report's table at
  hooks.md:82-99: dod 96, frontier 82, mail 98]. The re-read figures here use ≈90.
- **Starts per day: 186.** [M] `jq '[.events[]|select(.ts>="2026-10-16T05:49")]|length'` gives 371 events
  in the last 48 h.

**Known bias.** `hook_success` is recorded only when a hook prints something. A hook that printed nothing,
or was killed, leaves no attribution record. Every byte that reached the model is still counted, because
the `content[]` array is the billed surface.

## 2. Measurements

### 2.1 Totals per start [M, census script]

| source | n | mean chars | p50 | p90 |
|---|---:|---:|---:|---:|
| all | 413 | 3,622 | 2,467 | 6,798 |
| startup | 383 | 3,765 | 2,468 | 6,798 |
| resume | 28 | 1,660 | 882 | 3,787 |
| clear | 1 | 5,500 | | |
| fork | 1 | 1,934 | | |

- **compact:** 0 `SessionStart:compact` records in the corpus [M] (`rg -l 'SessionStart:compact'` over the
  list returns 0).
- **clear:** /clear is rare here (1 event).
- So source-gating mostly concerns **resume**, at 6.8% of starts.

The top-level `systemMessage` volume (0 model tokens) is 2,253 chars per start on average [M], almost all
of it the accounts board.

### 2.2 Per hook and per dispatcher child [M, census script]

| component | present in events | mean chars when present | p50 | p90 | chars/start (all 413) | share |
|---|---:|---:|---:|---:|---:|---:|
| **dod-persist.sh** (sync, separate) | 316 (76.5%) | 3,498 | 4,597 | 5,936 | **2,677** | 73.9% |
| mailbox-drain.sh session-start (sync, separate) | 294 (71.2%) | 447 | 254 | 254 | 318 | 8.8% |
| dispatch / frontier-status.sh | 404 (97.8%) | 270 | 270 | 270 | 264 | 7.3% |
| dispatch / setup-plan-symlinks.sh | 404 | 182 | 179 | 191 | 178 | 4.9% |
| dispatch / setup-task-symlinks.sh | 404 | 94 | 92 | 106 | 92 | 2.5% |
| dispatch / session-start.sh (MCP line) | 403 | 69 | 69 | 70 | 68 | 1.9% |
| dispatch / session-index-start.sh | 0 | | | | 0 | |
| dispatch / recycle-failed-inject.sh | 0 | | | | 0 | |
| desk-brief-inject.sh (sync, separate) | 0 | | | | 0 | |
| dispatch / activation-watch, escalation-watch, accounts-board, config-mirror-assert | systemMessage only | | | | 0 | |
| async (pre-session-validate, lead-crash-watchdog, session-register, live-session-registry, net-context-stamp) and mailbox-wake-arm | 0 | | | | 0 | |
| legacy per-hook layout (old transcripts) | 3-4 | | | | ~22 | 0.6% |

**Notes on the zero rows.**

- **session-index-start.sh:** its empty-index filter (session-index-start.sh:39-50) suppressed it in every
  event.
- **desk-brief-inject.sh:** never fired (no pane holds the desk role). When it does fire it injects the
  7,564-byte brief plus a frame [M] (`wc -c docs/templates/desk-boot-brief.md`).
- **recycle-failed-inject.sh:** 3 packets exist [M] (`ls ~/.claude/autonomy/recycle-failed | wc -l`).
- **Async hooks** reach the model only through `response.systemMessage` / `additionalContext`, never
  through stderr [M, binary: `case"async_hook_response":{let s=e.response … systemMessage … additionalContext`].
  All 56 `async_hook_response` records in the corpus have `response:{}` and stderr only: the
  pre-session-validate "no working version" warning and session-register's `Killed: 9`. They cost 0
  tokens, and they are also invisible to the operator (see open question 3).

### 2.3 Variants inside the big two [M]

**dod-persist.sh**, 316 injections:

- **Lineage contract: 205, mean 5,212 chars.**
  - Frame up to the first `## ` capture: 1,029 chars.
  - Contract head (text before `Below: the newest`): 638 chars.
  - History body: **4,183 chars**.
  - 151 of the 205 show "the newest 9 of 38 captures".
- **Negative notice: 111, mean 333 chars.** It reads "Durable frozen DoD: no capture in the store
  belongs to this session … so none is injected … Store: …" (dod-persist.sh:322-325). It tells the model
  that nothing is there.
- **Distinct contracts across the 205** [M] (`rg`/`jq` over the content):

  | sessions | contract |
  |---:|---|
  | 152 | FLEET_V2 origin lead |
  | 23 | corporate Mac v9 bring-back |
  | 19 | Perrier-Jouët/Moët bottles |
  | 8 | launch film |
  | 3 | other |

- **Where they landed:** 120 of the FLEET_V2 injections went to `-worktrees-tm2-plan` sessions. Sampled
  first prompts are "TrueMemory 2.0 research program …" and "Is this all before we close?", which are
  unrelated work.
  - Cause: `~/.claude/autonomy/dod/lineage.tsv:2565,2610,2611,2958` record
    `claude-infrastructure → tm2-plan` fire edges.
  - So the predecessor-toplevel rule (dod-persist.sh:231-238, lib/dod-path.sh:114-125) admits every
    capture ever written in the main checkout, by any session and any wave.

**mailbox-drain.sh session-start**, 294 injections:

| variant | count | size |
|---|---:|---|
| no-mail wake nag | 270 | 254 chars (mailbox-drain.sh:558-561, emitted at :620-625) |
| real peer mail | 22 | |
| parked-watcher alarm | 2 | |

**Is the startup nag a race?** I cross-tabbed each transcript's SessionStart nag against its first
UserPromptSubmit `hook_additional_context` [M, jq over the list]:

| SessionStart nag | first prompt | transcripts |
|---|---|---:|
| nag | no context at all, so the per-prompt drain did not nag and the watcher was armed | 263 |
| nag | nag again | 6 |
| no nag | nag | 13 |
| no nag | none | 129 |

This is consistent with mailbox-wake-arm.sh:1-8: it is registered on SessionStart as `asyncRewake` and
"arm[s] this session's inbox watcher BY CONSTRUCTION, at birth". It runs in G1, in parallel with the G3
drain, and the drain's `mailbox_wake_armed` check (mailbox-drain.sh:436-437) usually runs before the
marker exists.

### 2.4 Dispatcher one-liners: information content [M, `jq` over SessionStart content lines → /tmp/a4-lines.txt]

| line | n | what the data shows |
|---|---:|---|
| `MCP: …` | 406 | 406 report `N server(s) connected`; 0 degraded, 0 UNKNOWN. Variants differ only in `[cached Nm/Nh/Ns ago]` |
| `Tasks: …` | 406 | 358 are `Tasks: 0 active` |
| `Plans: …` | 407 | 62 are `0/N open`. All 407 carry the same 135-char help tail: `.claude-plans/ = project plans, … for the cross-project open list.` |
| `Frontier: …` | 404 | 1 distinct variant. `window OPEN→2099-12-31`, `holes: 0 OPEN` in 404/404 |

The Frontier line repeats ~/.claude/CLAUDE.md:130-145 almost word for word (default model, auto-escalation
and its budget, the `/frontier-hole` / `/frontier-run` skills, ledger `docs/research/FRONTIER_HOLES.md`).
frontier-status.sh:10 promises "otherwise → silent (zero context cost outside frontier-relevant sessions)".
With an `end:` of 2099, that branch never runs.

### 2.5 Resume and clear duplication [M counts; E on wire]

- **Who reads `source`:** among the 14 SessionStart scripts, **only accounts-board.sh reads the payload
  `source`** (accounts-board.sh:131, `rg '\.source'`), and it is systemMessage-only. Every
  context-emitting hook emits the same thing on startup, resume and clear.
- **What resume re-sends:** the 28 resume events re-injected 17,022 chars of dispatcher one-liners
  (608/resume), plus DoD in 5 and peer mail in 10.
- **Why that is a duplicate:** a resumed transcript keeps its earlier `hook_additional_context`
  attachments (same file; e.g. `…wt-cc-214325-42538/2569aad9….jsonl` carries one startup block and three
  resume blocks), so the one-liners are a second copy.
  - [E] that the earlier copy is still on the wire after resume. It is inferred from the attachments
    being in the same transcript; I did not capture it on the wire.
- **DoD and peer mail on resume** are not pure duplicates: the DoD may have changed, and peer mail is new.

### 2.6 Other startup-time context this repo controls [M, `wc -c` and the `instructions` attachment of session 5759497b]

| surface | bytes | notes |
|---|---:|---|
| ~/.claude/CLAUDE.md (all 5 config dirs symlink it) | 28,840 (28,338 loaded) | global instructions: not proposed for rewrite |
| ~/.claude/rules/10-session-close.md | 30,984 (30,270 loaded) | global |
| ~/.claude/rules/00-mission-board.md | 2,415 (2,281 loaded) | **hook-rendered**: `cc-mission render` in session-start.sh:460-462. Operator policy; size reported only |
| repo .claude/CLAUDE.md | 7,072 (7,028 loaded) | project |
| repo .claude/rules/agent-operating-lessons.md | 10,026 (9,880 loaded) | project |
| repo .claude/rules/agent-operating-lessons-situational.md | 80,648 | **not loaded**: absent from the `instructions.files[]` of 5759497b [M] |
| MEMORY.md (claude-infrastructure store) | 24,611 loaded | AutoMem |
| skill_listing | mean 27,543, max 30,001 (103 skills) | every-10th-transcript sample, n=41 |
| instructions attachment total | mean 94,886, max 143,092 | same sample, n=38 |
| deferred_tools_delta / agent_listing_delta / mcp_instructions_delta | 10,832 / 5,315 / 2,781 mean | same sample |

## 3. Per-block verdict: does the model need it to act in this session?

| block | needed? | verdict |
|---|---|---|
| DoD contract head (~640 chars): the newest frozen line of this session's real lineage | yes, on resume, compact and recycle; sometimes on startup | keep, but gate the predecessor rule (R1b) |
| DoD history body (~4,180 chars) | no: the frame itself calls it "prior CONTEXT, NOT additional binding scope", and the store path is already in the frame | replace with a one-line pointer (R1) |
| DoD negative notice (333 chars) | no: it says nothing is injected | drop, and log the disposition instead (R2) |
| mailbox wake nag at SessionStart (254 chars) | no: the sibling hook arms the watcher, and the per-prompt drain re-checks it | drop in `session-start` mode (R3) |
| peer mail at SessionStart | yes: the mail was consumed, and the model must see it | keep |
| Frontier line (270 chars) | no while holes=0 and the window is far off: it duplicates CLAUDE.md | emit only on holes>0 or when the window closes within 14 days (R4) |
| MCP line (69 chars) | only when unhealthy: the model already holds its tool list | emit only on 0-connected / UNKNOWN / degraded (R5) |
| Tasks line (94 chars) | only when there is active work | emit only when active>0 (R5) |
| Plans help tail (135 chars) | no: fixed text, re-read ~90× | drop the tail and keep the count (R5) |
| one-liners on resume (608 chars) | no: already in the resumed history [E] | skip on `source=resume` (R6) |
| recycle packet, desk brief | yes when present | keep: correct and rare |

## 4. Recommendations

Savings are chars per start averaged over all 413 events, then ×186 starts/day. Tokens are at 2.5 chars/token [E].

### R1. dod-persist: replace the history body with a pointer

- **Change:** in `_dod_inject_lineage_only` (dod-persist.sh:345-354), and the same frame at :452-461,
  keep `_pre`, which holds the frame and the current contract. Replace the
  `_dod_frame_budgeted … newest N of M captures` body with one line, for example:
  `History: N capture(s) from this lineage in <store>; read them with dod-persist.sh get / sed -n on the store.`
  Every capture stays in the store. Only the injection shrinks.
- **Impact:** 205 × (5,212 − 638 − ~250) / 413 = **≈2,146 chars/start (≈860 tokens)**, ≈160k tokens/day
  written [E]. It also removes the head-of-history crosstalk the 09-23 audit flagged.
- **Effort:** S. **Risk:** low. The completeness readers (wrap-ledger, completion-assert) read the store,
  not the injection, per the 09-23 audit (hooks.md:282-283). A session that wants the history reads one
  file.
- **settings.json edit:** no. **Conviction:** 85.

### R1b. dod-persist: stop the main checkout from leaking every capture into worktrees it fired

- **Change:** in the predecessor-toplevel rule (dod-persist.sh:231-238 consuming lib/dod-path.sh:114-125),
  admit a predecessor's capture only if it was written **at or before** the newest fire edge into this
  worktree (`lineage.tsv` column 1). Within that set, admit only the newest. Alternatively, record the
  firing session id on the edge and admit only that session's captures.
- **Why:** for `tm2-plan`, the FLEET_V2 captures (2026-10-10 and 10-11) postdate the last fire edge
  (2026-10-08), so this rule would have dropped all 152 FLEET_V2 injections.
- **Impact:** removes the misdirection in ≥120/205 lineage injections. If that leaves nothing to inject,
  it saves another ≈640 chars each (≈185 chars/start [E]).
- **Effort:** M (a lib change plus bats). **Risk:** medium: the rule has to keep the case where a fired
  child really inherits its parent's contract.
- **settings.json edit:** no. **Conviction:** 70.

### R2. dod-persist: no model context for "nothing to inject"

- **Change:** dod-persist.sh:322-325. Replace the `additionalContext` with an IDL disposition row
  (`hooks/lib/idl-log.sh`, the pattern desk-brief-inject.sh:70-80 uses). That keeps "ran and found
  nothing" distinguishable from "never ran" for the operator's alarms.
- **Impact:** 111 × 333 / 413 = **≈90 chars/start**, and 111 meaningless model reads in 2 days.
- **Effort:** S. **Risk:** very low. **settings.json edit:** no. **Conviction:** 85.

### R3. mailbox-drain: no wake nag in `session-start` mode

- **Change:** in the empty-inbox path (mailbox-drain.sh:620-625), add `[ "$MODE" = session-start ] && exit 0`,
  after the parked-watcher and inert-goal alarms so those stay.
- **Why it is safe:** mailbox-wake-arm.sh (SessionStart, asyncRewake) arms the watcher by construction, and
  the per-prompt `prompt` mode re-asserts the nag if the watcher really is missing. 13 sessions show the
  per-prompt path catching a missing arm that SessionStart did not flag.
- **Impact:** 270 × 254 / 413 = **≈166 chars/start**. It also stops telling the model to start a second
  `cc-await-ping` by hand while the mechanical one is starting.
- **Effort:** S. **Risk:** low. The mail body path (:628+) is untouched, so no mail is dropped.
- **settings.json edit:** no. **Conviction:** 80.

### R4. frontier-status: make "silent unless relevant" true again

- **Change:** frontier-status.sh:35-36. Print only when `holes > 0`, or when `end` is within 14 days.
  Optionally print one short line, ≤80 chars, the day the window changes. The routing guidance lives in
  CLAUDE.md:130-145.
- **Impact:** 404 × 270 / 413 = **≈264 chars/start** (≈106 tokens, ≈20k tokens/day written).
- **Effort:** S. **Risk:** low.
- **settings.json edit:** no. **Conviction:** 85.

### R5. Dispatcher one-liners: silent when they carry no information

| child | change | saving |
|---|---|---|
| session-start.sh:421-422 | when `MCP_STATE=ok && CONNECTED_COUNT>0 && DEGRADED_COUNT=0`, emit nothing. Keep the 0-connected and UNKNOWN wording, which is already distinct | 403 × 69 / 413 ≈ **67 chars/start** |
| setup-task-symlinks.sh:190-196 | emit only when `ACTIVE_TASKS>0` | 358 × 92 / 413 ≈ **80** |
| setup-plan-symlinks.sh:94 | drop the 135-char help tail (keep `Plans: X/Y open for P · Z all.`), and emit nothing when X=0 | ≈ **134 + 27** |

- **Total:** ≈310 chars/start.
- **Effort:** S. **Risk:** low.
- **settings.json edit:** no. **Conviction:** 75.
- **Hard precondition (fault tolerance):** once these lines are silent when healthy, a child the dispatcher
  killed at its 9 s bound (session-start-dispatch.sh:61-68: output dropped, no record) looks like a
  healthy one. Ship R5 and R4 together with the fault-tolerance axis's per-child disposition.
  - The dispatcher writes a sentinel per child; killed ⇒ a top-level `systemMessage` line naming the
    child and its bound (0 model tokens) plus an IDL row.
  - Otherwise this trades token cost for silent drops, which the operator ruled out.

### R6. Skip unchanged one-liners on resume

- **Change:** read `.source` once in session-start-dispatch.sh (the payload is already in `$T/payload`,
  :48) and export `CC_SS_SOURCE`. On `resume`, the Plans, Tasks, MCP and Frontier children print nothing
  unless their value differs from a per-session stamp.
- **Impact:** ≈608 chars per resume, ≈41 chars/start overall. It is small, and after R4 and R5 it is
  mostly moot.
- **Effort:** S-M. **Risk:** low.
- **settings.json edit:** no. **Conviction:** 55 (the on-wire duplication is [E]).

### Combined

| row | chars/start saved |
|---|---:|
| R1 | 2,146 |
| R2 | 90 |
| R3 | 166 |
| R4 | 264 |
| R5 | 308 |
| **total** | **≈2,970 of 3,622 (82%)** |

- **Tokens:** ≈1,190 tokens/start, ≈221k tokens/day written, ≈20M cache-read tokens/day at ~90 re-reads [E].
- **What remains:** ≈650 chars/start, mostly the real DoD contract head, the plan count, and peer mail
  when there is mail.

### O1 (other, cross-axis latency/drop): render the mission board off the critical path

- **Problem:** session-start.sh:460-462 runs `timeout 20 cc-mission render` **synchronously** inside a child
  whose dispatcher bound is 9 s. If the render overruns, the child is killed before its MCP line prints at
  :464-471.
- **Why it can move:** the file is read by the *next* session, and the code says so itself (:437-439, "the
  board a session reads was rendered by the PREVIOUS session").
- **Change:** detach it with `scripts/lib/detach.sh`, as the memory snapshot at :354-359 already does.
- **Impact:** removes up to 9 s of child time and the one observed MCP-line loss (1/404) [M]. The render's
  own duration under load was not measured, because running it writes the file.
- **Effort:** S. **Risk:** low. **settings.json edit:** no. **Conviction:** 60.

## 5. Corollary for the fault-tolerance axes (measured here, not my axis)

- **The model-context children survived the 9 s kills.** In all 404 dispatcher successes:
  - the merged context held every always-on context child (MCP, Plans, Tasks, Frontier), except one event
    missing MCP;
  - the systemMessage held the accounts board, including the **101 runs with `durationMs` > 9,000** [M]:
    `jq` on dispatcher `hook_success.stdout`, `/tmp/a4-disp.tsv`.
- **So either the children killed in those runs print nothing, or `durationMs > 9 s` does not by itself
  mean a child was killed.** Possible victims are config-mirror-assert, escalation-watch, activation-watch
  and session-index-start, which are silent when healthy. The second reading is possible because harness
  timing includes spawn and merge time at load ~52/core. The brief's "26% ⇒ at least one child killed"
  should be confirmed with a per-child sentinel before it is relied on.
- **Timeout counts:** `hook_cancelled` in this corpus [M] is mailbox-drain 34 (8.2% of starts),
  dod-persist 18 (4.4%), dispatcher 6, desk-brief 1. A cancelled dod-persist loses the contract with no
  operator-visible record. A cancelled mailbox-drain re-delivers at the next boundary, because commit
  follows print (mailbox-drain.sh:922-929).

## 6. Open questions

1. **R6 premise:** is the earlier SessionStart attachment on the wire after a resume? This is [E]. A
   `--resume` with a prompt-snapshot capture (`prompt_snapshot` records exist in transcripts) would settle
   it.
2. **R1b design:** should the fired-from contract carry over to a child worktree at all? If yes, should
   `lineage.tsv` record the firing session id so the rule can be exact rather than time-bounded? This is an
   operator call.
3. **Async stderr:** stderr from async SessionStart hooks (pre-session-validate's "no working version",
   session-register's `Killed: 9`) reaches neither the model nor the terminal [M, binary]. Should those
   paths emit a top-level systemMessage? Note that **for an async hook that is model context**, per the
   binary's `async_hook_response` handler. Or should they write an alarm row?
4. **Cache-read cost of an unchanging startup block:** a static block identical across sessions (the
   Frontier line) still sits after the unique first prompt, so it is not shared across sessions.
   docs/research/token-efficiency-2026-09-23/measure/hooks.md:255-259 found cross-session cache reuse
   blocked by the prompt. So gating beats relocation.
5. **Census coverage:** /clear (1 event) and compact (0) are nearly absent from 2 days of transcripts.
   Confirm that /clear and compact still fire SessionStart on 2.1.293 and are recorded, before treating
   their volume as negligible.

## Re-derive

```
cd /tmp
python3 -I /Users/chrisren/Development/.worktrees/wt-cc-004752-67086/docs/research/startup-hooks-2026-10-18/a4_tokens_census.py \
  > /tmp/a4-census.json            # tables on stderr: totals, per component, per source, variants
jq '[.events[]|select(.ts>="2026-10-16T05:49")]|length' /tmp/a4-census.json    # starts in 48 h
```

The one-off jq/rg passes behind §2.3-§2.5 are quoted inline above, with their output files under /tmp.

## Skeptic verdicts

Adversarial review, 2026-10-18. Read-only: no hook was executed. Scratch scripts and outputs are under
/tmp/skA4* (`skA4_grown*.py`, `skA4_nag.py`, `skA4_disp.py`, `skA4_anc.py`, `skA4-census.json`,
`skA4-dod-lineage.jsonl`). The census script reproduced exactly: 413 events, mean 3,622, dod-persist
2,676.6 chars/start, 205 lineage / 111 negative, 270 wake nags [M: `python3 -I a4_tokens_census.py`].
Inside the 48 h window alone the mean is 3,722 chars/start, of which dod-persist is 2,813 [M: jq over
`.ts>="2026-10-16T05:49"`]. So the 413-event averages slightly understate the current figures.

| id | verdict | severity | one line |
|---|---|---|---|
| A4-R1 | amended | minor | The numbers hold, but the quoted label is not in any live injection, the always-kept set must survive, and tests and prior design need revising |
| A4-R1b | amended | major | The misdirection is real, but the proposed time bound would drop 0 of the 120, not all of them |
| A4-R2 | amended | minor | The numbers hold. The notice is the evaluated "pointer line" design, and 5 bats assertions pin it |
| A4-R3 | amended | minor | 73 of the "263" have no UserPromptSubmit record at all, and the `exit 0` as written also kills the two alarms it says it keeps |
| A4-R4 | confirmed | none | Reproduced: 404/404 identical, holes 0 |
| A4-R5 | amended | minor | The Plans arithmetic is off: about 286 chars/start, not 308. The MCP-probe bats pin the healthy line |
| A4-R6 | confirmed | minor | Reproduced. Only 14 resumes in 48 h, so it is worth about 1.7k tokens/day |
| A4-O1 | amended | minor | The code facts hold. The impact is unmeasured: session-start.sh beat the bound in 403/404 runs |
| A4-X1 | amended | minor | Reproduced, but the within-account data suggest config-mirror-assert is the killed child |

**A4-R1.**
- **Reproduced:**
  - 205 lineage injections, mean 5,212 chars [M: jq over `/tmp/skA4-dod-lineage.jsonl`]. A codepoint
    split gives head 646, frame 1,037 and history 4,174.
  - 151 of the 205 show "9 of 38" [M].
- **Wrong:** the phrase "prior CONTEXT, NOT additional binding scope" appears in **0** of the 411
  transcripts [M: `rg -c` over the list]. It lives only in the `CC_DOD_LINEAGE_ONLY=0` frame
  (dod-persist.sh:457), which also never fired (0 transcripts carry "Durable frozen DoD for this
  worktree").
  - The live lineage frame (:345-352) presents the history as "written by this session, a session that
    held this pane before it, or a recorded predecessor worktree", with no disclaimer.
  - That makes the body more misleading than claimed, not less.
- **Also measured:**
  - The newest history block repeats the head's `THE CURRENT CONTRACT` line in 205/205 injections.
  - 0 of 1,622 injected blocks are grown-only [M: `skA4_grown3.py`]. So the body adds no binding scope
    in this corpus.
- **Correction to the recommendation:** keep `_dod_newest_within`'s always-kept set, meaning every
  capture newer than the newest `Scope (frozen):`, since `Scope (grown)` extends the contract
  (dod-persist.sh:257-259, pinned by tests/dod-persist.bats:590). Replace only the optional older
  captures with the pointer.
  - Measured saving is unchanged (≈2,146 chars/start), because that set was empty in 205/205.
- **Constraint lens:**
  - dod-crosstalk-2026-08-18.md:178-182 chose LOSSLESS history "so a legitimate inheritance cannot go
    missing", with bats case 28. The 10-04 budget already broke that.
  - The budget and frame tests (tests/dod-persist.bats:276-345 and :574-660) must be rewritten. Effort
    is M, not S.

**A4-R1b.**
- **Reproduced:**
  - 152 FLEET_V2 contracts, 120 of them in `-worktrees-tm2-plan` [M: jq over the lineage injections,
    `/tmp/skA4-dod-where.tsv`].
  - The cited lineage.tsv rows exist.
- **Wrong:** `lineage.tsv` holds **44** claude-infrastructure→tm2-plan fire edges, the newest
  2026-10-17T19:27:28Z (lineage.tsv:3501). The last one is not 2026-10-08 [M:
  `rg -n 'tm2-plan\t' lineage.tsv`].
  - The FLEET_V2 captures (2026-10-10T16:18, 2026-10-11T12:07, repo-86523465733a9afe.md:369,372)
    predate that edge.
  - So "admit only captures at or before the newest fire edge, newest only" would still admit the
    10-11 FLEET_V2 capture in all 120 sessions.
- **Missed:** admission is TRANSITIVE. A replica of the `dod_lineage_ancestors` BFS gives tm2-plan
  **26** ancestor toplevels, including `/`, personal and reso-management-app [M: `skA4_anc.py`].
- **Corrected recommendation:**
  - Have the fire path stamp the firing session id on the edge (`dod_lineage_record`, lib/dod-path.sh:94).
  - Admit only that session's captures, and only from depth-1 predecessors.
  - What to do with the 3,524 legacy rows that carry no sid (admit nothing, or admit a short pre-edge
    window) is an operator call.
- **Interim fix:** captures admitted only through the predecessor rule should not go in the "binds you"
  head.

**A4-R2.**
- **Reproduced:** 111 notices, mean 333.4 chars [M]. The arithmetic is right (≈90 chars/start).
- **Understated risk:** the notice is the "one-line pointer to the store" that the lineage-only design
  adopted (dod-persist.sh:137,151-152). It was present in the lineage arm of the 09-23 probe
  (eval/wave2/dod-lineage-probe.md:22,46), so dropping it deviates from the evaluated design.
- **Tests:** tests/dod-persist.bats:430,432,442,494,534 assert the notice.
- **Correction:** offer the operator two options:
  - (a) Shorten it to a pointer of 100 chars or less (≈55 chars/start).
  - (b) Drop it and write the IDL row. Note that sourcing idl-log adds a jq fork to a hook cancelled
    18 times in this corpus.

**A4-R3.**
- **Reproduced:** 270 nags at 254 chars, so ≈166 chars/start.
- **Cross-tab re-run** [M: `skA4_nag.py`]:

  | after a SessionStart nag | transcripts |
  |---|---:|
  | a first UserPromptSubmit context without the nag | 189 |
  | a UserPromptSubmit ran with no context | 1 |
  | **no UserPromptSubmit record at all** | **73** |
  | nag again | 6 |

  The "263 armed" therefore includes 73 with no evidence. The race is still supported by 190 of 196
  sessions that do have a UserPromptSubmit record (97%).
- **Code defect:**
  - The parked-watcher header (`_hdr`, :534) and the inert-goal breadcrumb (:585-586) are carried in
    `$nudge`/`_hdr` and emitted by the same jq at :623.
  - So `[ "$MODE" = session-start ] && exit 0` in the empty-inbox block would silence both alarms too.
  - Correct change: gate only the no-watcher branch, `[ "$_watched" = 1 ] || [ "$_headless" = 1 ] || [ "$MODE" = session-start ] || nudge=…`
    at :558-560.
- **Tests:** the drain bats test the nag in `prompt` mode only, so none breaks.

**A4-R4: confirmed.**
- 404/404 Frontier lines are identical, with `holes: 0` [M: rg over `/tmp/a4-lines.txt`]. The repo's
  FRONTIER_HOLES.md has 0 OPEN of 4.
- `model-config.yaml` has `permanent: true`, so `end` is a sentinel. The 14-day branch is dead and the
  gate is effectively `holes>0`.
- The line's "agent auto-escalates" also reads against CLAUDE.md:139 ("it is not automatic").
- No test pins the output.

**A4-R5.**
- **Reproduced:**
  - MCP: 403/403 `N server(s) connected`.
  - Tasks: 358/404 `0 active`.
  - Plans: the 135-char tail in 404/404, and 62 lines at `0/N open` [M: `skA4_disp.py`].
- **Arithmetic:** the "+27" for silencing 0-open plans is ≈62×47/413 ≈ 7. The row total is ≈286, not
  308.
- **Tests:** session-start-mcp-probe.bats:113,134,146,219 assert the healthy MCP line. The MCP line
  also carries the agent-browser status.
- **The precondition is right and binding:** dispatcher :61-68 drops a killed child's output with no
  record. The kill record could fire in up to 101/404 starts (the >9 s runs) [M, upper bound], so the
  root cause has to be fixed as well.

**A4-R6: confirmed.**
- Only accounts-board.sh:131 reads `.source` [M: rg over all 20 SessionStart scripts, including the
  untracked net-context-stamp.sh].
- 17,022 chars over 28 resumes [M].
- Only 14 resumes fall in the 48 h window, about 7/day, so this is worth ≈1.7k tokens/day [E].
- **Caveat:** after a compaction the earlier one-liners are summarized away, so "already in history" is
  false there.

**A4-O1.**
- **Code read is right:**
  - The render is synchronous at session-start.sh:459-461, before the emit at :464.
  - The board is read by the next session (:437-439).
  - The detach precedent is at :354-359.
- **Impact is unmeasured:** the MCP line is present in 403/404 dispatcher successes, including 100 of
  the 101 runs over 9 s [M]. So session-start.sh essentially never hit the bound.
  - Closing the drop path is worth ≤1/404.
  - The latency gain exists only if this child is the long pole, which nobody has measured.
- Keep it as a cheap hygiene item with impact "unmeasured", not "up to 9 s".

**A4-X1.**
- **Reproduced:**
  - Accounts board in 404/404 successes and 101/101 runs over 9 s.
  - Plans, Tasks and Frontier lines always present; MCP missing once.
  - Cancels: mailbox-drain 34, dod-persist 18, dispatcher 6 [M].
- **Inference needs amending:** within an account, config-mirror-assert's operator-visible
  `knowledge-layer mirror` systemMessage disappears in slow runs [M: `skA4_disp.py`]:

  | account | warning in fast runs (≤7 s) | warning in slow runs (>9 s) |
  |---|---:|---:|
  | .claude-next | 186/189 | 1/3 |
  | quaternary | 6/42 | 0/45 |

  - Slow runs are concentrated off .claude-next: 98 of the 101 are secondary, tertiary or quaternary
    transcripts.
  - So the 9 s kill plausibly does drop an operator-visible child. config-mirror-assert is not "silent
    when healthy" where a FORKED warning stands.
  - Confirm with a per-child sentinel, as the finding says.
