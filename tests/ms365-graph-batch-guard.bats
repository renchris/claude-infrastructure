#!/usr/bin/env bats
# enforce-email-formatting.py — R1c (A BATCH MAY ONLY READ).
#
# WHY THIS SUITE EXISTS (2026-09-14). R1 denies the four ms365 tools that compose and transmit in
# one call, and calls itself ABSOLUTE. It was one indirection away from optional: the Softeria
# ms-365-mcp-server also exposes `graph-batch` (POST /$batch), which forwards up to 20 RAW Graph
# requests in a single tool call. A batched {"method":"POST","url":"/me/sendMail"} reaches the same
# irreversible send with no send tool anywhere in the payload — so no matcher fired, no guard ran,
# and the rule held only against a model that used the named tools. Measured the same day: the ms365
# PreToolUse matcher in all four fleet config dirs contained zero occurrences of `graph-batch`.
#
# WHAT MAKES THIS SUITE NON-VACUOUS (same discipline as email-drafts-only-and-alias.bats):
#
#   RED-PROOF  The batched-POST payload is replayed against the REAL pre-R1c hook, read out of git
#              (`redproof_prefix_allows_a_batched_send`). It must ALLOW there and DENY here. A
#              hand-written stub would prove nothing about the artifact that actually shipped.
#   CONTROLS   A batch of GETs, a top-level GET list, ANOTHER server's graph-batch, and a non-ms365
#              tool must all stay ALLOW. Without them, "deny everything" passes every deny case.
#
# The controls are the load-bearing half in BOTH directions here. The deny is fail-CLOSED — an
# unreadable or empty request list is refused — which is the inverse of this file's default posture,
# so the reach of that closure is exactly what has to be pinned. `mcp__other__graph-batch` is named
# because the set is EXACT TOOL NAMES, never a `graph-batch` suffix match: a suffix match would
# silently police every other MCP server on the machine.
#
# Harness laws (inherited): L1 fixtures are literal PreToolUse payloads run through the REAL
# entrypoint; L2 assertions key on the permissionDecision value; L3 plain `[ ]` only — no negated
# assertions, which errexit makes dead unless final; L4 every rule has both a deny and an allow.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE="$REPO/hooks/enforce-email-formatting.py"
  unset CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
}

# decision <gate> <tool_name> <tool_input-json> -> prints allow | deny.
# NOTE: unlike the sibling suites this does NOT splice an `account` key into tool_input. R1c fires
# above R2, and a graph-batch payload in the wild carries only `body`; adding a field the real call
# never has would test a shape production cannot produce.
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

# reason <tool_name> <tool_input-json> -> the permissionDecisionReason the hook emitted.
reason() {
  GATE_UT="$GATE" TOOL="$1" TIN="$2" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": "bats-r", "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TIN"])})
p = subprocess.run([sys.executable, os.environ["GATE_UT"]], input=pay, capture_output=True, text=True)
out = p.stdout.strip()
if not out:
    print(""); sys.exit(0)
print(json.loads(out)["hookSpecificOutput"].get("permissionDecisionReason", ""))
'
}

# raw_decision <raw-stdin> -> decision for a payload we control byte-for-byte (crash path).
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

SENDMAIL_BATCH='{"body":{"requests":[{"id":"1","method":"GET","url":"/me"},{"id":"2","method":"POST","url":"/me/sendMail","body":{"message":{"subject":"x"}}}]}}'
GET_BATCH='{"body":{"requests":[{"id":"1","method":"GET","url":"/me"},{"id":"2","method":"get","url":"/me/events"}]}}'

# ── DENY: a batch that carries a write ────────────────────────────────────────────────

@test "R1c: a batched POST /me/sendMail is denied" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$SENDMAIL_BATCH")" = deny ]
}

@test "R1c: a lowercase post is still a post" {
  tin='{"body":{"requests":[{"id":"1","method":"post","url":"/me/messages/AAA/send"}]}}'
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$tin")" = deny ]
}

@test "R1c: a batched PATCH is denied (the rule is GET-only, not sendMail-only)" {
  tin='{"body":{"requests":[{"id":"1","method":"PATCH","url":"/me/messages/AAA"}]}}'
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$tin")" = deny ]
}

@test "R1c: the Copilot-CLI dialect is guarded too" {
  [ "$(decision "$GATE" ms365-graph-batch "$SENDMAIL_BATCH")" = deny ]
}

# ── DENY: fail-closed on a list this guard cannot read ────────────────────────────────

@test "R1c: a batch with no request list is denied" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch '{"body":{}}')" = deny ]
}

@test "R1c: an empty request list is denied" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch '{"body":{"requests":[]}}')" = deny ]
}

@test "R1c: a request list that is not a list is denied" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch '{"body":{"requests":"GET /me"}}')" = deny ]
}

