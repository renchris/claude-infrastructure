#!/bin/bash
# shellcheck disable=SC2016  # file-wide: jq program bodies are single-quoted ($x = jq var, not shell)
# shellcheck disable=SC2015  # file-wide: the selftest's `cmd && okp || badp` reporter idiom
# shellcheck disable=SC2088  # file-wide: a `~/...` hook command is LITERAL settings.json content —
#   Claude Code expands it at hook-exec time; expanding it here would write a machine-absolute path
# settings-hook-timeouts.sh — set a hook entry's `timeout`, or ensure a hook is wired under an
# event/matcher, in a settings.json. The scripted + reversible complement to hand-editing live config.
#
# Why (audit 09 D-5 / D-14): the heaviest per-tool-call hook, `waiting-recycle.sh` (795 lines,
# fires on EVERY Bash call, one of only two hooks that can emit {decision:"block"} from a non-Stop
# event), carried NO `timeout` key in any of the five config dirs — a hung git/transcript read had
# no ceiling. Same for `keychain-guard.sh`. And `PreCompact` was asymmetric: `dod-persist.sh` was
# wired on matcher:auto only, so a MANUAL /compact never persisted the frozen DoD.
#
# Both operations are IDEMPOTENT and NARROW by construction:
#   --set-timeout  touches only hooks[] entries whose command CONTAINS the given substring, and
#                  only within the named event. Entries that already carry that exact timeout are
#                  left byte-identical.
#   --ensure       adds a command to the object with the EXACT given matcher, and only if no entry
#                  there already resolves to the same hook (basename+args, the same normalization
#                  settings-dedup-stop.sh uses). It never creates an event or a matcher object that
#                  does not already exist — a typo'd matcher is an error, not a silent new object.
# Dry-run is the default. --apply backs up to <file>.timeouts.bak first, validates the result
# parses AND still has .hooks, and only then replaces the file.
#
# Usage:
#   settings-hook-timeouts.sh --event <E> --set-timeout <cmd-substring> --timeout <N> [--apply] <settings.json>...
#   settings-hook-timeouts.sh --event <E> --matcher <M> --ensure <command> --timeout <N> [--apply] <settings.json>...
#   settings-hook-timeouts.sh --selftest
#     --matcher accepts the literal matcher string; use --matcher-null for a matcher-less object.
# Exit: 0 ok · 2 bad arg · 3 environment error (no jq / missing file / jq failure / no such
#       event+matcher). --selftest: 0/1.
set -uo pipefail

JQ="$(command -v jq || true)"

usage() {
  sed -n '2,999p' "$0" | sed -n 's/^# \{0,1\}//p' | sed -n '/^Usage:/,/^      /p'
}

