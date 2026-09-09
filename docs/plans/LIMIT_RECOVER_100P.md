# /limit-recover — 100th-percentile recovery: the pane IS the continuation

Status: OPEN · opened 2026-09-08 by session b8fcf245 (claude-infrastructure, next)
Operator ruling 2026-09-08, verbatim intent:

> "every session (we provided a screenshot of three sessions) to be located, to then essentially
> conduct a /handoff of us 'self'-closing those sessions, and then within that same pane, to resume
> just as normal onto an account that isn't limit restricted."
>
> "What we have here now is 3 original sessions that are still limit blocked but open and taking up
> visual real estate of our window, and new sessions open and us not being sure which was opened for
> what, and what we should work from, and what we should retire."

Scope (frozen): make `/limit-recover` recover a limit-hit FLEET the way the operator described —
every limited session located, each one continued IN ITS OWN PANE on an unrestricted account, and no
husk, no orphan, and no ambiguity about which pane is which left behind. Research it to 100th
percentile first (the failure is a DESIGN failure, not a missing flag), then implement, gate, land
via the project-local /ship, and converge the live layer.

## 1. What actually happened on 2026-09-08 (the incident this plan is written from)

next2 hit its 5-hour session cap at 23:09Z with three sessions live:

| session | pane (orig) | account | work | recovery taken | pane after |
|---|---|---|---|---|---|
| `b418b97a` | 615 | next2 | 12-axis "why sessions idle" wave; 2 of 26 workflow slots NULL | transplanted → next3 | NEW pane 625; 615 left a husk (its TUI later exited to a bare shell) |
| `52e35019` | 616 | next2 | permission-harvest research; zero gaps | left parked; reset poller owns it at 00:50Z | 616 still limit-blocked, and the poller will resume it into ANOTHER new pane |
| `6e29fee9` | 618 | next2 | waiting-recycle arm-gate item, mid-`/ship` | transplanted → next4 | NEW pane 632; 618 left a husk |

Net result the operator saw: **three dead-but-open panes plus new panes of unclear provenance.**
Every individual mechanism worked. The composition is what failed.

## 2. The design defect, stated precisely

`lr-handoff.sh` moves a transcript to another account and then **spawns a NEW pane** for the
successor. The source pane survives as a husk — a window over a transcript that has moved and can
never take another turn (`handed-off-session-guard.sh` now blocks its prompts outright, which is
correct and also proves the pane is finished). `--close-source` exists but (a) needs `--source-pane`
plus a registry pairing, (b) was not used here, and (c) still yields NEW-pane-plus-closed-old-pane
rather than continuity.

The primitive the operator is describing already exists for the SAME-account case:
`handoff-fire.sh --recycle` — exit this pane's session and relaunch **the same pane** with a fresh
context, and since 2026-08-08 it composes with `--worktree`/`--cwd`. What has never been wired is
**recycle + transplant + a different account**: same pane, same session uuid, new account.

So the target behaviour is a `--recycle`-shaped transplant, not a spawn:

    for each limited session S:
        audit S (disk truth) → transplant S's transcript to an account with headroom
        → RECYCLE S's OWN PANE onto that account, resuming the same uuid
        → the pane's title, position and history are continuous; nothing new appears; nothing is left over

## 3. Hard questions the research must answer before any code is written

1. Can a pane whose session is limit-blocked run `--recycle` at all? The session cannot take a
   model turn, but `/exit` is a TUI command and the relaunch is typed into the surviving SHELL — so
   the recycle path may be entirely model-free. PROVE it, do not assume it.
2. Who drives it? A limited session cannot drive its own recovery (it cannot think). Today a THIRD
   session drives, and it does not own the other panes' ttys — `self-close --session-id` refused
   exactly this on 2026-09-08 ("no ancestor of this process owns that pane's tty"). Either the
   driver needs a sanctioned cross-pane path, or the recycle must be armed from inside each pane
   before it dies, or a daemon (the already-live `lr-reset-poller`) must own it.
3. What is the ownership gate protecting, and what is the narrowest carve-out that keeps that
   protection while allowing a driver to recycle a pane whose session is PROVABLY retired (a
   tombstone exists / the guard is already blocking its prompts)?
4. `lr-reset-poller` (launchd, autofire, live) already resumes parked sessions — into new panes.
   Should the poller become the single owner of fleet recovery, with `/limit-recover` a thin front
   end? Two mechanisms doing the same job by different means is half of this incident.
5. Provenance: when a recovery does spawn a pane, nothing tells the operator what it is. The pane
   title, the registry row, and a per-pane "this is the continuation of X" line are all candidates.
   Which one is un-fakeable and survives a recycle?
6. What must a fleet recovery report so the operator never has to ask "which do I work from, which
   do I retire?" — the answer should be that the question cannot arise.

## 4. Constraints (hard)

- The `/limit-recover` iron rules bind: disk-truth audit before any judgment, no partial results,
  re-audit to fixpoint, and **rule 7 — a recovery does not push/ship/deploy**. This plan's OWN
  landing is normal work, not a recovery, so it ships normally.
- Never break the split-brain protections: the tombstone, `handed-off-session-guard.sh`, and
  `lr-resume-tombstone-guard.bats` are what kept today's incident merely untidy instead of
  data-losing. A same-pane recycle must keep every one of them true.
- The capacity-admit gate (`scripts/lib/capacity-admit.sh`) refuses a resume above 2.0 load/core and
  refused one today at 161/10 — a fleet recovery fires N resumes at once and MUST sequence against
  it rather than spending its 3-refusal budget.
- Worktree isolation and the project-local `/ship` (never a bare push, never the shared checkout).

## 5. Already landed / in flight from the incident

- Committed on this branch, NOT yet landed: `fix(lr-handoff): a kitty window is not a resume` —
  `kitty @ launch` exits 0 when the WINDOW exists, so both of today's fires announced "fired split
  pane" over windows that had already closed (their launcher hit capacity-admit's exit 9). Both
  kitty arms now verify survival; `tests/kitty-recovery-launch.bats` 25/25, red-proofed.
  **Land this as part of the first wave.**
- Backlog `d5f1ba09e95a` (closed): the capacity-blocked resume, fired at 23:55Z when load fell to
  1.76/core.

## 6. Status log

- 2026-09-08T23:5xZ · plan opened from the live incident; three sessions recovered by hand
  (b418b97a→next3 pane 625, 6e29fee9→next4 pane 632, 52e35019 parked for the 00:50Z poller).
