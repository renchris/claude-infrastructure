#!/usr/bin/env bats
# shellcheck disable=SC2016  # the bash -c bodies read $1/$2 as positional args, on purpose
# lever-d1-d3-treatment — W7+ wave S12 (docs/plans/USAGE_LEVERS.md § W7+ §2 D1 and D3, §3 "Never
# tunable" and row "Auto-rollback"): the D1 idle recycle and the D3 keepalive wake in
# hooks/idle-keepalive.sh + hooks/lib/idle_gap.py, and handoff-fire.sh's d1_engage row.
#
# Owns:
#   pct 0        across a corpus of gaps (busy, idle, watcher-covered, 200k idle, 200k busy, 200k with
#                a pending question) in both shadow and live-at-pct-0 flag files: zero wakes (rc 0, no
#                stderr, no fired row) and zero recycles (the actuator never runs), while both arms log
#                (D1 arm + would_recycle rows, D3 wake rows).
#   pct 100      in a hermetic HOME: one wake per gap even with two timers racing on one gap and
#                CC_KEEPALIVE_MAX_WAKES=3; a wake only when busy (rc 2, the stderr ask, fired: true,
#                headless false); never on a not-busy gap or a headless transcript.
#   D1 recycle   at pct 100 the actuator is handoff-fire.sh --recycle --prompt-file <brief>, the brief
#                carries G3/G5 and the D1-CHAIN marker, the d1_recycle row matches the S6b contract, the
#                treated event lands in the IRS log keyed on turn_start = the due time; G1 (busy) and
#                G4 (pending question) hold it; and cc-lever-guard trips D1 on that row when no
#                d1_engage follows within 600 s, and not when handoff-fire's hf_d1_engage wrote one.
#   kill switches  CC_LEVER_ALL / CC_LEVER_D1 / CC_LEVER_D3 (off and control), CC_IRS=off and
#                CC_IDLE_KEEPALIVE=off each win over a pct-100 flag file.
# The shadow-only contracts (arm rows at the due time, gap v2, IRS v2) stay with
# tests/lever-idle-shadows.bats; the gap ledger and headless argv guard with tests/idle-keepalive.bats.
#
# RED-proof (2026-10-25): against the base hook and ledger (git show c15c9e288:…), (2)-(4) fail by
# construction (no exit 2, no d1-due subcommand, no d1_recycle row); (5) passes there, since the base
# never acts, and guards the treatment against a switch that stops winning. Mutants, each measured
# red: the O_EXCL claim dropped from claim_wake ⇒ (2) sees two wakes; both busy-scoped D3 guards
# (busy, watcher-fires) forced true ⇒ (2) wakes a not-busy gap (busy alone is an equivalent mutant:
# eligible implies busy); the G4 guard forced true ⇒ (4) recycles over the question.
# Hooks run under /bin/bash (3.2 on macOS), as the harness runs them.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"; mkdir -p "$CC_LEVER_STATE_DIR"
  export CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/logs"; mkdir -p "$CC_LEVER_LOG_DIR"
  export CC_IDLE_KEEPALIVE_LOG="$CC_LEVER_LOG_DIR/idle-keepalive.jsonl"   # where the guard reads it
  export CC_IRS_LOG="$CC_LEVER_LOG_DIR/idle-recycle-shadow.jsonl"
  export CC_IDLE_KEEPALIVE_STATE="$BATS_TEST_TMPDIR/state"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_IDLE_GAP_BOUND_S=120   # a loaded box can spend the default bound starting python
  unset CC_IDLE_KEEPALIVE CLAUDE_CODE_ENTRYPOINT CC_PANE_ID ITERM_SESSION_ID CC_KEEPALIVE_WAKE_S \
    CC_KEEPALIVE_MAX_WAKES CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D3 CC_LEVER_EXCLUDE CC_LEVER_LINEAGE \
    CC_LEVER_FLAGS CC_LEVER_HEARTBEAT CC_IRS CC_D1_K CC_D1_N_MIN CC_D1_IDLE_S CC_D1_RECYCLE_ID
  export CC_LEVER_LINEAGE=rootS12   # the lineage resolver's first source; keeps python off this path
  TX="$BATS_TEST_TMPDIR/sess.jsonl"; : > "$TX"
  SID="0b5e1d2c-aaaa-bbbb-cccc-000000000012"
  PAYLOAD="$(jq -nc --arg s "$SID" --arg t "$TX" '{session_id:$s,transcript_path:$t,hook_event_name:"Stop"}')"
  # the recycle actuator at its deployed path under the fixture HOME: it records argv, env and brief
  FIRED="$BATS_TEST_TMPDIR/fired"
  cc_stub "$HOME/.claude/scripts" handoff-fire.sh "$(printf '#!/bin/bash\n{ printf "%%s|" "$@"; printf "rid=%%s sid=%%s\\n" "$CC_D1_RECYCLE_ID" "$CC_D1_RECYCLE_SID"; } >> %q\nwhile [ $# -gt 0 ]; do [ "$1" = --prompt-file ] && cp "$2" %q; shift; done\n' "$FIRED" "$FIRED.brief")"
  flags live 100
}

