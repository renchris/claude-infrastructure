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
  # Fixture $HOME (hermeticity rule 1) + CC_TELEMETRY_DIR, whose default /tmp/cc-telemetry is
  # ABSOLUTE and so survives a fixtured $HOME untouched (rule 5). Measured, not assumed: 23/23 with
  # HOME pointed at an empty dir. Both are here so this suite can leave the host-suites partition.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # ── THE RUNNING PANE'S OWN SESSION ID IS IN THIS SUITE'S ENVIRONMENT (W3i D4) ───────────────────
  # `CLAUDE_CODE_SESSION_ID` is exported into every Bash tool call, so `sc()` — which runs the hook
  # with no identity of its own — handed the hook THIS session's id. Harmless until W3 taught `clear`
  # to refuse a sentinel another session armed: a sentinel armed as `sidA` then met a clear running
  # as `a4241557-…`, the refusal fired, and case 3 went red at line 101 in any ordinary session while
  # staying green under `env -u CLAUDE_CODE_SESSION_ID`. A verdict that depends on who ran the suite
  # is not a verdict. Every case that needs an identity now states it (`arm`, `sc_as`); the bare
  # helpers are the OPERATOR's shell, which carries none — and that is the one caller the refusal is
  # written to leave alone.
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"     # isolate the state dir from any real sentinel
  mkdir -p "$CLAUDE_CONFIG_DIR"
  # isolate the inbox too: the Stop-fold promotes .acked / takes mail for $ITERM_SESSION_ID's box, so
  # without this the actuation would mutate the REAL ~/.claude/mailbox of whatever pane runs the suite.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  # isolate the IDL too: the Stop-fold's abstain/decision rows append to the audit trail, so without
  # this every test writes to the LIVE ~/.claude/autonomy/idl.jsonl (404 leaked lines found 2026-07-25).
  # Only one test previously exported its own ($BATS_TEST_TMPDIR/bidl.jsonl) — that override still wins.
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # …and CC_IDL was NOT the seam this hook reads, so that isolation never bound (measured 2026-08-08,
  # backlog 22b839c85a52): run under an empty fixture $HOME, this suite deposited BOTH
  # .claude/autonomy/idl.jsonl and .claude/logs/session-continue.log — i.e. every run since had been
  # appending to the operator's live pair. hooks/session-continue.sh:58-59 reads CONTINUE_IDL /
  # CONTINUE_LOG; CC_IDL is real, but it belongs to hooks/lib/idl-log.sh and to boundary-handoff.sh,
  # which is why the line above still earns its place (the boundary test at the bottom drives it).
  # The seam was bound under a NAME the subject does not read, and a fix under the wrong name reads
  # exactly like a fix — the comment above asserted isolation for a year of runs that had none.
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"
  # PIN THE PANE. Without this, $_ouid is whatever pane RAN the suite — the suite is hermetic in its
  # paths and stubs yet still encodes the caller's identity, so a verdict can flip by pane. Two tests
  # already pinned it inline; those local exports still win.
  export ITERM_SESSION_ID="w0t0p0:CCCCCCCC-1111-2222-3333-444444444444"
  # SCOPE: this suite owns the SENTINEL actuator's contract (no sentinel ⇒ allow the stop). The WAKE
  # FLOOR is a second, independent reason the same hook may block a stop, and it deliberately fires on
  # exactly that no-sentinel path — so leaving it on here would make four base-behaviour assertions
  # test the floor instead of the sentinel. It is disabled here and owned end-to-end by
  # tests/wake-floor.bats. NOTE for a future reader: with the floor at its LIVE default (on), a
  # no-sentinel Stop in an unarmed session does NOT simply "allow" — see that suite.
  export CC_WAKE_FLOOR=0
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

