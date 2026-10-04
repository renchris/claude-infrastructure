# U-pain: recurring fleet problems an in-process mod could fix at the root

Sources: MEM = `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/`, LES = repo `docs/lessons`, REPO = the repo, BL = `cc-backlog list` (115 blocked + 1 open), DTS = `anthropics/claude-code/mods/types/claude-code.d.ts` (local copy `/tmp/mods-research/claude-code.d.ts`). **[M]** measured, **[I]** inferred.

**Preconditions for every item below.** The fleet runs 2.1.284 and mods need ≥2.1.287 [M]. The mods README says function-hook modules "load only where function hooks are enabled" and that the API "may change between releases without notice" [M]. A failing hook is *skipped* and core runs in its place (DTS ~3258) [M], so mods fail open. That suits an observer but not a hard guard. Whether mods load in `-p`/headless runs is [I] yes: DTS `session.end` lists "a `-p` run done" and `prompt.read` names "a -p run".

---

### 1. A fired or unattended peer stuck on a permission prompt looks exactly like a working one
- **Evidence:**
  - On 2026-09-05, 8 sessions were `permission-pend BLOCKED` (15–60+ min), 4 of them on the fire's own opening `cd <worktree> && …` (MEM `fired-peer-silence-has-a-third-cause.md:58-66`) [M].
  - On 2026-09-07, 3 blocked panes were graded `finished-teammate`, a teardown class (same file :79-93) [M].
  - 3 more misreads on 2026-09-09 (MEM `classifier-must-consult-the-blocked-store.md:111-121`) [M].
  - 27 of 110 beacons (24%) were cleared by an invocation other than the one that was prompted (MEM `resolution-signal-must-match-the-occurrence.md`) [M].
  - The PermissionRequest payload's `tool_use_id` is empty in 0 of 3,641 records (REPO `hooks/cc-permission-beacon.sh:146-155`) [M].
- **Current workaround:**
  - `hooks/cc-permission-beacon.sh` (443 lines) writes `/tmp/cc-permission-pending/<sid>.json` and clears it by invocation signature (`fde8917ca`).
  - The beacon is read by `cc-blockers` (10 refs), `lead-supervisor` (18) and `cc-classify` (12, wired after 09-09) [M].
  - Every brief bans prompt-raising idioms by name (`.claude/rules/agent-operating-lessons.md:43`).
- **Mod fix (root):**
  - `tool.check` (DTS:3264) resolves the engine's verdict before the mode settles an `ask`, and it carries `tool_use_id`.
  - A `tool.call` wrapper (DTS:3252) brackets the prompt exactly, because its `next(e)` runs "the permission prompt, the tool itself". So "pending" and "cleared" are keyed to the same occurrence by construction.
  - In an unattended session the mod can answer `{decision:"deny", reason}`. That turns a forever-hang into a turn boundary the model reads (see LES `a-deny-is-the-turn-boundary-a-message-lacks.md`).
  - Strictly tighter than core: never `ask` to `allow`.
  - [I] In auto mode the classifier still settles asks after `tool.check`, so the mod sees "ask raised", not "dialog drawn".

### 2. Turn-end detection read from transcripts breaks silently on version bumps
- **Evidence:**
  - On 2.1.260, 112 of 136 finished subagents never wrote `end_turn` (241 of 483 fleet-wide), so every research fan-out blocked self-recycle (MEM `bare-json-key-is-unforgeable-by-content.md:158-163`) [M].
  - `scripts/handoff-fire.sh:2620-2638` still keys on `assistant end_turn` [M].
- **Current workaround:** match a serializer-only bare key, and re-run a per-version census of the `stop_reason` distribution by hand.
- **Mod fix (root):**
  - `turn.complete` (DTS:3651) gives `e.reason ∈ {answer, aborted, refusal, error}` (DTS:10328) plus `e.agentId`.
  - The mod writes a typed record per turn, so nothing parses the transcript.
  - Types are rewritten per build and `claude plugin test` runs on the real runtime (guide, Step 5) [M], so the per-version census becomes a failing test, not a silent drift.

