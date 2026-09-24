# Dossier 9

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured by a brace-matching Python scan and checked with grep: bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, across 112 files, and 14 of them have an empty fallback. The fallbacks are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1. A further 9 expansions sit on comment lines and are excluded.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02-r1: census of CLAUDE_CONFIG_DIR fallback expansions

Scope: every regular file under `/tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}`, all depths. There are 572 files and no symlinks.
Rule applied: count each `${CLAUDE_CONFIG_DIR:-<fallback>}` on a code line, including several on one line. A line whose first non-space character is `#` is a comment and is skipped.
Method (measured): a read-only in-memory Python scan found each `${CLAUDE_CONFIG_DIR:-` and matched braces to find where it ends, so nested fallbacks such as `${HOME:-}/.claude` are captured whole. I checked the result with `grep -rF`.

## Result

| metric | value |
|---|---|
| expansions on code lines | **246** |
| of which have an empty fallback `${CLAUDE_CONFIG_DIR:-}` | **14** |
| distinct files with at least one code-line expansion | **112** |

## Distinct fallback values

| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| *(empty)* | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

## Per root (measured)

| root | expansions | files |
|---|---|---|
| bin | 41 | 23 |
| hooks | 110 | 51 |
| scripts | 95 | 38 |
| **total** | **246** | **112** |

## Cross-checks (measured with grep)

- The raw count of `${CLAUDE_CONFIG_DIR:-` with comments included is 255, which is 246 on code lines plus 9 on comment lines.
- The raw file count with comments included is 113. The one extra file is `scripts/ship-land.sh`, where the pattern appears only in `#` comments.
- None of the code lines has the expansion only inside a trailing comment (`code # ...${CLAUDE_CONFIG_DIR:-...}`).
- No other forms appear: `${CLAUDE_CONFIG_DIR-...}` and `${CLAUDE_CONFIG_DIR:=...}` have zero hits.

## Empty-fallback sites (14)

- hooks/config-mirror-assert.sh:9
- hooks/completion-assert.sh:410
- hooks/teammate-auto-shutdown.sh:118
- hooks/push-critical.sh:28
- hooks/lib/agent-identity.sh:107
- hooks/lib/read-before-write-parity.sh:141
- hooks/lib/session-busy.sh:111
- scripts/worktree-memory-link.sh:82
- scripts/wrap-ledger.sh:1145
- scripts/handoff-fire.sh:10105
- scripts/desk-arm-live.sh:164
- scripts/cloud-land-arm-diagnose.sh:171 (inside a single-quoted `zsh -lc` argument, so the child shell expands it)
- scripts/cloud-land-arm-diagnose.sh:175
- scripts/limit-recover/lr-ingest-verify.sh:320

## Caveats

- The rule is purely textual, so it counts some code lines where the shell does not actually expand the text at runtime:
  - The 2 `$HOME/.claude-next` hits are both in `scripts/relogin-desharing-activate.sh:57,60`. They sit inside single-quoted `echo '...'` strings that print shell-rc text.
  - The `<unset>` hit, `scripts/cloud-land-arm-diagnose.sh:120`, is a real expansion inside a diagnostic `echo`.
- Commented examples such as `${CLAUDE_CONFIG_DIR:-~/.claude}` in hooks/session-continue.sh and similar files are excluded by the rule, so `~/.claude` does not appear as a fallback value.


## Tool calls (7) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; ls out 2>/dev/null; ls -la /tmp/tokeff-gate/f2/out/ 2>/dev/null | head; find bin hooks scripts -type f | wc -l; find bin hooks scripts -type l | wc -l", "description": "Inspect tree layout and output dir"}`
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
2. `Bash: {"command": "ls -d /tmp/tokeff-gate/f2/out/B02-r1; cd /tmp/tokeff-gate/f2/tree && python3 - <<'EOF'\nimport os,collections\nroots=['bin','hooks','scripts']\ncnt=collections.Counter(); files=collections.Counter(); total=0; empty=0; nonutf=0; comment_hits=0\nneedle='${CLAUDE_CONFIG_DIR:-'\nfor r in ro`
   → /tmp/tokeff-gate/f2/out/B02-r1
total 246 empty 14 files 112 comment_hits 9
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnF -- '${CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; echo ---; grep -rhoF -- '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rlF -- '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; echo ---; grep -rnE -- '^\\s*#.*\\$\\{CLAUDE_CONFIG_DI`
   → scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
---
     255
     113
---
hooks/session-continue.sh:20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
hooks/session-save-i
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnF -- '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | grep -E '\\s#.*\\$\\{CLAUDE_CONFIG_DIR:-' | head; echo ---; grep -rnF -- '${CLAUDE_CONFIG_DIR:-}' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | cut -c1-160; ec`
   → ---
hooks/config-mirror-assert.sh:9:cfg="${CLAUDE_CONFIG_DIR:-}"
hooks/completion-assert.sh:410:    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && roots+=( "${CLAUDE_CONFIG_DIR}/teams" )
hooks/teammate-auto-shutdown.sh:118:[[ -n "${CLAUDE_CONFIG_DIR:-}" && -d "${CLAUDE_CONFIG_DIR}/teams" ]] && _team_roots+=("${
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && for r in bin hooks scripts; do e=$(grep -rnF -- '${CLAUDE_CONFIG_DIR:-' $r | grep -vE '^[^:]+:[0-9]+:\\s*#' | cut -d: -f3- | grep -oF '${CLAUDE_CONFIG_DIR:-' | wc -l); f=$(grep -rnF -- '${CLAUDE_CONFIG_DIR:-' $r | grep -vE '^[^:]+:[0-9]+:\\s*#' | cut -d: -`
   → bin       41       23
hooks      110       51
scripts       95       38
comment-only: scripts/ship-land.sh
   2 bin/cc-resume-layout.sh
   2 bin/it2-kitty
   1 bin/it2-wrapper
   1 bin/kitty-split-launch.sh
   2 scripts/boot-resume-launch.sh
   1 scripts/cloud-websetup-drive.sh
   1 scripts/drain-br
6. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B02-r1/answer.md", "content": "# B02-r1: census of CLAUDE_CONFIG_DIR fallback expansions\n\nScope: every regular file under `/tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}`, all depths. There are 572 files and no symlinks.\nRule applied: count each `${CLAUDE_CONF`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B02-r1/answer.md (file state is current in your context — no need to Read it back)
7. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r1/answer.md", "headline": "Measured by a brace-matching Python scan and checked with grep: bin, hooks and scripts contain 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines, across 112 files, and 14 of them have an empty fallback. The fallbacks are $`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
