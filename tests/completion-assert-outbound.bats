#!/usr/bin/env bats
# completion-assert.sh ARM O — OUTBOUND SOURCE READ. A Stop whose turn hands the operator a drafted
# outbound message is blocked unless the SAME turn read the live medium with a primary-source tool
# (operator ruling 2026-10-18: "a hard no for us drafting messages to people based off of some
# medium when we havent read said medium"). Decision: hooks/lib/outbound_source_read.py.
#
# The cases are the brief's (a)-(e) plus the shapes the incident adds: the incident turn's only
# live calls were `msg search "Elm"` → "(no matches)" and `msg search "Example"` → one unrelated
# 2023 row (a search is not a read, (f)); a read that returned nothing (h); and the arm firing once
# per turn, with a Stop-hook feedback record NOT opening a new turn (g).
#
# RED-proof (2026-10-18, on scratch copies, never the live hook): (a), (e), (f), (g)'s first Stop
# and the ms365 case go silent with the arm's `if` forced false; (f) goes silent when THREAD_SUBS
# admits `search` (its first fixture carried only an empty search, which the empty-result rule
# also rejects, so that mutant could not turn it red; the "Example" row is why it can now);
# (h) goes silent when result_empty() is forced false; (e) goes silent when the lib judges the
# whole transcript instead of the turn; (g) re-blocks when the latch check is removed; (b) and (c)
# block when the Bash live-verb reader returns nothing.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/completion-assert.sh"
  # HOME is the live-capture dirs' root (~/Documents/zillow-listings) and the research-route store;
  # never the operator's.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CLAUDE_CONFIG_DIR CC_OUTBOUND_SOURCE_READ COMPLETION_OUTBOUND_MAX
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  TP="$BATS_TEST_TMPDIR/t.jsonl"; : > "$TP"
  CWD="$BATS_TEST_TMPDIR/personal"; mkdir -p "$CWD"
}

# ── fixture writers: one JSONL record each, all main-chain ──
prompt()  { jq -cn --arg ts "$1" --arg t "$2" '{type:"user",timestamp:$ts,message:{role:"user",content:$t}}' >> "$TP"; }
skill()   { # the outbound-drafting skill loaded: the Skill call plus the body the harness injects
  { jq -cn --arg ts "$1" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"sk1",name:"Skill",input:{skill:"outbound-drafting"}}]}}'
    jq -cn --arg ts "$1" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"sk1",content:"Launching skill: outbound-drafting"}]}}'
    jq -cn --arg ts "$1" '{type:"user",isMeta:true,timestamp:$ts,message:{role:"user",content:[{type:"text",text:"Base directory for this skill: /x/skills/outbound-drafting\n\n# Drafting messages"}]}}'
  } >> "$TP"
}
tool()    { # <ts> <id> <name> <input-json> <result-text>
  { jq -cn --arg ts "$1" --arg id "$2" --arg n "$3" --argjson in "$4" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:$in}]}}'
    jq -cn --arg ts "$1" --arg id "$2" --arg r "$5" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$r}]}}'
  } >> "$TP"
}
say()     { jq -cn --arg ts "$1" --arg t "$2" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TP"; }
bash_()   { tool "$1" "$2" Bash "$(jq -cn --arg c "$3" '{command:$c}')" "$4"; }

DRAFT=$'Here is the first text for Sam:\n\n```\nHi Sam, I\'m interested in 12 Elm St. Could you send current photos of each room?\n\nChris\n```'
T0=2026-10-18T10:00:00.000Z; T1=2026-10-18T12:00:00.000Z; T2=2026-10-18T12:00:05.000Z; T3=2026-10-18T12:00:09.000Z

stop() { run bash "$HOOK" <<< "$(jq -cn --arg tp "$TP" --arg cwd "$CWD" '{session_id:"sid-o",transcript_path:$tp,cwd:$cwd}')"; }
assert_block() {
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .decision)" = block ]
  [[ "$(printf '%s' "$output" | jq -r .reason)" == "OUTBOUND SOURCE READ:"* ]]
}
assert_pass() {
  [ "$status" -eq 0 ]
  [[ "$output" != *"OUTBOUND SOURCE READ"* ]]
}

@test "(a) a draft whose only source read is our own dossier is BLOCKED, naming the live tools" {
  prompt "$T1" "Draft the first text to the Elm landlord"
  skill "$T1"
  tool "$T2" r1 Read "$(jq -cn --arg p "$CWD/research/landlords-2026-10-18/elm-12.md" '{file_path:$p}')" "Status: listed last night. Availability: unknown."
  say "$T3" "$DRAFT"
  stop
  assert_block
  [[ "$output" == *"bin/zillow-listing"* && "$output" == *"msg with"* ]]
}

