# Load re-investigation — 2026-10-17 evening (20:13-20:24 CDT)

Scope (frozen): measure and attribute the machine load as it is NOW, say what is new versus the
2026-10-17 morning findings (`docs/research/load-root-cause-2026-10-17/DESIGN.md`), apply every
immediate fix that removes work without throttling, demoting, capping, killing session work or
reducing sessions, and report findings plus what was applied; operator-only steps go in one /tmp
script.

## Answer

The load (515 at 20:13, 438 at 20:24, on 10 cores, 0% idle) is **real, deliberate work, not waste**.
**About 62-75% of all CPU is the TrueMemory tm2 build team** (session `ad2417e7`, teammates tm2-C1,
tm2-E4 and tm2-B2-2) running three verification matrices at once. Nothing that the morning fixed has
regressed, and no leaked or duplicated work big enough to matter was found. So **no immediate fix
qualified**: every remaining lever would slow a live session's work, which the brief rules out. The
one removable leftover (two orphaned headless Chrome trees, ~371 MB, 0% CPU) is the operator's
script below.

## Measured state

| Reading | 20:13 | 20:24 |
|---|---|---|
| load (1/5/15 min) | 515 / 434 / 375 | 438 / 454 / 424 |
| CPU user / sys / idle | 59 / 41 / 0 % | 64 / 36 / 0 % |
| RAM unused / compressor | 332 MB / 5.1 GB | 5.2 GB / 6.0 GB |
| swap used (of 10 GB) | 8.8 GB | 8.6 GB |
| fork rate (pid-counter delta, 25 s) | 352 /s | — |
| `memory_pressure` free | 49 % | — |
| paging (25 s) | ~12k compressions/s, ~1k pageins/s, 0 swapouts/s | — |

## Attribution (interval CPU including reaped children)

Instrument: `rusage-attrib.py` beside this file (proc_pid_rusage flavor 2, self + reaped-children CPU
delta per process, grouped by ancestor argv). It fixes the method gap that `top` and `ps` both have
here: top's per-process sum covered only ~324% of the 1000% in use, because most of the CPU goes to
processes that live for under a second. Caveats: uid-501 processes only; a process that exits during
the window can double-count its pre-window time into its parent, so totals overshoot 1000% (1147% in
run 1, 1724% in run 2). Rankings were stable across both runs; shares are of the attributed total.

