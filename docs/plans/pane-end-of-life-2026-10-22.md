---
status: open
---

# Pane end of life, 2026-10-22: every pane ends running Claude Code or closed, and says which

Scope (frozen): implement the fixes from `docs/research/husk-panes-2026-10-22/` (REPORT.md, then
synthesis.md F1-F8 as corrected by skeptics.md) so that (1) self-close can never close a pane holding a
different live session, (2) a pane is never kept without either a live claude or a durable row that a
reconciler retries, (3) one component writes a dead pane's final title and rows, following the message
contract in synthesis.md § CONTRACT, and (4) a fired peer's death reaches the lead holding its custody.
Each item needs a bats arm that fails on pre-fix trunk, one mutant, and a land through `/ship`.

## Phase 0: Agent Team Orchestration

- **Execution locus per wave:**
  - Wave A: **S**, one dispatched session.
  - Wave B: **S**, one dispatched session.
  - They run concurrently in separate worktrees. Each session leads its own teammates if it splits work.
- **Lead:** the originating session (wt-cc-181959-2541). It fires both waves and awaits their DONE pings.
  It writes no code. Its budget is to keep under 50% of its context. Succession point: once both waves
  are fired, recycle if context is at 35% or more while idle.
- **File ownership.** No file has two writers at once.
  - **A owns:** `scripts/handoff-fire.sh`, `hooks/lib/origin-identity.sh`, `hooks/validate-bash.sh`,
    `bin/cc-husk-sweep`.
  - **B owns:** `bin/cc-pane-runner`, `bin/kitty-fullscreen-guard`, `hooks/lead-crash-watchdog.sh`,
    `scripts/lib/pane-close-queue.sh`, `scripts/pane-close-retry.sh`, `bin/cc-pane-close`,
    `bin/cc-custody`, `scripts/custody-deathwatch.sh`, `scripts/autonomy-sweep*`, `bin/it2-kitty`, and the
    new `bin/cc-pane-verdict`.
  - **Exception:** B's two `scripts/handoff-fire.sh` edits (B7) run only after A has landed, on a rebased
    branch.

## Wave A: self-close can only close its own pane (behavior; the 2026-10-22 lead kill)

A1. F1(a): `pane_ownership` treats ancestry as "mine" only when the pane's registered live session
    (`cc-registry/<pane>.json`, pid alive) is the caller. For the remote forms (`SC_FIRER_RETIRE` /
    `SC_REMOTE_SOURCE`), compare with `SC_SOURCE_SESSION`, not with the armer (skeptic correction).
A2. F1(b): self-close from a headless run (sdk-cli entrypoint, or no tty on its claude ancestor) never takes
    its pane from the environment. It resolves its pane from its own fire stamp (the stamp whose
    transcript is `<own sid>.jsonl`), or it refuses.
A3. F1(c): immediately before typing `/exit`, the watcher re-reads the registry, and aborts with a printed
    reason if the pane now holds a different session. Every arm prints "pane N holds session X; you are Y".
A4. Adoption proves ownership with `oi_marker_inbound`, not with a bare grep (`adopt_orphan_stamp` ~:9136
    and the spent-retry path ~:15004). The test must use the real fixture shape: an open stamp for the same
    cwd whose marker appears only as tool output in the lead's transcript.
A5. F7(a, b): headless resumes cannot inherit pane identity. Prefer making the launch safe, by having
    `hf_bgjob_argv` or a wrapper unset `KITTY_WINDOW_ID`/`ITERM_SESSION_ID`, over an argv-text deny. A deny
    must not fire on text that merely mentions the command (lesson: research-block reads argv). Separately,
    `cc-husk-sweep` must not read a `tty=none` registration as a MOVE.
A6. F2: generation hygiene. Stamps and queue rows carry the kitty pid, and anything from an older kitty
    reads as stale. Add a garbage-collection pass for the 156 pre-generation open stamps.
A7. Read-only: identify the sender of the 09:12:40Z SIGTERM to 570d3917
    (`close-records/54386-1792654623.json`). Append the finding to the REPORT's "Open" line.

## Wave B: closes are durable and the screen says one true thing (behavior + messaging)

B1. F4: the guard reports *why* it could not read (`KittenFailed as e`, an error field, no placeholder
    line). The runner keeps guard stderr out of the pane and tells refused-fs apart from unreadable.
B2. F3: a new `husk` row kind in the pane-close queue. Producers: the runner's keep sites, `_no_command`
    (which first writes the exit record), the watchdog's refusal and CRASH branches. Consumer: a
    `drain_husk` in pane-close-retry. Triggers: the tick, SessionEnd, and custody return or abandon. Do not
    close a pane whose tty has had input since the row's `first_ts` (the operator took it over). A row
    created while custody is open waits for the return.
B3. F5: `bin/cc-pane-verdict`, the single final writer, idempotent, repainting only when its state
    changes. It uses the synthesis.md § CONTRACT states and wording. Set titles with
    `set-window-title --temporary`, or reset them on every relaunch path. A permanent title would outlive
    an in-pane resume (skeptic correction). Land the interim fix first: the watchdog's refusal branch never
    paints "✅ closed" or "reason unknown".
