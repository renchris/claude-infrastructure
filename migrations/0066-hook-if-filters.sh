#!/bin/bash
# migration-class: c10
# migration-step: give pr-gate.sh and relay-verbatim.sh Claude Code `if` filters so they start a process only for the commands they act on, and unregister the inert ship-rail-push-allow.sh PreToolUse hook, in the ONE shared ~/.claude/settings.json (docs/research/load-root-cause-2026-10-17/DESIGN.md X18). It writes settings.json, which is C10; --confirm first runs a live probe of `if` on this machine's claude binary and refuses unless every required spelling fires.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0066-hook-if-filters.sh --confirm settings.json
# migration-verify: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0066-hook-if-filters.sh" --verify
# migration-conflict: bash "${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}/migrations/0066-hook-if-filters.sh" --conflict
# migration-batch-hold: manual — its --confirm starts a live logged-in claude probe the scratch rehearsal cannot sandbox; run its migration-run line alone from a logged-in pane
#
# ══ 0066 — hook `if` filters (load root cause X18, 2026-10-17) ══
# 1. pr-gate.sh (PreToolUse Bash) acts only on `gh pr create` / `gh pr edit`, yet starts a bash on
#    every Bash call. Its entry becomes two, identical but for `"if": "Bash(*gh pr create*)"` and
#    `"if": "Bash(*gh pr edit*)"` (one `if` per entry).
# 2. relay-verbatim.sh (PostToolUse Bash) acts only on its three renderers (hooks/relay-verbatim.sh
#    `case`), so its entry becomes one per renderer, each `"if": "Bash(*<renderer> <flag>*)"`. The
#    leading `*` is what lets a path-prefixed spelling (~/.claude/bin/claude-accounts --readout) match.
# 3. ship-rail-push-allow.sh is unregistered: it can only ALLOW, and an allow from a hook cannot
#    override the `Bash(git push:*)` ask rule, so it never changes an outcome. The script stays.
# Claude Code skips the process when a call does not match `if`, and when it cannot tell which
# commands a Bash input runs it runs the hook anyway (code.claude.com/docs/en/hooks), so the miss
# direction is over-firing, which is today's behaviour. Deny guards are never given an `if`.
#
# THE PROBE (--probe; --confirm runs it first). The agent that wrote this could not run it: auto mode
# refused a headless claude run with a scratch settings file on 2026-10-17. So the operator's own
# apply proves the semantics on the binary that will read the filters. It runs `cc-claude-bin` (or
# $CC_IF_PROBE_CLAUDE) headless in a fresh scratch dir with ONLY a probe settings file: one logging
# hook per `if` pattern, one logger with no `if`, and one hook that DENIES every Bash call, so no
# probed command (gh pr create among them) ever executes. It then requires every pattern to fire on
# its spellings, no `if` logger to fire on `ls`, and the no-`if` logger to have seen every command
# (a command the model never ran is an UNKNOWN, which fails closed). The matrix is printed either way.
# A run that proves nothing is BLIND (rc 3), never a FAIL of the binary: an empty fired.log, a child
# that hit its 240 s bound (rc 124), "Not logged in", or any command the no-`if` logger never saw.
# The c10 batch's scratch HOME has no login, which is why 0066 is held out of the batch (above).
#
# BLAST RADIUS: three hook entries in one file; nothing else changes (verified by content after the
# edit). A pr-gate or relay-verbatim entry that already carries an `if` outside this set, or only part
# of this set, is somebody's decision: REFUSED rc 3, never overwritten. Backed up first; rollback is
# the printed `cp -p` line. Takes effect in NEW sessions.
#
# Usage: bash migrations/0066-hook-if-filters.sh --dry-run | --check | --verify | --conflict | --probe
#        bash migrations/0066-hook-if-filters.sh --confirm settings.json
# Exit: 0 applied / already applied / preflight ok / probe passed · 1 failure or probe failed (nothing
#       written) · 2 usage · 3 REFUSED: an account settings.json is forked (run 0037 first), a
#       different `if` is already set, or the probe was BLIND (nothing written)
# shellcheck disable=SC2016  # every single-quoted string below is a jq program; $x are jq variables
set -uo pipefail

