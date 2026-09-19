# Why our spawned agents do not close down — root-cause register (2026-09-19)

**Scope (frozen):** subagent/assignee lifecycle deep-dive — (1) establish the VENDOR out-of-the-box
contract for how in-process subagents and named teammates end on Claude Code 2.1.260, (2) measure
how OUR fleet's agents actually end and attribute every non-close mechanism to vendor vs fleet layer
with evidence, (3) write this register (each row = explicit mechanism + evidence + still-true-on-260
+ what a fix must NOT wrap) and `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md` (Phase 0 first; one
explicit fix per explicitly identified root cause, no general catches), land both, then
self-recycle into implementation.

**Operator's directive (verbatim, /goal 2026-09-19):** *"deep-dive investigate the behavior of
subagents / asignee agents spawned by a main agent session in Claude Code out-of-the-box. Identify
why our subagents are not being gracefully closed down automatically when done/idle/returned as we
would expect out-of-the-box. Exhaustively dive to investigate the root causes, document, and then
create an implementation plan (to self-recycle into implementation to) to solve at the core root
issue (only solve if and when we have explicit issues identified to explicitly solve, never wrap
unknown unknowns with general catches and patches)."*

**Method.** One lead (this session) + a 12-axis research wave writing per-axis reports under
`docs/research/subagent-lifecycle-2026-09-19/` (A–L; J and K adversarial). Every claim in this
register cites a per-axis file, a binary byte offset in the 2.1.260 strings dump, a `file:line` in
this repo, or a transcript/log path. Prior research on this topic was read and then RE-VERIFIED
against 2.1.260, never trusted: `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md`,
`docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md`, `docs/plans/SUBAGENT_STOP_HOOK_LOOP.md`,
`docs/plans/SESSION_LIFECYCLE_V2.md` (R-8/R-9/R-10), `skills/agent-teams/SKILL.md` § Shutdown.

---

## 0. The operator's experience — what "not gracefully closed" means on this box

Seven genuine operator prompts in the last 30 days name the symptom (extracted from the four config
dirs' transcripts, non-meta user records only; script in this session's scratchpad):

| date | lead session | the operator's words |
|---|---|---|
| 2026-08-17 | `4101dbdf` | "All of our subagents look idle. Please continue appropriately or close the entire Claude Code session and Kitty Terminal pane if youre done with them" |
| 2026-08-23 | `b1fb19b3` | "Done with all of your subagents? How come they werent gracefully closed? do we need to /handoff research and resolve implement our claude-infrastructure use of subagents / Agent Teams agents?" |
| 2026-08-26 | `65ec307b` | "Do we need to fix our cluade-infrastructure behavior? our subagents are not gracefully closed." |
| 2026-09-14 | `ba08cab8` | "are we done with these assignee agents and should close?" · "Are these our subagents; are they done; if so, we should close out the panes" |
| 2026-09-17 | `a11fe2dc` | "(Checking in, you have all of our subagents still open but idle)" |
| 2026-09-17 | `c2edde7f` | "Done with all your subagents? do we need a /handoff session why they arent gracefully as out of the box behavior when they are done?" |

So the surface is always the same: **kitty panes holding an idle Claude Code process after the lead
is done with it.** Forensics on those six lead sessions (team config, lead transcript tool_use
records, `~/.claude/logs/teammate-lifecycle.log` joined on the team name):

| lead | distinct named members (unnamed spawns) | member type | lead sent `shutdown_request` | lead `TaskStop` | closer fired for | closer closed | closer surfaced never-close | members the closer never touched |
|---|---|---|---|---|---|---|---|---|
| `4101dbdf` 08-17 | **63 (0)** | general-purpose (gapcheck-N, tx-*, tN) | 27 | 35 | 18 | 18 | 1 | 44 |
| `b1fb19b3` 08-23 | 0 (spawns were in a predecessor) | — | 0 | 3 | 0 | 0 | 0 | — |
| `65ec307b` 08-26 | **8 (0)** | general-purpose ×7, deep-research ×1 | 10 | 5 | 4 | 4 | 5 | 2 |
| `ba08cab8` 09-14 | **10 (0)** | deep-research ×10 | 6 | 10 | **0** | 0 | 2 ("WORKTREE unresolved after 3 defers") | 8 |
| `a11fe2dc` 09-17 | **10 (0)** | deep-research ×10 | 0 | 12 | 5 | 5 | 0 | 5 |
| `c2edde7f` 09-17 | **7 (0)** | general-purpose (hooks-N) | 0 | 10 | 2 | 2 | 4 | 2 |

