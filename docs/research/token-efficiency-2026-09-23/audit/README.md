# Always-loaded instruction audit (2026-09-23)

This audit covers every instruction file that Claude Code loads into every context: the global `CLAUDE.md` (source `CLAUDE.global.md`), the two files in `~/.claude/rules/`, and, for sessions in this repo, `.claude/CLAUDE.md` and `.claude/rules/agent-operating-lessons.md`. For each file it produces a slim variant, a label for every line, and an adversarial check that no operative rule was lost. Spec: `../SPEC.md` § 2.

Measured result: the always-loaded set drops from 48,232 to 19,507 tokens in every context (−59.6%), and from 78,462 to 23,560 tokens in sessions in this repo (−70.0%). Nothing was applied to a live file. The slim global file ships behind the per-account A/B flag. The rules-directory, board and project-file changes need the switches described in `C6.labels.md`, `C6.mission-board.md` and `C7.labels.md`.

## File map

| File | What it is |
|---|---|
| `CLAUDE.global.slim.md` | Slim global instructions: two-line header, then C1-C5 and C6 part 1 concatenated, after the cross-chunk coherence pass. This is the A/B candidate for `~/.claude/CLAUDE.md`. |
| `SYSTEM_PROMPT_DIFF.md` | The line-level diff: every label row from every chunk, grouped by source file, with per-chunk and per-section totals, the assembly-stage edits, the C6 parts, the C7 resident/index/delete split, and a what-moved-where index. |
| `C1.slim.md` … `C5.slim.md`, `C6.slim.md` | Per-chunk slim texts for `CLAUDE.global.md` lines 1-159, 160-331, 332-451, 452-805, 806-1061 and 1062-1077, after each chunk's fix pass. They are not changed by assembly. |
| `C1.labels.md` … `C7.labels.md` | Per-chunk label tables (KEEP / REWRITE / DELETE / MOVE; RESIDENT / INDEX for C7), with reason code, enforcing hook and destination, plus notes for the integrator. |
| `C1.verify.md` … `C7.verify.md` | Adversarial checks: each operative rule in the original checked against the slim text, then the violations and the fixes applied. |
| `C6.rules-essay.md` | C6 part 2: `~/.claude/rules/agent-operating-lessons.md`. Verdict (remove from the rules directory, no replacement), labels, the required `hooks/memory-nudge.sh` fix, and the file verbatim. |
| `C6.staged/docs/lessons/user-rules-dir-loads-in-every-invocation-mode.md` | Ready-to-copy destination for the rules essay. |
| `C6.mission-board.md` | C6 part 3: compact render for `~/.claude/rules/00-mission-board.md`, including the unified diff against `bin/cc-mission`, the new bats test, samples, and the rollout plan. |
| `C6.project-claudemd.slim.md` | C6 part 4: slim `.claude/CLAUDE.md`. |
| `C7.slim.md` | Slim `.claude/rules/agent-operating-lessons.md`: 19 resident lessons and the pointer to the index. It passes `scripts/rules-hook-budget-lint.sh`. |
| `C7.index.md` | Content for the proposed `docs/lessons/INDEX.md`: 185 lesson lines by topic, plus the ceilings note. |

## Token table

Method: each text was written as `CLAUDE.md` into a scratch directory `/tmp/tokeff-tok-<name>/`, then `cd <dir> && /Users/chrisren/.claude-280/node_modules/.bin/claude -p "/context"` was run (Claude Code 2.1.280, claude-opus-5-5, free count_tokens path), and the Project memory-file row was read.

That row rounds to 0.1k above 1,000 tokens. To get exact figures, each text over 1k was also split into parts of at most 2,400 bytes (1,300 for the two largest), with splits placed outside HTML comments and code fences. The parts were imported with `@pNN.md` from `/tmp/tokeff-tok-<name>-split/CLAUDE.md`, where each import gets its own exact row, and a one-character `p00.md` gave the per-row overhead (9 tokens, the same as the 2-byte control).

Derived count = Σ parts − N × 8, + (N − 1) for the one token each split boundary loses, + 8 for the single file's framing. Every derived figure falls inside the displayed row's rounding band, so treat each as exact to within a few tokens.

