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
# A BISECT MAY RETURN NO VERDICT, and four guards make it: the tip confirmation, the floor proof,
# the two bounds, and REACHABILITY (a commit whose diff cannot touch the failing subject is not a
# candidate — see bisect_reach_ok). On a non-verdict the page says NO VERDICT and names nobody;
# steps/elapsed/load-at-verdict ride beside every verdict so contention reads as contention.
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
#
# ── THE BOUNDING INVARIANT: every $BATS_BIN call is bounded, and the RUNNER'S is bounded THREE times
#    (measured 2026-08-08) ────────────────────────────────────────────────────────────────────────
# Backlog 36ed9b03e47a (filed 2026-07-29) read do_bisect's generated-runner bats as "the ONLY
# unbounded bats call in the file — a WEDGING suite hangs the singleton verifier". Its premise is
# literally true and its consequence is REFUTED; both halves are stated here because otherwise the
# next reader of that line re-files it. The runner's bats carries no `bounded` of its own BY
# CONSTRUCTION — the runner is never executed except through one, at all three of its call sites:
# the walk (`bounded "$BISECT_TO" git … bisect run`), the tip confirmation, and the floor check
# (both `bounded "$RETRY_TO" "$runner"`). The item also predates its own fix by a week: the wall
# landed as 7c32cc6f on 2026-08-05. Its lock clause is wrong on a third count — try_acquire never
# reaps a LIVE holder at any age, so LOCK_TTL cannot double a wedged verifier.
#
# WHAT ACTUALLY CONTAINS IT is the one word NOT in `bounded`: `--foreground`. Without it timeout(1)
# puts the child in its OWN process group and signals the whole group, so the kill reaches a bats
# nested two levels down inside `git bisect run`. Measured: a stub wedging 400s per step against a
# 3s wall ⇒ the SUT returns in 3s with ZERO survivors. The invariant is the process-group kill, NOT
# the presence of the token `bounded`.
#
# ...WHICH IS ONE TOKEN FROM SILENT FAILURE, and the two call-site shapes fail DIFFERENTLY. Adding
# `--foreground` leaves the WALK site loud — the orphan holds that site's `$( )` pipe open, so the
# SUT hangs 401s against a 3s bound and B1's wall-clock assertion goes red — and the TIP/FLOOR sites
# SILENT: they call the runner directly, with no command substitution to pin the parent, so the SUT
# returns in 4s with all 15 pre-existing assertions green while the wedged suite is reparented to
# PPID 1. That is the 2026-08-05 incident's exact shape (pid 57191, orphaned to PPID 1, alive
# 12h53m). B17 in tests/postland-verify-bisect-bound.bats is the assertion that sees it; B18 there
# is the call-site census, which is the half no runtime test can cover. The walk site is deliberately
# NOT given a survivor test — that block records why it would be unfalsifiable.
#
# ── THE VERIFIER IS EXEMPT FROM cc-bats ADMISSION CONTROL (2026-08-08) ───────────────────────────
# $BATS_BIN defaults to the bare name `bats`, which on this box PATH-resolves to ~/.claude/bin/cc-bats
# — an ADMISSION WRAPPER. When >=CC_BATS_MAX_ROOTS (2) other bats execution roots are live AND 1-min
# load/core is >=CC_BATS_MAX_LOAD_PER_CORE (2.0), it runs NOTHING and exits 75 (EX_TEMPFAIL): a
# DEFERRAL, explicitly "not a test result". Setting the ceiling to 0 is cc-bats' own documented
# admission-only kill switch, and it disables BOTH halves — this runner is never refused, and never
# mints a slot others are refused against.
#
# WHY THIS RUNNER AND NOT THE GENERAL CASE. This file DELETED its own admission control on purpose
# (see "NO ADMISSION CONTROL — deleted, not tuned" below, §4.2.3/R7: "the verifier is the one party
# that may never wait"), and then reached admission control anyway — through a bare NAME nothing here
# accounts for. Nothing in this file mentioned cc-bats before this line. The exemption restores the
# property R7 already asserted; it does not invent a new privilege.
#
# WHY A DEFERRAL IS WORSE HERE THAN ANYWHERE ELSE. rc 75 is not in the {0,1} set that speaks about the
# tree, so the ladder abstains, LADDER_UNPROVEN fires, and the WHOLE sweep stamps `cut` — no green
# stamp, so deploy-live stays fail-closed and needs --force. MEASURED, runner.log:
#     2026-08-07T23:29:53Z  ladder UNPROVEN for tests/cc-backlog-compact-race.bats
#                           — the re-run exited 75 ...; no verdict (cut, not red)
#     2026-08-07T23:29:53Z  CUT 488742fcb66a ... consecutive=2
# A ~3.4h sweep discarded to skip ONE re-run of ONE named test that costs ~1s at the utility band.
# The asymmetry is the whole argument: the load this deferral sheds is unmeasurable, the verdict it
# destroys is the only one that unblocks deploy.
#
# cc-bats ITSELF NAMED THIS HAZARD and did not close it — its admission block warns the refusal
# "inside the corpus, would present as a test failure in a repo that AUTO-REVERTS on red". This is
# that hazard, one level up: not a test failure but a whole-run non-verdict. Closing it there (a
# blanket cc-bats change) would weaken the bound for every caller; closing it here scopes it to the
# single background-clamped singleton that already holds run.lock.d and may never wait.
#
# SEAM SAFETY. Exported, so it reaches all SIX executing $BATS_BIN sites uniformly — the corpus in
# both its shapes (bounded, and the stall-watched leg), confirm_hang's per-file re-run, both
# retry_once legs, and do_bisect's generated probe runner — instead of six prefixes a seventh site
# would silently miss. (The other two sites, `--version` and `--count`, cc-bats classifies
# non-executing and never refuses; its own case (xvi).) It cannot blind cc-bats' own suite:
# tests/cc-bats-admission.bats unsets CC_BATS_MAX_ROOTS in setup() for exactly this reason ("an
# ambient value would decide the verdict instead of the test"), and suites nested inside a bats test
# skip the bound already (its case (x)).
export CC_BATS_MAX_ROOTS=0
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
# ONE TEMPLATE, TWO CONSUMERS — run_target mints the corpus's TMPDIR from it, and do_bisect mints the
# PROBE's from the same string whenever it has no live corpus dir to reuse. What must hold is that the
# adjudicator's TMPDIR is as LONG as the measurement's (see do_bisect's ADJUDICATOR ENV block for the
# 104-byte incident); a literal repeated at two call sites is exactly how a length delta comes back
# silently, so both sites share this name and cannot drift apart.
RUN_TMPL="postland-run.XXXXXX"
LOCK_TTL="${CC_POSTLAND_LOCK_TTL:-3600}"
SUITE_TO="${POSTLAND_SUITE_TIMEOUT_S:-10800}"  # wall BACKSTOP only — the primary bound is the TAP
# progress stall (POSTLAND_STALL_S, see run_target). 10800 (was 5400, was 2700): the background band
# yields to sessions by design, so a busy box legitimately runs the corpus past any tight wall —
# measured 2026-07-29, healthy runs CUT at 2737s AND 5437s with zero not-ok. Hangs are caught by the
# stall bound in ~15 min; this ceiling exists only for the case where the TAP writer itself wedges.
# THE PRE-PLAN GRACE — the bound for bats' COUNTING phase, the one phase that emits no TAP at all.
# `bats <403 files>` does not start testing when it starts. bats-exec-suite first runs
# bats-gather-tests over every file (bats 1.13.0, libexec/bats-core/bats-exec-suite:141), sourcing
# each one to enumerate its @tests, and only THEN prints `1..N` (:185). Nothing reaches the TAP
# stream during that pass — the file is 0 bytes — so tap_done is 0 BY CONSTRUCTION, and the stall
# watcher below, whose clock used to start at t=0, saw a perfectly healthy run as frozen from its
# very first poll. That is a FALSE CUT of a corpus that was never wedged, and the ledger cannot
# tell it from a real one (a cut is "nothing proven", so no suite is ever named).
# MEASURED 2026-08-10 under the REAL prefix (`nice -n 19 taskpolicy -c background` — the band the
# corpus actually runs in, not a bare foreground bench): 403 suites / 7487 tests gather in 72s at
# load 5.2. That is the QUIET number and it is NOT the one this bound has to fit. The same box at
# load 33-48 was measured still inside the counting pass at >600s with a 0-byte TAP and a live
# bats-exec-suite (docs/research/POSTLAND-CELL-BISECT-2026-07-29.md §3, defect 1) — and that was
# over 141 files. The corpus is 403 today, so that observation scaled by corpus is already past
# the 900s POSTLAND_STALL_S. The defect was filed as latent; it is no longer.
# DERIVED FROM THE CORPUS, NOT A CONSTANT — because a constant is exactly how this class recurs.
# The third tell in memory bound-must-fit-the-band-not-the-bench is "the corpus it scans GROWS, so
# headroom silently erodes" (136→218 suites in four days there; 141→403 here in two weeks).
# CORPUS_N is known one line before the watcher, so the grace sizes itself. 15s/suite = the
# 72s/403 = 0.18s measured quiet cost times the 84x background-band tax this repo has measured for
# long batch work (2514226e) — the WORST documented case, not the observed one, because the whole
# point is that the observed one is a foreground bench. Floored so a small corpus still gets a
# usable window (and so the `tests/` fallback corpus, which reports CORPUS_N=1 while gathering the
# whole directory, is never given LESS than the stall bound it has today), and clamped to SUITE_TO
# so the wall backstop always stays the outer bound. POSTLAND_PRE_PLAN_GRACE_S pins an absolute
# value; 0 disables the phase entirely and restores the t=0 clock (the kill switch).
# THE TRADE-OFF, STATED RATHER THAN HIDDEN. At today's 403 suites the grace resolves to 6045s, so a
# gather that genuinely WEDGES is now caught in up to ~100 min where the old clock caught it in 15.
# That is the right direction and not a reluctant compromise: a FALSE cut is indistinguishable from
# a real one in the ledger (a cut names no suite, so nothing is ever traced back to it), while a
# slow TRUE positive is merely slow — and it is still bounded, by the SUITE_TO wall three times
# further out. Detection latency for the rare case is the correct thing to spend to stop convicting
# the common one. If that latency ever needs to come down, the lever is a real progress signal for
# the counting phase, not a tighter blind wall: bats writes its discovered tests to TESTS_LIST_FILE
# under BATS_RUN_TMPDIR (which is ours, via TMPDIR=$RUN_TMP), so a future watcher COULD key on that
# file growing. Deliberately not done here — it reaches into bats' private layout, which is exactly
# the kind of coupling that silently stops matching when the producer changes shape.
PRE_PLAN_PER_SUITE_S="${POSTLAND_PRE_PLAN_PER_SUITE_S:-15}"
PRE_PLAN_FLOOR_S="${POSTLAND_PRE_PLAN_FLOOR_S:-900}"
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
# ── THE NON-VERDICT'S OWN OUT-PARAMETERS (2026-08-17, backlog ebbf3adfb4d0) ───────────────────────
# BISECT_CULPRIT already carried "undecidable" as the empty string, but that is one bit and the
# surfaces downstream need three more. WHY it abstained (a cut is a machine event, an unreachable
# candidate is a walk that convicted noise), and the two numbers that separate a REGRESSION from
# CONTENTION: how long the walk took and what the box's load was AT THE VERDICT.
#
# The load in $ENV_FP is captured at run START and is the corpus's, not the walk's — page
# postland-red-0f55846f7de4 carried `load 16.45` and nobody could tell whether that number was
# still true 20 minutes later when the bisect named its commit. A verdict reached at load 16 and a
# verdict reached at load 2 are different claims about the same sha, so the number belongs BESIDE
# the verdict, not only in a fingerprint taken before the walk began.
BISECT_STEPS=0     # walk steps actually run (0 = the walk never started)
BISECT_S=0         # wall seconds the walk spent, verdict or not
BISECT_LOAD=""     # 1-min loadavg read AT the verdict — empty when the instrument cannot be read
BISECT_WHY=""      # short slug: why there is no verdict. Empty iff BISECT_CULPRIT is set.
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
# net, so it is the one party that may never be the thing that waits. Instead the corpus is
# launched DEMOTED — nice 19 (scheduler) + `taskpolicy -c background` (throttled CPU *and* I/O
# tier, yields to interactive sessions). Wall time under load becomes DEPLOY LATENCY, never
# blockage. Seam: CC_POSTLAND_TASKPOLICY_BIN (set-but-EMPTY ⇒ nice alone, honored verbatim).
#
# ⚠️ THIS ARRAY DOES NOT DECIDE THE BAND THE CORPUS ACTUALLY RUNS IN — MEASURED 2026-08-11 (backlog
# 70dff02dcf4a). Read the two facts together before believing any band claim in this file:
#
#   1. $BATS_BIN is the bare name `bats`, which PATH-resolves to ~/.claude/bin/cc-bats (the note at
#      BATS_BIN says so for a different reason — admission control). cc-bats' own default band is
#      `utility`, and it EXECs `taskpolicy -c utility <real bats>`. taskpolicy sets a FRESH clamp on
#      the child — the LINT_QOS note below already relies on that — so cc-bats OVERRIDES the
#      `-c background` above. Sampled live on a real run: the corpus's bats processes read PRI 20,
#      not PRI 4. What this array actually clamps is the wrapper, not the work.
#   2. The one context where it is NOT overridden is a launchd job declaring `ProcessType
#      Background`, which applies Darwin's darwinbg TASK ROLE — a one-way floor. From inside it,
#      `taskpolicy -c utility` still reads PRI 4, and `taskpolicy -B -p <pid>` does not lift it
#      either. So the SCHEDULED lane ran at PRI 4 and the session-invoked lane at PRI 20, on the
#      same corpus and the same box: p50 3.11h vs 0.98h.
#
# The consequence that matters: the band was set by the PLIST, never by this array, and flipping
# this array to `utility` would have changed NOTHING in either population. The plist key was removed
# 2026-08-11 (launchd/com.claude.postland-verify.plist), which is what actually lets cc-bats' own
# `utility` clamp take effect on the scheduled lane. The array stays as-is because it is still the
# correct floor for any caller that supplies a REAL bats via CC_POSTLAND_BATS, bypassing cc-bats.
# Invariant pinned by tests/postland-band-floor.bats; derivation in LAND_PIPELINE_V2.md §8.
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
# a land but still cannot reach a green stamp.
#
# ── THE INSTRUMENT CHECK: `--selftest` RUNS HERE TOO (backlog 76644e76aaae, 2026-08-08) ───────────
# The caveat this block used to record — "this preserves the whole-tree SCAN, not the `--selftest`
# discrimination proof, which the prelint never invokes" — was true and it left the proof running
# NOWHERE automatically. Its three carriers had each gone dark for a different reason: the bats
# wrappers are partitioned to scripts/host-suites.manifest (so they run only post-deploy, a lagging
# check); scripts/nightly-regression.sh runs `--selftest` on every scripts/*lint*.sh but its launchd
# job is declared `staged` in launchd/fleet.manifest — an activation DECISION that is the operator's
# by construction (cc-fleet --table renders it `UNDECIDED … decision pending`, measured 2026-08-08
# as `staged: DISABLED`), never an agent's to make; and the prelint here only ever ran the scan. So
# the ~130 cases that prove these ratchets actually go RED on a new leak and on a stuck entry gated
# nothing. Read the declaration, not this sentence: whether that job is live is a perishable fact
# and fleet.manifest plus `cc-fleet --table` are the two places entitled to answer it.
#
# A SCAN AND A SELFTEST ANSWER DIFFERENT QUESTIONS, so they may not share a verdict column:
#   scan     exit 1 ⇒ THE TREE violates a rule      — attributable to a commit, RED, revert-eligible.
#   selftest exit 1 ⇒ THE LINT does not discriminate — a fact about the INSTRUMENT. It says nothing
#                     about the tree, and mapping it to RED would let a broken lint auto-revert a
#                     commit that never touched it. Worse, it retroactively voids the scan's GREEN:
#                     a ratchet that cannot fire reports "clean" on a dirty tree just as loudly.
# So a failed selftest lands in the category this file already has for "no claim about the tree is
# available" — PRELINT_UNPROVEN ⇒ CUT: never a red, and NEVER A GREEN either, with the CUT_MAX
# ladder escalating if it persists. It additionally SKIPS that lint's scan, because a red minted by
# an instrument already proven not to discriminate is exactly the auto-revert this guards against.
#
# THE OTHER DIRECTION IS DELIBERATELY NOT SYMMETRIC. A selftest that could not RUN (exit 2 / our own
# bound / not executable) marks the run unproven but LETS THE SCAN PROCEED. Suppressing the scan on
# an unrunnable instrument check would mean fork pressure — the very condition b4e49b4b5014 is about
# — could silently switch the ratchet off, which is the one failure direction this whole mechanism
# exists to prevent. Unproven-but-scanned is fail-closed toward MORE proof; unproven-and-skipped is
# not. A lint carrying no `--selftest` dispatch at all is skipped by the same rule as an absent
# lint, one clause below: a tree cannot be judged by a check it does not carry.
#
# COST, measured on this box 2026-08-08 at the UTILITY band the prelints run in, load 11.5:
# hermeticity 67s · walltime 5s · git-identity 4s · subshell-cleanup 1s = ~77s, against the 600s
# per-lint bound (~9x headroom on the slowest) and a corpus measured in hours. Sized in the band it
# actually runs in, not on a foreground bench — the 60s-bound deadlock below is what that costs.
# Seam: CC_POSTLAND_PRELINT_SELFTEST=off disables the instrument check (default on).
# STRICTNESS: the own-set seams are UNSET in the child (`${VAR+set}` is how both lints distinguish
# absent ⇒ judge the whole tree from set-but-empty ⇒ judge nothing), so an inherited own-set can
# never silently narrow the verifier's check to somebody else's diff.
# Seam: CC_POSTLAND_PRELINTS (space-separated, worktree-relative; set-but-EMPTY disables verbatim).
if [ -n "${CC_POSTLAND_PRELINTS+set}" ]; then
  # shellcheck disable=SC2206  # deliberate word-splitting: the seam is a space-separated list
  PRELINTS=($CC_POSTLAND_PRELINTS)
else
  # test-afunix-path-lint joined 2026-08-09, and THIS VERIFIER IS THE REASON IT EXISTS: an absolute
  # AF_UNIX bind is green everywhere except inside this run, because the 104-byte sun_path cap is
  # blown by this script's own $TMPDIR/postland-run.XXXXXX prefix (:1050,:1104) plus the test's name.
  # It kept tests/boot-resume-launch.bats in 17 of 17 reds across 40h while every hand-check said
  # green — including the re-run command this file PRINTS, which uses a short /tmp/pv-repro and so
  # exonerates the very file it is meant to convict. Correct that a prelint red skips the corpus: a
  # corpus verdict under that condition is a statement about path lengths, not about the tree.
  PRELINTS=(scripts/test-walltime-lint.sh scripts/test-hermeticity-lint.sh scripts/git-identity-lint.sh scripts/subshell-cleanup-lint.sh scripts/test-afunix-path-lint.sh)
