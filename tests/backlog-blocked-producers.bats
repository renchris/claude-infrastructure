#!/usr/bin/env bats
# THE TWO MACHINE PRODUCERS THAT FILED AGENT-DOABLE WORK INTO `blocked`.
#
# `blocked` is the operator-gated status and cc-dispatch excludes it from the wave BY CONSTRUCTION,
# so a row a machine puts there is a row no autonomous drain can ever reach. Measured 2026-08-18
# (BACKLOG_DRAIN_24_7 §2.1): `block` outran `unblock` 220:39 over 24h and ~119 of 403 open rows sat
# blocked. Two producers, both fixed here:
#
#   FIX 1  cc-backlog reap blocked EVERY venue=cloud claim, because the only oracle it consulted is
#          a LOCAL worktree probe that by construction cannot see an off-box worker. The block was
#          structural, not a finding — it could not fail to fire. 78 rows were sitting on that one
#          sentence, and all 78 had a cc-cloud declaration that answers them.
#   FIX 2  the `needs` mint brake folded two DISTINCT re-land steps onto one row, because the
#          mechanical key masks digit runs and this repo's fire branches differ ONLY in digits.
#
# EVERY TEST HERE IS RED ON THE PRE-FIX PAIR. Point CC_TEST_BIN_DIR at a directory holding the
# pre-fix bin/cc-backlog + bin/cc-cloud and the fix tests fail; the two CONTROLS stay green in both
# directions, which is what separates "the fix works" from "the key was disabled"
# (memory: control-must-replay-the-real-artifact, cost-gate-must-be-strictly-weaker).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="${CC_TEST_BIN_DIR:-$REPO/bin}"
  CB="$BIN/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"; mkdir -p "$CC_CLOUD_STATE"
  export CC_CLOUD_NOW=2000000

  # Two re-land steps VERBATIM in shape from the live ledger, from the SAME session — which is what
  # makes them collide: the pin's uuid supplies the only letters that could have differed, and it is
  # identical, so after digit-masking every token of both titles is the same string.
  # `@@` is substituted rather than printf-formatted (SC2059, and a stray `%` from a real title
  # would be eaten silently — the fixture would stop being the shape it claims to replay).
  RL_A='re-land claude/fire-20260812T071538Z-80941-1 (/private/tmp/.desk-land-claude-fire-20260812T071538Z-80941-1-68347): ship-land exited 5 (exit) and its author pane may be gone - head pinned at refs/land/failed/20260818T02@@Z-108d590f-63e9-453f-8e97-3813ef702e5e-claude-fire-20260812T071538Z-80941-1'
  RL_B='re-land claude/fire-20260814T055432Z-40416-1 (/private/tmp/.desk-land-claude-fire-20260814T055432Z-40416-1-38619): ship-land exited 5 (exit) and its author pane may be gone - head pinned at refs/land/failed/20260818T03@@Z-108d590f-63e9-453f-8e97-3813ef702e5e-claude-fire-20260814T055432Z-40416-1'
}

sub() { printf '%s' "${1//@@/$2}"; }   # <template> <digits> → the fixture title

# ── FIX 2 — the needs brake must not merge two branches ────────────────────────────────────────

@test "FIX2: two re-land steps naming DIFFERENT branches do NOT merge (they differ only in digits)" {
  first="$(bash "$CB" needs "$(sub "$RL_A" 5230)" --project p 2>/dev/null)"
  [ -n "$first" ]
  # stdout ONLY — bats `run` folds stderr in, and the brake announces RECURRENCE on stderr, so
  # $output would compare the NOTICE against an id and pass for the wrong reason.
  second="$(bash "$CB" needs "$(sub "$RL_B" 0945)" --project p 2>/dev/null)"
  # PRE-FIX: the brake reports RECURRENCE and echoes $first — one row now names branch A in its
  # title and branch B in its needs/run, so acting on it re-lands the WRONG branch and leaves the
  # titled one unowned. POST-FIX: a second id, and each branch keeps its own row.
  [ -n "$second" ]
  [ "$second" != "$first" ]
  [ "$(bash "$CB" list --all --json | jq 'length')" -eq 2 ]
}

@test "FIX2: the two branches remain separately addressable — neither is left unowned" {
  bash "$CB" needs "$(sub "$RL_A" 5230)" --project p >/dev/null 2>&1
  bash "$CB" needs "$(sub "$RL_B" 0945)" --project p >/dev/null 2>&1
  titles="$(bash "$CB" list --all --json | jq -r '.[].title')"
  [ "$(printf '%s\n' "$titles" | grep -c 'claude/fire-20260812T071538Z-80941-1')" -ge 1 ]
  [ "$(printf '%s\n' "$titles" | grep -c 'claude/fire-20260814T055432Z-40416-1')" -ge 1 ]
}

