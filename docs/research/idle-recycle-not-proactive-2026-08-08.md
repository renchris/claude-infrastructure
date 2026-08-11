# Why proactive idle self-recycle never fires — root cause, 2026-08-08

**Subject.** Session `a64e4989-10f1-45d9-96e3-df04680553a1` ran a long turn-heavy session in
`~/Development/claude-infrastructure`, climbed from 31% to 75% context, went idle at the prompt
repeatedly, and never self-recycled — against CLAUDE.md § Context Stewardship, which calls an idle
session at ≥35% a "free win" that should `/handoff` immediately.

**Scope (frozen):** root-cause the silence; deliver file:line evidence, a one-line statement of the
binding suspect, and either the fix or a named blocker. Explicitly NOT a redesign of the
context-economy policy (settled — `docs/plans/CONTEXT_ECONOMY_V2.md`).

---

## The one-line verdict

> **Suspect 1 binds.** The ≥35% idle free-win tier is implemented in exactly one place —
> `hooks/waiting-recycle.sh` — and for session `a64e4989` that hook abstained on **85 of its 88
> evaluations** at `hooks/waiting-recycle.sh:530` (`disarmed`), because a durable, never-expiring
> `clear` marker keyed on **(CLAUDE_CONFIG_DIR, cwd)** — written `2026-07-31T17:58:44Z` — silences
> whichever account a session happens to launch on. Behind that gate sit two more closed doors, so
> removing the marker alone would not have fired it either.

Three gates, all shut, each independently sufficient:

| # | Gate | Evidence | Would removing it alone fix it? |
|---|---|---|---|
| A | `disarmed` — durable per-(config-dir, cwd) opt-out, **no TTL** | `waiting-recycle.sh:530`, written at `:388`, removable only by an explicit `arm` at `:365` | **No** → falls through to B |
| B | `not-armed` — no arm sentinel, and arm-by-default is dead | `waiting-recycle.sh:535`; `is_monitoring_desk()` `:216` reads `cc-roles/$DESK_ROLE`, `DESK_ROLE` defaults to `desk` at `:205` — **`~/.claude/cc-roles/` contains only `orchestrator`; there is no `desk` file**, and nothing in the repo sets `CC_WR_DESK_ROLE` | **No** → still blocked by C for the operator's stated framing |
| C | Wrong event — registered **`PostToolUse` matcher `Bash` only**, never `Stop` | verified in all five `settings.json` (`~/.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`) | — it structurally cannot fire at idle-at-the-prompt |

Gate B is the memory pattern `liveness-free-channel-never-gated-behind-liveness` recurring exactly:
`cc-roles/desk` was **removed** because it held a dead pane uuid, and its removal silently disabled
the arm-by-default channel that a different consumer depended on.
`scripts/autonomy-sweep.sh:253-256` documents the removal reason in its own words: *"No desk
orchestrator runs here. cc-roles/desk holds an iTerm2 pane uuid from 2026-07-26 whose pane has
self-closed…"*. Nothing connected that cleanup to `waiting-recycle`'s arm gate.

---

## The arm/disarm matrix — a recycle lottery on account routing

`STATE_DIR` is `$CLAUDE_CONFIG_DIR/state/waiting-recycle` (`waiting-recycle.sh:202`) and every
cwd-keyed sentinel hashes `"$CFG|$cwd"` (`key_cwd()`, `waiting-recycle.sh:~288`). So the *same
working directory* carries **five independent arm states**, one per account:

| account (`CLAUDE_CONFIG_DIR`) | sentinel key | state for `~/Development/claude-infrastructure` |
|---|---|---|
| `~/.claude` | `df1308af96473054` | ARM + LIVE |
| `~/.claude-next` | `1c24a7da26668012` | **DISARM `2026-07-31T17:58:44Z`** |
| `~/.claude-secondary` | `2d9f60a8100434b6` | **DISARM `2026-07-30T05:58:09Z`** |
| `~/.claude-tertiary` | `e181330604ffe33f` | ARM + LIVE |
| `~/.claude-quaternary` | `cddcfbe2e938785c` | ARM + LIVE |

