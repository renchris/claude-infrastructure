# Dossier 2

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Found 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines in 112 files under bin, hooks and scripts. 14 have an empty fallback, and 9 more sit on comment lines and were not counted. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside single-quoted echo strings), <unset> 1 (all measured with an inline Python brace-matching scan, cross-checked with grep).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02: CLAUDE_CONFIG_DIR fallback census

Scope: every file at any depth under /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts} (572 regular files, 0 symlinks).
Method: a read-only inline Python scan. It finds each `${CLAUDE_CONFIG_DIR:-` occurrence (more than one per line is counted), matches braces to get the fallback, including nested `${HOME:-}`, and skips lines whose first non-space character is `#`. Cross-checked with grep. All numbers below are measured.

## Results
- Expansions on code lines: **246**
- Empty fallbacks (`${CLAUDE_CONFIG_DIR:-}`): **14**
- Distinct files with at least one: **112** (208 expansions in .sh files, 38 in files with no extension)
- Excluded: 9 occurrences on `#` comment lines

## Distinct fallback values
| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

## Notes
- The 2 `$HOME/.claude-next` hits are inside single-quoted `echo` strings in scripts/relogin-desharing-activate.sh, at lines 57 and 60. They print shell code and are not expanded at that point. They are counted because the lines are not comments.
- `<unset>` is a display fallback in scripts/cloud-land-arm-diagnose.sh:120.
- scripts/handoff-fire.sh lines 8471 and 10052 each contain 2 expansions.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; ls -d out 2>/dev/null; ls /tmp/tokeff-gate/f2/out/ 2>/dev/null | head; find bin hooks scripts -type f | wc -l; find bin hooks scripts -type l | wc -l; grep -rn 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Inspect tree and count raw`
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
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && python3 - <<'EOF'\nimport os,collections,re\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();commented=0;ext=collections.Counter();odd=[]\nfor root in ['bin','hooks','scripts']:\n  for dp,dn,fn in os.walk(r`
   → 246 14 112 commented 9
odd []
Counter({'.sh': 208, '': 38})
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rn 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; echo ---; grep -rnoI '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | cut -d: -f1,2 | uniq -c | awk '$1>1'; echo ---; grep -rn 'CLAUDE_CONFIG_DIR:-' bin hooks s`
   → scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      local _cfg="$(cc-config-slot "${CC_ACCT:-next}" --class "${CC_SESSION_CLASS:-default}" 2>/dev/null || echo "${CLAUDE_CONFIG_DIR:-$HOME/.cla
4. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B02-r4 && cat > /tmp/tokeff-gate/f2/out/B02-r4/answer.md <<'EOF'\n# B02: CLAUDE_CONFIG_DIR fallback census\n\nScope: every file at any depth under /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts} (572 regular files, 0 symlinks).\nMethod: a read-only inline P`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r4/answer.md", "headline": "Found 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines in 112 files under bin, hooks and scripts. 14 have an empty fallback, and 9 more sit on comment lines and were not counted. By fallback: $HOME/.claude 210, ${HOME:-}/`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
