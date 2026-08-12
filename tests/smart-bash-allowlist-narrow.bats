#!/usr/bin/env bats
# smart-bash-allowlist — the RETIRED rules (2, 4) and the repaired project-containment guard.
#
# Why this suite exists (2026-08-12). The hook is wired in 0 of 5 config dirs, so every assertion
# here is about what it WOULD do once wired — which is exactly when it stops being auditable by
# reading it. Two defects were found by reading, both of which made the "turn it on" option unsafe:
#
#   D1  Rule 4 (git push) was DEAD CODE, and separately mis-specified. Its extraction regex
#       `[[:alnum:]_.\-/]+` is an invalid character range: /usr/bin/grep exits 2 with "invalid
#       character range", so GIT_PUSH_MATCH was always empty and the rule could never allow ANY
#       push. Underneath that, its reject list was ^(develop|production|prod|release.*)$ — main
#       and master ABSENT — so the moment anyone repaired the bracket expression, `git push
#       origin main` would have started auto-allowing against a standing never-push-to-main rule
#       and against the operator's own `Bash(git push:*)` ask gate. A latent defect behind a
#       broken matcher, which is the worst place for one: no observable symptom to prompt a fix.
#
#       NOTE ON HOW THIS WAS NEARLY MIS-REPORTED. The first version of this suite asserted that
#       the pre-fix hook DID allow `git push origin main`, and its control failed. The missing
#       main|master was true; the consequence attached to it was not. A true fact beside a wrong
#       consequence reads as a diagnosis — the control is what separated them.
#   D2  Rules 3 and 5 guarded "absolute path outside the project" with an ERE negative lookahead,
#       `^/(?!Users/chrisren/Development…)`. POSIX ERE has no lookahead: /usr/bin/grep exits 2
#       ("repetition-operator operand invalid"), and the call site tested `if grep -qE …; then
#       exit 0; fi`, so rc 2 never took the reject branch. The guard was inert and fail-OPEN.
#
# CONTROL DISCIPLINE: every test below is run against BOTH the current hook and the pre-fix blob
# from git history. A test that cannot fail on the pre-fix file proves nothing about the fix, and
# D2 in particular is the kind of guard that passes a naive test for the wrong reason (it rejects
# nothing, so any input that SHOULD be allowed is still allowed). PREFIX_REF is resolved from the
# commit that introduced the fix, so the control cannot silently decay as the file moves on.

setup() {
  # Fixture $HOME before anything else: the hook and its helpers may read ~/ , and an unfixtured
  # suite mutates the operator's live config. test-hermeticity-lint.sh blocks the land on this.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HOOK="$REPO/hooks/smart-bash-allowlist.sh"
  [ -f "$HOOK" ] || skip "hook not found"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"; : > "$PROJ/file.ts"
}

# decide <hook-path> <command> -> allow | defer
decide() {
  local hook="$1" cmd="$2" json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$PROJ" && printf '%s' "$json" | bash "$hook" 2>/dev/null | grep -q '"permissionDecision": "allow"'); then
    echo allow
  else
    echo defer
  fi
}

# materialize the PRE-FIX hook from git so the control replays the real artifact, never a mutant.
#
# Pinned by BLOB SHA, not by branch or commit message. The first draft resolved it with
# `git log --grep=<subject>` and the blob was therefore unreachable until the fix itself was
# committed — so on the run that mattered all three controls SKIPPED, and a skipped control is
# indistinguishable from a passing one in the TAP output while proving nothing. `origin/main`
# would have decayed the opposite way: correct until this fix lands, then silently comparing the
# fixed file against itself, at which point the controls invert and fail for a reason that has
# nothing to do with the defect. A blob sha is content-addressed and immune to both.
PREFIX_BLOB=626ec2d47f571086c1e7b35d0b0c8b701379340a   # hooks/smart-bash-allowlist.sh @ pre-fix

prefix_hook() {
  local out="$BATS_TEST_TMPDIR/prefix-hook.sh"
  if [ ! -s "$out" ]; then
    git -C "$REPO" cat-file blob "$PREFIX_BLOB" > "$out" 2>/dev/null || return 1
  fi
  [ -s "$out" ] || return 1
  # positive control on the CONTROL: the pinned blob must actually contain the defect, else this
  # suite would "prove" the fix against an artifact that never had the bug.
  grep -q 'develop|production' "$out" || return 1
  echo "$out"
}

