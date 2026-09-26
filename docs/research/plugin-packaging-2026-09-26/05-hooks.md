# 05 — Which hooks could ship as standalone plugin hooks

Scope: `/Users/chrisren/Development/claude-infrastructure/hooks/`. It holds 93 hook files (90 `.sh`, 3 `.py`); the "~96" count also took in `lib/`, `tests/` and `__pycache__`. Registrations were read from the live `~/.claude*/settings.json` (5 config dirs) and from `settings-templates/settings.example.json`. Nothing in the repo was modified.

**Headline.** About 12 hooks have a portable core that is useful to other people. Six of them are T1 today, meaning they need only path and message edits: bash-output-offload, backup-before-write, git-worktree-guard, rm-safe-allowlist, pr-gate and unit-gate. The larger guards are T2. Each has a portable kernel wrapped in arms that only work on this fleet, so it needs surgery rather than copying: validate-bash, agent-teams-enforce, enforce-email-formatting, anti-deference-nudge and the session-continue kernel. The Session Close stack cannot ship as it stands. completion-assert and operator-readout need `scripts/wrap-ledger.sh` (2,587 lines), which reads the fleet's backlog, decision, DoD and 4-account stores. A smaller "close-integrity" plugin is possible if a git-only core is split out of wrap-ledger.

Tier key:
- **T1**: ships after mechanical edits. State paths move to `${CLAUDE_PLUGIN_DATA}` and fleet message text is removed. No fleet libs or binaries are needed.
- **T2**: a portable kernel inside fleet arms. It needs surgery: strip arms, vendor libs, and move hardcoded config to `userConfig` / `CLAUDE_PLUGIN_OPTION_<KEY>`.
- **T3**: welded to the fleet (backlog, decisions, mailbox, registry, 4 accounts, iTerm/kitty, launchd).

---

## (a) Top candidates

Latency figures come from the measured block in `hooks/hook-chain.sh:6-8,38-40` (load 0.75/core, 2026-07-31). The timeout is the one registered in live `~/.claude/settings.json`.