fi
# 600s, raised from 60s (2026-07-30): a bound must fit what it BOUNDS, in the band it actually runs
# in. 60s was sized for a foreground ~3s lint and left no room for the band the launchd job imposes,
# so the whole-tree lint timed out and no green could be claimed — a deadlock the growing corpus
# (136→218 suites in four days) only tightened. The band fix above is the primary remedy; this is the
# belt: even with taskpolicy absent (LINT_QOS empty ⇒ background inherited) at the measured 84x tax,
# ~250s still fits with 2.4x headroom, while a genuinely WEDGED lint is still cut well inside
# SUITE_TO. Sized against its siblings, 60s was the lone foreground-scaled outlier here.
LINT_TO="${CC_POSTLAND_LINT_TIMEOUT_S:-600}"
# The instrument check (see the block above). Default ON: a sensor whose shipping path is "off" is a
# sensor that ships blindness, and this one exists precisely because the proof was running nowhere.
PRELINT_SELFTEST="${CC_POSTLAND_PRELINT_SELFTEST:-on}"
PRELINT_UNPROVEN=0     # a lint whose own bound fired: nothing proven ⇒ never a red, never a green
LADDER_UNPROVEN=0      # a RETRY whose own bound fired: same rule — a cut, never a red (C23)
# Most backlog items ONE red run may file (red_actions files every failing entry, not just the
# first). 25 is ~2.5x the worst run observed across 69 REDs in runner.log (10 entries), so it is a
# runaway backstop for a catastrophically-red tree rather than a routine limit — and when it does
# bite it LOGS the dropped names, because a silent cap is the same defect as filing FAILING[0] only.
BACKLOG_MAX="${CC_POSTLAND_BACKLOG_MAX:-25}"
# ── AUTO-REVERT (§4.2.4) ─────────────────────────────────────────────────────────────────────────
AUTOREVERT="${POSTLAND_AUTOREVERT:-on}"                 # kill switch: POSTLAND_AUTOREVERT=off
MAX_REVERTS="${POSTLAND_MAX_REVERTS:-2}"                # markers written THIS run before we stop
REPO_SHIP="${CC_POSTLAND_SHIP_BIN:-$REPO/scripts/ship-land.sh}"   # the land lane (the ONLY pusher)
SHIP_TO="${CC_POSTLAND_SHIP_TIMEOUT_S:-900}"            # bound on the revert land
REVERTS="$STATE/reverts"                                # <sha> marker ⇒ never reverted twice
REVERTS_THIS_RUN=0
# ── THE NEVER-TWICE MARKER IS BOUNDED (item 8e8a306f6dc0) ────────────────────────────────────────
# Census of this host's own runner.log, all-time to 2026-08-07: 25 encounters — landed=3, FAILED=5,
# skipped=17, and every one of the 17 skips read `reason=already-attempted`. The actuator therefore
# actuated on 12% of the occasions it was asked to. The skips are four culprits, not one as first
# filed: a1743ffebd35 ×3, 47a5350498ee ×3, 57e162494c10 ×3, b3f728858a6f ×8 (2026-08-04 → 08-07).
# The shape is the same in every case and it is Law 2 of the inertness generator living INSIDE the
# safety mechanism: "attempted once" is a STATE, states outlive their premises, and this one then
# governs forever. A veto that cannot actuate is a permission gate in disguise — §9 of
# docs/research/inertness-generator-2026-08-07.md, which narrows the pure-veto law to "no gate on an
# actuation path may be unbounded; every permission predicate carries a finite budget whose expiry
# converts the standing state into an EVENT". These two knobs are that budget.
#
# The bound is ASYMMETRIC BY OUTCOME, because the two markers record different facts:
#   land_exit=0  — the revert LANDED. The culprit's content is out of trunk and a second revert
#                  would re-apply the bad change. That premise does not rot; the skip stays
#                  permanent. It is no longer SILENT (see revert_rearm) — b3f728858a6f skipped
#                  eight times across 2.5 red days and told nobody.
#   land_exit!=0 — the revert did NOT land. That is a fact about ONE trunk tip (rc 90 = the revert
#                  conflicted off THAT tip; rc 6 = the land lane refused THAT attempt), and the next
#                  tip is new evidence. Re-arm on a moved tip or on decay, RETRY_MAX attempts total.
REVERT_RETRY_MAX="${POSTLAND_REVERT_RETRY_MAX:-3}"      # attempts per culprit before the skip is terminal
REVERT_RETRY_DECAY_S="${POSTLAND_REVERT_RETRY_DECAY_S:-21600}"   # 6h — an UNMOVED tip re-arms on time alone
ATTEMPT_N=1                                             # which attempt this is, for the marker
STAMPS="$STATE/stamps"
LOCK="$STATE/run.lock.d"
LOG="$STATE/runner.log"
FLAKES="$STATE/flakes.jsonl"
LASTGREEN="$STATE/last-green"
QUEUE="$STATE/queue"
CUTS="$STATE/cuts"                                     # "<tree> <consecutive-n> <epoch>"
CUT_MAX="${CC_POSTLAND_CUT_MAX:-3}"                    # consecutive cuts on one tree before paging
CUT_COOLOFF="${CC_POSTLAND_CUT_COOLOFF:-1800}"         # ...and before the box is fed another suite
# ── C29 CROSS-WINDOW CORROBORATION — the ladder's three runs are ONE experiment ───────────────────
# classify_failures re-runs a failing test twice more BACK TO BACK: seconds apart, on the same box,
# inside the same run. Its three observations therefore sample ONE LOAD WINDOW, so ">=2/3 agreed"
# means only "it failed twice under the same ambient load" — which is what a starved box produces
# exactly as reliably as a bug. GATE_ARCHITECTURE_PLAN.md already records the governing law one
# variable off: "re-running is evidence only if the environment actually changed" (written about a
# ladder that re-ran under the same wrong PATH three times and called the agreement reproducible).
#
# THE BAND AXIS WAS ALREADY TRIED, AND IT IS NOT ENOUGH — this is the load-bearing fact, and it is
# why this clause is not a duplicate of C24. C24 (08dd4e3c, 2026-07-31) closed the FIRST half of
# that law by elevating the re-run OUT of the corpus's background clamp into utility, so the retry
# genuinely does run in a different environment now. It helped and it stays. But the environment it
# varies is PRIORITY, not AMBIENT LOAD: a box at load 15 is at load 15 for all three attempts, and
# a suite losing to memory/IO pressure loses in the utility band too. MEASURED on this box over the
# 100 stamps on disk, split at C24's own landing:
#     PRE  C24 (n=46): 42 red · 1 green · 2 cut · 1 hung — 7 of 34 consecutive red pairs DISJOINT
#     POST C24 (n=54): 48 red · 2 green · 4 cut        — 7 of 47 consecutive red pairs DISJOINT
# The fingerprint SURVIVED the band fix. A genuine red re-convicts the SAME file until somebody
# fixes it; a convicted set that reshuffles sweep to sweep (prev=11 now=2 overlap=0 · prev=12 now=1
# overlap=0 · prev=9 now=1 overlap=0) is the box talking, not the tree. Two greens in 54 sweeps, and
# a red is not merely a wrong stamp — it is terminal for that tree (C5 abstains on it forever) and
# it arms the bisect and AUTO-REVERT, which pushes a revert of an innocent commit to trunk.
#
# THIS IS AN EVIDENCE AXIS, NOT MORE RETRIES. §8 of LAND_PIPELINE_V2 forbids the "raising the
# ceiling / more retries / bigger budgets" class outright as parameter motion inside a broken frame,
# so be precise about what this is: nothing below adds an attempt, a poll, a sleep or a budget, and
# the in-run ladder costs exactly what it cost before. What changes is what ONE window's agreement
# BUYS — a conviction seen in one window becomes an ABSTENTION (the C23 shape: neither convicted nor
# cleared ⇒ cut ⇒ retried next sweep), and the second observation then arrives FREE, on the sweep
# that retry was already going to run.
#
# AND IT NEVER WAITS FOR A QUIET BOX (R1; LOAD_INSENSITIVE_VERIFY_V2.md — "no quiet period will ever
# exist… any design whose success requires load to fall is already failed"). The gate is SEPARATION
# IN TIME, which the clock always eventually satisfies; it is emphatically NOT "a lower load", which
# this box may never offer and which would deadlock exactly the way gate_admit did. Load is RECORDED
# per observation, as evidence a human can read, and is never tested by anything — a --selftest
# assert anchored to statement position forbids any if/while/until branch on it.
CONVICTIONS="$STATE/convictions"                       # TSV "<epoch>\t<file>\t<tree>\t<sha>\t<load>"
CONVICT_MODE="${CC_POSTLAND_CONVICT:-on}"              # kill switch: off ⇒ a one-window red again
CONVICT_TTL="${CC_POSTLAND_CONVICT_TTL_S:-86400}"      # an observation older than this is stale
CONVICT_SPREAD="${CC_POSTLAND_CONVICT_SPREAD_S:-900}"  # min separation of the two windows. A corpus
# run measures 50 min - 3.4 h (run_s on the stamps above), so consecutive sweeps clear this floor by
# construction and it is never the thing delaying a real conviction; it exists so that two runs that
# somehow land back-to-back cannot both count as "windows". Tests shrink it to 0 the same way they
# shrink every other bound — which removes the WALL-CLOCK floor ONLY: the two-SWEEP requirement, the
# actual guard, stays live in every test in the suite.

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
RETRY_BOUND_S=""   # retry_once's out-parameter: WHICH of the two bounds that call ran under
# INDEX-ALIGNED with FAILING: the failing TEST name for FAILING[i], so every filed item is
# actionable and not just the first. FAILTEST (one name, the first) is unchanged and still what the
# page/notify render; this is the per-file version red_actions needs to file the whole list. Every
# push site appends to BOTH — but red_actions still reads it as `${FAILNAME[i]:-}`, because
# SYNTAX_BAD is spliced onto FAILING wholesale after the fact and pads nothing.
FAILNAME=()
# C29: the subset of FAILING the LADDER convicted — i.e. the load-attributable ones, and the only
# population cross-window corroboration adjudicates. Deterministic reds (bash -n, the whole-tree
# prelints, the C13b sentinel) never enter it and are never delayed: they reproduce by construction,
# so a second window cannot tell them anything.
LADDER_FAILING=()
CONVICT_PENDING=0    # a ladder conviction seen in ONE window only: nothing proven yet ⇒ cut
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
# cond_slug <failing-entry> → a cc-backlog `--condition` key naming the RECURRING STATE
# "this suite is red on trunk", so re-filing it next sweep is idempotent instead of minting a
# second item. cc-backlog's valid_condition() accepts LOWERCASE LETTERS AND HYPHENS ONLY — no
# digits, no leading/trailing/doubled hyphen, <=64 — and REFUSES the whole add (rc 2) otherwise.
# That refusal is why the digits are SPELLED OUT rather than stripped: this call site is
# `|| true`'d best-effort, so a rejected add is silent, and stripping would have made the filing
# structurally blind to exactly the 10 of 305 suites whose names carry a digit (it2-kitty,
# iterm2-appname-lint, cc-dispatch-v2, subagent-stop-r1, …) — i.e. it would have re-created THIS
# bug's own invisibility for a different subset. Spelling keeps them distinct and filable.
# Verified over all 305 tests/*.bats plus the PRELINTS and the `shared-config-identity` literal:
# 0 rejected, 0 collisions, longest key 49 chars. `tests/` (the branch-(b) sentinel, which has no
# basename) folds to `unattributed` rather than the empty string valid_condition would reject.
cond_slug() {
  local s="${1##*/}"
  s="${s%.bats}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/0/-zero-/g'  -e 's/1/-one-/g'   -e 's/2/-two-/g' \
              -e 's/3/-three-/g' -e 's/4/-four-/g'  -e 's/5/-five-/g' \
              -e 's/6/-six-/g'   -e 's/7/-seven-/g' -e 's/8/-eight-/g' \
              -e 's/9/-nine-/g'  -e 's/[^a-z-]/-/g' \
        | sed -e ':a' -e 's/--/-/g' -e 'ta' -e 's/^-//' -e 's/-$//')"
  [ -n "$s" ] || s=unattributed
  printf 'postland-red-%s' "${s:0:50}"      # 13 + 50 = 63, inside valid_condition's 64
}
# file_linked <failing-entry> <title> <falsifier> — mint a TITLE-KEYED item and JOIN it to the
# condition group cond_slug() gives that suite, so cc-backlog's claim guard (6) can SEE it.
#
# THE DEFECT THIS FIXES (backlog 4f657ed3e064, 2026-08-11). This file has FOUR mint sites and
# exactly one of them — red_actions' per-entry loop — was condition-keyed. The other three
# (AUTO-REVERT <outcome>, AUTO-REVERT INERT, HUNG) were title-keyed on a sha or a tree, so one red
# episode on ONE suite minted TWO rows carrying two ids and no shared field. Measured on
# tests/cc-backlog-venue.bats @ 508c2b9db0ea: fd458e142ddc ("post-land RED") and 28740c313840
# ("post-land AUTO-REVERT FAILED") are the same (file, culprit) pair, both were dispatched, and two
# workers fixed it in parallel and collided at the rebase — 28740c313840's own closing evidence
# records it ("the cure landed on trunk from a sibling worker … my redundant commit reconciled
# away"). That is the 97f16b6709fa / 6078392359ac incident again, in a different producer.
#
# WHY BOTH VERBS AND NOT `add --condition`. Handing these three sites a condition at `add` would not
# dedupe the pair, it would DELETE the second item's CONTENT: `--condition` derives the id FROM the
# condition (cc-backlog § CONDITION KEY), so one suite can hold only one row, and cmd_add returns
# early with rc 0 on a known id. An AUTO-REVERT FAILED filed under a live RED condition would
# therefore write nothing at all — and its remedy is the one in this whole file that needs a HUMAN
# (resolve a revert conflict by hand), so its title, its branch and its falsifier would exist only
# in a page a green deletes. `link` sets the field WITHOUT touching the id or the status, which is
# precisely the verb cc-backlog's § CONDITION LEASE says exists "for a row minted from its title
# before anyone knew it was a sibling". Both rows survive; the LEASE, not the mint, is what stops
# the second dispatch — and cc-dispatch step 5a already journals that refusal as a SKIP
# (verdict=sibling-held), so the whole downstream path was built and waiting on a producer.
#
# THE VERDICT IS COUNTED, NOT ASSUMED (memory: claimed-outcome-vs-checked-outcome). `link` returns
# 4 when the row is already on a DIFFERENT condition and 2/3 on a bad slug or unknown id; a filed
# item that did not get linked is invisible to guard (6), which is the exact state being fixed, so
# it is logged as its own verdict token rather than folded into the success line.
file_linked() {
  local fentry="$1" title="$2" falsifier="$3" cond bid lerr lrc
  [ -x "$BACKLOG_BIN" ] || return 0
  bid="$("$BACKLOG_BIN" add --title "$title" --falsifier "$falsifier" \
           --project claude-infrastructure --source postland-verify 2>/dev/null)"
  # An id is the ONE thing `link` cannot proceed without, and cmd_add echoes it on the idempotent
  # path too — so an empty capture is a real add failure, never a re-file.
  if [ -z "$bid" ]; then
    log "backlog verdict=add-failed entry=$fentry — NOT filed: ${title:0:90}"
    return 0
  fi
  cond="$(cond_slug "$fentry")"
  lerr="$("$BACKLOG_BIN" link "$bid" --condition "$cond" 2>&1 >/dev/null)"; lrc=$?
  if [ "$lrc" -eq 0 ]; then
    log "backlog verdict=filed+linked id=$bid condition=$cond entry=$fentry"
  else
    log "backlog verdict=filed-UNLINKED rc=$lrc id=$bid condition=$cond entry=$fentry — claim guard (6) cannot see it, so this row can be dispatched beside its sibling: ${lerr//$'\n'/ }"
  fi
  return 0
}
tree_of() { git -C "$REPO" rev-parse "$1^{tree}" 2>/dev/null; }
env_fingerprint() { # sets ENV_FP — a verdict is NOT a pure function of the tree (tool bumps happen
  local b c l                                # constantly), so a stale-env green stamp stays diagnosable
  # `bounded` like every other $BATS_BIN call (see THE BOUNDING INVARIANT at BATS_BIN) — this was the
  # file's one real exception until 2026-08-08. It executes no test, so on a healthy box the bound is a
  # formality; it is here because an invariant with a remembered exception is one a census cannot
  # check, and because this call runs BEFORE the corpus, where a $BATS_BIN on a wedged network mount
  # would hang the run with no other bound watching. A cut leaves $b empty ⇒ "unknown" below, which
  # is the same honest rendering any other failure already gets.
  b="$(bounded 20 "$BATS_BIN" --version </dev/null 2>/dev/null | awk '{print $2}')"
  c="${CLAUDE_CODE_EXECPATH:-}"; [ -n "$c" ] && c="$(basename "$c")" || c=unknown
  l="$(load1)"                                                               # 1-min, at run start
  # `?`, never `0`: an unread instrument must not render as a value the reader would call healthy.
  # qos-census's loadavg1 column already answers this way; the stamp now agrees with it.
  ENV_FP="$(printf '{"bats":"%s","cc":"%s","load":"%s"}' "${b:-unknown}" "${c:-unknown}" "${l:-?}")"
}

