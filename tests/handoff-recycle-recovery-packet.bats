#!/usr/bin/env bats
# handoff-fire.sh __recycle — a post-/exit recycle failure is impossible to miss
# (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D3; the 2026-10-09 pane-44 strand).
#
# Every terminal arm that leaves the work stranded writes a RECOVERY PACKET (recycle-failed/<sid>.json
# + .prompt.md) carrying the one exact re-fire command, paints a bare-shell pane, and settles the debt
# with --recovery; the never-confirmed arm (the original may be ALIVE) mails the session instead. Each
# arm REVOKES the staged successor before its verdict, and a claim that beat the revoke owns the pane.
#
# These cases drive the REAL watcher (bash "$HF" __recycle …) to each arm with the harness of
# tests/handoff-recycle-successor-claim.bats: a `ps` shim reads a claude on the pane while
# $HOME/pane-cc exists and a bare zsh otherwise, it2 times out on every send, and the "pane tty" is a
# regular file — so the paint is read back from it. Nothing touches a real pane, socket or ~/.claude.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM \
        RESUME_LAUNCHER RCY_TRANSPLANT_CAUSE CC_PANE_SUCCESSOR CC_PANE_SUCCESSOR_TTY CC_PANE_SUCCESSOR_NOW \
        HF_RCY_WATCHER_LOG CC_ROLES_DIR
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  REAL_LIB="$REPO/lib/pane-successor.sh"
  export CC_PANE_SUCCESSOR_LIB="$REAL_LIB"
  [ -f "$REAL_LIB" ] || { echo "lib missing: $REAL_LIB" >&2; return 1; }
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"
  export CC_RECYCLE_FAILED_DIR="$BATS_TEST_TMPDIR/recycle-failed"
  export HF_LOAD_PER_CORE=0.5
  OLD_SID=6defb493-e229-4318-b0ab-86e7167c39e3
  PKT="$CC_RECYCLE_FAILED_DIR/$OLD_SID.json"
  # THE ORIGINAL ARGV, handed over the way the foreground does it: NUL-separated, by file. The goal
  # carries spaces, a quote and a `$(…)` so a rendering that splits, fuses or expands is caught.
  BRIEF="$BATS_TEST_TMPDIR/brief with space.md"; printf 'continue the wave\n' > "$BRIEF"
  GOAL='the wave lands — proven by "make gate" printing $(green); do not push'
  export HF_RCY_ORIG_ARGV_FILE="$BATS_TEST_TMPDIR/orig.argv"
  printf '%s\0' --recycle --prompt-file "$BRIEF" --effort high --account auto --goal "$GOAL" \
    --recovery-of recycle-recovery:old:1 > "$HF_RCY_ORIG_ARGV_FILE"
  export HF_RCY_ORIG_SELF="$HF" HF_RCY_ORIG_PWD="$BATS_TEST_TMPDIR"
}

