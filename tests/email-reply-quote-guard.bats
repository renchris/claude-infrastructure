#!/usr/bin/env bats
# enforce-email-formatting.py — the REPLY QUOTE GUARD: a reply that threads but shows no history.
#
# WHY THIS SUITE EXISTS (2026-08-25). The guard it covers shipped as a LIVE, UNCOMMITTED edit in the
# shared checkout that ~/.claude symlinks into — gating the operator's real outbound mail while trunk
# carried zero trace of it. One `git checkout --` would have reverted a live safety behaviour
# silently. It also had no test at all, which is why it could sit there: nothing went red.
#
# THE DEFECT IT GUARDS. Microsoft Graph auto-quotes the prior message ONLY when you pass `Comment`.
# Passing `Message.body` REPLACES that auto-quote. The reply then threads correctly at the protocol
# level — In-Reply-To and References are still set — but arrives VISUALLY ORPHANED: the recipient sees
# a bare note with no history, reading as a brand-new email. It cost a real defect on 2026-08-24, and
# the operator caught it in Outlook, not here. The pre-existing guard only inspected FRESH_SEND_TOOLS,
# so a reply carrying Message.body was never inspected at all.
#
# WHAT MAKES THIS SUITE NON-VACUOUS — and it is MEASURED, not asserted. Every case below was run
# against BOTH the pre-fix hook and the fixed one before its assertion was written:
#
#   RED-PROOF (pre-fix allow -> fixed deny): short-body, long-body, forward, uppercase-Message-key.
#   CONTROL   (identical on both):            short Comment, quoted body, long Comment, fresh send,
#                                             a body whose quote marker is "wrote:".
#
# Without the controls, "deny every reply" would satisfy every red-proof case. Without the red-proof
# cases, "allow everything" would satisfy every control. `redproof_prefix_allows` below re-runs the
# four red-proof fixtures against the REAL pre-fix artifact so the suite cannot rot into vacuity: it
# pins BLOB a3d229c9e, not `origin/main:hooks/…`, because after this fix lands that path IS the fixed
# file and a control read from it would silently start agreeing with the subject.
#
# SCOPE. This suite pins the guard's CURRENT behaviour; it does not endorse every part of it. The
# quote-marker list is deliberately loose — a bare "from:" or "wrote:" anywhere in the body counts as
# a quoted chain (case `marker_wrote_is_accepted`). That is a real false-negative surface, pinned here
# so that tightening it later is a visible, deliberate change rather than an unnoticed one.
#
# Harness laws (inherited from curl-gate-decide.bats): L1 fixtures are literal PreToolUse payloads run
# through the REAL entrypoint, so main()'s tool scoping and JSON emission are covered too; L2
# assertions key on the permissionDecision value; L3 plain `[ ]` only — no negated assertions, which
# errexit makes dead unless final; L4 every rule has both a deny fixture and an allow fixture.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  # The gate's kill switch would make EVERY case allow, so an inherited env var could turn this whole
  # suite green while proving nothing. Clear it explicitly rather than trusting the caller's shell.
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"  # the recipe-once marker lands here
}

# decision <gate> <tool_name> <tool_input-json> -> prints allow | deny.
# An empty stdout is the gate's implicit allow, so it is mapped here rather than left looking like a
# crash. A gate that dies is not silently forgiven: the hook's own fail-open wrapper prints an
# explicit allow, so an empty stdout from a crashed interpreter still surfaces as a decision we can
# read, and a malformed one raises here instead of passing.
decision() {
  GATE_UT="$1" TOOL="$2" TIN="$3" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": "bats", "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TIN"])})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print("allow"); sys.exit(0)
print(json.loads(out)["hookSpecificOutput"]["permissionDecision"])
'
}

# --- fixtures -------------------------------------------------------------------------------------
# tin_message <html> [envelope-key] -> a reply carrying Message.body, the field that REPLACES the
# auto-quote. The envelope key is parameterised because the ms365 server has shipped BOTH `Message`
# and `message`, and dig()'s case-insensitive lookup is what makes the guard reach either.
tin_message() {
  CONTENT="$1" KEY="${2:-message}" python3 -c '
import json, os
print(json.dumps({"body": {os.environ["KEY"]: {"body": {"contentType": "html",
                                                        "content": os.environ["CONTENT"]}}}}))'
}

tin_comment() {
  COMMENT="$1" python3 -c '
import json, os
print(json.dumps({"body": {"Comment": os.environ["COMMENT"]}}))'
}

SHORT_BODY='<p>Thanks - Tuesday works for me.</p>'

# A well-formed HTML body over MIN_LEN with real <p> breaks, so the pre-existing wall-of-text and
# density arms CANNOT be what fires — only the quote guard can. Keeping it under DENSITY_FLOOR (700
# visible chars) is deliberate for the same reason.
long_body() {
  local out='' i
  for i in $(seq 0 11); do out="${out}<p>Line ${i} of the reply, with enough text to count here.</p>"; done
  printf '%s' "$out"
}

# ── RED-PROOF: each of these is ALLOWED by the pre-fix hook and DENIED by the fixed one ────────────

