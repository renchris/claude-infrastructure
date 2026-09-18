#!/usr/bin/env bash
# union-alpha-route-probe.sh — can we reach union-alpha on a given route, and is it free there?
#
# ROUTES (measured 2026-09-18, each negative-controlled so the check can say no):
#   cf   Cloudflare  `stealth/union-alpha` — STILL LISTED (1 of 161 catalogue ids).
#                    Free BY EXAMPLE (every published sample returns "cost": 0) but Cloudflare
#                    publishes no price and states no end date.
#   zen  OpenCode Zen `union-alpha` — listed as "Union Alpha Free". The ONLY route that calls
#                    it free IN ITS OWN WORDS. Speaks the ANTHROPIC MESSAGES schema.
#   (OpenRouter retired the alias at reveal — 404 — and its successor unbiased/pareto BILLS,
#    measured at $0.0094 over 13 calls. That route is closed; this tool does not offer it.)
#
# WHY THIS EXISTS. OpenRouter retired the `stealth/union-alpha` alias at reveal (404, "This
# model WAS Unbiased's Pareto") and its successor bills. Measured 2026-09-18, CLOUDFLARE STILL
# LISTS `stealth/union-alpha` — 1 of 161 catalogue ids, negative-controlled (a nonsense model
# path 404s, so the instrument can say no). So the Cloudflare route is a genuinely different
# question, not a retry of the same one.
#
# THE ONE QUESTION IT ANSWERS is the UNKNOWN that A2-cloudflare.md could not close by reading:
#   Cloudflare's REST-API doc says "Ensure your Cloudflare account has sufficient credits
#   loaded before calling third-party models" — but union-alpha's every published example
#   returns "cost": 0. Is a ZERO-COST model actually gated on a non-zero balance?
# Only a call can tell. On OpenRouter the analogous answer was YES-for-variable-priced and
# NO-for-explicitly-zero — do NOT assume it carries over. That is what this measures.
#
# SAFETY. Read-only. It sends ONE tiny completion. It writes no config, no credential, no
# allowlist entry — it PRINTS what you must run and stops, because permission grants and
# egress allowlists are the operator's, never an agent's to script.
#
# USAGE (the token is read from the ENVIRONMENT only, never argv — argv is world-readable):
#   agent-secrets run -- bash cf-union-alpha-probe.sh
set -uo pipefail

ROUTE="${1:-cf}"
case "$ROUTE" in
  cf)  MODEL="stealth/union-alpha"; KEYVAR="CLOUDFLARE_API_TOKEN"; HOST="api.cloudflare.com" ;;
  zen) MODEL="union-alpha";         KEYVAR="OPENCODE_ZEN_API_KEY"; HOST="opencode.ai" ;;
  *)   printf 'usage: %s [cf|zen]\n' "$0" >&2; exit 64 ;;
esac
say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
note() { printf '    → %s\n' "$*"; }

say "== preconditions =="
missing=0

KEYVAL="$(eval printf '%s' "\"\${${KEYVAR}:-}\"")"
if [ -n "$KEYVAL" ]; then
  ok "$KEYVAR present in env (${#KEYVAL} chars; value never printed)"
else
  bad "$KEYVAR not in the environment"
  note "store it once (hidden input, tty-gated — an agent cannot do this):"
  note "    agent-secrets add $KEYVAR"
  if [ "$ROUTE" = cf ]; then
    note "token needs: Account > Workers AI > Read  (dash.cloudflare.com > My Profile > API Tokens)"
  else
    note "get it by logging in to OpenCode Zen: opencode.ai/docs/zen/ — 'You login to OpenCode"
    note "Zen and get your API key.' It is optional for OpenCode itself; we need it for the API."
  fi
  note "then re-run:  agent-secrets run -- bash $0 $ROUTE"
  missing=$((missing+1))
fi

ACCT="${CLOUDFLARE_ACCOUNT_ID:-}"
if [ "$ROUTE" = cf ]; then
  if [ -n "$ACCT" ]; then
    ok "CLOUDFLARE_ACCOUNT_ID present (${ACCT:0:6}…)"
  else
    bad "CLOUDFLARE_ACCOUNT_ID not set"
    note "not secret, but keep it beside the token: agent-secrets add CLOUDFLARE_ACCOUNT_ID"
    note "find it at: dash.cloudflare.com → any domain → right sidebar 'Account ID'"
    missing=$((missing+1))
  fi
