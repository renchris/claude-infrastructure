#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# postland-verify.sh — the ASYNC post-land full-suite net.
#
# WHY: the pre-push gate is fast-and-partial (typecheck + touched-file lint) and the FULL bats suite
# runs only nightly — a red landed at 09:00 sits unseen until 04:00. This closes that window: every
# 5 min launchd asks "is origin/main's TREE already stamped green?"; if not, it runs the full
# check-set against that exact tree. TREE-keyed, so a rebase/amend to an identical tree is free.
# CRITICAL — checks NEVER run in $REPO: its working tree IS the live ~/.claude layer (176 symlinks
# point into it), so a `checkout --detach <sha>` there would DEPLOY an untested sha to the live
# fleet. Everything runs in a disposable detached $WORKTREE (`git clean -fd` — NEVER -x).
# V2 (LAND_PIPELINE_V2 §4.2): this script is now THE full-suite verdict OWNER. The land lane carries
# only O(diff) work and makes NO full-suite claim, so nothing else may write gate-green, and a red
# reaching trunk is HEALED here (auto-revert) rather than left for the next lander to trip over.
# Five v2 properties, each with its own block comment below: FRESH worktree per run · TREE/HOST
# corpus PARTITION (scripts/host-suites.manifest) · BACKGROUND QoS with NO admission sleeping ·
# AUTO-REVERT of a bisected culprit · GATE-GREEN sync on green.
# CHECK-SET (in a freshly-minted $WORKTREE at the target sha, private TMPDIR + background QoS):
# bash -n on every tracked *.sh / bash-shebang file (cheap, VERDICT-AFFECTING) · the WHOLE-TREE
# META-LINTS run STANDALONE and strict before the corpus (walltime + hermeticity — VERDICT-
# AFFECTING, and a red there SKIPS the corpus: the answer is already decided) · bats over the TREE
# corpus — tests/*.bats MINUS the host manifest (THE verdict) · a whole-tree lint (sc) finding
# COUNT, recorded as shellcheck_advisory ONLY (baseline unproven, never a verdict).
# RETRY LADDER: a red suite re-runs each failing FILE alone twice more; >=2/3 fails = REPRODUCIBLE,
# 1/3 = flake (→ flakes.jsonl, excluded from the verdict; all-flake ⇒ GREEN-WITH-FLAKES).
# ON REPRODUCIBLE RED: `git bisect run` FIRST (culprit sha), then a STATE-KEYED page + backlog item
# + notification (a fixed page key gets path-dedup-swallowed for 7 days). last-green stays put.
# STATES: GREEN · RED (a named, reproducible failure) · HUNG (the suite never returned AND the
# suspect file wedges again ALONE on a pristine checkout — a proven property of the TREE: stamped,
# paged at that file, fix = timeout-wrap the un-stubbed seam, never a bisect) · CUT (truncated by a
# MACHINE event — a peer pkill, OOM, starvation: nothing was proven, never stamped green or red,
# retried next sweep, honest page + cool-off at CUT_MAX). HUNG vs CUT is the load-bearing split:
# "retry when quieter" is the right answer to one and the one answer guaranteed never to clear the
# other. Bounds: POSTLAND_SUITE_TIMEOUT_S (5400) · POSTLAND_FILE_TIMEOUT_S (300); unbounded, HUNG is
# UNPROVABLE (nothing can return 124) so every hang candidate honestly degrades to a CUT.
# Verbs: --run-if-needed (launchd) · --run <sha> · bisect <file> <good> <bad> · is-green <sha> ·
#        status · --selftest.   Kill switches: POSTLAND_VERIFY=off (runtime-read ⇒ instantly inert) ·
#        POSTLAND_AUTOREVERT=off (verify + page, never push a revert).
# C10: OPERATOR loads the plist (docs/activation/pending-activation/09-postland-verify-activate.sh).
set -uo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled job. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: PLV_OSA_TIMEOUT_S · PLV_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
PLV_OSA_TIMEOUT_S="${PLV_OSA_TIMEOUT_S:-5}"
if [ -n "${PLV_OSA_TIMEOUT_BIN+set}" ]; then
  PLV_OSA_TB="${PLV_OSA_TIMEOUT_BIN}"
else
  PLV_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { PLV_OSA_TB="$_c"; break; }
  done
fi
plv_osa() {
  if [ -z "$PLV_OSA_TB" ] || [ ! -x "$PLV_OSA_TB" ]; then "$@"; return $?; fi
  "$PLV_OSA_TB" -k 3 "$PLV_OSA_TIMEOUT_S" "$@"
}

