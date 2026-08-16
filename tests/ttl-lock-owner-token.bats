#!/usr/bin/env bats
# The two mtime-TTL mkdir locks must not double-release (a15/D4):
#   hooks/lib/mailbox-pending.sh  _mbx_lock / _mbx_unlock
#   bin/cc-idl                    acquire_lock / release_lock
#
# THE CHAIN. Both reaped purely on the lock dir's mtime and both released with an unconditional
# delete, with no owner token written or checked. So: A holds the lock and is SIGSTOP'd or
# load-starved past the TTL; B sees an over-age dir, deletes it, mkdirs its own, enters; A resumes and
# its unlock deletes B's lock; C now mkdirs and enters too. Two concurrent cursor writers is the
# bounded duplicate the mailbox design deliberately accepts (dup over hang). THREE — one of them
# holding a mutex that no longer exists — is not bounded by anything.
#
# WHAT IS *NOT* CHANGED, deliberately: the 2 s give-up and the TTL self-break. Those are the
# dup-over-hang contract (a hook must never block), and tests 3 and 7 pin that they still hold.
#
# The audit rated cc-idl's variant moot because cc-idl had zero callers; its own uncertainties
# section flagged the caveat, and the caveat is now the case — scripts/rotate-autonomy-logs.sh seals
# the IDL tail on every run, so this lock is genuinely contended.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbx"   # the seam _mbx_dir() actually reads
  mkdir -p "$CC_MAILBOX_DIR"
  # shellcheck source=/dev/null
  source "$REPO/hooks/lib/mailbox-pending.sh"
  U="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  MLD="$CC_MAILBOX_DIR/.$U.lock"

  IDL="$REPO/bin/cc-idl"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_IDL_CHAIN="$BATS_TEST_TMPDIR/idl.jsonl.chain"
  export CC_IDL_LOCK="$BATS_TEST_TMPDIR/idl.lock.d"
  : > "$CC_IDL"
}

deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; printf '%s\n' "$p"; }

# ── mailbox ──────────────────────────────────────────────────────────────────────────────────────

@test "1: mailbox — acquire stamps an owner token" {
  _mbx_lock "$U"
  [ -f "$MLD/owner" ] || { echo "no owner token written — release cannot be verified"; false; }
  local tok; read -r tok < "$MLD/owner"
  [ "$tok" = "$$" ] || { echo "token is '$tok', expected our pid $$"; false; }
  _mbx_unlock "$U"
}

@test "2: mailbox — unlock does NOT delete a lock owned by someone else (the double-release)" {
  _mbx_lock "$U"
  sleep 5 & local thief=$!
  printf '%s\n' "$thief" > "$MLD/owner"       # our lock was TTL-stolen; this dir is now theirs
  _mbx_unlock "$U"
  [ -d "$MLD" ] || { echo "deleted the thief's live lock — a third writer can now enter"; kill "$thief" 2>/dev/null; false; }
  local tok; read -r tok < "$MLD/owner"
  [ "$tok" = "$thief" ] || { echo "thief's token was clobbered"; kill "$thief" 2>/dev/null; false; }
  kill "$thief" 2>/dev/null || true; wait "$thief" 2>/dev/null || true
}

@test "3: mailbox — the dup-over-hang contract is intact: a live holder makes us GIVE UP, not hang" {
  mkdir -p "$MLD"
  printf '%s\n' "$$" > "$MLD/owner"           # a live holder (us), fresh dir → not stale
  local t0 t1
  t0=$(date +%s)
  run env CC_MBX_LOCK_WAIT_MS=300 bash -c "
    source '$REPO/hooks/lib/mailbox-pending.sh'
    _mbx_lock '$U'
  "
  t1=$(date +%s)
  [ "$status" -eq 1 ] || { echo "expected give-up (rc 1), got $status — a hook could now block"; false; }
  [ $((t1 - t0)) -le 5 ] || { echo "gave up but took $((t1 - t0))s — the wait bound is not honoured"; false; }
  rm -rf "$MLD"
}

@test "4: mailbox — a DEAD holder's lock is reclaimed at once, without waiting out the TTL" {
  mkdir -p "$MLD"
  deadpid > "$MLD/owner"
  # fresh dir, so only the pid check can justify entry — the mtime TTL (10s) cannot have elapsed
  run env CC_MBX_LOCK_WAIT_MS=300 bash -c "
    source '$REPO/hooks/lib/mailbox-pending.sh'
    _mbx_lock '$U'
  "
  [ "$status" -eq 0 ] || { echo "a dead holder still blocked acquisition for its full TTL"; false; }
}

