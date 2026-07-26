#!/usr/bin/env bats
# handoff-fire.sh external-call BOUND (hf_bounded) — machine-wide iTerm2 API wedge, 2026-07-26.
#
# Incident: `timeout 20 ~/.claude/bin/it2 session list --json` returned rc 124 with ZERO bytes while
# 13+ blocked `session list` forks piled up across ~110 registered sessions. Every surface that
# reaches iTerm2 — osascript AppleEvents, the it2 CLI, the iterm2 Python API — funnels into the same
# serialized API, so all three block together. handoff-fire.sh was the worst exposure of the fleet:
#
#   1. it deliberately forks $REAL_IT2 (the raw binary, NOT the ~/.claude/bin/it2 shim) so a split
#      inherits the firing pane's own profile — which also opts OUT of the shim's 30s bound; and
#   2. it2_type_verified RETRIES (up to 4 attempts x ~4 forks), so a per-fork bound MULTIPLIES:
#      even on the shim path the aggregate worst case is ~16 x 30s ~= 8 minutes.
#
# Observable symptom: `handoff-fire.sh self-close --terminal` stalling ~100s on a clean tree, so
# finished panes could not retire and piled up as false STALL/DEAD pages.
#
# These tests pin hf_bounded's REAL definition, extracted from the script. The other handoff-fire
# suites stub it as a passthrough (they extract single functions and only care about those); this
# file is the one place the bound itself is exercised, so a regression cannot hide behind a stub.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # Extract the helper AND its two configuration lines the same way the sibling suites extract
  # functions. Sourcing the whole script is not an option: it has top-level side effects.
  eval "$(sed -n '/^hf_bounded() {/,/^}/p' "$HF")"
  TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)"
}

@test "hf_bounded runs the command and returns its rc (transparent on the happy path)" {
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=10
  run hf_bounded /bin/echo hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "hf_bounded propagates a non-zero rc unchanged (fail-loud paths still classify)" {
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=10
  # it2 returns rc 3 for a missing anchor and it2_split keys on non-zero; a wrapper that swallowed
  # or rewrote rc would turn a dead anchor into a silent success.
  run hf_bounded /bin/sh -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "a WEDGED call is cut at the bound and reports 124, not an indefinite block" {
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=1
  # THE regression. `sleep 30` stands in for a fork against the wedged API: pre-fix this returned
  # only when the API drained (measured: minutes), which is what stalled self-close for ~100s.
  local start end
  start=$(date +%s)
  run hf_bounded /bin/sleep 30
  end=$(date +%s)
  [ "$status" -eq 124 ]
  [ $((end - start)) -lt 10 ] || false
}

@test "stdin (heredoc) reaches the bounded command — the as_write/as_tab osascript shape" {
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=10
  # as_write / _as_tty_query / as_tab all feed the AppleScript via heredoc AND pass argv. If the
  # wrapper broke either, every osascript pane lookup would silently stop resolving.
  run hf_bounded /bin/sh -s "argA" "argB" <<'IN'
printf 'args=[%s %s] stdin=ok\n' "$1" "$2"
IN
  [ "$status" -eq 0 ]
  [ "$output" = "args=[argA argB] stdin=ok" ]
}

@test "TIMEOUT_BIN set-but-EMPTY genuinely disables bounding (a seam that cannot turn OFF is not a seam)" {
  # `${VAR:-}` cannot tell unset from set-empty. That exact defect made cc-inbox-guard's documented
  # "" disable a no-op and hung every landing gate (c3edb2d), so the disable path is pinned here.
  HF_TIMEOUT_BIN="" HF_TIMEOUT_S=1
  run hf_bounded /bin/echo passthrough
  [ "$status" -eq 0 ]
  [ "$output" = "passthrough" ]
}

@test "no timeout(1) available ⇒ runs UNBOUNDED rather than breaking the call" {
  # Degradation choice: a box without coreutils must still be able to fire a handoff.
  HF_TIMEOUT_BIN="/nonexistent/timeout" HF_TIMEOUT_S=1
  run hf_bounded /bin/echo still-runs
  [ "$status" -eq 0 ]
  [ "$output" = "still-runs" ]
}

@test "the script resolves timeout(1) by ABSOLUTE path, not PATH alone (launchd has no Homebrew)" {
  # The hooks and launchd jobs that fire handoff-fire.sh run with a minimal PATH that excludes
  # /opt/homebrew/bin — exactly where coreutils installs timeout. A PATH-only lookup would leave the
  # AUTOMATED callers (the ones that built the pile-up) unbounded while interactive shells stayed
  # safe: the bound would look present and be absent in the only case it was written for.
  grep -q '/opt/homebrew/bin/timeout' "$HF" || false
  grep -q '/usr/local/bin/timeout' "$HF" || false
}

@test "every external iTerm2 call in handoff-fire.sh goes through the bound" {
  # Enumerates CALL SITES, not mechanisms (memory: enumerate-call-sites-not-mechanisms). A new
  # unbounded osascript / $REAL_IT2 / $PYTHON_BIN fork reintroduces the wedge silently, so the
  # sweep is the guard. Exemptions, each deliberate:
  #   - `osascript -e 'delay N'` is a pure sleep: no application tell, no AppleEvent, self-bounding.
  #   - REAL_IT2= / PYTHON_BIN= lines are path ASSIGNMENTS (and a parsed contract), not calls.
  # Matches the token only in COMMAND POSITION — at the start of a command, or opening a command
  # substitution. Passing the binary as an ARGUMENT to an already-bounded helper
  # (`it2_type_verified "$REAL_IT2" …`) or testing it (`[ -n "$REAL_IT2" ]`) is not a fork and must
  # not trip the sweep, or the guard would be noise and get deleted.
  # Matches ANY variable whose name contains IT2 or PYTHON — deliberately wider than a fixed list.
  # Three sweeps of this incident each used a different pattern family and each found sites the
  # previous missed: family 1 ("$it2"/"$REAL_IT2") missed :989 "$IT2"; family 2 missed :2098
  # "$IT2_SHIM". A fixed token list encodes the last reader's blind spot, so the guard matches the
  # NAME SHAPE instead (memory: enumerate-call-sites-not-mechanisms).
  local tok='(osascript|"\$[A-Za-z_]*([Ii][Tt]2|PYTHON)[A-Za-z_]*")'
  local unbounded
  unbounded="$(grep -nE "(^[[:space:]]*|[|;&]{1,2}[[:space:]]*|\\\$\\()${tok}[[:space:]]" "$HF" \
    | grep -v 'hf_bounded' \
    | grep -vE "osascript -e 'delay" \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' || true)"
  [ -z "$unbounded" ] || { printf 'unbounded external call sites:\n%s\n' "$unbounded" >&2; false; }
}
