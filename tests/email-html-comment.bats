#!/usr/bin/env bats
# enforce-email-formatting.py — the HTML-Comment rule (2026-09-14).
#
# WHAT CHANGED AND WHY. The gate used to refuse any reply `Comment` over 300 RAW chars, on the
# stated ground that "Graph strips newlines from Comment into one unreadable paragraph at this
# length". The first half is true and the second does not follow. MEASURED against this mailbox
# on 2026-09-14: a Comment of
#     <div style="color:#C00000"><p>para one</p><p>para two here</p></div>
# came back in the draft's own MIME as, byte for byte,
#     <body>\r\n<div style="color:#C00000">\r\n<p>para one</p>\r\n<p>para two here</p>\r\n</div>\r\n<hr …>
# Graph strips NEWLINES, not MARKUP. So the cure for a long reply was never "shorten it" or "move
# to Message.body" (which replaces Graph's auto-quote and cost a real defect on 2026-08-24) — it
# was to send the Comment AS HTML, which keeps the auto-quote and needs exactly one API call.
#
# WHAT MAKES THIS SUITE NON-VACUOUS.
#   RED-PROOF  a structured HTML Comment over the old cap: DENIED pre-fix, ALLOWED post-fix.
#   EQUIVALENCE a PLAIN-TEXT Comment over the cap must STAY denied. Green in both arms by design —
#              it is the guard that the fix did not simply delete the rule, and the mutant below is
#              what proves it has any power at all.
#   HOLE-CLOSE  opening Comment to HTML inherits the density rule, which is a whole-body average and
#              blind to one enormous <p>. MAX_BLOCK_CHARS closes that, and it is tested on BOTH
#              Comment and Message.body because the hole predates this change on the latter.
#
# Without the equivalence case, "drop the Comment rule entirely" passes every red-proof.
# Without the red-proof, "keep denying" passes every equivalence case.

bats_require_minimum_version 1.5.0  # `run !` (SC2314): a bare `! cmd` mid-test never fails

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  [ -f "$GATE" ]
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  # R4 freshness: these fixtures are single calls with no session history, so without this
  # stamp every ALLOW control would go red and every DENY would go green for the wrong reason.
  touch "$TMPDIR/cc-ms365-inbound-bats"
}

decision() {
  GATE_UT="$1" TOOL="$2" TIN="$3" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": "bats", "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"],
                  "tool_input": {"account": "ren.chris@outlook.com", **json.loads(os.environ["TIN"])}})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print("allow"); sys.exit(0)
print(json.loads(out)["hookSpecificOutput"]["permissionDecision"])
'
}

tin_comment() {
  COMMENT="$1" python3 -c '
import json, os
print(json.dumps({"body": {"Comment": os.environ["COMMENT"]}}))'
}

tin_message() {
  CONTENT="$1" python3 -c '
import json, os
print(json.dumps({"body": {"message": {"body": {"contentType": "html",
                                                "content": os.environ["CONTENT"]}}}}))'
}

# A real house fragment: wrapper div + six styled <p>, ~660 visible chars, ~3 KB of markup.
# Both numbers are over the old 300-char cap, which is the point.
html_comment() {
  python3 - <<'PY'
paras = [
    "Hi Harry,",
    "Thanks for reaching out, and for laying out the BytePlus range in that much detail.",
    "We are building Reso, a venue-operations product, and our current spend on inference is "
    "small enough that a switch would be premature.",
    "What would be genuinely useful now is the concrete pricing for two things, so I can hold "
    "them against what we pay today.",
    "If those land in the range you describe, I will come back to you with real numbers.",
    "Best regards,<br>Chris",
]
style = "margin:0 0 12pt 0;font-family:Aptos,Calibri,Arial,sans-serif;font-size:11pt;color:#000000;"
print('<div style="font-family:Aptos,Calibri,Arial,sans-serif;font-size:11pt;color:#000000;">'
      + "".join(f'<p style="{style}">{p}</p>' for p in paras) + "</div>", end="")
PY
}

# ── RED-PROOF ─────────────────────────────────────────────────────────────────────────────────────

@test "a formatted HTML Comment over the old cap is allowed" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_comment "$(html_comment)")"
  [ "$output" = "allow" ]
}

@test "the same fragment is allowed on reply-all and forward drafts too" {
  local tin; tin="$(tin_comment "$(html_comment)")"
  run decision "$GATE" mcp__ms365__create-reply-all-draft "$tin"; [ "$output" = "allow" ]
  run decision "$GATE" mcp__ms365__create-forward-draft "$tin"; [ "$output" = "allow" ]
}

@test "redproof: the pre-fix hook DENIES the fragment this fix allows" {
  # Pinned blob, not origin/main: after this lands that path becomes the FIXED file and a control
  # that drifts onto its own subject can only ever agree with it.
  local pre="$BATS_TEST_TMPDIR/prefix-hook.py"
  git -C "$REPO" cat-file -p 58d0886c49739cf00543cd399cb5420157cee289 > "$pre"
  [ -s "$pre" ]
  # Positive control on the instrument: the pre-fix file must NOT carry the symbol the fix adds,
  # or we are unknowingly running the fixed file against itself.
  run ! grep -q "is_structured_html" "$pre"

  run decision "$pre" mcp__ms365__create-reply-draft "$(tin_comment "$(html_comment)")"
  [ "$output" = "deny" ]
}

