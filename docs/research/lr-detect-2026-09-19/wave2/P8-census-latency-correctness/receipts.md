# P8 — census latency & correctness: the single-process prototype vs `lr-fleet --locate`

Measured 2026-09-19T20:53Z–21:05Z, read-only, on the live fleet.
**Verdict: PARTIAL.** The prototype's *speed* premise HOLDS (~650× faster, and the only one of the
two that is a snapshot). Its *correctness* premise is **REFUTED**: it silently dropped the single
most actionable row in the fleet. `lr-fleet --locate` is not the correctness baseline either — it
contradicted its own `--duplicates` in the same minute and mis-attributed an account.

---

## R1 — Latency: 0.067 s vs 43.6 s, and only one of them is a snapshot

```
$ ( time bash scripts/limit-recover/lr-fleet.sh --locate --json > locate-run1.json ) 
  started 2026-09-19T20:53:58Z  finished 2026-09-19T20:54:42Z
  18.66s user 21.87s system 93% cpu  43.558 total      rows=18

$ ( time python3 .../cc-limited-proto.py )
  run1 (first this session) real 0.20   ["elapsed 0.163s" self-timed]
  run2 (warm, immediate)          0.090 ["elapsed 0.045s"]
  run3 (after ~6 min idle)        0.067
```

**650×** on the warm pair, **218×** on the cold pair. (`purge` was not permitted; "cold" here is
first-run-of-session, so the true cold gap is a lower bound on the proto's advantage — the proto
touches ~35 files, `--locate` stats and tails 2,591.)

The number that matters more than the ratio: **a 43.6 s window is longer than the fleet's own
state-change interval.** During this run's window a transplant completed:

```
$ cat ~/.reso/limit-recover/locks/98f02458-….lock
{"sid":"98f02458-…","from":"…/.claude-tertiary","to":"…/.claude-secondary",
 "ts":"2026-09-19T20:53:26Z",…}
```

32 s before `--locate` started, and its `.handed-off` rename landed *inside* the scan. The two tools
therefore disagree on 98f02458 for a reason that is not a bug in either: `--locate` rows are not a
consistent snapshot of one instant. The proto's 0.045 s window is effectively atomic.

Marker inter-arrival for comparison — the next3 burst below has deaths **1 s** apart.

---

## R2 — The event stream already answers the operator's ask, with no screenshot and no pane probe

`~/.claude/autonomy/stop-failure/rate_limit__<acct>.jsonl`, 26 lines / 14 distinct sids:

```
next4 burst  16:58:33Z → 17:27:19Z  (29 min)  5 sids  all "resets 2:40pm"
             e442434c d02d8feb 09e64dcb cb227486 28f07827
next3 burst  19:52:33Z → 20:29:28Z  (37 min)  8 sids  all "resets 4:30pm"
             98f02458 09e64dcb 11569d45 65186f1f 8843bcf3 4bc1159f 26cd14be 07e30aeb
```

The shared reset string is the group key. `09e64dcb` appears in **both** bursts — the transplant is
visible in the event stream itself. This is the operator's "usually multiple sessions at once from
the same account", rendered from 6 KB of append-only JSONL.

**Markers are per-RETRY, not per-death.** 26 lines / 14 sids = 1.86×; `11569d45` fired three markers
in 6 s (19:53:44 / :45 / :50). Any consumer that counts LINES over-counts sessions by ~86%. The
proto dedupes by sid — correct, and load-bearing.

---

## R3 — 🚨 The proto DROPPED a live, limit-blocked, pane-held session (07e30aeb)

Disk truth, three copies of one sid:

```
~/.claude-secondary/…/07e30aeb….jsonl            1157520 B  25 asst  last_is_apierr=True  20:29:28Z
~/.claude-tertiary/…/07e30aeb….jsonl                2886 B   0 asst  last_is_apierr=None  —
~/.claude-tertiary/…/07e30aeb….jsonl.handed-off  1157520 B  25 asst  last_is_apierr=True  20:29:28Z
```

The 2,886-byte file holds **three records, none of them assistant**:

```
2026-09-19T20:52:44.742Z queue-operation
2026-09-19T20:52:44.748Z queue-operation
2026-09-19T20:52:45.142Z system
```

