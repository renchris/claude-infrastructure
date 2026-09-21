#!/usr/bin/env bats
# stop-failure-marker — the StopFailure consumer must collapse N deaths of ONE cause into ONE
# operator-visible fact, and must never make a noise on the death path.
#
# WHAT THIS PINS, and why each property is a test rather than a comment:
#   · COLLAPSE. One account hitting its cap or login cliff kills ~30 sessions at once. The marker is
#     keyed on the CAUSE (error × account), never the session, so 30 deaths write 30 lines into ONE
#     file. The CONTROL at the bottom mutates exactly that key to a session-keyed one and requires
#     this suite to go RED — without it, a suite asserting "1 file" proves nothing, because a script
#     that wrote nothing at all would also never write 30.
#   · CONCURRENCY. The 30 deaths are simultaneous. Every line must survive and none may interleave
#     into a malformed one — a single malformed line makes a reader's `jq -rs` slurp read as EMPTY,
#     which is the alarm going green over a live outage.
#   · SILENCE. Exit 0 and an EMPTY stdout on every path, including malformed input and no input.
#     This is Stop-family: a stray byte is not merely untidy, it can be read as a directive.
#   · IT IS NOT A PAGER. The hook must not notify anyone — paging stays with the reader that
#     consumes these markers. Asserted by pinning its whole write footprint.
#
# Hermetic: HOME is redirected into BATS_TEST_TMPDIR and CLAUDE_CONFIG_DIR is UNSET (on this box it
# points at a live account dir, which the subject reads to name the account). Nothing here touches
# ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/stop-failure-marker.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR
  export STOP_FAILURE_MARKER_DIR="$BATS_TEST_TMPDIR/markers"
  export STOP_FAILURE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export STOP_FAILURE_ACCOUNTS="$BATS_TEST_TMPDIR/accounts.json"
  cat > "$STOP_FAILURE_ACCOUNTS" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}
JSON
  # ── the LIMITED ARM's seams (LIMIT_DETECT_100P W1) ──
  # All four point OUTSIDE $HOME on purpose: the footprint test below diffs $HOME, and a seam that
  # defaulted under it would make every arm invisible to that assertion instead of pinned by it.
  # The two binaries are stubs that LOG THEIR ARGV, because "was it called, how many times, and
  # with what" is the whole question for a latch and for a kickstart flag.
  export STOP_FAILURE_LIMITED_DIR="$BATS_TEST_TMPDIR/limited"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  export STOP_FAILURE_BEAT="$REPO/hooks/session-beat.sh"
  export OSA_LOG="$BATS_TEST_TMPDIR/osa.log"
  export LC_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  export STOP_FAILURE_OSASCRIPT="$BATS_TEST_TMPDIR/osascript-stub"
  export STOP_FAILURE_LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl-stub"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$OSA_LOG"\n' > "$STOP_FAILURE_OSASCRIPT"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$LC_LOG"\n' > "$STOP_FAILURE_LAUNCHCTL"
  chmod +x "$STOP_FAILURE_OSASCRIPT" "$STOP_FAILURE_LAUNCHCTL"
  # ── ARM 2's seam (LIMIT_RECOVER_100P W5-F) ──
  # OUTSIDE $HOME for the same reason the four above are: the two footprint pins diff $HOME, and a
  # seam defaulting under it would make this arm invisible to them instead of pinned by them. Its
  # PRODUCTION default is under $HOME ($HOME/.reso/limit-recover), which is precisely why the seam
  # had to exist before the arm did.
  export STOP_FAILURE_LR_STATE="$BATS_TEST_TMPDIR/lrstate"
}

# The verbatim 2.1.260 five-hour cap text, held in a variable rather than written inline as a
# `${2:-...}` default. THAT IS NOT STYLE. bats' preprocessor mis-tokenizes an apostrophe inside a
# `${VAR:-default}` expansion, and it fails by SILENTLY TRUNCATING THE TEST LIST: with the text
# inline this file reported a clean `1..5` and ran five of its twenty-five tests, with no warning
# and no error. A suite that shrinks quietly is worse than one that breaks loudly — the count pin
# at the bottom of this file exists because of exactly this.
LIMIT_TEXT_5H="You've hit your session limit · resets 2:40pm (America/Chicago)"

# A rate_limit death — the only error class the limited arm reacts to.
limit_payload() {  # $1 = session id  $2 = last_assistant_message
  local sid="${1:-s1}" msg="${2:-}"
  [ -n "$msg" ] || msg="$LIMIT_TEXT_5H"
  jq -cn --arg sid "$sid" --arg msg "$msg" \
    '{session_id:$sid, transcript_path:("/tmp/hs/"+$sid+".jsonl"), cwd:"/private/tmp/hs/scratch",
      hook_event_name:"StopFailure", error:"rate_limit", last_assistant_message:$msg}'
}
pages()  { [ -f "$OSA_LOG" ] && wc -l < "$OSA_LOG" | tr -d ' ' || echo 0; }
kicks()  { [ -f "$LC_LOG" ]  && wc -l < "$LC_LOG"  | tr -d ' ' || echo 0; }
beatf()  { echo "$CC_BEAT_DIR/$1.json"; }

# The payload shape captured verbatim from 2.1.220 (/tmp/hs/log/stopfail.tsv, HOOK_SURFACE_100P W1).
real_payload() {   # $1 = session id  $2 = error (default authentication_failed)
  local sid="${1:-s1}" err="${2:-authentication_failed}"
  cat <<JSON
{"session_id":"${sid}","transcript_path":"/tmp/hs/${sid}.jsonl","cwd":"/private/tmp/hs/scratch",
 "prompt_id":"67784c16","effort":{"level":"high"},"hook_event_name":"StopFailure",
 "error":"${err}","last_assistant_message":"Not logged in · Please run /login"}
JSON
}

markers() { find "$STOP_FAILURE_MARKER_DIR" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' '; }
all_lines() { cat "$STOP_FAILURE_MARKER_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' '; }

# ── ARM 2 helpers (LIMIT_RECOVER_100P W5-F) ──────────────────────────────────────────────────────
requests()  { find "$STOP_FAILURE_LR_STATE/requests" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
tmpfiles()  { find "$STOP_FAILURE_LR_STATE/requests" -type f -name '.*' 2>/dev/null | wc -l | tr -d ' '; }
latches()   { find "$STOP_FAILURE_LR_STATE/requests-latch" -type f 2>/dev/null | wc -l | tr -d ' '; }
rqf()       { echo "$STOP_FAILURE_LR_STATE/requests/$1.json"; }

# A transcript whose LAST assistant record is a real cap death. The shape is not invented: it is
# the one tests/lr-predicate.bats:166 and tests/cc-limited.bats:257 already carry — `quotaLimits`
# is a TOP-LEVEL sibling of `message`, never nested inside it.
mk_transcript() {  # $1 = path  $2 = death uuid
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' > "$1"
  jq -cn --arg u "$2" \
    '{type:"assistant", isApiErrorMessage:true, error:"rate_limit", apiErrorStatus:429, uuid:$u,
      timestamp:"2026-09-19T20:29:28.332Z",
      quotaLimits:{status:"rejected", resetsAt:1789853400, rateLimitType:"five_hour"},
      message:{model:"<synthetic>", content:[{type:"text", text:"capped"}]}}' >> "$1"
}

# A teammate transcript: `agentName` is a TOP-LEVEL key on an early `user` record, which is why the
# first 8 KB answers the question (lr_predicate.py:423).
mk_teammate_transcript() {  # $1 = path
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '{"type":"user","agentName":"w5f","message":{"role":"user","content":"brief"}}' > "$1"
}

# The death payload with an explicit transcript and error — the shape every ARM 2 row needs.
rq_payload() {  # $1 = sid  $2 = transcript path  $3 = error  $4 = last_assistant_message
  local sid="$1" tp="$2" err="$3" msg="$4"
  [ -n "$err" ] || err="rate_limit"
  [ -n "$msg" ] || msg="$LIMIT_TEXT_5H"
  jq -cn --arg sid "$sid" --arg tp "$tp" --arg err "$err" --arg msg "$msg" \
    '{session_id:$sid, transcript_path:$tp, cwd:"/private/tmp/hs/scratch",
      hook_event_name:"StopFailure", error:$err, last_assistant_message:$msg}'
}

