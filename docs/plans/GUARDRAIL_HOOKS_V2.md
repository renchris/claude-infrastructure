---
status: open
---

# GUARDRAIL_HOOKS_V2 — row 6, the guardrail/hook layer

status: OPEN — reconciled 2026-08-17; design landed, build NOT started.

Ground-up campaign row 6 (*what a session may do*). This is the row's first design artifact and it
exists primarily to be **open**: the `plan-open` generator that mints dispatcher-reachable backlog
rows takes an OPEN PLAN DOC as its input, so until this file existed row 6 was structurally
unreachable by the only coordinator-free continuation path the campaign has
(`GROUND_UP_DISPATCH.md:331-338`). Filing it is the act that ends row 6's dormancy.

**Filename discrepancy, resolved once so nobody re-litigates it.** The payload
(`docs/ground-up-payloads/row6-guardrail-hooks.md`) names two files: line 26 says
`GUARDRAIL_HOOKS_V2.md`, its own DoD item 1 at line 195 says `GUARDRAIL_LAYER_V2.md`. Both the
backlog row `f5b31e05b0f7` and its stored falsifier
(`grep -qiE "^status:" docs/plans/GUARDRAIL_HOOKS_V2.md`, appended 2026-08-11T09:48:44Z) pin
**`GUARDRAIL_HOOKS_V2.md`**. The store wins over the prose. `GUARDRAIL_LAYER_V2.md` is a name that
should never be created.

---

## Phase 0 — Agent Team Orchestration (for the build this doc authorises, NOT for the doc itself)

**This session was reconciliation + design only — locus L (lead-inline), justified: a single-file
docs change whose entire cost is disk reads, with nothing to parallelise.** Phase 0 below governs the
build waves that §6's remainders authorise, and is the successor's starting point.

| Wave | Locus | Work | Worktree / branch | Depends on |
|---|---|---|---|---|
| **W1** | **S** — dispatched handoff session | **R-1**: F1+F2 — one atomic registration actuator across the five config dirs, and a caller for `scripts/settings-drift-assert.sh` (AC1 rc 0, AC2 ≥1). Owns `install.sh --wire-hooks`, `scripts/settings-drift-assert.sh`, the five `settings.json` **only via a COPIED dir** per the hazard block | `gu/row6-w1-parity` off `origin/main` | — |
| **W2** | **S** — dispatched handoff session | **R-3** (inverted `launchctl` deny term) + **AC3** (enumerate `hooks/*.sh` minus the registered union; make the difference an alarm row). Both are `permissions.deny` / roster surface, so they share W1's chokepoint and must land after it | `gu/row6-w2-roster` off `origin/main` | W1 |
| **W3** | **L** — lead-inline, justified: a one-cell edit to a shared single-owner file, too small to dispatch and unsafe to parallelise | **R-5**: `GROUND_UP_REBUILD_MAP.md` row 6 — status, plan link, landed shas, the `69 entries` correction, and the §3 cell rename | lead's own worktree | W1, W2 |
| **—** | **operator** | **R-4**: run migrations `0013` and `0014`. c10, not agent work; counted on the operator surface until the EFFECT reads (`[ -L ~/.claude-next/hooks ]`, a `SubagentStop` event exists) | n/a | — |

**Fire form for W1/W2** (`--goal` is not optional — the evaluator is tool-less and judges only what
the session PRINTS):

```
scripts/handoff-fire.sh --prompt-file /tmp/fire-row6-w1.txt --worktree gu/row6-w1-parity \
  --notify-back "${ITERM_SESSION_ID##*:}" --account auto --split-right \
  --goal 'scripts/settings-drift-assert.sh exits 0 AND at least one live settings.json or launchd plist invokes it — proven by the session running and printing `bash scripts/settings-drift-assert.sh; echo rc=$?` and the AC2 grep; do not edit any live ~/.claude*/settings.json as an experiment (copy the dir); DoD at docs/plans/GUARDRAIL_HOOKS_V2.md §5'
```

