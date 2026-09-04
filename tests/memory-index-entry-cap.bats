#!/usr/bin/env bats
# dim=entry — the PER-LINE cap on hooks/lib/memory-index-budget.sh, plus the nudge clamp that
# stops the advisory advertising a budget the gate will refuse.
#
# The defect this pins is not "index lines get long". It is that the OBVIOUS gate for that —
# "refuse any write whose result holds an over-cap line" — is a NON-TERMINATING LOOP on the index
# it was written for. Measured on reso's live index the day this shipped: 28 entry lines, 27 over
# 400 units, and ALL 28 over the 300-unit cap, the shortest at 358. Under the obvious gate every
# write to that index is refused forever, and the deny text's own remedy cannot clear it — archiving
# a different entry leaves the offending line exactly as long as it was. The only escape from the
# last such loop was the ungated `Bash >>` door that hooks/memory-index-drain.sh just closed, so
# shipping the cap without the grandfathering rule would push writers straight back through it.
#
# So the question the gate asks is "did THIS EDIT make an over-cap line longer", and the
# grandfathering TRIPLE below — lengthen REFUSED, shorten ALLOWED, unchanged-while-touching-others
# ALLOWED — is what proves the loop is absent. Any one of the three alone is satisfied by a gate
# that still wedges.
#
# RED-proof coverage: every verdict is SELECTED by arithmetic on a projected multiset diff, never
# asserted; three mutation controls anchor the mechanism (a mutant without the grandfathering clause
# refuses a shrink; a mutant comparing max-against-max lets a smuggled new line through; a mutant
# without the entry branch prints the ONE-IN-ONE-OUT epilogue that is FALSE for this dimension); the
# cap is proven to come from mim_entry_limit by moving it, not by reading it; and the fail-open on
# an unreadable cap is proven SCOPED — it costs this dimension and leaves the loader caps armed.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a non-final `[[ ]]` in
# a bats body evaluates and DISCARDS its result — the test passes vacuously
# (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/memory-index-budget.sh"
  NUDGE="$REPO/hooks/memory-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # shellcheck source=../hooks/lib/memory-index-budget.sh
  . "$LIB"
  CAP="$(mim_entry_limit)"
  LIMIT="$(mim_limit)"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

pad() { head -c "$1" /dev/zero | tr '\0' x; }

# An index whose FIRST entry line is `$2` units of hook (so the whole line is a little longer) and
# whose second is short. $1 names the fixture so several can coexist in one test.
mkidx() {
  local name="$1" hooklen="$2" d f
  d="$BATS_TEST_TMPDIR/$name/memory"; mkdir -p "$d"; f="$d/MEMORY.md"
  : >"$d/alpha.md"; : >"$d/beta.md"
  { printf '# Memory — fixture\n'
    printf -- '- [Alpha](alpha.md) — %s\n' "$(pad "$hooklen")"
    printf -- '- [Beta](beta.md) — short hook\n'
  } >"$f"
  printf '%s' "$f"
}

edit() { jq -nc --arg f "$1" --arg o "$2" --arg n "$3" \
           '{file_path:$f, old_string:$o, new_string:$n}'; }

# The units of the fixture's long line, read back through the SAME measure the gate uses, so a
# fixture whose punctuation changes cannot quietly stop discriminating.
# The loader's unit for a bare string. Never the shell's own length-of operator: that counts
# CHARACTERS in a UTF-8 locale and BYTES under LC_ALL=C, which the off-box runner sets — so a
# prefix carrying one em-dash measures 22 here and 24 there, and a boundary fixture built from it
# lands two units short of the cap and silently stops discriminating. jq counts UTF-16 code units
# in either locale, exactly as the gate does. (Caught by scripts/offbox-run.sh at land, green here.)
u() { jq -nr --arg s "$1" "$MIM_JQ_DEFS"'$s|mim_units'; }

units_of() {  # units_of <file> <substring that identifies the line>
  jq -nr --rawfile c "$1" --arg m "$2" "$MIM_JQ_DEFS"'
    ($c|split("\n")) as $L | [ $L[] | select(contains($m)) | mim_units ] | .[0] // 0'
}

