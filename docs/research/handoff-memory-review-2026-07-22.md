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

2. **RESOLVED — the crashes are a Claude Code VERSION REGRESSION, not per-session bloat/OOM.** An
   8,637-transcript scan across all 4 account roots (axis C) puts the genuine-crash rate at
   **0.02% on 2.1.183 → 4.76% on 2.1.207 → 1.56% on 2.1.215** (regression onset ~July 11),
   **100/100 dying mid-`Bash` tool-call** (the `tool_result` never arrives), median transcript
   **1.27 MB** — small. This **dissolves the 520 MB-RSS puzzle: it was never an OOM** (jetsam never
   takes `claude.exe`; `mem_free` ~87% at crash time). It also explains the operator's paradox —
   100%-context sessions on 2.1.183 never crashed; low-context sessions on 2.1.207+ do. **The
   primary prevention lever is the CC binary version, not session size** (see operator decisions).
   The stderr capture will name the exact 2.1.215 fault on the next event; the ledger now records
   `claude_version` so the regression is one grep.

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

## Part 4 — `/handoff` mechanism audit (axis A) — NOT the OOM culprit

Adversarially verified (12/13 A/B findings CONFIRMED; B5 REFUTED). The handoff path is well-behaved
and does **not** retain memory in the CC node process:

- **A3 (confirmed):** every handoff-spawned watcher is **bounded + self-terminating** — `detach()`
  uses `start_new_session=True` so watchers survive the `/exit` group-SIGKILL by design, but each
  exits on its own (`__selfclose` ≤180 s, `__recycle` ≤600 s; `cc-await-ping` is foreground with a
  1800 s timeout + `trap … EXIT` watchfile cleanup). No leaking daemon, no fd leak.
- **A4 (confirmed):** the self-close / `--recycle` common path types a foreground `/exit` →
  SessionEnd runs → (post-root-fix) the pidfile is removed cleanly. `classify_death` remains needed
  only for genuine OOM + the rare 180 s-hung force-close fallback.
- **A1/A2/A6 (confirmed, FIXED):** per-fire `/tmp` litter (`handoff-selfclose-*.log`,
  `handoff-recycle-*`, `handoff-prompt-nb-*`; ~740 in 5 d, ~80 % test-fixture) had **no reaper** —
  now age-swept by the session-end straggler pass (`b2e8e1f`).
- **A5 (confirmed, SURFACED):** dead-pane `mailbox/*.md` inboxes (73 files, largest 208 KB) are
  append-only with a read-cursor, never GC'd. Safe fix is age/dead-pane GC — **not** `.acked`-based
  (that cursor is a line count; deleting on it loses unread mail — the B4 verify caught this).

**Bottom line: axis A is not the RSS-OOM source.** The crash lives in the CC binary (Part 5).

## Part 5 — Genuine-crash isolation (axis C) — the version regression

A Python classifier scanned all **8,637** transcripts across the 4 account roots (realpath-deduped),
classifying each end clean vs abnormal (last record an assistant `tool_use` with no matching
`tool_result`; api-error records; abrupt EOF), then version-normalized the abnormal rate.

- **7,662 clean ends; ~100 genuine abnormal in-process deaths** over the 30-day window.
- **The dominant factor is a CC version regression, not size or memory:**

  | version | active | crash rate |
  |---|---|---|
  | 2.1.183 | 06-22…07-11 | **0.02 %** (1/5170) — safe |
  | 2.1.207 | 07-11…07-22 | **4.76 %** (80/1682) |
  | 2.1.215 | 07-19…now | **1.56 %** (19/1220, ~6/day — still broken) |

- **100/100 died mid-`Bash`** (Read/Edit/Grep finish in ms and never truncate; only Bash holds the
  death-window open). 0/100 interrupt markers, 0/100 sidechains, **median 1.27 MB**.
- **Jetsam-correlation zero** — 2 JetsamEvents in the window, both `qemu`, never `claude.exe`;
  `mem_free` ~87 % at crash time. Not an OS memory kill, not an OOM.

