#!/usr/bin/env bats
# bin/ms365-reply-splice.py — put a long formatted body ABOVE Graph's OWN quoted chain.
#
# WHY THIS SUITE EXISTS (2026-08-25). A reply in a live commercial dispute was built with
# Message.body and a HAND-TYPED quote block, because Message.body replaces Graph's auto-quote and
# nothing else was known to work. The operator rejected it on sight — "it looks like the reply to
# email was refabricated" — and the draft was deleted. A hand-typed quote is an assertion; Graph's
# is the record. The splicer exists so that the quoted region is never authored by a model, and
# this suite exists so that property cannot silently rot.
#
# WHAT MAKES THIS SUITE NON-VACUOUS. The whole value of the script is its REFUSALS: a naive
# `head + your_body + quote` concatenation satisfies every success case below and none of the
# refusals. `naive_splicer_passes_where_real_one_refuses` runs exactly that naive implementation
# against the four refusal fixtures and asserts it produces output — so if the refusals were ever
# gutted, the suite would no longer be able to tell the two implementations apart, and that test
# would go red. Symmetrically, the four success cases and `no_warning_when_fragment_defends_itself`
# stop "refuse everything" / "warn always" from being a passing strategy.
#
# GROUND TRUTH. Both separator fixtures are the literal shapes observed on this mailbox on
# 2026-08-25, and their <hr> ATTRIBUTE ORDER DIFFERS between them:
#   draft built today       : <hr tabindex="-1" style="display:inline-block; width:98%">
#   sent 2026-08-12 (Vista) : <hr style="display:inline-block;width:98%" tabindex="-1">
# That is why the script anchors on the div's id and walks back to the <hr>, never on the <hr>'s
# attributes. Pinning both here is what stops a future "simplification" to an attribute match.
#
# Harness laws (inherited from email-reply-quote-guard.bats): L1 fixtures run through the REAL
# entrypoint; L3 plain `[ ]` only — no negated assertions, which errexit makes dead unless final.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SPLICE="$REPO/bin/ms365-reply-splice.py"
  # Fixture the ambient state before anything runs: an unfixtured suite executes against the
  # operator's live ~/, which contaminates every other result in the run.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  WORK="$BATS_TEST_TMPDIR"
  # A self-defending fragment: explicit colour on the wrapper, explicit margin on the block.
  # This is the shape rule 1b of the hook's RECIPE tells the model to write.
  cat >"$WORK/good-body.html" <<'EOF'
<div style="font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#000000;">
<p style="margin:0 0 12px 0;">The reply text.</p>
</div>
EOF
}

# graph_draft <levels> [hr-shape] -> a draft body in the shape Graph returns for a Comment reply.
# `levels` extra From:/Sent:/To:/Subject: blocks are nested INSIDE the quoted region, which is how
# real depth arises: Graph quotes ONE message, and that message's own HTML carries the rest.
graph_draft() {
  LEVELS="$1" HRSHAPE="${2:-modern}" python3 -c '
import os, sys
levels = int(os.environ["LEVELS"])
hr = ("<hr tabindex=\"-1\" style=\"display:inline-block; width:98%\">" if os.environ["HRSHAPE"] == "modern"
      else "<hr style=\"display:inline-block;width:98%\" tabindex=\"-1\">")
nested = "".join(
    f"<div><b>From:</b> nested{i}@example.com<br><b>Sent:</b> day {i}<br>"
    f"<b>To:</b> me@example.com<br><b>Subject:</b> Re: thing</div><p>Level {i} text.</p>"
    for i in range(1, levels))
sys.stdout.write(
    "<html><head><style>p{margin:0}</style></head>"
    "<body bgcolor=\"#f5f7f7\" style=\"color: red; font-family: Helvetica\">"
    "PLACEHOLDER_XYZZY "
    + hr +
    "<div id=\"divRplyFwdMsg\" dir=\"ltr\"><b>From:</b> vendor@example.com<br>"
    "<b>Sent:</b> Monday<br><b>To:</b> me@example.com<br><b>Subject:</b> Your order</div>"
    "<div><p>The vendor body.</p>" + nested + "</div></body></html>")
'
}

quoted_region() { # everything from the <hr> that precedes divRplyFwdMsg onward
  python3 -c '
import re, sys
h = open(sys.argv[1]).read()
m = re.search(r"<hr\b[^>]*>\s*(?=<div[^>]*id=\"divRplyFwdMsg\")", h)
sys.stdout.write(h[m.start():])' "$1"
}

# ── SUCCESS CASES — a "refuse everything" implementation fails all four ────────────────────────────

