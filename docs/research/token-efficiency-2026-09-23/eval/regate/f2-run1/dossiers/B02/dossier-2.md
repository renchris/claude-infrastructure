# Dossier 2

## Brief
```
Census of CLAUDE_CONFIG_DIR fallbacks under /tmp/tokeff-regate/f2/tree/bin, /tmp/tokeff-regate/f2/tree/hooks and /tmp/tokeff-regate/f2/tree/scripts (all depths). Count every parameter expansion of the form ${CLAUDE_CONFIG_DIR:-<fallback>} on lines that are code, not comments (a line whose first non-space character is # is a comment). Report the total, how many have an EMPTY fallback (${CLAUDE_CONFIG_DIR:-}), and how many distinct files contain at least one. Tabulate the distinct fallback values with counts. numbers: {"expansions": N, "empty_fallbacks": N, "files": N}.
```

## Returned headline
Measured by a Perl scan that skips comment lines and matches braces, then cross-checked with grep: bin/, hooks/ and scripts/ have 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines in 112 files. 14 have an empty fallback; the fallbacks are $HOME/.claude 210, ${HOME:-}/.claude 19, empty 14, $HOME/.claude-next 2 (both inside single-quoted echo strings, printed as text rather than expanded) and <unset> 1. Another 9 expansions sit on comment lines and are not counted.

## Returned numbers
`{"expansions": 246, "empty_fallbacks": 14, "files": 112}`

## answer.md
# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)

Root: /tmp/tokeff-regate/f2/tree

## Result (measured)
- Expansions of `${CLAUDE_CONFIG_DIR:-<fallback>}` on code lines: **246**
- With an empty fallback (`${CLAUDE_CONFIG_DIR:-}`): **14**
- Distinct files containing at least one: **112**

## Distinct fallback values
| Fallback | Count |
|---|---|
| `$HOME/.claude` | 210 |
| `${HOME:-}/.claude` | 19 |
| (empty) | 14 |
| `$HOME/.claude-next` | 2 |
| `<unset>` | 1 |
| **Total** | **246** |

## Method
- Measured with a Perl scan over every text file that `grep -rlI "CLAUDE_CONFIG_DIR:-" bin hooks scripts` lists (113 files; no symlinks under the three dirs). Lines matching `^\s*#` were treated as comments and skipped. Each fallback was read up to its matching `}` with brace-depth counting, so nested forms such as `${HOME:-}/.claude` come out whole.
- Cross-check (measured): `grep -rhI '\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^\s*#' | grep -o '\${CLAUDE_CONFIG_DIR:-' | wc -l` gives 246. Across all lines, comments included, there are 255, so 9 sit on comment lines. Three of those comment-line cases use `~/.claude`, and one uses `$HOME/.claude-next` (scripts/handoff-fire.sh:10205). One file matches only on comment lines, which is why 113 files match but only 112 count.
- No code line has the expansion only after an inline `#` comment. That was checked with grep and none turned up.

## Notes on edge cases (all counted, since they are on code lines)
- Both `$HOME/.claude-next` cases are inside single-quoted `echo` strings in scripts/relogin-desharing-activate.sh (lines 57 and 60). They are printed as literal text, not expanded when the script runs.
- `<unset>` is a display default in a diagnostic echo: scripts/cloud-land-arm-diagnose.sh:120.