# ---- the fact it records ------------------------------------------------------------------------
@test "one death opens one marker carrying the error and the resolved account" {
  real_payload s1 | bash "$HOOK"
  [ "$(markers)" -eq 1 ] || false
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  jq -e '.error == "authentication_failed"' "$f" >/dev/null || false
  jq -e '.session_id == "s1"' "$f" >/dev/null || false
  jq -e '.last_assistant_message | test("Please run /login")' "$f" >/dev/null || false
  # the account is NOT in the payload — it is resolved from the config dir through the SSOT
  jq -e '.account == "next"' "$f" >/dev/null || false
}

@test "the marker FILENAME carries the cause, so a reader needs no parse to see which" {
  real_payload s1 | bash "$HOOK"
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next.jsonl' | grep -q . || false
}

@test "an account outside the SSOT still resolves — to its config-dir basename, never to blank" {
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-unlisted" real_payload s1 | true
  printf '%s' "$(real_payload s1)" | CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-unlisted" bash "$HOOK"
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__.claude-unlisted.jsonl' | grep -q . || false
}

# ---- THE POINT: collapse -----------------------------------------------------------------------
@test "30 CONCURRENT deaths of one cause collapse to ONE marker holding 30 lines" {
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$HOOK" & done
  wait
  [ "$(markers)" -eq 1 ] || false
  [ "$(all_lines)" -eq 30 ] || false
}

@test "no line is lost or interleaved under that concurrency — every line parses" {
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$HOOK" & done
  wait
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  # -e over the whole file: ONE malformed line makes a reader's slurp read as EMPTY, which is the
  # alarm going green over a live outage.
  jq -e -s 'length == 30 and all(.[]; .error == "authentication_failed")' "$f" >/dev/null || false
  # POSITIVE CONTROL for that assertion: it can see a malformed line when one is there.
  printf 'not json\n' >> "$f"
  run jq -e -s 'length == 30' "$f"
  [ "$status" -ne 0 ] || false
}

@test "a DIFFERENT cause is a different fact — two markers, not one" {
  real_payload s1 authentication_failed | bash "$HOOK"
  real_payload s2 usage_limit_reached  | bash "$HOOK"
  [ "$(markers)" -eq 2 ] || false
}

@test "the same error on a DIFFERENT account is also a different fact" {
  real_payload s1 | bash "$HOOK"
  printf '%s' "$(real_payload s2)" | CLAUDE_CONFIG_DIR="$HOME/.claude-quaternary" bash "$HOOK"
  [ "$(markers)" -eq 2 ] || false
  find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next4.jsonl' | grep -q . || false
}

@test "a runaway cause is bounded, and the capped marker does NOT look resolved" {
  local i
  for i in $(seq 1 6); do real_payload "s$i" | STOP_FAILURE_CAP=3 bash "$HOOK"; done
  [ "$(all_lines)" -eq 3 ] || false
  [ "$(markers)" -eq 1 ] || false          # the FACT survives the cap; only the census stops
  grep -q '"disposition":"passed","reason":"marker-capped"' "$STOP_FAILURE_IDL" || false
}

@test "SA10: the CAP DEFAULT is 500 — the file caps with no STOP_FAILURE_CAP in the environment" {
  # § 11 #7 REVERSES § 9 D3, which had proposed 5000. This row exists because the value is a
  # RULING, not a tuning knob, and every other cap assertion in this file passes STOP_FAILURE_CAP
  # explicitly — so all of them stay green at ANY default and none of them can see a drift in it.
  #
  # BEHAVIOURAL, not a grep. The marker is pre-filled to exactly the boundary with plain lines
  # (the cap is `wc -l`, which does not parse), so the two arms cost one hook invocation each
  # instead of 500. RED at pristine HEAD, where the default is 5000: arm A appends a 501st line
  # and the marker-capped row is never written.
  local f="$STOP_FAILURE_MARKER_DIR/authentication_failed__next.jsonl"
  mkdir -p "$STOP_FAILURE_MARKER_DIR"

  # arm A — AT the cap: no line is added, and the fact is logged as capped rather than dropped.
  seq 1 500 | sed 's/^/{"filler":/; s/$/}/' > "$f"
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 500 ] || false
  real_payload s1 | bash "$HOOK"
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 500 ] || false
  grep -q '"disposition":"passed","reason":"marker-capped"' "$STOP_FAILURE_IDL" || false

  # arm B — one BELOW it: the very same invocation appends, so arm A pinned the boundary and not
  # merely a hook that had stopped writing for some other reason.
  : > "$STOP_FAILURE_IDL"
  seq 1 499 | sed 's/^/{"filler":/; s/$/}/' > "$f"
  real_payload s2 | bash "$HOOK"
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 500 ] || false
  ! grep -q '"reason":"marker-capped"' "$STOP_FAILURE_IDL" || false
}

@test "SA11: the TTL DEFAULT is the seven_day window — a 6-day-old marker survives, an 8-day one does not" {
  # The other half of § 11 #7. EQUIVALENCE GUARD, not a red-proof: HEAD already carries 10080, so
  # this row is green in both arms of THIS wave. It is here for the mutant it kills — restoring the
  # pre-W1 `${STOP_FAILURE_TTL_MIN:-1440}` makes the 6-day arm go RED, which is the regression that
  # silently blanked the census over a session that was still weekly-capped. Verified by running
  # that mutant; see the RED-PROOF footer.
  local f="$STOP_FAILURE_MARKER_DIR/authentication_failed__next.jsonl"
  mkdir -p "$STOP_FAILURE_MARKER_DIR"

  # 6 days old — inside the seven_day window, so the record of the block outlives nothing yet.
  : > "$f"; touch -t "$(date -u -v-6d +%Y%m%d%H%M 2>/dev/null || date -u -d '6 days ago' +%Y%m%d%H%M)" "$f"
  real_payload s1 usage_limit_reached | bash "$HOOK"
  [ -f "$f" ] || false

  # 8 days old — past it, and a cause that stopped recurring stops being a fact.
  touch -t "$(date -u -v-8d +%Y%m%d%H%M 2>/dev/null || date -u -d '8 days ago' +%Y%m%d%H%M)" "$f"
  real_payload s2 usage_limit_reached | bash "$HOOK"
  [ ! -f "$f" ] || false
}

@test "a cause that stopped recurring self-retires at the TTL" {
  real_payload s1 | bash "$HOOK"
  [ "$(markers)" -eq 1 ] || false
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  touch -t 202501010000 "$f"
  real_payload s2 usage_limit_reached | STOP_FAILURE_TTL_MIN=60 bash "$HOOK"
  ! find "$STOP_FAILURE_MARKER_DIR" -name 'authentication_failed__next.jsonl' | grep -q . || false
  find "$STOP_FAILURE_MARKER_DIR" -name 'usage_limit_reached__next.jsonl' | grep -q . || false
}

