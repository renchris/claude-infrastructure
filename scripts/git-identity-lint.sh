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
# RULE 2 (the implicit cwd): an identity write with NO `-C` at all, preceded in the same region by a
# `cd` that could leave the process in the caller's repo. Same failure with the seam moved — the
# fixture's own `cd` is what was supposed to put the write inside the fixture repo, so a `cd` that
# silently did not happen leaves the write pointed at the caller's cwd.
#
# A `cd` is SAFE only when BOTH legs hold, and the second is the one that is easy to get wrong:
#   * GUARDED — `||`-chained (`|| exit`, `|| return`) or `&&`-chained to the work that follows, so a
#     cd to a NONEXISTENT path cannot be discarded.
#   * NON-EMPTIABLE ARGUMENT — because **`cd ""` RETURNS 0** (measured 2026-08-05: rc=0, cwd
#     unchanged). A `cd "$x" || return 1` is therefore INERT against an empty `$x`: the `||` never
#     fires and the `&&` never short-circuits, so the write still lands in the caller's repo. Scoring
#     the PRESENCE of a guard would mark every empty-variable site green — the exact
#     "denylist enumerates spellings, not the class" trap this tree has hit before. The
#     discriminating test is the ARGUMENT: a literal suffix (`"$d/repo"`), a `${x:?}` that aborts
#     rather than expanding to empty, or a variable PROVEN non-empty earlier in the region.
#
# A write with no `-C` and no preceding `cd` is OUT OF SCOPE and never flagged — that scoping is what
# stops rule 2 firing on every `git config` in the tree, which would pass every RED assertion while
# proving nothing.
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
# POPULATION INTEGRITY: self-exclusion, the grandfather ratchet and own-scope all key on a file's
# BASENAME over a population spanning three directories, so they are sound only while basename is a
# bijection with path. That precondition is now CHECKED rather than assumed — see the header above
# population_collisions() for the three decisions it protects and why a collision blocks (rc 1)
# instead of reporting a non-verdict.
#
# Exit: 0 = clean · 1 = violation or a colliding basename · 2 = bad usage / unusable scan root
#       (LOUD, never silent-green)
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
#
# git-identity-write-guard.bats is the AGENT-TYPED half of this same class — a PreToolUse deny that
# a source lint is structurally blind to, since reso was poisoned by a one-liner that never landed
# in a file. Its DENY cases are the leaky shapes passed to run_hook AS TEST INPUT, so scanning it
# convicts a suite whose whole purpose is to refuse them. It landed on trunk from a sibling session
# while this lint was in flight, which is exactly how a self-exclusion list acquires its entries:
# not by foresight, but by a green tree going red on the next file that carries fixtures.
#
# gitid-file-memo.bats is the third, and it arrived the way this comment predicts: it exists to
# prove this lint's own memo never replays a cached finding, so it has to WRITE a file carrying the
# leaky shape and then assert the lint reports it TWICE. The violation is the test input. Caught by
# the gate on the very commit that added the memo, not by review.
SELF_EXCLUDE="git-identity-lint.sh
git-identity-lint.bats
git-identity-write-guard.bats
gitid-file-memo.bats"

# ── THE PER-FILE MEMO ─────────────────────────────────────────────────────────────────────────────
# This arm costs 18.5 ms per file over 727 files — 13.4s, measured through ship-land's own_run, and
# essentially all of it is the one `awk` fork per file in scan_file. On a re-round (22-23% of lands)
# every second of that re-proves a verdict about bytes that did not move.
#
# WHAT MAKES A PER-FILE KEY EXACT HERE, stated because the sibling lint's version needed a read-set
# argument and this one genuinely does not: a file's verdict is a function of its own bytes, the
# ratchet list, and the self-exclusion list — and nothing else. scan_file is one awk pass over ONE
# file; it follows no include, reads no table, and compares this file to no other. There is no
# analogue of rules 5-6 next door, where a table built from bin+scripts+hooks decides a suite's
# verdict. So the read set is three values, and GITID_READSET below is it in executable form.
#
# The allowlists are hashed BY VALUE rather than left to the script blob: CC_GITID_ALLOWLIST changes
# what this file calls green without changing one byte of it, and a key that only fingerprinted the
# file would serve the next caller a green earned under a different list.
#
# Kill switch: CC_GITID_MEMO=off. SHIP_LAND_MEMO=off also disables it, via memo_init.
GITID_MEMO_OK=0
GITID_CHECKER=""
GITID_FILES=()
GITID_MEMO_HITS=0
GITID_MEMO_RAN=0
if [ "${CC_GITID_MEMO:-on}" != "off" ] && [ -r "$ROOT/scripts/lib/gate-memo.sh" ]; then
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/gate-memo.sh" 2>/dev/null || true
fi

