# Dossier 1

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
On code lines in bin, hooks and scripts there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1 (measured with a brace-matching python3 scan; it reconciles with a grep -o count of 255 raw = 246 code + 9 comment).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}

Code lines only, all depths. A line whose first non-space character is `#` counts as a comment and is excluded. Every `${CLAUDE_CONFIG_DIR:-` was matched to its closing brace, so nested defaults such as `${HOME:-}` are handled. Symlinks were skipped, since the three dirs contain none. Echo'd or quoted strings on code lines are counted.

- Expansions: **246**
- Empty fallbacks (`${CLAUDE_CONFIG_DIR:-}`): **14**
- Distinct files with at least one: **112**

| Fallback value | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Reconciliation (measured, `grep -rnI -o '\${CLAUDE_CONFIG_DIR:-'`): 255 raw occurrences = 246 on code lines + 9 on comment lines. 113 files contain any occurrence, and one of them has occurrences only in comments.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls -d bin hooks scripts; grep -rnI --include='*' -o '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | wc -l; grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' > /dev/null; echo ok", "description": "Check tree dirs`
   → bin
hooks
scripts
     254
ok
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; python3 - <<'EOF'\nimport os,re,collections\ntot=0;empty=0;files=set();vals=collections.Counter();com=0;bad=[]\nfor root in ['bin','hooks','scripts']:\n  for dp,dn,fn in os.walk`
   →      572
246 14 112 comments 9 []
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rn 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; grep -rnI -c 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | awk -F: '$2>0' | wc -l; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rl 'CLAUDE_CO`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnI -o '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rnI -o '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | grep -v '}$' ; grep -rnI '\\${CLAUDE_CONFIG_DIR:-[^}]*$' bin hooks scripts | head; grep -rnI -o 'CLAUDE_CONFIG_DIR:-[^}]*{[^}`
   →      255
scripts/ship-land.sh:2179:  # SET, NOT UNSET, and that is measured too. For the 65 readers spelling `${CLAUDE_CONFIG_DIR:-
   1 bin/cc-resume-layout.sh:64:CLAUDE_CONFIG_DIR:-${HOME:-}
   1 bin/cc-resume-layout.sh:88:CLAUDE_CONFIG_DIR:-${HOME:-}
   1 bin/it2-kitty:102:CLAUDE_CONFIG_DIR:-${HO
5. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B02-r12 && cat > /tmp/tokeff-gate/f2/out/B02-r12/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}\n\nCode lines only, all depths. A line whose first non-space character is `#` counts as a comment and is`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r12/answer.md", "headline": "On code lines in bin, hooks and scripts there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.c`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
