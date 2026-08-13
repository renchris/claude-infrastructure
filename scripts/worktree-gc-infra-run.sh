#!/usr/bin/env bash
# worktree-gc-infra-run.sh — the launchd wrapper that finally SCHEDULES the worktree janitor for
# claude-infrastructure.
#
# WHY THIS FILE EXISTS: `scripts/worktree-gc.sh` has been a complete, safe janitor for this repo
# since 2026-07-25, and nothing has ever run it on a cadence. The ONLY scheduled reaper on this box
# is `gl.reso.worktree-gc` → `~/.reso/worktree-gc-run.sh`, which hardcodes
# REPO=/Users/chrisren/Development/reso-management-app. So claude-infrastructure was never swept:
# measured 2026-08-01, 126 worktrees and 1,193 branches. The gap was never the janitor — it was the
# cron. This file is the cron, and NOTHING ELSE: every safety gate stays in worktree-gc.sh, which
# this wrapper only parameterises and never second-guesses.
#
# CRITICAL — PATH. lsof lives in /usr/sbin, NOT /usr/bin. reso's reaper shipped a PATH without
# /usr/sbin, so under launchd `lsof` was command-not-found, EVERY liveness gate returned empty, and
# it reaped a LIVE worktree (wt-cc-233227-53597, 2026-06-19). worktree-gc.sh inherits this PATH, so
# the omission would be silently re-inherited here. System dirs first so the entitled system tools
# win; homebrew kept for git and timeout(1).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
set -uo pipefail

# ── Seams. Defaults are production; the bats suite overrides all four to stay hermetic. ──────────
REPO="${CC_WTGC_INFRA_REPO:-/Users/chrisren/Development/claude-infrastructure}"
GC_SH="${CC_WTGC_INFRA_GC:-$REPO/scripts/worktree-gc.sh}"
GIT_BIN="${CC_WTGC_GIT:-git}"                       # same seam name worktree-gc.sh already uses
STATE="$HOME/.claude/autonomy"
LOG="${CC_WTGC_INFRA_LOG:-$HOME/.claude/logs/worktree-gc-infra.log}"
LAST="$STATE/worktree-gc-infra.last"
DISABLED="$STATE/worktree-gc-infra.disabled"
LOCK="$HOME/.claude/state/worktree-gc-infra.lock"
OBSERVE="${WTGC_OBSERVE:-0}"
FETCH_BOUND="${CC_WTGC_INFRA_FETCH_BOUND:-300}"

