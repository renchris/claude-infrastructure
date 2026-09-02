#!/bin/bash
# shellcheck disable=SC2016  # file-wide: every --selftest fixture body is written VERBATIM into a
# .bats file, where `$REPO`, `$PRE` and `$GIT_BIN` must arrive UNEXPANDED or the case asserts
# nothing, and the guidance text prints the literal fix an author must paste.
# moving-ref-control-lint — a RATCHET on pre-fix CONTROLS replayed from a MOVING git ref.
#
# WHY: a control exists to prove a case can FAIL, and the only artifact that proves it is the real
# code as it stood BEFORE the fix. `git show origin/main:<path>` is that artifact only until the fix
# lands on origin/main — from that instant the control replays the POST-fix file and compares the fix
# to itself. The ref moves; the control does not notice.
#
# THE TWO OUTCOMES, and the second is why this is a lint and not a note:
#   · LOUD — the control asserts a pre-fix VALUE, so it goes red the moment the ref advances.
#     tests/capacity-alarm-permb.bats (54555bed1, 2026-08-11) shipped its control in the same commit
#     as its fix and reddened on landing; fixed at 91ced60a5 by pinning 73f4a4ec1 (=54555bed1^).
#     Measured again here 2026-08-13: tests/compressor-sentinel.bats cases 72/75/76 were RED ON TRUNK
#     for the same reason, and had been since 6dd3ea468 landed.
#   · SILENT — the control asserts only that the pre-fix artifact does NOT do the new thing, and the
#     post-fix artifact happens not to do it either, for an unrelated reason. Measured 2026-08-13:
#     tests/ignition-gate-census.bats replayed the POST-fix gate through `pregate`, which sets no
#     CC_IGNITION_EXE_FILE, so the new code's name table named none of the fixture's synthetic pids
#     and answered node_n=0 — the very number the pre-fix defect produced. 9/9 GREEN, asserting
#     nothing. A red control gets fixed. A vacuous one gets trusted.
#
# WHY A LINT AND NOT A FOURTH PARAGRAPH. This is the third instance of one greppable mistake —
# tests/wake-floor.bats (2026-07-29), tests/capacity-alarm-permb.bats (2026-08-11), then the two
# above. The memory control-must-replay-the-real-artifact.md has carried the exact rule since the
# first instance and did not reach an author twelve days later. A per-file fix cannot see its own
# class. (memory: enforcement-must-live-at-the-chokepoint, per-site-mutation-attributes-coverage)
#
# THE RULE, and the discriminator is INVOCATION vs MENTION — not comment vs code. Both matter:
#   (a) comment lines are dropped first. This repo now has ~40 lines of prose in tests/ explaining
#       this defect, every one of them containing the offending phrase. A lint that flagged its own
#       documentation would teach people to ignore it. (memory: contract-prose-can-understate-the-
#       mechanism — here the census of a harness was disarmed by exactly this.)
#   (b) QUOTED SPANS are stripped before matching, because an executed line can MENTION the phrase
#       without running it. tests/cc-dispatch-projects.bats:359 asserts
#       `grep -q "git show origin/main:<path>" "$C/brief-proj-b-1.txt"` — a fully executed line whose
#       phrase is a string being asserted ABOUT. It is the positive control for the too-wide
#       direction, and a lint that flags 3 of those 3 sites is as wrong as one that flags 0.
#
# WHAT COUNTS AS PINNED: a ref token of 7+ hexadecimal characters — an abbreviated or full sha.
# EVERYTHING ELSE MOVES, and the rule is a subtraction rather than an enumeration on purpose:
# `origin/main`, `HEAD`, `main`, a branch name and a tag all advance, and a new spelling of "moving"
# needs no change here. A ref that survives quote-stripping as EMPTY (`git show "$SHA":path`) is
# flagged too — not because a variable is wrong, but because this lint cannot read what it holds, and
# a control whose pin cannot be read from the file cannot be audited from the file.
#
# KNOWN LIMITS, stated rather than hidden:
#   · `git show` only. `git cat-file -p origin/main:<path>`, `git archive` and a shell-out through a
#     helper have the same failure mode and are NOT caught. The corpus has no such site (checked
#     2026-08-13); do not read a green here as "no moving-ref replay anywhere".
#   · A scratch repo the test itself creates and pushes to is a LEGITIMATE moving-ref read — the test
#     owns that ref. No such `show` site exists today; one would take an allowlist line WITH its
#     explanation, exactly as a grandfathered entry does.
#   · A line with a dangling quote is matched RAW (fail-closed) rather than half-stripped.
#
# Exit: 0 = clean · 1 = violation / stuck ratchet entry · 2 = bad usage or unreadable scan dir
#       (LOUD, never silent-green)
#
# Env seams: CC_MOVINGREF_ALLOWLIST overrides the embedded ratchet · CC_MOVINGREF_OWN scopes which
# violations may BLOCK (three-state contract, identical to test-afunix-path-lint / test-walltime-lint).
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the ratchet: suites grandfathered with a moving-ref control. ONLY EVER DELETE LINES. ──────────
# EMPTY BY CONSTRUCTION. Both known sites were repaired in the same diff that landed this lint, so
# there is no grandfathered debt to erode. An entry added later must carry the same standard its
# sibling ratchets use — CHECKED and explained, never an unexamined hit; that is how a ratchet decays
# into an exemption list.
EMBEDDED_ALLOWLIST=""

