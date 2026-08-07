#!/usr/bin/env bats
# handoff-fire: a HEADLESS fire may never anchor on a pane the operator owns.
#
# Regression under test (2026-08-07, docs/plans/PANE_THEFT_2026-08-07.md). Two launchd fires at
# 06:41:13Z and 06:42:22Z anchored on the operator's own kitty panes; one of those panes was
# destroyed with a long unsent composer message in it, which exists nowhere on disk and could not be
# recovered. The kitty anchor picker's preference order was desk -> focused -> tabs[0][0], and all
# three degraded onto the operator:
#   * `desk` reads ~/.claude/cc-roles/desk, which holds an iTerm2 session UUID while the picker's
#     by_id is keyed by kitty INTEGER window ids, so the lookup was unconditionally None.
#   * `focused` is not the safety net it looks like: `kitty @ ls` reports is_focused FALSE for every
#     window whenever kitty is not the frontmost APP, which is precisely when a launchd fire runs.
#   * so the walk fell to "the first window of the first tab with room" — an arbitrary operator pane.
# The fix adds the thing the picker never had: a notion of OWNERSHIP, taken from disk truth that was
# already being written (~/.claude/cc-fired/<id>.json) and never consulted.
#
# THESE ARE BEHAVIOURAL, NOT STRUCTURAL. The picker is extracted verbatim from the shipped
# scripts/handoff-fire.sh and executed against fixture `kitty @ ls` payloads, so the test replays the
# real artifact rather than an approximation of it (memory: control-must-replay-the-real-artifact).
# The final test is a MUTATION CONTROL that runs the OLD picker against the same fixture and proves
# it takes the operator's pane — without it, every assertion below could be passing vacuously.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/cc-roles" "$HOME/.claude/cc-fired" "$HOME/.claude/cc-registry"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIRE="$REPO/scripts/handoff-fire.sh"
  [ -f "$FIRE" ] || skip "handoff-fire.sh not found at $FIRE"

  PICKER="$BATS_TEST_TMPDIR/picker.py"
  extract_picker > "$PICKER"
  [ -s "$PICKER" ] || skip "could not extract the kitty anchor picker from $FIRE"

  # A pid that is genuinely alive for the duration of the test. The ownership predicate pairs the
  # fired-peer marker with a LIVE registry pid, so a fixture that used a made-up number would test
  # the failure branch while claiming to test the success one. This process is the honest choice:
  # a backgrounded `sleep` would keep bats waiting on the job after every test (measured: the whole
  # file wedged past a 2-minute bound), and a hand-picked number would be a fabrication.
  LIVE_PID=$$
  # A pid that is genuinely dead: really started, then reaped, so the number is real and unusable.
  ( exit 0 ) & DEAD_PID=$!
  wait "$DEAD_PID" 2>/dev/null || true
}

# Pull the picker out of the shipped file: everything between the `python3 -c '` line of the kitty
# `anchor` verb and the lone closing quote. Anchored on ACC_HOME= so it can match exactly one block
# (memory: per-site-mutation — an anchor that matches more than once silently tests the wrong thing).
extract_picker() {
  sed -n "/ACC_HOME=\"\$HOME\/.claude\" \/usr\/bin\/python3 -c '/,/^'$/p" "$FIRE" | sed '1d;$d'
}

run_picker() { # $1=desk $2=cap ; fixture JSON on stdin
  ADESK="$1" ACAP="$2" ACC_HOME="$HOME/.claude" /usr/bin/python3 "$PICKER"
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────

# One os-window, one tab, windows given as "id:focused" pairs.
ls_json() { # $@ = id:true|false …
  local first=1; printf '[{"id":1,"tabs":[{"id":1,"windows":['
  for spec in "$@"; do
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"id":%s,"is_focused":%s}' "${spec%%:*}" "${spec##*:}"
  done
  printf ']}]}]'
}

own() { # $1=window id — mark it agent-owned (fired-peer marker + live registry pid)
  printf '{"paneUUID":"%s","closedAt":null,"originClass":"fired-peer"}' "$1" \
    > "$HOME/.claude/cc-fired/$1.json"
  printf '{"paneUUID":"%s","pid":%s}' "$1" "$LIVE_PID" > "$HOME/.claude/cc-registry/$1.json"
}

# ── (a) an iTerm2-UUID desk role is a BROKEN INVARIANT, not a miss ────────────────────