# ── THE WORLD ────────────────────────────────────────────────────────────────────────────────────
watcher_world() {
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms" CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  export CC_ADMIT_IDL="$HOME/.claude/autonomy/idl.jsonl"; : > "$CC_ADMIT_IDL"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOME/notify.log"\nexit 3\n' > "$CC_NOTIFY_BIN"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOME/debt.log"\nexit 0\n' > "$CC_RESUME_DEBT_BIN"
  chmod +x "$CC_NOTIFY_BIN" "$CC_RESUME_DEBT_BIN"
  WSHIM="$BATS_TEST_TMPDIR/wshim"; mkdir -p "$WSHIM"
  cat > "$WSHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
cc=0; [ -f "$HOME/pane-cc" ] && cc=1
case "$args" in *pgid=*) printf '4242\n'; exit 0 ;; esac
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-axww -o args="*) [ "$cc" = 1 ] && printf 'claude --permission-mode auto%s\n' "${PS_RESUME:+ --resume $PS_RESUME}"; exit 0 ;;
  *"-o pid= -t"*)     printf '100\n' ;;
  *"-o tpgid= -t"*)   printf '100\n' ;;
  *"-o comm= -t"*)    if [ "$cc" = 1 ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)       printf '100 1\n' ;;
  *"pid=,comm= -g"*)  printf '100 /bin/zsh\n' ;;
  *"-p 100"*)         if [ "$cc" = 1 ]; then printf 'claude\n'; else printf '/bin/zsh\n'; fi ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WSHIM/osascript"
  chmod +x "$WSHIM/ps" "$WSHIM/osascript"
  # `session list` names the pane for the first $HOME/gone-after listings (pane_proof's is the
  # first), then only a stranger — a deterministic "the pane is gone now". No file ⇒ always there.
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    n="$(cat "$HOME/list-n" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "$HOME/list-n"
    if [ -f "$HOME/gone-after" ] && [ "$n" -gt "$(cat "$HOME/gone-after")" ]; then
      printf '[{"id": "STRANGER", "tty": "/dev/ttys998"}]\n'
    else printf '[{"id": "SUCC-PANE", "tty": "/dev/ttys999"}, {"id": "STRANGER", "tty": "/dev/ttys998"}]\n'; fi
    exit 0 ;;
  "session send") exit 124 ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  WTTY="$BATS_TEST_TMPDIR/ttys999"; : > "$WTTY"
  WCMDF="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'cd /tmp && bash /tmp/lr-launch-succ.sh\n' > "$WCMDF"
  : > "$HOME/pane-cc"                                    # the predecessor is up when the watcher starts
}

# $1 = resume sid ($11) or empty. Positional order is the detach line's: SID tty cmdfile LAUNCH_DIR
# old_sid MARKER GOAL prompt RESUME_CFG source_sid T0 …
start_watcher() {
  WOUT="$BATS_TEST_TMPDIR/watcher.out"
  PATH="$WSHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
    HF_RECYCLE_SHELL_WAIT_S="${SHELL_WAIT:-60}" HF_RECYCLE_SHELL_POLL_S=3 CC_RECYCLE_CLAIM_GRACE_S="${GRACE:-20}" \
    CC_RECYCLE_TYPE_DEADLINE_S=0 FIRE_TYPE_ATTEMPTS=1 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0 \
    RCY_BOOT_WAIT_S=1 RCY_BOOT_STALE_S=2 RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2 \
    RCY_ENGAGE_TIMEOUT=2 HF_ENGAGE_PROC_HOLD_S=1 \
    bash "$HF" __recycle SUCC-PANE "$WTTY" "$WCMDF" /tmp "$OLD_SID" "" "$GOAL" "$BRIEF" \
      "${1:+$BATS_TEST_TMPDIR/cfg}" "${1:-}" "" > "$WOUT" 2>&1 3>&- &   # fd 3 closed: bats waits on it
  WPID=$!
}

stage_for_watcher() { # the producer's half, for the watcher's REAL pid + start time
  local wl m="$BATS_TEST_TMPDIR/meta.json" c="$BATS_TEST_TMPDIR/succ.cmd" i=0
  # After the heartbeat, as the foreground does (await_armed): the watcher's claim floor rcy_w_t0 is
  # set just before it, and a stage written earlier — easy under load, while bash is still parsing
  # this 18K-line script — reads as an older recycle's claim.
  until grep -q '^→ armed:' "$WOUT" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 300 ] || { echo "watcher never armed"; cat "$WOUT"; return 1; }
    sleep 0.1
  done
  sleep 1                                                # the stage's whole-second mtime lands at or after it
  wl="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$WPID" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$wl" ] || { echo "watcher $WPID has no lstart"; return 1; }
  printf 'true\n' > "$c"
  jq -n --arg tty "$WTTY" --arg wp "$WPID" --arg wl "$wl" --arg ce "$(date +%s)" \
     '{pane:"SUCC-PANE", pane_tty:$tty, pred_sid:"", watcher_pid:($wp|tonumber), watcher_lstart:$wl,
       created_epoch:($ce|tonumber), ttl_s:900, mode:"fresh", token:"t"}' > "$m"
  # shellcheck source=../lib/pane-successor.sh
  . "$REAL_LIB"
  cc_pane_successor_stage "$WTTY" "$c" "$m"
}

