#!/usr/bin/env bats
# Relogin observability (RELOGIN_BUILD_CONTRACT §6) — the three read-only surfaces:
#   1. claude-accounts --relogin-status  the per-account renewal board (+ --json)
#   2. cc-blockers                       the class-C relogin-blocked row, additive to safeguard-blocked
#   3. rotate-autonomy-logs.sh           bounds the cc-relogin*.log family
#
# Hermetic by construction: a scratch SSOT + a PRE-SEEDED shared cache (so the board never sweeps
# an endpoint, never reads a real keychain and never heals), a temp IDL board via CC_REAPER_IDL,
# a temp poller log via CC_RELOGIN_POLL_LOG, and a temp $HOME for rotation. Nothing here signs in.
#
# The load-bearing case is §2 version tolerance: the login_expires_* fields are NOT on every build,
# and a board that cannot see them must say UNKNOWN — a confident wrong "OK" is worse than useless.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  C="$REPO/bin/cc-blockers"
  ROT="$REPO/scripts/rotate-autonomy-logs.sh"
  export D="$BATS_TEST_TMPDIR"    # exported: one test splits streams via a `bash -c` subshell
  export CA_CFG="$D/accounts.json"
  export CACHE="$D/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$D/lastgood.json"
  export CC_RELOGIN_POLL_LOG="$D/cc-relogin-poll.log"
  export CC_REAPER_IDL="$D/idl.jsonl"
  # scratch SSOT — dead endpoints + a config_dir with no keychain item, so a sweep (if one ever
  # happened) would be offline and deterministic. Three accounts so state precedence is testable.
  python3 - "$CA_CFG" "$CACHE" <<'PY'
import json, sys
cfg_path, cache = sys.argv[1], sys.argv[2]
acct = lambda n: {"name": n, "config_dir": "/tmp/ca-relogin-nonexistent-" + n,
                  "launcher": "claude-" + n, "fable_launcher": "claude-fable-" + n,
                  "email": n + "@example.com", "mailbox": n + "@example.com", "dia_profile": n.upper()}
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache, "cache_ttl_s": 900,
  "frontier": {"scoped_display_name": "Fable", "coupling": 0.5, "deadline_margin_h": 2.0,
               "end_date_inclusive": True, "credits_authorized": False},
  "router": {"S_CUT": 0.85, "S_SOFT": 0.5, "SF_FLOOR": 0.05, "KMAX": 8, "KFLOOR": 0.1,
             "MARGIN_H": 0.5, "EPS_H": 0.25, "WEEKLY_FLOOR": 0.005, "FABLE_FLOOR": 0.02,
             "JB_BONUS": 1.25},
  "accounts": [acct("next"), acct("next2"), acct("next3")],
}, open(cfg_path, "w"))
PY
}

# seed the SHARED CACHE with exactly these rows — the board then reads them like any other mode,
# with zero network, zero keychain and zero heal. <rows-json>
seed() {
  python3 - "$CA_BIN" "$CACHE" "$1" <<'PY'
import importlib.machinery, importlib.util, json, sys, time
bin_, cache, rows_json = sys.argv[1], sys.argv[2], sys.argv[3]
loader = importlib.machinery.SourceFileLoader("ca", bin_)
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
cfg = ca.load_cfg()
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": True,
           "rows": json.loads(rows_json), "prev": None,
           "window": {"active": False, "end": None, "permanent": False, "deadline": None}},
          open(cache, "w"))
PY
}

rl() { # append a relogin-blocked class-C row: <ts> <acct> <state> <when> <recover_cmd>
  jq -nc --arg ts "$1" --arg a "$2" --arg s "$3" --arg w "$4" --arg cmd "$5" \
    '{ts:$ts,actor:"cc-relogin-poll",kind:"relogin-blocked",acct:$a,state:$s,
      login_expires_at:$w,recover_cmd:$cmd}' >> "$CC_REAPER_IDL"; }

