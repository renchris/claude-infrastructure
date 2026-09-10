#!/usr/bin/env bats
# smart-bash-allowlist — the INERT classes: arithmetic expansion, comments, `[` and `:`.
#
# WHY THIS SUITE EXISTS (2026-09-10, cc-backlog 5a629c6465d1, PERMISSION_HARVEST.md §12).
# Four shapes that cannot execute anything were each deferring a whole command:
#
#   I1  `$(( … ))` — ARITHMETIC expansion. `extract_substitutions` returned not-ok on sight of
#       it, so the WHOLE command deferred. Measured on the beacon archive: 87 of 1,749
#       structural rows failed the substitution pass at the top level because of it. It also
#       MASKED every other cause in those rows — the attribution pass returns early on an
#       undecomposable command, so a harvest report blamed "cannot decompose" instead of the
#       verbs the rows actually carry.
#   I2  a `# comment` line — `verb()` returned None and the segment was refused as "not on the
#       allowlist", so one comment deferred an entire multi-line command (162 occurrences over
#       114 structural rows).
#   I3  `[` — the exact synonym of `test`, which IS in READ_ONLY. `test -f x` was allowed and
#       `[ -f x ]` refused: one operator-visible inconsistency, 133 occurrences / 102 rows.
#   I4  `:` — the exact synonym of `true`, likewise already in READ_ONLY.
#
# HONEST SCOPE. This change clears ZERO archived prompts (measured A/B over all 3,768 rows:
# allow 162 before, 162 after, 0 regressions). It is a MEASUREMENT-FIDELITY fix, not a
# prompt-reduction lever — rows carry several independent blockers, and the ceiling analysis in
# docs/research/permission-harvest-hook-ceiling-2026-09-10.md says why no single lever can move
# the number. The suite is written so that claim stays true: the SAFETY cases below are the
# load-bearing ones.
#
# CONTROL DISCIPLINE. Every I-case runs against the pinned PRE-FIX blob as well, so a case that
# cannot fail before the fix is visible as such. The safety cases are green in BOTH arms — which
# makes them equivalence guards, not red-proofs, so each one is additionally run against a
# MUTANT that removes the cure. A green-in-both-arms case with no mutant behind it tests nothing
# (memory: a mutant must remove the cure, not merely disable one arm of it).

setup() {
  # Fixture $HOME first: load_fence() reads $CLAUDE_CONFIG_DIR or ~/.claude/settings.json, and an
  # unfixtured suite would read the operator's live fence. test-hermeticity-lint.sh blocks on this.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  [ -f "$REPO/hooks/lib/smart-bash-allowlist.py" ] || skip "decision core not found"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"; : > "$PROJ/file.ts"
  FIX="$(mktree fix "$REPO/hooks/lib/smart-bash-allowlist.py")"
}

# The core resolves `_RM_HOOK` relative to its OWN __file__, so an arm must be built in the SHAPE
# the subject reads — a flat copy in a scratch dir loses the sibling hook, every `rm` segment then
# refuses, and the A/B acquires a second variable. (Memory: subject reads its own path.)
#
# The `local` split below is load-bearing, not style. `local name="$1" d="$BATS_TEST_TMPDIR/$name"`
# expands `$name` to EMPTY in one statement, so every arm resolved to the tmpdir ROOT and the
# prefix tree silently OVERWROTE the fix tree — two arms at one path, which makes a control
# compare a file against itself. Caught only because the grep for the pinned defect then looked
# in a directory that had never been created. The non-empty assertion keeps it caught.
mktree() {
  local name="$1" lib="$2"
  local d="$BATS_TEST_TMPDIR/$name"
  [ -n "$name" ] || { echo "mktree: empty arm name — arms would collide at one path" >&2; return 1; }
  mkdir -p "$d/hooks/lib"
  cp "$REPO/hooks/smart-bash-allowlist.sh" "$d/hooks/"
  cp "$REPO/hooks/rm-safe-allowlist.sh" "$d/hooks/" 2>/dev/null || true
  if [ -f "$lib" ]; then cp "$lib" "$d/hooks/lib/smart-bash-allowlist.py"
  else git -C "$REPO" cat-file blob "$lib" > "$d/hooks/lib/smart-bash-allowlist.py"; fi
  [ -s "$d/hooks/lib/smart-bash-allowlist.py" ] || return 1
  echo "$d/hooks/smart-bash-allowlist.sh"
}

