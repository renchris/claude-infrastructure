# Dossier 7

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-gate/f2/tree/bin, /tmp/tokeff-gate/f2/tree/hooks and /tmp/tokeff-gate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
On code lines under bin, hooks and scripts there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2, <unset> 1 (measured with a python3 brace-matching walk; 9 more on comment lines were left out).

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}, all depths

On code lines (lines whose first non-space character is not `#`) there are **246** `${CLAUDE_CONFIG_DIR:-<fallback>}` expansions. **14** of them have an empty fallback (`${CLAUDE_CONFIG_DIR:-}`), and they appear in **112** distinct files.

| Fallback value | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| (empty) | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

Method (measured): I ran an inline python3 walk over all regular files. It counts every occurrence on each line, including several on one line, and reads the fallback up to the matching `}` using brace-depth matching. Comment lines were skipped: they hold 9 more occurrences, and one file (`hooks/session-continue.sh`) has matches only in comments. With it, `grep -c` finds 113 files; the code-only count is 112. `scripts/settings-dedup-stop.sh` is flagged as binary data, but `grep -a` finds no match in it. There are no symlinks in the three trees. The single `<unset>` is a literal display default in `scripts/cloud-land-arm-diagnose.sh:120` (an `echo` line), so it counts as code.


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-gate/f2/out/B02-r10/ 2>&1; grep -rn --binary-files=without-match -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l", "description": "Check tree dirs and raw match count"}`
   → bin
hooks
scripts
     253
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && find bin hooks scripts -type l | head; python3 - <<'EOF'\nimport os,collections\nkey='${CLAUDE_CONFIG_DIR:-'\ntot=0;empty=0;files=set();vals=collections.Counter();commented=0;binskip=[]\nfor root in ['bin','hooks','scripts']:\n  for dp,dn,fn in os.walk(roo`
   → total 246 empty 14 files 112 commented 9 binskip ['scripts/settings-dedup-stop.sh']
210 '$HOME/.claude'
19 '${HOME:-}/.claude'
14 ''
2 '$HOME/.claude-next'
1 '<unset>'
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -an -F '${CLAUDE_CONFIG_DIR:-' scripts/settings-dedup-stop.sh | cat -v | head; file scripts/settings-dedup-stop.sh; grep -rn -F 'CLAUDE_CONFIG_DIR:-<unset>' bin hooks scripts; grep -rn -F -c '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v ':0$' | `
   → scripts/settings-dedup-stop.sh: Bourne-Again shell script executable (binary data)
scripts/cloud-land-arm-diagnose.sh:120:echo "host: $(uname -s) · HOME=$HOME · CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
     113
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree && grep -rn -F '${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -E '^[^:]+:[0-9]+:[[:space:]]*#'", "description": "List comment-line matches"}`
   → hooks/session-continue.sh:20:# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
scripts/self-path-lint.sh:154:#       (`for cand in "$(dirname "$0")/../lib/x" \ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/x"; do`)
hooks/session-save-id.sh:3:# Writes to (pe
5. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B02-r10 && cat > /tmp/tokeff-gate/f2/out/B02-r10/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: /tmp/tokeff-gate/f2/tree/{bin,hooks,scripts}, all depths\n\nOn code lines (lines whose first non-space character is not `#`) there are **246** `${CLA`
   → (Bash completed with no output)
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B02-r10/answer.md", "headline": "On code lines under bin, hooks and scripts there are 246 ${CLAUDE_CONFIG_DIR:-...} expansions in 112 files, and 14 have an empty fallback. By fallback value: $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-nex`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