# ── EQUIVALENCE: the plain-text rule must survive the fix ──────────────────────────────────────────

@test "a long PLAIN-TEXT Comment is still refused" {
  # Graph really does strip newlines out of prose. This is the original 2026-06-12 defect and the
  # fix must not have deleted it. Green in both arms — see the mutant below for its power.
  local long; long="$(python3 -c 'print("word " * 80)')"
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_comment "$long")"
  [ "$output" = "deny" ]
}

@test "a long plain-text Comment with newlines in it is STILL refused" {
  # The tempting weaker rule is "allow it if the author put breaks in". Newlines are exactly what
  # Graph discards, so they are not breaks — only markup is.
  local long; long="$(python3 -c 'print(("word " * 20 + "\n\n") * 5)')"
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_comment "$long")"
  [ "$output" = "deny" ]
}

@test "mutant: THE NAIVE FIX re-opens the newline hole" {
  # What this proves, precisely. `is_structured_html` is NOT independently load-bearing for a
  # plain-text DENY — measured: forcing it true still denies, because a body with no block tags
  # scores zero html_breaks and the wall-of-text arm catches it. That is defence in depth, and a
  # test asserting otherwise would have been a lie about its own subject.
  #
  # The predicate earns its place against a DIFFERENT mutant: the naive fix — delete the length
  # cap and the Comment arm, and do not add a markup test. That is what a future reader reaches
  # for, and it is genuinely wrong, because a long plain-text Comment with blank lines in it then
  # counts its NEWLINES as breaks and sails through — and newlines are exactly what Graph discards.
  # Under the naive fix the fixture from the previous test flips ALLOW; under ours it stays DENY.
  local mut="$BATS_TEST_TMPDIR/mutant-naive.py"
  sed -e 's/and not is_structured_html(comment)/and False/' \
      -e 's/^    if source == "comment" and (ctype or "").lower() != "html":/    if False:/' \
      -e 's/^    return bool(_BLOCK_MARKUP_RE.search(content or ""))/    return False/' \
      "$GATE" > "$mut"
  # Instrument controls: all three edits must have landed, or the mutant is not the naive fix.
  grep -q "and False" "$mut"
  grep -q "^    if False:" "$mut"
  grep -q "^    return False" "$mut"

  local long; long="$(python3 -c 'print(("word " * 20 + "\n\n") * 5)')"
  run decision "$mut" mcp__ms365__create-reply-draft "$(tin_comment "$long")"
  [ "$output" = "allow" ]
}

@test "unit: is_structured_html separates markup from prose that merely mentions it" {
  # Called directly, because its effect on a DECISION is masked by the arms above.
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cases = [("<p>x</p>", True), ("<div>x</div>", True), ("a<br>b", True),
         ("<ul><li>x</li></ul>", True), ("<h2>x</h2>", True),
         ("plain prose", False), ("line one\n\nline two", False),
         ("<b>bold</b> only", False), ("<span style=\"color:#000\">x</span>", False),
         ("", False)]
bad = [(c, want, m.is_structured_html(c)) for c, want in cases if m.is_structured_html(c) != want]
print("BAD", bad) if bad else print("OK")
' "$GATE"
  [ "$output" = "OK" ]
}

# ── HOLE-CLOSE: one enormous block ────────────────────────────────────────────────────────────────

@test "an HTML Comment that is one enormous paragraph is refused" {
  # Without MAX_BLOCK_CHARS this passes: the density rule is a whole-body average, and a single
  # <p> inside a wrapper <div> scores enough "breaks" to clear it at any length.
  local wall
  wall="$(python3 -c 'print("<div><p>" + "word " * 200 + "</p></div>", end="")')"
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_comment "$wall")"
  [ "$output" = "deny" ]
}

@test "the same enormous paragraph is refused in Message.body, where the hole predates this fix" {
  local wall
  wall="$(python3 -c 'print("<div><p>" + "word " * 200 + "</p><p>From: quoted chain</p></div>", end="")')"
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_message "$wall")"
  [ "$output" = "deny" ]
}

@test "mutant: raising MAX_BLOCK_CHARS re-opens the enormous-paragraph hole" {
  local mut="$BATS_TEST_TMPDIR/mutant2.py"
  sed 's/^MAX_BLOCK_CHARS = 600/MAX_BLOCK_CHARS = 100000/' "$GATE" > "$mut"
  grep -q "MAX_BLOCK_CHARS = 100000" "$mut"
  local wall
  wall="$(python3 -c 'print("<div><p>" + "word " * 200 + "</p></div>", end="")')"
  run decision "$mut" mcp__ms365__create-reply-draft "$(tin_comment "$wall")"
  [ "$output" = "allow" ]
}

# ── CONTROLS: everything the fix must NOT have touched ────────────────────────────────────────────

@test "a short plain Comment is still allowed" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_comment "Thanks - Tuesday works for me.")"
  [ "$output" = "allow" ]
}

@test "a reply carrying Message.body with no quoted chain is still refused" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_message "<p>Thanks - Tuesday works.</p>")"
  [ "$output" = "deny" ]
}

@test "the four compose-and-send tools are still denied outright" {
  for t in send-mail reply-mail-message reply-all-mail-message forward-mail-message; do
    run decision "$GATE" "mcp__ms365__$t" "$(tin_comment "hello")"
    [ "$output" = "deny" ]
  done
}
