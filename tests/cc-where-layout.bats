#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats: every @test body is its own subshell.
#
# cc-where — the LAYOUT RULE alert (lr-wake incident 2026-10-18, REPORT §4 Wave D): any OS window
# with more than 1 tab or more than 4 panes is named, first, in the census, and `--layout` exits 1.
# Overnight OS window 18 held 18 tabs (13 of them dead shells nobody could see) and OS windows 16 and
# 20 held 5 panes each; nothing on the box said so.
#
# RED on origin/main: no alert line and no --layout verb (usage, exit 64).
# Hermetic: the kitty tree is a fixture behind CC_WHERE_KITTY_LS; cc-cloud and osascript are stubs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/bin/cc-where"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  mkdir -p "$D/bin"
  printf '#!/bin/bash\nexit 1\n' > "$D/bin/osascript"
  printf '#!/bin/bash\necho "[]"\n' > "$D/bin/cc-cloud"
  printf '#!/bin/bash\nexit 0\n' > "$D/bin/kitty"
  chmod +x "$D/bin/osascript" "$D/bin/cc-cloud" "$D/bin/kitty"
  export PATH="$D/bin:$PATH" CC_WHERE_CLOUD_BIN="$D/bin/cc-cloud"
  export CC_WHERE_KITTY_LS="$D/tree.json"
  unset CC_MAX_PANES_PER_SPACE
}

# tree <osw>:<tab>=<ids,…>[;<tab>=<ids,…>] …  — one arg per OS window
tree() {
  python3 -c '
import json, sys
out = []
for spec in sys.argv[2:]:
    osw, tabs = spec.split(":", 1)
    tl = []
    for i, t in enumerate(tabs.split(";")):
        tid, ids = t.split("=")
        tl.append({"id": int(tid), "is_active": i == 0, "layout": "splits",
                   "windows": [{"id": int(w), "title": "s%s" % w, "columns": 90, "is_active": j == 0}
                               for j, w in enumerate(ids.split(","))]})
    out.append({"id": int(osw), "tabs": tl})
json.dump(out, open(sys.argv[1], "w"))' "$CC_WHERE_KITTY_LS" "$@"
}

@test "a 2-tab OS window and a 5-pane OS window are each named first in the census" {
  tree "18:146=344;170=430" "16:160=8,47,246,374,445" "7:70=1,2,3"
  run "$W"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'LAYOUT RULE BROKEN.* kitty window 18: 2 tabs' || { echo "$output"; false; }
  echo "$output" | grep -q 'LAYOUT RULE BROKEN.* kitty window 16: 5 panes (max 4)' || { echo "$output"; false; }
  ! echo "$output" | grep -q 'kitty window 7:' || false
  # answer-first: the alerts come before the tree
  first_alert="$(echo "$output" | grep -n 'LAYOUT RULE BROKEN' | head -1 | cut -d: -f1)"
  first_tree="$(echo "$output" | grep -n '▸ ' | head -1 | cut -d: -f1)"
  [ "$first_alert" -lt "$first_tree" ]
}

@test "--layout exits 1 and names each violation; exit 0 and says ok on a compliant layout" {
  tree "18:146=344;170=430" "7:70=1,2,3,4"
  run "$W" --layout
  [ "$status" -eq 1 ]
  [ "$output" = "cc-where: LAYOUT RULE BROKEN — kitty window 18: 2 tabs" ]
  tree "18:146=344,345" "7:70=1,2,3,4"
  run "$W" --layout
  [ "$status" -eq 0 ]
  [ "$output" = "cc-where: layout ok — 2 OS window(s), each 1 tab and at most 4 panes" ]
}

@test "CONTROL: a compliant layout prints no alert in the census" {
  tree "18:146=344,345,346,347" "7:70=1"
  run "$W"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'LAYOUT RULE BROKEN' || false
}

@test "the pane cap follows CC_MAX_PANES_PER_SPACE" {
  tree "7:70=1,2,3"
  CC_MAX_PANES_PER_SPACE=2 run "$W" --layout
  [ "$status" -eq 1 ]
  [ "$output" = "cc-where: LAYOUT RULE BROKEN — kitty window 7: 3 panes (max 2)" ]
}
