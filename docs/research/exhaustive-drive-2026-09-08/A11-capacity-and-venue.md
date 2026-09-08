# A11 — Capacity and venue: no-capacity must route, not file

**Wave:** exhaustive-drive 2026-09-08 · **Axis:** A11 · **Mode:** read-only measurement
**Question:** how often does the machine admission gate (or load) turn drivable work into a filed row
or into serialized lead-inline work, and how should "no-capacity" route work to a self-draining queue
instead of a FILED row?

---

## Answer first

**Capacity almost never files. It SERIALIZES — and the cost lands on the one resource the fleet's own
policy calls scarcest, the lead's context.** Measured across all four transcript roots for
2026-09-08: 20 of 38 Agent-tool spawn attempts were denied by the machine admission gate; 15 of those
20 belong to three sessions whose transcripts I hand-read end to end; **0 were filed, 0 were retried,
and 3 of 3 leads announced in prose that they would "run the rest serially here."** The disposition
that actually occurred is not one of the three the close protocol admits (DRIVEN / FILED / BLOCKED) —
it is *re-venued onto the lead*, silently, with no store recording that a parallel plan degraded to a
serial one.

Three structural facts make that outcome inevitable, and each is separately fixable:

1. **A refused spawn has no destination.** `hooks/agent-teams-enforce.sh` holds the entire brief in
   `$INPUT` at the moment it denies, and writes it nowhere. `~/.claude/parked-briefs/` exists, holds
   exactly one file from 2026-08-09, and **no code reads it** (`grep -rl parked-briefs` over
   `scripts/ bin/ hooks/ commands/` → one hit, in a coverage *config*).
2. **The queue that does exist cannot drain, for reasons unrelated to capacity.** The dispatcher's
   local queue held 137 rows at 09:20Z and 101 at 21:56Z, with **96 of the original 137 still
   deferred 12.6 hours later**; `live_workers` ranged 1–8 against `ceiling 12` and **never once
   bound**. Of 90 real fire attempts today, **47 (52%) exited non-zero**, 12 of them on
   `handoff-fire: no pane anchor resolved`.
3. **Cloud cannot absorb the local queue.** `cc-eligible sweep` over the 357 open/blocked rows:
   **23 eligible (6.4%)**, 152 refused as `ineligible-box`. The work is *about this box*; the venue
   escape hatch is 6% wide by construction, not by neglect.

And one defect that inverts the picture on the *other* spawn path: **`scripts/handoff-fire.sh`'s
active-concurrency term is blind in production on 100% of fires** (48 of 48 admits today carry
`blind: active`), because its only sourcing site for `spawn-presence.sh` sits inside a command
substitution. The gate that is supposed to hold the box at 8 mid-turn sessions was, all day,
admitting into 9–16.

**Failure directions, stated up front:** the Agent-tool gate errs *closed on the plan and open on the
box* — it stops the fan-out but its 1-in-3 budget release lets the box reach load 155/10 cores
anyway. The fire gate errs *fully open*. Every recommendation below is placed on the side of
"the work keeps a destination" rather than "the box is protected harder", because the box already
survived every refusal today and the work did not.

---

## 1. The three gates, and which one is actually in play

| Gate | Code | Terms enabled today | Binding today? |
|---|---|---|---|
| **Agent-tool admission** (subagent/teammate spawn) | `hooks/agent-teams-enforce.sh:226-243` → `scripts/lib/capacity-admit.sh` | headroom · segments · **active (ceiling 8)** · load OFF | **YES — 20 refusals / 38 evals = 52.6%** |
| **handoff-fire capacity gate** (dispatched sessions) | `scripts/handoff-fire.sh:5052-5400` | headroom · segments · **active BLIND** · load OFF | **NO — 0 refusals / 48 production evals** |
| **cc-dispatch admission** (backlog → session) | `bin/cc-dispatch:55-58, 423` | `free_slots = max(0, CEILING(12) − live_workers)` | **NO — live_workers peaked at 8** |

Commands:

```bash
# Agent-tool gate, today (population: every Agent-tool + boot-resume evaluation since IDL rotation 08:22Z)
jq -rc 'select(.gate) | [.gate,(.verdict//"-"),(.basis//"-"),(.caller//"-")] | @tsv' \
  ~/.claude/autonomy/idl.jsonl | sort | uniq -c | sort -rn

# handoff-fire gate, today (population: ~/.claude/logs/handoffs.jsonl, rotated 04:48Z)
jq -rs '[.[]|select(.gate=="capacity" and (.under_test|not))] | group_by(.verdict)
        | map({(.[0].verdict): length}) | add' ~/.claude/logs/handoffs.jsonl
#   => {"admit": 48}      — zero refusals

# dispatcher ceiling, today
jq -rc 'select(.actor=="cc-dispatch" and .reason=="capacity")
        | [.pass,(.live_workers|tostring),(.free_slots|tostring),(.ceiling|tostring)] | @tsv' \
  ~/.claude/autonomy/idl.jsonl | awk '!seen[$1]++'
```