gitid_memo_arm() {  # $1 = the ratchet text lint_tree was called with · $2… = the EXACT population
  GITID_MEMO_OK=0
  [ "${CC_GITID_MEMO:-on}" != "off" ] || return 1
  command -v memo_init >/dev/null 2>&1 || return 1
  command -v memo_batch_arm >/dev/null 2>&1 || return 1  # an older lib ⇒ memo OFF, today's behaviour
  memo_init || return 1                    # dirty tree · no git dir · unwritable store ⇒ memo OFF
  local selfblob readset
  # $SELF is already symlink-resolved above, and ABSOLUTE only because ROOT was derived from it by
  # `cd`. Hash it by that resolved path rather than by "$ROOT/scripts/$(basename …)": the sibling
  # lint shipped both of those bugs in one iteration — a relative SELF made the key unobtainable
  # from any other directory (memo silently never armed), and the $ROOT/scripts/ reconstruction was
  # true of the checkout and false of every copy.
  selfblob="$(git hash-object -- "$SELF" 2>/dev/null)" || return 1
  [ -n "$selfblob" ] || return 1
  readset="$(
    printf 'gitid-readset/v1\n'
    printf 'lint=%s\n'      "$selfblob"
    printf 'allow=%s\n'     "$1"
    printf 'selfexcl=%s\n'  "$SELF_EXCLUDE"
  )" || return 1
  GITID_CHECKER="gitid/$(printf '%s' "$readset" | git hash-object --stdin 2>/dev/null)"
  [ "$GITID_CHECKER" != "gitid/" ] || return 1
  shift
  memo_batch_arm "$GITID_CHECKER" "$@" || return 1
  GITID_MEMO_OK=1
  return 0
}

# THE EMIT DETECTOR. Every branch in lint_tree that prints a finding increments exactly one of these
# three counters, so their sum is unchanged across a file IFF that file emitted nothing. Two lines
# rather than an `emitted=1` at each printf — but that is only true while it stays true, so
# --selftest pins a violating file as never-memoized under both of its rules.
gitid_emit_sum() { printf '%s' "$(( bad + stuck + other ))"; }

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
# BARE = the whole argument is one expansion, or the empty string: nothing in it can make the
# argument non-empty. VNAME pulls the variable out of $1 / ${1} / $r / ${r}.
function bare(a) { return (a == "" || a ~ /^\$[0-9]+$/ || a ~ /^\$[A-Za-z_][A-Za-z0-9_]*$/ ||
                           a ~ /^\$\{[0-9]+\}$/ || a ~ /^\$\{[A-Za-z_][A-Za-z0-9_]*\}$/) }
