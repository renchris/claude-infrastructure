# Haiku 5.5 + Claude Code 2.1.293 — which roles, at which effort (2026-10-07)

**Answer.** Advance the binary to 2.1.293 (activation 50, operator-run), and treat that move as the
model move too: on 2.1.293 the alias `haiku` already means Haiku 5.5, so the retrieval role changes
model the moment a new shell starts, whatever the config says. Haiku 5.5 takes **one role: codebase
retrieval, at effort medium, passed explicitly**. Every other role stays on Opus 5.5. The config
flip (`haiku_latest`) follows the activation; until then the id is parked in `versions.haiku_staged`.

Run ledger: [`UPGRADE.md`](UPGRADE.md). Everything below is cited to `notes/` (card facts carry PDF
page numbers; `pack/` holds the fetched sources).

## What is measured, and what is the vendor's word

- **Ours (live, 2.1.293):** gate GREEN ×2 on three accounts; resume through the symlinked
  `~/.claude-next/projects` works; Write under auto in `-p` works and `backup-before-write` fires; an
  Opus 5.5 lead at `--effort high` spawning Explore with `model: "haiku"` was served
  `claude-haiku-5-5` at effort high.
- **Ours (static binary read, not run):** `notes/bin293-probes.md`, `notes/gap-0*.md`.
- **Vendor:** the System Card (144 pp., seven page-range readers, every fact re-checked by a second
  reader: 912 read, 894 confirmed, 18 corrected, 0 refuted, 169 added) and the platform pages.
- **Not measured by anyone here:** plan-quota draw per Haiku 5.5 token; retrieval quality on our own
  lookups by effort level; the quota cost of helper calls that now think.

## The table

| Use case | Model @ effort | Evidence | Conv. | Moves it |
|---|---|---|---|---|
| Codebase retrieval (Explore, `model: "haiku"`) | **Haiku 5.5 @medium**, effort passed on the spawn | Moves with the binary regardless. Versus Haiku 4.5: coding prompt-injection success 0.08% vs 58.40% (p51), input hallucination 1.88 vs 3.96 (p66), ignoring constraints 2.06 vs 4.46 (p62). Medium is the vendor default; at low it skips searches and stops early (prompting guide), and wide search collapses at low (WANDR 3.5% vs Haiku 4.5's 6.4%, p123). | 80% | our low/medium/high A/B on file:line lookups against Haiku 4.5 |
| High-volume extraction / classification slot | stay Opus 5.5 (workflow-lean) | The vendor positions Haiku 5.5 here and single-answer work is flat across effort (HealthBench 59.9% low to 61.6% max, p133). But quota draw per token is not stated, its tokenizer counts ~30% more tokens, and requests over 100,000 prompt tokens bill at 5×. | 65% | a quota-draw measurement plus one extraction A/B |
| Mechanical code-writing teammate | stay Opus 5.5 @medium | Terminal-Bench 4.0: 39.2% vs Sonnet 5.5 70.6% and Opus 5.5 66.4% (p115); false completion claims are the worst of the 5.x models (1.89 vs Opus 1.48, p66); it is outside the binary's native read-before-write guard; our enforce hook denies a Haiku teammate. | 92% | — |
| Verifier / judge | stay Opus 5.5 | Self-preference bias +0.23 on a 0–9 scale and ~6% unscorable ratings as a grader (p79); closed-book recall net 0.12 vs Opus 0.58 (p80). | 90% | — |
| Research and synthesis workers | stay Opus 5.5 | The card names "a relative deficit in the reasoning required to succeed on complex, iterative tasks" (p18); it starts strong and does not improve with iteration (p17–18). | 90% | — |
| Helper calls (titles, summaries, WebFetch summaries) | leave on the alias (Haiku 5.5 after the move) | Not a choice we made: the small/fast model follows the alias. These calls now always think. `ANTHROPIC_SMALL_FAST_MODEL` pins the helper alone. | 70% | a meter read around a helper-heavy interval |

Two properties of Haiku 5.5 any slot must handle: a safety refusal returns HTTP 200 with
`stop_reason: "refusal"` and **there is no fallback model** (1.8% of Terminal-Bench trials ended
that way, p115); and it used a leaked answer without saying so 17.3% of the time (Haiku 4.5 1.6%,
p83), so it should not grade or verify work it can see answers to.

## The binary: 2.1.284 → 2.1.293

No blocker. 47 rated changelog items; after the referee, 14 stand as cautions, 20 were downgraded
and 13 refuted (`notes/cc293-referee.md`). What you take with it:

- `haiku` and the helper model become Haiku 5.5; a `model: "haiku"` spawn inherits the lead's effort.
- Headless sessions kill a backgrounded Bash command after 10 minutes (one-shot `-p`) or 30 minutes
  (streaming) unless the call passes its own `timeout`. Interactive panes are exempt. The changelog
  says only "30 minutes"; the 10 is from the binary.
- A per-agent token budget sits behind a server flag: off on all four accounts today, advisory only,
  Agent-tool spawns only. `CLAUDE_CODE_RIPPLING_TULIP=0` in settings `env` disables it for good.
- WebSearch's 1,000-per-session stop now refills at 100 per hour.
- 2.1.293 is itself the last fix in four regression clusters (background sessions, the daemon
  control path, cloud sessions, subagent prompt text). Our background-job rails
  (`handoff-fire.sh --bg` parsing, `lr-upgrade.sh`) were measured on 2.1.284 and are not re-measured.
- Held-open issues: 1 of 16 fixed; nothing restores a spawn cap. `SPAWN_DEPTH=1` stays load-bearing.

## Still owed (in order)

1. **Operator:** run activation 50; log `next3` in (then re-gate it for Haiku 5.5).
2. **After activation, one diff:** flip `haiku_latest` / add `haiku_prior` / clear `haiku_staged`,
   repoint `roles.research_retrieval`, and rewrite the emitters the sweep cannot see
   (`notes/census-haiku.md`: `scripts/handoff-fire.sh:13816` probe model, the dated-id sites in
   `bin/claude-accounts`, `hooks/model-permission-decider.py`, `bin/cc-memory-extract`,
   `scripts/headless-precondition-probe.sh`, and their pinned tests).
3. **Measure:** the retrieval A/B by effort; quota draw per Haiku 5.5 token; then pass `effort` on
   every `model: "haiku"` spawn site (research-subagents skill still says "no effort param").
4. **Operator-owned settings edit:** `CLAUDE_CODE_RIPPLING_TULIP=0` in the settings `env` block.
