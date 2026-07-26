#!/usr/bin/env bash
# e1-concurrent-logins.sh — E1: does a SECOND full-scope login for one account (into a
# different CLAUDE_CONFIG_DIR) invalidate the FIRST?
#
# ★ HIGHEST-VALUE PROBE — it decides the single open operator decision (design §4.4), and
#   Phase 5 (de-sharing) cannot start without the verdict:
#     COEXIST     -> VARIANT A: per-slot CLAUDE_CONFIG_DIR isolation, FULL SCOPE everywhere.
#     INVALIDATED -> VARIANT B: setup-token supplement — those sessions become inference-only
#                    (no Remote Control, no hosted connectors). A real capability boundary.
# Mechanism under test: the keychain item is "Claude Code-credentials-<sha256(CFG_DIR)[:8]>",
# so a distinct config dir already yields a distinct credential item LOCALLY; what is unknown
# is the SERVER side — whether the vendor keeps only one active login per account.
#
# HUMAN-GATED: two real `claude auth login` runs happen here. This script pauses and hands you
# the exact command each time; it NEVER signs in for you and never touches a token itself.
# Usage   e1-concurrent-logins.sh [acct]                       # refuses; prints plan+rollback
#         CONFIRM=1 e1-concurrent-logins.sh [acct]             # runs it (interactive tty)
#         CONFIRM=1 e1-concurrent-logins.sh [acct] --recheck   # re-observe later (T+24h)
# acct defaults to next3 — already logged out, so E1 costs nothing not already lost.
# Env     CC_PROBE_ACCOUNTS_JSON · CC_PROBE_ACCOUNTS_BIN · CC_PROBE_ARTIFACT_DIR
# Exit    0 verdict recorded · 1 error · 2 REFUSED (no CONFIRM, or a precondition failed)
set -uo pipefail
usage() { awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; }
ACCOUNTS_JSON="${CC_PROBE_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}"
ACCOUNTS_BIN="${CC_PROBE_ACCOUNTS_BIN:-claude-accounts}"
ART_DIR="${CC_PROBE_ARTIFACT_DIR:-/tmp}"
ACCT=next3; RECHECK=0
for a in "$@"; do case "$a" in
  -h|--help) usage; exit 0 ;;
  --recheck) RECHECK=1 ;;
  -*) echo "e1: unknown flag: $a" >&2; exit 2 ;;
  *)  ACCT="$a" ;;
esac; done
IDENT="$(python3 - "$ACCOUNTS_JSON" "$ACCT" <<'PY'
import json, os, sys
d = json.load(open(os.path.expanduser(sys.argv[1])))
a = next((x for x in d["accounts"] if x["name"] == sys.argv[2]), None)
if a is None:
    sys.exit("no such account: " + sys.argv[2])
fields = [os.path.expanduser(a["config_dir"]), a["email"],
          d["keychain_account"], os.path.expanduser(d["claude_bin"])]
# REFUSE on an empty identity field rather than emit it. The reader is `IFS=$'\t' read`, and tab is
# IFS-*whitespace*: an empty cell does not yield an empty variable, it shifts every later field one
# position LEFT. An account with a blank `email` would put keychain_account into $EMAIL and the
# claude binary into $KC_ACCT, so kc_svc() would hash the wrong string and every keychain lookup in
# this probe would silently address the wrong service. These four are all REQUIRED identity values,
# so failing loud is right where padding would only make a wrong run look plausible.
# See docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md.
names = ["config_dir", "email", "keychain_account", "claude_bin"]
empty = [n for n, v in zip(names, fields) if not str(v).strip()]
if empty:
    sys.exit("empty identity field(s) for '%s': %s" % (sys.argv[2], ", ".join(empty)))