### 3. Idle / working / finished is classified from transcript-tail heuristics and misfires destructively
- **Evidence:**
  - `bin/cc-classify` is 1,254 lines [M].
  - Work outlives its tool call in 3 shapes (2,818 moved-to-background results, 646 Monitor) [M]. On 2026-10-01, `teammate-auto-shutdown.sh` keyed on the `run_in_background` flag alone. It removed a worktree under a running bats suite and closed a live pane (MEM `background-work-has-three-launch-shapes.md`) [M].
  - 345 of 7,319 transcripts exceed the 2 MB tail window (REPO `docs/research/FRONTIER_HOLES.md` C-SC-1 table) [M].
- **Current workaround:** the three-valued `cc-interactive.sh` oracle, a 2 MB tail with a whole-file fallback, `cc-teardown` refusing without `--done-evidence`, and phrase-matching on tool_result text.
- **Mod fix (root):**
  - One host-held state machine built from `turn.start`, `turn.complete` and `tool.call` (observe the result, record background IDs).
  - Each transition writes `{state, turnId, inflightTools, bgTasks, agents, askPending}` to a per-sid file (`$.fs.write`), a fact closers read instead of infer.
  - [I] A dead process still needs an external pid check, because the file stops updating.

### 4. Firing a session and confirming it engaged rest on keystrokes and screen captures
- **Evidence:**
  - `scripts/handoff-fire.sh` is 16,703 lines. `verify_engagement` is at :4695, and an INC-4 resend paste is at :4761-4771 [M].
  - A cold-worktree fire can race auto-submit and never engage (MEM `cold-worktree-fire-autosubmit-race.md`) [M].
  - "never-engaged" verdicts are mostly false. Their cost is that the peer runs with no `/goal` armed, e.g. pane 739 sat static for 30+ min (MEM `never-engaged-verdict-is-mostly-false-and-costs-the-goal.md`) [M].
  - A capture showed an already-resolved prompt; a keystroke nearly hit a working session (MEM `tui-capture-is-a-sample-not-a-state.md:13-24`) [M].
  - A mid-turn brief is invisible to the fired-peer detector (LES `a-mid-turn-brief-is-invisible-to-the-fired-peer-detector.md`) [M].
- **Current workaround:** the paste-and-verify shim, a load-scaled engagement window, disk oracles, and "re-read right before acting".
- **Mod fix (root):**
  - On `session.start`, the fired session reads its own brief file (path from `$.env`/cwd) and calls `$.prompt.submit` (DTS:2507). That call "runs when the session is idle", so there is no boot race.
  - The mod stamps "engaged" at `turn.start` and holds `fired` identity in-process, independent of the first user message.
  - `$.prompt.read()` (DTS:2518) closes the C-SC-1 "composer-draft invisibility fleet-wide" negative space.

### 5. Mailbox and notify-back wake delivery is lossy
- **Evidence:**
  - 78% of mail was unacked and 0 of 16 live sessions were watching (MEM `cross-session-mail-v3.md`) [M].
  - Later: 0 armed watchers across 74 mailboxes, 1,300 unacked (46%). The watcher disarms itself by design (MEM `rearm-belongs-on-the-open-path.md`) [M].
  - Mailboxes are keyed by pane UUID while senders address session IDs, so a watcher polls a void (MEM `cc-notify-session-pane-mapping.md`) [M].
  - Backlog `ecf9c60083ff` (Stop `asyncRewake` re-arm) is blocked on a settings.json edit [M].
- **Current workaround:** `cc-await-ping`, a SessionStart `asyncRewake` hook (stderr-only payload), the `session-continue.sh` wake floor, and `cc-notify` typing into panes.
- **Mod fix (root):**
  - A host-held `$.clock.every` timer plus `$.fs.stat`/`read` on a mailbox keyed by `$.session.id()`, then `$.prompt.submit` when idle: nothing to arm or disarm, no pane mapping.
  - For native peer messages, `session.receive` (DTS:3563, `origin.kind` includes `peer`/`peer-send-message`) can tag or redirect.
  - [I] Whether `clock.every` fires while idle needs a probe.