# ---- silence on the death path -----------------------------------------------------------------
@test "exit 0 and EMPTY stdout on every input shape — Stop-family, never a gate" {
  local shape
  for shape in '{"hook_event_name":"StopFailure","error":"authentication_failed"}' \
               'not json at all' '{}' '' '{"error":""}'; do
    run bash -c "printf '%s' '$shape' | bash '$HOOK'"
    [ "$status" -eq 0 ] || false
    [ -z "$output" ] || false
  done
}

@test "it emits NOTHING on stderr either — including the very first death" {
  rm -rf "$STOP_FAILURE_MARKER_DIR"
  run bash -c "printf '%s' '$(real_payload s1 | tr -d '\n')' | bash '$HOOK' 2>&1 1>/dev/null"
  [ -z "$output" ] || false
}

@test "a payload with no error field abstains — it is LOGGED, never silent" {
  printf '%s' '{"session_id":"s","hook_event_name":"StopFailure"}' | bash "$HOOK"
  [ "$(markers)" -eq 0 ] || false
  grep -q '"disposition":"abstained","reason":"no-error-field"' "$STOP_FAILURE_IDL" || false
}

@test "IT IS NOT A PAGER: its entire write footprint is the marker and the IDL" {
  local before after
  before="$BATS_TEST_TMPDIR/before"; after="$BATS_TEST_TMPDIR/after"
  find "$HOME" -type f 2>/dev/null | sort > "$before"
  real_payload s1 | bash "$HOOK"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  # nothing written under HOME at all: markers + IDL are on their own env seams here
  diff -q "$before" "$after" >/dev/null || false
  # W5-F WIDENS this pin rather than weakening it. ARM 2 writes a recovery request, and a request
  # for a NON-CAP death would hand the poller a transplant for a session whose account is fine —
  # spending an account move on a problem that no longer exists. This is an authentication_failed
  # death, so the request arm must not be entered at all.
  [ "$(requests)" -eq 0 ] || false
  [ "$(latches)" -eq 0 ] || false
  # POSITIVE CONTROL: the detector can see a write under HOME when there is one.
  : > "$HOME/canary"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  run diff -q "$before" "$after"
  [ "$status" -ne 0 ] || false
}

# ══ THE LIMITED ARM (LIMIT_DETECT_100P W1) ═══════════════════════════════════════════════════════
# The hook already fired on 126 of 128 real rate_limit deaths, p50 0 s — and had ZERO consumers.
# Detection was never the missing piece; the missing pieces were an ADDRESS (which pane), a
# CORRECTED PRESENCE COUNT (the dead session still counted as active and refused a real recovery),
# and ONE page. The rows below pin each of those and, just as importantly, pin what the arm must
# NOT do: page per session, page for a non-cap death, or kick the poller unasked.

@test "SA1: KITTY_WINDOW_ID becomes the marker's pane" {
  # The address no store holds. 14 of 44 of one day's sessions had no registry row at all, and the
  # measured cause was a session carrying only KITTY_WINDOW_ID — an address session-register.sh
  # could not see. The marker is written by a hook that inherits the pane's environment, so it can
  # record what the registry missed.
  KITTY_WINDOW_ID=112 limit_payload d02d8feb | KITTY_WINDOW_ID=112 bash "$HOOK"
  local f; f="$(find "$STOP_FAILURE_MARKER_DIR" -name '*.jsonl' | head -1)"
  jq -e '.pane == "112"' "$f" >/dev/null || false
}

@test "SA2: the iTerm form is stripped to the bare id, and NO pane env is empty and silent" {
  ITERM_SESSION_ID='w0t0p0:112' limit_payload a1 | \
    env -u CC_PANE_ID -u KITTY_WINDOW_ID ITERM_SESSION_ID='w0t0p0:112' bash "$HOOK"
  jq -e 'select(.session_id=="a1") | .pane == "112"' \
     "$STOP_FAILURE_MARKER_DIR"/rate_limit__next.jsonl >/dev/null || false

  # THE NOUNSET CASE. `${ITERM_SESSION_ID##*:}` on an unset variable under `set -u` is an unbound
  # variable ERROR, not an empty string — measured exit 127 under bash 5.3. This hook runs on the
  # death path, so that would be a hard failure at the worst possible moment. Empty, exit 0, and
  # nothing on stdout is the required behaviour.
  local out rc=0
  out="$(limit_payload a2 | env -u CC_PANE_ID -u KITTY_WINDOW_ID -u ITERM_SESSION_ID \
         bash "$HOOK" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$out" ]
  jq -e 'select(.session_id=="a2") | .pane == ""' \
     "$STOP_FAILURE_MARKER_DIR"/rate_limit__next.jsonl >/dev/null || false
}

@test "SA3: an aliased config dir resolves to its ACCOUNT, never to a phantom named .claude" {
  # The phantom is real and it is on disk: five marker rows landed in
  # `authentication_failed__.claude.jsonl`, an account no ranker, poller or transplant target
  # knows. No accounts.json row names ~/.claude — `next` claims ~/.claude-next and reaches
  # ~/.claude through its `aliases` list — so the config_dir match missed and the basename
  # fallback minted a name out of a directory.
  cat > "$STOP_FAILURE_ACCOUNTS" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude-next","aliases":["claude"]},
             {"name":"next4","config_dir":"~/.claude-quaternary","aliases":[]}]}
