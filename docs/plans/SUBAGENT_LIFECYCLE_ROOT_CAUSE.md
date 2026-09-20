---
status: open
---

# Spawned agents that do not close — implementation plan (one explicit fix per identified root cause)

**Source of truth for every row here:** `docs/research/SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md`
(the register) and the twelve per-axis reports under `docs/research/subagent-lifecycle-2026-09-19/`.
This plan implements the register's **FIX** rows, runs its **PROBE** rows, and changes nothing for
its **KEEP**, **NOT-FIX** and **VENDOR** rows. Operator constraint, verbatim (2026-09-19): *"only
solve if and when we have explicit issues identified to explicitly solve, never wrap unknown
unknowns with general catches and patches"* and *"ensure we don't overfit break something that isn't
broken either if there isn't a problem identified."*

**Scope (frozen):** land the explicit fixes RC-1, RC-2, RC-3, RC-4, RC-5a, RC-5c, RC-6, RC-7,
RC-12 with RED-first controls; run the two probes (RC-10, the R2 idle-shutdown control); decide
RC-5b from measurement, never from a hunch. Out of scope by construction: any timer, idle count, age
sweeper, `teammateMode` switch, runner-wide exit-on-return, or auto-approval of `shutdown_request`.

**The contract these fixes restore, in one sentence:** a teammate is closed by its LEAD through
the vendor's own path (`shutdown_request` → self-exit → lead kills the pane), the lead is told
mechanically when it has residents to close, and the fleet's janitor and transport stop refusing
or destroying for reasons that were measured to be defects rather than protections.

---

## Phase 0 — Agent Team Orchestration (MANDATORY)

**Execution locus per wave** (S = dispatched session via `scripts/handoff-fire.sh`, the default;
T = in-session teammates; L = lead-inline):

| wave | locus | why (T and L need one line; S needs none) |
|---|---|---|
| W1 closer + completion-assert predicates | **S** | — |
| W2 `it2-kitty` composer guard + identity pin | **S** | — |
| W3 lead-side resident-member ledger arm | **S** | — |
| W4 spawn advisory + contract docs | **S** | — |
| W5 probes + the RC-5b measured decision | **S** (probes) then **L** (decision) | the decision is one paragraph over W3/W5 numbers; nothing to fan out |

**Task size band:** every unit is written to **40–150K output tokens ≈ 30–75 min ≈ 3–6 files**
(measured peak band). W1 and W2 sit in the band; W4 is small and is padded by nothing — it stays
small because it is one task, not because the band demands more.

**Lead (the recycled successor of this session).** Fires W1, W2, W4 and W5-probes in one batch,
each with `--worktree`, `--notify-back` and a `--goal` naming the wave's gate command; holds
**≥50% of its window** for merging verdicts and the RC-5b decision. **Succession point:** after W3
lands (the lead will have absorbed four completion pings and one merge loop); it recycles before W5's
decision if fill exceeds 50%. A live `/goal` in the firing pane means **no `cc-await-ping` park** —
`~/.claude/hooks/session-continue.sh set "<next wave>"` is the cross-turn lever.

**Roster and ownership (single owner per file):**

| wave | branch / worktree | owns | blockedBy |
|---|---|---|---|
| W1 | `fix/teammate-closer-predicates` | `hooks/teammate-auto-shutdown.sh`, `bin/cc-classify` (mirror of `_tool_in_flight`), `hooks/completion-assert.sh`, `tests/teammate-auto-shutdown.bats`, `tests/completion-assert*.bats` | — |
| W2 | `fix/it2-kitty-composer-guard-narrow` | `bin/it2-kitty`, `tests/it2-kitty-composer-guard.bats`, `tests/it2-kitty-identity-pin.bats` (new) | — |
| W3 | `feat/wrap-ledger-resident-members` | `scripts/wrap-ledger.sh`, `hooks/operator-readout.sh`, `CLAUDE.global.md` (§ Session Close Protocol, one paragraph), `tests/wrap-ledger*.bats` | W2 (a resident whose pane close is refused must be clearable) |
| W4 | `docs/teammate-lifecycle-contract` | `hooks/agent-teams-enforce.sh`, `skills/agent-teams/SKILL.md`, `skills/research-subagents/SKILL.md` (one line), `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md` (correction notes only, INTEGRATE), `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md` (falsifier note), `scripts/utc-stamp-lint.sh` (RC-12 note) | — |
| W5 | `probe/teammate-lifecycle-controls` | `docs/research/subagent-lifecycle-2026-09-19/P-probes.md` (new), `tests/fixtures/teammate-probe/` (scratch project) | W1, W2 for the R2 control's pane capture; W3 live two weeks for the RC-5b numbers |