# ── bounding the CHECK-SET itself ────────────────────────────────────────────────────────────────
# Separate from plv_osa above, which bounds only the notification fork. Unbounded, a suite that
# WEDGES never returns: it holds this runner's mutex until LOCK_TTL, emits no verdict, and the job
# just disappears — there is no rc to classify, so a hang is not merely misfiled, it is INVISIBLE.
# rc 124 is the bound firing, and it is the primary HUNG discriminator below. PATH alone is not
# enough: this runs under launchd, whose PATH has no Homebrew — exactly where coreutils installs
# timeout(1). Same resolution ladder as bin/it2-wrapper.
_resolve_timeout() {
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" \
           "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout \
           /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
# UNSET ⇒ resolve one. SET (including set to EMPTY) ⇒ honored verbatim, so CC_POSTLAND_TIMEOUT_BIN=
# genuinely disables bounding — `${VAR:-}` cannot tell unset from set-empty, and a seam that cannot
# turn a thing OFF is not a seam.
if [ -n "${CC_POSTLAND_TIMEOUT_BIN+set}" ]; then TIMEOUT_BIN="$CC_POSTLAND_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_timeout || true)"; fi

bounded() { # <secs> <cmd…> — rc 124 = OUR bound fired. Unbounded (never blocked) with no timeout(1).
  local secs="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 10 "$secs" "$@"   # no --foreground ⇒ its own process group ⇒ the whole bats tree
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
STATE="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
REPO="${CC_POSTLAND_REPO:-$HOME/Development/claude-infrastructure}"
# ── FRESH WORKTREE PER RUN (§4.2.1) ──────────────────────────────────────────────────────────────
# v1 reused ONE long-lived cell (…/.worktrees/ci-postland) for every run: `checkout --detach` +
# `clean -fd` leaves gitignored state, stale symlink targets and half-written fixtures from the
# PREVIOUS tree in place, so the cell accumulates exactly the cross-tree residue a verdict must not
# depend on — it is the prime suspect for the 6-suite red set that never reproduced on a fresh
# checkout. v2 MINTS a private cell per run under $WT_ROOT and removes it on every exit path.
# $WORKTREE stays the name every check reads (CC_POSTLAND_WORKTREE still names the cell verbatim for
# a caller that wants a fixed path); prepare_worktree now points it at a freshly-minted dir.
WT_ROOT="${CC_POSTLAND_WT_ROOT:-$STATE}"                # where per-run cells are minted
WT_STALE_S="${CC_POSTLAND_WT_STALE_S:-28800}"           # 8h — a CRASHED run's cell is reaped on entry
WORKTREE="${CC_POSTLAND_WORKTREE:-$WT_ROOT/wt-run-$$}"
WT_MINTED=""        # the check cell WE minted — teardown only ever removes cells recorded here
WT_REVERT=""        # the auto-revert cell (same rule)
WT_REAPED=0
PAGES="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$HOME/.claude/bin/cc-backlog}"
NOTIFY_BIN="${CC_POSTLAND_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"    # author notify (best-effort)
NOTIFY_CMD="${CC_POSTLAND_NOTIFY:-}"                                   # empty → builtin osascript
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LANDLOG="${CC_POSTLAND_LANDLOG:-${LAND_LOG:-$HOME/.claude/land.log}}"
BATS_BIN="${CC_POSTLAND_BATS:-bats}"
# ── EVERY $BATS_BIN CALL SITE REDIRECTS STDIN FROM /dev/null (2026-08-06) ────────────────────────
# STATED HERE ONCE; the sites carry only a `</dev/null` and no repeated rationale.
#
# WHY. This runner is launched by launchd/the desk, so its stdin is whatever the caller handed it.
# CORRECTED 2026-08-06 — the original wording here said "whatever the DAEMON handed it, routinely a
# pipe with no writer that will never EOF", and the daemon half of that is measurably FALSE: a
# throwaway RunAtLoad job reading its own `lsof -d 0` reports /dev/null, so launchd already hands its
# children a stdin that EOFs. The real exposure is the DESK/AGENT half, and it is worse than the
# original claim: a Claude Code session's fd 0 is a unix SOCKET whose reader never sees EOF
# (measured, rc 124), and that is the path these runners are invoked on constantly. The redirect and
# every argument below are unchanged — only the named source of the bad stdin was wrong. Full
# measurement in the commit that fixed the other seven runners (a6bbd8e46e60). bats does not read
# stdin itself, but it
# INHERITS it all the way down into every test, and a suite that stubs a stdin-consuming binary
# with an unconditional `cat` then blocks forever waiting for an EOF that is not coming. That is
# 5e460544 exactly: tests/handoff-fire-kitty.bats stubbed osascript with a bare `cat >/dev/null`,
# which is correct for `osascript - …` (script ON stdin) and a forever-hang for `osascript -e …`
# (script in ARGV, stdin merely inherited). Measured there: stdin=/dev/null → 34/34 green in <1s;
# stdin=an open pipe with a live writer → rc 124, wedged at the first `-e` caller.
#
# WHY HERE AND NOT ONLY IN THE SUITE. 5e460544 fixed the three stubs of that shape; this fixes the
# CLASS. All 290 suites were screened under a no-EOF stdin and none depends on inherited stdin, so
# /dev/null is a strictly safer stdin than the one a daemon supplies — and one redirect per call
# site immunises every suite that exists today and every one written later, including any stub
# whose drain is correct for its own subject. The polarity is what makes it worth doing at the
# runner: a hand-run gets a stdin that EOFs and is green, so the hang is invisible to the only
# person who could see it, and a hung gate is indistinguishable from a slow one — nothing alarms.
#
# WORST EXPOSURE, and the reason this is not cosmetic: do_bisect's generated runner (see there)
# redirected stdout+stderr but not stdin, so a wedged suite inside `git bisect run` hangs a step
# that nothing else bounds by content. 7c32cc6f WALLED that runaway (a 900s bound + a step cap)
# but did not DE-CAUSE it. This does.
#
# NOT via `bounded`: that helper also runs `git bisect run` and other non-bats children, and the
# screen that licenses /dev/null covers the bats tree only. Per call site, deliberately.
# ── THIS SCRIPT DELIBERATELY DOES NOT NORMALIZE PATH (settled 2026-07-29) ────────────────────────
# Do not re-add a PATH prepend here. It was here (5abe5934, 2026-07-26) and was removed on purpose;
# the reasoning below is what stops it coming back the next time a red stamp looks PATH-shaped.
#
# HISTORY. A minimal-PATH run reproduced a red the interactive shell could not see:
#   env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin TERM=dumb \
#     bash -c 'cd <worktree> && bats tests/deploy-parity.bats'   => "not ok 8", vs 8/8 under a
# session PATH. Because the retry ladder (see run_target) re-runs each red FILE alone twice and
# convicts at >=2/3, an env-dependent failure is deterministic — written as a HARD red, never a
# flake. Normalizing here turned that red green, and 6 of the 7 suites in the original cluster did
# go quiet. But it bought the green by running the corpus in an environment that never occurs.
#
# WHY THAT IS THE WRONG TRADE. This gate's problem has always been false SIGNAL, not slowness, and
# a synthesised PATH deletes a detection capability outright: a suite can no longer discover that
# the ARTIFACT IT TESTS depends on ambient PATH, because the gate has already hidden the ambient.
# That capability was not hypothetical — removing the normalization is what exposed
# deploy-parity-assert.sh reporting NOPATH (a fact about the CALLER's environment) as deployment
# DRIFT, so every daemon caller whose PATH lacks $HOME/bin was told the checkout had drifted while
# every filesystem leg read LINKED. Under normalization the gate could never have seen it.
#
# WHAT REPLACES IT. The suites own their own hermeticity: a test that needs a tool resolves it
# explicitly, by ABSOLUTE PATH as well as PATH (the pattern scripts/handoff-fire.sh uses for
# timeout(1)), and an artifact that genuinely depends on ambient PATH is a BUG to fix, not an
# environment to fake. So the corpus runs under exactly the PATH this process was handed — which
# under launchd is the one the plist exports, and that is the environment being gated.

# ── TMP BASE, SLASH-NORMALIZED — the 6-consecutive-RED root cause (RED-proved 2026-07-29) ────────
# Every temp path this script mints is templated off $TMPDIR, and `mktemp` copies its template
# VERBATIM. launchd hands its jobs TMPDIR=/var/folders/…/T/ WITH a trailing slash (this script runs
# from com.claude.postland-verify, which sets no TMPDIR of its own), so
# `mktemp -d "${TMPDIR}/postland-run.XXXXXX"` produced `…/T//postland-run.abc123` — a doubled
# separator in the MIDDLE of the string. RUN_TMP is then handed to the corpus as its TMPDIR, and
# bats chops only a TRAILING slash (bats:121 `BATS_TMPDIR=${BATS_TMPDIR%/}`), so the interior `//`
# propagated into BATS_RUN_TMPDIR → BATS_TEST_TMPDIR → every path a test derives from it. Meanwhile
# bash's `cd` COLLAPSES duplicate slashes when it sets $PWD. So every assertion comparing a child's
# recorded cwd against such a path missed by exactly one slash: in the real corpus TAP at
# 22e866dbb7ae, tests/postland-verify.bats's three positive cell-path claims (C7's pinned path, the
# mint/teardown cell, C20's revert cwd) failed while all 50 of their siblings passed — a red that
# never reproduced standalone, because a plain trailing-slash TMPDIR is one bats chops correctly.
# Normalize ONCE here so no consumer has to: strip the trailing slash, but never yield the empty
# string (TMPDIR=/ is legal and must stay "/").
TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"; [ -n "$TMPBASE" ] || TMPBASE=/
LOCK_TTL="${CC_POSTLAND_LOCK_TTL:-3600}"
SUITE_TO="${POSTLAND_SUITE_TIMEOUT_S:-10800}"  # wall BACKSTOP only — the primary bound is the TAP
# progress stall (POSTLAND_STALL_S, see run_target). 10800 (was 5400, was 2700): the background band
# yields to sessions by design, so a busy box legitimately runs the corpus past any tight wall —
# measured 2026-07-29, healthy runs CUT at 2737s AND 5437s with zero not-ok. Hangs are caught by the
# stall bound in ~15 min; this ceiling exists only for the case where the TAP writer itself wedges.
FILE_TO="${POSTLAND_FILE_TIMEOUT_S:-300}"      # per-TEST retry bound + the hang confirm
RETRY_TO="${POSTLAND_RETRY_TIMEOUT_S:-5400}"   # WHOLE-FILE retry bound — only the fallback path
# WHY THE LADDER NEEDS ITS OWN, LARGER BOUND (C23). Until 2026-07-29 the ladder re-ran the whole FILE
# under FILE_TO=300 and counted ANY non-zero rc as a fail — including 124, which `bounded` documents as
# "OUR bound fired". A suite whose solo runtime exceeds the bound could therefore only ever be
# CONVICTED, never exonerated: both retries returned 124, fails hit 3/3, and the tree was stamped a
# "reproducible RED" that no re-run could clear. That is why 33 stamps carried 0 green, ever — and why
# deploy-live refused forever off the back of it. tests/postland-verify.bats measures ~50 min solo
# (51 tests, each minting scratch git repos) = 10x the bound; flakes.jsonl 2026-07-28T19:39Z records
# `exit 124 / notok=0` for that very file at load 6.61, and the land gate filed the same signal
# correctly as `cut-not-red`. The heaviest suites are exactly the ones the stamps convicted
# (waiting-recycle 98 tests, cc-reaper 80, ship-land 74, cc-backlog 61, postland-verify 51).
BISECT_TO="${POSTLAND_BISECT_TIMEOUT_S:-900}"  # WHOLE-BISECT wall bound — see do_bisect for the WHY
# 900s and not larger, deliberately. 2026-08-05: `--run-if-needed` (pid 57191) started 00:51:28, was
# orphaned to PPID 1, and was still alive 12h53m later inside a runaway `git bisect run` — every
# step rewriting the shared .git/config and committing fixture blobs into the real object store, so
# a sibling session's 13:06:23 repair of that config was undone seconds later and read as "the fix
# did not hold". Nothing bounded it: `bisect run` was the one unbounded call left in this file.
# The cost of the bound is that a bisect over a heavy suite (C23's ~50-min files) will not FINISH —
# and that is fine, because a cut bisect is a NON-VERDICT here (do_bisect's documented "empty when
# undecidable"), never a false conviction: the callers fall back to the landed sha and page, exactly
# as they already do when the bisect cannot decide. Losing culprit REFINEMENT is a bad afternoon;
# an unbounded runaway corrupting the shared repo for half a day is the incident.
BISECT_MAX_STEPS="${POSTLAND_BISECT_MAX_STEPS:-24}"  # STEP-COUNT cap — the OTHER bound; see below
# do_bisect's OUT-PARAMETER, and the reason it is not a stdout capture (2026-08-06) ────────────────
# `do_bisect` mints a worktree cell (via prepare_worktree) whose ONLY durable record is the global
# WT_MINTED, which the EXIT trap consults to tear the cell down. Both callers used to read the
# culprit as `$(do_bisect …)`, so that assignment landed in the command-substitution CHILD: it is
# neither exported back nor covered by the parent's trap, and cleanup_exit saw the pre-call value
# and removed NOTHING. A cell leaked on every invocation including SUCCESS, collected only by the
# 8h age reaper. Nothing failed and nothing alarmed — the run was green.
#
# Returning through a global removes the subshell, so the shell that RECORDS the mint is the shell
# that RUNS the trap, by construction. The tempting patch — have the caller set WT_MINTED itself —
# re-implements the minter's bookkeeping outside it and goes stale the moment the mint path changes.
#
# do_bisect deliberately no longer PRINTS the culprit: while it still did, `$(do_bisect …)` kept
# working and the next caller written that way would silently re-introduce the leak. Now that shape
# yields an empty string, which fails loudly at the caller instead of quietly on disk.
# Enforced by scripts/subshell-cleanup-lint.sh, whose positive control is this file's pre-fix blob.
BISECT_CULPRIT=""
# TWO bounds, because the wall above does not address the measured CAUSE. The 12h41m walk was not
# made of slow steps — every step was fast. The RANGE GREW: the bisected suite committed into
# $WORKTREE on each invocation, so new revisions kept entering the interval and the walk had no
# fixed point. A wall bound caps that damage without ever explaining it; a per-step bound would
# never have fired at all. Only a STEP COUNT names a walk that is not converging.
#
#   sizing — a healthy bisect is ceil(log2(range)) steps and postland's range is the landing
#   window, single digits. 24 allows 16M commits of slack and still makes an infinite walk
#   impossible, so it cannot cut a legitimate bisect short.
#
# THE TWO DO NOT SHARE A FAILURE MODE, which is the entire point of keeping both. `bounded`
# degrades to running UNBOUNDED when no timeout(1) resolves (see its definition), so on such a box
# BISECT_TO is INERT — while the step cap is plain bash inside the runner and still fires. The
# bound that answers the measured cause is the one that does not depend on an external binary.
#
# Safe to err SMALL, unlike every other bound in this file, and the reason is worth stating so
# nobody "fixes" it upward later: do_bisect runs AFTER the verdict is already RED. Cutting it loses
# the culprit NAME, never a verdict, so it cannot manufacture the permanent non-verdict that an
# undersized SUITE_TO/RETRY_TO would.
# ── BACKGROUND QoS — the singleton must make progress at ANY load (§4.2.3) ───────────────────────
# v1 admission control (gate_admit, DELETED) waited for load < ceiling before the suite and before
# every retry: ~2h of sleeping per run (backlog 60ec4c2d86d4), and with 5 concurrent gates each
# gate's own corpus WAS the load the others were waiting out — self-starvation below their own
# ceiling. Deleted rather than tuned: a shedder that WAITS amplifies (R7), and the verifier is the
# net, so it is the one party that may never be the thing that waits. Instead the corpus runs in
# Darwin's BACKGROUND band — nice 19 (scheduler) + `taskpolicy -c background` (throttled CPU *and*
# I/O tier, yields to interactive sessions). Wall time under load becomes DEPLOY LATENCY, never
# blockage. Seam: CC_POSTLAND_TASKPOLICY_BIN (set-but-EMPTY ⇒ nice alone, honored verbatim).
if [ -n "${CC_POSTLAND_TASKPOLICY_BIN+set}" ]; then TASKPOLICY_BIN="$CC_POSTLAND_TASKPOLICY_BIN"
else TASKPOLICY_BIN=/usr/sbin/taskpolicy; fi
if [ -n "$TASKPOLICY_BIN" ] && [ -x "$TASKPOLICY_BIN" ]; then
  QOS=(nice -n 19 "$TASKPOLICY_BIN" -c background)
else
  QOS=(nice -n 19)                             # absent taskpolicy(8) ⇒ nice alone, never a hard fail
fi
# PRELINT BAND — utility (PRI 20), deliberately NOT the corpus's background (PRI 4). The band above
# is right for the CORPUS (hours of bats; wall time is deploy latency, never blockage) and wrong for
# the prelints, which are ~3s whole-tree greps sitting on the critical path to a green stamp. The
# launchd job is ProcessType Background, so ABSENT AN EXPLICIT BAND they inherit PRI 4 (E-core
# confined) and their runtime becomes load-proportional. Measured on this box 2026-07-30, same tree,
# 218 suites: hermeticity 2.9s utility / 12.9s background @ load 9, and 41s background @ load 14.8;
# walltime 3.3s utility / 30.4s background. The repo's own instrumented figure for long batch work in
# that band is 84-89x (2514226e, which moved the actuators background→utility for exactly this
# reason). That is how a 3s lint blew the 60s bound below and logged "no green may be claimed"
# (runner.log 2026-07-30T15:41:31Z) — the bound never fit the band it was bounding.
# taskpolicy(8) sets a FRESH clamp on the CHILD, so utility IS reachable out of a background-clamped
# parent — verified directly (PRI 20 child of a `-c background` parent), and the exit codes the
# verdict/non-verdict split keys on (0/1/2/124) all pass through the timeout+taskpolicy chain intact.
# Seam: shares CC_POSTLAND_TASKPOLICY_BIN with QOS above (set-but-EMPTY ⇒ no band, honored verbatim).
if [ -n "$TASKPOLICY_BIN" ] && [ -x "$TASKPOLICY_BIN" ]; then
  LINT_QOS=("$TASKPOLICY_BIN" -c utility)
else
  LINT_QOS=()                                  # absent taskpolicy(8) ⇒ inherit; the bound still fits
fi
# RETRY BAND — utility, for the SAME reason as the prelints, and it was the third site of this same
# oversight (measured 2026-07-31). The ladder's premise is "a re-run under a CHANGED environment
# discriminates a real failure from an environmental one" (see classify_failures). It ran that re-run
# in the CORPUS's background band — which does not de-contend the re-run, it DE-PRIORITISES it, and
# that moves the environment in the WRONG DIRECTION for the failure mode that actually dominates
# here. The file's own evidence, one function below: of 35 flake rows, 34 are `pass-on-retry`/`1-of-3`
# and their signals are dominated by `exit 143` (x8) and `exit 137` (x3) at a median loadavg of 13.9
# — suites SIGTERMed/SIGKILLed by machine pressure. A ladder starved at PRI 4 therefore cannot render
# the verdict it exists to render: post the 2026-07-31 non-verdict widening those kills correctly
# ABSTAIN, so the run takes the cut path and NO GREEN IS EVER CLAIMABLE. The deadlock simply changed
# shape — from false RED to perpetual CUT — which is why 45 of 46 stamps carry no green.
#
# WHY THIS IS NOT THE C-DIRECTION RISK ("foreground the verifier"). The CORPUS stays background,
# unchanged: it is hours of bats and its wall time is deploy latency, never blockage. Only the
# ladder moves, and the ladder re-runs a SINGLE NAMED TEST (retry_once GRANULARITY=test, "costs
# seconds"). Elevating seconds of decision procedure is not the same act as foregrounding 233
# suites on a box that crashed twice in 48h.
#
# WHY IT DOES NOT WEAKEN THE CLAIM (the A-direction risk). Nothing here excuses a failure: a test
# that fails at utility priority is still convicted, and 2-of-3 still convicts. This removes a
# machine artefact from the evidence, it does not lower the bar for the tree — the opposite of
# gating on absence-of-RED.
#
# Mechanism is already verified in this file (see the LINT_QOS note): taskpolicy(8) sets a FRESH
# clamp on the CHILD, so utility is reachable out of a background-clamped parent, and the exit codes
# the verdict/non-verdict split keys on (0/1/124/>128) pass through the timeout+taskpolicy chain
# intact. Seam: shares CC_POSTLAND_TASKPOLICY_BIN (set-but-EMPTY ⇒ no band, honored verbatim).
if [ -n "$TASKPOLICY_BIN" ] && [ -x "$TASKPOLICY_BIN" ]; then
  RETRY_QOS=(nice -n 5 "$TASKPOLICY_BIN" -c utility)
else
  RETRY_QOS=(nice -n 5)                        # absent taskpolicy(8) ⇒ nice alone, never a hard fail
fi
# ── WHOLE-TREE META-LINTS, RUN STANDALONE BEFORE THE CORPUS ──────────────────────────────────────
# These two judge the tree AS A WHOLE (every suite's hermeticity; every suite's wall-clock literals).
# Their bats WRAPPERS are LOAD-SENSITIVE from inside a full run, which is why clean-room runs failed
# on exactly tests/test-hermeticity-lint.bats and nothing else (2,085/1, 2,242/1) and why the wrapper
# is now partitioned out to the host manifest. NOT, as this comment previously claimed, because "a
# whole-tree assertion evaluated mid-corpus sees a tree the corpus is concurrently using" — the
# corpus never mutates the tree (watched for a full run: zero *.bats changes). The real cause,
# reproduced 2026-07-29 under b4e49b4b5014: the lint's pure predicates ran a bare `grep -q`, so
# rc=2 (grep could not RUN — fork exhaustion at the measured load 15-48) was indistinguishable from
# rc=1 (no match), and one transient fork failure fabricated a LEAK about a clean tree. Fixed at the
# source by afaf40de + ed4e6c6a; the full account, with the RED-proof, is in scripts/host-suites.manifest.
# Deleting the wrapper from the tree verdict WITHOUT putting the check somewhere would silently drop
# the enforcement, so it lands here instead: the real lint, standalone, whole-tree-strict, once,
# before the corpus — off every lander's critical path, where a violation can no longer fleet-block
# a land but still cannot reach a green stamp. (Caveat recorded in the manifest: this preserves the
# whole-tree SCAN, not the `--selftest` discrimination proof, which the prelint never invokes.)
# STRICTNESS: the own-set seams are UNSET in the child (`${VAR+set}` is how both lints distinguish
# absent ⇒ judge the whole tree from set-but-empty ⇒ judge nothing), so an inherited own-set can
# never silently narrow the verifier's check to somebody else's diff.
# Seam: CC_POSTLAND_PRELINTS (space-separated, worktree-relative; set-but-EMPTY disables verbatim).
if [ -n "${CC_POSTLAND_PRELINTS+set}" ]; then
  # shellcheck disable=SC2206  # deliberate word-splitting: the seam is a space-separated list
  PRELINTS=($CC_POSTLAND_PRELINTS)
else
  PRELINTS=(scripts/test-walltime-lint.sh scripts/test-hermeticity-lint.sh scripts/git-identity-lint.sh scripts/subshell-cleanup-lint.sh)
fi
# 600s, raised from 60s (2026-07-30): a bound must fit what it BOUNDS, in the band it actually runs
# in. 60s was sized for a foreground ~3s lint and left no room for the band the launchd job imposes,
# so the whole-tree lint timed out and no green could be claimed — a deadlock the growing corpus
# (136→218 suites in four days) only tightened. The band fix above is the primary remedy; this is the
# belt: even with taskpolicy absent (LINT_QOS empty ⇒ background inherited) at the measured 84x tax,
# ~250s still fits with 2.4x headroom, while a genuinely WEDGED lint is still cut well inside
# SUITE_TO. Sized against its siblings, 60s was the lone foreground-scaled outlier here.
LINT_TO="${CC_POSTLAND_LINT_TIMEOUT_S:-600}"
PRELINT_UNPROVEN=0     # a lint whose own bound fired: nothing proven ⇒ never a red, never a green
LADDER_UNPROVEN=0      # a RETRY whose own bound fired: same rule — a cut, never a red (C23)
# ── AUTO-REVERT (§4.2.4) ─────────────────────────────────────────────────────────────────────────
AUTOREVERT="${POSTLAND_AUTOREVERT:-on}"                 # kill switch: POSTLAND_AUTOREVERT=off
MAX_REVERTS="${POSTLAND_MAX_REVERTS:-2}"                # markers written THIS run before we stop
REPO_SHIP="${CC_POSTLAND_SHIP_BIN:-$REPO/scripts/ship-land.sh}"   # the land lane (the ONLY pusher)
SHIP_TO="${CC_POSTLAND_SHIP_TIMEOUT_S:-900}"            # bound on the revert land
REVERTS="$STATE/reverts"                                # <sha> marker ⇒ never reverted twice
REVERTS_THIS_RUN=0
STAMPS="$STATE/stamps"
LOCK="$STATE/run.lock.d"
LOG="$STATE/runner.log"
FLAKES="$STATE/flakes.jsonl"
LASTGREEN="$STATE/last-green"
QUEUE="$STATE/queue"
CUTS="$STATE/cuts"                                     # "<tree> <consecutive-n> <epoch>"
CUT_MAX="${CC_POSTLAND_CUT_MAX:-3}"                    # consecutive cuts on one tree before paging
CUT_COOLOFF="${CC_POSTLAND_CUT_COOLOFF:-1800}"         # ...and before the box is fed another suite

# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea, 2026-08-06) ───────────────────────────────────
# sysctl lives in /usr/sbin, and this job's plist wrapper EXPORTS a PATH ending /usr/bin:/bin — no
# /usr/sbin. So a bare `sysctl` resolved fine from a terminal and did not exist in any SCHEDULED
# run, which is exactly why it survived review. Measured on this machine's own stamps: 34 of 80
# carried "load":"0" — the load was never read, and `${l:-0}` rendered the unreadable instrument as
# an IDLE machine. Same shape as the swap rung in tests/capacity-alarm-launchd-path.bats.
#
# Fixed SCRIPT-SIDE rather than by adding /usr/sbin to the plist, following the precedent this
# repo already set for the identical class (e6de2e15 cc-authbrowser/git-worktree-guard, 752024be
# handoff-fire, 9ac045cb team-orphan-reaper's lsof): a plist-only edit would break
# launchd-parity-lint assertion (c) — live `plutil -p` vs repo SSOT — for every session in the
# fleet, staying red pending an operator reload, and it would still leave every NON-launchd caller
# (the nightly, a hand-run, the disposable verify worktree) reading a bare name.
#
# ABSOLUTE FIRST, bare name only as the fallback: this must not depend on the caller's PATH at all.
# Seam: CC_POSTLAND_SYSCTL_BIN — set-but-EMPTY is honored verbatim (i.e. no sysctl), because a seam
# that cannot turn the probe OFF cannot test the unreadable direction. The override is NOT folded
# into the fallback list, which is how an override stops being one (memory
# path-resolved-dependency-in-daemon-code).
if [ -n "${CC_POSTLAND_SYSCTL_BIN+set}" ]; then
  SYSCTL_BIN="$CC_POSTLAND_SYSCTL_BIN"
elif [ -x /usr/sbin/sysctl ]; then
  SYSCTL_BIN=/usr/sbin/sysctl
else
  SYSCTL_BIN="$(command -v sysctl 2>/dev/null || true)"
fi
load1() { # 1-min loadavg on stdout, or EMPTY when the instrument cannot be read at all
  [ -n "$SYSCTL_BIN" ] && [ -x "$SYSCTL_BIN" ] || return 0
  "$SYSCTL_BIN" -n vm.loadavg 2>/dev/null | awk '{print $2}'
}

FAILING=(); SYNTAX_BAD=(); RETRIES=0; NFLAKE=0; FAILTEST=""; RUN_TMP=""; IDL_DONE=0; ENV_FP='{}'; CUT=0
# Suites actually handed to bats. 0 is not a filler default — it is the honest value on every path
# where the corpus never ran (a prelint red SKIPS it), and the stamp should say so.
CORPUS_N=0
# WHY the cut fired, in the CUT log line. Default names case (a); case (c) overwrites it. A fixed
# string here would have the log assert "zero not-ok" about a run that carried one — see C13c.
CUT_WHY='zero not-ok in a non-zero run - truncated'
CORPUS_LIST=""       # the ONE ordered TREE-corpus list (see build_corpus) — bats runs exactly this
HOST_SKIPPED=0       # how many suites the host manifest partitioned OUT of the tree verdict
# ── hang evidence (reset per run_target) ─────────────────────────────────────────────────────────
DEATH_SIG=""         # sig:9 | timeout:2700s | exit:1 — what ended the run
WEDGE_AT=""          # "<completed>/<planned>" at the moment it stopped making progress
SUSPECT=""           # tests/<file>.bats the run wedged IN (best effort — see the CONFIRM note)
REPRODUCED=false     # did the suspect file wedge AGAIN, alone, in this pristine worktree?

now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }
ensure_dirs() { mkdir -p "$STAMPS" "$PAGES" "$(dirname "$IDL")" 2>/dev/null || true; }
log() { printf '%s postland-verify: %s\n' "$(now_iso)" "$1" >> "$LOG" 2>/dev/null || true; }

# ONE IDL line per invocation (guarded) — the abstention monitor reads this file.
idl() { # <fired|abstained> <reason> [sha]
  [ "$IDL_DONE" = 1 ] && return 0
  IDL_DONE=1
  printf '{"ts":"%s","check":"postland-verify","decision":"%s","reason":"%s","sha":"%s"}\n' \
    "$(now_iso)" "$1" "$2" "${3:-}" >> "$IDL" 2>/dev/null || true
}
notify() { # <title> <msg> — OS-level, API-independent
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$1" "$2" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    plv_osa osascript -e "display notification \"${2//\"/}\" with title \"${1//\"/}\"" >/dev/null 2>&1 || true
}
json_array() { local out="" i; for i in "$@"; do out="$out,\"$i\""; done; printf '[%s]' "${out#,}"; }
sha12() { printf '%s' "$1" | cut -c1-12; }
tree_of() { git -C "$REPO" rev-parse "$1^{tree}" 2>/dev/null; }
env_fingerprint() { # sets ENV_FP — a verdict is NOT a pure function of the tree (tool bumps happen
  local b c l                                # constantly), so a stale-env green stamp stays diagnosable
  b="$("$BATS_BIN" --version </dev/null 2>/dev/null | awk '{print $2}')"
  c="${CLAUDE_CODE_EXECPATH:-}"; [ -n "$c" ] && c="$(basename "$c")" || c=unknown
  l="$(load1)"                                                               # 1-min, at run start
  # `?`, never `0`: an unread instrument must not render as a value the reader would call healthy.
  # qos-census's loadavg1 column already answers this way; the stamp now agrees with it.
  ENV_FP="$(printf '{"bats":"%s","cc":"%s","load":"%s"}' "${b:-unknown}" "${c:-unknown}" "${l:-?}")"
}

# ════ mutex — shape copied from land-lock.sh (a LIVE holder is never reaped; dead pid → instant) ═══
try_acquire() {
  mkdir "$LOCK" 2>/dev/null && { printf '%s\n' "$$" > "$LOCK/pid"; return 0; }
  local holder age stale
  holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
  age="$(( $(now_epoch) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))"
  stale=0
  if [ -z "$holder" ]; then { [ "$age" -ge 5 ] || [ "$age" -gt "$LOCK_TTL" ]; } && stale=1
  elif kill -0 "$holder" 2>/dev/null; then stale=0     # holder ALIVE → NEVER reaped (wait it out)
  else stale=1; fi                                     # holder pid DEAD → reap immediately
  if [ "$stale" = 1 ]; then
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null && { printf '%s\n' "$$" > "$LOCK/pid"; return 0; }
  fi
  return 1
}
# shellcheck disable=SC2329  # invoked indirectly, from cleanup_exit (the EXIT trap)
release_lock() {
  [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ] && rm -rf "$LOCK"
  [ -n "$RUN_TMP" ] && rm -rf "$RUN_TMP"
  return 0
}
# THE exit handler. One function, so no verb can install a trap that drops half the cleanup — a
# minted worktree that outlives its run is disk that only ever grows, and (worse) the next run's
# `worktree add` collides with it. Installed in main() for every verb and re-installed by the
# verbs that also hold the mutex (same handler ⇒ re-installing is a no-op, never a lost trap).
# shellcheck disable=SC2329  # invoked indirectly: `trap cleanup_exit EXIT`
cleanup_exit() { release_lock; teardown_worktrees; return 0; }

# ════ disposable worktree — FRESH PER RUN (§4.2.1) ════════════════════════════════════════════════
wt_remove() { # <path> — git-aware removal, then belt-and-braces rm. Only ever called on a path THIS
  # process minted (WT_MINTED / WT_REVERT) or found under $WT_ROOT matching the mint pattern.
  local p="${1:-}"
  [ -n "$p" ] || return 0
  [ "$p" != "/" ] || return 0
  bounded 60 git -C "$REPO" worktree remove --force "$p" >/dev/null 2>&1 || true
  [ -e "$p" ] && rm -rf "$p" 2>/dev/null
  bounded 60 git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  return 0
}
# shellcheck disable=SC2329  # invoked indirectly, from cleanup_exit (the EXIT trap)
teardown_worktrees() {
  [ -n "$WT_MINTED" ] && { wt_remove "$WT_MINTED"; WT_MINTED=""; }
  [ -n "$WT_REVERT" ] && { wt_remove "$WT_REVERT"; WT_REVERT=""; }
  return 0
}
reap_stale_worktrees() { # bounded disk: a run KILLED mid-suite never runs its trap, so its cell
  # survives. Reaped by AGE on entry (once per process) — never by pid, which a recycled pid makes
  # a lie, and never by "is it mine", which is exactly the cell a crash leaves unclaimed.
  local d mins
  [ "$WT_REAPED" = 0 ] || return 0
  WT_REAPED=1
  [ -d "$WT_ROOT" ] || return 0
  mins=$(( $(int_or_zero "$WT_STALE_S") / 60 )); [ "$mins" -ge 1 ] || mins=1
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ "$d" = "$WORKTREE" ] && continue                    # never our own live cell
    log "reaping stale worktree cell $d (idle > ${mins}m)"
    wt_remove "$d"
  done <<EOF
$(find "$WT_ROOT" -maxdepth 1 -type d \( -name 'wt-run-*' -o -name 'wt-revert-*' \) -mmin "+$mins" 2>/dev/null | sort)
EOF
  return 0
}
prepare_worktree() { # <sha> — MINT a fresh detached cell at <sha>; any cell we already hold is removed
  local sha="$1" wtp repop par
  reap_stale_worktrees
  wt_remove "$WT_MINTED"; WT_MINTED=""          # a second run_target/bisect in one process re-mints
  par="$(dirname "$WORKTREE")"
  mkdir -p "$par" 2>/dev/null || true
  wtp="$( (cd "$par" 2>/dev/null && pwd -P) || printf '%s' "$par" )/$(basename "$WORKTREE")"
  repop="$(cd "$REPO" 2>/dev/null && pwd -P || printf '%s' "$REPO")"
  # the load-bearing guard: never check in $REPO (its working tree is the LIVE ~/.claude layer)
  [ "$wtp" = "$repop" ] && { log "REFUSED: worktree resolves to the live repo ($repop)"; return 1; }
  rm -rf "$WORKTREE" 2>/dev/null || true        # residue at our own path (crashed predecessor)
  bounded 60 git -C "$REPO" worktree prune >/dev/null 2>&1 || true
  bounded 120 git -C "$REPO" worktree add --detach "$WORKTREE" "$sha" >/dev/null 2>&1 || {
    log "worktree MINT failed at $WORKTREE for $(sha12 "$sha")"; return 1; }
  WT_MINTED="$WORKTREE"
  return 0
}
shell_files() { # tracked *.sh + bash/sh-shebang files, worktree-relative
  local f first
  while IFS= read -r f; do
    [ -f "$WORKTREE/$f" ] || continue
    case "$f" in *.sh) printf '%s\n' "$f"; continue ;; esac
    first="$(head -1 "$WORKTREE/$f" 2>/dev/null)"
    case "$first" in '#!'*bash*|'#!'*/sh|'#!'*env\ sh) printf '%s\n' "$f" ;; esac
  done <<EOF
