#!/usr/bin/env bats
# handoff-fire.sh _it2_type_line — the TYPED FALLBACK, hardened and instrumented
# (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D2; the 2026-10-09 pane-44 strand).
#
# At load ~45/core the recycle watcher's 16 typed relaunch attempts all failed and the pane stranded
# at a bare shell. WHICH LEG failed is unknown: no attempt recorded anything. Two candidates survive
# the skeptics — kitty requests timing out at the 10 s bound and executing LATE, or a fast transport
# into a cold zsh whose echo arrived after the single read 0.5 s later — so the stub below models
# both, on a file-backed input line, and every case counts pastes and CRs: a fallback that "fails"
# after its line landed, or types it twice, is the defect.
#
# Controls replay the REAL artifact where a line is typed: the incident's own relaunch cmdfile
# (tests/fixtures/recycle-keystrokeless/handoff-recycle-cmd-44-*.sh), quotes and `$(cat …)` intact.

setup() {
  # M11 pins (tests/handoff-fire-capacity-gate.bats PIN-GUARD): this suite fires; the gate is not its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  # Non-$HOME seams the script reads: pinned to ABSENT paths inside the test dir, never /tmp or PATH.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # A fired pane carries these (bin/it2-kitty --env); a suite run from one must not inherit them.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON IT2_KITTY_TIMEOUT_S HANDOFF_SEND_TIMEOUT_S HF_TYPE_TELEMETRY HF_TYPE_TTY \
        FIRE_TYPE_ECHO_DEADLINE_S CC_TERM
  local f
  for f in _iso_now _under_test emit_recycle_event hf_bounded hf_bounded_s _hf_now_ms hf_load_per_core \
           _hf_type_emit _hf_wire_is_tail _hf_type_read _it2_type_line it2_type_verified; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
    declare -F "$f" >/dev/null || { echo "could not extract $f from $HF" >&2; return 1; }
  done
  eval "$(grep -E '^BP_(START|END)=' "$HF")"
  eval "$(grep -E '^FIRE_NOCORRECT_LINE=' "$HF")"
  eval "$(grep -E '^HF_SEND_TIMEOUT_S=' "$HF")"
  hf_pane_focused() { echo no; }
  # Unbounded by default: the stub returns 124 ITSELF where a case needs a bound expiry, so the verdict
  # never depends on how busy the box running the suite is.
  HF_TIMEOUT_BIN=""
  export HF_LOAD_PER_CORE=0 FIRE_TYPE_SETTLE=0.05 FIRE_TYPE_PRESETTLE=0 FIRE_TYPE_ATTEMPTS=3 FIRE_TYPE_READLINES=50

  export TERMDIR="$BATS_TEST_TMPDIR/term"; mkdir -p "$TERMDIR"; : > "$TERMDIR/line"
  IT2="$BATS_TEST_TMPDIR/it2"
  # A file-backed interactive shell. `line` is the input line; ^U clears it (unless ULOST: a scrub
  # that never arrived), CR submits it. Knobs: PASTE_RC / CR_RC (the rc the TRANSPORT reports — the
  # effect happens regardless, which is the measured late-landing shape), CR_CONSUME=0 (a CR that
  # really did not land), LATE_S (the text reaches the line that much later), END_ECHO=raw|caret (the
  # paste-end marker echoed literally after the text), TRAIL (something after the input).
  cat > "$IT2" <<'SH'
#!/usr/bin/env bash
S="$TERMDIR"
case "$1 $2" in
  "session send")
    t="${!#}"; printf 'send %q\n' "$t" >> "$S/calls"
    case "$t" in
      $'\x15') [ "${ULOST:-0}" = 1 ] || : > "$S/line"; exit 0 ;;
      $'\r')
        if [ "${CR_CONSUME:-1}" = 1 ]; then
          { cat "$S/line"; echo; } >> "$S/submitted"; : > "$S/line"; echo x >> "$S/crs"
        fi
        exit "${CR_RC:-0}" ;;
    esac
    echo x >> "$S/pastes"
    case "$t" in
      $'\e[200~'*) t="${t#$'\e[200~'}"; t="${t%$'\e[201~'}"
                   case "${END_ECHO:-}" in raw) t="$t"$'\e[201~' ;; caret) t="$t^[[201~" ;; esac ;;
    esac
    if [ -n "${LATE_S:-}" ]; then ( sleep "$LATE_S"; printf '%s' "$t" >> "$S/line" ) >/dev/null 2>&1 &
    else printf '%s' "$t" >> "$S/line"; fi
    exit "${PASTE_RC:-0}" ;;
  "session read")
    printf 'some earlier output\n$ %s%s\n' "$(cat "$S/line")" "${TRAIL:-}"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$IT2"
  # The command line only: the fixture may carry `#` header lines (shellcheck directive, provenance)
  # above the verbatim command, and a header is not part of what the incident typed.
  REAL_CMD="$(grep -v '^#' "$REPO"/tests/fixtures/recycle-keystrokeless/handoff-recycle-cmd-44-*.sh)"
  [ -n "$REAL_CMD" ] || { echo "incident fixture missing" >&2; return 1; }
}