### 6. Context-fill telemetry only exists while the statusline renders
- **Evidence:**
  - `/tmp/cc-telemetry/<sid>.json` is written by `statusline.sh:191-241` [M], which "stops emitting when a pane is not actively rendering" (REPO `docs/plans/TERMINAL_AGNOSTIC_L3_L4.md:804`). The supervisor's world-view can therefore be empty while sessions are live (`docs/research/infra-reliability-audit-2026-07-22/synthesis.md:102`) [M].
  - The cadence mismatch with the beat produced a refuted backlog item (LES `two-producers-one-moment-different-cadences.md`) [M].
- **Current workaround:** treat telemetry age as a non-liveness proxy, and cross-read beats.
- **Mod fix (root):**
  - `session.measure` (DTS:3604) pushes the same figures after every main-thread turn and whenever a rate-limit window moves a point.
  - The mod writes telemetry from there, independent of rendering. `$.session.usage()` is free without a breakdown (guide, Step 3).

### 7. Recycle timing races auto-compact and is actuated from outside
- **Evidence:**
  - H-DSH-1/2 needed an 8-predicate safe-fire gate (S1–S8) and found that the policy "inverts above ~80%" (REPO `FRONTIER_HOLES.md:140-156`) [M].
  - The "74% mid-conversation" `/exit` incident (MEM `context-econ-recycle-policy.md`) [M].
  - A recycle prompt "fires hardest when acting on it kills the most" (rules `git-clean-is-not-nothing-in-hand`) [M].
- **Current workaround:** `waiting-recycle.sh`, `boundary-handoff.sh` (724 lines), the `context-econ` burn forecast from telemetry, and a `/exit` driven by an external watcher.
- **Mod fix (partial):**
  - `session.compact` (DTS:3575) intercepts threshold or precompute compaction. It can `{skip}` or rewrite `instructions` so the handoff brief goes into the summary. That attacks the "auto-compact without brief" arm directly.
  - The advisory can ride `prompt.submit` `context`.
  - [I] No `$` op ends the session. The actual `/exit` and relaunch stays external.

### 8. Unnamed subagent returns flood the lead, and "no spawn past ~70%" is prose only
- **Evidence:** 29 returns came to 1,220,109 chars, about 46% of a 1M window, and the lead died at 97.3% (MEM `unnamed-subagent-return-lands-in-full.md`) [M].
- **Current workaround:** brief text saying "final message is one line: path + count", and a CLAUDE.md rule.
- **Mod fix (root):**
  - `agent.spawn` (DTS:3362) can return `{deny}` when `$.session.usage().context.percent ≥ 70`. That enforces the threshold instead of hoping the model follows the prose.
  - An observe-and-rewrite on `tool.call{tool:"Agent"}` can cap or redirect an oversized return to a file.
  - [I] Background returns that arrive as task-notifications may bypass `tool.call`. This needs a probe.

### 9. Subagent and teammate activity is invisible without parsing side files
- **Evidence:**
  - The main transcript has 0 `isSidechain` rows. Agents write `<sid>/subagents/**`, and `session-writes.sh` attributed subagent edits to nobody (MEM `subagent-records-live-in-separate-files.md`) [M].
  - The SubagentStop harvest hook is blocked on settings (BL `296cc04bc3fd`) [M].
  - The operator asked 7+ times in 30 days why subagents are not closed (MEM `teammate-close-contract.md`) [M].
