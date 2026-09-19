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
