#!/usr/bin/env bats
# shellcheck disable=SC2329,SC2034,SC2016,SC2030,SC2031  # stubs run in extracted fragments, which read these globals; anchors are literal code text; each @test is its own subshell by design
# THE WATCHER'S PANE PROBE: ONE WINDOW, ADVISORY ON ONE NARROW NO (W12, docs/plans/
# LR_SUSTAINED_LOAD_IMPL.md § W12; design docs/research/lr-sustained-load-2026-10-20/impl/
# B5-kitty-off-critical-path.md §5.4, reviews R-5, R-10, S5, S6, S14, S17).
#
#   (a) transport: on kitty, in mode on, pane_proof asks `session list --json --only P` and
#       bin/it2-kitty answers it with `ls --match id:P`; iTerm2 and every other mode never see it;
#   (b) the watcher stays only for a no-answer whose listing OUR bound killed (rc 124/137), and only
#       when the foreground said it may (HF_PANE_PROOF_ADVISORY=1, then un-exported);
#   (c) the foreground defers that no past the stage, unless kitty's main thread is background-banded
#       (R-5), and goes on only staged, pinned and signal-exiting; the post-confirm typed-/exit arm
#       holds after the subject-gone yield with the debt abandoned first (S5);
#   (d) after an advisory no, a stage is revoked (and the relaunch typed) only once a bounded probe
#       answers, or at the load-scaled cap (R-10).
# Fragments are cut out of handoff-fire.sh by their marker comments and run over stubs, the way
# handoff-fire-recycle-custody.bats drives the precheck; mutants are applied to the cut text.
#
# Every assertion is `[ ]` or `… || false`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  K="$REPO/bin/it2-kitty"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/recon"; mkdir -p "$LR_STATE_DIR"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset CC_TERM CC_TERM_KITTY_TO CC_TERM_KITTY_PID HF_KITTY_OFFPATH HF_PANE_PROOF_ONLY HF_PANE_PROOF_ADVISORY
  unset KITTY_WINDOW_ID KITTY_PID KITTY_LISTEN_ON CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  CALLS="$BATS_TEST_TMPDIR/it2.calls"
}

# ── (a) the transport ───────────────────────────────────────────────────────────────────────────

pp_load() {
  eval "$(sed -n '/^in_kitty() {/p;/^kitty_identity() {/p;/^hf_bounded() {/,/^}/p;/^hf_bounded_s() {/,/^}/p;/^hf_kitty_offpath_mode() {/,/^}/p;/^hf_pane_proof_only_on() {/,/^}/p;/^pane_proof() {/,/^}/p' "$HF")"
  HF_TIMEOUT_BIN="" HF_TIMEOUT_S=10
  IT2="$BATS_TEST_TMPDIR/it2"
  # shellcheck disable=SC2016  # expanded when the stub runs
  printf '%s\n' '#!/bin/bash' "printf '%s\n' \"\$*\" >> '$CALLS'" \
    'case "${IT2_MODE:-hit}" in' \
    '  hit) printf "[{\"id\": \"41\"}]\n" ;;' \
    '  empty) printf "[]\n" ;;' \
    '  t124) exit 124 ;;' \
    '  fail) echo boom >&2; exit 1 ;;' \
    'esac' > "$IT2"
  chmod +x "$IT2"
}

