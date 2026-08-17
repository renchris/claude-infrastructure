#!/bin/bash
# Mutation controls for scripts/validate-bash-differential.sh — proves the harness CAN fail.
# Each mutant perturbs exactly ONE thing and asserts a non-zero exit. Run from the repo root.
set -u
# Symlink hops resolved before the root is derived — see scripts/ship-land.sh:199 for the canonical
# loop and scripts/validate-bash-differential.sh for why an unresolved $0 reads the wrong tree.
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [[ -L "$p" ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
ROOT="$(cd "$(dirname "$(_resolve_self "${BASH_SOURCE[0]:-$0}")")/.." && pwd)"
SRC="$ROOT/tests/fixtures/validate-bash-sites.tsv"
[[ -r "$SRC" ]] || { printf 'controls cannot run: %s unreadable\n' "$SRC"; exit 2; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

# A mutant must be caught for the RIGHT REASON: exit 1 (a verdict mismatch / coverage / drift
# failure), never exit 2 (harness or setup error) and never 127 (script not found). A control that
# accepts "any non-zero" passes on a typo in its own path and proves nothing.
run_mutant() { # label, mutated-sites-file
  local lbl="$1" f="$2" rc
  [[ -s "$f" ]] || { printf 'CONTROL FAILED (mutant file empty): %s\n' "$lbl"; fails=$((fails+1)); return; }
  CC_DIFF_SITES="$f" bash "$ROOT/scripts/validate-bash-differential.sh" >"$TMP/out" 2>&1
  rc=$?
  if [[ $rc -eq 1 ]]; then
    printf 'ok  mutant caught (exit 1): %s\n' "$lbl"
  else
    printf 'CONTROL FAILED (exit %d, wanted 1): %s\n' "$rc" "$lbl"; fails=$((fails+1))
  fi
}

# M1 — a site pinned DIVERGENT is re-pinned EQUIVALENT (the "conversion is safe" lie)
sed -e '/^S15	/s/	DIVERGENT	/	EQUIVALENT	/' "$SRC" > "$TMP/m1.tsv"
run_mutant "S15 re-pinned EQUIVALENT" "$TMP/m1.tsv"

# M2 — a site pinned EQUIVALENT is re-pinned DIVERGENT (a vacuous-control lie in the other direction)
sed -e '/^S03	/s/	EQUIVALENT	/	DIVERGENT	/' "$SRC" > "$TMP/m2.tsv"
run_mutant "S03 re-pinned DIVERGENT" "$TMP/m2.tsv"

# M3 — a site is DELETED from the inventory (simulates a new/unreviewed grep site in the hook)
/usr/bin/grep -v '^S19	' "$SRC" > "$TMP/m3.tsv"
run_mutant "S19 row deleted (coverage)" "$TMP/m3.tsv"

# M4 — a pinned pattern no longer matches the hook's line (transcription / hook drift)
sed -e '/^S26	/s/--hard\\b/--soft\\b/' "$SRC" > "$TMP/m4.tsv"
run_mutant "S26 pattern drifted" "$TMP/m4.tsv"

# M5 — the baseline itself must PASS, else the mutants prove nothing
if bash "$ROOT/scripts/validate-bash-differential.sh" >"$TMP/out" 2>&1; then
  printf 'ok  baseline passes\n'
else
  printf 'CONTROL FAILED: baseline does not pass\n'; fails=$((fails+1))
fi

[[ $fails -eq 0 ]] && printf '\nall controls held\n' || printf '\n%d control(s) failed\n' "$fails"
exit "$fails"
