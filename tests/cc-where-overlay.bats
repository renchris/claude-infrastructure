#!/usr/bin/env bats
# cc-where — the pane census, and specifically the THIRD way a live pane draws zero pixels:
# a kitten overlay mounted on it (kitty window groups). Hermetic: the whole kitty tree is a
# fixture behind CC_WHERE_KITTY_LS, so nothing here reads or touches the operator's live
# kitty. No test in this file executes `kitty`.
#
# WHY THIS SUITE EXISTS (incident 2026-08-07). A ⌘E mis-hit mounted an `open_url_with_hints`
# kitten ("Choose URL") on a working session's pane. The kitten redraws the pane's text plain
# and takes the keyboard, so the pane read as all-white and non-responsive — visually
# identical to a hung client. The session was fine: main thread parked in kevent64, and it
# answered `kitty @ send-text` instantly, because the API addresses the base window and
# bypasses the overlay. cc-where listed the kitten as a fifth ordinary pane titled
# "Choose URL" and said nothing about what it was covering, so the census — the one tool
# whose entire job is "where is my session and why can't I see it" — could not answer.
#
# THE CONTROL. `groups` is the only field carrying the overlay edge (kitty 0.48 `ls` has no
# overlay_for), and it was verified against real overlays before this was written.
#
# 🚨 THE TRAP THIS SUITE EXISTS TO PIN. `groups[].windows` is NOT in stacking order and is not
# stable. Three identical launches on kitty 0.48.2 (os-window base, then `launch
# --type=overlay --keep-focus` on it) produced:
#     run1 [480, 481]    run2 [483, 482]    run3 [485, 484]     base = 480 / 482 / 484
# — base first once, last twice, from the same script. The first implementation read position
# ("first element is the overlay"), passed its fixture, and then named the WRONG pane as the
# one to press ESC in when run against a live overlay. That is worse than silence, because the
# operator acts on it. The discriminator is `created_at`: the base is the OLDEST member of the
# group, true by construction — an overlay cannot predate the window it is mounted on.
#
# So `covered` and `covered_reversed` below are the SAME situation with the group array in
# OPPOSITE order, and must produce identical verdicts. A positional implementation passes one
# and fails the other; that pair is the mutation control for this whole file.
# `no_overlay` is the negative control — without it an implementation that flagged every pane
# would pass. `no_created_at` pins the fail-OPEN direction.

setup() {
  # Hermetic $HOME: cc-where reads none of it today, but a suite that runs against the
  # operator's live ~/ is one subject change away from doing so, and the ratchet is right.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/bin/cc-where"
  D="$BATS_TEST_TMPDIR"

  # One OS window, one active tab, two real session panes (471, 480). 472 is a "Choose URL"
  # kitten overlaid on 471 — exactly the incident's shape, including the real timestamps:
  # the session pane was created 05:33 and the kitten at 13:51, eight hours later.
  BASE_AT=1786106001848862000     # 05:33:21 — the session pane
  OVL_AT=1786135910573980000      # 13:51:50 — the ⌘E kitten
  SIB_AT=1786127774233656000      # 11:36:14 — an unrelated sibling pane

  _tree() { # $1=group array for the covered pair  $2=extra window objects
    cat <<EOF
[{"id": 11, "tabs": [{
  "id": 18, "is_active": true, "layout": "splits",
  "groups": [$1, {"id": 571, "windows": [480]}],
  "windows": [
    {"id": 471, "pid": 100, "title": "Add two-way text fade", "cwd": "/w/a",
     "columns": 149, "lines": 38, "is_active": false, "is_focused": false,
     "created_at": $BASE_AT},
    $2
    {"id": 480, "pid": 102, "title": "Fix dead holder lock", "cwd": "/w/b",
     "columns": 149, "lines": 38, "is_active": true, "is_focused": false,
     "created_at": $SIB_AT}]}]}]
EOF
  }
  KITTEN="{\"id\": 472, \"pid\": 101, \"title\": \"Choose URL\", \"cwd\": \"/w/a\",
     \"columns\": 149, \"lines\": 38, \"is_active\": false, \"is_focused\": false,
     \"created_at\": $OVL_AT},"

  # The two group orderings kitty actually emits for the SAME overlay. Both must be read
  # identically; a positional implementation passes exactly one of them.
  _tree '{"id": 570, "windows": [472, 471]}' "$KITTEN" >"$D/covered.json"
  _tree '{"id": 570, "windows": [471, 472]}' "$KITTEN" >"$D/covered-reversed.json"

  # NEGATIVE CONTROL: same tree with the kitten gone and 471 standing alone in its group.
  _tree '{"id": 570, "windows": [471]}' "" >"$D/no-overlay.json"

  # DEGRADE CONTROL: kitty too old to report `groups`. Same panes, no group array at all.
  cat >"$D/no-groups.json" <<EOF
[{"id": 11, "tabs": [{
  "id": 18, "is_active": true, "layout": "splits",
  "windows": [
    {"id": 471, "pid": 100, "title": "Add two-way text fade", "cwd": "/w/a",
     "columns": 149, "lines": 38, "is_active": false, "is_focused": false,
     "created_at": $BASE_AT},
    {"id": 480, "pid": 102, "title": "Fix dead holder lock", "cwd": "/w/b",
     "columns": 149, "lines": 38, "is_active": true, "is_focused": false,
     "created_at": $SIB_AT}]}]}]
EOF

  # FAIL-OPEN CONTROL: a group of two with no created_at to tell base from overlay. The
  # attribution is unknowable, and naming the wrong pane is worse than naming none.
  cat >"$D/no-created-at.json" <<'EOF'
[{"id": 11, "tabs": [{
  "id": 18, "is_active": true, "layout": "splits",
  "groups": [{"id": 570, "windows": [472, 471]}],
  "windows": [
    {"id": 471, "pid": 100, "title": "Add two-way text fade", "cwd": "/w/a",
     "columns": 149, "lines": 38, "is_active": false, "is_focused": false},
    {"id": 472, "pid": 101, "title": "Choose URL", "cwd": "/w/a",
     "columns": 149, "lines": 38, "is_active": false, "is_focused": false}]}]}]
EOF
}

