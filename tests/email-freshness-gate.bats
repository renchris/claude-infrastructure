#!/usr/bin/env bats
# enforce-email-formatting.py — R4, PRE-WRITE FRESHNESS: the draft is fine, the world moved.
#
# WHY THIS SUITE EXISTS (2026-08-25). A dispute letter was reviewed for 23 minutes — MIME parsed,
# indentation and font verified twice — while the counterparty's automated acknowledgement, a
# written 24-hour commitment, sat unread in the inbox. It had arrived 23 minutes before the send.
# The letter shipped asserting "I was not given a callback time": true of the phone call, false of
# the record. Verifying the ARTIFACT is not verifying the SITUATION.
#
# Sends are human-executed (R1, drafts-only), so there is no send call left to gate. The DRAFT
# WRITE is the last agent operation in an email flow, and that is where R4 stands.
#
# WHAT MAKES THIS SUITE NON-VACUOUS. The entire difficulty of this gate is the INBOUND
# distinction. In the final 20 minutes before that send the mailbox was queried SIX times, and
# every one was scoped `isDraft eq true` or was a read of our OWN draft. A gate that accepted "any
# mailbox read" would have passed all six and prevented nothing — so `draft_scoped_read_*` and
# `single_message_read_*` below are the load-bearing cases, and each is paired with an otherwise
# IDENTICAL payload that differs only in being an inbound list. Without those pairs, "count every
# read" would satisfy the suite. Without the ALLOW controls, "deny every draft" would.
#
# The gate is deliberately STRICTER than the original spec ("any read of a message that is not our
# own draft"). A PreToolUse hook sees only tool_name + tool_input, so on get-mail-message it has an
# opaque messageId and cannot know whether it is a draft this session just created — and reading
# back your own draft is RECIPE step 4, i.e. the read most likely to be sitting in the window.
# Counting it would reopen the exact hole. Only a non-draft-scoped LIST satisfies R4. That is
# pinned by `single_message_read_does_not_satisfy` so the loosening is a visible decision, not a
# silent drift.
#
# Harness laws: L1 fixtures are literal PreToolUse payloads through the REAL entrypoint; L2
# assertions key on permissionDecision; L3 plain `[ ]` only.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  unset CC_MS365_FRESHNESS_MIN
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  SID="bats-fresh"
}

# call <tool> <tool_input-json> -> allow | deny, run in session $SID against the real hook.
call() {
  GATE_UT="$GATE" TOOL="$1" TIN="$2" SID_UT="$SID" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": os.environ["SID_UT"], "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"], "tool_input": json.loads(os.environ["TIN"])})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print("allow"); sys.exit(0)
print(json.loads(out)["hookSpecificOutput"]["permissionDecision"])
'
}

# A draft write with a real, well-formed HTML body carrying a quote, so that NO other arm of the
# hook can be what fires — only R4 can. (Quote marker present => the quote guard passes; <p> tags
# and length => the wall-of-text and density arms pass.)
DRAFT_BODY='<div style="color:#000000"><p style="margin:0 0 12px 0;">Thanks for the update on the order. I have gone through the timeline again and want to put the sequence in one place so we are working from the same record, rather than trading recollections about who said what.</p><p style="margin:0 0 12px 0;">Happy to do this by phone if that is easier for you.</p></div><hr><div id="divRplyFwdMsg"><b>From:</b> them@example.com<br><b>Sent:</b> Monday<br><b>Subject:</b> Your order</div>'

draft_tin() {
  CONTENT="$DRAFT_BODY" python3 -c '
import json, os
print(json.dumps({"body": {"Message": {"body": {"contentType": "html",
                                                "content": os.environ["CONTENT"]}}}}))'
}

# The same body in the two OTHER envelope shapes Graph accepts. Built in python, never inlined
# into shell-quoted JSON: DRAFT_BODY contains double quotes (id="divRplyFwdMsg"), and splicing it
# into a '{"…"}' literal produces malformed JSON — which the hook then cannot parse, so the call
# fails OPEN and the test passes for a reason that has nothing to do with R4.
draft_email_tin() {
  CONTENT="$DRAFT_BODY" python3 -c '
import json, os
print(json.dumps({"body": {"subject": "Hello",
                           "body": {"contentType": "html", "content": os.environ["CONTENT"]}}}))'
}

update_tin() {
  CONTENT="$DRAFT_BODY" python3 -c '
import json, os
print(json.dumps({"messageId": "AAA=",
                  "body": {"body": {"contentType": "html", "content": os.environ["CONTENT"]}}}))'
}

# reason <tool> <tool_input-json> -> the deny text, so its remediation can be asserted.
reason() {
  GATE_UT="$GATE" TOOL="$1" TIN="$2" SID_UT="$SID" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": os.environ["SID_UT"], "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"], "tool_input": json.loads(os.environ["TIN"])})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
print(json.loads(p.stdout)["hookSpecificOutput"]["permissionDecisionReason"])
'
}

INBOUND='{"select":"id,subject","top":10}'
INBOUND_FILTERED='{"filter":"from/emailAddress/address eq '"'"'them@example.com'"'"' and receivedDateTime ge 2026-08-25T20:00:00Z"}'
DRAFT_SCOPED='{"filter":"isDraft eq true","select":"id,subject","top":10}'

