#!/bin/bash
# shellcheck disable=SC2015  # the selftest's `[ test ] && … || …` reporter idiom is intentional.
#
# payload-lint — F3 of the never-let-completion-go-silent bar (scripts/comms-safety-gate.sh). Lints a
# SUCCESSOR-FIRE PAYLOAD (a /tmp/fire-*.txt or a handoff prompt) for the BACK-CHANNEL BLOCK — the ROOT of
# the W5 incident.
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# W5's successor-fire payload DROPPED the back-channel block (the cc-notify line + the desk full-uuid), so
# the successor had no VERIFIED channel to the desk; its terminal announce fell back to SendMessage (a
# teammate-scope, UNRESOLVABLE target for the desk) and SILENTLY degraded to disk-truth — the desk learned
# of the ship 50 min late FROM THE OPERATOR. A payload without the back-channel block IS that bug waiting to
# happen. This lint makes it RED.
#
# THE RULE (two checks):
#   F3    BACK-CHANNEL BLOCK — the payload MUST carry a cc-notify reference AND a full desk uuid
#         (8-4-4-4-12). Missing EITHER → RED (a successor cannot announce).
#   F3/a  (serves F2) NO TERMINAL-ANNOUNCE VIA SendMessage — a line PRESCRIBING SendMessage for a terminal /
#         desk / orchestrator / operator announce is the W5 bug (SendMessage is teammate-scope only). A
#         PROHIBITION ('never SendMessage the desk') is fine — the lint distinguishes prescriptive from
#         proscriptive (the s3b-lint 'a comment is not the action' trap).
#
# THIS IS A STATIC PROXY (like s3b-lint): it faithfully discriminates the registered fixtures; it is NOT
# adversarial-obfuscation-proof, and it DECLARES that rather than rotting into false confidence. When the
# real fire-payload templates are authored, they must PASS this by construction, not by out-grepping it.
#
#   payload-lint.sh <payload-file>   lint one payload
#   payload-lint.sh --selftest       RED-prove: block-less → RED; SendMessage terminal → RED; well-formed →
#                                    GREEN (prohibition tolerated); missing file → LOUD(2)
#
# Exit: 0 = back-channel block present, no SendMessage terminal-announce (GREEN)
#       1 = block missing OR a SendMessage terminal-announce present (RED)
#       2 = cannot determine (missing/empty file) — LOUD, never a silent 0 (the D9 law: an indeterminate
#           check that passes is indistinguishable from a working one)
set -uo pipefail

UUID='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
SENDMSG='SendMessage'
# non-teammate TERMINAL targets/events — the scope F2/a forbids over SendMessage.
ANN='desk|orchestrator|operator|terminal|ship-witness|succession|program-complete'
# prohibition / documentation markers — a line carrying one is guidance, not a prescription.
NEGATION='never|not a teammate|unresolv|do ?n.?t|does ?n.?t|avoid|degrad|silent|teammate-scope|instead of|rather than|WRONG|bug|forbidden|prohibit'

lint_file() {
  local pf="$1"
  [ -n "$pf" ] && [ -f "$pf" ] && [ -s "$pf" ] || { echo "payload-lint: CANNOT DETERMINE — no readable payload '$pf'"; return 2; }
  local fail=0 has_cc has_uuid presc
  grep -qE 'cc-notify' "$pf" && has_cc=1 || has_cc=0
  grep -qE "$UUID"     "$pf" && has_uuid=1 || has_uuid=0
  # F3 — the back-channel block: a cc-notify line AND a full desk uuid, both present.
  if [ "$has_cc" = 0 ] || [ "$has_uuid" = 0 ]; then
    echo "  RED  F3   BACK-CHANNEL BLOCK missing — cc-notify line: $([ "$has_cc" = 1 ] && echo present || echo ABSENT); desk full-uuid: $([ "$has_uuid" = 1 ] && echo present || echo ABSENT). A successor cannot announce (the W5 root)."
    fail=1
  fi
  # F3/a — a PRESCRIPTIVE terminal-announce via SendMessage (a prohibition is filtered out by NEGATION).
  presc="$(grep -nE "$SENDMSG" "$pf" 2>/dev/null | grep -iE "$ANN" | grep -ivE "$NEGATION" || true)"
  if [ -n "$presc" ]; then
    echo "  RED  F3/a a terminal-announce via SendMessage (teammate-scope → UNRESOLVABLE for the desk; the W5 degrade):"
    printf '           %s\n' "$presc"
    fail=1
  fi
  [ "$fail" -eq 0 ] && { echo "  OK   F3   back-channel block present (cc-notify + desk full-uuid); no SendMessage terminal-announce"; return 0; }
  return 1
}

# ── --selftest: SEE F3 fire. RED on a block-less payload AND on a SendMessage terminal-announce; GREEN on a
# well-formed one (a prohibition line must NOT false-RED — the prescriptive/proscriptive discriminator);
# LOUD on a missing file. Every assertion TRAPS (a bare conditional that does not fail LOUD is dead). ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  DESK='99261468-A46A-498A-AE9B-F39473E5E7AE'

  # (1) MISSING BLOCK — succession instructions but NO cc-notify + NO uuid (the exact W5 drop) → RED.
  cat >"$d/missing.txt" <<EOF
SUCCESSOR FIRE — continue the build from the registered gate. Reload the plan, run
the gate unpiped, build the next artifact, ship at a green boundary.
(No back-channel block — exactly the W5 drop.)
EOF

  # (2) PRESENT BLOCK — carries the cc-notify line + the desk full-uuid, and a PROHIBITION line that must
  #     NOT false-RED (the prescriptive-vs-proscriptive discriminator) → GREEN.
  cat >"$d/present.txt" <<EOF
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: announce to the desk ONLY via cc-notify $DESK, VERIFIED (submit-confirmed).
NEVER SendMessage — the desk is NOT a teammate (SendMessage silently degrades to disk-truth).
EOF

  # (3) SendMessage TERMINAL — has the block (check 1 passes) but PRESCRIBES SendMessage → RED via F3/a only.
  cat >"$d/sendmsg.txt" <<EOF
SUCCESSOR FIRE — continue the build.
BACK-CHANNEL: cc-notify $DESK is the desk address.
On ship, announce the ship-witness to the desk via SendMessage.
EOF

  fails=0
  expect() { # <file> <want-rc> <label>  — capture the code directly (no `[ $? ]`, per SC2181)
    lint_file "$1" >/dev/null 2>&1; local got=$?
    [ "$got" -eq "$2" ] || { echo "SELFTEST FAIL: $3 (got $got, want $2)"; fails=1; }
  }
  expect "$d/missing.txt" 1 "block-less payload did not go RED"
  expect "$d/present.txt" 0 "well-formed payload did not go GREEN (a prohibition false-RED'd?)"
  expect "$d/sendmsg.txt" 1 "a SendMessage terminal-announce did not go RED"
  expect "$d/absent.txt"  2 "a missing file did not exit 2 (LOUD)"
  if [ "$fails" -eq 0 ]; then
    echo "payload-lint --selftest: 4/4 — RED on a block-less payload, RED on a SendMessage terminal-announce, GREEN on a well-formed one (prohibition tolerated), LOUD on missing."
    exit 0
  fi
  echo "payload-lint --selftest: FAILED — the lint does not discriminate (do not trust F3)."
  exit 1
fi

lint_file "${1:-}"
exit $?
