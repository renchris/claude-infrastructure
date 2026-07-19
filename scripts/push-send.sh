#!/bin/bash
# shellcheck disable=SC2015  # the selftest's `[ test ] && okp || badp` reporter idiom is intentional —
# okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# push-send.sh — the callable, VERIFIED away-phone (Pushover) sender. The phone leg of the comms
# triad: cc-notify (a pane), cc-announce (a role → a pane, verified), push-send (the operator's
# PHONE, verified). It is the missing primitive P0-7 / G-P15-1 needs.
#
# ── THE GAP THAT IS THE SPEC ───────────────────────────────────────────────────────────────────────────
# The ONLY code that reaches the phone today is `hooks/push-critical.sh` — a Notification HOOK that
# fires `curl … >/dev/null 2>&1 || true`, SWALLOWING the API response. So "the page reached the phone"
# was never anything better than "we made a syscall and hoped". A dead desk, a class-B fork, a morning
# digest — none had a callable, verifiable way to reach an away human. push-send closes that: it POSTs to
# Pushover, CAPTURES the response, and trusts ONLY `status:1` (HTTP 200) — every lesser outcome is a LOUD
# non-zero with the reason, never a silent success. It NEVER logs the token/user (redacted everywhere).
#
#   push-send.sh send --title T --message M [--priority N] [--sound S] [--url U] [--url-title UT]
#                     [--receipt] [--from LABEL]      send + VERIFY (status:1) or LOUD non-zero
#   push-send.sh receipt <token>                       poll an emergency (priority-2) receipt for delivery
#   push-send.sh --selftest                            RED-prove: status:0 / HTTP-4xx / no-creds each fail LOUD
#   push-send.sh -h | --help
#
# `--receipt` forces priority=2 (emergency: retry+expire) and, on success, prints `receipt=<token>` so a
# caller (the delivery-verify probe) can poll `push-send.sh receipt <token>` for true device delivery.
#
# STDOUT = machine key=value lines (status= request= receipt=); STDERR = the human ✅/⛔ line.
# INERT (creds unset) is exit 3 — a LOUD "channel not wired" signal a caller reports accurately, never a
# fake success. This mirrors push-critical.sh's inert guard, but SURFACES it instead of exiting 0.
#
# Env: PUSHOVER_TOKEN / PUSHOVER_USER (the creds; unset ⇒ INERT exit 3). Tests/tunables:
#   CC_PUSH_CURL_BIN (default curl) · CC_PUSH_API_BASE (default https://api.pushover.net/1) ·
#   CC_PUSH_MAX_TIME (8) · CC_PUSH_RETRY (30, priority-2) · CC_PUSH_EXPIRE (3600, priority-2) ·
#   CC_PUSH_RECORDS_DIR (default ~/.claude/autonomy/push-records — redacted verdict records).
# BSD+GNU portable, bash 3.2-safe, no eval, fail-loud. Exit: 0 verified · 2 usage · 3 INERT (no creds)
#   · 5 send failed (status:0 / HTTP≠200 / no response) · 6 receipt: not yet delivered.
set -uo pipefail

API_BASE="${CC_PUSH_API_BASE:-https://api.pushover.net/1}"
CURL="${CC_PUSH_CURL_BIN:-curl}"
MAX_TIME="${CC_PUSH_MAX_TIME:-8}"
RETRY="${CC_PUSH_RETRY:-30}"
EXPIRE="${CC_PUSH_EXPIRE:-3600}"
RECORDS_DIR="${CC_PUSH_RECORDS_DIR:-$HOME/.claude/autonomy/push-records}"

