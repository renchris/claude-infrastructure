# Dossier 2

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, spread over 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1. Another 9 occurrences are on comment lines and are not counted (measured: perl brace-matching scan; grep -ro cross-check finds 255 in total).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}

**Answer:** 246 `${CLAUDE_CONFIG_DIR:-<fallback>}` expansions on code lines, 14 of them with an empty fallback (`${CLAUDE_CONFIG_DIR:-}`), in 112 distinct files.

All numbers below come from one command. It runs a perl scan over every regular file in bin/, hooks/ and scripts/ at all depths (`find ... -type f | xargs perl -ne`). The scan skips any line matching `^\s*#`, finds every `${CLAUDE_CONFIG_DIR:-` on the remaining lines, and reads the fallback up to the matching `}` with brace-depth tracking, so `${HOME:-}` nested inside a fallback is handled. The per-match list is in `matches.tsv` (file, line, fallback) in this directory.

## Totals (measured)

| metric | value |
|---|---|
| expansions on code lines | 246 |
| of which empty fallback `${CLAUDE_CONFIG_DIR:-}` | 14 |
| distinct files with >=1 expansion | 112 |

By directory: bin 41 expansions / 23 files; hooks 110 / 51; scripts 95 / 38.

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

Files with empty fallbacks (one each unless noted): hooks/completion-assert.sh, hooks/config-mirror-assert.sh, hooks/lib/agent-identity.sh, hooks/lib/read-before-write-parity.sh, hooks/lib/session-busy.sh, hooks/push-critical.sh, hooks/teammate-auto-shutdown.sh, scripts/cloud-land-arm-diagnose.sh (2), scripts/desk-arm-live.sh, scripts/handoff-fire.sh, scripts/limit-recover/lr-ingest-verify.sh, scripts/worktree-memory-link.sh, scripts/wrap-ledger.sh.

The heaviest file is scripts/handoff-fire.sh with 25 expansions. The next are scripts/limit-recover/lr-handoff.sh and hooks/session-continue.sh with 10 each.

## Excluded / cross-checks (measured)

- `grep -ro -F '${CLAUDE_CONFIG_DIR:-'` finds 255 occurrences in 113 files. The 9 extra occurrences are on comment lines, and one of those files (hooks/session-save-id.sh) has its only occurrence in a comment. The 9 comment lines are: hooks/session-continue.sh:20, hooks/session-save-id.sh:3, hooks/lib/continue-sentinel.sh:7, scripts/self-path-lint.sh:154, scripts/handoff-fire.sh:10205, scripts/ship-land.sh:2170/2179/2181, scripts/cloud-land-arm-diagnose.sh:20. Three of these use a `~/.claude` fallback that appears on no code line.
- The tree contains no symlinks and no binary files with matches. Every file that matches is text. No code-line expansion is unterminated. The form `CLAUDE_CONFIG_DIR:-` never appears without the leading `${`.
- The rule is applied as written: a line counts as code unless its first non-space character is `#`. So an expansion sitting after an inline `#` comment on a code line would still be counted. A regex check found no such lines.


## Tool calls (10) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r4/ 2>&1; grep -rn --binary-files=without-match -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check dirs and raw match count"}`
   → bin
hooks
scripts
     253
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; grep -rlI -F 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v -F '${CLAUDE_CONFIG_DIR:-' | head; grep -rlI -F '${CLA`
   →      572
     113
   1 bin/cc-backlog
   1 bin/cc-classify
   1 bin/cc-crash-report
   1 bin/cc-custody
   1 bin/cc-digest
   1 bin/cc-discover
   1 bin/cc-do
   1 bin/cc-find
   1 bin/cc-halt
   1 bin/cc-husk-sweep
   1 bin/cc-lr
   1 bin/cc-notify
   1 bin/cc-pane
   1 bin/cc-reaper
   1 bin/cc-sp
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rl -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; find bin hooks scripts -type f -print0 | xargs -0 perl -e '\nfor $f (@ARGV){ open F,\"<\",$f or next; while(<F>){ next if /^\\s*#/; while(/\\$\\{CLAUDE_CONFIG_DIR:-/g){ my $p=pos($_); my $d=1`
   →      113
