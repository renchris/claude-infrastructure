#!/bin/bash
# shellcheck disable=SC2015  # okp/badp reporter idiom (always return 0) — SC2015's failure mode can't occur.
#
# delivery-verify.sh — the P0-7 page-delivery PROBE. Synthesizes a DEAD-desk page and drives it through
# the REAL phone channel (push-send.sh), so "the page reaches the phone" becomes a MACHINE VERDICT, not a
# hope. This is the "effect-checked live once" tool the plan calls for: the operator arms Pushover, runs
# this ONCE, and gets ✅/⛔ back (plus, with --receipt, device-delivery confirmation from Pushover itself).
#
# ── WHY A PROBE (the spec) ─────────────────────────────────────────────────────────────────────────────
# The acceptance for P0-7 is "a synthetic DEAD page reaches the phone (effect-checked live once)". Before
# push-send.sh there was no way to send-and-verify — wiring-all's ⑬ could only say `printf … | push-critical.sh
# (expect a phone buzz)`: fire-and-forget, no verdict. This probe sends a page shaped EXACTLY like a real
# DEAD-desk page (the incident this whole channel exists for), verifies Pushover accepted it, and — with
# --receipt — polls the receipt until a device confirms delivery. It is clearly SYNTHETIC/labelled so it
# can never be mistaken for a real incident, and it is INERT-honest: unarmed creds report "not wired", never
# a false green.
#
#   delivery-verify.sh [--receipt] [--desk] [--no-phone] [--role <role>]
#                      [--poll-tries N] [--poll-sleep S]        run the probe; ✅/⛔ verdict
#   delivery-verify.sh --selftest         RED-prove: accepted→PASS · inert→UNWIRED · rejected→FAIL · desk-leg
#   delivery-verify.sh -h | --help
#
# Legs: PHONE (push-send.sh; default ON) is the P0-7 core. --desk ALSO wakes the desk role in-terminal via
# cc-announce (proves both halves of "reaches you"). --receipt uses emergency priority-2 + receipt polling
# for true device-delivery (not just Pushover-accepted).
#
# Env/tunables (tests): CC_PUSH_SEND_BIN (default beside → ~/.claude/scripts/push-send.sh) · CC_ANNOUNCE_BIN
#   (default repo bin → ~/.claude/bin/cc-announce) · CC_ROLES_DIR (cc-announce's role map) · CC_DELIVERY_ROLE
#   (default desk) · CC_DELIVERY_PROBE_LOG (default ~/.claude/autonomy/delivery-probe.log) ·
#   CC_DELIVERY_POLL_TRIES (6) · CC_DELIVERY_POLL_SLEEP (5). bash 3.2-safe, no eval, fail-loud.
# Exit: 0 all requested legs delivered · 2 usage · 3 a requested leg is INERT/UNWIRED · 5 a requested leg FAILED.
set -uo pipefail

ROLE="${CC_DELIVERY_ROLE:-desk}"
PROBE_LOG="${CC_DELIVERY_PROBE_LOG:-$HOME/.claude/autonomy/delivery-probe.log}"
POLL_TRIES="${CC_DELIVERY_POLL_TRIES:-6}"
POLL_SLEEP="${CC_DELIVERY_POLL_SLEEP:-5}"

usage() { sed -n '4,30p' "$0" | sed 's/^# \{0,1\}//'; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ''; }
stamp() { date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo "$$"; }

# push-send.sh: env override → beside this script → CFG/scripts → ~/.claude/scripts.
resolve_push() {
  if [ -n "${CC_PUSH_SEND_BIN:-}" ]; then echo "$CC_PUSH_SEND_BIN"; return; fi
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  for c in "$sd/push-send.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/push-send.sh" "$HOME/.claude/scripts/push-send.sh"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  echo "$sd/push-send.sh"   # last resort — resolve-or-loud handled by the caller's rc
}
# cc-announce: env override → repo bin (../bin) → PATH → ~/.claude/bin.
resolve_announce() {
  if [ -n "${CC_ANNOUNCE_BIN:-}" ]; then echo "$CC_ANNOUNCE_BIN"; return; fi
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.."
  if   [ -x "$sd/bin/cc-announce" ]; then echo "$sd/bin/cc-announce"
  elif command -v cc-announce >/dev/null 2>&1; then command -v cc-announce
  else echo "$HOME/.claude/bin/cc-announce"; fi
}

