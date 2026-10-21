#!/usr/bin/env bats
# Regression guard for PANE 69 (2026-10-20): a fired peer that RECYCLED FROM A SUBDIRECTORY of the cwd
# its fired-peer stamp records could not self-close.
#
# THE INCIDENT, measured. Pane 69 was fired into …/tm-upstream-wt (stamp cwd, marker
# HANDOFF-ENGAGE-63792-…). Its session's shell was in …/tm-upstream-wt/.publish-state when it ran
# `handoff-fire.sh --recycle`, so the successor booted THERE. fired_stamp_tenancy compares the two
# cwds EXACTLY, so the recycle read the stamp as `stale` and hf_recycle_inherits_peer conferred
# nothing: no self-retire trailer in the successor's brief, no recycledAt on the stamp. The finished
# successor's `self-close --terminal` then hit the stale-stamp refusal ("belongs to a DIFFERENT
# session … an ORIGIN session under a reused id"), and neither recovery could prove it: adoption looks
# up the SUBDIRECTORY's cwd key, and the repair proof needs the trailer the recycle never wrote.
#
# THE FIX, pinned here with tests that are red on the pre-fix code:
#   · hf_peer_in_stamped_tree — `stale` ONLY because $PWD is a strict subdirectory of the stamp's cwd,
#     the stamp is OPEN, and its marker ARRIVED (inbound, never merely mentioned) in this pane's own
#     session or a recycle predecessor joined by handoff-fire's recycle-engaged row;
#   · a recycle from inside the stamped tree inherits the contract on that proof (trailer, re-anchor,
#     and the stamp's cwd follows the pane to the dir the successor boots in);
#   · self-close accepts the same proof, so a pane ALREADY in pane 69's state can retire.
# The negatives are the load-bearing half: a sibling dir, a spent stamp, a session that only READ the
# marker (a foreign tenant under a reused id), an origin session, and the kill switch all still refuse.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_TERM=iterm2

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  command -v jq >/dev/null || skip "jq required"

  # HERMETICITY — every default in the subject resolves under $HOME; pin it and the seams that do not.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR/projects"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export HF_HANDOFFS_LOG="$HOME/.claude/logs/handoffs.jsonl"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/absent-permission-pending"
  export CC_CLASSIFY_SESSIONS_BIN="$BATS_TEST_TMPDIR/absent-cc-sessions"
  export CC_CLOSE_LEDGER_GUARD=0
  unset CLAUDE_CODE_SESSION_ID

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  cat > "$SHIM/osascript" <<'SH'
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in -e) shift 2 2>/dev/null || shift ;; -) shift ;; *) uuid="$1"; shift ;; esac
done
[ -n "$uuid" ] && printf '%s' "TTY-$uuid"
exit 0
SH
  # git: no directory here is a work tree, so the cwd-scoped tree guards are skipped hermetically.
  printf '#!/bin/sh\n[ "$1" = rev-parse ] && exit 1\nexit 0\n' > "$SHIM/git"
  printf '#!/bin/sh\nexit 0\n' > "$SHIM/ps"
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  HEADING="$(sed -n "s/^SELF_RETIRE_CONTRACT_HEADING='\(.*\)'$/\1/p" "$HF" | head -1)"
  [ -n "$HEADING" ] || { echo "could not read SELF_RETIRE_CONTRACT_HEADING from $HF"; return 1; }

  PEER="69000000-bbbb-4000-8000-000000000069"
  SID_ROOT="adace0e2-8686-44bb-bf29-c1ee685e7705"     # the session the fire landed
  SID_NOW="4c5832b5-259b-4973-9d14-e5e7fbfa3387"      # the session the recycle booted
  ENGAGE="HANDOFF-ENGAGE-63792-1792386024-13596"
  RECYCLE="HANDOFF-RECYCLE-60889-1792448682-17218"
  mkdir -p "$BATS_TEST_TMPDIR/tm-upstream-wt/.publish-state" "$BATS_TEST_TMPDIR/tm-upstream-wt2"
  D="$(cd "$BATS_TEST_TMPDIR/tm-upstream-wt" && pwd -P)"
  SUB="$D/.publish-state"
  SIBLING="$(cd "$BATS_TEST_TMPDIR/tm-upstream-wt2" && pwd -P)"   # a string-PREFIX of D, not inside it
  SLUG="-x-tm-upstream-wt"; mkdir -p "$CC_PROJECTS_DIRS/$SLUG"
}