| # | hook | event + matcher (timeout) | what it guards | dependency closure | portability blockers (file:line) | tier | value 1-5 |
|---|---|---|---|---|---|---|---|
| 1 | `bash-output-offload.sh` (75 L) | PostToolUse `^Bash$` (10 s) | Bash stdout over 8,000 chars is saved to a file; the model gets the first 40 lines, the last 60, and up to 30 failure-looking lines from the hidden middle, via `updatedToolOutput`. Deliberate reads (cat/sed/grep/git show…) are skipped. | 0 libs, 0 bins. `python3` stdlib (inline). Env: `CC_BASH_OFFLOAD`, `CC_BASH_OFFLOAD_CHARS`, `CC_BASH_OFFLOAD_DIR`. State: `${TMPDIR}/claude-bash-output` | Output dir is never reaped (`:27`); move it to `${CLAUDE_PLUGIN_DATA}` and add a TTL sweep. Requires `python3` (`:23`). No fleet references. | **T1** | **5** |
| 2 | `backup-before-write.sh` (207 L) | PreToolUse `Write\|Edit\|MultiEdit` (10 s) | Takes a timestamped backup before a Write overwrites a file (keeps 10 per source) and injects a "use Edit, integrate" warning. On an Edit of a plan file it injects the plan rules. | Optional `lib/memory-index-budget.sh` (386 L), which sources `memory-index-measure.sh` (182 L) (`:61-63`). Needs `jq`, which fails open if missing. | `BACKUP_DIR=$HOME/.claude/backups` `:116`; identity-file backup dir `:143`. Plan rules are fleet doctrine (Phase 0 / execution locus) `:85-95`. Restore pointer `~/.claude/scripts/restore-file.sh` `:191`: vendor it (138 non-blank lines). The MEMORY.md budget arm (`:64-78`) is fleet-only; drop it. | **T1** | **5** |
| 3 | `validate-bash.sh` (2,288 L) | PreToolUse `Bash` (10 s; measured 79 ms, 94→142 ms when sourced) | Blocks sudo rm and fork bombs, catastrophic `rm` decided on argv (`:820-904`), `--no-verify` / `commit -n` / `--no-gpg-sign` / `git add -f` (`:1145-1164`), and `git clean -x` (ask). Decides `git reset --hard` / `stash drop` / `restore` on live repo state (`:1765-1925`). Unscoped `pkill`/`killall` gate (`:905-1140`). | `lib/is-true-flag.sh` (949 L, the shlex flag and heredoc stripper) and `lib/kill-selection.py` (328 L) are core. The fleet arms need `lib/goal-state.sh` 145, `cc-interactive.sh` 122, `mailbox-pending.sh` 959, `scripts/lib/spawn-lineage.sh` 215, `scripts/lib/worker-claim-gate.sh` 513, and bins `cc-await-ping` and `cc-permission-harvest`. Libs resolve script-relative first (`:80`). | Fleet arms: /goal guard `:191-346`; pane-spawn admission keyed on `it2-kitty\|handoff-fire.sh…` `:487`; duplicate-worker bash-write `:570-723`; FF-gate on `$HOME/Development/claude-infrastructure` `:1400` (inert elsewhere, dead weight); PERMHARVEST `:1537-1761`. Messages cite "CLAUDE.md critical rule #2" `:1146-1162`. Decision log `$HOME/.claude/logs/validate-bash-decisions.jsonl` `:101`; kill-gate log `:1046`. | **T2** (the core is roughly lines 724-1164 + 1763-2288 plus 2 libs) | **5** |
| 4 | `git-worktree-guard.sh` (146 L) | PreToolUse `Bash` (10 s; 33 ms) | Refuses `git worktree remove` when a live process has its cwd there or has files open under it, and refuses `git branch -D` on a branch that has a worktree | 0 libs. `jq` optional (grep fallback `:30`). `lsof`, `pgrep`, `git` | `pgrep -f claude` `:111` matches any argv containing "claude". `/usr/sbin/lsof` is the macOS path with a PATH fallback `:99-102`. It fails **closed** when lsof is missing `:103-109`, which blocks every worktree remove in slim Linux containers. | **T1** | **4** |
| 5 | `rm-safe-allowlist.sh` (146 L) | PreToolUse `Bash` (5 s; 25 ms) | Auto-allows a single-clause `rm` of regenerable targets (node_modules, dist, .next, …, `/tmp/*`). Never touches `.git`, globs, `..` or compound commands. | 0 libs. `jq` | Abstain log `$HOME/.claude/logs/validate-bash-unclear.log` `:39-42`. The **trust** problem: a plugin that emits `allow` skips the user's prompt (`:137-141`). | **T1** | **4** |
| 6 | `smart-bash-allowlist.sh` (138 L) + `lib/smart-bash-allowlist.py` (1,167 L) | PreToolUse `Bash` (5 s) | Splits a compound command into segments and allows it only if every segment is whitelisted, no segment hits the user's live `permissions.ask/deny`, and no danger pattern matches. Can never return `deny`. | 1 py lib, stdlib only (`json os re sys`). `exec python3` `:138` | Reads the permission fence from `$CLAUDE_CONFIG_DIR/settings.json` plus the cwd's `.claude/settings{,.local}.json` only (`lib:431-440`). It misses user `settings.local.json`, managed policy and other plugins' rules. The lib's own header says a PreToolUse `allow` "BYPASSES the permission system completely" (`lib:11-14`), so a missing fence rule means an over-allow. Whitelist rationale comes from the fleet's permission-archive (`lib:5-8`). | **T2** | **5** |
| 7 | `pr-gate.sh` (210 L) | PreToolUse `Bash` (no timeout set → harness default) | `gh pr create/edit`: asks when the repo has one author and no reviewer is named. Denies a body whose first line is a label or bullet, or that runs over 400 words. | 0 libs. `python3`, `git log -500` (`:95`). Env `CC_PR_PYRAMID`, `CC_PR_MAX_WORDS`, `PR_REVIEWER` | None fleet-bound. The policy is opinionated (Minto). Register it with an explicit timeout. | **T1** | **3** |
| 8 | `unit-gate.sh` (173 L) | PreToolUse `*`. Not registered in any of the 5 live settings; staged by `migrations/0024` | Emergency brake: if `$CFG/HALT` or `HALT.d/<sid\|agent_id>` exists, every tool call is denied. Writes a halted stamp and a first-seen unit ledger. Uses only bash builtins, no forks. | 0 libs, no `jq` | Paths under `$CLAUDE_CONFIG_DIR` `:49,124-126,133-144` should move to `${CLAUDE_PLUGIN_DATA}`. The deny text names `cc-halt` `:171`; the producer `bin/cc-halt` would need to ship as a plugin `bin/`. | **T1** | **4** |
| 9 | `teammate-checkpoint.sh` (381 L) | PostToolUse (all tools, 10 s, every 5th call) + Stop (10 s) | Uses git plumbing (read-tree / write-tree / commit-tree) to snapshot the dirty tree to `refs/checkpoints/<member>/<ts>` and `refs/wip/<member>/LAST` without touching the index or running git hooks | 0 libs. `jq`, `git` | State `$HOME/.claude/watchdog` and a log `:42-43`. Path conventions `/tmp/wt-*` and `$HOME/Development/.worktrees/*` `:100-101` are harmless, since any git tree qualifies `:104`. It **writes refs into the user's repos**, so it has to be opt-in. | **T1** | **4** |
| 10 | `task-quality-gate.sh` (333 L) | TaskCompleted (120 s) | Runs `tsc --noEmit` in the teammate's worktree and uses exit 2 to reject task completion when there are errors | 0 libs. `git`, `npx`, **GNU `timeout`** | `timeout 60` / `timeout 120` `:270,311` do not exist on stock macOS; the script relies on the Homebrew PATH it appends at `:21`. Worktree lookup `/tmp/worktree-*` `:87`. Repo-specific bats arm `~:200-290`. Log `$HOME/.claude/logs` `:31`. | **T2** | **4** |
| 11 | `enforce-email-formatting.py` (1,305 L) | PreToolUse `mcp__ms365__send-mail\|reply-mail-message\|…` (10 s) | R1: compose-and-send tools are denied outright, with no override. R1b: compose and send-draft may not happen in the same human turn (decided from the transcript). R2: the call must name a mailbox, and `from` must belong to it. R3: wall-of-text, lost-quote and detached-thread checks. R4: received mail must have been listed within 10 min of a draft write. | Stdlib only. The `hooks/lib/*.sh` references are comments (the predicate is re-implemented at `:628-700`). Marker in `tempfile.gettempdir()` `:296-299`. Env `CLAUDE_EMAIL_FORMAT_GATE_DISABLED`, `CC_MS365_FRESHNESS_MIN` | **The operator's email addresses are hardcoded in `MAILBOXES` `:353-366`** (personal data in a public repo); this must become `userConfig`. Tool names are tied to one MCP server's `mcp__ms365__*` naming `:124-175`. Recipe text points at `$HOME/.claude/bin/ms365-compose-body.py` / `ms365-reply-splice.py` `:499,528,1128,1153,1198`. | **T2** | **4** (R1 applies to any irreversible-send tool) |
| 12 | `agent-teams-enforce.sh` (746 L) | PreToolUse `Agent` (5 s) | Eight arms: duplicate-worker lease; machine-capacity admission; **per-session spawn budget (60) + depth cap (2)** `:268-460`; lineage generation cap; model allowlist; **brief line caps 150 warn / 250 deny** `:609-660`; named-research advisory; blocks background subagents from writing code `:691-737` | Portable part: 0 libs, `jq`. Fleet arms: `scripts/lib/worker-claim-gate.sh` 513, `capacity-admit.sh` 1,536, `spawn-lineage.sh` 215 (`:118,191,495`), `yq` | Budget state `$HOME/.claude/autonomy/spawn-budget` + IDL `:382-383`. **For anyone without `~/.claude/model-config.yaml`, the model allowlist falls back to `claude-opus-4-8` (`:535-536`), so every teammate spawned with `model: sonnet/haiku` is DENIED (`:552-563`).** PATH appends `$HOME/.claude/bin` `:18`. | **T2** (kernel about 150 L) | **4** |
| 13 | `frontier-spawn-gate.sh` (153 L) | PreToolUse `Agent` (5 s) | Per-session cap on spawns of the frontier model, and a refusal when the frontier window is closed | 0 libs. `jq` optional. Counter `${TMPDIR}/frontier-gate-<sid>.count` | Config `$HOME/.claude/model-config.yaml` (`FRONTIER_GATE_CFG`), parsed with sed from the `frontier_access:` block; the hook is inert without it. Model names are hardcoded `fable\|claude-fable-5*`. Messages cite `docs/research/FRONTIER_HOLES.md` and `handoff-fire.sh`. | **T2**, generalizes to a "model-tier spawn budget" | **3** |
| 14 | `anti-deference-nudge.sh` (528 L) | Stop (5 s) | Blocks a final message that asks permission for work it could just do ("want me to…", "say the word", handing work over by count). A one-shot latch per message hash plus a cap of 3 fires per session means it can never wedge the session. Exits 0 on every path. | `lib/idl-log.sh` 137, `lib/agent-identity.sh` 184 (`:68-77,342-346`). Optional: `lib/jev.sh` 237 (an LLM judge; egress allowlist `$HOME/.config/secrets/egress.allow`, `jev.sh:101`), `bin/cc-decide` 538 (`:96-99`), `scripts/wrap-ledger.sh` 2,587 (`:405-410`, only on ship-hold or done-claim) | State `${CLAUDE_CONFIG_DIR}/state/anti-deference` `:57`; IDL `~/.claude/autonomy/idl.jsonl` `:58`. The doctrine vocabulary ("Session Close Protocol", G1-G4, desk) is baked into the regexes and messages. `shasum` `:483-485`. | **T2** | **4** |
| 15 | `session-continue.sh` (1,468 L) | Stop (5 s), plus a CLI `set\|clear\|status` | Loop driven by an agent-set sentinel: the agent arms "🔧 next step" and the Stop hook blocks and feeds it back. The operator's stop phrase always wins; the sentinel is bound to the session ID; a hard loop cap applies. | Kernel: `lib/continue-sentinel.sh` 27, `lib/turn-scan.sh` 89. Fleet layers: `why-tier.sh` 383, `session-writes.sh` 433, `agent-identity.sh` 184, `goal-state.sh` 145, `mailbox-pending.sh` 959, `bin/cc-await-ping`, `bin/cc-custody`, `wrap-ledger.sh` | Fleet layers: comms lag-ack `:397-470`, teardown `:471-569` (`$HOME/.claude/watchdog/teardown` `:553`), wake floor `:570-928` (`cc-await-ping` `:853`, custody `:768`), mechanical 🔧 `:929-1114` and ship floor `:1115-1269` (both on wrap-ledger `:1038-1045,1151-1158`). BSD `stat -f` with a GNU fallback `:559`. IDL/log `:82-83`. | **T2** (kernel = `:1-340` + `:1270-1468`) | **3** (only works if a skill teaches the model to arm it) |
| 16 | `check-edit-boundary.sh` (196 L) | PreToolUse `Write\|Edit\|MultiEdit` (10 s) | freeze mode (deny edits inside the listed paths) and focus mode (deny edits outside them) | `jq`. Optional `scripts/lib/worker-claim-gate.sh` (`:92-94`) | State `$HOME/.claude/edit-boundary.json` `:12` is **global**, not per session or project. **Nothing in commands/, bin/ or scripts/ writes it**, so this consumer has no producer; a plugin would have to ship `/freeze` and `/focus`. Prefix match `"${BP}"*` lets `/src` match `/src-old`. | **T1** + a new command | **3** |

