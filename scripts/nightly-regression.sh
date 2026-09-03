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
#   3c. postland-verify.sh --selftest    — the post-land verifier's OWN instrument. Not a *gate*/*lint*
#                                          name, so step 4's globs never saw it. Run against a SANDBOXED
#                                          state dir (the step says why that is not optional).
#   4. every scripts/*gate*.sh + *lint*.sh: `--selftest` where supported, else a bare read-only run.
#      SKIPS *-e2e.sh (side-effectful — would spawn panes/sessions) — the skip is LOGGED, never silent.
#   5. postland_inertness — the post-land verification net's OWN liveness: stamps dir present but a
#      settled (>2h) trunk commit unstamped = the net stopped stamping (blind-check law). Abstains
#      green when the net isn't adopted (no stamps dir). Env seam: CC_NIGHTLY_POSTLAND_DIR/_AGE.
#   5b. postland_green_starvation — the OTHER half of that law: a net that stamps but never stamps
#      GREEN proves nothing, and step 5 cannot see it (a `cut`/`red` stamp satisfies it). Reds when
#      trunk has carried UNPROVEN content past the green budget. Seam: CC_NIGHTLY_POSTLAND_GREEN_MAX/_SCAN.
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
# The scripts dir this file SHIPS in — BASH_SOURCE-derived, so NOT redirectable by CC_NIGHTLY_REPO.
# NGR_UNSAFE_DECL declares basenames that travel WITH this script, so its staleness must be judged
# against this directory and never against $REPO (see the stale-declaration loop in step 4).
SELF_SCRIPTS="$(dirname "$SELF")"
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
POSTLANDV="${CC_NIGHTLY_POSTLAND_VERIFY:-$REPO/scripts/postland-verify.sh}"   # the post-land verifier's OWN instrument (step 3c); stubbable
PAGE_KEY="${CC_NIGHTLY_PAGE_KEY:-nightly-regression}"
POSTLAND_DIR="${CC_NIGHTLY_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"   # post-land verification net; stubbable
POSTLAND_AGE="${CC_NIGHTLY_POSTLAND_AGE:-7200}"                              # a trunk commit older than this MUST be stamped
# The GREEN budget: how long trunk may carry content nothing has proven. 24h is the figure the
# starvation this check exists for was measured against (backlog 01ab05685857: breaches of 57h, 53h
# and 26h, none of which paged). SCAN bounds the walk down trunk — 200 is deploy-live's own SCAN_N,
# so both instruments look through the same window and cannot disagree about what is visible.
POSTLAND_GREEN_MAX="${CC_NIGHTLY_POSTLAND_GREEN_MAX:-86400}"
POSTLAND_GREEN_SCAN="${CC_NIGHTLY_POSTLAND_GREEN_SCAN:-200}"
case "$POSTLAND_GREEN_MAX"  in ''|*[!0-9]*) POSTLAND_GREEN_MAX=86400 ;; esac
case "$POSTLAND_GREEN_SCAN" in ''|*[!0-9]*|0) POSTLAND_GREEN_SCAN=200 ;; esac

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
  local rc=0 to dto _nv
  case "$NGR_CHECK_TIMEOUT" in ''|*[!0-9]*) to=0 ;; *) to="$NGR_CHECK_TIMEOUT" ;; esac
  # A per-check MEASURED bound outranks the global default. The default is sized for one gate/lint;
  # a check that is itself a COMPOSITION of gates is a different animal, and a bound that does not
  # fit turns a real verdict into a permanent NON-VERDICT — worse than the too-late page it prevents.
  if dto="$(ngr_decl_lookup "$base" NGR_CHECK_TIMEOUT_DECL)"; then
    case "$dto" in ''|*[!0-9]*) ;; *) to="$dto" ;; esac
  fi
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
  #
  # 75 = EX_TEMPFAIL, added 2026-08-08 (item 38e4601fa933). bin/cc-bats — which every `bats` call
  # resolves to, via a PATH symlink — grew an ADMISSION BOUND on 2026-08-06 that REFUSES when the
  # box is over CC_BATS_MAX_LOAD_PER_CORE with CC_BATS_MAX_ROOTS suites already running, exiting 75
  # and printing "nothing ran, nothing was verified — this is a DEFERRAL, not a test result".
  # cc-bats did its part; the GATES threw it away (`bats … >/dev/null 2>&1`, every nonzero ⇒ RED),
  # so a deferral arrived here disguised as a bar count — a tally over criteria that never executed,
  # which the bar branch below would then compare against a declared baseline and score as met or
  # regressed. That is the same "convicted on a missing verdict" defect this block was built to
  # stop, re-entering one level down through a NEW exit code that fell into everyone's `else` arm
  # (memory: new-enum-member-falls-into-fail-closed-default). The gates now propagate 75 unchanged;
  # this arm is what makes propagating it correct.
  case "$rc" in
    124|137|143|75)
      case "$rc" in
        75) _nv='cc-bats DEFERRAL — the admission bound refused, the proof never ran' ;;
        *)  _nv='cut/killed, not a failure' ;;
      esac
      printf '  CUT  %s (rc %d — NON-VERDICT: %s)\n' "$name" "$rc" "$_nv"
      TIMEOUTS+=("$name:rc$rc"); return 0 ;;
    2)
      # rc 2 is this repo's lint convention for "could not run", and it is MARKER-GATED here for the
      # reason above — it is the one code in this case that a broken script can also produce by
      # accident. scripts/test-hermeticity-lint.sh --selftest reaches this arm (backlog 2c5ab136d63f):
      # its case (e) lints the REAL tree, so one lost fork on a loaded box used to make the whole
      # selftest exit 1 and be scored here as a regression — a clean tree convicted by a busy box.
      if ngr_nonverdict_marker "$out"; then
        printf '  CUT  %s (rc 2 — NON-VERDICT: %s)\n' "$name" 'the check says it could not run a predicate'
        TIMEOUTS+=("$name:rc2"); return 0
      fi ;;
  esac

  # (2) COUNT-JUDGED — judge the failed-COUNT against its declared baseline, never the exit code.
  # Two ways in, and the second is why never-stuck-gate stopped being unreadable:
  #   · the output self-identifies as a READINESS BAR (chronic-by-design; it may sit at a nonzero
  #     baseline), or
  #   · the check carries a DECLARED baseline, which is itself the statement "this check's verdict
  #     is its count". An INVARIANT is exactly that with the baseline pinned at 0 — it must never
  #     print a bar marker, because it is not chronic-by-design and a nonzero row here would declare
  #     a broken invariant tolerable.
  # Widening this entry cannot silence anything at baseline 0: ngr_bar_verdict returns `bar` only
  # when failed ≤ baseline, i.e. failed = 0, i.e. the check exited 0 and never reached this branch.
  # So for a 0-baseline row the only reachable outcomes are red-regressed and red-unparsable.
  if ngr_bar_marker "$out" || ngr_decl_lookup "$base" NGR_BAR_BASELINE >/dev/null; then
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
        # rc travels: a DECLARED check can reach here by dying before it counts anything (syntax
        # error, set -u, argv rejection), and "no parsable count" alone would drop the one datum
        # that says which.
        printf '  RED  %s (exit %d — no parsable "N met · M failed" count; judged a plain failure)\n' "$name" "$rc"
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
#
# The redirect below is NOT a style choice. As a PIPELINE this function was position-dependent:
# `grep -q` exits the instant it matches, the upstream `grep -vE` dies of SIGPIPE on its next block
# write, and `set -uo pipefail` (line 27) promotes that 141 to the pipeline's status — so an EARLY
# match read as "no --selftest" and the gate was silently BARE-RUN. A LATE match survives because the
# producer has already finished writing.
#
# It was a LATENT trap, not a live one: no shipped script had an early arm, so nothing had ever
# tripped it, and every S4 fixture below is 3-5 lines long — their matches sit at EOF by
# construction, so all five passed with the defect present. The first script to add an early arm hit
# it on the first run (gate-select.sh, arm at stripped line 27 of 521, rc=141 ⇒ bare-run), while
# gate-classify.sh (arm at 91 of 94) worked purely by position. Measured on /bin/bash 3.2, the shell
# the plist runs — under zsh the same pipeline returns 0, so probing in the wrong shell hides it.
# Process substitution keeps the producer OUT of the exit status, so the rc is grep -q's alone.
supports_selftest() {
  grep -qE -- \
    '^[[:space:]]*\(?[-|A-Za-z0-9_*."]*--selftest[-|A-Za-z0-9_*."]*\)|(^|[^[:alnum:]_])case[[:space:]].*[[:space:]]in[[:space:]].*--selftest[-|A-Za-z0-9_*."]*\)|==?[[:space:]]*"?--selftest"?' \
    < <(grep -vE '^[[:space:]]*#' "$1" 2>/dev/null)
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
# SC2034 is a FALSE POSITIVE here, and the discriminator is worth recording: every read of this array
# goes through ngr_decl_lookup's `eval "set -- \"\${${arr}[@]}\""` indirection (:137 live, :511
# selftest), which no static linter can follow. Its sibling NGR_UNSAFE_DECL is NOT flagged only
# because :365 also expands it directly — the difference is the linter's visibility, not the read.
# Do not "fix" this by adding a decorative direct expansion: the live proof is the selftest's
# "B: premortem-gate baseline resolves to a number", which an actually-unused array cannot pass.
# shellcheck disable=SC2034
NGR_BAR_BASELINE=(
  # premortem + wait-safety reached their bars on 2026-07-30 (8·0 and 13·0, both "un-hold is
  # defensible") once reaper-horizon-lint went clean. They now exit 0 and never reach the bar branch
  # at all — but these rows are pinned at 0 deliberately: leaving them at the old 1 would let the
  # FIRST future regression back in silently, which is the miscalibration this whole mechanism exists
  # to avoid. A baseline is a ratchet; it only ever tightens.
  "premortem-gate.sh|0"
  "wait-safety-gate.sh|0"
  "comms-safety-gate.sh|0"
  "reaper-safety-gate.sh|0"
  "respawn-safety-gate.sh|1"               # measured 2026-07-30: 1 met · 1 failed
  "route-safety-gate.sh|0"                 # measured 2026-07-30: 2 met · 0 failed
  # never-stuck-gate is an INVARIANT, not a readiness bar: 0 is its baseline BY DEFINITION, and a
  # nonzero row here would declare a broken invariant tolerable. The row exists so the page can
  # print HOW FAR it slipped. Measured 2026-08-08: 22 met · 0 failed at trunk AND at the deployed
  # layer; the 2026-07-30 pre-fix revision b21ff641 reproduces 20 met · 2 failed (wait-safety-gate +
  # premortem-gate, both from one reaper-horizon-lint red, closed by a9b784eb). Without this row
  # those two states print the identical line — `RED never-stuck-gate(live) (exit 1)` — which is the
  # 21·0→19·2 slip this whole job was built to catch, still invisible on its own page.
  "never-stuck-gate.sh|0"
  # MEASURED 2026-08-08 (item 38e4601fa933), resolving the two rows this block used to hold open as
  # "DELIBERATELY UNDECLARED — both re-run bats internally and outran a 900s probe on a loaded box,
  # so no honest baseline exists yet … Never guess these." That instruction was followed, and what
  # it turned up was not slowness. Recorded in full because the reasoning, not the number, is the
  # durable part:
  #
  #   · Both gates are GREEN — every registered criterion is met, so both exit 0 and never reach the
  #     bar branch at all. Per-suite, admission-verified, this box, 1-min load 18.6-21.0 on 10 cores:
  #       limit-reset       tests/lr-reset-poller.bats  23/23 ok, rc 0, 23s
  #       session-lifecycle tests/cc-classify.bats      58/58 ok, rc 0, 48s
  #                         tests/cc-reaper.bats        94/94 ok, rc 0, 205s
  #                         bin/cc-teardown --selftest        rc 0, 13s
  #     ⇒ limit-reset 1 met · 0 failed · session-lifecycle 3 met · 0 failed. Both rows are therefore
  #     0, pinned for the same reason premortem and wait-safety are: a baseline is a RATCHET, and
  #     leaving room the bar does not need lets the first future regression back in silently.
  #
  #   · The 900s "timeout" was never the suites — 289s covers all four proofs. It was bin/cc-bats'
  #     ADMISSION BOUND (2026-08-06) refusing under load with rc 75 and the message "nothing ran,
  #     nothing was verified — this is a DEFERRAL, not a test result", which both gates discarded
  #     via `>/dev/null 2>&1` and reported as a failed criterion. Measured at load 22: they emitted
  #     "0 met · 1 failed" in 0s and "1 met · 2 failed" in 14s having run ZERO tests. Declaring a
  #     baseline off THOSE numbers would have pinned a bar to a non-verdict — which is precisely
  #     what "Never guess these" was protecting. Both gates now propagate 75 and the NON-VERDICT
  #     arm above classifies it.
  "limit-reset-safety-gate.sh|0"           # measured 2026-08-08: 1 met · 0 failed (suite 23/23 green)
  "session-lifecycle-safety-gate.sh|0"     # measured 2026-08-08: 3 met · 0 failed (CL 58/58 · RP 94/94 · TD ok)
)

# PER-CHECK TIMEOUT overrides: "<basename>|<seconds>". Read through the same ngr_decl_lookup
# indirection as its two siblings, so SC2034 is the same false positive documented above.
# A bound must fit the BAND it runs in, not the bench it was sized on: this job's plist declares
# ProcessType Background + Nice 10 + LowPriorityIO, and a check cut at its bound reports rc 124 —
# a NON-VERDICT forever, which is silence wearing a verdict's clothes.
# shellcheck disable=SC2034
NGR_CHECK_TIMEOUT_DECL=(
  # never-stuck-gate runs EIGHT sibling gates, four of which re-run bats internally, so it is this
  # job's longest check by construction. Measured 2026-08-08 on this box: 245s in the foreground at
  # load 7.6, and 422s under the plist's OWN band (taskpolicy -c background + nice 10) at load 9.9 —
  # a 1.72x tax that puts it 41% ABOVE the 300s default. Moving it onto the bounded runner at the
  # default would have converted the job's headline signal into a nightly rc-124 NON-VERDICT. 1800s
  # is ~4.3x the measured background number and is still a TIGHTENING: on run_check it was unbounded.
  "never-stuck-gate.sh|1800"
  # postland-verify --selftest is the same animal for the same reason: it is not one check but a
  # sequence of FIXTURE LANDS, each running a real bats corpus inside a real git repo, plus the
  # pre-plan grace assertions that are timing by construction. MEASURED 2026-08-12 at trunk
  # 1b044624: 424s wall in the FOREGROUND (53 passed, 0 failed), of which 3.5s is user time — it is
  # dominated by waits, so it does not shrink on a bigger box and it does grow under the plist's
  # ProcessType Background + Nice 10. Applying the same 1.72x band tax never-stuck-gate measured
  # puts it near 730s, i.e. 2.4x ABOVE the 300s default: at the default this check would report rc
  # 124 every night forever — a NON-VERDICT, which is silence wearing a verdict's clothes, and
  # exactly the failure mode that would leave the instrument's rot as unwatched as it is today.
  "postland-verify.sh|1800"
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
# Does the check SAY it reached no verdict? This exists because rc 2 cannot be added to the blanket
# NON-VERDICT list in run_check_step4: `bash` itself exits 2 on a syntax error, so a bare `2)` arm
# would turn a broken check into a silent CUT — fail-OPEN, the one direction that block must never
# grow in. So the check has to announce it, and only our lints' two exit-2 announcements count. A
# syntax error, an argv rejection and a bad-ROOT ("⛔ not a directory") print none of them and stay
# RED. Both directions are proved in the selftest; the marker is the whole gate, so a widened regex
# here is a silenced red.
ngr_nonverdict_marker() { grep -qE '⛔ UNUSABLE|⛔ NON-VERDICT|SELFTEST NON-VERDICT' "$1" 2>/dev/null; }
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

# Blind-check law, SECOND HALF. Step 5 keys on a stamp EXISTING, and the producer's own vocabulary
# says a `cut` stamp means nothing was proven (postland-verify.sh:stamp_is_verdict separates
# green|red|hung from cut, and the runner re-queues a cut tree precisely because it decided nothing).
# So a verifier that stamps every tick and never earns a green reads ALIVE at step 5 while trunk goes
# unproven for days — measured on this box as three breaches of the 24h budget, 57h/53h/26h, none of
# which paged anywhere the operator reads (backlog 01ab05685857). "The net is running" and "the net
# is proving something" are two facts, and only the first had an instrument.
#
# THE MEASURE IS THE UNPROVEN SPAN, NEVER THE NEWEST GREEN'S AGE — the row's own wording ("newest
# GREEN stamp 46h old") is the sampled value, not the condition, and keying on it reds a healthy
# machine. Stamps are TREE-keyed, so a tree already proven is deliberately never re-run: a trunk that
# sits quiet for 30h keeps a 30h-old green and is FULLY proven the whole time. What harms is trunk
# CARRYING content nothing has re-proven, so the quantity is the age of the OLDEST trunk commit still
# unproven — which is also immune to the converse false positive (a 26h-quiet trunk that moved ten
# minutes ago has a 26h-old newest green and nothing wrong with it).
#
# Abstains GREEN on three facts, each of them somebody else's: no stamps dir (the net is not adopted),
# no stamp at all (step 5 owns that — two checks on one fact is two pages for one repair), and trunk
# unresolvable (no subject). An unreadable commit clock abstains too: a check that cannot read its own
# quantity has no verdict, and inventing one here would page over a corrupt object, not over famine.
stamp_verdict() { # <stamp-file> → green|red|hung|cut ("" when absent/unparseable)
  sed -n 's/.*"verdict":"\([a-z]*\)".*/\1/p' "${1:-/nonexistent}" 2>/dev/null | head -1
}
postland_green_starvation() {
  local stamps="$POSTLAND_DIR/stamps" offbox="$POSTLAND_DIR/offbox"
  local sha tree ct oldest="" oldest_ct="" n=0 newest_v="" acquitted="" age
  [ -d "$stamps" ] || return 0                                   # net not adopted → abstain
  set -- "$stamps"/*.json
  [ -e "$1" ] || return 0                                        # never stamped → step 5's fact
  git -C "$REPO" fetch origin main >/dev/null 2>&1 || true        # best-effort freshness
  git -C "$REPO" rev-parse origin/main >/dev/null 2>&1 || return 0
  # Fed by a HERE-DOC, not a pipe: a pipe runs the loop in a subshell and every count below would be
  # discarded at the `done`, so the check would abstain on exactly the trunk it was built to convict.
  while IFS=' ' read -r sha tree ct; do
    [ -n "$tree" ] || continue
    grep -q '"verdict":"green"' "$stamps/$tree.json" 2>/dev/null && break   # proven from here down
    n=$((n+1)); oldest="$sha"; oldest_ct="$ct"
    [ -n "$newest_v" ] || newest_v="$(stamp_verdict "$stamps/$tree.json")"
    # The off-box lane's acquittal is a WEAKER claim (a hermetic SUBSET), so it never cancels this
    # red — the host-coupled suites stay unproven either way. It is reported because it is the one
    # fact that changes the repair: a starving verifier over a CI-acquitted tree is a machine
    # problem, and a span nothing anywhere has proven is a code problem. Both fields, like
    # deploy-live.sh:is_offbox_green — a bare file drop must not launder a subset into an acquittal.
    [ -n "$acquitted" ] || { grep -q '"verdict":"green"' "$offbox/$tree.json" 2>/dev/null \
      && grep -q '"scope":"offbox-hermetic"' "$offbox/$tree.json" 2>/dev/null && acquitted="$sha"; }
  done <<EOF
$(git -C "$REPO" log -n "$POSTLAND_GREEN_SCAN" --format='%H %T %ct' origin/main 2>/dev/null)
EOF
  [ "$n" -gt 0 ] || return 0                                     # trunk tip itself is green → alive
  case "${oldest_ct:-}" in ''|*[!0-9]*) return 0 ;; esac         # unreadable clock → no verdict
  age=$(( $(now_epoch) - oldest_ct ))
  [ "$age" -gt "$POSTLAND_GREEN_MAX" ] || return 0
  local acq="none — nothing anywhere has proven this span"
  [ -n "$acquitted" ] && acq="$(printf 'yes, off-box hermetic green from %.12s down' "$acquitted")"
  printf 'postland net GREEN-STARVED: trunk has carried UNPROVEN content for %ss (max %ss) — %s commit(s) sit above the newest green, oldest %.12s; newest verdict over that span: %s; off-box acquittal: %s\n' \
    "$age" "$POSTLAND_GREEN_MAX" "$n" "$oldest" "${newest_v:-none (unstamped)}" \
    "$acq"                                                       # captured → quoted on the RED page
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
  #
  # `</dev/null` — bats does not read stdin itself but INHERITS it into every test, and a suite that
  # stubs a stdin-consuming binary with an unconditional `cat` then waits forever for an EOF that is
  # not coming (5e460544; ce13bd08 fixed the landing runners). MEASURED 2026-08-06, and it corrects
  # the premise those commits shipped with: launchd hands its child /dev/null on fd 0 already (probe:
  # a RunAtLoad job read `lsof -d 0` → /dev/null), so the 04:00 run is NOT the exposed path. The
  # exposed path is the one this script is run on by hand and by the desk — a Claude Code session's
  # fd 0 is a unix SOCKET, and a child reading it never sees EOF (measured: rc 124). That is the
  # inverted polarity that makes this worth a redirect: a hung nightly is indistinguishable from a
  # slow one and nothing alarms.
  #
  # ON `run_check` AND NOT INSIDE IT: the redirect rides this ONE invocation (a redirect on a
  # function call applies to its whole body, so the `"$@"` inside gets it). run_check also runs
  # plutil, never-stuck-gate and the step-4 gates; the screen that licenses /dev/null covers the
  # bats tree only, so it stays per call site — same reasoning that kept it out of postland-verify's
  # `bounded` helper. Step 4's gates need nothing here: each carries the redirect at its own bats
  # site, so the whole chain is immune at the leaf.
  if command -v bats >/dev/null 2>&1; then
    run_check "bats:$(basename "$BATS_DIR")" bats "$BATS_DIR" </dev/null
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
  # On run_check_step4, NOT run_check: this is the one check this job's own header names as its
  # reason to exist, and on the plain runner it got none of the three verdicts step 4 was built to
  # express. Two consequences, both measured 2026-08-08:
  #   · it is the job's LONGEST check (422s in the plist's own band) and therefore the likeliest to
  #     be cut or peer-pkilled — and run_check convicts rc 124/137/143 as RED. The selftest below
  #     has asserted "rc 143 is a NON-VERDICT" since 2026-07-30, but its subject was step 4, so the
  #     property was proven for every check EXCEPT the headline one.
  #   · its verdict is a COUNT ("N met · M failed"), and run_check threw it away: a slip to 20·2 and
  #     a collapse to 3·19 both printed `RED never-stuck-gate(live) (exit 1)`. That is the same
  #     blindness that let premortem slip 7·1 → 6·2 in plain view of this page.
  [ -x "$NEVERSTUCK" ] && run_check_step4 "never-stuck-gate(live)" never-stuck-gate.sh "$NEVERSTUCK"

  # 3b. the live IDL abstention monitor — a check stuck at 100% BLIND abstention is a silent
  #     no-check (blind-check law §3i, T-P6-4). Exits nonzero only on a PROVABLY inert hook;
  #     healthy-dormant hooks (100% abstained but condition-not-met) stay green. Not a *gate*/
  #     *lint* name, so step 4's glob never double-runs it.
  [ -x "$ABSTAIN" ] && run_check "idl-abstain-alarm(live)" "$ABSTAIN"

  # 3c. the post-land verifier's OWN instrument (item cb8b9620ddef, 2026-08-09).
  #
  # WHY IT IS ITS OWN STEP. Step 4 globs *gate*.sh + *lint*.sh; `postland-verify.sh` matches
  # NEITHER, so its --selftest ran in exactly one place — docs/activation/pending-activation/
  # 14-land-pipeline-v2-activate.sh, which gates on it at line 48. That is the rare moment it
  # blocks something, not the standing moment a regression is caught, and the difference is
  # measurable: an assertion invalidated by the 2026-08-08 identity-drop change sat RED on trunk
  # with nothing to notice it. This job already carries step 5, which watches whether that
  # verifier is STAMPING; nothing watched whether its own instrument still DISCRIMINATES. A net
  # whose liveness is monitored and whose correctness is not is the blind-check law one level up.
  #
  # SANDBOXED STATE IS NOT OPTIONAL — the check would otherwise MANUFACTURE the red beside it.
  # postland-verify's main() runs ensure_dirs BEFORE dispatch, so a bare `--selftest` mkdir -p's
  # the LIVE $STATE/stamps. Step 5 (postland_inertness) abstains green on exactly one fact — that
  # stamps dir NOT existing, i.e. "the net is not adopted here". So on an unadopted box this check
  # would create the dir on its first night and step 5 would go RED from the second night on,
  # forever, over a net nobody ever turned on. That is the step-4 classification defect
  # (a runner counting things that are not regressions) re-entering through a new door.
  # CC_POSTLAND_DIR/CC_PAGES_DIR/CC_IDL are the three $HOME-rooted knobs ensure_dirs touches;
  # pointing them into this run's own capture dir costs the selftest nothing, because every
  # assertion it makes is already fixture- or $SELF-based — its own last assertion, "sandbox: every
  # $HOME-rooted path knob is overridden by run_fixture", is the standing proof of that. The one
  # thing lost is its live-lock concurrency note, which cannot fire against a sandbox.
  #
  # NO SANDBOX ⇒ SKIP, never a bare run: this file's contract at the top is deterministic and
  # side-effect-free, so an unsandboxable run is one we decline, not one we take anyway.
  # KILL SWITCH ⇒ SKIP, never a green: POSTLAND_VERIFY=off exits 0 ABOVE the dispatch, so a
  # kill-switched run would score `ok` having proven nothing — a kill switch reading as a verdict,
  # the same two-meanings-for-exit-0 defect postland-verify itself dispatches --falsify-red above
  # the switch to avoid.
  if [ -x "$POSTLANDV" ]; then
    if [ "${POSTLAND_VERIFY:-on}" = "off" ]; then
      SKIPS+=("postland-verify.sh:kill-switched")
      printf '  skip postland-verify.sh --selftest (POSTLAND_VERIFY=off exits 0 above the dispatch — a green here would be a verdict the instrument never gave)\n'
    elif [ -n "$RUNDIR" ]; then
      mkdir -p "$RUNDIR/pv" 2>/dev/null || true
      run_check_step4 "postland-verify.sh --selftest" postland-verify.sh \
        env CC_POSTLAND_DIR="$RUNDIR/pv/state" CC_PAGES_DIR="$RUNDIR/pv/pages" \
            CC_IDL="$RUNDIR/pv/idl.jsonl" "$POSTLANDV" --selftest
    else
      SKIPS+=("postland-verify.sh:no-sandbox")
      printf '  skip postland-verify.sh --selftest (no capture dir — refusing to run it against LIVE postland state)\n'
    fi
  fi

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
  # …and $REPO is the SAME class of redirectable input, one level up. It defaults to this script's
  # checkout but CC_NIGHTLY_REPO overrides it, and a harness legitimately points it at a fixture
  # checkout to exercise the git-based checks (tests/deploy-live.bats does exactly this for
  # postland-inertness). A $REPO-derived answer then reports EVERY declaration stale — a statement
  # about the fixture repo, not about the declaration. NGR_UNSAFE_DECL names basenames that ship in
  # THIS file's own scripts dir, so judge it against $SELF_SCRIPTS, which no env var can move.
  # (Landed red: eb85b3f4 keyed this on $REPO and turned deploy-live.bats:187 red from 2026-07-30.)
  local d dn
  for d in "${NGR_UNSAFE_DECL[@]}"; do
    dn="${d%%|*}"
    [ -f "$SELF_SCRIPTS/$dn" ] && continue
    printf '  RED  stale UNSAFE declaration: %s no longer exists under %s\n' "$dn" "$SELF_SCRIPTS"
    REDS+=("stale-decl:$dn")
  done

  # 5. the post-land net's own liveness: exists-but-stopped-stamping is an INERT check (pages).
  run_check "postland-inertness" postland_inertness

  # 5b. …and stamping-but-never-GREEN is the same blindness one step on: the net runs, step 5 is
  # satisfied, and trunk goes unproven. Separate check, separate name — folding it into step 5 would
  # report one repair under the other's name, and they are repaired differently.
  run_check "postland-green-starvation" postland_green_starvation

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
      # The <N> is what makes a line a RESULT (TAP: `not ok <N> <desc>`). Without it this also
      # quoted anything that merely OPENS with those four bytes — a line truncated mid-write, or an
      # unprefixed stderr splice, both routine in a capture taken 2>&1. Two costs, and the second is
      # the one that hurts: the page's 15-line budget gets spent on noise, AND the `|| tail -15`
      # fallback that exists for precisely this case never fires, because the loose grep "succeeded".
      # Same spelling as scripts/postland-verify.sh TAP_NOTOK_RE (C30), scripts/ship-land.sh and
      # scripts/deploy-live.sh — pinned equal by tests/tap-grammar-parity.bats.
      { grep -aE '^not ok [0-9]+' "$rf" 2>/dev/null || tail -15 "$rf"; } | tail -15 >> "$pf"
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
  mkdir -p "$d/pages" "$d/goodtests" "$d/badtests" "$d/torntests" "$d/plists" "$d/emptygl"
  printf '#!/usr/bin/env bats\n@test "pass" { true; }\n' > "$d/goodtests/ok.bats"
  printf '#!/usr/bin/env bats\n@test "fail" { false; }\n' > "$d/badtests/no.bats"
  # A failing suite whose stream ALSO carries torn/spliced bytes. File-level output is written by
  # bats OUTSIDE any test, so it reaches the capture UNPREFIXED (measured: twice — the gather pass
  # and the exec pass), which is exactly the injection shape hooks/session-register.sh:347 names.
  cat > "$d/torntests/no.bats" <<'TORN'
#!/usr/bin/env bats
printf 'not ok\nnot ok3 squashed\nnot okay then\nnot okcorpus: 3 suites\n' >&2
@test "fail" { false; }
TORN
  cp "$REPO/launchd/com.claude.team-orphan-reaper.plist" "$d/plists/good.plist" 2>/dev/null \
    || printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' > "$d/plists/good.plist"
  printf '<plist><dict><string>2>&1 raw ampersand</string></dict></plist>\n' > "$d/plists/bad.plist"

  # run the invariant with a stubbed check-set (NO eval — env-scoped overrides).
  # <pagedir> <log> <batsdir> <plistglob> [postland-verify-stub] [console-capture] [POSTLAND_VERIFY]
  # The last three are POSITIONAL rather than ambient on purpose: a `VAR=x run_inv …` prefix on a
  # *function* call persists in the caller afterwards (bash, non-POSIX), and wrapping each call in a
  # subshell to contain that is what makes shellcheck read every one of them as an SC2030/SC2031
  # lost-modification pair. Positionals have neither problem and state the fixture at the call site.
  # THE ADMISSION BOUND IS PINNED OFF FOR THE FIXTURES, AND THAT IS NOT A BYPASS. cc-bats DEFERS
  # (rc 75) when live bats roots >= CC_BATS_MAX_ROOTS *and* 1-min load/core >= CC_BATS_MAX_LOAD_PER_CORE,
  # and the runner correctly scores that deferral as a NON-VERDICT — which is exactly right at 04:00
  # and exactly wrong here. Every red-path assertion below asks "does a FAILING suite page?", so a
  # deferred fixture answers a different question and is scored as a FAIL: the detector is reported
  # broken because the box was busy. Measured 2026-08-24 on a freshly-rebooted box at load/core 1.92
  # against the 2.0 default — 60 passed / 7 failed, every failure on the red-bats and red-torn arms;
  # re-run at load 18.16 with both bounds raised, 67 passed / 0 failed, no other variable changed.
  # That flake is not cosmetic: 22-nightly-regression-activate.sh gates activation on this selftest,
  # so a busy box made the operator's activation refuse for a defect that did not exist.
  # These fixtures are hermetic one-test stubs — they are not the contention the bound exists to
  # shed — so the honest value here is "do not count me", NOT a relaxation of the real bound, which
  # every non-selftest caller still gets. Both terms are pinned because the refusal is a conjunction:
  # leaving either live would let the flake back in the moment the other one flipped.
  run_inv() {
    env CC_NIGHTLY_NOTIFY=/usr/bin/true CC_NIGHTLY_NEVERSTUCK=/usr/bin/true CC_NIGHTLY_ABSTAIN=/usr/bin/true \
        CC_BATS_MAX_ROOTS=999999 CC_BATS_MAX_LOAD_PER_CORE=999999 \
        CC_NIGHTLY_POSTLAND_DIR="$d/nopostland" \
        CC_NIGHTLY_POSTLAND_VERIFY="${5:-/usr/bin/true}" POSTLAND_VERIFY="${7:-on}" \
        CC_NIGHTLY_GATE_GLOB="$d/emptygl/*.sh" CC_NIGHTLY_LINT_GLOB="$d/emptygl/*.sh" \
        CC_NIGHTLY_PAGEDIR="$1" CC_NIGHTLY_LOG="$2" CC_NIGHTLY_BATS_DIR="$3" CC_NIGHTLY_PLIST_GLOB="$4" \
        "$SELF" >"${6:-/dev/null}" 2>&1
  }

  echo "nightly-regression --selftest:"

  # "COULD NOT TEST" IS NOT "TEST FAILED", AND THIS FILE OF ALL FILES MUST NOT CONFLATE THEM.
  # Every red-path arm below asks "does a deliberately-broken suite make the detector page?".
  # Answering that requires bats to actually RUN the broken fixture. When bats does not resolve,
  # :468 SKIPS the bats check entirely — correct behaviour there, a skip is not a RED — so the
  # fixture never runs, no page is written, and SEVEN assertions report the detector broken when
  # the truth is that nothing was ever exercised. Measured 2026-08-24: from a shell with neither
  # ~/.claude/bin nor /opt/homebrew/bin on PATH this printed `60 passed, 7 failed`, byte-identical
  # to the deferral signature and to a genuine red — and it refused an activation for a detector
  # that returned 67/0 five times out of five the moment bats was on PATH.
  #
  # So this abstains LOUDLY and non-zero rather than scoring the arms. Non-zero because the
  # caller is a gate (22-nightly-regression-activate.sh) that must not arm on an untested
  # detector; loud because a silent skip here is the same defect one level up. This is the same
  # grammar as the rc-75 DEFERRAL the runner already honours: nothing ran, so nothing is claimed.
  if ! command -v bats >/dev/null 2>&1; then
    echo "  ABSTAIN: \`bats\` does not resolve on PATH, so the red-path fixtures cannot run." >&2
    echo "           This is NOT a detector failure and must not be read as one — the arms were" >&2
    echo "           never exercised. Put bats on PATH (brew install bats-core, or use the" >&2
    echo "           plist's own PATH) and re-run." >&2
    echo "nightly-regression --selftest: ABSTAINED — bats unavailable, 0 assertions scored."
    return 2
  fi

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
  grep -qE '^not ok [0-9]+' "$d/pages/nightly-regression.page" && okp "red-bats: page quotes the FAILING detail, not just the name" || badp "red-bats: page carries no failing detail"
  rm -f "$d/pages/nightly-regression.page"

  # red path (bats) with a TORN stream: the detail must be the RESULT lines, never the splice.
  # The page is the only thing a human reads at 04:00 to decide what broke; filling its 15-line
  # budget with bytes that merely OPEN like a verdict spends the whole budget on noise, and — worse
  # — the `|| tail -15` fallback that exists for exactly this case never fires, because the loose
  # grep "succeeded". Same grammar as the two lanes above (scripts/ship-land.sh, scripts/deploy-live.sh).
  run_inv "$d/pages" "$d/redt.log" "$d/torntests" "$d/plists/good.plist"; local trc=$?
  [ "$trc" -ne 0 ] && okp "red-torn: nonzero exit" || badp "red-torn: exit 0 on a failing suite"
  grep -qE '^not ok [0-9]+' "$d/pages/nightly-regression.page" \
    && okp "red-torn: page still quotes the REAL result line" || badp "red-torn: page lost the real detail"
  grep -qE '^not (okay|okcorpus|ok3)' "$d/pages/nightly-regression.page" \
    && badp "red-torn: page quotes SPLICED bytes as though they were verdicts" \
    || okp "red-torn: page carries no spliced non-verdict lines"
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

  # S4-b: POSITION INDEPENDENCE. Every fixture above is 3-5 lines, so its match is always near EOF
  # and the old pipeline form passed all five while silently bare-running the one real script whose
  # arm sits early in a long file. A control that cannot fail the way production failed is not a
  # control — so this one puts the arm on line 3 and ~2000 lines BEHIND it, which is what makes the
  # producer still be writing when `grep -q` short-circuits.
  # shellcheck disable=SC2016  # the ${1:-} below is LITERAL fixture script text, never an expansion
  { printf '#!/bin/bash\ncase "${1:-}" in\n  --selftest) run ;;\nesac\n'
    i=0; while [ "$i" -lt 2000 ]; do printf 'filler_%d=1\n' "$i"; i=$((i+1)); done
  } > "$d/detect/early-arm-long.sh"
  supports_selftest "$d/detect/early-arm-long.sh" \
    && okp "S4-b: an EARLY arm in a long file is still detected (no SIGPIPE/pipefail inversion)" \
    || badp "S4-b: early arm in a long file read as unsupported — the gate would be BARE-RUN"

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
  # Assert the row RESOLVES TO A NUMBER, never to one specific number — a baseline is a ratchet that
  # tightens as gates reach their bars (premortem went 1 → 0 on 2026-07-30), and an assertion pinned to
  # today's value turns every legitimate tightening into a false failure. The property that matters is
  # that the row parses at all: a typo'd row silently exempts nothing.
  case "$(ngr_decl_lookup premortem-gate.sh NGR_BAR_BASELINE)" in
    ''|*[!0-9]*) badp "B: premortem-gate baseline missing or non-numeric" ;;
    *)           okp  "B: premortem-gate baseline resolves to a number" ;;
  esac

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

  # ── I: the headline check — a DECLARED INVARIANT is count-judged (2026-08-08) ───────────────────
  # never-stuck-gate is not chronic-by-design, so it emits no bar marker and the marker alone could
  # never reach the count branch for it. Its DECLARATION is the way in; these prove the way in works
  # and that widening the entry did not make every plain failure count-judged.
  printf 'never-stuck-gate: 20 met · 2 failed\n⇒ THE INVARIANT IS BROKEN — a session CAN currently go silently idle through the failing leg.\n' > "$d/cls/invariant.out"
  ngr_bar_marker "$d/cls/invariant.out" \
    && badp "I: never-stuck-gate output must NOT read as a readiness bar (it tolerates nothing)" \
    || okp  "I: never-stuck-gate emits no bar marker — the declaration is the only way in"
  [ "$(ngr_bar_failed "$d/cls/invariant.out")" = 2 ] \
    && okp "I: parses the invariant's failed-count (the 20·2 the page could not print)" \
    || badp "I: invariant failed-count parse wrong"
  # Pinned at 0, unlike its bar siblings above: a bar's baseline ratchets, an invariant's is 0 BY
  # DEFINITION, so "resolves to a number" would accept the one value that must never be written.
  case "$(ngr_decl_lookup never-stuck-gate.sh NGR_BAR_BASELINE)" in
    0) okp  "I: never-stuck-gate baseline is 0 — an invariant tolerates nothing" ;;
    *) badp "I: never-stuck-gate baseline missing or nonzero (a broken invariant would read as a bar)" ;;
  esac
  [ "$(ngr_bar_verdict 2 0)" = red-regressed ] \
    && okp "I: 2 failed against baseline 0 ⇒ RED naming the count (the 19·2 case)" \
    || badp "I: a broken invariant was absorbed"

  local decd; decd="$d/cls/dec"; mkdir -p "$decd"
  printf '#!/bin/bash\necho "never-stuck-gate: 20 met · 2 failed"\nexit 1\n' > "$decd/counting-gate.sh"
  chmod +x "$decd/counting-gate.sh"
  # The verdict line goes to a FILE, never `$(…)`: a command substitution is its own subshell, so
  # run_check_step4's REDS+=/BARS+= would land there and the count read back as 0 — an assertion
  # that can only ever see an empty array is a vacuous pass wearing a measurement's clothes.
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "declared-invariant" never-stuck-gate.sh "$decd/counting-gate.sh" >"$decd/v-dec.txt" 2>&1
    [ "${#REDS[@]}" -eq 1 ] && [ "${#BARS[@]}" -eq 0 ] \
      && grep -q '2 failed > baseline 0' "$decd/v-dec.txt" ) \
    && okp "I: a DECLARED check with no marker is count-judged — the page names 2 failed > baseline 0" \
    || badp "I: the declaration never reached the count branch — the slip stays unprintable"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "undeclared-plain" no-such-gate.sh "$decd/counting-gate.sh" >"$decd/v-und.txt" 2>&1
    [ "${#REDS[@]}" -eq 1 ] && grep -q '(exit 1)' "$decd/v-und.txt" ) \
    && okp "I: an UNDECLARED check with the same output is still a plain RED (the widening's control)" \
    || badp "I: the widening swallowed an undeclared plain failure"
  # Every I-assertion above calls run_check_step4 DIRECTLY, so all of them would still pass with the
  # live invariant wired back onto plain run_check — the assertion's span would not be its subject,
  # which is the exact defect this change exists to fix (the 2026-07-30 "rc 143 is a NON-VERDICT"
  # row proved that property for every check EXCEPT the headline one, for a whole release). So pin
  # the CALL SITE. $SELF is BASH_SOURCE-derived, so this reads the file actually running, never a
  # sibling checkout that CC_NIGHTLY_REPO happens to point at.
  # shellcheck disable=SC2016  # the single quotes are the point: `$NEVERSTUCK` is LITERAL TEXT being
  # matched inside this file, not a variable to expand. Expanding it would search for the resolved
  # path and the assertion would pass on any wiring at all.
  grep -qE '\[ -x "\$NEVERSTUCK" \][[:space:]]*&&[[:space:]]*run_check_step4 "never-stuck-gate\(live\)" never-stuck-gate\.sh' "$SELF" \
    && okp  "I: the live invariant is wired to the count-judging runner under its declared basename" \
    || badp "I: never-stuck-gate(live) is on plain run_check — its count and its NON-VERDICTs are dropped"

  # ── P: the post-land verifier's instrument is a SCHEDULED check, and cannot manufacture step 5 ──
  # Three properties, because the wiring can rot in three independent ways and only the first is
  # visible in a diff: it can vanish, it can lose its sandbox (and then MINT step 5's red on every
  # unadopted box), or it can be scored on a runner that throws away its NON-VERDICTs.
  local pvd; pvd="$d/pv"; mkdir -p "$pvd"
  # The stub reds on exactly the two things the call site must supply. `case $HOME` is the sandbox
  # predicate stated the way the defect states it — ensure_dirs writes under $HOME unless every knob
  # is moved — so an unsandboxed wiring fails HERE rather than in the live tree at 04:00.
  cat > "$pvd/pv-ok.sh" <<'PVOK'
