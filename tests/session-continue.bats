#!/usr/bin/env bats
# session-continue.sh — 🔧 loose-ends continuation actuator + the three a19/a17 hardenings:
#   (a) KILL-SWITCH (D-8/I-2): an operator "…and stop" / "no auto-continue" / "just do X" / explicit
#       pause in the LAST user message clears a stale sentinel and ALLOWS the stop. RED today: the
#       actuator parses no phrase, so a stale sentinel BLOCKS the operator's stop (forces work).
#   (b) SID-BIND (S-12): `set` stamps the arming session id; actuation clears + ignores a sentinel
#       whose sid ≠ the actuating session's. RED today: a same-cwd successor inherits the
#       predecessor's sentinel and gets its first stops blocked with a rotted next-step.
#   (c) CAP RE-ARM (D-7): a fresh `set` zeroes .count; the block reason names the re-`set` lever each
#       turn; at the cap the hook names the lever (never a silent give-up) and allows the stop.
# Base behavior (no sentinel ⇒ allow; armed same-sid benign ⇒ block; set/clear/status) is preserved.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"     # isolate the state dir from any real sentinel
  mkdir -p "$CLAUDE_CONFIG_DIR"
  # isolate the inbox too: the Stop-fold promotes .acked / takes mail for $ITERM_SESSION_ID's box, so
  # without this the actuation would mutate the REAL ~/.claude/mailbox of whatever pane runs the suite.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

# arm the sentinel from $CWD as session $2 (default sidA)
arm() { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" set "${1:-do the thing}" >/dev/null ); }
# a CLI subcommand (clear/status) run from $CWD
sc()  { ( cd "$CWD" && bash "$HOOK" "$@" ); }
# actuation: Stop JSON on stdin. $1=session_id  $2=transcript_path.
# The stop DECISION is on stdout (block JSON / cap systemMessage JSON); stderr carries only
# human diagnostics (which bats would otherwise merge into $output) → drop it, assert on stdout.
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" 2>/dev/null; }
fired()   { printf '%s' "$1" | grep -q '"decision":"block"'; }

# transcript whose LAST genuine user message = $1 (array-of-text form), preceded by an earlier user
# text, an assistant turn, and a tool_result-only user record (which the extractor MUST skip).
mkuser_tx() {
  local path="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  {
    jq -nc '{type:"user",message:{content:[{type:"text",text:"earlier: build the thing"}]}}'
    jq -nc '{type:"assistant",message:{content:[{type:"text",text:"working on it"}]}}'
    jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"x",content:"ok"}]}}'
    jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'
  } > "$path"
  printf '%s' "$path"
}
# same, but the last user message uses STRING content (relayed operator/teammate form)
mkuser_tx_string() {
  local path="$BATS_TEST_TMPDIR/txs-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:$t}}' > "$path"
  printf '%s' "$path"
}

# ── BASE BEHAVIOR PRESERVED ──────────────────────────────────────────────────────
@test "base: no sentinel ⇒ allow the stop (no block)" {
  run actuate sidA ""
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "base: armed sentinel (same sid, benign last msg) ⇒ BLOCK with the next step" {
  arm "finish task X" sidA
  run actuate sidA "$(mkuser_tx "please keep going")"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q "finish task X"
}

@test "base: set arms → status ARMED; clear disarms → status inactive" {
  arm "do the thing" sidA
  run sc status; printf '%s\n' "$output" | grep -q "ARMED"
  run sc clear;  printf '%s\n' "$output" | grep -q "cleared"
  run sc status; printf '%s\n' "$output" | grep -q "inactive"
}

# ── (a) KILL-SWITCH ───────────────────────────────────────────────────────────────
@test "(a) '…and stop' in last user msg ⇒ clear + allow (stale sentinel overridden)" {
  arm "finish the refactor" sidA
  local tx; tx="$(mkuser_tx "just fix the typo and stop")"
  run actuate sidA "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]                 # allowed, NOT blocked
  run actuate sidA "$tx"; [ -z "$output" ]              # sentinel is gone (cleared)
}

@test "(a) discriminator: SAME sentinel blocks on benign msg, allows on kill phrase" {
  arm "finish the refactor" sidA
  run actuate sidA "$(mkuser_tx "please continue")";     fired "$output"   # benign ⇒ BLOCK
  arm "finish the refactor" sidA                                            # re-arm
  run actuate sidA "$(mkuser_tx "no auto-continue")";    [ -z "$output" ]  # kill  ⇒ ALLOW
}

@test "(a) each canonical kill phrase clears + allows" {
  local phrases=("just do X and stop" "no auto-continue" "just do the one fix" "stop here" "come back to this" "stop.")
  for p in "${phrases[@]}"; do
    arm "grind" sidA
    run actuate sidA "$(mkuser_tx "$p")"
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then echo "kill phrase did NOT clear: '$p' → $output" >&2; false; fi
  done
}

@test "(a) kill-switch also fires on a STRING-content user message" {
  arm "grind" sidA
  run actuate sidA "$(mkuser_tx_string "just do the hotfix and stop")"
  [ -z "$output" ]
}

@test "(a) benign 'stop' mention does NOT trigger the kill-switch (still continues)" {
  arm "grind" sidA
  run actuate sidA "$(mkuser_tx "please don't stop refactoring until tests pass")"
  fired "$output"                                         # no kill phrase ⇒ normal block
}

# ── (b) SID-BIND ──────────────────────────────────────────────────────────────────
@test "(b) successor (different sid) clears + allows an inherited sentinel" {
  arm "predecessor's leftover step" sidPRED
  local tx; tx="$(mkuser_tx "continue the work")"         # benign (no kill phrase)
  run actuate sidSUCC "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]                  # inherited sentinel cleared, allow
  run actuate sidSUCC "$tx"; [ -z "$output" ]            # proven cleared
}

@test "(b) discriminator: same-sid armed BLOCKS; different-sid CLEARS" {
  arm "step" sidX
  run actuate sidX "$(mkuser_tx "continue")"; fired "$output"     # same sid ⇒ BLOCK
  arm "step" sidX
  run actuate sidY "$(mkuser_tx "continue")"; [ -z "$output" ]    # diff sid ⇒ ALLOW
}

@test "(b) sentinel armed WITHOUT a session id ⇒ sid-check is a no-op (still blocks)" {
  ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="" CLAUDE_SESSION_ID="" bash "$HOOK" set "step" >/dev/null )
  run actuate sidANY "$(mkuser_tx "continue")"
  fired "$output"                                          # no stored sid ⇒ no wrong clear ⇒ block
}