else
  ok "no account id needed on the zen route"
fi

ALLOW="$HOME/.config/secrets/egress.allow"
if [ -f "$ALLOW" ] && grep -qx "$HOST" "$ALLOW" 2>/dev/null; then
  ok "$HOST is on the egress allowlist"
else
  bad "$HOST is NOT on the egress allowlist"
  note "agent-secrets run proxies HTTPS and refuses non-allowlisted hosts, so the call dies"
  note "with 'Tunnel connection failed: 403'. This line is YOURS to add — an agent may not"
  note "widen its own egress:"
  note "    echo $HOST >> $ALLOW"
  missing=$((missing+1))
fi

[ "$missing" -ne 0 ] && { say ""; say "== stopped: $missing precondition(s) above. Nothing was sent. =="; exit 2; }

if [ "$ROUTE" = cf ]; then
  URL="https://api.cloudflare.com/client/v4/accounts/${ACCT}/ai/v1/chat/completions"
  body=$(printf '{"model":"%s","max_tokens":24,"messages":[{"role":"user","content":"Reply with exactly the word READY and nothing else."}]}' "$MODEL")
else
  # Anthropic Messages schema — NOT chat/completions. `system` would be top-level; we send none.
  URL="https://opencode.ai/zen/v1/messages"
  body=$(printf '{"model":"%s","max_tokens":24,"messages":[{"role":"user","content":"Reply with exactly the word READY and nothing else."}]}' "$MODEL")
fi
say ""
say "== probing $MODEL =="
say "   POST $URL"

resp_file=$(mktemp); code=$(curl -sS -o "$resp_file" -w '%{http_code}' -X POST "$URL" \
  -H "Authorization: Bearer ${KEYVAL}" \
  -H 'Content-Type: application/json' --data "$body" --max-time 120 2>"$resp_file.err")
rc=$?

say ""
if [ "$rc" -ne 0 ]; then
  bad "curl failed (rc=$rc) — a transport fault, NOT a verdict about pricing"
  sed -n '1,4p' "$resp_file.err"; rm -f "$resp_file" "$resp_file.err"; exit 1
fi

say "== HTTP $code =="
python3 - "$resp_file" "$code" <<'PY'
import json, sys
body = open(sys.argv[1]).read(); code = sys.argv[2]; route = sys.argv[3]
try: d = json.loads(body)
except Exception: print("  (non-JSON body)"); print("  " + body[:400]); sys.exit(0)
if code == "200":
    if route == "zen":       # Messages API: content is a LIST OF BLOCKS, text blocks only
        txt = "".join(b.get("text","") for b in (d.get("content") or [])
                      if isinstance(b, dict) and b.get("type") == "text")
    else:
        txt = ((d.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    print("  text  :", repr(txt[:80]))
    print("  model :", d.get("model"))
    u = d.get("usage") or {}
    print("  usage :", json.dumps(u))
    cost = u.get("cost")
    print()
    if cost in (0, 0.0, "0"):
        print("  ⇒ REACHABLE and the response reports cost 0.")
        print("    NOT YET PROVEN FREE: a per-response cost field is what the provider")
        print("    REPORTS. On OpenRouter the account counter lagged >35s and a per-call")
        print("    cost of 0 is not the same as an account delta of 0. Check the Cloudflare")
        print("    billing dashboard after a settle before calling this free.")
    else:
        print(f"  ⇒ REACHABLE and BILLED: reported cost {cost!r}. Not free on this route.")
else:
    errs = d.get("errors") or d.get("error") or d
    print("  error:", json.dumps(errs)[:500])
    print()
    print("  Read the CODE, not the prose: 10000 = auth/permission (token lacks")
    print("  Workers AI > Read); a credits/billing message answers A2's UNKNOWN as")
    print("  'yes, a zero-cost third-party model IS gated on a loaded balance'.")
PY
rm -f "$resp_file" "$resp_file.err"