`under_test` matters: `~/.claude/logs/handoffs.jsonl` carries **219 capacity admits from the bats
harness** against 48 production ones. Any ratio computed without splitting on that field is wrong by
construction — the file's own header records a 25.5-point error made exactly that way.

---

## 2. What a refusal actually does — the hand-read (measured, n = 15 of 20)

Three sessions took every one of today's Agent-tool refusals. All three transcripts were read
line-by-line around each refusal.

| Session (sid prefix) | Root | Agents attempted | Refused | Admitted | Re-attempted | Filed |
|---|---|---|---|---|---|---|
| `ecdc97fa` | `.claude-quaternary` | 7 | 5 | 2 | **0** | **0** |
| `e5ab6841` | `.claude-secondary` | 8 | 6 | 2 | **0** | **0** |
| `98af4df2` | `.claude-secondary` | 6 | 4 | 2 | **0** | **0** |
| **total** | | **21** | **15** | **6** | **0** | **0** |

`ecdc97fa`'s wave, verbatim from the transcript (`timestamp` and `tool_use.input.description`):

```
09:16:47  Agent  A: mcp-config flag semantics        →  09:16:50  DENY  (refusal 2 of 3)
09:17:01  Agent  B: entrypoint chokepoint audit      →  09:17:02  DENY  (refusal 3 of 3)
09:17:12  Agent  C: existing governance tests        →  09:17:14  ADMIT (budget-expired)
09:17:27  Agent  D: MS365 plan interaction           →  09:17:28  DENY  (refusal 1 of 3)
09:17:44  Agent  E: migration failure mode           →  09:17:45  DENY  (refusal 2 of 3)
09:18:01  Agent  F: SSOT file location               →  09:18:03  DENY  (refusal 3 of 3)
09:18:21  Agent  G: adversarial red-team             →  09:18:22  ADMIT (budget-expired)
```

Each description appears **exactly once** in the whole transcript:

```bash
F=/Users/chrisren/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-9f203fa60cd0/ecdc97fa-d0a6-48a2-b1d7-91c62a251762.jsonl
jq -rc 'select(.type=="assistant")
        | ((.message.content//[])|map(select(.type=="tool_use" and .name=="Agent")|(.input.description//""))|join("~"))' "$F" \
  | grep -c "mcp-config flag semantics"      # => 1
```

### What the leads said they would do

This is the part that reframes the axis. All three leads *noticed*, and all three chose the same
thing — the thing the refusal message itself recommends:

> `ecdc97fa`: *"Machine at capacity — 5 of 7 spawns refused (16 sessions mid-turn, ceiling 8). Two are
> running (governance + adversarial); **I'll run the other five serially here** rather than
> retry-storm the gate."*

> `e5ab6841`: *"Box is at capacity (12 sessions mid-turn, ceiling 8) — two workers took SIG06-10 and
> SIG26-30; the refusal says run the rest serially rather than retry. **Doing that on the lead now.**"*

> `98af4df2`: *"Machine is at capacity (12 sessions mid-turn, ceiling 8) — 2 of 6 agents launched, and
> the refusal explicitly says don't retry. **I'll run the remaining four axes serially myself.**"*

The refusal text (`hooks/agent-teams-enforce.sh:235`, ~2,600 characters) contains the instruction
they followed: *"Run this work SERIALLY on the lead if it cannot wait — that is the correct answer
while the operator is working."* It also says *"shed first (close finished panes, let the running
wave drain, reduce the fan-out width), then spawn"* — **none of the three shed anything, and none
waited for a slot.** Prose in a denial is advisory, and advisory sits behind a diode; the one clause
with a zero-cost immediate action is the one all three took.

### Why "serialize on the lead" is the wrong default here

The global CLAUDE.md § Agent Teams states the axis directly: *"a teammate's every report… land in the
LEAD's window… so the mandated delegation unit above was the one that does NOT protect the scarcest
resource."* Serializing a refused subagent onto the lead is that failure in its purest form — it
takes work sized for a fresh 150–250K context and runs it inside a context that is already holding a
wave plan. Nothing measures the substitution: no IDL row, no backlog row, no ledger term. `/wrap`
cannot see it, `completion-assert` cannot see it, and the close reads exactly like a wave that ran.

