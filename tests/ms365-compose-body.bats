#!/usr/bin/env bats
# ms365-compose-body.py — the tool that turns prose into the house email fragment.
#
# WHY A TOOL AT ALL. Three defects kept recurring in hand-written markup, and none of them is a
# matter of care (full record: docs/research/email-formatting-2026-09-14.md):
#   * breaks   — Graph strips NEWLINES from a reply Comment, so prose arrives as one paragraph;
#   * colour   — Graph drops the comment into a BARE <body> as an unstyled text node, so it takes
#                the reading client's default and renders grey beside Graph's explicitly-black quote;
#   * signature — Graph never adds one and no Graph API can read the user's.
#
# THE RULES THAT ARE EASY TO REGRESS AND INVISIBLE WHEN BROKEN are pinned here with mutants:
# self-defending inline styles (the fragment lands inside a document the counterparty wrote, whose
# stylesheet Graph copies into the draft's <head>), no `padding` (classic Outlook renders through
# Word, where padding is supported on TABLE CELLS ONLY, so a padded list silently loses its indent
# THERE and nowhere else), and colour+background declared as a pair.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOOL="$REPO/bin/ms365-compose-body.py"
  [ -f "$TOOL" ]
  SIGS="$BATS_TEST_TMPDIR/sigs.json"
  cat >"$SIGS" <<'JSON'
{
  "full":     {"name":"Chris Ren","title":"Founder","company":"Reso",
               "email":"chris@reso.gl","website":"reso.gl","phone":"+1 555 0100"},
  "sparse":   {"name":"Chris Ren","company":"Reso"}
}
JSON
}

compose() { python3 "$TOOL" --signature-file "$SIGS" "$@"; }

# ── structure ─────────────────────────────────────────────────────────────────────────────────────

@test "a blank line makes a new paragraph; a single newline does not" {
  run compose --no-signature --out - <<< $'One.\n\nTwo.\n\nBest regards,\nChris'
  [ "$status" -eq 0 ]
  # three <p>, and the sign-off's soft break is a <br> INSIDE the last one, not a fourth paragraph.
  [ "$(grep -o '<p ' <<<"$output" | grep -c .)" -eq 3 ]
  [[ "$output" == *"Best regards,<br>Chris"* ]]
}

@test "a run of '- ' lines becomes a list" {
  run compose --no-signature --out - <<< $'Here:\n\n- alpha\n- beta'
  [ "$status" -eq 0 ]
  [ "$(grep -o '<li ' <<<"$output" | grep -c .)" -eq 2 ]
  [[ "$output" == *"alpha"* && "$output" == *"beta"* ]]
}

@test "prose is HTML-escaped, so a < or & in the text cannot become markup" {
  # The operator writes prose. If it contains "<3" or "R&D" that must render as typed, and must
  # not be able to inject an element into the draft body.
  run compose --no-signature --out - <<< 'Margins of <5% on R&D, per <b>their</b> note.'
  [ "$status" -eq 0 ]
  [[ "$output" == *"&lt;5% on R&amp;D"* ]]
  [[ "$output" == *"&lt;b&gt;their&lt;/b&gt;"* ]]
}

# ── the three self-defence rules, each with a mutant ──────────────────────────────────────────────

