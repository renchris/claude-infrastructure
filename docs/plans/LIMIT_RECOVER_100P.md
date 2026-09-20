---
status: open
---

# /limit-recover — 100th-percentile recovery: the pane IS the continuation

Status: COMPLETE 2026-09-10 (see § 6 continued, last entry) · was OPEN · opened 2026-09-08 by session b8fcf245 (claude-infrastructure, next)
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
- 2026-09-09T05:xxZ · successor (session 2c24bdb5, worktree lr100p) ran the 18-suite gate as ONE
  bats root. 22 red, and the "3 harness pins" above turned out to be **four defects, three of them
  in shipped code** (commit `68302d9e1`). They are recorded here because each is a rule, not an
  incident:
  1. **`lr_resume_procs` was in its own population.** `ps -axo command= | awk -v s="--resume $sid"`
     puts the search string into awk's OWN argv, and the concurrently-started `ps` prints it, so
     `index($0,s)` matched awk itself — the census answered YES for **every sid ever asked about**.
     `--locate` called a one-pane session DUPLICATE and a no-pane session RESUMING; lr-select
     retired parked records as `already-running`. The sid rides in the environment now. Red-proof:
     the old form returns the awk pid for a sid nothing holds; the new one returns nothing.
     (Generalises memory `pgrep-excludes-the-callers-ancestors` — pgrep excludes itself, a
     hand-rolled `ps | awk` does not, and nothing in this repo said so.)
  2. **One session, counted twice.** A resume runs under `bin/cc-close-attrib`, which stays alive as
     the PARENT of the real `claude` and carries the whole command line in its argv. Measured live:
     `--duplicates` called `b418b97a` a split brain over pids 16125 (wrapper) and 16212 (child) —
     one pane, one session — and its printed prescription was to retire a LIVE pane. The census
     keeps only leaves: a pid that is the parent of another matched pid is the launcher.
  3. **The NUDGE arm was unreachable code.** It sat BELOW the winner contest, and lr-select's
     liveness census counts a live registry row as already-running — so the one sid the arm exists
     for was filtered out of candidacy and retired as `LISTED … already-running` before the nudge
     was reached. This is why `lr-reset-poller-inplace` was red as a whole suite rather than in one
     case. The arm now runs ABOVE the contest (with its own headroom + per-run guards) and a
     registry-live sid is dropped from the SPAWN pool so it cannot take a winner slot from a session
     that needs a process. The contest still bounds every spawn — it bounds resurrections, and
     typing into a pane that is already open is not one.
  4. `gone -- '<pat>' "$log"` passed `--` as the pattern and the pattern as a nonexistent filename,
     so that assertion could only ever FAIL — it never tested the runner shape at all.
  Harness, same run: three fixtures were keyed on the incident's **live** sid (a tmux
  `claude --resume 52e35019-…` has run since 00:51Z), so the real process table answered questions
  the fixture's own registry row was meant to answer — tails zeroed, the `52e35019` prefix kept for
  legibility. lr-fleet's ACCT pins asserted the config-dir basename where the repo's own
  `lib/account-map.generated.sh` resolves `next2`. LR-o reaches the `LRP_TMUX_BIN` ladder through an
  explicit `LR_POLLER_SPAWN=tmux` now — reaching it through a failed GUI re-pins the silent fallback
  LR-m deleted this wave.
  **Gate: 326/326 across the 18 suites, 0 failures** (`/tmp/lr100p-gate-5.log`), plus 3 new
  argv-census cases in `tests/lr-lib.bats`.
- 2026-09-09T05:xxZ · live mess, audited: the seven tmux orphans are now **six** (94d58849 is gone).
  Two are the contained pair (52e35019 → tab 647, 0edc7e64 → tab 648). Four are sole copies, each
  idle for days and each with **0 unlanded commits** in its worktree — 1bd8904c
  (sevenrooms-bridge, last turn 2026-09-05), 3c4bdc06 (claude-infrastructure, 2026-09-06), 609597db
  (claude-infrastructure, 2026-08-30), 9e3074fc (personal, 2026-08-29). Filed one operator row each
  with the exact `tmux kill-session` command (`fae2b2d87a4d`, `09d6dff0e45f`, `2322c93da80e`,
  `45424ff78f85`): killing a live session from a session is classifier-blocked, and the poller can
  no longer create these. `--duplicates` after fix 2 above shows exactly one genuine duplicate,
  52e35019 (pane 616 pid 80874 started 21:20 vs the tmux resume pid 77720 started 00:51).
- 2026-09-09T06:xxZ · **E2E on a throwaway pane — it FAILED, and the failure is the plan's own §5
  finding with teeth.** A real claude session was launched in a fresh kitty OS-window (pane **687**,
  next4/`.claude-quaternary`, sid `d10a5ab1`), took one real turn, then was recovered with
  `lr-handoff.sh --launch --in-place --source-pane 687 --target next3` from this worktree. The
  transplant succeeded, the remote in-place recycle armed and typed correctly, the watcher confirmed
  the pane at a shell prompt in 3s — and then:
      lr-fire-resume: unknown arg --permission-mode
  twice, 90s apart, while the watcher waited for a claude process that could never appear. Outcome:
  **pane 687 a tombstoned husk whose session had already moved** — the exact composition failure §1
  was written from, reproduced by us.
  **Cause, exactly.** `lr-handoff.sh` sets `LR="$HOME/.claude/scripts/limit-recover"` deliberately —
  the launcher outlives the worktree, so it must name a durable path — so the launcher execs the
  **live** `lr-fire-resume.sh`, and the live layer is 25 commits behind trunk. Measured on the two
  copies: `--permission-mode)` parser arms — live **0**, worktree **1**; all four other flags 1-2 in
  both. So this feature CANNOT work until `deploy-live` advances, and that is the `🚀` rung's whole
  point: a landed EDIT rides its symlink and merely runs older bytes, which here means a flag the
  older bytes reject. `deploy-live` refuses today (no GREEN stamp within 200 commits — the standing
  `trunk-red`/`deploy-wedged` pair; T2's degrade budget at 25/25 commits, 1h49m/6h, not yet
  breached). Filed as an operator step, `24f84b0c0c5e`.
  **Fix taken (Follow-On Gate F1-F4 PASS, conviction ~92%).** `lr-handoff.sh` now PREFLIGHTS the live
  parser: before the transplant — i.e. before the first irreversible step, which is the property that
  matters — it asserts `$LR/lr-fire-resume.sh` carries a parser arm for every flag this script can
  emit, and refuses with exit 5 naming the missing flags and the convergence command. Kill switch
  `LRH_LIVE_PARSER_CHECK=off` for the two suites whose lr-fire-resume stub is a bare argv printer
  (they pin argv COMPOSITION, a different subject). Cases both ways in
  `tests/lr-handoff-launcher-quoting.bats` (13 refuses and asserts no transplant ran; 14 is the
  control). Without this, the driver's only signal was a line inside a detached watcher log, 90
  seconds after the session had already moved.
  `Scope (grown): +the live-parser preflight — a recovery must refuse before it moves a session when
  the layer it will execute cannot run what it is about to write.`
- 2026-09-09T06:4xZ · **E2E RE-RUN AFTER CONVERGENCE — VERIFIED.** The live layer advanced (live
  checkout `9c9687fcf`; both ADDED files linked under `~/.claude`; the live `lr-fire-resume.sh` now
  carries the `--permission-mode)` arm — checked BY CONTENT, not by the lag counter, which read 25
  then 4 without either file appearing in between: memory `convergence-counter-measures-distance-not-delivery`).
  A second throwaway session was launched in a fresh kitty OS-window (pane **695**,
  next4/`.claude-quaternary`, pid 16191, sid `f62a9f70`), took one real turn, and was recovered with
  `lr-handoff.sh --launch --in-place --source-pane 695 --target next3`. Result:
      → recycle VERIFIED: relaunched + ENGAGEMENT CONFIRMED in 695 (a real assistant turn, not just a process)
  | measurement | before | after |
  |---|---|---|
  | kitty window id | 695 | **695** (same window, `kitty @ ls`) |
  | registry account | claude-quaternary | **claude-tertiary** |
  | registry pid | 16191 | **70964** |
  | registry sid | f62a9f70 | **f62a9f70** (unchanged) |
  | assistant turns in the TARGET store | 1 (source copy) | **6**, newest 06:42:42Z — after the move |
  Total kitty windows unchanged by the recovery: nothing new appeared, nothing was left over. This
  is §2's target behaviour, measured: *the pane IS the continuation.*
  `tests/handoff-recycle-remote-resume.bats`: **30/30, 0 failures.** Full 18-suite gate: **326/326.**
- 2026-09-09T06:5xZ · **The live mess, resolved as far as the sanctioned rails allow.**
  · `52e35019` — `--duplicates --mark … --live 77720` wrote the SUPERSEDED tombstone, so the stale
    pane 616 can no longer take a turn: **the split brain is contained.** The pane RETIREMENT
    refused, correctly: `self-close` verifies a live claude on the successor pane's OWN tty, and
    647's claude is tmux-NESTED (ttys045 vs the pane's ttys049), so the check cannot see it. Not
    "fixed" — that check is one of the protections this wave is forbidden to weaken, and the
    tmux-nested successor is a CLOSING population (the poller can no longer spawn one). Filed
    `653e8214d505` with the exact close command.
  · `0edc7e64` — self-resolved: pane 630's pid is DEAD, so its registry row is stale and there is no
    duplicate. Only the tmux copy in tab 648 remains, and it is the live one.
  · the four sole-copy orphans — filed one row each (above), all idle for days with 0 unlanded
    commits.
- 2026-09-10 · **CLOSED** (cc-backlog `775afca94edc`, the plan-open row). Re-read against trunk:
  every § 8 deliverable is on `origin/main` by content, the E2E above is the acceptance, and all six
  rows this wave filed are `done` (`24f84b0c0c5e` converge; `653e8214d505` pane 616, gone per
  `kitten @ ls`; `fae2b2d87a4d` `09d6dff0e45f` `2322c93da80e` `45424ff78f85` tmux orphans, gone per
  `tmux ls`). The remainder was the two items § 8 lists as "Filed" — and **neither was ever filed**:
  no backlog row mentions `pane_shell_root` or `WatchPaths`. Disposed this pass:
  · `pane_shell_root` login-wrapper false-yes + ppid-1 detritus — **DRIVEN**, both narrow fixes from
    q-survivability-spawn.md § "The gate has to be fixed too", in `scripts/handoff-fire.sh`. Red-proof
    in `tests/handoff-recycle-pane-survives.bats` § 3b: 4 cases red on the pre-fix tree (P5's
    login→sleep census, expect + detritus, detritus alone, login with no child), the pane-634
    runner and bare-zsh controls green on both. Detritus and childless login ABSTAIN (`unknown`)
    rather than count as non-shells, so the gate's affirmative-only refusal polarity is unchanged.
  · launchd `WatchPaths` on the requests dir — **DROPPED**. `lr-fleet.sh` already prints the
    `launchctl kickstart` that runs the poller at once, the 600 s tick bounds the rest, and a plist
    change is an operator reinstall that `launchd-parity-lint` reads as drift until it is run: an
    operator step to buy ≤10 min of latency on a path that already has a manual accelerator.
  This file had no frontmatter, so `find-plan.sh --status` read `unknown` and the plan-open
  falsifier could never fire; `status: complete` is what lets it retract.

