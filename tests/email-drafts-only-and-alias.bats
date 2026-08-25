#!/usr/bin/env bats
# enforce-email-formatting.py — R1 (DRAFTS ONLY) and R2 (ALIAS CONTINUITY).
#
# WHY THIS SUITE EXISTS (2026-08-25). Two classes of outbound mistake the agent could make alone and
# could not undo:
#
#   R1  A Graph send is immediate and irreversible — Outlook's "undo send" is a client-side delay that
#       does not exist on this path. On 2026-08-24 three emails went out in one evening; only the
#       first was authorized, and the third was a legally operative Cal. Civ. Code §1950.5(f) notice
#       in a live deposit dispute. The agent now composes into Drafts and the OPERATOR presses Send.
#
#   R2  The mailbox has two aliases. Every Montway email on order #3414154 was addressed to
#       ichris96@hotmail.com; the dispatch-hold request went out from ren.chris@outlook.com, an
#       address they had never seen on that order, and they dispatched and charged $1,779 anyway.
#
# WHAT MAKES THIS SUITE NON-VACUOUS. Same discipline as email-reply-quote-guard.bats:
#
#   RED-PROOF (pre-R1 allow -> fixed deny): every send tool, replayed against the REAL pre-R1 blob in
#                                           `redproof_prefix_allows_every_send`.
#   CONTROL   (must stay ALLOW):            all four create-*-draft tools, update-mail-message, and
#                                           the read tools. `create-reply-all-draft` is called out by
#                                           name because it is the ONLY working path for a threaded
#                                           reply — if it ever denies, the guardrail has eaten the
#                                           thing it was built to protect.
#
# Without the controls, "deny everything" passes every red-proof case. Without the red-proof cases,
# "allow everything" passes every control.
#
# THE TWO ARMS THAT ARE NOT MERELY DECISIONS. R1 claims to be ABSOLUTE and to fail CLOSED. Neither is
# observable from a happy-path deny, so both are tested directly: `kill_switch_cannot_reopen_a_send`
# sets the documented env override and asserts the send is still refused, and `crash_denies_a_send`
# feeds malformed JSON so the interpreter genuinely dies inside main() and asserts the crash handler
# still denies. A guard that is absolute only while nothing goes wrong is not absolute.
#
# Harness laws (inherited from email-reply-quote-guard.bats): L1 fixtures are literal PreToolUse
# payloads run through the REAL entrypoint; L2 assertions key on the permissionDecision value; L3
# plain `[ ]` only — no negated assertions, which errexit makes dead unless final; L4 every rule has
# both a deny fixture and an allow fixture.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  # R4 (pre-write freshness, 2026-08-25) denies a draft write unless the session has listed
  # RECEIVED mail recently. These fixtures are single calls with no session history, so without
  # this stamp every ALLOW control below would go red for a reason that has nothing to do with
  # R1 or R2 — and, worse, the DENY cases would go green for the wrong reason. Same reasoning as
  # the note in email-reply-quote-guard.bats: R4's own behaviour is covered in its own suite
  # (tests/email-freshness-gate.bats), not smuggled in here.
  touch "$TMPDIR/cc-ms365-inbound-bats" "$TMPDIR/cc-ms365-inbound-bats-ctx"
}

# decision <gate> <tool_name> <tool_input-json> -> prints allow | deny.
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

# context <tool_name> <tool_input-json> -> prints the additionalContext the hook emitted.
# Used to prove the SURFACED half of R2 actually reaches the model, and that a deny names the
# replacement tool rather than just refusing.
context() {
  GATE_UT="$GATE" TOOL="$1" TIN="$2" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": "bats-ctx", "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TIN"])})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print(""); sys.exit(0)
h = json.loads(out)["hookSpecificOutput"]
print(h.get("additionalContext", "") + "\n" + h.get("permissionDecisionReason", ""))
'
}

# raw_decision <raw-stdin> -> prints the decision for a payload we control byte-for-byte, so a
# deliberately malformed one can be fed to the crash path.
raw_decision() {
  RAW="$1" GATE_UT="$GATE" python3 -c '
import json, os, subprocess, sys
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=os.environ["RAW"],
                   capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print("allow"); sys.exit(0)
print(json.loads(out)["hookSpecificOutput"]["permissionDecision"])
'
}

QUOTED_BODY='{"body":{"message":{"body":{"contentType":"html","content":"<p>Hi.</p><blockquote><p>Prior.</p></blockquote>"}}}}'
EMPTY='{}'

