# G — How teammate child sessions actually END (measured, 30 days, 4 config dirs)

**Scope frozen:** every top-level transcript carrying `agentName` + `teamName` + `isSidechain:false`
with a first record in 2026-08-20 → 2026-09-19, across `~/.claude`, `~/.claude-secondary`,
`~/.claude-tertiary`, `~/.claude-quaternary` (`~/.claude-next` is a symlink to `~/.claude`;
de-duplicated by `find -H`). **n = 278 teammate sessions, 71 leads.**
Per-session data: `G-teammate-end-states.csv` beside this file (58 columns).
Everything below is EMPIRICAL from transcripts + `~/.claude/logs/teammate-lifecycle.log` +
`~/.claude*/teams/*/config.json` unless a line is marked INFERRED.

---

## The headline: a harness-version regression multiplied teammate residency by ~2,400×

> 🚨 **SUPERSEDED 2026-09-19 — this whole section is a TIMEZONE ARTIFACT and is RETRACTED. See § RETRACTION — timezone at the end of this file. Corrected: both versions close at a median 0.05 min; there is no version effect.**

`2.1.220` → `2.1.260` (cutover in this fleet **2026-09-04**, see the per-day version table below)
changed *when* the harness delivers the `TeammateIdle` event. Our `TeammateIdle` hook
(`hooks/teammate-auto-shutdown.sh`, registered in `~/.claude/settings.json` under `TeammateIdle`)
has **no idle threshold of its own** — its own header says it "Fires (LEAD-side) when a teammate goes
idle after finishing its turn" and line 516 says "TeammateIdle fires on turn-boundary silence". So
the clock below is the product's, not ours.

Interval measured = **teammate's last transcript record → `✓ closed pane N (<member>)` in the
lifecycle log** (n=206 sessions that have both):

| version | n | median | <1 min | 115–121 min |
|---|---|---|---|---|
| **2.1.220** | 107 | **0.05 min (3 s)** | 106 | 1 |
| **2.1.260** | 99 | **120.05 min** | 5 | 94 |

The distribution is **perfectly bimodal with nothing in between**: 111 closes under 1 minute, 95 in
the 115–121 min band, **0 in the 1–115 min gap**. In the slow band the log's own
`Auto-shutdown idle teammate: <name>` line is timestamped at the close instant
(e.g. `skills`/`session-eda3a683`: last record `2026-09-16T03:38:18Z`, first auto-shutdown log line
`05:38:18Z`, pane closed `05:38:21Z`), so the **hook ran at +120 min** — the event was delivered late,
the hook did not wait. INFERRED: 2.1.260 gates `TeammateIdle` behind a ~2 h idle timer.

**Cost, lower bound:** summing last-real-work → best end evidence across all 278 sessions gives
**219.7 teammate-hours resident after the work was finished**, of which **202.2 h (92%) is 2.1.260**.
It is a lower bound because 72/278 have no close event, so their clock stops at the last transcript
record (see § Unknown bucket).

---

## (a) Population

| config dir | teammate sessions | distinct leads | 2.1.220 / 2.1.260 | got a `shutdown_request` |
|---|---|---|---|---|
| `~/.claude` | 56 | 17 | 19 / 37 | 13 |
| `~/.claude-secondary` | 94 | 23 | 73 / 21 | 14 |
| `~/.claude-tertiary` | 57 | 14 | 33 / 24 | 8 |
| `~/.claude-quaternary` | 71 | 17 | 11 / 60 | 14 |
| **total** | **278** | **71** | **136 / 142** | **49 (17.6%)** |

Members per lead: 22 leads had 1, 10 had 2, 7 had 3, 9 had 4, and the tail runs to two leads with 13
(`session-6d405232`, `session-c946091d`). Per-day version split (first record):
`2026-08-20 … 09-03` = 2.1.220 only; `09-04` = 4/6 mixed; `09-08` onward = 2.1.260 (one 2.1.220 straggler).

---

## (b)(c) End-state distribution

Classifier precedence: `pane_gone` → `closed_pane` (bucketed by latency) → close-refused → any
reaper trace → nothing.

| end state | n | % | what the evidence actually is |
|---|---|---|---|
| `pane-closed-prompt(<5m)` | 110 | 39.6% | `✓ closed pane` within 5 min of the last record (105 of these are 2.1.220) |
| `pane-closed-delayed(115-121m)` | 95 | 34.2% | `✓ closed pane` at the 2 h band (94 of these are 2.1.260) |
| `no-lifecycle-evidence(UNKNOWN)` | 44 | 15.8% | zero lines in `teammate-lifecycle.log`; transcript just stops |
| `reap-deferred-never-closed` | 18 | 6.5% | reaper fired, deferred (dirty/shared tree), pane never closed |
| `reap-REFUSED-never-closed` | 10 | 3.6% | `✗ pane close FAILED` / `✗ identity pin REFUSED`, no close ever |
| `pane-already-gone` | 1 | 0.4% | `~ pane N (…) already gone` |

Split by version — the shape of the whole fleet changed on 2026-09-04:

