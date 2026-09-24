# Dossier 7

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
There are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/hooks/scripts, and 14 of them have an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both are single-quoted echo literals), <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}

**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 files; 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`).**

numbers: {"expansions": 246, "empty_fallbacks": 14, "files": 112}

## Distinct fallback values

| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* `${CLAUDE_CONFIG_DIR:-}` | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

## Method
- Walked all regular files at every depth under bin (121 files), hooks (131), scripts (320). None of them are symlinks, so the walk missed nothing.
- A line is a comment when its first non-space character is `#`. Those lines were skipped; they held 9 more occurrences that are not counted.
- Counted every occurrence on each line, not one per line: 244 code lines carry 246 occurrences. The fallback was pulled out by brace-matching so a nested `${HOME:-}` stays whole. No unbalanced matches.

## Caveats (counted, but worth knowing)
- The 2 `$HOME/.claude-next` hits are in `scripts/relogin-desharing-activate.sh:57,60`. They sit inside single-quoted `echo '…'` strings, so the text is printed rather than expanded by that script.
- `scripts/cloud-land-arm-diagnose.sh:171` has `'printf %s "${CLAUDE_CONFIG_DIR:-}"'` in single quotes. It is expanded by a child `zsh -lc`, not by the script itself.
- `<unset>` is a display placeholder in `scripts/cloud-land-arm-diagnose.sh:120` (an `echo`), not a path.
- Leaving out the 2 single-quoted `echo` literals would give 244 expansions in 112 files (the file still has other hits). The empty count stays 14.

## Files with the most expansions
scripts/handoff-fire.sh 25 · hooks/session-continue.sh 10 · scripts/limit-recover/lr-handoff.sh 10 · hooks/boundary-handoff.sh 8 · hooks/waiting-recycle.sh 8 · bin/cc-lr 7 · hooks/completion-assert.sh 5. The other 105 files have 1–4 each.


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && for d in bin hooks scripts; do echo \"$d: files=$(find $d -type f | wc -l) links=$(find $d -type l | wc -l)\"; done; ls -ld /tmp/tokeff-regate/f2/out/B02-r3 2>&1", "description": "Check tree shape and output dir"}`
   → Exit code 1
bin: files=     121 links=       0
hooks: files=     131 links=       0
scripts: files=     320 links=       0
ls: /tmp/tokeff-regate/f2/out/B02-r3: No such file or directory
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r3 && cd /tmp/tokeff-regate/f2/tree && python3 - <<'EOF'\nimport os,collections,re\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=set();vals=collections.Counter();perfile=collections.Counter();skipped_comment=0;unbal=0\nfor d in ('bin','hooks','`
   → total 246 empty 14 files 112 comment-skipped 9 unbal 0
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
---
1 bin/cc-backlog
2 bin/cc-classify
1 bin/cc-crash-report
1 bin/cc-custody
2 bin/cc-digest
1 bin/cc-discover
2 bin/cc-do
1 bin/cc-find
1 bin/cc-halt
1 bin/cc-
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn -F -e '${CLAUDE_CONFIG_DIR:-<unset>' -e '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next' bin hooks scripts; echo ---; grep -rn -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#' | grep -E \"'[^']*\\\\\\$\\{CLAUDE_CO`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r3/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}\n\n**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 files; 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`).**\n`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r3/answer.md", "headline": "There are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/hooks/scripts, and 14 of them have an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
