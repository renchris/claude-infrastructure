#!/usr/bin/env bats
# effort-parity-assert.sh — asserts resolved effort matches the SSOT effort_defaults floor.
#
# Guards the drift the script was built for: model-config.yaml claimed a xhigh settings floor
# "symlinked into every CLAUDE_CONFIG_DIR", but the five settings.json are FIVE INDEPENDENT REAL files
# that had drifted to ~/.claude=high, four accounts=low — every non-wrapped surface silently resolved
# below the floor and no existing gate (claude-lint-models / settings-drift-assert) caught it.
#
# HERMETIC: each case builds a fake SSOT + config dirs + zshrc + ps fixture in BATS_TEST_TMPDIR and
# drives the script via CC_EFFORT_SSOT / CC_EFFORT_DIRS / CC_EFFORT_ZSHRC / CC_EFFORT_PS. The final case
# runs the script against the REAL live host (no fixtures) to prove the live path is assertable.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/effort-parity-assert.sh"

  # a minimal SSOT carrying the effort_defaults keys the script reads
  export CC_EFFORT_SSOT="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$CC_EFFORT_SSOT" <<'YAML'
effort_defaults:
  default: max
  settings_floor: xhigh
frontier_access:
  active: true
YAML

  # 🚨 THE ZSHRC FIXTURE REPRODUCES THE PRODUCTION SHAPE, AND THAT IS LOAD-BEARING.
  # Two launcher tracks live in ~/.zshrc and they read DIFFERENT knobs on purpose:
  #   claude()      — the MODERN track, ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-<v>}}   → GATING
  #   claude-prev() — the LEGACY stable track, ${CLAUDE_DEFAULT_EFFORT:-<v>}            → NON-gating NOTE
  # Corroborated independently of the fix by two in-repo records that predate it:
  # docs/plans/backlog-consolidation-2026-08-09/OUT-accounts.md:34 (".zshrc:451 claude() → :497
  # ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}} … the disagreement is claude()-only") and
  # docs/research/fable51-vs-opus5-routing-2026-09-16/A6-mechanics.md:194.
  # The FIRST line is a COMMENT carrying the modern knob at a WRONG value (low). That is not
  # decoration: it reproduces ~/.zshrc's header prose, and it is the live red-proof of the comment
  # filter — drop the `grep -vE '^[[:space:]]*#'` and every case below reads `low` and goes red.
  export CC_EFFORT_ZSHRC="$BATS_TEST_TMPDIR/zshrc"
  write_zshrc max max   # $1 = modern claude() default, $2 = legacy claude-prev default

  export CC_EFFORT_PS="$BATS_TEST_TMPDIR/ps.txt"
  printf 'claude --effort max\nnode server.js\n' > "$CC_EFFORT_PS"   # no below-floor live session

  export D="$BATS_TEST_TMPDIR/dirs"
  mkdir -p "$D"/one "$D"/two "$D"/three "$D"/four "$D"/five
  export CC_EFFORT_DIRS="$D/one $D/two $D/three $D/four $D/five"
}

# Build a two-track zshrc: $1 = claude()'s default (GATING), $2 = claude-prev()'s (NON-gating).
# Defined above its first caller deliberately — a helper placed below silently leaves every site
# above it broken while the suite stays green.
write_zshrc() {
  cat > "$CC_EFFORT_ZSHRC" <<ZRC
# header prose — the modern launcher resolves \${CLAUDE_EFFORT:-\${CLAUDE_OPUS5_EFFORT:-low}}.
# This is a COMMENT and must never be gated on; before 2026-09-16 the check read it first.
CLAUDE_DEFAULT_EFFORT="\${CLAUDE_DEFAULT_EFFORT:-$2}"   # legacy claude-prev track — separate knob BY DESIGN
claude-prev() { command claude-stable --effort "\${CLAUDE_DEFAULT_EFFORT:-$2}" "\$@"; }
claude() { local _eff="\${CLAUDE_EFFORT:-\${CLAUDE_OPUS5_EFFORT:-$1}}"; command claude-latest --effort "\$_eff" "\$@"; }
ZRC
}

set_all() {  # $1 = effortLevel written to every fake dir's settings.json
  local d
  for d in "$D"/one "$D"/two "$D"/three "$D"/four "$D"/five; do
    printf '{"effortLevel":"%s"}\n' "$1" > "$d/settings.json"
  done
}

@test "parity: every dir at the SSOT floor (xhigh) + claude() at SSOT max ⇒ exit 0" {
  set_all xhigh
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"parity"* ]] || false
  # The launcher row must be a REAL OK, not a SKIP. Asserting only the exit code let this case pass
  # while the gating grep matched NOTHING in the fixture — green, and decorative on the launcher.
  [[ "$output" == *"OK"*"zshrc launcher"*"claude() --effort default = max"* ]] || false
}

