# Dossier 7

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
246 non-comment ${CLAUDE_CONFIG_DIR:-…} expansions across 112 files in bin/hooks/scripts, 14 with an empty fallback; values: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02 — `${CLAUDE_CONFIG_DIR:-…}` fallback census

Scope: every file (572 regular files, 0 symlinks) under `/tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}`, all depths.
Rule: a line whose first non-space character is `#` is a comment and is excluded; every other line counts, including
occurrences inside `echo`/string literals (e.g. `scripts/relogin-desharing-activate.sh:57,60`, which print shell code).
Fallbacks were extracted with a brace-balanced parser, so nested forms like `${HOME:-}/.claude` are read whole.

## Result

| metric | value |
|---|---|
| expansions (code lines) | **246** |
| empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files containing ≥1 | **112** |
| excluded (on comment lines) | 9 |

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

Notes: both `$HOME/.claude-next` hits are inside `echo '…'` strings in `scripts/relogin-desharing-activate.sh` (lines 57, 60);
`<unset>` is a display default in `scripts/cloud-land-arm-diagnose.sh:120`. One more `$HOME/.claude-next` occurrence
(`scripts/handoff-fire.sh:10205`) is on a comment line and excluded.

Heaviest files: `scripts/handoff-fire.sh` 25, `hooks/session-continue.sh` 10, `scripts/limit-recover/lr-handoff.sh` 10,
`hooks/boundary-handoff.sh` 8, `hooks/waiting-recycle.sh` 8, `bin/cc-lr` 7.

Cross-check: an independent `grep -o` pass over non-comment lines also counts 246; `grep -l` on lines with a leading
non-comment char gives 111, plus `bin/cc-husk-sweep:71` whose line *begins* with the expansion = 112.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; find bin hooks scripts -type l | wc -l; find bin hooks scripts -type f | wc -l; mkdir -p /tmp/tokeff-gate/f2/out/B02-r3; ls /tmp/tokeff-gate/f2/out/B02-r3", "description": "Inspect tree and prepare output dir"}`
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
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && python3 - <<'EOF'\nimport os,re,collections\ntok='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=set();vals=collections.Counter();perfile=collections.Counter();skipped_comment=0;bad=0\nfor root in ['bin','hooks','scripts']:\n    for dp,dn,fn in os.walk(root):`
   → total 246 empty 14 files 112 comment_occ 9 unterminated 0
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
1 bin/
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && /usr/bin/grep -rhoE '^[^#]*' bin hooks scripts | /usr/bin/grep -v '^[[:space:]]*#' | /usr/bin/grep -o '\\${CLAUDE_CONFIG_DIR:-' | wc -l; /usr/bin/grep -rn 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; /usr/bin/gr`
   →      246
scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:ech
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && /usr/bin/grep -rlE '^[[:space:]]*[^#[:space:]]?.*\\$\\{CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; /usr/bin/grep -rnE '^[[:space:]]*\\$\\{CLAUDE_CONFIG_DIR:-' bin hooks scripts", "description": "Resolve file-count discrepancy"}`
   →      113
bin/cc-husk-sweep:71:${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh
5. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B02-r3/answer.md <<'EOF'\n# B02 — `${CLAUDE_CONFIG_DIR:-…}` fallback census\n\nScope: every file (572 regular files, 0 symlinks) under `/tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}`, all depths.\nRule: a line whose first non-space character is `#` is a comm`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r3/answer.md", "headline": "246 non-comment ${CLAUDE_CONFIG_DIR:-…} expansions across 112 files in bin/hooks/scripts, 14 with an empty fallback; values: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1.", "numbers": {"exp`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