Just outside the list: `cache-expiry-tracker.sh` + `cache-expiry-warning.sh` (T1, value 3). Both use one `.last-interaction` file per config dir (`tracker:8`, `warning:28`) rather than one per session, so concurrent sessions reset each other's idle clock. `keychain-guard.sh` (T1, value 2, macOS `security` only). `cc-unattended-ask-guard.sh` (T2, value 3): its 20-line kernel is fine, but the message tells the model to run `cc-decide` and `scripts/gate-classify.sh` (`:59-78`).

---

## (b) All other hooks, one line each (tier, main blocker)

| hook | tier | main blocker |
|---|---|---|
| accounts-board.sh | T3 | `launchctl list` of the fleet's LaunchAgent `:68`; 4-account board |
| activation-watch.sh | T3 | `~/.claude/autonomy/pending-activation` `:65` |
| boundary-handoff.sh | T3 | IDL `:165`, `/tmp/cc-telemetry` context fill, /handoff rails, 7 libs |
| cc-permission-beacon.sh | T3 | beacon for `lead-supervisor.sh` via `/tmp/cc-permission-pending` `:50` |
| coldcompile-admit.sh | T3 | prepends `bin/cc-ignition-gate` `:87` |
| completion-assert.sh | T3 | exits unless `wrap-ledger.sh` is present (`abstain "no-wrap-ledger"` `:286`); `cc-backlog` `:946`; 9 libs (see d) |
| config-change.sh | T1 (value 2) | log `$HOME/.claude/logs/config-change.jsonl` `:51` |
| config-mirror-assert.sh | T3 | `~/.claude/bin/cc-settings-parity` `:46`; multi-account mirror |
| curl-gate-scope.sh | T3 | **hardcoded `/Users/chrisren/Development/reso-management-app`** `:63` |
| curl-gate.py | T3 (unregistered) | project-scoped to reso-management-app `:5`; its shlex/urllib host parsing is reusable |
| cwd-changed.sh | T2 | `~/.claude/file-watch-paths` watch-list protocol `:66` |
| desk-brief-inject.sh | T3 | `~/.claude/cc-roles` desk role `:59` |
| dispatch-assert.sh | T3 | IDL `:53`; backlog and dispatch doctrine |
| dod-persist.sh | T3 | `~/.claude/autonomy/dod` `:49`; `mailbox-pending.sh` `:213`. The idea (a durable DoD that survives compaction) is portable. |
| escalation-watch.sh | T3 | `~/.claude/cc-announce-alarms` and dead-letter stores `:69` |
| file-changed.sh | T2 | log dir and watch list `:70-72`; the live matcher is an absolute `/Users/chrisren/...` path |
| frontier-status.sh | T3 | `$HOME/.claude/model-config.yaml` `:13`; FRONTIER_HOLES ledger |
| goal-inert-watch.sh | T2 | goal-state/turn-scan/page-damp libs, IDL `:153`; tied to CC 2.1.260 /goal behaviour |
| handed-off-session-guard.sh | T3 | cross-account transcript-transplant detection `:157` |
| handoff-claim-assert.sh | T3 | `$CFG/bin/cc-cannot` `:84` |
| handoff-intent-nudge.sh | T3 | fleet /handoff text `:42`; agent-identity lib `:30-31` |
| harvest-skill-end.sh | T3 | `~/.claude/session-index.db` `:22`, `skills-pending` `:49` |
| hook-chain.sh | n/a | dispatcher, deliberately left unwired (`:24-45`: measured no gain) |
| instructions-loaded.sh | T1 (value 2) | log dir `:68` |
| lead-crash-watchdog.sh | T3 | detached daemon, osascript×8, it2/kitty, `cc-teardown`/`cc-notify` |
| live-session-registry.sh | T3 | `$HOME/Development/.worktrees` `:27`; worktree-gc registry |
| log-bash.sh | T1 (value 2) | `~/.claude/logs/bash-execution.log` `:54-55` grows without bound and records full commands, including inline secrets |
| mail-images-auto.sh | T3 | `bin/cc-mail-images`; `autonomy` log `:14` |
| mailbox-drain.sh | T3 | `lib/mailbox-pending.sh` (959 L) `:56` |
| mailbox-wake-arm.sh | T3 | `~/.claude/mailbox` `:133`; `cc-await-ping`; 14400 s async |
| memory-index-drain.sh | T2 | `bin/cc-memory-rotate` `:135`; 3 memory-index libs |
| memory-nudge.sh | T2 | `cc-memory-rotate` `:207`; BSD `stat -f` `:231` (degrades); MEMORY.md doctrine |
| migrate-plans-index.sh | T3 (unregistered, one-shot) | `~/.claude/plans-index.json` `:4` |
| model-permission-decider.py | T3 (unregistered; `migrations/0022` shadow) | `MITL_STATE_DIR` under `autonomy` `:90`; `cc-claude-bin`; one model call per blocked Bash |
| net-recover-arm.sh | T3 (unregistered) | NONLIMIT_RESUME_LADDER; `/tmp/cc-net-recover` `:94` |
| notify.sh | T2, macOS-only | `afplay /System/Library/Sounds` `:83-84,337-339`; `osascript` `:351`; agent-identity lib `:71-73` |
| operator-readout.sh | T3 | autonomy stores `:201-204`, escalation dirs `:302-310`, `deploy-live.sh` `:314`, `cc-do` `:332` |
| permission-denied.sh | T1 (value 2) | log `:54` |
| plan-agent-teams-default.sh | T3 | execution-locus doctrine; IDL `:95` |
| plan-index-update.sh | T3 | `~/.claude/plans-index.json` `:22` (desk mission ledger) |
| plan-pin-session.sh | T2 (value 1) | `~/.claude/sessions/<sid>.plan`; its reader is retired (header) |
| plan-version-commit.sh | T2 (value 3) | `~/.claude/plan-history` git repo `:69`; plan path conventions `:26` |
| post-compact.sh | T1 (value 2) | log `:45` |
| post-file-edit.sh | T1 (value 3) | `npx eslint --fix` fallback `:40-41` can fetch from the network inside a 30 s hook |
| post-tool-batch.sh | T1 (value 2) | log `:38` |
| pre-session-validate.sh | T3 | `~/.claude-versions` binary rollback `:27` |
| push-critical.sh | T3 | Pushover with a per-account sound map `:59` |
| qos-rewrite.sh | T3 | rewrites to `cc-bats`/`cc-cpubound`/`taskpolicy` `:134` |
| recover-inject.sh | T3 (unregistered) | `scripts/limit-recover/lr-lib.sh` (806 L) |
| relay-verbatim.sh | T3 | matches only fleet renderers (`claude-accounts`, `operator-readout`, `cc-do`) `:24-28` |
| research-precognition-nudge.sh | T1 (value 2) | 0 deps; advisory text is fleet research doctrine `:22` |
| reset-hard-shadow-allow.sh | T2 (unregistered, shadow) | state `${CLAUDE_CONFIG_DIR}/state/reset-hard-allow` `:53-55`; overlaps validate-bash GIT-OWNERSHIP |
| session-beat.sh | T3 | `~/.claude/cc-beats` `:98`; spawn-presence lib |
| session-deregister.sh | T3 | `~/.claude/cc-registry` `:54`; iTerm pane |
| session-end.sh | T3 | `sessions.log` `:35`; kitty, `cc-in-kitty`, `scripts/lib/detach.sh` |
| session-index-end.sh / -start.sh / -sweep.sh | T3 | `session-index.db`, `bin/session-search.py`, `cc-history-union` (sweep `:229`), launchd sweep |
| session-register.sh | T3 | `~/.claude/cc-registry` `:123`; iTerm/kitty/`scutil` |
| session-save-id.sh | T1 (value 1) | `${CLAUDE_CONFIG_DIR}/.last-session` `:23`; duplicates the built-in `--continue` |
| session-start.sh | T2 | MCP status logger; `cc-claude-bin`, `cc-mission`; `~/.claude/logs` `:8` |
| setup-plan-symlinks.sh | T3 | `plans-index.json` `:8` |
| setup-task-symlinks.sh | T2 (value 2) | `lib/task-helpers.sh` |
| ship-rail-push-allow.sh | T1 (value 3) | 0 deps; auto-allows non-force `git push origin HEAD:<branch>` `:71-86` (trust question) |
| stop-failure-marker.sh | T3 | `~/.claude/autonomy/stop-failure` `:59`, `accounts.json` `:60`, launchctl/osascript |
| subagent-stop.sh | T2 (in the template but not live) | IDL + `research-artifacts` log `:48-51` |
| task-completed-index / task-created-attrib / task-mutation-index | T2 (value 2) | `lib/task-helpers.sh`; `~/.claude/tasks` indexing |
| teammate-auto-shutdown.sh | T3 | it2×18 / kitty×29, `cc-notify`, `cc-in-kitty` |
| validate-plan-structure.sh | T2 (value 2) | plan `status:` schema doctrine |
| waiting-recycle.sh | T3 | desk recycle; osascript×9; `/tmp/cc-telemetry` `:242`; 101 ms per Bash call |
| worktree-setup.sh | T2 (value 3) | `scripts/worktree-pool.sh` `:154`; `$HOME/Development/.worktrees` `:174,187` |