JSON
  mkdir -p "$HOME/.claude"
  limit_payload s1 | env CLAUDE_CONFIG_DIR="$HOME/.claude" bash "$HOOK"
  [ -f "$STOP_FAILURE_MARKER_DIR/rate_limit__next.jsonl" ]
  [ ! -e "$STOP_FAILURE_MARKER_DIR/rate_limit__.claude.jsonl" ]

  # CONTROL: the alias clause is what did it. With the alias removed from the fixture the same
  # call falls back to the basename and the phantom reappears — so this row cannot be passing
  # because the config_dir happened to match.
  rm -f "$STOP_FAILURE_MARKER_DIR"/*.jsonl
  cat > "$STOP_FAILURE_ACCOUNTS" <<'JSON'
{"accounts":[{"name":"next","config_dir":"~/.claude-next","aliases":[]}]}
JSON
  limit_payload s2 | env CLAUDE_CONFIG_DIR="$HOME/.claude" bash "$HOOK"
  [ -f "$STOP_FAILURE_MARKER_DIR/rate_limit__.claude.jsonl" ]
}

@test "SA4: a rate_limit death flips the beat to limited; a non-cap death writes NO beat" {
  # THE PHANTOM ACTIVE. Stop never fires on a limit turn, so the beat keeps its last kind:"prompt"
  # and spawn-presence counts the corpse. Measured: 12 of 14 sids frozen that way, ACTIVE=10
  # against a ceiling of 8, and a real recovery parked at 9>8. Flipping four to `limited` took
  # ACTIVE to 7 and it admitted.
  local sid=beatsid
  mkdir -p "$CC_BEAT_DIR"
  # A prior beat with a sticky operator high-water mark. Writing through the EXISTING writer is
  # what preserves it; a hand-rolled write would drop operatorT and seq and silently demote a
  # session the operator had touched.
  jq -cn '{sid:"beatsid",pane:"9",cwd:"/tmp",pid:1,lstart:"x",t:1,kind:"prompt",who:"operator",
           operatorT:1789000000,seq:7}' > "$(beatf $sid)"
  limit_payload "$sid" | bash "$HOOK"
  jq -e '.kind == "limited"'      "$(beatf $sid)" >/dev/null || false
  jq -e '.who  == "auto"'         "$(beatf $sid)" >/dev/null || false
  jq -e '.operatorT == 1789000000' "$(beatf $sid)" >/dev/null || false
  jq -e '.seq == 8'               "$(beatf $sid)" >/dev/null || false

  # The arm is scoped to rate_limit. A login cliff or a network stall is NOT a capped session, and
  # stamping those `limited` would un-count a session that is genuinely still working.
  rm -f "$(beatf other)"
  real_payload other authentication_failed | bash "$HOOK"
  [ ! -e "$(beatf other)" ]
}

@test "SA5: the beat is written even when the marker file is already at CAP" {
  # THE PLACEMENT TEST. Every arm sits ABOVE the cap early-exit. A session whose account has
  # already logged CAP deaths is exactly the one most in need of a flipped beat, so an arm below
  # that exit would go silent during the mass event it exists for.
  export STOP_FAILURE_CAP=1
  mkdir -p "$STOP_FAILURE_MARKER_DIR"
  printf '{"pre":"existing"}\n' > "$STOP_FAILURE_MARKER_DIR/rate_limit__next.jsonl"
  limit_payload capsid | bash "$HOOK"
  # the marker itself is correctly capped — one line, not two
  [ "$(wc -l < "$STOP_FAILURE_MARKER_DIR/rate_limit__next.jsonl" | tr -d ' ')" -eq 1 ]
  grep -q '"reason":"marker-capped"' "$STOP_FAILURE_IDL" || false
  # …and the arms still ran
  jq -e '.kind == "limited"' "$(beatf capsid)" >/dev/null || false
  [ "$(pages)" -eq 1 ]
}

@test "SA6: 30 concurrent deaths of one cause send exactly ONE page" {
  # The flood this hook was built to prevent, now applied to the page itself. The latch is O_EXCL
  # (`( set -C; : > f )`), not check-then-write: 30 processes die simultaneously and a
  # `[ -e ] && write` has a window all 30 pass through. The key is derived from the PAYLOAD alone
  # — account plus the first 64 bytes of the message — so all 30 compute the same string with no
  # shared read and no coordination.
  local i
  for i in $(seq 1 30); do limit_payload "s$i" | bash "$HOOK" & done
  wait
  [ "$(pages)" -eq 1 ]
  [ "$(all_lines)" -eq 30 ]          # every death is still RECORDED; only the page collapses

  # A DIFFERENT cause is a different fact and gets its own page.
  limit_payload s31 "You've hit your weekly limit · resets 7am (America/Chicago)" | bash "$HOOK"
  [ "$(pages)" -eq 2 ]
  # A different ACCOUNT likewise.
  limit_payload s32 | env CLAUDE_CONFIG_DIR="$HOME/.claude-quaternary" bash "$HOOK"
  [ "$(pages)" -eq 3 ]
}

@test "CONTROL sid_keyed_latch_is_red: a session-keyed latch pages 30 times" {
  # Without this, SA6 is satisfiable by a hook that never pages at all. The mutant is the naive
  # shape — one latch per session — and it must turn SA6's count from 1 into 30.
  local mutant="$BATS_TEST_TMPDIR/latch-mutant.sh"
  sed 's|_sf_pg="$LIM/.paged/$(_sf_slug "$ACCOUNT")__.*|_sf_pg="$LIM/.paged/$(_sf_slug "$SID")"|' \
    "$HOOK" > "$mutant"
  grep -q '_sf_pg="$LIM/.paged/$(_sf_slug "$SID")"' "$mutant" || false   # the mutation applied
  local i
  for i in $(seq 1 30); do limit_payload "s$i" | bash "$mutant" & done
  wait
  [ "$(pages)" -eq 30 ]
}

@test "SA7: an unwritable latch FAILS OPEN — the page is sent and the IDL names it" {
  # The three outcomes of the create are NOT two. EEXIST means someone else already paged (stay
  # quiet). Any OTHER error — unwritable dir, full disk, bad mount — means the latch is broken, and
  # reading that as "already paged" silences the page for a cause nobody has heard about yet.
  # page-damp.sh:42-50 gets this wrong in the same direction and returns 0 on every failure.
  # A regular FILE where the directory belongs makes the create fail with ENOTDIR, and unlike a
  # chmod it still holds when the suite runs as root.
  mkdir -p "$STOP_FAILURE_LIMITED_DIR"
  : > "$STOP_FAILURE_LIMITED_DIR/.paged"
  limit_payload s1 | bash "$HOOK"
  [ "$(pages)" -eq 1 ]
  grep -q '"disposition":"abstained","reason":"page-latch-unwritable-sent"' "$STOP_FAILURE_IDL" || false

  # And it stays fail-open: a second death with the latch still broken pages again rather than
  # going quiet. A broken latch must never DEGRADE into a working one.
  limit_payload s2 | bash "$HOOK"
  [ "$(pages)" -eq 2 ]
}

@test "SA8: the kill switches are FILES, and the kick is OFF unless its sentinel exists" {
  # Files, not env vars, and the reason is the population: during a mass cap every affected pane is
  # ALREADY RUNNING, and no env var can reach a running process. `[ -e ]` costs nothing.
  mkdir -p "$STOP_FAILURE_LIMITED_DIR"

  # .kick-on ABSENT — the default. The poller is not woken.
  limit_payload k0 | bash "$HOOK"
  [ "$(kicks)" -eq 0 ]

  # .kick-on PRESENT — one bare kickstart. `-k` KILLS a running job, so it would abort the very
  # tick that is already doing the work this kick asks for.
  : > "$STOP_FAILURE_LIMITED_DIR/.kick-on"
  limit_payload k1 | bash "$HOOK"
  [ "$(kicks)" -eq 1 ]
  grep -qE "^kickstart gui/[0-9]+/com\.reso\.lr-reset-poller$" "$LC_LOG" || false
  # `run` + an explicit status check, never a bare `! grep`: under the harness's errexit an
  # inverted command can never abort the test, so a mid-body `! grep` passes whatever it finds.
  run grep -q -- '-k' "$LC_LOG"
  [ "$status" -ne 0 ]

  # .page-off silences the page and nothing else: the marker and the beat still happen, because
  # they are records, not interruptions.
  : > "$STOP_FAILURE_LIMITED_DIR/.page-off"
  rm -f "$OSA_LOG"
  limit_payload k2 "a brand new cause that has never been latched" | bash "$HOOK"
  [ "$(pages)" -eq 0 ]
  jq -e '.kind == "limited"' "$(beatf k2)" >/dev/null || false

  # .off silences the WHOLE arm — no beat, no page, no kick — while the marker keeps recording.
  : > "$STOP_FAILURE_LIMITED_DIR/.off"
  rm -f "$LC_LOG"
  limit_payload k3 | bash "$HOOK"
  [ ! -e "$(beatf k3)" ]
  [ "$(pages)" -eq 0 ]
  [ "$(kicks)" -eq 0 ]
  jq -e 'select(.session_id=="k3")' "$STOP_FAILURE_MARKER_DIR"/rate_limit__next.jsonl >/dev/null || false
}

@test "SA9: the armed footprint is marker + IDL + beat + latch + request + request-latch, nothing else" {
  # The original pin said the hook's entire footprint was the marker and the IDL, and enforced
  # "it is not a pager" by pinning that. The arm makes it a pager — exactly once per cause — so the
  # pin is WIDENED rather than deleted: it now names the things the arm may touch, and still
  # fails on one more. Every seam points outside $HOME, so a write under $HOME is still a violation.
  # W5-F widens it AGAIN, by the same rule and for the same reason: ARM 2 adds a request and a
  # request-latch, so they are NAMED here. This pin is the only thing standing between this hook
  # and an unreviewed write on the death path — it may be widened, never deleted or relaxed.
  local before after
  before="$BATS_TEST_TMPDIR/fp-before"; after="$BATS_TEST_TMPDIR/fp-after"
  find "$HOME" -type f 2>/dev/null | sort > "$before"
  limit_payload fp1 | bash "$HOOK"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  diff -q "$before" "$after" >/dev/null || false

  # the six permitted surfaces, each present and each on its own seam
  [ -s "$STOP_FAILURE_MARKER_DIR/rate_limit__next.jsonl" ]
  [ -s "$STOP_FAILURE_IDL" ]
  [ -s "$(beatf fp1)" ]
  [ "$(find "$STOP_FAILURE_LIMITED_DIR/.paged" -type f | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(requests)" -eq 1 ]
  [ "$(latches)" -eq 1 ]
  # and NOTHING is left half-written: the temp file is published by rename or removed, never kept
  [ "$(tmpfiles)" -eq 0 ]

  # POSITIVE CONTROL: the detector can still see a write under HOME when there is one.
  : > "$HOME/canary"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  run diff -q "$before" "$after"
  [ "$status" -ne 0 ]
}

# ══ ARM 2 · THE RECOVERY REQUEST (LIMIT_RECOVER_100P W5-F) ═══════════════════════════════════════
# Until this arm landed the recovery lane had exactly ONE producer — a human running
# `lr-fleet.sh --enqueue` — so the hook's detection (right on 126 of 128 real rate_limit deaths)
# started nothing. The rows below pin what the arm writes, and, with at least equal weight, what it
# must NOT do: request for a non-cap death, request for a teammate or a handed-off session,
# re-request a death it already requested, kick the poller unasked, or ever create the operator's
# `autorecover.on` flag itself.

@test "SB1: a cap death writes ONE request carrying the four keys the poller actually reads" {
  # THE CONSUMER FIXES THE SHAPE, not our plan. lr-reset-poller.sh:674 reads `.sid` and DESTROYS a
  # request without one (renamed `.malformed.json` into results/, never retried); :677 reads
  # `.target`, `.source_pane` and `.requested_by`. A key missing there is a request destroyed on
  # arrival, which is why these four are asserted by name and by non-emptiness.
  mk_transcript "$BATS_TEST_TMPDIR/tx/b1.jsonl" f4dead
  rq_payload b1 "$BATS_TEST_TMPDIR/tx/b1.jsonl" rate_limit "" | CC_PANE_ID=427 bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  local f; f="$(rqf b1)"
  jq -e '.sid == "b1"' "$f" >/dev/null || false
  jq -e '.target == "auto"' "$f" >/dev/null || false
  jq -e '.source_pane == "427"' "$f" >/dev/null || false
  jq -e '.requested_by == "stop-failure-marker"' "$f" >/dev/null || false
  # and every one of the four is non-empty, which is the property the poller depends on
  jq -e '[.sid, .target, .requested_by] | map(length > 0) | all' "$f" >/dev/null || false
}

@test "SB2: the request carries the enrichment the poller cannot re-derive from the payload" {
  # `resetsAt` and `rateLimitType` live ONLY in the transcript's death record; nothing in the
  # StopFailure payload names either. They ride the request so a later wave can schedule the
  # recovery at the reset rather than polling blind.
  mk_transcript "$BATS_TEST_TMPDIR/tx/b2.jsonl" f4dead
  rq_payload b2 "$BATS_TEST_TMPDIR/tx/b2.jsonl" rate_limit "" | bash "$HOOK"
  local f; f="$(rqf b2)"
  jq -e '.reset_at_epoch == "1789853400"' "$f" >/dev/null || false
  jq -e '.rate_limit_type == "five_hour"' "$f" >/dev/null || false
  jq -e '.death_uuid == "f4dead"' "$f" >/dev/null || false
  jq -e '.account == "next"' "$f" >/dev/null || false
  jq -e '.transcript_path | test("b2.jsonl")' "$f" >/dev/null || false
}

@test "SB3: the enrichment DEGRADES, never blocks — no transcript still produces a valid request" {
  # The hook is fail-open by construction. A transcript that is absent, rotated or unreadable must
  # cost the session its scheduling hint, never its recovery.
  rq_payload b3 "$BATS_TEST_TMPDIR/tx/does-not-exist.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  local f; f="$(rqf b3)"
  jq -e '.sid == "b3"' "$f" >/dev/null || false
  jq -e '.reset_at_epoch == ""' "$f" >/dev/null || false
  jq -e '.rate_limit_type == ""' "$f" >/dev/null || false
  # the latch still has a key, derived from the payload — never a constant, which would latch the
  # FIRST death for the life of the session and go silent on every later one
  [ "$(latches)" -eq 1 ]
}

@test "SB4: rate_limit_error — the second spelling of one fact — also earns a request" {
  rq_payload b4 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit_error "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  jq -e '.error == "rate_limit_error"' "$(rqf b4)" >/dev/null || false
}

@test "SB5: a NON-cap death writes no request, and a near-miss spelling is not a cap" {
  # A request for a non-cap death hands the poller a transplant for a session whose ACCOUNT is
  # fine — an account move spent on a problem that no longer exists (lr-fleet.sh:880-884 refuses
  # exactly that). The last two are near misses on purpose: the gate is an EXACT match on two
  # spellings, so a substring or prefix test would let them through.
  local e
  for e in authentication_failed usage_limit_reached network_error rate_limited limit; do
    rm -rf "$STOP_FAILURE_LR_STATE"
    rq_payload "b5-$e" "$BATS_TEST_TMPDIR/tx/none.jsonl" "$e" "" | bash "$HOOK"
    [ "$(requests)" -eq 0 ] || { echo "requested on error=$e"; false; }
  done
  # POSITIVE CONTROL: the same harness DOES produce a request for a real cap, so the five rows
  # above are measuring the gate and not a broken fixture.
  rm -rf "$STOP_FAILURE_LR_STATE"
  rq_payload b5-ok "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
}

@test "SB6: the KICK is gated on the operator flag, and the hook never creates that flag" {
  # 🚨 THE SAFETY PROPERTY OF THIS WHOLE ARM. `autorecover.on` is an OPEN OPERATOR DECISION
  # (LIMIT_RECOVER_100P:384, 85 % conviction, shipped default OFF) and it is what W5-A's poller
  # gate reads before draining anything this hook wrote. A hook that created it would decide the
  # operator's question for them and auto-transplant a whole fleet.
  rq_payload b6 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  [ "$(kicks)" -eq 0 ]
  [ ! -e "$STOP_FAILURE_LR_STATE/autorecover.on" ]

  # with the flag present the poller is woken — bare `kickstart`, never `-k` (which KILLS a running
  # job, aborting the very tick this is asking for), and never load/unload
  : > "$STOP_FAILURE_LR_STATE/autorecover.on"
  rq_payload b6b "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "a different cause entirely" | bash "$HOOK"
  [ "$(kicks)" -eq 1 ]
  grep -q 'kickstart gui/[0-9]*/com.reso.lr-reset-poller' "$LC_LOG" || { cat "$LC_LOG"; false; }
  ! grep -q -- '-k ' "$LC_LOG" || { cat "$LC_LOG"; false; }
  ! grep -qE '(^| )(load|unload|bootout)( |$)' "$LC_LOG" || { cat "$LC_LOG"; false; }
}

