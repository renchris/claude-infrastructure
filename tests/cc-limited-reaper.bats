#!/usr/bin/env bats
# bin/cc-limited — the reaper, faults persistence + ack, the resolver, --kitty (LIMIT_DETECT_100P W2c).
#
# WHAT THESE SIX ROWS DEFEND. The census (tests/cc-limited.bats) answers "who is blocked". This
# file answers the question one layer down: a recovery was PROMISED and produced nothing. That
# state has no sensor anywhere else on the box — a claimed session that never came back is
# byte-identical, in every store, to a claimed session that came back and worked.
#
# THE ONE THING EASY TO GET BACKWARDS, and R1c is its control: the reaper must NOT be derived from
# the census. Marker files are GC'd on mtime, so a fault derived from census rows goes silent
# exactly when it gets old enough to matter. The reaper reads the CLAIM stores (locks/, faults/)
# and derives liveness; a `--persist`ed fault then outlives the lock as well.
#
# HERMETIC: the same frozen-afternoon fixture as the census suite, every store a seam into
# BATS_TEST_TMPDIR, the clock pinned by LR_NOW. Nothing here reads the mood of the machine.
# CC_LIMITED_BIN exists so the RED proof can run these rows against a pristine HEAD copy of the
# subject; it defaults to the worktree's own binary and is never set by the green run.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="${CC_LIMITED_BIN:-$REPO/bin/cc-limited}"
  W="$BATS_TEST_TMPDIR/fix"
  bash "$REPO/tests/fixtures/lr-2026-09-19/build.sh" "$W" >/dev/null
  export HOME="$W/home"
  set -a; . "$W/env.sh"; set +a
  F="$LR_STATE_DIR/faults"; L="$LR_STATE_DIR/locks"
  SID_4B=4bc1159f-0000-4000-8000-000000000000
}