# OWN-SCOPE — THREE states, and `${VAR:-}` cannot express them: own-set ABSENT ⇒ strict whole-tree;
# SET-BUT-EMPTY ⇒ "I change no suite" ⇒ nothing blocks; SET ⇒ block on those only. Presence rides on
# argument count here and on `${CC_MOVINGREF_OWN+set}` at the entry point.
#
# This is what dissolves the deferral this work carried for two days ("the lint would block every
# concurrent lander in the live dispatch wave"). Own-scoped, it blocks nobody who does not touch
# these files, so the F1 downside does not arise.
in_own() {  # $1=basename · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  # DRAINED, not -q: this pipeline is the FUNCTION-FINAL statement, so its rc IS the answer every
  # caller reads. Under the `set -uo pipefail` above, `grep -q` exits on the first match, `sed`
  # takes SIGPIPE, and pipefail returns 141 — a MATCH reading as NOT-IN-OWN-SCOPE, which downgrades
  # a finding this land actually wrote from BLOCKING to advisory. The three-stage form inverts far
  # earlier than the two-stage one its siblings document — but ⚠️ the numbers this comment used to
  # quote ("safe to 17,427 bytes and ALWAYS inverted from 23,227", 20 trials, 2026-08-26) are
  # REFUTED and were in the wrong UNIT: re-measured 2026-08-28, 17,427 producer bytes is 0/200 at
  # 13 B per line and 43-54/200 at 55 and 149 B, and 23,227 is RACY at 137-149/200, not ALWAYS.
  # THE BINDING QUANTITY IS WHAT THE `sed` EMITS, not what the printf writes — 22,000 producer bytes
  # held constant across six cells reads 279/400 wrong at 18,000 emitted and 0/400 at 15,600.
  # Full table + method: the header of scripts/pipefail-sigpipe-lint.sh (the SSOT for these bands).
  # LATENT here rather than live, and the RIGHT ceiling to watch is the EMITTED one: this own-set is
  # CHANGED PATHS, the whole .bats corpus is 16,945 bytes of them, and the `sed 's:.*/::'` below
  # reduces those paths to basenames — so what reaches grep is smaller still. That ceiling is an
  # operational quantity and it grows; measure it after the sed, not before. Draining costs
  # nothing and keeps the same 0/1 ladder the callers read. (backlog ca97c678b18b: pipefail-sigpipe
  # -lint cannot SEE a function-final pipeline, so no ratchet would have caught this.)
  printf '%s\n' "$2" | sed 's:.*/::' | grep -xF "$1" >/dev/null
}