| end state | 2.1.220 (n=136) | 2.1.260 (n=142) |
|---|---|---|
| closed prompt (<5 m) | **105** | 5 |
| closed delayed (~120 m) | 1 | **94** |
| no lifecycle evidence | 21 | 23 |
| reap deferred, never closed | 7 | 11 |
| reap REFUSED, never closed | 1 | 9 |
| pane already gone | 1 | 0 |

**Classes the brief asked for that have ZERO instances, and why:**
- **`TaskStop`** — not observable from a teammate transcript. No record type, subtype or field records
  it. The only system subtypes present across all 278 files are `stop_hook_summary` (422),
  `turn_duration` (341), `away_summary` (36). **There is no `SessionEnd`-type record in a teammate
  transcript at all** — so "the session ended" is never self-evidenced; it is always inferred from a
  second store.
- **`recycle-kill` / `crash`** — indistinguishable from any other silent stop for the same reason.
  They are inside the 44 + 28 no-close cases, unseparated. Stated, not guessed.
- **approved-shutdown as a terminal class** — see (e); it is a real mechanism but it leaves no
  positive trace, only the absence of one.

---

## (d) Residency — last real work → end evidence

`last real work` = last `tool_use` timestamp, falling back to last assistant record.
`end evidence` = lifecycle-log close ts where one exists, else the last transcript record (a **lower
bound** in that case).

| bucket | ALL (278) | 2.1.220 (136) | 2.1.260 (142) |
|---|---|---|---|
| <1 min | 130 | 96 | 34 |
| 1–5 min | 19 | 16 | 3 |
| 5–30 min | 23 | 16 | 7 |
| 30–115 min | 9 | 5 | 4 |
| **115–121 min** | **83** | 1 | **82** |
| >121 min | 14 | 2 | 12 |

Session wall time (first→last record) is unremarkable by comparison: median 11.7 min, p90 57.8 min,
max 733 min. The residency is not long work — it is finished work left plugged in.

---

## (b)(e) The `shutdown_request` channel, and what a teammate does between arrival and end

Only **49 of 278 (17.6%)** teammates ever received a `shutdown_request` at all. The other 229 were
never asked; they were reaped.

| reply shape | n | of 49 |
|---|---|---|
| **prose ack only** (no structured artifact) | 25 | 51% |
| **NO reply — never took another turn** | 9 | 18% |
| **took turns after it, never acknowledged** | 7 | 14% |
| **structured `shutdown_response` emitted** | 8 | 16% |

### The structured path terminates in seconds; the prose path does not terminate at all

For 7 of the 8 structured emitters the transcript **stops 0.0–3.6 s after the `SendMessage` call**,
and 5 of the 8 have **zero** lifecycle-log lines — nothing ever reaped them because there was nothing
left to reap:

| agent | version | `shutdown_response` → last record | log events | pane close |
|---|---|---|---|---|
| `undo-booking` | 2.1.220 | 0.0 s | 0 | none |
| `s60-guards` | 2.1.220 | 0.0 s | 4 | none |
| `s60-guards-2` | 2.1.220 | 0.0 s | 2 | none |
| `context2` | 2.1.220 | 2.0 s | 0 | none |
| `stamp-reach` | 2.1.220 | 3.6 s | 0 | none |
| `t6-assistant` | 2.1.260 | 0.0 s | 0 | none |
| `adj-cloud-refs` | 2.1.260 | 0.0 s | 2 | none |
| `band-hooks` | 2.1.260 | **39,326 s (10.9 h)** | 11 | none |

