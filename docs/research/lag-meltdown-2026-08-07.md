# The load-781 meltdown — root cause + fixes (2026-08-07)

**Measured state at 15:45** (10-core M1 Max, 64GB): load `781 / 683 / 474` · 3,599 processes ·
free RAM ~60MB · swap 3.9/5GB · 179 ptys (`who`) · 341 zombies. The machine felt seconds-per-
keystroke laggy. Memory-pressure level still read 1 (normal) — the lag was run-queue + swap
churn, not a jetsam storm.

## Where the load actually was

| population | count | evidence |
|---|---|---|
| `ps` processes | **1,146** (959 orphaned to launchd) | ~288% CPU aggregate — the single largest consumer |
| zsh shells | 497 (299 orphaned interactive `-zsh`) | dead panes' shells surviving pane death |
| bash | 395 — incl. **59 `cc-close-attrib` wrappers vs 16 live claude binaries**, 49 `lead-crash-watchdog`, 22 `cc-pane-runner`, 18 `session-register.sh` | residue of dead sessions |
| claude.exe | **16** live, 7.2GB RSS | the actual fleet is small |
| terminal ownership | kitty (pid 567, up since boot): 1,053 descendants, 17.5GB, 174/179 logins, 153 panes · iTerm2: 24 descendants, 6 sessions, **launched 03:51:18 today** | kitty is the fleet home; iTerm2 was resurrected |

The dominant `ps` fingerprint (308 live at snapshot, `ps -A -o pid= -o ppid=`) is **Claude Code's
own internal liveness poll** — not repo code (grep proves absence). Under load each full-table
walk takes 10-20s, polls overlap (one session held 17 concurrent), and dead sessions orphan
their in-flight walks to launchd where they keep running. `ps aux` ×20 concurrent came from
lead-crash-watchdog's crash-path probe (49 daemons × full-table walk, 5s bound unreachable
under load). tmux-resurrect added 3 overlapping `save.sh` sweeps.

## The amplification loop (why it snowballs instead of settling)

1. Sessions die (OOM/teardown) → their hook shells, `ps` walks, and interactive zsh **orphan to
   launchd and keep running**; their `cc-close-attrib` wrapper lingers (see below) pinning a
   `tee` and the pipeline's zombies.
2. Every orphan `ps` walk slows every other walk (kernel proc-table contention) → walks overlap
   more → run queue grows.
3. **cc-reaper — the relief mechanism — is disabled by the load it should relieve**: its
   classify phase bound-fires at 90s → *"sweep yields NO candidates (fail-closed)"* on every
   sweep → panes/sessions accumulate (153 kitty panes) → more load. The `bound-must-fit-the-band`
   class, on the machine's own immune system.
4. Meanwhile a worker wave for backlog item `149789b69fc4` spawned ~25 panes in 10 minutes
   (panes 650→674, spawn log), each 400-500MB when its claude boots — under memory exhaustion
   workers die/stall, the item requeues, more panes spawn.

## Why sessions "fire off in iTerm2 instead of Kitty"

Terminal dispatch was **env-inheritance sampling**: `[ -n "$KITTY_WINDOW_ID" ] → kitty, else
iTerm2`. Correct inside panes; **structurally wrong under launchd** (lr-reset-poller,
boot-resume), which carries no terminal env — so every *autonomous* spawn fell to the iTerm2
arm. `scripts/boot-resume-launch.sh:250` then ran the one unguarded spell: **`open -a iTerm`**
— which *launches* the app. That is the 03:51:18 resurrection with 6 sessions fired into a
terminal the operator abandoned. (All handoff-fire/lr-handoff iTerm2 references were already
`is running`-guarded; this was the remaining launcher.)

## What shipped (branch `fix/lag-relief`)

1. **`bin/cc-close-attrib` — the wrapper leak.** The `2> >(tee …)` procsub's stdin is the
   session's fd2, inherited by every process the session ever backgrounded ⇒ one surviving
   orphan keeps tee EOF-less and the wrapper waits forever (43 of 59 wrappers, S+ up to 10h).
   A procsub's pid is *unreachable* (forks under the exec'd brace-group; `$!` after
   `exec 9> >(tee…)` names the previous job — both measured). Rebuilt the capture as an
   explicit FIFO + ordinary `tee … &` job (unambiguous `$!`), exact-pid TERM after
   `write_record`. Repro: bats-shaped pipe capture went **25s → 0s**; full 17-test suite green.
2. **`bin/cc-reaper garbage` — the residue finally has an owner.** New arm, run FIRST in every
   sweep (cheap: 2 `ps` forks + awk) and standalone via `cc-reaper garbage [--reap]`: orphan
   `ps`/leaf-tools, orphaned interactive shells, stuck close-attrib wrappers, dead-lead
   watchdog daemons. Kill discipline: one snapshot, per-pid ucomm re-verification, TERM→KILL,
   never a pattern-kill, never a claude binary / kitty / tmux / whitelisted daemon / anything
   with a live claude in its subtree. Fail-open, `CC_REAPER_GARBAGE=0` kill switch, fixture
   seams for tests (6 tests).
3. **`cc-reaper` classify bound-fire → one retry at 3×** before failing closed — the sweep can
   again produce verdicts on a loaded box (test: bound fires at 1s, retry completes).
4. **`bin/cc-kitty-socket` + daemon-context dispatch.** The resolver verifies a LIVE kitty by
   its control socket (`/tmp/kitty-<pid>` + comm check; oldest instance wins) — a live detector
   replacing env sampling for the absent-env case only (env still wins when present).
   `boot-resume-launch.sh` and `lr-handoff.sh` consume it via `CC_TERM_KITTY_TO` (it2-kitty's
   documented explicit-intent channel); lr-handoff's existing os-window fallback fires with no
   invoking pane. **`open -a iTerm` is deleted**; the iTerm2 arm now requires the app already
   running (`is running` probe, the one reference that never launches) → rc 3 to callers'
   existing deferred/queue fallbacks. 9 + 2 new tests, hermetic (fixtured socket dir + ps).
5. **`lead-crash-watchdog.sh` probe**: `ps aux | grep -c` → `pgrep -x` (comm-exact, ms, can
   never match a brief in argv).

## What this does NOT fix (named, filed)

- **The standing pile from before the fixes** — drains autonomously on upcoming
  `cc-reaper sweep --reap` cadences once live; the operator can force it immediately with
  `cc-reaper garbage --reap` (backlog `needs` updated to the sanctioned command).
- **Spawn admission for it2-kitty splits** (the 25-panes-in-10-min runaway): boot-resume is
  gated by `capacity-admit.sh`, worker-wave splits are not — filed.
- **agent-browser daemon accumulation** (42 at census) — filed.
- **CC-internal `ps -A` polls**: harness-owned, not patchable here; shrinking session count +
  load is the lever.
- **kitty config**: already correct for this fleet (scrollback 2000, `repaint_delay 16`,
  `input_delay 5`, socket-only remote control). kitty itself held 130MB for 153 panes — the
  terminal is not the memory story; the residue was.
