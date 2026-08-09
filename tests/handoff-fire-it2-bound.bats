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
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # hermeticity ratchet: never the live ~/
  # Extract the helper AND its two configuration lines the same way the sibling suites extract
  # functions. Sourcing the whole script is not an option: it has top-level side effects.
  #
  # BOTH functions, because hf_bounded now DELEGATES (2026-08-08): the caller-named-duration variant
  # hf_bounded_s holds the actual timeout invocation and hf_bounded is a one-line wrapper passing the
  # default. Extracting only hf_bounded gave every test below exit 127 — loudly RED, not vacuous, which
  # is the property that makes this extraction style safe to maintain. If a third helper joins the
  # chain, it is added here or these tests go red on the next run and say exactly why.
  eval "$(sed -n '/^hf_bounded() {/,/^}/p;/^hf_bounded_s() {/,/^}/p' "$HF")"
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

# ── hf_bounded_s: the caller-named duration (2026-08-08) ─────────────────────────────────────────────
# Added for the completion-push bound, whose contents (up to two cc-notify attempts, each holding an
# internally-bounded it2 call) legitimately exceed HF_TIMEOUT_S — a bound smaller than what it bounds
# can only ever CONVICT a healthy callee (memory: exoneration-bound-must-fit-what-it-bounds).

@test "hf_bounded_s honours the CALLER's duration, not HF_TIMEOUT_S" {
  # The whole reason the variant exists: a long default must not stop a caller cutting early, and a
  # short default must not cut a caller that needs longer. Both directions, since pinning only one
  # would pass on a build that ignored the argument and used HF_TIMEOUT_S throughout.
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=30
  run hf_bounded_s 1 /bin/sleep 20
  [ "$status" -eq 124 ]                     # caller's 1s won over the 30s default

  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=1
  run hf_bounded_s 10 /bin/echo fits
  [ "$status" -eq 0 ]                       # caller's 10s won over the 1s default
  [ "$output" = "fits" ]
}

@test "hf_bounded_s: an empty OR zero duration runs UNBOUNDED (both disable paths, explicitly)" {
  # 0 is pinned separately from empty because GNU `timeout 0` ALSO means "no timeout" — so a build
  # that forwarded 0 straight to timeout(1) would pass a test that only checked the empty case, while
  # every consumer reading back the configured value would disagree about whether a bound exists.
  # HF_TIMEOUT_S=1 is a deliberate FOIL, not decoration: a build that ignored the ""/0 argument and
  # fell back to the default would cut `sleep 2` at 1s and these assertions would fail. HF_TIMEOUT_BIN
  # is likewise essential — with no timeout binary the calls would run unbounded for the WRONG reason,
  # and the test would pass while proving nothing about the duration.
  # shellcheck disable=SC2034  # both are read by the eval'd hf_bounded_s, whose body shellcheck cannot see
  HF_TIMEOUT_BIN="$TIMEOUT_BIN" HF_TIMEOUT_S=1
  run hf_bounded_s "" /bin/sleep 2
  [ "$status" -eq 0 ]
  run hf_bounded_s 0 /bin/sleep 2
  [ "$status" -eq 0 ]
}

@test "hf_bounded_s escalates to SIGKILL: a TERM-ignoring wedge is still cut (rc 137, not a hang)" {
  # `-k 3` is the half that matters for a real wedge — the completion-push chain installs its own TERM
  # trap, so a TERM-only bound would expire and leave the callee running, still holding the pipe that
  # made it a wedge. MEASURED codes: 124 when TERM suffices, 137 when the KILL is needed.
  # No HF_TIMEOUT_S here, deliberately: hf_bounded_s takes its duration as an ARGUMENT, so setting the
  # default would be a dead assignment implying this test depends on it (shellcheck SC2034 caught it).
  # shellcheck disable=SC2034  # read by the eval'd hf_bounded_s — shellcheck cannot see that body
  HF_TIMEOUT_BIN="$TIMEOUT_BIN"
  local ign="$BATS_TEST_TMPDIR/ign.sh"
  printf '#!/bin/bash\ntrap "" TERM\nwhile :; do sleep 1; done\n' > "$ign"; chmod +x "$ign"
  run hf_bounded_s 1 "$ign"
  [ "$status" -eq 137 ]
}

@test "hf_bounded delegates to hf_bounded_s — one timeout(1) invocation, not two that can drift" {
  # The delegation is the POINT: a second call site that re-derived the timeout binary is precisely
  # the one that would silently run unbounded on a launchd PATH. Pinned textually because the
  # behavioural tests above cannot tell delegation from a faithful duplicate.
  run bash -c "sed -n '/^hf_bounded() {/,/^}/p' '$HF'"
  [[ "$output" == *"hf_bounded_s"* ]] || false
  [[ "$output" != *"-k 3"* ]] || false        # the invocation lives in ONE place, below
  # SPAN = the two helpers, NOT the whole file. A file-wide `-eq 1` would red on any unrelated future
  # `-k 3 ` — growth, not regression — which is the tripwire shape this repo has shipped before
  # (memory: assertion-span-must-equal-its-subject; exact-count-assertion-tripwires-its-own-subject).
  # Scoped here the count IS the invariant: these two functions must hold exactly one invocation.
  run bash -c "sed -n '/^hf_bounded() {/,/^}/p;/^hf_bounded_s() {/,/^}/p' '$HF' | grep -c -- '-k 3 '"
  [ "$output" = "1" ]
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
  #
  # FOURTH sweep, 2026-07-29 (backlog f44a901152d9): the name-shape family is still a name-shape
  # family, so it was blind to the LITERAL-PATH fork — `"$HOME/.claude/bin/it2" session close …`,
  # where the only variable is HOME. Four such sites existed, all unbounded, all invisible: the
  # watcher's CR nudge, the pane-close retry (a WEDGED call there means the documented 4-attempt
  # retry never runs at all, turning a blip into a permanent husk pane), the successor focus, and a
  # new one this backlog item added. The guard read GREEN over every one of them — a detector that
  # cannot see part of its target population is worse than none, because it certifies the gap
  # (memory: actuator-must-see-the-target-population). So the sweep now matches the binary by PATH
  # SHAPE as well as by variable-name shape.
  #
  # …and the SAME sweep also had to learn a second command position. The prefix group accepted only
  # line-start, a `|;&` separator, or `$(` — so `if "$HOME/.claude/bin/it2" session close …` was
  # invisible for the additional reason that `if ` precedes the token. Two of the four sites above
  # were of exactly that shape, so widening only the binary pattern still certified them green.
  # Shell KEYWORDS are now skipped after a real command-position prefix; passing the binary as an
  # ARGUMENT (`it2_type_verified "$REAL_IT2" …`) still does not match, because what follows the
  # line-start there is a command name, not a keyword.
  local pre='(^[[:space:]]*|[|;&]{1,2}[[:space:]]*|\$\()((if|elif|while|until|then|else|do|!)[[:space:]]+)*'
  local tok='(osascript|"\$[A-Za-z_]*([Ii][Tt]2|PYTHON)[A-Za-z_]*"|"[^"]*/bin/it2")'
  local unbounded
  unbounded="$(grep -nE "${pre}${tok}[[:space:]]" "$HF" \
    | grep -v 'hf_bounded' \
    | grep -vE "osascript -e 'delay" \
    | grep -vE '^[[:space:]]*[0-9]+:[[:space:]]*#' || true)"
  [ -z "$unbounded" ] || { printf 'unbounded external call sites:\n%s\n' "$unbounded" >&2; false; }
}