# arm the sentinel from $CWD as session $2 (default sidA)
arm() { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" set "${1:-do the thing}" >/dev/null ); }
# a CLI subcommand (clear/status) run from $CWD with NO session identity — the operator's own shell
sc()  { ( cd "$CWD" && bash "$HOOK" "$@" ); }
# the same, run AS session $1 — an agent, or a recovery's clause D. The sid is what `clear` reads to
# decide whether the sentinel in this cwd is the caller's to remove.
sc_as() { local s="$1"; shift; ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="$s" bash "$HOOK" "$@" ); }
# arm with NO session identity — the operator's own bare-shell park. `set` writes no .sid sidecar
# on this path, which is exactly the evidence gap the ownership guard has to survive.
arm_anon() { ( cd "$CWD" && bash "$HOOK" set "${1:-do the thing}" >/dev/null ); }
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
  run sc status
  [[ "$output" == *ARMED* ]] || { echo "status after set: $output"; false; }
  # AS the arming session, WITH the guard asked for: the ordinary shape, and the one the
  # foreign-sid refusal must let through. `--if-mine` is what engages the guard at all (W3i B1) —
  # a bare `clear` is the unconditional verb trunk has always shipped, pinned by its own case below.
  run sc_as sidA clear --if-mine
  # ANCHORED, and NOT merely the substring `cleared`. The refusal text is
  # "refused — … nothing was cleared: <cwd>", so a bare `grep -q cleared` passes on the very path
  # this assertion exists to exclude — it went decorative the moment the refusal shipped.
  [[ "$output" == "cleared → "* ]] || { echo "clear did not disarm: $output"; false; }
  [[ "$output" != *refused* ]] || { echo "the arming session was REFUSED its own sentinel: $output"; false; }
  run sc status
  [[ "$output" == *inactive* ]] || { echo "the sentinel survived its own session's clear: $output"; false; }
}

