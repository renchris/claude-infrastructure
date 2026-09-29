#!/usr/bin/env bats
# claude-accounts — the v2 assignment ledger (lr-reconciler W1): weighted, voidable, ttl'd rows,
# --assign-many / --unassign, the sweep-sid double-charge guard, and a REAL --max-wait N bound.
#
# Hermetic: scratch SSOT, cache, ledger, util series and logs all under BATS_TEST_TMPDIR (the
# harness is claude-accounts-core.bats's, trimmed). Nothing touches the real ~/.claude stores.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CC_ROUTE_ASSIGN CC_ROUTE_ASSIGN_TTL_MIN
  rm -f "$CA_LEDGER" "$CACHE" "$CC_ASSIGN_LOG"
  python3 - "$CA_CFG" "$CACHE" "$CA_SSOT" "$YAML" <<'PY'
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
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"},
               {"name": "next2", "config_dir": "/tmp/ca-test-nonexistent-xyz2",
                "launcher": "claude2",
                "email": "test2@example.com", "mailbox": "test2@example.com", "dia_profile": "U"}],
}, open(cfg_path, "w"))
PY
}

LOAD='
import importlib.machinery, importlib.util, os, json
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
P = os.environ["CC_ASSIGN_LOG"]
def put(*rows):
    with open(P, "a") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
'

@test "(i) void rows survive _assignment_rows and ttl_s expiry works" {
  run python3 -c "$LOAD"'
t = 1_000_000.0
put({"t": t, "acct": "next3", "id": "gone", "w": 3},
    {"t": t + 1, "void": "gone"},
    {"t": t, "acct": "next2", "id": "heavy", "w": 5},
    {"t": t, "acct": "next3", "id": "short", "ttl_s": 30},
    {"t": t, "acct": "next2"})                                        # legacy: 15 min TTL
rows = ca._assignment_rows(P)
assert any(r.get("void") == "gone" for r in rows), rows
c = ca.assignment_counts(cfg, path=P, now=t + 10)
assert c == {"next2": 6, "next3": 1}, c                   # voided id 0 · w=5 · ttl row · legacy
c = ca.assignment_counts(cfg, path=P, now=t + 40)
assert c == {"next2": 6}, c                               # the ttl_s=30 row expired, legacy did not
assert ca.assignment_counts(cfg, path=P, now=t + 14 * 60) == {"next2": 6}
assert ca.assignment_counts(cfg, path=P, now=t + 16 * 60) == {}      # legacy keeps 15 min
# duplicate id: a re-plan REPLACES — counted once, and the newest row (acct + w) wins
put({"t": t + 2, "acct": "next3", "id": "dup", "w": 2},
    {"t": t + 3, "acct": "next2", "id": "dup", "w": 4})
c = ca.assignment_counts(cfg, path=P, now=t + 10)
assert c == {"next2": 10, "next3": 1}, c
# a void row is never a charge for desk_incumbent either
assert ca.desk_incumbent(cfg, path=P, now=t + 10) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "(j) --max-wait 2 on a held lock returns within 2.5 s with exit 3" {
  python3 - "$CACHE.lock" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[1] + ".held", "w").close()
time.sleep(6)
PY
  holder=$!
  for _ in $(seq 50); do [ -e "$CACHE.lock.held" ] && break; python3 -c 'import time; time.sleep(0.1)'; done
  [ -e "$CACHE.lock.held" ]
  # Timed around the child alone, in one interpreter: bats' `run` and a second python startup
  # are not the command's wall clock, and on a loaded box they alone cost ~0.5 s.
  run python3 -c '
import os, subprocess, sys, time
t = time.monotonic()
r = subprocess.run([os.environ["CA_BIN"], "--json", "--max-wait", "2"], capture_output=True)
print(r.returncode, round(time.monotonic() - t, 3))'
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  read -r rc elapsed <<<"$output"
  [ "$rc" -eq 3 ] || { echo "$output"; false; }
  python3 -c "import sys; sys.exit(0 if $elapsed < 2.5 else 1)" || { echo "elapsed=$elapsed"; false; }
  [ ! -e "$CACHE" ]                                   # nothing swept, nothing cached
}