# ════ mutex — {pid,lstart} identity, the same rule land-lock.sh:lock_is_stale uses ════════════════
# THE COPY THAT DROPPED THE IDENTITY CHECK (fixed 2026-08-11). The header used to read "shape copied
# from land-lock.sh" while carrying only half of it: the holder was recorded as a bare pid and any
# `kill -0` success was read as "the holder is alive". A pid is not an identity — the OS recycles it —
# so a holder that DIED and whose pid was later handed to an unrelated process read as permanently
# live. And it wedged FOREVER, not just for a while: $LOCK_TTL is consulted ONLY in the empty-holder
# branch, so the escape every other lock in this repo has was unreachable on exactly the branch that
# needed it. Reproduced against the pre-fix function: lock dir aged 208572449s with TTL=900 and a live
# unrelated pid in $LOCK/pid ⇒ try_acquire REFUSED. Both consumers (do_run_if_needed, do_run_one) then
# `idl abstained lock-held` and return 0, so `--run-if-needed`/`--run` silently stopped stamping —
# the verifier looks healthy and verifies nothing. Same class land-lock.sh already fixed on 2026-07-25.
#
# THE RULE (identical semantics to lock_is_stale; POSIX-test dialect because this file is `[ ]`, not
# `[[ ]]`): a holder is genuinely alive iff its pid is alive AND that pid's CURRENT start time equals
# the one recorded when the lock was taken. A live pid with a DIFFERENT lstart is a stranger, so the
# real holder is dead ⇒ reap. A live pid with a MATCHING lstart is never reaped at any age — H2 is
# unchanged, and it is what keeps this a mutex instead of "always reap".
#
# ── THE IDENTITY MUST BE READ THROUGH A LOCALE-PINNED INSTRUMENT (C33, 2026-08-11) ────────────────
# The rule above compares a string RECORDED by one process to a string READ FRESH by another. That
# is only an identity comparison if both processes render the same instant the same way — and
# `ps -o lstart=` does not: it formats through LC_TIME, so the SAME live pid reads
#     "Tue Aug 11 15:20:07 2026"   from the launchd daemon (no LANG in launchd's env ⇒ C locale)
#     "Tue 11 Aug 15:20:07 2026"   from an interactive session (LANG=en_CA.UTF-8 on this box)
# Both are /bin/ps; only the locale differs. So a session-fired `--run-if-needed` read the daemon's
# perfectly valid record, found "a DIFFERENT lstart", took the `stranger ⇒ holder DEAD ⇒ reap`
# branch on a LIVE holder, and started a SECOND full-corpus verifier beside the first.
#
# THIS IS THE CUT ENGINE, not a latency bug. Measured on this box 2026-08-11: two 441-suite corpus
# runs live at once (launchd pid 22960 and session pid 34453, whose start times are 7 min apart and
# whose lock the second one owned), 8 of the 9 overlapping run-pairs in the whole 170-stamp history
# dated to that one day. Two concurrent corpora on one box is self-inflicted machine pressure, and
# machine pressure is what the runner then reports back as a verdict about the TREE: 14 stamps read
# `the run was KILLED by signal 15|9 (machine pressure, not the tree)`, ~50% of recent cuts. A cut
# proves nothing, so no green can be earned, so deploy-live converges only through T2 DEGRADED and
# nothing reaching the live layer is full-suite-proven. The fix is one word at two sites; the
# symptom it was being read as ("per-suite reliability under load") had zero real intermittent
# assertion failures behind it in the trailing 7 days.
#
# FAIL DIRECTION, restated because this bug INVERTED it: an unverifiable identity must make the
# reader MORE patient, never less. `stranger ⇒ reap` is the only branch here that can produce two
# live verifiers, so nothing may reach it except a genuine mismatch of two canonically-rendered
# strings — hence the empty-`cur` guard below, which previously fell through to it whenever the
# instrument simply could not be read.
#
# MIGRATION: a lock still on disk from a pre-C33 process is honoured iff its record was rendered in
# C anyway (the daemon's always was — launchd has no LANG), and is reaped once otherwise. That is a
# strict improvement on the steady state being fixed, where the reap happened every sweep.
proc_lstart() { # <pid> → that pid's start time, rendered CANONICALLY (locale-pinned) and trimmed.
  # LC_ALL, not LC_TIME: LC_ALL outranks every other locale variable, so one export cannot be
  # defeated by an LC_TIME the caller also set. Trimmed because `ps -o lstart=` pads to a fixed
  # column width — a difference in trailing blanks is not a difference in identity, and comparing
  # untrimmed strings would re-introduce this same class the next time a ps changes its padding.
  LC_ALL=C ps -o lstart= -p "${1:-$$}" 2>/dev/null | sed 's/^ *//;s/ *$//'
}
lock_claim() { # write the holder identity into a lock dir THIS process just mkdir'd
  # ORDER MATTERS: lstart first, pid last. A racing acquirer reads pid first, so publishing pid last
  # makes "pid present" imply "lstart present" — the mid-acquire window is the empty-holder branch
  # (5s grace) rather than a lock that looks like a pre-fix one. Hence the no-lstart case below is
  # exclusively a PRE-FIX process, never a race.
  printf '%s\n' "$(proc_lstart $$)" > "$LOCK/lstart" 2>/dev/null || true
  printf '%s\n' "$$" > "$LOCK/pid"
}
try_acquire() {
  mkdir "$LOCK" 2>/dev/null && { lock_claim; return 0; }
  local holder age stale rec cur
  holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
  # Trimmed on READ as well as on write (C33): a record written before proc_lstart existed carries
  # ps's column padding, and the comparison below must not convict a live holder over blanks.
  rec="$(sed 's/^ *//;s/ *$//' "$LOCK/lstart" 2>/dev/null || true)"
  age="$(( $(now_epoch) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))"
  stale=0
  if [ -z "$holder" ]; then { [ "$age" -ge 5 ] || [ "$age" -gt "$LOCK_TTL" ]; } && stale=1
  elif ! kill -0 "$holder" 2>/dev/null; then stale=1   # holder pid DEAD → reap immediately
  elif [ -z "$rec" ]; then
    # COMPATIBILITY RULE — pid but NO lstart: a lock taken by a PRE-FIX process (only possible
    # during the one migration window; see the ORDER MATTERS note above). Its identity is
    # UNVERIFIABLE, so it is honoured like a live holder — but bounded by $LOCK_TTL, never forever.
    # This DIVERGES from land-lock.sh, which treats a missing lstart as live indefinitely: that is
    # the very wedge being fixed here, and an unverifiable holder is exactly the case a TTL exists
    # for. Fail-safe direction: too-patient (a stale pre-fix lock costs up to LOCK_TTL of latency)
    # rather than too-eager (two live verifiers on one box).
    [ "$age" -gt "$LOCK_TTL" ] && stale=1
  else
    cur="$(proc_lstart "$holder")"
    # EMPTY cur is NOT a mismatch — it is an unreadable instrument (C33). `ps` returning nothing for
    # a pid `kill -0` just proved alive means the probe failed, not that the holder is a stranger,
    # and routing that through the reap branch is how an instrument failure becomes two live
    # verifiers. Same fail-safe direction as the missing-lstart branch above: honour, TTL-bounded.
    if [ -z "$cur" ]; then
      [ "$age" -gt "$LOCK_TTL" ] && stale=1
    else
      [ "$rec" != "$cur" ] && stale=1                  # pid REUSED by a stranger → holder DEAD → reap
    fi
  fi                                                   # rec = cur → genuinely alive → NEVER reaped
  if [ "$stale" = 1 ]; then
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null && { lock_claim; return 0; }
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
# Does this file carry a real `--selftest` DISPATCH? 0 = yes · 1 = no · 2 = the check could not RUN.
# THE REGEX IS NOT NEW — it is scripts/nightly-regression.sh's `supports_selftest`, S4-hardened after
# its naive form (`grep -qE -- '--selftest|selftest\)'`) proved to be a false-positive machine: it
# matched a `--selftest` in a USAGE comment, a `selftest)` verb-only case whose CLI then rejected the
# flag, and a cosmetic mention in a log name. A false positive here is a lint fed a flag it does not
# understand, whose exit code we would then read as a verdict about the instrument. Keep the two in
# step; postland-verify's own --selftest asserts this predicate fires on all four default PRELINTS,
# which is the positive control that stops a drifted regex from silently reading as "none support it".
# THREE states, not two. A bare `grep -q` conflates rc=2 (grep could not run — the fork-exhaustion
# case this whole file is scarred by) with rc=1 (no match), and that conflation would silently
# down-grade a supported lint to "no instrument check" under exactly the load where it matters most.
prelint_has_selftest() { # <path> → 0 supported · 1 not supported · 2 unknown (could not check)
  grep -qE '^[[:space:]]*\(?[-|A-Za-z0-9_*."]*--selftest[-|A-Za-z0-9_*."]*\)|(^|[^[:alnum:]_])case[[:space:]].*[[:space:]]in[[:space:]].*--selftest[-|A-Za-z0-9_*."]*\)|==?[[:space:]]*"?--selftest"?' \
    "$1" 2>/dev/null
  local rc=$?
  [ "$rc" -le 1 ] && return "$rc"
  return 2
}
prelint_invoke() { # <script> <outfile> [argv…] → rc. THE one invocation shape, so the band, the
  # bound and the own-seam unsets can never drift between the instrument check and the scan.
  # `unset` inside the subshell, NOT `env -u`: env execs a binary and could never run the
  # `bounded` FUNCTION, which has to stay the outer call so the bound owns the process group.
  # `${LINT_QOS[@]+"${LINT_QOS[@]}"}` — NOT a bare "${LINT_QOS[@]}": this is bash 3.2 under `set -u`,
  # where expanding an EMPTY array unguarded is an unbound-variable death (the taskpolicy-absent
  # path). QOS above needs no such guard because it is never empty. `"$@"` IS safe empty — it is a
  # positional expansion, not an array one — which is what keeps the scan's "no positional arg"
  # contract below exact rather than passing an empty string.
  local sc="$1" so="$2"; shift 2
  ( cd "$WORKTREE" && unset CC_HERM_OWN CC_WALLTIME_OWN SHIP_LAND_HERM_OWN_SCOPE
    bounded "$LINT_TO" ${LINT_QOS[@]+"${LINT_QOS[@]}"} "./$sc" "$@" ) > "$so" 2>&1
}
prelint_check() { # whole-tree meta-lints, standalone, BEFORE the corpus. Appends any RED to FAILING
  # (so it flows through the existing verdict chain: FAILING non-empty ⇒ RED, and it OUTRANKS a cut
  # — which is the point, a deterministic named violation must never be filed as "nothing proven").
  local s rc out first why sout src has
  PRELINT_UNPROVEN=0                        # reset BEFORE the early return — the requeue loop
  [ "${#PRELINTS[@]}" -eq 0 ] && return 0   # calls run_target twice in one process
  for s in "${PRELINTS[@]}"; do
    [ -n "$s" ] || continue
    # ABSENT from this tree ⇒ skipped, never red: a tree cannot be judged by a check it does not
    # carry (an older sha predates the lint, and convicting it would make history unverifiable).
    [ -x "$WORKTREE/$s" ] || { log "prelint: $s absent from this tree — skipped"; continue; }
    # ── THE INSTRUMENT CHECK — does this lint still DISCRIMINATE? (backlog 76644e76aaae) ─────────
    # Runs BEFORE the scan, because its answer decides whether the scan's answer means anything.
    # See the PRELINTS block above for the full verdict-column argument; the three outcomes are:
    #   0 ⇒ proven, scan on.   1 ⇒ THE LINT IS BROKEN: unproven (never red, never green) + scan
    #   SKIPPED.               other ⇒ the check could not be MADE: unproven, but scan STILL RUNS.
    if [ "$PRELINT_SELFTEST" != off ]; then
      prelint_has_selftest "$WORKTREE/$s"; has=$?
      if [ "$has" -eq 2 ]; then
        PRELINT_UNPROVEN=1
        log "prelint: $s — could not determine whether it carries a --selftest (grep would not run); instrument unproven, scanning anyway"
      elif [ "$has" -eq 1 ]; then
        # Same rule as an absent lint: no dispatch means no proof is on offer, and inventing a
        # non-verdict for every run would deadlock any custom CC_POSTLAND_PRELINTS list forever.
        log "prelint: $s ships no --selftest dispatch — instrument check skipped (scan still judged)"
      else
        sout="$RUN_TMP/prelint.$(basename "$s").selftest.out"
        prelint_invoke "$s" "$sout" --selftest
        src=$?
        if [ "$src" -eq 0 ]; then
          log "prelint: $s --selftest proven — the instrument discriminates"
        else
          PRELINT_UNPROVEN=1
          # The lints' own selftests announce failure on the LAST line ("… FAILED — the ratchet does
          # not discriminate") and name the individual case on a `SELFTEST FAIL:` line, so prefer the
          # named case and fall back to the summary. Quoted INTO the log, not pointed at: $RUN_TMP is
          # removed when run_target returns, so a "see <path>" breadcrumb is dead before anyone reads it.
          why="$(grep -aE 'SELFTEST FAIL|FAILED|⛔|✗' "$sout" 2>/dev/null | head -1 | cut -c1-160)"
          [ -n "$why" ] || why="$(sed -n '$p' "$sout" 2>/dev/null | cut -c1-160)"
          if [ "$src" -eq 1 ]; then
            CUT_WHY="the LINT is broken, not the tree: $s --selftest does not discriminate — ${why:-（no output)}"
            log "prelint INSTRUMENT-BROKEN: $s --selftest exit 1 — ${why:-（no output)}; its scan is SKIPPED (no red may be minted by a lint proven not to discriminate) and no green is claimable"
            continue
          fi
          case "$src" in
            124) log "prelint: $s --selftest hit OUR ${LINT_TO}s bound — instrument unproven, scanning anyway" ;;
            *)   log "prelint: $s --selftest exit $src — the instrument check could not be MADE; unproven, scanning anyway — ${why:-（no output)}" ;;
          esac
        fi
      fi
    fi
    out="$RUN_TMP/prelint.$(basename "$s").out"
    # The band/bound/own-seam mechanics moved to prelint_invoke above (one shape, two call sites).
    # NO POSITIONAL ARG — each lint resolves its OWN scan root from its own $0. This used to pass a
    # literal `tests`, which was correct only because both lints then in the list happen to default to
    # `${1:-$ROOT/tests}`, i.e. the argument re-stated their default. git-identity-lint does not scan a
    # corpus dir — it defaults to `${1:-$ROOT}` and walks tests/ + scripts/ + bin/, because bin/ and
    # scripts/ carry real identity writes. Handing IT `tests` makes it look for tests/tests, tests/scripts
    # and tests/bin, find nothing, and exit 2 = NON-VERDICT — which prelint_check below turns into
    # PRELINT_UNPROVEN, so EVERY run would become a CUT and no tree could ever be stamped green again.
    # Measured before wiring: `git-identity-lint.sh tests` → exit 2 "nothing to scan"; no arg → exit 0,
    # 490 files, clean. The other two are unchanged by this: verified exit 0 both with and without it.
    prelint_invoke "$s" "$out"
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
    FAILNAME+=("${first:-whole-tree lint exit $rc}")     # index-aligned with the push above
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
# 🚨 RESTORE-TO-SNAPSHOT WAS THE RECURRENCE ENGINE (fixed 2026-08-08). "Restore the run-start value"
# is only a repair if the run-start value was RIGHT. It was not. A sweep that begins while
# .git/config already holds `user.email=t@e.com` snapshots the poison, and at the end faithfully
# writes it back — so the guard built to undo a corpus leak instead PINNED it, re-applying it after
# every clean-up, for as long as sweeps kept running. Measured: pid 27946 snapshotted the poison at
# 01:40 on 2026-08-08, a human unset it at 02:13, and the sweep would have restored it at ~04:40.
# That is why the 2026-08-05 fix "landed" and the operator still saw `t` on GitHub three days later.
#
# The repair now restores the snapshot ONLY when the snapshot is itself acceptable — absent, or the
# sanctioned identity. A poisoned snapshot is DROPPED rather than re-applied, which is always safe
# here because the correct identity lives in the global config and an absent local override simply
# lets it through. Either way the run still goes RED, so the leak is still found: this narrows what
# the guard WRITES, never what it REPORTS.
#
# Side-car discipline (memory: addon-failure-exceeds-its-blast-radius): this may never fail wider than
# itself. Every git call is best-effort, an unreadable snapshot means "cannot judge" and stays silent
# rather than fabricating a red, and only a genuine non-empty DIFFERENCE convicts.
identity_snapshot() { git -C "$REPO" config --local --get-regexp '^user\.' 2>/dev/null | sort || true; }
# A snapshot is restorable iff it cannot itself mis-author a commit: no local override at all, or one
# whose email is the sanctioned address. Anything else is the fault, not the baseline.
identity_snap_ok() {
  local snap="$1" want em
  # Sealed like the hooks: an env var that can widen this predicate is a bypass, not a seam.
  if [ "${CC_GIT_IDENTITY_TEST:-}" = 1 ]; then want="${CC_GIT_IDENTITY_EMAIL:-ren.chris@outlook.com}"
  else want="ren.chris@outlook.com"; fi
  [ -z "$snap" ] && return 0
  # LAST, not first. `user.email` is multi-valued when .git/config carries two [user] sections,
  # and git's effective author is the LAST one — measured. An `awk … exit` read the FIRST, i.e.
  # the opposite end of the list from the arbiter, so a config whose good value precedes a bad one
  # read "sanctioned" to the oracle while git committed with the bad one.
  em="$(printf '%s\n' "$snap" | awk '$1=="user.email"{v=$2} END{print v}')"
  [ "$em" = "$want" ]
}
identity_assert() {  # compare against $IDENTITY_SNAP, restore it if SAFE, and convict on any change
  local now line k v
  [ -n "${IDENTITY_SNAP+set}" ] || return 0        # never snapshotted ⇒ nothing to compare against
  now="$(identity_snapshot)"
  if [ "$now" = "$IDENTITY_SNAP" ]; then
    identity_snap_ok "$now" && return 0
    # UNCHANGED but WRONG. Guarding only the CHANGED case leaves the machine wedged: once a bad
    # value is resident, every later sweep reads now == snap and returns early, so nothing ever
    # clears it — and with githooks/pre-commit installed every commit is refused until a human
    # runs the cure by hand. Fail-closed is right for one commit and wrong as a resting state, so
    # a resident unsanctioned identity is dropped here too. It falls through to the global SSOT.
    log "IDENTITY: $REPO local [user] is unsanctioned and UNCHANGED this run [${now}] — DROPPING; falls through to the global identity"
    git -C "$REPO" config --local --remove-section user >/dev/null 2>&1 || true
    # Deliberately NOT added to FAILING. A red here reaches red_actions, which can auto-revert —
    # and this run did not cause the fault, it inherited it. Convicting the commit that happened
    # to be under test would launder someone else's red into this land's verdict.
    return 0
  fi
  log "IDENTITY LEAK: the corpus mutated $REPO local [user] during this run — was [${IDENTITY_SNAP:-absent}] now [${now:-absent}]"
  git -C "$REPO" config --local --remove-section user >/dev/null 2>&1 || true
  if ! identity_snap_ok "$IDENTITY_SNAP"; then
    # The baseline was already poisoned. Dropping it hands the repo back to the global SSOT, which is
    # the state a human would have to restore by hand anyway. Say so loudly — a silent divergence
    # from "restored" is exactly the shape that hid this for three days.
    log "IDENTITY LEAK: run-start value [${IDENTITY_SNAP}] was ITSELF unsanctioned — DROPPED, not restored; $REPO now falls through to the global identity"
    FAILING+=("shared-config-identity")
    FAILNAME+=("$REPO started this run with an unsanctioned git identity: ${IDENTITY_SNAP}")
    [ -n "$FAILTEST" ] || FAILTEST="$REPO started this run with an unsanctioned git identity"
    return 0
  fi
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
  FAILNAME+=("a suite wrote git user.* into $REPO (empty -C, or an unguarded cd)")
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
# HAS bats planned yet? — a PREDICATE, and deliberately NOT spelled `tap_plan > 0`. int_or_zero
# collapses two genuinely different states onto the same 0: "no plan line has been written yet" and
# a real, emitted `1..0` (the empty-corpus plan, which this file already treats as a NON-VERDICT at
# the retry site). The stall watcher is the consumer that must tell them apart — it reads this to
# decide WHICH bound it is currently under, and taking a `1..0` for "still counting" would hold a
# finished run inside the pre-plan grace instead of the stall clock. (memory: lookup-miss-is-not-
# absence — a reader that cannot distinguish "absent" from "zero" will eventually be asked to.)
# `1\.\.[0-9]` and not `1\.\.[0-9]+`: this asks only whether the line has STARTED, so a plan
# truncated mid-write still counts as planned — bats writes it in one printf, and the alternative
# is a torn digit reading as "never planned" and cutting a live run.
# Same `-a` as the grammar readers below, for the same reason: ugrep 7.5.0 — on the operator's own
# interactive PATH — counts a NUL-carrying TAP as EMPTY without it.
tap_planned() { # <tap> → 0 once the `1..N` plan line exists (INCLUDING `1..0`) · 1 before that
  grep -aqE '^1\.\.[0-9]' "$1" 2>/dev/null
}
pre_plan_grace() { # <corpus_n> → seconds bats may spend COUNTING before we call it wedged.
  # Every input goes through int_or_zero: this file runs under `set -u`, the values are operator-
  # settable env, and a non-numeric one must degrade to the default rather than make a `[ x -ge y ]`
  # inside the watcher loop a fatal error mid-run. Clamped to SUITE_TO only when SUITE_TO is itself
  # a positive number — a 0/garbage backstop must not silently zero the grace and re-open the very
  # false cut this exists to close.
  local n per floor g
  if [ -n "${POSTLAND_PRE_PLAN_GRACE_S:-}" ]; then int_or_zero "$POSTLAND_PRE_PLAN_GRACE_S"; return 0; fi
  n="$(int_or_zero "${1:-0}")"
  per="$(int_or_zero "$PRE_PLAN_PER_SUITE_S")"; [ "$per" -gt 0 ] || per=15
  floor="$(int_or_zero "$PRE_PLAN_FLOOR_S")"
  g=$(( n * per ))
  [ "$g" -lt "$floor" ] && g="$floor"
  [ "$(int_or_zero "$SUITE_TO")" -gt 0 ] && [ "$g" -gt "$SUITE_TO" ] && g="$SUITE_TO"
  printf '%s' "$g"
}
# ════ THE TAP RESULT-LINE GRAMMAR — ONE definition, every reader (C30) ════════════════════════════
# TAP13 (and bats) spell a result line `ok <N> <desc>` / `not ok <N> <desc>`. The <N> is not
# decoration: it is the ONLY thing separating a RESULT LINE from arbitrary text that merely opens
# with those bytes — and arbitrary text is ROUTINE here, because the corpus TAP is captured as
# `> "$tap" 2>&1`: an unprefixed stderr write (a test's background child, a shell's own diagnostic)
# splices straight into the stream, and a run we kill mid-write truncates a line wherever the
# buffer happened to end.
#
# TWO READERS DISAGREEING WAS THE BUG. tap_done required the <N>; classify_failures' failure count
# did not; the awk that pairs a failure with its file diagnostic required neither. Three spellings
# of one grammar, and the loosest decided whether the tree was RED. Measured against /usr/bin/grep
# (BSD 2.6.0-FreeBSD), FOUR shapes read as BOTH "0 tests completed" — which is what the stall
# watcher cuts on — AND "a not-ok exists", which is what branch (b) convicts on, with zero
# attributable pairs:
#
#   `not ok`                 truncated mid-write   tap_done=0  notok=1  pairs=0
#   `not ok3 squashed`       torn digit            tap_done=0  notok=1  pairs=0
#   `not okay then`          PREFIX OF A WORD      tap_done=0  notok=1  pairs=0
#   `not okcorpus: 3 suites` stderr spliced in     tap_done=0  notok=1  pairs=0
#
# That pair is in runner.log at 2026-07-30T05:47:21Z (9586f1ac51f5) and 06:04:21Z (4399852f21c2):
# `STALL … at test 0 — cutting the run` and then `RED failing=tests/ retries=0` 41s later — a
# backlog item pointing at a DIRECTORY, and a bisect that can hand auto_revert a culprit off a run
# in which no test failed. AUTOREVERT defaults on.
#
# C13c (the rc guard below) closed the ROUTE those two events took — rc∉{0,1} ⇒ cut, never red —
# but not the CONTRADICTION: at rc 1, bats genuinely saying "something failed", all four shapes
# still file `FAILING=(tests/)`.
#
# NOTOK is now a strict SUBSET of DONE by construction, so `notok > 0` IMPLIES `tap_done > 0` and
# "stalled at test 0" and "a failure exists" can no longer both be true. The invariant is the
# guarded property — C30 pins it per shape AND asserts the subset relation itself, so a future
# re-divergence on a FIFTH shape is falsifiable rather than merely unobserved. Both readers also
# take `-a`: the count must not change with WHICH grep is on PATH (ugrep 7.5.0 — on the operator's
# own interactive PATH — counts a NUL-carrying TAP as EMPTY without it, which would resurrect the
# disagreement from the other side).
TAP_DONE_RE='^(ok|not ok) [0-9]+'    # a test that COMPLETED — either verdict
TAP_NOTOK_RE='^not ok [0-9]+'        # a test that completed and FAILED — strict subset of the above
tap_done() { # <tap> → completed tests. bats emits `ok`/`not ok` only AFTER a test returns, so this
  # is exactly "how far did it get". (`grep -c` prints 0 AND exits 1 on no-match — never `|| printf 0`.)
  int_or_zero "$(grep -acE "$TAP_DONE_RE" "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_notok() { # <tap> → completed tests that FAILED. Same grammar as tap_done, so it can only ever
  # count a SUBSET of what tap_done counts — that implication is the whole point (C30).
  int_or_zero "$(grep -acE "$TAP_NOTOK_RE" "$1" 2>/dev/null | head -1 | tr -d '\n')"
}
tap_failtest() { # <tap> → the <desc> off the FIRST failing result line ("" when there is none).
  # Derived from TAP_NOTOK_RE rather than re-spelled: the old `s/^not ok [0-9]* //` matched ZERO
  # digits too, i.e. it was a THIRD spelling of the grammar and the loosest of the three.
  # Armed on the regex PLUS its separating space — the sed it replaces required that space too
  # (`s/^not ok [0-9]* //`), and this keeps a DESCRIPTIONLESS `not ok 1` falling through to the
  # caller's "(unattributed)" instead of being reported as though `not ok 1` were a test's name.
  awk -v re="$TAP_NOTOK_RE" 'BEGIN{ re = re " " } $0 ~ re { sub(re, "", $0); print; exit }' "$1" \
    2>/dev/null | cut -c1-120
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
  # RETRY_BOUND_S is an OUT-PARAMETER: which of the two bounds this call actually ran under. There
  # are two, they differ by 18x, and rc 124 alone cannot say which fired — so the ladder's cut
  # message named RETRY_TO unconditionally and was WRONG on the common path. MEASURED 2026-08-16:
  # sixteen consecutive cuts logged "our own 5400s bound fired on the re-run" for
  # tests/autonomy-sweep.bats inside runs whose OWN total was run_s=3364 and run_s=3538 — a 5400s
  # bound cannot fire in a 3364s run, so every one of those lines named a bound that never ran. The
  # figure is what the diagnosis is built on: 5400s says "a suite far too slow to re-run", 300s says
  # "one test overran", and only the second is compatible with this suite measuring 77s / 55 green
  # at this exact band (nice -n 5, taskpolicy -c utility). A guessed number in a cut message is not
  # cosmetic — it is the whole rung the next reader stands on, and it sent a session hunting a
  # 90-minute suite that does not exist.
  local f="$1" t="$2" td="$3" rc=0 out filt
  RETRY_BOUND_S="$RETRY_TO"
  if [ "${POSTLAND_RETRY_GRANULARITY:-test}" = "test" ] && [ -n "$t" ]; then
    out="$td/tap"
    RETRY_BOUND_S="$FILE_TO"
    # `bats -f` takes a REGEX: escape every metachar in the TAP-reported name, then anchor it.
    filt="$(printf '%s' "$t" | sed 's/[][\\.^$*+?(){}|\/]/\\&/g')"
    ( cd "$WORKTREE" && TMPDIR="$td" bounded "$FILE_TO" "${RETRY_QOS[@]}" \
        "$BATS_BIN" -f "^${filt}\$" "$f" ) </dev/null > "$out" 2>&1 || rc=$?
    # A filter that matched NOTHING exits 0 with `1..0` — a NON-VERDICT that would exonerate the file
    # for free. Only trust this run if it actually PLANNED a test; otherwise fall through to the file.
    [ "$(tap_plan "$out")" -gt 0 ] && { rm -f "$out"; return "$rc"; }
    rm -f "$out"; rc=0
    RETRY_BOUND_S="$RETRY_TO"          # fell through: the bound that decides is now the file's
  fi
  # FALLBACK: the whole file, under the bound sized for a whole file.
  ( cd "$WORKTREE" && TMPDIR="$td" bounded "$RETRY_TO" "${RETRY_QOS[@]}" "$BATS_BIN" "$f" ) </dev/null >/dev/null 2>&1 || rc=$?
  return "$rc"
}
# WHY AN rc IS NOT A VERDICT ABOUT THE TREE — ONE ladder, read by BOTH no-pair branches below.
# It used to live inside branch (c) only, so branch (a) — zero `not ok` at all, which is what a run
# killed before any test COMPLETES looks like, i.e. the commonest truncation — returned above it and
# kept the generic default, discarding the rc. That is the single most diagnostic fact a cut has:
# MEASURED 2026-08-10, nine consecutive sweeps logged `zero not-ok in a non-zero run - truncated`
# with no rc and no cause, while this runner's own stderr file carried `Killed: 9` TWELVE times
# alongside six `Terminated: 15` (ours — the stall watcher). The verdict was right both times (cut,
# never red) and the CAUSE was unrecoverable from the log, so diagnosing it took an lsof against a
# live run. Signal-death and our own bound are opposite findings — one says "a peer killed us", the
# other "a test is slow" — and a default naming neither sends every reader to the wrong one.
#
# ── THE SIGNAL ARM NAMED A CAUSE IT HAD NEVER ESTABLISHED (C33b, 2026-08-11) ──────────────────────
# It read `(machine pressure, not the tree)`. The second half is right and is the whole job of this
# function; the first half was a GUESS, and it was swept against disk and refuted on every axis it
# could mean:
#   · jetsam/OOM — 0 `memorystatus: killing` events in 24h of unified log, swap total 0.00M,
#     compressor at 0.98% of its segment limit. macOS was not killing anything for memory.
#   · load — the killed runs average 13.18 against green's 9.56, but the distributions OVERLAP and
#     the extremes invert: runs killed at load 2.26 and 5.90, runs stamped GREEN at 16.09 and 14.60.
#     Load does not separate the populations, so it cannot be the cause that distinguishes them.
#   · the 15-vs-9 split is not even known to be two senders: `timeout -k 10` re-raises the child's
#     signal, so an external TERM manufactures an internal KILL 10s later, and TERM→wrapper,
#     TERM→child, KILL→wrapper and KILL→child produce identical rc AND identical shell text (143/137).
# What IS established: the signal came from outside this runner's tree (both stall sites set `cutby`
# and force rc 124, and no `STALL:` line precedes any of the 14), and the parent survived every one —
# which excludes anything signalling the process group, the launchd job, or the session.
#
# A GUESSED CAUSE IS WORSE THAN A NAMED UNKNOWN when it prescribes a remedy, and this one did: "the
# box is busy" reads as "retry when quieter", which §R1 of LOAD_INSENSITIVE_VERIFY_V2 records as the
# one response guaranteed never to clear it, on a box whose steady state is saturation. Say what is
# known and mark what is not; the sender-identifying evidence (a child-process snapshot taken before
# `wait` and written into the stamp) is filed, not guessed at here.
rc_why() { # <rc> → why this rc says nothing about the tree
  if   [ "$1" -eq 124 ]; then printf 'our own bound cut the run'
  elif [ "$1" -gt 128 ]; then printf 'the run was KILLED by signal %s from OUTSIDE this runner (sender unidentified) - not the tree' "$(( $1 - 128 ))"
  elif [ "$1" -eq 126 ] || [ "$1" -eq 127 ]; then printf 'the run could not execute (rc %s)' "$1"
  # WORDING IS LOAD-BEARING: this says "ADMISSION DEFERRAL", never the bare token R-E-F-U-S-E-D.
  # permission-gate-lint treats that token as a guard-refusal VERB (`s ~ /REFUSED/`, substring,
  # inside strings too) and would count this message-assignment as an unbounded permission gate
  # on an actuation path. It is not one — nothing here refuses; cc-bats did, and this arm only
  # NAMES it, after which the cut path logs and retries next sweep. Declaring a `gate_bounded:`
  # budget for a gate that does not exist would launder a false positive into a real exemption.
  # "Deferral" is also cc-bats' own word for it ("this is a DEFERRAL, not a test result").
  elif [ "$1" -eq 75 ]; then printf '%s' "the run hit cc-bats' ADMISSION DEFERRAL (rc 75, EX_TEMPFAIL) — NOTHING RAN. This runner exports CC_BATS_MAX_ROOTS=0 to be exempt, so seeing this means the exemption did not reach the child"
  else printf 'the run exited %s — not a tree verdict (bats says 0=pass, 1=fail)' "$1"
  fi
}
classify_failures() { # <tapfile> <rc> — retry ladder: >=2/3 = REPRODUCIBLE, 1/3 = flake, 124 = no verdict
  # <rc> is the CORPUS run's exit code, and it is load-bearing for case (c) below: without it this
  # function cannot tell a failure of the tree from a run we killed ourselves. Defaults to 1 (bats'
  # "something failed") so an omitted argument can only ever preserve the old convicting behaviour,
  # never invent a cut.
  local pairs f t rc i tdir fails notok abstain ABSTAIN_RC ABSTAIN_BOUND ABSTAIN_EL arc why abnd ael aleg rt0 rtel tap_rc="${2:-1}"
  # TAP: `not ok N <name>` followed by a `# (in test file tests/X.bats, line N)` diagnostic.
  # $TAP_NOTOK_RE, never a re-spelling: this arming pattern was the LOOSEST of the three readers
  # (`/^not ok /`, no <N> at all), so a torn line armed `p` and paired the NEXT `#` line's filename
  # with a description that was never a test name — attributing a failure to an innocent file (C30).
  pairs="$(awk -v re="$TAP_NOTOK_RE" '$0 ~ re {p=1; n=$0; sub(re " ","",n); next}
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
    notok="$(tap_notok "$1")"                   # THE one grammar (C30) — tap_done's, exactly
    if [ "$notok" -eq 0 ]; then
      CUT=1
      # NAME THE rc HERE TOO. A cut with no attributable pair AND no completed failure is the
      # commonest truncation there is, and it was the one shape that recorded nothing about its own
      # cause. rc 0 is not reachable (the caller only calls on non-zero), so every value that lands
      # here has a reading in rc_why — including bats' own 1, which on a zero-not-ok TAP means the
      # run died before writing a verdict rather than that a test failed.
      CUT_WHY="zero not-ok in a non-zero run — $(rc_why "$tap_rc")"
      log "corpus TRUNCATED — $CUT_WHY; no test completed and failed, so nothing is proven (cut, not red)"
      return 0
    fi
    case "$tap_rc" in
      0|1) ;;                                   # the only two codes that speak about the tree
      *)   CUT=1                                # 124 / >128 signal / 126 / 127 ⇒ nothing proven
           FAILTEST="$(tap_failtest "$1")"
           [ -n "$FAILTEST" ] || FAILTEST="(unattributed)"
           # Name WHICH non-verdict fired, for the same reason C23 does: a fixed message would
           # misattribute a SIGKILL to our timeout and send the next reader hunting a slow test.
           # ONE ladder with branch (a) above — see rc_why's header for why it was hoisted out.
           why="$(rc_why "$tap_rc")"
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
    FAILTEST="$(tap_failtest "$1")"
    [ -n "$FAILTEST" ] || FAILTEST="(unattributed)"
    FAILNAME=("$FAILTEST")
    return 0
  fi
  while IFS="$(printf '\t')" read -r f t; do
    [ -n "$f" ] || continue
    fails=1; rc=1; abstain=0; ABSTAIN_RC=124; ABSTAIN_BOUND=""; ABSTAIN_EL=0; rtel=0   # RESET per file: a stale rc/bound/elapsed would misname the cut
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
      # TIME IT. `timeout` reports 124 when IT cuts, and a CHILD that exits 124 on its own is
      # byte-identical in rc — so 124 alone cannot say whose it is, and the message has been
      # asserting the bound for both. ELAPSED is what separates them, and it needs no new
      # cooperation from anything: a 124 that arrives in seconds is the child's, because our bound
      # had not yet come due. MEASURED 2026-08-16 against the live ladder's own failing case: the
      # corpus's pair is consistently tests/autonomy-sweep.bats / "nothing new → abstain, zero
      # notifies", and re-running EXACTLY that under the daemon's own environment (its PATH, a
      # pristine detached worktree, nice -n 5 + taskpolicy -c utility) costs 3.56s against a 300s
      # bound — 84x headroom, planning 1 and passing. So the sixteen consecutive `ladder UNPROVEN`
      # cuts cannot be this bound firing, and every one of them said it was. cc-bats documents a
      # sustained `rc 124, zero output` of its own (a shim exec chain, bin/cc-bats §"THE 2-CYCLE
      # IS STILL LIVE"), which is what a non-slow 124 looks like. Name the elapsed and the reader
      # can tell the two apart in one line instead of dispatching a session at the wrong one.
      rt0="$(now_epoch)"
      retry_once "$f" "$t" "$tdir"; rc=$?
      rtel=$(( $(now_epoch) - rt0 ))
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
        # ABSTAIN_BOUND is captured HERE, beside the rc it belongs to — never re-read at the message.
        *)   abstain=1; ABSTAIN_RC="$rc"; ABSTAIN_BOUND="$RETRY_BOUND_S"; ABSTAIN_EL="$rtel"; break ;;   # 124 / >128 / 126 / 127 ⇒ nothing proven
      esac
      [ "$rc" -eq 0 ] || fails=$((fails+1))
    done
    # C29: record it as LADDER-convicted as well. Same push, one extra array — the verdict this run
    # renders is unchanged here; corroborate_convictions below decides what it is WORTH.
    if [ "$fails" -ge 2 ]; then FAILING+=("$f"); FAILNAME+=("$t"); LADDER_FAILING+=("$f"); [ -n "$FAILTEST" ] || FAILTEST="$t"
    elif [ "$abstain" = 1 ]; then
      # Not a red (nothing was proven) and not a flake (nothing was cleared) ⇒ the cut path, which
      # says exactly that and retries next sweep. FAILTEST carries the name so the cut is diagnosable.
      LADDER_UNPROVEN=1; [ -n "$FAILTEST" ] || FAILTEST="$t"
      # Name WHICH non-verdict fired. "our own bound" was accurate while 124 was the only abstaining
      # code; now that a signal kill also abstains, a fixed message would misattribute a SIGKILL to
      # our timeout and send the next reader hunting a slow test that was never slow.
      arc="${ABSTAIN_RC:-124}"
      # 124 IS TWO FINDINGS, and only the elapsed separates them. Our bound firing means the re-run
      # really did run for the whole bound; a 124 that arrives well inside it was the CHILD's own
      # exit code, and the two send a reader to opposite places (a slow test vs. a runner that never
      # ran). The split is at half the bound: comfortably above any real cut, comfortably below the
      # seconds a non-slow 124 takes.
      if   [ "$arc" -eq 124 ]; then
        abnd="${ABSTAIN_BOUND:-$RETRY_TO}"; ael="${ABSTAIN_EL:-0}"
        aleg="$([ "$abnd" = "$FILE_TO" ] && printf 'the single named test' || printf 'the whole file')"
        if [ "$ael" -ge $(( abnd / 2 )) ]; then
          why="our own ${abnd}s bound fired on the re-run of ${aleg} (ran ${ael}s)"
        else
          why="the re-run of ${aleg} exited 124 after only ${ael}s — our bound is ${abnd}s and had not come due, so this is the CHILD's own exit code, NOT a slow test (cc-bats documents a sustained rc-124 shim chain; check what \`bats\` resolves to on this PATH)"
        fi
      elif [ "$arc" -gt 128 ]; then why="the re-run was KILLED by signal $(( arc - 128 )) (machine pressure, not the tree)"
      elif [ "$arc" -eq 126 ] || [ "$arc" -eq 127 ]; then why="the re-run could not execute (rc $arc)"
      # 75 = cc-bats' EX_TEMPFAIL deferral. It is the ONLY abstaining code that means "nothing was even
      # attempted" — 124/137/143/126/127 are all facts about the machine that a re-run cannot undo. This
      # runner is exempt (CC_BATS_MAX_ROOTS=0, see BATS_BIN), so this arm is a BACKSTOP: it exists so a
      # recurrence names itself instead of falling into the generic "exited N" arm, which is what sent
      # the 2026-08-07T23:29Z investigation hunting a slow test that had never been slow.
      # Same wording constraint as the corpus arm above — "ADMISSION DEFERRAL", never the bare token.
      elif [ "$arc" -eq 75 ]; then why="the re-run hit cc-bats' ADMISSION DEFERRAL (rc 75, EX_TEMPFAIL) — NOTHING RAN, so this is a deferral, not evidence; the CC_BATS_MAX_ROOTS=0 exemption did not reach the child"
      else why="the re-run exited $arc — not a tree verdict (bats says 0=pass, 1=fail)"
      fi
      log "ladder UNPROVEN for $f — $why; no verdict (cut, not red)"
    else record_flake "$f" "$t" "$rc"; fi
  done <<EOF
