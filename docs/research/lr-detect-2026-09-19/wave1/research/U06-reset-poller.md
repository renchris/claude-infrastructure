# U06 — lr-reset-poller: the zero-touch arm that already saw today's five sessions and chose to wait

**Headline.** The poller detected all five next4 limits within ~2 minutes of the first one — **128 seconds BEFORE the operator's first `/limit-recover`** — and then did nothing for 2h41m, by design. It is a *wait-for-reset, resume-on-the-SAME-account* daemon. It has **no cross-account transplant arm of its own**; the only transplant path it can execute is a request another process enqueues for it. Today nobody enqueued one. The whole 98.7-minute manual recovery ran on top of a daemon that had already done the identification work for free.

---

## 1. THE ANSWER: it waits. Cited.

### The gate

```
scripts/limit-recover/lr-reset-poller.sh:896
  (( now < reset_epoch )) && continue                        # reset not reached yet
```

`§2 RESUME` (`:870`) iterates `$PARKED/*.json`, parses `reset_at_utc` (`:894-895`), and **`continue`s** when the reset is in the future. Every action arm lives *below* that line:

| arm | line | what it does |
|---|---|---|
| TRANSPLANTED-retire | `:898-905` | retire the record if `/limit-recover` already moved this sid |
| fire latch | `:911` | suppress a repeatedly-failing sid |
| **NUDGE in place** | `:928-943` | original pane alive ⇒ type `/limit-recover` into it, never spawn |
| winner contest / LISTED | `:947-961` | consolidate duplicates per worktree |
| **SPAWN resume** | `:966-1013` | `lr-fire-resume.sh <acct> <cwd> <sid> --prompt /limit-recover` |
| notify-once | `:1014-1031` | `osascript display notification` |

The same filter is applied a second time when the winner set is built, in `§1b CONSOLIDATE`:

```
scripts/limit-recover/lr-reset-poller.sh:833-834
    try: e=calendar.timegm(datetime.fromisoformat(str(d.get('reset_at_utc','')).replace('Z','+00:00')).utctimetuple())
    except Exception: continue
    if now < e: continue
```

So a pre-reset session is not merely un-fired, it is **not even a candidate**.

### It is also single-account by construction

The account is read off the parked record and never reconsidered:

```
:995   printf 'exec %q %q %q %q' "$LR/lr-fire-resume.sh" "$acct" "$cwd" "$sid"
:931   if ! account_has_headroom "$acct"; then log "WAIT  $sid — $acct still capped, retry next tick"; continue; fi
:964   (same, for the spawn arm)
```

`account_has_headroom()` (`:382-396`) takes **one** account name and answers yes/no; it is not a ranker. `grep -c 'claude-accounts' lr-reset-poller.sh => 2` — both hits are inside that one predicate. There is **no call to `claude-accounts --rank`, no target selection, no other-account arm anywhere in the 1033 lines.** The poller's model of recovery is: *this session belongs to this account; wait until this account is uncapped.*

> Note: `account_has_headroom` fails **open** — `j=$("$HOME/bin/claude-accounts" --json 2>/dev/null) || return 0   # unreadable ⇒ don't block` (`:384`).

### The receipt that this is not theoretical — 24h47m of measured waiting

```
2026-09-16T23:11:17Z PARKED cc1f8d0a-… (next2, session) resets 2026-09-17T00:30:00Z  cwd=…/claude-infrastructure
2026-09-17T07:00:44Z WAIT  cc1f8d0a-… — next2 still capped, retry next tick
   … 100 identical WAIT lines, one per tick …
2026-09-17T23:58:49Z RESUMED cc1f8d0a-… on next2 (autofire, gui) — pane opened
```
(`grep -c 'WAIT  cc1f8d0a' ~/.reso/limit-recover/poller.log => 100`)

Park → resume = **24h47m**. Its own reset time passed at 00:30; it then sat **23h28m past reset** because next2 stayed capped — while next, next3 and next4 existed the whole time. One session, one account, 100 log lines, zero moves.

---

## 2. Did it run today? Yes — and it beat the operator to the detection.

`~/.reso/limit-recover/poller.log`, all five of today's lines (the file has exactly 5 rows for 2026-09-19):

