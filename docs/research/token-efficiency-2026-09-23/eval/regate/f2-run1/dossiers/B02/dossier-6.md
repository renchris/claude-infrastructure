# Dossier 6

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured with a python3 walk over 572 files, cross-checked against grep's 255 raw matches: bin/, hooks/ and scripts/ hold 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines across 112 files. 14 have an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside echo strings), <unset> 1. Another 9 expansions sit on comment lines and are excluded.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)

Tree: /tmp/tokeff-regate/f2/tree. I counted every `${CLAUDE_CONFIG_DIR:-<fallback>}` on code lines. A line whose first non-space character is `#` is a comment and is excluded. Nested braces in the fallback (such as `${HOME:-}`) are matched correctly.

Method (measured): an inline python3 os.walk over the 572 regular files (`find bin hooks scripts -type f | wc -l`). No symlinks and no binary files contain a match. Cross-check (measured): `grep -rnIo '\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l` = 255 raw, which is 246 on code lines plus 9 on comment lines.

## Results (measured)

| Metric | Value |
|---|---|
| Expansions on code lines | **246** |
| Empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| Distinct files with at least one expansion | **112** |
| (Excluded: expansions on comment lines) | 9 |

## Distinct fallback values

| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Notes:
- The 2 `$HOME/.claude-next` expansions are at scripts/relogin-desharing-activate.sh:57 and :60. Both sit inside `echo '...'` string literals that print rc-file text; they are not live expansions. I counted them because the brief defines code by line, not by execution.
- The single `<unset>` is a display fallback in scripts/cloud-land-arm-diagnose.sh:120 (`CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}` in an echo).
- No code line has the pattern inside a trailing `# ...` comment (checked with grep).
- Files with the most expansions: scripts/handoff-fire.sh (25), hooks/session-continue.sh (10), scripts/limit-recover/lr-handoff.sh (10), hooks/boundary-handoff.sh (8), hooks/waiting-recycle.sh (8), bin/cc-lr (7).


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r8/ 2>&1; grep -rnI --include='*' -o '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | wc -l", "description": "Check dirs and raw count of expansions"}`
   → bin
hooks
scripts
ls: /tmp/tokeff-regate/f2/out/B02-r8/: No such file or directory
     254
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; python3 - <<'EOF'\nimport os,collections\nroots=['bin','hooks','scripts']\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();ba`
   →      572
total 246 empty 14 files 112 commented 9
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
unterminated []
1 bin/cc-backlog
2 bin/cc-classify
1 bin/cc-crash-report
1 bin/cc-custody
2 bin/cc-digest
1 bin/cc-discover
2 bin/cc-do
1 bin/cc-find
1 bin/cc-halt
1 
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI -e 'CLAUDE_CONFIG_DIR:-<unset>' -e 'CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -E '^[^:]+:[0-9]+:[[:space:]]*#' | head -20; grep -rnIo '\\${CLAUDE_CONFIG_DIR:-' bin hooks`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*#' | grep -E '[[:space:]]#[^!{]*CLAUDE_CONFIG_DIR:-' | head", "description": "Check for trailing-comment occurrences on code lines"}`
   → (Bash completed with no output)
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r8 && cat > /tmp/tokeff-regate/f2/out/B02-r8/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)\n\nTree: /tmp/tokeff-regate/f2/tree. I counted every `${CLAUDE_CONFIG_DIR:-<fallback>}` on code lines. A line w`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r8/answer.md", "headline": "Measured with a python3 walk over 572 files, cross-checked against grep's 255 raw matches: bin/, hooks/ and scripts/ hold 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines across 112 files. 14 have an empty fallback. By `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
