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
BARS=()          # readiness bars at-or-under baseline: reported, never a regression (see step 4)
TIMEOUTS=()      # checks CUT at the per-check bound: a NON-VERDICT, never scored as a failure
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

# Step-4 runner: same capture as run_check, plus the three verdicts a bare exit code cannot express.
# NGR_OSA_TB is a resolved timeout(1)/gtimeout(1) (found at the top of this file) — reused here as the
# generic bound, not for its osascript purpose.
run_check_step4() { # <display-name> <basename> -- <cmd...>
  local name="$1" base="$2"; shift 2
  NCHECK=$((NCHECK+1))
  local out; out="$(outfile "$name")"; [ -n "$out" ] || out=/dev/null
  local rc=0 to
  case "$NGR_CHECK_TIMEOUT" in ''|*[!0-9]*) to=0 ;; *) to="$NGR_CHECK_TIMEOUT" ;; esac
  if [ "$to" -gt 0 ] && [ -n "$NGR_OSA_TB" ] && [ -x "$NGR_OSA_TB" ]; then
    "$NGR_OSA_TB" -k 10 "$to" "$@" >"$out" 2>&1 || rc=$?
  else
    "$@" >"$out" 2>&1 || rc=$?
  fi
  [ "$rc" -eq 0 ] && { printf '  ok   %s\n' "$name"; return 0; }

  # (1) NON-VERDICT — the check could not RUN to a conclusion, so it has no opinion. 124 = cut at the
  # bound; 137/143 = SIGKILL/SIGTERM, i.e. killed from OUTSIDE (the peer-pkill class, backlog
  # a0718a5d78b3, where concurrent sessions killed each other's gates with machine-wide patterns).
  # Scoring these as failures is what made this page unreadable: it convicted on a missing verdict.
  case "$rc" in
    124|137|143)
      printf '  CUT  %s (rc %d — NON-VERDICT: cut/killed, not a failure)\n' "$name" "$rc"
      TIMEOUTS+=("$name:rc$rc"); return 0 ;;
  esac

  # (2) READINESS BAR — judge the failed-COUNT against its declared baseline, never the exit code.
  if ngr_bar_marker "$out"; then
    local nf bmax v; nf="$(ngr_bar_failed "$out")"
    bmax="$(ngr_decl_lookup "$base" NGR_BAR_BASELINE || true)"
    v="$(ngr_bar_verdict "$nf" "$bmax")"
    case "$v" in
      bar)
        printf '  bar  %s (%s failed ≤ baseline %s — a readiness bar, not a regression)\n' "$name" "$nf" "$bmax"
        BARS+=("$base:$nf/$bmax"); return 0 ;;
      red-regressed)
        printf '  RED  %s (%s failed > baseline %s — the BAR ITSELF REGRESSED)\n' "$name" "$nf" "$bmax"
        REDS+=("$name"); return 1 ;;
      red-undeclared)
        printf '  RED  %s (readiness bar with NO declared baseline — add a row to NGR_BAR_BASELINE)\n' "$name"
        REDS+=("$name"); return 1 ;;
      *)
        printf '  RED  %s (readiness bar emitted no parsable "N met · M failed" count)\n' "$name"
        REDS+=("$name"); return 1 ;;
    esac
  fi

  # (3) a plain regression
  printf '  RED  %s (exit %d)\n' "$name" "$rc"
  REDS+=("$name"); return 1
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

