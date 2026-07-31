#!/bin/bash
# cc-permission-beacon.sh — the PermissionRequest BEACON for lead-supervisor.sh (desk-anti-hitl §B2).
#
# WHY: an UNATTENDED autonomous session that hits a permission prompt HANGS until a human answers
# (the 133-min `git reset --hard` incident, desk-anti-hitl-2026-07-19.md §B). Nothing IN-session can
# answer the prompt, and the out-of-session supervisor is STRUCTURALLY blind to modal/permission
# dialogs (lead-supervisor.sh S-3 — a bash sweep cannot read a modal). Today that block only surfaces
# ~30 min later as a generic STALL?/MODAL page with no detail; resolution took 2h13m.
#
# THIS beacon makes the block VISIBLE, ATTRIBUTED, and FAST: on a permission prompt the HARNESS (not a
# worker) writes an unspoofable record {ts, tool_name, tool_input, cwd} to CC_PERMPEND_DIR/<sid>.json.
# lead-supervisor.sh's sweep reads the dir and pages "PERMISSION-PENDING: <cmd> since <ts>" within
# minutes, with the exact blocked command attached — a precise escalation instead of a silent hang.
#
# CONTRACT (mode = $1, from the hook wiring):
#   write  — PermissionRequest event: the harness is showing a permission prompt ⇒ persist the beacon.
#   clear  — PostToolUse | Stop | SessionEnd: the prompt is RESOLVED ⇒ remove the beacon.
#
# WHY THE CLEARS ARE COMPLETE (no missed-clear leak, and no dependence on a PermissionDenied event —
# this harness has none):
#   • A permission prompt is ALWAYS mid-turn — the turn cannot Stop until the human answers. So the
#     turn's Stop fires after EVERY resolution, GRANT or DENY, guaranteeing a clear even on the deny
#     path (which never runs PostToolUse). Stop is the universal clearer.
#   • PostToolUse is the FASTER clear on the grant path (fires the instant the tool runs, before the
#     turn ends), narrowing the stale window.
#   • SessionEnd is the backstop for a session that closes without a Stop.
#   • A hard-killed session (kill -9 / OOM, no SessionEnd) cannot strand a forever-pending beacon:
#     the supervisor independently REAPS a beacon whose owning session is provably dead (pid gone via
#     telemetry) and any beacon past a long orphan horizon.
#
# SAFETY: the payload is HARNESS-AUTHORED (session_id/tool_name/tool_input/cwd arrive on the hook's
# stdin from the harness, NOT worker-influenced content) ⇒ unspoofable. This hook is a pure OBSERVER:
# it emits NO permission decision, so the prompt proceeds exactly as before. Fail-open + fail-quiet:
# any parse/IO error exits 0 with no decision and no partial file.
#
# Kill switch: CC_PERMISSION_BEACON_DISABLED=1  (no-op, both modes).
# Seams: CC_PERMPEND_DIR (default /tmp/cc-permission-pending) — MUST match lead-supervisor.sh; E2E
#        isolation. CC_PERMARCHIVE_DIR / CC_PERMARCHIVE_MAXLEN — the durable archive (see `archive`).

[[ "${CC_PERMISSION_BEACON_DISABLED:-0}" == "1" ]] && exit 0
set -uo pipefail

MODE="${1:-}"
DIR="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"
# Durable ARCHIVE (see the `archive` function below). Deliberately NOT under CC_PERMPEND_DIR:
# that lives in /tmp and is wiped on reboot, and the whole point of the archive is a record that
# outlives the box's uptime so the classifier can be tuned on weeks of real data.
ARCHDIR="${CC_PERMARCHIVE_DIR:-$HOME/.claude/autonomy/permission-archive}"
ARCH_MAXLEN="${CC_PERMARCHIVE_MAXLEN:-3500}"