# ── (c) CAP RE-ARM ────────────────────────────────────────────────────────────────
@test "(c) a fresh set resets the continuation counter to 0" {
  arm "grind" sidA
  local tx; tx="$(mkuser_tx "continue")"
  actuate sidA "$tx" >/dev/null                            # count→1
  actuate sidA "$tx" >/dev/null                            # count→2
  run sc status; printf '%s\n' "$output" | grep -q "2 continuations"
  arm "grind v2" sidA                                      # fresh set
  run sc status; printf '%s\n' "$output" | grep -q "0 continuations"
}

@test "(c) block reason names the re-arm lever (set) + counter-reset instruction each turn" {
  arm "grind" sidA
  run actuate sidA "$(mkuser_tx "continue")"
  fired "$output"
  printf '%s' "$output" | grep -q 'session-continue.sh set'
  printf '%s' "$output" | grep -qi "reset the continuation counter"
}

@test "(c) at the cap: allows the stop AND names the re-arm lever (never a silent give-up)" {
  export CLAUDE_CONTINUE_MAX=2
  arm "grind" sidA
  local tx; tx="$(mkuser_tx "continue")"
  run actuate sidA "$tx"; fired "$output"                  # continuation 1
  run actuate sidA "$tx"; fired "$output"                  # continuation 2
  run actuate sidA "$tx"                                   # n=2 ≥ MAX=2 ⇒ cap
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'systemMessage'          # cap emits a systemMessage — a block never does ⇒ proves ALLOW
  printf '%s' "$output" | grep -qi "cap"                   # names the cap
  printf '%s' "$output" | grep -q "set"                    # names the re-arm lever
}

@test "(c) continuation counter increments across stops (1,2,3…)" {
  export CLAUDE_CONTINUE_MAX=8
  arm "grind" sidA
  local tx; tx="$(mkuser_tx "continue")"
  run actuate sidA "$tx"; printf '%s' "$output" | grep -q "continuation 1/8"
  run actuate sidA "$tx"; printf '%s' "$output" | grep -q "continuation 2/8"
}

# ── (G-P6-6b) BOUNDARY COMPOSE-GUARD via the shared sentinel-path SSOT ─────────────
@test "(G-P6-6b) boundary computes the IDENTICAL sentinel path session-continue writes" {
  local armed; armed="$( cd "$CWD" && CLAUDE_CODE_SESSION_ID=x bash "$HOOK" set "x" )"
  local sc_path="${armed#armed → }"                        # path session-continue actually wrote
  local lib_path; lib_path="$( . "$REPO/hooks/lib/continue-sentinel.sh"; continue_sentinel_for "$CWD" )"
  [ -n "$sc_path" ]; [ "$sc_path" = "$lib_path" ]          # boundary's guard uses lib_path → must match
}

