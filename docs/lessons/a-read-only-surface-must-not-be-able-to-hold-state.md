# A read-only surface must not be able to hold state of its own

**2026-09-19.** `~/Development/reso-management-app` — the folder a human opens in Cursor or Finder
to read a file — had been showing files **1,948 commits old**. It is nobody's workspace: every
session in that repo is routed into a worktree by `~/.zshrc:_cc_route_check` →
`scripts/new-worktree.sh`, so the original checkout is only ever read.

## The reframing that made the fix small

The repository was **never stale**. `refs/remotes` lives in the git *common* dir, so every fetch by
any of that repo's 35 worktrees had been updating the root's own `origin/main` the whole time —
measured, root and `wt-pool-1` both read `06ce6fee5` at the same instant. The objects were local.
The refs were current. Only `HEAD`, and therefore the **files**, had never moved.

That matters because it kills the expensive readings of the problem before they are attempted. There
is nothing to re-clone, nothing to mirror over the network, no second remote to configure, and the
advance itself costs no network at all. The whole defect was one ref that nothing ever advanced.

## Why nothing ever advanced it, and why "just run `git pull --ff-only`" is not the fix

Two wedges, independent, both silent, both permanent once entered:

1. **Divergence.** The root's local `main` was 10 commits *ahead* — 7 of them already on trunk under
   a different sha, rebased by the land flow (`git cherry` prints those as `-`). A diverged branch
   makes `pull --ff-only` refuse, correctly, into a terminal nobody is watching. **One** accidental
   commit in a shared checkout is enough, and this box produces those: the same folder had already
   rotted and been hand-reconciled once before, preserved at tag `archive/local-main-20260702`
   ("169 ahead / 702 behind origin/main at retirement", 32 patch-unique commits triaged). Ten weeks
   later it was 10 ahead / 1,948 behind again.
2. **Tooling dirt.** `next dev` *regenerates* a block in `AGENTS.md` — the file carries its own
   `BEGIN:nextjs-agent-rules` marker and names the writer,
   `next/dist/server/lib/generate-agent-files.js`. A dirty tree blocks a merge, and "keep the browse
   checkout clean" is therefore not a discipline any human can hold: the build tool re-dirties it.

The second occurrence is the whole lesson. A one-time reconcile was *tried*, by a careful person,
with a proper triage doc — and the folder rotted again on the same axis. The remedy that only
removes today's divergence leaves tomorrow's reachable.

## The rule

**If a surface exists only to be read, remove its ability to hold state — do not ask people to keep
it clean.** Concretely, for a git checkout: hold it at a **detached HEAD**, never on a local branch.

- Detached ⇒ divergence is structurally impossible. There is no branch to commit onto, so wedge (1)
  cannot recur. It is also the honest signal to whoever opens the folder: git itself refuses a
  casual commit from a detached HEAD, so "we never implement against it" stops being a convention
  and becomes a property of the thing.
- Dirt is **absorbed, not blocked**. `git stash create` mints a real commit object without touching
  the tree; point `refs/mirror-rescue/<ts>` at it, then clear. Nothing is lost — `git stash apply`
  recovers it years later — and wedge (2) can no longer stop the mirror.

## The one case that must still stop it, and why

An **untracked** file sitting where the target ref wants to write one. `git checkout -f` would make
the mirror unstoppable, and that is the wrong trade: the bytes it deletes are the only bytes on that
surface a human actually wrote. So: plain `checkout --detach`, never `-f`, and report
`verdict=blocked` loudly. Stopping is correct here precisely because the alternative is deleting
what we did not write.

Symmetrically, a **diverged local branch is reported, never rewritten** — the mirror fast-forwards a
local branch only when it is provably an ancestor, so the ref that holds someone's unlanded work
survives the mirror moving past it.

## The trigger, and why one of the two halves is not optional

`refs/remotes` being shared is also the *event source*: when any worktree fetches, the file that
changes is the mirror's own `.git/refs/remotes/origin/main`. The watch target and the input are the
same file, so a `WatchPaths` launchd job advances the folder within seconds of the fleet learning
about a land, with no polling. (`packed-refs` is watched beside the loose refs because `git gc`
moves a ref between the two representations; watching only one goes quiet at an unpredictable
moment.)