*(A first cut of this table read "closer closed 0" on every row. That was a join error — `✓ closed
pane` lines carry the member name and not the team name, so a join on the team name cannot see
them. Recomputed by member name, ±1 day around each incident. The same class of error — a
timezone offset — produced and then retracted a "2-hour residency" headline in axis G; see §4.)*

Three facts fall out before any binary is opened:

1. **Every agent in every incident was spawned with `name:`** — 98 distinct named members, 0
   unnamed spawns — and the population is overwhelmingly *research* (deep-research, gapcheck,
   verify, hooks-audit briefs). On this runtime `name:` is the lifecycle switch: a named agent is
   a real child session in a pane that never exits on its own (§2); an unnamed one returns
   in-process and reaps itself.
2. **When the fleet's closer fires and its gates pass, it closes** (29 fired → 29 closed across
   the five teams, 3 s after the member's last record). The defect is upstream of it: **for 61 of
   98 members the closer never fired at all**, and for 12 it surfaced a never-close. What keeps
   `TeammateIdle` from firing is a vendor rule the fleet trips (§3, RC-2): a blocking `Stop` hook
   inside the teammate suppresses the event entirely.
3. **Leads reached for `TaskStop` more than for `shutdown_request`** (75 vs 43); two of the five
   leads sent no `shutdown_request` at all. `TaskStop` on 2.1.260 is a pane kill plus a team-file
   edit and never a message to the teammate (§2), so it closes the pane but can leave the
   `claude.exe` process alive — the binary's own warning says so.

The team directories for all six incident leads are gone (`~/.claude*/teams/session-<sid>/` absent)
while 411 other team directories survive back to 2026-06-22 and no fleet script deletes them
(`rg 'rm -rf.*teams/' bin scripts hooks` → 0). Whatever removed them is a vendor path; see §2.

## 1. The fleet as it actually runs (measured this session)

| layer | fact | evidence |
|---|---|---|
| binary | every live session is 2.1.260 (`~/.claude-260/…/bin/claude.exe`); 2.1.220 is the baseline the prior research read | `ps` census 2026-09-19 11:05 |
| teammate backend | `teammateMode: "iterm2"` in every config dir's settings.json | `~/.claude/settings.json:66`, `~/.claude-quaternary/settings.json:1184` |
| transport | the vendor's ITermBackend `it2` calls are served by `bin/it2-kitty` (kitty 0.48.2); each agent pane launches `bin/cc-pane-runner`, which runs the delivered command and then **`exec`s an interactive login shell when the command returns** | `bin/cc-pane-runner` header + `_fallback` |
| closer | `hooks/teammate-auto-shutdown.sh` (1,325 lines) on `TeammateIdle`; `SubagentStop` has 0 hooks in every config dir | `jq .hooks ~/.claude*/settings.json` |
| closer outcomes, all time | 16,268 fires · 1,270 `✓ closed pane` · 166 `rc=67` composer-UNKNOWN refusals · 284 `SHARED-CWD-NEVER-REAPS` surfaces | `~/.claude/logs/teammate-lifecycle.log` (4.1 MB) |
| closer outcomes, last 14 d | 177 fires · 98 closes (55%) · 26 rc=67 · 75 surfaced · 124 defers | same log, per-day counts in this session |
| in-process subagents, last 7 d | 153 sidechain transcripts under `<project>/<sid>/subagents/` across the four config dirs | `find … -path '*/subagents/agent-*.jsonl'` |
| teammate child sessions, last 7 d | ≥30 top-level transcripts carrying `--agent-id` argv | grep over `projects/*/*.jsonl` |

## 2. The vendor contract on 2.1.260 — what out-of-the-box actually does

<!-- filled from A-vendor-exit-paths, B-vendor-idle-protocol, C-vendor-in-process-subagents, D-vendor-pane-backends, I-vendor-docs-and-changelog -->

### 2.0 Vendor CHANGELOG, hand-verified this session (raw file, 7,158 lines, head = 2.1.278)