# A mutant copy of the lib, sourced into a subshell. `sed` on ONE anchored site, asserted to occur
# exactly once first, so the mutant is the intended one and not a near-miss.
#
# THE MUTANT MUST BE ABLE TO RUN, AND A DEAD ONE READS AS AN INNOCENT ONE. memory-index-budget.sh
# resolves memory-index-measure.sh by its OWN dirname, so a mutant alone in a tmpdir dies at its
# `.` line and the subshell exits non-zero -- which is exactly the status an ALLOW verdict returns.
# Written that way first, the max-against-max control below passed GREEN while its mutant had never
# executed a line of the mechanism it was written to indict. So the sibling lib is copied next to
# the mutant, and the mutant is asserted to define the subject before any verdict is trusted.
mutant() {  # mutant <from> <to> -> path
  local from="$1" to="$2" d m esc
  d="$BATS_TEST_TMPDIR/mut-$RANDOM"
  [ "$(grep -cF -- "$from" "$LIB")" -eq 1 ]
  mkdir -p "$d"; m="$d/memory-index-budget.sh"
  cp "$REPO/hooks/lib/memory-index-measure.sh" "$d/memory-index-measure.sh"
  # BRE, not a literal search: `.` `*` `[` `]` `^` `$` `/` `&` all mean something to sed, and an
  # under-escaped anchor produces a mutant IDENTICAL to the original -- which reads as "the mutant
  # behaved correctly", i.e. a green control over a mutation that never happened.
  esc="$(printf '%s' "$from" | sed 's/[][\\.*^$/&]/\\&/g')"
  sed "s|$esc|$to|" "$LIB" >"$m"
  bash -n "$m"                                  # a malformed mutant proves nothing
  bash -c '. "$1"; command -v mib_verdict' _ "$m" >/dev/null   # and neither does an unsourced one
  printf '%s' "$m"
}

# Run a verdict under a mutant in a shell that dies loudly rather than silently, so an unsourceable
# mutant can never be mistaken for an ALLOW.
mut_run() {  # mut_run <mutant> <file> <tool_input>
  bash -c 'set -e; . "$1"; mib_verdict Edit "$2" "$3"' _ "$1" "$2" "$3"
}

# ── the GRANDFATHERING TRIPLE. All three, or the loop is not proven absent. ───────────────────

@test "grandfathering 1/3: an edit that LENGTHENS an already-over line is REFUSED" {
  idx="$(mkidx over1 480)"; long="$(pad 480)"
  was="$(units_of "$idx" Alpha)"
  [ "$was" -gt "$CAP" ]                          # the fixture is already over: that is the point
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 0 ]
  has "$output" 'per-entry cap'
  has "$output" 'so this edit LENGTHENS it'
}

@test "grandfathering 2/3: an edit that SHORTENS the same over-cap line is ALLOWED" {
  idx="$(mkidx over2 480)"; long="$(pad 480)"
  [ "$(units_of "$idx" Alpha)" -gt "$CAP" ]
  # Still far over the cap afterwards — allowed because it got SHORTER, not because it got legal.
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "$(pad 400)")"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "grandfathering 3/3: leaving the over line UNTOUCHED while editing another is ALLOWED" {
  idx="$(mkidx over3 480)"
  [ "$(units_of "$idx" Alpha)" -gt "$CAP" ]
  run mib_verdict Edit "$idx" "$(edit "$idx" 'short hook' 'short hook, corrected')"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "the refusal is SELECTED by the cap, not asserted: the same edit passes at a higher cap" {
  idx="$(mkidx sel 480)"; long="$(pad 480)"
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 0 ]
  MEMORY_ENTRY_LIMIT=9000 run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 1 ]
}

# ── a NEW line, and the boundary ──────────────────────────────────────────────────────────────

@test "a NEW line over the cap is REFUSED, and names itself as replacing nothing" {
  idx="$(mkidx new1 40)"
  run mib_verdict Edit "$idx" \
    "$(edit "$idx" '- [Beta](beta.md) — short hook' \
        "- [Beta](beta.md) — short hook
- [Gamma](gamma.md) — $(pad 400)")"
  [ "$status" -eq 0 ]
  has "$output" 'it is a NEW line, replacing nothing'
}