@test "(a) kitty + mode on asks ONE window; shadow, iTerm2, HF_PANE_PROOF_ONLY=off, its file and the offpath file's off never do" {
  pp_load
  CC_TERM=kitty HF_KITTY_OFFPATH=on run pane_proof "$IT2" 41 __recycle
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(tail -1 "$CALLS")" = "session list --json --only 41" ] || { cat "$CALLS"; false; }
  for env in "CC_TERM=kitty HF_KITTY_OFFPATH=shadow" "CC_TERM=iterm2 HF_KITTY_OFFPATH=on" \
             "CC_TERM=kitty HF_KITTY_OFFPATH=on HF_PANE_PROOF_ONLY=off"; do
    : > "$CALLS"
    eval "$env run pane_proof \"\$IT2\" 41 __recycle"
    [ "$(cat "$CALLS")" = "session list --json" ] || { echo "$env: $(cat "$CALLS")"; false; }
  done
  : > "$CALLS"; printf 'off' > "$LR_STATE_DIR/pane-proof-only.mode"
  CC_TERM=kitty HF_KITTY_OFFPATH=on run pane_proof "$IT2" 41 __recycle
  [ "$(cat "$CALLS")" = "session list --json" ] || { echo "pane-proof-only.mode off: $(cat "$CALLS")"; false; }
  rm -f "$LR_STATE_DIR/pane-proof-only.mode"; : > "$CALLS"; printf 'off' > "$LR_STATE_DIR/kitty-offpath.mode"
  CC_TERM=kitty HF_KITTY_OFFPATH=on run pane_proof "$IT2" 41 __recycle
  [ "$(cat "$CALLS")" = "session list --json" ] || { echo "kitty-offpath.mode off: $(cat "$CALLS")"; false; }
}

@test "(a) the one-window answers keep the three verdicts: [] rc 0 ⇒ UNREACHABLE (1), rc 124 ⇒ NO-ANSWER (2) naming rc=124; HF_PP_LIST_RC is the listing rc" {
  pp_load; export CC_TERM=kitty HF_KITTY_OFFPATH=on
  IT2_MODE=empty run pane_proof "$IT2" 41 __recycle
  [ "$status" -eq 1 ] || false
  printf '%s\n' "$output" | grep -q '^!! pane-UNREACHABLE:' || { echo "$output"; false; }
  IT2_MODE=t124 run pane_proof "$IT2" 41 __recycle
  [ "$status" -eq 2 ] || false
  printf '%s\n' "$output" | grep -q '^!! pane-NO-ANSWER: .* failed (rc=124 in ' || { echo "$output"; false; }
  rc=0; IT2_MODE=t124 pane_proof "$IT2" 41 __recycle >/dev/null || rc=$?
  [ "$rc" = 2 ] || { echo "rc=$rc"; false; }
  [ "$HF_PP_LIST_RC" = 124 ] || { echo "list_rc=$HF_PP_LIST_RC"; false; }
}

@test "(a) mutant: --only sent whenever kitty_identity holds would reach the probe in shadow mode (the guard above is not vacuous)" {
  pp_load
  src="$(sed -n '/^pane_proof() {/,/^}/p' "$HF")"
  # pattern and replacement through variables: bash 3.2 keeps quotes inside a replacement literally
  from="if kitty_identity && hf_pane_proof_only_on; then" to="if kitty_identity; then"
  mut="${src/"$from"/$to}"
  [ "$mut" != "$src" ] || false
  eval "$mut"
  CC_TERM=kitty HF_KITTY_OFFPATH=shadow run pane_proof "$IT2" 41 __recycle
  [ "$(tail -1 "$CALLS")" = "session list --json --only 41" ] || { cat "$CALLS"; false; }
}

fake_kitty() { # $1=mode: two (ignores --match) · none (No matching windows) · boom
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock" CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  # shellcheck disable=SC2016  # expanded when the stub runs
  printf '%s\n' '#!/bin/bash' "printf '%s\n' \"\$*\" >> '$CALLS'" \
    'case "${KMODE:-two}" in' \
    '  two) printf "[{\"id\":1,\"tabs\":[{\"id\":1,\"windows\":[{\"id\":41,\"title\":\"a\",\"cwd\":\"/a\",\"pid\":7},{\"id\":42,\"title\":\"b\",\"cwd\":\"/b\",\"pid\":8}]}]}]\n" ;;' \
    '  none) echo "Error: No matching windows for expression: id:41" >&2; exit 1 ;;' \
    '  boom) echo "read unix: i/o timeout" >&2; exit 1 ;;' \
    'esac' > "$CC_TERM_KITTY"
  chmod +x "$CC_TERM_KITTY"
}

