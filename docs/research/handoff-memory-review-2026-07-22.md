# /handoff mechanism + per-session memory review (2026-07-22)

**Scope (frozen):** a 100th-percentile review of (A) the `/handoff` mechanism and (B) machine-wide
per-transcript / per-session memory & state accumulation for memory-leak-like issues; (C) isolate
genuine crashes from the 93% watchdog noise; (D) fix the leaks + the watchdog root cause + capture
the crash stderr; (E) add concise zero-bloat telemetry so the next occurrence is one-grep traceable.

**Method:** disk-truth first (every claim tied to a command that ran), a parallel Opus research
workflow over axes A/B/C + telemetry with **adversarial reproduce-or-refute** on each finding, and a
bounded **Fable** baseline-blind derivation panel for unknown-unknown retention seams. Builds on —
does not duplicate — [`session-crash-diagnosis-2026-07-22.md`](session-crash-diagnosis-2026-07-22.md)
(prior desk; landed `ef7f7a4`).

---

## TL;DR (answer-first)

1. **The "crash to shell" mechanism was captured nowhere → now it is.** The operator's crashes
   (TUI → error text → bare shell, tab survives) are a **per-process** memory event. Its exact
   mechanism stayed unproven because *no launcher teed `claude.exe`'s stderr* (no iTerm2
   autologging, no native `.ips`). **FIX (shipped):** `bin/claude-latest` now tees stderr to a
   bounded per-pid log (`~/.claude/logs/stderr/<ts>-<pid>.log`), keyed by a pid that equals the
   watchdog's `LEAD_PID` — so the next crash **names** the mechanism and joins straight to its
   session + crash-ledger row.