sg() { # append a safeguard-blocked row (the pre-existing kind): <ts> <pane> <name> <cmd>
  jq -nc --arg ts "$1" --arg p "$2" --arg n "$3" --arg cmd "$4" \
    '{ts:$ts,actor:"cc-reaper",kind:"safeguard-blocked",pane:$p,name:$n,account:"claude-quaternary",
      blocked_model:"Fable 5",refusal:"safeguards flagged this message",recover_cmd:$cmd}' \
    >> "$CC_REAPER_IDL"; }

# ── 1. claude-accounts --relogin-status ────────────────────────────────────────────────────────

@test "OK: every account outside the attempt window → exit 0, no next action" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z","login_expires_h":400}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'next .*OK'
  echo "$output" | grep -q '2026-09-01T00:00:00Z'
}

@test "DUE: inside the 7d attempt window → exit 1 + the exact cc-relogin command" {
  seed '[{"acct":"next2","auth":"ok","login_expires_at":"2026-07-29T00:00:00Z","login_expires_h":100}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 1 ]                       # 100h < 168h trigger, > 48h escalate
  echo "$output" | grep -q 'DUE'
  echo "$output" | grep -q 'cc-relogin next2'
}

@test "ESCALATED: inside the 48h escalation window → exit 2" {
  seed '[{"acct":"next3","auth":"ok","login_expires_at":"2026-07-26T00:00:00Z","login_expires_h":12}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ESCALATED'
  echo "$output" | grep -q 'cc-relogin next3'
}

@test "ESCALATED: an already-expired login window (login_expired) → exit 2" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-07-01T00:00:00Z","login_expires_h":-5,"login_expired":true}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ESCALATED'
}

@test "ESCALATED: a logged-out account is never UNKNOWN, even with no login_* fields" {
  seed '[{"acct":"next","auth":"logged-out","error":"logged-out"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]                       # auth exists on EVERY build — past the cliff already
  echo "$output" | grep -q 'ESCALATED'
}

# ── the §2 case: the detection surface is absent on this build ─────────────────────────────────

@test "UNKNOWN: login_* fields absent → NOT a confident OK, exit 3, loud named surface" {
  seed '[{"acct":"next","auth":"ok"},{"acct":"next2","auth":"healed"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -ne 0 ]                       # the load-bearing assertion: never 0-with-a-wrong-OK
  [ "$status" -eq 3 ]                       # DETECTION-UNAVAILABLE
  echo "$output" | grep -q 'UNKNOWN'
  ! echo "$output" | grep -qE '\bOK\b'      # the word OK must not appear anywhere
  echo "$output" | grep -q 'DETECTION-UNAVAILABLE'
  echo "$output" | grep -q 'login_expires_h' # names the missing surface (§2)
  echo "$output" | grep -q 'feat/accounts-login-cliff'
}

@test "UNKNOWN outranks OK: a partially-blind board never reports all-clear" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z","login_expires_h":400},
         {"acct":"next2","auth":"ok"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 3 ]                       # one blind account is enough to withhold "all clear"
}

@test "act-now outranks cannot-see: DUE + UNKNOWN → exit 1" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-07-29T00:00:00Z","login_expires_h":100},
         {"acct":"next2","auth":"ok"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 1 ]
}

@test "login_expires_at without login_expires_h → UNKNOWN (cannot age it), not OK" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'UNKNOWN'
}

# ── last attempt, read from the poller's log ───────────────────────────────────────────────────

@test "last attempt: JSONL poller row (ts + result), latest wins" {
  printf '%s\n' '{"ts":"2026-07-24T10:00:00Z","acct":"next","result":"FALLBACK-REQUIRED"}' \
                '{"ts":"2026-07-25T11:00:00Z","acct":"next","result":"PROVEN"}' \
                '{"ts":"2026-07-25T11:30:00Z","acct":"next2","result":"ERROR"}' > "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-07-29T00:00:00Z","login_expires_h":100}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_result')" = "PROVEN" ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_ts')" = "2026-07-25T11:00:00Z" ]
}

