#!/usr/bin/env bash
# rules-hook-budget-lint.sh — keep the ALWAYS-LOADED project rules file a HOOK tier, not a body tier.
#
# ── WHAT THIS REFUSES, AND WHY IT IS A GATE RATHER THAN A NOTE ───────────────────────────────────
# `.claude/rules/agent-operating-lessons.md` is injected into every session in this repo, in full.
# On 2026-09-17 it measured 190,960 chars (~48K tokens a session) against a product warn cap of
# 150,000, because 70 of its 121 lessons had been pasted in WHOLE — hook and body together — at an
# average of 2,442 chars, while the 29 that used the repo's own hook+link shape averaged 289. The
# bodies moved to docs/lessons/<slug>.md and the file fell to ~45K for the same 121 rules.
#
# The convention that produced that is written in the file's own header. A convention in a header
# is executed by nothing — this repo's corpus records that shape repeatedly (a checker's population
# resting on an untested belief; a cited mechanism existing only in prose). The append rate is
# 1-3 lessons/day, so an unenforced convention re-inflates the file inside a quarter. Hence a gate,
# at the land, where the act happens.
#
# TWO refusals, both mechanical:
#   (1) a BODYLESS bullet — link target `.` — which is the exact shape the cleanup removed. It
#       means a body was never written and the evidence is riding on the resident surface.
#   (2) an OVER-BUDGET bullet. The budget is per-bullet and generous; a lesson that cannot state
#       its rule inside it is carrying evidence that belongs in its body file.
#
# 🚨 IT REFUSES ON SHAPE, NEVER ON TOTAL SIZE. A whole-file byte ceiling would convict a land that
# added one well-formed hook to a file someone else had already inflated — attribution by
# reachability, which this repo has measured as the wrong polarity. Every finding here names a
# LINE the land can fix.
#
# ── OWN-SCOPE: BLOCK ON WHAT THIS LAND ADDED, REPORT THE REST ────────────────────────────────────
# Measured on this lint's own first run: a rebase onto a moved trunk brought in three sibling
# bullets, and a whole-file verdict duly convicted THIS land for lines that were on trunk before it
# started — attribution by reachability, the polarity this repo has measured as wrong. With
# --own-range <gitrange> a finding on a line the range did not ADD is printed as `advisory:` and
# does not set the exit code. Coverage is not lost by doing this: every bodyless bullet is ADDED by
# some land, and that land's own diff contains it, so the blocking set is exactly the guilty set.
# Fails CLOSED — if the diff cannot be read, the run is a NON-VERDICT rather than an all-advisory
# pass, because "I could not tell who added it" must never render as "nobody did".
#
# Exit: 0 clean · 1 findings · 2 NON-VERDICT (could not run / could not trust its parse). A 2 is
# never a pass — the caller arms a non-verdict, exactly as the other ratchets do.
#
# ── TWO FILES SINCE 2026-09-23 ────────────────────────────────────────────────────────────────
# The rules file was split into a resident half (same path) and agent-operating-lessons-situational.md,
# so a per-account claudeMdExcludes glob can drop the situational half
# (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md). Both load by default and both are
# hook tiers, so with no --file this lints BOTH, and adds one arm neither per-file scan can see: a
# body linked from both files, or one bullet line present in both, is one rule loaded twice. A
# missing situational file is skipped (a project that never split has only the one file); a missing
# resident file stays a NON-VERDICT.
#
# The land calls this once per changed rules file with --file (ship-land.sh, rules_own loop), so
# --file naming either half also runs the cross-file arm whenever the other half exists. Without
# that, the arm would never run where it matters: a rebase through `merge=union` can copy the
# original's tail back into the resident file, and only the cross-file arm sees it
# (docs/research/token-efficiency-2026-09-23/implement/F4-project-rules-split.review.md, major 1-2).
#
# RESIDENT ADDS. Under --own-range, a bullet the range adds to the resident file is refused unless
# the same range removes that line from one of the two files (a move or a re-indent, as the split
# itself does). New lessons go to the situational file; copies of the rotor, drain and nudge that
# predate the split keep appending to the resident file until their sessions end, and this is what
# stops them. RULES_RESIDENT_ADD_OK=1 turns it advisory for a lesson that really must load in every
# session.
#
# Usage: rules-hook-budget-lint.sh [--file <path>] [--own-range <gitrange>] [--selftest]
set -u

