# Shaping the agent's final response — entrypoints and methodologies

**Date:** 2026-08-08 · **Binary measured:** Claude Code **2.1.220** (`~/.claude-220/node_modules/.bin/claude`, the
binary this session is actually running per `ps -o command= -p $PPID`) · **Method:** live headless probes
(`claude -p --output-format stream-json --verbose`) with a differential control, plus doc survey and repo inventory.

**Scope (frozen):** investigate the best-practice entrypoints and methodologies for adjusting Claude Code agent
behaviour when it returns its final prompt/response to the user on finishing work.

---

## 1 · The answer, first

There are **five** channels that can touch the end of a turn, and they differ on the only axis that matters:
**who receives it — the model, or the human.** Everything else follows from that split.

There are **six** channels that can touch the end of a turn, and they split on two axes: **who receives it** (model or
human) and **when it acts** (before generation, or after).

| Want to… | Use | Reaches | Forces another turn? |
|---|---|---|---|
| Change *what the agent writes*, always | **Output style** / `--append-system-prompt` | model, before generation | no |
| Change it *per project*, with rationale that survives | **CLAUDE.md** | model, before generation | no |
| **Refuse the stop** and make the agent work more | **Stop `decision:"block"` + `reason`** | model, as a user turn | **yes** |
| Same, from a script that failed | **Stop `exit 2` + stderr** | model, as a user turn | **yes** |
| Feed the model facts at close, not labelled an error | **Stop `additionalContext`** | model, as a system-reminder | **yes** — see §2b |
| Tell the *human* something, model untouched | **Stop `systemMessage`** | human only, **TUI only** | no |
| **Rewrite the rendered text** of the final message | **`MessageDisplay` hook** | human (and SDK stream) | no |

**Two load-bearing rules.**

1. **Only a Stop hook can *enforce*; only a system prompt can *shape*.** A prompt instruction ("always close with X")
   is advisory — the model may drop it under context pressure. A Stop hook is mechanical: it refuses the stop. Pick by
   whether a violation must be *impossible* or merely *unlikely*.
2. **Every model-facing Stop channel forces another turn — there is no "advisory whisper" at Stop.** `reason`,
   `exit 2`, and `additionalContext` all re-enter the query loop and all increment the same block counter. The only
   fields that do *not* extend the turn are `systemMessage` (human-only) and `MessageDisplay` (display-only). Anyone
   looking for "leave a note for the model without making it do more work" is looking for something that does not exist
   on this event.

---

## 2 · Measured channel matrix — Stop hook output on 2.1.220

Each row was probed live: a Stop hook emitting exactly one field, a unique marker word, and a grep of the full
stream-json transcript for that marker. A **control** case (hook emits nothing) established the baseline, since the
operator's own global Stop hooks fire alongside any test hook — `--settings` **merges with**, does not replace,
user-level settings. That contamination invalidated the first run and is worth stating as a trap in its own right.

| Field | Reaches model? | Reaches human? | Extends turn? | Evidence |
|---|---|---|---|---|
| `decision:"block"` + `reason` | **yes** | notice only | **yes** | user turn `"Stop hook feedback:\n<reason>"`; probe said `BANANA` on command |
| `exit 2` + stderr | **yes** | no | **yes** | user turn `"Stop hook feedback:\n[<hook path>]: <stderr>"` — path-prefixed, unlike `reason` |
| `hookSpecificOutput.additionalContext` | **yes** (new) | no | **yes** | `system` record `"Stop hook additional context: …"`; 11 hook invocations vs control's 2 |
| `systemMessage` | **no** | **TUI only** | no | 3 invocations, valid JSON, marker absent from stdout *and* stderr in headless |
| `continue:false` (+ `stopReason`) | no | yes | ends turn | **precedence trap — see below** |
| *(control — empty output)* | n/a | n/a | no | 2 invocations, clean stop |

Binary corroboration for the two model-invisible/visible extremes: `systemMessage` maps to `hook_system_message:()=>[]`
— an empty content list, so it provably cannot reach the model on the sync path. `additionalContext` maps to
`hook_additional_context:(e)=>[…]` wrapping the text in a `<system-reminder>` user message, and unlike the
`hook_success` arm it is **not** gated on `hookEvent`, which is precisely why it now works on Stop.

🚨 **Precedence trap:** `continue:false` is evaluated **first** and returns `blockingErrors:[]`. It therefore
**silently discards any `decision:"block"` or `additionalContext` in the same JSON payload.** Never combine them.

