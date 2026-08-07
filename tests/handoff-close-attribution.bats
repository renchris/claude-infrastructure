#!/usr/bin/env bats
# handoff-fire: every pane close is GUARDED and ATTRIBUTED.
#
# Regression under test (2026-08-07, docs/plans/PANE_THEFT_2026-08-07.md). Three call sites each ran
# a bare `it2 session close -f -s "$x"`, and between them they recorded nothing: handoffs.jsonl
# carries firing_sid and target_pane only, and the fire's stderr — the sole place the close sites
# ever spoke — is captured to a mktemp by cc-dispatch and deleted UNREAD on rc 0. When an autonomous
# fire destroyed a pane the operator was composing into, there was no artifact anywhere that named
# which call had done it.
#
# Two properties are pinned here:
#   1. hf_close_pane REFUSES the closes that can only be wrong — an empty id, the fire's own anchor,
#      and (in peer mode) a pane that is not provably agent-owned.
#   2. every attempt, refusals included, lands a durable row. A refusal is the most interesting row
#      there is, so a guard that refused silently would re-create the blindness it was built to end.
#
# Behavioural: the real functions are extracted from the shipped script and driven with stubbed
# transport, so the assertions run the artifact rather than a paraphrase of it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/cc-fired" "$HOME/.claude/cc-registry" "$HOME/.claude/logs"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIRE="$REPO/scripts/handoff-fire.sh"
  [ -f "$FIRE" ] || skip "handoff-fire.sh not found at $FIRE"

  export CC_CLOSE_ATTRIB_LOG="$BATS_TEST_TMPDIR/close-attrib.jsonl"
  CLOSED_LOG="$BATS_TEST_TMPDIR/closed.log"
  export CLOSED_LOG

  LIVE_PID=$$

  # Extract the three real functions. Each is a plain `name() { … }` block terminated by a lone `}`.
  LIB="$BATS_TEST_TMPDIR/lib.sh"
  {
    sed -n '/^hf_pane_agent_owned()/,/^}/p' "$FIRE"
    sed -n '/^hf_close_pane()/,/^}/p'      "$FIRE"
    sed -n '/^hf_close_attrib()/,/^}/p'    "$FIRE"
  } > "$LIB"
  grep -q '^hf_close_pane()'   "$LIB" || skip "could not extract hf_close_pane from $FIRE"
  grep -q '^hf_close_attrib()' "$LIB" || skip "could not extract hf_close_attrib from $FIRE"

  # Stubbed transport. `in_kitty` false keeps the post-close verification on the iterm2 arm, so a
  # test never has to reach a live terminal; the close itself is recorded by the stub instead.
  STUBS="$BATS_TEST_TMPDIR/stubs.sh"
  cat > "$STUBS" <<'SH'
in_kitty() { return 1; }
kt_window_field() { return 0; }
hf_bounded() {
  # record exactly what was asked to be destroyed — the evidence the real sites never produced
  printf '%s\n' "$*" >> "$CLOSED_LOG"
  return 0
}
SH
}

own() { # $1=window id — agent-owned: fired-peer marker + live registry pid
  printf '{"paneUUID":"%s","closedAt":null}' "$1" > "$HOME/.claude/cc-fired/$1.json"
  printf '{"paneUUID":"%s","pid":%s}' "$1" "$LIVE_PID" > "$HOME/.claude/cc-registry/$1.json"
}

close_pane() { # $1=id $2=site $3=mode ; optional FIRING_SID via env
  bash -c ". '$LIB'; . '$STUBS'; hf_close_pane '$1' '$2' '$3'"
}

attrib_rows() { cat "$CC_CLOSE_ATTRIB_LOG" 2>/dev/null; }
closes()      { cat "$CLOSED_LOG" 2>/dev/null; }

# ── the refusals ──────────────────────────────────────────────────────────────────────

@test "a close is REFUSED when the pane is the fire's own anchor" {
  # The incident shape: a background fire anchors on a pane and then destroys it. This invariant
  # holds even when ownership is unprovable, which is why it is checked first and unconditionally.
  own 300
  run env FIRING_SID=300 bash -c ". '$LIB'; . '$STUBS'; hf_close_pane 300 restore-focus-or-fail spawn"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "own ANCHOR"
  # and nothing was actually asked to close
  [ -z "$(closes)" ]
  attrib_rows | grep -q '"verdict":"refused-is-anchor"'
}

@test "the anchor invariant survives a w0t0p0: prefixed anchor" {
  # FIRING_SID is an iTerm2-shaped address at some call sites and a bare kitty id at others; the
  # comparison must normalise both or the guard silently stops matching.
  own 300
  run env FIRING_SID=w0t0p0:300 bash -c ". '$LIB'; . '$STUBS'; hf_close_pane 300 fire-cleanup spawn"
  [ "$status" -eq 2 ]
  [ -z "$(closes)" ]
}

@test "an empty pane id is REFUSED and recorded, never passed to the transport" {
  run close_pane "" fire-cleanup spawn
  [ "$status" -eq 2 ]
  [ -z "$(closes)" ]
  attrib_rows | grep -q '"verdict":"refused-empty-id"'
}

@test "peer mode REFUSES a pane that is not provably agent-owned" {
  # 301 is registered but carries no fired-peer marker — exactly the operator's pane 247 on the
  # night of the incident.
  printf '{"paneUUID":"301","pid":%s}' "$LIVE_PID" > "$HOME/.claude/cc-registry/301.json"
  run close_pane 301 reaper peer
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'not provably agent-owned'
  [ -z "$(closes)" ]
  attrib_rows | grep -q '"verdict":"refused-not-agent-owned"'
}