```
2026-09-19T16:59:23Z PARKED e442434c-… (next4, session) resets 2026-09-19T19:40:00Z  cwd=/Users/chrisren/Development/claude-infrastructure
2026-09-19T16:59:25Z PARKED d02d8feb-… (next4, session) resets 2026-09-19T19:40:00Z  cwd=/Users/chrisren/Development/.worktrees/wt-cc-095358-75429
2026-09-19T17:09:45Z PARKED 28f07827-… (next4, session) resets 2026-09-19T19:40:00Z  cwd=/Users/chrisren/Development/.worktrees/wt-cc-100046-36511
2026-09-19T17:09:47Z PARKED cb227486-… (next4, session) resets 2026-09-19T19:40:00Z  cwd=/Users/chrisren/Development/claude-infrastructure
2026-09-19T17:09:51Z PARKED 09e64dcb-… (next4, session) resets 2026-09-19T19:40:00Z  cwd=/Users/chrisren/Development/claude-infrastructure
```

Timeline in America/Chicago (UTC−5):

| clock | event |
|---|---|
| **11:59:23** | poller parks `e442434c` — **first detection, autonomous** |
| 11:59:25 | poller parks `d02d8feb` |
| **12:01:33** | operator's first `/limit-recover` — **128 s AFTER the poller already knew** |
| 12:09:45–51 | poller parks the remaining three in its next tick |
| 12:09:51 → now (13:43) | **silence. ≥9 further ticks, zero log lines** — `now < reset_epoch` |
| 14:40:00 | the time the poller intended to act (`reset_at_utc 19:40:00Z`) |

Detection latency: **≤ one 600 s tick**, and in practice 2 s per session once the tick starts (16:59:23 → 16:59:25). Identification — the thing that cost the operator a screenshot, an eyeball and a keyword search per session — was **already done, on disk, for free, before the first manual command**. The parked record even carries the two facts the screenshot could not supply:

```
$ cat ~/.reso/limit-recover/parked/d02d8feb-1f9d-42bb-8487-80b726c88950.json
{"sid":"d02d8feb-1f9d-42bb-8487-80b726c88950","acct":"next4","cfg":"/Users/chrisren/.claude-quaternary",
 "cwd":"/Users/chrisren/Development/.worktrees/wt-cc-095358-75429","kind":"session",
 "reset_at_utc":"2026-09-19T19:40:00Z","parked_at":"2026-09-19T16:59:25Z"}
```

**The sid is right there.** The statusline fields the operator had to squint at (`(4) 52% · wt-cc-095358-75429 (06ce6fee5) · xhigh`) map onto `acct` + `cwd` in this file. `d02d8feb` IS the `wt-cc-095358-75429` session. A `kitty @ get-text` keyword or a screenshot never needed to be the identification channel — this directory is.

### Daemon health

```
$ launchctl print gui/501/com.reso.lr-reset-poller
  state = not running          (between ticks; normal)
  runs = 403        last exit code = 0
  run interval = 600 seconds
  environment = { LR_POLLER_AUTOFIRE => 1 }
  program = /bin/bash /Users/chrisren/.claude/scripts/limit-recover/lr-reset-poller.sh
```
`~/.claude/scripts/limit-recover/lr-reset-poller.sh` is a symlink → the checkout, so live == repo source. Installed plist ≡ repo plist semantically (byte-diff is comment-only; `plistlib` dicts identical).

**`poller.launchd.err` is NOT current.** It holds 234 lines ending in `_LRP_SELF: unbound variable`, `account-map.generated.sh: line 21: syntax error`, `cc_acct_name_for_dir_basename: command not found` — but its **mtime is Sep 15 19:48**, and both defects are since fixed (`_LRP_SELF` now assigned at `:141`; `bash -n ~/.claude/lib/account-map.generated.sh` is clean, file rewritten Sep 19 13:16). Today's five PARKED lines prove `acct_of_cfg` resolved. Do not cite that stderr as a live fault.

---

## 3. What it will do at 19:40:00Z to five sessions the operator already recovered

All five parked records are **still on disk** (`ls ~/.reso/limit-recover/parked/` — 5 files, mtimes 11:59 and 12:09). At 19:40 the loop reaches `:898`:

