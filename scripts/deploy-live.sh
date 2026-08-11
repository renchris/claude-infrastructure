#!/bin/bash
# deploy-live.sh — the OPERATOR's one safe command for advancing the LIVE layer.
#
# Why: the live checkout (~/Development/claude-infrastructure) is what every session actually
# runs — hooks, scripts, launchd jobs. The old nag emitted a raw `git pull --ff-only`, which
# deploys whatever happens to be on origin/main, VERIFIED OR NOT. Agents are classifier-blocked
# from deploying, so the operator is the only one who can pull the trigger — this script makes
# that trigger fail-closed: it advances ONLY to a commit whose tree carries a GREEN post-land
# verification stamp, and refuses (loudly, with a page) when none exists.
#
# Stamp contract: <stamps>/<tree-sha>.json containing "verdict":"green" (tree-keyed, so a
# rebase/cherry-pick that preserves the tree keeps its verdict). Written by postland-verify.sh.
#
# Behavior: UNCONDITIONAL link refresh (see link_refresh — monotone, so it is never nested in the
# advance) → fetch origin/main → TARGET SELECTION (three tiers, below) →
# `merge --ff-only TARGET` (never origin/main) → run install.sh (idempotent) → POST-DEPLOY HOST
# CHECKS (§4.3) → report the un-stamped commits still queued above the deployed tip.
#
# TARGET SELECTION IS THREE-TIER WITH A BLOCKED FLOOR (DEPLOY_LANE_GROUND_UP §2.2, + T1H from
# backlog b4f93c9fa73c). A single
# green-only tier deadlocks BY CONSTRUCTION: the verifier emits 0.17 greens/day while trunk moves
# ~63 commits/day, so the green pointer permanently LAGS, and the moment any other writer advances
# live HEAD past it (~/.claude is per-file symlinks, so every land does) the target is history and
# this script refuses forever. Measured 2026-08-07: 534 identical refusals, launchd runs=276 every
# one exit 1, live layer 91 commits stale, ZERO pages. The green gate is NOT deleted — it answers a
# named incident (the raw `git pull --ff-only` above) — it is given a DEGRADATION PATH:
#   T1  VERIFIED  newest GREEN tree that is a DESCENDANT of live HEAD → advance, silent (unchanged)
#   T1H HERMETIC  T1 empty → newest commit above live HEAD whose tree carries an OFF-BOX green over
#                 the hermetic subset AND no on-box RED → advance under a banner NAMING the reduced
#                 scope. No lag budget: T1H advances on a POSITIVE result, so making it wait on a
#                 clock the way T2 must would hold a proven tree hostage. The `no on-box RED`
#                 conjunct is load-bearing — the machine-coupled suites are exactly this producer's
#                 blind spot, so an on-box red saw something it structurally cannot.
#   T2  DEGRADED  T1 and T1H empty AND lag past budget → newest commit above live HEAD carrying no
#                 RED stamp → advance under a LOUD banner + a page recording the unverified advance
#   T3  BLOCKED   every commit above live HEAD is RED → refuse + page ("trunk is red all the way
#                 down" is real information; the old single tier could not tell it from "no stamps")
# Stamp semantics under T1H and T2, applying R6 where the land path already honors it: absent ⇒
# eligible · cut/hung ⇒ eligible (a NON-VERDICT is not a red) · red ⇒ ineligible, walk back one.
# WHY T1H EXISTS AT ALL: T1's producer emits 0.17 greens/day, so the healthy silent path is
# unreachable in practice and every advance has to come through T2's absence-of-evidence door. T1H
# is a SECOND producer for the same ladder — same fail-closed shape, positive evidence, narrower
# claim, and it says so out loud on every advance rather than passing itself off as T1.
#
# --auto (LAND_PIPELINE_V2 §4.3) makes the same fail-closed decision AUTONOMOUSLY, on a launchd
# tick every 600s. Three deltas, all of them consequences of running 144×/day unattended:
#   (a) nothing new stamped green (TARGET == live HEAD) ⇒ SILENT exit 0. The steady state must
#       not narrate; a log line per tick is 144/day of "already deployed".
#   (b) a REFUSAL pages at most once per damp window (CC_DEPLOY_DAMP_S, default 24h), keyed on
#       the refusal REASON — subject+state damping, so any change of reason re-pages immediately
#       and a recovery (advance / already-at-target) CLEARS the marker so the next failure is
#       loud again. Undamped, the "no stamps dir" refusal alone is 144 identical pages/day, which
#       is how an operator learns to ignore the channel.
#   (c) --auto is non-interactive BY CONSTRUCTION: it can never be combined with --bootstrap or
#       --force. Those two are the operator's documented escape hatches from the green gate;
#       an unattended job that could take them would silently deploy unverified trees forever.
#
# POST-DEPLOY HOST CHECKS: the suites listed in scripts/host-suites.manifest are the ones whose
# real subject is the LIVE layer (deploy-parity & friends). Running them PRE-deploy is the
# bootstrap circle — they assert a tree that is not deployed yet, so they can never pass, which
# is why 0 green stamps have ever existed. Post-advance they run against their actual subject,
# `nice -n 19` and bounded, from $DEPLOY_REPO. A host RED is a LIVE-LAYER finding: it pages and
# files a backlog packet, and does NOT roll back (this script never rolls back — rolling the live
# layer back is an operator decision) and does NOT change the exit code.
#
# Flags: --dry-run (decide + print, mutate nothing) · --offline (decide against the ALREADY-FETCHED
# origin/main, never the network — composes with --dry-run to give a caller this lane's own verdict
# at zero network risk; that is how the operator platter avoids offering a command this gate
# rejects, §2.6 D5) · --auto (unattended launchd mode) · --bootstrap (stamps dir ABSENT: deploy the
# tip unstamped, loud banner) · --force (same, with stamps present — documented escape hatch).
# Env: DEPLOY_REPO · CC_POSTLAND_DIR · CC_POSTLAND_BIN · CC_PAGES_DIR · CC_DEPLOY_SCAN ·
#      CC_DEPLOY_MAX_LAG_COMMITS (25) / CC_DEPLOY_MAX_LAG_HOURS (6) — the T2 budget, whichever
#      trips FIRST · CC_DEPLOY_DEGRADE (on; off|0|no|false ⇒ T2 disabled = the strict green-only
#      gate, i.e. exactly the pre-2026-08-07 behaviour, freeze included) ·
#      CC_DEPLOY_DAMP_S · CC_HOST_MANIFEST · CC_DEPLOY_HOST_TIMEOUT_S · CC_BACKLOG_BIN ·
#      CC_DEPLOY_BATS_BIN / CC_DEPLOY_TIMEOUT_BIN (UNSET ⇒ resolved; SET-EMPTY ⇒ disabled) ·
#      CC_DEPLOY_PARITY_ASSERT (UNSET ⇒ scripts/deploy-parity-assert.sh; SET-EMPTY ⇒ refresh off) ·
#      CC_DEPLOY_MIGRATIONS (UNSET ⇒ scripts/deploy-migrations.sh; SET-EMPTY ⇒ migration converge off).
# bash-3.2-safe, no eval, fail-closed, never rolls back.
set -uo pipefail