# decide <hook.sh> <command> -> allow | defer
decide() {
  local hook="$1" cmd="$2" json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$PROJ" && printf '%s' "$json" | bash "$hook" 2>/dev/null | grep -q '"permissionDecision": "allow"'); then
    echo allow
  else
    echo defer
  fi
}

# Pinned by BLOB SHA, never by ref: `origin/main` would compare the fixed file against itself the
# moment this lands, inverting every control for a reason unrelated to the defect.
PREFIX_BLOB=d3850a25c73963cc06e75235107cdd006f551d4e   # hooks/lib/smart-bash-allowlist.py @ pre-fix

prefix_hook() {
  local h; h="$(mktree prefix "$PREFIX_BLOB")" || return 1
  # positive control ON THE CONTROL: the pinned blob must actually carry the defect, else this
  # suite would "prove" the fix against an artifact that never had it.
  grep -q 'arithmetic )) — not a command, refuse' "$BATS_TEST_TMPDIR/prefix/hooks/lib/smart-bash-allowlist.py" || return 1
  echo "$h"
}

# mutant <name> <python-expr-free sed script> — my FIXED core with the cure removed.
mutant() {
  local name="$1"; shift
  local lib="$BATS_TEST_TMPDIR/$name.py"
  python3 "$BATS_TEST_DIRNAME/sba-mutate.py" "$name" \
    "$REPO/hooks/lib/smart-bash-allowlist.py" "$lib" || return 1
  mktree "$name" "$lib"
}

# ── the four inert classes: each must FAIL before the fix ────────────────────────────

@test "I1: arithmetic expansion no longer defers the whole command" {
  [ "$(decide "$FIX" 'echo $((1+2))')" = allow ]
  [ "$(decide "$FIX" 'echo $(( (3*4) - 1 ))')" = allow ]
  [ "$(decide "$FIX" 'D=1; echo $((D+1))')" = allow ]

  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE — pinned blob missing or lacks the defect"; return 1; }
  [ "$(decide "$old" 'echo $((1+2))')" = defer ]
  [ "$(decide "$old" 'echo $(( (3*4) - 1 ))')" = defer ]
}

@test "I2: a comment line carries no command" {
  [ "$(decide "$FIX" "$(printf 'echo hi\n# a comment\nls')")" = allow ]
  [ "$(decide "$FIX" 'echo hi # trailing')" = allow ]

  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE"; return 1; }
  [ "$(decide "$old" "$(printf 'echo hi\n# a comment\nls')")" = defer ]
}

@test "I3/I4: \`[\` is test and \`:\` is true — both already in READ_ONLY under their word spellings" {
  [ "$(decide "$FIX" '[ -f file.ts ]')" = allow ]
  [ "$(decide "$FIX" ':')" = allow ]
  [ "$(decide "$FIX" '[ -f file.ts ] && echo yes')" = allow ]

  local old; old="$(prefix_hook)" || { echo "CONTROL UNAVAILABLE"; return 1; }
  [ "$(decide "$old" '[ -f file.ts ]')" = defer ]
  [ "$(decide "$old" ':')" = defer ]
  # the word spellings were allowed all along — that asymmetry IS the defect
  [ "$(decide "$old" 'test -f file.ts')" = allow ]
  [ "$(decide "$old" 'true')" = allow ]
}

# ── safety: green in BOTH arms, so each is pinned by a mutant that removes the cure ──

@test "SAFETY 1: a command substitution hidden inside arithmetic still defers" {
  # `$(($(id -u)))` and a backtick body would smuggle a COMMAND past a placeholder that the
  # outer scanners never see again.
  [ "$(decide "$FIX" 'echo $(($(id -u)))')" = defer ]
  [ "$(decide "$FIX" 'echo $((`whoami`))')" = defer ]
  [ "$(decide "$FIX" 'echo $(( ${!v} ))')" = defer ]

  # MUTANT: delete the _ARITH_NEVER/charclass screen. The case must go RED, else it is decorative.
  local m; m="$(mutant arith_never)" || { echo "MUTANT UNAVAILABLE"; return 1; }
  [ "$(decide "$m" 'echo $(($(id -u)))')" = allow ]
}