Session `a64e4989` ran on `.claude-next` (`config_dir` in its telemetry) and therefore drew a
disarmed slot. **Whether a session can self-recycle is decided by which account the router handed
it at launch** — invisible to the session, to the operator, and to every readout. A `clear` typed
once in one pane silences that account for that directory forever.

Note `~/.claude-next/state` is a symlink to `~/.claude/state`, so those two accounts share one
store while `-secondary`/`-tertiary`/`-quaternary` keep their own. The key still carries the config
dir, so sharing the store does not share the arm.

### Reproduced live

Running the deployed hook directly with a realistic `PostToolUse` payload (`CC_WR_IDL` to a scratch
file), varying only `CLAUDE_CONFIG_DIR`:

```
A) CFG=.claude-next       cwd=claude-infrastructure  → abstained  reason=disarmed      ← exactly a64e4989
B) CFG=.claude            cwd=claude-infrastructure  → abstained  reason=below-threshold-no-tell  (gate PASSED)
C) CFG=.claude-secondary  cwd=claude-infrastructure  → abstained  reason=disarmed
D) CFG=.claude-quaternary cwd=<a fresh worktree>     → abstained  reason=not-armed     ← the ordinary builder
```

Row B is the control: the identical directory clears the arm gate and reaches the threshold check
under a different account.

---

## Suspect-by-suspect

### 1. `hooks/waiting-recycle.sh` — **BINDING** (and yes, desk-role-gated)

Confirmed above. Two further facts matter:

- The disarm has **no expiry**. Written at `:388`, it is deleted only by an explicit `arm`
  (`:365`). There is no TTL and no re-prompt. `status` reports it (`:393`) but nothing runs `status`.
- Even fully armed, Stage-2 (the deterministic recycle exec) requires a `live-<key>` sentinel
  (`:1112`); absent → SHADOW, which logs a would-fire and does not recycle. Stage-1 (the advisory)
  would still have fired, which is the outcome the operator wants at minimum.

### 2. `hooks/boundary-handoff.sh` — **REFUTED as inert; it is simply the wrong tier**

The plan's hypothesis was that it rides the inert `additionalContext` channel. It does not: **[STALE as of 2026-08-08 — measured on 2.1.220, Stop `additionalContext` DOES reach the model; it forces a turn like `decision:block`, so every conclusion below still stands. See docs/research/final-response-shaping-2026-08-08.md]**
`boundary-handoff.sh:394` emits

```
jq -nc --arg r "$reason" '{decision:"block",reason:$r,systemMessage:$r}'
```

— the same `decision:"block"` actuator `session-continue.sh` uses, and its own header at `:21`
records why (`additionalContext is inert/probe-gated on 2.1.207`). It is registered on `Stop` in all **[STALE as of 2026-08-08 — measured on 2.1.220, Stop `additionalContext` DOES reach the model; it forces a turn like `decision:block`, so every conclusion below still stands. See docs/research/final-response-shaping-2026-08-08.md]**
five config dirs and it **did** evaluate for `a64e4989` — 21 IDL rows, every one
`abstained: below-threshold:NN<73`, climbing `37 → 38 → 39 → 49 → 50 → 52 → 53 → 54 → 55 → 57 → 59
→ 60 → 61 → 66 → 67 → 70`. Threshold `T=73` (`boundary-handoff.sh:88`); the session peaked at 71%
before the recycle. It abstained **correctly on every single evaluation**.

The finding is structural, not behavioural: `boundary-handoff` implements the ≥73%
*committed-and-green forced-drain* tier. **The ≥35% idle free-win tier has no Stop-side
implementation at all.** That is the named blocker below.

### 3. Fill measurement — **not causal here**, but the failure direction is silent-open

The denominator was never missing. `/tmp/cc-telemetry/a64e4989-….json` carries
`"window":1000000,"used_pct":75,"input_tokens":750639`, and the `.hist` sidecar holds 27 rows
tracking 31% → 70%. Both hooks read a healthy telemetry file throughout.

