# log-rotation — activation snippet (T-P10-2 idl.jsonl + bash-log rotation)

**C10 ceiling:** the agent builds + RED-proves `scripts/rotate-autonomy-logs.sh` and stages the
TEMPLATE plist. The **operator** performs the live wiring below. Nothing here is auto-loaded: this
file is the hand-off. The agent never `launchctl load`s, never edits `settings.json`, never edits a
live writer/hook, and never symlinks. Until the operator wires it, `rotate-autonomy-logs.sh` is a
plain CLI you can run by hand — and the agent already ran it ONCE against the live files to drain the
183 MB backlog (see the item evidence), so wiring only makes it *recurring*.

## Why this is safe (the load-bearing invariant)

Every writer of these logs appends **per-line via `>>`** — `lead-supervisor.sh:61`,
`hooks/log-bash.sh`, `hooks/validate-bash.sh` all `open → write → close` on each call and hold **no
persistent fd**. So renaming the fat file aside and letting the next `>>` recreate it in place
(logrotate's `create` mode) loses **zero** data and needs **no** writer edit (no C10 surface). The
recreate step additionally only fires when a racing writer hasn't already remade the path, so an
in-flight line is never truncated. Rotated data is gzipped and kept (`ROTATE_KEEP` generations), and
live consumers only `tail -1` the logs (`desk-invariant.sh`), so a smaller live file is strictly
better for them.

## What was built (repo files, on `feat/desk-log-rotation`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `scripts/rotate-autonomy-logs.sh` | size-gated `create`-mode rotation engine (mv → recreate → gzip → prune) | **symlink** into `~/.claude/scripts/` + load the plist below |
| `launchd/com.claude.log-rotation.plist` | TEMPLATE plist (RunAtLoad **true**, StartInterval 3600) | **operator** `launchctl bootstrap` |
| `tests/rotate-autonomy-logs.bats` | 10 RED-proofs (threshold, recreate, no-loss, mode, prune, gzip-off, missing, mixed, idempotent, env) | none (CI/regression only) |

## Interface contract

```
rotate-autonomy-logs.sh [target ...]   rotate each target (default: the 3 unbounded logs) whose
                                        size >= ROTATE_MAX_BYTES; else skip. Always exits 0.
rotate-autonomy-logs.sh --help         the header block.
```

Default targets: `~/.claude/autonomy/idl.jsonl`, `~/.claude/logs/bash-commands.log`,
`~/.claude/logs/bash-execution.log`.

Env knobs (all default sanely): `ROTATE_MAX_BYTES` (25 MiB) · `ROTATE_KEEP` (8) ·
`ROTATE_GZIP` (1) · `ROTATE_TARGETS` (whitespace/newline-separated override) · `CC_IDL` (audit
sink). Defaults hardcode `$HOME/.claude` (NOT `$CLAUDE_CONFIG_DIR`) to match the writers.

## Operator activation

```bash
# 1. symlink the engine into the live scripts dir (matches the sibling daemons' layout)
ln -sf ~/Development/claude-infrastructure/scripts/rotate-autonomy-logs.sh ~/.claude/scripts/rotate-autonomy-logs.sh

# 2. (optional) dry sanity run — prints "rotated=N skipped=M"; safe, idempotent
~/.claude/scripts/rotate-autonomy-logs.sh

# 3. install + load the recurring job (RunAtLoad rotates immediately, then hourly)
cp ~/Development/claude-infrastructure/launchd/com.claude.log-rotation.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude.log-rotation.plist
launchctl list | grep com.claude.log-rotation     # verify loaded
```

To unload: `launchctl bootout gui/$(id -u)/com.claude.log-rotation`.