@test "SB7: a TEAMMATE is skipped — a breadcrumb and nothing else" {
  # Its lead owns its life: an assignee is woken over the teammate channel, and transplanting it
  # would put a second writer on one transcript.
  mk_teammate_transcript "$BATS_TEST_TMPDIR/tx/b7.jsonl"
  rq_payload b7 "$BATS_TEST_TMPDIR/tx/b7.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]
  [ "$(latches)" -eq 0 ]
  [ -e "$STOP_FAILURE_LR_STATE/teammate-skip/b7" ]
  grep -q '"disposition":"passed","reason":"request-skip-teammate"' "$STOP_FAILURE_IDL" || false
  # the MARKER still records the death — the skip is about the recovery lane, not about the record
  [ "$(markers)" -eq 1 ]
}

@test "SB8: a HANDED-OFF session is skipped, and the tomb is read BESIDE ITS OWN TRANSCRIPT" {
  # The tomb is per-session — lr-transplant writes `<sid>.HANDOFF.json` into the session's own
  # project dir. A global path here would let one handed-off session mute the whole fleet, which
  # during a mass cap is every session on the account.
  mk_transcript "$BATS_TEST_TMPDIR/tx/b8.jsonl" f8
  printf '%s\n' '{"ts":"2026-09-20T00:00:00Z"}' > "$BATS_TEST_TMPDIR/tx/b8.HANDOFF.json"
  rq_payload b8 "$BATS_TEST_TMPDIR/tx/b8.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]
  grep -q '"disposition":"passed","reason":"request-skip-handed-off"' "$STOP_FAILURE_IDL" || false

  # a tomb for a DIFFERENT sid, in the same directory, must not mute this one
  mk_transcript "$BATS_TEST_TMPDIR/tx/b8b.jsonl" f8b
  rq_payload b8b "$BATS_TEST_TMPDIR/tx/b8b.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  [ -f "$(rqf b8b)" ]
}

