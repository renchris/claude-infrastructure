#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# A limit line inherited through a transplant is not a limit on the account the session landed on
# (lr-wake 2026-10-18, REPORT §5 Q7 follow-on, decisions/q7-next2-cap.md, 97%; Wave G).
#
# THE REPLAY, 5232121f: next4 wrote "You've hit your weekly limit · resets 4am (America/Chicago)" at
# 06:51:35Z; the transplant to next2 ran 07:00:25Z-07:05:20Z and byte-copied that line, the tail of
# the next2 transcript, because the stranded session appended nothing after it. The poller then
# logged `PARKED 5232121f (next2, weekly) resets 2026-10-18T09:00:00Z` — next4's reset — while next2
# sat at 0-1%, and set off REROUTE churn. The rule: a limit event dated at or before the newest
# tombstone in another store that handed this sid to THIS store is the source's, never this one's.
# Times are shifted to now (limit 30 min ago, handoff 15 min ago) so the reset parses in the future.
# WHAT IS PINNED:
#   · the inherited line parks nothing and logs one SKIP naming the transplant;
#   · a limit hit AFTER the handoff, on the landing account, still parks (CONTROL);
#   · with no tombstone at all the line parks as before (CONTROL).
# [RED] cases fail on the tree before the fix.

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/cwd"
  CWD="$BATS_TEST_TMPDIR/cwd"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  local s
  for s in osascript tmux cc-decide; do printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/stubs/$s"; done
  chmod +x "$BATS_TEST_TMPDIR/stubs/"*
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  printf '#!/bin/bash\necho %s\n' "'{\"rows\":[{\"acct\":\"next2\",\"session_pct\":1,\"weekly_pct\":1}]}'" > "$HOME/bin/claude-accounts"
  chmod +x "$HOME/bin/claude-accounts"
  export LR_POLLER_NO_CENSUS=1
  export CC_ACCOUNT_MAP="$REPO/lib/account-map.generated.sh"
  export LR_POLLER_CAPACITY_LIB="$REPO/tests/fixtures/lr-poller-capacity-stub.sh"
  SID="5232121f-0000-4000-8000-000000000001"
  SRC="$HOME/.claude-quaternary"; DST="$HOME/.claude-secondary"
  mkdir -p "$SRC/projects/-p" "$DST/projects/-p"
}
iso_ago() { python3 -c "from datetime import datetime,timezone,timedelta;import sys;print((datetime.now(timezone.utc)-timedelta(minutes=int(sys.argv[1]))).isoformat(timespec='milliseconds').replace('+00:00','Z'))" "$1"; }
future_disp() { python3 -c "from datetime import datetime,timezone,timedelta;d=datetime.now(timezone.utc)+timedelta(hours=2);h=d.hour%12 or 12;print(f\"{h}:{d.minute:02d}{'pm' if d.hour>=12 else 'am'}\")"; }
# $1=store $2=limit event minutes ago — the transcript as next4 wrote it and the transplant copied it
mk_limited() {
  local ev; ev="$(iso_ago "$2")"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"go"}}\n' "$CWD" "$ev"
    printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","uuid":"a051ad65-82b8-40f0-bad4-cd8eda6d094a","message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'\''ve hit your weekly limit \\u00b7 resets %s (UTC)"}]}}\n' "$ev" "$(future_disp)"
  } > "$1/projects/-p/$SID.jsonl"
}
# $1=handoff minutes ago — the source's tombstone and its retired copy, naming DST
mk_tombstone() {
  local ts; ts="$(iso_ago "$1" | sed 's/\.[0-9]*Z$/Z/')"
  cp "$DST/projects/-p/$SID.jsonl" "$SRC/projects/-p/$SID.jsonl.handed-off"
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s"}\n' "$DST" "$DST/projects/-p/$SID.jsonl" "$ts" \
    > "$SRC/projects/-p/$SID.HANDOFF.json"
}

@test "1 [RED] 5232121f replay: a limit line inherited through the transplant parks nothing on next2" {
  mk_limited "$DST" 30
  mk_tombstone 15
  run bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -f "$STATE/parked/$SID.json" ] || { cat "$STATE/parked/$SID.json" "$STATE/poller.log"; false; }
  if grep -q "PARKED $SID" "$STATE/poller.log"; then false; fi
  [ "$(grep -c "SKIP  $SID (next2) — its limit line was inherited through the transplant" "$STATE/poller.log")" = 1 ] || { cat "$STATE/poller.log"; false; }
  # the next tick says nothing new
  run bash "$POLLER" --once
  [ "$(grep -c "inherited through the transplant" "$STATE/poller.log")" = 1 ]
}

@test "2 CONTROL a limit hit on next2 AFTER the handoff still parks it on next2" {
  mk_limited "$DST" 10
  mk_tombstone 45
  run bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$STATE/parked/$SID.json" ] || { cat "$STATE/poller.log"; false; }
  [ "$(jq -r .acct "$STATE/parked/$SID.json")" = next2 ]
}

@test "3 CONTROL with no tombstone the limit line parks exactly as before" {
  mk_limited "$DST" 30
  run bash "$POLLER" --once
  [ -f "$STATE/parked/$SID.json" ] || { cat "$STATE/poller.log"; false; }
}