@test "a desk role in another terminal's id space REFUSES instead of falling through" {
  own 300
  run bash -c "$(declare -f ls_json); ls_json 200:true 300:false | \
    ADESK=D40A5752-F313-4F2C-B5BF-2FADE3BADB2C ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  # rc 3 = terminal-identity mismatch. NOT 0 with a guessed anchor, which is the incident.
  [ "$status" -eq 3 ]
  # and it must say why, and name the repair — a refusal nobody can act on is a new outage
  echo "$output" | grep -q 'not a kitty window id'
  echo "$output" | grep -q 'cc-roles'
  # crucially: it must not have emitted ANY window id on stdout
  run bash -c "$(declare -f ls_json); ls_json 200:true 300:false | \
    ADESK=D40A5752-F313-4F2C-B5BF-2FADE3BADB2C ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER' 2>/dev/null"
  [ -z "$output" ]
}

# ── (b) desk absent: the agent-owned pane wins, the focused operator pane never does ──

@test "with no desk role it takes the agent-owned pane, never the focused one" {
  own 300
  run bash -c "$(declare -f ls_json); ls_json 200:true 300:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 0 ]
  # 200 is is_focused AND enumerated first — both of the old code's preferences — and must lose.
  [ "${output%% *}" = "300" ]
}

@test "the operator's pane loses even when it is the ONLY focused window and comes first" {
  own 300
  # three operator panes ahead of the agent-owned one, one of them focused
  run bash -c "$(declare -f ls_json); ls_json 201:false 202:true 203:false 300:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 0 ]
  [ "${output%% *}" = "300" ]
}

# ── (c) nothing is ours: REFUSE. This is the incident's exact input ───────────────────

@test "live windows but none agent-owned REFUSES rather than taking one" {
  # No own() call at all: every pane on the box belongs to the operator.
  run bash -c "$(declare -f ls_json); ls_json 200:true 201:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'NONE agent-owned'
  # and nothing on stdout — a caller parsing stdout must not receive an anchor
  run bash -c "$(declare -f ls_json); ls_json 200:true 201:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER' 2>/dev/null"
  [ -z "$output" ]
}

@test "kitty NOT frontmost — every window is_focused false — still refuses, never guesses" {
  # This is the real headless shape: `focused` is empty, so the OLD code fell to tabs[0][0].
  run bash -c "$(declare -f ls_json); ls_json 200:false 201:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 4 ]
}

# ── the three-state contract is preserved ─────────────────────────────────────────────

@test "an EMPTY box is still DETERMINED-empty (NO-LIVE-SESSION, rc 0), not a refusal" {
  # Collapsing determined-empty into refuse would be as wrong as the leak it replaced: the caller
  # distinguishes 1 (a fresh window is honest) from 2 (refuse) and both arms must stay reachable.
  # stdout ONLY: the verdict token is a parsed contract, and the picker also explains itself on
  # stderr. `run` merges the two streams, so an unredirected assertion here would compare the
  # contract against the commentary and fail for the wrong reason.
  run bash -c "echo '[]' | ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "NO-LIVE-SESSION" ]
}

@test "unparseable kitty output is a QUERY FAILURE (rc 1), never determined-empty" {
  run bash -c "echo 'not json' | ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qv 'NO-LIVE-SESSION' || false
}

# ── (d) a full tab still spills rather than drifting to the operator ──────────────────

@test "an agent-owned pane whose tab is at CC_FIRE_MAX_PANES is still chosen, with its true count" {
  own 300
  run bash -c "$(declare -f ls_json); ls_json 200:true 300:false | \
    ADESK= ACAP=2 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 0 ]
  # the tab holds 2 windows and the cap is 2 ⇒ no room; the second pass must still return it,
  # reporting the TRUE count so the caller can spill to a tab instead of slivering the split.
  [ "$output" = "300 2" ]
}

# ── the ownership predicate is not a rubber stamp ─────────────────────────────────────

@test "a fired-peer marker whose registry pid is DEAD does not confer ownership" {
  # Why this matters: a kitty window id is a per-kitty-process counter that restarts at 1, so a
  # marker left by a previous kitty can name a live UNRELATED window — an operator's, typically.
  printf '{"paneUUID":"300","closedAt":null}' > "$HOME/.claude/cc-fired/300.json"
  printf '{"paneUUID":"300","pid":%s}' "$DEAD_PID" > "$HOME/.claude/cc-registry/300.json"
  run bash -c "$(declare -f ls_json); ls_json 300:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 4 ]
}