@test "SB9: a RE-FIRE of the same death does not re-request after the poller drained it" {
  # StopFailure re-fires for one sid — 22 of 42 sessions, up to 30 times (this file's own header).
  # The poller DELETES a request when it drains it, so without the latch every re-fire would
  # re-enqueue a recovery that already ran: a transplant loop with no bound.
  mk_transcript "$BATS_TEST_TMPDIR/tx/b9.jsonl" f9
  rq_payload b9 "$BATS_TEST_TMPDIR/tx/b9.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  rm -f "$(rqf b9)"                                     # the poller drains and deletes
  rq_payload b9 "$BATS_TEST_TMPDIR/tx/b9.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]
  grep -q '"disposition":"passed","reason":"request-latched"' "$STOP_FAILURE_IDL" || false
}

@test "SB10: a NEW death of the same session DOES re-request — the latch key is per death" {
  # The mirror of SB9, and the reason the latch may never key on the sid alone: a session capped
  # again next week must be recoverable again. lr-lib.sh:203-206 names the same trap.
  mk_transcript "$BATS_TEST_TMPDIR/tx/ba.jsonl" fa1
  rq_payload ba "$BATS_TEST_TMPDIR/tx/ba.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  rm -f "$(rqf ba)"
  mk_transcript "$BATS_TEST_TMPDIR/tx/ba.jsonl" fa2     # a DIFFERENT death record
  rq_payload ba "$BATS_TEST_TMPDIR/tx/ba.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  jq -e '.death_uuid == "fa2"' "$(rqf ba)" >/dev/null || false
  [ "$(latches)" -eq 2 ]
}

@test "SB11: a sid that cannot address a recovery produces no request at all" {
  # `.sid` is passed straight to `lr-fleet.sh --one`, and the poller DESTROYS a request with an
  # absent one. A sid that is missing, unknown or not path-safe is dropped, never sanitized — the
  # same rule the PANE guard follows, for the same reason: a half-cleaned address is worse than none.
  local p
  for p in '{"hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"x"}' \
           '{"session_id":"?","error":"rate_limit","last_assistant_message":"x"}' \
           '{"session_id":"../../etc/passwd","error":"rate_limit","last_assistant_message":"x"}' \
           '{"session_id":"a b","error":"rate_limit","last_assistant_message":"x"}'; do
    rm -rf "$STOP_FAILURE_LR_STATE"
    run bash -c "printf '%s' '$p' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(requests)" -eq 0 ] || { echo "requested for $p"; false; }
  done
  grep -q '"disposition":"passed","reason":"request-skip-bad-sid"' "$STOP_FAILURE_IDL" || false
}

@test "SB12: 30 CONCURRENT cap deaths write 30 parseable requests and leave no temp file" {
  # A per-sid request path is naturally collision-free; a shared temp name is NOT. 30 writers
  # arrive at once, so the temp file carries the pid and the publish is a rename.
  local i
  for i in $(seq 1 30); do
    rq_payload "c$i" "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK" &
  done
  wait
  [ "$(requests)" -eq 30 ]
  [ "$(latches)" -eq 30 ]
  [ "$(tmpfiles)" -eq 0 ]
  for i in $(seq 1 30); do
    jq -e --arg s "c$i" '.sid == $s and .requested_by == "stop-failure-marker"' "$(rqf "c$i")" >/dev/null \
      || { echo "bad request c$i"; false; }
  done
}

@test "SB13: three kill switches, each of which alone stops the request" {
  # CC_SF_REQUEST is the briefed switch and is honoured. The two FILE sentinels are not redundant
  # with it: this file's own header records why an env var is the weak form here — it cannot reach
  # a pane that is ALREADY RUNNING, and during a mass cap that is the entire population.
  rq_payload d1 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | CC_SF_REQUEST=off bash "$HOOK"
  [ "$(requests)" -eq 0 ]

  mkdir -p "$STOP_FAILURE_LIMITED_DIR"; : > "$STOP_FAILURE_LIMITED_DIR/.off"
  rq_payload d2 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]
  rm -f "$STOP_FAILURE_LIMITED_DIR/.off"

  mkdir -p "$STOP_FAILURE_LR_STATE"; : > "$STOP_FAILURE_LR_STATE/.request-off"
  rq_payload d3 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]
  rm -f "$STOP_FAILURE_LR_STATE/.request-off"

  # POSITIVE CONTROL: with every switch clear the same payload DOES produce a request, so the
  # three rows above are measuring the switches and not a permanently dead arm.
  rq_payload d4 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
}

@test "SB14: the request latches expire on the marker clock, so a cause can recur" {
  # Without this a latch from last week permanently suppresses this week's recurrence, and a
  # permanently latched arm reads exactly like an arm with nothing to do. Same rule as the page
  # latches, which expire on the same TTL.
  mkdir -p "$STOP_FAILURE_LR_STATE/requests-latch"
  : > "$STOP_FAILURE_LR_STATE/requests-latch/stale.oldkey"
  touch -t 202501010000 "$STOP_FAILURE_LR_STATE/requests-latch/stale.oldkey"
  rq_payload e1 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "" | STOP_FAILURE_TTL_MIN=60 bash "$HOOK"
  [ ! -e "$STOP_FAILURE_LR_STATE/requests-latch/stale.oldkey" ]
  [ "$(requests)" -eq 1 ]
}

