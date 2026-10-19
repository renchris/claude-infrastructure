#!/usr/bin/env bats
# wrap-ledger.sh — the research-pending ⛔ (REPORT A3, docs/research/
# research-pending-implementation-close-2026-10-18/REPORT.md §3 + A3).
#
# A session that re-checks FOREIGN open class-C packets (`cc-decide recheck` appends a
# `.rechecks[]` entry carrying this session's sid, a conviction and a receipt) has produced work
# that waits on the operator, yet every ⛔ arm keys on `.session_sid == $sid`, so it closed ✅
# "nothing to do". The ledger now counts THIS TURN's re-checks — entries stamped at or after the
# last genuine human prompt — as a ⛔ that rides the ✅-eligible path: dirty/unlanded still win, a
# filed-by-me ⛔ still wins byte for byte, and the next human prompt returns the rung to git state.
#
# cc-decide is the REAL binary over a per-test CC_DECISIONS_DIR; packets are hand-written in the
# shape `cc-decide recheck` writes. Timestamps are absolute PAST (a future one trips the gate's
# wall-clock ratchet); only their order matters.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export WRAP_TRUNK="origin/main"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/absent-cc-backlog"
  SID="sess-11111111-2222-3333-4444-555555555555"
  OTHER="sess-99999999-8888-7777-6666-555555555555"
  # Hermetic live layer, migrations and postland (see tests/wrap-ledger.bats setup for why each).
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  export WRAP_LIVE_ROOT="$BATS_TEST_TMPDIR/no-live-root"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  unset WRAP_LIVE_BUDGET_COMMITS WRAP_LIVE_BUDGET_MIN
  # ⛔: the REAL cc-decide over a per-test store (the operator's live store is never read).
  export CC_DECIDE_BIN="$REPO/bin/cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  mkdir -p "$CC_DECISIONS_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_CONVICTION_EPOCH="2026-09-01T00:00:00Z"
  unset CLAUDE_CODE_SESSION_ID
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"
  mkdir -p "$CC_WF_TEAM_ROOTS"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  mkdir -p "$CC_FIRED_DIR"
  unset CC_PANE_ID ITERM_SESSION_ID WRAP_TRANSCRIPT
  # The memo keys on the transcript, which every case here passes; off keeps cases independent.
  export WRAP_CACHE=off WRAP_SESSION_ID="$SID"
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  # clean · landed · DoD all checked · gate green — the ✅-eligible state
  printf -- '- [x] item one\n' > "$BATS_TEST_TMPDIR/dod-ok.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod-ok.md"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# an OPEN class-C packet. $1 id · $2 owner sid · $3 what_plain · $4 rechecks JSON array
mk_packet() {
  jq -n --arg id "$1" --arg sid "$2" --arg what "$3" --argjson rc "$4" \
    '{id:$id, created:"2026-09-20T00:00:00Z", class:"C", session_sid:$sid, what_plain:$what,
      options:[], status:"open", veto_deadline:"", conviction:80, receipt:"/tmp/r.md", rechecks:$rc}' \
    > "$CC_DECISIONS_DIR/$1.json"
}
# one re-check entry, the shape `cc-decide recheck` appends. $1 sid · $2 ts
rc_entry() {
  jq -nc --arg sid "$1" --arg ts "$2" \
    '{sid:$sid, ts:$ts, conviction:91, receipt:"/tmp/rpic/receipt.md", recommendation:"approve", tier:"signoff"}'
}

# transcript records
t_human()    { printf '{"type":"user","timestamp":"%s","origin":{"kind":"human"},"message":{"role":"user","content":"%s"}}\n' "$1" "${2:-check the open decisions}"; }
t_queued()   { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"and one more"}}\n' "$1"; }
t_notify()   { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"<task-notification><status>completed</status></task-notification>"}}\n' "$1"; }
t_stopfb()   { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"Stop hook feedback:\\nfinish the work"}}\n' "$1"; }
t_toolres()  { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}\n' "$1"; }

H0="2026-10-18T10:00:00.000Z"    # the turn's human prompt
S1="2026-10-18T10:05:00Z"        # the re-check stamp, inside that turn
L2="2026-10-18T10:10:00.000Z"    # a LATER record

one_stamp() { mk_packet pkt-a "$OTHER" "ship the reaper in act mode" "[$(rc_entry "$SID" "$S1")]"; }