```
scripts/limit-recover/lr-reset-poller.sh:902-905
  if command -v lr_transplanted_to >/dev/null 2>&1 && _lrp_to="$(lr_transplanted_to "$sid" "$cfg")"; then
    log "TRANSPLANTED $sid ($acct) → $_lrp_to; parked record retired (the successor carries it)"
```

`lr_transplanted_to` (`scripts/limit-recover/lr-lib.sh:262-273`) requires (a) `locks/<sid>.lock` holding a `"to"` cfg ≠ the source, and (b) `ls "$to"/projects/*/"$sid".jsonl`. **Both hold for all five** — verified:

| sid | lock `to` | successor transcript |
|---|---|---|
| `09e64dcb` | `.claude-tertiary` | present |
| `28f07827` | `.claude-secondary` | present |
| `cb227486` | `.claude-secondary` | present |
| `d02d8feb` | `.claude-secondary` | present |
| `e442434c` | `.claude-tertiary` | present |

**Verdict: no duplicate spawn at 19:40.** The tombstone arm is correct and will retire all five. The residual defect is that the retirement *also* waits behind `:896` — the ledger will carry five stale "parked" records for 2h41m after the work was actually recovered, so any consumer reading `parked/` as live state is wrong for that whole window.

### But if they had NOT been transplanted, the poller would have abandoned two of them

`MAX_PER_RUN=4` (`:282`), `MAX_PER_WT=1` (`:289`). Today's five span three worktrees: `claude-infrastructure` ×3, `wt-cc-095358-75429`, `wt-cc-100046-36511`. On the spawn path, `lr-select` picks **one winner per worktree** and the two losers in `claude-infrastructure` are retired, not deferred:

```
:958   log "LISTED $sid ($acct) — $why; consolidated, resume by sid if wanted"
:959   mv "$pf" "$RESUMED/$(basename "$pf")" …
```

That is a *silent write-off of two of five sessions*, recoverable only by a human resuming by sid. (Conditional: the live-pane NUDGE arm at `:928` sits above the contest and nudge candidates are dropped from candidacy at `:850`, so if all five still had live registry rows they would all take the nudge path — but `MAX_PER_RUN=4` at `:932` still caps the tick at 4, deferring the 5th ten minutes.)

---

## 4. The request/queue protocol — complete end to end, proven once, three named gaps

### Producer — `lr-fleet.sh --enqueue` (`scripts/limit-recover/lr-fleet.sh:444-467`)

```
:449   case "$disp" in RECOVERABLE|NO-PANE) : ;; *) continue ;; esac
:453   [ "$kind" = limit ] || continue        # last api-error must be a cap, not a network drop
:456-7 jq -n … '{sid:$sid, target:$target, source_pane:$pane, requested_by:$by, ts:$ts}' > "$STATE/requests/$sid.json"
:463-4 echo "…to run it now:"; echo "  launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller"
```

### Consumer — poller `§0 REQUESTS` (`lr-reset-poller.sh:639-661`)

Runs **first in the tick**, before detection, inside the self-overlap lock:

```
:657   "$FLEET" --one "$_rq_sid" --target "$_rq_target" ${_rq_pane:+--source-pane "$_rq_pane"} --from-daemon > "$RESULTS/$_rq_sid.log" 2>&1 || _rq_rc=$?
:658-9 jq -n … '{sid:$sid, rc:($rc|tonumber), ts:$ts, log:$log, requested_by:$by}' > "$RESULTS/$_rq_sid.json"
:660   rm -f "$_rq"
:661   log "REQUEST $_rq_sid — done rc=$_rq_rc (result $RESULTS/$_rq_sid.json)"
```

Its *raison d'être* is stated at `:641-643`: a session's own tool is refused by auto mode's classifier when acting on a live pane; **a LaunchAgent runs outside every session and every classifier, so this is the locus that cannot be refused.**

### Is the path complete? YES — measured, 2026-09-14

```
poller.log:2522  2026-09-14T15:38:12Z REQUEST 5e0d69f7-… — executing the in-place recovery (target auto, pane 341) for 912fe54f-…
poller.log:2523  2026-09-14T15:38:57Z REQUEST 5e0d69f7-… — done rc=4
poller.log:2524  2026-09-14T15:38:57Z REQUEST a99681dc-… — executing the in-place recovery (target auto, pane 276) for 912fe54f-…
poller.log:2525  2026-09-14T15:39:38Z REQUEST a99681dc-… — done rc=4
```