@test "base DISCRIMINATOR: a clear from a FOREIGN sid refuses and the sentinel SURVIVES" {
  # The other half of the case above, and what makes its `!= *refused*` a live assertion rather than
  # a hope: same verb, same cwd, same sentinel — only the caller's identity differs.
  arm "do the thing" sidA
  run sc_as sidB clear --if-mine
  [ "$status" -eq 0 ] || { echo "a refusal is not an error: $output"; false; }
  [[ "$output" == refused\ * ]] || { echo "a foreign session cleared another session's chain: $output"; false; }
  run sc status
  [[ "$output" == *ARMED* ]] || { echo "THE SIBLING'S CHAIN WAS DISARMED: $output"; false; }
  [[ "$output" == *"do the thing"* ]] || { echo "the step text did not survive: $output"; false; }
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

# ── (a2) THE MULTI-LINE READER, AND WHY A COMMAND BODY IS NOT OPERATOR PROSE ──────────────────────
# Every kill-switch fixture ABOVE is a single line, which is exactly why the reader's blindness
# survived here after the same bug was fixed in the sibling hook (299e4d563). `jq -r … | tail -1`
# puts the message's OWN newlines into the stream, so tail takes the last LINE, not the last RECORD.
# Six short lines reach the regime — no size is needed, because the defect is line COUNT.
#
# The arms are built to fail independently: CONTROL and LAST-LINE are green on both branches (so a
# blanket suppressor cannot pass), FIRST-LINE is the reader, and META is the isMeta guard.
mkuser_tx_multi() { # <line1> … <lineN> → transcript path whose last user record is those lines
  local path="$BATS_TEST_TMPDIR/txm-${BATS_TEST_NUMBER}-$RANDOM.jsonl" body=""
  local l; for l in "$@"; do body="${body}${l}"$'\n'; done
  jq -nc --arg t "${body%$'\n'}" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}
# a typed operator message, then the harness-injected body of a slash command (isMeta=true) after it
mkuser_tx_meta() { # <typed-msg> <injected-line1> … → transcript path
  local path="$BATS_TEST_TMPDIR/txmeta-${BATS_TEST_NUMBER}-$RANDOM.jsonl" typed="$1" body=""; shift
  local l; for l in "$@"; do body="${body}${l}"$'\n'; done
  {
    jq -nc --arg t "$typed" '{type:"user",message:{content:[{type:"text",text:$t}]}}'
    jq -nc --arg t "${body%$'\n'}" \
      '{type:"user",isMeta:true,message:{content:[{type:"text",text:$t}]}}'
  } > "$path"
  printf '%s' "$path"
}

@test "(a2) CONTROL: a single-line kill phrase still clears + allows" {
  arm "grind" sidA
  run actuate sidA "$(mkuser_tx_multi "just fix the typo and stop")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "(a2) CONTROL: a multi-line message with NO kill phrase still BLOCKS (not a suppressor)" {
  arm "grind" sidA
  run actuate sidA "$(mkuser_tx_multi "here is what I want:" "read the plan" \
                        "then land it" "thanks" "one more thing" "run the gate")"
  fired "$output"
}

@test "(a2) THE BUG: kill phrase on the FIRST line of a multi-line message ⇒ clear + allow" {
  arm "finish the refactor" sidA
  run actuate sidA "$(mkuser_tx_multi "just do the one typo and stop" "context follows:" \
                        "the file is hooks/x.sh" "line four" "line five" "line six")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "(a2) kill phrase on the LAST line of a multi-line message ⇒ clear + allow" {
  arm "finish the refactor" sidA
  run actuate sidA "$(mkuser_tx_multi "context first:" "the file is hooks/x.sh" \
                        "line three" "line four" "line five" "no auto-continue")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "(a2) META: an injected /ship-shaped body carrying 'stop here' must NOT disarm the actuator" {
  # A `/foo` invocation injects the command or skill FILE's text as a user record flagged isMeta —
  # and those files discuss stopping (commands/ship.md:42 literally contains "stop here"). Once the
  # reader above stops truncating, that body becomes visible and would disarm the actuator, so
  # typing /ship would suppress the continuation on exactly the turn that lands code. The operator's
  # own typed message is the earlier record, and it is benign — so the correct answer is BLOCK.
  arm "finish the refactor" sidA
  run actuate sidA "$(mkuser_tx_meta "/ship" \
                        "Land the current work onto the remote trunk, safely." \
                        "The gate runs first; a red gate is real." \
                        "If the landing range escalates, stop here and surface it.")"
  fired "$output"
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

# ── v3 D11 — the in-loop fold must be HUMAN-visible too ──────────────────────────────────────────────
# The desk's continuation loop is the heaviest mail consumer in the fleet, and its deliveries ride
# decision:block — which the model sees but which renders nothing NAMING the delivery to the operator.
# Without a systemMessage here, D11 would light up the two drain boundaries and leave the busiest
# channel of all still invisible (U-1). The block itself must survive alongside it.
@test "D11 fold: an armed Stop carrying mail emits systemMessage AND still blocks" {
  local U="FFFFFFFF-1111-2222-3333-444444444444"
  printf '2026-07-25T10:00:00+0000 [cc-reaper] a page\n' > "$CC_MAILBOX_DIR/$U.md"
  arm "next step"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$U' bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  fired "$output"                                            # the continuation still blocks
  sm="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$sm" | grep -q '📬 1 message'
  printf '%s' "$sm" | grep -q 'cc-reaper'
  printf '%s' "$output" | jq -r '.reason' | grep -q 'a page'  # …and the mail is still in the reason
}

@test "D11 fold: an armed Stop with NO mail emits NO systemMessage (notice on delivery only)" {
  local U="99999999-1111-2222-3333-444444444444"
  arm "next step"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$U' bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]; fired "$output"
  [ "$(printf '%s' "$output" | jq -r '.systemMessage // "none"')" = "none" ]
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

# ════ `clear` REPORTS WHAT IT DID (backlog 2d0074dae889) ═════════════════════════════════════════
#
# The sentinel is $PWD-KEYED (sentinel_for "$PWD"), and `rm -f` on an absent file exits 0 — so the
# verb printed "cleared" whether it disarmed a live chain or looked in the wrong directory and
# touched nothing. MEASURED 2026-08-11 (session a28e8b9c): armed from the main checkout, cleared
# from a worktree, got "cleared", and the next Stop replayed the same step — `status` read ARMED at
# the checkout and inactive in the worktree, with nothing in between to say so. A success message
# that is independent of the effect is the claimed-outcome ≠ checked-outcome defect.

@test "clear: disarming something says so, and names the sentinel it removed" {
  cd "$BATS_TEST_TMPDIR" || false
  run bash "$HOOK" set "do the thing"
  [ "$status" -eq 0 ]
  run bash "$HOOK" clear
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^cleared → '
}

@test "clear DISCRIMINATOR: disarming NOTHING says THAT, and names the cwd it looked in" {
  # Same verb, same exit code, different fact — and the cwd is the actionable half, because the
  # sentinel NAME is a one-way hash of (config-dir|cwd) and cannot be read back into a directory.
  d="$BATS_TEST_TMPDIR/never-armed"; mkdir -p "$d"; cd "$d" || false
  run bash "$HOOK" clear
  [ "$status" -eq 0 ]                                 # NOT an error: clearing a deliberate park is normal
  echo "$output" | grep -q 'nothing to clear'
  echo "$output" | grep -qF "$d"
  ! echo "$output" | grep -q '^cleared → ' || false   # the two messages must not be confusable
}

@test "clear: a CROSS-CWD clear names the directory to re-run it from" {
  # The measured case end to end: arm in A, clear in B. B must report that it disarmed nothing AND
  # that this session still holds an armed sentinel in A — which is only answerable because `set`
  # stamps a .cwd sidecar beside the .sid one.
  export CLAUDE_CODE_SESSION_ID="sid-xcwd"
  a="$BATS_TEST_TMPDIR/wt-a"; b="$BATS_TEST_TMPDIR/wt-b"; mkdir -p "$a" "$b"
  cd "$a" || false; run bash "$HOOK" set "finish wave 3"; [ "$status" -eq 0 ]
  cd "$b" || false; run bash "$HOOK" clear
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing to clear'
  echo "$output" | grep -q 'armed sentinel elsewhere'
  echo "$output" | grep -qF "$a"
  # …and the chain in A is genuinely still armed — the report is not a consolation message.
  cd "$a" || false; run bash "$HOOK" status
  echo "$output" | grep -qi 'armed'
}

@test "clear: the cross-cwd report is SID-SCOPED — a sibling session's sentinel is not named" {
  # Without this, the scan would hand every session a list of every other session's armed
  # directories, which is the same bystander-noise defect the custody arm had.
  a="$BATS_TEST_TMPDIR/wt-sib-a"; b="$BATS_TEST_TMPDIR/wt-sib-b"; mkdir -p "$a" "$b"
  cd "$a" || false; CLAUDE_CODE_SESSION_ID="sid-them" run bash "$HOOK" set "their step"
  [ "$status" -eq 0 ]
  cd "$b" || false; CLAUDE_CODE_SESSION_ID="sid-mine" run bash "$HOOK" clear
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'nothing to clear'
  ! echo "$output" | grep -qF "$a" || false
}

# ── THE MECHANICAL ARM'S OWN DISPOSITIONS (A07 R5, 2026-09-08) ────────────────────────────────────
# The arm has two silent releases the sibling floors both record: the operator kill-switch (:825)
# and the peer exemption (:846). Silence there is the B-3 ambiguity this hook's header (:64-79)
# exists to remove — "stood down" was byte-identical to "never ran", so 47 releases in 11 days
# could be attributed to neither the switch nor the exemption, and the exemption's rc 0
# (*confirmed assignee*) could not be told from its rc 2 (*cannot read the process table*).
# Fixture technique is tests/mechanical-arm-exemption.bats' — a ledger stub on 🔧, an attribution
# stub that says the dirt is mine, and an assignee oracle driven by env — so ONLY the disposition
# under test can stop the block.
ma_fixture() { # arm the mechanical path: 🔧 ledger + own dirty files + ship floor off
  export CC_SHIP_FLOOR=0
  local wrap="$BATS_TEST_TMPDIR/ma-wrap"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "RUNG=🔧\nDIRTY=1\nUNLANDED=0\nREMAINDER=0\nTRUNK=origin/main\nAHEAD=0\n"' > "$wrap"
  chmod +x "$wrap"; export WRAP_LEDGER_BIN="$wrap"
  local sw="$BATS_TEST_TMPDIR/ma-sw.sh"
  printf '%s\n' 'session_dirty_mine() { printf "a.txt\n"; return 0; }' \
                'session_writes_paths() { return 0; }' \
                'session_writes_paths_turn() { return 0; }' \
                'session_wrote_here_this_turn() { return 0; }' \
                'session_unlanded_mine() { return 1; }' > "$sw"
  export SESSION_WRITES_LIB="$sw"
}
ma_ai_stub() { # $1 = rc echoed by agent_team_member_confirms; AI_ID empty ⇒ "not an assignee"
  local p="$BATS_TEST_TMPDIR/ma-ai.sh"
  printf '%s\n' "agent_assignee_argv() { [ -n \"\${AI_ID:-}\" ] && printf '%s' \"\$AI_ID\" && return 0; return 1; }" \
                "agent_team_member_confirms() { return $1; }" > "$p"
  export AGENT_IDENTITY_LIB="$p"
}
ma_actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "$1" "${2:-}" | bash "$HOOK" 2>/dev/null; }
# the disposition row this arm wrote, if any (reason is exact — a substring would also match
# `ship-floor-kill-switch`, which is a DIFFERENT floor's row and is not what is under test)
ma_row() { grep -F "\"reason\":\"$1\"" "$CONTINUE_IDL" 2>/dev/null | tail -1; }

@test "mechanical arm: CONTROL — the fixture really reaches the arm (it blocks)" {
  ma_fixture; ma_ai_stub 1; unset AI_ID
  run ma_actuate sid-ma-ctl ""
  [ "$status" -eq 0 ]; fired "$output"
}

@test "mechanical arm: an operator kill-switch release is LOGGED, not silent" {
  ma_fixture; ma_ai_stub 1; unset AI_ID
  local tx; tx="$(mkuser_tx "just fix the typo and stop")"
  run ma_actuate sid-ma-ks "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]              # released — the operator asked to stop
  [ -n "$(ma_row mechanical-kill-switch)" ]          # …and said so, attributably
}

@test "mechanical arm: CONTROL — no kill phrase ⇒ no kill-switch row (the row is caused, not constant)" {
  ma_fixture; ma_ai_stub 1; unset AI_ID
  run ma_actuate sid-ma-nok "$(mkuser_tx "please keep going")"
  [ "$status" -eq 0 ]; fired "$output"
  [ -z "$(ma_row mechanical-kill-switch)" ]
}

@test "mechanical arm: a CONFIRMED assignee release records assignee + confirm_rc=0" {
  ma_fixture; ma_ai_stub 0; export AI_ID="member-x"
  run ma_actuate sid-ma-c0 ""
  [ "$status" -eq 0 ]; [ -z "$output" ]
  local row; row="$(ma_row mechanical-assignee)"
  [ -n "$row" ]
  [ "$(printf '%s' "$row" | jq -r '.assignee')" = "member-x" ]
  [ "$(printf '%s' "$row" | jq -r '.confirm_rc')" = "0" ]
}

@test "mechanical arm: a CANNOT-TELL release is distinguishable — confirm_rc=2, not 0" {
  # The whole point of the field: rc 2 means the process table was unreadable, so the release is
  # evidence of ignorance rather than of a real assignee. Pre-fix both wrote the identical row.
  ma_fixture; ma_ai_stub 2; export AI_ID="member-y"
  run ma_actuate sid-ma-c2 ""
  [ "$status" -eq 0 ]; [ -z "$output" ]
  local row; row="$(ma_row mechanical-assignee)"
  [ -n "$row" ]
  [ "$(printf '%s' "$row" | jq -r '.confirm_rc')" = "2" ]
}

# ── W3i D6 — THE OWNERSHIP GUARD'S EVIDENCE IS OPTIONAL AT THE ARM ───────────────────────────────
# `set` writes ${f}.sid only when the session HAS an id (:145), so the OPERATOR'S own park — armed
# from a bare shell — records no owner at all. Requiring both sids to be known therefore made the
# guard strongest over agent-armed chains and INERT over exactly the sentinels a recovery running in
# a shared checkout is most likely to meet.

@test "clear: an ANONYMOUSLY armed sentinel is still not a foreign session's to remove" {
  arm_anon "the operator's parked step"
  run sc_as sidZ clear --if-mine
  [ "$status" -eq 0 ] || { echo "a refusal is not an error: $output"; false; }
  [[ "$output" == refused\ * ]] || { echo "an anonymous sentinel was cleared by a foreign session: $output"; false; }
  [[ "$output" == *"an unidentified armer"* ]] || { echo "the refusal does not say WHY it cannot tell: $output"; false; }
  run sc status
  [[ "$output" == *"the operator's parked step"* ]] || { echo "THE OPERATOR'S PARK WAS DISARMED: $output"; false; }
}

@test "clear CONTROL: the operator's OWN bare-shell clear still disarms an anonymous sentinel" {
  # The arm that keeps the fix from being a blanket refusal. A caller with no identity IS the
  # documented park gesture and must behave exactly as it did before.
  arm_anon "the operator's parked step"
  run sc clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "cleared → "* ]] || { echo "the operator's own park gesture was refused: $output"; false; }
}

