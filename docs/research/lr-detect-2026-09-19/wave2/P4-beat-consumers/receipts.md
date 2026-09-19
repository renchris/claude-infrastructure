# P4 — beat consumers: is a new beat `kind` safe?

Unit: P4-beat-consumers · 2026-09-19 · read-only on /Users/chrisren/Development/claude-infrastructure
Verdict: **PARTIAL** — safe on every READ consumer (measured, no exceptions), but "safe" understates
and mis-locates the value: the new kind is a CAPACITY-ACCOUNTING fix, not a detection mechanism, and
it is safe only if the marker write carries `operatorT` forward.

---

## R1 — The complete consumer census (`cc-beats` / the `kind` field)

```
cd /Users/chrisren/Development/claude-infrastructure
grep -rn "cc-beat\|CC_BEAT\|cb_last_beat\|cb_operator_age\|cb_system_live" hooks scripts bin lib commands | grep -v node_modules
grep -rn "\.kind" hooks scripts bin lib tests | grep -v node_modules
```

| # | consumer | file:line | what it reads | behaviour on an UNKNOWN kind |
|---|---|---|---|---|
| 1 | `cb_last_beat` | `hooks/lib/cc-beat.sh:41-50` | whole JSON, `jq -e .` validity only | **ignored** (returns the row) |
| 2 | `cb_operator_age` | `hooks/lib/cc-beat.sh:52-65` | `.operatorT` | **ignored** — kind-agnostic |
| 3 | `cb_system_live` | `hooks/lib/cc-beat.sh:67-82` | `.t` | **ignored** — kind-agnostic |
| 4 | `cc_sp_active` | `scripts/lib/spawn-presence.sh:319` — `map(select(.kind == "prompt" …))` | `.kind`,`.pid`,`.lstart`,`.t` | **counted INACTIVE** (excluded from the mid-turn census) |
| 5 | `cc_sp_operator_state` | `scripts/lib/spawn-presence.sh:445-448` | `.t`,`.operatorT` (one jq slurp) | **ignored** — kind-agnostic |
| 6 | `session_busy_live` | `hooks/lib/session-busy.sh:335`, branch at `:342` `if [ "$kind" = "prompt" ]` | `.kind`,`.pid`,`.lstart`,`.t` | **counted IDLE** → falls to the job/arm legs → `IDLE-ARMED` or `IDLE-DEAF` |
| 7 | `cc-await-ping` `_turn_moved` | `bin/cc-await-ping:570` — `seq > base && kind == "prompt"` | `.seq`,`.kind` | **not a new turn** (clause 2 fails; clause 1 at `:568` is seq-only) |
| 8 | `cc-await-ping` stale-beat refusal | `bin/cc-await-ping:508` | `.kind` | **printed verbatim in a diagnostic string** — no branch |
| 9 | `cc-reaper` act-time re-take | `bin/cc-reaper:2552-2578` | `cb_operator_age` + `cb_system_live` | **ignored** |
| 10 | `cc-teardown` presence belt | `bin/cc-teardown:642-660` | same two fns | **ignored** |
| 11 | `hooks/teammate-auto-shutdown.sh` `_beat_or_hold` | `:570-578` | same two fns | **ignored** |
| 12 | `bin/cc-inbox-guard` `headless_beat_live` | `:259-293` | `.t` only | **ignored** |
| 13 | `scripts/measure-terminations.py` | `read_beats():202`, `liveness():219-232` | `.sid`,`.pid`,`.lstart` | **ignored** |
| 14 | `bin/cc-cloud` | `:46` | *comment only* — `grep -n cc-beats bin/cc-cloud` returns exactly 1 line, a header list | **not a consumer** |
| — | `bin/cc-comms-alarm-sweep:100` | reads `.kind` of an **alarm** file, not a beat | — | not a consumer |

**No consumer errors, aborts, or mis-parses on an unknown kind. Every kind-testing consumer tests
`== "prompt"`, so a new kind inherits `stop`'s already-correct handling.**

`.who` has **zero** readers in code (`grep -rn "'\.who\|\"\.who\|\.who //" hooks scripts bin lib` ⇒ no
hits): it is written by `hooks/session-beat.sh:114` and read by nothing; presence rides `operatorT`.

