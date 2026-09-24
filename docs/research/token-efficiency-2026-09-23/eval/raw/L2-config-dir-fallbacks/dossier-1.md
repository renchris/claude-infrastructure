# Dossier 1

## Brief

Read-only. Find every place under /Users/chrisren/Development/claude-infrastructure/hooks and /Users/chrisren/Development/claude-infrastructure/bin that expands CLAUDE_CONFIG_DIR with a default fallback (for example ${CLAUDE_CONFIG_DIR:-...}). Report file:line and the fallback value for each, and the total count. Write it to /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-N/answer.md and reply with that path.

## Answer file (verbatim)

````markdown
# CLAUDE_CONFIG_DIR default-fallback expansions — hooks/ and bin/

Repo: /Users/chrisren/Development/claude-infrastructure (read-only scan, 2026-09-23).
Pattern: `${CLAUDE_CONFIG_DIR:-…}` / `:=` / `-` / `=` forms. Comments and plain assignments are excluded.

## Total: 153 expansions on 153 lines in 74 files (bin: 40, hooks: 113); no line has more than one

| Fallback value | Count |
|---|---|
| `$HOME/.claude` | 137 |
| empty string (`${CLAUDE_CONFIG_DIR:-}`) | 7 |
| `${HOME:-}/.claude` (nested) | 6 |
| `~/.claude` (literal tilde) | 3 |

Only the `:-` form occurs. There are no `:=`, bare `-`, or bare `=` forms.
Heads-up: the 3 `~/.claude` fallbacks are not tilde-expanded when the result is quoted.

## Every occurrence (file:line — fallback)