**Honest limit on this section:** n = 3 sessions / 15 refusals, all on one day. It is 100% of the
refusals that reached a transcript I could read, and the behaviour is 3/3 identical, but it is not a
30-day figure and the IDL cannot be made into one (see §6).

---

## 3. The budget is global, and it releases on volume rather than on the box

`scripts/lib/capacity-admit.sh:82-83` — the budget state file is keyed on `<caller>`, and every Agent
spawn on the box passes the same caller id, `agent-tool`. `CC_ADMIT_BUDGET` defaults to 3
(`capacity-admit.sh:564`). So under saturation the gate admits **exactly 1 spawn in 3**, from
whichever session happens to make the third attempt, *regardless of how far over the ceiling the box
is*. Today it released at 16 mid-turn against a ceiling of 8 — twice the ceiling — six times:

```bash
jq -rc 'select(.gate=="capacity-admit" and .basis=="budget-expired") | [.ts,(.detail|.[0:80])] | @tsv' \
  ~/.claude/autonomy/idl.jsonl
# 6 rows, all "active term over after 3 consecutive refusals — admitting and paging"
```

Two consequences worth naming:

- **The mechanism contradicts its own message.** The message says *"DO NOT retry in a loop"*; the
  mechanism rewards exactly three attempts with an admit. A lead that retried would have gotten every
  axis through in ~90 seconds. The three leads that obeyed the prose paid with their context. A rule
  whose mechanical incentive points the other way is a rule the model learns to route around — the
  brief's own warning.
- **The bound is not sized to the breach.** At 9 mid-turn the release is proportionate; at 16 it is
  not. The budget answers "how long may a refusal stand" and nothing answers "how far over are we".

Total refusal-imposed delay today, measured burst-by-burst from the IDL timestamps
(first refusal → budget-expired admit): 24 s, 54 s, 5 s, 25 s, 15 s, 60 s ≈ **3 minutes across the
whole day.** Capacity is not costing the fleet time. It is costing it *parallelism*.

---

## 4. handoff-fire's active term is blind in production — 48 of 48

Every production capacity admit in `~/.claude/logs/handoffs.jsonl` today carries `blind: active`:

```bash
jq -rc 'select(.gate=="capacity" and (.under_test|not) and .verdict=="admit")
        | (.detail | capture("blind: (?<b>[a-z, ]+)").b // "none")' ~/.claude/logs/handoffs.jsonl \
  | sort | uniq -c
#  48 active            (production)
# and, for contrast, 219 test-harness admits read "none" — the suites set CC_FIRE_ACTIVE_OVERRIDE
```

Corroborated in the dispatcher's own live log, verbatim, on today's fires:

```
===== 2026-09-08T21:36:52Z item=99dbf659930c account=next rc=1 pid=72372 =====
-- capacity gate: headroom ADMIT — reclaimable 23.91GB (floor 4GB)
-- capacity gate: active term BLIND (instrument unreadable) — noted, not fatal
```

### Root cause (measured, not inferred)

`handoff-fire.sh` never sources `scripts/lib/spawn-presence.sh` at function scope. Its only sourcing
site is inside `_cc_fire_presence()` (`:4995-5011`), and that function is invoked **inside a command
substitution**:

```bash
# scripts/handoff-fire.sh:5152
CC_FIRE_PRESENCE="$(_cc_fire_presence)"
```

The subshell sources the library, returns the presence string through the substitution — which is why
every admit row *does* carry `operator present` — and then dies with the function definitions. By the
time the active term runs 200 lines later it tests `command -v cc_sp_active` (`:5360`) and fails.
Reproduced directly:

```bash
cd /Users/chrisren/Development/.worktrees/exhaustive-drive
bash -c '. scripts/lib/capacity-admit.sh >/dev/null 2>&1
  command -v cc_sp_active >/dev/null && echo DEFINED || echo NOT-DEFINED
  p=$( { command -v cc_sp_operator_state >/dev/null || . scripts/lib/spawn-presence.sh; }; cc_sp_operator_state "" )
  echo "presence=[$p]"
  command -v cc_sp_active >/dev/null && echo DEFINED || echo STILL-NOT-DEFINED'
# NOT-DEFINED / presence=[absent] / STILL-NOT-DEFINED
```

Sourced at top level the function works fine and answers correctly:

```bash
bash -c '. scripts/lib/spawn-presence.sh >/dev/null 2>&1; echo "active=$(cc_sp_active)"'
# active=9        (against CC_FIRE_ACTIVE_CEILING default 8 — a fire right now SHOULD refuse)
```

