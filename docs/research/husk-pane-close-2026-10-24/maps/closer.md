# Map: the post-exit closer (bin/cc-pane-close) and its gate 4, incident pane 289 (2026-10-24)

Read-only map. Every number is labelled **measured** (with its command) or **estimated** (with its method).
Line numbers are from worktree `wt-cc-203953-20264` at 7cdb9adae. Timestamps: logs in UTC (`Z`), except
`lead-crash-watchdog.log`, which is local time (CDT = UTC-5).

## 1. What pane 289 actually went through, in order

| UTC | Actor | Fact | Source |
|---|---|---|---|
| 23:23:22Z | SessionStart | `registered session=7555024a… pid=20092 tty=ttys046 pane=289` | lead-crash-watchdog.log:67932 (18:23:22 CDT) |
| 23:53:22Z | handoff-fire self-close | fired record `closedAt 23:53:22Z, succession.kind terminal` | ~/.claude/cc-fired/289.json |
| 23:53:36Z | cc-pane-runner | claude exited rc 0 → exit record `{rc:0, claude_started:true, ts:1792886016}` | ~/.claude/run/pane-exit/289.json |
| 23:53:36Z | cc-pane-runner `_close_pane` | fullscreen guard **refused**: `refused (refused-fs) kitty window 289 scope=pane … state=FS types=[4] onscreen=False`; pane kept, husk row `guard-fullscreen` | pane-say.jsonl ts 1792886017; bin/cc-pane-runner:323-333 |
| 23:53:36Z | cc-pane-verdict | painted DONE, "⌘W closes it · last pane of a fullscreen window" | pane-say.jsonl ts 1792886016 |
| 23:53:38Z | handoff-fire | close-attrib `STILL-PRESENT-rc70` | close-attrib.jsonl:1256 |
| 23:55:00Z | lead-crash-watchdog | `pane_work_state` read `dirty:138` → **CANTTELL** (repaints over DONE); husk row re-added with `reason=ended` (overwrites `guard-fullscreen`; pcq_add updates the row, scripts/lib/pane-close-queue.sh:28) | lead-crash-watchdog.log:67947-67948; pane-say.jsonl ts 1792886100 |
| 00:00:13Z | drainer → cc-pane-close | gate 4 refused: `/Users/chrisren/Development/personal holds 138 uncommitted change(s)` | pane-close.jsonl; pane-close-retry.log "attempt 1" |
| 00:00:14Z | drainer → cc-pane-verdict --recompute | **RESUME** "⛔ resume 7555024a / ✗ stopped mid-task · 138 unsaved files / ▶ cc-husk-sweep --resume --yes --pane 289" | pane-say.jsonl ts 1792886414; bin/cc-pane-verdict:86-87 |
| 00:00:13Z → 01:38:50Z | drainer | 21 attempts: 9 × gate-4 refusal (rc 1), 12 × rc 124 with no output | pane-close-retry.log, `grep 'pane=289'` |
| 01:45:55Z | drainer | row removed: `its tty was typed in since  — the operator owns it; row removed, never closed` (first_ts prints empty: the row is read after `pcq_remove`, scripts/pane-close-retry.sh:279) | pane-close-retry.log |
| ≤01:56:56Z | ? | pane gone. **Measured**: `CC_PANE_CLOSE_LOG=/tmp/closer-map/pc.jsonl bin/cc-pane-close --pane 289 --dry-run` → `ALREADY CLOSED — kitty's window list (kitty pid 1881) does not hold this pane`. No pane-close/close-attrib row records who closed it. | — |

Total in-between time: ≥112 min from claude's exit (23:53:36Z) to the row's removal (01:45:55Z).

The incident therefore has **three** independent keep reasons stacked, and the closer only ever reported the
last: (a) the runner's fullscreen guard (`onscreen=False`, i.e. the window was FS on another Space at that
instant), (b) the watchdog's whole-tree dirt read → CANTTELL, (c) cc-pane-close gate 4 → recompute RESUME.
Because gate 4 runs **before** the closer's fullscreen guard (bin/cc-pane-close:509-520), the drainer never
learned whether the guard still refused; its operator-hold path keys on `refused-fs` in the closer's output
(scripts/pane-close-retry.sh:315), which gate 4 masks.

## 2. The closer: bin/cc-pane-close, all gates

