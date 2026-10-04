# Prompt audit — shard "commands" (commands/*.md, 25 files)

## Assumptions (Step 0)
- Scope: the 25 slash commands in /Users/chrisren/Development/.worktrees/wt-cc-003409-15565/commands/. Read-only; nothing in the repo was edited. Hunks: /tmp/capi-audit/commands_hunks.json; unified diff against a scratch copy: /tmp/capi-audit/commands.diff (each old_text occurs exactly once).
- Target model: Opus 5.5 (claude-opus-5-5) at effort high for the commands. evolve-skill's scorer pins claude-opus-5-5 itself. Fable 5.1 and Sonnet 5.5 are relevant only where routing text names them.
- Coverage: all small and mid-size files were read in full. handoff.md, limit-recover.md and compact-memory.md are each 70K or more, so they got signal greps (model ids, launchers, effort, pressure words, choreography) and a full check of every repo path they reference, with targeted reads around each hit. They were not read line by line.
- Keep-list as briefed: operator rulings, "Why" lines, measured incidents, hook-enforced rules (pr.md's 400 words is enforced by hooks/pr-gate.sh CC_PR_MAX_WORDS), and safety pressure (cc-relogin, git and credentials).

## Summary
The highest-impact findings are stale facts that break execution or mislead it, not dated prompt idioms:
1. **evolve-skill.md:23-34**: the scorer runs `claude-latest -p --model claude-opus-5-5`. `claude-latest` resolves to 2.1.114 (~/.claude-versions/current), and the API refuses claude-opus-5-5 below 2.1.280 (model-config.yaml:96-103; memory headless-trial-arm-model-from-init-line). Every scoring call fails or runs another model. Fix: use `"$(cc-claude-bin)"`, which resolves 2.1.284. `--bare` is still a valid flag on 2.1.284.
2. **wrap.md**: three claims are contradicted by scripts/wrap-ledger.sh.
   - "👤 not computed on the pull path" (L26-34, L80, L83, L133). The ledger resolves CLAUDE_CODE_SESSION_ID (wrap-ledger.sh:702-712, 2026-09-05). A live run gave BLOCKED_SRC=CLAUDE_CODE_SESSION_ID.
   - "⛔ cannot be derived from git" (L139-144). The ledger computes ⛔ from class-C packets (wrap-ledger.sh:24, 1113-1303, 2289).
   - "relay at the TOP of your close / a single fenced thing" (L40-46). This contradicts wrap.md's own L171 ("Line 1 stays wrap-ledger's rung readout") and the global rule that the handed command is an inline-code span, not a fence.
3. **Hardcoded retired model and launcher facts**:
   - limit-recover.md:317 names `claude-opus-4-8` as the fable fallback. The SSOT's frontier_access.fallback is claude-opus-5-5, and lr-fire-resume.sh:122 already dropped the same hardcode.
   - handoff.md:528 example says "Opus@max", but the same file's table (L406) says the default is high.
   - handoff.md:356 says to relaunch on "another `claude-nextN`". Those launchers were deleted; accounts.json lists claude/claude2/claude3/claude4.

Counts: Group 1 = 3 (commit.md:41 update suppressor, accounts.md duplicate rule, research.md manifest fiction). Group 2 = 19 (stale facts and internal contradictions). Group 3 = not applicable (no tool descriptions). Group 4 = not applicable (no request-building code). The one CLI invocation, evolve-skill, is covered under Group 2.

## Findings (highest confidence first)

| id | Location | Pattern | Why | Conf | Action |
|---|---|---|---|---|---|
| commands-01 | evolve-skill.md:23-26 | G2 volatile specifics | claude-latest = 2.1.114 cannot run claude-opus-5-5 (needs >=2.1.280). `--bare` auth is API-key only (2.1.284 --help) | high | rewrite |
| commands-02 | evolve-skill.md:30-34 | G2 volatile specifics | same binary in the generate and score commands | high | rewrite |
| commands-03 | limit-recover.md:316-317 | G2 / 1d pinned retired model | claude-opus-4-8 vs SSOT frontier_access.fallback=claude-opus-5-5 | high | rewrite to SSOT key |
| commands-04 | handoff.md:528 | G2 intra-file contradiction | "Opus@max" (2026-07, Opus 4.8 era) vs L406 default @high (2026-09-22) | high | rewrite |
| commands-05 | handoff.md:356 | G2 stale command | claude-nextN launchers deleted (accounts.json launchers; research.md:87) | high | rewrite |
| commands-06 | wrap.md:26-34 | G2 stale fact | pull path resolves the session id since 2026-09-05 | high | rewrite |
| commands-07 | wrap.md:80 | G2 stale fact | same | high | rewrite |
| commands-21 | wrap.md:83 | G2 stale fact | "unlike 👤" | high | rewrite |
| commands-22 | wrap.md:133 | G2 stale fact | "Unlike 👤" | high | rewrite |
| commands-08 | wrap.md:139-144 | G2 stale fact | ⛔ is computed from class-C packets, which contradicts "CANNOT derive" and L56 of the same file | high | rewrite |
| commands-11 | recover.md:189-195 | G2 stale fact / migration-relative | "until it is live" — ~/.claude/commands/recover.md has been symlinked since 2026-09-11 | high | rewrite |
| commands-09 | wrap.md:40-46 | G2 contradiction | "top of your close" vs L171 and the global S1. A "fenced" command vs the global inline-code rule (global is newer) | medium | rewrite |
| commands-10 | recover.md:147-161 | 1d patch accretion | "SELF-only… unbuildable today" followed by "Superseded 2026-09-23". Two paragraphs say opposite things; bin/cc-lr:160 confirms --pane/--sid/--from | medium | merge into one current paragraph |
| commands-12 | commit.md:33-36 | G2 conflict with global | auto-autosquash after every fixup (2026-03) vs global "squash when the user asks" (2026-09). Tightening, so the edit is safe | medium | rewrite |
| commands-13 | commit.md:41 | 1d update suppressor + intra-file conflict | "DO NOT read files…" vs L9 "Read it" and Read in allowed-tools. The narration ban under-narrates on Opus 5.5 | medium | rewrite |
| commands-14 | fix-lint.md:8 | G2 conflict with global | hardcoded bun/npm vs the global "package manager its lockfile names". Omits pnpm, the house default | medium | rewrite |
| commands-15 | deploy-check.md:7 | G2 conflict with global | same | medium | rewrite |
| commands-16 | accounts.md:88-90 | 1c repetition as reinforcement | repeats step 2's "never re-derive from score_*; --rank round-robin" word for word | medium | trim to a back-reference |
| commands-17 | research.md:87 | G2 history narrative | correction archaeology. Keeps the two live facts and the key-not-model reason | medium | rewrite |
| commands-18 | limit-recover.md:524 | G2 pinned model name | "Fable 5" where the tier is Fable 5.1. The point is model-independent | medium | rewrite |
| commands-19 | accounts.md:40-45 | G2 history narrative | "Why it moved into code (2026-07-30)" is archaeology. The directives are preserved in bin/claude-accounts comments (e.g. :6954, :7068). The rule table is kept | low | rewrite (proposed only) |
| commands-20 | research.md:66-70 | G2 conflict (flag) | the manifest asks for "~$X-Y cost band… Reply 'abort' within 15s". skills/research-subagents/SKILL.md:480 says not to put a quota/$ number in the manifest (decided 2026-07-01), but its own :843 says the manifest names $$. accounts.json says there is no $ exposure. A model cannot wait 15s (the Bash tool refuses sleep) | low | flag — operator decides; proposal aligns with SKILL:480 |

## Checked and clean
- No `budget_tokens`, thinking-disabled, prefill, temperature, tool_choice or "think step by step" in any command.
- `--bare`, `--json-schema`, `--max-budget-usd` and `--effort` all exist on 2.1.284.
- All 91 repo paths the commands cite exist, except placeholders (docs/plans/WSFA.md is an example) and ~/.claude/bin shims outside the repo.
- These are fragile-op scripts and stay (keep-list 3): ship.md, relogin.md, cc-relogin exit tables, keep-laptop-alive.md (operator rulings), are-we-done.md (operator-saved format, hook-enforced close shape), desk.md, copy-plan.md, read-twitter.md, research-program.md, pr.md (hook-enforced).
- compact-memory.md: its NEVER lines guard against data loss on memory files, so they stay.
- handoff.md's 23 caps markers are mechanical contracts (locks, setsid, disposition); none is plain style pressure.
- The routing table in handoff.md:402-420 matches the SSOT and the global instructions.

## Not covered
- A line-by-line read of the bodies of handoff.md, limit-recover.md and compact-memory.md. A follow-up shard should take each one alone.
- Behavioral probes (Step 7). All findings are repo-fact checks, verified against scripts and SSOT files.