DEPLOY_REPO="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"
POSTLAND_DIR="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
STAMPS_DIR="$POSTLAND_DIR/stamps"
# The SECOND green producer's store, deliberately NOT $STAMPS_DIR (backlog b4f93c9fa73c). Every
# consumer of stamps/ reads `.verdict` and nothing else — no producer field exists there and the
# `suites` scope field is checked by nobody — so a hermetic-SUBSET green written into stamps/ would
# be indistinguishable from a full-corpus one and would silently become a T1 target. Separate
# directory, separate reader, separate tier: T1H below is the ONE place the weaker claim is spent.
OFFBOX_DIR="${CC_OFFBOX_STAMPS:-$POSTLAND_DIR/offbox}"
OFFBOX_PULL_BIN="${CC_OFFBOX_PULL_BIN:-$DEPLOY_REPO/scripts/offbox-green-pull.sh}"
OFFBOX_PULL_BOUND_S="${CC_DEPLOY_OFFBOX_PULL_S:-60}"
# T1H's kill switch, same shape and spellings as CC_DEPLOY_DEGRADE. Off ⇒ the ladder is exactly the
# T1/T2/T3 it was before this producer existed.
OFFBOX="${CC_DEPLOY_OFFBOX:-on}"
POSTLAND_BIN="${CC_POSTLAND_BIN:-$DEPLOY_REPO/scripts/postland-verify.sh}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
SCAN_N="${CC_DEPLOY_SCAN:-200}"
# T2's authorisation, and its kill switch. A budget of 0 is NOT "disabled" — it means "degrade the
# moment there is any lag at all"; turning T2 off entirely is CC_DEPLOY_DEGRADE, one switch with one
# job. `off` is the documented spelling; the other three are accepted because a kill switch that
# silently ignores `=0` is a trap, and this one is the only way back to the strict green-only gate.
MAX_LAG_COMMITS="${CC_DEPLOY_MAX_LAG_COMMITS:-25}"
MAX_LAG_HOURS="${CC_DEPLOY_MAX_LAG_HOURS:-6}"
DEGRADE="${CC_DEPLOY_DEGRADE:-on}"
case "$MAX_LAG_COMMITS" in ''|*[!0-9]*) MAX_LAG_COMMITS=25 ;; esac
case "$MAX_LAG_HOURS"   in ''|*[!0-9]*) MAX_LAG_HOURS=6 ;; esac
DAMP_FILE="$POSTLAND_DIR/deploy-auto.damp"
DAMP_WINDOW_S="${CC_DEPLOY_DAMP_S:-86400}"
MANIFEST="${CC_HOST_MANIFEST:-$DEPLOY_REPO/scripts/host-suites.manifest}"
# SIZED FROM THE BAND THIS RUNNER EXECUTES IN, NOT FROM A BENCH (2026-08-10, backlog cb9980e4b0e5).
# 300s was a bench number. host_checks runs under com.claude.deploy-live — ProcessType Background
# (PRI 4), Nice 10, LowPriorityIO — and puts `nice -n 19` on top of that. MEASURED on this box, one
# `test-hermeticity-lint.sh --selftest` back to back at load ~9-11: 70s in the utility band, 252s
# under `taskpolicy -c background`. A 3.6x band tax. tests/test-hermeticity-lint.bats is 272s in the
# utility band (52/52 green, 234s of it three --selftest invocations) — and it was CUT on 6 of 6
# host runs, never once producing the post-deploy verdict scripts/host-suites.manifest admits it
# for. A bound structurally below its suite's runtime does not bound that suite, it DELETES it: the
# sensor is default-off and every artifact the operator reads looks identical to a healthy one.
# THE FIGURE IS THE END-TO-END RUN, NOT THE EXTRAPOLATION — and the difference is why this says
# 3600. Scaling the utility-band total by the per-selftest tax predicted ~980s; the same command
# this function issues (`timeout -k 10 <bound> taskpolicy -c background nice -n 19 bats <suite>`,
# from $DEPLOY_REPO, stdin closed) actually took **1399s** wall, 52/52 green, at load 9-22. The
# extrapolation was 1.4x optimistic, because the band tax is not a constant you may multiply
# through — it moves with contention, and this box has been observed at load 15-48. 1800 would have
# been 1.29x the real figure: enough to look fixed, and enough for one load spike to put the sensor
# straight back to a permanent non-verdict. 3600 is 2.6x a REALISTICALLY-LOADED measurement. What
# it costs is deploy CADENCE, never deploy safety: host_checks runs AFTER the advance and never
# blocks, never rolls back, never changes the exit code, so a long host phase cannot touch the
# deploy that already happened — it can only delay the NEXT one.
# THIS SCRIPT HAS NO RUN LOCK — checked, not assumed, because a longer host phase is only safe if
# something serialises the ticks. What serialises them is launchd, on the timer path only:
# launchd.plist(5) StartInterval, verbatim — "If the job is running during an interval firing, that
# interval firing will likewise be missed." com.claude.deploy-live is StartInterval 600, so the
# ticks queue rather than overlap however long the host phase runs.
# The path launchd does NOT cover is scripts/deploy-now.sh (`deploy-live.sh --force`, agent- or
# desk-fired), which can land inside a running host phase. That was already true at 300s; this
# widens the window it can land in. It is survivable for the same reason as above: by then the
# advance is done and host_checks is a read-only `bats` run over $DEPLOY_REPO, so the overlap costs
# load, not correctness.
# The hang this bound exists to contain is still contained — and its known cause was removed at the
# source by the `</dev/null` at the invocation site below.
HOST_TIMEOUT_S="${CC_DEPLOY_HOST_TIMEOUT_S:-3600}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"
# ── CONSECUTIVE-CUT COUNTER, PER SUITE (2026-08-10, backlog 75463ef0d0f9) ────────────────────────
# R6 is what makes a cut safe: a non-verdict is a claim about the MACHINE, never about the tree, so
# it must not page as a failure. What R6 does not supply is the other half — a suite that reaches no
# verdict on EVERY deploy is not a machine event any more, it is a sensor that has stopped being one,
# and by R6 alone it looks identical to a healthy one on every artifact an operator reads. Measured:
# tests/test-hermeticity-lint.bats was CUT on 6 of 6 host runs across 12 days against a bound
# structurally below its runtime (cb9980e4b0e5), and nothing anywhere said so. The deploy log said
# `CUT` six times, correctly, one line per run — and one correct line per run, forever, is the
# alarm-polarity defect: a message that appears at the same rate whether or not anything is wrong.
#
# The counter is the fix and it is a straight port of scripts/postland-verify.sh's (CUT_MAX /
# CUT_COOLOFF, :527) with ONE change of key: postland tracks a single streak on the TREE, because it
# runs one corpus per sweep and a new tree is a new subject. The host lane runs N INDEPENDENT suites
# against one live layer, so the streak that means anything here is PER SUITE — one suite cutting
# forever while its neighbours stay green is exactly the case that went unnoticed, and a tree-keyed
# streak cannot see it (any neighbour's verdict would clear it).
#
# BOTH KNOBS ARE PORTED, because they are one mechanism and not two. CUT_MAX decides when a streak
# becomes news; the COOL-OFF is what stops that news being re-sent every tick — the same job
# hooks/lib/page-damp.sh does for the pagers that have one, and this lane has no damping of its own
# (its RED page is sha-keyed, so it is naturally per-deploy). Without it a suite past CUT_MAX
# re-pages every 600s tick forever, which is the 570-near-duplicate-pages defect page-damp.sh
# records, rebuilt here. Damping by cool-off also collects the second prize: a suite that provably
# is not reaching a verdict stops being fed a full HOST_TIMEOUT_S of a loaded box every tick.
# The suppression is BOUNDED and SPOKEN — the skip is `say`n with its remaining time on every tick
# it fires, and when it expires the suite runs again and re-pages if it cuts again, so an unresolved
# condition re-asserts about twice an hour rather than never (page-damp.sh's own TTL rule).
# 0 disables either half without a separate kill switch: COOLOFF=0 ⇒ `elapsed -lt 0` is never true.
HOST_CUTS="$POSTLAND_DIR/host-cuts"                              # rows: "<suite> <consecutive-n> <epoch>"
HOST_CUT_MAX="${CC_DEPLOY_HOST_CUT_MAX:-3}"                      # consecutive cuts on ONE suite before paging
HOST_CUT_COOLOFF="${CC_DEPLOY_HOST_CUT_COOLOFF:-1800}"           # ...and before that suite is run again
case "$HOST_CUT_MAX"     in ''|*[!0-9]*) HOST_CUT_MAX=3 ;; esac
case "$HOST_CUT_COOLOFF" in ''|*[!0-9]*) HOST_CUT_COOLOFF=1800 ;; esac

DRY_RUN=0; BOOTSTRAP=0; FORCE=0; AUTO=0; OFFLINE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --auto)      AUTO=1 ;;
    --bootstrap) BOOTSTRAP=1 ;;
    --force)     FORCE=1 ;;
    --offline)   OFFLINE=1 ;;
    -h|--help)   sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *)           printf 'deploy-live: unknown arg %s (use --dry-run|--offline|--auto|--bootstrap|--force)\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
# --offline IS DECISION-ONLY, and that is a safety property, not a convenience. Skipping the fetch
# means deciding against a tip that may be arbitrarily stale; a mode that could then really merge
# would deploy old trunk without ever saying it had not looked. It also takes this mode off the
# actuation path entirely, so its refusals (below) cannot strand an advance — they can only decline
# to answer a question. Callers who want a real deploy must fetch.
[ "$OFFLINE" -eq 1 ] && DRY_RUN=1

# --auto implies non-interactive: the two gate-bypasses are OPERATOR verbs and an unattended job
# must never be able to take them. Refused at parse time, before anything reads the network.
if [ "$AUTO" -eq 1 ] && { [ "$BOOTSTRAP" -eq 1 ] || [ "$FORCE" -eq 1 ]; }; then
  printf 'deploy-live: --auto cannot be combined with --bootstrap/--force (operator-only gate bypasses)\n' >&2
  exit 2
fi

say()  { printf 'deploy-live: %s\n' "$1"; }
# Under --auto the steady state is silence: only state CHANGES reach the log.
asay() { [ "$AUTO" -eq 1 ] || printf 'deploy-live: %s\n' "$1"; }
die()  { printf 'deploy-live: REFUSED — %s\n' "$1" >&2; exit 1; }
g()    { git -C "$DEPLOY_REPO" "$@"; }

# ── damping: subject+state, sticky only while the STATE holds ────────────────────────────────────
# Returns 0 (emit + re-arm) when the reason CHANGED or the window elapsed; 1 (suppress) otherwise.
# The marker is cleared on every healthy outcome, so recovery→re-failure is loud immediately —
# a window that survives a recovery would swallow the first page of the NEXT outage.
damp_ok() { # <state-key>
  local key="$1" prev_key="" prev_ts=0 now
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ -r "$DAMP_FILE" ]; then
    prev_ts="$(sed -n '1p' "$DAMP_FILE" 2>/dev/null || true)"
    prev_key="$(sed -n '2p' "$DAMP_FILE" 2>/dev/null || true)"
  fi
  case "$prev_ts" in ''|*[!0-9]*) prev_ts=0 ;; esac
  case "$now"     in ''|*[!0-9]*) now=0 ;; esac
  if [ "$prev_key" = "$key" ] && [ "$((now - prev_ts))" -lt "$DAMP_WINDOW_S" ]; then return 1; fi
  mkdir -p "$POSTLAND_DIR" 2>/dev/null || true
  printf '%s\n%s\n' "$now" "$key" > "$DAMP_FILE" 2>/dev/null || true
  return 0
}
damp_clear() { rm -f "$DAMP_FILE" 2>/dev/null || true; }

# ── absolute-path binary resolution (launchd's PATH has no Homebrew — where both of these live) ──
_resolve_bin() { # <name…> → first executable absolute path
  local c n
  for n in "$@"; do
    c="$(command -v "$n" 2>/dev/null || true)"
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    for c in "/opt/homebrew/bin/$n" "/usr/local/bin/$n"; do
      if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    done
  done
  return 1
}
# UNSET ⇒ resolve one. SET (including set to EMPTY) ⇒ honored verbatim, so CC_DEPLOY_TIMEOUT_BIN=
# genuinely disables bounding — `${VAR:-}` cannot tell unset from set-empty, and a seam that
# cannot turn a thing OFF is not a seam.
if [ -n "${CC_DEPLOY_TIMEOUT_BIN+set}" ]; then TIMEOUT_BIN="$CC_DEPLOY_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_bin timeout gtimeout || true)"; fi
if [ -n "${CC_DEPLOY_BATS_BIN+set}" ]; then BATS_BIN="$CC_DEPLOY_BATS_BIN"
else BATS_BIN="$(_resolve_bin bats || true)"; fi

bounded() { # <secs> <cmd…> — rc 124 = OUR bound fired. Unbounded (never blocked) with no timeout(1).
  local secs="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 10 "$secs" "$@"   # no --foreground ⇒ its own process group ⇒ the whole bats tree
}

# a stamp is green iff its JSON says so — python3 when available (real parse), grep otherwise
is_green() { # <stamp-file>
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try: sys.exit(0 if json.load(open(sys.argv[1])).get("verdict")=="green" else 1)
except Exception: sys.exit(1)' "$1" 2>/dev/null && return 0
    return 1
  fi
  grep -qE '"verdict"[[:space:]]*:[[:space:]]*"green"' "$1" 2>/dev/null
}