$pairs
EOF
}
conviction_observe() { # <file> <tree> <sha> → 0 when a PRIOR, time-SEPARATED observation exists
  local f="$1" tree="$2" sha="$3" now cutoff newest prior load tmp
  now="$(now_epoch)"; cutoff=$(( now - CONVICT_TTL )); newest=$(( now - CONVICT_SPREAD ))
  # READ for the record, never a predicate and never slept on — which is verbatim the invariant
  # qos-chokepoint.bats (xiii) settled on 2026-08-07 after its own proxy was found wrong in BOTH
  # directions: "read the instrument if you must, never wait on it". (Its earlier form banned the
  # substring `loadavg` outright, which forbade the plan's own remedy while still passing any shim
  # that slept without writing the word.) Same accessor record_flake uses, so a PATH-blind sysctl
  # cannot make this row silently empty.
  load="$(load1)"
  prior=0
  if [ -f "$CONVICTIONS" ]; then
    # A QUALIFYING prior: same FILE, still inside the TTL, and at least CONVICT_SPREAD ago. That
    # last clause is the whole point — without it this run's own ladder would corroborate itself.
    prior="$(awk -F'\t' -v f="$f" -v lo="$cutoff" -v hi="$newest" \
               '$2==f && $1+0>=lo && $1+0<=hi {n++} END{print n+0}' "$CONVICTIONS" 2>/dev/null || printf 0)"
    # PRUNE past the TTL on the way through: this file is re-read on every conviction, so it may not
    # grow without bound. Best-effort by construction — a failed prune costs disk, never a verdict.
    tmp="$(mktemp "$STATE/convictions.XXXXXX" 2>/dev/null)" && {
      awk -F'\t' -v lo="$cutoff" '$1+0>=lo' "$CONVICTIONS" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$CONVICTIONS" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    }
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$f" "$tree" "$sha" "${load:-}" >> "$CONVICTIONS" 2>/dev/null || true
  [ "${prior:-0}" -ge 1 ]
}
corroborate_convictions() { # <tree> — rebuild FAILING, keeping only CROSS-WINDOW-corroborated reds
  # The C29 filter. Runs AFTER classify_failures, so the in-run ladder is untouched and still costs
  # what it always did; this only decides what its verdict is worth. A file the ladder convicted in
  # one window is recorded and DROPPED from FAILING — not cleared (nothing exonerated it) and not
  # convicted (one window is one experiment) — which is precisely the abstention C23 already
  # established: FAILING empty + a pending flag ⇒ cut ⇒ the same tree is re-run next sweep, and THAT
  # sweep is the second window. No new run is scheduled to get it; the retry was already happening.
  local tree="${1:-}" f i n=0
  local -a keep keepname
  keep=(); keepname=()
  [ "$CONVICT_MODE" != "off" ] || return 0
  [ "${#LADDER_FAILING[@]}" -gt 0 ] || return 0     # nothing load-attributable ⇒ nothing to adjudicate
  [ "${#FAILING[@]}" -gt 0 ] || return 0
  # INDEX-WALKED, not value-walked, because FAILNAME is index-aligned with FAILING and both must be
  # rebuilt in LOCKSTEP. Dropping a file from FAILING alone would shift every later name by one and
  # red_actions would file each surviving file under its NEIGHBOUR's test name — a silent
  # mis-attribution on the one path whose entire job is to say what failed. (This runs BEFORE the
  # SYNTAX_BAD splice, which is the point at which the two arrays are still 1:1.)
  for (( i = 0; i < ${#FAILING[@]}; i++ )); do
    f="${FAILING[$i]}"
    case " ${LADDER_FAILING[*]} " in
      *" $f "*) ;;
      *) keep+=("$f"); keepname+=("${FAILNAME[$i]:-}"); continue ;;   # deterministic: never delayed
    esac
    if conviction_observe "$f" "$tree" "${CUR_SHA:-}"; then
      keep+=("$f"); keepname+=("${FAILNAME[$i]:-}")
      log "C29 CORROBORATED $f — convicted again in a SECOND window (>=${CONVICT_SPREAD}s apart): RED"
    else
      CONVICT_PENDING=1; n=$(( n + 1 ))
      log "C29 PENDING $f — convicted in ONE load window only; a same-window 2/3 is one experiment, not three (re-run next sweep decides)"
    fi
  done
  if [ "${#keep[@]}" -gt 0 ]; then FAILING=("${keep[@]}"); FAILNAME=("${keepname[@]}")
  else FAILING=(); FAILNAME=(); fi
  [ "$n" -eq 0 ] || CUT_WHY="the ladder convicted $n file(s) in ONE load window - awaiting a second (C29)"
  return 0
}
# ════ NO ADMISSION CONTROL — deleted, not tuned (§4.2.3, R7) ══════════════════════════════════════
# v1's gate_admit() lived here: poll the 1-min load, sleep while it exceeded a ceiling, proceed when
# the budget ran out. It is GONE, and its absence is the feature — see the BACKGROUND QoS block at
# the top for why (waiting is the amplifier; the singleton verifier may never be the thing that
# waits). Nothing in this file sleeps on load. If you are about to re-add a load wait here, the
# measurement to beat is: 5 concurrent gates at load 16-18 against their own ceiling of 8, each
# one's corpus being the load the others were waiting out.

# ════ THE FLOOR IS THE OTHER UNMEASURED ENDPOINT (2026-08-06) ═════════════════════════════════════
# The tip confirmation inside do_bisect closes one half of "git takes BOTH endpoints on trust"; this
# closes the other, and the two are mirror images. When the suite is ALREADY red at `good`
# (= $LASTGREEN), every interior probe answers BAD, the walk converges on the FIRST COMMIT AFTER
# good, and that commit is innocent of everything — it is merely the earliest sha git was allowed to
# consider. Measured against this git, not reasoned: an all-bad 4-commit range probes c3 then c2 and
# names c2, never once running at c1. The floor is not a hypothetical either — the 2026-08-06
# mis-revert's own last-green (29313ae4c35a) sat two days and ~130 commits below the tip.
#
# SCOPED THE SAME WAY THE TIP GUARD IS, and for the same reason. If the culprit is NOT the first
# commit after good, the walk necessarily observed a GREEN probe below it — a green probe becomes the
# new floor and the culprit must descend from it — so there is a real measured differential and
# nothing is owed. `rev-list --count good..culprit` = 1 is that predicate, and it survives merges: a
# count of 1 means every parent of the culprit is reachable from good, so no interior commit sits
# below it. One whole-file run, on the one path where the evidence is otherwise zero.
#
# THREE ANSWERS, NOT TWO. Ask FIRST whether the floor is even applicable: a suite that does not EXIST
# at good cannot have been red there, so the culprit is simply where the file was born, git probed it
# BAD, and that conviction stands. `cat-file -e` settles it for free. Collapsing this into "not green
# ⇒ abstain" is not merely conservative — it retires auto-revert for EVERY newly-added red suite,
# which is postland's own C20 fixture, i.e. the commonest shape rather than an edge (B16). The
# runner's rc could never have decided it: 125 means "file absent" OR "bats errored", and those two
# must not share a verdict. Otherwise, as with the tip, anything but a definite verdict — here rc 1
# (the failure predates the window), 125, or our own 124 — is UNDECIDABLE.
bisect_floor_ok() { # <good> <culprit> <runner> <counter> <file> — 0 = floor green, or not load-bearing
  local good="$1" culprit="$2" runner="$3" counter="$4" file="$5" below want got rc=0
  below="$(git -C "$WORKTREE" rev-list --count "$good..$culprit" 2>/dev/null || true)"
  case "$below" in ''|*[!0-9]*) below=1 ;; esac   # unreadable ⇒ assume load-bearing ⇒ PROBE (safe way)
  [ "$below" -gt 1 ] && return 0                  # the walk measured its own GREEN below the culprit
  # Resolve the floor FIRST and key everything below on the resolved sha: `cat-file -e` fails both
  # for an absent PATH and for an unresolvable REV, and only the first of those may convict.
  want="$(git -C "$WORKTREE" rev-parse --verify "$good^{commit}" 2>/dev/null || true)"
  [ -n "$want" ] || {
    log "bisect FLOOR UNPROVEN: cannot resolve the last-green $(sha12 "$good") in the cell, and $(sha12 "$culprit") is the first commit after it — undecidable, no culprit named"
    BISECT_WHY="floor-unproven"; return 1; }
  git -C "$WORKTREE" cat-file -e "$want:$file" 2>/dev/null || {
    log "bisect floor N/A: $file does not exist at the last-green $(sha12 "$good"), so the floor cannot be the red — $(sha12 "$culprit") is where the file appeared and the walk probed it BAD; culprit stands"
    return 0; }
  : > "$counter"          # a confirmation is not a bisect STEP — leave the cap's budget alone
  git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true      # ...so the checkout below can run
  if ! bounded 120 git -C "$WORKTREE" checkout --detach --force "$want" >/dev/null 2>&1; then
    log "bisect FLOOR UNPROVEN: cannot check out the last-green $(sha12 "$good") to confirm it — undecidable, no culprit named"
    BISECT_WHY="floor-unproven"; return 1
  fi
  # CONFIRM WHERE WE ARE, never assume the checkout took: this probe's entire meaning is the commit
  # it ran at, and any way of failing to reach the floor leaves HEAD somewhere a GREEN would be
  # misread as the floor's. Belt-and-braces, and stated as such — no fixture in B13-B16 can make that
  # checkout fail, so deleting this line turns nothing red. It is kept for the failure it catches.
  got="$(git -C "$WORKTREE" rev-parse --verify HEAD 2>/dev/null || true)"
  [ "$want" = "$got" ] || {
    log "bisect FLOOR UNPROVEN: the cell did not land on the last-green $(sha12 "$good") — undecidable, no culprit named"
    BISECT_WHY="floor-unproven"; return 1; }
  bounded "$RETRY_TO" "$runner"; rc=$?      # the walk's own step, re-run — same script, same band
  [ "$rc" -eq 0 ] && {
    log "bisect floor CONFIRMED green at $(sha12 "$good") — $(sha12 "$culprit") is its first child, so the walk itself had no green to stand on"
    return 0; }
  log "bisect FLOOR NOT GREEN: the walk named $(sha12 "$culprit") only because it is the first commit after an ASSUMED-green floor, and $file is not green at $(sha12 "$good") either (runner rc=$rc) — undecidable, no culprit named"
  BISECT_WHY="floor-not-green"
  return 1
}
# ════ REACHABILITY — A COMMIT THAT CANNOT TOUCH THE SUBJECT IS NOT A CANDIDATE (2026-08-17) ═══════
# THE MEASUREMENT (backlog ebbf3adfb4d0). Page postland-red-0f55846f7de4 named
# `tests/cc-wait.bats::the timeout verdict names itself as designed` at culprit 0f55846f7de4,
# bisected from last-green f5b67a94760e. That commit's ENTIRE diff is `docs/plans/BACKLOG_DRAIN_24_7.md`,
# +88 lines and no code — a file bats never opens, that cc-wait.bats never names, and that no
# process in the run reads. It cannot reach the subject by any path. The suite was 19/19 green at
# origin/main with that same plan line present, so the RED never reproduced; the page env recorded
# load 16.45, i.e. the corpus failure was CONTENTION, and the walk then elected the nearest commit
# rather than reporting no verdict. Two costs, both durable: the originating chain gets paged for a
# fault it did not cause, and a docs commit acquires a permanent RED in the page store.
#
# WHY THE THREE EXISTING GUARDS DO NOT COVER IT. The tip confirmation and the floor proof both ask
# "did the walk MEASURE what it names" — they re-run the runner at an endpoint. An interior culprit
# with a real GOOD probe below it and a real BAD probe at it passes both, because under contention
# that differential genuinely existed: the box was loaded when one step ran and not when the other
# did. Nothing in a re-run can separate that from a regression. This guard asks a different question
# — CAN THIS DIFF REACH THE SUBJECT AT ALL — and it is answered from the tree, not from a probe, so
# it costs no bats run and works on the one path where re-running is exactly what cannot decide.
#
# THE PREDICATE IS DELIBERATELY ONE-SIDED. Only a POSITIVE proof of unreachability vetoes; anything
# unreadable, ambiguous, or merely unmentioned in the diff leaves the culprit standing. The reason
# is the shape of the two errors: a wrong veto costs culprit REFINEMENT (red_actions still pages and
# still backlogs the RED — it just names nobody), while a wrong conviction costs an AUTO-REVERT of an
# innocent commit on trunk. So:
#   · ANY changed path outside the inert class ⇒ stands, no questions. A `.sh` under docs/ is code,
#     a config is loadable, and a script the subject never names can still be reached transitively
#     through whatever binary it does invoke. This is what keeps every real code conviction intact.
#   · A merge, an unreadable diff, an empty diff, or a subject we cannot read ⇒ stands. Unprovable
#     is not proven.
#   · ALL changed paths inert (`*.md`) AND none of them named by the subject ⇒ VETO.
# THE INERT CLASS IS `*.md` AND NOTHING ELSE, and the narrowness is the point. Markdown in this repo
# is never executed and never sourced — the one extension for which "bats cannot reach it except by
# reading it" is a property of the format rather than a guess about the file. `*.txt` was in the
# class for one draft and came straight back out: the fixture ranges in
# tests/postland-verify-bisect-bound.bats commit `seq.txt`, and B10/B13/B17 — the tip and floor
# clauses — went red because the veto short-circuited them. That is not a fixture accident. A `.txt`
# in this tree is as likely to be a test fixture read through a path the test never spells as it is
# to be prose, so vetoing on it proves less than it claims. Widen this class only with a measured
# reason; every extension added here removes convictions somewhere.
# "Named by the subject" is checked against the full path, every ancestor directory prefix, and the
# basename, because a test that reads a doc does not always spell the whole path: tests/backlog-
# grouping.bats builds `$REPO/docs/plans/$(… tr …).md` at runtime, so only the `docs/plans/` prefix
# can see it, while tests/desk-brief-ssot.bats spells `docs/templates/desk-boot-brief.md` in full.
# Both of those must keep their convictions; tests/cc-wait.bats, which contains no `docs/` at all,
# is what this vetoes. Measured against the live tree, not reasoned: those are the three shapes in it.
# The walk runs all the way up to the TOP-LEVEL component, so a subject merely saying the word
# `docs` in a comment exonerates the whole of docs/ for that suite. That is a real loss of
# discrimination and it is taken deliberately: stopping one level short would start vetoing on
# subjects that reach a directory by a spelling this cannot see, and a wrong veto and a wrong
# conviction are not the same size of mistake. The suite that produced the incident says `docs`
# nowhere, which is the population that matters.
#
# SCOPE — the subject file's own text is the corpus. This repo has zero bats `load` helpers
# (`grep -c '^ *load ' tests/*.bats` = 0), so the file IS its own closure today. If a helper is ever
# introduced, its content has to be appended here or a doc named only by the helper reads as
# unreachable — that is the one way this guard could start vetoing wrongly.
bisect_reach_ok() { # <culprit> <bad> <file> — 0 = can reach the subject, or unprovable; 1 = provably cannot
  local culprit="$1" bad="$2" file="$3" parents paths p subject dir tok
  local -a inert=()
  # ONE parent only. `diff-tree --name-only` prints NOTHING for a merge, and an empty path list read
  # as "touches no file" would veto every merge commit — the opposite of one-sided.
  parents="$(git -C "$WORKTREE" rev-list --parents -n1 "$culprit" 2>/dev/null | wc -w | tr -d ' ')"
  case "$parents" in 2) ;; *) return 0 ;; esac        # 2 words = the sha + exactly one parent
  paths="$(git -C "$WORKTREE" diff-tree --no-commit-id --name-only -r "$culprit" 2>/dev/null)"
  [ -n "$paths" ] || return 0                          # unreadable, or an empty commit — unprovable
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      *.md) inert+=("$p") ;;
      *)    return 0 ;;                                # code/config class — reachable, possibly transitively
    esac
  done <<EOF