N=0066
RAIL_RE='/ship-rail-push-allow\.sh$'
PR_RE='/pr-gate\.sh$'
RV_RE='/relay-verbatim\.sh$'
PR_IFS='["Bash(*gh pr create*)","Bash(*gh pr edit*)"]'
RV_IFS='["Bash(*claude-accounts*--readout*)","Bash(*operator-readout.sh --render*)","Bash(*cc-do --list*)"]'
f="$HOME/.claude/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
# Through its interpreter, never by path: a #! exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md). Read from its own #! line, so a stub still runs.
_pl=""; IFS= read -r _pl < "$parity" 2>/dev/null || true
case "$_pl" in *python3*) parity_cmd=(/usr/bin/env python3 "$parity") ;; *) parity_cmd=("$parity") ;; esac
command -v jq >/dev/null 2>&1 || { printf '%s: jq required — nothing written\n' "$N" >&2; exit 1; }

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --conflict) mode=conflict ;;
  --probe) mode=probe ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '%s: --confirm must name its target: --confirm settings.json\n' "$N" >&2; exit 2; }
             [ -z "${3:-}" ] || { printf '%s: unknown argument %s after --confirm settings.json\n' "$N" "$3" >&2; exit 2; }
             mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '%s: unknown argument %s (use --dry-run, --check, --verify, --conflict, --probe or --confirm settings.json)\n' "$N" "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '%s: pass --dry-run, --check, --verify, --conflict, --probe or --confirm settings.json\n' "$N" >&2; exit 2; }

# ── the probe ─────────────────────────────────────────────────────────────────────────────────
# Rows are `<label>\t<if pattern>\t<command numbers that must fire it>`; the commands are numbered
# 1-10 in PROBE_CMDS. Over-firing is never a failure, except on `ls` (10), which no `if` may match.
# shellcheck disable=SC2088  # literal command text the probed session types; the ~ must stay unexpanded
PROBE_CMDS=(
  "gh pr create --title if-probe --body x"
  "cd /tmp && gh pr create --title if-probe --body x"
  "bash -c 'gh pr edit 1 --title if-probe'"
  "/opt/homebrew/bin/gh pr create --title if-probe --body x"
  "gh pr edit 1 --title if-probe"
  "~/.claude/bin/claude-accounts --readout"
  "bash ~/.claude/hooks/operator-readout.sh --render"
  "~/.claude/bin/cc-do --list"
  "~/.claude/bin/claude-accounts --fresh --readout"
  "ls"
)
PROBE_ROWS="pr-create	Bash(*gh pr create*)	1 2 4
pr-edit	Bash(*gh pr edit*)	3 5
rv-accounts	Bash(*claude-accounts*--readout*)	6 9
rv-readout	Bash(*operator-readout.sh --render*)	7
rv-cc-do	Bash(*cc-do --list*)	8"