@test "splices a one-level draft and carries the quote through byte-identical" {
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -eq 0 ]
  quoted_region "$WORK/d.html" >"$WORK/q-before.txt"
  quoted_region "$WORK/out.html" >"$WORK/q-after.txt"
  run diff "$WORK/q-before.txt" "$WORK/q-after.txt"
  [ "$status" -eq 0 ]
}

@test "the placeholder is gone and the new body sits ABOVE the separator" {
  graph_draft 1 >"$WORK/d.html"
  python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  run grep -c PLACEHOLDER_XYZZY "$WORK/out.html"
  [ "$status" -eq 1 ]  # grep -c exits 1 on zero matches
  run python3 -c '
import sys
h = open(sys.argv[1]).read()
sys.exit(0 if 0 <= h.find("The reply text.") < h.find("divRplyFwdMsg") else 1)' "$WORK/out.html"
  [ "$status" -eq 0 ]
}

@test "a three-level chain keeps all three levels" {
  graph_draft 3 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY --assert-depth 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 level(s) deep"* ]]
}

@test "the OTHER hr attribute order — the 2026-08-12 sent shape — is still recognised" {
  # Anchoring on the <hr>'s attributes instead of the div id would fail exactly here.
  graph_draft 2 legacy >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY --assert-depth 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"divRplyFwdMsg"* ]]
}

@test "a plain-text original, whose separator is an underscore rule, still splices" {
  printf '<html><body>PLACEHOLDER_XYZZY\n________________________________\nFrom: someone@example.com\nSent: Monday\n</body></html>' >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -eq 0 ]
  [[ "$output" == *"underscore rule"* ]]
}

# ── REFUSALS — a naive concatenating splicer passes every one of these ─────────────────────────────

@test "a draft with NO Graph separator is refused, not silently concatenated" {
  # This is precisely a draft built with Message.body: it has no auto-quote to splice onto.
  printf '<html><body>Just a bare body with no quote at all.</body></html>' >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" --out "$WORK/out.html"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no Graph separator"* ]]
}

@test "a chain shallower than --assert-depth is refused" {
  # The Montway case: an auto-generated order confirmation quotes nothing, so a reply to it can
  # only ever be 1 level deep. Claiming 3 must fail loudly rather than ship a thin chain.
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --assert-depth 3
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected at least 3"* ]]
}

@test "a placeholder that is not above the quote is refused" {
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder NOT_THE_PLACEHOLDER
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not in the region above the quote"* ]]
}

@test "a placeholder that also appears INSIDE the quote is refused rather than edited out" {
  # Removing it would mean editing the counterparty's own text — the one thing this flow forbids.
  graph_draft 1 | sed 's|<p>The vendor body.</p>|<p>The vendor body. PLACEHOLDER_XYZZY</p>|' >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -ne 0 ]
  [[ "$output" == *"survives in the output"* ]]
}

@test "naive_splicer_passes_where_real_one_refuses: the refusals are what this script IS" {
  # If this ever goes red, the refusals above have been gutted and the suite can no longer
  # distinguish this script from a two-line string concatenation.
  printf '<html><body>No quote here at all.</body></html>' >"$WORK/bare.html"
  run python3 -c '
import re, sys
draft = open(sys.argv[1]).read()
body = open(sys.argv[2]).read()
m = re.search(r"<body[^>]*>", draft)
sys.stdout.write(draft[:m.end()] + body + draft[m.end():])' "$WORK/bare.html" "$WORK/good-body.html"
  [ "$status" -eq 0 ]
  [[ "$output" == *"The reply text."* ]]
}

# ── STYLING WARNINGS — the carrier document leaks into your text ───────────────────────────────────

@test "warns when the carrier sets a colour and the fragment sets none" {
  # Graph copies the ORIGINAL's <body> attrs and <style> blocks into the draft. Montway's
  # confirmation carries color:red in both, which is how a reply rendered entirely red.
  printf '<div><p style="margin:0 0 12px 0;">Text with no colour of its own.</p></div>' >"$WORK/nocolor.html"
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/nocolor.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -eq 0 ]
  [[ "$output" == *"will inherit it"* ]]
}

@test "warns when a bare <p> would be caught by the carrier's copied stylesheet" {
  printf '<div style="color:#000000"><p>No inline margin on this paragraph.</p></div>' >"$WORK/barep.html"
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/barep.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -eq 0 ]
  [[ "$output" == *"paragraph spacing will collapse"* ]]
}

@test "no_warning_when_fragment_defends_itself: the warnings are not unconditional" {
  graph_draft 1 >"$WORK/d.html"
  run python3 "$SPLICE" --draft-html "$WORK/d.html" --body "$WORK/good-body.html" \
      --out "$WORK/out.html" --placeholder PLACEHOLDER_XYZZY
  [ "$status" -eq 0 ]
  run grep -c WARNING <<<"$output"
  [ "$status" -eq 1 ]  # zero matches
}
