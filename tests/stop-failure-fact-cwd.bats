#!/usr/bin/env bats
# stop-failure-fact-cwd — ARM 3 of hooks/stop-failure-marker.sh must not import from the capped
# session's cwd (LR sustained-load W0b, G2 review C1).
#
# The hook runs with the dying session's cwd, and `python3 -m lr_recon.facts` puts the cwd at
# sys.path[0], ahead of the stdlib. facts.py imports json, so a json.py sitting in that cwd ran
# inside the fact writer, against the live facts tree. The cure runs the write from the package's
# own parent dir with `/usr/bin/python3 -E -s`.
#
# WHAT THIS PINS:
#   · NO HIJACK. A planted json.py in the cwd that writes a marker: the marker exists before the
#     fix and is absent after.
#   · THE WRITE STILL HAPPENS. The same run writes the account fact, so the cure cannot pass by
#     breaking the write (a write that never runs also never imports the planted file).
#   · THE PLANT IS LIVE. A control imports json from that cwd and sees the marker, so the first
#     test cannot pass on an inert plant.
#
# Hermetic: the same seams as stop-failure-facts.bats — HOME, the marker dir, the IDL and the
# limit-recover state all live in BATS_TEST_TMPDIR; CLAUDE_CONFIG_DIR is unset.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/stop-failure-marker.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR LR_STATE_DIR LR_RECON_ROOT CC_SF_REQUEST PYTHONPATH
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export STOP_FAILURE_MARKER_DIR="$BATS_TEST_TMPDIR/markers"
  export STOP_FAILURE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export STOP_FAILURE_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  printf '%s\n' '{"accounts":[{"name":"next","config_dir":"~/.claude"}]}' > "$STOP_FAILURE_ACCOUNTS"
  export STOP_FAILURE_LIMITED_DIR="$BATS_TEST_TMPDIR/limited"
  mkdir -p "$STOP_FAILURE_LIMITED_DIR"; : > "$STOP_FAILURE_LIMITED_DIR/.page-off"
  export STOP_FAILURE_BEAT="$BATS_TEST_TMPDIR/no-beat"
  export STOP_FAILURE_LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl-stub"
  printf '#!/bin/bash\nexit 0\n' > "$STOP_FAILURE_LAUNCHCTL"; chmod +x "$STOP_FAILURE_LAUNCHCTL"
  export STOP_FAILURE_LR_STATE="$BATS_TEST_TMPDIR/lrstate"
  mkdir -p "$STOP_FAILURE_LR_STATE"; : > "$STOP_FAILURE_LR_STATE/recon.on"
  # The hook bounds the fact write at 2 s. At load ~250 a cold python3 import overran that, the fact
  # was never written, and the land gate's off-box run read this suite red. The bound is not this
  # suite's subject, so it is widened here; the hijack assertion does not depend on it.
  export STOP_FAILURE_FACT_TIMEOUT_S=120
  FACTS="$STOP_FAILURE_LR_STATE/recon/facts"
  # The capped session's cwd, holding the planted module. It writes the marker on import, but only
  # inside ARM 3's own process (`hook-write` in argv): the teammate predicate (lr-predicate.sh,
  # `python3 -c`) imports json from the same cwd earlier in the hook, and that site is not ARM 3.
  CWD="$BATS_TEST_TMPDIR/session-cwd"; mkdir -p "$CWD"
  HIJACK="$BATS_TEST_TMPDIR/hijacked"
  printf 'import sys\nif "hook-write" in sys.argv:\n    open(%s, "w").write("hijacked\\n")\n' \
    "'$HIJACK'" > "$CWD/json.py"
  TX="$BATS_TEST_TMPDIR/tx/a.jsonl"; mkdir -p "$(dirname "$TX")"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' > "$TX"
  jq -cn '{type:"assistant", isApiErrorMessage:true, error:"rate_limit", uuid:"u1",
           quotaLimits:{status:"rejected", resetsAt:1789853400, rateLimitType:"five_hour"},
           message:{content:[{type:"text", text:"capped"}]}}' >> "$TX"
}

payload() {  # $1 = cwd
  jq -cn --arg tp "$TX" --arg cwd "$1" \
    '{session_id:"a", transcript_path:$tp, cwd:$cwd, hook_event_name:"StopFailure",
      error:"rate_limit", last_assistant_message:"capped"}'
}

@test "a json.py planted in the session cwd is not imported by the fact write, and the fact is still written" {
  cd "$CWD"
  run /bin/bash "$HOOK" < <(payload "$CWD")
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # RED before the fix: the planted module ran, and the write it hijacked failed.
  [ ! -e "$HIJACK" ]
  jq -e '.acct=="next" and .scope=="5h" and .first_sid=="a"' "$FACTS/next.5h.json" >/dev/null
}

@test "control: the planted module is live — imported from that cwd, it does write the marker" {
  # Without this the test above could pass because the plant itself was inert.
  cd "$CWD"
  run /usr/bin/python3 -c 'import json' hook-write
  [ -e "$HIJACK" ]
}
