# Dossier 4

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Across bin/, hooks/ and scripts/ there are 246 `${CLAUDE_CONFIG_DIR:-...}` expansions on non-comment lines, in 112 files. 14 have an empty fallback; the rest use `$HOME/.claude` (210), `${HOME:-}/.claude` (19), `$HOME/.claude-next` (2, both inside echoed text) or `<unset>` (1). All counts are measured with a brace-matching Python walk that skipped 9 hits on comment lines.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02-r5: census of CLAUDE_CONFIG_DIR fallbacks in /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}

## Answer
- **Total `${CLAUDE_CONFIG_DIR:-<fallback>}` expansions on code lines: 246**
- **With an empty fallback (`${CLAUDE_CONFIG_DIR:-}`): 14**
- **Distinct files with at least one: 112**

All three are measured. I walked the tree with a Python `os.walk` script sent over stdin, so no scratch file was written. It read every regular file under bin/, hooks/ and scripts/ at any depth, 572 files in total. There are no symlinks in those directories (checked with `find -type l`), and no binary file contains the pattern.

## Distinct fallback values (measured)
| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* `${CLAUDE_CONFIG_DIR:-}` | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

## Method
- For each line containing `${CLAUDE_CONFIG_DIR:-`, a line whose first non-space character is `#` counts as a comment and is skipped. 9 occurrences on comment lines were excluded: hooks/session-continue.sh:20, hooks/lib/continue-sentinel.sh:7, hooks/session-save-id.sh:3, scripts/self-path-lint.sh:154, scripts/handoff-fire.sh:10205, scripts/ship-land.sh:2170/2179/2181 and scripts/cloud-land-arm-diagnose.sh:20.
- Each occurrence on a code line counts once, even when a line has two (scripts/handoff-fire.sh:8471 and :10052). The fallback is read with brace-depth matching, so nested forms like `${HOME:-}/.claude` come out whole.
- Trailing `# ...` text after code on the same line does not turn that line into a comment.

## Empty-fallback sites (14)
hooks/completion-assert.sh:410, hooks/lib/read-before-write-parity.sh:141, hooks/config-mirror-assert.sh:9, hooks/lib/session-busy.sh:111, hooks/teammate-auto-shutdown.sh:118, hooks/push-critical.sh:28, hooks/lib/agent-identity.sh:107, scripts/handoff-fire.sh:10105, scripts/worktree-memory-link.sh:82, scripts/wrap-ledger.sh:1145, scripts/desk-arm-live.sh:164, scripts/limit-recover/lr-ingest-verify.sh:320, scripts/cloud-land-arm-diagnose.sh:171, scripts/cloud-land-arm-diagnose.sh:175.

## Caveats
- The two `$HOME/.claude-next` hits (scripts/relogin-desharing-activate.sh:57 and :60) sit inside single-quoted `echo` strings. They are code lines that print the expansion as text; the script never evaluates it. Both are counted because the brief counts by line type, not by whether the shell evaluates the expansion.
- The `<unset>` hit (scripts/cloud-land-arm-diagnose.sh:120) is a display default in an echo, not a path fallback.
- Out of scope and not counted: `${CLAUDE_CONFIG_DIR-...}` (no colon), `${CLAUDE_CONFIG_DIR:=...}` and bare `$CLAUDE_CONFIG_DIR`.
- A plain `grep -o` gives 254 raw matches. That is 246 code + 9 comment = 255, minus 1 because the comment at scripts/ship-land.sh:2179 has a `${CLAUDE_CONFIG_DIR:-` with no closing brace on that line.

## Files per count (measured)
25 scripts/handoff-fire.sh; 10 hooks/session-continue.sh, scripts/limit-recover/lr-handoff.sh; 8 hooks/boundary-handoff.sh, hooks/waiting-recycle.sh; 7 bin/cc-lr; 5 hooks/completion-assert.sh; 4 bin/cc-reaper, hooks/anti-deference-nudge.sh, hooks/teammate-auto-shutdown.sh, hooks/validate-bash.sh, scripts/boot-resume-launch.sh, scripts/cloud-land-arm-diagnose.sh, scripts/limit-recover/lr-fire-resume.sh, scripts/limit-recover/lr-fleet.sh, scripts/limit-recover/lr-reset-poller.sh; the remaining 96 files hold 1 to 3 each. There are 112 files in total, split as bin 23, hooks 51 and scripts 38.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; ls -d bin hooks scripts; ls /tmp/tokeff-gate/f2/out/ 2>&1 | head; grep -rnI --include='*' -o '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | wc -l", "description": "Inspect tree and count raw matches"}`
   → accounts.json
accounts.json.example
agents
assets
autonomy
bench
bin
bus
CLAUDE.global.md
CLAUDE.global.slim.md
commands
config
docs
evolve-fixtures
githooks
hooks
install.sh
launchd
lib
mcp-servers.json
migrations
model-config.yaml
package-lock.json
package.json
providers.json
README.md
requirement
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; python3 - <<'EOF'\nimport os,re,collections\nroots=['bin','hooks','scripts']\npat='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();c`
   →      572
total 246 empty 14 files 112 comment_skipped 9 binskip []
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
1 bin/
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnF -e '${CLAUDE_CONFIG_DIR:-<unset>' -e '${CLAUDE_CONFIG_DIR:-$HOME/.claude-next' -e '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | cut -c1-220; echo ---; grep -rnF '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | awk -F: '{l=$0; sub(/^[^:]*:[^:]*:/,\"\",l`
   → hooks/completion-assert.sh:410:    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && roots+=( "${CLAUDE_CONFIG_DIR}/teams" )
hooks/lib/read-before-write-parity.sh:141:  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then printf '%s' "$CLAUDE_CONFIG_DIR"
hooks/config-mirror-assert.sh:9:cfg="${CLAUDE_CONFIG_DIR:-}"
hooks/lib/s
4. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B02-r5 && cat > /tmp/tokeff-gate/f2/out/B02-r5/answer.md <<'EOF'\n# B02-r5: census of CLAUDE_CONFIG_DIR fallbacks in /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}\n\n## Answer\n- **Total `${CLAUDE_CONFIG_DIR:-<fallback>}` expansions on code lines: 246**\n`
   → {'bin': 23, 'hooks': 51, 'scripts': 38}
5. `Bash: {"command": "sed -i '' 's/split as bin 23, hooks 54 and scripts 35\\./split as bin 23, hooks 51 and scripts 38./' /tmp/tokeff-gate/f2/out/B02-r5/answer.md && grep -n 'split as' /tmp/tokeff-gate/f2/out/B02-r5/answer.md", "description": "Correct per-root split in answer"}`
   → 35:25 scripts/handoff-fire.sh; 10 hooks/session-continue.sh, scripts/limit-recover/lr-handoff.sh; 8 hooks/boundary-handoff.sh, hooks/waiting-recycle.sh; 7 bin/cc-lr; 5 hooks/completion-assert.sh; 4 bin/cc-reaper, hooks/anti-deference-nudge.sh, hooks/teammate-auto-shutdown.sh, hooks/validate-bash.sh,
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r5/answer.md", "headline": "Across bin/, hooks/ and scripts/ there are 246 `${CLAUDE_CONFIG_DIR:-...}` expansions on non-comment lines, in 112 files. 14 have an empty fallback; the rest use `$HOME/.claude` (210), `${HOME:-}/.claude` (19), `$HOME/.claude-n`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