2. **The 520 MB-RSS puzzle keeps the leak/spike hypothesis live.** The prior doc concluded
   *per-session bloat → single-process OOM* from genuinely enormous transcripts (65 MB / 16,963
   records). But its own evidence — **peak RSS ~520 MB** — cannot OOM a 64 GB box and sits far
   below any V8/JSC heap ceiling (~1.5–4 GB), and the operator has run **100%-context sessions
   with zero crashes**. So transcript size *alone* does not explain it; a **leak/spike** (the
   operator's hypothesis) remains open. The stderr capture is the discriminator — it resolves
   "JS-heap-OOM vs internal-limit vs `/compact`-crash" on the next event, not by theory.

3. **The "LEAD CRASH" signal was 93% false at the ROOT.** No `SessionEnd` hook removed the
   watchdog pid-file, so the daemon's clean-exit branch (`pid file gone`) was **never taken** on a
   normal exit — every clean `/exit`, ⌘W, handoff and recycle registered as a crash (3011/3244 =
   93%). **ROOT FIX (shipped):** `hooks/session-end.sh` now removes `<sid>.pid`, `<sid>.id` and
   `cp-<sid>.count` on clean `SessionEnd`. A genuine crash/OOM does **not** run `SessionEnd`, so its
   pid-file survives and the crash is still detected. `classify_death` (`abdafc4`) is **reconciled,
   not removed** — it stays as the secondary RECYCLE-vs-CRASH refiner for abnormal-but-deliberate
   pane kills (self-close / `--recycle`) that skip `SessionEnd`.

4. **Machine-wide per-session accumulation with NO reaper** (this is the "leak" the brief expected
   to find in state, distinct from the per-process OOM): **1,941 `cp-<sid>.count`** checkpoint
   counters + **83 stale watchdog pid-files** (of 93; only 10 live) + **~92 MB of logs** (several
   unrotated). `cc-reaper` touches none of the watchdog dir. The root fix reaps pid/id/cp per
   session going forward; a bounded backlog sweep + log rotation close the rest.

*(Parts 4–7 — the `/handoff` mechanism audit, genuine-crash isolation counts, the telemetry schema,
and the Fable unknown-unknowns — integrate the research-workflow results below.)*

---

## Part 1 — The "crash to shell": per-process memory event, now capturable

The prior doc established (and this review re-confirms) what the crash is **not**: not
`waiting-recycle` firing (0 fires in `idl.jsonl`), not `boundary-handoff` (advisory-only), not the
reaper (prunes only dead panes), not a native segfault (no `.ips`), not a logged-out launcher exit.
It is a real `claude.exe` process death that leaves the pid-file behind.

**The unresolved core.** The prior "bloat → OOM" story is *plausible but unproven*, and three facts
keep it open rather than closed:

| Fact | Tension with "size alone OOMs" |
|---|---|
| Peak observed `claude.exe` RSS ≈ **520 MB** | A 64 GB box does not OOM at 520 MB; V8/JSC old-space limits are ~1.5–4 GB. |
| Operator ran **100%-context (1M) sessions, zero crashes** | If big context/transcript were the cause, those would be the *first* to die. |
| Crashes at **1–2 live sessions, <60% context** | Concurrency-independent and context-low — the profile of a **leak/spike**, not steady size. |

The honest position: **the mechanism is unproven, and the operator's leak/spike hypothesis is the
better-supported one.** Rather than argue theory, this review closes the *evidence gap* the prior
doc named as its #1 follow-up:

**Fix — launcher stderr capture (`bin/claude-latest`).** At the single `exec` point, `claude.exe`
stderr is teed to `~/.claude/logs/stderr/<ts>-<pid>.log` while still shown live in the terminal
(UX unchanged) and the exit code preserved. Design properties:

- **Joinable by construction.** `exec` preserves the pid, so `$$` in the launcher == the
  `claude.exe` pid == the `LEAD_PID` the watchdog writes to `~/.claude/watchdog/<sid>.pid`. A crash
  log therefore joins directly to its session id and its `claude-crashes.jsonl` row — no guessing.
- **Zero-accumulation.** Only crashes/warnings write bytes; a clean run leaves a 0-byte file that
  the *next* launch garbage-collects (dead pid + empty). Non-empty crash logs are retained, capped
  at the newest 200. This does not itself become an unbounded log.
- **Fail-safe + reversible.** Any setup failure falls through to the original plain `exec`; kill
  switch `CLAUDE_STDERR_CAPTURE=0`. It can never block a launch.
- **Captures the informative class.** A JS-heap-OOM / JSC-abort / internal-limit prints its FATAL
  line to stderr and flushes before dying → captured. A silent `SIGKILL` (jetsam) writes nothing →
  empty → GC'd. So the log fills *exactly* when it can name a mechanism.

Tested end-to-end against a stubbed binary (`tests/claude-latest-stderr.bats`): exit code + stdout
preserved through the tee, stderr captured, kill-switch honored, empty-log GC verified.

**What this buys:** the *next* real crash is self-diagnosing. Until then `suspected-oom-large-context`
(transcript_kb > 4 MB) remains the working attribution and the ledger's `transcript_kb` the watch
signal — but the argument no longer has to rest on the RSS number that doesn't add up.

---

## Part 2 — Machine-wide per-session state accumulation (the state "leaks")

These are the unbounded-growth stores the brief expected in `~/.claude/**`. They accumulate on the
host filesystem (dir entries / inodes / log bytes); they do **not** directly cause the per-process
OOM, but they are exactly the "per-session state that is never reaped" class in scope B, and one
(the pid-file) is the root of the false-crash signal.

| Store | Now | Growth | Reaped by | Verdict / fix |
|---|---|---|---|---|
| `~/.claude/watchdog/cp-<sid>.count` | **1,941** (back to Apr 17) | 1 / session (any session with a Stop) | **NONE** (`cc-reaper` skips the dir) | Written by `teammate-checkpoint.sh:84`; never removed. **Fix:** `session-end.sh` reaps per session + a one-time backlog sweep. |
| `~/.claude/watchdog/<sid>.pid` | 93 (10 live, **83 stale**) | 1 / session; leaks when the daemon dies before its lead (reboot/kill/OOM) | NONE | The clean-exit branch never fired (no `SessionEnd` removal). **Fix:** root fix removes it on clean exit. |
| `~/.claude/watchdog/<sid>.id` | 93 | as above; **the daemon's clean-exit branch returns without removing `.id`** (`lead-crash-watchdog.sh:115`) | NONE | **Fix:** `session-end.sh` removes it alongside `.pid` (the daemon path can't). |
| `~/.claude/logs/**` | **~92 MB** | per-event; some rotate (`bash-*.log.gz`), some don't (`teammate-checkpoint.log` 14 MB, `lead-crash-watchdog.log` 2.1 MB, `sessions.log` 2.6 MB) | partial | **Fix:** size-cap rotation for the unrotated logs. |

*(Axis-B workflow may add further stores — `~/.claude/state/nudge-*.count`, `mailbox/*.md`, the
live-session registry, `~/.claude*/projects/**/*.jsonl` retention. Integrated below.)*

---

## Part 3 — Watchdog false-signal root fix + reconciliation with `classify_death`