`scripts/lib/capacity-admit.sh` does not have this bug: its `_cc_admit_load_presence()` (`:457-476`)
sources at *function* scope, so the Agent-tool gate's active term evaluates correctly — which is why
that gate refused 20 times today and this one refused zero. This is
memory `assignment-inside-command-substitution-never-escapes`, one library over.

**Consequence:** `handoff-fire.sh:5185`'s comment claims the two gates *"agree by construction rather
than by coincidence"*, and `hooks/agent-teams-enforce.sh:216-219` calls `active` *"the ceiling the
whole design point rests on."* Neither is true of the fire path. The exact disagreement the comment
was written to end — a fire admitting while the Agent gate refuses — is what the fleet ran all day.

**Failure direction of the fix:** turning the term on will start refusing fires. Today that would be
9 > 8 → refuse, i.e. **the fix converts the fire path from silent over-admission into a refusal with
no queue behind it** — the §2 defect, on a second surface. It must land *after* the routing
mechanism, not before. Stated plainly because the tempting order is the wrong one.

---

## 5. The local queue exists, is correctly shaped, and does not drain — but not because of capacity

`bin/cc-dispatch:55-58` is explicit: *"The first `free_slots` items by the S7 key are admitted; every
other item DEFERS with its queue position."* So `reason:"capacity"` on the dispatcher's rows means
*"beyond this pass's admit budget"*, not *"the box is full"* — and 10,183 such rows were written in
13.5 hours:

```bash
jq -rc 'select(.actor=="cc-dispatch") | [(.verdict//"-"),(.reason//"-")] | @tsv' \
  ~/.claude/autonomy/idl.jsonl | sort | uniq -c | sort -rn
# 10183 defer capacity · 1435 skip project-not-dispatched · 693 admit · 126 defer cluster-sibling
```

A live row, at a moment when a third of the fleet's slots were free:

```json
{"ts":"2026-09-08T21:56:14Z","actor":"cc-dispatch","verdict":"defer","position":104,
 "reason":"capacity","free_slots":4,"ceiling":12,"live_workers":8}
```

### Drain rate, measured

| | |
|---|---|
| Queue depth 09:20Z → 21:56Z | **137 → 101** (−36 over 12.6 h ≈ **2.9 rows/h**) |
| Rows deferred at 09:20Z that were **still** deferred at 21:56Z | **96 of 137 (70%)** |
| Distinct ids admitted all day | **35** (22 of which reached `event:"done"`) |
| `live_workers` range | **1 – 8**, against `ceiling 12` — **never binding** |

```bash
F=$(jq -rc 'select(.actor=="cc-dispatch" and .verdict=="defer") | .pass' ~/.claude/autonomy/idl.jsonl | head -1)
L=$(jq -rc 'select(.actor=="cc-dispatch" and .verdict=="defer") | .pass' ~/.claude/autonomy/idl.jsonl | tail -1)
jq -rc --arg p "$F" 'select(.pass==$p and .verdict=="defer")|.id' ~/.claude/autonomy/idl.jsonl | sort -u > /tmp/a.txt
jq -rc --arg p "$L" 'select(.pass==$p and .verdict=="defer")|.id' ~/.claude/autonomy/idl.jsonl | sort -u > /tmp/b.txt
comm -12 /tmp/a.txt /tmp/b.txt | wc -l     # => 96
```

### The actual bottleneck: the fire itself

`~/.claude/logs/dispatch-fires.log`, today, excluding the `i1`/`i7` selftest items:

| rc | count | meaning |
|---|---|---|
| 0 | 43 | pass completed (only **19** carry a `→ fired:` line) |
| **1** | **34** | includes `!! firing pane NNN not found in iTerm2 — anchor gone; NOT firing into a random window. Nothing was launched.` (6 occurrences) |
| **7** | **12** | `handoff-fire: no pane anchor resolved` |
| 2 | 1 | `/Users/chrisren/.claude/scripts/handoff-fire.sh: line 8058: syntax error near unexpected token ')'` |

```bash
L=~/.claude/logs/dispatch-fires.log
grep -a "^===== 2026-09-08" "$L" | grep -av "item=i[0-9] " | grep -o "rc=[0-9]*" | sort | uniq -c
grep -a "^===== 2026-09-08" "$L" | grep -av "item=i[0-9] " | grep -o "item=[0-9a-f]\{12\}" | sort -u | wc -l  # 53
```

**52% of real dispatch fires failed (47 of 90), and the dominant cause is that the headless drain
lane needs a live iTerm2 pane to anchor to and cannot make one.** The local queue's 101-row backlog is
not a capacity problem at all — it is an *actuator* problem wearing capacity's label. Any routing
rule that enqueues refused work into this queue inherits that bottleneck; the rc=7/anchor-gone path
must be fixed for the routing to mean anything.

