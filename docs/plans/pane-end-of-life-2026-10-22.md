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

Scope (grown 2026-10-23): +Wave C. The reconciler from Waves A-B works only when it is run from
inside kitty. Panes 144-147 and 165 sat refused 8-44 times under screens promising "closes when it
does" (`docs/research/husk-panes-2026-10-22/round2-2026-10-23/`). Wave C makes the background closer
see kitty, makes teammate panes closeable, and gives a pane only a person can close an honest
"operator" state.

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

## Wave C (2026-10-23): the background closer sees kitty, and a stuck pane says so

**Locus:** S, one dispatched session in its own worktree. The lead (wt-cc-181959-2541) writes no code.
Evidence: `round2-2026-10-23/synthesis.md` FX1-FX7, with the corrections in `skeptics.md` taking
precedence. Every item needs a bats arm that fails on pre-fix trunk, one mutant, and a land.

C1. FX1: `bin/cc-pane-close` pins kitty for its listing (`kitty_list_once` ~:211-219) and its
    remote-control probe (`remote_answers` ~:338-342), as the close at ~:461 already does. Use an
    env prefix on the bounded call, not a shell function: `bounded`/timeout execs its argument, so a
    function name fails with rc 127 (skeptic). The refusal "does not name this pane's window" must
    split into "the listing did not answer" and "listed, and the pane is absent" (treat absent as
    already closed). Stop discarding the closer's stderr at `hooks/lead-crash-watchdog.sh` ~:2171.
    The test runs the closer with KITTY_*/CC_TERM unset and a stub iTerm2 `it2` that fails. Pre-fix
    it reads "remote control is down".
C2. FX2: all four registration readers accept a trailing ` teammate=<id>` (`cc-pane-close` ~:263 and
    ~:356, `cc-husk-sweep` ~:253 and ~:285), ideally through one shared parser in hooks/lib. Keep the
    `tty=none` exclusion. Gate 3 (~:432) accepts any teamName transcript, so gate 4 (clean cwd) is
    what protects a crashed teammate's work. Pin that with a test.
C3. FX4: `bin/cc-pane-verdict` classifies the closer's refusal before choosing row 2:
    - transient (kitty truly did not answer);
    - operator-only (pane-scope refused-fs: the pane is the last one of a fullscreen window);
    - stuck (anything no future tick can change).
    Only the transient class may say "closes when it does". Every operator action names ⌘W (the
    guarded kitty-confirm-close path), never Ctrl-D, unless the guard has said the pane is not last
    (skeptic: Ctrl-D on the last pane of a fullscreen window is the 2026-10-15 crash trigger). The
    NOTHING state must also read the closer line.
C4. FX5: in `scripts/pane-close-retry.sh` `drain_husk`, a pane-scope refused-fs on a one-pane OS
    window sets `hold=operator`. That row pages once ("⌘W pane N on its Desktop"), stops counting
    attempts, and is re-checked only when its window's pane count changes. Drain oldest-first, and
    defer with a logged line near the run's time bound. Add a single-instance lock: overlapping
    drainers race pcq_add's read-modify-write.
C5. FX3: the drainer gets its own launchd job at Standard priority, every 5 min, wrapped in
    `/opt/homebrew/bin/timeout`, declared in `launchd/fleet.manifest` with expect=run. Remove the call
    from `teammate-reap-alarm.sh` (~:429-439). Bound `assignee-pane-residency.sh` at both of its call
    sites (`teammate-reap-alarm.sh` ~:169 and the plist). A plist edit does not apply while the old
    job is running (install.sh ~:1437-1440): say so in Progress.
C6. FX6: self-close rows can end.
    - After a proven arm, handoff-fire clears the row for its own pane whose sid matches (~:15885).
    - The drainer counts self-close rows toward its kitty gate, and drops a row whose pane is absent
      from `$LS` within the same kitty. It drops, never acts on, a row whose pane now runs a different
      sid.
    - "Same kitty" falls back to first_ts vs kitty start when kitty_pid is null.
    - A non-numeric pane id (`fake:UUID`) is dropped.
    - Expected effect: the 7 dead rows (137, 17, 41, 57, 75, 79, 83), recycle-fake_UUID and the two
      *.tmp.* leftovers clear on the first tick after landing; verify in pane-close-retry.log.
