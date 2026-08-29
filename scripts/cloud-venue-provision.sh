#!/usr/bin/env bash
# cloud-venue-provision.sh — make a cloud VM's OWN land path able to render a verdict.
#
#   scripts/cloud-venue-provision.sh            check, install what is missing, re-verify, verdict
#   scripts/cloud-venue-provision.sh --check    read-only: the census and the verdict, install nothing
#   scripts/cloud-venue-provision.sh --selftest prove the verdict function discriminates (no box needed)
#
# WHY THIS EXISTS. docs/plans/BACKLOG_DRAIN_24_7.md's 2026-08-29 addendum ends "Not fixable as code
# from here. A SessionStart hook would mean editing .claude/settings.json, which the dispatch rails
# forbid in place. It is a venue-provisioning step and is recorded as one." The first sentence is
# true of a HOOK and not of a SCRIPT: a dispatched session can run one command before it works, and
# that costs no settings edit, no hook registration and no launchd change. This file is that command.
#
# WHAT IT IS NOT. It does not weaken a gate, widen an allowlist, edit settings.json, or touch a ref.
# It installs two tools the land gate needs in order to SPEAK, and then asserts they made the gate
# speak. Everything else about the land is unchanged.
#
# ── THE CORRECTION THIS FILE CARRIES, AND IT IS THE REASON THE TWO TOOLS ARE NOT INTERCHANGEABLE ──
# The addendum calls shellcheck and bats "Both locks … provisionable in the venue" and prescribes one
# `apt-get install -y shellcheck bats`. The prescription is right and the framing is wrong: MEASURED
# on a cloud VM 2026-08-29 (Ubuntu, shellcheck 0.9.0, bats 1.10.0, HEAD == origin/main), only ONE of
# them is a lock, and the other fails in the opposite direction — silently.
#
#   [the checker] ABSENT → scripts/bats-shellcheck-lint.sh exits 2 (--selftest AND bare) →
#                       ship-land.sh:3444 routes 2 to bats_sc_nonverdict → GATE_KILLED → exit 9.
#                       A HARD LOCK. Measured: `--precheck --working` rc 9, stderr "the usual cause
#                       is that shellcheck is not installed on this host".
#                       (Spelled "[the checker]" on purpose: a comment line BEGINNING with the
#                       checker's own name parses as a directive, SC1072/SC1073, and aborts the lint
#                       for this whole file — ship-land.sh:2552 names the same trap, and this file
#                       tripped it on its first run.)
#   bats ABSENT       → NOT a lock at all. gate_bats runs a bare `bats "$@"` (ship-land.sh:1749),
#                       which exits 127 with ZERO `not ok`; run_scoped_suite's discriminator is the
#                       TAP BODY and never the exit code, so 127 reads as a CUT, the exoneration
#                       re-run is a second cut, and it returns 2. run_smoke maps that to cut=1 →
#                       SMOKE_STATE="partial" → `return 0`, and the land PROCEEDS.
#
# The polarity is not a bug in ship-land.sh, and this file does not change it. "A non-verdict never
# blocks a land; the post-land verifier decides" (ship-land.sh:2136) is a sound trade ON THE BOX THAT
# HAS A POST-LAND VERIFIER. A cloud VM does not: the verifier is a launchd job on the operator's Mac,
# and the same plan records it INERT for days (backlog 01ab05685857). So on THIS venue "partial"
# means no process anywhere will ever execute the diff — the silent skip that fe6540a6 went blocking
# to eliminate for shellcheck, still live in the smoke arm and invisible because it exits 0.
#
# Hence the two tools have different jobs and both are required:
#   the checker lets the land HAPPEN.       bats lets the land MEAN something.
# A venue that installs only shellcheck lands green-looking commits that nothing ever ran.
#
# ── AND A THIRD LOCK THE PRESCRIPTION ITSELF WALKS INTO: PRESENCE IS NOT A VERSION ────────────────
# `apt-get install -y shellcheck` gives **0.9.0** from the Ubuntu archive. `run_gate`'s statics arm
# runs a BARE `shellcheck "${sc_todo[@]}"` (ship-land.sh:2586) over every CHANGED shell file IN FULL
# and reds on ANY non-zero. Measured here on `origin/main`'s own UNMODIFIED `scripts/ship-land.sh`:
#
#     v0.9.0  · LC_ALL unset (this container's default) → rc 2, output CRASHES mid-stream
#                                       ("commitBuffer: invalid argument"), 48 of the findings printed
#     v0.9.0  · LC_ALL=C.UTF-8                          → rc 1, 114 findings (SC2317 noise)
#     v0.11.0 · any locale                             → rc 0, ZERO findings
#
# So the prescribed command installs a checker that REDs unmodified trunk, and it does so twice over:
# 0.9.0's SC2317 fires on shapes 0.11 does not flag, and the repo's `.shellcheckrc` waives exactly
# SC2001 and SC2015 by name (deliberately — "a lowered severity threshold would have waived every
# future info/style finding sight-unseen"). That file's own header says it was verified against
# **0.11**, which is the version this repo is written for. The rc-2 crash is the second, sharper
# half: a Haskell runtime writing this repo's em-dashes and arrows under a non-UTF-8 locale dies,
# and the statics arm cannot tell rc 2 from rc 1 — a NON-VERDICT read as a red, which is the exact
# conflation `bats_sc_nonverdict` exists to prevent one arm over.
#
# ⚠ Indentation does NOT save a comment from the directive parser: the three rows above began
# `#     <tool name> 0.9.0…` and SC1073 fired on them, which is the FOURTH instance of this same trap
# in one diff. Only the first WORD matters, whatever precedes it.
#
# The version floor subsumes the locale: 0.11 is clean at the inherited locale. This file therefore
# probes the checker by RUNNING it on a witness that trunk keeps clean, never by parsing --version
# alone — a version string is a claim about the binary, the witness is a claim about this box.
#
# ── AND A FIFTH LOCK: THIS FILE APPLIED "PRESENCE IS NOT A VERSION" TO ONE OF ITS TWO TOOLS ───────
# MEASURED on this venue 2026-08-29 (Ubuntu, the box this file had just certified READY). The
# paragraph above is the rule; arm 1 below installs `bats` from the distro and the assertion arm at
# the bottom then printed `assert : bats runs — Bats 1.10.0` — a VERSION STRING, which this header
# says twice is not a verdict. It is not one here either:
#
#   runner            loads tests/*.bats   the 3 it cannot load
#   1.10.0 (archive)     553 / 556         bats-shellcheck-lint · git-identity-lint · qos-chokepoint
#   1.13.0 (the pin)     556 / 556         —
#
# bats mangles a test description into a shell function name, and before 1.11 two descriptions that
# mangle alike are a fatal `Error: Duplicate test name(s)` for the WHOLE file. Its preprocessor is
# line-based, so a `@test "x"` inside a HEREDOC — fixture text a suite writes out to drive its own
# subject — counts. Three suites here do exactly that, legitimately.
#
# THE CONSEQUENCE IS THE SAME SILENT UNGATING THE `bats ABSENT` ROW ABOVE DESCRIBES, and it arrives
# with a green tool-presence line above it. A suite the runner cannot LOAD exits non-zero having
# printed no TAP at all, which is zero `not ok` — the cut the row above traces to `partial` and a
# land that PROCEEDS. Driven end to end on the land path, one comments-only commit to
# scripts/git-identity-lint.sh (4 direct suites, one of them unloadable), `--dry-run` so the whole
# gate runs and stops before the push, same commit and same box in both cells:
#
#   runner    smoke                                            verdict about the diff
#   1.10.0    PARTIAL — git-identity-lint.bats cut TWICE        none; "gate GREEN … would push"
#             (exit 1, zero not-ok), GATE-KILLED at the suite
#   1.13.0    green — 4 direct suite(s) in 35s                  all four ran
#
# The control's log contains zero occurrences of `Duplicate test name(s)`, which is what makes the
# PARTIAL attributable to the runner rather than to the budget or to the diff.
#
# ⚠ AND THE PROBE BELOW IS ONLY EVER AS STRONG AS THE RUNNER IT MEASURES, which is a property to know
# rather than to fix. `bats -c` means different things in the two versions, measured on one fixture
# corpus of {a good suite, a suite with a shell syntax error}:
#     1.10.0 → prints `2`, exit 0    — it counts @test LINES and checks name uniqueness; nothing sourced
#     1.13.0 → `not ok bats-gather-tests`, exit 1 — it actually gathers, so the broken file is caught
# The direction is the safe one: an old runner still fails the duplicate-name class, which is the one
# that is silent at the land, so the probe can never report READY on the venue this section is about.
# It just cannot see the loud class until after the upgrade — by which point that class reds the land
# on its own. Do not "fix" this by sourcing the corpus ourselves: the question is what THE RUNNER can
# load, and a second implementation of gather would answer a different question.
#
# So the runner is probed the same way the checker is: by RUNNING it — `bats -c` over this repo's own
# corpus, which gathers every suite and executes none. `--version` would have answered "1.10.0" and
# said nothing. And the cure is ordered so the pin is never load-bearing: upgrade to the version this
# repo pins, then RE-MEASURE. A witness that still fails after the upgrade is not news about the
# venue, and the verdict says so rather than falling through to READY.
set -uo pipefail
# CAPTURED BEFORE THE FORCED PREPEND, AND IT IS LOAD-BEARING. The line below is the launchd-safe
# idiom every sibling here uses, and it puts /usr/bin AHEAD of everything — including /usr/local/bin,
# where an upstream binary is installed. So this process resolves a tool differently from the shell
# that will run the land, and a verdict taken under the forced PATH can certify a checker the LAND
# will never see. The upgrade arm verifies against THIS value, not against ours.
AMBIENT_PATH="${PATH}"
# APPENDED, NOT PREPENDED — and this file is the one place in the repo where that difference is a
# CORRECTNESS bug rather than a style choice. The sibling launchd-safe idiom puts the standard dirs
# FIRST, which is right for a script that must survive an empty PATH and does not care WHICH copy of
# a tool it gets. This script's entire job is to answer "which copy will the LAND get", so a forced
# /usr/bin:… prefix makes it measure the distro binary even after an upstream one is installed ahead
# of it — reporting STALE-CHECKER forever on a venue that is actually fine, and re-fetching on every
# run. Caught by tests/cloud-venue-provision.bats, which went red on the positive control the moment
# the upgrade arm landed. Appending keeps the empty-PATH guarantee and leaves ambient precedence — the
# land's precedence — intact.
export PATH="${PATH}:/usr/bin:/bin:/usr/sbin:/sbin"

