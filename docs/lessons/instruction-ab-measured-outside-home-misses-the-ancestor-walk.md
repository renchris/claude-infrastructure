# An instruction A/B measured outside $HOME misses the ancestor walk

2026-10-03 (plan `docs/plans/INSTRUCTION_BUDGET.md`, research `docs/research/instruction-budget-2026-10-03/`).

**Rule.** Measure any change to what Claude Code loads as instructions in the composition production
actually gets: a cwd under `$HOME`, a real account config dir, no `claudeMdExcludes` the fleet does not
ship. And re-point an account's `CLAUDE.md` only at the canonical `~/.claude/CLAUDE.md`, never at a sibling file.

**What happened.** Migration 0042 (slim-instructions A/B, gate passed: −34% cost per task) re-pointed each
account's `CLAUDE.md` symlink from `~/.claude/CLAUDE.md` to `~/.claude/CLAUDE.slim.md`. Claude Code walks
from the cwd up to `/` and loads every `.claude/CLAUDE.md` and `.claude/rules/*.md` it meets as Project
memory, and every cwd on this machine sits under `/Users/chrisren`, so the walk reaches
`~/.claude/CLAUDE.md`. Before 0042 that copy was free: the loader records a symlink's resolved target
in `processedPaths`, and the account link resolved to the same file. After 0042 it resolved elsewhere,
so every session loaded slim (57k) **plus** full (113k) plus both rules dirs: 181k chars against the
121k it replaced. That is +50%, the reverse of the certified saving, and it ran for 8 days. A reso
session showed it as `9 instruction files add up to 428.1k chars, over the 150.0k-char total limit`.

**Why the gate could not see it.** The eval harness ran every arm from a fixture under `/tmp`, outside
`$HOME`, and set `claudeMdExcludes` on `~/.claude/CLAUDE.md` and its rules (run.sh:11,62-64). Both
arms therefore contained only their own frozen files. The measurement was correct about the arms and
silent about production, because the variable that mattered (where the cwd sits) was held at a value
production never takes. The migration's verify line checked symlink targets, not what loads.

**Measured fix.** A `claudeMdExcludes` entry for the ancestor copy works for account sessions but is
type-blind: it also removes the user memory of a default-config-dir session (measured: zero memory
files load). A symlinked `~/.claude/CLAUDE.md` still double-loads on 2.1.114. What works on 2.1.114,
2.1.278 and 2.1.284: `~/.claude/CLAUDE.md` is a regular file holding the selected variant and every
account link points back at it (migration 0053). `cc-instructions-variant set <acct>` now refuses a
divergent target, and `cc-instruction-budget assert` fails on any instruction file loaded twice.

**How to check.** `claude -p /context` from a cwd under `$HOME` (auth-free, works with a scratch
`CLAUDE_CONFIG_DIR`) lists every memory row with its type; a Project row under `~/.claude/` is the
regression. `cc-instruction-budget census` shows the same per repo, marked `DUP`.