B4. F6, via the existing channel: get `custody-deathwatch` to actually run (not starved by
    autonomy-sweep's own time bound), and make its liveness check read the session, not the pane's
    existence. It must page the originator once per marker, naming the in-pane resume command.
B5. F7(c): the watchdog classifies a `tty=none`/sdk-cli end with no close record as `headless-ended`. It
    classifies a death right after another session typed `/exit` into the pane (pane-keys.jsonl) as
    `closed-by-other-session`, and pages it.
B6. F8: the it2-kitty split uses the session's target directory when the caller supplies it.
B7. After Wave A has landed, on a rebased branch: the husk-row producer in handoff-fire's husk-pane and
    husk-fs arms (~:11722), and the os-window `--cwd` (~:19661).

## Progress

- A1-A3 (wave A): self-close refuses a claude nested in the pane's live tenant ("pane N holds live
  session X; you are Y"); a headless run uses its own fire stamp's pane and types nothing; the
  registry is re-read before /exit and at the watcher's close. Landed aea01028e (+ fixups 70cd225cb
  2d8b49c12 2ba830035) · tests/handoff-selfclose-nested-claude.bats.
- A4 (wave A): adoption and the spent-stamp retry prove the marker arrived (oi_marker_inbound).
  Landed 64513d5e1 (+ 0dc4fb368) · tests/handoff-selfclose-stale-stamp.bats.
- A5 (wave A): validate-bash denies an unscrubbed `claude -p --resume` from a pane (command position
  only); cc-husk-sweep ignores tty=none registrations. Landed 8d69845a0 (+ 4d00e7c20, site re-pin) ·
  tests/validate-bash-headless-resume.bats, tests/cc-husk-sweep-lineage.bats.
- A6 (wave A): stamps carry kittyPid and self-close queue rows kitty_pid; an older kitty's stamps read
  stale; a once-per-generation GC closes them (closedReason kitty-restarted). Landed af6c54c8d ·
  tests/origin-identity.bats. For wave B: pane-close-retry can drop self-close rows whose kitty_pid is
  not the live kitty; a headless self-close leaves its pane to the pane closer (a husk row would close it).
- A7 (wave A): the 09:12Z SIGTERM sender is still unresolved after 40+ stores; lane K sat 55 min at an
  unanswered permission dialog, not mid-pytest. Landed d0b3a043a · REPORT.md Open line, a7-sigterm.md.
- Wave A converged: live checkout at 2ba830035 (deploy-live degraded tier).
- B1 (wave B): the guard's kitten-failed carries its error (row + stderr, no placeholder state); the
  runner keeps guard output out of the pane and says "kitty didn't answer" unless the verdict is
  refused-fs. Landed f9e50608f (in 262781d14) · tests/kitty-fullscreen-guard.bats #39,
  tests/cc-pane-runner-no-command-closes.bats.
- B2 (wave B): `husk` rows in the pane-close queue from the runner's keep sites and the watchdog's
  paint; `_no_command` writes its exit record first; `drain_husk` closes through cc-pane-close (holds:
  kitty generation, pane gone/in use, tty typed in, open custody); cc-custody return/abandon detaches
  a drain. Landed c15d60c3b (+ dd88ffec1 5e8601f45 262781d14) · tests/pane-close-queue.bats,
  tests/cc-pane-runner-exit75-closes.bats, tests/cc-custody.bats, tests/lead-crash-pane-verdict.bats.
- B6 (wave B): it2-kitty split honours IT2_SPLIT_CWD (an existing dir) over --cwd=current ·
  tests/it2-kitty-operator-safety.bats. Scope (grown): +cc-pane-close polls a zombie root up to
  CC_PANE_CLOSE_REAP_S before calling kitty wedged (lead report, 2026-10-23) · tests/cc-pane-close.bats.
- B3 (wave B): interim — a refused close paints its reason (✓ done / ◆ check), never ✅ closed or
  "reason unknown" (90968e105). Then bin/cc-pane-verdict, the one writer: contract states, width-fit,
  `set-window-title --temporary`, repaint only on change; watchdog, runner and drain_husk paint through
  it (98639e603) · tests/cc-pane-verdict.bats, tests/lead-crash-pane-verdict.bats.
- B5 (wave B): classify_death names closed-by-other-session (an /exit typed by a session nested in the
  pane; pages) and headless-ended (tty=none, no close record; no page) (a96e52bdc) ·
  tests/lead-crash-watchdog.bats F7c.
- B7 (wave B, after A): husk-pane/husk-fs and the headless self-close write husk rows; splits and
  os-windows start in LAUNCH_DIR (764745e6d) · tests/handoff-selfclose.bats,
  tests/handoff-selfclose-nested-claude.bats, tests/handoff-fire-kitty.bats. Scope (grown): +self-close
  rows from an older kitty are dropped (5fe7685c3) · tests/pane-close-queue.bats.
- Known red, not wave B's: tests/handoff-alarm-records.bats #28 pins 9 `hf_alarm` sites; trunk has had 10
  for at least the last 12 handoff-fire commits.