The direction is still worth naming: on a genuine miss, `boundary-handoff.sh:180`
(`[ -f "$tel" ] || abstain "no-telemetry"`) and `:187` (`stale-telemetry`) **abstain** — i.e. never
fire. Blindness ships as the quiet path (`sensor-default-off-makes-blindness-the-shipping-path`).
Not this incident's cause; a real hole for a post-reboot fleet, where `/tmp/cc-telemetry` is wiped.

### 4. `hooks/session-continue.sh` — **nobody wired it, and nothing prevents it**

It proved the channel live *in this very session*: IDL carries
`session-continue armed:mechanical-dirty`, `fired:continue`, `cleared:cli-clear` for `a64e4989`. And
`boundary-handoff` already uses the identical `decision:"block"` channel at Stop. So the actuator is
available and proven — there is no technical reason the idle tier cannot use it. The answer to
"why doesn't the recycle path use it?" is plainly: **nobody wired it.** The tier exists only in a
hook registered on the wrong event.

---

## The observability defect — why this survived 8 days unnoticed (FIXED)

`scripts/idl-abstain-alarm.sh` is the monitor built for exactly this failure ("a check whose whole
job is to FIRE but which ABSTAINS 100% of the time is indistinguishable from a DEAD check"). Over
the 14-day window it saw **waiting-recycle: 2,868 records, 2,864 abstained, 0 fired** — 2,291
`not-armed` + 573 `disarmed` — and reported it **`HEALTHY`**, the same verdict a firing hook gets.

Cause: `total` counted *every* record carrying `.hook` and `.disposition`, while both verdicts that
can report a problem require `abst == total`:

```
if   total >= NMIN && abst == total && pct >= BLIND_PCT ; then INERT
elif total >= NMIN && abst == total ;                    then DORMANT-100
else                                                          HEALTHY
```

`waiting-recycle` also emits four `disposition:"gc"` housekeeping rows (its `gc_bats_pollution`
fixture sweep — not an evaluation of anything). Four such rows broke the equality and dropped a
zero-fire hook into `HEALTHY`. The `productive` column was already correct (`fired/passed=0`) — the
numerator was right and the **denominator** was wrong (`positive-control-the-denominator`,
`new-enum-member-falls-into-fail-closed-default`).

**Fix landed.** `total` now counts evaluations only — the four dispositions the shipped contract
names (`premortem-gate.sh:90`, *"every check ships emitting {fired|passed|abstained|failed}"*).
Strictly tightening: nothing previously INERT or DORMANT-100 can become HEALTHY through it, and a
hook with no evaluations leaves the table rather than posing as healthy.

Verified: selftest cases **M** (a `gc` row must not launder DORMANT-100 into HEALTHY) and **N** (the
dangerous direction — a `gc` row must not launder a genuinely INERT hook green) were **provably RED
before the change and green after**; 29/29 selftest, 11/11 bats, shellcheck clean. Live post-fix:

```
DORMANT-100 waiting-recycle  total=2926  abst=2926  fired/passed=0  failed=0  blind=0  (0%)
idl-abstain-alarm: GREEN — hooks=7 inert=0 dormant100=3 healthy=4 window=14d
```

Exit 0 — it surfaces the hook for review without paging (blind=0, so not INERT). Three hooks that
emit only lifecycle rows and never evaluated anything (`capacity-admit`, `session-register`,
`worker-claim-gate`) correctly dropped out of the table rather than counting as healthy.

`tests/idl-abstain-alarm.bats:25` also pinned an exact `-eq 25` check-count and went red on the
suite's own growth; converted to floor + tally (`exact-count-assertion-tripwires-its-own-subject`).

---

## Named blocker — the idle free-win tier has no Stop-side carrier

> **CLOSED 2026-08-11 — and the premise below was already false when this was written.** The carrier
> exists: `hooks/boundary-handoff.sh` shipped the ✅-ledger **free-win arm** (`T_FREEWIN`, default 35)
> on **2026-08-03** in `ab6d3d1e` — five days BEFORE this report claimed the tier had "no Stop-side
> implementation at all". The claim was not a bad inference from the evidence; it was a stale reading
> of the subject, and the evidence could not contradict it because **the arm had never fired**: the
> `gate-not-green-at-head` abstain sat upstream of it, and only the background `postland-verify`
> daemon can advance that marker, so the whole rail was unfireable (1,341 evaluations / 296 sessions /
> zero fires). This report's own §2 read the hook's threshold as 73 and stopped there. Lesson, in this
> repo's own vocabulary: *an inert mechanism is indistinguishable from an absent one* — a hook that
> cannot fire will read as unbuilt no matter how carefully you grep its source
> (`spec-named-mechanism-may-be-prose-only`, inverted — here the mechanism was real and the prose was
> the thing that lagged).
>
> Resolution timeline, all landed:
> - `ab6d3d1e` (08-03) — the arm itself, keyed on `RUNG=✅` rather than the bare fill number this
>   report proposed. The stronger predicate: ✅ *is* CLAUDE.md's Recycle test, mechanically.
> - `57d8c4dd` (08-11) — gate-green demoted from gate to reported field, in this hook and in
>   `wrap-ledger.sh`. This is what made the arm reachable at all.
> - `af66a60b` (08-11) — the arm fired under the **forecast tier's name**: it set the shared `early`
>   flag, so a 41% fire narrated itself "BURNING toward the wall — forecast ≤-1min at the observed
>   rate" (`-1` = the UNKNOWN sentinel) and recorded `axis:"forecast"`. Now its own axis, its own
>   free-win wording (`handoff-fire.sh --recycle`), S6 conversation-hold **suppressing** at this tier
>   rather than re-wording, and `FREEWIN_RUNG` on the abstain so a declining ledger stops being
>   byte-identical to a dead arm.
>
> Proposal items 1–4 below map onto what shipped: **1** = `T_FREEWIN` (with the ✅ predicate replacing
> the bare threshold), **2** = shipped in `af66a60b`, **3** = shipped in `af66a60b`, **4** = the damping
> is the ✅ predicate + the B-2 latch rather than an env kill-switch; the arm defaults ON at 35 and is
> disabled with `CC_BOUNDARY_T_FREEWIN=0`. The **secondary items** at the end of this section are
> untouched and remain open.
>
> **Verified at close (2026-08-11), backlog `bd2f7c2209fa`.** Executed rather than re-read: 35/35
> `tests/boundary-handoff.bats` green, shellcheck `-x` clean. Ten of those cases are the arm itself —
> it fires at 43% on a ✅ ledger, stays silent at 34% (floor) and on a 🔧 dirty tree, says FREE WIN and
> names `--recycle` (not the drain wording), records `axis:"freewin"` with `early:false` and the rung
> that authorised it, leaves the forecast tier's own attribution intact, and is SUPPRESSED (not
> re-worded, and without burning the latch) by a live exchange. Case 65 is the PREMISE control: it
> fails loudly if the fixture repo stops computing ✅, so the fire cases cannot pass vacuously.
> Live layer at close: 11 commits / 4h behind, inside the converge budget (25 / 6h), and `af66a60b`
> is an EDIT — it rides its per-file symlink and merely runs the older wording until the
> fast-forward. No `LIVE_ADDS` breach on this hook.
>
> **The item's own remedy had rotted, and the literal reading was the wrong build.** Item
> `bd2f7c2209fa` prescribed "damped env-gated `CC_BOUNDARY_T_IDLE` … reusing its clean-tree/**gate-green**
> /no-teammates gates". Both halves were stale by the time a worker read them: the knob shipped as
> `CC_BOUNDARY_T_FREEWIN`, so building `CC_BOUNDARY_T_IDLE` would have minted a second name for one
> switch — and `gate-green` was DELIBERATELY DEMOTED from gate to reported field in `57d8c4dd`,
> because gating on a stamp only `postland-verify` can advance is what made this rail unfireable for
> 1,341 evaluations. Implementing the remedy as written would have re-introduced the defect the item
> exists to fix (`work-item-remedy-can-become-forbidden`). Its falsifier — `grep -q CC_BOUNDARY_T_IDLE
> hooks/boundary-handoff.sh` — names a symbol that must never exist, so it can only ever CONVICT;
> harmless only because `cc-backlog` re-runs a falsifier on the claim path alone, which a done-latched
> row never reaches (`bin/cc-backlog:1855`).