consumer_claims() { # the pane's own shell takes the stage (and does not run it: no claude appears)
  CC_PANE_SUCCESSOR_TTY=ttys999 bash -c '. "$1"; cc_pane_successor_take ttys999' _ "$REAL_LIB" >/dev/null
}

await_watcher() { # $1=seconds → 0 when the watcher exited inside the bound
  local i=0
  while kill -0 "$WPID" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le $(( ${1:-90} * 5 )) ] || { kill "$WPID" 2>/dev/null; cat "$WOUT"; return 1; }
    sleep 0.2
  done
}

# Every packet: valid JSON, the frozen field names U3 consumes, the class, and a usable refire_cmd.
assert_packet() { # $1=class
  [ -f "$PKT" ] || { echo "no packet at $PKT"; ls -la "$CC_RECYCLE_FAILED_DIR" 2>&1; cat "$WOUT"; return 1; }
  jq -e . "$PKT" >/dev/null || { cat "$PKT"; return 1; }
  jq -e --arg c "$1" '.class == $c' "$PKT" >/dev/null || { cat "$PKT"; return 1; }
  jq -e '[.failed_at, .class, .pane, .pane_tty, .cause, .brief, .goal, .account, .effort, .watcher_log, .token, .refire_cmd]
         | all(. != null)' "$PKT" >/dev/null || { cat "$PKT"; return 1; }
  jq -e --arg s "$OLD_SID" '.token | test("^recycle-recovery:" + $s + ":[0-9]+$")' "$PKT" >/dev/null || { cat "$PKT"; return 1; }
  jq -e '.pane == "SUCC-PANE" and .account == "auto" and .effort == "high"' "$PKT" >/dev/null || { cat "$PKT"; return 1; }
  [ "$(jq -r .brief "$PKT")" = "$BRIEF" ] || { cat "$PKT"; return 1; }
  [ "$(jq -r .goal "$PKT")" = "$GOAL" ] || { cat "$PKT"; return 1; }
  local tok; tok="$(jq -r .token "$PKT")"
  grep -qF -- "$tok" "${PKT%.json}.prompt.md" || { cat "${PKT%.json}.prompt.md"; return 1; }
  grep -qF -- "$(jq -r .refire_cmd "$PKT")" "${PKT%.json}.prompt.md" || { cat "${PKT%.json}.prompt.md"; return 1; }
}

settled_with_packet() { grep -q -- "settle --sid $OLD_SID --recovery $PKT" "$HOME/debt.log"; }

# ── THE ARMS ─────────────────────────────────────────────────────────────────────────────────────

@test "relaunch-write-failed (the pane-44 arm): packet, paint on the pane's tty, settle --recovery" {
  watcher_world
  start_watcher
  rm -f "$HOME/pane-cc"                                  # the predecessor exits; nothing is staged
  await_watcher 120
  assert_packet relaunch-write-failed
  grep -q 'HANDOFF RECYCLE FAILED (relaunch-write-failed)' "$WTTY" || { cat "$WTTY"; false; }
  # The one command for a BARE SHELL is the relaunch line; the banner names the packet that carries
  # the original session's refire_cmd (which needs a live claude to recycle).
  grep -qxF -- "$(cat "$WCMDF")" "$WTTY" || { cat "$WTTY"; false; }
  grep -qF -- "$PKT" "$WTTY" || { cat "$WTTY"; false; }
  settled_with_packet || { cat "$HOME/debt.log"; false; }
}