# RESOLVED THROUGH $0's SYMLINKS FIRST, then derived — the canonical form, copied from the sibling
# lints rather than re-invented. `~/.claude/{scripts,hooks,bin}/` are per-FILE symlinks into the
# checkout, so a bare `dirname "$0"/..` on the live path yields `~/.claude`, which has no tests/ and
# no scripts/ship-land.sh to use as a witness. This script would then read NOT-APPLICABLE — a clean
# verdict about the wrong tree, on the only path that matters. Caught by self-path-lint, which
# refused the first spelling; no `readlink -f`, which is GNU-only and this repo's box is BSD.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
REPO_ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
SC_LINT="${CC_VENUE_SC_LINT:-$REPO_ROOT/scripts/bats-shellcheck-lint.sh}"

# ── the verdict function, pure, so --selftest can drive every cell with no box at all ─────────────
# $1 = the checker's state: absent | stale | ok   $2 = the runner's state: absent | stale | ok
# $3 = does this repo have tests/*.bats? (1|0) — the .bats ratchet's entry condition is a property of
#      the REPO, not of the diff (ship-land.sh:3421), so a repo with no suites is not locked by a
#      missing shellcheck and must not be reported as if it were.
# $4 = is a post-land verifier reachable on this box? (1|0) — what makes "partial" survivable.
# $5 = the checkout's history horizon: full | shallow (empty or anything else ⇒ UNKNOWN, see below).
# Echoes "<TOKEN>\t<one line>". TOKEN ∈ TRUNCATED-HISTORY | LOCKED | STALE-CHECKER | UNGATED |
# STALE-RUNNER | READY | NOT-APPLICABLE | UNKNOWN.
#
# THE ORDER IS THE ORDER THE LAND MEETS THEM, and that is what makes it right rather than arbitrary:
# TRUNCATED-HISTORY outranks LOCKED outranks STALE-CHECKER outranks {UNGATED | STALE-RUNNER}. A land
# that cannot start cannot be ungated, and a land the statics arm reds never reaches the smoke — so
# naming a softer failure first would send a reader to fix the thing that changes nothing yet. The
# last two are not ranked against each other because they cannot co-occur: they are two values of
# ONE operand, absent and stale, and they are separate tokens for the same reason `absent` and
# `stale` are separate for the checker — the cure differs (install one, replace one) even though the
# damage is identical.
#
# ⚠ $2 WAS A BOOLEAN AND IS NOW A WORD, for the reason the checker's operand became one: `bats is
# present` and `bats can load this repo` are different questions, and a flag can only carry the
# first. An unrecognised word reaches UNKNOWN rather than READY, pinned by its own cell.
#
# ── WHY THE HORIZON OUTRANKS EVEN THE HARD LOCK, THOUGH IT BLOCKS NO LAND ────────────────────────
# Every other cell here is about whether the gate can render a verdict about a diff. This one is
# about whether the diff is the right diff. A dispatched worker's FIRST instruction in this lane is
# to read what its item cites ON TRUNK — `merge-base --is-ancestor <cure-sha> origin/main`,
# `git log <sha>..origin/main -- <path>`, `git cherry origin/main <branch>` — and a cloud checkout
# arrives SHALLOW. Measured in this container 2026-08-29 on `renchris/claude-infrastructure`:
# `.git/shallow` present, `git rev-list --count origin/main` = **50**, and after `--unshallow`,
# **3832**.
#
#   read                                        depth 50        unshallowed
#   merge-base --is-ancestor a42f107a main      rc 1 (FALSE)    rc 0 (TRUE)
#   git cherry census, day 2026-08-22            0% landed       67% landed
#   git cherry census, day 2026-08-19            0% landed       24% landed
#   git cherry census, whole 305-branch corpus   0 landed        45 landed / 371 own commits
#   "own commits" attributed to 2 branches on
#   2026-08-11 (fork point below the horizon)    5119            3
#
# Every one of those wrong answers is wrong in the SAME direction — it reports landed work as never
# landed — and that is byte-for-byte the sentence backlog `f85fce7c26f5` has been re-derived from
# nine times: *"the cloud return/land arm died; landed branches score identically to never-pushed."*
# The horizon is always the last ~50 trunk commits, so it MOVES: every dispatch, whenever fired,
# measures a step a few days back and confirms the item afresh. A self-renewing false positive.
#
# 🚨 AND THE FAILURE IS SILENT IN BOTH DIRECTIONS, WHICH IS WHY THIS IS A REFUSAL AND NOT A NOTE.
# `git merge-base --is-ancestor` answers rc 1 for "no" and rc 1 for "I cannot see that far"; `git
# log <sha>..origin/main -- <path>` prints nothing for "nothing changed since" and nothing for "that
# sha is below my horizon". A worker that reads a landed cure as absent re-derives it, and the diff
# it then writes REVERTS trunk — the exact hazard this repo already filed as `6110fc45141e`. A gate
# that reds is a smaller failure than a green land of a revert, so this is met first.
#
# What it does NOT claim: `landed()` in bin/cc-cloud reads `git ls-tree <trunk> -- <path>`, which is
# a read of the TIP TREE and is unaffected by the horizon; and `fill-paths` runs desk-side on a full
# clone. The corruption measured here is of the WORKER's own reads, not of the desk's verdict
# machinery. Unmeasured, deliberately: whether ship-land's rebase onto trunk survives a fork point
# below the horizon. The cure is the same either way and costs one fetch.
venue_verdict() {
  local sc="$1" bt="$2" suites="$3" verifier="$4" hist="${5:-}"
  # FIRST, AND FAIL-CLOSED ON AN UNRECOGNISED OPERAND for the same reason the checker state is:
  # a caller that forgot the operand must not be handed a clean verdict about a horizon nobody read.
  case "$hist" in
    shallow)
      printf 'TRUNCATED-HISTORY\tThis checkout is SHALLOW, so every read the worker makes about trunk — is the cited cure an ancestor, has this branch landed, what changed since that sha — answers from inside its own horizon and answers WRONG in the direction that reports landed work as never landed. git merge-base --is-ancestor cannot distinguish "no" from "I cannot see that far". Deepen before reading anything.\n'
      return 0 ;;
    # `n-a` = not a work tree at all, so there is no trunk to read and no horizon to be wrong about.
    # It falls through to the tool arms rather than short-circuiting: the rest of the census is still
    # a true statement about the box even where the repo question does not arise.
    full|n-a) : ;;
    *)
      printf 'UNKNOWN\tThe history horizon "%s" is not one this verdict knows (full|shallow|n-a), so there is NO verdict about this venue — not a clean one.\n' "$hist"
      return 0 ;;
  esac
  if [ "$suites" != 1 ]; then
    if [ "$bt" != absent ]; then
      printf 'NOT-APPLICABLE\tThis repo has no tests/*.bats, so the .bats shellcheck ratchet never fires and there is no smoke to run. Nothing to provision.\n'
    else
      printf 'NOT-APPLICABLE\tThis repo has no tests/*.bats: the ratchet never fires. bats is still absent, so any suite added later would land unrun.\n'
    fi
    return 0
  fi
  if [ "$sc" = absent ]; then
    printf 'LOCKED\tThe checker is absent: bats-shellcheck-lint exits 2, ship-land routes that to GATE_KILLED, and EVERY land here exits 9 — docs-only included, because the arm keys on the repo having tests/*.bats, not on the diff.\n'
    return 0
  fi
  if [ "$sc" = stale ]; then
    printf 'STALE-CHECKER\tThe checker is present but does NOT render a clean verdict on a witness file trunk keeps clean, so ship-land'"'"'s statics arm (a bare run over every changed shell file, red on ANY non-zero) will red this land on findings the diff never wrote. Ubuntu ships 0.9.0; this repo is written for 0.11 and its .shellcheckrc waives two codes BY NAME, not by severity.\n'
    return 0
  fi
  if [ "$bt" = absent ]; then
    if [ "$verifier" = 1 ]; then
      printf 'UNGATED\tbats is absent: every selected suite exits 127 with zero TAP not-ok lines, the smoke attests "partial" and the land PROCEEDS unrun. A post-land verifier is reachable here, so it is the remaining net — but nothing executed the diff at land time.\n'
    else
      printf 'UNGATED\tbats is absent: every selected suite exits 127 with zero TAP not-ok lines, the smoke attests "partial" and the land PROCEEDS unrun. There is NO post-land verifier on this box, so no process anywhere will ever execute this diff. This exits 0 and is therefore silent.\n'
    fi
    return 0
  fi
  if [ "$bt" = stale ]; then
    if [ "$verifier" = 1 ]; then
      printf 'STALE-RUNNER\tbats is present but cannot LOAD every suite in this repo, so those suites never render a verdict about anyone'"'"'s code. In the shape measured here — the distro 1.10.0 refusing a file whose @test descriptions mangle alike, which a heredoc fixture can cause — it exits non-zero having printed NO TAP AT ALL: zero not-ok lines, which is a CUT, which the smoke attests as "partial" and the land PROCEEDS over, under a green "bats runs" line. A post-land verifier is reachable here, so it is the remaining net.\n'
    else
      printf 'STALE-RUNNER\tbats is present but cannot LOAD every suite in this repo, so those suites never render a verdict about anyone'"'"'s code. In the shape measured here — the distro 1.10.0 refusing a file whose @test descriptions mangle alike, which a heredoc fixture can cause — it exits non-zero having printed NO TAP AT ALL: zero not-ok lines, which is a CUT, which the smoke attests as "partial" and the land PROCEEDS over, under a green "bats runs" line. There is NO post-land verifier on this box, so nothing anywhere will ever execute those suites. (A load failure that DOES emit "not ok bats-gather-tests" reds the land instead — loud, and correctly blocking. This verdict refuses on both, because neither is a suite that ran.)\n'
    fi
    return 0
  fi
  if [ "$bt" != ok ]; then
    # FAIL CLOSED on an unrecognised RUNNER state, for the same reason the checker's arm below does.
    # This operand became a word in the same edit that added STALE-RUNNER, so the very first thing
    # that can go wrong with it is a caller still passing the old 1/0 — which must not read READY.
    printf 'UNKNOWN\tThe runner state "%s" is not one this verdict knows (absent|stale|ok), so there is NO verdict about this venue — not a clean one.\n' "$bt"
    return 0
  fi
  if [ "$sc" != ok ]; then
    # FAIL CLOSED ON AN OPERAND WE DO NOT RECOGNISE. The checker's state is a WORD, not a flag, so a
    # typo or a future third failure mode would otherwise fall straight through to READY and certify
    # a box nobody measured. Caught by the selftest cell added with this arm, not by review.
    printf 'UNKNOWN\tThe checker state "%s" is not one this verdict knows (absent|stale|ok), so there is NO verdict about this venue — not a clean one.\n' "$sc"
    return 0
  fi
  printf 'READY\tThe checker renders a clean verdict on the witness and the runner LOADS every suite in this repo: the land gate can reach a verdict and the smoke can earn one.\n'
}