@test "clear EQUIVALENCE GUARD: a sid-bearing clear over NOTHING is not a refusal, and spends the budget" {
  # Green in BOTH arms by construction, and named as such. The `[ -f "$f" ]` half of the widened
  # guard exists so that clearing where nothing is armed keeps reaching the mech-budget write:
  # without it a sid-bearing agent parking deliberate dirt would be REFUSED over an empty cwd, the
  # budget would never be spent, and the mechanical arm would re-block on the next Stop — the
  # snooze-button state this verb exists to end.
  d="$BATS_TEST_TMPDIR/never-armed-sid"; mkdir -p "$d"
  run bash -c "cd '$d' && CLAUDE_CODE_SESSION_ID=sidQ bash '$HOOK' clear --if-mine"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"nothing to clear"* ]] || { echo "$output"; false; }
  [[ "$output" != refused* ]] || { echo "refused with no sentinel present: $output"; false; }
  n="$(ls -1 "$CLAUDE_CONFIG_DIR/state"/continue-*.mech 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -ge 1 ] || { echo "the mech budget was not spent"; ls -la "$CLAUDE_CONFIG_DIR/state"; false; }
}

# ── W3i B1 — THE GUARD IS OPT-IN, BECAUSE AN INHERITED SID IS NOT A CLAIM ────────────────────────
# `CLAUDE_CODE_SESSION_ID` is exported into EVERY descendant of a Claude Code session, so a guard
# that reads it as "who is asking" convicts any script the session happens to run. Shipped ON by
# default it turned `tests/completion-assert.bats`' unchanged trunk control "double-block CONTROL:
# the marker is per-STOP — a later silent Stop convicts again" RED in any ordinary session, green
# under `env -u CLAUDE_CODE_SESSION_ID` — the A/B that attributed it. These two cases are the pair
# that keeps the flag load-bearing: without the first, `--if-mine` could be deleted everywhere and
# the suite would stay green; without the second, the guard could be restored to default-on.