# T2's eligibility test, and deliberately NOT `! is_green` — the two are not complements. Only an
# explicit "red" verdict is disqualifying: an ABSENT stamp is the common case (the verifier emits
# 0.17 greens/day, so most trees are simply unjudged) and a `cut`/`hung` stamp is a NON-VERDICT
# about the machine, never a claim about the tree — R6, the same rule host_checks applies below.
# An unparseable stamp lands here too, and lands as eligible: a stamp we cannot read has not
# claimed anything. Kept as a second function rather than folded into a shared verdict-reader
# because is_green sits on the DEFAULT path and rewriting it to serve this one would put the whole
# green gate at risk for a caller that runs only past the budget.
is_red() { # <stamp-file>
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try: sys.exit(0 if json.load(open(sys.argv[1])).get("verdict")=="red" else 1)
except Exception: sys.exit(1)' "$1" 2>/dev/null && return 0
    return 1
  fi
  grep -qE '"verdict"[[:space:]]*:[[:space:]]*"red"' "$1" 2>/dev/null
}

# T1H's eligibility test — a THIRD reader, for the same reason is_red is a second one: is_green sits
# on the DEFAULT path and must not be reshaped to serve a weaker caller.
#
# IT CHECKS THE SCOPE, WHICH is_green DOES NOT. The on-box store has no producer field and no
# consumer that checks corpus scope, so `verdict:"green"` there means whatever the writer meant. Here
# the claim is explicitly narrower, so the reader demands the narrower claim be SPELLED: a record
# must say BOTH `verdict:"green"` AND `scope:"offbox-hermetic"`. A record that says only the first —
# a full-corpus stamp copied into this directory, or a future producer with a different scope — is
# NOT eligible. Without that clause this reader would accept any green from any producer that ever
# learns to write here, which is the conflation the separate directory exists to prevent.
is_offbox_green() { # <offbox-stamp-file>
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    sys.exit(0 if d.get("verdict") == "green" and d.get("scope") == "offbox-hermetic" else 1)
except Exception: sys.exit(1)' "$1" 2>/dev/null && return 0
    return 1
  fi
  grep -qE '"verdict"[[:space:]]*:[[:space:]]*"green"' "$1" 2>/dev/null \
    && grep -qE '"scope"[[:space:]]*:[[:space:]]*"offbox-hermetic"' "$1" 2>/dev/null
}

