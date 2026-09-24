# Dossier 2

## Brief

Read-only. Find every place under /Users/chrisren/Development/claude-infrastructure/hooks and /Users/chrisren/Development/claude-infrastructure/bin that expands CLAUDE_CONFIG_DIR with a default fallback (for example ${CLAUDE_CONFIG_DIR:-...}). Report file:line and the fallback value for each, and the total count. Write it to /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-N/answer.md and reply with that path.

## Answer file (verbatim)

````markdown
# CLAUDE_CONFIG_DIR default-fallback expansions in hooks/ and bin/

Repo: /Users/chrisren/Development/claude-infrastructure

Method (measured): a perl scan of every file under hooks/ and bin/ that mentions CLAUDE_CONFIG_DIR, matching `${CLAUDE_CONFIG_DIR<op><fallback>}` for op in `:-`, `-`, `:=`, `=` (only `:-` occurs). Each match is split into shell code vs. whole-line comment.

## Total

- **150** real (code) fallback expansions, on 150 distinct file:line locations (one per line), measured.
  - 137 use fallback `$HOME/.claude`
  - 6 use fallback `${HOME:-}/.claude`
  - 7 use an empty fallback (`${CLAUDE_CONFIG_DIR:-}`, a set -u guard, not a path default)
- Plus 3 occurrences in comments only (fallback `~/.claude`), not counted above. Including them: 153.
- Every one uses the `:-` operator; no `-`, `:=` or `=` forms exist.
- Several are nested as the inner default of another variable (e.g. `${SUBAGENT_STOP_STATE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/...}`); these are counted.

## Code occurrences (file:line -> fallback)

