#!/usr/bin/env bats
# scripts/lib/restore-heartbeat.sh — the 300 s record of the live fleet that a hard power-off restore
# reads (W3 P3a-i). Every case drives the library under /bin/bash 3.2, because launchd runs it there
# (lesson: the deployment interpreter is not the one on your PATH). HOME is a fixture, and
# cc-sessions, kitten, ps and lsof are stubs: nothing here reads the live registry or the live kitty.
# RED-proof (pid reuse, 2026-10-15), run against origin/main's library: all four pid-reuse cases fail —
# "not provably the dead kitty" at its not-kitty scenario (the dead roster is rewritten), "genuinely
# live" on the missing hb.kitty-start, "re-proves" with the roster emptied, hb_pick --dead-kitty
# dropping the reused pid's fleet.
# RED-proof (2026-10-19, panic recovery), run against origin/main dfdb5c273's library: both backfill
# cases fail (the roster holds only the registry row, windows 27 and 28 absent), the carried-census
# case fails at its first hb.census read (no such file: a failed census wrote nothing), and the bound
# case fails (no _hb_census_bound).

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
  # `ps -p <pid>` (the identity check) answers from ident.<pid>, or ident.<pid>.once exactly once;
  # with neither it fails, as ps does for a pid it cannot see. Anything else is the fleet listing.
  printf '#!/bin/sh\nif [ "$1" = -p ]; then\n  f="%s/ident.$2"\n  [ -f "$f.once" ] && { cat "$f.once"; rm -f "$f.once"; exit 0; }\n  [ -f "$f" ] && { cat "$f"; exit 0; }\n  exit 1\nfi\ncat "%s/ps.txt"\n' "$D" "$D" > "$CC_HB_PS_BIN"
  printf '#!/bin/sh\ncat "%s/lsof.txt"\n' "$D" > "$CC_HB_LSOF_BIN"
  chmod +x "$CC_HB_SESSIONS_BIN" "$CC_HB_KITTEN_BIN" "$CC_HB_PS_BIN" "$CC_HB_LSOF_BIN"
  : > "$D/ps.txt"; : > "$D/lsof.txt"
  KP=$$                                   # a LIVE kitty pid: this test's own process
  sleep 0 & DEADP=$!; wait "$DEADP"       # a pid that is certainly not alive any more
  echo '[]' > "$D/sessions.json"
  KSTART=1784700000                       # when the live kittys started: before every tick here
  ident "$KP" "$KSTART"; ident "$PPID" "$KSTART"
}

