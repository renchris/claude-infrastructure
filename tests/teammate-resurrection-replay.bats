#!/usr/bin/env bats
# shellcheck disable=SC2016  # stubs are written verbatim
# REPLAY of the 2026-10-16 teammate resurrection (docs/research/teammate-resurrection-2026-10-16/
# REPORT.md § 3 B, § 4.2 steps 4-5): teammate web-next16 (5423f92a) approved its lead's
# shutdown_request; the upgrade drainer read the death as a failed relaunch and called
# `cc-resume-debt settle`, which reopened the already-PROVEN debt as "no prior debt" and relaunched
# the session through boot-resume-launch.sh in a NEW window with no team flags: an orphan.
#
# WHAT RUNS FOR REAL: bin/cc-resume-debt, scripts/boot-resume-launch.sh (as cc-resume-debt's
# relaunch child, under /bin/bash 3.2), and through it lr-recon-fence.sh, lr-lib.sh
# (lr_team_member) and lr-predicate.sh, plus the real bin/cc-custody. RECORDER STUBS: kitty (a window
# is a `kitty @ launch` argv in kitty.argv), reso-resume-one, cc-find, cc-backlog and cc-notify.
#
# HERMETIC: HOME and every store (debt, custody, recon, registry, crash log, pending-launch,
# admission) are fixtures under BATS_TEST_TMPDIR. Nothing opens a window or reads the operator's
# state.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RD="$REPO/bin/cc-resume-debt"
  BRL="$REPO/scripts/boot-resume-launch.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export CC_CRASH_LOG="$BATS_TEST_TMPDIR/claude-crashes.jsonl"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export LR_STATE_DIR="$HOME/.reso/limit-recover" LR_RECON_ROOT="$HOME/.reso/limit-recover/recon"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PENDING_LAUNCH_DIR="$BATS_TEST_TMPDIR/pending-launch"
  export CC_BOOT_RESUME_STATE_DIR="$BATS_TEST_TMPDIR/boot-resume"
  unset LR_LAUNCH_LOCK LR_RECORD_ID CC_RESUME_TEAMMATE_GUARD CC_RESUME_MEMBER_HINT CC_RESUME_DEBT_SETTLING
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID CC_SESSION_ID KITTY_PID KITTY_LISTEN_ON CC_TERM_KITTY_TO
  unset IT2_WRAPPER_NO_KITTY LR_PREDICATE_PY LR_LIB_DIR LR_CONFIG_DIRS CC_BOOT_RESUME_MODE
  export T="$BATS_TEST_TMPDIR"
  S="$T/stubs"; mkdir -p "$S"

  # kitty: the launcher runs inside kitty; a window is one `@ launch` line in kitty.argv.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/kitty.argv"\nexit 0\n' "$T" > "$S/kitty"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/resume-one.log"\nexit 0\n' "$T" > "$S/resume-one"
  # cc-find: one liveness word per call from find.seq (the last word repeats).
  cat > "$S/find" <<'SH'
#!/bin/bash
st="$(head -1 "$T/find.seq" 2>/dev/null)"; st="${st:-DEAD}"
if [ "$(wc -l < "$T/find.seq" 2>/dev/null || echo 0)" -gt 1 ]; then
  tail -n +2 "$T/find.seq" > "$T/find.seq.tmp" && mv "$T/find.seq.tmp" "$T/find.seq"
fi
printf '%s\t217\tnext2\t/cfg\t/wt\t%s\tidle\n' "$1" "$st"
SH
  cat > "$S/backlog" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$T/backlog.log"
[ "$1" = needs ] && printf 'abcdef012345\n'
exit 0
SH
  cat > "$S/notify" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$T/notify.log"
printf 'cc-notify: verdict=delivered\n' >&2
SH
  # cc-resume-resolve: settle's reopen refills account/cfg/cwd from it, as it did on 2026-10-16.
  cat > "$S/resolve" <<'SH'