@test "clear: the BARE verb is unconditional — trunk's shape, and what an inherited sid must not change" {
  # THE DEFAULT-ON RED PROOF. Same state as the DISCRIMINATOR case above — a sidA sentinel met by a
  # sidB caller — differing in one thing: no `--if-mine`. A guard restored to default-on turns this
  # red, which is the only evidence the opt-in is real.
  arm "do the thing" sidA
  run sc_as sidB clear
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "cleared → "* ]] || { echo "the bare verb refused, so the guard is still default-on: $output"; false; }
  run sc status
  [[ "$output" == *inactive* ]] || { echo "the bare verb did not disarm: $output"; false; }
}

@test "clear: an unknown flag is an ERROR, not a silently ignored word" {
  # A misspelled `--if-mine` that fell through to the unconditional path would clear a stranger's
  # sentinel while its caller believed it had asked for the guard — the fail-OPEN this flag makes
  # possible. rc 2 is the CLI vocabulary the `set`/`clear`/`status` arms already use for a misconfig.
  arm "do the thing" sidA
  run sc_as sidB clear --if-mien
  [ "$status" -eq 2 ] || { echo "an unknown flag did not refuse: rc=$status $output"; false; }
  run sc status
  [[ "$output" == *ARMED* ]] || { echo "the typo cleared the sentinel anyway: $output"; false; }
}