Registration drift found along the way:
- 12 repo hooks are wired in none of the 5 live settings: curl-gate.py, hook-chain, migrate-plans-index, model-permission-decider, net-recover-arm, recover-inject, reset-hard-shadow-allow, session-index-sweep, subagent-stop, task-completed-index, task-created-attrib, unit-gate.
- 2 live-registered hooks do not exist in the repo: `~/.claude/hooks/net-context-stamp.sh` and `web-entrypoint-ladder.sh`.

---

## (b′) Cross-cutting portability facts, all measured

1. **Lib resolution mostly works for a plugin already.** Most hooks try the script-relative `$(dirname "$0")/lib/…` first (e.g. `validate-bash.sh:80`, `anti-deference-nudge.sh:68,342`), then `${CLAUDE_CONFIG_DIR}/hooks/lib`, then `$HOME/.claude/hooks/lib`. Under `${CLAUDE_PLUGIN_ROOT}/hooks/` the first candidate hits.
   - The fallbacks leak. For this operator, a plugin build that is missing a lib would silently bind to the fleet's live copy (version skew). The build should strip them.
   - `scripts/lib/*` is found via `$(dirname)/../scripts/lib` (`agent-teams-enforce.sh:118,191,495`; `check-edit-boundary.sh:92`), so the plugin must keep the `hooks/` + `scripts/lib/` layout.