@test "every block element carries its own font, size and colour" {
  # The fragment is pasted inside a document the counterparty wrote, and Graph copies their
  # <style> blocks into the draft's <head>. A vendor `p{margin:0}` collapses spacing and a
  # `body{color:…}` recolours prose unless each element states its own.
  run compose --signature full --out - <<< $'One.\n\n- a\n\nTwo.'
  [ "$status" -eq 0 ]
  local blocks styled
  blocks="$(grep -oE '<(p|li|div|ul) ' <<<"$output" | grep -c .)"
  styled="$(grep -oE '<(p|li|div|ul) style="[^"]*"' <<<"$output" | grep -c .)"
  [ "$blocks" -ge 6 ]
  [ "$blocks" -eq "$styled" ]          # no block element may be unstyled
  # and every paragraph/list-item must name a colour, not merely a margin
  [ "$(grep -oE '<(p|li) style="[^"]*color:[^"]*"' <<<"$output" | grep -c .)" \
    -eq "$(grep -oE '<(p|li) ' <<<"$output" | grep -c .)" ]
}

@test "no 'padding' anywhere: classic Outlook supports it on table cells only" {
  run compose --signature full --out - <<< $'Here:\n\n- alpha\n- beta'
  [ "$status" -eq 0 ]
  run ! grep -q 'padding' <<<"$output"
}

@test "mutant: indenting the list with padding-left reintroduces the Outlook defect" {
  # Proves the assertion above has power — it is the natural way to indent a <ul> and it is wrong.
  local mut="$BATS_TEST_TMPDIR/mutant-padding.py"
  sed 's/margin:0 0 12pt 24px/margin:0 0 12pt 0;padding-left:24px/' "$TOOL" >"$mut"
  grep -q 'padding-left:24px' "$mut"
  run python3 "$mut" --signature-file "$SIGS" --no-signature --out - <<< $'Here:\n\n- alpha'
  [ "$status" -eq 0 ]
  [[ "$output" == *"padding"* ]]
}

@test "colour and background are declared as a PAIR on the wrapper" {
  # A fragment's only dark-mode lever is the colours it states; every other mechanism needs a
  # <head>, :root or <style> it cannot deliver. Colour alone is the shape that goes INVISIBLE
  # under partial inversion — the client darkens the inherited background and keeps your black.
  run compose --no-signature --out - <<< 'One.'
  [ "$status" -eq 0 ]
  [[ "$output" == *"color:#000000;background-color:#ffffff;"* ]]
}

@test "--no-background drops the background but keeps the colour" {
  run compose --no-signature --no-background --out - <<< 'One.'
  [ "$status" -eq 0 ]
  [[ "$output" == *"color:#000000;"* ]]
  run ! grep -q 'background-color' <<<"$output"
}

@test "colours are hex, never whitespace-syntax rgb()" {
  # caniemail, verbatim: a style attribute containing whitespace-syntax rgb() has THE WHOLE
  # ATTRIBUTE stripped by Gmail, and a modern token like oklch() removes every inline style on
  # the element. `rgb(31 35 41)` vs `rgb(31,35,41)` is the difference between a styled fragment
  # and an unstyled one, with no warning.
  run compose --signature full --out - <<< 'One.'
  [ "$status" -eq 0 ]
  run ! grep -qE 'rgb\([0-9]+ |oklch|lab\(|color\(' <<<"$output"
}

# ── the signature ─────────────────────────────────────────────────────────────────────────────────

@test "a full signature renders every field it was given" {
  run compose --signature full --out - <<< 'One.'
  [ "$status" -eq 0 ]
  for f in "Chris Ren" "Founder" "Reso" "chris@reso.gl" "reso.gl" "+1 555 0100"; do
    [[ "$output" == *"$f"* ]]
  done
  [[ "$output" == *'href="mailto:chris@reso.gl"'* ]]
  [[ "$output" == *'href="https://reso.gl"'* ]]
}

@test "a sparse signature renders ONLY what it was given — no placeholder, no invention" {
  # The defect this guards: a signature block that emits an empty "Title:" line, or worse a
  # plausible-looking invented one, in a real business email.
  run compose --signature sparse --out - <<< 'One.'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Chris Ren"* && "$output" == *"Reso"* ]]
  run ! grep -qiE 'founder|mailto:|title|phone|\+1' <<<"$output"
}

# ── refusals: exit 2, distinct from a usage error ─────────────────────────────────────────────────

@test "an unknown signature id is REFUSED, not silently unsigned" {
  run compose --signature ghost --out - <<< 'One.'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in"* ]]
}

@test "omitting --signature is REFUSED: unsigned has to be deliberate" {
  run compose --out - <<< 'One.'
  [ "$status" -eq 2 ]
}

@test "empty input is REFUSED" {
  run compose --signature full --out - <<< ''
  [ "$status" -eq 2 ]
}

@test "a refusal (2) is distinguishable from a usage error (1)" {
  # The contract both scripts document. `raise SystemExit(str)` exits 1, so this promise was
  # broken from the first commit and every caller branching on it was wrong.
  run compose --signature full --signature-file /nonexistent/sigs.json --out - <<< 'One.'
  [ "$status" -eq 2 ]   # a missing signature FILE means the id is unknown -> refusal
  run python3 "$TOOL" --not-a-flag
  [ "$status" -eq 2 ] || [ "$status" -eq 1 ]   # argparse's own usage exit, never 0
  [ "$status" -ne 0 ]
}