By contrast the 25 prose-ack teammates stop *talking* at a median 6.4 s after the ack — and then
**22 of 25 still needed the reaper to close their pane** (19 prompt, 3 at the 2 h band); 3 more have
no evidence either way. **This confirms `TEAMMATE_SELFCLOSE_INVESTIGATION.md` D2** ("prose that means
yes is not the artifact"): prose ends the turn, the structured response ends the process.

### …but the structured artifact is mostly unreachable, which is why it is only 16%

Two measured obstructions, both in the teammate's own transcript:

1. **`SendMessage` is refused outright in some teammate sessions on 2.1.260.** 11 of 89 sessions that
   called `SendMessage` got an error; 7 of those 11 (all 2.1.260, 0 on 2.1.220) got the verbatim
   `<tool_use_error>Error: No such tool available: SendMessage. SendMessage is disabled for this
   session, in subagents as well as here.</tool_use_error>` — hit by `band-hooks`, `backlog-floor`,
   `adj-b` among others. `band-hooks` is the one structured emitter that survived (10.9 h) and it is
   exactly the one whose call was refused.
2. **The approval schema rejects the natural call.** 4 of 8 emitters (2.1.220: `context2`,
   `s60-guards`, `s60-guards-2`, `stamp-reach`) got
   `<tool_use_error>reason is only delivered on rejections (approve: false) — approvals are sent as a
   silent confirmation with no reason text; omit reason or reject instead</tool_use_error>`.

Consequence measured elsewhere in the corpus: teammates go looking for the tool and fail —
`F2-main-thread-audit` (2.1.260) answered the request with `ToolSearch {"query":"select:SendMessage"}`
→ `No matching deferred tools found`, then acknowledged in prose. `fp-axis3-soundness` (2.1.220)
wrote *"No SendMessage tool is exposed in this session, so acknowledging here."*

### Between arrival and end: the teammate is SILENT, not blocked

The brief's hypothesis was that Stop-hook blocks might keep an idling teammate taking turns. **It does
not happen, anywhere.** Across all 278 teammate transcripts there are **422 `stop_hook_summary`
records and every single one reads `preventedContinuation: false`, `level: "suggestion"`,
`stopReason: ""`, no `hookAdditionalContext`** — with 12–13 hooks running each time. Zero blocked
stops. A teammate's stop is never held open; `session-continue.sh`, `completion-assert.sh` and the
wake floor all abstain inside a teammate.

So for the 9 "no reply" cases the answer to (e) is unambiguous: **the request is the last record in
the file.** The teammate had already stopped, took no further turn, and nothing woke it.

**Excerpt 1 — `lint-window-id`, team `session-d02d8feb`, `~/.claude-quaternary`, 2.1.260** (idle
10.9 min before the request; the request is the final content record):
```
[2026-09-19T15:59:42Z] system away_summary
[2026-09-19T16:07:23.421Z] user  <teammate-message teammate_id="team-lead">
  {"type":"shutdown_request","requestId":"shutdown-1789834043048@lint-window-id","from":"team-lead",
   "reason":"Your rule, generator, list, tests and wiring were reviewed, run through the gate engine
   and the suites by the lead, and are committed. Nothing furthe…
[no timestamp] bridge-session / cost-state / last-prompt        ← end of file
```

**Excerpt 2 — same team, `e2e-legacy-nav`, still unreaped 2 h later** (lifecycle log, local time;
`10:55` local = `17:55Z` = exactly +120 min after its last record at `15:55:26Z`):
```
[2026-09-19 10:55:33]   ↳ e2e-legacy-nav: shared cwd dirty AND this member's own files are among the dirty ones — defer stands
[2026-09-19 11:02:11]   ↳ e2e-legacy-nav: worktree …/wt-cc-095358-75429 is SHARED by 3 members — gating on it, removal refused
[2026-09-19 11:02:12] ⚑ SURFACE e2e-legacy-nav (team=session-d02d8feb): reap-guard has deferred 3 times … Pane NOT closed
[2026-09-19 11:02:12]   ~ page suppressed (damped) [SHARED-CWD-NEVER-REAPS:session-d02d8feb:e2e-legacy-nav]
```

**Excerpt 3 — `band-hooks`, `~/.claude-secondary`, 2.1.260: the structured path refused mid-flight**
(request `07:33:28Z`, last record `18:28:59Z` — 10.9 h later):
```
[07:33:33.469Z] assistant TOOL_USE SendMessage {"to":"team-lead","message":"{\"type\":\"shutdown_response\",
                \"request_id\":\"shutdown-1788852808123@band-hooks\",\"approve\":true}"}
[07:33:33.472Z] user      <tool_use_error>Error: No such tool available: SendMessage. SendMessage is
                disabled for this session, in subagents as well as here.</tool_use_error>
[07:33:35.505Z] assistant TOOL_USE ToolSearch {"query":"select:SendMessage","max_results":3}
```

---

## Verification of the two prior measurements

| prior claim | verdict |
|---|---|
| `skills/agent-teams/SKILL.md:356-375` (2026-08-26): mid-turn 3/3 reaped, **idle 0/4**, survivors resident **20–40 min** with a queued shutdown | **CONFIRMED and now generalised.** 9/49 requests landed on an already-stopped teammate and produced **no further turn at all**; 0/278 teammates ever had a Stop-hook block that could have woken one. The "20–40 min" residency figure is a **2.1.220 number** — on 2.1.260 the equivalent wait is **120 min**, and `e2e-legacy-nav` is still unreaped past it today. |
| `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md` D2: prose "acknowledged — shutting down" does not terminate; only a structured `shutdown_response` does | **CONFIRMED, with the mechanism now measured on both sides.** Structured: 7/8 transcripts end within 0–3.6 s and 5/8 need no reaper at all. Prose: 22/25 still had to be pane-closed by `teammate-auto-shutdown.sh`. **New:** the structured artifact is only reachable 16% of the time — `SendMessage` is hard-refused in 7 sessions on 2.1.260 and the approval schema rejects `reason` on `approve:true`. |

One premise in the brief **does not hold**: *"members are REMOVED on an approved shutdown — so absence
is itself a signal."* Measured live today: `e2e-legacy-nav` and `lint-window-id` were **in**
`~/.claude-quaternary/teams/session-d02d8feb/config.json` at 2026-09-19T~18:05Z and **off the roster**
by ~18:25Z, having **never answered** the 16:07Z request and never taken another turn. Roster absence
records the **lead's** action, not the teammate's. Fleet-wide it is nearly useless as a signal anyway:
**251 of 278 teammates' team directories no longer exist at all** (deleted, not archived — 0 of our 278
are under `teams/_archive/`), so 254/278 read "absent" for a reason unrelated to shutdown.