@test "last attempt: a missing poller log is UNKNOWN ('never'), never an error" {
  rm -f "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z","login_expires_h":400}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]                       # absent log does not change the renewal state
  echo "$output" | grep -q 'never'
}

@test "last attempt: a plain-text (non-JSON) poller line is still read" {
  printf '%s\n' 'THIS IS NOT JSON' '2026-07-25T12:00:00Z next3 attempt failed: BROWSER-FAILED' \
    > "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next3","auth":"ok","login_expires_at":"2026-07-26T00:00:00Z","login_expires_h":12}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 2 ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_ts')" = "2026-07-25T12:00:00Z" ]
  echo "$output" | jq -r '.rows[0].last_attempt_result' | grep -q 'BROWSER-FAILED'
}

# ── --json shape + read-only posture ───────────────────────────────────────────────────────────

@test "--json: documented shape (exit, state, detection, per-account rows)" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-07-29T00:00:00Z","login_expires_h":100},
         {"acct":"next2","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z","login_expires_h":400}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.exit')" = "1" ]            # the exit code is DATA too
  [ "$(echo "$output" | jq -r '.state')" = "DUE" ]
  [ "$(echo "$output" | jq -r '.detection')" = "available" ]
  [ "$(echo "$output" | jq '.rows | length')" = "2" ]
  [ "$(echo "$output" | jq -r '.rows[0].acct')" = "next" ]
  [ "$(echo "$output" | jq -r '.rows[0].state')" = "DUE" ]
  [ "$(echo "$output" | jq -r '.rows[0].next_action')" = "cc-relogin next" ]
  [ "$(echo "$output" | jq -r '.rows[1].state')" = "OK" ]
  [ "$(echo "$output" | jq -r '.rows[0].login_expires_h')" = "100" ]
  echo "$output" | jq -e '.rows[0] | has("last_attempt_ts") and has("reason")' >/dev/null
}

@test "--json: detection=unavailable, and the loud line goes to stderr — stdout stays parseable" {
  seed '[{"acct":"next","auth":"ok"}]'
  # Split the streams: a machine consumer pipes stdout to jq, so the §2 warning must NOT land
  # there and corrupt it — but it must still be emitted, unmissably, on stderr.
  run bash -c '"$CA_BIN" --relogin-status --json 2>"$D/err.txt"'
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.detection')" = "unavailable" ]
  [ "$(echo "$output" | jq -r '.rows[0].state')" = "UNKNOWN" ]
  [ "$(echo "$output" | jq -r '.rows[0].login_expires_at')" = "null" ]
  grep -q 'DETECTION-UNAVAILABLE' "$D/err.txt"
  ! grep -q 'DETECTION-UNAVAILABLE' <<<"$output"
}

@test "read-only: a cache hit is served as-is — no re-sweep, no cache rewrite" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-09-01T00:00:00Z","login_expires_h":400}]'
  before="$(cat "$CACHE")"
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]
  [ "$(cat "$CACHE")" = "$before" ]         # byte-identical ⇒ collect() never ran
}

@test "plain output always: no ANSI escapes on a machine surface" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"2026-07-26T00:00:00Z","login_expires_h":12}]'
  FORCE_COLOR=1 run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  ! printf '%s' "$output" | grep -q $'\033'
}

# ── 2. cc-blockers — the class-C relogin row (additive) ────────────────────────────────────────

@test "cc-blockers renders a relogin-blocked row with its EXACT recover command" {
  rl "2026-07-25T09:00:00Z" "next3" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next3 --debug"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -q 'next3'
  echo "$output" | grep -q 'ESCALATED'
  echo "$output" | grep -q '2026-07-27T00:00:00Z'
  echo "$output" | grep -qF 'cc-relogin next3 --debug'   # verbatim, never paraphrased
}

