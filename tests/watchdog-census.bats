#!/usr/bin/env bats
#
# watchdog-census.bats — M4. Two subjects, one defect:
#
#   hooks/lead-crash-watchdog.sh  the daemon could not EXIT (the wedge)
#   bin/cc-reaper watchdog-census the population could not be SEEN (the census)
#
# THE WEDGE. The daemon's poll loop tested the lead with a bare `kill -0 "$pid"`, which answers only
# "some process holds this pid". macOS recycles pids, so once the lead died and its pid was reused the
# answer flipped back to ALIVE permanently and NEITHER of the loop's two exit conditions could ever
# become true again. Measured 2026-07-29 before the fix: 63 live daemons, 14 named by no .daemon
# record, oldest 1d15h, against 157 spawns and ZERO logged exits of EITHER kind that day. The
# remedy is the {pid, lstart} identity this file already used on the DAEMON (daemon_alive) and
# cc-reaper uses on its sweep lock — never applied to the SUBJECT being watched.
#
# THE UNTRACKED CLASS. Separately, the parent hook held the only record of the daemon it had just
# spawned and had no HUP trap (only the daemon subshell did), so a pane teardown inside that window
# killed the parent and left a daemon named by no .daemon file and no log line — invisible to the
# single-instance guard forever (0 "retired stale watchdog" lines in 3864 spawns).
#
# WHY THE CENSUS IS PROCESS-TABLE-FIRST: a census keyed on ~/.claude/watchdog/*.pid can only see
# daemons that were RECORDED, and the untracked class is by definition the ones that were not. Keyed
# on files it would have printed a clean zero while 14 daemons ran. Both controls below exist because
# a blind census and a healthy one produce identical output.
#
# RED-PROOF: every test fails against the pristine pre-change tree, where the dispatch arm, both
# controls, lead_alive and the parent trap do not exist:
#   t=$(mktemp -d); git archive eaa0cdeb | tar -x -C "$t"
#   CC_WATCHDOG_SUBJECT_ROOT="$t" bats tests/watchdog-census.bats
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` wherever a
# non-final `[[ ]]` / `!` / `A && B` appears.
#
# FORK-FREE FIXTURES: no `sleep &` anywhere. A backgrounded job in a bats fixture prints its own
# `not ok` line BESIDE the `ok` for a body that passed, and the land gate greps for `not ok`.
# Where a "live process" is needed, the test uses its OWN pid — alive by construction, nothing to reap.

# shellcheck disable=SC2034  # consumed by bats itself; file-level is the ONLY working placement (memory: bats-runtime-cap-placement)
BATS_TEST_TIMEOUT=180

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_WATCHDOG_SUBJECT_ROOT:-$REPO}"
  REAPER="$ROOT/bin/cc-reaper"
  HOOK="$ROOT/hooks/lead-crash-watchdog.sh"

  D="$BATS_TEST_TMPDIR"
  # Fixture HOME: the census defaults to ~/.claude/watchdog and ~/.claude/logs. An unfixtured HOME
  # reads the operator's real fleet, which the repo's hermeticity ratchet fails the land gate on.
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs"
  export CC_WATCHDOG_DIR="$D/watchdog"; mkdir -p "$CC_WATCHDOG_DIR"
  export CC_WATCHDOG_LOG="$D/wd.log"; : > "$CC_WATCHDOG_LOG"

  # Hermetic process table. Two reasons, both load-bearing: the census would otherwise read the
  # OPERATOR's real fleet (the repo's hermeticity ratchet fails the land gate on exactly that), and
  # a live table of ~60 daemons makes every test pay for a full ps plus a row per daemon — on a
  # machine already running a dozen sibling suites that is the difference between a suite that
  # finishes and one that looks hung. Tests that need a specific table override this with their own.
  export CC_WATCHDOG_PS_BIN="$D/ps-empty"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "  PID STARTED ELAPSED ARGS"\n'; } > "$CC_WATCHDOG_PS_BIN"
  chmod +x "$CC_WATCHDOG_PS_BIN"

  # A pid that CANNOT exist: macOS caps pids at 99999, so this is ESRCH by construction and can never
  # be recycled into a live process underneath the test.
  DEAD_PID=2147483647
  MY_LSTART="$(ps -o lstart= -p $$ 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
}

# ── the census leg exists at all ────────────────────────────────────────────────────────────────
@test "watchdog-census: the dispatch arm exists and the leg runs clean" {
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *"CENSUS ONLY"*) ;; *) echo "no census banner: $output"; false ;; esac
}

# ── positive controls: a blind census and a healthy census print the same counts ────────────────
@test "watchdog-census: control 1 proves the sid-keyed classifier actually decides" {
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *"control=OK"*) ;; *) echo "control did not pass: $output"; false ;; esac
}

@test "watchdog-census: control 2 proves the process-table enumerator can SEE an unrecorded daemon" {
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *"control-untracked=OK"*) ;; *) echo "untracked control did not pass: $output"; false ;; esac
}

# Control 3 covers what control 1 structurally cannot. Control 1 writes its fixture with wd_lstart
# and reads it back through wd_lstart_matches's reader-ambient arm — the SAME function in the SAME
# shell — so it matches by construction: measured 2026-08-26, deleting EITHER cross-dialect arm of
# wd_lstart_matches leaves control 1 printing OK. Those arms carry backlog 7a00b5de1ec0's dialect
# tolerance, and their failure is the quiet one (a running daemon recorded in another locale
# classifies `stale-file` = "residue, nothing to reap", and the census reports a clean zero).
#
# The assertion is "not FAIL and not absent", never "== OK", because OK is not portable: a reader
# already at UTC/C renders every dialect the same and the fixture then cannot discriminate, which
# control 3 reports as N/A. N/A is an honest non-verdict and must not red; FAIL and a missing line
# must. Killable either way — delete an arm and the real subject prints FAIL here.
@test "watchdog-census: control 3 proves the cross-dialect arms match, or says it cannot tell" {
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in
    *"control-dialect=FAIL"*) echo "dialect control FAILED: $output"; false ;;
    *"control-dialect="*) ;;
    *) echo "dialect control did not render at all: $output"; false ;;
  esac
}

# ── classification ──────────────────────────────────────────────────────────────────────────────
@test "classify: dead lead + live pinned daemon = orphan, and its reap command is printed" {
  printf '%s\n' "$DEAD_PID" > "$CC_WATCHDOG_DIR/sid-a.pid"
  printf '%s\t%s\n' "$$" "$MY_LSTART" > "$CC_WATCHDOG_DIR/sid-a.daemon"
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *"kill $$"*) ;; *) echo "no reap command for the orphan: $output"; false ;; esac
}

@test "classify: a live pid that is NOT a claude binary is never called a live session (recycled-pid defense)" {
  # $$ is this bats shell — alive, but not claude. Answering "is the session alive" with bare pid
  # liveness is the very defect under test; the classifier must read the command too.
  printf '%s\n' "$$" > "$CC_WATCHDOG_DIR/sid-b.pid"
  run "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  case "$output" in *'"sid":"sid-b","class":"stale-file"'*) ;; *) echo "recycled lead pid not caught: $output"; false ;; esac
}

@test "classify: a .daemon record whose lstart no longer matches is NOT a live daemon" {
  printf '%s\n' "$DEAD_PID" > "$CC_WATCHDOG_DIR/sid-c.pid"
  printf '%s\t%s\n' "$$" "Wed 01 Jan 00:00:00 2000" > "$CC_WATCHDOG_DIR/sid-c.daemon"
  run "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  case "$output" in *'"sid":"sid-c","class":"stale-file"'*) ;; *) echo "wrong-lstart record trusted: $output"; false ;; esac
}

# ── the enumerator ──────────────────────────────────────────────────────────────────────────────
@test "enumerate: matches the script in the COMMAND position, not a mere argv mention" {
  # The decoy is the pgrep -f trap: a claude session whose brief quotes the hook path. It is a real
  # observed failure (agent argv carries whole briefs), and counting it would inflate the census with
  # sessions that are not daemons at all.
  stub="$D/ps"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "  PID STARTED                     ELAPSED ARGS"\n'
    printf 'printf "%%s\\n" "111 Wed 29 Jul 22:34:14 2026 00:10 /bin/bash /x/hooks/lead-crash-watchdog.sh"\n'
    printf 'printf "%%s\\n" "222 Wed 29 Jul 22:34:14 2026 00:10 /x/claude --print please fix hooks/lead-crash-watchdog.sh"\n'
    printf 'printf "%%s\\n" "333 Wed 29 Jul 22:34:14 2026 00:10 /bin/bash /x/hooks/not-the-watchdog.sh"\n'
  } > "$stub"
  chmod +x "$stub"
  # The suite's own copy of the census sees the stub table; a stray real daemon must not leak in.
  run env CC_WATCHDOG_PS_BIN="$stub" "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["counts"]["live_procs"]==1, d["counts"]; assert d["counts"]["untracked_orphan"]==1, d["counts"]'
  case "$output" in *'"daemon_pid":"111"'*) ;; *) echo "the real daemon was not enumerated: $output"; false ;; esac
  case "$output" in *'"daemon_pid":"222"'*) echo "argv MENTION counted as a daemon (pgrep -f trap): $output"; false ;; *) ;; esac
}

# ── the safety property: CENSUS ONLY ────────────────────────────────────────────────────────────
@test "census kills NOTHING — the process it names as an orphan is still alive afterwards" {
  # Effect read, not a text scan: the fixture orphan names THIS test's own pid, so if the leg ever
  # actuated instead of printing, the assertion below could not run at all.
  printf '%s\n' "$DEAD_PID" > "$CC_WATCHDOG_DIR/sid-d.pid"
  printf '%s\t%s\n' "$$" "$MY_LSTART" > "$CC_WATCHDOG_DIR/sid-d.daemon"
  run "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *"kill $$"*) ;; *) echo "orphan not named: $output"; false ;; esac
  kill -0 "$$" 2>/dev/null || { echo "the census KILLED its own subject"; false; }
}

@test "census: kill switch CC_WATCHDOG_CENSUS=off takes no census" {
  run env CC_WATCHDOG_CENSUS=off "$REAPER" watchdog-census
  [ "$status" -eq 0 ]
  case "$output" in *DISABLED*) ;; *) echo "kill switch ignored: $output"; false ;; esac
  case "$output" in *"CENSUS ONLY"*) echo "census ran despite the kill switch: $output"; false ;; *) ;; esac
}

# ── machine output + log reconcile ──────────────────────────────────────────────────────────────
@test "census --json emits parseable JSON carrying both control verdicts" {
  run "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["control_ok"] is True, d; assert d["control_untracked_ok"] is True, d; assert "untracked_orphan" in d["counts"], d; assert "spawned" in d["log"], d'
}

# control_dialect is a STRING here, not a bool, and that is the point: its N/A and UNKNOWN values
# are non-verdicts a bool would launder into `true`. Assert it is one of the four declared values
# and that it is not FAIL — the same polarity as the human-output test above.
@test "census --json carries the dialect control as a four-valued string, not a laundered bool" {
  run "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d["control_dialect"]; assert v in ("OK","N/A","UNKNOWN","FAIL"), d; assert v != "FAIL", d'
}

@test "census reconciles spawned vs exits from the daemon's own log" {
  {
    printf '%s\n' "[t] spawned watchdog daemon pid=1 for session=x pid=2"
    printf '%s\n' "[t] spawned watchdog daemon pid=3 for session=y pid=4"
    printf '%s\n' "[watchdog x] pid file gone — exit"
    printf '%s\n' "[watchdog y] SUPERSEDED — pidfile holds 9, not our lead 4 — exit"
    printf '%s\n' "[watchdog z] LEAD CRASH detected pid=7"
  } > "$CC_WATCHDOG_LOG"
  run "$REAPER" watchdog-census --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin)["log"]; assert d["spawned"]==2, d; assert d["clean_exit"]==1, d; assert d["superseded"]==1, d; assert d["crash_path"]==1, d'
}

# ── the wedge itself: the hook must be able to exit ─────────────────────────────────────────────
@test "hook: lead_alive reads a RECYCLED pid as DEAD (the wedge), and an unpinned one as alive" {
  # The real function, lifted out of the daemon subshell and executed — not a re-implementation, and
  # not a text match. A text assertion would pass on a function that had been commented out.
  fn="$D/lead_alive.sh"
  awk '/^  lead_alive\(\) \{$/,/^  \}$/' "$HOOK" > "$fn"
  [ -s "$fn" ] || { echo "lead_alive() not found in $HOOK — extraction empty, the pin is absent"; false; }
  # shellcheck disable=SC1090
  . "$fn"
  type lead_alive >/dev/null 2>&1 || { echo "extraction did not define lead_alive"; false; }

  lead_alive "$$" "$MY_LSTART" || { echo "the live, correctly-pinned process read DEAD"; false; }
  run lead_alive "$$" "Wed 01 Jan 00:00:00 2000"
  [ "$status" -eq 1 ]                       # ← THE FIX: recycled to a non-claude stranger = DEAD
  run lead_alive "$DEAD_PID" "$MY_LSTART"
  [ "$status" -eq 1 ]
  lead_alive "$$" "" || { echo "the documented empty-lstart fallback stopped working"; false; }
}

@test "hook: a re-rendered start time on a LIVE claude is state 2, never an invented crash" {
  # `ps -o lstart=` renders through the CURRENT timezone — the same live pid prints 00:53 local,
  # 07:53 under TZ=UTC, 16:53 under TZ=Asia/Tokyo — so a DST transition changes the pin string for a
  # process that never restarted. If that read as DEAD, handle_crash would fire on a HEALTHY team
  # (shutdown_request into every inbox, CRASH_REPORT.md, pane teardown where armed), twice a year,
  # on every daemon at once. It must be a distinct, non-fatal state.
  fn="$D/lead_alive2.sh"
  awk '/^  lead_alive\(\) \{$/,/^  \}$/' "$HOOK" > "$fn"
  [ -s "$fn" ] || { echo "lead_alive() not found — extraction empty"; false; }
  # shellcheck disable=SC1090
  . "$fn"

  # Shadowing ps drives all three verdicts fork-free: no background job, nothing to reap, and the
  # REAL function body is what is being exercised.
  ps() { case "$*" in *lstart*) printf 'Wed 01 Jan 00:00:00 2000\n' ;;
                      *command*) printf '%s\n' "$FAKE_CMD" ;; esac; }

  FAKE_CMD="/Users/x/.claude/node_modules/.bin/claude"
  run lead_alive "$$" "Thu 30 Jul 00:00:00 2026"
  [ "$status" -eq 2 ] || { echo "a live claude with a re-rendered pin returned $status — 1 would invent a crash on a live team"; false; }

  FAKE_CMD="/usr/bin/some-unrelated-daemon"
  run lead_alive "$$" "Thu 30 Jul 00:00:00 2026"
  [ "$status" -eq 1 ] || { echo "a pid recycled to a stranger returned $status — the wedge stays open"; false; }
}

@test "hook: state 2 re-pins but is BOUNDED, so it cannot restore immortality" {
  grep -qE 'repins > 2' "$HOOK" || { echo "the re-pin path is unbounded — immortality returns through it"; false; }
  grep -qF 'IDENTITY LOST' "$HOOK" || { echo "the exhausted-re-pin exit is not named"; false; }
  grep -qE 'lrc=0; lead_alive "\$pid" "\$start" \|\| lrc=\$\?' "$HOOK" || { echo "lead_alive is called bare under errexit — state 1 would abort the daemon before handle_crash"; false; }
}

@test "hook: the poll loop uses the pinned check and the call site actually passes the lstart" {
  # An unpassed third argument would leave lead_alive permanently in its unpinned fallback — the pin
  # present, dead, and reading as fixed.
  grep -qE 'lead_alive "\$pid" "\$start"' "$HOOK" || { echo "poll loop is not using lead_alive"; false; }
  grep -qE 'local_watchdog "\$LEAD_PID" "\$SESSION_ID" "\$LEAD_START"' "$HOOK" || { echo "call site does not pass LEAD_START"; false; }
  grep -qE '^LEAD_START=\$\(ps -o lstart=' "$HOOK" || { echo "LEAD_START is never captured"; false; }
}

@test "hook: a superseded daemon retires itself without needing any bookkeeping" {
  grep -qF 'SUPERSEDED — pidfile holds' "$HOOK" || { echo "no superseded exit in the poll loop"; false; }
}

@test "hook: the parent survives its own bookkeeping window (the untracked class, at source)" {
  # The trap must be armed BEFORE the daemon is spawned; after the `&` the record can already be lost.
  trap_line="$(grep -n "^trap '' HUP" "$HOOK" | head -1 | cut -d: -f1)"
  spawn_line="$(grep -n '^# Spawn detached watchdog daemon' "$HOOK" | head -1 | cut -d: -f1)"
  [ -n "$trap_line" ] || { echo "parent has no HUP trap — the untracked class survives"; false; }
  [ -n "$spawn_line" ] || { echo "spawn comment anchor missing"; false; }
  [ "$trap_line" -lt "$spawn_line" ] || { echo "HUP trap ($trap_line) is armed after the spawn ($spawn_line)"; false; }
}

# ── death-path bounding ─────────────────────────────────────────────────────────────────────────
@test "hook: every external call on the death path is time-bounded" {
  # The daemon is the last thing running for a dead session and nothing supervises IT: an unbounded
  # call here strands every teammate the crash handler exists to notify.
  grep -qE 'lcw_bounded\(\)' "$HOOK" || { echo "no lcw_bounded helper"; false; }
  # `pgrep -x`, NOT `ps aux`. This list named `ps aux` from the day it was written (dd7ddb528) and
  # the same commit's hook stopped executing one — the concurrency probe is `pgrep -x` and the walk
  # survives only inside the comment explaining its removal. So the assertion was born unsatisfiable
  # in the one direction that matters: the only way to make it pass was to RE-INTRODUCE the
  # full-table walk that the load-781 incident measured at 10-30s × ~20 concurrent scans, feeding
  # the very load it was measuring. A stale term here does not merely fail to guard — it guards the
  # bug (memory: stale-assertion-becomes-an-inverted-guard). Nothing else in the corpus ran it: the
  # suite is in scripts/offbox-excluded.manifest, so the off-box producer never judged it.
  # PER SITE, not once per name. The original form asked only whether the file contained SOME
  # bounded occurrence of each name, so with two pgrep probes on the death path, unbinding one was
  # invisible — proved by mutation: dropping lcw_bounded from the first probe left this case green.
  # A rule called "every external call" has to be able to fail on one of them
  # (memory: per-site-mutation-attributes-coverage). The patterns are INVOCATION shapes rather than
  # bare names, because `[[ -n "$tdbin" ]]` is a test, not a call, and a per-line rule keyed on the
  # bare name would red the three guards that legitimately surround the one invocation.
  for call in '"\$\{LCW_PYTHON_BIN:-python3\}"' '/usr/bin/memory_pressure' '/usr/bin/pgrep' '"\$tdbin" "'; do
    sites="$(grep -vE '^[[:space:]]*#' "$HOOK" | grep -E "$call" || true)"
    [ -n "$sites" ] || { echo "death-path call vanished (the rule cannot pass by deletion): $call"; return 1; }
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in
        *lcw_bounded*) ;;
        *) echo "unbounded death-path call: $call"; echo "  $line"; return 1 ;;
      esac
    done <<EOF_SITES
$sites
EOF_SITES
  done
}

@test "hook: the concurrency probe stays pgrep -x — the full-table walk must not come back" {
  # The load-781 cure had no guard of its own, and the assertion above pointed the other way. An
  # executable `ps aux` on the death path is the regression; the comment that explains why it left
  # is not, so the scan is of code lines only.
  if grep -vE '^\s*#' "$HOOK" | grep -qE '(^|[^-])\bps\b[^|]*\baux\b'; then
    echo "the full-table walk is back on an executable line:"
    grep -vE '^\s*#' "$HOOK" | grep -nE '(^|[^-])\bps\b[^|]*\baux\b'
    return 1
  fi
  # …and the probe it was replaced by is still there, so this case cannot pass by the hook simply
  # losing the probe altogether.
  grep -qE "lcw_bounded [^|]*pgrep -x" "$HOOK" || { echo "the pgrep -x probe is gone entirely"; return 1; }
}

@test "hook: a cut teardown is a THIRD state, never counted as a verdict" {
  # timeout(1)'s rc 124 must not land in n_fail ("acted, pane survived" — unclaimable) nor n_refuse
  # ("a gate declined" — nothing declined).
  grep -qE '^\s*124\)' "$HOOK" || { echo "rc 124 has no arm — a cut call is read as a verdict"; false; }
  grep -qF 'NO-VERDICT' "$HOOK" || { echo "the cut state is not named distinctly"; false; }
}