---

## Adversarial pass — where this classifier is wrong, and by how much

**The case it mislabels.** `no-lifecycle-evidence(UNKNOWN)` (44, 15.8%) is a bucket, not a state, and
it provably contains at least two opposite things: a teammate the harness terminated cleanly on a
structured response (leaves no `TeammateIdle`, so no log line — 5 of the 8 structured emitters land
here) and a teammate that silently survived with no reaper ever reaching it. **I cannot separate them
from a transcript**, because no teammate transcript carries a session-end record of any kind. What is
measurable about the bucket: 28 of the 44 belong to a team where a **sibling WAS** closed by the
reaper, so the reaper was alive and simply never fired for them; their median wall time is 4.1 min and
median residency 0.15 min; 42 of 44 are off the roster and 41 of 44 have no team dir left.

**Honest size of the unknown.** Treating "the terminating act is not observed" as the criterion:
`no-lifecycle-evidence` 44 + `reap-deferred-never-closed` 18 + `reap-REFUSED-never-closed` 10 =
**72 of 278 = 25.9%**. For those 72 the residency figures in (d) are **lower bounds only** — the clock
stops at the last transcript record because nothing else ever wrote about them.

**Three more defects I found by looking for them, not by assuming they were absent:**
1. **Log-join collision risk.** A `✓ closed pane N (<name>)` line carries only the member NAME; I key
   it to the team named by the most recent `Auto-shutdown idle teammate:` line. 6 of 278 agent names
   are reused across two different teams (`microsoft`, `cloud-lane`, `local-lane`,
   `reg-vinyl-rooftop`, `reg-church-balcony`, `reg-vinyl-ground`) — a **2.2% maximum** cross-assignment
   exposure. The timezone join itself is sound: converting log local (`America/Los_Angeles`) to UTC
   gives a median close-minus-last-record of **+0.1 min** over 206 pairs with only 3 negatives
   (`reg-vinyl-rooftop` −0.01, `reg-church-balcony` −0.00, `blast-radius` −0.00 — a pane closed while
   the transcript was still flushing).
2. **`resp_count` counts an ATTEMPT, not a delivery.** Of 9 sessions emitting a `shutdown_response`
   tool call, exactly **one** (`r-agentreport`) has a `tool_result` confirming delivery — and that one
   never received a request. 5 got an explicit error, 3 have no result record because the session ended
   first. Any statement of the form "N teammates approved shutdown" is unsupportable; what is supported
   is "N emitted the artifact, and 7 of 8 stopped within 4 seconds".
3. **The `-mtime -31` discovery filter** bounds the population by file mtime, not by session start. It
   cannot have dropped an in-window session (a session starting after 2026-08-20 cannot have an mtime
   older than 31 d), and the one out-of-window file it pulled in (first record 2026-08-19) is excluded.
   Discovery used `/usr/bin/grep -l -F '"teamName":"session-'` over `projects/*/*.jsonl` at
   `-maxdepth 2`, which structurally excludes `<sid>/subagents/**` sidechain files; all 279 hits had
   `agentName` set and `isSidechain:false` in every record, so no lead transcript contaminated the set.

**The axis I assumed irrelevant and then checked:** whether the *lead's* state explains the 120-minute
band (a dead lead cannot fire a lead-side `TeammateIdle`). It does not — the band is explained entirely
by harness version (2.1.260: 94/99 slow; 2.1.220: 106/107 fast), and the slow cases have a live reaper
that logs `Auto-shutdown idle` at exactly +120 min, which a dead lead could not do.

---

## What this implies operationally (all three follow from the numbers above)

1. **A `shutdown_request` is not a teardown and, on 2.1.260, neither is a prose ack.** 51% of requests
   get prose; 22/25 prose acks then sat waiting for a pane close that now arrives 2 h later.
2. **The idle case — the one you always hit, because you tear a teammate down BECAUSE it finished —
   is the case where the cooperative path cannot fire at all.** 9/49 requests reached a session that
   never took another turn, and no Stop hook in this fleet can wake one (0/422 blocks).
3. **The 2 h band is a product-side change, not a regression in our hook**, so it cannot be fixed by
   tuning `TEAMMATE_MAX_DEFERS` or the reap guard. The lever is an actuator the lead runs itself
   (`TaskStop` per `SKILL.md:356-375`), not a longer wait.

---

### Method / re-derivation
Population: `find -H ~/.claude{,-secondary,-tertiary,-quaternary}/projects -maxdepth 2 -name '*.jsonl'
-mtime -31 | xargs /usr/bin/grep -l -F '"teamName":"session-'` → 279 files → 278 with first record
≥ 2026-08-20. Per-session fields streamed line-by-line (never whole-file). Team rosters from
`~/.claude*/teams/*/config.json` + `teams/_archive/*/config.json` (421 team dirs, 999 member entries).
Lifecycle events from `~/.claude/logs/teammate-lifecycle.log` (29,768 lines; single shared log — no
other config dir has one, and teams from all four appear in it). Live-residency cross-check via
`kitty @ ls` (7 windows) and `ps`. Read-only throughout: nothing killed, closed, torn down or messaged.

