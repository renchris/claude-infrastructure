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
  # settle's --wait is its one WALL-CLOCK deadline (CC_RESUME_DEBT_NOW pins only the state machine),
  # and settle returns the moment the state decides — so a case that expects a DECIDED outcome gets a
  # ceiling it can never meet on a healthy box. `--wait 5` read rc 3 (undecided) at load ~150, where
  # one open→retrying→escalated walk took 12-28 s. The rc-3 control keeps its own short wait.
  SETTLE_WAIT=300
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
  run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qx "next3 $WT $SID SETTLING=1" "$T/relaunch.log"
  [ "$(jq -r .attempts "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = 1 ]
}

@test "second failure files ONE backlog needs row with a runnable resume command" {
  open_debt
  run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
  [ "$status" -eq 1 ]
  [ "$(state)" = escalated ]
  grep -q "^needs Resume stranded session $SID (wt, account next3) — lr-upgrade closed it and the relaunch failed (debt opened 1970-01-01T00:16:40Z)" "$T/backlog.log"
  grep -q -- "--project claude-infrastructure" "$T/backlog.log"
  grep -q -- "--run bash $HOME/.claude/scripts/boot-resume-launch.sh next3 $WT $SID\$" "$T/backlog.log"
  # the message goes to the stranded session's own mailbox (cc-notify has no --page; §D4)
  grep -qx -- "--from cc-resume-debt $SID STRANDED SESSION $SID — relaunch failed; run: cc-do abcdef012345" "$T/notify.log"
  [ "$(jq -r .backlog_id "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = abcdef012345 ]
  [ "$(jq -r .page_verdict "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = reached ]
  "$BIN" sweep; "$BIN" sweep
  [ "$(lines "$T/backlog.log" '^needs')" = 1 ]
  [ "$(lines "$T/notify.log" 'STRANDED SESSION')" = 1 ]
  [ "$(lines "$T/relaunch.log" "$SID")" = 1 ]
}

@test "a failed backlog call still pages, with the raw command, and records no id" {
  open_debt
  BACKLOG_RC=1 run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
  [ "$status" -eq 1 ]
  [ "$(jq -r .backlog_id "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = "" ]
  grep -q -- "run: bash $HOME/.claude/scripts/boot-resume-launch.sh" "$T/notify.log"
  jq -e '.events | map(.note) | any(test("backlog needs rc=1"))' "$CC_RESUME_DEBT_DIR/meta/$SID.json"
}

@test "relaunch rc≠0 escalates without waiting WAIT" {
  export CC_RESUME_DEBT_WAIT_S=100000
  open_debt
  RELAUNCH_RC=9 run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
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
  "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT" || true
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
  "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT" || true
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

@test "settle with NO prior debt opens one from the resolver and relaunches the same sid" {
  # An older mover (or a failed open) closed the session without a debt on file: settle must not
  # be a silent no-op — the caller is reporting a close it could not undo.
  run "$BIN" settle --sid "$SID" --wait 0
  [ -f "$CC_RESUME_DEBT_DIR/meta/$SID.json" ]
  [ "$(jq -r .account "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = next4 ]
  grep -q "^next4 $WT $SID SETTLING=1$" "$T/relaunch.log"
  jq -r '.events[0].note' "$CC_RESUME_DEBT_DIR/meta/$SID.json" | grep -q 'settle (no prior debt)'
}

@test "a FRESH-brief debt is discharged by a LIVE successor holding its pane (new sid)" {
  "$BIN" open --sid "$SID" --cwd "$WT" --account next3 --pane 42 --mode fresh --by "handoff-fire --recycle"
  printf 'DEAD\nLIVE\n' > "$T/find.seq"    # closed sid DEAD, then the pane read: a successor LIVE
  run "$BIN" step --sid "$SID"
  [ "$(state)" = proven ]
  grep -qx 42 "$T/find.log"
  [ ! -f "$T/relaunch.log" ]
}

@test "a RESUME debt is NOT discharged by some other session in its pane (control)" {
  "$BIN" open --sid "$SID" --cwd "$WT" --account next3 --pane 42 --by lr-upgrade
  [ "$(jq -r .mode "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = resume ]
  printf 'DEAD\nLIVE\n' > "$T/find.seq"
  run "$BIN" step --sid "$SID"
  [ "$(state)" = open ]
  ! grep -qx 42 "$T/find.log"
}

@test "an unknown --mode is refused" {
  run "$BIN" open --sid "$SID" --mode sideways
  [ "$status" -eq 2 ]
}

# ── RECYCLE_KEYSTROKELESS_DELIVERY §D4: recovery debts (settle --recovery <packet>) ──────────────
# The packet is the shape U4's rcy_recovery_packet writes; this suite reads only the fields
# cc-resume-debt consumes (token, refire_cmd) and the sibling <sid>.prompt.md.
mk_packet() {
  PKD="$T/recycle-failed"; mkdir -p "$PKD"
  PKT="$PKD/$SID.json"; TOK="recycle-recovery:$SID:1791000000"
  jq -n --arg tok "$TOK" '{failed_at:"2026-10-09T05:31:00Z", class:"relaunch-failed", pane:"44",
    token:$tok, refire_cmd:"bash /h/.claude/scripts/handoff-fire.sh --recycle --recovery-of \($tok)"}' > "$PKT"
  printf 'Your self-recycle FAILED. token %s\n' "$TOK" > "$PKD/$SID.prompt.md"
}
# [pane] — the find stub reports every row in pane 42, so the default 44 has NO successor in it.
open_recovery_debt() { # a real cfg dir, so the transcript proof has somewhere to look
  CFGD="$T/cfg"; mkdir -p "$CFGD/projects/p"
  "$BIN" open --sid "$SID" --cwd "$WT" --account next3 --cfg "$CFGD" --pane "${1:-44}" --by handoff-fire --why "recycle failed"
}
transcript() { # <jsonl lines…>
  printf '%s\n' "$@" > "$CFGD/projects/p/$SID.jsonl"
}

