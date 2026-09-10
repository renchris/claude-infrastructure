#!/usr/bin/env bats
# tests/session-busy.bats — the working-vs-idling sensor (CLOSE_SCANNABILITY D8, backlog
# a3eaa0dc1be2; build spec docs/research/exhaustive-drive-2026-09-08/A10-idle-visibility.md §6).
#
# WHAT THESE ARE FOR. The sensor's whole value is that it can say IDLE — a count that is never zero
# cannot answer "working or idling", and the naive form of this scan was FALSIFIED before a line
# was built precisely there (its negative control returned 9, not 0, all of it wake/watchdog
# infrastructure). So every BUSY case here is paired with a negative control, and the three idle
# states are asserted apart from one another rather than as "not busy".

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  # HERMETIC $HOME: the subject resolves config roots and its own sibling libs under $HOME, so an
  # unfixtured run reads the operator's live ~/.claude — and a suite that goes red only in a pane
  # that injects CC_PANE_CMD* reads as a trunk red. Both are the test-hermeticity ratchet's classes.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/hooks/lib"
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE || true
  LIB="$REPO/hooks/lib/session-busy.sh"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats";      mkdir -p "$CC_BEAT_DIR"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/perm";   mkdir -p "$CC_PERMPEND_DIR"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg";  mkdir -p "$CLAUDE_CONFIG_DIR/state"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbx";     mkdir -p "$CC_MAILBOX_DIR"
  export CC_BUSY_LIB_DIR="$REPO/hooks/lib"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT/scripts" "$WT/tests"; WT="$(cd "$WT" && pwd -P)"
  # The root rule RESOLVES an argv token against the process cwd and stats it, so a fixture whose
  # argv names a file that does not exist tests the negative branch by accident. A fixture is a
  # contract claim about its producer, and the producer's scripts are on disk.
  : > "$WT/scripts/ship-land.sh"; : > "$WT/tests/wrap-ledger.bats"
  EMPTY="$BATS_TEST_TMPDIR/empty"; mkdir -p "$EMPTY"; EMPTY="$(cd "$EMPTY" && pwd -P)"
  SID="11111111-2222-4333-8444-555555555555"
  unset CC_PANE_ID ITERM_SESSION_ID CC_BUSY_CUSTODY_OPEN || true
}