## R2 — The kind enum was DESIGNED extensible, and two declared members were never built

```
grep -n "kind" docs/plans/SESSION_REGISTRY_V2.md
:231 {"sid":"…","pane":"…","pid":1234,"lstart":"…","t":…,"kind":"start|prompt|stop|end",
:190 SessionStart → beat kind=start     :195 SessionEnd → beat kind=end (tombstone)
```
Live histogram over the whole store:
```
jq -rs 'map(.kind)|group_by(.)|map("\(.[0]) \(length)")|.[]' ~/.claude/cc-beats/*.json
prompt 1725
stop   2054          (3779 files)
```
`start` and `end` are declared and unimplemented ⇒ consumers have ALWAYS had to tolerate a kind they
do not know, and they do.

## R3 — Hermetic fixture: three kinds, one live pid, every consumer in one process

```
bash -c '... write sid-prompt / sid-limited / sid-stop, kind-varied, same live pid+lstart ...
         . hooks/lib/session-busy.sh;      session_busy_live sid-$k /tmp
         . scripts/lib/spawn-presence.sh;  cc_sp_active
         . hooks/lib/cc-beat.sh;           cb_operator_age sid-limited'
=>
prompt   -> BUSY 0 1 beat prompt              rc=0
limited  -> IDLE-DEAF 0 1 none no-wake-path   rc=1
stop     -> IDLE-DEAF 0 2 none no-wake-path   rc=1
ACTIVE=1                                 # only the prompt beat counts
cb_operator_age(limited)=3               # kind-agnostic, still answers
```

## R4 — THE LIVE DEFECT THE KIND FIXES (today's fleet)

14 distinct sids hit `rate_limit` today
(`cat ~/.claude/autonomy/stop-failure/rate_limit__*.jsonl | jq -r .session_id | sort -u`).
Beat state of each, with `beat.t − last marker ts`:

```
07e30aeb kind=prompt alive=True  beat_t-marker= +1396s   (recovered)
09e64dcb kind=prompt alive=True  beat_t-marker=    -1s   FROZEN AT THE LIMIT TURN
0e2567ee kind=prompt alive=False beat_t-marker=    -1s
11569d45 kind=prompt alive=False beat_t-marker=    -5s
26cd14be kind=prompt alive=True  beat_t-marker=    -5s   FROZEN
28f07827 kind=prompt alive=False beat_t-marker= +2616s
4bc1159f kind=prompt alive=True  beat_t-marker=    -1s   FROZEN
65186f1f kind=prompt alive=True  beat_t-marker= +3017s   (recovered/transplanted)
8843bcf3 kind=prompt alive=True  beat_t-marker=    -1s   FROZEN
98f02458 kind=prompt alive=False beat_t-marker=    -1s
cb227486 kind=stop   alive=False beat_t-marker=+12277s
d02d8feb kind=stop   alive=False beat_t-marker= +6120s
e442434c kind=prompt alive=False beat_t-marker= +1954s
fff83638 kind=prompt alive=False beat_t-marker=    -1s
```
**12 of 14 rate-limit deaths left `kind:"prompt"` on disk.** The `−1s / −5s` rows are the limit turn's
OWN opening prompt beat with nothing written since — Stop never fired, so the beat never advanced.

Confirmed at the transcript, not inferred (`rate_limit` record index vs file length):
```
09e64dcb lines=1935 rate_limit at 1933 records after: 1  quotaLimits.resetsAt=1789853400 five_hour
26cd14be lines=1326 rate_limit at 1324 records after: 1  resetsAt=1789853400
4bc1159f lines=1608 rate_limit at 1606 records after: 1  resetsAt=1789853400
8843bcf3 lines= 713 rate_limit at  711 records after: 1  resetsAt=1789853400
```
All four share one `resetsAt` — the operator's "multiple sessions at once from the same account", as data.

## R5 — A/B over a COPY of the live beat dir: what the kind actually buys