**Hazard, binding on every wave.** A `PreToolUse` hook that exits non-zero BLOCKS the tool call, on
~30 live sessions, every turn. Never edit a live `settings.json` in place to try something; copy a
config dir, point a scratch session at it, exercise there. Write the rollback before the change and
say out loud what restores it. A slow hook is a broken hook (F9).

**Lead context budget + succession.** The lead holds ≥50% of its window for deciding, spends none of
it on W1/W2 implementation detail, and recycles (`handoff-fire.sh --recycle`) at the seam after W2's
notify-back rather than carrying the merge loop.

---

## §1 STEP -1 — reconciliation against `origin/main`, 2026-08-17

The payload was composed **2026-07-30** and is 18 days older than its subsystem. Per the campaign's
own measured law (`GROUND_UP_REBUILD_MAP.md` Learnings, 2026-08-07) — *an open row is not a row that
needs a rebuild; a dormant row's subsystem keeps moving without it* — every claim in it was re-run
against live disk before any design work. Verdicts are MET / FAILS / SUPERSEDED, one per acceptance
claim, content-verified (`git ls-tree` / a live run), never by sha lookup alone.

**Headline: 8 of 12 claims are MET or SUPERSEDED. One thing still genuinely FAILS, and it is the
same thing the row was commissioned for.**

