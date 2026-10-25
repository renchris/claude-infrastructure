# Husk-pane fix: a minimum-moving-parts design (2026-10-24)

Lens: start from deletion. Every number is labelled **measured** (with the command) or **estimated**
(with the method). Code citations are `file:line` at HEAD `fa9cadc24` of
`/Users/chrisren/Development/.worktrees/husk-skill-and-fix`. I re-read every cited line with `sed -n` or
`grep -n` at that HEAD. The repo was only read. The only files written are under `/tmp/husk-fix-design/`:
this document and `probe/`, a throwaway bash/python probe that touches no kitty and no pane.

Inputs: Track A's `REPORT.md` and maps (`lifecycle`, `selfclose`, `closer`, `painter`, `sweep`, `recycle`,
`history`), the census (`CENSUS.md` §1, §3, §6 and the Skeptic pass), and `PANE-289-TIMELINE.md`.

---

## 0. The answer in brief

- **Owner.** `bin/cc-pane-runner` is already the window's root process. It is the only actor that can end a
  pane with no socket and no gates. On a guard refusal it calls `_fallback` → `exec $SHELL` (`:579` → `:104`),
  which throws that ability away. Every other actor in the pane-289 relay then runs only because a bare
  shell now exists.
- **Fix.** The runner decides once, writes the decision into the record it already writes, and acts on it.
  On a guard refusal it **stays alive in its own process and holds**: it re-asks the guard and exits once
  closing is safe. Nothing else needs to act on that pane. The two producers of outside action, the
  self-close watcher and the crash watchdog, read the decision and stand down.
- **New mechanism, all of it:**
  - one field (`tail`) in the existing record `~/.claude/run/pane-exit/<wid>.json`;
  - one decision function (`_pane_end_decide`), which replaces `_close_on_exit` and `_close_pane`;
  - one owner (the runner process). There is no new process, exec body, launchd job, lock, env switch or
    record-trust rule.
