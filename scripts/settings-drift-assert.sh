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

  # ── --file: the three outcomes, each RED-provable ───────────────────────────────────────────────
  # A stub cc-backlog records argv instead of writing the real store, so the selftest asserts WHAT
  # would be filed — not merely that something was attempted. A stub that always succeeded would let
  # a broken filing call pass, so the recorded argv is checked for the condition key that makes the
  # row single (without it every sweep mints a new item, the defect this whole mode exists to avoid).
  local stub="$d/stub-backlog" log="$d/filed.argv"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> "%s"\nexit 0\n' "$log" > "$stub"; chmod +x "$stub"

  # (1) agreement → files NOTHING and exits 0. The case that must stay silent: a detector that filed
  # on a clean fleet would carry the same zero bits as one that never fires.
  : > "$log"
  out="$(CC_DRIFT_DIRS="$d/a $d/b $d/c" CC_BACKLOG_BIN="$stub" "$SELF" --file 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && okp "--file on agreement → exit 0" || badp "--file on agreement exited $rc"
  [ ! -s "$log" ] && okp "--file on agreement files NOTHING" || badp "--file filed over a clean fleet"
  # exit 0 + an empty filing log is NOT enough to prove agreement was reported AS agreement: a
  # mutant that routes rc 0 into the non-verdict arm is silent and exits 0 too, yet tells the
  # operator the fleet could not be measured. It survived until this line existed. Assert the
  # VERDICT, not just the side effects.
  case "$out" in
    *NON-VERDICT*) badp "--file called a clean fleet a NON-VERDICT" ;;
    *GREEN*)       okp "--file on agreement reports GREEN, not a non-verdict" ;;
    *)             badp "--file on agreement reported neither GREEN nor a non-verdict" ;;
  esac

  # (2) drift → files exactly one condition-keyed row, exit 1
  : > "$log"
  CC_DRIFT_DIRS="$d/x $d/y $d/z" CC_BACKLOG_BIN="$stub" "$SELF" --file >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && okp "--file on drift → exit 1" || badp "--file on drift exited $rc"
  grep -qxF 'settings-drift-across-config-dirs' "$log" \
    && okp "--file passes the condition key (one row, not one per run)" \
    || badp "--file filed WITHOUT --condition — would mint a row per sweep"
  # `--` before the pattern: without it grep parses a leading-dash pattern as its own option and
  # dies usage-style, which `|| badp` would have reported as a missing falsifier — a test bug
  # wearing a subject bug's clothes.
  grep -qxF -- '--falsifier' "$log" \
    && okp "--file attaches the falsifier (the row self-closes)" || badp "--file filed with no falsifier"
  # `z(1)`, not a bare `z`: an unanchored 'MISSING in: z' passes over BOTH the flat-union spelling
  # and the weighted one, so it could never have caught the shape defect — a control pinned to a
  # spelling that any correct fix leaves standing is not a second opinion.
  grep -qF 'MISSING in: z(1)' "$log" \
    && okp "--file names the divergent dir WITH its incidence" || badp "--file title lacks the per-dir count"

  # (2b) TWO divergences with DIFFERENT missing-dir sets — the shape a flat union cannot express.
  # m1 holds both denies, m2 lacks Q, m3 lacks both: so P is missing in ONE dir and Q in TWO, and
  # the title must read m3(2) m2(1). The old union emitted the two dir names sorted alphabetically
  # with no weights at all, which renders "5 hooks in one dir + 1 hook in four" identically to
  # "6 hooks in four dirs". This arm is the one that reds on that code.
  : > "$log"
  mkcfg "$d/m1" '["Bash(P:*)","Bash(Q:*)"]'; mkcfg "$d/m2" '["Bash(P:*)"]'; mkcfg "$d/m3"
  CC_DRIFT_DIRS="$d/m1 $d/m2 $d/m3" CC_BACKLOG_BIN="$stub" "$SELF" --file >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && okp "--file on a two-shape drift → exit 1" || badp "two-shape drift exited $rc"
  grep -qF 'MISSING in: m3(2) m2(1)' "$log" \
    && okp "--file title carries per-dir weights, heaviest first" \
    || badp "--file title flattened two different missing-dir sets into one union"

  # (3) NON-VERDICT → files nothing AND does not report green. Forced by an unwritable TMPDIR, which
  # makes the inner assert's mktemp fail (exit 3). This is the arm that keeps "the checker could not
  # look" distinct from "the fleet is clean" — the confusion that makes a dead detector read healthy.
  : > "$log"
  TMPDIR=/nonexistent/no-such-dir CC_DRIFT_DIRS="$d/x $d/y $d/z" CC_BACKLOG_BIN="$stub" \
    "$SELF" --file >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && okp "--file on a non-verdict does NOT report green (exit $rc)" \
                  || badp "--file reported green when the comparison could not run"
  [ ! -s "$log" ] && okp "--file on a non-verdict files NOTHING" || badp "--file filed on a non-verdict"

  echo "settings-drift-assert --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "settings-drift-assert --selftest: GREEN — agreement passes; deny/hook divergence + missing-dir all caught; path variants normalized; --file is silent on agreement, condition-keyed + falsified on drift, and files nothing on a non-verdict."
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/bin/cc-backlog}"