# A DOCUMENTED TEST SEAM, AND IT IS ONE-DIRECTIONAL BY CONSTRUCTION: CC_VENUE_ABSENT can only make
# a tool look ABSENT, never present. It exists because this file forces /usr/bin onto PATH two lines
# below (the sibling launchd-safe idiom), which makes PATH-shielding useless as a way to drive the
# absent cells from a suite. A seam that could manufacture PRESENCE would let a test prove READY on
# a box that cannot land — the one direction that must never be reachable — so this one is wired to
# produce only the pessimistic answer, and tests/cloud-venue-provision.bats pins that asymmetry.
have() {
  case " ${CC_VENUE_ABSENT:-} " in *" $1 "*) return 1 ;; esac
  command -v "$1" >/dev/null 2>&1
}
b()    { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }

# The verifier probe is deliberately conservative and one-sided. It answers "is a post-land verifier
# plausibly reachable", never "is one running": launchd is macOS-only and this file's whole point is
# that it runs off-box, so a false 1 here would soften the UNGATED line on exactly the venue that
# must not have it softened. Absence of the platform ⇒ 0, which is the safe direction.
verifier_present() {
  [ "$(uname -s)" = "Darwin" ] && have launchctl && return 0
  return 1
}

repo_has_suites() {
  [ -d "$REPO_ROOT/tests" ] && ls "$REPO_ROOT"/tests/*.bats >/dev/null 2>&1
}

# → full | shallow | n-a | unknown. ASKED OF GIT, never inferred from `.git/shallow` existing: a
# worktree's `.git` is a file, a grafted repo can carry the marker after a deepen, and the plumbing
# already owns the predicate. `--is-shallow-repository` is git ≥ 2.15; on anything older the answer
# is `unknown` and the verdict refuses rather than certifying a horizon it never read.
#
# `n-a` IS A MEASUREMENT, NOT AN ABSTENTION, and the distinction was forced by a control rather than
# foreseen: this file is copied into a bare directory by tests/cloud-venue-provision.bats to drive
# the NOT-APPLICABLE cell, and the first spelling of this probe answered `unknown` there — turning a
# clean abstention about a suite-less tree into "no verdict about this venue". A directory that is
# not a work tree has no trunk to read and therefore no horizon to be wrong about; folding it in with
# "git could not answer" conflates a question that does not arise with one that went unanswered. The
# two-step is deliberate: ask whether there is a repo FIRST, then ask about its depth, so a future
# reader cannot collapse them back.
#
# CC_VENUE_HISTORY overrides it for the suite in BOTH directions — unlike CC_VENUE_ABSENT, which is
# one-directional. That asymmetry is deliberate too: this operand's optimistic value is `full`, and a
# test that can only force `shallow` cannot drive the positive control on a box whose own clone is
# shallow. The seam is named in the census output whenever it is used, so a forced value can never be
# mistaken for a measurement, and the provision path REFUSES to fetch while it is set.
history_state() {
  local ans
  if [ -n "${CC_VENUE_HISTORY:-}" ]; then echo "${CC_VENUE_HISTORY}"; return 0; fi
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo n-a; return 0; }
  ans="$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" || { echo unknown; return 0; }
  case "$ans" in
    true)  echo shallow ;;
    false) echo full ;;
    *)     echo unknown ;;
  esac
}

# THE WITNESS, AND WHY IT IS A RUN AND NOT A VERSION STRING. `--version` is a claim about the binary;
# what the gate cares about is whether a bare run over a long-lived repo script exits 0 on THIS box,
# which folds in the version, the locale, and any .shellcheckrc that is or is not being found. The
# witness is scripts/ship-land.sh itself, deliberately: it is the file the statics arm most often has
# to clear, the gate requires it clean anyway, and trunk keeps it that way — so a non-zero here is
# never news about the witness and always news about the venue. A DIFFERENT witness is a different
# experiment, hence CC_VENUE_WITNESS is named rather than globbed.
# Resolved INSIDE the probe, not once at file scope: a caller (the selftest, a suite) that sets
# CC_VENUE_WITNESS for one call must actually get that witness, and a file-scope capture silently
# ignores it — which is a control that measures a different question than its subject.

# → absent | stale | ok. The `stale` arm pools "wrong version" with "wrong locale" ON PURPOSE: both
# make the same bare run non-zero, the cure for both is the same newer binary (0.11 is clean at the
# inherited locale where 0.9.0 crashes), and a token per cause would be a distinction the reader
# cannot act on differently.
checker_state() {
  local witness="${CC_VENUE_WITNESS:-$REPO_ROOT/scripts/ship-land.sh}"
  have shellcheck || { echo absent; return 0; }
  [ -f "$witness" ] || { echo ok; return 0; }   # no witness ⇒ no evidence ⇒ never invent a failure
  if shellcheck "$witness" >/dev/null 2>&1; then echo ok; else echo stale; fi
}

# → absent | stale | ok. THE RUNNER'S WITNESS IS THIS REPO'S OWN CORPUS, AND IT IS A GATHER, NOT A
# RUN OF THE TESTS. `bats -c` sources and preprocesses every named suite and executes none of them,
# which is exactly the phase that fails: the damage measured here is a LOADER refusal, not a failing
# assertion. So the probe answers the only question the land cares about — can this binary get as far
# as emitting TAP for every suite the smoke might select — in one process, without running anything.
#
# WHY THE WHOLE CORPUS AND NOT ONE FILE, unlike the checker's witness. The checker's failure mode is
# a property of the BINARY and shows up on any sufficiently rich file, so one long-lived script is a
# fair witness. This one is a property of a COLLISION between the binary and particular suites — 3 of
# 556 here — so a single-file witness would be a curated guess about which three, and would go on
# convicting the venue after those files changed. The corpus is the honest witness and costs ~43s in
# one process; CC_VENUE_RUNNER_WITNESS names a different directory for a suite that needs to drive
# the cells cheaply, and is a DIFFERENT EXPERIMENT whenever it is set, exactly like CC_VENUE_WITNESS.
#
# ABSTAINS RATHER THAN CONVICTS when the witness directory holds no suites — same law as the checker
# arm: no evidence is never "bad". The `stale` arm deliberately pools "the runner is too old" with
# "a suite in this tree does not load under ANY runner", because the two are indistinguishable from
# here and the provision path separates them by ACTING: it upgrades to the version this repo pins and
# RE-MEASURES. A witness that still fails after that is not news about the venue, and the second
# census says STALE-RUNNER again rather than falling through to a clean verdict.
runner_state() {
  local dir="${CC_VENUE_RUNNER_WITNESS:-$REPO_ROOT/tests}"
  have bats || { echo absent; return 0; }
  ls "$dir"/*.bats >/dev/null 2>&1 || { echo ok; return 0; }
  # Unquoted glob on purpose — it is the argument LIST bats wants, and a quoted one is a single
  # nonexistent path. The `ls` above has already established that it expands to real files.
  # shellcheck disable=SC2086
  if bats -c $dir/*.bats >/dev/null 2>&1; then echo ok; else echo stale; fi
}

census() {   # prints the four reads, then the verdict line; sets VERDICT_TOKEN
  local sc bt su vf hs line depth
  # Called in the plain `if` form rather than through the b() indirection: a static analyser cannot
  # see a function reached only via "$@", and reports it as dead code (SC2329). Silencing that with
  # a disable directive would trade a true statement about reachability for a comment nobody reruns.
  sc="$(checker_state)"; bt="$(runner_state)"
  if repo_has_suites;   then su=1; else su=0; fi
  if verifier_present;  then vf=1; else vf=0; fi
  echo "host   : $(uname -s) $(uname -m) · repo $REPO_ROOT"
  printf 'locale : LANG=%s LC_ALL=%s LC_CTYPE=%s\n' \
    "${LANG:-<unset>}" "${LC_ALL:-<unset>}" "${LC_CTYPE:-<unset>}"
  # The runner's version is printed BESIDE its witness state and never instead of it. Reading
  # `bats Bats 1.10.0` alone is what this file's fifth-lock section is about: the string was true
  # and the venue could not load three of its own suites.
  printf 'tools  : shellcheck %s (witness %s) · bats %s (corpus %s)\n' \
    "$( [ "$sc" != absent ] && shellcheck --version 2>/dev/null | sed -n 's/^version: /v/p' | head -1 || echo ABSENT )" \
    "$sc" \
    "$( [ "$bt" != absent ] && bats --version 2>/dev/null | head -1 || echo ABSENT )" \
    "$bt$( [ -n "${CC_VENUE_RUNNER_WITNESS:-}" ] && echo ' — witness FORCED by CC_VENUE_RUNNER_WITNESS' )"
  printf 'repo   : tests/*.bats %s · post-land verifier %s\n' \
    "$( [ "$su" = 1 ] && echo present || echo absent )" \
    "$( [ "$vf" = 1 ] && echo reachable || echo 'NOT on this box' )"
  hs="$(history_state)"
  # The DEPTH is printed beside the state, because "shallow" alone does not tell a reader how far
  # back the wrong answers begin — and it is the number that makes the verdict's claim checkable.
  # Counted over the trunk ref the land uses, falling back to HEAD where that ref is not fetched.
  depth="$(git -C "$REPO_ROOT" rev-list --count origin/main 2>/dev/null \
           || git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo '?')"
  printf 'history: %s%s · %s commits reachable on the trunk ref\n' \
    "$hs" "$( [ -n "${CC_VENUE_HISTORY:-}" ] && echo ' (FORCED by CC_VENUE_HISTORY — not a measurement)' )" "$depth"
  line="$(venue_verdict "$sc" "$bt" "$su" "$vf" "$hs")"
  VERDICT_TOKEN="${line%%$'\t'*}"
  printf 'verdict: %s — %s\n' "$VERDICT_TOKEN" "${line#*$'\t'}"
}

# ── --selftest ────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--selftest" ]; then
  fails=0; checks=0
  expect() { checks=$((checks+1)); [ "$2" = "$1" ] || { fails=$((fails+1)); printf 'SELFTEST FAIL: %s (want %s, got %s)\n' "$3" "$1" "$2"; }; }
  # `full` is this HELPER's default so the pre-existing cells still read as statements about the
  # tools; venue_verdict itself has NO default and answers UNKNOWN on a missing horizon, which is
  # what cell 17 pins. The helper's default can only ever make a cell more optimistic, never less.
  tok() { venue_verdict "$1" "$2" "$3" "$4" "${5:-full}" | cut -f1; }
  # 1-3. each failure reaches its OWN token, and they are three different tokens — a verdict that
  #      collapsed "cannot run" into "ran vacuously" is the exact error this file was written to fix.
  expect LOCKED         "$(tok absent ok 1 0)" 'a missing checker did not read LOCKED'
  expect STALE-CHECKER  "$(tok stale  ok 1 0)" 'a checker that reds the witness did not read STALE-CHECKER'
  expect UNGATED        "$(tok ok     absent 1 0)" 'a missing bats did not read UNGATED'
  # 4-5. PRECEDENCE, in the order the land meets them: absent outranks stale outranks ungated. Each
  #      is asserted against the token it must beat, so a reordering cannot pass by luck.
  expect LOCKED         "$(tok absent absent 1 0)" 'absent+no-bats did not give precedence to the hard lock'
  expect STALE-CHECKER  "$(tok stale  absent 1 0)" 'stale+no-bats did not give precedence to the statics arm'
  # 6. the positive control — with everything good the token is none of the failures, so 1-5 mean
  #    something. Without it a verdict stuck on any single failure token passes every cell above.
  expect READY          "$(tok ok ok 1 0)" 'a good venue did not read READY'
  # 7-8. the ratchet keys on the REPO having suites, so a repo without them is not convicted by a
  #      checker problem at all. Without this arm the script would convict every consumer repo.
  expect NOT-APPLICABLE "$(tok absent ok 0 0)" 'a repo with no .bats suites was reported LOCKED'
  expect NOT-APPLICABLE "$(tok stale  absent 0 0)" 'a repo with no .bats suites was reported STALE-CHECKER'
  # 9. …and NOT-APPLICABLE still distinguishes bats present from absent in its TEXT, because the
  #    next suite added to such a repo would land unrun. Token equal, sentence not.
  expect 1 "$( [ "$(venue_verdict ok absent 0 0 full)" != "$(venue_verdict ok ok 0 0 full)" ] && echo 1 || echo 0 )" \
           'NOT-APPLICABLE said the same thing with and without bats'
  # 10-11. the verifier operand moves only the UNGATED sentence, and never the token. It is the whole
  #      reason this venue is different from the operator's box, so it must be visible and must not
  #      be able to turn a failure into a pass.
  expect UNGATED "$(tok ok absent 1 1)" 'a reachable verifier changed the UNGATED token'
  expect 1 "$( [ "$(venue_verdict ok absent 1 1 full)" != "$(venue_verdict ok absent 1 0 full)" ] && echo 1 || echo 0 )" \
           'the verifier operand did not change the UNGATED sentence'
  # 12. READY is insensitive to the verifier — nothing about a green smoke depends on it.
  expect 1 "$( [ "$(venue_verdict ok ok 1 1 full)" = "$(venue_verdict ok ok 1 0 full)" ] && echo 1 || echo 0 )" \
           'READY was made to depend on the verifier'
  # 13. every token is reachable and distinct: a stuck verdict passes 1-12 only if it also passes this.
  expect 5 "$(printf '%s\n' "$(tok absent ok 1 0)" "$(tok stale ok 1 0)" "$(tok ok absent 1 0)" "$(tok ok ok 1 0)" "$(tok ok ok 0 0)" | sort -u | wc -l | tr -d ' ')" \
           'the five tokens are not five distinct strings'
  # 14. an UNRECOGNISED checker state must not silently read as good. The operand is a word now, and
  #     a typo that fell through to READY would certify a box nobody measured.
  expect 1 "$( [ "$(tok wat ok 1 0)" != READY ] && echo 1 || echo 0 )" 'an unknown checker state fell through to READY'
  # 15. the probe is one-sided by construction: off-Darwin it must answer 0, because a false
  #      "verifier reachable" softens the one line that must stay hard on a cloud VM.
  if [ "$(uname -s)" != "Darwin" ]; then
    expect 0 "$(b verifier_present)" 'verifier_present answered 1 on a non-Darwin host'
  else
    checks=$((checks+1))
  fi
  # 16. the witness probe is a RUN, not a version string, and it must abstain rather than convict
  #     when there is no witness to run on — "no evidence" is never "bad".
  expect ok "$(CC_VENUE_WITNESS=/nonexistent/witness checker_state)" 'an absent witness manufactured a failure'
  # ── the history horizon: 17-21 ──────────────────────────────────────────────────────────────────
  # 17. NO DEFAULT. A call site that forgets the operand must not be handed a clean verdict about a
  #     horizon nobody read — the same fail-closed law cell 14 pins for the checker state, and the
  #     one the helper's own `${5:-full}` would otherwise hide.
  expect UNKNOWN "$(venue_verdict ok ok 1 0 | cut -f1)" 'a missing history operand fell through to a verdict'
  expect UNKNOWN "$(tok ok ok 1 0 sorta)" 'an unrecognised history horizon reached a real verdict'
  # …but "there is no repo here" is a MEASUREMENT and must not be confused with "git could not
  # answer". Pinned because a control caught this, not review: the suite copies this file into a
  # bare directory to drive NOT-APPLICABLE, and the first spelling answered UNKNOWN there.
  expect READY          "$(tok ok ok 1 0 n-a)" 'a non-repo horizon was treated as an unanswered one'
  expect NOT-APPLICABLE "$(tok absent ok 0 0 n-a)" 'a non-repo horizon overrode the suite-less abstention'
  # 18. the cell itself, on a venue that is otherwise perfect. Without this the token is unreachable.
  expect TRUNCATED-HISTORY "$(tok ok ok 1 0 shallow)" 'a shallow checkout on a READY box did not read TRUNCATED-HISTORY'
  # 19-20. PRECEDENCE, asserted against each token it must beat, in the order a worker meets them: a
  #     horizon is consulted before the first read, and the first read happens before any land. A
  #     shallow clone that ALSO cannot land must name the horizon, because fixing the lock alone
  #     leaves the worker writing the wrong diff — and a correct-looking land of a revert is worse
  #     than a red gate (backlog 6110fc45141e).
  expect TRUNCATED-HISTORY "$(tok absent absent 1 0 shallow)" 'the hard lock outranked the horizon that decides WHICH diff gets written'
  # …and it outranks the abstention too: the horizon corrupts a worker's reads in a repo with no
  # .bats suites exactly as much as in one with them. NOT-APPLICABLE is a statement about the gate.
  expect TRUNCATED-HISTORY "$(tok ok ok 0 0 shallow)" 'a repo with no suites hid a truncated horizon behind NOT-APPLICABLE'
  # ── the runner's own witness: 21-27 ─────────────────────────────────────────────────────────────
  # 21. the cell itself. A runner that is PRESENT and cannot load the corpus is not READY and is not
  #     UNGATED either — it is its own token, because the cure is different (replace, not install).
  expect STALE-RUNNER "$(tok ok stale 1 0)" 'a runner that cannot load the corpus did not read STALE-RUNNER'
  # 22-23. PRECEDENCE against each token it must beat, in the order the land meets them. A stale
  #     runner is met at the SMOKE, which is after the statics arm and after the gate has started, so
  #     both checker failures outrank it — telling a reader to replace bats first would send them to
  #     fix the thing that changes nothing while the land still exits 9.
  expect LOCKED        "$(tok absent stale 1 0)" 'the hard lock did not outrank a stale runner'
  expect STALE-CHECKER "$(tok stale  stale 1 0)" 'the statics arm did not outrank a stale runner'
  # 24. …and the horizon outranks it too, for the reason cells 19-20 give: which diff gets written is
  #     decided before whether anything runs it.
  expect TRUNCATED-HISTORY "$(tok ok stale 1 0 shallow)" 'a stale runner hid a truncated horizon'
  # 25. the verifier operand moves the STALE-RUNNER SENTENCE and never its token — the same asymmetry
  #     cells 10-11 pin for UNGATED, and for the same reason: this venue has no verifier, and that is
  #     the clause that makes "partial" terminal here rather than merely deferred.
  expect STALE-RUNNER "$(tok ok stale 1 1)" 'a reachable verifier changed the STALE-RUNNER token'
  expect 1 "$( [ "$(venue_verdict ok stale 1 1 full)" != "$(venue_verdict ok stale 1 0 full)" ] && echo 1 || echo 0 )" \
           'the verifier operand did not change the STALE-RUNNER sentence'
  # 26. FAIL CLOSED on an unrecognised RUNNER state. This operand was a BOOLEAN until this edit, so
  #     the live failure mode is a caller still passing 1 — which must not certify a box nobody read.
  expect UNKNOWN "$(tok ok 1 1 0)" 'the old boolean runner operand fell through to a verdict'
  expect UNKNOWN "$(tok ok wat 1 0)" 'an unknown runner state fell through to READY'
  # 27. seven tokens, seven distinct strings — cell 13 two wider, so a verdict stuck on the new token
  #     cannot pass 17-26 by luck.
  expect 7 "$(printf '%s\n' "$(tok absent ok 1 0 full)" "$(tok stale ok 1 0 full)" "$(tok ok absent 1 0 full)" "$(tok ok stale 1 0 full)" "$(tok ok ok 1 0 full)" "$(tok ok ok 0 0 full)" "$(tok ok ok 1 0 shallow)" | sort -u | wc -l | tr -d ' ')" \
           'the seven tokens are not seven distinct strings'
  if [ "$fails" = 0 ]; then
    echo "cloud-venue-provision --selftest: $checks/$checks — TRUNCATED-HISTORY on a shallow checkout, LOCKED on an absent checker, STALE-CHECKER on one that reds a witness trunk keeps clean, UNGATED on a missing bats, STALE-RUNNER on a bats that cannot LOAD this repo's suites: five distinct failures, ordered as a worker meets them (which diff, then whether the land starts, then whether anything ran) and each asserted against the token it must beat; READY as the positive control; a repo with no .bats suites abstains as NOT-APPLICABLE in both directions yet still says which tool is missing, but never hides a truncated horizon behind that abstention; neither an unrecognised checker state, nor an unrecognised runner state, nor the boolean the runner operand used to be, nor a missing/unrecognised history horizon can reach a clean verdict; the verifier operand moves the UNGATED and STALE-RUNNER sentences and never any token; all seven tokens distinct; the verifier probe answers 0 off-Darwin; and the witness probe abstains when there is no witness."
    exit 0
  fi
  echo "cloud-venue-provision --selftest: FAILED ($fails of $checks)."
  exit 1
fi

# The version this repo is written for. NOT a guess: .shellcheckrc's own header records that its
# `disable=` policy was verified against 0.11, and 0.11.0 measured rc 0 / zero findings on trunk's
# scripts/ship-land.sh where 0.9.0 measured rc 1 with 114.
SC_WANT="${CC_VENUE_SHELLCHECK_VERSION:-0.11.0}"
# The runner version this repo is written for, and the SAME KIND of fact: .github/workflows/
# hermetic.yml installs bats v1.13.0 from source and says why in its own comment — "pinned, not
# `brew install bats-core`: the verdict must be comparable with the on-box verifier's, and every
# stamp it writes records bats 1.13.0". scripts/postland-verify.sh cites the same version for the
# gather step it depends on. So this is the repo's declared runner, not a preference.
#
# ⚠ AND IT IS DELIBERATELY NOT LOAD-BEARING. The number decides what gets FETCHED; it decides
# nothing about the verdict, because the arm re-measures the witness afterwards and a still-stale
# witness stays STALE-RUNNER. If this pin ever drifts from the workflow's, the venue reports a
# failure it cannot cure — which is the safe direction, and visible.
BATS_WANT="${CC_VENUE_BATS_VERSION:-1.13.0}"
UPGRADE=1

MODE=provision
for a in "$@"; do
  case "$a" in
    provision|--provision) MODE=provision ;;
    --check)               MODE=check ;;
    --no-upgrade)          UPGRADE=0 ;;
    -h|--help)             sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "cloud-venue-provision: unknown argument '$a' (expected --check, --no-upgrade, --selftest, or nothing)." >&2; exit 2 ;;
  esac
done

VERDICT_TOKEN=""
echo "cloud-venue-provision — plan docs/plans/BACKLOG_DRAIN_24_7.md, addendum 2026-08-29"
census

[ "$MODE" = check ] && { case "$VERDICT_TOKEN" in READY|NOT-APPLICABLE) exit 0 ;; *) exit 1 ;; esac; }

if [ "$VERDICT_TOKEN" = READY ] || [ "$VERDICT_TOKEN" = NOT-APPLICABLE ]; then
  echo "nothing to provision."
elif [ "$VERDICT_TOKEN" = UNKNOWN ]; then
  echo "⛔ no verdict about this venue — refusing to act on a state this script does not model." >&2
  exit 3
else
  # ── arm 0: the HISTORY HORIZON, first because it is the first thing a worker meets. It is also the
  # cheapest and the only one that fixes a WRONG ANSWER rather than a missing one: the other arms
  # decide whether a diff can land, this one decides whether the diff is right.
  #
  # `--unshallow` is the whole horizon in one call and is what a reader can re-run by hand. It is
  # REFUSED by git on a repo that is not shallow, which is why this is reached only from the shallow
  # verdict and why a failure here is reported rather than fatal: a venue behind a proxy that cannot
  # complete a full fetch is still better off knowing its reads are truncated than being stopped
  # from installing the tools. `--deepen` is not offered as a fallback on purpose — a deeper wrong
  # horizon is still a wrong horizon, and a partial cure here would put the silent failure back with
  # a green line above it.
  if [ "$VERDICT_TOKEN" = TRUNCATED-HISTORY ]; then
    if [ -n "${CC_VENUE_HISTORY:-}" ]; then
      echo "⛔ the horizon is FORCED by CC_VENUE_HISTORY — refusing to fetch against a value that is not a measurement." >&2
      exit 3
    fi
    echo "→ the checkout is shallow — fetching the full history before anything reads trunk"
    if git -C "$REPO_ROOT" fetch --unshallow --quiet 2>/dev/null; then
      printf '  deepened: %s commits now reachable on the trunk ref\n' \
        "$(git -C "$REPO_ROOT" rev-list --count origin/main 2>/dev/null || echo '?')"
    else
      echo "⛔ git fetch --unshallow failed — this venue's reads about trunk are STILL truncated and still silent about it. Every 'is the cited sha on trunk' answer below is unsafe; re-run when the remote is reachable." >&2
      exit 3
    fi
  fi

  # ── arm 1: the packages, from the distro. Deliberately not clever: one package manager, the two
  # packages the addendum names, and a REFUSAL rather than a sudo prompt where it cannot run
  # unattended — a dispatched session has nobody to answer a prompt, so a prompt is a hang.
  # AN ARRAY, not a space-joined string: an unquoted expansion is how a package list becomes a glob,
  # and this one is interpolated into a privileged command. The joined form survives only in the
  # human-facing messages, where it is quoted.
  want=()
  have shellcheck || want+=(shellcheck)
  have bats       || want+=(bats)
  if [ "${#want[@]}" -gt 0 ]; then
    want_s="${want[*]}"
    if ! have apt-get; then
      echo "⛔ apt-get is absent — cannot provision from here. Install ${want_s} by this venue's own means and re-run." >&2
      exit 3
    fi
    if [ "$(id -u)" != 0 ]; then
      echo "⛔ not root and this must not prompt (a dispatched session has nobody to answer). Run: sudo apt-get install -y ${want_s}" >&2
      exit 3
    fi
    echo "→ installing: ${want_s}"
    apt-get install -y "${want[@]}" >/dev/null 2>&1 || { echo "⛔ apt-get install failed for: ${want_s}" >&2; exit 3; }
  fi

  # ── arm 2: the VERSION, which the distro cannot supply. This is the arm the addendum's one-line
  # prescription does not have, and without it a provisioned VM reds unmodified trunk. Ubuntu's
  # newest shellcheck is 0.9.0; this repo is written for 0.11 (its own .shellcheckrc says so) and
  # the statics arm reds on ANY non-zero from a bare run. So when the witness still fails after the
  # package install, fetch the upstream release.
  #
  # THIS IS A NETWORK FETCH OF A BINARY, AND IT IS NAMED AS ONE RATHER THAN BURIED. It is the
  # project's own GitHub release — the same trust class as the distro archive, not better — and the
  # sha256 of what was fetched is PRINTED, so a reader can compare it against the release page
  # instead of taking this script's word. It is not an authenticity check and does not pretend to be.
  # `--no-upgrade` skips this arm entirely and leaves STALE-CHECKER standing, for a venue whose
  # policy is that binaries come from the archive or not at all.
  if [ "$(checker_state)" = stale ] && [ "$UPGRADE" = 1 ]; then
    echo "→ the distro's checker still reds the witness — fetching shellcheck v${SC_WANT} from upstream"
    tgz="$(mktemp -d)/sc.tar.xz"
    url="https://github.com/koalaman/shellcheck/releases/download/v${SC_WANT}/shellcheck-v${SC_WANT}.linux.$(uname -m).tar.xz"
    if ! curl -fsSL --max-time 180 -o "$tgz" "$url"; then
      echo "⛔ could not fetch ${url} — leaving the distro checker in place; the verdict below stands." >&2
    else
      printf '  fetched %s\n  sha256  %s  (compare against the release page; this is provenance, not proof)\n' \
        "$url" "$(sha256sum "$tgz" | cut -d' ' -f1)"
      tar -xJf "$tgz" -C "$(dirname "$tgz")" 2>/dev/null
      newsc="$(dirname "$tgz")/shellcheck-v${SC_WANT}/shellcheck"
      if [ -x "$newsc" ]; then
        install -m 0755 "$newsc" /usr/local/bin/shellcheck 2>/dev/null \
          || cp "$newsc" /usr/local/bin/shellcheck
        # /usr/local/bin must WIN over the distro copy, and this file forces /usr/bin to the FRONT
        # of PATH near the top. Prepending here rather than editing that line keeps the launchd-safe
        # base intact and makes the precedence local and visible.
        PATH="/usr/local/bin:$PATH"; export PATH
        hash -r 2>/dev/null || true
        # …AND THE LAND DOES NOT RUN UNDER OUR PATH. Verify against the AMBIENT one: if a shell that
        # never sourced this script would still resolve the distro copy, our READY would be a claim
        # about a binary the gate never invokes — the one direction this file must not fail in. On
        # that venue, replace the distro copy in place so BOTH resolutions agree, and say so.
        if [ "$(PATH="$AMBIENT_PATH" command -v shellcheck 2>/dev/null)" != /usr/local/bin/shellcheck ]; then
          echo "  note: this venue's PATH resolves /usr/bin before /usr/local/bin — replacing the distro copy so the LAND sees the same binary this check does."
          install -m 0755 "$newsc" /usr/bin/shellcheck 2>/dev/null || cp "$newsc" /usr/bin/shellcheck
          hash -r 2>/dev/null || true
        fi
      else
        echo "⛔ the fetched archive did not contain an executable at the expected path — nothing installed." >&2
      fi
    fi
  fi

  # ── arm 3: THE RUNNER'S VERSION, the same arm as arm 2 for the other tool — and the one this file
  # did not have, having applied its own "presence is not a version" rule to exactly one of the two
  # binaries it installs (see the FIFTH LOCK section in the header for the measurement).
  #
  # ORDERED AFTER THE CHECKER DELIBERATELY, matching the verdict's own precedence: a land the statics
  # arm reds never reaches the smoke, so curing the runner first would spend a clone on a venue that
  # still exits 9. Both arms run in one pass because both are needed before the FIRST land, not
  # because the second depends on the first.
  #
  # SOURCE, NOT A RELEASE TARBALL: bats ships as a shell tree (bin/bats + libexec/bats-core), and its
  # own install.sh is what wires the two together — the same route .github/workflows/hermetic.yml
  # takes for the same reason. The resolved COMMIT is printed, which is the provenance analogue of
  # arm 2's sha256 and is exactly as much: a thing to compare against the tag page, never proof.
  # `--no-upgrade` skips it and leaves STALE-RUNNER standing, for an archive-only venue.
  if [ "$(runner_state)" = stale ] && [ "$UPGRADE" = 1 ]; then
    echo "→ the distro's runner cannot LOAD this repo's corpus — fetching bats-core v${BATS_WANT} from upstream"
    bsrc="$(mktemp -d)/bats-core"
    if ! git clone --depth 1 --branch "v${BATS_WANT}" --quiet \
           https://github.com/bats-core/bats-core.git "$bsrc" 2>/dev/null; then
      echo "⛔ could not clone bats-core v${BATS_WANT} — leaving the distro runner in place; the verdict below stands." >&2
    else
      printf '  fetched bats-core v%s at %s  (compare against the tag page; this is provenance, not proof)\n' \
        "$BATS_WANT" "$(git -C "$bsrc" rev-parse HEAD 2>/dev/null || echo '?')"
      if "$bsrc/install.sh" /usr/local >/dev/null 2>&1 && [ -x /usr/local/bin/bats ]; then
        PATH="/usr/local/bin:$PATH"; export PATH
        hash -r 2>/dev/null || true
        # …AND THE LAND DOES NOT RUN UNDER OUR PATH — arm 2's clause, and it bites harder here.
        # ship-land's gate_bats runs a BARE `bats "$@"`, so whichever copy the ambient PATH resolves
        # is the one that decides whether the smoke means anything. A SYMLINK rather than a copy:
        # 1.13's launcher locates its own libexec relative to the resolved path, so overwriting the
        # distro FILE with the new launcher would leave it pointing at 1.10.0's internals.
        if [ "$(PATH="$AMBIENT_PATH" command -v bats 2>/dev/null)" != /usr/local/bin/bats ]; then
          echo "  note: this venue's PATH resolves the distro runner first — pointing it at the new one so the LAND sees the same binary this check does."
          ln -sf /usr/local/bin/bats /usr/bin/bats 2>/dev/null \
            || echo "  ⛔ could not repoint /usr/bin/bats — the land may still resolve the distro runner." >&2
          hash -r 2>/dev/null || true
        fi
      else
        echo "⛔ bats-core's own install.sh did not produce an executable at /usr/local/bin/bats — nothing installed." >&2
      fi
    fi
  fi

  echo "→ re-reading the venue:"
  census
fi

# ── the assertion arm: presence is not a verdict, so make each tool SPEAK before claiming ready ───
# A tool on PATH that cannot answer is the same non-verdict one that is absent, and this is the arm
# that separates them. `--selftest` is the lint's OWN discrimination proof, so a green one is the
# strongest available statement that its clean verdict will mean something at land time.
rc=0
if [ -x "$SC_LINT" ] && repo_has_suites; then
  if out="$("$SC_LINT" --selftest 2>&1)"; then
    printf 'assert : bats-shellcheck-lint --selftest OK — %s\n' "$(printf '%s' "$out" | sed -n 's/^bats-shellcheck-lint --selftest: \([0-9]*\/[0-9]*\).*/\1/p' | head -1)"
  else
    printf 'assert : bats-shellcheck-lint --selftest did NOT pass (exit %s) — the land will not reach a verdict here.\n' "$?" >&2
    rc=1
  fi
fi
# THIS ARM USED TO PRINT `bats runs — <version string>` AND THAT WAS THE FIFTH LOCK IN ONE LINE: the
# string was true (`Bats 1.10.0`) on a venue that could not load three of its own suites, and this
# file's own header says twice that a version is a claim about the binary, not about this box. It now
# says what the runner DID — gather every suite in the corpus — which is the property the smoke needs.
case "$(runner_state)" in
  ok)
    if repo_has_suites; then
      # Counted by GLOB, not by `ls | wc -l` (SC2012, and the statics arm reds on any non-zero): the
      # shell already expanded the same pattern the probe gathered, so this is the same population.
      wit=( "${CC_VENUE_RUNNER_WITNESS:-$REPO_ROOT/tests}"/*.bats )
      printf 'assert : bats LOADS this repo — %s suite(s) gather under %s\n' \
        "${#wit[@]}" "$(bats --version 2>&1 | head -1)"
    else
      printf 'assert : bats present — %s (no tests/*.bats here, so nothing to gather)\n' "$(bats --version 2>&1 | head -1)"
    fi ;;
  stale)
    # NAMES THE SUITES, because the pooled `stale` arm cannot say whether the cause is the runner or
    # the tree, and the list is what a reader needs to tell those apart in one look. Bounded: the
    # first few, then a count, so a corpus-wide breakage cannot bury the verdict under 556 lines.
    printf 'assert : bats is present (%s) but CANNOT LOAD this repo — the smoke will attest "partial" over those suites and the land will proceed as if they had passed.\n' \
      "$(bats --version 2>&1 | head -1)" >&2
    n=0
    for s in "${CC_VENUE_RUNNER_WITNESS:-$REPO_ROOT/tests}"/*.bats; do
      [ -f "$s" ] || continue
      bats -c "$s" >/dev/null 2>&1 && continue
      n=$((n+1))
      [ "$n" -le 5 ] && printf '         · %s\n' "${s#"$REPO_ROOT"/}" >&2
    done
    [ "$n" -gt 5 ] && printf '         … and %s more\n' "$((n-5))" >&2
    printf '         If v%s is already installed, this is NOT the venue: the tree has a suite no runner can gather.\n' "$BATS_WANT" >&2
    rc=1 ;;
  absent)
    if repo_has_suites; then
      echo "assert : bats still absent — the smoke will attest \"partial\" and the land will proceed UNRUN." >&2
      rc=1
    fi ;;
esac

[ "$rc" = 0 ] && echo "✓ venue ready: this box's land path can both run and mean something."
exit "$rc"