# ── post-deploy HOST checks (§4.3) ───────────────────────────────────────────────────────────────
# The manifest is the corpus PARTITION contract (§4.2, owned by postland-verify): plain text, one
# tests/<name>.bats per line, `#` comments. MISSING manifest ⇒ EMPTY set ⇒ skip silently — the
# verifier's side of the same contract reads a missing manifest as "run everything", so the two
# halves stay total by construction and neither ever needs hand-syncing.
host_cut_row() { # <suite> → its prior "<consecutive-n> <epoch>", or "0 0" when it has no streak
  local p pn pts
  # `[ -f ]` FIRST. Redirections are applied left to right, so `< "$HOST_CUTS" 2>/dev/null` opens the
  # input BEFORE stderr is silenced — a missing file therefore prints the shell's own "No such file
  # or directory" into the launchd log on every run before the first cut. Control flow is fine
  # either way; the noise reads like a failure in the one log an operator scans. Same trap, same
  # fix, same reason as scripts/postland-verify.sh cut_bump.
  if [ -f "$HOST_CUTS" ]; then
    while read -r p pn pts || [ -n "${p:-}" ]; do
      [ "${p:-}" = "$1" ] || continue
      case "${pn:-}"  in ''|*[!0-9]*) pn=0 ;; esac
      case "${pts:-}" in ''|*[!0-9]*) pts=0 ;; esac
      printf '%s %s' "$pn" "$pts"; return 0
    done < "$HOST_CUTS"
  fi
  printf '0 0'
}
host_in_cut_cooloff() { # <suite> — 0 = still cooling off, so do not run it this tick
  local row pn pts
  row="$(host_cut_row "$1")"; pn="${row%% *}"; pts="${row##* }"
  [ "$pn" -ge "$HOST_CUT_MAX" ] || return 1
  [ "$(( $(date +%s) - pts ))" -lt "$HOST_CUT_COOLOFF" ]
}
host_cut_page() { # <suite> <n> <deployed-sha> — an HONEST page: names no test, asks for no bisect
  local pf slug
  slug="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')"
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  # Keyed on the SUITE, never on the sha — the opposite of the RED page below, and deliberately so.
  # A red is a claim ABOUT A TREE, so its page is per-deploy and shows the current one. A cut is a
  # claim about the machine and says nothing whatever about the tree, so a sha in this name would
  # mint a fresh file every tick for one unchanging finding — which is also what defeats
  # autonomy-sweep's is_new damping, since a never-before-seen path is always new.
  pf="$PAGES_DIR/deploy-host-cut-$slug.page"
  { date +%s
    printf 'post-deploy HOST CUT (no verdict) — %s has reached NO verdict on %s consecutive deploys\n' "$1" "$2"
    printf 'live layer: %.12s\n' "$3"
    printf 'NOT a test failure — do not bisect, and do not read this suite as passing.\n'
    printf 'It emitted no result line matching "^not ok <N>", or our %ss bound fired: either way NO\n' "$HOST_TIMEOUT_S"
    printf 'claim about the live layer was produced, and none has been for %s deploys running.\n' "$2"
    printf 'Causes in the order they have actually occurred here: the bound sits below the suite'"'"'s\n'
    printf 'runtime IN THIS LAUNCHD BAND (cb9980e4b0e5 — a 3.6x tax on the bench figure); the box is\n'
    printf 'starved; the suite wedges. Time it in the band before re-sizing anything.\n'
    printf 're-run:  cd %s && time %s %s\n' "$DEPLOY_REPO" "${BATS_BIN:-bats}" "$1"
    printf 'cool-off: this suite is skipped for %ss, then run again — it re-pages if it cuts again.\n' "$HOST_CUT_COOLOFF"
  } > "$pf" 2>/dev/null || true
  say "  PAGE $1 — $2 consecutive non-verdicts · $pf"
  # SAME KEYING RULE AS THE RED BACKLOG BELOW, for the same reason: cc-backlog mints its event key
  # from project+title+source, so the title carries the SUITE and nothing else. `$2` here grows by
  # one every cool-off, and a sha changes every deploy — either in the title would mint a new item
  # per tick for one unresolved finding, which is exactly the defect that produced 5 items for one
  # finding on 2026-08-05. stderr is NOT swallowed: the DONE-GUARD announces a re-file of an
  # already-closed key there and deliberately does not reopen it.
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-deploy HOST CUT (no verdict): $1" \
    --project claude-infrastructure --source deploy-live >/dev/null
  return 0
}
host_checks() { # <deployed-sha> — never blocks, never rolls back, never changes the exit code
  local sha="$1" line s tap rc notok n=0 red="" cut="" pf iscut row cn newcuts=""
  [ -r "$MANIFEST" ] || return 0
  # Build a list (bash 3.2: no mapfile). Suite paths are repo-relative and space-free by contract.
  local SUITES; SUITES=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                                   # trailing / whole-line comment
    line="$(printf '%s' "$line" | tr -d '[:space:]')"    # trim (a path with whitespace is not one)
    [ -n "$line" ] || continue
    SUITES[${#SUITES[@]}]="$line"
  done < "$MANIFEST"
  [ "${#SUITES[@]}" -gt 0 ] || return 0

  if [ -z "$BATS_BIN" ] || [ ! -x "$BATS_BIN" ]; then
    say "host-checks SKIPPED — no bats(1) resolvable (${#SUITES[@]} manifest suite(s) unrun)"
    return 0
  fi
  say "post-deploy host checks: ${#SUITES[@]} suite(s) from ${MANIFEST##*/}, against the LIVE layer"
  for s in "${SUITES[@]}"; do
    iscut=0
    # COOL-OFF IS TESTED BEFORE THE ABSENT CHECK, and that ordering carries the state. A suite
    # skipped here is the one case that must CARRY ITS ROW FORWARD UNCHANGED — including the epoch,
    # which is what the remaining cool-off is measured from. Every other outcome below writes no row
    # at all, which is how the streak is cleared and how the file prunes itself (see the write).
    if host_in_cut_cooloff "$s"; then
      row="$(host_cut_row "$s")"
      say "  skip $s (cut cool-off: ${row%% *} consecutive non-verdicts, $(( HOST_CUT_COOLOFF - ($(date +%s) - ${row##* }) ))s left)"
      newcuts="$newcuts$s $row
"
      continue
    fi
    if [ ! -f "$DEPLOY_REPO/$s" ]; then say "  skip $s (absent in the deployed tree)"; continue; fi
    n=$((n + 1))
    # `</dev/null` — THE $BATS_BIN INVOCATION SITE (the resolution at the top of this file is not
    # one). bats does not read stdin itself but INHERITS it into every test, so a manifest suite that
    # stubs a stdin-consuming binary with an unconditional `cat` waits forever for an EOF that never
    # comes (5e460544 measured rc 124; ce13bd08 fixed the landing runners).
    # MEASURED 2026-08-06, correcting the premise those commits shipped with: launchd hands its child
    # /dev/null on fd 0 already, so `com.claude.deploy-live --auto` is NOT the exposed path. The
    # exposed path is an agent- or desk-fired deploy, where fd 0 is a unix SOCKET whose reader never
    # sees EOF. That hang would be especially quiet here: host_checks never blocks and never changes
    # the exit code, so a wedged suite is not even a red — it is a deploy that simply never returns.
    # `bounded` DOES cover it (rc 124 → CUT), which contains the failure; this removes its cause.
    # Nothing pipes into this script and its four while-read loops are all fed from files, so no
    # stdin in use is lost.
    tap="$( cd "$DEPLOY_REPO" && bounded "$HOST_TIMEOUT_S" nice -n 19 "$BATS_BIN" "$s" </dev/null 2>&1 )"; rc=$?
    # THE <N> IS WHAT MAKES A LINE A RESULT. TAP spells a result `not ok <N> <desc>`; without the
    # <N> this also counted a line truncated mid-write and any unprefixed stderr opening with those
    # four bytes — routine, since the suite above is captured 2>&1. Measured on /usr/bin/grep (BSD,
    # what launchd's PATH resolves) and ugrep 7.5.0: `not ok`, `not ok3 x`, `not okay x` and
    # `not okcorpus: …` each count 1 under `^not ok` and 0 here. Same spelling as
    # scripts/postland-verify.sh TAP_NOTOK_RE (C30) and scripts/ship-land.sh — pinned equal by
    # tests/tap-grammar-parity.bats. `-a` so the count cannot change with which grep is on PATH.
    notok="$(printf '%s\n' "$tap" | grep -acE '^not ok [0-9]+' 2>/dev/null || true)"
    case "$notok" in ''|*[!0-9]*) notok=0 ;; esac
    # R6: a NAMED failure is the only red. rc alone is blind — bats masks a load-kill behind its
    # own pipefail'd pipeline and exits non-zero naming zero tests. That is CUT: a non-verdict
    # about the machine, never a claim about the tree, and it must never page as a failure.
    #
    # OUR BOUND IS TESTED FIRST, and that ordering is the rule, not a detail (2026-08-10, backlog
    # cb9980e4b0e5). `notok > 0` used to be tested first, so a suite this script KILLED mid-corpus
    # was reported RED off whatever it had emitted before the kill. A killed run is a non-verdict
    # about the machine by the same R6 reasoning that covers rc-124-naming-nothing — and worse
    # here, because the failing SET is a function of where the kill landed, so the `$s($notok)`
    # title below (cc-backlog's event key is project+title+source) mints a NEW item every time load
    # moves the truncation point. That is the sha-in-the-title non-idempotency, by another door.
    # Found on tests/test-hermeticity-lint.bats: 52/52 green in a clean tree at 272s against this
    # 300s bound, 6 of 6 host runs CUT, and the one RED it ever produced was a truncated run
    # claiming a green tree was broken. The reached failures are NAMED in the line — a non-verdict
    # must not also be a silence — but they do not page and do not file.
    if [ "$rc" -eq 124 ]; then
      cut="$cut $s"; iscut=1
      if [ "$notok" -gt 0 ]
        then say "  CUT  $s — bound ${HOST_TIMEOUT_S}s fired after $notok named failure(s) (truncated: no verdict)"
        else say "  CUT  $s — bound ${HOST_TIMEOUT_S}s fired (no verdict)"
      fi
    elif [ "$notok" -gt 0 ]; then    red="$red $s($notok)"; say "  RED  $s — $notok failing"
    elif [ "$rc" -ne 0 ];    then    cut="$cut $s"; iscut=1; say "  CUT  $s — rc=$rc naming 0 tests (no verdict)"
    else                                                    say "  ok   $s"
    fi
    # A VERDICT CLEARS THE STREAK — and clearing is spelled "write no row", never "write 0". Both
    # RED and ok land here, because the streak counts NON-VERDICTS and a red is a verdict: a suite
    # failing every deploy is already the RED channel's finding, and counting it here would page it
    # a second time under a headline that says the opposite ("no claim was produced").
    if [ "$iscut" -eq 1 ]; then
      row="$(host_cut_row "$s")"; cn=$(( ${row%% *} + 1 ))
      newcuts="$newcuts$s $cn $(date +%s)
"
      [ "$cn" -ge "$HOST_CUT_MAX" ] && host_cut_page "$s" "$cn" "$sha"
    fi
  done
  # WRITTEN ONCE, FROM THIS TICK ONLY — the file is rebuilt rather than edited, so it prunes itself:
  # a suite that reached a verdict, vanished from the deployed tree, or left the manifest simply has
  # no row and starts from zero next time it cuts. That is why there is no TTL and no reaper here.
  # Note where this sits: ABOVE the `[ -n "$red" ] || return 0` below, because the common tick has
  # no red at all and an early return would drop every streak the loop just counted.
  if [ -n "$newcuts" ]; then
    mkdir -p "${HOST_CUTS%/*}" 2>/dev/null || true
    printf '%s' "$newcuts" > "$HOST_CUTS" 2>/dev/null || true
  else
    rm -f "$HOST_CUTS" 2>/dev/null || true
  fi
  [ -n "$cut" ] && say "host-checks: non-verdict (cut) suites —$cut"
  [ -n "$red" ] || return 0

  # A live-layer finding, not a deploy blocker: page + backlog, sha-keyed so a repeat tick of the
  # same deployed sha overwrites one page instead of accreting a new one per run.
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  pf="$PAGES_DIR/deploy-host-red-$(printf '%.12s' "$sha").page"
  { date +%s
    printf 'post-deploy HOST RED at %.12s — the LIVE layer is advanced and FAILING host suites\n' "$sha"
    printf 'failing:%s\n' "$red"
    [ -n "$cut" ] && printf 'no-verdict (cut):%s\n' "$cut"
    printf 're-run:  cd %s && bats%s\n' "$DEPLOY_REPO" "$(printf '%s' "$red" | sed 's/([0-9]*)//g')"
    printf 'NOT a rollback trigger: rolling the live layer back is an operator decision.\n'
  } > "$pf" 2>/dev/null || true
  say "host RED —$red · paged $pf (live layer NOT rolled back)"
  # BACKLOG KEY = the FAILING SET, never the sha. cc-backlog mints its event key from
  # project+title+source (bin/cc-backlog mk_id), so a sha in the title made every deploy a NEW item
  # for the SAME unresolved finding and the ledger's own idempotency never engaged — measured
  # 2026-08-05 at 5 items for `tests/deploy-parity-live.bats(1)` across 5 shas, 2 of them already
  # auto-blocked as "persistent thrash — the worker cannot land". The sha was STALE ON ARRIVAL
  # besides: the live layer advances again before a worker claims, so the item named a tree that was
  # no longer deployed (item f271cd880295 read @7ded71b8 with 3e423b76 already live).
  # The two channels key differently ON PURPOSE — the PAGE is per-deploy (sha-keyed, overwritten, so
  # it always shows the CURRENT tree), the BACKLOG is per-finding (one unresolved finding, one item).
  # stderr is NOT swallowed: cc-backlog's DONE-GUARD announces a re-file of an already-closed key
  # there and deliberately does not reopen it, so hiding it would turn a regression into silence.
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-deploy HOST RED:$red" \
    --project claude-infrastructure --source deploy-live >/dev/null
  return 0
}

# ── link refresh (MONOTONE ⇒ UNCONDITIONAL, never nested in the advance) ─────────────────────────
# Advancing content and reconciling the namespace are UNRELATED operations that used to share one
# branch: install.sh sat below `merge --ff-only`, so BOTH earlier exits — "already deployed" and the
# rollback refusal — returned before a single link was created. That was survivable only while the
# advance actually fired. It stopped firing because content advances by a SECOND path: ~/.claude is
# per-file symlinks into this checkout, so every land moves the live layer for free, while TARGET
# (last-green) lags by the verify duration. Live HEAD is therefore PERMANENTLY ahead of last-green,
# the rollback guard correctly refuses forever, and everything nested under it is dead code.
# Measured 2026-07-30 on the live host: 96 consecutive `would ROLL BACK` refusals, 174 commits of
# lag. The content stayed fresh throughout — only files that did not exist at the last successful
# advance rotted, which is exactly why nothing looked broken. Diagnose from the actuator's own log
# (a wall of identical refusals is the tell), never from the freshness of the content.
#
# A step that is idempotent and monotone has no business being conditional, so this one runs before
# the fetch too: it depends on neither the network nor the TARGET decision.
#
# WHY NOT SIMPLY HOIST install.sh — it is not link-only, and at this cadence it is destructive.
# install.sh:452-463 runs `launchctl bootout` + `bootstrap` for every one of the 20 launchd/*.plist
# on EVERY run, OUTSIDE copy_file's skip path, i.e. whether or not the plist changed. At 144
# ticks/day that resets every StartInterval (the three 3600s jobs would never fire again), SIGTERMs
# the three KeepAlive daemons, and boots out com.claude.deploy-live — the job running this script.
# It also has ZERO notion of staged-pending (`grep -n pending-activation install.sh` → no hits), so
# it would link deliberately-unlinked files 144×/day and erase the "activation un-run" signal
# (tests/deploy-parity.bats:315 pins that hazard). install.sh therefore stays exactly where it is,
# on the advance path only, at operator cadence.
#
# The safe partition is the assert's OWN output: `MISSING: ln -sf <src> <dest>` is emitted only
# AFTER by-design-PENDING files have `continue`d — so MISSING is by construction the set that
# belongs to nobody else. Consuming that verdict rather than re-deriving the want-list here is
# deliberate: two auditors over one population that do not share a state model disagree, and that
# divergence is how this whole class of bug survives.
#
# THE UNIVERSE THIS REPAIRS IS THE ASSERT'S, AND IT WIDENED 2026-08-10 (P6,
# docs/research/land-architecture-100p-2026-08-10.md §2.E). No code changed here, and that is the
# point of consuming a verdict instead of re-deriving one — but the SCOPE changed underneath, so a
# reader of this block should not have to go and diff another file to learn it. The assert's
# pathspec was `hooks commands scripts bin skills`, i.e. 5 of install.sh's ~19 deploy classes; it
# now enumerates every SYMLINK class install.sh globs (adding agents/, top-level lib/, hooks/*.py,
# scripts/lib/*.sh, bin/desk-*, the root-config SSOTs, and vendor/ as one dir link per plugin).
# Before that, a brand-new file in any of those classes reached the live layer only when install.sh
# ran — i.e. only after a SUCCESSFUL advance, on a lane measured refusing 601 consecutive times. It
# did not land degraded, it landed ABSENT, and every consumer guard on it (`[ -f x ] && . x`) is a
# silent skip. This function is the only thing on the machine that repairs that without an advance.
#
# WHAT IT MUST NOT REPAIR, and why the grep is the whole safety argument: install.sh's COPY classes
# (githooks/, launchd/*.plist, statusline.sh, bin/it2-wrapper→bin/it2, CLAUDE.md) are now asserted
# too, under their own COPYMISS/COPYSTALE/CLAUDEMD tokens — deliberately NOT the `MISSING: ln -sf`
# spelling. install.sh:289 records why: githooks shipped as symlinks for six hours and it is called
# "a critical bug", because a link into the working tree dangles on any branch switch in the shared
# checkout and git fails OPEN on a dangling hook, so the gate silently stops existing. This loop
# consumes one line shape and creates symlinks; the copy classes are kept out of that shape at the
# producer, not filtered here, so there is nothing for a future edit of this function to get wrong.
# Both directions are pinned by tests (deploy-live.bats: a new class IS repaired · a COPYMISS is
# NOT; deploy-parity.bats: no copy-class finding ever prints an ln -sf line).
PARITY_ASSERT="${CC_DEPLOY_PARITY_ASSERT-$DEPLOY_REPO/scripts/deploy-parity-assert.sh}"

link_refresh() { # never fails, never changes the exit code, never touches a PENDING file
  local out rc miss line src dest n=0
  # UNSET ⇒ the default path. SET (including SET-EMPTY) ⇒ honored verbatim, so
  # CC_DEPLOY_PARITY_ASSERT= genuinely disables the refresh — same seam contract as the bin vars.
  [ -n "$PARITY_ASSERT" ] && [ -r "$PARITY_ASSERT" ] || return 0
  out="$( cd "$DEPLOY_REPO" && /bin/bash "$PARITY_ASSERT" 2>/dev/null )"; rc=$?
  # rc 3 is the assert's NO-VERDICT (its own enumeration failed). An empty MISSING list produced by
  # a failed enumeration is NOT "nothing is missing" — piping stdout straight to grep would launder
  # one into the other, so the rc is read BEFORE the text.
  if [ "$rc" -eq 3 ]; then
    say "link-refresh: NO VERDICT from ${PARITY_ASSERT##*/} (rc 3) — nothing relinked"
    return 0
  fi
  miss="$(printf '%s\n' "$out" | grep '^MISSING: ln -sf ' 2>/dev/null || true)"
  [ -n "$miss" ] || return 0   # steady state emits NOTHING: --auto's silence contract holds here too
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # "MISSING: ln -sf <src> <dest>" — tracked runtime paths are space-free by the same contract the
    # host manifest relies on, so trailing-field splitting is safe and needs no array.
    src="${line#MISSING: ln -sf }"; dest="${src#* }"; src="${src%% *}"
    [ -n "$src" ] && [ -n "$dest" ] && [ "$src" != "$dest" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then say "  would link $dest"; n=$((n + 1)); continue; fi
    mkdir -p "${dest%/*}" 2>/dev/null || true
    # Monotone by construction: the assert only reports a dest that fails `-e`, so this creates a
    # link where none resolved and never overwrites a live file.
    if ln -sf "$src" "$dest" 2>/dev/null; then n=$((n + 1)); say "  linked $dest"
    else say "  FAILED to link $dest (→ $src)"; fi
  done <<EOF
$miss
EOF
  if [ "$n" -gt 0 ] && [ "$DRY_RUN" -eq 1 ]; then say "link-refresh: $n live link(s) WOULD BE created; nothing mutated"
  elif [ "$n" -gt 0 ]; then say "link-refresh: $n live link(s) created — brand-new tracked file(s) had no link"
  fi
  return 0
}

# ── which tracked path is about to block the fast-forward (§2.6b) ────────────────────────────────
# `--ff-only` refuses when the advance would overwrite a locally-modified tracked file — and ONLY
# for files the advance actually touches, so the answer is the INTERSECTION of two sets, not either
# one alone. Emitted one path per line; empty ⇒ nothing in the advance's own path set is dirty.
# Iterating the DIRTY set (typically 0-3 entries) and asking git about each is deliberate: the
# changed set can be thousands of paths across 91 commits of lag, and git's own pathspec is a
# sounder membership test than any string matching we would write here.
merge_blockers() { # <from-sha> <to-sha>
  local from="$1" to="$2" line path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in '??'*) continue ;; esac        # untracked cannot block a --ff-only
    path="${line#???}"                             # porcelain v1: exactly 2 status chars + a space
    case "$path" in *' -> '*) path="${path##* -> }" ;; esac   # rename ⇒ the DESTINATION is on disk
    [ -n "$path" ] || continue
    [ -n "$(g diff --name-only "$from" "$to" -- "$path" 2>/dev/null)" ] && printf '%s\n' "$path"
  done <<EOF
$(g status --porcelain 2>/dev/null)
EOF
  return 0
}