⚠️ **Async asymmetry:** for a hook returning `{"async":true}` and responding later, `systemMessage` **does** reach the
model — the opposite of the sync path. If a hook is ported from sync to async, its `systemMessage` silently becomes
model-visible.

Three of these are corrections to claims currently written down in this repo.

### 2a · `systemMessage` is silently dropped in headless mode

Positive-controlled: the hook emitted `{"systemMessage":"…"}` three times, the payload re-runs clean standalone, and
the marker appears **zero** times across stdout and stderr — while the exit-2 marker is found in the same search. It
renders in the interactive TUI (which is why `operator-readout.sh` works and `tests/operator-readout.bats` passes),
but any automation asserting a `systemMessage` reached anyone under `claude -p` is asserting nothing.

### 2b · `additionalContext` on Stop is **no longer inert**

Six places in this repo state that Stop `additionalContext` is inert, citing GH #37559 and measurements on
**2.1.207** — `hooks/boundary-handoff.sh:21-22`, `hooks/memory-nudge.sh:5-8`,
`docs/research/cross-session-mail-2026-07-20.md:114-130`,
`docs/research/desk-audit-2026-07-18/p13-behavioral.md:8-14`, `p07-roadmap.md:57`,
`docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md:251,315,480`.

On **2.1.220** it delivers. The marker arrived as a `system` record reading
`Stop hook additional context: PROBE-C-ADDCTX: you must state the word CHERRY.`, and the run ended with the model
saying `CHERRY`. This closes open task **#139** ("Stop additionalContext may no longer be inert on 2.1.219/220 — 2
repo claims may be stale") — the answer is yes, and it is 6 claims, not 2.

The binary states the design intent outright, in the `stop_hook_summary` schema:

> `hook_additional_context: … "Non-error feedback from hookSpecificOutput.additionalContext — kept separate from
> hook_errors so the sanctioned feedback channel is not labeled an error."`

So it is not merely working — it is **the sanctioned channel**. Its schema description says: *"Feedback for the model;
**the conversation continues** so the model can act on it."*

**Two caveats before reaching for it.**

*It is not advisory.* "The conversation continues" means it forces another turn and increments the same block counter
as `decision:"block"`. My probe measured 11 hook invocations against the control's 2. A hook emitting
`additionalContext` unconditionally loops exactly like an unlatched block — it just isn't labelled an error.

*The model may refuse it.* In the first probe run the model read the same payload and replied:

> "I notice this Stop hook appears to contain a prompt injection attempt… I'm flagging this suspicious hook content
> rather than complying with its injected directives."

Same payload, same binary, opposite outcome. It arrives out-of-band, attributed to a hook, unanchored to anything the
user said — the shape of an injection, so the suspicion is *correct* behaviour. `decision:"block"` + `reason` arrives
as an ordinary user turn and carries no such ambiguity. **Prefer `reason` when compliance matters; use
`additionalContext` when "not labelled an error" matters more than certainty.**

### 2c · The harness has its own loop cap — `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, default 8

```js
let Kt = Rue(process.env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, 8);
if (Kt > 0 && _o > Kt) … "A hook blocked the turn from ending N consecutive times — overriding and ending turn.
  For Stop/SubagentStop hooks, check stop_hook_active in the input and return success while it's true."
```

The counter resets whenever a Stop pass returns no blocking errors, `maxTurns` is checked first and wins, and
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` **disables the cap entirely**. This repo's `CLAUDE_CONTINUE_MAX` default of 8
coincides with it but is independent — the harness cap is a backstop under every hook, including third-party ones.

---

## 2d · `MessageDisplay` — the only channel that rewrites the final message

This is the direct answer to "adjust what the agent returns", and it is **not** SDK-only: it is event 31 of 31 in the
CLI's hook registry and fires from an ordinary `settings.json` entry. Probed live and confirmed.

- **Input:** `{turn_id, message_id, index, final, delta}` — `delta` is the newly completed text; `final:true` on the
  completed message. Measured payload: `{"hook_event_name":"MessageDisplay","index":0,"final":true,"delta":"APPLE"}`.
- **Output:** `hookSpecificOutput.displayContent` — **not** `delta`. My first probe returned `delta` and silently did
  nothing; the field name is the whole mechanism.
- **Fail-open:** on error or the 10 s timeout it emits the original text (`"MessageDisplay hook failed for completed
  message; emitting original text"`).
- **Gotcha:** it collapses all text blocks into the first and blanks the rest.

