#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cmd && okp || badp` reporter idiom
# shellcheck disable=SC2016  # file-wide: jq program bodies are intentionally single-quoted ($x = jq var)
# settings-drift-assert.sh — the settings.json drift assertion across the 5 INDEPENDENT config dirs.
#
# Why (G-P10-7 / T-P10-4): the 5 config dirs (~/.claude · .claude-next · .claude-secondary ·
# .claude-tertiary · .claude-quaternary) each carry their OWN settings.json (distinct inodes — hooks/
# are symlinked-shared but settings.json is NOT). A safety `deny`/`ask` rule or an anti-premature-done
# Stop hook present in 4 dirs but silently missing in the 5th ⇒ that account runs looser / un-guarded
# (memory: next4 already drifted, missing a deny). This is the config-mirror-assert analog for
# settings.json — READ-ONLY: it compares, reports drift lines, and exits 1 on any drift. Wire it on
# SessionStart (advisory; the wiring line rides the wiring-all bundle). It NEVER edits a settings file.
#
# Normalization: hook commands are compared by basename+args, so `~/.claude/hooks/X`,
# `/Users/you/.claude/hooks/X`, and a repo-absolute `…/claude-infrastructure/hooks/X` are the SAME hook
# — drift means a hook PRESENT in some dirs and ABSENT in others, regardless of path spelling.
# Selftest: `--selftest`. bats fixtures drive it via CC_DRIFT_DIRS.
set -uo pipefail

DEFAULT_DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
read -r -a DIRS <<< "${CC_DRIFT_DIRS:-$DEFAULT_DIRS}"

JQ="$(command -v jq || true)"
[ -n "$JQ" ] || { printf 'settings-drift-assert: jq required\n' >&2; exit 3; }

norm_cmd() { # <command-string> → "<basename-of-first-token><rest-verbatim>" (path-spelling-independent)
  local first rest
  first="${1%% *}"; rest="${1#"$first"}"
  printf '%s%s' "$(basename -- "$first")" "$rest"
}

sig_deny()  { "$JQ" -r '.permissions.deny[]?  // empty' "$1/settings.json" 2>/dev/null | sort -u; }
sig_ask()   { "$JQ" -r '.permissions.ask[]?   // empty' "$1/settings.json" 2>/dev/null | sort -u; }
sig_hooks() { # emit one normalized "event|basename+args" line per wired hook command
  "$JQ" -r '.hooks // {} | to_entries[] | .key as $e | (.value // [])[]? | (.hooks // [])[]? | "\($e)|\(.command)"' \
    "$1/settings.json" 2>/dev/null \
  | while IFS='|' read -r ev cmd; do [ -n "$ev" ] && printf '%s|%s\n' "$ev" "$(norm_cmd "$cmd")"; done | sort -u
}

WORK=""; DRIFT=""
compare_array() { # <label> <extract-fn> — append DRIFT lines to $DRIFT for entries not in EVERY present dir
  local label="$1" fn="$2" dir nd=0 entry have miss
  local present=()
  : > "$WORK/all.$label"
  for dir in "${DIRS[@]}"; do
    [ -f "$dir/settings.json" ] || continue
    present+=("$dir"); nd=$((nd+1))
    "$fn" "$dir" > "$WORK/${nd}.$label"
    cat "$WORK/${nd}.$label" >> "$WORK/all.$label"
  done
  [ "$nd" -lt 2 ] && return 0
  local i
  sort -u "$WORK/all.$label" | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    have=0; miss=""
    for i in $(seq 1 "$nd"); do
      if grep -qxF -- "$entry" "$WORK/${i}.$label"; then have=$((have+1))
      else miss="$miss ${present[$((i-1))]##*/}"; fi
    done
    [ "$have" -lt "$nd" ] && printf 'DRIFT [%s] "%s" — missing in:%s\n' "$label" "$entry" "$miss" >> "$DRIFT"
  done
}