# transcript <sid> <first-user-text> <brief-iso-ts> [extra-jsonl-line]
transcript() {
  local f="$CC_PROJECTS_DIRS/$SLUG/$1.jsonl"
  {
    jq -nc '{type:"user", isMeta:true, message:{content:"hook context"}}'
    jq -nc --arg t "$2" --arg ts "$3" '{type:"user", timestamp:$ts, message:{content:$t}}'
    [ -z "${4:-}" ] || printf '%s\n' "$4"
    jq -nc '{type:"assistant", message:{content:[{type:"text",text:"done"}], stop_reason:"end_turn"}}'
  } > "$f"
}
root_brief() {
  printf 'TASK — publish.\n\n## BACK-CHANNEL — ping the originator (research-kit-24)\nping it.\n\n%s\n  1. DRIVE it.\n\n<!-- handoff-fire engagement marker: %s (ignore) -->\n' "$HEADING" "$ENGAGE"
}
# The pane-69 recycle brief: a HANDOFF-RECYCLE marker and NO trailer (the contract was not inherited).
recycle_brief() { printf 'PHASE 2 — continue.\n\n<!-- handoff-fire recycle engagement marker: %s (ignore) -->\n' "$RECYCLE"; }
row() { # $1=sid $2=cwd
  jq -nc --arg p "$PEER" --arg s "$1" --arg c "$2" --argjson pid "$$" \
    '{paneUUID:$p, session_id:$s, cwd:$c, pid:$pid, startedAt:1792448740000}' > "$CC_REGISTRY_DIR/$PEER.json"
}
recycle_row() { # $1=prev-sid $2=ts
  jq -nc --arg p "$PEER" --arg s "$1" --arg t "$2" \
    '{ts:$t, class:"recycle-engaged", gate:"recycle", engaged:true, target_pane:$p, prev_sid:$s}' >> "$HF_HANDOFFS_LOG"
}
stamp() { # $1=cwd [$2=closedAt]
  jq -n --arg p "$PEER" --arg c "$1" --arg m "$ENGAGE" --arg closed "${2:-}" \
    '{paneUUID:$p, cwd:$c, firedBy:"24", firedAt:"2026-10-19T05:02:23Z", selfRetire:true, schema:2,
      originClass:"fired-peer", originator:"24", notifyBack:"research-kit-24", marker:$m,
      closedAt:(if $closed == "" then null else $closed end), succession:null}' > "$CC_FIRED_DIR/$PEER.json"
}
# The pane-69 state: stamp in D, the recycled session (in D/.publish-state) joined to the root.
state_69() {
  stamp "$D"
  row "$SID_NOW" "$SUB"
  transcript "$SID_ROOT" "$(root_brief)" "2026-10-19T05:01:40.000Z"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-10-19T22:25:40.186Z"
  recycle_row "$SID_ROOT" "2026-10-19T22:26:11Z"
}
selfclose_in() { ( cd "$1" && ITERM_SESSION_ID="w0t0p0:$PEER" bash "$HF" self-close --terminal --dry-run 2>&1 ); }
refused_stale() { [ "$status" -eq 2 ] && [[ "$output" == *"belongs to a DIFFERENT session"* ]]; }

load_fns() {
  FN="$BATS_TEST_TMPDIR/fns.sh"
  {
    echo '. "'"$REPO"'/hooks/lib/origin-identity.sh"'
    for f in cc_sid_for_pane transcript_for_sid hf_recycle_predecessor fired_marker_owner \
             hf_peer_in_stamped_tree hf_recycle_inherits_peer; do
      awk "/^$f\\(\\) \\{/,/^\\}/" "$HF"
    done
  } > "$FN"
  # shellcheck disable=SC1090
  . "$FN"
  export REG_DIR="$CC_REGISTRY_DIR"
}

# ── self-close ───────────────────────────────────────────────────────────────────────────────────

@test "pane 69 repro: the recycled peer self-closes from a SUBDIRECTORY of its stamped cwd" {
  state_69
  run selfclose_in "$SUB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"self-close REFUSED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"inside the stamped tree"* ]] || { echo "the authorisation change is not announced: $output"; false; }
  # The stamp is the original fire's — never re-minted, never set aside.
  [ "$(jq -r .cwd "$CC_FIRED_DIR/$PEER.json")" = "$D" ]
  [ "$(jq -r .marker "$CC_FIRED_DIR/$PEER.json")" = "$ENGAGE" ]
  [ -z "$(ls "$CC_FIRED_DIR" | grep superseded || true)" ] || { ls "$CC_FIRED_DIR"; false; }
}