# Read the harness payload once (fail-open on empty/malformed — never block the prompt).
INPUT="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -z "$SID" ]] && exit 0                       # no session id ⇒ nothing to key a beacon on
# Defense-in-depth: a session id is a uuid; reject anything that isn't a safe basename so the
# path can never escape DIR (harness sids are already clean — this is belt-and-suspenders).
case "$SID" in *[!A-Za-z0-9._-]*|''|.|..) exit 0 ;; esac

BEACON="$DIR/$SID.json"

# ── EXISTENCE EVIDENCE / positive control (cc-backlog 1e16815bac51) ──────────────────────────────
# WHY: an EMPTY beacon dir and a beacon that has NEVER RUN are the SAME observation — absence — and
# only one of them is good news. This hook shipped landed-but-registered-nowhere, so
# /tmp/cc-permission-pending/ was never created; "no pending approvals" actually meant "the hook has
# never fired once" and NOTHING could tell the two apart. A teammate sat blocked on an approval its
# (dead) lead could never answer while the board reported all-clear (2026-07-29; memory
# absence-alarm-needs-existence-evidence — an absence alarm needs evidence its producer's world exists).
#
# The heartbeat is the liveness half of that control: EVERY invocation — write AND clear — creates
# the dir and stamps this file, so after the first hook call of any session the dir exists even when
# nothing is ever pending. Consumers then read a THREE-state world instead of a two-state one:
#   dir ABSENT                      ⇒ the hook has never run (INERT — wired wrong, or not at all)
#   dir present, no <sid>.json      ⇒ genuinely nothing pending  (the all-clear that can be trusted)
#   dir present, <sid>.json present ⇒ a real pending prompt
# cc-blockers' `beacon-inert` alarm renders exactly that split; the wiring half (registered in no
# settings.json) it reads statically, because an unregistered hook cannot heartbeat either.
#
# COST: `clear` runs on every PostToolUse, so this stays FORK-FREE on the hot path — a builtin
# [[ -d ]] test (so mkdir forks once per boot, not once per tool call) and a `:` truncate whose
# MTIME *is* the timestamp, so no date(1) fork. Dot-prefixed and suffix-less so it can never be read
# as a beacon: lead-supervisor globs "$dir"/*.json, which matches neither a dotfile nor this name.
HEARTBEAT="$DIR/.beacon-alive"
beat() {
  [[ -d "$DIR" ]] || mkdir -p "$DIR" 2>/dev/null || return 0
  : > "$HEARTBEAT" 2>/dev/null || true
}

