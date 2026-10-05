#!/usr/bin/env bats
# scripts/lib/restore-heartbeat.sh — the 300 s record of the live fleet that a hard power-off restore
# reads (W3 P3a-i). Every case drives the library under /bin/bash 3.2, because launchd runs it there
# (lesson: the deployment interpreter is not the one on your PATH). HOME is a fixture, and
# cc-sessions, kitten, ps and lsof are stubs: nothing here reads the live registry or the live kitty.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  LIB="$REPO/scripts/lib/restore-heartbeat.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$D/absent-repo"   # hermeticity: no live converge
  export CC_HEARTBEAT_DIR="$D/hb" CC_BOOTUUID_OVERRIDE=UUID-A CC_HB_NOW=1784800000
  export CC_ROLES_DIR="$D/roles" CC_HB_MAILBOX_DIR="$D/mailbox" CC_HB_AGENT_BROWSER_DIR="$D/ab"
  mkdir -p "$CC_ROLES_DIR" "$CC_HB_MAILBOX_DIR" "$CC_HB_AGENT_BROWSER_DIR"
  export CC_HB_SESSIONS_BIN="$D/stub-sessions" CC_HB_KITTEN_BIN="$D/stub-kitten"
  export CC_HB_PS_BIN="$D/stub-ps" CC_HB_LSOF_BIN="$D/stub-lsof"
  printf '#!/bin/sh\n[ -f "$0.fail" ] && exit 1\ncat "%s/sessions.json"\n' "$D" > "$CC_HB_SESSIONS_BIN"
  printf '#!/bin/sh\necho "$*" >> "$0.log"\n[ -f "$0.fail" ] && exit 1\necho "[{\\"id\\": 1, \\"tabs\\": []}]"\n' > "$CC_HB_KITTEN_BIN"
  printf '#!/bin/sh\ncat "%s/ps.txt"\n' "$D" > "$CC_HB_PS_BIN"
  printf '#!/bin/sh\ncat "%s/lsof.txt"\n' "$D" > "$CC_HB_LSOF_BIN"
  chmod +x "$CC_HB_SESSIONS_BIN" "$CC_HB_KITTEN_BIN" "$CC_HB_PS_BIN" "$CC_HB_LSOF_BIN"
  : > "$D/ps.txt"; : > "$D/lsof.txt"
  KP=$$                                   # a LIVE kitty pid: this test's own process
  sleep 0 & DEADP=$!; wait "$DEADP"       # a pid that is certainly not alive any more
  echo '[]' > "$D/sessions.json"
}

hb() { run /bin/bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }
sess() { # <sid> <kitty_pid> [pid] [cwd] [account] [pane]
  printf '{"session_id":"%s","kitty_pid":%s,"pid":%s,"cwd":"%s","account":"%s","paneUUID":"%s","name":"N-%s","kitty_listen_on":"unix:/tmp/kitty-test"}' \
    "$1" "$2" "${3:-1}" "${4:-/nonexistent/$1}" "${5:-claude-next}" "${6:-P$1}" "$1"
}
dir() { printf '%s/%s/%s' "$CC_HEARTBEAT_DIR" "$1" "$2"; }

@test "a tick writes all six files into <bootuuid>/<kitty-pid>/, hb.start one line, no temp left" {
  echo "[$(sess s1 "$KP"),$(sess s2 "$KP")]" > "$D/sessions.json"
  hb hb_tick
  [ "$status" -eq 0 ] || false
  for f in hb.roster.json hb.start hb.session.tsv hb.kitty-ls.json hb.bg.tsv hb.roles.tsv; do
    [ -f "$(dir UUID-A "$KP")/$f" ] || { echo "missing $f"; false; }
  done
  [ "$(jq length "$(dir UUID-A "$KP")/hb.roster.json")" -eq 2 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ -z "$(find "$CC_HEARTBEAT_DIR" -name '.*.tmp*')" ] || false
  grep -q -- '@ --to unix:/tmp/kitty-test ls' "$CC_HB_KITTEN_BIN.log" || false
}

