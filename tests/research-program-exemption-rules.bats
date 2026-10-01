#!/usr/bin/env bats
# research-program-exemption-rules.bats — REPORT.md §8 item 3 / §3.1 ruling 2
# (docs/research/upfront-research-exhaustion-2026-09-30/): BOTH instruction variants carry the
# active-research-program exemption at every rule the report cites, and the exemption is keyed on
# the program registry (§10 open item 10, option 1), never on a DoD marker.
#
# The behavioral half: the check command the rule text tells a session to run is extracted from
# each variant and executed against a planted registry — an active program vs none — so the rule
# cannot name a command that does not answer.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never the operator's live ~/
  G="$REPO/CLAUDE.global.md"; S="$REPO/CLAUDE.global.slim.md"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/programs.json"
  PROG="$BATS_TEST_TMPDIR/prog"; mkdir -p "$PROG/wt" "$BATS_TEST_TMPDIR/elsewhere"
}

# The paragraph (blank-line delimited) holding the anchor text — a pointer must live WITH its rule.
para() { awk -v a="$2" 'BEGIN{RS=""} index($0, a) { print; exit }' "$1"; }

@test "global: every cited rule carries the active-program pointer" {
  para "$G" 'Below 90% conviction the research is MANDATORY' | grep -q 'Inside an ACTIVE research program'
  para "$G" '**F1 net-positive**' | grep -q 'apply-at-build list instead'                  # F1
  para "$G" '0 of 20 open decision packets stated a conviction' | grep -q 'timebox receipt satisfies'  # F2
  grep -F '| _E0_ read-only' "$G" | grep -q 'answered by relaying the certificate'           # E0 row
  para "$G" '**Offering is the defect**' | grep -q 'is not an offer'
}

@test "slim: every cited rule carries the active-program pointer" {
  grep -F -- '- F1 net-positive:' "$S" | grep -q 'apply-at-build list instead'
  grep -F -- '- F2 well-researched:' "$S" | grep -q 'timebox receipt satisfies'
  grep -F 'A close question ("are we done?"' "$S" | grep -q 'relaying the certificate'
  grep -F -- '- E0, read-only turn:' "$S" | grep -q 'relaying the certificate'
  grep -F 'Offering researched, in-scope remaining work' "$S" | grep -q 'is not an offer'
  grep -F 'Research to raise conviction under Follow-On Gate F2' "$S" | grep -q 'timebox receipt'
}

@test "both variants define the exemption on the registry, with all four rulings and the hook arm" {
  local f d
  for f in "$G" "$S"; do
    # the definition = from its own opening to the "Outside an active program" paragraph
    d="$(awk '/Active research program exemption\**\*? \(operator ruling/{p=1} p{print} p&&/^Outside an active program/{exit}' "$f")"
    [ -n "$d" ] || { echo "no definition in $f"; return 1; }
    printf '%s' "$d" | grep -q '83adb541ea19'
    printf '%s' "$d" | grep -q 'programs.json'
    printf '%s' "$d" | grep -q 'registered'
    printf '%s' "$d" | grep -q 'certifying'
    printf '%s' "$d" | grep -q 'certified'
    printf '%s' "$d" | grep -q "apply-at-build list"
    printf '%s' "$d" | grep -q 'research exhausted at timebox'
    printf '%s' "$d" | grep -q "next version"
    printf '%s' "$d" | grep -qi 'offer arm'
    printf '%s' "$d" | grep -q 'never a DoD marker'
  done
}

@test "the check command each variant names answers correctly against a planted registry" {
  local f cmd
  for f in "$G" "$S"; do
    cmd="$(grep -o 'bash[[:space:]]*~/.claude/scripts/lib/research-program.sh is-active' "$f" | head -1)"
    [ -z "$cmd" ] && cmd="$(tr '\n' ' ' < "$f" | grep -o 'bash ~/.claude/scripts/lib/research-program.sh is-active' | head -1)"
    [ -n "$cmd" ] || { echo "no check command in $f"; return 1; }
    cmd="${cmd/\~\/.claude\/scripts\/lib/$REPO/scripts/lib}"
    jq -n --arg r "$PROG" '{programs:[{slug:"pilot",aliases:[],cwd_roots:[$r],state:"certifying"}]}' > "$CC_RESEARCH_REGISTRY"
    ( cd "$PROG/wt" && /bin/bash -c "$cmd \"\$PWD\"" )                       # active ⇒ exit 0
    ! ( cd "$BATS_TEST_TMPDIR/elsewhere" && /bin/bash -c "$cmd \"\$PWD\"" 2>/dev/null ) || false # outside ⇒ 1
    rm -f "$CC_RESEARCH_REGISTRY"
    ! ( cd "$PROG/wt" && /bin/bash -c "$cmd \"\$PWD\"" 2>/dev/null ) || false # no registry ⇒ 1
  done
}
