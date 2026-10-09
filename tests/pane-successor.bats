#!/usr/bin/env bats
# lib/pane-successor.sh — keystroke-free successor delivery (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md
# §D1), and its two consumers: lr-fire-resume.sh's fall-through and bin/cc-close-attrib.
#
# Hermetic: a sandboxed HOME and staging dir, the caller's tty pinned through CC_PANE_SUCCESSOR_TTY
# (or a real pty from script(1) where the TTY ITSELF is the subject), and a fake $SHELL that records
# its argv and env instead of starting a login shell. The "watcher" whose liveness take proves is this
# test's own bats process, read with the same ps call the lib uses.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/lib/pane-successor.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # The lr-fire-resume and cc-close-attrib cases reach scripts/lib/capacity-admit.sh, whose gate reads
  # live load, memory and the session census; the gate is not this suite's subject.
  export CC_ADMIT_GATE=off
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/ps"
  export CC_PANE_SUCCESSOR_TTY=/dev/ttys913
  unset CC_PANE_SUCCESSOR CC_PANE_SUCCESSOR_NOW CC_PANE_SUCCESSOR_LOOP_PID CC_PANE_SUCCESSOR_HANDBACK
  # The pane-identity check reads KITTY_WINDOW_ID; a suite run from a kitty pane would inherit its own.
  unset KITTY_WINDOW_ID
  W_PID=$$
  W_LSTART="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$W_PID" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  CMD="$BATS_TEST_TMPDIR/succ.cmd"
  META="$BATS_TEST_TMPDIR/meta.json"
  MARK="$BATS_TEST_TMPDIR/marker"
  export FAKESH_LOG="$BATS_TEST_TMPDIR/fakesh.log"
  FAKESH="$BATS_TEST_TMPDIR/fakesh"
  # Records argv + the inherited CLAUDE_CONFIG_DIR, then runs a `-c` program the way zsh would
  # ($0 = the word after it, $1 = the claimed path); a bare `-l -i` (the trailing shell) just exits.
  cat > "$FAKESH" <<'EOF'
#!/bin/bash
{ printf 'argv:'; printf ' [%s]' "$@"; printf '\n'; printf 'CCD=%s\n' "${CLAUDE_CONFIG_DIR-<unset>}"
  printf 'LOOP=%s\n' "${CC_PANE_SUCCESSOR_LOOP_PID-<unset>}"; } >> "$FAKESH_LOG"
if [ "${3:-}" = -c ]; then shift 3; exec /bin/bash -c "$@"; fi
exit 0
EOF
  chmod +x "$FAKESH"
  printf 'printf "ran CCD=%%s\\n" "${CLAUDE_CONFIG_DIR-<unset>}" > %q\n' "$MARK" > "$CMD"
  mk_meta
}

mk_meta() { # [tty] [watcher_pid] [lstart] [created_epoch] [ttl_s]
  printf '{"pane":"44","pane_tty":"%s","pred_sid":"s-1","watcher_pid":%s,"watcher_lstart":"%s","created_epoch":%s,"ttl_s":%s,"mode":"fresh","token":"tok"}\n' \
    "${1:-/dev/ttys913}" "${2:-$W_PID}" "${3:-$W_LSTART}" "${4:-$(date +%s)}" "${5:-120}" > "$META"
}

# shellcheck source=lib/pane-successor.sh
stage() { . "$LIB"; cc_pane_successor_stage "${1:-ttys913}" "$CMD" "$META"; }

# Every refusal must be SILENT as well as rc 1: a consumer treats any output as a claim path.
assert_refused() {
  # shellcheck source=lib/pane-successor.sh
  . "$LIB"
  run cc_pane_successor_take
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ -f "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" ]
}

@test "stage → take prints the claim, the .cmd is gone, .claimed.<pid> exists, revoke then fails" {
  stage
  [ "$(stat -f '%Lp' "$CC_PANE_SUCCESSOR_DIR")" = 700 ]
  run cc_pane_successor_take
  [ "$status" -eq 0 ]
  case "$output" in "$CC_PANE_SUCCESSOR_DIR"/ttys913.claimed.[0-9]*) ;; *) false ;; esac
  [ -f "$output" ]
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" ]
  claim="$output"
  run cc_pane_successor_revoke ttys913
  [ "$status" -ne 0 ]
  run cc_pane_successor_claimed ttys913
  [ "$status" -eq 0 ]
  [ "${output%% *}" = "$claim" ]
  case "${output##* }" in ''|*[!0-9]*) false ;; esac
}