@test "a NEW line UNDER the cap is allowed — the boundary is the cap, one unit either side" {
  idx="$(mkidx new2 40)"
  # A line of exactly CAP units is allowed; CAP+1 is not. Built by measuring, not by counting.
  pfx='- [Gamma](gamma.md) — '
  body="$(pad $(( CAP - $(u "$pfx") )))"
  run mib_verdict Edit "$idx" \
    "$(edit "$idx" '- [Beta](beta.md) — short hook' "- [Beta](beta.md) — short hook
${pfx}${body}")"
  [ "$status" -eq 1 ]
  run mib_verdict Edit "$idx" \
    "$(edit "$idx" '- [Beta](beta.md) — short hook' "- [Beta](beta.md) — short hook
${pfx}${body}x")"
  [ "$status" -eq 0 ]
}

@test "a shrinking edit reports longest_added=0 — the negative control on the delta itself" {
  idx="$(mkidx shrink 480)"
  run mib_entry_delta Edit "$idx" \
    "$(edit "$idx" '- [Beta](beta.md) — short hook
' '')" "$CAP"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | cut -f1 | grep -qx 0
}

@test "only ENTRY lines are judged: a long prose line is not a rule with a home to move to" {
  idx="$(mkidx prose 40)"
  run mib_verdict Edit "$idx" "$(edit "$idx" '# Memory — fixture' "# Memory — $(pad 600)")"
  [ "$status" -eq 1 ]
  # Same text as an ENTRY line does trip it — so the discriminator is the shape, not the length.
  run mib_verdict Edit "$idx" \
    "$(edit "$idx" '# Memory — fixture' "# Memory — fixture
- [P](p.md) — $(pad 600)")"
  [ "$status" -eq 0 ]
}

# ── the deny text, and the epilogue that must NOT follow it ────────────────────────────────────

@test "dim=entry prints its own remedies IN ORDER and forbids self-truncation, citing R15" {
  idx="$(mkidx text 480)"; long="$(pad 480)"
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 0 ]
  has "$output" '1. WRITE THE RULE TO THE RULES FILE'
  has "$output" '2. SPLIT IT INTO TWO ENTRIES'
  has "$output" '3. MOVE THE DETAIL INTO THE TOPIC FILE'
  has "$output" 'R15'
  has "$output" 'FORBIDDEN'
  has "$output" 'GRANDFATHERED'
}

@test "the deny text names the routing destination W3 built, and the entry's own topic file" {
  idx="$(mkidx dest 480)"; long="$(pad 480)"
  CLAUDE_PROJECT_DIR=/tmp/proj-xyz run mib_verdict Edit "$idx" \
    "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 0 ]
  has "$output" '/tmp/proj-xyz/.claude/rules/agent-operating-lessons.md'
  has "$output" '/alpha.md'
}

@test "the ONE-IN-ONE-OUT epilogue does NOT print for dim=entry — it is FALSE for it" {
  idx="$(mkidx epi 480)"; long="$(pad 480)"
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 0 ]
  hasnt "$output" 'ONE-IN-ONE-OUT'
  hasnt "$output" 'Any write that SHRINKS the index'
  # Polarity control: the SAME gate still prints it for the size dimension, so the absence above
  # is a routing decision and not a deleted epilogue.
  big="$BATS_TEST_TMPDIR/big/memory"; mkdir -p "$big"
  printf '%sTAIL' "$(pad $(( LIMIT - 4 )))" >"$big/MEMORY.md"
  run mib_verdict Edit "$big/MEMORY.md" "$(edit "$big/MEMORY.md" TAIL 'TAILyyyy')"
  [ "$status" -eq 0 ]
  has "$output" 'ONE-IN-ONE-OUT'
}

# ── precedence, and the SCOPE of the fail-open ─────────────────────────────────────────────────

