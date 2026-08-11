#!/usr/bin/env bats
# land-gate-memo.bats — the blob-sha-keyed statics memo (land-arch P3, backlog 963bbebe7c9a).
#
# WHAT IS BEING PINNED. 22-23% of lands re-round (a sibling lands mid-gate, exit 42) and re-run the
# whole unlocked gate over a tree that is byte-identical except for the sibling's delta. shellcheck,
# `bash -n` and py_compile are pure functions of one file's bytes, so re-proving an unchanged file
# is pure waste. scripts/lib/gate-memo.sh removes it by keying each per-file verdict on the blob sha
# PLUS the checker's own version.
#
# THE FAILURE DIRECTION IS THE WHOLE POINT, so most of this suite tests the memo NOT working: a
# miss, a corrupt entry, an unreadable entry, a superseded checker version and a red verdict must
# every one of them RE-RUN THE CHECK. A memo that returns a green it did not earn is strictly worse
# than the seconds it saves (repo memory: gate-default-decides-failure-direction).
#
# RED-PROOFED AGAINST A NAIVE MUTANT, not merely against the pre-P3 tree. "No memo at all" fails
# these tests trivially (undefined functions), which proves nothing about the design. The control is
# tests/fixtures/gate-memo-naive.sh — a memo that keys on the PATH ONLY (no blob sha, no version
# salt) and treats any existing entry as green. Running this suite with
# CC_MEMO_LIB=tests/fixtures/gate-memo-naive.sh must FAIL exactly the invalidation and corruption
# tests and PASS the rest; that asymmetry is what attributes each test to the mechanism it guards
# (repo memory: control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"
  MEMO_LIB="$REPO/${CC_MEMO_LIB:-scripts/lib/gate-memo.sh}"
  export SHIP_LAND_MEMO_LIB="$MEMO_LIB"

  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || exit 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  # py_compile drops __pycache__/ NEXT TO the file it compiles, which would leave the fixture tree
  # dirty and make the SECOND gate exit on ship-land's dirty-tree refusal — an artefact of the
  # fixture, not of the memo. The real repo ignores it the same way.
  printf '__pycache__/\n*.pyc\n' > .gitignore
  git add base.txt .gitignore
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=30
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-memo"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off
  export CC_GATE_MAX_LOAD=0
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N SHIP_LAND_LANE SHIP_LAND_SMOKE_BUDGET_S SHIP_LAND_SMOKE_NICE \
        SHIP_LAND_TIMEOUT_BIN SHIP_LAND_SMOKE_STATE SHIP_LAND_SMOKE_N SHIP_LAND_SMOKE_S \
        SHIP_LAND_NET_STATE SHIP_LAND_MEMO 2>/dev/null || true

  # PATH-shimmed checkers whose ARGV is the durable product: a re-check is visible as a new line,
  # a carried verdict as the absence of one. The shim's reported version lives in a file so a test
  # can upgrade the checker without touching any subject file.
  SC_ARGV="$BATS_TEST_TMPDIR/sc-argv"
  SC_VERSION_F="$BATS_TEST_TMPDIR/sc-version"
  SC_FAIL_ON="$BATS_TEST_TMPDIR/sc-fail-on"     # basename ⇒ the shim reports that file RED
  echo "0.11.0" > "$SC_VERSION_F"
  : > "$SC_ARGV"
  SHIMDIR="$BATS_TEST_TMPDIR/shims"
  mkdir -p "$SHIMDIR"
  cat > "$SHIMDIR/shellcheck" <<EOF
#!/bin/bash
if [ "\$1" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\nversion: %s\n' "\$(cat "$SC_VERSION_F")"
  exit 0
fi
printf '%s\n' "\$*" >> "$SC_ARGV"
if [ -s "$SC_FAIL_ON" ]; then
  for a in "\$@"; do
    case "\$a" in *"\$(cat "$SC_FAIL_ON")") echo "SC9999 synthetic finding in \$a" >&2; exit 1 ;; esac
  done
fi
exit 0
EOF
  chmod +x "$SHIMDIR/shellcheck"
  export PATH="$SHIMDIR:$PATH"
}