@test "refire_cmd is ONE parseable command carrying the original flags AS GIVEN, and only the NEW token" {
  watcher_world
  start_watcher
  rm -f "$HOME/pane-cc"
  await_watcher 120
  local cmd tok i; cmd="$(jq -r .refire_cmd "$PKT")"; tok="$(jq -r .token "$PKT")"
  bash -n -c "$cmd" || { echo "not parseable: $cmd"; false; }
  [[ "$cmd" == "cd "*" && "* ]] || { echo "$cmd"; false; }
  local -a a=(); eval "a=(${cmd#* && })"
  [ "${a[0]}" = "$HF" ]
  local flags=" ${a[*]:1} "
  [[ "$flags" == *" --recycle "* ]] || { echo "$cmd"; false; }
  for i in "${!a[@]}"; do
    case "${a[$i]}" in
      --prompt-file) [ "${a[$((i + 1))]}" = "$BRIEF" ] ;;
      --effort)      [ "${a[$((i + 1))]}" = high ] ;;
      --account)     [ "${a[$((i + 1))]}" = auto ] ;;             # AS GIVEN: auto stays auto
      --goal)        [ "${a[$((i + 1))]}" = "$GOAL" ] ;;
      --recovery-of) [ "${a[$((i + 1))]}" = "$tok" ] ;;
    esac
  done
  [ "$(printf '%s\n' "${a[@]}" | grep -cx -- --recovery-of)" = 1 ]   # the old token was replaced
  ! printf '%s\n' "${a[@]}" | grep -qx 'recycle-recovery:old:1' || false
}

@test "surface-gone: packet, settle --recovery — and NO paint (the tty may be a stranger's now)" {
  watcher_world
  echo 1 > "$HOME/gone-after"                             # only pane_proof's listing names the pane
  rm -f "$HOME/pane-cc"
  start_watcher
  await_watcher 60
  grep -q 'relaunch surface gone' "$WOUT" || { cat "$WOUT"; false; }
  assert_packet surface-gone
  [ ! -s "$WTTY" ] || { cat "$WTTY"; false; }
  settled_with_packet
}

@test "pane-vanished: packet and settle --recovery, no paint" {
  watcher_world
  echo 1 > "$HOME/gone-after"
  start_watcher                                          # claude stays up: the 15 s vanish probe decides
  await_watcher 90
  grep -q 'VANISHED' "$WOUT" || { cat "$WOUT"; false; }
  assert_packet pane-vanished
  [ ! -s "$WTTY" ]
  settled_with_packet
}

@test "boot-failed (a claimed successor that never booted): packet, the final arm's paint, settle --recovery" {
  watcher_world
  start_watcher
  stage_for_watcher
  rm -f "$HOME/pane-cc"
  consumer_claims                                        # claimed, but no claude ever appears
  await_watcher 90
  assert_packet boot-failed
  grep -q 'HANDOFF RECYCLE FAILED (boot-failed)' "$WTTY" || { cat "$WTTY"; false; }
  settled_with_packet
}

@test "never-engaged: packet (the successor booted but took no turn), no paint, discharge not settle" {
  watcher_world
  start_watcher
  stage_for_watcher
  rm -f "$HOME/pane-cc"; consumer_claims; : > "$HOME/pane-cc"   # a task-less claude is up
  await_watcher 90
  assert_packet never-engaged
  grep -q 'never took a turn' "${PKT%.json}.prompt.md"
  [ ! -s "$WTTY" ]
  ! grep -q '^settle' "$HOME/debt.log" || false
}

@test "never-held-resume (no-prompt relaunch): packet and settle --recovery" {
  watcher_world
  export HF_ENGAGE_BY_PROCESS=1
  start_watcher RESUMED-SID-1
  stage_for_watcher
  rm -f "$HOME/pane-cc"; consumer_claims; : > "$HOME/pane-cc"   # a claude WITHOUT --resume <sid>
  await_watcher 90
  grep -q 'never held a live' "$WOUT" || { cat "$WOUT"; false; }
  PKT="$CC_RECYCLE_FAILED_DIR/RESUMED-SID-1.json"
  jq -e '.class == "never-held-resume"' "$PKT" >/dev/null || { cat "$PKT" "$WOUT"; false; }
  grep -q -- "settle --sid RESUMED-SID-1 --recovery $PKT" "$HOME/debt.log"
}