g rev-parse --git-dir >/dev/null 2>&1 || die "DEPLOY_REPO is not a git checkout: $DEPLOY_REPO"

# ── migration converge (face 3 of inertness-generator-2026-08-07 §3) ────────────────────────────
# Registration state is no longer a script in a folder someone is supposed to visit: it is a
# migration that landed in the same diff as its subject, and the converger runs it. Two phases —
# materialise the live pending-activation queue from the repo SSOT (which makes the REPO-ONLY and
# CONTENT-DRIFT parity classes unrepresentable), then run every un-applied migrations/*.sh.
#
# Called from TWO places, deliberately, and the reason is the same one the link_refresh block above
# spells out. This step is idempotent and monotone, so it "has no business being conditional" — but
# the ONLY call that can run a migration in the same cycle as the land that carried it is the one
# BELOW the advance, and both early exits ("already deployed", the rollback refusal) return before
# reaching it. Unconditional here catches the retries and any hand-edit of the derived queue; the
# post-advance call is what makes LANDED ⇒ LIVE hold within one cycle. In steady state the second
# call never runs (the early exit fires first) and this one is two `cmp`s and a ledger read.
#
# NEVER `die`: a migration failure is a finding about the enforcing store, not a reason to abandon
# the deploy — the advance has value on its own, and scripts/wrap-ledger.sh is what refuses ✅ while
# a failure stands. Same contract as host_checks below.
MIGRATIONS_BIN="${CC_DEPLOY_MIGRATIONS-$DEPLOY_REPO/scripts/deploy-migrations.sh}"
migrations_converge() { # never fails, never changes the exit code
  [ -n "$MIGRATIONS_BIN" ] && [ -x "$MIGRATIONS_BIN" ] || return 0
  # --dry-run MUST propagate. This script's own contract for the flag is "decide + print, mutate
  # nothing", and a converge step that quietly ran for real underneath it would make the operator's
  # one safe way to inspect a deploy the thing that performs it.
  if [ "$DRY_RUN" -eq 1 ]; then
    "$MIGRATIONS_BIN" --dry-run || true
    return 0
  fi
  "$MIGRATIONS_BIN" || say "migration converge reported a FAILURE — see $STATE_MIGRATIONS/failed/ (the deploy itself stands: a migration failure is a finding about the enforcing store, and scripts/wrap-ledger.sh is what refuses ✅ while it holds)"
  return 0
}
STATE_MIGRATIONS="${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrations}"

# UNCONDITIONAL, and deliberately ahead of the fetch — a landed-but-unlinked file must be repaired
# even when the network is down, the tip has no green stamp, or the live layer already sits above it.
link_refresh
migrations_converge

# ── --offline · DECIDE WITHOUT THE NETWORK (§2.6 D5 / V9) ────────────────────────────────────────
# The operator platter (bin/cc-do, hooks/operator-readout.sh) must not offer a deploy command this
# script's own gate rejects. So it asks THIS script for the verdict instead of re-deriving the tier
# ladder in the renderer — the predicate stays in exactly one place, which is the whole point of
# `--dry-run --offline` existing at all. Two reasons it cannot simply call `--dry-run`:
#
#   1. operator-readout.sh is a STOP HOOK. A fetch there is a network round-trip at every turn close.
#   2. Decisive: a fetch that FAILS `die`s rc 1, and the caller reads rc as "the lane refuses" — so a
#      renderer probing runnability over a dropped network would report a deploy blocker THAT IT
#      CAUSED ITSELF. A gate must never key on a signal it produces. (Same shape as the guard that
#      aborted its own measurement: memory gate-must-not-key-on-its-own-signal.)
#
# --offline therefore decides against the ALREADY-FETCHED origin/main — the identical ref both
# renderers already use to compute `behind`, so the probe and the row it guards cannot disagree
# about which trunk they mean. An absent ref is still a hard refusal: unknown is never assumed safe.
if [ "$OFFLINE" -eq 1 ]; then
  # gate_bounded: NOT-ON-THE-ACTUATION-PATH — --offline forces DRY_RUN at parse time, so this
  # refusal can only decline to ANSWER, never withhold an advance; and its sole callers are
  # renderers that print it as a ⊘ HELD row, so it is an EVENT on first occurrence rather than
  # after a budget expires. The 545-refusal scar was a standing state nobody was told about; this
  # one is told every time or it is not reached at all. (permission-gate-lint §9 — a gate that
  # pages immediately is strictly stronger than one that pages when a clock runs out.)
  #
  # DECLARED HERE AND NOT ON THE ENCLOSING `if`, deliberately. The lint accepts a marker on the
  # enclosing condition so a multi-line gate declares its bound once — but that would have covered
  # the `g fetch … || die` on the else-branch too, and this marker's text is FALSE of that leg: the
  # fetch gate IS on the actuation path, it is what the 144x/day launchd lane hits. It went from 10
  # undeclared gates to 9 on the first attempt, which is the lint catching a declaration that
  # exempted more than it was true of.
  g rev-parse --verify -q origin/main >/dev/null 2>&1 || die "no already-fetched origin/main in $DEPLOY_REPO — --offline never fetches one"
else
  g fetch origin main >/dev/null 2>&1 || die "git fetch origin main FAILED in $DEPLOY_REPO (network? remote?)"
fi

HEAD_SHA="$(g rev-parse HEAD 2>/dev/null || true)"
TIP_SHA="$(g rev-parse origin/main 2>/dev/null || true)"
[ -n "$HEAD_SHA" ] && [ -n "$TIP_SHA" ] || die "cannot resolve HEAD / origin/main in $DEPLOY_REPO"

# ── STALENESS, measured on BOTH axes before any tier decides (§2.3) ───────────────────────────────
# Commits = how far the live layer trails trunk. Hours = the age of the commit the live layer is ON,
# which is the only clock that keeps ticking when trunk is quiet. Whichever exceeds its budget first
# authorises T2. Both are read here, unconditionally, so every refusal page can state them even when
# the budget is nowhere near tripping — the old refusals named a reason and never a magnitude.
LAG_COMMITS="$(g rev-list --count "$HEAD_SHA..origin/main" 2>/dev/null || echo 0)"
case "$LAG_COMMITS" in ''|*[!0-9]*) LAG_COMMITS=0 ;; esac
_head_ts="$(g log -1 --format=%ct "$HEAD_SHA" 2>/dev/null || echo 0)"
_now="$(date +%s 2>/dev/null || echo 0)"
case "$_head_ts" in ''|*[!0-9]*) _head_ts=0 ;; esac
case "$_now"     in ''|*[!0-9]*) _now=0 ;; esac
LAG_HOURS=0
[ "$_head_ts" -gt 0 ] && [ "$_now" -gt "$_head_ts" ] && LAG_HOURS=$(( (_now - _head_ts) / 3600 ))
# LAG_TRIP carries the boolean AND the reason in one value: empty ⇒ inside the budget. A degraded
# advance must be able to say WHICH clock authorised it, or the banner is an assertion with no
# evidence attached to it.
LAG_TRIP=""
if [ "$LAG_COMMITS" -gt "$MAX_LAG_COMMITS" ]; then
  LAG_TRIP="$LAG_COMMITS commit(s) behind trunk (budget $MAX_LAG_COMMITS)"
