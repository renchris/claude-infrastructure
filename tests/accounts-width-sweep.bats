#!/usr/bin/env bats
# accounts-width-sweep — both /accounts surfaces fit every pane from 40 to 200 columns.
#
# Operator, 2026-10-18 21:13, with a screenshot of a ~55-column pane: "correct and improve layout
# for all small screen widths — it breaks when small". The desk clause broke mid-sentence, the grid
# headers split, every account row wrapped its last cells onto a second line. Two surfaces draw
# this table into a pane, and both are swept here at the same widths:
#
#   · the /accounts chat readout — `claude-accounts --readout` leaves a pane-fitted copy that
#     hooks/relay-verbatim.sh draws as a PostToolUse systemMessage (`--pane --cols N` prints it);
#   · the SessionStart board — hooks/accounts-board.sh draws a file the keepwarm producer wrote,
#     choosing among the producer's narrow variants by the pane's width (`CC_PANE_COLS` seam).
#
# THE BUDGET, measured (docs/research/board-render-2026-09-22.md, findings 6-7): a hook
# systemMessage gets pane − 5 cells per row (a 5-column continuation indent), and line 1 alone also
# carries the harness's `⎿ <Event>:<source> says: ` prefix (~31 columns for SessionStart). The
# check below measures DISPLAY CELLS with SGR stripped, re-implemented here rather than imported
# from the subject — a check that calls the subject's own measure agrees with it by construction.
#
# The one allowance: a single token wider than the pane (a path or a command the hook names) is
# never split, because a broken command no longer pastes. The check accepts such a line only when
# it is ONE token after its indent; any line a word wrap could have shortened is a breach.

WIDTHS="40 50 55 60 70 76 80 100 120 160 200"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOOK="$REPO/hooks/accounts-board.sh"
  export RELAY="$REPO/hooks/relay-verbatim.sh"
  export CA_BIN="$REPO/bin/claude-accounts"
  export D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"
  export CC_ACCOUNTS_BOARD="$D/board.txt"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  mk_cfg
}

# Fixture config and rows: the same shape tests/accounts-board.bats uses (a 61-character account
# name, so truncation is load-bearing; a stale `*` reading; a 100% 5h row the wire rejected).
mk_cfg() {
  python3 - "$D/acct.json" "$D/cache.json" "$REPO/accounts.json" <<'PY'
import json, sys
out, cache, real = sys.argv[1:4]
r = json.load(open(real))
acct = lambda n, l, x: {"name": n, "config_dir": f"/tmp/ca-sweep-nonexistent-{x}", "launcher": l,
                        "email": f"{x}@example.com", "mailbox": f"{x}@example.com", "dia_profile": x}
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [acct("next-quaternary-extremely-long-account-name-for-width-testing", "claude4", "a"),
               acct("next2", "claude2", "b"), acct("next3", "claude3", "c"),
               acct("next", "claude", "d")],
}, open(out, "w"))
PY
}

FIXTURE='
_t = lambda m: (datetime.now(timezone.utc) + timedelta(minutes=m)).isoformat()
    rows = [
  {"acct": "next-quaternary-extremely-long-account-name-for-width-testing",
   "auth": "ok", "launcher": "claude4", "k": 12,
   "session_pct": 88.0, "weekly_pct": 46.0, "fable_pct": 18.0,
   "session_reset_h": 1.2, "weekly_reset_h": 100.4, "login_expires_h": 447.0,
   "session_reset_at": _t(72), "weekly_reset_at": "2126-01-05T00:00:00+00:00",
   "login_expires_at": "2126-02-01T00:00:00+00:00", "stale_quota": True},
  {"acct": "next2", "auth": "ok", "launcher": "claude2", "k": 1,
   "session_pct": 82.0, "weekly_pct": 48.0, "fable_pct": 21.0,
   "session_reset_h": 2.5, "weekly_reset_h": 83.5, "login_expires_h": 636.0,
   "session_reset_at": _t(150), "weekly_reset_at": "2126-01-04T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00"},
  {"acct": "next3", "auth": "ok", "launcher": "claude3", "k": 0,
   "session_pct": 100.0, "weekly_pct": 40.0, "fable_pct": 10.0,
   "session_reset_h": 0.75, "weekly_reset_h": 60.0, "login_expires_h": 50.0,
   "session_reset_at": _t(45), "weekly_reset_at": "2126-01-03T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00",
   "wire": {"5h_util": 1.02, "5h_status": "rejected", "7d_util": 0.4, "7d_status": "allowed",
            "status": "rejected", "http": 429}},
  {"acct": "next", "auth": "ok", "launcher": "claude", "k": 2,
   "session_pct": 0.0, "weekly_pct": 22.0, "fable_pct": 0.0,
   "session_reset_h": 3.6, "weekly_reset_h": 145.0, "login_expires_h": 671.0,
   "session_reset_at": _t(218), "weekly_reset_at": "2126-01-07T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00"},
]
    wj, cached, prev = {}, True, None'

ca() {  # <args…> → claude-accounts run over the fixture rows (source patch at the documented anchor)
  python3 - "$CA_BIN" "$@" <<PY
import subprocess, sys
src = open(sys.argv[1]).read()
anchor = "rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)"
new = src.replace(anchor, '''$FIXTURE'''.strip())
assert new != src, "source patch did not apply — the anchor moved (see the note at that line)"
p = subprocess.run([sys.executable, "-c", new] + sys.argv[2:], capture_output=True, text=True)
sys.stderr.write(p.stderr)
sys.stdout.write(p.stdout)
sys.exit(p.returncode)
PY
}