(The rc=2 syntax error is separate and worth a second look: the *live* `~/.claude/scripts/handoff-fire.sh`
was unparseable at 14:07:15Z. Either a peer worktree was read mid-write, or a broken file was deployed.
One fire died on it.)

---

## 6. What "no-capacity" filings actually look like on disk

**Zero rows in the entire backlog carry the `no-capacity` impossibility class.**

```bash
jq -rc 'select((.why_not_now // .whyNotNow // "" | length)>0)
        | ((.why_not_now // .whyNotNow) | split(":")[0])' ~/.claude/autonomy/backlog.jsonl \
  | sort | uniq -c | sort -rn
# 13 not-yet-true · 8 needs-human · 0 no-capacity  (plus free-text legacy strings)
```

`bin/cc-backlog:1026` accepts `no-capacity`, and `:1752` defines it as a **conjunction** —
*"MEASURED: `claude-accounts --rank general` routes nowhere AND the machine admission gate refuses the
spawn."* The first conjunct is false right now:

```bash
bin/claude-accounts --rank general
# next4 0.000054 / next 0.000040 / next3 0.000024   — three accounts route
```

So no legitimate `no-capacity` filing is even constructible today. **The class is not the leak.**

### The leak is a *prose* park, and it is a two-week deferral

Rows whose text names a capacity refusal, with their full measured lifecycle:

| id | filed | first drivable event | add → done |
|---|---|---|---|
| `7d6b462a468c` "HANDOFF TRACK HELD BY CAPACITY GATE" | 08-02 11:21 | done 08-10 20:42 | **8.4 d** |
| `ce86cedc176c` "parked on handoff-fire" | 08-09 06:49 | done 08-09 22:14 | 15.4 h |
| `54c3af2f2afa` "PARKED: capacity gate 3.18/core" | 08-09 11:05 | done 08-09 23:12 | 12.1 h |
| `7a7f554c3b0a` "the capacity gate REFUSED the fire" | 08-12 11:30 | done 08-12 12:26 | 0.9 h |
| `253aaa52412e` "six wave fires PARKED on the box capacity gate" | 08-21 02:37 | done 09-04 13:19 | **14.4 d** |
| `f79353f8c096` "the machine-capacity gate refused on 2026-08-21" | 08-21 07:44 | done 09-05 02:50 | **14.8 d** |
| `80ed5e7a1e7e` "9 AT-REST panes still parked" | 08-25 08:12 | done 09-08 20:23 | **14.5 d** |
| `0e0c5a875dc0` "DEFERRED ON MEASURED CAPACITY, not on judgment" | 08-25 08:17 | **still open** | **≥ 14.6 d** |

```bash
jq -rc 'select((tostring)|test("capacity gate|PARKED.*capacity|DEFERRED ON MEASURED CAPACITY";"i"))
        | [.event,.id,.ts] | @tsv' ~/.claude/autonomy/backlog.jsonl
for id in 253aaa52412e f79353f8c096 0e0c5a875dc0; do
  jq -rc --arg i "$id" 'select(.id==$i)|[.ts,.event]|@tsv' ~/.claude/autonomy/backlog.jsonl | sort; done
```

Median ≈ 8 days; three of eight sat **over two weeks**; one never drained. The global CLAUDE.md's
FILED rule already prices this — *"a p90 of 9.3 days in the queue"*. A capacity park is therefore a
two-week deferral wearing a "temporary, retry when it settles" label, and nothing re-checks the
premise: `--falsifier` coverage is what would (62 `falsify` events fired today), but none of these
eight rows carried one.

### The graveyard

```bash
ls ~/.claude/parked-briefs/    # mailbox-groundup.txt, 10,463 bytes, 2026-08-09 — one file
grep -rl "parked-briefs" scripts/ bin/ hooks/ commands/    # scripts/growth-coverage.conf  (a config, not a reader)
```

A spool with a cheap entrance and no exit — memory `parking-state-cheap-entrance-no-exit`, exactly.

### The other silent strand: refused *resumes*

`scripts/boot-resume-launch.sh:279-283` prints on refusal:

```
  Session $sid is DEFERRED, not lost — re-run /resume-sessions once the box settles.
```

…to **stderr**, then `exit 9`, with no row anywhere. That is memory
`fail-loud-into-a-log-nobody-reads-is-silent`. Two sessions were refused this way over four days:
`2de07510-…` (09-05, three refusals) and `sid-dc2 on next4` (09-06 05:13 → 09-08 15:42, spanning
**three days** of intermittent retries). A crashed session that cannot resume is the highest-value
item in the whole queue, and its only record is a line in a log with no consumer.

