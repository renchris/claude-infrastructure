# Dossier 3

## Brief

Read-only. Find every place under /Users/chrisren/Development/claude-infrastructure/hooks and /Users/chrisren/Development/claude-infrastructure/bin that expands CLAUDE_CONFIG_DIR with a default fallback (for example ${CLAUDE_CONFIG_DIR:-...}). Report file:line and the fallback value for each, and the total count. Write it to /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-N/answer.md and reply with that path.

## Answer file (verbatim)

````markdown
# CLAUDE_CONFIG_DIR default-fallback expansions in hooks/ and bin/

Repo: /Users/chrisren/Development/claude-infrastructure (read-only scan, 2026-09-23).

## Totals (measured)

Measured with `grep -RnoE '\$\{CLAUDE_CONFIG_DIR:?[-=+?]([^{}]|\{[^{}]*\})*\}' hooks bin`, then each hit's line checked for a leading `#`.

- **143 code expansions with a non-empty fallback** (all resolve to the default config dir `~/.claude`), in 69 files:
  - 137 x `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`
  - 6 x `${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}` (set -u safe variant)
- **7 code expansions with an empty fallback** `${CLAUDE_CONFIG_DIR:-}` (set -u guard only, no real default).
- **150 code expansions in all**, one per line (no line has two), in 74 files.
- Also 3 occurrences inside comments only, fallback `~/.claude`, left out of the counts above: hooks/session-save-id.sh:3, hooks/session-continue.sh:20, hooks/lib/continue-sentinel.sh:7.
- No `:=`, `:+`, `:?` or colon-less (`-`) forms exist.
- Not counted, because they are not `${...}` expansions: Python `os.environ.get("CLAUDE_CONFIG_DIR", ...)` fallbacks to `~/.claude` at bin/kitty-pane-menu:122, bin/cc-permission-harvest:95, and hooks/lib/smart-bash-allowlist.py:434.

## Every code occurrence (file:line, fallback value)