@test "(a) it2-kitty --only: ls --match id:N, re-filtered by id; 'No matching windows' ⇒ [] rc 0; any other failure ⇒ 1; a non-numeric id ⇒ 64" {
  fake_kitty
  run "$K" session list --json --only 41
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c 'import json,sys; print(",".join(w["id"] for w in json.load(sys.stdin)))')" = 41 ] || { echo "$output"; false; }
  grep -q -- '@ --to unix:.*/sock ls --match id:41$' "$CALLS" || { cat "$CALLS"; false; }
  run "$K" session list --only 41
  [ "$status" -eq 0 ] || false
  [ "$output" = 41 ] || { echo "bare: $output"; false; }
  KMODE=none run "$K" session list --json --only 41
  [ "$status" -eq 0 ] || { echo "absent: rc=$status"; false; }
  [ "$output" = "[]" ] || { echo "absent: $output"; false; }
  KMODE=boom run "$K" session list --json --only 41
  [ "$status" -eq 1 ] || { echo "failure: rc=$status $output"; false; }
  [[ "$output" == *"i/o timeout"* ]] || false
  run "$K" session list --json --only x41
  [ "$status" -eq 64 ] || { echo "usage: rc=$status $output"; false; }
  # without --only the full listing is unchanged
  run "$K" session list --json
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c 'import json,sys; print(",".join(w["id"] for w in json.load(sys.stdin)))')" = 41,42 ] || { echo "$output"; false; }
}

# ── (b) the watcher ──────────────────────────────────────────────────────────────────────────────

watcher_frag() {
  awk '/# ADVISORY ON ONE NARROW NO/{p=1} p{print} p && /^  fi$/{exit}' "$HF" > "$BATS_TEST_TMPDIR/w.sh"
  grep -q 'pane_proof "$IT2" "$RSID" __recycle' "$BATS_TEST_TMPDIR/w.sh" || false
}
# $1=pane_proof rc $2=listing rc $3=advisory env; prints STAYED and the child's view of the env
watcher_run() {
  run env PP_RC="$1" PP_LIST="$2" HF_PANE_PROOF_ADVISORY="$3" bash -c '
    pane_proof() { HF_PP_LIST_RC="$PP_LIST"; return "$PP_RC"; }
    IT2=x RSID=41
    . "$1"
    echo "STAYED advisory=$rcy_pp_advisory child_sees=$(bash -c "echo \${HF_PANE_PROOF_ADVISORY:-unset}")"' _ "$BATS_TEST_TMPDIR/w.sh"
}

@test "(b) the watcher stays only on a no-answer our bound killed, when told it may; UNREACHABLE, other rcs and no advisory exit 1" {
  watcher_frag
  watcher_run 2 124 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"STAYED advisory=1 child_sees=unset"* ]] || { echo "S17: the env must not ride on: $output"; false; }
  watcher_run 2 137 1; [[ "$output" == *"STAYED advisory=1"* ]] || false
  watcher_run 1 0 1;   [ "$status" -eq 1 ] || { echo "UNREACHABLE: $output"; false; }
  watcher_run 2 1 1;   [ "$status" -eq 1 ] || { echo "a crashed listing (rc 1) is a broken transport: $output"; false; }
  watcher_run 2 64 1;  [ "$status" -eq 1 ] || { echo "a usage rc is a broken transport: $output"; false; }
  watcher_run 2 124 0; [ "$status" -eq 1 ] || { echo "no advisory: $output"; false; }
  watcher_run 0 0 1;   [[ "$output" == *"STAYED advisory=0"* ]] || false
}

# ── (c) the foreground ───────────────────────────────────────────────────────────────────────────