n_of() { [ -f "$TERMDIR/$1" ] && wc -l < "$TERMDIR/$1" | tr -d ' ' || echo 0; }
submitted_has() { grep -qF -- "$1" "$TERMDIR/submitted" 2>/dev/null; }

@test "bound pin: HF_SEND_TIMEOUT_S exceeds the TWO kitty calls one send makes (default and raised)" {
  local inner
  inner="$(sed -n 's/^TIMEOUT_S="\${IT2_KITTY_TIMEOUT_S:-\([0-9]*\)}"$/\1/p' "$REPO/bin/it2-kitty")"
  [ -n "$inner" ] || { echo "bin/it2-kitty's inner bound line moved — re-pin"; false; }
  echo "send bound=$HF_SEND_TIMEOUT_S inner kitty bound=$inner"
  [ "$HF_SEND_TIMEOUT_S" -gt $(( 2 * inner )) ]
  # Derived, not hardcoded: raising the inner bound can never re-invert the pair.
  HF_SEND_TIMEOUT_S=""; IT2_KITTY_TIMEOUT_S=40 eval "$(grep -E '^HF_SEND_TIMEOUT_S=' "$HF")"
  [ "$HF_SEND_TIMEOUT_S" -gt 80 ] || { echo "raised: $HF_SEND_TIMEOUT_S"; false; }
}

@test "bound pin, measured on the call: every send and read runs under HF_SEND_TIMEOUT_S, not the 10s IPC bound" {
  local rec="$BATS_TEST_TMPDIR/bounds"
  HF_TIMEOUT_BIN="$BATS_TEST_TMPDIR/timeout-rec"
  printf '#!/usr/bin/env bash\necho "$3" >> %q\nshift 3\nexec "$@"\n' "$rec" > "$HF_TIMEOUT_BIN"
  chmod +x "$HF_TIMEOUT_BIN"
  HF_TIMEOUT_S=10 run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; false; }
  [ -s "$rec" ]
  [ "$(sort -u "$rec")" = "$HF_SEND_TIMEOUT_S" ] || { sort "$rec" | uniq -c; false; }
}

@test "a 124-but-DELIVERED paste is read, verified and submitted with exactly ONE CR (was: scrubbed unread)" {
  PASTE_RC=124 run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; false; }
  [ "$(n_of pastes)" = 1 ] || { echo "pastes=$(n_of pastes)"; cat "$TERMDIR/calls"; false; }
  [ "$(n_of crs)" = 1 ]
  submitted_has "$REAL_CMD"
}

@test "a 124 CR on a CONSUMED line is a submission — no retype, the command ran once" {
  CR_RC=124 run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; false; }
  [ "$(n_of pastes)" = 1 ] || { echo "RETYPED: pastes=$(n_of pastes)"; cat "$TERMDIR/calls"; false; }
  [ "$(grep -c . "$TERMDIR/submitted")" = 1 ]
}

@test "a 124 CR on a line that is STILL there is not called a submission" {
  CR_RC=124 CR_CONSUME=0 FIRE_TYPE_ATTEMPTS=2 run _it2_type_line "$IT2" 44 "claude --resume x"
  [ "$status" -eq 1 ] || { cat "$TERMDIR/calls"; false; }
  [ ! -s "$TERMDIR/submitted" ]
}

