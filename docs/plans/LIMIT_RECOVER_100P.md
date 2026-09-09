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

## 7. Research findings (wave of 2026-09-09; artifacts in docs/research/lr100p-2026-09-09/)

Ten axes were decomposed (00-context.md). The capacity gate refused 8 of 10 subagent spawns (9-12
sessions mid-turn > active ceiling 8), so eight axes ran serially on the lead
(lead-serial-findings.md); two ran as subagents (q-survivability-spawn.md, q-relaunch-command.md).
Answers to §3, each MEASURED unless marked:

1. **Q1 — a limit-blocked TUI takes `/exit`.** The corpus holds zero recycles over a limit-blocked
   predecessor (34 recycle rows, none limit-blocked), so the proof is live: pane 616 was blocked
   23:09Z→00:50Z and at 23:57:28Z a queued task-notification was SUBMITTED and RAN a turn (API error
   again) — the input loop, queue and turn machinery are alive; `/exit` is a local slash command on
   the same loop, and the 2.1.260 binary attaches no modal to the session/weekly limit strings. The
   recycle chain is model-free end to end.
2. **Q2/Q3 — who drives, and the carve-out.** A driver (third session or the launchd poller) uses
   handoff-fire's `--recycle` REMOTE FORM: the self-identity gate is REPLACED (never skipped) by the
   registry row binding pane→sid, the transplant tombstone (handed_off_to ≠ the pane's config dir)
   with its lock held, and — because a recycle TYPES — the row's process alive with the pane's tty in
   its ancestry (kitty reuses window ids). Same predicates as self-close's remote form, now ONE copy
   (`hf_remote_source_bind` / `hf_remote_source_pin` / `hf_transplant_evidence`); the gate stays
   byte-identical for a live session (c5f80b8b).
3. **Q4 — the poller.** It is the daemon half of one design, not a rival: the same actuator run
   outside every session and every classifier (401 auto-mode denials in 30 days, shapes no rule
   predicts). Its three live defects are fixed: liveness by registry row + live pid (it resumed
   52e35019 into tmux while pane 616 held the original — `pgrep -f "resume <sid>"` is blind to a
   fresh launch's argv), tombstone-aware parked records, no silent tmux (the tmux copy froze on a
   permission prompt nobody could see; five siblings were alive there for up to ten days).
4. **Ordering** — transplant → `/exit` → relaunch. The tombstone must exist BEFORE a driver types
   into a pane it does not own; a stub the dying process re-creates after the rename is folded into
   `.handed-off` by the watcher once the shell is back. lr-transplant.sh, the guard and the
   tombstone verdict are unmodified.
5. **Spawn shape** — every recovered window is RUNNER-rooted (`bin/cc-pane-runner`: the launcher
   rides in `CC_PANE_CMD`, the window survives a refusal with the message on screen, the pane is
   recyclable next time); `-- /bin/bash <launcher>` is what left panes 625/632 un-recyclable and all
   seven tmux resumes the same. `--cwd=current` needs `--source-window` (without it the successor
   inherited the operator's ACTIVE window's cwd AND title); `--title` is sticky and never passed;
   provenance rides in `--var`. `pane_shell_root` has a false YES on macOS's `login` wrapper —
   filed below.
6. **Tier** — the transcript's last non-error turn BEFORE the limit error, never argv (616: Fable
   xhigh vs argv Opus high); the poller's tier-less launcher had put every unattended Fable
   recovery on Opus/max. `CLAUDE_CODE_TASK_LIST_ID`, `--permission-mode` and the subagent depth
   bound are read off the live process and carried in the launcher / MANIFEST.
7. **Q5/Q6** — with an in-place recycle nothing new appears and nothing is left over, so the "which
   pane" question cannot arise; the fleet report proves it per session (pane before == pane after).
   Registry rows (session-written) and `--var` user_vars are the un-fakeable provenance.
8. **Capacity** — `cc_capacity_probe`, the non-charging read; recoveries run one at a time behind
   it; the 3-refusal budget is never spent by asking.

## 8. Implementation (branch lr100p, 2026-09-09)

- `scripts/handoff-fire.sh` — `--recycle --source-pane P --source-session S --transplanted-source
  --resume-launcher F --resume-cfg D [--resume-cwd] [--await]`; shared predicates; `resume_engaged`
  oracle; watcher args $10-$13 (target cfg, sid, baseline, source transcript to fold); SUPERSEDED
  same-account admission in `hf_transplant_evidence`. Suites: handoff-recycle-remote-resume (30),
  handoff-selfclose-transplanted-source (36), every recycle/self-close suite green.
- `scripts/limit-recover/lr-handoff.sh` — `--in-place`; source-anchored, runner-rooted,
  `--source-window`-pinned spawn; tier/env/permission carry; driver-written HANDOFF-CONTEXT
  (UNRECONSTRUCTED); MANIFEST fields source_argv/runtime_model/runtime_effort/permission_mode.
- `scripts/limit-recover/lr-lib.sh` (new) — tier, engagement-after-baseline, registry liveness,
  transplant read, kitty socket/runner spawn. Suite lr-lib (16).
- `scripts/limit-recover/lr-reset-poller.sh` — registry liveness → NUDGE in place; TRANSPLANTED
  retire; socket-resolved runner-rooted kitty spawn; no silent tmux; tier flags; requests drain.
  Suites lr-reset-poller (LR-m inverted with its reason), lr-reset-poller-inplace (new).
- `scripts/limit-recover/lr-fleet.sh` (new) — `/limit-recover fleet`: locate · recover · one ·
  enqueue · duplicates/--mark · report. Suite lr-fleet.
- `scripts/limit-recover/lr-fire-resume.sh` — `--permission-mode`. `scripts/limit-recover/lr-select.py`
  — registry liveness. `scripts/lib/capacity-admit.sh` — `cc_capacity_probe` (suite capacity-probe).
- `hooks/handed-off-session-guard.sh` — SUPERSEDED tombstone: acquit by process identity
  (`superseded_by_pid`), block every other copy (suite handed-off-guard-superseded).
- `commands/limit-recover.md` — fleet mode + `--in-place`.

Filed (impossibility class `not-yet-true`/needs a launchd reload): `pane_shell_root` login-wrapper
false-yes (two narrow fixes named in q-survivability-spawn.md § The gate has to be fixed too);
launchd `WatchPaths` on the requests dir (plist change ⇒ install step); the seven tmux `lr-resume-*`
orphans and the 616/630 same-account duplicates need the `--duplicates --mark` + self-close pass
once this lands (the poller can never create them again).

## 6. Status log (continued)

- 2026-09-09T02:00Z · research wave fired; 8/10 spawns refused by capacity-admit; 8 axes run serially
  on the lead; 2 subagent artifacts landed. Live finding: 52e35019 running in TWO processes on
  next2 (pane 616 + tmux) — the poller's argv-only liveness; 7 tmux orphans; originator (622)
  containment: tmux copies attached to visible tabs 647/648.
- 2026-09-09T04:xxZ · implementation on branch lr100p: actuator + shared predicates + in-place
  front end + lib + poller + fleet + guard + probe; 11/12 suites green (kitty-recovery-launch: 3
  harness pins being re-pointed at the runner shape); commit + land + deploy-live + E2E on a
  throwaway pane pending — the lead recycled at ~74% context per the desk page; successor continues
  from § 8 and the suite list above.