defer_frag() { # → $BATS_TEST_TMPDIR/d.sh, the deferral block alone
  awk '/# DEFERRED, NOT DROPPED/{p=1} p && /^  if \[ "\$RCY_PP" != 0 \]; then$/{exit} p{print}' "$HF" > "$BATS_TEST_TMPDIR/d.sh"
  grep -q 'hf_kitty_band "$HF_KID_KPID"' "$BATS_TEST_TMPDIR/d.sh" || false
}
band_fn() { sed -n '/^hf_bounded_s() {/,/^}/p;/^hf_kitty_band() {/,/^}/p;/^hf_kitty_offpath_mode() {/,/^}/p' "$HF" > "$BATS_TEST_TMPDIR/band.sh"; }
# $1=band PRI (or "none") $2=listing rc in the log $3=advisory → prints RCY_PP, DEFERRED, the hold why, and the rows
defer_run() {
  local band="$1" lrc="$2" adv="$3" log="$BATS_TEST_TMPDIR/watcher.log"
  printf '!! pane-NO-ANSWER: __recycle — x failed (rc=%s in 13s, shape=bare, ids=0, CC_TERM=kitty) without naming pane 41.\n' "$lrc" > "$log"
  printf '%s\n' '#!/bin/bash' "[ '$band' = none ] && exit 1" \
    "printf 'USER PID TT %%CPU STAT PRI STIME UTIME COMMAND\nme 610 ?? 0.0 S ${band}T 0:00.01 0:00.01 kitty\n'" > "$BATS_TEST_TMPDIR/ps"
  chmod +x "$BATS_TEST_TMPDIR/ps"
  run env HF_PANE_PROOF_ADVISORY="$adv" HF_KID_PS_BIN="$BATS_TEST_TMPDIR/ps" bash -c '
    . "$1"; HF_TIMEOUT_BIN=""
    emit_recycle_event() { echo "ROW $1 $4"; }
    hf_succ_mode() { echo resume; }
    RCY_PP="${PP:-3}" SID=41 log="$2" HF_KID_KPID=610 HF_KID_OK=1 HF_KID_FOR=41 RCY_REMOTE=1
    . "$3"
    echo "RCY_PP=$RCY_PP DEFERRED=${RCY_PP_DEFERRED:-} WHY=${RCY_PP_HOLD_WHY:-}"' _ "$BATS_TEST_TMPDIR/band.sh" "$log" "$BATS_TEST_TMPDIR/d.sh"
}

@test "(c) R-5 band gate: band 47 ⇒ deferred (RCY_PP 0) with a deferred row; band 4 ⇒ held, 'kitty background-banded'; unreadable ⇒ held" {
  defer_frag; band_fn
  defer_run 47 124 1
  [[ "$output" == *"RCY_PP=0 DEFERRED=3 WHY="* ]] || { echo "$output"; false; }
  [[ "$output" == *"ROW recycle-pane-probe-deferred "*"band [47 47 47]"* ]] || { echo "$output"; false; }
  defer_run 4 124 1
  [[ "$output" == *"RCY_PP=3 DEFERRED= WHY=kitty background-banded: its main thread would not drain the successor's output (B8); kitty 610 band [4 4 4]"* ]] || { echo "$output"; false; }
  defer_run none 137 1
  [[ "$output" == *"RCY_PP=3 DEFERRED= WHY=kitty 610 main-thread band unreadable"* ]] || { echo "$output"; false; }
}

@test "(c) S6 narrowing: a listing rc other than 124/137 or no advisory is not deferred; shadow logs what on would do and holds" {
  defer_frag; band_fn
  defer_run 47 1 1;   [[ "$output" == *"RCY_PP=3 DEFERRED= WHY="* ]] || { echo "rc 1: $output"; false; }
  # a STALLED probe (await rc 2: no verdict at all) keeps today's hold, even with a bound-killed line
  export PP=2; defer_run 47 124 1; unset PP
  [[ "$output" == *"RCY_PP=2 DEFERRED= WHY="* ]] || { echo "stalled: $output"; false; }
  defer_run 47 124 0; [[ "$output" == *"RCY_PP=3 DEFERRED= WHY="* ]] || { echo "no advisory: $output"; false; }
  [[ "$output" == *"ROW recycle-pane-probe-deferred-shadow "* ]] || { echo "shadow row: $output"; false; }
  export HF_KITTY_OFFPATH=off
  defer_run 47 124 0
  [[ "$output" != *"ROW "* ]] || { echo "off must log nothing: $output"; false; }
}

