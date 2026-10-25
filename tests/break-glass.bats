#!/usr/bin/env bats
# scripts/break-glass/rescue.sh + rescue.bashrc — the no-tty break-glass kit (incident 2026-10-25,
# DESIGN.md C5). Hermetic: BG_ROOT and CC_LOCKWATCH_DIR are fixtures; the only processes signalled are
# throwaway setsid trees this file starts, and teardown reaps them BY GROUP (never a leader by pid).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RS="$REPO/scripts/break-glass/rescue.sh"
  export BG_ROOT="$BATS_TEST_TMPDIR/bg" CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lw"
  # a scan abandoned under fleet load is a correct refusal, but not the path these cases test
  export RESCUE_SCAN_DL=60
  mkdir -p "$CC_LOCKWATCH_DIR"
  TREES=()
}

teardown() {
  local g
  for g in "${TREES[@]+"${TREES[@]}"}"; do kill -KILL -- "-$g" 2>/dev/null || true; done
}

# tree <shell program> → starts an ORPHANED session (leader's parent exits, so its ppid is 1) running
# the program under /bin/sh; prints the leader pid. Its pgid and sid are the leader's pid.
tree() {
  local f="$BATS_TEST_TMPDIR/leader.$RANDOM"
  /usr/bin/perl -e 'use POSIX; fork and exit; POSIX::setsid(); open F, ">", $ARGV[0]; print F $$; close F;
                    exec "/bin/sh", "-c", $ARGV[1]' "$f" "$1" </dev/null >/dev/null 2>&1
  local i=0; while [ ! -s "$f" ] && [ "$i" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.5
  cat "$f"
}
lstart() { ps -o lstart= -p "$1"; }
alive_in_group() { ps -axo pgid= | awk -v g="$1" '$1 == g' | wc -l | tr -d ' '; }
ptymap() { printf '{"leaders":[{"pid":%s,"lstart":"x","pgid":%s,"tdev":"16/63","ppid":1,"state":"S"}]}\n' "$1" "$1" > "$CC_LOCKWATCH_DIR/pty.json"; }

@test "(a) capture: the summary carries every field and progress ends in EXIT" {
  BG_LIGHT=1 BG_FORENSICS_KIT=/nonexistent run perl -e 'alarm 120; exec @ARGV' -- /bin/bash "$RS" capture
  [ "$status" -eq 0 ]
  # abandoned= is a field, not a verdict: under load a step may be abandoned, and the kit must say so
  for k in procs= threads= U= E= claude= 'cpu[' 'devprobe OK n=' abandoned= kit=; do
    [[ "$output" == *"$k"* ]] || { echo "missing $k in: $output"; false; }
  done
  prog="$(ls -d "$BG_ROOT"/kits/*-capture-*)/progress"
  [[ "$(tail -1 "$prog")" == *" EXIT rc=0" ]] || false
  grep -q ' FORENSICS missing=/nonexistent' "$prog"
}

@test "(b) a step that outlives its deadline is ABANDONED within 3 s, and the kit still finishes" {
  # trap '' ALRM survives exec, so the alarm wrapper cannot end it: the shape of an uninterruptible wait
  BG_LIGHT=1 BG_FORENSICS_KIT=/nonexistent BG_TEST_STEP="trap '' ALRM; exec /bin/sleep 30" BG_TEST_STEP_DL=1 \
    run perl -e 'alarm 120; exec @ARGV' -- /bin/bash "$RS" capture
  [ "$status" -eq 0 ]
  prog="$(ls -d "$BG_ROOT"/kits/*-capture-*)/progress"
  b=$(awk '$2 == "BEGIN" && $3 == "teststep" {print $1}' "$prog")
  a=$(awk '$2 == "ABANDON" && $3 == "teststep" {print $1}' "$prog")
  [ -n "$a" ] && [ $(( a - b )) -le 3 ]
  [[ "$output" == *"abandoned=teststep,"* ]] || false
  [[ "$(tail -1 "$prog")" == *" EXIT rc=0" ]] || false
  p=$(awk '$2 == "ABANDON" {sub("pid=", "", $4); print $4}' "$prog")
  pkill -KILL -P "$p" 2>/dev/null || true
}

@test "(c) unpoison: a leader whose lstart differs gets NO signal (rc 2)" {
  L=$(tree 'sleep 300 & sleep 300 & wait'); TREES+=("$L")
  ptymap "$L"
  run /bin/bash "$RS" unpoison "$L" "Thu Jan  1 00:00:00 2026"
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED"*"pid reused"* ]] || { echo "got: $output"; false; }
  [ "$(alive_in_group "$L")" -eq 3 ]
  grep -q '"result":"refused","detail":"lstart-mismatch"' "$CC_LOCKWATCH_DIR/actions.jsonl"
}

@test "(c) unpoison: an orphaned pty session tree is killed whole, by group, openers first" {
  # the opener sits in a SECOND group of the same session (RCA R3: pgid alone is not enough)
  L=$(tree '/usr/bin/perl -e "setpgrp(0,0); sleep 300" & sleep 300 & wait'); TREES+=("$L")
  O=$(ps -axo pid=,ppid=,pgid= | awk -v l="$L" '$2 == l && $3 != l {print $1}')
  [ -n "$O" ]; TREES+=("$O")
  ptymap "$L"
  run /bin/bash "$RS" unpoison "$L" "$(lstart "$L")" --dry-run
  [ "$status" -eq 4 ]
  [[ "$output" == *"WOULD"*"groups: $O $L"* ]] || false
  [ "$(alive_in_group "$L")" -eq 2 ]
  run /bin/bash "$RS" unpoison "$L" "$(lstart "$L")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CURED"* ]] || false
  sleep 0.5
  [ "$(alive_in_group "$L")" -eq 0 ]
  [ "$(alive_in_group "$O")" -eq 0 ]
  prog="$(ls -d "$BG_ROOT"/kits/*-unpoison-* | tail -1)/progress"
  [ "$(grep -n "KILL -$O" "$prog" | cut -d: -f1)" -lt "$(grep -n "KILL -$L\$" "$prog" | cut -d: -f1)" ]
  grep -q '"result":"cured"' "$CC_LOCKWATCH_DIR/actions.jsonl"
}