| # | file:line | fallback |
|---|-----------|----------|
| 1 | hooks/agent-teams-enforce.sh:119 | `$HOME/.claude` |
| 2 | hooks/agent-teams-enforce.sh:192 | `$HOME/.claude` |
| 3 | hooks/agent-teams-enforce.sh:485 | `$HOME/.claude` |
| 4 | hooks/plan-agent-teams-default.sh:93 | `$HOME/.claude` |
| 5 | hooks/unit-gate.sh:49 | `$HOME/.claude` |
| 6 | hooks/mailbox-drain.sh:57 | `$HOME/.claude` |
| 7 | hooks/mailbox-drain.sh:68 | `$HOME/.claude` |
| 8 | hooks/mailbox-drain.sh:560 | `$HOME/.claude` |
| 9 | hooks/config-mirror-assert.sh:9 | (empty) |
| 10 | hooks/net-recover-arm.sh:123 | `$HOME/.claude` |
| 11 | hooks/net-recover-arm.sh:139 | `$HOME/.claude` |
| 12 | hooks/dod-persist.sh:41 | `$HOME/.claude` |
| 13 | hooks/handed-off-session-guard.sh:157 | `$HOME/.claude` |
| 14 | hooks/boundary-handoff.sh:140 | `$HOME/.claude` |
| 15 | hooks/boundary-handoff.sh:173 | `$HOME/.claude` |
| 16 | hooks/boundary-handoff.sh:182 | `$HOME/.claude` |
| 17 | hooks/boundary-handoff.sh:209 | `$HOME/.claude` |
| 18 | hooks/boundary-handoff.sh:236 | `$HOME/.claude` |
| 19 | hooks/boundary-handoff.sh:278 | `$HOME/.claude` |
| 20 | hooks/boundary-handoff.sh:287 | `$HOME/.claude` |
| 21 | hooks/boundary-handoff.sh:488 | `$HOME/.claude` |
| 22 | hooks/subagent-stop.sh:51 | `$HOME/.claude` |
| 23 | hooks/backup-before-write.sh:63 | `$HOME/.claude` |
| 24 | hooks/backup-before-write.sh:143 | `$HOME/.claude` |
| 25 | hooks/activation-watch.sh:58 | `$HOME/.claude` |
| 26 | hooks/pre-session-validate.sh:52 | `$HOME/.claude` |
| 27 | hooks/hook-chain.sh:103 | `$HOME/.claude` |
| 28 | hooks/cache-expiry-tracker.sh:8 | `$HOME/.claude` |
| 29 | hooks/goal-inert-watch.sh:146 | `$HOME/.claude` |
| 30 | hooks/goal-inert-watch.sh:217 | `$HOME/.claude` |
| 31 | hooks/goal-inert-watch.sh:302 | `$HOME/.claude` |
| 32 | hooks/session-continue.sh:109 | `$HOME/.claude` |
| 33 | hooks/session-continue.sh:120 | `$HOME/.claude` |
| 34 | hooks/session-continue.sh:406 | `$HOME/.claude` |
| 35 | hooks/session-continue.sh:413 | `$HOME/.claude` |
| 36 | hooks/session-continue.sh:531 | `$HOME/.claude` |
| 37 | hooks/session-continue.sh:739 | `$HOME/.claude` |
| 38 | hooks/session-continue.sh:993 | `$HOME/.claude` |
| 39 | hooks/session-continue.sh:1008 | `$HOME/.claude` |
| 40 | hooks/session-continue.sh:1119 | `$HOME/.claude` |
| 41 | hooks/session-continue.sh:1136 | `$HOME/.claude` |
| 42 | hooks/reset-hard-shadow-allow.sh:53 | `$HOME/.claude` |
| 43 | hooks/reset-hard-shadow-allow.sh:55 | `$HOME/.claude` |
| 44 | hooks/handoff-claim-assert.sh:29 | `$HOME/.claude` |
| 45 | hooks/handoff-claim-assert.sh:36 | `$HOME/.claude` |
| 46 | hooks/check-edit-boundary.sh:93 | `$HOME/.claude` |
| 47 | hooks/recover-inject.sh:56 | `$HOME/.claude` |
| 48 | hooks/recover-inject.sh:82 | `$HOME/.claude` |
| 49 | hooks/memory-index-drain.sh:59 | `$HOME/.claude` |
| 50 | hooks/cache-expiry-warning.sh:28 | `$HOME/.claude` |
| 51 | hooks/waiting-recycle.sh:185 | `$HOME/.claude` |
| 52 | hooks/waiting-recycle.sh:244 | `$HOME/.claude` |
| 53 | hooks/waiting-recycle.sh:246 | `$HOME/.claude` |
| 54 | hooks/waiting-recycle.sh:486 | `$HOME/.claude` |
| 55 | hooks/waiting-recycle.sh:492 | `$HOME/.claude` |
| 56 | hooks/waiting-recycle.sh:653 | `$HOME/.claude` |
| 57 | hooks/waiting-recycle.sh:832 | `$HOME/.claude` |
| 58 | hooks/waiting-recycle.sh:925 | `$HOME/.claude` |
| 59 | hooks/mailbox-wake-arm.sh:162 | `$HOME/.claude` |
| 60 | hooks/mailbox-wake-arm.sh:182 | `$HOME/.claude` |
| 61 | hooks/session-start.sh:140 | `$HOME/.claude` |
| 62 | hooks/desk-brief-inject.sh:71 | `$HOME/.claude` |
| 63 | hooks/dispatch-assert.sh:52 | `$HOME/.claude` |
| 64 | hooks/dispatch-assert.sh:59 | `$HOME/.claude` |
| 65 | hooks/lead-crash-watchdog.sh:1404 | `$HOME/.claude` |
| 66 | hooks/teammate-auto-shutdown.sh:118 | (empty) |
| 67 | hooks/teammate-auto-shutdown.sh:545 | `$HOME/.claude` |
| 68 | hooks/teammate-auto-shutdown.sh:994 | `$HOME/.claude` |
| 69 | hooks/teammate-auto-shutdown.sh:1305 | `$HOME/.claude` |
| 70 | hooks/stop-failure-marker.sh:90 | `$HOME/.claude` |
| 71 | hooks/stop-failure-marker.sh:121 | `$HOME/.claude` |
| 72 | hooks/stop-failure-marker.sh:251 | `$HOME/.claude` |
| 73 | hooks/session-end.sh:52 | `$HOME/.claude` |
| 74 | hooks/session-save-id.sh:23 | `$HOME/.claude` |
| 75 | hooks/session-save-id.sh:32 | `$HOME/.claude` |
| 76 | hooks/operator-readout.sh:192 | `$HOME/.claude` |
| 77 | hooks/operator-readout.sh:199 | `$HOME/.claude` |
| 78 | hooks/operator-readout.sh:397 | `$HOME/.claude` |
| 79 | hooks/handoff-intent-nudge.sh:30 | `$HOME/.claude` |
| 80 | hooks/task-created-attrib.sh:38 | `$HOME/.claude` |
| 81 | hooks/push-critical.sh:28 | (empty) |
| 82 | hooks/anti-deference-nudge.sh:57 | `$HOME/.claude` |
| 83 | hooks/anti-deference-nudge.sh:60 | `$HOME/.claude` |
| 84 | hooks/anti-deference-nudge.sh:76 | `$HOME/.claude` |
| 85 | hooks/anti-deference-nudge.sh:345 | `$HOME/.claude` |
| 86 | hooks/memory-nudge.sh:57 | `$HOME/.claude` |
| 87 | hooks/session-register.sh:165 | `$HOME/.claude` |
| 88 | hooks/session-register.sh:429 | `$HOME/.claude` |
| 89 | hooks/validate-bash.sh:317 | `$HOME/.claude` |
| 90 | hooks/validate-bash.sh:495 | `$HOME/.claude` |
| 91 | hooks/validate-bash.sh:550 | `$HOME/.claude` |
| 92 | hooks/validate-bash.sh:703 | `$HOME/.claude` |
| 93 | hooks/lib/continue-sentinel.sh:18 | `$HOME/.claude` |
| 94 | hooks/lib/continue-sentinel.sh:25 | `$HOME/.claude` |
| 95 | hooks/lib/task-helpers.sh:13 | `$HOME/.claude` |
| 96 | hooks/completion-assert.sh:115 | `$HOME/.claude` |
| 97 | hooks/completion-assert.sh:125 | `$HOME/.claude` |
| 98 | hooks/completion-assert.sh:128 | `$HOME/.claude` |
| 99 | hooks/completion-assert.sh:144 | `$HOME/.claude` |
| 100 | hooks/completion-assert.sh:410 | (empty) |
| 101 | hooks/lib/read-before-write-parity.sh:141 | (empty) |
| 102 | hooks/lib/peer-owned.sh:161 | `$HOME/.claude` |
| 103 | hooks/lib/context-econ.sh:131 | `$HOME/.claude` |
| 104 | hooks/lib/context-econ.sh:191 | `$HOME/.claude` |
| 105 | hooks/lib/memory-index-locate.sh:35 | `$HOME/.claude` |
| 106 | bin/cc-notify:201 | `$HOME/.claude` |
| 107 | bin/cc-notify:591 | `$HOME/.claude` |
| 108 | bin/cc-notify:712 | `$HOME/.claude` |
| 109 | hooks/lib/session-busy.sh:111 | (empty) |
| 110 | hooks/notify.sh:45 | `$HOME/.claude` |
| 111 | hooks/notify.sh:198 | `$HOME/.claude` |
| 112 | bin/cc-find:63 | `$HOME/.claude` |
| 113 | bin/it2-kitty:102 | `${HOME:-}/.claude` |
| 114 | bin/it2-kitty:130 | `${HOME:-}/.claude` |
| 115 | bin/it2-kitty:1422 | `$HOME/.claude` |
| 116 | bin/cc-wake-headless:110 | `$HOME/.claude` |
| 117 | bin/cc-husk-sweep:71 | `$HOME/.claude` |
| 118 | bin/cc-do:77 | `$HOME/.claude` |
| 119 | bin/cc-do:84 | `$HOME/.claude` |
| 120 | bin/cc-backlog:3738 | `$HOME/.claude` |
| 121 | bin/cc-digest:85 | `$HOME/.claude` |
| 122 | bin/cc-digest:95 | `$HOME/.claude` |
| 123 | bin/it2-wrapper:182 | `${HOME:-}/.claude` |
| 124 | hooks/lib/agent-identity.sh:107 | (empty) |
| 125 | bin/cc-spawn-verify:191 | `$HOME/.claude` |
| 126 | bin/reso-resume-one:127 | `$HOME/.claude` |
| 127 | bin/reso-resume-one:487 | `$HOME/.claude` |
| 128 | bin/cc-reaper:385 | `$HOME/.claude` |
| 129 | bin/cc-reaper:394 | `$HOME/.claude` |
| 130 | bin/cc-reaper:404 | `$HOME/.claude` |
| 131 | bin/cc-reaper:414 | `$HOME/.claude` |
| 132 | bin/cc-lr:68 | `$HOME/.claude` |
| 133 | bin/cc-lr:79 | `$HOME/.claude` |
| 134 | bin/cc-lr:88 | `$HOME/.claude` |
| 135 | bin/cc-lr:97 | `$HOME/.claude` |
| 136 | bin/cc-lr:109 | `$HOME/.claude` |
| 137 | bin/cc-lr:422 | `$HOME/.claude` |
| 138 | bin/cc-lr:759 | `$HOME/.claude` |
| 139 | bin/desk-register:168 | `$HOME/.claude` |
| 140 | bin/cc-crash-report:30 | `$HOME/.claude` |
| 141 | bin/kitty-split-launch.sh:85 | `${HOME:-}/.claude` |
| 142 | bin/cc-resume-layout.sh:64 | `${HOME:-}/.claude` |
| 143 | bin/cc-resume-layout.sh:88 | `${HOME:-}/.claude` |
| 144 | bin/cc-halt:16 | `$HOME/.claude` |
| 145 | bin/cc-pane:200 | `$HOME/.claude` |
| 146 | bin/cc-discover:82 | `$HOME/.claude` |
| 147 | bin/cc-custody:77 | `$HOME/.claude` |
| 148 | bin/cc-classify:173 | `$HOME/.claude` |
| 149 | bin/cc-classify:187 | `$HOME/.claude` |
| 150 | bin/cc-teardown:782 | `$HOME/.claude` |

