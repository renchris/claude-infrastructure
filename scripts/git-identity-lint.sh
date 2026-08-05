#!/bin/bash
# git-identity-lint — a RATCHET on git IDENTITY writes that can escape their fixture.
#
# WHY: `git -C ""` is a documented NO-OP. It does not change directory and it does not error —
# verified live on git 2.54.0, a `git -C "" config user.email PROBE@probe` run from inside a repo
# writes to THAT repo. So the fixture shape `git -C "$dir" config user.email t@t`, evaluated with
# `$dir` empty (an unset positional, a failed mktemp, a helper called with no argument), writes the
# TEST identity into whatever repo the process happens to be standing in.
#
# WHY THAT IS FLEET-WIDE AND NOT LOCAL: claude-infrastructure is one repo with ~100 linked
# worktrees, and every one of them shares a single .git/config. One such call therefore re-authors
# every session on the machine, not just the one that ran it. It happened: 9 commits on this trunk
# and 214 on reso-management-app are authored `t <t@t>`. Evidence:
# docs/research/git-identity-leak-2026-08-05.md.
#
# RULE 1 (the bare -C): an identity write — `git … config … user.email` / `user.name` — whose `-C`
# argument is a BARE expansion is a violation. Bare means the whole argument is nothing but a
# parameter expansion (`"$1"`, `$dir`, `"${d}"`) or the empty string (`""`), so there is no token in
# it that can make the argument non-empty. ACCEPTED, because each carries such a token: a guarded
# expansion (`"${1:?}"`, `"${d:-/some/path}"`), a literal path, and an expansion with a literal
# suffix (`"$d/repo"` — the suffix alone makes the argument non-empty, so the worst case is a write
# to `/repo`, not to the caller's cwd).
#
# RULE 2 (the implicit cwd): an identity write with NO `-C` at all, preceded in the same region by
# an UNGUARDED `cd` to an expansion. Same failure with the seam moved — the fixture's own `cd` is
# what was supposed to put the write inside the fixture repo, so a `cd` that silently did not happen
# leaves the write pointed at the caller's cwd. Guarded means the `cd` is `||`-chained (`|| exit`,
# `|| return`) or `&&`-chained to the work that follows; anything else is a `cd` whose failure is
# discarded. A write with no `-C` and no preceding `cd` is OUT OF SCOPE and never flagged — that
# scoping is what stops rule 2 firing on every `git config` in the tree, which would pass every RED
# assertion while proving nothing.
#
# ACCEPTED FLOOR, stated rather than hidden. The scan is TEXTUAL and per-line, and the region rule 2
# tracks is delimited heuristically — a `@test` / function opener or a closing `}`/`)` at the start
# of a line resets it. A `cd` and a write separated by some other block shape are not paired. This
# is the same floor every ratchet in this tree takes: it binds where the evidence is plain, and the
# suite (tests/git-identity-lint.bats) is what proves it still discriminates.
#
# SELF-EXCLUSION: this script and its suite carry the leaky shapes as fixtures and as prose by
# construction, so scanning them could only ever produce a self-report. Same self-exclusion
# scripts/utc-stamp-lint.sh takes, and for the same reason.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan root (LOUD, never silent-green)
#
# Env seams (selftest / escape hatch):
#   CC_GITID_ALLOWLIST  overrides the embedded grandfather list (set-but-empty = grandfather nothing)
#   CC_GITID_OWN        own-scope set (see in_own); UNSET = strict whole-tree blocking
#
# `set -uo pipefail`, NOT `-e`: every predicate here answers by EXIT CODE, so errexit would abort the
# run on the first honest "no" instead of letting it be read. Same shape as scripts/test-hermeticity-lint.sh.
set -uo pipefail