```
cp -R ~/.claude/cc-beats <mydir>/beatcopy          # 3780 files
CC_BEAT_DIR=<mydir>/beatcopy  cc_sp_active  => ACTIVE_baseline=10
jq '.kind="limited"' applied to the 4 frozen sids above
CC_BEAT_DIR=<mydir>/beatcopy  cc_sp_active  => ACTIVE_after_flip=7
```
Drop is **3, not 4**, and the reason is measured not hand-waved: a re-run `kill -0` showed pid 64409
(26cd14be) died between the two samples, so the baseline had already lost it. **3 of 10 mid-turn
ACTIVE right now (30%) are limit-dead phantoms, and the kind removes exactly those and nothing else.**

Consequence, straight off the gate's own arithmetic (`scripts/lib/capacity-admit.sh:782-792`):
`act_ceiling` default **8**; refusal when `act + 1 > ceiling`. Baseline `10+1 > 8` ⇒ **REFUSE**;
after the flip `7+1 = 8`, not `> 8` ⇒ **ADMIT**. This is the term that parked a recovery today.
(Arithmetic read off the source line; the gate itself was NOT executed — it writes a spend ledger.)

## R6 — The MINIMAL WRITE is zero new writer code: `session-beat.sh <kind>` already takes the kind

`hooks/session-beat.sh:124` is `beat "${1:-prompt}"`, and `:62` `if [ "$kind" = prompt ]` gates the
whole `who` derivation, so any non-prompt kind skips it. Registration today
(`jq` over `~/.claude/settings.json`):
```
UserPromptSubmit  ~/.claude/hooks/session-beat.sh prompt
Stop              ~/.claude/hooks/session-beat.sh stop
StopFailure       ~/.claude/hooks/stop-failure-marker.sh
```
Proof the existing writer handles a StopFailure payload unmodified:
```
printf '{"session_id":"S1","transcript_path":"/t/x.jsonl","cwd":"/x",
         "hook_event_name":"StopFailure","error":"rate_limit",
         "last_assistant_message":"5-hour limit reached"}' | bash hooks/session-beat.sh limited

BEFORE: {... "kind":"prompt","who":"operator","operatorT":1789851467,"seq":7}
AFTER : {... "kind":"limited","who":"auto","operatorT":1789851467,"seq":8}
then: ACTIVE=0   OPSTATE=present   session_busy_live => IDLE-DEAF
```
`operatorT` carried forward, `who` correctly `auto`, `seq` +1. **One line, no schema change.**

WARNING observed in that same run: the writer re-derives `pid`/`pane` from its OWN ancestry+env
(`session-beat.sh:85-93`, `:55`). Run out-of-band it rewrote pid to the *calling* session. On the
StopFailure path the hook runs inside the dying session's own tree, so this is correct there — but it
means the marker beat must never be relayed from another process.

## R7 — The three conditions that make this PARTIAL rather than HOLDS

**(a) `operatorT` MUST be carried forward.** If a limited beat dropped it, `cb_operator_age` returns
empty, and the three presence belts take their *fail-closed* arms — safe, but noisy:
- `bin/cc-reaper:2556-2563` → `keep … no presence beat … → surface (fail-closed)`
- `bin/cc-teardown:645-649` → `REFUSE presence-unprovable … exit 2`
- `hooks/teammate-auto-shutdown.sh:578-585` → HOLD + **pages the desk**, damped per (team,member,cause)

i.e. every limited teammate would page. Reusing `session-beat.sh` (R6) gets this right for free;
a bespoke writer is where it would be got wrong. The inverse hazard is worse and must be banned
outright: the marker write must NEVER set `who=operator` / `operatorT=now`, which would forge
presence and make the reaper refuse forever.

**(b) The kind must NOT be `prompt`.** `cc-await-ping:568-571` stands a parked watcher down on
`seq > base+1` OR (`seq > base` AND `kind == "prompt"`). A limited beat at `base+1` with a non-prompt
kind correctly does **not** count as a new turn; writing `prompt` there would falsely stand the
watcher down over a session that is dead.