## Per-file counts
| File | Count |
|---|---|
| bin/cc-backlog | 1 |
| bin/cc-classify | 2 |
| bin/cc-crash-report | 1 |
| bin/cc-custody | 1 |
| bin/cc-digest | 2 |
| bin/cc-discover | 1 |
| bin/cc-do | 2 |
| bin/cc-find | 1 |
| bin/cc-halt | 1 |
| bin/cc-husk-sweep | 1 |
| bin/cc-lr | 7 |
| bin/cc-notify | 3 |
| bin/cc-pane | 1 |
| bin/cc-reaper | 4 |
| bin/cc-resume-layout.sh | 2 |
| bin/cc-spawn-verify | 1 |
| bin/cc-teardown | 1 |
| bin/cc-wake-headless | 1 |
| bin/desk-register | 1 |
| bin/it2-kitty | 3 |
| bin/it2-wrapper | 1 |
| bin/kitty-split-launch.sh | 1 |
| bin/reso-resume-one | 2 |
| hooks/activation-watch.sh | 1 |
| hooks/agent-teams-enforce.sh | 3 |
| hooks/anti-deference-nudge.sh | 4 |
| hooks/backup-before-write.sh | 2 |
| hooks/boundary-handoff.sh | 8 |
| hooks/cache-expiry-tracker.sh | 1 |
| hooks/cache-expiry-warning.sh | 1 |
| hooks/check-edit-boundary.sh | 1 |
| hooks/completion-assert.sh | 5 |
| hooks/config-mirror-assert.sh | 1 |
| hooks/desk-brief-inject.sh | 1 |
| hooks/dispatch-assert.sh | 2 |
| hooks/dod-persist.sh | 2 |
| hooks/goal-inert-watch.sh | 3 |
| hooks/handed-off-session-guard.sh | 1 |
| hooks/handoff-claim-assert.sh | 2 |
| hooks/handoff-intent-nudge.sh | 1 |
| hooks/hook-chain.sh | 1 |
| hooks/lead-crash-watchdog.sh | 1 |
| hooks/lib/agent-identity.sh | 1 |
| hooks/lib/context-econ.sh | 2 |
| hooks/lib/continue-sentinel.sh | 2 |
| hooks/lib/memory-index-locate.sh | 1 |
| hooks/lib/peer-owned.sh | 1 |
| hooks/lib/read-before-write-parity.sh | 1 |
| hooks/lib/session-busy.sh | 1 |
| hooks/lib/task-helpers.sh | 1 |
| hooks/mailbox-drain.sh | 3 |
| hooks/mailbox-wake-arm.sh | 2 |
| hooks/memory-index-drain.sh | 1 |
| hooks/memory-nudge.sh | 1 |
| hooks/net-recover-arm.sh | 2 |
| hooks/notify.sh | 2 |
| hooks/operator-readout.sh | 3 |
| hooks/plan-agent-teams-default.sh | 1 |
| hooks/pre-session-validate.sh | 1 |
| hooks/push-critical.sh | 1 |
| hooks/recover-inject.sh | 2 |
| hooks/reset-hard-shadow-allow.sh | 2 |
| hooks/session-continue.sh | 10 |
| hooks/session-end.sh | 1 |
| hooks/session-register.sh | 2 |
| hooks/session-save-id.sh | 2 |
| hooks/session-start.sh | 1 |
| hooks/stop-failure-marker.sh | 3 |
| hooks/subagent-stop.sh | 1 |
| hooks/task-created-attrib.sh | 1 |
| hooks/teammate-auto-shutdown.sh | 4 |
| hooks/unit-gate.sh | 1 |
| hooks/validate-bash.sh | 4 |
| hooks/waiting-recycle.sh | 8 |
| scripts/autonomy-sweep.sh | 3 |
| scripts/backlog-consolidation-trigger.sh | 1 |
| scripts/backlog-grouping-sweep.sh | 1 |
| scripts/banner-shots.sh | 1 |
| scripts/banner-timeline-anchor.sh | 1 |
| scripts/boot-resume-launch.sh | 4 |
| scripts/boot-resume.sh | 1 |
| scripts/cloud-land-arm-diagnose.sh | 4 |
| scripts/cloud-return-lane.sh | 1 |
| scripts/cloud-websetup-drive.sh | 1 |
| scripts/comms-strand-report.sh | 1 |
| scripts/custody-deathwatch.sh | 1 |
| scripts/delivery-verify.sh | 1 |
| scripts/desk-arm-live.sh | 2 |
| scripts/desk-invariant.sh | 1 |
| scripts/drain-brief.sh | 1 |
| scripts/drain-chain-assert.sh | 2 |
| scripts/drain-pick.sh | 1 |
| scripts/drain-recycle-fire.sh | 1 |
| scripts/handoff-fire.sh | 25 |
| scripts/kitty-drift-run.sh | 1 |
| scripts/lead-supervisor.sh | 1 |
| scripts/lib/capacity-admit.sh | 2 |
| scripts/lib/cc-common.sh | 1 |
| scripts/lib/cc-tui.sh | 2 |
| scripts/lib/spawn-presence.sh | 1 |
| scripts/limit-recover/lr-fire-resume.sh | 4 |
| scripts/limit-recover/lr-fleet.sh | 4 |
| scripts/limit-recover/lr-handoff.sh | 10 |
| scripts/limit-recover/lr-ingest-verify.sh | 1 |
| scripts/limit-recover/lr-lib.sh | 2 |
| scripts/limit-recover/lr-probe.sh | 1 |
| scripts/limit-recover/lr-reset-poller.sh | 4 |
| scripts/reap-guard.sh | 1 |
| scripts/relogin-desharing-activate.sh | 2 |
| scripts/self-path-lint.sh | 2 |
| scripts/worktree-memory-link.sh | 1 |
| scripts/wrap-ledger.sh | 1 |


