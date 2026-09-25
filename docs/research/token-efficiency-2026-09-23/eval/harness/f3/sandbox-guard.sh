#!/bin/bash
# sandbox-guard.sh <run-dir> — PreToolUse hook for the F3 gate runs (identical in BOTH arms).
#
# An F3 run works in a real clone of claude-infrastructure, and that repo's tooling reaches past the
# clone: scripts/deploy-live.sh defaults DEPLOY_REPO to the machine's shared checkout, ship-land takes
# a machine-wide land lock, and cc-backlog / cc-decide / cc-custody / cc-notify write the operator's
# real stores. This hook denies exactly those reaches, plus any Edit/Write outside the run dir and
# /tmp, so a run can only change its own clone and its own private origin. Everything else passes.
# F4 runs (harness/run.sh with GATE_GUARD set) use the same hook, identically in both arms.
# It prints a PreToolUse deny on a match and nothing otherwise.
set -u
RUN=${1:?run dir required}
IN=$(cat)

deny() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
    "permissionDecision": "deny", "permissionDecisionReason": sys.argv[1]}}))' "$1"
  exit 0
}

tool=$(printf '%s' "$IN" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
case "$tool" in
  Bash)
    cmd=$(printf '%s' "$IN" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("command",""))' 2>/dev/null)
    if printf '%s' "$cmd" | grep -qE 'ship-land|deploy-live|cc-backlog|cc-decide|cc-custody|cc-notify|cc-signoff|handoff-fire|(^|[^a-z-])cc-do([^a-z-]|$)|migrations/[0-9]{4}-|Development/'; then
      deny "This checkout is an isolated clone: landing, deploying, the shared backlog/decision/notify stores and other checkouts are not reachable from it. Do not retry through another path; say what you would have run and hand it back."
    fi
    # The customer board is readable (next / show / list) but not writable from a gate run.
    if printf '%s' "$cmd" | grep -qE 'cc-mission' && ! printf '%s' "$cmd" | grep -qE 'cc-mission +(next|show|list|status|--help|-h)( |$)'; then
      deny "The mission board is read-only from here (cc-mission next / show / list work). Say what you would change and hand it back."
    fi
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    p=$(printf '%s' "$IN" | python3 -c 'import json,sys; i=json.load(sys.stdin).get("tool_input") or {}; print(i.get("file_path") or i.get("notebook_path") or "")' 2>/dev/null)
    case "$p" in
      "$RUN"/*|/private"$RUN"/*|/tmp/*|/private/tmp/*|"") ;;
      *) deny "This checkout is an isolated clone: files outside it (and outside /tmp) cannot be written from here. Hand the change back instead." ;;
    esac
    ;;
esac
exit 0