Entry: `close_one` (bin/cc-pane-close:402-555), once per `--pane`. Preconditions before any gate: a running
kitty pid from `$KITTY_LISTEN_ON` or `bin/cc-kitty-socket` (:111-117, :396-399) — no kitty ⇒ exit 1, nothing logged.

| # | Gate | Lines | Fails closed with |
|---|---|---|---|
| 0 | GONE: kitty's pinned listing answers and does not hold the pane ⇒ `gone`, rc 0 | :409-413 (listing :252-268, `it2 session list` bounded 10 s, pinned `CC_TERM=kitty CC_TERM_KITTY_TO=unix:/tmp/kitty-$KPID`) | — |
| 1 | IDENTITY: last `registered session= … pane=N` line in lead-crash-watchdog.log inside this kitty's lifetime; or NEVER-LAUNCHED via exit record (`claude_started=false`, rc≠0, newer than registration) | :416-446 | "no session registration…" / "registration names no tty" / never-launched-but-kitty-deaf |
| 2 | NOTHING LIVE: registered claude pid gone or newer; window tree (root = tty proc whose ppid is kitty) holds only login/zsh/bash/sh; root started before registration | :447-488 | "its claude is still running" / "a live job runs" / "a different window" / "kitty names window process X" |
| 3 | MEANT TO END: teammate (`teamName`), last assistant `Good to close: yes` (following HANDOFF.json hops), custody abandon/return after registration, self-close stamp (`closedAt`) for this transcript, or MOVED with a LIVE copy (skips gate 4) | :489-507 (facts :342-367, custody :368-380, self_closed :381-390, moved_live :309-338) | "nothing says session … meant to end" / STRANDED / "no transcript" |
| **4** | **NO WORK AT RISK: `git -C "$cwd" status --porcelain \| grep -c .` must be 0** (cwd = last `cwd` field in the transcript); skipped only when never-launched or moved-live | **:508-512** | **"$cwd holds $d uncommitted change(s)"** |
| G | FULLSCREEN GUARD (remote control up): `kitty-fullscreen-guard --scope pane --mode refuse`; deaf: `--any-fs` | :519-534 (guard :153-201) | refused-fs / guard-missing / "could not read" / "remote control is down and a kitty window is in native fullscreen" |
| A | ACT: `it2 session close -f -s N --expect-generation KPID`, else SIGHUP to the window shell when remote control is DOWN (never when it said no); verify by root exit, 10 s reap wait | :519-554 | "remote control refused the close" / FAILED |

`--dry-run` stops after the guard and logs `would-close` (:521-523, :535-537). Every verdict appends a row to
`$CC_PANE_CLOSE_LOG` (default ~/.claude/logs/pane-close.jsonl, :144-149) — **including dry-runs**, so the log mixes
predicate checks with real attempts, and **a run killed by its caller's timeout writes no row at all**
(output is only printed at the verdict).

### Gate 4 specifics (why it refused 7555024a)
- It counts the **whole checkout's** dirt, in git's default untracked mode (directories collapsed): 138 lines.
  **Measured** now: `GIT_OPTIONAL_LOCKS=0 git status --porcelain | wc -l` in ~/Development/personal → 138
  (47 ` M`, 91 `??`); with `-uall` → 563 files.
- `~/Development/personal` is the shared checkout (`git rev-parse --git-dir --git-common-dir` → `.git .git`, not a linked worktree).
- Gate 4 is unbounded and takes optional locks (no `GIT_OPTIONAL_LOCKS=0`), i.e. it can grab `.git/index.lock`
  in a shared checkout while sibling sessions are committing. **Measured**: 3.29 s for one `git status --porcelain` at load avg 336.
- Gate 4 runs only after gate 3 passed, so **every gate-4 refusal is, by construction, a session that meant to
  end**. bin/cc-pane-verdict:86-87 nevertheless maps "uncommitted change" to RESUME ("stopped mid-task") — the
  closer's own logic contradicts that paint.
- The same whole-tree count exists in two more places, each with its own state model:
  hooks/lead-crash-watchdog.sh:1664-1671 `pane_work_state` (dirty ⇒ CANTTELL, :1997) and bin/cc-husk-sweep:508-518
  `work_of`/`verdict_of` (dirty ⇒ RESUME, then overridden by COLLECTED at :563). Gate 3 in the closer accepts a
  custody discharge as "meant to end" (:498) but still applies gate 4, while cc-husk-sweep treats the same custody
  discharge as COLLECTED ("close the pane", :595). Three copies of one predicate, three different answers.

