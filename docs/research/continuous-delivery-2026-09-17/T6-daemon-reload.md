# T6 — the smallest RELIABLE way for a long-lived python daemon here to adopt new code

Repo READ-ONLY. No process signalled, no `kill`/`pkill` run. All timings measured on
`/usr/local/bin/python3` = `/Library/Frameworks/Python.framework/Versions/3.11` 3.11.4,
which is the interpreter the live daemon is actually running (`ps` + `interp` file agree).

## ANSWER (conviction 92%)

**Hash your own source each idle tick; on change, `break` out of the accept loop and let the
existing `finally` retire the daemon. The client respawns it on the next press.**

Two reasons this is the *smallest* reliable thing, and both are facts about this file
rather than preferences:

1. **The repo already shipped this exact cure, for this exact incident.**
   `scripts/lead-supervisor.sh:1329 self_restart_if_stale()` — sha256 its own source each
   tick, ABSTAIN if unreadable, and on change **exit 0** for its supervisor to respawn on the
   new bytes. Its inline why is the same sentence as tonight's: *"the on-disk script changed
   under a daemon that holds the old inode … Without this a landed fix never reaches this
   process and is silent: 10348ff6a landed the permpend escalation ladder at 14:45Z, pid 31716
   started 15:17Z, and 0 of 5,155 IDL records were an escalation."* Test template at
   `tests/lead-supervisor-self-restart.bats` (3 cases: changed⇒exit, unchanged⇒control,
   no-hasher⇒ABSTAIN-and-say-so).
2. **This daemon already retires itself on a timer and already relies on the client to bring
   it back.** `IDLE_EXIT = 6*3600` at `scripts/kitty-pane-title-overlay.py:1152-1153`, whose
   own comment reads *"the next press respawns in ~400ms and this stops holding 31MB"*, and
   the `break` at `:1234`. A source-change check is the **same exit path with a second
   reason** — not a new lifecycle. That is why it is ~8 lines.

### The shape (for the implementer)

- Module level, beside `SOCK`/`STATE` (`:45-51`): `_SELF = os.path.abspath(__file__)`.
- In `daemon()` after the flock is won (`:1131`): `sha0 = _self_sha()`; if it is empty, `_log`
  once that the version assertion is INERT for this process's whole lifetime — lead-supervisor
  does exactly this at its `--daemon` arm, because a fail-safe default that renders like the
  healthy state is unfalsifiable (memory: *fail-safe-default-mimics-the-healthy-state*).
- In the accept loop, **immediately after the `os.kill(kpid, 0)` liveness check at `:1230-1233`
  and beside the IDLE_EXIT break at `:1234`**:

      if not st["on"]:
          cur = _self_sha()                 # "" ⇒ unreadable NOW (mid-rename) ⇒ ABSTAIN
          if cur and sha0 and cur != sha0:
              _log("self-retire: on-disk sha256 changed (%s -> %s); the next press "
                   "respawns on the new bytes" % (sha0[:12], cur[:12]))
              break

- `finally` (`:1273-1287`) already does the whole cleanup: `stop.set()`, no wipe because
  `st["on"]` is False, unlink STATE + SOCK, close srv. **Nothing new to write.**

### `not st["on"]` is load-bearing, not caution

Retiring while the titles are UP costs a visible wipe (`finally: if st["on"]: wipe(...)`,
`:1275-1276`) and unlinks STATE — the operator would watch the bars vanish for no reason. It
would also land in a latent bug: `daemon()` treats `initial=="toggle"` as **on**
(`:1226-1227`) and never consults STATE, unlike `cold()` which does (`:1293`). So gate on
idle. Adoption latency then = *the moment titles go down, +1.0s* (the cold accept timeout,
`:1236`).

### What it costs when it goes wrong