@test "D4: settle --recovery stores the packet and its prompt reaches the RELAUNCH argv" {
  mk_packet; open_recovery_debt
  run "$BIN" settle --sid "$SID" --recovery "$PKT" --wait "$SETTLE_WAIT"
  [ "$(jq -r .recovery "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = "$PKT" ]
  grep -qx "next3 $WT $SID --prompt-file $PKD/$SID.prompt.md SETTLING=1" "$T/relaunch.log" || { cat "$T/relaunch.log"; false; }
}

@test "D4: a plain settle (no packet) passes NO --prompt-file (control)" {
  open_recovery_debt
  run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
  grep -qx "next3 $WT $SID SETTLING=1" "$T/relaunch.log" || { cat "$T/relaunch.log"; false; }
}

@test "D4: a missing --recovery packet is noted and the settle still runs as a plain debt" {
  open_recovery_debt
  run "$BIN" settle --sid "$SID" --recovery "$T/absent.json" --wait "$SETTLE_WAIT"
  [[ "$output" == *"no such packet"* ]] || { echo "$output"; false; }
  grep -qx "next3 $WT $SID SETTLING=1" "$T/relaunch.log"
}

@test "D4: with a packet, LIVE alone does NOT discharge — the 2026-10-09 false proof" {
  mk_packet; open_recovery_debt
  printf 'LIVE\n' > "$T/find.seq"            # the original is alive (and idle) on every read
  run "$BIN" settle --sid "$SID" --recovery "$PKT" --wait "$SETTLE_WAIT"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  [ "$(state)" = escalated ]
  # control: the same LIVE reads DO discharge a plain debt
  rm -rf "$CC_RESUME_DEBT_DIR"; printf 'LIVE\n' > "$T/find.seq"
  open_recovery_debt
  run "$BIN" settle --sid "$SID" --wait "$SETTLE_WAIT"
  [ "$status" -eq 0 ] && [ "$(state)" = proven ]
}

@test "D4: the token in a user record FOLLOWED by an assistant record discharges; the token alone does not" {
  mk_packet; open_recovery_debt
  transcript '{"type":"user","message":{"role":"user","content":"Your self-recycle FAILED. token '"$TOK"'"}}'
  run "$BIN" settle --sid "$SID" --recovery "$PKT" --wait "$SETTLE_WAIT"
  [ "$(state)" = escalated ] || { cat "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  transcript '{"type":"assistant","message":{"content":"earlier, before the token"}}' \
             '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"token '"$TOK"'"}]}}' \
             '{"type":"assistant","message":{"content":"Checking for a live successor, then re-firing."}}'
  run "$BIN" step --sid "$SID"
  [ "$(state)" = proven ] || { cat "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  jq -e '.events[-1].note | test("recovery token answered")' "$CC_RESUME_DEBT_DIR/meta/$SID.json"
  grep -q '^done abcdef012345' "$T/backlog.log"
}

@test "D4: a live successor holding the pane discharges a recovery debt" {
  mk_packet; open_recovery_debt 42
  "$BIN" settle --sid "$SID" --recovery "$PKT" --wait 0 >/dev/null 2>&1 || true
  printf 'LIVE\n' > "$T/find.seq"            # the pane read (42) reports a LIVE successor sid
  run "$BIN" step --sid "$SID"
  [ "$(state)" = proven ] || { cat "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  grep -qx 42 "$T/find.log"
}

@test "D4: _escalate never passes --page; the row's title and --run carry refire_cmd and the packet" {
  mk_packet; open_recovery_debt
  run "$BIN" settle --sid "$SID" --recovery "$PKT" --wait "$SETTLE_WAIT"
  [ "$(state)" = escalated ]
  ! grep -q -- '--page' "$T/notify.log" || { cat "$T/notify.log"; false; }
  grep -q -- "^--from cc-resume-debt $SID STRANDED SESSION $SID .*recovery packet: $PKT" "$T/notify.log"
  grep -q -- "^needs Re-fire the failed recycle of session $SID .*packet $PKT; re-fire: bash /h/.claude/scripts/handoff-fire.sh --recycle --recovery-of $TOK" "$T/backlog.log"
  grep -q -- "--run bash /h/.claude/scripts/handoff-fire.sh --recycle --recovery-of $TOK  # recovery packet: $PKT\$" "$T/backlog.log"
}

@test "D4: H(sid)>0 deferrals are counted — the MAX_DEFER-th becomes a failed attempt, then escalates" {
  open_recovery_debt
  printf 'lr_holder_count() { echo 1; }\n' > "$T/lr-lib-held.sh"
  export CC_RESUME_DEBT_LR_LIB="$T/lr-lib-held.sh" CC_RESUME_DEBT_GRACE_S=0 CC_RESUME_DEBT_MAX_DEFER=3
  "$BIN" step --sid "$SID"; "$BIN" step --sid "$SID"
  [ "$(state)" = open ] && [ "$(jq -r .deferrals "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = 2 ]
  "$BIN" step --sid "$SID"
  [ "$(state)" = retrying ] || { cat "$CC_RESUME_DEBT_DIR/meta/$SID.json"; false; }
  [ "$(jq -r .relaunch_rc "$CC_RESUME_DEBT_DIR/meta/$SID.json")" = 75 ]
  [ ! -f "$T/relaunch.log" ]                 # never launched beside a live holder
  "$BIN" step --sid "$SID"
  [ "$(state)" = escalated ]
}