@test "SB15: the request path is SILENT — exit 0, empty stdout, empty stderr" {
  # Stop-family. A stray byte here is not untidy, it can be read as a directive — and this arm runs
  # on the same death path as everything above it. The payload goes through a FILE, never inlined
  # into a `bash -c` string: it carries an apostrophe and a middle dot, and quoting it inline is
  # the class of mistake that silently changes what is under test.
  mk_transcript "$BATS_TEST_TMPDIR/tx/e2.jsonl" fe2
  rq_payload e2 "$BATS_TEST_TMPDIR/tx/e2.jsonl" rate_limit "" > "$BATS_TEST_TMPDIR/p-e2.json"
  run bash -c 'bash "$1" < "$2"' _ "$HOOK" "$BATS_TEST_TMPDIR/p-e2.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(requests)" -eq 1 ]

  # STDERR specifically, on the path that actually reaches a failed write: the requests directory
  # EXISTS but is not writable, so `mkdir -p` exits 0 and the abstain above it never fires. A
  # trailing `2>/dev/null` on the redirecting command does NOT cover this — the shell reports a
  # failed redirection itself, before the command runs — which is why the subject uses a group.
  rq_payload e3 "$BATS_TEST_TMPDIR/tx/e2.jsonl" rate_limit "" > "$BATS_TEST_TMPDIR/p-e3.json"
  chmod 500 "$STOP_FAILURE_LR_STATE/requests"
  run bash -c 'bash "$1" < "$2" 2>&1 1>/dev/null' _ "$HOOK" "$BATS_TEST_TMPDIR/p-e3.json"
  chmod 700 "$STOP_FAILURE_LR_STATE/requests"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "stderr: $output"; false; }
}

@test "SB17: an EXISTING but unwritable marker dir is still silent on the death path" {
  # PRE-EXISTING, found by W5-F and fixed in the same file. `mkdir -p` exits 0 on a directory that
  # already exists, so the abstain guarding the marker dir cannot fire for one that is merely
  # READ-ONLY, and the append then leaked the shell's own `Permission denied` to the real stderr.
  # Reproduced 2026-09-20; this row is the regression pin. It is a NON-cap death on purpose, so it
  # exercises the inherited marker write and nothing of ARM 2.
  chmod 500 "$STOP_FAILURE_MARKER_DIR" 2>/dev/null || { mkdir -p "$STOP_FAILURE_MARKER_DIR"; chmod 500 "$STOP_FAILURE_MARKER_DIR"; }
  real_payload s1 > "$BATS_TEST_TMPDIR/p-ro.json"
  run bash -c 'bash "$1" < "$2" 2>&1 1>/dev/null' _ "$HOOK" "$BATS_TEST_TMPDIR/p-ro.json"
  chmod 700 "$STOP_FAILURE_MARKER_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "stderr: $output"; false; }
}

@test "SB18: with NO transcript the latch key still tracks the death, never a constant" {
  # The degraded twin of SB10. When the transcript is gone the latch key falls back to the payload,
  # and the fallback may NOT be a constant: a constant would latch the FIRST death for the life of
  # the session and go silent on every later one — a session capped twice recovers once, forever.
  # The cap message carries the reset time, so it moves when the death does.
  rq_payload f1 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "hit your session limit resets 2:40pm" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  rm -f "$(rqf f1)"                                    # the poller drains and deletes
  rq_payload f1 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "hit your session limit resets 2:40pm" | bash "$HOOK"
  [ "$(requests)" -eq 0 ]                              # same death — latched
  rq_payload f1 "$BATS_TEST_TMPDIR/tx/none.jsonl" rate_limit "hit your weekly limit resets Tuesday" | bash "$HOOK"
  [ "$(requests)" -eq 1 ]                              # a DIFFERENT death — requested again
  [ "$(latches)" -eq 2 ]
}

@test "SB19: the enrichment survives a tail that starts MID-RECORD and carries junk" {
  # A tail ALWAYS starts mid-record on a real transcript, and a naive `jq -s` slurp fails the whole
  # stream on that first fragment — which reads as "this session has no death record" on exactly
  # the long-running sessions most likely to be capped. Measured: the slurp shape returns nothing
  # here; the per-line shape returns the death. The fixture also carries a bare scalar line and an
  # api-error record whose `quotaLimits` is a STRING, both before the real one.
  local tx total cut
  tx="$BATS_TEST_TMPDIR/tx/g1.jsonl"; mkdir -p "$(dirname "$tx")"
  {
    printf '{"type":"user","pad":"%s"}\n' "$(head -c 600 /dev/zero | tr '\0' 'x')"
    printf '123\n'
    printf '%s\n' '{"type":"assistant","isApiErrorMessage":true,"uuid":"u3","quotaLimits":"rejected"}'
    printf '%s\n' '{"type":"assistant","isApiErrorMessage":true,"uuid":"u4","timestamp":"2026-09-19T20:29:28.332Z","quotaLimits":{"resetsAt":1789853400,"rateLimitType":"five_hour"},"message":{"model":"<synthetic>","content":[]}}'
  } > "$tx"
  total="$(wc -c < "$tx" | tr -d ' ')"
  cut=$(( total - 300 ))                               # 300 bytes into the 600-byte first record
  rq_payload g1 "$tx" rate_limit "" | STOP_FAILURE_TAIL_BYTES="$cut" bash "$HOOK"
  [ "$(requests)" -eq 1 ]
  local f; f="$(rqf g1)"
  jq -e '.death_uuid == "u4"' "$f" >/dev/null || { cat "$f"; false; }
  jq -e '.reset_at_epoch == "1789853400"' "$f" >/dev/null || { cat "$f"; false; }
  jq -e '.rate_limit_type == "five_hour"' "$f" >/dev/null || { cat "$f"; false; }
}

@test "SB16: ANCHOR — requested_by is the exact literal W5-A's poller gate matches" {
  # 🚨 THIS IS A SAFETY ANCHOR, not a style pin. The poller's policy gate (LIMIT_RECOVER_100P W5-A)
  # refuses to drain a HOOK-ORIGINATED request unless the operator's `autorecover.on` flag exists,
  # and it identifies one by this string. Rename it and the gate stops matching — the requests then
  # look human-originated and drain unconditionally, auto-transplanting the fleet. The literal is
  # pinned in the SUBJECT as well as in the output, because a test asserting only the output would
  # go green against a subject that computed the same string a second way.
  [ "$(grep -c 'stop-failure-marker' "$HOOK")" -ge 2 ] || false
  grep -q -- '--arg by "stop-failure-marker"' "$HOOK" || false
}

# ---- the control that must be able to FAIL ------------------------------------------------------
@test "ANCHOR: this file's own test list is not silently truncated" {
  # MEASURED, not hypothetical. An apostrophe inside a `${VAR:-default}` expansion makes bats'
  # preprocessor stop emitting tests at that point: this file reported `1..5` and exited GREEN
  # while twenty of its twenty-five tests never ran. Nothing warned — not bats, not the gate, not
  # the TAP output, which is internally consistent at any length.
  #
  # So the plan line and the parsed list are compared here, in the suite itself, because a suite
  # is the one thing that cannot be trusted to report its own absence. grep counts what the FILE
  # declares; bats --count reports what the PARSER found; a gap between them is the failure.
  local declared parsed
  declared="$(grep -c '^@test' "$BATS_TEST_FILENAME")"
  parsed="$(cd "$REPO" && bats --count "$BATS_TEST_FILENAME" 2>/dev/null || echo -1)"
  [ "$parsed" -eq "$declared" ]
}