@test "cc-blockers: safeguard-blocked still renders unchanged alongside relogin (regression)" {
  sg "2026-07-25T09:05:00Z" "725A269A" "wt-pool-2-725A269A" "cc-recover-safeguard 725A269A"
  rl "2026-07-25T09:10:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'SAFEGUARD-BLOCKED'
  echo "$output" | grep -q 'wt-pool-2-725A269A'
  echo "$output" | grep -q 'Fable 5'
  echo "$output" | grep -q 'safeguards flagged this message'
  echo "$output" | grep -qF 'cc-recover-safeguard 725A269A'
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -qF 'cc-relogin next'
}

@test "cc-blockers --json: one array carrying both kinds, newest first" {
  sg "2026-07-25T09:05:00Z" "PANE-A" "peer-a" "cc-recover-safeguard PANE-A"
  rl "2026-07-25T09:20:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "relogin-blocked" ]   # newest first
  [ "$(echo "$output" | jq -r '.[1].kind')" = "safeguard-blocked" ]
}

@test "cc-blockers dedup: latest relogin row per acct, both accounts kept" {
  rl "2026-07-25T09:00:00Z" "next" "DUE" "2026-07-27T00:00:00Z" "cc-relogin next"
  rl "2026-07-25T10:00:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next --debug"
  rl "2026-07-25T10:30:00Z" "next2" "ESCALATED" "2026-07-28T00:00:00Z" "cc-relogin next2"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.acct=="next")][0].state')" = "ESCALATED" ]
  [ "$(echo "$output" | jq -r '[.[] | select(.acct=="next")][0].recover_cmd')" = "cc-relogin next --debug" ]
}

@test "cc-blockers: a malformed board line never hides the good rows" {
  printf '%s\n' 'THIS IS NOT JSON at all' >> "$CC_REAPER_IDL"
  printf '%s\n' '"a bare string"' >> "$CC_REAPER_IDL"
  rl "2026-07-25T09:00:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  sg "2026-07-25T09:01:00Z" "PANE-Z" "peer-z" "cc-recover-safeguard PANE-Z"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'cc-relogin next'
}

@test "cc-blockers: a relogin row missing optional fields still shows acct + command" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","kind":"relogin-blocked","acct":"next4","recover_cmd":"cc-relogin next4"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'next4'
  echo "$output" | grep -qF 'cc-relogin next4'
}

@test "cc-blockers: relogin rows do not disturb the empty-board message" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","actor":"cc-reaper","kind":"surface-page","pane":"P0"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked sessions surfaced'
}

# ── 3. log rotation covers the cc-relogin*.log family ──────────────────────────────────────────

@test "rotation: cc-relogin-poll.log + cc-relogin.log are rotated by default" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  for f in cc-relogin-poll.log cc-relogin.log; do
    head -c 200 < /dev/zero | tr '\0' 'a' > "$H/.claude/logs/$f"
  done
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  for f in cc-relogin-poll.log cc-relogin.log; do
    [ -f "$H/.claude/logs/$f" ]                                    # recreated in place
    [ "$(wc -c < "$H/.claude/logs/$f" | tr -d ' ')" -eq 0 ]        # emptied
    ls "$H/.claude/logs/$f".* >/dev/null                           # a rotation exists
  done
  grep -q '"file":"cc-relogin-poll.log"' "$D/rot-idl.jsonl"
  grep -q '"file":"cc-relogin.log"' "$D/rot-idl.jsonl"
}

@test "rotation: a cc-relogin log under threshold is left untouched" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  head -c 50 < /dev/zero | tr '\0' 'a' > "$H/.claude/logs/cc-relogin-poll.log"
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$H/.claude/logs/cc-relogin-poll.log" | tr -d ' ')" -eq 50 ]
  ! ls "$H/.claude/logs/cc-relogin-poll.log".* >/dev/null 2>&1
}

@test "rotation: absent cc-relogin logs are a no-op, never a literal unmatched-glob target" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  ! ls "$H/.claude/logs/cc-relogin"* >/dev/null 2>&1   # no file named after the glob was created
  echo "$output" | grep -q 'skipped=4'                 # the 4 literal defaults only
}