# ── set-timeout: within $ev, every hooks[] entry whose .command contains $sub gets .timeout = $to ──
JQ_SET='
  def touch: if ((.command // "") | contains($sub)) then .timeout = $to else . end;
  .hooks[$ev] = [ (.hooks[$ev] // [])[] | .hooks = [ (.hooks // [])[] | touch ] ]
'

# ── ensure: append $cmd (timeout $to) to the object of $ev whose matcher == $m, unless an entry
#    there already normalizes to the same hook. $mnull=true targets the matcher-less object. ──
JQ_ENSURE='
  def normcmd:
    (index(" ")) as $sp
    | (if $sp == null then . else .[0:$sp] end) as $first
    | (if $sp == null then "" else .[$sp:] end) as $rest
    | (($first | split("/")) | last) + $rest;
  def is_target: if $mnull then (.matcher == null) else ((.matcher // null) == $m) end;
  ($cmd | normcmd) as $want
  | .hooks[$ev] = [ (.hooks[$ev] // [])[]
      | if (is_target and ([ (.hooks // [])[] | (.command // "") | normcmd ] | index($want)) == null)
        then .hooks = ((.hooks // []) + [ {type:"command", command:$cmd, timeout:$to} ])
        else . end ]
'

# count how many hooks[] entries the target selection currently matches (0 ⇒ nothing to do / bad arg)
JQ_COUNT_SET='[ (.hooks[$ev] // [])[] | (.hooks // [])[] | select((.command // "") | contains($sub)) ] | length'
JQ_COUNT_SET_NEEDED='[ (.hooks[$ev] // [])[] | (.hooks // [])[]
  | select((.command // "") | contains($sub)) | select((.timeout // null) != $to) ] | length'
JQ_COUNT_MATCHER='[ (.hooks[$ev] // [])[] | select(if $mnull then (.matcher == null) else ((.matcher // null) == $m) end) ] | length'

# write_result <file> <new-json> <label> — validate, back up, replace. Returns 0 ok / 3 refused.
write_result() {
  local f="$1" new="$2" label="$3"
  if [ -z "$new" ] || ! printf '%s' "$new" | "$JQ" -e '.hooks' >/dev/null 2>&1; then
    printf 'settings-hook-timeouts: refusing to write — result malformed for %s\n' "$f" >&2
    return 3
  fi
  cp "$f" "$f.timeouts.bak" || return 3
  printf '%s\n' "$new" > "$f.tmp" && mv "$f.tmp" "$f" || return 3
  printf '  APPLY  %s — %s; backup: %s\n' "$f" "$label" "$f.timeouts.bak"
  return 0
}

do_set_timeout() { # <file>
  local f="$1" n needed new
  n="$("$JQ" --arg ev "$EVENT" --arg sub "$SUBSTR" "$JQ_COUNT_SET" "$f" 2>/dev/null)" || return 3
  if [ "${n:-0}" -eq 0 ]; then
    printf 'settings-hook-timeouts: no %s hook command contains "%s" in %s\n' "$EVENT" "$SUBSTR" "$f" >&2
    return 3
  fi
  needed="$("$JQ" --arg ev "$EVENT" --arg sub "$SUBSTR" --argjson to "$TIMEOUT" "$JQ_COUNT_SET_NEEDED" "$f" 2>/dev/null)" || return 3
  if [ "${needed:-0}" -eq 0 ]; then
    printf '  clean  %s — %s/%s already at timeout %s (%s match)\n' "$f" "$EVENT" "$SUBSTR" "$TIMEOUT" "$n"
    return 0
  fi
  printf '  SET    %s %s [*%s*] timeout → %s (%s entr(y|ies))\n' "$f" "$EVENT" "$SUBSTR" "$TIMEOUT" "$needed"
  $APPLY || { printf '  (dry-run — pass --apply to write)\n'; return 0; }
  new="$("$JQ" --arg ev "$EVENT" --arg sub "$SUBSTR" --argjson to "$TIMEOUT" "$JQ_SET" "$f" 2>/dev/null)" || return 3
  write_result "$f" "$new" "timeout $TIMEOUT on $needed $EVENT entr(y|ies) matching *$SUBSTR*"
}

do_ensure() { # <file>
  local f="$1" nm before after new
  nm="$("$JQ" --arg ev "$EVENT" --arg m "$MATCHER" --argjson mnull "$MNULL" "$JQ_COUNT_MATCHER" "$f" 2>/dev/null)" || return 3
  if [ "${nm:-0}" -eq 0 ]; then
    printf 'settings-hook-timeouts: no %s object with matcher %s in %s (never created here)\n' \
      "$EVENT" "$($MNULL && printf '<null>' || printf '"%s"' "$MATCHER")" "$f" >&2
    return 3
  fi
  before="$("$JQ" --arg ev "$EVENT" '[ (.hooks[$ev] // [])[] | (.hooks // [])[] ] | length' "$f" 2>/dev/null)" || return 3
  new="$("$JQ" --arg ev "$EVENT" --arg m "$MATCHER" --argjson mnull "$MNULL" \
         --arg cmd "$COMMAND" --argjson to "$TIMEOUT" "$JQ_ENSURE" "$f" 2>/dev/null)" || return 3
  after="$(printf '%s' "$new" | "$JQ" --arg ev "$EVENT" '[ (.hooks[$ev] // [])[] | (.hooks // [])[] ] | length')" || return 3
  if [ "$before" -eq "$after" ]; then
    printf '  clean  %s — %s already wired under that matcher\n' "$f" "$COMMAND"
    return 0
  fi
  printf '  WIRE   %s %s matcher=%s + [%s] timeout=%s\n' "$f" "$EVENT" \
    "$($MNULL && printf '<null>' || printf '%s' "$MATCHER")" "$COMMAND" "$TIMEOUT"
  $APPLY || { printf '  (dry-run — pass --apply to write)\n'; return 0; }
  write_result "$f" "$new" "wired $COMMAND under $EVENT/${MATCHER}"
}

# ════ selftest — RED-prove both operations end-to-end via the real CLI on fixture files ═════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-58s\n' "$1"; PASS=$((PASS + 1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-58s\n' "$1"; FAIL=$((FAIL + 1)); }
# shellcheck disable=SC2317
selftest() {
  local d out
  d="$(mktemp -d "${TMPDIR:-/tmp}/settings-hook-timeouts-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  echo "settings-hook-timeouts --selftest:"

  # the live shape: PostToolUse/Bash has log-bash (timeout 5) + waiting-recycle (NO timeout)
  mklive() {
    "$JQ" -n '{hooks:{PostToolUse:[
        {matcher:"Bash",hooks:[
          {type:"command",command:"~/.claude/hooks/log-bash.sh",timeout:5},
          {type:"command",command:"~/.claude/hooks/waiting-recycle.sh"}]}],
      PreCompact:[
        {matcher:"auto",hooks:[
          {type:"command",command:"date >> log"},
          {type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:10}]},
        {matcher:"manual",hooks:[
          {type:"command",command:"date >> log"}]}]}}' > "$1"
  }

  # ── --set-timeout ──
  mklive "$d/a.json"
  out="$("$SELF" --event PostToolUse --set-timeout waiting-recycle --timeout 30 "$d/a.json")"
  printf '%s' "$out" | grep -q 'SET ' && okp "dry-run reports the timeout it would set" || badp "dry-run did not report"
  [ "$("$JQ" '.hooks.PostToolUse[0].hooks[1] | has("timeout")' "$d/a.json")" = "false" ] \
    && okp "dry-run leaves the file untouched" || badp "dry-run mutated the file"
  "$SELF" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$d/a.json" >/dev/null
  [ "$("$JQ" '.hooks.PostToolUse[0].hooks[1].timeout' "$d/a.json")" = "30" ] \
    && okp "--apply sets the timeout on the matching entry" || badp "timeout not set"
  [ "$("$JQ" '.hooks.PostToolUse[0].hooks[0].timeout' "$d/a.json")" = "5" ] \
    && okp "a NON-matching sibling entry keeps its own timeout" || badp "clobbered a sibling timeout"
  [ -f "$d/a.json.timeouts.bak" ] && okp "--apply writes a .timeouts.bak backup" || badp "no backup written"
  "$SELF" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$d/a.json" | grep -q 'clean' \
    && okp "--set-timeout is idempotent (second run is a clean no-op)" || badp "not idempotent"
  "$SELF" --event PostToolUse --set-timeout nosuchhook --timeout 9 "$d/a.json" >/dev/null 2>&1
  [ "$?" -eq 3 ] && okp "an unmatched substring is exit 3, never a silent no-op" || badp "unmatched substring not an error"

  # ── --ensure ──
  mklive "$d/b.json"
  out="$("$SELF" --event PreCompact --matcher manual --ensure '~/.claude/hooks/dod-persist.sh' --timeout 10 "$d/b.json")"
  printf '%s' "$out" | grep -q 'WIRE ' && okp "dry-run reports the hook it would wire" || badp "ensure dry-run did not report"
  [ "$("$JQ" '.hooks.PreCompact[1].hooks | length' "$d/b.json")" -eq 1 ] \
    && okp "ensure dry-run leaves the file untouched" || badp "ensure dry-run mutated the file"
  "$SELF" --event PreCompact --matcher manual --ensure '~/.claude/hooks/dod-persist.sh' --timeout 10 --apply "$d/b.json" >/dev/null
  [ "$("$JQ" '.hooks.PreCompact[1].hooks | length' "$d/b.json")" -eq 2 ] \
    && okp "--apply wires the hook onto the named matcher" || badp "hook not wired"
  [ "$("$JQ" -r '.hooks.PreCompact[1].hooks[1].command' "$d/b.json")" = "~/.claude/hooks/dod-persist.sh" ] \
    && okp "the wired command is exactly what was asked for" || badp "wrong command wired"
  [ "$("$JQ" '.hooks.PreCompact[0].hooks | length' "$d/b.json")" -eq 2 ] \
    && okp "the sibling matcher:auto object is untouched" || badp "touched the wrong matcher object"
  "$SELF" --event PreCompact --matcher manual --ensure '~/.claude/hooks/dod-persist.sh' --timeout 10 --apply "$d/b.json" | grep -q 'clean' \
    && okp "--ensure is idempotent (second run is a clean no-op)" || badp "ensure not idempotent"
  "$SELF" --event PreCompact --matcher auto --ensure '/abs/path/dod-persist.sh' --timeout 10 --apply "$d/b.json" | grep -q 'clean' \
    && okp "a different path spelling of an already-wired hook is NOT re-added" || badp "re-added under another spelling"
  "$SELF" --event PreCompact --matcher typo --ensure '~/x.sh' --timeout 5 "$d/b.json" >/dev/null 2>&1
  [ "$?" -eq 3 ] && okp "a matcher that does not exist is exit 3, never a new object" || badp "created a matcher object"

  echo "settings-hook-timeouts --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "settings-hook-timeouts --selftest: GREEN — narrow, idempotent, backed up, never invents an event/matcher."
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

[ -n "$JQ" ] || { printf 'settings-hook-timeouts: jq required\n' >&2; exit 3; }

APPLY=false; MNULL=false; MODE=""
EVENT=""; MATCHER=""; SUBSTR=""; COMMAND=""; TIMEOUT=""
declare -a FILES=()
need() { [ $# -ge 2 ] || { printf 'settings-hook-timeouts: %s needs a value\n' "$1" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true ;;
    --event) need "$@"; shift; EVENT="$1" ;;
    --matcher) need "$@"; shift; MATCHER="$1" ;;
    --matcher-null) MNULL=true ;;
    --set-timeout) need "$@"; shift; SUBSTR="$1"; MODE="set" ;;
    --ensure) need "$@"; shift; COMMAND="$1"; MODE="ensure" ;;
    --timeout) need "$@"; shift; TIMEOUT="$1" ;;
    --selftest) selftest; exit $? ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done; break ;;
    -*) printf 'settings-hook-timeouts: unknown arg %s\n' "$1" >&2; exit 2 ;;
    *) FILES+=("$1") ;;
  esac
  shift
done

[ -n "$MODE" ]  || { printf 'settings-hook-timeouts: need --set-timeout or --ensure\n' >&2; usage >&2; exit 2; }
[ -n "$EVENT" ] || { printf 'settings-hook-timeouts: --event is required\n' >&2; exit 2; }
case "$TIMEOUT" in ''|*[!0-9]*) printf 'settings-hook-timeouts: --timeout needs a non-negative integer\n' >&2; exit 2 ;; esac
[ "${#FILES[@]}" -gt 0 ] || { printf 'settings-hook-timeouts: no settings.json path given\n' >&2; exit 2; }
if [ "$MODE" = ensure ] && [ -z "$MATCHER" ] && ! $MNULL; then
  printf 'settings-hook-timeouts: --ensure needs --matcher <M> or --matcher-null\n' >&2; exit 2
fi

rc=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then printf 'settings-hook-timeouts: no such file: %s\n' "$f" >&2; rc=3; continue; fi
  if ! "$JQ" -e . "$f" >/dev/null 2>&1; then
    printf 'settings-hook-timeouts: %s is not valid JSON — refusing to touch it\n' "$f" >&2; rc=3; continue
  fi
  case "$MODE" in
    set)    do_set_timeout "$f" || rc=$? ;;
    ensure) do_ensure "$f" || rc=$? ;;
  esac
done
exit "$rc"