Two requests drained in **one tick**, 45 s and 41 s wall each; both results written (`results/*.json`, `results/*.log`). Transport works.

**The payload failed identically to today.** `results/a99681dc-….log`, verbatim:

```
lr-handoff: transplant ok -> /Users/chrisren/.claude-quaternary/projects/…/a99681dc-….jsonl
lr-handoff: IN-PLACE — recycling pane 276 (registry-bound to a99681dc) onto 'next4': same window, same uuid
!! --recycle REFUSED: pane 276 resolved to no tty — the terminal does not enumerate it, so nothing can be typed into it.
lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=2). The transplant is DONE … the source pane is a tombstoned husk
…
a99681dc  276 → 276  next3 → next4  recycle-in-place/PARTIAL
RECOVERY PARTIAL — 1 named gap(s) above
```

**rc=4 / PARTIAL / tombstoned husk — the same last mile that produced 4 of 5 PARTIALs today.** So the daemon route is not a shortcut around today's failure; it hits the same wall from the other side.

### Today the path was not used at all

`ls ~/.reso/limit-recover/requests/` → **empty**. Newest `results/` entry → **2026-09-14 10:39**. The lead ran `lr-fleet --one` directly from the session; no request was ever enqueued. `grep -rn -- '--enqueue' scripts bin commands docs skills tests hooks` finds **zero programmatic callers** — only the flag's own parser (`lr-fleet.sh:79`), doc prose (`commands/limit-recover.md:5,404,437`) and two bats tests (`tests/lr-fleet.bats:157,282,289`). **Nothing in the fleet ever calls `--enqueue`.** It is a hand-typed escape hatch.

### The three gaps

1. **No auto-kickstart.** `lr-fleet.sh:463-464` *prints* the kickstart command for a human. Unkickstarted, enqueue→drain latency is up to **600 s**. The 2026-09-14 run shows the natural-tick case: previous tick 15:28:03, drain 15:38:12.
2. **Serial drain inside the lock.** Each request costs ~45 s of the tick (measured above) and holds the self-overlap lock (`:170-192`); detection for *every* account is behind it. 8 queued requests ≈ 6 min, and a tick that outruns 600 s makes the next tick a no-op `skip`.
3. **The result file has no reader and no alarm.** `fire_fail_note` / `fire_latched` (`:251-282`) instrument the poller's *own* nudge and spawn arms (`:938`, `:1007`) — the REQUEST arm at `:639-661` never calls them. A `rc=4` request logs one line and stops. The enqueuer is by definition a session that was *refused* and may be dead. **A PARTIAL daemon recovery is a file nobody reads** — exactly the "fire-and-forget husk" class. Likewise a request the poller cannot execute (`:648`, `$FLEET` not executable) logs `REQUEST-SKIP` once per tick and sits in `requests/` forever with no age alarm.

---

## 5. What would have to change for a ≤60 s in-place recycle

Ordered by what actually binds. **The detector is not the problem; it already ran at 11:59:23.**

