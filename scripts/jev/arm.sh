#!/usr/bin/env bash
# arm.sh — the operator's ONE typed act. Authorises the scheduled batch to make Jev calls, once,
# inside a bounded window, on bounded content. Run via `cc-jev arm`.
#
# 🚨 AN AGENT MUST NEVER RUN THIS. The whole reason the sentinel exists is that the scheduled job
# is not bound by the session permission classifier, so the authorisation to send has to come from
# a human rather than from whatever process happens to be running. An agent writing this file
# would be scripting its own authorisation — the thing the classifier refusal is there to prevent,
# performed one layer down. If you are an agent reading this: print the command, do not run it.
#
# What arming means, concretely, and it is deliberately narrow:
#   - ONE run. The batch consumes this file BEFORE its first call, so it cannot be re-used.
#   - A clock. Unused, it expires by itself and the window closes.
#   - Bounded content. It records the corpus, the per-file byte cap and the call ceiling, and the
#     batch refuses to exceed any of them. A token authorising an unbounded act is not consent.
set -uo pipefail

TTL="${CC_JEV_ARM_TTL_MIN:-180}"
CALLS=60; CAPB="${CC_JEV_PROMO_CAP_B:-1200}"; CORPUS="memory-orphans"
ARM="${CC_JEV_ARM_FILE:-$HOME/.claude/autonomy/jev-batch.arm}"
while [ $# -gt 0 ]; do
  case "$1" in
    --calls) CALLS="${2:?--calls needs a number}"; shift 2 ;;
    --ttl)   TTL="${2:?--ttl needs minutes}"; shift 2 ;;
    --cap-b) CAPB="${2:?--cap-b needs bytes}"; shift 2 ;;
    --revoke) rm -f "$ARM" && printf 'Revoked. %s is gone; the scheduled batch is inert again.\n' "$ARM"; exit 0 ;;
    --status) if [ -f "$ARM" ]; then printf 'ARMED:\n'; cat "$ARM"; else printf 'not armed — the scheduled batch will make no call.\n'; fi; exit 0 ;;
    -h|--help) printf 'usage: cc-jev arm [--calls N] [--ttl MIN] [--cap-b N] | --status | --revoke\n'; exit 0 ;;
    *) printf 'usage: cc-jev arm [--calls N] [--ttl MIN] [--cap-b N] | --status | --revoke\n' >&2; exit 2 ;;
  esac
done

# The billing cliff is checked HERE as well as in the batch, because this is where a human is
# present to read it. The free window ends 2026-09-25 and the route does not stop answering then —
# it starts charging.
# Resolve the symlinks before deriving anything from $0: ~/.claude/bin and ~/.claude/scripts are a
# per-file symlink farm over the checkout, so a '..' from an UNRESOLVED BASH_SOURCE walks out of
# the live layer instead of out of the repo and the library is silently not found.
_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac; done
  printf '%s' "$p"
}
ARM_SELF="$(_resolve_self "${BASH_SOURCE[0]}")"
ARM_ROOT="$(cd "$(dirname "$ARM_SELF")/../.." && pwd)"
# shellcheck source=/dev/null
. "$ARM_ROOT/hooks/lib/jev.sh"
jev_window_open || exit 4

mkdir -p "$(dirname "$ARM")" || { printf 'cannot create %s\n' "$(dirname "$ARM")" >&2; exit 3; }
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXP="$(date -u -v"+${TTL}M" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+${TTL} minutes" +%Y-%m-%dT%H:%M:%SZ)"
[ -n "$EXP" ] || { printf 'cannot compute an expiry; refusing to arm without one\n' >&2; exit 3; }
jq -n --arg c "$NOW" --arg e "$EXP" --argjson n "$CALLS" --argjson b "$CAPB" --arg k "$CORPUS" \
   '{created:$c, expires:$e, max_calls:$n, cap_b:$b, corpus:$k}' > "$ARM"
cat <<EOF
ARMED until $EXP (${TTL} min).

  corpus     $CORPUS — memory topic files reachable from NEITHER the index nor the
             always-loaded rules file. Our own engineering lessons. Never a transcript,
             never the mailbox, never the msg corpus.
  sends      the frontmatter description + the first $CAPB bytes of the body, per file
  ceiling    $CALLS calls, this window only
  retention  STANDARD (ZDR is Pro/Enterprise-only and 403s on this plan)

The scheduled job consumes this BEFORE its first call, so it fires at most once.
  see it:     cc-jev arm --status
  take it back: cc-jev arm --revoke
  watch it:   tail -f ~/.claude/autonomy/jev-batch.log
EOF