**Not built here.** It is a fleet-wide behaviour change to when every session is blocked at Stop,
which is larger than a safe in-actuator fix, so it is specified rather than shipped.

**The gap.** `waiting-recycle` owns the ≥35% idle tier but runs on `PostToolUse:Bash` — i.e. mid-turn
while the agent is *working*, never at the boundary the operator actually names ("it has returned,
finished its prompt, and is idle waiting on the user"). `boundary-handoff` owns Stop but starts at
73%. Between 35% and 73%, an idle session at a clean committed boundary is seen by nothing.

**Proposed change.** Add a second, lower trigger to `boundary-handoff.sh` — the hook that already
runs at Stop, on all five config dirs, through a proven actuator, under a latch that prevents
looping:

1. `T_IDLE` (default 35) as a second threshold beside `T=73`, firing **only** when the gates it
   already enforces all hold — clean tree (`:304`), gate-green at HEAD (`:306`), no live teammates
   (`:311`), fresh telemetry (`:180`,`:187`). Those *are* the "idle and safe" conditions.
2. Suppress under the context-econ **S6 conversation-hold** so it cannot cut a live operator
   exchange (the signal already exists in `hooks/lib/context-econ.sh`; `boundary-handoff` already
   consumes it for wording at `:392`).
3. Wording is the free-win advisory (`/handoff` → `handoff-fire.sh --recycle`), not the forced drain.
4. Ship **damped**: env-gated off by default (`CC_BOUNDARY_T_IDLE=0`), soak the IDL, then enable —
   the same damp-first discipline `waiting-recycle` Stage-2 used.

**Risk to weigh before enabling:** at 35% with a +10% re-arm latch this fires far more often than
the 73% tier. The latch and the committed+green+clean gates are what keep it from becoming noise;
that ratio is what the soak is for.

**Secondary items** (smaller, independent, not built):

- **Arm state is account-partitioned but the session's account is chosen by the router.** Arming a
  desk does not survive a relaunch onto a different account. Either key the sentinel on cwd alone,
  or have `arm` write all five — both are migrations with a real blast radius (a cwd-only key would
  also propagate the two existing disarms to every account, which is worse).
- **`disarm` has no TTL and no visibility.** An opt-out that outlives by 8+ days the session that set
  it, with nothing surfacing it, is indistinguishable from a broken hook. The fix landed above at
  least makes the *aggregate* silence visible; the per-cwd disarm still is not.
- **`cc-roles/desk` is absent** (only `orchestrator` exists), so `waiting-recycle`'s arm-by-default
  and `hooks/desk-brief-inject.sh:40` (`ROLE="${DESK_BRIEF_ROLE:-desk}"`) are both dead consumers of
  a role file that was deliberately removed. Two mechanisms silently keyed on a file a cleanup
  deleted; neither fails loud.

---

## Evidence index

| Claim | Source |
|---|---|
| 85 `disarmed` + 3 `not-armed` for `a64e4989` | `~/.claude/autonomy/idl.jsonl` |
| 21 `below-threshold:NN<73`, peak 70 | same |
| telemetry complete, `window:1000000` | `/tmp/cc-telemetry/a64e4989-….json` + `.hist` |
| disarm marker + timestamp | `~/.claude/state/waiting-recycle/disarm-1c24a7da26668012` |
| key derivation | `waiting-recycle.sh:202` (STATE_DIR), `key_cwd()` |
| arm/disarm gates | `waiting-recycle.sh:530`, `:535`, `:365`, `:388` |
| desk-role arm | `waiting-recycle.sh:205`, `:216`; `~/.claude/cc-roles/` listing |
| registration, all 5 dirs | `settings.json` × 5 |
| Stop delivery channel | `boundary-handoff.sh:394` |
| threshold 73 | `boundary-handoff.sh:88` |
| telemetry abstains | `boundary-handoff.sh:180`, `:187` |
| Stop actuator proven live | IDL `session-continue armed/fired/cleared` @ `a64e4989` |
| desk role removal rationale | `scripts/autonomy-sweep.sh:253-256` |