The proto's marker carries `transcript_path = …/.claude-tertiary/…07e30aeb….jsonl`. That path
**exists** (a new file was reborn at it 20 min after the transplant), so the MOVED branch is not
taken; the tail read finds zero assistant records; `last` stays `None`;
`c['blocked']=bool(None)=False` → `disp='RE-ENGAGED'` → filtered out of the render by
`cc-limited-proto.py:68`, surfacing only inside `"1 dropped as re-engaged/gone"`.

**The defect is the conflation of "no api-error in the tail" with "took a real turn since".**
Absence of evidence read as evidence of recovery, and the drop is silent. The two `queue-operation`
rows are queued input against a blocked pane — a positive signal it is *still stuck*.

`--locate` found it, on a live pane:
`07e30aeb next2 pane=147 pid=84167 RECOVERABLE limit age=1485 wt-cc-143039-68221`

---

## R4 — 🚨 …and `--locate`'s ACCOUNT on that same row is wrong

```
$ ps -E -o command -p 84167 | tr ' ' '\n' | grep CLAUDE_CONFIG_DIR
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary
$ cat ~/.claude/cc-registry/147.json
{"paneUUID":"147","account":"claude-tertiary","pid":84167,"session_id":"07e30aeb-…"}
$ marker line:  2026-09-19T20:29:28Z  account=next3  transcript_path=…/.claude-tertiary/…
$ --locate row: account=next2  cfg=/Users/chrisren/.claude-secondary  pid=84167
```

Three independent stores say **next3**; `--locate` says **next2**. Mechanism, both halves measured:

- `lr-fleet.sh:210` — `acct="$(lf_acct_of_cfg "$cfg")"`: the account is inferred from **which
  directory the file was found in**. A transplant leaves a full-size copy under *both* config dirs,
  so the sid is enumerated twice and the losing copy names the wrong account.
- `lr-lib.sh:217` — `[ "$(jq -r '.session_id …')" = "$sid" ] || continue`: the registry join has **no
  account/cfg predicate**, and `lr-fleet.sh:215` (`IFS=$'\t' read -r pane pid _ cwd`) discards the
  registry row's own `.account` into `_`.

Result: one row welding **next2's transcript to next3's pane**. For a tool whose entire purpose is
"group the blocked sessions by account", the account column is the one field that must not be
inferred. **The marker's account is authoritative** — `stop-failure-marker.sh:82-89` derives it from
the dying process's own `CLAUDE_CONFIG_DIR` against `accounts.json`, not from a file's location.

---

## R5 — 🚨 `--locate` calls a single-process session DUPLICATE, and DUPLICATE *parks* it

```
$ lr-fleet.sh --locate  →  09e64dcb  next3  pane=111  pid=37018  DUPLICATE
$ lr-fleet.sh --duplicates
(no session is held by more than one live process)
```

Same disk, same minute, opposite answers. Truth: **one** live registry row (pane 111, pid 37018) and
`lr_resume_procs` returns exactly **one** leaf pid — `37018`, the same process:

```
$ ps -axo pid=,ppid=,command= | awk 'index($0,"--resume 09e64dcb…")'
36913 36905 bash …/cc-close-attrib …          ← wrapper (correctly dropped by the leaf filter)
37018 36913 …/claude … --resume 09e64dcb…     ← the session
$ lr_resume_procs 09e64dcb…  ⇒  37018
```

The bug is the boolean at **`lr-fleet.sh:217`**:

```sh
if [ "$n" -gt 1 ] || lr_resume_procs "$sid" >/dev/null 2>&1; then disp=DUPLICATE; else disp=RECOVERABLE; fi
```

`lr_resume_procs` returns rc 0 whenever *any* resume process exists — i.e. for **every session that
was started by `--resume`**, which is every transplanted or recovered session. It never had to be
two. Blast radius is not cosmetic: `lr-fleet.sh:399` parks DUPLICATE rows
(`"parked" "DUPLICATE — more than one live process; resolve with --duplicates first"; worst=1`) and
`--duplicates` then reports nothing to resolve — a recoverable session is refused, forever, by a
condition that cannot clear. Fix: cardinality of `{registry live pids} ∪ {resume leaf pids}` > 1.

The proto gets this row wrong too, differently: `cc-limited-proto.py:59` marks TRANSPLANTED on bare
`os.path.exists(locks/<sid>.lock)`. The lock says `"to":"…/.claude-tertiary"` — which is where the
session now *is*. `lr_transplanted_to` (`lr-lib.sh:262-271`) has the correct test and the proto
lacks it: **`lock.to != this cfg` AND the successor transcript exists at `to`.**

