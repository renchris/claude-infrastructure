#!/bin/bash
# shellcheck disable=SC2016  # file-wide: every --selftest fixture body is written VERBATIM into a
# shell file, where an awk program's `$0`, `$1` and `{n,m}` must arrive UNEXPANDED or the case
# asserts nothing, and the guidance text prints the literal fix an author must paste.
# awk-interval-lint — a RATCHET on INTERVAL EXPRESSIONS ({n} / {n,} / {n,m}) inside awk programs.
#
# WHY: the rule already existed as prose and it rotted. scripts/typed-send-lint.sh:164 states it
# outright — "No interval expressions ({n,m}) anywhere in the program: the classic one-true-awk that
# ships as /usr/bin/awk on this box has not always supported them, and a silently-unmatched pattern
# here is a false GREEN" — and that comment is the ONLY place it was enforced. Censused
# 2026-08-26: EIGHT interval sites across SIX other files, two of them ratchets and one of them the
# sensor a dispatch brief's PLAN-OPEN SNAPSHOT is generated from. A rule that lives in one file's
# comment binds one file. (memory: enforcement-must-live-at-the-chokepoint)
#
# THE TWO FAILURES, and the second is why this is a lint and not a fourth paragraph of prose:
#   · NO INTERVAL SUPPORT AT ALL — the classic one-true-awk. `{7,40}` is then a LITERAL brace run,
#     so `/^[0-9a-f]{7,40}$/` matches the string `[0-9a-f]{7,40}` and nothing else. Every site goes
#     silently, permanently negative: a lint answers "clean", a detector answers "nothing found".
#   · PARTIAL INTERVAL SUPPORT — MEASURED, and worse, because the sites still fire and lie.
#     mawk 1.3.4 20240123 (Debian/Ubuntu default /usr/bin/awk, and the awk in the Linux VMs this
#     repo's cloud lane runs in) accepts `{m,n}` and then matches EXACTLY m whenever m >= 2:
#
#         echo aaaaaaaaa | awk '{print ($0 ~ /^a{2,9}$/) ? "M" : "no"}'   →  no
#         echo 2026      | awk '{print ($0 ~ /^[0-9]{2,4}$/) ? "M" : "no"}' →  no
#         echo 2026      | awk '{print ($0 ~ /^[0-9]{4}$/)   ? "M" : "no"}' →  M
#
#     `{m}` exact is correct there and `{0,n}` / `{1,n}` are correct there; only m >= 2 with an
#     upper bound or an open `{m,}` is wrong. THE LINT DOES NOT ENCODE THAT SPLIT, deliberately —
#     the first failure above takes every shape including `{4}`, and a rule that admitted the
#     shapes one implementation happens to get right would be a rule about mawk, not about awk.
#
# MEASURED HARM, on this repo, both directions on one artifact (scripts/plan-phase-scan.sh, whose
# `/[0-9a-f]{7,40}/` is what a plan's `commit_hashes` field is built from):
#     heading                        gawk 5.2.1            mawk 1.3.4
#     ce7651b02a17            →      ce7651b02a17          ce7651b            (TRUNCATED)
#     a1b2c3d4e5f6a7b8        →      a1b2c3d4e5f6a7b8      a1b2c3d, 4e5f6a7   (FABRICATED — two
#                                                                              shas nobody wrote)
#     1234567abcdef           →      1234567abcdef         (none)             (MISSED, and the
#                                                                              section flipped
#                                                                              DONE → PENDING)
# and scripts/moving-ref-control-lint.sh, whose `/^[0-9a-f]{7,40}$/` decides which refs are PINNED,
# reported TEN correctly-pinned suites as MOVING refs — each told to "replay a LITERAL sha" that it
# already replays. Neither failure is visible from the file: an interval site reads correct.
#
# THE RULE. Inside an awk PROGRAM BODY, a `{` followed by digits and closed by `}` or `,digits}` is
# a violation. Two subtractions, both load-bearing:
#   (a) COMMENT LINES ARE DROPPED FIRST. This file, and the fixed sites, explain the defect using
#       the offending spelling. A lint that flagged its own documentation would teach people to
#       ignore it. (Same subtraction, same reason, as moving-ref-control-lint.)
#   (b) An awk ACTION BLOCK is not a violation: `{ print $1 }` has no digit adjacent to the brace,
#       and the pattern requires `{<digits>`. `{7,40}` and `{4}` are the only shapes matched.
#
# WHAT COUNTS AS A PROGRAM BODY: the single-quoted argument of an `awk` invocation — the only form
# this repo uses. STATED LIMITS, rather than hidden:
#   · `awk -f prog.awk` and a double-quoted program are NOT scanned. No such site exists today
#     (checked 2026-08-26); do not read a green here as "no interval expression anywhere".
#   · A DYNAMICALLY built regex (`$0 ~ "^a{" n ",9}$"`) is not caught — the interval is assembled at
#     runtime and no literal appears in the file. Same class, out of a grep's reach.
#   · A program body containing an escaped apostrophe cannot exist in shell single quotes, so the
#     body always ends at the next `'`. That is what makes the extraction exact rather than a guess.
#
# Exit: 0 = clean · 1 = violation / stuck ratchet entry · 2 = bad usage or unreadable scan root
#       (LOUD, never silent-green)
#
# Env seams: CC_AWKINT_ALLOWLIST overrides the embedded ratchet · CC_AWKINT_OWN scopes which
# violations may BLOCK (three-state contract, identical to moving-ref-control-lint).
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

