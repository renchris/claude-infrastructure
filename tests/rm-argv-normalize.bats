#!/usr/bin/env bats
# The CATASTROPHIC-RM contract: recursive + force + a root/home target is ONE rule, and the way it
# is spelled must not decide whether it is enforced.
#
# WHAT HAPPENED (codex-security scan dc12c8db, finding 1 — reproduced by execution, not inference):
# hooks/validate-bash.sh hardcoded a single flag bundle, `-rf`, in the deny regex and the bundle set
# `-(r|rf|fr)` in the warn regex. Feeding the SHIPPED hook crafted payloads and reading the emitted
# permissionDecision:
#     rm -rf /*                  deny          ← the only spelling it knew
#     rm -fr /*                  ask           ← downgraded to a prompt
#     rm -r -f /*                ask
#     rm -rf /                   ask           ← the slash branch ended in `[^a-zA-Z]`, which must
#                                                CONSUME a character, so bare `/` at end-of-input
#                                                could not match — while the tilde branch beside it
#                                                was `~(/|$|…)` and did. That internal disagreement
#                                                is what proves oversight rather than intent.
#     rm -Rf /                   NO DECISION   ← -R is the same flag, spelled in caps
#     rm -f -r /                 NO DECISION
#     rm --recursive --force /*  NO DECISION   ← the long form is not a flag bundle at all
# 11 of the 13 spellings below walked past it. The equivalence class is not enumerable by regex —
# order, bundling, case, long form and `--` separation multiply — so the fix answers the spelling
# question by TOKENIZING (hooks/lib/is-true-flag.sh :: rm_argv_scan) and the rule is then read off
# argv exactly as CLAUDE.md states it.
#
# The mirror-image defect is in scope too, because text is not execution: the old regex DENIED
# `git commit -m "fix: guard rm -rf / properly"`, so the guard blocked its own fix from being
# committed. That is not hypothetical — it refused this very session's first probe command.
#
# Assertions use `|| false` where they are non-final: a bare `[[ ]]` / `!` / `A && B` is
# errexit-EXEMPT in bats and would be a DEAD assertion (memory: bats-dead-assertions).

setup() {
  # HERMETIC $HOME — the hook's last act is `mkdir -p ~/.claude/logs; echo "$CMD" >> …`, and the
  # UNCLEAR log asserted below lands there too. Unfixtured, every probe in this file would append
  # to the OPERATOR'S live command-audit log.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
}

