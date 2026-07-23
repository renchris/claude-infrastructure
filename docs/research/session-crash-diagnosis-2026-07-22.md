# Session-crash diagnosis — "sessions keep closing on themselves abruptly" (2026-07-22)

**Question (operator):** the last several sessions "keep closing on themselves abruptly."
Clarified symptom: **claude TUI → error text/freeze → back at a bare shell prompt; the
process exited, the tab survived.** A genuine process death, not a handoff.

## Ruled out (hard evidence, last 2–3 days, all 4 accounts)

| Suspected cause | Verdict | Evidence |
|---|---|---|
| `waiting-recycle.sh` auto-firing a recycle | not it | 28,046 abstains, 2 escalations, **0 fires** in `idl.jsonl` (despite `live-df1308af96473054` being armed) |
| `boundary-handoff.sh` closing sessions | not it | advisory-only — emits a latched `decision:block`, never execs a close |
| Reaper/watchdog killing live panes | not it | `cc-reaper`/`team-reaper` pruned only already-dead panes; teammate closes were post-work |
| Native crash (segfault) | not it | no `claude.exe-*.ips` crash reports anywhere |
| Logged-out account → launcher exits at open | not it | all 4 accounts healthy (the "keychain explosion" log is a test fixture) |

The `bridge-session` record is **not** a close-marker — it is routine persistence, present
in live sessions too. Early guesses keyed on it were wrong.

## Root cause — per-session bloat → single-process OOM (NOT aggregate concurrency)

`lead-crash-watchdog.sh` had been silently recording every abnormal death (pid dies while
its pid-file survives = no clean `SessionEnd`): **2,961 "LEAD CRASH detected" lines.** That
signal was **conflated** — it lumped deliberate self-recycles, genuine crashes, and operator
pane-closes together, which is why "why did it close" was unanswerable from disk.

**The load-bearing signal: the crashers are individually ENORMOUS.** Backfill of the last ~57
deaths (`cc-crash-report --backfill`): 4 deliberate-recycle, the rest CRASH, OOM-suspect
dominant — **`000ff296` = 65 MB / 16,963 records**, **`1a705246` = 62 MB / 27,105 records**,
plus several 6–13 MB. A single session grows to tens of MB / tens of thousands of records, then
its own `claude.exe` process exhausts memory → "error text → shell", pid-file survives.

**This is concurrency-INDEPENDENT** (operator: crashes occurred at **1–2 live sessions**; the
box has run 12–30 before without this). Two facts kill the earlier "aggregate memory pressure"
framing:

- The two **JetsamEvent** system-pressure reports (Jul 19, Jul 22) are a **separate, occasional**
  phenomenon — the giant crashers died **Jul 21**, days from any jetsam event, so they were *not*
  system-pressure kills. (The Jul-22 jetsam even flagged a daemon on a `per-process-limit`, not
  claude.) Aggregate load (qemu 4.8 GB + iTerm2 3.1 GB + many sessions) is a real but secondary
  tail risk, not the operator's crash.
- A single session's peak RSS I can see is only ~520 MB — which alone can't OOM a 64 GB box. So
  the fatal ceiling is **per-process** (JSC heap limit / an internal claude-code limit / a
  `/compact` crash on a huge session, GH #49593), reached by ONE bloated session.

**The exact per-process death mechanism is UNPROVEN** — the crash stderr is captured nowhere
(iTerm2 autologging off; the launcher doesn't tee the binary's stderr; no native `.ips`). That
capture gap is the reason this stayed unexplained, and is exactly what the resolution closes.

### Why sessions bloat now — the recycle is blind to size (the actionable root)

The auto-recycle that should cap a session **abstains** (0 fires in 2 days) while sessions reach
60+ MB, because its trigger is **context% window-fill (`used_pct`, line ~51/404 of
`waiting-recycle.sh`)** — *orthogonal* to the OOM risk, which is **transcript/RSS size**. A
session can be OOM-dangerous (huge transcript) at low context% (heavy caching/compaction), so the
size-blind recycle never fires. **This is the concurrency-independent prevention lever:** a
recycle (or `/compact`, or a per-process memory cap) triggered on session SIZE, not just
context%. It is a session-lifecycle change on a live-armed hook (could worsen "abrupt closes"),
so it is an **operator decision, surfaced not built here.**

**Adjacent, already-committed:** the session-sprawl fix (`resume-sessions` → `--max-per-worktree`
+ ceiling 4; commits `c29e454` …) reduces crash/limit-recovery multiplication. It addresses the
*occasional* concurrency tail, not the primary per-session bloat.

## Resolution (this branch — `fix/session-crash-diagnostics`)

1. **`lead-crash-watchdog.sh` — de-conflate + attribute** (`9b50140`). `classify_death`
   (top-level, unit-testable via `--classify <sid>`) separates a death into RECYCLE vs CRASH
   from the transcript + a JetsamEvent sweep: **jetsam-oom** (a report within ~6 min, highest
   confidence) outranks everything; deliberate-recycle via disposition/successor-brief phrasing;
   else CRASH (`suspected-oom-large-context` > 4 MB, else `abrupt-unknown`). Each death now
   writes a structured `~/.claude/logs/claude-crashes.jsonl` record (class, cause, transcript_kb,
   mem_free_pct, concurrent_claude), and **only a genuine CRASH alerts**. Bias: unsure ⇒ CRASH.
2. **`bin/cc-crash-report`** (`769782c`). Summarizes the ledger; `--backfill [N]` reclassifies
   recent history. Hard guard: refuses any watchdog hook lacking `--classify` (a stale copy would
   spawn a daemon per call — a bug caught + fixed in review).

Tests: `tests/lead-crash-watchdog.bats` (6) + `tests/cc-crash-report.bats` (4), all green.

**Honest limits:** `abrupt-unknown` still conflates real crashes with operator ⌘W-closes, so
the CRASH count is an upper bound; the `large-context` and (going forward) `jetsam-oom` rows are
the hard OOM signal. Historical backfill can't attribute jetsam retroactively (reports age out of
the 6-min window) — only live detection can.

## Follow-ups (surfaced, not done)

- **PRIMARY prevention decision — cap session SIZE before the per-process ceiling.** Add a
  transcript-size / RSS trigger to `waiting-recycle.sh` (today it fires only on context% `used_pct`,
  which is blind to the bloat that OOMs). Concurrency-independent; directly stops the 60 MB-session
  crash. Session-lifecycle change on a live-armed hook → operator's call (auto-recycle-on-size vs a
  size-threshold page vs an earlier forced `/compact`).
- **Confirm the exact mechanism:** capture `claude.exe` stderr (tee in the launcher) so the next
  crash names JSC-heap-OOM vs internal-limit vs `/compact`-crash. Until then `suspected-oom-large-
  context` is the working attribution; the ledger's `transcript_kb` is the signal to watch.
- **Secondary (occasional):** aggregate memory pressure (the Jul-19/22 jetsam events) — qemu (4.8 GB)
  and iTerm2 pane count (3.1 GB) are the operator-owned levers; the sprawl cap already trims the
  concurrent-session tail. Not the primary crash.
- **Deploy note:** `bin/cc-crash-report` is a brand-new tracked file — per the deploy-symlink gap,
  it is not auto-linked into the live `~/.claude/bin`; link + exercise the live path after landing.