# DRAINED for the reason in in_own above — same shape, same pipefail, and this body IS the pipeline.
in_allowlist() { printf '%s\n' "$2" | grep -xF "$1" >/dev/null; }

# Moving-ref `git show` sites in one suite: "<lineno>:<ref>:<trimmed source>", one per line.
#
# 🚨 THE "IS THIS A PINNED SHA" TEST USES `length()`, NEVER AN ERE INTERVAL — A PORTABILITY FIX, NOT
# A STYLE ONE (backlog b60eb29e97dd, 2026-08-29). The pin test below used to read
# `ref ~ /^[0-9a-f]{7,40}$/`. POSIX makes `{n,m}` OPTIONAL in awk EREs, and mawk — Debian/Ubuntu's
# default `awk`, hence every Linux CI box and every cloud VM this repo dispatches work to — does not
# honour it. Measured on mawk 1.3.4 20240123: a literal `0fe052972` piped through that pattern prints
# nothing, while macOS's BWK awk matches it. So on Linux EVERY correctly-pinned literal sha fell past
# the test and was reported as a MOVING ref — this lint's verdict inverted, in the direction that
# BLOCKS: it is a land gate, so a false MOVING-REF is a land that cannot proceed at all.
#
# It was not silent, and it had already cost something. `--selftest` reds 4/22 on such a box, the
# first being "an abbreviated literal sha went RED — that is the prescribed fix", i.e. the lint
# refuting its own remedy. And a cloud session working backlog b60eb29e97dd reported
# "gate issues: lint detector, mawk interval" as the thing blocking its ship, then handed the land
# back to the desk rather than landing it — a finished, tested fix stranded on a ref nobody fetched.
#
# `--re-interval` is not the cure: it is a gawk/mawk flag that BWK awk rejects outright, so it would
# trade this venue's red for the operator's. `length()` is POSIX awk on every implementation.
moving_ref_shows() { # $1=file
  awk '
    # Drop every span between a quote and its MATCHING partner. A dangling quote keeps the rest of
    # the line RAW — the fail-closed direction: better to look at too much than to blind the match.
    # A CONTEXT STACK, not naive pairing. A command substitution nested in double quotes re-opens an
    # UNQUOTED context, so in  x="$(git -C "$REPO" show <ref>:<path>)"  the inner "$REPO" is a quoted
    # span of its OWN. Pairing the outer opener with that inner opener drops the whole tail, and the
    # show token this lint exists to find goes with it. Live fixture and the reason this landed:
    # tests/cc-dispatch-projects.bats:429, which reddened every land in this repo on 2026-09-02 while
    # this lint reported 560 suites clean. Backslash escapes are honoured for the same reason.
    # THE DANGLING-QUOTE CONTRACT IS UNCHANGED and has its own selftest case: a quote with NO partner
    # is treated as a LITERAL, so the remainder of the line stays RAW. That is the fail-CLOSED
    # direction — a stripper that swallows the tail lets a violation walk.
    # NO APOSTROPHE MAY APPEAR ANYWHERE IN THIS PROGRAM: it is carried in a single-quoted bash
    # string, and one stray apostrophe truncates it into a detector that scans everything, matches
    # nothing, and reports a clean tree. The sibling lint records the same scar in its own header.
    function partner(s, i, c,   j) { j = index(substr(s, i + 1), c); return (j == 0 ? 0 : i + j) }
    function strip(s,   out, i, c, dq, sq, n, st) {
      dq = sprintf("%c", 34); sq = sprintf("%c", 39)
      n = 0; out = ""; i = 1
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (n > 0 && st[n] == 1) {                       # inside a single-quoted span
          if (c == sq) { n-- }
          i++
          continue
        }
        if (n > 0 && st[n] == 2) {                       # inside a double-quoted span
          if (c == "\\") { i += 2; continue }
          if (c == dq) { n--; i++; continue }
          if (c == "$" && substr(s, i + 1, 1) == "(") { n++; st[n] = 3; i += 2; continue }
          i++
          continue
        }
        if (c == "\\") { out = out c substr(s, i + 1, 1); i += 2; continue }
        if ((c == sq || c == dq) && partner(s, i, c) > 0) {
          n++; st[n] = (c == sq ? 1 : 2); i++
          continue
        }
        if (c == "$" && substr(s, i + 1, 1) == "(") { n++; st[n] = 3; out = out "$("; i += 2; continue }
        if (c == ")" && n > 0 && st[n] == 3) { n--; out = out c; i++; continue }
        out = out c; i++
      }
      return out
    }
    /^[[:space:]]*#/ { next }
    {
      t = strip($0)
      # `show <ref>:<path>` surviving the strip. The ref part is a STAR, so an expansion that strips
      # to nothing still matches and still gets a verdict.
      if (!match(t, /(^|[^[:alnum:]_-])show[[:space:]]+[^[:space:]:]*:[^[:space:];|&)]+/)) next
      tok = substr(t, RSTART, RLENGTH)
      sub(/^[^[:alnum:]_-]?show[[:space:]]+/, "", tok)
      ref = tok; sub(/:.*$/, "", ref)
      # PINNED: 7-40 hex characters, an abbreviated or full sha. Everything else moves.
      # The length bound is length(), never an ERE interval — see the block above the function.
      if (ref ~ /^[0-9a-f]+$/ && length(ref) >= 7 && length(ref) <= 40) next
      src = $0; sub(/^[[:space:]]+/, "", src)
      printf "%d:%s:%s\n", NR, (ref == "" ? "<unreadable expansion>" : ref), src
    }
  ' "$1" 2>/dev/null
}