## 9. REOPENED 2026-09-19 — the n=5 production run refutes "complete"

`status: complete` rested on n=1 (one throwaway, one-turn-old, self-spawned pane on a quiet box — U09).
The first production run — five sessions limit-killed on next4 between 11:58 and 12:20 — measured
**98.7 min wall for 5 sessions, 1 RECOVERED / 4 PARTIAL**, and the one success was bought by a
two-day-old refusal counter that happened to sit at 2. Full corpus: `docs/research/lr100p-2026-09-19/`
(14 research units, 3 designs, 9 critiques, synthesis in `PLAN_DRAFT.md` — the waves below are its
ordered output; every number is cited there).

### Phase 0 — Agent orchestration (execution locus per wave)

| wave | locus | why |
|---|---|---|
| W1, W4, W6a (Round A, independent) | **W** — workflow agents, `claude-opus-5`/high, one pre-created worktree each off `feat/limit-recover-100p` | **S is refused on a measurement**, not a feeling: at 21:10Z `claude-accounts --rank general` => `none` (next weekly-exhausted · next3 5h-cutoff · next2/next4 kmax-concurrency); teammates take the same admission gate. Workflow agents take no pane, their tool output stays out of the lead's window (the property S exists to buy), and ultracode prescribes them. Opus not Fable: 5.1 rewrites whole files for small edits and `handoff-fire.sh` is 12,383 lines. |
| W2 → W3 (serial; W2 needs W1, W3 needs W2) | **W**, same terms | both edit `handoff-fire.sh`'s recycle region — one writer at a time |
| W5 → W6b, W7 | **W**, same terms; **S** if the admission gate admits by then (re-measure, never assume) | W5 fans across poller + hook + transplant + two new bins |
| lead | merges each wave into `feat/limit-recover-100p` (rebase + ff), runs the wave's own suites + shellcheck, lands via the project `/ship` from `wt-lr-100p`, converges. **Never the shared checkout** (`.claude/CLAUDE.md`; this lead violated it once today and paid 7.7 min for a permission prompt) | lead context budget: hold ≥50% for merge judgment; succession point = after Round A lands (recycle, same pane) |

Merge order: smallest diff first; every wave's bats suite + `shellcheck` green in the lead's worktree
before its land; no wave lands over a red sibling. Iron rule 7 is unchanged throughout — nothing in this
work lands a *recovered* session's work.

### Measured baseline (the "before" column)

