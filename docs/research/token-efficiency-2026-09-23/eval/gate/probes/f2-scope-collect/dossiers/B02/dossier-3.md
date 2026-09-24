# Dossier 3

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured by a Python scan of the tree: 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines across 112 files, 14 of them with an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside single-quoted echo strings, so the shell never expands them), <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ under /tmp/tokeff-gate/f2/tree (all depths)

Measured with a Python scan: it walked every file, skipped lines whose first non-space character is `#`, found every `${CLAUDE_CONFIG_DIR:-` on each remaining line, and read the fallback up to the matching `}`, counting nested braces.

- Total expansions on code lines: **246**
- Empty fallbacks (`${CLAUDE_CONFIG_DIR:-}`): **14**
- Distinct files with at least one: **112**

| Fallback value | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| (empty) | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Notes:
- grep finds 253 lines with the pattern, spread over 113 files. The 7 lines not counted are comments, and one file has the pattern only in comments. One excluded comment is scripts/handoff-fire.sh:10205.
- The 2 `$HOME/.claude-next` hits are in scripts/relogin-desharing-activate.sh:57 and :60. Both are inside single-quoted `echo` strings, so the shell prints them as text and does not expand them. They are counted because the brief asks for the pattern on non-comment lines. Without them the total is 244.
- `<unset>` is a display default in scripts/cloud-land-arm-diagnose.sh:120.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls -d bin hooks scripts 2>&1; ls /tmp/tokeff-gate/f2/out/B02-r11/ 2>&1; grep -rnI --include='*' 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check tree dirs and count raw matches"}`
   → bin
hooks
scripts
     253
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rlaL -I . bin hooks scripts | head\npython3 - <<'EOF'\nimport os,re,collections\ntot=0;empty=0;files=set();vals=`
   →      572
     113
246 14 112
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
[]
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-<unset>\\|\\\\\\${CLAUDE_CONFIG_DIR:-\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '\\${CLAUDE_CONFIG_DIR:-' | head", "description": "Inspect unusual`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B02-r11 && cat > /tmp/tokeff-gate/f2/out/B02-r11/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ under /tmp/tokeff-gate/f2/tree (all depths)\n\nMeasured with a Python scan: it walked every file, skipped lines whose first no`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r11/answer.md", "headline": "Measured by a Python scan of the tree: 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines across 112 files, 14 of them with an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.c`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
