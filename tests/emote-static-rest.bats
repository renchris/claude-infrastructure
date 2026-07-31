#!/usr/bin/env bats
# emote-static-rest — the reduced-motion resting-opacity contract in tools/banner/emotes.py.
#
# WHAT IS BEING GUARDED. `base_css` ends with
# `@media(prefers-reduced-motion:reduce){*{animation:none!important}}`, so for that reader every
# animation is off and each element paints its STATIC rule. A track whose only `opacity` lived
# inside its keyframes therefore falls back to the CSS default of 1 — fully visible, when the whole
# point of the track was that it rests hidden. That defect was found and fixed FOUR separate times
# (`.eglyph`, `.gtN`, and two tracks inside `_steps`' pack) before it was lifted into the
# vocabulary, and each time every other gate passed: a gate that reads the animated timeline never
# looks at the frame where the animation is absent.
#
# TWO HALVES, and both are needed. `egate`/`glyph_pop` now EMIT the rest, which closes the path a
# candidate takes when it uses the vocabulary — tests 1-3. `assert_static_rest` closes the rest,
# and it is the half that matters, because three of the four instances were hand-rolled
# `@keyframes` blocks that no amount of fixing the helpers can reach — tests 4-8.
#
# THE RED CASES ARE THE POINT. A guard nobody has seen go red is a guess, and this file's own
# subject is a guard that four times was not there. Each red case asserts the specific diagnosis,
# never merely a non-zero exit, which an unrelated import error would counterfeit.
#
# HERMETIC: pure stdlib Python against the module in the repo, no browser and no network. The
# synthetic stylesheets below are hand-written rather than harvested from a built candidate, so a
# future edit to a real candidate cannot silently turn a red case green.
#
# BATS ERREXIT: a non-final bare `[[ ]]` is errexit-EXEMPT and therefore a DEAD assertion — every
# non-final assertion below is `|| false` or a live final `[ ]`.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BANNER="$REPO/tools/banner"
}

# gate <css> <svg-body> — run assert_static_rest on a synthetic candidate.
# Prints "ACCEPTED", or "REFUSED: <the gate's own message>". Always exits 0, so a test asserts on
# the VERDICT rather than on a status an import failure could also produce.
gate() {
  python3 - "$BANNER" "$1" "$2" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import emotes

svg = f"<svg><style>{sys.argv[2]}</style>{sys.argv[3]}</svg>"
e = emotes.Emote(
    key="probe", title="probe", category="c",
    entry="a written entry", showcase="a written showcase", exit="a written exit",
    window=(1.0, 5.0),
)
try:
    emotes.assert_static_rest(svg, e)
except SystemExit as ex:
    print("REFUSED:", ex)
else:
    print("ACCEPTED")
PY
}

# vocab <expr> — evaluate one expression against the module and print it.
vocab() {
  python3 - "$BANNER" "$1" <<'PY'
import sys

sys.path.insert(0, sys.argv[1])
import emotes

print(eval(sys.argv[2], vars(emotes)))
PY
}

# ── the vocabulary emits the rest ────────────────────────────────────────────────────────────────

@test "egate emits the resting opacity statically — hidden-at-rest" {
  run vocab 'egate("g", ".x", [(1.0, 5.0)])'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *".x{opacity:0;animation:g "* ]]
}

@test "egate emits the resting opacity statically — visible-at-rest" {
  run vocab 'egate("g", ".x", [(1.0, 5.0)], on_inside=False)'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *".x{opacity:1;animation:g "* ]]
}

@test "glyph_pop emits its opacity:0 rest statically" {
  run vocab 'glyph_pop("g", ".x", 1.0, 5.0)'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *".x{opacity:0;animation:g "* ]]
}

# ── the gate refuses what the vocabulary cannot reach ─────────────────────────────────────────────