age_marker() { # push the inbound stamp back N seconds
  SECS="$1" M="$TMPDIR/cc-ms365-inbound-$SID" python3 -c '
import os, time
p = os.environ["M"]; back = time.time() - float(os.environ["SECS"])
os.utime(p, (back, back))'
}

# ── RED-PROOF: an "any mailbox read" gate passes every one of these ────────────────────────────────

@test "a draft write with no prior mailbox read at all is refused" {
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "draft_scoped_read_does_not_satisfy: a list filtered isDraft eq true is not an inbound read" {
  # The exact shape of the six blind queries that preceded the 2026-08-25 send.
  call mcp__ms365__list-mail-messages "$DRAFT_SCOPED"
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "a list scoped to the drafts FOLDER is not an inbound read either" {
  call mcp__ms365__list-mail-folder-messages '{"mailFolderId":"drafts","top":5}'
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "single_message_read_does_not_satisfy: get-mail-message-mime on one id is not enough" {
  # RECIPE step 4 tells you to read your OWN draft's MIME back. If that counted, the gate would
  # be satisfiable by the very read that proves nothing about the counterparty.
  call mcp__ms365__get-mail-message-mime '{"messageId":"AAA="}'
  call mcp__ms365__get-mail-message '{"messageId":"AAA="}'
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "an inbound read that has gone stale stops satisfying the gate" {
  call mcp__ms365__list-mail-messages "$INBOUND"
  age_marker 3600
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "a fresh create-draft-email is gated too, not just replies" {
  run call mcp__ms365__create-draft-email "$(draft_email_tin)"
  [ "$output" = "deny" ]
}

@test "the deny names the retry call and says a draft read will not do" {
  # grep, not [[ ]]: under errexit only the LAST [[ ]] in a test can fail it, so the first two
  # would have been dead assertions. tests/bats-assert-liveness.bats catches exactly that.
  run reason mcp__ms365__create-reply-draft "$(draft_tin)"
  printf '%s' "$output" | grep -q "receivedDateTime ge"
  printf '%s' "$output" | grep -q "isDraft eq true"
  printf '%s' "$output" | grep -q "InefficientFilter"
}

# ── CONTROLS: a "deny every draft" gate fails every one of these ───────────────────────────────────

@test "the first draft after a plain inbound list passes with no friction" {
  # If this ever goes red the gate is wrong, not the caller. Reading the thread then writing the
  # reply is the ordinary flow and must cost nothing.
  call mcp__ms365__list-mail-messages "$INBOUND"
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "the counterparty-and-since filter from the RECIPE satisfies the gate" {
  call mcp__ms365__list-mail-messages "$INBOUND_FILTERED"
  run call mcp__ms365__create-reply-all-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "a KQL search list counts as inbound too" {
  call mcp__ms365__list-mail-messages '{"search":"\"from:them@example.com\""}'
  run call mcp__ms365__create-forward-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "update-mail-message carrying a body is gated, and the same call after a read passes" {
  # The PATCH that lands a spliced reply. Pair: identical tool, identical body, differing ONLY in
  # whether an inbound read preceded it — so neither "gate update-mail-message always" nor "never"
  # can satisfy both halves.
  SID="bats-upd-a"
  run call mcp__ms365__update-mail-message "$(update_tin)"
  [ "$output" = "deny" ]
  SID="bats-upd-b"
  call mcp__ms365__list-mail-messages "$INBOUND"
  run call mcp__ms365__update-mail-message "$(update_tin)"
  [ "$output" = "allow" ]
}

@test "update-mail-message with no body — flagging, marking read — is never gated" {
  run call mcp__ms365__update-mail-message '{"messageId":"AAA=","body":{"isRead":true}}'
  [ "$output" = "allow" ]
}

@test "read tools are never gated by R4" {
  run call mcp__ms365__list-mail-messages "$INBOUND"
  [ "$output" = "allow" ]
  run call mcp__ms365__get-mail-message '{"messageId":"AAA="}'
  [ "$output" = "allow" ]
}

@test "CC_MS365_FRESHNESS_MIN=0 disables R4 over a real refusal" {
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
  export CC_MS365_FRESHNESS_MIN=0
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "the kill switch also disables R4" {
  export CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "a garbage window value falls back to the default instead of crashing the hook" {
  export CC_MS365_FRESHNESS_MIN=not-a-number
  call mcp__ms365__list-mail-messages "$INBOUND"
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "a marker location that cannot be written fails OPEN — a hook bug never strands the operator" {
  # NOT done by chmod-ing TMPDIR: python's tempfile.gettempdir() probes its candidates and
  # silently falls back to /tmp when TMPDIR is unwritable, so that version of this test passed
  # through a perfectly writable directory and never reached the fail-open branch at all.
  # Occupying the probe path with a DIRECTORY makes touch() raise IsADirectoryError for real.
  mkdir -p "$TMPDIR/cc-ms365-inbound-$SID.probe"
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "allow" ]
}

@test "POSITIVE CONTROL for the above: without the blocked probe the same call is denied" {
  run call mcp__ms365__create-reply-draft "$(draft_tin)"
  [ "$output" = "deny" ]
}

@test "R4 does not reorder R1: a send is still refused, read or no read" {
  call mcp__ms365__list-mail-messages "$INBOUND"
  run call mcp__ms365__send-mail '{"body":{"Message":{"subject":"x","body":{"contentType":"html","content":"<p>x</p>"}}}}'
  [ "$output" = "deny" ]
}
