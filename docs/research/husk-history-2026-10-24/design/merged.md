# Husk-pane fix: the merged design (judge's ruling, 2026-10-24)

Inputs: `design-minimal.md`, `design-faithful.md`, Track A `REPORT.md` §4-§6, census `CENSUS.md` §3/§4/§6.
Every code citation was re-read at HEAD `fa9cadc24` of `.worktrees/husk-skill-and-fix` (`sed -n`, `grep -n`,
`git grep -n`). The repo was only read. Written: this file, `/tmp/husk-fix-design/c2probe/` (a probe that
sources two repo libraries against a temp fixture; no kitty, no pane). Numbers are tagged **[M]** measured (the
command is in §7), **[C]** measured by the census or Track A and cited, **[E]** estimated (method in §7).

---

## 0 Ruling in brief

- **One owner.** `bin/cc-pane-runner` is the window's root process and the only actor that can end a pane
  with no socket. After its command returns it **closes**, **holds**, or **keeps** a shell, and writes which one
  into the record it already writes (`tail` in `~/.claude/run/pane-exit/<wid>.json`).
- **The hold runs in the runner's own process** (minimal design). No `exec -a cc-pane-held`, no rename, no
  `/dev/fd/3` body, no trust fields, no env or file rollback switch, no HELD sweep verdict.
- **Outside actors stand down by one rule.** "A live `cc-pane-runner` in the pane's foreground owns the pane"
  is a one-line pattern in the watchdog, the drainer and the sweep. The self-close watcher is the one reader of
  `tail`, because it must tell a hold from a keep while the runner is still deciding.
- **Kept from Track A for safety:**
  - the hold: two safe reads at least 10 s apart; signals ignored; an EXIT-trap fallback; no tty reads;
  - a close reservation inside `kitty-fullscreen-guard`, moved into the GOAL wave. Holds that start in the same
    deaf-kitty episode share a backoff schedule and would confirm together. 22 of the 36 runner refusals since
    10-15 were kitten-failed **[C REPORT §3]**.
- **One dirt subject.** Every re-judge (gate 4, the sweep, the watchdog) asks `session_dirty_mine`, not the shared
  checkout:
  - It also checks unlanded commits, keyed on the session.
  - It runs a **strict** per-path proof only when the session is known *not* to have ended cleanly. That is the
    hard invariant "a crash with its own work is kept". Measured on a C2-shaped fixture: `session_dirty_mine`
    returns rc 1 (so it would exonerate), and `dirt_unreachable_by_session` returns rc 2 (cannot tell, so the
    pane is kept).
- **The reconciler can no longer paint RESUME from a closer refusal.** `uncommitted change` maps to CANTTELL, and
  the `UNSAVED` sed is deleted.