# lint_dir <tests-dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f base hits bad=0 seen=0 other=0 stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$dir" ] || { echo "moving-ref-control-lint: ⛔ not a directory: $dir" >&2; return 2; }
  for f in "$dir"/*.bats; do
    [ -e "$f" ] || continue
    seen=$((seen + 1)); base="$(basename "$f")"
    hits="$(moving_ref_shows "$f")"
    if [ -n "$hits" ]; then
      if in_allowlist "$base" "$allow"; then
        continue                                   # grandfathered — known site, already on the list
      elif in_own "$base" "$own" "$own_scoped"; then
        printf '  MOVING-REF %s: a control replayed from a ref that ADVANCES past the fix\n' "$base"
        printf '%s\n' "$hits" | sed 's/^/               /'
        bad=$((bad + 1))
      else
        printf '  moving?    %s: moving-ref control (NOT in your diff — advisory, not blocking)\n' "$base"
        other=$((other + 1))
      fi
    elif in_allowlist "$base" "$allow"; then
      if in_own "$base" "$own" "$own_scoped"; then
        printf '  RATCHET    %s replays no moving ref now — delete its allowlist line\n' "$base"
        stuck=$((stuck + 1))
      else
        printf '  ratchet?   %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$base"
        other=$((other + 1))
      fi
    fi
  done
  [ "$seen" -gt 0 ] || { echo "moving-ref-control-lint: ⛔ no .bats suites under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "moving-ref-control-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bad" -gt 0 ]; then
    echo "moving-ref-control-lint: ⛔ $bad suite(s) above replay a pre-fix control from a MOVING ref."
    echo "  Why it matters: the ref advances past your fix the moment it lands, and the control then"
    echo "  compares the fix to itself. It either reddens permanently (compressor-sentinel, 3 cases"
    echo "  red on trunk) or passes vacuously for an unrelated reason (ignition-gate-census, 9/9"
    echo "  green asserting nothing). The second is worse: a red control gets fixed."
    echo "  Fix, BOTH halves — the pin alone re-goes-vacuous if the sha is ever re-pointed:"
    echo "    1. replay a LITERAL sha, normally <fix-commit>^ —  git -C \"\$REPO\" show 808c09609:<path>"
    echo "    2. assert a MARKER: an identifier the FIX introduced must be ABSENT from the replay,"
    echo "       e.g.  ! grep -q 'exe_table' \"\$PRE\" || false"
    echo "       Derive that marker from the two artifacts' MEASURED diff, never from the prose: the"
    echo "       obvious spelling is often named in the post-fix file's own explanatory comment and"
    echo "       greps 1 on BOTH sides."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "moving-ref-control-lint: ⛔ $stuck suite(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "moving-ref-control-lint: clean — $seen suite(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 moving-ref controls."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  for c in cmdsub mainref headref bareref branchref expansion dangling pinned pinnedfull mention prose nogit push catfile showref; do mkdir -p "$d/$c"; done
  mk() { printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$d/$1/zz-fixture.bats"; }

  # RED — the moving refs, each spelling the corpus has actually used or could plausibly use.
  # RED — the same moving ref inside a COMMAND SUBSTITUTION, which is how the corpus actually spells
  # it when the pre-fix text is captured into a variable. The inner "$REPO" is a quoted span of its
  # own, and naive pairing mis-paired the outer opener with it and dropped the show. Live fixture:
  # tests/cc-dispatch-projects.bats:429, which reddened every land in this repo on 2026-09-02.
  mk cmdsub    'setup() { if ! r="$(git -C "$REPO" show origin/main:bin/cc-thing 2>/dev/null)"; then :; fi; }'
  mk mainref   'setup() { git -C "$REPO" show origin/main:bin/cc-thing > "$PRE" 2>/dev/null; }'
  mk headref   'setup() { git -C "$REPO" show HEAD:bin/cc-thing > "$PRE" 2>/dev/null; }'
  mk bareref   'setup() { git show main:bin/cc-thing > "$PRE"; }'
  mk branchref 'setup() { git -C "$REPO" show feat/some-branch:bin/cc-thing > "$PRE"; }'
  # RED — the ref is an expansion this lint cannot read. Not wrong, but not auditable from the file.
  mk expansion 'setup() { git -C "$REPO" show "$PRE_SHA":bin/cc-thing > "$PRE"; }'
  # RED — the binary itself is an expansion, so a `git`-token requirement would MISS this. The rule
  # deliberately does not require one: tests/session-start-mcp-probe.bats spells it exactly this way.
  mk nogit     'setup() { "$GIT_BIN" -C "$REPO" show origin/main:hooks/session-start.sh > "$PRE"; }'
  # RED — a DANGLING quote ahead of the site. The apostrophe in `don't` has no partner, and the
  # stripper's choice there is the whole difference between a guard and a hole: keeping the remainder
  # RAW (fail-closed) still sees the show; breaking out of the scan (fail-open) drops it and the
  # violation walks. Pinned as a case because the fail-open mutant left every OTHER case green.
  sq="$(printf '%c' 39)"
  mk dangling  "setup() { : don${sq}t ; git -C \"\$REPO\" show origin/main:bin/cc-thing > \"\$PRE\"; }"
  # GREEN — a literal sha, abbreviated and full.
  mk pinned     'setup() { git -C "$REPO" show 808c09609:bin/cc-thing > "$PRE"; }'
  mk pinnedfull 'setup() { git -C "$REPO" show 808c0960917e6d5d2323280d24af522c9b4dd7ea:bin/cc-thing > "$PRE"; }'
  # GREEN — THE POSITIVE CONTROL FOR THE TOO-WIDE DIRECTION. An executed line that MENTIONS the
  # phrase inside a string it is asserting about. tests/cc-dispatch-projects.bats:359, verbatim shape.
  mk mention   'setup() { grep -q "git show origin/main:<path>" "$C/brief-proj-b-1.txt" || false; }'
  # GREEN — the defect described in PROSE. ~40 lines in tests/ do exactly this.
  mk prose     '# The pre-fix control is `git show origin/main:bin/cc-thing` — never a mutant.
setup() { true; }'
  # GREEN — `push`, not `show`. `HEAD:refs/heads/main` is the ordinary land shape, 20+ sites.
  mk push      'setup() { git -C "$d" push -q origin HEAD:refs/heads/main; }'
  # GREEN — a different verb entirely (KNOWN LIMIT: cat-file is out of scope by construction).
  mk catfile   'setup() { git -C "$R" cat-file -e origin/main:tests/bad.bats; }'
  # GREEN — `show-ref` is not `show`, and a prefix match would flag it.
  mk showref   'setup() { git -C "$R" show-ref --verify refs/heads/main; }'

  fails=0
  red()   { lint_dir "$d/$1" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: $2"; fails=1; }; }
  green() { lint_dir "$d/$1" "" >/dev/null 2>&1  || { echo "SELFTEST FAIL: $2"; fails=1; }; }

  red   cmdsub     "a show inside a COMMAND SUBSTITUTION did not go RED — naive quote pairing dropped the token"
  red   mainref    "origin/main:<path> did not go RED — the whole subject of this lint"
  red   headref    "HEAD:<path> did not go RED — HEAD moves with every commit"
  red   bareref    "a bare branch name (main:<path>) did not go RED"
  red   branchref  "a slashed branch name (feat/x:<path>) did not go RED"
  red   expansion  "a ref that strips to an unreadable expansion did not go RED — an unauditable pin"
  red   nogit      "a show through \$GIT_BIN did not go RED — the rule must not require a literal git token"
  red   dangling  "a site behind a DANGLING quote did not go RED — the stripper failed OPEN and the violation walked"
  green pinned     "an abbreviated literal sha went RED — that is the prescribed fix"
  green pinnedfull "a full 40-char sha went RED"
  green mention    "the phrase MENTIONED inside an asserted string went RED — invocation vs mention lost"
  green prose      "the defect described in a COMMENT went RED — prose is not a control"
  green push       "git push origin HEAD:refs/heads/main went RED — push is not show"
  green catfile    "git cat-file origin/main:<path> went RED — out of scope by construction"
  green showref    "git show-ref went RED — a prefix match, not a verb match"

  # the ratchet, both directions
  lint_dir "$d/mainref" "zz-fixture.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered moving-ref control did not go GREEN"; fails=1; }
  lint_dir "$d/pinned"  "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted suite did not go RED (ratchet not shrinking)"; fails=1; }
  # own-scope, all four states
  lint_dir "$d/mainref" "" "other.bats"      >/dev/null 2>&1 || { echo "SELFTEST FAIL: a violation OUTSIDE the own-set blocked — this is the fleet-wide stop the deferral feared"; fails=1; }
  lint_dir "$d/mainref" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a violation INSIDE the own-set did not block — own-scope disabled the rule"; fails=1; }
  lint_dir "$d/mainref" "" ""                >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty collapsed into unset"; fails=1; }
  lint_dir "$d/mainref" ""                   >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }
  # the real tree must be clean, and a bad dir is a NON-VERDICT (2), never a stale-allowlist claim
  lint_dir "$ROOT/tests" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: the real tree carries an unlisted moving-ref control"; fails=1 ;;
  esac
  lint_dir "$d/nope" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  if [ "$fails" -eq 0 ]; then
    echo "moving-ref-control-lint --selftest: 23/23 — RED on origin/main, HEAD, a bare branch, a slashed branch, an unreadable expansion, a show through \$GIT_BIN, a show inside a COMMAND SUBSTITUTION (the live shape this lint could not see until 2026-09-02), and a site behind a dangling quote; GREEN on an abbreviated sha, a full sha, the phrase MENTIONED in an asserted string, a comment, push HEAD:refs/heads/main, cat-file and show-ref; ratchet fires both ways; own-scope blocks INSIDE / advises OUTSIDE / passes set-empty / stays strict when absent; real tree clean; LOUD on a bad dir."
    exit 0
  fi
  echo "moving-ref-control-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

if [ -n "${CC_MOVINGREF_OWN+set}" ]; then
  lint_dir "${1:-$ROOT/tests}" "${CC_MOVINGREF_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_MOVINGREF_OWN"
else
  lint_dir "${1:-$ROOT/tests}" "${CC_MOVINGREF_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
exit $?