2. **The telemetry sink is hardcoded in about 12 hooks.** `~/.claude/autonomy/idl.jsonl` is written by most of them, but each has an env override (`ANTIDEF_IDL`, `COMPLETION_IDL`, `CONTINUE_IDL`, `CC_ADMIT_IDL`, …). A plugin can point these at `${CLAUDE_PLUGIN_DATA}` inline in the shell-form `command`.
3. **`jq` is a hard runtime dependency of almost every shell hook, and missing jq disables the guard.**
   - Every hook fails open when jq is absent (`backup-before-write.sh` top, `agent-teams-enforce.sh:21`). Only validate-bash leaves a trace.
   - A plugin cannot install jq. It is shipped as `/usr/bin/jq` on macOS 15 (this box is Darwin 24), but it is not guaranteed on Linux.
4. **`python3` hooks** (bash-output-offload, pr-gate, smart-bash-allowlist, enforce-email, the keychain fallback) guard with `command -v python3`. On a Mac without Command Line Tools, `/usr/bin/python3` is a stub that passes that check and then opens an install dialog. I did not verify this on this box.
5. **macOS-only calls in the top candidates are rare.**
   - Genuinely macOS-only: `notify.sh` (afplay, osascript, `/System/Library/Sounds`) and `keychain-guard.sh`, whose target is the `security` command.
   - GNU `timeout` is missing on stock macOS: `task-quality-gate.sh:270,311`. `wrap-ledger.sh` documents the same trap and probes for it.
   - `stat -f` has a GNU fallback in `session-continue.sh:559`.
   - The osascript and launchctl hits in `is-true-flag.sh:404-407`, `lib/smart-bash-allowlist.py:228` and `completion-assert.sh:882` are token lists and regexes, not calls.
