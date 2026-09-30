# On macOS `ps -o comm` is argv[0], and a newness gate does not keep a browser out

Two premises in `scripts/compressor-sentinel.sh` sat under its cohort widening of 790f2dc2d
(2026-09-16). Each was a sentence in a comment. Both were false, and between them they let the
sentinel freeze and kill the operator's browser while leaving the storm classes it was built for
out of reach.

## 1. `comm` is argv[0], not the executable path

The path-protection rule was `comm !~ /^\//` ⇒ protected: "a comm that is not an absolute path is a
zombie or an exiting process, so UNIDENTIFIABLE ⇒ NEVER ACTED ON". It is right about `(git)`. It is
wrong about everything else, because on macOS `ps -o comm` prints **argv[0]**, not the resolved
executable:

- A process started by bare name has a bare comm. Live: `node` workers print `comm=node`, and 27 live
  processes with `ucomm=node` had a non-absolute comm.
- A process that rewrites its title prints the title. The 2026-08-09 spawner rendered as
  `next-server (v16.2.6)`. Panic #5's 249 workers had argv `node /…/postcss.js`.

So the rule silently protected every bare-invoked or title-rewritten process. That covers both the
08-09 class and the panic-#5 class the parent-breaker was written for. Replay: with the rule, the
panic-#5 fixture selects cohort 0 and no parent. Without it, the cohort is 5 and the fixture breaks
`42897 5 next-server_(v16.2.6)`.

**The rule:** use the kernel's exec name (`ps -axo pid=,ucomm=`) when you need to know what a process
IS. argv rewriting cannot change it. Treat `comm` as a claim the process makes about itself. The fix
narrows the protection instead of dropping it: a process is selectable again only when its ucomm is
exactly `node`, its comm does not start with `(` or `<`, and its comm does not mention claude. If the
ucomm read fails, the process stays protected.

## 2. "It has been up for hours, so it is in the previous census" is false for a browser

The same commit said a GUI app is kept out of the generic cohort by the newness gate: "a browser that
has been up for hours is in the previous census". A browser starts a **fresh renderer process per
tab**. So the tabs opened in the minute before a trip are new, unprotected and over the floor, and
three of them clear the population floor (`ACT_MIN_COHORT=3`). The browser then owns 100% of the
selected burst, and the parent-breaker freezes the browser as the spawner.

Measured since 790f2dc2d: **7 Dia parent freezes and 4 Dia SIGKILLs**. In the latest, at
2026-09-30T15:51:34Z, row `18285 … parent` was killed on `retrip-over-debt`. Between those events
WindowServer logged the operator's browser as unresponsive. The replay of the 15:39:16Z trip at the
live floor and cap (40960 kB, cap 400) gives these results:

- Pre-fix, it selects the four renderers 43930 45904 46829 47473 and breaks `18285 4 Dia`.
- Fixed, it selects nothing.

**The rule:** a newness gate measures when a process started, not what it is. Any app that forks
per unit of user activity (browsers, Electron editors, terminals running agents) produces "new"
processes all day. Keep such apps out by structure. The sentinel now uses class 2: a bundle root
started by launchd with no automation switch, plus its whole process family at any depth. A family
member is a child that lives in the same app bundle (bundle-shaped or a plain binary, such as Dia's
agent-server) or has a rewritten title (Cursor's tsserver, two levels down). The chain ends at a shell
or any path outside the bundle. It does not rely on the gate.

## 3. Custody that checks only identity cannot see an outside resume

The kill at 15:51:34Z needed one more defect. The lead had already resumed Dia by hand (SIGCONT), but
custody compared only (pid, lstart). The row was still "owed", and the next retrip SIGKILLed a process
that was running normally. Custody now reads `stat=,lstart=` in the same single fork. A ledgered pid
that reads R/S/I past a grace period gets a belt SIGCONT, its row is dropped, and it is never killed.

## How to apply

- Before you build a protection or selection rule on a `ps` column, run it against live rows that
  were invoked by bare name and rows with rewritten titles. On this box that is `node` workers and
  `next-server (vX)`.
- When a comment says a gate "keeps X out", test that sentence against X's process model. Ask whether
  X spawns per request, per tab or per window.
- A custody ledger that can escalate to SIGKILL has to re-read process state as well as identity at
  kill time. "We froze it" stops being true as soon as someone else resumes the process.

Record: the bodies of the three `fix(sentinel)` commits just before this lesson in
`git log -- scripts/compressor-sentinel.sh`, and the header comment above `exe_classify` in
`scripts/compressor-sentinel.sh`. The judged design was drafted in `/tmp`, which a reboot wiped the
same day, so the commits are the tracked record.