- **A spurious retire** (mtime/content touched with no real change, e.g. a `git checkout` of
  identical bytes): the daemon exits while idle, nothing is on screen, and the next press pays
  the cold path instead of the warm one. Repo's own measured numbers, commit `93c27d492`:
  **warm press 0.07s → cold press 0.33s** (the cold re-warm inside `turn_on()` is ~130ms).
  Invisible to a human.
- **A retire loop** cannot happen here, and this is the one place the kitty daemon is *safer*
  than lead-supervisor: nothing supervises it. `config/kitty.conf:596` (and the DISARMED `:669`)
  are the only spawners and they are key presses, so a file being rewritten repeatedly produces
  **zero** respawns, not a launchd KeepAlive storm.
- **A bad land** (SyntaxError in the new file): the daemon dies at import and the chord silently
  does nothing — `_spawn_daemon` returns True on a successful `Popen` regardless
  (`:127-138`), so `main()` returns 0 and never falls through to `cold()`. **This exposure is
  identical for every candidate below, including doing nothing**, because the next kitty restart
  or the 6h IDLE_EXIT already forces a fresh interpreter onto the new bytes. It is not a cost of
  the reload; it is a pre-existing property.

## RAN — measurements

| what | result |
|---|---|
| `os.stat` on the deployed path | **2.3 µs** |
| `sha256` of the whole 61,208-byte source | **44.8 µs** |
| bare interpreter start | 0.02-0.03 s |
| `from PIL import Image,ImageDraw,ImageFont` | 0.06-0.08 s |
| `kitty @ --to unix:/tmp/kitty-73832 ls` | 0.03-0.08 s |
| live daemon | pid **79958**, ppid **1**, started 23:53:34, RSS **41.8 MB**, argv `daemon --initial=off --all` |
| kitty sockets present | exactly one, `/tmp/kitty-73832` |
| daemon's inherited env | `KITTY_PID=73832`, `KITTY_LISTEN_ON=unix:/tmp/kitty-73832` |
| `socket.timeout is TimeoutError` (⊂ OSError) on 3.11.4 | **True** |

A sha per idle tick (1 Hz) is **45 µs/s = 0.0045% of a core**. There is no cost argument
against hashing; do not bother with an mtime pre-filter (it would be a cost gate that is not
strictly weaker than its predicate, for a saving of 42 µs).

## RAN — the execv trap, probed on the daemon's own interpreter

`scratchpad/execv-probe.py`, one process, bind + flock + STATE, then `os.execv` into itself:

    srv.fileno()=4 inheritable=False        # PEP 446: CLOEXEC ⇒ execv CLOSES it
    lockfh.fileno()=3 inheritable=False
    socket FILE survives close() of its fd: True
    -- after execv, same pid --
    sock file still on disk: True
    state file still on disk: True
    RE-FLOCK after execv: ACQUIRED          # the exec RELEASED the advisory lock
    connect() to the old socket path: errno 61 (Connection refused)
    unlink+rebind after execv: OK

So a naive `os.execv` in this daemon:

- **leaves a stale socket FILE with nobody listening.** It does not leave a *broken* daemon —
  `daemon()` unlinks before bind at `:1139-1143` — but for the whole re-exec window every
  `_client()` connect gets **ECONNREFUSED**, which `_client` is documented to read as *"no
  daemon"* (`:73-82`) and answers by spawning a competitor.
- **releases the flock** (`:1130-1134`), so that competitor can win it. Then the re-exec'd
  process loses `flock(LOCK_EX|LOCK_NB)` and `return 0`s — **and the press that spawned the
  competitor is silently dropped**, because `main()` already returned 0 on a successful Popen.
- The window is real: exec + interpreter + `from PIL import …` + `ksock()` + `kitty @`-free
  socket resolution ≈ **0.1-0.2 s** before `srv.listen()`.
- What it *does* preserve, and this is the one thing in re-exec's favour: `finally` never runs,
  so a re-exec **while the titles are up** keeps them painted and keeps STATE, and passing
  `--initial=on` repaints with `force=True`. If you ever need hot adoption *without dropping the
  bars*, re-exec is the only candidate that can do it. Nothing today needs that.

