#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# hooks/model-permission-decider.py -- the four safety properties, pinned.
#
# ASSERTION STYLE. bats does not fail a test on a mid-test `[[ ]]`; only a
# simple command's status is caught. So every assertion here is a CALL to a
# helper that returns non-zero, never a bare conditional. Each assertion was
# mutant-verified in BOTH directions against the subject (see the commit body)
# -- an assertion that cannot fail proves nothing.
#
# The model is stubbed via MITL_MODEL_CMD. Where a test's whole point is that
# the model is NOT consulted, the stub records its own invocation to a file and
# the test asserts that file is absent -- absence of a decision is not the same
# as absence of a call, and only the second one is the property.

setup() {
  # Hermetic $HOME -- required by scripts/test-hermeticity-lint.sh, and the
  # subject reads $HOME/.claude/settings.json as its live fence source.
  export BATS_HOME="$BATS_TEST_TMPDIR/home"
  export HOME="$BATS_HOME"
  mkdir -p "$HOME/.claude"
  export MITL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export MITL_MODE=enforce
  export STUB_MARK="$BATS_TEST_TMPDIR/stub-was-called"
  unset CC_MITL_DECIDER MITL_DECIDER_DISABLED

  SUBJECT="${BATS_TEST_DIRNAME}/../hooks/model-permission-decider.py"

  cat >"$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "defaultMode": "auto",
    "ask": ["Bash(fly deploy:*)", "Bash(git push:*)", "Bash(git reset --hard:*)",
            "Bash(git restore:*)", "Bash(git stash clear:*)", "Bash(git stash drop:*)"],
    "deny": ["Bash(sudo:*)", "Bash(rm -rf /)", "Bash(eval:*)"],
    "allow": ["Bash(ls:*)", "Bash(git status:*)"]
  }
}
JSON

  # Default stub: approves everything. Every fence test therefore proves the
  # FENCE held, not that the model happened to agree.
  make_stub ALLOW
}

make_stub() { # $1 = ALLOW | ASK | GARBAGE | SLEEP | RC1
  cat >"$BATS_TEST_TMPDIR/stub.sh" <<EOF
#!/bin/bash
echo called >>"$STUB_MARK"
case "$1" in
  ALLOW)   echo ALLOW; echo "looks routine" ;;
  ASK)     echo ASK; echo "not sure" ;;
  GARBAGE) echo "I think probably it is fine?" ;;
  SLEEP)   sleep 30; echo ALLOW ;;
  RC1)     echo ALLOW; exit 1 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/stub.sh"
  export MITL_MODEL_CMD="bash $BATS_TEST_TMPDIR/stub.sh"
}

run_hook() { # $1 = command string, $2 = tool_name (default Bash)
  local tool="${2:-Bash}"
  local payload
  payload=$(TOOL="$tool" CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": os.environ["TOOL"],
                  "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ.get("BATS_TEST_TMPDIR", "/tmp"),
                  "session_id": "s-test",
                  "transcript_path": "/nonexistent"}))')
  run --separate-stderr python3 "$SUBJECT" <<<"$payload"
}