usage() { sed -n '5,30p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "push-send: $*" >&2; exit 2; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ''; }
stamp() { date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "$$"; }

command -v jq >/dev/null 2>&1 || { echo "push-send: jq required" >&2; exit 1; }

# Redacted verdict record — NEVER the token/user, only the outcome (evidence, inv7). Best-effort.
record() { # <kind> <verdict> <detail>
  mkdir -p "$RECORDS_DIR" 2>/dev/null || return 0
  jq -n --arg k "$1" --arg v "$2" --arg d "$3" --arg ts "$(iso)" \
     '{kind:$k, verdict:$v, detail:$d, ts:$ts}' \
     > "$RECORDS_DIR/push-$(stamp)-$$-${RANDOM:-0}.json" 2>/dev/null || true
}

creds_or_inert() { # exit 3 LOUD if either credential is unset — a caller reports "channel not wired"
  if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
    echo "push-send: INERT — PUSHOVER_TOKEN/PUSHOVER_USER unset; the phone channel is not wired (P0-7 operator step)" >&2
    record "$1" inert "creds unset"
    exit 3
  fi
}

cmd_send() {
  local title="" message="" priority="0" sound="" url="" url_title="" from="" receipt=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)     title="${2:?--title needs text}"; shift 2 ;;
      --message)   message="${2:?--message needs text}"; shift 2 ;;
      --priority)  priority="${2:?--priority needs a number}"; shift 2 ;;
      --sound)     sound="${2:?--sound needs a value}"; shift 2 ;;
      --url)       url="${2:?--url needs a value}"; shift 2 ;;
      --url-title) url_title="${2:?--url-title needs a value}"; shift 2 ;;
      --from)      from="${2:?--from needs a value}"; shift 2 ;;
      --receipt)   receipt=1; shift ;;
      *)           die "unknown send arg '$1'" ;;
    esac
  done
  [ -n "$title" ]   || die "send needs --title"
  [ -n "$message" ] || die "send needs --message"
  creds_or_inert send

  # Pushover hard limits: title ≤250, message ≤1024. Truncate defensively — an over-length field is a
  # guaranteed API 400, and the digest summary is caller-shaped and could grow.
  title="$(printf '%s' "$title" | cut -c1-250)"
  message="$(printf '%s' "$message" | cut -c1-1024)"
  [ -n "$from" ] && title="$title [$from]" && title="$(printf '%s' "$title" | cut -c1-250)"

  # --receipt ⇒ emergency priority=2 (repeat-until-acknowledged) + mandatory retry/expire.
  [ "$receipt" = 1 ] && priority=2

  # Build the form args as an array so values with spaces stay intact (SC-safe, no eval).
  local args=()
  args+=( -s --max-time "$MAX_TIME" -w $'\n%{http_code}' )
  args+=( --form-string "token=${PUSHOVER_TOKEN}" )
  args+=( --form-string "user=${PUSHOVER_USER}" )
  args+=( --form-string "title=${title}" )
  args+=( --form-string "message=${message}" )
  args+=( --form-string "priority=${priority}" )
  [ -n "$sound" ]     && args+=( --form-string "sound=${sound}" )
  [ -n "$url" ]       && args+=( --form-string "url=${url}" )
  [ -n "$url_title" ] && args+=( --form-string "url_title=${url_title}" )
  if [ "$priority" = 2 ]; then
    args+=( --form-string "retry=${RETRY}" --form-string "expire=${EXPIRE}" )
  fi

  local out code body status request rcpt
  out="$("$CURL" "${args[@]}" "${API_BASE}/messages.json" 2>/dev/null)" || out=""
  # curl appended `\n<http_code>`; split it back off (Pushover bodies are single-line JSON).
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  [ "$code" = "$out" ] && { code=""; body="$out"; }   # no newline ⇒ nothing came back

  if [ -z "$body" ]; then
    echo "push-send: ⛔ NO RESPONSE from Pushover (network/timeout) — NOT delivered" >&2
    record send failed "no response (http=${code:-none})"
    exit 5
  fi
  status="$(printf '%s' "$body" | jq -r '.status // 0' 2>/dev/null || echo 0)"
  request="$(printf '%s' "$body" | jq -r '.request // ""' 2>/dev/null || echo "")"
  rcpt="$(printf '%s' "$body" | jq -r '.receipt // ""' 2>/dev/null || echo "")"

  if [ "$code" = 200 ] && [ "$status" = 1 ]; then
    printf 'status=1\n'; [ -n "$request" ] && printf 'request=%s\n' "$request"
    [ -n "$rcpt" ] && printf 'receipt=%s\n' "$rcpt"
    echo "push-send: ✅ delivered — Pushover accepted (status:1, request=${request:-?}${rcpt:+, receipt=$rcpt})" >&2
    record send verified "request=${request:-?}${rcpt:+ receipt=$rcpt} priority=$priority"
    exit 0
  fi

  # status:0 ⇒ Pushover rejected it; surface .errors[] (never the creds).
  local errs
  errs="$(printf '%s' "$body" | jq -r '(.errors // []) | join("; ")' 2>/dev/null || echo "")"
  printf 'status=0\n'
  echo "push-send: ⛔ REJECTED by Pushover (http=${code:-?}, status=${status}): ${errs:-unknown error} — NOT delivered" >&2
  record send failed "http=${code:-?} status=$status errors=${errs:-unknown}"
  exit 5
}