**Spawn order:** W1 ∥ W2 ∥ W4 ∥ W5-probes (batch 1) → W3 (after W2 lands) → W5-decision (lead,
after W3 has run for two weeks).

**Every brief carries verbatim:** "Stop on issue, message lead." · reading list ≤5 files · ≤150
brief lines · pre-grepped line ranges below · the RED-first rule: the control must fail on the
pinned pre-fix sha before the fix is written · "never `it2 session close`, `kitty @ close-window`,
`kill`, `TaskStop` or `SendMessage` against a live session; probes run in the scratch project only."

---

## W1 — closer and completion-assert predicates (RC-5a, RC-5c, RC-3, RC-7)

**RC-5a · tool-in-flight predicate.** `hooks/teammate-auto-shutdown.sh:523-560` `_tool_in_flight()`
reads `tail -n 1` and requires `.type=="assistant"`; the runtime writes an `attachment` record in
the same second as the `tool_use`, so a pending Bash reads as not in flight (register RC-5, L §1).
Fix: walk backwards to the last **assistant** record; treat its trailing `tool_use` ids without a
matching `tool_result` as in flight; additionally treat a `Bash` `run_in_background` launch with no
later task-notification record as in flight. Mirror the same change in `bin/cc-classify`'s
`tool_in_flight()` (the comment at `:520-522` says the two are kept in step by hand).
**RED control:** fixture transcript `tool_use(Bash)` → `attachment` → EOF must read IN-FLIGHT; the
pre-fix predicate reads not-in-flight (that is the RED). Second fixture: `tool_use` → `attachment`
→ `user tool_result` must read NOT in flight.

**RC-5c · `✓ closed pane` verified by process.** After `close_and_log` (`:267-329`, called from
the detached close at `:1288-1306`), verify `pgrep -f -- "--agent-id <member>@session-<team>"` (the
three-flag conjunction from `hooks/lib/agent-identity.sh`) is empty; if not, log
`✗ process survived pane close (<member>, pid <n>)` and page (damped). **Never kill** — the row is
an instrument; L §5 measured 11/105 survivors and the fix for them is the register's RC-4/RC-6,
not a signal. Control: a fake `ps` table with the member alive after a stubbed close ⇒ the line.

**RC-3 · completion-assert abstains for a shared-cwd assignee.** `hooks/completion-assert.sh:336-410`
(`_ca_assignee`, `_ca_mine`): for a **confirmed** assignee (`agent_is_assignee` rc 0 — the SSOT
in `hooks/lib/agent-identity.sh`) whose cwd is shared with its lead (the same `jq` over
`~/.claude*/teams/session-<t>/config.json` that `teammate-auto-shutdown.sh:784` uses for
`WORKTREE_OWNED`, or `cwd == lead.cwd`), the `dirty` and `unlanded` convictions return "not mine":
on a shared cwd the commit is the lead's by construction, and `session-continue.sh:874-884` /
`:1009-1012` already abstain for the same population. **Controls (both RED-first):** (1) an
assignee on a shared cwd that wrote a file and reports done → not blocked (pre-fix: blocked);
(2) an assignee on its OWN worktree that wrote and did not commit → still blocked (equivalence
guard — pin it). Measured population: 94 blocks / 53 sessions since 2026-08-20; re-measure after
two weeks with the census script in the register's §4 row.

**RC-7 · locus comment.** Correct `hooks/teammate-auto-shutdown.sh:3` and `:29-35`: the hook runs
inside the teammate's own Stop pass (binary `260:19651537`; 2,070/2,083 PPID-forensic lines); the
retired `kill -TERM $PPID` story stays as history with the corrected cause.

**Gate:** `bats tests/teammate-auto-shutdown.bats tests/completion-assert*.bats` prints 0 failures;
`scripts/test-hermeticity-lint.sh` clean on the changed tests. **DoD:** both RED controls recorded
red at the pinned pre-fix sha in the commit body.

## W2 — `it2-kitty` composer guard and identity pin (RC-4, RC-6)