@test "RED: a hand-rolled keyframes-only opacity is refused" {
  # The shape of three of the four real instances: the author wrote the @keyframes directly, so
  # fixing egate would not have saved them.
  run gate '@keyframes k{0%{opacity:0}50%{opacity:1}100%{opacity:0}}.probe{animation:k 12s linear infinite}' \
           '<g class="probe"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"paints 1 with animations OFF"* ]] || false
  [[ "$output" == *"renders VISIBLE"* ]]
}

@test "RED: stripping egate's static rest is caught — the lift cannot be quietly reverted" {
  # egate's real output with `opacity:0;` deleted from the rule, i.e. exactly the file as it stood
  # before the fix. This is the regression test for THIS change.
  css="$(vocab 'egate("g", ".probe", [(1.0, 5.0)])')"
  # No brace in either half of the substitution: bash keeps a backslash in the REPLACEMENT
  # literally, so `.probe\{animation:` is what the first spelling of this actually produced — CSS
  # no parser matches, a gate with no rule to judge, and a red case that passed by being unreadable.
  stripped="${css/opacity:0;animation:/animation:}"
  [ "$stripped" != "$css" ] || false   # the sabotage must have LANDED, or the case is vacuous
  run gate "$stripped" '<g class="probe"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"renders VISIBLE"* ]]
}

@test "RED: the inverse direction too — a visible-at-rest track on a hidden element" {
  # Not one-sided. A gate that only ever caught 0-vs-1 would pass the mirror defect, which is how
  # `.eglyph` came to hide an envelope that was only borrowing the class.
  run gate '.probe{opacity:0}@keyframes k{0%{opacity:1}50%{opacity:0}100%{opacity:1}}.probe{animation:k 12s linear infinite}' \
           '<g class="probe"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"renders HIDDEN"* ]]
}

# ── and accepts what is legitimately correct ─────────────────────────────────────────────────────

@test "a rest inherited from a SIBLING class is accepted" {
  # `class="eglyph cuG"` — `.eglyph` carries the resting value, `.cuG` carries only the animation.
  # Six shipping candidates sit in exactly this position, and a gate that convicted them would be
  # worked around rather than obeyed.
  run gate '.eglyph{opacity:0}@keyframes k{0%{opacity:0}50%{opacity:1}100%{opacity:0}}.cuG{animation:k 12s ease-out infinite}' \
           '<g class="eglyph cuG"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"ACCEPTED"* ]]
}

@test "a transform-only track has no resting opacity to check" {
  run gate '@keyframes k{0%{transform:translateX(0)}100%{transform:translateX(-96px)}}.probe{animation:k 1s linear infinite}' \
           '<g class="probe"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"ACCEPTED"* ]]
}

@test "RED: an opacity the gate cannot read is refused, never passed" {
  # The third state. A guard that answers "fine" when it means "I could not look" reports coverage
  # it does not have, which is the failure mode this whole file exists to prevent.
  run gate '.probe{opacity:var(--x)}@keyframes k{0%{opacity:0}50%{opacity:1}100%{opacity:0}}.probe{animation:k 12s linear infinite}' \
           '<g class="probe"></g>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"CANNOT say"* ]]
}

@test "a mixed-case SVG element is not skipped by the tag scan" {
  # `clipPath`, `linearGradient` — a lowercase-only tag match plus \b silently skips every one.
  run gate '@keyframes k{0%{opacity:0}50%{opacity:1}100%{opacity:0}}.probe{animation:k 12s linear infinite}' \
           '<clipPath class="probe"></clipPath>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSED"* ]]
}

@test "stop-opacity is not read as an element's opacity" {
  # `(?:^|;)opacity:` rather than a bare search: a gradient stop's alpha is not the element's, and
  # reading one as the other reports a rest no element has.
  run gate '.probe{stop-opacity:.5}@keyframes k{0%{opacity:1}50%{opacity:0}100%{opacity:1}}.probe{animation:k 12s linear infinite}' \
           '<stop class="probe"/>'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"ACCEPTED"* ]]
}

# ── the shipping corpus ──────────────────────────────────────────────────────────────────────────

@test "every shipping candidate passes the gate" {
  run python3 "$BANNER/emotes.py" --out "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"27 candidate(s)"* ]]
}