| | measured |
|---|---|
| wall, 5 sessions | 98.7 min (146 tool calls, 68.8 min inside them) |
| identify | `lr-fleet --locate` 40–86 s (2,579 transcripts × tail+2 greps = 61.1 s); statusline carries no pane/sid; panes 122/124 render byte-identical |
| invoke | every fire blocks the invoking turn: 658 s park + 5 × ~2.5 min; screenshots queued 13.5 / 38.1 / 35.2 min behind those turns |
| engaged | 1/5, and that one falsely (oracle satisfied by the harness's own `Continue from where you left off.` / `No response requested.`); ingest prompt reached 0/5 target transcripts |
| husks | 4/5: watcher makes exactly 2 relaunch attempts (`handoff-fire.sh:6811,6815`) vs a 3-refusal budget (`capacity-admit.sh:581`) — release needs a 4th evaluation, so under load the in-place recycle CANNOT succeed by arithmetic |
| gate split | driver probes non-charging with the load term OFF; the relaunch is typed into the pane's own zsh (`lr-handoff.sh:586-593` exports two vars) and re-gated CHARGING with the load term ON — structural, not per-term: after `226b73888` the 8-session next3 event still refused on the ACTIVE term in the launcher |
| detection | `hooks/stop-failure-marker.sh` recorded all five sub-second (first 3 min before the first `/limit-recover`) into `~/.claude/autonomy/stop-failure/` — zero consumers; the reset poller parked all five 128 s before the operator acted and waited for 2:40pm by design (`lr-reset-poller.sh:896`) |
| target | ranker has no weekly gate; `next` at 2 pp weekly was a legal pick and hit 100 % 1 h 54 m later |
| ingest | bought zero information on 5/5 (`gaps_at_handoff: 0` in every bundle); ~26.5 K resident tokens and 6–9 round trips per session for one verifiable line |

### Waves (ordered by minutes-saved ÷ lines; full file:function detail and acceptance in `PLAN_DRAFT.md` §waves)

| wave | goal | files (anchor, re-grep before editing) | deps | est |
|---|---|---|---|---|
| **W1** | non-blocking invocation + a verdict that reaches someone: `lr-fleet --one … --detach` returns ≤3 s; verdict via `cc-notify` mailbox; the silent no-process arm (`handoff-fire.sh` "relaunch typed but no claude process appeared") writes a `recycle-dead` row + `hf_alarm` + IDL-joined `term=` + real elapsed + a pane-tty paint | `scripts/lib/detach.sh` (new, lifted from handoff-fire `detach()`), `lr-fleet.sh` (lf_one), `handoff-fire.sh` (that arm), `commands/limit-recover.md` front section | — | 90 |
| **W2** | ONE admission decision; nothing irreversible before every refusable read: corrected probe mints a one-shot TTL-300 sid-enforced token; `lr-fire-resume` redeems it call-scoped (`env -u` on spawn); per-RUN budget key; `lrh_precheck()` before the transplant (registry bind · `lr_last_api_error` kind=limit · teammate head · pane_cc_state==cc · composer EMPTY) refuses with nothing moved; boot wait becomes a 0.5 s loop on positive discriminators (`relaunch.rc`, IDL row, `cc_alive`), timeouts INDETERMINATE, no retype | `capacity-admit.sh`, `lr-lib.sh`, `handoff-fire.sh` (new read-only verb `--probe-recycle-preconditions`; boot wait), `lr-handoff.sh` (precheck; launcher heredoc exports `LR_RUN LR_RUN_DIR LR_ADMIT_TOKEN LR_SUBMIT_TOKEN LR_LOAD_TERM`), `lr-fire-resume.sh` | W1 | 240 |
| **W3** | RECOVERED = submitted then engaged: `lr-submit-probe.sh` (submitted\|queued\|none from the TARGET transcript, run token); `resume_engaged` requires an assistant record AFTER the token record; dead `esc to interrupt` oracle deleted; quiet pty ⇒ loud READY-NOT-SEEN, never a blind CR; `lr-ingest-verify.sh` fast path inside the launcher (1 round trip, ≤0.2 K resident) fails closed when a subagent was killed | `lr-fire-resume.sh` expect block, `handoff-fire.sh` resume_engaged, two new scripts, `lr-handoff.sh` | W2 | 200 |
| **W4** | identity in the pixels + a resolver that refuses: statusline `⌗<pane> <sid8>` left-anchored (+1.2 ms/render); `bin/cc-find` (pane/sid8/tuple/keyword/--limited; teammate rule 0; liveness by (pid,lstart); REFUSES within 12 pct points); `--one` resolves registry/store FIRST, census only on a miss; DUPLICATE subtracts registry pids | `statusline.sh`, `bin/cc-find` (new), `lr-fleet.sh`, `lr-lib.sh` | — | 180 |
| **W5** | the request lane + state readers + one actuator per pane: StopFailure ARM 2 writes `requests/<sid>` atomically (write-then-latch, teammate/tombstone skip, `CC_SF_REQUEST=off`); poller claims per-sid and drives OFF its lock (hook-originated only under `autorecover.on`); read-only REAPER names every non-terminal run past its bound; retire only on RECOVERED or a live target registry row; lock gains custody so a re-limited target can hop; `bin/cc-lr` (find/recover/status/repair) and `scripts/lib/cc-tui.sh` | `hooks/stop-failure-marker.sh`, `lr-reset-poller.sh`, `lr-transplant.sh`, `bin/cc-husk-sweep`, `bin/cc-lr` (new), `scripts/lib/cc-tui.sh` (new) | W1–W3 | 300 |
| **W6a** | ranker recovery lane: `--recovery` floors (weekly ≥ 90 excluded; 5h projected ≤ 0.60; fable floor 0.05); POLICY-classed reasons so an all-thin fleet exits 2; `CC_ROUTE_RECOVERY=off` byte-identical | `bin/claude-accounts`, `accounts.json .router`, `tests/account-recovery-lane.bats` | — | 110 |
| **W6b** | fleet pool: rank→assign→probe→mint under `flock`, pool of `LR_RECOVER_MAX_CONCURRENT=2`, empty rank parks with the router's own reasons | `lr-fleet.sh`, `handoff-fire.sh` `--assign` guard | W5, W6a | 60 |
| **W7** | census as one Python pass (0.148 s vs 40–86 s); `tests/lr-drill.sh` — the operator-launched DoD instrument (5 throwaway sessions, fault arms a–e); command doc rewritten around `cc-lr` | `lr-fleet.sh` lf_locate, `tests/lr-drill.sh` (new), `commands/limit-recover.md` | W5 | 180 |

### DoD (a diff against the operator's target; the drill in W7 is the instrument)

- identify < 2 s from a screenshot tuple / pane id / sid8 / keyword, REFUSING a tie — `time bin/cc-find …`, `tests/cc-lr.bats`
- one command (`cc-lr recover <ref>` or `/limit-recover <ref>`) = one Bash call; the turn ends ≤ 5 s; verdict via `cc-notify` — `grep -c 'until \[' commands/limit-recover.md` = 0
- engaged in place on the recovery lane's target: p50 ≤ 45 s, max ≤ 90 s idle; loaded ⇒ ENGAGED ≤ 300 s or a NAMED `PARKED:capacity:<term>` with nothing moved; same kitty window id, same uuid
- every failure named ≤ 30 s (`FAILED:gate:<term>` ≤ 3 s via `relaunch.rc`; unsubmitted prompt ≤ 40 s or `queued`), every terminal arm = events row + alarm + pane paint + notify; `cc-lr status` ≤ 0.1 s; re-drivable under the one-actuator rule
- zero silent husks in the 5-session drill; every recycle-intent has a terminal row (today 7/15); a held draft refuses BEFORE the transplant with no lock and no tombstone
- no teammate touched (cc-find rule 0, precheck, hook skip); no recovered work landed (iron rule 7 — `grep -c 'git \(commit\|push\|merge\|reset\|checkout\)'` over the recovery scripts = 0)
- ≤ 0.2 K resident tokens and 1 round trip on the gaps-0 ingest path; HANDOFF-CONTEXT ≤ 2 KB

### Dropped, with reason (full list in `PLAN_DRAFT.md` § dropped)

`CC_ADMIT_NET_ZERO` (double-discounts with `226b73888`; patched one of two `act + 1` sites; leaked into every hook of the recovered session) · the watcher retype (re-runs the same command against a counter advanced by one) · expect exit-code verdicts (an exit before `interact` kills the TUI) · quiet-pty blind CR (takes a parked menu's default) · per-run keystroke watchdogs (two actuators on one pane) · `cc-lr … &` from the hook (child reaped before its own setsid; inherits the session id) · `statusLine.refreshInterval: 5` (+0.28 core, buys nothing — liveness is (pid,lstart)) · the never-released global lock as the already-moved guard · WatchPaths (race-prone per Apple; QueueDirectories) · unbounded `--all` (N probes mint N tokens; pool of 2 + flock).

### Open decisions (genuine operator value-forks — everything else is decided above)

1. **Auto-recover policy (spend).** Should a session limit transplant with no human in the loop? Shipped default OFF — `~/.reso/limit-recover/autorecover.on` absent; the hook still writes the request so `cc-find --limited` is instant and the one command needs no census. Flip = `touch` that file after two clean drills. Conviction the lane is safe ON: 85 % pending fault arms (b)/(c) — below 90, so it is the operator's.
2. **Thin-account policy.** When the lane excludes every account, park until the source resets (today 2 h 41 m) or admit the least-thin for its last ≤ 10 %? Shipped default PARK with the router's reasons. Conviction 80 % — an hour of a thin account against an hour of a parked session is a value call.

### Status log (§9)

- 2026-09-19 21:2xZ — reopened by session 11569d45 (itself limit-killed on next3 mid-research and transplanted in place to next2; post-ingest audit NO GAPS, 25/27 workflow slots survived on disk, 2 re-run). Corpus committed. Round A (W1 ∥ W4 ∥ W6a) firing as workflow agents in pre-created worktrees.
- 2026-09-19 23:1xZ — **Round A gated and landing** (W1 4 commits · W4 5 · W6a 2 · +1 suite rebuild). Reports: `docs/research/lr100p-2026-09-19/reports/W{1,4,6a}.md`. Gates in the lead worktree: lr-lib · statusline-identity · cc-lr · account-recovery-lane · lr-fleet (39/39) · handoff-recycle-remote-resume · claude-accounts-core · account-cliff-routing · claude-accounts-schema-drift all green; shellcheck -S warning clean; py_compile ok. One merge defect found and fixed: the W4-over-W1 rebase conflicted on `tests/lr-fleet.bats` (both appended cases) and git aligned the two waves' identical closing lines as a common suffix below the marker, so a keep-both resolution left W1(a) unterminated (`bats-gather-tests` red) — rebuilt as base + W1 tail + W4 tail after proving both pure appends (`cd87025a5`). Lesson: verify a merged bats file with `bats --count`, never a `grep -c '^@test'` fallback. W1 residuals carried: a detached `verdict=RECOVERED` is ARMED not ENGAGED until W3; `scripts/lib/detach.sh` is an ADD ⇒ converge after landing. Live facts at the time: the poller's request lane is ACTIVE (a sibling, `be39c489`, enqueued 5 recoveries this hour; results rc=4/rc=2 — the husk arithmetic and precheck classes W2 removes); three next4 panes (7f533f05 · eb77ca3e · 7730a605) are parked `kind:weekly` until 2026-09-20T09:00Z while next3 holds 97 % session headroom — the missing transplant arm (W5), to be driven with the fixed chain as W2's real-world check; pane 111 (09e64dcb) had no parked record at all (retired as TRANSPLANTED this morning, blind to its new limit — the custody-less lock, W5) and was nudged by hand after next3 refilled. `cc-find --limited` measured 5.5 s on the live box against a 2 s spec — W7's census pass.
- 2026-09-19 23:5xZ — **five recovery attempts, five DIFFERENT causes** (session 12e163a9, itself transplanted next4→next3 mid-run). Recorded because the plan's own DoD asks for "every failure named ≤30 s", and no single fix reaches these: **(1)** held composer draft — the rail correctly refused to type `/exit` over an operator's unsubmitted text (pane 147), leaving a tombstoned husk; **(2)** engagement window — `relaunch typed but no claude process appeared within 90s` on a box at load 40+, i.e. the window was too short, not the relaunch wrong; **(3)** box capacity — `cc_capacity_probe` refused 15× at 4–5/core against ceiling 2.0, correctly (bats was 0–5, NOT a gate pile-up: the "15 ship-lands" that suggested one was a pgrep PROCESS count inflated by ship-land's wrapper + its re-exec'd locked child); **(4)** account capacity — `--rank general` returned **none**: next/next4 weekly-exhausted, next2/next3 kmax-concurrency, so "no routable target" was a TRUE verdict, not a missing-binary artifact (`~/bin/claude-accounts` exists; `lr-fleet.sh:71` hardcodes that path against the command doc's own "resolve from PATH, not ~/bin" warning — worth aligning, but it was not the cause); **(5)** transplant residue — `lr-transplant: REFUSED — <target>/…/<sid>.jsonl already [exists]`, because an earlier attempt had already placed the record there. (5) is the one this plan should absorb: **a retry against a session whose record ALREADY sits in the target store needs a resume-in-place path, not another transplant**, or every retry after a partial attempt is refused by construction.
  - Operational note for the next driver: `fleet --enqueue` writes requests the poller CONSUMES — five were drained and all five failed, after which nothing retries. A consumed request that failed looks identical to one never filed (`a-reader-that-cannot-prove-delivery-must-not-consume`). Re-enqueue is manual today.
  - Also landed from this session: `226b73888` (a limit-killed turn never writes its turn-end beat, so blocked panes counted mid-turn forever and inflated the very admission ceiling gating their own recovery — the deadlock had no supported escape, `--from-daemon` takes the same probe) and `362811da6` (the land gate's `command -v shellcheck` is a claim about PATH, not the host; it gate-killed a land on a box carrying a working `/opt/homebrew/bin/shellcheck`).
  - **Correction to (5), same session, 00:0xZ — it is not "residue", it is a BACKWARDS route into a tombstoned source.** Census of `07e30aeb` across all five stores: `.claude-secondary` (next2) holds the authoritative transcript at **1,157,520 B**; `.claude-tertiary` (next3) holds a **5,339 B** stub plus a `.jsonl.handed-off` tombstone; the lock reads `from .claude-tertiary → to .claude-secondary` (20:49Z). So next2 is the session's correct home. The poller then attempted **next2 → next3** — undoing that move — because `--rank` walked past next2 (kmax-concurrency) and next3 was the only routable account, and `lr-transplant` refused since the destination still held the old file. **That refusal was protective**: it stopped a 5 KB stub from shadowing a 1.1 MB transcript. Two things follow, and neither is "add a resume-in-place path" as (5) first suggested: **(a)** a transplant target that already holds a `<sid>.jsonl.handed-off` tombstone is this session's OWN retired source — the router must exclude it as a destination, not merely refuse on arrival; **(b)** when a session's home account is at kmax, the correct action is to WAIT for a slot in place, never to relocate it to the store it was transplanted out of. Falsifier for (a): `ls <target-cfg>/projects/*/<sid>.jsonl.handed-off` non-empty ⇒ that account must not be chosen as the target for that sid.
- 2026-09-19 23:5xZ — **Round A LANDED** `1b2676f4c → origin/main` (16 commits, 20 paths content-verified, sweep clean). Four gate rounds to get there, each a different ratchet stopping at its first red: (1) rebase conflict with a sibling's `5fe4c9f84` — the same DUPLICATE defect W4 fixed, done better as the shared `lr_holder_count`; resolved in the sibling's favour, W4's three behaviour cases hold against it. (2) test-hermeticity: the two suites Round A EXTENDED each pinned one capacity gate and not the other (`b669e3aae`). (3) pipefail-SIGPIPE: two `grep -q` consumers in `bin/cc-find`'s keyword arm (`6e9b316af`). (4) `cc-lr.bats`' 0.3 s judge fired at 1.98/core, a hair inside a 2.0 band that is the capacity gate's refusal line, not a quiet-box line — judged band lowered to 1.0/core (`acebfcfc4`); then one DNS-only push failure, re-shipped on a two-green probe. Lesson filed: `docs/lessons/keep-both-on-appended-blocks-leaves-the-first-unterminated.md`. W2 returned with 5 commits while this landed.

### Reconciliation with `docs/plans/LIMIT_DETECT_100P.md` (2026-09-20 00:1xZ)

A sibling — session `7f533f05`, pane 150 — landed `LIMIT_DETECT_100P` at 23:44Z (`c62af4338`) with THIS
plan's research corpus as its wave 1 and its own detection research (`docs/research/lr-detect-2026-09-19/`)
as wave 2. It does not cite this § 9 and its waves assume nothing of Round A exists. Its scope line
draws the boundary itself: *"nothing here types into a pane, drains a request, moves a session"*
— detection, identification, surfacing; the recovery chain is "carried as R1–R11, not designed here".
So the split is by construction, not negotiation:

| theirs (`LIMIT_DETECT_100P`) | ours (this plan) |
|---|---|
| W0 predicate SSOT (`lr_predicate.py`) · W1 StopFailure hook arm (pane, `kind:limited` beat, one page per cause) · W2 `bin/cc-limited` + reaper + faults · W3 census consumers (`lf_census`, poller delegation) · W4 the twelve predicate copies · W6 drill | W2 admission token + `lrh_precheck` + boot wait (in flight) · W3 submit/engage/ingest · **W5 narrowed** to actuation: poller claim/drive-off-lock, custody lock, `bin/cc-lr` front, `scripts/lib/cc-tui.sh`, husk-sweep — the REAPER and the hook's request/page writer are theirs, W5 consumes their `faults/` · W6b pool · **W7 census item DROPPED** (their `lf_census`); W7 keeps the drill + doc |

Already landed here that their waves assume absent — their lead re-anchors on trunk before firing:
the statusline identity segment (`statusline.sh`, their W5 — done; glyph switched to `#` on their
`fc-list` finding: Monaco carries no U+2317), `bin/cc-find` (resolves ONE session from pane/sid8/tuple/kw,
plus `--limited` — their `cc-limited` enumerates the fleet; both stay, and `--limited` should consume
their W0 predicate once it lands), `--one` registry-first, `lr_holder_count` (`5fe4c9f84`), `--detach`
+ the named `recycle-dead` arm, the `--recovery` lane. One design conflict, theirs to rule: their
`kind:limited` beat vs this synthesis's drop of it (double-discount with `226b73888`); their § 4.3
argues the shim cannot double-subtract and keeps both for a measured week — acceptable, provided the
W2 token path never reads the beat (it does not). Message sent to `7f533f05` via cc-notify (drains when
that session is recovered — it is one of the three next4 panes parked until 09:00Z).
- 2026-09-20 00:3xZ — **SUCCESSION BRIDGE** (lead 11569d45 at 73 % fill, recycling in place). STATE ON DISK: trunk `1b2676f4c` = Round A, LIVE (`LIVE_SHA` matches, both ADDs linked, statusline copy current). Unlanded on `feat/limit-recover-100p` (worktree `~/Development/.worktrees/wt-lr-100p`, gates green): `460465f00` the keep-both lesson (hook lint clean), `775499d06` the LIMIT_DETECT_100P reconciliation (both plans), `aa4b2f924` the `#` glyph (statusline-identity 28/28, cc-lr 15/15). **W2** is on branch `lr100p/w2` (worktree `wt-lr-w2`, 6 commits from `6a6f9a129`: capacity-admit token + per-run key · lr-lib probe + state log · lr-handoff precheck + leak-free launcher · lr-fire-resume redeem + relaunch.rc + env -u · handoff-fire `--probe-recycle-preconditions` + positive-discriminator boot wait · a duplicate of the landed suite brace fix `15f8d5054` — DROP that one at rebase); its agent (`wf_3e1667c1-a38`) was writing `reports/W2.md` when the lead recycled — if the report is absent, derive it from the six commit bodies. **SUCCESSOR, in order:** (1) `git -C wt-lr-w2 rebase feat/limit-recover-100p` (conflict on `tests/lr-fleet.bats` ⇒ take feat's), ff-merge into `wt-lr-100p`; (2) gates: `bats tests/{capacity-admit,launcher-quoting,handoff-recycle-remote-resume,lr-relaunch-bound,lr-fleet,lr-lib}.bats` + `shellcheck -S warning` on every touched .sh (retry on rc 75; never the full suite); (3) `bash scripts/ship-land.sh` from `wt-lr-100p` (expect one ratchet at a time; the land gate is admission-exempt); (4) converge is kicked by the land — confirm `LIVE_SHA` via `wrap-ledger.sh --machine`, else `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`; (5) **W2's real-world check = the three next4 panes** parked `kind:weekly` until 09:00Z: `lr-fleet.sh --one 7f533f05 --target next3 --source-pane 150 --detach` (the LIMIT_DETECT_100P lead — recover it FIRST so it can read the reconciliation mail), then `eb77ca3e`/pane 159 and `7730a605`/pane 167 — the verdict must arrive as peer mail with `verdict=`, no husk, no hand-typed prompt; a PARTIAL here is a W2 defect, not a flake; (6) fire **W3** per `PLAN_DRAFT.md § waves → W3` with anchors from `reports/W1.md` + `reports/W2.md`, Opus 5 xhigh, worktree off the merged tip, same rules block as W2; (7) W5 as NARROWED in the reconciliation. Open decisions unchanged (autorecover policy · thin-account policy). Do not touch `LIMIT_DETECT_100P`'s waves — theirs.

- 2026-09-20 00:2x–00:5xZ — **A SIXTH cause, and it is the one that makes the other five invisible: the census cannot SEE a husk.** Session `c26162f3` (next3, pane 198) was asked "/limit-recover" and reported `0 RECOVERABLE … nothing owed`, which was true about owed WORK and false about the fleet the operator was looking at: three panes (110 `c0f857b6` reso-web-app · 126 `c301b7a5` claude-infrastructure · 150 `7f533f05` wt-cc-143333-63422) sat rendering afternoon `weekly limit` errors the whole time. Measured causes, in the order they bite:

  **(6a) `lf_locate`'s predicate is keyed on the SESSION's last assistant word, and a husk's session has moved on.** `lr-fleet.sh:~205` requires the limit record to be the last non-`No response requested.` assistant turn — its own comment: *"a session that took a real turn since is not blocked."* All six transplants of 17:23–17:39 left successors that kept taking turns on next3, so every one of those sids drops out of the census **entirely**. The predicate answers *"did this session's last turn die at a limit?"*; the operator's question is *"can this pane do work?"*. A husk is precisely where those diverge: the pane is dead, the session is not. `--duplicates` uses a different predicate and found all three instantly — so the tool already HOLDS the evidence its own census discards. **Fix direction: `--locate` must enumerate PANES (registry × live pid), not only transcripts, and emit a `HUSK` disposition for a live pane whose session carries a `handed_off_to` tombstone pointing elsewhere.** A husk is not "not blocked" and not "recoverable" — it is *retirable*, a third state neither existing row models.

  **(6b) the in-place contract was not merely skipped — the successors cannot satisfy its gate.** All six successors were spawned as bare `--resume` processes on fresh ttys under `bin/cc-close-attrib` (parents 9401/31972/41431), each as its own kitty window titled `recover-<sid8>` (181–186), rather than by recycling the source pane. So `handoff-fire.sh self-close --transplanted-source` ABORTS on every one, at the successor-liveness gate (`handoff-fire.sh:~6487`): for `7f533f05` it resolved successor pane 186 → pid 41639 → `/dev/ttys042`, while 41639 actually owns `ttys043` (`/dev/ttys042` belongs to an unrelated kitty shell). Pane 186's registry row carries `pid` and `session_id` but **no `tty` and no `pane` field at all**. The gate is RIGHT to refuse — closing on an unproven successor strands both panes — but it means the husk can never be retired by the sanctioned path, and nothing else is watching. **Fix direction: whatever writes the registry row must record the tty it actually owns, and the gate should prefer `pid → ps tty` over a pane→tty lookup that can name a different window's shell.**

  **(6c) `--recover` would have parked them anyway.** At census time `--rank general` returned `none` (next/next4 weekly-exhausted; next2/next3 `kmax-concurrency` at `k_work` 16 and 13 against `KMAX=8`) — the same true-verdict class as (4) above. Worth recording that this is NOT the `KMAX`/`KMAX_RESIDENT` confusion `accounts.json` warns about: `k_src=work`, so the ACTIVE instrument was charged against the ACTIVE cap, correctly. It cleared on its own ~40 min later (`k_work` 6) without intervention.

  **(6d) method warning — `--duplicates --mark` is the WRONG instrument on a transplanted session, and it BREAKS the retire path.** This session ran `--mark` on all three, believing it the fix. `--mark` writes a *same-account duplicate* tombstone into the TARGET dir; each session already had a correct cross-account transplant tombstone in its SOURCE dir (`handed_off_to`, `target_transcript`, `lock`; ts 22:23–22:30Z). Two tombstones then trip `self-close`'s own guard — *"more than one transplant tombstone … disambiguate by hand"* — so the mark converted a blocked retire into a refused one. Reverted by deleting only the three files carrying `written_by: c26162f3…`; verified back to exactly one tombstone per session, distinct inodes (NOT a config-dir mirror artifact — `.claude`/`.claude-next` mirror, `.claude-tertiary` does not). **Reserve `--mark` for the genuine two-live-processes-one-account case; a session with a `handed_off_to` tombstone is already disambiguated.**

  **Residual left open:** the three husk panes are still up. Verified-safe retire program at `/tmp/husk-panes-retire.sh` (proves tombstone + successor-transcript freshness + successor window alive, then gated `kitty @ close-window --match id:N`, then reads back from a FRESH `kitty @ ls` rather than the close's own return). Backlog `45cc39bf65c3`. Filing note: that row was first filed with no `--run`, so `cc-do 45cc39bf65c3` failed with *"judgment, not a step"* — a worksheet handed over as if it were a program, the exact § Manual-Command-Delivery defect; `--run` added afterwards.
- 2026-09-20 01:0xZ — **W2 LANDED** (`e364bed23`, then `bdb1a4553` for the defect below), converged, live-verified. Session `a4241557`, successor to `11569d45`. W2's own implementer (`wf_3e1667c1-a38`) died with its parent's recycle before writing a report; `reports/W2.md` is DERIVED from its six commit bodies, with every suite re-run by this lead on the merged tip rather than quoted. Rebase dropped its duplicate of the landed brace fix. Gates: capacity-admit 27/27 · coverage 17/17 · launcher-quoting 21/21 · handoff-recycle-remote-resume 36/36 · lr-relaunch-bound 4/4 · lr-fleet 41/41 · lr-lib 24/24 · launcher-temp-hardening 10/10 · probe-preconditions 5/5; shellcheck clean.
  - **Six land rounds, each one ratchet, and three of them were real defects rather than lint.** (1) test-hermeticity: both suites W2 added pinned neither capacity gate, and `lr-relaunch-bound` ran against the live `~/` — the same class as Round A's `984f3c7d1`. (2) the ratchet only shrinks: closing the gate obsoleted `launcher-quoting`'s own `EMBEDDED_ADMIT_ALLOWLIST` line. (3) **pipefail/SIGPIPE — a correctness defect, not a style one:** `cc_up_cheap()` (`ps … | grep -qE '^-?(claude|node)'`) and the probe's teammate test (`head -c 8000 … | grep -q '"agentName"'`) both read FALSE **on a match**, so the boot wait's one positive discriminator could never fire and a teammate transcript read as not-a-teammate. Every suite was green over both. (4) dead-assertion: six sites; the fixer revived three and DECLINED three `A && B || { diag; false; }` composites — those DO fail under errexit (measured), but each non-last conjunct's failure is absorbed into one shared diagnostic, so two states demanding opposite reads arrived identical; split, and verified in both directions with an anchor mutant. (5) a rebase conflict with a sibling's status entry, resolved keep-both.
  - 🚨 **THE HEADLINE DEFECT, found by running the thing rather than testing it.** W2's read-only probe answered `REFUSED:no-transcript` for pane 174 / `75c7e2a5` — a session `cc-find` had just resolved as LIMITED. Narrowing `CC_PROJECTS_DIRS` to the one root holding it produced the correct `limit: kind=limit … REFUSED:pane:unknown`. Cause: `for _f in ${CC_PROJECTS_DIRS:-…}/*/"$SID".jsonl` — `${LIST}/*/x` is ONE word before field splitting, so the literal suffix attaches only to the LAST element and every earlier root expands to a bare directory no `[ -f ]` can match. **Four of five config roots invisible ⇒ `lrh_precheck` refused ~80% of recoverable sessions.** It fails CLOSED, so it cost no data — it made recovery impossible, which is the husk's outcome reached from the safe side. **A SECOND site carries the identical idiom and is NOT W2's:** `subagent_dir_for_sid` (`:4849`), which the recycle gate asks whether the dying session still has live subagents — "none" for every session outside the last root would let a recycle proceed over in-flight work. Both fixed. **No suite could have caught it: with ONE config root the broken and correct forms are identical, and every fixture in the tree has one** (`docs/lessons/fixture-shape-hides-address-bugs.md`). `tests/handoff-probe-preconditions.bats` is new, fixtures TWO roots with the subject in the FIRST, and is also the probe verb's first direct test at all — the only thing naming it in `tests/` was a stub of the whole binary.
  - **Step 5's population had already moved, so it was re-measured rather than re-fired.** The bridge's three parked next4 panes are not recoverable subjects: `7f533f05` (the LIMIT_DETECT lead) recovered ITSELF onto next3 as pane 186 (one live claude, pid 41639, fable-5.1 xhigh), leaving pane 150 as a stale registry row that still reads LIVE — a shape their reaper should know about, and mailed to them. `cc-find --limited` now returns 5 sessions, **all DEAD**, and `claude-accounts --rank general` routes **nowhere** (next/next4 weekly-exhausted, next2/next3 kmax-concurrency), so `lf_one` parks at `lf_pick_target` before ever reaching the new precheck. What WAS driven is the check that needs no capacity and no target: the read-only probe against four real panes, live. After the fix it classifies `kind=limit` correctly on sessions in `.claude-tertiary` AND `.claude-next` and refuses at `pane_cc_state` with nothing moved, in **0.16 s**, tree byte-identical. The full in-place arm still owes a live limited session with a routable target.

## 10. IN-PLACE BY DEFAULT — the root of cause 6b is measured, and it is not the successor gate (2026-09-20 01:1x–02:0xZ; stage 1 of a Fable 5.1 → Opus 5 ladder, session 59681f3c, worktree `lr-inplace`)

Operator's words, verbatim: *"recover split panes in place so we are never at this confused middle case of
untouched limited original sessions being resumed elsewhere in a new session."*

`Scope (grown): +/limit-recover recovers a limit-blocked session IN ITS OWN PANE BY DEFAULT — same kitty window id,
same session uuid, new account — from every driver (an attached session, a detached fleet run, the launchd poller);
a pane whose session has moved is a named, retirable state; the bare spawn survives only where there is no pane.`
Receipts for every claim below: `docs/research/lr100p-2026-09-19/inplace-default-2026-09-20.md` (commands + outputs,
all read-only). Stage 1 wrote documents only; the stage-2 brief is `docs/research/lr100p-2026-09-19/STAGE2_BRIEF.md`.

### 10.1 What stage 1 verified live — 6a–6d re-run, and the seventh cause underneath 6b

- **6a CONFIRMED.** `lr-fleet.sh --locate` (16 rows) lists none of panes 110/126/150; `--duplicates` finds all three.
  The three panes still render the afternoon's weekly-limit error with **empty composers**, and their **original
  claude processes are alive** (pids 95369 / 48984 / 17221, registry rows intact) — so `/exit` was never typed into
  any of them. The census predicate (`lr-fleet.sh:199`) is the reason, exactly as §6a says.
- **6b — the in-place path WAS taken, and it was refused at a gate that has never once passed from a detached
  driver.** The bundle manifests prove the request (`MANIFEST.json`: `source_pane:"110", in_place:true`, ts
  22:23:37Z; likewise 126 at 22:26:57Z and 150 at 22:30:34Z), driver session `be39c489` (pane 178). The transplant
  succeeded; the remote recycle then printed
  `!! --recycle REFUSED: pane 110 resolved to no tty — the terminal does not enumerate it, so nothing can be typed into it.`
  and `lr-handoff` exited 4 ("the transplant is DONE … tombstoned husk"). **Mechanism, traced and reproduced:**
  `handoff-fire.sh:9247` runs `pin_term_verdict_for_watcher` BEFORE the remote pin (`:9260 hf_remote_source_pin`). Had `cc-in-kitty` answered rc 2 (UNVERIFIABLE) nothing would be pinned (`:1699`) and `kitty_identity` would fall through to `in_kitty`, which the orphan's inherited env satisfies — the failure is specific to the DEFINITIVE no, which is what makes W8's target exact.
  That function (`:1686-1700`) asks `bin/cc-in-kitty` about the **driver's own ancestry**; the driver was
  `nohup bash lr-handoff.sh … &` from a Bash tool call that returned at once, so it was reparented away from kitty;
  `cc-in-kitty:101` reads "reached launchd without meeting kitty" as a DEFINITIVE not-kitty (rc 1) →
  `export CC_TERM=iterm2` (`:1697`) → `kitty_identity` (`:991`) is false → `_as_tty_query` (`:1561`) takes the
  iTerm2 osascript branch → iTerm2 is not running → empty → `hf_remote_source_pin` (`as_tty` at `:2037`, the refusal at `:2039`) reports "no tty".
  Reproduced from this session: `cc-in-kitty` rc 0 attached; **rc 1 from a process reparented off kitty with
  `KITTY_WINDOW_ID=198` and `KITTY_PID=73832` intact in its env.** Population: the identical refusal in **9 of 9**
  daemon- or detached-driven in-place attempts on record (2026-09-10 ×3, 09-14 ×2, 09-19 ×4; `results/<sid>.json`
  `requested_by` names the poller's drain for the first six), each rc 4 = a tombstoned husk before W2. The launchd
  poller has no kitty ancestor by construction (`cc-in-kitty:75` → rc 1), and W1's `--detach`
  (`scripts/lib/detach.sh`, `start_new_session=True`) orphans the **fleet** path by default. **So the in-place
  recycle has never succeeded from the fleet or the daemon; the one measured success (pane 695, 2026-09-09) was
  driven from an attached session's foreground Bash call.** W2's probe (`:7478-7483`) now runs the same pin before
  the transplant, so post-W2 the fleet path refuses `REFUSED:pane:unknown (tty <unresolved>)` with nothing moved —
  no husk, and no recovery either.
- **6b, successor half, CONFIRMED as stated.** `pin_still_live` (`handoff-fire.sh:3463-3470`; `:3472-3493` is `pid_is_cc`, a different function) compares the pinned
  pid's tty to the PANE's tty by **equality**; a resumed successor runs claude on expect's nested pty (pane 186: pane
  tty `ttys042`, claude `ttys043`), so a PINNED successor is judged DEAD. `hf_remote_source_pin` (the walk at `:2041-2046`)
  already walks **ancestry** for the same question. Registry rows carry no tty field at all (fields: paneUUID, name,
  cwd, account, pid, startedAt, session_id, surface, lstart). Successor windows 181–185 have **no row** — they are
  bare `kitty @ launch --type=os-window --hold --title recover-<sid8> bash -c 'for i in 1 2 3 4 5 6; …'` windows the
  driver improvised at 22:35–22:39Z from lr-handoff's rc-4 manual-fallback line, after first running the launcher
  from a Bash tool (which killed each session with the tool call — `docs/lessons/engaged-is-not-running.md`).
  No `--var` provenance, no registry row, no watcher: nothing on the box can prove or retire them.
- **6c CONFIRMED** as a true verdict: five `parked · no routable target` rows at 22:35–22:38Z and again at 00:24Z.
- **6d CONFIRMED.** `--mark` writes `<tx>.HANDOFF.json` beside the TARGET copy (`lr-fleet.sh:692-695`); its only existence check
  (`:693`) is keyed on that same target-store path, so a `handed_off_to` tombstone in the SOURCE store is never seen;
  `hf_transplant_evidence` (`:2081`) refuses on two.
- **Also measured.** `--duplicates` prints a sid once per registry row (7f533f05 twice). `LIMIT_DETECT_100P`'s state
  table settles a re-engaged session as RE-ENGAGED → "none" and models AWAITING-ENGAGE only for the not-yet-engaged
  transplant, so **the husk — a live row on the death account whose session is engaged elsewhere — is a hole in BOTH
  plans' state models**; `bin/cc-husk-sweep` models the other husk (a bare shell over a dead session), not this one.

### 10.2 The decision (conviction 93 %) and why the fix is not where 6b first pointed

In-place becomes the **default** of every path that has a pane to recycle; the bare spawn survives only as the
NO-PANE fallback and as an explicit `--spawn`. It is not deleted: a session with no live pane has nothing to
recycle. The **remote pane's terminal is decided by enumerating the pane** — an integer id that a live kitty socket
lists is a kitty pane; a UUID is iTerm2 — never by the driver's ancestry, which is the wrong subject: "which
terminal am I in" and "which terminal owns pane P" are different questions, and the remote form only ever asks the
second. `cc-in-kitty` is left exactly as it is: its DEFINITIVE-no is correct for the genuine-iTerm2 case it was
built for (2026-08-05), and softening it would re-open that incident. The husk becomes a state with an actuator.
The successor gate reads ancestry, as its sibling already does. `--mark` refuses what it cannot disambiguate.

### Phase 0 — Agent orchestration (execution locus per wave; stage 2 is Opus 5 in THIS pane per the ladder brief)

| wave | locus | why |
|---|---|---|
| W8 (Round B) | **T** — teammate under the stage-2 lead, `claude-opus-5`/high, own worktree off trunk | the ladder brief pins Agent Teams in this pane; W8 is the root fix and every later wave's precondition |
| W9a ∥ W10-census (Round B, parallel with W8) | **T** | disjoint files (`lr-fleet.sh`, `lr-lib.sh`) — no writer shared with W8 |
| W9b → W10-actuator ∥ W11 (Round C) | **T** | W9b edits `handoff-fire.sh` and must follow W8 (one writer on that file at a time, §9 rule); W10-actuator needs W9b's gate; W11 needs W8 to be true |
| W12 (Round D) | **T**, or **L** for the live acceptance only | the drill is one command whose numbers the lead compares; retiring the three live husks is the lead's read-out |
| fallback | **W** — workflow agents in pre-created worktrees, as Round A ran | `cc_capacity_probe` refused at plan time (load 39/46/44 on 10 cores against 2.0/core); re-measure at fire time — a refused teammate spawn is a PARK, never a retry |
| lead | merges smallest-diff first, runs each wave's suites + `shellcheck -S warning` in its worktree, lands via the project `/ship` from its own worktree, converges (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, never `--force`); **never the shared checkout** | context budget ≥ 50 % for merge judgment; succession point = after Round B lands (`--recycle`, same pane) |

Brief discipline: ≤ 150 lines, anchors below re-grepped before editing, "Stop on issue, message lead" verbatim, no
investigate/explore language. Iron rule 7 unchanged: nothing here lands a recovered session's work.

### Waves (W8–W12 continue §9's numbering; anchors at `8b5db5947`, re-grep before editing)

| wave | goal | files (anchor) | deps | est |
|---|---|---|---|---|
| **W8** | **remote-pane terminal identity.** New `hf_remote_pane_term P` in `handoff-fire.sh`: P integer ∧ a live kitty socket enumerates window P ⇒ `export CC_TERM=kitty CC_TERM_KITTY_TO=<sock>`; P a UUID ⇒ `CC_TERM=iterm2`. Sockets come from `kitty_sockets` (`:1181-1201`, substitutes per live kitty pid) + `kitty_socket_answers` called DIRECTLY — never `kitty_headless` (env-gated at `:1127-1128`, the opposite of "the driver's env is irrelevant") and never `kitty_socket_template` (unsubstituted). THREE return codes, because absent and wedged have opposite remedies (`:1500-1511`): 0 resolved · 1 `REMOTE-PANE-ABSENT` (a socket answered and lists no such window — terminal) · 3 `REMOTE-PANE-RESOLVER-UNAVAILABLE` (no socket answered / rc 124 — park, retry). The export is process-global and is inherited by the detached watcher (`detach()` passes no `env=`, `:1615-1620`), so the `__recycle` re-exec's own pin returns at `:1687`; `:11838` and `:11983` inside `recycle_fire` are therefore no-ops by inheritance — leave them. Invariant to assert, not inherit: every terminal write after `:9247` targets P. Called by the remote recycle form (`:9247`, before `pin_term_verdict_for_watcher`, which then returns at its first line), by `self-close --source-pane` (`:7560`) and by `--probe-recycle-preconditions` (`:7478`). The watcher inherits the pinned verdict (it types into P). `hf_remote_source_pin` (`:2036`) reads `as_tty_classified`, not `as_tty`: rc 3 refuses `RESOLVER-CANNOT-TELL` (park / retry), never "no tty". `lr-handoff.sh`: the socket-resolution block (`:893-901`) moves ABOVE the in-place call (`:764`) — this serves the launchd arm only (`:893` is gated on `KITTY_WINDOW_ID` being unset); the orphaned-driver arm (3 of the 9) is carried entirely by `hf_remote_pane_term`'s own export, since the orphan still inherits `KITTY_LISTEN_ON`. Brief constraints from the static judge in `tests/handoff-selfclose-terminal-pin-order.bats:109-126`: do not rename or reshape `SUC_TTY="$(as_tty …)"`, and `hf_remote_pane_term`'s body must not contain the literal `as_tty "` (use `as_tty_classified`). Kill switch `CC_REMOTE_PANE_TERM=off` (today's ancestry pin, byte-identical). | `scripts/handoff-fire.sh` (`:1686` pin · `:2024` remote pin · `:7415` probe · `:9247` recycle) · `scripts/limit-recover/lr-handoff.sh` (`:764`, `:893`) · `tests/handoff-remote-pane-term.bats` (new) | — | 150 |
| **W9a** | `--mark`'s existing check (`:693`, target store only) widens to every `lr_config_dirs` root in the shape `hf_transplant_evidence:2068-2078` already uses, refusing when a `handed_off_to` tombstone exists anywhere for the sid (names it; "a transplanted session is already disambiguated"); `--duplicates` dedupes by sid | `scripts/limit-recover/lr-fleet.sh` (`:692-695`, `:699-716`) · `tests/lr-fleet.bats` | — | 30 |
| **W9b** | `pin_still_live` proves liveness by **ancestry** — the pane's tty appears in the pid's ancestor chain (≤ 12 hops, the walk `:2041-2046` already uses) — keeping `pid_is_cc` and pid liveness strict. Two fixtures, because no suite pins either direction today (`grep -rn 'pin_still_live\|tty_now' tests/` = 0): LIVE — a pinned pid on a nested pty whose ancestor owns the pane tty (today DEAD); still-DEAD — a pid on an unrelated tty with no ancestor owning the pane tty. Callers that inherit the widening: `successor_pin:3455` (via `:2351` and the self-close gate `:8062`) and the `__selfclose` close-instant re-verify `:6482` | `scripts/handoff-fire.sh` (`:3463-3470`) · `tests/handoff-selfclose-transplanted-source.bats` (+2 cases) | W8 (file) | 40 |
| **W10** | **HUSK is a state; retiring it is an actuator.** Census: `lf_locate` gains a pane-first pass (registry × live pid, `lr_registry_live_rows`) that emits `HUSK` for a live row on account A whose sid carries a transplant LOCK with `to` ≠ A (`lr_transplanted_to`, `lr-lib.sh:450-459`, reads `locks/<sid>.lock` and never a tombstone — a same-account `--mark` writes no lock and cannot match) AND no in-flight recycle for the sid (no live `__recycle` watcher for that pane, no `handoffs.jsonl` row younger than `LR_HUSK_MIN_AGE_S`, default 900 s = the `--await` bound; the lock is never deleted, so age alone is not the guard) — evaluated BEFORE the last-assistant-word filter, so a moved session cannot drop out, and gated on the in-flight conjunct so a recovery in its `/exit`→relaunch window is never read as a husk; the same row is proposed as a **binding amendment** to `LIMIT_DETECT_100P` § 3 W0's state table (HUSK above RE-ENGAGED: `live row on acct_death ∧ (tombstone to ≠ acct_death ∨ a real assistant turn after death.ts under another account)` → next action `--retire-husks`) and recorded in both plans. Actuator `lr-fleet.sh --retire-husks [--pane P] [--yes]`: lifts `/tmp/husk-panes-retire.sh` (tombstone present · successor copy has an assistant turn after the tombstone ts · successor process alive by registry row or `lr_resume_procs` leaf · the husk window exists) → when a successor PANE is known, `handoff-fire.sh self-close --transplanted-source --source-pane P --source-session S --successor <pane>`; when the successor is a bare resume window with no row, the direct gated `kitty @ close-window --match id:P` under the same proof → read back from a FRESH `kitty @ ls`, never the close's return. Poller: at the `TRANSPLANTED … parked record retired` arm (`lr-reset-poller.sh:~903`) a live source-account row for the sid logs `HUSK` and writes a retire request. Kill switch `LR_HUSK_RETIRE=off`. | `lr-fleet.sh` (`:186` lf_locate, new arm) · `lr-lib.sh` (`:226`, `:450`) · `lr-reset-poller.sh` (`:902-904`) · `commands/limit-recover.md` fleet section · `tests/lr-fleet.bats`, `tests/lr-lib.bats`, `tests/lr-reset-poller-inplace.bats`, `tests/handed-off-session-guard.bats` | W9b (self-close path) | 160 |
| **W11** | **the default flip.** `lr-handoff.sh --launch` implies in-place whenever a pane is resolvable: self (`--sid` == `$CLAUDE_CODE_SESSION_ID` and `$KITTY_WINDOW_ID`/`$ITERM_SESSION_ID` present) or driver (`--source-pane`, else `lr_registry_live_rows $SID` → its pane, refusing on > 1). New `--spawn` = today's split/os-window path, explicit. The implied pane is resolved into `SOURCE_PANE` BETWEEN the end of argv parsing (`:225`) and `lrh_precheck` (`:631-633`), because the precheck probes the pane only when `SOURCE_PANE` is set (`:588`) — the ordering invariant that makes "nothing moved" true at all. Automatic fallback to spawn ONLY on NO-PANE and on the launcher-rooted REPLACE class (`:799-807`); every refusal from `lrh_precheck` (`:585-630`, called at `:632`, before the transplant at `:641`) parks with nothing moved — never a silent spawn. Stated honestly: REPLACE and the rc-4 arm (`:809-814`) both run AFTER `"$HF" "${RCY_ARGS[@]}"` at `:791`, so on either the session HAS moved and a tombstone exists; their disposition is a retry (`lr-fleet.sh --one <sid> --source-pane P`) or `--retire-husks`, never a park. `lr-transplant.sh` becomes idempotent on a same-target retry at BOTH refusal sites — `:55-57` (`$DST already exists`) and `:63-66` (`lock exists`) — returning rc 0 `already transplanted` when the lock's `to` == target ∧ the target copy's sha/size ≥ the source copy (`:97` is the source-retirement guard and is unrelated), so a retry after rc 4 / PARTIAL re-drives the recycle. The rc-4 text (`:809-812`) stops prescribing a hand-spawn and prescribes `lr-fleet.sh --one <sid> --source-pane P` (retry) plus `--retire-husks`; the improvised `recover-<sid8>` os-window is documented as forbidden. `--in-place` stays accepted (no-op); `--close-source` stays for `--spawn`. Kill switch `LR_INPLACE_DEFAULT=off`. Doc: handoff mode rewritten, default first. | `lr-handoff.sh` (`:203-240` flags, `:764-814`, `:830-1010` spawn) · `lr-transplant.sh` (`:55-57`, `:63-66`) · `commands/limit-recover.md` (`:420-452`) · `tests/lr-handoff-launcher-quoting.bats`, `tests/lr-handoff-close-source.bats`, `tests/lr-resume-tombstone-guard.bats`, `tests/lr-transplant.bats` (new) | W8 | 120 |
| **W12** | drill arms (f) the recovery driven from a `detach`ed driver AND from `launchctl kickstart` of the poller — same window id, same uuid; (g) a seeded transplant-husk → `--locate` shows HUSK → `--retire-husks` closes it and a fresh `kitty @ ls` proves it. Live acceptance: panes 110/126/150 retired by the W10 actuator (or the seeded husk if the operator's script closed them first). | `tests/lr-drill.sh` (§9 W7) · `commands/limit-recover.md` | W10, W11 | 60 |

### DoD (extends §9's; the drill is still the instrument)

- an in-place recovery driven from a detached process, a Bash tool call, or the launchd poller recycles IN PLACE —
  same kitty window id, same uuid, new account — **today 0 of 9**; the drill's arm (f) is the receipt
- `--locate` names every live pane whose session has moved as `HUSK` in one pass; `--retire-husks` closes it and
  proves it from a fresh `kitty @ ls`; the post-run census shows `0 HUSK` and `--duplicates` prints nothing (the
  in-flight conjunct in W10 is what keeps this from flaking against arm (f) — a recovery mid-relaunch is not a husk)
- `handoff` mode with no flags leaves no husk and spawns nothing when a pane holds the session
- a PINNED successor on expect's nested pty is verified alive (the 186 class) — today refused
- `--mark` on a transplanted session refuses with the reason; no session ever carries two tombstones
- every negative control named in W8 stays byte-identical: `tests/handoff-selfclose-kitty-identity.bats:121-196`,
  `tests/handoff-selfclose-terminal-pin-order.bats:140-219`, `tests/handoff-fire-kitty-daemon.bats:182-271`,
  `tests/cc-in-kitty.bats`; iron rule 7 unchanged (`grep -c 'git \(commit\|push\|merge\|reset\|checkout\)'` over the
  recovery scripts = 0)

### Kill switches and backward compatibility

| switch | restores |
|---|---|
| `CC_REMOTE_PANE_TERM=off` | the driver-ancestry pin for remote panes (today) |
| `LR_INPLACE_DEFAULT=off` | spawn-by-default for `handoff` mode (today); `--in-place` still opts in |
| `LR_HUSK_RETIRE=off` | census only — `HUSK` rows print, nothing closes |
| `LRH_PRECHECK=off`, `LR_INPLACE_AWAIT`, `CC_TRANSPLANT_SOURCE_CLOSE` | unchanged from W2 / §8 |

Compat: the fleet and poller paths already pass `--in-place`, so their flags do not change; `--in-place` is a no-op
on the new default; `--close-source` keeps its meaning under `--spawn`; every existing tombstone, lock and guard is
read, none is rewritten; the registry row gains no field (the ancestry walk needs none — and `session-register.sh`
is `LIMIT_DETECT_100P` W1's file, single owner).

### Open decisions (operator value-forks; everything else above is decided)

1. **Should `--spawn` stay reachable on a session that HAS a live pane?** Conviction 75 % keep it (an operator may
   want the limited pane's scrollback beside the successor for a while). Options: (a) keep as an explicit flag,
   documented as the exception; (b) remove it, reachable only through `--close-source`. Below 90 %, so it is
   theirs; the waves ship (a) and (b) is a one-line deletion.
2. Unchanged from §9: auto-recover policy (spend) and thin-account policy.

### Dropped, with reason

- softening `cc-in-kitty`'s DEFINITIVE no for an orphan (it would re-open the 2026-08-05 genuine-iTerm2 misroute;
  the orphan case is answered at the remote pane instead)
- a `tty` / `pane_tty` field on the registry row as the gate's oracle (the ancestry walk needs none; the writer is
  the sibling plan's file)
- adopting a bare `--resume` window as a successor on argv alone (no row, no engaged turn ⇒ not proof; the gate's
  positive-proof polarity stays; W10 requires the engaged turn)
- a per-pane HUSK paint in the statusline (theirs — `LIMIT_DETECT_100P` W2c/W5 own the pixels; the census row is
  what they consume)

### 10.3 Critic pass (2026-09-20 02:0xZ) — 17 items, folded as BINDING amendments

A read-only Opus 5 critic re-grepped every anchor and refuted 6 items, partially refuted 10, and let 1 stand
(`docs/research/lr100p-2026-09-19/critique/inplace-default-critic.md`). Every correction is folded into the text
above; the ones that changed a DESIGN rather than an anchor are restated here so stage 2 reads them with the table:

1. **W8 resolver has THREE codes, not two** — absent (terminal) and resolver-unavailable (park) must never share a
   verdict; the same rule W8 imposes on `as_tty` one layer down.
2. **W8 uses `kitty_sockets` + `kitty_socket_answers` directly** — `kitty_headless` is env-gated the wrong way for a
   remote pane, and `kitty_socket_template` cannot enumerate.
3. **W8's static-judge constraints** — `SUC_TTY="$(as_tty …)"` keeps its shape; the new function body carries no
   literal `as_tty "`; `:11838`/`:11983` are inheritance no-ops.
4. **W10's HUSK needs the in-flight conjunct** — the transplant lock is never deleted and the source row stays live
   until the typed `/exit` lands, so a bare lock-plus-live-row reads every in-progress recovery as a husk; the
   predicate reads the LOCK, never a tombstone.
5. **W11's "nothing moved" is the precheck's guarantee only** — anything refused after the recycle call is already
   tombstoned; its disposition is retry or retire, and the plan says so instead of promising a park.
6. **W11 resolves the implied pane before the precheck** — or the default flip transplants without the reads W2 built.
7. **W11's transplant idempotence lands at both refusal sites** (`:55-57`, `:63-66`); `:97` was the wrong line.
8. **W9b ships a still-DEAD fixture beside the LIVE one** — ancestry is strictly weaker than equality on a gate that
   protects a close, and nothing pins either direction today.
9. Four suites added to W10/W11's gates; `tests/lr-transplant.bats` is NEW, not an edit.

### Status log (§10)

- 2026-09-20 01:1x–02:0xZ — stage 1 (Fable 5.1, xhigh): the predecessor's 6a–6d entry applied from
  `~/lr-plan-append.patch`; 6a–6d re-verified on the live fleet; the seventh cause found and reproduced from this
  session (§10.1); waves W8–W12, DoD, switches and decisions written; receipts committed beside the corpus; stage 2
  fired as a same-pane recycle onto Opus 5 with `STAGE2_BRIEF.md`. The three husk panes were left standing for W10's
  live acceptance (`/tmp/husk-panes-retire.sh` remains the operator's manual path; `45cc39bf65c3` is `done`).
- 2026-09-20 02:2xZ — **land REFUSED on two trunk reds that are W2's, not this diff's** (docs-only commit; the gate
  said so). `tests/handoff-alarm-records.bats:323` pins six `hf_alarm` sites and W2 added a seventh
  (`recycle-boot-indeterminate`, `handoff-fire.sh:6923`, sha `eaf7c82da`) without raising the pin — the exact silent
  move that test's comment was written to catch; `tests/handoff-probe-preconditions.bats` lacks
  `export CC_FIRE_HEADROOM_GATE=off`, so the capacity-gate pin-guard names it a new unpinned fire suite. Stage 1
  may not edit code; both ≤ 5-line fixes are step 0 of `STAGE2_BRIEF.md`, and the sibling that landed W2
  (`a4241557`, pane 127) was notified.
- 2026-09-20 02:1xZ — **W2 WAS ADVERSARIALLY VERIFIED AFTER LANDING, AND IT DOES NOT MEET ITS OWN DoD.** Three mutation-testing lenses (`wf_5503904b-6cd`, 750 K tokens, 3 detached worktrees at `cc424132a`, every tree restored and checked) ran against W2's diff. **Why this pass existed at all:** W2 is the only wave in this project whose implementer died before reporting, so it landed on its own tests alone. Every finding below was proved by EXECUTION, not by reading, and 11 of 34 mutants SURVIVED with all suites green.
  - 🚨 **The husk W2 exists to remove was REPRODUCED on the W2 tip.** Every pane- and session-level refusable read in `lrh_precheck` sits inside `if [[ -n "$SOURCE_PANE" ]]`. A/B with one variable: with `--source-pane`, `REFUSED:not-limited`, rc 6, nothing moved; with the flag REMOVED and everything else identical, the transplant RAN and 180 s later handoff-fire printed `The transplant is DONE — the source pane is a tombstoned husk`, rc 4. **Both documented callers can take that path** (`commands/limit-recover.md:430` self-recycle; `lr-fleet.sh:406`'s conditional flag). The ordering fix is real but it is CONDITIONAL, and the report says it is unconditional.
  - 🚨 **The two-gate split is re-created under a new name.** The driver's probe reads `CC_ADMIT_LOAD_TERM` (`lr-lib.sh:331`); the launcher writes `LR_LOAD_TERM` (`lr-handoff.sh:747`). They agree only when NEITHER is set. Executed: `LR_LOAD_TERM=on` yields an IDL row with the load term OFF, admits, and mints a token, while the rendered launcher carries `export LR_LOAD_TERM=on`. W2's own comment — "the SAME switch the driver's probe used, so this is not a different gate" — is false. This is U05 §3.3's defect with different spelling, which is precisely the failure mode lr-lib's one-probe-two-callers refactor was meant to end.
  - 🚨 **The admission token fails four of its five claimed properties.** (1) NOT one-shot: read-with-awk then unlink, so N concurrent redeemers all admit — **40 of 40 trials** on a refusing box, in exactly the five-concurrent-recoveries regime it was built for. (2) A non-integer `CC_ADMIT_TOKEN_TTL_S` makes every token IMMORTAL: `[ -gt ]` errors rc 2 and `if` reads that as a clean false — executed, a token 315,360,000 s old admitted at 9.90/core. (3) The unlink's result is never checked (`rm -f … || true`): in an unwritable dir, or when the token is a SYMLINK (`-f` and `-O` both follow it), the token replays forever with rows indistinguishable from one legitimate redemption. (4) "SID-ENFORCED" is a caller convention — the check is skipped entirely when `CC_ADMIT_WANT_SID` is empty, and `cut -f2` without `-s` returns the WHOLE line when no tab is present, so **any file whose first line is a bare integer is a valid token**. (5) The TTL (300 s) is shorter than ONE stage of the window it must cross (`HF_RECYCLE_SHELL_WAIT_S`=600; handoff-fire sizes the whole window at ~1200 s), and an expired token is silently CONSUMED into a fresh in-pane evaluation — the split, after the transplant, under exactly the load that produces limits.
  - **The probe answers a strictly SMALLER question than the gate.** `--probe-recycle-preconditions` omits `hf_remote_source_pin`, a refusal `--recycle` runs AFTER the transplant on three pre-readable conditions; the verifier drove the probe to `verdict: OK` exit 0 on a dead pid. It also disposes two unreadable-transport states OPPOSITELY — an unreadable PANE is `REFUSED` (exit 5, terminal) while an unreadable COMPOSER is `HELD` (exit 3, retry) — an abstention rendered as a permanent refusal. And the verb documented as changing NOTHING writes ~51 `.pyc` files into `$HOME` through `lr_last_api_error`'s `python3` heredoc (my own read-only test passes only because it is scoped to the project roots — noted there).
  - **Where the suites are decorative, by surviving mutant:** the token MINT itself can be DELETED (21/21 green) · the launcher's `LR_LOAD_TERM` default can be inverted (17/17 + 21/21 green) · the probe's ADMIT arm can be made to refuse everything (green) · discriminators #2 (IDL refusal row) and #3 (claude on the pane) can both be disabled (36/36 green — only `relaunch.rc` has executing coverage, and its case is the load-flaky one) · both halves of the stale-rc guard can be deleted at the seam values the case actually runs · `recycle_await_verdict`'s "reads every stage variable BY NAME" claim is pinned by nothing (a frozen literal passes 4/4) · coverage case 27's BASIS PARITY greps strings anywhere in the FILE including comments, so renaming all nine `fail-open` basis VALUES left it green · the uid (`-O`) check, the sid charset guard and the budget-key path sanitizer have no test at all.
  - **Also true and worth keeping:** `%q` rendering is value-exact against space/quote/backtick/`$( )`/newline across all five exports; there is exactly ONE writer of the launcher heredoc, so the five-export claim holds on every path; the exit-6 path leaves no lock, no tombstone, no fire and an untouched registry row; `FAILED:relaunch` / `STALE:boot` are genuinely pinned at the boot layer — though `recycle_await_verdict:12089` puts them in ONE grep alternation, so one layer up they DO read alike, which is the thing the wave insists must never happen.
  - **Two more, and they are about US, not the code.** `tests/handoff-recycle-remote-resume.bats` case 33 asserts a 3 s walltime with NO load guard and failed twice consecutively on the UNMUTATED tree at load 62 — the identical defect `1b2676f4c` fixed in `cc-lr.bats` one day earlier, re-introduced in a sibling suite. And `W2.md`'s "every suite re-run by the LEAD" listed eight suites and did not include the repo's own `pipefail-sigpipe` ratchet, which was already red — I found that independently at the land gate and fixed it; the lesson is that a wave report's suite table is a claim about WHICH gates ran, and it was incomplete.
  - **Disposition.** `lr100p/w2-admission` (worktree `wt-lr-w2fa`, workflow `wf_535a405f-85b`) is fixing the five token defects and the four decorative axes NOW — capacity-admit.sh is the one file no other wave has open. The `lrh_precheck` conditional (`--source-pane`), the `LR_LOAD_TERM`/`CC_ADMIT_LOAD_TERM` name split, the probe's missing `hf_remote_source_pin`, the HELD/REFUSED transport polarity, the `recycle_await_verdict` alternation and the load-guard on case 33 are queued behind the W3 merge, because W3p owns `handoff-fire.sh` and W3i owns `lr-handoff.sh` until it lands. **None of this is a decision for the operator: every item is a defect with a measured repro and a known fix.**
- 2026-09-20 09:0xZ — **W3 SPLIT INTO TWO BRANCHES, AND THE INGEST HALF FAILED ITS ADVERSARIAL PASS.** W3 was fired as two disjoint writers (`wf_352756f4-f8c`): **W3p** = the oracle (`lr-submit-probe.sh`, the lr-fire-resume expect block, `resume_engaged`), **W3i** = the ingest (`lr-ingest-verify.sh`, the launcher prompt, `session-continue.sh`, `lr-preseed-env.sh`). Disjoint file sets, so they ran in parallel in separate worktrees; both implementers finished (W3p 3 commits + report, W3i 5 + report).
  - **W3i verdict: FAIL**, 37 mutants, **11 surviving**. Its own half's defects: (a) clause D writes into the WRONG config dir, so it can never clear the sentinel it exists for and the only one it CAN reach belongs to a SIBLING; (b) A6 — the flagship `killed_inflight` clause — is FAIL-OPEN when `events.jsonl` EXISTS but carries no such record, which is the state of every bundle once W2's writer is live, and the suite's own CONTROL fixture pins that fail-open; (c) the fail-closed prompt does not carry the run token its report claims; (d) **a REGRESSION this diff caused — `tests/session-continue.bats` is 36/37 at HEAD in any ordinary session**, a suite guarding a hook every session on this machine runs, and its line-100 `grep -q "cleared"` has gone decorative because the REFUSAL text also contains "nothing was cleared"; (e) C5 fails open whenever git cannot evaluate, contradicting the file's own written contract; (f) the sibling-sentinel refusal is keyed on OPTIONAL evidence (`${f}.sid` is written only when `csid` is non-empty), so it fails open on the operator's own sentinels; (g) the receipt prints `PASS D1 — auto-continue cleared: refused — … nothing was cleared`, a label contradicting its own value. Fix wave fired: `wf_3472cd2a-0a3` on the same branch.
  - **The verifier also listed W3p's items as unmet and then caught itself** — it added a SCOPE NOTE naming `PLAN_DRAFT` row C19 as the legitimate split. Worth keeping as method: a verifier handed a spec wider than its subject will report the difference as failure, and the fix is for the BRIEF to carry the split, not for the reader to remember it.
  - **W3p's verifier is still running at ~9 h** (the wave's 4th agent). Not a stall — sampled live, it is generating box load deliberately to test whether W3p's timing assertions are load-flaky, which is the exact defect class the W2 pass found in case 33 and that `1b2676f4c` fixed in `cc-lr.bats` a day earlier. `handoff-fire.sh` and `lr-fire-resume.sh` stay OFF LIMITS to every other wave until it returns.
  - **Three waves are now in flight on disjoint files**, which is the only reason they can run at once: `wt-lr-w2fa` owns `capacity-admit.sh` (`wf_535a405f-85b`), `wt-lr-w3i` owns the ingest set (`wf_3472cd2a-0a3`), `wt-lr-w3p` owns `handoff-fire.sh` + `lr-fire-resume.sh` (verifier). The queued `lrh_precheck` / `LR_LOAD_TERM` / `hf_remote_source_pin` fixes from the W2 pass cannot start until W3p and W3i land, because they touch those same files.
- 2026-09-20 10:1xZ — **W3p's adversarial pass (9 h, 21 mutants) found the defect that makes the wave INERT — and its own suite DEFENDS it.** `handoff-fire.sh:6651` reads `RCY_SUBMIT_TOKEN="${16:-}"` while the submit token is passed as argv **15**, so the watcher never receives it and `resume_engaged`'s token arm can never engage. `tests/lr-fire-resume-submit.bats:162` then asserts `grep -c 'RCY_SUBMIT_TOKEN="\${16:-}"' "$HF"` **= 1** — the expected value IS the wrong constant, so APPLYING THE FIX TURNS THE SUITE RED (`watcher does not parse $16: 0`). The verifier proved it by applying the bugfix and watching the red. A literal grep pinned to a constant can only ever certify whatever is currently written; `docs/lessons/stale-assertion-becomes-an-inverted-guard.md` is the standing rule and this is its sharpest instance yet — the assertion does not merely fail to catch the bug, it prevents the cure.
  - **What else SURVIVED** (all 37/37 green): the token's whole delivery path is untested end to end — removing `"$RCY_SUBMIT_TOKEN_ARG"` from `recycle_fire:12143`'s detach argv survives, as does the `-lt 2` arming gate; `resume_engaged`'s token scan is unguarded on two of its three filters, so a PREVIOUS run's token record or a SUBAGENT record quoting the brief can become the baseline (only "a token record exists at all" is pinned); `RCY_ENGAGE_INTERVAL`'s DEFAULT is unguarded because every case overrides it as a knob; widening the re-CR gate from `DRAFT-MINE` to `DRAFT-MINE || DRAFT` — pressing Enter on someone ELSE's composer text, the author's own declared safety property — survives; the Tcl probe's `unreadable`→`none` mapping survives, so a predicate that REFUSES reads as a clean "no" one layer up; and deleting the `❯<ordinal>` MENU detector survives because the fixture's menu screen carries no U+2500 borders, so the box parse exits 9 and the verdict is UNKNOWN either way.
  - **Three decorative assertions to REPLACE, not supplement:** one pins a COMMENT verbatim and can only fail on a doc edit; `#15` ("never blind-CRs a quiet pty") is two string greps that stayed GREEN under the mutant that makes the quiet arm type unconditionally, while `#18` died — its title over-claims; `#14` extracts a span with `sed -n` and never asserts the span is non-empty, so an indentation change makes it vacuously green at 0.
  - 🚨 **LOAD FRAGILITY IS NOW A REPEATED, MEASURED PATTERN — three suites in one week.** W3p's four executed-expect cases wrap the program in `timeout 60`/`timeout 90` with NO load guard: **16 reds across three contended runs, 1 red in 12 case-runs at load 140-170, green 4/4 in isolation** — and they fail as a BLOCK at `[ "$status" -eq 0 ]` before any behavioural check, so a green from that file is not a reproducible property and a red cannot be attributed to a diff. That is `cc-lr.bats` (fixed `1b2676f4c`), `handoff-recycle-remote-resume.bats` case 33 (fixed `b538f4724`, both arms proved on the live box at 14.15/core), and now W3p. **The convention keeps being re-derived per suite instead of enforced**: a load guard that lives only where it was last needed does not reach the suite written next week. Candidate for a ratchet — a lint over walltime assertions carrying no load guard — named here, not yet built.
  - **Both W3 halves therefore need hardening before either merges**, and they are running now on disjoint files: `wf_3ed47534-7db` on `lr100p/w3p` (handoff-fire + lr-fire-resume + lr-submit-probe), `wf_3472cd2a-0a3` on `lr100p/w3i` (the ingest set), `wf_535a405f-85b` on `capacity-admit.sh`. **The pattern across all four adversarial passes is one finding:** every wave in this project passed its own suite and failed an independent mutation pass — W2 on four of five token properties, W3i on its flagship clause, W3p on the argv its own test pins. A wave's own tests measure whether it does what its author meant; only a mutant measures whether the test would notice if it stopped.
  - **The ratchet candidate, MEASURED so the next session starts from a number rather than a hunch.** `grep -lE '\[ *"?\$\(\( *[A-Za-z_]+ *- *[A-Za-z_]+ *\)\)"? *-(le|lt|ge|gt) '` over `tests/*.bats` returns **21 suites carrying a duration comparison, 13 of them with no load guard at all** (no `getloadavg`, no `load/core`, no `*_MAX_LPC`). That is the upper bound, NOT the population: the heuristic cannot yet tell a WALLTIME assertion (both operands traced to `$(date +%s)` around a real command) from a duration computed out of FIXTURE timestamps, which is legitimate and common here — a TTL, a lock age, a beat age. A ratchet built on the loose form would block 8 innocent suites at the land gate, which is worse than the red it prevents. **The narrowing is the whole design problem**, and it is the reason this is recorded rather than half-built: the discriminator must be "both operands trace to a `date +%s` capture in this file", and it should ship ADVISORY-first (report, never block) the way the other own-scope ratchets did, until its false-positive rate is measured against those 21.