**RC-4 · narrow-pane `UNKNOWN`.** `bin/it2-kitty:891-931` (`is_rule` at `:891-905` with
`thresh = max(20, cols//2)`; `AGENT-NO-BOX` at `:925-931` blocked by `not any("❯")`). Fixture =
`~/.claude/logs/composer-snapshots/20260918T031850Z-win89.txt` copied into
`tests/fixtures/it2-kitty/narrow-agent-pane.txt` with `AGENT=rc-consumer-audit`, `ALT=True`,
`COLS<40`. Required verdict: `AGENT-PANE` or `EMPTY`, never `UNKNOWN`; RED first at rc 67. The
only licensed change: when the **argv proof** holds (the window's foreground process carries
`--agent-name <member>`, already computed for the identity pin) and no `NON-EMPTY` body is
readable, the narrow-pane reflow case reads as an agent pane. Never widen the zero-rules rule
(`:764-770`); never touch the `NON-EMPTY` branch. Must-not-wrap (register RC-4): the 20/24 true
positives — add a regression fixture from one of them (`band-hooks`, `session-dc73c0ce`) that must
still read `NON-EMPTY`/refuse if its snapshot shows unsent text; if its snapshot is also a bare
reflow, record that the true positives were saved by accident and that W1's RC-5a/W3's RC-2 are
what now protect them.

**RC-6 · identity pin two-state collapse.** `bin/it2-kitty:628-650` `identity_ok`: when
`kitty @ ls --match id:N` exits 1 with empty stdout and stderr "No matching windows", return a
distinct **gone** verdict (a new rc, e.g. 68, mapped by `teammate-auto-shutdown.sh:284` to
`~ pane already gone` and a clean `✓`-equivalent), not "payload unreadable". Control: stub `kt ls`
to that output → gone; stub it to a two-window payload → refused as today.

**Gate:** `bats tests/it2-kitty-composer-guard.bats tests/it2-kitty-identity-pin.bats` 0 failures.
**DoD:** rc 67 count in `~/.claude/logs/teammate-lifecycle.log` for the narrow-pane cause reads 0
over the first week live (F's per-day table is the baseline: 26 in 14 d).

## W3 — the lead is told it has residents (RC-2, resolves RC-8)

`scripts/wrap-ledger.sh`: new field `RESIDENT_MINE` = members listed in
`~/.claude*/teams/session-<this-sid>/config.json` (excluding the lead) whose
`claude.exe --agent-id <name>@session-<sid>` process is alive (the three-flag conjunction; `ps`,
never `pgrep -f <name>` alone — memory `pgrep-f-matches-agent-briefs`). Non-empty ⇒ rung 🔧 with
the members NAMED and, for a shared cwd, the member's own dirty files (from `session_dirty_mine`
against the member's transcript). `hooks/operator-readout.sh` renders the line; `CLAUDE.global.md`
§ Session Close Protocol gets one paragraph: *a resident member is your loose end — `shutdown_request`
each, escalate to `TaskStop` after ~60 s, and the rung clears when the process is gone.* It is a
CHECK: nothing in W3 closes anything. **Control:** fake config + fake ps table with one live member
⇒ `wrap-ledger.sh --machine` does not read ✅; the same with the process gone ⇒ ✅ reachable.
**Measurement it exists to produce (feeds W5):** the share of leads sending a `shutdown_request` to
every member over the following two weeks (H's baseline: 26.4% of leads; 44.7% of members got
nothing), re-run with H's script.

## W4 — spawn advisory and the contract stated correctly (RC-1, RC-7, RC-11, RC-12)

- `hooks/agent-teams-enforce.sh`: advisory `additionalContext` (never a deny) when an `Agent` call
  sets `name:` on a research `subagent_type` (`deep-research`, `deep-research-sonnet`, `Explore`,
  `frontier-derivation`): *"naming makes this a persistent teammate you must shut down; leave it
  unnamed to have it return and reap itself, unless you will message it."* Control: fixture spawn
  payloads with/without `name:` and by type.
- `skills/agent-teams/SKILL.md:336-410`: state the vendor contract (idle ≠ done; `TaskStop` is a
  pane kill plus a team-file edit and can leave the process; structured `shutdown_response` is what
  terminates; `isolation`/`cwd` beside `name` demote silently). `skills/research-subagents/SKILL.md`:
  one line pointing at the advisory.
- `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md:577` and
  `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md:15`: INTEGRATE correction notes (locus; the
  "rc=67 has not recurred since 2026-08-17" falsifier is false — 32 events since).
- `scripts/utc-stamp-lint.sh`: note the 2026-09-06 PDT→CDT change and the rule that a join between
  a local-stamped log and UTC transcripts must census the raw offset and require it unimodal.

## W5 — probes, then the one measured decision (RC-10, RC-11 control, RC-5b)

**Probe P1 (RC-10, lead-exit cleanup budget).** Scratch project under `tests/fixtures/teammate-probe/`
with its own `settings.local.json`; a lead spawns 4 named teammates, waits for all four idle
notifications, then exits gracefully; at +30 s count surviving kitty windows and `--agent-id`
processes. Two runs. Result → `P-probes.md`. Only a failed probe (survivors > 0 on a graceful
exit) licenses a fleet-side change, and that change is scoped to the fixture that failed.

**Probe P2 (the R2 control from K).** One named teammate, let it idle, send a structured
`shutdown_request`, capture the pane with `kitten @ get-text` at +10 s and +60 s, and read the
transcript's tail. Outcomes: modal on screen ⇒ brief-side ban of prompt-triggering commands (a
lesson already on file); no modal and no exit ⇒ a vendor reproduction worth filing (issue #81807's
shape); clean exit ⇒ the 2026-08-26 "idle 0/4" was environment, not vendor.

