#!/bin/bash
# rm-safe-allowlist.sh — PreToolUse(Bash) hook that AUTO-ALLOWS `rm` of regenerable,
# within-tree targets so 24/7 autonomous work stops halting on the static `Bash(rm:*)`
# ask rule (~21×/build on `rm -rf artifacts/`). Everything not provably safe stays SILENT
# (exit 0, no decision) → the existing `ask` prompt / deny array / validate-bash still apply.
#
# SAFETY MODEL — allow is OPT-IN to a whitelist, never opt-out:
#   • auto-allow ONLY when EVERY target is a regenerable build/cache dir (or a path within one),
#     relative to cwd with no `..`, no glob, no `~`, no bare `/`; OR an absolute path strictly
#     UNDER /tmp or /private/tmp (regenerable scratch).
#   • NEVER allow if any target is `.git`/inside `.git`, `~`, `/`, an outside-repo absolute path,
#     or any name not on the regenerable list → those fall through to the ask prompt (operator's call).
#   • Re-runs the catastrophic DANGER_PATTERNS (rm -rf /, sudo rm, fork bomb) and defers on match.
# The design mirrors hooks/smart-bash-allowlist.sh (allow-only; deny always overrides; hooks chain,
# first non-empty decision wins) but is scoped to `rm` alone for a minimal blast radius.
#
# Kill switch: RM_SAFE_ALLOWLIST_DISABLED=1  (defer everything).
# Contract: read the PreToolUse payload on stdin, emit allow-JSON + exit 0 to allow, else exit 0 silent.

[[ "${RM_SAFE_ALLOWLIST_DISABLED:-0}" == "1" ]] && exit 0
set -uo pipefail

INPUT=$(cat)
# Fail-open on malformed input (let validate-bash.sh handle it)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -z "$CMD" ]] && exit 0

# ── Catastrophic danger re-check: on match, DEFER (exit 0, no allow) ───────────────────────
# rm -rf / (system damage), sudo rm, fork bomb. (Belt-and-suspenders; the whitelist below
# already cannot match these, but re-checking keeps the invariant explicit and local.)
if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_])sudo[[:space:]]+rm|rm[[:space:]]+-[a-zA-Z]*[[:space:]]*/[[:space:]]*$|rm[[:space:]]+-[a-zA-Z]*[[:space:]]+/[[:space:]]*($|[^a-zA-Z0-9._/-])|:\(\)\{[[:space:]]*:'; then
  exit 0
fi

# ── Only handle a SIMPLE, single `rm` command: no compound / substitution / redirection ─────
# (A compound line could hide an unsafe rm after `;`/`&&`/`|`; defer those to the prompt.)
# shellcheck disable=SC2016  # the single-quoted shell metacharacters are LITERALS to match, by design
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'$('*|*'`'*|*'>'*|*'<'*|*$'\n'*) exit 0 ;;
esac
# Must be exactly an `rm ...` invocation (optionally leading whitespace).
[[ "$CMD" =~ ^[[:space:]]*rm[[:space:]] ]] || exit 0

# Regenerable directory names (exact path components). Deleting anything WITHIN such a tree is
# safe because the tree is reproducible from source (build output / caches / test artifacts).
SAFE_NAMES='node_modules .next .nuxt dist build out target __pycache__ .pytest_cache .mypy_cache .ruff_cache .cache .turbo .parcel-cache .nyc_output coverage test-results playwright-report .vercel .svelte-kit artifacts .gradle .terraform'

is_safe_target() { # <raw-target> → 0 safe · 1 not-safe
  local t="$1"
  [[ -z "$t" ]] && return 1
  # Strip a single leading ./ ; strip trailing slashes.
  t="${t#./}"; while [[ "$t" == */ ]]; do t="${t%/}"; done
  [[ -z "$t" ]] && return 1
  # Reject glob/home/parent-traversal outright.
  case "$t" in *'*'*|*'?'*|*'['*|'~'*|*'..'*) return 1 ;; esac

  if [[ "$t" == /* ]]; then
    # Absolute path: allow ONLY strictly under /tmp or /private/tmp (regenerable scratch) —
    # never the bare tmp root, never any other absolute location (outside-repo). `..`/glob/~
    # were already rejected above, so a path under tmp is safe on its own (no component match
    # required — a relative dir literally named `tmp` is NOT on the whitelist, only real /tmp).
    case "$t" in
      /tmp/?*|/private/tmp/?*) return 0 ;;
      *) return 1 ;;
    esac
  fi

  # Component scan: reject empty / .git components; require >=1 component to be a regenerable name.
  # NB: scope IFS='/' to the `read` ALONE — a function-wide `local IFS=/` would also break the
  # space-splitting of $SAFE_NAMES in the inner loop below (the target would never match).
  local parts=() p hit=0
  IFS='/' read -r -a parts <<< "$t"
  for p in "${parts[@]}"; do
    [[ -z "$p" ]] && continue                      # leading-/ produces an empty first field
    [[ "$p" == ".git" ]] && return 1               # never touch a git dir, even nested
    local n
    for n in $SAFE_NAMES; do [[ "$p" == "$n" ]] && { hit=1; break; }; done
  done
  [[ "$hit" == 1 ]] && return 0
  return 1
}

# ── Parse: separate flags from targets; only known rm flags may appear ──────────────────────
read -r -a TOKS <<< "$CMD"
# TOKS[0] == "rm"
targets=()
for ((i=1; i<${#TOKS[@]}; i++)); do
  tok="${TOKS[$i]}"
  case "$tok" in
    --) ;;                                          # end-of-flags separator: skip
    --recursive|--force|--verbose|--dir) ;;         # long recursive/force flags: OK
    --*) exit 0 ;;                                   # any other long flag: unknown → defer
    -*)                                              # short flags: only r/f/R/d/v/i combos allowed
        [[ "$tok" =~ ^-[rfRdvi]+$ ]] || exit 0 ;;
    *) targets+=("$tok") ;;
  esac
done
[[ ${#targets[@]} -eq 0 ]] && exit 0                 # no targets (e.g. `rm --help`) → defer

# EVERY target must be provably safe, or we defer to the prompt.
for t in "${targets[@]}"; do
  is_safe_target "$t" || exit 0
done

# ── All targets safe → AUTO-ALLOW ───────────────────────────────────────────────────────────
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "rm of regenerable within-tree target(s) only (build/cache/artifacts or /tmp scratch); no .git/~///outside-repo/glob"
  }
}
EOF
exit 0
