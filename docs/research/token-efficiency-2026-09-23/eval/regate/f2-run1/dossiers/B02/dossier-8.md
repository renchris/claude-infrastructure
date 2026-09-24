# Dossier 8

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
There are 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines across 112 files. 14 have an empty fallback, and the other values are $HOME/.claude (210), ${HOME:-}/.claude (19), $HOME/.claude-next (2) and <unset> (1).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)

Tree: /tmp/tokeff-regate/f2/tree. 572 regular files scanned, no symlinks. A line counts as code unless its first non-space character is `#`. Each `${CLAUDE_CONFIG_DIR:-...}` occurrence counts once, even when a line has several. Fallbacks were read with brace matching, so nested forms like `${HOME:-}` are parsed correctly. No expansion was left unterminated.

| Metric | Value |
|---|---|
| Expansions on code lines | **246** |
| Empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| Distinct files with at least one | **112** |

## Distinct fallback values

| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 (scripts/relogin-desharing-activate.sh:57 and :60, both inside echo'd text) |
| `<unset>` | 1 (scripts/cloud-land-arm-diagnose.sh:120, a display value) |
| **Total** | **246** |

## Cross-check
- A plain `grep -F` over non-comment lines finds the same 246 occurrences.
- A further 9 occurrences sit on comment lines and are excluded. One example is scripts/handoff-fire.sh:10205, which has the `.claude-next` form.
- 113 files contain the pattern anywhere. One of them has it only on comment lines, which is why the code-line file count is 112.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r7 && python3 - <<'EOF'\nimport os,collections\nroots=['/tmp/tokeff-regate/f2/tree/bin','/tmp/tokeff-regate/f2/tree/hooks','/tmp/tokeff-regate/f2/tree/scripts']\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collection`
   → files scanned 572 symlinks 0 unterm 0
total 246 empty 14 files 112
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn --include='*' -F '${CLAUDE_CONFIG_DIR:-<unset>}' bin hooks scripts; grep -rn -F '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}' bin hooks scripts; echo ---; grep -rh -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^[[:space:]]*#' | grep -o -F`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r7/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)\n\nTree: /tmp/tokeff-regate/f2/tree. 572 regular files scanned, no symlinks. A line counts as code unless its first non-space character is `#`. Each `${CLA`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r7/answer.md", "headline": "There are 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines across 112 files. 14 have an empty fallback, and the other values are $HOME/.claude (210), ${HOME:-}/.claude (19), $HOME/.claude-next (2) and <unset> (1).", "nu`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