@test "status: an anonymously armed sentinel reports sid=unrecorded, never a session named ?" {
  # W3i C3. `set` stamps ${f}.sid only when the arming session HAS an id, so the no-sid state is
  # ORDINARY. `status` used to render it `sid=?`, and lr-ingest-verify's clause D2 read that one
  # layer up as a session literally named "?" — it printed "session ? has an armed continuation",
  # a sentence about a session that does not exist. Absence needs its own token.
  arm_anon "the operator's parked step"
  run sc status
  [[ "$output" == *"sid=unrecorded"* ]] || { echo "$output"; false; }
  [[ "$output" != *"sid=?"* ]] || { echo "the ? is back: $output"; false; }
}

# ── W3i ROUND 4 — THE FLAG FAILED OPEN ON AN ABSENT CALLER IDENTITY ──────────────────────────────
# D6 removed a refusal keyed on evidence the ARM need not have written. The same shape survived on
# the other side of the call: the guard additionally required `[ -n "$CLAUDE_CODE_SESSION_ID" ]`, so
# a caller that PASSED `--if-mine` and carried no identity skipped the guard entirely and cleared a
# stranger's chain — the incident this flag closes, re-opened through a MISSING identity rather than
# a foreign one. `--if-mine` asks one question, "did I arm this?", and a caller with no sid has
# already answered it: no. Unknown ownership is not consent, on either side.

