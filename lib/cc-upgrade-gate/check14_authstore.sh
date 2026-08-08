#!/usr/bin/env bash
# check14_authstore.sh — #14 Credential-write safety net (the vendor write-loss window).
# ─────────────────────────────────────────────────────────────────────────────
# The way-of-working under test is STAYING LOGGED IN. `forced-relogin-rootcause-2026-08-02.md`
# UPDATE 3 measured an upstream defect we cannot fix: a keychain write that times out (2 s) is
# classified `transient`, which SKIPS the plaintext fallback, while both refresh paths report
# success anyway. It is filed known-open — and a known-open fact that lives only in prose has no
# way to learn it changed.
#
# POLARITY — deliberate, and the reason this probe is not a blocker (memory: alarm-polarity):
#   FIXED      → PASS. News worth acting on: close backlog 4adbeab56aa7.
#   STATUS-QUO → SKIP. The candidate matches the binary we ALREADY RUN. An upstream defect we
#                cannot fix, unchanged, is not a reason to refuse an upgrade — a check that FAILed
#                on it would go red on every candidate forever and carry zero bits.
#   WORSE      → FAIL. The plaintext fallback was REMOVED: a failed keychain write would then have
#                no safety net at all. That is a genuine regression in a way we work.
#   UNREADABLE → FAIL, fail-closed. Every auth-health compensation we run assumes this layer's
#                shape; if it is no longer introspectable, someone must re-derive before we move.
#
# Self-evidencing: the verdict comes from reading the CANDIDATE binary (scripts/cc-authstore-probe.sh),
# never from a recalled fact about 2.1.220. The candidate is READ, never executed.
# shellcheck shell=bash

check_14() {
  local probe out rc verdict axes
  # CC_AUTHSTORE_PROBE mirrors CC_UPGRADE_GATE_CHECKS: the hermetic tests copy this file to a temp
  # dir, where the sibling-relative path cannot resolve. Real runs use the relative path.
  probe="${CC_AUTHSTORE_PROBE:-}"
  if [ -z "$probe" ]; then
    for cand in "$(dirname "${BASH_SOURCE[0]}")/../../scripts/cc-authstore-probe.sh" \
                "$HOME/.claude/scripts/cc-authstore-probe.sh"; do
      [ -f "$cand" ] && { probe="$cand"; break; }
    done
  fi

  if [ -z "$probe" ] || [ ! -f "$probe" ]; then
    emit_result 14 authstore-writeloss FAIL "probe missing: $probe" ""
    return 0
  fi

  out="$(bash "$probe" "$GATE_BIN" 2>/dev/null)"; rc=$?
  verdict="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("verdict","UNREADABLE"))
except Exception: print("UNREADABLE")')"
  axes="$(printf '%s' "$out" | python3 -c 'import json,sys
try:
    a=json.load(sys.stdin)["axes"]
    print("skip=%s fallback=%s timeout=%sms argv>%s" % (a["transient_skip"], a["plaintext_fallback"],
          a["write_timeout_ms"], a["argv_threshold_chars"]))
except Exception: print("unparseable")')"

  case "$verdict" in
    FIXED)
      emit_result 14 authstore-writeloss PASS \
        "vendor CLOSED the write-loss window — a failed keychain write now reaches the fallback" \
        "rc=$rc $axes ⇒ close backlog 4adbeab56aa7, re-read docs/research/vendor-report-cc-authstore-write-loss.md" ;;
    STATUS-QUO)
      emit_result 14 authstore-writeloss SKIP \
        "write-loss window still open, unchanged from the 2.1.220 baseline (known-open upstream, not an upgrade blocker)" \
        "rc=$rc $axes" ;;
    WORSE)
      emit_result 14 authstore-writeloss FAIL \
        "REGRESSION: the plaintext fallback under a failed keychain write is GONE" \
        "rc=$rc $axes" ;;
    *)
      emit_result 14 authstore-writeloss FAIL \
        "credential-store layer not introspectable — cannot certify the write path; re-derive the anchors in scripts/cc-authstore-probe.sh" \
        "rc=$rc $axes" ;;
  esac
  return 0
}
