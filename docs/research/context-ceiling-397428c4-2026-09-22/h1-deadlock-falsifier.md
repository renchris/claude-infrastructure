# H1 — "the deadlock": does an armed session-continue chain suppress boundary-handoff?

## VERDICT

**H1 REFUTED AS A *STRUCTURAL DEADLOCK* (n=11 co-occurrences: 1 inside an armed interval + 10 within
5 s of a session-continue block) — but the SUPPRESSION IT PREDICTS IS REAL, LARGER THAN CLAIMED, AND
DELIBERATE: it is an explicit `abstain "continue-hook-armed"` compose-guard at
`hooks/boundary-handoff.sh:450`, not a block collision.**

One sentence: the two hooks never race for the Stop — session-continue runs first (Stop index 3 vs 7)
and boundary-handoff *voluntarily stands down* the moment it finds session-continue's sentinel file,
so the advisory is lost to a deliberate yield, not to a dropped second `decision:"block"`.

Read the two halves separately, because they have opposite consequences:

| | claim | verdict |
|---|---|---|
| **H1a** | *mechanism* = the stop is already blocked / only one reason is shown | **REFUTED.** MEASURED: both hooks CAN block one Stop and both messages reach the model (`hooks/session-continue.sh:315-320`, 33 same-Stop double-fires). The loss is a guard, not a collision. |
| **H1b** | *effect* = an armed session-continue chain structurally suppresses the boundary advisory | **CONFIRMED, at 216/216.** Every boundary-handoff evaluation that reached the guard with the sentinel present abstained. It has never once fired through a sentinel it found. |

⚠️ The literal falsifier as briefed is met (≥1), but **both arms of it are false positives for H1b**,
and saying so is the load-bearing part of this report — see § 3.3 and § 3.4.

---

## 1 · Record schemas  (MEASURED)

Both hooks write one line per invocation to `~/.claude/autonomy/idl.jsonl` via the shared writer
`hooks/lib/idl-log.sh`. Session-id field is **`sid`** in both. Timestamp field is **`ts`**
(`%Y-%m-%dT%H:%M:%SZ`, UTC). Disposition field is **`disposition`**; free-text reason is **`reason`**.

### boundary-handoff
Writer: `hooks/boundary-handoff.sh:223` (`idl_init "$IDL" "boundary-handoff" "sid" "SIZE_JSON"`).
`SIZE_JSON` is merged into **every** record once the size axis has been read, so `tx_mb`/`rss_mb`/
`tok_k` ride abstains too. `used_pct`, `threshold`, `head`, `axis`, `over_*` appear only once the
evaluation gets past the threshold block.

Abstain example (MEASURED, `grep -m1 '"hook":"boundary-handoff"' ~/.claude/autonomy/idl.jsonl`):
```json
{"ts":"2026-09-22T03:09:55Z","hook":"boundary-handoff","sid":"1bf6241b-59fb-4963-832e-de73a1efec3f",
 "disposition":"abstained","reason":"below-threshold:19<73;freewin=below-floor",
 "tx_mb":1,"rss_mb":505,"size_mb_t":25,"rss_mb_t":1500,"tok_k":194,"tok_k_t":700}
```
Fired example (MEASURED, the single co-occurrence of § 3.3):
```json
{"ts":"2026-09-13T04:52:10Z","hook":"boundary-handoff","sid":"22100d17-b2be-4fc2-adde-cb29aadd6f47",
 "disposition":"fired","reason":"past-boundary","tx_mb":8,"rss_mb":1504,"size_mb_t":25,
 "rss_mb_t":1500,"tok_k":692,"tok_k_t":700,"used_pct":69,"threshold":73,"head":"bb38cbf3",
 "burn_x100":56,"forecast_min":33,"early":false,"conv_age_s":"470","stale_ok":"",
 "over_size":false,"over_rss":true,"over_tok":false,"gate_green":"absent","dirty":"not-mine",
 "freewin":false,"freewin_rung":"","axis":"size"}
```
⚠️ **`used_pct` is ABSENT from `continue-hook-armed` abstains.** Its only carrier on a suppressed row
is `tok_k`. Every fill figure quoted below for a suppressed session is therefore `tok_k` (absolute
thousands of input tokens), never a percentage.

