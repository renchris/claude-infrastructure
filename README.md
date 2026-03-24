# Claude Code Infrastructure

Custom infrastructure for [Claude Code](https://claude.ai/code) — 3,300+ lines across 29 scripts providing versioned updates, file protection, session persistence, and autonomous agent support.

Built and battle-tested across 1,348+ sessions from January–March 2026.

## Architecture Overview

```
~/.claude/                            # Config directory (NOT a git repo)
├── settings.json                     # Global settings (permissions, hooks, env)
├── .mcp.json                         # MCP server configuration (BrowserMCP)
├── CLAUDE.md                         # Global instructions for all projects
├── hooks/ (19 scripts)               # Lifecycle hooks
├── scripts/ (3 scripts)              # Backup/restore utilities
├── bin/it2                           # iTerm2 teammate profile wrapper
├── backups/                          # Auto-backups (10/file, 30-day TTL)
├── logs/                             # Audit logs
├── plans/ + plans-index.json         # Plan files + project mapping
├── plan-history/                     # Plan version control (separate git repo)
├── plan-versions/MANIFEST.jsonl      # Plan metadata log
├── tasks/ + tasks-index.json         # Task lists + project mapping
├── session-index.db                  # Session search (SQLite FTS5)
├── statusline.sh                     # Context % + branch display
└── projects/                         # Per-project memory + transcripts

~/.claude-versions/                   # Versioned Claude installations
├── 2.1.7/ ... 2.1.81/               # Isolated npm installs (~80 MB each)
└── current -> 2.1.81                 # Atomic symlink to active version

~/bin/                                # CLI tools
├── claude-latest                     # Auto-update wrapper (entrypoint)
├── claude-update                     # Manual version management
├── claude-versions                   # Version listing
└── browsermcp-wrapper.sh             # NVM-aware MCP bridge

~/Library/LaunchAgents/               # Background daemons
├── com.claude.session-search-sweep   # Session indexing (every 60s)
└── com.claude.session-search-backfill # Weekly full backfill (Sunday 3am)
```

## Versioned Update System

**Problem**: npm overwrites Claude's binary in-place during updates, causing `ENOTEMPTY` errors when sessions hold file handles.

**Solution**: Homebrew-style parallel installations — each version lives in its own directory, a symlink points to the active one, and old sessions keep their loaded binaries untouched.

### How It Works

```
~/.claude-versions/
├── 2.1.79/           # Old version (still works for any running session)
├── 2.1.81/           # Current version
└── current -> 2.1.81 # Atomic symlink (ln -sfn)
```

The `claude` shell function calls `claude-latest` instead of the binary directly:

```bash
# ~/.zshrc
claude() {
    CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")" claude-latest "$@"
}
```

`claude-latest` (see [`bin/claude-latest`](bin/claude-latest)):
1. Checks npm for the latest version (10-minute cache to avoid excessive lookups)
2. Installs new versions to their own directory (`npm install --prefix`)
3. Updates the `current` symlink atomically (`ln -sfn` is atomic on macOS)
4. Sets `DISABLE_AUTOUPDATER=1` to prevent Claude's built-in updater from conflicting
5. Execs the binary from the `current` symlink

**Result**: Updates happen transparently between commands. Old sessions are never disrupted. 44 versions installed over 2+ months with zero conflicts.

### Version Management Commands

| Command | Purpose |
|---------|---------|
| `claude` | Auto-updates + launches (via `claude-latest`) |
| `claude-update` | Install latest or specific version |
| `claude-update 2.1.75` | Pin to a specific version |
| `claude-update --cleanup` | Remove old versions (keep current + 1 previous) |
| `claude-versions` | Show all installed versions with disk usage |
| `CLAUDE_SKIP_UPDATE=1 claude` | Skip update check for this invocation |

### Shell Aliases

```bash
claude()      # Main entrypoint — auto-update + task list persistence
claude-plan   # Plan mode with "ultrathink" system prompt
claude2       # Second isolated instance (CLAUDE_CONFIG_DIR=~/.claude-secondary)
claude-which  # Show active config directory
claude-sync-mcp  # Sync MCP config to secondary instance
```

## Hook System

22 hooks across 8 lifecycle events. All hooks are non-blocking (`exit 0`) — failures never prevent tool execution.

### Execution Flow

```
SessionStart
├── session-start.sh          MCP status check, daily backup prune, agent-browser detect
├── setup-plan-symlinks.sh    Create .claude-plans/ with project-filtered symlinks
├── setup-task-symlinks.sh    Create .claude-tasks/, detect active UUID list, generate TASKS.md
└── session-index-start.sh    Crash-safe stub row + inject recent session context

PreToolUse (before each tool call)
├── validate-bash.sh          Block rm -rf /, sudo rm, chmod 777, fork bombs; audit log
└── backup-before-write.sh    Auto-backup before Write/Edit, OVERWRITE GUARD, plan rule injection

PostToolUse (after each tool call)
├── post-file-edit.sh         Auto-format (ESLint for TS/JS, ruff for Python)
├── plan-index-update.sh      Update plans-index.json project mapping
├── validate-plan-structure.sh  Warn if multi-section plan lacks Phase 0
├── plan-version-commit.sh    Auto-commit plans to ~/.claude/plan-history/ git repo
├── log-bash.sh               Audit bash command + exit code
└── task-mutation-index.sh    Regenerate _summary.json + TASKS.md on TaskCreate/TaskUpdate

TaskCompleted
└── task-completed-index.sh   Update summary, TASKS.md, tasks-index.json

TeammateIdle
└── teammate-auto-shutdown.sh  Exit code 2 forces immediate shutdown (no orphan panes)

SessionEnd
├── session-end.sh            Log timestamp
└── session-index-end.sh      Rich session indexing (context, files, commands, keywords)

Notification
└── notify.sh                 Audio + desktop notifications (permission, question, plan, complete)

PreCompact
└── (inline)                  Log auto/manual compact events
```

### Hook Details

| Hook | Lines | Trigger | Key Feature |
|------|-------|---------|-------------|
| `backup-before-write.sh` | 115 | Write/Edit/MultiEdit | Nanosecond timestamps, symlink-aware, auto-prune to 10/file |
| `setup-task-symlinks.sh` | 135 | SessionStart | UUID auto-detection, TASKS.md generation, stale symlink pruning |
| `session-start.sh` | 80 | SessionStart | MCP exponential backoff (3 attempts), agent-browser detect |
| `plan-version-commit.sh` | 82 | Write/Edit on plans | Dual-layer: MANIFEST.jsonl + git repo snapshots |
| `notify.sh` | 77 | Permission/question/plan/complete | 6 sound mappings, 2s debounce, desktop notification for high-priority |
| `task-completed-index.sh` | 75 | TaskCompleted | Summary regeneration, tasks-index.json update |
| `validate-plan-structure.sh` | 46 | Edit on plans | Phase 0 guard (warn-only, non-blocking) |
| `teammate-auto-shutdown.sh` | 26 | TeammateIdle | Exit code 2 = force shutdown. Zero orphan panes. |
| `validate-bash.sh` | 26 | Bash commands | Pattern-block dangerous commands + audit log |

## Backup & Recovery System

Every `Write` and `Edit` tool call automatically creates a timestamped backup before modifying the file.

### Components

| File | Purpose |
|------|---------|
| [`hooks/backup-before-write.sh`](hooks/backup-before-write.sh) | PreToolUse hook — creates backup + injects OVERWRITE GUARD |
| [`scripts/restore-file.sh`](scripts/restore-file.sh) | Restore from backup (latest, --list, --diff, --pick N, --recent) |
| [`scripts/prune-backups.sh`](scripts/prune-backups.sh) | Daily cleanup (10/file cap, 30-day TTL, orphan .path cleanup) |
| [`scripts/test-overwrite-guard.sh`](scripts/test-overwrite-guard.sh) | 26-scenario test harness |

### Usage

```bash
restore-file /path/to/file           # Restore latest backup
restore-file /path/to/file --list    # List all backups with timestamps
restore-file /path/to/file --diff    # Unified diff vs latest backup
restore-file /path/to/file --pick 3  # Restore 3rd most recent
restore-file --recent 10             # Show 10 most recent across all files
```

### Design Decisions

- **Nanosecond timestamps + PID** for uniqueness (safe for parallel agent teams)
- **Sidecar `.path` files** resolve basename collisions (multiple files with same name)
- **Atomic restore** via `mktemp` + `mv` (no corruption on interrupt)
- **Symlink-following** (`cp -L`) preserves real content, not symlink paths
- **Graceful failure** — backup errors warn but never block the Write

## Plan Versioning

Every edit to a plan file is automatically tracked in two layers:

1. **MANIFEST.jsonl** (`~/.claude/plan-versions/`) — append-only metadata (timestamp, session, SHA256, line count)
2. **Git repo** (`~/.claude/plan-history/`) — full plan snapshots with auto-commits

Browse history: `cd ~/.claude/plan-history && git log --oneline`

Plan files are indexed by project (`~/.claude/plans-index.json`) and symlinked into each project as `.claude-plans/`.

### Plan Convention Enforcement

The `backup-before-write.sh` hook injects rules into the model context when editing plan files:
- **Completed sections**: Compact to key learnings, commit hashes, blockers only
- **Upcoming sections**: Comprehensive detail (file paths, decision context, trade-offs)
- **Phase 0 mandatory**: First section must be Agent Team Orchestration
- **Never delete**: Historical decisions, rationale, learnings

## Task Persistence

Claude Code generates UUID-based task list directories and ignores `CLAUDE_CODE_TASK_LIST_ID`. The task persistence system works around this:

1. `setup-task-symlinks.sh` (SessionStart) auto-detects the active UUID list
2. Creates `.claude-tasks/_current/` symlink to the active list
3. Generates human-readable `TASKS.md` from task JSON
4. Tracks via `.active-list-id` file for inter-hook coordination

The shell function sets `CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")"` for project-scoped lists.

Resume tasks across sessions: `/resume-tasks [optional context]`

## Session Search

Full-text search across all Claude Code sessions via SQLite FTS5.

**Repo**: [claude-session-search](https://github.com/renchris/claude-session-search) (standalone)

```bash
claude-search "replicache mutation"        # Full-text search
claude-search --fzf                        # Interactive picker
claude-search --stats                      # Database statistics
```

**Architecture**:
- `session-index-start.sh` creates crash-safe stub on SessionStart
- `session-index-end.sh` extracts rich metadata on SessionEnd (5 user messages, files, commands, keywords)
- `session-index-sweep.sh` catches missed sessions (60s daemon via LaunchAgent)
- Source priority: `sessions-index.json (100)` > `session-end (50)` > `sweep (25)` > `stub (0)`

## Status Line

[`statusline.sh`](statusline.sh) displays `dir (commit) branch* · N%` in the Claude Code prompt.

Context % applies a 48% offset to the INPUT-only token percentage to approximate effective remaining (accounts for output buffer ~32%, auto-compact buffer ~6.5%, warning threshold ~10%).

Color thresholds: <60% gray, 60-90% default, >90% red.

## Audio Notifications

[`hooks/notify.sh`](hooks/notify.sh) plays system sounds and shows desktop notifications:

| Event | Sound | Desktop Alert |
|-------|-------|---------------|
| Permission required | Funk | Yes |
| Question from Claude | Blow | Yes |
| MCP input needed | BubbleAppear | Yes |
| Plan ready for review | Glass | Yes |
| Task complete | Purr | No |
| Authentication | Pop | No |

2-second debounce prevents duplicate notifications. All sounds are background (`disown`).

## Agent Team Support

### Teammate Auto-Shutdown

The `TeammateIdle` hook (`teammate-auto-shutdown.sh`) exits with code 2 on first idle, forcing immediate teammate shutdown. This prevents orphaned tmux panes.

### iTerm2 Integration

`bin/it2-wrapper` injects `--profile Claude-Teammate` on `session split`, suppressing "prompt before closing" dialogs for teammate panes.

Settings: `teammateMode: "tmux"` in `settings.json` enables iTerm2 native panes.

### Custom Agents

| Agent | Model | Isolation | Purpose |
|-------|-------|-----------|---------|
| `schema-migration` | Opus | Worktree | Drizzle schema changes with atomic commits |
| `visual-design-iterator` | Opus | — | V2 pairwise comparison + 24-rule design constitution |
| `north-star-design-agent` | Opus | — | Autonomous 10-principle design iteration |
| `fresh-eyes-evaluator` | Opus | Read-only | Zero-context independent design evaluation |

### Custom Commands

| Command | Purpose |
|---------|---------|
| `/commit` | Atomic task-specific commits with fixup/autosquash |
| `/deploy-status` | Multi-platform health check (Amplify + Fly.io + GitHub Actions) |
| `/amplify-build` | Poll AWS Amplify build status |
| `/cleanup-team` | Graceful teammate shutdown + worktree cleanup |

## BrowserMCP

[`bin/browsermcp-wrapper.sh`](bin/browsermcp-wrapper.sh) wraps BrowserMCP to fix 71% of MCP connection failures by loading NVM environment consistently. Configured in `~/.claude/.mcp.json`:

```json
{
  "mcpServers": {
    "browsermcp": {
      "command": "/Users/chrisren/bin/browsermcp-wrapper.sh",
      "timeout": 15000
    }
  }
}
```

## Auto Mode

**Status**: Research preview (March 24, 2026). Requires Team plan + Opus 4.6 or Sonnet 4.6.

### Enabling

```bash
# Per-session via CLI flag
claude --permission-mode auto

# Or modify shell function for default auto mode
claude() {
    CLAUDE_CODE_TASK_LIST_ID="$(basename "$(pwd)")" claude-latest --permission-mode auto "$@"
}
```

Note: `--enable-auto-mode` (referenced in docs) does not exist as a flag in v2.1.81. The actual mechanism is `--permission-mode auto`.

### Safety Layers (all preserved in auto mode)

| Layer | Behavior in Auto Mode |
|-------|----------------------|
| `deny` rules (19) | Always enforced — classifier cannot override |
| `ask` rules (45) | LLM classifier decides instead of user prompt |
| PreToolUse hooks | Always fire — hook deny = absolute block |
| PostToolUse hooks | Always fire — logging, plan versioning, task indexing |
| Backup-before-write | Always fires — backups created before every Write/Edit |

### Classifier Configuration

Inspect and customize via:

```bash
claude auto-mode defaults   # Print built-in rules (7 allow, 27 soft_deny)
claude auto-mode config     # Show effective merged configuration
claude auto-mode critique   # Get AI feedback on custom rules
```

Custom rules go in `settings.json` under `autoMode.allow` and `autoMode.soft_deny`. Setting either replaces the entire default list — always start from `claude auto-mode defaults`.

### Known Issues

- `defaultMode: "auto"` in settings.json has a bug (GitHub #33587) — doesn't persist
- Auto mode reduces permission prompt frequency, meaning fewer audio notifications
- Unknown CLI flags are silently ignored — if a future version removes `--permission-mode auto`, sessions start normally in default mode

## Permissions Model

### Three tiers in `settings.json`:

| Tier | Count | Behavior |
|------|-------|----------|
| `allow` | 340+ | Auto-approved (read-only commands, WebFetch domains, Edit/Write, MCP tools) |
| `ask` | 45 | Prompt user (git commit/push, curl, deploy, rm, install/uninstall) |
| `deny` | 19 | Hard block (force push, sudo, eval, exec, git clean, secrets) |

### Key deny rules (always enforced, even in auto mode):

- `Bash(git push --force:*)`, `Bash(git push -f:*)`
- `Bash(sudo:*)`, `Bash(su:*)`, `Bash(eval:*)`, `Bash(exec:*)`
- `Bash(git clean:*)`, `Bash(wget:*)`, `Bash(dd:*)`
- `Read(./.env)`, `Read(./.env.local)`, `Read(./**/*.key)`, `Read(./**/*.pem)`

## LaunchAgent Daemons

| Plist | Schedule | Purpose |
|-------|----------|---------|
| `com.claude.session-search-sweep` | Every 60s | Catch missed session transcripts |
| `com.claude.session-search-backfill` | Sunday 3am | Full backfill of all sessions |

Both are low-priority background processes. Install via `launchctl load ~/Library/LaunchAgents/com.claude.*.plist`.

## Installation

This repo is a reference snapshot — not an installer. To use these scripts:

1. **Update system**: Copy `bin/claude-latest`, `bin/claude-update`, `bin/claude-versions` to `~/bin/` and add the `claude()` function to `~/.zshrc`

2. **Hooks**: Copy `hooks/` to `~/.claude/hooks/` and register in `~/.claude/settings.json` under the `hooks` key

3. **Scripts**: Copy `scripts/` to `~/.claude/scripts/` and symlink `restore-file` to `~/bin/`

4. **LaunchAgents**: Copy `launchd/` plists to `~/Library/LaunchAgents/` and load with `launchctl`

5. **Status line**: Copy `statusline.sh` to `~/.claude/` and set in settings.json:
   ```json
   { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
   ```

## Stats

- **3,308 lines** of custom infrastructure across 29 scripts
- **22 hooks** across 8 lifecycle events
- **44 versions** managed concurrently (Jan–Mar 2026)
- **1,348+ sessions** indexed and searchable
- **940+ sessions** in FTS5 database (<5ms search)
- **19 deny rules**, **45 ask rules**, **340+ allow rules**