---

# § +120 min mechanism

> 🚨 **SUPERSEDED 2026-09-19 — the +120 min mode does not exist; it was a 2 h timezone conversion error. See § RETRACTION — timezone at the end of this file.**

Appended 2026-09-19 answering the coordinator's four follow-ups, over the same 278-session index
(`G-teammate-end-states.csv`). Subject = the **95** `pane-closed-delayed(115-121m)` sessions (94 of
them 2.1.260), control = the **106** 2.1.220 sub-minute closes.

**Verdict in one line: the 2.1.260 delay is a MISSING first fire, not a slow or refused one.** No
`TeammateIdle` invocation exists at turn end for any of the 95 — not a defer, not an rc=66/67
refusal, not a birth-grace or adoption hold, and nothing in the teammate's own transcript marks the
+120 moment either. The first hook invocation of any kind IS the one at +120 min.

## 1 — What `teammate-lifecycle.log` holds between the last record and the close

Window = `(last transcript record, pane-close − 5 s)`, log local time converted
`America/Los_Angeles` → UTC.

| what the window contains | members | share |
|---|---|---|
| **NOTHING — not one line mentioning the member** | **60** | **63.2%** |
| reap-guard shared-cwd / worktree notes only | 12 | 12.6% |
| defer + reap-guard notes | 12 | 12.6% |
| adoption/presence hold + defer + notes | 7 | 7.4% |
| a *second* `Auto-shutdown idle teammate:` fire (+ checkpoint / PPID-forensic) | 4 | 4.2% |

Aggregate line kinds inside all 95 windows: reap-guard shared-cwd notes 119 · worktree notes 130 ·
`defer …(k/3)` 60 · adoption/presence hold 55 · `~ page suppressed (damped)` 48 ·
`Auto-shutdown idle teammate:` 7 · checkpoint 1 · fallback patch 1 · PPID-forensic 1.

**The decisive statistic is the *earliest* line, not the mix.** Minutes from the teammate's last
transcript record to the FIRST log line of any kind naming it (n = 95):

| bucket | n |
|---|---|
| **< 5 min (a first fire at turn end)** | **0** |
| 5–115 min | 8 (earliest 51.88 min) |
| **115–121 min** | **87** |

median **119.96 min**, p10 115.65, max 119.99. So for every one of the 95 the hook's first contact
with that member came at least **51.9 minutes** after it stopped working, and for 87 of them at
essentially exactly two hours. Everything in the table above — the defers, the adoption holds, the
shared-cwd notes — happens *at or after* that first late fire, never before it.

## 2 — What sits at ≈ +120 min in the teammate's own transcript: nothing

For the 95, the offset from last real work (last `tool_use`/assistant record) to the LAST
**timestamped** record in the file:

| bucket | n |
|---|---|
| < 5 min | **89** |
| 5–115 min | 5 |
| ≥ 115 min | 1 |

median **0.23 min (14 s)**, p90 1.52 min. The file simply ends at turn end. The trailing sequence is
the ordinary turn-close one — `assistant` → `user` → `attachment` → `system/stop_hook_summary`
and/or `system/turn_duration` — followed by **untimestamped** `last-prompt` + `cost-state` (sometimes
`bridge-session`), which carry no clock and therefore cannot be the +120 marker.

Twelve worked examples (agent | last timestamped record | pane close | last-record offset from last
real work | trailing timestamped record types):

| agent | last record (UTC) | pane close (UTC) | offset | trailing records |
|---|---|---|---|---|
| `skills` | 2026-09-16T03:38:18.602Z | 05:38:21Z | +0.18 m | assistant, user, attachment, `stop_hook_summary` |
| `rewrite-model-local` | 2026-09-15T12:45:43.536Z | 14:45:46Z | +0.35 m | attachment, user, attachment, `stop_hook_summary` |
| `local-apps` | 2026-09-15T19:46:07.282Z | 21:46:07Z | +0.15 m | attachment, `turn_duration`, user, queue-operation |
| `agent-cli` | 2026-09-15T20:37:29.722Z | 22:37:33Z | +0.22 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `local-only-check` | 2026-09-15T06:25:57.033Z | 08:26:00Z | +0.22 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `extraagents` | 2026-09-16T04:30:13.980Z | 06:30:17Z | +0.26 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `microsoft` | 2026-09-15T15:11:57.871Z | 17:12:01Z | +0.28 m | attachment ×2, `turn_duration`, user |
| `microsoft-2` | 2026-09-15T21:41:04.140Z | 23:41:07Z | +0.23 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `ghcli` | 2026-09-16T03:33:18.737Z | 05:33:21Z | +0.20 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `configdir` | 2026-09-16T04:05:40.854Z | 06:05:44Z | +0.25 m | assistant, user, attachment, `stop_hook_summary` |
| `agentenv` | 2026-09-16T03:35:35.593Z | 05:35:38Z | +0.23 m | `stop_hook_summary`, attachment ×2, `turn_duration` |
| `agent-config` | 2026-09-15T19:44:05.758Z | 21:44:06Z | +0.13 m | attachment, `turn_duration`, queue-operation ×2 |