@test "R1c: a request with no method at all is denied" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch '{"body":{"requests":[{"id":"1","url":"/me"}]}}')" = deny ]
}

@test "R1c: a crash on a graph-batch denies rather than failing open" {
  [ "$(raw_decision '{"tool_name":"mcp__ms365__graph-batch","tool_input":')" = deny ]
}

@test "R1c: the kill switch cannot reopen a batched send" {
  CLAUDE_EMAIL_FORMAT_GATE_DISABLED=1
  export CLAUDE_EMAIL_FORMAT_GATE_DISABLED
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$SENDMAIL_BATCH")" = deny ]
}

@test "R1c: the deny names the replacement tool, not just the refusal" {
  r="$(reason mcp__ms365__graph-batch "$SENDMAIL_BATCH")"
  n="$(printf '%s' "$r" | grep -cF 'create-draft-email')" || true
  [ "${n:-0}" -gt 0 ]
}

# ── ALLOW controls: without these, "deny everything" passes every case above ──────────

@test "R1c control: a batch of GETs passes" {
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$GET_BATCH")" = allow ]
}

@test "R1c control: a top-level requests list of GETs passes" {
  [ "$(decision "$GATE" ms365-graph-batch '{"requests":[{"id":"1","method":"GET","url":"/me"}]}')" = allow ]
}

@test "R1c control: ANOTHER server's graph-batch is untouched" {
  tin='{"body":{"requests":[{"id":"1","method":"POST","url":"/x"}]}}'
  [ "$(decision "$GATE" mcp__other__graph-batch "$tin")" = allow ]
}

@test "R1c control: a non-ms365 tool is untouched" {
  [ "$(decision "$GATE" Bash '{"command":"echo hi"}')" = allow ]
}

@test "R1c control: an ms365 READ tool still passes" {
  [ "$(decision "$GATE" mcp__ms365__list-mail-messages '{"account":"ren.chris@outlook.com"}')" = allow ]
}

# ── RED-PROOF: the REAL pre-R1c artifact, read out of git, must ALLOW ─────────────────
#
# THE REF IS A LITERAL SHA, AND THAT IS THE WHOLE POINT. `HEAD:` would read the pre-fix file
# exactly once — on this branch, before the land — and then advance past the fix, after which the
# "pre" artifact IS the fixed one and the control compares the fix to itself. It does not go red
# when that happens; it passes, asserting nothing, which is the failure mode that never gets found.
# 2d6c608ca is the commit this fix was written on top of, and it is already on trunk, so a rebasing
# land cannot rewrite it.
#
# The pin alone is not enough either: re-point the sha by accident and it goes vacuous again in
# silence. So the replay also asserts a MARKER — an identifier the fix INTRODUCED — is absent from
# the pre artifact and present in the gate under test. Measured, not read off the prose:
# MS365_BATCH_TOOLS greps 0 at 2d6c608ca and 4 in the current hook. Asserting BOTH directions is
# what stops a mistyped marker from grepping 0 on both sides and passing for free.
PRE_FIX_SHA=2d6c608ca
FIX_MARKER=MS365_BATCH_TOOLS

# pre_fix_hook -> path to the pre-R1c artifact, replayed from the pinned sha and proven to be it.
pre_fix_hook() {
  local pre="$BATS_TEST_TMPDIR/pre-r1c.py" n
  git -C "$REPO" show "$PRE_FIX_SHA:hooks/enforce-email-formatting.py" > "$pre"
  [ -s "$pre" ] || return 1
  # ABSENT from the replay...
  n="$(grep -c "$FIX_MARKER" "$pre")" || true
  [ "${n:-0}" -eq 0 ] || return 1
  # ...and PRESENT in the subject, so the marker itself cannot be a typo that matches nothing.
  n="$(grep -c "$FIX_MARKER" "$GATE")" || true
  [ "${n:-0}" -gt 0 ] || return 1
  printf '%s' "$pre"
}

@test "R1c red-proof: the pre-R1c hook allowed a batched send" {
  pre="$(pre_fix_hook)"
  [ -s "$pre" ]
  # The bypass, in the artifact that shipped: allowed there, denied by the gate under test.
  [ "$(decision "$pre" mcp__ms365__graph-batch "$SENDMAIL_BATCH")" = allow ]
  [ "$(decision "$GATE" mcp__ms365__graph-batch "$SENDMAIL_BATCH")" = deny ]
}

@test "R1c red-proof: the pre-R1c hook also allowed the Copilot dialect" {
  pre="$(pre_fix_hook)"
  [ -s "$pre" ]
  [ "$(decision "$pre" ms365-graph-batch "$SENDMAIL_BATCH")" = allow ]
}

@test "R1c red-proof: the pinned ref is on trunk, so a rebasing land cannot rewrite it" {
  git -C "$REPO" merge-base --is-ancestor "$PRE_FIX_SHA" origin/main
}
