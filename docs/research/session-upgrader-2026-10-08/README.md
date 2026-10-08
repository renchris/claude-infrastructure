# In-place session upgrader — measured, redesigned, rebuilt (2026-10-08)

The upgrader (`scripts/limit-recover/lr-upgrade.sh`, driven by the launchd poller
`com.reso.lr-reset-poller`) moves an idle live session onto the current Claude Code binary in the
same pane with the same session id. On the 2.1.284 → 2.1.293 move it was slow, lost sessions it
was halfway through, retried some forever and never retried others, and paid one full-context
turn per session. This page records what was measured, the design chosen, and what changed.

## 1. Where the minutes went (before)

Sources: `~/.reso/limit-recover/upgrade/<sid8>-<ts>/{events.jsonl,handoff-fire.log}`,
`results/*.json`, `upgrade-drain.log`, `poller.log`, `~/.claude/logs/cc-reaper.log`, and the
upgraded sessions' transcripts.

Six sessions upgraded to 2.1.293 between 18:53Z and 19:21Z (drain pid 894):

| pane | sid8 | census + admission | prefire | /exit | wait for exit | boot | engage | confirm | verdict | total |
|---|---|---|---|---|---|---|---|---|---|---|
| 2 | 7f5deb68 | 91 | 7 | 9 | 20 | 6 | 8 | 5 | 21 | 169 s |
| 3 | 1c0f7f90 | 369 | 7 | 6 | 19 | 13 | 0 | 4 | 28 | 447 s |
| 8 | cbbbbfcb | 197 | 5 | 8 | 69 | 5 | 2 | 3 | 23 | 312 s |
| 12 | c56c729c | 176 | 6 | 9 | 78 | 5 | 6 | 4 | 22 | 307 s |
| 14 | 4d059264 | 159 | 6 | 12 | 23 | 6 | 6 | 3 | 24 | 240 s |
| 15 | 7a588319 | 149 | 10 | 9 | 93 | 8 | 3 | 2 | 24 | 299 s |

The move itself (prefire through confirmation) took 60–150 s. Everything before it took 91–369 s,
and it was three things measured directly:

- **The capacity probe's phantom-session scan**: one `jq` fork per beat file over 7105 files,
  70–87 s per probe at load 39–45, inside every drive (`lr_phantom_actives`, `lr-lib.sh`).
- **The drive-time census judged the whole fleet** and then kept one pane: 24.6 s at load 45 for
  22 rows; minutes at the load 100–275 the drains ran under.
- **`LRU_GAP_S`** (10 s) and the reconciler fence (up to 17 s).

The longest session, pane 37 (d1e95e5d), took 3855 s: 2905 s before its launcher was minted under
load 100–275, then `/exit` was sent, the old claude never exited, and the watcher gave up after
893 s. The drain was then killed.

**Drains died.** `cc-reaper` sent TERM to `lr-upgrade.sh --drain` as an "orphan bash" 10 times
that day (ages 639–4182 s); three deaths were mid-session (c56c729c, 30c3a88d, and d1e95e5d
after `/exit`). Nothing recorded which step a killed drive had reached. 27 of 78 poller ticks
logged no auto-enqueue verdict (the in-tick census shared a 60 s bound), and drains were 60–98
min apart.

**Skips were unbounded and expensive.** 125 of 134 outcome rows that day were one cause,
`relaunch-surface-unverified (surface rc 3)` (fixed in 673add0dd), repeated 9–13 times per
session, each after 55–640 s of census and capacity and each minting a capacity token first
(unredeemed tokens count as active load for 1020 s; up to 7 were seen at once). Pane 33's
`exit-readback '<unreadable>'` abort was a skip like any other, never retried by design and
never marked.

## 2. Where the tokens went (before)

The confirming turn, over the 6 upgraded sessions: **1,027,708 cache-write, 4,127,188
cache-read, 4,359 output tokens**, 3–7 API calls each (the prompt asks the session to re-arm its
inbox watcher, so it makes tool calls). Four of six had been idle 1.4–96 h, so the relaunch paid
a full cache rewrite of the session's context (up to 363K tokens). The process proof the drive
already ran (a registry-bound live `--resume` process on the target binary and model, held
15 s) proves the move; the turn added only "this binary, model and account answers a call".

## 3. Design (judged panel)

Three rival designs, each attacked by an adversarial reviewer asked how it strands a pane, then
scored by a judge against the measurements:

