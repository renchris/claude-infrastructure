# The beat producer was never broken — cc-backlog 02c8b96e55b9, REFUTED

**Date:** 2026-09-09 · **Item:** `02c8b96e55b9` (filed 2026-08-20T20:10Z) · **Verdict:** premise refuted,
residual attribution defect fixed.

## What the item claimed

> the session per-turn TELEMETRY writer is ALIVE while its BEAT writer is dead, so they are
> independent producers and a blanket "this session hooks are broken" explanation is refuted …
> Both are per-turn-boundary writes for the SAME session at the SAME moment, so the failure is
> specific to the beat producer, not to this session hook execution in general. ELIMINATES
> candidate 1 (session-wide dead/erroring hook).

Its evidence: `cc-context` listed sid `781b64cd` at age=1s while `~/.claude/cc-beats/781b64cd-*.json`
sat frozen at `seq=8`, hours stale, which is what made `cc-await-ping --idle-scoped` refuse
`reason=stale-beat`. It left two candidates open (a sid re-keyed by recycle-in-place; a producer that
skips sessions under a live `/goal`) and proposed a probe to separate them.

## The premise does not hold: the two producers have different cadences

The inference needs both writers to fire at turn boundaries. They do not.

| producer | file | fires |
|---|---|---|
| beat | `~/.claude/cc-beats/<sid>.json` | `hooks/session-beat.sh`, wired at **UserPromptSubmit and Stop** — true turn boundaries |
| telemetry | `/tmp/cc-telemetry/<sid>.json` | the **statusline** (`~/.claude/statusline.sh`), re-run on every render |

`bin/cc-context:9` says the statusline "exports it to `/tmp/cc-telemetry/<session_id>.json`", and
`:29` calls that "on each turn boundary" — but that phrase is a **comment**, and nothing executes a
comment. Measured live on this session, inside a single turn with exactly one submitted prompt and no
Stop:

```
CALL A t=1789003665 telem_mtime=1789003664 beat_t=1789003484 beat_seq=1
CALL B t=1789003667 telem_mtime=1789003665 beat_t=1789003484 beat_seq=1
```

Telemetry advanced between two consecutive tool calls; the beat held at `seq=1` for 183s+ across the
whole turn. So **fresh telemetry beside a stale beat is the ordinary, healthy signature of a session
inside a long turn** — not evidence about the beat producer.

Two consequences for the item:

1. Its central inference does not follow. The observation has no power to localise a fault.
2. Its stated *elimination* is also invalid, in the opposite direction. The telemetry writer is the
   statusline, **not a hook**, so its liveness says nothing whatever about hook execution — candidate
   1 (session-wide dead/erroring hook) was never eliminated by this evidence.

## The producer was demonstrably alive — including for the item's own session

The item recorded `781b64cd` "frozen at seq=8". The store today reads **`seq=59`**: 51 further beats
after the moment it was called dead.

Generalised over every real `stale-beat` refusal on this box (9 distinct sessions), comparing the
final `beat.t` against the last record in each session's own transcript:

| sid | seq now | beat.t vs transcript end |
|---|---|---|
| 0e965e62 | 26 | 84s |
| 1a78a148 | 71 | 124s |
| 52e35019 | 68 | 520s |
| 781b64cd | 59 | 90s |
| 7e05b1dc | 56 | 119s |
| 8af1ab5d | 29 | 78s |
| 94ccf559 | 15 | 64s |
| a6f08e63 | 10 | 190s |
| 2de07510 | 15 | beat.t *after* the transcript end (resume/continuation, not a dead producer) |

**9 of 9 producers beat right up to their session's last record. Zero true positives.**

### The item's own 4.4h gap, to the minute