### session-continue
Writer: `hooks/session-continue.sh:85-96` — a local `log_idl`, not the shared lib:
```
'{ts:$ts,hook:"session-continue",sid:$sid,disposition:$disp,reason:$reason} + $extra'
```
Examples (MEASURED):
```json
{"ts":"2026-09-13T04:49:37Z","hook":"session-continue","sid":"22100d17-…","disposition":"armed",
 "reason":"mechanical-dirty","cwd":"/Users/chrisren/Development/personal/mario-followalong",
 "files":2,"source":"session-writes"}
{"ts":"2026-09-13T04:49:37Z","hook":"session-continue","sid":"22100d17-…","disposition":"fired",
 "reason":"continue","count":1,"max":8,"step":"Commit the 2 file(s) …","mail_folded":false}
{"ts":"2026-09-13T04:53:22Z","hook":"session-continue","sid":"22100d17-…","disposition":"cleared",
 "reason":"cli-clear","cwd":"/Users/chrisren/Development/personal/mario-followalong","disarmed":true}
```
**There is no `block` disposition.** A `decision:"block"` is recorded as `disposition:"fired"`, and
the `reason` says WHICH arm blocked — `continue` (the 🔧 chain, sentinel present) vs `wake-floor` /
`ship-floor` (the *no-sentinel* floors). This distinction is what disposes of falsifier arm B.

MEASURED dispositions: `armed` · `fired` · `cleared` · `abstained` · `refused`.

---

## 2 · Disposition census over the WHOLE IDL  (MEASURED)

Command: `python3 /tmp/ctx-pm-h1-scan.py` — streams `~/.claude/autonomy/idl.jsonl` plus the 8 rotated
`idl.jsonl.2*.gz` siblings line-by-line (`.chain` files excluded: they are a hash chain, `<n>\t<sha256>`,
not data).

```
FILES=9  TOTAL_LINES=926695  PARSE_FAIL=0  BH+SC_ROWS=7774
SPAN=2026-09-10T21:25:40Z .. 2026-09-22T06:25:22Z
```
🚨 **The retained corpus is 11.4 days, so "whole IDL" and "last 30 days" are the SAME population.**
The two histograms below are byte-identical and only one is printed. Nothing here can speak to
behaviour before 2026-09-10.

| boundary-handoff | n | | session-continue | n |
|---|---:|---|---|---:|
| `abstained:below-threshold` | 2544 | | `armed:cli-set` | 1885 |
| `abstained:no-telemetry` | 379 | | `fired:continue` | **983** |
| **`abstained:continue-hook-armed`** | **216** | | `fired:wake-floor` | 377 |
| `abstained:team-assignee` | 184 | | `abstained:ship-floor-not-mine` | 170 |
| `abstained:latched` | 154 | | `cleared:mechanical-assignee` | 166 |
| **`fired:past-boundary`** | **110** | | `abstained:ship-floor-assignee` | 166 |
| `abstained:stale-telemetry` | 10 | | `cleared:cli-clear` | 142 |
| `abstained:freewin-conversation-hold` | 9 | | `cleared:mechanical-teardown` | 42 |
| `abstained:freewin-inflight-wave` | 4 | | `abstained:ship-floor-teardown` | 42 |
| `abstained:dirty-tree` | 1 | | `cleared:mechanical-kill-switch` | 36 |
| `abstained:not-a-repo` | 1 | | `abstained:ship-floor-kill-switch` | 36 |
| `abstained:live-teammates` | 1 | | `abstained:wake-floor-teardown` | 33 |
| | | | `cleared:sid-mismatch` | 19 |
| | | | `fired:ship-floor` | 18 |
| | | | `abstained:ship-floor-latched` | 18 |
| | | | `armed:mechanical-dirty` | 9 |
| | | | (6 tail rows ≤6 each) | 15 |
| **TOTAL** | **3613** | | **TOTAL** | **4161** |

Fleet context (MEASURED): `waiting-recycle` 95,426 · `goal-inert-watch` 4,662 · `dispatch-assert`
4,661 · `anti-deference-nudge` 4,631 · `session-continue` 4,161 · `completion-assert` 3,722 ·
`boundary-handoff` 3,613 · `operator-readout` 2,941.