# <pane cols> <line-1 prefix cells> < message → exit 1 and one BREACH line per row that the
# terminal would wrap. Line 1 is charged the prefix; every row is charged the 5-column gutter.
fits() {
  python3 -c '
import re, sys, unicodedata
cols, prefix = int(sys.argv[1]), int(sys.argv[2])
sgr = re.compile("\x1b\\[[0-9;]*m")
def cells(s):
    return sum(0 if unicodedata.combining(c) or c in "‍︎️" else
               2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
bad = 0
for i, l in enumerate(sys.stdin.read().split("\n"), 1):
    p = sgr.sub("", l)
    budget = cols - 5 - (prefix - 5 if i == 1 else 0)
    if cells(p) > budget and len(p.split()) > 1:
        bad += 1
        print(f"BREACH pane={cols} line {i}: {cells(p)} cells > {budget}: {p!r}")
sys.exit(1 if bad else 0)' "$@"
}

@test "1 /accounts pane readout: no row wraps at any pane width 40..200" {
  local w out fail=0
  for w in $WIDTHS; do
    out="$(ca --readout --pane --cols "$w" --no-agents --max-wait 0 2>"$D/err")" \
      || { echo "pane=$w: --pane failed: $(cat "$D/err")"; fail=1; continue; }
    [ -n "$out" ] || { echo "pane=$w: empty render"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 5 || fail=1
  done
  [ "$fail" -eq 0 ]
}

@test "2 /accounts pane readout keeps the answer at 40 columns: desk pick and every account" {
  run ca --readout --pane --cols 40 --no-agents --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *desk* ]] || { echo "desk line lost at 40: $output"; false; }
  local a
  for a in next2 next3 next; do
    [[ "$output" == *"$a"* ]] || { echo "account $a dropped at 40: $output"; false; }
  done
}

@test "3 /accounts as drawn by the relay hook: the drawn message fits at every width" {
  local w out fail=0
  export CLAUDE_CODE_SESSION_ID="sweep-sid" CC_PANE_DIR="$D/pane"
  for w in $WIDTHS; do
    CC_PANE_COLS="$w" ca --readout --no-agents --max-wait 0 >/dev/null 2>"$D/err" \
      || { echo "pane=$w: readout failed: $(cat "$D/err")"; fail=1; continue; }
    out="$(jq -nc --arg c "claude-accounts --readout" \
            '{tool_name:"Bash", tool_input:{command:$c}, tool_response:{stdout:"x"},
              session_id:"sweep-sid", hook_event_name:"PostToolUse"}' \
           | "$RELAY" | jq -r '.systemMessage // empty')"
    [ -n "$out" ] || { echo "pane=$w: the relay hook drew nothing"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 27 || fail=1     # `⎿ PostToolUse:Bash says: `
  done
  [ "$fail" -eq 0 ]
}

board_at() {  # <pane cols> → the SessionStart systemMessage for that pane
  printf '{"source":"startup","hook_event_name":"SessionStart"}' \
    | CC_PANE_COLS="$1" "$HOOK" | jq -r '.systemMessage // empty'
}

@test "4 SessionStart board: no row wraps at any pane width 40..200" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$CC_ACCOUNTS_BOARD" ] || { echo "producer wrote no board"; false; }
  local w out fail=0
  for w in $WIDTHS; do
    out="$(board_at "$w")"
    [ -n "$out" ] || { echo "pane=$w: the hook drew nothing"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 31 || fail=1
    [[ "$out" == *next3* ]] || { echo "pane=$w: an account row was lost: $out"; fail=1; }
  done
  [ "$fail" -eq 0 ]
}

@test "5 SessionStart board: a STALE board's warning lines fit too, at every width" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f t
  t=$(( $(date +%s) - 900 ))
  for f in "$CC_ACCOUNTS_BOARD" "$CC_ACCOUNTS_BOARD".w*; do
    [ -e "$f" ] && touch -t "$(date -r "$t" +%Y%m%d%H%M.%S)" "$f"
  done
  # launchctl stubbed: the warning names the producer's state, and the real job is not ours to read
  mkdir -p "$D/bin"; printf '#!/bin/sh\nexit 1\n' > "$D/bin/launchctl"; chmod +x "$D/bin/launchctl"
  local w out fail=0
  for w in $WIDTHS; do
    out="$(PATH="$D/bin:$PATH" board_at "$w")"
    [[ "$out" == *STALE* ]] || { echo "pane=$w: not on the stale path: $out"; fail=1; continue; }
    printf '%s' "$out" | fits "$w" 31 || fail=1
  done
  [ "$fail" -eq 0 ]
}

@test "6 SessionStart board: byte-identical to the 76-column board wherever that board fits" {
  run ca --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local want w
  want="$(cat "$CC_ACCOUNTS_BOARD")"
  for w in 81 100 120 160 200; do
    [ "$(board_at "$w")" = "$want" ] || { echo "pane=$w: board changed where it fit"; false; }
  done
  # and an unknown width (no tty anywhere up the tree, no override) keeps the old board too
  [ "$(printf '{"source":"startup"}' | CC_PANE_COLS=x "$HOOK" | jq -r .systemMessage)" = "$want" ]
}