## 3. Who invokes the closer (callers found by name)

`grep -rln cc-pane-close bin scripts hooks lib` → kitty-fullscreen-guard (comment only), cc-husk-sweep (message
only), cc-pane-verdict (comment), cc-pane-runner (comments), handoff-fire.sh (comments), pane-close-queue.sh
(comment); **real call sites**:

1. **scripts/pane-close-retry.sh `drain_husk`** (:261-328) — the husk drainer. `bounded "$pc" --pane N` with
   `TIMEOUT_S=${CC_PCQ_CLOSE_TIMEOUT_S:-60}` (:302-304) → `timeout -k 3 60` (:116-120). Deaf kitty ⇒ same call with
   `CC_PANE_CLOSE_REMOTE=off` (:304, :380-382). On rc 124 with empty output: logs "closer exceeded its 60s bound",
   `bump`s, **does not repaint** (:310-313). On any other non-close: `bump`, then `cc-pane-verdict --recompute
   --closer-out "$out"` (:320-326). Teammate rows on a deaf kitty also go to the closer (:366-378, bound = default
   `TIMEOUT_S` 10 s).
2. **hooks/lead-crash-watchdog.sh** — `pane_close_predicate` (:2174-2186): `lcw_bounded 60 cc-pane-close --pane N
   --dry-run`, only when the verdict block says "closing in"/"safe to close" (:2059-2061); and `pane_verdict_close`
   (:2188-2202): one real close after a 20 s grace, **unbounded** (`cc_run "$bin" --pane`, :2199). For 7555024a the
   block was already CANTTELL (dirty:138), so neither ran; only `pane_husk_row` (:2132-2150) did.

Producers of the `husk` rows the drainer feeds to the closer: bin/cc-pane-runner `_husk_row` (:155-172; sites
:292, :316, :332, :337, :365), lead-crash-watchdog `pane_husk_row` (:2132-2150), handoff-fire `hf_husk_row`
(:2251-2259; sites :11918-11919, :15809).

Triggers of the drainer (scripts/pane-close-retry.sh):
- launchd **com.claude.pane-close-drainer**: `StartInterval 300`, `timeout -k 5 270`, `CC_PCQ_DRAIN_TIMEOUT_S=240`,
  ProcessType Standard (~/Library/LaunchAgents/com.claude.pane-close-drainer.plist; repo launchd/ copy).
- **hooks/session-end.sh:116-146**: every SessionEnd that finds a queue row detaches a run, at most once per
  `CC_PCQ_SESSIONEND_MIN_S` (300 s) machine-wide via a stamp.
- **bin/cc-custody `_husk_drain`** (:79-91): one detached run when custody for a husk pane is returned/abandoned.
- Single-instance lock `$PCQ_DIR/.drain.lock` (:69-84); husks drained last, least-recently-tried first (:255-260,
  :514-516); a husk is deferred within 30 s of the 240 s run budget (:297-299).

Retry policy: **unbounded**. `bump` counts attempts and pages the desk **once** at `CC_PCQ_MAX_ATTEMPTS=6`
(:51, :212-222); the row stays until the pane is gone, its tty atime moves, its foreground is not a bare shell,
or kitty restarts (:264-281). rc 124 and real refusals count the same.
**Measured** cadence for 289: 21 attempts in 98.6 min (00:00:13Z → 01:38:50Z), mean 4.9 min; the gaps of
~2 min (00:10:44 → 00:12:56) are SessionEnd-triggered runs.

## 4. Can gate 4 be scoped to the session's own writes, and is the data there after exit?

Yes — all of it is durable after exit:
- **Transcript**: persists (`~/.claude-quaternary/projects/-Users-chrisren-Development-personal/7555024a….jsonl`,
  5.4 MB, 601 records); subagent transcripts under `<sid>/subagents/`. The closer already resolves it (gate 3).
- **Own edit set**: hooks/lib/session-writes.sh `session_writes_paths` / `session_dirty_mine` (:502-594), the fleet's
  SSOT for "files THIS session wrote" (Write/Edit/MultiEdit/NotebookEdit tool_use, main + subagents, canonicalised,
  `-uall`, `-z`). Known residue: files written only through Bash are invisible (:39-53).