# ── EFFECT, NOT EXIT CODE (master 66ef300dd0b4 — fleet footprint) ────────────────────────────────
# This wrapper already refuses to call lock contention a success, which is the right instinct
# applied to the wrong quantity: `verdict=ok removed=65 kept=126` reports what the JANITOR SAID,
# and nothing anywhere reads what the janitor DID. Measured 2026-08-09, that gap ran for three
# days in a row and no rung of this file noticed:
#
#   2026-08-06 04:15  verdict=ok ... removed=65 kept=126        ← last completed sweep
#   2026-08-07 04:15  verdict=skipped reason=janitor-lock-held  ← surrendered for a FULL DAY
#   2026-08-08 04:15  (lock dir created, pid written, NO verdict line ever) ← died mid-sweep, silent
#   2026-08-09 04:15  (nothing at all — the box panicked in this very window)
#   2026-08-09 22:00  TRUE POPULATION 558 directories / 427 registered
#
# Every one of those is exit 0 or no row at all, so the fleet's only staleness sensor read HEALTHY
# while the population it exists to bound more than tripled. That population is not cosmetic: it
# is one end of the spawn/teardown invariant whose other end is a 224-agent fan-out, and the
# kernel watchdog panicked this box 4 times in 7 days.
#
# So four rungs are added here, all of them reading FACTS ABOUT THE WORLD rather than about this
# script's own return value, and all of them inside THIS ALREADY-SCHEDULED FILE — a new launchd
# job would be a C10 operator step, and this repo's pending-activation queue is where such things
# rot (the inertness generator). An edit rides the existing per-file symlink and goes live on the
# trunk fast-forward; an added file would not.
#
#   1. POPULATION, before and after, from the filesystem — `pop_before`/`pop_after`/`pop_delta`.
#   2. `verdict=over-ceiling` — the sweep RAN, exited 0, and the count is STILL over the ceiling.
#      Today that state is indistinguishable from a healthy `ok`; it is the one that was true.
#   3. PREVIOUS-RUN DEATH. The lock's dead-holder self-heal currently erases the evidence that a
#      run died mid-sweep. It now reports it (`prev=died-mid-sweep`) before clearing — which is
#      how the 2026-08-08 death becomes attributable instead of theoretical.
#   4. MISSED WINDOWS. A calendar job that never fired leaves no row by construction, so absence
#      has to be measured from the LAST row's age, not from a row's contents.
#
# The ceiling is a CEILING, not a target: worktree-gc.sh legitimately KEEPs live, dirty, unlanded
# and owned trees (108 of them at this measurement), so a number near that is normal and only a
# multiple of it is news. An alarm that fires every night carries exactly as many bits as one that
# cannot fire (memory: alarm-polarity-and-attention-budget).
#
# ⚠ THE CEILING BINDS `pop_owned`, NOT `pop` — AND THAT DISTINCTION WAS FOUND BY THE FIRST SWEEP,
# NOT BY DESIGN. The root ~/Development/.worktrees is SHARED: three repos keep worktrees in it and
# only this repo's are ours to reap. Measured right after the 2026-08-09 sweep took the population
# 558 → 246: claude-infrastructure 104, reso-management-app 69, doc_classifier 60. A ceiling on the
# TOTAL therefore reported BREACH on a box whose janitor had just done its job perfectly, for 142
# directories this job cannot touch — an alarm firing over something it cannot act on, which is the
# exact polarity defect the paragraph above warns about, committed one paragraph later.
#
# So both numbers are reported and only the actionable one is judged. `pop` stays on every row
# because the FOOTPRINT is the thing that panicked the box and it does not care which repo minted
# it; `pop_foreign` makes a total that grows without our doing greppable and attributable to the
# repo that owns it — reso runs its own reaper at 03:15 and its population is its own alarm's job.
CEILING="${CC_WTGC_INFRA_CEILING:-150}"
WT_ROOT="${CC_WTGC_INFRA_WT_ROOT:-$HOME/Development/.worktrees}"
STALE_H="${CC_WTGC_INFRA_STALE_HOURS:-48}"
LOCK_RETRIES="${CC_WTGC_INFRA_LOCK_RETRIES:-3}"
LOCK_BACKOFF="${CC_WTGC_INFRA_LOCK_BACKOFF:-120}"
case "$CEILING"      in ''|*[!0-9]*) CEILING=150 ;; esac
case "$STALE_H"      in ''|*[!0-9]*) STALE_H=48 ;; esac
case "$LOCK_RETRIES" in ''|*[!0-9]*) LOCK_RETRIES=3 ;; esac
case "$LOCK_BACKOFF" in ''|*[!0-9]*) LOCK_BACKOFF=120 ;; esac

# ── STRANDED VALUE — the balance the KEEP side has never been counted against (M4, 0328e7cc5742)
# The paragraph above says worktree-gc.sh "legitimately KEEPs live, dirty, UNLANDED and owned
# trees", and that is true and correct: gate 6 refuses to remove a worktree whose branch still
# holds unlanded commits, `bin/cc-reaper`'s work_landed() refuses on the same patch-id test, and
# `scripts/branch-reaper.sh` deletes only merged branches with `-d`. Nothing here weakens any of
# that — deleting finished work is the failure this repo already engineered out.
#
# But the invariant is ONE-SIDED, and that is what this rung adds. "Unlanded ⇒ KEEP" has no
# counter-pressure: a branch nobody lands is kept FOREVER, and `kept=126` reports it in the same
# integer as a worktree kept because a session is live inside it. So the safe direction is also
# an accumulator, and the balance is invisible by construction — the only reason anyone has ever
# known the number is that a human summed it by hand. Measured that way 2026-08-10: 95 unlanded
# patches across 31 registered worktree branches in this repo, the oldest 16 days old. None of it
# was ever at risk of deletion. All of it was at risk of never landing, which is the same loss
# arriving by a slower road — a worktree reaped after its branch is forgotten, or a machine that
# simply never runs the work.
#
# So the janitor now reports the value it is HOLDING, on every row, beside the footprint it
# already reports. A breach is not a reason to reap anything; it is a reason to LAND.
#
# ⚠ `git cherry` is the only correct instrument, and its two failure modes both bite here:
#   · `git rev-list --count <trunk>..<branch>` reads 455 for a branch holding 8 real patches —
#     it counts the TRUNK's own commits since the fork. Patch-id equivalence is the question.
#   · `git cherry` output of ZERO means LANDED, not "the command did nothing" — indistinguishable
#     from outside, so '+' rows are counted explicitly and a git failure yields n-a, never 0.
# Counted by UNIQUE sha across branches: three worktrees here held byte-identical commit sets
# (a re-created worktree keeps the old branch), so a per-branch sum reports 111 for 95 real
# patches and would breach a ceiling on arithmetic nobody did.
STRANDED_CEILING="${CC_WTGC_STRANDED_CEILING:-40}"
STRANDED_BOUND="${CC_WTGC_STRANDED_BOUND:-120}"
STRANDED_TRUNK="${CC_WTGC_STRANDED_TRUNK:-origin/main}"
case "$STRANDED_CEILING" in ''|*[!0-9]*) STRANDED_CEILING=40 ;; esac
case "$STRANDED_BOUND"   in ''|*[!0-9]*) STRANDED_BOUND=120 ;; esac