| Text | Bytes | `/context` row | Derived exact | Change |
|---|---|---|---|---|
| Full `CLAUDE.global.md` | 106,863 | 40.4k | 40,374 | |
| `CLAUDE.global.slim.md` | 50,867 | 18.5k | 18,546 | −21,828 (−54.1%) |
| Full `.claude/rules/agent-operating-lessons.md` | 74,780 | 27.9k | 27,857 | |
| `C7.slim.md` | 7,567 | 2.9k | 2,885 | −24,972 (−89.6%) |
| Full `~/.claude/rules/00-mission-board.md` (today's rows) | 13,998 | 5.5k | 5,456 | |
| Compact mission-board sample (fallback render, `C6.mission-board.md` § A) | 2,418 | 961 | 961 | −4,495 (−82.4%) |
| Full rules essay `~/.claude/rules/agent-operating-lessons.md` | 6,334 | 2.4k | 2,402 | |
| Its replacement (none; the file leaves the directory) | 0 | no row | 0 | −2,402 (−100%) |
| Full `.claude/CLAUDE.md` | 6,289 | 2.4k | 2,373 | |
| `C6.project-claudemd.slim.md` | 3,036 | 1.2k | 1,168 | −1,205 (−50.8%) |
| Control (`x`) | 2 | 9 | 9 | per-file overhead |

| Scope | Full | Slim | Change |
|---|---|---|---|
| Every context, every account (global + board + rules essay) | 48,232 | 19,507 | −28,725 (−59.6%) |
| Added in this repo (`.claude/rules` + `.claude/CLAUDE.md`) | 30,230 | 4,053 | −26,177 (−86.6%) |
| Sessions in this repo, total | 78,462 | 23,560 | −54,902 (−70.0%) |

Notes:
- The loader strips HTML comments (C6 finding 1). The `tone_preference` comment kept at the end of `CLAUDE.global.slim.md` therefore costs nothing.
- The task brief estimated `.claude/rules/agent-operating-lessons.md` at about 20k tokens. It measures 27.9k because its many paths and links tokenize at about 2.7 bytes per token.
- The board figure uses today's five rows and grows as rows are appended. The headline variant (§ B) was measured at 805 tokens by C6 before its last sentence was added, and was not re-measured here.
- These are prefix tokens per request. Per-task cost depends on the cache-write and cache-read multipliers and on turns per task, both covered elsewhere in the spec.

## Verify outcomes per chunk

"Rules" is the number of operative rules the checker extracted from the original. "Preserved" counts rules the first slim draft kept intact. Violations are counted before the fix pass.

| Chunk | Source | Rules | Preserved | Violations (major / minor) | Fixed | Rejected | Deferred (needs a write outside `audit/`) |
|---|---|---|---|---|---|---|---|
| C1 | `CLAUDE.global.md` 1-159 | 55 | 48 | 8 (1 / 7) | 8 | 0 | Registering `mail-images-auto.sh` in the account config dirs (it is only in `~/.claude/settings.json`) |
| C2 | 160-331 | 32 | 24 | 8 (1 / 7) | 7 | 0 | R12: `commands/handoff.md` :283/:307 and `skills/plan-conventions/SKILL.md` :98-99 still say a recycle must re-arm the goal |
| C3 | 332-451 | 59 | 49 | 10 (1 / 9) | 10 | 0 | — |
| C4 | 452-805 | 96 | 75 | 8 (1 / 7) | 7 | 1 (`CC_MECH_MAX` is already in C5) | — |
| C5 | 806-1061 | 63 | 56 | 7 (1 / 6) | 7 | 0 | — |
| C6 | global 1062-1077, rules essay, mission board, `.claude/CLAUDE.md` | 64 | 38 | 12 (1 / 11) | 12 (4 of them as ready changes) | 0 | `hooks/memory-nudge.sh` hint; copying the lesson doc into `docs/lessons/`; setting row headlines; the part 2 and part 4 switches |
| C7 | `.claude/rules/agent-operating-lessons.md` | 215 | 196 | 12 (4 / 8) | 12 in text | 0 | Add `docs/lessons/INDEX.md` to the E3 list in `commands/compact-memory.md` (without it, 47 memory topic files become orphans); retarget `memory-nudge.sh`, `memory-index-budget.sh`, `cc-memory-rotate`, `memory-index-drain.sh` and `promote-memory.sh` at the index; ship `docs/lessons/INDEX.md` in the same commit |

The major violations, one line each, fixed in text unless noted:
- C1: the email-images rule assumed a hook that four of the five config dirs lack. It now works whether or not the hook fired.
- C2: the brief carve-out on the parallelize precedence rule was invented and has been removed.
- C3: the operator-only status of migration 0029 was lost and has been restored.
- C4: "below 90%" let an agent at exactly 90% skip the research. It now reads "at or below".
- C5: the instruction to file a held decision immediately had become a description. It is an instruction again.
- C6: the live-copy sync rule for `.claude/CLAUDE.md` had been narrowed. It is restored with every copy class.
- C7: the slim header contradicted the tools that route lessons into this file (the tools still need changing). 47 memory topic files would be orphaned, which is deferred. The index pointer was too narrow and has been widened. The standing operator ruling on kitty title bars was dropped and is now resident.

## Cross-chunk coherence pass (assembly)

These 15 edits were made to `CLAUDE.global.slim.md` after concatenation. Each is listed with its label and reason in `SYSTEM_PROMPT_DIFF.md` § Assembly-stage edits.
- Duplicates reduced to one statement: when to run or offer `/ship` (Git Safety now points to Ship policy); the two force-push sentences; the class-C ⛔ trigger (now only in the six-slots decision paragraph); the conviction-refusal and `UNCONVICTED_MINE` sentence (now only in Follow-On Gate F2); the two `Good to close:` forms (now only in Origin close contract); the ship repeat in `→ Next`.
- Contradictions fixed: the ship-policy sentence "a project CLAUDE.md loads only when the session cwd is that project" was inaccurate and duplicated Working rules, so it was removed. Communication Discipline's "below 90%" is now "at or below 90%", matching F2. Context Stewardship said "`/handoff`" where Session Close says to try recycle first; it now says "recycle or hand off" and points to the context table.
- Pointers fixed: `commands/handoff.md` § Waves / item 1 are now `~/.claude/commands/handoff.md` § Autonomous fire, items 6 and 1, because there is no Waves heading and a relative path does not resolve from other repos. "Context dispositions below" now names its table. Every other section, skill, hook, script, bin and migration named in the file was checked on disk and exists. `mailbox-drain` and `mailbox-wake-arm` are hooks, not bins.
- Emphasis removed: `INTEGRATE-never-overwrite`, `STOP-ASK` (twice) and `<the ONE next step>`. What remains in capitals is terms and strings that tools match or render (`PASS`/`FAIL`/`FILED`, slot names, `SAFE TO CLOSE`, `OPERATOR ▸`, `OVERWRITE GUARD`, `SELECT`, `CONFIRM`) and one quoted example (`UNVERIFIED`). No emoji alarm markers remain. The rung glyphs stay because the hooks match them.
- Kept on purpose: the `tone_preference` block restates chat brevity at the end of the prompt, as the original intends. C1's "read a non-cwd repo's CLAUDE.md" stays as the single general statement.

Issues that no text edit can fix, for whoever integrates:
- `hooks/agent-teams-enforce.sh` still tells the model to use `TeamCreate … team_name` in its deny message, which disagrees with the slim `Agent({ name, … })` wording (C2).
- `completion-assert.sh` (`ca_last_user_msg`) and `session-continue.sh` treat fire/recycle briefs as legitimate kill-switch disarms, while the slim text (like the original) says a machine-authored brief is not the operator's instruction (C5).
- `CC_LADDER=off` has no reader in code (C3).
- `tests/deploy-parity.bats:1831` extracts skill claims only from the bold `**name** skill` spelling, so it would find none if pointed at the slim file (C2).
- The C7 lesson "never leave a brief on a shared /tmp path" conflicts with `commands/handoff.md` :172 and :515, which write briefs to `/tmp/fire-<slug>.txt`.
- The stale `validate-bash.sh:1352` citation remains in `scripts/deploy-live.sh:14` (C6).
- A/B watch item: the slim file keeps "commit as you go without being asked", which contradicts the Bash tool's built-in "commit only when the user asks" (C1).
- Only the global file can use the per-account flag. The rules directory and the mission board apply fleet-wide, and the project files load by repo path, so C6 parts 2-4 and C7 need a time-window or before/after comparison (C6, C7).