cc()    { python3 "$SUBJ" "$@"; }
# ONE assertion idiom. `grep -q X && false` fails whether or not X matched, and a mid-test
# `! grep -q X` is exempt from errexit and can never fail — both are dead assertions. Count.
cnt()   { printf '%s\n' "$output" | grep -c -- "$1" || true; }
mtime() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }
slug()  { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
title() { # $1 = transcript path — the LAST ai-title in the tail is the one that renders
  printf '{"type":"system","subtype":"ai-title","aiTitle":"%s"}\n' "$2" >> "$1"
}

# ── R1 ───────────────────────────────────────────────────────────────────────────────────────────

@test "R1 4bc1159f: a stale claim with no live process is ONE reaper line, with claimant/ts/age/path" {
  run cc --reaper
  [ "$status" -eq 0 ]
  [ "$(cnt '^CLAIMED-NOT-LIVE  4bc1159f')" -eq 1 ]
  [ "$(cnt 'claimed by .claude-secondary')" -ge 1 ]
  [ "$(cnt 'pid 44616')" -ge 1 ]
  [ "$(cnt '2026-09-19T20:59:34Z')" -ge 1 ]
  [ "$(cnt 'age 14m26s')" -ge 1 ]           # pinned clock, same on every box
  [ "$(cnt "$L/$SID_4B.lock")" -ge 1 ]
}

@test "R1 --persist writes the fault ONCE: a second tick leaves first_seen and mtime untouched" {
  # O_EXCL is the mechanism. A poller re-writing first_seen every minute resets the age of every
  # fault it renders, and nothing on the box ever looks overdue again.
  run cc --reaper --persist
  [ "$status" -eq 0 ]
  [ -f "$F/$SID_4B.json" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["claim"]["pid"])' "$F/$SID_4B.json")" = 44616 ]
  before="$(mtime "$F/$SID_4B.json")"
  seen="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["first_seen"])' "$F/$SID_4B.json")"
  run cc --reaper --persist
  [ "$status" -eq 0 ]
  [ "$(mtime "$F/$SID_4B.json")" = "$before" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["first_seen"])' "$F/$SID_4B.json")" = "$seen" ]
}

@test "R1b ack --why renames the fault and is the ONLY exit — the lock stops being reaped too" {
  cc --reaper --persist >/dev/null
  run cc ack 4bc1159f --why "superseded by a manual resume"
  [ "$status" -eq 0 ]
  [ ! -f "$F/$SID_4B.json" ]
  [ -f "$F/$SID_4B.acked.json" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["why"])' "$F/$SID_4B.acked.json")" = "superseded by a manual resume" ]
  run cc --reaper
  [ "$(cnt 4bc1159f)" -eq 0 ]               # acked: gone, lock and all
  printf '%s\n' "$output" | grep -q 98f02458 || false               # …and its sibling is untouched
  run cc ack 4bc1159f --why x
  [ "$status" -eq 4 ]                                               # no un-acked fault left
}

@test "R1c the marker aged past its TTL and the fault STILL renders" {
  # THE CONTROL FOR THE WHOLE DESIGN. stop-failure-marker GCs on FILE mtime, so a quiet account's
  # death record expires while its failed recovery is still outstanding. A FAULT derived from
  # census rows vanishes here — which is exactly when a Fable/monthly row, never parked, needs it.
  cc --reaper --persist >/dev/null
  run cc                                                            # pre-condition: the census sees it
  [ "$(cnt 'FAULT CLAIMED-NOT-LIVE.*4bc1159f')" -ge 1 ]
  rm -f "$CC_LIMITED_MARKER_DIR"/*.jsonl
  run cc
  [ "$status" -eq 0 ]
  [ "$(cnt 4bc1159f)" -eq 0 ]                # the census has nothing left…
  run cc --reaper
  [ "$status" -eq 0 ]
  [ "$(cnt "^CLAIMED-NOT-LIVE  4bc1159f")" -ge 1 ]   # …the reaper still does
  rm -rf "$L"                                                        # and once the lock goes too,
  run cc --reaper
  [ "$(cnt "^CLAIMED-NOT-LIVE  4bc1159f")" -ge 1 ]   # the PERSISTED record carries it
  [ "$(cnt 'locks/ absent')" -ge 1 ]         # absent source: named, not fatal
  [ "$status" -eq 0 ]
}

# ── R2-R3: the two ways a claim is NOT a fault ───────────────────────────────────────────────────

@test "R2 a claim younger than the 120 s grace is not reaped" {
  run cc --reaper
  [ "$(cnt '^CLAIMED-NOT-LIVE')" -eq 2 ]   # control: they ARE reapable
  python3 - "$L" "$LR_NOW" <<'PY'
import json, sys, glob, datetime
now = datetime.datetime.fromisoformat(sys.argv[2].replace("Z", "+00:00"))
fresh = (now - datetime.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ")
for p in glob.glob(sys.argv[1] + "/*.lock"):
    rec = json.load(open(p)); rec["ts"] = fresh; json.dump(rec, open(p, "w"))
PY
  run cc --reaper
  [ "$status" -eq 0 ]
  [ "$(cnt '^CLAIMED-NOT-LIVE')" -eq 0 ]
  [ "$(cnt '^0 claimed-not-live')" -ge 1 ]
}

@test "R3 a live registry row for the claimed sid clears its own claim" {
  # A TRUE claim clears itself: the transplant it recorded worked, the session is alive on the
  # account the lock names, and there is nothing left to reap.
  run cc --reaper
  [ "$(cnt '^CLAIMED-NOT-LIVE  4bc1159f')" -ge 1 ]
  cat > "$CC_REGISTRY_DIR/199.json" <<JSON
{"paneUUID":"199","name":"p199","cwd":"$HOME","account":"claude-secondary","pid":12341,
 "startedAt":1789857366000,"session_id":"$SID_4B","lstart":"Fri Sep 19 12:00:00 2026"}
JSON
  run cc --reaper
  [ "$status" -eq 0 ]
  [ "$(cnt 4bc1159f)" -eq 0 ]
  [ "$(cnt '^CLAIMED-NOT-LIVE  98f02458')" -ge 1 ]   # the other one stands
}

# ── R4-R5: the resolver ──────────────────────────────────────────────────────────────────────────

@test "R4 one title over two panes on two accounts is exit 3 with BOTH candidates printed" {
  # P10: two panes on different accounts genuinely share the title "limit-recover optimization".
  # Picking one is the failure — the operator asked about a name that names two things.
  DEV="$W/Users/chrisren/Development"
  title "$HOME/.claude-tertiary/projects/$(slug "$DEV/.worktrees/wt-cc-143039-68221")/07e30aeb-0000-4000-8000-000000000000.jsonl" "limit-recover optimization"
  title "$HOME/.claude-secondary/projects/$(slug "$DEV/.worktrees/subagent-lifecycle-w0")/65186f1f-0000-4000-8000-000000000000.jsonl" "limit-recover optimization"
  run cc --keyword limit-recover
  [ "$status" -eq 3 ]
  [ "$(cnt 'limit-recover optimization')" -eq 2 ]
  [ "$(cnt '#147  · 07e30aeb · next3')" -ge 1 ]
  [ "$(cnt '#121  · 65186f1f · next2')" -ge 1 ]
  run cc "LIMIT-Recover"                       # bare query, case-insensitive, same verdict
  [ "$status" -eq 3 ]
}

@test "R5 a sid prefix resolves to one row; an unmatched query is exit 4" {
  run cc --sid 07e3
  [ "$status" -eq 0 ]
  [ "$(cnt '07e30aeb')" -eq 1 ]
  run cc 07e3                                  # the bare-query form resolves the same one row
  [ "$status" -eq 0 ]
  [ "$(cnt '07e30aeb')" -eq 1 ]
  run cc --sid zz
  [ "$status" -eq 4 ]
  [ -z "$output" ]
  run cc zzqq
  [ "$status" -eq 4 ]
  [ -z "$output" ]
}

# ── R6: --kitty ──────────────────────────────────────────────────────────────────────────────────

@test "R6 a truncated kitten payload gives every title ? and exit 6 — rows still printed" {
  # NEVER a partial parse. A regex over half a JSON document returns SOME titles and no way to know
  # which are missing, which is strictly worse than none (the 10.06 s corrupt-payload case, U07 §5).
  printf '#!/bin/sh\nprintf %%s %s\n' "'[{\"tabs\":[{\"windows\":[{\"id\":147,\"tit'" > "$W/kitten"
  chmod +x "$W/kitten"
  export CC_LIMITED_KITTEN="$W/kitten"
  run cc --kitty
  [ "$status" -eq 6 ]
  [ "$(cnt '07e30aeb')" -ge 1 ]              # the rows are NOT withheld
  [ "$(cnt '4bc1159f')" -ge 1 ]
  [ "$(cnt 'truncated/unparseable')" -ge 1 ]
  [ "$(cnt 'wt-cc-143039-68221')" -eq 0 ]   # no stale transcript title
  [ "$(cnt '07e30aeb .*  ?')" -ge 1 ]
}

@test "R6 CONTROL a well-formed payload titles the rows from kitty and stays green" {
  # Without this the row above passes for a subject that always prints `?` and always exits 6.
  cat > "$W/kitten" <<'EOF'
#!/bin/sh
echo '[{"tabs":[{"windows":[{"id":147,"title":"limit-recover optimization"}]}]}]'
EOF
  chmod +x "$W/kitten"
  export CC_LIMITED_KITTEN="$W/kitten"
  run cc --kitty
  [ "$status" -eq 0 ]
  [ "$(cnt 'limit-recover optimiza')" -ge 1 ]
  [ "$(cnt ' ? ')" -eq 0 ]
}

# ── RED-PROOF ────────────────────────────────────────────────────────────────────────────────────
# Every row above run against a PRISTINE HEAD copy of bin/cc-limited (17c64b1a8^..HEAD = 7802a283d),
# via CC_LIMITED_BIN, with the sibling scripts/limit-recover symlinked so the subject still imports
# its own predicate module (a copy that dies at import reads as "killed" for the wrong reason):
#
#   $ CC_LIMITED_BIN=<pristine>/bin/cc-limited bats tests/cc-limited-reaper.bats
#   1..10
#   not ok 1 R1 4bc1159f: a stale claim with no live process is ONE reaper line, with claimant/ts/age/path
#   # (in test file tests/cc-limited-reaper.bats, line 45)
#   #   `[ "$status" -eq 0 ]' failed
#   not ok 2 R1 --persist writes the fault ONCE: a second tick leaves first_seen and mtime untouched
#   # (in test file tests/cc-limited-reaper.bats, line 58)
#   #   `[ "$status" -eq 0 ]' failed
#   not ok 3 R1b ack --why renames the fault and is the ONLY exit — the lock stops being reaped too
#   #  in test file tests/cc-limited-reaper.bats, line 70)
#   #   `cc --reaper --persist >/dev/null' failed with status 2
#   not ok 4 R1c the marker aged past its TTL and the fault STILL renders
#   #  in test file tests/cc-limited-reaper.bats, line 87)
#   #   `cc --reaper --persist >/dev/null' failed with status 2
#   not ok 5 R2 a claim younger than the 120 s grace is not reaped
#   # (in test file tests/cc-limited-reaper.bats, line 108)
#   #   `[ "$(cnt '^CLAIMED-NOT-LIVE')" -eq 2 ]   # control: they ARE reapable' failed
#   not ok 6 R3 a live registry row for the claimed sid clears its own claim
#   # (in test file tests/cc-limited-reaper.bats, line 126)
#   #   `[ "$(cnt '^CLAIMED-NOT-LIVE  4bc1159f')" -ge 1 ]' failed
#   not ok 7 R4 one title over two panes on two accounts is exit 3 with BOTH candidates printed
#   # (in test file tests/cc-limited-reaper.bats, line 146)
#   #   `[ "$status" -eq 3 ]' failed
#   not ok 8 R5 a sid prefix resolves to one row; an unmatched query is exit 4
#   # (in test file tests/cc-limited-reaper.bats, line 159)
#   #   `[ "$status" -eq 0 ]' failed
#   not ok 9 R6 a truncated kitten payload gives every title ? and exit 6 — rows still printed
#   # (in test file tests/cc-limited-reaper.bats, line 178)
#   #   `[ "$status" -eq 6 ]' failed
#   not ok 10 R6 CONTROL a well-formed payload titles the rows from kitty and stays green
#   # (in test file tests/cc-limited-reaper.bats, line 195)
#   #   `[ "$status" -eq 0 ]' failed
