#!/usr/bin/env bats
# claude-accounts --fresh must not wait forever on the single-flight lock (a15/D7).
#
# THE DEFECT. `_acquire_lock` took a bare `fcntl.flock(lock, LOCK_EX)` with no deadline whenever
# allow_degrade was False — i.e. on every --fresh call — and a second bare blocking flock sat on the
# "no servable cache" fallback. fcntl releases on holder DEATH, so a crashed holder was always
# harmless; an ALIVE-but-wedged one (hung heal subprocess, network stall) was not. The holder legally
# owns this for MINUTES (4 accounts x keychain + a 90s heal + two retry ladders), and handoff-fire
# runs `--fresh --json` before firing a wave to decide the fleet is healthy — so one wedged holder
# stalled the wave indefinitely, with no diagnostic at all.
#
# WHY BOUNDING DOES NOT WEAKEN THE CONTRACT. --fresh may never be satisfied by cached data (the
# function's own reasoning: handing handoff-fire a 91-second-old cache would report "all accounts
# healthy or auto-healed" when no heal ran, and the wave would fire at a stranded account). So expiry
# RAISES a distinct type instead of returning the "serve grace cache" False — falling into the degrade
# path is made structurally impossible — and the top level renders that as a parseable failure: rc 5,
# and under --json an {"error":"fresh_lock_wedged"} object rather than a plausible table a machine
# consumer would read as success.
#
# Hermetic: the scratch SSOT + cache fixture from claude-accounts-core.bats (unreachable endpoints, a
# config_dir that hashes to a nonexistent keychain service), and the lock is held by a real flock in a
# python helper. Nothing touches the operator's accounts, cache, or keychain.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # $HOME is fixtured before anything else: CFG_PATH defaults to $HOME/.claude/accounts.json and
  # claude-accounts resolves several other paths under $HOME, so an unfixtured suite reads AND writes
  # the operator's live account state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  LOCK="$CACHE.lock"
  # Same DERIVED-from-real-SSOT fixture as claude-accounts-core.bats: a hand-copied config block
  # silently diverges the moment a constant is added.
  python3 - "$CA_CFG" "$CACHE" "$CA_SSOT" "$BATS_TEST_TMPDIR/model-config.yaml" <<'PY'
import json, sys
cfg_path, cache, real, yaml = sys.argv[1:5]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": yaml, "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude3",
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"}],
}, open(cfg_path, "w"))
PY
}

teardown() { [ -n "${HOLDER:-}" ] && { kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true; }; true; }

# Hold a REAL flock on $LOCK for N seconds in a live process — the alive-but-wedged holder.
hold_lock() { # $1=seconds
  python3 - "$LOCK" "$1" <<'PY' &
import fcntl, sys, time
with open(sys.argv[1], "w") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    time.sleep(float(sys.argv[2]))
PY
  HOLDER=$!
  # Block until the lock is genuinely held, so the test never races its own fixture.
  local i=0
  while [ "$i" -lt 60 ]; do
    if python3 - "$LOCK" <<'PY'
import fcntl, sys
try:
    with open(sys.argv[1], "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    sys.exit(1)      # acquired ⇒ holder not ready yet
except BlockingIOError:
    sys.exit(0)      # held ⇒ ready
except OSError:
    sys.exit(1)
PY
    then return 0; fi
    sleep 0.1; i=$((i + 1))
  done
  echo "fixture: the holder never took the lock"; return 1
}

@test "1: no UNBOUNDED blocking flock survives, and expiry has its own type" {
  # Structural on purpose: the defect was the bare `fcntl.flock(lock, fcntl.LOCK_EX)` form, and a
  # behavioural test can only prove boundedness on the ONE path it drives, never its absence
  # everywhere in the file. Both former sites are covered by this grep.
  run grep -nE 'fcntl\.flock\([a-z]+, fcntl\.LOCK_EX\)[[:space:]]*$' "$CA_BIN"
  [ "$status" -ne 0 ] || { echo "an UNBOUNDED blocking flock survives:"; echo "$output"; false; }
  grep -q 'class FreshLockWedged' "$CA_BIN" || { echo "no distinct wedged type — expiry could fall into the degrade path"; false; }
  grep -q '_fresh_lock_wait_s' "$CA_BIN" || { echo "no shared wall-clock budget helper"; false; }
}

@test "2: --fresh gives up within its budget instead of waiting out a live holder" {
  hold_lock 25
  local t0 t1
  t0=$(date +%s)
  run env CC_ACCOUNTS_FRESH_LOCK_WAIT_S=2 python3 "$CA_BIN" --fresh --json
  t1=$(date +%s)
  # The pre-fix code returns only when the holder exits, i.e. after ~25s.
  [ $((t1 - t0)) -lt 20 ] || { echo "waited $((t1 - t0))s — the --fresh flock is still unbounded (holder held 25s)"; false; }
}

@test "3: the failure is rc 5 and machine-parseable, never cache dressed as fresh" {
  # A SERVABLE cache is seeded first, so a wrong fix (quietly degrading to it) is distinguishable
  # from the right one (refusing loudly).
  python3 - "$CACHE" <<'PY'
import json, sys, time
json.dump({"ts": time.time(), "rows": [{"acct": "next3", "state": "ok"}],
           "window": {}, "prev": None}, open(sys.argv[1], "w"))
PY
  hold_lock 25
  run env CC_ACCOUNTS_FRESH_LOCK_WAIT_S=2 python3 "$CA_BIN" --fresh --json
  [ "$status" -eq 5 ] || { echo "expected rc 5 (io/lock), got $status. output: $output"; false; }
  printf '%s' "$output" | grep -q 'fresh_lock_wedged' || {
    echo "no parseable error token — handoff-fire would have to guess. output: $output"; false; }
  printf '%s' "$output" | grep -q '"cached": false' || { echo "did not declare cached:false: $output"; false; }
}

@test "4: an UNCONTENDED --fresh call does not report a wedged lock (no spurious fire)" {
  # Nothing holds the lock, so acquisition is immediate. The sweep itself fails on this fixture (no
  # reachable endpoint, no keychain) and that is fine — what is asserted is only that the BOUND did
  # not fire, i.e. the fix cannot manufacture a lock failure out of an uncontended call.
  run env CC_ACCOUNTS_FRESH_LOCK_WAIT_S=2 python3 "$CA_BIN" --fresh --json
  [ "$(printf '%s' "$output" | grep -c 'fresh_lock_wedged')" -eq 0 ] || {
    echo "reported a wedged lock with NO contention — the bound fires spuriously: $output"; false; }
}

@test "5: the budget is generous by default — never shorter than a lawful multi-minute hold" {
  # An exoneration bound set under what it bounds can only convict (memory:
  # exoneration-bound-must-fit-what-it-bounds). A legitimate holder can own this for minutes, so the
  # default must be minutes, not the 5s degrade-path budget.
  run python3 -c "
import importlib.machinery, importlib.util, json, os
loader = importlib.machinery.SourceFileLoader('ca', os.environ['CA_BIN'])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader('ca', loader))
loader.exec_module(ca)
cfg = json.load(open(os.environ['CA_CFG']))
print(int(ca._fresh_lock_wait_s(cfg)))
"
  [ "$status" -eq 0 ] || { echo "could not read the budget: $output"; false; }
  [ "$output" -ge 120 ] || { echo "default budget is only ${output}s — shorter than a lawful hold, so it would convict healthy sweeps"; false; }
}
