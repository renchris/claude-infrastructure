# Adapting to Opus 5 — what the infrastructure and the operator should change

**Date:** 2026-08-01 · **Verified against:** `origin/main` @ `9b969edb`
**Sources:** Anthropic *Prompting Claude Opus 5*, *Effort*, *Migration guide (4.8→5)*, *Task budgets*
(all fetched verbatim this session) · Opus 5 System Card (2026-07-24) via the prior extraction in
[`OPUS5_ADOPTION_AND_PROMPTING_2026-07-24.md`](OPUS5_ADOPTION_AND_PROMPTING_2026-07-24.md) ·
direct measurement of the live fleet.

---

## The answer in one paragraph

**The model bump landed; the behavioral adaptation did not.** `claude-opus-5` is live everywhere —
`opus_latest`, every role, the `claude()` launcher at `--effort high`, 25 live processes on the 2.1.219
binary. But this repo is, structurally, a **compensation layer for three Opus-4.8 weaknesses**, and
Opus 5 inverts all three. Rules that used to correct the model now push in the direction it already
leans. The fix is not "trust it more" — the card shows Opus 5 is a *more confident* fabricator. The
fix is a clean split: **delete the prose that tells the model to verify; keep and strengthen the
machinery that verifies the model.**

| 4.8 weakness | What we built | Opus 5 reality (Anthropic's words) |
|---|---|---|
| Stopped early, faked "done" | Session Close Protocol, `completion-assert`, `session-continue`, the ledger — plus the "🔧 never yields" rule | "completes full tasks rather than leaving stubs"; "verifies its own work without being told to"; **"REMOVE [verification instructions]… the same applies to legacy harness scaffolding that adds separate verification steps"** |
| Context rotted; sessions died | Context Stewardship at 25/35/50/73/75, `/handoff`, split-pane firing, `limit-recover`, transcript transplant | **1M window, default *and* maximum**; instruction-following, tool-calling and reasoning "stay consistent throughout the window" |
| Under-parallelised | 🚨 PARALLELIZE BY DEFAULT · "No parallelism cap" · N=12 · Agent-Teams-by-default | **"delegates to subagents more readily than prior models"**; "do not use subagents to verify or double-check your own work"; "keep spawn counts low"; and it **"can expand the scope of a task"** |

---

## What is already done (do not redo)

- **Model flip: complete.** `opus_latest: claude-opus-5`; `lead_default`, `default_teammate`,
  `teammate_mechanical`, `teammate_research`, `research_worker`, `frontier_access.fallback` all on
  `claude-opus-5`. Branches `feat/opus-5-upgrade` and `opus5-activate-land` are fully merged
  (`main..<branch>` = 0 on both). The 2026-07-24 adoption doc still says "STAGED, not executed" —
  **that status line is stale; the flip happened after it was written.**
- **Session effort already correct.** `.zshrc claude()` → `--model claude-opus-5 --effort high`.
  Measured: 13 of 14 sampled sessions at `high`. This matches Opus 5's own default.
- **Concision rule: landed 01:05 today** (`9b969edb`) as § Communication Discipline + a closing
  `<tone_preference>` block — chat brevity, narration cadence, written-file length, and
  "never add verification you were not asked for". This is the single most important Opus 5 prompt
  change and it is done. **But see D1 below — it landed in only one of the two files.**

## Measured state of the live fleet (2026-08-01 01:03)

| Measure | Value |
|---|---|
| Live `claude` processes | 25, all on `~/.claude-219/…` ⇒ all Opus 5 |
| Registered sessions (`cc-context`) | 38; 32 share cwd `claude-infrastructure` |
| Context window | **1,000,000 on 39/39 telemetry files** — the 200k/1M ambiguity is gone |
| Context fill | min 6% · **median 17%** · max 70% |
| Process RSS | median 576 MB · max 1281 MB · **total 10.2 GB** |
| Worktrees | 123 |
| Load average | 14.86 / 20.89 / 23.03 |
| Resident prompt corpus | 88 KB (~22k tokens) before the first user word |

---

## D. The open gaps, in priority order

### D1 — The live global `~/.claude/CLAUDE.md` never got the concision fix
`~/.claude/CLAUDE.md` is a **separate real file, not a symlink** (`-rw-------`, Jul 31 12:51). The
project CLAUDE.md is the one `9b969edb` edited. So § Communication Discipline and `<tone_preference>`
are live **only for sessions running in claude-infrastructure** — every other project still loads the
verbose-by-default corpus. The project CLAUDE.md documents this exact hazard ("apply the same edits
there"); it was missed this time. *Cheapest high-value fix on this list.*

### D2 — Two rules in the resident corpus are now factually false or actively harmful
Both appear in **both** CLAUDE.md files:

- `:190/:191` — **"Default model = Opus 4.8 @ effort max."** False on both halves (lead is
  `claude-opus-5` @ `high`, measured). The entire § Frontier Tier Routing is built on this premise.
- `:171-173/:172-174` — **"No parallelism cap; decomposition determines count… Default N=12"**, plus
  🚨 **PARALLELIZE BY DEFAULT** at `:130/:131`. Anthropic's guidance for Opus 5 is the opposite:
  cap delegation, don't delegate what you can do in a handful of tool calls, don't use subagents to
  verify your own work, prefer one subagent to several. We are spurring a horse that is already
  bolting.

### D3 — Effort re-tier: the config was written but nothing reads it
`model-config.yaml` carries a complete Opus 5 ladder — `opus5_default: high`,
`opus5_coding_agentic: medium`, `opus5_capability_sensitive: xhigh`, `opus5_routine: low`.
**Grep confirms the only file referencing those keys is `model-config.yaml` itself.** Meanwhile:

- `effort_defaults.default: max` still governs teammates and workflow slots. Its certification note
  is explicitly dated 2026-06-30 and was measured **on Opus 4.8**. Anthropic: "run a fresh effort
  sweep… rather than reusing" and `max` "can be prone to overthinking".
- `settings_floor: xhigh` now makes `scripts/effort-parity-assert.sh` **convict Opus 5's own
  recommended default** — it emits `PS-WARN live session --effort high < floor xhigh` for 8 live
  sessions and exits DRIFT. The guard is inverted. Live `~/.claude/settings.json` is at
  `effortLevel: medium`, disagreeing with both. Three-way drift: floor `xhigh` / launcher `high` /
  settings `medium`.

### D4 — Context thresholds are 4.8-era constants against a 1M window
The *mechanism* is sound — `hooks/lib/context-econ.sh:80` explicitly refuses to impute the window
size and reads `.window` from telemetry (a prior hardcoded-1M bug is documented right there). Only
the **constants** are stale:

| Knob | Now | At a 1M window that means | Suggested |
|---|---|---|---|
| `T_IDLE` (waiting-recycle) | 35 | recycle an idle session at **350k tokens** | ~60 |
| `T_IDLE_FLOOR` | 25 | …decaying to **250k** | ~45 |
| `T_NUDGE` | 50 | pause-point advisory at 500k | ~70 |
| `boundary-handoff T` | 73 | 730k | ~85 |
| `T_BUSY` | 75 | 750k | ~85 |

Median live fill is 17% — sessions are being treated as "filling up" at ~170k of a 1M window that
Anthropic says holds quality throughout. This is the single biggest lever on session sprawl,
worktree sprawl and machine load.

**Counterweight, so this is not naive:** process RSS is a genuinely independent axis
(`RSS_PAGE_MB=1500`, page-only, never auto-recycle) and only a *new process* resets it. But that
argues the *same* way — per-process baseline RSS is being paid 25 times over, so consolidating to
fewer, deeper sessions lowers total RSS even as each session's own RSS rises.

*(Also settled: `autoCompactEnabled: false` in settings.json — that is why 39/39 compactions are
manual. There is genuinely no net at the ceiling; but at 1M the ceiling is ~5× further away than the
thresholds assume. `boundary-handoff.sh:88`'s "autocompact at 90" comment is stale.)*

### D5 — The Follow-On Gate now fights the harness
Claude Code's own system prompt ships, near-verbatim, Anthropic's recommended Opus 5 scope-constraint
paragraph ("The requested scope is the deliverable — don't quietly narrow, widen, or transform it").
CLAUDE.md's **Follow-On Gate (F1–F4)** says adjacent work is "pursued WITHOUT re-affirmation",
appending `Scope (grown): +<item>`. On 4.8 that corrected under-delivery. On a model Anthropic warns
"can expand the scope of a task", it is an accelerant aimed the same way — and it contradicts the
harness. Keep F1–F4 for *continuation without asking*; drop its scope-**growth** licence.

### D6 — Frontier tier: the delta it was built on has largely closed
`pricing_per_mtok`: `claude-fable-5: [10, 50]` vs `claude-opus-5: [5, 25]` — Fable is exactly 2×.
The card says Opus 5 is "not more capable overall" than Fable 5 but "on many evaluations… comparable
to—and in some cases ahead of" it, and the SSOT already carries the note that "Fable's cost-justified
delta has collapsed for most work". The whole `/frontier-hole` · `/frontier-run` ·
`/frontier-campaign` apparatus, the ledger, and the per-session spawn budget are premised on a gap
that is now narrow. Shrink to the residual where Fable/Mythos genuinely lead.

### D7 — Corpus weight
94% of the global CLAUDE.md (356 of 377 lines) is repeated verbatim in the project CLAUDE.md — ~25.8 KB
duplicated in every session in this repo. `MEMORY.md` is 25,433 B against a 24,985 B loader cap, so its
newest entries silently never load. Total resident corpus ~88 KB / ~22k tokens. Emphasis devices:
73 and 78 ALL-CAPS words respectively. Opus 5 "performs well out of the box on existing Opus 4.8
prompts" — the weight is buying less than it did.

### Verified negative — task budgets are not available to us
`output_config.task_budget` (beta `task-budgets-2026-03-13`) is the natural forcing-function for the
long-horizon self-verification death-loop the card documents. But: **"Task budgets are not supported
on Claude Code or Cowork surfaces."** Do not design around it for CC sessions.

---

## What the human should change

1. **Fewer, deeper sessions.** 25 live processes, median 17% fill, 123 worktrees, load ~20. That
   breadth was correct when each session was a shallow, rot-prone context needing supervision. At 1M
   consistent-quality context with good self-coordination, depth beats breadth. Reserve split-panes
   for work you actually want to *watch*, not for throughput.
2. **Front-load the whole spec, then leave it alone.** "Performs best when given the complete task
   specification up front and left to run." Drip-feeding mid-task is now how you *get* scope
   expansion and narration.
3. **Stop reaching for `max`.** `high` is the default; `low`/`medium` are genuinely strong on Opus 5
   and are the recommended primary cost/latency control. Reserve `max` for pure reasoning/maths.
4. **Stop reflexively escalating to Fable** — 2× the price for a delta that has mostly closed.
5. **On review tasks, say "report everything, I'll filter."** Opus 5 takes "only high-severity" or
   "be conservative" *literally* and reports less.
6. **Keep trusting gates over narration — more, not less.** Opus 5 is more accurate *and* a more
   confident fabricator; the artifact is the evidence, its stated confidence is not.

## Sequencing

- **Now, cheap:** D1 (sync the global file), D2 (two false rules).
- **Next:** D3 (wire the `opus5_*` ladder, un-invert the effort floor), D4 (rescale five constants).
- **Then, design work:** D5, D6, D7.

**One principle to carry through all of it:** remove *prompt-level* verification and parallelism
pressure; keep every *out-of-model, fail-closed* gate. Opus 5 will rationalise a prose rule — the
card documents it fabricating consent and working around blocks — but it cannot rationalise a
chokepoint. This repo already knows that (*enforcement must live at the chokepoint*); Opus 5 makes it
decisive rather than stylistic.