#!/bin/bash
printf 'account=next2\nconfig_dir=%s\ncwd=%s\n' "$RESOLVED_CFG" "$RESOLVED_CWD"
SH
  chmod +x "$S"/*
  export CC_RESUME_DEBT_RESOLVE_BIN="$S/resolve"
  export KITTY_WINDOW_ID=31 CC_TERM_KITTY="$S/kitty" CC_RESUME_ONE_BIN="$S/resume-one"
  export CC_RESUME_DEBT_RELAUNCH="/bin/bash $BRL"
  export CC_RESUME_DEBT_BIN="$T/no-cc-resume-debt"   # brl_open_debt: never the real ledger
  export CC_RESUME_DEBT_DIR="$T/debt" CC_RESUME_DEBT_FIND_BIN="$S/find"
  export CC_RESUME_DEBT_BACKLOG_BIN="$S/backlog" CC_RESUME_DEBT_NOTIFY_BIN="$S/notify"
  export CC_RESUME_DEBT_KITTY_BIN="$S/kitty" CC_RESUME_DEBT_HANDOFFS_LOG="$T/handoffs.jsonl"
  export CC_RESUME_DEBT_HOLD_S=0 CC_RESUME_DEBT_POLL_S=0 CC_RESUME_DEBT_WAIT_S=100000 CC_RESUME_DEBT_NOW=1792193085

  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$BATS_TEST_DIRNAME/helpers/member-transcript.sh"
  # NOT the incident's real sid: H(sid) reads the live `ps`, and that session's orphan still holds
  # `--resume 5423f92a-…` on the box, so the real id read "1 live holder" — a refusal for the wrong reason.
  SID=fx5423f92a-9089-4690-8c85-28ffc4018768
  WT="$T/wt-pool-5"; mkdir -p "$WT"
  CFG="$HOME/.claude-secondary"
  TX="$CFG/projects/$(printf %s "$WT" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')/$SID.jsonl"
  export RESOLVED_CFG="$CFG" RESOLVED_CWD="$WT"
}

meta() { jq -r "$1" "$CC_RESUME_DEBT_DIR/meta/$SID.json"; }
windows() { grep -c -- '^@ launch' "$T/kitty.argv" 2>/dev/null || echo 0; }
# Debt #1 as the incident had it: opened by the recycle before /exit, then PROVEN by cc-find.
debt1_proven() { # [open args…]
  "$RD" open --sid "$SID" --cfg "$CFG" --cwd "$WT" --account next2 --pane 217 \
    --by "handoff-fire --recycle" --why "recycle of pane 217 (resume-launcher, same sid)" "$@" >/dev/null
  printf 'LIVE\n' > "$T/find.seq"
  "$RD" step --sid "$SID"
  [ "$(meta .state)" = proven ] || { cat "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  printf 'DEAD\n' > "$T/find.seq"    # the member approved its shutdown and its pane closed
}

@test "REPLAY 2026-10-16 5423f92a: a member debt proven at T and re-settled opens no window" {
  mk_member_transcript "$TX" "$SID" session-3cbb68e5 web-next16
  debt1_proven --member yes
  # the drainer's call, verbatim in shape: no --since, no --member
  run "$RD" settle --sid "$SID" --wait 300
  [ "$status" -eq 4 ] || { echo "$output"; cat "$CC_RESUME_DEBT_DIR/log/$SID.log" 2>/dev/null; false; }
  [ "$(windows)" = 0 ] || { cat "$T/kitty.argv"; false; }
  [ ! -e "$T/resume-one.log" ]
  [ "$(meta .state)" = abandoned ]
  meta '.events[-1].note' | grep -q 'Agent Teams member'
  [ ! -e "$T/backlog.log" ]
  [ ! -e "$T/notify.log" ]
  [ ! -e "$CC_PENDING_LAUNCH_DIR/$SID.json" ]
  grep -q 'closed as an Agent Teams member' "$CC_RESUME_DEBT_DIR/log/$SID.log"   # the launcher refused, not the debt
}

@test "REPLAY control: the same chain with the member records stripped relaunches in a NEW window" {
  mk_plain_transcript "$TX" "$SID"
  debt1_proven
  run "$RD" settle --sid "$SID" --wait 0
  [ "$(windows)" = 1 ] || { echo "$output"; cat "$CC_RESUME_DEBT_DIR/log/$SID.log" "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  grep -q -- "--type=os-window" "$T/kitty.argv"
  grep -q -- "$SID" "$T/kitty.argv"
  [ "$(meta .state)" = retrying ]
  [ "$(meta .relaunch_rc)" = 0 ]
}

@test "REPLAY R2-H1: a plain-argv member head (--member no) is relaunched" {
  mk_member_transcript "$TX" "$SID" session-3cbb68e5 web-next16
  debt1_proven --member no
  run "$RD" settle --sid "$SID" --wait 0
  [ "$(windows)" = 1 ] || { echo "$output"; cat "$CC_RESUME_DEBT_DIR/log/$SID.log"; false; }
  [ "$(meta .member)" = no ]
  [ "$(meta .relaunch_rc)" = 0 ]
}

@test "REPLAY R2-H1: no hint + a member head escalates ONCE with a CC_RESUME_TEAMMATE_GUARD=off run line" {
  mk_member_transcript "$TX" "$SID" session-3cbb68e5 web-next16
  debt1_proven
  run "$RD" settle --sid "$SID" --wait 300
  [ "$status" -eq 1 ] || { echo "$output"; cat "$CC_RESUME_DEBT_DIR/log/$SID.log"; false; }
  [ "$(windows)" = 0 ] || { cat "$T/kitty.argv"; false; }
  [ "$(meta .state)" = escalated ]
  [ "$(meta .relaunch_rc)" = 7 ]
  grep -q -- "--run CC_RESUME_TEAMMATE_GUARD=off bash $HOME/.claude/scripts/boot-resume-launch.sh next2 $WT $SID\$" "$T/backlog.log" \
    || { cat "$T/backlog.log"; false; }
  grep -q "an Agent Teams member ($TX)" "$CC_RESUME_DEBT_DIR/log/$SID.log"
  "$RD" sweep >/dev/null; "$RD" sweep >/dev/null
  [ "$(grep -c '^needs' "$T/backlog.log")" = 1 ]
  [ "$(windows)" = 0 ]
}
