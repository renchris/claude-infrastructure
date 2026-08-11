#!/usr/bin/env bash
# land-verify.sh — CONTENT-verify a landing, as code (not prose).
#
#   scripts/land-verify.sh <range> [trunk-ref] [local-ref]
#
# After a push, prove that EVERY path the landing range touched actually reached the
# trunk with the content you shipped — the check a bare `git rev-list --count` cannot
# make (it read 0 during the 2026-07-11 incident while the files were absent from main).
# This closes G-P9-2 (content-verify was prose the model could skip) and, per-path, also
# stranded-sweep's mixed add+edit blind spot (G-P9-7): a dropped NEW file among landed
# edits fails here even though its sibling edits are present.
#
#   <range>      revision range enumerating the landed change, e.g. `origin/main..HEAD`
#                or `<base>..<head>`; passed to `git diff --name-only`.
#   [trunk-ref]  the ref the content must have LANDED on (default: origin/<trunk>).
#   [local-ref]  what you shipped (default: the right side of `A..B`, else HEAD).
#
# Per changed path P:
#   * P present on local-ref (an add/edit) ⇒ require P present on trunk (`git ls-tree`
#     non-empty) AND `git diff <local> <trunk> -- P` empty.
#   * P absent on local-ref (a deletion)   ⇒ require `git diff <local> <trunk> -- P`
#     empty only (i.e. the deletion also landed) — never false-flag a landed delete.
# Any miss ⇒ exit 1 after listing every offending path. All verified ⇒ exit 0.
#
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

RANGE="${1:-}"
if [[ -z "${RANGE}" ]]; then
  echo "✗ land-verify.sh: no range given. Usage: land-verify.sh <range> [trunk-ref] [local-ref]" >&2
  exit 64
fi
TRUNK_REF="${2:-}"
LOCAL_REF="${3:-}"

if [[ -z "${TRUNK_REF}" ]]; then
  t="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [[ -z "${t}" ]] && t="main"
  TRUNK_REF="origin/${t}"
fi

if [[ -z "${LOCAL_REF}" ]]; then
  case "${RANGE}" in
    *..*) LOCAL_REF="${RANGE##*..}" ;;
    *)    LOCAL_REF="HEAD" ;;
  esac
  [[ -z "${LOCAL_REF}" ]] && LOCAL_REF="HEAD"
fi

# A range that does not RESOLVE must never read as a clean land. The `git diff --name-only`
# below ran inside a process substitution with stderr suppressed and its exit status
# unobservable, so an unresolvable range yielded zero paths and fell through to the success
# line: `land-verify.sh definitely-not-a-rev..also-not-a-rev` printed
# "✓ 0 path(s) present + content-identical" and exited 0 (measured 2026-08-10). This is the
# step ship-land uses to PROVE a land reached the trunk — this repo verifies by CONTENT
# precisely because a commit count lies — so "I could not look" was certifying "I looked and
# it was fine". Resolve both endpoints up front and fail closed.
_range_endpoint_check() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1 && return 0
  echo "✗ land-verify: range endpoint '${1}' does not resolve to a commit — cannot verify" >&2
  echo "  (an unenumerable range is a NON-VERDICT, never a clean land)" >&2
  exit 2
}
case "${RANGE}" in
  *..*)
    _lhs="${RANGE%%..*}"; _rhs="${RANGE##*..}"
    _range_endpoint_check "${_lhs:-HEAD}"
    _range_endpoint_check "${_rhs:-HEAD}"
    ;;
  *) _range_endpoint_check "${RANGE}" ;;
esac

# Enumerate into a file so the diff's own exit status is observable — a process
# substitution discards it, which is the other half of the fail-open above.
_paths="$(mktemp -t landverify.XXXXXX)" || {
  echo "✗ land-verify: could not create a scratch file — cannot verify" >&2; exit 2; }
trap 'rm -f "${_paths}"' EXIT
if ! git diff --name-only -z "${RANGE}" > "${_paths}" 2>/dev/null; then
  echo "✗ land-verify: 'git diff ${RANGE}' failed — cannot enumerate the landed range" >&2
  echo "  (an unenumerable range is a NON-VERDICT, never a clean land)" >&2
  exit 2
fi

misses=""
checked=0
while IFS= read -r -d '' path; do
  [[ -z "${path}" ]] && continue
  checked=$(( checked + 1 ))

  if [[ -n "$(git ls-tree "${LOCAL_REF}" -- "${path}" 2>/dev/null)" ]]; then
    # add/edit — must be present on trunk AND byte-identical to what we shipped.
    if [[ -z "$(git ls-tree "${TRUNK_REF}" -- "${path}" 2>/dev/null)" ]]; then
      misses="${misses}    ${path}  (ABSENT from ${TRUNK_REF} — dropped)
"
      continue
    fi
    if [[ -n "$(git diff "${LOCAL_REF}" "${TRUNK_REF}" -- "${path}" 2>/dev/null)" ]]; then
      misses="${misses}    ${path}  (content on ${TRUNK_REF} DIFFERS from shipped)
"
    fi
  else
    # deletion — the delete must also be on trunk (diff empty). Never require presence.
    if [[ -n "$(git diff "${LOCAL_REF}" "${TRUNK_REF}" -- "${path}" 2>/dev/null)" ]]; then
      misses="${misses}    ${path}  (deletion NOT landed on ${TRUNK_REF})
"
    fi
  fi
done < "${_paths}"

if [[ -n "${misses}" ]]; then
  echo "✗ land-verify: content NOT fully landed on ${TRUNK_REF} (local ${LOCAL_REF}):" >&2
  printf '%s' "${misses}" >&2
  echo "  These paths were changed in ${RANGE} but did not reach the trunk intact — a rebase-drop or partial land." >&2
  exit 1
fi

echo "✓ land-verify: ${checked} path(s) present + content-identical on ${TRUNK_REF}"
exit 0
