---
status: in-progress
---

# Load reduction and UserPromptSubmit hook timeouts (2026-10-11)

Scope (frozen): stop the UserPromptSubmit hook timeouts at their root, restore the claude-accounts board `live` column, surface the 5h reset time on the board when 5h >= 80%, and reduce machine load — never by killing or pausing session work. Delivered as Wave 1 (WP1-WP6) landed + converged, WP7 sent to its branch owner, operator steps O1-O6 filed.

Design and evidence: `docs/research/load-hook-timeouts-2026-10-11/DESIGN.md` (ranked items, file:line sites, verify recipes; `<\task-notification>` there means the literal `<task-notification>` tag), `investigations.json` (6 verified investigations, adversarial verdicts), `census-prototype.py` (KERN_PROCARGS2 census, 0.16 s for 41 procs at load ~480 where `ps -wwEo` never finished).

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave:** Wave 1 = **L+Workflow** — the operator invoked ultracode, so the recycled lead runs one Workflow with one `isolation: 'worktree'` code-writing slot per WP (default agent, not workflow-lean), then lands the branches itself one at a time. Wave 2/3 = **S** (dispatched handoff sessions), only after Wave 1 is converged and O5's exec trace has run.
- **Lead context budget:** keep ≥50% free; the lead only reviews diffs, lands, converges and files. Succession point: after Wave 1 converges, or at 60% fill, whichever is first.
- **Load etiquette for every slot (machine at load ~400-600):** run only the bats files your WP names, never the full suite; no `ps -A`/`ps -ax` in new code; never kill/signal anything.

## Root cause (one paragraph)

All hooks of one event run in parallel, so a prompt waits on the slowest. 3 of 7 prompt hooks cause all 162 cancels in 40 min: `handoff-intent-nudge` (95) runs a full-table argv `ps -axo pid=,ppid=,command=` (via `hooks/lib/agent-identity.sh:51` `agent_is_assignee`) BEFORE its cheap intent grep; measured 559 s once during a `ps` wave. `mailbox-drain` (39) and `memory-nudge` (28) are fork-heavy (40-75 forks/prompt). The same full-table walk underlies the Stop-hook cancels (~1,130 of 1,490). Full-table `ps` comes in waves where it blocks uninterruptibly for minutes (Claude Code 2.1.293 itself spawns `ps -A` and leaves timed-out children; 224 orphans under launchd seen), while `pgrep` (sysmond XPC) and single-pid `ps -p` stay fast. The board's `live ?` is the same: `concurrency()` `ps -wwEo` times out every sweep since 01:04 UTC; `subprocess.run` then blocks on the stuck child, and `heal()` refuses token refreshes too (login risk). Steady load (~370-400) is runnable work + ~29k spawns/min, not the `ps` pile; hooks are ~20-24% of spawns, ~21k/min are unattributed (O5).

## Wave 1 — work packages (disjoint files; full detail in DESIGN.md "Ranked items")

