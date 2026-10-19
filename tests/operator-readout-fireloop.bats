#!/usr/bin/env bats
# operator-readout.sh — the dispatcher fire-loop line (fire_loop_line).
#
# ONE counted `◆` line while the dispatcher keeps firing items that keep failing, read from the
# backlog ledger's spawn-fail self-releases and, for the remedy, the convicted item's newest header
# in the dispatcher fire log. What these cases pin:
#   - the REMEDY follows the rc, not the item count: a single item refused at the payload gate
#     (rc 3 or 4) is told to block that brief; any other rc, or more than one item, points at the log
#   - the count is floored to the ladder 5/10/20/50/100/200/500, so two renders one failure apart
#     are byte-identical and the readout's damping latch keeps holding while a loop runs
#   - a run is reset by any non-failure event, expires 24 h after its newest failure, and is closed
#     while a claim older than 30 min holds the item
#   - kill switch CC_OPREADOUT_FIRELOOP=off; a healthy ledger renders nothing at all
#
# Hermetic: CC_BACKLOG_FILE, CC_DISPATCH_FIRE_LOG, CC_OPREADOUT_NOW and HOME are pinned to planted
# files. The hook runs under /bin/bash (3.2), the interpreter a Stop hook gets on this box.

NOW=1791547200   # 2026-10-09T12:00:00Z
# what `--render` prints when nothing fires the block: the fire-loop line did not join the predicate
EMPTY="OPERATOR ▸ no manual steps pending."

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  READOUT="$REPO/hooks/operator-readout.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_RESUME_DEBT_BIN=none
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main" WRAP_CACHE=off
  export CC_OPREADOUT_COLOR=0 CC_WAKE_FLOOR=0
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-registry/programs.json"
  unset KITTY_WINDOW_ID WRAP_DOD_FILE WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  unset CC_OPREADOUT_FIRELOOP
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DISPATCH_FIRE_LOG="$BATS_TEST_TMPDIR/dispatch-fires.log"
  export CC_OPREADOUT_NOW="$NOW"
  : > "$CC_BACKLOG_FILE"; : > "$CC_DISPATCH_FIRE_LOG"
  W="$(mkrepo w)"
}

mkrepo() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git checkout -q -b main
    echo base > f.txt; git add -A; git commit -q -m base
    git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$(cd "$w" && pwd -P)"
}

iso() { date -u -r "$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }   # iso <seconds before NOW>

# Ledger rows. Each takes <id> <seconds before NOW>; rows land in call order (ledger order).
fail()  { printf '{"id":"%s","ts":"%s","event":"reopen","selfRelease":true,"releaseReason":"spawn-fail"}\n' "$1" "$(iso "$2")" >> "$CC_BACKLOG_FILE"; }
claim() { printf '{"id":"%s","ts":"%s","event":"claim","by":"h-1","role":"dispatcher"}\n' "$1" "$(iso "$2")" >> "$CC_BACKLOG_FILE"; }
ev()    { printf '{"id":"%s","ts":"%s","event":"%s"}\n' "$1" "$(iso "$2")" "$3" >> "$CC_BACKLOG_FILE"; }

# loop <id> <n> <seconds before NOW of the FIRST failure> — n claim+fail pairs, 60 s apart
loop() {
  local i=0 t="$3"
  while [ "$i" -lt "$2" ]; do
    claim "$1" "$t"; fail "$1" "$(( t - 30 ))"
    t=$(( t - 60 )); i=$(( i + 1 ))
  done
}

# hdr <id> <rc> [acct] — one fire-log header plus a body line, appended (newest last)
hdr() {
  printf '===== %s item=%s account=%s rc=%s pid=4242 =====\nfire output for %s\n' \
    "$(iso 60)" "$1" "${3:-next3}" "$2" "$1" >> "$CC_DISPATCH_FIRE_LOG"
}

render() { run /bin/bash "$READOUT" --render --cwd "$W"; }
nline()  { printf '%s\n' "$output" | grep -c 'dispatch fails'; }

@test "the hook parses under /bin/bash 3.2 and that is the interpreter these cases run" {
  run /bin/bash -n "$READOUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run /bin/bash -c 'printf %s "${BASH_VERSINFO[0]}"'
  [ "$output" = 3 ]
}

@test "one item refused at the payload gate (rc=4) renders the block remedy for that item" {
  loop aaaa11112222 6 21600                      # first failure just under 6 h ago, 06:00:30Z
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  # rows fit 52 cells (lr-wake Wave H): facts cut at a whole-fact boundary, the remedy on its own row
  printf '%s\n' "$output" | grep -qxF ' ◆ 5+ dispatch fails since 10-09 06:00Z…' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF '   cc-backlog block aaaa11112222 --needs "<why>"' || { echo "$output"; false; }
  # the loop alone fires the block: line 1 is the governing header, and nothing is a run line
  [[ "$(printf '%s\n' "$output" | head -1)" == "OPERATOR ▸ "* ]] || false
  [ "$(printf '%s\n' "$output" | grep -c '▶')" -eq 0 ]
}

@test "rc=3 is the payload gate too; the item's NEWEST header decides, not an older one or another item's" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 1; hdr aaaa11112222 3; hdr bbbb11112222 1
  render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF '   cc-backlog block aaaa11112222 --needs "<why>"' \
    || { echo "$output"; false; }
}