tin_from() {
  ADDR="$1" python3 -c '
import json, os
print(json.dumps({"body": {"message": {
    "body": {"contentType": "html", "content": "<p>Hi.</p><blockquote><p>Prior.</p></blockquote>"},
    "from": {"emailAddress": {"address": os.environ["ADDR"]}}}}}))'
}

# ── R1 RED-PROOF: every tool that transmits is refused ─────────────────────────────────────────────

@test "send-mail is refused" {
  run decision "$GATE" mcp__ms365__send-mail "$QUOTED_BODY"
  [ "$output" = "deny" ]
}

@test "reply-mail-message is refused" {
  run decision "$GATE" mcp__ms365__reply-mail-message "$QUOTED_BODY"
  [ "$output" = "deny" ]
}

@test "reply-all-mail-message is refused" {
  run decision "$GATE" mcp__ms365__reply-all-mail-message "$QUOTED_BODY"
  [ "$output" = "deny" ]
}

@test "forward-mail-message is refused" {
  run decision "$GATE" mcp__ms365__forward-mail-message "$QUOTED_BODY"
  [ "$output" = "deny" ]
}

@test "send-draft-message is refused even with an empty tool_input" {
  # It carries no body at all — the composition already happened. A guard that only inspects bodies
  # would wave this straight through, and it is the single call that turns a reviewed draft into an
  # unrecallable send.
  run decision "$GATE" mcp__ms365__send-draft-message "$EMPTY"
  [ "$output" = "deny" ]
}

# ── R1 CONTROLS: the draft path must keep working ──────────────────────────────────────────────────

@test "create-reply-all-draft is ALLOWED — the only working path for a threaded reply" {
  # The negative case that matters most. If this ever denies, the guardrail has eaten the workflow.
  run decision "$GATE" mcp__ms365__create-reply-all-draft "$QUOTED_BODY"
  [ "$output" = "allow" ]
}

@test "create-reply-draft is allowed" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$QUOTED_BODY"
  [ "$output" = "allow" ]
}

@test "create-forward-draft is allowed" {
  run decision "$GATE" mcp__ms365__create-forward-draft "$QUOTED_BODY"
  [ "$output" = "allow" ]
}

@test "create-draft-email is allowed" {
  run decision "$GATE" mcp__ms365__create-draft-email \
    '{"body":{"subject":"Parking permit","body":{"contentType":"html","content":"<p>Hi.</p>"}}}'
  [ "$output" = "allow" ]
}

@test "update-mail-message is allowed, so a draft can still be revised in place" {
  run decision "$GATE" mcp__ms365__update-mail-message \
    '{"body":{"body":{"contentType":"html","content":"<p>Revised.</p>"}}}'
  [ "$output" = "allow" ]
}

@test "a read tool is untouched" {
  run decision "$GATE" mcp__ms365__get-mail-message '{"messageId":"AAA"}'
  [ "$output" = "allow" ]
}

# ── R1 IS ABSOLUTE, AND FAILS CLOSED ───────────────────────────────────────────────────────────────

@test "kill_switch_cannot_reopen_a_send: the documented env override does not reach R1" {
  # CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1 disables the FORMATTING rules by design. R1 sits above it on
  # purpose: an override the model can set is exactly the escape hatch that makes a guard advisory.
  export CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1
  run decision "$GATE" mcp__ms365__send-mail "$QUOTED_BODY"
  [ "$output" = "deny" ]
}

@test "the kill switch DOES still disable the formatting rules — it is not inert" {
  # Control for the case above: without this, R1 could be passing merely because the switch never
  # worked at all, and the "R1 sits above it" claim would be untested.
  export CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1
  run decision "$GATE" mcp__ms365__create-reply-draft \
    '{"body":{"message":{"body":{"contentType":"html","content":"<p>No quote here.</p>"}}}}'
  [ "$output" = "allow" ]
}

@test "crash_denies_a_send: malformed JSON kills main(), and the send is STILL refused" {
  # Genuinely exercises the except branch: json.loads raises inside main(). The formatting gate fails
  # OPEN by design, but a crash must not become consent for the one call that cannot be undone.
  run raw_decision '{"tool_name": "mcp__ms365__send-mail", "tool_input": {NOT VALID JSON'
  [ "$output" = "deny" ]
}

@test "crash on a NON-send payload still fails open, so a hook bug cannot take mail down" {
  # The other half of the fail-closed decision. Scoping the crash-deny to the send tool names is what
  # keeps a malformed read from denying — the operator's constraint was that a bad deny here breaks
  # email for every session on the machine.
  run raw_decision '{"tool_name": "mcp__ms365__get-mail-message", "tool_input": {NOT VALID JSON'
  [ "$output" = "allow" ]
}