#!/bin/bash
[ "${1:-}" = "--selftest" ] || { echo "the check did not pass --selftest"; exit 1; }
[ -n "${CC_POSTLAND_DIR:-}" ] || { echo "UNSANDBOXED: CC_POSTLAND_DIR unset"; exit 1; }
case "$CC_POSTLAND_DIR" in "$HOME"/*) echo "UNSANDBOXED: points into live state"; exit 1 ;; esac
mkdir -p "$CC_POSTLAND_DIR/stamps"      # what ensure_dirs does to whatever it is pointed at
echo "postland-verify selftest: 53 passed, 0 failed"
PVOK
  printf '#!/bin/bash\necho "postland-verify selftest: 52 passed, 1 failed"\nexit 1\n' > "$pvd/pv-red.sh"
  chmod +x "$pvd/pv-ok.sh" "$pvd/pv-red.sh"

  # The composed property, in ONE run: 3c executes green AND step 5 still abstains. Asserting them
  # together is the point — separately, a wiring that created $d/nopostland/stamps would still pass
  # the first and the manufactured RED would only appear on the SECOND night, which is precisely the
  # shape that makes this class of defect survive review.
  run_inv "$d/pages" "$d/pv-green.log" "$d/goodtests" "$d/plists/good.plist" \
          "$pvd/pv-ok.sh" "$d/pv-green.out"; local pvrc=$?
  [ "$pvrc" -eq 0 ] && okp "P: postland-verify --selftest runs and is scored (green night)" \
                    || badp "P: the postland-verify instrument check did not run green — see $d/pv-green.out"
  grep -q 'ok   postland-verify.sh --selftest' "$d/pv-green.out" \
    && okp "P: it is reported under its own name, not folded into another check" \
    || badp "P: no 'postland-verify.sh --selftest' row in the run — the check is not wired"
  grep -q 'ok   postland-inertness' "$d/pv-green.out" && [ ! -d "$d/nopostland/stamps" ] \
    && okp "P: step 5 still ABSTAINS — 3c did not mint the stamps dir it keys on" \
    || badp "P: 3c manufactured step 5's RED (stamps dir created under the live postland knob)"
  rm -f "$d/pages/nightly-regression.page"

  # ANTI-VACUITY. Everything above passes just as well against a check that is launched and then
  # ignored; only a stub that FAILS can prove its verdict reaches the night's.
  run_inv "$d/pages" "$d/pv-red.log" "$d/goodtests" "$d/plists/good.plist" \
          "$pvd/pv-red.sh" "$d/pv-red.out"; local pvrrc=$?
  [ "$pvrrc" -ne 0 ] && grep -q 'RED  postland-verify.sh --selftest' "$d/pv-red.out" \
    && okp "P: a FAILING instrument reds the night (the verdict is not decorative)" \
    || badp "P: a failing postland-verify --selftest did not red the night"
  grep -q '52 passed, 1 failed' "$d/pages/nightly-regression.page" \
    && okp "P: the page quotes WHICH assertions failed, not just the check name" \
    || badp "P: the page carries no detail from the failing instrument"
  rm -f "$d/pages/nightly-regression.page"

  # KILL SWITCH ≠ VERDICT. POSTLAND_VERIFY=off exits 0 above the dispatch, so a bare run would score
  # `ok` having proven nothing. It must SKIP — logged, never silent, and never counted as a pass.
  run_inv "$d/pages" "$d/pv-off.log" "$d/goodtests" "$d/plists/good.plist" \
          "$pvd/pv-red.sh" "$d/pv-off.out" off; local pvorc=$?
  [ "$pvorc" -eq 0 ] && grep -q 'skip postland-verify.sh --selftest' "$d/pv-off.out" \
    && ! grep -q 'ok   postland-verify.sh --selftest' "$d/pv-off.out" \
    && okp "P: POSTLAND_VERIFY=off SKIPS the check — a kill switch never reads as a green" \
    || badp "P: the kill switch produced a verdict (or reddened the night) instead of a logged skip"
  grep -q 'skipped:.*postland-verify.sh:kill-switched' "$d/pv-off.log" \
    && okp "P: the skip reaches regression.log with its reason" \
    || badp "P: the kill-switched skip is invisible in the log"
  rm -f "$d/pages/nightly-regression.page"

  # The CALL SITE, pinned the same way the invariant's is at "I:" above and for the same reason:
  # every assertion above would still pass with this check moved onto plain run_check, because none
  # of them is its subject. run_check_step4 under the declared basename is what buys it the rc
  # 124/137/143/75 NON-VERDICT arm and the 1800s bound — on run_check a cut night would be convicted
  # as a REGRESSION in the instrument, which is worse than not watching it at all.
  grep -qE 'run_check_step4 "postland-verify\.sh --selftest" postland-verify\.sh' "$SELF" \
    && okp  "P: wired to the count/NON-VERDICT runner under its declared basename" \
    || badp "P: postland-verify --selftest is not on run_check_step4 — its cuts would score as REDs"
  # shellcheck disable=SC2016  # `$RUNDIR` is LITERAL TEXT being matched inside this file, not an
  # expansion — expanding it would search for the resolved tmpdir and pass on any wiring at all.
  grep -qE 'CC_POSTLAND_DIR="\$RUNDIR/pv/state"' "$SELF" \
    && okp  "P: the sandbox is rooted in this run's capture dir (trap-cleaned), not in \$HOME" \
    || badp "P: the sandbox no longer points into RUNDIR — the check can touch live postland state"
  case "$(ngr_decl_lookup postland-verify.sh NGR_CHECK_TIMEOUT_DECL)" in
    ''|*[!0-9]*) badp "P: postland-verify.sh has no numeric per-check bound (424s measured > 300s default)" ;;
    *) [ "$(ngr_decl_lookup postland-verify.sh NGR_CHECK_TIMEOUT_DECL)" -gt "$NGR_CHECK_TIMEOUT" ] \
         && okp  "P: its declared bound exceeds the default it exists to correct" \
         || badp "P: the declared bound is at-or-under the default — a nightly rc-124 NON-VERDICT" ;;
  esac

  # ── T: the per-check bound must FIT ITS BAND, and must reach the runner ─────────────────────────
  case "$(ngr_decl_lookup never-stuck-gate.sh NGR_CHECK_TIMEOUT_DECL)" in
    ''|*[!0-9]*) badp "T: never-stuck-gate has no numeric per-check bound" ;;
    *) [ "$(ngr_decl_lookup never-stuck-gate.sh NGR_CHECK_TIMEOUT_DECL)" -gt "$NGR_CHECK_TIMEOUT" ] \
         && okp  "T: the declared bound exceeds the default it exists to correct (422s measured > 300s)" \
         || badp "T: the declared bound is at-or-under the default — the check would be cut nightly" ;;
  esac
  ngr_decl_lookup route-safety-gate.sh NGR_CHECK_TIMEOUT_DECL >/dev/null \
    && badp "T: an undeclared check picked up an override" \
    || okp  "T: an undeclared check keeps the global default"
  # Effect-read, not table-read: a row nothing consults is a decoration. Paired so neither can pass
  # vacuously — same stub, same tiny global bound, ONLY the declaration differs.
  if [ -n "$NGR_OSA_TB" ] && [ -x "$NGR_OSA_TB" ]; then
    printf '#!/bin/bash\nsleep 3\n' > "$decd/slow-gate.sh"; chmod +x "$decd/slow-gate.sh"
    ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0; NGR_CHECK_TIMEOUT=1
      run_check_step4 "declared-slow" never-stuck-gate.sh "$decd/slow-gate.sh" >/dev/null 2>&1
      [ "${#TIMEOUTS[@]}" -eq 0 ] && [ "${#REDS[@]}" -eq 0 ] ) \
      && okp "T: the declared 1800s bound OVERRIDES a 1s global — the check completes" \
      || badp "T: the per-check override never reached the runner"
    ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0; NGR_CHECK_TIMEOUT=1
      run_check_step4 "undeclared-slow" no-such-gate.sh "$decd/slow-gate.sh" >/dev/null 2>&1
      [ "${#TIMEOUTS[@]}" -eq 1 ] ) \
      && okp "T: the same stub UNDECLARED is cut at 1s (the override is doing the work)" \
      || badp "T: the global bound did not cut an undeclared check — the pair proves nothing"
  else
    badp "T: no timeout(1) resolved — the bound assertions would pass vacuously"
  fi

  # rc 75 (cc-bats DEFERRAL) — the fixture prints a bar's OWN wording AND a parsable count before
  # exiting 75, because that is the exact shape the defect produced: a gate that never ran a test
  # still emitting "N met · M failed" and "it is the bar". A fixture that exited 75 silently would
  # pass against the BROKEN code too (no marker ⇒ it lands in the plain-regression arm either way),
  # so it could not tell the two apart — this one can. Pre-fix, 75 fell past the NON-VERDICT case
  # into the bar branch and scored red-undeclared: REDS=1, TIMEOUTS=0. Asserting all three buckets
  # is what pins it; BARS=0 is the half that catches the worse failure, a deferral ABSORBED as a
  # met bar once a baseline row exists.
  printf '#!/bin/bash\necho "fake-gate: 1 met · 2 failed · 0 NOT BUILT"\necho "⇒ NOT READY. (Red here is not a bug — it is the bar.)"\nexit 75\n' \
    > "$nvd/deferred-gate.sh"; chmod +x "$nvd/deferred-gate.sh"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "deferred-gate.sh" deferred-gate.sh "$nvd/deferred-gate.sh" >/dev/null 2>&1
    [ "${#REDS[@]}" -eq 0 ] && [ "${#BARS[@]}" -eq 0 ] && [ "${#TIMEOUTS[@]}" -eq 1 ] ) \
    && okp "NV: rc 75 (cc-bats DEFERRAL) is a NON-VERDICT — never a bar, even when it prints one" \
    || badp "NV: a cc-bats deferral was scored as a bar or a RED"

  # rc 2 — MARKER-GATED, and the pair is the point. Unlike 124/137/143/75, rc 2 is reachable by a
  # merely BROKEN check (`bash` exits 2 on a syntax error), so the CUT must key on what the check
  # SAYS, not on its code. Two fixtures differing ONLY in that line: without the pair, widening the
  # arm to a bare `2)` would pass the first case and silence every syntax error in the fleet.
  printf '#!/bin/bash\necho "test-hermeticity-lint: ⛔ UNUSABLE — a predicate failed to run (see above); no verdict."\nexit 2\n' \
    > "$nvd/unusable-lint.sh"; chmod +x "$nvd/unusable-lint.sh"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "unusable-lint.sh" unusable-lint.sh "$nvd/unusable-lint.sh" >/dev/null 2>&1
    [ "${#REDS[@]}" -eq 0 ] && [ "${#BARS[@]}" -eq 0 ] && [ "${#TIMEOUTS[@]}" -eq 1 ] ) \
    && okp "NV: rc 2 WITH a non-verdict marker is a NON-VERDICT, not a regression" \
    || badp "NV: a lint that said it could not run was scored as a RED"
  printf '#!/bin/bash\necho "test-hermeticity-lint: ⛔ not a directory: /nope"\nexit 2\n' \
    > "$nvd/broken-lint.sh"; chmod +x "$nvd/broken-lint.sh"
  ( REDS=(); TIMEOUTS=(); BARS=(); NCHECK=0
    run_check_step4 "broken-lint.sh" broken-lint.sh "$nvd/broken-lint.sh" >/dev/null 2>&1
    [ "${#TIMEOUTS[@]}" -eq 0 ] && [ "${#REDS[@]}" -eq 1 ] ) \
    && okp "NV: rc 2 WITHOUT the marker stays RED (a syntax error is not an abstain)" \
    || badp "NV: rc 2 became a blanket CUT — every broken check is now silent"

  # The two rows measured 2026-08-08 must RESOLVE — same ratchet discipline as premortem above:
  # assert they parse to a number, never to one specific number, so tightening a bar stays legal.
  for _b in limit-reset-safety-gate.sh session-lifecycle-safety-gate.sh; do
    case "$(ngr_decl_lookup "$_b" NGR_BAR_BASELINE)" in
      ''|*[!0-9]*) badp "B: $_b baseline missing or non-numeric" ;;
      *)           okp  "B: $_b baseline resolves to a number" ;;
    esac
  done

  echo "nightly-regression --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "nightly-regression --selftest: GREEN — red-path pages (bats + plutil), green-path clears, page is epoch-headed."
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--run)   regress ;;
  *)          printf 'nightly-regression: unknown arg %s (use --run | --selftest)\n' "$1" >&2; exit 2 ;;
esac