print("\t".join(fields))
PY
)" || { echo "e1: REFUSED — cannot resolve '$ACCT' in $ACCOUNTS_JSON" >&2; exit 2; }
IFS=$'\t' read -r PRIMARY_DIR EMAIL KC_ACCT CLAUDE_BIN <<<"$IDENT"
kc_svc() { printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"; }
kc_has() { /usr/bin/security find-generic-password -s "$1" -a "$KC_ACCT" >/dev/null 2>&1 \
           && echo present || echo absent; }   # metadata probe only — never reads the secret
row()    { python3 -c 'import json,sys; d=json.load(sys.stdin)
r=next((x for x in d.get("rows",[]) if x.get("name")==sys.argv[1]),{})
print(r.get(sys.argv[2],""))' "$ACCT" "$1" <<<"$2"; }
emit()   { python3 -c 'import json,sys
print(json.dumps(dict(z.split("=",1) for z in sys.argv[1:]), indent=2))' "$@"; }
SLOT_DIR="${PRIMARY_DIR}-e1probe"; ART="$ART_DIR/relogin-probe-e1-$ACCT.json"
PRIMARY_SVC="$(kc_svc "$PRIMARY_DIR")"; SLOT_SVC="$(kc_svc "$SLOT_DIR")"
teardown() { cat <<EOF
TEARDOWN — reverses everything E1 creates (run once the verdict is transcribed):
  /usr/bin/security delete-generic-password -s '$SLOT_SVC' -a '$KC_ACCT'
  rm -rf '$SLOT_DIR' ; rm -f '$ART'
The primary store ($PRIMARY_DIR) is LEFT LOGGED IN — that is the desired end state.
EOF
}
die()    { echo "e1: $*" >&2; teardown; exit 1; }
refuse() { echo "e1: REFUSED — $*" >&2; exit 2; }
pause()  { echo; echo "▶ RUN THIS in another terminal, then press ENTER here:"; echo "    $1"; echo
           [[ -t 0 ]] || die "not a tty — E1's human-gated steps need an interactive terminal"
           read -r _; }

cat <<EOF
E1 — concurrent same-account logins        decides design §4.4 (Variant A vs Variant B)
account           $ACCT  ($EMAIL)
primary store     $PRIMARY_DIR   keychain: $PRIMARY_SVC
probe slot store  $SLOT_DIR   keychain: $SLOT_SVC      <- BOTH created by this experiment
verdict artifact  $ART                                 <- created by this experiment
login binary      $CLAUDE_BIN
WILL DO  1. assert k==0 and snapshot the primary's auth state
         2. hand you the exact 'auth login' for the PRIMARY store (logged out today;
            restoring it is wanted regardless of the verdict)
         3. hand you the exact 'auth login' for the PROBE SLOT store
         4. re-read the primary and record COEXIST / INVALIDATED
WON'T DO sign in for you · /logout · POST a refresh token · widen oauth_scopes ·
         touch any account other than $ACCT
COST IF IT GOES WRONG  the worst case IS the verdict: the primary login is invalidated by the
         second. $ACCT is already logged out, so nothing is lost that is not already lost, and
         recovery is one more 'auth login' into $PRIMARY_DIR.
EOF
teardown
if [[ "${CONFIRM:-}" != "1" ]]; then
  echo; echo "e1: REFUSED — nothing read, created, or signed in. Re-run with CONFIRM=1." >&2
  exit 2
fi
# Our sha derivation must agree with claude-accounts' authoritative one, or we would be
# watching the wrong keychain item and every verdict below would be fiction.
AUTH_SVC="$("$ACCOUNTS_BIN" --relogin-info "$ACCT" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("keychain_service",""))' 2>/dev/null)"
[[ -n "$AUTH_SVC" && "$AUTH_SVC" != "$PRIMARY_SVC" ]] \
  && refuse "keychain derivation mismatch: mine=$PRIMARY_SVC theirs=$AUTH_SVC"
BEFORE="$("$ACCOUNTS_BIN" --fresh --json 2>/dev/null)" || die "$ACCOUNTS_BIN --fresh --json failed"
K="$(row k "$BEFORE")"; BEFORE_AUTH="$(row auth "$BEFORE")"
[[ "$K" == "0" ]] || refuse "k=$K live sessions on $ACCT — E1 needs k==0 (a live session rotates tokens under us)"
if [[ "$RECHECK" == 0 ]]; then
  [[ -e "$SLOT_DIR" ]] && refuse "$SLOT_DIR exists — tear the previous run down or E1 is not testing a fresh slot"
  echo "before: auth=$BEFORE_AUTH  k=$K  primary keychain=$(kc_has "$PRIMARY_SVC")"
  pause "CLAUDE_CONFIG_DIR='$PRIMARY_DIR' '$CLAUDE_BIN' auth login --claudeai --email '$EMAIL'"
  [[ "$(kc_has "$PRIMARY_SVC")" == present ]] || die "primary keychain item still absent — the first login did not complete"
  pause "mkdir -p '$SLOT_DIR' && CLAUDE_CONFIG_DIR='$SLOT_DIR' '$CLAUDE_BIN' auth login --claudeai --email '$EMAIL'"
else
  [[ -d "$SLOT_DIR" ]] || refuse "--recheck with no slot store at $SLOT_DIR — run E1 first"
fi
# Raw first (--no-heal): the primary exactly as the second login left it. Then heal-allowed: a
# successful refresh proves the primary's refresh CHAIN survived (the strongest Variant-A
# evidence), invalid_grant proves revocation. Raw alone cannot tell "revoked" from "access
# token merely expired" — which is why both are recorded.
SLOT_KC="$(kc_has "$SLOT_SVC")"
RAW="$(row auth "$("$ACCOUNTS_BIN" --fresh --no-heal --json 2>/dev/null)")"
HEALED="$(row auth "$("$ACCOUNTS_BIN" --fresh --json 2>/dev/null)")"
PRIMARY_KC="$(kc_has "$PRIMARY_SVC")"
if [[ "$SLOT_KC" != present ]]; then
  VERDICT=INCONCLUSIVE; DECIDES="the slot login never landed its own keychain item — E1 did not test what it claims. Re-run."
elif [[ "$PRIMARY_KC" != present ]]; then
  VERDICT=INVALIDATED;  DECIDES="VARIANT B — the second login DELETED the primary's credential item."
else case "$HEALED" in
  ok|healed) VERDICT=COEXIST; DECIDES="VARIANT A — per-slot CLAUDE_CONFIG_DIR isolation, full scope in every slot. Phase 5 may proceed." ;;
  logged-out|token-invalid) VERDICT=INVALIDATED; DECIDES="VARIANT B — one active login per account; refresh-free setup-token sessions are the only way out of the racing set (inference-only)." ;;
  *) VERDICT=INCONCLUSIVE; DECIDES="auth=$HEALED is neither clear survival nor clear revocation — record it verbatim and re-observe with --recheck." ;;
esac; fi
emit experiment=E1 acct="$ACCT" verdict="$VERDICT" decides="$DECIDES" \
     before_auth="$BEFORE_AUTH" after_auth_no_heal="$RAW" after_auth_healed="$HEALED" \
     primary_keychain="$PRIMARY_KC" slot_keychain="$SLOT_KC" \
     primary_dir="$PRIMARY_DIR" slot_dir="$SLOT_DIR" recheck="$RECHECK" | tee "$ART"
echo "E1 VERDICT: $VERDICT — $DECIDES"
echo "artifact: $ART   (transcribe into docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md)"
teardown