@test "(c) unpoison refuses a healthy leader, a leader with no pty on record, and our own group" {
  L=$(tree 'sleep 300 & sleep 300 & wait'); TREES+=("$L")
  run /bin/bash "$RS" unpoison "$L" "$(lstart "$L")"          # no ttymap/pty.json: tdev reads ??
  [ "$status" -eq 2 ]; [[ "$output" == *"no pty"* ]] || false
  /usr/bin/perl -e 'use POSIX; POSIX::setsid(); exec @ARGV' -- /bin/sleep 300 </dev/null >/dev/null 2>&1 &
  H=$!; TREES+=("$H"); sleep 0.5; ptymap "$H"
  run /bin/bash "$RS" unpoison "$H" "$(lstart "$H")"          # ppid is this shell, not 1, and not exiting
  [ "$status" -eq 2 ]; [[ "$output" == *"neither exiting nor orphaned"* ]] || false
  run /bin/bash "$RS" unpoison "$(ps -o pgid= -p $$ | tr -d ' ')" "$(lstart "$(ps -o pgid= -p $$ | tr -d ' ')")"
  [ "$status" -eq 2 ]
  [ "$(alive_in_group "$L")" -eq 3 ] && [ "$(alive_in_group "$H")" -eq 1 ]
}

@test "(d) rescue.bashrc: no \\l prompt escape, pager off, and the /dev-walking commands refused" {
  ! grep -nE '^[^#]*PS1=.*\\l' "$REPO/scripts/break-glass/rescue.bashrc"
  H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H"
  run env -i HOME="$H" PATH=/usr/bin:/bin /bin/bash --noprofile --norc -c '
    . "$0" >/dev/null 2>&1
    printf "PS1=%s PAGER=%s\n" "$PS1" "$PAGER"
    ps -p $$ >/dev/null 2>&1; echo "ps-p=$?"
    ps -axo pid=,tty= >/dev/null 2>&1; echo "ps-tty=$?"
    ps -axo pid=,tdev= >/dev/null 2>&1; echo "ps-tdev=$?"
    zsh -fc true >/dev/null 2>&1; echo "zsh=$?"
    pkill -f claude >/dev/null 2>&1; echo "pkill=$?"' "$REPO/scripts/break-glass/rescue.bashrc"
  [[ "$output" != *'\l'* ]] || false
  [[ "$output" == *"PAGER=cat"* ]] || false
  [[ "$output" == *"ps-p=2"* && "$output" == *"ps-tty=2"* && "$output" == *"ps-tdev=0"* ]] || false
  [[ "$output" == *"zsh=2"* && "$output" == *"pkill=2"* ]] || false
  [ -s "$H/.claude/autonomy/break-glass/rescue-profile.last" ]
}

@test "brownout: holds with by=operator, and off releases only an operator hold" {
  export CC_BROWNOUT_FILE="$BATS_TEST_TMPDIR/brownout.json"
  run /bin/bash "$RS" brownout 60
  [ "$status" -eq 0 ]
  jq -e '.by == "operator" and .hold_s == 3600 and (.surface_unavailable_since | test("Z$"))' "$CC_BROWNOUT_FILE"
  run /bin/bash "$RS" brownout off
  [ ! -e "$CC_BROWNOUT_FILE" ]
  printf '{"surface_unavailable_since":"2026-10-25T00:00:00Z","by":"dispatcher"}\n' > "$CC_BROWNOUT_FILE"
  run /bin/bash "$RS" brownout off
  [ -e "$CC_BROWNOUT_FILE" ]
}

@test "migration 0081: installs the links and the rendered profile, refuses a real file, undoes cleanly" {
  M="$REPO/migrations/0081-break-glass-install.sh"
  H="$BATS_TEST_TMPDIR/mh"; mkdir -p "$H"
  P="$H/Library/Application Support/iTerm2/DynamicProfiles/break-glass-rescue.json"
  HOME="$H" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_NO_HS=1 run bash "$M"
  [ "$status" -eq 0 ]
  [ "$(readlink "$H/.claude/scripts/break-glass/rescue.sh")" = "$REPO/scripts/break-glass/rescue.sh" ]
  jq -e --arg h "$H" '.Profiles[0] | .Guid == "cc-break-glass-rescue-0001" and .Name == "Rescue"
        and (.Command == "/bin/bash --noprofile --rcfile \($h)/.claude/scripts/break-glass/rescue.bashrc -i")' "$P"
  HOME="$H" run bash "$M" --verify
  [ "$status" -eq 0 ]
  HOME="$H" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_NO_HS=1 run bash "$M"       # idempotent
  [ "$status" -eq 0 ]
  HOME="$H" CC_MIGRATION_NO_HS=1 run bash "$M" --undo
  [ ! -e "$H/.claude/scripts/break-glass/rescue.sh" ] && [ ! -e "$P" ]
  printf 'mine\n' > "$H/.claude/scripts/break-glass/rescue.sh"                 # a real file is never clobbered
  HOME="$H" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_NO_HS=1 run bash "$M"
  [ "$status" -eq 1 ]
  [ "$(cat "$H/.claude/scripts/break-glass/rescue.sh")" = mine ]
}