# ════ step-4 CLASSIFICATION — why the RED set could never empty ═══════════════════════════════════
# Eight consecutive nights went RED (2026-07-19..26, escalating 7→8→9→12) and every one was
# unactioned. Re-triaging the 2026-07-25 set found the majority of it was manufactured HERE, by this
# runner, not by the tree: step 4 globs `*gate*.sh` + `*lint*.sh` and runs whatever it finds, so it
# counted three things that are not regressions. An alarm that can never go green carries the same
# zero bits as one that cannot fire (memory: alarm-polarity-and-attention-budget) — and it actively
# hid a real change: premortem-gate silently went 7·1 → 6·2 inside a RED nobody could read.
#
#   L  LIBRARY          a sourced file, not a runnable check. gate-policy.sh documents itself as
#                       "SOURCED, never executed (no shebang, not +x, on purpose)" — executing it
#                       yields "Permission denied", which step 4 scored as a regression.
#   U  UNSAFE           must not run inside an unattended 04:00 job. Declared below WITH the reason,
#                       because for these the naive fix is worse than the false RED: passing
#                       cc-upgrade-gate.sh its required argv would have it SPAWN LIVE SESSIONS every
#                       night (GATE_SPAWN defaults to 1), violating this file's own contract at the
#                       top ("deterministic, side-effect-free — a 3am job must not mutate the live
#                       fleet"). The usage-exit was accidentally protective; a SKIP is the real fix.
#   B  READINESS BAR    a gate whose nonzero exit means "this subsystem is not built to its bar YET",
#                       not "something broke". Eight of the fourteen *gate*.sh scripts are these, and
#                       they say so in their own output: "Red here is not a bug — it is the bar."
#                       Chronic by design ⇒ never a regression on its own.
#
# B is NOT silenced — silencing eight gates would delete eight checks (memory:
# miscalibrated-check-is-a-deleted-check). Each bar's failed-count is compared against a DECLARED
# baseline below: at-or-under the baseline reports as a bar, OVER it is a real RED, and a bar with no
# baseline row is RED too (fail-closed — a new bar must be declared, never absorbed silently).
NGR_CHECK_TIMEOUT="${CC_NIGHTLY_CHECK_TIMEOUT_S:-300}"   # per step-4 check; 0/empty = unbounded

# UNSAFE declarations: "<basename>|<reason surfaced in the skip line>".
NGR_UNSAFE_DECL=(
  "cc-upgrade-gate.sh|requires argv <bin> <model> <account>; GATE_SPAWN defaults to 1 ⇒ a correct invocation SPAWNS LIVE SESSIONS"
  "gate-cleanup.sh|sends SIGTERM/SIGKILL to gate processes — a mutation, and this job is contract-bound side-effect-free"
)
# READINESS-BAR baselines: "<basename>|<max failed criteria that is NOT a regression>".
# Raise a number ONLY with the measurement that justifies it; lower it when a bar is genuinely met.
NGR_BAR_BASELINE=(
  "premortem-gate.sh|1"                    # S-1 (reaper-horizon-lint) outstanding
  "wait-safety-gate.sh|1"                  # L1 outstanding; L2 is the keeper of the set
  "comms-safety-gate.sh|0"
  "reaper-safety-gate.sh|0"
)

ngr_decl_lookup() { # <basename> <array-name> → payload on stdout, rc 1 when undeclared
  local want="$1" arr="$2" row
  eval "set -- \"\${${arr}[@]}\""
  for row in "$@"; do
    case "$row" in "$want|"*) printf '%s' "${row#*|}"; return 0 ;; esac
  done
  return 1
}

is_library() { # a sourced file: not executable, or carrying no shebang
  [ -x "$1" ] || return 0
  head -1 "$1" 2>/dev/null | grep -q '^#!' || return 0
  return 1
}