landable() {  # $1=file $2=body-marker — a committed shell file, so the statics always fire
  printf '#!/usr/bin/env bash\necho %s\n' "$2" > "$1"
  git add "$1"
  git commit -q -m "add $1"
}

gate_once() {  # run the gate exactly as a re-round does: reconcile + statics, stop before push
  run "$SHIPLAND" --dry-run --trunk main
}

sc_invocations() { grep -c . "$SC_ARGV" 2>/dev/null || echo 0; }
sc_last() { tail -1 "$SC_ARGV" 2>/dev/null; }

# ---- the memo carries a verdict it earned ----------------------------------

@test "a second gate over unchanged content does not re-invoke the checker" {
  git checkout -q -b feat/a main
  landable a.sh alpha
  gate_once
  [ "$status" -eq 0 ]
  local first; first="$(sc_invocations)"
  [ "$first" -ge 1 ]
  echo "first-run shellcheck invocations: $first" >&3

  gate_once
  [ "$status" -eq 0 ]
  # The file was proven a round ago and is byte-identical: nothing is left unproven, so the
  # checker is not started at all. THIS is the re-round cost the item is about.
  [ "$(sc_invocations)" -eq "$first" ]
}

# ---- invalidation: the two axes the key must separate ----------------------

@test "INVALIDATES on content change: an edited file is re-checked" {
  git checkout -q -b feat/b main
  landable b.sh beta
  gate_once
  local before; before="$(sc_invocations)"

  printf '#!/usr/bin/env bash\necho beta-edited\n' > b.sh
  git commit -q -am "edit b.sh"
  gate_once
  [ "$status" -eq 0 ]
  [ "$(sc_invocations)" -gt "$before" ]
  [[ "$(sc_last)" == *"b.sh"* ]]
}

@test "INVALIDATES on checker version change: an upgrade re-checks everything" {
  git checkout -q -b feat/c main
  landable c.sh gamma
  gate_once
  local before; before="$(sc_invocations)"
  gate_once                                   # carried, as the first test pins
  [ "$(sc_invocations)" -eq "$before" ]

  echo "0.12.0" > "$SC_VERSION_F"             # the checker itself changed; the bytes did not
  gate_once
  [ "$status" -eq 0 ]
  # A verdict earned under 0.11.0 says nothing about 0.12.0 — without the version salt the memo
  # becomes a stale-verdict generator, which is the failure mode worse than the cost it saves.
  [ "$(sc_invocations)" -gt "$before" ]
  [[ "$(sc_last)" == *"c.sh"* ]]
}

# ---- failure direction: every unknown re-runs, none returns green -----------

@test "a CORRUPT entry re-runs the check and cannot pass a red file" {
  git checkout -q -b feat/d main
  landable d.sh delta
  gate_once
  local before; before="$(sc_invocations)"

  # Corrupt every entry: a truncated / hand-edited / colliding body must fail the exact match.
  local store; store="$(git rev-parse --git-common-dir)/ship-land-memo"
  [ -d "$store" ]
  local n; n="$(find "$store" -type f | grep -c . || echo 0)"
  [ "$n" -ge 1 ]
  find "$store" -type f -exec sh -c 'printf "gate-memo v1 green" > "$1"' _ {} \;

  # …and simultaneously make the file genuinely RED. If the corrupt entry were honoured, the gate
  # would return the stale green and this land would pass — the exact defect. It must go red.
  echo "d.sh" > "$SC_FAIL_ON"
  gate_once
  [ "$(sc_invocations)" -gt "$before" ]      # the check RE-RAN
  [ "$status" -ne 0 ]                        # and its real verdict won
}

@test "an UNREADABLE entry re-runs the check" {
  git checkout -q -b feat/e main
  landable e.sh epsilon
  gate_once
  local before; before="$(sc_invocations)"

  local store; store="$(git rev-parse --git-common-dir)/ship-land-memo"
  find "$store" -type f -exec chmod 000 {} \;
  gate_once
  chmod -R u+rw "$store" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(sc_invocations)" -gt "$before" ]
}

