# Session-close attribution + machine lag — forensics, 2026-07-26

Investigation trigger: operator reported (a) lag suspected to come from Claude Code memory, and
(b) sessions "abruptly ending" even when not a handoff and while Agent-Team members were working.

Both were investigated against live disk truth. **They are largely independent problems**, and the
headline for each inverts the initial hypothesis.

---

## 1. The abrupt session ends

### 1.1 What it is NOT

- **Not the kernel.** No jetsam/OOM kills in 12h (`log show … "jetsam"|"memorystatus"` → empty).
- **Not memory.** `claude-crashes.jsonl`: `mem_free_pct` at CRASH events ranges **74–88 %, mean
  86.2**. Deaths do not cluster at memory pressure.
- **Not our own signal-senders.** `pkill`/`killall`/`kill -TERM` appear **nowhere** in the live
  `~/.claude/{hooks,bin,scripts}` tree (grep -R, symlink-following).
  🚨 **THIS EVIDENCE IS REFUTED (recycle #298, 2026-09-04T10:38:50Z). `grep -R` IS NOT
  SYMLINK-FOLLOWING.** Measured over those same three directories, `-R` reaches **9 of 429 files —
  2.1%** — and all nine are *real* files (four `__pycache__/*.pyc`, `bin/it2`,
  `bin/kitty-pane-menu-native`, and the two known strays), so it opened **not one** of the ~420
  symlinked scripts this clause is actually about. Re-asked with an instrument that can see the
  population, `find -L … -type f -exec grep -El 'pkill|killall|kill -TERM' {} +`, the same three
  directories carry those tokens in **29** files today — `cc-teardown`, `cc-notify`,
  `gate-cleanup.sh`, `handoff-fire.sh`, `ship-land.sh` and `postland-verify.sh` among them — and, at
  the checkout as of this document's own date (`2a979c15158c`, 2026-07-26), in **12**, including
  `hooks/teammate-auto-shutdown.sh` and `hooks/validate-bash.sh`. **The population was non-empty when
  this bullet was written: the sentence was false then, not merely stale now.**
  ⚠️ **What that does and does not overturn.** It removes the *evidence* for this bullet, not
  automatically its *conclusion* — a file that contains `pkill` is not a file that killed these
  sessions, and §1.2's end-to-end verified class is untouched. **Re-establish "not our own
  signal-senders" from reachability — which sender actually ran, in the window — never from a
  recursive grep's null over a tree it cannot walk.** Instrument + controls:
  `~/.claude/autonomy/probe298-270d.sh`.
- **Not the reaper.** `cc-reaper` sweeps in the window: `0 candidates 0 reaped`. `team-reaper`:
  `0 archived`. No `cc-teardown` invocation in `bash-execution.log`.

### 1.2 Class 1 — deliberate self-close whose pane-close half fails (VERIFIED end to end)

Incident: team `session-a3f68174` (wt-pool-2, "gate-reliability"), 2026-07-26T01:36Z.

Chain, every link confirmed on disk:

1. Lead's **last transcript record** is `tool_use Bash`, `desc="Self-retire the pane"`:
   `$HOME/.claude/scripts/handoff-fire.sh self-close --terminal`. A **deliberate** close.
2. Teardown marker `watchdog/teardown/a3f68174….json` → `"mode":"terminal"`, `"pane":"1FBFCD05…"`.
3. `/exit` landed: SessionEnd ran, pidfile removed, watchdog logged `pid file gone — exit`
   (i.e. correctly did **not** call it a crash).
4. The watcher then failed to close the pane:
   `/private/tmp/handoff-selfclose-1FBFCD05-…-1785029784.log` contains
   **`There was a problem connecting to iTerm2.`**
5. Result: **husk pane** — claude gone, pane alive at a shell prompt showing the resume banner.
   That husk is what the operator reads as "the session ended abruptly".

Rate: **1 of 16** real self-close logs that day (~6 %). The it2 Python API was healthy when probed
directly (3/3, 0.5–0.95 s), so this is an intermittent socket blip, **not** systemic saturation —
an earlier framing of mine that the evidence did not support.

**Compounding defect, same incident:** the lead ran
`git worktree remove --force /private/tmp/wt-gr-t{1..6}` and self-closed one tool call later while
**8 assignees were still running**. Four hours on they were still alive holding **3.4 GB**, their
worktrees deleted underneath them, every final report reachable only by digging its transcript off
disk. `selfclose_inventory_warn` counts unread mail and orphaned *fires* only, and is **WARN-only**.
This is also the source of the already-filed `teammate-auto-shutdown` "cannot resolve worktree"
false-surface pages (that backlog item names `t2-shipland@a3f68174`).

*Data-loss check (negative):* the 5 assignee commits (`4f73958 3629759 1b97724 8b8039a 33c557f`)
survive as objects; **no file from any of them is absent from `origin/main`** — the lead did
integrate the work before `git branch -D`. An initial "data loss" alarm was raised and **retracted**.

### 1.3 Class 2 — a real death mis-labelled as deliberate (detection gap)

Incident: `9850bcd5` (wt-94edb2fa9f14), 2026-07-26.

- Transcript runs `01:34:45Z → 01:36:32Z`, ending on a `tool_result`; the UI was mid-`Recombobulating`
  at 1 m 57 s with max effort. Nowhere near its brief's completion self-retire.
- Watchdog detected death at **01:53:15Z** — 17 minutes of silence — and logged `LEAD CRASH detected`
  (pidfile **present** ⇒ **no clean SessionEnd ran** ⇒ genuinely abrupt).
- Yet it was recorded `class=RECYCLE cause=deliberate-teardown`. **A real death was absolved.**

The specific marker that absolved it is **unproven** (its pane `A8672E6F` has no marker; the
watchdog GCs markers right after classifying). But the mechanism class is proven by code reading:
`hooks/lead-crash-watchdog.sh` matched a **pane-keyed** marker on pane-uuid + freshness (<30 min)
**without comparing the marker's `sid` field** to the dying session — though every pane-keyed marker
carries that sid. Any session dying in a pane within 30 min of a prior session's teardown was
absolved. Fix = `marker_owns_sid` (U9).

**The two classes couple.** A failed `it2 session close` (§1.2) leaves a husk pane *carrying a fresh
teardown marker*. That is precisely the precondition for the false absolution in §1.3.

### 1.4 Why this stayed invisible

`claude-crashes.jsonl`: **38 of 43** entries are `cause=abrupt-unknown`, every `stderr_log` empty,
`claude_version:"?"` on older rows. The close-attribution shim
(`10-close-attrib-activate.sh`) captures real exit codes/signals — it has **never been run** (C10,
operator-owned). Until it is, a genuine crash cannot be attributed without a manual trace like this
one.

---

## 2. The lag

**Claude Code memory is real waste but is not the lag driver.** Instantaneous sampling (`top`, not
`ps` lifetime averages — `ps -o %cpu` reports a *lifetime* average and made a 14-day-old iTerm2
look like a live hog before the cross-check):

```
load average: 18.80        (10 cores — ~1.9× oversubscribed)   ← this is the lag
iTerm2            127.7 % CPU   up 13d22h   top memory consumer
XprotectService    93.0 % CPU   (scanning the worktree/node_modules churn)
WindowServer       63.8 % CPU
kernel_task        40.6 % CPU
```

### 2.1 CORRECTION — what actually dominates that load

The above ranks iTerm2 first; **it is second**. Measured an hour later, from a landing attempt of
*this very branch* that the phenomenon killed: a **machine-wide gate runaway** — **six sibling
sessions each running a full ~120-suite landing gate concurrently**, load **20.96** on 10 cores,
1244 processes. Filed by a sibling as backlog `f8e40b4c577d`.

The loop is self-feeding:

1. load makes a gate suite slow → it is killed or times out
2. fail-closed degradation escalates **scoped → FULL** suite → *more* load
3. sessions try to unstick themselves with machine-wide `pkill -f 'bats-core/bats'` /
   `pkill -f bats-exec` — which kills **sibling** sessions' gates
   (`bash-execution.log` 20:42:27, 20:45, 169721)
4. those sessions retry → step 1

Evidence it is not code: this branch's `ship-land` exited 6 with **zero assertion failures** —
`tests/cc-reaper.bats` died `Killed: 9`, `tests/handoff-fire-validate.bats` `Terminated: 15`
mid-suite, the latter passing **3/3** on the exoneration re-run. No jetsam events; the kernel was
not OOM-killing. That is the third state this repo already names: **gate-never-ran ≠ gate-red** —
and it is *not* landing clearance either.

**Framing for the fix (owner: the `f8e40b4c577d` stream, not this one).** Parallel gates are
**deliberate** — `ship-land.sh`'s own header: *"The full gate runs UNLOCKED and therefore in
PARALLEL"*, the lock intentionally covering only the fetch→push→content-verify race. So the fix is
**not** serialization (that trades away the designed throughput) but **admission control**: cap
concurrent gates (~2–3) and queue beyond, plus scope those `pkill` patterns to the caller's own
worktree/PGID — a machine-wide `pkill -f bats` can never be correct with N sessions running.
Single-owner-per-file: this stream did **not** touch `ship-land.sh`; the evidence was sent to the
desk role instead.

*Counting caveat recorded because it nearly became a false claim:* a first pass reported "559 bats
processes across 5 worktrees". That was `grep -oE` counting path **occurrences inside single
command lines**, not processes. The true figure is **6 concurrent suites**. Count processes with
`pgrep`/line-wise `ps`, never by substring frequency.

Memory is *not* critical: **72 % free**, 2.56 GB of 4 GB swap.

Claude-side inventory: **57 claude-family processes, 15.25 GB** (20 leads 10.5 GB · 8 teammates
3.4 GB · 29 daemon/pty 1.4 GB). For comparison the Dia browser holds **10.6 GB across 41 processes**.

**Provably reclaimable: 5.3 GB**
- **3.4 GB** — the 8 orphaned assignees of the dead lead `a3f68174` (§1.2). Harvested to
  `docs/research/orphan-harvest-2026-07-26/` before any GC.
- **1.9 GB** — **four** concurrent `claude --resume 076a1186-…`, each under its own
  `lr-fire-resume.sh` expect wrapper, three spawned within ~90 s. Four processes appending to **one**
  transcript. Two holes: `lr-reset-poller` had **no self-overlap lock** (launchd fires it every
  ~10 min; a tick doing per-session `lr-audit` + `claude-accounts` outruns that on a loaded box), and
  its "already running" guard `pgrep -f "resume <sid>"` looks for the claude **child**, which does not
  exist during the multi-second launcher→expect→claude chain.

---

## 3. What was changed

| # | Fix | File | Tests |
|---|-----|------|-------|
| U8 | teammate-auto-shutdown drops a teardown marker before an idle close | `hooks/teammate-auto-shutdown.sh` | `tests/teammate-auto-shutdown.bats` |
| U9 | a pane-keyed marker must **name** the session it absolves (`marker_owns_sid`) | `hooks/lead-crash-watchdog.sh` | `tests/lead-crash-watchdog.bats` |
| G  | self-close **BLOCKS** (exit 4) on live teammates; `--allow-live-teammates` to override, LOUD | `scripts/handoff-fire.sh` | `tests/handoff-selfclose-teammate-gate.bats` G1-G6 |
| H  | `it2 session close` retried 4×; exhausted ⇒ desk page, never a silent husk | `scripts/handoff-fire.sh` | same file, H1-H3 |
| L  | poller self-overlap lock (pid+lstart identity) + TTL-bounded pre-spawn fire claim | `scripts/limit-recover/lr-reset-poller.sh` | `tests/lr-reset-poller-overlap.bats` |

U8/U9 were already built and **parked unlanded** on `fix/teammate-shutdown-marker`; they were
cherry-picked here rather than rewritten.

All new suites were **RED-proven** against the unfixed code (7/9 and 7/9 fail respectively). The
tests that stay green in both states are deliberate controls (`G6` no-behaviour-change for solo
sessions, `H3` happy path, `LO1b` positive control, `LO2` don't-over-block guard) and are labelled
as such — a vacuous negative assertion is worse than no test (cf. `debc016`, `1cfbde7`).

---

## 4. Operator-owned remainder (C10 — agent cannot self-activate)

1. `CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-close-attrib-activate.sh` — the only
   thing that makes a future death attributable without a manual trace. Then
   `touch …/10-close-attrib-activate.sh.done`.
2. **Restart iTerm2** — 13d22h uptime, 127.7 % CPU, top memory consumer, and the owner of the flaky
   Python-API socket behind §1.2.