**(c) Placement inside `stop-failure-marker.sh` matters.** The cap early-exit is at `:115-120`
(`if [ "$LINES" -ge "$CAP" ]; then … exit 0`). A beat write placed after it stops firing once a cause
hits 500 lines — exactly the mass-death case this whole unit is about. Put it after `ACCOUNT`
resolves (`:89`) and before `:115`; or register `StopFailure → session-beat.sh limited` as a second
hook entry (a settings.json edit ⇒ operator-owned migration class).

## R8 — What the kind does NOT buy (scope honesty)

The beat carries no account and no cause, and widening it is against: it is the highest-frequency
writer on the box (one write per turn per session, 3,779 rows live) for a field only the limit census
reads. **The account is already in the marker** (`stop-failure-marker.sh:82-89` resolves it from
`CLAUDE_CONFIG_DIR` via the accounts SSOT and writes it on every line), and the pane is already in
`~/.claude/cc-registry/<pane>.json`. So DETECTION is a join over three stores that each already hold
their half — marker(sid, account, error, ts) × registry(pane, pid, cwd) × beat(kind, pid, lstart) —
and the new kind's job is only to stop the capacity census counting the dead.

Recommendation, ranked:
1. **New kind written by the EXISTING writer, invoked from `stop-failure-marker.sh` between `:89`
   and `:115`, kind derived from `$ERR`** (`rate_limit` ⇒ `limited`, otherwise `failed`). Zero
   consumer changes, zero schema change, `operatorT` preserved by construction.
2. Reject: a new FIELD on the beat (`cause`/`account`). It widens the hottest writer on the box for
   a fact two other stores already hold, and the marker is the natural home for cause+account.
3. Reject: reusing an existing kind (`stop`). It would make a limit death indistinguishable from a
   clean Stop in `session_busy_live` and in any future census, for no saving.

## Tests that pin it

| test | file | asserts |
|---|---|---|
| `kind=limited is NOT counted mid-turn` | `tests/spawn-presence.bats` (beside the TZ case at `:536`, fixture style at `:554`) | two live beats, one `prompt` one `limited`, same live pid ⇒ `cc_sp_active` = 1 |
| `an UNKNOWN kind is not counted either` | same | kind `"zzz"` ⇒ same count (pins TOLERANCE, not one literal) |
| `kind=limited reads IDLE, never BUSY` | `tests/session-busy.bats` (`mk_beat` at `:38` already takes a kind; sibling case at `:131`) | live pid + `limited` ⇒ `IDLE-DEAF`, rc 1 |
| `the limited write preserves operatorT and who=auto` | `tests/session-beat.bats` (`emit()` at `:22`, kind assert at `:55`) | prompt beat with `operatorT` → `session-beat.sh limited` → `operatorT` unchanged, `who=auto`, `seq+1` |
| `a limited beat does not stand a parked watcher down` | `tests/cc-await-ping.bats` (the RED-PROOF case) | `_turn_moved` false at `base+1` with kind `limited` |
| `the ACTIVE term admits once phantoms are excluded` | `tests/capacity-admit-active.bats` (`sp cc_sp_active` style at `:261`) | 10 beats, 3 `limited` ⇒ count 7 ⇒ admit at ceiling 8 |
| ARITHMETIC PARITY (already exists — re-run it) | `tests/spawn-presence.bats` case P2 | `cc_sp_active` / `cb_system_live` must not disagree over a fixture containing `limited` |

## Unmeasured / UNMEASURABLE here

- Whether `StopFailure` fires for the Fable-scoped cap (`quotaLimits` NULL) — out of this unit's scope.
- Whether a second hook entry on `StopFailure` runs before/after the marker — not probed (no writes).
- `session_busy_live` on a limited session renders `IDLE-DEAF` ("no wake path"), which is *true* but
  names the wrong reason; a `LIMITED` state would be a separate, larger change to `session-busy.sh`'s
  state enum and its renderers, and is NOT part of the minimal write.
- Instrument defect recorded so it is not repeated: my first transcript sweep omitted
  `~/.claude-secondary/projects` and reported 3 sids as NO-TRANSCRIPT. `measure-terminations.py:86-91`
  has the correct four-root list; my probe did not. Re-run with the right roots gave 0 no-transcripts.