**Decision D1 (RC-5b, janitor scope) — taken by the lead from W3's two-week numbers, with a
conviction figure.** The closer's P4 class (it closes members the lead still wants, 11/17 of
premature closes) is structurally invisible to a hook that sees only turn boundaries. Two measured
options: **(a)** keep the closer as it is after W1 (premature rate re-measured with L's script);
**(b)** restrict the closer to members whose lead is DEAD (positive death evidence — the class
`lead-crash-watchdog.sh` + `cc-teardown --assignee-of` already handle) and let W3's 🔧 plus the
vendor's lead-exit cleanup carry live leads. Choose (b) only if W3 moves the shutdown rate above the
closer's live-lead reap share (36.7% of teardowns today) AND P1 passes; otherwise (a), and say why.
Falsifier for (b) if chosen: residency p90 (H: 2.2 h) must not rise over the following two weeks.

---

## Acceptance — disk-truth reads

| # | check | command |
|---|---|---|
| A1 | W1 RED controls were red at the pinned sha, green after | commit bodies name the sha and the two `not ok` lines |
| A2 | narrow-pane fixture reads `AGENT-PANE`/`EMPTY` | `bats tests/it2-kitty-composer-guard.bats` |
| A3 | a live resident member blocks ✅ | `bats tests/wrap-ledger*.bats` (resident-member case) |
| A4 | premature-close rate re-measured ≤ half of 17.1% at 45 d after W1 | L's classifier over `L-closes.csv` regenerated |
| A5 | `completion-assert` blocks inside shared-cwd assignees = 0 over 2 weeks | the register §4 census script |
| A6 | rc 67 narrow-pane cause = 0 over 1 week | `/usr/bin/grep -c 'rc=67' ~/.claude/logs/teammate-lifecycle.log` per day |
| A7 | P1 and P2 recorded with captures | `docs/research/subagent-lifecycle-2026-09-19/P-probes.md` |

## Decisions and why

- **Why no actuator is added anywhere.** Every candidate actuator (timer, idle count, sweeper,
  runner exit, auto-approve) was red-teamed and shown to hide a measured protective hold or an
  unknown; the vendor's own actuator (lead `shutdown_request` → self-exit → pane kill) worked end to
  end on the live specimen. The plan makes the lead use it, and unblocks it where fleet code stood
  in its way.
- **Why RC-4 and RC-5 ship together.** The composer guard's refusals were the accidental saviour of
  members the closer had wrongly decided to reap (20/24). Fixing the guard alone converts those
  saves into premature closes.
- **Why RC-9 (runner exec-shell) is not touched.** No measured population; a falsifier is named in
  the register. Touching it would be the exact "fix what isn't broken" the operator forbade.
- **Why D1 waits for W3's numbers.** Removing the live-lead janitor is a policy change with a
  measured cost (124 reaps/30 d) and a measured benefit (17% of them premature); only the lead-side
  rate after W3 decides which side is larger. Filing it as "needs-human" would be the deference
  reflex; measuring it is the work.

## Status log

- 2026-09-19 — plan written from the register; W1–W5 unstarted. Next: land with the register, then
  `handoff-fire.sh --recycle` into the implementation lead that fires W1 ∥ W2 ∥ W4 ∥ W5-probes.
- 2026-09-19 13:00–14:30 — implementation lead fired batch 1. **W1, W2 and W4 are live and have
  committed; W5 is held on a capacity refusal; W3's brief is written and waits on W2's land.**
  Briefs live at `/tmp/claude-501/fire-subagent-lifecycle/{W1,W2,W2-recover,W3,W4,W5}.txt`.
  Three things were measured that the plan did not anticipate, and all three cost real time:
  - **A cold `--worktree` fire under load reports `never-engaged` and is wrong.** 3 of 3 cold fires
    expired their load-scaled window (223 s / 261 s / 480 s) while every one of those sessions was
    working. Raising `FIRE_ENGAGE_TIMEOUT_BASE` did not help — W4 got the full 480 s cap and still
    "expired". A warm `--cwd` fire engaged in **9 s** at the same load. Lesson landed as
    `docs/lessons/cold-fire-under-load-duplicates-the-session.md` (c341a2987, hooked 0194d9cb1).
  - **The INC-4 re-type duplicated W2 into its own worktree**, and separately `/tmp/fire-W2.txt`
    collided with a *different* lead's plan file of the same name — their fire read our brief 5 s
    after we wrote it and ran our W2 from their pane. The surviving duplicate stood itself down
    correctly and left W2's work complete, green and **uncommitted**; `W2-recover.txt` was written to
    give that orphaned work an owner, and it engaged in 9 s. Brief files no longer live on a shared
    `/tmp` path.
  - **Every expired fire leaves `goal-arm verdict=unreachable`.** W1 and W4 are therefore running
    with no `/goal` blocking their Stop. They are driven by their briefs and their pings, not by a
    goal — a successor must not assume the goal is what is holding them to the DoD.
  W5 is held **deliberately, not only because the gate refused**: probe P1 measures whether the
  vendor closes four panes inside its 2 000 ms race, and running it at `cc_sp_active` 9–11 with 32+
  bats processes live would measure the box rather than the subject. Note for whoever fires it: the
  capacity gate refuses **once** and then admits, so the next attempt is effectively unguarded and
  the moment has to be chosen by hand.
  A6 baseline captured for W2 before any fix landed: `grep -c 'rc=67'` on
  `~/.claude/logs/teammate-lifecycle.log` = **166 all-time, 26 in the 14 d since 2026-09-05, 0 today**
  (per-day 09-04:5 09-08:13 09-09:2 09-11:4 09-15:3 09-17:4) — matches axis F.
  The research worktree `wt-research-subagent-lifecycle-2026-09-19` was verified 0-ahead/0-dirty with
  no process cwd'd there, and removed.
- 2026-09-19 15:00–16:00 — **W1, W2 and W4 landed and content-verified; W3 and W5 are live.** The
  lead was killed by a next3 session limit at 19:57Z and transplanted to next2 under the same uuid
  (`lr-handoff --in-place`, bundle `bundle-20260919T204738Z`); the post-ingest `lr-audit` read
  **NO GAPS** — delegation population Bash 2, settled 2, open 0 — so nothing in-process was lost.
  - **W1 `3cdaa2552`** (RC-5a/RC-5c/RC-3/RC-7). RED at pinned `d88366d52`: 1..74 with 5 not-ok;
    post-fix 1..212, 212 ok. Two mutants built and killed, so the equivalence guards are not
    decorative. Two findings it surfaced: the RC-7 comment pushed the governed `PATH=` line past
    `unattended-path-lint`'s 1-60 window and un-hardened the file (prose now sits below `export
    PATH`); and the hook and `cc-classify` run under **bash 3.2** in production while bats runs 5.3,
    so both predicates were re-verified under both. Stated residual: 18 of 941 measured background
    launches were never notified and now read in-flight indefinitely — a hold, never a reap.
  - **W2 `c9e70fcca`** (RC-4/RC-6). RED at `e6b212080`. The guard's supposed true positive
    (`band-hooks`/`session-dc73c0ce`) hexdumps as glyph+NBSP+LF on both snapshots — **it was
    protecting nothing**, confirmed by two independent reads, so the honest negative the plan
    anticipated is the recorded outcome. RC-6 lands in `teammate-auto-shutdown.sh:309`'s existing
    already-gone arm with zero edit to W1's file.
  - **W4 `46ccdf23c`** (RC-1/RC-7/RC-11/RC-12). Advisory on every path, no deny/ask/block, keyed on
    `subagent_type`. RED unwaived at `b80f9408e`; each equivalence guard names the mutant it kills.
    Caveat it volunteered: the two GREEN runs used the runner's recorded `CC_BATS_MAX_ROOTS` waiver
    after ~45 min deferral behind sibling suites at load 37-60 — **the RED arm ran unwaived**.
  - **W3** fired warm onto next4; **W5** fired warm onto next2, its brief hardened first to record
    box load before and after every P1 run and to state it in the verdict sentence — P1's 2 000 ms
    budget is wall-clock, so a loaded box manufactures the "probe FAILED" reading that is the only
    one licensing a fleet-side change.
  - 🚨 **The capacity gate refused both fires for a measured-wrong reason, and the row is filed.**
    `cc_sp_active` counted 11-12 mid-turn against a ceiling of 8 while the box sat at **61.75% idle,
    load 5.7**. Cause (peer `wt-cc-100046-36511`, backlog `d20fb6d12810`): a usage-limit kill ends
    the turn with an API error and writes **no Stop beat**, so the corpse's `kind:"prompt"` beat
    counts forever — seven capped next3 sessions were 7 of the 9 counted, and the victims block
    their own recovery. `spawn-presence.sh`'s own comment names this failure class and its liveness
    check misses it, because the limit-killed TUI process **stays alive**. Both fires were admitted
    through the gate's designed refuse-once-then-admit escalation, not by disabling the term.
- 2026-09-20 — **PLAN COMPLETE. All five waves landed, content-verified and live.** W1 `3cdaa2552` ·
  W2 `c9e70fcca` · W3 `f710200f8` · W4 `46ccdf23c` · W5 `dd070aaa1`, every one an ancestor of trunk;
  live layer at `f710200f8`, `LIVE_LAG=0`, `LIVE_ADDS=0`; custody all returned. Nothing on the
  forbidden list was added anywhere, and **both probes declined to license a change** — the plan's
  central bet (fix what was measured, wrap nothing) held end to end.
  - **W3 (RC-2)** shipped `RESIDENT_MINE`/`_NAMES`/`_SRC`/`_DIRTY_FILES` as a 🔧 that NAMES live
    members, ranked one below the custody arm, kill switch `WRAP_RESIDENT=off`. RED 19/19 at pinned
    `3cdaa2552`; its anti-false-positive fixture kills **four** one-line mutants (pgrep-f/name
    substring, single-flag, co-presence-without-cross-field, team-blind) and a fifth case proves all
    four still read 1 on a REAL member. No-team-config ⇒ 0 and nothing changes.
  - 🚨 **D1's baseline is NOT the register's, and the difference is not cosmetic.** W3 re-derived it
    today: 101 leads spawned a named member in 30 d; **23 (22.8%) sent `shutdown_request` to EVERY
    member, 68 (67.3%) to NONE, and 334 of 490 named members (68.2%) got nothing.** These are not
    comparable to §4's 26.4%/44.7% — that script no longer exists, and W3's counts `Agent` `tool_use`
    `name:` spawns, the durable record. D1 must re-run W3's verbatim heredoc (`git show f710200f8`)
    on BOTH ends; its window is transcript mtime and **slides**, so re-run, never re-quote.
  - **A named residual W3 deliberately did not wrap:** Claude Code MUTATES the team config, removing
    a member row on shutdown completion (91 of 95 30-day configs list only the lead, against ~490
    spawns), so a member whose row was removed while its PROCESS survived (RC-11 — `TaskStop` may
    leave the process) is **invisible** to `RESIDENT_MINE`. Closing that needs a different fact and
    was correctly kept out of this wave.
  - **D1 is filed, not dropped:** backlog `b1432e348362`, `not-yet-true` with a falsifier that fires
    2026-10-03. P1's term is already satisfied, so D1 turns entirely on the post-W3 lead-side rate.
  - **Two recovery-machinery findings this wave paid for.** A cold `--worktree` fire under load
    reports `never-engaged` and is wrong (3 of 3; the INC-4 re-type then duplicated W2 into its own
    worktree) — fire warm with `--cwd`, which engaged in 9 s at the same load. And after a
    limit-recover transplant relaunch, W3's `PATH` lacked `/opt/homebrew/bin`, so a gate run returned
    **exit 127 on every suite with ZERO `not ok`** — a non-verdict that reads as a pass unless the
    `1..N` plan line is asserted.