@test "a VISIBLE paste-end echo (raw ESC[201~ and caret ^[[201~) earns NO CR; the plain final attempt submits clean" {
  # zsh never renders a marker it consumed, so a visible one is bytes in the line buffer that a CR
  # would submit onto the last argument (lead ruling). Paste attempts refuse; plain mode carries none.
  local m
  for m in raw caret; do
    rm -f "$TERMDIR/crs" "$TERMDIR/pastes" "$TERMDIR/submitted"; : > "$TERMDIR/line"
    END_ECHO="$m" run _it2_type_line "$IT2" 44 "$REAL_CMD"
    [ "$status" -eq 0 ] || { echo "[$m]"; cat "$TERMDIR/calls"; false; }
    [ "$(n_of pastes)" = 3 ] || { echo "[$m] pastes=$(n_of pastes)"; false; }
    [ "$(n_of crs)" = 1 ] || { echo "[$m] crs=$(n_of crs)"; false; }
    ! grep -q '201~' "$TERMDIR/submitted" || { echo "[$m] a marker was submitted"; cat -v "$TERMDIR/submitted"; false; }
    submitted_has "$REAL_CMD"
  done
}

@test "residue of an earlier copy FUSED before the wire earns no CR (it would execute the two fused)" {
  # A late-landing earlier attempt's line sits on the input line, and the ^U meant to clear it never
  # arrived: the new wire lands right after it. The line ENDS with the wire, so a suffix check alone
  # would submit both.
  printf ': hfv-1-1-1; claude --resume x' > "$TERMDIR/line"
  ULOST=1 run _it2_type_line "$IT2" 44 "claude --resume x"
  [ "$status" -eq 1 ] || { cat "$TERMDIR/calls"; false; }
  [ "$(n_of crs)" = 0 ] || { echo "a CR was sent over a fused line"; cat "$TERMDIR/calls"; false; }
}

@test "text AFTER the wire earns no CR on an UNFOCUSED pane either — the line must END with the wire" {
  TRAIL="ab" FIRE_TYPE_ATTEMPTS=2 run _it2_type_line "$IT2" 44 "claude --resume x"
  [ "$status" -eq 1 ]
  [ "$(n_of crs)" = 0 ] || { cat "$TERMDIR/calls"; false; }
}

@test "telemetry: ONE line and ONE recycle-type-attempt row per attempt, naming every leg" {
  local tl="$BATS_TEST_TMPDIR/tele.log"
  # A receiver that never echoes: every attempt fails, and each must say so.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$IT2"
  HF_TYPE_TELEMETRY="$tl" run _it2_type_line "$IT2" 44 "claude --resume x"
  [ "$status" -eq 1 ]
  [ "$(grep -c 'type-attempt pane=44' "$tl")" = 3 ] || { cat "$tl"; false; }
  local k
  for k in send_rc= send_ms= read_rc= read_bytes= nonce_seen=0 suffix_ok=0 focused= load_per_core= verdict=echo-unverified; do
    [ "$(grep -c -- "$k" "$tl")" = 3 ] || { echo "missing $k"; cat "$tl"; false; }
  done
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ' "$tl" || { cat "$tl"; false; }
  [ "$(grep -c '"class":"recycle-type-attempt"' "$HOME/.claude/logs/handoffs.jsonl")" = 3 ]
}

@test "telemetry is OPT-IN: without HF_TYPE_TELEMETRY nothing is printed or written" {
  run _it2_type_line "$IT2" 44 "claude --resume x"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "printed: $output"; false; }
  [ ! -s "$HOME/.claude/logs/handoffs.jsonl" ]
}

@test "CONTROL fast transport + SLOW-TO-ECHO receiver (echo 0.8s after the paste) succeeds, one paste" {
  # Pre-fix: the single read FIRE_TYPE_SETTLE after the paste saw an empty line, scrubbed and retyped.
  # The echo deadline scales with load per core: 0.05 × (4 + 2 × 10) = 1.2 s here.
  local tl="$BATS_TEST_TMPDIR/tele.log"
  LATE_S=0.8 HF_LOAD_PER_CORE=10 HF_TYPE_TELEMETRY="$tl" run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; cat "$tl"; false; }
  [ "$(n_of pastes)" = 1 ] || { echo "pastes=$(n_of pastes)"; false; }
  [ "$(n_of crs)" = 1 ]
  grep -q 'echo_deadline_ms=1200' "$tl" || { cat "$tl"; false; }
  submitted_has "$REAL_CMD"
}

@test "CONTROL a transport that TIMES OUT but executes late succeeds without a second paste" {
  LATE_S=0.6 PASTE_RC=124 FIRE_TYPE_ECHO_DEADLINE_S=3 run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; false; }
  [ "$(n_of pastes)" = 1 ] || { echo "pastes=$(n_of pastes)"; cat "$TERMDIR/calls"; false; }
  [ "$(n_of crs)" = 1 ]
  submitted_has "$REAL_CMD"
}

