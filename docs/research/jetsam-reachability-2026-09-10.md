# Jetsam reachability for the dev-worker class — what actually reaches a non-daemon child

**2026-09-10 · Darwin 24.6.0 / macOS 15.7.9, arm64, uid 501 · cc-backlog `8474ae944ece`**
Answers fix direction #5 of `panic-2026-08-24-fifth-watchdog.md` §6, whose own text left it open as
a *"research task: which launchd/spawn attributes reach non-daemon children"*, and re-measures the
"verified lever" of `panic-compressor-2026-08-05.md` §7.6.

Every claim below is one arm of **`jetsam-reachability-2026-09-10/probe.sh`**, which is shipped
beside this file and takes under a second per arm. These are properties of a kernel and a dyld that
arrive with the OS: re-run the probe before trusting a number here, exactly as the ship-policy table
delegates to a repo's own status tool rather than restating a perishable fact.

## The question

In panic #5 the storm held **128 GB across 747 node workers and 746 of them sat at jetsam band 180**
— the default band for a non-app process. Jetsam ran the entire spiral and could not touch one of
them: it harvested **3,109 small daemons for 9.28 GB** while the actual holders were structurally
out of reach, `killing_top_process` count 0. Every userspace guard this repo ships can itself be
starved off-CPU (jetsam was unrun for 94 s in the Aug-5 panic), so the kernel is the actor of last
resort — and it was disarmed by the band, not by bad luck.

So: can an unprivileged agent lane make its own workers reachable?

## The nine arms

| # | What was asked | Result |
|---|---|---|
| 1 | `memorystatus_control(…)` on a **live pid**, unprivileged — the Aug-5 §7.6 lever | **EPERM on every command**, including `GET_*`, including on the caller's **own** pid |
| 2 | `posix_spawnattr_setjetsam_ext(3)`, FATAL 100 MB, child touches 300 MB | child **SIGKILL** at the limit |
| 3 | **control** — identical child, no jetsam attrs | `SURVIVED 300`, exit 0 |
| 4 | SOFT limit (`flags=0`), same child, no system pressure | `SURVIVED 300`, exit 0 — a high-water mark, not a cap |
| 5 | Is the stamp inherited by an **exec'd** grandchild? | **No.** Grandchild exited 0 at 3× the limit |
| 6 | Is it inherited by a **`fork()`ed** child? | **No.** |
| 7 | `posix_spawn` **interposed** via `DYLD_INSERT_LIBRARIES` | grandchild **SIGKILL** — the interposer reaches processes the wrapper never spawned |
| 8 | Does a system shell carry `DYLD_INSERT_LIBRARIES` to its children? | `/bin/sh` **empty**, `/bin/zsh` **empty**, `node` **carries it** |
| 9 | What does dyld do with an unloadable inserted library? | **exit 134 (SIGABRT)** — it TERMINATES the process. Except under a SIP-restricted binary (`/usr/bin/true`), where it silently ignores it |

## What the arms decide

**1. The cited lever is root-only, so the obvious design cannot be built by an agent lane at all.**
Aug-5 §7.6 called `memorystatus_control(MEMORYSTATUS_CMD_SET_MEMLIMIT_PROPERTIES)` "the verified
lever … on ANY live pid, **root**". The word *root* was in the source and did not survive into the
backlog row, whose remedy reads as something a lane could do. Arm 1 settles it: not merely the
setters — the **getters** are EPERM too, and so is targeting your own pid. Any design of the shape
*"the sentinel walks the storm cohort and stamps what is already running"* needs an
operator-installed root helper. It is not written here and is not filed as work: a standing root
daemon is a privilege expansion whose benefit is unproven while the spawn-time arm is untested in
production, and a row prescribing one would be a decision minted by the wrong party.

**2. The spawn-time arm IS unprivileged and IS enforced** (arms 2/3, one variable, both arms run).
This is the whole opening. `posix_spawnattr_setjetsam_ext` is Apple SPI — `spawn_private.h` is not
in the SDK — but the symbol is exported by libSystem and resolves at run time.

**3. The stamp is per-process and NOT inherited** (arms 5/6) — and this is the fact that decides
every design above it. A wrapper that stamps the command it launches reaches the parent and **none
of the workers**, which in the storm's own shape (one `next-server`, 746 `node` workers) is the
entire population missed. The stamp must be applied at *every* spawn, which unprivileged means
interposing `posix_spawn`/`posix_spawnp` for the life of the tree (arm 7).