# flags <mode> <pct> — D1 and D3 with fixed salts; at pct 100 every unit hashes into treat
flags() {
  jq -nc --arg m "$1" --argjson p "$2" '{v:1, rev:5, levers:{
    D1:{stage:"S1", mode:$m, pct:$p, holdback:0, salt:"saltD1", split_salt:"splitD1", params_id:"p0", stage_started_at:"2026-10-01T00:00:00Z"},
    D3:{stage:"S1", mode:$m, pct:$p, holdback:0, salt:"saltD3", split_salt:"splitD3", params_id:"p0", stage_started_at:"2026-10-01T00:00:00Z"}}}' \
    > "$CC_LEVER_STATE_DIR/flags.json"
  touch "$CC_LEVER_STATE_DIR/guard.heartbeat"   # fresh: the dead-man switch is not what holds pct 0
}
iso() { date -u -r "$1" +%FT%TZ; }
asst() { # <epoch> <context tokens> [text]
  jq -nc --arg t "$(iso "$1")" --argjson c "$2" --arg x "${3:-Done.}" \
    '{type:"assistant",timestamp:$t,entrypoint:"cli",message:{model:"claude-opus-5-5",content:[{type:"text",text:$x}],
      usage:{input_tokens:2,cache_creation_input_tokens:500,cache_read_input_tokens:($c-502),output_tokens:0}}}' >> "$TX"
}
bg_job() { # <epoch> — a background Bash still running (busy by its launching tool)
  jq -nc --arg t "$(iso "$1")" '{type:"assistant",timestamp:$t,entrypoint:"cli",message:{model:"claude-opus-5-5",
    content:[{type:"tool_use",id:"tu_b",name:"Bash",input:{command:"bats tests/x.bats",run_in_background:true}}],
    usage:{input_tokens:2,cache_creation_input_tokens:500,cache_read_input_tokens:100,output_tokens:0}}}' >> "$TX"
  jq -nc --arg t "$(iso $(( $1 + 1 )))" '{type:"user",timestamp:$t,message:{content:[{type:"tool_result",
    tool_use_id:"tu_b",content:"Command running in background with ID: bx1q2w3e4"}]}}' >> "$TX"
}
watcher() { # <epoch> — a background cc-await-ping that fires on its own before the cache TTL
  jq -nc --arg t "$(iso "$1")" '{type:"assistant",timestamp:$t,entrypoint:"cli",message:{model:"claude-opus-5-5",
    content:[{type:"tool_use",id:"tu_w",name:"Bash",input:{command:"cc-await-ping --timeout 600",run_in_background:true}}],
    usage:{input_tokens:2,cache_creation_input_tokens:500,cache_read_input_tokens:100,output_tokens:0}}}' >> "$TX"
  jq -nc --arg t "$(iso $(( $1 + 1 )))" '{type:"user",timestamp:$t,message:{content:[{type:"tool_result",
    tool_use_id:"tu_w",content:"Command running in background with ID: bw1q2w3e4"}]}}' >> "$TX"
}
# gap <kind> — one fixture gap, the Stop that opens it already run: d3busy d3idle d3watch d1idle
# d1busy d1question. d1* gaps open at 250k with the last request 20 min back (past D1's 15 min).
gap() {
  : > "$TX"; rm -rf "$CC_IDLE_KEEPALIVE_STATE"
  local now; now=$(date +%s)
  case "$1" in
    d3busy)     asst $((now - 60)) 150000; bg_job $((now - 50)) ;;
    d3idle)     asst $((now - 60)) 150000 ;;
    d3watch)    asst $((now - 60)) 150000; bg_job $((now - 50)); watcher $((now - 40)) ;;
    d1idle)     bg_job $((now - 1500)); printf '{"type":"user","timestamp":"%s","message":{"content":"<task-notification>\\n<task-id>bx1q2w3e4</task-id>\\n<tool-use-id>tu_b</tool-use-id>\\n<status>completed</status>\\n</task-notification>"}}\n' "$(iso $((now - 1400)))" >> "$TX"
                asst $((now - 1200)) 250000 "Landed abc123; nothing open." ;;
    d1busy)     bg_job $((now - 1300)); asst $((now - 1200)) 250000 ;;
    d1question) asst $((now - 1200)) 250000 "Both are ready. Should I land the first one?" ;;
  esac
  run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/cache-expiry-tracker.sh"
  [ "$status" -eq 0 ]
}
# timer [env…] — the keepalive as an interactive session runs it: D1 due 1 s in, D3 2 s in
timer() {
  run env CC_IDLE_KEEPALIVE_HARNESS_ARGV="claude --model x" CC_IDLE_KEEPALIVE_HARNESS_FD1=/dev/ttys009 \
    CC_KEEPALIVE_WAKE_S=2 CC_D1_IDLE_S=1 CC_IDLE_KEEPALIVE_SETTLE_S=0 CC_IDLE_KEEPALIVE_POLL_S=1 "$@" \
    bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/idle-keepalive.sh"
}
rows() { [ -f "$CC_IDLE_KEEPALIVE_LOG" ] || return 0; jq -c "select(.kind==\"$1\")" "$CC_IDLE_KEEPALIVE_LOG"; }
nrows() { rows "$1" | grep -c . || true; }
fired_rows() { [ -f "$CC_IDLE_KEEPALIVE_LOG" ] || { echo 0; return; }; jq -c 'select(.fired == true)' "$CC_IDLE_KEEPALIVE_LOG" | grep -c . || true; }
guard_inv() { # <now epoch> → the guard's read-only invariant pass over every row, as JSON
  run env CC_NOW="$1" /usr/bin/python3 -I "$REPO/bin/cc-lever-guard" invariants --all --json
}

