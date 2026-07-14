#!/bin/bash
# s3b-lint — premortem-gate criterion S-3b (desk-registered 2026-07-14, proven by a live incident).
#
# THE RULE: the supervisor's page path MUST encode deadline→RE-OBSERVATION. The disposition branch
# (reap / close / escalate-to-recover a lead) must be reachable ONLY through a fresh effects-dark
# RE-READ, NEVER from deadline-silence alone — reply-compliance is NOT a liveness signal (a busy lead
# ignores pages). Audit §3h, the first live stall-page cycle: a lead ran all four D10 signals dark for
# 69-75 min, the page deadline expired with NO REPLY, and the mandatory effect re-read found it ALIVE +
# productive. A reply-or-kill deadline ALONE would have killed a healthy wave lead mid-work.
#
# THIS IS A STATIC PROXY for a control-flow property grep cannot fully prove — and the desk's own warning
# names the trap: "review criteria rot toward their grep the same way checks rot toward their spine." So:
# it faithfully discriminates an HONEST silence-reaps straw-supervisor from an HONEST re-observe one (the
# registered negative fixture); it is NOT adversarial-obfuscation-proof, and it declares that rather than
# rotting into false confidence. When the real supervisor is built, it must PASS this by construction, not
# by out-grepping it.
#
# Exit: 0 = disposition gated by a re-observe / effects-dark re-read (GREEN)
#       1 = disposition reachable from deadline-silence alone, OR no re-read gate at all (RED)
#       2 = cannot determine (missing/empty file) — LOUD, never a silent 0 (the D9 law: an
#           indeterminate check that passes is indistinguishable from a working one)
set -uo pipefail

DISPOSE='reap|kill|close|dispose|escalat|recover|self-close|TaskStop'
SILENCE='no.?repl|no.?answer|silence|unanswered|deadline.{0,20}(expir|elaps|pass)|timed?.?out|timeout'
REREAD='re-?observ|re-?read|reobserv|effects?.?dark|effect.?re-?read'

lint_file() {
  local sup="$1"
  [ -n "$sup" ] && [ -f "$sup" ] && [ -s "$sup" ] || { echo "s3b-lint: CANNOT DETERMINE — no readable supervisor file '$sup'"; return 2; }
  # strip whole-line comments so a '# never reap on silence' remark is not read as code — the exact bug
  # reaper-horizon-lint.sh shipped with (a grep hit is file:line:CONTENT, so comments read as code).
  local code; code="$(grep -vE '^[[:space:]]*#' "$sup")"
  local fail=0
  if printf '%s\n' "$code" | grep -qiE "(${SILENCE}).{0,40}(${DISPOSE})|(${DISPOSE}).{0,40}(${SILENCE})"; then
    echo "  RED  S-3b  disposition on the same line as a silence trigger — a '<silence> -> <dispose>' shortcut; would kill a healthy long turn"
    fail=1
  fi
  if ! printf '%s\n' "$code" | grep -qiE "${REREAD}"; then
    echo "  RED  S-3b  no re-observe / effects-dark re-read gate present — the disposition has nothing to gate on but silence"
    fail=1
  fi
  [ "$fail" -eq 0 ] && { echo "  OK   S-3b  disposition gated by a fresh effects-dark re-read; not reachable from silence alone"; return 0; }
  return 1
}

# --selftest: PROVE the assertion discriminates (the desk's "SEE it fire RED"). Builds the registered
# negative fixture (a minimal silence-reaps straw), a positive fixture (re-observe-gated), and the
# indeterminate case; asserts RED / GREEN / LOUD. Every assertion TRAPS (harness law L3: a bare
# conditional that does not exit on mismatch is a dead assertion).
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  cat >"$d/straw.sh" <<'STRAW'
#!/bin/bash
# a MINIMAL silence-reaps straw-supervisor (the registered negative fixture): it disposes on silence.
sweep_lead() {
  page_lead "$1" --deadline 15m
  if [ "$(await_reply "$1")" = "no_reply" ]; then reap_lead "$1"; fi   # <- the bug: silence -> reap
}
STRAW
  cat >"$d/correct.sh" <<'GOOD'
#!/bin/bash
# a correct supervisor: the page deadline triggers a RE-READ, and disposition gates on effects-dark only.
sweep_lead() {
  page_lead "$1" --deadline 15m
  await_reply "$1" || true                       # reply-compliance is NOT liveness; ignore the answer
  effects="$(reobserve_effects "$1")"            # mandatory effect re-read at the deadline
  if [ "$effects" = "dark" ]; then dispose_lead "$1"; fi   # disposition gates on the re-read, not silence
}
GOOD
  fails=0
  lint_file "$d/straw.sh"   >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: straw (silence-reaps) did not go RED"; fails=1; }
  lint_file "$d/correct.sh" >/dev/null 2>&1; [ "$?" -eq 0 ] || { echo "SELFTEST FAIL: correct (re-observe) did not go GREEN"; fails=1; }
  lint_file "$d/absent.sh"  >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: missing file did not exit 2 (LOUD)"; fails=1; }
  if [ "$fails" -eq 0 ]; then
    echo "s3b-lint --selftest: 3/3 — RED on the silence-reaps straw, GREEN on re-observe, LOUD on missing."
    exit 0
  fi
  echo "s3b-lint --selftest: FAILED — the assertion does not discriminate (do not trust S-3b)."
  exit 1
fi

lint_file "${1:-}"
exit $?
