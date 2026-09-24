# Dossier 6

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
bin, hooks and scripts together hold 246 ${CLAUDE_CONFIG_DIR:-…} expansions on non-comment lines, across 112 files; 14 have an empty fallback, and the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}

**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, 14 with an empty fallback, in 112 distinct files.**

| metric | value |
|---|---|
| expansions (code lines) | **246** |
| empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files with ≥1 | **112** |

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

## By directory

| dir | expansions | files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |

## Method
- Walked all regular files at every depth under the three dirs (572 files, no symlinks present).
- Skipped lines whose first non-space character is `#`; every other line counted, including lines with a trailing comment.
- Each occurrence of `${CLAUDE_CONFIG_DIR:-` counted separately (so two on one line count as two). The fallback was pulled out by matching braces, so nested defaults like `${HOME:-}/.claude` come out whole. None were left unterminated.
- Cross-checked with grep: `grep -rnF '${CLAUDE_CONFIG_DIR:-'`, comment lines filtered, `grep -o | wc -l` = 246, which agrees.

## Notes
- 113 files contain the literal string somewhere. One of them, `scripts/ship-land.sh`, has it only on comment lines, so it is excluded, leaving 112.
- The 14 empty fallbacks are in: hooks/completion-assert.sh, hooks/config-mirror-assert.sh, hooks/lib/agent-identity.sh, hooks/lib/read-before-write-parity.sh, hooks/lib/session-busy.sh, hooks/push-critical.sh, hooks/teammate-auto-shutdown.sh, scripts/cloud-land-arm-diagnose.sh (×2), scripts/desk-arm-live.sh, scripts/handoff-fire.sh, scripts/limit-recover/lr-ingest-verify.sh, scripts/worktree-memory-link.sh, scripts/wrap-ledger.sh.
- These are counted as written, text matches rather than live expansions: both `$HOME/.claude-next` hits are in `scripts/relogin-desharing-activate.sh:57,60`, inside single-quoted `echo` strings, so the shell prints them without expanding them. The `<unset>` hit, `scripts/cloud-land-arm-diagnose.sh:120`, is a real expansion inside a double-quoted diagnostic echo. The brief's rule excludes only comment lines, so all three are included.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "ls /tmp/tokeff-gate/f2/tree/ ; mkdir -p /tmp/tokeff-gate/f2/out/B02-r7; python3 - <<'EOF'\nimport os,re,collections\nroots=['/tmp/tokeff-gate/f2/tree/'+d for d in ('bin','hooks','scripts')]\ntok='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=set();vals=collections.Counter();perfile=collec`
   → accounts.json
accounts.json.example
agents
assets
autonomy
bench
bin
bus
CLAUDE.global.md
CLAUDE.global.slim.md
commands
config
docs
evolve-fixtures
githooks
hooks
install.sh
launchd
lib
mcp-servers.json
migrations
model-config.yaml
package-lock.json
package.json
providers.json
README.md
requirement
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree; grep -rn --include='*' -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -o -F '${CLAUDE_CONFIG_DIR:-' | wc -l; grep -rlF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rnF -e '${CLAUDE_CONFIG_DIR:-<unset>`
   →      246
     113
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree; comm -23 <(grep -rlF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | sort) <(grep -rnF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u); for d in bin hooks scripts; do echo \"$d $(grep -rnF '${CLAUDE_CON`
   → scripts/ship-land.sh
bin       41       23
hooks      110       51
scripts       95       38
   1 hooks/completion-assert.sh
   1 hooks/config-mirror-assert.sh
   1 hooks/lib/agent-identity.sh
   1 hooks/lib/read-before-write-parity.sh
   1 hooks/lib/session-busy.sh
   1 hooks/push-critical.sh
   1 
4. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B02-r7/answer.md", "content": "# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}\n\n**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, 14 with an empty fallback, in 112 distinct files.**\n\n| metric | value |\n|---|---|\n`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B02-r7/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r7/answer.md", "headline": "bin, hooks and scripts together hold 246 ${CLAUDE_CONFIG_DIR:-…} expansions on non-comment lines, across 112 files; 14 have an empty fallback, and the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
