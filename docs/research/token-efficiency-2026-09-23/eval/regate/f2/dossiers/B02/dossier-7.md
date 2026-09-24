# Dossier 7

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
The code lines in bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files; 14 have an empty fallback, and the most common fallback is $HOME/.claude (210), followed by ${HOME:-}/.claude (19), empty (14), $HOME/.claude-next (2) and <unset> (1).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02 — CLAUDE_CONFIG_DIR fallback census

Scope: `/tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}`, all depths (572 regular files, 0 symlinks).
Counted: every `${CLAUDE_CONFIG_DIR:-<fallback>}` occurrence on lines whose first non-space character is not `#`.
Fallbacks were extracted with a brace-matching parser (so `${HOME:-}/.claude` nests correctly).

## Answer

- **Expansions: 246**
- **Empty fallbacks (`${CLAUDE_CONFIG_DIR:-}`): 14**
- **Distinct files with at least one: 112**

(9 further occurrences sit on full-line `#` comments and are excluded. No trailing-comment occurrences exist on code lines.)

Cross-check: independent `grep -oF` counts, with comment lines filtered, give the same 246 / 14 / 112.

## Distinct fallback values

| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Notes on the less common values:
- `$HOME/.claude-next` (2): both are in `scripts/relogin-desharing-activate.sh:57,60`, inside single-quoted `echo` strings that print shell rc text. They match the textual form but are not expanded at runtime.
- `<unset>` (1): `scripts/cloud-land-arm-diagnose.sh:120`, a diagnostic echo that uses a placeholder for display.

## Top files by count

`scripts/handoff-fire.sh` 25 · `hooks/session-continue.sh` 10 · `scripts/limit-recover/lr-handoff.sh` 10 · `hooks/boundary-handoff.sh` 8 · `hooks/waiting-recycle.sh` 8 · `bin/cc-lr` 7 · `hooks/completion-assert.sh` 5. The other 105 files have 1 to 4 each.

By directory: bin 23 files, hooks 51 files, scripts 38 files.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -la | head; find bin hooks scripts -type l | wc -l; find bin hooks scripts -type f | wc -l; mkdir -p /tmp/tokeff-regate/f2/out/B02-r3", "description": "Inspect tree layout and symlinks"}`
   → total 1248
dr-xr-xr-x@  46 chrisren  wheel    1472 Sep 24 12:36 .
drwxr-xr-x@  10 chrisren  wheel     320 Sep 24 13:39 ..
dr-xr-xr-x@   6 chrisren  wheel     192 Sep 24 12:36 .claude
-r--r--r--@   1 chrisren  wheel    5016 Sep 24 00:14 .gitattributes
dr-xr-xr-x@   3 chrisren  wheel      96 Sep 24 12
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && python3 - <<'EOF'\nimport os,collections\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();skipped_comment=0\nfor root in ('bin','hooks','scripts'):\n  for dp,dn,fn in os.walk(root):\n    for f in fn:\n   `
   → total 246 empty 14 files 112 comment_skipped 9
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
---files
1 bin/cc-backlog
2 bin/cc-classify
1 bin/cc-crash-report
1 bin/cc-custody
2 bin/cc-digest
1 bin/cc-discover
2 bin/cc-do
1 bin/cc-find
1 bin/cc-halt
1 bin/cc-hus
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnF -e '${CLAUDE_CONFIG_DIR:-<unset>' -e '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next' bin hooks scripts; echo ---; grep -rnF '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | head; echo ---; grep -rnF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rhF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^[[:space:]]*#' | grep -oF '${CLAUDE_CONFIG_DIR:-' | wc -l; grep -rhF '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -v '^[[:space:]]*#' | grep -oF '${CLAUDE_CONFIG_DIR:-}' | wc -l; grep -`
   →      246
      14
     112
5. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r3/answer.md <<'EOF'\n# B02 — CLAUDE_CONFIG_DIR fallback census\n\nScope: `/tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}`, all depths (572 regular files, 0 symlinks).\nCounted: every `${CLAUDE_CONFIG_DIR:-<fallback>}` occurrence on lines whose first `
   → bin       23
hooks       51
scripts       38
6. `Bash: {"command": "sed -i '' 's/By directory: bin 22 files, hooks 51 files, scripts 39 files./By directory: bin 23 files, hooks 51 files, scripts 38 files./' /tmp/tokeff-regate/f2/out/B02-r3/answer.md && tail -1 /tmp/tokeff-regate/f2/out/B02-r3/answer.md", "description": "Correct per-directory file counts`
   → By directory: bin 23 files, hooks 51 files, scripts 38 files.
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r3/answer.md", "headline": "The code lines in bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files; 14 have an empty fallback, and the most common fallback is $HOME/.claude (210), followed by ${HOME:-}/.claude (19), e`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
