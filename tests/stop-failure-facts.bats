#!/usr/bin/env bats
# stop-failure-facts — ARM 3 of hooks/stop-failure-marker.sh (LIMIT_RECOVER_FLEET_V2 W4, § C4):
# under `$STATE/recon.on` a death writes ONE account fact through `lr_recon.facts hook-write`,
# and the teammate skip reads the transcript head PARSED rather than by substring.
#
# WHAT THIS PINS:
#   · SCOPE. auth (error or message), 5h/7d (rateLimitType off the death record), fable and
#     model:<name> (the model-scoped cap text); anything else writes nothing.
#   · INERT WITHOUT THE FLAG. recon.on absent ⇒ no facts dir at all.
#   · MERGE. A second death on the same scope is merged into the same file, never duplicated,
#     and the first writer keeps first_sid.
#   · PARSED TEAMMATE TEST. A real `agentName` head is skipped; `"agentName":null` is NOT (the old
#     grep skipped it).
#   · FAIL-OPEN. No jq on PATH ⇒ exit 0, empty stdout.
#
# Hermetic: HOME, the marker dir, the IDL and the limit-recover state all live in BATS_TEST_TMPDIR;
# CLAUDE_CONFIG_DIR is unset so the account resolves through the fixture accounts.json.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/stop-failure-marker.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR LR_STATE_DIR LR_RECON_ROOT CC_SF_REQUEST
  export STOP_FAILURE_MARKER_DIR="$BATS_TEST_TMPDIR/markers"
  export STOP_FAILURE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export STOP_FAILURE_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  printf '%s\n' '{"accounts":[{"name":"next","config_dir":"~/.claude"}]}' > "$STOP_FAILURE_ACCOUNTS"
  export STOP_FAILURE_LIMITED_DIR="$BATS_TEST_TMPDIR/limited"
  # The page, beat and kick are other arms' subjects; disabled so this suite forks none of them.
  mkdir -p "$STOP_FAILURE_LIMITED_DIR"; : > "$STOP_FAILURE_LIMITED_DIR/.page-off"
  export STOP_FAILURE_BEAT="$BATS_TEST_TMPDIR/no-beat"
  export STOP_FAILURE_LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl-stub"
  printf '#!/bin/bash\nexit 0\n' > "$STOP_FAILURE_LAUNCHCTL"; chmod +x "$STOP_FAILURE_LAUNCHCTL"
  export STOP_FAILURE_LR_STATE="$BATS_TEST_TMPDIR/lrstate"
  mkdir -p "$STOP_FAILURE_LR_STATE"
  FACTS="$STOP_FAILURE_LR_STATE/recon/facts"
}

recon_on() { : > "$STOP_FAILURE_LR_STATE/recon.on"; }

# A transcript whose last record is a cap death. $3 = rateLimitType, or "" for a record carrying
# no quotaLimits at all (the model-scoped caps do not carry one).
mk_tx() {  # $1 = path  $2 = uuid  $3 = rateLimitType
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' > "$1"
  if [ -n "${3:-}" ]; then
    jq -cn --arg u "$2" --arg r "$3" \
      '{type:"assistant", isApiErrorMessage:true, error:"rate_limit", uuid:$u,
        quotaLimits:{status:"rejected", resetsAt:1789853400, rateLimitType:$r},
        message:{content:[{type:"text", text:"capped"}]}}' >> "$1"
  else
    jq -cn --arg u "$2" \
      '{type:"assistant", isApiErrorMessage:true, error:"rate_limit", uuid:$u,
        message:{content:[{type:"text", text:"capped"}]}}' >> "$1"
  fi
}

payload() {  # $1 = sid  $2 = transcript  $3 = error  $4 = last_assistant_message
  jq -cn --arg sid "$1" --arg tp "$2" --arg err "$3" --arg msg "$4" \
    '{session_id:$sid, transcript_path:$tp, cwd:"/private/tmp/x", hook_event_name:"StopFailure",
      error:$err, last_assistant_message:$msg}'
}

nfacts() { find "$FACTS" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# Held in variables: bats mis-tokenizes an apostrophe inside `${VAR:-…}` (stop-failure-marker.bats).
MSG_5H="You've hit your session limit · resets 2:40pm (America/Chicago)"
MSG_FABLE="You've reached your Fable limit. Run /usage-credits to continue"
MSG_SONNET="You've hit your Sonnet limit · resets Oct 2 at 9am (America/Chicago)"

# ── scope ────────────────────────────────────────────────────────────────────────────────────────
@test "5h: rateLimitType five_hour writes next.5h with the window and the reset" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 five_hour
  run bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(nfacts)" -eq 1 ]
  jq -e '.acct=="next" and .scope=="5h" and .window=="five_hour" and .resets_at==1789853400
         and .src=="hook" and .first_sid=="a" and .untested==false' "$FACTS/next.5h.json" >/dev/null
}

@test "7d: rateLimitType seven_day writes next.7d" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 seven_day
  run bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(nfacts)" -eq 1 ]
  jq -e '.scope=="7d" and .window=="seven_day"' "$FACTS/next.7d.json" >/dev/null
}