@test "(1) pct 0: across the gap corpus, in shadow and live-at-0 flag files, nothing wakes or recycles, and both levers log" {
  for f in "shadow 0" "live 0"; do
    # shellcheck disable=SC2086  # "<mode> <pct>", split on purpose
    flags $f
    for g in d3busy d3idle d3watch d1idle d1busy d1question; do
      : > "$CC_IDLE_KEEPALIVE_LOG"
      gap "$g"; timer
      [ "$status" -eq 0 ] || { echo "$f $g rc=$status"; false; }
      [ -z "$output" ] || { echo "$f $g output: $output"; false; }
      [ "$(fired_rows)" -eq 0 ]
      [ "$(nrows d1_recycle)" -eq 0 ]
      [ "$(nrows wake)" -eq 1 ]            # D3 logged its would-wake in this arm
      rows wake | jq -e '.arm == "ctrl" and .fired == false and .pct_eff == 0 and .why_not == "arm-ctrl"' >/dev/null
      case "$g" in
        d1*) [ "$(rows would_recycle | jq -r '[.schema,.v,.arm,.fired,.why_not,.lineage,.k2_thousand,.would_advise_k2] | map(tostring) | join(" ")')" \
                 = "2 ok ctrl false arm-ctrl rootS12 200 true" ] ;;
        *)   [ "$(nrows would_recycle)" -eq 0 ] ;;   # below 200k: D1 decides nothing
      esac
    done
  done
  [ ! -e "$FIRED" ]                                    # the recycle actuator never ran
  [ ! -s "$CC_IRS_LOG" ]                               # and no treated D1 event was logged
  [ "$(jq -c 'select(.lever == "D1" and .hook == "idle-keepalive")' "$CC_LEVER_LOG_DIR/lever-arms.jsonl" | grep -c .)" -eq 6 ]
}