---

## R6 — The full successor table: what BOTH tools are missing (the disposition algebra)

All 14 marker sids × every copy across all config dirs (`allcopies.py`, in this dir):

| sid | live copy | last_is_apierr | truth | proto | --locate |
|---|---|---|---|---|---|
| 07e30aeb | secondary (+2886 B stub in tertiary) | True 20:29 | **BLOCKED, pane 147** | *dropped* | RECOVERABLE, wrong acct |
| 09e64dcb | tertiary | True 19:53 | **BLOCKED, pane 111** | TRANSPLANTED ✗ | DUPLICATE ✗ (parks it) |
| 4bc1159f / 8843bcf3 | tertiary | True | BLOCKED, pane | RECOVERABLE ✓ | RECOVERABLE ✓ |
| 26cd14be | secondary (tertiary handed-off 7 s ago) | True 20:04 | moved, **still blocked** | RECOVERABLE (stale) | RECOVERABLE (stale) |
| 11569d45 | secondary, mtime 3 s | **False** 20:58 | **recovered on next2** | RECOVERABLE ✗ | RECOVERABLE ✗ |
| 98f02458 | secondary | True 19:57 | moved, **blocked, NO pane** | MOVED ✗ (hidden) | NO-PANE ✓ |
| 65186f1f 28f07827 cb227486 d02d8feb e442434c | secondary/tertiary | **False** | recovered | MOVED (noise) | absent ✓ |
| fff83638 / 0e2567ee | quaternary | True 19:28 | next4, reset passed, no pane | RESET-PASSED ✓ | CWD-GONE / NO-PANE |

**The rule neither tool encodes: a transplant COPIES the death record into the successor.** The
successor's last assistant record is *still* an api-error until it takes a real turn (26cd14be,
98f02458 above). So `last_is_apierr` alone can never separate *still blocked* from *moved and
awaiting re-engage* — you need the lock (`from`/`to`/`ts`) **and** the live copy's mtime **and** a
live pid, jointly. `last_is_apierr=False` *is* a sound recovery signal (five sessions), but only when
there is at least one assistant record to read.

Scoreboard on the 13 rows each renders:
- **proto**: 5/13 = **38 % pure noise** (MOVED rows already recovered), 1 hidden actionable
  (98f02458), 1 total drop (07e30aeb), 1 mislabel (09e64dcb).
- **`--locate`**: 18 rows, **9 of them older than 24 h** (125 h … **505 h**) — 50 % of the census is
  archaeology. It has **no reset clock at all** (it never reads `quotaLimits`), so a 21-day-old block
  and a 24-minute-old one differ only by an `err_age` column that measures the *death*, not the time
  to *reset*. The proto reads `quotaLimits.resetsAt` and renders `next3: 7 blocked cap=five_hour
  reset=in 0h36m` — the actionable framing, and the whole reason its output groups per account.

**Neither tool has a teammate path in common**: `--locate` has two (`lr-fleet.sh:189` `agent-*|wf_*`
skip; `:211` `agentName` head-grep → TEAMMATE). `grep -c agent cc-limited-proto.py` ⇒ **0** — the
proto would render a teammate as an ordinary recoverable row. No teammate marker exists today, so
this is by inspection, not by instance.

---

## R7 — REQUIRED vs OPTIONAL sources, and the disposition algebra that follows

| source | role | required? |
|---|---|---|
| `stop-failure/rate_limit__*.jsonl` | the **event** (sid, account, cwd, ts, cause) — sub-second, authoritative account | **REQUIRED** — the only store that names *when* and *whose* |
| `~/.reso/limit-recover/locks/<sid>.lock` | `from`/`to`/`ts` — the only successor pointer | **REQUIRED** — without it a transplanted row reads as blocked (R6) |
| `~/.claude/cc-registry/<pane>.json` + `kill -0` | pane & pid; `.account` cross-check | **REQUIRED** for RECOVERABLE vs NO-PANE, and for R4's dissent |
| transcript **tail** of the resolved LIVE copy | `last_is_apierr`, `quotaLimits.resetsAt/rateLimitType` | **REQUIRED** — but the copy must be resolved (glob all cfgs, prefer newest mtime with ≥1 assistant record), never taken from the marker's snapshot path |
| `~/.reso/limit-recover/parked/<sid>.json` | poller's reset estimate | **OPTIONAL** — today it is a strict subset of markers ∪ nothing; ≤600 s late by `StartInterval` |
| `cc-beats/<sid>.json` | `kind` | **OPTIONAL and currently useless** — all four blocked next3 rows read `beat=prompt` (Stop never fires on a limit turn), confirming the `cc_sp_active` phantom |
| full 2,591-transcript scan | — | **NOT required** for a *currently-limited* view; it is the entire 43.6 s and it is what drags 505-h rows in |