@test "two recycles deep, both from the subdirectory, still resolve to the root fire" {
  local mid="11111111-2222-4333-8444-555555555555"
  stamp "$D"; row "$SID_NOW" "$SUB"
  transcript "$SID_ROOT" "$(root_brief)" "2026-10-19T05:01:40.000Z"
  transcript "$mid" "$(recycle_brief)" "2026-10-19T12:00:00.000Z"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-10-19T22:25:40.186Z"
  recycle_row "$SID_ROOT" "2026-10-19T12:00:20Z"
  recycle_row "$mid" "2026-10-19T22:26:11Z"
  run selfclose_in "$SUB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "REFUSED: a FOREIGN tenant in the subdirectory that only READ the stamp (marker in tool output, not its prompt)" {
  stamp "$D"; row "$SID_NOW" "$SUB"
  # An unrelated session under the reused id `cat`-ed the stamp: the marker sits in a tool_result.
  local leak
  leak="$(jq -nc --arg m "$ENGAGE" '{type:"user", toolUseResult:{stdout:$m},
           message:{content:[{type:"tool_result", content:("\"marker\": \"" + $m + "\"")}]}}')"
  transcript "$SID_NOW" "just an operator session" "2026-10-20T01:00:00.000Z" "$leak"
  run selfclose_in "$SUB"
  refused_stale || { echo "a foreign tenant under a reused id was authorised: $output"; false; }
}

@test "REFUSED: an origin session in the subdirectory with no marker anywhere" {
  stamp "$D"; row "$SID_NOW" "$SUB"
  transcript "$SID_NOW" "just an operator session" "2026-10-20T01:00:00.000Z"
  run selfclose_in "$SUB"
  refused_stale || { echo "$output"; false; }
}

@test "REFUSED: a SIBLING dir that merely shares the stamp cwd as a string prefix" {
  state_69; row "$SID_NOW" "$SIBLING"
  run selfclose_in "$SIBLING"
  refused_stale || { echo "/x/wt2 read as inside /x/wt: $output"; false; }
}

@test "REFUSED: a SPENT stamp read from the subdirectory is not resurrected" {
  state_69; stamp "$D" "2026-10-20T00:00:00Z"
  run selfclose_in "$SUB"
  [ "$status" -eq 2 ] || { echo "a used-up contract authorised a second close: $output"; false; }
}

@test "REFUSED: kill switch CC_SELFCLOSE_SUBTREE=0 restores the exact-cwd refusal" {
  state_69
  CC_SELFCLOSE_SUBTREE=0 run selfclose_in "$SUB"
  refused_stale || { echo "$output"; false; }
}

# ── the recycle that started it ──────────────────────────────────────────────────────────────────

@test "hf_recycle_inherits_peer: a recycle from inside the stamped tree INHERITS (the root session recycling)" {
  load_fns
  stamp "$D"; row "$SID_ROOT" "$SUB"
  transcript "$SID_ROOT" "$(root_brief)" "2026-10-19T05:01:40.000Z"
  hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PEER" "$SUB" 0 || { echo "pane 69's recycle conferred nothing"; false; }
  # …and a foreign tenant recycling from the same subdirectory does not.
  transcript "$SID_ROOT" "just an operator session" "2026-10-19T05:01:40.000Z"
  ! hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PEER" "$SUB" 0 || { echo "a foreign tenant inherited"; false; }
}

@test "END-TO-END: a recycle from the subdirectory composes the self-retire trailer" {
  export TMPDIR="$BATS_TEST_TMPDIR"
  stamp "$D"; row "$SID_ROOT" "$SUB"
  transcript "$SID_ROOT" "$(root_brief)" "2026-10-19T05:01:40.000Z"
  printf 'CONTINUE the work.\n' > "$BATS_TEST_TMPDIR/p.md"
  run bash -c "cd '$SUB' && ITERM_SESSION_ID='w1t0p0:$PEER' bash '$HF' --prompt-file '$BATS_TEST_TMPDIR/p.md' --launcher claude-test --recycle --dry-run 2>&1"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  copy="$(printf '%s\n' "$output" | sed -n 's/.*\(handoff-prompt-nb-[A-Za-z0-9]*\).*/\1/p' | head -1)"
  [ -n "$copy" ] || { echo "no trailer copy composed for a recycle inside the stamped tree"; echo "$output"; false; }
  grep -qF -- "$HEADING" "$BATS_TEST_TMPDIR/$copy" || { cat "$BATS_TEST_TMPDIR/$copy"; false; }
}

@test "the subtree inherit MIGRATES the stamp to the dir the successor boots in (structural: one call site)" {
  run grep -c 'hf_migrate_peer_stamp "\$FIRED_DIR"' "$HF"
  [ "$output" = 1 ] || { echo "expected exactly one migration call site, got $output"; false; }
  run grep -B1 'hf_migrate_peer_stamp "\$FIRED_DIR"' "$HF"
  [[ "$output" == *'RCY_INHERIT_SUBTREE" = 1'* ]] || { echo "the migration is not reached by a subtree inherit: $output"; false; }
}