@test "(b) a draft after 'msg with' on the counterparty's thread passes" {
  prompt "$T1" "Reply to Sam"
  skill "$T1"
  bash_ "$T2" b1 'msg with "+15125550100" | head -20' "live  2026-10-18 11:50:02  +15125550100  <-  Yes it is available now, want photos?"
  say "$T3" "$DRAFT"
  stop
  assert_pass
}

@test "(c) a draft after bin/zillow-listing on the listing passes" {
  prompt "$T1" "Draft the first text to the Elm landlord"
  skill "$T1"
  bash_ "$T2" z1 'timeout 120 bin/zillow-listing "https://www.zillow.com/homedetails/12-Elm-St/10000001_zpid/"' "Status: Available now. 19 photo link(s), 19 downloaded; facts.md"
  say "$T3" "$DRAFT"
  stop
  assert_pass
}

@test "(d) a turn with no drafted message passes, in a session that loaded the skill" {
  prompt "$T1" "How often does the Elm lot flood?"
  skill "$T1"
  tool "$T2" r1 Read "$(jq -cn --arg p "$CWD/research/elm-12.md" '{file_path:$p}')" "FEMA Zone AO (1 ft)."
  say "$T3" "Hi, short answer: about a 1-in-85 chance over a 14-month lease. The house sits on a raised floor."
  stop
  assert_pass
}

@test "(e) a read in an EARLIER turn does not cover a draft in this one: BLOCKED" {
  prompt "$T0" "Reply to Sam"
  skill "$T0"
  bash_ "$T0" b1 'msg with "+15125550100"' "live  2026-10-18 09:58:00  +15125550100  <-  It's available now."
  say "$T0" "$DRAFT"
  prompt "$T1" "Make it shorter"
  say "$T3" "$DRAFT"
  stop
  assert_block
}

@test "(f) the incident: a msg SEARCH is not a read of the medium, even when it returns a row: BLOCKED" {
  prompt "$T1" "Draft the first text to the Elm landlord"
  skill "$T1"
  bash_ "$T2" s1 'msg search "Elm" 2>/dev/null | head -5' "(no matches)"
  bash_ "$T2" s2 'msg search "Example" 2>/dev/null | head -5' $'mid   2023-01-31 23:06:11  +15125550199  <-  Pat Example - Acme\n\n1 row(s)'
  say "$T3" "$DRAFT"
  stop
  assert_block
}

@test "(h) a thread read that returned nothing read nothing: BLOCKED" {
  prompt "$T1" "Reply to Sam"
  skill "$T1"
  bash_ "$T2" w1 'msg with "+15125550100"' $'(no matches)\n0 row(s)'
  say "$T3" "$DRAFT"
  stop
  assert_block
}

@test "(g) once per turn: the reply to the block's own feedback is not a new turn, and the other arms still run" {
  prompt "$T1" "Draft the first text to the Elm landlord"
  skill "$T1"
  say "$T2" "$DRAFT"
  stop
  assert_block
  jq -cn --arg ts "$T3" '{type:"user",isMeta:true,timestamp:$ts,message:{role:"user",content:"Stop hook feedback:\nOUTBOUND SOURCE READ: …"}}' >> "$TP"
  say "$T3" "$DRAFT"
  stop
  assert_pass
  # fell through to the downstream gate rather than exiting at the latch
  [ "$(tail -1 "$COMPLETION_IDL" | jq -r .reason)" = no-close-tell ]
}

@test "ms365: a create-reply-draft after only a drafts-scoped list is BLOCKED; a received-mail list passes" {
  prompt "$T1" "Reply to Connie's email"
  tool "$T2" m1 mcp__ms365__list-mail-folder-messages '{"mailFolderId":"drafts"}' '{"value":[{"subject":"RE: carpet","isDraft":true}]}'
  tool "$T2" d1 mcp__ms365__create-reply-draft '{"messageId":"AAMk1"}' '{"id":"AAMk2","isDraft":true}'
  say "$T3" "The reply is in Drafts."
  stop
  assert_block
  rm -rf "$COMPLETION_STATE_DIR"
  tool "$T3" m2 mcp__ms365__list-mail-messages '{"filter":"receivedDateTime ge 2026-10-18T11:00:00Z"}' '{"value":[{"subject":"RE: carpet","from":"connie@example.com"}]}'
  stop
  assert_pass
}

@test "kill switch CC_OUTBOUND_SOURCE_READ=0 silences the arm" {
  prompt "$T1" "Draft the first text to the Elm landlord"
  skill "$T1"
  say "$T2" "$DRAFT"
  export CC_OUTBOUND_SOURCE_READ=0; stop
  assert_pass
}