- **GOAL wave = W1 (W1a + W1b + W1c).**
  - It turns `tests/pane-289-replay.bats` GREEN.
  - It makes the GOAL true for every pane that ends inside its runner (pane 289's path) or reaches a closer.
  - **W2 completes the GOAL** for resume-launched panes, whose launchers exec their own shells
    (`lr-fire-resume.sh:2304`, `reso-resume-one:1216`).
  - W3 and W4 are follow-on.

Size **[E: sketch line counts]**:

| wave | code | tests |
|---|---|---|
| W1 | about +190 / −100 | about +420 (replay + guard claims) and 13 pin edits (9 in W1a, 4 in W1b) |
| W2 | about +45 / −160 | |

---

## 1 The invariant

After its command returns, a runner-rooted window is in exactly one of four states:

| state | on screen | `tail` | who ends it |
|---|---|---|---|
| RUNNING | claude | none for this launch (`ts` < launch) | the session |
| CLOSED | nothing | `closed` | the runner's `exit 0`, after the guard said safe *and reserved the window* |
| HELD | one DONE/NOTHING paint; the runner alive with no command child | `hold:fs` / `hold:unreadable` | the runner: two safe reads at least 10 s apart, the second one reserving; or the operator's ⌘W; or kitty itself gone |
| KEPT | a shell exec'd by the runner | `keep:<r>`, r ∈ crash, recycle, kill-switch, not-a-session, no-guard, no-recycle-lib, fallback | the operator, the crash/resume path, or a recycle |

A bare shell over a dead fleet session whose tail is not `keep:*` is an **anomaly**: W3 counts it, and it is
never a resting state.

**Hard invariants, and the mechanism that holds each:**

1. **Never empty the last pane of a fullscreen window.**
   - Every exit follows a guard rc 0 that also took the window's reservation (W1c), or a read saying the
     window is gone (rc 4), or a dead `KITTY_PID`.
   - INT, QUIT, TSTP, TERM and HUP are SIG_IGN during the hold.
   - An unplanned exit runs the EXIT trap, which gives a shell (today's state).
2. **Never close a pane with a live job.** The runner decides only after its command returned, as today's rc-0
   close (`bin/cc-pane-runner:257-278`). kitty keeps a window whose pty another process still holds.
3. **Never resume a finished session.**
   - Nothing in W1 paints RESUME for a held or closed pane.
   - The sweep treats a runner in the foreground as live and never types into it.
   - The reconciler loses its dirt→RESUME arm.
4. **A crash with its own uncommitted work is kept/resumed.**
   - `keep:crash` is unchanged (`_kept_line`, `:358-375`).
   - Gate 4 and the sweep run the strict proof for a known crash, so Bash-only own writes still keep the pane.
   - The watchdog's crash paint is unchanged (`hooks/lead-crash-watchdog.sh:2005-2030`).

---

## 2 Decision log

Each entry gives the options (Track A / faithful / minimal / other), the **choice**, and the reason.

**D1. Where the hold runs.**
- Options:
  - Track A and faithful: `exec -a cc-pane-held /bin/bash /dev/fd/3` with a `declare -f` body and env
    marshalling.
  - Minimal: an in-process `_hold`.
- **Choice: in-process.**
- Why:
  - The runner already is the window's process.
  - `_launch` never returns (`bin/cc-pane-runner:546-580`, called at `:591`/`:646`), so bash reads nothing more
    from the script file once the hold starts. The R2 "re-read from disk" class does not arise.
  - Re-measured **[M]**: under /bin/bash 3.2.57, a SIG_IGN loop stayed alive through INT, QUIT, TSTP, TERM and
    HUP sent to its process group, and kept polling. It released (rc 0) only after two safe reads. One safe read
    followed by a refusal did not release. An unplanned exit ran the EXIT trap and exec'd the fallback with INT,
    TERM and HUP *not* ignored.

**D2. Wait primitive and signal disposition.**
- Options:
  - Track A / faithful: logging handlers, plus a builtin `read -t` on a private fd, because a child `sleep`
    could be stopped by ^Z.
  - Minimal: `trap ''` (SIG_IGN) plus `/bin/sleep`.
- **Choice: SIG_IGN plus `/bin/sleep`.**
- Why:
  - SIG_IGN is inherited by the `sleep` and guard children, so ^C/^Z sent to the foreground group are dropped by
    every member. Faithful's R2 applies to *handlers*, which reset to default on exec.
  - Track A's objection ("SIG_IGN is inherited across exec") is met by `trap -` before the fallback exec
    (measured above).
  - The guard's own kitty call stays bounded: `subprocess.run(..., timeout=KITTY_CALL_TIMEOUT_S)`
    (`bin/kitty-fullscreen-guard:253`, `:120` = 5.0 s) kills with SIGKILL, which an ignored TERM cannot block.
- Residual: a pty test (`script(1)`) is still added, because the probe sent signals with `killpg`, not through
  a terminal.

**D3. SIGHUP and an orphaned hold.**
- Options:
  - Track A: exit on HUP.
  - Faithful: ask the guard once.
  - Minimal: ignore it; two rc-4 reads end the hold.
- **Choice: ignore HUP, and exit when `KITTY_PID` no longer exists.**
- Why:
  - ⌘W or a kitty-side close turns the window into `not-found`. The guard returns 4 (`:753`) and the hold leaves
    after two reads.
  - **Gap in both designs:** if kitty *quits*, the kitten call fails, giving `kitten-failed` rc 3 (`:756-758`)
    forever, so the orphan polls forever. `kill -0 "$KITTY_PID"` (kitty exports it, as `_husk_row` uses at
    `:167`) is one line.
  - PID reuse errs toward holding, which is safe.

**D4. How outside readers stand down.**
- Options:
  - Track A: rename the process; readers key on the name.
  - Minimal: `tail` reads with freshness rules in the watcher, the watchdog and the drainer, plus a sweep pattern.
  - Other: a process-identity pattern.
- **Choice:**
  - **Process identity** for the watchdog `pane_procs_are_shells` (`hooks/lead-crash-watchdog.sh:1640-1647`),
    the drainer `shell_only` (`scripts/pane-close-retry.sh:421-426`) and the sweep `has_claude_under`
    (`bin/cc-husk-sweep:206-219`). One line each.
  - **`tail`** only in the self-close watcher.
- Why:
  - "A live runner owns its pane" is exactly the invariant. It needs no freshness or trust rule, and when the
    runner keeps, it exec's a shell, so the rule turns off by itself.
  - The watcher alone acts during the seconds the runner is still deciding, so it needs the decision, not the
    process.
  - The runner's argv already contains "claude" by install path **[M]**: `~/.claude/bin/cc-pane-runner` points to
    `…/claude-infrastructure/bin/cc-pane-runner`. The sweep therefore skips it today by accident; the pattern makes
    that intentional.

**D5. Record trust.**
- Options:
  - Track A: 6 fields, plus an ancestor walk.
  - Faithful: 4 fields.
  - Minimal: `tail` only.
- **Choice: `tail` only.**
- Why: the watcher, the only `tail` reader, accepts the record when `ts` ≥ the watcher's own start
  (`_sc_t0`). That rejects a reused window id from an older kitty (ids restart at 1). The watcher polls only when
  `CC_PANE_RUNNER_OWNS_CLOSE` is set and the pane id is numeric; otherwise every non-runner self-close would
  wait 20 s (see D19).

**D6. Rollback switch.**
- Options:
  - Track A: `CC_PANE_HOLD=0` env.
  - Faithful: a policy file.
  - Minimal: none.
- **Choice: none; rollback is `git revert` of W1a.**
- Why:
  - An env var cannot reach kitty-spawned panes (`bin/kitty-fullscreen-guard:75-77`).
  - A file is another moving part.
  - The hold is entered only on a path that ends in a shell today, so a revert restores HEAD exactly for new panes.
- Test seams: `CC_PANE_HOLD_STEP_S` (default 5) and `CC_PANE_HOLD_MAX_POLLS` (default unset). The second
  takes the escape path in tests.

**D7. Two closers reading "not last" at once.**
- Options:
  - Track A: an mkdir lock in Phase 2.
  - Faithful: an O_EXCL lock in the guard in W1, with takeover.
  - Minimal: none in W1; an atomic kitten close later.
- **Choice: W1c, a reservation inside the guard.**
  - It is `flock`-serialised: read, decide and write happen under one lock.
  - It is **on by default** for every `safe-not-last` verdict.
  - Reads that will not act opt out with `--peek`. Those are `cc-pane-close --dry-run` and the hold's
    non-confirming reads.
- Why:
  - The hold creates a new trigger. Two clean exits in one fullscreen OS window during a deaf-kitty episode both
    hold `unreadable` on the same schedule. When kitty answers, both read "2 panes, not last" within milliseconds,
    and both confirm 10 s later. The window is emptied: the 10-15 crash.
  - At HEAD these two panes became shells, and the drainer closed them serially (one drainer at a time,
    `scripts/pane-close-retry.sh:66-70`).
  - The two-read rule does not de-correlate aligned schedules.
  - flock avoids O_EXCL's stale-takeover race.
  - "Default on" means **0 of the 9 exact guard-argv pins change** **[M]**; only the hold's reads and the dry-run
    gain `--peek`.
- Faithful's O_EXCL takeover can let two takers both proceed. Minimal's atomic kitten close is unverified,
  because it depends on whether kitty removes the window inside the same main-loop step. It is kept as W4f.

**D8. The work-at-risk subject.**
- Options:
  - Track A: a 3-function chain plus an allowDirty stamp.
  - Faithful: `session_dirty_mine`, plus strict mode only when gate 3 passed on `teamName`.
  - Minimal: `session_dirty_mine` only, with the C2 fixture rewritten to record a Write.
- **Choice: `session_work_at_risk <tp> <dir> [strict]`**, a wrapper of the existing `session_dirty_mine` and
  `session_unlanded_mine`.
  - **strict** runs `dirt_unreachable_by_session` (unmodified, `hooks/lib/peer-owned.sh:822`) when the session is
    *known* not to have ended cleanly. Any of these makes it known:
    - a fresh exit record with rc ∉ {0, 75};
    - a crash-log cause ∉ {clean-exit, -};
    - gate 3 passed on `teamName` alone.
  - No allowDirty stamp.
- Why:
  - The repo's own doctrine (`hooks/lib/session-writes.sh:45-53`): exonerating on `session_dirty_mine` rc 1
    inherits the Bash-write blind spot. It is acceptable where the misread costs a close over files left on disk
    (a clean exit). It is not acceptable for a crash keep (hard invariant 4).
  - Measured **[M]** on a C2-shaped fixture (teammate transcript, no recorded writes, one untracked file):
    `session_dirty_mine` rc 1 and `dirt_unreachable_by_session` rc 2. So minimal's version would close a crashed
    teammate's pane, and the strict one keeps it without rewriting the C2 fixture.
  - Pane 289 exited cleanly, so it never takes the strict path. Track A measured that the chain returns
    "unknown" for 7555024a; this is why 3.3's stamp is not needed.
  - The unlanded commits are folded in: the 2 remaining whole-checkout counts **[M]** (`origin/main..HEAD`,
    `bin/cc-husk-sweep:513`, `hooks/lead-crash-watchdog.sh:1669`) are the same failure class at the same sites.

**D9. What the reconciler paints for a gate-4 refusal.**
- Options:
  - HEAD: RESUME with an "N unsaved" count.
  - Minimal: RESUME with the session's own count.
  - Faithful: CANTTELL.
- **Choice: CANTTELL; delete the `UNSAVED` sed** (`bin/cc-pane-verdict:86-87`).
- Why:
  - Gate 4 runs only after gate 3 said the session meant to end (`bin/cc-pane-close:489-506`), so "stopped
    mid-task" contradicts gate 3 by construction.
  - For a teammate (never resumable, `bin/cc-husk-sweep:608`) RESUME is false.
  - For the same facts on a clean exit, the watchdog already paints CANTTELL (`hooks/lead-crash-watchdog.sh:1995-1997`).
  - The resume decision stays with the sweep, which reads custody and its own facts.
  - The crash-without-yes RESUME (`:89`, `--reason crash`) is unchanged.

**D10. Sweep over a held pane.**
- Options: Track A / faithful: a HELD verdict (+12). Minimal: a pattern.
- **Choice: the pattern** `*claude*|*cc-pane-runner*` at `bin/cc-husk-sweep:214`.
- Why: a runner in the foreground means the pane is live, so it is never listed and never typed into.

**D11. ⌘W confirm dialog over a hold.**
- Options: minimal changes `is_busy` in W1; faithful defers.
- **Choice: defer to W4c.**
- Why: the dialog is safe. It shows "sleep", because `jobs_in` skips `bash` and `cc-*`
  (`bin/kitty-confirm-close:270-290`), which is cosmetic.

**D12. The census metric.**
- Options: faithful puts it in W0, before the fix; minimal puts it in W3; Track A gives it its own launchd job.
- **Choice: W3, inside the existing drainer job, before its empty-queue exit** (`scripts/pane-close-retry.sh:63-64`).
- Why:
  - It is independent and may land before W1.
  - It is not a GOAL precondition: the replay test is the gate, and a retrospective baseline exists in
    `kitty-pane-actions.jsonl` and `pane-say.jsonl` **[C §4e-f]**.

**D13. The lr-fire-resume tail (W2).**
- Options: minimal: unconditional `exit "$lr_rc"`; faithful: conditional, with a wait-forwarding precondition.
- **Choice: faithful's precondition W2.0, plus an exit only when the runner owns this window**
  (`CC_PANE_RUNNER_OWNS_CLOSE` = `$KITTY_WINDOW_ID`).
- Why:
  - The expect program ends at `interact` with no `wait` (`scripts/limit-recover/lr-fire-resume.sh:2235`). Its
    sibling documents that this construct "exits 0 however the session ended" and fixes it
    (`bin/reso-resume-one:1103-1110`). So `lr_rc` is 0 for every end **[E: sibling's statement; not measured on
    lr]**, and closing on it would close killed sessions' panes.
  - Under a `zsh -ic` root, an unconditional exit closes the window *unguarded*.

**D14. Teammate exit 143/137 → close (Track A 1.8).**
- **Choice: dropped.** It widens the close predicate and is not needed for the GOAL.

**D15. Placement: fill held windows first.**
- **Choice: W4a, as a sort key only.** Not needed for the GOAL; it only shortens holds.

**D16. custody-deathwatch's resume text** (faithful W3.6).
- **Choice: W4e, off the GOAL path.** It fires only on an *open* custody debt
  (`scripts/custody-deathwatch.sh:390-394`). Pane 289's custody was returned before exit **[C REPORT §2.1]**.

**D17. boot-resume retirement** (faithful W3.5).
- **Choice: W4d.** It is pre-existing (a roster snapshot later than a non-self-close `/exit`) and independent of
  the hold.

**D18. What an unplanned exit from the hold leaves.**
- Options: minimal: a tail only; faithful: a tail plus a husk row.
- **Choice: tail `keep:fallback` plus one husk row `hold-escape`.**
- Why: it keeps today's fail-closed recovery (a drainer retry) for an anomaly.

**D19. Watcher poll gating** (both designs poll always).
- **Choice: poll only when `CC_PANE_RUNNER_OWNS_CLOSE` is set** (exported to the command at
  `bin/cc-pane-runner:569`, inherited by the detached watcher) **and the pane id is numeric.** Poll at most 20 s.
- Why:
  - Otherwise every non-runner self-close, and the `handoff-selfclose` suite, waits 20 s.
  - The runner's decision precedes the watcher's close by 0-6 s **[C selfclose map §2.12, via minimal]**.
- Verify at implementation that the variable reaches the watcher (`env` inside a runner pane's Bash tool) **[E]**.

**D20. Pins neither design listed.**
- `tests/cc-pane-runner-exit75-closes.bats:59` asserts the record keys are exactly
  `claude_started,launch_sha,rc,ts` **[M]**. W1a updates it to include `tail`.
- The hold code must be `set -u`-clean, because `_no_command` (`:614-623`) runs before `_launch`'s `set +u`
  (`:567`).

---

## 3 Waves

### W0: the replay test, written first (RED on HEAD)

`tests/pane-289-replay.bats`, specified in §4. Commit it with the arms that W1 turns GREEN.

### W1a: the runner owns the end (GOAL; ships with W1c)

| file:line (HEAD) | change | − | + [E] |
|---|---|---|---|
| `bin/cc-pane-runner:257-278` `_close_on_exit`, `:283-349` `_close_pane` | Replaced by `_exit_policy`, `_gate`, `_end`, `_hold`, `_hold_class`, `_hold_done`, `_hold_escape`, `_pane_exit_tail`. The recycle-lib and guard-path bodies (`:285-294`, `:308-318`) move into `_gate` unchanged. The `guard-fullscreen` and `guard-unreadable` husk rows (`:332`, `:337`) are **deleted**. | 74 code lines [M] | ≈80 |
| `:426-443` `_pane_exit_record` | Keep rc, cs, sha, ts in globals for `_pane_exit_tail`. That function rewrites the record atomically (tmp+mv) with `"tail"`. | — | +8 |
| `:576-579` | `_close_on_exit …; _fallback ""` → `_exit_policy "$1" "$_rc" "$_interactive" "$_started" "$(_pane_owed)"; _end "<verb>" "$_rc" "$_interactive" "$_started"` (both set or read the global `_TAIL`, with no subshell) | 2 | +2 |
| `:614-623` `_no_command` | `_TAIL=close` (`keep:kill-switch` when `CC_PANE_CLOSE_ON_EXIT=0`), then `_PV_STATE=NOTHING _end "this armed agent pane" 124 0 false`. This runs under `set -u` (D20). | 3 | +3 |
| `:46-63`, `:300-304` | Doctrine comments rewritten: "a clean exit closes or holds; a shell is kept only for a recorded reason". The "accepted cost is a husk" rule (`:303`) is deleted. | comments | comments |
| `scripts/handoff-fire.sh:11645` | `_sc_t0=$(date +%s)` at watcher entry | — | +1 |
| `scripts/handoff-fire.sh` near `:6693` | New `hf_pane_exit_tail PANE T0 MAXS`: polls 1 s steps up to MAXS and prints `tail` when `ts ≥ T0`. It is a separate function: adding a third word to `hf_pane_exit_record`'s "rc cs" output would break `read rc cs` callers. | — | +9 |
| `scripts/handoff-fire.sh:11831-11832` | After the tenant check (`:11827-11830`) **and after** `_close_ok=0 _close_rc=0` (`:11831`, which would otherwise reset the flag), before the loop (`:11832`): if `CC_PANE_RUNNER_OWNS_CLOSE` is set and the tail is `closed` or `hold:*`, print "pane N belongs to its cc-pane-runner (tail) — nothing to close", set `_close_ok=1`, and skip the loop. The failure arm (`:11861-11920`) is then skipped by `_close_ok`. The successor focus (`:11922`) still runs. A `keep:*` tail or no record means today's path. | — | +6 |
| `hooks/lead-crash-watchdog.sh:1640-1647` | Any foreground line whose command contains `cc-pane-runner` → `exit 1` (not shells). The settle then reports `unknown`, so there is no paint, no husk row and no grace close (`:2045`). | — | +1 |
| `scripts/pane-close-retry.sh:421-426` `shell_only` | A foreground cmdline containing `cc-pane-runner` → not shell-only, so the row is removed "in use" (`:271`). This covers deploy skew and stray rows such as `handoff-fire.sh:15809`. | — | +1 |
| `bin/cc-husk-sweep:214` | `*claude*)` → `*claude*\|*cc-pane-runner*)` | ±1 | ±1 |
| `bin/cc-pane-verdict:97-102` | Add `held) g2="closes itself when its window gains a pane · ⌘W now"`. `unreadable` already reads "closes when it does". | — | +1 |
| `scripts/handoff-fire.sh:1872-1878`, `:11816-11822`; `bin/it2-kitty:86-89`, `:1663-1667` | "a fixed fact" → "a condition: it clears when the window gains a pane or leaves fullscreen; a runner pane holds and closes itself" | comments | comments |

**Runner sketch** (bash 3.2; it must be `set -u`-safe, see D20). Neither `_gate` nor `_exit_policy` runs in a
subshell, because `_gate` sources the recycle lib and sets `_GUARD`:

```bash
_exit_policy() { # $1=cmd $2=rc $3=interactive $4=claude_started $5=owed → sets _TAIL=close|keep:<why>  (no git, no transcript)
  _TAIL=close
  _claude_verb "$1" >/dev/null || [ "${3:-0}" = 1 ] || { _TAIL=keep:not-a-session; return; }
  [ "${CC_PANE_CLOSE_ON_EXIT:-1}" = 0 ] && { _TAIL=keep:kill-switch; return; }
  case "$2" in 0|75) return ;; esac
  [ "${4:-true}" = false ] && [ "${5:-0}" = 1 ] && return
  _TAIL=keep:crash
}
_gate() { # → _TAIL=closed|hold:fs|hold:unreadable|keep:recycle|keep:no-recycle-lib|keep:no-guard
  _recycle_lib || { _TAIL=keep:no-recycle-lib; return; }
  cc_pane_recycle_pending "${KITTY_WINDOW_ID:-}" && { _TAIL=keep:recycle; return; }
  { [ -n "${KITTY_WINDOW_ID:-}" ] && [ "${CC_KITTY_FS_GUARD:-}" != off ]; } || { _TAIL=closed; return; }
  _guard_bin || { _TAIL=keep:no-guard; return; }
  local o="" i
  for i in 1 2; do   # a sibling's reservation (W1c) clears in seconds: ask once more
    o="$(cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-runner 2>&1)" && { _TAIL=closed; return; }
    case "$o" in *refused-inflight*) [ "$i" = 1 ] && { /bin/sleep 2; continue; } ;; esac; break
  done
  case "$o" in *"refused (refused-fs)"*) _TAIL=hold:fs ;; *) _TAIL=hold:unreadable ;; esac
}
_end() { # $1=verb $2=rc $3=interactive $4=started — _TAIL set by _exit_policy (or close); never returns
  [ "$_TAIL" = close ] && _gate
  _pane_exit_tail "$_TAIL"
  case "$_TAIL" in
    closed) [ -n "${_armed:-}" ] && rm -f "$_armed" 2>/dev/null; exit 0 ;;
    hold:*) _hold "${_TAIL#hold:}" ;;
    keep:crash) _kept_line "$1" "$2" "${3:-0}" "${4:-true}" ;;
    keep:no-guard|keep:no-recycle-lib) _say warn "pane kept, not closed" "${_TAIL#keep:}"; _husk_row "${_TAIL#keep:}" what="$1" ;;
  esac
  _fallback ""
}
_hold() { # $1=fs|unreadable — exit 0 only once removing this pane cannot empty a fullscreen window
  local c="$1" s="${CC_PANE_HOLD_STEP_S:-5}" w ok=0 n=0 rc o cap pk
  trap '' INT QUIT TSTP TERM HUP          # SIG_IGN, inherited by the sleep/guard children
  trap '_hold_escape' EXIT                # any unplanned exit → keep:fallback + a shell, never an empty window
  _hold_paint "$c"; w="$s"
  while :; do
    /bin/sleep "$w"; n=$((n + 1))
    if [ -n "${KITTY_PID:-}" ] && ! kill -0 "$KITTY_PID" 2>/dev/null; then _hold_done; fi   # kitty quit: no window left
    if [ -n "${CC_PANE_HOLD_MAX_POLLS:-}" ] && [ "$n" -gt "$CC_PANE_HOLD_MAX_POLLS" ]; then exit 1; fi  # test seam → escape
    pk=--peek; [ "$ok" -ge 1 ] && pk=""   # only the read that would release RESERVES the window
    rc=0; o="$(cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane $pk --tool cc-pane-hold 2>&1)" || rc=$?
    case "$rc" in
      0|4) ok=$((ok + 1)); [ "$ok" -ge 2 ] && _hold_done; w=$((2 * s)) ;;   # 2 safe reads ≥ 2s apart (Release ≠ !trip)
      *)   ok=0
           case "$o" in *refused-inflight*) ;; *"refused (refused-fs)"*) _hold_class fs ;; *) _hold_class unreadable ;; esac
           cap=$((12 * s)); [ "$c" = unreadable ] && cap=$((60 * s))          # 60 s / 300 s at s=5
           w=$((w * 2)); [ "$w" -gt "$cap" ] && w="$cap"; [ "$w" -gt 0 ] || w="$s" ;;
    esac
  done
}
_hold_class()  { [ "$1" = "$c" ] && return; c="$1"; _pane_exit_tail "hold:$c"; _hold_paint "$c"; }
_hold_paint()  { if [ "$1" = fs ]; then _verdict --state "${_PV_STATE:-DONE}" --guard held || _say wait "done · closes itself when safe" "⌘W closes it now"
                 else _verdict --state "${_PV_STATE:-DONE}" --guard unreadable || _say wait "kitty didn't answer" "closes when it does"; fi; }
_hold_done()   { _HOLD_DONE=1; _pane_exit_tail closed; exit 0; }
_hold_escape() { [ "${_HOLD_DONE:-0}" = 1 ] && return; trap - INT QUIT TSTP TERM HUP EXIT
                 _pane_exit_tail keep:fallback; _husk_row hold-escape; _fallback "the hold ended unexpectedly"; }
```

**W1a tests:**
- Replay arms A1, A1b, A1t, A1x, A1k, A2, A2s, A3, A4, A5, D (§4).
- Inversions. Each encodes the cured state; the old expectation keeps a named control (C1).
  - `tests/pane-close-from-inside.bats:186-192`: refused keeps the shell → holds, then closes on `3,0,0`.
  - `tests/cc-pane-runner-no-command-closes.bats:52,81,89,99,112` and `tests/cc-pane-runner-exit75-closes.bats:63,136`:
    - these become guard *sequence* files ending `0,0`, run with `KITTY_PID=$$`;
    - the "kept" assertions move to the `MAX_POLLS` escape case;
    - `husk reason = guard-*` (`:103`, `:138`) becomes `tail = hold:* → closed`.
  - `tests/cc-pane-runner-exit75-closes.bats:59`: the keys gain `tail`.
- New tests:
  - `tests/cc-pane-verdict.bats` gains a `held` row-2 test.
  - A structural lint in the replay file: one `exec "${SHELL` in the runner (`_fallback`, `:104`), and every
    post-launch `_fallback` is preceded by a `keep:` tail write.

**Size [E]:** +112 / −79.

### W1b: one subject for every re-judge (GOAL; independent, may land first)

| file:line (HEAD) | change | − | + [E] |
|---|---|---|---|
| `hooks/lib/session-writes.sh` after `:583` | `session_work_at_risk <tp> <dir> [strict]` prints `-`, `clean`, `dirty:N`, `unlanded:N` or `unknown`; rc 1 means clean or not a repo, rc 0 means at risk. Steps: not a work tree → `-`. A clean tree → skip the transcript parse (`GIT_OPTIONAL_LOCKS=0`). `session_dirty_mine` rc 0 → `dirty:N`; rc 2 → `unknown`. rc 1 with strict → `dirt_unreachable_by_session` must return 0, else `unknown`. If `origin/HEAD` resolves → `session_unlanded_mine` (rc 0 → `unlanded:N`, rc 2 → `unknown`). | — | +22 |
| `bin/cc-pane-close:508-512` gate 4 | Replace `git status --porcelain \| grep -c .` (`:510`). strict = `team=1` from gate 3 (`:496`), or a fresh exit record (`XR_TS` > `reg_ep`, already read at `:424`) with rc ∉ {0, 75}. Messages: `dirty:N` → "… holds N uncommitted change(s) written by session X"; `unlanded:N` → "… N commit(s) of session X not on origin/HEAD"; `unknown` → "… holds uncommitted change(s) session X may have written (it did not end cleanly / its writes cannot be read)". Source `session-writes.sh` and `peer-owned.sh` beside `:93`. | 3 | +12 |
| `bin/cc-husk-sweep:508-515` `work_of`, call `:558` | Takes `R_TP` and strict = `death` (`:555`) ∉ {clean-exit, -}. The output alphabet is unchanged (`dirty`, `unlanded:N`, `clean`, `-`), so `verdict_of` (`:516`) is untouched. | 6 | +6 |
| `hooks/lead-crash-watchdog.sh:1664-1671` `pane_work_state`, call `:1932` | Takes `tpath`; non-strict, because the crash branch paints RESUME/KILLED whatever the work. Alphabet unchanged. | 6 | +6 |
| `bin/cc-pane-verdict:86-87` | `*"uncommitted change"*) STATE=CANTTELL ;;` (the `UNSAVED` sed deleted) | 2 | +1 |

**W1b tests:**
- Replay arms B1, B1fs, B2, B2c, B3, B4, B5, I2, I3 (§4).
- A cross-closer lint: `git grep -nE 'status --porcelain|origin/main\.\.HEAD' -- bin/cc-pane-close bin/cc-husk-sweep hooks/lead-crash-watchdog.sh`
  must be empty (census §6 item 3).
- Pin edits (the semantics stay; the dirt becomes the session's own):
  - `tests/lead-crash-pane-verdict.bats` setup (`:39`): the fixture transcript records a `Write` of its default
    untracked file, so `:91-92`, `:176` and `:506` stay green unchanged.
  - `tests/cc-husk-sweep.bats:93-100`: the transcript records the `Write` of `dirty`.
  - `tests/cc-pane-verdict.bats:77`: `4 unsaved files` → `state=CANTTELL`, with no "unsaved" and no "--resume".
    `:75` (crash → RESUME) is the positive control.
  - `tests/cc-pane-close-background.bats:155`: `"1 uncommitted change"` → `"uncommitted change"`. The behaviour pin
    (REFUSED, no `session close`) is unchanged, via the strict path (measured rc 2).
  - `tests/cc-pane-close.bats:186-190`: unchanged (strict, `*"uncommitted change(s)"*`).
  - Verify at implementation that `dirt_unreachable_by_session` stays non-zero on that fixture's timestamps.

**Size [E]:** +47 / −17.

### W1c: a guard "yes" reserves the window (GOAL safety; ships with W1a)

| file:line (HEAD) | change | + [E] |
|---|---|---|
| `bin/kitty-fullscreen-guard:761-762` (`decide`, `last_for[scope] is False`) | `claim_gate(info, wid, peek)`: under `fcntl.flock` on `state_dir()/claims/<info.pid>-<info.os_window_id>.json`, read `{wid, panes, ts}`. If another wid holds it, `panes == panes_in_os_window` and age < 30 s, return `3, "refused-inflight"`. Otherwise, unless `--peek`, write `{wid, panes, ts}` and return `0, "safe-not-last"`. An OSError means no reservation (HEAD semantics), and the verdict row records `claim:"error"`. Fields come from the kitten reply (`lib/kitty-fs-kitten.py:94-109`). | +30 |
| `bin/kitty-fullscreen-guard` argparse and docstring EXIT CODES | `--peek`; rc 3 now also covers "another pane of this OS window was just told safe" | +4 |
| `bin/cc-pane-close:184` | `$([ "$DRY" = 1 ] && echo --peek)`: a dry run never reserves | +1 |

**Why default-on.** Every destroyer (the runner, `it2-kitty` `:1671`, `cc-pane-close`, zshexit
`lib/pane-successor.sh:338`, `cc-relayout`, the chords) becomes reserving and reservation-respecting with no
argv change.
- A caller refused this way reaches its existing refusal path:
  - the runner holds;
  - the watcher retries 4×2 s;
  - the drainer retries next tick;
  - zshexit keeps the shell.

**Tests** (`tests/kitty-fullscreen-guard.bats`, stub kitten):
- G1: wid 10 is safe and reserves; wid 11 in the same window is refused-inflight.
- G2: the count dropped, so wid 11 is safe.
- G3: a reservation older than 30 s is ignored.
- G4: wid 10 again is safe.
- G5: `--peek` writes nothing.
- G6: `--peek` respects a reservation.

Mutants:
- no check → G1 red;
- writing on peek → G5 red;
- no count-drop release → G2 red.

**Size [E]:** +35 Python, +60 test.

**W1 total [E]:** about +194 / −96 code. Tests: about +420 (replay about +360, guard about +60) and 13 pin edits (9 in W1a, 4 in W1b).

### W2: every fleet launch returns to the runner (GOAL-completing for resume-launched panes; net deletion)

| step | file:line (HEAD) | change |
|---|---|---|
| W2.0 (precondition) | `scripts/limit-recover/lr-fire-resume.sh:2235` | After `interact`, copy `bin/reso-resume-one:1108-1110` (`catch {wait}`; CHILDKILLED → 1; `exit [lindex $w 3]`). Test: a SIGTERM'd stub gives `lr_rc` ≠ 0. Mutant: no wait. |
| W2.1 | `bin/cc-pane-runner:569` | `export CC_PANE_RUNNER_OWNS_CLOSE="${KITTY_WINDOW_ID:-1}"`. `bin/cc-close-attrib:651` tests only non-empty. |
| W2.2 | `lr-fire-resume.sh:2253-2304` | When `CC_PANE_RUNNER_OWNS_CLOSE` = `$KITTY_WINDOW_ID`: a staged successor runs via `cc_pane_successor_exec "$c" 0` (no trailing shell, `lib/pane-successor.sh:231-240`), else `exit "$lr_rc"`. The ordinary-shell tail stays only for an operator-typed launch (ruling 337e100f5c71). |
| W2.3 | `bin/reso-resume-one:1131-1216` | The same rule. `rr_close_on_clean_exit` (`:1136-1186`, a second guarded closer) is deleted once W2.4 roots its launches. `rr_pane_shell` (`:229-236`) stays for typed launches. |
| W2.4 | `scripts/boot-resume-launch.sh:258`; `bin/cc-resume-layout.sh:1053`, `:1359`; `scripts/limit-recover/lr-lib.sh:1340-1345` | `zsh -ic "$CMD \|\| exec zsh -i"` becomes the runner argv shape (`scripts/handoff-fire.sh:1326-1327`). The doctrine at `boot-resume-launch.sh:240-249` is retired. The lr `argv` fallback refuses instead of launching bare. |
| W2.5 | `scripts/handoff-fire.sh:3776` `hf_resume_cmd_set` (typed); `bin/cc-husk-sweep:619-628` | Typed relaunches start with `exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash "$R"`. |
| W2.6 | `bin/kitty-split-launch.sh:146-149` | The fleet argv goes through the runner. `bin/kitty-split-cwd.sh:38` (the operator's ⌘D) is unchanged. |

**W2 tests:**
- Invert the SURVIVABILITY pins: `tests/kitty-recovery-launch.bats:467`, `:493` and
  `tests/handoff-recycle-pane-survives.bats`.
- A launch-site lint: `git grep -nE '\|\| exec zsh -i|exec "\$\{SHELL'`. Its allowlist is the runner's
  `_fallback`, `lib/pane-successor.sh:341` and `bin/kitty-split-cwd.sh:38`.
- lr and reso exit with the session's rc under ownership, and keep a shell when typed.

Mutants:
- restore the lr tail shell;
- drop the ownership test (an operator-typed launch then closes its pane);
- drop W2.0's wait.

**Size [E: minimal's measured non-comment ranges 29 + 62 + 21, plus wrappers]:** about +45 / −160.

### W3: the standing census and the remaining refusal classes (follow-on; may land before W1)

- New `scripts/pane-census.sh`, called from `scripts/pane-close-retry.sh` before `:63`. It is bounded to 20 s
  and its rc is ignored, so it runs every 300 s even with an empty queue. On each tick:
  - Resolve the socket with `bin/cc-kitty-socket` and make one bounded `kitty @ ls`.
  - For each window with a `pane-exit` record from this kitty generation, classify it:

    | condition | class |
    |---|---|
    | claude in the foreground | running |
    | `cc-pane-runner` in the foreground, tail `hold:*` | held (age from the record) |
    | `cc-pane-runner` in the foreground, no tail | deciding |
    | shells only, tail `keep:<r>` | kept[r] |
    | shells only, any other tail or none | **anomaly** |

  - Windows with no record (operator) are excluded.
  - Append one row to `~/.claude/logs/pane-census.jsonl`.
  - Page once per (kitty pid, pane) when an anomaly is seen 2 ticks running, and when a hold is older than 6 h.
- **Done = `anomaly` max 0 for 7 days** (census §6 item 7). Before W1 every shells-only window with a record
  counts as an anomaly, which gives the baseline.
- rc124 becomes its own class (census §6 item 6): `pane-close-retry.sh:310-313` logs `timeout` to
  `pane-close.jsonl` and does not count it toward the attempts page.
- Operator-owns fix (REPORT 3.5): read `first_ts` before `pcq_remove` (`:279`), and delete the pane's paint
  record on removal.

**Size [E]:** about +80 code and +60 test.

### W4: follow-on candidates (none needed for the GOAL)

| id | change | notes |
|---|---|---|
| W4a | `scripts/lib/pane-placement.sh:115` `_ccp_decide`: rank a window whose only foreground is a runner first | shortens holds; D1 below |
| W4b | One final-turn close reader replaces `bin/cc-pane-close:342` `transcript_facts`, `hooks/lead-crash-watchdog.sh:1677` `pane_last_close` and `bin/cc-husk-sweep:452` `facts_of` | removes the stale-yes residual (5 sessions in 4 days, [C TA red team 1]) |
| W4c | `bin/kitty-confirm-close:250-290`: a runner-only foreground reads "held · closes itself", not "sleep" | |
| W4d | `scripts/boot-resume.sh:783`: retire on SessionEnd `prompt_input_exit` | |
| W4e | `scripts/custody-deathwatch.sh:394`: the triage form | |
| W4f | Investigate a close-if-not-last in `lib/kitty-fs-kitten.py` | if kitty removes the window inside one main-loop step, it replaces both the reservation and the two-read rule |
| W4g | Deletion audit: the watcher's husk-fs arm (`handoff-fire.sh:11899-11903`, `:11918`) and the drainer's operator hold (`pane-close-retry.sh:282-288`, `:315-318`) serve only non-runner panes after W2 | delete when W3 shows 0 non-runner fleet husks for 7 days and D2 is ruled |

---

## 4 `tests/pane-289-replay.bats`: RED on HEAD, GREEN after W1

### Fixture `fixture_289` (shared)

**Hermetic setup.** Every seam the subject *spawns* is pinned (lesson: hermeticity ends at the third tool):

| variable | value |
|---|---|
| `HOME` | `$T/home` |
| `CC_PANE_EXIT_DIR` | `$T/pane-exit` |
| `CC_PANE_CLOSE_QUEUE_DIR` | `$T/q` |
| `CC_SAY_LOG` | `$T/say.jsonl` |
| `CC_PANE_RUNNER_TTY` | `$T/tty` (a file) |
| `CC_PANE_VERDICT_KITTY_BIN` | a logging stub |
| `CC_KITTY_FS_GUARD` | the guard stub |
| `CC_REGISTRY_DIR`, `CC_BEAT_DIR` | under `$T` |
| `CC_PANE_WEDGE_WATCH` | `0` |
| `KITTY_WINDOW_ID` | `289` |
| `KITTY_PID` | `$$` (live; never `610`) |
| `SHELL` | `$T/bin/fakeshell` (touches `$T/shell-ran`, exits 7) |
| `PATH` | `$T/bin:/usr/bin:/bin`, with a `git` wrapper that logs to `$T/git.log` then execs `/usr/bin/git` |

**The checkout, `$T/personal`.**
- `git init -b master`, no remote. A dozen committed files, including the session's own
  `reso-walkthrough/short/C-scenes/NOTES.md` and `scene.py`, both clean.
- **Sibling dirt** that is not the session's: 2 modified tracked files and 3 untracked files under
  `deadlines/items/`, each with `touch -t` 1 h before the session. There is also 1 file with an mtime after the exit.

**Transcript** `$STORE/projects/-x-personal/7555024a-….jsonl`, with timestamps:
- a user record with `cwd`;
- an assistant `Edit` of NOTES.md and a `Write` of scene.py, each with a tool_result;
- assistant text `✅ Good to close: yes`;
- a final assistant `Bash` tool_use (the self-close) with **no** tool_result (bg=1, an open window).

**Logs and records.**
- Watchdog log: `registered session=7555024a… pid=7000 tty=ttys046 pane=289` inside the stub kitty lifetime.
- Crash log: `{"sid":"7555024a…","cause":"clean-exit"}`.
- No custody row by default, so COLLECTED cannot rescue a verdict. One B3 variant adds a `return` row.

**Guard stub.** It reads `$T/guard-seq` (one `rc<TAB>stderr` line per call; the last line repeats) and logs its
argv to `$T/guard-log`. The refusal text is HEAD's real line:
`kitty-fullscreen-guard: refused (refused-fs) kitty window 289 scope=pane mode=refuse: state=FS types=[4] onscreen=False`.

**claude stub.** It touches `$CC_PANE_STARTED_FILE` and exits `$CLAUDE_RC` (default 0). It runs in eval mode:
`CC_PANE_CMD="$T/bin/claude4"`.

### Arms. RED on HEAD; GREEN after the named wave.

| arm | wave | run | asserts after the fix | RED on HEAD because |
|---|---|---|---|---|
| A1 runner holds, then closes | W1a | guard-seq `3fs,3fs,0,0`; `CC_PANE_HOLD_STEP_S=0` | status 0; no `shell-ran`; guard called 4 times; line 1 `--window 289 --mode refuse --scope pane --tool cc-pane-runner` (HEAD's argv); lines 2-3 carry `--peek --tool cc-pane-hold`; line 4 has **no** `--peek`; `tail` = `closed`, and `say.jsonl` logs `hold:fs` first; queue dir empty; the paint holds DONE and `held`; final `run grep -E 'RESUME\|resume\|stopped mid-task' $T/say.jsonl $T/tty; [ "$status" -eq 1 ]`; `$T/git.log` absent | status 7, `shell-ran`, husk row `guard-fullscreen` (`bin/cc-pane-runner:332`, `:579` → `:104`), one guard call |
| A1b first safe read does not release | W1a | seq `3fs,0,3fs,0,0` | 5 guard calls, status 0 | 1 call, status 7 |
| A1t signals | W1a | runner in the background; seq repeats `3fs` until `$T/release` exists; `STEP_S=1`; `kill -TERM`, `-INT`, `-HUP`, `-QUIT`, `-TSTP` the pid | alive after each; `touch $T/release` → exit 0 within 10 s; no `shell-ran`. A `script(1)` variant sends ^C ^\ ^Z through a pty and **skips** when `script` is absent (an env precondition skips, never reds). | the fakeshell exited at once (no process to signal) |
| A1x escape | W1a | seq always `3fs`; `CC_PANE_HOLD_MAX_POLLS=2` | status 7; `shell-ran`; `tail` = `keep:fallback`; one husk row `hold-escape` | no `tail` field |
| A1k kitty gone | W1a | seq always `3unreadable`; `KITTY_PID` = a reaped pid | exit 0 after ≤1 poll; `tail` = `closed`; no `shell-ran` | status 7 |
| A2 watcher stands down | W1a | `handoff-fire.sh __selfclose 289 TTY-A` (harness of `tests/handoff-selfclose.bats`), `CC_PANE_RUNNER_OWNS_CLOSE=1`, record `{rc:0,…,ts:now,tail:"hold:fs"}`, it2 stub close rc 70 | no `session close` in the it2 log; no alarm file; no husk row; output names its cc-pane-runner | `hf_close_pane` → rc 70 → husk-fs alarm and row (`:11916-11918`) |
| A3 watchdog | W1a | `--pane-verdict 7555024a 7000 RECYCLE clean-exit 0 "" $TP`; `CC_PANE_VERDICT_TTY_PROCS` = one line `S+ /bin/bash $REPO/bin/cc-pane-runner` (the instant between children); `SETTLE_S=0` | log "NOT PAINTED"; no verdict call; no husk row | `bash` reads as a shell (`:1640-1647`) → CANTTELL from `dirty:6`, row `reason=ended` (`:2142-2145`) |
| A4 drainer | W1a | a stray husk row for 289; ls stub foreground `[["/bin/bash","/opt/x/bin/cc-pane-runner"]]`; closer stub | row removed "not a bare shell"; closer stub never called | `shell_only` sees `bash` (`:421-426`) → closer called |
| A5 sweep | W1a | `CC_HUSK_PS_FILE` puts `/bin/bash /opt/x/bin/cc-pane-runner` under the window pid (a **claude-free** path) | 289 not listed; `--resume --all --yes` types nothing | listed as a husk → RESUME (sibling dirt) → typed |
| D composed, launchd-like | W1a | after A1: `env -i HOME=$HOME PATH=/usr/bin:/bin /bin/bash scripts/pane-close-retry.sh` with the queue dir, `CC_PCQ_PANE_CLOSE_BIN` and `CC_PCQ_VERDICT_BIN` logging stubs, socket stub empty | both stub logs absent; no RESUME anywhere | A1's HEAD husk row → closer → recompute |
| B1 closer | W1b | `cc-pane-close --pane 289 --dry-run`; listing stub has 289 with a zsh-only tree; guard rc 0 | `WOULD CLOSE … Good to close: yes`; guard argv has `--peek` (W1c) | `REFUSED — … holds 6 uncommitted change(s)` (`:510-511`) |
| B1fs | W1b | the same with the guard refusing (refused-fs) | `REFUSED — the fullscreen guard refused … refused-fs`, with no "uncommitted" | gate 4 answers first |
| B2 painter | W1b | `cc-pane-verdict --pane 289 --recompute --closer-out 'pane 289: REFUSED — /x/personal holds 138 uncommitted change(s)' --dry-run` | `state=CANTTELL`; no "stopped mid-task", "unsaved" or "--resume" | `state=RESUME` (`:86-87`) |
| B2c | W1b | recompute with B1fs's real output | `state=DONE`, fullscreen row | RESUME |
| B3 sweep | W1b | `cc-husk-sweep --json` (pane 289, zsh only); then with a custody `return` | `"work":"clean","verdict":"DONE"`, then `COLLECTED`; `--resume --yes` → "nothing to resume" | `"work":"dirty","verdict":"RESUME"` (`:511`, `:517`) |
| B4 watchdog, bare shell | W1b | as A3 with procs `Ss+ -zsh` | `pvs=DONE` | `dirty:6` → CANTTELL (`:1667`, `:1997`) |
| B5 sibling commit | W1b | variant: a bare `origin` whose HEAD lags by one commit that touches only `deadlines/` | sweep `"work":"clean"`; watchdog DONE | `unlanded:1` → RESUME / CANTTELL (`:513`, `:1669`) |

### Equivalence guards (GREEN on HEAD and after; each named mutant must turn it red)

| arm | run | asserts | mutant it kills |
|---|---|---|---|
| I1 crash with own dirt | NOTES.md modified (recorded Edit); `CLAUDE_RC=143`; seq `3,3,0,0` | runner status 7, `tail` `keep:crash` (after W1), husk row `crash` rc 143, guard **never called**. Closer REFUSED (+`written by session 7555024a` after W1b). Sweep with death `external-sigterm` → RESUME. | M-I1: crash routed to the hold |
| I2 crash, stale yes, Bash-only own write | yes, then a later `Bash` tool_use writing `own/bash-only.txt` (no Edit/Write); exit record rc 143 | closer REFUSED; sweep RESUME | M-strict: strict ignored (gate 4 and sweep) |
| I3 teammate crash (C2 shape) | `teamName`, no recorded writes, untracked file | closer REFUSED, no `session close` | M-team: `team=1` not strict |
| C1 boundary | no "yes"; rc 143; seq `3,3,0,0` | shell kept; guard not asked; never held | M-I1 |
| C2 own dirt on a clean exit (non-runner) | NOTES.md dirty via a recorded Edit; rc 0 | closer REFUSED "holds 1 … written by session" (after W1b); painter CANTTELL; never RESUME paint | M-scope: `session_work_at_risk` ignores own paths |

### Mutants (each run once by hand when its wave lands, on a scratch copy whose unmutated control passes first)

| id | mutation | killed by |
|---|---|---|
| m1 | release on the first safe read | A1b |
| m2 | the hold exits on a refusal (HEAD shape) | A1 |
| m3 | the `trap ''` line deleted | A1t |
| m4 | the confirm read keeps `--peek` (no reservation) | A1 line-4 assertion |
| m5 | no kitty-gone check | A1k (bounded wait) |
| m6 | watcher stand-down removed | A2 |
| m7 | watcher freshness or ownership gate removed | A2s: a record older than `_sc_t0` → today's path (`session close` called) |
| m8 | watchdog runner rule removed | A3 |
| m9 | drainer runner rule removed | A4, D |
| m10 | sweep runner pattern removed | A5 |
| m11 | gate 4 back to porcelain | B1 |
| m12 | painter `uncommitted` → RESUME restored | B2 |
| m13 | `work_of` back to porcelain | B3 |
| m14 | `pane_work_state` back to porcelain | B4 |
| m15 | inline `origin/main..HEAD` restored | B5 |
| M-strict, M-team, M-I1, M-scope | as named in the table above | I1-I3, C1, C2 |

Plus G1-G6 and their mutants in the guard suite (W1c).

**Gates before landing:** `/bin/bash -n` on every changed file; the suite run serially under /bin/bash 3.2;
`test-afunix-path-lint.sh`, `test-hermeticity-lint.sh`, `bats-assert-liveness-fix.py` and bare `shellcheck` on
each changed suite (`.claude/rules/agent-operating-lessons-situational.md:260`). Every negative assertion is a
final `run …; [ "$status" -eq 1 ]`, never a mid-test `!`.

---

## 5 What the GOAL needs, and what is follow-on

| wave | needed for | effect |
|---|---|---|
| **W1a + W1c** | GOAL, pane 289's population | Runner-rooted panes: handoff-fire fires (`scripts/handoff-fire.sh:1326-1327`), it2-kitty splits including teammates, and armed no-command panes. This covers all 22 fullscreen-guard keeps and 6 "kitty didn't answer" keeps since 10-20 [C §4e], and all 10 rc70 self-close husks [C REPORT §3]. Arms A*, D. W1c is a precondition of W1a, not an option: it removes the correlated-release crash path the hold introduces. |
| **W1b** | GOAL, "never painted resume despite sibling dirt" for every pane that reaches a re-judge | Covers lr/reso tails, boot-resume, operator panes and crash keeps. Arms B*. Independent, so it may land first. |
| **W2** | GOAL for resume-launched panes where the operator typed `/exit` | No closer is ever queued for these: lr's tail execs its own shell (`lr-fire-resume.sh:2304`), and the watchdog reads expect's inner pty. The measured population is 6 real lr husks since 10-19, 5 after "Good to close: yes" [C REPORT §3]. Minimal's claim that W1 alone suffices is wrong for these. W2's own tests carry them; the 289 replay does not. |
| **W3** | follow-on | Measures that the class stays at 0 (census items 6-7); recommended to land with or before W1. |
| **W4** | follow-on | Only after W2 and W3 data, and the operator decisions below. |

**Pane 289 under W1** [E: the measured HEAD timeline replayed through the new code]:
- 23:53:36: the runner records `hold:fs` and paints DONE, "closes itself when its window gains a pane".
- 23:53:38: the watcher reads `hold:fs` and stands down. There is no alarm and no row.
- 23:55:00: the watchdog does not paint.
- 00:16:58: pane 293 joins window 25.
- The next poll (≤60 s), plus a 10 s confirm that reserves the window, gives an estimated close between 00:17:10
  and 00:18:10.
- Measured actual at HEAD: closed by hand at 01:46:25 [C REPORT §2.1].

---

## 6 Residual risks and operator decisions

1. **An off-screen fullscreen sole pane holds until a pane joins or the operator presses ⌘W.** It is truthful
   and owned, and W3 pages at 6 h. Today's rc70 husks lived 21 min to 9 h 29 min [C selfclose map §4, via
   minimal]. This is **operator decision D1**: placement `6fd8c7068`/`fd34d855d` against the guard ruling
   `e3920969aba9`, whose exit condition (`fsfix`) was false on 977 of 977 guard rows [C Skeptic pass]. W4a shortens
   the hold.
2. **SIGKILL of a held runner** empties the window, exactly as SIGKILL of today's kept zsh does.
3. **Reservation side-effects.** A caller that is told "safe" and then does not act blocks the window's other
   panes for ≤30 s (refused-inflight leads to their existing retry). Dry runs and the hold's first reads use
   `--peek`. The watcher's 4×2 s retry could exhaust in that window and raise `husk-pane`: rare, and a page,
   not a crash.
4. **Unknown-crash residual.** A non-runner crash with no crash-log row, a stale "yes" and Bash-only own writes
   takes the non-strict path, so its pane may close (the files stay on disk). W2 gives such panes an exit record;
   W4b removes the stale yes.
5. **Escape with buffered input.** Keys typed into a held pane run in the fallback shell if the hold escapes.
   The sweep never types into a runner pane (D10). The escape is an anomaly that W3 counts.
6. **Unguarded vanishing.** A sibling window removed without the guard (SIGKILL, the operator's ⌘W) at the
   moment of a confirm read is not covered by the reservation. The two-read rule narrows it; W4f would remove it.
7. **Deploy skew.** Running runners keep their parsed HEAD functions until relaunched. Legacy husks appear in W3
   as anomalies until the fleet turns over.
8. **Instrument shift.** Held runner panes no longer produce `STILL-PRESENT-rc70` rows in `close-attrib.jsonl`,
   so that series drops for a reason unrelated to success. W3 is the metric of record (census §4b warned that this
   denominator had moved before).
9. **Operator decision D2.** Ruling 337e100f5c71 keeps hand-opened windows open on `/exit`, against the contract
   restated 10-01, 10-18, 10-22 and 10-25 (census §2). Operator panes stay outside the invariant until this is
   ruled.

---

## 7 Evidence ledger

**Measured by this judge:**

| [M] | command | result |
|---|---|---|
| HEAD | `git log -1` | `fa9cadc24` |
| runner close code | `sed -n 257,349p bin/cc-pane-runner \| grep -cv '^\s*#'` | 74 |
| hold probe | `python3 -I /tmp/husk-fix-design/probe/drive.py`, under `GNU bash 3.2.57(1)-release (arm64)` | signals: all 5 alive, still polling, release rc 0 after 1.3 s, no fallback. single_ok_then_refuse: alive. escape: fallback ran with `INT=False TERM=False HUP=False` |
| C2 fixture | `bash /tmp/husk-fix-design/c2probe/run.sh` | `session_dirty_mine rc=1`; `dirt_unreachable_by_session rc=2` |
| whole-cwd porcelain | `git grep -n 'status --porcelain' -- bin/cc-pane-close bin/cc-husk-sweep hooks/lead-crash-watchdog.sh bin/cc-pane-verdict scripts/pane-close-retry.sh` | 3 (`cc-husk-sweep:511`, `cc-pane-close:510`, `lead-crash-watchdog.sh:1667`) |
| whole-checkout unlanded | `git grep -n 'origin/main..HEAD' -- bin/cc-husk-sweep hooks/lead-crash-watchdog.sh bin/cc-pane-close` | 2 (`:513`, `:1669`) |
| exact guard-argv pins | `git grep -n -- '--tool cc-pane-runner'` in tests, plus `-E '--tool (it2-kitty\|zshexit\|cc-pane-close)'` | 9 (4 + 1 + 1 + 3); 0 change under W1c |
| record-keys pin | `git grep -n "keys" tests` | `tests/cc-pane-runner-exit75-closes.bats:59` |
| refusing-guard runner pins | `git grep -c 'GUARD_RC=3'` | no-command 5, exit75 2, from-inside 1 |
| runner argv | `ls -la ~/.claude/bin/cc-pane-runner` | → `/Users/chrisren/Development/claude-infrastructure/bin/cc-pane-runner` (contains "claude") |
| pane-exit readers | `git grep -n -E 'run/pane-exit\|EXITDIR=\|CC_PANE_EXIT_DIR'` | 4 readers (`cc-pane-close:86`, `cc-pane-verdict:79`, `handoff-fire.sh:6697`, `:6727`), all tolerant of an extra field |
| dirt libraries | `grep -n session-writes\|peer-owned` in the 3 re-judges | 0 (W1b adds the sourcing) |

**Cited (measured by their authors):**
- REPORT §3: 390 runner guard verdicts, 36 refused (13 fs, 22 kitten-failed, 1 unknown); rc70 husks 10/10;
  lr 7 paints / 6 husks / 5 after yes; rc124 25 on 6 panes; gate-4 rows 9.
- Census §4e: 28 runner keeps (22 fullscreen, 6 kitty-unanswered).
- Census Skeptic pass: `fsfix:false` on 977/977.
- Via minimal: selfclose map §2.12 (runner precedes the watcher by 0-6 s) and §4 (husk lifetimes).

**Estimated:**
- All LOC: line counts of the sketches and tables above.
- The pane-289 close time (§5 method).
- `lr_rc` = 0 on every end (from `bin/reso-resume-one:1103-1104`, not measured on lr).
- `CC_PANE_RUNNER_OWNS_CLOSE` reaching the detached watcher (env inheritance; verify at implementation).