RULES_REL=".claude/rules/agent-operating-lessons.md"
SIT_REL=".claude/rules/agent-operating-lessons-situational.md"
OWN_RANGE="${OWN_RANGE:-}"
BUDGET="${RULES_HOOK_BUDGET:-420}"

usage() { echo "usage: $0 [--file <path>] [--own-range <gitrange>] [--selftest]" >&2; }

# added_lines <file> → prints the NEW-file line numbers $OWN_RANGE adds to <file>; rc 2 if unreadable
added_lines() {
  local f="$1" d
  d=$(git diff -U0 "$OWN_RANGE" -- "$f" 2>/dev/null) || return 2
  printf '%s\n' "$d" | awk '
    /^@@ / { if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
               spec=substr($0, RSTART+1, RLENGTH-1); ci=index(spec, ",")
               if (ci) { st=substr(spec,1,ci-1)+0; ln=substr(spec,ci+1)+0 } else { st=spec+0; ln=1 }
               for (i=0; i<ln; i++) print st+i } }'
  return 0
}

scan() {  # scan <file> → 0 clean, 1 findings, 2 non-verdict
  local f="$1" n=0 bodyless=0 over=0 dup=0 line=0 adv=0
  [ -f "$f" ] || { echo "rules-hook-budget-lint: NON-VERDICT — no such file: $f" >&2; return 2; }
  local OWN_SET=""
  if [ -n "${OWN_RANGE:-}" ]; then
    OWN_SET="$(added_lines "$f")" || {
      echo "rules-hook-budget-lint: NON-VERDICT — could not read the diff for $OWN_RANGE -- $f, so" >&2
      echo "  attribution is unknown; refusing to render that as 'nobody added it'." >&2
      return 2; }
    OWN_SET=" $(printf '%s' "$OWN_SET" | tr '\n' ' ') "
  fi
  # mine <line> → 0 when this land added it (or when no range was given, i.e. judge everything)
  _mine() { [ -z "${OWN_RANGE:-}" ] && return 0; case "$OWN_SET" in *" $1 "*) return 0 ;; esac; return 1; }
  # A bullet is a top-level '- [..](..)' line. Anything else (prose, tables, html comments) is not
  # judged: the header is deliberately long and is not a lesson.
  while IFS= read -r l; do
    line=$((line+1))
    case "$l" in '- ['*|'- **['*) ;; *) continue ;; esac
    printf '%s' "$l" | grep -q '](' || continue
    n=$((n+1))
    if printf '%s' "$l" | grep -q '](\.)'; then
      if _mine "$line"; then bodyless=$((bodyless+1)); else adv=$((adv+1)); printf 'advisory: '; fi
      printf '%s:%d: BODYLESS — the link target is a bare dot, so this lesson has no body file.\n' "$f" "$line"
      printf '    Write the body to docs/lessons/<slug>.md and link ../../docs/lessons/<slug>.md here.\n'
      continue
    fi
    local len; len=$(printf '%s' "$l" | wc -c | tr -d ' ')
    case "$len" in ''|*[!0-9]*) echo "rules-hook-budget-lint: NON-VERDICT — unreadable length at line $line" >&2; return 2 ;; esac
    if [ "$len" -gt "$BUDGET" ]; then
      if _mine "$line"; then over=$((over+1)); else adv=$((adv+1)); printf 'advisory: '; fi
      printf '%s:%d: OVER BUDGET — %d chars > %d. Move the evidence (counts, shas, dates, incident\n' "$f" "$line" "$len" "$BUDGET"
      printf '    narrative) into the linked body and leave a hook that still STATES its rule.\n'
    fi
  done < "$f"
  # DUPLICATE LINK TARGETS. Two bullets pointing at one body are two copies of one rule paying
  # resident budget twice, and they are silent — nothing else in the chain compares bullets to each
  # other. Found live: a rebase onto a moved trunk re-introduced three lessons this land had already
  # tiered, and a fourth pair predated the land entirely. Always blocking: a duplicate is a property
  # of the PAIR, so "who added it" has two answers and own-scope cannot arbitrate between them.
  # A bare `.` is EXCLUDED: it is the bodyless marker, not a body, so two bullets carrying it are
  # two separate defects the BODYLESS arm already names — not one rule stored twice.
  local dups
  dups=$(grep -oE '^- \*{0,2}\[[^]]*\]\([^)]*\)' "$f" 2>/dev/null \
         | sed -E 's/.*\(([^)]*)\)$/\1/' | grep -v '^\.$' | sort | uniq -d)
  if [ -n "$dups" ]; then
    while IFS= read -r _d; do
      [ -n "$_d" ] || continue
      dup=$((dup+1))
      printf '%s: DUPLICATE — two or more bullets link %s. One rule, resident twice. Keep the\n' "$f" "$_d"
      printf '    better hook and delete the other; the body file is shared and stays.\n'
    done <<< "$dups"
  fi
  if [ "$n" -eq 0 ]; then
    echo "rules-hook-budget-lint: NON-VERDICT — parsed 0 bullets in $f; the anchor no longer matches the file." >&2
    return 2
  fi
  [ "$adv" -gt 0 ] && printf 'rules-hook-budget-lint: %d advisory finding(s) on lines this land did not add — not blocking.\n' "$adv" >&2
  if [ $((bodyless+over+dup)) -gt 0 ]; then
    printf 'rules-hook-budget-lint: %d finding(s) over %d bullet(s) — bodyless=%d over-budget=%d duplicate=%d\n' \
      "$((bodyless+over+dup))" "$n" "$bodyless" "$over" "$dup" >&2
    return 1
  fi
  printf 'rules-hook-budget-lint: clean — %d bullet(s), all bodied and within %d chars\n' "$n" "$BUDGET" >&2
  return 0
}