@test "the live-state shape (one dir high, four low) ⇒ DRIFT, exit 1 (the 2026-07-24 regression)" {
  printf '{"effortLevel":"high"}\n' > "$D/one/settings.json"
  local d
  for d in two three four five; do printf '{"effortLevel":"low"}\n' > "$D/$d/settings.json"; done
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BELOW"* ]] || false
  [[ "$output" == *"high < floor xhigh"* ]] || false
  [[ "$output" == *"low < floor xhigh"* ]] || false
}

# 🚨 THIS CASE WAS INVERTED ON 2026-09-17, AND THE INVERSION IS THE POINT — DO NOT "RESTORE" IT.
# It used to write ONE line, `alias claude="claude --effort ${CLAUDE_DEFAULT_EFFORT:-high}"`, and
# demand DRIFT + exit 1 on it. That is the LEGACY claude-prev knob, which the modern claude() never
# reads — so the case encoded the very defect 2909762748ee cures (a check gating on the wrong track's
# variable, convicting a launcher already sitting on the floor). When that fix landed, this case went
# red, post-land AUTO-REVERT convicted the fix, and ab16fb3e reverted it: the cure was undone by a
# test demanding the disease. The legacy knob's non-gating behaviour is now pinned one case below,
# where it belongs, and this case drifts the knob the launcher ACTUALLY reads.
@test "claude() --effort default drifted below SSOT (high, not max) ⇒ DRIFT, exit 1" {
  set_all xhigh
  write_zshrc high max          # modern track drifts; legacy track stays on the SSOT default
  run "$ASSERT"
  [ "$status" -eq 1 ]
  # Name claude() explicitly: a bare "zshrc launcher" match is satisfied by a SKIP row too.
  [[ "$output" == *"DRIFT"*"zshrc launcher"*"claude()"* ]] || false
  [[ "$output" == *"CLAUDE_OPUS5_EFFORT:-high"* ]] || false
}

@test "the LEGACY claude-prev knob differing from SSOT is a NON-gating NOTE ⇒ exit 0" {
  set_all xhigh
  write_zshrc max low           # modern track correct; legacy track far below the SSOT default
  run "$ASSERT"
  [ "$status" -eq 0 ]           # the exact assertion the old case had backwards
  [[ "$output" == *"NOTE"*"zshrc claude-prev"*"CLAUDE_DEFAULT_EFFORT:-low"* ]] || false
  [[ "$output" == *"OK"*"zshrc launcher"*"claude() --effort default = max"* ]] || false
}

@test "a comment carrying a WRONG modern value must not outrank the code line ⇒ OK, exit 0" {
  set_all xhigh
  # write_zshrc's header comment already claims the modern knob is `low` while claude() says `max`.
  # Pre-2026-09-16 the check grepped unfiltered and `head -1` reached the header prose first.
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"*"zshrc launcher"*"claude() --effort default = max"* ]] || false
  [[ "$output" != *"DRIFT"* ]] || false
}

@test "modern knob present ONLY in a comment ⇒ SKIP naming the cause, never a silent pass" {
  set_all xhigh
  cat > "$CC_EFFORT_ZSHRC" <<'ZRC'
# claude() used to resolve ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-max}} — prose only, no code.
CLAUDE_DEFAULT_EFFORT="${CLAUDE_DEFAULT_EFFORT:-max}"
ZRC
  run "$ASSERT"
  [ "$status" -eq 0 ]
  # The SKIP must name the knob it looked for AND tell the reader not to trust it blindly —
  # a bare "SKIP" is indistinguishable from "this surface is fine".
  [[ "$output" == *"SKIP"*"zshrc launcher"*"no CLAUDE_EFFORT default found"* ]] || false
  [[ "$output" == *"re-derive before trusting this SKIP"* ]] || false
}

@test "a below-floor LIVE session is REPORT-ONLY by default (⚠, does NOT gate)" {
  set_all xhigh
  printf 'claude --effort low\n' > "$CC_EFFORT_PS"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PS-WARN"* ]]
}

@test "a below-floor LIVE session GATES under CC_EFFORT_PS_STRICT=1" {
  set_all xhigh
  printf 'claude --effort low\n' > "$CC_EFFORT_PS"
  CC_EFFORT_PS_STRICT=1 run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PS-WARN"* ]]
}

@test "missing effortLevel key ⇒ NOFLOOR drift (binary default, not the floor)" {
  set_all xhigh
  printf '{"model":"claude-opus-4-8"}\n' > "$D/one/settings.json"   # no effortLevel key
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOFLOOR"* ]]
}

@test "SSOT unreadable ⇒ exit 3 (missing prerequisite), never a false parity" {
  set_all xhigh
  CC_EFFORT_SSOT="$BATS_TEST_TMPDIR/nope.yaml" run "$ASSERT"
  [ "$status" -eq 3 ]
}

@test "the REAL live host is assertable — script runs to a 0/1 verdict, never a crash (exit 3)" {
  run env -u CC_EFFORT_SSOT -u CC_EFFORT_DIRS -u CC_EFFORT_ZSHRC -u CC_EFFORT_PS "$ASSERT"
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]     # a real verdict, not a missing-prereq crash
  [[ "$output" == *"SSOT floor="* ]]
}