### 2.1 · The guard's true share  (MEASURED)
Of 3,613 boundary-handoff evaluations, only **496 ever reach the compose-guard** — the rest abstain
upstream on `below-threshold` / `no-telemetry` / `team-assignee` / `stale-telemetry`. Of those 496:

| outcome at/after the guard | n | share of 496 |
|---|---:|---:|
| **suppressed by the guard (`continue-hook-armed`)** | **216** | **43.5 %** |
| `latched` (already advised, re-arm not met) | 154 | 31.0 % |
| **fired** | 110 | 22.2 % |
| freewin-hold / dirty / not-a-repo / live-teammates | 16 | 3.2 % |

**Nearly half of every boundary-handoff evaluation that got far enough to matter was stood down by
this one guard.**

---

## 3 · THE JOIN  (MEASURED — `python3 /tmp/ctx-pm-h1-join.py`)

Method: per `sid`, armed intervals = `armed` → next `cleared` (unclosed intervals run to corpus end);
`block` timestamps = all `disposition:"fired"` rows. Then each boundary-handoff `fired` row is tested
for (a) membership in a same-sid armed interval and (b) a same-sid session-continue `fired` within 5 s.

```
SC armed intervals : 63 across 36 sids
SC fired rows      : 1378  (reason=continue: 983)
BH fired total     : 110   BH abstained continue-hook-armed: 216
sids with BH fired : 41 ; sids with SC armed interval: 36 ; overlap: 11
```

### 3.1 · Results
| | count | examples |
|---|---:|---|
| **(a)** BH `fired` INSIDE a same-sid armed interval | **1** | `2026-09-13T04:52:10Z sid=22100d17 past-boundary` |
| **(b)** BH `fired` within 5 s of a same-sid SC `fired` | **10** | listed in § 3.4 |
| **(c)** BH `fired` outside any armed interval, no nearby block (BASE RATE) | **99** | `2026-09-11T05:14:52Z 2d71c6d8` · `2026-09-11T06:11:38Z 65e22fd1` · `2026-09-11T23:54:11Z 41f80731` · `2026-09-12T00:09:46Z 41f80731` · `2026-09-12T01:47:00Z 41f80731` |

(a) and (b) overlap by 0; 1 + 10 + 99 = 110. ✓

### 3.2 · Base-rate contrast  (MEASURED)
BH rows falling inside a same-sid armed interval: **946** — of which
`abstained:below-threshold` 729, **`abstained:continue-hook-armed` 216**, `fired` **1**.
BH rows outside: 3,613 − 946 = 2,667, of which **109 fired**.

- fire rate **inside** an armed interval: 1/946 = **0.11 %**
- fire rate **outside**: 109/2,667 = **4.09 %**
- **≈ 39× suppression.**

And the sharper conditional: **216 of 216** rows where the guard actually *found* the sentinel
abstained. The guard has a **100 % suppression rate on its own arm** and has never once let a fire
through a sentinel it located.

### 3.3 · The ONE inside-interval fire is a KEY MISS, not a guard that allowed a fire
sid `22100d17-b2be-4fc2-adde-cb29aadd6f47`, 2026-09-13 (MEASURED, full trace):
```
04:49:36  boundary-handoff  abstained  dirty-tree:mine            tok_k=673 rss=1503   ← passed the guard: no sentinel yet
04:49:37  session-continue  armed      mechanical-dirty  cwd=/Users/chrisren/Development/personal/mario-followalong
04:49:37  session-continue  fired      continue          count=1
04:52:10  boundary-handoff  FIRED      past-boundary     used_pct=69 tok_k=692 over_rss=true axis=size
04:53:17  session-continue  cleared    cli-clear  cwd=/Users/chrisren/Development/personal              "disarmed":false
04:53:22  session-continue  cleared    cli-clear  cwd=/Users/chrisren/Development/personal/mario-followalong  "disarmed":true
04:53:39  boundary-handoff  FIRED      past-boundary     used_pct=70 tok_k=700 over_rss=true axis=size
```
MEASURED: the sentinel was keyed on `…/personal/mario-followalong`. A `clear` issued from
`…/personal` found **nothing there** (`"disarmed":false`) and the one from `…/mario-followalong`
found it (`"disarmed":true`) — so those two cwds map to two different sentinel paths for one session.
The key is `sha(CLAUDE_CONFIG_DIR|cwd)` (`hooks/lib/continue-sentinel.sh:25-26`).

