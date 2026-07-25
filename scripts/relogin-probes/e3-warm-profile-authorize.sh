#!/usr/bin/env bash
# e3-warm-profile-authorize.sh — E3: drive ONE real authorize URL end to end and prove the
# login deadline actually moved.
#
# PROVES THE WHOLE EXECUTOR. E1 and E2 each settle one assumption; E3 is the integration —
# cc-relogin -> cc-authbrowser -> real OAuth -> a later login_expires_at. Nothing else in the
# build demonstrates that the pieces compose.
#   PROVEN     -> the unattended executor works; the poller (§5) may be activated.
#   UNVERIFIED -> cc-relogin claimed success but the deadline did NOT move. Verification is by
#                 EFFECT precisely so this case is caught instead of believed.
#
# HUMAN-GATED: the first moment a real sign-in occurs, and the only probe that spends a real
# re-auth — so rehearse first with `cc-relogin <acct> --dry-run`.
#
# BLOCKED TODAY, USUALLY: login_expires_at does not exist on main (it lands with branch
# feat/accounts-login-cliff). With no deadline to compare, E3 exits 3 DETECTION-UNAVAILABLE
# rather than declare a success it cannot measure.
#
# Usage   e3-warm-profile-authorize.sh [acct]            # refuses; prints plan+rollback
#         CONFIRM=1 e3-warm-profile-authorize.sh [acct]  # runs the real renewal once
# acct defaults to next3.
# Env     CC_PROBE_ACCOUNTS_JSON · CC_PROBE_ACCOUNTS_BIN · CC_PROBE_RELOGIN_BIN ·
#         CC_PROBE_AUTHBROWSER_BIN · CC_PROBE_PROFILE_ROOT · CC_PROBE_ARTIFACT_DIR
# Exit    0 verdict recorded · 1 error · 2 REFUSED (no CONFIRM / precondition) ·
#         3 DETECTION-UNAVAILABLE (contract §2 — never silently "nothing to do")
set -uo pipefail
usage() { awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; }
ACCOUNTS_JSON="${CC_PROBE_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}"
ACCOUNTS_BIN="${CC_PROBE_ACCOUNTS_BIN:-claude-accounts}"
RELOGIN_BIN="${CC_PROBE_RELOGIN_BIN:-cc-relogin}"
AUTHBROWSER_BIN="${CC_PROBE_AUTHBROWSER_BIN:-cc-authbrowser}"
PROFILE_ROOT="${CC_PROBE_PROFILE_ROOT:-$HOME/.claude/auth-profiles}"
ART_DIR="${CC_PROBE_ARTIFACT_DIR:-/tmp}"; ACCT=next3
for a in "$@"; do case "$a" in
  -h|--help) usage; exit 0 ;;
  -*) echo "e3: unknown flag: $a" >&2; exit 2 ;;
  *)  ACCT="$a" ;;
esac; done
python3 -c 'import json,os,sys
d=json.load(open(os.path.expanduser(sys.argv[1])))
sys.exit(0 if any(x["name"]==sys.argv[2] for x in d["accounts"]) else "no such account: "+sys.argv[2])' \
  "$ACCOUNTS_JSON" "$ACCT" || { echo "e3: REFUSED — cannot resolve '$ACCT' in $ACCOUNTS_JSON" >&2; exit 2; }