@test "a single item failing on any other rc gets the tail remedy, never the block" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 4; hdr aaaa11112222 1         # same item: the gate once, then the anchor probe
  render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF ' ◆ 5+ dispatch fails since 10-09 06:00Z…' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "   tail -40 $CC_DISPATCH_FIRE_LOG" \
    || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'cc-backlog block')" -eq 0 ]
}

@test "an rc the fire log cannot supply is unknown and gets the tail remedy" {
  loop aaaa11112222 6 21600
  hdr bbbb11112222 4                              # a payload refusal, but of a different item
  render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '   tail -40 ' || { echo "$output"; false; }   # the tail remedy, not the gate's
  [ "$(printf '%s\n' "$output" | grep -c 'cc-backlog block')" -eq 0 ]
  rm -f "$CC_DISPATCH_FIRE_LOG"                   # and with no log at all
  render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '   tail -40 ' || { echo "$output"; false; }   # the tail remedy, not the gate's
}

@test "several items render the tail remedy even when the longest run is a payload refusal" {
  # three runs of 3: no run reaches 5, so this also pins the >= 3 big runs arm of the predicate
  loop aaaa11112222 3 21600; loop bbbb11112222 3 18000; loop cccc11112222 3 14400
  hdr aaaa11112222 4; hdr bbbb11112222 4; hdr cccc11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  printf '%s\n' "$output" | grep -qxF ' ◆ 5+ dispatch fails since 10-09 06:00Z · 3 items' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF "   tail -40 $CC_DISPATCH_FIRE_LOG" \
    || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'cc-backlog block')" -eq 0 ]
  # control on the same arm: two runs of 3 are below both thresholds and render nothing
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600; loop bbbb11112222 3 18000
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
}

@test "two items, one of them looping on the payload gate, still get the tail remedy" {
  loop aaaa11112222 7 21600; loop bbbb11112222 3 18000
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF ' ◆ 10+ dispatch fails since 10-09 06:00Z · 2 items' \
    || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'cc-backlog block')" -eq 0 ]
}

@test "two renders one failure apart are byte-identical; the output moves only at a ladder step" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 4
  render; [ "$status" -eq 0 ]; a="$output"
  [ "$(nline)" -eq 1 ]
  claim aaaa11112222 300; fail aaaa11112222 270  # the 7th failure
  render; [ "$status" -eq 0 ]; b="$output"
  [ "$a" = "$b" ] || { printf 'A:\n%s\nB:\n%s\n' "$a" "$b"; false; }
  # control: the comparison can fail — three more failures cross 10 and the line changes
  loop aaaa11112222 3 240
  render; [ "$status" -eq 0 ]
  [ "$a" != "$output" ] || false
  printf '%s\n' "$output" | grep -qF ' ◆ 10+ dispatch fails since 10-09 06:00Z' \
    || { echo "$output"; false; }
}

@test "a run reset by a non-failure event is silent; claim, venue, link and falsify do not reset it" {
  # control: the neutral events sit inside the run and it still counts 6
  loop aaaa11112222 3 21600
  ev aaaa11112222 20000 venue; ev aaaa11112222 19990 link; ev aaaa11112222 19980 falsify
  loop aaaa11112222 3 7200
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  # the same rows with one `done` after them: the run is over
  ev aaaa11112222 600 "done"
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
  [ "$output" = "$EMPTY" ] || { echo "$output"; false; }
  # and a reset in the MIDDLE leaves only the failures after it (3 + block + 4 is a run of 4)
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600; ev aaaa11112222 20000 block; ev aaaa11112222 19000 unblock
  loop aaaa11112222 4 7200
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
}