# ── --selftest: the detector must DISCRIMINATE, or its clean verdict means nothing ───────────────
# Three arms. A clean fixture must pass, and EACH refusal must fire on its own — a selftest that
# only proves the red case cannot tell a working lint from one that refuses everything.
selftest() {
  local d rc fail=0
  d=$(mktemp -d) || { echo "selftest: NON-VERDICT — mktemp failed" >&2; return 2; }
  trap 'rm -rf "$d"' RETURN

  printf '# rules\n\n- [Ok](../../docs/lessons/a.md) — a hook that states its rule inside the budget.\n' > "$d/clean.md"
  scan "$d/clean.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] || { echo "selftest: clean fixture returned $rc, want 0" >&2; fail=1; }

  printf '# rules\n\n- [Bad](.) — a lesson pasted whole with no body file.\n' > "$d/bodyless.md"
  scan "$d/bodyless.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || { echo "selftest: bodyless fixture returned $rc, want 1" >&2; fail=1; }

  { printf '# rules\n\n- [Fat](../../docs/lessons/b.md) — '; \
    awk 'BEGIN{for(i=0;i<500;i++)printf "x"}'; printf '\n'; } > "$d/fat.md"
  scan "$d/fat.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] || { echo "selftest: over-budget fixture returned $rc, want 1" >&2; fail=1; }

  printf '# rules\n\nno bullets here at all\n' > "$d/nobullets.md"
  scan "$d/nobullets.md" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] || { echo "selftest: no-bullet fixture returned $rc, want 2 (non-verdict)" >&2; fail=1; }

  if [ "$fail" -eq 0 ]; then echo "rules-hook-budget-lint --selftest: PASS (4 arms)" >&2; return 0; fi
  echo "rules-hook-budget-lint --selftest: FAIL" >&2; return 1
}

FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) shift; FILE="${1:-}"; [ -n "$FILE" ] || { usage; exit 2; } ;;
    --file=*) FILE="${1#--file=}" ;;
    --own-range) shift; OWN_RANGE="${1:-}"; [ -n "$OWN_RANGE" ] || { usage; exit 2; } ;;
    --own-range=*) OWN_RANGE="${1#--own-range=}" ;;
    --selftest) selftest; exit $? ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done
