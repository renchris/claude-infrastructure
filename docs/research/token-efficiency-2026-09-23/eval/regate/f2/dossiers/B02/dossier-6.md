# Dossier 6

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured with a Perl scan that skips comment lines and matches braces: bin/, hooks/ and scripts/ have 246 code-line ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside single-quoted echo text), <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)

Tree: /tmp/tokeff-regate/f2/tree

## Headline numbers (measured)
- expansions: **246**. These are `${CLAUDE_CONFIG_DIR:-<fallback>}` occurrences on code lines.
- empty_fallbacks: **14**. These are `${CLAUDE_CONFIG_DIR:-}`.
- files: **112**. These are distinct files with at least one expansion on a code line.

## Distinct fallback values (measured)
| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

## Per directory (measured)
| dir | expansions | empty | files |
|---|---|---|---|
| bin | 41 | 0 | 23 |
| hooks | 110 | 7 | 51 |
| scripts | 95 | 7 | 38 |
| **total** | **246** | **14** | **112** |

## Empty-fallback sites (code lines)
hooks/completion-assert.sh:410, hooks/config-mirror-assert.sh:9, hooks/lib/agent-identity.sh:107,
hooks/lib/read-before-write-parity.sh:141, hooks/lib/session-busy.sh:111, hooks/push-critical.sh:28,
hooks/teammate-auto-shutdown.sh:118, scripts/cloud-land-arm-diagnose.sh:171, scripts/cloud-land-arm-diagnose.sh:175,
scripts/desk-arm-live.sh:164, scripts/handoff-fire.sh:10105, scripts/limit-recover/lr-ingest-verify.sh:320,
scripts/worktree-memory-link.sh:82, scripts/wrap-ledger.sh:1145.

## Method
- I ran `find bin hooks scripts -type f -print0 | xargs -0 perl -ne ...` over every regular file. The tree has no symlinks. The script skipped lines matching `^\s*#`. It then found every `${CLAUDE_CONFIG_DIR:-` on the remaining lines and read the fallback by matching braces, so nested fallbacks like `${HOME:-}/.claude` come out whole. It counted every occurrence, including more than one on a line.
- Cross-check: `grep -rIo '\${CLAUDE_CONFIG_DIR:-'` finds 255 raw occurrences in 113 files. 9 of those occurrences are on comment lines, which leaves 246. Every one of those 9 has the fallback `~/.claude`, `$HOME/.claude` or empty. One file, scripts/ship-land.sh, has matches only on comment lines (2170, 2179, 2181), so it drops out and the file count is 112. Every match is written as `${`; none is a bare `$CLAUDE_CONFIG_DIR:-`.

## Caveats
- The rule is applied as written: a line is a comment only if its first non-space character is `#`. No code line in the tree has a match after a trailing `#` comment, so this rule makes no difference here.
- Three of the counted expansions are text in strings, not live expansions. scripts/relogin-desharing-activate.sh:57 and :60 contain the 2 `$HOME/.claude-next` ones, which sit inside single-quoted `echo` strings. The `<unset>` one is at scripts/cloud-land-arm-diagnose.sh:120. It is a real expansion, but its fallback is a display placeholder, not a path. All three are on code lines, so they are counted.
- scripts/handoff-fire.sh:10205 also holds a `$HOME/.claude-next` example, but that line is a comment, so it is excluded.


## Tool calls (13) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r8/ 2>&1; grep -rn --binary-files=text 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check dirs and raw match count"}`
   → bin
hooks
scripts
     253
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rl 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rhoI 'CLAUDE_CONFIG_DIR:-.\\{0,30\\}' bin hooks scripts | sort | uniq -c | sort -rn", "descr`
   →      113
     113
  24 CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  20 CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-r
  12 CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib
  11 CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailb
  10 CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-
   9 CLAUDE_CONFIG_DIR
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-$' bin hooks scripts; grep -rnoI '.\\{0,2\\}CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '\\${CLAUDE_CONFIG_DIR:-$' ; echo ---; grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | awk -F: '{l=$0; sub(/^[^:]*:[^:]*:/,\"\"`
   → scripts/ship-land.sh:2179:  # SET, NOT UNSET, and that is measured too. For the 65 readers spelling `${CLAUDE_CONFIG_DIR:-
