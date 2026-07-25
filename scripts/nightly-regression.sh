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
#   3b. idl-abstain-alarm.sh (live)      — the IDL abstention monitor: PAGES a check stuck at 100%
#                                          BLIND abstention (an inert no-check, T-P6-4); healthy-dormant is quiet.
#   4. every scripts/*gate*.sh + *lint*.sh: `--selftest` where supported, else a bare read-only run.
#      SKIPS *-e2e.sh (side-effectful — would spawn panes/sessions) — the skip is LOGGED, never silent.
#   5. postland_inertness — the post-land verification net's OWN liveness: stamps dir present but a
#      settled (>2h) trunk commit unstamped = the net stopped stamping (blind-check law). Abstains
#      green when the net isn't adopted (no stamps dir). Env seam: CC_NIGHTLY_POSTLAND_DIR/_AGE.
#   6. e2e-transitive-skip — the step-4 skip must hold TRANSITIVELY: a declared gate may not run an
#      e2e suite from inside itself unless that call carries an inline `# e2e:reviewed-hermetic`.
#
# ON RED: write a page file to autonomy/pages/ (drainable by the P0-15 SO-5 desk-role consumer) +
# osascript notification. ALWAYS append a one-line result to autonomy/regression.log.
# C10: OPERATOR loads the plist (StartCalendarInterval nightly). Selftest: `--selftest`.
set -uo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled job. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: NGR_OSA_TIMEOUT_S · NGR_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
NGR_OSA_TIMEOUT_S="${NGR_OSA_TIMEOUT_S:-5}"
if [ -n "${NGR_OSA_TIMEOUT_BIN+set}" ]; then
  NGR_OSA_TB="${NGR_OSA_TIMEOUT_BIN}"
else
  NGR_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NGR_OSA_TB="$_c"; break; }
  done
fi
ngr_osa() {
  if [ -z "$NGR_OSA_TB" ] || [ ! -x "$NGR_OSA_TB" ]; then "$@"; return $?; fi
  "$NGR_OSA_TB" -k 3 "$NGR_OSA_TIMEOUT_S" "$@"
}


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
ABSTAIN="${CC_NIGHTLY_ABSTAIN:-$REPO/scripts/idl-abstain-alarm.sh}"        # live IDL abstention monitor (T-P6-4); stubbable for --selftest
PAGE_KEY="${CC_NIGHTLY_PAGE_KEY:-nightly-regression}"
POSTLAND_DIR="${CC_NIGHTLY_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"   # post-land verification net; stubbable
POSTLAND_AGE="${CC_NIGHTLY_POSTLAND_AGE:-7200}"                              # a trunk commit older than this MUST be stamped

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