# The beat, in the PRODUCER's dialect. hooks/session-beat.sh:93 is the only authority on what that
# is, and this helper mirrors it token for token — a fixture is a contract claim about its producer.
producer_lstart() { TZ=UTC ps -o lstart= -p "${1:-$$}" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//'; }

mk_beat() {  # <kind> [pid] [lstart-override]
  local kind="$1" pid="${2:-$$}" ls="${3:-}"
  [ -n "$ls" ] || ls="$(producer_lstart "$pid")"
  jq -nc --arg sid "$SID" --arg k "$kind" --arg ls "$ls" --argjson pid "$pid" --argjson t "$(date +%s)" \
    '{sid:$sid,pane:"999",cwd:"/x",pid:$pid,lstart:$ls,t:$t,kind:$k,who:"operator",operatorT:$t,seq:3}' \
    > "$CC_BEAT_DIR/$SID.json"
}

# ps/cwd stubs. Production pids are NUMERIC and production argv carries absolute paths, so the
# fixture emits both shapes — a fixture that cannot express the axis under test holds it constant
# (MEMORY: fixture-identifier-shape-collapses-two-spaces).
mk_procs() {  # rows: "pid ppid command"
  { echo '#!/bin/bash'; echo 'cat <<TABLE'; for r in "$@"; do printf '%s\n' "$r"; done; echo 'TABLE'; } \
    > "$BATS_TEST_TMPDIR/ps"; chmod +x "$BATS_TEST_TMPDIR/ps"
  export CC_PROC_SCOPE_PS="$BATS_TEST_TMPDIR/ps"
}
mk_cwds() {  # pairs: "pid=cwd"
  { echo '#!/bin/bash'; echo 'case "$1" in'
    for kv in "$@"; do printf '  %s) echo "%s" ;;\n' "${kv%%=*}" "${kv#*=}"; done
    echo '  *) echo "" ;;'; echo 'esac'; } > "$BATS_TEST_TMPDIR/cwd"; chmod +x "$BATS_TEST_TMPDIR/cwd"
  export CC_PROC_SCOPE_CWD="$BATS_TEST_TMPDIR/cwd"
}
sbl() { bash -c ". '$LIB'; $*"; }

# ════ THE LSTART DIALECT — the red-proof this whole file exists for ══════════════════════════════
# The beat producer writes `TZ=UTC ps -o lstart=` in the reader's AMBIENT locale. Every other
# {pid,lstart} consumer in this repo pins the canonical `TZ=UTC LC_ALL=C`, so the natural reader —
# and the one A10 §6.1 literally specifies — MISMATCHES, and a mismatch means GONE, and GONE never
# renders BUSY. The sensor would have read "not working" for every live session on the box: silent,
# total, and in the direction the design calls the dangerous one. Same class as land-inflight.sh's
# C31/C33 (two producers, opposite dialects, 100% miss).

@test "dialect: the two renderings actually DIFFER here — else every case below is vacuous" {
  # PRECONDITION, asserted rather than hoped for. If this box rendered both dialects identically,
  # the red-proof beneath would pass against the BROKEN reader too and prove nothing.
  #
  # AND THE ENVIRONMENT DECIDES IT. Under LC_ALL=C — which is exactly what scripts/offbox-run.sh
  # and CI impose — `TZ=UTC ps` and `TZ=UTC LC_ALL=C ps` are the SAME STRING, so the two dialects
  # coincide and the red-proof genuinely has nothing to prove THERE. That is a fact about the
  # world, not a failure of the subject: the reader accepts both renderings either way, and the
  # cases below still pass. So this SKIPS rather than reds — a precondition that cannot hold in an
  # environment must retire the case it guards, not convict it (a red here would report "the
  # sensor is broken" for a locale setting). The interactive desk, where the operator's ambient
  # locale is not C, is where this case has power and where the bug it pins was measured.
  a="$(TZ=UTC ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  b="$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$a" ] && [ -n "$b" ] || false
  if [ "$a" = "$b" ]; then
    skip "LC_ALL=C here: both lstart dialects render identically, so the red-proof is vacuous in this environment"
  fi
  [ "$a" != "$b" ] || false
}

@test "dialect: a beat in the PRODUCER's dialect reads BUSY (canonical-only would read GONE)" {
  mk_beat prompt "$$"
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "session_busy_live '$SID' '$EMPTY'"
  # This half binds EVERYWHERE, C locale included: the reader must accept what the producer wrote.
  [ "$status" -eq 0 ]
  [[ "$output" == BUSY* ]] || false
  [[ "$output" == *beat* ]] || false
  # The mutant, executed rather than described: a reader accepting ONLY the house canon. It can
  # only discriminate where the dialects differ — see the precondition case above.
  rec="$(jq -r .lstart "$CC_BEAT_DIR/$SID.json")"
  canon="$(TZ=UTC LC_ALL=C ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  if [ "$rec" = "$canon" ]; then
    skip "dialects coincide in this environment; the canonical-only mutant is indistinguishable here"
  fi
  [ "$rec" != "$canon" ] || false   # ⇒ the canonical-only reader cannot match ⇒ GONE ⇒ never BUSY
}

@test "dialect: a beat whose lstart names a DIFFERENT instant is GONE, never BUSY" {
  # The fallback forgives a DIALECT; it must not forgive a different process. Both renderings of a
  # recycled pid differ in their time-of-day digits, so no dialect can rescue this.
  mk_beat prompt "$$" "Thu 10 Sep 03:33:33 1999"
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "session_busy_live '$SID' '$EMPTY'"
  [ "$status" -eq 1 ]
  [[ "$output" == GONE* ]]
}

@test "dialect: a beat naming a DEAD pid is GONE, never a frozen BUSY" {
  # The measured false-BUSY: a frozen `prompt` beat from a dead session reads prompt forever.
  dead=99998; while kill -0 "$dead" 2>/dev/null; do dead=$(( dead + 1 )); done
  mk_beat prompt "$dead" "Thu 10 Sep 03:33:33 2026"
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "session_busy_live '$SID' '$EMPTY'"
  [ "$status" -eq 1 ]
  [[ "$output" == GONE* ]]
}

# ════ THE THREE IDLE-SIDE STATES — asserted APART, never as "not busy" ═══════════════════════════

@test "states: kind=stop with no job and no arm is IDLE-DEAF" {
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "session_busy_live '$SID' '$EMPTY'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

@test "states: the SAME session with a continue sentinel armed is IDLE-ARMED, not IDLE-DEAF" {
  # Collapsing these two re-creates the wake-floor blindness: one resumes by itself, one never will.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl ". '$REPO/hooks/lib/continue-sentinel.sh'; touch \"\$(continue_sentinel_for '$EMPTY')\"; session_busy_live '$SID' '$EMPTY'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-ARMED* ]] || false
  [[ "$output" == *continue* ]]
}

@test "states: the continue sentinel is keyed on the PHYSICAL path" {
  # session-continue.sh hashes (config-dir | cwd) with a PHYSICAL cwd, so a /tmp spelling of a
  # /private/tmp dir hashes differently, the file test misses, and an ARMED session reports DEAF —
  # the wrong direction. Measured on the first draft of sb_idle_arms.
  case "$EMPTY" in /private/*) ;; *) skip "TMPDIR is not /private-prefixed on this box" ;; esac
  nonphys="${EMPTY#/private}"
  mk_beat stop "$$"; mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl ". '$REPO/hooks/lib/continue-sentinel.sh'; touch \"\$(continue_sentinel_for '$EMPTY')\"; session_busy_live '$SID' '$nonphys'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-ARMED* ]] || false
}

@test "states: an open custody debt is a wake path too" {
  mk_beat stop "$$"; mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "CC_BUSY_CUSTODY_OPEN=2 session_busy_live '$SID' '$EMPTY'"
  [[ "$output" == IDLE-ARMED* ]] || false
  [[ "$output" == *custody* ]]
}

@test "states: no session id is UNKNOWN — an instrument gap, never an idle verdict" {
  mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  run sbl "session_busy_live '' '$EMPTY'"
  [ "$status" -eq 1 ]
  [[ "$output" == UNKNOWN* ]]
}

# ════ THE JOB SCAN (Q2) — and the classifier that made it usable ═════════════════════════════════

@test "jobs: a gate executing in MY worktree is BUSY at a Stop, with its sample attached" {
  # At a Stop the beat says `stop` and is RIGHT — the model is not thinking. This arm is the only
  # sensor that can see a backgrounded gate, which is the whole Q2 half of the design.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" "4000 1 bash $WT/scripts/ship-land.sh --trunk main" "4001 4000 sleep 30"
  mk_cwds "1=/" "4000=$WT" "4001=/private/var/folders/bats-run-XXX/test/1"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 0 ]
  [[ "$output" == BUSY* ]] || false
  [[ "$output" == *job* ]] || false
  [[ "$output" == *ship-land.sh* ]]      # THE SAMPLE IS THE CONTRACT — see the header of the lib
}

@test "jobs: the NEGATIVE control — wake/watchdog infrastructure is not work" {
  # This is the case that falsified the naive predicate: its negative control returned 9, not 0,
  # and all 9 were exactly these processes. A sensor that is never idle answers nothing.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" \
           "5000 1 bash $HOME/.claude/bin/cc-await-ping abcd" \
           "5001 1 bash $HOME/.claude/hooks/mailbox-wake-arm.sh" \
           "5002 1 bash $HOME/.claude/hooks/lead-crash-watchdog.sh" \
           "5003 1 caffeinate -i -t 300"
  mk_cwds "1=/" "5000=$WT" "5001=$WT" "5002=$WT" "5003=$WT"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

@test "jobs: a claude SESSION in my worktree is not a job — it is the session itself" {
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" \
           "6000 1 /Users/x/.claude/node_modules/.bin/claude --model claude-opus-5 TASK run ./scripts/ship-land.sh and bats tests/"
  mk_cwds "1=/" "6000=$WT"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

@test "jobs: a program naming NO worktree path is not this worktree's work" {
  # INVERTED IN PLACE, 2026-09-10, and the old assertion is kept as the record of what was believed.
  # D8 addendum 2 chose fail-toward-WORK for the unknown case, when this scan was the ENTIRE design.
  # Re-measured against the live population it made the scan read BUSY in an idle worktree — the
  # same falsification D8 ran on the naive form, surviving its own fix (a `zsh -c` snapshot shell,
  # bare `sleep`s, a `tee` into a log, the Python side-cars, a sibling repo's cc-pane-runner). A10
  # §4 then showed the beat answers "am I working" directly, which demotes this arm to the Stop-time
  # question and makes an allowlist root rule the right trade. See the lib header, § WHAT A ROOT IS.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" "7000 1 /opt/homebrew/bin/some-novel-tool --run"
  mk_cwds "1=/" "7000=$WT"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

@test "jobs: the SAME unknown program IS work once it names a worktree path" {
  # The pair is the point: the discriminator is argv POSITION resolving to a real file in MY
  # worktree, not the program's name. `CC_BUSY_JOB_EXTRA` is the seam for the known residual (a job
  # like `pnpm build` that names no repo path).
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" "7000 1 /opt/homebrew/bin/some-novel-tool --run $WT/scripts/ship-land.sh"
  mk_cwds "1=/" "7000=$WT"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 0 ]
  [[ "$output" == BUSY* ]] || false
  [[ "$output" == *some-novel-tool* ]]
}

@test "jobs: the MEASURED furniture population reads IDLE — the falsification D8 prescribed" {
  # These are the exact rows the composed rule still called WORK on 2026-09-10. A count that is
  # never zero cannot answer "working or idling", so this case is the sensor's reason to exist.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" \
    "9001 1 /bin/zsh -c source /Users/chrisren/.claude-tertiary/shell-snapshots/snapshot-zsh-1789.sh" \
    "9002 1 sleep 25" \
    "9003 1 /bin/bash /Users/chrisren/Development/claude-infrastructure/bin/cc-pane-runner" \
    "9004 1 tee -a /Users/chrisren/.claude/logs/close-records/.stderr.u7eE2k" \
    "9005 1 /Library/Frameworks/Python.framework/Versions/3.11/Resources/Python.app/Contents/MacOS/Python - /var/folders/0s/T/cc-x"
  mk_cwds "1=/" "9001=$WT" "9002=$WT" "9003=$WT" "9004=$WT" "9005=$WT"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

@test "jobs: a test runner is reached through its PARENT, which is why the closure is not optional" {
  # D8's own falsifier for the allowlist direction: bats-exec-test's suite path sits at argv[2+] and
  # its cwd is its own BATS_TEST_TMPDIR, so neither half of the root test can see it. Its parent
  # `bats tests/wrap-ledger.bats` resolves argv[1] against its cwd and matches; the descendant
  # closure carries the children, whatever their own cwd or argv say.
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" \
    "1000 1 bash /opt/homebrew/Cellar/bats-core/1.13.0/libexec/bats-core/bats tests/wrap-ledger.bats" \
    "1001 1000 bash /opt/homebrew/Cellar/bats-core/1.13.0/libexec/bats-core/bats-exec-suite --dummy-flag" \
    "1002 1001 sleep 30"
  mk_cwds "1=/" "1000=$WT" "1001=/private/var/folders/bats-run-XXX/test/1" "1002=/private/var/folders/bats-run-XXX/test/1"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 0 ]
  [[ "$output" == BUSY* ]] || false
  [[ "$output" == *bats* ]]
}

@test "jobs: a job in SOMEBODY ELSE's worktree is never mine" {
  mk_beat stop "$$"
  mk_procs "1 0 /sbin/launchd" "8000 1 bash /other/scripts/ship-land.sh"
  mk_cwds "1=/" "8000=/other"
  run sbl "session_busy_live '$SID' '$WT'"
  [ "$status" -eq 1 ]
  [[ "$output" == IDLE-DEAF* ]]
}

# ════ BUSY-SUSPECT and the permission beacon ═════════════════════════════════════════════════════

@test "suspect: kind=prompt with a long-frozen transcript is BUSY-SUSPECT, not plain BUSY" {
  mk_beat prompt "$$"; mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  tp="$BATS_TEST_TMPDIR/t.jsonl"; : > "$tp"; touch -t 202601010000 "$tp"
  run sbl "session_busy_live '$SID' '$EMPTY' '$tp'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | awk '{print $1}')" = "BUSY" ]
  [ "$(echo "$output" | awk '{print $2}')" = "1" ]      # the suspect qualifier, not a fourth state
}

@test "suspect: a FRESH transcript on the same beat is plain BUSY" {
  mk_beat prompt "$$"; mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  tp="$BATS_TEST_TMPDIR/t.jsonl"; : > "$tp"
  run sbl "session_busy_live '$SID' '$EMPTY' '$tp'"
  [ "$(echo "$output" | awk '{print $2}')" = "0" ]
}

@test "suspect: a pending permission prompt is NAMED, which turns a suspicion into an instruction" {
  mk_beat prompt "$$"; mk_procs "1 0 /sbin/launchd"; mk_cwds "1=/"
  jq -nc --argjson ts "$(( $(date +%s) - 2888 ))" '{ts:$ts,tool_name:"Bash",cwd:"/x"}' > "$CC_PERMPEND_DIR/$SID.json"
  run sbl "session_busy_live '$SID' '$EMPTY'"
  [[ "$output" == *permission* ]]
}

# ════ THE LINE — one composer, two surfaces ══════════════════════════════════════════════════════

@test "line: the PUSH surface prints only news; the PULL surface always answers" {
  # Silence means opposite things on the two surfaces, and collapsing them is how a useful sensor
  # becomes wallpaper (push) or an unanswerable question (pull).
  run sbl "sb_render_line BUSY 0 12 beat 0 0 '🔧' 0 ''"
  [ "$status" -eq 1 ]; [ -z "$output" ]
  run sbl "sb_render_line BUSY 0 12 beat 0 0 '🔧' 1 ''"
  [ "$status" -eq 0 ]; [[ "$output" == *WORKING* ]]
}

@test "line: UNKNOWN is reported as an instrument gap, never as idle" {
  run sbl "sb_render_line UNKNOWN 0 0 error 0 0 '🔧' 1 ''"
  [[ "$output" == *UNKNOWN* ]] || false
  [[ "$output" == *"instrument gap"* ]] || false
  [[ "$output" != *"IDLE —"* ]]
}

@test "line: IDLE-DEAF at ✅ is NOT news — the certificate owns that close" {
  # Arm 3 excludes ✅ so this arm and hooks/operator-readout.sh's close certificate can never
  # contradict each other on the same turn.
  run sbl "sb_render_line IDLE-DEAF 0 0 none 0 0 '✅' 0 ''"
  [ "$status" -eq 1 ]; [ -z "$output" ]
  run sbl "sb_render_line IDLE-DEAF 0 0 none 0 0 '🔧' 0 ''"
  [ "$status" -eq 0 ]; [[ "$output" == *"no wake path armed"* ]]
}

@test "line: a WEDGED pane is news at EVERY rung, ✅ included" {
  run sbl "sb_render_line BUSY 1 2888 beat 1 2888 '✅' 0 'prompt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *WEDGED* ]] || false
  [[ "$output" == *"permission prompt"* ]]
}

# ── THE LEDGER FIELDS — reported, never a rung (D8 / A10 §6.2) ───────────────────────────────────

@test "ledger: --machine emits every busy field, beside LANDING" {
  run bash "$REPO/scripts/wrap-ledger.sh" --machine
  [ "$status" -eq 0 ]
  for k in BUSY BUSY_STATE BUSY_SRC BUSY_AGE BUSY_SUSPECT BUSY_SAMPLE PERMPEND PERMPEND_AGE; do
    echo "$output" | grep -qE "^$k=" || { echo "missing $k"; false; }
  done
}

@test "ledger: BUSY_STATE is always one of the five — never a manufactured state" {
  # The house rule (scripts/wrap-ledger.sh:756): any failure reports SRC=error, never an invented
  # answer. "IDLE" asserted by a blind instrument is the one output that actively misleads.
  run bash "$REPO/scripts/wrap-ledger.sh" --machine
  st="$(echo "$output" | grep -E '^BUSY_STATE=' | cut -d= -f2)"
  case "$st" in BUSY|IDLE-ARMED|IDLE-DEAF|GONE|UNKNOWN) ;; *) echo "bad state: $st"; false ;; esac
}

@test "ledger: busy-ness does NOT become a rung — the ladder is unchanged" {
  # A "working" rung would fire on every turn of every session forever. The rung ladder is MECE
  # against the disposition table and busy-ness is orthogonal to it.
  run bash "$REPO/scripts/wrap-ledger.sh" --machine
  r="$(echo "$output" | grep -E '^RUNG=' | cut -d= -f2)"
  case "$r" in ⛔|📤|🔧|📦|🚀|👤|✅|\?) ;; *) echo "rung polluted: $r"; false ;; esac
}

@test "ledger: --busy always answers on the PULL surface, and WRAP_BUSY=off is a kill switch" {
  run bash "$REPO/scripts/wrap-ledger.sh" --busy
  [ "$status" -eq 0 ]
  [[ "$output" == ⏳* ]] || false              # the operator ASKED — silence is not an answer here
  run bash -c "WRAP_BUSY=off '$REPO/scripts/wrap-ledger.sh' --machine | grep -E '^BUSY_SRC='"
  [[ "$output" == "BUSY_SRC=none" ]]
}