C7. FX7: `tests/handoff-fire-validate.bats` and the other fake:UUID recycle suites isolate the queue dir
    and must not reach the live kitty. Its test 3 ran a live `--recycle` against kitty 1881.

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
  refused-fs. Landed c820e86f1 (in 262781d14) · tests/kitty-fullscreen-guard.bats #39,
  tests/cc-pane-runner-no-command-closes.bats.
- B2 (wave B): `husk` rows in the pane-close queue from the runner's keep sites and the watchdog's
  paint; `_no_command` writes its exit record first; `drain_husk` closes through cc-pane-close (holds:
  kitty generation, pane gone/in use, tty typed in, open custody); cc-custody return/abandon detaches
  a drain. Landed 5d0be0366 (+ 564a9ab49 7a2becf81 262781d14) · tests/pane-close-queue.bats,
  tests/cc-pane-runner-exit75-closes.bats, tests/cc-custody.bats, tests/lead-crash-pane-verdict.bats.
- B6 (wave B): it2-kitty split honours IT2_SPLIT_CWD (an existing dir) over --cwd=current (d0ef0fcbd) ·
  tests/it2-kitty-operator-safety.bats. Scope (grown): +cc-pane-close polls a zombie root up to
  CC_PANE_CLOSE_REAP_S before calling kitty wedged (lead report, 2026-10-23; ab7e82e9f) · tests/cc-pane-close.bats.
- B3 (wave B): interim — a refused close paints its reason (✓ done / ◆ check), never ✅ closed or
  "reason unknown" (2c94cf6d8). Then bin/cc-pane-verdict, the one writer: contract states, width-fit,
  `set-window-title --temporary`, repaint only on change; watchdog, runner and drain_husk paint through
  it (99acf1d9f) · tests/cc-pane-verdict.bats, tests/lead-crash-pane-verdict.bats.
- B5 (wave B): classify_death names closed-by-other-session (an /exit typed by a session nested in the
  pane; pages) and headless-ended (tty=none, no close record; no page) (21ea2a872) ·
  tests/lead-crash-watchdog.bats F7c.
- B7 (wave B, after A): husk-pane/husk-fs and the headless self-close write husk rows; splits and
  os-windows start in LAUNCH_DIR (d82aa7860) · tests/handoff-selfclose.bats,
  tests/handoff-selfclose-nested-claude.bats, tests/handoff-fire-kitty.bats. Scope (grown): +self-close
  rows from an older kitty are dropped (85b1d7131) · tests/pane-close-queue.bats.
- Known red, not wave B's: tests/handoff-alarm-records.bats #28 pins 9 `hf_alarm` sites; trunk has had 10
  for at least the last 12 handoff-fire commits.
- B4 (wave B, teammate b4-deathwatch): custody-deathwatch is hoisted above §0a in autonomy-sweep, so a
  truncated tick still reaches it; a listed pane whose registry pid is dead (a husk) reads GONE, and the
  page names `cc-husk-sweep --resume --yes --pane N` once per marker (6ad98363a + b5e155596) · tests/custody-deathwatch.bats, tests/autonomy-sweep.bats (0a-ii).