INFERRED (cannot be proven — the telemetry file is ephemeral and gone): the guard computed the
`…/personal` path and found no file. **The two hooks read `cwd` from DIFFERENT SOURCES** —
`boundary-handoff.sh:434` reads `.cwd` from the *telemetry* file, `session-continue.sh:310` reads
`.cwd` from *Stop stdin*. They can diverge, and that is the only escape route observed in 11.4 days.

Not the cause, checked and excluded (MEASURED): the guard's fix (`bd3faae40`,
*"compose-guard reads session-continue's REAL sentinel path"*) landed **2026-07-18**, two months
before the corpus starts, so this is not a pre-fix artifact.

### 3.4 · All 10 "within 5 s of a block" cases are the *no-sentinel* floors — not the 🔧 chain
MEASURED (`/tmp/ctx-pm-near.py`), the nearby session-continue `fired` reason in every case:
```
2026-09-11T08:25:37Z 4e5f171f  BH used=71 axis=tokens   <- SC fired ship-floor  (+2s)
2026-09-11T08:42:06Z 4e5f171f  BH used=73 axis=fill     <- SC fired wake-floor  (+2s)
2026-09-13T23:21:01Z eab98191  BH used=34 axis=size     <- SC fired wake-floor  (+3s)
2026-09-13T23:48:57Z eab98191  BH used=45 axis=size     <- SC fired wake-floor  (+2s)
2026-09-13T23:59:04Z eab98191  BH used=45 axis=size     <- SC fired wake-floor  (+2s)
2026-09-14T13:57:23Z f0947ae8  BH used=70 axis=tokens   <- SC fired wake-floor  (+2s)
2026-09-16T07:04:30Z 6e22cc40  BH used=73 axis=fill     <- SC fired wake-floor  (+3s)
2026-09-17T00:19:13Z 5cea01e1  BH used=76 axis=fill     <- SC fired wake-floor  (+2s)
2026-09-20T09:52:32Z 8843bcf3  BH used=44 axis=freewin  <- SC fired wake-floor  (+2s)
2026-09-20T09:58:45Z 05683f40  BH used=47 axis=freewin  <- SC fired wake-floor  (+2s)
```
**0 of 10 carry `reason:"continue"`.** MEASURED at `hooks/session-continue.sh:1205` —
`if [ ! -f "$f" ]; then … mechanical_arm → ship_floor → wake_floor` — the floors run **only when no
sentinel exists**. So every one of these 10 Stops had session-continue *un*armed by construction.

They are still worth keeping, because they are the positive control for H1a: **two Stop hooks DID
both emit `decision:"block"` on one Stop, 2–3 s apart, and both were recorded.** The collision H1
posits as the suppression mechanism demonstrably does not suppress.

---

## 4 · sid `397428c4-8186-4720-8b3b-81406e46a16a`  (MEASURED)

1,980 IDL rows, span `2026-09-22T05:45:58Z` → `2026-09-22T06:29:50Z` (43 min 52 s).

**boundary-handoff produced 22 rows, not 28.** Its Stop-chain siblings produced 28
(`dispatch-assert`) and 27 (`operator-readout`, `goal-inert-watch`), so **6 Stops left no
boundary-handoff record at all** — see § 4.2. What it decided on the 22 it did record, and why:

```
05:56:24  abstained  below-threshold:34<73;freewin=below-floor   tok_k=344  tx=2MB  rss=910
06:02:24  abstained  continue-hook-armed                          tok_k=584  tx=4MB  rss=1281
06:02:58  abstained  continue-hook-armed                          tok_k=591  tx=4MB  rss=1281
06:03:57  abstained  continue-hook-armed                          tok_k=661  tx=5MB  rss=1282
06:04:32  abstained  continue-hook-armed                          tok_k=667  tx=5MB  rss=1282
06:04:55  abstained  continue-hook-armed                          tok_k=670  tx=5MB  rss=1282
06:06:10  abstained  continue-hook-armed                          tok_k=707  tx=6MB  rss=1283
06:06:32  abstained  continue-hook-armed                          tok_k=712  tx=6MB  rss=1283
06:08:30  abstained  continue-hook-armed                          tok_k=739  tx=6MB  rss=1284
06:08:47  abstained  continue-hook-armed                          tok_k=742  tx=6MB  rss=1287
06:09:15  abstained  continue-hook-armed                          tok_k=747  tx=6MB  rss=1287
06:10:13  abstained  continue-hook-armed                          tok_k=770  tx=6MB  rss=1287
06:11:15  abstained  continue-hook-armed                          tok_k=782  tx=6MB  rss=1288
06:11:40  abstained  continue-hook-armed                          tok_k=785  tx=6MB  rss=1288
06:11:54  abstained  continue-hook-armed                          tok_k=787  tx=6MB  rss=1288
06:12:10  abstained  continue-hook-armed                          tok_k=789  tx=7MB  rss=1349
06:12:29  abstained  continue-hook-armed                          tok_k=792  tx=7MB  rss=1349
06:12:38  abstained  continue-hook-armed                          tok_k=793  tx=7MB  rss=1349
06:12:50  abstained  continue-hook-armed                          tok_k=794  tx=7MB  rss=1349
06:14:23  abstained  continue-hook-armed                          tok_k=896  tx=8MB  rss=1353
06:14:47  abstained  continue-hook-armed                          tok_k=921  tx=8MB  rss=1353
06:15:29  abstained  continue-hook-armed                          tok_k=968  tx=9MB  rss=1353   ← LAST BH row of the session
```

**Plainly: it decided ONCE that the session was small (34 %), and then stood down 21 consecutive
times — every remaining Stop it reached — because session-continue's sentinel was on disk. It never
once evaluated the boundary. The last thing it did was stand down at 968 K tokens.**

Companion hooks over the same window (MEASURED):
- `session-continue` — `armed:cli-set` **37**, `fired:continue` **27**, `cleared:cli-clear` **1**.
  The chain was re-armed by the model roughly every 30–60 s, so the sentinel was essentially never
  absent after 06:02.
- `waiting-recycle` — **1,682** rows, **100 % `abstained:not-armed`**. This is the hook the
  boundary-handoff header nominates as the carrier for exactly this case, and it was opted out for
  the whole session. See § 5.2.
- `operator-readout` — 27 × `abstained:continue-armed` (it yields to the same sentinel).
- `completion-assert` — 15 × `abstained:no-close-tell`. `anti-deference-nudge` — 26 × `abstained:no-tell`.
- `dispatch-assert` — 28 × `abstained:no-naming-tell`. `goal-inert-watch` — 27 × `abstained:damped:never`,
  **1 × `fired:goal-inert:named`**.
- `capacity-admit` 29 × admitted · `spawn-budget` 29 × admitted · `desk-brief-inject` 1 × `other-holder`.

Interleave at the danger point (MEASURED, verbatim ordering):
```
06:14:22  anti-deference-nudge  abstained  no-tell
06:14:23  completion-assert     abstained  no-close-tell
06:14:23  operator-readout      abstained  continue-armed
06:14:23  session-continue      fired      continue   count=1  step="CONTEXT ~82%. RECOVERY.md in the run dir…"
06:14:23  boundary-handoff      abstained  continue-hook-armed   tok_k=896
```
The session's own `step` text says **CONTEXT ~82 %** — the model knew. The one hook whose entire job
is to convert that into "/handoff now" was, on that same Stop, standing aside for the hook carrying
the model's note.

### 4.1 · Six Stops produced NO boundary-handoff row — B-3 is violated 6/28 here  (MEASURED)
Between the first row (05:56:24) and the second (06:02:24) there are **six Stops** on which
`dispatch-assert` and `operator-readout` both logged and boundary-handoff logged nothing:
`05:58:45` · `05:59:30` · `05:59:43` · `06:00:48` · `06:01:24` · `06:01:51`.

This contradicts the hook's own B-3 invariant (`boundary-handoff.sh:17-19`): *"Every invocation emits
{fired|abstained:<reason>} to the IDL. Without it, 'didn't fire' and 'never evaluated' are the same
observation."* INFERRED: those Stops took one of the pre-`idl_init` **silent** exits — a failed
resolve of `lib/idl-log.sh`, `lib/context-econ.sh` or the telemetry path (`boundary-handoff.sh:200-222`),
each of which exits 0 before the writer exists. Cannot be confirmed from the corpus by construction:
the evidence of a silent exit is the absence of the row.