@test "(c) mutant: the deferral without the band gate proceeds into a background-banded kitty (red)" {
  defer_frag; band_fn
  src="$(cat "$BATS_TEST_TMPDIR/d.sh")"
  from='hf_kitty_band "$HF_KID_KPID" || rcy_band_rc=$?' to=':'
  printf '%s\n' "${src/"$from"/$to}" > "$BATS_TEST_TMPDIR/d.sh"
  ! grep -q 'hf_kitty_band "$HF_KID_KPID"' "$BATS_TEST_TMPDIR/d.sh" || false
  defer_run 4 124 1
  [[ "$output" == *"RCY_PP=0 DEFERRED=3"* ]] || { echo "the mutant should defer past band 4: $output"; false; }
}

stage_frag() {
  awk '/^  rcy_staged=0; hf_succ_stage "\$tty" "\$cmdfile"/{p=1} p && /^  # THE COMMIT — confirm/{exit} p{print}' "$HF" > "$BATS_TEST_TMPDIR/s.sh"
  grep -q 'RCY_PP_DEFERRED' "$BATS_TEST_TMPDIR/s.sh" || false
}
# $1=stage rc $2=pin rc $3=RCY_PP_DEFERRED $4=HF_EXIT_ACTUATOR
stage_run() {
  run env ST="$1" PIN="$2" DEF="$3" HF_EXIT_ACTUATOR="${4:-signal}" bash -c '
    hf_succ_stage() { return "$ST"; }
    hf_exit_signal_pin() { HF_EXIT_SIG_WHY="2 claude process(es)"; return "$PIN"; }
    hf_recycle_disarm() { echo DISARM; }
    hf_recycle_owed_record() { echo OWED; }
    emit_recycle_event() { echo "ROW $1 $4"; }
    tty=/dev/ttys777 cmdfile=/x SID=41 log=/l CMD=c RCY_SOURCE_SESSION=s RCY_PP_DEFERRED="$DEF"
    . "$1"
    echo "WENT ON staged=$rcy_staged"' _ "$BATS_TEST_TMPDIR/s.sh"
}

@test "(c) after the stage: a deferred no goes on only staged, pinned and signal-exiting; each missing leg holds before the confirm" {
  stage_frag
  stage_run 0 0 3; [[ "$output" == *"WENT ON staged=1"* ]] || { echo "$output"; false; }
  stage_run 1 0 3; [ "$status" -eq 1 ] || false
  [[ "$output" == *"ROW recycle-held-unreachable "*"the successor could not be staged"* && "$output" == *DISARM* ]] || { echo "$output"; false; }
  stage_run 0 1 3; [ "$status" -eq 1 ] || false
  [[ "$output" == *"no single claude to signal (2 claude process(es))"* ]] || { echo "$output"; false; }
  stage_run 0 0 3 typed; [ "$status" -eq 1 ] || false
  [[ "$output" == *"HF_EXIT_ACTUATOR=typed"* ]] || { echo "$output"; false; }
  # not deferred: today's path, whatever the stage did
  stage_run 1 1 ""; [[ "$output" == *"WENT ON staged=0"* ]] || { echo "$output"; false; }
}

@test "(c) S5: in the typed-/exit arm the deferred hold sits AFTER the subject-gone yield and abandons the debt before holding" {
  body="$(sed -n '/^recycle_fire_commit() {/,/^}/p' "$HF")"
  arm="$(printf '%s\n' "$body" | awk '/^    \*\) # THE SUBJECT, RE-READ \(3 of 3\)/{p=1} p{print} p && /echo "→ exit: typed \/exit/{exit}')"
  [ -n "$arm" ] || false
  printf 'arm() {\n  case "$rcy_sig_rc" in\n%s\n  esac\n  echo TYPED-PATH\n}\n' "$arm" > "$BATS_TEST_TMPDIR/arm.sh"
  run bash -c '
    hf_recycle_subject_gone() { [ "$GONE" = 1 ]; }
    hf_recycle_subject_yield() { echo YIELD; }
    _hf_resume_debt() { echo "DEBT $1"; }
    hf_recycle_hold() { echo "HOLD $1"; exit 1; }
    . "$1"; rcy_sig_rc=1 rcy_debt_sid=s HF_EXIT_SIG_WHY=w
    GONE=1 RCY_PP_DEFERRED=3; ( arm )
    GONE=0 RCY_PP_DEFERRED=3; ( arm )
    GONE=0 RCY_PP_DEFERRED=""; ( arm )' _ "$BATS_TEST_TMPDIR/arm.sh"
  [ "$(printf '%s\n' "$output" | tr '\n' ' ')" = "YIELD DEBT abandon HOLD unreachable → exit: typed /exit — w TYPED-PATH " ] || { echo "$output"; false; }
}