$paths
EOF
  [ "${#inert[@]}" -gt 0 ] || return 0
  subject="$(git -C "$WORKTREE" show "$bad:$file" 2>/dev/null)"
  [ -n "$subject" ] || return 0                        # cannot read the subject ⇒ cannot prove anything
  # SUBSTRING VIA `case`, NEVER `printf | grep -q`. The pipe form is the pipefail-SIGPIPE trap this
  # repo ratchets against, and here it inverts the guard's own meaning: `grep -q` exits at the FIRST
  # match, the producer takes SIGPIPE, `set -o pipefail` promotes that to 141, and the `&&` reads
  # FALSE — i.e. the subject NAMES the doc and the culprit gets vetoed anyway, which is the wrong
  # veto this whole function is one-sided to avoid. It hides in small fixtures (a printf under the
  # 64KB pipe buffer finishes before grep leaves) and appears on real subjects, so B20/B21 pass and
  # the live path does not. `case` is a builtin over a string already in memory: no pipe, no fork,
  # and the quoted "$tok" is matched LITERALLY, which is exactly `grep -F`'s semantics.
  for p in "${inert[@]}"; do
    for tok in "$p" "${p##*/}"; do
      case "$subject" in *"$tok"*) return 0 ;; esac
    done
    # Ancestors WITHOUT a trailing slash, deliberately: tests/codex-probe-corpus.bats spells
    # `"$REPO_ROOT/tests/fixtures/codex-probe"` with no slash after it, so a slash-terminated token
    # would miss the very directory that suite reads its .md corpus out of. The bare form is a
    # substring of the slashed one, so it matches both spellings and never fewer.
    dir="$p"
    while [ "${dir%/*}" != "$dir" ]; do                 # every ancestor: docs/plans then docs
      dir="${dir%/*}"
      case "$subject" in *"$dir"*) return 0 ;; esac
    done
  done
  log "bisect UNREACHABLE: $(sha12 "$culprit") changes only ${inert[*]} — $file names none of those paths and bats never loads them, so this diff cannot reach the subject; undecidable, no culprit named (a red with no reachable candidate is contention or a pre-existing trunk red, not this commit)"
  BISECT_WHY="unreachable"
  return 1
}
do_bisect() { # <file> <good> <bad> → sets BISECT_CULPRIT (empty when undecidable); rc 1 = no culprit
  # NEVER call this in `$( )` — it MINTS a worktree cell and the record is a global. See BISECT_CULPRIT.
  local file="$1" good="$2" bad="$3" runner out culprit qos rc=0 counter steps b0
  local probe_tmp="" probe_own=0
  BISECT_CULPRIT=""; BISECT_STEPS=0; BISECT_S=0; BISECT_LOAD=""; BISECT_WHY="no-range"
  b0="$(now_epoch)"
  [ -n "$good" ] && [ -n "$bad" ] && [ "$good" != "$bad" ] || return 1
  file="tests/$(basename "$file")"
  BISECT_WHY="no-cell"
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
  trap 'git -C "$WORKTREE" bisect reset >/dev/null 2>&1 || true; rm -f "$runner" "$counter"; [ "$probe_own" = 1 ] && rm -rf "$probe_tmp"; trap - RETURN' RETURN
  # ── ADJUDICATOR ENV: the probe runs where the MEASUREMENT ran (2026-08-06) ───────────────────────
  # An adjudicator that cannot reproduce the failure has a predetermined verdict. This runner used to
  # inherit the launchd TMPDIR while the corpus measured under TMPDIR=$RUN_TMP
  # (`…/postland-run.XXXXXX`, +20 bytes) — and a `tests/kitty-*.bats` fixture bound an AF_UNIX socket
  # at its ABSOLUTE path against Darwin's 104-byte sun_path cap: 87 bytes under a session prefix
  # (green), 107 under the corpus's (red). The red therefore existed ONLY at the longer prefix, no
  # probe could reproduce it, and the walk converged on the asserted-bad tip — auto_revert landed a
  # revert of e80c85aa (a correct, unrelated cc-queue fix) as f323b427, restoring a permanent red that
  # commit had just fixed. Re-landed by 12549d8b; the 2026-08-01T21:00:00Z flakes.jsonl row is N=2.
  #
  # 937c6fc5 (tip confirmation) and 4348ddc2 (floor proof) made that walk REFUSE to convict, which is
  # the safety half. This is the ATTRIBUTION half, and the two are not substitutes: a probe that
  # cannot reproduce still names nobody, so an env-dependent red stays permanently unattributed. Both
  # of those guards re-run THIS SAME `$runner`, so setting the env here fixes all three probe sites —
  # the walk, the tip confirmation, and the floor check — at one site.
  #
  # $RUN_TMP is the corpus's OWN dir, the exact string it measured under, and it outlives this call by
  # construction: run_target deletes it only after red_actions returns. The `bisect` verb has no
  # corpus, so it mints its own from the SHARED template — same length, which is what the reproduction
  # depends on. Minted AFTER the trap is armed so no later exit path can leak it, and torn down ONLY
  # when we own it: deleting the corpus's dir here would pull the ground from under run_target.
  #
  # Why $RUN_TMP and not the retry ladder's (longer) dir: the ladder only ever runs on a file the
  # CORPUS already failed, so the corpus prefix is where the failure was first observed and the floor
  # every ladder confirmation sits above. Matching it is necessary and sufficient.
  probe_tmp="$RUN_TMP"
  if [ -z "$probe_tmp" ] || [ ! -d "$probe_tmp" ]; then
    probe_tmp="$(mktemp -d "$TMPBASE/$RUN_TMPL")" || return 1
    probe_own=1
  fi
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
    # TMPDIR= is the ADJUDICATOR ENV invariant at its one load-bearing site: without it this probe
    # runs at the daemon's prefix while the corpus measured at a longer one, and a length-dependent
    # red is exonerated by construction. %q, not "%s", because this is being written INTO a script.
    printf 'TMPDIR=%q %s"%s" "%s" </dev/null >/dev/null 2>&1\n' "$probe_tmp" "$qos" "$BATS_BIN" "$file"
    # shellcheck disable=SC2016  # authoring a script: $rc must NOT expand here
    printf 'rc=$?\n[ "$rc" -le 1 ] || exit 125\nexit "$rc"\n'
  } > "$runner"
  chmod +x "$runner"
  BISECT_WHY="no-walk"
  if git -C "$WORKTREE" bisect start "$bad" "$good" >/dev/null 2>&1; then
    # THE BOUND (2026-08-05, 12h53m runaway — see BISECT_TO). `bounded` degrades to running
    # unbounded when no timeout(1) resolves, so log that state rather than skip the bisect: a
    # missing tool must not silently become a different behaviour, and the operator needs to know
    # which of the two shapes a 12-hour process was.
    [ -n "$TIMEOUT_BIN" ] && [ -x "$TIMEOUT_BIN" ] \
      || log "bisect UNBOUNDED — no timeout(1) resolved; the ${BISECT_TO}s wall is INERT this run — only the ${BISECT_MAX_STEPS}-step cap bounds it"
    out="$(bounded "$BISECT_TO" git -C "$WORKTREE" bisect run "$runner" 2>/dev/null)"; rc=$?
    steps="$(cat "$counter" 2>/dev/null || echo 0)"
    case "$steps" in ''|*[!0-9]*) steps=0 ;; esac
    BISECT_STEPS="$steps"
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
      BISECT_WHY="cut-wall"
    elif [ "${steps:-0}" -gt "$BISECT_MAX_STEPS" ]; then
      log "bisect CUT at the ${BISECT_MAX_STEPS}-step cap (POSTLAND_BISECT_MAX_STEPS) — the range is NOT SHRINKING (a suite that commits into \$WORKTREE does exactly this); undecidable, no culprit named"
      BISECT_WHY="cut-steps"
    else
      culprit="$(printf '%s\n' "$out" | sed -n 's/^\([0-9a-f]\{7,40\}\) is the first bad commit.*/\1/p' | head -1)"
      [ -n "${culprit:-}" ] || BISECT_WHY="no-first-bad"
      # REACHABILITY FIRST, and deliberately so (see bisect_reach_ok). It is the only one of the
      # three culprit guards that costs NO bats run, and it is the only one that can decide the
      # contention shape at all — so spending two whole-file probes to confirm endpoints of a
      # candidate whose diff cannot touch the subject is burning a starved box to reach the same
      # answer. Ordered before the tip confirmation, never merged into it: the tip guard is scoped
      # to `culprit = bad`, and the commit this vetoes was an INTERIOR one.
      [ -n "${culprit:-}" ] && { bisect_reach_ok "$culprit" "$bad" "$file" || culprit=""; }
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
          BISECT_WHY="tip-unconfirmed"; culprit=""
        else
          rc=0; bounded "$RETRY_TO" "$runner" || rc=$?
          if [ "$rc" -ne 1 ]; then
            log "bisect UNCONFIRMED: the walk named the TIP $(sha12 "$bad") without ever running it, and $file is NOT reproducibly red there ALONE (runner rc=$rc) — undecidable, no culprit named"
            BISECT_WHY="tip-unconfirmed"; culprit=""
          fi
        fi
      fi
      # ...and the FLOOR is the same class, in mirror image (see bisect_floor_ok). Both can fire on a
      # single-candidate range, and should: that is the walk with the least evidence of any, so it is
      # the one worth measuring from both ends before C20 acts on it.
      [ -n "${culprit:-}" ] && { bisect_floor_ok "$good" "$culprit" "$runner" "$counter" "$file" || culprit=""; }
    fi
  fi
  # ── THE TWO NUMBERS THAT SEPARATE A REGRESSION FROM CONTENTION (2026-08-17) ────────────────────
  # Read AT the verdict, not at the corpus's start, and recorded on BOTH arms — a non-verdict under
  # load is as much a fact about the box as a verdict is. `load1` returns empty when the instrument
  # cannot be read, and empty is rendered as `?` downstream rather than as a number: an unreadable
  # loadavg printed as 0 is the alarm-polarity defect this file already carries a comment about.
  BISECT_S=$(( $(now_epoch) - b0 ))
  BISECT_LOAD="$(load1)"
  if [ -n "${culprit:-}" ]; then
    BISECT_WHY=""
    log "bisect verdict=$(sha12 "$culprit") steps=$BISECT_STEPS elapsed=${BISECT_S}s load=${BISECT_LOAD:-?}"
  else
    log "bisect verdict=NONE why=${BISECT_WHY:-unknown} steps=$BISECT_STEPS elapsed=${BISECT_S}s load=${BISECT_LOAD:-?}"
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
#   3. marker $REVERTS/<C> exists ⇒ revert_rearm decides: never twice for a LANDED revert (permanent,
#      and now paged rather than silent), a BOUNDED retry for one that never landed.
#   4. MAX_REVERTS markers written THIS run ⇒ skip. A cascade means the TREE is wrong, not one
#      commit — an operator finding, and continuing would be the fail-closed-amplifier (R7).
#   5. no executable land lane ⇒ skip. This function never pushes anything itself; the ONLY writer
#      to origin stays ship-land.sh, with its esc-scan, CAS, content-verify and land-lock intact
#      (a parked revert is a feature, R8).
# The marker records EVERY attempt past the guards, landed or not, and the never-twice it enforces is
# now BOUNDED — see the REVERT_RETRY_MAX block above for the census that forced that. What must never
# repeat unattended is a revert that SUCCEEDED; an attempt that landed nothing repeated nothing, and
# refusing to try it again at a tip where it might work is how a veto becomes a permission gate.
mk_field() { printf '%s' "$(sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1)"; }
# A TERMINAL skip is the event the budget's expiry converts the standing state into. It gets the two
# surfaces a FAILED attempt already gets — a state-keyed page (retracted by the next green along with
# its postland-revert-* siblings, because on a green the concern is moot) and a DURABLE backlog item
# (the sha in the title defeats wasDone). The page is the loud half; the backlog item is the half
# that survives a green, which is what "page on FAILED revert" has to mean here: the page a FAILED
# attempt already wrote is deletable, while the disarm it announced was not.
revert_inert() { # <culprit> <c12> <reason> <detail>
  local c="$1" c12="$2" reason="$3" detail="$4" pf="$PAGES/postland-revert-inert-$2.page" fresh=1 ftest
  # WHICH SUITE the veto was for, recovered from the marker — the one fact that makes this item
  # ADJUDICABLE, and the one every INERT surface used to drop (2026-08-10, item 50af9e4a4258).
  # This is the asymmetry red_actions already fixed for the RED item ("ONE rendering of the failing
  # NAME for all three artifacts"), reproduced in the terminal arm: the page and the backlog item
  # named a sha, a reason and a count, while `failing=` sat only in the marker on disk. A durable
  # item nobody can act on without archaeology is the unattributed-RED defect wearing a new label.
  #
  # Measured on the item that forced this. Title: "culprit f60b7ca220ee — the veto cannot actuate,
  # 3 of 3 attempts, none landed (last exit 90)". Nothing in it says WHAT was red, so the first
  # question an adjudicator has — is it still red? — cannot even be asked. With the name, it is one
  # `git log` away: `tests/boot-resume-launch.bats` was fixed FORWARD by 612784f8 (Darwin caps
  # sun_path against the string handed to bind(2), not the resulting path), trunk went green on
  # ed095d4b, and the veto's inertness stopped being a capability loss. The name also inverts the
  # remedy — `git revert f60b7ca2` still conflicts today AND would delete bin/cc-kitty-socket, a
  # live dependency — so the surface that omitted it was the surface arguing for a destructive fix.
  #
  # Read from the marker rather than threaded through revert_rearm's signature: the marker IS the
  # record of what the spent attempts were about, and both call sites are reached only from inside
  # `[ -f "$mk" ]`, so it is present by construction. `tests/` matches FAILING's own sentinel for a
  # pre-C26 marker that predates the field — a stale spelling, never a silent empty.
  ftest="$(mk_field "$REVERTS/$c" failing)"; [ -n "$ftest" ] || ftest="tests/"
  # DAMPED ON THE PAGE FILE. A terminal skip is re-reached on EVERY later sweep that convicts the
  # same culprit — b3f728858a6f would have filed 8 items in 2.5 days — and an alarm that fires every
  # sweep carries the same zero bits as one that cannot fire at all (memory: alarm-polarity). The
  # page is the state; the backlog item and the OS notification are the EDGE into it. A green
  # retracts the page, so a fresh red episode is a fresh event and does re-fire — which is right.
  [ -f "$pf" ] && fresh=0
  { now_epoch
    printf 'post-land AUTO-REVERT is INERT for this culprit @ %s\n' "$(now_iso)"
    printf 'culprit: %s (failing %s)\n' "$c12" "$ftest"
    printf 'reason:  %s — %s\n' "$reason" "$detail"
    printf 'the veto did NOT actuate; trunk keeps whatever verdict it has and deploy stays pinned.\n'
    printf 'first:   is %s still red on trunk? a green there makes this moot — fixed FORWARD, and the\n' "$ftest"
    printf '         revert may by now be FORBIDDEN (its files moved on) rather than merely stale.\n'
    printf 'do:      %s status ; sed -n 1,20p %s/%s\n' "$SELF" "$REVERTS" "$c"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  if [ "$fresh" -eq 1 ]; then
    # The page above already names the FIRST question a reader must ask — "is $ftest still red on
    # trunk? a green there makes this moot" — and until now nothing ever asked it. That question IS
    # --falsify-red, so the item now carries it and cc-premise re-asks it at claim time. It is also
    # JOINED to $ftest's condition group, so a RED row naming the same suite holds the lease against
    # this one instead of being dispatched beside it (see file_linked).
    file_linked "$ftest" \
      "post-land AUTO-REVERT INERT ($reason): $ftest @ $c12 — the veto cannot actuate, $detail; check $ftest is still red before reverting" \
      "$(fals_red "$ftest" "$c")"
    notify "Claude post-land AUTO-REVERT INERT" "$c12 — $reason on $ftest; see $pf"
  fi
  log "AUTOREVERT verdict=skipped reason=$reason culprit=$c12 terminal=1 fresh=$fresh ($detail)"
}
# 0 = re-arm (ATTEMPT_N set to this attempt's number) · 1 = skip (this function logs/pages its own).
revert_rearm() { # <marker> <culprit> <c12>
  local mk="$1" c="$2" c12="$3" prev_exit prev_tip prev_epoch n age tip_now moved=0
  prev_exit="$(mk_field "$mk" land_exit)"
  prev_tip="$(mk_field "$mk" tip)"
  prev_epoch="$(mk_field "$mk" epoch)"
  n="$(mk_field "$mk" attempts)"
  # Pre-bound markers carry none of these fields. attempts ⇒ 1 (the attempt that wrote it); epoch and
  # tip ⇒ absent, which reads as decayed-and-moved, so a stranded FAILED marker re-arms ONCE on the
  # first encounter after this lands. That one-time migration is the point, not a side effect.
  case "$n" in ''|*[!0-9]*) n=1 ;; esac
  case "$prev_epoch" in ''|*[!0-9]*) prev_epoch=0 ;; esac
  # UNREADABLE land_exit ⇒ treat as LANDED, i.e. skip. The default decides which way this fails, and
  # the two directions are not symmetric: a wrong "failed" re-reverts a commit already out of trunk
  # and re-lands the bad change (the revert war guard 2 exists to stop), while a wrong "landed"
  # leaves the veto inert — the status quo, and now a paged one.
  case "$prev_exit" in ''|*[!0-9]*) prev_exit=0 ;; esac
  if [ "$prev_exit" -eq 0 ]; then
    # Convicted AGAIN after its own revert landed: the culprit's content is already out of trunk, so
    # the bisect is naming a commit that has been handled and the surviving red has another cause.
    # Nothing here can fix that, and a human must look — which is exactly what eight silent skips of
    # b3f728858a6f did not cause to happen.
    revert_inert "$c" "$c12" already-reverted \
      "its revert LANDED and it is convicted again — the surviving red has another cause"
    return 1
  fi
  if [ "$n" -ge "$REVERT_RETRY_MAX" ]; then
    revert_inert "$c" "$c12" retry-budget-spent \
      "$n of $REVERT_RETRY_MAX attempts, none landed (last exit $prev_exit)"
    return 1
  fi
  tip_now="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"
  [ -n "$tip_now" ] && [ "$tip_now" != "$prev_tip" ] && moved=1
  age=$(( $(now_epoch) - prev_epoch ))
  if [ "$moved" -eq 0 ] && [ "$age" -lt "$REVERT_RETRY_DECAY_S" ]; then
    # Same tip, inside the decay window: nothing has happened that could change the answer. This is
    # the ONLY non-terminal skip, so it stays log-only — paging on it would train the operator to
    # ignore the class, and the terminal skip above is the one that carries information.
    log "AUTOREVERT verdict=skipped reason=failed-at-this-tip culprit=$c12 attempt=$n/$REVERT_RETRY_MAX age=${age}s tip=$(sha12 "${prev_tip:-none}")"
    return 1
  fi
  ATTEMPT_N=$((n+1))
  log "AUTOREVERT rearm culprit=$c12 attempt=$ATTEMPT_N/$REVERT_RETRY_MAX prev_exit=$prev_exit why=$( [ "$moved" -eq 1 ] && echo new-tip || echo "decay-${age}s" )"
  return 0
}
auto_revert() { # <culprit> <failing-file> — 0 = attempted (marker written), 1 = skipped
  local c="$1" file="${2:-tests/}" c12 br wt mk rc=1 rev="" step="mint" outcome pf sid tip=""
  c12="$(sha12 "$c")"
  [ "$AUTOREVERT" = "off" ] && { log "AUTOREVERT verdict=skipped reason=kill-switch culprit=$c12"; return 1; }
  git -C "$REPO" log -1 --format=%s "$c" 2>/dev/null | grep -q '^Revert' \
    && { log "AUTOREVERT verdict=skipped reason=culprit-is-itself-a-revert culprit=$c12"; return 1; }
  mkdir -p "$REVERTS" 2>/dev/null || true
  mk="$REVERTS/$c"
  ATTEMPT_N=1
  [ -f "$mk" ] && { revert_rearm "$mk" "$c" "$c12" || return 1; }
  case "$MAX_REVERTS" in ''|*[!0-9]*) MAX_REVERTS=2 ;; esac
  [ "$REVERTS_THIS_RUN" -ge "$MAX_REVERTS" ] \
    && { log "AUTOREVERT verdict=skipped reason=cap-$MAX_REVERTS-this-run culprit=$c12"; return 1; }
  [ -n "$REPO_SHIP" ] && [ -x "$REPO_SHIP" ] \
    || { log "AUTOREVERT verdict=skipped reason=no-land-lane ($REPO_SHIP) culprit=$c12"; return 1; }

  # ── GUARD: THE CULPRIT MUST BE IN THE TRUNK WE ARE ABOUT TO REVERT FROM (2026-08-09, item a31d1fe3de3d)
  # Everything below reverts FROM origin/main — `worktree add … origin/main`, then `git revert $c`.
  # Nothing until now checked that $c is REACHABLE from there, and it is routinely not: the sweep
  # captures `target=origin/main` at entry and the corpus then runs for the better part of an hour,
  # during which the land lane REBASES. A branch that lands in that window re-writes the shas the
  # sweep is standing on, so the captured target is orphaned and every commit the bisect can name
  # off it is a PRE-REBASE sha whose patch reached trunk under a DIFFERENT one.
  #
  # Measured, not reasoned (this box, item a31d1fe3de3d): the 2026-08-01T04:29Z run measured
  # 86774743ffcd, which is not an ancestor of origin/main — its patch is in trunk as fa78e662. The
  # bisect off it named 57e162494c10, also not in trunk; ITS patch is in trunk as 28949c7b, with
  # five commits built on top including 71e96bcbc825, the current last-green. `git revert` then
  # asked a tree that never had 57e162494c10 applied from that parent to un-apply it — conflict,
  # rc 90, revert=none, and a page whose remedy re-runs the same impossible revert by hand.
  #
  # rc 90 is the MILD outcome. The conflict is what stopped it; a culprit whose lines happen not to
  # have moved reverts CLEANLY and the land lane puts it on trunk — reverting a patch by CONTENT
  # while trunk carries a different-sha twin, on a premise nothing checked. That is the f323b427
  # shape (2026-08-06, a correct cc-queue fix reverted, permanent red restored, re-landed by
  # 12549d8b), reached by a different route: there the walk convicted an innocent commit, here the
  # walk is internally sound and the HISTORY it walked is the thing that is no longer trunk.
  # 47a5350498ee is the live proof this half is reachable — not in trunk, and its revert APPLIED.
  #
  # So the ancestry test is not a conflict predictor and must not be read as one: it decides whether
  # reverting is a MEANINGFUL operation against this trunk at all. Refuse before the budget is spent
  # and before any marker is written — nothing was attempted, so nothing should be recorded as an
  # attempt. The fetch moves up here because the guard must test the SAME tip the revert will use.
  bounded 120 git -C "$REPO" fetch origin main >/dev/null 2>&1 || true
  tip="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"
  # Two distinct not-permitted states, two distinct tokens: an unresolvable trunk ref is a BLIND
  # instrument, a resolved one that does not contain $c is a PROVEN non-ancestor. Collapsing them
  # would report the blind case as a finding about the culprit.
  [ -n "$tip" ] \
    || { log "AUTOREVERT verdict=skipped reason=no-trunk-ref culprit=$c12 (origin/main unresolvable — cannot prove the premise)"; return 1; }
  git -C "$REPO" merge-base --is-ancestor "$c" "$tip" 2>/dev/null \
    || { log "AUTOREVERT verdict=skipped reason=culprit-not-in-trunk culprit=$c12 tip=$(sha12 "$tip") (orphaned by a rebase-land; its patch is in trunk under another sha — revert it there, or fix FORWARD)"; return 1; }

  REVERTS_THIS_RUN=$((REVERTS_THIS_RUN+1))               # counted at ATTEMPT, so the cap bounds attempts
  # PROVISIONAL marker, written BEFORE the work and rewritten after it. The retry budget must count
  # attempts STARTED, exactly as REVERTS_THIS_RUN does one line above: this path spends up to
  # 120s+120s+SHIP_TO under a launchd job that really does get pkill'd (that is what a CUT is), and a
  # budget that only shrank on completion would let a reliably-killed attempt re-arm forever — the
  # unbounded gate this whole change removes, inverted. land_exit=99 is the in-flight/killed
  # sentinel: non-zero, so it reads as FAILED (accurate — nothing landed) and stays inside the
  # bounded-retry arm rather than falling into the permanent already-reverted one.
  { printf 'ts=%s\nepoch=%s\nculprit=%s\nattempts=%s\ntip=%s\nfailing=%s\nstep=in-flight\nland_exit=99\n' \
      "$(now_iso)" "$(now_epoch)" "$c" "$ATTEMPT_N" "${tip:-none}" "$file"; } > "$mk" 2>/dev/null || true
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
    printf 'epoch=%s\n' "$(now_epoch)"
    printf 'culprit=%s\n' "$c"
    printf 'attempts=%s\n' "$ATTEMPT_N"
    printf 'tip=%s\n' "${tip:-none}"
    printf 'revert=%s\n' "${rev:-none}"
    printf 'branch=%s\n' "$br"
    printf 'failing=%s\n' "$file"
    printf 'step=%s\n' "$step"
    printf 'land_exit=%s\n' "$rc"
  } > "$mk" 2>/dev/null || true

  # A landed revert and a failed one share this premise: $file was broken by $c. Whichever way the
  # attempt went, a full-corpus green that CONTAINS $c settles it — the revert worked, someone fixed
  # forward, or the suite left the corpus. That is one meaning, and --falsify-red is how it is asked.
  # The sha in the title keeps each ATTEMPT its own row (it defeats wasDone) — and file_linked then
  # joins that row to $file's condition group, because "revert attempt N on this suite" and "this
  # suite is red on trunk" are two rows naming ONE piece of work. This exact pair is what
  # 4f657ed3e064 was filed about; the lease is what stops both being dispatched.
  file_linked "$file" \
    "post-land AUTO-REVERT $outcome: $file @ $c12 (revert ${rev:-none} on $br)" \
    "$(fals_red "$file" "$c")"
  sid="$(author_sid "$c")"
  [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ] \
    && "$NOTIFY_BIN" "$sid" "post-land AUTO-REVERT $outcome — your land $c12 failed $file in the trunk verifier; revert branch $br" >/dev/null 2>&1
  if [ "$rc" -ne 0 ]; then
    # The revert did NOT land: trunk is still red, deploy stays pinned to the last green (R3 holds
    # by construction), and this needs a human. State-keyed page, same protocol as the RED page.
    #
    # TWO DIFFERENT FAILURES SHARE THIS PAGE, and until 2026-08-07 they shared one remedy. At
    # step=land the revert commit EXISTS on $br and did not reach trunk, so hand-landing that branch
    # is exactly right. At step=revert (rc 90) the revert CONFLICTED and applied nothing, so $br is
    # a bare copy of origin/main — and the same `do:` line then ships a branch with ZERO commits on
    # it. That lands nothing, exits clean, and reads to the operator as "the revert is in". The
    # page's own `branch:` line printed `revert commit none` two lines above the remedy that assumed
    # one existed. Measured on the live box 2026-08-07: postland-revert-13bfa557db3a, standing page
    # from 03:40Z, `git rev-list --count origin/main..postland-revert-13bfa557db3a` = 0 — and rc 90
    # is the COMMON half, 4 of the 5 FAILED attempts in the all-time census (the other 3 rc-90
    # markers: 57e162494c10, d25c4dd47384, a1743ffebd35, which is the item that filed this).
    # So branch on what actually EXISTS ($rev), never on the exit code: the remedy for "no revert
    # commit was ever made" is to make one, and it is the operator who has to resolve the conflict.
    pf="$PAGES/postland-revert-$c12.page"
    { now_epoch
      printf 'post-land AUTO-REVERT FAILED @ %s\n' "$(now_iso)"
      printf 'culprit: %s (failing %s)\n' "$c12" "$file"
      printf 'step:    %s (exit %s%s)\n' "$step" "$rc" \
        "$( [ "$rc" -eq 124 ] && printf ' — OUR %ss bound fired' "$SHIP_TO" || true )"
      printf 'trunk is STILL RED; deploy stays pinned to the last green stamp.\n'
      # The cell is `manual-revert-*`, NOT `wt-revert-manual`. reap_stale_worktrees deletes anything
      # under $WT_ROOT matching `wt-run-*` or `wt-revert-*` older than WT_STALE_S (8h) — and it is
      # deliberately blind to whose cell it is, "never by is-it-mine, which is exactly the cell a
      # crash leaves unclaimed". The old path sat inside that glob, so the one remedy that asks the
      # operator for HAND-WORK — resolving a revert conflict — parked it where the next sweep would
      # delete it, unresolved conflict and all. `manual-revert-` matches neither glob, and the
      # branch is `revert-*` rather than `postland-revert-*` for the same reason: the branch reaper
      # below is scoped to the machine's own namespace and must never reach the operator's.
      if [ -n "$rev" ]; then
        printf 'branch:  %s (revert commit %s) — worktree already torn down\n' "$br" "$rev"
        printf 'do:      git -C %s worktree add %s/manual-revert-%s %s && cd %s/manual-revert-%s && %s\n' \
          "$REPO" "$WT_ROOT" "$c12" "$br" "$WT_ROOT" "$c12" "$REPO_SHIP"
      else
        printf 'branch:  none — the revert CONFLICTED and applied nothing, so %s held no commit and was dropped\n' "$br"
        printf 'do:      git -C %s worktree add -b revert-%s %s/manual-revert-%s origin/main && cd %s/manual-revert-%s && git revert %s\n' \
          "$REPO" "$c12" "$WT_ROOT" "$c12" "$WT_ROOT" "$c12" "$c"
        printf 'then:    resolve the conflict, git revert --continue, and land it with %s — or fix the red FORWARD, which the next green retracts this page for.\n' "$REPO_SHIP"
      fi
      printf 'env:     %s\n' "$ENV_FP"
    } > "$pf" 2>/dev/null || true
    notify "Claude post-land AUTO-REVERT FAILED" "$c12 — trunk still red, see $pf"
  fi
  log "AUTOREVERT verdict=$outcome culprit=$c12 attempt=$ATTEMPT_N/$REVERT_RETRY_MAX revert=$(sha12 "${rev:-none}") branch=$br step=$step rc=$rc"
  wt_remove "$wt"; WT_REVERT=""
  # KEEP the branch in exactly ONE case: it is the only copy of something. A LANDED revert's branch
  # is now in trunk and carries nothing else. A revert that never APPLIED left the branch identical
  # to origin/main, and the old rule — keyed on `rc`, with the stated reason "a FAILED one is the
  # only copy of the revert commit" — kept that one too, on a premise that is FALSE for rc 90: there
  # is no revert commit to be the only copy of. That empty branch is what made the page's remedy
  # look actionable, so dropping it is half of the same fix. Keyed on $rev, which is the thing being
  # preserved; `branch -D` on a name `worktree add` never created (rc 91) is a harmless no-op.
  if [ "$rc" -eq 0 ] || [ -z "$rev" ]; then
    case "$br" in
      postland-revert-*) bounded 30 git -C "$REPO" branch -D "$br" >/dev/null 2>&1 || true ;;
    esac
  fi
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
    # ── NAME A CULPRIT ONLY WHEN ONE WAS CONVICTED (2026-08-17, backlog ebbf3adfb4d0) ─────────────
    # `culprit` falls back to the TARGET sha when the bisect abstained — that fallback exists to key
    # the page file and to route the courtesy ping, and it was never a verdict. Rendering it under
    # the word "culprit (bisected from last-green …)" turned the fallback INTO one on disk: the sha
    # is the tip of the landing window, so whoever landed last acquires a permanent RED in the page
    # store for a suite nothing showed they touched. Say which of the two this is, in the line that
    # carries the sha, and put the walk's own numbers beside it — steps, wall, and the load AT the
    # verdict, which is what tells a regression from a starved box.
    if [ -n "$bisected" ]; then
      printf 'culprit: %s (bisected from last-green %s)\n' "$c12" "$(sha12 "${good:-unknown}")"
    else
      printf 'culprit: NO VERDICT — the bisect convicted nothing (%s); RED observed at %s, which is where the window ENDS, not a commit shown to cause it\n' \
        "${BISECT_WHY:-unknown}" "$c12"
    fi
    printf 'bisect:  steps=%s elapsed=%ss load-at-verdict=%s (last-green %s)\n' \
      "$BISECT_STEPS" "$BISECT_S" "${BISECT_LOAD:-?}" "$(sha12 "${good:-unknown}")"
    printf 'failing: %s::%s\n' "$file" "$ftest"
    [ "${#FAILING[@]}" -gt 1 ] && printf 'all failing: %s\n' "${FAILING[*]}"
    printf 're-run:  git -C %s worktree add --detach /tmp/pv-repro %s && cd /tmp/pv-repro && bats %s\n' \
      "$REPO" "$c12" "$file"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
  # ── FILE EVERY FAILING ENTRY, ONE CONDITION-KEYED ITEM EACH (2026-08-07) ──────────────────────
  # Was: ONE `add` for $file — i.e. FAILING[0] — keyed on project+title+source with the sha IN THE
  # TITLE, so "sha defeats wasDone" and each run minted a fresh item for whatever happened to sort
  # first. Both halves were wrong, in opposite directions, and they hid each other:
  #   · per-EVENT key ⇒ 69 RED runs minted 69 items for the SAME standing reds (the defect memory
  #     per-event-key-defeats-per-finding-dedupe names: page per-EVENT, backlog per-FINDING);
  #   · FAILING[0] only ⇒ 472 failing-suite observations across those runs produced 69 filings, and
  #     38 of the 58 distinct suites were filed ZERO times — invisible not by accident but BY
  #     CONSTRUCTION, since FAILING is TAP/corpus-ordered and a suite that never sorts first can
  #     never be reached. tests/gate-home-isolation.bats is the worst case: 28 appearances, 0
  #     filings, because a 'c'-named suite outsorts a 'g' every time. It has zero rows in
  #     flakes.jsonl, so it was never a flake being correctly withheld — just never looked at.
  # Now: one item per entry, keyed on the CONDITION (cond_slug — "this suite is red on trunk"),
  # which is stable across runs, so the second and subsequent sweeps are idempotent `has_id` no-ops
  # rather than new items. The sha stays in the TITLE, where it is DISPLAYED but is not identity —
  # exactly what cc-backlog's own --condition refusal message prescribes.
  # The PAGE is untouched and stays per-EVENT (state-keyed by culprit sha, cleared on green): the
  # two artifacts are supposed to have different lifetimes, and only the backlog is durable.
  if [ -x "$BACKLOG_BIN" ]; then
    local i n fentry fname ftitle berr brc nfiled=0 refused=0 skipped=0
    n="${#FAILING[@]}"
    for ((i = 0; i < n; i++)); do            # builtin, not `seq` — this path runs starved
      # A pathological all-red tree must not fork one `cc-backlog` per suite on a path that runs
      # starved by definition. The cap is far above anything observed (worst run: 10 entries) and,
      # when it DOES bite, the dropped names are logged rather than silently swallowed — a silent
      # cap is the same class of bug as the FAILING[0] one this replaces.
      # Keyed on ATTEMPTS ($i), not on $nfiled: the cap exists to bound the number of FORKS on a
      # starved path, and a run where every add is refused increments nfiled zero times — so a
      # success-keyed cap would not bound anything in exactly the degenerate case it is for.
      if [ "$i" -ge "$BACKLOG_MAX" ]; then
        skipped=$((n - i))
        log "backlog CAP $BACKLOG_MAX reached — NOT filed (${skipped} entries): ${FAILING[*]:$i}"
        break
      fi
      fentry="${FAILING[$i]}"
      # `${FAILNAME[i]:-}` deliberately, not an aligned read: SYNTAX_BAD is spliced onto FAILING
      # wholesale by the caller and pads no name, so the tail is legitimately unnamed.
      fname="${FAILNAME[$i]:-}"; fname="${fname//[$'\n\r']/ }"; fname="${fname:0:120}"
      [ -n "$fname" ] || fname='?'
      ftitle="post-land RED: $fentry::$fname @ $c12"
      # stderr is CAPTURED, not discarded: a --condition add against an item already marked done
      # warns and deliberately does NOT re-open (cc-backlog's DONE-GUARD). Swallowing that would
      # make a RECURRENCE invisible — the exact failure mode being fixed — so it goes to runner.log.
      berr="$("$BACKLOG_BIN" add --title "$ftitle" --condition "$(cond_slug "$fentry")" \
                --project claude-infrastructure --source postland-verify 2>&1 >/dev/null)"; brc=$?
      # COUNT THE CHECKED OUTCOME, NOT THE ATTEMPT. The obvious shape here is `… || true` followed
      # by an unconditional `nfiled++`, and it logs "filed=3" for three adds that were all REFUSED —
      # a fake success, and on the one path whose entire purpose is to stop failures going unseen
      # (memory claimed-outcome-vs-checked-outcome). rc 2 is exactly what cc-backlog returns for a
      # condition key it will not accept, so this is the live case, not a hypothetical one.
      if [ "$brc" -ne 0 ]; then
        refused=$((refused + 1))
        log "backlog REFUSED rc=$brc for $fentry — NOT filed: ${berr//$'\n'/ }"
      else
        nfiled=$((nfiled + 1))
        case "$berr" in
          # A recurrence of a CLOSED condition is deliberately not re-opened by cc-backlog's
          # DONE-GUARD. Discarding its stderr would make that recurrence invisible — the exact
          # failure mode this whole change exists to fix — so it lands in runner.log instead.
          *'already DONE'*) log "backlog RECURRED (closed item, NOT re-opened — needs \`reopen --force\`): $fentry" ;;
          ?*)               log "backlog add noise for $fentry: ${berr//$'\n'/ }" ;;
        esac
      fi
    done
    log "backlog verdict=filed n=$nfiled refused=$refused skipped=$skipped of=$n (condition-keyed, idempotent across sweeps)"
  fi
  notify "Claude post-land RED" "$file fails at $c12 — see $pf"
  sid="$(author_sid "$culprit")"
  # The PEER ping is an accusation when a bisect convicted and a courtesy when it did not, and the
  # wording has to differ or the abstention is invisible to the one session that acts on it. "(your
  # land)" over an unconvicted sha is exactly how the originating chain gets paged for a fault it
  # did not cause — the sha is merely where the window ends.
  if [ -n "$sid" ] && [ -x "$NOTIFY_BIN" ]; then
    if [ -n "$bisected" ]; then
      "$NOTIFY_BIN" "$sid" "post-land RED: $file::$ftest at $c12 (your land) — see $pf" >/dev/null 2>&1
    else
      "$NOTIFY_BIN" "$sid" "post-land RED: $file::$ftest observed after your land $c12 — NO bisect verdict (${BISECT_WHY:-unknown}, load ${BISECT_LOAD:-?}); NOT attributed to your commit — see $pf" >/dev/null 2>&1
    fi
  fi
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
  # THE PROBE TAKES $sha, THE COMMIT — never the $tree in the title. --falsify-red compares against
  # last-green with `merge-base --is-ancestor`, which only speaks about commits; handing it a tree
  # sha makes `rev-parse <tree>^{commit}` fail and the probe answers "could not ask" on every single
  # run — a falsifier that is inert by construction, which is the one outcome indistinguishable from
  # never having emitted one. A wedged suite also keeps the corpus from ever going green, so this
  # correctly stays at "still live" for exactly as long as the hang does.
  # Linked for the same reason as the two AUTO-REVERT sites, and it is NOT redundant here even
  # though a hang and a red are different verdicts: a wedged suite keeps the corpus from ever going
  # green, so the very next sweep that classifies it as a failure files a `post-land RED` row for
  # the SAME suite — one wedge, two rows, both dispatchable. The tree in the title keeps each hang
  # episode its own row; the condition is what tells guard (6) they are one piece of work.
  file_linked "$file" \
    "post-land HUNG: $file wedged at $WEDGE_AT @ $(sha12 "$tree") — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)" \
    "$(fals_red "$file" "$sha")"
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
  RUN_TMP="$(mktemp -d "$TMPBASE/$RUN_TMPL")" || return 1   # do_bisect probes under this very string
  FAILING=(); FAILNAME=(); FAILTEST=""; RETRIES=0; NFLAKE=0; CUT=0; LADDER_UNPROVEN=0; CORPUS_N=0   # reset per requeue pass
  LADDER_FAILING=(); CONVICT_PENDING=0                                     # C29, same reset scope
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
    local stall poll cpid last ndone still grace preplan planned cutby
    stall="${POSTLAND_STALL_S:-900}"; poll="${POSTLAND_STALL_POLL_S:-60}"
    case "$stall$poll" in *[!0-9]*) stall=900; poll=60 ;; esac
    grace="$(pre_plan_grace "$CORPUS_N")"     # see THE PRE-PLAN GRACE by FILE_TO for the arithmetic
    if [ "$stall" -eq 0 ] || [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then
      ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" bounded "$SUITE_TO" "${QOS[@]}" "$BATS_BIN" "${bargs[@]}" ) </dev/null > "$tap" 2>&1; rc=$?
    else
      # EXPLICIT on the async branch too. bash redirects an asynchronous command's stdin from
      # /dev/null only when job control is OFF — true for this script today, and exactly the kind
      # of ambient property that stops being true (one `set -m`, one interactive re-entry). The
      # whole corpus is behind it; it does not get to depend on a default.
      ( cd "$WORKTREE" && TMPDIR="$RUN_TMP" exec "$TIMEOUT_BIN" -k 10 "$SUITE_TO" "${QOS[@]}" "$BATS_BIN" "${bargs[@]}" ) </dev/null > "$tap" 2>&1 &
      # TWO PHASES, TWO CLOCKS. Until the `1..N` line lands, bats is COUNTING and there is no
      # per-line signal to key on — tap_done is 0 for a healthy run and a wedged one alike, so the
      # only honest bound on that phase is a wall, and it gets its own (grace, derived above). The
      # stall clock starts when the plan does. `still=0` on the transition is the load-bearing line:
      # without it the pre-plan seconds would carry into the progress clock and cut the corpus a
      # few polls into its first real test.
      cpid=$!; last=0; still=0; preplan=0; planned=0; cutby=""
      [ "$grace" -gt 0 ] || planned=1              # grace 0 = kill switch: one clock, from t=0
      while kill -0 "$cpid" 2>/dev/null; do
        sleep "$poll"
        if [ "$planned" -eq 0 ] && tap_planned "$tap"; then
          planned=1; still=0
          log "corpus: bats finished counting after ${preplan}s (plan $(tap_plan "$tap")) — stall clock starts"
        fi
        if [ "$planned" -eq 0 ]; then
          preplan=$(( preplan + poll ))
          [ "$preplan" -lt "$grace" ] && continue
          log "PRE-PLAN STALL: no '1..N' plan line after ${preplan}s (grace ${grace}s over $CORPUS_N suite(s)) — bats never finished counting; cutting the run"
          cutby=preplan; kill -TERM "$cpid" 2>/dev/null || true
          break
        fi
        ndone="$(tap_done "$tap")"; ndone="${ndone:-0}"
        if [ "$ndone" -gt "$last" ]; then last="$ndone"; still=0; else still=$(( still + poll )); fi
        if [ "$still" -ge "$stall" ]; then
          log "STALL: no TAP progress for ${stall}s at test $last — cutting the run (a stall, not slowness)"
          cutby=stall; kill -TERM "$cpid" 2>/dev/null || true
          break
        fi
      done
      wait "$cpid" 2>/dev/null; rc=$?
      # EITHER cut presents as the bound firing: classify_hang keys on 124 and will name the wedged
      # file from the TAP index. A PRE-PLAN cut carries ndone=0, so that index is 1 and the suspect
      # is the FIRST corpus file — a guess, because a wedge while GATHERING can be on any file. It is
      # a safe guess only because classify_hang confirms it: the suspect is re-run alone and a
      # mis-map degrades to a CUT rather than convicting the wrong suite (its own comment, "a
      # mis-mapped suspect can only LOSE a hang, never invent one"). That is why routing a pre-plan
      # cut through the SAME 124 is right rather than merely convenient — it inherits the adjudication.
      # timeout's own ceiling already exits 124; unify both TERM paths onto it.
      # Keyed on cutby — the LOOP's own record of why it broke — never re-derived from the counters:
      # re-testing `still -ge stall` here would be a second copy of the predicate that decided, and
      # the two can disagree at the boundary (a plan line arriving on the same poll that exhausted
      # the grace resets `still` while `preplan` stays at the limit). memory: make-the-actuator-the-arbiter.
      [ -n "$cutby" ] && rc=124
    fi
  fi
  adv="$(sc_count)"
  [ "$rc" -eq 0 ] || classify_failures "$tap" "$rc"
  # C29 — BEFORE the SYNTAX_BAD splice, for two reasons: those findings are DETERMINISTIC and must
  # never be delayed by a corroboration round they cannot fail, and this is the last point at which
  # FAILING and FAILNAME are still index-aligned 1:1 (the splice pads no names, by design).
  corroborate_convictions "$tree"
  [ "${#SYNTAX_BAD[@]}" -eq 0 ] || FAILING+=("${SYNTAX_BAD[@]}")
  identity_assert            # did anything we just ran write a git identity into the shared config?
  # A meta-lint whose own bound fired proves nothing — so an otherwise-clean run may NOT be stamped
  # green off the back of a check that never returned. Downgrade to the cut path: honest, retried
  # next sweep, and cool-off/paged by the existing CUT_MAX ladder if the tree keeps doing it.
  # Same rule for a RETRY whose own bound fired (C23): the file was neither convicted nor cleared, so
  # the run proved nothing about this tree. Green would be unearned; red would be the lie that kept
  # every stamp red and deploy refused. Cut says it honestly and the next sweep retries.
  # C29 joins the same clause for the same reason: a conviction seen in ONE load window neither
  # convicted nor cleared the file, so this run proved nothing about this tree. Cut says exactly
  # that, keeps the tree unstamped-green so C5's abstain does not fire, and hands the NEXT sweep the
  # second window — which is the whole mechanism, obtained without scheduling a single extra run.
  { [ "$PRELINT_UNPROVEN" = 1 ] || [ "$LADDER_UNPROVEN" = 1 ] || [ "$CONVICT_PENDING" = 1 ]; } \
    && [ "${#FAILING[@]}" -eq 0 ] && CUT=1
  run_s="$(( $(now_epoch) - t0 ))"
  if [ "$CUT" = "1" ] && [ "${#FAILING[@]}" -eq 0 ] && classify_hang "$tap" "$rc"; then
    # HUNG is carved out of the cut population and IS a verdict about the tree: it reproduced here,
    # at this load, on a pristine detached checkout. Stamp it so the tree is not re-run forever, and
    # page the FILE with the fix that actually applies (timeout-wrap the seam), not "retry when
    # quieter" — which is the one response guaranteed never to clear it.
    write_stamp "$tree" "$sha" hung "$run_s" "$RETRIES" "$adv" "${SUSPECT:-tests/}"
    cut_clear; conviction_clear                 # a verdict was reached: streak over, candidates spent
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
    # $CUT_WHY, not a fixed "run truncated": the two cut populations need OPPOSITE things said about
    # them. A truncation means NO test failed; a C29 pending means a test DID fail and is one load
    # window short of proof. The log line one above already reads CUT_WHY — this one asserted the
    # truncation unconditionally, which would have described every C29 cut wrongly.
    echo "postland-verify: CUT $(sha12 "$sha") (${run_s}s) - $CUT_WHY; not red, retrying next sweep"
  elif [ "${#FAILING[@]}" -eq 0 ]; then
    write_stamp "$tree" "$sha" green "$run_s" "$RETRIES" "$adv"
    printf '%s\n' "$sha" > "$LASTGREEN"
    cut_clear; conviction_clear                 # a verdict was reached: streak over, candidates spent
    # A now-passing state clears every standing page. postland-revert-* belongs in that set and was
    # the one class missing from it: a FAILED auto-revert's page asserts "trunk is STILL RED" and
    # hands the operator a `do:` line to land the revert BY HAND, and neither claim survives a
    # green — the red is gone, so the remedy has become the wrong action (at best a no-op, at worst
    # re-reverting a commit whose red was fixed forward, per memory
    # work-item-remedy-can-become-forbidden). Nothing durable is lost: the never-twice record is the
    # $REVERTS/<culprit> marker, which this does not touch. Measured 2026-08-06 — 5 standing revert
    # pages, oldest a week old, against 0 red/cut/hung: the classes that ARE retracted had none, so
    # the omission is the whole reason the channel filled with stale ones.
    rm -f "$PAGES"/postland-red-*.page "$PAGES"/postland-cut-*.page \
          "$PAGES"/postland-hung-*.page "$PAGES"/postland-revert-*.page 2>/dev/null || true
    log "GREEN $(sha12 "$sha") tree=$(sha12 "$tree") run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    echo "postland-verify: GREEN $(sha12 "$sha") (${run_s}s, flakes=$NFLAKE)"
  else
    write_stamp "$tree" "$sha" red "$run_s" "$RETRIES" "$adv" "${FAILING[@]}"
    cut_clear; conviction_clear                 # a verdict was reached: streak over, candidates spent
    log "RED $(sha12 "$sha") failing=${FAILING[*]} run_s=$run_s retries=$RETRIES flakes=$NFLAKE sc_adv=$adv"
    red_actions "$sha" "${FAILING[0]}"
    echo "postland-verify: RED $(sha12 "$sha") — ${FAILING[*]}"
  fi
  rm -rf "$RUN_TMP"; RUN_TMP=""
  return 0
}