@test "never-confirmed (the original may be ALIVE): NO packet, the sid is mailed, the attempt counted" {
  watcher_world
  SHELL_WAIT=3 start_watcher                             # claude never leaves the pane
  await_watcher 60
  [ ! -e "$PKT" ] || { cat "$PKT"; false; }
  [ ! -e "${PKT%.json}.prompt.md" ]
  grep -q -- "--from handoff-fire $OLD_SID HANDOFF-RECYCLE-NOT-CONFIRMED" "$HOME/notify.log" || { cat "$HOME/notify.log"; false; }
  [ "$(cat "$CC_RECYCLE_FAILED_DIR/$OLD_SID.never-confirmed")" = 1 ]
  # mailed ONCE: the alarm's own sid fallback is off at this arm
  [ "$(grep -c "^$OLD_SID \|^--from handoff-fire $OLD_SID" "$HOME/notify.log")" = 1 ] || { cat "$HOME/notify.log"; false; }
}

# ── REVOKE BEFORE ANY FAILURE VERDICT ────────────────────────────────────────────────────────────
# The consumer wins the race at the exact instant the arm revokes: the lib's revoke is wrapped so the
# claim lands first. The arm must then write no packet and settle nothing — the claimed successor owns
# the pane — and here it goes on to engage (a claude carrying --resume <sid>), so the run ends clean.
late_claim_lib() {
  export CC_PANE_SUCCESSOR_LIB="$BATS_TEST_TMPDIR/late-claim-lib.sh"
  {
    printf '. %q\n' "$REAL_LIB"
    # shellcheck disable=SC2016  # written for the watcher to expand
    printf '%s\n' 'cc_pane_successor_revoke() { local d k; d="$(cc_pane_successor_dir)"; k="${1##*/}"; mv "$d/$k.cmd" "$d/$k.claimed.99999" 2>/dev/null; mv "$d/$k.cmd" "$d/$k.revoked" 2>/dev/null; }'
  } > "$CC_PANE_SUCCESSOR_LIB"
}

@test "a claim that beats the pane-vanished arm's revoke: no packet, no settle, claimed-late row" {
  watcher_world
  late_claim_lib
  echo 1 > "$HOME/gone-after"
  export PS_RESUME=RESUMED-SID-2 HF_ENGAGE_BY_PROCESS=1
  start_watcher RESUMED-SID-2
  stage_for_watcher
  await_watcher 90
  grep -q 'CLAIMED before this failure arm could revoke' "$WOUT" || { cat "$WOUT"; false; }
  grep -q '"class":"recycle-successor-claimed-late"' "$HOME/.claude/logs/handoffs.jsonl"
  [ -z "$(ls "$CC_RECYCLE_FAILED_DIR" 2>/dev/null)" ] || { ls -la "$CC_RECYCLE_FAILED_DIR"; false; }
  ! grep -q '^settle' "$HOME/debt.log" 2>/dev/null || { cat "$HOME/debt.log"; false; }
}

@test "a claim that beats the never-confirmed arm's revoke: no mail, no settle — the claimed path owns it" {
  watcher_world
  late_claim_lib
  export PS_RESUME=RESUMED-SID-3 HF_ENGAGE_BY_PROCESS=1
  SHELL_WAIT=3 start_watcher RESUMED-SID-3
  stage_for_watcher
  await_watcher 60
  grep -q 'never-confirmed: the staged successor was CLAIMED' "$WOUT" || { cat "$WOUT"; false; }
  [ ! -e "$CC_RECYCLE_FAILED_DIR/RESUMED-SID-3.never-confirmed" ]
  [ ! -e "$CC_RECYCLE_FAILED_DIR/$OLD_SID.never-confirmed" ]
  [ -z "$(ls "$CC_RECYCLE_FAILED_DIR"/*.json 2>/dev/null)" ]
  ! grep -q '^settle' "$HOME/debt.log" 2>/dev/null || { cat "$HOME/debt.log"; false; }
}