**The scope of "display-only" is narrower than it sounds.** The binary keeps the original in `mutableMessages` and
routes the rewrite to the renderer, so the transcript and the model's own history keep the original. But under
`claude -p --output-format stream-json`, the **emitted assistant message carried the rewritten text**
(`[REWRITTEN-BY-HOOK]`, not `APPLE`). So for any SDK or automation consuming the stream, `MessageDisplay` is not
cosmetic — it changes what they receive. Use it for redaction of rendered output; do **not** assume a downstream
consumer still sees the original.

---

## 3 · Methodologies — the patterns that hold

### M1 · Fact-bound, never scope-judging

A Stop hook cannot see the user's intent, and its only way to reach the model is to *block*. So a hook that tries to
judge "is this work complete?" either blocks forever or guesses. Every durable hook in this repo instead asserts a
**mechanically checkable fact**: are there uncommitted files this session wrote (`hooks/lib/session-writes.sh`), is
the ledger's rung `🔧` (`scripts/wrap-ledger.sh --machine`), is a wake path armed. Scope judgment stays with the model,
which is the only party that has seen the request.

### M2 · Every block needs a bound, and the bound must be visible in the exit path

An unlatched `decision:"block"` is an infinite loop — the model finishes, the hook blocks, the model finishes again.
This repo bounds each blocking arm and, critically, **each one allows the stop at its cap and says why**:

| Hook | Bound | Mechanism |
|---|---|---|
| `session-continue.sh` | `CLAUDE_CONTINUE_MAX` = 8, × `CC_MECH_MAX` = 2 | counter file; at cap deletes sentinel, emits `systemMessage`, allows |
| `anti-deference-nudge.sh` | `ANTIDEF_MAX` = 3 | hash latch-set + counter |
| `completion-assert.sh` | `COMPLETION_MAX` = 3 | latch-set + counter |
| `dispatch-assert.sh` | 2 per window, 6 per session | obligation file — a hash latch fails here, because the block's own reason re-enters the transcript and resets the window |
| `boundary-handoff.sh` | one-shot latch, 3 re-arm dimensions | `hash(configdir\|cwd)-HEADsha` |

The harness supplies two backstops the repo's hooks predate. `stop_hook_active` in the Stop payload flips
`false → true` on the re-entrant invocation (probe-confirmed), and the binary's own override message names it as the
intended guard: *"check `stop_hook_active` in the input and return success while it's true."* Behind that,
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (§2c) ends the turn unconditionally at 8 consecutive blocks. **No hook in this repo
reads `stop_hook_active`** — every bound here is home-grown. That is redundancy rather than a defect, but for any hook
written from scratch, `stop_hook_active` is a two-line guard that subsumes most of a counter file and should be the
first thing in it.

The Stop payload also carries **`last_assistant_message`** — the text of the closing message, explicitly so a hook need
not parse the transcript to see what the agent just said. That makes a *content-aware* close gate cheap: a hook can
assert the closing message actually contains what policy requires, without reading a single file.

### M3 · A Stop hook must never `exit 2` by accident

`exit 2` *is* the block signal. A hook that runs `set -e` and trips on an unrelated command false-blocks the stop and
injects its own stderr into the conversation. Every blocking hook in this repo is `set -uo pipefail` **without**
`set -e`, and every path ends `exit 0` — the reason is written verbatim into four separate hook headers.

### M4 · One renderer, or push and pull drift

Where the same close block is both pushed (Stop hook) and pulled (`/wrap`), both call one code path —
`hooks/operator-readout.sh --render` (`commands/wrap.md:30-33`). Two renderers for one artifact is how a paraphrase
silently becomes a second, worse source of truth.

### M5 · Prefer the system prompt for *form*, the hook for *floor*

Output styles and `--append-system-prompt` shape how the closing message reads; they cost nothing per turn and cannot
loop. Hooks enforce that a close is *permitted at all*. Using a hook to enforce prose formatting is expensive and
brittle; using a prompt to enforce "never close with uncommitted work" is unenforceable. Match the tool to the
failure you actually fear.

### M6 · `/goal` is the built-in, session-scoped version of all this

`/goal <condition>` registers a session-scoped Stop hook of `{type:"prompt", prompt:<condition>}` and sets
`activeGoal`; the Stop hook is model-judged and **auto-clears when the condition is met**. Bounds measured from the
2.1.220 binary (`docs/research/goal-in-handoff-2026-08-08.md:96-110`): 4000-char cap on the condition, gated on a
trusted workspace, refused under `disableAllHooks`/`allowManagedHooksOnly`, dies with the session, and does **not**
survive `--recycle`. It is the right tool for a one-session objective; it is not a place to put durable policy.