6. **Personal data and hardcoded paths in a public repo:** `enforce-email-formatting.py:353-366` (addresses), `curl-gate-scope.sh:63` (`/Users/chrisren/...`), and the `FileChanged` matcher in live settings.
7. **Plugin mechanics that change behaviour:**
   - Plugin hook processes receive `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` and `CLAUDE_PLUGIN_OPTION_<KEY>` (`src/code_plugins_components.md:784`).
   - A plugin `bin/` is on the Bash tool's PATH (`:876`). That is how a `session-continue set` CLI would reach the model.
   - `${CLAUDE_PLUGIN_ROOT}` changes with each version; state must go in `${CLAUDE_PLUGIN_DATA}` = `~/.claude/plugins/data/<id>/` (`:1046-1047`).
   - "If you define the same handler in more than one settings file, it runs once. A plugin's or skill's copy of the same handler stays separate" (`src/code_hooks.md:414`). An operator who installs the plugin on top of the fleet install gets **double fires**: two backups, two Stop blocks.

---

## (c) Candidate bundles

| bundle | members | tier | what it needs first |
|---|---|---|---|
| **bash-safety** | validate-bash core (`:724-1164`, `:1763-2288` minus the fleet arms) + `lib/is-true-flag.sh` + `lib/kill-selection.py` + git-worktree-guard (+ keychain-guard as an optional macOS arm) | T2 | Cut arms `:191-723`, `:1352-1761`; move the decision log to `${CLAUDE_PLUGIN_DATA}`; rewrite messages that cite "CLAUDE.md rule #2"; make the lsof-absent case ask instead of deny (`git-worktree-guard.sh:103-109`) |
| **permission-prompt reducer** (label it as trust-sensitive) | smart-bash-allowlist (+py), rm-safe-allowlist, ship-rail-push-allow, reset-hard-shadow-allow (shadow) | T1/T2 | Widen the fence read to user `settings.local.json` and managed policy (`lib:431-440`); ship with opt-in `userConfig`. Every member can emit `allow`. |
| **write-backup / edit safety** | backup-before-write + vendored `scripts/restore-file.sh` + check-edit-boundary + new `/freeze` `/focus` commands + teammate-checkpoint (opt-in) | T1 | `BACKUP_DIR`→`${CLAUDE_PLUGIN_DATA}` (`:116,143`); drop the MEMORY.md arm and plan doctrine (`:61-95`); make the boundary state per project; fix the prefix match |
| **context economy** | bash-output-offload + cache-expiry pair (keyed by session) | T1 | Reaper for the offload dir; per-session `.last-interaction` |
| **email send guard** | enforce-email-formatting.py | T2 | `MAILBOXES` → `userConfig`; tool-name prefix configurable; drop the `$HOME/.claude/bin/ms365-*` recipe or ship those scripts in plugin `bin/` |
| **agent-spawn governor** | agent-teams-enforce kernel (budget/depth `:268-460`, brief caps `:609-660`) + frontier-spawn-gate generalized to "tier budget" + unit-gate HALT brake (+ `bin/cc-halt`) | T2 | **Remove the `claude-opus-4-8` fail-closed allowlist (`:535-563`)** or make it opt-in; config via `userConfig`, not `model-config.yaml` |
| **PR hygiene** | pr-gate | T1 | Explicit timeout |
| **hook-surface observability** | log-bash, permission-denied, post-compact, post-tool-batch, config-change, instructions-loaded | T1 | Logs → `${CLAUDE_PLUGIN_DATA}` with rotation; redact secrets in log-bash |
| **close-integrity** (see d) | session-continue kernel + anti-deference-nudge + a git-only ledger + a slim completion-assert | T2, with an extraction project | wrap-ledger split |
| *not packageable* | mailbox, registry, desk, accounts, recycle, watchdog, index, backlog/decision/DoD hooks (the T3 rows above) | T3 | These are the fleet itself |

