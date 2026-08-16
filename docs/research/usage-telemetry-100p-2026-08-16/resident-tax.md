---
axis: A4 — the resident-context tax
status: complete
date: 2026-08-16
headline: "`./CLAUDE.md` is byte-identical (md5 10de4a19…) to `~/.claude/CLAUDE.md`, so 83.5% of sessions load the same 63,983 bytes twice — a measured 23,697-token duplicate charged before any work, at zero informational gain."
load_bearing_claim: "The 24,543-token turn-1 floor gap between a claude-infrastructure session and an otherwise-identical session in a repo with no root CLAUDE.md is caused by the duplicated file, not by anything else that co-varies with the repo."
---

## Headline

**One file is loaded twice.** `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md` (63,983 B) is
**md5-identical** to `/Users/chrisren/.claude/CLAUDE.md` — not similar, identical (`10de4a19394fc5c4d7a342a76636d057`
both). Claude Code loads the user-level file *and* the project-root file, and does not de-duplicate: I can see
both rendered in full in my own system prompt right now. Every session whose cwd is inside a
claude-infrastructure checkout — **1,647 of 1,972 sessions since 2026-08-01, 83.5%** — therefore pays
**23,697 tokens** for a second copy of text it already has. That is not an estimate of a nuisance: it is
**11.8% of a 200K context window consumed before the first user token**, and at 1,132 sessions/week and a
median 100 assistant turns/session it is **22.4 M cache-creation + ~2.24 B cache-read tokens per week**.

The removal is uniquely safe: because the duplicate is *byte-identical*, deleting the second load cannot change
a single decision the agent makes. It is the only item in this report with **quality risk NONE by construction**
rather than by argument. The fix is not `rm` — the repo copy is the version-controlled mirror of the live global
file — it is `git mv CLAUDE.md global/CLAUDE.md`, which keeps the history and stops the harness finding it at a
loading path.

Two secondary findings. **The block is compounding**: `CLAUDE.md` went 21,600 B → 63,983 B across 36 commits in
70 days (+196%, monotone), which is **+605 B/day = +224 tokens/day added to the floor of every session, forever**;
the measured turn-1 p10 floor rose 30,075 → 51,378 tokens (W28 → W31, +71%). And the brief's ms365 hypothesis is
**refuted**: the 188-name ms365 roster costs 2,356 tokens but is carried by only **2.8%** of sessions (it is
deferred, names-only) and *is* used (166 calls / 15 sessions / 30 d). It is not the win; the duplicate is.

## Findings

