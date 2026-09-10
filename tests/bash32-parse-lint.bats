#!/usr/bin/env bats
# bash32-parse-lint — proves the ratchet in scripts/bash32-parse-lint.sh both FIRES on the real scar
# and STAYS SILENT on every shape it must not claim.
#
# The scar: macOS /bin/bash is 3.2 and does not recognise a heredoc delimiter inside $( ) — it lexes
# the heredoc BODY as code, so one apostrophe in a comment there opens an unterminated quote and the
# whole script dies at parse time. scripts/mcp-ssot-wire.sh carried exactly that and was red in 12 of
# 12 clean post-cure off-box folds, alongside tests/mcp-no-inherit.bats which runs the same script —
# together the deterministic floor that made an off-box green unreachable. The operator's PATH puts
# brew bash 5.3 first, so it was invisible on the desk.
# Record: docs/research/offbox-deterministic-floor-2026-09-10.md
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail (memory: negated-assertion-dead-unless-final).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/bash32-parse-lint.sh"
  OLD=/bin/bash
  if [ ! -x "$OLD" ] || [ "$("$OLD" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" != "3" ]; then
    skip "no bash 3.x at $OLD — this ratchet's precondition is environment-falsifiable"
  fi
  # Fixture $HOME: this suite must never read or write the operator's live ~/ (sibling rule,
  # scripts/test-hermeticity-lint.sh). The subject resolves its scan root from git, not from HOME.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  WORK="$BATS_TEST_TMPDIR/w"; mkdir -p "$WORK"
}

# The scar, reduced to its mechanism: apostrophe inside a <<'PY' heredoc nested in $( ).
_write_scar() {
  cat > "$1" <<'EOS'
#!/bin/bash
v="$(python3 - <<'PY'
# set only the SSOT's own keys
print("x")
PY
)"
if [ -n "$v" ]; then
  echo "$v"
fi
EOS
}

@test "the tree as it stands is CLEAN — a ratchet that ships standing-red is rot" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "lint went red on the tree:"; echo "$output"; false; }
}

@test "RED-PROOF: the scar shape — apostrophe in a heredoc nested in a command substitution — is CAUGHT" {
  _write_scar "$WORK/scar.sh"
  run bash "$LINT" "$WORK/scar.sh"
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status:"; echo "$output"; false; }
  [[ "$output" == *"scar.sh"* ]] || { echo "the offending file was not named:"; echo "$output"; false; }
}

@test "CONTROL: the SAME shape without the apostrophe is NOT flagged" {
  _write_scar "$WORK/ok.sh"
  # one variable: remove the apostrophe, keep the heredoc-inside-$( ) shape intact
  sed -i '' "s/SSOT's own/SSOT own/" "$WORK/ok.sh"
  run bash "$LINT" "$WORK/ok.sh"
  [ "$status" -eq 0 ] || { echo "false positive on the apostrophe-free twin:"; echo "$output"; false; }
}

@test "CONTROL: a file broken under BOTH bashes is NOT this ratchet's finding" {
  printf '#!/bin/bash\nif [ 1\n' > "$WORK/broken.sh"
  run bash "$LINT" "$WORK/broken.sh"
  [ "$status" -eq 0 ] || { echo "claimed a plain syntax error it did not discriminate:"; echo "$output"; false; }
}

@test "POPULATION: a .bats file is excluded BY EXTENSION even with a bash shebang" {
  # The shebang is deliberately `#!/bin/bash` here: if the exclusion keyed on the shebang instead
  # of the extension, this file would be scanned and the scar inside it flagged.
  _write_scar "$WORK/f.bats"
  run bash "$LINT" "$WORK/f.bats"
  [ "$status" -eq 0 ] || { echo "scanned a bats file:"; echo "$output"; false; }
}

@test "REAL ARTIFACT: the pre-fix mcp-ssot-wire.sh, replayed from git, is CAUGHT" {
  blob=949ff9bd5c93dba113102a470c3f01bd808ea04f
  git -C "$REPO" cat-file -e "$blob" 2>/dev/null || skip "pre-fix blob $blob unreachable in this checkout"
  git -C "$REPO" cat-file blob "$blob" > "$WORK/prefix.sh"
  run bash "$LINT" "$WORK/prefix.sh"
  [ "$status" -eq 1 ] || { echo "the ratchet does not catch the artifact it was built for:"; echo "$output"; false; }
}

@test "an unusable environment reports NON-VERDICT (exit 2), never a false green" {
  run env CC_BASH32=/nonexistent-bash bash "$LINT"
  [ "$status" -eq 2 ] || { echo "expected rc 2, got $status:"; echo "$output"; false; }
}
