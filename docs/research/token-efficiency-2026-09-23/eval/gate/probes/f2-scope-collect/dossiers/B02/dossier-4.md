# Dossier 4

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
On code lines under bin/, hooks/ and scripts/ there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1 (measured with a read-only python3 scan).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}

Method: I walked all three directories to every depth with a read-only python3 scan of 572 files. Each `${CLAUDE_CONFIG_DIR:-...}` occurrence was matched up to its closing brace, with nested braces handled. Lines whose first non-space character is `#` were skipped; 9 occurrences on comment lines were excluded.

| Metric | Count |
|---|---|
| Expansions on code lines | **246** |
| Empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| Distinct files with at least one | **112** (21 in bin/, 91 *.sh in hooks/ and scripts/) |

| Fallback value | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Note: I counted text literally on non-comment lines. Three occurrences sit inside echoed strings rather than being live expansions:
- The 2 `$HOME/.claude-next` ones are inside single-quoted `echo` lines at scripts/relogin-desharing-activate.sh:57 and :60.
- The `<unset>` one is a diagnostic print at scripts/cloud-land-arm-diagnose.sh:120.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls -d bin hooks scripts; mkdir -p /tmp/tokeff-gate/f2/out/B02-r9; grep -rnI --null -e 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | awk -F'\\0' '{print $1\"\\t\"$2}' | awk -F'\\t' '{split($2,a,\":\"); line=substr($2,length(a[1])+2); if (line ~ /^[ \\t]*#/) nex`
   → bin
hooks
scripts
ok
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; python3 - <<'EOF'\nimport os,collections,re\ntot=0;empty=0;files=set();vals=collections.Counter();comm=0\nfor d in ['bin','hooks','scripts']:\n  for root,ds,fs in os.walk(d):\n `
   →      572
246 14 112 comment-occurrences 9
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rn 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | sed 's/.*\\.//' | sort | uniq -c; grep -rn 'CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -v '^[^:]*:[0-`
   → scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      local _cfg="$(cc-config-slot "${CC_ACCT:-next}" --class "${CC_SESSION_CLASS:-default}" 2>/dev/null || echo "${CLAUDE_CONFIG_DIR:-$HOME/.cla
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B02-r9/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}\n\nMethod: I walked all three directories to every depth with a read-only python3 scan of 572 files. Each `${CLAUDE_CONFIG_DIR:-...}` occurrence was `
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r9/answer.md", "headline": "On code lines under bin/, hooks/ and scripts/ there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