@test "a deny names the replacement tool instead of only refusing" {
  # A refusal that leaves the model guessing gets retried in a slightly different shape.
  run context mcp__ms365__reply-all-mail-message "$QUOTED_BODY"
  [[ "$output" == *"create-reply-all-draft"* ]]
}

# ── R2: ALIAS CONTINUITY ───────────────────────────────────────────────────────────────────────────

@test "a from outside the two known aliases is refused" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_from 'chris.ren@gmail.com')"
  [ "$output" = "deny" ]
}

@test "the ichris96 alias is allowed" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_from 'ichris96@hotmail.com')"
  [ "$output" = "allow" ]
}

@test "the ren.chris alias is allowed" {
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_from 'ren.chris@outlook.com')"
  [ "$output" = "allow" ]
}

@test "an alias differing only in case is allowed, not treated as a foreign address" {
  # Graph is case-insensitive on addresses; a case-sensitive set membership test would deny a
  # perfectly valid call. This is a false-positive guard, not a nicety.
  run decision "$GATE" mcp__ms365__create-reply-draft "$(tin_from 'Ren.Chris@Outlook.com')"
  [ "$output" = "allow" ]
}

@test "the alias check reaches the create-draft-email envelope shape too" {
  # create-draft-email puts from at body.from, NOT body.Message.from. A check wired only for the
  # reply envelope would silently miss every fresh draft.
  run decision "$GATE" mcp__ms365__create-draft-email \
    '{"body":{"subject":"Hi","body":{"contentType":"html","content":"<p>Hi.</p>"},"from":{"emailAddress":{"address":"someone@evil.test"}}}}'
  [ "$output" = "deny" ]
}

@test "the alias check reaches the sender spelling too" {
  run decision "$GATE" mcp__ms365__create-draft-email \
    '{"body":{"subject":"Hi","body":{"contentType":"html","content":"<p>Hi.</p>"},"sender":{"emailAddress":{"address":"someone@evil.test"}}}}'
  [ "$output" = "deny" ]
}

@test "setting a valid from does NOT become a bypass for the quote guard" {
  # Caught while writing this change: the alias arm originally returned allow() the moment it saw a
  # well-formed address, which skipped every formatting and quote check below it. A reply with a
  # legitimate alias and no quoted chain must still be refused.
  run decision "$GATE" mcp__ms365__create-reply-draft \
    '{"body":{"message":{"body":{"contentType":"html","content":"<p>No quote.</p>"},"from":{"emailAddress":{"address":"ren.chris@outlook.com"}}}}}'
  [ "$output" = "deny" ]
}

@test "an allowed alias still carries the thread-match advisory to the model" {
  # R2's enforced half only proves the address is ours. The half that cost $1,779 — is it the alias
  # THIS THREAD is on — cannot be checked here, so it must at least be said. If this goes red, the
  # surfaced half has silently become no half at all.
  run context mcp__ms365__create-reply-draft "$(tin_from 'ren.chris@outlook.com')"
  [[ "$output" == *"toRecipients"* ]]
}

# ── THE RED-PROOF CONTROL: replay every send against the REAL pre-R1 artifact ───────────────────────

@test "redproof_prefix_allows_every_send: the pre-R1 hook allowed all five" {
  # Blob 7d69df7e6 is hooks/enforce-email-formatting.py at origin/main immediately before R1 landed.
  # Pinned as a BLOB, not read from origin/main, because after this lands that path IS the fixed file
  # and a control that drifts onto its own subject can only ever agree with it.
  local pre="$BATS_TEST_TMPDIR/pre-r1-hook.py"
  git -C "$REPO" cat-file -p 7d69df7e6 > "$pre"
  [ -s "$pre" ]

  # Positive control on the instrument: the pre-R1 file must NOT contain the symbol R1 adds. The
  # pattern is ANCHORED because the pre-R1 file already defines FRESH_SEND_TOOLS (the threading
  # guard), so a bare `SEND_TOOLS` grep matches it and the control passes vacuously — which is what
  # it did on first run here, and is precisely the rot this control exists to catch.
  run grep -c '^SEND_TOOLS' "$pre"
  [ "$output" = "0" ]

  run decision "$pre" mcp__ms365__send-mail "$QUOTED_BODY"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__reply-mail-message "$QUOTED_BODY"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__reply-all-mail-message "$QUOTED_BODY"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__forward-mail-message "$QUOTED_BODY"
  [ "$output" = "allow" ]

  run decision "$pre" mcp__ms365__send-draft-message "$EMPTY"
  [ "$output" = "allow" ]
}