@test "FIX2 CONTROL: two re-lands of the SAME branch differing only in the pin timestamp STILL fold" {
  # The key must keep doing its job — §1.3 measured 39 duplicate rows for ONE stuck branch. A fix
  # that split these too would have disabled the key rather than repaired it. GREEN BOTH SIDES.
  first="$(bash "$CB" needs "$(sub "$RL_A" 5230)" --project p 2>/dev/null)"
  second="$(bash "$CB" needs "$(sub "$RL_A" 9911)" --project p 2>/dev/null)"
  [ "$second" = "$first" ]
  [ "$(bash "$CB" list --all --json | jq 'length')" -eq 1 ]
}

# ── FIX 1 — the reap must consult cc-cloud before blocking a venue=cloud claim ──────────────────

# decl <item-id> <branch> <push?> [contract?] — a cloud declaration + the git fixture classify()
# reads through.
# ONE fixture, ONE flag: the ref is ABSENT (-> NOT-STARTED, past the 900s boot budget) or PRESENT
# (-> ALIVE, inside the 21600s life budget). declared_at sits 1000s before the pinned clock so it is
# past boot and inside life at once — the two states then differ by exactly one observable, which is
# what makes the pair a control rather than two unrelated fixtures.
#
# `contract=ok` is written by DEFAULT because these fixtures model a REAL fire, and a real fire
# attaches the boot-push contract (cc-cloud's THE CONTRACT; cc-offload writes it after the brief
# queues). Without it cc-cloud answers NO-CONTRACT rather than NOT-STARTED — an honest "cannot
# tell" — and the reap correctly declines to reopen. The 4th arg drops it, so that arm has its own
# fixture rather than being reached by accident.
#
# Identity is passed with transient `-c`, never `git config`: this suite runs inside a linked
# worktree that shares one .git/config with ~100 siblings, and `git -C ""` is a documented NO-OP, so
# an all-expansion target would silently re-author commits in the REAL repo (the 2026-08-05 leak).
decl() {
  local item="$1" branch="$2" push="${3:-no}" contract="${4:-yes}"
  local bare="$BATS_TEST_TMPDIR/remote.git" work="$BATS_TEST_TMPDIR/work"
  if [ ! -d "$bare" ]; then
    git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
    git init -q "$BATS_TEST_TMPDIR/work"
    echo seed > "$BATS_TEST_TMPDIR/work/a.txt"
    git -C "$BATS_TEST_TMPDIR/work" add a.txt
    git -C "$BATS_TEST_TMPDIR/work" -c user.email=t@t -c user.name=t commit -qm seed
    git -C "$BATS_TEST_TMPDIR/work" remote add origin "$bare"
    git -C "$BATS_TEST_TMPDIR/work" push -q origin HEAD:refs/heads/main
  fi
  [ "$push" = yes ] && git -C "$BATS_TEST_TMPDIR/work" push -q origin "HEAD:refs/heads/$branch"
  cat > "$CC_CLOUD_STATE/session_$item.decl" <<EOF
id=session_$item
branch=$branch
remote=origin
repo=$work
paths=
url=https://claude.ai/code/session_$item
item=$item
declared_at=$(( CC_CLOUD_NOW - 1000 ))
EOF
  [ "$contract" = yes ] && printf 'contract=ok\n' >> "$CC_CLOUD_STATE/session_$item.decl"
  return 0
}

# reap_cloud <push?> — files a row, claims it off-box, ages the claim past the stale gate, sweeps.
# Sets ROW and writes the sweep log to $REAPLOG. Deliberately NOT called in a command substitution:
# that is a subshell, and ROW would never reach the test.
reap_cloud() {
  ROW="$(bash "$CB" add --title "off-box unit of work" --project p --source t)"
  decl "$ROW" "claude/fire-20260812T071538Z-80941-1" "${1:-no}"
  bash "$CB" claim "$ROW" --by dispatcher-9999 --venue cloud --force >/dev/null 2>&1
  REAPLOG="$BATS_TEST_TMPDIR/reap.log"
  CC_BACKLOG_NOW="$(( $(date +%s) + 100000 ))" bash "$CB" reap >"$REAPLOG" 2>&1
}

status_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