# ════ verbs ═══════════════════════════════════════════════════════════════════════════════════════
# Runs on EVERY 300s tick, BEFORE any abstain — and that placement is the entire point.
#
# identity_assert lives inside run_target, which do_run_if_needed skips on `already-stamped`,
# `cut-cooloff` and `lock-held`. On a quiet trunk it is therefore never reached, and with
# githooks/pre-commit installed that closes a CIRCLE: a resident bad identity refuses every commit,
# while only a NEW commit would produce the unstamped tree whose sweep would clear it. The box
# would sit unable to commit until a human ran the cure by hand — fail-closed is the right answer
# for one commit and the wrong resting state for a machine.
#
# Deliberately silent and verdict-free: two config reads, never appends to FAILING, and cannot fail
# wider than itself. It only ever REMOVES an unsanctioned local override, handing the repo back to
# the global SSOT; it never writes an identity of its own.
identity_resident_guard() {
  local now
  now="$(identity_snapshot)"
  [ -n "$now" ] || return 0                    # no local override at all ⇒ the healthy default
  identity_snap_ok "$now" && return 0          # a sanctioned override is legal — leave it alone
  log "IDENTITY: resident unsanctioned [user] in $REPO [${now}] — DROPPING ahead of the abstain gate; falls through to the global identity"
  git -C "$REPO" config --local --remove-section user >/dev/null 2>&1 || true
}