@test "a RED verdict is never cached: it re-runs and stays red" {
  git checkout -q -b feat/f main
  landable f.sh phi
  echo "f.sh" > "$SC_FAIL_ON"
  gate_once
  [ "$status" -ne 0 ]
  local before; before="$(sc_invocations)"

  gate_once
  [ "$status" -ne 0 ]                        # still red — no green was ever recorded
  [ "$(sc_invocations)" -gt "$before" ]      # and the finding is re-printed by the real checker,
                                             # never replayed out of a cache
}

@test "a DIRTY worktree disables the memo entirely" {
  # The population/blob key is only equal to what the linters read if the tree matches HEAD.
  # memo_init asserts that rather than assuming it; ship-land's own dirty-tree refusal is the
  # outer guard, so this is tested at the library seam where the assertion lives.
  # shellcheck source=/dev/null
  . "$MEMO_LIB"
  run memo_init
  [ "$status" -eq 0 ]
  echo dirt >> base.txt
  run memo_init
  [ "$status" -ne 0 ]
  git checkout -q -- base.txt
}

# ---- the rejected-S3 tripwire ----------------------------------------------

@test "the memo changes no suite selection: cold-memo and memo-off hand the linters the same set" {
  git checkout -q -b feat/g main
  landable g.sh gamma
  printf 'print("x")\n' > g.py
  git add g.py
  git commit -q -m "add g.py"

  SHIP_LAND_MEMO=off gate_once
  [ "$status" -eq 0 ]
  local off_argv; off_argv="$(cat "$SC_ARGV")"

  : > "$SC_ARGV"
  rm -rf "$(git rev-parse --git-common-dir)/ship-land-memo"
  gate_once                                   # memo ON but COLD — nothing proven yet
  [ "$status" -eq 0 ]

  # Byte-identical argv. P3 memoizes VERDICTS; changed-file-scoped suite SELECTION is proposal S3
  # and it is rejected. A memo that narrowed the input set on a cold run would be S3 wearing P3's
  # name, and this assertion is the tripwire that says so.
  [ "$(cat "$SC_ARGV")" = "$off_argv" ]
}

@test "the memo changes no ARM selection: the gate runs the same steps carrying or proving" {
  # The sibling of the assertion above, and the one that actually names S3's unit. S3 was
  # changed-file-scoped SUITE SELECTION — running FEWER STEPS because of what the diff touched.
  # P3 runs the SAME steps and only skips re-PROVING a verdict it already holds, so the sequence of
  # gate steps must be identical between a fully-carried run and a memo-off run. Counts and
  # parentheticals are normalised away because those are exactly what the memo is allowed to
  # change; the step LABELS are what it may not.
  git checkout -q -b feat/i main
  landable i.sh iota

  SHIP_LAND_MEMO=off gate_once
  [ "$status" -eq 0 ]
  local off_steps
  off_steps="$(printf '%s\n' "$output" | grep '^→ gate:' | sed -e 's/([^)]*)//g' -e 's/[0-9][0-9]*//g')"

  gate_once                       # cold: proves and records
  [ "$status" -eq 0 ]
  gate_once                       # warm: everything carried — the maximally-different case
  [ "$status" -eq 0 ]
  local on_steps
  on_steps="$(printf '%s\n' "$output" | grep '^→ gate:' | sed -e 's/([^)]*)//g' -e 's/[0-9][0-9]*//g')"

  # The memo's own summary line is the one legitimate addition; drop it and the rest must match.
  off_steps="$(printf '%s\n' "$off_steps" | grep -v 'statics memo')"
  on_steps="$(printf '%s\n' "$on_steps" | grep -v 'statics memo')"
  [ "$on_steps" = "$off_steps" ]
}

@test "SHIP_LAND_MEMO=off reproduces the pre-P3 gate exactly" {
  git checkout -q -b feat/h main
  landable h.sh eta
  SHIP_LAND_MEMO=off gate_once
  local first; first="$(sc_invocations)"
  SHIP_LAND_MEMO=off gate_once
  [ "$status" -eq 0 ]
  # With the memo off, nothing is ever carried — the second round pays in full, which is both the
  # pre-P3 behaviour and the A/B baseline the measurement is taken against.
  [ "$(sc_invocations)" -gt "$first" ]
}
