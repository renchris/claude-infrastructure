#!/usr/bin/env bats
# claude-accounts — the working census is capped at the live processes (bound_kwork).
#
# working_concurrency counts transcripts written in the last KWORK_WINDOW_MIN minutes, which is
# THROUGHPUT: a headless `claude -p` job that exited nine minutes ago still counts. Measured
# 2026-09-25: an eval harness running short headless jobs back to back made every account read
# 18-21 top-level "working" transcripts against 2-4 live processes, so all three healthy accounts
# were refused kmax-concurrency (KMAX 8) and the router abstained. These cases pin the physical
# ceiling (top-level term <= live processes incl. headless), the subagent carve-out, the
# plain-dict no-op that keeps every older stub valid, and the kill switch. The first case is the
# control: it fails on the pre-fix tree, where bound_kwork does not exist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CA_BIN="$REPO/bin/claude-accounts"
}

_pre() {
  cat <<'PY'
import importlib.machinery, importlib.util, os
_ld = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", _ld))
_ld.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
PY
}

@test "bound_kwork: finished headless jobs no longer count as working sessions" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 2}, headless={"a": 1})     # 2 interactive + 1 headless live
wc = ca._Census({"a": 21}, top={"a": 21})            # 21 top-level transcripts in the window
row = {"k_work": 21}
ca.bound_kwork(row, "a", counts, wc)
assert row["k_work"] == 3, row
assert row["k_work_raw"] == 21, row
R = {"KMAX": 8, "KMAX_RESIDENT": 40}
assert ca.k_eff(row) < ca.k_cap(dict(row, k=2), R), "still refused kmax-concurrency"
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: subagent transcripts stay uncapped (they share their parent process)" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 4}, headless={"a": 0})
wc = ca._Census({"a": 28}, top={"a": 18})            # 18 top-level + 10 subagent
row = {"k_work": 28}
ca.bound_kwork(row, "a", counts, wc)
assert row["k_work"] == 4 + 10, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: never raises the count, and a live count above the walk changes nothing" {
  run python3 -c "$(_pre)"'
counts = ca._Census({"a": 9}, headless={"a": 3})
wc = ca._Census({"a": 5}, top={"a": 5})
row = {"k_work": 5}
ca.bound_kwork(row, "a", counts, wc)
assert row == {"k_work": 5}, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: plain dicts (older callers and test stubs) and unmeasured inputs are a no-op" {
  run python3 -c "$(_pre)"'
for counts, wc, kw in [({"a": 1}, {"a": 21}, 21),                       # no split carried
                       (None, ca._Census({"a": 21}, top={"a": 21}), 21), # ps unmeasured
                       (ca._Census({"a": 1}, headless={"a": 0}), None, None)]:  # walk over budget
    row = {"k_work": kw}
    ca.bound_kwork(row, "a", counts, wc)
    assert row == {"k_work": kw}, (row, counts, wc)
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "bound_kwork: CC_ROUTE_KWORK_LIVE_BOUND=off restores the raw census" {
  CC_ROUTE_KWORK_LIVE_BOUND=off run python3 -c "$(_pre)"'
row = {"k_work": 21}
ca.bound_kwork(row, "a", ca._Census({"a": 2}, headless={"a": 1}), ca._Census({"a": 21}, top={"a": 21}))
assert row == {"k_work": 21}, row
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "concurrency: a headless claude -p is tallied as headless, never as interactive" {
  run python3 -c "$(_pre)"'
import types
cfg = {"accounts": [{"name": "a", "config_dir": "/tmp/cfg-a"}]}
ps_out = ("/opt/bin/claude --model x CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude -p hello CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude --print hi CLAUDE_CONFIG_DIR=/tmp/cfg-a\n"
          "/opt/bin/claude --version CLAUDE_CONFIG_DIR=/tmp/cfg-a\n")
ca.subprocess.run = lambda *a, **k: types.SimpleNamespace(stdout=ps_out)
c = ca.concurrency(cfg)
assert dict(c) == {"a": 1}, dict(c)
assert c.headless == {"a": 2}, c.headless
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