**4. The interposer's reach ends at the first system shell** (arm 8). `/bin/sh` and `/bin/zsh` are
SIP-restricted: dyld both ignores **and purges** `DYLD_INSERT_LIBRARIES`, so everything below such a
shell silently loses the stamp while continuing to work perfectly. `node` is not restricted, keeps
the variable, and re-stamps at depth 2 — so a `node → node → worker` tree is covered and a
`sh -c 'node …'` tree is not. Any consumer must therefore `exec` its target **directly**.

**5. Arm 9 killed a design that looked obviously right.** The natural way to make this box-wide is
to have `hooks/coldcompile-admit.sh` — which already prepends a complete statement to every command
that would ignite a cold compile, and has the measured argument for why that shape and not a prefix
wrapper — also prepend an `export DYLD_INSERT_LIBRARIES=…`. That is **not safe**, and the reason is
arm 9: a bad inserted library is not a warning, it is `SIGABRT` at exec. The helper cache lives
under `~/.cache`; the day any tmp-reaper prunes it, every process launched from that shell dies at
exec with a message that names dyld and never names us. An injected export into a long-lived agent
shell is a loaded gun with a fuse of unknown length. The variable may only be set for the duration
of one command whose helper was verified moments earlier — which is what `bin/cc-jetsam-exec` does.

Arm 9's last line is a second, sharper trap: the smoke test that verifies the library loads must
probe an **unsigned** binary. The first implementation here probed `/usr/bin/true`, which is
SIP-restricted, so dyld ignored the inserted library and the check passed over a corrupt artifact —
a smoke test blind to the only state it exists to detect. `tests/cc-jetsam-exec.bats` C5 went red on
exactly that and is the pin.

## What shipped

`bin/cc-jetsam-exec` — `--mem <MB> [--band N] [--fatal] -- <cmd> …`. It builds the helper pair
(interposer dylib + a launcher that stamps the top process) from source embedded in the script
itself, caches them keyed on the source's own hash and the arch, smoke-tests the dylib against an
unsigned binary, then execs the target directly with the stamp in place. The default limit is
**soft** because that is what the item is actually about: a soft limit does not cap a lane, it makes
it *eligible* — it converts the kernel's measured "no eligible processes" dead-end into a targeted
kill of a real holder at the edge, and costs nothing on a healthy box (arm 4). `--fatal` is the hard
cap. With no compiler, or with a helper that will not load, it **refuses** rather than running the
lane unprotected; `--allow-unprotected` is the loud override. Every run prints one parseable
`verdict=protected|unprotected` token.

Wrap a lane at its own launcher, never through a shell:

```
cc-jetsam-exec --mem 6144 -- pnpm design:gate      # covered: pnpm → node → workers
cc-jetsam-exec --mem 6144 -- sh -c 'pnpm design:gate'   # NOT covered below the shell (arm 8)
```

## The band arm is applied but UNVERIFIED, and this document does not claim it

`posix_spawnattr_setjetsam_ext` carries the band in the same call as the memlimit, and the call
returns 0 — but **no unprivileged read of a process's jetsam band exists on this box** (arm 1:
`GET_PRIORITY_LIST` is EPERM), and the only honest way to observe the band taking effect is to put
the machine under genuine memory pressure, which is the one thing the Aug-5 research forbids
("do NOT probe limits by reaching them"). So: the memlimit half is measured-enforced, the band half
is measured-*accepted* and not measured-*effective*. Treat `--band` as unproven until either a root
read (`launchctl procinfo`, `memorystatus_control` as root) or a real JetsamEvent report attributes
a kill to a stamped worker.

## The residual, named rather than filed

- **Wiring.** Nothing in `claude-infrastructure` runs a node worker pool; the lanes that produced
  all six panics live in `reso-management-app` (`design:gate`, `pnpm build`, `test:unit`) and are a
  change in that repo, not this one. This ships the mechanism, not the adoption.
- **Live-pid stamping** (a root helper the compressor-sentinel could call at trip time, to make a
  storm cohort reachable *instead of* SIGKILLing it) remains available and unbuilt, per §1 above.
- **Open question 7 of the fifth-watchdog doc** — *can `killing_top_process` ever engage on this
  config?* — is untouched here and still open. If it structurally cannot, this arm and the root
  memlimits carry the entire load.

## Provenance

`docs/research/panic-2026-08-24-fifth-watchdog.md` §6 fix #5, §2.1, §7 Q7 ·
`docs/research/panic-compressor-2026-08-05.md` §7.6, §7.2 ·
`scripts/compressor-sentinel.sh` (the userspace arm this backstops) ·
instrument: `jetsam-reachability-2026-09-10/probe.sh` · subject: `bin/cc-jetsam-exec` ·
proof: `tests/cc-jetsam-exec.bats` (15 cases, incl. the interposer mutant and the dyld-abort pin).