probe() {
  local bin s label pat need c i fired ok=0
  bin="${CC_IF_PROBE_CLAUDE:-}"
  [ -n "$bin" ] || bin="$(cc-claude-bin 2>/dev/null)" || bin=""
  [ -n "$bin" ] && [ -x "$bin" ] || { printf '%s: probe: no claude binary (cc-claude-bin, or set CC_IF_PROBE_CLAUDE)\n' "$N" >&2; return 1; }
  s="$(mktemp -d "${TMPDIR:-/tmp}/if-probe.XXXXXX")" || return 1
  # log.sh <label>: one `<label>\t<command>` row per hook start. deny.sh: blocks every Bash call.
  cat > "$s/log.sh" <<LOG
#!/bin/bash
c="\$(jq -r '.tool_input.command // empty')"
printf '%s\t%s\n' "\$1" "\${c//\$'\n'/ }" >> "$s/fired.log"
exit 0
LOG
  cat > "$s/deny.sh" <<'DENY'
#!/bin/bash
cat >/dev/null
echo "if-probe: blocked by design, nothing runs" >&2
exit 2
DENY
  chmod +x "$s/log.sh" "$s/deny.sh"
  jq -n --arg s "$s" --arg rows "$PROBE_ROWS" '
    ($rows | split("\n") | map(split("\t"))) as $r
    | {hooks: {PreToolUse: [{matcher: "Bash", hooks: (
        [$r[] | {type: "command", command: ($s + "/log.sh " + .[0]), "if": .[1]}]
        + [{type: "command", command: ($s + "/log.sh noif")},
           {type: "command", command: ($s + "/deny.sh")}])}]}}' > "$s/probe-settings.json" || return 1
  local prompt="Run each of the following shell commands with the Bash tool, exactly as written, one command per Bash call, in order. Every call will be blocked by a hook; that is expected, so do not retry or change any command, just move on to the next one. Commands:"
  for i in "${!PROBE_CMDS[@]}"; do prompt="$prompt
$((i + 1)). ${PROBE_CMDS[$i]}"; done
  printf '%s: probe: %s in %s (all Bash calls are denied by a probe hook)\n' "$N" "$("$bin" --version 2>/dev/null | head -1)" "$s"
  # The child is bounded (240 s), detached from any calling session (an inherited CLAUDECODE or
  # CLAUDE_CODE_SESSION_ID binds it to the caller), and runs on the CALLER's account: CLAUDE_CONFIG_DIR
  # is inherited as-is, never pinned to one account dir.
  local rc=0 blind=""
  ( cd "$s" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID timeout 240 "$bin" -p --setting-sources project \
      --settings "$s/probe-settings.json" --allowedTools Bash --max-turns 30 "$prompt" ) > "$s/claude.out" 2>&1 || rc=$?
  : >> "$s/fired.log"
  _fired() { grep -qxF -- "$1	$2" "$s/fired.log"; }   # <label> <command> → it ran that hook
  printf '%-12s %s\n' "spelling" "fired (no-if logger first)"
  for i in "${!PROBE_CMDS[@]}"; do
    c="${PROBE_CMDS[$i]}"; fired=""
    _fired noif "$c" && fired="noif" || { fired="NOT-RUN"; blind="${blind:+$blind; }cmd $((i + 1)) never ran"; }
    while IFS=$'\t' read -r label pat need; do _fired "$label" "$c" && fired="$fired $label"; done <<< "$PROBE_ROWS"
    printf '%-12s %s   ← %s\n' "cmd $((i + 1))" "$fired" "$c"
  done
  # BLIND (rc 3): the run proves nothing about `if`, so it is neither a pass nor a FAIL of the binary.
  [ -s "$s/fired.log" ] || blind="no hook fired at all (empty fired.log)"
  [ "$rc" -eq 124 ] && blind="${blind:+$blind; }the child hit its 240 s bound (rc 124)"
  grep -q 'Not logged in' "$s/claude.out" 2>/dev/null && blind="${blind:+$blind; }claude is not logged in"
  if [ -n "$blind" ]; then
    printf '%s: probe BLIND — %s; nothing about `if` was proven. Transcript: %s/claude.out\n' "$N" "$blind" "$s" >&2
    return 3
  fi
  # FAIL (rc 1) only for a command that RAN and whose `if` did not fire, or an `if` that fired on ls.
  while IFS=$'\t' read -r label pat need; do
    for i in $need; do
      _fired "$label" "${PROBE_CMDS[$((i - 1))]}" \
        || { printf '%s: probe FAIL — %s (%s) did not fire on: %s\n' "$N" "$label" "$pat" "${PROBE_CMDS[$((i - 1))]}" >&2; ok=1; }
    done
    _fired "$label" "ls" && { printf '%s: probe FAIL — %s (%s) fired on ls\n' "$N" "$label" "$pat" >&2; ok=1; }
  done <<< "$PROBE_ROWS"
  [ "$ok" -eq 0 ] && printf '%s: probe PASSED — every filter fires on its spellings and none on ls\n' "$N" \
    || printf '%s: probe did not pass; transcript: %s/claude.out\n' "$N" "$s" >&2
  return "$ok"
}
if [ "$mode" = probe ]; then probe; exit $?; fi

