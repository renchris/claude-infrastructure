#!/usr/bin/env bats
# python-deps.sh — the third-party-Python-module gate for bin/.
#
# Guards the failure that motivated the script: `websocket-client` was absent from the host, so
# bin/cc-relogin's import guard raised BROWSER_FAILED(4) and MASKED the CONSENT_GATE(7) verdict —
# tests/cc-relogin.bats went red and the operator-facing recovery pointed at the wrong problem
# (a dead browser rather than an un-toggled dia://inspect). Nothing in the repo installed it.
#
# The load-bearing assertion is the LYING-PIP case: a pip that exits 0 without making the module
# importable must still read `failed`. pip reports that a distribution was recorded; the property
# every caller depends on is that the module IMPORTS under the python3 that will actually run.
#
# FULLY HERMETIC: every case drives the script via PYTHON_DEPS_REQUIREMENTS / PYTHON_DEPS_PYTHON /
# PYTHON_DEPS_PIP against stubs in BATS_TEST_TMPDIR. No case reads the real requirements.txt, the
# real python3, or the network, and no case can install anything onto the host.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Fixtured per the repo's hermeticity ratchet (scripts/test-hermeticity-lint.sh). Safe for the
  # LIVE probe below: the deps this file guards install into the interpreter's own site-packages
  # (/opt/homebrew/lib/python3.14/site-packages), not per-user site under ~/.local — verified, so
  # a fixtured $HOME cannot turn a genuinely-satisfied host into a false green.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export DEPS="$REPO_ROOT/scripts/python-deps.sh"
  export PYTHON_DEPS_REQUIREMENTS="$BATS_TEST_TMPDIR/req.txt"
  export MARKER="$BATS_TEST_TMPDIR/installed.marker"
  printf 'websocket-client>=1.6.1  # import: websocket\n' > "$PYTHON_DEPS_REQUIREMENTS"

  # python3 stub: `import websocket` succeeds only once the marker exists, so "did pip actually
  # work" is a state the stubs control rather than something the script is trusted to report.
  cat > "$BATS_TEST_TMPDIR/py" <<'EOF'
#!/bin/bash
[[ "$1" == "-c" && "$2" == import\ websocket* ]] && { [[ -f "$MARKER" ]] && exit 0 || exit 1; }
[[ "$1" == "-c" ]] && { echo "/stub/python3"; exit 0; }
exit 0
EOF
  cat > "$BATS_TEST_TMPDIR/pip-works" <<'EOF'
#!/bin/bash
touch "$MARKER"; exit 0
EOF
  # The liar: reports success, changes nothing. This is the shape of a pip that installed into a
  # DIFFERENT interpreter than the one on PATH — the real-world version of this failure.
  cat > "$BATS_TEST_TMPDIR/pip-liar" <<'EOF'
#!/bin/bash
echo "Successfully installed websocket-client-1.9.0"; exit 0
EOF
  cat > "$BATS_TEST_TMPDIR/pip-dead" <<'EOF'
#!/bin/bash
echo "error: externally-managed-environment" >&2; exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR"/py "$BATS_TEST_TMPDIR"/pip-*
  export PYTHON_DEPS_PYTHON="$BATS_TEST_TMPDIR/py"
  export PYTHON_DEPS_PIP="$BATS_TEST_TMPDIR/pip-works"
}

# ---- the verdict ladder ------------------------------------------------------------------------

@test "satisfied: an already-importable dep reports satisfied and installs nothing" {
  touch "$MARKER"
  export PYTHON_DEPS_PIP="$BATS_TEST_TMPDIR/pip-dead"   # a dead pip must never be reached
  run bash "$DEPS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=satisfied"* ]] || false
}

@test "installed: a missing dep is installed and re-probed, reporting the module by name" {
  run bash "$DEPS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=installed"* ]] || false
  [[ "$output" == *"websocket"* ]] || false
  [ -f "$MARKER" ]                                      # pip really ran
}

@test "failed: pip exits 0 but the module STILL does not import ⇒ failed, not installed" {
  export PYTHON_DEPS_PIP="$BATS_TEST_TMPDIR/pip-liar"
  run bash "$DEPS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=failed"* ]] || false
  [[ "$output" != *"verdict=installed"* ]] || false     # pip's own claim must not win
  [[ "$output" == *"recovery:"* ]] || false             # the operator gets a runnable next step
}

@test "failed: a pip that cannot run at all reports failed with the recovery command" {
  export PYTHON_DEPS_PIP="$BATS_TEST_TMPDIR/pip-dead"
  run bash "$DEPS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=failed"* ]] || false
  [[ "$output" == *"--break-system-packages"* ]] || false
}

# ---- the non-mutating modes --------------------------------------------------------------------

@test "--probe: reports missing and never installs, so a checker cannot become an installer" {
  run bash "$DEPS" --probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=missing"* ]] || false
  [ ! -f "$MARKER" ]
}

@test "--dry-run: names what it would install and mutates nothing" {
  run bash "$DEPS" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=dry-run"* ]] || false
  [[ "$output" == *"websocket"* ]] || false
  [ ! -f "$MARKER" ]
}

# ---- the marker contract -----------------------------------------------------------------------

@test "a requirement with no '# import:' marker is a HOLE and fails loudly, not silently skipped" {
  # Without this, a dep added to requirements.txt would be installed but never verified — the
  # exact class of silent gap this file exists to close.
  printf 'somepkg>=1\n' > "$PYTHON_DEPS_REQUIREMENTS"
  run bash "$DEPS" --probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=failed"* ]] || false
  [[ "$output" == *"unmarked-requirement"* ]] || false
  [[ "$output" == *"somepkg"* ]] || false
}

@test "comments and blank lines are not treated as requirements" {
  printf '# a comment\n\n   \nwebsocket-client>=1.6.1  # import: websocket\n' > "$PYTHON_DEPS_REQUIREMENTS"
  touch "$MARKER"
  run bash "$DEPS" --probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=satisfied"* ]] || false
}

@test "a missing requirements file is a failure, never a silent all-clear" {
  export PYTHON_DEPS_REQUIREMENTS="$BATS_TEST_TMPDIR/nope.txt"
  run bash "$DEPS" --probe
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=failed"* ]] || false
  [[ "$output" == *"no-requirements-file"* ]] || false
}

# ---- the live contract (positive control) ------------------------------------------------------

@test "LIVE: the repo's own requirements.txt is satisfied on this host" {
  # The one non-hermetic case, and deliberately so: it is the assertion that actually keeps
  # tests/cc-relogin.bats green. If this goes red, cc-relogin's CONSENT_GATE(7) path is unreachable
  # on this host — run scripts/python-deps.sh to fix it.
  unset PYTHON_DEPS_REQUIREMENTS PYTHON_DEPS_PYTHON PYTHON_DEPS_PIP
  run bash "$DEPS" --probe
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=satisfied"* ]] || false
}

@test "every requirement in the repo's requirements.txt carries an '# import:' marker" {
  run grep -cE '^[^#[:space:]].*#[[:space:]]*import:[[:space:]]*[A-Za-z0-9_.]+' "$REPO_ROOT/requirements.txt"
  [ "$status" -eq 0 ]
  marked="$output"
  run grep -cE '^[^#[:space:]]' "$REPO_ROOT/requirements.txt"
  [ "$output" -eq "$marked" ]
}