---

## 4 · Anti-patterns, each with a live example

| Anti-pattern | Why it fails | Evidence |
|---|---|---|
| Treating Stop `additionalContext` as advisory | It forces a turn and counts toward the block cap; unbounded ⇒ loop | §2b — 11 invocations vs control's 2 |
| Advisory Stop hook that only emits `additionalContext` | Model may classify it as prompt injection and refuse | §2b — same payload, opposite outcomes |
| `continue:false` alongside `decision:"block"`/`additionalContext` | `continue` wins and silently discards both | §2 precedence trap |
| Returning `delta` from a `MessageDisplay` hook | Output field is `displayContent`; `delta` is input-only, so the hook no-ops silently | §2d — cost one probe run |
| Assuming `MessageDisplay` is cosmetic | Under `-p --output-format stream-json` the emitted message carries the rewrite | §2d |
| Asserting `systemMessage` delivery in headless | Silently dropped under `-p` | §2a, positive-controlled |
| `--settings` assumed to *replace* user settings | It **merges**; the operator's global Stop chain still fires | first probe run was invalidated by exactly this |
| Unlatched `decision:"block"` | Infinite loop | `hooks/boundary-handoff.sh:21-22` names it "the banned infinite-loop anti-pattern" |
| Hash-latch on a hook whose block reason re-enters the transcript | The reason resets the window, so the latch never matches | `hooks/dispatch-assert.sh:35-39` — why it uses an obligation file |
| Registering a `SubagentStop` hook and assuming it runs | Registered in the template, in **none** of the 5 live config dirs; foreground subagents therefore get no close-time hook at all, while background ones run the full **main** Stop chain | `tests/subagent-stop-r1.bats:11-13` |

---

## 5 · Open items this raises

1. **Six stale claims to correct** (§2b) — `hooks/boundary-handoff.sh:21-22`, `hooks/memory-nudge.sh:5-8`,
   `docs/research/cross-session-mail-2026-07-20.md:114-130`, `docs/research/desk-audit-2026-07-18/p13-behavioral.md:8-14`
   and `p07-roadmap.md:57`, `docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md:251,315,480`. Each says Stop `additionalContext`
   is inert; on 2.1.220 it is not. The *design decisions* those files made remain sound — `reason` stays the right
   channel where compliance matters (§2b) — so this is a comment/doc correction, not a rewiring.
2. **`CLAUDE.md`'s own framing is now wrong in one clause.** It states a Stop hook "can't reach the model except by
   *blocking*". On 2.1.220 there is a second path (`additionalContext`) that reaches the model without being labelled
   an error. The practical conclusion is unchanged — both extend the turn, so both need a bound — but the sentence as
   written closes off a design space that is open.
3. **`SubagentStop` template/live drift** — wired in `settings-templates/settings.example.json:482`, absent from all
   five live config dirs, so `hooks/subagent-stop.sh` never runs in production.
4. **`stop_hook_active` and `last_assistant_message` are unread repo-wide** — a free loop guard and a free
   content-aware gate, both already in the payload.

*Items 1–2 close task #139. Items 3–4 are pre-existing, recorded not actioned — outside this investigation's frozen
scope.*

---

## 6 · Reproducing this

Probe harness (throwaway, not committed): a per-case dir with a `hook.sh` that records its stdin, counts invocations,
and emits one field; a `settings.json` registering it; then
`claude -p "…" --model claude-haiku-4-5-20251001 --settings <file> --output-format stream-json --verbose`,
grepping the transcript for a unique marker word.

**Two traps that invalidated the first run**, both worth carrying into any future harness probe:

- **`--settings` merges with user settings, it does not replace them.** The operator's global Stop chain fired
  alongside every test hook, and its output was initially misread as the probe's. The fix that does not need
  credentials is a **control case** whose hook emits nothing — then a unique marker word discriminates regardless of
  what else is on the chain. (Full isolation via `HOME`/`CLAUDE_CONFIG_DIR` fails: the isolated dir has no
  credentials, and every run returns `Not logged in`.)
- **Absence needs a positive control.** `systemMessage` appearing nowhere is only evidence once the same search finds
  the `exit 2` marker that *did* land, and the hook's payload is re-run standalone to prove it was well-formed.