- bin/cc-backlog:3738 — `$HOME/.claude`
- bin/cc-classify:173 — `$HOME/.claude`
- bin/cc-classify:187 — `$HOME/.claude`
- bin/cc-crash-report:30 — `$HOME/.claude`
- bin/cc-custody:77 — `$HOME/.claude`
- bin/cc-digest:85 — `$HOME/.claude`
- bin/cc-digest:95 — `$HOME/.claude`
- bin/cc-discover:82 — `$HOME/.claude`
- bin/cc-do:77 — `$HOME/.claude`
- bin/cc-do:84 — `$HOME/.claude`
- bin/cc-find:63 — `$HOME/.claude`
- bin/cc-halt:16 — `$HOME/.claude`
- bin/cc-husk-sweep:71 — `$HOME/.claude`
- bin/cc-lr:68 — `$HOME/.claude`
- bin/cc-lr:79 — `$HOME/.claude`
- bin/cc-lr:88 — `$HOME/.claude`
- bin/cc-lr:97 — `$HOME/.claude`
- bin/cc-lr:109 — `$HOME/.claude`
- bin/cc-lr:422 — `$HOME/.claude`
- bin/cc-lr:759 — `$HOME/.claude`
- bin/cc-notify:201 — `$HOME/.claude`
- bin/cc-notify:591 — `$HOME/.claude`
- bin/cc-notify:712 — `$HOME/.claude`
- bin/cc-pane:200 — `$HOME/.claude`
- bin/cc-reaper:385 — `$HOME/.claude`
- bin/cc-reaper:394 — `$HOME/.claude`
- bin/cc-reaper:404 — `$HOME/.claude`
- bin/cc-reaper:414 — `$HOME/.claude`
- bin/cc-resume-layout.sh:64 — `${HOME:-}/.claude`
- bin/cc-resume-layout.sh:88 — `${HOME:-}/.claude`
- bin/cc-spawn-verify:191 — `$HOME/.claude`
- bin/cc-teardown:782 — `$HOME/.claude`
- bin/cc-wake-headless:110 — `$HOME/.claude`
- bin/desk-register:168 — `$HOME/.claude`
- bin/it2-kitty:102 — `${HOME:-}/.claude`
- bin/it2-kitty:130 — `${HOME:-}/.claude`
- bin/it2-kitty:1422 — `$HOME/.claude`
- bin/it2-wrapper:182 — `${HOME:-}/.claude`
- bin/kitty-split-launch.sh:85 — `${HOME:-}/.claude`
- bin/reso-resume-one:127 — `$HOME/.claude`
- bin/reso-resume-one:487 — `$HOME/.claude`
- hooks/activation-watch.sh:58 — `$HOME/.claude`
- hooks/agent-teams-enforce.sh:119 — `$HOME/.claude`
- hooks/agent-teams-enforce.sh:192 — `$HOME/.claude`
- hooks/agent-teams-enforce.sh:485 — `$HOME/.claude`
- hooks/anti-deference-nudge.sh:57 — `$HOME/.claude`
- hooks/anti-deference-nudge.sh:60 — `$HOME/.claude`
- hooks/anti-deference-nudge.sh:76 — `$HOME/.claude`
- hooks/anti-deference-nudge.sh:345 — `$HOME/.claude`
- hooks/backup-before-write.sh:63 — `$HOME/.claude`
- hooks/backup-before-write.sh:143 — `$HOME/.claude`
- hooks/boundary-handoff.sh:140 — `$HOME/.claude`
- hooks/boundary-handoff.sh:173 — `$HOME/.claude`
- hooks/boundary-handoff.sh:182 — `$HOME/.claude`
- hooks/boundary-handoff.sh:209 — `$HOME/.claude`
- hooks/boundary-handoff.sh:236 — `$HOME/.claude`
- hooks/boundary-handoff.sh:278 — `$HOME/.claude`
- hooks/boundary-handoff.sh:287 — `$HOME/.claude`
- hooks/boundary-handoff.sh:488 — `$HOME/.claude`
- hooks/cache-expiry-tracker.sh:8 — `$HOME/.claude`
- hooks/cache-expiry-warning.sh:28 — `$HOME/.claude`
- hooks/check-edit-boundary.sh:93 — `$HOME/.claude`
- hooks/completion-assert.sh:115 — `$HOME/.claude`
- hooks/completion-assert.sh:125 — `$HOME/.claude`
- hooks/completion-assert.sh:128 — `$HOME/.claude`
- hooks/completion-assert.sh:144 — `$HOME/.claude`
- hooks/completion-assert.sh:410 — `(empty)`
- hooks/config-mirror-assert.sh:9 — `(empty)`
- hooks/desk-brief-inject.sh:71 — `$HOME/.claude`
- hooks/dispatch-assert.sh:52 — `$HOME/.claude`
- hooks/dispatch-assert.sh:59 — `$HOME/.claude`
- hooks/dod-persist.sh:41 — `$HOME/.claude`
- hooks/goal-inert-watch.sh:146 — `$HOME/.claude`
- hooks/goal-inert-watch.sh:217 — `$HOME/.claude`
- hooks/goal-inert-watch.sh:302 — `$HOME/.claude`
- hooks/handed-off-session-guard.sh:157 — `$HOME/.claude`
- hooks/handoff-claim-assert.sh:29 — `$HOME/.claude`
- hooks/handoff-claim-assert.sh:36 — `$HOME/.claude`
- hooks/handoff-intent-nudge.sh:30 — `$HOME/.claude`
- hooks/hook-chain.sh:103 — `$HOME/.claude`
- hooks/lead-crash-watchdog.sh:1404 — `$HOME/.claude`
- hooks/lib/agent-identity.sh:107 — `(empty)`
- hooks/lib/context-econ.sh:131 — `$HOME/.claude`
- hooks/lib/context-econ.sh:191 — `$HOME/.claude`
- hooks/lib/continue-sentinel.sh:7 — `~/.claude`
- hooks/lib/continue-sentinel.sh:18 — `$HOME/.claude`
- hooks/lib/continue-sentinel.sh:25 — `$HOME/.claude`
- hooks/lib/memory-index-locate.sh:35 — `$HOME/.claude`
- hooks/lib/peer-owned.sh:161 — `$HOME/.claude`
- hooks/lib/read-before-write-parity.sh:141 — `(empty)`
- hooks/lib/session-busy.sh:111 — `(empty)`
- hooks/lib/task-helpers.sh:13 — `$HOME/.claude`
- hooks/mailbox-drain.sh:57 — `$HOME/.claude`
- hooks/mailbox-drain.sh:68 — `$HOME/.claude`
- hooks/mailbox-drain.sh:560 — `$HOME/.claude`
- hooks/mailbox-wake-arm.sh:162 — `$HOME/.claude`
- hooks/mailbox-wake-arm.sh:182 — `$HOME/.claude`
- hooks/memory-index-drain.sh:59 — `$HOME/.claude`
- hooks/memory-nudge.sh:57 — `$HOME/.claude`
- hooks/net-recover-arm.sh:123 — `$HOME/.claude`
- hooks/net-recover-arm.sh:139 — `$HOME/.claude`
- hooks/notify.sh:45 — `$HOME/.claude`
- hooks/notify.sh:198 — `$HOME/.claude`
- hooks/operator-readout.sh:192 — `$HOME/.claude`
- hooks/operator-readout.sh:199 — `$HOME/.claude`
- hooks/operator-readout.sh:397 — `$HOME/.claude`
- hooks/plan-agent-teams-default.sh:93 — `$HOME/.claude`
- hooks/pre-session-validate.sh:52 — `$HOME/.claude`
- hooks/push-critical.sh:28 — `(empty)`
- hooks/recover-inject.sh:56 — `$HOME/.claude`
- hooks/recover-inject.sh:82 — `$HOME/.claude`
- hooks/reset-hard-shadow-allow.sh:53 — `$HOME/.claude`
- hooks/reset-hard-shadow-allow.sh:55 — `$HOME/.claude`
- hooks/session-continue.sh:20 — `~/.claude`
- hooks/session-continue.sh:109 — `$HOME/.claude`
- hooks/session-continue.sh:120 — `$HOME/.claude`
- hooks/session-continue.sh:406 — `$HOME/.claude`
- hooks/session-continue.sh:413 — `$HOME/.claude`
- hooks/session-continue.sh:531 — `$HOME/.claude`
- hooks/session-continue.sh:739 — `$HOME/.claude`
- hooks/session-continue.sh:993 — `$HOME/.claude`
- hooks/session-continue.sh:1008 — `$HOME/.claude`
- hooks/session-continue.sh:1119 — `$HOME/.claude`
- hooks/session-continue.sh:1136 — `$HOME/.claude`
- hooks/session-end.sh:52 — `$HOME/.claude`
- hooks/session-register.sh:165 — `$HOME/.claude`
- hooks/session-register.sh:429 — `$HOME/.claude`
- hooks/session-save-id.sh:3 — `~/.claude`
- hooks/session-save-id.sh:23 — `$HOME/.claude`
- hooks/session-save-id.sh:32 — `$HOME/.claude`
- hooks/session-start.sh:140 — `$HOME/.claude`
- hooks/stop-failure-marker.sh:90 — `$HOME/.claude`
- hooks/stop-failure-marker.sh:121 — `$HOME/.claude`
- hooks/stop-failure-marker.sh:251 — `$HOME/.claude`
- hooks/subagent-stop.sh:51 — `$HOME/.claude`
- hooks/task-created-attrib.sh:38 — `$HOME/.claude`
- hooks/teammate-auto-shutdown.sh:118 — `(empty)`
- hooks/teammate-auto-shutdown.sh:545 — `$HOME/.claude`
- hooks/teammate-auto-shutdown.sh:994 — `$HOME/.claude`
- hooks/teammate-auto-shutdown.sh:1305 — `$HOME/.claude`
- hooks/unit-gate.sh:49 — `$HOME/.claude`
- hooks/validate-bash.sh:317 — `$HOME/.claude`
- hooks/validate-bash.sh:495 — `$HOME/.claude`
- hooks/validate-bash.sh:550 — `$HOME/.claude`
- hooks/validate-bash.sh:703 — `$HOME/.claude`
- hooks/waiting-recycle.sh:185 — `$HOME/.claude`
- hooks/waiting-recycle.sh:244 — `$HOME/.claude`
- hooks/waiting-recycle.sh:246 — `$HOME/.claude`
- hooks/waiting-recycle.sh:486 — `$HOME/.claude`
- hooks/waiting-recycle.sh:492 — `$HOME/.claude`
- hooks/waiting-recycle.sh:653 — `$HOME/.claude`
- hooks/waiting-recycle.sh:832 — `$HOME/.claude`
- hooks/waiting-recycle.sh:925 — `$HOME/.claude`