---

## 7. Cloud is not the escape hatch — it is 6.4% wide, and correctly so

`bin/cc-eligible sweep` over the live open+blocked board (n = 357 rows):

| verdict | rows |
|---|---|
| `ineligible-box` — local-only state a VM cannot see | **152** |
| `ineligible-cross-repo` | 75 |
| `ineligible-offbox-lane` — the cloud lane itself | 34 |
| `ineligible-visual` | 23 |
| `ineligible-spawn-rail` | 23 |
| `ineligible-branch-banking` | 15 |
| `ineligible-parked` / `external-deploy` / `deep-history` / `github` | 12 |
| **`eligible`** | **23 (6.4%)** |

Current venue labels tell the same story: **801 rows `local`, 129 `cloud`** (last `venue` event per
id). `bin/cc-eligible`'s own header explains why this is right rather than a gap — *"a wrong ELIGIBLE
puts a worker in a VM that CANNOT do the work at all and cannot tell you so… stranding is
recoverable; a confident worker on invisible state is not."*

**And for the refused *subagent* case specifically, cloud is 0% wide.** All 15 refused axes today were
research about this box or this repo's own rails: `mcp-config flag semantics`, `entrypoint chokepoint
audit`, `Infra hooks watcher audit`, `Headless spawn census`, `Adjudicate SIG01-05`… Every one lands
in `ineligible-box` or `ineligible-spawn-rail`. **The venue answer to a refused research fan-out is
"later, here" — never "now, there."** Any proposal to route capacity overflow to cloud is answering a
question the corpus does not ask.

---

## 8. Is the box actually saturated? (the ceiling's own basis)

Measured at 21:03Z while this axis ran:

```
load averages: 154.89  91.33  75.15     hw.ncpu = 10        → 15.5 / core (1-min)
claude processes: 27 trees · cc_sp_active = 9 mid-turn · operator absent
cc-beats: 3,050 files, 4 fresh <900 s, 20 <1 h, 155 <24 h
```

So: **27 resident session trees, 9 of them mid-turn.** The design's core claim — *"residency is nearly
free; what the box binds on is sessions MID-TURN"* (`agent-teams-enforce.sh:235`) — is the right axis,
and the ceiling of 8 is not obviously wrong: the box is at 15.5 load/core with 9 mid-turn.

Two caveats that belong on the record:

- **A wave lead awaiting subagents is counted as mid-turn while costing ~nothing.** The `prompt` beats
  I sampled were 54–218 minutes old. `cc_sp_active`'s own header charges liveness by `(pid,lstart)`,
  which correctly excludes crashes but cannot distinguish *working* from *awaiting*. A ceiling of 8
  that counts orchestrators binds hardest on exactly the sessions whose fan-out it is refusing —
  a lead's own slot is charged against the wave it is trying to launch. This is the axis backlog row
  `a3eaa0dc1be2` (D8 working-vs-idling sensor) reaches for, and it is a *prerequisite* for raising the
  ceiling honestly rather than a nice-to-have.
- **Refusals only began on 2026-09-05.** Across the IDL archives the active term evaluated the whole
  time (details from 09-02 read `7 sessions mid-turn`), and produced **zero refusals over 09-29 → 09-04
  across 132 evaluations**; 09-05 is when occupancy first crossed 8. So the gate is neither always-on
  nor decorative — it fires when and only when the box is genuinely over, which is the polarity a gate
  should have.

```bash
for f in ~/.claude/autonomy/idl.jsonl.2026*.gz; do echo -n "$f "; gzcat "$f" \
  | jq -rc 'select(.gate=="capacity-admit") | [(.ts[0:10]),(.verdict),(.basis//"-")] | @tsv' \
  | sort | uniq -c | tr '\n' '|'; echo; done
```

| day | evals | refusals |
|---|---|---|
| 08-29 → 09-04 (6 days) | 132 | **0** |
| 09-05 | 55 | 11 (20%) |
| 09-06 | 36 | 20 (56%) |
| 09-07 | 11 | 1 (9%) |
| 09-08 | 62 | 31 (50%) |

---

## 9. The routing rule this axis was asked to propose

Every part below already exists in the tree; the proposal is wiring, not invention.

### R1 — A refused spawn writes a SPOOL ENTRY before it denies (the load-bearing change)

`hooks/agent-teams-enforce.sh` already holds the entire `tool_input` in `$INPUT` at the moment of
denial. Immediately before emitting the deny JSON, write:

```
$CC_SPAWN_SPOOL_DIR/<sid>/<sha1(description)>.json
  { ts, sid, cwd, subagent_type, description, prompt, term, detail, admit_ceiling, active_at_refusal }