@test "never overwritten across either key: a new boot uuid and a new kitty pid each get their own dir" {
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
  hb hb_tick
  echo "[$(sess s2 "$KP")]" > "$D/sessions.json"
  CC_BOOTUUID_OVERRIDE=UUID-B CC_HB_NOW=1784800300 hb hb_tick
  echo "[$(sess s3 "$PPID")]" > "$D/sessions.json"
  CC_BOOTUUID_OVERRIDE=UUID-B CC_HB_NOW=1784800600 hb hb_tick
  [ "$(jq -r '.[0].session_id' "$(dir UUID-A "$KP")/hb.roster.json")" = s1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ "$(jq -r '.[0].session_id' "$(dir UUID-B "$PPID")/hb.roster.json")" = s3 ] || false
}

@test "a dead kitty's last heartbeat is never rewritten; a live kitty with no session left records []" {
  mkdir -p "$(dir UUID-A "$DEADP")" "$(dir UUID-A "$KP")"
  echo "[$(sess old "$DEADP")]" > "$(dir UUID-A "$DEADP")/hb.roster.json"; echo 1784799000 > "$(dir UUID-A "$DEADP")/hb.start"
  echo "[$(sess gone "$KP")]" > "$(dir UUID-A "$KP")/hb.roster.json"; echo 1784799000 > "$(dir UUID-A "$KP")/hb.start"
  echo "[$(sess old "$DEADP")]" > "$D/sessions.json"   # a registry row still naming the dead kitty
  hb hb_tick
  [ "$(cat "$(dir UUID-A "$DEADP")/hb.start")" = 1784799000 ] || false
  [ "$(jq -c . "$(dir UUID-A "$KP")/hb.roster.json")" = '[]' ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
}

@test "cc-sessions failing or not parsing writes nothing and keeps the last good heartbeat (rc 2)" {
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
  hb hb_tick
  touch "$CC_HB_SESSIONS_BIN.fail"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$status" -eq 2 ] || false
  rm "$CC_HB_SESSIONS_BIN.fail"; echo 'not json' > "$D/sessions.json"
  CC_HB_NOW=1784800600 hb hb_tick
  [ "$status" -eq 2 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ "$(jq -r '.[0].session_id' "$(dir UUID-A "$KP")/hb.roster.json")" = s1 ] || false
}

@test "a failed kitten @ ls keeps the last good tree" {
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
  hb hb_tick
  touch "$CC_HB_KITTEN_BIN.fail"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$status" -eq 0 ] || false
  [ "$(jq -r '.[0].id' "$(dir UUID-A "$KP")/hb.kitty-ls.json")" = 1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800300 ] || false
}

@test "prune drops heartbeat dirs older than 7 days and keeps younger ones" {
  mkdir -p "$(dir OLD 11)" "$(dir OLD 12)" "$(dir NEW 13)"
  echo $((1784800000 - 8 * 86400)) > "$(dir OLD 11)/hb.start"
  echo $((1784800000 - 6 * 86400)) > "$(dir OLD 12)/hb.start"
  echo 1784799000 > "$(dir NEW 13)/hb.start"
  hb hb_prune
  [ ! -e "$(dir OLD 11)" ] || false
  [ -d "$(dir OLD 12)" ] || false
  [ -d "$(dir NEW 13)" ] || false
}

@test "hb_pick: the newest in (lower, upper], with the upper bound inclusive and a same-tick sibling" {
  while read -r u k st; do
    mkdir -p "$(dir "$u" "$k")"; echo '[]' > "$(dir "$u" "$k")/hb.roster.json"; echo "$st" > "$(dir "$u" "$k")/hb.start"
  done <<EOF
A 101 1784790000
A 102 1784799000
B 103 1784799900
B 104 1784799950
C 105 1784800100
EOF
  hb hb_pick "$CC_HEARTBEAT_DIR" 1784780000 1784800000
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | cut -f2 | sed 's#.*/hb/##' | tr '\n' ' ')" = "B/103 B/104 " ] || false
  hb hb_pick "$CC_HEARTBEAT_DIR" 1784780000 1784799000
  [ "$output" = "1784799000	$(dir A 102)" ] || false
  hb hb_pick "$CC_HEARTBEAT_DIR" 1784800100 1784900000
  [ "$status" -eq 1 ] || false
}

@test "hb_pick --dead-kitty skips a kitty that is still alive (a crash restores the fleet that died)" {
  mkdir -p "$(dir A "$DEADP")" "$(dir A "$KP")"
  while read -r k st; do
    echo '[]' > "$(dir A "$k")/hb.roster.json"; echo "$st" > "$(dir A "$k")/hb.start"
  done <<EOF
$DEADP 1784799000
$KP 1784799900
EOF
  hb hb_pick "$CC_HEARTBEAT_DIR" 0 1784800000 --dead-kitty
  [ "$output" = "1784799000	$(dir A "$DEADP")" ] || false
}