# ── the ratchet: files grandfathered with an interval expression. ONLY EVER DELETE LINES. ─────────
# EMPTY BY CONSTRUCTION. All eight known sites were repaired in the same diff that landed this lint,
# so there is no grandfathered debt to erode. An entry added later must carry the same standard its
# sibling ratchets use — CHECKED and explained, never an unexamined hit; that is how a ratchet
# decays into an exemption list.
EMBEDDED_ALLOWLIST=""

# OWN-SCOPE — THREE states, and `${VAR:-}` cannot express them: own-set ABSENT ⇒ strict whole-tree;
# SET-BUT-EMPTY ⇒ "I change no file" ⇒ nothing blocks; SET ⇒ block on those only. Presence rides on
# argument count here and on `${CC_AWKINT_OWN+set}` at the entry point.
in_own() {  # $1=path · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  # `grep -xF … >/dev/null` and not `grep -q`: under `set -o pipefail` an early-exiting consumer
  # SIGPIPEs its producer and the pipeline reports 141, so a MATCH would read as a failure
  # (scripts/pipefail-sigpipe-lint.sh). Draining costs nothing on a list this size.
  printf '%s\n' "$2" | grep -xF "$1" >/dev/null
}

in_allowlist() { printf '%s\n' "$2" | grep -xF "$1" >/dev/null; }   # drained — see in_own