Lifecycle entries between the prior research's baseline (2.1.220) and today, with the version each
shipped in — the fleet runs **2.1.260**, so everything at or below it is already in the binary:

| version | entry (verbatim) | bearing |
|---|---|---|
| 2.1.224 | Fixed `SendMessage` reporting "Message sent" when the write to a teammate's inbox had actually failed | a delivered `shutdown_request` can now be trusted as delivered |
| 2.1.232 | non-teammate agent spawns in interactive sessions now run in the background by default | unnamed agents are background by default; `name:` remains the persistence switch |
| 2.1.234 | teammates now use the leader's model unless the spawn names one | teammates default to Opus 5 here |
| 2.1.239 | `ListAgents` now lists live teammates | a lead can enumerate what it must still shut down |
| **2.1.251** | **a teammate's final answer not reaching the team lead — it now arrives in the idle notification instead of a content-free "available" notice** | partial correction to the 2026-08-04 "no completion producer" finding: the `summary` channel is now populated; the `completedTaskId/Status` channel is a separate question (§2.2) |
| **2.1.257** | **Fixed agent-team teammates in tmux/iTerm2 panes sometimes staying open after acknowledging a shutdown request** | the vendor's own pane-close-after-approval defect is fixed BELOW the fleet's version |
| 2.1.260 | in-process teammate transcript losing messages during long retry waits | — |
| 2.1.261 | in-process teammates re-sending first-turn announcements (cache miss) | above the fleet |
| 2.1.273 | `/tui` refusing to restart because of a teammate that had already finished and was no longer shown | above the fleet; evidence the vendor tracks "finished" teammates as a distinct state |

Nothing at any version adds an idle timeout, an auto-shutdown, or a self-close for a finished
teammate. The vendor's documented contract (I-vendor-docs-and-changelog.md) is that a finished
teammate goes idle and STAYS RUNNING until the lead shuts it down; `TeammateIdle`'s only documented
power is to KEEP a teammate alive (exit 2 blocks the idle). The fleet's expectation is the opposite
polarity of the documented contract, not a degraded form of it.

### 2.1 Live specimen, 2026-09-19 (team `session-d02d8feb`, the operator's screenshot)

Two named teammates in one shared worktree, both finished at 10:55 local and idle at a prompt:

| step | `e2e-legacy-nav` | `lint-window-id` | source |
|---|---|---|---|
| last real work + report to lead | 10:55:30 | 10:55:49 | member transcripts |
| fleet Stop hook inside the teammate | — | `completion-assert.sh` blocked its stop twice ("26 files YOU edited"), forcing 2 extra turns; the member's brief forbade git commands, so the demand was unsatisfiable by design; it stopped at 10:56:34 | transcript `de6725d8…`, 15:55:51Z / 15:56:03Z |
| fleet closer (`TeammateIdle`) | deferred 3× "dirty tree", then `⚑ SURFACE … Pane NOT closed` twice | deferred 2× | lifecycle log 10:54–11:02 |
| lead sends structured `shutdown_request` | 11:06:11 | 11:06:09 | lead transcript `d02d8feb` |
| request lands in the member | 11:07:23 | 11:07:23 | member transcripts (≈70 s inbox latency) |
| member's response | **no assistant turn recorded** — the next records are `bridge-session`/`cost-state`/`last-prompt` end-of-session rows | same | member transcripts, last 4 records |
| process, config membership, kitty window | all gone within the minute; `kitty @ ls` shows no window on that cwd | same | `ps`, `config.json` (lead only), `kitty @ ls` at 11:27 |

So the vendor path — lead sends `shutdown_request`, an IDLE teammate is terminated by the runtime
without a model turn, the member is removed, the pane is closed through the it2 shim — **worked end
to end on 2.1.260**. The eleven minutes between "done" and "closed" were the lead's own decision
latency; it was still using both members ("your call, I'm idle"). This is the designed behaviour,
and the operator's instruction for this investigation is explicit: do not break it.

### 2.2 A named teammate's life on 2.1.260, read from the binary (A, B, C, D)