**Algebra** (per sid, after resolving the live copy):
```
copies := glob(~/.claude*/projects/*/<sid>.jsonl)          # live only, not .handed-off
live   := the copy with ≥1 assistant record and max mtime
pids   := {registry rows with session_id==sid, kill -0 ok} ∪ {resume leaf pids}
succ   := lock.to if lock exists and lock.to != cfg(live) and <sid>.jsonl exists under lock.to

if succ                         → MOVED→<acct(succ)>   (then recurse on succ; never terminal)
elif live has 0 assistant recs  → UNKNOWN-STUB         (R3 — NEVER "re-engaged")
elif not last_is_apierr         → RE-ENGAGED           (drop)
elif |pids| > 1                 → DUPLICATE
elif |pids| == 1                → RECOVERABLE (pane, pid)   [+ RESET-PASSED if resetsAt<=now]
else                            → NO-PANE              [+ CWD-GONE if not isdir(cwd)]
account := marker.account, else registry.account, else cfg(live)   # NEVER cfg-of-scan
```
The two additions that fix today's misses are `UNKNOWN-STUB` (R3) and making `MOVED` **non-terminal**
(R6: 98f02458's successor is blocked with no pane, and the proto's MOVED hid it).

---

## R8 — The marker GC: what a "currently limited" view loses at the TTL boundary

`hooks/stop-failure-marker.sh:41` `TTL_MIN=1440`, `:42` `CAP=500`, `:93`
`CAUSE_KEY="$(_sf_slug "$ERR")__$(_sf_slug "$ACCOUNT")"   # ANCHOR: cause-keyed, never session-keyed`,
`:100`:

```sh
find "$MARKER_DIR" -type f -name '*.jsonl' -mmin "+$TTL_MIN" -delete
```

GC is **per-FILE on the file's mtime**, not per-LINE on each event's `ts`. Two consequences, opposite
in sign, both wrong:

1. **Nothing ages out while the account keeps dying.** The file's mtime is the *most recent* death on
   that account, so one death per 24 h keeps **every** line alive indefinitely — the same unbounded
   staleness that gives `--locate` its 505-h rows, waiting to happen in the marker store too.
2. **Everything is lost at once when it does.** A quiet account loses its whole file — every session
   on it, atomically. `seven_day` caps reset at **168 h ≫ 24 h**, so a weekly-capped fleet is
   *guaranteed* to lose its entire marker record ~6 days before the reset it is waiting for. The
   context reports 22 `seven_day` records; every one of them outlives its own evidence.

The 500-line cap is **not** the binding constraint (26 lines / 14 sids today), though the per-retry
duplication of R2 burns it ~1.9× faster than sessions do.

**Fix — per-session state file, and it is the right one for three independent reasons.** Write
`~/.claude/autonomy/limited/<sid>.json`, **replaced not appended**: (a) dedupe becomes O(1) instead
of 1.86 lines/sid; (b) GC keys on the *session's* own liveness — retire when its transcript is gone,
it re-engages, or `resetsAt` passes by a margin — which is a fact about the thing being described,
not about its account's aggregate recency; (c) it survives a weekly cap by construction. Merely
lengthening the TTL fixes only (2) and makes (1) strictly worse. Keep the cause-keyed append-only
file as the **event log** (R2's burst clustering is exactly what it is good at) and add the
per-session file as the **state**; they are different shapes and the current store is being asked to
be both. This is the same second arm the three sibling designs converged on
(`lr/design/D1-zero-touch.md`, `D2-one-command.md`, `D3-identity-observability.md`).

---

## Files
`proto-run1.txt` `proto-run2.txt` `proto-run1.time` `locate-run1.json` `locate-run1.time`
`proto-debug.py` (stderr dump of every candidate incl. dropped) · `allcopies.py` (R6 table).