## Tool calls (6) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && ls -d bin hooks scripts; ls /tmp/tokeff-regate/f2/out/B02-r4/ 2>&1; grep -rnI --include='*' -o '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | wc -l", "description": "Check dirs and rough count"}`
   → bin
hooks
scripts
ls: /tmp/tokeff-regate/f2/out/B02-r4/: No such file or directory
     254
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && find bin hooks scripts -type l | head; find bin hooks scripts -type f | wc -l; grep -rlI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l\nperl -e '\nuse strict; my (%vals,%files,$tot,$empty,$commented);\nfor my $f (split /\\n/, `grep -rlI \"CLAUDE_CONFIG`
   →      572
     113
total=246 empty=14 files=112 commented=9
210	[$HOME/.claude]
19	[${HOME:-}/.claude]
14	[]
2	[$HOME/.claude-next]
1	[<unset>]
--files
1	bin/cc-backlog
2	bin/cc-classify
1	bin/cc-crash-report
1	bin/cc-custody
2	bin/cc-digest
1	bin/cc-discover
2	bin/cc-do
1	bin/cc-find
1	bin/cc-halt
1
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rnI 'CLAUDE_CONFIG_DIR:-<unset>\\|CLAUDE_CONFIG_DIR:-\\$HOME/.claude-next' bin hooks scripts; echo ---; grep -rnI 'CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^[^:]*:[0-9]*:\\s*#' | grep '#.*CLAUDE_CONFIG_DIR:-' | head -20; echo ---; grep -rn`
   → scripts/handoff-fire.sh:10205:  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
scripts/relogin-desharing-activate.sh:57:echo '      local _cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"'
scripts/relogin-desharing-activate.sh:60:echo '      
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree && grep -rhoI '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | wc -l; grep -rhI '\\${CLAUDE_CONFIG_DIR:-' bin hooks scripts | grep -v '^\\s*#' | grep -o '\\${CLAUDE_CONFIG_DIR:-' | wc -l; grep -rhoI '\\${CLAUDE_CONFIG_DIR:-[^}]*}' bin hooks scripts | sort | un`
   →      255
     246
  15 ${CLAUDE_CONFIG_DIR:-}
   1 ${CLAUDE_CONFIG_DIR:-<unset>}
   3 ${CLAUDE_CONFIG_DIR:-~/.claude}
  19 ${CLAUDE_CONFIG_DIR:-${HOME:-}
   3 ${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}
 213 ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
5. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B02-r4 && cat > /tmp/tokeff-regate/f2/out/B02-r4/answer.md <<'EOF'\n# CLAUDE_CONFIG_DIR fallback census: bin/, hooks/, scripts/ (all depths)\n\nRoot: /tmp/tokeff-regate/f2/tree\n\n## Result (measured)\n- Expansions of `${CLAUDE_CONFIG_DIR:-<fallback>}``
   → | scripts/self-path-lint.sh | 2 |
| scripts/worktree-memory-link.sh | 1 |
| scripts/wrap-ledger.sh | 1 |
112
6. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B02-r4/answer.md", "headline": "Measured by a Perl scan that skips comment lines and matches braces, then cross-checked with grep: bin/, hooks/ and scripts/ have 246 ${CLAUDE_CONFIG_DIR:-...} expansions on code lines in 112 files. 14 have an empty fallback;`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