elif [ "$LAG_HOURS" -gt "$MAX_LAG_HOURS" ]; then
  LAG_TRIP="${LAG_HOURS}h since the live commit was authored (budget ${MAX_LAG_HOURS}h)"
fi

# ── PULL THE OFF-BOX VERDICT, BOUNDED AND FAIL-OPEN (backlog b4f93c9fa73c) ───────────────────────
# GitHub cannot write to this machine, so the second producer's last mile is a pull, and this is the
# only scheduled thing that runs often enough to be it (144x/day) without adding a launchd job — an
# addition that would be C10 and operator-gated, i.e. a producer parked behind a manual step.
# EVERY failure here is a no-op: the puller exits 0 on a missing gh, a locked keychain, no network,
# a rate limit or an unparseable response, and this call is bounded on top of the puller's own two
# bounds. Skipped under --offline, which is decision-only by contract and must touch no network.
if [ "$OFFLINE" -eq 0 ] && [ -x "$OFFBOX_PULL_BIN" ]; then
  case "$OFFBOX" in
    off|OFF|0|no|NO|false|FALSE) : ;;
    # gate_bounded: the bound is the point — a hung pull must never become a deploy refusal, so the
    # rc is discarded deliberately rather than checked.
    *) bounded "$OFFBOX_PULL_BOUND_S" "$OFFBOX_PULL_BIN" --quiet >/dev/null 2>&1 || true ;;
  esac
fi

TARGET=""; UNSTAMPED=0; BANNER=""; TIER=""; GREEN_SHA=""; RED_WALKED=0; GREEN_AT_HEAD=""
if [ ! -d "$STAMPS_DIR" ]; then
  # The verification net is not active yet. Deploying is a decision, not a default.
  if [ "$BOOTSTRAP" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    if [ "$AUTO" -eq 1 ]; then
      # Damped: this state persists until an operator runs the activation, i.e. potentially for
      # days at 144 ticks/day. Page once per window; the cc-blockers VERIFIER-INERT alarm is the
      # standing surface (absence-is-loud, R9) — the page is the edge, not the level.
      if damp_ok "no-stamps-dir:$STAMPS_DIR"; then
        mkdir -p "$PAGES_DIR" 2>/dev/null || true
        { date +%s
          printf 'deploy-live BLOCKED: no stamps dir (%s) — the post-land verification net is not active\n' "$STAMPS_DIR"
          printf 'the live layer is FROZEN until the net is activated and a tree verifies green.\n'
          printf 'fix: run docs/activation/pending-activation/14-land-pipeline-v2-activate.sh (CONFIRM=1)\n'
        } > "$PAGES_DIR/deploy-no-stamps.page" 2>/dev/null || true
        die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Run 14-land-pipeline-v2-activate.sh."
      fi
      exit 1   # same refusal, inside the damp window: an honest non-zero, silently
    fi
    die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active. Re-run with --bootstrap to deploy origin/main UNSTAMPED."
  fi
  TARGET="$TIP_SHA"; BANNER="UNSTAMPED bootstrap deploy — no verification net; nothing vouches for this tree"
elif [ "$FORCE" -eq 1 ]; then
  TARGET="$TIP_SHA"; BANNER="UNSTAMPED --force deploy — green-stamp gate BYPASSED by the operator"
else
  # ── T1 · VERIFIED — the default path, and the only tier that is allowed to be silent ────────────
  # ── ONE process for sha+tree, not one fork PER COMMIT ────────────────────────────────────────────
  # This loop used to call `g rev-parse "$sha^{tree}"` per candidate, i.e. up to SCAN_N=200 forks per
  # evaluation. Measured on this box: 2.233s for the 200-fork walk vs 0.011s for `git log --format`
  # — a 200x difference that IS the whole cost of an evaluation. It matters twice over:
  #   · the lane runs 144x/day under launchd, so this was ~28,800 forks/day of pure overhead; and
  #   · it is the precondition for `--dry-run --offline` being cheap enough for the operator platter
  #     to ask this script for a verdict (§2.6 D5) instead of re-deriving the ladder in a renderer.
  # It is slowest in exactly the state that matters: T1 `break`s early when it finds a green
  # descendant, so the full 200-commit walk happens only when the answer is "blocked".
  # `git log --format` is the header-free spelling of `rev-list --format`; verified identical sha
  # lists to the `rev-list` it replaces, and %T is the same tree `rev-parse ^{tree}` returned.
  scanned=0
  while IFS=' ' read -r sha tree; do
    [ -n "$sha" ] || continue
    if [ -n "$tree" ] && is_green "$STAMPS_DIR/$tree.json"; then
      [ -n "$GREEN_SHA" ] || GREEN_SHA="$sha"    # newest green, deployable or not — the DIAGNOSIS
      # The ancestry test belongs HERE and not only at the anti-rollback guard below. A green tree
      # BEHIND live HEAD is history, not lag — bin/cc-blockers:425 says exactly that in its own
      # comment — so selecting it as TARGET only to be refused 60 lines later is what turned a
      # transient miss into an ABSORBING state: the same target, refused identically, 534 times.
      # A GREEN ON LIVE HEAD IS A STATE, NOT A TARGET (2026-08-10, backlog 3b22efbc2340).
      # `merge-base --is-ancestor X X` is TRUE, so this test used to match HEAD against ITSELF,
      # set TARGET=HEAD, and — because everything below is wrapped in `if [ -z "$TARGET" ]` —
      # skip T1H and T2 entirely. The lag budget then became STRUCTURALLY UNREACHABLE: once the
      # live layer sat on any green tree, the lane reported "already deployed" and exited 0 no
      # matter how far trunk ran ahead, and under --auto that path is SILENT by design. Measured
      # with a fixture pair: green-on-HEAD + 30 commits above (budget 25) ⇒ no advance, lag stays
      # 30, exit 0; the identical case with NO green anywhere ⇒ T2 degrades and converges to 0.
      # So one green FROZE the layer where zero greens did not — strictly worse than the loud
      # refusal it replaced, because exit 0 reads as healthy.
      # The fix is the STRICT half of the same ancestry test: a target must be ABOVE the layer.
      # HEAD-is-green is remembered instead, and spent below as the benign no-advance exit — the
      # message and exit code that state is entitled to, once T1H and T2 have had their turn.
      if [ "$sha" = "$HEAD_SHA" ]; then
        GREEN_AT_HEAD=1; break                  # nothing above was green; below is history
      elif g merge-base --is-ancestor "$HEAD_SHA" "$sha" >/dev/null 2>&1; then
        TARGET="$sha"; UNSTAMPED="$scanned"; TIER=T1; break
      fi
    fi
    scanned=$((scanned + 1))
  done <<EOF
$(g log --format='%H %T' -n "$SCAN_N" origin/main 2>/dev/null)
EOF

  if [ -z "$TARGET" ]; then
    # ── AT-TIP IS A STATE, NOT A REFUSAL (added 2026-08-07 from the first LIVE v2 evaluation) ──────
    # T1 missed AND there is nothing above the layer, so the candidate set is EMPTY and no tier can
    # ever match. Without this the ladder falls through to T3's `die`. Observed on the first v2
    # dry-run, with the layer sitting exactly on origin/main:
    #   REFUSED — no GREEN tree is a DESCENDANT of live HEAD 5b6c7e3e (the newest one, 3725e543, is
    #   BEHIND it …) — nothing is safe to deploy
    # Every clause is true and the verdict is still wrong: there was nothing to deploy, safe or not.
    # "Nothing is safe to deploy" about an EMPTY set reports a hazard where there is only completion.
    #
    # NOT COSMETIC. `die` exits 1, so at the healthy steady state the lane emits a refusal every 600s
    # (144/day) and pins `launchctl … last exit code = 1` forever — the exact signal that hid the
    # original 33h freeze. Once the lane always says 1, the next REAL refusal is indistinguishable
    # from the noise; an alarm that fires when nothing is wrong carries the same zero bits as one
    # that cannot fire. §2.2's table named T1/T2/T3 and had no row for "already at the tip".
    #
    # PLACED HERE, not before the ladder. Keying it on TIP up front also swallowed the "already
    # deployed" exit (TARGET == HEAD, a green ON the live commit with unstamped commits above), which
    # is a genuinely different and more informative state — measured: it reddened two tests that were
    # right. The empty-candidate-set condition is only meaningful AFTER T1 has missed, so it belongs
    # inside this branch. LAG_COMMITS is the same precondition T2 already relies on 15 lines below.
    if [ "$LAG_COMMITS" -eq 0 ]; then
      [ "$AUTO" -eq 1 ] && damp_clear
      # Two spellings of one empty candidate set, kept distinct because the evidence differs: with
      # a green ON the layer this is the VERIFIED steady state, without one it is merely the tip.
      # Both are exit 0; conflating them would drop the only positive fact the lane ever reports.
      if [ -n "$GREEN_AT_HEAD" ]; then
        asay "already deployed — live layer is at the newest deployable commit ${HEAD_SHA:0:12} (0 un-stamped commit(s) above)"
      else
        asay "at trunk tip ${HEAD_SHA:0:12} — nothing above the live layer to deploy"
      fi
      exit 0
    fi

    # T1 missed, in one of two states. WHICH one is a diagnosis for the page and the operator; the
    # policy below is identical either way, so the tier logic never branches on it again.
    RSTEM="deploy-blocked"
    if [ -n "$GREEN_AT_HEAD" ]; then
      # The newest green IS the live layer, so "no green descendant" is true but reads as a
      # rollback hazard; the real state is that nothing ABOVE has verified yet. Only reachable
      # past the lag budget (inside it, the benign exit below returns first).
      RKEY="green-at-head:${HEAD_SHA:0:12}"
      RMSG="the newest GREEN tree IS live HEAD ${HEAD_SHA:0:12}; none of the $LAG_COMMITS commit(s) above it has verified"
    elif [ -n "$GREEN_SHA" ]; then
      RKEY="green-behind:${GREEN_SHA:0:12}"
      RMSG="no GREEN tree is a DESCENDANT of live HEAD ${HEAD_SHA:0:12} (the newest one, ${GREEN_SHA:0:12}, is BEHIND it — deploying that would report a deploy that never happened)"
    else
      RKEY="no-green:$STAMPS_DIR"
      RMSG="no GREEN stamp among the newest $SCAN_N commits of origin/main"
    fi

    # ── T1H · HERMETICALLY VERIFIED — positive evidence, narrower scope (backlog b4f93c9fa73c) ────
    # Sits between T1 and T2 because it is strictly more evidence than T2 and strictly less than T1:
    #   T1  a FULL-corpus green on this tree           → advance, silent
    #   T1H an OFF-BOX green over the HERMETIC subset,  → advance, BANNERED (the scope is named)
    #       and no on-box RED on the same tree
    #   T2  no red at all, i.e. the ABSENCE of evidence → advance, LOUD + a page
    #
    # NOT GATED ON THE LAG BUDGET, and that is the deliberate difference from T2. T2's budget exists
    # because T2 advances on absence — it must wait until staleness outweighs having no proof at all.
    # T1H advances on a POSITIVE result, so making it wait for the same budget would hold a proven
    # tree hostage to a clock, and produce exactly the freeze this whole rebuild was for.
    #
    # THE `is_red` CONJUNCT IS LOAD-BEARING, NOT BELT-AND-BRACES. The hermetic subset is defined by
    # excluding the machine-coupled suites, so those failures are precisely its blind spot. If the
    # on-box verifier has actually judged this tree RED, it saw something this producer cannot, and
    # the off-box acquittal must not overrule it. Absent / cut / hung stay eligible, per R6 — the
    # same reading is_red already gives T2.
    if [ -z "$TARGET" ] && [ "$LAG_COMMITS" -gt 0 ]; then
      case "$OFFBOX" in
        off|OFF|0|no|NO|false|FALSE) : ;;
        *)
          while IFS=' ' read -r sha tree; do
            [ -n "$sha" ] || continue
            [ -n "$tree" ] || continue
            if is_offbox_green "$OFFBOX_DIR/$tree.json" && ! is_red "$STAMPS_DIR/$tree.json"; then
              TARGET="$sha"; TIER=T1H
              BANNER="HERMETIC deploy — $RMSG; taking ${sha:0:12}, acquitted OFF-BOX over the hermetic subset only (the machine-coupled suites are NOT covered by this verdict)"
              break
            fi
          done <<EOF