@test "hb.session.tsv: account from the NEWEST transcript, model/effort/permission from its records" {
  cwd="$D/wt"; mkdir -p "$cwd"; git -C "$cwd" init -q -b feat-x
  slug="$(printf '%s' "$cwd" | tr '/.' '--')"
  mkdir -p "$HOME/.claude-next/projects/$slug" "$HOME/.claude-tertiary/projects/$slug"
  echo '{"type":"assistant","message":{"model":"old-model"},"effort":"low"}' > "$HOME/.claude-next/projects/$slug/s1.jsonl"
  touch -t 202001010000 "$HOME/.claude-next/projects/$slug/s1.jsonl"
  { echo '{"type":"permission-mode","permissionMode":"plan"}'
    echo '{"type":"assistant","message":{"model":"claude-opus-5-5"},"effort":"xhigh"}'
    echo '{"type":"assistant","message":{"model":"<synthetic>"}}'
    echo '{"type":"assistant","isSidechain":true,"message":{"model":"side-model"},"effort":"low"}'
  } > "$HOME/.claude-tertiary/projects/$slug/s1.jsonl"
  echo "[$(sess s1 "$KP" 4242 "$cwd" claude-next)]" > "$D/sessions.json"
  hb hb_tick
  [ "$(cat "$(dir UUID-A "$KP")/hb.session.tsv")" = "s1	claude-tertiary	claude-opus-5-5	xhigh	plan	feat-x	4242" ] || false
}

@test "hb.session.tsv: with no transcript, model/effort/permission come from the claude argv" {
  echo "[$(sess s2 "$KP" 4343)]" > "$D/sessions.json"
  echo ' 4343     1 /x/claude --permission-mode auto --model=claude-sonnet-5-5 --effort medium --resume s2' > "$D/ps.txt"
  hb hb_tick
  [ "$(cut -f3-5 "$(dir UUID-A "$KP")/hb.session.tsv")" = "claude-sonnet-5-5	medium	auto" ] || false
}

@test "hb.bg.tsv: non-MCP descendants, a live watcher, a listening port, an agent-browser session" {
  echo "[$(sess s1 "$KP" 500)]" > "$D/sessions.json"
  { echo '  500     1 claude --resume s1'
    echo '  501   500 /bin/zsh -c bash scripts/ship-land.sh'
    echo '  502   501 node server.js'
    echo '  503   500 node /x/ms365-mcp-server/index.js'
    echo "$KP   500 cc-await-ping --timeout 3300"
  } > "$D/ps.txt"
  printf 'p502\nf20\nn*:3000\n' > "$D/lsof.txt"
  printf 'pid=%s\n' "$KP" > "$CC_HB_MAILBOX_DIR/s1.watching"
  printf '%s\n' "$KP" > "$CC_HB_AGENT_BROWSER_DIR/shop.pid"
  printf '%s\n' "$DEADP" > "$CC_HB_AGENT_BROWSER_DIR/gone.pid"
  hb hb_tick
  bg="$(dir UUID-A "$KP")/hb.bg.tsv"
  grep -qx "s1	500	child	501	/bin/zsh -c bash scripts/ship-land.sh" "$bg" || false
  grep -qx "s1	500	child	502	node server.js" "$bg" || false
  grep -qx "s1	500	listen	502	\*:3000" "$bg" || false
  grep -qx "s1	500	watching	$KP	s1" "$bg" || false
  ! grep -q 'ms365-mcp' "$bg" || false
  grep -q "	agent-browser	$KP	shop\$" "$bg" || false
  ! grep -q 'gone' "$bg" || false
}

@test "hb.roles.tsv maps each role to its pane and, when live, its sid" {
  echo "[$(sess s1 "$KP" 1 /x claude-next 450)]" > "$D/sessions.json"
  echo 450 > "$CC_ROLES_DIR/docs-lead"; echo 999 > "$CC_ROLES_DIR/desk"
  hb hb_tick
  grep -qx "docs-lead	450	s1" "$(dir UUID-A "$KP")/hb.roles.tsv" || false
  grep -qx "desk	999	$(printf '\037')" "$(dir UUID-A "$KP")/hb.roles.tsv" || false
}