@test "a short reply carrying Message.body with no quoted chain is refused" {
  # The 2026-08-24 shape exactly: brief enough that Comment was the right field, sent via Message.body,
  # so Graph's auto-quote was replaced by nothing. Pre-fix this fell straight through the MIN_LEN
  # short-circuit and was never inspected.
  run decision "$GATE" mcp__ms365__reply-mail-message "$(tin_message "$SHORT_BODY")"
  [ "$output" = "deny" ]
}

@test "a long reply carrying Message.body with no quoted chain is refused" {
  run decision "$GATE" mcp__ms365__reply-all-mail-message "$(tin_message "$(long_body)")"
  [ "$output" = "deny" ]
}

@test "a forward carrying Message.body with no quoted chain is refused" {
  # Forwards lose history the same way, and are the case most likely to be read as "not a reply".
  run decision "$GATE" mcp__ms365__forward-mail-message "$(tin_message "$SHORT_BODY")"
  [ "$output" = "deny" ]
}

@test "the guard reaches the uppercase Message envelope key too" {
  # dig() is case-insensitive by design; a case-sensitive lookup once made this whole gate inert on
  # the reply paths (2026-08-12). This pins that the new arm inherits the fix rather than re-breaking.
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_message "$SHORT_BODY" Message)"
  [ "$output" = "deny" ]
}

# ── CONTROLS: identical on both versions — without these, "deny every reply" passes the four above ──

@test "a short reply carrying Comment is allowed" {
  # Comment is the CORRECT field for a short reply: Graph auto-quotes the original for you.
  run decision "$GATE" mcp__ms365__reply-mail-message "$(tin_comment 'Thanks - Tuesday works.')"
  [ "$output" = "allow" ]
}

@test "a reply carrying Message.body WITH an appended quote is allowed" {
  run decision "$GATE" mcp__ms365__reply-mail-message \
    "$(tin_message "${SHORT_BODY}<blockquote><p>Original note.</p></blockquote>")"
  [ "$output" = "allow" ]
}

@test "marker_wrote_is_accepted: a bare 'wrote:' counts as a quoted chain" {
  # Pinning the loose end named in SCOPE above: this is accepted today. If the marker list is ever
  # tightened, this case goes red and the change becomes visible instead of silent.
  run decision "$GATE" mcp__ms365__reply-mail-message \
    "$(tin_message "${SHORT_BODY}<p>On Mon, Ann wrote:</p>")"
  [ "$output" = "allow" ]
}

@test "an over-length Comment is still refused, as it was before" {
  # Both versions deny this; the reason text differs but the decision must not. Graph strips newlines
  # from a long Comment into one unreadable paragraph — the original 2026-06-12 defect.
  local long_comment
  long_comment="$(python3 -c 'print("word " * 80)')"
  run decision "$GATE" mcp__ms365__reply-mail-message "$(tin_comment "$long_comment")"
  [ "$output" = "deny" ]
}

@test "a fresh send-mail carrying Message.body is untouched by the reply guard" {
  # The scoping control. send-mail has no prior message to quote, so the new arm must not reach it —
  # if REPLY_TOOLS ever grows to include a fresh-send tool, this goes red.
  run decision "$GATE" mcp__ms365__send-mail "$(tin_message "$SHORT_BODY")"
  [ "$output" = "allow" ]
}

@test "the fresh-send threading guard still fires on a RE: subject" {
  # Pre-existing behaviour the salvage patch also touched (its guidance text). The DECISION must be
  # unchanged: a fresh send with a reply subject has no In-Reply-To/References and breaks the chain.
  local tin
  tin="$(python3 -c 'import json; print(json.dumps({"body":{"message":{"subject":"RE: parking permit"}}}))')"
  run decision "$GATE" mcp__ms365__send-mail "$tin"
  [ "$output" = "deny" ]
}

# ── THE RED-PROOF CONTROL: replay the four deny fixtures against the REAL pre-fix artifact ─────────

@test "redproof_prefix_allows: the pre-fix hook allows every fixture the guard now denies" {
  # Blob a3d229c9e is the pre-fix file — verified 2026-08-25 to be byte-identical to
  # origin/main:hooks/enforce-email-formatting.py at that time. It is PINNED as a blob rather than
  # read from origin/main because after this fix lands that path becomes the FIXED file, and a
  # control that drifts onto its own subject can only ever agree with it.
  local pre="$BATS_TEST_TMPDIR/prefix-hook.py"
  git -C "$REPO" cat-file -p a3d229c9e > "$pre"
  [ -s "$pre" ]

  # Positive control on the instrument itself: the pre-fix file must NOT contain the symbol the fix
  # adds. If a future rewrite makes this blob unreachable or wrong, this fails loudly rather than
  # certifying a vacuous replay.
  run grep -c REPLY_TOOLS "$pre"
  [ "$output" = "0" ]

  run decision "$pre" mcp__ms365__reply-mail-message "$(tin_message "$SHORT_BODY")"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__reply-all-mail-message "$(tin_message "$(long_body)")"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__forward-mail-message "$(tin_message "$SHORT_BODY")"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__create-reply-draft "$(tin_message "$SHORT_BODY" Message)"
  [ "$output" = "allow" ]
}
