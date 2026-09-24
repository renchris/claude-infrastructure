# Dossier 5

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
bin/, hooks/ and scripts/ contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, spread over 112 files; 14 of them have an empty fallback, and the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)

**Answer:** 246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 files. 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`).

Scope: /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}. I read all 572 files there, recursively, and none was a broken symlink. A line counts as a comment when its first non-space character is `#`, and those lines were excluded. Each occurrence is counted separately, so a line with two counts twice. I took each fallback by matching braces, which keeps nested defaults such as `${HOME:-}/.claude` whole. No expansion was left unterminated.

## Distinct fallback values

| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* `${CLAUDE_CONFIG_DIR:-}` | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` (display string, `scripts/cloud-land-arm-diagnose.sh:120`) | 1 |
| **Total** | **246** |

## Breakdown by directory

| Dir | Expansions | Files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |
| **Total** | **246** | **112** |

By file type: 208 are in `.sh` files and 38 are in files with no extension.

## Cross-check

I ran a separate count with `grep -rnF` and `awk gsub`, again excluding comment lines, and it also found 246 occurrences, on 244 lines (two lines carry two each). If comment lines are included, 113 files contain the pattern, so one file has it only in comments.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r6 && python3 - <<'EOF'\nimport os,collections\nroots=['/tmp/tokeff-regate/f2/tree/bin','/tmp/tokeff-regate/f2/tree/hooks','/tmp/tokeff-regate/f2/tree/scripts']\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collection`
   → scanned files 572 broken symlinks 0
total 246 empty 14 files 112 unterm 0
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
Counter({'.sh': 208, '(none)': 38})
/tmp/tokeff-regate/f2/tree/bin 41 23
/tmp/tokeff-regate/f2/tree/hooks 110 51
/tmp/tokeff-regate/f2/tree/sc
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree; grep -rnF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | awk '{n+=gsub(/\\$\\{CLAUDE_CONFIG_DIR:-/,\"&\")} END{print n, NR}'; grep -rnF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'`
   → 246 244
scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
     113
3. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B02-r6/answer.md", "content": "# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)\n\n**Answer:** 246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 files. 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`).\n\n`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B02-r6/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r6/answer.md", "headline": "bin/, hooks/ and scripts/ contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, spread over 112 files; 14 of them have an empty fallback, and the fallback values are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
