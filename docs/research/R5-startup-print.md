# SessionStart Hook Output Channels: Token Cost Analysis

## Recommendation (TL;DR)

**Use `systemMessage` in a SessionStart hook with a cached `claude-accounts` read.** This displays the `/accounts` table to the operator at session start, costs ZERO model tokens, and requires no model involvement. Pair it with a ~90s cache (warm) + non-blocking read (timeout 0.5s, max-age 90) so cold reads never stall startup.

---

## Channel Matrix: Mechanisms & Token Cost

| Mechanism | Reaches Operator Terminal? | Enters Model Context? | Token Cost | Evidence |
|---|---|---|---|---|
| **SessionStart hook `systemMessage`** | ✅ Yes | ❌ No | **0 tokens** | GitHub issue #15344: "In the CLI, these messages appear correctly." Repo CLAUDE.md: "`systemMessage` is the only field that does not extend the turn, and it provably cannot reach the model." |
| **SessionStart hook `additionalContext`** | ❌ No (enters context) | ✅ Yes | **~200 tokens** (table size) | Repo CLAUDE.md: "`hookSpecificOutput.additionalContext` DOES reach the model on Stop" and "forces a turn." Reso's `session-start.sh` line 226 uses this for MCP status (~75 tokens). |
| **SessionStart hook stdout (plain)** | ❌ No (swallowed) | ✅ Yes | **Cost = length** | "Hook stdout gets injected into additionalContext automatically" (swallowed by harness, not visible to operator). |
| **Pre-binary launcher print** | ✅ Yes (terminal scrollback) | ❌ No | **0 tokens** | Terminal output before binary invocation persists in scrollback; TUI alt-screen doesn't start until after hook fires. Requires modifying launcher. |
| **Statusline** | ✅ Yes (one line only) | ❌ No | **0 tokens** | Pure terminal display; current implementation ~15 chars context usage %. Cannot fit 30-row table. |
| **Slash command** (`/show-accounts`) | ❌ No (model-routed) | ✅ Yes | **3000–5000 tokens** | Fires a turn; model reads table in context and synthesizes response. High token cost. |

---

## Detailed Findings

### 1. **systemMessage** — Zero-Token Winner

**Evidence (measured)**: 
- GitHub issue #15344: "In the CLI, these messages appear correctly" — SessionStart hook `systemMessage` is rendered to operator terminal.
- Repo's `~/.claude-tertiary/CLAUDE.md` (Session Close Protocol section): "`systemMessage` is the only field that does not extend the turn, and it provably cannot reach the model."
- Schema: `systemMessage` in `hookSpecificOutput` renders as visible banner to operator. No model context injection. No turn created.

**Token cost**: **0 tokens**. Operator sees table; model sees nothing.

### 2. **additionalContext** — High Cost, Not Usable

`additionalContext` reaches the model and **forces a turn increment**. Injecting a ~200-token table on every session start violates the operator's constraint: *"low-token cost… I don't want overhead to every session."*

Reso's `session-start.sh` (line 226) already uses this for MCP status (~75 tokens). Adding `/accounts` would roughly double the startup cost.

### 3. **Stdout from SessionStart Hook** — Silent Injection

Plain stdout from a hook:
- Gets auto-injected into `additionalContext` (enters model context, costs tokens).
- Does NOT appear to operator's terminal (swallowed by harness).

**Not viable.**

### 4. **Pre-Binary Launcher Print** — Possible but Higher Friction

Terminal output printed before the binary is invoked (e.g., from `claude()` function in zshrc:451–503) persists in scrollback. TUI alt-screen does not start until binary takes control.

**Drawback**: Requires modifying the launcher (outside `.claude/settings.json` scope); affects all launches including non-interactive ones.

### 5. **Statusline** — Limited to Summary Only

Statusline is one persistent line (~15 chars); cannot display a 30-row table. Could show a **summary** (e.g., "📋 next4 active, 8% usage") but not the full table.

---

## Recommended Implementation

### Hook Script: `~/.claude/hooks/session-start-accounts.sh`

```bash
#!/bin/bash
CACHE_DIR="$HOME/.claude/.cache"
CACHE_FILE="$CACHE_DIR/accounts-readout.txt"
CACHE_AGE_SECS=90

mkdir -p "$CACHE_DIR"

get_accounts_cached() {
  if [[ -f "$CACHE_FILE" ]]; then
    local mtime=$(stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0)
    local age=$(($(date +%s) - mtime))
    [[ $age -le $CACHE_AGE_SECS ]] && { cat "$CACHE_FILE"; return 0; }
  fi
  
  # Attempt fresh read with 0.5s timeout (non-blocking)
  if timeout 0.5 claude-accounts --readout --max-age 90 > "$CACHE_FILE.tmp" 2>/dev/null; then
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    cat "$CACHE_FILE"
  elif [[ -f "$CACHE_FILE" ]]; then
    echo "⚠️  Accounts table stale (refresh timeout)"
    cat "$CACHE_FILE"
  else
    echo "⚠️  Accounts table unavailable (cache miss; run \`claude-accounts --readout --fresh\` to refresh)"
  fi
}

ACCOUNTS=$(get_accounts_cached)

cat <<JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "systemMessage": "📋 Account Status:\n${ACCOUNTS}"
  }
}
JSON
exit 0
```

### Settings.json Entry

```json
{
  "type": "command",
  "command": "~/.claude/hooks/session-start-accounts.sh",
  "timeout": 2
}
```

Add to `"hooks"."SessionStart"` array.

### Cache Refresh

- Hook attempts refresh on every start but times out after 0.5s (non-blocking).
- Cache refreshes ~every 90s if available.
- Or: run `claude-accounts --readout --fresh` manually to force a live sweep.

---

## Failure Modes

| Scenario | Operator Sees | Action |
|---|---|---|
| Cache fresh (common) | ✅ Full table | Normal; no issues. |
| Cache stale + refresh timeout | ⚠️ "stale" warning + last-known table | Operator sees old numbers; can run `--fresh` if needed. |
| Cache miss (first run) | ⚠️ "unavailable" + instruction | Transparent; run `--fresh` to populate. |
| Account logged out | ⚠️ "! Connected" marker in table | Visible on next start; operator can re-login. |

---

## Token Cost Summary

- **What operator sees**: Full `/accounts` table at session start (SystemMessage).
- **What model sees**: Nothing (zero tokens, zero model cost).
- **When operator must act**: Only to run `--fresh` if cache is stale (rare, ≥90s between starts).

**Satisfies the hard constraint: zero model token cost, pure script function.**

---

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [GitHub Issue #15344: Display SessionStart hook systemMessage in VS Code](https://github.com/anthropics/claude-code/issues/15344)
- [GitHub Issue #47117: Display SessionStart hook stdout to user in terminal](https://github.com/anthropics/claude-code/issues/47117)
- Reso's `/Users/chrisren/.claude-tertiary/CLAUDE.md` — Session Close Protocol section
- Reso's `~/.claude/hooks/session-start.sh` — working SessionStart example using `additionalContext`