# ── DURABLE ARCHIVE (§3 Stage A.4) ───────────────────────────────────────────────────────────────
# WHY: `clear` used to `rm -f` each record the moment it was answered, so NO history of actual
# permission prompts existed anywhere on this box. Two consequences, both measured:
#   • bin/cc-permission-audit can only ever report an UPPER bound — it infers candidates from
#     transcripts against the static rules, and cannot see what auto mode's classifier silently
#     approved or additionally raised. Its own docstring says so.
#   • The classifier therefore can never be tuned on real data, which is Step 3's named guardrail.
# So the record is appended to a durable append-only JSONL before it is removed.
#
# `resolved_by` + `cleared_tool` are the load-bearing fields for that tuning, and the PAIR is
# required. The tempting shortcut — "PostToolUse only fires on the grant path, so PostToolUse means
# approved" — is FALSE: PostToolUse fires for every tool, not only the prompted one, so after a
# DENIAL the turn can continue, run some other tool, and have THAT tool's PostToolUse clear this
# still-pending beacon. The denial would then be archived as an approval. Recording which tool did
# the clearing lets the consumer demand a match before calling it a grant, and report a mismatch as
# UNKNOWN rather than guessing. Neither field is recoverable from anywhere else after the fact.
#
# ATOMICITY: many sessions append to one file concurrently. A single small write(2) under O_APPEND
# does not interleave, so the record is length-BOUNDED (ARCH_MAXLEN, default 3500 B — comfortably
# inside the 4 KiB atomic-append regime) and over-long payloads degrade to a truncated summary
# rather than risking a torn line. Truncation is RECORDED (`tool_input_truncated`), never silent.
archive() {
  local rts mon line
  mkdir -p "$ARCHDIR" 2>/dev/null || return 0
  # One date(1) fork for both the timestamp and the month bucket.
  local d; d="$(date +'%s %Y-%m' 2>/dev/null)" || return 0
  rts="${d%% *}"; mon="${d##* }"
  # BOTH fields in one jq fork. `cleared_tool` is what makes the outcome inferable at all:
  # PostToolUse fires for EVERY tool, not only the prompted one. After a DENIAL the turn can
  # continue and run some other tool, whose PostToolUse then clears this still-pending beacon —
  # so `resolved_by == PostToolUse` alone would silently record that denial as an approval.
  # Comparing cleared_tool against the beacon's own tool_name separates a real grant from such a
  # collateral clear; the consumer treats a mismatch as UNKNOWN rather than guessing either way.
  local by ct _bi
  _bi="$(printf '%s' "$INPUT" | jq -r '[(.hook_event_name // ""), (.tool_name // "")] | join("\u001f")' 2>/dev/null || true)"
  IFS=$'\x1f' read -r by ct <<<"$_bi" || true

  line="$(jq -c --arg sid "$SID" --arg by "${by:-unknown}" --arg ct "$ct" --argjson rts "$rts" \
      '{session_id:$sid, ts:(.ts//$rts), resolved_ts:$rts, waited_s:($rts - (.ts//$rts)),
        resolved_by:$by, cleared_tool:$ct, tool_name:(.tool_name//""),
        tool_input:(.tool_input//{}), cwd:(.cwd//"")}' "$BEACON" 2>/dev/null)" || return 0
  [[ -z "$line" ]] && return 0

  if (( ${#line} > ARCH_MAXLEN )); then
    line="$(jq -c --arg sid "$SID" --arg by "${by:-unknown}" --argjson rts "$rts" \
        --argjson cap "$((ARCH_MAXLEN / 2))" \
        '{session_id:$sid, ts:(.ts//$rts), resolved_ts:$rts, waited_s:($rts - (.ts//$rts)),
          resolved_by:$by, tool_name:(.tool_name//""), cwd:(.cwd//""),
          tool_input_truncated:true,
          tool_input_summary:((.tool_input//{}|tostring)[0:$cap])}' "$BEACON" 2>/dev/null)" || return 0
    [[ -z "$line" ]] && return 0
  fi
  printf '%s\n' "$line" >> "$ARCHDIR/$mon.jsonl" 2>/dev/null || true
}

case "$MODE" in
  clear)
    beat
    # FAST PATH: with no beacon there is nothing to archive or remove. This builtin test makes the
    # overwhelmingly common PostToolUse call CHEAPER than the unconditional `rm -f` it replaces —
    # the archive costs forks only when a real prompt actually resolved.
    [[ -f "$BEACON" ]] || exit 0
    archive
    rm -f "$BEACON" 2>/dev/null || true
    exit 0
    ;;
  write)
    mkdir -p "$DIR" 2>/dev/null || exit 0
    beat
    TS="$(date +%s)"
    # Atomic write (temp in the SAME dir + mv) so the supervisor never reads a half-written beacon.
    TMP="$(mktemp "$DIR/.$SID.XXXXXX" 2>/dev/null)" || exit 0
    if printf '%s' "$INPUT" | jq -c \
         --argjson ts "$TS" \
         '{ts:$ts, tool_name:(.tool_name // ""), tool_input:(.tool_input // {}), cwd:(.cwd // "")}' \
         > "$TMP" 2>/dev/null; then
      mv -f "$TMP" "$BEACON" 2>/dev/null || rm -f "$TMP" 2>/dev/null || true
    else
      rm -f "$TMP" 2>/dev/null || true         # never leave a partial/garbage beacon behind
    fi
    exit 0
    ;;
  *)
    exit 0                                       # unknown/absent mode ⇒ no-op (fail-quiet)
    ;;
esac