cmd_receipt() {
  local token="${1:-}"
  [ -n "$token" ] || die "receipt needs a <token>"
  creds_or_inert receipt
  local out code body status delivered acked
  out="$("$CURL" -s --max-time "$MAX_TIME" -w $'\n%{http_code}' \
        "${API_BASE}/receipts/${token}.json?token=${PUSHOVER_TOKEN}" 2>/dev/null)" || out=""
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  [ "$code" = "$out" ] && { code=""; body="$out"; }
  [ -n "$body" ] || { echo "push-send: ⛔ receipt query — no response (http=${code:-none})" >&2; exit 5; }
  status="$(printf '%s' "$body" | jq -r '.status // 0' 2>/dev/null || echo 0)"
  delivered="$(printf '%s' "$body" | jq -r '.last_delivered_at // 0' 2>/dev/null || echo 0)"
  acked="$(printf '%s' "$body" | jq -r '.acknowledged // 0' 2>/dev/null || echo 0)"
  if [ "$code" = 200 ] && [ "$status" = 1 ] && [ "$delivered" != 0 ] && [ -n "$delivered" ]; then
    printf 'delivered=1\nacknowledged=%s\n' "$acked"
    echo "push-send: ✅ receipt — DELIVERED to a device (last_delivered_at=$delivered, acknowledged=$acked)" >&2
    exit 0
  fi
  printf 'delivered=0\n'
  echo "push-send: ⏳ receipt — not yet delivered to a device (status=$status, last_delivered_at=$delivered)" >&2
  exit 6
}