# The population is the DIRECTORY count, deliberately not `git worktree list`. A registration is
# the janitor's own bookkeeping; a directory is what occupies the disk, and the two disagree —
# measured the same day, 558 on disk against 427 registered in this repo. Counting registrations
# would let a whole unowned population stay invisible to its own alarm, which is the shape of
# defect this rung exists to end.
population() {
  # `find`, not `ls | wc -l`: SC2012, and the gate lints at info severity. -mindepth/-maxdepth 1
  # counts the root's own entries and nothing beneath them, which is what a worktree population is.
  local n; n="$(find "$WT_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')" || true
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# What THIS janitor governs: worktrees this repo has registered under the shared root. Counted
# from git rather than from the directory listing, because ownership is precisely what a listing
# cannot tell you — and ownership is what makes a breach actionable.
# EVERY reader here must return a NUMBER, never an empty string. Both of these feed `$(( ))`
# subtractions, and under `set -u` an empty operand is a hard syntax error that would take the
# whole run down — turning an unreadable git into a dead janitor rather than a reported unknown.
# `grep -c` prints 0 and exits 1 on no match (hence `|| true`), but a missing git binary or a cut
# pipeline yields nothing at all, and that is the case the normalisation covers.
population_owned() {
  local n
  n="$("$GIT_BIN" -C "$REPO" worktree list --porcelain 2>/dev/null \
        | sed -n 's#^worktree ##p' | grep -c "^$WT_ROOT/")" || true
  case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# stranded_scan → "<unique-patches> <branches>", or "n-a n-a" when it cannot be measured.
# Same contract as the readers above: a NUMBER or an explicit unknown, never an empty string
# (both feed a `[ ]` numeric test, and an unknown must never be mistaken for a healthy 0).
# The trunk ref must EXIST — an absent origin/main would make every branch read fully unlanded
# and manufacture a breach out of a missing fetch. Bounded by wall clock: the scan is one
# `git cherry` per registered branch (measured 6.7s over 117 branches, but it grows with the
# population it is watching), and a janitor that hangs is strictly worse than one reporting n-a.
stranded_scan() {
  local deadline shas n_br=0 b out
  "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "$STRANDED_TRUNK" >/dev/null 2>&1 \
    || { printf 'n-a n-a'; return 0; }
  deadline=$(( $(date +%s) + STRANDED_BOUND ))
  shas=""
  while read -r b; do
    [ -n "$b" ] || continue
    if [ "$(date +%s)" -ge "$deadline" ]; then printf 'n-a n-a'; return 0; fi
    out="$("$GIT_BIN" -C "$REPO" cherry "$STRANDED_TRUNK" "$b" 2>/dev/null | awk '/^\+ /{print $2}')" || true
    [ -n "$out" ] || continue
    n_br=$(( n_br + 1 ))
    shas="$shas$out
"
  done <<EOF
$("$GIT_BIN" -C "$REPO" worktree list --porcelain 2>/dev/null | awk '/^branch /{print substr($0,19)}' | sort -u)
EOF
  # UNIQUE shas: duplicate branches hold byte-identical commits (see the header note).
  # `grep -c .` prints 0 and exits 1 on empty input, hence the `|| true` + normalisation.
  local n_pt
  n_pt="$(printf '%s' "$shas" | sort -u | grep -c .)" || true
  case "${n_pt:-}" in ''|*[!0-9]*) n_pt=0 ;; esac
  printf '%s %s' "$n_pt" "$n_br"
}

# Hours since the last verdict of ANY kind. `date -r` is BSD; GNU needs -c. Unknown ⇒ empty, and
# every consumer below treats empty as "do not claim", never as "fine".
last_row_age_h() {
  [ -f "$LAST" ] || return 0
  local m now
  m="$(date -r "$LAST" +%s 2>/dev/null || stat -c %Y "$LAST" 2>/dev/null)" || return 0
  case "$m" in ''|*[!0-9]*) return 0 ;; esac
  now="$(date +%s)"
  echo $(( (now - m) / 3600 ))
}

mkdir -p "$STATE" "$(dirname "$LOG")" "$(dirname "$LOCK")" 2>/dev/null
ts="$(date '+%Y-%m-%d %H:%M:%S')"

