# Dossier 4

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
bin/, hooks/ and scripts/ contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines, spread across 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1. These counts were measured with a python brace-matching walk and cross-checked by a grep pipeline. Another 9 occurrences on # lines were left out.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)

Tree: /tmp/tokeff-regate/f2/tree. Searched every regular file under bin/, hooks/ and scripts/ at all depths. There are no symlinks, and no undecodable file contains the pattern.

Method (measured): a read-only inline python3 walk (os.walk) found every `${CLAUDE_CONFIG_DIR:-` occurrence. It skipped lines whose first non-space character is `#`. For each occurrence, it took the fallback text up to the matching close brace, counting nested braces. The totals were cross-checked with `grep -rn -F ... | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -o -F ... | wc -l` for each directory, and both methods agree.

## Results

| Metric | Value |
|---|---|
| Expansions on code (non-comment) lines | **246** |
| of which have an empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| Distinct files with at least one | **112** |

Per directory (measured, grep pipeline):

| Dir | Expansions | Files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |
| **Total** | **246** | **112** |

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

- Excluded comment lines: 9 occurrences on 9 `#` lines. These are hooks/session-continue.sh:20, hooks/lib/continue-sentinel.sh:7, hooks/session-save-id.sh:3, scripts/handoff-fire.sh:10205, scripts/self-path-lint.sh:154, scripts/ship-land.sh:2170/2179/2181 and scripts/cloud-land-arm-diagnose.sh:20. The raw count including comments is 255 (grep -o).
- I counted by the brief's literal rule (a non-`#` line is code). Some counted expansions sit inside string literals rather than live shell code:
  - Both `$HOME/.claude-next` hits are inside `echo '...'` text at scripts/relogin-desharing-activate.sh:57 and :60.
  - One empty-fallback hit is inside a `zsh -lc '...'` string at scripts/cloud-land-arm-diagnose.sh:171. It is still evaluated, by the child shell.
- The single `<unset>` fallback is at scripts/cloud-land-arm-diagnose.sh:120. It is a display default in an `echo`, not a path.
- A trailing `# ...` comment after code on the same line does not make the line a comment under the brief's rule.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r5/ 2>&1; grep -rn --binary-files=without-match -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check tree and count raw matches"}`
   → bin
hooks
scripts
ls: /tmp/tokeff-regate/f2/out/B02-r5/: No such file or directory
     253
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; python3 - <<'EOF'\nimport os,collections\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=set();vals=collections.Counter();commented=0;skipped=[]\nfor root in ['bin','hooks','scripts']:\n  for dp,dn,fn in os.walk(r`
   → total 246 empty 14 files 112 commented 9 symlinks []
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn -F '${CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; grep -rn -F '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next' bin hooks scripts; grep -rn -F '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -v '^[^:]*:[0-9]*:[[:space:]]*#'; grep -rn -F '${CLAUDE_C`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && for d in bin hooks scripts; do echo \"$d $(grep -rn -F '${CLAUDE_CONFIG_DIR:-' $d | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | grep -o -F '${CLAUDE_CONFIG_DIR:-' | wc -l) $(grep -rn -F '${CLAUDE_CONFIG_DIR:-' $d | grep -v '^[^:]*:[0-9]*:[[:space:]]*#' | cut`
   → bin       41       23
hooks      110       51
scripts       95       38
hooks/session-continue.sh:20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUD
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r5 && cat > /tmp/tokeff-regate/f2/out/B02-r5/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)\n\nTree: /tmp/tokeff-regate/f2/tree. Searched every regular file under bin/, hooks/ and scripts/ at all depths.`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r5/answer.md", "headline": "bin/, hooks/ and scripts/ contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines, spread across 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empt`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