@test "CONTROL: the same vanished arm with a revoke that WINS writes the packet (the late-claim test can fail)" {
  watcher_world
  echo 1 > "$HOME/gone-after"
  start_watcher
  stage_for_watcher
  await_watcher 90
  grep -q 'staged successor REVOKED before the failure verdict' "$WOUT" || { cat "$WOUT"; false; }
  [ -e "$CC_PANE_SUCCESSOR_DIR/ttys999.revoked" ]
  assert_packet pane-vanished
}

# ── --recovery-of: A RE-FIRE IS IDEMPOTENT ──────────────────────────────────────────────────────
recovery_world() {
  export HF_HANDOFFS_LOG="$HOME/.claude/logs/handoffs.jsonl"
  TOK="recycle-recovery:$OLD_SID:1791521000"
  mkdir -p "$CC_RECYCLE_FAILED_DIR"
  jq -n --arg t "$TOK" --arg tty "$BATS_TEST_TMPDIR/ttys-none" '{token:$t, pane_tty:$tty, class:"relaunch-write-failed"}' > "$PKT"
  # The gate alone, for the cases that PASS it: a full run past the gate would go on to recycle.
  GATE="$BATS_TEST_TMPDIR/gate.sh"
  { sed -n '/^hf_recovery_of_gate() {/,/^}/p' "$HF"
    # shellcheck disable=SC2016  # written for the extracted gate to expand
    printf '%s\n' 'pane_cc_state() { cat "$HOME/state"; }' 'emit_fire_refusal() { :; }'; } > "$GATE"
  grep -q '^hf_recovery_of_gate()' "$GATE" || { echo "gate not extractable"; return 1; }
  echo shell > "$HOME/state"
}
gate() { run bash -c 'set -euo pipefail; . "$1"; DRY=0 hf_recovery_of_gate "$2"' _ "$GATE" "$1"; }

@test "--recovery-of REFUSES (exit 2, named) once the token's recycle has recorded recycle-engaged" {
  recovery_world
  printf '{"ts":"2026-10-09T05:10:00Z","class":"recycle-engaged","engaged":true,"prev_sid":"%s","target_pane":"44"}\n' "$OLD_SID" > "$HF_HANDOFFS_LOG"
  run bash "$HF" --recycle --recovery-of "$TOK" --prompt-file "$BRIEF" --dry-run
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"--recovery-of $TOK REFUSED"*"ENGAGED"* ]] || { echo "$output"; false; }
  [ "$(jq -r '.refired_at // "none"' "$PKT")" = none ]
}

@test "--recovery-of: an engaged row from BEFORE the failure, or a stranger's, does not refuse — and the packet is stamped" {
  recovery_world
  { printf '{"ts":"2026-10-09T04:00:00Z","class":"recycle-engaged","engaged":true,"prev_sid":"%s"}\n' "$OLD_SID"
    printf '{"ts":"2026-10-09T06:00:00Z","class":"recycle-engaged","engaged":true,"prev_sid":"someone-else"}\n'; } > "$HF_HANDOFFS_LOG"
  gate "$TOK"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--recovery-of $TOK: not engaged since"* ]] || { echo "$output"; false; }
  jq -e '.refired_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$PKT" >/dev/null || { cat "$PKT"; false; }
  # …and the same gate, handed the row AFTER the failure, refuses: the two cases differ only in time.
  printf '{"ts":"2026-10-09T05:10:00Z","class":"recycle-engaged","engaged":true,"prev_sid":"%s"}\n' "$OLD_SID" >> "$HF_HANDOFFS_LOG"
  gate "$TOK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

@test "--recovery-of REFUSES when a live claude holds the packet's pane; a malformed token is refused too" {
  recovery_world
  echo cc > "$HOME/state"
  gate "$TOK"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"live claude holds"* ]] || { echo "$output"; false; }
  [ "$(jq -r '.refired_at // "none"' "$PKT")" = none ]
  gate not-a-token
  [ "$status" -eq 2 ]
  gate "recycle-recovery:$OLD_SID:notanumber"
  [ "$status" -eq 2 ]
}

