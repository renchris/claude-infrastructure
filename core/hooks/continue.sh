#!/bin/bash
# continue.sh — Stop hook: keep working on an armed "next step" instead of stopping.
#
# The model arms it when it stops with in-scope work left:
#   ~/.claude/autonomy-core/bin/autonomy continue set "<the one next step>"
# and every Stop after that is turned into another turn whose prompt is that step, until the model
# clears it (`autonomy continue clear`) or the cap is reached (AUTONOMY_CONTINUE_MAX, default 8).
# Re-arming with `set` resets the count, so a long job can chain; the cap bounds a stuck loop.
#
# The sentinel is keyed on the session id when Claude Code exports one, else on the working
# directory, so two sessions in two directories never drive each other.
# Kill switch: AUTONOMY_CORE_CONTINUE=off. This hook always exits 0; it blocks only via JSON.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
dir="$AC_STATE/continue"
mkdir -p "$dir" 2>/dev/null

# ---- CLI: set | clear | status (run from the model's Bash tool) ----
case "${1:-}" in
  set|clear|status)
    sid="${CLAUDE_CODE_SESSION_ID:-}"
    if [ -n "$sid" ]; then f="$dir/sid-$(ac_key "$sid")"; else f="$dir/cwd-$(ac_key "$PWD")"; fi
    case "$1" in
      set)
        printf '%s' "${2:-Continue the in-scope work.}" > "$f"
        rm -f "$f.count"
        echo "armed: the next stop continues with: ${2:-Continue the in-scope work.}" ;;
      clear)
        rm -f "$f" "$f.count" "$dir/cwd-$(ac_key "$PWD")" "$dir/cwd-$(ac_key "$PWD").count"
        echo "cleared: stops are no longer auto-continued here" ;;
      status)
        if [ -f "$f" ]; then echo "armed ($(cat "$f.count" 2>/dev/null || echo 0)/${AUTONOMY_CONTINUE_MAX:-8}): $(cat "$f")"
        else echo "not armed"; fi ;;
    esac
    exit 0 ;;
esac

# ---- Stop hook ----
[ "${AUTONOMY_CORE_CONTINUE:-on}" = off ] && exit 0
input="$(cat)"
sid="$(ac_json_get "$input" session_id)"
cwd="$(ac_json_get "$input" cwd)"
f=""
if [ -n "$sid" ] && [ -f "$dir/sid-$(ac_key "$sid")" ]; then f="$dir/sid-$(ac_key "$sid")"
elif [ -n "$cwd" ] && [ -f "$dir/cwd-$(ac_key "$cwd")" ]; then f="$dir/cwd-$(ac_key "$cwd")"
fi
[ -n "$f" ] || exit 0

max="${AUTONOMY_CONTINUE_MAX:-8}"
n="$(cat "$f.count" 2>/dev/null || echo 0)"
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" -ge "$max" ]; then
  step="$(cat "$f")"
  rm -f "$f" "$f.count"
  printf '{"systemMessage":%s}\n' "$(ac_json_str "autonomy-core: auto-continue stopped after $max turns on: $step")"
  exit 0
fi
n=$((n + 1))
printf '%s' "$n" > "$f.count"
ac_block "Auto-continue ($n/$max): $(cat "$f")

Keep working on it. When it is finished, blocked on a decision only the user can make, or out of scope, run: $AC_HOME/bin/autonomy continue clear
Re-arm with a new next step (\`$AC_HOME/bin/autonomy continue set \"...\"\`) if more in-scope work remains."
exit 0