decision_is() { # $1 = expected permissionDecision
  local got
  got=$(printf '%s' "$output" | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
if not raw:
    print("NONE"); raise SystemExit
try:
    print(json.loads(raw)["hookSpecificOutput"]["permissionDecision"])
except Exception as e:
    print("UNPARSEABLE:" + str(e))')
  if [ "$got" != "$1" ]; then
    echo "expected decision [$1] got [$got]; raw output: $output" >&2
    return 1
  fi
}

stub_not_called() {
  if [ -e "$STUB_MARK" ]; then
    echo "model WAS consulted but must not have been" >&2
    return 1
  fi
}

stub_was_called() {
  if [ ! -e "$STUB_MARK" ]; then
    echo "model was NOT consulted but should have been" >&2
    return 1
  fi
}

# --- fence: the decider may never auto-approve an operator gate -------------

@test "fence: bare git push escalates even when the model approves" {
  run_hook "git push origin main"
  decision_is ask
  stub_not_called
}

@test "fence: git push hidden in a COMPOUND command still escalates" {
  run_hook "cd /tmp && export PATH=/usr/bin && git push origin feature-x"
  decision_is ask
  stub_not_called
}

@test "fence: git push behind a leading VAR= assignment still escalates" {
  run_hook "GIT_SSH_COMMAND=ssh git push origin main"
  decision_is ask
  stub_not_called
}

@test "fence: every operator ask rule is covered, not just git push" {
  for c in "fly deploy --now" "git reset --hard HEAD~1" "git restore src/x.ts" \
           "git stash clear" "git stash drop"; do
    rm -f "$STUB_MARK"
    run_hook "$c"
    decision_is ask
  done
}

@test "fence: a deny-listed command is never auto-approved either" {
  run_hook "sudo systemsetup -setremotelogin on"
  decision_is ask
  stub_not_called
}

@test "fence: indirection is escalated without being resolved" {
  for c in 'cd /tmp && $(printf "git push")' 'echo hi | bash' \
           'sh -c "git push"' 'find . | xargs rm'; do
    rm -f "$STUB_MARK"
    run_hook "$c"
    decision_is ask
    stub_not_called
  done
}

@test "fence: the gate is read LIVE, so a new operator rule arms it with no code change" {
  run_hook "npm publish"
  decision_is allow                      # not gated yet
  python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["ask"].append("Bash(npm publish:*)")
json.dump(d, open(p, "w"))
PY
  rm -f "$STUB_MARK"
  run_hook "npm publish"
  decision_is ask
  stub_not_called
}

@test "fence: an unreadable settings file escalates rather than approving" {
  echo 'not json {' >"$HOME/.claude/settings.json"
  run_hook "echo hello"
  decision_is ask
}

# --- fail direction: always ask, never deny, never allow -------------------

@test "fail direction: a model timeout escalates to the human" {
  make_stub SLEEP
  MITL_DEADLINE_S=2 run_hook "echo hello"
  decision_is ask
}

@test "fail direction: an unparseable model verdict escalates" {
  make_stub GARBAGE
  run_hook "echo hello"
  decision_is ask
}

@test "fail direction: a non-zero model exit escalates" {
  make_stub RC1
  run_hook "echo hello"
  decision_is ask
}

@test "fail direction: budget exhaustion escalates rather than approving" {
  MITL_PER_SESSION_MAX=1 run_hook "echo one"
  decision_is allow
  rm -f "$STUB_MARK"
  MITL_PER_SESSION_MAX=1 run_hook "echo two"
  decision_is ask
  stub_not_called
}

@test "fail direction: deny is unreachable on every path exercised here" {
  for c in "git push origin main" "echo hello" "sudo x" 'a $(b)' "fly deploy"; do
    run_hook "$c"
    if printf '%s' "$output" | grep -q '"deny"'; then
      echo "emitted deny for [$c]: $output" >&2
      return 1
    fi
  done
}

# --- recursion containment -------------------------------------------------

@test "recursion: the sentinel short-circuits before anything else runs" {
  CC_MITL_DECIDER=1 run_hook "git push origin main"
  decision_is NONE
  stub_not_called
}

@test "recursion: the child model call carries the sentinel" {
  cat >"$BATS_TEST_TMPDIR/stub.sh" <<EOF
#!/bin/bash
echo called >>"$STUB_MARK"
echo "\${CC_MITL_DECIDER:-UNSET}" >"$BATS_TEST_TMPDIR/sentinel-seen"
echo ALLOW
EOF
  chmod +x "$BATS_TEST_TMPDIR/stub.sh"
  export MITL_MODEL_CMD="bash $BATS_TEST_TMPDIR/stub.sh"
  run_hook "echo hello"
  local seen
  seen=$(cat "$BATS_TEST_TMPDIR/sentinel-seen" 2>/dev/null || echo MISSING)
  if [ "$seen" != "1" ]; then
    echo "child did not receive CC_MITL_DECIDER=1, got [$seen]" >&2
    return 1
  fi
}

# --- cost: the model is consulted only when it can change the outcome ------

@test "cost: a command the operator already allows costs no model call" {
  run_hook "ls -la"
  decision_is NONE
  stub_not_called
}

@test "cost: a non-Bash tool is not our business" {
  run_hook "irrelevant" "Write"
  decision_is NONE
  stub_not_called
}

@test "cost: a genuinely undecided command IS sent to the model" {
  run_hook "pytest -q tests/"
  decision_is allow
  stub_was_called
}

# --- shadow mode: the default deploys with zero authority ------------------

@test "shadow mode emits no decision even when the model approves" {
  MITL_MODE=shadow run_hook "echo hello"
  decision_is NONE
}

@test "shadow mode still records what it would have decided" {
  MITL_MODE=shadow run_hook "echo hello"
  if ! grep -rq '"decision": *"allow"' "$MITL_STATE_DIR"/decisions-*.jsonl; then
    echo "shadow mode logged nothing; state dir:" >&2
    ls -la "$MITL_STATE_DIR" >&2 || true
    return 1
  fi
}

@test "kill switch disables the decider entirely" {
  MITL_DECIDER_DISABLED=1 run_hook "git push origin main"
  decision_is NONE
  stub_not_called
}

@test "fail direction: a crash inside the decider escalates instead of vanishing" {
  # A hook that writes nothing is indistinguishable from one that timed out --
  # the harness discards it and resumes the normal flow. So a bug in the gate
  # must not be able to silently withdraw the gate.
  cat >"$BATS_TEST_TMPDIR/boom.py" <<'PY'
import runpy, sys, os
sys.argv = [sys.argv[0]]
os.environ["MITL_MODE"] = "enforce"
import importlib.util
spec = importlib.util.spec_from_file_location("subj", os.environ["SUBJECT_PATH"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.fence = lambda cmd: (_ for _ in ()).throw(RuntimeError("synthetic"))
sys.exit(m.guarded_main())
PY
  run --separate-stderr env SUBJECT_PATH="$SUBJECT" python3 "$BATS_TEST_TMPDIR/boom.py" <<<'{"tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"/tmp","session_id":"s","transcript_path":"/nonexistent"}'
  decision_is ask
}