- **Current workaround:** `find <sid>/subagents`, per-version re-census, and a manual shutdown protocol.
- **Mod fix (root for in-process subagents):**
  - `turn.start`, `turn.step` and `turn.complete` carry `e.agentId` (guide: "main-loop turns only, not subagents"), so a live Pane can list agents, their tools and their fill.
  - [I] Named teammates are separate processes. Each needs its own copy of the mod, so a fleet roster still needs a shared store.

### 10. Rate-limit and husk detection is reconstructed after the fact, and the statusline is too expensive to poll
- **Evidence:**
  - 12 copies of the "limited" predicate exist (REPO `docs/plans/LIMIT_DETECT_100P.md` roster W4) [M].
  - `statusLine.refreshInterval` was refuted at 1 s × 16 panes × 61 ms ≈ one core (same plan :466) [M].
  - Whether `rate_limits` appears in the Max payload is "UNMEASURED" (:459) [M].
  - 6 "resumed" sessions had all exited within 12 min (LES `engaged-is-not-running.md`) [M].
  - The net-recover wake is blocked (BL `4ea535a3a3a3`) [M].
- **Current workaround:** the StopFailure marker hook, the `cc-limited` census, a statusline chip, and a reset poller.
- **Mod fix (root):**
  - `turn.complete` `reason:"error"` gives an exact death signal.
  - `session.measure` pushes `rateLimits` (DTS:8937), and `$.ui.status` displays them with no render polling.
  - `$.clock.every` probes the path and `$.prompt.submit` resumes, which covers net-recover in-process.

### 11. A killed session looks identical to a clean exit
- **Evidence:** SIGTERM prints the ordinary `Resume this session with:` line, byte-identical to `/exit`. The DESK died this way on 2026-09-08 (MEM `dead-session-verdict-belongs-in-the-pane.md`) [M].
- **Current workaround:** `lead-crash-watchdog.sh` paints a verdict onto the pane's tty.
- **Mod fix (partial):**
  - `session.end` (DTS:3616) gives `e.reason` (`prompt_input_exit` vs `other` = signal or `-p` done; DTS:8907) and `e.resume.id`. The mod records the verdict durably.
  - DTS states "a `kill -9` raises nothing", so the watchdog stays as the backstop [M].

### 12. Text-matching Bash guards miss spellings and block prose
- **Evidence:**
  - `hooks/validate-bash.sh` is 2,306 lines [M]. It let 11 of 13 equivalent `rm` spellings past and denied its own fix's commit message (MEM `denylist-enumerates-spellings-not-the-class.md`) [M].
  - Heredoc prose tripped a `git reset --hard` ask (MEM `tui-capture-is-a-sample-not-a-state.md:19-22`) [M].
- **Current workaround:** argv tokenization (`rm_argv_scan`), recursing into `bash -c`/`eval`, and banning idioms in briefs.
- **Not mod-fixable at the root.**
  - A mod's `tool.call` receives the same `e.command` string a PreToolUse hook does.
  - The guide says so outright about Blast Radius: "It reads the command text, so $(…), aliases and scripts that call rm get past it. Use permission rules for a hard block."
  - Mods also fail open (see Preconditions).
  - Only [I] latency and dry-run gains. The root lies in the sandbox or permission rules.

---

**Considered, not ranked:** a lead with live teammates cannot `/exit` unattended (LES `a-lead-with-live-teammates-cannot-exit-unattended.md`). Not mod-fixable [I]: the modal is not a hookable `RenderComponent` (DTS:7459).

### Cross-cutting concerns
1. **Governance.** About 12 blocked backlog rows wait on operator-only (C10) settings.json edits or hook registrations [M: `cc-backlog list | grep -c -E "register hooks/|settings\.j|C10"`]. One mod could ship them all, but later plugin updates would then change behavior without C10 review, so install and update must stay operator-gated.
2. **Install surface.** The plugin must reach all 4 `CLAUDE_CONFIG_DIR`s without forking settings (MEM `feedback-accounts-are-interchangeable`) [I].
3. **Budget.** Each hook gets 10 s of its own time per dispatch, excluding time spent waiting in `$` calls (guide) [M].