log_probe() { # <verdict> <detail>
  mkdir -p "$(dirname "$PROBE_LOG")" 2>/dev/null || return 0
  printf '%s  delivery-verify %s — %s\n' "$(iso)" "$1" "$2" >> "$PROBE_LOG" 2>/dev/null || true
}

run_probe() {
  local want_receipt=0 want_desk=0 want_phone=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --receipt)    want_receipt=1; shift ;;
      --desk)       want_desk=1; shift ;;
      --no-phone)   want_phone=0; shift ;;
      --role)       ROLE="${2:?--role needs a value}"; shift 2 ;;
      --poll-tries) POLL_TRIES="${2:?--poll-tries needs a number}"; shift 2 ;;
      --poll-sleep) POLL_SLEEP="${2:?--poll-sleep needs a number}"; shift 2 ;;
      -h|--help)    usage; exit 0 ;;
      *)            echo "delivery-verify: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
    esac
  done

  local sid title msg worst=0   # worst: 0 pass · 3 inert · 5 fail (monotone max)
  sid="probe-$(stamp)-$$"
  title="Claude ${ROLE} — DEAD (delivery probe)"
  msg="SYNTHETIC dead-${ROLE} page — if you see this, the phone page channel is LIVE. sid=${sid} state=DEAD ts=$(iso). (P0-7 delivery-verify probe — NOT a real incident.)"

  echo "delivery-verify: firing a synthetic DEAD page (sid=$sid, role=$ROLE, receipt=$want_receipt, desk=$want_desk)" >&2

  # ── PHONE leg (push-send.sh) — the P0-7 core ──────────────────────────────────────────────────────────
  if [ "$want_phone" = 1 ]; then
    local push out rc token
    push="$(resolve_push)"
    if [ ! -x "$push" ]; then
      echo "delivery-verify: ⛔ PHONE leg — push-send.sh not found/executable ($push)" >&2
      log_probe FAIL "phone: push-send unresolved"; worst=5
    else
      local sargs=( send --title "$title" --message "$msg" --from probe )
      if [ "$want_receipt" = 1 ]; then sargs+=( --receipt ); else sargs+=( --priority 1 ); fi
      out="$("$push" "${sargs[@]}" 2>/dev/null)"; rc=$?
      case "$rc" in
        0)
          token="$(printf '%s' "$out" | sed -n 's/^receipt=//p' | head -1)"
          echo "delivery-verify: ✅ PHONE leg — Pushover ACCEPTED the DEAD page" >&2
          if [ "$want_receipt" = 1 ] && [ -n "$token" ]; then
            # poll the receipt for real device delivery — the strongest programmatic proof.
            local i=1 delivered=0
            while [ "$i" -le "$POLL_TRIES" ]; do
              if "$push" receipt "$token" >/dev/null 2>&1; then delivered=1; break; fi
              i=$((i + 1)); [ "$i" -le "$POLL_TRIES" ] && sleep "$POLL_SLEEP" 2>/dev/null || true
            done
            if [ "$delivered" = 1 ]; then
              echo "delivery-verify: ✅ PHONE leg — DELIVERED to a device (receipt confirmed)" >&2
              log_probe PASS "phone: delivered-to-device (receipt)"
            else
              echo "delivery-verify: ⚠ PHONE leg — accepted, but device-delivery UNCONFIRMED after ${POLL_TRIES} polls (device offline? check the phone)" >&2
              log_probe PASS "phone: accepted, device-delivery unconfirmed"
            fi
          else
            log_probe PASS "phone: accepted (status:1)"
          fi
          ;;
        3)
          echo "delivery-verify: ⛔ PHONE leg — channel NOT WIRED (PUSHOVER_TOKEN/USER unset). Arm them in ~/.zshenv, then re-run (P0-7 operator step)." >&2
          log_probe UNWIRED "phone: inert (no creds)"; worst=3
          ;;
        *)
          echo "delivery-verify: ⛔ PHONE leg — send FAILED (push-send rc=$rc); see its stderr" >&2
          log_probe FAIL "phone: send failed rc=$rc"; [ "$worst" -lt 5 ] && worst=5
          ;;
      esac
    fi
  fi

  # ── DESK leg (cc-announce → role → pane) — the in-terminal half of "reaches you" (--desk) ─────────────
  if [ "$want_desk" = 1 ]; then
    local ann rc
    ann="$(resolve_announce)"
    if [ ! -x "$ann" ]; then
      echo "delivery-verify: ⛔ DESK leg — cc-announce not found/executable ($ann)" >&2
      log_probe FAIL "desk: cc-announce unresolved"; [ "$worst" -lt 5 ] && worst=5
    else
      "$ann" --from probe --event delivery-probe "$ROLE" "SYNTHETIC DEAD-$ROLE page (delivery-verify probe, sid=$sid) — if this woke you in-terminal, the desk-role wake is LIVE." >/dev/null 2>&1; rc=$?
      if [ "$rc" = 0 ]; then
        echo "delivery-verify: ✅ DESK leg — cc-announce VERIFIED the desk-role wake" >&2
        log_probe PASS "desk: announce verified"
      else
        echo "delivery-verify: ⛔ DESK leg — cc-announce did NOT verify (rc=$rc: role unresolved / stranded / alarmed)" >&2
        log_probe FAIL "desk: announce rc=$rc"; [ "$worst" -lt 5 ] && worst=5
      fi
    fi
  fi

  case "$worst" in
    0) echo "delivery-verify: ✅ PROBE PASSED — every requested leg delivered." >&2; exit 0 ;;
    3) echo "delivery-verify: ⛔ PROBE UNWIRED — a requested leg has no live channel (arm the creds/role, then re-run)." >&2; exit 3 ;;
    *) echo "delivery-verify: ⛔ PROBE FAILED — a requested leg did not deliver (see above)." >&2; exit 5 ;;
  esac
}

