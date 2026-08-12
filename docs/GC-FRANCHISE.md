# The GC franchise — store → owner

Answer to root cause 2 of the infra-reliability audit (`docs/research/infra-reliability-audit-2026-07-22/synthesis.md`),
roadmap item 4: *"one sweeping reaper with per-store adapters."* Backlog `6cab0ab3cb2f`.

The audit's finding was not that any one store lacked a reaper. It was that **no one could
enumerate the stores**, so each leak was discovered by incident. This file is that enumeration;
`scripts/cc-gc.sh --list` is its executable half.

## The table

| Store | Owner | Kind | Horizon | Liveness gate |
|---|---|---|---|---|
| mailbox | `cc-gc.sh` | EXEC | 7 d fully-acked · 30 d stranded → **archived** | registry row w/ live pid, role pointer, name-keyed box |
| watchdog `.pid`/`.id` | `cc-gc.sh` | EXEC | 2 d, behind an identity pin | registry row; process start-time vs pidfile mtime |
| `/tmp/claude-501` scratchpads | `scratchpad-reaper.sh` (delegated) | EXEC | 48 h | live pid **or** transcript touched in-window |
| merged worktrees | `worktree-gc.sh` (delegated) | EXEC | 30 min idle + landed by patch-equivalence | live cwd, lsof, `.teammate-busy`, dirty tree |
| `.page` + 5 sibling event dirs | `autonomy-sweep.sh` | ASSERT | 7 d (`CC_EVENT_TTL_DAYS`) | drained by the same 300 s sweep ~2,000× first |
| session-index rows | `session-index-sweep.sh` | ASSERT | rows whose transcript is gone, + VACUUM | staleness-aware trylock |

> **session-index is the one store not yet closed.** Its retention leg is written and tested but
> **parked on branch `park/gc-session-index`**, because it deletes index rows and `ship-land.sh`'s
> escalation scan correctly refuses to auto-land destructive SQL — that is an operator ratification,
> not something this franchise may self-certify. Decision packet:
> `~/.claude/autonomy/decisions/shipland-esc-ab66db8.json`. Until it lands, `cc-gc.sh --store
> session-index` reports **inert**, which is accurate: nothing is pruning those rows. The adapter is
> shipped now precisely so the gap is visible rather than silent.
| transcripts | **the CC harness** (`cleanupPeriodDays`) | ASSERT | 30 d + 15 d grace | n/a — we never delete these |

## Why some adapters do not delete

An ASSERT adapter exists because the store **already has an owner**. A second deleter would race
the first; what these stores lack is not a reaper but a *reader*. Root cause 1 of the same audit is
that reapers land and then never take effect — `com.claude.log-rotation` was authored and never
`launchctl load`ed while `idl.jsonl` grew to 85 MB, and nothing noticed because nothing was
looking. An ASSERT adapter looks: residue older than the owner's **own** declared horizon proves
the owner is inert. `cc-gc.sh --strict` turns that into a non-zero exit.

`transcripts` is the case worth stating plainly, because it contradicts the audit that commissioned
this work. The audit recorded *"1.8 GB total, no retention"*. Measured 2026-07-25 across all four
config roots: **0** transcripts older than 30 d in `~/.claude` and `~/.claude-secondary`, 20 in
`~/.claude-tertiary`, and **0** past 60 d anywhere. The harness's own `cleanupPeriodDays` is the
owner and it is working. Writing a second transcript deleter would aim this repo's `rm` at the
harness's evidence for no measured benefit. The adapter reads instead — and it still catches the
failure the audit actually named, an *abandoned* config root whose cleanup never re-runs, because
that root's oldest transcript walks straight past the horizon and the assert goes red.

## Two safety rules every adapter obeys

1. **Liveness outranks age.** An unanswerable liveness question is a KEEP. This repo has already
   reaped live operator conversations once (2026-07-24) by deciding on age alone.
2. **`kill -0` is not an identity oracle.** With ~30 concurrent `claude` processes a recycled pid
   lands on another `claude`; measured 2026-07-25, all 28 watchdog pairs pass both `kill -0` and a
   `comm=claude` check. The pin that works: a process whose **start time is later than the
   pidfile's mtime** cannot be the process that wrote it.

Both rules are RED-proven in `tests/cc-gc.bats` — every reaping test is a discriminator pair whose
two fixtures differ by exactly the predicate under test.

## Deploying it

Two different deploy paths, and the difference is the whole of K26:

- **Existing files** (`scripts/autonomy-sweep.sh`, `hooks/session-index-sweep.sh`) are already
  per-file symlinks into the checkout, so their new legs go live on the operator's ff-sync with no
  further action. Their launchd jobs (`com.chrisren.autonomy-sweep`,
  `com.claude.session-search-sweep`) are already loaded — verified.
- **New files** (`cc-gc.sh`, `scratchpad-reaper.sh`, `worktree-gc.sh`) are linked by nothing. A
  brand-new tracked file is never symlinked however current the checkout, so it lands inert. That
  symlink is Step 1 of `docs/activation/pending-activation/12-cc-gc-activate.sh`.

Related operator-gated step, already staged separately: `08-session-deregister-activate.sh` (K20,
registry deregister — roadmap item 4's other half).

## Adding a store

Add the adapter to `cc-gc.sh`, add its name to `ALL_STORES`, add a discriminator pair to
`tests/cc-gc.bats`, and add a row above. If the store already has an owner, write an ASSERT that
proves the owner runs — do not write a second deleter.