| transition | what the vendor does | evidence |
|---|---|---|
| spawn | `Agent({name})` with no `isolation` and no `cwd` → a child process `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>` in a pane chosen by `teammateMode`; the parent holds an `in_process_teammate` task record carrying a `paneTeardown` closure. **`isolation` or `cwd` beside `name` silently demotes the spawn to a plain subagent** — no pane, no member, no warning (still true on 260). | C §0, §5 (`@19024382`: `!C&&!ye`); J #8 |
| turn end | the TeammateInit `Stop` function hook writes `isActive:false` to the team file and mails `idle_notification{idleReason:"available", summary, result}` to the lead; `result` (new in 2.1.260) carries the last assistant text. The lead's panel renders it, in green, as `✓ Teammate @X finished` — **at every turn boundary**. `completedTaskId` is assigned nowhere; `completedStatus` only on the in-process crash path. | B §1–2, A (`260:15182786`), J #1–4 |
| wait | a pane teammate polls its inbox at 1 Hz (`InboxPoller`) and submits any message as a prompt when it is not loading and no dialog is up. **There is no idle timeout anywhere in the binary**, and nothing ends a teammate on its own. | B §3, A (`idle_timeout` constructed 0×) |
| `shutdown_request` | delivered as an ordinary user message with an in-band instruction; **approval is model-mediated** (`SendMessage{shutdown_response, approve:true}`), no timeout, no retry, no escalation. On approval the teammate exits its own process (`Rn(0,"other")`, SessionEnd hooks run); the **lead's** `InboxPoller` then kills the pane (`it2 session close -f -s <id>`), removes the member row and unassigns its tasks. A prose "shutting down" does nothing. | A (`260:29617342`), B §4, D §5, G |
| `TaskStop <name>` | abort + `paneTeardown` (= backend `killPane`), 10 s settle, team-file edit; the binary's own warning says the separate `claude --agent-id` process may still be running. Never a message to the teammate's model. | A (`Ugt`, `260:19133984`), J #13 |
| lead graceful exit | `cleanupSessionTeams`: `killPane` per member, then worktrees and `rm -rf` of the team dir — the whole cleanup registry raced against a **2 000 ms** timeout, each close a separate Python-CLI round trip, result discarded; skipped entirely on `forceExit`/SIGKILL. | D §4 (`Qge=2000`), A |
| crash · `/exit` · `^C` · context wall | nothing closes the pane. The iTerm2 backend never sets a `remain-on-exit` equivalent (all three decorate methods are empty) and never polls; `session list` is consulted only when a later split fails. Stock residue: a live shell at a prompt. tmux differs: `remain-on-exit failed` + `respawn-pane -k` closes the pane on a clean exit. | D §2b/§5 |
| `TeammateIdle` hook | fires **inside the teammate**, in its own Stop pass, only when the session is a team member. exit 2 or `decision:"block"` ⇒ the teammate takes another turn and **no idle notification goes out that cycle**; `{"continue": false}` ⇒ the turn ends, the process stays, the notification still goes out. **A blocking settings `Stop` hook evaluated earlier in the same pass returns before the `TeammateIdle` block: no `TeammateIdle`, no `isActive:false`, no `idle_notification`.** | B §5.1–5.4 (`260:19651537`, `20842361`), A § deltas, log PPID-forensic 2,070/2,083 |
| documented contract | "the teammate stays running and addressable while hidden"; a teammate "can approve, exiting gracefully, or reject"; team directories are removed "when the session ends"; "Shutdown can be slow" is a listed limitation; `TeamDelete` no longer exists. | I §2(a)–(d) with URL quotes |

### 2.3 An unnamed agent's life (C)

Unnamed `Agent()` calls run async by default on 2.1.260 (even with `run_in_background:false` in an
ordinary interactive session), return through a task notification, and are torn down: task
registry entry, abort controller, transcript writer. What persists is small and inert — the
sidechain transcript and its `.meta.json`, the `tasks/<id>.output` symlink, and the task record
for 30 s after notification. `SubagentStop` can block only at the `blockable_turn_end` site; no
vendor `maxTurns` default exists; at a definition's cap the agent exits normally as `completed`
and the truncation is visible only on the async notification. **Nothing in this class lingers on
the box; the operator's complaint population contains zero unnamed agents.**

### 2.4 The expectation versus the contract, in one sentence