This is the operator's "crash to shell," and it is **version-caused**. The stderr capture (`0eed887`)
will name the exact 2.1.215 fault on the next event.

**Live corroboration + a second false-positive class.** The ledger gained **16 CRASH rows in a 6-min
window tonight** (`n_claude` 9→0, `mem_free` 87 %). These are **not** the regression (which spreads
over days) — the frontier (Part 7) identified them as **workflow subagents completing**: an agent
runs the full watchdog at SessionStart but never fires SessionEnd, so its pidfile persists and the
daemon logs a false CRASH. A distinct false-positive class the SessionEnd root fix cannot cover —
surfaced below.

## Part 6 — Telemetry (concise, zero-bloat) — SHIPPED

Two structured lines, both self-bounded, no per-turn cost (written only on a fire or a death):

- **Per-crash** — extend the existing `claude-crashes.jsonl` (do NOT fork): `handle_crash` now
  records **`claude_version`** (the decisive regression signal) + **`stderr_log`** (joins the crash
  to the launcher's captured stderr by pid). `cc-crash-report` renders a **crash-by-version
  histogram** + version per row. Readers tolerate the additive keys — zero reader change. (`4d7dd2f`)
- **Per-handoff** — new `~/.claude/logs/handoffs.jsonl`, one line per real fire
  (`ts, firing_sid, class, engaged, target_pane, account, firing_rss_kb`), self-bounded to 500.
  (`9d722fb`)

One-grep answers: *did THIS handoff engage?* `grep '"firing_sid":"<sid>"' handoffs.jsonl`; *crash —
why + what version?* `grep '"class":"CRASH"' claude-crashes.jsonl | jq '[.ts,.claude_version,.cause,.stderr_log]'`;
*the regression* → `cc-crash-report`'s histogram. Bloat: ~190 B/handoff-line, ~230 B/crash-line;
0–600 B per session, usually one line or zero.

## Part 7 — Frontier (Fable) unknown-unknowns — the delta above Opus

The bounded Fable derivation panel found watchdog-subsystem defects the Opus audit + verify missed.
**Fixed here** (safe, small, verified):

- **rm-race disarm (critical, confirmed — 125 instances) → FIXED (`4d7dd2f`):** `handle_crash`
  deleted `<sid>.pid` without checking it still held its own pid; a resume/re-fire overwrites it with
  the successor's live pid → deletion silently disarms a LIVE session. Now guarded.
- **`/clear` regression in the root fix (confirmed on the reaper side) → FIXED (`b2e8e1f`):**
  SessionEnd also fires on `/clear` while the process survives; removing the pidfile flips
  `team-orphan-reaper` to "lead dead" and could archive a live team. Now skipped on `reason=clear`.

**Surfaced (larger / riskier — the clean solution is ONE campaign, not point-fixes):**

- **Watchdog daemon stacking (high, confirmed):** SessionStart is source-blind + spawn-unguarded →
  `/clear`//compact//resume stack N daemons per process (3262 spawns vs 3098 sids); all N fire at
  death → N duplicate crash records + **N racing jq inbox rewrites = lost-message races**. Needs a
  per-sid spawn guard / single-instance lock.
- **Subagent false-crashes (high, confirmed):** agents run the full watchdog but never fire
  SessionEnd → every completing subagent writes a false CRASH + Basso (tonight's 16-cluster). Fix:
  the watchdog should not arm for agent invocations (detect `--agent-id` / `isSidechain`).
- **`idl.jsonl` rotation deadlock (high, confirmed):** the 72 MB / 370 K-line audit log's
  `rotate-autonomy-logs.sh` has zero callers AND `cc-idl`'s hash-seal chain makes rotation
  tamper-fault — a design conflict (rotation must become a seal-chain epoch).
- **Others:** `cc-reaper` has no single-instance lock (concurrent sweeps race); `session-index`
  re-parses active transcripts in full every 60 s (O(size²), only 1 of 4 roots); `refs/checkpoints`
  grows unbounded (1842 refs, no pruner); a SessionStart mailbox-drain can inject a stranded 200 KB+
  inbox as one `additionalContext` blob — a candidate **context-spike-at-birth** (the operator's
  "leak/spike," adjacent to the version regression).
- **Campaign candidate (`/frontier-campaign`):** a **registered-state-family contract** — every
  producer of per-session/-event files or refs registers `(glob, key-epoch, TTL, owner)` in one
  manifest enforced by ONE sweeper — dissolves cp-count / nudge-count / watchdog / mailbox / refs GC
  **and** the idl deadlock as no-ops. Every leak here is the same defect: keyed state minted with no
  enumerated owner/TTL.

---

## Fixes shipped (this branch — `feat/handoff-memory-review`)

| commit | change | tests |
|---|---|---|
| `b026894` | `session-end` clean-exit watchdog + checkpoint reap (root fix for the 93 % false signal) | session-end.bats |
| `0eed887` | `claude-latest` per-session stderr capture (crash forensics) | claude-latest-stderr.bats |
| `b2e8e1f` | `session-end` straggler/backlog GC + `/clear` regression guard | session-end.bats |
| `4d7dd2f` | `lead-crash-watchdog` `claude_version`+`stderr_log` telemetry + rm-race guard; `cc-crash-report` version histogram | lead-crash-watchdog.bats |
| `7dd2ccf` | `.fired` latch-set GC (completion-assert + anti-deference) | — |
| `9d722fb` | `handoff-fire` per-handoff telemetry line | — |

All gated: `bash -n` + `shellcheck` clean on new code, 21 bats green.

**Deploy (deploy-symlink gap):** `hooks/*` + `bin/cc-crash-report` are symlinks into the checkout →
live on the trunk fast-forward. `bin/claude-latest` is a **real-file copy** in `~/bin` (a
`deploy-parity-assert.sh` COPY_TOOL) → must be `cp`'d after landing, then exercised. New log files
(`handoffs.jsonl`, `logs/stderr/`) are created on first write.

**Deploy notes (deploy-symlink gap):** `hooks/session-end.sh` is a symlink into the checkout → live
on the trunk fast-forward. `bin/claude-latest` is a **real-file copy** in `~/bin` (a `COPY_TOOLS`
entry in `deploy-parity-assert.sh`) → must be `cp`'d / re-`install.sh`'d after landing, then the live
path exercised.

---

## Open decisions surfaced to the operator (not built here)

1. **PRIMARY — pin / hold the CC binary version.** The crashes are a **2.1.207+ regression**
   (Part 5), so the decisive lever is the binary, not session size. `claude-next*` already pin the
   safe **2.1.183**; the interactive `claude` → `claude-latest` **auto-updates to the broken
   2.1.215**. Options: pin `claude-latest` to 2.1.183 (`CLAUDE_SKIP_UPDATE=1` + point
   `~/.claude-versions/current` at 2.1.183) until a fixed release, or hold upgrades past 2.1.207. A
   toolchain decision → operator's call; the stderr capture will hand Anthropic the exact fault.
2. **Watchdog subsystem redesign** — the frontier's registered-state-family campaign (Part 7):
   promote via `/frontier-campaign`. Subsumes the stacking / subagent-arming / idl-deadlock /
   mailbox-GC / refs-pruning items into one supervised, identity-pinned sweeper.
3. **Log-rotation activation (C10):** `launchd/com.claude.log-rotation.plist` exists but is
   **unloaded** and `rotate-autonomy-logs.sh` has zero callers. `launchctl load` it + broaden
   `DEFAULT_TARGETS` to the 9 unrotated logs (safe for 7; 2 hold persistent fds — copytruncate them).
4. **Size-recycle (from the prior doc)** — now **secondary** to the version pin; keep as
   defense-in-depth, still an operator lifecycle decision.
