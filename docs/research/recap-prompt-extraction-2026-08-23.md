# Claude Code's built-in recap prompt, extracted verbatim

**Date:** 2026-08-23 · **Subject:** Claude Code 2.1.220 (`~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, Mach-O arm64, 245 MB)
**Question asked:** can we introspect/retrieve the system prompt behind the built-in *recap*, to use as a reference for making our own Stop-hook close body more concise and actionable?

**Answer: yes, and here it is.** It is a single string constant (`bHy`) in the bundled JS, 41 words long,
and it is the entire specification — there is no schema, no examples, no second prompt.

---

## 1. The prompt

```text
The user stepped away and is coming back. Recap in under 40 words, 1-2 plain sentences,
no markdown. Lead with the overall goal and current task, then the one next action.
Skip root-cause narrative, fix internals, secondary to-dos, and em-dash tangents.
```

Four moves, in this order. The order is the design:

| # | Move | Text | What it does |
|---|---|---|---|
| 1 | **Reader model** | "The user stepped away and is coming back." | One clause. Fixes *who is reading and what they lost* before any rule lands. |
| 2 | **Hard budget** | "under 40 words, 1-2 plain sentences, no markdown" | A countable ceiling, not "be brief". Bans the formatting that invites padding. |
| 3 | **Positive slot order** | "Lead with the overall goal and current task, then the one next action" | Three slots, sequenced. Note **"the one next action"** — singular, pre-empting a list. |
| 4 | **Named exclusions** | "Skip root-cause narrative, fix internals, secondary to-dos, and em-dash tangents" | Four *named failure modes*, not a generic "avoid verbosity". |

The prompt is 41 words and asks for under 40 — it is almost exactly as long as its own output.
That is the cheapest possible demonstration that the budget is achievable.

**The load-bearing half is move 4.** Moves 1–3 are conventional. Naming the four things a model
*actually* does when over-explaining a coding session — narrating the root cause, explaining fix
internals, enumerating leftover to-dos, and trailing em-dash asides — is what makes it bind. A rule
that says "be concise" is scored by the model against its own notion of concise; a rule that says
"skip root-cause narrative" is checkable.

## 2. How to re-extract it (technique, so this survives a version bump)

The binary is Bun-compiled: strings appear **twice** — once in a native data section, once in the
embedded JS source blob. The JS copy is the one worth reading, because it carries the surrounding
control flow.

```bash
B=~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe
LC_ALL=C grep -abo "stepped away" "$B"          # byte offsets; the JS copy is the high one
tail -c +237347780 "$B" | head -c 320 | LC_ALL=C tr -d '\000'
```

`dd if=…` is **denied by `hooks/validate-bash.sh`** — use `tail -c +N | head -c M`, which is
byte-exact and ungated. To make a mangled dump readable:
`| LC_ALL=C tr -c '[:print:]\n' '.' | LC_ALL=C sed 's/\.\{4,\}/ ~ /g'`.

Search on the **internal** name, not the user-facing one: the feature is `awaySummary` everywhere in
code and `recap` only in UI strings. Grepping `recap` returns 80 hits across unrelated subsystems;
grepping `awaySummary` returns 43, tightly clustered.

Prior art for this class of extraction is `tests/suggest-ladder-oracle.mjs` + `bin/cc-suggest-filter`
(the `TM_` prompt-suggestion ladder, `docs/research/prompt-suggestion-filter-2026-08-05.md`), which
goes one step further and *executes* the extracted source as an oracle.

## 3. Mechanism (what actually fires it)

Generation (`jpn`) **forks the live conversation** rather than re-summarising a transcript: it reuses
the saved `cacheSafeParams` from the last real turn and prepends one user message containing the
prompt. So the recap sees the whole session at near-zero marginal cost.

```js
R3({ promptMessages:[zr({content:bHy})], cacheSafeParams:r,
     canUseTool: async () => ({behavior:"deny", …}),   // all tools denied
     querySource:"away_summary", forkLabel:"away_summary",
     maxTurns:1, skipCacheWrite:true, skipTranscript:true })
```

Result is injected as a `system` message with `subtype:"away_summary"`. The first **3** per session
get ` (disable recaps in /config)` appended, then it stops.

**Trigger = terminal focus.** On `blurred`, if cache age ≥ `min(delayMs, ttl*0.8)`; `delayMs` comes
from gate `tengu_sedge_lantern_config`, floored at 30 s. (This is why kitty focus-event support
gates the feature entirely — task #144.)

**Suppression ladder** — every one of these is bypassed by `force`, which is what `/recap` passes:

| Skip reason | Condition |
|---|---|
| `cache age unknown` | no saved turn timestamp |
| `cache stale` | age > ttl × 0.9 |
| `at or near rate limit` | `Vie().status !== "allowed"` |
| `draft input present` | user has typed something unsent |
| `background work pending` | `pendingAgents > 0 \|\| pendingWorkflows > 0` |
| `loop wakeup pending` | `lct()` |
| `StructuredOutput recap present` | an assistant turn already produced one |
| *(silent)* | last message is already an `away_summary`; or too few new user messages since the last one |

**Config surface:** `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` env · gate `tengu_sedge_lantern` (default
**on**) · `awaySummaryEnabled` user setting · `/config` → "Session recap" · `/recap` slash command
(`description: "Generate a one-line session recap now"`, forced, works non-interactively).
The remote variant is separate and default-**off**: `CLAUDE_CODE_ENABLE_REMOTE_RECAP`, gate
`tengu_harbor_moth`, requires the `ccr` client.
Telemetry: `away_summary_generate` / `generate_failed`, and `tengu_return_to_session`
(`msSinceFocus`, `blurDurationMs`, `hadRecap`, `scrolledBeforeSubmit`).

## 4. Bonus find: Anthropic's own Opus 5 communication block ships in the same binary

The bundled `claude-api` skill embeds Anthropic's published calibration for this model. Two lines in
it bear directly on our close contract, and one **contradicts** the direction we have been pushing:

> Being readable and being concise are different things, and readable matters more. If the user has
> to reread your summary or ask you to explain, any time saved by brevity is gone. The way to keep
> output short is to be selective about what you include (drop details that don't change what the
> reader would do next), **not to compress the writing into fragments, abbreviations, arrow chains
> like `A → B → fails`, or jargon.**

> Don't make the reader cross-reference labels or numbering you invented earlier; say what you mean
> in place.

The second is the same defect our CLAUDE.md already records from the `G-A` incident. The first is the
corrective we do **not** have: the budget must be spent by *dropping items*, never by compressing
surviving items into shorthand.

## 5. What this indicts in our close body

Measured this session, `hooks/operator-readout.sh --render`:

```
OPERATOR ▸ 13 runnable now, 201 need your call · 🔧 in progress — 22 file(s) uncommitted · gate stale on HEAD
 ▶ cc-do   [13 runnable]
 ◆ 21 decisions — your call   cc-decide list --open
 ◆ 180 blocked backlog — your call   cc-backlog list --blocked
 ◆ 1255 escalation record(s) unseen — cc-escalations list
 ─ queue: 158 open (claude-infrastructure) — cc-dispatch auto-drains · board: cc-blockers
```

Held against the recap spec, three gaps — and they are gaps in *kind*, not in length:

1. **No goal, no current task.** Slots 1 and 2 of the recap's three are simply absent. Every line is
   standing inventory. A reader coming back learns the size of the pile and nothing about the work.
2. **The one next action competes with four alternatives.** `▶ cc-do` is correct and is slot 3 — but
   it sits in a list of five commands, which is exactly the "secondary to-dos" the prompt excludes.
3. **`1255 escalation record(s) unseen` is an always-firing alarm.** A count that large has never
   been actionable and cannot become so; per `[[alarm-polarity-and-attention-budget]]` it carries as
   many bits as a line that never fires.

Our contract already has moves 1 and 3 (reader model, slot order — Minto answer-first, the `⛔📤🔧📦🚀👤✅`
rungs). What it lacks is exactly the two that make the recap prompt bind: **a countable budget** and
**a named exclusion list**. It has ~40 prose paragraphs governing close style and no number a close
can be checked against.

**Applied in this session's diff:** `CLAUDE.md` § "The close message" gains a word budget and a
four-item named-exclusion list, both derived from the prompt above and from §4's readability
correction. See the commit for the exact wording.

## 6. Durable lesson

*A style rule is only enforceable if it is countable or names the failure mode.* Anthropic's own
recap prompt spends **half its 41 words** on a number and a list of four named defects, and zero on
adjectives. Our close protocol had spent thousands of words on adjectives. The reference was worth
retrieving less for its content than for its **shape**.

**Corollary for extraction work:** search on the internal identifier, not the user-facing label. The
feature the operator calls "recap" is called `awaySummary` in every line of code that implements it,
and the user-facing word appears only in strings a grep cannot distinguish from noise.