| Group | Run 1 share | What it is |
|---|---|---|
| TrueMemory tm2 team, all | **62% + 6% (its claude processes and tool shells)** | see next table |
| personal-project session, tool children | 6 % | a shopping-research session driving ~10 named agent-browser sessions |
| agent-context-sync round-14 lane gates | 6 % | `scripts/gate.sh` (the morning's W1-ACS fix is in: r14-d contains 5b1f10f1), serialized by `lockf /tmp/b13-r14-land.lock` |
| claude binaries themselves (all sessions) | ~6-8 % | 37 `claude` + 7 `claude.exe` processes, 11 GB RSS |
| Dia browser | 4 % | one renderer tab at ~25-30 % CPU |
| agent-browser headless Chrome | 2-3 % | 14 Chrome trees, ~10.5 GB RSS |
| everything else | < 1 % each | Hammerspoon, kitty, SystemUIServer, secd, … |

In run 2, ~250% labeled "claude-infrastructure sessions" was in fact TrueMemory teammate work: the
teammates are launched by this repo's `bin/cc-pane-runner`, so their ancestry contains the repo path.
The subtree check confirmed it (219% under tm2-E4's run-all, 91% under tm2-B2-2's gate).

TrueMemory breakdown (run 2):

| Workload | Share | Shape |
|---|---|---|
| hostmatrix (`.tools/hostmatrix/hm.py 597c0d7 fb166ff`, tm2-C1) | 38 % | `--jobs 10` cells; each cell runs install, install2, uninstall, repair, repair2 as separate `truememory-ingest` Python processes (1-20 s each, 130-250 MB) — the short-lived processes top cannot see |
| corpus run-all (`.tools/mc/run-all.sh --legs skew`, tm2-E4) | 16 % | 7 × `python3.12` workers at ~1.4 GB each (~10 GB RAM), one embedding model per worker, plus `inspect` probes at 370-510 MB |
| gate (`.tools/gate.py`, tm2-B2-2) | ~5 % | three `pytest tests/` legs, one per Python version venv (not duplicates) |

## What is new versus the morning

- **Morning cause is gone.** Then: four concurrent agent-context-sync `pytest -n auto` gates times
  per-test waste plus a 12-13 GB fseventsd. Now: agent-context-sync is ~6% and serialized; fseventsd
  is 6-9 MB RSS (pid 96656) at ~5% CPU; the fork rate halved (730/s at load 45-50, now 352/s at
  load ~500).
- **New dominant source:** the TrueMemory tm2 build wave (above). At 13:30 it was one hostmatrix run;
  now three teammates run hostmatrix, the corpus run and the gate concurrently.
- **New memory axis:** swap is 8.6-8.8 of 10 GB. The largest RSS holders are claude processes
  (11 GB), agent-browser Chrome (10.5 GB), the TrueMemory corpus workers (~10 GB), kitty (3.1 GB) and
  WindowServer (2 GB). `memory_pressure` still reports 49% free and swapouts are 0/s, so the
  compressor is absorbing it. This adds kernel CPU (kernel_task ~49%), but it is not paging the
  machine to a halt.
- syspolicyd at ~16%: its log shows per-exec provenance checks, so it scales with the exec rate (the
  short-lived TrueMemory processes). There is no separate lever.

## Candidates checked and why each was not applied

| Candidate | Measurement | Verdict |
|---|---|---|
| Compact the regrown `xcrun_db` | 712 KB (was 91 MB in the morning, compacted to 870 B) | negligible; no work removed |
| fseventsd regrowth | 6-9 MB RSS | healthy |
| agent-browser idle Chromes | `AGENT_BROWSER_IDLE_TIMEOUT_MS=1800000` is already in `~/.claude/settings.json`; every live daemon is under 25 min old | already handled; a shorter timeout would cost a live session its page state |
| Leaked crash watchdogs (39 `lead-crash-watchdog.sh` processes, morning 28) | 40/40 pidfiles in `~/.claude/watchdog` point at live leads | not leaked: one per live session |
| Duplicate TrueMemory work | gate.py legs are three different venvs; hm.py's `install2`/`repair2` are deliberate idempotence checks; bytecode caching is on in the sandbox | not duplicates; cutting `--jobs` is throttling |
| agent-context-sync gates | on `scripts/gate.sh`, serialized by a land lock | already fixed; the shared pool is W6 (backlog 75b041426dba) |
| **Two orphaned headless Chrome trees** (pids 22415 and 41102, reparented to launchd, 1 day and 5.8 days old, ~371 MB, 0% CPU) | no daemon owns them, so the idle timeout cannot reach them | **removable — operator script** |

## Fixes applied

None. No candidate removed work at equal or better wall time without touching a live session's
processes or slowing its work.

## Operator step

`/tmp/load-reinvestigate-orphan-chrome.sh` — a bare run lists the targets; `--confirm orphan-chromes`
stops only agent-browser Chrome main processes that have no daemon (ppid 1) and are over 1 h old, then
verifies by a fresh `ps` read that they are gone. Re-runnable; a second run reports `none-found`.
Gain: ~371 MB RSS. Load effect: none (0% CPU).

## If the load needs to come down further

Only the TrueMemory team's own concurrency would move it materially (hostmatrix `--jobs`, mc
`--jobs`, three heavy teammates at once). That is throttling, which is the operator's or that team's
lead's call, not an immediate fix.