@test "FIX1: a venue=cloud claim whose cc-cloud state is NOT-STARTED is REOPENED, never blocked" {
  reap_cloud no
  # PRE-FIX: BLOCK <id> [unresolvable worktree oracle] — the local probe cannot see off-box, so the
  # block could not fail to fire. POST-FIX: cc-cloud answers NOT-STARTED and the row returns to the
  # wave. Asserted on the STATUS too, not just the log line: the ledger is what cc-dispatch reads.
  grep -q 'NOT-STARTED' "$REAPLOG"
  [ "$(status_of "$ROW")" = open ]
}

@test "FIX1 CONTROL: a venue=cloud claim whose worker is genuinely ALIVE off-box STILL blocks" {
  # The block is not deleted, it is RESERVED — reopening a live off-box worker would fire a second
  # peer onto live work, the exact double-dispatch the local oracle existed to prevent.
  reap_cloud yes
  grep -q 'live-cloud-worker' "$REAPLOG"
  [ "$(status_of "$ROW")" = blocked ]
}

@test "FIX1 CONTROL: an UNCONTRACTED fire is NO-CONTRACT, and that BLOCKS rather than reopening" {
  # The same absent ref as the FIX1 case above, with exactly one thing removed: the fire never
  # promised a first push. cc-cloud then reads NO-CONTRACT — four worlds at once, including a
  # session that booted, worked and had nothing to push — and reopening on that would fire a
  # SECOND peer onto possibly-live work. So it parks, and NAMES the reader that can settle it.
  ROW="$(bash "$CB" add --title "uncontracted off-box work" --project p --source t)"
  decl "$ROW" "claude/fire-20260812T071538Z-80941-1" no no
  bash "$CB" claim "$ROW" --by dispatcher-9999 --venue cloud --force >/dev/null 2>&1
  REAPLOG="$BATS_TEST_TMPDIR/reap-nc.log"
  CC_BACKLOG_NOW="$(( $(date +%s) + 100000 ))" bash "$CB" reap >"$REAPLOG" 2>&1
  grep -q 'NO-CONTRACT' "$REAPLOG"
  [ "$(status_of "$ROW")" = blocked ]
}

@test "FIX1 CONTROL: with NO cloud declaration the reap still blocks — ignorance stays fail-closed" {
  # rc 2 from the oracle means "cannot tell", and cannot-tell must never manufacture a verdict.
  # GREEN BOTH SIDES: pre-fix blocks because it always did, post-fix because it abstained.
  id="$(bash "$CB" add --title "undeclared off-box work" --project p --source t)"
  bash "$CB" claim "$id" --by dispatcher-9999 --venue cloud --force >/dev/null 2>&1
  CC_BACKLOG_NOW="$(( $(date +%s) + 100000 ))" bash "$CB" reap >/dev/null 2>&1
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = blocked ]
}

@test "FIX1 CURE: a row ALREADY blocked on the off-box sentence is re-adjudicated and cleared" {
  # A fix that only stops the bleeding leaves every earlier casualty unreachable — nothing else
  # scans `blocked`. Scoped to the reap's OWN blocks carrying that sentence; a human's block, or
  # any other reason, is never touched.
  id="$(bash "$CB" add --title "stranded off-box row" --project p --source t)"
  decl "$id" "claude/fire-20260812T071538Z-80941-1" no
  bash "$CB" claim "$id" --by dispatcher-9999 --venue cloud --force >/dev/null 2>&1
  bash "$CB" block "$id" --by cc-backlog-reap \
    --needs 'the worktree occupancy oracle could not be RESOLVED past the 21600s ceiling - worker runs off-box (venue cloud)' >/dev/null 2>&1
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = blocked ]
  run env CC_BACKLOG_NOW="$(( $(date +%s) + 100000 ))" bash "$CB" reap
  [ "$status" -eq 0 ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = open ]
}

@test "FIX1 CURE CONTROL: a block written by someone OTHER than the reap is left alone" {
  id="$(bash "$CB" add --title "operator gated off-box row" --project p --source t)"
  decl "$id" "claude/fire-20260812T071538Z-80941-1" no
  bash "$CB" claim "$id" --by dispatcher-9999 --venue cloud --force >/dev/null 2>&1
  bash "$CB" block "$id" --by a-human \
    --needs 'the worktree occupancy oracle could not be RESOLVED past the 21600s ceiling - worker runs off-box (venue cloud)' >/dev/null 2>&1
  CC_BACKLOG_NOW="$(( $(date +%s) + 100000 ))" bash "$CB" reap >/dev/null 2>&1
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = blocked ]
}