| WP | Files owned | Item | Status |
|---|---|---|---|
| WP1 | `hooks/handoff-intent-nudge.sh`, `tests/handoff-intent-nudge-fastpath.bats` (new) | jq parse; exit on `<task-notification>` prompts; intent grep BEFORE assignee check | **DONE** `a52745362` `faff4ae23` — live; 10/10 on trunk |
| WP2 | `hooks/lib/agent-identity.sh`, `hooks/teammate-auto-shutdown.sh`, `tests/agent-identity-walk.bats` (new) | per-hop `ps -o … -p` ancestry walk feeding the unchanged awk; seam `CC_WF_PSTABLE_FILE` unchanged | **DONE** `51a821560` `f6495d5b6` — live; 14/14 on trunk; no early stop (nested `claude -p` under a teammate still reads as the teammate) |
| WP3 | `hooks/memory-nudge.sh`, `hooks/lib/episodic_cue.sh`, `hooks/lib/idl-log.sh`, `scripts/idl-expected-fires.tsv`, `tests/memory-nudge-*.bats` | due-check first; `-nt` caches; daily prune; ≤15 forks on a non-due prompt | **DONE** `943d94638` — live; non-due prompt 39 → 4-7 external calls |
| WP4 | `hooks/mailbox-drain.sh`, `hooks/lib/mailbox-pending.sh`, `hooks/lib/goal-state.sh`, `tests/mailbox-drain.bats` | one jq parse; skip ancestry walk when alias current; incremental goal scan | **DONE** `dc11e310b` `c3b3d0bd5` `935a85bf1` `827b93fb1` `de5ce4dd1` — live; 4 review rounds (COUNT ONCE vs rotation check, mid-line offset straddle, below-floor stale cache) |
| WP5 | `bin/claude-accounts`, `scripts/lib/claude_census.py` (new), `tests/account-fact-derivation.bats`, `tests/claude-accounts-core.bats`, `tests/accounts-board.bats` | (C) KERN_PROCARGS2 census replaces `ps -wwEo` at :697, Popen+kill-never-wait; (D) `; resets in 1h 12m` on the ▲ line (:7225) and out-of-5h sentence, plus `△` line for 80% ≤ 5h < 85% (`router.S_RESET_SHOW`) | **(C) DROPPED** — superseded by the accounts-freshness native census (`988eb2107`, bounded reap `030f021a1`, `census:"ab"`), which already restored non-null `k` on all 4 accounts; our findings sent to pane 297, branch `load-wp5` not landed. **(D) DONE** `5e2a32bfb` — live. `scripts/lib/claude_census.py` therefore does not exist |
| WP6 | `hooks/research-precognition-nudge.sh`, `hooks/handed-off-session-guard.sh`, `hooks/session-beat.sh` + their bats | drop python3 starts; session-beat self-detaches | **DONE** `de69938a4` `a646160d2` `0d2be4405` `400b15ec4` — live; only the PROMPT beat detaches (stop and limited stay synchronous for cc-await-ping's arm baseline and stop-failure-marker) |
| WP7 | branch `lr-poller-decisions` (owner session holds it) | evidence-gc leak: `LR_EVIDENCE_GC=off` in tests, live-path guard, `taskpolicy -c utility` | **SENT** to pane 303; owner landed the live-path gate, single-flight and utility band in `b4d609a80`; declined items 1 and 5 (unreachable behind the live-path gate) |

Wave 1 landing notes (2026-10-12): Workflow worktree slots start at origin/main, not the lead's branch (first run burned at the base check). Two pre-existing trunk issues surfaced and were fixed in-wave: `tests/memory-nudge-forks.bats` SC2155 (bats-shellcheck gate) and `tests/lr-autorecover-drill.bats` stale since `d30f1f3ad` (`f122d1739`). Cancel check: baseline 23 UserPromptSubmit cancels / 30 min (03:56-04:26Z, 70 transcripts: 15 handoff-intent-nudge, 5 mailbox-drain, 3 memory-nudge); counter `/tmp/wf-load-lead/count-cancels.py <minutes>`. Post-converge (all six live): 0 cancels 09:25-09:56Z over 15 transcripts — but at load ~22-25, not the baseline's 400-600, so this is not a controlled comparison; re-count during the next high-load period before calling the timeouts gone. claude-accounts cache: non-null `k` on all 4 accounts (1/1/18/1, native agrees), 09:28Z.

## Wave 2/3 (after Wave 1; S locus)

WP8 other `ps -wwEo` consumers → shared census (`tools/auth/auth-timeseries.sh:58`, `bin/cc-relogin`, `bin/cc-reaper`, `scripts/supervisor-e2e.sh`); WP9 cc-bats bounded queue replaces waivable refusal; WP10 migration for O1/O3; WP11 lead-crash-watchdog → one kqueue watcher; WP12 foreground-run-queue load signal for gates. Gate WP11/WP12 on O5. **O5 ANSWERED (2026-10-12):** hooks are ≈3–5% of execs; ≈84% is agent-context-sync test runs in its `b13/r5-*` worktrees and 7.4% was postland-verify's per-file `head` (fixed) — so WP11 and the hook-consolidation half of item 12 stay parked (docs/research/load-hook-timeouts-2026-10-11/O5-EXEC-TRACE.md).

Wave 2 outcome (2026-10-12, dispatched session for backlog item 55f0aafea981; two teammates):

| WP | Status |
|---|---|
| WP8 | **DONE** `a0c09994c` `bae21a7ad`. The "shared census" premise was dropped with WP5 (C), so no module exists to move to; the native census is still in-file in `bin/claude-accounts` and still in A/B soak. Of the four sites only two were unbounded: `auth-timeseries.sh` now takes ONE bounded snapshot per batch (was 5 unbounded walks), never waits on a stuck `ps`, writes `n_live: null` (not 0) when it has no census, and skips a batch while the previous run is alive; `cc-relogin` `live_sessions` joins `ps` on a daemon thread at 15 s and returns -1 (fail closed). `cc-reaper` was already bounded (`_rp_bounded`, 30 s); `supervisor-e2e.sh` has no full-table `ps`. Tests: auth-timeseries-schedule + cc-relogin 96/96. |
| WP9 | **DECISION** `b74c6368bbdb` (class C, conviction 65 for building it): a waiting queue reverses `bin/cc-bats`'s recorded R1 rule ("a shedder that waits amplifies"), while the refusal it would replace is bypassed 170-430 times a day (`~/.claude/state/bats-waivers.jsonl`, 10-09..10-12). Not built. |
| WP10 | **DONE** `870767fe8` (0064: `timeout: 5` on handed-off-session-guard.sh + `PYTEST_XDIST_AUTO_NUM_WORKERS=3`, c10, `--confirm settings.json`) · `f01b9c595` (0065: session-search-sweep `SESSION_INDEX_SWEEP_MIN_INTERVAL_S=300` in its plist env, public-publish 10800 → 86400 s plus `fleet.manifest`, c10 reload `--confirm launchd`). Precedent `7820cd375` (0055) for repo plist edits plus a c10 reload. `install.sh` reloads a changed `run` plist at converge, so O3 likely takes effect on the converge; 0065 `--verify` reads it back. |
| WP11/WP12 | Gated on O5 (`1fa5c54f8b87`, needs sudo). Not started. |

## Operator-only (file with cc-backlog / cc-decide; never edit settings.json or plists)

O1 `timeout: 5` on `handed-off-session-guard.sh` + `PYTEST_XDIST_AUTO_NUM_WORKERS=3` (migration, c10) · O2 decision: `CC_SENTINEL_KILL=off` for compressor-sentinel (128 SIGKILLs since 10-07 conflict with "never kill work"; recommend off, 75%) · O3 plist throttles (session-index sweep 60 s → 300 s; public-publish daily) · O4 Claude Code upgrade via cc-upgrade + upstream report on the `ps -A` child leak · O5 30 s `eslogger exec` trace to attribute ~21k spawns/min · O6 optional cleanup of non-work orphans.

Filed 2026-10-11: O1 `4ae1c7d77e2b` · O2 decision `f3d6b2b1a2b9` (class C, conviction 75; CORRECTED (2026-10-12): superseded by `5bb842d8a406`, recommendation reversed to KEEP the kill rung at 88% — it is the guard added after SIGSTOP alone failed to prevent panic #5, docs/research/panic-2026-08-24-fifth-watchdog.md; pair with O1's worker cap). RULED (2026-10-12, operator): keep the kill rung — no config change; `5bb842d8a406` actioned · O3 `73ea54aec513` · O4 `c2aa7ab8be97` · O5 `1fa5c54f8b87` (runs `bash /tmp/loadinv/o5-exec-trace.sh`) · O6 `ad60ef86e98e`. WP7 sent to pane 303 (`lr-poller-decisions-303`) via cc-notify, delivered unread at send time.

## Already done this session (2026-10-11)

- Blender headless launch-film render (pid 12507, Cycles 128 spp, frames 1-1500, `use_overwrite=False`) moved to the background QoS band with `taskpolicy -b -p 12507` at the operator's request: PRI 31 → 4, still rendering on spare E-core capacity; load 1-min fell ~600 → ~400. Irreversible in place (restart resumes at the last frame). Memory (17-18 GB) cannot be capped live.

## Rejected (why in DESIGN.md)

`ps` shim on PATH for Claude Code; blanket `taskpolicy -c background` (background band starves at saturation — use `utility` for must-finish work); load-threshold early exits; `async: true` for heavy hooks; new precompute daemons.