# ── state readers ─────────────────────────────────────────────────────────────────────────────
# Every hook object under one event, wherever its matcher group sits.
HK='[.hooks[$ev][]?.hooks[]? | select((.command // "") | test($re))]'
hooks_of() { jq -c --arg ev "$1" --arg re "$2" "$HK" "$3" 2>/dev/null || echo '[]'; }
rail_gone() { [ "$(hooks_of PreToolUse "$RAIL_RE" "$1" | jq 'length')" = 0 ]; }
# The `if` values on a hook set, as a sorted array (null where an entry has none).
ifs_of() { hooks_of "$1" "$2" "$3" | jq -c 'map(.["if"]) | sort'; }
ifs_done() { [ "$(ifs_of "$1" "$2" "$4")" = "$(jq -cn --argjson w "$3" '$w | sort')" ]; }
# Somebody else's `if`: any value outside the wanted set, or part of the set with an `if`-less entry.
ifs_other() {
  ifs_of "$1" "$2" "$4" | jq -r --argjson w "$3" '
    (map(select(. != null))) as $set
    | if ($set | length) == 0 then empty
      elif ($set - $w | length) > 0 then ($set - $w | join(", "))
      elif ($set | sort) != ($w | sort) or any(.[]; . == null) then "a partial set: " + ($set | join(", "))
      else empty end'
}
applied() { rail_gone "$1" && ifs_done PreToolUse "$PR_RE" "$PR_IFS" "$1" && ifs_done PostToolUse "$RV_RE" "$RV_IFS" "$1"; }

[ -f "$f" ] || { printf '%s: %s not found — nothing written\n' "$N" "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '%s: %s is not valid JSON — nothing written\n' "$N" "$real" >&2; exit 1; }
o_pr="$(ifs_other PreToolUse "$PR_RE" "$PR_IFS" "$real")"
o_rv="$(ifs_other PostToolUse "$RV_RE" "$RV_IFS" "$real")"

case "$mode" in
  verify)
    applied "$f" && { printf '%s: live — %s filters pr-gate and relay-verbatim with `if` and has no ship-rail-push-allow entry\n' "$N" "$f"; exit 0; }
    rail_gone "$f" || printf '%s: NOT live — ship-rail-push-allow.sh is still registered in %s\n' "$N" "$f" >&2
    ifs_done PreToolUse "$PR_RE" "$PR_IFS" "$f" || printf '%s: NOT live — pr-gate.sh `if` set is %s\n' "$N" "$(ifs_of PreToolUse "$PR_RE" "$f")" >&2
    ifs_done PostToolUse "$RV_RE" "$RV_IFS" "$f" || printf '%s: NOT live — relay-verbatim.sh `if` set is %s\n' "$N" "$(ifs_of PostToolUse "$RV_RE" "$f")" >&2
    exit 1 ;;
  conflict)
    rc=1
    [ -n "$o_pr" ] && { printf '%s: overridden — pr-gate.sh carries %s\n' "$N" "$o_pr"; rc=0; }
    [ -n "$o_rv" ] && { printf '%s: overridden — relay-verbatim.sh carries %s\n' "$N" "$o_rv"; rc=0; }
    exit "$rc" ;;
esac

[ "$(hooks_of PreToolUse "$PR_RE" "$real" | jq 'length')" -gt 0 ] 2>/dev/null \
  || { printf '%s: no PreToolUse hook ends in pr-gate.sh in %s — nothing written\n' "$N" "$real" >&2; exit 1; }
[ "$(hooks_of PostToolUse "$RV_RE" "$real" | jq 'length')" -gt 0 ] 2>/dev/null \
  || { printf '%s: no PostToolUse hook ends in relay-verbatim.sh in %s — nothing written\n' "$N" "$real" >&2; exit 1; }
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '%s: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$N" "$f" "$parity" >&2
  exit 3
}
if applied "$real"; then
  printf '%s: already applied — %s filters pr-gate and relay-verbatim and has no ship-rail-push-allow entry\n' "$N" "$real"
  exit 0
