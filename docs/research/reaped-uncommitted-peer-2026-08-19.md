# What closed pane B2D1CE68 at 2026-07-30T04:39Z — and why its own safety guard could not fire

Answers the open question of backlog row `b521cb445465` ("UNEXPLAINED ABRUPT SESSION DEATH … WHAT TO
INVESTIGATE: what closed that pane at 04:39Z with no continuation. Check whether any closer ran at
04:39Z."). Recycle #50, 2026-08-19.

**A closer did run: `cc-reaper` reaped it.** Not a crash, not a kernel kill, not the orphan-close
watchdog (which the row had already ruled out on timing). And the reaper was operating exactly as
written — which is the finding, because the guard that exists to prevent precisely this could not
fire for this session, and still cannot.

## The evidence

`~/.claude/logs/cc-reaper.out.log`, the victim's full lifecycle:

```
  healed: gu-worktree-warmpool-B2D1CE68
  keep   gu-worktree-warmpool-B2D1CE68 [active] — never-reap cause
  keep   gu-worktree-warmpool-B2D1CE68 [active] — never-reap cause
  keep   gu-worktree-warmpool-B2D1CE68 [finished-teammate] — idle 473s < settle 600s (self-close still has its chance)
  REAP   gu-worktree-warmpool-B2D1CE68 [finished-teammate] pane=B2D1CE68-EDE6-4232-B40D-D821A12D91FC
```

The transcript's mtime is `Jul 29 21:39` local and its final record is stamped
`2026-07-30T04:39:12.303Z`, which fixes the offset at PDT = UTC-7 and puts the reap and the last
transcript write in the same minute. That final record is a `queue-operation` enqueuing a
`<task-notification>` for background Bash task `bn8c8kjam` — **the session was blocked waiting on
its own background task when it was killed.** There is no `SessionEnd` record in the transcript.

## Why the safety guard did not fire

`bin/cc-reaper`'s reap chain checks, in order:

| line | gate | fired for the victim? |
|---|---|---|
| `:1323` | `[ "$landed" != yes ]` ⇒ `keep … work NOT landed (would strand work) → DEFER` | **no** |
| `:1332` | `idle < SETTLE_S` (600s) ⇒ keep | no — it had accrued >600s |
| `:1342` | 2026-07-24 belt: `finished*` + `! fired_peer` ⇒ refuse | **no** |
| — | REAP | yes |

**The DEFER guard is the one that mattered, and the victim's own log proves it did not fire**: the
`idle 473s < settle 600s` message is emitted at `:1332`, *after* the `:1323` check, so reaching it
requires `landed == yes`.

`landed` comes from `work_landed`, and `work_landed`'s first line is `bin/cc-reaper:842`:

```sh
[ "${ahead:-1}" = 0 ] && return 0        # fast path: 0 ahead by COUNT → landed
```

The victim had made **no commits at all** — the row records it as `ahead=0` and clean, mid-Phase-1,
"with NOTHING landed". So `ahead=0` was true, the fast path returned "landed", and the guard whose
own comment at `:1324` calls it *"unchanged and still the whole safety story"* was structurally
unable to protect it.

**`ahead=0` conflates two opposite states: "committed everything and landed it" and "never committed
anything".** `:1432` describes the reap as resting on *"positive done-evidence, not inferred from
silence"* — but for a session that never committed, `ahead=0` **is** the silence. This is the
indexed `lookup-miss-is-not-absence` shape, and it is still in the tree today.

The 2026-07-24 belt could not help either, and for a symmetric reason: it refuses to auto-reap an
**unstamped** pane, i.e. one that is operator-launched or adopted. The victim was a properly
dispatched peer with a valid fired-peer stamp — precisely the class the belt exempts.

## Why this is worse than it looks: the protection is inverted with respect to the loss

Three sibling sessions in the **same sweep** were saved by the DEFER guard:

```
  keep   wt-ed3e27c06b2f-48774445 [finished-teammate] — work NOT landed (would strand work) → DEFER
  keep   wt-97148f9ea7e2-674270E9 [finished-teammate] — work NOT landed (would strand work) → DEFER
  keep   gu-account-relogin-9B38FF36 [finished-teammate] — work NOT landed (would strand work) → DEFER
```

Every one of them was protected *because it held commits*. Commits are the recoverable case — they
sit on a branch and a later sweep can surface them. The victim held none, so its entire work product
existed only in its transcript, and it was the one session in the sweep with no protection. Its
Phase-1 findings survived only because a human harvested them out of the transcript afterwards into
`docs/ground-up-payloads/row11-worktree-warmpool.md`.

**So the guard is weakest exactly where the loss is total, and strongest where the loss would be
smallest.** A dispatched peer is at maximum risk in the window before its first commit — which is
also the window in which it is most likely to look idle, because it is reading, thinking, or (as
here) blocked on a background task it has no way to report progress from.

## Two indexed laws this incident instantiates

- `shutdown-request-is-not-an-actuator` — *"`idleReason` is a Stop-hook LITERAL painted 'finished'
  every turn ⇒ idle TRIGGERS, never PROVES."* The `[active] → [finished-teammate]` transition in the
  log is that literal being believed.
- `liveness-proxy-cannot-be-output-age` — a session waiting on a background task emits nothing, and
  emitting nothing is indistinguishable from being done under an age-based idle proxy.

## What is NOT claimed here

This does not establish *why* `cc-classify` moved the session from `[active]` to
`[finished-teammate]`; the classifier's input at that moment is not recoverable from these logs. The
reap chain above is sufficient to explain the death regardless of how the label was reached — the
DEFER guard is supposed to be the backstop for a wrong label, and it is that backstop's failure that
is established here. The remedy is filed separately rather than built in this pass, because
`cc-reaper` is a live janitor with real blast radius and the fix needs its own red-proofs: a correct
predicate has to distinguish "never committed" from "committed and landed", which `ahead` alone
cannot do.

## POSTSCRIPT 2026-08-20 — the belt was built against the minority door

*(Drain recycle #63. The belt landed 2026-08-19 across `4e4c0f3f4` / `ab22990a1` / `d99841243`, and
for its first day it protected a population that is not the one this document is about.)*

The belt's gate read `cause =~ ^(finished|finished-teammate)$`. That is the cause set of **one** of
the two doors into the reap path. A **dispatched peer** — the thing this incident is about, and the
thing backlog `7c22e9b43956`'s own title names — does not come through that door at all:

- `cc-classify` labels a desk-fired peer **`finished-shared-review`**, which is in `SURFACE_PAGE_RE`,
  not `REAPABLE_RE`.
- It reaches the reap path through the **T-P3-4 promotion** (`AUTOREAP_FIRED_RE`, `bin/cc-reaper:243`),
  which sets `promoted=1`, and the disposition gate is written `[ "$promoted" = 0 ] && ! [[ "$cause"
  =~ $REAPABLE_RE ]]` — so a promotion bypasses the reapable-cause requirement entirely.
- The belt never consulted `$promoted`. All four legs were therefore skipped for exactly the
  population they were built to protect, leaving `work_landed`'s 0-ahead-by-silence fast path
  load-bearing there with nothing behind it.

**Measured on the live reaper log, not reasoned.** Over the 7 days to 2026-08-20 (99,502 lines,
2026-08-13T01:03Z →) the classifier emitted six causes across ~2,106 session-sightings:

| cause | sightings | reachable by reap? |
|---|---:|---|
| `crashed` | 788 | never (by design) |
| `finished-operator` | 528 | never (by design) |
| **`finished-shared-review`** | **467** | **yes — via promotion; UNBELTED until this fix** |
| `coordination-hang` | 247 | never (by design) |
| **`finished-teammate`** | **71** | yes — belted since 2026-08-19 |
| `task-less` | 5 | never (by design) |

The other two `REAPABLE_RE` causes — `finished` and `coordination-abandoned` — were emitted **zero
times in seven days**. So the belt shipped measured against the minority door, by a factor of ~6.6.

**Reproduced end-to-end** rather than argued (`tests/cc-reaper.bats` B11): a 0-commit,
never-announced, desk-fired peer labelled `finished-shared-review` reads `1 classified · 1 safe
candidate(s) · 1 reaped`, `cc-teardown` is invoked, and the worktree is **removed** — this
document's death, on the majority path, on unmodified trunk.

**The fix is a widening, not a re-scope**, and that is the whole safety argument: every belt leg can
only refuse-and-continue or fall through, so admitting a population can convert a reap into a
surface and can never do the reverse. B12 is the discriminator that keeps it from degrading into
"never auto-reap a desk-fired peer" — a promoted peer that DID commit still reaps, so the
confirm-close pile-up T-P3-4 exists to drain stays drained. Mutant-checked: forcing the
never-committed precondition true reds B12 and leaves B11 green, so neither case is vacuous.

**A third indexed law this instantiates** — `guard-proxy-fails-in-both-directions` is the near miss,
but the exact one is **`span must equal its subject`**: the guard's span (`finished|finished-teammate`)
was narrower than its subject (*the dispatched peer*), and nothing in the suite could see the gap
because **every** B/C/G fixture entered through the belted door. A suite that only ever builds
fixtures on one branch of a two-branch gate cannot discover the other branch is unguarded.