Reconstructing `781b64cd`'s genuine prompt boundaries (user records that are neither `tool_result`
nor `isMeta`) gives 31 boundaries, and its largest gap is **4.66h — 2026-08-20T15:44:02Z ->
20:23:27Z**. The item was filed at **20:10:48Z**, i.e. *inside* that gap, and the refusal it quoted
reported the beat as **15,937s = 4.43h** old. `20:10:48 - 15:44:02 = 4.44h`. The arithmetic closes
exactly: the beat was written at the 15:44 boundary, the session had no further boundary until
20:23, and the beat advanced again the moment one arrived.

Nothing was frozen. The producer wrote at every boundary it was given; there simply was not one for
4.7 hours, while the statusline kept the telemetry file a second old throughout.

Instrument note, per the house rule that a grep counts readers: 259 transcripts *mention* `stale-beat`
and only **10** carry the emitted `verdict=refused reason=stale-beat` — 96% are sessions that merely
read the source. The census above uses the emitted verdict string only.

## The real defect: a confounded statistic wearing a causal explanation

`bin/cc-await-ping` refused with:

> An arm happens INSIDE a turn, so a live beat producer makes this seconds old — a stale one means
> either the producer is not running or the sid is not this session's.

An arm does happen inside a turn — and that is precisely why the claim fails. The newest beat at arm
time is **this turn's opening beat**, so `now - beat.t` measures **how long the current turn has been
running**, a quantity with no upper bound on a healthy session. A dead producer and a long turn drive
it up identically; the statistic cannot separate them. This is the shape the corpus already names in
*freshness-is-relative-to-the-subject-not-the-clock*: an absolute `now - heartbeat < bound` answers a
question about the clock and gets read as an answer about the subject.

## What changed, and what deliberately did not

**Kept: the refusal.** Fail-closed is correct here and the arithmetic is cheap. A false *pass* arms
the starvation pole (a watcher parked forever over an oracle that can never fire); a false *refusal*
merely declines to park, which is the wanted polarity under a goal.

Measured cost, against a denominator that is actually idle-scoped: **71** `stale-beat` emissions
beside **446** `stood-down` (the C2 exit, which only the idle-scoped mode emits) and 268 `no-beat` /
4 `no-session-id` / 4 `no-mailbox-lib`. So `stale-beat` is ~9% of *decided* idle-scoped arms and a
far smaller share of attempts. **`verdict=delivered` is deliberately excluded**: the bare form emits
it too, so folding its 5,189 in would have inflated the denominator with a different population —
the first draft of this note did exactly that and reported "~1% of 5,632", which is wrong.

The bound (`CC_AWAIT_BEAT_FRESH_S`, 900s) is unchanged; loosening a fail-closed gate on a separator
that has so far produced only false positives would be exactly the move the corpus warns against.

**Fixed: the attribution.** The message no longer asserts a mechanism the evidence refutes, and it now
reports `seq` and `kind` — the two fields that *do* separate the states. A live producer inside a long
turn shows `kind=prompt` with a `seq` that climbs across reads; a genuinely dead one shows a `seq`
frozen forever. That message is what sent a 20-day dispatch cycle hunting a producer that was never
broken, so correcting it is the durable half of this item.

`tests/cc-await-ping.bats` carried the same false cause in a test *name*
("the producer is not running, or the sid is not ours"). Renamed, plus a red-proof case asserting the
refuted sentence is gone and `seq`/`kind` are present.

## The two candidates the item left open

Neither needs the proposed probe, because the symptom they were competing to explain is not a fault.

- **sid re-keyed by recycle-in-place** — a recycle starts a *new session with a new sid*, so the old
  sid's beat correctly freezes and the new one advances. The item's own note that pane 102 carried
  two sids (`781b64cd` seq 8, `6b720014` seq 103) is that working as designed, not a re-keying bug.
- **producer skips sessions under a live `/goal`** — refuted directly: `781b64cd` went on to `seq=59`,
  and `hooks/session-beat.sh` has no goal-aware branch. Its own header records why auto-traffic still
  beats (`who=auto`): Stop-hook feedback and task notifications arrive through UserPromptSubmit.