@test "a loader cap outranks the entry cap: a write breaching both reports the loader one" {
  d="$BATS_TEST_TMPDIR/both/memory"; mkdir -p "$d"
  { printf '# Memory\n'; printf -- '- [A](a.md) — %s\n' "$(pad $(( LIMIT - 100 )))"; } >"$d/MEMORY.md"
  run mib_verdict Edit "$d/MEMORY.md" \
    "$(edit "$d/MEMORY.md" '# Memory' "# Memory
- [B](b.md) — $(pad 400)")"
  [ "$status" -eq 0 ]
  has "$output" 'over its read limit'
  hasnt "$output" 'per-entry cap'
}

@test "an unreadable entry cap costs THIS dimension only — the loader caps stay armed" {
  idx="$(mkidx failopen 480)"; long="$(pad 480)"
  MEMORY_ENTRY_LIMIT=abc run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "${long}MORE")"
  [ "$status" -eq 1 ]
  big="$BATS_TEST_TMPDIR/fo/memory"; mkdir -p "$big"
  printf '%sTAIL' "$(pad $(( LIMIT - 4 )))" >"$big/MEMORY.md"
  MEMORY_ENTRY_LIMIT=abc run mib_verdict Edit "$big/MEMORY.md" \
    "$(edit "$big/MEMORY.md" TAIL 'TAILyyyy')"
  [ "$status" -eq 0 ]
  has "$output" 'over its read limit'
}

@test "the entry cap default is spelled in exactly ONE place, and this gate is not it" {
  [ "$(grep -c 'MEMORY_ENTRY_LIMIT:-' "$REPO/hooks/lib/memory-index-measure.sh")" -eq 1 ]
  [ "$(grep -c 'MEMORY_ENTRY_LIMIT:-' "$LIB")" -eq 0 ]
  [ "$(grep -c 'MEMORY_ENTRY_LIMIT:-' "$NUDGE")" -eq 0 ]
}

# ── mutation controls: each anchors ONE mechanism this suite would otherwise assert vacuously ──

@test "mutation control: a gate without the grandfathering clause REFUSES a shrinking edit" {
  m="$(mutant '$A[.].u > $cap and $A[.].u > ($R[.] // 0)' '$A[.].u > $cap')"
  idx="$(mkidx mut1 480)"; long="$(pad 480)"
  run mib_verdict Edit "$idx" "$(edit "$idx" "$long" "$(pad 400)")"
  [ "$status" -eq 1 ]                                       # real gate: shrinking is allowed
  run mut_run "$m" "$idx" "$(edit "$idx" "$long" "$(pad 400)")"
  [ "$status" -eq 0 ]                                       # mutant: wedged, the loop is back
  has "$output" 'per-entry cap'
}

@test "mutation control: comparing max-against-max lets a smuggled NEW over-cap line through" {
  # Shorten the 500-unit line AND add a new 400-unit one in the same edit. Max-vs-max answers for
  # the whole write with 400 < 500 and allows it; ranked pairwise, the new line is compared against
  # rank 1 of the removed set — nothing — and is refused.
  m="$(mutant '($R[.] // 0)' '($R[0] // 0)')"
  idx="$(mkidx mut2 480)"; long="$(pad 480)"
  ti="$(edit "$idx" "$long" "$(pad 400)
- [Gamma](gamma.md) — $(pad 380)")"
  run mib_verdict Edit "$idx" "$ti"
  [ "$status" -eq 0 ]                                       # real gate: refused
  run mut_run "$m" "$idx" "$ti"
  [ "$status" -eq 1 ]                                       # mutant: smuggled through
}

@test "mutation control: a gate without the entry branch prints the epilogue that is FALSE here" {
  m="$(mutant 'if [ "$dim" = entry ]; then' 'if [ "$dim" = xyzzy-never ]; then')"
  idx="$(mkidx mut3 480)"; long="$(pad 480)"
  ti="$(edit "$idx" "$long" "${long}MORE")"
  run mut_run "$m" "$idx" "$ti"
  [ "$status" -eq 0 ]
  has "$output" 'ONE-IN-ONE-OUT'                            # mutant: the wrong remedy
  run mib_verdict Edit "$idx" "$ti"
  hasnt "$output" 'ONE-IN-ONE-OUT'                          # real gate: its own remedy
}