assert() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/settings-drift.XXXXXX")" || { echo "mktemp failed" >&2; exit 3; }
  DRIFT="$WORK/drift"; : > "$DRIFT"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORK'" EXIT

  local dir seen=0
  for dir in "${DIRS[@]}"; do
    if [ -f "$dir/settings.json" ]; then seen=$((seen+1))
    else printf 'NOTE [config-missing] %s (no settings.json — not counted in the comparison)\n' "$dir"; fi
  done
  if [ "$seen" -lt 2 ]; then
    printf 'settings-drift-assert: only %d config dir(s) with settings.json — nothing to compare (OK)\n' "$seen"
    return 0
  fi

  compare_array deny  sig_deny
  compare_array ask   sig_ask
  compare_array hooks sig_hooks

  if [ -s "$DRIFT" ]; then
    cat "$DRIFT"
    printf 'settings-drift-assert: DRIFT — %d divergence(s) across %d config dirs (a rule/hook missing in some ⇒ that account runs differently)\n' \
      "$(wc -l < "$DRIFT" | tr -d ' ')" "$seen"
    return 1
  fi
  printf 'settings-drift-assert: GREEN — deny/ask/hooks agree across %d config dirs\n' "$seen"
  return 0
}

# ════ selftest — RED-prove: identical dirs → GREEN; a planted missing deny → DRIFT (exit 1, named) ═══
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
mkcfg() { # <dir> <extra-deny-json-or-empty>
  mkdir -p "$1"
  "$JQ" -n --argjson xd "${2:-[]}" '{
    permissions: { deny: (["Bash(sudo:*)","Bash(eval:*)"] + $xd), ask: ["Bash(git push:*)"] },
    hooks: { Stop: [ { hooks: [ { type:"command", command:"~/.claude/hooks/anti-deference-nudge.sh" } ] } ] }
  }' > "$1/settings.json"
}
# shellcheck disable=SC2317
selftest() {
  local d out rc; d="$(mktemp -d "${TMPDIR:-/tmp}/settings-drift-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  echo "settings-drift-assert --selftest:"

  # agreement: 3 identical dirs → GREEN, exit 0
  mkcfg "$d/a"; mkcfg "$d/b"; mkcfg "$d/c"
  CC_DRIFT_DIRS="$d/a $d/b $d/c" "$SELF" >/dev/null 2>&1 \
    && okp "identical dirs → exit 0 (GREEN)" || badp "identical dirs flagged drift"

  # path-spelling equivalence: same hook via /Users/... absolute vs ~/.claude → NOT drift
  mkcfg "$d/p1"; mkcfg "$d/p2"
  "$JQ" '.hooks.Stop[0].hooks[0].command = "/Users/x/.claude/hooks/anti-deference-nudge.sh"' "$d/p2/settings.json" > "$d/p2/tmp" && mv "$d/p2/tmp" "$d/p2/settings.json"
  CC_DRIFT_DIRS="$d/p1 $d/p2" "$SELF" >/dev/null 2>&1 \
    && okp "path-spelling variants of a hook are NOT drift" || badp "path variant falsely flagged"

  # deny drift: c is missing a deny that a+b have → DRIFT exit 1, naming the entry
  mkcfg "$d/x" '["Bash(rm -rf /:*)"]'; mkcfg "$d/y" '["Bash(rm -rf /:*)"]'; mkcfg "$d/z"
  out="$(CC_DRIFT_DIRS="$d/x $d/y $d/z" "$SELF" 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && okp "a missing deny → exit 1 (DRIFT)" || badp "missing deny not caught (exit $rc)"
  printf '%s' "$out" | grep -q 'DRIFT \[deny\].*rm -rf' && okp "drift line names the array + entry" || badp "drift line missing the entry"
  printf '%s' "$out" | grep -q 'missing in:.*z' && okp "drift line names the divergent dir" || badp "drift line missing the dir"

  # hooks drift: one dir missing the anti-deference Stop hook → DRIFT
  mkcfg "$d/h1"; mkcfg "$d/h2"
  "$JQ" '.hooks.Stop = []' "$d/h2/settings.json" > "$d/h2/tmp" && mv "$d/h2/tmp" "$d/h2/settings.json"
  CC_DRIFT_DIRS="$d/h1 $d/h2" "$SELF" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && okp "a missing Stop hook → exit 1 (DRIFT)" || badp "missing Stop hook not caught"

  echo "settings-drift-assert --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "settings-drift-assert --selftest: GREEN — agreement passes; deny/hook divergence + missing-dir all caught; path variants normalized."
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
case "${1:-}" in
  --selftest) selftest ;;
  ""|--assert) assert ;;
  *) printf 'settings-drift-assert: unknown arg %s (use --assert | --selftest)\n' "$1" >&2; exit 2 ;;
esac