| design | fit | strand risk | guards | size | fault tolerance | total |
|---|---|---|---|---|---|---|
| A. one serial drainer, tuned | 8 | 7 | 7 | 7 | 7 | **36** |
| C. event-driven drain (launchd WatchPaths) | 5 | 3 | 4 | 4 | 5 | 21 |
| B. bounded concurrency 2–3 | 3 | 4 | 5 | 3 | 5 | 20 |

Concurrency was rejected: 25,470 s of the day's drive time was census and admission against
about 1,900 s of move steps, so width was not the lever, and its own load gate would have
forced width 1 at the loads that mattered. The event-driven job was rejected: launchd kills a
job's process group, which takes handoff-fire with it mid-recycle. The serial path was mostly
waiting on work that could be removed, so that is what was built, with grafts from both
runners-up and every attack fix.

## 4. What changed

| commit | change |
|---|---|
| 8e3fd6a0e | per-pane census: unrequested rows skip pass 2; the process table is cut to registry pids once |
| 7572da583 | capacity probe: an uncorrected admit is final, so the phantom scan runs only on a refusal; the scan is one `jq` pass |
| 85a67c70b | state record, step ledger, crash settle, bounded retry, `--status`, `--reset`, prompt-free proof, self-bounded and self-refilling drain |
| 5de53c98b | `cc-reaper` never collects `lr-upgrade.sh --drain` (by that argv only) |
| 98455412a | 41 hermetic bats cases for the above |

- **State record** `~/.reso/limit-recover/upgrade-state/<sid>.json` (and a `.open` sentinel while
  in flight or exit-pending): disposition, step, step start, attempts, readbacks, last reason,
  run dir, token, receipt, pane identity, old pid and lstart, handoff-fire pid and lstart.
- **Step ledger**: one `lru-step` row per closed step in the run's own `events.jsonl`
  (`outcome`, `dur_s`, `attempt`, `load1`). Fleet query:
  `cat ~/.reso/limit-recover/upgrade/*/events.jsonl | jq -c 'select(.state == "lru-step")'`.
- **Crash settle** at every drain start. Which side of `/exit` is read from handoff-fire's own log
  lines (debt open, `ABORTED (held: …)`, abandon), not from whether the old pid is alive. Before
  `/exit`: orphan watchers are ended, the token, receipt and team hold are given back. After it:
  the only relaunch is `handoff-fire.sh --relaunch-at-shell` (launch lock, no live holder, pane at
  its shell, identity file, fresh capacity), else `cc-resume-debt` relaunches in a new window. The
  raw `it2 session run` retype loop is gone.