@test "only a spawn-fail SELF-release is a failed fire: each of the three conditions resets the run alone" {
  # control: the two halves with nothing between them are one run of 6
  loop aaaa11112222 3 21600; loop aaaa11112222 3 7200
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  # an operator reopen (no selfRelease, no reason) is a reset, not a failure
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600; ev aaaa11112222 20000 reopen; loop aaaa11112222 3 7200
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ] || { echo "plain reopen: $output"; false; }
  # a self-release for another reason (the worktree could not be made) is a reset too
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600
  printf '{"id":"aaaa11112222","ts":"%s","event":"reopen","selfRelease":true,"releaseReason":"worktree-fail"}\n' "$(iso 20000)" >> "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 7200
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ] || { echo "worktree-fail: $output"; false; }
  # and so is a reopen that carries the reason without being a self-release
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600
  printf '{"id":"aaaa11112222","ts":"%s","event":"reopen","releaseReason":"spawn-fail"}\n' "$(iso 20000)" >> "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 7200
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ] || { echo "no selfRelease: $output"; false; }
}

@test "the thresholds at their edges: a run of exactly 5 fires; 4+3 and 3+3+2 are silent" {
  loop aaaa11112222 5 21600
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF ' ◆ 5+ dispatch fails since 10-09 06:00Z…' \
    || { echo "$output"; false; }
  # longest run 4, and only two runs of >= 3
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 4 21600; loop bbbb11112222 3 18000
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ] || { echo "4+3: $output"; false; }
  # a run of 2 is not a big run, so it does not make a third beside two runs of 3
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 3 21600; loop bbbb11112222 3 18000; loop cccc11112222 2 14400
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ] || { echo "3+3+2: $output"; false; }
}

@test "an id outside the ledger alphabet is never used as a pattern: it cannot borrow another item's rc" {
  loop aaaa.1112222 6 21600
  hdr aaaaX1112222 4                              # the dot would match this X as a regex
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  printf '%s\n' "$output" | grep -qF '   tail -40 ' || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'cc-backlog block')" -eq 0 ]
}

@test "a loop that has run for days stays visible: staleness is measured from the NEWEST failure" {
  # the incident shape (2026-10-05..09): first failure 3 days ago, newest 10 min ago
  fail aaaa11112222 259200; fail aaaa11112222 172800; fail aaaa11112222 86040
  fail aaaa11112222 7200;   fail aaaa11112222 3600;   fail aaaa11112222 600
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF ' ◆ 5+ dispatch fails since 10-06 12:00Z…' \
    || { echo "$output"; false; }
}

@test "a run whose newest failure is older than 24 h is silent" {
  loop aaaa11112222 6 86100                      # newest failure 23 h 50 m ago: still open
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 6 90000                      # newest failure 24 h 54 m ago
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
  [ "$output" = "$EMPTY" ] || { echo "$output"; false; }
}

@test "a claim older than 30 min closes the run (a session holds the item); a fresh claim does not" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 4
  claim aaaa11112222 600                         # claimed 10 min ago, no release yet
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  : > "$CC_BACKLOG_FILE"
  loop aaaa11112222 6 21600
  claim aaaa11112222 2400                        # claimed 40 min ago and still held
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
}

@test "CC_OPREADOUT_FIRELOOP=off renders nothing for a loop that otherwise fires" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  export CC_OPREADOUT_FIRELOOP=off
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
  [ "$output" = "$EMPTY" ] || { echo "$output"; false; }
}

@test "a healthy backlog is silent: ordinary traffic and a few isolated spawn-fails render nothing" {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    ev "dddd0000000$i" $(( 30000 - i * 100 )) add
    claim "dddd0000000$i" $(( 29000 - i * 100 ))
    ev "dddd0000000$i" $(( 28000 - i * 100 )) "done"
  done
  # six failures in all, but no run reaches 5 and only two reach 3
  loop aaaa11112222 3 21600; loop bbbb11112222 3 18000
  hdr aaaa11112222 4
  # a torn row and a non-object row are dropped, not fatal
  printf '{"id":"aaaa11112222","ts":"2026-10-0\n[1,2]\n' >> "$CC_BACKLOG_FILE"
  render
  [ "$status" -eq 0 ]
  [ "$output" = "$EMPTY" ] || { echo "$output"; false; }
  # an absent ledger is silent too
  rm -f "$CC_BACKLOG_FILE"
  render
  [ "$status" -eq 0 ]
  [ "$output" = "$EMPTY" ] || { echo "$output"; false; }
}

@test "the ledger read is a bounded tail: a loop more than 5000 rows back is not scanned for" {
  loop aaaa11112222 6 21600
  hdr aaaa11112222 4
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 1 ]
  local ts; ts="$(iso 3600)"
  awk -v ts="$ts" 'BEGIN { for (i = 0; i < 5000; i++) printf "{\"id\":\"f%05d\",\"ts\":\"%s\",\"event\":\"add\"}\n", i, ts }' >> "$CC_BACKLOG_FILE"
  render
  [ "$status" -eq 0 ]
  [ "$(nline)" -eq 0 ]
}