@test "(2) pct 100: one wake per gap — a busy gap wakes once (rc 2, the ask, fired), two racing timers wake once, idle and headless never" {
  gap d3busy
  timer CC_KEEPALIVE_MAX_WAKES=3
  [ "$status" -eq 2 ]
  grep -qF "Keepalive wake (lever D3)" <<<"$output"
  [ "$(nrows wake)" -eq 1 ]                            # MAX_WAKES=3, and still one wake row: it exited at the first
  rows wake | jq -e '.fired == true and .arm == "treat" and .pct_eff == 100 and .busy == true
                     and .headless == false and .mode == "live" and .why_not == null' >/dev/null
  # two timers for ONE gap: exactly one of them wakes
  gap d3busy; : > "$CC_IDLE_KEEPALIVE_LOG"
  ( timer; echo "$status" > "$BATS_TEST_TMPDIR/rc.a" ) &
  ( timer; echo "$status" > "$BATS_TEST_TMPDIR/rc.b" ) &
  wait
  [ "$(cat "$BATS_TEST_TMPDIR/rc.a" "$BATS_TEST_TMPDIR/rc.b" | sort | tr '\n' ' ')" = "0 2 " ]
  [ "$(fired_rows)" -eq 1 ]
  [ "$(rows wake | jq -r 'select(.fired == false) | .why_not')" = "wake-spent" ]
  # a gap whose job finished is not busy; one a watcher covers is skipped; neither wakes
  for g in d3idle d3watch; do
    gap "$g"; : > "$CC_IDLE_KEEPALIVE_LOG"; timer
    [ "$status" -eq 0 ]; [ -z "$output" ]; [ "$(fired_rows)" -eq 0 ]
  done
  # a headless transcript (entrypoint sdk-cli) never wakes, even past the hook's argv test
  gap d3busy; : > "$CC_IDLE_KEEPALIVE_LOG"
  jq -c '.entrypoint = "sdk-cli"' "$TX" > "$TX.h" && mv "$TX.h" "$TX"
  timer
  [ "$status" -eq 0 ]; [ "$(fired_rows)" -eq 0 ]
  rows wake | jq -e '.headless == true and .why_not == "headless"' >/dev/null
}