# Interval sites across every file named on stdin: "<path>\t<lineno>\t<interval>", one per line.
#
# ONE awk pass for the WHOLE population, not one fork per file: 262 awk-bearing files here, and a
# fork each cost 5.2 s against 0.3 s for a single pass — a gate is only run if it is cheap enough to
# leave on. The scanner itself carries no interval expression, because a detector written in the
# shape it forbids could not report on the awk that cannot run it.
interval_sites() { # file list on stdin
  xargs awk '
    # A three-state walk over the whole file. ARMED means the word `awk` (or gawk/mawk/nawk, or a
    # path ending in one) has been seen and the NEXT apostrophe opens its program body. INPROG means
    # we are inside that body, which ends at the next apostrophe — a shell single-quoted string
    # cannot contain one, so the end is exact rather than a guess. Both states survive a line break,
    # which is what lets a `\`-continued invocation and a multi-line program be read.
    BEGIN { SQ = "\047" }
    FNR == 1 { inprog = 0; armed = 0 }        # state is per FILE, never carried across one

    function tokrun(s, p,   q) {          # the [A-Za-z0-9_./-] run starting at p, "" if none
      q = p
      while (q <= length(s) && substr(s, q, 1) ~ /[A-Za-z0-9_.\/-]/) q++
      return substr(s, p, q - p)
    }

    {
      line = $0
      out = ""                      # the part of THIS line that is program body
      i = 1
      while (i <= length(line)) {
        c = substr(line, i, 1)

        if (inprog) {
          if (c == SQ) { inprog = 0; i++; continue }
          out = out c; i++; continue
        }

        if (c == SQ) {
          if (armed) { armed = 0; inprog = 1; i++; continue }
          # An apostrophe outside an armed invocation opens some OTHER quoted string. Skip to its
          # end so a {7,40} in an unrelated sed/grep argument is never read as an awk program.
          j = index(substr(line, i + 1), SQ)
          if (j == 0) { i = length(line) + 1; continue }
          i = i + j + 1; continue
        }

        # A SHELL comment outside a program body ends the line and disarms: a prose mention of awk
        # must not arm the machine and capture the next unrelated quoted string.
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:]]/)) { armed = 0; break }

        if (i == 1 || substr(line, i - 1, 1) !~ /[A-Za-z0-9_.\/-]/) {
          tok = tokrun(line, i)
          if (tok != "") {
            if (tok ~ /awk$/) armed = 1
            i = i + length(tok); continue
          }
        }
        i++
      }
      # THE ARM DIES AT END OF LINE unless the line is continued. Without this the word `awk` in
      # ordinary prose ("...depends on WHICH awk runs it...") arms the machine, and the next
      # apostrophe anywhere below — an English possessive is enough — opens a program body that
      # never closes. Measured on THIS file before the guard: ten violations, every one of them a
      # `{n,m}` inside a quoted GUIDANCE STRING. Invocation vs mention, the same discriminator
      # moving-ref-control-lint draws, drawn here in the axis a shell gives us for free.
      if (armed && line !~ /\\$/) armed = 0

      if (out == "") next
      # An awk COMMENT line inside the body — prose about the defect is not the defect.
      if (out ~ /^[[:space:]]*#/) next
      rest = out
      while (match(rest, /\{[0-9]+(,[0-9]*)?\}/)) {
        printf "%s\t%d\t%s\n", FILENAME, FNR, substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' 2>/dev/null
}

# lint_root <dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan root
lint_root() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f rel bad=0 seen=0 other=0 stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$dir" ] || { echo "awk-interval-lint: ⛔ not a directory: $dir" >&2; return 2; }

  local files sites
  # THE ONE STRUCTURAL EXCLUSION, and it is this file only. --selftest writes its RED fixtures as
  # heredocs INSIDE this script, so every shape the lint must catch is present here as data; a lint
  # that flagged its own fixtures could never report clean. The detector living here is not thereby
  # unguarded: --selftest scans those same fixtures as real files on disk (RED, all six shapes),
  # tests/awk-interval-lint.bats re-runs that from a pristine checkout, and the exclusion is pinned
  # to exactly one basename so it cannot widen into an exemption list.
  files="$(find "$dir" -type f \( -name '*.sh' -o -name '*.bats' -o -path '*/bin/*' \) 2>/dev/null \
             | grep -v '/\.git/' | grep -v '/awk-interval-lint\.sh$' | sort)"
  [ -n "$files" ] || { echo "awk-interval-lint: ⛔ no shell files under $dir" >&2; return 2; }

  # THE POPULATION IS THE AWK-BEARING FILES, and it is computed in ONE grep rather than 262 — the
  # whole point of a gate being cheap is that nobody is tempted to turn it off.
  local awkfiles offenders
  awkfiles="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -l 'awk' 2>/dev/null | sort)"
  seen="$(printf '%s\n' "$awkfiles" | grep -c . || true)"

  # ONE awk over that population; the per-file verdicts are read back out of its output.
  sites="$(printf '%s\n' "$awkfiles" | interval_sites)"
  offenders="$(printf '%s\n' "$sites" | cut -f1 | grep -v '^$' | sort -u)"

  # relkey <abs-path> — the report key: repo-relative when the file is inside the repo, since that
  # is the spelling `git diff --name-only` produces and own-scope must compare like with like. A
  # file outside the repo (a fixture tree under mktemp) keys off the SCAN root instead, so both
  # mechanisms stay testable without a checkout.
  relkey() {
    case "$1" in
      "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
      "$dir"/*)  printf '%s\n' "${1#"$dir"/}"  ;;
      *)         printf '%s\n' "$1"            ;;
    esac
  }

  # The offenders' report keys, computed ONCE — the ratchet's other direction reads them back and a
  # per-entry re-derivation would fork relkey for every allowlist line on every file.
  local offrels=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    offrels="$offrels$(relkey "$f")
"
  done <<EOF
$offenders
EOF

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="$(relkey "$f")"
    in_allowlist "$rel" "$allow" && continue      # grandfathered — known site, already on the list
    if in_own "$rel" "$own" "$own_scoped"; then
      printf '  AWK-INTERVAL %s: an interval expression inside an awk program\n' "$rel"
      printf '%s\n' "$sites" | awk -F'\t' -v want="$f" -v rel="$rel" \
        '$1 == want { printf "               %s:%s:%s\n", rel, $2, $3 }'
      bad=$((bad + 1))
    else
      printf '  interval?    %s: interval expression (NOT in your diff — advisory, not blocking)\n' "$rel"
      other=$((other + 1))
    fi
  done <<EOF
$offenders
EOF

  # The ratchet's other direction: an allowlisted file that no longer offends must lose its line.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$offrels" | grep -xF "$rel" >/dev/null && continue
    if in_own "$rel" "$own" "$own_scoped"; then
      printf '  RATCHET      %s carries no interval expression now — delete its allowlist line\n' "$rel"
      stuck=$((stuck + 1))
    else
      printf '  ratchet?     %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$rel"
      other=$((other + 1))
    fi
  done <<EOF
$allow
EOF

  [ "$other" -eq 0 ] || echo "awk-interval-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bad" -gt 0 ]; then
    echo "awk-interval-lint: ⛔ $bad file(s) above use an interval expression inside an awk program."
    echo "  Why it matters: the answer depends on WHICH awk runs it, and both wrong answers are silent."
    echo "  An awk with no interval support matches the literal braces, so the site goes permanently"
    echo "  negative; mawk 1.3.4 accepts {m,n} and matches EXACTLY m for m>=2, so a bounded run is"
    echo "  truncated — measured on plan-phase-scan.sh, where ce7651b02a17 was reported as ce7651b,"
    echo "  a1b2c3d4e5f6a7b8 became TWO shas nobody wrote, and 1234567abcdef vanished and took its"
    echo "  section's DONE status with it."
    echo "  Fix: spell the repetition out, and put any BOUND in code where every awk agrees."
    echo "    /^[0-9a-f]{7,40}\$/   ->  ref ~ /^[0-9a-f]+\$/ && length(ref) >= 7 && length(ref) <= 40"
    echo "    /^#{1,6} /           ->  /^(#|##|###|####|#####|######) /"
    echo "    /^\\[[0-9]{4}-/        ->  /^\\[[0-9][0-9][0-9][0-9]-/"
    echo "    /^\\.{0,2}\\//          ->  /^\\.?\\.?\\//"
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "awk-interval-lint: ⛔ $stuck file(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "awk-interval-lint: clean — $seen awk-bearing file(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 interval expressions."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
selftest() {
  local d fails=0
  d="$(mktemp -d)"
  trap 'rm -rf "$d"' RETURN

  mk() { mkdir -p "$d/$1"; cat > "$d/$1/f.sh"; }

  # RED cases — an interval expression that a live awk program will execute.
  mk bounded  <<'FIX'
#!/bin/bash
awk '{ if ($0 ~ /^[0-9a-f]{7,40}$/) print "pinned" }' "$1"
FIX
  mk exact    <<'FIX'
#!/bin/bash
awk '/^\[[0-9]{4}-/ { print }' "$1"
FIX
  mk openend  <<'FIX'
#!/bin/bash
awk '{ if ($0 ~ /^x{3,}$/) print }' "$1"
FIX
  mk zeromin  <<'FIX'
#!/bin/bash
awk '{ if ($1 ~ /^\.{0,2}\//) print }' "$1"
FIX
  mk multiline <<'FIX'
#!/bin/bash
awk '
  BEGIN { n = 0 }
  /^#{1,6} / { n++ }
  END { print n }
' "$1"
FIX
  mk dynamic_note <<'FIX'
#!/bin/bash
awk -v p="$P" '
  { if ($0 ~ /^[0-9]{2,4}$/) print }
' "$1"
FIX

  # GREEN cases — every shape that must NOT be flagged.
  mk fixed    <<'FIX'
#!/bin/bash
awk '{ if ($0 ~ /^[0-9a-f]+$/ && length($0) >= 7) print "pinned" }' "$1"
FIX
  mk prose    <<'FIX'
#!/bin/bash
awk '
  # This used to read /^[0-9a-f]{7,40}$/ and mawk truncated it — see awk-interval-lint.
  { if ($0 ~ /^[0-9a-f]+$/) print }
' "$1"
FIX
  mk action   <<'FIX'
#!/bin/bash
awk '{ print $1 }' "$1"
FIX
  mk notawk   <<'FIX'
#!/bin/bash
sed -E 's/^[0-9]{4}-[0-9]{2}//' "$1"
grep -E '^[a-f0-9]{7,40}$' "$1"
FIX
  mk shellbrace <<'FIX'
#!/bin/bash
v="${1:-}"
printf '%s\n' "${v}" | awk '{ print length($0) }'
FIX
  mk noawk    <<'FIX'
#!/bin/bash
echo '{7,40}'
FIX

  red()   { lint_root "$d/$1" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: $2"; fails=1; }; }
  green() { lint_root "$d/$1" "" >/dev/null 2>&1  || { echo "SELFTEST FAIL: $2"; fails=1; }; }

  red   bounded      "a bounded {7,40} did not go RED — the whole subject of this lint"
  red   exact        "an exact {4} did not go RED — a no-interval awk matches literal braces"
  red   openend      "an open-ended {3,} did not go RED"
  red   zeromin      "a {0,2} did not go RED — correct on mawk is not correct on every awk"
  red   multiline    "an interval on a LATER line of a multi-line program did not go RED"
  red   dynamic_note "an interval in an awk -v program did not go RED — the flag is not the body"
  green fixed        "an interval-FREE length() bound went RED — that is the prescribed fix"
  green prose        "an interval named in an awk COMMENT went RED — prose is not a program"
  green action       "a plain action block { print \$1 } went RED — a brace is not an interval"
  green notawk       "an interval in sed/grep -E went RED — those are not awk"
  green shellbrace   "a shell \${v} expansion beside an awk call went RED"
  green noawk        "a file with no awk program at all went RED"

  # the ratchet, both directions
  lint_root "$d/bounded" "f.sh" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered interval site did not go GREEN"; fails=1; }
  lint_root "$d/fixed"   "f.sh" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted file did not go RED (ratchet not shrinking)"; fails=1; }

  # own-scope, all four states
  lint_root "$d/bounded" "" "f.sh"       >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: own-scope INSIDE did not block"; fails=1; }
  lint_root "$d/bounded" "" "other/f.sh" >/dev/null 2>&1 || { echo "SELFTEST FAIL: own-scope OUTSIDE did not advise"; fails=1; }
  lint_root "$d/bounded" "" ""           >/dev/null 2>&1 || { echo "SELFTEST FAIL: own-scope SET-BUT-EMPTY did not pass"; fails=1; }
  lint_root "$d/bounded" ""              >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: own-set ABSENT was not strict"; fails=1; }

  # the real tree, and a LOUD non-verdict
  lint_root "$ROOT/scripts" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: the real scripts/ tree is not clean"; fails=1; }
  lint_root "$d/does-not-exist" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an unreadable scan root did not exit 2"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "awk-interval-lint --selftest: 20/20 — RED on a bounded, exact, open-ended, zero-min, later-line and -v-flag interval; GREEN on the length() fix, an interval in a comment, a plain action block, sed/grep -E, a shell brace expansion and a file with no awk; ratchet fires both ways; own-scope blocks INSIDE / advises OUTSIDE / passes set-empty / stays strict when absent; real tree clean; LOUD on a bad dir."
    return 0
  fi
  echo "awk-interval-lint --selftest: FAILED — the lint does not discriminate."
  return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -h|--help)
    sed -n '4,60p' "$SELF" | sed 's/^# \{0,1\}//'
    exit 0 ;;
esac

ALLOW="${CC_AWKINT_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
SCAN="${1:-$ROOT/scripts}"
if [ -n "${CC_AWKINT_OWN+set}" ]; then
  lint_root "$SCAN" "$ALLOW" "$CC_AWKINT_OWN"
else
  lint_root "$SCAN" "$ALLOW"
fi
exit $?