- **Second half of the GOAL.** "Never painted resume" must also hold for panes the runner does not own.
  For that, the three whole-checkout dirt counts (`cc-pane-close` gate 4, the watchdog's `pane_work_state`,
  the sweep's `work_of`) become one call to the existing `session_dirty_mine`.
- **Which wave.** **Wave 1 (W1a + W1b) alone makes the GOAL true.** W1a alone already makes it true for
  pane 289 and every runner-rooted pane. Code size of W1 (estimated from the sketches below): about +134/−88
  lines.

---

## 1. The invariant (true by construction for every runner-rooted pane)

After its command returns, a kitty window whose root is `cc-pane-runner` is in exactly one of these four
states:

| state | what is on screen | what the record says | who ends it |
|---|---|---|---|
| **running** | the command (claude) | `rc`/`ts` not yet written for this launch | the command |
| **closed** | nothing: the window is gone | `tail:"close"` or `"closed"` | the runner's own `exit 0` |
| **held** | one DONE/NOTHING paint; the runner process is alive with no child | `tail:"hold:fs"` or `"hold:unreadable"` | the runner, after two safe guard reads ≥10 s apart |
| **kept** | an interactive shell exec'd by the runner | `tail:"keep:<reason>"`, where `<reason>` is crash, launch-failed, recycle, kill-switch, not-a-session, no-guard, no-recycle-lib or fallback | the operator, the crash/resume path, or a recycle |

The construction:
- The runner leaves its post-command code in exactly three ways:
  - `exit 0` after a `close` verdict;
  - `exit 0` from the hold after a confirmed safe read;
  - `_fallback`, which is reached only after `keep:<reason>` has been written.
- The hold's `EXIT` trap turns any unplanned exit into `keep:fallback` plus a shell, never an empty window.

The three pre-command fallbacks (`bin/cc-pane-runner:593`, `:594`, `:641`: no state dir, not kitty, empty
command) run before any launch. They stay as today: config faults with their own line.

Hard invariants, and how each holds:
- **Never empty a fullscreen last pane.** The only exits are a guard `rc 0`, or two reads ≥10 s apart that
  say safe or not-found. `INT`, `QUIT`, `TSTP`, `TERM` and `HUP` are ignored while holding.
- **Never close a pane with a live job.** The runner closes only after its command returned. This is the same
  rule as today's rc-0 close.
- **Never resume a finished session.** No RESUME paint or `--resume` is ever produced for a held or closed
  pane. W1b removes the foreign-dirt RESUME at the three remaining sites.
- **A crash with its own uncommitted work is kept/resumed.** `keep:crash` is unchanged. Gate 4 still refuses
  on the session's own edit-recorded dirt, and recompute still paints RESUME with the session's own count.

---

## 2. Start from deletion

### 2.1 What the GOAL path stops running

These stop running for a runner pane whose session ended cleanly (pane 289's path):

| actor (today, pane 289) | HEAD lines | after W1a |
|---|---|---|
| runner husk rows on guard refusal | `bin/cc-pane-runner:332`, `:337` | **deleted** (a hold is not a husk) |
| runner `_fallback` exec of a shell after a close decision | `:579` → `:104` | not reached (`close` exits, `hold` holds) |
| self-close watcher: 4-try close, husk-fs alarm, `hf_husk_row` | `scripts/handoff-fire.sh:11832-11859`, `:11861-11920` | skipped when the runner's fresh record says `close`/`hold:*` |
| watchdog paint (CANTTELL from whole-cwd dirt), its husk row, grace close | `hooks/lead-crash-watchdog.sh:2036-2123`, `:2132`, `:2187` | returns at `:2046` when the record says `hold:*` |
| drainer → `cc-pane-close` → `cc-pane-verdict --recompute` | `scripts/pane-close-retry.sh:261-328` | never fed. A stray row for a held pane is dropped. |
| "fixed fact" doctrine (refused-fs is permanent) | `scripts/handoff-fire.sh:1872-1878`, `:11816-11822`; runner `:300-304` | comments rewritten: refused-fs is a condition the hold waits out |

All 28 runner-kept panes since 10-20 were guard refusals: 22 fullscreen and 6 "kitty didn't answer"
(**measured** by the census §4e, `pane-say.jsonl`). Under W1a every one of them becomes a hold.

### 2.2 Track A mechanisms that a deletion makes unnecessary

| Track A item | why it is not needed | replacement | saved (estimated) |
|---|---|---|---|
| 1.2 `exec -a cc-pane-held /bin/bash /dev/fd/3` with a `declare -f` body and env marshalling | The runner is already the window's process, so the hold can run in it. **Measured** with `python3 -I /tmp/husk-fix-design/probe/drive.py` under /bin/bash 3.2.57: an in-process loop with `trap '' INT QUIT TSTP TERM HUP` stayed alive through all five signals sent to its process group; `TSTP` did not freeze the `sleep` child; it exited 0 only after two safe reads; one safe read followed by a refusal did **not** release; an unplanned exit ran the EXIT trap, which exec'd the fallback with default signal dispositions (INT, TERM, HUP all not-ignored). | the `_hold` function inside the runner | about 30 lines, plus the whole R2 class (re-exec from disk or fd at the worst moment) |
| rename to `cc-pane-held` so that readers stand down by name | Renaming for the pane's whole life touches 130 `comm=` readers in about 40 files (**measured**: `grep -rn 'comm=' bin scripts hooks lib \| wc -l`; `lib/pane-successor.sh:327` keys on a `*sh` parent, for example). Renaming only at hold time needs the exec above. Readers do not need to stand down if the producers stop. | 2 producer checks (watcher, watchdog) and 1 defensive drainer check, all reading `tail` | about 25 lines |
| 1.3 record trust fields `pid`, `lstart`, `kitty_pid`, `root_pid` and a trust rule | Each reader already has its own reference epoch: the watcher's `/exit` time, the watchdog's `LEAD_START_EPOCH` (`hooks/lead-crash-watchdog.sh:2336-2339`), the drainer's `_kitty_start_epoch` (`scripts/pane-close-retry.sh:225-231`). "ts ≥ my reference" is the trust rule. A `hold` tail implies a live runner, because any other way out rewrites `tail` first. | `tail` only | about 30 lines |
| 1.5 a HELD verdict in `cc-husk-sweep` | `has_claude_under` (`bin/cc-husk-sweep:214`) already skips a runner whose path contains "claude". | one explicit pattern, `*cc-pane-runner*`, so it does not depend on the install path | about 10 lines |
| `CC_PANE_HOLD=0` as "the rollback" | An env var does not reach kitty-spawned panes: "the chords and every kitty-spawned pane inherit KITTY's environment, which no shell export reaches" (`bin/kitty-fullscreen-guard:75-77`). `CC_PANE_CLOSE_ON_EXIT=0` has the same limit today. | rollback = revert the W1a commit; tests use a step seam | a knob that would not work |
| 1.8 teammate exit 143/137 → close | It widens the close predicate and is not needed for the GOAL. | dropped (optional later) | — |
| 2.1 `CC_PANE_RUNNER_PID` plus a 6-hop ancestor walk | The runner already exports `CC_PANE_RUNNER_OWNS_CLOSE` to its command (`bin/cc-pane-runner:569`). | that export carries the window id instead of `1`; a launcher compares it to `KITTY_WINDOW_ID` (W2) | about 15 lines |
| 2.6 per-window mkdir close lock | There is one owner per pane already. The cross-pane race (two panes of one fullscreen window closing at once) exists today between **all** closers. A file lock shared by three closers needs reaping and does not remove the race when one side closes by child exit. | none in W1. The race is removed (optional W4b) by one atomic close-if-not-last in kitty's main loop, which also replaces the two-read rule. | a third shared state |
| 3.2 `session_work_at_risk` with end_epoch, bg and live-peer chaining | A clean-exit runner pane never reaches gate 4 after W1a, so 7555024a's bg=1/open-window "unknown" never matters. | the existing `session_dirty_mine` at three sites (W1b) | about 60 lines |
| 3.3 stamp `allowDirty`/`workAtClose`; `hf_husk_row` passes the sid | No reader needs a waiver once dirt is scoped to the session (W1b) and the runner never consults dirt (W1a). | dropped | about 20 lines |
| 3.6 census as its own launchd job | The drainer's launchd job already runs every 300 s (`StartInterval 300`, closer map §3). It exits only because of its own early return (`scripts/pane-close-retry.sh:63-64`). | census step moved above that return (W3) | a plist, a job and its tests |

Totals (estimated from Track A's own sizing and the sketches below):
- Track A Phases 1–3: about +380/−270 code lines.
- This design, W1–W3: about +200/−200.
- The new code is about 1 record field + 1 decision function + 1 work-at-risk wrapper.

---

## 3. The new mechanism, all of it

1. **Record.** `~/.claude/run/pane-exit/<wid>.json` gains a `"tail"` field. It is written by
   `_pane_exit_tail` right after the decision and before the act. The hold rewrites it to `"closed"` on
   release, and the escape rewrites it to `"keep:fallback"`. Existing readers ignore extra fields:
   - `bin/cc-pane-close:287` uses a jq `select` on typed fields;
   - `scripts/handoff-fire.sh:6693-6711` asserts types only;
   - `bin/cc-pane-verdict:80` reads only `.claude_started`/`.rc`.
2. **Decision.** `_pane_end_decide` prints `close | hold:fs | hold:unreadable | keep:<reason>`. Its inputs
   are the ones the runner already has: rc, claude_started, owed, kill switch, recycle-pending, guard. It
   reads **no** git dirt, transcript or custody, so the runner's rule is the 10-01 rule (`74baff1ee`: "a
   clean exit closes the pane") and nothing else.
3. **Owner.** The runner process, through `_end` (the one tail) and `_hold`.
4. **Work at risk** (W1b, for the panes the runner does not own). `session_work_at_risk <transcript> <dir>`
   (12 lines) wraps `session_dirty_mine` (`hooks/lib/session-writes.sh:502-583`). It replaces three inline
   whole-checkout counts.

---

## 4. Waves

### W0: the replay test, written first (RED on HEAD)

`tests/pane-289-replay.bats`. It reuses the harness shape of `tests/pane-close-from-inside.bats:13-66`:
a guard stub driven by `GUARD_RC`, a fake `SHELL` that records being exec'd (exit 7), and a claude stub.

**Shared fixture `fixture_289`:**
- `$T/personal`: `git init -b master`, no remote. 140 files are committed. Then 138 porcelain lines
  (modified plus untracked) are made by "siblings", with `touch -t` an hour before the session.
- The session's two own files (`reso-walkthrough/short/C-scenes/NOTES.md`, `…/scene.py`) are committed and
  clean.
- Transcript `7555024a-….jsonl`:
  - an `Edit` and a `Write` tool_use (with tool_results) for the two own paths;
  - last assistant text `✅ Good to close: yes`;
  - a trailing self-close `Bash` tool_use with **no** tool_result (the open window measured in the closer
    map §4).
- Supporting files: a watchdog registration line for pane 289 (`tty=ttys046`), an optional custody
  `return`, and these seams: `CC_PANE_EXIT_DIR`, `CC_PANE_CLOSE_QUEUE_DIR`, `CC_SAY_LOG`,
  `CC_PANE_VERDICT_DIR`.
- A `git` wrapper on `PATH` that logs every call.

Arms (each lists the wave that turns it GREEN):

| arm | what it runs | asserts after the fix | RED on HEAD because |
|---|---|---|---|
| **A1 runner** (W1a) | `CC_PANE_CMD="cd $R && claude4"` in interactive mode; claude stub exits 0 and touches `$CC_PANE_STARTED_FILE`; guard sequence `3 3 0 0`; `CC_PANE_HOLD_STEP_S=0` | status 0; fake shell **not** exec'd; guard called exactly 4 times; record has `rc:0`, `tail` first `hold:fs` and finally `closed`; no file in the pcq dir; `pane-say.jsonl` holds a DONE paint and no `RESUME`, `resume`, `stopped mid-task` or `--resume`; git log empty | HEAD execs the shell after one refusal (status 7), writes a `guard-fullscreen` husk row (`:332`), and calls the guard once |
| **A2 watcher** (W1a) | handoff-fire `__selfclose` close phase (harness of `tests/handoff-selfclose.bats`) with a record `{rc:0, claude_started:true, ts:now, tail:"hold:fs"}`; it2 stub returns 70 on close | no `session close` in the it2 log; no alarm record; no husk row; output names "belongs to its cc-pane-runner" | HEAD calls `hf_close_pane`, gets rc70, raises husk-fs and writes a row (`:11918`) |
| **A2s** (W1a) | same, but record `ts` is older than the watcher start | today's path runs (`session close` is called) | GREEN on HEAD. This is the guard against an over-broad stand-down. |
| **A3 watchdog** (W1a) | `lead-crash-watchdog.sh --pane-verdict 7555024a 7000 RECYCLE clean-exit 0 "" $TP`, with `CC_PANE_VERDICT_TTY_PROCS="S+ /bin/bash $REPO/bin/cc-pane-runner"`, `CC_PANE_VERDICT_SETTLE_S=0`, `CC_LEAD_START_EPOCH` ≤ record ts, record `hold:fs` | log line "NOT PAINTED — its cc-pane-runner holds pane 289"; no `cc-pane-verdict` row; no husk row | HEAD treats `bash` as a shell (`:1640-1647`), paints CANTTELL from `dirty:138` (`:1997`) and writes a row with `reason=ended` |
| **A4 drainer** (W1a) | husk row for 289 and record `hold:fs`; stub `kitty @ ls` lists 289 with foreground `[/bin/bash …/cc-pane-runner]` | row removed with "held by its runner"; closer stub never called | HEAD's `shell_only` (`:421-426`) reads `bash` as a shell and calls the closer |
| **B1 closer** (W1b) | `cc-pane-close --pane 289 --dry-run`, guard stub safe | `WOULD CLOSE`; no "uncommitted" | HEAD refuses with "…personal holds 138 uncommitted change(s)" (`:510-511`) |
| **B2 painter** (W1b) | B1 with the guard stub refusing (refused-fs), then `cc-pane-verdict --recompute --closer-out "$out"` | state DONE, row 2 is the fullscreen ⌘W text; never RESUME | HEAD: gate 4 masks the guard and `:86-87` paints RESUME "138 unsaved files" |
| **B3 sweep** (W1b) | `cc-husk-sweep --json` with `CC_HUSK_PANES_JSON` (pane 289, no claude); run with and without the custody return | DONE (no custody) / COLLECTED (custody); never RESUME | HEAD: `work_of` gives dirty → RESUME (`:512`, `:517`) when there is no custody |
| **B4 watchdog, bare shell** (W1b) | as A3 but with no record and foreground `-zsh` | state DONE (not CANTTELL) | HEAD: CANTTELL from `dirty:138` |
| **I1 invariant** (W1b) | own `NOTES.md` dirty; claude exits 143 | runner: `tail:"keep:crash"` and a crash row; closer refuses "holds **1** uncommitted change(s) written by session 7555024a"; recompute gives RESUME "1 unsaved files" | HEAD reports 139, not 1 |
| **C1 boundary** (none) | no "yes"; rc 143; guard sequence `3 3 0 0` | kept as a shell; never held; guard not asked | GREEN on HEAD (pins that a crash is never held or closed) |

Mutants that must fail (each is run once by hand when the wave lands; the A1 mutants via
`CC_PANE_HOLD_STEP_S=0`):
- **m1**: the hold releases on the first safe read. Guard sequence `3 0 3 3 0 0` must call the guard 6
  times; the mutant stops at 2.
- **m2**: the hold exits on refusal. A1's status and call count fail.
- **m3**: the signal-ignore line is deleted. A1t runs the runner in the background, sends `kill -TERM` and
  `kill -INT` mid-hold, asserts it is still running, then flips the guard file to 0 and asserts exit 0.
- **m4**: the watcher freshness check is dropped. A2s fails.
- **m5**: gate 4 is reverted to `git status --porcelain | grep -c .`. B1 fails.
- **m6**: `pane_work_state` is reverted. B4 fails.
- **m7**: `work_of` is reverted. B3 fails.

### W1: the GOAL wave (W1a and W1b; each can be reverted on its own)

#### W1a: the runner owns the end

| file:line (HEAD) | change | deleted | added (estimated) |
|---|---|---|---|
| `bin/cc-pane-runner:257-278` `_close_on_exit`, `:283-349` `_close_pane` | replaced by `_pane_end_decide`, `_guard_ask`, `_end`, `_hold`, `_hold_escape`, `_pane_exit_tail` (sketch below) | **93 lines, 74 code** (measured: `sed -n 257,349p bin/cc-pane-runner \| grep -cv '^\s*#'`), including both husk rows `:332`, `:337` | about 63 |
| `bin/cc-pane-runner:426-443` `_pane_exit_record` | keep the emitted row in `_XR_ROW` for `_pane_exit_tail` | — | +1 |
| `bin/cc-pane-runner:576-579`, `:614-623` | `_close_on_exit …; _fallback ""` → `_end …` (`_no_command` keeps `_PV_STATE=NOTHING`) | 4 | +2 |
| `bin/cc-pane-runner:46-63`, `:82-84`, `:300-304` | doctrine comments rewritten: "a clean exit closes or holds; a shell is kept only for a recorded reason" | comments | comments |
| `scripts/handoff-fire.sh:6693-6711` `hf_pane_exit_record` | optional 2nd arg `tail` prints `d.get("tail","")` for a fresh record (same freshness rule, `ts ≥ HF_SPAWN_T0`) | — | +3 |
| `scripts/handoff-fire.sh:11648` (watcher entry) | `_sc_t0=$(date +%s)` | — | +1 |
| `scripts/handoff-fire.sh:11831-11832` | poll the record up to 20 s (2 s steps). On `close`/`closed`/`hold:*`: one line "belongs to its cc-pane-runner", `_close_ok=1`, skip the loop and the failure arm (`:11861-11920`), still run the successor focus (`:11922`). A `keep:*` tail or no record → today's path. | — | +13 |
| `scripts/handoff-fire.sh:1872-1878`, `:11816-11822`; `bin/it2-kitty:88`, `:1665` | "fixed fact" wording → "a condition: it clears when the window gains a pane or leaves fullscreen" | comments | comments |
| `hooks/lead-crash-watchdog.sh:2046` (after the settle `case`) | if `LEAD_START_EPOCH` is set and `pane-exit/$LEAD_PANE.json` has `ts ≥ LEAD_START_EPOCH` and `tail` = `hold:*` → log "NOT PAINTED — its cc-pane-runner holds pane N", return (no paint, no row, no grace close) | — | +6 |
| `scripts/pane-close-retry.sh:267` (in `drain_husk`, after the generation check) | if the record's `ts ≥ _kitty_start_epoch` and `tail` = `close`/`closed`/`hold:*` → `pcq_remove`, log "held by its runner", return. Defensive: covers a stray producer such as the headless self-close row (`scripts/handoff-fire.sh:15809`) or a deploy skew. | — | +5 |
| `bin/cc-pane-verdict:97-102` | `fs)` row 2 = "closes itself when this window gets another pane · ⌘W closes it now". `unreadable` already reads "kitty didn't answer · closes when it does". | — | +1 |
| `bin/kitty-confirm-close:250-258` `is_busy` | not busy when the foreground list contains `cc-pane-runner` and every other entry is a shell or `login`. Today `jobs_in` skips `cc-*` (`:286`), so a held pane would show "running an unknown program". | — | +5 |
| `bin/cc-husk-sweep:214` | `*claude*)` → `*claude*\|*cc-pane-runner*)`: a held runner is never listed or typed into | — | ±1 |

Runner sketch (bash 3.2; `set +u` is already in force after `:567`):

```bash
_pane_end_decide() { # $1=cmd $2=rc $3=interactive $4=claude_started $5=owed → the tail
  _claude_verb "$1" >/dev/null || [ "${3:-0}" = 1 ] || { echo keep:not-a-session; return; }
  [ "${CC_PANE_CLOSE_ON_EXIT:-1}" = 0 ] && { echo keep:kill-switch; return; }
  case "$2" in 0|75) ;; *)
    if [ "${4:-true}" = false ] && [ "${5:-0}" = 1 ]; then :
    elif [ "${4:-true}" = true ]; then echo keep:crash; return
    else echo keep:launch-failed; return; fi ;; esac
  _recycle_lib || { echo keep:no-recycle-lib; return; }          # body of :285-294
  cc_pane_recycle_pending "${KITTY_WINDOW_ID:-}" && { echo keep:recycle; return; }
  _guard_ask                                                       # body of :305-344
}
_guard_ask() {   # → close | hold:fs | hold:unreadable | keep:no-guard ; sets _GUARD
  [ -n "${KITTY_WINDOW_ID:-}" ] && [ "${CC_KITTY_FS_GUARD:-}" != off ] || { echo close; return; }
  _guard_bin || { echo keep:no-guard; return; }
  local o; o="$(cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-runner 2>&1)" \
    && { echo close; return; }
  case "$o" in *"refused (refused-fs)"*) echo hold:fs ;; *) echo hold:unreadable ;; esac   # rc 4 at decision → hold (conservative)
}
_end() { # never returns
  local t; t="$(_pane_end_decide "$@")"; _pane_exit_tail "$t"
  case "$t" in
    close)  rm -f "${_armed:-/dev/null/x}" 2>/dev/null; exit 0 ;;
    hold:*) _verdict --state "${_PV_STATE:-DONE}" --guard "${t#hold:}" || _say wait "done · closes itself when safe" "⌘W closes it now"
            _hold ;;
    keep:crash|keep:launch-failed) _kept_line "$1" "$2" "${3:-0}" "${4:-true}" ;;
    keep:no-guard|keep:no-recycle-lib) _say warn "pane kept, not closed" "${t#keep:}"; _husk_row "${t#keep:}" what="$1" ;;
  esac
  _fallback ""
}
_hold() { # exit 0 only when removing this pane cannot empty a fullscreen window
  local s="${CC_PANE_HOLD_STEP_S:-5}" w ok=0 rc; w="$s"
  trap '' INT QUIT TSTP TERM HUP          # ^C, ^Z, pkill, a stray HUP: the window must outlive them
  trap '_hold_escape' EXIT                # any unplanned way out keeps a shell, never an empty window
  while :; do
    /bin/sleep "$w"; rc=0
    cc_run "$_GUARD" --window "$KITTY_WINDOW_ID" --mode refuse --scope pane --tool cc-pane-hold >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0|4) ok=$((ok + 1)); [ "$ok" -ge 2 ] && { _HOLD_DONE=1; _pane_exit_tail closed; exit 0; }; w=$((2 * s)) ;;
      *)   ok=0; w=$(( w * 2 > 12 * s ? 12 * s : (w > 0 ? w * 2 : 0) )) ;;
    esac
  done
}
_hold_escape() { [ "${_HOLD_DONE:-0}" = 1 ] && return; trap - INT QUIT TSTP TERM HUP EXIT; _pane_exit_tail keep:fallback; _fallback "the hold ended unexpectedly"; }
```

Notes on the sketch:
- `HUP` is ignored, not "exit 0": a stray HUP on a fullscreen last pane must not end the hold. When kitty
  itself closes the window (⌘W through `kitty-confirm-close`, which leaves fullscreen first), the orphaned
  runner sees the guard's rc 4 (not-found) twice and exits.
- Backoff is 5 → 60 s with confirmation reads 10 s apart, all scaled by one test seam.
- The hold writes nothing to the tty after its one paint and reads nothing from it.

Tests for W1a:
- Arms A1, A1t, A2, A2s, A3, A4.
- Inverted pins:
  - `tests/pane-close-from-inside.bats:186-192` ("the guard refusing … keeps the shell") becomes "holds,
    then closes on two safe reads";
  - the refused-fs arms of `tests/cc-pane-runner-no-command-closes.bats` and
    `tests/cc-pane-runner-exit75-closes.bats` become holds, using a guard sequence file.
- New: `tests/cc-pane-verdict.bats` gains an `fs` row-2 test; `kitty-confirm-close` gains an `is_busy` test
  (runner-only foreground → not busy; runner plus claude → busy).
- Structural lint (in the replay file): `bin/cc-pane-runner` has exactly one `exec "${SHELL` line (`_fallback`),
  and every call to `_fallback` after a launch is preceded by `_pane_exit_tail keep:`.
- Mutants m1–m4.

Size of W1a (estimated from the sketch line counts; deletion measured): about **+100 / −77** code lines.

#### W1b: one work-at-risk predicate for the panes the runner does not own

| file:line (HEAD) | change | deleted | added (estimated) |
|---|---|---|---|
| `hooks/lib/session-writes.sh` after `:583` | `session_work_at_risk <transcript> <dir>` → `clean` (rc 1) / `mine:<n>` (rc 0) / `unknown` (rc 2). A clean tree returns before parsing the transcript. Otherwise it calls `session_dirty_mine` (already bounded 5 s per git call, `-uall`, `-z`). | — | +12 |
| `bin/cc-pane-close:508-512` gate 4 | `mine:N` → refuse "`$cwd` holds N uncommitted change(s) written by session X"; this keeps the `holds N uncommitted` text that `bin/cc-pane-verdict:86-87` parses, so RESUME stays truthful (own count). `unknown` → refuse "cannot tell which dirty paths … are session X's" (no "uncommitted change" substring, so recompute gives CANTTELL). `clean` → pass. Source the lib beside `:93-97`. | 4 | +10 |
| `hooks/lead-crash-watchdog.sh:1664-1671` `pane_work_state`; call `:1932` | takes `tpath`; dirt = `session_work_at_risk` (`mine:N` → `dirty:N`, `unknown` → `dirty:?`); the unlanded arm is unchanged | 3 | +6 |
| `bin/cc-husk-sweep:508-515` `work_of`; call `:558` | takes `R_TP`; `mine:*`/`unknown` → `dirty`, else today's unlanded check | 3 | +6 |
| `tests/cc-pane-close-background.bats:149-157` (C2 pin of `957279537`) | the fixture adds the teammate's own `Write` of `half-done.txt`, so gate 4 still protects a crashed teammate, now on its own paths, as census §6 item 3 asks. Add C2b: an untracked file the teammate never wrote does not block. | — | +2 (test) |

Tests for W1b: arms B1–B4 and I1; mutants m5–m7. Plus one cross-closer lint: `git grep -nE
'status --porcelain[^|]*\| *(wc -l|grep -c)'` over `bin/cc-pane-close`, `bin/cc-husk-sweep` and
`hooks/lead-crash-watchdog.sh` must be empty (census §6 item 3).

Size of W1b (estimated): about **+34 / −11** code lines.

**W1 total (estimated): about +134 / −88 code lines; tests about +260 lines.**

### W2: every fleet launch rooted in the runner; launchers hand back their rc (the deletion wave)

This extends the one owner to the pane families W1a cannot reach, where a launcher execs its own shell.
That covers lr-fire-resume's "ordinary shell" husks: 7 paints since 10-19, 6 of them real husks, 5 of
those 6 after "Good to close: yes" (**measured**, recycle map §2a).

| file:line (HEAD) | change | deleted (measured, `sed -n A,Bp \| wc -l` / non-comment) | added (estimated) |
|---|---|---|---|
| `bin/cc-pane-runner:569` | `export CC_PANE_RUNNER_OWNS_CLOSE="${KITTY_WINDOW_ID:-1}"`. `bin/cc-close-attrib:651` only tests non-empty. | — | ±1 |
| `bin/cc-pane-runner` `_pane_end_decide` | before `keep:recycle`: `cc_pane_successor_take` → run the successor loop as a **child** (`"$SHELL" -l -i -c "$_CC_PANE_SUCCESSOR_LOOP" cc-successor …`, no `exec`), then decide again on its rc. A staged recycle then needs no idle shell; `keep:recycle` stays only for an unstaged, typed recycle. | — | +12 |
| `scripts/limit-recover/lr-fire-resume.sh:2253-2304` tail | → `exit "$lr_rc"`. Its parent is always the runner or an operator's prompt once the bare-argv launch below is gone. | **52 / 29** | +1 |
| `bin/reso-resume-one:1131-1216` (`rr_close_on_clean_exit`, `rr_successor_take_exec`, shell tail) | → `exit "$rr_rc"` | **86 / 62** | +1 |
| `bin/reso-resume-one:229-256` (`rr_pane_shell`, `rr_refused_exit`'s shell arm) | → `exit "$1"` | **28 / 21** | +1 |
| `scripts/limit-recover/lr-lib.sh:1340-1342` (`LR_SPAWN_SHAPE=argv` fallback) | refuse when there is no runner, instead of launching bare | 2 | +2 |
| `scripts/boot-resume-launch.sh:258`; `bin/cc-resume-layout.sh:1053`, `:1359` | `zsh -ic "$CMD \|\| exec zsh -i"` → the runner argv shape of `scripts/handoff-fire.sh:1326-1327`; retire the doctrine at `scripts/boot-resume-launch.sh:240-242` | 3 | +6 |
| `bin/kitty-split-launch.sh:146-149` | fleet argv → `CC_PANE_CMD` plus the runner | — | +3 |
| typed relaunches into a kept shell: `scripts/handoff-fire.sh` `hf_resume_cmd_set` (`:3776-3787`) when typed; `bin/cc-husk-sweep:623` | prefix `exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash <runner>` so the resumed session is runner-owned | — | +4 |
| `bin/kitty-split-cwd.sh:38` | **unchanged**: it is the operator's own split (ruling `337e100f5c71`) | — | — |

Tests for W2:
- lr-fire-resume and reso-resume-one with `CC_PANE_RUNNER_OWNS_CLOSE=$KITTY_WINDOW_ID` exit with the
  session's rc and never exec `$SHELL`; with the flag unset or naming another window they also only exit
  (the operator's prompt remains).
- The runner consumes a staged successor and decides again on its rc (rc 0 plus guard safe → closes).
- Launch-site lint: `git grep -nE '\|\| exec zsh -i|exec "\$\{SHELL' -- bin scripts lib` allowlist =
  {`cc-pane-runner` `_fallback`, `lib/pane-successor.sh` zshexit hook `:341`, `bin/kitty-split-cwd.sh:38`}.
- Invert the SURVIVABILITY pins (`tests/kitty-recovery-launch.bats`, `tests/handoff-recycle-pane-survives.bats`).
- Mutant: restore `exec "${SHELL:-/bin/zsh}" -l -i` at the lr-fire-resume tail → the lint and the test fail.

Size of W2: about **+32 / −118** code lines (deletions measured as non-comment lines; about −170 with
comments).

### W3: the standing census, in the existing drainer job (no new launchd job)

`scripts/pane-close-retry.sh`: move the kitty socket resolution (`:96-106`) and one bounded `kitty @ ls`
above the empty-queue exit (`:63-64`). Then classify each window that has a pane-exit record from this kitty
generation (`ts ≥ _kitty_start_epoch`):

| condition | class |
|---|---|
| claude in the foreground | running |
| `cc-pane-runner` in the foreground, no claude | held (`hold:*`) or waiting (no tail) |
| shells only, with a `keep:<r>` tail | kept[r] |
| shells only, any other tail | **anomaly** |

- Write one row per tick to `~/.claude/logs/pane-census.jsonl`.
- Page once per pane for an anomaly seen on two consecutive ticks, and once for a hold older than 6 h.
- Operator-opened windows have no record and are outside the count by construction.
- "Done" means `anomaly=0` for 7 days on this log (census §6 item 7).

Tests:
- A stub listing yields the right counts; one row per tick even with an empty queue.
- One page for an anomaly; no page for kept panes or holds under 6 h.
- Mutant: census placed after `:64` → no row with an empty queue → fails.

Size: about **+40** code lines (estimated); cost is one `kitty @ ls` per 300 s (estimated as negligible next
to the 300 s interval).

### W4 (optional; none of these is needed for the GOAL)

- **W4a placement.** `scripts/lib/pane-placement.sh` `_ccp_decide` (`:114-170`) ranks a window whose only
  pane is a held runner first in step 2, which shortens holds. About +8 lines.
- **W4b one atomic close.** A `close-if-not-last` action in `lib/kitty-fs-kitten.py` runs in kitty's main
  loop. The runner's close and the hold's release both use it; the process exits on not-found. This
  removes the cross-pane race and the two-read rule. All closers must adopt it for it to help. About
  +25/−10 lines.
- **W4c one final-turn close reader** replaces `transcript_facts` (`bin/cc-pane-close:342-367`),
  `pane_last_close` (`hooks/lead-crash-watchdog.sh:1677-1711`) and `facts_of` (`bin/cc-husk-sweep:452-507`).
  It fixes a stale "yes" and closes risk 4 below. About +35/−60 lines.

---

## 5. Which wave alone makes the GOAL true

**Wave 1 (W1a + W1b).**
- W1a alone makes the GOAL true for pane 289 and every runner-rooted pane, and arms A1–A4 go GREEN with it.
  That is pane 289's actual path, and the path of all 28 runner-kept panes since 10-20 (census §4e) and all
  10 rc70 self-close husks: in every rc70 episode the runner's refusal preceded the watcher's by 0–6 s
  (**measured**, selfclose map §2 item 12).
- W1b is needed before "never painted resume / pane closes despite sibling dirt" also holds for panes the
  runner does not own: lr-fire-resume and reso-resume-one tails, boot-resume, operator panes.
  - Without W1b, such a pane in pane 289's situation still reaches gate 4 → RESUME (arms B1–B4).
  - With W1b, it reaches the guard, gets an honest DONE ⌘W paint, is held by the drainer's existing
    `hold=operator` row, and closes when its window changes (`scripts/pane-close-retry.sh:282-288`).
- W2 and W3 are not needed for the GOAL. W2 moves those panes under the one owner (and is net deletion);
  W3 measures that the class stays at zero.

---

## 6. Pane 289 under W1 (estimated replay of the measured timeline)

| UTC | event (HEAD, measured) | under W1 (estimated) |
|---|---|---|
| 23:53:36 | runner guard refused-fs → husk row, DONE paint, `exec zsh` | `tail:"hold:fs"`, one paint: "✓ 7555024a finished · closes itself when this window gets another pane · ⌘W closes it now" |
| 23:53:38 | watcher rc70 → husk-fs alarm + row | the watcher reads `hold:fs` (≤2 s poll) and logs that the runner owns the pane: no close, no alarm, no row |
| 23:55:00 | watchdog CANTTELL (`dirty:138`) + row | "NOT PAINTED — its cc-pane-runner holds pane 289" |
| 00:00:14 | recompute RESUME "138 unsaved files" | no row, so no recompute |
| 00:16:58 | pane 293 joins window 25; nothing asks again | the next hold poll (≤60 s) reads safe-not-last, confirms 10 s later, `exit 0`; estimated close 00:17:10–00:18:10 (method: join time + ≤60 s backoff + 10 s confirm) |
| 01:46:25 | closed by hand (Track A REPORT §2.1) | already closed |

---

## 7. Risks and operator decisions

**Residual risks:**
1. **An off-screen fullscreen sole pane holds until a companion arrives or the operator presses ⌘W.** Today's
   rc70 husks lasted 21 min to 9 h 29 min (**measured**, selfclose map §4, 8 with end times); the same
   windows would hold that long. The hold is truthful and owned, and W3 pages at 6 h. Shortening it is
   **operator decision D1**: placement rule `fd34d855d`/`6fd8c7068` versus guard decision `e3920969aba9`,
   whose exit condition (`fsfix`) was false on all 977 guard rows from 10-16 to 10-25 (**measured**, census
   Skeptic pass). W4a reduces it.
2. **Cross-pane race.** If two panes of one fullscreen window close in the same instant, both can read
   "not last". This exists today for every closer pair; Track A measured 11 same-count guard pairs within
   5 s. W1 does not widen it, and the two-read rule turns "a joiner that dies within 10 s" into a no-op.
   W4b removes it.
3. **SIGKILL of a held runner** empties the window, exactly as SIGKILL of today's kept zsh does.
4. **Bash-only writes.** `session_dirty_mine` rc 1 means "no edit-recorded path of mine is dirty"
   (`hooks/lib/session-writes.sh:45-53`). Under W1b, a crashed session that said a stale "yes" and wrote
   only through Bash can have its kept pane closed, though its files stay on disk.
   - Bound: gate 4 refused one pane in its whole log, 9 rows all pane 289 (**measured**, closer map §5,
     `jq 'select(.reason|test("uncommitted"))'`).
   - A runner pane never reaches gate 4 after W1a.
   - W4c closes this residue.
   - **Operator decision D3**: accept it, or ship W4c with W1b.
5. **Deploy skew.** Runners and watchers already running keep the code bash parsed at their start until
   they are relaunched. During that window an old watcher can still queue a row for a new held pane; the
   W1a drainer check drops it.
6. **A held pane accepts no shell input.** Keystrokes echo and are ignored; ⌘W closes it without a dialog
   (`is_busy` change).
7. **Closer cost.** W1b adds one bounded `git status -uall` plus a transcript scan to `cc-pane-close` when
   the cwd is dirty. The closer already hits its 60 s bound (25 rc-124 attempts on 6 panes, **measured** by
   the closer map §5). Mitigations: the clean-tree fast path, and W2 removes most callers.
8. **No env kill switch** (`bin/kitty-fullscreen-guard:75-77`). Rollback is a revert of the W1a or W1b
   commit; each is self-contained.

**Operator decisions flagged, not taken here:**
- **D1**: placement versus the fullscreen guard (see risk 1).
- **D2**: ruling `337e100f5c71` keeps hand-opened windows open on `/exit`, against the contract restated
  on 10-01, 10-18, 10-22 and 10-25 (census §2). Operator panes stay outside the invariant until this is
  decided.
- **D3**: see risk 4.

---

## 8. Evidence index

**Measured:**
- `python3 -I /tmp/husk-fix-design/probe/drive.py` (bash 3.2.57, `/bin/bash --version`):
  - signals case: all five signals → alive; still polling; release rc 0 after two safe reads; no fallback;
  - single-ok case: alive after one safe read then refusal; rc 4 → exit 0;
  - escape case: fallback exec'd with INT/TERM/HUP not ignored.
- Range sizes: `sed -n A,Bp FILE | wc -l` / `| grep -cv '^\s*#'`:
  - `bin/cc-pane-runner:257-349` = 93/74;
  - `scripts/limit-recover/lr-fire-resume.sh:2253-2304` = 52/29;
  - `bin/reso-resume-one:1131-1216` = 86/62;
  - `bin/reso-resume-one:229-256` = 28/21;
  - `bin/cc-pane-close:508-512` = 4 code; `hooks/lead-crash-watchdog.sh:1664-1671` = 8;
    `bin/cc-husk-sweep:508-515` = 8.
- File sizes, `wc -l`: runner 646, cc-pane-close 557, cc-pane-verdict 176, cc-husk-sweep 629,
  pane-close-retry.sh 517, handoff-fire.sh 21830, lead-crash-watchdog.sh 2761, session-writes.sh 670,
  kitty-fullscreen-guard 1019, pane-placement.sh 283.
- `grep -rn 'comm=' bin scripts hooks lib | wc -l` = 130 (blast radius of a lifelong rename).
- Cited from inputs (measured there): census §4e (28 runner keeps), selfclose map §2/§4 (rc70 10/10,
  husk durations), closer map §4/§5 (`session_dirty_mine` rc 1 for 7555024a; gate-4 rows = 9; rc 124 = 25),
  recycle map §2a (lr-fire-resume husks), lifecycle map §5 (390 runner guard verdicts, 36 refused), census
  Skeptic pass (977 guard rows `fsfix:false`).

**Estimated:**
- All "added" LOC: line counts of the sketches and tables in this document.
- Track A totals: its own §4 sizing.
- Pane 289's W1 close time (method in §6).
- Census cost: one `kitty @ ls` per 300 s.