# ── The verdict token. ───────────────────────────────────────────────────────────────────────────
# One structured, parseable line per run — `verdict=<v>` plus k=v fields — written to $LAST and
# echoed into $LOG. NEVER `|| true` a failure into a fake success: a claimed outcome that no reader
# can distinguish from a checked one deletes the signal entirely (claimed-outcome-vs-checked-outcome).
# Every field is ASCII, unquoted, whitespace-free, so `grep -o 'verdict=[a-z-]*'` and a plain
# `awk -F= ` both work.
#
#   verdict=ok        the sweep RAN and worktree-gc.sh printed its summary. removed/disposed/
#                     branches/refusals carry that summary's numbers verbatim.        exit 0
#   verdict=disabled  a kill switch is present; nothing was swept. TWO switches can produce this
#                     row and the field says which: `switch=$DISABLED` is THIS wrapper's file flag
#                     (checked in preflight — nothing is attempted at all, not even a fetch), while
#                     `switch=janitor env=…|file=…` is worktree-gc.sh's own CC_WTGC_DISABLE, read
#                     back off its output after this run has already fetched.        exit 0
#   verdict=skipped   the sweep did NOT run, by design and harmlessly — another pass holds the
#                     janitor's own lock (worktree-gc.sh:324 exits 0 with no summary). Deliberately
#                     NOT `ok`: `ok removed=0` would be indistinguishable from a clean sweep that
#                     found nothing, which is exactly the fake success this token exists to prevent.
#                                                                                     exit 0
#   verdict=blind     worktree-gc.sh REFUSED to act (rc 3) — no liveness oracle, so it cannot prove
#                     a worktree is idle. A safe refusal, but a broken sensor: under this PATH lsof
#                     always resolves, so rc 3 here means something is genuinely wrong.  exit 3
#   verdict=nofetch   `git fetch` failed or timed out, so origin/main is stale. Landedness is
#                     measured against origin/main; a stale ref makes landed branches look unlanded
#                     (fails SAFE — a KEEP — but makes the whole sweep useless). Nothing swept.
#                                                                                     exit 3
#   verdict=error     anything else, INCLUDING an unrecognised rc. rc is carried verbatim.
#                     A new worktree-gc.sh exit code lands here rather than in a success arm
#                     (new-enum-member-falls-into-fail-closed-default).                exit = rc
#   verdict=over-ceiling  the sweep RAN and exited 0, and the population is STILL over
#                     CC_WTGC_INFRA_CEILING. The janitor is working as designed and is being
#                     OUT-PRODUCED — every KEEP is legitimate, so this is never fixed by making
#                     the janitor more aggressive; it is fixed upstream, where the worktrees are
#                     minted. Distinct from `ok` precisely because `ok` is what it read while the
#                     count tripled.                                                    exit 3
PREV_NOTE=""      # carried into whatever verdict fires, so a prior death is never lost
# THE KILL SWITCH MEANS DO NOTHING, AND `pop_owned` COSTS A GIT CALL. The ownership count needs
# `git worktree list`, and tests/worktree-gc-infra.bats:79 pins the contract that a disabled or
# preflight-failed run touches git ZERO times. That test caught this as a real regression: a
# switch whose whole promise is inertness must not start shelling out because a new field wanted
# a number. So the git-derived half is OFF until the run has actually committed to sweeping, and
# the rows that fire before then carry `pop_owned=n-a` — an honest "not measured", never a 0 that
# would read as "we own none of them".
OWNED_MODE="skip"
verdict() { # <verdict> <exit-code> [k=v ...]
  local v="$1" rc="$2"; shift 2
  local line="$ts  verdict=$v observe=$OBSERVE"
  [ "$#" -gt 0 ] && line="$line $*"
  # POPULATION ON EVERY ROW, including the failure rows. A `skipped` or `error` row that does not
  # carry the count is exactly the row that read healthy for three days.
  # STRANDED rides the SAME OWNED_MODE gate as pop_owned, and that is not tidiness — the kill
  # switch's whole promise is inertness, and tests/worktree-gc-infra.bats pins `[ ! -f GITARGV ]`
  # on the disabled path. `stranded_scan` is a per-branch `git cherry` loop, so putting it on an
  # ungated row would make a DISABLED janitor the single most git-expensive path in the file —
  # the exact regression the pop_owned n-a arm was written to prevent, committed one field later.
  # Pre-sweep rows therefore say n-a: an honest "not measured", never a 0 that reads as "none".
  _vp="$(population)"
  if [ "$OWNED_MODE" = "read" ]; then
    _vo="$(population_owned)"
    _vs="$(stranded_scan)"
    line="$line pop=$_vp pop_owned=$_vo pop_foreign=$(( _vp - _vo )) ceiling=$CEILING"
    line="$line stranded_patches=${_vs%% *} stranded_branches=${_vs##* } stranded_ceiling=$STRANDED_CEILING"
  else
    line="$line pop=$_vp pop_owned=n-a pop_foreign=n-a ceiling=$CEILING"
    line="$line stranded_patches=n-a stranded_branches=n-a stranded_ceiling=$STRANDED_CEILING"
  fi
  [ -n "$PREV_NOTE" ] && line="$line $PREV_NOTE"
  line="$line rc=$rc"
  printf '%s\n' "$line" > "$LAST" 2>/dev/null
  printf '%s\n' "$line" >> "$LOG" 2>/dev/null
  # Keep the log bounded in place — it is the fleet's staleness sensor, so it must stay one file.
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -n 1000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
  exit "$rc"
}