# Re-assert that the identity GATES are still installed. Same tick, same reasoning, and it closes
# the last structural gap the red-team named: scripts/git-identity-assert.sh had ZERO invoking
# callers — not a plist, not install.sh, not a hook, not cron — so the sensor built to notice a
# missing gate was itself only ever run by hand. A guard nobody runs is the original fault (a
# defence with no sensor) repeated one layer out.
#
# Hooks are COPIES now (a symlink into the working tree dangled on any older checkout), so what
# this catches is deletion or a re-init, not a dangle. Idempotent and silent when nothing is
# missing; it logs only when it actually restored something, so the log carries EVENTS rather than
# a heartbeat that nobody would read.
identity_hooks_guard() {
  local cdir hookdir src h from restored=0
  cdir="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  hookdir="$cdir/hooks"; [ -d "$hookdir" ] || return 0
  src="$REPO/githooks"; [ -d "$src" ] || return 0    # older checkout: nothing to assert from
  for h in pre-commit pre-push pre-merge-commit; do
    [ -e "$hookdir/$h" ] && continue
    case "$h" in pre-merge-commit) from="$src/pre-commit" ;; *) from="$src/$h" ;; esac
    [ -f "$from" ] || continue
    cp "$from" "$hookdir/$h" 2>/dev/null || continue
    chmod +x "$hookdir/$h" 2>/dev/null || true
    restored=$((restored+1))
  done
  [ "$restored" -gt 0 ] && log "IDENTITY: re-installed $restored missing git identity hook(s) in $REPO"
  return 0
}