---
comment lines 9
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nBEGIN{}\nnext if /^\\s*#/;\nmy $l=$_;\nwhile ($l =~ /\\$\\{CLAUDE_CONFIG_DIR:-/g) {\n  my $p=pos($l); my $d=1; my $i=$p;\n  while ($i<length($l) && $d>0){ my $c=substr($l,$i,1); if($c eq \"{\"`
   →      492
 418 [$HOME/.claude]
  38 [${HOME:-}/.claude]
  28 []
   4 [$HOME/.claude-next]
   2 [<unset>]
   1 201
   1
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && R=$(find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nnext if /^\\s*#/;\nmy $l=$_;\nwhile ($l =~ /\\$\\{CLAUDE_CONFIG_DIR:-/g) {\n  my $p=pos($l); my $d=1; my $i=$p;\n  while ($i<length($l) && $d>0){ my $c=substr($l,$i,1); if($c eq \"{\"){$d+`
   →      246
     112
 210 [$HOME/.claude]
  19 [${HOME:-}/.claude]
  14 []
   2 [$HOME/.claude-next]
   1 [<unset>]
     255
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next\\|CLAUDE_CONFIG_DIR:-~' bin hooks scripts | cut -c1-220; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | sed 's/.*\\.//' | sort | uniq -c; grep -rlI 'CLAUDE_CONFIG_DIR:-'`
   → hooks/session-continue.sh:20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
hooks/session-save-id.sh:3:# Writes to (per-account root = ${CLAUDE_CONFIG_DIR:-~/.claude}):
hooks/lib/continue-sentinel.sh:7:# `${CLAUDE_CONFIG_DIR:-~/.claude}/state/contin
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v ':[0-9]*:[[:space:]]*#' | grep '#.*\\${CLAUDE_CONFIG_DIR:-\\|`\\${CLAUDE' | cut -c1-240", "description": "Find code-line matches inside trailing comments or backticks"}`
   → (Bash completed with no output)
8. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-}` (scripts\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude}` walks\\|lib/x\"; do`' bin hooks scripts | cut -c1-200", "description": "Locate backtick-quoted occurrences"}`
   → scripts/self-path-lint.sh:154:#       (`for cand in "$(dirname "$0")/../lib/x" \ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/x"; do`)
scripts/ship-land.sh:2170:  # ABSOLUTE path, so a child resolving `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` walks straight past
scripts/ship-land.sh:2181:  # `${CLAUDE_CONFI
9. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nnext if /^\\s*#/;\nmy $l=$_;\nwhile ($l =~ /\\$\\{CLAUDE_CONFIG_DIR:-/g) {\n  my $p=pos($l); my $d=1; my $i=$p;\n  while ($i<length($l) && $d>0){ my $c=substr($l,$i,1); if($c eq \"{\"){$d++} e`
   → scripts 95 7 38
hooks 110 7 51
bin 41 0 23

   1 hooks/completion-assert.sh
   1 hooks/config-mirror-assert.sh
   1 hooks/lib/agent-identity.sh
   1 hooks/lib/read-before-write-parity.sh
   1 hooks/lib/session-busy.sh
   1 hooks/push-critical.sh
   1 hooks/teammate-auto-shutdown.sh
   2 scripts/clou
10. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnIo '\\${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -v 'ship-land' | cut -d: -f1,2 | uniq -c | awk '$1>1'", "description": "Find lines with two empty fallbacks"}`
   → (Bash completed with no output)
11. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnIo '\\${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | cut -d: -f1,2 | sort | uniq -c", "description": "List empty fallback occurrences by line"}`
   →    1 hooks/completion-assert.sh:410
   1 hooks/config-mirror-assert.sh:9
   1 hooks/lib/agent-identity.sh:107
   1 hooks/lib/read-before-write-parity.sh:141
   1 hooks/lib/session-busy.sh:111
   1 hooks/push-critical.sh:28
   1 hooks/teammate-auto-shutdown.sh:118
   1 scripts/cloud-land-arm-diagnose
12. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r8/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)\n\nTree: /tmp/tokeff-regate/f2/tree\n\n## Headline numbers (measured)\n- expansions: **246**. These are `${CLAUDE_CONFIG_DIR:-<fallback>}` occurrences on co`
   → (Bash completed with no output)
13. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r8/answer.md", "headline": "Measured with a Perl scan that skips comment lines and matches braces: bin/, hooks/ and scripts/ have 246 code-line ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 of them have an empty fallback. By fallback value: `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
