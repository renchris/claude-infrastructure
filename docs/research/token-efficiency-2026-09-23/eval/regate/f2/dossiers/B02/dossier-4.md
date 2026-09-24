# Dossier 4

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Code lines under tree/bin, tree/hooks and tree/scripts hold 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files, 14 of them with an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside single-quoted echo strings), <unset> 1. Another 9 hits sit on comment lines and are not counted (measured: perl brace-matching scan over grep -rlI; raw grep count 255 = 246 + 9).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: tree/bin, tree/hooks, tree/scripts (all depths)

Root: /tmp/tokeff-regate/f2/tree. The three dirs hold 572 regular files and no symlinks (measured: `find -type f` / `find -type l`).

## Result

| metric | value |
|---|---|
| `${CLAUDE_CONFIG_DIR:-...}` expansions on code lines | **246** |
| of those with EMPTY fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files with at least one code-line expansion | **112** |

All three were measured with a perl scan over `grep -rlI -F '${CLAUDE_CONFIG_DIR:-'`. The scan counts every match on each line, skips lines whose first non-space character is `#`, and extracts each fallback by matching braces, so nested `${HOME:-}` is handled.

Cross-checks (measured):
- Raw occurrences, comments included: 255 (`grep -rhoI '\${CLAUDE_CONFIG_DIR:-' | wc -l`). 255 = 246 code + 9 on comment lines.
- The 9 comment-line hits sit in 7 files. One of those files, scripts/ship-land.sh, has only comment-line hits, so it is excluded: 113 files contain the string and 112 contain a code-line expansion.
- No code line has a match after a trailing ` #` comment (grep check returned nothing).
- Per directory (expansions / files): bin 41 / 23, hooks 110 / 51, scripts 95 / 38. Totals are 246 / 112.

## Distinct fallback values (code lines only)

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

Notes on the odd ones:
- `$HOME/.claude-next` (2): scripts/relogin-desharing-activate.sh:57 and :60. Both are inside single-quoted `echo '...'` strings, so they are printed text and never expanded at runtime. They still count because they are on code lines, which is what the brief's rule counts.
- `<unset>` (1): scripts/cloud-land-arm-diagnose.sh:120. It is a display placeholder in an `echo`.

## Empty-fallback sites (14)

hooks/config-mirror-assert.sh:9, hooks/completion-assert.sh:410, hooks/teammate-auto-shutdown.sh:118, hooks/push-critical.sh:28, hooks/lib/agent-identity.sh:107, hooks/lib/read-before-write-parity.sh:141, hooks/lib/session-busy.sh:111, scripts/worktree-memory-link.sh:82, scripts/wrap-ledger.sh:1145, scripts/handoff-fire.sh:10105, scripts/desk-arm-live.sh:164, scripts/cloud-land-arm-diagnose.sh:171, scripts/cloud-land-arm-diagnose.sh:175, scripts/limit-recover/lr-ingest-verify.sh:320

## Excluded comment-line hits (9, not counted)

hooks/session-save-id.sh:3, hooks/session-continue.sh:20, hooks/lib/continue-sentinel.sh:7 (all `~/.claude`), scripts/self-path-lint.sh:154, scripts/handoff-fire.sh:10205 (`$HOME/.claude-next`), scripts/ship-land.sh:2170, :2179 (truncated), :2181 (empty), scripts/cloud-land-arm-diagnose.sh:20.

Out of scope and not counted: other spellings such as `${CLAUDE_CONFIG_DIR-...}` without the colon (5 raw hits) and bare `CLAUDE_CONFIG_DIR=` assignments (48 raw hits).


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r5/ 2>&1; grep -rn --binary-files=without-match -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check dirs and raw match count"}`
   → bin
hooks
scripts
     253
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; grep -rlI -F 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rl -F 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rhoI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts |`
   →      572
     113
     113
     255
     255
   5 CLAUDE_CONFIG_DIR-
 255 CLAUDE_CONFIG_DIR:-
  48 CLAUDE_CONFIG_DIR=
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rlI -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | sort | perl -e '\nmy ($tot,$empty,$cmt,%files,%vals,%cmtfiles);\nwhile(my $f=<STDIN>){chomp $f; open my $h,\"<\",$f or die; while(my $l=<$h>){\n my $iscmt = ($l =~ /^\\s*#/);\n while($l =~ /\\$\\{C`
   → code=246 empty=14 files=112 comments=9 cmtfiles=7
210	[$HOME/.claude]
19	[${HOME:-}/.claude]
14	[]
2	[$HOME/.claude-next]
1	[<unset>]
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI -F '${CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; grep -rnI -F '.claude-next' bin hooks scripts; echo ---; grep -rnI -E '^\\s*#.*\\$\\{CLAUDE_CONFIG_DIR:-' bin hooks scripts; echo ---; grep -rlI -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts |`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
bin/cc-find:131:  # store list, which already dedupes the `.claude`/`.claude-next` symlink pair.
bin/cc-resume-classify.py:78:    ".claude-next",
bin/cc-husk-sweep:48:STORES
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI -E '^\\s*[^#[:space:]].*\\s#.*\\$\\{CLAUDE_CONFIG_DIR:-' bin hooks scripts; echo ---; grep -rnI -F '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | wc -l; grep -rnI -F '${CLAUDE_CONFIG_DIR:-${HOME:-}' bin hooks scri`
   → ---
      14
bin/it2-kitty:102:            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
bin/it2-kitty:130:           "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/spawn-lineage.sh" \
bin/kitty-split-launch.sh:85:            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && comm -23 <(grep -rlI -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | sort) <(grep -rnI -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | cut -d: -f1 | sort -u); for d in bin hooks scripts; do printf \"%s \" $d; grep -rnI -F '`
   → scripts/ship-land.sh
bin       41 files       23
hooks      110 files       51
scripts       95 files       38
hooks/config-mirror-assert.sh:9
hooks/completion-assert.sh:410
hooks/teammate-auto-shutdown.sh:118
hooks/push-critical.sh:28
hooks/lib/agent-identity.sh:107
hooks/lib/read-before-write-pari
7. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B02-r5/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: tree/bin, tree/hooks, tree/scripts (all depths)\n\nRoot: /tmp/tokeff-regate/f2/tree. The three dirs hold 572 regular files and no symlinks (measured: `find -type f` / `find -type l`).\n\n## Re`
   → (Bash completed with no output)
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r5/answer.md", "headline": "Code lines under tree/bin, tree/hooks and tree/scripts hold 246 ${CLAUDE_CONFIG_DIR:-...} expansions across 112 files, 14 of them with an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