@test "--assign-many is all-or-nothing: one bad line exits 64 and the ledger is unchanged" {
  printf '%s\n' '{"t":1,"ts":"x","acct":"next3"}' > "$CC_ASSIGN_LOG"
  before="$(cat "$CC_ASSIGN_LOG")"
  f="$BATS_TEST_TMPDIR/plan.jsonl"
  printf '%s\n' '{"acct":"next3","id":"a1","sid":"s-1","w":2,"ttl_s":60}' \
                '{"acct":"next2","id":"a2","w":0}' > "$f"
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 64 ] || { echo "$output"; false; }
  [[ "$output" == *"line 2"* ]]
  [ "$(cat "$CC_ASSIGN_LOG")" = "$before" ]
  # the good batch lands whole, with one shared t
  printf '%s\n' '{"acct":"next3","id":"a1","sid":"s-1","w":2,"ttl_s":60}' '' \
                '{"acct":"next2","id":"a2"}' > "$f"
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -c '
import json, os, sys
rows = [json.loads(l) for l in open(os.environ["CC_ASSIGN_LOG"])][1:]
assert len(rows) == 2 and rows[0]["t"] == rows[1]["t"], rows
assert list(rows[0]) == ["t", "ts", "acct", "id", "sid", "w", "ttl_s"], rows[0]
assert list(rows[1]) == ["t", "ts", "acct", "id"], rows[1]
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  # an empty file writes nothing
  : > "$f"
  n0=$(wc -l < "$CC_ASSIGN_LOG")
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_ASSIGN_LOG")" -eq "$n0" ]
}

@test "--unassign appends {t, ts, void} and is idempotent; a bad id exits 64" {
  run "$CA_BIN" --unassign plan:w1.a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CA_BIN" --unassign plan:w1.a
  [ "$status" -eq 0 ]
  run python3 -c '
import json, os
rows = [json.loads(l) for l in open(os.environ["CC_ASSIGN_LOG"])]
assert len(rows) == 2 and all(list(r) == ["t", "ts", "void"] for r in rows), rows
assert rows[0]["void"] == "plan:w1.a", rows
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  run "$CA_BIN" --unassign 'bad id!'
  [ "$status" -eq 64 ]
  run "$CA_BIN" --assign next3 --w 0
  [ "$status" -eq 64 ]
  run "$CA_BIN" --assign next3 --sid 'a b'
  [ "$status" -eq 64 ]
  [ "$(wc -l < "$CC_ASSIGN_LOG")" -eq 2 ]
}

@test "legacy --assign next3 --src x writes the byte-identical {t,ts,acct,src} row" {
  run "$CA_BIN" --assign next3 --src x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CA_BIN" --assign next2
  [ "$status" -eq 0 ]
  run python3 -c '
import json, os
from datetime import datetime, timezone
lines = open(os.environ["CC_ASSIGN_LOG"]).read().splitlines()
a, b = (json.loads(l) for l in lines)
assert list(a) == ["t", "ts", "acct", "src"] and a["acct"] == "next3" and a["src"] == "x", a
assert list(b) == ["t", "ts", "acct"], b
# the exact serialisation the pre-v2 writer produced for the same values
want = json.dumps({"t": a["t"], "ts": a["ts"], "acct": "next3", "src": "x"}, separators=(",", ":"))
assert lines[0] == want, (lines[0], want)
assert datetime.fromisoformat(a["ts"]).tzinfo is not None and a["ts"].endswith("+00:00"), a
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "apply_assignments skips a sid phantom the same account's sweep already counts" {
  run python3 -c "$LOAD"'
import time
t = time.time() - 60
put({"t": t, "acct": "next3", "id": "p1", "sid": "sess-a", "w": 2},   # swept by next3 → skipped
    {"t": t, "acct": "next3", "id": "p2", "sid": "sess-b"},           # not in the sweep → 1
    {"t": t, "acct": "next2", "id": "p3", "sid": "sess-a"},           # other acct swept it → 1
    {"t": t, "acct": "next3"})                                        # no sid → 1
ca.ASSIGN_PATH = P
rows = [dict(acct="next3", k_sids=["sess-a"], k_sids_at=t + 5), dict(acct="next2")]
ca.apply_assignments(rows, cfg)
assert [r["k_phantom"] for r in rows] == [2, 1], rows
# a sweep OLDER than the phantom does not know that session yet: the charge stands
rows = [dict(acct="next3", k_sids=["sess-a"], k_sids_at=t - 5), dict(acct="next2")]
ca.apply_assignments(rows, cfg)
assert [r["k_phantom"] for r in rows] == [4, 1], rows
# an unmeasured sweep (k_sids_at None) skips nothing
rows = [dict(acct="next3", k_sids=None, k_sids_at=None)]
ca.apply_assignments(rows, cfg)
assert rows[0]["k_phantom"] == 4, rows
# the census carries the top-level sids it counted, and only those
import os
base = os.path.join(os.environ["BATS_TEST_TMPDIR"], "kw")
sub = os.path.join(base, "projects", "slug", "sess-x", "subagents")
os.makedirs(sub)
open(os.path.join(base, "projects", "slug", "sess-x.jsonl"), "w").close()
open(os.path.join(sub, "agent-1.jsonl"), "w").close()
got = ca.working_concurrency({"accounts": [{"name": "a", "config_dir": base}]},
                             window_min=10, budget_s=5.0)
assert got == {"a": 2} and got.sids == {"a": {"sess-x"}} and got.at is not None, (got, got.sids)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}
