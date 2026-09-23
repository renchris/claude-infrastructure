# Postland Errno 24 — the "runner fd budget" premise is unmeasured, and bats cannot supply the fds

cc-backlog `2e8228525c94` · cloud session, off-box (Linux VM) · 2026-09-23 · trunk at fire = this
branch's base (`git rev-list --count HEAD..origin/main` = 0; `bin/cc-dispatch` blob
`dc9130372d63…` EQUAL to `origin/main`, so the dispatcher that fired this IS trunk).

## The row, as filed

`b743e182` (2026-09-17) closed the 9/14 `_NoFace` postland windows on
`tests/kitty-conf-bindings.bats` and filed the residue:

> the 5/14 raw Errno 24 windows die inside Python's own import machinery before the script runs,
> so no script-level guard can reach them; that is the runner's fd budget, filed as 2e8228525c94
> (needs-human, conviction 65 — raising the ulimit may mask a concurrency defect).

Its `--why-not-now` offered three remedies ("raise the fd budget or cut concurrency") and measured
none of them (`docs/research/jev-100p-2026-09-21/a2-autonomy-stores.md` flags it as one of two
arguable launderings in 337 rows). No cure for it exists on trunk: `git log -S"ulimit -n"` and
`git log -S"NumberOfFiles"` over `origin/main` touch only research docs, and
`launchd/com.claude.postland-verify.plist` carries no `SoftResourceLimits`.

## What was measured here

**EMFILE is per-process, so "the runner's budget" only bites a process that holds ~256 fds.**
The limit term is real: launchd jobs inherit a soft `maxfiles` of **256** while session shells
carry **1048576** (measured on the desk, `docs/research/mcp-memory-groundup-2026-08-10/06-daemon-multiplex.md:177`).
So the postland corpus is the one population of this suite that runs under 256. But a limit only
matters if something *fills* it, and every fill route this VM can build came back empty:

| arm (bats 1.13.0, the desk's version; `ulimit -n 256`) | fds a `run` child inherits |
|---|---|
| one file, one `run python3 …` | `[0,1,2,3,4,5]` |
| the same probe as file 301 of a 300-file single invocation (the corpus shape: ONE `bats <list>`) | `[0,1,2,3,4,5]` |
| plus a file that opens fds at TOP LEVEL (`exec 7</dev/null`, `exec {x}</dev/null`) earlier in the run | `[0,1,2,3,4,5]` |

bats isolates each file in its own process, so a leak in one suite cannot reach another's children.
The runner opens no persistent fds of its own either: `scripts/postland-verify.sh` has no `exec N>`,
`{var}>` or lock-fd redirections. A fresh interpreter starting with 6 fds cannot exhaust 256 by
importing.

**The subject itself does not leak under Pillow 12.3.0 / FreeType.** A second hypothesis was that
`_FACES` caches a `FreeTypeFont` per em (152 ems, 2–3 faces each) and FreeType keeps each font file
open, which would put `measure` past 256 in-process and would make the lazy PIL imports after that
point die with Errno 24. That is REFUTED on Linux: `measure()` run in full under `ulimit -n 256`
with DejaVu substituted for the macOS faces returned `rc 0`, `VERDICT BREATHING`, 152 cached ems,
and **4 fds at start and 4 at end**. FreeType's unix stream mmaps the file and closes the fd.

## What is NOT settled, stated in the verdict rather than under it

Every arm above ran on **Linux**. The failing windows ran on **macOS under launchd**, at load
13–30, and this VM can reproduce neither. The five tracebacks themselves live on the desk
(`land.log` / the postland page), not in any tracked file, so the claim "dies in import machinery
*before the script runs*" could not be re-read here. Note that the script's own `_faces` comment
records the other reading: PIL's *lazy* plugin import failing mid-`measure`, after fonts had been
opened, which is an in-process import, not interpreter startup. The mac-only arm (does
macOS's FreeType or CoreText path hold font fds?) is **unrun**.

So the row's premise is neither confirmed nor refuted. What *is* established is that its three
proposed remedies were chosen without a reading of either term. Raising the limit would hide a
leak if one exists; cutting concurrency does nothing, because the corpus runs one file at a time.

## What this change does

It makes the next Errno 24 window name its own cause:

1. `scripts/postland-verify.sh` `env_fingerprint` now stamps `"nofile"` (the soft limit every child
   inherits) and `"fds"` (the fds the runner holds at corpus start) into `ENV_FP`. That value goes
   into every stamp's `env` and every RED/HUNG/cut page's `env:` line. Keys are additive, so no
   consumer that reads `bats`/`cc`/`load` changes.
2. `tests/kitty-conf-bindings.bats`'s two `measure` cases print
   `fd budget: nofile=N fds=M` on a red, read **inside the test process**, whose table `run`'s child
   inherits.

How to read the next red window:

| stamp / red line | means |
|---|---|
| `nofile=256`, `fds` single digits | neither term is inherited. The fds are consumed **inside** the python process, so run the mac-only arm: count `lsof -p` across `measure` |
| `fds` in the hundreds | a leak upstream of the test. Bisect runner → bats → suite |
| `nofile` far below 256 | something lowered it. Find the setter; do not raise the limit over it |

Only the first row justifies `SoftResourceLimits { NumberOfFiles }` in the plist, and even then
as parity with the session population, not as a fix.

## Close

This row is not cured. It is **instrumented**. The remaining step is to read the `nofile`/`fds` pair
off the next postland page that convicts this suite. That is a desk read, not operator-only, so
this is not a park.