$(g log --format='%H %T' -n "$SCAN_N" "$HEAD_SHA..origin/main" 2>/dev/null)
EOF
          ;;
      esac
    fi

    # ── T2 · DEGRADED — authorised by the LAG, never by the reason ────────────────────────────────
    # Three preconditions, and the third is not redundant: with LAG_COMMITS=0 there is nothing above
    # live HEAD to degrade TO, while LAG_HOURS keeps climbing on a quiet trunk — so without it the
    # hours budget would fire forever against an empty candidate list and report T3's "trunk is red
    # all the way down" about a trunk that is simply already deployed.
    if [ -z "$TARGET" ] && [ "$LAG_COMMITS" -gt 0 ] && [ -n "$LAG_TRIP" ]; then
      case "$DEGRADE" in
        off|OFF|0|no|NO|false|FALSE) : ;;   # the kill switch: strict green-only gate, freeze included
        *)
          # Bounded to HEAD..origin/main, so the walk cannot step below the live layer and re-propose
          # history as a target. Every candidate here is above live HEAD by construction; the
          # anti-rollback guard below still runs, because "above" is not "descendant" if HEAD ever
          # diverges from trunk.
          # Same one-process sha+tree read as T1 above, for the same reason.
          while IFS=' ' read -r sha tree; do
            [ -n "$sha" ] || continue
            if [ -n "$tree" ] && is_red "$STAMPS_DIR/$tree.json"; then
              RED_WALKED=$((RED_WALKED + 1)); continue      # walk back one commit
            fi
            TARGET="$sha"; TIER=T2; break
          done <<EOF
$(g log --format='%H %T' -n "$SCAN_N" "$HEAD_SHA..origin/main" 2>/dev/null)
EOF
          if [ -n "$TARGET" ]; then
            BANNER="DEGRADED deploy — $RMSG; taking the newest NOT-RED commit instead, authorised by $LAG_TRIP"
          else
            # ── T3 · BLOCKED ──
            RSTEM="deploy-trunk-red"
            RKEY="trunk-red:${TIP_SHA:0:12}"
            RMSG="every one of the $RED_WALKED commit(s) above live HEAD carries a RED stamp — trunk is red all the way down"
          fi
          ;;
      esac
    fi

    # ── GREEN-ON-HEAD, INSIDE BUDGET · the benign no-advance exit ────────────────────────────────
    # Reached only after T1H and T2 have both declined, which is the whole point of moving this
    # state down here: it used to be decided ABOVE the ladder (T1 matching HEAD against itself),
    # which is what made the budget unreachable. Ordering it last means a positive off-box verdict
    # (T1H, which carries no lag budget) still deploys a proven tree instead of resting on
    # "already deployed", and a tripped budget still degrades through T2.
    # LAG_TRIP empty is the guard: inside the budget this is the healthy steady state and exit 0
    # is honest. PAST the budget it is a freeze, and the refusal path below says so with a page —
    # so the one green on the layer can no longer buy unlimited silence.
    if [ -z "$TARGET" ] && [ -n "$GREEN_AT_HEAD" ] && [ -z "$LAG_TRIP" ]; then
      [ "$AUTO" -eq 1 ] && damp_clear
      asay "already deployed — live layer is at the newest deployable commit ${HEAD_SHA:0:12} ($LAG_COMMITS un-stamped commit(s) above)"
      exit 0
    fi

    # ── GREEN-BEHIND HEAD, INSIDE BUDGET · the benign WAIT (2026-08-10, backlog 2e7fe6fd5b7c) ─────
    # The clause above gave ONE face of "nothing above the layer is proven" its in-budget exit: the
    # green sitting exactly ON live HEAD. The other faces fell through to the refusal below, and the
    # commonest of them is the one a previous T2 leaves behind — a DEGRADED advance moves the layer
    # without minting a green for where it landed, so the newest green ends up strictly BEHIND live
    # HEAD. That state is not a rollback hazard and not a freeze; it is the same wait, wearing a
    # different diagnosis.
    #
    # MEASURED, and it is what dispatched this item: live HEAD 5f63cdc1 with the newest green
    # ed095d4b one step behind it, lag 24 commit(s) / 5h against a 25 / 6h budget — inside on BOTH
    # axes — refused, wrote a page reading "the live layer is FROZEN until a tree verifies green",
    # and exited 1. Nothing was frozen: the budget had not tripped and T2 would have degraded of its
    # own accord within the hour. The page was false, and a human wave was dispatched onto it.
    #
    # THE COST IS THE ONE §T1-at-tip ALREADY NAMES 130 LINES UP: `die` exits 1, so the lane spends
    # its healthy steady state emitting refusals (144/day) and pinning launchctl's last exit code at
    # 1 — after which the next REAL refusal is indistinguishable from the noise. That reasoning was
    # never specific to an empty candidate set; it applies verbatim to every in-budget wait.
    #
    # WHAT IS DELIBERATELY *NOT* WIDENED, because each would delete a capability:
    #   · PAST the budget ($LAG_TRIP set) stays the loud refusal + page. A freeze must stay a freeze.
    #   · DEGRADE off is the operator electing a strict green-only gate, so T2 can never fire and
    #     this wait has nothing to wait FOR. Exiting 0 would convert their deliberate strictness
    #     into permanent silence, so that path keeps refusing.
    #   · The DIAGNOSIS is not dropped — $RMSG is carried into the message, so "the newest green is
    #     BEHIND live HEAD" (i.e. the layer is running unverified bytes) is still stated every time.
    #     This is a WAIT, not an all-clear, and it must not read as one.
    #   · NO GREEN ANYWHERE ($GREEN_SHA empty) is EXCLUDED, and that exclusion is the load-bearing
    #     half. The three faces are not interchangeable: green-at-head means the layer runs PROVEN
    #     bytes, green-behind means the net is demonstrably ALIVE (it produced that green) so a
    #     green above is plausibly coming — but no green in the whole $SCAN_N window is the
    #     VERIFIER-INERT condition, where the net may simply be dead. That is not a wait, it is the
    #     alarm, and it stays loud for the same reason the no-stamps-dir path does at the top of
    #     this ladder (absence-is-loud, R9). Widening to it broke four T1H controls that pin the
    #     budget out at 999/999 — they were right: with nothing above ever verifying and no green
    #     below to prove the producer works, "wait for the budget" is waiting for nothing.
    #     `$GREEN_SHA` is precisely the discriminator, being set by T1's walk on the first green it
    #     sees whether or not that green was deployable.
    case "$DEGRADE" in
      off|OFF|0|no|NO|false|FALSE) : ;;
      *)
        if [ -z "$TARGET" ] && [ -z "$LAG_TRIP" ] && [ -n "$GREEN_SHA" ]; then
          [ "$AUTO" -eq 1 ] && damp_clear
          asay "waiting — $RMSG; lag $LAG_COMMITS commit(s) / ${LAG_HOURS}h, inside the degrade budget ($MAX_LAG_COMMITS / ${MAX_LAG_HOURS}h) — no advance, and none is due yet"
          exit 0
        fi
        ;;
    esac
  fi

  if [ -z "$TARGET" ]; then
    # Under --auto this refusal is damped on the REASON, not the tip: a moving tip with no green
    # is one persistent state, and keying the page on the tip would mint a fresh page per land.
    if [ "$AUTO" -eq 1 ] && ! damp_ok "$RKEY"; then exit 1; fi
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$PAGES_DIR" 2>/dev/null || true
      pf="$PAGES_DIR/$RSTEM-$(printf '%.12s' "$TIP_SHA").page"
      { date +%s
        printf 'deploy-live BLOCKED: %s (tip %.12s)\n' "$RMSG" "$TIP_SHA"
        # The magnitude, on every refusal. A refusal that names only its reason cannot be told from
        # a healthy pause, which is how 534 of them read as normal for 33h.
        printf 'lag: %s commit(s) / %sh · degrade budget %s commit(s) / %sh · CC_DEPLOY_DEGRADE=%s\n' \
          "$LAG_COMMITS" "$LAG_HOURS" "$MAX_LAG_COMMITS" "$MAX_LAG_HOURS" "$DEGRADE"
        printf 'the live layer is FROZEN until a tree verifies green. stamps=%s verifier=%s\n' "$STAMPS_DIR" "$POSTLAND_BIN"
      } > "$pf" 2>/dev/null || true
      say "wrote page $pf"
    fi
    die "$RMSG — nothing is safe to deploy (verifier: $POSTLAND_BIN)"
  fi
fi

