# Limit-recover zero-memory plan — close verdict (2026-10-06)

cc-backlog `ed9e2ce7dfdb` ("advance Limit-recover without the memory bottleneck — plan"), run off-box in a cloud session.

## Verdict

**The plan's work was already on trunk and only the plan's markers were stale.** The item's title and the
scanner's "5 of 6 sections not DONE" came from unmarked headings, not from work left to do. This close marks the
headings DONE, sets the frontmatter to `status: complete`, and adds a closing status line. No code changed.

## What was run

- `git fetch --unshallow`, then `git rev-list --count HEAD..origin/main` → `0`. The tree read here IS trunk.
- Dispatcher vintage: `git rev-parse origin/main:bin/cc-dispatch` → `03e82d02b1fc534d11df9cd4939541225bdb6829`.
  That EQUALS the blob in the brief, so the dispatcher that fired this session is trunk's.
- The plan's Status section cites desk shas `b485687a0`, `c6f7dd483` and `c91d7210b`. None of them resolves in
  this mirror (`fatal: Not a valid object name`), so landedness was checked by CONTENT on `origin/main`. The
  matching mirror commits are:
  - `cf41e6aa` W0 slot receipts (`docs/research/limit-recover-zero-memory-2026-10-06/slots/`)
  - `a05b5f95` W0 synthesis (`…/README.md`)
  - `7368bd1d` W1: `cc-lr rotate --list` / `rotate (--all | --account A)`. `git show origin/main:bin/cc-lr`
    carries the verb at lines 33-35, 164-175 and 1447 onward.
  - `0cc89c51` skill text, skeptic corrections, W1 before/after, plan status
- `scripts/plan-phase-scan.sh <plan> --falsify`. Before the edit it printed nothing and exited 1, because the
  scanner reads unmarked headings as PENDING. After the edit it prints `FALSIFIED` and exits 0, and every
  section reads DONE.

## Why the frozen scope is met

| Scope clause | Evidence on trunk |
|---|---|
| Two quick commands: one lists, one rotates all in place | `cc-lr rotate --list`, `cc-lr rotate --all`; `tests/cc-lr-front.bats` has 8 rotate cases |
| Per-session memory cost of a rotation is measured | README § Q2: relaunch costs 177-197 MB steady and replaces a process that was already there; the machinery peaks at 45-58 MB for under 1 s |
| Its cause is removed or cut to near zero | Nothing to remove: the net cost is about zero. README row 2 (conviction 93) |
| Any remaining concurrency limit is set by a measured constraint and stated in the output | Widths stay at move 4 and recover 2. The one batch at width 4 ran at load 150 on 10 CPUs with boot time tripling. Each `rotate`, `plan` and `move` output prints the widths with their reasons (README § W1 result) |

## Outside this plan, and left open on purpose

Rows 10-14 of the README's ranked table are not built. They are: a move width above 4, recover caps above 2,
adding the reaper's whitelist entry, spreading a batch over several targets, and shortening the proof waits. The
two unexplained stalls are also open: 68-70 s at the head of `lr-handoff`, and 71-134 s between the typed
relaunch and the launcher.

Every one of these needs a **real rotation**. Phase 0's hard constraints forbid that from inside a session, so
none of it is work this item can do. The plan's Status says the `--slots 6` trial decision is "filed".

**Not verified from here:** the backlog store is on the operator box, so this session could not check that the
follow-up row exists. When the desk closes `ed9e2ce7dfdb`, it should confirm a row for that trial exists, and
file one if it does not.
