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

@test "SA9: the armed footprint is marker + IDL + beat + latch, and nothing else" {
  # The original pin said the hook's entire footprint was the marker and the IDL, and enforced
  # "it is not a pager" by pinning that. The arm makes it a pager — exactly once per cause — so the
  # pin is WIDENED rather than deleted: it now names the four things the arm may touch, and still
  # fails on a fifth. Every seam points outside $HOME, so a write under $HOME is still a violation.
  local before after
  before="$BATS_TEST_TMPDIR/fp-before"; after="$BATS_TEST_TMPDIR/fp-after"
  find "$HOME" -type f 2>/dev/null | sort > "$before"
  limit_payload fp1 | bash "$HOOK"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  diff -q "$before" "$after" >/dev/null || false

  # the four permitted surfaces, each present and each on its own seam
  [ -s "$STOP_FAILURE_MARKER_DIR/rate_limit__next.jsonl" ]
  [ -s "$STOP_FAILURE_IDL" ]
  [ -s "$(beatf fp1)" ]
  [ "$(find "$STOP_FAILURE_LIMITED_DIR/.paged" -type f | wc -l | tr -d ' ')" -eq 1 ]

  # POSITIVE CONTROL: the detector can still see a write under HOME when there is one.
  : > "$HOME/canary"
  find "$HOME" -type f 2>/dev/null | sort > "$after"
  run diff -q "$before" "$after"
  [ "$status" -ne 0 ]
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
