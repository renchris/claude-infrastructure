#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2016,SC2034  # stubs run inside extracted functions; mutant anchors are literal code text; globals are read by eval'd functions
# KERNEL PANE IDENTITY (W12, docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W12; design
# docs/research/lr-sustained-load-2026-10-20/impl/B5-kitty-off-critical-path.md §5.1-5.2, reviews R-2,
# R-3, S1-S4, S8, S14, S16, S17). "Pane P holds the row's claude on tty T" from the registry row and
# the kernel, with no kitty round-trip, so a slow or deaf kitty no longer stops identity being proven.
#
# Every ps the identity runs goes through HF_KID_PS_BIN; here that is a stub answering from fixture
# files, so nothing in this suite reads the box's process table or reaches a real kitty. The verb
# `__kid` is driven directly (`bash "$HF" __kid …`); the bounded parent is driven through the precheck
# in tests/handoff-probe-preconditions.bats.
#
# RED on the parent tree (29fa7e597): the verb, the mode switch and lr_env_block do not exist, and
# hf_lr_admit passes no CC_ADMIT_LOAD_TERM. Mutants embedded below each turn their case red.
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` is errexit-exempt in bats except on a body's
# last line.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/recon"; mkdir -p "$LR_STATE_DIR"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset CC_TERM CC_TERM_KITTY_TO CC_TERM_KITTY_PID HF_KITTY_OFFPATH HF_PANE_PROOF_ONLY HF_PANE_IDENTITY_FILE
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_REMOTE_PANE_TERM
  KF="$BATS_TEST_TMPDIR/kid"; mkdir -p "$KF"
  export KID_FIX="$KF" HF_KID_PS_BIN="$KF/ps"
  kid_ps_stub
  # The kitty socket must EXIST (-S). Bound RELATIVE: the test dir is past Darwin's 104-byte sun_path.
  SOCK="$KF/kitty-610"
  afunix_file "$SOCK"
  [ -S "$SOCK" ] || false
  LS="Wed Oct 21 03:37:41 2026"
  kid_world 41
}

# A socket FILE (bound, never listened on). Basename bind: Darwin caps sun_path at 104 bytes.
afunix_file() { /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"; }
# The ps stub. One line per call in $KID_FIX/calls; $KID_FIX/sleep delays every answer.
kid_ps_stub() {
  # shellcheck disable=SC2016  # expanded when the STUB runs
  printf '%s\n' '#!/bin/bash' \
    'F="${KID_FIX:?}"; L="${!#}"; printf "%s\n" "$*" >> "$F/calls"' \
    'if [ -f "$F/sleep" ]; then /bin/sleep "$(cat "$F/sleep")"; fi' \
    'case "$*" in' \
    '  "-E -ww -o command= -p "*) cat "$F/env.$L" 2>/dev/null ;;' \
    '  "-axo pid=,ppid=,stat=,tty=,lstart=,comm=") cat "$F/table" ;;' \
    '  "-ww -o command= -p "*) cat "$F/argv.$L" 2>/dev/null ;;' \
    '  "-M -p "*) printf "USER PID TT %%CPU STAT PRI STIME UTIME COMMAND\nme %s ?? 0.0 S %sT 0:00.01 0:00.01 kitty\n" "$L" "$(cat "$F/band" 2>/dev/null || echo 47)" ;;' \
    'esac' > "$KF/ps"
  chmod +x "$KF/ps"
}
# kitty 610 → window root 70001 (login, ttys777) → shell 70002 → claude 70003, all born at $LS.
kid_world() { # $1=window id in the claude's env
  printf '%s\n' "  610     1 S    ??       $LS /Applications/kitty.app/Contents/MacOS/kitty" \
    "70001   610 Ss   ttys777  $LS login" "70002 70001 S    ttys777  $LS -zsh" "70003 70002 S+   ttys777  $LS claude" \
    > "$KF/table"
  printf 'claude --resume x' > "$KF/argv.70003"
  printf 'claude --resume x HOME=/h PATH=/bin KITTY_WINDOW_ID=%s KITTY_PID=610 KITTY_LISTEN_ON=unix:%s\n' "$1" "$SOCK" > "$KF/env.70003"
}
kid() { run bash "$HF" __kid "$@"; }
val() { printf '%s\n' "$output" | sed -n "s/^$1=//p" | tail -1; }
# A mutated copy of the subject (lr-lib beside it, where hf_lr_script looks). $1=from $2=to.
# A literal replace in python: bash 3.2's ${var/pat/rep} over the 1 MB subject is effectively quadratic.
# The copy sits in a tree of symlinks to the real scripts/ entries, so its start-up finds its siblings.
mutant() {
  local d="$BATS_TEST_TMPDIR/mut/scripts" e
  mkdir -p "$d"
  for e in "$REPO/scripts"/*; do [ "${e##*/}" = handoff-fire.sh ] || [ -e "$d/${e##*/}" ] || ln -s "$e" "$d/${e##*/}"; done
  MUT="$d/handoff-fire.sh"; rm -f "$MUT"
  /usr/bin/python3 -I -c '
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(sys.argv[2]) != 1:
    sys.exit("mutant anchor found %d times: %s" % (s.count(sys.argv[2]), sys.argv[2]))
open(sys.argv[4], "w", encoding="utf-8").write(s.replace(sys.argv[2], sys.argv[3]))' "$HF" "$1" "$2" "$MUT" || return 1
  chmod +x "$MUT"
}

@test "T1 verified: rc 0, the kernel tty/root/socket, exactly three ps forks, and the bound is on the window id from the ENV" {
  kid 41 70003 "$LS" 610
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$(val HF_KID_TTY)" = /dev/ttys777 ] || { echo "$output"; false; }
  [ "$(val HF_KID_ROOT)" = 70001 ] || { echo "$output"; false; }
  [ "$(val HF_KID_KPID)" = 610 ] || { echo "$output"; false; }
  [ "$(val HF_KID_SOCK)" = "unix:$SOCK" ] || { echo "$output"; false; }
  [ "$(val HF_KID_PID_LS)" = "$LS" ] || { echo "$output"; false; }
  [ "$(val HF_KID_ROOT_LS)" = "$LS" ] || { echo "$output"; false; }
  [ "$(grep -c . "$KF/calls")" -eq 3 ] || { cat "$KF/calls"; false; }
  # a preset CC_TERM=kitty is fine; the identity never exports (the parent applies it, in mode on)
  CC_TERM=kitty kid 41 70003 "$LS" 610; [ "$status" -eq 0 ] || false
}

@test "T1 zombies refute: a zombie claude ⇒ 1, a zombie window root ⇒ 1; mutant without the Z test verifies them (red)" {
  sed -i '' 's/^70003 70002 S+ /70003 70002 Z+ /' "$KF/table"
  kid 41 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "zombie claude: rc=$status $output"; false; }
  kid_world 41; sed -i '' 's/^70001   610 Ss /70001   610 Zs /' "$KF/table"
  kid 41 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "zombie root: rc=$status $output"; false; }
  [ "$(val HF_KID_WHY)" = "window root 70001 gone or a zombie" ] || { echo "$output"; false; }
  mutant "case \"\$rst\" in ''|Z*) _hf_kid_no 1" "case \"\$rst\" in '') _hf_kid_no 1" || false
  run bash "$MUT" __kid 41 70003 "$LS" 610
  [ "$status" -eq 0 ] || { echo "the mutant should verify the zombie root (so the case above is the guard): rc=$status $output"; false; }
}

@test "T1 the row lstart must be the live one ⇒ 1; the env's window id must be the pane ⇒ 1; the row kitty_pid must be the env's ⇒ 1" {
  kid 41 70003 "Thu Oct 22 01:00:00 2026" 610; [ "$status" -eq 1 ] || { echo "lstart: rc=$status"; false; }
  kid 42 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "window: rc=$status"; false; }
  [ "$(val HF_KID_WHY)" = "env KITTY_WINDOW_ID=41 is not pane 42" ] || { echo "$output"; false; }
  kid 41 70003 "$LS" 999; [ "$status" -eq 1 ] || { echo "row kitty_pid: rc=$status"; false; }
  # an empty row lstart / kitty_pid is not a disagreement
  kid 41 70003 "" ""; [ "$status" -eq 0 ] || { echo "empty row fields: rc=$status $output"; false; }
}

@test "T1 argv spoof: KITTY_WINDOW_ID in claude's argv never decides — the env block alone does; whole-line mutants go red" {
  # argv says 41, env says 99: pane 41 is refuted (the env says 99), pane 99 verifies
  printf 'claude --resume x KITTY_WINDOW_ID=41 KITTY_PID=610' > "$KF/argv.70003"
  printf 'claude --resume x KITTY_WINDOW_ID=41 KITTY_PID=610 HOME=/h PATH=/bin KITTY_WINDOW_ID=99 KITTY_PID=610 KITTY_LISTEN_ON=unix:%s\n' "$SOCK" > "$KF/env.70003"
  kid 41 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "argv 41 / env 99 as pane 41: rc=$status $output"; false; }
  kid 99 70003 "$LS" 610; [ "$status" -eq 0 ] || { echo "argv 41 / env 99 as pane 99: rc=$status $output"; false; }
  # mutant: the FIRST token of the whole line (cc_sid_for_pane's grep -m1 shape) verifies pane 41
  mutant 'wid="$(sed -n '"'"'s/^KITTY_WINDOW_ID=//p'"'"' <<<"$toks" | tail -1)"' \
         'wid="$(printf '"'"'%s\n'"'"' "$full" | tr '"'"' '"'"' '"'"'\n'"'"' | sed -n '"'"'s/^KITTY_WINDOW_ID=//p'"'"' | head -1)"' || false
  run bash "$MUT" __kid 41 70003 "$LS" 610
  [ "$status" -eq 0 ] || { echo "the whole-line head -1 mutant should be fooled by argv: rc=$status $output"; false; }
}

@test "T1 cannot tell ⇒ 2: no env block, no kitty ancestor, a missing socket, a socket naming another kitty, a gone pid" {
  printf 'claude --resume x KITTY_WINDOW_ID=41 KITTY_PID=610\n' > "$KF/env.70003"
  kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "no env block: rc=$status $output"; false; }
  kid_world 41
  sed -i '' 's/^70001   610 /70001     1 /' "$KF/table"
  kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "no kitty ancestor: rc=$status $output"; false; }
  kid_world 41
  printf 'claude --resume x HOME=/h PATH=/bin KITTY_WINDOW_ID=41 KITTY_PID=610 KITTY_LISTEN_ON=unix:%s/nope/kitty-610\n' "$KF" > "$KF/env.70003"
  kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "missing socket: rc=$status $output"; false; }
  afunix_file "$KF/kitty-999"
  printf 'claude --resume x HOME=/h PATH=/bin KITTY_WINDOW_ID=41 KITTY_PID=610 KITTY_LISTEN_ON=unix:%s/kitty-999\n' "$KF" > "$KF/env.70003"
  kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "socket of kitty 999: rc=$status $output"; false; }
  kid_world 41
  kid 41 70099 "$LS" 610; [ "$status" -eq 2 ] || { echo "gone pid: rc=$status"; false; }
  kid x 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "non-numeric pane: rc=$status"; false; }
}

@test "T1 a kitty_pid whose comm is not kitty ⇒ 1" {
  sed -i '' 's|/Applications/kitty.app/Contents/MacOS/kitty|/usr/bin/login|' "$KF/table"
  kid 41 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
}

@test "S8: a preset CC_TERM other than kitty ⇒ 2, CC_REMOTE_PANE_TERM=off ⇒ 2" {
  CC_TERM=iterm2 kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "iterm2 preset: rc=$status"; false; }
  CC_REMOTE_PANE_TERM=off kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "resolver off: rc=$status"; false; }
}

@test "T1 census identity (field 5): agreeing fields verify (tty normalised), root_lstart disagreeing ⇒ 1; mutant without the compare verifies (red)" {
  export HF_PANE_IDENTITY_FILE="$BATS_TEST_TMPDIR/id.json"
  printf '{"window_id":41,"kitty_pid":610,"kitty_lstart":"%s","root_pid":70001,"root_lstart":"%s","tty":"ttys777"}\n' "$LS" "$LS" > "$HF_PANE_IDENTITY_FILE"
  kid 41 70003 "$LS" 610; [ "$status" -eq 0 ] || { echo "agreeing census: rc=$status $output"; false; }
  printf '{"window_id":41,"root_lstart":"Thu Oct 22 01:00:00 2026"}\n' > "$HF_PANE_IDENTITY_FILE"
  kid 41 70003 "$LS" 610; [ "$status" -eq 1 ] || { echo "disagreeing census: rc=$status $output"; false; }
  [ "$(val HF_KID_WHY)" = "census identity disagrees on root_lstart (Thu Oct 22 01:00:00 2026)" ] || { echo "$output"; false; }
  printf 'not json' > "$HF_PANE_IDENTITY_FILE"
  kid 41 70003 "$LS" 610; [ "$status" -eq 2 ] || { echo "unreadable census: rc=$status"; false; }
  printf '{"window_id":41,"root_lstart":"Thu Oct 22 01:00:00 2026"}\n' > "$HF_PANE_IDENTITY_FILE"
  mutant '[ -z "$cv" ] || [ "$cv" = "${cf#*:}" ] || {' '[ -z "$cv" ] || true || {' || false
  run bash "$MUT" __kid 41 70003 "$LS" 610
  [ "$status" -eq 0 ] || { echo "the no-compare mutant should verify: rc=$status"; false; }
}

@test "the switch is MONOTONE: off from the env or the file wins; else env, else file, else shadow (the code default)" {
  eval "$(sed -n '/^hf_kitty_offpath_mode() {/,/^}/p;/^hf_pane_proof_only_on() {/,/^}/p' "$HF")"
  M="$LR_STATE_DIR/kitty-offpath.mode"
  [ "$(hf_kitty_offpath_mode)" = shadow ] || false
  printf 'garbage' > "$M"; [ "$(hf_kitty_offpath_mode)" = shadow ] || false
  printf 'on\n' > "$M"; [ "$(hf_kitty_offpath_mode)" = on ] || false
  [ "$(HF_KITTY_OFFPATH=shadow hf_kitty_offpath_mode)" = shadow ] || false
  [ "$(HF_KITTY_OFFPATH=off hf_kitty_offpath_mode)" = off ] || false
  printf 'off\n' > "$M"; [ "$(HF_KITTY_OFFPATH=on hf_kitty_offpath_mode)" = off ] || { echo "an env on defeated the file's off"; false; }
  rm -f "$M"; [ "$(HF_KITTY_OFFPATH=on hf_kitty_offpath_mode)" = on ] || false
  # --only: on only in mode on, with its own monotone off
  HF_KITTY_OFFPATH=shadow; ! hf_pane_proof_only_on || false
  HF_KITTY_OFFPATH=on; hf_pane_proof_only_on || false
  ! HF_PANE_PROOF_ONLY=off hf_pane_proof_only_on || false
  printf 'off' > "$LR_STATE_DIR/pane-proof-only.mode"; ! hf_pane_proof_only_on || false
  rm -f "$LR_STATE_DIR/pane-proof-only.mode"; printf 'off' > "$M"; ! hf_pane_proof_only_on || false
}

@test "every new event and line text classifies as nothing the reconciler acts on (classify._CLASSES; S16b)" {
  # The fixed parts of each new text. Each must still be in the subject (a list that drifted from the
  # code would pass vacuously), and none may match an IMPOSSIBLE/HOLD/WAIT/DETERMINISTIC pattern.
  T="$BATS_TEST_TMPDIR/texts"
  printf '%s\n' \
    "kernel identity: kitty 610 window 41 root 70001 on ttys777; no terminal round-trip" \
    "identity: kernel (kitty 610 window 41 root 70001 on ttys777; no terminal round-trip)" \
    "pane_root_lstart: Wed Oct 21 03:37:41 2026" \
    "kid_rc=2 kernel_tty= kitty_tty=ttys777 agree=- at=precheck kitty_pid=- kitty_lstart=- root=- why=the identity probe ended rc 124 (124/137: our own bound fired, no verdict)" \
    "pane probe got no answer (listing rc 124); kitty 610 main-thread band [47 47 47]; decided after the stage: the move proceeds only staged, pinned and signal-exiting" \
    "kitty background-banded: its main thread would not drain the successor's output (B8); kitty 610 band [4 4 4]" \
    "kitty 610 main-thread band unreadable [? ? ?], so the advisory proceed has no proof" \
    "the watcher's pane probe got NO ANSWER and the relaunch could not avoid the terminal: the successor could not be staged" \
    "pane probe unanswered and the signal exit declined (no process on ttys777)" \
    "→ pane-probe ADVISORY: the terminal did not answer inside our bound (listing rc 124)" \
    "shadow: pane probe got no answer (listing rc 124) over a verified kernel identity; mode on would decide after the stage" \
    > "$T"
  for frag in "no terminal round-trip" "identity: kernel (kitty" "pane_root_lstart:" "kernel_tty=" "decided after the stage: the move proceeds only staged" \
              "kitty background-banded: its main thread would not drain the successor's output (B8)" "main-thread band unreadable" \
              "the relaunch could not avoid the terminal" "pane probe unanswered and the signal exit declined" "pane-probe ADVISORY" "over a verified kernel identity"; do
    grep -qF -- "$frag" "$HF" || { echo "text no longer in the subject: $frag"; false; }
  done
  run env PYTHONPATH="$REPO/scripts/limit-recover" /usr/bin/python3 -c '
import sys
from lr_recon import classify
bad = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    for cls, pats in classify._CLASSES:
        if cls == "TRANSIENT":
            continue
        for p in pats:
            if p.search(line):
                bad.append("%s %s: %s" % (cls, p.pattern, line))
print("\n".join(bad))
sys.exit(1 if bad else 0)' "$T"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "G1: hf_lr_admit's admission carries the load term OFF unless the rail turned it on (red on 29fa7e597)" {
  eval "$(sed -n '/^hf_lr_admit() {/,/^}/p' "$HF")"
  hf_launcher_file() { echo "$BATS_TEST_TMPDIR/launcher"; }
  hf_launcher_is_lr() { return 0; }
  hf_launcher_subject() { echo "sid-1"; }
  cc_capacity_admit() { printf 'term=%s\n' "${CC_ADMIT_LOAD_TERM-<unset>}" >> "$BATS_TEST_TMPDIR/admit.log"; return 1; }
  : > "$BATS_TEST_TMPDIR/launcher"
  RECYCLE=0 DRY=0; unset LR_ADMIT_TOKEN LR_LOAD_TERM CC_ADMIT_LOAD_TERM
  run hf_lr_admit; [ "$status" -eq 9 ] || { echo "rc=$status $output"; false; }
  LR_LOAD_TERM=on run hf_lr_admit
  [ "$(cat "$BATS_TEST_TMPDIR/admit.log")" = "$(printf 'term=off\nterm=on')" ] || { cat "$BATS_TEST_TMPDIR/admit.log"; false; }
}