- **Per-path time proof**: hooks/lib/peer-owned.sh `dirt_unreachable_by_session` (:822-917): a dirty path clears if
  it is not edit-recorded AND (mtime < session start OR it falls in a gap between tool windows with no background
  task). Already used by completion-assert (hooks/completion-assert.sh:964-968).
- **Session end instant**: the exit record's `ts` (cc-pane-runner, ~/.claude/run/pane-exit/<pane>.json,
  1792886016 = 23:53:36Z for 289) and the self-close stamp `closedAt` (cc-fired/<pane>.json). Gate 2 already proves
  the claude pid is gone.

**Measured** on 7555024a (script /tmp/closer-map/mine.sh, sourcing both libs, `GIT_OPTIONAL_LOCKS=0`):
- `session_writes_paths` rc 0: 2 paths (`reso-walkthrough/short/C-scenes/NOTES.md`, `…/scene.py`).
- `session_dirty_mine` rc **1**: none of its own edit-recorded paths is dirty.
- `dirt_unreachable_by_session` rc **1 (refuted)** — **not usable as-is post-exit**. Cause (/tmp/closer-map/act.sh):
  `_po_activity` → `META 1792884203 1792885958 1` (bg=1, so the gap clause is off) and an **open window
  `W 1792885958 -1`**: the final self-close Bash call never got a tool_result because the session exited inside
  it, so its window runs to +∞, and the one sibling write after the session ended
  (`.claude-tasks/TASKS.md`, mtime 1792893893 = 02:04:53Z) lands "inside" it.
- mtime split of the 563 `-uall` dirty files vs the transcript span 23:23:23Z-23:52:38Z
  (/tmp/closer-map/dist.py): **562 predate the session, 0 during, 1 after it ended, 0 deleted**.

So the scoped answer for 7555024a is unambiguous: none of the 563 files is its work. A post-exit variant of
the proof that closes open windows at the exit-record ts and counts mtime > end as unreachable would have cleared
the tree and closed the pane at 00:00:13Z (estimated: same predicate, applied to the measured split).

## 5. Quantification, last 14 days (pane-close.jsonl from 2026-10-11T01:35Z; retry log for husk rows)

Commands: /tmp/closer-map/an.py (pane-close.jsonl classes and episodes), /tmp/closer-map/husk.py (husk episodes in
pane-close-retry.log), plus the greps quoted.

**Measured, pane-close.jsonl rows (366 in window; 402 total since 2026-10-01):**

| Class | Rows |
|---|---|
| refused: G1 no registration | 151 |
| refused: never-launched, window unreadable (fixed 10-23, panes 145-147 then closed) | 130 |
| refused: remote control down + a window FS/unreadable | 23 |
| would-close (dry-run) | 15 |
| refused: G3 nothing says meant-to-end | 12 |
| refused: guard refused-fs | 11 |
| **refused: G4 dirty cwd** | **9** |
| closed-kitty-unreaped | 7 |
| refused: guard unreadable | 6 |
| refused: G3 no transcript / G1 different window | 1 / 1 |
| `closed` (plain) | **0** |

- 80 (pane, sid) episodes, 78 with ≥1 refusal; dominant class: G1 48, deaf+FS 11, G3 10, never-launched 4,
  refused-fs 2, G4 **1**, others 2.
- **Panes refused only by gate 4 in a shared cwd: 1** (pane 289, 9 rows, all
  `/Users/chrisren/Development/personal holds 138`). It is also the only gate-4 refusal in the log's whole lifetime
  (`jq 'select(.reason|test("uncommitted"))'` → 9 rows, all pane 289).
- **rc 124 never appears in pane-close.jsonl** (the closer is killed before `log_row`). From pane-close-retry.log:
  **25 rc-124 attempts on 6 panes** (145:1, 146:1, 165:5, 280:4, 282:2, **289:12**), all 2026-10-23..25;
  18 "closer exceeded its 60s bound" lines (6 on 10-24, 12 on 10-25 UTC; the message postdates some rc-124 rows).
  For 289, rc 124 was 12 of 21 attempts (57%).
- **How long panes stayed** (first → last row; a lower bound — the pane may outlive its last row):
  pane-close.jsonl refused episodes median 0 min (one-row dry-run predicates), p90 456 min, max 1328 min (pane 42).
  Husk-row episodes (retry log): 135 133 min, 139 17, 141/142 33, 144 904, 145-147 806-807, 165 467, 280 63, 282 44,
  **289 106 min of retries (≥112 min from claude exit)**.
