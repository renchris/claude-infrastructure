---
status: open
---

# GROUND-UP DISPATCH — coordinator runbook for the 12-subsystem rebuild campaign

**Scope (frozen):** drive every open row of GROUND_UP_REBUILD_MAP.md to DONE via one
/ground-up handoff session per row — ≤2 in flight fleet-wide, rows 4→3→2 strictly
sequenced, every fire with --notify-back to the coordinator, account chosen at fire time.

## Phase 0 — Orchestration (the "team" here is the handoff-session fleet)

- **Roster:** 1 COORDINATOR (the recycled successor of e891e080, standing) + up to 2
  concurrent REBUILD sessions (full handoff sessions, one per map row — visible split-pane
  peers per the dedicated-split-pane rule, never in-process subagents). Each rebuild
  session runs its OWN Agent Team internally per its own plan's Phase 0 — this file
  orchestrates SESSIONS, not teammates.
- **Dependency graph:** 4 → 3 → 2 strict chain (shared liveness/comms/succession seams);
  {5, 12, 10, 8, 7, 11, 9} independent of the chain and of each other; 6 blocked-by ALL
  (enforcement surface). Wave 1 = {4, 5}.
- **Worktree assignments:** each rebuild session claims its own warm worktree at fire time
  (handoff-fire does this); the coordinator holds NO worktree claim beyond its own pane's.
- **Spawn-wave order:** fire next-in-order only on (a) a verified completion ping AND
  (b) load < 10 AND (c) an eligible account per the fire-time policy below.

## Coordinator protocol (the recycled session runs this loop)

1. **Fire-time account choice** (never pre-assigned — quota moves): run `claude-accounts`;
   eligible = auth-healthy AND 5-hour headroom AND weekly headroom; among eligible prefer
   the SOONEST refreshTokenExpiresAt (use logins before their cliff); never two in-flight
   rebuilds on one account. Log the choice in this file's row.
2. **Fire** via /handoff → handoff-fire.sh --split-right --notify-back with the row's
   payload below. Verify ENGAGED (transcript birth), record pane uuid + account in the
   Wave log.
3. **On completion ping**: verify the row's DoD by DISK (map row updated, plan doc exists,
   landed shas content-verified on origin/main) — a ping is a claim, not evidence. Then
   fire the next row per the order. On a blocker ping: triage; a seam dispute is decided
   by the seam's OWNER row per the map.
4. **Cadence guards**: before each fire read `uptime` — 1-min load ≥ 10 ⇒ hold the fire
   until the running rebuild lands its next batch (the sessions are the load, not the
   lands). Coordinator itself recycles at ≥50% context per context-econ policy.

## Dispatch order (map §dispatch, dependency-aware)

4 → 3 → 2 (STRICT SEQUENCE, shared seams) · 5 · 12 · 10 · 8 · 7 · 11 · 9 · 6 (last —
enforcement surface of every other row). Wave 1 = row 4 + row 5 (independent of the 4→3→2
chain). Wave N = next-in-order as slots free.

## Per-row fire payloads

Template (compose per row; the goal clause is the FALSIFIABLE distillation — superlatives
are banned by the skill).

**The original template opened with `/goal` and MUST NOT be used as written** — kept here only
so the reason survives. handoff-fire submits the whole file as the session's first prompt, so a
leading slash command makes CC parse the entire submission as that command, and `/goal` caps at
4000 chars; over it the prompt is silently REJECTED, the pane idles at an empty box, and
engagement-verify still reports "confirmed (birth)". Measured on the first wave-1 fire: a 1.7 KB
body plus the notify-back and self-retire trailers came to 3423 chars — only 577 under the cap,
with the account-sweep bridge still able to append at fire time. Corrected shape:

