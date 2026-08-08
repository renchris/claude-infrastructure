# Resource guard for runaway agent-spawned commands — the ceiling that exists, and the fork resolved

**Backlog** `2af4c4908422`. **Generating incident** 2026-08-02. **Measured** 2026-08-08 on Darwin
24.6.0, uid 501. **Doctrinal home** `docs/plans/MACHINE_CAPACITY_V2.md:1513-1519` — class "B, single
runaway action in one session", control point "the Bash tool boundary", asking for "a RESOURCE guard
— never a denylist of binary names".

## 1. The fork was mis-posed, and that is the finding

The item left one question open: **notify-only vs kill**. Neither, because both answers assume a
shape this guard does not have.

A notification has exactly one consumer here — the agent that issued the command — and **that agent
is blocked on the very command the notification is about**. It cannot read a page, a log line or a
JSONL row until the command returns. So "notify-only" at the Bash tool boundary is not a softer
option than killing; it degenerates to a post-mortem record, which is precisely what the existing
reapers already produce and precisely what the item says constrains nothing.

And "kill" overstates what happens. Nothing hunts a victim, matches a pattern, or selects a pid.
The wrapper *declares a ceiling before the command starts* and the kernel enforces it. There is no
selector to get wrong, no race, no reaper — which also means none of the reaper-safety machinery
(birth grace, effect-read predicates, `{pid,start-time}` identity, `pkill` scoping) is in play,
because none of its failure modes can occur.

**The resolution: bound the command, and make the RETURN the notification.** The ceiling fires, the
command exits 152, and a parseable verdict lands on stderr where the agent reads it at the only
moment it can act — the moment it is unblocked. `verdict=cpu-ceiling-exceeded limit_cpu_s=60`.

The fork keeps a different answer for the *other* shape — a process already running, observed from
outside. That is `scripts/compressor-sentinel.sh`, and it was already ruled: **SIGSTOP**, because
"a frozen worker is recoverable; a panicked box is not" (`compressor-sentinel.sh:25-35`). Both
shapes now have an answer; they are different answers because the guard sits in different places.

## 2. What macOS actually gives you (measured, with a positive control)

The item's premise — no per-process RSS cap — **holds**, and now has a measurement rather than
folklore behind it. `setrlimit` in one process, 2026-08-08:

| rlimit | set to 512 MB | note |
|---|---|---|
| `RLIMIT_AS` (`ulimit -v`) | **EINVAL** | bash agrees: "cannot modify limit: Invalid argument" |
| `RLIMIT_RSS` (`ulimit -m`) | **EINVAL** | absent from zsh entirely (`bad option: -m`); present but inert in bash |
| `RLIMIT_DATA` | **EINVAL** | |
| `RLIMIT_STACK` | **EINVAL** | |
| `RLIMIT_CPU` (`ulimit -t`) | **SET OK** | |
| `RLIMIT_NOFILE` | SET OK | |
| `RLIMIT_NPROC` | SET OK | |
| `RLIMIT_FSIZE` | SET OK | |

**The 4-of-8 split IS the positive control.** Four limits set fine in the same process, so the
refusal is Darwin's property, not a broken probe. (CPython surfaces the kernel's `EINVAL` as
`ValueError: current limit exceeds maximum limit`, which reads like a bad argument and is not.)

Capping virtual address space would be useless even if it worked: a bare `node` measured
**VSZ 392.4 GB against RSS 37.1 MB**, so any VA ceiling low enough to matter false-kills node at
startup. The item's "394GB" figure is confirmed.

### Correction to an existing doc

`docs/research/panic-compressor-2026-08-05.md:260` states:

> "VA-based rlimits (ulimit -v / HardResourceLimits) ARE enforced on modern xnu — contrary to folklore"

**Refuted for the userspace path.** `ulimit -v` cannot be *set* at all here, so enforcement is moot.
The claim may still hold for launchd's `HardResourceLimits` plist key, which launchd applies as root
at spawn — untested, and irrelevant to bounding a command an agent spawns. That doc's *other* lever,
`memorystatus_control(SET_MEMLIMIT_PROPERTIES)`, is real but needs root and a private header, so it
is not reachable from a wrapper the agent itself invokes.

## 3. Why a CPU ceiling beats a wall clock here

`RLIMIT_CPU` is the one ceiling Darwin honours, and its semantics fit this job better than `timeout`:

- **It bounds compute, not patience.** Measured: `ulimit -t 2; sleep 5` runs the full 5 s and exits
  0. A command slow because it *waits* — network, a lock, a build it did not start — is untouched.
  A wall clock cannot tell that apart from a runaway.
- **It is per-process and inherited, not shared across the tree.** Each process gets its own budget,
  so a long pipeline of many short-lived children is never bounded in aggregate while any single
  runaway is stopped on its own. That is the observed shape exactly: the runaway ugrep sat at
  12m48s of CPU while its parent shell was at **0.0% CPU and 752 KB RSS**.
- **The kernel enforces it.** No poller to schedule, starve or keep alive, and nothing to reap.

Enforcement, measured: `ulimit -t 1` → rc **152** (SIGXCPU) at 1.04 s wall; `ulimit -t 2` → rc 152 at
2.03 s; unbounded control still running at the 3 s sample.

### Two traps, both measured

