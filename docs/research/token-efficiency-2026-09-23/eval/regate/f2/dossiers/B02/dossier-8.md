# Dossier 8

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
There are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/, hooks/ and scripts/, and 14 of them have an empty fallback; the rest fall back to $HOME/.claude (210), ${HOME:-}/.claude (19), $HOME/.claude-next (2) or <unset> (1).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}

**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 distinct files. 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`).**

## Method
- Scope: every regular file under `bin/`, `hooks/` and `scripts/`, at every depth. That is 572 files, with no symlinks.
- A line counts as a comment when its first non-space character is `#`. Comment lines are excluded. 9 occurrences sat on comment lines and are not counted.
- Each expansion was extracted with a brace-balanced perl match, so nested fallbacks like `${HOME:-}/.claude` are captured whole. 0 were left unparsed.
- The rule is line-based, so an expansion inside a quoted string on a code line still counts. For example, 2 of the `$HOME/.claude-next` hits are inside `echo '…'` literals in `scripts/relogin-desharing-activate.sh:57,60`.
- Cross-check: a separate grep count of `CLAUDE_CONFIG_DIR:-` on non-comment lines also returned 246.
- The raw rows (file, fallback) are in `rows.tsv` beside this file.

## Totals
| metric | value |
|---|---|
| expansions (code lines) | **246** |
| empty fallbacks `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files with ≥1 | **112** |

## Distinct fallback values
| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

The `<unset>` row is a display default in `scripts/cloud-land-arm-diagnose.sh:120` (`echo "… CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"`).

## Per directory
| dir | expansions | files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |

## Where the empty fallbacks are (14 in 13 files)
- 2 in `scripts/cloud-land-arm-diagnose.sh`
- 1 each in `hooks/completion-assert.sh`, `hooks/config-mirror-assert.sh`, `hooks/lib/agent-identity.sh`, `hooks/lib/read-before-write-parity.sh`, `hooks/lib/session-busy.sh`, `hooks/push-critical.sh`, `hooks/teammate-auto-shutdown.sh`, `scripts/desk-arm-live.sh`, `scripts/handoff-fire.sh`, `scripts/limit-recover/lr-ingest-verify.sh`, `scripts/worktree-memory-link.sh` and `scripts/wrap-ledger.sh`


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -ld bin hooks scripts && find bin hooks scripts -type l | wc -l && find bin hooks scripts -type f | wc -l && mkdir -p /tmp/tokeff-regate/f2/out/B02-r7", "description": "Inspect tree dirs and counts"}`
   → dr-xr-xr-x@ 123 chrisren  wheel  3936 Sep 24 12:36 bin
dr-xr-xr-x@  96 chrisren  wheel  3072 Sep 24 12:36 hooks
dr-xr-xr-x@ 270 chrisren  wheel  8640 Sep 24 12:36 scripts
       0
     572
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nBEGIN{ our $re; $re = qr/\\$\\{CLAUDE_CONFIG_DIR:-((?:[^{}]|\\{(?:[^{}]|(?-1))*\\}|\\$\\{(?:[^{}]|\\{[^{}]*\\})*\\})*)\\}/; }\nnext if /^\\s*#/;\nwhile (/\\$\\{CLAUDE_CONFIG_DIR:-/g) { my $p=p`
   →      246
0
     112
      14
 210 $HOME/.claude
  19 ${HOME:-}/.claude
  14 
   2 $HOME/.claude-next
   1 <unset>
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn --binary-files=text 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -o 'CLAUDE_CONFIG_DIR:-' | wc -l; grep -rn 'CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; grep -rn --binary-files=text 'CLAUDE_CONFIG_DI`
   →      246
scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
       9
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/out/B02-r7 && for d in bin hooks scripts; do printf '%s %s %s\\n' $d \"$(grep -c \"^$d/\" rows.tsv)\" \"$(grep \"^$d/\" rows.tsv | cut -f1 | sort -u | wc -l | tr -d ' ')\"; done; awk -F'\\t' '$2==\"\"{print $1}' rows.tsv | sort | uniq -c; awk -F'\\t' '$2==\"${HO`
   → bin 41 23
hooks 110 51
scripts 95 38
   1 hooks/completion-assert.sh
   1 hooks/config-mirror-assert.sh
   1 hooks/lib/agent-identity.sh
   1 hooks/lib/read-before-write-parity.sh
   1 hooks/lib/session-busy.sh
   1 hooks/push-critical.sh
   1 hooks/teammate-auto-shutdown.sh
   2 scripts/cloud-land-
5. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B02-r7/answer.md", "content": "# CLAUDE_CONFIG_DIR fallback census — /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}\n\n**246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, across 112 distinct files. 14 of them have an empty fallback (`${CLAUDE_CONFIG_DIR`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B02-r7/answer.md (file state is current in your context — no need to Read it back)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r7/answer.md", "headline": "There are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines across 112 files in bin/, hooks/ and scripts/, and 14 of them have an empty fallback; the rest fall back to $HOME/.claude (210), ${HOME:-}/.claude (19), $HOME/.cl`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