Consequence for this postmortem: **21 % (6/28) of this session's Stops are unaccounted for on this
rail**, so the § 4 trace is a lower bound on the suppression, not a complete census. It is also the
one place where the H1 framing could still be partly right — a co-occurring block on one of those six
Stops would be invisible here. Nothing in the IDL can settle it.

### 4.2 · This session is not unique — and the pattern is a death signature
MEASURED: all 216 suppressions belong to just **4 sids**, and **3 of the 4 end on a suppression at
the top of the window**:

| sid | suppressions | max `tok_k` | last BH row |
|---|---:|---:|---|
| `65e22fd1` | **185** | 896 | `06:16:55  abstained continue-hook-armed  tok_k=896` |
| `397428c4` | 21 | **968** | `06:15:29  abstained continue-hook-armed  tok_k=968` |
| `540263da` | 8 | 909 | `17:50:55  abstained continue-hook-armed  tok_k=909` |
| `7f533f05` | 2 | 770 | — |

**201 of 216 suppressions occurred at ≥700 K tokens; 56 at ≥850 K.** For contrast, the highest
`tok_k` boundary-handoff ever *fired* at is 915 K, and only 8 of its 110 fires were ≥850 K.

---

## 5 · Mechanism

### 5.1 · What actually happens when both hooks block on one Stop
**MEASURED, and it is not a deadlock.** `hooks/session-continue.sh:315-320`:
> *"This hook and completion-assert can both emit {decision:"block"} on ONE Stop, and the harness does
> not short-circuit — hooks/hook-chain.sh:78 states it as contract ("every member always runs"), so
> the model receives TWO separate messages about the same facts, 0.77 s apart. Measured over the
> retained IDL window against 1,335 completion-assert evaluations: 33 same-Stop double-fires (2.5 %),
> completion-assert on its `false-done` arm in 33/33."*

`hooks/hook-chain.sh:77-78`:
> *"EVERY MEMBER ALWAYS RUNS. The harness runs every hook in a matcher group even when one blocks, so
> this does too — short-circuiting would drop the side effects of later members."*

Corroborated by § 3.4: 10 measured Stops where boundary-handoff `fired` and session-continue `fired`
2–3 s apart, both recorded.

**`docs/research/final-response-shaping-2026-08-08.md`: UNKNOWN.** That doc measures the six
end-of-turn channels, the `additionalContext`-vs-`systemMessage` split, the `continue:false`
precedence trap, and the headless `systemMessage` drop — but it contains **no measurement of two Stop
hooks both returning `decision:"block"`** (grepped for `two|both|second.*block|concatenat|drop|
short-circuit|last.*wins`: no hit on that question). Do not attribute the double-block finding to it;
the citation is `session-continue.sh:315-320` + `hook-chain.sh:78`.

So H1's proposed mechanism is refuted from both ends: the harness does not short-circuit, and the
advisory is lost *before* any JSON is emitted.

### 5.2 · The real mechanism — an explicit yield that was designed, and its known blind spot
`hooks/boundary-handoff.sh:437-450` (MEASURED, verbatim):
```
# ── Compose-guard (G-P6-6b / a19 I-1): if session-continue's 🔧 loop is armed for THIS cwd, it owns
#    the next turn — yield, don't double-inject. Check its REAL sentinel path (test override
#    CC_CONTINUE_SENTINEL wins; else the shared SSOT hooks/lib/continue-sentinel.sh). The old guard
#    hardcoded ~/.claude/hooks/.session-continue-armed — a path session-continue never writes → the
#    guard was a dead no-op that let both hooks block one Stop. Placed after cwd resolution so it can
#    compute the cwd-keyed path; still BEFORE the latch/fire, so an armed session is never advised. ──
…
{ [ -n "$sc_sentinel" ] && [ -f "$sc_sentinel" ]; } && abstain "continue-hook-armed"
```
Provenance: `bd3faae40` (2026-07-18) *"fix(boundary-handoff): compose-guard reads session-continue's
REAL sentinel path"*. The guard was **repaired into effectiveness** two months before this corpus —
i.e. what looks like a deadlock is a fix working exactly as specified, on a session shape nobody
priced: one whose sentinel is re-armed on *every* turn.

