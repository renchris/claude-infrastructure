#!/usr/bin/env bats
# bin/cc-resume-debt — close-resume custody (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D1/D2).
#
# WHAT IS PINNED: a stranded close is retried in a NEW window with the SAME sid; a failed retry
# files exactly ONE runnable backlog row and ONE page (latched across sweeps); proof is two LIVE
# reads from cc-find, never one; a proof discharges the custody row and closes the backlog row; the
# per-sid lock makes a concurrent step a no-op; grace, idempotent open, abandon, surface's
# three-way verdict, and the resolver fill. The REAL bin/cc-custody backs every case; every other
# dependency is a recorder stub under $BATS_TEST_TMPDIR/bin.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="$REPO_ROOT/bin/cc-resume-debt"
  CUSTODY="$REPO_ROOT/bin/cc-custody"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export CC_RESUME_DEBT_DIR="$BATS_TEST_TMPDIR/debt"
  export CC_RESUME_DEBT_HOLD_S=0 CC_RESUME_DEBT_POLL_S=0 CC_RESUME_DEBT_GRACE_S=240
  export CC_RESUME_DEBT_WAIT_S=0 CC_RESUME_DEBT_NOW=1000
  S="$BATS_TEST_TMPDIR/bin"; mkdir -p "$S"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  SID=11111111-2222-4333-8444-555555555555
  export T="$BATS_TEST_TMPDIR"

  # cc-find: pops one liveness word per call from $T/find.seq (the last word repeats).
  cat > "$S/find" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$T/find.log"
st="$(head -1 "$T/find.seq" 2>/dev/null)"; st="${st:-DEAD}"
if [ "$(wc -l < "$T/find.seq" 2>/dev/null || echo 0)" -gt 1 ]; then
  tail -n +2 "$T/find.seq" > "$T/find.seq.tmp" && mv "$T/find.seq.tmp" "$T/find.seq"
fi
printf '%s\t42\tnext3\t/cfg\t/wt\t%s\tidle\n' "$1" "$st"
SH
  cat > "$S/relaunch" <<'SH'
#!/usr/bin/env bash
printf '%s SETTLING=%s\n' "$*" "${CC_RESUME_DEBT_SETTLING:-}" >> "$T/relaunch.log"
exit "${RELAUNCH_RC:-0}"
SH
  cat > "$S/backlog" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$T/backlog.log"
[ "$1" = needs ] && printf 'filed\nabcdef012345\n'
exit "${BACKLOG_RC:-0}"
SH
  cat > "$S/notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$T/notify.log"
SH
  cat > "$S/pane" <<'SH'
#!/usr/bin/env bash
[ -n "${PANE_RC:-}" ] && exit "$PANE_RC"
printf '%b' "${PANE_LIST:-}"
SH
  cat > "$S/resolve" <<'SH'