@test "clear --if-mine: a caller that recorded NO sid is refused — it cannot be the armer" {
  arm "the owner's step" sidA
  run bash -c "cd '$CWD' && env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash '$HOOK' clear --if-mine"
  [ "$status" -eq 0 ] || { echo "a refusal is not an error: rc=$status $output"; false; }
  [[ "$output" == refused\ * ]] || { echo "an anonymous CALLER cleared sidA's chain: $output"; false; }
  # and it must say WHICH side is unidentified — "not by you ()" names nothing, and this refusal is
  # read by a human deciding whether their own park was just taken away.
  [[ "$output" == *"a caller that recorded no sid"* ]] || { echo "the refusal does not name the caller's missing identity: $output"; false; }
  # the message is not the outcome — the chain must still be armed (claimed ≠ checked)
  run sc status
  [[ "$output" == *"the owner's step"* ]] || { echo "SIDA'S CHAIN WAS DISARMED: $output"; false; }
}

@test "clear --if-mine: neither side identified is still a refusal, not a match on two empty strings" {
  # The arm a bare `[ "$_sc_owner" != "$_sc_cur" ]` cannot make: with the arm anonymous AND the
  # caller anonymous both sides are "", the inequality is FALSE, and the clear proceeds on a
  # coincidence of absence. Two unknowns are not a proof of identity.
  arm_anon "the operator's parked step"
  run bash -c "cd '$CWD' && env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID bash '$HOOK' clear --if-mine"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == refused\ * ]] || { echo "two empty sids compared EQUAL and cleared: $output"; false; }
  run sc status
  [[ "$output" == *"the operator's parked step"* ]] || { echo "THE OPERATOR'S PARK WAS DISARMED: $output"; false; }
}