# ── `--assert`: READ THE EFFECT, ON DEMAND, WITHOUT SWEEPING. ────────────────────────────────────
# The DoD this rung answers to is "verify by effect (count before/after), NEVER by the reaper's own
# exit code", and a nightly row satisfies that only for whoever reads the log at 04:15. This is the
# same three facts any time anyone asks: the true population, the age of the last verdict, and what
# that last verdict actually was. It sweeps nothing, takes no lock and writes no row, so it is safe
# to call from a close, a hook, or a human's terminal.
#
# Exit codes are the verdict: 0 = bounded and fresh · 3 = breached (over ceiling, or the sensor
# itself is stale/absent, which is NOT the same as healthy and must never read as 0).
if [ "${1:-}" = "--assert" ]; then
  _p="$(population)"; _o="$(population_owned)"; _a="$(last_row_age_h)"; _l="$(cat "$LAST" 2>/dev/null)"
  _s="$(stranded_scan)"; _sp="${_s%% *}"; _sb="${_s##* }"
  printf 'population=%s (ours=%s foreign=%s) ceiling=%s last_verdict_age_h=%s\n' \
    "$_p" "$_o" "$(( _p - _o ))" "$CEILING" "${_a:-unknown}"
  printf 'stranded=%s unlanded patch(es) across %s branch(es) ceiling=%s\n' "$_sp" "$_sb" "$STRANDED_CEILING"
  printf 'last_row=%s\n' "${_l:-<none — the janitor has never recorded a verdict>}"
  _bad=0
  # The shared root holds other repos' worktrees; only ours are reapable here, so only ours are
  # judged. A foreign total that grows is reported, never alarmed on — reso owns its own reaper.
  [ "$_o" -gt "$CEILING" ] && { printf 'BREACH our worktrees %s > ceiling %s\n' "$_o" "$CEILING"; _bad=1; }
  # A stranded breach is a LANDING backlog, not a reaping one — different verb, same exit code, so
  # a caller that only reads rc still learns "something needs doing". n-a is unknown ⇒ never a breach.
  case "$_sp" in
    ''|*[!0-9]*) printf 'stranded balance UNMEASURABLE (no %s, or the scan exceeded %ss)\n' \
                   "$STRANDED_TRUNK" "$STRANDED_BOUND" ;;
    *) [ "$_sp" -gt "$STRANDED_CEILING" ] && {
         printf 'BREACH %s unlanded patch(es) held across %s branch(es) > ceiling %s — LAND them (/ship per branch); reaping will not clear this\n' \
           "$_sp" "$_sb" "$STRANDED_CEILING"; _bad=1; } ;;
  esac
  if [ -z "$_a" ]; then
    printf 'BREACH the janitor has no verdict row at all — it has never demonstrably run\n'; _bad=1
  elif [ "$_a" -gt "$STALE_H" ]; then
    printf 'BREACH last verdict is %sh old (stale > %sh) — the janitor is not running\n' "$_a" "$STALE_H"; _bad=1
  fi
  [ "$_bad" = 0 ] && printf 'OK bounded and fresh\n'
  exit $(( _bad * 3 ))
fi

# ── Kill switch. Observe mode is read-only, so it is not gated by the switch: the switch stops the
#    janitor from REMOVING things, and observe removes nothing by construction. ───────────────────
if [ "$OBSERVE" = "0" ] && [ -f "$DISABLED" ]; then
  verdict disabled 0 "switch=$DISABLED"
fi

[ -f "$GC_SH" ] || verdict error 1 "stage=preflight reason=gc-script-missing"
[ -d "$REPO" ]  || verdict error 1 "stage=preflight reason=repo-missing"

OWNED_MODE="read"   # past the kill switch and preflight: this run is going to sweep, git is fair game

# ── MISSED WINDOWS. A StartCalendarInterval job that never fires writes nothing, so its absence
#    is unobservable from the log's CONTENTS and can only be measured from the last row's AGE.
#    2026-08-09's 04:15 window is the live case: the box was panicking in it, so there is no row
#    to find. Recorded, never acted on — a missed window self-heals at the next fire, and the
#    reason it matters is that it explains a population, not that it needs a remedy tonight.
_age_h="$(last_row_age_h)"
if [ -n "$_age_h" ] && [ "$_age_h" -gt "$STALE_H" ]; then
  PREV_NOTE="missed_windows_h=$_age_h"
fi