@test "under bats with the cc-sessions and kitten seams unset, a tick touches nothing real" {
  unset CC_HB_SESSIONS_BIN CC_HB_KITTEN_BIN
  hb hb_tick
  [ "$status" -eq 2 ] || false
  [ ! -e "$CC_HEARTBEAT_DIR" ] || false
}

# ── hb.displays.tsv (W3 P7): which display each kitty OS window is on ─────────────────────────────
# swift is a stub that logs its argv and prints $0.out; no case runs the real one.
displays_setup() {
  export CC_HB_SWIFT_BIN="$D/stub-swift"
  printf '#!/bin/sh\nshift\necho "$*" >> "$0.log"\n[ -f "$0.fail" ] && exit 1\ncat "$0.out" 2>/dev/null\n' > "$CC_HB_SWIFT_BIN"
  chmod +x "$CC_HB_SWIFT_BIN"
  printf '#!/bin/sh\necho "[{\\"id\\": 6, \\"platform_window_id\\": 700, \\"tabs\\": []}, {\\"id\\": 7, \\"platform_window_id\\": 701, \\"tabs\\": []}]"\n' > "$CC_HB_KITTEN_BIN"
  printf '700\tUUID-EXT\t-832\t-1440\t2560\t1440\t1\t-832\t-1440\t2560\t1440\n701\tUUID-BUILTIN\t0\t0\t1728\t1117\t0\t100\t80\t900\t700\n' > "$CC_HB_SWIFT_BIN.out"
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
}

@test "displays: a tick maps each platform_window_id of the tree to its display, atomically" {
  displays_setup
  hb hb_tick
  [ "$status" -eq 0 ] || false
  f="$(dir UUID-A "$KP")/hb.displays.tsv"
  [ "$(cat "$CC_HB_SWIFT_BIN.log")" = "700 701" ] || false          # one read, the tree's ids in its order
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 2 ] || false
  [ "$(awk -F'\t' '$1 == 701 { print $2, $7, $8, $9, $10, $11 }' "$f")" = "UUID-BUILTIN 0 100 80 900 700" ] || false
  [ -z "$(find "$CC_HEARTBEAT_DIR" -name '.*.tmp*')" ] || false
}

@test "displays: a failed, empty or malformed read keeps the last good file" {
  displays_setup
  hb hb_tick
  f="$(dir UUID-A "$KP")/hb.displays.tsv"; good="$(cat "$f")"
  touch "$CC_HB_SWIFT_BIN.fail"; hb hb_tick
  [ "$(cat "$f")" = "$good" ] || false
  rm "$CC_HB_SWIFT_BIN.fail"; : > "$CC_HB_SWIFT_BIN.out"; hb hb_tick
  [ "$(cat "$f")" = "$good" ] || false
  printf '700\tUUID-EXT\t0\t0\n' > "$CC_HB_SWIFT_BIN.out"; hb hb_tick       # 4 fields, not 11
  [ "$(cat "$f")" = "$good" ] || false
  [ -z "$(find "$CC_HEARTBEAT_DIR" -name '.*.tmp*')" ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false        # the tick itself still succeeds
}

@test "displays: a tree with no platform_window_id asks swift nothing; under bats an unset seam runs no real swift" {
  displays_setup
  printf '#!/bin/sh\necho "[{\\"id\\": 1, \\"tabs\\": []}]"\n' > "$CC_HB_KITTEN_BIN"
  hb hb_tick
  [ ! -f "$CC_HB_SWIFT_BIN.log" ] || false
  [ ! -f "$(dir UUID-A "$KP")/hb.displays.tsv" ] || false
  displays_setup; unset CC_HB_SWIFT_BIN
  hb hb_tick
  [ "$status" -eq 0 ] || false
  [ ! -f "$(dir UUID-A "$KP")/hb.displays.tsv" ] || false
}

@test "hb_display_probe: no argument lists the attached displays; no swift is rc 1" {
  displays_setup
  printf 'UUID-EXT\t-832\t-1440\t2560\t1440\n' > "$CC_HB_SWIFT_BIN.out"
  hb hb_display_probe
  [ "$status" -eq 0 ] || false
  [ "$output" = "$(printf 'UUID-EXT\t-832\t-1440\t2560\t1440')" ] || false
  [ "$(cat "$CC_HB_SWIFT_BIN.log")" = "" ] || false
  CC_HB_SWIFT_BIN="$D/absent" hb hb_display_probe
  [ "$status" -eq 1 ] || false
}