@test "(G-P6-6b) an armed session-continue sentinel SUPPRESSES boundary-handoff (double-inject killed)" {
  local BHOOK="$REPO/hooks/boundary-handoff.sh"
  local BWT="$BATS_TEST_TMPDIR/brepo"; mkdir -p "$BWT"
  git -C "$BWT" init -q; git -C "$BWT" config user.email t@t; git -C "$BWT" config user.name t
  echo x > "$BWT/f"; git -C "$BWT" add f; git -C "$BWT" commit -qm init
  local HEAD GITDIR; HEAD="$(git -C "$BWT" rev-parse HEAD)"
  GITDIR="$(git -C "$BWT" rev-parse --git-common-dir)"; case "$GITDIR" in /*) ;; *) GITDIR="$BWT/$GITDIR";; esac
  printf '%s' "$HEAD" > "$GITDIR/gate-green"               # committed + green tree (fire-eligible)
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"; mkdir -p "$CC_TELEMETRY_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/bidl.jsonl"
  export CC_BOUNDARY_LATCH_DIR="$BATS_TEST_TMPDIR/latch"
  unset CC_CONTINUE_SENTINEL                               # force boundary to compute via the shared lib
  local BSID="bsid-1"
  jq -nc --arg sid "$BSID" --arg cwd "$BWT" --arg cfg "$CLAUDE_CONFIG_DIR" --argjson ts "$(date +%s)" \
     '{ts:$ts,session_id:$sid,cwd:$cwd,config_dir:$cfg,used_pct:90,pid:1}' > "$CC_TELEMETRY_DIR/$BSID.json"
  bfire() { printf '{"session_id":"%s"}' "$BSID" | bash "$BHOOK" 2>/dev/null; }

  run bfire                                                # CONTROL: no sentinel ⇒ boundary FIRES
  printf '%s' "$output" | grep -q '"decision":"block"'
  ( cd "$BWT" && CLAUDE_CODE_SESSION_ID=y bash "$HOOK" set "loose ends" >/dev/null )   # arm for SAME cwd
  rm -rf "$CC_BOUNDARY_LATCH_DIR"                          # drop the control fire's latch (discriminating)
  run bfire                                                # TREATMENT: armed ⇒ boundary ABSTAINS
  [ -z "$output" ]                                         # no double-inject
  tail -1 "$CC_IDL" | grep -q 'continue-hook-armed'        # abstained for the RIGHT reason (not 'latched')
}

# ── FAIL-SAFE (a Stop hook must never block on an error) ──────────────────────────
@test "fail-safe: garbage stdin ⇒ exit 0, no block" {
  arm "step" sidA
  run bash -c 'printf "not json" | bash "$1" 2>/dev/null' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]                    # cwd unknown ⇒ no sentinel match ⇒ empty stdout
}

@test "fail-safe: missing transcript ⇒ kill-switch skipped, normal actuation (blocks same-sid)" {
  arm "step" sidA
  run actuate sidA "/no/such/transcript.jsonl"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── v2 comms LAG-ACK (the promote must fire on EVERY Stop, not only an armed continuation) ───────────
@test "lag-ack: the promote runs on a NO-sentinel Stop too — .acked folds to .seen (no guard false-alarm)" {
  local U="DDDDDDDD-1111-2222-3333-444444444444"
  printf 'page one\npage two\n' > "$CC_MAILBOX_DIR/$U.md"
  printf '2\n' > "$CC_MAILBOX_DIR/$U.seen"       # drain already SURFACED both (emitted); acked still behind
  printf '0\n' > "$CC_MAILBOX_DIR/$U.acked"
  # NO sentinel armed ⇒ the stop is allowed — but the promote MUST still fold .acked=.seen BEFORE that
  # exit, else a common unarmed Stop leaves .acked lagging forever and cc-inbox-guard false-alarms.
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$U' bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                # no decision:block — the sentinel gate still allows the stop
  [ "$(cat "$CC_MAILBOX_DIR/$U.acked")" -eq 2 ]   # …yet .acked was promoted to .seen unconditionally
}

@test "lag-ack discriminator: an unarmed Stop does NOT take (advance .seen) undelivered mail" {
  local U="EEEEEEEE-1111-2222-3333-444444444444"
  printf 'unseen page\n' > "$CC_MAILBOX_DIR/$U.md"    # a fresh line the drain has NOT surfaced (.seen=0)
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$U' bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # promote clamps to .seen (=0), so .acked stays 0; the take is gated to the armed path, so .seen is
  # NOT advanced here — the line stays pending for a real delivery boundary (no silent drop).
  [ "$(cat "$CC_MAILBOX_DIR/$U.acked" 2>/dev/null || echo 0)" -eq 0 ]
  [ "$(cat "$CC_MAILBOX_DIR/$U.seen" 2>/dev/null || echo 0)" -eq 0 ]
}
