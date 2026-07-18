#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# nightly-regression.sh — P0-18: the standing regression signal.
#
# Why (p12): NOTHING runs the tests between lands. never-stuck regressed 21·0 → 19·2 and sat unwatched;
# a broken detector can rot for days because its bats only run when a human remembers. This is the
# launchd-side nightly that runs the deterministic regression suite and PAGES on any red via P0-15's
# pages/ consumer + an OS-level notification — so a deliberately-broken detector pages by morning.
#
# WHAT IT RUNS (deterministic, side-effect-free — a 3am job must not mutate the live fleet):
#   1. bats tests/                       — the full suite (a broken detector's bats reds here)
#   2. plutil -lint launchd/*.plist      — every plist parses (catches the raw-& class, T-P16-6)
#   3. never-stuck-gate.sh (live)        — THE systematic invariant (the p12 21·0→19·2 signal)
#   4. every scripts/*gate*.sh + *lint*.sh: `--selftest` where supported, else a bare read-only run.
#      SKIPS *-e2e.sh (side-effectful — would spawn panes/sessions) — the skip is LOGGED, never silent.
#
# ON RED: write a page file to autonomy/pages/ (drainable by the P0-15 SO-5 desk-role consumer) +
# osascript notification. ALWAYS append a one-line result to autonomy/regression.log.
# C10: OPERATOR loads the plist (StartCalendarInterval nightly). Selftest: `--selftest`.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO="${CC_NIGHTLY_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PAGEDIR="${CC_NIGHTLY_PAGEDIR:-$HOME/.claude/autonomy/pages}"
LOG="${CC_NIGHTLY_LOG:-$HOME/.claude/autonomy/regression.log}"
NOTIFY_CMD="${CC_NIGHTLY_NOTIFY:-}"                                   # empty → builtin osascript
BATS_DIR="${CC_NIGHTLY_BATS_DIR:-$REPO/tests}"
PLIST_GLOB="${CC_NIGHTLY_PLIST_GLOB:-$REPO/launchd/*.plist}"
GATE_GLOB="${CC_NIGHTLY_GATE_GLOB:-$REPO/scripts/*gate*.sh}"
LINT_GLOB="${CC_NIGHTLY_LINT_GLOB:-$REPO/scripts/*lint*.sh}"
NEVERSTUCK="${CC_NIGHTLY_NEVERSTUCK:-$REPO/scripts/never-stuck-gate.sh}"   # live systematic invariant; stubbable for --selftest
PAGE_KEY="${CC_NIGHTLY_PAGE_KEY:-nightly-regression}"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

notify() { # <title> <msg> — OS-level, API-independent
  local title="$1" msg="$2"
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$title" "$msg" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    osascript -e "display notification \"${msg//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

REDS=()          # names of failing checks
SKIPS=()         # names of skipped (e2e) checks — logged, never silent
NCHECK=0

run_check() { # <name> -- <cmd...>
  local name="$1"; shift
  NCHECK=$((NCHECK+1))
  if "$@" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$name"
  else
    printf '  RED  %s (exit %d)\n' "$name" "$?"
    REDS+=("$name")
  fi
}

supports_selftest() { grep -qE -- '--selftest|selftest\)' "$1" 2>/dev/null; }

regress() {
  mkdir -p "$PAGEDIR" "$(dirname "$LOG")" 2>/dev/null || true
  echo "nightly-regression @ $(now_iso) — repo=$REPO"

  # 1. bats suite
  if command -v bats >/dev/null 2>&1; then
    run_check "bats:$(basename "$BATS_DIR")" bats "$BATS_DIR"
  else
    SKIPS+=("bats:not-installed"); printf '  skip bats (not installed)\n'
  fi

  # 2. plist lint
  if command -v plutil >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # PLIST_GLOB is an intentional glob
    run_check "plutil-lint" plutil -lint $PLIST_GLOB
  else
    SKIPS+=("plutil:not-installed"); printf '  skip plutil (not installed)\n'
  fi

  # 3. the live systematic invariant (p12 regression signal)
  [ -x "$NEVERSTUCK" ] && run_check "never-stuck-gate(live)" "$NEVERSTUCK"

  # 4. every gate + lint: --selftest where supported, else bare; SKIP e2e (side-effectful)
  local f b
  # shellcheck disable=SC2086  # GATE_GLOB/LINT_GLOB are intentional globs
  for f in $GATE_GLOB $LINT_GLOB; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in
      *-e2e.sh)          SKIPS+=("$b:e2e"); printf '  skip %s (e2e — side-effectful)\n' "$b"; continue ;;
      never-stuck-gate.sh) continue ;;   # already run live above
    esac
    if supports_selftest "$f"; then run_check "$b --selftest" "$f" --selftest
    else                            run_check "$b" "$f"; fi
  done

  # ── verdict ──
  local n_red="${#REDS[@]}" summary
  if [ "$n_red" -gt 0 ]; then
    summary="RED ($n_red): ${REDS[*]}"
    local pf="$PAGEDIR/$PAGE_KEY.page"
    { now_epoch; printf 'nightly-regression RED @ %s: %s\n' "$(now_iso)" "${REDS[*]}"; \
      printf 'see %s ; re-run: scripts/nightly-regression.sh\n' "$LOG"; } > "$pf"
    notify "Claude nightly-regression RED" "$n_red check(s) failed: ${REDS[*]}"
  else
    summary="GREEN ($NCHECK checks)"
    rm -f "$PAGEDIR/$PAGE_KEY.page" 2>/dev/null || true   # clear a prior standing alarm on a green night
  fi
  [ "${#SKIPS[@]}" -gt 0 ] && summary="$summary; skipped: ${SKIPS[*]}"
  printf '%s nightly-regression: %s\n' "$(now_iso)" "$summary" >> "$LOG"
  echo "nightly-regression: $summary"
  [ "$n_red" -eq 0 ]
}