# ── selftest: SEE the probe discriminate accepted / unwired / rejected, and add the desk leg. ───────────
PASS=0; FAIL=0
okp()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF; d="$(mktemp -d "${TMPDIR:-/tmp}/delivery-verify-selftest.XXXXXX")" || { echo mktemp>&2; exit 2; }
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  export CC_DELIVERY_PROBE_LOG="$d/probe.log"
  export CC_DELIVERY_POLL_SLEEP=0

  # stub push-send: `send` prints $STUB_SEND_OUT + exits $STUB_SEND_RC; `receipt` exits $STUB_RCPT_RC.
  mkpush() {
    local p="$d/push-$1.sh"
    cat > "$p" <<'EOF'
#!/bin/bash
case "${1:-}" in
  send)    [ -n "${STUB_SEND_OUT:-}" ] && printf '%s\n' "$STUB_SEND_OUT"; exit "${STUB_SEND_RC:-0}" ;;
  receipt) exit "${STUB_RCPT_RC:-0}" ;;
  *)       exit 2 ;;
esac
EOF
    chmod +x "$p"; echo "$p"
  }
  mkann() { # stub cc-announce with a fixed exit
    local p="$d/ann-$1.sh"; { printf '#!/bin/bash\n'; printf 'exit %s\n' "$2"; } > "$p"; chmod +x "$p"; echo "$p"
  }

  echo "delivery-verify --selftest — the probe must discriminate accepted / unwired / rejected:"

  # (1) phone accepted → PASS (exit 0), log PASS, message names the DEAD page.
  rm -f "$d/probe.log"
  CC_PUSH_SEND_BIN="$(mkpush ok)" STUB_SEND_RC=0 "$SELF" >/dev/null 2>"$d/e1"; rc=$?
  [ "$rc" = 0 ] && grep -q 'ACCEPTED the DEAD page' "$d/e1" && grep -q 'PROBE PASSED' "$d/e1" \
    && grep -q 'PASS' "$d/probe.log" \
    && okp "phone accepted → PROBE PASSED (exit 0), synthetic DEAD page fired, logged PASS" \
    || badp "an accepted phone leg did not pass (rc=$rc)"

  # (2) phone inert (creds unset, push-send exit 3) → UNWIRED (exit 3), never a false green.
  CC_PUSH_SEND_BIN="$(mkpush inert)" STUB_SEND_RC=3 "$SELF" >/dev/null 2>"$d/e2"; rc=$?
  [ "$rc" = 3 ] && grep -qi 'NOT WIRED' "$d/e2" && grep -q 'PROBE UNWIRED' "$d/e2" \
    && okp "phone inert → PROBE UNWIRED (exit 3), 'not wired' surfaced — never a false green" \
    || badp "an inert phone channel did not surface UNWIRED (rc=$rc)"

  # (3) phone rejected (push-send exit 5) → FAIL (exit 5).
  CC_PUSH_SEND_BIN="$(mkpush bad)" STUB_SEND_RC=5 "$SELF" >/dev/null 2>"$d/e3"; rc=$?
  [ "$rc" = 5 ] && grep -q 'PROBE FAILED' "$d/e3" \
    && okp "phone rejected → PROBE FAILED (exit 5)" \
    || badp "a rejected phone leg did not fail (rc=$rc)"

  # (4) --receipt: accepted + receipt token + device confirms → 'DELIVERED to a device'.
  CC_PUSH_SEND_BIN="$(mkpush rok)" STUB_SEND_RC=0 STUB_SEND_OUT='receipt=RCPT9' STUB_RCPT_RC=0 \
    "$SELF" --receipt --poll-tries 2 >/dev/null 2>"$d/e4"; rc=$?
  [ "$rc" = 0 ] && grep -q 'DELIVERED to a device' "$d/e4" \
    && okp "--receipt + device confirms → DELIVERED to a device (exit 0)" \
    || badp "a confirmed receipt did not report device delivery (rc=$rc)"

  # (5) --receipt: accepted but device never confirms → PASS-accepted but 'UNCONFIRMED' (exit 0, warned).
  CC_PUSH_SEND_BIN="$(mkpush rno)" STUB_SEND_RC=0 STUB_SEND_OUT='receipt=RCPT9' STUB_RCPT_RC=6 \
    "$SELF" --receipt --poll-tries 2 >/dev/null 2>"$d/e5"; rc=$?
  [ "$rc" = 0 ] && grep -qi 'UNCONFIRMED' "$d/e5" \
    && okp "--receipt + device silent → accepted but device-delivery UNCONFIRMED (exit 0, warned)" \
    || badp "an unconfirmed receipt was not surfaced as a warning (rc=$rc)"

  # (6) --desk: phone accepted + desk announce verified → PASS both legs.
  CC_PUSH_SEND_BIN="$(mkpush ok)" STUB_SEND_RC=0 CC_ANNOUNCE_BIN="$(mkann ok 0)" \
    "$SELF" --desk >/dev/null 2>"$d/e6"; rc=$?
  [ "$rc" = 0 ] && grep -q 'DESK leg — cc-announce VERIFIED' "$d/e6" && grep -q 'PROBE PASSED' "$d/e6" \
    && okp "--desk + announce verified → both legs PASS (exit 0)" \
    || badp "a verified desk leg did not pass (rc=$rc)"

  # (7) --desk: desk announce fails (alarm) → overall FAIL even though phone was fine.
  CC_PUSH_SEND_BIN="$(mkpush ok)" STUB_SEND_RC=0 CC_ANNOUNCE_BIN="$(mkann bad 5)" \
    "$SELF" --desk >/dev/null 2>"$d/e7"; rc=$?
  [ "$rc" = 5 ] && grep -q 'DESK leg — cc-announce did NOT verify' "$d/e7" \
    && okp "--desk + announce alarmed → PROBE FAILED (exit 5) even with phone OK" \
    || badp "a failed desk leg did not fail the probe (rc=$rc)"

  echo "delivery-verify --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "delivery-verify --selftest: GREEN — the probe fires a synthetic DEAD page and returns a HONEST accepted/unwired/failed verdict."
  exit 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          run_probe "$@" ;;
esac