@test "revoke before take wins: take then finds nothing, claimed reports nothing" {
  stage
  run cc_pane_successor_revoke ttys913
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_SUCCESSOR_DIR/ttys913.revoked" ]
  run cc_pane_successor_take
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run cc_pane_successor_claimed ttys913
  [ "$status" -eq 1 ]
}

@test "a new stage clears the previous recycle's claim and revoke" {
  stage; cc_pane_successor_take >/dev/null
  stage; cc_pane_successor_revoke ttys913
  stage
  [ -z "$(find "$CC_PANE_SUCCESSOR_DIR" -name 'ttys913.claimed.*')" ]
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys913.revoked" ]
}

@test "refuses: dead watcher pid" {
  sleep 30 & dead=$!
  kill "$dead"; wait "$dead" 2>/dev/null || true
  mk_meta "" "$dead"
  stage
  assert_refused
}

@test "refuses: watcher pid alive but lstart differs (pid reuse)" {
  mk_meta "" "" "Thu Jan  1 00:00:00 1970"
  stage
  assert_refused
}

@test "refuses: TTL expired" {
  mk_meta "" "" "" "$(( $(date +%s) - 200 ))" 120
  stage
  assert_refused
  # and the boundary is exclusive: now == created + ttl is expired
  mk_meta "" "" "" 1000 60
  stage
  CC_PANE_SUCCESSOR_NOW=1060 assert_refused
  CC_PANE_SUCCESSOR_NOW=1059 run cc_pane_successor_take
  [ "$status" -eq 0 ]
}

@test "refuses: caller's tty is not the pane's (an expect inner pty)" {
  stage
  CC_PANE_SUCCESSOR_TTY=/dev/ttys777 assert_refused
  # and asking for the pane's key explicitly from the wrong tty does not help
  CC_PANE_SUCCESSOR_TTY=/dev/ttys777 run cc_pane_successor_take ttys913
  [ "$status" -eq 1 ]
}

@test "refuses: a real pty from script(1) that is not the staged pane's tty" {
  stage
  unset CC_PANE_SUCCESSOR_TTY
  run script -q /dev/null /bin/bash -c '. "$1"; cc_pane_successor_take; echo "rc=$?"' _ "$LIB"
  [[ "$output" == *rc=1* ]] || false
  [[ "$output" != *claimed* ]] || false
  [ -f "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" ]
}

