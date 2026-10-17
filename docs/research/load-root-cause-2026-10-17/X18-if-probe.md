# X18 — hook `if` filter probe (2026-10-17)

**Status:** the agent-side probe was refused; the probe now runs inside the migration, at operator apply time.

## What the filters rely on

From the vendor's hook docs (code.claude.com/docs/en/hooks):

- `if` takes permission-rule syntax (`Bash(<glob>)`). When a call does not match, Claude Code skips the hook process entirely.
- "When Claude Code can't determine which commands the Bash input runs, it runs your hook regardless." So a compound, `bash -c` or otherwise opaque command over-fires. That is today's behavior, so it is the safe direction.
- `if` has existed since 2.1.85, which predates every binary in the fleet, 2.1.114 included.
- The docs call `if` best-effort and advise against it on hard denies. The migration therefore filters only pr-gate.sh and relay-verbatim.sh, which are advisory, and never a deny guard.

## Why the agent could not probe it

On 2026-10-17, auto mode refused the W4 teammate's headless `claude -p` run against a scratch settings file and classed it as "Security Weaken". The likely reason is that the scratch run leaves out the user-level guard hooks. That refusal stands for agent sessions. The run was not retried or respelled.

## Where the matrix comes from instead

`migrations/0066-hook-if-filters.sh --probe` runs the fleet binary (`cc-claude-bin`) headless in a fresh `mktemp -d` dir:

- **Hooks loaded:** only a probe settings file. It holds one logging hook per `if` pattern, one logging hook with no `if`, and one hook that denies every Bash call, so no probed command ever executes.
- **Output:** a matrix of spelling against the hooks that fired.
- **Pass condition:**
  - each filter fires on its spellings (`gh pr create`, `cd /tmp && gh pr create`, `bash -c 'gh pr edit 1'`, `/opt/homebrew/bin/gh pr create`, `gh pr edit`, and the path-prefixed relay renderers);
  - no filter fires on `ls`;
  - the hook with no `if` saw every command. A command the model never ran counts as unknown, which fails closed.

`--confirm settings.json` runs the probe first and writes nothing unless it passes, so the operator's apply both measures this machine's binary and acts on the result. `--dry-run` and `--check` never start it. The decision logic is unit-tested against a stub claude in `tests/migration-0066-hook-if-filters.bats`. No test starts a real one.

**Not covered:** the probe exercises `if` on PreToolUse only, because the deny hook has to stop the commands before they run. relay-verbatim.sh is a PostToolUse hook, and the docs describe `if` as the same tool-input match on both events. If that ever differs, a PostToolUse filter could miss a renderer; nothing would be blocked, but the relay reminder would not appear.
