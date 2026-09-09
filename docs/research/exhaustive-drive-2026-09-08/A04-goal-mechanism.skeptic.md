# A04 — SKEPTIC pass on "Is /goal working, and should every session carry one"

Wave: exhaustive-drive 2026-09-08. Read-only. Re-measured 2026-09-08 22:20–22:45Z against the same
binary (2.1.260 @ `/Users/chrisren/.claude-260/…/claude.exe`), the same four transcript roots, and the
live IDL (which has grown since the axis ran; deltas noted).

## Headline

The axis's **verdict survives**: `/goal` is a terminator, not a drive loop, and its arm-then-never-
evaluate rate is real (re-ran the census: 434 of 641 runs; unmet evaluations ARE persisted, so "0
evaluations" is an observation, not an artifact). **Two load-bearing claims do not survive:**

1. **"No programmatic arming path exists" is FALSE as a statement about the binary.** 2.1.260 ships a
   model-callable tool **`ProposeGoal`** (`var MSt="ProposeGoal"` @159557655) whose `ask_user:false`
   path enqueues `/goal <condition>` onto the message queue with **no TUI paste and no dialog**
   (`proposal_direct`, @79664916 region). It is gated by GrowthBook flag `tengu_propose_goal`
   (`function mct(){return I("tengu_propose_goal",!1)}` @172100409 — **default OFF**), by the settings
   key **`modelProposedGoals`** (`disabled | alwaysAsk | <permissive>`; managed-policy treats
   `disabled`/`alwaysAsk` as the restrictive values @156741085), and refused in agent contexts and
   non-interactive sessions. Measured usage: **0 of 6,142 transcripts** (30 d, 4 roots) contain a
   `"name":"ProposeGoal"` tool_use, and no flag cache on this box shows the flag on. So the axis's
   *operational* conclusion (auto-arm is not achievable here today) holds — but for a different,
   perishable reason (a remote flag), and R2's reason (1) needs rewording: a SessionStart hook's
   `additionalContext` CAN reach the goal registry *through the model* once that flag flips.
2. **§2.4 "The Stops were happening — median 476 Stop-hook instants after arming" is an instrument
   artifact.** `goalstop.py` counts EVERY IDL row for the sid, not Stop-hook rows. For the axis's own
   in-hand example (the wave lead `b418b97a`) the IDL holds 1,196 rows, of which **1,135 are
   `waiting-recycle`, a PostToolUse hook** (`jq '.hooks|to_entries[]|select(.value|tostring|
   test("waiting-recycle"))|.key' ~/.claude/settings.json` → `PostToolUse`). The Stop-chain hooks
   show **5–6 rows each**, i.e. the lead had ~6 Stops after arming, not 476. And the lead's transcript
   **does carry the 2.1.260 check-in** — twice, at 22:14:36Z and 22:17:53Z (`isMeta:true`, "Goal
   check-in: «improve our Claude Code…»"), 54 min after the 21:20:36Z arm — the axis measured before
   the 30-min timer had elapsed. The "unresolved residual: which branch swallows the evaluation" is,
   for the one case in hand, **resolved in favour of the documented branch**: deferred behind the
   wave's own subagent tasks (`d2n` non-empty), check-in fired as designed. Nothing in the data
   requires the silent `evaluator_timeout`/`evaluator_error` branches.

Corollary to (2): the axis's "PARTIAL REFUTATION of the background-work explanation" is weaker than
stated. Its decorrelation keyed on *background bash present anywhere in the transcript*, a proxy for
"non-terminal task in the registry at the instant of each Stop". The in-hand case shows the standing
explanation (deferral behind registry tasks — here `local_agent` subagents, not bash) operating
exactly as `goal-inert-watch.sh`'s header describes.

## Re-checks, per recommendation

| Rec | Re-ran | Result |
|---|---|---|
| R1 pipefail inversion | synthetic fixtures under `set -uo pipefail` sourcing the live lib | `nogoal.jsonl` → rc=1 ONLY under pipefail (rc=0 `absent` without); `live.jsonl` → rc=0 `live 0 arm`; `prose.jsonl` → rc=0 `absent`. Mechanism at `goal-state.sh:38,84` + `goal-inert-watch.sh:90,177` confirmed. IDL now: 428 goal-unreadable / 75 absent / 41 cleared / 8 damped / 4 blind / 3 named (was 375/75/36/2/3/2). `idl-abstain-alarm.sh:117-119` `_default_blind` lacks `goal-unreadable` — confirmed. **HOLDS.** |
| R2 do-not-auto-arm | binary greps (CLAUDE_CODE_GOAL=4 all CHECKIN_MINUTES; set_goal/setGoal=0; `"--goal"`=1) — hold. **But** `ProposeGoal` exists (above). Cost claim "~901 evaluator calls/day" is inferred (fleet close count × 1), not measured; and the evaluator only runs when NOT deferred, so it overstates. | **Conclusion holds, reason (1) refuted; conviction down.** |
| R3 session-continue primary | `jq 'select(.hook=="session-continue")|.reason'` → 293 cli-set · 238 continue · 27 wake-floor · 58 ship-floor-not-mine (matches). `wake-floor-goal-live` = 0. | **HOLDS**, with a fail-direction note the axis under-weights: session-continue's `decision:block` is exactly the nag-on-legitimate-stop mechanism; it already fires 238×/13 h. |
| R4 shorten template | `goalorigin.py` → 21.6% / 53.8% / 82.1% reproduced. Confound acknowledged by the axis; a second unnamed confounder: freehand goals are typed by a human who is present to *also* stop the session, so "evaluated" partly measures "session was short and interactive". | **Not refuted, not supported** — stays an experiment. |
| R5 re-anchor goal-inert-watch | header cites 2.1.231 `kFe||vKo` (`goal-inert-watch.sh:4-10, 50-66`) — confirmed stale. Check-in count re-measured: **15 transcripts** (axis: 11; grown). The check-in string IS a free exact signal. | **HOLDS**, and (2) above makes it more valuable: the lead's own case is a two-state "CC said deferred". |
| R6 auto-clear + resume | `tengu_goal_restored_on_resume`=2 hits, `origin:"restored"`=1; CLAUDE.md:185 (both copies) carries "A goal also dies with its session". | **HOLDS.** |

## House-rule checks

- *Alarms that always fire*: R1 removes a 428-row always-firing mislabel — good. R3 risks the
  opposite (session-continue already blocks 238×/13 h; making it "primary" without a nag-rate
  measurement is the always-fires shape). Neither recommendation measured how often session-continue
  blocks a stop the operator would have accepted.
- *Positive control that cannot fail*: `goalstop.py` had none — a Stop-only filter (`hook in
  Stop-chain set`) would have caught the PostToolUse inflation immediately.
- *Count read as content*: "476 Stop instants" was a count of rows, read as a count of Stops.
- *Gate keyed on its own signal*: none of R1–R6.

## What the axis MISSED that the question required

1. `ProposeGoal` + `modelProposedGoals` + `tengu_propose_goal` — the binary's own answer to
   "should every session carry one": Anthropic built model-initiated goals, default-off, with an
   explicit "propose only when the user asked for a verifiable end state spanning multiple turns"
   rule and a 500-char cap (`NSt=500`). That cap is itself evidence for R4's direction.
2. A Stop-only denominator for "Stops after arming" (above).
3. The deferral is keyed on the **task registry**, and this wave's own shape (12 subagents) defers
   the lead's goal for the wave's whole duration — so "should the lead carry a goal" has a
   measured answer for fan-out leads: it will be deferred, then check in at 30/60/120 min.
4. Whether `stop_hook_active` / a command hook's `decision:block` interacts with the prompt-hook
   evaluator (does session-continue's block starve the goal?). Not resolved here either
   (`stop_hook_active` has 5 hits in the binary; contexts not read within this pass's budget).
5. The 901-vs-469 closes gap the lead flagged is unaddressed by the axis and untouched here.

## Commands (all measured this pass)

- fixtures + `probe.sh` in `scratchpad/skeptic/` — pipefail reproduction.
- `python3 goalstale.py | goalanalyze.py | goalorigin.py | goalver.py` over the axis's `goalsess.json`
  (re-run, same numbers) + a new check: `('eval','unmet')=713` records; `iterations == counted evals`
  on 154/154 met goals.
- `find … -mtime -30 | realpath | sort -u` → 6,142 files; `xargs -n200 -P4 env LC_ALL=C /usr/bin/grep
  -a -l -F` → 626 `"type":"goal_status"`, 15 check-in, 0 `"name":"ProposeGoal"`. (Two earlier passes
  returned 0/0/0 — GNU `xargs -a` and a bare `LC_ALL=C` as the xargs command — kept as a reminder that
  a zero from a pipeline needs a positive control; the third pass carried one.)
- IDL: `jq -r 'select(.sid=="b418b97a-…")|.hook' | sort | uniq -c` → 1135 waiting-recycle, 6
  goal-inert-watch, 6 completion-assert, 5 operator-readout…
- lead transcript: `grep -a -F 'evaluation has been deferred for' | jq '{ts,isMeta}'` → 22:14:36Z,
  22:17:53Z.
- binary: `python3 re.finditer` windows at 79664916, 159557655, 172100409, 156741085, 175036804.

## Addendum (results that landed after the body was written)

- **Flag cache:** a `find` over the four config dirs (depth ≤4, excluding projects/tasks/backups/logs)
  for any file containing `tengu_propose_goal` returned **nothing** — the live value of the
  `ProposeGoal` gate is not readable from disk on this box; "default OFF + 0 uses in 30 d" is the
  whole of the evidence.
- **`stop_hook_active` (5 hits, all read):** it is a payload field (`stop_hook_active:o` in the Stop and
  SubagentStop inputs @165475379) and the cap message text; the consecutive-block cap telemetry carries
  `goal_active:zf` @164402407, confirming the goal's own blocks share the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`
  counter with command hooks (CLAUDE.md already states this). **No branch skips the prompt-hook
  evaluator on `stop_hook_active`** — so session-continue's blocks do not starve the goal by that route.
  MISSED item 4 in the body is thereby narrowed, not closed: the two mechanisms compete only for the cap.

---

## SECOND SKEPTIC PASS (2026-09-08 23:30–23:55Z) — the Stop-occasion decomposition

Independent re-measurement; the first pass above was found only after this one had run, and the two
agree on the pipefail bug, the `goalstop.py` PostToolUse inflation, the lead's check-ins and
`ProposeGoal` (independently confirmed: `grep -a -c -F` on the binary → `ProposeGoal` 13 ·
`tengu_propose_goal` 2 · `modelProposedGoals` 6). What this pass ADDS is the denominator the axis's
headline lacks: **did the goal ever get a Stop to evaluate at?**

### The headline "67.7% armed and never evaluated" conflates two populations

`skep/goalturns.py` + `goalafter.py` + `goalsr.py` + `goalcond.py` (scratchpad
`b418b97a-…/scratchpad/skep/`), over the axis's re-run `goalsess.json` (census re-run this pass:
6,214 transcripts · 811 with the string · 626 with an attachment · 642 runs · 434 dead-never-evaluated
· median iterations 1 · 2.1.260 n=40 / 72.5% — all of the axis's numbers reproduce).

Counting assistant records with `"stop_reason":"end_turn"` AFTER the arm record (the transcript's
turn-end marker; validated on the lead — 10 end_turn in file vs 27 distinct-second Stop-hook IDL
instants from 7 hooks; stop_reason vocabulary across all 434 dead sessions is `tool_use` 84,299 ·
`end_turn` 935 · `stop_sequence` 69 · **null/absent 0**, so the proxy has no blind stratum):

| population | n | note |
|---|---:|---|
| dead never-evaluated goal sessions (axis's 434) | 434 | |
| … with **ZERO** end_turn after arming | **371 (85.5%)** | the session never completed a turn after `/goal`; 364 of 371 have ONLY `tool_use` stop_reasons after the arm; median 147 assistant records after arm — **active, then dead mid-turn** |
| … with ≥1 end_turn and 0 evaluations | 63 (14.5%) | median 7 end_turns; 56 carry `Stop hook feedback` — the TRUE "a Stop happened and the goal stayed silent" population |
| … carrying a 2.1.260 check-in | 6 | |

Over all 640 runs with a locatable arm (`goalcond.py`):

| stratum | n | ≥1 evaluation |
|---|---:|---:|
| ALL | 640 | 28.4% |
| no end_turn after arm (no Stop occasion) | 376 | **0.0%** (by construction) |
| **≥1 end_turn after arm (had a Stop)** | **264** | **68.9%** |
| ≥3 end_turn after arm | 148 | 54.7% |

So: **given an occasion, the evaluator ran 69% of the time.** The 31% residual (82 runs = 12.8% of all
runs) is the deferral/silent-branch population; the other 59% of all runs are goals on sessions that
died inside the turn the goal was armed into. The axis read a *no-occasion* number as an
*evaluator-failure* number.

**Fail direction of this correction:** it errs toward EXONERATING `/goal`. Whether "died mid-turn"
is itself a defect (a dispatched session that `--recycle`s itself from inside a turn never Stops, so
a Stop-time lever cannot act on it — the same holds for `session-continue`) is inferred, not
measured: I did not read WHY those 371 turns never ended (recycle chain · limit · crash · kill).

### R4 is REFUTED, not "an experiment"

The template/freehand gap is entirely session-type. `goalcond.py`:

| stratum | n | ≥1 evaluation |
|---|---:|---:|
| had a Stop · template ("proven by") | 164 | **69.5%** |
| had a Stop · freehand | 100 | **68.0%** |
| had a Stop · freehand ≤200 chars | 29 | 79.3% (n=29; 3 goals of difference) |
| ≥3 Stops · template / freehand | 82 / 66 | 56.1% / 53.0% |
| share of runs with ZERO Stop occasion — template / freehand | | **68.4% / 17.4%** |

Template goals evaluate exactly as often as freehand ones once the session reaches a Stop. Shortening
the condition would change nothing measurable; the axis's own named confound IS the whole effect.
(The first pass's `NSt=500` cap observation is about `ProposeGoal`'s proposal text, not evidence that
short conditions evaluate more.)

### Other re-checks this pass

- **R1** reproduced on synthetic fixtures (`nogoal` rc=1 under pipefail, rc=0 `absent` without;
  `corrupt` rc=1 either way, so the "grep succeeded / jq failed" rc survives the fix). Live IDL now
  449 goal-unreadable / 593 goal-inert-watch rows over **57** sids; **54 of 56** resolvable
  transcripts contain zero `goal_status` (axis: 47/48). HOLDS.
- **"median iterations = 1"** confirmed WITHOUT trusting the field: **136 of 152 met goals (89%)
  have exactly one evaluation record**; mean 2.85. The terminator finding stands.
- **goal-arm telemetry "all time"** = 14 rows, ALL from 2026-09-08 05:08Z–23:26Z (5 set · 7
  unverified · 2 unreachable). The emitter is <1 day old; "all time" is 18 hours.
- **Check-in adoption**: 25 transcript files now carry the text (axis 11, first pass 15) — includes
  `agent-*` subagent transcripts, so the count is not "sessions". Lead check-ins at 22:17:53Z and
  23:17:53Z (`Goal check-in: background work no longer running`), i.e. 30 min → ×2 backoff, as read
  from the binary.
- **2.1.260 n=40**: 29/40 never-evaluated has a 95% CI of roughly 56–85%; "70.8 vs 72.5,
  unchanged" is directionally right and numerically over-precise.
- **R2 reason (3)** (~901 evaluator calls/day) is inferred, and given 59% of goals never reach a
  Stop it also overstates. Reasons (1)+(2) carry R2; (1) is qualified by `ProposeGoal` (first pass)
  and by two channels neither pass tested: `claude "/goal …"` as initial-prompt argv, and a
  settings-declared `type:"prompt"` Stop hook (every registered hook is `command` type — 0 `prompt`
  hooks in `~/.claude/settings.json`), which would be a per-fleet static goal NOT subject to the `d2n`
  deferral (the gate finds only the activeGoal's own hook by `prompt === Ze.condition`). Fail
  direction of that untested lever: one tool-less LLM call at EVERY Stop of EVERY session.
- **R3**: session-continue counts reproduce (239 continue · 28 wake-floor · 429 cli-set). But "primary
  drive lever" rests on fire COUNTS, not on any measured outcome of a forced turn (closure-count ≠
  value); and both levers are Stop-time, so neither reaches the 59% of goal sessions that never Stop.
  The `--goal`-is-a-terminator reframing is supported (89% single-evaluation); the "primary lever"
  claim is not measured.