# ── the WHOLE-INDEX shape that made grandfathering load-bearing ────────────────────────────────

@test "an index where EVERY line is over the cap still accepts a correcting-clause append" {
  # reso's live shape the day this shipped: 28 entries, 27 over 400 units, all 28 over the cap.
  # Under a gate without grandfathering this index can never be written to again by any door.
  d="$BATS_TEST_TMPDIR/reso/memory"; mkdir -p "$d"
  printf '# Memory — fixture\n' >"$d/MEMORY.md"
  for i in $(seq 1 28); do
    printf -- '- [E%s](e%s.md) — %s\n' "$i" "$i" "$(pad 420)" >>"$d/MEMORY.md"
  done
  n_over="$(jq -nr --rawfile c "$d/MEMORY.md" --argjson cap "$CAP" "$MIM_JQ_DEFS"'
    [ ($c|split("\n"))[] | select(startswith("- [")) | mim_units | select(. > $cap) ] | length')"
  [ "$n_over" -eq 28 ]
  # A correcting clause traded against words removed from the SAME line: net shorter, allowed.
  run mib_verdict Edit "$d/MEMORY.md" \
    "$(edit "$d/MEMORY.md" "- [E7](e7.md) — $(pad 420)" \
        "- [E7](e7.md) — $(pad 380) — but only under X")"
  [ "$status" -eq 1 ]
  # And archiving a DIFFERENT entry, the remedy the ONE-IN-ONE-OUT epilogue prescribes, is allowed
  # too — it just could never have cleared a non-grandfathered refusal, which is why that epilogue
  # must not print for this dimension.
  run mib_verdict Edit "$d/MEMORY.md" "$(edit "$d/MEMORY.md" "- [E9](e9.md) — $(pad 420)
" '')"
  [ "$status" -eq 1 ]
}

# ── item 4: the nudge may not advertise a budget the gate will refuse ──────────────────────────

nfire() {  # nfire <sid> <index-path>
  printf '{"session_id":"%s","cwd":"/nonexistent-cwd-xyz"}' "$1" \
    | MEMORY_INDEX_PATH="$2" bash "$NUDGE"
}
nctx() { jq -r '.hookSpecificOutput.additionalContext'; }

mkflat() {  # mkflat <name> <entries> <hooklen> → path
  local d="$BATS_TEST_TMPDIR/$1"; mkdir -p "$d"
  : >"$d/MEMORY.md"
  for i in $(seq 1 "$2"); do
    printf -- '- [T%s](t%s.md) — %s\n' "$i" "$i" "$(pad "$3")" >>"$d/MEMORY.md"
  done
  printf '%s' "$d/MEMORY.md"
}

@test "the nudge's per-append hard cap is clamped to the entry cap, not to index headroom" {
  # 40 short entries: ~20000 chars of headroom, which the unclamped form advertised in full.
  idx="$(mkflat nudge1 40 100)"; out=""
  for _ in $(seq 1 12); do out="$(nfire s-clamp "$idx" || true)"; done
  ctxout="$(printf '%s' "$out" | nctx)"
  has "$ctxout" 'hard cap this append:'
  cap_shown="$(printf '%s' "$ctxout" | sed -n 's/.*hard cap this append: \([0-9]*\).*/\1/p')"
  [ -n "$cap_shown" ]
  [ "$cap_shown" -lt "$CAP" ]                    # clamped, and by the prefix as well
  [ "$cap_shown" -gt 0 ]
}

@test "the clamp is a MIN, not a constant: raising the entry cap restores the headroom figure" {
  idx="$(mkflat nudge2 40 100)"; out=""
  for _ in $(seq 1 12); do
    out="$(MEMORY_ENTRY_LIMIT=99000 nfire s-unclamp "$idx" || true)"
  done
  ctxout="$(printf '%s' "$out" | nctx)"
  cap_shown="$(printf '%s' "$ctxout" | sed -n 's/.*hard cap this append: \([0-9]*\).*/\1/p')"
  [ -n "$cap_shown" ]
  [ "$cap_shown" -gt "$CAP" ]                    # headroom, not the cap — so the min is real
}