@test "peer mode ALLOWS a provably agent-owned pane" {
  # The guard must not retire the common case: reaping a fired peer is the normal path.
  own 302
  run close_pane 302 reaper peer
  [ "$status" -eq 0 ]
  closes | grep -q 'session close -f -s 302'
  attrib_rows | grep -q '"id_requested":"302"'
  attrib_rows | grep -q '"owner":"agent"'
}

# ── the modes are three states, not two ───────────────────────────────────────────────

@test "self mode closes an unmarked pane — a session may always retire itself" {
  # An operator's own pane has no fired-peer marker. If `self` were guarded like `peer`, the ordinary
  # self-close would start refusing and the guard would have retired the mechanism's main path
  # (memory: abstain-rule-can-retire-the-common-case).
  run close_pane 303 self-close self
  [ "$status" -eq 0 ]
  closes | grep -q 'session close -f -s 303'
  attrib_rows | grep -q '"mode":"self"'
}

@test "spawn mode closes a pane too young to carry a marker" {
  # restore_focus_or_fail and fire-cleanup un-create a pane they made seconds earlier; it cannot have
  # a fired-peer marker yet, so an ownership check there would refuse a legitimate self-clean.
  run close_pane 304 fire-cleanup spawn
  [ "$status" -eq 0 ]
  closes | grep -q 'session close -f -s 304'
  attrib_rows | grep -q '"mode":"spawn"'
}

# ── attribution is durable and complete ───────────────────────────────────────────────

@test "every attempt records site, mode, id, owner and verdict" {
  own 305
  run close_pane 305 restore-focus-or-fail spawn
  [ "$status" -eq 0 ]
  local row; row="$(attrib_rows | tail -1)"
  echo "$row" | grep -q '"site":"restore-focus-or-fail"'
  echo "$row" | grep -q '"mode":"spawn"'
  echo "$row" | grep -q '"id_requested":"305"'
  echo "$row" | grep -q '"owner":"agent"'
  echo "$row" | grep -q '"verdict":'
  echo "$row" | grep -q '"caller_pid":'
  # one line per attempt, and it must be valid JSON — a log nothing can parse is not attribution
  run bash -c "/usr/bin/python3 -c \"import json,sys; [json.loads(l) for l in open('$CC_CLOSE_ATTRIB_LOG')]\""
  [ "$status" -eq 0 ]
}

@test "attribution is APPEND-only across attempts" {
  own 306; own 307
  close_pane 306 reaper peer
  close_pane 307 reaper peer
  [ "$(attrib_rows | wc -l | tr -d ' ')" = "2" ]
}

@test "a close attempt that leaves the pane PRESENT is recorded as such, not as success" {
  # `close` returning 0 is a claim; the pane being gone is the outcome, and the two have come apart
  # before (memory: claimed-outcome-vs-checked-outcome).
  own 308
  cat > "$BATS_TEST_TMPDIR/stubs2.sh" <<'SH'
in_kitty() { return 0; }
kt_window_field() { printf '%s\n' "308"; return 0; }
hf_bounded() { return 0; }
SH
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/stubs2.sh'; hf_close_pane 308 reaper peer"
  [ "$status" -eq 1 ]
  attrib_rows | grep -q '"verdict":"STILL-PRESENT"'
}

@test "an unreadable terminal is recorded as UNVERIFIED but is NOT convicted" {
  # A failed query is not an absence, and it is not a failure either. Recording it as `unverified`
  # keeps the log honest (memory: lookup-miss-is-not-absence); returning 0 keeps the self-close
  # retry loop from burning 4 attempts and paging a HUSK for a close that actually worked. Both
  # halves matter, and only asserting one of them would let the other regress silently.
  own 309
  cat > "$BATS_TEST_TMPDIR/stubs3.sh" <<'SH'
in_kitty() { return 0; }
kt_window_field() { return 1; }
hf_bounded() { return 0; }
SH
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/stubs3.sh'; hf_close_pane 309 reaper peer"
  [ "$status" -eq 0 ]
  attrib_rows | grep -q '"verdict":"unverified"'
}

@test "a non-zero transport is convicted even when the pane cannot be re-read" {
  # The mirror of the test above: unverified must not become a blanket amnesty.
  own 310
  cat > "$BATS_TEST_TMPDIR/stubs4.sh" <<'SH'
in_kitty() { return 0; }
kt_window_field() { return 1; }
hf_bounded() { return 7; }
SH
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/stubs4.sh'; hf_close_pane 310 reaper peer"
  [ "$status" -eq 1 ]
  attrib_rows | grep -q '"verdict":"unverified-rc7"'
}

# ── the call sites actually use it ────────────────────────────────────────────────────

@test "exactly ONE executed 'session close' remains, and it is inside hf_close_pane" {
  # A guard that a single site bypasses is not a guard. Comments and operator-facing
  # "close it by hand" hints are prose and are excluded by shape, not by hand-listing them.
  run bash -c "grep -n 'session close -f -s' '$FIRE' \
     | grep -v ':[[:space:]]*#' \
     | grep -v 'echo ' \
     | wc -l | tr -d ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  # and that one line is the transport call inside hf_close_pane
  run bash -c "sed -n '/^hf_close_pane()/,/^}/p' '$FIRE' | grep -c 'session close -f -s'"
  [ "$output" = "1" ]
}

@test "each of the three sites passes an explicit mode" {
  grep -q 'hf_close_pane "\$SID" self-close self' "$FIRE"
  grep -q 'hf_close_pane "\$SPAWNED_PANE" fire-cleanup spawn' "$FIRE"
  grep -q 'hf_close_pane "\$newid" restore-focus-or-fail spawn' "$FIRE"
}