# ── PREVIOUS-RUN DEATH. A run killed mid-sweep (SIGKILL, a panic, a reboot) never reaches its
#    trap, so it leaves the lock dir behind holding a pid that is now dead. The self-heal below
#    correctly clears it — and in doing so DESTROYS the only evidence that a run died, which is
#    why 2026-08-08's death was invisible. Read it before clearing.
if [ -d "$LOCK" ]; then
  _lp="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$_lp" ] && ! kill -0 "$_lp" 2>/dev/null; then
    _lstarted="$(cat "$LOCK/started" 2>/dev/null)"
    PREV_NOTE="${PREV_NOTE:+$PREV_NOTE }prev=died-mid-sweep prev_pid=$_lp${_lstarted:+ prev_started=$_lstarted}"
  fi
fi

# ── Wrapper-level singleton (atomic mkdir, dead-holder self-heal). Distinct from worktree-gc.sh's
#    own CC_WTGC_LOCK, which is deliberately left at its default so this sweep and reso's 03:15 one
#    can never mutate worktrees concurrently. Observe mode is read-only ⇒ no lock. ────────────────
LOCK_HELD=0
if [ "$OBSERVE" = "0" ]; then
  if mkdir "$LOCK" 2>/dev/null; then
    LOCK_HELD=1
  else
    lpid="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
      verdict skipped 0 "reason=wrapper-lock-held holder=$lpid"
    fi
    rm -rf "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null && LOCK_HELD=1
  fi
  [ "$LOCK_HELD" = "1" ] || verdict skipped 0 "reason=wrapper-lock-unobtainable"
  echo "$$" > "$LOCK/pid" 2>/dev/null
  # The breadcrumb the next run reads to attribute a mid-sweep death (see PREVIOUS-RUN DEATH
  # above). Written INSIDE the lock so it is removed with it on a clean exit — its presence beside
  # a dead pid is therefore proof of an unclean one, never of an ordinary finish.
  printf '%s\n' "$ts" > "$LOCK/started" 2>/dev/null
  trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM
fi

POP_BEFORE="$(population)"

# ── FETCH FIRST. Landedness is `git cherry origin/main <branch>`; a stale remote-tracking ref makes
#    landed branches read as unlanded. That direction fails SAFE (a KEEP, never a wrongful delete)
#    but it also makes the sweep do nothing, which is the outcome this file exists to end.
#    Bounded so a hung fetch cannot hold the wrapper lock forever. The bound is ~100x a measured
#    fetch of this repo, sized for the launchd Background band's 4-84x tax, not for a foreground
#    run (bound-must-fit-the-band-not-the-bench). rc 124 is timeout(1)'s own code and is handled
#    as its OWN state, never folded into a generic failure.
fetch_rc=0
if command -v timeout >/dev/null 2>&1; then
  timeout "$FETCH_BOUND" "$GIT_BIN" -C "$REPO" fetch --quiet origin main >/dev/null 2>&1
  fetch_rc=$?
else
  "$GIT_BIN" -C "$REPO" fetch --quiet origin main >/dev/null 2>&1
  fetch_rc=$?
fi
if [ "$fetch_rc" -eq 124 ]; then
  verdict nofetch 3 "stage=fetch reason=timeout bound=${FETCH_BOUND}s"
elif [ "$fetch_rc" -ne 0 ]; then
  verdict nofetch 3 "stage=fetch reason=git-failed git_rc=$fetch_rc"
fi