# ── --file: make the verdict REACH somebody ───────────────────────────────────────────────────────
# This checker was complete, correct and INERT for its whole life: measured 2026-08-11 it had zero
# callers — not wired in any of the 5 settings.json, not invoked by any live launchd job — while the
# drift it names was live in .claude-next (backlog 4ce34a4f703c). Printing to a terminal nobody is
# watching is not detection. `--file` writes ONE condition-keyed backlog row, so the verdict lands in
# the store the readout, the ledger and dispatch already read.
#
# CONDITION-KEYED, not a fresh row per run: the title carries a live count, so an unkeyed `add` would
# mint a new item on every sweep and reproduce one layer down the exact rot this repo keeps filing.
# The falsifier IS this script in --assert mode, whose rc 0 means the dirs agree — so the row closes
# itself the moment the drift is fixed, with no human marking it done.
#
# THREE OUTCOMES, NOT TWO. rc 1 is drift; rc 0 is agreement; anything else (no jq, mktemp failure,
# fewer than two readable config dirs) is a NON-VERDICT — the checker could not look. A non-verdict
# must neither file (a bogus item over a store nobody measured) nor report green (the failure mode
# that makes a broken detector indistinguishable from a clean fleet). It is passed through as its own
# exit code and says so.
file_mode() {
  local out rc n dirs
  out="$("$SELF" --assert 2>&1)"; rc=$?
  printf '%s\n' "$out"

  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -ne 1 ]; then
    printf 'settings-drift-assert --file: NON-VERDICT (exit %d) — the comparison could not run, so nothing was filed and nothing is claimed clean.\n' "$rc" >&2
    return "$rc"
  fi

  [ -x "$BACKLOG_BIN" ] || {
    printf 'settings-drift-assert --file: cannot file — no cc-backlog at %s (the drift above stands unrecorded)\n' "$BACKLOG_BIN" >&2
    return 1
  }

  n="$(printf '%s\n' "$out" | grep -c '^DRIFT ' 2>/dev/null | tr -d ' ')"
  # The divergent dirs WITH their per-dir incidence, heaviest first.
  #
  # This used to `sort -u` every per-line dir list into one flat union, and the title then read
  # "N guardrail(s) ... MISSING in: <every dir that appears anywhere>". That reads as a CROSS
  # PRODUCT — N guardrails absent from all those dirs — and on the live fleet (2026-09-04) it is
  # not: 5 of the 6 divergences are missing in .claude-next ALONE, and the 6th (pr-gate.sh) is
  # missing in FOUR dirs, i.e. registered only in ~/.claude. The union renders those two opposite
  # shapes identically, and the per-dir weight is exactly what answers the question the old
  # comment here already asked — "which account runs looser".
  #
  # The verdict and the count were never wrong; only the SHAPE was, and the shape lives solely in
  # the title, which is the one part of this row a human or a successor session ever reads.
  # A row's numerals and a row's STRUCTURE rot independently, and a condition key protects the
  # first and says nothing about the second (#300, method 272).
  dirs="$(printf '%s\n' "$out" \
          | awk -F'missing in:' '/^DRIFT /{n=split($2,a," ");
                                           for(i=1;i<=n;i++) if(a[i]!="") c[a[i]]++}
                                 END{for(k in c) printf "%d\t%s\n", c[k], k}' \
          | sort -k1,1nr -k2,2 \
          | awk '{printf "%s%s(%d)", (NR>1?" ":""), $2, $1}')"

  "$BACKLOG_BIN" add --project claude-infrastructure \
    --source settings-drift-assert \
    --condition settings-drift-across-config-dirs \
    --falsifier "$SELF --assert" \
    --title "${n} guardrail(s) wired in some config dirs but MISSING in: ${dirs:-unknown} — the fleet picks a config dir by account at fire time, so what a session may do depends on which account fired it. Run \`$SELF\` for the named lines. Fixing it edits settings.json (C10) — stage a migration, never an in-place edit. The falsifier on this row IS the detector, so this item closes itself when the dirs agree." \
    >/dev/null 2>&1 && printf 'settings-drift-assert --file: filed/updated the condition-keyed drift item.\n'
  return 1
}

case "${1:-}" in
  --selftest) selftest ;;
  --file)     file_mode ;;
  ""|--assert) assert ;;
  *) printf 'settings-drift-assert: unknown arg %s (use --assert | --file | --selftest)\n' "$1" >&2; exit 2 ;;
esac