# ── selftest: SEE the verify discriminate — a status:0, an HTTP-4xx, and no-creds must each fail LOUD, ──
# ── and only a real status:1/HTTP-200 passes. Uses a stub curl (no network, no phone). ─────────────────
PASS=0; FAIL=0
okp()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF; d="$(mktemp -d "${TMPDIR:-/tmp}/push-send-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  export CC_PUSH_RECORDS_DIR="$d/rec"

  mkstub() { # <name> <body> <code> -> a stub curl printing "<body>\n<code>" (mimics our -w format)
    local p="$d/curl-$1.sh"
    cat > "$p" <<EOF
#!/bin/bash
printf '%s\n%s' '$2' '$3'
EOF
    chmod +x "$p"; echo "$p"
  }

  echo "push-send --selftest — the verify must trust ONLY status:1 + HTTP 200:"

  # (1) status:1 + HTTP 200 → VERIFIED (exit 0), stdout status=1, a 'verified' record.
  rm -rf "$d/rec"
  CC_PUSH_CURL_BIN="$(mkstub ok '{"status":1,"request":"REQ1","receipt":"RCPT1"}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    "$SELF" send --title T --message M --receipt >"$d/o1" 2>"$d/e1"; rc=$?
  grep -q '^status=1' "$d/o1" && grep -q '^receipt=RCPT1' "$d/o1" \
    && [ "$rc" = 0 ] && [ -n "$(find "$d/rec" -name '*.json' 2>/dev/null)" ] \
    && [ "$(jq -r .verdict "$(find "$d/rec" -name '*.json' | head -1)")" = verified ] \
    && okp "status:1/HTTP-200 → VERIFIED (exit 0, status=1, receipt echoed, record=verified)" \
    || badp "a real success did not verify cleanly (rc=$rc)"

  # (2) status:0 + HTTP 400 → LOUD FAIL (exit 5), errors surfaced, a 'failed' record.
  rm -rf "$d/rec"
  CC_PUSH_CURL_BIN="$(mkstub bad '{"status":0,"errors":["user key is invalid"]}' 400)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    "$SELF" send --title T --message M >"$d/o2" 2>"$d/e2"; rc=$?
  [ "$rc" = 5 ] && grep -qi 'REJECTED' "$d/e2" && grep -qi 'user key is invalid' "$d/e2" \
    && [ "$(jq -r .verdict "$(find "$d/rec" -name '*.json' | head -1)")" = failed ] \
    && okp "status:0/HTTP-400 → LOUD FAIL (exit 5, errors surfaced, record=failed)" \
    || badp "a rejected send was not LOUD (rc=$rc)"

  # (3) HTTP 200 but status:0 (Pushover's own soft-reject shape) → FAIL, not a false pass.
  CC_PUSH_CURL_BIN="$(mkstub soft '{"status":0,"errors":["message cannot be blank"]}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    "$SELF" send --title T --message M >/dev/null 2>"$d/e3"; rc=$?
  [ "$rc" = 5 ] && okp "HTTP-200 + status:0 → FAIL (exit 5) — the verify never trusts HTTP alone" \
    || badp "HTTP-200 with status:0 falsely passed (rc=$rc)"

  # (4) no creds → INERT (exit 3), a LOUD 'channel not wired' — never a fake success, never a syscall.
  ( unset PUSHOVER_TOKEN PUSHOVER_USER
    CC_PUSH_CURL_BIN=/bin/false "$SELF" send --title T --message M >/dev/null 2>"$d/e4" ); rc=$?
  [ "$rc" = 3 ] && grep -qi 'INERT' "$d/e4" \
    && okp "no creds → INERT (exit 3, LOUD 'not wired') — surfaced, never exit 0" \
    || badp "missing creds did not surface as INERT exit 3 (rc=$rc)"

  # (5) empty body (network death) → NO RESPONSE FAIL, never a false pass.
  CC_PUSH_CURL_BIN="$(mkstub empty '' '')" PUSHOVER_TOKEN=t PUSHOVER_USER=u \
    "$SELF" send --title T --message M >/dev/null 2>"$d/e5"; rc=$?
  [ "$rc" = 5 ] && grep -qi 'NO RESPONSE' "$d/e5" \
    && okp "empty response (network death) → FAIL (exit 5), never a false pass" \
    || badp "an empty response falsely passed (rc=$rc)"

  # (6) receipt: last_delivered_at>0 → delivered (exit 0); ==0 → not-yet (exit 6).
  CC_PUSH_CURL_BIN="$(mkstub rok '{"status":1,"last_delivered_at":1784000000,"acknowledged":1}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u "$SELF" receipt RCPT1 >"$d/o6" 2>/dev/null; rc=$?
  [ "$rc" = 0 ] && grep -q '^delivered=1' "$d/o6" \
    && okp "receipt last_delivered_at>0 → DELIVERED (exit 0, delivered=1)" \
    || badp "a delivered receipt did not pass (rc=$rc)"
  CC_PUSH_CURL_BIN="$(mkstub rno '{"status":1,"last_delivered_at":0,"acknowledged":0}' 200)" \
    PUSHOVER_TOKEN=t PUSHOVER_USER=u "$SELF" receipt RCPT1 >/dev/null 2>/dev/null; rc=$?
  [ "$rc" = 6 ] && okp "receipt last_delivered_at==0 → not-yet-delivered (exit 6)" \
    || badp "an undelivered receipt did not report exit 6 (rc=$rc)"

  echo "push-send --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "push-send --selftest: GREEN — the phone send is VERIFIED (status:1+HTTP200 only), inert-loud, and receipt-aware."
  exit 0
}

case "${1:-}" in
  send)         shift; cmd_send "$@" ;;
  receipt)      shift; cmd_receipt "$@" ;;
  --selftest)   selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)            die "unknown command '$1' (use send | receipt | --selftest)" ;;
esac