| # | change | where | why / size |
|---|---|---|---|
| **A** | **Branch above the reset gate.** Today `:896` gates *everything*. A limited session with (i) a live pane and (ii) another account with headroom should be transplanted+recycled NOW; the reset wait is the *fallback* for when no account has headroom. | insert before `lr-reset-poller.sh:896` | ~25 lines. This is the semantic change; everything else is plumbing. |
| **B** | **Give the poller a target ranker.** It has none — `account_has_headroom` (`:382`) answers about one named account. Needs `claude-accounts --rank <tier>` (respecting the Fable/Opus tier already read by `lr_tier_from_transcript`, `:987`). Note today's observed ranker/chooser disagreement (`--rank fable` said next3 @11%, lr-fleet's dry run chose next @98-99%) means **B must be fixed in lr-fleet/lr-select first or the daemon inherits the same wrong target.** | new helper + `:931/:964` call sites | ~40 lines + the upstream ranker fix. |
| **C** | **Kill the 600 s floor for the request path.** Add `WatchPaths` on `~/.reso/limit-recover/requests` to the plist (`com.reso.lr-reset-poller.plist:37` currently `StartInterval 600` only; this repo already uses WatchPaths in `launchd/com.claude.browse-mirror.plist`), and have `lr-fleet --enqueue` stop printing the kickstart and just write the file. Latency enqueue→drain becomes ~1 s. | plist + `lr-fleet.sh:463-464` | ~6 lines. **Cheapest single win.** |
| **D** | **Kill the 600 s floor for DETECTION.** Options: (i) WatchPaths on the four `*/projects` trees — rejected, fires on every transcript append, far too hot; (ii) a Stop/PostToolUse hook in the limited session that writes `requests/<sid>.json` on seeing its own limit error (`hooks/recover-inject.sh` already recognises the limit shape) — this is the ~0 s path and it composes with C. | new hook + C | ~30 lines. Gets total limit→recycle under 60 s. |
| **E** | **Drain requests concurrently / off the lock**, or cap the in-tick drain and background the rest. | `:639-661` | ~15 lines. Needed once D makes requests arrive in bursts of 5. |
| **F** | **Extend the fire-fail latch to the request arm** — `fire_fail_note "$sid" request-rc$rc` on non-zero `_rq_rc`, plus a `results/*.json rc!=0` and `requests/*.json age>2 ticks` sweep that pages. | `:657-661` | ~12 lines. This is the answer to "can we identify it instead of fire-and-forgetting". |
| **G** | **Fix the last mile first.** Both the 2026-09-14 daemon runs and today's manual runs ended `recycle-in-place/PARTIAL` at *the same step* — `pane N resolved to no tty` / "no claude process appeared within 90s". Firing faster without this multiplies husks. | `lr-handoff.sh` / `handoff-fire.sh` recycle verify | **out of this unit's scope but it is the ordering constraint on A-F.** |
| **H** | **Drop the `MAX_PER_WT=1` write-off on the transplant path.** `:958` retires losers permanently. Five sessions in three worktrees ⇒ two silently abandoned. A transplant creates no memory pressure comparable to the 8.8 GB resurrection incident the cap was built for; the cap should bound *spawns*, not *in-place recycles*. | `:289`, `:947-961` | ~10 lines + a test. |

**Minimum viable ≤60 s path = C + D + F + G.** A + B + H turn it from "recycle when the reset arrives" into "recycle onto a fresh account immediately", which is what the operator asked for.

---

## 6. Things a rebuild should keep (this file is scar tissue, most of it load-bearing)

- **`lr_transplanted_to` tombstone check** (`:898-905`) — prevents the daemon re-firing a session `/limit-recover` already moved. Verified correct against today's five.
- **Live-pane NUDGE above the winner contest** (`:928`, comment at `:918-927`) — it sat *below* until 2026-09-09 and was unreachable dead code; the fix note explains exactly why.
- **`find -H`** (`:795`) — without it, `~/.claude-next/projects` (a symlink) yielded 0 transcripts and `next` was invisible to the poller forever. 0 vs 123.
- **Event-keyed, not sid-keyed, `resumed/` marker** (`:775-785`) — a sid-keyed skip made a session unrecoverable after its first limit.
- **Envelope conjunct in the pre-filter** (`:718`, `:746-747`) — the limit-recover *skill description* quotes the limit strings verbatim and rides in every session's `skill_listing`, so a bare text grep matched every healthy session.
- **`%q` on every interpolated field in the generated launcher** (`:990-1000`) — a `cwd` named `proj$(…)` re-expanded under launchd.
- **Absolute-path ladders for `timeout` and `tmux`** (`:60-78`, `:79-120`) — launchd's PATH has no Homebrew; the bare `command -v tmux ||` guard silently lost the tmux fallback for 24 days / 1,797 log lines.

---

## 7. Open / unverified

- I did not verify whether the five sids still hold live `session-register` rows (that read is another unit's; it decides nudge-vs-spawn at `:928` and therefore whether `MAX_PER_WT` bites). Stated conditionally in §3.
- Whether the 2026-09-14 requests were hand-kickstarted or drained on a natural tick is not recoverable from the log; the 15:28:03 → 15:38:12 gap is consistent with a natural tick (guess, labelled).
- `poller.launchd.err` mtime Sep 15 means the `_LRP_SELF` / `account-map` faults are resolved, but I did not bisect *which* commit resolved them.