do_run_if_needed() {
  local target tree new loops=0
  identity_resident_guard                      # BEFORE every abstain — see the note above
  identity_hooks_guard                         # …and the gates themselves must still be there
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
  [ -n "$c" ] || { echo "postland-verify: bisect undecidable (${BISECT_WHY:-unknown}; steps=$BISECT_STEPS elapsed=${BISECT_S}s load=${BISECT_LOAD:-?})" >&2; return 1; }
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
# A VERDICT SPENDS THE CANDIDATES (C29) — called at exactly the three sites cut_clear is, and for the
# same reason: candidate rows are suspicion accumulated TOWARD a verdict, so once one is reached they
# are spent. Without this the ledger's 24h TTL becomes a trap. File F is convicted once (window 1,
# cut); the next sweep proves the whole corpus GREEN, exonerating F; hours later F fails once on some
# unrelated tree — and the stale row from before the exoneration corroborates it into an instant RED
# off a single window, which is the exact defect C29 exists to prevent, rebuilt out of its own state.
conviction_clear() { rm -f "$CONVICTIONS" 2>/dev/null || true; }
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
    printf 'cut:     %s consecutive runs reached NO verdict.\n' "$3"
    # The two cut populations need OPPOSITE things said about them, and a page that guesses is worse
    # than no page. A TRUNCATION means no test failed at all; a C29 pending means a test DID fail and
    # is one load window short of proof. Printing "ZERO not ok, do not bisect" over the second would
    # send the operator hunting a machine event that never happened. Branched on CONVICT_PENDING
    # rather than on the CUT_WHY text, so a later reword of that string cannot silently flip the page.
    if [ "${CONVICT_PENDING:-0}" = 1 ]; then
      printf '         %s\n' "$CUT_WHY"
      printf 'A test DID fail here — it is simply not PROVEN, having failed in ONE load window only.\n'
      printf 'The next sweep re-runs this tree and decides it. Ledger: %s\n' "$CONVICTIONS"
    else
      # Quotes $TAP_NOTOK_RE rather than a hand-spelled "not ok": the cut's claim is about RESULT
      # lines, and a hint LOOSER than the predicate sends the reader grepping up a torn line the
      # cut deliberately did not count — then disbelieving a page that was right (C30).
      printf '         The suite emitted ZERO result lines matching %s, so NO test failed.\n' "$TAP_NOTOK_RE"
      printf '         Each run was TRUNCATED before reaching a verdict (peer pkill / OOM / load).\n'
      printf 'NOT a test failure — do not bisect. Re-run on a quiet box:\n'
    fi
    printf 're-run:  git -C %s worktree add --detach /tmp/pv-repro %s && cd /tmp/pv-repro && bats tests/\n' \
      "$REPO" "$(sha12 "$1")"
    printf 'env:     %s\n' "$ENV_FP"
  } > "$pf" 2>/dev/null || true
}
# fals_red <suite> <sha> → the STORED FALSIFIER string for an item about <suite> breaking at <sha>.
#
# Addressed at the LIVE layer rather than at $SELF, and left with `$HOME` UNEXPANDED: cc-premise runs
# the stored string through `/bin/sh -c`, so it resolves at probe time. $SELF here is whichever
# checkout ran the verifier — routinely a detached worktree — and baking that path into a record that
# outlives the run would pin the probe to a directory that gets reaped, leaving the item carrying a
# falsifier that can only ever answer "could not ask". This file is an existing per-file symlink, so
# `--falsify-red` reaches the live layer on the ordinary fast-forward; no new link is needed.
#
# Both arguments are single-quoted for the SECOND parse. A suite path with a space would otherwise
# re-split at probe time and the probe would answer confidently about the wrong subject.
fals_sq()  { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
fals_red() { # <suite> <sha> → the probe string, or rc 1 when either half is missing
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  # shellcheck disable=SC2016  # $HOME must NOT expand here — see the header comment below.
  # The output is a STORED STRING that cc-premise later runs through `/bin/sh -c`, so the expansion
  # belongs at probe time. Expanding it now would bake this run's home into a durable ledger record.
  printf '"$HOME/.claude/scripts/postland-verify.sh" --falsify-red %s %s' \
    "$(fals_sq "$1")" "$(fals_sq "$2")"
}

# ── --falsify-red <suite> <sha> — THE STORED FALSIFIER this script hands to its own items ────────
# Every backlog item this file mints about a commit that broke the corpus (AUTO-REVERT INERT,
# AUTO-REVERT <outcome>, HUNG) now carries `cc-backlog add --falsifier "<this verb>"`, and cc-premise
# re-runs it at CLAIM time. Its contract (bin/cc-premise run_falsifier) is asymmetric and this verb
# is written to it: exit 0 means the premise is GONE and the claim is refused; every non-zero means
# "still live", advisory only. So exit 0 is the only load-bearing answer here.
#
# EXACTLY ONE SUCCESS STATE: a tree CONTAINING the accused commit has since run the FULL corpus
# green, and that green's span actually covered this suite. Every other reachable state — including
# every state where the question could not be asked at all — is non-zero, split into 1 (asked,
# answered no) and 2 (could not ask) for a human reading it by hand. The split is legibility only:
# cc-premise reads both as "still live", which is the safe direction, because an unread premise is
# "I could not tell" and never "finished".
#
# WHY IT READS last-green RATHER THAN RE-RUNNING THE SUITE, which is the obvious probe and the wrong
# one twice over. It cannot fit the bound (cc-premise gives a probe 20s; one suite alone runs ~50min
# in this band), so a probe honest enough to hold it would hold a claim hostage and a probe that fits
# would be a permanent non-verdict wearing a measurement's clothes (memory:
# bound-must-fit-the-band-not-the-bench). And it would re-derive an answer this script has ALREADY
# recorded: last-green advances only on a full-corpus pass.
#
# THE SPAN CLAUSE IS NOT BELT-AND-BRACES. The corpus is tests/*.bats MINUS the host manifest, so a
# green is silent about a host suite by construction and cannot speak about a file that did not exist
# yet. Retracting on ancestry alone would assert a verdict over a suite the run never executed
# (memory: assertion-span-must-equal-its-subject) — so those cases exit 2, not 0.
#
# NOT EMITTED ON `post-land RED:` ITEMS, deliberately. That population already has a DERIVED
# falsifier in cc-premise (run_derived_postland_falsifier) computing this same predicate in Python,
# and cc-premise's composition rule is that a STORED probe outranks a derived one. Storing an equal
# probe there would shadow a tested, documented arm and buy nothing but a second implementation to
# keep in sync. These three item classes have no derived arm at all — that is where a stored probe
# is the difference between a re-run and no question being asked.
verb_falsify_red() { # <suite-path|tests/> <red-sha> → 0 retracted · 1 still live · 2 could not ask
  local path="${1:-}" redsha="${2:-}" lg lgc redc
  [ -n "$path" ] && [ -n "$redsha" ] || return 2
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 2
  lg="$(cat "$LASTGREEN" 2>/dev/null || true)"
  case "$lg" in ''|*[!0-9a-f]*) return 2 ;; esac
  [ "${#lg}" -ge 7 ] || return 2
  # BOTH refs must RESOLVE before either is compared — the positive control that separates "git
  # answered no" from "git was never able to answer". Without it an unreadable object reads as a
  # clean negative and this verb goes quietly inert while still returning a confident number.
  lgc="$(git -C "$REPO" rev-parse --verify --quiet "$lg^{commit}" 2>/dev/null || true)"
  redc="$(git -C "$REPO" rev-parse --verify --quiet "$redsha^{commit}" 2>/dev/null || true)"
  [ -n "$lgc" ] && [ -n "$redc" ] || return 2
  # The ordinary LIVE case: trunk has not gone green past the accused commit yet.
  git -C "$REPO" merge-base --is-ancestor "$redc" "$lgc" >/dev/null 2>&1 || return 1
  # The unattributed subject needs no span clause: `tests/` IS the corpus, so a full-corpus green
  # covers it by definition. Every FILE subject has to prove the green actually ran it.
  case "$path" in
    tests|tests/) return 0 ;;
  esac
  # A host suite is EXCLUDED from the corpus, so the green never executed it and cannot speak about
  # it. An ABSENT manifest is the EMPTY set by the manifest's own frozen contract, not a failure —
  # but an unreadable one at that ref is "could not ask", and the two must not collapse.
  if git -C "$REPO" cat-file -e "$lgc:$MANIFEST_REL" >/dev/null 2>&1; then
    local mf
    mf="$(git -C "$REPO" show "$lgc:$MANIFEST_REL" 2>/dev/null)" || return 2
    printf '%s\n' "$mf" | sed 's/#.*//' | tr -d '[:blank:]' | grep -qxF "$path" && return 2
  fi
  # The suite must have EXISTED at the green — a green cannot vouch for a file it never saw.
  git -C "$REPO" cat-file -e "$lgc:$path" >/dev/null 2>&1 || return 2
  return 0
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
# `inert` is the count that matters: culprits the veto will never attempt again (its revert landed, or
# the retry budget is spent). A bare total hid exactly that — 8 of this host's own markers, 5 of them
# never landed, and nothing anywhere said the actuator had gone quiet on them.
#
# A FUNCTION, not a `$( … )` body, because this loop needs `case` for its numeric guards and a `case`
# inside a command substitution is the bash 3.2 trap this suite's own `norm()` helper carries a memory
# note about. It is not even the silent no-op there: /bin/bash 3.2 raises `syntax error near
# unexpected token 'newline'` and then trips `set -u` on the half-parsed body — which is how this got
# caught, by running `status` against the LIVE marker store instead of only through the fixture.
reverts_inert_n() {
  local f e a n=0
  for f in "$REVERTS"/*; do
    [ -f "$f" ] || continue
    e="$(mk_field "$f" land_exit)"; a="$(mk_field "$f" attempts)"
    case "$e" in ''|*[!0-9]*) e=0 ;; esac
    case "$a" in ''|*[!0-9]*) a=1 ;; esac
    { [ "$e" -eq 0 ] || [ "$a" -ge "$REVERT_RETRY_MAX" ]; } && n=$((n+1))
  done
  printf '%s' "$n"
}
verb_status() {
  # `worktree` is the cell this invocation WOULD mint — cells are per-run and torn down, so between
  # runs there is deliberately nothing there to look at (§4.2.1). `reverts` is the never-twice ledger.
  printf 'postland-verify status\n  state      : %s\n  worktree   : %s (minted per run)\n  last-green : %s\n' \
    "$STATE" "$WORKTREE" "$(render_lastgreen)"
  printf '  reverts    : %s total · %s INERT (landed-or-budget-spent)\n' \
    "$(find "$REVERTS" -type f 2>/dev/null | wc -l | tr -d ' ')" "$(reverts_inert_n)"
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
#
# ── HERMETICITY vs A LIVE DAEMON (backlog 9a34c9b9865a) ──────────────────────────────────────────
# The item filed against this block asked for two things. The first was already true, and the second
# is refuted by measurement; both are recorded here because an item whose premise is not written
# down where the code lives gets re-minted from the same observation.
#
# "The green-path assertions read a shared $STATE the daemon mutates." NO. run_fixture has passed
# CC_POSTLAND_DIR="$d/state" since this file was born (95438bbb, 2026-07-25) and every assertion
# reads a LITERAL "$d/…" path, never $STATE/$STAMPS/$LASTGREEN. That was already the shape at the
# revision live on the day of the incident (6147ab21, 2026-07-26), so the mechanism the item names
# could not have produced the failure it was filed for, and its prescribed fix is a no-op. What
# replaced it is the sandbox-completeness assertion below: the claim "the fixture cannot reach real
# state" stops being a thing a reader verifies by inspection and becomes a thing that goes RED.
#
# "Activation should refuse-or-pause while the daemon holds the lock." REJECTED — the remedy is
# worse than the flake. Measured 2026-08-09 from this host's own stamps: corpus runs take 2231-4454s
# against the plist's StartInterval of 300, so the real lock is held ≳91% of the time. `refuse` is
# therefore an activation gate that fails ~9 times in 10 for a reason unrelated to the tree, and
# `pause` is a wait of up to ~74 minutes inside an interactive activation script. A gate that cannot
# pass is the same defect as one that cannot fail. What the incident actually needed was
# ATTRIBUTION — the operator could not tell a real red from a concurrent one — so that is what the
# failure summary now prints, as evidence, never as a gate.
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-52s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-52s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d rc tree green_sha red_sha pl pl_f pl_missing
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
    #
    # CC_GIT_IDENTITY_TEST=1 + CC_GIT_IDENTITY_EMAIL declare the FIXTURE's identity to be the
    # sanctioned one for the duration (the same sealed seam tests/git-identity-guard.bats uses;
    # production never sets it). Without it identity_snap_ok measures the fixture's
    # pv@selftest.local against the OPERATOR's real address, calls the fixture's own baseline
    # unsanctioned, and takes the DROP branch — so the leak case below could only ever exercise
    # "drop", never "restore", and the restore assertion went red for a reason that had nothing to
    # do with the tree. Both branches are now reachable and both are asserted.
    env POSTLAND_VERIFY="${POSTLAND_VERIFY:-on}" POSTLAND_AUTOREVERT=off \
        CC_POSTLAND_DIR="$d/state" CC_POSTLAND_REPO="$d/src" \
        CC_POSTLAND_WT_ROOT="$d/cells" CC_PAGES_DIR="$d/pages" CC_IDL="$d/idl.jsonl" \
        CC_BACKLOG_BIN=/usr/bin/true CC_POSTLAND_NOTIFY=/usr/bin/true CC_POSTLAND_NOTIFY_BIN=/usr/bin/true \
        CC_GIT_IDENTITY_TEST=1 CC_GIT_IDENTITY_EMAIL=pv@selftest.local \
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
  # C29 WINDOW 1 — a LADDER conviction is a candidate, so this sweep stamps `cut` and proves nothing.
  # CONVICT_SPREAD is zeroed for the fixture the same way every other bound is shrunk here: the
  # two-SWEEP requirement is what this exercises, and it is left fully live.
  CC_POSTLAND_CONVICT_SPREAD_S=0 run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  grep -q '"verdict":"cut"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "C29: one window convicts nothing — the first sweep stamps cut" \
    || badp "C29: a SINGLE window produced a verdict (a same-window 2/3 is one experiment)"
  CC_POSTLAND_CONVICT_SPREAD_S=0 run_fixture --run-if-needed >/dev/null 2>&1; rc=$?   # ── window 2
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
  # The corpus must be LAUNCHED demoted. Worded as "launched", not "runs in", because until
  # 2026-08-11 this check read `okp "the corpus runs in the background band"` — and that was FALSE
  # of the running process: $BATS_BIN resolves to cc-bats, which re-clamps to `utility` (PRI 20).
  # A control asserting a claim about a RUNNING band by grepping a PREFIX in its own source can
  # only ever confirm the prefix. It passed for weeks over a corpus running in a different band
  # than the one it named, and that false confirmation is what kept the real lever hidden.
  grep -qE 'nice -n 19' "$SELF" \
    && okp "qos: the corpus is LAUNCHED demoted (prefix present)" || badp "qos: no demotion prefix"

  # THE BAND THE CORPUS ACTUALLY GETS is decided by the launchd plist, not by the prefix above:
  # `ProcessType Background` applies the darwinbg task role, a one-way floor that pins every
  # descendant at PRI 4 and that cc-bats' `-c utility` provably cannot lift. Re-adding that key
  # would silently restore a 3.19x wall-clock tax on the scheduled lane with nothing else changing,
  # so assert its ABSENCE from the SSOT here — this file is the only place that would notice.
  _pv_plist="$(dirname "$SELF")/../launchd/com.claude.postland-verify.plist"
  if [ -f "$_pv_plist" ]; then
    grep -qE '<string>Background</string>' "$_pv_plist" \
      && badp "qos: plist re-declares ProcessType Background (pins the corpus at PRI 4)" \
      || okp "qos: plist declares no darwinbg ProcessType (cc-bats' utility clamp can take)"
  else
    okp "qos: plist SSOT not reachable from here (skipped, not asserted)"
  fi
  unset _pv_plist

  # ── C29 cross-window corroboration — structural, and specifically that it did NOT become a wait ──
  # The failure mode this guards is not "the feature is missing", it is "somebody implemented the
  # second window by SLEEPING until the box went quiet" — which is gate_admit again under a new name,
  # and the name-anchored grep above would not catch it. So assert the mechanism directly: the gate
  # is a TIME SEPARATION between two sweeps, and no branch anywhere may test the load it records.
  grep -qE '^corroborate_convictions\(\)' "$SELF" \
    && okp "C29: ladder convictions are corroborated across sweeps" \
    || badp "C29: corroborate_convictions is gone (a one-window 2/3 can red again)"
  # ANCHORED TO STATEMENT POSITION, for the same reason the gate_admit pattern above is anchored: an
  # unanchored '.*load1' matches this very comment and reports the guard as the violation. A load
  # WAIT has to be a conditional or a loop at statement position, so that is what is forbidden; the
  # `load=` capture in conviction_observe is an assignment and is deliberately still legal. Both
  # spellings are covered — the raw sysctl key and the load1() accessor that wraps it — because
  # closing only one leaves the other as an open door.
  # Positive control for this pattern lives with C29 in tests/postland-verify.bats.
  grep -qE '^[[:space:]]*(if|while|until)[[:space:]].*(loadavg|load1)' "$SELF" \
    && badp "C29: a branch tests the recorded load (a quiet-box wait is gate_admit again, R1)" \
    || okp "C29: load is recorded as evidence, never branched on or waited for"

  # ── PRE-PLAN GRACE — the bound for bats' no-TAP COUNTING pass ────────────────────────────────────
  # Asserted on the FUNCTION, not only through a bats fixture. This is the number that decides
  # whether a healthy corpus is falsely cut, and a fixture that has to wedge a real bats to reach it
  # costs ~90s and can exercise exactly ONE corpus size — while the property that matters is that the
  # window SCALES. A constant is how this class recurs: the corpus went 141 -> 403 suites in two
  # weeks (memory: bound-must-fit-the-band-not-the-bench, third tell — "headroom silently erodes").
  # Each case runs in its own command substitution, so the assignments cannot leak into the next.
  [ "$( unset POSTLAND_PRE_PLAN_GRACE_S; PRE_PLAN_PER_SUITE_S=15 PRE_PLAN_FLOOR_S=900 SUITE_TO=10800; pre_plan_grace 400 )" = 6000 ] \
    && okp "pre-plan: the grace is DERIVED from corpus size (400 suites x 15s = 6000s)" \
    || badp "pre-plan: the grace does not scale with the corpus (a constant rots as tests/ grows)"
  [ "$( unset POSTLAND_PRE_PLAN_GRACE_S; PRE_PLAN_PER_SUITE_S=15 PRE_PLAN_FLOOR_S=900 SUITE_TO=10800; pre_plan_grace 1 )" = 900 ] \
    && okp "pre-plan: a tiny corpus still gets the floor, never 15s" \
    || badp "pre-plan: the floor does not bind (the tests/ fallback corpus would get a 15s window)"
  [ "$( unset POSTLAND_PRE_PLAN_GRACE_S; PRE_PLAN_PER_SUITE_S=15 PRE_PLAN_FLOOR_S=900 SUITE_TO=10800; pre_plan_grace 100000 )" = 10800 ] \
    && okp "pre-plan: the grace is clamped to SUITE_TO (the wall stays the outer bound)" \
    || badp "pre-plan: the grace can exceed the wall backstop it is nested inside"
  [ "$( POSTLAND_PRE_PLAN_GRACE_S=42; pre_plan_grace 400 )" = 42 ] \
    && okp "pre-plan: an absolute POSTLAND_PRE_PLAN_GRACE_S overrides the derivation" \
    || badp "pre-plan: the absolute override is ignored (no kill switch, no test seam)"
  # DEGRADATION, both directions. These are operator-settable env values read into a `[ x -ge y ]`
  # inside the watcher loop: garbage must fall back to the default, and a 0/garbage SUITE_TO must not
  # silently CLAMP the grace to zero — that would re-open the exact false cut this exists to close.
  [ "$( unset POSTLAND_PRE_PLAN_GRACE_S; PRE_PLAN_PER_SUITE_S=abc PRE_PLAN_FLOOR_S=900 SUITE_TO=10800; pre_plan_grace 400 )" = 6000 ] \
    && okp "pre-plan: a non-numeric per-suite value degrades to the default" \
    || badp "pre-plan: a non-numeric per-suite value corrupts the grace"
  [ "$( unset POSTLAND_PRE_PLAN_GRACE_S; PRE_PLAN_PER_SUITE_S=15 PRE_PLAN_FLOOR_S=900 SUITE_TO=0; pre_plan_grace 400 )" = 6000 ] \
    && okp "pre-plan: a 0 wall backstop does not clamp the grace to nothing" \
    || badp "pre-plan: SUITE_TO=0 zeroes the grace (every counting pass would be cut instantly)"
  # THE TWO STATES int_or_zero COLLAPSES. tap_plan returns 0 for "no plan line yet" AND for a real
  # `1..0`; the watcher must not read a finished empty corpus as "still counting" (nor an empty TAP
  # as planned, which would put a genuinely wedged gather back on the stall clock it is blind to).
  printf '' > "$d/preplan-empty.tap"; printf '1..0\n' > "$d/preplan-zero.tap"
  tap_planned "$d/preplan-empty.tap" \
    && badp "pre-plan: an EMPTY tap reads as planned (the counting pass would get no grace at all)" \
    || okp "pre-plan: an empty TAP is not planned"
  tap_planned "$d/preplan-zero.tap" \
    && okp "pre-plan: an emitted 1..0 IS planned (a finished empty corpus leaves the grace)" \
    || badp "pre-plan: a real 1..0 reads as 'still counting' (a finished run held in the grace)"
  # The cut REASON is the loop's own record. Re-deriving it here would be a second copy of the
  # predicate that decided, and the two disagree at the boundary — a plan line landing on the same
  # poll that exhausts the grace resets `still` while `preplan` stays at the limit
  # (memory: make-the-actuator-the-arbiter).
  # shellcheck disable=SC2016  # the single quotes are the POINT: this is a source PATTERN to find,
  # not a string to expand — `$still`/`$stall` must reach grep as literal bytes.
  grep -qE '\[ "\$still" -ge "\$stall" \] && rc=124' "$SELF" \
    && badp "pre-plan: the rc unify re-derives the cut predicate instead of reading why the loop broke" \
    || okp "pre-plan: rc 124 is keyed on the loop's own cut reason, never re-derived"

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
  # RESTORE, specifically — not merely "cleaned". The run-start value here is SANCTIONED (run_fixture
  # declares it through the sealed seam), which is the only condition under which restoring is a
  # repair at all; the poisoned-baseline case below is the other half.
  [ "$(git -C "$d/src" config --local --get user.email 2>/dev/null)" = "pv@selftest.local" ] \
    && okp "identity: a SANCTIONED run-start value is restored after a leak" \
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

  # ── AN INHERITED unsanctioned identity is DROPPED, and the run is NOT convicted for it ───────────
  # The 2026-08-08 pair of fixes, asserted on the path that actually executes them. "Restore the
  # run-start value" was the RECURRENCE ENGINE: a sweep that starts while .git/config already holds
  # the poison snapshots it and faithfully writes it back, which is why the 08-05 fix "landed" and
  # the operator still saw the wrong author on GitHub three days later. Two properties have to hold
  # together, and each is the other's control:
  #   DROPPED  — else the poison is pinned forever by the guard built to remove it.
  #   NOT RED  — this run INHERITED the fault; convicting the commit that happened to be under test
  #              would launder someone else's red into this land's verdict, and a red here reaches
  #              red_actions, which can auto-revert an innocent commit.
  # Only this ONE drop branch is pinned: identity_resident_guard runs ahead of the abstain gate
  # (before run_target takes IDENTITY_SNAP), so on the --run-if-needed path a snapshot can only ever
  # be absent-or-sanctioned by the time identity_assert compares it. Asserting the other drop branch
  # from here would pin a path this verb cannot reach.
  git -C "$d/src" config user.email poison@leak.local
  printf '#!/bin/bash\necho inherited\n' > "$d/src/inherited.sh"
  fixture_land "a run that INHERITS an unsanctioned identity it did not write"
  run_fixture --run-if-needed >/dev/null 2>&1
  tree="$(git -C "$d/src" rev-parse 'origin/main^{tree}')"
  [ -z "$(git -C "$d/src" config --local --get-regexp '^user\.' 2>/dev/null)" ] \
    && okp "identity: an INHERITED unsanctioned identity is dropped, not re-applied" \
    || badp "identity: the poisoned baseline SURVIVED the run ($(git -C "$d/src" config --local --get user.email 2>/dev/null)) — restore-to-snapshot is pinning it"
  grep -q '"verdict":"green"' "$d/state/stamps/$tree.json" 2>/dev/null \
    && okp "identity: the run that inherited it is NOT convicted for it" \
    || badp "identity: a run was convicted for an identity it inherited (that red can auto-revert)"
  git -C "$d/src" config user.email pv@selftest.local      # back to the sanctioned baseline
  git -C "$d/src" config user.name pv-selftest

  # ── the prelint wiring, and the argument contract that makes it safe ─────────────────────────────
  grep -qE 'PRELINTS=\(.*git-identity-lint\.sh' "$SELF" \
    && okp "prelint: git-identity-lint is in the blocking pre-corpus slot" \
    || badp "prelint: git-identity-lint NOT wired into PRELINTS"
  # The wiring is only safe because the slot stopped passing a positional. git-identity-lint scans a
  # repo ROOT, not a corpus dir; handed `tests` it exits 2, and prelint_check turns a 2 into
  # PRELINT_UNPROVEN — so every run would CUT and no tree could be stamped green again. Assert the
  # absence of that argument, because its presence is silent and fleet-fatal.
  # shellcheck disable=SC2016  # a literal search pattern: the $s must NOT expand here
  grep -qE '^[[:space:]]*prelint_invoke "\$s" "\$out"$' "$SELF" \
    && okp "prelint: lints are invoked with NO positional — each resolves its own scan root" \
    || badp "prelint: a positional is still passed — a root-scanning lint would exit 2 and CUT every run"

  # ── the INSTRUMENT CHECK (backlog 76644e76aaae) ──────────────────────────────────────────────────
  # The detector is a REGEX over other people's files, and a regex that silently stops matching does
  # not fail — it reports "none of them support --selftest" and the instrument check evaporates for
  # every lint at once, restoring exactly the gap this closed. So it is positive-controlled against
  # the real files, and negative-controlled against a prose mention, which is the false positive
  # nightly-regression's S4 audit actually caught. Without the negative half, a regex degenerate
  # enough to match anything would pass the positive half perfectly.
  pl_missing=""
  for pl in "${PRELINTS[@]}"; do
    [ -n "$pl" ] || continue
    # $SELF-relative, NOT $WORKTREE-relative: during a selftest the check cell has not been minted.
    pl_f="$(dirname "$SELF")/$(basename "$pl")"
    [ -f "$pl_f" ] || continue
    prelint_has_selftest "$pl_f" || pl_missing="$pl_missing $(basename "$pl")"
  done
  [ -z "$pl_missing" ] \
    && okp "prelint: the detector fires on every default PRELINT (instrument check is reachable)" \
    || badp "prelint: prelint_has_selftest does NOT detect --selftest in:$pl_missing — the instrument check would silently skip them"
  printf '#!/bin/bash\n# usage: x.sh --selftest\n./other.sh --selftest >/dev/null && ok\n' > "$d/prose-only.sh"
  prelint_has_selftest "$d/prose-only.sh" \
    && badp "prelint: the detector matches a PROSE --selftest — it would feed a flag the lint rejects and read the rejection as a verdict" \
    || okp "prelint: the detector ignores a prose-only --selftest (the S4 false positive)"
  # A failed selftest must reach PRELINT_UNPROVEN and `continue` — never FAILING. The end-to-end
  # RED-proof of both halves is tests/postland-verify.bats (C22); this asserts the wiring is present
  # at all, so a refactor that drops the mapping cannot pass this file's own selftest.
  grep -qE 'PRELINT_UNPROVEN=1' "$SELF" && grep -q 'INSTRUMENT-BROKEN' "$SELF" \
    && okp "prelint: a failed --selftest is wired to the non-verdict column, not to FAILING" \
    || badp "prelint: the INSTRUMENT-BROKEN mapping is gone — a broken lint could auto-revert an innocent commit"
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

  # ── SANDBOX COMPLETENESS — the fixture may not reach anything the daemon owns ────────────────────
  # The item this closes (9a34c9b9865a) asserted the fixture was reading real state. It was not — but
  # nothing PROVED it wasn't, so the claim had to be re-established by hand every time somebody asked.
  # This is that proof, and it is RED-provable in the direction that actually rots: a NEW knob is
  # added with a $HOME-rooted default, run_fixture is not updated, and from then on one more of the
  # fixture's paths silently resolves into the operator's live tree. The frontier is deliberately
  # "$HOME-rooted default" — knobs defaulting to $STATE or $REPO are already inside the sandbox
  # because those two are overridden, and demanding an override for all ~40 tuning knobs would red on
  # bounds that are inherited on purpose.
  local rf knob knobs escapes=""
  rf="$(awk '/^  run_fixture\(\) \{/,/^  \}/' "$SELF")"
  # The prefix is stripped EXACTLY, never with a greedy `.*{`: $LANDLOG's default is nested
  # (`${CC_POSTLAND_LANDLOG:-${LAND_LOG:-$HOME/…}}`) and a greedy strip walks to the LAST brace,
  # yielding the INNER name — which then "passes" only because `CC_POSTLAND_LANDLOG=` happens to
  # contain `LAND_LOG=` as a substring, while the outer knob that actually governs goes unchecked.
  # shellcheck disable=SC2016  # a literal search pattern: the $s must NOT expand here
  knobs="$(grep -oE '="\$\{(CC_|POSTLAND_)[A-Z0-9_]+:-[^"]*\$HOME' "$SELF" \
             | sed -e 's/^="\$[{]//' -e 's/:-.*//' | sort -u)"
  # Fed by here-doc, not a pipeline: a `while read` on the right of a `|` runs in a SUBSHELL and
  # every $escapes append is discarded when it exits, so the check would report clean whatever it
  # found. Same idiom identity_assert uses to walk its snapshot, for the same reason.
  while IFS= read -r knob; do
    [ -n "$knob" ] || continue
    printf '%s' "$rf" | grep -q "$knob=" || escapes="$escapes $knob"
  done <<EOF
$knobs
EOF
  # An extraction that yields nothing reports EVERY knob as escaping rather than passing vacuously —
  # if run_fixture is ever reshaped out from under that awk range, this must fail loud, not silent.
  [ -z "$escapes" ] \
    && okp "sandbox: every \$HOME-rooted path knob is overridden by run_fixture" \
    || badp "sandbox: run_fixture does NOT override:$escapes — the fixture reaches the live tree"

  # ── ATTRIBUTION, NEVER A GATE (see the hermeticity note above) ───────────────────────────────────
  # Read-only, failure-only, and it changes no verdict: the one thing the 2026-07-26 operator could
  # not do was tell "this tree is red" from "a full corpus run was chewing the box underneath me".
  # $LOCK here is the PARENT's, i.e. the real one — the fixture's own lock lives under $d.
  if [ "$FAIL" -gt 0 ] && [ -d "$LOCK" ]; then
    printf '  note: the live verifier held %s (pid %s) while this ran — concurrency does not change\n' \
      "$LOCK" "$(cat "$LOCK/pid" 2>/dev/null || echo '?')"
    printf '        a verdict here (the fixture is sandboxed, asserted above), but it does change\n'
    printf '        how long it took, so weigh any TIMING-shaped failure against it.\n'
  fi

  echo "postland-verify selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
}

usage() {
  echo "usage: postland-verify.sh [--run-if-needed | --run <sha> | bisect <file> <good> <bad> | is-green <sha> | status | --falsify-red <suite> <sha> | --selftest]"
  echo "  --falsify-red: the STORED FALSIFIER on this script's own backlog items — 0 = a full-corpus green contains that commit AND covered that suite (premise gone) · 1 = still live · 2 = could not ask"
  echo "  kill switches: POSTLAND_VERIFY=off (inert) · POSTLAND_AUTOREVERT=off (verify+page, never push)"
  echo "  revert retry : POSTLAND_REVERT_RETRY_MAX=$REVERT_RETRY_MAX · POSTLAND_REVERT_RETRY_DECAY_S=$REVERT_RETRY_DECAY_S (a revert that never landed re-arms; one that landed never does)"
  echo "  state: $STATE   ·   host partition: $MANIFEST_REL   ·   header comment = full design notes"
}

main() {
  # DISPATCHED ABOVE THE KILL SWITCH, AND ABOVE ensure_dirs/the cleanup trap — both halves are
  # load-bearing. This verb is a pure read that mints nothing, so it needs neither. More sharply:
  # the kill switch below exits 0, and under the falsifier contract exit 0 MEANS "the premise is
  # gone, refuse the claim". Leaving `--falsify-red` beneath it would make `POSTLAND_VERIFY=off`
  # silently retract every item this script ever filed — a kill switch that reads as a verdict, and
  # the exact two-meanings-for-exit-0 defect this verb was written to avoid.
  if [ "${1:-}" = "--falsify-red" ]; then
    shift; verb_falsify_red "${1:-}" "${2:-}"; exit $?
  fi
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
    # --falsify-red is dispatched ABOVE, before the kill switch; it can never reach this case.
    status)     verb_status ;;
    --selftest) selftest ;;
    -h|--help)  usage ;;
    *) echo "postland-verify: unknown verb '$1'" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
exit $?