| # | Payload claim (line) | Verdict | Evidence, re-run 2026-08-17 |
|---|---|---|---|
| A1 | Cell says "69 hook entries / 12 events"; payload measured 67·67·67·64·63 | **SUPERSEDED** | 12 events is still exactly right in all five dirs. Entries are now **84·84·84·84·77** (`.claude`, `-secondary`, `-tertiary`, `-quaternary`, `-next`). Neither 69 nor the payload's five numbers exist any more — which is itself the point: **the constant is a moving target and no carried number may be quoted.** The finding was never the value, it was that the five dirs disagree, and they still do. |
| A2 | 62 distinct `(event, script)` pairs, 58 wired in all five, **4 drifting** across 2 dirs | **FAILS — and the number got WORSE, not better** | **79 distinct pairs, 72 in all five, 7 drifting.** Independently confirmed by `scripts/settings-drift-assert.sh` (rc=1, "DRIFT — 7 divergence(s) across 5 config dirs"). |
| A3 | `Stop`/`operator-readout.sh` missing from `.claude-next` (also row 10's **R-2**) | **MET** | Now wired in all five; absent from the drift list. R-2's first half is closed. |
| A4 | `PreToolUse`/`cc-unattended-ask-guard.sh` — *a permission rail* — missing from `.claude-next` + `.claude-quaternary` | **FAILS (halved)** | `.claude-quaternary` healed; `.claude-next` still missing it. The named permission rail is still absent from one of five. |
| A5 | `SessionEnd`/`session-deregister.sh`, `SessionStart`/`desk-brief-inject.sh` missing from 2 dirs each | **FAILS (halved)** | Both healed in `.claude-quaternary`; both still missing from `.claude-next`. |
| A6 | `permissions.deny` rail missing from 2 of 5 dirs (`cc-backlog 4ce34a4f703c`) | **SUPERSEDED** | `permissions.deny` is **41 entries in all five** (`ask` 6 in all five). `migrations/0009-claude-next-guardrail-parity.sh` landed; row `4ce34a4f703c` was closed 2026-08-11T06:55:55Z. Do not re-file it. |
| A7 | Graveyard slice — `hooks/curl-gate.py`, `hooks/keychain-guard.sh`, `hooks/subagent-stop.sh`, `tests/subagent-stop.bats`, `tests/hook-jq-abstain.bats` all **absent from trunk**, present on `fix/infra-perfection` | **MET (all five landed)** | `git ls-tree origin/main` returns all five PRESENT. Negative control `tests/no-such.bats` ABSENT; positive control `hooks/dod-persist.sh` PRESENT — the instrument discriminates. **The whole graveyard cherry-pick step in the payload is dead work.** |
| A8 | `~/.claude*/settings.json` are NOT symlinks into the repo — "your whole row turns on it" | **MET, and it is the root cause** | All five are REAL FILES, five distinct inodes. `~/.claude/hooks` is a real dir of 78 entries; `~/.claude-next/hooks` a real dir of **53**. Everything in A2/A4/A5 follows from this: hooks converge for free via per-file symlinks, `settings.json` does not converge at all. |
| A9 | Row 13's inbound remainder: PreToolUse Bash admission term needed because ~30% of `bats` invocations use an absolute path (AC1 ceilinged at ~70%) | **SUPERSEDED — the premise was falsified by row 13 itself** | `MACHINE_CAPACITY_V2` §9.7 / map row 13 addendum (0): the 73.2% figure came from a **contaminated denominator** (`timeout` wrappers, `shell -c` lines and claude sessions counted as bats). Clean instrument: **92/92 = 100%**. The `~30% absolute-path` claim is explicitly FALSIFIED. The follow-on `0086d70f85c7` is **done**. Row 6 inherits nothing here. |
| A10 | Row 10 **R-2**: "no alarm covers a hook's own wiring" (second half) | **FAILS — this is the one real hole** | `scripts/settings-drift-assert.sh` exists, is correct, compares deny/ask/hooks across all five dirs, has a `--selftest`, and **has zero live callers**: 0 of 5 `settings.json`, 0 launchd plists, no crontab. Its only non-doc reference is `migrations/0009` (one-shot) and `docs/activation/wiring-all.sh` (unrun). |
| A11 | `/goal ...` "DOES NOT EXIST — verified absent from all five config dirs" | **SUPERSEDED, and the payload's read was wrong** | There is no `commands/goal.md` in any dir, which is what the payload measured — but `/goal` is a **built-in**, documented at code.claude.com/docs/en/goal, and the global CLAUDE.md makes `--goal` mandatory on every dispatched fire. The payload inferred absence-of-feature from absence-of-a-slash-command-file. Ignore its STEP 1 note. |
| A12 | Inbound remainders from other rows are addressed to row 6 | **MET — the inbound queue is empty** | Every named one is closed: `2193948bb00e` (O(N²) hook broker) **done** · `0086d70f85c7` (Bash admission term) **done** · `1e16815bac51` (`cc-permission-beacon`, from `SESSION_LIFECYCLE_V2` F3) **done** · `80321b2556e6` (activation durability) **done**. `DAEMON_FLEET_V2` F21 (agents may `launchctl bootout` but not `enable`) is named as a row-6 permission-layer fact and is **not** filed as a backlog row — see R-3. |

**Two oracles disagreed and the shipping side won.** The payload's drift table and
`settings-drift-assert.sh` now report different sets; the live run of the checker is the truth and
the payload's table is the stale doc. The checker was *right on 2026-07-30* and is right today — it
just names seven rows instead of four.

### What changed under the row while it was dormant, that no earlier doc records

Three commits landed **2026-08-17**, hours before this reconciliation, squarely inside row 6's
surface. All three content-verified as ancestors of `origin/main`:

- `7c08a4bbf` — `migrations/0013-claude-next-hooks-unfork.sh`: converts the forked
  `~/.claude-next/hooks` (53 entries vs 78) into a symlink to `~/.claude/hooks`. **c10, gated on zero
  live `.claude-next` panes; NOT YET RUN** — the fork is still live on disk today.
- `7b1049846` — `migrations/0014-subagent-stop-registration.sh`: registers `hooks/subagent-stop.sh`,
  which has been built and deployed since 2026-07-30 and is in **zero** `settings.json`. **c10, NOT
  YET RUN** — verified: no dir has a `SubagentStop` event at all.
- `17ecae6c6` — the `hooks/validate-bash.sh` **FF-GATE**: denies an ungated fast-forward of the
  shared checkout at the tool call that makes it, because a bare fast-forward advances the FILES and
  creates no symlink for any newly tracked one (42 `merge origin/main` + 8 `pull --ff-only` ungated
  advances, 2026-08-01..08-17). `tests/validate-bash-ff-gate.bats` on trunk.

---

## §2 Measured constants, with citations

Every number below is a live read taken 2026-08-17, not a carried figure. **Each is stated with the
method that produced it, because the whole lesson of A1 is that a constant quoted without its
instrument is a liability.**

| Constant | Value | How |
|---|---|---|
| Hook **events** per config dir | **12**, identical in all five | `json.load(settings.json)['hooks']` key count. Events: `Notification`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PreToolUse`, `SessionEnd`, `SessionStart`, `Stop`, `TaskCompleted`, `TeammateIdle`, `UserPromptSubmit`, `WorktreeCreate` |
| Hook **entries** per config dir | **84 · 84 · 84 · 84 · 77** | sum of `len(matcher['hooks'])` over all events |
| Distinct `(event, script)` pairs | **79** | union across the five dirs, script = basename of the first `*.sh|.py|.js` token in the command |
| Pairs wired in **all five** | **72** | — |
| Pairs **drifting** | **7**, every one missing from `.claude-next` and only `.claude-next` | `scripts/settings-drift-assert.sh` rc=1, independently reproduced by the pair-diff above |
| `permissions.deny` / `ask` | **41 / 6** in all five | — |
| `settings.json` inodes | **5 real files**, zero symlinks | `[ -L ]` per dir |
| `~/.claude/hooks` vs `~/.claude-next/hooks` | real dir **78** entries vs real dir **53** entries | `ls | wc -l`; neither is a symlink |
| Live callers of the parity checker | **0** of 5 `settings.json`, **0** launchd plists, **0** cron | `grep -l` across all five settings + `~/Library/LaunchAgents/*.plist` + `launchd/*.plist` + `crontab -l` |
| Deploy lag, shared checkout | **23** commits `HEAD..origin/main` | `git -C ~/Development/claude-infrastructure rev-list --count` |
| Un-run pending activations | **11** | `*-activate.sh` with no `.done` sibling |

The seven drifting pairs, verbatim from the checker:

```
DRIFT [hooks] "PreToolUse|cc-unattended-ask-guard.sh"    — missing in: .claude-next
DRIFT [hooks] "PreToolUse|coldcompile-admit.sh"          — missing in: .claude-next
DRIFT [hooks] "SessionEnd|session-deregister.sh"         — missing in: .claude-next
DRIFT [hooks] "SessionStart|desk-brief-inject.sh"        — missing in: .claude-next
DRIFT [hooks] "Stop|session-beat.sh stop"                — missing in: .claude-next
DRIFT [hooks] "UserPromptSubmit|handed-off-session-guard.sh" — missing in: .claude-next
DRIFT [hooks] "UserPromptSubmit|session-beat.sh prompt"  — missing in: .claude-next
```

**Read the shape, not the count.** In July the drift was scattered across two dirs; today it is a
clean partition — four dirs agree perfectly and `.claude-next` is behind on seven pairs, three of
which (`coldcompile-admit`, `handed-off-session-guard`, both `session-beat` slots) did not exist in
July. The drift is not decaying; **it is being re-minted by every new hook registration**, because
the registration act writes four files and skips the fifth. `.claude-next` is the busiest account
(bare `claude`), so the dir that runs the most sessions is the one running the fewest rails.

---

## §3 Failure-mode table — every observed mode, and its structural answer

The row's cell reads *"a hook failure must never block a tool by accident."* That half is real but
it is not the binding one. **Proposed cell rename, on the evidence below:**

> **A guardrail that is built, deployed, and registered nowhere is indistinguishable from one that
> does not exist — and reads GREEN. Every rail's presence must be PROVABLE at the point of use, not
> assumed from the fact that it was written.**

This is row 10's ratified duality (*an alarm that always fires and an alarm that cannot fire are the
same alarm*) landing in the dispatch surface. A rename is a first-class outcome on this campaign —
six of the eight closed rows renamed or falsified their cell.

| # | Failure mode | Observed instance | Structural answer |
|---|---|---|---|
| **F1** | **The registration act is not atomic across the five dirs.** Wiring a hook means writing five real files; nothing forces the fifth. | 7 drifting pairs today, all `.claude-next`; 3 of them are hooks that did not exist in July. Was 4 in July — the population *turns over* while the count stays small, so a stable count reads as a stable problem when it is actually a continuously re-minted one. | Registration goes through ONE actuator that writes all five or none (`install.sh --wire-hooks` already merges additively per dir — the gap is that nothing *requires* it), plus F2. Never a per-dir hand edit. |
| **F2** | **The detector for F1 exists, is correct, and is wired to nothing.** | `scripts/settings-drift-assert.sh`: correct, cross-dir, `--selftest`, rc 1 on drift — and 0 live callers in 5 settings.json / 0 plists / 0 cron. It has been right and silent for 18 days. This *is* row 10's R-2 second half. | The checker must run where it can refuse: a `SessionStart` term (cheap, advisory) plus a blocking slot in the land gate. **A checker with no caller is the row's own subject matter applied to itself.** |
| **F3** | **A built-and-deployed hook registered in zero config dirs is invisible.** No count moves, no test reds, no alarm fires. | `hooks/subagent-stop.sh` — on trunk, deployed, referenced by `tests/subagent-stop.bats` — and **no dir has a `SubagentStop` event at all**. Undetected from 2026-07-30 to 2026-08-17. | Existence evidence keyed on the *consumer*, not the artifact: enumerate `hooks/*.sh`, subtract the union of registered scripts, and make the difference an alarm row. An unregistered hook is a defect, not a spare part. |
| **F4** | **A c10 migration that lands is not a rail that runs.** Landing moves a git ref; the operator-gated step is what changes behaviour. | `0013` (unfork) and `0014` (subagent-stop registration) both landed today and **neither has run** — `.claude-next/hooks` is still a 53-entry fork. Both are correctly gated (0013 refuses under live panes; converting under a live pane is unsafe) — the gate is right, the *invisibility* is the defect. | Every c10 migration is a counted row on the operator surface until its effect is observed — and the observation reads the EFFECT (is `~/.claude-next/hooks` a symlink?), never the `.done` marker. |
| **F5** | **A `.done` marker proves the script ran, never that the effect landed.** | `10-lead-crash-orphan-close-activate.sh` ran, wrote its env file, got its `.done`, and is 100% inert because nothing sources that file (`80321b2556e6`, now closed). 11 activations sit un-run today. | Activation health is an EFFECT-read. Env-var-armed activations need a consumer assertion in the same diff, or they escape both existing health axes. |
| **F6** | **The guardrail set a session gets is a side effect of quota routing.** Config dir is chosen BY ACCOUNT at fire time, so *what a session may do depends on which account fired it.* | Any session on `.claude-next` today runs with no unattended-ask guard, no `session-deregister`, no `desk-brief-inject`, no `session-beat`, no `handed-off-session-guard`. Row 7 ran its entire rebuild that way. | This is the row's Scope (frozen) restated as a defect. F1+F2 are its cure; there is no separate mechanism. |
| **F7** | **A landed file that the deploy path ADDS is absent, not merely stale.** Per-file symlinks mean an edit rides its link and runs an older version; an ADD has no link at all, and every consumer guard on it (`[ -f x ] && . x`) is a silent skip. | The FF-GATE (`17ecae6c6`) exists because of exactly this: 42 `merge origin/main` + 8 `pull --ff-only` ungated advances between 2026-08-01 and 08-17, each advancing files and creating no links. `scripts/lib/pane-spawn-log.sh` shipped that way with all 20 call sites inert. | Already answered, landed today: deny the ungated advance at the tool call, route through `scripts/deploy-live.sh` which runs `install.sh` and creates the links. **Row 6's only shipped structural answer so far.** |
| **F8** | **A hook that abstains because a dependency failed is indistinguishable from a hook that passed.** | `tests/hook-jq-abstain.bats` (now on trunk) exists for this: a hook whose `jq` fails exits 0 and the rail silently does nothing. The row's standing constraint in miniature — the ABSENT half, not the blocking half. | Abstention is a third state and must be *emitted*, never collapsed into success. Same law as the `1..N` header vs a `not ok` count. |
| **F9** | **Cost is a correctness property here.** A hook chain is executed by ~30 sessions × every turn. | Row 13 measured the Stop chain at 3688ms/turn before its M3 fix (operator-readout 2711→140ms). The O(N²) broker item (`2193948bb00e`) is closed with its worst term removed by M13. | Any new dispatch-layer term is budgeted in ms/turn × fleet before it is wired. Fail-open + per-hook `timeout` is mandatory, not defensive style. |
| **F10** | **The classifier boundary is asymmetric.** Agents are denied `launchctl enable` but not `bootout`/`disable`. | An agent darked 13 labels on 2026-07-26 (`DAEMON_FLEET_V2` F21). Named as a row-6 permission-layer fact; **not filed as a backlog row.** | A deny list that blocks the constructive verb and allows the destructive one is inverted. Filed here as **R-3**; the fix is a `permissions.deny` term, which is F1's surface. |

---

## §4 Rejected alternatives

1. **Make the five `settings.json` symlinks to one file — REJECTED.** It is the obvious cure for F1
   and it is wrong: the dirs legitimately differ (per-account model/effort/env), and
   `CONSOLIDATION_AUDIT02.md:150` already records that replacing the live real file is the thing
   several assertions depend on *not* happening. The invariant is parity **of the guardrail roster**,
   not identity of the file. Cure the roster, keep the files.
2. **Fix the drift by hand, now — REJECTED as a cure, and deliberately not done by this session.**
   Editing a live `settings.json` is the payload's own worst hazard (a bad `PreToolUse` edit halts
   ~30 sessions), and more importantly it treats a *generator* as an incident: the July drift was
   hand-fixed and seven new rows appeared. Nothing is learned by clearing a counter whose producer
   is untouched.
3. **A nightly cron for `settings-drift-assert.sh` — REJECTED as the primary answer.** It converts a
   silent failure into a delayed one and adds a row to the operator's attention budget without
   changing who can create drift. It is acceptable only *behind* the registration chokepoint (F1),
   as its backstop.
4. **Row 13's PreToolUse Bash admission term — REJECTED, premise falsified.** See A9: the ~30%
   absolute-path residual was a contaminated denominator; clean coverage is 92/92. Row 13's own
   follow-on `0086d70f85c7` is closed. Adding a per-tool-call fork to the busiest hook chain to
   close a hole that does not exist would be a straight regression against F9.
5. **Rebuild the graveyard cherry-picks — REJECTED, already landed.** All five files the payload
   lists as stranded on `fix/infra-perfection` are on trunk today (A7). Doing the payload's Phase 1(c)
   as written would re-land shipped code, which is the exact failure the STEP -1 law exists to
   prevent.

---

## §5 Acceptance criteria as disk-truth reads

Each is a command whose output is the verdict. All currently FAIL except AC5, which is why this doc
is `status: OPEN`.

| AC | Read | Passes when | Today |
|---|---|---|---|
| **AC1** parity | `bash scripts/settings-drift-assert.sh; echo $?` | `0` | **FAILS** — rc 1, 7 divergences |
| **AC2** the checker is not inert | `grep -l settings-drift-assert ~/.claude*/settings.json ~/Library/LaunchAgents/*.plist \| wc -l` | `≥1` | **FAILS** — 0 |
| **AC3** no unregistered hook | enumerate `hooks/*.sh` minus the union of scripts registered across the five dirs | empty, or every member explicitly declared non-dispatch | **FAILS** — `subagent-stop.sh` is the known member; the full set is unmeasured |
| **AC4** `.claude-next` is not a fork | `[ -L ~/.claude-next/hooks ]` | true | **FAILS** — real dir, 53 vs 78 entries; cure landed (`0013`), operator-gated, un-run |
| **AC5** ungated advance is denied | `bats tests/validate-bash-ff-gate.bats` | green | **MET** — landed `17ecae6c6` |
| **AC6** permission-rail parity | `python3 -c` deny/ask counts across five dirs | all equal | **MET** — 41/6 everywhere |

**Instrument discipline that these reads assume**, each of which has produced a wrong verdict for
someone on this campaign: use `git ls-tree "$b" -- "$p"`, never `"$b:$p"` interpolation (zsh eats
`:h`/`:t` as glob modifiers and `hooks/` is the worst-hit prefix); every absence assertion gets a
positive control sharing the first path segment's initial letter (used here: `hooks/dod-persist.sh`
and `tests/no-such.bats`); never read an exit code through a pipe, and reconcile the `1..N` header —
a missing verdict is a third state, not a pass.

---

## §6 What this doc does NOT do — the remainder the successor inherits

**This session landed the reconciliation and this design. It did not build anything.** The payload's
four-item DoD is 1 of 4 complete:

| DoD item | State |
|---|---|
| 1. design doc, four load-bearing sections | **DONE** — this file |
| 2. adversarially proven to the skill's Phase 4 bar | **NOT STARTED** — no new mechanism exists to prove |
| 3. landed continuously via project-local `/ship` | **NOT DONE** — committed on a branch |
| 4. `GROUND_UP_REBUILD_MAP.md` row 6 updated | **NOT DONE** — see below |

Named remainders, in the order a successor should take them:

- **R-1 (the row's whole point).** F1+F2: make hook registration atomic across the five dirs and
  give `settings-drift-assert.sh` a caller. Everything else in §3 is downstream. Note the hazard
  block — never edit a live `settings.json` as an experiment; copy a config dir and exercise there.
- **R-2 (row 10's R-2, second half, inherited).** No alarm covers a hook's own wiring. First half
  (`operator-readout` in 4/5) is now MET; the alarm half is R-1's AC2.
- **R-3 (new, from `DAEMON_FLEET_V2` F21).** Agents are denied `launchctl enable` but permitted
  `bootout`/`disable` — an inverted deny list that darked 13 labels once. Not filed as a backlog row
  anywhere; it is a `permissions.deny` fix and therefore row 6's.
- **R-4 (operator-gated, not agent work).** Migrations `0013` and `0014` are landed, correct, and
  un-run. Until `0013` runs, `.claude-next` keeps re-minting F1 drift; until `0014` runs,
  `hooks/subagent-stop.sh` stays a hook that exists and does nothing.
- **R-5.** The map's row-6 cell still carries the falsified `69 hook entries` figure and the "no
  design doc" status. Correcting it needs `GROUND_UP_REBUILD_MAP.md`, which is a shared file — a
  separate, single-owner edit.

**And the campaign-level statement row 6 owes, since there is no row after it:** the guardrail layer
is the campaign's last row precisely because it is everyone else's enforcement surface, and what
this reconciliation found is that the enforcement surface's own failure mode is *inertness, not
incorrectness*. Every mechanism examined here — the parity checker, the subagent-stop hook, the two
migrations, the activation markers — is **correct and does nothing**. Nothing in the campaign's
existing health axes can see that, because a mechanism that is registered nowhere emits no signal at
all, and no signal reads as green. That is the one structural property the remaining build must
answer, and it is not specific to hooks.