---

## (d) The Session Close stack as a standalone plugin

**Verdict: it cannot ship as is. A reduced version ("close-integrity") is coherent and would take about 1,200 lines after extraction.**

| member | could it stand alone? | why |
|---|---|---|
| `session-continue.sh` | **Kernel yes** | The `set/clear/status` CLI, Stop actuator, operator stop phrase (`:1270-1277`), SID-bind (`:1287-1296`), idle re-block skip (`:1307-1377`) and loop cap (`:1380-1397`) need only `continue-sentinel.sh` (27 L) and `turn-scan.sh` (89 L). The other ~900 lines are fleet floors: mailbox wake, custody, teardown, and the 🔧/ship floors on wrap-ledger. The model only arms it if it is taught the 🔧/✅/📦/⛔/📤 taxonomy, so the plugin needs a skill plus `bin/session-continue`. |
| `anti-deference-nudge.sh` | **Yes, minus one arm** | Three of its four fire arms do not use the ledger. The ledger arm degrades to silence without wrap-ledger (`:405-420`). It needs `idl-log.sh` + `agent-identity.sh` (321 L). jev and cc-decide are optional. |
| `completion-assert.sh` | **No** | Hard `abstain "no-wrap-ledger"` (`:286`). Its facts (dirty, unlanded, DoD remainder, 🚀 live-layer, ⛔ operator packets, `FILEDM`/`UNCONV`/`CLOSEF` backlog terms at `:728-748`) come from wrap-ledger, `cc-backlog` (7,043 L) and `cc-decide`. Nine libs, including `peer-owned.sh` at 838 L. |
| `operator-readout.sh` | **No** | Everything it renders comes from fleet stores: pending-activation, decisions, backlog (`:201-204`), escalation dirs (`:302-310`), `deploy-live.sh` (`:314`), `cc-do` (`:332`). For a stranger the block is empty by construction. |
| `scripts/wrap-ledger.sh` (dependency, not a hook) | **Split** | The git rung is general: trunk detection `:505-507`, dirty, ahead, cherry. The rest is fleet: DoD store `:588`, 4-account project roots `:675-676`, backlog `:889`, decisions `:952`, and the live-layer and migration rungs. |