```
YOUR TASK — a from-first-principles GROUND-UP rebuild of ONE subsystem: <subsystem> (row <n>).
You were fired by the ground-up campaign coordinator.

Scope (frozen): <subsystem> achieves <row's metric target> under <row's standing constraint>
— measured, landed, and verified by disk-truth acceptance reads.

STEP 1 (one short command): arm your standing goal so you drive to DONE across recycles —
  /goal <the falsifiable one-liner with the NUMBER in it>. Rebuild per skills/ground-up/SKILL.md.

STEP 2: run /ground-up <slug>. Before any other tool call, READ: GROUND_UP_REBUILD_MAP.md row
<n> - skills/ground-up/SKILL.md - docs/plans/LAND_PIPELINE_V2.md (exemplar).

[locate] your own worktree on branch gu-<slug> (base origin/main) of claude-infrastructure.
Commit ONLY here - NEVER in the shared checkout.

YOU OWN: <row's core surfaces>.  SEAMS NOT YOURS: <seam → owning row> - consume those
contracts, do not redesign them. Any seam dispute: ping the coordinator, never decide alone.

PHASE 1 IS NOT OPTIONAL — two checks BEFORE you design anything (added 2026-07-29):
  (a) RE-DERIVE YOUR ROW'S STANDING-CONSTRAINT CELL from primary disk truth. The map cell is
      the PRIOR SESSION'S HYPOTHESIS, not a fact; say in your plan whether you killed or
      confirmed it. Row 5's cell was falsified mid-rebuild.
  (b) CHECK DAEMON-ACTIVATION TRUTH for every job your row's metric depends on
      (`launchctl print-disabled gui/$(id -u)` + `launchctl list`). 12 of 14 com.claude.* jobs
      are disabled; a metric measured against an inert daemon reads 0% BY CONSTRUCTION and is
      not a performance result.

DoD (all four, or you are not done):
1. docs/plans/<TOPIC>_V2.md with the four load-bearing sections - measured constants WITH
   citations, failure-mode table (every observed mode to its structural answer), rejected
   alternatives with reasons, acceptance criteria as disk-truth reads.
2. Adversarially proven to the skill's Phase 4 bar: RED-proof every new test against a pristine
   pre-change tree recovered via git archive; a positive control beside every absence
   assertion; `|| false` on non-final `[[ ]]` in bats; re-run launchd-bound artifacts under
   /bin/bash (the Bash tool runs zsh, so repros lie).
3. Landed via the project-local /ship CONTINUOUSLY - never batch. Never add corpus work to the
   land path.
4. GROUND_UP_REBUILD_MAP.md row <n> updated with status + plan link + landed shas, landed too.

Every new mechanism ships with an env kill switch, never revert-as-plan.
```

| Row | Slug | Metric target (the number in the /goal) | Standing constraint |
|---|---|---|---|
| 4 | session-registry-reaping | zero live-conversation reaps; reap decision ≤60s stale | never reap a live operator conversation |
| 3 | cross-session-comms | delivery ≥99% within one boundary; exactly-once ack | must survive pane recycles + .forward chains |
| 2 | session-lifecycle | fire→engaged ≤60s p95; zero illegible pane exits | a watched pane never vanishes without visible continuation |
| 5 | autonomy-dispatch | dispatch decision ≤5 min from backlog-add; zero false cliffs | backlog > concurrency is normal, not a stall |
| 12 | daemon-fleet-activation | every staged job runs-or-alarms within 24h of staging | disabled-bit trap; agent stages / operator activates once |
| 10 | operator-surface | every operator-owned step platter'd as ONE runnable command | absence-is-loud requires existence evidence |
| 8 | context-economy | recycle before 75% fill p95; zero auto-compact walls hit | rot degrades decisions before the wall |
| 7 | account-relogin | zero work stranded by login cliffs; routing reads live quota | cliffs are hard walls; 4 isolated accounts |
| 11 | worktree-warm-pool | claim ≤3s warm; disk drift bounded + swept | ownership is per artifact-class |
| 9 | memory-knowledge | index within read limits; zero anti-capture violations | memory rot is the failure mode |
| 6 | guardrail-hooks | zero accidental tool blocks; every deny attributable | rebuild LAST — every row's enforcement surface |

## Wave log (coordinator appends; map rows carry the durable status)

- 2026-07-29: campaign opened; coordinator = the recycled successor of session e891e080.
- 2026-07-29T17:53Z: coordinator re-armed — pane `71B42B48-1331-4F60-8DA3-6849F2682CA2`,
  session `98f66842`, account next2 (claude-secondary), worktree `.worktrees/gu-coordinator`
  on `gu/coordinator`. Fire-time account snapshot (all 4 auth-healthy, `claude-accounts`):
  weekly-window expiry next2 08-01T10:59Z < next 08-02T03:59Z < next4 08-02T09:00Z <
  next3 08-04T12:00Z; `--rank general` = next > next3 = next4 > next2.