ident() { # <pid> <start-epoch> [executable] — what `ps -p <pid> -o lstart=,comm=` reports
  printf '%s     %s\n' "$(date -r "$2" '+%a %b %e %T %Y')" "${3:-/Applications/kitty.app/Contents/MacOS/kitty}" > "$D/ident.$1"
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

# The 2026-10-15 loss: a crashed kitty's directory stays in this boot's dir, the loop re-adds its pid
# every tick, and a process that drew that pid passed kill -0, so its roster became [].
dead_fleet() { # <pid> — a dead kitty's full last heartbeat (start 1784799000), no registry row naming it
  local d; d="$(dir UUID-A "$1")"; mkdir -p "$d"
  echo "[$(sess lost1 "$1"),$(sess lost2 "$1")]" > "$d/hb.roster.json"
  printf 's1\tclaude-next\tm\te\tauto\tmain\t1\n' > "$d/hb.session.tsv"
  echo '[{"id": 7, "tabs": []}]' > "$d/hb.kitty-ls.json"; echo 'bg' > "$d/hb.bg.tsv"; echo 'roles' > "$d/hb.roles.tsv"
  echo 1784799000 > "$d/hb.start"
}
snap() { (cd "$(dir UUID-A "$1")" && ls -A && shasum ./*); }

@test "a live pid that is not provably the dead kitty leaves its heartbeat byte-identical" {
  while read -r why; do
    rm -rf "$CC_HEARTBEAT_DIR"; dead_fleet "$KP"
    case "$why" in
      not-kitty)     ident "$KP" "$KSTART" /bin/zsh ;;
      started-later) ident "$KP" 1784799500 ;;                       # after the dead kitty's last tick
      ps-silent)     rm -f "$D/ident.$KP" ;;
      start-differs) ident "$KP" "$KSTART"; echo 1784600000 > "$(dir UUID-A "$KP")/hb.kitty-start" ;;
    esac
    before="$(snap "$KP")"
    hb hb_tick
    [ "$(snap "$KP")" = "$before" ] || { echo "rewritten: $why"; false; }
    [ "$status" -eq 1 ] || { echo "rc $status: $why"; false; }
  done <<WHY
not-kitty
started-later
ps-silent
start-differs
WHY
}

@test "a genuinely live kitty still updates, records its start, and stops when another kitty takes its pid" {
  dead_fleet "$KP"                                       # a legacy dir: hb.start only, kitty older
  hb hb_tick
  [ "$status" -eq 0 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ "$(jq -c . "$(dir UUID-A "$KP")/hb.roster.json")" = '[]' ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.kitty-start")" = "$KSTART" ] || false
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$(jq -r '.[0].session_id' "$(dir UUID-A "$KP")/hb.roster.json")" = s1 ] || false
  ident "$KP" 1784800400                                 # that kitty died; a new kitty drew its pid
  echo '[]' > "$D/sessions.json"
  CC_HB_NOW=1784800600 hb hb_tick
  [ "$status" -eq 1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800300 ] || false
  [ "$(jq -r '.[0].session_id' "$(dir UUID-A "$KP")/hb.roster.json")" = s1 ] || false
}

@test "emptying a non-empty roster re-proves the kitty at the write: a pid reused mid-tick keeps the roster" {
  dead_fleet "$KP"
  echo "$KSTART" > "$(dir UUID-A "$KP")/hb.kitty-start"
  mv "$D/ident.$KP" "$D/ident.$KP.once"                  # ps proves the kitty once, then not again
  hb hb_tick
  [ "$(jq -r '.[0].session_id' "$(dir UUID-A "$KP")/hb.roster.json")" = lost1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784799000 ] || false
}

# Changed on purpose 2026-10-19: this case used to pin "writes nothing", and under load that froze the
# record for 2 h (every 30 s census overran at load 40/core), so a crash would restore a stale fleet.
@test "a census that fails, does not parse or overruns its bound carries the last roster (live pids only), rc 2" {
  echo "[$(sess s1 "$KP" 1),$(sess s2 "$KP" "$DEADP")]" > "$D/sessions.json"
  hb hb_tick
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "ok 1784800000" ] || false
  printf '    1     0 /sbin/launchd\n' > "$D/ps.txt"                      # s1's pid is alive, s2's is not
  r="$(dir UUID-A "$KP")/hb.roster.json"
  touch "$CC_HB_SESSIONS_BIN.fail"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$status" -eq 2 ] || false
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = s1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800300 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "carried 1784800300 1784800000" ] || false
  [[ "$output" == *"failed or did not parse within"*"carried each kitty's last roster"* ]] || false
  rm "$CC_HB_SESSIONS_BIN.fail"; echo 'not json' > "$D/sessions.json"
  CC_HB_NOW=1784800600 hb hb_tick
  [ "$status" -eq 2 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "carried 1784800600 1784800000" ] || false
  # A census slower than its bound is carried the same way, not waited out.
  printf '#!/bin/sh\nsleep 8\ncat "%s/sessions.json"\n' "$D" > "$CC_HB_SESSIONS_BIN"
  echo "[$(sess s3 "$KP" 1)]" > "$D/sessions.json"
  CC_HB_SESSIONS_TIMEOUT=1 CC_HB_NOW=1784800900 hb hb_tick
  [ "$status" -eq 2 ] || false
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = s1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "carried 1784800900 1784800000" ] || false
  # ps not answering drops no carried row; the next census that works is "ok" again.
  : > "$D/ps.txt"; printf '#!/bin/sh\ncat "%s/sessions.json"\n' "$D" > "$CC_HB_SESSIONS_BIN"
  CC_HB_NOW=1784801200 hb hb_tick
  [ "$status" -eq 0 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "ok 1784801200" ] || false
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = s3 ] || false
}

@test "an ok census that names none of a kitty's sessions keeps the rows whose pid still runs (2026-10-25)" {
  # From 08:41 on 2026-10-25 every ok census left kitty 1881 at [] while 13 of its session pids ran;
  # the reboot then restored nobody. RED-proof: against origin/main's restore-heartbeat.sh the second
  # tick writes [].
  echo "[$(sess s1 "$KP" 1),$(sess s2 "$KP" "$DEADP")]" > "$D/sessions.json"
  hb hb_tick
  r="$(dir UUID-A "$KP")/hb.roster.json"
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = "s1 s2" ] || false
  printf '    1     0 /sbin/launchd\n' > "$D/ps.txt"                      # s1's pid is alive, s2's is not
  echo '[]' > "$D/sessions.json"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = s1 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.census")" = "ok 1784800300" ] || false
  [[ "$output" == *"named no session of kitty $KP, but 1 of its last roster still run"* ]] || false
  # once that pid is gone too, the roster empties as before
  printf '    2     0 /sbin/other\n' > "$D/ps.txt"
  CC_HB_NOW=1784800600 hb hb_tick
  [ "$(jq -r 'length' "$r")" = 0 ] || false
}

@test "the census bound is 30 s on an idle box, at most 75 s under any load, and CC_HB_SESSIONS_TIMEOUT overrides it" {
  CC_HB_LOAD1=0.5 hb _hb_census_bound
  [ "$output" = 30 ] || false
  CC_HB_LOAD1=100000 hb _hb_census_bound
  [ "$output" = 75 ] || false
  CC_HB_LOAD1=100000 CC_HB_SESSIONS_TIMEOUT=7 hb _hb_census_bound
  [ "$output" = 7 ] || false
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

@test "hb_pick --dead-kitty skips a kitty that is still alive, never a reused pid (a crash restores the fleet that died)" {
  ident "$PPID" "$KSTART" /bin/zsh                       # alive, but a reused pid: counts as dead
  mkdir -p "$(dir A "$PPID")"; echo '[]' > "$(dir A "$PPID")/hb.roster.json"; echo 1784799000 > "$(dir A "$PPID")/hb.start"
  mkdir -p "$(dir A "$DEADP")" "$(dir A "$KP")"
  while read -r k st; do
    echo '[]' > "$(dir A "$k")/hb.roster.json"; echo "$st" > "$(dir A "$k")/hb.start"
  done <<EOF
$DEADP 1784799000
$KP 1784799900
EOF
  hb hb_pick "$CC_HEARTBEAT_DIR" 0 1784800000 --dead-kitty
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ] || false
  printf '%s\n' "$output" | grep -qxF "1784799000	$(dir A "$DEADP")" || false
  printf '%s\n' "$output" | grep -qxF "1784799000	$(dir A "$PPID")" || false
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

# ── roster backfill from the kitty tree (2026-10-18 panic) ──────────────────────────────────────────
# Three live kitty panes had no registry row by the last tick, so they were absent from the roster and
# boot-resume never considered them. Window 27 runs claude under reso-resume-one's expect (not the
# foreground process group); window 28 runs it directly. Claude Code's own sessions/<pid>.json names
# each session, and its procStart must equal the pid's start time now.
backfill_setup() { # registry holds only s-reg in window 5; windows 27 and 28 have no row
  echo "[$(sess s-reg "$KP" 400 /w/reg claude-next 5)]" > "$D/sessions.json"
  echo '[{"id": 1, "tabs": [{"windows": [{"id": 5, "pid": 300, "cwd": "/w/reg"},
         {"id": 27, "pid": 500, "cwd": "/w/tpg"}, {"id": 28, "pid": 600, "cwd": "/w/voiceink"}]}]}]' > "$D/tree.json"
  printf '#!/bin/sh\n[ -f "%s/tree.json" ] && exec cat "%s/tree.json"\necho "[]"\n' "$D" "$D" > "$CC_HB_KITTEN_BIN"
  cat > "$D/ps.txt" <<PS
  300     1 -zsh
  400   300 /x/node_modules/.bin/claude --model m
  500     1 -zsh
  510   500 bash /h/.reso/bin/reso-resume-one next2 /w/tpg sid-tpg
  520   510 expect -c script
  530   520 /x/node_modules/.bin/claude --resume sid-tpg --effort high
  600     1 -zsh
  610   600 bash /h/.claude/bin/cc-close-attrib /x/node_modules/.bin/claude --permission-mode auto
  620   610 /x/node_modules/.bin/claude --permission-mode auto VoiceInk lead
  630   620 /x/node_modules/.bin/claude -p probe
PS
  mkdir -p "$HOME/.claude-secondary/sessions" "$HOME/.claude-quaternary/sessions"
  printf '{"pid":530,"sessionId":"sid-tpg","cwd":"/w/tpg","startedAt":1784600000123,"procStart":"Mon Oct 19 00:45:55 2026"}' \
    > "$HOME/.claude-secondary/sessions/530.json"
  printf '{"pid":620,"sessionId":"sid-vi","cwd":"/w/voiceink","startedAt":1784600500000,"procStart":"Mon Oct 19 01:00:00 2026"}' \
    > "$HOME/.claude-quaternary/sessions/620.json"
  echo 'Mon Oct 19 00:45:55 2026' > "$D/ident.530"; echo 'Mon Oct 19 01:00:00 2026' > "$D/ident.620"
}

@test "backfill: live panes with no registry row join the roster and hb.session.tsv, named by sessions/<pid>.json" {
  backfill_setup
  hb hb_tick
  [ "$status" -eq 0 ] || false
  r="$(dir UUID-A "$KP")/hb.roster.json"
  [ "$(jq -c '[.[] | [.paneUUID, .session_id, .account, .pid]] | sort' "$r")" \
    = '[["27","sid-tpg","claude-secondary",530],["28","sid-vi","claude-quaternary",620],["5","s-reg","claude-next",400]]' ] || false
  [ "$(jq -r '.[] | select(.paneUUID == "27") | [.name, .cwd, .startedAt, .kitty_pid == '"$KP"', .source] | @tsv' "$r")" \
    = "$(printf 'tpg-27\t/w/tpg\t1784600000123\ttrue\tkitty-tree')" ] || false
  [ "$(cut -f1 "$(dir UUID-A "$KP")/hb.session.tsv" | sort | tr '\n' ' ')" = "s-reg sid-tpg sid-vi " ] || false
  [[ "$output" == *"2 live pane(s) with no registry row added to the roster: 27 28"* ]] || false
}

@test "backfill: a stale sessions file, a pane already rostered, or no tree this tick adds nothing; --resume is the fallback" {
  backfill_setup
  echo 'Mon Oct 19 09:09:09 2026' > "$D/ident.620"          # pid 620 reused since the file was written
  hb hb_tick
  r="$(dir UUID-A "$KP")/hb.roster.json"
  [ "$(jq -r '[.[].paneUUID] | sort | join(" ")' "$r")" = "27 5" ] || false
  # The same file with its pid's start time restored is accepted, so the refusal above was procStart.
  echo 'Mon Oct 19 01:00:00 2026' > "$D/ident.620"; hb hb_tick
  [ "$(jq -r '[.[].paneUUID] | sort | join(" ")' "$r")" = "27 28 5" ] || false
  # No sessions file: the argv's --resume names the session (window 27); window 28's argv has none.
  rm -f "$HOME"/.claude-*/sessions/*.json
  mkdir -p "$HOME/.claude-secondary/projects/-w-tpg"; : > "$HOME/.claude-secondary/projects/-w-tpg/sid-tpg.jsonl"
  hb hb_tick
  [ "$(jq -c '[.[] | select(.source == "kitty-tree") | [.paneUUID, .session_id, .account]]' "$r")" \
    = '[["27","sid-tpg","claude-secondary"]]' ] || false
  # A pane the registry already names is never duplicated, and a failed tree read adds nothing.
  echo "[$(sess s-reg "$KP" 400 /w/reg claude-next 5),$(sess s-27 "$KP" 999 /w/tpg claude-next 27)]" > "$D/sessions.json"
  hb hb_tick
  [ "$(jq -r '[.[].paneUUID] | sort | join(" ")' "$r")" = "27 5" ] || false
  [ "$(jq -r '.[] | select(.paneUUID == "27") | .session_id' "$r")" = s-27 ] || false
  echo "[$(sess s-reg "$KP" 400 /w/reg claude-next 5)]" > "$D/sessions.json"; touch "$CC_HB_KITTEN_BIN.fail"
  printf '#!/bin/sh\nexit 1\n' > "$CC_HB_KITTEN_BIN"
  hb hb_tick
  [ "$(jq -r '[.[].paneUUID] | join(" ")' "$r")" = "5" ] || false
}

# ── reboot-resume 2026-10-21, wave T4 (docs/research/reboot-resume-2026-10-21/REPORT.md R9 R19 R23) ──
# RED-proof, run against origin/main cc1d441f6's library: the ps-kitty case fails at its first
# assertion (no directory for a kitty the registry does not name), census.log does not exist, the
# no-session-id row stays in the roster, _hb_display_bound and hb_tree_refresh are undefined.

@test "R9: a live kitty that only ps knows gets its heartbeat; a kitty child, a +subcommand and a non-kitty do not" {
  cat > "$D/ps.txt" <<PS
  $KP     1 /Applications/kitty.app/Contents/MacOS/kitty
  $PPID   $KP /Applications/kitty.app/Contents/MacOS/kitty
  777     1 /Applications/kitty.app/Contents/MacOS/kitty +kitten panel
  778     1 /Applications/kitty.app/Contents/MacOS/kitty
PS
  ident 777 "$KSTART"; ident 778 "$KSTART" /bin/zsh
  hb hb_tick
  [ "$status" -eq 0 ] || false
  [ "$(jq -c . "$(dir UUID-A "$KP")/hb.roster.json")" = '[]' ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.kitty-start")" = "$KSTART" ] || false
  for p in "$PPID" 777 778; do [ ! -e "$(dir UUID-A "$p")" ] || { echo "dir for $p"; false; }; done
  hb _hb_ps_kittys "$D/ps.txt"
  [ "$output" = "$KP" ] || false
}

@test "R9 R19: each tick appends ok|carried, the census and tick durations and the kitty count to census.log" {
  echo "[$(sess s1 "$KP")]" > "$D/sessions.json"
  hb hb_tick
  touch "$CC_HB_SESSIONS_BIN.fail"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$status" -eq 2 ] || false
  [ "$(wc -l < "$CC_HEARTBEAT_DIR/census.log" | tr -d ' ')" = 2 ] || false
  head -1 "$CC_HEARTBEAT_DIR/census.log" | grep -Eq $'^1784800000\tok\tcensus_s=[0-9]+\ttick_s=[0-9]+\tkittys=1$' || false
  tail -1 "$CC_HEARTBEAT_DIR/census.log" | grep -Eq $'^1784800300\tcarried\tcensus_s=[0-9]+\ttick_s=[0-9]+\tkittys=1$' || false
  # Prune leaves the log alone (it is a file beside the boot dirs, not one of them).
  [ -d "$CC_HEARTBEAT_DIR/UUID-A" ] || false
}

@test "R19: a registry row with no session id never enters the roster, from a census or from a carried roster" {
  echo "[$(sess s1 "$KP"),{\"session_id\":null,\"kitty_pid\":$KP,\"pid\":1,\"paneUUID\":\"P9\"},{\"session_id\":\"\",\"kitty_pid\":$KP,\"pid\":1,\"paneUUID\":\"P8\"}]" > "$D/sessions.json"
  hb hb_tick
  r="$(dir UUID-A "$KP")/hb.roster.json"
  [ "$(jq -r '[.[].session_id] | join(" ")' "$r")" = s1 ] || false
  echo "[$(sess s1 "$KP" 1),{\"kitty_pid\":$KP,\"pid\":1,\"paneUUID\":\"P7\"}]" > "$r"
  printf '    1     0 /sbin/launchd\n' > "$D/ps.txt"
  touch "$CC_HB_SESSIONS_BIN.fail"
  CC_HB_NOW=1784800300 hb hb_tick
  [ "$(jq -r '[.[].paneUUID] | join(" ")' "$r")" = Ps1 ] || false
}

@test "R23: the display read is bounded at 20 s idle, scaled by load up to 60 s, and CC_HB_SWIFT_TIMEOUT overrides it" {
  CC_HB_LOAD1=0.5 hb _hb_display_bound
  [ "$output" = 20 ] || false
  CC_HB_LOAD1=100000 hb _hb_display_bound
  [ "$output" = 60 ] || false
  n="$(/usr/sbin/sysctl -n hw.ncpu)"
  CC_HB_LOAD1="$((n * 8))" hb _hb_display_bound
  [ "$output" = 40 ] || false
  CC_HB_LOAD1=100000 CC_HB_SWIFT_TIMEOUT=7 hb _hb_display_bound
  [ "$output" = 7 ] || false
}

@test "R23: hb_tree_refresh re-reads one kitty's tree and backfills its roster between ticks, leaving hb.start alone" {
  backfill_setup
  mv "$D/tree.json" "$D/tree.later"
  hb hb_tick
  r="$(dir UUID-A "$KP")/hb.roster.json"
  [ "$(jq -r '[.[].paneUUID] | join(" ")' "$r")" = 5 ] || false
  mv "$D/tree.later" "$D/tree.json"
  hb hb_tree_refresh "$KP"
  [ "$status" -eq 0 ] || false
  [ "$(jq -r '[.[].tabs[].windows[].id] | join(" ")' "$(dir UUID-A "$KP")/hb.kitty-ls.json")" = "5 27 28" ] || false
  [ "$(jq -r '[.[].paneUUID] | sort | join(" ")' "$r")" = "27 28 5" ] || false
  [ "$(cat "$(dir UUID-A "$KP")/hb.start")" = 1784800000 ] || false
  [ -z "$(find "$CC_HEARTBEAT_DIR" -name '.hb.*')" ] || false
  # A failed ls keeps the last good tree (rc 2); a kitty with no directory this boot is rc 1.
  printf '#!/bin/sh\nexit 1\n' > "$CC_HB_KITTEN_BIN"
  hb hb_tree_refresh "$KP"
  [ "$status" -eq 2 ] || false
  [ "$(jq -r '[.[].tabs[].windows[].id] | join(" ")' "$(dir UUID-A "$KP")/hb.kitty-ls.json")" = "5 27 28" ] || false
  hb hb_tree_refresh "$PPID"
  [ "$status" -eq 1 ] || false
}