# ════ selftest — RED-prove the red-path (page written) and the green-path (no page) ════════════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nightly-reg-selftest.XXXXXX")" || { echo mktemp failed; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  mkdir -p "$d/pages" "$d/goodtests" "$d/badtests" "$d/plists" "$d/emptygl"
  printf '#!/usr/bin/env bats\n@test "pass" { true; }\n' > "$d/goodtests/ok.bats"
  printf '#!/usr/bin/env bats\n@test "fail" { false; }\n' > "$d/badtests/no.bats"
  cp "$REPO/launchd/com.claude.team-orphan-reaper.plist" "$d/plists/good.plist" 2>/dev/null \
    || printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' > "$d/plists/good.plist"
  printf '<plist><dict><string>2>&1 raw ampersand</string></dict></plist>\n' > "$d/plists/bad.plist"

  # run the invariant with a stubbed check-set (NO eval — env-scoped overrides). <pagedir> <log> <batsdir> <plistglob>
  run_inv() {
    env CC_NIGHTLY_NOTIFY=/usr/bin/true CC_NIGHTLY_NEVERSTUCK=/usr/bin/true \
        CC_NIGHTLY_GATE_GLOB="$d/emptygl/*.sh" CC_NIGHTLY_LINT_GLOB="$d/emptygl/*.sh" \
        CC_NIGHTLY_PAGEDIR="$1" CC_NIGHTLY_LOG="$2" CC_NIGHTLY_BATS_DIR="$3" CC_NIGHTLY_PLIST_GLOB="$4" \
        "$SELF" >/dev/null 2>&1
  }

  echo "nightly-regression --selftest:"
  # green path: good bats + good plist + no gates → no page, exit 0
  run_inv "$d/pages" "$d/green.log" "$d/goodtests" "$d/plists/good.plist"; local grc=$?
  [ "$grc" -eq 0 ] && okp "green: exit 0" || badp "green: exit $grc (want 0)"
  [ ! -f "$d/pages/nightly-regression.page" ] && okp "green: NO page written" || badp "green: page written on green"
  grep -q 'GREEN' "$d/green.log" && okp "green: regression.log records GREEN" || badp "green: log missing GREEN"

  # red path (bats): failing suite → page written + exit nonzero + log RED
  run_inv "$d/pages" "$d/redb.log" "$d/badtests" "$d/plists/good.plist"; local brc=$?
  [ "$brc" -ne 0 ] && okp "red-bats: nonzero exit" || badp "red-bats: exit 0 on a failing suite"
  [ -f "$d/pages/nightly-regression.page" ] && okp "red-bats: page file written to pages/" || badp "red-bats: no page written"
  grep -q 'RED' "$d/redb.log" && okp "red-bats: regression.log records RED" || badp "red-bats: log missing RED"
  head -1 "$d/pages/nightly-regression.page" | grep -qE '^[0-9]+$' && okp "page: first line is an epoch (convention-compatible)" || badp "page: first line not an epoch"
  rm -f "$d/pages/nightly-regression.page"

  # red path (plutil): deliberately-bad fixture plist → page + RED
  run_inv "$d/pages" "$d/redp.log" "$d/goodtests" "$d/plists/bad.plist"; local prc=$?
  [ "$prc" -ne 0 ] && okp "red-plutil: nonzero exit on a bad plist" || badp "red-plutil: exit 0 on a bad plist"
  [ -f "$d/pages/nightly-regression.page" ] && okp "red-plutil: page written" || badp "red-plutil: no page"

  # green night clears a prior standing page
  run_inv "$d/pages" "$d/clear.log" "$d/goodtests" "$d/plists/good.plist"
  [ ! -f "$d/pages/nightly-regression.page" ] && okp "green night clears the standing page" || badp "green night left a stale page"

  echo "nightly-regression --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "nightly-regression --selftest: GREEN — red-path pages (bats + plutil), green-path clears, page is epoch-headed."
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--run)   regress ;;
  *)          printf 'nightly-regression: unknown arg %s (use --run | --selftest)\n' "$1" >&2; exit 2 ;;
esac
