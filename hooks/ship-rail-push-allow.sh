#!/bin/bash
# ship-rail-push-allow.sh — PreToolUse(Bash) hook that AUTO-ALLOWS the one ship-rail LAND
# push shape (`git push origin HEAD:<branch>`, non-force) so 24/7 autonomous ship stops
# halting on the static `Bash(git push:*)` ask rule. Everything not provably the land shape
# stays SILENT (exit 0, no decision) → the existing `ask` prompt / `deny` array (force) /
# validate-bash still apply.
#
# WHY THIS EXISTS (T-P15-4, desk-audit 2026-07-18 §U2/G-P15-3): `defaultMode:auto` still
# HALTS on the `ask` array, and `Bash(git push:*)` sits there — so a model-issued land push
# strands with no human to approve (page unconfigured / prompt blocks the turn). The infra
# ship rail's own push escapes this because `scripts/ship-land.sh:186` runs `git push` as a
# SUBPROCESS (non-Bash-tool path) — resolving U2: it is already ask-exempt. The strand is the
# MODEL-ISSUED land push (`commands/ship.md:43` "on trunk directly → git push origin HEAD:<trunk>";
# a rebased feature branch fast-forward-land), which surfaces as a Bash tool call. This hook
# narrows the `git push:*` ask so exactly that land shape is auto-allowed. It is the COMPLEMENT
# of hooks/smart-bash-allowlist.sh, which allows `git push origin <feature>` but DELIBERATELY
# EXCLUDES trunk (main/master/develop/…) — leaving the land-to-trunk push with no allow path.
#
# SAFETY MODEL — allow is OPT-IN to one shape, never opt-out:
#   • auto-allow ONLY the exact simple command `git push origin HEAD:<branch>` — one remote
#     (origin), the `HEAD:<ref>` land refspec, a safe branch name ([A-Za-z0-9][A-Za-z0-9._/-]*,
#     no `..`), NO flags, NO force.
#   • a non-force push CANNOT rewrite trunk history — a non-fast-forward is REJECTED by the
#     server (ship-land.sh exit 7), so the blast radius is "advance a ref you can already
#     fast-forward", which is precisely the land operation.
#   • NEVER allow force in any form (`--force`, `-f`, `--force-with-lease`, a `+HEAD:` refspec,
#     `--mirror`, `--delete`), a non-`origin` remote, a bare `git push`, `-u`/`--set-upstream`,
#     or ANY compound / substitution / redirection → all fall through to the ask/deny (the
#     `Bash(git push --force:*)` / `-f` deny rules and the `git push:*` ask stay in force).
# The design mirrors hooks/rm-safe-allowlist.sh (allow-only; deny always overrides; hooks
# chain, a hook `allow` overrides the settings `ask`) but is scoped to the ONE land shape.
#
# Kill switch: SHIP_RAIL_PUSH_ALLOW_DISABLED=1  (defer everything).
# Contract: read the PreToolUse payload on stdin, emit allow-JSON + exit 0 to allow, else exit 0 silent.

[[ "${SHIP_RAIL_PUSH_ALLOW_DISABLED:-0}" == "1" ]] && exit 0
set -uo pipefail

INPUT=$(cat)
# Fail-open on malformed input (let the ask prompt / validate-bash.sh handle it).
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -z "$CMD" ]] && exit 0

# ── Only handle a SIMPLE, single command: no compound / substitution / redirection ──────────
# A compound line could hide an unsafe command after the safe push (`git push … && curl x|sh`);
# a substitution could smuggle an arbitrary ref. Defer every such form to the prompt.
# shellcheck disable=SC2016  # the single-quoted shell metacharacters are LITERALS to match, by design
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'$('*|*'`'*|*'>'*|*'<'*|*$'\n'*) exit 0 ;;
esac

# ── Belt-and-suspenders force/danger re-check: on match, DEFER (exit 0, no allow) ────────────
# The positive match below already requires an exact flag-free `HEAD:<branch>` tail, so none of
# these can reach the allow — but re-checking keeps the "never auto-allow force" invariant
# explicit and local, and guards against any future loosening of the matcher.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(--force([[:space:]]|=|$)|-f([[:space:]]|$)|--force-with-lease|--mirror|--delete|--prune|-u([[:space:]]|$)|--set-upstream)|[[:space:]]\+[^[:space:]]*HEAD'; then
  exit 0
fi

# ── Positive match: exactly `git push origin HEAD:<safe-branch>`, nothing else ───────────────
# Anchored ^…$ with the metachar/force pre-checks above means the WHOLE command must be this
# single land push — no trailing tokens, no leading flags between `push` and `origin`.
LAND_RE='^[[:space:]]*git[[:space:]]+push[[:space:]]+origin[[:space:]]+HEAD:([A-Za-z0-9][A-Za-z0-9._/-]*)[[:space:]]*$'
if [[ "$CMD" =~ $LAND_RE ]]; then
  ref="${BASH_REMATCH[1]}"
  # git refname rule + safety: no `..` range/traversal in the destination branch.
  case "$ref" in *..*) exit 0 ;; esac
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "ship-rail land push: non-force git push origin HEAD:$ref (fast-forward land shape; server rejects non-ff, force/compound/other-remote deferred)"
  }
}
EOF
  exit 0
fi

# Not the land shape → no decision; the existing git push:* ask / force deny still apply.
exit 0