# ── (d) R-10 ─────────────────────────────────────────────────────────────────────────────────────

@test "(d) R-10: after an advisory no, the grace does not revoke until a bounded probe answers; past the cap it does" {
  frag="$(awk '/# R-10: after an advisory no-answer/{p=1} p{print} p && /^      fi$/{exit}' "$HF")"
  [[ "$frag" == *"continue"* ]] || false
  printf 'step() {\n  local n=0\n  while [ "$n" -lt 1 ]; do n=$((n + 1))\n%s\n  echo REVOKE-CHECK; done\n}\n' "$frag" > "$BATS_TEST_TMPDIR/r10.sh"
  run bash -c '
    hf_bounded() { [ "$ANSWERS" = 1 ]; }; sleep() { :; }
    . "$1"; IT2=x rcy_cgrace=20 rcy_cmax=120 rcy_c0=1000 rcy_cshell=1000
    rcy_pp_advisory=1 ANSWERS=0 rcy_cnow=1030; echo "a: $(step)"
    rcy_pp_advisory=1 ANSWERS=1 rcy_cnow=1030; echo "b: $(step)"
    rcy_pp_advisory=0 ANSWERS=0 rcy_cnow=1030; echo "c: $(step)"
    rcy_pp_advisory=1 ANSWERS=0 rcy_cnow=1200; echo "d: $(step)"' _ "$BATS_TEST_TMPDIR/r10.sh"
  [ "$(printf '%s\n' "$output" | tr '\n' ' ')" = "a:  b: REVOKE-CHECK c: REVOKE-CHECK d: REVOKE-CHECK " ] || { echo "$output"; false; }
}

@test "the foreground exports HF_PANE_PROOF_ADVISORY on every detach, 0 unless mode on + remote + verified + staged + signal (S17)" {
  blk="$(awk '/THE WATCHER.S PANE PROBE MAY BE ADVISORY/{p=1} p{print} p && /^  export HF_PANE_PROOF_ADVISORY$/{exit}' "$HF")"
  [ -n "$blk" ] || false
  printf 'adv() {\n%s\n  echo "$HF_PANE_PROOF_ADVISORY"\n}\n' "$blk" > "$BATS_TEST_TMPDIR/adv.sh"
  run bash -c '
    hf_succ_mode() { echo "$MODE"; }; hf_kid_on_for() { [ "$KID" = 1 ]; }; hf_succ_lib_load() { return 0; }
    . "$1"; SID=41
    MODE=resume RCY_REMOTE=1 KID=1; echo "a $(adv)"
    MODE=resume RCY_REMOTE=1 KID=0; echo "b $(adv)"
    MODE=fresh RCY_REMOTE=1 KID=1; echo "c $(adv)"
    MODE=transplant RCY_REMOTE=1 KID=1 HF_EXIT_ACTUATOR=typed; echo "d $(adv)"
    MODE=resume RCY_REMOTE=0 KID=1 HF_EXIT_ACTUATOR=signal; echo "e $(adv)"
    MODE=resume RCY_REMOTE=1 KID=1 CC_PANE_SUCCESSOR=off; echo "f $(adv)"' _ "$BATS_TEST_TMPDIR/adv.sh"
  [ "$(printf '%s\n' "$output" | tr '\n' ' ')" = "a 1 b 0 c 0 d 0 e 0 f 0 " ] || { echo "$output"; false; }
}
