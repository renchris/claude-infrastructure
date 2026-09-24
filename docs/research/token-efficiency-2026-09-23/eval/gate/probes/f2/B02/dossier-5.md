# Dossier 5

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
bin/, hooks/ and scripts/ contain 246 code-line expansions of ${CLAUDE_CONFIG_DIR:-...} across 112 files, and 14 of them have an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 and <unset> 1. I measured this with a brace-matching Python walk and cross-checked it with grep: 253 matching lines, minus 9 comment lines, plus 2 lines that hold two expansions each.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# B02: census of CLAUDE_CONFIG_DIR fallbacks (bin/, hooks/, scripts/ under /tmp/tokeff-gate/f2/tree)

## Answer
- **Expansions `${CLAUDE_CONFIG_DIR:-<fallback>}` on code lines: 246**
- **Empty fallback `${CLAUDE_CONFIG_DIR:-}`: 14**
- **Distinct files with at least one: 112**

How I measured it: an in-memory Python walk (`os.walk`) over bin, hooks and scripts at every depth. It finds each
`${CLAUDE_CONFIG_DIR:-` and matches braces to its closing `}`, so nested fallbacks such as
`${HOME:-}/.claude` are read whole. A line counts as a comment when its first non-space
character is `#`. I cross-checked with grep: 253 matching lines, minus 9 comment lines, gives 244 code lines.
Two of those lines hold two expansions each (scripts/handoff-fire.sh lines 8471 and 10052), so the total is 246.
The tree has no symlinks (checked with find -type l).

## Distinct fallback values
| fallback | count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| `` (empty) | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **total** | **246** |

File types: 208 of the expansions are in `.sh` files and 38 are in bin/ scripts with no extension (all bash, going by their shebangs).

## Excluded (comment lines)
9 expansions sit on comment lines in 7 files and are not counted:
hooks/session-save-id.sh:3, hooks/session-continue.sh:20, hooks/lib/continue-sentinel.sh:7,
scripts/handoff-fire.sh:10205, scripts/self-path-lint.sh:154, scripts/ship-land.sh:2170/2179/2181,
scripts/cloud-land-arm-diagnose.sh:20. Several of these use the fallback `~/.claude`, which appears only in comments.
scripts/ship-land.sh has no code-line expansion, so it is not among the 112 files.

## Caveats (counted under the brief's literal rule)
- Three expansions sit inside single-quoted strings, so the current shell does not expand them:
  - scripts/relogin-desharing-activate.sh:57 and :60 (`echo '...${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}...'`). These are the only 2 `$HOME/.claude-next` fallbacks.
  - scripts/cloud-land-arm-diagnose.sh:171. Here a child `zsh -lc` does expand it (fallback empty).
- The `<unset>` fallback (scripts/cloud-land-arm-diagnose.sh:120) is a display default inside an echo, not a path.
- No code line has an expansion that sits only in a trailing `#` comment (checked by grep).

## Files with the most expansions
scripts/handoff-fire.sh 25; hooks/session-continue.sh 10; scripts/limit-recover/lr-handoff.sh 10;
hooks/boundary-handoff.sh 8; hooks/waiting-recycle.sh 8; bin/cc-lr 7; hooks/completion-assert.sh 5.
Of the 112 files, 23 are in bin/, 51 in hooks/ and 38 in scripts/ (grep, counting unique file names per folder).


## Tool calls (8) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls; ls -d bin hooks scripts; mkdir -p /tmp/tokeff-gate/f2/out/B02-r8; ls -la /tmp/tokeff-gate/f2/out/B02-r8; grep -rn --binary-files=text 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rln 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; find bin h`
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
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && python3 - <<'EOF'\nimport os,re,collections\nroots=['bin','hooks','scripts']\ntot=0;empty=0;files=collections.Counter();vals=collections.Counter();comm=0;commfiles=set();odd=[]\nexts=collections.Counter()\nfor r in roots:\n  for dp,dn,fn in os.walk(r):\n  `
   → total 246 empty 14 files 112 comment-occ 9 commentfiles 7
odd [('scripts/ship-land.sh', 2179, '# SET, NOT UNSET, and that is measured too. For the 65 readers spelling `${CLAUDE_CONFIG_DIR:-')]
Counter({'.sh': 208, '': 38})
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<u
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rn 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v -E '^[^:]+:[0-9]+:\\s*#' | grep -E \"CLAUDE_CONFIG_DIR:-(\\}|<unset>|\\\\\\$HOME/.claude-next)|\\\\\\\\\\\\\\$\\{CLAUDE_CONFIG_DIR|'[^']*\\\\\\$\\{CLAUDE_CONFIG_DIR\" | cut -c1-250; echo ---; grep `
   → hooks/config-mirror-assert.sh:9:cfg="${CLAUDE_CONFIG_DIR:-}"
hooks/lib/read-before-write-parity.sh:141:  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then printf '%s' "$CLAUDE_CONFIG_DIR"
hooks/lib/session-busy.sh:111:  printf '%s' "$HOME/.claude:$HOME/.claude-next:$HOME/.claude-tertiary:$HOME/.claude-quater
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnE '[^$]#[^!]*\\$\\{CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | cut -c1-220; echo ---; grep -rnE 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | awk -F'CLAUDE_CONFIG_DIR:-' 'NF>2' | wc -l", "d`
   → ---
       2
5. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rnE 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -vE '^[^:]+:[0-9]+:\\s*#' | awk -F'CLAUDE_CONFIG_DIR:-' 'NF>2' | cut -c1-200; grep -rn 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -cE '^[^:]+:[0-9]+:\\s*#'", "description": "Show lines with two e`
   → scripts/handoff-fire.sh:8471:    if [ "$SC_REMOTE_SOURCE" = 1 ]; then SC_TS_ROOTS="$CC_PROJECTS_DIRS"; _sc_local_cfg=""; else SC_TS_ROOTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"; _sc_local_cfg=
scripts/handoff-fire.sh:10052:    hf_transplant_evidence "$RCY_TS_SID" "${CLAUDE_CONFIG_DIR:-$HOME/
6. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B02-r8/answer.md <<'EOF'\n# B02: census of CLAUDE_CONFIG_DIR fallbacks (bin/, hooks/, scripts/ under /tmp/tokeff-gate/f2/tree)\n\n## Answer\n- **Expansions `${CLAUDE_CONFIG_DIR:-<fallback>}` on code lines: 246**\n- **Empty fallback `${CLAUDE_CONFIG_DIR:-}`:`
   → bin       23
hooks       51
scripts       38
7. `Bash: {"command": "sed -i '' 's|Of the 112 files, 21 are in bin/, 50 in hooks/ and 41 in scripts/.|Of the 112 files, 23 are in bin/, 51 in hooks/ and 38 in scripts/ (grep, counting unique file names per folder).|' /tmp/tokeff-gate/f2/out/B02-r8/answer.md && tail -2 /tmp/tokeff-gate/f2/out/B02-r8/answer.md`
   → hooks/boundary-handoff.sh 8; hooks/waiting-recycle.sh 8; bin/cc-lr 7; hooks/completion-assert.sh 5.
Of the 112 files, 23 are in bin/, 51 in hooks/ and 38 in scripts/ (grep, counting unique file names per folder).
8. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r8/answer.md", "headline": "bin/, hooks/ and scripts/ contain 246 code-line expansions of ${CLAUDE_CONFIG_DIR:-...} across 112 files, and 14 of them have an empty fallback. By fallback: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