The two hooks sit in the **same Stop array**, session-continue at index 3 and boundary-handoff at
index 7 (MEASURED, `jq -r '.hooks.Stop[]?.hooks[]?.command' ~/.claude/settings.json`), so
session-continue always writes the sentinel before boundary-handoff reads it.

**The blind spot is named in the tree, in two places.** `hooks/waiting-recycle.sh:11-18`, verbatim:
```
# WHY A NEW HOOK, NOT boundary-handoff.sh (which already advises /handoff at a threshold):
#   boundary-handoff.sh fires on the **Stop** event. A watch-driven desk polling in a long turn (or
#   held open by session-continue's loose-ends loop) NEVER cleanly Stops, so that advisory never
#   lands and the desk OVER-ACCUMULATES (boundary-handoff's own B-1 header names this blind spot; the
#   out-of-session lead-supervisor.sh covers 'past-threshold ∧ not-Stopping' but can only PAGE — bash
#   cannot drive a live pane). This hook is the IN-SESSION carrier for exactly that case: it fires on
#   the desk's MONITORING CADENCE — PostToolUse:Bash, the heartbeat of a polling desk — so it reaches
#   the desk between polls, not only at a Stop it never hits.
```
and `hooks/boundary-handoff.sh:7-11` (B-1): *"It fires on the Stop event, so a session HUNG MID-TURN
never reaches Stop and this hook NEVER RUNS for exactly the sessions most likely to be past their
boundary… ⇒ This hook is a REFINEMENT, never the carrier (invariant 4)."*

⚠️ **The designated compensating control was inert for the postmortem session.** `waiting-recycle.sh`
is registered as **PostToolUse:Bash**, not Stop (MEASURED:
`jq -r '.hooks.PostToolUse[]? | "\(.matcher):\(.hooks[]?.command)"' ~/.claude/settings.json`
→ `Bash: ~/.claude/hooks/waiting-recycle.sh`), and it is opt-in via a cwd/role-keyed `arm` sentinel
(`waiting-recycle.sh:40-45`, `421-465`). For sid `397428c4` it evaluated **1,682 times and abstained
`not-armed` every single time**. So on 2026-09-22 the boundary rail had **no live carrier at all**:
the Stop-event advisory yielded to the sentinel, and the cadence-event carrier was never armed.

---

## 6 · Residuals and honest limits

1. **The corpus is 11.4 days** (2026-09-10 → 2026-09-22). Every rate here is conditioned on that
   window. "All time" in § 2 means "all *retained*".
2. **The join is SID-keyed; the guard is CWD-keyed.** A session with sentinels in two cwds (§ 3.3) is
   modelled as one interval. This makes arm (a) *generous* — it can only over-count co-occurrences —
   so it strengthens rather than weakens the H1b conclusion. MEASURED: all 216 `continue-hook-armed`
   abstains fall inside a same-sid armed interval, so the approximation costs nothing on that side.
3. **boundary-handoff IDL rows carry no `cwd`**, so a true cwd-keyed join cannot be built from the
   corpus. The § 3.3 diagnosis of the single escape is therefore INFERRED, not proven.
4. **`used_pct` is missing from suppressed rows**; `tok_k` is the only fill proxy available for them.
   On a 1 M window `tok_k` ≈ `used_pct × 10`, but the window is not recorded in these rows, so treat
   `tok_k=968` as "968 K tokens", not as "96.8 %".
5. **Not run, per the brief:** `cc-ctx-audit` and any fleet audit; no transcript under
   `~/.claude*/projects` was opened. Nothing outside `/tmp` was written; no repo file was modified.
6. Scripts retained for re-derivation: `/tmp/ctx-pm-h1-scan.py` · `/tmp/ctx-pm-h1-join.py` ·
   `/tmp/ctx-pm-h1-sid.py` · `/tmp/ctx-pm-bh397.py` · `/tmp/ctx-pm-sev.py` · `/tmp/ctx-pm-near.py` ·
   `/tmp/ctx-pm-raw.py`.
