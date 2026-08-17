#!/usr/bin/env bats
# The FORCE-ADD contract: `git add --force` is ONE rule about ONE invocation, and neither the way
# the flag is spelled nor what else shares the command line may decide whether it is enforced.
#
# WHAT HAPPENED (backlog 44750ff72ae7 — reproduced by execution, not inference). The rule was two
# independent tests ANDed together: "a real `-f`/`--force` argv token SOMEWHERE in $CMD" and "the
# text `git add` SOMEWHERE in $CMD". A command string is not one invocation, so the two halves were
# never tied to the same clause, and the guard failed in BOTH directions at once. Feeding the
# SHIPPED hook (recovered from git below, not approximated) and reading the emitted decision:
#
#   too STRONG — innocent commands refused, with a reason naming what they do not do:
#     rm -f f.txt && echo x > f.txt && git add f.txt   deny "git add -f blocked"   ← the -f is rm's
#     grep -f pats.txt in.txt && git add out.txt       deny
#     git add out.txt && rsync -f rules a b            deny
#     git ls-files | xargs grep -f p; git add .        deny
#   too WEAK — the force-add the rule exists to stop, in 8 of 14 real spellings:
#     git add -fv ignored.bin        PASS   ← same flag, company in the bundle
#     git add -Af node_modules       PASS
#     git add --forc ignored.bin     PASS   ← parse-options takes any unambiguous abbreviation
#     git -C /tmp/x add -f x         PASS   ← `add` is not argv[1] once git has a global option
#     git stage -f ignored.bin       PASS   ← `stage` is git's own synonym for `add`
#     bash -c 'git add -f x'         PASS
#
# The too-strong half is how it was found: a plain `git add f.txt` in a throwaway fixture repo was
# DENIED mid-investigation, because the line that made the fixture began `rm -f f.txt`. That
# innocent command is pinned below as a control — the fix is only half tested without it, and the
# defect class this repeats (memory: denylist-enumerates-spellings-not-the-class) was first
# recorded on a guard that let 11 of 13 rm spellings past while refusing its own fix commit.
#
# Both halves are the same defect and get the same answer as rm_argv_scan's: TOKENIZE, find the
# invocation, and read the flag off ITS argv (hooks/lib/is-true-flag.sh :: git_add_force_scan).
#
# Assertions use `|| false` where they are non-final: a bare `[[ ]]` / `!` / `A && B` is
# errexit-EXEMPT in bats and would be a DEAD assertion (memory: bats-dead-assertions).

setup() {
  # HERMETIC $HOME — the hook's last act appends to ~/.claude/logs, and the UNCLEAR log asserted
  # below lands there too. Unfixtured, every probe here would append to the OPERATOR'S live log.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
}

# ── the two corpora ─────────────────────────────────────────────────────────────────────────────
# One list each, shared by every consumer below (argv path, fallbacks, RED control). Per-test
# copies would drift and quietly stop testing the same thing.

force_corpus() {   # every one of these IS a force-add and MUST be denied
  cat <<'CORPUS'
git add -f ignored.bin
git add --force build/
git add -fv ignored.bin
git add -Af node_modules
git add -vf secret.env
git add ignored.bin -f
git add --forc ignored.bin
git -C /tmp/x add -f ignored.bin
git -c core.pager=cat add --force ignored.bin
git stage -f ignored.bin
sudo git add -f ignored.bin
xargs git add -f
bash -c 'git add -f ignored.bin'
cd /repo && git add -f .env
CORPUS
}

