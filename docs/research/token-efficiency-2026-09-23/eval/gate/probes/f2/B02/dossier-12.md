# Dossier 12

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/hooks/scripts, 14 with an empty fallback; the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)

Tree: /tmp/tokeff-gate/f2/tree. 572 regular files scanned (bin 121, hooks 131, scripts 320; no symlinks).

**Answer: 246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, 14 with an empty fallback, in 112 distinct files.**

| numbers | value |
|---|---|
| expansions | 246 |
| empty_fallbacks | 14 |
| files | 112 |

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* `${CLAUDE_CONFIG_DIR:-}` | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

## Per directory

| dir | expansions | files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |

## Method
- Brace-matching parser (handles nested `${HOME:-}` inside a fallback), every occurrence per line counted.
- A line is a comment if its first non-space character is `#`; those lines are excluded, trailing `# …` on a code line is not.
- Cross-check: raw grep finds 255 occurrences on all lines; 9 sit on comment lines (e.g. scripts/handoff-fire.sh:10205); 255 − 9 = 246. No unterminated or backslash-escaped instances.

## Edge cases counted (they match the form on non-comment lines)
- `scripts/cloud-land-arm-diagnose.sh:120` — `${CLAUDE_CONFIG_DIR:-<unset>}` is a display default inside an `echo`, not a path fallback.
- `scripts/relogin-desharing-activate.sh:57,60` — both `$HOME/.claude-next` hits are inside **single-quoted** `echo` strings (printed shell-rc text), so they never expand at runtime. Excluding them would give 244 expansions / 111 files; the brief's textual rule counts them.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; for d in bin hooks scripts; do echo \"$d: $(find $d -type f | wc -l) files, $(find $d -type l | wc -l) links\"; done; mkdir -p /tmp/tokeff-gate/f2/out/B02-r2", "description": "Inspect the tree layout and create output dir"}`
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
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && /usr/bin/python3 - <<'EOF'\nimport os, collections\npat = \"${CLAUDE_CONFIG_DIR:-\"\ntot=0; empty=0; files=collections.Counter(); vals=collections.Counter(); unterminated=[]; escaped=0\nfor root in (\"bin\",\"hooks\",\"scripts\"):\n    for dp,dn,fn in os.w`
   → total 246 empty 14 files 112 escaped 0
unterminated []
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
--- per top dir
bin 41 23
hooks 110 51
scripts 95 38
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && /usr/bin/grep -rn -F '${CLAUDE_CONFIG_DIR:-<unset>}' bin hooks scripts; /usr/bin/grep -rn -F '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}' bin hooks scripts; echo; echo \"raw all-lines occurrences: $(/usr/bin/grep -rho -F '${CLAUDE_CONFIG_DIR:-' bin hooks scr`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B02-r2/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)\n\nTree: /tmp/tokeff-gate/f2/tree. 572 regular files scanned (bin 121, hooks 131, scripts 320; no symlinks).\n\n**Answer: 246 `${CLAUDE_CONFIG_DIR:-…}` expan`
   → ok
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r2/answer.md", "headline": "246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/hooks/scripts, 14 with an empty fallback; the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