fi
if [ -n "$o_pr" ] || [ -n "$o_rv" ]; then
  [ -n "$o_pr" ] && printf '%s: REFUSED — pr-gate.sh already carries %s; somebody chose it, nothing written.\n' "$N" "$o_pr" >&2
  [ -n "$o_rv" ] && printf '%s: REFUSED — relay-verbatim.sh already carries %s; somebody chose it, nothing written.\n' "$N" "$o_rv" >&2
  exit 3
fi
rail_gone "$real" || printf '%s: will unregister ship-rail-push-allow.sh (PreToolUse) in %s\n' "$N" "$real"
ifs_done PreToolUse "$PR_RE" "$PR_IFS" "$real" || printf '%s: will split pr-gate.sh into one entry per `if` in %s\n' "$N" "$PR_IFS"
ifs_done PostToolUse "$RV_RE" "$RV_IFS" "$real" || printf '%s: will split relay-verbatim.sh into one entry per `if` in %s\n' "$N" "$RV_IFS"
case "$mode" in
  dry) printf '%s: DRY RUN — nothing written (the probe runs only under --confirm, or alone as --probe)\n' "$N"; exit 0 ;;
  check) printf '%s: preflight ok — accounts share one file, the edit is well-formed; nothing written\n' "$N"; exit 0 ;;
esac

probe; prc=$?
case "$prc" in
  0) ;;
  3) printf '%s: REFUSED — BLIND, nothing written (the probe ran nothing it could judge; run it from a logged-in pane)\n' "$N" >&2; exit 3 ;;
  *) printf '%s: REFUSED — the `if` probe did not pass on this binary; nothing written\n' "$N" >&2; exit 1 ;;
esac

bdir="$HOME/.claude/backups/hook-if-filters-$N-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '%s: backup FAILED — nothing written\n' "$N" >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
# Expand each `if`-less target entry into one copy per wanted `if`, in place, and drop the rail entry.
EDIT='def fan($re; $ifs): if (.hooks | type) == "array"
        then .hooks |= [.[] | if ((.command // "") | test($re)) and (has("if") | not) then (. + {"if": $ifs[]}) else . end]
        else . end;
      .hooks.PreToolUse |= map(fan($pr; $pri) | if (.hooks | type) == "array" then .hooks |= map(select((.command // "") | test($rail) | not)) else . end)
      | .hooks.PostToolUse |= map(fan($rv; $rvi))'
ARGS=(--arg rail "$RAIL_RE" --arg pr "$PR_RE" --arg rv "$RV_RE" --argjson pri "$PR_IFS" --argjson rvi "$RV_IFS")
if ! jq "${ARGS[@]}" "$EDIT" "$real" > "$tmp" 2>/dev/null || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '%s: jq edit FAILED — nothing written\n' "$N" >&2; exit 1
fi
# Everything else must be byte-for-byte the same JSON: drop the three targets from both sides, compare.
NORM='def norm: .hooks.PreToolUse |= map(if (.hooks | type) == "array" then .hooks |= map(select((.command // "") | (test($rail) or test($pr)) | not)) else . end)
                | .hooks.PostToolUse |= map(if (.hooks | type) == "array" then .hooks |= map(select((.command // "") | test($rv) | not)) else . end);
      ($a[0] | norm) == ($b[0] | norm)'
same_rest=$(jq -n "${ARGS[@]}" --slurpfile a "$real" --slurpfile b "$tmp" "$NORM")
if [ "$same_rest" != true ] || ! applied "$tmp"; then
  rm -f "$tmp"; printf '%s: edit did not verify by content — nothing written\n' "$N" >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '%s: write FAILED — nothing written\n' "$N" >&2; exit 1; }
printf '%s: filters set. Backup: %s/settings.json (restore: cp -p %s/settings.json %s)\n' "$N" "$bdir" "$bdir" "$real"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '%s: WARNING — cc-settings-parity check now fails; restore with the line above\n' "$N" >&2
applied "$f" || { printf '%s: did NOT verify through %s\n' "$N" "$f" >&2; exit 1; }
printf '%s: verified — %s filters pr-gate and relay-verbatim with `if` and no longer registers ship-rail-push-allow. New sessions pick it up.\n' "$N" "$f"
exit 0