**Order is load-bearing and fails silently.** The soft limit must be lowered *before* the hard limit.
A hard limit below the current soft limit is `EINVAL`, so `ulimit -H -t N` on a fresh shell (soft =
unlimited) fails and leaves **both unlimited** — printing an error nobody reads. Soft-then-hard
works: `soft=1 hard=4`.

**Declared blind spot: Darwin's hard tier does not deliver SIGKILL.** With `soft=1 hard=3`, a process
that installs `SIG_IGN` for SIGXCPU consumed **12.0 CPU-seconds and reported `SURVIVED`**. So the
enforcing tier is SIGXCPU at the soft limit and nothing else. No member of the shipped table ignores
SIGXCPU (grep/ugrep/rg/ag/ack/find all die on default disposition). The layer that would cover it is
a polling per-pid CPU watchdog — **deliberately not built**, because it costs a permanent poller to
defend against a case with no measured instance.

## 4. Calibration — why 60, and why scoped

Pairing the PreToolUse and PostToolUse bash logs (`~/.claude/logs/bash-{commands,execution}.log*`),
2026-07-30 → 2026-08-08, **56,269 paired agent Bash calls**:

| population | n | > 30 s | > 60 s |
|---|---|---|---|
| ALL agent bash calls | 56,269 | — | **2.611%** (1 in 38) |
| SIMPLE calls (no compound metacharacter) | 4,343 | — | — |
| **SIMPLE + starting with a search binary** | **233** | **0** | **0** |

A 60-second bound on *every* Bash call would fire on 1 in 38 and kill typechecks, bats suites and
ship-land runs. Scoped to simple search commands, **zero of 233 exceeded even thirty seconds**, so
the ceiling sits at better than 2× the widest observed call.

**The compound refusal is what makes that zero real.** A separate survey that classified "pure
search" *without* excluding compounds found 88 calls over 60 s — and on inspection every one was a
pipeline piping a heavy job through grep (`ship-land.sh … ; grep` at 604 s, `eslint … ; grep` at
404 s). `qos-rewrite.sh` has always refused compound lines, so that entire population is excluded by
construction, and the measured rate is 0 rather than 0.67%.

Honest bound: 0/233 gives a 95% upper bound near 1.3% (rule of three), not proof of impossibility.
The cost when it is wrong is one command returning rc 152 with a verdict naming the ceiling and
telling the agent to narrow and retry — recoverable in one turn, against the 12m48s it prevents.

### The incident, corrected in two places

The runaway was **not** a large-corpus scan. It was catastrophic regex backtracking on ONE HTML file
— two bounded classes straddling an alternation, `[^<>{}"]{0,90}(per cover|…|commission)[^<>{}"]{0,90}`
over `/tmp/tock.html` — so no corpus-size heuristic could have predicted it. And the agent typed
`grep`; the interactive shell function rewrote it to `ugrep -G …`.

The item's "all 13 reaper scripts" is a filename count (`ls scripts/ | grep -icE 'gc|reap|clean|orphan|prune'`),
not a census; it reads 16 today. About half are lints, tests, or file/ref janitors. Three do act on
live processes — `bin/cc-reaper`, `scripts/gate-cleanup.sh`, `scripts/compressor-sentinel.sh` — so
"nothing constrains a LIVE one" was already loose when filed. **But the specific hole was real and
survived:** all three key on *identity* (session state, worktree pattern, `comm ~ ^node`), none on
resource consumption, and the sentinel trips on VM-compressor segment rate rather than per-process
cost. A `ugrep` matches none of them.

## 5. What shipped

- **`bin/cc-cpubound`** — `cc-cpubound <cpu_seconds> <command> …`. Sets the soft ceiling then the
  hard one, runs the command, passes its status through verbatim, and on rc 152 emits the parseable
  verdict. Fail-open everywhere: a bad ceiling, or a ceiling the kernel refuses, runs the command
  **unbounded and says so** rather than costing the caller their command.
- **`config/qos-bound.patterns`** — `<cpu_seconds><TAB><ERE>`, three rows at 60: the grep family,
  the ripgrep family, `find`. Widening it is cheap and welcome; the price of a new row is the same
  false-positive measurement, because §4 shows what an uncalibrated ceiling costs.
- **`hooks/qos-rewrite.sh` transform (c)** — the ceiling prefix, alongside the existing demotion
  prefix. **(b) and (c) compose** rather than race: a first-match-wins scheme would have made which
  wrapper survives depend on table read order, a silent order-dependent drop.

It needed no settings.json change and no operator activation: `qos-rewrite.sh` is already registered
in the live PreToolUse(Bash) chain and symlinked into the checkout, so this is live on land — the
`hooks/backup-before-write.sh:40-43` pattern, chosen deliberately over a new hook that would have
become a pending activation nobody runs.

## 6. What was deliberately not built

- **A polling RSS watchdog** (the item's mechanism 2). The machine-wide case already has an owner in
  `compressor-sentinel.sh`; the per-command case is now covered by a kernel ceiling with no poller.
  Building a third watcher to cover the SIGXCPU-ignoring residual would add a permanent process to
  defend a case with zero measured instances.
- **A wall-clock bound at the tool boundary.** §4 measures its false-positive rate at 2.611%. If the
  IO-blocked-forever class ever produces an instance, that is the lever — and it needs its own
  calibration, not this one.
- **A memory ceiling.** §2: there is nothing to call that an unprivileged spawner can reach.