The fleet expects a finished teammate to close itself; the vendor built a teammate that goes idle
and stays running until its lead sends a `shutdown_request` it may still refuse, stops it with
`TaskStop`, or exits. Every "graceful close" the operator has ever seen on this box was either the
lead doing exactly that (§2.1) or a fleet hook guessing from a turn boundary (§3).

---

## 3. Where the fleet diverges — the root-cause register

Disposition vocabulary: **FIX** = an explicit mechanism with a measured population and a control;
**KEEP** = a fleet guard whose true positives were measured — must not be wrapped; **NOT-FIX** = no
measured population, so no change (the operator's rule); **VENDOR** = the fleet cannot change it and
must state it correctly; **PROBE** = the one measurement that decides before any change.

| # | layer | mechanism | evidence | 260? | explicit fix | must NOT wrap | disposition |
|---|---|---|---|---|---|---|---|
| **RC-1** | fleet practice | Research agents are spawned with `name:`, which converts a self-reaping subagent into a persistent member. 904 spawns in 30 d, 419 named; 71% of named briefs are research/read-only; **0 of 338 named members ever received a non-shutdown message** — the persistence naming buys was used zero times. | H (a); §0 (98/98 incident members named) | yes | An advisory (never a deny) at the spawn chokepoint `hooks/agent-teams-enforce.sh` when `name:` is set on a research `subagent_type` (deep-research, deep-research-sonnet, Explore, frontier-derivation) — restating the rule the research-subagents skill already carries. | The legitimate named case: a member the lead will message or re-task. An advisory cannot wrap it; a deny would. | FIX (advisory) |
| **RC-2** | fleet lead discipline | The vendor requires the lead to end its members, and **58% of leads send nothing** (42/72); 44.7% of members get no signal; 82% of teammate sessions never see a `shutdown_request`. 105 of the closer's 124 reaps in 30 d fired while the lead was still alive — a janitor working behind a live lead. | H (b)(c); G | yes | A fact-bound ledger arm: `scripts/wrap-ledger.sh` computes `RESIDENT_MINE` = members of THIS session's team config whose `--agent-id <name>@session-<sid>` process is alive, and renders 🔧 naming them and (for a shared cwd) their dirty files; the close protocol then drives `shutdown_request` → `TaskStop` per member before ✅ is reachable. A check, never an actuator. | Members the lead is still using (P4 below). The arm only names residents; the lead decides. Precondition: RC-4 and RC-6, else a refused close leaves the 🔧 unclearable. | FIX |
| **RC-3** | fleet Stop chain inside teammates | A teammate is a full session and runs the fleet's 13 `Stop` hooks. `completion-assert.sh` convicts a confirmed assignee that wrote files and cannot commit them (shared worktree, lead commits by brief): **94 blocks across 53 of 334 teammate sessions since 2026-08-20**, each costing a forced turn — and by the vendor rule each blocked Stop emits no `TeammateIdle` and no `idle_notification`, so the fleet's own closer is silently disarmed on those stops. Live specimen: `lint-window-id` blocked twice at 15:55:51Z/15:56:03Z. `session-continue.sh` already abstains for assignees (`:874-884`, `:1009-1012`); two arms, one population, opposite policies. | this session's census; B §5.3; §2.1 | yes | `completion-assert.sh`: abstain from the `dirty`/`unlanded` convictions for a **confirmed assignee whose cwd is shared with its lead** (same jq over `config.json` the closer uses for `WORKTREE_OWNED`), matching session-continue's policy. Control: an assignee that wrote a file on a shared cwd and reports done is not blocked; an assignee on its OWN worktree that wrote and did not commit is still convicted. | R3 for owned worktrees — an implementation teammate on its own branch must still be convicted for uncommitted work. | FIX |
| **RC-4** | fleet transport (`bin/it2-kitty` composer guard, rc 67) | Every vendor pane kill and the fleet closer funnel through the shim, which drops `-f` and applies the composer guard; the guard refuses on **unreadability**, never on unsent text (166/166 `UNKNOWN`, 0 `NON-EMPTY`). The live era (45 events since 2026-08-10) is 80% one cause: a pane narrower than ~40 columns makes `thresh = max(20, cols//2)` unreachable, so the footer proof fails; each successful close reflows survivors narrower and manufactures the next refusal. Terminal: 7 of 12 never-closed episodes in 14 d. Never retried or escalated. | E §2, F (v) #12, K root B, snapshot `composer-snapshots/20260918T031850Z-win89.txt` | yes | RED-first fixture from that snapshot in `tests/it2-kitty-composer-guard.bats`; move a pane out of `UNKNOWN` only when the argv proof holds (foreground process carries `--agent-name <member>`) and no `NON-EMPTY` body is readable; never widen the zero-rules rule. Unblocks `TaskStop`, the lead's `InboxPoller` kill, `cleanupSessionTeams` and the closer at once. | **The guard's true positives**: 20 of 24 measurable rc-67 refusals (8 of 9 members) were followed by more work, two by ~12 h — the refusal saved members the closer had wrongly decided to reap. Fix RC-4 only together with RC-5, or those members are closed prematurely instead of refused. | FIX (paired with RC-5) |
| **RC-5** | fleet closer (`hooks/teammate-auto-shutdown.sh`) | The closer acts on `TeammateIdle`, which means "a turn ended", not "the work is done". Measured premature rate **17.1% of decidable closes** (18/105, 95% CI 9–23), confirmed by a lead's own contemporaneous message ("the idle-teammate hook REAPS a teammate that goes idle while a background job runs … killed their characterize runs"). Three mechanisms: **(a)** `_tool_in_flight()` reads `tail -n 1` and requires an assistant record, but the runtime appends an `attachment` record in the same second, so a pending Bash reads as not in flight — 4/4 P1 cases, calls returning 1 h 45 m and 3 h 29 m after the close; **(b)** P4 "lead wanted more" (11/17): the closer cannot see lead intent; **(c)** `✓ closed pane` verifies the pane, not the process — 11/105 members kept writing after their `✓`, including an 8-member wave that delivered two hours later. | L §1, §4, §5, §9; F (iii) | yes | **(a)** key the predicate on the last ASSISTANT record and on background tasks launched without a matching completion; **(c)** after a close, verify the `--agent-id` process is gone and log `✗ process survived` otherwise (an instrument, not a kill); **(b)** is structurally unfixable inside a hook that only sees turn boundaries — it is decided by the PROBE below, after RC-2 is live. | The holds that were measured protective: dirty-tree defer with checkpoint-first, `.teammate-busy`, birth grace, operator adoption, the identity pin, rc 67 — 88% of surviving deferred members went on to more work (p90 span 615 min). No new timer, no idle count, no age sweeper. | FIX (a, c) · PROBE (b) |
| **RC-6** | fleet transport (identity pin, rc 66) | `identity_ok` reads `kitty @ ls --match id:N`; an already-gone pane returns rc 1 with empty stdout, which the python reads as "payload unreadable" — a two-state collapse that reports the safe-sounding one. 65 spurious refusals in 30 d (42 of 51 September ones are a second fire on a pane closed ≤6 lines earlier); costs a whole extra `TeammateIdle` cycle of residency each and depresses the `✓ closed pane` health metric the reap alarm reads. Reproduced live, read-only. | F (v) #11, J | yes | In `identity_ok`, discriminate kitty's "No matching windows" (rc 1, empty stdout) as **gone** and return that verdict, distinct from unverifiable. | The pin itself — a kitty window id is a per-process counter and a wrong-window close was observed (`hook:169-184`). | FIX |
| **RC-7** | fleet docs/comments | The closer's header says it runs lead-side and reasons from that; 2,070 of 2,083 PPID-forensic lines show the teammate's own `claude.exe`, and the binary agrees. Two docs carry the wrong locus. | B §5.1, D, A § deltas | yes | Correct `hooks/teammate-auto-shutdown.sh:3,:29-35`, `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md:577` and the agent-teams skill's `TaskStop` claim in the same commit as RC-3/RC-5. | — | FIX (docs) |
| **RC-8** | fleet policy on a vendor constraint | A member whose OWN files are dirty in a shared worktree is held forever by the closer (`⚑ SURFACE … own-footprint hold`, 91 in 30 d) — a **correct** hold (the lead commits by design, and `isolation` cannot give the member its own cwd, RC-11) that nothing resolves because the teammate-side mechanical arm is cleared for assignees. Live specimen: `e2e-legacy-nav`. | K root C, F (v) #10, §2.1 | yes | None in the closer: the hold is right. RC-2's 🔧 names the member and its dirty files, so the lead commits and then shuts it down — the only owner that can. | The hold. A closer that reaps on the 3rd defer here discards uncommitted work. | KEEP (resolved by RC-2) |
| **RC-9** | fleet transport (`bin/cc-pane-runner`) | The runner execs a login shell when the agent command returns, so a teammate that exits without a lead kill leaves a bare-shell pane. No consumer needs that prompt on a teammate pane, and the discriminator (`CC_PANE_CMD_INTERACTIVE`) is already read at `:208` and not at `:213`. **But no measured population exists**: a finished teammate never exits on its own, an approved one is followed by the lead's pane kill, and the live census found 0 former-agent shells. | E §0 V1/V3/V4, K R1 | yes | None now. Falsifier that reopens it: a census showing bare-shell panes descended from `cc-pane-runner` whose launch verb was `claude.exe`. | The pane-outlives-session invariant two suites pin for handoff-fired panes. | NOT-FIX (no population) |
| **RC-10** | vendor (lead exit) | `cleanupSessionTeams` closes every member pane inside a 2 000 ms race, each close a separate CLI round trip through the shim; failure is silent. Whether it completes for N > 2 panes is undecidable from strings. | D §4, A | yes | A controlled probe: 4 named teammates, lead graceful `/exit`, count surviving panes and `--agent-id` processes at +30 s, in a scratch project. Only a failed probe licenses a fleet-side SessionEnd close, and only with the probe as its fixture. | Nothing until measured. | PROBE |
| **RC-11** | vendor | No unprompted self-exit; `idle_notification` renders "finished" every turn; `completedTaskId` has no producer; `TaskStop` may leave the process; `isolation`/`cwd` silently demote a named spawn; the iTerm2 backend has no `remain-on-exit`; `shutdown_approved` is missing from the lifecycle-frame blacklist. Open issue #24385 says an out-of-band pane close corrupts pane tracking; open issue #81807 says Opus subagents ignore `shutdown_request` while emitting `idle_notification`. | A, B, C, D, I §5 | yes | State the contract correctly in the fleet's own docs and skills (RC-7). File upstream only with a reproduction (K R7): the R2 control — named agent idles, send `shutdown_request`, capture the pane at +10 s — decides whether idle non-consumption is vendor-owned or a permission modal. | — | VENDOR |
| **RC-12** | instrument | `~/.claude/logs/teammate-lifecycle.log` is stamped in local time and the box changed zone PDT→CDT on 2026-09-06 (`/etc/localtime` mtime), two days after the 2.1.260 cutover; any fixed-offset or current-zone parse of pre-Sep-6 lines is 2 h off. It manufactured a "2.1.260 delays closes by 120 min" headline this session before retraction. | G § RETRACTION; this session's 12-sample re-measure | yes | Era-aware conversion in any tool that joins the log to UTC transcripts; `scripts/utc-stamp-lint.sh` already names the class. Live instruments (`date -j -f` in the current zone) are correct for lines written after Sep 6. | — | FIX (instrument, small) |

**What this register deliberately does not contain:** an age sweeper, a close-after-N-idles, a
`teammateMode` switch to tmux, a runner-wide exit-on-return, or an auto-approve of
`shutdown_request` — each was red-teamed (K) and rejected as a general catch that hides one of
the rows above or destroys a measured protective hold.

## 4. What the measurements say (G corrected, H, L, F, this session)

| question | answer | source |
|---|---|---|
| population, 30 d | 278 teammate child sessions under 71 leads; 904 Agent spawns, 419 named, 338 launched | G (a), H (a) |
| how a finished teammate ends | torn down by its own lead 55%; reaped by the fleet closer 37%; never closed by anyone 8% (27) | H (c) |
| close latency when the closer fires and its gates pass | median 3 s on BOTH 2.1.220 and 2.1.260 (206 closes, all under 1 min) — re-measured after the timezone retraction; verified independently on 12 samples this session | G § RETRACTION; §0 note |
| residency after last work, fleet-abandoned members | median 21 min, p90 2.2 h to the fleet reap; 105 of 124 reaps while the lead was alive | H (c) |
| `shutdown_request` reach | 49 of 278 received one; structured `shutdown_response` terminates in 0–3.6 s; prose acks never terminate (22/25 still needed a pane close); on 7 sessions `SendMessage` was disabled for the teammate | G (b)(e) |
| Stop-hook blocks inside teammates since 08-20 | 94 blocks, 53 of 334 sessions, all `completion-assert` | this session |
| closer outcome funnel, 14 d | gates said REAP 177 → closed 98 (55%); rc 66 38 (retried, eventually closes); rc 67 30 (terminal); 11 lost inside the 5 s hook budget | F headline |
| dirty-tree backstop | `MAX_DEFERS` discharges into SURFACE 155× and into a reap 0× since the off-by-one fix | F (iv) |
| premature closes | 17.1% of decidable closes (18/105); P4 lead-wanted-more 11, tool-in-flight 4, self-declared-pending 3, deliverable-absent 2 | L §4 |
| guard true positives | rc 67: 20/24 refusals followed by more work; deferred members: 38/43 followed by more work | L §8–9 |
| instrument caveats | 450 of 555 closes have no surviving transcript (retention); 46 of 82 known leads have no transcript; team `config.json` rows are removed by the LEAD's action and 251/278 team dirs are gone (vendor cleanup at lead exit) | L §2, H, G |

## 5. Prior conclusions re-audited (J) and remedy classes red-teamed (K)

J audited 18 load-bearing prior claims against 2.1.260: still true — the `"available"` literal
at every turn, `name:` as the persistence switch, F-a demotion (now readable in code and `cwd`
demotes too), F-c runner exec-shell, `SubagentStop` unwired, D1 shared-cwd holds; **wrong** — "the
only actuator is `abort()`" (the lead's `InboxPoller` kills the pane on approval, on both
binaries, and 260 adds the teammate's self-exit), "`TeammateIdle` fires in the lead",
"`teammate_terminated` proves the process died" (it is minted lead-side after the approval frame);
**stale** — R-8 (`LCW_ORPHAN_CLOSE` is activated), "rc 67 refuses 100%" (three arms shipped
2026-08-10; the narrow-pane residue remains). J also notes the 2026-08-04 enumeration method is
unsound on 260: 1,645 Bun bytecode chunks versus 8 on 220, so "nowhere in the binary" now needs a
runtime probe, not a grep.

K judged eight remedy classes against four measured roots and rejected four outright (age
sweeper, close-after-N-idles, tmux switch, runner-wide exit) — see the note under §3 — and named
the three worth building, which are RC-4, RC-8→RC-2 and RC-2 above, each with its positive control.

## 6. Dimensions deliberately not explored, and why

1. **Bytecode blindness** — the 260 binary's constants live in bytecode chunks; every "no producer
   exists" claim carried forward from 220 is now a runtime question (`--debug` `[InboxPoller]` /
   `[inProcessRunner]` lines, which no session on this box has ever captured). Out of scope for a
   read-only wave; the PROBE rows are where it enters.
2. **The `result` channel** — 260's `idle_notification.result` is unread by any fleet doc, skill or
   hook (0 references). Whether it changes the Delivery-contract discipline is a separate question.
3. **In-process teammates** — whether the Stop chain runs inside an in-process teammate and whether
   the 2.1.219 "idle 0/4" reproduces on 260 both need a live spawn; the live specimen (§2.1) is
   one positive control for the idle pane case (2/2 reaped within a minute), not a rate.

## 7. Status log

- 2026-09-19 11:05 — investigation opened under /goal; worktree `research/subagent-lifecycle-2026-09-19`; 12-axis wave fired (A–L), decomposition critic APPROVE after one gap-fill (L: false-positive closes).
- 2026-09-19 11:27 — operator screenshot of team `session-d02d8feb` captured as the live specimen (§2.1); operator instruction recorded: *"ensure we don't overfit break something that isn't broken either if there isn't a problem identified"*.
- 2026-09-19 ~12:40 — G's "2.1.260 delays closes by 120 min" headline refuted by J and by a 12-sample re-measure; G retracted (§ RETRACTION): the box's zone changed PDT→CDT on 2026-09-06. Incident table's "closer closed 0" corrected (join on member name).
- 2026-09-19 — register written; plan at `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`.