@test "--recovery-of without --recycle is refused (exit 2)" {
  run bash "$HF" --recovery-of "recycle-recovery:x:1" --prompt-file "$BRIEF" --dry-run
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"--recovery-of is a --recycle flag"* ]] || { echo "$output"; false; }
}

# ── THE STAGED .cmd ON THE REAL INCIDENT LAUNCH LINE ────────────────────────────────────────────
@test "REAL FIXTURE: the pane-44 relaunch line, staged, exports the launcher's CLAUDE_CONFIG_DIR BEFORE the launch line" {
  local f fx line_cfg line_cmd
  for f in _iso_now _under_test emit_recycle_event hf_load_per_core hf_succ_lib_load hf_succ_mode hf_succ_stage; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
    declare -F "$f" >/dev/null || { echo "could not extract $f"; false; }
  done
  TARGET_CFG="$BATS_TEST_TMPDIR/home/.claude-next"
  config_dir_for_launcher() { [ "$1" = claude ] && echo "$TARGET_CFG"; }
  fx="$(ls "$REPO"/tests/fixtures/recycle-keystrokeless/handoff-recycle-cmd-44-*.sh)"
  CMD="$(tail -n +3 "$fx")"                                # the fixture, minus its two leading # lines
  [[ "$CMD" == *'claude --effort high'* ]] || false        # the incident's shape: a launch line…
  [[ "$CMD" != *CLAUDE_CONFIG_DIR* ]] || false              # …that names no config dir of its own
  # shellcheck disable=SC2034  # read by the extracted hf_succ_stage, not by this test's own lines
  LAUNCHER=claude SID=44 WATCHER_PID=$$ rcy_old_sid=$OLD_SID
  BASE="$BATS_TEST_TMPDIR/handoff-recycle-cmd-44.sh"; printf '%s\n' "$CMD" > "$BASE"
  run hf_succ_stage /dev/ttys044 "$BASE"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local c="$CC_PANE_SUCCESSOR_DIR/ttys044.cmd"
  line_cfg="$(grep -nx "export CLAUDE_CONFIG_DIR=$TARGET_CFG" "$c" | cut -d: -f1)"
  line_cmd="$(grep -nF -- "$CMD" "$c" | cut -d: -f1)"
  [ -n "$line_cfg" ] || { cat "$c"; false; }
  [ -n "$line_cmd" ] || { cat "$c"; false; }
  [ "$line_cfg" -lt "$line_cmd" ] || { cat "$c"; false; }
  bash -n "$c"
  # A consumer that UNSET the predecessor's CLAUDE_CONFIG_DIR still lands on the target account.
  run env -u CLAUDE_CONFIG_DIR bash -c 'eval "$(grep "^export " "$1")"; printf "%s" "$CLAUDE_CONFIG_DIR"' _ "$c"
  [ "$output" = "$TARGET_CFG" ]
}

@test "HF_WATCHER_IT2 routes the watcher's own transport (the live proof's forced-failure seam)" {
  watcher_world
  cp "$HOME/.claude/bin/it2" "$HOME/alt-it2"
  sed -i.bak 's|it2-calls.log|alt-it2-calls.log|' "$HOME/alt-it2"
  HF_WATCHER_IT2="$HOME/alt-it2" start_watcher
  rm -f "$HOME/pane-cc"
  await_watcher 120
  grep -q '^session send' "$HOME/alt-it2-calls.log" || { cat "$HOME/alt-it2-calls.log"; false; }
  ! grep -q '^session send' "$HOME/it2-calls.log" 2>/dev/null || { cat "$HOME/it2-calls.log"; false; }
  assert_packet relaunch-write-failed
}