j() { CC_WHERE_KITTY_LS="$D/$1.json" python3 "$W" --json; }
r() { CC_WHERE_KITTY_LS="$D/$1.json" python3 "$W"; }

@test "covered pane is marked not-on-screen, hidden_by overlay, naming its coverer" {
  run j covered
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
rows={r["win"]: r for r in json.load(sys.stdin)}
b=rows[471]
assert b["on_screen"] is False, "buried pane still reported on_screen"
assert b["hidden_by"] == "overlay", b["hidden_by"]
assert b["covered_by"] == 472, b["covered_by"]
assert b["covered_by_title"] == "Choose URL", b["covered_by_title"]
assert b["is_overlay"] is False
'
}

@test "the kitten is flagged as an overlay and names the pane it covers" {
  run j covered
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
o={r["win"]: r for r in json.load(sys.stdin)}[472]
assert o["is_overlay"] is True
assert o["covers"] == 471, o["covers"]
'
}

@test "an uncovered sibling in the same tab is untouched" {
  run j covered
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
s={r["win"]: r for r in json.load(sys.stdin)}[480]
assert s["on_screen"] is True
assert s["covered_by"] is None, s["covered_by"]
assert s["hidden_by"] == ""
'
}

@test "an overlay does not inflate the tab pane count" {
  run j covered
  [ "$status" -eq 0 ]
  # 3 windows, but 2 groups = 2 real session panes. Counting windows read "3 panes" and is
  # how the kitten passed for a session in the incident.
  echo "$output" | python3 -c '
import json,sys
for r in json.load(sys.stdin):
    assert r["tab_panes"] == 2, r["tab_panes"]
'
}

@test "ORDER CONTROL: the reversed group array yields the identical verdict" {
  # This is the mutation control for the whole file. kitty emitted BOTH orders for the same
  # overlay across three identical runs; reading position instead of created_at inverts the
  # verdict here and tells the operator to press ESC in the pane that is working fine.
  run j covered-reversed
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
rows={r["win"]: r for r in json.load(sys.stdin)}
assert rows[471]["covered_by"] == 472, "base and overlay inverted: " + repr(rows[471])
assert rows[471]["is_overlay"] is False
assert rows[472]["is_overlay"] is True
assert rows[472]["covers"] == 471
assert rows[480]["covered_by"] is None
'
}

@test "FAIL-OPEN CONTROL: no created_at means no attribution, never a guessed one" {
  run j no-created-at
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
for r in json.load(sys.stdin):
    assert r["covered_by"] is None, r
    assert r["is_overlay"] is False, r
'
  run r no-created-at
  [[ "$output" != *"BURIED"* ]] || false
}

@test "NEGATIVE CONTROL: identical tree without the overlay reports no coverage" {
  run j no-overlay
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
for r in json.load(sys.stdin):
    assert r["covered_by"] is None, r
    assert r["is_overlay"] is False, r
    assert r["on_screen"] is True, r
    assert r["tab_panes"] == 2, r["tab_panes"]
'
}

@test "DEGRADE CONTROL: a tree with no groups key censuses as before, never blank" {
  run j no-groups
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
rows=json.load(sys.stdin)
assert len(rows) == 2, len(rows)
for r in rows:
    assert r["covered_by"] is None
    assert r["on_screen"] is True
    assert r["tab_panes"] == 2, r["tab_panes"]
'
}

@test "human census leads with the buried-pane verdict and the ESC remedy" {
  run r covered
  [ "$status" -eq 0 ]
  [[ "$output" == *"BURIED UNDER A KITTEN OVERLAY"* ]] || false
  [[ "$output" == *"press ESC"* ]] || false
  # The remedy must sit on the buried pane's own row too, not only in the header.
  [[ "$output" == *"covered by win 472"* ]] || false
  # And the lid must render as a lid, not as a peer session.
  [[ "$output" == *"OVERLAY covering win 471"* ]]
}

@test "human census stays silent about overlays when there are none" {
  run r no-overlay
  [ "$status" -eq 0 ]
  [[ "$output" != *"BURIED"* ]] || false
  [[ "$output" != *"OVERLAY"* ]]
}

@test "--go refuses to send the operator into a kitten" {
  # "Choose URL" matches no session, so this is a miss (rc 1), not a successful jump to a lid.
  CC_WHERE_KITTY_LS="$D/covered.json" run python3 "$W" --go 'Choose URL'
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing matches"* ]]
}