@test "a marker with a non-null closedAt does not confer ownership" {
  printf '{"paneUUID":"300","closedAt":"2026-08-07T00:00:00Z"}' > "$HOME/.claude/cc-fired/300.json"
  printf '{"paneUUID":"300","pid":%s}' "$LIVE_PID" > "$HOME/.claude/cc-registry/300.json"
  run bash -c "$(declare -f ls_json); ls_json 300:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 4 ]
}

@test "a registry row with no fired-peer marker does not confer ownership" {
  # The operator's own panes ARE registered — 247 was, on the night of the incident. A registry row
  # alone must therefore never read as "the machine made this".
  printf '{"paneUUID":"300","pid":%s}' "$LIVE_PID" > "$HOME/.claude/cc-registry/300.json"
  run bash -c "$(declare -f ls_json); ls_json 300:false | \
    ADESK= ACAP=5 ACC_HOME='$HOME/.claude' /usr/bin/python3 '$PICKER'"
  [ "$status" -eq 4 ]
}

# ── MUTATION CONTROL — prove the fixtures can convict ─────────────────────────────────

@test "CONTROL: the OLD picker takes the operator's pane on the very same fixture" {
  # Without this the whole file could be green because the fixtures never exercised the hazard.
  # This is the pre-fix preference order, verbatim, and it must FAIL the safety property.
  cat > "$BATS_TEST_TMPDIR/old.py" <<'PY'
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
cap = int(os.environ.get("ACAP") or 5)
desk = os.environ.get("ADESK") or ""
tabs = [t.get("windows") or [] for ow in d for t in ow.get("tabs", [])]
by_id = {str(w.get("id")): ws for ws in tabs for w in ws}
focused = [str(w.get("id")) for ws in tabs for w in ws if w.get("is_focused")]
def pick(room):
    for wid in ([desk] if desk else []) + focused:
        ws = by_id.get(wid)
        if ws and (not room or len(ws) < cap):
            return wid, len(ws)
    for ws in tabs:
        if ws and (not room or len(ws) < cap):
            return str(ws[0].get("id")), len(ws)
    return None
hit = pick(True) or pick(False)
if hit is None:
    print("NO-LIVE-SESSION")
else:
    print("%s %d" % hit)
PY
  # (c)'s fixture — nothing agent-owned. The new picker refuses; the old one hands back pane 200.
  run bash -c "$(declare -f ls_json); ls_json 200:true 201:false | \
    ADESK= ACAP=5 /usr/bin/python3 '$BATS_TEST_TMPDIR/old.py'"
  [ "$status" -eq 0 ]
  [ "${output%% *}" = "200" ]

  # and with focus absent it still guesses — the launchd shape that actually fired
  run bash -c "$(declare -f ls_json); ls_json 200:false 201:false | \
    ADESK= ACAP=5 /usr/bin/python3 '$BATS_TEST_TMPDIR/old.py'"
  [ "$status" -eq 0 ]
  [ "${output%% *}" = "200" ]

  # and the stale iTerm2 desk hint is silently ignored rather than refused
  run bash -c "$(declare -f ls_json); ls_json 200:true | \
    ADESK=D40A5752-F313-4F2C-B5BF-2FADE3BADB2C ACAP=5 /usr/bin/python3 '$BATS_TEST_TMPDIR/old.py'"
  [ "$status" -eq 0 ]
  [ "${output%% *}" = "200" ]
}

# ── the caller maps the new refusals onto the existing three-state contract ───────────

@test "resolve_headless_anchor maps rc 3 and rc 4 to INCONCLUSIVE (2), never to determined-empty" {
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$FIRE'"
  [ "$status" -eq 0 ]
  # both new refusal codes must be handled explicitly and both must return 2 — returning 1 would
  # re-enable the fresh-window mint that leaked ~12 windows/hour on 2026-07-30.
  echo "$output" | grep -qE '^\s+3\)'
  echo "$output" | grep -qE '^\s+4\)'
  echo "$output" | grep -q 'NO-LIVE-SESSION) return 1'
  # and the probe's own stderr must no longer be discarded, or the refusal reason never reaches a reader
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$FIRE' | grep -q 'it2py anchor .*2>/dev/null'"
  [ "$status" -ne 0 ]
}