@test "5b: mailbox — _mbx_mtime reads a REAL mtime here (the stat-flag-order trap under test 3)" {
  # Test 3 above is the behavioural half; this is the direct one, because the two failures look
  # nothing alike. `stat -f %m` is BSD mtime and GNU --file-system: on Linux the old macOS-first
  # idiom exited 0 printing an inode report, the digit guard read it as 0, and every freshness
  # question in the lib answered "ancient" forever — a live holder's lock stolen on the first poll,
  # a live watcher's heartbeat reported unarmed. Pin that the helper returns a plausible NOW, so a
  # future "simplification" back to the wrong flag order is caught as itself, not as a lock bug.
  local f="$CC_MAILBOX_DIR/mtime-probe" now mt
  : > "$f"; now="$(date +%s)"; mt="$(_mbx_mtime "$f")"
  [ "$mt" -gt 0 ] || { echo "_mbx_mtime returned '$mt' for a file that exists"; false; }
  [ "$(( now - mt ))" -lt 60 ] || { echo "_mbx_mtime returned $mt, now is $now — not this file's mtime"; false; }
  [ "$(_mbx_mtime "$CC_MAILBOX_DIR/does-not-exist")" = "0" ]
}

@test "5: mailbox — an untokened dir (pre-fix holder) is still released, never leaked" {
  mkdir -p "$MLD"                             # no owner file, as a pre-fix holder would leave
  _mbx_unlock "$U"
  [ ! -d "$MLD" ] || { echo "release skipped an untokened lock — pre-fix dirs would leak forever"; false; }
}

# ── cc-idl ───────────────────────────────────────────────────────────────────────────────────────

@test "6: cc-idl — append stamps a token and releases its own lock cleanly" {
  run "$IDL" append '{"k":"v"}'
  [ "$status" -eq 0 ] || { echo "append failed: $output"; false; }
  [ ! -d "$CC_IDL_LOCK" ] || { echo "lock dir survived a clean append — release is incomplete"; false; }
}

@test "7: cc-idl — a live holder is respected and the wait is BOUNDED (rc 5, no hang)" {
  mkdir -p "$CC_IDL_LOCK"
  printf '%s\n' "$$" > "$CC_IDL_LOCK/owner"   # live holder, fresh dir
  run env CC_IDL_LOCK_WAIT=1 CC_IDL_LOCK_TTL=9999 "$IDL" append '{"k":"v"}'
  [ "$status" -eq 5 ] || { echo "expected rc 5 (could not acquire), got $status"; false; }
  [ -d "$CC_IDL_LOCK" ] || { echo "the live holder's lock was destroyed"; false; }
  local tok; read -r tok < "$CC_IDL_LOCK/owner"
  [ "$tok" = "$$" ] || { echo "live holder's token was clobbered"; false; }
  rm -rf "$CC_IDL_LOCK"
}

@test "8: cc-idl — a DEAD holder's lock is reclaimed immediately, not after LOCK_TTL" {
  mkdir -p "$CC_IDL_LOCK"
  deadpid > "$CC_IDL_LOCK/owner"
  # TTL pushed far out: only the pid-liveness check can let this through
  run env CC_IDL_LOCK_WAIT=1 CC_IDL_LOCK_TTL=9999 "$IDL" append '{"k":"v"}'
  [ "$status" -eq 0 ] || { echo "a dead holder blocked the append (rc $status) — reclaim did not fire"; false; }
  [ ! -d "$CC_IDL_LOCK" ] || { echo "lock not released after the reclaimed append"; false; }
}

@test "9: cc-idl — the REAL release_lock does not delete a foreign token (steal mid-hold)" {
  # Drives cc-idl's own release_lock, not a copy of it. An earlier version of this test reimplemented
  # the release logic inline and therefore asserted nothing about the subject — a tautology that
  # passed against the unfixed binary. To make it real the critical section has to stay open long
  # enough to steal the lock, so `perl` (which chain_extend shells out to) is stubbed to stall. The
  # seal then fails, which is fine and deliberate: cmd_seal calls release_lock on EVERY path, so the
  # release we want to observe still runs.
  local bin="$BATS_TEST_TMPDIR/stub"; mkdir -p "$bin"
  cat > "$bin/perl" <<'SH'
#!/bin/bash
sleep 3
exit 1
SH
  chmod +x "$bin/perl"

  printf '{"k":"v"}\n' > "$CC_IDL"
  PATH="$bin:$PATH" "$IDL" append '{"k":"v2"}' >/dev/null 2>&1 &
  local runner=$!

  # Wait on the lock DIR, not on the owner file: the unfixed binary writes no token at all, and
  # keying on the token would make this test fail pre-fix merely for the token's absence (which
  # tests 1/6 already cover) instead of for the release behaviour it is meant to isolate.
  local i=0
  while [ ! -d "$CC_IDL_LOCK" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -d "$CC_IDL_LOCK" ] || { echo "cc-idl never took the lock"; kill "$runner" 2>/dev/null; false; }

  sleep 9 & local peer=$!
  printf '%s\n' "$peer" > "$CC_IDL_LOCK/owner"     # peer stole it and now owns this dir
  wait "$runner" 2>/dev/null || true                # cc-idl exits → its release_lock runs
  sleep 0.5

  [ -d "$CC_IDL_LOCK" ] || { echo "cc-idl's release deleted a lock owned by another pid — third writer admitted"; kill "$peer" 2>/dev/null; false; }
  local tok; read -r tok < "$CC_IDL_LOCK/owner"
  [ "$tok" = "$peer" ] || { echo "peer token clobbered: '$tok'"; kill "$peer" 2>/dev/null; false; }
  kill "$peer" 2>/dev/null || true; wait "$peer" 2>/dev/null || true
}