@test "D1: no push is auto-allowed, and the pre-fix rule 4 was DEAD rather than permissive" {
  [ "$(decide "$HOOK" "git push origin main")" = defer ]
  [ "$(decide "$HOOK" "git push origin master")" = defer ]
  [ "$(decide "$HOOK" "git push origin feature/x")" = defer ]   # rule 4 retired entirely

  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE - pinned pre-fix blob missing or lacks the defect"; return 1; }
  # The pre-fix rule allowed NOTHING — its extraction regex errored out before any branch ran.
  # This is the corrected claim: the earlier draft asserted `= allow` here and was refuted.
  [ "$(decide "$old" "git push origin feature/x")" = defer ]
  [ "$(decide "$old" "git push origin main")" = defer ]
}

@test "D1 root cause: rule 4's extraction regex is an invalid character range under /usr/bin/grep" {
  # This is what made rule 4 dead, and it is the thing that would have UNMASKED the missing
  # main|master had anyone repaired it. Pinned so a future repair cannot silently re-arm the rule.
  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE"; return 1; }
  run bash -c 'echo "git push origin main" | /usr/bin/grep -oE "^[[:space:]]*git[[:space:]]+push[[:space:]]+origin[[:space:]]+[[:alnum:]_.\-/]+$"'
  [ "$status" -eq 2 ]
  # A SIMPLE COMMAND, not `[[ ]]`. Two dead forms were caught here in a row, and the second is the
  # instructive one:
  #   draft 1  [[ "$output" == *…* ]] || [[ "$stderr" == *…* ]]   — an `||` chain cannot fail, and
  #            `$stderr` is unset anyway (bats folds stderr into $output without --separate-stderr).
  #   draft 2  [[ "$output" == *…* ]]                             — STILL dead. Collapsing to one
  #            condition fixed the `||`, but in this bats a `[[ ]]` failure mid-test does not fail
  #            the test; only a simple command's status is caught. A mutant with a deliberately
  #            absent needle still reported `ok`, which is exactly how a green suite credits nothing.
  # grep is a simple command, so its non-zero status registers. Mutant-verified in both directions.
  echo "$output" | grep -q "invalid character range"

  # and the reject list it guarded genuinely omitted main/master
  grep -q "develop|production|prod|release" "$old"
  ! grep -qE '\^\(main\|master' "$old"
}

@test "D1b: no push of any kind is auto-allowed now that rule 4 is retired" {
  [ "$(decide "$HOOK" "git push origin release-2")" = defer ]
  [ "$(decide "$HOOK" "git push")" = defer ]
}

@test "rule 2 retired: no rm is auto-allowed, not even a build artifact" {
  [ "$(decide "$HOOK" "rm -rf node_modules")" = defer ]
  [ "$(decide "$HOOK" "rm -rf dist")" = defer ]

  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE - pinned pre-fix blob missing or lacks the defect"; return 1; }
  [ "$(decide "$old" "rm -rf node_modules")" = allow ]          # CONTROL
}

@test "D2: an absolute path outside the project is refused for sed -i and chmod" {
  [ "$(decide "$HOOK" "sed -i 's/a/b/' /etc/hosts")" = defer ]
  [ "$(decide "$HOOK" "chmod 644 /etc/hosts")" = defer ]
  [ "$(decide "$HOOK" "chmod 644 ../outside.ts")" = defer ]
}

@test "D2 control: the pre-fix containment guard was inert, so it allowed the same paths" {
  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE - pinned pre-fix blob missing or lacks the defect"; return 1; }
  # The pre-fix guard exits 2 on its own regex, never taking the reject branch.
  [ "$(decide "$old" "chmod 644 /etc/hosts")" = allow ]
}

@test "D2 does not over-reject: in-project targets still auto-allow" {
  [ "$(decide "$HOOK" "chmod 644 file.ts")" = allow ]
  [ "$(decide "$HOOK" "chmod 755 $PROJ/file.ts")" = allow ]     # absolute but UNDER $PWD
}

@test "surviving rules are untouched: commit and read-only sed -n still auto-allow" {
  [ "$(decide "$HOOK" "git commit -m 'x'")" = allow ]
  [ "$(decide "$HOOK" "sed -n '1,20p' file.ts")" = allow ]
}

@test "kill switch still disarms every rule" {
  SMART_ALLOWLIST_DISABLED=1
  export SMART_ALLOWLIST_DISABLED
  [ "$(decide "$HOOK" "git commit -m 'x'")" = defer ]
}