#!/usr/bin/env bash
printf 'account=next4\nconfig_dir=/fx/.claude-next4\ncwd=%s\n' "$RESOLVED_CWD"
SH
  chmod +x "$S"/*
  export CC_RESUME_DEBT_FIND_BIN="$S/find" CC_RESUME_DEBT_RELAUNCH="$S/relaunch"
  export CC_RESUME_DEBT_BACKLOG_BIN="$S/backlog" CC_RESUME_DEBT_NOTIFY_BIN="$S/notify"
  export CC_RESUME_DEBT_PANE_BIN="$S/pane" CC_RESUME_DEBT_RESOLVE_BIN="$S/resolve"
  export RESOLVED_CWD="$WT"
  printf 'DEAD\n' > "$T/find.seq"
}

open_debt() { "$BIN" open --sid "$SID" --cwd "$WT" --account next3 --cfg /fx/.claude-next3 --pane 42 --by lr-upgrade --why "upgrade mover"; }
state() { jq -r .state "$CC_RESUME_DEBT_DIR/meta/$SID.json"; }
custody_open() { CC_CUSTODY_DIR="$CC_RESUME_DEBT_DIR" "$CUSTODY" count --open; }
lines() { [ -f "$1" ] && grep -c -- "$2" "$1" || echo 0; }

@test "stranded debt relaunches in a new window with the SAME session id" {
  open_debt
  [ "$(custody_open)" = 1 ]
  run "$BIN" settle --sid "$SID" --wait 5
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qx "next3 $WT $SID SETTLING=1" "$T/relaunch.log"
  [ "$(jq -r .attempts "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = 1 ]
}

@test "second failure files ONE backlog needs row with a runnable resume command" {
  open_debt
  run "$BIN" settle --sid "$SID" --wait 5
  [ "$status" -eq 1 ]
  [ "$(state)" = escalated ]
  grep -q "^needs Resume stranded session $SID (wt, account next3) — lr-upgrade closed it and the relaunch failed (debt opened 1970-01-01T00:16:40Z)" "$T/backlog.log"
  grep -q -- "--project claude-infrastructure" "$T/backlog.log"
  grep -q -- "--run bash $HOME/.claude/scripts/boot-resume-launch.sh next3 $WT $SID\$" "$T/backlog.log"
  grep -q -- "--page STRANDED SESSION $SID — relaunch failed; run: cc-do abcdef012345" "$T/notify.log"
  [ "$(jq -r .backlog_id "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = abcdef012345 ]
  [ "$(jq -r .page_verdict "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = reached ]
  "$BIN" sweep; "$BIN" sweep
  [ "$(lines "$T/backlog.log" '^needs')" = 1 ]
  [ "$(lines "$T/notify.log" '--page')" = 1 ]
  [ "$(lines "$T/relaunch.log" "$SID")" = 1 ]
}

@test "a failed backlog call still pages, with the raw command, and records no id" {
  open_debt
  BACKLOG_RC=1 run "$BIN" settle --sid "$SID" --wait 5
  [ "$status" -eq 1 ]
  [ "$(jq -r .backlog_id "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = "" ]
  grep -q -- "run: bash $HOME/.claude/scripts/boot-resume-launch.sh" "$T/notify.log"
  jq -e '.events | map(.note) | any(test("backlog needs rc=1"))' "$CC_RESUME_DEBT_DIR/meta/$SID.json"
}

@test "relaunch rc≠0 escalates without waiting WAIT" {
  export CC_RESUME_DEBT_WAIT_S=100000
  open_debt
  RELAUNCH_RC=9 run "$BIN" settle --sid "$SID" --wait 5
  [ "$status" -eq 1 ]
  [ "$(state)" = escalated ]
  [ "$(jq -r .relaunch_rc "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = 9 ]
}

@test "relaunch rc 0 inside WAIT stays retrying (the control for the rc≠0 case)" {
  export CC_RESUME_DEBT_WAIT_S=100000
  open_debt
  run "$BIN" settle --sid "$SID" --wait 1
  [ "$status" -eq 3 ]
  [ "$(state)" = retrying ]
  [ ! -f "$T/backlog.log" ]
}

@test "proof discharges: LIVE twice ⇒ proven, custody closed, escalated backlog row gets done" {
  open_debt
  "$BIN" settle --sid "$SID" --wait 5 || true
  [ "$(state)" = escalated ]
  [ "$(custody_open)" = 1 ]
  printf 'LIVE\n' > "$T/find.seq"
  run "$BIN" step --sid "$SID"
  [ "$status" -eq 0 ]
  [ "$(state)" = proven ]
  [ "$(custody_open)" = 0 ]
  grep -qx "done abcdef012345 --evidence proven LIVE by cc-find" "$T/backlog.log"
}

@test "a one-read LIVE that is DEAD on the hold re-read is NOT proof" {
  open_debt
  printf 'LIVE\nDEAD\n' > "$T/find.seq"
  run "$BIN" prove --sid "$SID" --hold 0
  [ "$status" -eq 1 ]
  printf 'LIVE\nDEAD\n' > "$T/find.seq"
  "$BIN" step --sid "$SID"
  [ "$(state)" = open ]
  printf 'LIVE\nLIVE\n' > "$T/find.seq"
  run "$BIN" prove --sid "$SID" --hold 0
  [ "$status" -eq 0 ]
}

@test "a held lock makes step a no-op (no relaunch); a stale lock is taken" {
  open_debt
  export CC_RESUME_DEBT_NOW=5000
  mkdir -p "$CC_RESUME_DEBT_DIR/lock/$SID"
  run "$BIN" step --sid "$SID"
  [ "$status" -eq 0 ]
  [ ! -f "$T/relaunch.log" ]
  [ "$(state)" = open ]
  touch -t 202001010000 "$CC_RESUME_DEBT_DIR/lock/$SID"
  "$BIN" step --sid "$SID"
  [ "$(state)" = retrying ]
  [ "$(lines "$T/relaunch.log" "$SID")" = 1 ]
  [ ! -d "$CC_RESUME_DEBT_DIR/lock/$SID" ]
}

@test "a sid that proves LIVE is never relaunched, even past grace" {
  open_debt
  export CC_RESUME_DEBT_NOW=5000
  printf 'LIVE\n' > "$T/find.seq"
  "$BIN" step --sid "$SID"
  [ "$(state)" = proven ]
  [ ! -f "$T/relaunch.log" ]
}

@test "open is idempotent per sid" {
  m1="$(open_debt)"; m2="$(open_debt)"
  [ "$m1" = "resume:$SID:1000" ]
  [ "$m1" = "$m2" ]
  [ "$(custody_open)" = 1 ]
}

@test "abandon closes the debt and sweep ignores proven and abandoned debts" {
  open_debt
  run "$BIN" abandon --sid "$SID" --why "close never happened"
  [ "$status" -eq 0 ]
  [ "$(state)" = abandoned ]
  [ "$(custody_open)" = 0 ]
  SID2=99999999-2222-4333-8444-555555555555
  "$BIN" open --sid "$SID2" --cwd "$WT" --account next3 --by t
  "$BIN" discharge --sid "$SID2" --why test
  export CC_RESUME_DEBT_NOW=5000
  run "$BIN" sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$T/relaunch.log" ]
}

@test "grace is respected: no relaunch before GRACE, relaunch at GRACE" {
  open_debt
  CC_RESUME_DEBT_NOW=1239 "$BIN" step --sid "$SID"
  [ "$(state)" = open ]
  [ ! -f "$T/relaunch.log" ]
  CC_RESUME_DEBT_NOW=1240 run "$BIN" sweep
  [ "$output" = "$SID retrying" ]
}

@test "surface: present / absent / enumerator failure → 0 / 1 / 3" {
  PANE_LIST='p1\np2\n' run "$BIN" surface --pane p2
  [ "$status" -eq 0 ]
  PANE_LIST='p1\np2\n' run "$BIN" surface --pane p
  [ "$status" -eq 1 ]
  PANE_RC=4 run "$BIN" surface --pane p2
  [ "$status" -eq 3 ]
  PANE_LIST='' run "$BIN" surface --pane p2
  [ "$status" -eq 3 ]
}

@test "open fills account/cfg/cwd from the RESOLVE stub; explicit flags win" {
  "$BIN" open --sid "$SID" --by t
  f="$CC_RESUME_DEBT_DIR/meta/$SID.json"
  [ "$(jq -r .account "$f")" = next4 ]
  [ "$(jq -r .cfg "$f")" = /fx/.claude-next4 ]
  [ "$(jq -r .cwd "$f")" = "$WT" ]
  SID2=99999999-2222-4333-8444-555555555555
  "$BIN" open --sid "$SID2" --account next2 --by t
  [ "$(jq -r .account "$CC_RESUME_DEBT_DIR/meta/$SID2.json")" = next2 ]
}

@test "a vanished subject cwd keys the custody row on HOME, and the debt is still opened" {
  run "$BIN" open --sid "$SID" --cwd "$BATS_TEST_TMPDIR/gone" --account next3 --by t
  [ "$status" -eq 0 ]
  [ "$(custody_open)" = 1 ]
  [ "$(jq -r .cwd "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = "$BATS_TEST_TMPDIR/gone" ]
}

@test "list --open / --escalated / --json read the meta store" {
  open_debt
  [ "$("$BIN" list --open --json | jq length)" = 1 ]
  [ "$("$BIN" list --escalated --json | jq length)" = 0 ]
  "$BIN" settle --sid "$SID" --wait 5 || true
  [ "$("$BIN" list --escalated --json | jq -r '.[0].sid')" = "$SID" ]
  "$BIN" list | grep -q "^$SID	escalated	1	abcdef012345	resume:$SID:1000\$"
}

@test "usage errors: missing --sid is rc 2; a path-shaped sid is refused" {
  run "$BIN" open
  [ "$status" -eq 2 ]
  run "$BIN" step --sid ../x
  [ "$status" -eq 2 ]
  run "$BIN" discharge --sid nobody --why x
  [ "$status" -eq 0 ]
}