Quit-and-respawn has none of these: the process exits, the kernel releases the flock, `finally`
unlinks SOCK so the next `connect()` gets **ENOENT** rather than ECONNREFUSED, and the respawned
daemon is started by a **fresh client with live kitty ancestry and env** rather than replaying a
possibly-stale `KITTY_LISTEN_ON` through `ksock()`'s ancestry/glob ladder (`:697-751`).

**In-flight state lost by quitting while idle: nothing that is not derived.** `st["tg"]`/
`st["frames"]` are rebuilt by `warm()`; `_PNG_CACHE` (`:459`) and `_SENT` (`:884`) are caches and
the next press transmits with `force=True` anyway (`:1204-1206`); the strips are on disk under
`STRIPDIR` (`:949-950`); STATE is unlinked but is already False. The daemon is a **cache with a
duty only while `st["on"]`** — which is exactly why the idle gate makes dropping it free.

## The candidates, priced

| mechanism | latency to adopt | mid-paint | in-flight state | verdict |
|---|---|---|---|---|
| **sha check ⇒ break, client respawns** | next idle tick (≤1.0s after titles are down) | cannot fire — gated on `not st["on"]` | none (all derived) | **SHIP** |
| `os.execv` self re-exec | ~0.1-0.2 s, any time | survives (finally skipped), needs `--initial=on` | preserved | only if hot-swap-while-painted is ever required; costs a 0.1-0.2 s ECONNREFUSED window in which a press is **dropped** |
| deploy-time version stamp the daemon compares | same as sha, minus reliability | same | same | **rejected**: a second store that can rot; `deploy-live.sh`'s own `deploy-last-advance` precedent exists but the source file IS the ground truth here — a stamp adds a way to be wrong |
| launchd `KeepAlive` supervision | instant | would fire mid-paint | wipe + repaint | **rejected**: the daemon must die with *its* kitty (`os.kill(kpid,0)`, `:1231`) and must not exist when kitty does not; launchd would fight that, and KeepAlive turns a rewrite-storm into a respawn-storm |
| a separate watcher process | instant | same as launchd | same | **rejected**: a second long-lived process to solve a long-lived-process problem |
| do nothing (status quo) | 6 h (IDLE_EXIT) or the next kitty restart | — | — | this is what happened tonight |

## Q4 — is this general? Yes, and the fleet is mostly already immune

`~/Library/LaunchAgents`, 36 `com.claude.*`/`com.chrisren.*`/`com.reso.*` jobs read:
**32 are `StartInterval` or `StartCalendarInterval`** — they re-exec every tick and therefore
adopt new code for free. Only **4 are `KeepAlive=true`**:

| job / process | holds repo code? | self-restart on change? |
|---|---|---|
| `com.claude.lead-supervisor` → `scripts/lead-supervisor.sh --daemon` (pid 1094, up since 16:29) | yes | **YES** — `:1329`, the template |
| `com.claude.compressor-sentinel` → `scripts/compressor-sentinel.sh` (pid 9749, `while :;` at `:1434`) | yes | **NO — same gap, second instance** |
| `com.claude.caffeinate-floor` → `scripts/caffeinate-floor.sh --run` | thin wrapper round `caffeinate` | n/a-ish |
| `com.reso.sevenrooms-sidecar` | other repo | out of scope |

Plus the one with no supervisor at all: **`kitty-pane-title-overlay.py daemon`**. So the general
answer is a two-line rule, not a one-off:

> A process that holds repo code in memory for longer than one land must either (a) be
> re-exec'd by its scheduler every tick — the fleet default — or (b) carry
> `self_restart_if_stale()`. There is no third state, and `compressor-sentinel.sh` is currently
> in it.

