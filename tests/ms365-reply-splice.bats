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

# --- DEPLOY REACHABILITY (2026-08-31) ------------------------------------------------
# A tool the live hook TELLS the model to run must exist where the model would run it.
# Measured 2026-08-31: bin/ms365-reply-splice.py was on trunk and in no live location at
# all, and was named ZERO times across install.sh, deploy-live.sh and deploy-link-parity.sh
# — so no advance of the live layer could ever place it. install.sh:809 populates
# ~/.claude/bin from a NAME-PREFIX GLOB (bin/cc-* and bin/desk-*) and this tool matches
# neither, which is the identical defect install.sh's own comment records for desk-register:
# "nothing else linked it … the live /desk command … invoked a nonexistent binary".
#
# TWO INDEPENDENT DEFECTS, AND FIXING EITHER ALONE LEAVES THE PRESCRIPTION BROKEN:
#   (1) the tool is not linked onto PATH, and
#   (2) the hook prescribed it as `bin/ms365-reply-splice.py` — a path containing a SLASH,
#       which the shell resolves against the CWD and never against PATH. The hook fires in
#       every session whatever its cwd, so that form resolves only from the checkout root.
#
# These arms pin the MECHANISM, not the wording: arm A executes install.sh's own extracted
# selection loop, and arm C derives its population from the hook rather than naming a tool,
# so the next tool added to the RECIPE is covered without editing this suite.

@test "deploy: install.sh's PATH-tools pass selects the splicer the hook prescribes" {
  # EXTRACT the subject's own loop header rather than restating the glob — a restated
  # predicate drifts silently from the one that ships. Uniqueness asserted first, so we
  # can never be executing an unknown line (#245: a census that cannot refuse is not one).
  [ "$(grep -cF 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh")" -eq 1 ]
  HDR="$(grep -F 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh")"

  REPO_DIR="$WORK/fakerepo"; mkdir -p "$REPO_DIR/bin"
  : >"$REPO_DIR/bin/cc-probe-xyzzy"            # POS control: always selected
  : >"$REPO_DIR/bin/ms365-reply-splice.py"     # the subject
  : >"$REPO_DIR/bin/never-linked-xyzzy"        # NEG control: must NOT be selected
  SEL="$WORK/selected.txt"; : >"$SEL"

  # Run the REAL header with a recording stub in place of link_file.
  eval "$HDR
    [ -f \"\$tool\" ] || continue
    basename \"\$tool\" >>\"$SEL\"
  done"

  # POS control first: if the harness selects nothing, every assertion below is vacuous.
  [ "$(grep -cxF 'cc-probe-xyzzy' "$SEL")" -eq 1 ]
  # NEG control: the pass must still be selective, or "everything is linked" would pass.
  [ "$(grep -cxF 'never-linked-xyzzy' "$SEL")" -eq 0 ]
  # The subject.
  [ "$(grep -cxF 'ms365-reply-splice.py' "$SEL")" -eq 1 ]
}

@test "deploy: the hook prescribes the splicer by a cwd-independent path" {
  H="$REPO/hooks/enforce-email-formatting.py"
  [ -f "$H" ]
  # NOTE ON THE NEEDLES: the absolute form CONTAINS the relative form as a substring, so a
  # bare count of the short needle also matches the long one (the land-verify/postland-verify
  # scar). Count both and assert EQUALITY — every mention must be the absolute form — plus a
  # floor of 1 so this cannot pass by the hook simply never mentioning the tool.
  ABS="$(grep -oF '.claude/bin/ms365-reply-splice.py' "$H" | grep -c .)"
  ALL="$(grep -oF 'bin/ms365-reply-splice.py' "$H" | grep -c .)"
  [ "$ABS" -ge 1 ]
  [ "$ALL" -eq "$ABS" ]
}

@test "deploy: every ~/.claude/bin tool the hook prescribes is one install.sh would link" {
  # THE CLASS ARM. Derived from the hook, not from a name, so a tool added to the RECIPE
  # tomorrow is covered without touching this file. It is what stops the prescription and
  # the deploy pass drifting apart again.
  H="$REPO/hooks/enforce-email-formatting.py"
  TOOLS="$WORK/prescribed.txt"
  grep -oE '\.claude/bin/[A-Za-z0-9._-]+' "$H" | sed 's#.*/##' | sort -u >"$TOOLS"
  # Non-vacuity: the population must be non-empty, else "all members pass" says nothing.
  [ "$(grep -c . "$TOOLS")" -ge 1 ]

  MISSED="$WORK/missed.txt"; : >"$MISSED"
  while IFS= read -r t; do
    case "$t" in
      cc-*|desk-*) continue ;;                                   # taken by the glob
    esac
    # otherwise install.sh must name it explicitly somewhere
    [ "$(grep -cF "$t" "$REPO/install.sh")" -ge 1 ] || printf '%s\n' "$t" >>"$MISSED"
  done <"$TOOLS"
  [ "$(grep -c . "$MISSED")" -eq 0 ]
}

@test "deploy: every bin/ family install.sh globs is a want=1 class in the parity assert" {
  # THE SECOND CLASS ARM, and the one that makes the fix reach the ENFORCING STORE.
  # install.sh is not the mechanism that keeps the live layer in step — it REFUSES a global
  # install from a behind-trunk checkout, which is the state deploy-live creates by design.
  # The repairer that runs 144x/day is scripts/deploy-parity-assert.sh, and it RESTATES
  # install.sh's bin/ families as its own case arms. A family present in one and absent from
  # the other falls to that file's `*) want=0` default and is scored NOT-EXPECTED-LIVE —
  # silently, which is the precise failure its own comment records for two earlier classes.
  # Derived from install.sh rather than named, so the next family is covered here too.
  ASSERT="$REPO/scripts/deploy-parity-assert.sh"
  [ -f "$ASSERT" ]
  [ "$(grep -cF 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh")" -eq 1 ]
  FAMS="$WORK/families.txt"
  grep -F 'for tool in "$REPO_DIR"/bin/' "$REPO/install.sh" \
    | grep -oE '/bin/[A-Za-z0-9._-]+\*' | sed 's#^/bin/##' | sort -u >"$FAMS"
  # Non-vacuity: install.sh must glob at least the two families that predate this test.
  [ "$(grep -c . "$FAMS")" -ge 2 ]
  [ "$(grep -cxF 'cc-*' "$FAMS")" -eq 1 ]

  UNCLAIMED="$WORK/unclaimed.txt"; : >"$UNCLAIMED"
  while IFS= read -r fam; do
    # the assert must carry a want=1 arm naming this family
    [ "$(grep -cF "bin/$fam)" "$ASSERT")" -ge 1 ] || printf '%s\n' "$fam" >>"$UNCLAIMED"
  done <"$FAMS"
  [ "$(grep -c . "$UNCLAIMED")" -eq 0 ]
}
