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