`scripts/kitty-pane-title-overlay.py` is reached through a symlink
(`~/.claude/scripts/... -> ~/Development/claude-infrastructure/scripts/...`, verified by `ls -l`),
and `os.stat` follows it, so the check re-resolves the live layer on every tick and sees both a
checkout fast-forward and a symlink repoint.

## Q5 — prior art found before designing

- `scripts/lead-supervisor.sh:112-134` (`SUP_SELF`, `sup_self_sha`, `SUP_SELF_SHA0`) + `:1329-1344`
  (`self_restart_if_stale`) + `:1379` (`while :; do self_restart_if_stale; sweep; sleep …`).
  Note its warning at `:1326-1328`: **call it PLAINLY, never inside `$(…)` or a pipeline**, or the
  exit lands in a subshell and the stale daemon sails on. The python analogue of that trap is
  `break` inside a nested `try` — put it in the loop body, not in a helper that returns a bool
  you then forget to act on.
- `tests/lead-supervisor-self-restart.bats` — the red-proof shape, including *"replace by RENAME,
  never by appending"* and the ABSTAIN control.
- `scripts/deploy-live.sh` / `scripts/wrap-ledger.sh` carry the `deploy-last-advance` stamp — a
  *deploy-side* version pointer, but it answers "what did the converger deliver", not "what bytes
  is this process running", and is the wrong instrument here.
- No reload convention, SIGHUP handler, or version-stamp file exists for python daemons:
  `grep -rn "os.execv\|SIGHUP"` over `scripts/ bin/ hooks/ tools/` returns 5 hits, all of them
  interpreter re-exec at startup (`kitty-pane-title-overlay.py:163,189`, the two mcp probes) and
  one `os.execvp` in `kitty-drag-w4.sh:459`. **Nothing listens for a reload.**

## Adversarial pass — what I nearly got wrong

1. **I first argued re-exec would break `ksock()`** because `os.getppid()` is 1 and the ancestry
   walk (`:730-748`) dies immediately, leaving only the `/tmp/kitty-*` glob which returns `None`
   with 2+ kitties. Then I read the live daemon's environment: it carries
   `KITTY_LISTEN_ON=unix:/tmp/kitty-73832`, and `execv` preserves `environ`, so `ksock()` short-
   circuits at `:722-728`. **Downgraded from a blocker to a residual.** It still favours
   quit-and-respawn (a fresh client cannot carry a stale listen-path), but it is not the argument.
2. **The glob fallback is polluted right now** — `/tmp/kitty-482` and `/tmp/kitty-dev` are
   symlinks left by the drag work. They happen to be filtered (`S_ISSOCK` on the resolved target
   is False), so `len(socks)==1` still holds. That is luck, and it is the namespace this repo's
   own memory rule already warns about writing into.
3. **The daemon has no bound `on` path today.** `config/kitty.conf:596` invokes the overlay only
   as `off --all` and the ⌘⌥B map at `:669` is DISARMED, which is why the live daemon shows
   `--initial=off` and STATE is absent. So `st["on"]` is effectively always False and the idle
   gate will fire every time — good for the recommendation, and worth the operator knowing that
   41.8 MB is resident to answer a chord that only ever says `off`.
4. **The log cannot answer "did it adopt?"** — `_log` writes on failure only, and
   `grep -c daemon` over the 249 KB log returns **0**: no start, exit, or version line has ever
   been written. A retire that logs nothing is indistinguishable from a daemon that was never
   there. The `_log` line in the shape above is therefore not decoration; it is the only evidence
   the mechanism ever runs.

## Conviction

- **92%** that sha-check-then-break-when-idle is the right mechanism here (the 8% is the
  possibility the operator wants adoption *while the bars are up*, which only re-exec gives).
- **97%** on the execv facts (probed directly, on the daemon's own interpreter, with both arms).
- **85%** that `compressor-sentinel.sh` has the same gap — read from its plist + `while :;` +
  absence of any `self_restart`; I did not exercise its loop.
