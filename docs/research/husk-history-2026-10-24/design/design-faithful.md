# Husk-pane fix, Track-A-faithful and checked against the census (2026-10-24)

Lens: Track A's design (`wt-cc-203953-20264/docs/research/husk-pane-close-2026-10-24/REPORT.md`) is the base. I checked it point by point against census §6 (ten requirements) and the census mechanism inventory (§3). Where Track A misses a requirement or leaves out an actor, I propose the smallest addition. Where a Track A item is not needed, I name it.

- All code citations were checked at HEAD `fa9cadc24` of `.worktrees/husk-skill-and-fix` with `sed -n`, `grep -n` or `git grep -n`.
- Nothing in the repo was edited, run or tested. Nothing touched kitty or a pane.
- Numbers are labelled. **[M]** = measured, with the command. **[TA]** / **[C]** = measured by Track A's maps or by the census, cited. **[E]** = estimated, with the method.

---

## 0. Verdict in brief

Track A's core is right and stays:
- **The runner owns the pane's end.**
- A guard refusal becomes a **hold** (the runner stays the window's process, re-asks, and exits once that is safe), never a shell.

Measured against the census, Track A falls short in five places:

1. **Its own replay test cannot pass after its Phase 1.**
   - Arm B asserts `cc-pane-close --dry-run` → WOULD CLOSE, and Watchdog → DONE, on the 289 fixture.
   - Both need gate 4 and `pane_work_state` scoped to the session's own files. Track A puts that in Phase 3 (3.2 + 3.3).
   - So the GOAL clause "even when its shared cwd holds sibling sessions' dirt" is unmet until Phase 3. W1 below pulls forward a **smaller** own-footprint rule.
2. **The two-closer lock (2.6) ships in Phase 2, but the hold creates correlated releases.**
   - Example: several holds in one window that kitty answers at the same moment.
   - That is a new trigger for "two closers both read not-last → the window is emptied → the 2026-10-15 crash".
   - The lock moves into W1, inside the guard, so every caller gets it.
3. **The standing population metric (census item 7) comes last (3.6) and as a new launchd job.** It moves to W0, before the fix, so "done" is measured against a baseline. It runs inside the existing drainer job (no new plist).
4. **Track A's lr-fire-resume change (2.2, "exit $rc") would close every killed lr session's pane.**
   - The lr expect program ends at `interact` (`scripts/limit-recover/lr-fire-resume.sh:2235-2236`) and forwards no exit status.
   - The repo's own sibling comment says this construct "exits 0 however the session ended" (`bin/reso-resume-one:1103-1104`). reso-resume-one fixes it with `wait` forwarding (`:1108-1110`).
   - A concrete precondition is added (W2.0).
5. **Track A leaves out several actors.**
   - **custody-deathwatch** (`scripts/custody-deathwatch.sh:356-357, :394`) tells a lead to `cc-husk-sweep --resume --yes` a pane that may be held.
   - **boot-resume's selection** (`scripts/boot-resume.sh:754-766`) does not read any end-of-life fact except self-close markers and reaps.
   - **The drainer's rc-124 class** is left alone.
   - All three get small additions in W3.

Track A items that are not needed are listed in §4, among them 2.1, 3.3, 1.6, part of 3.2, part of 1.7, and part of 1.3. The result has fewer moving parts than Track A, and more deletions than additions on the default path.

---

## 1. The invariant

**A fleet pane is in exactly one of four states, and the runner (the window's own process) is the only writer of which one:**

| state | what the window holds | who ends it | record (`~/.claude/run/pane-exit/<wid>.json`) |
|---|---|---|---|
| RUNNING | claude under the runner | the session | none yet |
| CLOSED | nothing (the window is gone) | the runner exiting | `tail=closed` |
| HELD | `cc-pane-held`, the runner's in-memory body: no shell, no tty reads | the hold itself, once the guard says safe twice, 10 s apart, under the in-flight lock; or the operator's ⌘W | `tail=held:guard-fs` or `tail=held:guard-unreadable` |
| KEPT | an interactive shell | the operator, the sweep's resume, or the closer | `tail=kept:crash`, `kept:recycle`, `kept:kill-switch`, `kept:not-a-session` or `kept:fallback` |

A bare shell over a dead fleet session whose record is not `kept:*` is an alarm (W0 counts it), never a resting state. **Only the death-time watchdog may paint RESUME.** No reconciler re-derives RESUME from a closer refusal.

**Safety invariants, unchanged in force:**
- **(S1)** Never empty the last pane of a native-fullscreen OS window. Every process exit that can empty a window passes `kitty-fullscreen-guard` and its new in-flight lock. A hold never exits on a signal it cannot attribute to kitty closing the window.
- **(S2)** Never close a pane with a live job.
  - A hold release only ends the hold's own process. It kills nothing.
  - kitty keeps a window whose pty is still held by another process (`close_on_child_death no`, per Track A's lifecycle map §1).
  - Gate 2 of cc-pane-close is unchanged.
- **(S3)** Never resume a finished session. The sweep gets a never-resumed HELD verdict, and the reconciler can no longer paint RESUME.
- **(S4)** A crashed session with its own uncommitted work is still kept and resumable.
  - rc≠0 still ends in `_kept_line` and a kept shell (`bin/cc-pane-runner:273-275`, `:358-375`).
  - Gate 4 still refuses on the session's own edit-recorded dirt.
  - A gate 3 that passed on the `teamName` fact alone keeps the stricter per-path proof.

---

## 2. Track A against census §6, point by point

| # | Census requirement | Track A | Verdict | Smallest addition (wave) |
|---|---|---|---|---|
| 1 | One end-of-life record, written by the session and read by every actor | The runner's exit record gains a `tail` field (1.3). Self-close writes allowDirty to the fired record (3.3). Readers stand down on the process name. | **Partial.** The record is written by the runner, not the session. boot-resume and custody-deathwatch read neither record. | Do not build a session-written record. On the default path the runner observes rc and owns the end, so no reader needs intent. Remaining readers share **one intent reader** (3.1) and **one dirt predicate** (W1.5). boot-resume (W3.5) and deathwatch (W3.6) are added as readers. Named residual: the transcript's final turn, the fired record and the exit record stay three sources. |
| 2 | One decision function; painters only render | lib/pane-fate.sh is deferred. 1.7 remaps the substrings. | **Partial**, and I agree with deferring the library: a new 260-line single point is a moving part. | Reach the outcome without the library. The reconciler (`--recompute`) never produces RESUME (W1.4). RESUME then has one writer: the death-time watchdog, which reads custody. So the last caller cannot flip a pane to RESUME, and RESUME cannot coexist with COLLECTED. |
| 3 | Work-at-risk keyed on the same subject as intent, at every site, plus a cross-closer test | Phase 3: a 3-function chain plus an allowDirty stamp | **Met late, and over-built** | W1.5: `session_work_at_risk` = `session_dirty_mine` everywhere. The existing, unmodified `dirt_unreachable_by_session` is added only when gate 3 passed on `teamName` alone. A lint fails any whole-cwd `status --porcelain` in the closers (W1 test). |
| 4 | Admit before you act; reconcile placement with the fullscreen rule | The hold (1.1-1.2); held windows fill first (2.5) | **Met in substance.** The session never exits into a husk: it exits into an owned, labelled hold. The fullscreen placement versus guard conflict is still an operator decision (§8 R9). | 2.5 reduced to one sort-key change (W2.6). |
| 5 | Invert the default: the close is the pane's own exit | Phases 1 and 2 | **Met**, with named `kept:*` exceptions | Keep. W2.0 is a precondition for lr panes. |
| 6 | Every refusal has an owner and a terminal state; rc124 is its own class | FS refusal → hold; sibling dirt removed as an input; rc124 deferred | **Partial** (rc124) | W3.4: the drainer logs rc124 as `timeout`, outside the 6-attempt page count. |
| 7 | A standing population metric; "done" = 0 for 7 days | 3.6: a census job that pages, last phase | **Partial**: no metric-of-record log, no done query, and it comes last | **W0**: `scripts/pane-census.sh`, one JSONL row per drainer tick, a `done` query, and page-once. |
| 8 | Composed replay in the real topology, from a launchd-like parent | Replay arms A, B and C, each run separately | **Partial** | Arm D (§6): runner → queue → drainer under `env -i`, with no kitty env. |
| 9 | Agents may execute the decision | Not addressed | **Met by construction.** A hold or close is the runner's own exit, so no agent act and no classifier call are needed. The one remaining operator act, ⌘W on an off-screen fullscreen held pane, is operator-only by safety ruling e3920969aba9, not by the classifier. | None. No settings change is proposed. |
| 10 | Brief the invariant, not the incident | The replay arms span 289, a deaf kitty, a crash and a teammate | **Met** once W0's metric exists | The deliverable is the §1 invariant plus W0's metric at 0 for 7 days. A new incident is a regression against that metric. |

---

## 3. Track A against the census actor inventory

| Actor (census §3) | Track A covers? | Gap and smallest addition |
|---|---|---|
| Session close line | 3.1 final-turn reader | Also used by boot-resume (W3.5) |
| handoff-fire self-close watcher | 1.4 stand-down | Covered. The trust rule is simplified (§4). |
| cc-pane-runner | 1.1-1.3, 1.8 | Covered. The rollback switch must be a **file**: kitty-spawned panes inherit kitty's environment, not a shell export, which is why the guard's own policy is a file (`bin/kitty-fullscreen-guard:73-76`). |
| reso-resume-one | 2.2 | Covered in W2. The duplicate close (`bin/reso-resume-one:1145-1186`) is deleted once rooted. |
| it2-kitty actuator | comments only (1.4) | Covered |
| kitty-fullscreen-guard | 2.6 lock, Phase 2 | **Moved to W1** (correlated releases) |
| Placement policy | 2.5 | Reduced to a sort key (W2.6) |
| lead-crash-watchdog | stands down on cc-pane-held; 3.2, 3.4 | Own-dirt scoping moves into W1. The inner-pty identity (`hooks/lead-crash-watchdog.sh:2299`) stays deferred, because after W2 an lr crash keep gets its husk row from the runner instead (`bin/cc-pane-runner:365`). |
| cc-pane-close | 3.2, 3.3 | **W1.5**, simplified; 3.3 dropped |
| pane-close-retry drainer | 3.5 | Operator-owns rule: the 1-line log fix plus deleting the paint record (W3.3). The census's "atime ≠ typing" point stays as a named residual: after W1 it applies only to `kept:*` shells, where an atime rise is a fair proxy for a human using the shell. rc124: W3.4. |
| cc-pane-verdict | 1.7 | Simplified: `uncommitted` → CANTTELL (W1.4), and a `held` row text |
| cc-husk-sweep | 1.5 HELD | Plus own-scoped `work_of` in W1 (Track A has it in Phase 3) |
| crash attributor / close-attrib | — | Not needed. Rows keep being written. A held pane yields no `STILL-PRESENT-rc70` row, because the watcher stands down. |
| **boot-resume** | Launch tail only (2.3) | **Left out of selection.** It retires only on a self-close marker or a lead-supervisor reap (`scripts/boot-resume.sh:754-766, :783-795, :845-856`). W3.5 adds: SessionEnd `reason=prompt_input_exit` after the last activity, with no later SessionStart for that sid, or a final-turn yes → retired. |
| **lr-fleet `--retire-husks` / cc-limited** | not named | Covered transitively. It closes through `self-close --transplanted-source` (`scripts/limit-recover/lr-fleet.sh:2140-2141`), so the source pane's runner holds or closes (W1), and lr panes are rooted (W2). No code. |
| reap-guard / teammate-auto-shutdown | — | Already own-footprint. Unchanged. |
| **custody-deathwatch** (not in the census table; found here) | not named | `husk=1` whenever the peer is GONE and its pane exists (`scripts/custody-deathwatch.sh:356-357`). It then tells the lead to run `cc-husk-sweep --resume --yes --pane N` (`:394`). For a held pane that instruction is false. W1's sweep HELD makes it harmless; W3.6 fixes the text (1 line). |
| husk-pane skill | — | Doc-only. Update after W1. |

---

## 4. Track A items that are unnecessary or should move

| Track A item | Disposition | Why |
|---|---|---|
| 2.1 `CC_PANE_RUNNER_PID` plus a 6-hop ancestor walk | **Drop** | `CC_PANE_RUNNER_OWNS_CLOSE=1` already means "the runner closes this pane". It is exported to the command (`bin/cc-pane-runner:569`), unset before any fallback shell (`:103`), and already honoured by cc-close-attrib. Launchers test that, plus `[ -t 0 ]`, which lr-fire-resume already checks (`:2250-2252`). |
| 3.3 allowDirty / workAtClose in the fired record, honoured by gate 4 | **Drop** | Needed only because Track A's 3.2 chain returns "unknown" for 7555024a (bg=1, open final window). With gate 4 = `session_dirty_mine`, 7555024a's own 2 paths are clean: rc 1 **[TA closer map §4, /tmp/closer-map/mine.sh]**. |
| 3.2 `dirt_unreachable_by_session` with an `end_epoch` change, plus the live-peer chain everywhere | **Reduce** | Use the existing function **unmodified**, and only when gate 3 passed on `teamName` alone, the one case gate 4 was pinned to protect (`tests/cc-pane-close-background.bats:146-157`). Everywhere else `session_dirty_mine` decides. No shared-library change. |
| 1.6 ⌘W without a dialog (`bin/kitty-confirm-close:250-258`) | **Defer** | A confirm dialog over a held pane is safe and costs one click. It is not on the GOAL path. |
| 1.7 "the gate-4 line names the gate-3 fact" and "print `--resume` only when the sweep would select it" | **Replace** | `*"uncommitted change"*` → CANTTELL with the existing triage row. The closer line carries no new coupling, and the sweep is not called at paint time. |
| 1.3 `root_pid`, `lstart` and the ancestor walk for record trust | **Reduce** | Readers inside W1: the watcher needs only `kitty_pid` equal to the live kitty and `tail_ts` ≥ its own start epoch. Readers with a deaf kitty (W0) use `pid` plus `ps -p pid -o command=` reading `cc-pane-held`. Fields added: `tail, tail_ts, pid, kitty_pid`. |
| 2.5 "counts 0 toward the cap" and "one placement per hold" | **Drop** both | The held-first sort key alone suffices. After one placement the window has 2 panes, so it is no longer held-only and loses priority by itself. |
| 3.6 "its own launchd job" | **Fold into the existing drainer job** | One call before the drainer's empty-queue exit (`scripts/pane-close-retry.sh:63-64`). No new plist. |
| 2.6 lock in Phase 2 | **Move to W1** | Correlated hold releases (§0 item 2) |
| 3.6 census in Phase 3 | **Move to W0** | Census items 7 and 10 |
| "Seven tails" includes `kitty-split-cwd.sh:38` | **Out of scope** | That file is the operator's ⌘D split chooser (`bin/kitty-split-cwd.sh:1-12`), so ruling 337e100f5c71 applies. |

---

## 5. Waves, in order

### W0: the population metric first (census items 7 and 10)

**Targets**
- New `scripts/pane-census.sh`.
- One call in `scripts/pane-close-retry.sh`, inserted before `:63-64` (`ROWS="$(pcq_list)"` / `[[ -n "$ROWS" ]] || exit 0`), bounded at 20 s, rc ignored.

**What it does, once per drainer tick** (launchd `com.claude.pane-close-drainer`, 300 s, per Track A's closer map §3):
1. Resolve the socket with `bin/cc-kitty-socket`, then one bounded `kitty @ ls`.
2. Classify each window by `foreground_processes[].cmdline[0]` basename:
   - **held**: any entry is `cc-pane-held`. Age comes from the record's `tail_ts`, or the record's mtime before W1.
   - **bare**: every entry is a login shell (the drainer's own `shell_only` predicate, `:421-426`).
   - otherwise live.
3. Attribute bare windows:
   - **bare_runner**: a `pane-exit/<wid>.json` with mtime ≥ kitty start, plus its `tail` once W1 lands.
   - **bare_registered**: a `registered session=… pane=<wid>` line in the watchdog log since kitty start (informational upper bound; it includes operator-typed claudes).
4. Append one row to `~/.claude/logs/pane-census.jsonl`:
   `{ts, kitty_pid, windows, held:[{pane,age_s,tail}], bare_runner:[{pane,tail}], bare_registered:[…], unreadable}`.
5. **Metric of record:** `count(bare_runner whose tail ∉ {kept:crash, kept:recycle, kept:kill-switch, kept:not-a-session}) + count(held with age_s > 21600)`.
6. Page once per (kitty_pid, pane) via `bin/cc-desk-page` when a pane stays in the metric for 2 consecutive rows. Dedup marker: `~/.claude/run/pane-census/paged-<kpid>-<pane>`.
7. **Done query** (written into the plan): `jq -s '[.[]|select(.ts>=$since)|<metric>]|max' pane-census.jsonl` = 0 over 7 days.

**Deleted:** nothing.

**Size:** about 90 lines plus 1 line, and tests of about 80 lines **[E: sketch line count]**.

**Tests:** `tests/pane-census.bats`, with fixture ls JSON and records, run under `/bin/bash` 3.2.
- A held window counts as held.
- A bare runner window with no tail counts.
- An operator zsh with no record and no registration does not count.
- A live claude window does not count.
- A deaf kitty yields `unreadable:true` and no page.
- **Mutant:** count every bare shell. The operator-zsh case fails.

**Why first:** the census says "done" was declared five times from field proofs (§6 item 7). The baseline must exist before the fix lands.

---

### W1: the GOAL wave. The runner holds; one dirt subject; no reconciler RESUME; the lock.

**W1.1 Runner: hold instead of a shell** (`bin/cc-pane-runner`)
- **Refusal branch** `:328-342`. The `refused (refused-fs)` arm (`:331-335`) and the `*` arm (`:336-340`) both become `_hold guard-fs` / `_hold guard-unreadable`.
  - They no longer write `_husk_row guard-fullscreen|guard-unreadable` (`:332`, `:337`).
  - They no longer `return 0` into `_fallback` (`:579` → `:104`).
  - The hold is skipped, giving today's path, when the rollback file `~/.claude/state/pane-hold/policy` reads `off` (or `CC_PANE_HOLD=0` for tests). That file is read at hold entry, so a live rollback reaches new holds.
- **Hold body**, captured once at startup with `declare -f` into `_HOLD_BODY`, and entered as `exec -a cc-pane-held /bin/bash /dev/fd/3 3<<<"$_HOLD_BODY"`. Track A measured this form: comm and command read `cc-pane-held /dev/fd/3` under /bin/bash 3.2.57 **[TA §4 1.2]**. The body:
  - `set +u`. Its inputs travel in env, including the guard path, the cc-pane-verdict path and the queue library path, all resolved before the exec.
  - **Wait primitive:** the builtin `read -t "$s" -u 9` on a private fd opened with `exec 9<> <(:)`. **Not a child `sleep`**, because ^Z would stop a child sleep and wedge the hold (§8 R2), and ^C would kill it.
  - **Signals:**
    - INT, QUIT, TSTP and TERM go to a logging handler that continues.
    - HUP asks the guard once: rc 0 or rc 4 (not-found, i.e. kitty is closing the window) → `exit 0`; rc 3 → keep holding. Track A exits on HUP unconditionally, which would empty the window if anything other than kitty sent the HUP.
    - An EXIT trap, unless the sanctioned flag is set: write `tail=kept:fallback`, add one `husk` row (parity with today), then `exec "${SHELL:-/bin/zsh}" -l -i`. This is today's state, i.e. fail-closed.
  - **Loop:** `guard --window $wid --mode refuse --scope pane --tool cc-pane-hold`.
    - **Release** needs two rc-0 reads at least `CC_PANE_HOLD_GAP_S` (10) seconds apart. The repo rule "Release ≠ !trip" (`.claude/rules/agent-operating-lessons-situational.md:6`) forbids releasing on the trip predicate negated.
    - **Backoff:** 5→60 s for refused-fs and refused-inflight; 30→300 s for kitten-failed.
    - Repaint and log only when the class changes. No tty reads.
  - `CC_PANE_HOLD_MAX_S` (default 0, meaning unlimited) is a **test seam only**: when exceeded, it takes the EXIT fallback.
- **Exit record** `_pane_exit_record` `:426-443`, contract `:377-395`. Fields added: `tail, tail_ts, pid, kitty_pid`. The existing four fields are unchanged, so the three readers named at `:391` are unaffected. Tail values: `held:guard-fs|held:guard-unreadable|closed|kept:*`.
- **Paint:** the hold calls cc-pane-verdict with `--state "${_PV_STATE:-DONE}" --guard held` (fullscreen) or `--guard unreadable`. The no-command path (`:614-623`) keeps `_PV_STATE=NOTHING`.
- **Header** `:46-63`: rewrite "AFTER THE COMMAND … KEEPS A SHELL" to the §1 four-state rule.
- **Deleted from the default path:** the two guard husk rows (`:332`, `:337`); the shell for a ruled close; and the "accepted cost is a husk in a fullscreen window" rule (`:303`).
- **Size:** about +110 / −25 **[E: sketch]**.

**W1.2 One closer for a runner pane** (`scripts/handoff-fire.sh`)
- Before the close loop at `:11831`: poll `pane-exit/$SID.json` for up to 10 s.
- If `tail` is `held:*` or `closed`, `kitty_pid` equals the live kitty (`oi_live_kitty_pid`), and `tail_ts` ≥ the watcher's own start epoch: log "held/closed by its runner — nothing to close" and skip:
  - the loop,
  - the failure arm `:11861-11920` (alarm `hf_alarm` and `hf_husk_row` at `:11916-11920`).
- No record → today's path.
- Reword the "fixed fact" comments: `scripts/handoff-fire.sh:1872-1878` and `:11816-11822`, and `bin/it2-kitty:88` and `:1665` (refused-fs is a fact about the pane count, which changes).
- **Size:** +15 / −8.

**W1.3 Sweep never resumes a held pane** (`bin/cc-husk-sweep`)
- In the main loop at `:545-547`, before `has_claude_under`: if any child of the window pid in `PS_TABLE` has a command starting with `cc-pane-held`, emit row verdict `HELD` and continue.
- Add `HELD` to the never-resume case at `:608` and to the header list at `:47-55`.
- **Why it is mandatory in W1:** without it a held pane looks like a husk (its argv has no "claude"), and `--resume` types into it. If the hold later takes its EXIT fallback, the buffered line runs in the new shell and **resumes a finished session** (S3).
- **Size:** +12.

**W1.4 The reconciler never paints RESUME from a closer refusal** (`bin/cc-pane-verdict`)
- `:86-87` `*"uncommitted change"*` → `STATE=CANTTELL`, which deletes the `UNSAVED` sed. Rationale: gate 4 is reached only after gate 3 says the session meant to end (`bin/cc-pane-close:489-506`). After W1.5 the dirt is the session's own, so "can't tell, triage" is the honest state. "Stopped mid-task" never is.
- Add `held) g2="closes when this window gets another pane · ⌘W now"` beside `:97-102`. The existing `unreadable` text already says "closes when it does".
- **Size:** +2 / −2.

**W1.5 One dirt subject at all three re-judging sites**
- New `session_work_at_risk <transcript> <cwd> <sid> [strict]` in `hooks/lib/session-writes.sh`, after `session_dirty_mine` (ends `:582`). About 25 lines:
  - Not a git work tree → rc 1 (not at risk), the same as today's gate 4 on a non-repo cwd.
  - `session_dirty_mine` rc 0 → at risk ("N of its own files"). rc 2 → at risk ("cannot tell").
  - rc 1 → not at risk, unless `strict`. Under `strict`, `dirt_unreachable_by_session` (`hooks/lib/peer-owned.sh:822`, **unmodified**) must return 0; otherwise at risk.
- **`bin/cc-pane-close` gate 4** `:507-512`:
  - Replace `git status --porcelain | grep -c .` (`:510`) with `session_work_at_risk "$TP" "$cwd" "$sid" "$strict"`.
  - `strict=1` only when gate 3's `why` came from `team=1` (`:496`).
  - The refusal names the session's own count.
  - Source the two libraries by sibling path, else `~/.claude/hooks/lib`.
  - Header `:34`.
  - **Size:** +12 / −3.
- **`bin/cc-husk-sweep` `work_of`** `:508-515`: takes `R_TP`; dirt comes from `session_work_at_risk` (non-strict). The `origin/main..HEAD` unlanded arm (`:513`) is unchanged here (see W3.7). The call site is `:558`. **Size:** +6 / −3.
- **`hooks/lead-crash-watchdog.sh` `pane_work_state`** `:1664-1671`: takes `tpath`; the call is at `:1932`. Dirt comes from `session_work_at_risk` (non-strict). **Size:** +6 / −3.
- **Deleted:** 3 whole-cwd porcelain counts **[M: `git grep -n 'status --porcelain' -- bin/cc-pane-close bin/cc-husk-sweep hooks/lead-crash-watchdog.sh bin/cc-pane-verdict scripts/pane-close-retry.sh` → 3 hits: `:510`, `:511`, `:1667`]**.

**W1.6 The in-flight close lock** (`bin/kitty-fullscreen-guard`, `decide()` `:744-806`)
- At the `safe-not-last` return (`:761-762`), when `scope == "pane"`, use the lock file `state_dir()/inflight-<info.pid>-<info.os_window_id>`, created with `O_CREAT|O_EXCL`, holding `{wid, panes_in_os_window, ts}`.
- If a lock exists for **another** wid, its recorded pane count still equals the current count, and it is younger than 30 s → return `3, "refused-inflight"`. That close has not landed yet.
- If the count dropped, or the lock is older than 30 s → take it over.
- Our own wid → proceed.
- No extra kitty call: the kitten reply already carries both fields.
- **Effect:** every caller gets it (runner, hold, it2-kitty close, cc-pane-close, zshexit). Two holds released together now close one at a time, and the second re-reads "last" and keeps holding.
- **Size:** about +30 Python.

**W1 tests** (run serially under /bin/bash 3.2 and checked with `/bin/bash -n`, plus the ratchets in `.claude/rules/agent-operating-lessons-situational.md:260`):
- `tests/pane-289-replay.bats`, specified in §6.
- **Inversions** (each a behaviour change the GOAL requires; give the old expectation a named control):
  - `tests/pane-close-from-inside.bats:186-192` ("the guard refusing … keeps the shell") → hold, then close on a `3,0,0` sequence.
  - `tests/cc-pane-runner-no-command-closes.bats:52, 81, 88-89, 99, 112` and `tests/cc-pane-runner-exit75-closes.bats:63, 136` run with `CC_PANE_HOLD=0`. Otherwise a stub that always says 3 hangs the suite. Plus one new held case each.
  - `tests/cc-husk-sweep.bats:93` ("uncommitted … forces RESUME whatever the session said") → own edit-recorded dirt forces RESUME; sibling dirt does not.
  - `tests/lead-crash-pane-verdict.bats:91, 176` (`dirty:1` from an untracked file) → own edit-recorded dirt only.
- **Must stay green unchanged:**
  - `tests/cc-pane-close-background.bats:149` (C2: a crashed teammate with uncommitted work is refused) through the strict path.
  - `tests/cc-pane-close.bats:186` (teammate fixture) the same way.
  - At implementation, confirm `dirt_unreachable_by_session` returns 1 or 2 on that untimestamped fixture.
- **New suites:**
  - `kitty-fullscreen-guard.bats`: lock cases (two wids at the same count → second refused-inflight; count dropped → takeover; stale >30 s → takeover).
  - `handoff-selfclose-*.bats`: the stand-down case (a held record yields no alarm, no husk row, no close call).
  - `session-writes.bats`: `session_work_at_risk` (non-repo → 1; own dirty → 0; sibling-only → 1; rc 2 → 0; strict with untimestamped dirt → 0).
  - A **lint**: any `status --porcelain` in `bin/cc-pane-close`, `bin/cc-husk-sweep` or `hooks/lead-crash-watchdog.sh` fails.

**W1 mutants** (each must turn at least one W1 test red):

| ID | Mutation |
|---|---|
| M1 | Hold exits on the first guard read |
| M2 | Hold execs a shell on refused-fs (HEAD behaviour) |
| M3 | No INT/TERM traps |
| M4 | HUP exits without asking the guard |
| M5 | Release after one rc-0 read |
| M6 | Restore porcelain at `cc-pane-close:510` |
| M7 | Restore `cc-pane-verdict:86-87` |
| M8 | Restore `work_of` porcelain |
| M9 | Restore `pane_work_state` porcelain |
| M10 | `strict` ignored (C2 pin goes red) |
| M11 | rc 2 read as not-at-risk |
| M12 | No HELD in the sweep |
| M13 | Guard without the lock |
| M14 | Watcher without the stand-down |

**W1 size:** code about +230 / −50; tests about +450 **[E: sum of the sketches above]**.

---

### W2: every fleet launch rooted in the runner (Track A Phase 2, trimmed)

**W2.0 Precondition: lr-fire-resume must report claude's exit status**
- After `interact` (`scripts/limit-recover/lr-fire-resume.sh:2235`), add reso-resume-one's three lines verbatim (`bin/reso-resume-one:1108-1110`: `catch {wait}`; `CHILDKILLED` → 1; `exit [lindex $w 3]`).
- **Test:** a stub claude killed by SIGTERM gives `lr_rc` ≠ 0, and the runner keeps the pane (`kept:crash`).
- **Mutant:** omit the wait. The SIGTERM case closes the pane, violating S4.
- Today `lr_rc` is 0 for every end. **[E: reso-resume-one:1103-1104 states this for the identical construct; not measured on lr-fire-resume.]**

**W2.1 lr-fire-resume tail**
- After the successor claim (`:2253-2275`): `[ "${CC_PANE_RUNNER_OWNS_CLOSE:-}" = 1 ] && exit "$lr_rc"`.
- Delete the "ordinary shell" banner and the shell for that case (`:2276-2304`). A typed launch outside the runner keeps the shell (ruling 337e100f5c71).
- **Size:** +4 / about −20.

**W2.2 reso-resume-one tail**
- Under `CC_PANE_RUNNER_OWNS_CLOSE=1`, after `rr_successor_take_exec`: `exit "$rr_rc"`.
- Delete `rr_close_on_clean_exit` (`:1136-1186`), because the runner now owns the close.
- **Size:** +3 / about −50.

**W2.3 Root the resume wrappers**
- `scripts/boot-resume-launch.sh:258` and `bin/cc-resume-layout.sh:1053, :1359` launch `--env CC_PANE_CMD=… --env CC_PANE_CMD_INTERACTIVE=1 --env CC_PANE_RUNNER=… -- zsh -l -i -c 'exec /bin/bash "$CC_PANE_RUNNER"'`, the shape at `scripts/handoff-fire.sh:1325-1326`.
- Delete `|| exec zsh -i` and the survivability rule `scripts/boot-resume-launch.sh:240-242` (recycle is covered by `kept:recycle` at `bin/cc-pane-runner:295-298`).
- `scripts/limit-recover/lr-lib.sh:1343-1345`: no runner → refuse, never the bare `(-- /bin/bash "$1")`.

**W2.4 Successor tail and relaunch lines**
- `lib/pane-successor.sh:236-240`: under the runner, call `cc_pane_successor_exec "$c" 0` (no trailing shell).
- The typed relaunch lines (`scripts/handoff-fire.sh:3775-3785` `hf_resume_cmd_set`; `bin/cc-husk-sweep:619-628`) start `[ -x "$R" ] && exec env CC_PANE_CMD=… CC_PANE_CMD_INTERACTIVE=1 /bin/bash "$R"`.
- `lib/pane-successor.sh:341` (the zshexit re-exec) stays: it guards an operator's root shell.

**W2.5 Teammate signal exits (Track A 1.8)**
- A `--agent-id` verb that exits 143 or 137 goes to `_close_pane` instead of `_kept_line` (`bin/cc-pane-runner:273-275`). Teammates are never resumed (`bin/cc-husk-sweep:608`).
- Evidence: panes 141 and 142 **[TA]**.

**W2.6 Placement: held windows first**
- In `scripts/lib/pane-placement.sh` `_ccp_decide`, the sort at `:163` becomes `(0 if held_only(t) else 1, -panes(t), id)`.
- `held_only` = every window's `foreground_processes[].cmdline[0]` basename includes `cc-pane-held`.
- Rig containment (`:156-158`) is unchanged.
- **Size:** +7.

**W2.7 Inverted pins**
- `tests/kitty-recovery-launch.bats:459-516` (SURVIVABILITY) and `tests/handoff-recycle-pane-survives.bats:531-575` become "rooted in the runner; a clean exit closes or holds".
- Add a launch-site lint: no `exec zsh -i` or `exec "${SHELL` fallback in fleet launchers. The allowlist covers the runner's fallback, the hold's EXIT fallback, the zshexit hook, and `kitty-split-cwd.sh`.

**W2 mutants:** omit the wait (W2.0); keep `|| exec zsh -i`; drop the `[ -t 0 ]` / `OWNS_CLOSE` test (an operator-typed launch then closes its pane).

**W2 size:** about +60 / −200 **[E: Track A's Phase 2 deletion estimate, minus 2.1]**.

---

### W3: truthful verdicts for what is still kept (Track A Phase 3, trimmed, plus the omitted actors)

- **W3.1 One final-turn close reader (Track A 3.1)**
  - "yes" counts only in the last main-chain assistant text, with no later user record, tool_use or open tool window.
  - It replaces `bin/cc-pane-close:342-367` (`transcript_facts`), `hooks/lead-crash-watchdog.sh:1677-1711` (`pane_last_close`) and `bin/cc-husk-sweep:452-507` (`facts_of`).
  - It fixes the live stale-yes bug: 5 sessions in 4 days **[TA red team 1]**.
- **W3.2 Watchdog**
  - The crash branch (`:2005-2030`) reads W3.1: a final-turn yes → DONE (D3).
  - The RECYCLE branch (`:1995-2004`) reads custody (D1).
- **W3.3 Drainer operator-owns rule**
  - Read `first_ts` before `pcq_remove` (`scripts/pane-close-retry.sh:279`).
  - On removal, delete `run/pane-verdict/<kpid>-<pane>.json`, so a frozen paint is not "unchanged" forever.
  - Reap paint records for panes absent from `ls`.
- **W3.4 rc124 as its own class**
  - In `:310-313`, log `timeout` to `pane-close.jsonl` as well.
  - Do not let rc124 count toward the `MAX_ATTEMPTS` page.
- **W3.5 boot-resume selection**
  - In `scripts/boot-resume.sh` beside `retired_marker` (`:783`), retire a sid when either holds:
    - its last `Session ended sid=… reason=prompt_input_exit` line (written by `hooks/session-end.sh:34-35`) is newer than its last activity, with no later SessionStart for it;
    - W3.1 reads a final-turn yes.
  - Kill switch: the existing `CC_BOOT_RESUME_SKIP_RETIRED`.
  - **Size:** about +20.
- **W3.6 custody-deathwatch** `:394`: the husk clause says `cc-husk-sweep --pane ${target}` (read-only triage), not `--resume --yes`. 1 line.
- **W3.7 Unlanded, own-scoped**
  - Sweep `:513` and watchdog `:1669` use `session_unlanded_mine` (`hooks/lib/session-writes.sh:596`) against `origin/HEAD` when it resolves, else skip.
  - Today `origin/main` fails open on repos without it (D6).
  - **Measured:** 2 such sites **[M: `git grep -n 'origin/main..HEAD' -- bin/cc-husk-sweep hooks/lead-crash-watchdog.sh bin/cc-pane-close`]**.
- **Tests:**
  - A stale yes followed by SIGTERM → refuse, and RESUME is painted.
  - A crashed teammate with its own edits → refused.
  - Restart after an `/exit` with no self-close → not resumed.
  - deathwatch text.
  - rc124 logged without paging.
  - **Mutants:** read "any yes" instead of the final turn; drop the SessionEnd rule.
- **W3 size:** about +130 / −110 **[E]**.

---

## 6. `tests/pane-289-replay.bats`: RED at HEAD, GREEN after W1

### The fixture (`fixture_289`)
- `$CWD`: `git init -b master`, with no remote. Two "own" files (`own/NOTES.md`, `own/scene.py`) are committed clean.
- **Sibling dirt** (none of it the session's):
  - 2 modified tracked files and 3 untracked files under `deadlines/items/`, all with `touch -t` before the session start;
  - 1 file with an mtime after the exit.
  - This mirrors 562 predate / 1 after **[TA closer map §4]**.
- **Transcript** `$STORE/projects/p/$SID.jsonl`:
  - a user record with `cwd`;
  - assistant `Edit` on `own/NOTES.md` and `Write` on `own/scene.py`, each with a tool_result;
  - assistant text `✅ Good to close: yes`;
  - a final assistant `Bash` tool_use (the self-close) with **no** tool_result: an open window, bg=1 shape.
- Watchdog log registration `pane=289 tty=ttys046` inside the kitty lifetime.
- Exit record `{"rc":0,"claude_started":true,…}`.
- No custody row, so COLLECTED cannot rescue the verdicts and the work fix must stand on its own.

### Arms

| Arm | Run | Asserts after W1 | Why RED at HEAD |
|---|---|---|---|
| **A1 runner** | `KITTY_WINDOW_ID=289`; `CC_PANE_CMD=<stub launcher>` that touches `$CC_PANE_STARTED_FILE` and exits 0; guard stub sequence `3,3,0,0` with `refused (refused-fs) … state=FS types=[4] onscreen=False`; hold seams `GAP_S=0, MIN_S=0`; `SHELL=fakeshell` (writes a sentinel and exits 7, as at `tests/pane-close-from-inside.bats:44`); a `git` logging stub first on PATH | status 0. No shell sentinel. The guard log has 4 lines: line 1 `--tool cc-pane-runner`, lines 2-4 `--tool cc-pane-hold`. Record tail `closed`, with a `held:guard-fs` transition logged first. The queue dir is empty. The git stub was never called. Final assertion: `run grep -E 'RESUME|stopped mid-task|--resume' pane-say.jsonl; [ "$status" -eq 1 ]` (never a mid-test `!`). | status 7, the shell sentinel exists, and a husk row exists (`bin/cc-pane-runner:332`, `:579`, `:104`) |
| **A2 hold identity and signals** | Background runner; the guard returns 3 until `$T/release` exists | `ps -o command= -p $pid` = `cc-pane-held /dev/fd/3`. After `kill -TERM` and `-INT`, still alive. `kill -HUP` while the guard says 3 → still alive. `touch release` → exits 0 within 5 s. A `script(1)` pty variant also sends ^C, ^\ and ^Z. | The process is the fakeshell, which exits at once |
| **A3 deaf kitty** | Guard `3 (kitten-failed)`, then `0,0` | tail `held:guard-unreadable` → `closed`. Paint row 2 is "kitty didn't answer". | Shell plus husk row |
| **B1 closer** | `cc-pane-close --pane 289 --dry-run` (remote off, guard 0) | `WOULD CLOSE … Good to close: yes` | `REFUSED — … holds N uncommitted change(s)` (`:510-511`) |
| **B2 reconciler** | `cc-pane-verdict --pane 289 --recompute --closer-out 'pane 289: REFUSED — /x holds 138 uncommitted change(s)' --dry-run` | `state=CANTTELL`; no "stopped mid-task"; no `--resume` | `state=RESUME` (`:86-87`) |
| **B3 sweep** | `cc-husk-sweep --json` with `CC_HUSK_PANES_JSON`, `CC_HUSK_PS_FILE`, `CC_HUSK_STORES` and `CC_HUSK_WATCHDOG_LOG` | `"work":"clean","verdict":"DONE"`; `--resume --yes` → "nothing to resume" | `"work":"dirty","verdict":"RESUME"` (`:511`, `:517`) |
| **B4 watchdog, kept shell (rollback)** | `--pane-verdict` entrypoint, harness of `tests/lead-crash-pane-verdict.bats:23-53`; procs file `Ss+ -zsh` | `pvs=DONE` | `dirty:N` → CANTTELL (`:1667`, `:1997`) |
| **B5 watchdog, held** | procs file `S+ cc-pane-held /dev/fd/3` | NOT PAINTED; no husk row | Green at HEAD too (a pin: `pane_procs_are_shells` at `:1640-1647`) |
| **B6 sweep over held** | The PS file shows `cc-pane-held` under the window pid | verdict `HELD`; `--resume --all --yes` types nothing | It types the resume line (no HELD) |
| **C1 crash pin (S4)** | rc 143 stub, with an own edit-recorded dirty file | Runner status 7 plus husk row `crash`. Closer dry-run REFUSED (non-teammate: "nothing says"; teammate variant: own work). Sweep RESUME. | Green at HEAD and after (safety pin) |
| **C2 rollback** | Policy file `off`, guard 3 | Today's path: shell plus husk row `guard-fullscreen` | Green at both (pin) |
| **C3 fail-closed** | Guard always 3, `CC_PANE_HOLD_MAX_S=1` | EXIT fallback: shell, tail `kept:fallback`, one husk row | RED (no hold at HEAD) |
| **D composed, launchd-like** | After A1: `env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/bash scripts/pane-close-retry.sh` with `CC_PANE_CLOSE_QUEUE_DIR`, `CC_PCQ_PANE_CLOSE_BIN=<logging stub>` and a kitty stub listing 289 with a zsh foreground | The closer stub log is empty. pane-say has no RESUME. | The runner's husk row makes the drainer call the closer, and the recompute paints |

**Mutants named against this file:** M1, M2, M3, M4, M5, M6, M7, M8, M9, M12 and M14 from W1 each turn at least one of A1, A2, B1, B2, B3, B4, B6 or D red. The test file must **fail on HEAD in A1, A2, A3, B1, B2, B3, B4, B6, C3 and D**, and pass after W1.

---

## 7. Which wave alone makes the GOAL true

**W1 alone.** It covers every pane whose root is the runner and whose session's command returns to it:
- handoff-fire fires (pane 289's path, `scripts/handoff-fire.sh:1325-1326`);
- it2-kitty runner splits, including Claude Code teammate splits (`bin/it2-kitty:1358-1363`).

After W1, such a session (clean exit, "Good to close: yes", own paths clean) either:
- **closes** (guard safe), or
- **holds**: owned, labelled DONE, never painted resume, no husk row, no outside closer. It releases itself on two safe reads under the lock, e.g. when placement adds a pane, as happened 23 min after 289's exit **[TA selfclose map §3: 293 joined at 00:16:58Z]**.

W1 also makes the **never-painted-resume** half true for **every** pane, runner-rooted or not:
- the reconciler's only RESUME-from-dirt arm is gone;
- sibling dirt no longer drives gate 4, the sweep or the watchdog.

**Not true after W1 alone**, so W2 is needed: resume-launched panes. Those are lr-fire-resume, reso-resume-one via boot-resume, and cc-resume-layout. They still end in a kept shell (lr) or an unqueued shell on a guard refusal (reso). Scale: 6 real lr-fire-resume husks since 10-19 **[TA recycle map §2a]**, against 22 of 28 runner-kept panes since 10-20 that were guard keeps **[C §4e]**.

---

## 8. Risks

| # | Risk | Severity | Mitigation / residual |
|---|---|---|---|
| R1 | SIGKILL of a held process empties a fullscreen last pane, crashing kitty | critical, rare | Same as today's kept zsh. The hold's argv carries no brief, so `pkill -f` on brief text cannot match it. Named residual. |
| R2 | ^Z or ^C reaching a child `sleep` wedges or ends the hold | medium | The builtin `read -t` on a private fd: no child to stop or kill. The EXIT fallback otherwise. A pty test is required: Track A's probe ran in the background, where INT is ignored **[TA R1]**. |
| R3 | A HUP from a non-kitty sender | medium | HUP asks the guard and exits only on rc 0 or 4 (Track A exits on any HUP) |
| R4 | Correlated releases (several holds, kitty answers) | high without W1.6 | The in-flight lock in the guard, plus two reads 10 s apart. Residual: an **unguarded** exit (a non-runner pane's process dying) racing a release, which exists today. |
| R5 | Stale lock after a caller that asked and did not close (a `--dry-run`) | low | 30 s expiry. Holds just wait. |
| R6 | Hold polling adds kitty remote-control load while kitty is deaf | medium | Backoff to 300 s for unreadable. W0 reports the held count. Estimate: 10 holds ≈ 10 kitten calls a minute worst case **[E: 10 × 1/60 s]**. |
| R7 | `session_dirty_mine` misses files written only through Bash (`hooks/lib/session-writes.sh:39-54`) | low | Applies only after gate 3 passed on the session's own word, a stamp or a custody discharge. A pane close never deletes files. The `teamName`-only path keeps the per-path proof. Effect: "yes plus Bash-only own dirt" changes from sweep RESUME to DONE. |
| R8 | `session_dirty_mine` rc 2 under load (jq bounded at 5 s on a 5.4 MB transcript) | low | Fail-closed: the pane stays kept on the non-runner path. The runner path never runs git (asserted in A1). |
| R9 | An off-screen fullscreen sole pane stays held until a pane joins or ⌘W (the 363/476 shape: "no later row within 30 h", **[TA selfclose map §4]**) | medium | W2.6 fills held windows first. W0 pages at 6 h. **Operator decision outstanding:** e3920969aba9's exit condition (fsfix) never held (`fsfix:false` on 977 of 977 guard rows **[C §1]**), and fd34d855d makes lone fired peers sole fullscreen panes. Code cannot settle this. The hold makes it honest. |
| R10 | W2's lr-fire-resume exit code is 0 for every end, so a killed session's pane would close | **high if W2.0 is skipped** | W2.0 is a precondition, with its own red test. |
| R11 | Running panes keep their old runner functions in memory until relaunched | medium | W0's metric shows legacy husks until the fleet turns over. Nothing to do. |
| R12 | Inverting `cc-husk-sweep.bats:93` and `lead-crash-pane-verdict.bats:91, :176` is a policy change ("sibling dirt no longer outranks the word") | medium | This is the GOAL's own statement. Keep a positive control: own edit-recorded dirt still forces RESUME or CANTTELL. |
| R13 | An env rollback does not reach kitty-spawned panes | low | The rollback is a file read at hold entry (§3, runner row) |

---

## 9. Numbers ledger

- **[M]** HEAD `fa9cadc24` (`git log -1`).
- **[M]** File sizes (`wc -l`): cc-pane-runner 646, cc-pane-close 557, cc-pane-verdict 176, cc-husk-sweep 629, pane-close-retry.sh 517, handoff-fire.sh 21830, lead-crash-watchdog.sh 2761, session-writes.sh 670, kitty-fullscreen-guard 1019, pane-placement.sh 283.
- **[M]** 3 whole-cwd porcelain counts and 2 `origin/main..HEAD` counts in the re-judging actors (the `git grep` commands in W1.5 and W3.7).
- **[M]** 6 `_husk_row` tokens in the runner (`git grep -c _husk_row bin/cc-pane-runner`): 1 definition plus 5 calls (`:292`, `:316`, `:332`, `:337`, `:365`). W1 deletes 2 from the default path.
- **[M]** Runner tests that pin the old keep: 5 `GUARD_RC=3` lines in `cc-pane-runner-no-command-closes.bats` and 2 in `cc-pane-runner-exit75-closes.bats` (`grep -n GUARD_RC=3`), plus `pane-close-from-inside.bats:186`.
- **[TA]** 390 runner guard verdicts since 10-15, of which 36 refused: 13 fs, 22 kitten-failed, 1 unknown. All 10 of 10 rc70 self-closes became husks. 7555024a: `session_dirty_mine` rc 1; 562 of 563 dirty paths predate the session. Pane 289: 21 drainer attempts (9 gate-4, 12 rc124). 6 lr-fire-resume husks, 5 of which said yes.
- **[C]** 22 of 28 runner-kept panes since 10-20 were guard keeps. `fsfix:false` on 977 of 977 guard rows (10-16 to 10-25).
- **[E]** All LOC figures (sketch line counts) and R6's load figure.

## 10. Deviations and limits

- Read-only throughout. No test was run and no mutant was executed. The "RED at HEAD" column in §6 is inferred from the cited code paths, not measured.
- Not measured, and should be measured first:
  - lr-fire-resume's actual exit code after a SIGTERM (W2.0, R10);
  - `dirt_unreachable_by_session`'s answer on the C2 fixture (W1 tests);
  - the guard's per-call cost under load (R6).
- custody-deathwatch is not in the census actor table. I found it by grepping for `--resume --yes` (`git grep -n 'cc-husk-sweep --resume --yes' -- bin scripts hooks lib`).
