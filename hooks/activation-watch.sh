#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# shellcheck disable=SC2016  # file-wide: the jq program body is intentionally single-quoted ($c = jq var)
# activation-watch.sh — SessionStart: the absence-is-loud re-page for the C10 activation QUEUE (D-v).
#
# Why: the C10 ceiling means agents stage one-action activation scripts into
# ~/.claude/autonomy/pending-activation/ and the OPERATOR runs them — but a staged-but-un-run
# activation is silently-incomplete wiring (P8 sat ~90 min on stated-but-unexecuted verbal intent;
# a17 §3 "make the activation QUEUE absence-is-loud — re-page an un-run activation"). This hook
# surfaces, once per session, every pending-activation script older than N hours with NO matching
# `.done` marker — so an un-run wiring step can't rot unseen. Advisory only (additionalContext);
# never blocks; fail-open. It reads NO session state and mutates nothing.
#
# Convention: an activation `foo-activate.sh` is marked run by an adjacent `foo-activate.sh.done`
# marker (the operator `touch`es it after running). Selftest: `--selftest`.
set -uo pipefail

DIR="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
MAX_AGE_H="${CC_ACTIVATION_MAX_AGE_H:-24}"
MAX_AGE_S=$(( MAX_AGE_H * 3600 ))
JQ="$(command -v jq || true)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

emit() { # <context-string> — SessionStart additionalContext (JSON form, matching session-start.sh)
  if [ -n "$JQ" ]; then
    "$JQ" -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
  else
    printf '%s\n' "$1"   # SessionStart also injects plain stdout as context (frontier-status precedent)
  fi
}

watch() {
  [ -d "$DIR" ] || exit 0
  local now f mt stale=()
  now="$(date +%s)"
  for f in "$DIR"/*.sh; do
    [ -f "$f" ] || continue
    [ -f "$f.done" ] && continue                 # already run (operator touched the marker)
    mt="$(stat -f %m "$f" 2>/dev/null || echo "$now")"
    [ $(( now - mt )) -ge "$MAX_AGE_S" ] && stale+=("$(basename "$f")")
  done
  [ "${#stale[@]}" -eq 0 ] && exit 0
  local names; names="$(printf '%s, ' "${stale[@]}")"; names="${names%, }"
  emit "ACTIVATION QUEUE (absence-is-loud, D-v): ${#stale[@]} pending-activation script(s) staged >${MAX_AGE_H}h and NOT run — ${names}. These are C10 operator hand-steps (agent stages, operator runs): review + run ${DIR}/<name>, then \`touch ${DIR}/<name>.done\`. An un-run activation is silently-incomplete wiring."
  exit 0
}

# ════ selftest — stale-unrun named · fresh-unrun skipped · done-marked skipped · absent-dir silent ══
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d out; d="$(mktemp -d "${TMPDIR:-/tmp}/activation-watch-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  local old; old="$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo 200001010000.00)"
  echo "activation-watch --selftest:"

  mkdir -p "$d/q"
  printf '#!/bin/bash\n' > "$d/q/stale-activate.sh";  touch -t "$old" "$d/q/stale-activate.sh"
  printf '#!/bin/bash\n' > "$d/q/fresh-activate.sh"                                   # mtime = now
  printf '#!/bin/bash\n' > "$d/q/done-activate.sh";   touch -t "$old" "$d/q/done-activate.sh"; : > "$d/q/done-activate.sh.done"

  out="$(CC_ACTIVATION_DIR="$d/q" CC_ACTIVATION_MAX_AGE_H=24 "$SELF")"
  printf '%s' "$out" | grep -q 'stale-activate.sh' && okp "stale un-run script is named" || badp "stale un-run NOT named"
  printf '%s' "$out" | grep -q 'fresh-activate.sh' && badp "fresh script wrongly named" || okp "fresh (<24h) script NOT named"
  printf '%s' "$out" | grep -q 'done-activate.sh'  && badp ".done-marked script wrongly named" || okp ".done-marked script NOT named"
  printf '%s' "$out" | grep -q 'ACTIVATION QUEUE'  && okp "emits the absence-is-loud line" || badp "no activation-queue line"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null 2>&1 \
      && okp "output is valid SessionStart additionalContext JSON" || badp "output not valid SessionStart JSON"
  else okp "jq absent — plain-stdout fallback (skipped JSON check)"; fi

  # only fresh + done → NO output, exit 0
  mkdir -p "$d/clean"
  printf '#!/bin/bash\n' > "$d/clean/fresh.sh"
  out="$(CC_ACTIVATION_DIR="$d/clean" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "no stale scripts → silent, exit 0" || badp "spurious output on a clean queue"

  # absent dir → silent, exit 0
  out="$(CC_ACTIVATION_DIR="$d/does-not-exist" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "absent queue dir → silent, exit 0 (fail-open)" || badp "absent dir not tolerated"

  echo "activation-watch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "activation-watch --selftest: GREEN — stale named, fresh/done/absent all skip, valid SessionStart JSON."
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          watch ;;
esac