```

Keyed on `sha1(description)` so a genuine retry updates one entry instead of minting a second. Then
change the deny message's advice clause from *"Run this work SERIALLY on the lead"* to *"N briefs are
spooled; they will be re-offered when a slot frees — do not re-run them inline."*

- **Failure direction: errs toward accumulating entries nobody drains** — i.e. it recreates
  `parked-briefs/` unless R2 lands in the same diff. R1 without R2 is strictly worse than today,
  because today at least the lead does the work.
- Effort **S**. Files: `hooks/agent-teams-enforce.sh`.

### R2 — One desk lane drains the spool, and it is the SAME lane that already drains the queue

The drain condition is measurable and already computed: `cc_sp_active < CC_ADMIT_ACTIVE_CEILING`. On
each tick, for each spool entry whose owning `sid` is still live, re-offer it by messaging the owner
(`cc-mail` / `mailbox-wake-arm`, both goal-safe) with the description and the id. If the owner is
gone, promote the entry to a backlog row **with a `--falsifier`** — `cc-backlog add --title "<desc>"
--condition spawn-deferred-<sha> --falsifier "<the check that proves the work is done>"` — so the row
self-retracts and cannot become another 14.6-day park.

- **Failure direction: errs toward re-offering work the lead already did inline.** Mitigation is a
  cheap one: the re-offer names the description and asks; a duplicate research axis costs one subagent,
  a lost one costs the wave. Choose the duplicate.
- Effort **M**. Files: `scripts/autonomy-sweep.sh`, `bin/cc-backlog` (no change if `--condition` +
  `--falsifier` suffice — they do).

### R3 — Fix `handoff-fire`'s blind active term, but only AFTER R1/R2 exist

Source `spawn-presence.sh` at top level (or inside `capacity_gate()` before the substitution) so
`cc_sp_active` survives into the term at `:5360`. One-line class of change; add a red-proof asserting
`blind:` never contains `active` on a production admit.

- **Failure direction: errs closed.** It will start refusing fires — today, at 9 mid-turn vs ceiling
  8, immediately. Landing it before R1/R2 moves the §2 defect onto a second surface. Landing it after
  is what makes the two gates' claimed agreement true.
- Effort **S**. Files: `scripts/handoff-fire.sh`, `tests/handoff-fire-capacity-gate.bats`.

### R4 — Size the refusal budget to the BREACH, not to a constant

`CC_ADMIT_BUDGET=3` releases 1-in-3 whether the box is at 9 mid-turn or 16. Make the budget a function
of the overshoot (e.g. `budget = max(1, ceiling*2 − active)`), so a mild breach releases quickly and a
2× breach effectively holds. Keep the page on release — the event must stay legible.

- **Failure direction: errs closed under heavy breach** — a wave could stall for minutes rather than
  seconds. That is acceptable *only once R1/R2 hold the work*; today a longer stall means more
  serialization, which is the defect.
- Effort **S**. Files: `scripts/lib/capacity-admit.sh`.

### R5 — A ledger term so a serialized wave cannot close as a clean one

`wrap-ledger.sh` cannot currently see that a fan-out degraded. Add `SPAWN_DEFERRED_MINE` (count of
live spool entries owned by this session), folding to **🔧** — the same shape as `UNCONVICTED_MINE`
and `FILED_MINE`. A close that says *"I'll run the other five serially here"* then cannot render ✅
until those five are done or explicitly parked.

- **Failure direction: errs toward blocking a legitimate close** if the spool is not reliably cleared
  on success. Clear on the admit path, and cap it (`CC_SPAWN_SPOOL_MAX`) exactly as the ship floor is
  capped.
- Effort **M**. Files: `scripts/wrap-ledger.sh`, `hooks/completion-assert.sh`.

### R6 — Fix the drain's actuator, or R2's promotion path is a queue into a wall

52% of real dispatch fires failed today, 12 on `no pane anchor resolved` and 6 on `anchor gone`.
`live_workers` never exceeded 8 against a ceiling of 12 — the fleet has ~4 permanently unused slots
because the headless lane cannot manufacture a pane. Until that is fixed, promoting spool entries to
backlog rows adds depth to a queue draining at 2.9 rows/h with 96/137 rows untouched in 12.6 hours.

- **Failure direction: errs toward spawning into a window the operator did not choose** — which is
  precisely the safety the current code is enforcing when it says *"NOT firing into a random window."*
  The fix is a designated headless anchor (a reserved window/tab), not a relaxation of that check.
- Effort **L**. Files: `scripts/handoff-fire.sh` (anchor resolution), `bin/cc-dispatch`.

### What NOT to do

- **Do not route capacity overflow to cloud.** 6.4% of the board is eligible and 0% of the refused
  research axes are. `bin/cc-eligible` is right and should not be widened on a hunch — its own header
  says a word added because it "sounds local" costs the tap a whole class of real work, and the
  reverse costs a confident worker on invisible state.
- **Do not raise `CC_ADMIT_ACTIVE_CEILING` yet.** The count charges an awaiting orchestrator the same
  as a working session; raise it only after `a3eaa0dc1be2` (working-vs-idling sensor) can tell them
  apart. Raising it now is `LOAD_INSENSITIVE_VERIFY_V2`'s forbidden move — moving the number a wrong
  input is compared against.
- **Do not add a `no-capacity` filing path.** The class exists, its conjunction is currently
  unsatisfiable, and zero rows use it. The leak is prose parks and silent serialization, not the class.

---

## 10. Adversarial pass — what I checked because it would have made me wrong

| Challenge | What I did | Result |
|---|---|---|
| *"Your transcript grep found nothing — the refusals never reached a model."* | Positive-controlled the instrument, then located the three sessions by `sid` from the IDL. | **My instrument was blind**: `find -newermt` (this box's `find` is `bfs`) silently excluded the very files. Direct `find -name "<sid>.jsonl"` found all three, with 5 / 6 / 4 `MACHINE CAPACITY` hits. Every transcript claim above comes from the re-found files. Memory `positive-control-the-denominator`, paid in full. |
| *"The work was dropped, not serialized."* | Grepped each lead's assistant text for `capacit\|refus\|serial`. | **Refuted my own first reading.** All three leads narrated the refusal and announced serial execution. The finding is *serialization*, which is more defensible and worse. |
| *"Maybe capacity is filing rows and you looked in the wrong field."* | Censused `why_not_now` classes AND free-text over the whole backlog; checked today's 80 adds against the dropped axes' keywords. | 0 `no-capacity` rows; 0 of the 15 refused axes filed. Eight *prose* parks found instead, with the 14-day latencies in §6. |
| *"The dispatcher's 10,183 `capacity` defers ARE the filing you're looking for."* | Read `bin/cc-dispatch:55-58` and the live rows. | It is a **queue-position** label: rows deferred at position 104 with `free_slots: 4`, and at ~116 with `free_slots: 11`. Real, but a different thing — and it made me check the drain, which is where the actual bottleneck turned out to be (§5). |
| *"Cloud solves this."* | Ran `cc-eligible sweep`; classified the 15 refused axes by hand. | 6.4% of the board, 0% of the refused axes. Killed the obvious recommendation. |
| *"Is the ceiling of 8 just too low?"* | Multi-day IDL archive census + live box measurement. | Zero refusals in 132 evaluations across 6 days; refusals began the day occupancy crossed 8. Polarity is right. But the count charges awaiting orchestrators — named as a prerequisite, not a fix. |

**Instrument caveats that bound every number above.** The IDL was rotated at 08:22Z and
`handoffs.jsonl` at 04:48Z, so all "today" figures are 13.5 h / 17 h windows, not days —
the archives in §8 are the only multi-day view and they carry only the `capacity-admit` gate.
`dispatch-fires.log` is not rotated and covers the full day. The transcript hand-read is
n = 3 sessions / 15 refusals — 100% of the readable refusals, one day.

---

## 11. Open questions

1. **What does a serialized axis cost, in outcome rather than in tokens?** No instrument compares a
   research axis run in a fresh 200K subagent against the same axis run inline on a loaded lead. Every
   argument in §2 for why serialization is bad is architectural, not measured.
2. **Why did the live `~/.claude/scripts/handoff-fire.sh` fail to parse at 14:07:15Z?** One fire died
   on `line 8058: syntax error`. Peer worktree read mid-write, or a broken deploy — the distinction
   matters and this axis did not chase it.
3. **`0e0c5a875dc0` has been open 14.6 days** ("Restore the sessions that did not come back from the
   2026-08-25 reboot — DEFERRED ON MEASURED CAPACITY"). Are those sessions still recoverable, or has
   the park outlived its own subject?
4. **`sid-dc2` has been failing to resume since 09-06.** Nothing owns it. Is it worth resuming at all,
   and if not, what retracts the retry loop?
5. **Would R4's breach-sized budget interact badly with the reserve terms?** `reserve-active` /
   `reserve-slots` fire on operator presence and share the same budget file; sizing one on overshoot
   may change the other's release cadence.