**A coupling that breaks in a plugin, and already rests on a false premise:**
- session-continue writes a per-Stop `.blocked` marker (`:315-340`) that completion-assert reads (`:866-867`) to suppress a second block. The comment justifies this by settings.json order ("position 4 … position 6").
- The docs say "All matching hooks run in parallel" (`src/code_hooks.md:414`). The order is therefore not guaranteed today either, and in a plugin the suppression is a race.
- A close-integrity plugin should merge the two Stop arms into one process, or have them share a lock, rather than depend on order.

**Minimal coherent close-integrity plugin:**
- the session-continue kernel;
- anti-deference-nudge;
- a new `git-close-ledger.sh` (about 200 L, lifted from wrap-ledger's git rung);
- a completion-assert reduced to "done-claim ∧ (dirty ∨ unlanded)";
- a `/wrap` command;
- a skill that carries the close taxonomy.

operator-readout, the DoD, backlog and decision terms, the mailbox and wake floors and the ship floor all stay in the fleet.

---

## Adversarial pass (checked with tool calls, folded into the findings above)

- *"Does validate-bash's FF-gate misfire for strangers?"* No. `FFG_SHARED` defaults to `$HOME/Development/claude-infrastructure` (`:1400`) and anything outside it is skipped (`:1488-1491`). It is dead weight, not a false positive.
- *"Does agent-teams-enforce hold up for a stranger?"* No. When `model-config.yaml` is missing it falls back to a stale allowlist and fails closed, denying non-opus teammates (`:535-563`). This is the biggest hidden blocker among the candidates.
- *"Is the Stop-stack ordering guaranteed?"* No. The docs say matching hooks run in parallel (`code_hooks.md:414`), which contradicts the ordering assumption in `session-continue.sh:315-330`.
- *"Is check-edit-boundary usable?"* It has no producer anywhere in the repo, so it is inert unless something outside the repo writes `~/.claude/edit-boundary.json`.
- *"Are the py hooks' lib references real?"* The `session-writes.sh` / `cc-interactive.sh` references in `enforce-email-formatting.py` are comments only; the predicate is re-implemented in Python (`:628-700`).

Unverified or left out:
- Stop-stack latency, as opposed to Bash-chain latency, was not measured.
- The python3 CLT-stub behaviour was not tested on this box.
- I did not check whether a PreToolUse `allow` from a plugin overrides a user **deny** rule. The docs cited here state "deny and ask rules are still evaluated" only for PermissionRequest (`code_hooks.md:1937`).