@test "stamp after the last human prompt ⇒ RUNG=⛔ with the research wording (was ✅)" {
  one_stamp
  { t_human "$H0"; t_toolres "$S1"; } > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" READOUT)" = "⛔ Blocked — research done, implementation pending; need your call: ship the reaper in act mode." ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "1" ]
  [ "$(field "$output" RECHECKED_IDS)" = "pkt-a" ]
  [ "$(field "$output" RECHECKED_SRC)" = "ok" ]
}

@test "a later human prompt ⇒ RUNG=✅, BLOCKED_RECHECKED=0" {
  one_stamp
  { t_human "$H0"; t_human "$L2" "thanks, what next"; } > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
  [ "$(field "$output" RECHECKED_SRC)" = "ok" ]
}

@test "a later origin-less human prompt (legacy record) ⇒ RUNG=✅" {
  one_stamp
  { t_human "$H0"; printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"ok go"}}\n' "$L2"; } > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
}

@test "a later queued prompt attachment ⇒ RUNG=✅" {
  one_stamp
  { t_human "$H0"; t_queued "$L2"; } > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
}

@test "CONTROL: a later task-notification or Stop-hook-feedback record does NOT launder the stamp ⇒ still ⛔" {
  one_stamp
  { t_human "$H0"; t_notify "$L2"; t_stopfb "$L2"; t_toolres "$L2"; } > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "1" ]
}

@test "CONTROL: the latest re-checker is another session ⇒ not counted" {
  mk_packet pkt-a "$OTHER" "ship the reaper" "[$(rc_entry "$SID" "$S1"), $(rc_entry "$OTHER" "2026-10-18T10:06:00Z")]"
  t_human "$H0" > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
}

@test "CONTROL: my entry lacks a conviction or a receipt ⇒ not counted, UNCONVICTED_PKTS unchanged" {
  mk_packet pkt-a "$OTHER" "no number" "[$(rc_entry "$SID" "$S1" | jq -c 'del(.conviction)')]"
  mk_packet pkt-b "$OTHER" "no receipt" "[$(rc_entry "$SID" "$S1" | jq -c '.receipt = ""')]"
  t_human "$H0" > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
  [ "$(field "$output" UNCONVICTED_PKTS)" = "0" ]
}

@test "CONTROL: dirty + stamp ⇒ 🔧; unlanded + stamp ⇒ 📦 (the re-check ⛔ rides the ✅-eligible path)" {
  one_stamp
  t_human "$H0" > "$TP"
  echo wip > wip.txt
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "🔧" ]
  git add wip.txt; git commit -q -m wip
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "📦" ]
}

@test "CONTROL: filed-by-me + stamp ⇒ the filed wording byte-identical, BLOCKED_WHAT from the filed packet" {
  one_stamp
  mk_packet pkt-mine "$SID" "may the dispatcher run unattended" "[]"
  t_human "$H0" > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED)" = "1" ]
  [ "$(field "$output" READOUT)" = "⛔ Blocked — need your call: may the dispatcher run unattended." ]
}

@test "two stamps ⇒ '2 decision(s) need your call: cc-decide list --open'" {
  one_stamp
  mk_packet pkt-b "$OTHER" "retire the old poller" "[$(rc_entry "$SID" "2026-10-18T10:07:00Z")]"
  t_human "$H0" > "$TP"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" READOUT)" = "⛔ Blocked — research done, implementation pending: 2 decision(s) need your call: cc-decide list --open" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "2" ]
  case " $(field "$output" RECHECKED_IDS) " in *" pkt-a "*) ;; *) false ;; esac
  case " $(field "$output" RECHECKED_IDS) " in *" pkt-b "*) ;; *) false ;; esac
}

@test "--full Next row on the research ⛔ names the sign-off" {
  one_stamp
  t_human "$H0" > "$TP"
  run bash "$LEDGER" --full --transcript "$TP"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^Next: *STOP-ASK — research done, implementation pending'
}

@test "no transcript ⇒ RECHECKED_SRC=none, RUNG=✅ (fail-open)" {
  one_stamp
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
  [ "$(field "$output" RECHECKED_SRC)" = "none" ]
}

@test "unreadable store ⇒ BLOCKED_SRC=error, BLOCKED_RECHECKED=0" {
  one_stamp
  t_human "$H0" > "$TP"
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" BLOCKED_SRC)" = "error" ]
  [ "$(field "$output" BLOCKED_RECHECKED)" = "0" ]
  [ "$(field "$output" RECHECKED_SRC)" = "error" ]
}