@test "refuses: no tty at all (stdin not a terminal, no seam)" {
  stage
  unset CC_PANE_SUCCESSOR_TTY
  run bash -c '. "$1"; cc_pane_successor_take' _ "$LIB" </dev/null
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "refuses: world-writable .cmd" {
  stage
  chmod 606 "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd"
  assert_refused
}

@test "refuses: group-writable .cmd" {
  stage
  chmod 620 "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd"
  assert_refused
}

@test "refuses: group-writable staging dir" {
  stage
  chmod 770 "$CC_PANE_SUCCESSOR_DIR"
  assert_refused
}

@test "refuses: missing meta" {
  stage
  rm -f "$CC_PANE_SUCCESSOR_DIR/ttys913.json"
  assert_refused
}

@test "refuses: garbled meta, and meta missing a field" {
  stage
  printf '{"pane_tty":"/dev/ttys913", not json' > "$CC_PANE_SUCCESSOR_DIR/ttys913.json"
  assert_refused
  printf '{"pane_tty":"/dev/ttys913","watcher_pid":%s,"created_epoch":%s,"ttl_s":60}\n' \
    "$W_PID" "$(date +%s)" > "$CC_PANE_SUCCESSOR_DIR/ttys913.json"
  assert_refused
  printf '{"pane_tty":"/dev/ttys913","watcher_pid":"12x","watcher_lstart":"%s","created_epoch":%s,"ttl_s":60}\n' \
    "$W_LSTART" "$(date +%s)" > "$CC_PANE_SUCCESSOR_DIR/ttys913.json"
  assert_refused
}

@test "refuses: jq absent" {
  stage
  nojq="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$nojq"
  for b in ps tr sed date stat id mv touch find head cat; do
    ln -s "$(command -v "$b")" "$nojq/$b"
  done
  PATH="$nojq" assert_refused
}

@test "refuses: CC_PANE_SUCCESSOR=off" {
  stage
  CC_PANE_SUCCESSOR=off assert_refused
}

@test "race: 50 take-vs-revoke rounds on fresh stages, exactly one winner each" {
  # shellcheck source=lib/pane-successor.sh
  . "$LIB"
  local t r both=0 none=0
  for _ in $(seq 1 50); do
    stage
    rm -f "$BATS_TEST_TMPDIR/t.rc"
    # errexit is on in a bats body, so each rc is captured with && || rather than $?
    ( if cc_pane_successor_take >/dev/null; then echo 0; else echo 1; fi > "$BATS_TEST_TMPDIR/t.rc" ) &
    if cc_pane_successor_revoke ttys913; then r=0; else r=1; fi
    wait
    t="$(cat "$BATS_TEST_TMPDIR/t.rc")"
    if [ "$t" -eq 0 ] && [ "$r" -eq 0 ]; then both=$((both + 1)); fi
    if [ "$t" -ne 0 ] && [ "$r" -ne 0 ]; then none=$((none + 1)); fi
  done
  echo "both=$both none=$none"
  [ "$both" -eq 0 ]
  [ "$none" -eq 0 ]
}

@test "exec (trailing shell): predecessor CLAUDE_CONFIG_DIR does not leak; argv is -l -i -c … cc-successor <claim>" {
  stage
  claim="$(cc_pane_successor_take)"
  run env CLAUDE_CONFIG_DIR=/pred CC_ACCOUNT_PINNED=1 SHELL="$FAKESH" /bin/bash -c '. "$1"; cc_pane_successor_exec "$2" 1' _ "$LIB" "$claim"
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "ran CCD=<unset>" ]
  grep -q '^argv: \[-l\] \[-i\] \[-c\] \[' "$FAKESH_LOG"
  # shellcheck disable=SC2016
  grep -qxF 'exec "${SHELL:-/bin/zsh}" -l -i] [cc-successor] ['"$claim"'] ['"$CC_PANE_SUCCESSOR_DIR"'/ttys913.handback]' "$FAKESH_LOG"
  grep -qxF 'argv: [-l] [-i]' "$FAKESH_LOG"
  ! grep -q '^CCD=/pred' "$FAKESH_LOG" || false
  # the trailing login shell keeps the loop's pid but must not advertise the loop: it is gone
  [ "$(grep '^LOOP=' "$FAKESH_LOG" | tail -1)" = 'LOOP=<unset>' ]
}