@test "ANCHOR: the cause-key line the control mutates still exists in the subject" {
  # If this goes to 0, the subject moved out from under the control below and the collapse
  # assertions have quietly stopped testing the thing they were written for.
  [ "$(grep -c 'ANCHOR: cause-keyed, never session-keyed' "$HOOK")" -eq 1 ] || false
}

@test "CONTROL session_keyed_is_red: a session-keyed mutant fails the collapse test" {
  # The whole value of this hook is the KEY. A mutant that keys on the session — the naive
  # page-per-death shape — must make "30 deaths ⇒ 1 marker" go RED. If it does not, the collapse
  # assertions are vacuous and this suite is decoration.
  local mutant="$BATS_TEST_TMPDIR/mutant.sh"
  sed 's|^CAUSE_KEY=.*ANCHOR: cause-keyed, never session-keyed$|CAUSE_KEY="$(_sf_slug "$SID")"|' \
    "$HOOK" > "$mutant"
  grep -q 'CAUSE_KEY="$(_sf_slug "$SID")"' "$mutant" || false     # the mutation actually applied
  local i
  for i in $(seq 1 30); do real_payload "s$i" | bash "$mutant" & done
  wait
  # RED under the mutant: 30 separate markers, which is 30 operator-visible facts for one event.
  [ "$(markers)" -eq 30 ] || false
}

# ── DEATH-PATH COST (LIMIT_DETECT_100P W1 DoD) ───────────────────────────────────────────────────
# The budget is 0.30 s, and it is a real budget: this hook runs at the instant a session dies, on
# every session of an account that just capped — ~30 of them at once. Measured 2026-09-20 on the
# cloud VM (Linux, bash 5.3, python3 3.11), three runs per arm, beat writer = the REAL
# hooks/session-beat.sh with CC_BEAT_DIR fixtured, osascript and launchctl stubbed. `/usr/bin/time`
# is absent there, so the timer is `date +%s%N` either side of the invocation.
#
#   arm                                                    armed              pristine trunk
#   A rate_limit, WINS the latch (beat + page + marker)    0.158 0.162 0.157  —  (no arm exists)
#   B rate_limit, LOSES the latch (beat + marker) x29/30   0.149 0.149 0.151  0.063 0.065 0.064
#   C authentication_failed — arm NOT entered              0.070 0.073 0.074  0.064 0.066 0.066
#
# Read off it. The cost of the arm on the population it is FOR is ~+90 ms, and effectively all of
# it is the beat fork — the page adds ~8 ms on the one winner, and the other 29 pay nothing for it
# because the O_EXCL latch fails without forking anything. The cost on every OTHER death — the
# overwhelming majority of this hook's traffic — is ~+7 ms, which is the three `[ -e ]` sentinels
# and one extra GC find. Nothing here approaches the budget.
#
# What was REJECTED for cost, each measured elsewhere and named so it is not re-proposed: a python
# fork for the cap (the census re-classifies anyway), `oi_origin_class` (3.17 s full-file grep on a
# 230 MB transcript), `agent_assignee_argv` (0.19-0.23 s ancestry walk), and reading the tier from
# the transcript (79 ms). The arm buys its latency with one fork it can justify and no reads at all.

# ══ RED-PROOF (LIMIT_DETECT_100P W1) ═════════════════════════════════════════════════════════════
# Every row W1 ADDS was run once against PRISTINE HEAD and its output is pasted verbatim. A row that
# CANNOT go red at HEAD is labelled an EQUIVALENCE GUARD and names the mutant it does kill — a row
# green in both arms proves nothing about the change it was written for, and saying so here is
# cheaper than a future session re-deriving it.
#
# ── SA10 · the CAP default ───────────────────────────────────────────────────────────────────────
# § 11 #7 REVERSES § 9 D3: the default STAYS 500, it does not rise to 5000. Pristine subject =
# `git show 0bc639660:hooks/stop-failure-marker.sh` (CAP default 5000), swapped in and run filtered:
#
#   1..1
#   not ok 1 SA10: the CAP DEFAULT is 500 — the file caps with no STOP_FAILURE_CAP in the environment
#   # (in test file tests/stop-failure-marker.bats, line 167)
#   #   `[ "$(wc -l < "$f" | tr -d ' ')" -eq 500 ] || false' failed
#
# Read it: at a 5000 default the hook appends a 501st line to a marker already at the boundary, so
# the cap never engages and no `marker-capped` row is written. Armed subject: `ok 1`.
#
# ── SA11 · the TTL default ───────────────────────────────────────────────────────────────────────
# EQUIVALENCE GUARD, stated as one. HEAD already carries 10080, so this row is green in both arms of
# W1 and no pristine run can redden it. The mutant it kills is the pre-W1 default restored —
# `sed 's|STOP_FAILURE_TTL_MIN:-10080|STOP_FAILURE_TTL_MIN:-1440|; s|TTL_MIN=10080 ;;|TTL_MIN=1440 ;;|'`:
#
#   1..1
#   not ok 1 SA11: the TTL DEFAULT is the seven_day window — a 6-day-old marker survives, an 8-day one does not
#   # (in test file tests/stop-failure-marker.bats, line 191)
#   #   `[ -f "$f" ] || false' failed
#
# Read it: at 1440 the 6-day-old marker is GC'd while the weekly cap that wrote it is still in
# force — the census going blank over a session that is still blocked, which is the whole failure
# § 11 #7's TTL half exists to prevent. Armed subject: `ok 2`.
#
# ══ DEATH-PATH COST — the TWO arms § 11 #8 requires ══════════════════════════════════════════════
# Measured 2026-09-20 on THIS box (Darwin 24.6, 10 cores, bash 3.2 via /bin/bash), `/usr/bin/time -p`,
# WINNER path every run (the latch dir is cleared between runs, so each run also pays the page —
# the worst case, not the typical one).
#
#   arm                                                        runs   readings / statistic
#   (i)  beat writer STUBBED — the HOOK's own budget            3     0.29  0.15  0.13
#   (ii) beat writer REAL (hooks/session-beat.sh)              20     min 0.17 · median 0.18 · p95 0.20 · max 0.31
#   CONTROL authentication_failed — the arm is NOT entered       3     0.08  0.08  0.08
#
# 🚨 THE 0.30 s BAR BELONGS TO ARM (i), and arm (ii) is not judged against it — § 11 #8 makes (ii)'s
# OWN p95 the recorded bar, which is **0.20 s**. Both clear 0.30 anyway. The first reading in each
# arm is a cold-cache outlier (0.29, 0.31) and is kept rather than trimmed, because the death path
# IS cold on the first session of a mass cap.
#
# 🚨 LOAD IS PART OF THE MEASUREMENT, and omitting it would have inverted this verdict. Taken at
# 1-min load 7.96 on 10 cores. The SAME harness four hours earlier, at load 141 (eight concurrent
# bats roots), read arm (i) as 0.47 / 0.34 / 0.32 — three clean breaches of the bar. What refutes
# the obvious reading is the CONTROL, which does not enter the arm at all and still read 0.22 s
# there against 0.08 s here: the box was ~3x inflated and the hook was never the subject. A latency
# bar quoted without the load beside it is a fact about the machine wearing a verdict's clothes
# (fleet memory: a-cure-is-verified-only-under-the-load-that-caused-it, inverted).
#
# What the arm costs, read off the rows: ~+0.10 s on the population it is FOR (page + beat + the
# three sentinels) and ~+0.07 s on every other death, which is the sentinels and one extra GC find.