# cross_file <resident> <situational> → 0 clean, 1 findings. Always blocking, like the in-file
# duplicate arm: a duplicate is a property of the pair, so own-scope cannot say who added it.
cross_file() {
  local res="$1" sit="$2" xd xl bad=0
  _targets() { grep -oE '^- \*{0,2}\[[^]]*\]\([^)]*\)' "$1" 2>/dev/null | sed -E 's/.*\(([^)]*)\)$/\1/' | sort -u; }
  xd=$( { _targets "$res"; _targets "$sit"; } | grep -v '^\.$' | sort | uniq -d)
  if [ -n "$xd" ]; then
    while IFS= read -r _d; do
      [ -n "$_d" ] || continue
      bad=$((bad+1))
      printf '%s + %s: DUPLICATE — both files link %s. One rule, loaded twice. Keep it in one file.\n' \
        "$res" "$sit" "$_d"
    done <<< "$xd"
  fi
  # Unlinked bullets (rotor `- demoted …` pointers, nested topic lines) have no link target to
  # compare, so compare the lines themselves, whitespace-trimmed.
  _lines() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' "$1" 2>/dev/null | grep -E '^- ' | grep -vF '](' | sort -u; }
  xl=$( { _lines "$res"; _lines "$sit"; } | sort | uniq -d)
  if [ -n "$xl" ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      bad=$((bad+1))
      printf '%s + %s: DUPLICATE — this line is in both files: %s\n' "$res" "$sit" "$(printf '%s' "$_l" | cut -c1-100)"
    done <<< "$xl"
  fi
  [ "$bad" -eq 0 ] && return 0
  printf 'rules-hook-budget-lint: %d cross-file duplicate(s) between the resident and situational files\n' "$bad" >&2
  return 1
}

# resident_adds <resident> <situational> → 0 clean, 1 findings, 2 non-verdict. Needs OWN_RANGE.
resident_adds() {
  local res="$1" sit="$2" d hits
  d=$(git diff -U0 "$OWN_RANGE" -- "$res" "$sit" 2>/dev/null) || {
    echo "rules-hook-budget-lint: NON-VERDICT — could not read the diff for $OWN_RANGE -- $res $sit" >&2; return 2; }
  hits=$(printf '%s\n' "$d" | awk -v resbase="$(basename "$res")" '
    function norm(x) { sub(/^[ \t]+/, "", x); sub(/[ \t\r]+$/, "", x); return x }
    /^\+\+\+ / { p = $2; n = split(p, a, "/"); cur = a[n]; next }
    /^--- / { next }
    /^-/ { rm[norm(substr($0, 2))] = 1; next }
    /^\+/ { if (cur == resbase) { l = norm(substr($0, 2)); if (l ~ /^- /) add[++k] = l }; next }
    END { for (i = 1; i <= k; i++) if (!(add[i] in rm)) print add[i] }')
  [ -n "$hits" ] || return 0
  local tag="" rc=1
  if [ "${RULES_RESIDENT_ADD_OK:-0}" = 1 ]; then tag="advisory: "; rc=0; fi
  while IFS= read -r _h; do
    [ -n "$_h" ] || continue
    printf '%s%s: RESIDENT ADD — this land adds a bullet to the resident file: %s\n' "$tag" "$res" "$(printf '%s' "$_h" | cut -c1-100)"
  done <<< "$hits"
  printf '    New lessons go in %s. If this one must load in every session, re-run with RULES_RESIDENT_ADD_OK=1.\n' "$sit"
  return "$rc"
}

# pair_of <file> → prints "<resident> <situational>" when <file> is either half, else nothing
pair_of() {
  local dir base; dir=$(dirname "$1"); base=$(basename "$1")
  case "$base" in
    agent-operating-lessons.md) printf '%s\t%s\n' "$1" "$dir/agent-operating-lessons-situational.md" ;;
    agent-operating-lessons-situational.md) printf '%s\t%s\n' "$dir/agent-operating-lessons.md" "$1" ;;
  esac
}

# The worst verdict wins (2 > 1 > 0).
worst=0
_take() { [ "$1" -gt "$worst" ] && worst=$1; return 0; }
if [ -n "$FILE" ]; then
  scan "$FILE"; _take $?
  pair=$(pair_of "$FILE")
  if [ -n "$pair" ]; then
    RES=${pair%%$'\t'*}; SIT=${pair#*$'\t'}
    if [ -f "$RES" ] && [ -f "$SIT" ]; then
      cross_file "$RES" "$SIT"; _take $?
      if [ -n "$OWN_RANGE" ] && [ "$FILE" = "$RES" ]; then resident_adds "$RES" "$SIT"; _take $?; fi
    fi
  fi
  exit "$worst"
fi

# No --file: both halves, then the cross-file arm.
scan "$RULES_REL"; _take $?
if [ -f "$SIT_REL" ]; then
  scan "$SIT_REL"; _take $?
  cross_file "$RULES_REL" "$SIT_REL"; _take $?
  if [ -n "$OWN_RANGE" ]; then resident_adds "$RULES_REL" "$SIT_REL"; _take $?; fi
fi
exit "$worst"