$(git -C "$WORKTREE" ls-files 2>/dev/null)
EOF
}
syntax_check() { # bash -n — cheap and verdict-affecting
  local f
  SYNTAX_BAD=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    bash -n "$WORKTREE/$f" 2>/dev/null || SYNTAX_BAD+=("$f")
  done <<EOF
$(shell_files)
EOF
}
prelint_check() { # whole-tree meta-lints, standalone, BEFORE the corpus. Appends any RED to FAILING
  # (so it flows through the existing verdict chain: FAILING non-empty ⇒ RED, and it OUTRANKS a cut
  # — which is the point, a deterministic named violation must never be filed as "nothing proven").
  local s rc out first why
  PRELINT_UNPROVEN=0                        # reset BEFORE the early return — the requeue loop
  [ "${#PRELINTS[@]}" -eq 0 ] && return 0   # calls run_target twice in one process
  for s in "${PRELINTS[@]}"; do
    [ -n "$s" ] || continue
    # ABSENT from this tree ⇒ skipped, never red: a tree cannot be judged by a check it does not
    # carry (an older sha predates the lint, and convicting it would make history unverifiable).
    [ -x "$WORKTREE/$s" ] || { log "prelint: $s absent from this tree — skipped"; continue; }
    out="$RUN_TMP/prelint.$(basename "$s").out"
    # `unset` inside the subshell, NOT `env -u`: env execs a binary and could never run the
    # `bounded` FUNCTION, which has to stay the outer call so the bound owns the process group.
    # `${LINT_QOS[@]+"${LINT_QOS[@]}"}` — NOT a bare "${LINT_QOS[@]}": this is bash 3.2 under `set -u`,
    # where expanding an EMPTY array unguarded is an unbound-variable death (the taskpolicy-absent
    # path). QOS above needs no such guard because it is never empty.
    # NO POSITIONAL ARG — each lint resolves its OWN scan root from its own $0. This used to pass a
    # literal `tests`, which was correct only because both lints then in the list happen to default to
    # `${1:-$ROOT/tests}`, i.e. the argument re-stated their default. git-identity-lint does not scan a
    # corpus dir — it defaults to `${1:-$ROOT}` and walks tests/ + scripts/ + bin/, because bin/ and
    # scripts/ carry real identity writes. Handing IT `tests` makes it look for tests/tests, tests/scripts
    # and tests/bin, find nothing, and exit 2 = NON-VERDICT — which prelint_check below turns into
    # PRELINT_UNPROVEN, so EVERY run would become a CUT and no tree could ever be stamped green again.
    # Measured before wiring: `git-identity-lint.sh tests` → exit 2 "nothing to scan"; no arg → exit 0,
    # 490 files, clean. The other two are unchanged by this: verified exit 0 both with and without it.
    ( cd "$WORKTREE" && unset CC_HERM_OWN CC_WALLTIME_OWN SHIP_LAND_HERM_OWN_SCOPE
      bounded "$LINT_TO" ${LINT_QOS[@]+"${LINT_QOS[@]}"} "./$s" ) > "$out" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && { log "prelint: $s clean (whole-tree strict)"; continue; }
    # THE VERDICT / NON-VERDICT SPLIT — exit 1 is the ONLY code that says anything about the tree.
    # Both lints publish the same contract (`0 clean · 1 violation · 2 unusable, LOUD`), so every
    # other code means the check could not be MADE: 2 = a predicate that would not run (the
    # fork-pressure case afaf40de carved out INSIDE the lint, measured at load 15-48), 124 = our
    # own bound, 126/127 = not executable, 137 = killed. Filing any of those as FAILING re-creates one
    # layer out precisely the conflation afaf40de removed, and it is STRICTLY WORSE here: a prelint
    # RED reaches red_actions, so a check that never ran can auto-revert a commit never shown to be
    # at fault. Backlog b4e49b4b5014 is the reproduction — a transient `grep` rc=2 made the pre-fix
    # lint fabricate "the embedded allowlist is stale" and name three clean suites as LEAKs, and the
    # same suite's failure was recorded `pass-on-retry` at loadavg 17.38. Unproven is not silent:
    # FAILING stays empty ⇒ CUT ⇒ the CUT_MAX page ladder, and no green may be claimed either.
    if [ "$rc" -ne 1 ]; then
      PRELINT_UNPROVEN=1
      # Quote the lint's own first line INTO the log rather than pointing at $out: $RUN_TMP is
      # removed when run_target returns, so a "see <path>" breadcrumb is dead by the time anyone
      # reads this. Same reason the RED path lifts `first` into FAILTEST.
      why="$(grep -aE '⛔|✗|UNUSABLE|could not' "$out" 2>/dev/null | head -1 | cut -c1-160)"
      [ -n "$why" ] || why="$(sed -n '1p' "$out" 2>/dev/null | cut -c1-160)"
      case "$rc" in
        124) log "prelint: $s hit OUR ${LINT_TO}s bound — nothing proven (not a red, and no green may be claimed)" ;;
        2)   log "prelint: $s exit 2 NON-VERDICT — its own check could not run; not a red, no green claimable — ${why:-（no output)}" ;;
        *)   log "prelint: $s exit $rc — unexpected, treated as a NON-VERDICT; not a red, no green claimable — ${why:-（no output)}" ;;
      esac
      continue
    fi
    FAILING+=("$s")
    first="$(grep -aE '^[[:space:]]*(RATCHET|LEAK|⛔|✗)' "$out" 2>/dev/null | head -1 | cut -c1-120)"
    [ -n "$first" ] || first="$(sed -n '1p' "$out" 2>/dev/null | cut -c1-120)"
    [ -n "$FAILTEST" ] || FAILTEST="${first:-whole-tree lint exit $rc}"
    log "prelint RED: $s exit $rc — ${first:-（no output)}"
  done
  [ "${#FAILING[@]}" -eq 0 ]
}
# ── SHARED-CONFIG INTEGRITY ──────────────────────────────────────────────────────────────────────
# The DYNAMIC half of the git-identity fix; scripts/git-identity-lint.sh is the static half, and this
# exists because that one cannot be complete. The lint reads SOURCE, so it is blind to any identity
# write that arrives by a route it does not scan — a suite landing between prelint and corpus, a
# helper reached through a variable, a fixture generated at runtime, or the agent-typed one-liner the
# lint's own header disclaims. This reads the actual config, so it convicts on EFFECT rather than on
# shape, and the two together are what make the class closed.
#
# It ASSERTS rather than merely cleaning, and that is the whole design. A bare `config --unset-all` in
# the exit trap would have kept the operator's repo tidy through all 12h41m of the 2026-08-05 runaway
# and reported NOTHING — the corruption was silent precisely because every consumer only ever read the
# current value. Restoring as well is strictly better than either alone: the repo comes back AND the
# run goes red, so the cause still gets found.
#
# Side-car discipline (memory: addon-failure-exceeds-its-blast-radius): this may never fail wider than
# itself. Every git call is best-effort, an unreadable snapshot means "cannot judge" and stays silent
# rather than fabricating a red, and only a genuine non-empty DIFFERENCE convicts.
identity_snapshot() { git -C "$REPO" config --local --get-regexp '^user\.' 2>/dev/null | sort || true; }
identity_assert() {  # compare against $IDENTITY_SNAP, restore it, and convict on any change
  local now line k v
  [ -n "${IDENTITY_SNAP+set}" ] || return 0        # never snapshotted ⇒ nothing to compare against
  now="$(identity_snapshot)"
  [ "$now" = "$IDENTITY_SNAP" ] && return 0
  log "IDENTITY LEAK: the corpus mutated $REPO local [user] during this run — was [${IDENTITY_SNAP:-absent}] now [${now:-absent}]"
  git -C "$REPO" config --local --remove-section user >/dev/null 2>&1 || true
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    k="${line%% *}"; v="${line#* }"
    git -C "$REPO" config --local "$k" "$v" >/dev/null 2>&1 || true
  done <<EOF
$IDENTITY_SNAP
EOF
  [ "$(identity_snapshot)" = "$IDENTITY_SNAP" ] \
    && log "IDENTITY LEAK: $REPO local [user] restored to its run-start value" \
    || log "IDENTITY LEAK: restore did NOT converge — $REPO local [user] needs a human"
  FAILING+=("shared-config-identity")
  [ -n "$FAILTEST" ] || FAILTEST="a suite wrote git user.* into $REPO (empty -C, or an unguarded cd)"
  return 0
}
sc_count() { # whole-tree lint finding count — ADVISORY, never verdict-affecting
  command -v shellcheck >/dev/null 2>&1 || { printf '0\n'; return 0; }
  ( cd "$WORKTREE" && shell_files | tr '\n' '\0' | xargs -0 shellcheck -f gcc 2>/dev/null ) | grep -c ':'
}
record_flake() { # <file> <test> <rc>
  local sig load
  if [ "$3" -gt 128 ]; then sig="sig:$(( $3 - 128 ))"; else sig="exit:$3"; fi
  # The SECOND site of the same bare-name defect, and the one that matters most: this column is how
  # a flake is later adjudicated as machine-pressure vs a real red (see the median-loadavg reasoning
  # at the HUNG/cut notes below). Recorded `0` it reads as "flaked on an idle box" — the opposite
  # conclusion. `?` says the load is unknown, which is the truth when sysctl cannot be reached.
  load="$(load1)"
  printf '{"ts":"%s","file":"%s","test":"%s","sha":"%s","phase":"postland","outcome":"1-of-3","signal":"%s","loadavg":"%s"}\n' \
    "$(now_iso)" "$1" "$2" "${CUR_SHA:-}" "$sig" "${load:-?}" >> "$FLAKES" 2>/dev/null || true
  NFLAKE=$((NFLAKE+1))
}
# ════ HUNG — the one state a CUT cannot express ═══════════════════════════════════════════════════
# A CUT says "the run was truncated, nothing was proven, retry next sweep". That is exactly right for
# a peer's pkill, an OOM, or load starvation — a MACHINE event: unactionable, self-clearing, and its
# own honest page names no test. It is exactly WRONG for a suite that simply never returns. That is a
# property OF THE TREE (an un-stubbed external seam), it reproduces on a quiet box, and retrying it
# every sweep forever is the precise opposite of the right response — the tree is never verified and
# the box burns a full suite per tick on it. So HUNG is carved OUT of the cut population as a real
# verdict: stamped (the tree is decided), paged at the FILE that wedged, routed to the seam owner.
# Everything else that reaches here stays a CUT, with trunk's ledger and cool-off untouched.
int_or_zero() { case "${1:-}" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }
tap_plan() { # <tap> → N from the `1..N` plan line (0 when it never even planned)
  int_or_zero "$(sed -n 's/^1\.\.\([0-9][0-9]*\).*$/\1/p' "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_done() { # <tap> → completed tests. bats emits `ok`/`not ok` only AFTER a test returns, so this
  # is exactly "how far did it get". (`grep -c` prints 0 AND exits 1 on no-match — never `|| printf 0`.)
  int_or_zero "$(grep -acE '^(ok|not ok) [0-9]+' "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_signal() { # <tap> → the job-control death line, if the shell printed one. `# `-prefixed lines
  # are a TEST'S OWN captured output (this repo has reaper/kill suites that print those very words),
  # so they are excluded — the needle is the shell's `Killed: 9` / `Terminated: 15` shape. Needed
  # because bats can OUTLIVE the child it lost and exit 1, so rc alone never sees that signal.
  grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$1" 2>/dev/null | head -1 \
    | grep -oE '(Killed|Terminated): *[0-9]+' | head -1 | tr -d '\n'
}
# ════ TREE vs HOST corpus partition (§4.2.2) ══════════════════════════════════════════════════════
# Some suites assert the LIVE DEPLOYED layer (~/.claude), not the tree. Running them here is the
# bootstrap circle: the tree under test is by definition ahead of what is deployed, so they can only
# pass AFTER a deploy — and the deploy waits on this verdict. 22 stamps, 0 green ever. v2 partitions
# them out by SET DIFFERENCE against scripts/host-suites.manifest (total by construction, never
# hand-synced), and deploy-live.sh runs exactly the manifest set POST-deploy, against its real
# subject. The manifest travels WITH THE TREE (read from the worktree), so a suite changes sides by
# a one-line land and the verdict for a given tree is reproducible from that tree alone.
# CONTRACT (frozen for the deploy lane): plain text, one `tests/<name>.bats` per line, `#` comments;
# a MISSING manifest ⇒ empty ⇒ everything runs (fail-closed toward MORE proof, never less);
# an unreadable line ⇒ ignored + logged, never a silent partial partition.
MANIFEST_REL="scripts/host-suites.manifest"
manifest_path() { # CC_POSTLAND_MANIFEST set-but-EMPTY disables the partition verbatim
  if [ -n "${CC_POSTLAND_MANIFEST+set}" ]; then printf '%s' "$CC_POSTLAND_MANIFEST"
  else printf '%s' "$WORKTREE/$MANIFEST_REL"; fi
}
manifest_excludes() { # → "|tests/a.bats|tests/b.bats|" (empty when there is nothing to exclude)
  local mf line out=""
  mf="$(manifest_path)"
  [ -n "$mf" ] && [ -f "$mf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                                   # trailing/whole-line comment
    line="${line#"${line%%[![:space:]]*}"}"              # ltrim
    line="${line%"${line##*[![:space:]]}"}"              # rtrim
    [ -n "$line" ] || continue
    case "$line" in
      tests/*.bats) out="$out|$line" ;;
      *) log "manifest: ignoring unreadable line '$line'" ;;
    esac
  done < "$mf"
  [ -n "$out" ] && printf '%s|' "$out"
  return 0
}
build_corpus() { # sets CORPUS_LIST — worktree-relative, in the order bats will run it. THE single
  # list: the bats argv and suite_file_at's index→file mapping are both derived from it, so the
  # partition can never desynchronise the two (a suspect named from a re-expansion of `tests/`
  # would be off by however many suites the manifest removed).
  local excl f rel
  excl="$(manifest_excludes)"
  CORPUS_LIST=""; HOST_SKIPPED=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$WORKTREE"/}"
    case "$excl" in *"|$rel|"*) HOST_SKIPPED=$((HOST_SKIPPED+1)); continue ;; esac
    CORPUS_LIST="$CORPUS_LIST$rel
"
  done <<EOF
$(find -L "$WORKTREE/tests" -type f -name '*.bats' 2>/dev/null | sort)
EOF
  return 0
}
suite_files() { # the corpus in the order bats runs it — bats' OWN expansion order (bats:480 is
  # `find -L … -type f -name "*.bats" -print0 | sort -z`; no test filename here contains a newline,
  # so the line-delimited form is byte-equivalent and stays readable), minus the host manifest.
  [ -n "$CORPUS_LIST" ] && printf '%s' "$CORPUS_LIST"
  return 0
}
suite_file_at() { # <1-based test index> → tests/<file>.bats (empty when unmappable)
  local want="$1" f n acc=0
  case "$want" in ''|*[!0-9]*) return 1 ;; esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n="$(int_or_zero "$( (cd "$WORKTREE" && bounded 20 "$BATS_BIN" --count "$f") </dev/null 2>/dev/null | tr -d '\n')")"  # parses, never executes
    acc=$(( acc + n ))
    if [ "$want" -le "$acc" ]; then printf '%s\n' "$f"; return 0; fi
  done <<EOF
$(suite_files)
EOF
  return 1
}
confirm_hang() { # <suspect-file> — THE clean discriminator: the file, ALONE, bounded, right here in
  # the pristine detached worktree. 0 = it wedged again (HUNG); 1 = it completed, so the wedge was
  # environmental and we refuse to invent a verdict from it.
  local rc=0
  # `bounded` is a FUNCTION, so it must be the outer call — the QoS prefix execs a binary and could
  # never run it. timeout-then-QoS also keeps the bound owning the process group.
  ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" bounded "$FILE_TO" "${QOS[@]}" "$BATS_BIN" "$1" ) </dev/null >/dev/null 2>&1 || rc=$?
  RETRIES=$((RETRIES+1))
  [ "$rc" -eq 124 ]
}
classify_hang() { # <tapfile> <rc> — 0 = HUNG (sets SUSPECT/WEDGE_AT/DEATH_SIG/REPRODUCED), 1 = CUT
  local tap="$1" rc="$2" plan ndone sig
  plan="$(tap_plan "$tap")"; ndone="$(tap_done "$tap")"; sig="$(tap_signal "$tap")"
  WEDGE_AT="$ndone/$plan"; SUSPECT=""; REPRODUCED=false
  # (1) OUR bound. FIRST, and the ordering is the whole point: timeout(1) SIGTERMs the group, so a
  #     hang's own TAP carries `Terminated: 15` — a signal-first ladder files every hang as a kill.
  if [ "$rc" -eq 124 ]; then DEATH_SIG="timeout:${SUITE_TO}s"
  # (2)/(3) an EXTERNAL signal — either straight through as rc-128, or seen only in the TAP because
  #     bats outlived the child it lost. Either way a MACHINE event ⇒ trunk's CUT, not a hang.
  elif [ "$rc" -gt 128 ]; then DEATH_SIG="sig:$(( rc - 128 ))"; return 1
  elif [ -n "$sig" ]; then DEATH_SIG="${sig// /}"; return 1
  # (4) it planned and then completed NOTHING, with nobody to blame — fe21305312ec's signature.
  elif [ "$plan" -gt 0 ] && [ "$ndone" -eq 0 ]; then DEATH_SIG="exit:$rc"
  # (5) neither shape fits ⇒ undecidable, which is what a CUT already says honestly.
  else DEATH_SIG="exit:$rc"; return 1
  fi
  SUSPECT="$(suite_file_at "$(( ndone + 1 ))" 2>/dev/null || true)"
  if [ -n "$SUSPECT" ]; then
    # CONFIRM. A mis-mapped suspect can therefore only LOSE a hang (it degrades to a CUT and is
    # retried), never invent one — the failure mode we can afford.
    if confirm_hang "$SUSPECT"; then REPRODUCED=true; return 0; fi
    DEATH_SIG="$DEATH_SIG/not-reproduced"; SUSPECT=""; return 1
  fi
  # Unmappable suspect. Our own bound firing is still direct evidence the run never returned, so
  # HUNG stands — flagged unreproduced, because nothing was re-run to prove it. Without the bound
  # (CC_POSTLAND_TIMEOUT_BIN=) nothing can ever return 124, so a hang is simply unprovable and
  # degrades to a CUT: no bound, no hang verdict. We never fabricate one.
  [ "$rc" -eq 124 ]
}
retry_once() { # <file> <testname> <tmpdir> → rc of ONE re-run (124 = OUR bound ⇒ decides nothing)
  # GRANULARITY: the failing TEST, not the whole FILE (POSTLAND_RETRY_GRANULARITY=file restores the
  # file-wide re-run). A bound the re-run cannot fit inside is not a bound, it is a verdict — see the
  # RETRY_TO block above. Re-running only the named test costs seconds, so the ladder can DECIDE for a
  # heavy suite instead of timing out and calling that a failure. Trade-off, stated rather than hidden:
  # an INTRA-file ordering dependence now reads as a flake rather than a red. The ladder already
  # dropped cross-FILE ordering by re-running the file alone; this widens that same assumption by one
  # level, and a suite that can never be exonerated (0 green in 33 stamps) is the worse failure.
  local f="$1" t="$2" td="$3" rc=0 out filt
  if [ "${POSTLAND_RETRY_GRANULARITY:-test}" = "test" ] && [ -n "$t" ]; then
    out="$td/tap"
    # `bats -f` takes a REGEX: escape every metachar in the TAP-reported name, then anchor it.
    filt="$(printf '%s' "$t" | sed 's/[][\\.^$*+?(){}|\/]/\\&/g')"
    ( cd "$WORKTREE" && TMPDIR="$td" bounded "$FILE_TO" "${RETRY_QOS[@]}" \
        "$BATS_BIN" -f "^${filt}\$" "$f" ) </dev/null > "$out" 2>&1 || rc=$?
    # A filter that matched NOTHING exits 0 with `1..0` — a NON-VERDICT that would exonerate the file
    # for free. Only trust this run if it actually PLANNED a test; otherwise fall through to the file.
    [ "$(tap_plan "$out")" -gt 0 ] && { rm -f "$out"; return "$rc"; }
    rm -f "$out"; rc=0
  fi
  # FALLBACK: the whole file, under the bound sized for a whole file.
  ( cd "$WORKTREE" && TMPDIR="$td" bounded "$RETRY_TO" "${RETRY_QOS[@]}" "$BATS_BIN" "$f" ) </dev/null >/dev/null 2>&1 || rc=$?
  return "$rc"
}
classify_failures() { # <tapfile> <rc> — retry ladder: >=2/3 = REPRODUCIBLE, 1/3 = flake, 124 = no verdict
  # <rc> is the CORPUS run's exit code, and it is load-bearing for case (c) below: without it this
  # function cannot tell a failure of the tree from a run we killed ourselves. Defaults to 1 (bats'
  # "something failed") so an omitted argument can only ever preserve the old convicting behaviour,
  # never invent a cut.
  local pairs f t rc i tdir fails notok abstain ABSTAIN_RC arc why tap_rc="${2:-1}"
  # TAP: `not ok N <name>` followed by a `# (in test file tests/X.bats, line N)` diagnostic.
  pairs="$(awk '/^not ok /{p=1; n=$0; sub(/^not ok [0-9]+ /,"",n); next}
                /^#/ && p { if (match($0, /[A-Za-z0-9_.\/-]+\.bats/)) { print substr($0,RSTART,RLENGTH) "\t" n; p=0 } }' "$1" \
             | awk -F'\t' '!seen[$1]++')"
  if [ -z "$pairs" ]; then
    # CUT ≠ RED. No attributable pair has TWO causes, and they need opposite handling:
    #   (a) the TAP contains ZERO `not ok` at all  ⇒ the run was TRUNCATED (killed / starved),
    #       so nothing failed — stamping it red is a LIE, and a costly one: the red stamp is
    #       what `deploy-live.sh` and `ship-land.sh:postland_net_live` read. With every run
    #       cut, NO GREEN STAMP CAN EVER EXIST, so deploy-live refuses forever ("no GREEN
    #       stamp among the newest 200 commits") and the liveness guard silently reads
    #       "net not adopted ⇒ trust". Verified 2026-07-26: 4 of the last 5 runner.log
    #       verdicts were `failing=tests/ retries=0` — i.e. all four were cuts, not reds.
    #   (b) `not ok` lines exist but carry no `# (in test file …)` diagnostic ⇒ a GENUINE red
    #       we merely cannot attribute to a file. It stays RED — see C13b — but ONLY when the rc
    #       is bats speaking about the tree; see (c).
    #   (c) the SAME shape as (b) in a run that never returned a verdict at all (C13c). bats
    #       answers with exactly TWO codes about the tree: 0 = all passed, 1 = something failed.
    #       Every other code says the run could not be MADE — 124 is OUR bound, >128 is a machine
    #       signal, 126/127 could not execute — so an unattributable `not ok` inside one is not
    #       evidence about the tree, and (b) must not convict on it. This was the LAST rc-blind
    #       site in the file; C23 already applies this identical predicate one function below, and
    #       C22/confirm_hang/classify_hang/the stall unify all apply it too. MEASURED: runner.log
    #       2026-07-30T06:04:21Z stamped `RED 4399852f21c2 failing=tests/ retries=0` 41s after its
    #       own `STALL … at test 0 — cutting the run`, minting a backlog item that pointed at a
    #       DIRECTORY. `retries=0` is the tell — (b) returns before the ladder can run.
    notok="$(grep -c '^not ok' "$1" 2>/dev/null || true)"; notok="${notok:-0}"
    if [ "$notok" -eq 0 ]; then CUT=1; return 0; fi
    case "$tap_rc" in
      0|1) ;;                                   # the only two codes that speak about the tree
      *)   CUT=1                                # 124 / >128 signal / 126 / 127 ⇒ nothing proven
           FAILTEST="$(sed -n 's/^not ok [0-9]* //p' "$1" 2>/dev/null | head -1 | cut -c1-120)"
           [ -n "$FAILTEST" ] || FAILTEST="(unattributed)"
           # Name WHICH non-verdict fired, for the same reason C23 does: a fixed message would
           # misattribute a SIGKILL to our timeout and send the next reader hunting a slow test.
           if   [ "$tap_rc" -eq 124 ]; then why="our own bound cut the run"
           elif [ "$tap_rc" -gt 128 ]; then why="the run was KILLED by signal $(( tap_rc - 128 )) (machine pressure, not the tree)"
           elif [ "$tap_rc" -eq 126 ] || [ "$tap_rc" -eq 127 ]; then why="the run could not execute (rc $tap_rc)"
           else why="the run exited $tap_rc — not a tree verdict (bats says 0=pass, 1=fail)"
           fi
           CUT_WHY="unattributable not-ok (${FAILTEST}) in a run that reached no verdict — $why"
           log "corpus UNPROVEN — $why; the one unattributable not-ok proves nothing (cut, not red)"
           return 0 ;;
    esac
    # NAME-CARRY (b): TAP names the TEST on the `not ok` line even when it never names the
    # FILE. Recording the opaque "(unattributed)" threw that name away, leaving a page that
    # reads exactly like the signal-death case (a) it was just separated from — the operator
    # cannot tell "a real failure we could not attribute" from "no verdict at all", which is
    # the whole distinction this branch exists to draw. Keep the sentinel only as a fallback.
    FAILING=("tests/")
    FAILTEST="$(sed -n 's/^not ok [0-9]* //p' "$1" 2>/dev/null | head -1 | cut -c1-120)"
    [ -n "$FAILTEST" ] || FAILTEST="(unattributed)"
    return 0
  fi
  while IFS="$(printf '\t')" read -r f t; do
    [ -n "$f" ] || continue
    fails=1; rc=1; abstain=0; ABSTAIN_RC=124   # RESET per file: a stale rc would misname the cut
    for i in 1 2; do                                     # each re-run gets a FRESH private TMPDIR
      # NO ADMISSION WAIT before a retry (v1 slept here, per file, per attempt — the ~12-call ×
      # 600s budget that made a run 2h of sleeping). Waiting was never the cheap half of that
      # trade; it was the amplifier, and the verifier is the one party that may never wait (R7).
      #
      # The ladder's premise is "a re-run under a CHANGED environment discriminates a real failure
      # from an environmental one", and the change it applies is a BAND CHANGE, not a wait: the
      # re-run is elevated OUT of the corpus's background clamp into utility (RETRY_QOS, see the
      # RETRY BAND note at the top). Until 2026-07-31 this ran in "${QOS[@]}" — the corpus band —
      # which de-prioritises the re-run rather than de-contending it, i.e. it moved the environment
      # the WRONG WAY for the dominant failure mode (pressure kills: exit 143/137, see below) and
      # left the ladder unable to render the verdict it exists to render. Elevating buys the same
      # "different environment" the wait used to buy, for seconds, without waiting for a quiet
      # window that never comes (§1: none by construction).
      tdir="$(mktemp -d "$RUN_TMP/retry.XXXXXX")"
      # BOUNDED for the same reason the full suite is: a file that WEDGES would hold the ladder —
      # and this runner's mutex — open forever, turning one hung test into a dead post-land net.
      retry_once "$f" "$t" "$tdir"; rc=$?
      RETRIES=$((RETRIES+1)); rm -rf "$tdir"
      # OUR OWN BOUND IS NOT EVIDENCE ABOUT THE TREE (C23) — the rule every other 124 site in this
      # file already follows (prelint ⇒ cut, confirm_hang ⇒ the HUNG discriminator, classify_hang case
      # 1, the stall unify). This was the one site that read rc without asking WHOSE bound fired, and
      # it is the whole 0-green-stamp deadlock: a slow suite's 124 became a fail, two of them became a
      # "reproducible RED", and a red stamp is what blocks deploy forever. Attempt 2 is skipped
      # deliberately — under an identical bound it would abstain identically, so it buys no
      # information and costs another RETRY_TO.
      #
      # 124 WAS NOT THE ONLY NON-VERDICT, and fixing only that half left the deadlock standing
      # (2026-07-31). bats(1) answers with exactly TWO codes about the tree — measured, not assumed:
      # 0 = every test passed, 1 = at least one test FAILED (1 whether one test failed or all of
      # them). Every OTHER code therefore says the run could not be MADE, exactly as prelint's
      # `rc != 1 ⇒ non-verdict` contract already spells out one function away:
      #     124        our own bound fired
      #     >128       killed by a signal — 137 SIGKILL, 143 SIGTERM (rc-128 names it)
      #     126/127    not executable / not found
      # The evidence this matters more than the 124 case: of 35 flake rows, 34 are `pass-on-retry`
      # or `1-of-3`, and their signals are dominated by `exit 143` (x8) and `exit 137` (x3) at a
      # median loadavg of 13.9 — i.e. suites SIGKILLed by machine pressure on a box that never goes
      # quiet. Each one was scored as a genuine failure; two on one file minted a "reproducible RED";
      # and 40 of 42 stamps went red with the last green 24h stale, so nothing could deploy. Run
      # standalone at load 15, four of the five "consistently RED" suites pass outright.
      #
      # Stated plainly because it is a real widening: a suite killed by an OOM/pressure signal can no
      # longer be convicted here. That is the correct trade — a kill is a fact about the MACHINE, and
      # a verifier that convicts the tree for the box's load blocks deploy forever while proving
      # nothing. Unproven is not silent: it takes the CUT path below and is retried next sweep.
      case "$rc" in
        0|1) ;;                                  # the only two codes that speak about the tree
        *)   abstain=1; ABSTAIN_RC="$rc"; break ;;   # 124 / >128 signal / 126 / 127 ⇒ nothing proven
      esac
      [ "$rc" -eq 0 ] || fails=$((fails+1))
    done
    if [ "$fails" -ge 2 ]; then FAILING+=("$f"); [ -n "$FAILTEST" ] || FAILTEST="$t"
    elif [ "$abstain" = 1 ]; then
      # Not a red (nothing was proven) and not a flake (nothing was cleared) ⇒ the cut path, which
      # says exactly that and retries next sweep. FAILTEST carries the name so the cut is diagnosable.
      LADDER_UNPROVEN=1; [ -n "$FAILTEST" ] || FAILTEST="$t"
      # Name WHICH non-verdict fired. "our own bound" was accurate while 124 was the only abstaining
      # code; now that a signal kill also abstains, a fixed message would misattribute a SIGKILL to
      # our timeout and send the next reader hunting a slow test that was never slow.
      arc="${ABSTAIN_RC:-124}"
      if   [ "$arc" -eq 124 ]; then why="our own ${RETRY_TO}s bound fired on the re-run"
      elif [ "$arc" -gt 128 ]; then why="the re-run was KILLED by signal $(( arc - 128 )) (machine pressure, not the tree)"
      elif [ "$arc" -eq 126 ] || [ "$arc" -eq 127 ]; then why="the re-run could not execute (rc $arc)"
      else why="the re-run exited $arc — not a tree verdict (bats says 0=pass, 1=fail)"
      fi
      log "ladder UNPROVEN for $f — $why; no verdict (cut, not red)"
    else record_flake "$f" "$t" "$rc"; fi
  done <<EOF
$pairs
EOF
}
# ════ NO ADMISSION CONTROL — deleted, not tuned (§4.2.3, R7) ══════════════════════════════════════
# v1's gate_admit() lived here: poll the 1-min load, sleep while it exceeded a ceiling, proceed when
# the budget ran out. It is GONE, and its absence is the feature — see the BACKGROUND QoS block at
# the top for why (waiting is the amplifier; the singleton verifier may never be the thing that
# waits). Nothing in this file sleeps on load. If you are about to re-add a load wait here, the
# measurement to beat is: 5 concurrent gates at load 16-18 against their own ceiling of 8, each
# one's corpus being the load the others were waiting out.

do_bisect() { # <file> <good> <bad> → sets BISECT_CULPRIT (empty when undecidable); rc 1 = no culprit
  # NEVER call this in `$( )` — it MINTS a worktree cell and the record is a global. See BISECT_CULPRIT.
  local file="$1" good="$2" bad="$3" runner out culprit qos rc=0 counter steps
  BISECT_CULPRIT=""
  [ -n "$good" ] && [ -n "$bad" ] && [ "$good" != "$bad" ] || return 1
  file="tests/$(basename "$file")"
  prepare_worktree "$bad" || return 1
  runner="$(mktemp "$TMPBASE/postland-bisect.XXXXXX")" || return 1
  counter="$runner.steps"; : > "$counter"
  # UNWIND STRUCTURALLY, not positionally. A CUT bisect leaves the cell parked on a probe commit
  # with BISECT_* state in .git — the next `bisect start` there fails and the cell's git state is a
  # lie. The reset used to sit inline after the `if`, which happened to cover the two exits that
  # existed then; the bound below adds a third, so make it a RETURN trap that no later exit path can
  # miss. Verified on bash 3.2 (macOS): the trap fires on every return and still sees $runner.
  # It DISARMS ITSELF (`trap - RETURN` in the handler) because bash's trap table is GLOBAL, not
  # function-scoped — measured, not assumed: `trap -p RETURN` after the return still shows it armed,
  # pointing at a $runner that no longer exists. Inert today only because functrace is off; one
  # `set -T` anywhere later and every subsequent function return would run a `rm -f` on an unbound
  # variable under `set -u`. Disarming costs nothing and removes the whole class.
  trap 'git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true; rm -f "$runner" "$counter"; trap - RETURN' RETURN
  qos="$(printf '%q ' "${QOS[@]}")"     # every bats invocation runs in the background band, incl. this one
  {                                     # 125 = SKIP: file absent, or bats ERRORED (rc>1) — not a red
    printf '#!/bin/bash\n'
    # STEP CAP (see BISECT_MAX_STEPS). Counted in the RUNNER because only the runner is guaranteed
    # to execute exactly once per step — `git bisect run` exposes no step hook. Exiting >=128 makes
    # git abort the run itself, so the bisect unwinds cleanly instead of being left parked mid-walk;
    # verified against this git: a 129 gives `bisect run failed: exit code 129 ... is < 0 or >= 128`
    # and NO "is the first bad commit" line. Note it is git that reports rc 127 for that abort, not
    # 129 — which is why the cut below is detected from the COUNTER, never from rc.
    # shellcheck disable=SC2016  # authoring a script: $n and the $( ) must NOT expand here
    printf 'n=$(( $(cat "%s" 2>/dev/null || echo 0) + 1 )); printf %%s "$n" > "%s"\n' "$counter" "$counter"
    # shellcheck disable=SC2016  # ditto — $n is read by the RUNNER, not by us
    printf '[ "$n" -le %s ] || exit 129\n' "$BISECT_MAX_STEPS"
    # cd EXPLICITLY. `git bisect run` already invokes this with the cell as cwd, but the TIP
    # CONFIRMATION below calls the runner directly, and the relative `tests/…` needs the cell there too.
    printf 'cd %q || exit 125\n' "$WORKTREE"
    printf '[ -f "%s" ] || exit 125\n' "$file"
    # `</dev/null` is THE worst-exposure site of the class documented at BATS_BIN. This runner is
    # `git bisect run`'s child, so its stdin is the daemon's — and a step that wedges on it is a
    # hang nothing decides by content. 7c32cc6f's wall + step cap CONTAIN that runaway; this is
    # what removes its cause.
    printf '%s"%s" "%s" </dev/null >/dev/null 2>&1\n' "$qos" "$BATS_BIN" "$file"
    # shellcheck disable=SC2016  # authoring a script: $rc must NOT expand here
    printf 'rc=$?\n[ "$rc" -le 1 ] || exit 125\nexit "$rc"\n'
  } > "$runner"
  chmod +x "$runner"
  if git -C "$WORKTREE" bisect start "$bad" "$good" >/dev/null 2>&1; then
    # THE BOUND (2026-08-05, 12h53m runaway — see BISECT_TO). `bounded` degrades to running
    # unbounded when no timeout(1) resolves, so log that state rather than skip the bisect: a
    # missing tool must not silently become a different behaviour, and the operator needs to know
    # which of the two shapes a 12-hour process was.
    [ -n "$TIMEOUT_BIN" ] && [ -x "$TIMEOUT_BIN" ] \
      || log "bisect UNBOUNDED — no timeout(1) resolved; the ${BISECT_TO}s wall is INERT this run — only the ${BISECT_MAX_STEPS}-step cap bounds it"
    out="$(bounded "$BISECT_TO" git -C "$WORKTREE" bisect run "$runner" 2>/dev/null)"; rc=$?
    steps="$(cat "$counter" 2>/dev/null || echo 0)"
    # EITHER bound firing ⇒ NON-VERDICT, and the parse is SKIPPED rather than merely expected to
    # come back empty: `bisect run` prints its running log to stdout, so a cut mid-report could in
    # principle carry the "is the first bad commit" line for a commit it had not finished proving.
    # An innocent sha named as the culprit is what C20 then REVERTS. Undecidable is the safe read.
    #
    # The cap is detected from the COUNTER, not from rc: git reports its abort as rc 127, which is
    # indistinguishable from a runner that could not be executed. `-gt` and not `-ge` — the runner
    # refuses only on the step AFTER the cap, so the counter exceeds BISECT_MAX_STEPS iff the cap
    # actually fired. A healthy bisect that finishes in exactly the cap's worth of steps still gets
    # its culprit named (pinned by B8).
    if [ "$rc" -eq 124 ]; then
      log "bisect CUT at ${BISECT_TO}s (POSTLAND_BISECT_TIMEOUT_S) — undecidable, no culprit named"
    elif [ "${steps:-0}" -gt "$BISECT_MAX_STEPS" ]; then
      log "bisect CUT at the ${BISECT_MAX_STEPS}-step cap (POSTLAND_BISECT_MAX_STEPS) — the range is NOT SHRINKING (a suite that commits into \$WORKTREE does exactly this); undecidable, no culprit named"
    else
      culprit="$(printf '%s\n' "$out" | sed -n 's/^\([0-9a-f]\{7,40\}\) is the first bad commit.*/\1/p' | head -1)"
      # ── A BISECT CAN NAME A COMMIT IT NEVER RAN ──────────────────────────────────────────────────
      # `git bisect` takes BOTH endpoints on trust and probes only until ONE candidate remains, which
      # it then DECLARES without running. So whenever the walk narrows onto the tip — every interior
      # probe returning GOOD — it names `bad` having never executed a step there. That verdict is
      # produced by the ASSUMPTION, not by a measurement, and it is the one input auto_revert trusts
      # enough to mutate trunk with.
      #
      # Both halves measured, not reasoned: over a 6-commit range a runner that always exits 0 probes
      # the 2 interior commits and then names the bad tip, never having run it. The degenerate case
      # proves the rule rather than breaking it — when the range holds a SINGLE candidate that
      # candidate is bisect's first checkout, so it does get probed (verified: 1 probe, tip named).
      # The confirmation below is therefore redundant on that path and wrong on none, which is why it
      # is keyed on the verdict (`culprit = bad`) and not on a guess about how the walk got there.
      #
      # Which is exactly how revert f323b427 reached trunk on 2026-08-06. The corpus convicted
      # tests/handoff-fire-kitty-daemon.bats — a suite already red in EVERY postland run that day from
      # 00:04, 12h BEFORE the land, and filed as a pre-existing trunk red in backlog 043c2e5fcc7e /
      # d4fcb1f5eb53. It does not reproduce in isolation, so the interior probed green and the bisect
      # named the tip e80c85aa2e47, whose ENTIRE diff is tests/cc-queue.bats — a file bats runs in a
      # different process, which therefore cannot reach the convicted suite at all. Reverting it
      # re-opened the /sbin-PATH red e80c85aa had just fixed, so the auto-heal left trunk strictly
      # worse than it found it.
      #
      # So CONFIRM the tip before naming it. Scoped to `culprit = bad` deliberately: an INTERIOR
      # culprit was genuinely executed and returned BAD while its parent returned GOOD — a real
      # measured differential that needs nothing added — so the common single-commit regression keeps
      # its auto-revert and the existing step-cap controls keep counting only real walk steps. The
      # confirmation costs one whole-file run, on the one path where the evidence is otherwise zero.
      #
      # Anything but a definite red — green, 125, or our own 124 bound — is UNDECIDABLE, and
      # red_actions already spends that correctly: it pages and backlogs the RED and reverts nothing.
      # Abstaining costs a page; not abstaining cost a correct fix.
      if [ -n "${culprit:-}" ] && [ "$culprit" = "$bad" ]; then
        : > "$counter"          # a confirmation is not a bisect STEP — leave the cap's budget alone
        git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true      # ...so the checkout below can run
        if ! bounded 120 git -C "$WORKTREE" checkout --detach --force "$bad" >/dev/null 2>&1; then
          log "bisect UNCONFIRMED: cannot check out the tip $(sha12 "$bad") to confirm it — undecidable, no culprit named"
          culprit=""
        else
          rc=0; bounded "$RETRY_TO" "$runner" || rc=$?
          if [ "$rc" -ne 1 ]; then
            log "bisect UNCONFIRMED: the walk named the TIP $(sha12 "$bad") without ever running it, and $file is NOT reproducibly red there ALONE (runner rc=$rc) — undecidable, no culprit named"
            culprit=""
          fi
        fi
      fi
    fi
  fi
  [ -n "${culprit:-}" ] || return 1
  BISECT_CULPRIT="$culprit"
}
write_stamp() { # <tree> <commit> <verdict> <run_s> <retries> <adv> [failing…]
  local tree="$1" commit="$2" verdict="$3" run_s="$4" retries="$5" adv="$6" gcd; shift 6
  mkdir -p "$STAMPS" 2>/dev/null || true
  printf '{"tree":"%s","commit":"%s","verdict":"%s","failing":%s,"ts":"%s","run_s":%s,"retries":%s,"suites":%s,"checks":"bats+bash-n","shellcheck_advisory":%s,"env":%s}\n' \
    "$tree" "$commit" "$verdict" "$(json_array "$@")" "$(now_iso)" "$run_s" "$retries" "${CORPUS_N:-0}" "$adv" "$ENV_FP" > "$STAMPS/$tree.json"
  # ── GATE-GREEN SYNC (§4.2.5) ───────────────────────────────────────────────────────────────────
  # gate-green asserts "the FULL suite proved this tree". In v2 the land lane no longer runs a
  # corpus, so it can no longer make that claim and stops writing the marker — this is the ONLY
  # writer left. Its consumers (hooks/boundary-handoff.sh:172, hooks/wrap-ledger.sh) read
  # `cat <git-common-dir>/gate-green` and compare it to HEAD, so the value is the COMMIT sha, not
  # the tree. Best-effort by construction: a stamp is the verdict of record, and a failed marker
  # write degrades those consumers to "not green ⇒ abstain", which is the safe direction.
  [ "$verdict" = "green" ] || return 0
  gcd="$(git -C "$REPO" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$gcd" in
    '')  return 0 ;;
    /*)  ;;
    *)   gcd="$REPO/$gcd" ;;                  # `-C` makes this RELATIVE to $REPO (usually `.git`)
  esac
  [ -d "$gcd" ] && printf '%s\n' "$commit" > "$gcd/gate-green" 2>/dev/null
  return 0
}
author_sid() { # <sha> — the sid that LANDED it, from land.log. The attested land line carries
  # "head":"<sha>","sid":"<sid>"; key on that pair, and fall back to the pre-v2 substring match so
  # an older line still notifies. Best-effort: a missing sid costs a courtesy ping, never a verdict.
  local sha="${1:-}" line=""
  [ -n "$sha" ] || return 0
  line="$(grep -F "\"head\":\"$sha\"" "$LANDLOG" 2>/dev/null | tail -1)"
  [ -n "$line" ] || line="$(grep -F "$sha" "$LANDLOG" 2>/dev/null | tail -1)"
  printf '%s' "$line" | sed -n 's/.*"sid":"\([^"]*\)".*/\1/p'
}
# ════ AUTO-REVERT — a red trunk is HEALED, not merely announced (§4.2.4, R2) ══════════════════════
# v2 moves the full-suite verdict OFF the land path, so a red CAN reach trunk. That is only sound
# because the culprit comes back out automatically within one cycle: the revert is what restores the
# invariant the deploy lane depends on (R3), it is O(1), and every alternative response (page and
# wait / block later landers) either does nothing or rebuilds the queue v2 exists to delete.
# GUARDS, in order — each one is a way this could otherwise become a revert WAR:
#   0. no BISECTED culprit ⇒ never called. red_actions falls back to the target sha when bisect is
#      undecidable, and reverting a sha that nothing convicted would revert an innocent tip.
#   1. POSTLAND_AUTOREVERT=off ⇒ skip. A kill switch must be env, not a revert — a revert needs the
#      pipeline that is on fire (§6.4).
#   2. C is itself a revert ⇒ skip. Reverting a revert re-lands the red; that is the war.
#   3. marker $REVERTS/<C> exists ⇒ skip. NEVER twice for one culprit, and it survives the process.
#   4. MAX_REVERTS markers written THIS run ⇒ skip. A cascade means the TREE is wrong, not one
#      commit — an operator finding, and continuing would be the fail-closed-amplifier (R7).
#   5. no executable land lane ⇒ skip. This function never pushes anything itself; the ONLY writer
#      to origin stays ship-land.sh, with its esc-scan, CAS, content-verify and land-lock intact
#      (a parked revert is a feature, R8).
# The marker records EVERY attempt past the guards, landed or not: "attempted" is the thing that
# must never repeat unattended, and a failed attempt is a human's call, not a retry loop's.
auto_revert() { # <culprit> <failing-file> — 0 = attempted (marker written), 1 = skipped
  local c="$1" file="${2:-tests/}" c12 br wt mk rc=1 rev="" step="mint" outcome pf sid
  c12="$(sha12 "$c")"
  [ "$AUTOREVERT" = "off" ] && { log "AUTOREVERT verdict=skipped reason=kill-switch culprit=$c12"; return 1; }
  git -C "$REPO" log -1 --format=%s "$c" 2>/dev/null | grep -q '^Revert' \
    && { log "AUTOREVERT verdict=skipped reason=culprit-is-itself-a-revert culprit=$c12"; return 1; }
  mkdir -p "$REVERTS" 2>/dev/null || true
  mk="$REVERTS/$c"
  [ -f "$mk" ] && { log "AUTOREVERT verdict=skipped reason=already-attempted culprit=$c12"; return 1; }
  case "$MAX_REVERTS" in ''|*[!0-9]*) MAX_REVERTS=2 ;; esac
  [ "$REVERTS_THIS_RUN" -ge "$MAX_REVERTS" ] \
    && { log "AUTOREVERT verdict=skipped reason=cap-$MAX_REVERTS-this-run culprit=$c12"; return 1; }
  [ -n "$REPO_SHIP" ] && [ -x "$REPO_SHIP" ] \
    || { log "AUTOREVERT verdict=skipped reason=no-land-lane ($REPO_SHIP) culprit=$c12"; return 1; }

  REVERTS_THIS_RUN=$((REVERTS_THIS_RUN+1))               # counted at ATTEMPT, so the cap bounds attempts
  bounded 120 git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
  br="postland-revert-$c12"
  git -C "$REPO" show-ref --verify --quiet "refs/heads/$br" && br="$br-$$"
  wt="$WT_ROOT/wt-revert-$$"
  wt_remove "$wt"                                        # residue from a crashed predecessor
  mkdir -p "$WT_ROOT" 2>/dev/null || true
  if bounded 120 git -C "$REPO" worktree add -b "$br" "$wt" origin/main >/dev/null 2>&1; then
    WT_REVERT="$wt"; step="revert"
    if ( cd "$wt" && bounded 120 git revert --no-edit "$c" >/dev/null 2>&1 ); then
      rev="$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)"
      step="land"
      # The land lane, from the revert's own worktree+branch. BOUNDED: its gate is the one piece of
      # this pipeline whose wall time is not ours to predict, and an unbounded fork here would hold
      # the verifier mutex the way the cc-inbox-guard fork held the gates for five days.
      ( cd "$wt" && bounded "$SHIP_TO" "$REPO_SHIP" ) >/dev/null 2>&1; rc=$?
    else
      ( cd "$wt" && bounded 60 git revert --abort >/dev/null 2>&1 ) || true
      rc=90                                              # revert did not apply cleanly
    fi
  else
    rc=91                                                # could not mint the revert cell
  fi
  [ "$rc" -eq 0 ] && outcome=landed || outcome="FAILED(step=$step rc=$rc)"

  { printf 'ts=%s\n' "$(now_iso)"
    printf 'culprit=%s\n' "$c"
    printf 'revert=%s\n' "${rev:-none}"
    printf 'branch=%s\n' "$br"
    printf 'failing=%s\n' "$file"
    printf 'step=%s\n' "$step"
    printf 'land_exit=%s\n' "$rc"
  } > "$mk" 2>/dev/null || true

  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-land AUTO-REVERT $outcome: $file @ $c12 (revert ${rev:-none} on $br)" \
    --project claude-infrastructure --source postland-verify >/dev/null 2>&1   # sha defeats wasDone
  sid="$(author_sid "$c")"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land AUTO-REVERT $outcome — your land $c12 failed $file in the trunk verifier; revert branch $br" >/dev/null 2>&1
  if [ "$rc" -ne 0 ]; then
    # The revert did NOT land: trunk is still red, deploy stays pinned to the last green (R3 holds
    # by construction), and this needs a human. State-keyed page, same protocol as the RED page.
    pf="$PAGES/postland-revert-$c12.page"
    { now_epoch
      printf 'post-land AUTO-REVERT FAILED @ %s\n' "$(now_iso)"
      printf 'culprit: %s (failing %s)\n' "$c12" "$file"
      printf 'step:    %s (exit %s%s)\n' "$step" "$rc" \
        "$( [ "$rc" -eq 124 ] && printf ' — OUR %ss bound fired' "$SHIP_TO" || true )"
      printf 'branch:  %s (revert commit %s) — worktree already torn down\n' "$br" "${rev:-none}"
      printf 'trunk is STILL RED; deploy stays pinned to the last green stamp.\n'
      printf 'do:      git -C %s worktree add %s/wt-revert-manual %s && cd %s/wt-revert-manual && %s\n' \
        "$REPO" "$WT_ROOT" "$br" "$WT_ROOT" "$REPO_SHIP"
      printf 'env:     %s\n' "$ENV_FP"
    } > "$pf" 2>/dev/null || true
    notify "Claude post-land AUTO-REVERT FAILED" "$c12 — trunk still red, see $pf"
  fi
  log "AUTOREVERT verdict=$outcome culprit=$c12 revert=$(sha12 "${rev:-none}") branch=$br step=$step rc=$rc"
  wt_remove "$wt"; WT_REVERT=""
  # A LANDED revert's branch is now in trunk and carries nothing else — drop it. A FAILED one is the
  # only copy of the revert commit, so it stays for the operator (the page names it).
  [ "$rc" -eq 0 ] && case "$br" in
    postland-revert-*) bounded 30 git -C "$REPO" branch -D "$br" >/dev/null 2>&1 || true ;;
  esac
  return 0
}
red_actions() { # <sha> <file> — bisect, page, backlog, notify, auto-revert. Side channels || true'd.
  local sha="$1" file="$2" good culprit bisected c12 pf sid ftest
  # ONE rendering of the failing NAME for all three artifacts below. The page and the notify already
  # carried it; the BACKLOG ITEM — the only DURABLE one — did not, and that asymmetry is what made an
  # unattributed RED unactionable. When classify_failures takes branch (b) (a real `not ok` with no
  # `# (in test file …)` diagnostic) FAILING is the sentinel "tests/", so the title read "post-land
  # RED: tests/ @ <sha>" — a work item with nothing in it to act on, while the name that WAS captured
  # lived only in the page. Item 7ddd2c171e43 was minted from exactly that shape (2026-07-30,
  # retries=0, load 47.25): by the time a worker opened it the 06:42 green had deleted the page —
  # run_target's green branch clears postland-red-*.page — so the name was unrecoverable BY
  # CONSTRUCTION, not by accident. 78526c19 has since closed that item's OWN route in (a run our
  # own bound cut is no longer a verdict at all), but branch (b) still stands for rc 0|1 — a real
  # bats failure it cannot pin to a file, which C13b deliberately keeps as a RED — so the durable
  # artifact can still be minted nameless. That surviving case is what C13d pins.
  # Bounded in pure bash (no subshell; this path runs starved by definition): FAILTEST is TAP-derived
  # and the title becomes a JSONL ledger FIELD, where an embedded newline would corrupt the record it
  # is appended to — mapping it to a space keeps the token boundary readable. The 120 cap is BYTES
  # under the C locale launchd hands this job, exactly as `cut -c` would be: not a multibyte fix,
  # just a cheaper one, sized so no single test name dominates the backlog listing.
  ftest="${FAILTEST:-?}"; ftest="${ftest//[$'\n\r']/ }"; ftest="${ftest:0:120}"
  [ -n "$ftest" ] || ftest='?'
  good="$(cat "$LASTGREEN" 2>/dev/null || true)"
  do_bisect "$file" "$good" "$sha" 2>/dev/null || true      # NOT `$( )` — see BISECT_CULPRIT
  bisected="$BISECT_CULPRIT"
  culprit="$bisected"
  [ -n "$culprit" ] || culprit="$sha"
  c12="$(sha12 "$culprit")"
  # No re-mint after the bisect: the check cell is EPHEMERAL now (§4.2.1) and nothing below reads
  # it — the re-run hint hands the operator their own cell instead of a path we are about to delete.
  # STATE-KEYED page filename — a fixed key gets path-dedup-swallowed for 7 days.
  pf="$PAGES/postland-red-$c12.page"
  { now_epoch
    printf 'post-land RED @ %s\n' "$(now_iso)"
    printf 'culprit: %s (bisected from last-green %s)\n' "$c12" "$(sha12 "${good:-unknown}")"
    printf 'failing: %s::%s\n' "$file" "$ftest"
    [ "${#FAILING[@]}" -gt 1 ] && printf 'all failing: %s\n' "${FAILING[*]}"
    printf 're-run:  git -C %s worktree add --detach /tmp/pv-repro %s && cd /tmp/pv-repro && bats %s\n' \
      "$REPO" "$c12" "$file"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add --title "post-land RED: $file::$ftest @ $c12" \
    --project claude-infrastructure --source postland-verify >/dev/null 2>&1  # sha defeats wasDone
  notify "Claude post-land RED" "$file fails at $c12 — see $pf"
  sid="$(author_sid "$culprit")"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land RED: $file::$ftest at $c12 (your land) — see $pf" >/dev/null 2>&1
  # AUTO-REVERT only a BISECTED culprit (guard 0). When the bisect was undecidable, `culprit` above
  # fell back to the target sha for PAGING purposes — reverting that would revert a tip nothing
  # convicted, so the fallback is deliberately not passed through here.
  [ -n "$bisected" ] && auto_revert "$bisected" "$file"
  return 0
}
hung_actions() { # <sha> <tree> — page + backlog + notify, routed to the SEAM owner.
  # Deliberately NO bisect: a hang is a latent un-stubbed seam that surfaced when contention eased,
  # not a recent regression — and every bisect step would itself wedge for the full bound.
  local sha="$1" tree="$2" slug pf sid file="${SUSPECT:-tests/}"
  slug="$(printf '%s' "$file" | sed 's#.*/##; s/\.bats$//; s/[^A-Za-z0-9_-]/-/g')"
  [ -n "$slug" ] || slug=suite                        # unmappable suspect ⇒ still a keyable name
  pf="$PAGES/postland-hung-$slug-$(sha12 "$tree").page"
  { now_epoch
    printf 'post-land HUNG @ %s\n' "$(now_iso)"
    printf 'suite:   %s (tree %s)\n' "$(sha12 "$sha")" "$(sha12 "$tree")"
    printf 'wedged:  %s at %s completed — %s\n' "$file" "$WEDGE_AT" "$DEATH_SIG"
    printf 'proof:   re-ran %s ALONE in this pristine detached worktree; wedged again: %s\n' "$file" "$REPRODUCED"
    printf 'NOT a cut: no signal reached this run (a peer pkill shows rc>128 / a job-control line).\n'
    printf 'FIX:     find the un-stubbed external seam and timeout-wrap it (or stub it in setup()).\n'
    printf 're-run:  git -C %s worktree add --detach /tmp/pv-repro %s && cd /tmp/pv-repro && %s %s\n' \
      "$REPO" "$(sha12 "$sha")" "${TIMEOUT_BIN:-timeout} $FILE_TO bats" "$file"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  [ -x "$BACKLOG_BIN" ] && "$BACKLOG_BIN" add \
    --title "post-land HUNG: $file wedged at $WEDGE_AT @ $(sha12 "$tree") — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)" \
    --project claude-infrastructure --source postland-verify >/dev/null 2>&1   # tree defeats wasDone
  notify "Claude post-land HUNG" "$file wedges at $WEDGE_AT — un-stubbed seam, see $pf"
  sid="$(author_sid "$sha")"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land HUNG: $file wedged at $WEDGE_AT on your land — un-stubbed external seam, see $pf" >/dev/null 2>&1
  return 0
}
run_target() { # <sha> — the whole check-set + verdict for ONE sha
  local sha="$1" tree tap rc adv t0 run_s n sf
  local -a bargs
  CUR_SHA="$sha"
  tree="$(tree_of "$sha")"
  [ -n "$tree" ] || { log "cannot resolve tree for $sha"; return 1; }
  IDENTITY_SNAP="$(identity_snapshot)"   # BEFORE the cell exists — the widest window we can watch
  prepare_worktree "$sha" || { log "worktree prepare FAILED for $(sha12 "$sha")"; return 1; }
  t0="$(now_epoch)"; env_fingerprint            # captured at run START — a green is env-relative
  RUN_TMP="$(mktemp -d "$TMPBASE/postland-run.XXXXXX")" || return 1
  FAILING=(); FAILTEST=""; RETRIES=0; NFLAKE=0; CUT=0; LADDER_UNPROVEN=0; CORPUS_N=0   # reset per requeue pass
  CUT_WHY='zero not-ok in a non-zero run - truncated'
  DEATH_SIG=""; WEDGE_AT=""; SUSPECT=""; REPRODUCED=false
  syntax_check
  tap="$RUN_TMP/bats.tap"; : > "$tap"; rc=0
  prelint_check                       # whole-tree meta-lints, standalone, BEFORE the corpus
  if [ "${#FAILING[@]}" -gt 0 ]; then
    # FAIL FAST. The tree is already red on a DETERMINISTIC, named, whole-tree violation, and 138
    # suites cannot change that verdict — running them would spend 20-53 min of the singleton's
    # only slot to re-reach a decided answer, delaying the NEXT tree's verification by that much
    # (R7: a degradation path must never pick the more expensive action). The stamp names the lint,
    # and run_s/retries≈0 is itself the tell that this was a lint red, not a corpus red.
    log "corpus SKIPPED — pre-corpus whole-tree lint(s) already red: ${FAILING[*]}"
  else
    # THE TREE CORPUS — an explicit file list, never `tests/`. Passing the list is what makes the
    # partition real AND what keeps suite_file_at's index→file mapping honest (bats runs files in
    # the order given, which is the order of this same list). ONE bats process over that list —
    # per-suite looping is deliberately NOT done here: the retry ladder already isolates a failure
    # to its file, and a per-suite loop pays process startup 138 times for the same information.
    build_corpus
    bargs=()
    while IFS= read -r sf; do [ -n "$sf" ] && bargs+=("$sf"); done <<EOF
$(suite_files)
EOF
    if [ "${#bargs[@]}" -eq 0 ]; then
      # No tests, or a manifest that excluded everything. Hand bats the directory so ITS error is
      # the one recorded, rather than inventing a green out of an empty corpus.
      log "corpus EMPTY after the host partition — falling back to tests/ (never green-by-absence)"
      bargs=("tests/")
    fi
    log "corpus: ${#bargs[@]} tree suite(s), $HOST_SKIPPED host suite(s) partitioned out @ $(sha12 "$sha")"
    # THE STAMP'S DENOMINATOR. Recorded here because a verdict without the size of the population it
    # judged is not auditable: `{"verdict":"green","failing":[]}` reads identically whether 197 suites
    # passed or the corpus collapsed to a handful and passed by absence. That ambiguity cost real time
    # on 2026-07-31 — the one green stamp in 46 had to be cleared of being a vacuous partial run by
    # cross-reading runner.log for its `corpus:` line, and runner.log is rotated/GC'd on a different
    # schedule from the stamps it would be needed to explain. `suites` makes the stamp self-contained.
    CORPUS_N="${#bargs[@]}"
    # BOUNDED BY PROGRESS, backstopped by wall-clock. A fixed duration bound conflates two runs a
    # busy box cannot tell apart: STARVED-BUT-PROGRESSING (the background band yielding to 12+
    # sessions — measured 2026-07-29: two healthy runs CUT at 5437s/2737s with ZERO not-ok) and
    # WEDGED (no test completes again, ever). The bound's failure mode is the STALL, so that is what
    # it keys on: no new TAP line for POSTLAND_STALL_S (900) ⇒ cut as rc 124, which routes into
    # classify_hang exactly like the old wall bound — and names the wedged file via the TAP index —
    # only 6x sooner than the old 90-min wall. A progressing corpus runs to completion under the
    # 3h backstop (SUITE_TO), which exists for the pathological case where even the TAP writer
    # wedges. POSTLAND_STALL_S=0 restores the plain wall bound (the kill switch).
    # exec, not `bounded`: the watcher must signal timeout(1) ITSELF (which kills its child's whole
    # process group) — TERMing a wrapper subshell would orphan the bats tree instead of ending it.
    local stall poll cpid last ndone still
    stall="${POSTLAND_STALL_S:-900}"; poll="${POSTLAND_STALL_POLL_S:-60}"
    case "$stall$poll" in *[!0-9]*) stall=900; poll=60 ;; esac
    if [ "$stall" -eq 0 ] || [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then
      ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" bounded "$SUITE_TO" "${QOS[@]}" "$BATS_BIN" "${bargs[@]}" ) </dev/null > "$tap" 2>&1; rc=$?
    else
      # EXPLICIT on the async branch too. bash redirects an asynchronous command's stdin from
      # /dev/null only when job control is OFF — true for this script today, and exactly the kind
      # of ambient property that stops being true (one `set -m`, one interactive re-entry). The
      # whole corpus is behind it; it does not get to depend on a default.
      ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" exec "$TIMEOUT_BIN" -k 10 "$SUITE_TO" "${QOS[@]}" "$BATS_BIN" "${bargs[@]}" ) </dev/null > "$tap" 2>&1 &
      cpid=$!; last=0; still=0
      while kill -0 "$cpid" 2>/dev/null; do
        sleep "$poll"
        ndone="$(tap_done "$tap")"; ndone="${ndone:-0}"
        if [ "$ndone" -gt "$last" ]; then last="$ndone"; still=0; else still=$(( still + poll )); fi
        if [ "$still" -ge "$stall" ]; then
          log "STALL: no TAP progress for ${stall}s at test $last — cutting the run (a stall, not slowness)"
          kill -TERM "$cpid" 2>/dev/null || true
          break
        fi
      done
      wait "$cpid" 2>/dev/null; rc=$?
      # A stall-cut presents as the bound firing: classify_hang keys on 124 and will name the
      # wedged file from the TAP index. timeout's own ceiling already exits 124; unify the TERM path.
      [ "$still" -ge "$stall" ] && rc=124
    fi
  fi
  adv="$(sc_count)"
  [ "$rc" -eq 0 ] || classify_failures "$tap" "$rc"
  [ "${#SYNTAX_BAD[@]}" -eq 0 ] || FAILING+=("${SYNTAX_BAD[@]}")
  identity_assert            # did anything we just ran write a git identity into the shared config?
  # A meta-lint whose own bound fired proves nothing — so an otherwise-clean run may NOT be stamped
  # green off the back of a check that never returned. Downgrade to the cut path: honest, retried
  # next sweep, and cool-off/paged by the existing CUT_MAX ladder if the tree keeps doing it.
  # Same rule for a RETRY whose own bound fired (C23): the file was neither convicted nor cleared, so
  # the run proved nothing about this tree. Green would be unearned; red would be the lie that kept
  # every stamp red and deploy refused. Cut says it honestly and the next sweep retries.
  { [ "$PRELINT_UNPROVEN" = 1 ] || [ "$LADDER_UNPROVEN" = 1 ]; } && [ "${#FAILING[@]}" -eq 0 ] && CUT=1
  run_s="$(( $(now_epoch) - t0 ))"
  if [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ] && classify_hang "$tap" "$rc"; then
    # HUNG is carved out of the cut population and IS a verdict about the tree: it reproduced here,
    # at this load, on a pristine detached checkout. Stamp it so the tree is not re-run forever, and
    # page the FILE with the fix that actually applies (timeout-wrap the seam), not "retry when
    # quieter" — which is the one response guaranteed never to clear it.
    write_stamp "$tree" "$sha" hung "$run_s" "$RETRIES" "$adv" "${SUSPECT:-tests/}"
    cut_clear                                   # a verdict was reached: the cut streak is over
    log "HUNG $(sha12 "$sha") tree=$(sha12 "$tree") suspect=${SUSPECT:-?} wedge_at=$WEDGE_AT sig=$DEATH_SIG reproduced=$REPRODUCED run_s=$run_s"
    hung_actions "$sha" "$tree"
    echo "postland-verify: HUNG $(sha12 "$sha") — ${SUSPECT:-tests/} wedged at $WEDGE_AT ($DEATH_SIG)"
  elif [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ]; then
    # A cut proves NOTHING — do not stamp green (unearned) and do not stamp red (a lie that
    # blocks deploy forever). Stamp `cut` for diagnosability: the tree stays unstamped-green,
    # so C5's abstain does not fire and the NEXT sweep retries it. No bisect, no page — you
    # cannot bisect a machine event, and paging on one trains the operator to ignore pages.
    write_stamp "$tree" "$sha" cut "$run_s" "$RETRIES" "$adv"
    n="$(cut_bump "$tree")"
    [ "$n" -ge "$CUT_MAX" ] && cut_page "$sha" "$tree" "$n"
    log "CUT $(sha12 "$sha") tree=$(sha12 "$tree") run_s=$run_s retries=$RETRIES sc_adv=$adv consecutive=$n ($CUT_WHY; will retry)"
    echo "postland-verify: CUT $(sha12 "$sha") (${run_s}s) - run truncated, not red; retrying next sweep"
  elif [ "${#FAILING[@]}" -eq 0 ]; then
    write_stamp "$tree" "$sha" green "$run_s" "$RETRIES" "$adv"
    printf '%s\n' "$sha" > "$LASTGREEN"
    cut_clear                                   # a verdict was reached: the cut streak is over
    rm -f "$PAGES"/postland-red-*.page "$PAGES"/postland-cut-*.page \
          "$PAGES"/postland-hung-*.page 2>/dev/null || true  # now-passing state clears standing pages
    log "GREEN $(sha12 "$sha") tree=$(sha12 "$tree") run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    echo "postland-verify: GREEN $(sha12 "$sha") (${run_s}s, flakes=$NFLAKE)"
  else
    write_stamp "$tree" "$sha" red "$run_s" "$RETRIES" "$adv" "${FAILING[@]}"
    cut_clear                                   # a verdict was reached: the cut streak is over
    log "RED $(sha12 "$sha") failing=${FAILING[*]} run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    red_actions "$sha" "${FAILING[0]}"
    echo "postland-verify: RED $(sha12 "$sha") — ${FAILING[*]}"
  fi
  rm -rf "$RUN_TMP"; RUN_TMP=""
  return 0
}

# ════ verbs ═══════════════════════════════════════════════════════════════════════════════════════
do_run_if_needed() {
  local target tree new loops=0
  git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
  target="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"
  [ -n "$target" ] || { idl abstained no-origin-main; return 0; }
  tree="$(tree_of "$target")"
  if [ -n "$tree" ] && stamp_is_verdict "$tree"; then idl abstained already-stamped "$(sha12 "$target")"; return 0; fi
  # A tree the box has cut CUT_MAX times running is hostile: re-running a full suite on it every
  # tick amplifies the contention doing the cutting. Cool off (already paged), then resume retrying.
  if [ -n "$tree" ] && in_cut_cooloff "$tree"; then idl abstained cut-cooloff "$(sha12 "$target")"; return 0; fi
  try_acquire || { idl abstained lock-held "$(sha12 "$target")"; return 0; }   # 2nd instance: quiet 0
  trap cleanup_exit EXIT
  while [ "$loops" -lt 2 ]; do                                # single-slot self-requeue, never a queue
    loops=$((loops+1))
    printf '%s\n' "$target" > "$QUEUE" 2>/dev/null || true
    run_target "$target"
    git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
    new="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || printf '%s' "$target")"
    [ "$new" = "$target" ] && break
    tree="$(tree_of "$new")"
    # SAME predicate as the entry gate above, and for the same reason: a `cut` stamp on the
    # moved-to tree means nothing was proven there, so breaking on its mere EXISTENCE hands the
    # new head straight back to the next sweep unverified. Only a real verdict ends the requeue.
    [ -n "$tree" ] && stamp_is_verdict "$tree" && break
    target="$new"
  done
  : > "$QUEUE" 2>/dev/null || true
  idl fired "ran:$(sha12 "$target")" "$(sha12 "$target")"
  return 0
}
do_run_one() { # <sha>
  local sha
  [ -n "${1:-}" ] || { echo "usage: postland-verify.sh --run <sha>" >&2; idl abstained no-sha; return 2; }
  sha="$(git -C "$REPO" rev-parse "$1^{commit}" 2>/dev/null || true)"
  [ -n "$sha" ] || { echo "postland-verify: unknown sha '$1'" >&2; idl abstained unknown-sha; return 2; }
  try_acquire || { echo "postland-verify: another run holds the mutex" >&2; idl abstained lock-held "$(sha12 "$sha")"; return 0; }
  trap cleanup_exit EXIT
  run_target "$sha"
  idl fired "ran:$(sha12 "$sha")" "$(sha12 "$sha")"
  return 0
}
verb_bisect() { # <file> <good> <bad>
  local c
  [ "$#" -eq 3 ] || { echo "usage: postland-verify.sh bisect <file> <good> <bad>" >&2; idl abstained bad-args; return 2; }
  do_bisect "$1" "$2" "$3" || true; c="$BISECT_CULPRIT"      # NOT `$( )` — see BISECT_CULPRIT
  idl fired "bisect:$1"
  [ -n "$c" ] || { echo "postland-verify: bisect undecidable" >&2; return 1; }
  echo "$c"
}
# ════ a CUT stamp is a DIAGNOSTIC, never a verdict ════════════════════════════════════════════════
# `cut` records that a run was truncated (killed / starved) — no test ever said no, so nothing was
# proven. Abstaining on it strands the tree UNVERIFIED FOREVER: the stamp file exists, so an
# existence-keyed abstain fires on every later sweep and the suite never runs again. That also keeps
# is-green false, which drives ship-land to declare the whole post-land net INERT and degrade every
# gate scoped→FULL — more full suites, more load, more cuts. Only a real verdict earns an abstain.
# `hung` IS a verdict and belongs here: unlike a cut it is a proven property of the TREE (the suspect
# file wedged again, alone, on a pristine checkout), so re-running it every sweep re-proves a decided
# fact and burns a full suite per tick doing it. It is paged at the file, and the fix lands as a new
# tree — which carries a new stamp key, so the abstain releases by construction.
stamp_is_verdict() { # <tree> — 0 when the tree carries a REAL verdict (green|red|hung), 1 cut/absent
  grep -qE '"verdict":"(green|red|hung)"' "$STAMPS/$1.json" 2>/dev/null
}
cut_bump() { # <tree> → the new CONSECUTIVE cut count for this tree
  local pt pn n
  # `[ -f ]` FIRST: redirections are applied left to right, so `< "$CUTS" 2>/dev/null` opens the
  # input BEFORE stderr is silenced — a missing file therefore printed the shell's own "No such
  # file or directory" to the launchd job's stderr on every first-cut sweep. Control flow was
  # always fine (`|| true`); the noise read like a failure in the one log an operator scans.
  [ -f "$CUTS" ] && { read -r pt pn _ < "$CUTS" 2>/dev/null || true; }
  if [ "${pt:-}" = "$1" ]; then n=$(( ${pn:-0} + 1 )); else n=1; fi
  printf '%s %s %s\n' "$1" "$n" "$(now_epoch)" > "$CUTS" 2>/dev/null || true
  printf '%s' "$n"
}
cut_clear() { rm -f "$CUTS" 2>/dev/null || true; }
in_cut_cooloff() { # <tree> — 0 = still cooling off
  local pt pn pts
  [ -f "$CUTS" ] || return 1                      # see cut_bump: the redirect fails before 2>/dev/null
  read -r pt pn pts < "$CUTS" 2>/dev/null || return 1
  [ "${pt:-}" = "$1" ] || return 1
  [ "${pn:-0}" -ge "$CUT_MAX" ] || return 1
  [ "$(( $(now_epoch) - ${pts:-0} ))" -lt "$CUT_COOLOFF" ]
}
cut_page() { # <sha> <tree> <n> — an HONEST page: names no test, asks for no bisect
  local pf t12
  t12="$(sha12 "$2")"; pf="$PAGES/postland-cut-$t12.page"
  { now_epoch
    printf 'post-land CUT (no verdict) @ %s\n' "$(now_iso)"
    printf 'target:  %s (tree %s)\n' "$(sha12 "$1")" "$t12"
    printf 'cut:     %s consecutive runs — the suite emitted ZERO "not ok" lines, so NO test failed.\n' "$3"
    printf '         Each run was TRUNCATED before reaching a verdict (peer pkill / OOM / load).\n'
    printf 'NOT a test failure — do not bisect. Re-run on a quiet box:\n'
    printf 're-run:  git -C %s worktree add --detach /tmp/pv-repro %s && cd /tmp/pv-repro && bats tests/\n' \
      "$REPO" "$(sha12 "$1")"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
}
verb_is_green() { # <sha> — exit 0 green-stamped, 1 not
  local tree sha
  sha="$(git -C "$REPO" rev-parse "${1:-}^{commit}" 2>/dev/null || true)"
  idl abstained "is-green:${1:-}"
  [ -n "$sha" ] || return 1
  tree="$(tree_of "$sha")"
  [ -n "$tree" ] && [ -f "$STAMPS/$tree.json" ] || return 1
  grep -q '"verdict":"green"' "$STAMPS/$tree.json" 2>/dev/null || return 1
  return 0
}

# last-green, RENDERED WITH ITS STAMP RESOLVED — never the bare sha (measured misdiagnosis 2026-07-31).
# `last-green` holds a COMMIT sha; the stamp store is keyed by TREE sha. Printing the commit alone
# invites the one wrong inference that store shape makes available: a reader looks for
# `stamps/<that-sha>.json`, does not find it, and concludes the pointer is DANGLING and the verifier's
# records are corrupt. That inference was drawn and acted on — it became the headline finding of a
# whole diagnosis doc ("no stamp file with that name exists", filed as a standalone bug) when in fact
# the pointer was correct, the stamp existed, and it was green under its TREE name. So resolve the
# hop and print BOTH names plus the verdict actually on disk.
#
# This is verify-before-print, not decorate-before-print: the file is opened, so a genuinely GC'd or
# unreadable stamp renders as MISSING rather than being implied healthy by a sha that merely LOOKS
# plausible. That is the difference between a claimed outcome and a checked one, and the reason a
# status surface is allowed to be trusted at all.
render_lastgreen() {
  local sha tree f
  sha="$(cat "$LASTGREEN" 2>/dev/null || true)"
  [ -n "$sha" ] || { printf '(none)'; return 0; }
  tree="$(tree_of "$sha" 2>/dev/null || true)"
  if [ -z "$tree" ]; then
    # A THIRD state, and it must not read as either healthy or dangling: the commit is simply not in
    # this checkout (GC'd, or a sha from a repo this invocation cannot see), so nothing is claimed.
    printf '%s (commit UNRESOLVABLE here — cannot check its stamp)' "$(sha12 "$sha")"
    return 0
  fi
  f="$STAMPS/$tree.json"
  if [ ! -f "$f" ]; then
    printf '%s → stamp %s.json MISSING (tree-keyed; GCd or never written)' "$(sha12 "$sha")" "$(sha12 "$tree")"
  elif grep -q '"verdict":"green"' "$f" 2>/dev/null; then
    printf '%s → stamp %s.json green' "$(sha12 "$sha")" "$(sha12 "$tree")"
  else
    printf '%s → stamp %s.json present but NOT green' "$(sha12 "$sha")" "$(sha12 "$tree")"
  fi
}
verb_status() {
  # `worktree` is the cell this invocation WOULD mint — cells are per-run and torn down, so between
  # runs there is deliberately nothing there to look at (§4.2.1). `reverts` is the never-twice ledger.
  printf 'postland-verify status\n  state      : %s\n  worktree   : %s (minted per run)\n  last-green : %s\n' \
    "$STATE" "$WORKTREE" "$(render_lastgreen)"
  printf '  reverts    : %s\n' "$(find "$REVERTS" -type f 2>/dev/null | wc -l | tr -d ' ')"
  printf '  stamps     : %s\n  queue      : %s\n  lock       : %s\n  flakes     : %s\n  pages      : %s\n  last run   : %s\n' \
    "$(find "$STAMPS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')" \
    "$(cat "$QUEUE" 2>/dev/null || echo '(empty)')" \
    "$([ -d "$LOCK" ] && echo "held by pid $(cat "$LOCK/pid" 2>/dev/null)" || echo free)" \
    "$(cat "$FLAKES" 2>/dev/null | wc -l | tr -d ' ')" \
    "$(find "$PAGES" -name 'postland-red-*.page' 2>/dev/null | wc -l | tr -d ' ')" \
    "$(tail -1 "$LOG" 2>/dev/null || echo '(none)')"
  idl abstained status
}

# ════ selftest — RED-provable, fixture-scoped, zero side effects outside the temp dir ═════════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d rc tree green_sha red_sha
  d="$(mktemp -d "$TMPBASE/postland-selftest.XXXXXX")" || { echo mktemp failed; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  mkdir -p "$d/src/tests" "$d/state" "$d/pages"
  git init -q --bare "$d/origin.git" >/dev/null 2>&1; git init -q "$d/src" >/dev/null 2>&1
  git -C "$d/src" config user.email pv@selftest.local; git -C "$d/src" config user.name pv-selftest
  git -C "$d/src" remote add origin "$d/origin.git" >/dev/null 2>&1
  printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$d/src/tests/ok.bats"
  printf '#!/bin/bash\necho hi\n' > "$d/src/ok.sh"
  fixture_land() { # <msg> — commit + publish to the fixture origin
    git -C "$d/src" add -A >/dev/null 2>&1; git -C "$d/src" commit -qm "$1" >/dev/null 2>&1
    git -C "$d/src" push -q origin HEAD:main >/dev/null 2>&1
    git -C "$d/src" fetch -q origin >/dev/null 2>&1
  }
  run_fixture() {
    # No admission env any more: v2 has no load wait to disable (§4.2.3). POSTLAND_AUTOREVERT=off —
    # the selftest proves VERDICT logic, and a fixture must never be able to push a revert; the
    # auto-revert guards are asserted structurally below and behaviourally in tests/.
    env POSTLAND_VERIFY="${POSTLAND_VERIFY:-on}" POSTLAND_AUTOREVERT=off \
        CC_POSTLAND_DIR="$d/state" CC_POSTLAND_REPO="$d/src" \
        CC_POSTLAND_WT_ROOT="$d/cells" CC_PAGES_DIR="$d/pages" CC_IDL="$d/idl.jsonl" \
        CC_BACKLOG_BIN=/usr/bin/true CC_POSTLAND_NOTIFY=/usr/bin/true CC_POSTLAND_NOTIFY_BIN=/usr/bin/true \
        CC_POSTLAND_LANDLOG="$d/land.log" "$SELF" "$@"
  }
  fixture_land green; green_sha="$(git -C "$d/src" rev-parse HEAD)"

  echo "postland-verify --selftest:"
  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                                   # ── green path
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  [ "$rc" -eq 0 ] && okp "green: exit 0" || badp "green: exit $rc (want 0)"
  [ -f "$d/state/stamps/$tree.json" ] && okp "green: tree stamp written" || badp "green: no stamp for tree"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null && okp "green: stamp verdict green" || badp "green: stamp not green"
  [ "$(cat "$d/state/last-green" 2>/dev/null)" = "$green_sha" ] && okp "green: last-green advanced" || badp "green: last-green NOT advanced"
  [ -z "$(find "$d/pages" -name 'postland-red-*.page' 2>/dev/null)" ] && okp "green: no page written" || badp "green: page written on green"
  grep -q '"check":"postland-verify"' "$d/idl.jsonl" 2>/dev/null && okp "green: IDL line appended" || badp "green: no IDL line"
  grep -qE '"env":\{"bats":"[^"]+","cc":"[^"]*","load":"[^"]*"\}' "$d/state/stamps/$tree.json" 2>/dev/null && okp "green: stamp carries the env fingerprint" || badp "green: stamp missing env fingerprint"
  # v2 §4.2.5 — the verifier is now the ONLY writer of the full-suite claim, and it writes the COMMIT
  [ "$(cat "$d/src/.git/gate-green" 2>/dev/null)" = "$green_sha" ] \
    && okp "green: gate-green synced to the proven commit" || badp "green: gate-green NOT synced"
  # v2 §4.2.1 — the check cell is minted per run and gone afterwards (no cross-tree residue)
  [ -z "$(find "$d/cells" -maxdepth 1 -name 'wt-run-*' 2>/dev/null)" ] \
    && okp "green: the per-run worktree cell was torn down" || badp "green: worktree cell LEAKED"

  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                        # ── abstain (tree stamped)
  [ "$rc" -eq 0 ] && okp "abstain: exit 0 on an already-stamped tree" || badp "abstain: exit $rc"
  grep -q '"decision":"abstained","reason":"already-stamped"' "$d/idl.jsonl" 2>/dev/null && okp "abstain: IDL records already-stamped" || badp "abstain: IDL missing already-stamped"
  run_fixture is-green "$green_sha" >/dev/null 2>&1 && okp "is-green: exit 0 on a green sha" || badp "is-green: nonzero on a green sha"
  POSTLAND_VERIFY=off run_fixture --run-if-needed >/dev/null 2>&1; rc=$?                # ── kill switch
  [ "$rc" -eq 0 ] && okp "kill switch: POSTLAND_VERIFY=off exits 0" || badp "kill switch: exit $rc"

  printf '#!/usr/bin/env bats\n@test "boom" { false; }\n' > "$d/src/tests/bad.bats"     # ── red path
  fixture_land red; red_sha="$(git -C "$d/src" rev-parse HEAD)"
  run_fixture --run-if-needed >/dev/null 2>&1; rc=$?
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  [ "$rc" -eq 0 ] && okp "red: exit 0 (the net pages, it does not fail launchd)" || badp "red: exit $rc"
  grep -q '"verdict":"red"' "$d/state/stamps/$tree.json" 2>/dev/null && okp "red: stamp verdict red" || badp "red: stamp not red"
  [ -n "$(find "$d/pages" -name 'postland-red-*.page' 2>/dev/null)" ] && okp "red: state-keyed page written" || badp "red: NO page written"
  [ "$(cat "$d/state/last-green" 2>/dev/null)" = "$green_sha" ] && okp "red: last-green NOT advanced" || badp "red: last-green advanced on red"
  find "$d/pages" -name 'postland-red-*.page' 2>/dev/null | head -1 | xargs head -1 2>/dev/null \
    | grep -qE '^[0-9]+$' && okp "red: page line 1 is an epoch" || badp "red: page line 1 not an epoch"
  find "$d/pages" -name "postland-red-$(sha12 "$red_sha").page" 2>/dev/null | grep -q . \
    && okp "red: page keyed to the bisected culprit sha" || badp "red: page not culprit-keyed"

  # ── §4.2.2 PARTITION: a suite named in the manifest is NOT part of the tree verdict ─────────────
  # Behavioural, against the real producer: the tree still carries the red bad.bats from the block
  # above; listing it in the manifest must turn the very same tree GREEN. The control is that same
  # red stamp, already asserted — so this cannot pass by the corpus silently running nothing.
  mkdir -p "$d/src/scripts"
  printf '# HOST suites\ntests/bad.bats\n' > "$d/src/scripts/host-suites.manifest"
  fixture_land "partition the red suite out as a host suite"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "partition: a manifest suite is excluded from the tree verdict" \
    || badp "partition: manifest suite still counted in the verdict"
  # ── PRE-CORPUS WHOLE-TREE META-LINTS: verdict-affecting, standalone, and they SKIP the corpus ───
  # Exercises the DEFAULT prelint list (scripts/test-walltime-lint.sh), not an injected one, and the
  # absent-second-lint skip in the same pass. The tree is GREEN at this point (the partition block
  # above proved it), so a red here can only have come from the lint.
  printf '#!/bin/bash\necho "  RATCHET fixture.bats is grandfathered but fixed"\nexit 1\n' \
    > "$d/src/scripts/test-walltime-lint.sh"
  chmod +x "$d/src/scripts/test-walltime-lint.sh"
  fixture_land "a whole-tree lint that reds"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"red"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "prelint: a whole-tree lint red is a RED verdict" || badp "prelint: lint red not stamped red"
  grep -q 'test-walltime-lint' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "prelint: the stamp NAMES the failing lint" || badp "prelint: stamp does not name the lint"
  grep -q 'corpus SKIPPED' "$d/state/runner.log" 2>/dev/null \
    && okp "prelint: a lint red skips the corpus (decided answer, not re-derived)" \
    || badp "prelint: corpus ran anyway after a lint red"
  # POSITIVE CONTROL — the same tree, same wiring, lint exiting 0 must go back to GREEN, so the
  # test above cannot be passing merely because the fixture is red for some other reason.
  printf '#!/bin/bash\nexit 0\n' > "$d/src/scripts/test-walltime-lint.sh"
  fixture_land "the same lint, now clean"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "prelint: a clean lint lets the corpus decide (control)" || badp "prelint: clean lint still red"
  # ── §4.2.3 NO ADMISSION SLEEPING — asserted structurally, because its absence IS the feature ────
  # (the pattern is anchored to CODE — the block comment above deliberately still names the deleted
  # function, and a bare-name grep would read its own tombstone as the thing being forbidden)
  grep -qE '^[[:space:]]*gate_admit' "$SELF" \
    && badp "qos: gate_admit still present (the verifier must never wait on load)" \
    || okp "qos: no admission control anywhere in the runner"
  grep -qE 'nice -n 19' "$SELF" \
    && okp "qos: the corpus runs in the background band" || badp "qos: no background-band prefix"

  # ── SHARED-CONFIG IDENTITY — behavioural, through the real corpus path ───────────────────────────
  # The leak suite writes its identity exactly the way the incident did: a bare `git config
  # user.email` with NO -C and NO cd, which lands in whatever repo owns the cwd — and the corpus's
  # cwd is $WORKTREE, a linked worktree of $CC_POSTLAND_REPO, so it really hits the fixture repo's
  # shared config. Nothing is simulated here.
  #
  # That shape is also the one git-identity-lint deliberately does NOT convict (rule 2 needs a
  # preceding unguarded cd; with no cd there is no evidence to key on), which is what keeps this
  # test non-vacuous in two directions at once: the prelint cannot pre-empt the write, so the corpus
  # really runs it — and the case therefore proves the dynamic assertion catches precisely what the
  # static lint declines to. If someone later widens that rule, this test goes red by design,
  # because the fixture will stop reaching the corpus. That is the correct alarm, not a nuisance.
  printf '#!/usr/bin/env bats\n@test "leak" { git config user.email leak@leak.local; git config user.name leaker; }\n' \
    > "$d/src/tests/leak.bats"
  fixture_land "a suite that writes an identity into the shared config"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"red"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "identity: a corpus write to the shared config is a RED verdict" \
    || badp "identity: the shared config was mutated and the run still claimed a verdict"
  grep -q 'shared-config-identity' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "identity: the stamp NAMES the leak, not just 'some suite failed'" \
    || badp "identity: stamp does not name shared-config-identity"
  [ "$(git -C "$d/src" config --local --get user.email 2>/dev/null)" = "pv@selftest.local" ] \
    && okp "identity: the repo config was RESTORED to its run-start value" \
    || badp "identity: repo config left poisoned ($(git -C "$d/src" config --local --get user.email 2>/dev/null))"
  # POSITIVE CONTROL — remove the leak suite and the same tree must go back to GREEN, so none of the
  # three above can be passing because the fixture was red for some unrelated reason.
  rm -f "$d/src/tests/leak.bats"
  fixture_land "the leak suite removed"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "identity: a clean corpus is unaffected by the assertion (control)" \
    || badp "identity: the assertion reds a clean corpus — it convicts on something else"

  # ── the prelint wiring, and the argument contract that makes it safe ─────────────────────────────
  grep -qE 'PRELINTS=\(.*git-identity-lint\.sh' "$SELF" \
    && okp "prelint: git-identity-lint is in the blocking pre-corpus slot" \
    || badp "prelint: git-identity-lint NOT wired into PRELINTS"
  # The wiring is only safe because the slot stopped passing a positional. git-identity-lint scans a
  # repo ROOT, not a corpus dir; handed `tests` it exits 2, and prelint_check turns a 2 into
  # PRELINT_UNPROVEN — so every run would CUT and no tree could be stamped green again. Assert the
  # absence of that argument, because its presence is silent and fleet-fatal.
  # shellcheck disable=SC2016  # a literal search pattern: the $s must NOT expand here
  grep -qE '"\./\$s" \)' "$SELF" \
    && okp "prelint: lints are invoked with NO positional — each resolves its own scan root" \
    || badp "prelint: a positional is still passed — a root-scanning lint would exit 2 and CUT every run"
  grep -qE 'PRELINTS=\(.*subshell-cleanup-lint\.sh' "$SELF" \
    && okp "prelint: subshell-cleanup-lint is in the blocking pre-corpus slot" \
    || badp "prelint: subshell-cleanup-lint NOT wired into PRELINTS"
  # THIS file was the class's only live instance (see BISECT_CULPRIT), so the lint that closes the
  # class has to be reachable from the gate rather than only from its own suite. It is also the one
  # prelint whose cost was measured against the BAND: ~3.6s foreground over 356 files, ~300s at the
  # measured 84x tax, inside LINT_TO's 600s. A future change that makes it slow does not fail — it
  # CUTS, silently, on every run.
  # Resolved from $SELF, NOT from $WORKTREE: during a selftest the check cell has not been minted,
  # so a $WORKTREE-relative path is absent and this would fail for the wrong reason.
  [ -x "$(dirname "$SELF")/subshell-cleanup-lint.sh" ] \
    && okp "prelint: subshell-cleanup-lint is executable (prelint_check gates on -x)" \
    || badp "prelint: subshell-cleanup-lint is NOT executable — the slot would skip it silently"

  echo "postland-verify selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

usage() {
  echo "usage: postland-verify.sh [--run-if-needed | --run <sha> | bisect <file> <good> <bad> | is-green <sha> | status | --selftest]"
  echo "  kill switches: POSTLAND_VERIFY=off (inert) · POSTLAND_AUTOREVERT=off (verify+page, never push)"
  echo "  state: $STATE   ·   host partition: $MANIFEST_REL   ·   header comment = full design notes"
}

main() {
  if [ "${POSTLAND_VERIFY:-on}" = "off" ]; then            # runtime read — instant, side-effect-free
    printf 'postland-verify: DISABLED (POSTLAND_VERIFY=off)\n' >&2
    exit 0
  fi
  ensure_dirs
  # Installed for EVERY verb, before dispatch: `bisect` mints a cell too, and a verb-local trap is
  # exactly how a cleanup gets forgotten. selftest replaces it with its own (it mints nothing).
  trap cleanup_exit EXIT
  case "${1:---run-if-needed}" in
    --run-if-needed) do_run_if_needed ;;
    --run)      shift; do_run_one "${1:-}" ;;
    bisect)     shift; verb_bisect "$@" ;;
    is-green)   shift; verb_is_green "${1:-}" ;;
    status)     verb_status ;;
    --selftest) selftest ;;
    -h|--help)  usage ;;
    *) echo "postland-verify: unknown verb '$1'" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
exit $?