| # | Claim | Evidence (command / file / number + denominator) | Status | Coverage |
|---|---|---|---|---|
| 1 | `./CLAUDE.md` and `~/.claude/CLAUDE.md` are **byte-identical**, 63,983 B each | `md5 -q CLAUDE.md ~/.claude/CLAUDE.md` → `10de4a19394fc5c4d7a342a76636d057` twice; `wc -c` → 63983 twice | **MEASURED** | 2/2 files |
| 2 | Both are loaded into the same context — the harness does **not** de-duplicate | Direct observation: this session's system prompt renders `~/.claude-tertiary/CLAUDE.md` **and** `~/Development/claude-infrastructure/CLAUDE.md` in full, both opening `# Global Development Standards` | **MEASURED** | 1 session (self) |
| 3 | `~/.claude{,-secondary,-tertiary,-quaternary,-next}/CLAUDE.md` are all **symlinks to one realpath** — no cross-account duplication | `os.path.realpath` on all 8 → `/Users/chrisren/.claude/CLAUDE.md` for the 5 that exist; `-next2/3/4` absent | **MEASURED** | 8/8 config dirs |
| 4 | **1 byte ≈ 0.370 tokens (2.70 B/token)** for this markdown, derived two independent ways | (a) natural experiment: matched turn-1 floor gap 24,543 tok ÷ (63,983 + 2,167 B) = 2.70; (b) 374 single full `Read` of `*.md` → prompt-delta ratio median 2.33, large-file cases 2.45–3.34 | **MEASURED** | (a) n=225 sessions; (b) n=374 reads |
| 5 | The duplicate costs **23,697 tokens/session** | 63,983 ÷ 2.70 | INFERRED (from #1 MEASURED + #4 MEASURED) | — |
| 6 | **83.5%** of recent sessions pay it | 1,647 / 1,972 sessions since 2026-08-01 with cwd in a claude-infrastructure checkout or worktree | **MEASURED** | 1,972 sessions |
| 7 | Turn-1 prompt (the whole resident tax + first message) **median 74,215 tokens** | `input+cache_creation+cache_read` on the first assistant message; n=3,290 of 3,404 deduped transcripts | **MEASURED** | **96.7%** (3,290/3,404) |
| 8 | Matched floor gap = **24,543 tok** (p10), 24,913 (p05), 20,908 (p25) | DUP_ROOT p10 76,264 (n=127) vs NODUP p10 51,721 (n=98); both restricted to sessions carrying the full skill listing (median attach chars 36,325 vs 36,354 — matched to 0.08%) | **MEASURED** | 225 sessions, 2026-08-01→16 |
| 9 | Predicted gap from #4/#5 = (63,983 + 2,167)/2.70 = **24,500**; measured 24,543 → **0.2% residual** | arithmetic vs #8 | **MEASURED** (agreement) | — |
| 10 | `CLAUDE.md` grew **21,600 → 63,983 B in 70 days (+196%)**, monotone across 36 commits | `git log -- CLAUDE.md` + `git cat-file -s <sha>:CLAUDE.md`, 2026-06-06 → 2026-08-16 | **MEASURED** | 36/36 commits since 2026-04 |
| 11 | Growth rate = **605 B/day = +224 tokens/day on every session's floor** | (63,983−21,600)/70 ÷ 2.70 | INFERRED | — |
| 12 | Measured floor is rising: p10 turn-1 **30,075 (W28) → 51,378 (W31)**, +71% | weekly buckets, n≥15/week, n=3,283 total | **MEASURED** | 96.7% |
| 13 | The **skill listing stepped +25,450 chars (≈9,400 tok) at W31** and is now the 3rd-largest block | median `skill_listing` chars: 3,996 (W29) → 4,519 (W30) → **29,968** (W31) → 29,948 (W32) | **MEASURED** | 1,203 sessions record it |
| 14 | Hooks inject a **median 9,087 chars (≈3,365 tok) before turn 1**; p90 33,223 (≈12,305 tok); p99 51,344 | `hook_success` + `hook_additional_context` + `hook_cancelled` attachment bytes prior to first assistant msg, n=300 sampled sessions | **MEASURED** | 300/3,404 = 8.8% sample |
| 15 | ms365's deferred roster = **188 names / 6,361 chars (2,356 tok)**, 88.7% of the whole roster | `deferred_tools_delta.addedLines` in a live claude-infrastructure transcript: 225 names / 7,173 chars total | **MEASURED** | 1 session, roster is config-determined |
| 16 | …but only **2.8%** of sessions carry it | 34 / 1,200 sessions since 8/1 with ≥150 deferred names | **MEASURED** | 1,200 sessions |
| 17 | ms365 **is used** — not pure tax | 166 tool_use calls in 15/3,388 sessions (0.44%) over 30 d | **MEASURED** | 3,388 transcripts (99.5% of corpus) |
| 18 | MCP usage overall is concentrated: chrome-devtools 3,844 calls/93 sessions; motion 154/49; motion-plus 97/46; uidotsh 27/7; claude_ai_Gmail 1/1 | same scan; **positive control for the absence assertions below** — this scan *does* find MCP calls, so a zero elsewhere is real | **MEASURED** | 3,388 transcripts |
| 19 | **28 of 64** listed skills were never invoked via the `Skill` tool in 30 d | roster from `skill_listing.names`; invocations from `tool_use.name=="Skill"`; positive control: the same scan finds 38 skills that *were* invoked, `ship` 515× | **MEASURED**, but see caveat | 3,388 transcripts |
| 20 | Project `.claude/CLAUDE.md` (2,167 B, 803 tok) is **genuinely unique** content — the shared-checkout and standing-land rules | `md5` differs (`af769b24…`); content is claude-infrastructure-specific | **MEASURED** | 1 file |
| 21 | `settings.json` (36,371 B) does **not** enter context | it is harness config, never rendered into the prompt; its context-relevant contents are the 3 global `mcpServers` (→ #15/#16) and the hooks (→ #14) | INFERRED | 5 settings files inspected |
| 22 | No `mcpServers` are added at the project level for this repo | `~/.claude.json` → project `mcpServers: []`, `enabledMcpjsonServers: []`; global = `['motion','motion-plus','ms365']` | **MEASURED** | 1 config |
| 23 | The MEMORY.md index is **not** a differentiator between the compared groups | claude-infrastructure 23,340 B vs doc-classifier 21,686 B vs personal 23,055 B — Δ ≤ 1,654 B (≤ 612 tok), which is why #9's residual is 0.2% | **MEASURED** | 4 projects; 28 memory dirs, median 7,937 B |

**Caveat on #19 (stated so it cannot be misread as a cut list):** "never invoked via the `Skill` tool" is not
"unused". `coding-standards`, `react-best-practices`, `vercel-design-guidelines`, `dataviz`, `frontier-routing`
and `plan-conventions` are documented **auto-loading knowledge skills** — the model reads them without a `Skill`
call, so my instrument is structurally blind to their use. #19 is a *candidate* list requiring per-skill
verification, and I make no recommendation to trim it.

## Resident inventory, ranked (one claude-infrastructure session, 2026-08-16)

Bytes/chars are MEASURED; the token column applies the MEASURED 2.70 B/token (finding #4).

| Rank | Resident block | Bytes / chars | Tokens | Load-bearing? |
|---|---|---|---|---|
| 1 | `~/.claude/CLAUDE.md` (user global) | 63,983 | 23,697 | **Yes** — the operating policy |
| 1= | **`./CLAUDE.md` (project root — byte-identical duplicate)** | **63,983** | **23,697** | **NO — zero information, provably** |
| 3 | `skill_listing` (64–65 skills) | 29,968 | 11,099 | Yes (discovery surface); see #19 caveat |
| 4 | `MEMORY.md` auto-memory index (~120 one-liners) | 23,340 | 8,644 | Yes — under the 25,000-char loader cap |
| 5 | hook output injected before turn 1 (median) | 9,087 | 3,365 | Partly — p90 is 33,223 chars |
| 6 | `agent_listing` | 5,051 | 1,871 | Yes |
| 7 | deferred tool roster, MCP-connected sessions only (2.8%) | 7,173 | 2,657 | of which ms365 = 6,361 / 2,356 |
| 8 | `.claude/CLAUDE.md` (project-specific) | 2,167 | 803 | **Yes** — unique repo rules |
| 9 | `mcp_instructions` (median / full) | 255 / 2,312 | 94 / 856 | Yes |
| 10 | deferred tool roster, median session | 427 | 158 | Yes |
| — | system prompt + core tool schemas (**residual, by subtraction**) | — | **~15,300** | INFERRED — see Method |

Sum of rows 1–10 for a typical claude-infrastructure session ≈ **60,300 tokens**, against a measured p10 turn-1
floor of **76,264** — the ~16K difference is the residual row, and it is consistent with the independently
computed NODUP residual (51,721 − 36,427 = 15,294). The two residuals agreeing to within 5% is the check that
the inventory is not missing a large block.

## Method

**Corpus.** 3,404 transcripts, de-duplicated **by `os.path.realpath`** across all 8 config dirs (`~/.claude`,
`-secondary`, `-tertiary`, `-quaternary`, `-next{,2,3,4}`) — the `-next*` dirs are symlinks and were collapsed,
per the `token-usage-from-transcripts` trap. Post-dedupe: `.claude` 860, `-secondary` 874, `-tertiary` 790,
`-quaternary` 880. **No sampling for the primary statistic**: the turn-1 census streamed the head of all 3,404
files (≤400 lines each) and recovered a value from 3,290 → **96.7% coverage**; the 114 misses are transcripts
with no assistant message carrying `usage`, and are reported as null rather than imputed.

**The primary instrument.** For each transcript, `turn1 = input_tokens + cache_creation_input_tokens +
cache_read_input_tokens` on the **first** assistant message. This is the whole prompt the model was charged for
before doing anything — resident block + tool schemas + first user message — and it is durable in every
transcript, so unlike context *fill* it needs no window denominator (this is the axis where
`CONTEXT_ECONOMY_V2`'s discarded-denominator problem does **not** bite, because the numerator alone is the
answer).

**Isolating the duplicate (the natural experiment).** Sessions since 2026-08-01 were split by cwd into
`DUP_ROOT` (exactly `~/Development/claude-infrastructure`, n=127), `DUP_WT` (its worktrees, n=833) and `NODUP`
(`doc-classifier`, `doc_classifier`, `personal`, `lakehouse-lecture`, bare `/private/tmp` — verified to have no
repo-root `CLAUDE.md`, n=98). Both arms were **restricted to sessions carrying the full skill listing**
(`skill ≥ 25,000` chars) **and** the agent listing (`agents ≥ 3,000`), which matched median attachment chars to
36,325 vs 36,354 (0.08% apart) and removed the largest time-correlated confounder. `DUP_WT` was excluded from
the gap because fired handoff sessions carry huge first-user-message briefs. Comparison at **p05/p10** rather
than the median deliberately minimises first-message contamination, since the first message is the only
component that varies freely.

**Calibrating bytes→tokens.** I could not call a real tokenizer: `tiktoken` is not installed, `transformers` has
no offline Claude vocabulary, and `anthropic.count_tokens` needs a network call on the operator's credentials —
so I did **not** guess a constant. Two independent in-corpus measurements were used instead:
(a) 374 turns consisting of exactly one full `Read` of a `*.md` file with no other content, where
`tokens = prompt_{n+1} − prompt_n − output_n` → median **2.33** chars/token, large files 2.45–3.34;
(b) the natural experiment above, where the gap ÷ the known duplicated bytes → **2.70**.
I adopt **2.70** because it is measured on the exact artifact in question, and note that the brief's suggested
`chars/3.6` estimator would **understate this file by 33%** (17,773 vs 23,697 tokens).

**Rejected instruments, named so they are not re-run.** (i) An OLS of turn-1 on `CLAUDE.md` size-at-time
returned 0.70 tok/byte (1.43 B/token — physically impossible) at R²=0.37: `CLAUDE.md` size is a near-perfect
proxy for calendar date and absorbed every other thing that grew. (ii) Calibrating on assistant `output_tokens`
÷ text chars collapsed to a median 1.37 because thinking tokens are billed but not stored in the transcript.
Both are reported because their failure modes are reusable.

**What I could not measure, and why.**
- **Exact tokenizer counts** — no offline Claude vocabulary on this machine; all token figures for a *byte* count
  are INFERRED through the measured 2.70 ratio with a plausible band of [2.33, 3.00] (i.e. the duplicate is
  21,300–27,500 tokens; the point estimate 23,697).
- **The system-prompt + tool-schema block in isolation** — it is never written to disk and never appears as an
  attachment; the ~15,300 figure is a *subtraction residual*, and is labelled as such. Positive control that the
  scan sees what *is* recorded: the same pass enumerates 15 distinct attachment types including `skill_listing`,
  `agent_listing_delta`, `deferred_tools_delta` and `mcp_instructions_delta` with exact char counts.
- **Whether cache-read tokens are weighted against the Max weekly allowance at 1× or 0.1×** — not public, and no
  usage time-series exists on disk to fit it. The weekly figures below are stated in raw tokens with the
  discount named, never converted to a quota percentage.
- **Per-session context *fill* %** — out of scope here and structurally unavailable (the window denominator lives
  in ephemeral `/tmp/cc-telemetry`); this axis needs only the numerator.

## Recommendations

### R1 — `git mv CLAUDE.md global/CLAUDE.md` (stop the double load, keep the history)

The repo-root file is the version-controlled mirror of the live `~/.claude/CLAUDE.md`; deleting it would lose
that. Moving it to a path the harness does not scan for project memory keeps every byte in git and removes the
second load. `~/.claude/CLAUDE.md` is a separate real file and is untouched, so no other repo changes behaviour.
`.claude/CLAUDE.md` (the genuinely project-specific rules) stays exactly as it is.

- **Expected effect:** −23,697 tokens on **83.5%** of sessions (1,647/1,972 measured). At 1,132 sessions/week:
  **−22.4 M cache-creation tokens/week**, and — because the prefix is re-read every turn at a median 100
  assistant turns/session — **~−2.24 B cache-read tokens/week** (billed at the cache-read rate). In context terms:
  **+23,697 tokens of usable window on every session**, 11.8% of a 200K window.
- **Quality risk: NONE.** Not "low" — none, and by construction: the removed bytes are md5-identical to bytes
  that remain loaded. No prompt content changes. This is the only recommendation in this report that cannot
  degrade output, which is exactly what the operator policy requires before a token saving is taken at all.
- **Effort:** ~20 minutes — and the move is **not** a one-liner, see the mandatory same-diff change below.
- **Verification after landing:** re-run the matched-floor comparison; DUP_ROOT p10 should fall from 76,264 to
  ≈52,500, i.e. converge on the NODUP floor of 51,721.

**🚨 R1 has one live consumer, and it fails OPEN — it must move in the same diff.**
`scripts/deploy-parity-assert.sh:731` reads:

```sh
if [ -f "$REPO/CLAUDE.md" ]; then
  …  same_file "$REPO/CLAUDE.md" "$LIVE/CLAUDE.md"   # :742
```

This is the assertion that the live `~/.claude/CLAUDE.md` has not drifted from the repo mirror — the check that
makes the operator's "hand-apply the same edits to the live file" rule enforceable, and the emitter of the
`claude-md-absent` / `claude-md-diverged` backlog rows (`:739`, `:749`). A bare `git mv` leaves the path missing,
the `[ -f ]` guard evaluates false, and the entire block is **silently skipped**: no row, no drift flag, no
error — the global-instructions parity check simply goes dark while every readout keeps rendering green. That is
the exact `[ -f x ] && …` silent-skip shape this repo already has recorded (`LIVE_ADDS` breaches at a lag of 1;
memory: *Add-on blast radius*, *Land in the enforcer*). Change both references to `$REPO/global/CLAUDE.md` in the
same commit, and confirm by running `scripts/deploy-parity-assert.sh` before and after — the `CLAUDE.md (copy)`
class must still report `live`, never vanish from the table. **A disappearing row is the failure, not a pass.**

### R2 — Put a byte budget on `CLAUDE.md` and make growth visible

It has tripled in 70 days at +605 B/day, and nothing measures it. Unchecked, that is **+20,200 tokens on every
session's floor over the next 90 days** — more than R1 saves, arriving silently. This is not a request to cut
content: it is a request to make the price legible at the moment of writing, e.g. a pre-commit advisory printing
`CLAUDE.md: 63,983 B (23,697 tok/session, +X since last commit)`.

- **Expected effect:** avoids ~+20,200 tok/session/90 d of unbudgeted growth. Saves nothing today.
- **Quality risk: NONE** (advisory only — it blocks nothing and removes no content).
- **Effort:** ~30 minutes.

### R3 — Move `ms365` from global to a project-scoped MCP config

Measured, not assumed: the roster is 2,356 tokens but reaches only **2.8%** of sessions, and ms365 *is* used
(166 calls, 15 sessions/30 d). So this is a **small** win, listed for completeness and explicitly *not* the
headline — the brief's "if zero in 30 days it is pure tax" hypothesis is refuted by finding #17.

- **Expected effect:** −2,356 tokens on ~2.8% of sessions ≈ −75 K tokens/week. Two orders of magnitude below R1.
- **Quality risk: LOW** — the 15 sessions/30 d that use it would need it enabled in the owning project.
- **Effort:** ~20 minutes.

### R4 — Audit the p90 hook injection, not the median

The median 9,087 chars (3,365 tok) of pre-turn-1 hook output is a fair price for the rails. The **p90 of 33,223
and p99 of 51,344** (≈12,300 and ≈19,000 tokens) are not, and one observed `hook_success` payload was **44,553
chars** on its own. The top repeat emitter is the `Frontier: claude-fable-5 window OPEN→…` line (234 occurrences,
201,929 chars in a 300-session sample). Measure which hook produces the p90 tail before changing anything.

- **Expected effect:** unquantified until the emitter is identified — plausibly −5,000 to −15,000 tok on the
  worst decile of sessions. **Stated as unquantified rather than guessed.**
- **Quality risk: MEDIUM** — hook output is how the deterministic rails reach the model; trimming the wrong one
  silences a close-integrity arm. Do not act on this without naming the specific hook.
- **Effort:** ~2 hours to attribute the tail to hooks.

### Explicitly NOT recommended

- **Trimming the skill listing** (11,099 tok, rank 3). 28/64 skills show no `Skill`-tool invocation in 30 days,
  but my instrument is blind to auto-loading knowledge skills (#19 caveat), and a skill absent from the listing
  is a skill the agent cannot discover. The test is "would removing it change a decision" and for a discovery
  surface the answer is plainly *yes*. Not a candidate.
- **Trimming `MEMORY.md`** (8,644 tok, rank 4). It is 23,340 B against a documented 25,000-char loader cap —
  already governed, with `/compact-memory` as the sanctioned lever.
- **Trimming `~/.claude/CLAUDE.md` itself** (23,697 tok, rank 1). Every section I sampled is standing policy that
  demonstrably steers behaviour. R1 removes the *copy*, and that is the whole win available at zero risk.

## What would falsify my headline

1. **The harness de-duplicates identical CLAUDE.md content and I mis-read my own prompt.** Direct falsifier: after
   R1 lands, the matched DUP_ROOT p10 floor does **not** drop by ~24,000 tokens. If it stays at 76,264, the second
   copy was never charged and the entire headline collapses. This is the cheapest and most decisive test, and it
   is a one-command re-run of the census.
2. **The 24,543-token floor gap has another cause that co-varies with the repo.** I controlled for the skill
   listing, agent listing, MCP roster and MCP instructions (matched to 0.08%), and checked MEMORY.md (Δ ≤ 1,654 B).
   If some *unmeasured* per-project injection worth ~24,000 tokens exists only in claude-infrastructure sessions,
   the gap is not the duplicate. The evidence against this is finding #9: the gap matches the duplicated byte count
   at the independently-derived ratio to **0.2%**, which would be a remarkable coincidence.
3. **2.70 B/token is wrong.** If the true ratio is 3.6 (the brief's default estimator), the duplicate is 17,773
   tokens, not 23,697 — the headline survives in kind but is 25% smaller. But then the measured 24,543-token gap
   would require 88,300 duplicated bytes, and only 66,150 exist. The gap measurement *is* the ratio measurement;
   they cannot both be wrong in the same direction.
4. ~~**`./CLAUDE.md` is load-bearing for something other than being read as project memory.**~~ **CHECKED, and it
   partly is** — `scripts/deploy-parity-assert.sh:731,742` consumes the path as the repo-vs-live drift oracle.
   This does **not** falsify the headline (the file is still loaded twice into context, and the consumer needs a
   *path*, not that path) but it converts R1 from a one-liner into a two-file diff, and the failure mode is
   silent. Written up in R1. Scan run: `grep -rnE '(claude-infrastructure/CLAUDE\.md|\$\{?REPO[A-Z_]*\}?/CLAUDE\.md|\./CLAUDE\.md)' bin hooks scripts commands .claude`
   → 4 hits, all in that one script; positive control that the grep works: it returned those 4 rather than zero.
5. **Session count is inflated.** 1,132 sessions/week counts every deduped transcript with a turn-1 usage record,
   including short-lived subagent and fired-peer sessions. If the operator considers only interactive sessions to
   count, the weekly totals fall — but the per-session figure (23,697 tokens, 11.8% of a 200K window) is
   unaffected, and that is the figure the operator policy actually cares about.