@test "POSITIVE CONTROL a composer-like receiver (echoes at once, as /exit did at the same load) succeeds under the same always-124 stub" {
  # The transport reports 124 on EVERY send, as in the slowest pane-44 reading — and a receiver that
  # echoes immediately is still verified and submitted once. So the stub alone cannot fail a case.
  PASTE_RC=124 CR_RC=124 run it2_type_verified "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ] || { cat "$TERMDIR/calls"; false; }
  [ "$(n_of pastes)" = 2 ]          # the spell-correction disarm line, then the command
  [ "$(grep -c . "$TERMDIR/submitted")" = 2 ]
  submitted_has "$REAL_CMD"
}

@test "a foreground that is already claude stops the typing (HF_TYPE_TTY) — nothing typed into its composer" {
  pane_cc_state() { echo cc; }
  HF_TYPE_TTY=/dev/ttys013 run _it2_type_line "$IT2" 44 "$REAL_CMD"
  [ "$status" -eq 0 ]
  [ "$(n_of pastes)" = 0 ] || { cat "$TERMDIR/calls"; false; }
}

# ── THE WATCHER: a deadline, not two rounds ──────────────────────────────────────────────────────
# The detached __recycle watcher, fresh mode, driven to its typing block with the phase-aware ps shim
# of tests/handoff-recycle-remote-resume.bats pinned at `shell`, and an it2 that never echoes.
watcher_setup() {
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms" CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  mkdir -p "$HOME/.claude/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  WSHIM="$BATS_TEST_TMPDIR/wshim"; mkdir -p "$WSHIM"
  cat > "$WSHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in *pgid=*) printf '%s\n' "4242"; exit 0 ;; esac
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-o pid= -t"*)    printf '100\n' ;;
  *"-o tpgid= -t"*)  printf '100\n' ;;
  *"-o comm= -t"*)   printf -- '-zsh\n' ;;
  *pid=,ppid=*)      printf '100 1\n' ;;
  *"pid=,comm= -g"*) printf '100 /bin/zsh\n' ;;
  *"-p 100"*)        printf '/bin/zsh\n' ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WSHIM/osascript"
  chmod +x "$WSHIM/ps" "$WSHIM/osascript"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "TYPED-PANE", "tty": "/dev/ttys999"}]\n'
    else printf 'TYPED-PANE\n'; fi ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  WCMDF="$BATS_TEST_TMPDIR/relaunch.cmd"; printf '%s\n' "$REAL_CMD" > "$WCMDF"
  WTTY="$BATS_TEST_TMPDIR/ttys999"; : > "$WTTY"
}
drive_watcher() {
  run env HOME="$HOME" PATH="$WSHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" HF_LOAD_PER_CORE=0 \
      FIRE_TYPE_ATTEMPTS=2 FIRE_TYPE_SETTLE=0.01 FIRE_TYPE_PRESETTLE=0 \
      CC_RECYCLE_TYPE_DEADLINE_S="$1" \
      bash "$HF" __recycle TYPED-PANE "$WTTY" "$WCMDF" /tmp
}

@test "watcher: deadline 0 keeps the old two rounds, and every attempt leaves a telemetry line and row" {
  watcher_setup
  drive_watcher 0
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  # 2 rounds × (disarm line + launch line) × 2 attempts
  [ "$(printf '%s\n' "$output" | grep -c 'type-attempt pane=TYPED-PANE')" = 8 ] || { echo "$output"; false; }
  [ "$(grep -c '"class":"recycle-type-attempt"' "$HOME/.claude/logs/handoffs.jsonl")" = 8 ]
  grep '"class":"recycle-dead"' "$HOME/.claude/logs/handoffs.jsonl" | grep -q '2 typing rounds' \
    || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "watcher: a deadline keeps typing past two rounds while the pane sits at a bare shell" {
  watcher_setup
  # 30 s against rounds of a few seconds plus the 3 s gap: a third round needs only round 2 to END
  # before the deadline, which holds even with every fork slowed by a loaded box.
  drive_watcher 30
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  local rounds
  rounds="$(grep '"class":"recycle-dead"' "$HOME/.claude/logs/handoffs.jsonl" | sed -n 's/.*(\([0-9]*\) typing rounds.*/\1/p')"
  [ "${rounds:-0}" -ge 3 ] || { echo "rounds=$rounds"; echo "$output"; false; }
}