Paths for the first three (the rest are in the CSV's `path` column):
`~/.claude/projects/-Users-chrisren-Development-mac-bootstrap/df81fdf9-a620-4d72-bcc4-00ab2a31dab9.jsonl`
(`skills`, team `session-eda3a683`),
`…/6e6b9db2-cd9d-44ce-9066-0c3a5ab0619d.jsonl` (`rewrite-model-local`, `session-085ee6d8`),
`…/1c57d9fa-0e80-46bd-9ec4-8aa9166dd329.jsonl` (`local-apps`, `session-59ed2093`).

**The away-summary hypothesis is refuted.** `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=true` is set in the
`env` block of all four `settings.json` (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`), and
the feature does emit: 36 `system`/`away_summary` records across the 278 sessions. But it fires
**early, not at the 2 h mark** — corpus-wide offsets from last real work run min −672.0 / median
**3.9** / max 49.4 minutes, and **0 of 36 land in the 115–121 min band**. Within the 95 delayed
sessions only 5 carry one at all (median offset 4.6 min, max 13.1). So the +120 event is not the
away-summary turn.

**Nor is it visible on the lead side.** Sampling 3 of the 95 against their lead's transcript
(`session-4899dafd`, members `A6-blocked` / `A5-uptime` / `A1-cloud-outcomes`, lead transcript
`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/3a9761b3-0539-4609-a48f-3cbe9f0c6811.jsonl`),
the lead has **0 timestamped records within ±2 min** of each pane close. The `TeammateIdle`
invocation writes to neither transcript; our own log line is its only footprint.

## 3 — Control: on 2.1.220 the first fire at turn end succeeded, 106/106

Every one of the 106 sub-minute 2.1.220 closes has an `Auto-shutdown idle teammate: <name>` line,
and it is stamped at the turn boundary:

| \|Δ\| between last record and first auto-shutdown line | n |
|---|---|
| ≤ 5 s | **98** |
| ≤ 30 s | 2 |
| ≤ 5 min | 1 |
| > 5 min (all NEGATIVE — an earlier in-session fire) | 5 |

Core (n = 101, \|Δ\| ≤ 5 min): min −247.8 s, **median −1.3 s**, max **+1.0 s**. The median is
*negative* because the hook runs at the turn boundary and the teammate's final `stop_hook_summary` /
`turn_duration` record is flushed about a second later — i.e. the fire is simultaneous with the stop,
not after it. The five outliers (`A4-abnormal-death` −19.0 m, `W4d` −7.6 m, `W4c` −35.0 m,
`ratify-desk` −7.2 m, `A7-RISK` −218.3 m) are members that got a fire, then did more work.

Same measurement on the 95 delayed: **93 of 95 in the 115–121 min band**, 2 negative outliers. So the
difference between the two versions is entirely in *whether a fire happens at turn end*, not in how
fast the hook runs once it does — the hook's own close latency is ~3 s in both regimes
(close − first-auto line).

## 4 — Failed first attempts among the 95: none exist

There is **no log line of any kind** within 5 minutes of the last record for any of the 95 (§1), so
there is no turn-end failure string to name. **rc=66 and rc=67 do not appear at all** in these 95
members' post-last-record spans (rc=67 — the composer-guard `refusing to close window N — composer
state is UNKNOWN` — is real in this log but belongs to other members, e.g. panes 89/90 on
2026-09-17).

Failures that DO occur, all of them *after* the late first fire, across 42 of the 95:

| failure string | count |
|---|---|
| `✗ identity pin REFUSED the close of pane N (<name>) — wrong window, wrong kitty generation, or unverifiable` | 43 |
| `✗ pane close FAILED (rc=1) for N (<name>)` | 4 |

These are re-fires hitting a pane that the successful close (or a kitty restart) had already removed
— consequences of the delay, not its cause.

## What this rules in and out

| candidate mechanism | verdict |
|---|---|
| hook is slower on 2.1.260 | **refuted** — close latency after the fire is ~3 s in both versions |
| first fire happened and was DEFERRED (dirty/shared tree, birth grace) | **refuted** — 0 of 95 have any line < 5 min; every defer observed post-dates the +120 fire |
| first fire happened and the pane close was REFUSED (rc=66/67, identity pin) | **refuted** — no rc=66/67 at all; the 43 identity refusals are all post-+120 re-fires |
| the +120 record is the `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` turn | **refuted** — 0 of 36 `away_summary` records fall in 115–121 min; median offset 3.9 min |
| **2.1.260 does not deliver `TeammateIdle` at turn end; the first delivery is ~2 h later** | **supported** — the only hypothesis consistent with 0 lines < 5 min, 87/95 lines at 119.96 min, 106/106 fires at ±5 s on 2.1.220, and no transcript footprint on either side |

Residual uncertainty, stated rather than hidden: this establishes *when the hook was invoked*, which
is a lower bound on *when the event was delivered* — a delivery that reached a process whose hook
runner was blocked would look identical. Nothing in either transcript or in `ps` can separate those
two, because the invocation leaves no record outside our own log. The 8 members whose first line
lands at 51.9–115 min rather than ~120 are unexplained by this account and are named in the CSV
(`log_first_auto` minus `last_ts`).

---

# § RETRACTION — timezone

**Appended 2026-09-19. The `+120 min` mode does not exist. It is a two-hour timezone conversion
error of mine, and it invalidates this file's original headline, its end-state split, its residency
distribution, its `219.7 teammate-hours` figure, and the entire `§ +120 min mechanism` section.**

## 1 — The artifact and the correct offset

`~/.claude/logs/teammate-lifecycle.log` is stamped in the **box's local time at the moment of
writing**, with no zone marker. I converted every line as `America/Los_Angeles` (PDT, UTC−7). The
box's zone is `America/Chicago`: `/etc/localtime -> /var/db/timezone/zoneinfo/America/Chicago`, and
`date` returns `CDT-0500`.

The coordinator's correction is right about the effect and understates the cause — **the zone changed
mid-window**, which is exactly why the artifact looked like a version regression. Measuring the raw
(unconverted) log stamp against each teammate's UTC last record over all 206 closes gives **exactly
two offsets and no mixing**:

| era | offset of the log's naive stamp vs UTC | closes | dates covered |
|---|---|---|---|
| 2026-08-20 → **2026-09-04** | **−7 h (PDT, America/Los_Angeles)** | 111 | every close in that range |
| 2026-09-08 → 2026-09-18 | **−5 h (CDT, America/Chicago)** | 95 | every close in that range |

The switch is dated independently: `/etc/localtime`'s symlink mtime is **Sep 6 23:49**, and the log
has **no lines at all between 2026-09-04 and 2026-09-07 19:27**, so no record's era assignment is
ambiguous. My blanket PDT conversion was therefore **correct for the first era and exactly +2 h wrong
for the second** — which is the 120-minute "mode", to the minute.

**Why it masqueraded as a version regression:** the 2.1.220→2.1.260 cutover in this fleet was
2026-09-04 and the zone change was 2026-09-06 — **two days apart**. Version was a near-perfect proxy
for era, so the version cross-tab (106/107 fast on 2.1.220, 94/99 slow on 2.1.260) was *true* and
*causally empty*. Corrected conversion (`America/Los_Angeles` before the `/etc/localtime` mtime,
`America/Chicago` after; equivalently `.astimezone()` for anything recent):

| | n | median | p10 | p90 | max | <1 min |
|---|---|---|---|---|---|---|
| **2.1.220** | 107 | **0.05 min** | 0.04 | 0.06 | 0.25 | **107/107** |
| **2.1.260** | 99 | **0.05 min** | 0.01 | 0.05 | 0.06 | **99/99** |

**All 206 closes land under 1 minute. The version effect is zero.** The coordinator's worked example
reproduces: `capability-per-token`, close `2026-09-16 19:05:51` CDT = `00:05:51Z` against a last
record of `00:05:48.188Z` → **+2.8 s**.

## 2 — Corrected end-state and residency numbers

**End states** (same classifier, corrected clock):

| end state | ORIGINAL (wrong) | **CORRECTED** | 2.1.220 | 2.1.260 |
|---|---|---|---|---|
| `pane-closed-prompt(<5m)` | 110 | **205** | 106 | 99 |
| `pane-closed-delayed(≥115m)` | 95 | **0** | 0 | 0 |
| `no-lifecycle-evidence(UNKNOWN)` | 44 | 44 | 21 | 23 |
| `reap-deferred-never-closed` | 18 | 18 | 7 | 11 |
| `reap-REFUSED-never-closed` | 10 | 10 | 1 | 9 |
| `pane-already-gone` | 1 | 1 | 1 | 0 |

**Residency** (last real work → end evidence), side by side:

| statistic | ORIGINAL ALL | **CORRECTED ALL** | **CORRECTED 2.1.220** | **CORRECTED 2.1.260** |
|---|---|---|---|---|
| n | 278 | 278 | 136 | 142 |
| median | 3.3 min | **0.34 min (20 s)** | **0.45 min** | **0.27 min** |
| p75 | 120.2 min | **0.77 min** | 2.11 min | 0.44 min |
| p90 | 120.4 min | **9.67 min** | 10.62 min | 6.16 min |
| max | 540.7 min | 420.72 min | 222.46 min | 420.72 min |

Corrected buckets — the 115–121 min band is **empty**:

| bucket | ALL | 2.1.220 | 2.1.260 |
|---|---|---|---|
| <1 min | **213** | 97 | 116 |
| 1–5 min | 25 | 16 | 9 |
| 5–30 min | 28 | 16 | 12 |
| 30–115 min | 9 | 5 | 4 |
| 115–121 min | **0** | 0 | 0 |
| >121 min | 3 | 2 | 1 |

The first-fire control now covers both versions rather than one: of 218 members with an
`Auto-shutdown idle teammate:` line, **192 fire within |Δ| ≤ 5 s** of the teammate's last record and
10 more within 30 s (median **−1.4 s**; negative because the hook runs at the turn boundary and the
teammate's final `stop_hook_summary` flushes a second later). 13 outliers are all earlier in-session
fires. **`hooks/teammate-auto-shutdown.sh` fires at turn end and closes the pane ~3 s later, on
2.1.220 and 2.1.260 alike.**

## 3 — The teammate-hours figure, re-derived

| | ORIGINAL | **CORRECTED** |
|---|---|---|
| total resident-after-work | 219.7 h | **29.7 h** |
| 2.1.260 share | 202.2 h (92%) | **14.2 h (48%)** |
| 2.1.220 share | 17.5 h | **15.5 h** |

Of the corrected 29.7 h, **23.7 h** comes from the 206 sessions with an observed close (median
**0.36 min** each — this is essentially just normal turn-end latency summed over 206 members), and
**6.0 h** from the 72 sessions with no close at all, which remain **lower bounds** because nothing
ever wrote about them. There is no 2-hour tax. The only real residency left is the long tail: 3
sessions over 121 min and 9 in the 30–115 min band, which are individual reap-guard defers
(dirty/shared worktrees), not a systemic mode.

## 4 — What survives, what dies

**DEAD** (retracted): the headline version regression and the "~2,400×" claim · the
`pane-closed-delayed(115-121m)` class (95 → 0) · the 219.7 h figure · the whole `§ +120 min
mechanism` section, including its Q1 "60/95 have NOTHING in the window" (the window was 2 h too long;
at the true close it is ~3 s wide and empty for everyone, which is the healthy state) and its Q2/Q4
findings, which answer a question that no longer exists · operational implication #3 ("the 2 h band is
a product-side change").

**STILL STANDS** — none of it touches the lifecycle log's clock, because it is computed inside
transcripts, which are stamped in UTC:
- Population: 278 teammate sessions, 71 leads, per-config-dir table.
- No teammate transcript carries a `SessionEnd`-type record; only `stop_hook_summary` (422),
  `turn_duration` (341), `away_summary` (36). `TaskStop`/crash/recycle remain unobservable.
- **0 of 422 `stop_hook_summary` records have `preventedContinuation:true`** — a teammate's stop is
  never held open by a Stop hook.
- The `shutdown_request` channel: 49/278 received one; prose 25, no-reply 9, turns-no-ack 7,
  structured 8; 7 of the 8 structured emitters stop within **0.0–3.6 s** of the `SendMessage` call
  while 22/25 prose acks still needed a pane close. `SendMessage is disabled for this session` on 7
  sessions (all 2.1.260); the `reason is only delivered on rejections` schema error on 4 (2.1.220).
  Only 1 of 9 `shutdown_response` calls has a `tool_result` confirming delivery.
- Roster absence is the **lead's** action, not the teammate's (`e2e-legacy-nav` / `lint-window-id`,
  2026-09-19), and 251/278 team directories no longer exist at all.
- The unknown bucket: **72/278 = 25.9%** have no observed terminating act.
- The away-summary check: `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=true` in all four `settings.json`; 36
  records, median offset 3.9 min from last real work. (True, and now answering nothing.)

## 5 — Why my own checks did not catch it

I ran a validation and it passed for the wrong reason. The original file says the timezone join is
*"sound: median close-minus-last-record of +0.1 min over 206 pairs with only 3 negatives."* That
median was computed over a **bimodal** population — 111 points at ~0 and 95 at ~120 — and a median
over two modes validates neither. The 3 negatives came entirely from the correct-era half, so the
"only 3 negatives" reassurance was measuring the arm that was already right.

Every corroborating check I ran afterwards (version cross-tab, per-day cutover table, the Q1 window
census, the Q3 control) was computed **inside the contaminated instrument**, and each one agreed,
because within each era the instrument is internally consistent. The check I never ran was the one
that tests the instrument against a second clock — which is what the coordinator ran, and it took one
example to kill 95 data points. This is the corpus's `wrong-cause-corroborated-by-true-metric` shape:
the version split was a **true measurement** sitting beside a **false cause**, and the true half made
the false half read as diagnosed.

**The rule this earns:** a log with a bare local timestamp is an instrument with an undeclared zone,
and a zone is a property of the *machine at write time*, not of the file. Before any cross-store
join, census the raw offset between the two stores and require it to be **unimodal**; a bimodal
offset is a clock change, never a finding. Two modes exactly `n` hours apart is a timezone, not a
mechanism.

## 6 — Regenerated artifact

`G-teammate-end-states.csv` has been rewritten from the corrected clock: 278 rows × 53 columns, now
carrying **`close_minus_last_min`** (the corrected close − last-record interval in minutes) plus
`first_auto_minus_last_s`, with `log_close_ts` / `log_fail_ts` / `log_first_auto` / `resid_min` /
`sd_to_close_min` / `endstate` all recomputed. The conversion boundary is the `/etc/localtime` mtime
(2026-09-06 23:49 local); the log is silent from 2026-09-04 to 2026-09-07 19:27, so nothing falls in
the ambiguous gap. **Residual:** that mtime is itself a local stamp, so the boundary carries the same
±2 h uncertainty — it does not matter here only because no log line exists within 3 days of it.
