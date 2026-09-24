# Dossier 3

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured with a brace-aware perl scan (checked against grep -F): 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines in 112 files under bin, hooks and scripts. 14 have an empty fallback. The fallbacks are $HOME/.claude (210), ${HOME:-}/.claude (19), empty (14), $HOME/.claude-next (2) and <unset> (1).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02: CLAUDE_CONFIG_DIR fallback census

Scope: every regular file under /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}, all depths (no symlinks present).
Counted: every `${CLAUDE_CONFIG_DIR:-<fallback>}` on a line whose first non-space character is not `#`.
Fallback extracted with brace-balanced parsing (so `${HOME:-}/.claude` is one fallback).

## Results (measured: perl brace-balanced scan over `find ... -type f`; full list in occurrences.tsv)

| metric | value |
|---|---|
| expansions (code lines) | 246 |
| empty fallbacks `${CLAUDE_CONFIG_DIR:-}` | 14 |
| distinct files with at least one | 112 (bin 23, hooks 51, scripts 38) |

Expansions by directory: bin 41, hooks 110, scripts 95.

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| (empty) | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| total | 246 |

Non-default locations:
- empty: hooks/completion-assert.sh:410, hooks/config-mirror-assert.sh:9, hooks/lib/agent-identity.sh:107, hooks/lib/read-before-write-parity.sh:141, hooks/lib/session-busy.sh:111, hooks/push-critical.sh:28, hooks/teammate-auto-shutdown.sh:118, scripts/cloud-land-arm-diagnose.sh:171,175, scripts/desk-arm-live.sh:164, scripts/handoff-fire.sh:10105, scripts/limit-recover/lr-ingest-verify.sh:320, scripts/worktree-memory-link.sh:82, scripts/wrap-ledger.sh:1145
- `$HOME/.claude-next`: scripts/relogin-desharing-activate.sh:57,60
- `<unset>` (display string in an echo): scripts/cloud-land-arm-diagnose.sh:120

## Cross-checks
- `grep -rIn -F 'CLAUDE_CONFIG_DIR:-'` minus `#`-leading lines: 244 lines holding 246 occurrences (`grep -o | wc -l`), all in `${...}` form; matches the perl count.
- Including comment lines the fixed-string grep finds 253 lines, so 9 comment lines were excluded.
- No occurrence sits after a trailing `#` on a code line; no binary files contain the string.


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r1/ 2>&1; grep -rIn --exclude-dir=.git -e '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | wc -l", "description": "Check dirs and count candidate lines"}`
   → bin
hooks
scripts
ls: /tmp/tokeff-regate/f2/out/B02-r1/: No such file or directory
       0
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rIn -F --exclude-dir=.git 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rIn -F --exclude-dir=.git 'CLAUDE_CONFIG_DIR' bin hooks scripts | wc -l; find bin hooks scripts -type l | head", "description": "Count with fixed-string grep"}`
   →      253
     447
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nnext if /^\\s*#/;\nmy $s=$_; my $pos=0;\nwhile ((my $i=index($s,q{${CLAUDE_CONFIG_DIR:-},$pos))>=0){\n  my $j=$i+length(q{${CLAUDE_CONFIG_DIR:-}); my $d=1; my $k=$j;\n  while($k<length($s) && `
   → Can't find string terminator "}" anywhere before EOF at -e line 4.
xargs: perl: exited with status 255; aborting
files 0
exp  empty
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nBEGIN{ $P = \"\\$\" . \"{CLAUDE_CONFIG_DIR:-\"; }\nif (/^\\s*#/) { close ARGV if eof; next; }\nmy $s=$_; my $pos=0;\nwhile ((my $i=index($s,$P,$pos))>=0){\n  my $j=$i+length($P); my $d=1; my $`
   → 210	[$HOME/.claude]
19	[${HOME:-}/.claude]
14	[]
2	[$HOME/.claude-next]
1	[<unset>]
files 112
exp 246 empty 14
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn -F 'CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; echo ---; grep -rIn -F --exclude-dir=.git 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | wc -l; grep -rIn -F 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
---
     244
     246
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && mkdir -p /tmp/tokeff-regate/f2/out/B02-r1 && find bin hooks scripts -type f -print0 | xargs -0 perl -ne '\nBEGIN{ $P = \"\\$\" . \"{CLAUDE_CONFIG_DIR:-\"; }\nif (/^\\s*#/) { close ARGV if eof; next; }\nmy $s=$_; my $pos=0;\nwhile ((my $i=index($s,$P,$pos`
   → ---
bin/cc-resume-layout.sh	64	${HOME:-}/.claude	
bin/cc-resume-layout.sh	88	${HOME:-}/.claude	
bin/it2-kitty	102	${HOME:-}/.claude	
bin/it2-kitty	130	${HOME:-}/.claude	
bin/it2-wrapper	182	${HOME:-}/.claude	
bin/kitty-split-launch.sh	85	${HOME:-}/.claude	
hooks/completion-assert.sh	410		
hooks/conf
7. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r1/answer.md <<'EOF'\n# B02: CLAUDE_CONFIG_DIR fallback census\n\nScope: every regular file under /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}, all depths (no symlinks present).\nCounted: every `${CLAUDE_CONFIG_DIR:-<fallback>}` on a line whose firs`
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r1/answer.md", "headline": "Measured with a brace-aware perl scan (checked against grep -F): 246 ${CLAUDE_CONFIG_DIR:-...} expansions on non-comment lines in 112 files under bin, hooks and scripts. 14 have an empty fallback. The fallbacks are $HOME/.cla`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