- Wave B landed and live at 29198dcea (also f3466586f: validate-bash's headless-resume gate takes the
  cc-pane-id-lint allow marker, clearing trunk's red tests/cc-pane.bats #27 from 8d69845a0). The land
  smoke's autonomy-sweep.bats reds were load (~300): a same-moment A/B failed the identical tests on
  trunk and on wave B.
- Close (lead, 2026-10-23): both waves verified against the remote tip (`git ls-remote`, not the local
  origin/main ref, which briefly listed unpushed B4 commits at 00:33 and 01:28). The remaining trunk red,
  tests/handoff-alarm-records.bats #28, predated both waves: e2d0cee07 (2026-10-19) added a tenth
  hf_alarm site, recycle-held-fold, without raising the pin. Recorded and raised in d4c496ad9. Open
  question carried in REPORT.md: the 09:12:40Z SIGTERM sender.
- C1 (wave C): cc-pane-close pins its listing and probe to the running kitty (env prefix on the bounded
  call); a listing without the pane reads ALREADY CLOSED; "did not answer (<it2 error>)" apart from
  absent; guard refusals name refused-fs; the watchdog predicate keeps stderr. Landed 957279537
  (+ d29d83843, stubs via cc_stub, by the re-land worker) · tests/cc-pane-close-background.bats.
- C2 (wave C): hooks/lib/watchdog-registration.sh wd_reg_norm strips ` teammate=<id>` for all four
  readers (cc-pane-close identity + moved_live, cc-husk-sweep watchdog_sid; lineage_of's regex carries
  the group); gate 4 pinned for a crashed teammate. Landed 975dd4d94 (+ 957279537) ·
  tests/cc-pane-close-background.bats, tests/cc-husk-sweep-identity.bats, tests/cc-husk-sweep-lineage.bats.
- C3 (wave C): cc-pane-verdict classes the closer line — transient / operator-only (refused-fs, ⌘W) /
  stuck (--guard stuck, ⌘W, "won't close by itself"); NOTHING reads the closer line; an empty
  --closer-out paints nothing. The watchdog's kept-pane paint uses the same classes. Landed 03696fdd5,
  7f7b9c293 · tests/cc-pane-verdict.bats, tests/lead-crash-pane-verdict.bats.
- C6 (wave C): a proven self-close arm spends its pane's row when the sid matches; the drainer asks kitty
  for self-close rows too, drops a same-kitty row whose pane is gone or whose registry names another sid,
  drops non-numeric pane ids (recycle-fake_UUID), sweeps hour-old *.json.tmp.*, and reads the retrier's
  lstart in UTC. Landed 3f1a77b71 · tests/pane-close-queue.bats, tests/handoff-selfclose-records-after-proof.bats.
  The live rows (137, 17, 41, 57, 75, 79, 83, recycle-fake_UUID, two tmp files) clear on the drainer's
  first tick after convergence: read ~/.claude/logs/pane-close-retry.log for "✓ pane gone".
- C4 (wave C): drain_husk holds a refused-fs husk that is its OS window's only pane as hold=operator
  (paged once, "⌘W pane N on its Desktop", no attempts, released when the window's pane count
  changes); rc 124 with no output is logged, not repainted; husks drain oldest last_ts first and defer
  within 30 s of CC_PCQ_DRAIN_TIMEOUT_S; a single-instance lock (.drain.lock). Landed 4cb749ceb ·
  tests/pane-close-queue.bats.
- C5 (wave C): com.claude.pane-close-drainer, its own launchd job (Standard, no Nice, every 300 s,
  timeout -k 5 270, budget 240), declared `run` in launchd/fleet.manifest; the drainer call is gone from
  teammate-reap-alarm.sh; assignee-pane-residency.sh bounded at 300 s at both call sites. A plist edit
  does not apply while the old job is executing (install.sh never bounces a running job): the
  teammate-reap-alarm change takes effect at its next load. Landed 0375891ac ·
  tests/teammate-reap-alarm.bats, tests/cc-fleet.bats.
- C7 (wave C): tests/handoff-fire-validate.bats runs hermetic (fixture HOME, its own queue dir, a stub
  kitty socket, CC_FIRE_KITTY_PROBE=off); the three other fake:UUID suites export the queue dir. Landed
  920c2dc72 · tests/handoff-fire-validate.bats.
- Wave C method notes: the cc-bats governor deferred every run for 20+ min (both slots held by lints
  from the shared checkout at load ~130); runs went through its recorded waiver. The land gate's
  test-stub ratchet (R4) and dead-assertion ratchet each reddened one land; both were fixed as
  their fixers prescribe.