**The bug (confirmed in code).** `lead-crash-watchdog.sh` spawns a per-session daemon that polls
`kill -0`. Branch logic: *pid-file gone* ⇒ clean shutdown, exit; *lead pid dead while pid-file
present* ⇒ "LEAD CRASH detected". **`hooks/session-end.sh` never removed the pid-file** — it only
logged and GC'd old `claude-versions`. So on every normal exit the lead died with the pid-file still
present → the crash branch fired. `SessionEnd` *does* fire reliably on clean exit (10,083
"Session ended" in `sessions.log`, 42 today), so the fix has a reliable hook to land in.

**The fix (`hooks/session-end.sh`).** On clean `SessionEnd`, remove `<sid>.pid`, `<sid>.id` and
`cp-<sid>.count` (sid validated to a safe charset first). Result: clean exits take the daemon's
"pid file gone" branch → **no crash record**; only a genuine crash/OOM/SIGKILL — which does **not**
run `SessionEnd` — leaves the pid-file for the daemon to detect. The signal becomes meaningful.

**Reconciliation (the two are complementary, not redundant).** Once clean exits stop tripping the
signal, the residual population that still reaches `handle_crash` is: (a) genuine crashes, and
(b) **deliberate pane kills that skip `SessionEnd`** — `handoff-fire self-close` / `--recycle` kill
the pane out-of-band, leaving the pid-file. `classify_death` (`abdafc4`) is exactly what separates
(b) RECYCLE from (a) CRASH via transcript-tail phrasing + a jetsam sweep. So:

- **Root fix** removes the 93% false-positive floor (clean exits).
- **`classify_death`** refines the *remaining* deaths (recycle vs real crash) and attributes cause.

Neither is removable. `cc-crash-report` continues to summarize the (now honest) ledger.

Tested: `tests/session-end.bats` (5) — reaps this sid's 3 files, leaves other sessions', safe no-op
on empty sid, refuses path-traversal sids, still logs. `tests/lead-crash-watchdog.bats` (6) unchanged
and green.

---

## Part 4 — `/handoff` mechanism audit  *(integrating axis A)*

_Pending research-workflow synthesis: orphaned watchers/daemons, unbounded per-fire state, temp-file
and fd leaks in `scripts/handoff-fire.sh` (2127 lines), `handoff-disposition.sh`, the handoff skill,
and the `cc-await-ping` / `cc-notify` / mailbox back-channels._

---

## Part 5 — Genuine-crash isolation  *(integrating axis C)*

_Pending: the defensible real-crash count/rate (transcripts truncated mid-tool_use, api-error
records, no-final-assistant) across the 4 account roots, and any common factor (version / operation
/ hook / account / time), cross-referenced with JetsamEvent timing._

---

## Part 6 — Telemetry design (concise, zero-bloat)  *(integrating axis D)*

_Pending: the exact one-line-per-handoff and one-line-per-crash schemas, reconciled with the existing
`claude-crashes.jsonl` + `cc-crash-report`, emit points, and the one-grep recipes._

---

## Part 7 — Frontier (Fable) unknown-unknowns  *(integrating)*

_Pending: baseline-blind derivation of retention/lifecycle seams (daemon double-spawn across
in-place recycle, pid-reuse false-alive, O(n) inbox rewrites) beyond the Opus-visible findings._

---

## Fixes shipped (this branch — `feat/handoff-memory-review`)

1. **`b026894`** `fix(session-end)` — clean-exit watchdog + checkpoint reap (root fix for the 93%
   false signal + the pid/id/cp accumulation). Tests: `tests/session-end.bats` (5, green).
2. **`0eed887`** `feat(claude-latest)` — per-session stderr capture (crash-mechanism forensics).
   Tests: `tests/claude-latest-stderr.bats` (4, green).

_(Further fixes — backlog sweep / log rotation / telemetry — appended below as they land.)_

**Deploy notes (deploy-symlink gap):** `hooks/session-end.sh` is a symlink into the checkout → live
on the trunk fast-forward. `bin/claude-latest` is a **real-file copy** in `~/bin` (a `COPY_TOOLS`
entry in `deploy-parity-assert.sh`) → must be `cp`'d / re-`install.sh`'d after landing, then the live
path exercised.

---

## Open decisions surfaced to the operator (not built here)

1. **PRIMARY prevention — cap session SIZE before the per-process ceiling** (reaffirmed from the
   prior doc). Today's auto-recycle fires on context% (`used_pct`), blind to the transcript/RSS bloat
   that precedes the crash. A size trigger (auto-recycle-on-size / a size page / earlier forced
   `/compact`) is a session-lifecycle change on a **live-armed hook** → operator's call. The stderr
   capture now lets us confirm whether size is even the true cause before changing lifecycle
   behavior.