@test "(3) pct 100 D1: the recycle runs handoff-fire.sh --recycle with the brief; rows match the guard's contract; the guard trips on no engage" {
  gap d1idle
  timer
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # the actuator: --recycle carrying the brief, with the recycle id and predecessor in its env
  rid="$(rows d1_recycle | jq -r .recycle_id)"
  [ "$(cut -d'|' -f1,2 "$FIRED")" = "--recycle|--prompt-file" ]
  grep -qF "rid=$rid sid=$SID" "$FIRED"
  grep -q "^D1-CHAIN v1 lineage=rootS12 pred=$SID " "$FIRED.brief"
  grep -q "How to start (G5)" "$FIRED.brief"
  grep -q "Landed abc123; nothing open." "$FIRED.brief"     # G3: the final message, verbatim
  # the S6b row contract, one write under 2 KB, and no D3 wake after it (the gap's wake is spent)
  [ "$(nrows d1_recycle)" -eq 1 ]; [ "$(nrows wake)" -eq 0 ]
  rows d1_recycle | jq -e --arg s "$SID" '.v == 1 and .sid == $s and .lineage == "rootS12" and .fired == true
    and .arm.arm == "treat" and .arm.pct_eff == 100 and .busy == false and .pending_question == false
    and .g1_kill == false and .g4_violation == false and (.gap_start | test("Z$")) and (.ts | test("Z$"))
    and .gap_s >= 1200 and (tojson | utf8bytelength) <= 2047' >/dev/null
  [ "$(rows d1_recycle | jq -r .gap_start)" = "$(rows would_recycle | jq -r .gap_start)" ]
  # the treated D1 event, where lever_chain.py reads it: turn_start = the due time, gap_s = idle s
  jq -e --arg r "$rid" '.v == "ok" and .schema == 2 and .recycle_id == $r and .arm == "treat"
    and .turn_start - .idle_start == .gap_s and .would_advise_k2 == true' "$CC_IRS_LOG" >/dev/null
  # the guard: 700 s on, no d1_engage ⇒ D1 trips d1_no_engage, and nothing else
  t="$(rows d1_recycle | jq -r '.ts | fromdateiso8601')"
  guard_inv $(( t + 700 ))
  [ "$status" -eq 3 ]
  [ "$(jq -c '[.occurrences | to_entries[] | .key as $L | .value[] | "\($L):\(.inv)"]' <<<"$output")" = '["D1:d1_no_engage"]' ]
  # handoff-fire's engage writer, run as the recycle watcher runs it, clears the occurrence
  eval "$(sed -n '/^hf_d1_engage() {/,/^}/p' "$REPO/scripts/handoff-fire.sh")"
  cc_sid_for_pane() { echo "5ucc5e55-0000-0000-0000-000000000001"; }
  CC_D1_RECYCLE_ID="$rid" CC_D1_RECYCLE_SID="$SID" hf_d1_engage pane-1
  rows d1_engage | jq -e --arg r "$rid" --arg s "$SID" '.v == 1 and .recycle_id == $r and .sid == $s
    and .successor_sid == "5ucc5e55-0000-0000-0000-000000000001"' >/dev/null
  guard_inv $(( t + 700 ))
  [ "$status" -eq 0 ]
  # a recycle that is not D1's writes no engage row
  hf_d1_engage pane-1; [ "$(nrows d1_engage)" -eq 1 ]
}

@test "(4) pct 100 D1 guards: G1 (a job busy) and G4 (a pending question) hold the recycle" {
  for g in d1busy d1question; do
    gap "$g"; : > "$CC_IDLE_KEEPALIVE_LOG"; rm -f "$FIRED"
    timer
    [ "$status" -eq 0 ] || [ "$g" = d1busy ]          # d1busy is still busy at the D3 due time: it may wake
    [ ! -e "$FIRED" ]; [ "$(nrows d1_recycle)" -eq 0 ]
    want=busy; [ "$g" = d1busy ] || want=pending-question
    [ "$(rows would_recycle | jq -r '[.arm,.fired,.why_not] | join(" ")')" = "treat false $want" ]
  done
}

@test "(5) kill switches win over pct 100: no wake and no recycle" {
  for k in CC_LEVER_ALL=off CC_LEVER_ALL=control CC_LEVER_D3=off CC_LEVER_D3=control CC_IDLE_KEEPALIVE=off; do
    gap d3busy; : > "$CC_IDLE_KEEPALIVE_LOG"
    timer "$k"
    [ "$status" -eq 0 ] || { echo "$k rc=$status"; false; }
    [ -z "$output" ]; [ "$(fired_rows)" -eq 0 ]
  done
  for k in CC_LEVER_ALL=off CC_LEVER_D1=off CC_LEVER_D1=control CC_IRS=off CC_IDLE_KEEPALIVE=off; do
    gap d1idle; : > "$CC_IDLE_KEEPALIVE_LOG"
    timer "$k"
    [ "$status" -eq 0 ] || { echo "$k rc=$status"; false; }
    [ ! -e "$FIRED" ]; [ "$(nrows d1_recycle)" -eq 0 ]
  done
}