# ── the corpus ──────────────────────────────────────────────────────────────────────────────────
# One list, used by FOUR consumers: the argv path, the two text-fallback paths, and the RED control
# that convicts the pre-fix hook with it. A per-test copy would let them drift and quietly stop
# testing the same thing.
catastrophic_corpus() {
  cat <<'CORPUS'
rm -rf /*
rm -fr /*
rm -r -f /*
rm --recursive --force /*
rm -rf /
rm -Rf /
rm -rf --no-preserve-root /
rm --force --recursive ~
rm -r -f $HOME
rm -rf "$HOME"
rm -rf ~/
rm -f -r /
rm -rf src && rm -rf /
CORPUS
}

decide_with() {  # <hook> <command> → DENY | ASK | ALLOW | PASS   (PASS = no decision emitted)
  local hook="$1" cmd="$2" out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$cmd" \
        | bash "$hook" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  # Parsing is part of the assertion: a decision the harness cannot parse is NOT enforced.
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"].upper())'
}

decision() { decide_with "$HOOK" "$1"; }

# not_denied_count <hook> → "<missed> <total>". The TOTAL is returned, never assumed: a "0 missed"
# read off a loop that never ran is the vacuous pass this whole file exists to avoid, and it is not
# hypothetical — the first draft of the python3-absent test below asserted 0 misses against a
# corpus it had silently failed to iterate. Misses are NAMED on stderr, so a red reads as "these
# spellings got through" rather than as a bare number.
not_denied_count() {
  local hook="$1" c d n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    d="$(decide_with "$hook" "$c")"
    if [ "$d" != "DENY" ]; then
      n=$((n+1))
      echo "  NOT DENIED ($d): $c" >&2
    fi
  done < <(catastrophic_corpus)
  # The trailing newline is load-bearing: `read` returns non-zero at EOF-without-newline even
  # though it did assign, and under bats errexit that non-zero FAILS the caller's test.
  printf '%s %s\n' "$n" "$total"
}

# ════ the rule ══════════════════════════════════════════════════════════════════════════════════

@test "every spelling of recursive+force on root/home is DENIED" {
  local missed total
  read -r missed total < <(not_denied_count "$HOOK")
  [ "$total" -eq 13 ]
  [ "$missed" -eq 0 ]
}

@test "the invocation is found wherever it really is, not only at argv[0]" {
  # sudo / env-prefix / time / an absolute path / -exec / xargs all put rm mid-argv, and a nested
  # shell hides the whole command inside ONE string token.
  [ "$(decision 'sudo rm -rf /')" = "DENY" ]
  [ "$(decision 'env FOO=1 rm -rf /')" = "DENY" ]
  [ "$(decision 'time rm -rf /')" = "DENY" ]
  [ "$(decision '/bin/rm -rf /')" = "DENY" ]
  [ "$(decision 'find . -name x -exec rm -rf / ;')" = "DENY" ]
  [ "$(decision 'xargs rm -rf /')" = "DENY" ]
  [ "$(decision "bash -c 'rm -rf /'")" = "DENY" ]
  [ "$(decision 'eval rm -rf /')" = "DENY" ]
}

@test "the same variable spelled differently is the same target" {
  [ "$(decision 'rm -rf ${HOME}')" = "DENY" ]      # the old regex knew only the brace-less form
  [ "$(decision 'rm -rf "$HOME"')" = "DENY" ]      # quoting is a spelling, not a defence
  [ "$(decision 'rm -rf -- /')" = "DENY" ]         # `--` ends the flags, it does not end the rule
  [ "$(decision 'rm -vrf /')" = "DENY" ]           # company in the bundle is irrelevant
}

@test "text is NOT execution: a message describing the rule stays writable" {
  # The guard must not repeat, in its own detector, the defect it exists to stop. A commit
  # describing this very fix has to be committable — the old regex denied exactly that.
  [ "$(decision 'git commit -m "fix(hooks): rm --recursive --force / must deny"')" = "PASS" ]
  [ "$(decision "git commit -m 'fix: rm -rf ~ and rm -rf \$HOME both blocked'")" = "PASS" ]
  [ "$(decision 'echo "never run rm -rf /"')" = "PASS" ]
}

@test "REACH unchanged: this fix moves spellings, never which targets count" {
  # A guard that quietly grew its blast radius would be a different change wearing this one's name.
  # /etc and /usr were `ask` before and stay `ask` — only the spellings that reach that verdict grew.
  [ "$(decision 'rm -rf /etc')" = "ASK" ]
  [ "$(decision 'rm -Rf /etc')" = "ASK" ]
  [ "$(decision 'rm --recursive --force /etc')" = "ASK" ]
  [ "$(decision 'rm -rf /usr/local/foo')" = "ASK" ]
  [ "$(decision 'rm -rf node_modules')" = "PASS" ]
  [ "$(decision 'rm -rf .next')" = "PASS" ]
  [ "$(decision 'rm -rf node_modules dist')" = "PASS" ]
  [ "$(decision 'rm src/foo.txt')" = "PASS" ]
}

@test "every target is judged, not just the first one after the flags" {
  # The old warn clause extracted ONE target per occurrence, so a safe first target hid the rest.
  [ "$(decision 'rm -rf node_modules /etc')" = "ASK" ]
  [ "$(decision 'rm -rf src && rm -rf node_modules')" = "ASK" ]
}

# ════ the fallbacks — a rollback of the PARSER, never a re-opening of the bypass ════════════════

@test "fallback: VALIDATE_BASH_LEGACY=1 still denies the whole corpus" {
  local c out n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$c" \
          | VALIDATE_BASH_LEGACY=1 bash "$HOOK" 2>/dev/null)"
    printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || { echo "  legacy MISSED: $c" >&2; n=$((n+1)); }
  done < <(catastrophic_corpus)
  [ "$total" -eq 13 ]        # positive control on the DENOMINATOR: 0 misses of 0 cases is not a pass
  [ "$n" -eq 0 ]
}

@test "fallback: with python3 ABSENT the corpus still denies, and the degradation is logged" {
  # An UNCLEAR that leaves no trace is the silent-degradation shape. It does not fail open here —
  # text matching still denies — but it also over-blocks message bodies, so when an operator asks
  # why a commit message was refused, that log line is the answer.
  local bin="$BATS_TEST_TMPDIR/nopy"; mkdir -p "$bin"
  local t p
  # `dirname` belongs on this list and its absence is the reason this test is written the way it
  # is: without it the hook's `LIB_DIR="$(cd "$(dirname …)" && pwd)/lib"` resolves nowhere, the lib
  # is never sourced, and the run degrades via a DIFFERENT door (no lib at all) while still
  # denying — so the deny assertions passed while the thing under test never executed. Remove ONE
  # tool from a restricted-PATH fixture and you are testing a different failure than you named.
  for t in jq grep sed date mkdir cat tr cut bash dirname basename; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$bin/$t"
  done
  [ ! -e "$bin/python3" ] || false          # the control's own precondition: it really is absent
  [ -x "$bin/jq" ] || false                 # …and the hook has not been crippled some other way
  [ -x "$bin/dirname" ] || false            # …and the lib IS reachable, so python3 is the only loss

  local c payload out n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    # The payload is built OUTSIDE the restricted PATH, so the harness does not depend on the
    # very thing it is removing.
    payload="$(jq -nc --arg c "$c" '{tool_input:{command:$c}}')"
    out="$(printf '%s' "$payload" | env -i HOME="$HOME" PATH="$bin" bash "$HOOK" 2>/dev/null)"
    printf '%s' "$out" | grep -q '"permissionDecision": "deny"' || { echo "  nopy MISSED: $c" >&2; n=$((n+1)); }
  done < <(catastrophic_corpus)
  [ "$total" -eq 13 ]        # positive control on the DENOMINATOR (see not_denied_count)
  [ "$n" -eq 0 ]
  # …and the degraded path is the one that ran, evidenced by its own log line rather than inferred
  # from the verdict (which the legacy text matcher would have produced either way).
  grep -q 'rm-argv-scan-UNCLEAR(python3-absent)' "$HOME/.claude/logs/validate-bash-unclear.log" || false
}

@test "fallback: an unparseable command is UNCLEAR, and says so rather than passing silently" {
  # Unbalanced quotes → shlex ValueError → the caller must fall back, never read an empty scan as
  # "nothing found" (that is the fail-open shape).
  run decision 'rm -rf "unclosed'
  [ "$status" -eq 0 ]
  grep -q 'rm-argv-scan-UNCLEAR(unparseable)' "$HOME/.claude/logs/validate-bash-unclear.log" || false
}

# ════ the RED control ═══════════════════════════════════════════════════════════════════════════

@test "RED control: the corpus CONVICTS the shipped pre-fix hook (recovered from git, not approximated)" {
  # A control that hand-writes an "old-looking" regex proves nothing about what actually shipped —
  # it passes vacuously against an artifact nobody ever ran (memory: control-must-replay-the-real-
  # artifact). So: walk this path's history newest-first, take the last version that still carries
  # the hardcoded `-rf` bundle, recover its SIBLING lib from the same commit, and run the real pair.
  local mark='rm[[:space:]]+-rf[[:space:]]+/'
  local sha="" s
  for s in $(git -C "$REPO" rev-list --all -- hooks/validate-bash.sh); do
    if git -C "$REPO" show "$s:hooks/validate-bash.sh" 2>/dev/null | grep -qF "$mark"; then sha="$s"; break; fi
  done
  [ -n "$sha" ] || { echo "no pre-fix version in history — this control cannot run, and a silent skip would be a fake pass"; false; }

  local old="$BATS_TEST_TMPDIR/old"
  mkdir -p "$old/lib"
  git -C "$REPO" show "$sha:hooks/validate-bash.sh"    > "$old/validate-bash.sh"
  git -C "$REPO" show "$sha:hooks/lib/is-true-flag.sh" > "$old/lib/is-true-flag.sh"
  [ -s "$old/validate-bash.sh" ] || false
  [ -s "$old/lib/is-true-flag.sh" ] || false           # without it the old hook silently runs in
                                                       # legacy mode — a different artifact again

  local missed total
  read -r missed total < <(not_denied_count "$old/validate-bash.sh" 2>/dev/null)
  echo "pre-fix $(git -C "$REPO" log -1 --format=%h "$sha"): $missed/$total spellings NOT denied"
  [ "$total" -eq 13 ]
  # The number is the finding's own: 11 of 13 got through, and only `rm -rf /*` and `rm -rf ~/`
  # (the two shapes the hardcoded regex was written around) were denied. Asserted EXACTLY, not
  # `>0`: if a corpus line is ever added or reworded, this number moves and forces a look at
  # whether the new line is really part of the class the finding measured.
  [ "$missed" -eq 11 ]
}

# ════ the orphaned matrix, brought under the gate ═══════════════════════════════════════════════

@test "the hooks/tests decision matrix passes (86 cases, none of which the gate could see before)" {
  # hooks/tests/validate-bash.test.sh is the SSOT decision matrix for this hook — false positives,
  # true positives, ask cases, silent no-ops, edge cases. The land gate runs `tests/*.bats` and
  # nothing else, so those 60 assertions have never blocked a land: detection, not a gate
  # (memory: enforcement-must-live-at-the-chokepoint). One line fixes that, and it is the natural
  # regression net for exactly this change.
  run bash "$REPO/hooks/tests/validate-bash.test.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'PASSED' || false
}