420	[$HOME/.claude]
38	[${HOME:-}/.claude]
28	[]
4	[$HOME/.claude-next]
2	[<unset>]
expansions 492 empty 28 files 115
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -ro -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rc -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v ':0$' | wc -l; find bin hooks scripts -type f -print0 | xargs -0 perl -ne 'print \"$ARGV\\n\" if /\\$\\{CLAUDE_CONFIG_DIR:-/' |`
   →      255
     113
     112
bin/cc-wake-headless:132:    "$ID" "${FIFO:-<unset>}" >&2
scripts/iterm2-perf-parity.sh:169:  REPORT="$REPORT  $(printf '%-8s %-46s expected=%-6s live=%s' "$state" "$key" "$expected" "${live:-<unset>}")
scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type f -print0 | xargs -0 perl -ne 'next if /^\\s*#/; while(/\\$\\{CLAUDE_CONFIG_DIR:-/g){ my $p=pos($_); my $d=1; my $i=$p; while($i<length($_) && $d>0){ my $c=substr($_,$i,1); $d++ if $c eq \"{\"; $d-- if $c eq \"}\"; $i++ } my `
   →      246
     112
      14
 210 $HOME/.claude
  19 ${HOME:-}/.claude
  14 
   2 $HOME/.claude-next
   1 <unset>
0
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | awk -F: '{l=$0; sub(/^[^:]*:[^:]*:/,\"\",l); if(l ~ /^[ \\t]*#/) print}' ; file $(grep -rl -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts) | grep -v 'text' | head; grep -rlI $'\\r' $(grep -rl -F '${CL`
   → hooks/session-continue.sh:20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
hooks/session-save-id.sh:3:# Writes to (per-account root = ${CLAUDE_CONFIG_DIR:-~/.claude}):
hooks/lib/continue-sentinel.sh:7:# `${CLAUDE_CONFIG_DIR:-~/.claude}/state/contin
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/out/B02-r4 && cut -f1 matches.tsv | cut -d/ -f1 | sort | uniq -c; awk -F'\\t' '{print $1}' matches.tsv | sort | uniq -c | cut -c1-8 | sort | uniq -c | sort -k2n | tr '\\n' ' '; echo; cd /tmp/tokeff-regate/f2/tree && grep -rn -E '[^[:space:]].*[[:space:]]#.*\\$\\`
   →   41 bin
 110 hooks
  95 scripts
  14    1 bin   23    1 scr   26    1 hoo    5    2 bin    7    2 scr   13    2 hoo    1    3 scr    2    3 bin    5    3 hoo    1    4 bin    3    4 hoo    5    4 scr    1    5 hoo    1    7 bin    2    8 hoo    1   10 hoo    1   10 scr    1   25 scr 
   1 hooks/com
8. `Bash: {"command": "cd /tmp/tokeff-regate/f2/out/B02-r4 && cut -f1 matches.tsv | sort -u | cut -d/ -f1 | uniq -c; cut -f1 matches.tsv | sort | uniq -c | sort -rn | head -5", "description": "Distinct files per dir, top files"}`
   →   23 bin
  51 hooks
  38 scripts
  25 scripts/handoff-fire.sh
  10 scripts/limit-recover/lr-handoff.sh
  10 hooks/session-continue.sh
   8 hooks/waiting-recycle.sh
   8 hooks/boundary-handoff.sh
9. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r4/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-regate/f2/tree/{bin,hooks,scripts}\n\n**Answer:** 246 `${CLAUDE_CONFIG_DIR:-<fallback>}` expansions on code lines, 14 of them with an empty fallback (`${CLAUDE_CONFIG_DIR:-}`), in `
   → (Bash completed with no output)
10. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r4/answer.md", "headline": "bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, spread over 112 files, and 14 of them have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