innocent_corpus() {  # none of these force-adds anything, and none may be denied
  cat <<'CORPUS'
git add f.txt
rm -f f.txt && echo x > f.txt && git add f.txt
grep -f pats.txt in.txt && git add out.txt
git add out.txt && rsync -f rules a b
git ls-files | xargs grep -f p; git add .
git add -- -f.txt
git add -A
git commit -m "git add -f is blocked by the hook"
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

# not_denied_count <hook> → "<missed> <total>"; false_deny_count <hook> → "<wrong> <total>".
# The TOTAL is returned, never assumed: a "0 missed" read off a loop that never ran is the vacuous
# pass this file exists to avoid (memory: exact-count-assertion-tripwires-its-own-subject is about
# the opposite failure — here the denominator is the guard). Offenders are NAMED on stderr, so a
# red reads as "these spellings got through" rather than as a bare number.
not_denied_count() {
  local hook="$1" c d n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    d="$(decide_with "$hook" "$c")"
    if [ "$d" != "DENY" ]; then n=$((n+1)); echo "  NOT DENIED ($d): $c" >&2; fi
  done < <(force_corpus)
  printf '%s %s\n' "$n" "$total"
}

false_deny_count() {
  local hook="$1" c d n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    d="$(decide_with "$hook" "$c")"
    if [ "$d" = "DENY" ]; then n=$((n+1)); echo "  FALSELY DENIED: $c" >&2; fi
  done < <(innocent_corpus)
  printf '%s %s\n' "$n" "$total"
}

# ════ the rule ══════════════════════════════════════════════════════════════════════════════════

@test "every spelling of a force-add is DENIED" {
  local missed total
  read -r missed total < <(not_denied_count "$HOOK")
  [ "$total" -eq 14 ]
  [ "$missed" -eq 0 ]
}

@test "an innocent git add is NOT denied, whatever else shares the command line" {
  # The control the backlog row asks for by name. `git add f.txt` is the reported symptom and the
  # rest are the same defect with the sibling clause made explicit — without these, half the fix
  # (the too-strong half) is untested and could be "fixed" by denying even more.
  local wrong total
  read -r wrong total < <(false_deny_count "$HOOK")
  [ "$total" -eq 8 ]
  [ "$wrong" -eq 0 ]
}

@test "the invocation is found wherever it really is, not only at argv[0]" {
  [ "$(decision 'sudo git add -f x')" = "DENY" ]
  [ "$(decision 'env GIT_DIR=.git git add -f x')" = "DENY" ]
  [ "$(decision '/usr/bin/git add -f x')" = "DENY" ]
  [ "$(decision 'xargs git add -f')" = "DENY" ]
  [ "$(decision "bash -c 'git add -f x'")" = "DENY" ]
  [ "$(decision 'eval git add -f x')" = "DENY" ]
}

@test "git's own global options do not hide the subcommand" {
  # `add` stops being argv[1] the moment git carries -C/-c/--git-dir, and the old head-anchored
  # text match lost the invocation entirely — the shape an agent reaches for FIRST in a worktree.
  [ "$(decision 'git -C /tmp/x add -f x')" = "DENY" ]
  [ "$(decision 'git --git-dir=/tmp/x/.git add -f x')" = "DENY" ]
  [ "$(decision 'git -c core.pager=cat add --force x')" = "DENY" ]
  [ "$(decision 'git --no-pager add -f x')" = "DENY" ]
}

@test "the same flag spelled differently is the same flag" {
  [ "$(decision 'git add -fv x')" = "DENY" ]        # company in the bundle is irrelevant
  [ "$(decision 'git add -Af x')" = "DENY" ]        # …and so is its position in the bundle
  [ "$(decision 'git add x -f')" = "DENY" ]         # flags may follow the pathspec
  [ "$(decision 'git add --forc x')" = "DENY" ]     # unambiguous abbreviation: parse-options takes it
  [ "$(decision 'git add --f x')" = "DENY" ]        # --force is git add's only long option in f
  [ "$(decision 'git stage -f x')" = "DENY" ]       # `stage` is a spelling of `add`, not a bypass
}

@test "REACH unchanged: this fix moves spellings, never which command counts" {
  # A guard that quietly grew its blast radius would be a different change wearing this one's name.
  [ "$(decision 'git add -- -f.txt')" = "PASS" ]    # after `--` it is a pathname, not a flag
  [ "$(decision 'git add --no-force x')" = "PASS" ] # the auto-generated negation is not --force
  [ "$(decision 'git add -A')" = "PASS" ]
  [ "$(decision 'git add .')" = "PASS" ]
  [ "$(decision 'git commit -f')" = "PASS" ]        # a -f on some OTHER git subcommand is not this rule
  [ "$(decision 'git clean -f x')" = "PASS" ]
}

@test "text is NOT execution: a message describing the rule stays writable" {
  # The guard must not repeat, in its own detector, the defect it exists to stop. A commit
  # describing this very fix has to be committable.
  [ "$(decision 'git commit -m "fix(hooks): git add -f must deny every spelling"')" = "PASS" ]
  [ "$(decision 'echo "never run git add -f on a gitignored path"')" = "PASS" ]
}

@test "the deny NAMES the token it read, so an over-block is diagnosable" {
  # The pre-fix message asserted `-f` for a command whose -f belonged to another program, which is
  # what made the false positive unreadable to the agent that hit it.
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' 'git add -Af node_modules' \
        | bash "$HOOK" 2>/dev/null)"
  printf '%s' "$out" | grep -q '\-Af' || false
  printf '%s' "$out" | grep -q 'gitignore' || false
}

# ════ the fallbacks — a rollback of the PARSER, never a re-opening of the bypass ════════════════

@test "fallback: python3 ABSENT still denies everything the pre-fix hook denied, and logs the degradation" {
  # The safety property for a degraded path is not "as good as the fix" — text matching cannot be —
  # it is "never weaker than what shipped". Measured against the recovered pre-fix artifact, so it
  # cannot go vacuous if the corpus grows.
  local bin="$BATS_TEST_TMPDIR/nopy"; mkdir -p "$bin"
  local t p
  # `dirname` is on this list deliberately: without it the hook's LIB_DIR resolves nowhere, the lib
  # is never sourced, and the run degrades through a DIFFERENT door while still denying — testing a
  # failure other than the one named (memory: rm-argv-normalize's nopy control).
  for t in jq grep sed date mkdir cat tr cut bash dirname basename; do
    p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$bin/$t"
  done
  [ ! -e "$bin/python3" ] || false          # the control's own precondition: it really is absent
  [ -x "$bin/jq" ] || false
  [ -x "$bin/dirname" ] || false            # …and the lib IS reachable, so python3 is the only loss

  local old; old="$(prefix_hook_dir)"
  local c payload out nopy pre n=0 total=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    total=$((total+1))
    pre="$(decide_with "$old/validate-bash.sh" "$c")"
    [ "$pre" = "DENY" ] || continue         # only the pre-fix denials are the floor
    payload="$(jq -nc --arg c "$c" '{tool_input:{command:$c}}')"
    out="$(printf '%s' "$payload" | env -i HOME="$HOME" PATH="$bin" bash "$HOOK" 2>/dev/null)"
    printf '%s' "$out" | grep -q '"permissionDecision": "deny"' \
      || { echo "  nopy RE-OPENED: $c" >&2; n=$((n+1)); }
  done < <(force_corpus)
  [ "$total" -eq 14 ]        # positive control on the DENOMINATOR: 0 of 0 is not a pass
  [ "$n" -eq 0 ]
  # …and the degraded path is the one that ran, evidenced by its own log line rather than inferred
  # from the verdict (which the text matcher would have produced either way).
  grep -q 'git-add-force-scan-UNCLEAR(python3-absent)' "$HOME/.claude/logs/validate-bash-unclear.log" || false
}

@test "fallback: the innocent control survives EVERY mode, including both rollbacks" {
  # `git add f.txt` carries no -f substring at all, so no layer of any mode has an excuse to
  # convict it. This is the one assertion that must hold whatever else is broken.
  [ "$(decision 'git add f.txt')" = "PASS" ]
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' 'git add f.txt' \
        | VALIDATE_BASH_LEGACY=1 bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ] || false
}

@test "fallback: an unparseable command is UNCLEAR, and says so rather than passing silently" {
  # Unbalanced quotes → shlex ValueError → the caller must fall back, never read an empty scan as
  # "nothing found" (that is the fail-open shape).
  run decision 'git add -f "unclosed'
  [ "$status" -eq 0 ]
  grep -q 'git-add-force-scan-UNCLEAR(unparseable)' "$HOME/.claude/logs/validate-bash-unclear.log" || false
}

# ════ the RED control ═══════════════════════════════════════════════════════════════════════════

# prefix_hook_dir → a directory holding the last SHIPPED pre-fix hook and its SIBLING lib from the
# same commit. A control that hand-writes an "old-looking" rule proves nothing about what actually
# shipped (memory: control-must-replay-the-real-artifact). The marker pair is exact: the old
# two-condition rule PRESENT and the argv scanner ABSENT — matching on the old rule alone would
# also match the current hook, whose fallback still carries those very lines, and the control would
# then replay itself and pass vacuously.
prefix_hook_dir() {
  local sha="" s
  for s in $(git -C "$REPO" rev-list --all -- hooks/validate-bash.sh); do
    git -C "$REPO" show "$s:hooks/validate-bash.sh" 2>/dev/null \
      | grep -qF 'check_real_flag "-f" && echo "$CMD" | grep -qE' || continue
    git -C "$REPO" show "$s:hooks/validate-bash.sh" 2>/dev/null \
      | grep -qF 'git_add_force_scan' && continue
    sha="$s"; break
  done
  [ -n "$sha" ] || { echo "no pre-fix version in history — this control cannot run, and a silent skip would be a fake pass" >&2; return 1; }
  local old="$BATS_TEST_TMPDIR/prefix"
  mkdir -p "$old/lib"
  git -C "$REPO" show "$sha:hooks/validate-bash.sh"    > "$old/validate-bash.sh"
  git -C "$REPO" show "$sha:hooks/lib/is-true-flag.sh" > "$old/lib/is-true-flag.sh"
  [ -s "$old/validate-bash.sh" ] || return 1
  [ -s "$old/lib/is-true-flag.sh" ] || return 1   # without it the old hook silently runs in legacy
                                                  # mode — a different artifact again
  printf '%s' "$old"
}

@test "RED control: both corpora CONVICT the shipped pre-fix hook (recovered from git, not approximated)" {
  local old; old="$(prefix_hook_dir)"
  [ -n "$old" ] || false

  local missed total wrong wtotal
  read -r missed total < <(not_denied_count "$old/validate-bash.sh" 2>/dev/null)
  read -r wrong wtotal < <(false_deny_count "$old/validate-bash.sh" 2>/dev/null)
  echo "pre-fix: $missed/$total force spellings NOT denied · $wrong/$wtotal innocent commands DENIED"
  [ "$total" -eq 14 ]
  [ "$wtotal" -eq 8 ]
  # Both numbers asserted EXACTLY, not `>0`: if a corpus line is added or reworded these move, and
  # that forces a look at whether the new line really belongs to the class that was measured.
  [ "$missed" -eq 8 ]
  [ "$wrong" -eq 4 ]
}

@test "the hooks/tests decision matrix passes" {
  # hooks/tests/validate-bash.test.sh is the SSOT decision matrix for this hook. The land gate runs
  # tests/*.bats and nothing else, so it reaches the matrix only through a line like this one
  # (memory: enforcement-must-live-at-the-chokepoint).
  run bash "$REPO/hooks/tests/validate-bash.test.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'PASSED' || false
}
