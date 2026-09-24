# Dossier 5

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Across bin/, hooks/ and scripts/ there are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines in 112 files, 14 of them with an empty fallback. The other fallbacks are $HOME/.claude 210, ${HOME:-}/.claude 19, $HOME/.claude-next 2 and <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)

Tree: `/tmp/tokeff-regate/f2/tree`. Scope: 572 regular files (bin 121, hooks 131, scripts 320; no symlinks).

**Answer: 246 `${CLAUDE_CONFIG_DIR:-…}` expansions on code lines, 14 with an empty fallback, in 112 distinct files.**

| metric | value |
|---|---|
| expansions (code lines) | **246** |
| empty fallbacks `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files with >=1 | **112** |

## Distinct fallback values

| fallback | count | example |
|---|---|---|
| `$HOME/.claude` | 210 | bin/cc-notify:201 |
| `${HOME:-}/.claude` | 19 | bin/it2-kitty:102 |
| *(empty)* | 14 | hooks/config-mirror-assert.sh:9 |
| `$HOME/.claude-next` | 2 | scripts/relogin-desharing-activate.sh:57 |
| `<unset>` | 1 | scripts/cloud-land-arm-diagnose.sh:120 (display string inside an `echo`) |
| **total** | **246** | |

Empty fallbacks are in 13 files: hooks/completion-assert.sh, hooks/config-mirror-assert.sh, hooks/lib/agent-identity.sh, hooks/lib/read-before-write-parity.sh, hooks/lib/session-busy.sh, hooks/push-critical.sh, hooks/teammate-auto-shutdown.sh, scripts/cloud-land-arm-diagnose.sh (2), scripts/desk-arm-live.sh, scripts/handoff-fire.sh, scripts/limit-recover/lr-ingest-verify.sh, scripts/worktree-memory-link.sh, scripts/wrap-ledger.sh.

## Method
- A Python scan walked each tree. It skipped any line whose first non-space character is `#`, and found every `${CLAUDE_CONFIG_DIR:-` on the remaining lines, including more than one per line. It pulled out each fallback by matching braces, so nested forms like `${HOME:-}/.claude` come out whole. No expansion was left unterminated.
- Cross-check with grep: 246 occurrences on non-comment lines, which matches the scan. 9 more occurrences sit on comment lines and are excluded. 113 files contain the pattern anywhere. One of them, `scripts/ship-land.sh`, has it only in comments, which leaves 112.
- Lines that begin with code and carry a trailing `# ...` count as code, as the brief defines. Occurrences inside strings or heredocs on non-comment lines are counted too, since they are still parameter expansions (for example the `<unset>` one).


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls; for d in bin hooks scripts; do echo \"$d: $(find -H $d -type f | wc -l) files, $(find -H $d -type l | wc -l) links\"; done; ls /tmp/tokeff-regate/f2/out/B02-r6/ 2>&1", "description": "Inspect tree layout and output dir"}`
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
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && python3 - <<'EOF'\nimport os,collections\nkey='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();ex={}\nfor d in ('bin','hooks','scripts'):\n  for root,ds,fs in os.walk(d):\n    for f in fs:\n      p=os.path.joi`
   → 246 14 112
210 '$HOME/.claude' bin/cc-notify:201
19 '${HOME:-}/.claude' bin/it2-kitty:102
14 '' hooks/config-mirror-assert.sh:9
2 '$HOME/.claude-next' scripts/relogin-desharing-activate.sh:57
1 '<unset>' scripts/cloud-land-arm-diagnose.sh:120
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rn --include='*' -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -oF '${CLAUDE_CONFIG_DIR:-' | wc -l; grep -rln -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rn -F '${CLAUDE_CONFIG_DIR:-' b`
   →      246
     113
       9
echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && for f in $(grep -rl -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts); do n=$(grep -F '${CLAUDE_CONFIG_DIR:-' \"$f\" | grep -vcE '^[[:space:]]*#'); [ \"$n\" = 0 ] && echo \"$f\"; done; grep -rn -F '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -vE '^[^:]+`
   → scripts/ship-land.sh
   1 hooks/completion-assert.sh
   1 hooks/config-mirror-assert.sh
   1 hooks/lib/agent-identity.sh
   1 hooks/lib/read-before-write-parity.sh
   1 hooks/lib/session-busy.sh
   1 hooks/push-critical.sh
   1 hooks/teammate-auto-shutdown.sh
   2 scripts/cloud-land-arm-diagnose.sh

5. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B02-r6/answer.md", "content": "# CLAUDE_CONFIG_DIR fallback census — bin/, hooks/, scripts/ (all depths)\n\nTree: `/tmp/tokeff-regate/f2/tree`. Scope: 572 regular files (bin 121, hooks 131, scripts 320; no symlinks).\n\n**Answer: 246 `${CLAUDE_CONFIG_DIR:-…}``
   → File created successfully at: /tmp/tokeff-regate/f2/out/B02-r6/answer.md (file state is current in your context — no need to Read it back)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r6/answer.md", "headline": "Across bin/, hooks/ and scripts/ there are 246 ${CLAUDE_CONFIG_DIR:-…} expansions on code lines in 112 files, 14 of them with an empty fallback. The other fallbacks are $HOME/.claude 210, ${HOME:-}/.claude 19, $HOME/.claude-n`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
