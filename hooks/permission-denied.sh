#!/bin/bash
# permission-denied.sh — the REFUSAL LEDGER, one line per denied tool call (HOOK_SURFACE_100P § 3
# row 17, W3-D).
#
# WHY THIS EVENT AND NOTHING ELSE. `PermissionDenied` is the only hook that observes an OUTCOME of
# `deny`. `PreToolUse` sees the same call and returns before the decision exists; `PostToolUse` and
# `PostToolUseFailure` never fire on a denial at all, because no tool ran. So a refusal is, today,
# invisible to every hook the fleet owns — 105 real auto-mode classifier denials sit in the
# transcript corpus that no hook of ours has ever seen. This handler is what makes a refusal an
# EVENT instead of something a later reader has to scrape out of a transcript. It fires on BOTH
# binaries (2.1.114 and 2.1.220 — § 3 row 17), so nothing here is version-conditional.
#
# 🚨 THE ADOPTION CONSTRAINT THAT SHAPES EVERY LINE: THIS HOOK MUST EMIT NOTHING ON STDOUT.
# The event's `hookSpecificOutput` schema is `{hookEventName:"PermissionDenied", retry:boolean}`,
# and **`retry:true` RE-OFFERS THE DENIED CALL**. A stray `echo` on this path does not produce a
# cosmetic defect — it silently re-drives work the classifier just refused. There is therefore no
# writer to stdout anywhere below: every byte this script produces goes to the log FILE, the
# abstain marker goes to the same file, and `tests/permission-denied.bats` asserts empty stdout on
# every one of the handler's paths rather than trusting that property to remain true by accident.
# (No `exec 1>/dev/null` guard is installed: with no writer it would be un-falsifiable dead code,
# which is exactly what the W3-C mutation sweep deleted from the sibling handler. The contract is
# held by the suite, which CAN go red.)
#
# ⚠️ ITS MATCHER IS A TOOL NAME. This event goes through the same `preparePermissionMatcher` path
# as PreToolUse/PostToolUse, so a registration's `matcher` selects by TOOL, not by anything in the
# reason. Register it matcher-less (or `*`) to get the whole refusal ledger; a tool-scoped
# registration silently narrows the population and no reader can tell that from a quiet week.
#
# MEASURED PAYLOAD (2.1.220 · headless `-p` · `--permission-mode auto`, /tmp/hs/log/permdenied.tsv,
# W1 — the fields, verbatim):
#   {session_id, transcript_path, cwd, permission_mode, hook_event_name:"PermissionDenied",
#    tool_name, tool_input, tool_use_id, reason}
#   There is NO `prompt_id` and NO `effort` in any of the four captured rows, so a reader must not
#   key on them. `reason` is the classifier's own prose sentence, not a code.
#
# WHY `tool_input` IS DIGESTED AND NEVER STORED WHOLE. `tool_input` is the denied call's arguments,
# and for Write/Edit that is an entire file body. An unbounded copy of it in a log is both a size
# defect and a content hazard (the refused payload is the thing someone decided not to run). The row
# carries the LENGTH plus a bounded head, which is enough to identify the call and never enough to
# replay it.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e`. Empty stdin, malformed JSON, a wrong event name, an absent
# jq, an unwritable log — every one of them exits 0 having emitted nothing. A hook on the permission
# path must never be able to change the outcome of a permission decision.
#
# Env seams (tests): PERMISSION_DENIED_LOG · PERMISSION_DENIED_MAX_BYTES ·
#                    PERMISSION_DENIED_REASON_CHARS · PERMISSION_DENIED_INPUT_CHARS
# Kill switch: CC_PERMISSION_DENIED_DISABLED=1 (inert, exit 0, no row — the operability escape
#              hatch every fleet hook carries; see hooks/cc-permission-beacon.sh for the naming).
set -uo pipefail

[ "${CC_PERMISSION_DENIED_DISABLED:-0}" = "1" ] && exit 0

LOG="${PERMISSION_DENIED_LOG:-$HOME/.claude/logs/permission-denied.jsonl}"
MAX_BYTES="${PERMISSION_DENIED_MAX_BYTES:-4194304}"     # 4 MiB, one generation kept
REASON_CHARS="${PERMISSION_DENIED_REASON_CHARS:-400}"   # the classifier's sentences run ~120-200
INPUT_CHARS="${PERMISSION_DENIED_INPUT_CHARS:-300}"
case "$MAX_BYTES"    in ''|*[!0-9]*) MAX_BYTES=4194304 ;; esac
case "$REASON_CHARS" in ''|*[!0-9]*) REASON_CHARS=400 ;; esac
case "$INPUT_CHARS"  in ''|*[!0-9]*) INPUT_CHARS=300 ;; esac

# Builtin read, NOT `$(cat)`: a command substitution forks AND execs /bin/cat. `read -d ''` returns
# non-zero at EOF — the normal case — hence `|| true`.
IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0                               # missing args / empty stdin ⇒ inert

LOGDIR="${LOG%/*}"
ensure_dir() { [ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null || true; }

abstain() { # <reason> — a blind ledger must be distinguishable from an empty one (idl-abstain law)
  local ts
  ensure_dir
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')"
  printf '{"ts":"%s","hook":"permission-denied","abstain":"%s"}\n' "$ts" "$1" >> "$LOG" 2>/dev/null || true
  exit 0
}

command -v jq >/dev/null 2>&1 || abstain "no-jq"

# ONE jq call: the event gate, the digest, the timestamp and the row. The event-name gate is the
# only thing that makes a mis-registration INERT rather than WRONG — pointed at PreToolUse (whose
# payload carries tool_name and tool_input too, so no shape gate could tell them apart) this handler
# would otherwise mint a "denial" for every single tool call. That gate has its own arm in the suite
# precisely because no other assertion exercises it.
ROW="$(printf '%s' "$INPUT" | jq -c --argjson rc "$REASON_CHARS" --argjson ic "$INPUT_CHARS" '
    select(.hook_event_name == "PermissionDenied")
  | (.tool_input // null | if . == null then "" else tojson end) as $ti
  | { ts:          (now | todate),
      hook:        "permission-denied",
      sid:         (.session_id // "-"),
      tool:        (.tool_name  // "-"),
      tool_use_id: (.tool_use_id // "-"),
      mode:        (.permission_mode // "-"),
      reason:      ((.reason // "-") | tostring | .[0:$rc]),
      input_chars: ($ti | length),
      input_head:  ($ti | .[0:$ic]),
      cwd:         (.cwd // "-"),
      transcript:  (.transcript_path // "-") }
' 2>/dev/null)" || ROW=""

# Nothing to say is legitimate for the event gate — that IS what inertness looks like, and marking
# it would turn a mis-registration on a live event into a marker per tool call, the very flood the
# gate exists to prevent. Unparseable input is the one anomaly worth a marker.
if [ -z "$ROW" ]; then
  if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then abstain "malformed-json"; fi
  exit 0
fi
case "$ROW" in '{'*) ;; *) exit 0 ;; esac          # never append anything that is not an object line

# HOOK_CHAIN_COST R-5: bash-execution.log is unbounded and that is a live defect. Do not mint a
# second one. Single-generation rotation, checked BEFORE the append.
ensure_dir
SIZE="$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
if [ "$SIZE" -ge "$MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi

printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
exit 0
