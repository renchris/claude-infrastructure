# Axes B, D, E, F — run on the lead (5 of 7 subagent spawns were refused at the capacity gate)

## B — the chokepoint. The tracked launcher does NOT compose argv.
- `lib/claude-launcher.zsh` (tracked, 300 ln) is only a ROUTER: `_cc_install_router` copies the
  existing `claude()` into `_claude_pinned` and redefines `claude()` to pick a config dir. It
  composes no binary argv at all.
- The REAL launcher body is `~/.zshrc:451` — **untracked, unreviewed, outside the deploy layer**.
  It ends at `~/.zshrc:500`:
  `"$HOME/.claude/bin/cc-close-attrib" "$_bin" --permission-mode … --model … --effort … "$@"`
- ⇒ **`bin/cc-close-attrib` is the real chokepoint and it IS tracked** (383 ln; `exec "$REAL_BIN" "$@"`
  at :316). Every interactive launcher (`claude`, `claude1..4`) and every `handoff-fire.sh` fire
  (which TYPES `claudeN …` into an interactive shell) passes through it.
- Paths that BYPASS it: `hooks/session-start.sh:270` (the MCP probe) and
  `lib/cc-upgrade-gate/check13_mcp.sh:14` both invoke the binary directly. `bin/cc-offload` uses
  `~/.claude-220/…/claude` for cloud creates.
- ⚠️ Argv is a SENSED surface: `bin/cc-ignition-gate:142` matches on
  `^([^[:space:]]*/)?(claude|claude-latest|claude-next[0-9]*|claude-fable[0-9]*)([[:space:]]|$)`
  and `bin/cc-reaper:2836` has a control asserting the `cc-close-attrib <bin>` wrapper shape is
  REJECTED as a lead cell. Injecting a flag is argv-visible; any injection must be re-checked
  against both.

## D — divergence #1 is worse than filed: THREE endpoints, not two.
| where | ms365 definition |
|---|---|
| `~/.claude.json` | `npx -y @softeria/ms-365-mcp-server@latest`, env `MS365_MCP_TENANT_ID=consumers` |
| the five config dirs | `…/fnm/aliases/default/bin/ms-365-mcp-server`, args `[]`, env **`{}`** |
| `~/Development/personal/.mcp.json` | `npx -y @softeria/ms-365-mcp-server` (**no `@latest`**), env tenant=consumers |
The env difference is functional, not cosmetic: the five dirs carry NO `MS365_MCP_TENANT_ID`.
Per the axis-A precedence measurement, inside `~/Development/personal` the project's npx form WINS
over the config dir's fnm binary — which is precisely the `[Conflicting scopes]` warning the plan
quotes. `mac-messages` survives only in that one project file (absent from all six user-scope copies),
so the plan's 2026-08-22 note ("removed everywhere, not unified") is still accurate.

## E — the migration surface is clean, and the mutation mechanism ALREADY EXISTS.
- **No hidden survivors.** Recursive key search over all six files: `mcpServers` occurs at 49–120
  paths per file, but every nested `projects.<path>.mcpServers` is an EMPTY dict. Exactly ONE
  non-empty top-level `.mcpServers` per file. A strip/render at the top level misses nothing.
- **`scripts/ms365-mcp-wire.sh` (170 ln, tracked, wired into `install.sh:610-630`) is already the
  SSOT-render mechanism**, hardcoded to one server. It enumerates dirs from tracked `accounts.json`,
  MERGES exactly one key under `.mcpServers`, writes via temp + `mv` in the same dir (atomic, never
  truncates a file a live session is reading), is idempotent and `--check`-able. Its header already
  argues why config-mirror CANNOT carry this: `.claude.json` is in `_CC_ISOLATE` because it races
  between concurrent processes.
- 🚨 **Its population is wrong, and that is the direct cause of divergence #1.** The loop is
  `accounts.json` config_dirs + `~/.claude`, on the comment *"plus ~/.claude itself (the default dir
  a bare `claude` uses when CLAUDE_CONFIG_DIR is unset)"*. **Measured false** (see the axis-A
  harness): with `CLAUDE_CONFIG_DIR` unset, 2.1.260 reads **`$HOME/.claude.json`**, NOT
  `$HOME/.claude/.claude.json`. So the file the comment is aiming at is never in the loop, and
  `./scripts/ms365-mcp-wire.sh --check` today prints **5/5 `✓ already correct`** while the sixth file
  — the one it believes it is covering — carries the divergent `@latest` npx form.
  A green checker over a population that excludes the defect.

## F — a tracked SSOT needs no new deploy machinery; the precedent is already load-bearing.
- `accounts.json` is TRACKED at repo root and reaches the live layer as a per-file symlink
  (`~/.claude/accounts.json -> …/claude-infrastructure/accounts.json`). `scripts/` is symlinked the
  same way (`~/.claude/scripts/ms365-mcp-wire.sh -> …`). So a tracked `mcp-servers.json` at repo root
  is read by both the installer (`$REPO_DIR/…`) and the standalone script
  (`$(dirname "${BASH_SOURCE[0]}")/../…`) with **zero new top-level** — no `LIVE_ADDS` converge risk,
  which is the failure mode a brand-new deployed directory would carry.
- **Secrets:** no live MCP definition on this machine carries a secret in `env` today (motion/
  motion-plus are bare http URLs; ms365 env is `{}` or a tenant id). And axis A measured that
  `${VAR}` in a server `command` IS expanded, so a future secret can be held by env indirection
  without committing it. A tracked SSOT is safe on this axis.