But that fast path is *driven by other people's fetches*. If the fleet goes quiet for a day,
`refs/remotes` never changes, the watch never fires, and a mirror pinned to a stale `origin/main`
reports itself **perfectly current** — the same silent-staleness failure in a new costume. So the
periodic tick stays, and it is what carries the (rate-limited) network fetch.

Generalisable form: **an event-driven refresh whose events come from a third party needs a
time-driven backstop, because the third party going quiet is indistinguishable from nothing having
changed.**

## A postscript the land gate wrote, and it is the sharper half

The first land was REFUSED by `pipefail-sigpipe-lint` over two sites in the subject itself. Both
were `producer | grep -q`: under `set -o pipefail`, `-q` exits on the first match, the producer takes
SIGPIPE, and the pipeline's status is that failure — **so the condition reads FALSE on a MATCH**.
Both failed in the dangerous direction. The "is this branch checked out in a worktree?" guard would
have answered *no* on a match and fast-forwarded a branch another worktree holds; the failure rollup
would have reported a **blocked** mirror as success, which is the exact silent staleness the rest of
this work exists to end.

The suite was 9/9 green at that moment. Green was not evidence of correctness — it was evidence the
fixture was too small.

**Then the interesting part.** A regression case was written, and a mutant run was done to prove it
had power: restore `grep -qx`, run the case. **The mutant SURVIVED.** `git worktree list --porcelain`
emits ~120 bytes per worktree, so any fixture buildable in a test writes its entire output into the
64 KiB pipe buffer and exits before `grep` reads a byte — no blocked write, no SIGPIPE, no failure.
Reaching the regime needs roughly 550 worktrees. The new case is therefore an **equivalence guard**,
and it says so in its own comment rather than posing as a red-proof.

Two rules fall out, and the second is the one worth carrying:

- **Run the mutant.** A case written immediately after a real bug, by the person who just understood
  it, still failed to detect it. Nothing but executing the pre-fix form would have revealed that.
- **Some defect classes are cheap to see in SOURCE and unreachable at RUNTIME, and for those the
  static ratchet is not a second-best stand-in for a test — it is the correct and only guard.**
  Pursuing behavioural coverage there buys a fixture that resembles production while provably not
  reaching the defect, which reads as coverage and is worse than none.

## And the second gate caught a worse one, by the same mechanism

The next land was refused by `unattended-path-lint`: `timeout` is **not a macOS binary** — it arrives
with Homebrew coreutils — so on a launchd job's own minimal PATH, `timeout 180 git fetch …
>/dev/null 2>&1` finds no `timeout`, fails, and the redirect eats the error. **The network fetch
would silently never have run.** The mirror would have been limited to whatever refs sibling
worktrees happened to fetch: fine while the fleet is busy, broken exactly when it goes quiet — the
precise silent-staleness failure the periodic tick exists to prevent, re-entering through the back
door, and invisible for weeks because it looks like it works.

No behavioural test in this suite could reach it either: the tests run under a developer shell with
Homebrew on PATH. The defect exists only in the *deployment environment*, which is the second
instance in one change of the same shape — **a defect cheap to see in source and unreachable from
the test harness**. Two gates, two such defects, one suite reporting green throughout.

Worth noting what the repair needed beyond the lint's advice: the house `bounded()` helper degrades
to *unbounded* when there is no `timeout(1)`, and an unbounded fetch that hangs wedges a launchd job
permanently, because launchd will not start a second instance while one runs. So the fix carries a
second bound that needs no external binary (`GIT_SSH_COMMAND` with `ConnectTimeout`, the remote being
SSH), and a failed fetch now surfaces as `fetch=failed` on the verdict line instead of vanishing.

## Subject

`scripts/browse-mirror-sync.sh` · `launchd/com.claude.browse-mirror.plist` ·
`migrations/0032-browse-mirror.sh` (c10) · `tests/browse-mirror-sync.bats`.

Pre-existing divergent history preserved at tag `archive/root-main-2026-09-19`; the one genuinely
stranded file in it is `docs/research/NEXTJS_16_3_VS_REPLICACHE_VERDICT_2026-08-05.md`, absent from
trunk (the other nine commits are landed-equivalent or superseded).