# Resolve $0 THROUGH symlinks before deriving ROOT. Everything under ~/.claude/scripts/ is a per-file
# symlink into this checkout, so a bare `dirname "$0"` yields ~/.claude — which has no tests/ — and a
# run through the live layer then fails for a reason that has nothing to do with the ratchet
# (scripts/test-hermeticity-lint.sh:113 records the same scar). No `readlink -f`: GNU-only, and this
# box ships the BSD userland.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the ratchet: files grandfathered as carrying an escaping identity write. Matched by BASENAME.
# ONLY EVER DELETE LINES FROM THIS LIST.
#
# SHIPS EMPTY, and that is a decision rather than a measurement of a clean tree: the ~19 offending
# corpus sites are being fixed on a SIBLING branch at the same time as this lands, so any list read
# here would be stale before the merge — the failure mode rules 2-4 of test-hermeticity-lint each
# record. An empty list is also the only list that cannot decay into a permanent exemption: a NEW
# identity write is one that can name a guarded path from the start.
EMBEDDED_ALLOWLIST=""

ALLOW="${CC_GITID_ALLOWLIST-$EMBEDDED_ALLOWLIST}"

# Files whose CONTENT is fixtures of the very shape being linted (see SELF-EXCLUSION above).
SELF_EXCLUDE="git-identity-lint.sh
git-identity-lint.bats"