- 2026-07-29T18:03Z **WAVE 1 · row 4 FIRED** — session-registry-reaping. Account **next**
  (rank #1; ALSO the soonest login cliff 08-02T20:21Z — use the login before it dies).
  Pane `3446A212-B9A0-4754-95A4-66FBC33C97BC`, session `be504c79`, branch/worktree
  `gu-session-registry-reaping`. **ENGAGED verified by transcript CONTENT** — 12 assistant
  turns + 6 tool_use blocks, not birth alone (the /goal-prefix trap makes birth a false
  positive; this fire deliberately leads with plain text and self-arms a short `/goal`).
- 2026-07-29T18:03Z **row 5 HELD at the cadence guard** — 1-min load 12.58 ≥ 10 immediately
  after the row-4 fire. Account **next2** reserved (soonest-expiring weekly window,
  08-01T10:59Z). Fires resume when load < 10; the sessions are the load, not the lands.
- 2026-07-29T18:10Z **WAVE 1 · row 5 FIRED** — autonomy-dispatch, after the guard cleared
  (load 12.58 → 7.74 over ~7 min). Account **next2** (soonest-expiring weekly window).
  Pane `F3B8333C-AC94-4CF7-B1ED-1212A5D77A94`, session `8891c11f`, branch/worktree
  `gu-autonomy-dispatch`. **ENGAGED verified by content** — 23 assistant turns, 13 tool_use,
  and 0 rows carrying the 4000-char `/goal` rejection.
- 2026-07-29T18:12Z **wave 1 saturated (2/2 in flight); on-method check passed for both** —
  each session armed its own short `/goal` and has read the map row + the ground-up skill +
  the exemplar plan. Row 4: 81 assistant turns / 32 tool_use, writing. Row 5: 23 / 13.
  **Next fire is BLOCKED on a verified completion, not on a timer** — the next row in order
  is **3 (cross-session-comms)**, which additionally requires row 4 DONE (strict 4→3→2).
  So a row-5 completion does NOT unblock row 3; it unblocks **12 (daemon-fleet-activation)**,
  the next independent row.
- 2026-07-29T18:12Z coordinator side-fix LANDED `dfaf7323` (+ wave log `9014fb8b`),
  content-verified on origin/main. **Not yet DEPLOYED** — `~/.claude/scripts/` symlinks the
  shared checkout, which sits at `38eec335`; the deploy autopilot is fail-closed with no GREEN
  postland stamp yet. Until it advances, every cold fire must be preceded by
  `rm -f "$TMPDIR"handoff-deps-XXXXXX.sh` (the live script is still the pre-fix copy).

- 2026-07-29T18:30Z **row 5 INTERIM ping — verified, no fire triggered.** Ping text: design
  landed `7400c614` + map row `bf796c57`, "3 teammates building". **Disk verification (a ping
  is a claim):** both shas are ancestors of origin/main; `docs/plans/AUTONOMY_DISPATCH_V2.md`
  is present at 375 lines carrying all four load-bearing sections; map row 5 now reads
  `**REBUILDING 2026-07-29**` with the plan link and sha. Claims hold. **This is an INTERIM
  milestone, not a completion** — row 5 keeps its slot, wave stays 2/2 saturated, nothing
  fired. The dispatch rule is "fire on a verified COMPLETION", and a design-landed ping is not
  one; treating it as one would have put 3 rebuilds in flight against the hard cap.
- 2026-07-29T18:32Z **cross-row finding from row 5, INDEPENDENTLY CONFIRMED by the
  coordinator** — and it corrects this runbook, so it is actioned here rather than filed:
  (a) `bef587a` landed **2026-07-18** (`git log -1 --date=short`) while the cliffs its cell
  credits it with preventing occurred **2026-07-26** ⇒ row 5's standing-constraint cell rested
  on a falsified premise; (b) `launchctl print-disabled gui/$(id -u)` shows **12 of 14
  `com.claude.*` jobs disabled**, `com.claude.dispatcher` and `com.claude.discovery` among
  them, with only postland-verify + deploy-live enabled and loaded ⇒ row 5's metric was
  unmeetable by construction. **Coordinator response:** the per-row payload template above now
  carries a mandatory PHASE 1 pair — re-derive your own constraint cell, and check daemon
  activation truth before measuring — and the same two paragraphs were appended to the MAP's
  Learnings so every future row session reads them before its first tool call. The two staged
  payloads (rows 3 and 12) were amended in place. **Why this mattered enough to act on
  mid-wave:** I had been copying the map's constraint cell verbatim into every fire payload, so
  an unverified cell was being propagated into all 11 remaining rebuilds.

- 2026-07-29T18:38Z **row 5 SEAM QUESTION → ruled** (non-blocking ping; row 5 kept working).
  Asked who owns `bin/cc-wave-plan`, named in no map row, and offered to stand down if row 7
  should have it. **Ruled row 5's**, plus `bin/cc-route` ruled **row 7's** pre-emptively; both
  recorded in the map's new *Unowned-surface rulings* register with their evidence, so the
  next row inherits the answer instead of re-asking. **Method note worth keeping:** row 5
  justified its claim with a COMMENT in the file (`cc-wave-plan:268` says cc-dispatch is its
  only consumer). A comment is text, not evidence. My first verification grep was *also* wrong
  — `--include='*.sh'` hid `bin/cc-dispatch` and `bin/cc-backlog`, which are extensionless — and
  the corrected sweep is what actually confirmed the claim (cc-backlog's two references are
  comments; `cc-dispatch:200` is the only call). Same trap, two agents, one minute apart.
  The ruling also handed row 5 two things it had not asked for and needed:
  `tests/cc-wave-plan.bats:135` **encodes the premise row 5 just falsified** (wave exceeds
  concurrency ⇒ cliff), so changing it is in-scope but must be RED-proofed and reasoned in the
  plan; and `:141` (a cc-route-propagated cliff) must stay distinguishable, since separating a
  real capped-account stop from a wave-sizing false cliff is the entire point of the split.

## INCIDENT 2026-07-29T19:04Z — row 5's lead died mid-work, orphaning 5 assignees (RECOVERED)

Operator-spotted from the pane view: the `gu-autonomy-dispatch` pane sat at a zsh prompt showing
`Resume this session with: claude --resume 8891c11f…` while its `@gu5-*` assignees were still
visibly working. Disk verdict below — every line was checked, none inferred from the pane.

**It did NOT self-close.** Zero `self-close` tool calls in the whole 502-row transcript (the 18
textual hits are the `--self-retire` trailer it was *given*, not a call it *made*). So the
`--self-retire` trailer this runbook attaches is **exonerated** — do not "fix" it.
**Not quota:** next2 was at 14% of the 5h window / 42% weekly at the time.
**Not one of our closers:** `waiting-recycle` logged `abstained / not-armed` throughout;
`lead-crash-watchdog` only observed `pid file gone — exit`; `cc-reaper`/`team-reaper` show
nothing near the timestamp. **Not row 4** (the obvious suspect, since it is rebuilding the
reaper): all 53 of its kill/teardown-adjacent tool calls are Edits and RED-proofs against files
inside **its own worktree**, zero live process kills.
**Cause remains UNATTRIBUTED.** The transcript stops mid-tool-sequence right after a
`queue-operation` enqueue of a `<task-notification>`, and CC printed its normal resume banner, so
it was an exit rather than a SIGKILL. Filed under the existing `cc-backlog 95281da714f0`
(*Agent-Team lead crash ORPHANS its assignees*, operator-identified 2026-07-26) — **this is that
item's second confirmed occurrence**, not a new class, so no duplicate was filed.

**Damage was bounded by continuous landing — the discipline paid for itself.** The lead had
already landed 6 dispatch commits to trunk (`7400c614`, `0a8a2976`, `361675e8`, `c87ca381`,
`e0356664`, `15cc1f4f`) and its own worktree was clean at 0 ahead. Only assignee work was
exposed: `gu5-decide` held ~518 insertions UNCOMMITTED at the moment of death. Had the lead
batched, the whole rebuild would have been in that basket.

**Recovery playbook that worked (reuse verbatim for the remaining rows):**
1. Confirm death by pid + registry, not by the pane. Confirm assignees still live via
   `ps -axo pid=,command= | grep 'agent-id gu5-'` — assignees DO outlive their lead.
2. Read the lead's transcript for cause BEFORE acting; discriminate self-close vs crash by
   counting `self-close` **tool_use** calls, never textual mentions.
3. **Resume, do not re-fire.** The assignees are keyed `--agent-id <name>@session-<sid>`, so only
   that same sid can re-establish them:
   `handoff-fire.sh --cwd <worktree> --extra "--resume <sid>" --account <same-account-as-the-config-dir> --notify-back <coordinator> --follow`.
   The account MUST match the config dir holding the transcript (`--resume` cannot see another
   account's sessions). Brief it to **recover by DISK, never by waiting on the team channel**,
   which may not reconnect.
4. Retire the emptied pane via `handoff-fire.sh self-close --session-id <dead> --successor <new>`.
   Expect it to refuse — see `cc-backlog 93a9f880b6fe`, filed today: the successor engagement
   check false-negatives on a RESUMED session because a resume writes to the ORIGINAL sid's
   transcript, so there is no "new" transcript to find. Only pass
   `--successor-assume-engaged` once you have proven engagement another way (transcript row
   growth past the pre-resume count + live assistant turns).
5. **Re-deliver anything you sent the dead session.** Its inbox does not follow it. The close
   inventory reported **2 unread messages** stranded in `mailbox/F3B8333C….md` — the coordinator's
   ACK *and* the seam ruling row 5 had explicitly asked for. It died never having read either,
   and the resumed pane has a fresh mailbox. Live proof of `cc-backlog a98084b79b2c`: cc-notify
   reports "delivered to inbox" for a session that will never read it — delivered, read, and
   acted-on are three different events.

**Outcome:** lead resumed in pane `0813A7FF-6E90-49C0-8880-909A267E29F3` (transcript 502 → 536
rows, 188 assistant turns, immediately inventorying its assignees by disk); all three assignee
worktrees now clean and committed (`gu5-decide` +1, `gu5-cadence` +1, `gu5-verdict` +2 — the 518
uncommitted insertions landed safely); orphaned pane retired with succession announced; ruling
and ACK re-delivered. **Row 5 kept its slot — the wave was never over the ≤2 cap.**

### Incident addendum — a resume restores the SESSION, never the TEAM CHANNEL (operator-spotted)

The recovery above was necessary but **not sufficient**, and the operator caught the gap from the
pane view before any alarm did. `handoff-fire --extra "--resume <sid>"` brought the lead back with
its context and its sid — but the five assignees are keyed `--agent-id <name>@session-<sid>` to the
**process** that died (pid 15095), not to the session id. The resumed lead's own words:
`No agent named 'gu5-decide' is reachable.` Every agent-directed send from a resumed lead fails
permanently. **Correct the step-3 expectation in the playbook above: resume buys you context and
landed-work continuity, never team reconnection — brief the resumed lead to harvest by DISK and to
send nothing to any assignee.**

**The operator-visible failure this produced is the sharper finding.** `@gu5-decide` parked on
*"Waiting for team lead approval"* — a permission request routed to a lead process that cannot
answer, with **no fallback to the operator**: no prompt was ever rendered, so the pane looks like
it is waiting on the human while the human has nothing to click. Worse, the mechanism built for
this is inert rather than missing: `hooks/cc-permission-beacon.sh` is landed (`b7db06c5`) and wired
in `~/.claude/settings.json`, yet `/tmp/cc-permission-pending/` **has never been created** and
`cc-blockers` reported *"no safeguard-blocked sessions surfaced"* while the teammate was
demonstrably blocked. A teammate's approval traverses the team channel to the lead and never
presents as a session-local hook event, so the beacon abstains ~100% by construction. Filed
`cc-backlog 1e16815bac51` with both required fixes (fail OPEN to the operator when the approver
process is not alive; give the beacon existence evidence so "none pending" is distinguishable from
"never ran"). Siblings: `95281da714f0`, `93a9f880b6fe`.

**Nothing was lost.** Every assignee's output was already committed in its own worktree
(`gu5-decide` `5a7eb60c`, `gu5-cadence` `21d8e869`, `gu5-verdict` ×2) and worktrees survive session
close, so the dead channel cost coordination, not work. The lead was told to cherry-pick
`5a7eb60c` and **fix its DOA rationale in its own branch rather than drop the commit** — with no
round trip available, dropping it would have been the only real data loss on the table.
Assignee-session GC is deliberately deferred until the lead confirms harvest, so nothing is closed
early.

### Orphaned assignees are NOT agent-reapable — the resolution-path dead end, demonstrated

Trying to GC row 5's five orphaned assignees closed the loop on `cc-backlog 95281da714f0`'s
"no pane close, no resolution path" leg. Every sanctioned route is blocked, and the last one
fails with a refusal that is *correct by its own contract*:

1. **Lead `shutdown_request`** — unavailable: the team channel died with the lead's process.
2. **`cc-teardown` / registry** — they hold **0 registry rows**; the reaper cannot see them.
3. **it2 resolution by cwd** — 0 panes report a `gu5-*` worktree as `session.path`. They ARE
   resolvable, but only by mapping the agent process's **tty** to the pane
   (`ps -axo pid=,tty=` → `--agent-id gu5-*@session-<sid>`, then match `session.tty` via the it2
   API). Recorded because it is the only working resolution and it is not obvious.
4. **`handoff-fire self-close --terminal`** — **REFUSED**: `this is an ORIGIN session, not a
   fired peer … no fired-peer stamp at ~/.claude/cc-fired/<pane>.json`. An Agent-Team assignee
   was spawned by its lead, never fired by handoff-fire, so it has no originator to hand back
   to and the tool classifies it as an origin session that must never self-close.

**The gap is a missing CATEGORY, not a missing feature.** self-close models exactly two kinds of
session — a fired peer (may retire) and an origin session (never retires). An assignee whose lead
is dead is neither: it has an originator, but that originator no longer exists. There is an
`--allow-origin-close` override documented as "deliberate, loud, almost never right"; **this
coordinator deliberately did NOT use it** — forcing a safety gate whose whole purpose is to stop
sessions being closed with no continuation, purely for tidiness, is the wrong trade. Closing them
is therefore an operator step, plattered below.

**Pre-verified safe to close** (checked before deciding, so the operator does not have to):
every assignee transcript has been silent 13-69 min while only the lead is active (22s), all
worktrees are clean with work committed (`gu5-decide` `5a7eb60c`, `gu5-cadence` `21d8e869`,
`gu5-verdict` ×2), and worktrees survive session close, so nothing is lost either way.

| assignee | pane | pid |
|---|---|---|
| gu5-decide (parked on "Waiting for team lead approval") | `8A43425B-C6AA-493D-A14E-678AF747C6A8` | 36549 |
| gu5-cadence | `EAC69523-13DB-4EC1-AE54-5D1384F11F75` | 49251 |
| gu5-archaeology | `75857BFD-6F29-4216-AC92-0F665E13E3D5` | 32551 |
| gu5-telemetry | `261F11A5-C3B9-47A4-9563-3710E9E0EC6E` | 42421 |
| gu5-seams | `B270E0F4-D483-459C-9C5E-A91235992F4F` | 48765 |

### Coordinator error 2026-07-29T19:33Z — the load guard was read but not ENFORCED

Row 3 was fired at 1-min load **25.96**, over this runbook's own hard `load >= 10` hold. The read
happened; the *gate* did not. `uptime` was batched into the same unconditional Bash call as the
fire, so the number was printed and the fire ran regardless — a guard you observe but never branch
on is decoration. **Fix, binding for every remaining fire: the load read and the fire must be ONE
conditional command** — `L=$(uptime | sed -E 's/.*averages?: ([0-9.]+).*/\1/'); if load<10 then
fire else hold` — never two statements separated by a semicolon. Consequence was bounded (the spike
was cold-worktree + npm install and fell back to 12.15 within two minutes, and row 3 engaged
cleanly), which is luck, not vindication. Related trap already recorded above: one fire moves the
guard by itself, so the read must be immediate AND binding.

## Inherited watch — first GREEN postland stamp (status, not a coordinator work item)

Read 2026-07-29T18:15Z: **zero GREEN stamps have ever existed** (`grep -l '"verdict":"green"'
over ~/.claude/autonomy/postland/stamps = 0`). Last 7 verifier cycles: RED ×5 (dominant
attribution `tests/postland-verify.bats`, also `tests/cc-backlog.bats`), CUT ×1, HUNG ×1
(`tests/lead-crash-close-panes.bats`, wedge_at 1565/2215, `reproduced=true`). Deploy stays
fail-closed by design, so **everything this campaign lands is landed-but-not-deployed** until
the stamp exists — the shared checkout sits at `38eec335` while trunk moved on.

**Not reopened here, deliberately.** This is `cc-backlog da18f179ac50` plus a mature lead
chain (`19080082c195` root-cause repro · `10941179f8ec` retraction · `c3dd374de94a` an already
RULED decision · `b4e49b4b5014` the one reproduced postland-config failure · `980fc9e1359b` a
PARKED COMMIT `9423fad6` that fixes it, itself blocked on the `cc-authbrowser` port-lease item
`e280bbc8b6e4` · `ba63751cea54` the open bisect). Ten hypotheses are already eliminated with
evidence and trunk is provably green in a clean room (2096 ok / 0 not-ok); the standing
conclusion is to audit the VERDICT PATH, not the suites. A coordinator diving in would burn
the context the campaign depends on and duplicate owned work.

One NEW data point worth carrying forward: the verifier now emits **HUNG as a distinct state**
with `suspect=`, `wedge_at=` and `reproduced=`, which is exactly what `8b90c69e0edd` asked for
(KILLED vs HUNG route to opposite fixes). That ask appears to be at least partly implemented —
whoever picks up `da18f179ac50` should not re-file it.

## Learnings (accumulate; never delete)

- Wave sizing is the load lever: sessions are the ambient load (14 ≈ load 88-104 pre-v2);
  lands are cheap now. Cap in-flight rebuilds, not landing frequency.
- **One rebuild fire moves the load guard by itself.** Row 4's fire took the 1-min load
  6.93 → 12.58 in ~90s (cold worktree + session boot + its own Phase-1 fan-out). So the
  guard must be re-read IMMEDIATELY BEFORE each fire, never once per wave — a wave-1 pair
  read as "both clear" at wave open is a stale reading by the time fire #2 is typed.
- **A rebuild fire payload must NOT start with `/goal`.** handoff-fire submits the whole
  file as the first prompt; a leading slash command makes CC parse the entire submission as
  that command, and `/goal` caps at 4000 chars — over it, the prompt is REJECTED and the
  session idles at an empty box while engagement-verify still reports "confirmed (birth)".
  Measured here: base 1.7 KB + the notify-back/self-retire trailers = 3423 chars, only 577
  under the cap, and the account-sweep bridge can be appended at fire time. Structure used
  instead: plain-text first line + an inline `Scope (frozen):` + a STEP 1 that has the fired
  session arm its own SHORT `/goal`. Zero cap exposure, and the goal condition ends up being
  the falsifiable one-liner the ground-up skill's Phase 0 actually asks for.
- **Verify engagement by transcript CONTENT, never the script's verdict.** `→ engagement
  confirmed (transcript/registry birth)` is satisfied by attachment/system rows alone. The
  real read is `type=="assistant"` turn count + tool_use blocks in
  `$CONFIG_DIR/projects/<slug>/*.jsonl`.
- **Cold `--worktree` fires collide on a literal temp filename** (fixed 2026-07-29, below):
  BSD `mktemp` only substitutes a TRAILING `XXXXXX`, so
  `mktemp "$TMPDIR/handoff-deps-XXXXXX.sh"` created a file named literally
  `handoff-deps-XXXXXX.sh` and every subsequent cold fire died `mkstemp failed … File
  exists`. First fire of the day always works; fire #2 onward never does — which is exactly
  the shape a per-wave campaign hits and a single manual fire never sees.