function vname(a) { gsub(/^\$\{?|\}$/, "", a); return a }
function emptiable(a) { return bare(a) && !(vname(a) in proven) }
function unquote(a) { gsub(/^["']|["']$/, "", a); return a }
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
  # EVERY assignment on the line, not just the first: `local o="$T/o" w="$T/w"` and
  # `o="$T/o"; w="$T/w"` are both single lines that bind TWO paths, and matching once proved `o`
  # while leaving `w` convicted — which is how 13 correct sites survived the first pass here.
  if (match(line, /^[[:space:]]*:[[:space:]]+"?\$\{[A-Za-z0-9_]+:\?/)) {         # : "${1:?msg}"
    seg = substr(line, RSTART, RLENGTH); gsub(/^.*\$\{|:\?$/, "", seg); if (seg != "") proven[seg] = 1
  }
  rest = line                                                                     # local r="${1:?msg}"
  while (match(rest, /(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\{[A-Za-z0-9_]+:\?/)) {
    seg = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    lhs = seg; sub(/^local[[:space:]]+/, "", lhs); sub(/=.*$/, "", lhs); if (lhs != "") proven[lhs] = 1
    rhs = seg; gsub(/^.*\$\{|:\?$/, "", rhs);                          if (rhs != "") proven[rhs] = 1
  }
  rest = line                                                                     # repo="$d/repo"
  while (match(rest, /(local[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="\$\{?[A-Za-z0-9_]+\}?\/[^"]*"/)) {
    seg = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    lhs = seg; sub(/^local[[:space:]]+/, "", lhs); sub(/=.*$/, "", lhs); if (lhs != "") proven[lhs] = 1
  }

  # A cd whose failure OR whose emptiness can leave the process in the caller's repo. BOTH legs
  # are required, and the second is the one that is easy to get wrong:
  #
  #   * UNGUARDED (no ||, no &&) — a cd to a NONEXISTENT path fails and the write lands in cwd.
  #   * EMPTIABLE argument — `cd ""` RETURNS 0 (measured 2026-08-05, bash 3.2/5.x: rc=0, cwd
  #     unchanged). So `cd "$x" || return 1` is INERT against an empty $x: the guard never fires,
  #     and the write still lands in the caller's repo. Scoring the PRESENCE of a `||` would mark
  #     every empty-variable site green — the same "denylist enumerates spellings, not the class"
  #     trap the repo has hit before. The discriminating test is the ARGUMENT, not the guard.
  #
  # So: safe only when the argument cannot be empty (a literal suffix like "$d/repo", a `${x:?}`
  # which aborts rather than expanding to empty, or a variable PROVEN in this region) AND the cd
  # is guarded against a nonexistent path.
  if (match(line, /(^|[[:space:];&|(])cd[[:space:]]+(--[[:space:]]+)?[^[:space:];&|)]+/)) {
    cdarg = substr(line, RSTART, RLENGTH)
    sub(/^[^c]*cd[[:space:]]+/, "", cdarg); sub(/^--[[:space:]]+/, "", cdarg)
    cdarg = unquote(cdarg)
    if (emptiable(cdarg) || (line !~ /\|\|/ && line !~ /&&/)) cdline = NR
  }

  if (line !~ /git[[:space:]]/) next
  if (line !~ /config/) next
  if (line !~ /user\.(email|name)/) next

  if (match(line, /(^|[[:space:]])-C[[:space:]]+[^[:space:]]+/)) {
    arg = substr(line, RSTART, RLENGTH)
    sub(/^[[:space:]]*-C[[:space:]]+/, "", arg)
    gsub(/^["']|["']$/, "", arg)
    # BARE = the whole argument is one expansion, or the empty string. Nothing in it can make the
    # argument non-empty, so `git -C` degrades to a no-op and the write lands in the caller's cwd.
    if (emptiable(arg))
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

# ── POPULATION INTEGRITY: this lint keys THREE decisions on a file's BASENAME ─────────────────────
# The population is `tests/*.bats` + `scripts/*.sh` + `bin/*` — THREE directories, one flat glob
# each — and a file's basename is the key for all of:
#
#   1. SELF-EXCLUSION (lint_tree's build loop)  a match DROPS the file from the population outright.
#      It is never scanned, never reported, not even advisory: the file simply is not there.
#   2. THE GRANDFATHER RATCHET (in_allowlist)   a match EXEMPTS the file's findings.
#   3. OWN-SCOPE (in_own)                       a match decides BLOCKING versus advisory.
#
# All three are sound only while basename is a BIJECTION with path across that population — an
# assumption nothing stated and nothing checked. `bin/` carries no extension constraint, so
# `bin/git-identity-lint.sh` is enough to make SELF_EXCLUDE swallow a real file whole, and the two
# fail-GREEN directions (1 and 2) are exactly the class this lint exists to catch: a verdict that
# reads clean because the instrument never looked.
#
# MEASURED 2026-08-15 ON THIS TREE: **0 colliding basenames** across all three globs. That clean
# baseline is what makes the strictest rule the free one — the same argument bats-kill-guard-lint
# and bats-testname-eval-lint each record, and the reason this is a guard rather than a rewrite of
# the three keys into paths. Nothing is grandfathered because nothing needs to be.
#
# WHY BLOCKING (rc 1) AND NOT A NON-VERDICT (rc 2): ship-land routes 2 to GATE_KILLED ⇒ exit 9,
# "retryable, re-run when the box is quieter". A collision is not transient and re-running never
# clears it; it is author-fixable — rename the file, or promote the three keys to paths. Sending it
# down the retry path would loop forever on a condition no retry can touch.
#
# It is OWN-SCOPED like every other finding here, which is what makes it a chokepoint rather than a
# fleet-wide hard stop: the land that ADDS the namesake is refused, and everyone else reads one
# advisory line naming it (memory: enforcement-must-live-at-the-chokepoint).
#
# population_collisions <root> → one "<basename>\t<path>, <path>[, …]" line per colliding basename.
# rc 1 = no collisions (or nothing to scan) — the common case, and it prints nothing.
population_collisions() {
  local root="$1" f list="" dups b paths
  for f in "$root"/tests/*.bats "$root"/scripts/*.sh "$root"/bin/*; do
    [ -f "$f" ] || continue
    list="$list${list:+
}${f#"$root"/}"
  done
  [ -n "$list" ] || return 1
  # A full pipeline, not a `| grep -q` probe: `uniq` drains its input, so there is no early-exit
  # consumer and no SIGPIPE 141 to be misread under `pipefail` (see the here-string note above).
  dups="$(printf '%s\n' "$list" | sed 's:.*/::' | sort | uniq -d)"
  [ -n "$dups" ] || return 1
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    paths="$(printf '%s\n' "$list" | awk -F/ -v b="$b" '$NF == b { printf "%s%s", (n++ ? ", " : ""), $0 }')"
    printf '%s\t%s\n' "$b" "$paths"
  done <<EOF
$dups
EOF
  return 0
}

# lint_tree <repo-root> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable root
lint_tree() {
  local root="$1" allow="$2" own="${3:-}" own_scoped=0
  local f base rel seen=0 bad=0 stuck=0 other=0 collide=0 records n _gitid_emit0=0
  local _c_base _c_paths
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$root" ] || { echo "git-identity-lint: ⛔ not a directory: $root" >&2; return 2; }
  # THE PRECONDITION, CHECKED BEFORE ANY BASENAME-KEYED DECISION IS TRUSTED — see the header note
  # above population_collisions. It runs ahead of the build loop deliberately: the build loop is
  # itself decision (1), so a collision that involves a SELF_EXCLUDE entry has already deleted its
  # own evidence by the time the loop ends.
  while IFS="$(printf '\t')" read -r _c_base _c_paths; do
    [ -n "$_c_base" ] || continue
    if in_own "$_c_base" "$own" "$own_scoped"; then
      printf '  COLLIDE  %s names %s\n' "$_c_base" "$_c_paths"
      printf '           self-exclusion, the ratchet and own-scope all key on the BASENAME, so a\n'
      printf '           verdict for either file is silently a verdict for both.\n'
      collide=$((collide + 1))
    else
      printf '  collide? %s names %s (NOT in your diff — advisory, not blocking)\n' "$_c_base" "$_c_paths"
      other=$((other + 1))
    fi
  done <<EOF
$(population_collisions "$root")
EOF
  # THE POPULATION, BUILT EXACTLY ONCE. The batch memo is INDEX-KEYED, so the list it arms on and
  # the list this loop walks must be the SAME list — not two globs written to look alike. Both
  # filters (the `-f` test and the self-exclusion) live here, so a file skipped for either reason is
  # absent from both, and the index cannot drift. Building it twice is the only way this API can
  # serve one file's verdict for another.
  GITID_FILES=()
  for f in "$root"/tests/*.bats "$root"/scripts/*.sh "$root"/bin/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    in_allowlist "$base" "$SELF_EXCLUDE" && continue
    GITID_FILES[${#GITID_FILES[@]}]="$f"
  done
  GITID_MEMO_HITS=0; GITID_MEMO_RAN=0
  if [ "${#GITID_FILES[@]}" -gt 0 ]; then
    gitid_memo_arm "$allow" "${GITID_FILES[@]}" || true
  fi
  for f in ${GITID_FILES[@]+"${GITID_FILES[@]}"}; do
    base="$(basename "$f")"
    rel="${f#"$root"/}"
    seen=$((seen + 1))
    # THE MEMO HIT: this exact content already emitted nothing under this exact read set. `seen` is
    # incremented above regardless, so the census this run reports is the whole population and never
    # the miss-list — a count that shrank with the cache would be the memo lying about its scope.
    # The index is `seen - 1`, DERIVED and never a parallel counter: `seen` moves exactly once per
    # iteration, as the first statement and before any `continue`, so it cannot drift from the
    # position in GITID_FILES the way a second variable eventually does.
    if [ "$GITID_MEMO_OK" = "1" ] && memo_batch_hit "$((seen - 1))"; then
      GITID_MEMO_HITS=$((GITID_MEMO_HITS + 1))
      continue
    fi
    GITID_MEMO_RAN=$((GITID_MEMO_RAN + 1))
    _gitid_emit0="$(gitid_emit_sum)"
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
    elif ! in_allowlist "$base" "$allow"; then
      # Was `in_allowlist … && continue` before the memo: a grandfathered file with findings prints
      # nothing and falls through. Inverted into an `elif` rather than left as a `continue` so that
      # every green path reaches the ONE record site below — a `continue` past it would not be
      # unsound, but it would silently exclude the grandfathered files from the cache forever.
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
    fi
    # ── THE RECORD, the ONLY place a green is earned here. Two vetoes, both fail-safe: ──
    # (1) this file emitted something ⇒ it is a finding, and a finding is NEVER cached (gate-memo
    #     invariant 1) — it must re-print itself from the file on every run.
    # (2) CHECK_FAILED is set ⇒ some predicate in this run could not RUN. Both of this lint's
    #     unrunnable states are fail-SAFE — scan_file returns a sentinel rather than a fabricated
    #     violation, and in_allowlist answers 'present' — so a non-verdict looks EXACTLY like a
    #     clean file at this site. Caching that would freeze a could-not-check into a permanent
    #     green keyed on content, the one way a memo turns "I don't know" into "green".
    #
    #     🚨 ABSOLUTE, never a per-file delta. A delta vetoes only the FIRST file whose predicate
    #     dies; every file after it compares equal and is recorded — out of a run that exits 2 and
    #     whose whole point is that it produced no verdict. The sibling lint shipped exactly that
    #     bug for one iteration and only its own selftest caught it.
    if [ "$GITID_MEMO_OK" = "1" ] \
       && [ "$(gitid_emit_sum)" = "$_gitid_emit0" ] \
       && [ "$CHECK_FAILED" -eq 0 ]; then
      memo_batch_record "$((seen - 1))"
    fi
  done
  if [ "$GITID_MEMO_OK" = "1" ]; then
    echo "git-identity-lint: per-file memo — $GITID_MEMO_HITS verdict(s) carried, $GITID_MEMO_RAN proven fresh." >&2
  fi
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
    echo "  WHY: \`git -C \"\"\` is a NO-OP and \`cd \"\"\` RETURNS 0, so an empty path writes user.email/"
    echo "       user.name into whatever repo the process is standing in — and ~100 worktrees here share"
    echo "       ONE .git/config, so one such call re-authors every session on the box (9 commits on"
    echo "       trunk, 214 on reso). A \`||\`-chain does not rescue the cd shape: on an empty path the cd"
    echo "       SUCCEEDS, so the guard never fires and the write still lands in the caller's repo."
    echo "  Fix: guard the ARGUMENT — \`git -C \"\${1:?repo path required}\" config …\` — or give it a"
    echo "       literal suffix (\"\$d/repo\"). Same for the no-\`-C\` shape, chain included:"
    echo "       \`cd \"\${d:?repo path required}\" || return 1\`."
    echo "       Do NOT add to the allowlist — it ships empty and is meant to stay that way."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "git-identity-lint: ⛔ $stuck file(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$collide" -gt 0 ]; then
    echo "git-identity-lint: ⛔ $collide basename(s) above name more than one file in this lint's scan population."
    echo "  WHY: the population is tests/*.bats + scripts/*.sh + bin/* — three directories — and this"
    echo "       lint keys THREE decisions on the basename alone: self-exclusion (which DROPS a file"
    echo "       from the scan entirely), the grandfather ratchet (which EXEMPTS its findings), and"
    echo "       own-scope (which decides blocking vs advisory). With two files to one name, each of"
    echo "       those answers the wrong question silently — a namesake of an excluded or"
    echo "       grandfathered file is never really checked, and reads exactly like a clean one."
    echo "  Fix: rename one of the files so the basename is unique. The population has been collision-"
    echo "       free since this guard landed, which is why the rule is strict and carries no"
    echo "       allowlist — there is nothing to grandfather."
  fi
  [ $((bad + stuck + collide)) -eq 0 ] || return 1
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
  # THE INERT GUARD. `cd ""` returns 0, so a ||-chain on a bare expansion never fires. This fixture
  # is the whole reason rule 2 keys on the ARGUMENT and not on the presence of a guard — it looks
  # exactly like the remedy and protects against nothing when the variable is empty.
  mk cd_guarded_bare <<'F'
@test "x" {
  cd "$dir" || return 1
  git config user.email t@t
}
F
  mk cd_chained_bare <<'F'
@test "x" {
  cd "$dir" && git config user.email t@t
}
F
  # Genuinely safe: the argument cannot BE empty (literal suffix / proven binding) AND the cd is
  # guarded against a nonexistent path. Both legs, or it is not a fix.
  mk cd_guarded <<'F'
@test "x" {
  cd "$d/repo" || return 1
  git config user.email t@t
}
F
  mk cd_chained <<'F'
@test "x" {
  cd "$d/repo" && git config user.email t@t
}
F
  mk cd_guarded_proven <<'F'
@test "x" {
  repo="$BATS_TEST_TMPDIR/repo"
  cd "$repo" || return 1
  git config user.email t@t
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
  lint_tree "$d/cd_guarded" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a ||-guarded cd to a NON-EMPTIABLE path did not go GREEN"; fails=1; }
  lint_tree "$d/cd_chained" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an &&-chained cd to a NON-EMPTIABLE path did not go GREEN"; fails=1; }
  lint_tree "$d/cd_guarded_proven" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a ||-guarded cd to a PROVEN variable did not go GREEN"; fails=1; }
  # THE INERT GUARD — `cd ""` returns 0, so these protect against nothing when the variable is empty
  lint_tree "$d/cd_guarded_bare" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a ||-guarded cd to a BARE expansion did not go RED — \`cd \"\"\` returns 0, so the guard is INERT and rule 2 is scoring the guard instead of the argument"; fails=1; }
  lint_tree "$d/cd_chained_bare" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an &&-chained cd to a BARE expansion did not go RED — the && never short-circuits on an empty path"; fails=1; }
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
  # (m) POPULATION INTEGRITY — the basename bijection this lint's three keys all assume.
  #     The CONTROL IS CASE 1 BY CONSTRUCTION: a collision-free root must stay clean, or every
  #     assertion below passes for the wrong reason (the sibling's gitid-file-memo.bats shipped
  #     exactly that — three cases green against a fail-closed-OFF mechanism).
  mkdir -p "$d/coll/tests" "$d/coll/scripts" "$d/coll/bin"
  printf '@test "x" {\n  : ok\n}\n' > "$d/coll/tests/zz-fixture.bats"
  printf '#!/bin/bash\n: ok\n' > "$d/coll/scripts/foo.sh"
  lint_tree "$d/coll" "" >/dev/null 2>&1; [ "$?" -eq 0 ] || { echo "SELFTEST FAIL: a collision-FREE population did not read clean — the guard fires on everything"; fails=1; }
  #     The positive: one basename, two files, two directories.
  printf '#!/bin/bash\n: ok\n' > "$d/coll/bin/foo.sh"
  out="$(lint_tree "$d/coll" "" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] || { echo "SELFTEST FAIL: a colliding basename did not block (got $rc)"; fails=1; }
  case "$out" in *COLLIDE*) ;; *) echo "SELFTEST FAIL: a colliding basename blocked without naming itself COLLIDE"; fails=1 ;; esac
  #     THE ONE THAT MATTERS: a namesake of a SELF_EXCLUDE entry is DROPPED from the population
  #     outright — not exempted, dropped — so a real escaping write in it was reported as
  #     "clean — N file(s)" with the file absent from the census. Every SELF_EXCLUDE name maps to
  #     exactly one real file in this repo, so a namesake is necessarily a collision, which is what
  #     makes this guard cover the whole reachable class rather than a sample of it.
  rm -f "$d/coll/bin/foo.sh"
  printf '#!/bin/bash\n: ok\n' > "$d/coll/scripts/git-identity-lint.sh"
  printf '#!/bin/bash\ngit -C "$1" config user.email t@t\n' > "$d/coll/bin/git-identity-lint.sh"
  lint_tree "$d/coll" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a leaky namesake of a SELF_EXCLUDE entry was swallowed — the silent-green this guard exists to stop"; fails=1; }
  #     Own-scoped like every other finding: the land that ADDS the namesake is refused, everyone
  #     else reads one advisory line. Without this, the guard is a fleet-wide hard stop.
  ( CC_GITID_OWN="tests/zz-fixture.bats" "$SELF" "$d/coll" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: a collision OUTSIDE the diff blocked — own-scope is not taking"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "git-identity-lint --selftest: 34/34 — RULE 1 (bare -C): RED on a bare variable, a bare positional and the empty literal; GREEN on a \${1:?} guard, on an expansion with a literal suffix, and on a literal path; GREEN on a COMMENT naming the shape (the prose-match regression). RULE 1 SCOPE: GREEN on a use site under a \${1:?}-PROVEN binding (the guard belongs on the binding, so demanding it per use site would convict the prescribed fix), and RED on all three mutants of that proof — guard deleted, guard proving a DIFFERENT variable, guard in a DIFFERENT region — which is what separates scope-awareness from a file-level wildcard. RULE 2 (implicit cwd): RED on a write after an UNGUARDED cd; GREEN on a ||-guarded cd and an &&-chained cd to a NON-EMPTIABLE path, and on a ||-guarded cd to a PROVEN variable — but RED on the ||-guarded AND the &&-chained form of a BARE expansion, because \`cd \"\"\` returns 0 so neither chain ever fires and the guard is INERT, which is what pins rule 2 to the ARGUMENT rather than to the presence of a guard; GREEN on a write with no cd at all (the scope control). Report names file:line; the ratchet is consulted BOTH ways (grandfathered ⇒ green, fixed-but-listed ⇒ red); own-scope blocks INSIDE the diff and advises OUTSIDE it (path form accepted); a NON-VERDICT (exit 2) on an unrunnable scan with no fabricated line, on a missing root, and on a root with nothing to judge; self-exclusion proved by name; both env seams (CC_GITID_ALLOWLIST, CC_GITID_OWN incl. its set-but-empty state) proved at the entrypoint; and POPULATION INTEGRITY — the basename bijection that self-exclusion, the ratchet and own-scope all silently assume — with a collision-FREE root as the control, a colliding basename blocking and naming itself COLLIDE, a leaky namesake of a SELF_EXCLUDE entry REPORTED rather than swallowed (it was previously dropped from the population outright and read as 'clean'), and a collision outside the diff staying advisory."
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