# ── the scanner. One awk pass per file, emitting "<lineno><TAB><RULE><TAB><excerpt>" per violation.
#
# COMMENT-STRIPPED, for the reason test-hermeticity-lint's setup_statements() records: a predicate
# must key on what a file DOES, never on what it says about itself. Rules 2, 3 and 4 there each
# shipped VACUOUS on exactly the prose-match shape before that was fixed, so this one starts with it.
# `read -r -d ''`, NOT `$(cat <<'AWK' … AWK)`. This box's /bin/bash is 3.2, whose `$( )` parser
# counts parentheses across the heredoc body before the heredoc is honoured — and the cd pattern
# below carries a `(` inside a BRACKET EXPRESSION, which reads to that parser as unbalanced and dies
# with a syntax error 40 lines from anything it names. `read` never enters that path. (The sibling
# lint's `$(cat <<'ALLOW')` is fine only because a list of file names contains no parens.)
# `|| true`: read returns 1 when it hits EOF without finding the NUL delimiter, which is every time.
IFS= read -r -d '' GITID_AWK <<'AWK' || true
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
{
  line = $0
  sub(/[[:space:]]+#.*$/, "", line)          # trailing comment
  sub(/^[[:space:]]*#.*$/, "", line)         # whole-line comment

  # REGION RESET — a new @test/function opener, or a closing brace/paren at the head of a line, ends
  # whatever region an unguarded cd was recorded in. See the ACCEPTED FLOOR note in the header.
  if (line ~ /^[[:space:]]*(@test|[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\))/) { cdline = 0; split("", proven) }
  if (line ~ /^[[:space:]]*[})]/) { cdline = 0; split("", proven) }

  # ── PROOF TRACKING (rule 1) ───────────────────────────────────────────────────────────────────
  # A variable the shell has already proven non-empty is NOT a bare expansion: `${x:?…}` aborts
  # before any git call when x is empty, so a later `git -C "$x"` can never degrade to the no-op.
  # Without this, the lint convicts the very remedy its own message prescribes — the fix belongs on
  # the BINDING (once, where the path enters) and demanding it at each use site is noise, not safety.
  #
  # Keyed by VARIABLE NAME and cleared at every region boundary above. Deliberately NOT "does this
  # file contain a ${…:?} anywhere": that file-level shape would clean a file whose guard governs a
  # DIFFERENT variable, which is the vacuous-pass trap the header already records for rules 2-4.
  # `split("", proven)` rather than `delete proven` — this box's awk is BWK, not gawk.
  if (match(line, /^[[:space:]]*:[[:space:]]+"?\$\{[A-Za-z0-9_]+:\?/)) {         # : "${1:?msg}"
    seg = substr(line, RSTART, RLENGTH); gsub(/^.*\$\{|:\?$/, "", seg); if (seg != "") proven[seg] = 1
  }
  if (match(line, /(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{[A-Za-z0-9_]+:\?/)) {
    seg = substr(line, RSTART, RLENGTH)                                           # local r="${1:?msg}"
    lhs = seg; sub(/^local[[:space:]]+/, "", lhs); sub(/=.*$/, "", lhs); if (lhs != "") proven[lhs] = 1
    rhs = seg; gsub(/^.*\$\{|:\?$/, "", rhs);                          if (rhs != "") proven[rhs] = 1
  }
  if (match(line, /(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="\$\{?[A-Za-z0-9_]+\}?\/[^"]+"/)) {
    seg = substr(line, RSTART, RLENGTH)                                           # repo="$d/repo"
    lhs = seg; sub(/^local[[:space:]]+/, "", lhs); sub(/=.*$/, "", lhs); if (lhs != "") proven[lhs] = 1
  }

  # An UNGUARDED cd to an expansion: no ||-chain, no &&-chain, so its failure is discarded.
  if (line ~ /(^|[[:space:];&|(])cd[[:space:]]+(--[[:space:]]+)?"?\$/ && line !~ /\|\|/ && line !~ /&&/)
    cdline = NR

  if (line !~ /git[[:space:]]/) next
  if (line !~ /config/) next
  if (line !~ /user\.(email|name)/) next

  if (match(line, /(^|[[:space:]])-C[[:space:]]+[^[:space:]]+/)) {
    arg = substr(line, RSTART, RLENGTH)
    sub(/^[[:space:]]*-C[[:space:]]+/, "", arg)
    gsub(/^["']|["']$/, "", arg)
    # BARE = the whole argument is one expansion, or the empty string. Nothing in it can make the
    # argument non-empty, so `git -C` degrades to a no-op and the write lands in the caller's cwd.
    name = arg; gsub(/^\$\{?|\}$/, "", name)     # $1 / ${1} / $r / ${r} → the bare variable name
    if ((arg == "" || arg ~ /^\$[0-9]+$/ || arg ~ /^\$[A-Za-z_][A-Za-z0-9_]*$/ ||
         arg ~ /^\$\{[0-9]+\}$/ || arg ~ /^\$\{[A-Za-z_][A-Za-z0-9_]*\}$/) &&
        !(name in proven))
      printf "%d\tBARE-C\t%s\n", NR, trim(line)
  } else if (cdline > 0) {
    printf "%d\tAFTER-CD\t%s\n", NR, trim(line)
  }
}
AWK

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────
# Inherited wholesale from scripts/test-hermeticity-lint.sh, whose header records what it cost to
# learn: a predicate that could not RUN (fork exhaustion on a loaded box) was indistinguishable from
# a real answer, so the ratchet FABRICATED violations naming clean files — worse than a bare
# non-verdict, because the message names files and reads as an attributable RED. Three tries, 1s
# apart (the scan is pure and cheap, so re-running it is free), then the whole run is condemned to
# exit 2 rather than reporting anything.
CHECK_FAILED=0

# scan_file <path> — prints the violation records; 0 records is an ANSWER, not a failure.
#
# A FAILED scan is reported IN BAND, as the single record SCAN_SENTINEL, and NOT by setting
# CHECK_FAILED here. It has to be: every caller reads this through `$( )`, so an assignment made in
# this function happens in a SUBSHELL and is discarded — the flag would read 0 in the parent and an
# unrunnable scan would exit 0, silent-green, which is the exact conflation the third state exists
# to prevent. Caught by case (h), which is why that assertion checks the EXIT CODE and not just the
# absence of a violation line.
SCAN_SENTINEL='!SCAN-FAILED'
scan_file() {
  local out rc
  for _ in 1 2 3; do
    out="$(awk "$GITID_AWK" "$1" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
    sleep 1                       # transient fork pressure — see the block above
  done
  echo "git-identity-lint: ⛔ scan could not RUN for $1 after 3 tries (awk rc=$rc)" >&2
  printf '%s\n' "$SCAN_SENTINEL"  # fail-SAFE: a non-verdict, never a fabricated violation
}

# 0 = present · 1 = absent. Fail-SAFE = present ('grandfathered' cannot fabricate a violation).
in_allowlist() {
  local rc
  for _ in 1 2 3; do
    printf '%s\n' "$2" | grep -qxF "$1"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1
  done
  CHECK_FAILED=1
  echo "git-identity-lint: ⛔ allowlist check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0
}

# OWN-SCOPE — which violations may BLOCK, as distinct from which are REPORTED. Identical contract to
# test-hermeticity-lint's in_own(), including the THREE states `${VAR:-}` cannot express: an own-set
# that is ABSENT means "strict, judge the whole tree" (the postland net, a bare human run); an
# own-set that is PRESENT BUT EMPTY means "this land changes nothing in scope", so NOTHING may block.
# Presence is carried by ARGUMENT COUNT here and by `${CC_GITID_OWN+set}` at the entrypoint.
in_own() {  # $1=basename · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  printf '%s\n' "$2" | sed 's:.*/::' | grep -qxF "$1"
}

why_of() {  # $1=rule token → the human sentence
  case "$1" in
    BARE-C)   echo 'git -C takes a BARE expansion — empty ⇒ a NO-OP, and the identity lands in the caller'"'"'s repo' ;;
    AFTER-CD) echo 'an identity write with no -C, after an UNGUARDED cd — a failed cd leaves it in the caller'"'"'s repo' ;;
    *)        echo 'escaping identity write' ;;
  esac
}

# lint_tree <repo-root> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable root
lint_tree() {
  local root="$1" allow="$2" own="${3:-}" own_scoped=0
  local f base rel seen=0 bad=0 stuck=0 other=0 records n
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "git-identity-lint: ⛔ not a directory: $root" >&2; return 2; }
  for f in "$root"/tests/*.bats "$root"/scripts/*.sh "$root"/bin/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    in_allowlist "$base" "$SELF_EXCLUDE" && continue
    rel="${f#"$root"/}"
    seen=$((seen + 1))
    records="$(scan_file "$f")"
    if [ "$records" = "$SCAN_SENTINEL" ]; then CHECK_FAILED=1; continue; fi
    n="$(printf '%s' "$records" | grep -c . )"
    if [ "$n" -eq 0 ]; then
      if in_allowlist "$base" "$allow"; then
        if in_own "$base" "$own" "$own_scoped"; then
          printf '  RATCHET  %s writes no escaping identity now — delete its allowlist line\n' "$base"
          stuck=$((stuck + 1))
        else
          printf '  ratchet? %s is clean but still grandfathered (NOT in your diff — advisory)\n' "$base"
          other=$((other + 1))
        fi
      fi
      continue
    fi
    in_allowlist "$base" "$allow" && continue
    while IFS="$(printf '\t')" read -r lineno rule excerpt; do
      [ -n "$lineno" ] || continue
      if in_own "$base" "$own" "$own_scoped"; then
        printf '  IDENTITY %s:%s: %s\n' "$rel" "$lineno" "$(why_of "$rule")"
        printf '           %s\n' "$excerpt"
        bad=$((bad + 1))
      else
        printf '  identity? %s:%s: %s (NOT in your diff — advisory, not blocking)\n' "$rel" "$lineno" "$(why_of "$rule")"
        other=$((other + 1))
      fi
    done <<EOF
$records
EOF
  done
  [ "$seen" -gt 0 ] || { echo "git-identity-lint: ⛔ nothing to scan under $root (no tests/, scripts/ or bin/)" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "git-identity-lint: $other pre-existing violation(s) NOT in your diff — reported, not blocking (own-scope)."
  # Checked AFTER the own-scope report, for lint_dir's reason: own-scope narrows WHICH violations
  # block, it does not make an unrunnable scan trustworthy.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "git-identity-lint: ⛔ UNUSABLE — a scan failed to run (see above); no verdict." >&2
    echo "  This is NOT a violation report. Re-run when the box is quieter; do not 'fix' any file on it." >&2
    return 2
  fi

  if [ "$bad" -gt 0 ]; then
    echo "git-identity-lint: ⛔ $bad escaping git-identity write(s) above."
    echo "  WHY: \`git -C \"\"\` is a NO-OP, so an empty path writes user.email/user.name into whatever repo"
    echo "       the process is standing in — and ~100 worktrees here share ONE .git/config, so one such"
    echo "       call re-authors every session on the box (9 commits on trunk, 214 on reso)."
    echo "  Fix: guard the path — \`git -C \"\${1:?repo path required}\" config …\` — or give it a literal"
    echo "       suffix (\"\$d/repo\"). For the no-\`-C\` shape, chain the cd: \`cd \"\$d\" || return 1\`."
    echo "       Do NOT add to the allowlist — it ships empty and is meant to stay that way."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "git-identity-lint: ⛔ $stuck file(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "git-identity-lint: clean — $seen file(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 escaping identity writes."
  return 0
}

# ── --selftest: PROVE the RED paths fire and the GREEN paths don't, each RED paired with the GREEN
# that shows it fired for its OWN reason (harness law: every assertion traps).
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d "${TMPDIR:-/tmp}/git-identity-lint-selftest.XXXXXX")"; trap 'rm -rf "$d"' EXIT
  fails=0

  mk() { mkdir -p "$d/$1/tests"; cat >"$d/$1/tests/zz-fixture.bats"; }

  # ── RULE 1 fixtures. Every one is identical but for the -C ARGUMENT, so a rule-1 verdict can only
  # be about that argument.
  mk bare_var <<'F'
@test "x" {
  git -C "$dir" config user.email t@t
}
F
  mk bare_pos <<'F'
@test "x" {
  git -C "$1" config user.name t
}
F
  mk bare_empty <<'F'
@test "x" {
  git -C "" config user.email t@t
}
F
  mk guarded <<'F'
@test "x" {
  git -C "${1:?repo required}" config user.email t@t
}
F
  mk suffixed <<'F'
@test "x" {
  git -C "$d/repo" config user.email t@t
}
F
  # ── RULE 1 SCOPE-AWARENESS + its three mutants. The guard belongs on the BINDING, so a use site
  # under a proven variable must go GREEN — but each mutant below breaks exactly one leg of that
  # proof and must go RED. Without them, "scope-aware" is indistinguishable from a file-level
  # wildcard that reads clean on files it never really checked.
  mk bound_guarded <<'F'
mkgit() {
  : "${1:?mkgit: repo path required}"
  git -C "$1" config user.email t@t
}
mkrepo() { local r="${1:?mkrepo: repo path required}"
  git -C "$r" config user.email t@t
}
F
  mk bound_no_guard <<'F'
mkgit() {
  git -C "$1" config user.email t@t
}
F
  mk bound_other_var <<'F'
mkgit() {
  : "${a:?a required}"
  git -C "$b" config user.email t@t
}
F
  mk bound_other_region <<'F'
one() {
  : "${r:?r required}"
}
two() {
  git -C "$r" config user.email t@t
}
F
  mk literal <<'F'
@test "x" {
  git -C fixture-repo config user.email t@t
}
F
  # The PROSE-MATCH regression control. Rules 2, 3 and 4 of test-hermeticity-lint each shipped
  # vacuous on exactly this shape — a file that MENTIONS the pattern in a comment and never runs it.
  mk prose <<'F'
@test "x" {
  # never do this: git -C "$dir" config user.email t@t
  true
}
F

  # ── RULE 2 fixtures. All four omit -C entirely, so the ONLY axis that varies is the cd. nocd is
  # byte-identical to cd_bare MINUS the cd — the scope control, without which "cd_bare went red"
  # proves nothing about SCOPING and the rule could simply be flagging every `git config`.
  mk cd_bare <<'F'
@test "x" {
  cd "$dir"
  git config user.email t@t
}
F
  mk cd_guarded <<'F'
@test "x" {
  cd "$dir" || return 1
  git config user.email t@t
}
F
  mk cd_chained <<'F'
@test "x" {
  cd "$dir" && git config user.email t@t
}
F
  mk nocd <<'F'
@test "x" {
  git config user.email t@t
}
F

  # (a) RED on each bare -C shape — a variable, a positional, and the empty literal that IS the bug.
  lint_tree "$d/bare_var"   "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a bare \$dir under -C did not go RED"; fails=1; }
  lint_tree "$d/bare_pos"   "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a bare positional under -C did not go RED"; fails=1; }
  lint_tree "$d/bare_empty" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: git -C \"\" — the literal bug — did not go RED"; fails=1; }
  # (b) GREEN on each accepted shape — the fixes the RED prescribes actually clear it.
  lint_tree "$d/guarded"  "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a \${1:?}-guarded -C did not go GREEN"; fails=1; }
  lint_tree "$d/suffixed" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an expansion with a literal suffix did not go GREEN"; fails=1; }

  # scope-awareness: GREEN when the binding is proven, RED when any leg of that proof is broken
  lint_tree "$d/bound_guarded" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a use site under a \${1:?}-proven BINDING did not go GREEN — the lint is convicting its own prescribed fix"; fails=1; }
  lint_tree "$d/bound_no_guard"    "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: MUTANT (guard line deleted) did not go RED — proof tracking is vacuous"; fails=1; }
  lint_tree "$d/bound_other_var"   "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: MUTANT (guard proves \$a, write uses \$b) did not go RED — proof is not keyed on the VARIABLE"; fails=1; }
  lint_tree "$d/bound_other_region" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: MUTANT (guard in a DIFFERENT function) did not go RED — proof is leaking across regions, i.e. a file-level wildcard"; fails=1; }
  lint_tree "$d/literal"  "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a literal path under -C did not go GREEN"; fails=1; }
  # (c) the PROSE-MATCH regression control.
  lint_tree "$d/prose" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a COMMENT naming the leaky shape counted as a write — the scan is matching prose"; fails=1; }
  # (d) RULE 2, with its scope control and both guard forms.
  lint_tree "$d/cd_bare" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an identity write after an UNGUARDED cd did not go RED"; fails=1; }
  lint_tree "$d/cd_guarded" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a ||-guarded cd did not go GREEN"; fails=1; }
  lint_tree "$d/cd_chained" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an &&-chained cd did not go GREEN"; fails=1; }
  lint_tree "$d/nocd" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an identity write with NO -C and NO cd was flagged — rule 2 is not scoping"; fails=1; }
  # (e) the report NAMES file and line. A ratchet whose message cannot be acted on is detection.
  ( out="$(lint_tree "$d/bare_var" "" 2>&1)"
    case "$out" in
      *"tests/zz-fixture.bats:2"*) exit 0 ;;
      *) echo "SELFTEST FAIL: the violation report did not name file:line"; exit 1 ;;
    esac
  ) || fails=1
  # (f) the ratchet is consulted in BOTH directions: grandfathered ⇒ green, fixed-but-listed ⇒ red.
  lint_tree "$d/bare_var" "zz-fixture.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered violation did not go GREEN"; fails=1; }
  lint_tree "$d/guarded"  "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a clean-but-still-grandfathered file did not go RED (the ratchet is not shrinking)"; fails=1; }
  # (g) own-scope: advisory OUTSIDE the lander's diff, blocking INSIDE it (path form accepted).
  lint_tree "$d/bare_var" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a violation OUTSIDE the own-set blocked"; fails=1; }
  lint_tree "$d/bare_var" "" "tests/zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a violation INSIDE the own-set did not block"; fails=1; }
  # (h) COULD-NOT-CHECK is a NON-VERDICT (exit 2) and must never print a line naming a file nobody
  #     was able to check. The output test is a `case`, not a grep: awk is what is stubbed, but the
  #     same discipline applies — an assertion must not be built out of the thing under stub.
  # shellcheck disable=SC2329  # invoked INDIRECTLY — scan_file's `awk` resolves to this stub
  ( awk() { return 2; }
    out="$(lint_tree "$d/guarded" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable scan did not exit 2 (got $rc)"; exit 1; }
    case "$out" in *IDENTITY*) echo "SELFTEST FAIL: an unrunnable scan still fabricated an IDENTITY line"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (i) LOUD, never silent-green, on a root with nothing to judge.
  lint_tree "$d/does-not-exist" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan root did not exit 2"; fails=1; }
  mkdir -p "$d/empty/tests"
  lint_tree "$d/empty" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a root with no scannable file did not exit 2"; fails=1; }
  # (j) SELF-EXCLUSION, proved rather than asserted: a file named git-identity-lint.bats carrying the
  #     leaky shape is skipped, and the identical file under any other name is not.
  mkdir -p "$d/selfex/tests"
  cp "$d/bare_var/tests/zz-fixture.bats" "$d/selfex/tests/git-identity-lint.bats"
  lint_tree "$d/selfex" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: the self-excluded suite was scanned (or counted) — exclusion is not taking"; fails=1; }
  # (k) entrypoint parity for the CC_GITID_ALLOWLIST seam, both directions. The RED half is what
  #     makes the GREEN half meaningful: without it, 'grandfathered' could be passing vacuously.
  ( CC_GITID_ALLOWLIST="" "$SELF" "$d/bare_var" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_GITID_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_GITID_ALLOWLIST="zz-fixture.bats" "$SELF" "$d/bare_var" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_GITID_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  # (l) entrypoint parity for CC_GITID_OWN's three states — absent ⇒ strict, set-but-empty ⇒ nothing
  #     blocks, set-and-matching ⇒ blocks. `${VAR:-}` cannot express the middle one; that collapse is
  #     the bug this shape exists to prevent.
  ( CC_GITID_ALLOWLIST="" CC_GITID_OWN="" "$SELF" "$d/bare_var" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_GITID_OWN set-but-EMPTY blocked — a diff touching nothing in scope must never block"; fails=1; }
  ( CC_GITID_ALLOWLIST="" CC_GITID_OWN="tests/zz-fixture.bats" "$SELF" "$d/bare_var" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_GITID_OWN naming the file did not block at the entrypoint"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "git-identity-lint --selftest: 26/26 — RULE 1 (bare -C): RED on a bare variable, a bare positional and the empty literal; GREEN on a \${1:?} guard, on an expansion with a literal suffix, and on a literal path; GREEN on a COMMENT naming the shape (the prose-match regression). RULE 1 SCOPE: GREEN on a use site under a \${1:?}-PROVEN binding (the guard belongs on the binding, so demanding it per use site would convict the prescribed fix), and RED on all three mutants of that proof — guard deleted, guard proving a DIFFERENT variable, guard in a DIFFERENT region — which is what separates scope-awareness from a file-level wildcard. RULE 2 (implicit cwd): RED on a write after an UNGUARDED cd; GREEN on a ||-guarded cd, on an &&-chained cd, and on a write with no cd at all (the scope control). Report names file:line; the ratchet is consulted BOTH ways (grandfathered ⇒ green, fixed-but-listed ⇒ red); own-scope blocks INSIDE the diff and advises OUTSIDE it (path form accepted); a NON-VERDICT (exit 2) on an unrunnable scan with no fabricated line, on a missing root, and on a root with nothing to judge; self-exclusion proved by name; and both env seams (CC_GITID_ALLOWLIST, CC_GITID_OWN incl. its set-but-empty state) proved at the entrypoint."
    exit 0
  fi
  echo "git-identity-lint --selftest: FAILED — the ratchet does not discriminate."
  exit 1
fi

# CC_GITID_OWN — newline-delimited names (basenames or paths) the caller is answerable for.
# UNSET ⇒ strict whole-tree blocking. SET (including set to EMPTY) ⇒ own-scope, where an empty value
# legitimately means "I change nothing in scope, so nothing may block me". `+set` is the only test
# that separates those; `${CC_GITID_OWN:-}` would collapse them and reinstate the fleet-wide hard
# stop for precisely the docs-only land the own-scope contract exists to let through.
if [ -n "${CC_GITID_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "$ALLOW" "$CC_GITID_OWN"
else
  lint_tree "${1:-$ROOT}" "$ALLOW"
fi