- **exit-pending**: `/exit` sent and the old claude still alive (pane 37's shape) is watched,
  never typed into; paged once at 30 min; terminal `exit-unanswered` at 6 h.
- **Bounded retry**: the session's own state (mid-turn, busy, capacity, occupied composer) is a
  free wait. A fault in our machinery, or an exit-readback, costs an attempt: backoff 10 then 20
  min, terminal `exhausted` or `exit-readback` at 3, expiring after 6 h; a new target clears it,
  `--reset` clears it by hand. Our own `/exit` left in a composer is cleared with one Ctrl-U,
  only on an exact `/exit` read, and verified by read-back.
- **Cheap checks first**: composer and relaunch surface before the capacity mint; any skip
  after the mint gives the token back.
- **Prompt-free relaunch** for a plain session once its (binary, model, account) has answered one
  canary turn: proven by the registry-bound process, the pane binding and lr-fire-resume's
  READY; nothing is typed if READY is missing. Leads keep their prompt. `LRU_CONFIRM_TURN=on`
  restores a turn for every session.
- **Drain**: bounds itself (`LRU_DRAIN_MAX_S` 3600 s, census `LRU_CENSUS_TIMEOUT_S` 300 s),
  refills from its own census, and the poller starts it every tick instead of running a census
  inside its 60 s tick bound.
- **`lr-upgrade.sh --status [--json] [--census]`**: per session the disposition, step, time in
  step, attempts and last reason; a fleet line by binary.

One hazard surfaced during the measurement: a headless `claude --print` child (from
`cc-upgrade-gate.sh`) inherited this session's pane id, and the census called it `upgrade`; the
deployed drainer then tried pane 50 and only handoff-fire's tty binding refused it. `fc3609e9f`
(another session, landed the same afternoon) marks such rows `headless`; this work kept that
implementation.

Every existing guard stays: idle only, capacity admitted before `/exit`, nothing typed into an
occupied composer, an unknown surface types nothing.

## 5. After (live pass)

Landed `98455412a` and converged the live layer (`deploy-live.sh` at the land, degraded tier,
never `--force`). One explicit drain on the live fleet then ran end to end on the new code: settle
found nothing open, the refill census took 26 s at load 66, nothing was eligible, and the drain
finished in 26 s. Nothing was upgraded, because nothing was idle on the old binary: the census at
23:14Z read `.claude-293` 19 · `.claude-284` 2, the two being pane 7 (mid-turn, actively working)
and pane 37 (in the background-sessions view). The poller now starts the drainer every tick, so
pane 7 moves on the new code when it goes idle, and its `lru-step` rows will give the first
end-to-end after-measurement.

The after column is therefore **the new pre-typing path measured live** (three runs at load 61-64,
read-only, against pane 7: per-pane census 9.2-18.3 s, composer read 0.2-0.3 s, relaunch surface
0.6-0.8 s, capacity probe 2.9-6.3 s on its lazy admit path, plus the 10 s gap) **added to each
session's own measured move steps**, which this change does not touch:

| pane | sid8 | before total | before census + admission | after census + admission (measured) | after total (projected) |
|---|---|---|---|---|---|
| 2 | 7f5deb68 | 2.8 min (169 s) | 91 s | 23-36 s | 1.7 min (101-114 s) |
| 3 | 1c0f7f90 | 7.5 min (447 s) | 369 s | 23-36 s | 1.7 min (101-114 s) |
| 8 | cbbbbfcb | 5.2 min (312 s) | 197 s | 23-36 s | 2.4 min (138-151 s) |
| 12 | c56c729c | 5.1 min (307 s) | 176 s | 23-36 s | 2.6 min (154-167 s) |
| 14 | 4d059264 | 4.0 min (240 s) | 159 s | 23-36 s | 1.8 min (104-117 s) |
| 15 | 7a588319 | 5.0 min (299 s) | 149 s | 23-36 s | 2.9 min (173-186 s) |
| **mean** | | **4.9 min** | 190 s | 26 s | **2.2 min** |

`lr-upgrade.sh --status` after the live drain:

```
lr-upgrade  2026-10-08T23:14:48Z · drainer idle
census 0s ago (26 s, load1 66.38)
PANE  SID8      FROM         TO           DISPOSITION   STEP       IN-STEP  ATT  LAST REASON
fleet (cached census): .claude-284 2 · .claude-293 19 —
```

A skipped session now costs about 25 s and no token, against a median of about 170 s plus a
leaked token. The gap between drains is at most one poller tick plus a census, against the 60-98
min gaps measured. The confirming turn is spent once per (binary, model, account) instead of
once per session: after the first canary, a plain session's relaunch costs 0 model tokens against
a measured mean of 171K cache-write and 688K cache-read. Most of that cache write is deferred to
the session's next real turn rather than saved.

Proof: 41 new hermetic bats cases (`tests/lr-upgrade-state.bats` 20, `tests/lr-upgrade-settle.bats`
21) plus the existing suites: `lr-upgrade` 56, `lr-upgrade-custody` 7, `lr-lib` 60,
`lr-reset-poller` 38, `lr-reset-poller-requests` 44: 246 tests, 0 failures, run before the land.
They include the drain killed between `/exit` and relaunch, one session failing while the next
proceeds, and the read-back unreadable three times reaching the `exit-readback` terminal.

Backlog row `139f3cb28419` (five idle sessions on the old binary) was already closed by another
session at 22:22Z with the falsifier "the census shows no `upgrade` row", which this census
confirms.

## 6. Remaining risks

- The prompt-free READY rate on 2.1.293 is unmeasured until the first prompt-free relaunches;
  `LRU_CONFIRM_TURN=on` is the switch back.
- The refill census runs every tick (13.5 s at load 45, more under load), the same work the
  in-tick census attempted before its 60 s kill; its duration is in `.census.tsv`.
- `cc-resume-debt` can discharge a debt by proving the very pid it told to exit; lr-upgrade's
  exit-pending owns that case for upgrades, the tool itself is unchanged.
- Pane 37 showed Claude Code's background-sessions view, whose input placeholder reads as an
  occupied composer, so it is (correctly) never typed into until someone returns it to the chat.