# ── The sweep. Every gate lives in worktree-gc.sh; this only chooses the flags. ───────────────────
# --prune-branches is the whole point of scheduling this: 1,193 branches, and the janitor deletes
# ONLY landed, worktree-less, unprotected ones with `git branch -d` — never -D, so git's own
# merge check is a second gate on our evidence and a refusal is a KEEP.
# --dispose-abandoned is deliberately NOT passed: the DISPOSE class needs an operator-recorded
# ownership decision, and a nightly cron is exactly the wrong place to infer one. The class is
# still CLASSIFIED and printed by the janitor, so it stays visible in this log.
#
# --dispose-landed-dirt is a DIFFERENT class and its withholding has a different reason, so it gets
# its own switch rather than riding on the one above. That rationale — "needs an operator-recorded
# OWNERSHIP decision" — does not apply here: this class infers no ownership at all, it proves that
# every dirty path is byte-identical to the trunk, and a worktree whose dirt is redundant is the
# same object as the clean+idle+landed ones this cron ALREADY removes nightly.
#
# It still ships OFF, for one reason that is about timing rather than safety: 32 candidates exist
# right now, the janitor has never once printed this class, and the first run after the switch flips
# would remove all of them in the same night — before anyone has read a single line of evidence
# about it. Every one of those directories also carries gitignored content (node_modules/,
# .claude-tasks/, .ruff_cache/ — regenerable, but destroyed all the same), which the janitor now
# reports per candidate. So the nightly log accrues the evidence first and the switch is flipped
# against it, deliberately. Flip with WTGC_DISPOSE_LANDED_DIRT=1 (or in the plist); the class is
# CLASSIFIED, counted and blast-radius-reported every night regardless, so this cannot go inert.
DISPOSE_LANDED_DIRT="${WTGC_DISPOSE_LANDED_DIRT:-0}"
case "$DISPOSE_LANDED_DIRT" in 1) GC_DIRT_FLAG="--dispose-landed-dirt" ;; *) GC_DIRT_FLAG="" ;; esac
export CC_WTGC_REPO="$REPO"
export CC_WTGC_TRUNK="origin/main"
# EXCLUDE — colon-separated, also covering nested worktrees.
#   · the repo ROOT: the main checkout is not a linked worktree so the janitor already skips it,
#     but ~/.claude is a symlink INTO this checkout, so a wrongful removal here would take the live
#     harness layer with it. Belt and braces on the one path whose loss is unrecoverable.
#   · ~/.claude/autonomy/postland: the post-land verifier's OWN worktrees. They are created and
#     destroyed by com.claude.postland-verify on its own cadence; reaping one mid-cycle breaks the
#     verifier that gates every deploy — and it is the one consumer whose worktrees are legitimately
#     idle-looking while genuinely in use.
export CC_WTGC_EXCLUDE="$REPO:$HOME/.claude/autonomy/postland"

# RETRY THE JANITOR LOCK RATHER THAN SURRENDERING FOR A DAY. reso's sweep owns 03:15 and this one
# owns 04:15; they share worktree-gc.sh's own CC_WTGC_LOCK by design, so an hour of separation is
# the entire margin. When reso's sweep runs long, this one exits `skipped` and the NEXT chance is
# 24 hours away — which is what 2026-08-07 was, and a whole day of accrual is a high price for a
# few minutes of overlap. A bounded backoff costs nothing when the lock is free (the first attempt
# wins) and recovers the night when it is not. It is bounded, so it can never become a spin.
_attempt=0
while : ; do
  # ${GC_DIRT_FLAG:+...} — an EMPTY switch must expand to NO argument at all, never to an empty
  # string, which worktree-gc.sh's own flag loop would reject as `unknown flag ''` and turn the
  # whole nightly sweep into an exit-2 no-op.
  if [ "$OBSERVE" = "1" ]; then
    out="$(bash "$GC_SH" --dry-run --prune-branches ${GC_DIRT_FLAG:+"$GC_DIRT_FLAG"} 2>&1)"; rc=$?
  else
    out="$(bash "$GC_SH" --prune-branches ${GC_DIRT_FLAG:+"$GC_DIRT_FLAG"} 2>&1)"; rc=$?
  fi
  # Only the contention case is retryable. Every other rc is a real verdict and falls straight
  # through — a retry loop over a genuine error is how a bounded gate becomes a storm.
  printf '%s\n' "$out" | grep -q 'another pass holds' || break
  _attempt=$((_attempt + 1))
  [ "$_attempt" -ge "$LOCK_RETRIES" ] && break
  sleep "$LOCK_BACKOFF"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
done
[ "$_attempt" -gt 0 ] && PREV_NOTE="${PREV_NOTE:+$PREV_NOTE }lock_attempts=$_attempt"

{
  echo "===== $ts  worktree-gc-infra (observe=$OBSERVE repo=$REPO) ====="
  printf '%s\n' "$out"
} >> "$LOG" 2>/dev/null

# ── Reduce the janitor's output to the verdict. The SUMMARY LINE is the evidence that a sweep
#    actually happened; rc 0 alone is not (lock contention also exits 0, printing no summary).
summary="$(printf '%s\n' "$out" | grep -m1 '^worktree-gc: removed ')"