[ -n "$BANNER" ] && UNSTAMPED="$(g rev-list --count "$TARGET..origin/main" 2>/dev/null || echo 0)"

if [ "$TARGET" = "$HEAD_SHA" ]; then
  # The healthy steady state: nothing new is stamped green. Silent under --auto, and it CLEARS the
  # damp marker — a later refusal is then a state CHANGE and pages immediately.
  [ "$AUTO" -eq 1 ] && damp_clear
  asay "already deployed — live layer is at the newest deployable commit ${HEAD_SHA:0:12} ($UNSTAMPED un-stamped commit(s) above)"
  exit 0
fi
# THE GUARD AND ITS CONDITION ARE UNCHANGED; ONLY ITS CLAIM IS. MEASURED 2026-08-07 in a throwaway
# repo: when this test fails, TARGET is an ANCESTOR of live HEAD, and `git merge --ff-only <ancestor>`
# returns "Already up to date." with EXIT 0 — it cannot roll anything back, so "this would ROLL BACK
# the live layer" was never true. What the guard actually prevents is the lane taking that exit 0 and
# reporting `deployed X → Y`, running install.sh, running the host checks and filing a backlog item,
# ALL against a tree that never moved. It buys TRUTHFULNESS, not safety — which is also why it is
# kept: removing it risks the lane lying about a deploy, not losing work.
g merge-base --is-ancestor "$HEAD_SHA" "$TARGET" >/dev/null 2>&1 || \
  die "target ${TARGET:0:12} is not a descendant of live HEAD ${HEAD_SHA:0:12} — --ff-only would exit 0 WITHOUT moving the tree, so the lane would report a deploy that NEVER HAPPENED"

if [ "$DRY_RUN" -eq 1 ]; then
  [ -n "$BANNER" ] && say "!! $BANNER"
  say "DRY RUN — would fast-forward ${HEAD_SHA:0:12} → ${TARGET:0:12} ($UNSTAMPED un-stamped commit(s) would remain above); nothing mutated"
  exit 0
fi

[ -n "$BANNER" ] && say "!!!!! $BANNER !!!!!"

# ── the blocking state is NAMED BEFORE the merge, never guessed after it (§2.6b) ─────────────────
# This used to be `die "…FAILED (dirty tree? diverged?)"` — a guess offering two alternatives at the
# moment the operator can least afford to test both. Both are knowable exactly, and one of the two
# is not even reachable here (the anti-rollback guard above already excludes divergence), so the
# guess was wrong half the time by construction.
#
# 🚨 NEVER auto-stash, auto-checkout or auto-discard the blocking file. The live checkout is shared:
# an uncommitted tracked change in it is a PEER SESSION's work in progress (measured cause:
# hooks/backup-before-write.sh). The repo's own 26-deploy-gate-unblock refuses exactly this, in
# exactly these words — "That is very likely a peer session's uncommitted work. REFUSING to
# overwrite it… this script never discards local work." Detect, name, page, stop.
BLOCKERS="$(merge_blockers "$HEAD_SHA" "$TARGET")"
if [ -n "$BLOCKERS" ]; then
  BLOCKER_LIST="$(printf '%s\n' "$BLOCKERS" | tr '\n' ' ')"
  if [ "$AUTO" -eq 1 ] && ! damp_ok "dirty-tree:$BLOCKER_LIST"; then exit 1; fi
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  { date +%s
    printf 'deploy-live BLOCKED: DIRTY TREE — the advance %.12s → %.12s rewrites tracked path(s) that\n' "$HEAD_SHA" "$TARGET"
    printf 'carry UNCOMMITTED local changes in the shared checkout %s:\n' "$DEPLOY_REPO"
    printf '%s\n' "$BLOCKERS" | sed 's/^/  /'
    printf "That is very likely a PEER SESSION's uncommitted work. This lane never stashes, checks out\n"
    printf 'or discards it — commit or stash it in that checkout and the next tick advances.\n'
    printf 'inspect: git -C %s status --porcelain\n' "$DEPLOY_REPO"
  } > "$PAGES_DIR/deploy-dirty-tree.page" 2>/dev/null || true
  die "DIRTY TREE — the advance to ${TARGET:0:12} rewrites tracked path(s) carrying UNCOMMITTED local changes: $BLOCKER_LIST(very likely a peer session's work — this lane never stashes or discards it; commit or stash it yourself, then re-run)"
fi

# ⚠️ THE FILE UNDER THIS PROCESS CHANGES ON THE NEXT LINE. The merge rewrites the working tree and
# THIS script is in it, so from here on the code executing is the copy bash parsed BEFORE the merge,
# never the copy now on disk. Every function called below was defined above this line (host_checks()
# at 151, called at 391) and is therefore the PRE-merge definition.
#
# Consequence, and it presents exactly as a fix that did not work: a change to any post-merge code
# path is INERT for the very deploy that delivers it, and takes effect one deploy late. Measured
# 2026-08-05 — 8035ea63 took the sha OUT of the host-RED backlog title at 08:35Z; the checkout sat at
# c400e36e (pre-fix) until the 20:19Z advance, so that run parsed the OLD host_checks, fast-forwarded
# to e9cabc46 (which CONTAINS the fix), and at 20:28Z filed "…deploy-parity-live.bats(1) @
# e9cabc46698d" — sha-keyed, out of a tree whose own source can no longer emit one. That is item
# 27ac5a5b258f, and against the current source it reads as "the fix never landed". It had landed; it
# could not yet run. Never diagnose a post-merge behaviour against the CURRENT file: resolve what the
# checkout was on when the run STARTED (git reflog) and read THAT revision.
#
# Closing the gap for real means re-exec'ing self after the ff. Deliberately NOT done, and NOT filed
# either: the ledger already carries 24 symptom items for this one condition plus a generator item
# (07e6e3888e9c), so a 25th buys less than this comment does. The trap is low-frequency by
# construction — it can only bite a change to deploy-live.sh itself — and the cost it actually
# imposes is diagnostic, which is what these lines remove. Re-open the question if a post-merge fix
# ever needs to be correct on the FIRST deploy rather than the second.
if ! g merge --ff-only "$TARGET" >/dev/null 2>&1; then
  # The dirty-tree pre-flight above ruled out the first of the old message's two guesses. Rule out
  # the second by MEASURING it rather than offering it: divergence is `origin/main..HEAD` non-empty.
  # It should be structurally unreachable — the anti-rollback guard passed, so live HEAD is an
  # ancestor of a commit on origin/main — so reaching this arm means that premise broke, which is
  # worth saying out loud instead of hiding inside a shrug.
  AHEAD="$(g rev-list --count "origin/main..$HEAD_SHA" 2>/dev/null || echo 0)"
  case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
  [ "$AHEAD" -gt 0 ] && die "DIVERGED — the live checkout carries $AHEAD commit(s) that are not on origin/main, so it cannot fast-forward to ${TARGET:0:12}. This lane never rebases or resets a shared checkout; land or drop those commits by hand."
  die "git merge --ff-only ${TARGET:0:12} FAILED in $DEPLOY_REPO with BOTH named causes RULED OUT (no dirty tracked path inside the advance's own path set; HEAD carries no commit missing from trunk) — read \`git -C $DEPLOY_REPO status\` by hand"
fi
say "deployed ${HEAD_SHA:0:12} → ${TARGET:0:12}: $(g log -1 --pretty=%s "$TARGET" 2>/dev/null)"

# T2 only: the page records that an UNVERIFIED advance OCCURRED, and is written AFTER the merge so
# it can never claim one that did not. Sha-keyed and overwritten, like every per-deploy page here.
if [ "$TIER" = T2 ]; then
  mkdir -p "$PAGES_DIR" 2>/dev/null || true
  { date +%s
    printf 'deploy-live DEGRADED advance: %.12s → %.12s — NO green-verified tree was deployable\n' "$HEAD_SHA" "$TARGET"
    printf 'authorised by: %s\n' "$LAG_TRIP"
    printf 'the deployed tree carries no RED stamp, but nothing vouches for it GREEN. stamps=%s\n' "$STAMPS_DIR"
    printf 'walked back past %s RED-stamped commit(s) to reach it.\n' "$RED_WALKED"
    printf 'kill switch: CC_DEPLOY_DEGRADE=off restores the strict green-only gate (and its freeze).\n'
  } > "$PAGES_DIR/deploy-degraded-$(printf '%.12s' "$TARGET").page" 2>/dev/null || true
fi

if [ -x "$DEPLOY_REPO/install.sh" ]; then
  "$DEPLOY_REPO/install.sh" >/dev/null 2>&1 || die "merged ${TARGET:0:12} but install.sh FAILED — re-run $DEPLOY_REPO/install.sh by hand"
  # install.sh re-globs every per-file-symlink class on EVERY run and link_file ln -sf's whatever is
  # missing, so a brand-new tracked file IS linked by this call.
  #
  # > SUPERSEDED 2026-07-30 — the enumeration that stood here (8 classes, cited to
  # > install.sh:43-52,89-105,148-155,193-200,256-259) is stale on BOTH halves: the real count is 17
  # > classes (hooks/*.py, lib/*.zsh, agents/*.md, scripts/lib/*.sh, vendor/*/ and more were absent),
  # > launchd/*.plist is a COPY class rather than a link class, and every one of those line ranges
  # > has moved. It is not re-listed here: a hand-maintained mirror of another file's globs rots
  # > silently and this one already did. install.sh is the SSOT; scripts/deploy-parity-assert.sh:284
  # > carries the only want-table that is test-pinned against it (tests/deploy-parity.bats:191).
  #
  # This call is NOT what keeps the live namespace whole — it is unreachable whenever the advance
  # does not fire, which on this host is always. link_refresh() above owns that, unconditionally.
  say "install.sh ok (links refreshed, incl. any brand-new tracked file)"
else
  die "merged ${TARGET:0:12} but $DEPLOY_REPO/install.sh is missing/not executable — new files are NOT linked"
fi

# The advance has landed new tracked files, so a migration that shipped WITH its subject is on disk
# for the first time here. This is the call that makes LANDED ⇒ LIVE true within ONE cycle rather
# than two — the pre-fetch call above ran before the merge and could not see it.
migrations_converge

# The live layer has ADVANCED — only now do the host suites have a real subject to assert.
host_checks "$TARGET"

# A successful advance is a healthy outcome: re-arm the refusal channel.
[ "$AUTO" -eq 1 ] && damp_clear

say "$UNSTAMPED un-stamped commit(s) remain above the live tip (they deploy once verified green)"
exit 0