@test "exec (0 flag): no trailing shell, and a cmd that sets CLAUDE_CONFIG_DIR keeps its own" {
  { printf 'export CLAUDE_CONFIG_DIR=/target\n'; cat "$CMD"; } > "$CMD.2"; mv "$CMD.2" "$CMD"
  stage
  claim="$(cc_pane_successor_take)"
  run env CLAUDE_CONFIG_DIR=/pred SHELL="$FAKESH" /bin/bash -c '. "$1"; cc_pane_successor_exec "$2" 0' _ "$LIB" "$claim"
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "ran CCD=/target" ]
  [ "$(grep -c '^argv:' "$FAKESH_LOG")" -eq 1 ]
  grep -qF "] [cc-successor] [$claim] [$CC_PANE_SUCCESSOR_DIR/ttys913.handback]" "$FAKESH_LOG"
  # shellcheck disable=SC2016  # a literal: the trailing-shell line must be absent from the program
  [ "$(grep -cF 'exec "${SHELL' "$FAKESH_LOG")" -eq 0 ]
}

@test "real artifact: the 2026-10-09 pane-44 relaunch cmdfile is claimed byte-identical, plus only its nonce line" {
  fx="$(ls "$REPO"/tests/fixtures/recycle-keystrokeless/handoff-recycle-cmd-44-*.sh)"
  { printf 'export CLAUDE_CONFIG_DIR=%q\n' "$HOME/.claude-next"; cat "$fx"; } > "$CMD"
  stage
  nonce="$(jq -r .nonce "$CC_PANE_SUCCESSOR_DIR/ttys913.json")"
  claim="$(cc_pane_successor_take)"
  sed '$d' "$claim" | cmp - "$CMD"
  [ "$(tail -n 1 "$claim")" = "# cc-pane-successor-nonce: $nonce" ]
}

@test "nonce: a stale .cmd from an earlier stage (another nonce) is refused under the new meta" {
  stage
  cp "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" "$BATS_TEST_TMPDIR/stale.cmd"
  stage                                   # the next recycle: a new meta, a new nonce
  cp "$BATS_TEST_TMPDIR/stale.cmd" "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd"
  assert_refused
  # and a .cmd that carries no nonce line at all
  cp "$CMD" "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd"
  assert_refused
}

@test "nonce: stage removes the old .cmd FIRST — a stage that dies between its renames leaves nothing takeable" {
  stage
  # The next stage writes its meta, then cannot write its .cmd (its temp path is a directory).
  mkdir "$CC_PANE_SUCCESSOR_DIR/.ttys913.cmd.tmp.$$"
  run cc_pane_successor_stage ttys913 "$CMD" "$META"
  [ "$status" -ne 0 ]
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" ]
  run cc_pane_successor_take
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "pane identity: KITTY_WINDOW_ID ≠ meta.pane is refused; equal, or unknown on either side, takes" {
  stage
  KITTY_WINDOW_ID=45 assert_refused
  KITTY_WINDOW_ID=44 run cc_pane_successor_take
  [ "$status" -eq 0 ]
  stage
  run cc_pane_successor_take                    # no KITTY_WINDOW_ID (iTerm, a bare terminal)
  [ "$status" -eq 0 ]
  jq '.pane = "w-abc"' "$META" > "$META.2"; mv "$META.2" "$META"
  stage
  KITTY_WINDOW_ID=45 run cc_pane_successor_take  # non-numeric meta.pane: the tty decides
  [ "$status" -eq 0 ]
  jq 'del(.pane)' "$META" > "$META.2"; mv "$META.2" "$META"
  stage
  KITTY_WINDOW_ID=45 run cc_pane_successor_take  # no meta.pane at all
  [ "$status" -eq 0 ]
}

@test "handback: refused when the advertised loop is not an ancestor (an inherited env, not a parent)" {
  stage
  claim="$(cc_pane_successor_take)"
  sleep 30 & other=$!
  # shellcheck disable=SC2016  # $1 and $2 are the inner bash's
  run env CC_PANE_SUCCESSOR_LOOP_PID="$other" CC_PANE_SUCCESSOR_HANDBACK="$CC_PANE_SUCCESSOR_DIR/ttys913.handback.$other" \
    /bin/bash -c '. "$1"; cc_pane_successor_handback "$2"' _ "$LIB" "$claim"
  kill "$other" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys913.handback.$other" ]
  # a hand-back path outside the staging dir is refused before any ancestry read
  # shellcheck disable=SC2016  # as above
  run env CC_PANE_SUCCESSOR_LOOP_PID="$$" CC_PANE_SUCCESSOR_HANDBACK="$BATS_TEST_TMPDIR/x.handback.$$" \
    /bin/bash -c '. "$1"; cc_pane_successor_handback "$2"' _ "$LIB" "$claim"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/x.handback.$$" ]
}

@test "bash 3.2 and zsh: the lib stages, takes and revokes under both" {
  for sh in /bin/bash zsh; do
    command -v "$sh" >/dev/null || continue
    rm -rf "$CC_PANE_SUCCESSOR_DIR"
    run "$sh" -c '. "$1"; cc_pane_successor_stage ttys913 "$2" "$3" || exit 9; c="$(cc_pane_successor_take)" || exit 8
                  [ -f "$c" ] || exit 7; cc_pane_successor_revoke ttys913 && exit 6; cc_pane_successor_claimed ttys913 >/dev/null || exit 5' \
      _ "$LIB" "$CMD" "$META"
    echo "$sh → $status $output"
    [ "$status" -eq 0 ]
  done
  [[ "$(/bin/bash -c 'echo $BASH_VERSION')" == 3.2* ]]
}

# ── lr-fire-resume.sh: the fall-through tail, extracted between its markers and run from a sandbox
#    tree laid out like the checkout (scripts/limit-recover/ + lib/), reached through a symlink so the
#    lib is found by the same symlink resolution the real script uses. ─────────────────────────────
mk_lr_tail() {
  local t="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$t/scripts/limit-recover" "$t/lib" "$t/bin"
  ln -sf "$LIB" "$t/lib/pane-successor.sh"
  { printf '#!/bin/bash\nset -euo pipefail\nlr_rc=0\n'
    sed -n '/^# >>> lr-successor$/,/^# <<< lr-successor$/p' "$REPO/scripts/limit-recover/lr-fire-resume.sh"
    printf 'echo FELL-THROUGH\n'
  } > "$t/scripts/limit-recover/lr-tail.sh"
  grep -q 'cc_pane_successor_take' "$t/scripts/limit-recover/lr-tail.sh"   # extraction sanity
  chmod +x "$t/scripts/limit-recover/lr-tail.sh"
  ln -sf "$t/scripts/limit-recover/lr-tail.sh" "$t/bin/lr-fire-resume"
  LR_TAIL="$t/bin/lr-fire-resume"
}

@test "lr-fire-resume fall-through: a staged successor runs (marker written), CLAUDE_CONFIG_DIR does not leak" {
  mk_lr_tail
  stage
  run env CLAUDE_CONFIG_DIR=/pred SHELL="$FAKESH" "$LR_TAIL"
  [ "$status" -eq 0 ]
  [ "$(cat "$MARK")" = "ran CCD=<unset>" ]
  [[ "$output" == *"running the staged successor $CC_PANE_SUCCESSOR_DIR/ttys913.claimed."* ]] || false
  [[ "$output" != *FELL-THROUGH* ]] || false
  grep -qxF 'argv: [-l] [-i]' "$FAKESH_LOG"   # the trailing shell keeps the pane
}

@test "lr-fire-resume fall-through: no stage (or a refused take) reaches the ordinary shell path" {
  mk_lr_tail
  run env SHELL="$FAKESH" "$LR_TAIL"
  [ "$status" -eq 0 ]
  [[ "$output" == *FELL-THROUGH* ]] || false
  [ ! -e "$MARK" ]
  stage
  run env CC_PANE_SUCCESSOR_TTY=/dev/ttys777 SHELL="$FAKESH" "$LR_TAIL"
  [[ "$output" == *FELL-THROUGH* ]] || false
  [ -f "$CC_PANE_SUCCESSOR_DIR/ttys913.cmd" ]
}

# ── bin/cc-close-attrib: stdin must be a REAL tty here (the wrapper tests -t 0), so these run under
#    script(1). The stage is made from inside that pty with its own `tty`, so no seam stands in for
#    the match being tested. ─────────────────────────────────────────────────────────────────────────
mk_cca() {
  STUB="$BATS_TEST_TMPDIR/claude-stub"
  printf '#!/bin/bash\n[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }\nexit 0\n' > "$STUB"
  chmod +x "$STUB"
  export CC_CLOSE_RECORDS_DIR="$BATS_TEST_TMPDIR/close-records"
  export CC_LAUNCH_WATCHDOG=off
  unset CC_PANE_SUCCESSOR_TTY
  DRIVER="$BATS_TEST_TMPDIR/driver.sh"
  # $1=lib $2=cmd $3=meta-template $4=wrapper $5=stub $6=pane tty to stage ('' = this pty)
  cat > "$DRIVER" <<'EOF'
#!/bin/bash
. "$1"
me="$(tty)"; pane="${6:-$me}"
sed "s#@TTY@#$pane#" "$3" > "$3.json"
cc_pane_successor_stage "$pane" "$2" "$3.json" || { echo STAGE-FAILED; exit 1; }
"$4" "$5"; echo "wrapper-rc=$?"
[ -e "$(cc_pane_successor_dir)/${pane##*/}.cmd" ] && echo STILL-STAGED
EOF
  chmod +x "$DRIVER"
  mk_meta "@TTY@"
}

@test "cc-close-attrib: on the pane's own tty it claims, records the claim, and runs the successor with no trailing shell" {
  mk_cca
  run env CLAUDE_CONFIG_DIR=/pred SHELL="$FAKESH" script -q /dev/null "$DRIVER" "$LIB" "$CMD" "$META" "$REPO/bin/cc-close-attrib" "$STUB" ""
  echo "$output"
  [ "$(cat "$MARK")" = "ran CCD=<unset>" ]
  [[ "$output" == *wrapper-rc=0* ]] || false
  [[ "$output" != *STILL-STAGED* ]] || false
  [ "$(grep -c '^argv:' "$FAKESH_LOG")" -eq 1 ]
  # shellcheck disable=SC2012  # newest close record by mtime; the names are this suite's own
  rec="$(ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json | head -1)"
  grep -q '"successor_claim":"[^"]*/ttys[0-9]*\.claimed\.[0-9]*"' "$rec"
  grep -q '"record_state":"closed"' "$rec"
}

@test "cc-close-attrib: inside an expect inner pty (stage names the OUTER pane tty) it refuses and leaves the stage" {
  mk_cca
  run env SHELL="$FAKESH" script -q /dev/null "$DRIVER" "$LIB" "$CMD" "$META" "$REPO/bin/cc-close-attrib" "$STUB" /dev/ttys913
  echo "$output"
  [[ "$output" == *wrapper-rc=0* ]] || false
  [[ "$output" == *STILL-STAGED* ]] || false
  [ ! -e "$MARK" ]
  # shellcheck disable=SC2012  # newest close record by mtime; the names are this suite's own
  rec="$(ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json | head -1)"
  grep -q '"successor_claim":""' "$rec"
}

@test "cc-close-attrib: a non-interactive launch (-p) never takes, even on the pane's own tty" {
  mk_cca
  sed -i '' 's#"\$4" "\$5"#"$4" "$5" -p hi#' "$DRIVER"
  run env SHELL="$FAKESH" script -q /dev/null "$DRIVER" "$LIB" "$CMD" "$META" "$REPO/bin/cc-close-attrib" "$STUB" ""
  echo "$output"
  [[ "$output" == *STILL-STAGED* ]] || false
  [ ! -e "$MARK" ]
}

@test "cc-close-attrib: three successor generations keep a constant ancestry depth (one loop shell, no nesting)" {
  mk_cca
  # A stub claude that, like a recycling session, stages its own successor (the wrapper again, on this
  # stub) while it runs, and records how many hops separate it from the driver. Generation 1 is the
  # driver's launch; 2, 3 and 4 are successors. Its tty comes from ps: the wrapper backgrounds it.
  export GEN_FILE="$BATS_TEST_TMPDIR/gen" DEPTH_LOG="$BATS_TEST_TMPDIR/depth" LIB META_T="$META" \
         CCA="$REPO/bin/cc-close-attrib" NEXT_CMD="$BATS_TEST_TMPDIR/next.cmd"
  GSTUB="$BATS_TEST_TMPDIR/gen-stub"
  cat > "$GSTUB" <<'EOF'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }
g=$(( $(cat "$GEN_FILE" 2>/dev/null || echo 0) + 1 )); echo "$g" > "$GEN_FILE"
d=0; p=$$
while [ "$p" != "$DRIVER_PID" ] && [ "$d" -lt 30 ]; do p="$(ps -o ppid= -p "$p" | tr -d ' ')"; d=$((d + 1)); done
echo "gen=$g depth=$d" >> "$DEPTH_LOG"
if [ "$g" -le 3 ]; then
  # shellcheck source=lib/pane-successor.sh
  . "$LIB"
  me="/dev/$(ps -o tty= -p $$ | tr -d ' ')"
  printf '"%s" "%s"\n' "$CCA" "$0" > "$NEXT_CMD"
  sed "s#@TTY@#$me#" "$META_T" > "$NEXT_CMD.json"
  cc_pane_successor_stage "$me" "$NEXT_CMD" "$NEXT_CMD.json" || echo "gen=$g STAGE-FAILED" >> "$DEPTH_LOG"
fi
exit 0
EOF
  chmod +x "$GSTUB"
  # shellcheck disable=SC2016  # the driver's own $$, $1, $2 and $?
  printf '#!/bin/bash\nexport DRIVER_PID=$$\n"$1" "$2"; echo "wrapper-rc=$?"\n' > "$DRIVER"
  run env SHELL="$FAKESH" script -q /dev/null "$DRIVER" "$CCA" "$GSTUB"
  echo "$output"; cat "$DEPTH_LOG"
  [[ "$output" == *wrapper-rc=0* ]] || false
  [ "$(grep -c '^gen=[0-9]* depth=' "$DEPTH_LOG")" -eq 4 ]
  [ "$(grep -c STAGE-FAILED "$DEPTH_LOG")" -eq 0 ]
  d2="$(sed -n 's/^gen=2 depth=//p' "$DEPTH_LOG")"
  [ -n "$d2" ]
  [ "$(sed -n 's/^gen=3 depth=//p' "$DEPTH_LOG")" = "$d2" ]
  [ "$(sed -n 's/^gen=4 depth=//p' "$DEPTH_LOG")" = "$d2" ]
  # one successor shell served all three generations, and nothing is left staged or handed back
  [ "$(grep -c '^argv:' "$FAKESH_LOG")" -eq 1 ]
  [ -z "$(find "$CC_PANE_SUCCESSOR_DIR" -name '*.cmd' -o -name '*.handback*')" ]
}