notify() { # <title> <msg> — OS-level, API-independent
  local title="$1" msg="$2"
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$title" "$msg" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    ngr_osa osascript -e "display notification \"${msg//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

REDS=()          # names of failing checks
SKIPS=()         # names of skipped (e2e) checks — logged, never silent
NCHECK=0

# Per-check output capture: a page naming only the FAILING CHECK is un-actionable (7 straight RED
# nights went unactioned on name-only pages). Each check's output lands in RUNDIR; the RED page
# quotes the failing tail. Capture-only — the console/green path is unchanged.
RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/nightly-reg.XXXXXX" 2>/dev/null)" || RUNDIR=""
# shellcheck disable=SC2064
[ -n "$RUNDIR" ] && trap "rm -rf '$RUNDIR'" EXIT
outfile() { # <check-name> → capture path ("" when no tmpdir)
  [ -n "$RUNDIR" ] || return 0
  printf '%s/%s.out' "$RUNDIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
}

run_check() { # <name> -- <cmd...>
  local name="$1"; shift
  NCHECK=$((NCHECK+1))
  local out; out="$(outfile "$name")"; [ -n "$out" ] || out=/dev/null
  if "$@" >"$out" 2>&1; then
    printf '  ok   %s\n' "$name"
  else
    printf '  RED  %s (exit %d)\n' "$name" "$?"
    REDS+=("$name")
  fi
}

# S4 (audit 08): the old form `grep -qE -- '--selftest|selftest\)'` was a false-positive machine and
# TWO of the eight 2026-07-24 REDs were pure artifacts of it: it matched (a) a bare-verb case arm
# (`selftest)` in gate-manifest) → the runner passed a flag the CLI rejects (exit 2 "unknown verb"),
# and (b) the literal string appearing in PROSE inside a todo/ok message (premortem-gate:72,
# reaper-safety-gate:45) or in a mid-line call to a DIFFERENT script (wait-safety-gate:78,93,118,
# session-lifecycle-safety-gate:70, comms-safety-gate:39) → a cosmetic `--selftest` in the log name
# for gates that ignore argv entirely. Now: a literal `--selftest` must appear as a real DISPATCH —
# a case pattern (own line, or on the `case … in` line) or an option comparison. Nothing else counts.
supports_selftest() {
  grep -vE '^[[:space:]]*#' "$1" 2>/dev/null | grep -qE -- \
    '^[[:space:]]*\(?[-|A-Za-z0-9_*."]*--selftest[-|A-Za-z0-9_*."]*\)|(^|[^[:alnum:]_])case[[:space:]].*[[:space:]]in[[:space:]].*--selftest[-|A-Za-z0-9_*."]*\)|==?[[:space:]]*"?--selftest"?'
}

# Blind-check law: an INERT net must page. If the post-land verification net exists (stamps dir
# present) but the newest settled trunk commit (older than POSTLAND_AGE) carries NO stamp for its
# tree, the net stopped stamping — deploys are silently frozen and nobody was told. RED.
# Abstains GREEN when the net is not adopted yet (no stamps dir) or trunk can't be resolved.
postland_inertness() {
  local stamps="$POSTLAND_DIR/stamps" cutoff sha tree
  [ -d "$stamps" ] || return 0                                   # net not adopted → abstain
  git -C "$REPO" fetch origin main >/dev/null 2>&1 || true        # best-effort freshness
  cutoff=$(( $(now_epoch) - POSTLAND_AGE ))
  sha="$(git -C "$REPO" rev-list -n 1 "--before=@$cutoff" origin/main 2>/dev/null || true)"
  [ -n "$sha" ] || return 0                                      # no settled trunk commit → abstain
  tree="$(git -C "$REPO" rev-parse "$sha^{tree}" 2>/dev/null || true)"
  [ -n "$tree" ] || return 0
  [ -f "$stamps/$tree.json" ] && return 0                        # stamped → the net is alive
  printf 'postland net INERT: trunk %.12s (tree %.12s), settled >%ss ago, has NO stamp under %s\n' \
    "$sha" "$tree" "$POSTLAND_AGE" "$stamps"                     # captured → quoted on the RED page
  return 1
}

# S3 (audit 08): step 4 SKIPS *-e2e.sh as side-effectful — but the skip is NOT TRANSITIVE.
# premortem-gate.sh:64 runs telemetry-e2e.sh AND p8-e2e.sh from inside itself. Both were verified
# hermetic (mktemp sandboxes, no live ~/.claude writes), so the skip's intent is not violated TODAY —
# but nothing enforced it, and the next e2e appended to that line would run against the live fleet at
# 04:00, unnoticed. Every direct e2e invocation inside a DECLARED gate/lint must carry an inline
# `# e2e:reviewed-hermetic` marker; an unmarked one is RED (fail-closed — review it, then mark it).
transitive_e2e_assert() {
  local f b hit rc=0 n=0
  # shellcheck disable=SC2086  # GATE_GLOB/LINT_GLOB are intentional globs
  for f in $GATE_GLOB $LINT_GLOB; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in *-e2e.sh) continue ;; esac   # the e2e suites themselves are skipped wholesale
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      case "$hit" in *e2e:reviewed-hermetic*) n=$((n+1)); continue ;; esac
      printf '⛔ UNMARKED transitive e2e call: %s:%s\n' "$b" "$hit"
      rc=1
    done < <(
      grep -nE '(\./|bash[[:space:]]+|sh[[:space:]]+|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)[A-Za-z0-9_./-]*-e2e\.sh' "$f" 2>/dev/null \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true
    )
  done
  if [ "$rc" -eq 0 ]; then
    printf 'e2e-transitive-skip: clean — %d reviewed-hermetic call(s), 0 unmarked\n' "$n"
  else
    printf 'Each line above runs an e2e suite from inside a gate the nightly believes it SKIPPED.\n'
    printf 'Fix: verify the suite is hermetic (no live ~/.claude writes), then append  # e2e:reviewed-hermetic\n'
  fi
  return "$rc"
}

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

  # 3b. the live IDL abstention monitor — a check stuck at 100% BLIND abstention is a silent
  #     no-check (blind-check law §3i, T-P6-4). Exits nonzero only on a PROVABLY inert hook;
  #     healthy-dormant hooks (100% abstained but condition-not-met) stay green. Not a *gate*/
  #     *lint* name, so step 4's glob never double-runs it.
  [ -x "$ABSTAIN" ] && run_check "idl-abstain-alarm(live)" "$ABSTAIN"

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

  # 5. the post-land net's own liveness: exists-but-stopped-stamping is an INERT check (pages).
  run_check "postland-inertness" postland_inertness

  # 6. the e2e skip must be TRANSITIVE (S3) — a gate may not smuggle an unreviewed e2e past step 4.
  run_check "e2e-transitive-skip" transitive_e2e_assert

  # ── verdict ──
  local n_red="${#REDS[@]}" summary
  if [ "$n_red" -gt 0 ]; then
    summary="RED ($n_red): ${REDS[*]}"
    local pf="$PAGEDIR/$PAGE_KEY.page"
    { now_epoch; printf 'nightly-regression RED @ %s: %s\n' "$(now_iso)" "${REDS[*]}"; \
      printf 'see %s ; re-run: scripts/nightly-regression.sh\n' "$LOG"; } > "$pf"
    local rn rf                                   # …and WHY: the failing tail, not just the name
    for rn in "${REDS[@]}"; do
      rf="$(outfile "$rn")"; [ -n "$rf" ] && [ -s "$rf" ] || continue
      printf -- '--- %s ---\n' "$rn" >> "$pf"
      { grep -E '^not ok' "$rf" 2>/dev/null || tail -15 "$rf"; } | tail -15 >> "$pf"
    done
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
  trap "rm -rf '$d' '${RUNDIR:-/nonexistent}'" EXIT   # keep the capture dir cleaned too
  mkdir -p "$d/pages" "$d/goodtests" "$d/badtests" "$d/plists" "$d/emptygl"
  printf '#!/usr/bin/env bats\n@test "pass" { true; }\n' > "$d/goodtests/ok.bats"
  printf '#!/usr/bin/env bats\n@test "fail" { false; }\n' > "$d/badtests/no.bats"
  cp "$REPO/launchd/com.claude.team-orphan-reaper.plist" "$d/plists/good.plist" 2>/dev/null \
    || printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' > "$d/plists/good.plist"
  printf '<plist><dict><string>2>&1 raw ampersand</string></dict></plist>\n' > "$d/plists/bad.plist"

  # run the invariant with a stubbed check-set (NO eval — env-scoped overrides). <pagedir> <log> <batsdir> <plistglob>
  run_inv() {
    env CC_NIGHTLY_NOTIFY=/usr/bin/true CC_NIGHTLY_NEVERSTUCK=/usr/bin/true CC_NIGHTLY_ABSTAIN=/usr/bin/true \
        CC_NIGHTLY_POSTLAND_DIR="$d/nopostland" \
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
  grep -q 'not ok' "$d/pages/nightly-regression.page" && okp "red-bats: page quotes the FAILING detail, not just the name" || badp "red-bats: page carries no failing detail"
  rm -f "$d/pages/nightly-regression.page"

  # red path (plutil): deliberately-bad fixture plist → page + RED
  run_inv "$d/pages" "$d/redp.log" "$d/goodtests" "$d/plists/bad.plist"; local prc=$?
  [ "$prc" -ne 0 ] && okp "red-plutil: nonzero exit on a bad plist" || badp "red-plutil: exit 0 on a bad plist"
  [ -f "$d/pages/nightly-regression.page" ] && okp "red-plutil: page written" || badp "red-plutil: no page"

  # green night clears a prior standing page
  run_inv "$d/pages" "$d/clear.log" "$d/goodtests" "$d/plists/good.plist"
  [ ! -f "$d/pages/nightly-regression.page" ] && okp "green night clears the standing page" || badp "green night left a stale page"

  # S4: supports_selftest must fire on a real DISPATCH and NEVER on prose / a call to another script
  mkdir -p "$d/detect"
  # shellcheck disable=SC2016  # the ${1:-} below is LITERAL fixture script text, never an expansion
  {
  printf '#!/bin/bash\ncase "${1:-}" in\n  --selftest|selftest) run ;;\nesac\n'  > "$d/detect/arm.sh"
  printf '#!/bin/bash\ncase "${1:-}" in --selftest) run ;; esac\n'               > "$d/detect/inline.sh"
  printf '#!/bin/bash\nif [ "${1:-}" = "--selftest" ]; then run; fi\n'           > "$d/detect/opt.sh"
  printf '#!/bin/bash\n# usage: x.sh --selftest\ntodo "A" "module with --selftest). prose"\n./other.sh --selftest >/dev/null && ok\n' > "$d/detect/prose.sh"
  printf '#!/bin/bash\ncase "${1:-}" in\n  selftest) run ;;\nesac\n'             > "$d/detect/bareverb.sh"
  }
  supports_selftest "$d/detect/arm.sh"      && okp "S4: detects a case arm (--selftest|selftest)" || badp "S4: missed a case arm"
  supports_selftest "$d/detect/inline.sh"   && okp "S4: detects an inline \`case … in --selftest)\`" || badp "S4: missed an inline case arm"
  supports_selftest "$d/detect/opt.sh"      && okp "S4: detects an option comparison" || badp "S4: missed an option comparison"
  supports_selftest "$d/detect/prose.sh"    && badp "S4: matched PROSE / another script's flag" || okp "S4: ignores prose + calls to other scripts"
  supports_selftest "$d/detect/bareverb.sh" && badp "S4: matched a BARE-verb arm (would pass a rejected flag)" || okp "S4: ignores a bare-verb arm"

  # S3: an unmarked transitive e2e call inside a declared gate must go RED; a reviewed one must not
  mkdir -p "$d/e2egates"
  printf '#!/bin/bash\nbash scripts/telemetry-e2e.sh >/dev/null 2>&1  # e2e:reviewed-hermetic\n' > "$d/e2egates/marked-gate.sh"
  printf '#!/bin/bash\n./scripts/newthing-e2e.sh >/dev/null 2>&1 && ok\n'                        > "$d/e2egates/unmarked-gate.sh"
  ( GATE_GLOB="$d/e2egates/marked-gate.sh"; LINT_GLOB="$d/emptygl/*.sh"; transitive_e2e_assert >/dev/null 2>&1 ) \
    && okp "S3: a  # e2e:reviewed-hermetic  call is accepted" || badp "S3: rejected a reviewed-hermetic call"
  ( GATE_GLOB="$d/e2egates/unmarked-gate.sh"; LINT_GLOB="$d/emptygl/*.sh"; transitive_e2e_assert >/dev/null 2>&1 ) \
    && badp "S3: an UNMARKED transitive e2e call passed (the skip is not enforced)" || okp "S3: an unmarked transitive e2e call goes RED"
  ( GATE_GLOB="$REPO/scripts/*gate*.sh"; LINT_GLOB="$REPO/scripts/*lint*.sh"; transitive_e2e_assert >/dev/null 2>&1 ) \
    && okp "S3: the live gate corpus carries no unmarked e2e call" || badp "S3: an unmarked e2e call exists in scripts/"

  echo "nightly-regression --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "nightly-regression --selftest: GREEN — red-path pages (bats + plutil), green-path clears, page is epoch-headed."
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--run)   regress ;;
  *)          printf 'nightly-regression: unknown arg %s (use --run | --selftest)\n' "$1" >&2; exit 2 ;;
esac