## Comment-only occurrences (not real expansions)

| file:line | fallback |
|-----------|----------|
| hooks/session-continue.sh:20 | `~/.claude` |
| hooks/session-save-id.sh:3 | `~/.claude` |
| hooks/lib/continue-sentinel.sh:7 | `~/.claude` |

## Related, but not `${...:-...}` syntax (excluded from the count)

Python equivalents with a default:
- hooks/lib/smart-bash-allowlist.py:434 -> `os.environ.get("CLAUDE_CONFIG_DIR") or ~/.claude` (via os.path.join(expanduser("~"), ".claude"))
- bin/cc-permission-harvest:95 -> `or os.path.expanduser("~/.claude")`
- bin/cc-permission-audit:53 -> `or os.path.expanduser("~/.claude")`
- bin/claude-accounts:4253 -> `or os.path.join(HOME, ".claude")`
- bin/kitty-pane-menu:122 -> `os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))`
- bin/cc-agent-harvest:72 reads the variable with no default.

````

## Tool calls (6)

1. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && grep -rnE 'CLAUDE_CONFIG_DIR[:]?[-=]' hooks bin; echo \"---\"; grep -rnE 'CLAUDE_CONFIG_DIR' hooks bin | grep -vE '\\$\\{CLAUDE_CON`
2. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && perl -ne '\nwhile (/\\$\\{CLAUDE_CONFIG_DIR(:?[-=+?])((?:[^{}]|\\{[^{}]*\\})*)\\}/g) { $c = ($_ =~ /^\\s*#/) ? \"COMMENT\" : \"CODE`
3. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && sed -n '66,74p' bin/cc-husk-sweep; grep -nE '#.*\\$\\{CLAUDE_CONFIG_DIR:' $(cut -f1 /tmp/ccd.tsv | cut -d: -f1 | sort -u) | grep -v`
4. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && sed -n '434,436p' hooks/lib/smart-bash-allowlist.py; sed -n '72,76p' bin/cc-agent-harvest; mkdir -p /tmp/tokeff-eval/lean/L2-config`
5. **Bash** — `{"command": "cd /Users/chrisren/Development/claude-infrastructure && O=/tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-2/answer.md; test -e $O && echo EXISTS && exit 1\n{\necho \"# CLAUDE_CONFIG_DIR`
6. **SubagentHandback** — `{"message": "The answer is in /tmp/tokeff-eval/lean/L2-config-dir-fallbacks/out-2/answer.md. There are **150** places in shell code under hooks/ and bin/ that expand CLAUDE_CONFIG_DIR with a default f`