- Watchdog side (lead-crash-watchdog.log, 10-11..10-24 CDT): 23 "the closer keeps pane" lines — 12 G1 no
  registration, 8 deaf/unreadable, 2 ⌘W, 1 G3. The watchdog's own whole-tree dirt check is what made 289 CANTTELL
  (pane-say ts 1792886100 `uncommitted work in personal … dirty:138`).

**Why rc 124** (estimated): not reproduced (pane 289 was gone by the time it could be timed). Measured component
costs at load avg 336 (`uptime`): the 5-store transcript glob `"$s"/projects/*/"$sid".jsonl` in
`transcript_resolve` (:223-234) over ~18.2-18.8k project dirs per store = **11.05 s** total
(/tmp/closer-map/glob.sh: 3.68 + 2.60 + 1.65 + 2.33 + 0.79 s); `git status` 3.29 s (unbounded); it2 list 0.34 s;
python transcript pass 0.42 s; plus a bash `while read` + `date -j` fork per matching line of a 9.6 MB
watchdog log. The glob is the largest bounded-by-nothing cost and scales with project-dir count and load; under
the 300-350 load spikes logged, it plausibly pushes a run past 60 s. A first attempt to time the glob via
`ls ~/.claude*/projects/*/<sid>.jsonl` did not finish within 120 s.

## 6. Fix levers (closer-scoped; ordered by leverage)

1. **Scope gate 4 to the session's own work, in one shared helper used by all three copies**
   (cc-pane-close:509-512, lead-crash-watchdog.sh:1664-1671, cc-husk-sweep:508-518). Refuse only on:
   `session_dirty_mine` rc 0 (own edit-recorded dirt) OR a post-exit per-path proof that refutes (a dirty path
   whose mtime falls inside one of the session's tool windows). The post-exit proof is
   `dirt_unreachable_by_session` plus two clauses: close any open window (`-1`) at the exit-record ts
   (pane-exit/<pane>.json, or `closedAt`), and count `mtime > end` as unreachable. Keep cannot-tell (rc 2) as a
   refusal. This keeps the skeptics' concern (round2 skeptics.md:31: gate 4 is the only thing protecting a crashed
   teammate's work) because own edit-recorded dirt and in-window dirt still refuse. Open question to verify before
   relying on the `mtime > end` clause when `bg=1`: whether Claude Code's background shells outlive the session.
2. **Fix the verdict mapping**: a gate-4 refusal implies gate 3 passed, so cc-pane-verdict:86-87 must not paint
   RESUME "stopped mid-task" from it. Own-dirt → RESUME is fair; foreign dirt → DONE (close).
3. **Bound and de-lock gate 4**: `GIT_OPTIONAL_LOCKS=0` and a timeout on the `git status` (the libs already use
   `_po_bounded 5`), so gate 4 can neither stall the run nor take `index.lock` in a shared checkout.
4. **Kill the glob**: resolve the transcript from data that already names it — the fired record's `transcript`
   (cc-fired/<pane>.json), the registry (cc-registry/<pane>.json), or the cwd-derived project dir — before falling
   back to the 5-store glob. That removes the largest measured cost behind rc 124.
5. **Print before you can be killed / give rc 124 a reason**: the closer prints and logs only at its verdict, so a
   60 s kill leaves no row in pane-close.jsonl and nothing to repaint. Log a `timeout` row from the drainer (it
   knows the pane and sid) and report which gate was running (e.g. a progress line on stderr per gate).
6. **Ask the guard before gate 4, or report both**: today gate 4 masks the guard, so the drainer's ⌘W operator
   hold (pane-close-retry.sh:315) cannot fire. Either order the cheap remote checks first or carry every failing
   gate in one refusal line.
7. Small defects: pane-close-retry.sh:279 logs `first_ts` after `pcq_remove` (prints empty); pcq_add's update lets
   the watchdog's `reason=ended` overwrite the runner's `guard-fullscreen` reason on the same row; rc 124 counts
   toward the 6-attempt page the same as a real refusal.

## 7. Scope notes
- Read-only. The only command that touched a fleet tool was one `cc-pane-close --pane 289 --dry-run` with
  `CC_PANE_CLOSE_LOG=/tmp/closer-map/pc.jsonl` (so pane-close.jsonl was not appended); it answered ALREADY CLOSED.
- All git reads used `GIT_OPTIONAL_LOCKS=0`. Analysis scripts are in /tmp/closer-map/.