PROFILE="$PROFILE_ROOT/$ACCT"; ART="$ART_DIR/relogin-probe-e3-$ACCT.json"
emit() { python3 -c 'import json,sys
print(json.dumps(dict(z.split("=",1) for z in sys.argv[1:]), indent=2))' "$@"; }
row() { python3 -c 'import json,sys; d=json.load(sys.stdin)
r=next((x for x in d.get("rows",[]) if x.get("name")==sys.argv[1]),{})
v=r.get(sys.argv[2]); print("" if v is None else v)' "$ACCT" "$1" <<<"$2"; }
teardown() { cat <<EOF
TEARDOWN — E3 creates no durable artifact of its own; it spends a real renewal:
  $AUTHBROWSER_BIN $ACCT --stop    # belt-and-braces: cc-relogin already stops it in a finally
  rm -f '$ART'
A SUCCESSFUL renewal is the desired end state and is NOT rolled back. A FAILED run leaves the
account exactly as it was — cc-relogin never half-writes a credential.
EOF
}
die()    { echo "e3: $*" >&2; teardown; exit 1; }
refuse() { echo "e3: REFUSED — $*" >&2; exit 2; }
cat <<EOF
E3 — warm-profile Authorize, end to end        proves the executor (design §5.1-5.2)
account           $ACCT
executor          $RELOGIN_BIN $ACCT --json
substrate         $AUTHBROWSER_BIN (dedicated Chrome, started + stopped by the executor)
warm profile      $PROFILE   <- must already hold a signed-in claude.ai web session
verdict artifact  $ART       <- created by this experiment
measurement       login_expires_at before vs after (by EFFECT, never by exit code alone)
WILL DO  1. assert k==0, executor+substrate present, profile seeded, and that a login
            deadline is actually READABLE (else exit 3, never a confident "fine")
         2. snapshot login_expires_at
         3. run the executor ONCE, for real — one browser Authorize on $ACCT
         4. re-snapshot; record PROVEN only if the deadline MOVED FORWARD
WON'T DO /logout · POST a refresh token · widen oauth_scopes · retry on failure ·
         touch any account other than $ACCT
COST IF IT GOES WRONG  one spent re-auth on $ACCT and possibly a stray browser (teardown
         below kills it). Rehearse with '$RELOGIN_BIN $ACCT --dry-run' — every gate, free.
EOF
teardown
if [[ "${CONFIRM:-}" != "1" ]]; then
  echo; echo "e3: REFUSED — no browser started, no sign-in performed, no token touched. Re-run with CONFIRM=1." >&2
  exit 2
fi
command -v "$RELOGIN_BIN"     >/dev/null 2>&1 || refuse "$RELOGIN_BIN not on PATH — E3 needs the executor (tm/relogin-exec) installed"
command -v "$AUTHBROWSER_BIN" >/dev/null 2>&1 || refuse "$AUTHBROWSER_BIN not on PATH — E3 needs the substrate (tm/relogin-browser) installed"
[[ -d "$PROFILE" ]] || refuse "no warm profile at $PROFILE — seed it once (sign in to claude.ai in that profile) before E3"
BEFORE_JSON="$("$ACCOUNTS_BIN" --fresh --json 2>/dev/null)" || die "$ACCOUNTS_BIN --fresh --json failed"
K="$(row k "$BEFORE_JSON")"
[[ "$K" == "0" ]] || refuse "k=$K live sessions on $ACCT — E3 needs k==0 (cc-relogin refuses too; failing here is cheaper)"
# §2 version tolerance. NOTE for the ladder's step 1: claude-accounts SILENTLY IGNORES an
# unknown flag and renders its default table with exit 0, so `--login-status` presence cannot
# be probed by exit code. The reliable surface test is whether the field exists in --json —
# and the field is what E3 needs anyway, since --login-status only enumerates accounts already
# DUE and so yields no value for an account that is not.
BEFORE_EXP="$(row login_expires_at "$BEFORE_JSON")"
if [[ -z "$BEFORE_EXP" ]]; then
  echo "e3: DETECTION-UNAVAILABLE — no login_expires_at for $ACCT in '$ACCOUNTS_BIN --fresh --json'," >&2
  echo "    and --login-status cannot be probed by exit code. That surface lands with branch" >&2
  echo "    feat/accounts-login-cliff; until it does, E3 cannot measure the effect it must prove." >&2
  echo "    Refusing to run a real re-auth whose result would be unverifiable." >&2
  emit experiment=E3 acct="$ACCT" verdict="DETECTION-UNAVAILABLE" \
       decides="E3 is BLOCKED until claude-accounts exposes login_expires_at (branch feat/accounts-login-cliff). Do NOT record a PROVEN verdict from a green exit code alone." > "$ART"
  teardown; exit 3
fi
echo; echo "before: login_expires_at=$BEFORE_EXP  k=$K"
echo "running: $RELOGIN_BIN $ACCT --json"
RESULT="$("$RELOGIN_BIN" "$ACCT" --json 2>&1)"; RC=$?
echo "$RESULT"
AFTER_EXP="$(row login_expires_at "$("$ACCOUNTS_BIN" --fresh --json 2>/dev/null)")"
# The field's TYPE is unverified (it lands with feat/accounts-login-cliff), so accept epoch
# numbers AND ISO-8601 — and say "unparseable" rather than silently reporting "did not move",
# which would fail a genuinely successful renewal and wrongly block the cadence.
MOVED="$(python3 -c 'import sys
from datetime import datetime as D
def p(s):
    try: return float(s)
    except ValueError: return D.fromisoformat(s.replace("Z","+00:00")).timestamp()
try: print("yes" if p(sys.argv[1]) > p(sys.argv[2]) else "no")
except Exception: print("unparseable")' "${AFTER_EXP:-}" "$BEFORE_EXP" 2>/dev/null)"
MOVED="${MOVED:-unparseable}"
if [[ "$RC" == 0 && "$MOVED" == yes ]]; then
  VERDICT=PROVEN; DECIDES="the unattended executor works end to end — cadence (§5) and observability (§6) may be activated."
elif [[ "$RC" == 0 ]]; then
  VERDICT=UNVERIFIED; DECIDES="cc-relogin exited 0 but login_expires_at did not verifiably move: $BEFORE_EXP -> ${AFTER_EXP:-unreadable} (moved=$MOVED). Its verify-by-EFFECT gate is not doing its job — fix that BEFORE any cadence is activated."
elif [[ "$RC" == 7 ]]; then
  VERDICT="CONSENT-GATE"; DECIDES="exit 7 is supposed to be structurally impossible on the dedicated-profile substrate. The §5.1 substrate premise is WRONG — stop and re-open the design."
else
  VERDICT="FAILED-rc$RC"; DECIDES="executor exit $RC (frozen §4: 1 ERROR · 2 REFUSED · 3 HEADLESS-EXHAUSTED · 4 BROWSER-FAILED · 5 UNVERIFIED · 6 FALLBACK-REQUIRED). Record the code verbatim — it names which stage broke."
fi
emit experiment=E3 acct="$ACCT" verdict="$VERDICT" decides="$DECIDES" executor_exit="$RC" \
     before_login_expires_at="$BEFORE_EXP" after_login_expires_at="${AFTER_EXP:-}" \
     deadline_moved="$MOVED" executor_output="$RESULT" | tee "$ART"
echo; echo "E3 VERDICT: $VERDICT — $DECIDES"
echo "artifact: $ART   (transcribe into docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md)"
teardown