| # | file:line | fallback |
|---|---|---|
| 1 | bin/cc-backlog:3738 | `$HOME/.claude` |
| 2 | bin/cc-classify:173 | `$HOME/.claude` |
| 3 | bin/cc-classify:187 | `$HOME/.claude` |
| 4 | bin/cc-crash-report:30 | `$HOME/.claude` |
| 5 | bin/cc-custody:77 | `$HOME/.claude` |
| 6 | bin/cc-digest:85 | `$HOME/.claude` |
| 7 | bin/cc-digest:95 | `$HOME/.claude` |
| 8 | bin/cc-discover:82 | `$HOME/.claude` |
| 9 | bin/cc-do:77 | `$HOME/.claude` |
| 10 | bin/cc-do:84 | `$HOME/.claude` |
| 11 | bin/cc-find:63 | `$HOME/.claude` |
| 12 | bin/cc-halt:16 | `$HOME/.claude` |
| 13 | bin/cc-husk-sweep:71 | `$HOME/.claude` |
| 14 | bin/cc-lr:68 | `$HOME/.claude` |
| 15 | bin/cc-lr:79 | `$HOME/.claude` |
| 16 | bin/cc-lr:88 | `$HOME/.claude` |
| 17 | bin/cc-lr:97 | `$HOME/.claude` |
| 18 | bin/cc-lr:109 | `$HOME/.claude` |
| 19 | bin/cc-lr:422 | `$HOME/.claude` |
| 20 | bin/cc-lr:759 | `$HOME/.claude` |
| 21 | bin/cc-notify:201 | `$HOME/.claude` |
| 22 | bin/cc-notify:591 | `$HOME/.claude` |
| 23 | bin/cc-notify:712 | `$HOME/.claude` |
| 24 | bin/cc-pane:200 | `$HOME/.claude` |
| 25 | bin/cc-reaper:385 | `$HOME/.claude` |
| 26 | bin/cc-reaper:394 | `$HOME/.claude` |
| 27 | bin/cc-reaper:404 | `$HOME/.claude` |
| 28 | bin/cc-reaper:414 | `$HOME/.claude` |
| 29 | bin/cc-resume-layout.sh:64 | `${HOME:-}/.claude` |
| 30 | bin/cc-resume-layout.sh:88 | `${HOME:-}/.claude` |
| 31 | bin/cc-spawn-verify:191 | `$HOME/.claude` |
| 32 | bin/cc-teardown:782 | `$HOME/.claude` |
| 33 | bin/cc-wake-headless:110 | `$HOME/.claude` |
| 34 | bin/desk-register:168 | `$HOME/.claude` |
| 35 | bin/it2-kitty:102 | `${HOME:-}/.claude` |
| 36 | bin/it2-kitty:130 | `${HOME:-}/.claude` |
| 37 | bin/it2-kitty:1422 | `$HOME/.claude` |
| 38 | bin/it2-wrapper:182 | `${HOME:-}/.claude` |
| 39 | bin/kitty-split-launch.sh:85 | `${HOME:-}/.claude` |
| 40 | bin/reso-resume-one:127 | `$HOME/.claude` |
| 41 | bin/reso-resume-one:487 | `$HOME/.claude` |
| 42 | hooks/activation-watch.sh:58 | `$HOME/.claude` |
| 43 | hooks/agent-teams-enforce.sh:119 | `$HOME/.claude` |
| 44 | hooks/agent-teams-enforce.sh:192 | `$HOME/.claude` |
| 45 | hooks/agent-teams-enforce.sh:485 | `$HOME/.claude` |
| 46 | hooks/anti-deference-nudge.sh:57 | `$HOME/.claude` |
| 47 | hooks/anti-deference-nudge.sh:60 | `$HOME/.claude` |
| 48 | hooks/anti-deference-nudge.sh:76 | `$HOME/.claude` |
| 49 | hooks/anti-deference-nudge.sh:345 | `$HOME/.claude` |
| 50 | hooks/backup-before-write.sh:63 | `$HOME/.claude` |
| 51 | hooks/backup-before-write.sh:143 | `$HOME/.claude` |
| 52 | hooks/boundary-handoff.sh:140 | `$HOME/.claude` |
| 53 | hooks/boundary-handoff.sh:173 | `$HOME/.claude` |
| 54 | hooks/boundary-handoff.sh:182 | `$HOME/.claude` |
| 55 | hooks/boundary-handoff.sh:209 | `$HOME/.claude` |
| 56 | hooks/boundary-handoff.sh:236 | `$HOME/.claude` |
| 57 | hooks/boundary-handoff.sh:278 | `$HOME/.claude` |
| 58 | hooks/boundary-handoff.sh:287 | `$HOME/.claude` |
| 59 | hooks/boundary-handoff.sh:488 | `$HOME/.claude` |
| 60 | hooks/cache-expiry-tracker.sh:8 | `$HOME/.claude` |
| 61 | hooks/cache-expiry-warning.sh:28 | `$HOME/.claude` |
| 62 | hooks/check-edit-boundary.sh:93 | `$HOME/.claude` |
| 63 | hooks/completion-assert.sh:115 | `$HOME/.claude` |
| 64 | hooks/completion-assert.sh:125 | `$HOME/.claude` |
| 65 | hooks/completion-assert.sh:128 | `$HOME/.claude` |
| 66 | hooks/completion-assert.sh:144 | `$HOME/.claude` |
| 67 | hooks/completion-assert.sh:410 | (empty) |
| 68 | hooks/config-mirror-assert.sh:9 | (empty) |
| 69 | hooks/desk-brief-inject.sh:71 | `$HOME/.claude` |
| 70 | hooks/dispatch-assert.sh:52 | `$HOME/.claude` |
| 71 | hooks/dispatch-assert.sh:59 | `$HOME/.claude` |
| 72 | hooks/dod-persist.sh:41 | `$HOME/.claude` |
| 73 | hooks/goal-inert-watch.sh:146 | `$HOME/.claude` |
| 74 | hooks/goal-inert-watch.sh:217 | `$HOME/.claude` |
| 75 | hooks/goal-inert-watch.sh:302 | `$HOME/.claude` |
| 76 | hooks/handed-off-session-guard.sh:157 | `$HOME/.claude` |
| 77 | hooks/handoff-claim-assert.sh:29 | `$HOME/.claude` |
| 78 | hooks/handoff-claim-assert.sh:36 | `$HOME/.claude` |
| 79 | hooks/handoff-intent-nudge.sh:30 | `$HOME/.claude` |
| 80 | hooks/hook-chain.sh:103 | `$HOME/.claude` |
| 81 | hooks/lead-crash-watchdog.sh:1404 | `$HOME/.claude` |
| 82 | hooks/lib/agent-identity.sh:107 | (empty) |
| 83 | hooks/lib/context-econ.sh:131 | `$HOME/.claude` |
| 84 | hooks/lib/context-econ.sh:191 | `$HOME/.claude` |
| 85 | hooks/lib/continue-sentinel.sh:18 | `$HOME/.claude` |
| 86 | hooks/lib/continue-sentinel.sh:25 | `$HOME/.claude` |
| 87 | hooks/lib/memory-index-locate.sh:35 | `$HOME/.claude` |
| 88 | hooks/lib/peer-owned.sh:161 | `$HOME/.claude` |
| 89 | hooks/lib/read-before-write-parity.sh:141 | (empty) |
| 90 | hooks/lib/session-busy.sh:111 | (empty) |
| 91 | hooks/lib/task-helpers.sh:13 | `$HOME/.claude` |
| 92 | hooks/mailbox-drain.sh:57 | `$HOME/.claude` |
| 93 | hooks/mailbox-drain.sh:68 | `$HOME/.claude` |
| 94 | hooks/mailbox-drain.sh:560 | `$HOME/.claude` |
| 95 | hooks/mailbox-wake-arm.sh:162 | `$HOME/.claude` |
| 96 | hooks/mailbox-wake-arm.sh:182 | `$HOME/.claude` |
| 97 | hooks/memory-index-drain.sh:59 | `$HOME/.claude` |
| 98 | hooks/memory-nudge.sh:57 | `$HOME/.claude` |
| 99 | hooks/net-recover-arm.sh:123 | `$HOME/.claude` |
| 100 | hooks/net-recover-arm.sh:139 | `$HOME/.claude` |
| 101 | hooks/notify.sh:45 | `$HOME/.claude` |
| 102 | hooks/notify.sh:198 | `$HOME/.claude` |
| 103 | hooks/operator-readout.sh:192 | `$HOME/.claude` |
| 104 | hooks/operator-readout.sh:199 | `$HOME/.claude` |
| 105 | hooks/operator-readout.sh:397 | `$HOME/.claude` |
| 106 | hooks/plan-agent-teams-default.sh:93 | `$HOME/.claude` |
| 107 | hooks/pre-session-validate.sh:52 | `$HOME/.claude` |
| 108 | hooks/push-critical.sh:28 | (empty) |
| 109 | hooks/recover-inject.sh:56 | `$HOME/.claude` |
| 110 | hooks/recover-inject.sh:82 | `$HOME/.claude` |
| 111 | hooks/reset-hard-shadow-allow.sh:53 | `$HOME/.claude` |
| 112 | hooks/reset-hard-shadow-allow.sh:55 | `$HOME/.claude` |
| 113 | hooks/session-continue.sh:109 | `$HOME/.claude` |
| 114 | hooks/session-continue.sh:120 | `$HOME/.claude` |
| 115 | hooks/session-continue.sh:406 | `$HOME/.claude` |
| 116 | hooks/session-continue.sh:413 | `$HOME/.claude` |
| 117 | hooks/session-continue.sh:531 | `$HOME/.claude` |
| 118 | hooks/session-continue.sh:739 | `$HOME/.claude` |
| 119 | hooks/session-continue.sh:993 | `$HOME/.claude` |
| 120 | hooks/session-continue.sh:1008 | `$HOME/.claude` |
| 121 | hooks/session-continue.sh:1119 | `$HOME/.claude` |
| 122 | hooks/session-continue.sh:1136 | `$HOME/.claude` |
| 123 | hooks/session-end.sh:52 | `$HOME/.claude` |
| 124 | hooks/session-register.sh:165 | `$HOME/.claude` |
| 125 | hooks/session-register.sh:429 | `$HOME/.claude` |
| 126 | hooks/session-save-id.sh:23 | `$HOME/.claude` |
| 127 | hooks/session-save-id.sh:32 | `$HOME/.claude` |
| 128 | hooks/session-start.sh:140 | `$HOME/.claude` |
| 129 | hooks/stop-failure-marker.sh:90 | `$HOME/.claude` |
| 130 | hooks/stop-failure-marker.sh:121 | `$HOME/.claude` |
| 131 | hooks/stop-failure-marker.sh:251 | `$HOME/.claude` |
| 132 | hooks/subagent-stop.sh:51 | `$HOME/.claude` |
| 133 | hooks/task-created-attrib.sh:38 | `$HOME/.claude` |
| 134 | hooks/teammate-auto-shutdown.sh:118 | (empty) |
| 135 | hooks/teammate-auto-shutdown.sh:545 | `$HOME/.claude` |
| 136 | hooks/teammate-auto-shutdown.sh:994 | `$HOME/.claude` |
| 137 | hooks/teammate-auto-shutdown.sh:1305 | `$HOME/.claude` |
| 138 | hooks/unit-gate.sh:49 | `$HOME/.claude` |
| 139 | hooks/validate-bash.sh:317 | `$HOME/.claude` |
| 140 | hooks/validate-bash.sh:495 | `$HOME/.claude` |
| 141 | hooks/validate-bash.sh:550 | `$HOME/.claude` |
| 142 | hooks/validate-bash.sh:703 | `$HOME/.claude` |
| 143 | hooks/waiting-recycle.sh:185 | `$HOME/.claude` |
| 144 | hooks/waiting-recycle.sh:244 | `$HOME/.claude` |
| 145 | hooks/waiting-recycle.sh:246 | `$HOME/.claude` |
| 146 | hooks/waiting-recycle.sh:486 | `$HOME/.claude` |
| 147 | hooks/waiting-recycle.sh:492 | `$HOME/.claude` |
| 148 | hooks/waiting-recycle.sh:653 | `$HOME/.claude` |
| 149 | hooks/waiting-recycle.sh:832 | `$HOME/.claude` |
| 150 | hooks/waiting-recycle.sh:925 | `$HOME/.claude` |

````

## Tool calls (5)

1. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && grep -rnE 'CLAUDE_CONFIG_DIR:?[-=]' hooks bin; echo \"---\"; grep -rnE 'CLAUDE_CONFIG_DIR' hooks bin | grep -vE 'CLAUDE_CONFIG_DIR:`
2. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && sed -n 65,75p bin/cc-husk-sweep; echo ---; find hooks bin -type l | head; echo ---; grep -RnoE '\\$\\{CLAUDE_CONFIG_DIR:?[-=+?]([^{`
3. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && O=/tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-3; while IFS=$'\\t' read -r loc val; do f=${loc%%:*}; n=${loc##*:}; line=$(sed `
4. **Bash** — `{"command": "cd /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-3 && nonempty_files=$(grep -v 'DIR:-}$' classified.tsv | grep ^code | cut -f2 | cut -d: -f1 | sort -u | wc -l | tr -d ' '); all_files=`
5. **SubagentHandback** — `{"message": "The full answer is in /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-3/answer.md. It has a table with all 150 file:line entries and the fallback value for each, sorted by path.\n\nTota`
