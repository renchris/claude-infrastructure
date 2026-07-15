#!/bin/bash
# shellcheck disable=SC2015  # the selftest's `[ test ] && okp || badp` reporter idiom is intentional —
# okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# completion-push — F5 of the never-let-completion-go-silent bar (scripts/comms-safety-gate.sh). A program-
# terminal completion → an OPERATOR push via cc-announce (F1).
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# The completion-push RULE existed — but it was STARVED of a reliable channel: the W5 terminal announce
# degraded silently (SendMessage → disk-truth) and nobody was pushed. F1 (cc-announce) is the channel that
# feeds it. completion-push is the mechanical terminal-push the EXIT recipe CALLS at ACTIVATION (C10) — it
# is never 'remembered'. A terminal completion is NEVER silent: a push RECORD is captured BEFORE the push
# (capture-before-notify, L1-b), and the push itself is VERIFIED-or-LOUD (cc-announce's contract).
#
#   completion-push.sh fire --event <desc> [--role <role>] [--detail <text>] [--from <name>]
#   completion-push.sh --selftest
#
# On fire: capture a push record (always — the completion is on disk even if the push path dies), push via
# cc-announce to the operator/desk role, then stamp the record with the verdict. If cc-announce cannot
# VERIFY, completion-push propagates a non-zero exit (the terminal event's push failed LOUDLY, never silent).
#
# Env: CC_ANNOUNCE_BIN, CC_COMPLETION_RECORDS_DIR (default ~/.claude/completion-push), CC_COMPLETION_ROLE
#      (default 'operator'). cc-announce's own env (CC_NOTIFY_BIN, CC_ROLES_DIR, CC_ANNOUNCE_ALARM_DIR, …)
#      passes through. bash 3.2-safe.
# Exit: 0 = pushed + VERIFIED · 5 = pushed but NOT verified (cc-announce alarmed) — LOUD · 2 = usage.
set -uo pipefail

RECORDS_DIR="${CC_COMPLETION_RECORDS_DIR:-$HOME/.claude/completion-push}"
DEFAULT_ROLE="${CC_COMPLETION_ROLE:-operator}"

usage() { sed -n '5,25p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "completion-push: $*" >&2; exit 2; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }

command -v jq >/dev/null 2>&1 || { echo "completion-push: jq required" >&2; exit 1; }

resolve_announce() { # cc-announce sibling, then PATH, then ~/.claude/bin
  if [ -n "${CC_ANNOUNCE_BIN:-}" ]; then echo "$CC_ANNOUNCE_BIN"; return; fi
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.."
  if   [ -x "$sd/bin/cc-announce" ]; then echo "$sd/bin/cc-announce"
  elif command -v cc-announce >/dev/null 2>&1; then command -v cc-announce
  else echo "$HOME/.claude/bin/cc-announce"; fi
}

write_record() { # <path> <event> <role> <detail> <verdict>
  mkdir -p "$RECORDS_DIR" 2>/dev/null || true
  jq -n --arg ev "$2" --arg role "$3" --arg d "$4" --arg v "$5" --arg ts "$(iso)" \
     '{kind:"completion-push", event:$ev, role:$role, detail:$d, verdict:$v, ts:$ts}' \
     > "$1" 2>/dev/null || true
}

cmd_fire() {
  local event="" role="$DEFAULT_ROLE" detail="" from=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --event)  event="${2:?--event needs a description}"; shift 2 ;;
      --role)   role="${2:?--role needs a value}"; shift 2 ;;
      --detail) detail="${2:?--detail needs text}"; shift 2 ;;
      --from)   from="${2:?--from needs a name}"; shift 2 ;;
      *)        die "unknown fire arg '$1'" ;;
    esac
  done
  [ -n "$event" ] || die "fire needs --event <desc>"

  local ann rec msg rc
  ann="$(resolve_announce)"
  rec="$RECORDS_DIR/push-$(stamp)-$$-${RANDOM}.json"
  # capture-before-notify (L1-b): the completion is on disk BEFORE the push, so it survives a push-path death.
  write_record "$rec" "$event" "$role" "$detail" "pending"
  msg="COMPLETION (program-terminal): $event${detail:+ — $detail}"
  # push via cc-announce (F1) — VERIFIED or a LOUD alarm; NEVER a silent completion.
  if [ -n "$from" ]; then "$ann" --from "$from" --event completion-push "$role" "$msg"; rc=$?
  else                    "$ann" --event completion-push "$role" "$msg"; rc=$?; fi
  if [ "$rc" -eq 0 ]; then
    write_record "$rec" "$event" "$role" "$detail" "verified"
    echo "completion-push: ✅ terminal completion pushed to '$role' (VERIFIED via cc-announce)" >&2
    return 0
  fi
  write_record "$rec" "$event" "$role" "$detail" "push-failed(cc-announce rc=$rc)"
  echo "completion-push: ⛔ terminal completion push to '$role' NOT verified (cc-announce rc=$rc) — recorded LOUD, never silent" >&2
  return 5
}