@test "fable: the Fable cap text writes next.fable, untested" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 ""
  run bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_FABLE")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(nfacts)" -eq 1 ]
  jq -e '.scope=="fable" and .untested==true and .window==""' "$FACTS/next.fable.json" >/dev/null
}

@test "model: a named model cap writes model:<name lower>; model_scoped:<Name> does too" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 ""
  run bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_SONNET")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  jq -e '.scope=="model:sonnet" and .untested==false' "$FACTS/next.model:sonnet.json" >/dev/null
  mk_tx "$BATS_TEST_TMPDIR/tx/b.jsonl" u2 ""
  run bash "$HOOK" < <(payload b "$BATS_TEST_TMPDIR/tx/b.jsonl" rate_limit "cap model_scoped:Opus hit")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  jq -e '.scope=="model:opus"' "$FACTS/next.model:opus.json" >/dev/null
  [ "$(nfacts)" -eq 2 ]
}

@test "auth: authentication_failed writes next.auth; so does a 401 in the message" {
  recon_on
  run bash "$HOOK" < <(payload a "" authentication_failed "Not logged in · Please run /login")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  jq -e '.scope=="auth" and .first_sid=="a"' "$FACTS/next.auth.json" >/dev/null
  rm -f "$FACTS/next.auth.json"
  run bash "$HOOK" < <(payload b "" server_error "API Error: 401 token is invalid")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  jq -e '.scope=="auth" and .first_sid=="b"' "$FACTS/next.auth.json" >/dev/null
}

@test "no scope: a network death and a prose session cap with no rateLimitType write nothing" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 ""
  run bash "$HOOK" < <(payload a "" server_error "Connection error.")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$HOOK" < <(payload b "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(nfacts)" -eq 0 ]
}

@test "recon.on absent: a scoped death writes no fact and creates no facts dir" {
  mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 five_hour
  run bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -e "$STOP_FAILURE_LR_STATE/recon" ]
}

@test "merge: a second death on the same scope is merged into one file, first_sid kept" {
  recon_on
  mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 five_hour
  mk_tx "$BATS_TEST_TMPDIR/tx/b.jsonl" u2 five_hour
  bash "$HOOK" < <(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")
  local first; first="$(jq -r .observed_at "$FACTS/next.5h.json")"
  bash "$HOOK" < <(payload b "$BATS_TEST_TMPDIR/tx/b.jsonl" rate_limit "$MSG_5H")
  [ "$(nfacts)" -eq 1 ]
  jq -e --arg o "$first" '.first_sid=="a" and (.observed_at|tostring)==$o' \
    "$FACTS/next.5h.json" >/dev/null
}

# ── the parsed teammate test (ARM 2's SKIP 1) ────────────────────────────────────────────────────
@test "teammate: a named agentName head is skipped (no request, breadcrumb left)" {
  local tx="$BATS_TEST_TMPDIR/tx/t.jsonl"; mkdir -p "$(dirname "$tx")"
  printf '%s\n' '{"type":"user","agentName":"w4t","message":{"role":"user","content":"brief"}}' > "$tx"
  run bash "$HOOK" < <(payload t1 "$tx" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -e "$STOP_FAILURE_LR_STATE/requests/t1.json" ]
  [ -e "$STOP_FAILURE_LR_STATE/teammate-skip/t1" ]
}

@test "teammate: an \"agentName\":null head is NOT skipped — its request is written" {
  local tx="$BATS_TEST_TMPDIR/tx/n.jsonl"; mkdir -p "$(dirname "$tx")"
  printf '%s\n' '{"type":"user","agentName":null,"message":{"role":"user","content":"hi"}}' > "$tx"
  run bash "$HOOK" < <(payload n1 "$tx" rate_limit "$MSG_5H")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ -s "$STOP_FAILURE_LR_STATE/requests/n1.json" ]
  [ ! -e "$STOP_FAILURE_LR_STATE/teammate-skip/n1" ]
}

# ── fail-open ────────────────────────────────────────────────────────────────────────────────────
@test "no jq on PATH: exit 0 and empty stdout, even with recon.on" {
  recon_on; mk_tx "$BATS_TEST_TMPDIR/tx/a.jsonl" u1 five_hour
  local p="$BATS_TEST_TMPDIR/nojq" d f
  mkdir -p "$p"
  # macOS 15 ships /usr/bin/jq, so a bare /usr/bin:/bin PATH would still have it: mirror both
  # dirs by symlink with jq left out.
  for d in /bin /usr/bin; do
    for f in "$d"/*; do
      case "${f##*/}" in jq) continue ;; esac
      [ -e "$p/${f##*/}" ] || ln -s "$f" "$p/${f##*/}"
    done
  done
  local pl; pl="$(payload a "$BATS_TEST_TMPDIR/tx/a.jsonl" rate_limit "$MSG_5H")"
  run env PATH="$p" /bin/bash "$HOOK" <<<"$pl"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(nfacts)" -eq 0 ]
}