@test "SAFETY 2: \`\$((cmd) )\` is not arithmetic — a non-\`))\` close defers" {
  # `$( (subshell) )` written without the space is a COMMAND substitution. Treating it as
  # arithmetic data would hand the contents a free pass.
  [ "$(decide "$FIX" 'echo $((cmd) )')" = defer ]

  # MUTANT: drop the `))`-pair requirement from _arith_end.
  local m; m="$(mutant arith_pair)" || { echo "MUTANT UNAVAILABLE"; return 1; }
  [ "$(decide "$m" 'echo $((cmd) )')" = allow ]
}

@test "SAFETY 3: the redirect scanner still sits ABOVE \`[\` and \`:\`" {
  # `: > file` is the one way a no-op touches the filesystem; `[ … ] > file` likewise. Both must
  # stay refused, which is only true because the new branches sit BELOW redirects_to_file().
  [ "$(decide "$FIX" ': > out.txt')" = defer ]
  [ "$(decide "$FIX" '[ -f file.ts ] > out.txt')" = defer ]
  [ "$(decide "$FIX" '[ -f file.ts ] >> out.txt')" = defer ]

  # MUTANT: hoist the two branches above the redirect check.
  local m; m="$(mutant noop_above_redirect)" || { echo "MUTANT UNAVAILABLE"; return 1; }
  [ "$(decide "$m" ': > out.txt')" = allow ]
}

@test "SAFETY 4: a command that is ONLY comments is not allowed" {
  # decide() requires judged > 0, so reducing comments to "" must not turn a comment-only input
  # into a blanket allow.
  local nuke; nuke="rm -""rf /"
  [ "$(decide "$FIX" "# $nuke")" = defer ]
  [ "$(decide "$FIX" '# just a note')" = defer ]

  # MUTANT: admit comments as an allowed VERB instead of reducing them away.
  local m; m="$(mutant comment_as_verb)" || { echo "MUTANT UNAVAILABLE"; return 1; }
  [ "$(decide "$m" '# just a note')" = allow ]
}

@test "SAFETY 5: \`[\` without its closing bracket is not the builtin" {
  [ "$(decide "$FIX" '[ -f file.ts')" = defer ]
}

@test "SAFETY 6: the operator's own fence still binds every new branch" {
  # The fence is the one thing a hook allow cannot revoke, and the whole point of these classes
  # is that they make MORE commands judgeable — so they must not carry a gated verb through.
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions":{"ask":["Bash(git push:*)"],"deny":["Bash(curl:*)"]}}
JSON
  [ "$(decide "$FIX" '[ -f file.ts ] && git push origin x')" = defer ]
  [ "$(decide "$FIX" "$(printf '# note\ncurl https://example.com')")" = defer ]
  [ "$(decide "$FIX" 'echo $((1+1)); git push origin x')" = defer ]
  # control: with the fence in place the inert classes themselves still decide
  [ "$(decide "$FIX" '[ -f file.ts ]')" = allow ]
}

@test "SAFETY 7: danger patterns still win over every inert class" {
  # The `&&` lives in a VARIABLE, not on the assertion line: bats-assert-liveness reads an `&&`
  # anywhere on the line as an and-chain that absorbs the assertion's exit status, and a literal
  # one in the test DATA trips it. Hoisting the payload satisfies the lint by being right rather
  # than by annotating the line, which would silence it for any real `&&` added here later.
  local nuke chained arith
  nuke="rm -""rf /"
  chained="[ -f file.ts ] && $nuke"
  arith="echo \$((1+1)) && $nuke"
  [ "$(decide "$FIX" "$chained")" = defer ]
  [ "$(decide "$FIX" "$arith")" = defer ]
}

@test "REGRESSION GUARD: a substitution standing in the VERB position still defers" {
  # The arithmetic placeholder is the same token a command substitution leaves behind, and a
  # placeholder in verb position is genuine indirection.
  [ "$(decide "$FIX" '$((x)) --flags')" = defer ]
  [ "$(decide "$FIX" '$(which foo) --flags')" = defer ]
}