# A readiness bar identifies ITSELF in its output, so this cannot rot the way a hardcoded list does:
# a gate that reaches its bar stops emitting the marker and rejoins the regression set on its own.
ngr_bar_marker() { grep -qE 'NOT READY|it is the bar' "$1" 2>/dev/null; }
ngr_bar_failed() { # → failed-criteria count from the gate's own "N met · M failed" line
  grep -oE '[0-9]+ met · [0-9]+ failed' "$1" 2>/dev/null | tail -1 | awk '{print $4}'
}
# The bar decision as a PURE function of (failed-count, baseline) so the selftest can RED-prove every
# branch without a seam that weakens the declarations it is testing.
ngr_bar_verdict() { # <failed> <baseline|""> → bar | red-regressed | red-undeclared | red-unparsable
  local nf="$1" bmax="${2:-}"
  [ -n "$bmax" ] || { printf 'red-undeclared'; return 0; }
  case "$nf" in ''|*[!0-9]*) printf 'red-unparsable'; return 0 ;; esac
  if [ "$nf" -le "$bmax" ]; then printf 'bar'; else printf 'red-regressed'; fi
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
  local f b reason
  # shellcheck disable=SC2086  # GATE_GLOB/LINT_GLOB are intentional globs
  for f in $GATE_GLOB $LINT_GLOB; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in
      *-e2e.sh)          SKIPS+=("$b:e2e"); printf '  skip %s (e2e — side-effectful)\n' "$b"; continue ;;
      never-stuck-gate.sh) continue ;;   # already run live above
    esac
    # L — a sourced library is not a runnable check (gate-policy.sh is +x-less ON PURPOSE)
    if is_library "$f"; then
      SKIPS+=("$b:library"); printf '  skip %s (library — sourced, not executable)\n' "$b"; continue
    fi
    # U — declared unsafe for an unattended run; the reason travels with the skip
    if reason="$(ngr_decl_lookup "$b" NGR_UNSAFE_DECL)"; then
      SKIPS+=("$b:unsafe")
      printf '  skip %s (unsafe for an automated run — %s)\n' "$b" "$reason"; continue
    fi
    if supports_selftest "$f"; then run_check_step4 "$b --selftest" "$b" "$f" --selftest
    else                            run_check_step4 "$b" "$b" "$f"; fi
  done
  # A declaration that no longer matches the tree is a rotting exemption — the class that let
  # test-hermeticity-lint's stale allowlist stop discriminating. Name it RED, never carry it.
  # Keyed on the file's EXISTENCE, not on whether this run's glob happened to iterate it: the globs
  # are env-overridable (the selftest points them at empty fixture dirs), so a glob-derived answer
  # would report every declaration stale whenever the glob is narrowed — which is a statement about
  # the glob, not about the declaration.
  local d dn
  for d in "${NGR_UNSAFE_DECL[@]}"; do
    dn="${d%%|*}"
    [ -f "$REPO/scripts/$dn" ] && continue
    printf '  RED  stale UNSAFE declaration: %s no longer exists under %s/scripts\n' "$dn" "$REPO"
    REDS+=("stale-decl:$dn")
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
    # Bars and non-verdicts go on the page too — visible, but never inside the RED count. Reading
    # "RED (12)" when nine of the twelve were bars/cuts is what made eight nights unactionable.
    [ "${#BARS[@]}" -gt 0 ]     && printf -- '--- readiness bars (at/under baseline — NOT regressions) ---\n%s\n' "${BARS[*]}"     >> "$pf"
    [ "${#TIMEOUTS[@]}" -gt 0 ] && printf -- '--- NON-VERDICTS (cut/killed — no opinion, re-run on a quiet box) ---\n%s\n' "${TIMEOUTS[*]}" >> "$pf"
    notify "Claude nightly-regression RED" "$n_red check(s) failed: ${REDS[*]}"
  else
    summary="GREEN ($NCHECK checks)"
    rm -f "$PAGEDIR/$PAGE_KEY.page" 2>/dev/null || true   # clear a prior standing alarm on a green night
  fi
  [ "${#SKIPS[@]}" -gt 0 ]    && summary="$summary; skipped: ${SKIPS[*]}"
  [ "${#BARS[@]}" -gt 0 ]     && summary="$summary; bars: ${BARS[*]}"
  [ "${#TIMEOUTS[@]}" -gt 0 ] && summary="$summary; non-verdict: ${TIMEOUTS[*]}"
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

  # ── step-4 classification (2026-07-30): the three verdicts a bare exit code cannot express ──
  # Each branch is RED-proven: the assertion must be able to FAIL, so every positive case is paired
  # with the negative that would have been mis-scored before.
  mkdir -p "$d/cls"
  printf '# shellcheck shell=bash\nX=1\n'            > "$d/cls/lib-noshebang.sh"   # no shebang, not +x
  printf '#!/bin/bash\necho hi\n'                    > "$d/cls/runnable.sh"; chmod +x "$d/cls/runnable.sh"
  printf '#!/bin/bash\necho hi\n'                    > "$d/cls/notexec.sh"         # shebang but not +x
  is_library "$d/cls/lib-noshebang.sh" && okp "L: a shebang-less non-+x file is a LIBRARY" || badp "L: missed a library"
  is_library "$d/cls/notexec.sh"       && okp "L: a non-executable file is a LIBRARY" || badp "L: missed a non-executable"
  is_library "$d/cls/runnable.sh"      && badp "L: called a real +x script a library" || okp "L: a +x script with a shebang is NOT a library"

  # the real tree's own case — gate-policy.sh documents itself as sourced-never-executed
  if [ -f "$REPO/scripts/gate-policy.sh" ]; then
    is_library "$REPO/scripts/gate-policy.sh" && okp "L: live gate-policy.sh classifies as a library" || badp "L: live gate-policy.sh would still be EXECUTED"
  fi

  # UNSAFE/BASELINE declarations must actually resolve (a typo'd row silently exempts nothing)
  ngr_decl_lookup cc-upgrade-gate.sh NGR_UNSAFE_DECL >/dev/null && okp "U: cc-upgrade-gate.sh is declared unsafe" || badp "U: cc-upgrade-gate.sh not declared"
  ngr_decl_lookup gate-cleanup.sh    NGR_UNSAFE_DECL >/dev/null && okp "U: gate-cleanup.sh is declared unsafe" || badp "U: gate-cleanup.sh not declared"
  ngr_decl_lookup pane-id-lint.sh    NGR_UNSAFE_DECL >/dev/null && badp "U: exempted a script that must still RUN" || okp "U: an undeclared script is NOT exempt"
  [ "$(ngr_decl_lookup premortem-gate.sh NGR_BAR_BASELINE)" = 1 ] && okp "B: premortem-gate baseline resolves to 1" || badp "B: premortem-gate baseline missing/wrong"

  # bar marker detection, off the gates' OWN wording
  printf 'premortem-gate: 7 met · 1 failed · 0 NOT BUILT\n⇒ RUNTIME PHASE: NOT READY TO UN-HOLD\n' > "$d/cls/bar.out"
  printf 'reaper-horizon-lint: ⛔ 4 violation(s).\n'                                              > "$d/cls/plain.out"
  ngr_bar_marker "$d/cls/bar.out"   && okp "B: detects a readiness bar from its own NOT READY line" || badp "B: missed a readiness bar"
  ngr_bar_marker "$d/cls/plain.out" && badp "B: called a plain lint failure a readiness bar" || okp "B: a plain lint failure is NOT a bar"
  [ "$(ngr_bar_failed "$d/cls/bar.out")" = 1 ] && okp "B: parses the failed-count from 'N met · M failed'" || badp "B: failed-count parse wrong"

  # the decision itself — every branch, including the two that MUST stay RED
  [ "$(ngr_bar_verdict 1 1)" = bar ]            && okp "B: failed == baseline ⇒ bar, not a regression" || badp "B: at-baseline scored wrong"
  [ "$(ngr_bar_verdict 0 1)" = bar ]            && okp "B: failed  < baseline ⇒ bar" || badp "B: under-baseline scored wrong"
  [ "$(ngr_bar_verdict 2 1)" = red-regressed ]  && okp "B: failed  > baseline ⇒ RED (the 7·1→6·2 case)" || badp "B: a REGRESSED bar was absorbed"
  [ "$(ngr_bar_verdict 1 '')" = red-undeclared ] && okp "B: an undeclared bar ⇒ RED (fail-closed)" || badp "B: an undeclared bar was absorbed"
  [ "$(ngr_bar_verdict '' 1)" = red-unparsable ] && okp "B: an unparsable count ⇒ RED, never silently a bar" || badp "B: unparsable count absorbed"

  # NON-VERDICT: cut (124) and externally killed (137/143) must not be scored as failures
  local nvd; nvd="$d/cls/nv"; mkdir -p "$nvd"
  printf '#!/bin/bash\nexit 143\n' > "$nvd/killed-gate.sh"; chmod +x "$nvd/killed-gate.sh"
  printf '#!/bin/bash\nexit 1\n'   > "$nvd/broken-gate.sh"; chmod +x "$nvd/broken-gate.sh"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "killed-gate.sh" killed-gate.sh "$nvd/killed-gate.sh" >/dev/null 2>&1
    [ "${#REDS[@]}" -eq 0 ] && [ "${#TIMEOUTS[@]}" -eq 1 ] ) \
    && okp "NV: rc 143 (SIGTERM — peer-pkill class) is a NON-VERDICT, not RED" || badp "NV: a killed check was convicted as RED"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "broken-gate.sh" broken-gate.sh "$nvd/broken-gate.sh" >/dev/null 2>&1
    [ "${#REDS[@]}" -eq 1 ] && [ "${#TIMEOUTS[@]}" -eq 0 ] ) \
    && okp "NV: a genuine exit 1 is still RED (the control)" || badp "NV: a real failure stopped being RED"

  echo "nightly-regression --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "nightly-regression --selftest: GREEN — red-path pages (bats + plutil), green-path clears, page is epoch-headed."
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--run)   regress ;;
  *)          printf 'nightly-regression: unknown arg %s (use --run | --selftest)\n' "$1" >&2; exit 2 ;;
esac