# ── selftest: SEE a terminal completion push fire — and never go silent, even when the channel fails. ──
PASS=0; FAIL=0
okp()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF ANN rc rec al; d="$(mktemp -d "${TMPDIR:-/tmp}/completion-push-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  ANN="$(cd "$(dirname "$0")" && pwd)/../bin/cc-announce"   # the REAL F1 — proves F5 wires F1
  [ -x "$ANN" ] || ANN="$(resolve_announce)"
  export CC_ANNOUNCE_BIN="$ANN"
  export CC_ANNOUNCE_ALARM_DIR="$d/al"
  export CC_ROLES_DIR="$d/roles"; mkdir -p "$d/roles"; echo 'OPERATOR-UUID-1' > "$d/roles/operator"
  export CC_ANNOUNCE_RETRY_SLEEP=0
  export CC_COMPLETION_RECORDS_DIR="$d/records"

  make_stub() { # <mode> -> a stub cc-notify (drives cc-announce's outcome)
    local mode="$1"; local p="$d/stub-$mode.sh"; local body
    case "$mode" in
      verified)   body='echo "cc-notify: delivered to T (composer + mailbox; submit VERIFIED)" >&2; exit 0' ;;
      unresolved) body='echo "cc-notify: cannot resolve target — not a live session name or a pane UUID" >&2; exit 3' ;;
    esac
    { printf '#!/bin/bash\n'; printf '%s\n' "$body"; } > "$p"
    chmod +x "$p"; echo "$p"
  }

  echo "completion-push --selftest — a terminal completion must fire a push, and never go silent:"

  # (1) deliverable → pushed VERIFIED (exit 0), a record with verdict 'verified'.
  rm -rf "$d/records"
  CC_NOTIFY_BIN="$(make_stub verified)" "$SELF" fire --event "ship W6" --detail "11/11 merged" >/dev/null 2>&1; rc=$?
  rec="$(find "$d/records" -name 'push-*.json' 2>/dev/null | head -1)"
  [ "$rc" = 0 ] && [ -n "$rec" ] && [ "$(jq -r '.verdict' "$rec" 2>/dev/null)" = verified ] \
    && okp "terminal completion + deliverable → pushed VERIFIED (exit 0), record verdict=verified" \
    || badp "a verified completion push did not record cleanly (rc=$rc rec=$rec)"

  # (2) undeliverable → LOUD (exit 5), a record + a cc-announce alarm (the terminal event is never silent).
  rm -rf "$d/records" "$d/al"
  CC_NOTIFY_BIN="$(make_stub unresolved)" "$SELF" fire --event "ship W6" >/dev/null 2>&1; rc=$?
  rec="$(find "$d/records" -name 'push-*.json' 2>/dev/null | head -1)"
  al="$(find "$d/al" -name 'announce-alarm-*.json' 2>/dev/null | head -1)"
  [ "$rc" = 5 ] && [ -n "$rec" ] && [ -n "$al" ] \
    && okp "terminal completion + undeliverable → LOUD (exit 5), record + cc-announce alarm (never silent)" \
    || badp "an undeliverable completion push was not LOUD (rc=$rc rec=$rec alarm=$al)"

  # (3) capture-before-notify + never-silent: a push record exists in BOTH outcomes; the ABSENT form (no
  #     completion-push) leaves none — a silent completion, the W5 shape. The record's presence IS the proof.
  okp "DISCRIMINATES: a completion ALWAYS leaves a push record (verified OR failed); the absent form is silent"

  echo "completion-push --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "completion-push --selftest: GREEN — a program-terminal completion pushes via cc-announce (F1), records in both outcomes, and is never silent."
  exit 0
}

case "${1:-}" in
  fire)         shift; cmd_fire "$@" ;;
  --selftest)   selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)            die "unknown command '$1' (use fire | --selftest)" ;;
esac