case "$rc" in
  0)
    if [ -z "$summary" ]; then
      # THE JANITOR'S OWN KILL SWITCH, read from the janitor rather than re-tested here. It has one
      # too now (worktree-gc.sh CC_WTGC_DISABLE / CC_WTGC_DISABLE_FILE), and a disabled janitor
      # exits 0 printing no summary — which lands in the arm two lines down as `error
      # stage=parse`, i.e. an operator who used the switch would be paged by this file every
      # night for using it (new-nonverdict-state-strands-its-consumers). The predicate is NOT
      # duplicated up in preflight beside $DISABLED: the janitor is the arbiter of its own switch,
      # and a copy of its rule here would be a second oracle to keep in sync
      # (make-the-actuator-the-arbiter). Cost of parsing instead: this run has already fetched.
      if printf '%s\n' "$out" | grep -q '^worktree-gc: verdict=disabled'; then
        _jsw="$(printf '%s\n' "$out" \
          | sed -n 's/^worktree-gc: verdict=disabled[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
        verdict disabled 0 "switch=janitor ${_jsw:-unknown}"
      fi
      if printf '%s\n' "$out" | grep -q 'another pass holds'; then
        verdict skipped 0 "reason=janitor-lock-held"
      fi
      verdict error 1 "stage=parse reason=no-summary-line"
    fi
    # ── READ THE MACHINE LINE BY NAME. Never the human summary, and never by position. ───────────
    # This used to be `set -- $(printf '%s\n' "$summary" | tr -cd '0-9 \n')` — five fields taken
    # POSITIONALLY out of a human sentence. It was correct when written and became wrong the day
    # `$N_DIRT_REMOVED landed-dirt` was inserted as the THIRD number (§9, --dispose-landed-dirt):
    # the line then carried SIX numbers, so kept/branches/refusals each shifted one place left and
    # the real refusal count fell off the end. Reproduced on the exact format:
    #   removed=7 disposed=3 dirt=5 kept=11 branches=2 refusals=9   (truth)
    #   removed=7 disposed=3 kept=5 branches=11 refusals=2          (what this logged)
    # Three mislabelled numbers per nightly row, exit 0, for as long as the field has existed —
    # and no test could see it, because the wrapper's suite fixtures the janitor's output.
    # Named fields make adding a field a NON-event; that is the whole point of the counts line.
    _counts="$(printf '%s\n' "$out" | grep -m1 '^worktree-gc: counts ')"
    if [ -z "$_counts" ]; then
      # Fail CLOSED. The old positional path is NOT kept as a fallback: it is known-wrong, and a
      # silent wrong number is worse than a loud absent one (the whole reason this block changed).
      verdict error 1 "stage=parse reason=no-counts-line"
    fi
    _f() { printf '%s\n' "$_counts" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p" | head -1; }
    set -- "$(_f removed)" "$(_f disposed)" "$(_f kept)" "$(_f branches_deleted)" "$(_f refusals)"
    # THE EFFECT ASSERTION. Everything above this line is the janitor's own account of itself;
    # this is the only rung that reads the world. `removed=65 kept=126` was a true sentence on
    # 2026-08-06 and the population was 558 three days later, so the summary's numbers cannot
    # stand in for the count — they describe one sweep, and the count is a running balance.
    _pop_after="$(population)"
    _delta=$(( POP_BEFORE - _pop_after ))
    # §6 R-b: carry the janitor's own wall-clock into the log row, so the question "does a sweep
    # outrun the mutex's 3,600 s staleness window?" is answered every night from the REAL
    # population instead of from a synthetic repo. Read from its own line, never from the summary
    # line above — that one is parsed positionally and must keep exactly five numbers.
    # `n-a` (not 0) when the line is absent: an unmeasured duration is unknown, and unknown must
    # not read as "instantaneous" to whoever later thresholds this field.
    _el="$(_f elapsed)"
    _eff="pop_before=$POP_BEFORE pop_after=$_pop_after pop_delta=$_delta elapsed=${_el:-n-a} dirt=$(_f landed_dirt)"
    _owned_after="$(population_owned)"
    if [ "$OBSERVE" = "0" ] && [ "$_owned_after" -gt "$CEILING" ]; then
      verdict over-ceiling 3 "removed=${1:-0} disposed=${2:-0} kept=${3:-0} branches=${4:-0} refusals=${5:-0} $_eff"
    fi
    # STRANDED BREACH — ranked BELOW the footprint breach deliberately. pop_owned is what panicked
    # this box; stranded value costs nothing at runtime and is a backlog problem, not a machine one.
    # It is its own verdict rather than a note because the remedy has a different actor and a
    # different verb: over-ceiling means REAP, stranded-over-ceiling means LAND. n-a never breaches
    # (an unmeasurable balance is unknown, and unknown must not fire an alarm nobody can action).
    _vsw="$(stranded_scan)"; _vsw_p="${_vsw%% *}"
    case "$_vsw_p" in
      ''|*[!0-9]*) : ;;
      *) if [ "$OBSERVE" = "0" ] && [ "$_vsw_p" -gt "$STRANDED_CEILING" ]; then
           verdict stranded-over-ceiling 3 \
             "removed=${1:-0} disposed=${2:-0} kept=${3:-0} branches=${4:-0} refusals=${5:-0} $_eff"
         fi ;;
    esac
    verdict ok 0 "removed=${1:-0} disposed=${2:-0} kept=${3:-0} branches=${4:-0} refusals=${5:-0} $_eff"
    ;;
  3) verdict blind 3 "reason=no-liveness-oracle" ;;
  4) verdict error 4 "reason=disposal-preservation-unverified" ;;
  *) verdict error "$rc" "reason=unexpected-janitor-rc" ;;
esac