## Out of scope but related: Python equivalents (not `${…}` expansions, so not counted)

- hooks/lib/smart-bash-allowlist.py:434 — `os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(...)`
- bin/claude-accounts:4253 — `or os.path.join(HOME, ".claude")`
- bin/cc-permission-harvest:95 — `or os.path.expanduser("~/.claude")`
- bin/kitty-pane-menu:122 — `os.environ.get(..., os.path.expanduser("~/.claude"))`
- bin/cc-permission-audit:53 — `or os.path.expanduser("~/.claude")`

````

## Tool calls (7)

1. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && grep -rnoE '\\$\\{CLAUDE_CONFIG_DIR:?[-=][^}]*\\}' hooks bin | sort -t: -k1,1 -k2,2n; echo; grep -rnoE '\\$\\{CLAUDE_CONFIG_DIR:?[-`
2. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && grep -rnoE '\\$\\{CLAUDE_CONFIG_DIR:?[-=][^}]*\\}' hooks bin | cut -d: -f1,2 | sort | uniq -d; echo ---; grep -rnoE '\\$\\{CLAUDE_C`
3. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && grep -rnE \"(environ\\.get|getenv|process\\.env)[^\\n]*CLAUDE_CONFIG_DIR\" hooks bin | head -30; grep -rnE \"(environ\\.get|getenv|`
4. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && sed -n 434,436p hooks/lib/smart-bash-allowlist.py; sed -n 72,76p bin/cc-agent-harvest; mkdir -p /tmp/tokeff-eval/lean/L2-config-dir`
5. **Bash** — `{"command": "grep -E 'it2-kitty|cc-resume-layout|continue-sentinel:7|push-critical' /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-1/answer.md", "description": "Spot-check nested fallback rendering`
6. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && F=/tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-1/answer.md && python3 - \"$F\" <<'EOF'\nimport sys,subprocess,re\nf=sys.argv[1`
7. **SubagentHandback** — `{"message": "The answer is at /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-1/answer.md.\n\n**Total: 153 expansions of `${CLAUDE_CONFIG_DIR:-\u2026}`, one per line, across 74 files.** 113 are in ``
