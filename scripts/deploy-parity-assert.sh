#!/bin/bash
# deploy-parity-assert.sh — assert the ~/bin tools actually RUNNING match this checkout.
#
# Why: ~/bin/ is the one deployed surface install.sh populates by COPY (hooks, commands,
# scripts and ~/.claude/bin/cc-* are all symlinked, so they cannot drift). A copy silently
# rots the moment the repo advances without a re-install, and nothing detected it:
#   - 2026-07-17→19 bin/claude-accounts gained the last-good quota ledger in the repo while
#     ~/bin stayed two days behind. Every consumer (cc-board, cc-context --quota, cc-route,
#     handoff-fire, lr-*) ran the OLD code, so handoff-fire read a `stale_quota` field the
#     deployed binary never emitted and silently reported "weekly n/a" forever.
#   - sync.sh copies ~/bin BACK into the repo with no direction guard, so one ./sync.sh in
#     that state would have clobbered the newer repo file with the stale copy.
# claude-accounts is therefore SYMLINKED (install.sh) and asserted STRICTLY here; the
# remaining ~/bin tools are self-updating launchers that may legitimately diverge, so they
# are asserted by CONTENT only and a difference is reported as drift, never as a hard error.
#
# SECOND LEG (2026-07-25) — EXISTENCE parity for ~/.claude. The "they are symlinked, so they
# cannot drift" assumption above is true only of files ALREADY linked, and silent about NEW
# ones: ~/.claude/{hooks,hooks/lib,commands,scripts,bin} are real dirs of PER-FILE symlinks, so
# a brand-new tracked file is never linked at all, however current the checkout. The operator's
# documented deploy step (ff-sync the shared checkout) cannot create the link — only
# ./install.sh can. That hole shipped live: hooks/lib/cc-interactive.sh landed and stayed
# unlinked, collapsing all three of bin/cc-classify's resolve candidates onto one missing path
# and silently disabling the operator-adoption hold — a reaper fail-OPEN that reclassified an
# operator-adopted pane as reapable. The leg below makes that FAIL LOUD and hands over the exact
# `ln -sf` per miss.
#
# THIRD LEG (2026-07-31) — PROVENANCE: how the shared checkout reached the commit it is on. The two
# legs above compare LIVE against CHECKOUT, and a raw `git merge --ff-only origin/main` leaves those
# two in perfect agreement while skipping both the green-stamp gate and install.sh — so the one
# failure ship.md:98 names this script the catcher of was, until now, the one failure it could not
# see. Scored as two independent facts: UNGATED (the mechanism bypassed deploy-live.sh) and
# UNVERIFIED (the live tree never earned a green stamp). Full derivation at the leg itself.
# The CONTENT fact is three-valued as of 2026-08-07 — VERIFIED · DEGRADED · UNVERIFIED — because the
# two-tier lane deploys unverified ON PURPOSE; see the DEGRADED branch for the measured incident.
#
# READ-ONLY: compares and reports. It never installs, copies, or repairs anything.
# Exit 0 = parity · 1 = a NAMED failure · 3 = NO VERDICT — the repo under assertion could not be
# resolved, so nothing was compared (see the derivation guard below). Both 0 and 1 CLAIM a
# comparison happened; this state must never borrow either exit code.
# Exit 1 covers TWO kinds, and they do NOT share a remedy: a ~/bin or existence miss is repaired by
# ./install.sh (or the printed ln -sf lines), whereas a PROVENANCE finding cannot be repaired by
# deploying again — the remedy block names the difference so the two never get one blanket fix.
# Covered by tests/deploy-parity.bats, whose fixtures drive it via CC_PARITY_REPO /
# CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY / CC_PARITY_LIVE / CC_PARITY_PENDING /
# CC_PARITY_STAMPS / CC_PARITY_PAGES / CC_PARITY_PROVENANCE (fully hermetic — no host deps).
set -uo pipefail

if [ -n "${CC_PARITY_REPO:-}" ]; then
  REPO="$CC_PARITY_REPO"
else
  # A linked worktree must assert the CANONICAL checkout (the live symlink source),
  # not itself: live ~/bin links target the shared checkout, so a self-rooted
  # comparison from a worktree reads every correct link as drift (gate red on
  # every worktree land). --git-common-dir is ".git" in the main checkout and an
  # absolute main-.git path in a linked worktree; outside git, fall back to self.
  # RESOLVE $0 THROUGH SYMLINKS FIRST. Everything under ~/.claude/scripts/ is a per-file symlink
  # into this checkout, so invoked by its DEPLOYED path a bare dirname yields ~/.claude — which is
  # not a git repo, so the fallback sets REPO=~/.claude, and every correctly-linked tool is then
  # compared against ~/.claude/bin/<tool> and reported UNLINKED. Measured 2026-07-27 immediately
  # after this leg landed: RC=0 via the checkout path, RC=1 "claude-accounts must be a symlink" via
  # the deployed path — the same script, opposite verdicts, and the DRIFT claim was the false one.
  # A guard that false-REDs through its own deployed path is worse than no guard: it trains readers
  # to ignore it, which is exactly how the deploy drift this leg exists to catch went unnoticed.
  # tests/test-hermeticity-lint.bats already carries this scar ("a false RED on a self-evidencing
  # proof, misnaming its own cause"); same loop, same reason. No `readlink -f` — GNU-only, BSD box.
  _self="${BASH_SOURCE[0]}"
  while [ -L "$_self" ]; do
    _link="$(readlink "$_self")"
    case "$_link" in
      /*) _self="$_link" ;;
      *)  _self="$(dirname "$_self")/$_link" ;;
    esac
  done
  _self_root="$(cd "$(dirname "$_self")/.." && pwd)"
  _common="$(git -C "$_self_root" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$_common" in
    "")  REPO="$_self_root" ;;
    /*)  REPO="$(cd "$_common/.." && pwd)" ;;
    *)   REPO="$(cd "$_self_root/$_common/.." && pwd)" ;;
  esac
  # THE DERIVATION MUST BE ABLE TO FAIL (2026-07-29). Every leg below is written to SKIP what it
  # cannot find: the strict loop reports SKIP on `[ ! -f "$src" ]`, the COPY and PATH loops
  # `continue` SILENTLY, and the whole existence leg is gated on `[ -e "$REPO/.git" ]`. That is
  # correct when a caller has DECLARED the subject — the hermetic fixtures do, via CC_PARITY_REPO,
  # and one of them asserts precisely that a non-checkout repo skips the existence leg. It is
  # catastrophic when the subject was DERIVED and the derivation missed: every leg skips, and the
  # script still exits 0 — "the code running IS the code in this checkout", asserted about a
  # checkout it never located. Measured on the pre-fix tree: copied into a non-repo directory it
  # printed one `SKIP claude-accounts` line and returned 0, indistinguishable by exit code from
  # real parity. A fail-OPEN on the one guard standing between a bare-ff deploy and a silently
  # stale live layer — the same shape as the drift this script exists to catch.
  # So an unresolvable REPO is a THIRD STATE: exit 3, never 0 (parity) and never 1 (drift), because
  # both of those claim a comparison that did not happen. Validated ONLY here, on the derived path:
  # CC_PARITY_REPO above is the caller declaring the subject, and it keeps its skip semantics.
  # Self-path is named literally; a rename makes this fire LOUDLY rather than rot (and
  # tests/deploy-parity.bats pins the literal against the tree so it cannot go stale unnoticed).
  if [ ! -e "$REPO/.git" ] || [ ! -f "$REPO/scripts/deploy-parity-assert.sh" ]; then
    printf 'deploy-parity-assert: CANNOT DETERMINE — no verdict, nothing was compared.\n' >&2
    printf '  resolved REPO = %s\n' "$REPO" >&2
    printf '  derived from  = %s\n' "$_self" >&2
    printf '  That is not a checkout containing this script. This is NOT a parity result: invoke it\n' >&2
    printf '  from the checkout, or set CC_PARITY_REPO to declare the subject explicitly.\n' >&2
    exit 3
  fi
fi
BINDIR="${CC_PARITY_BINDIR:-$HOME/bin}"

# Tools that MUST be symlinks into the repo (drift is structurally impossible once linked).
STRICT_TOOLS="${CC_PARITY_STRICT:-claude-accounts}"
# Tools deployed as copies — compared by content; a difference is drift, not an error.
COPY_TOOLS="${CC_PARITY_COPY:-claude-latest claude-update claude-versions browsermcp-wrapper.sh claude-kimi}"

drift=0
noverdict=0
ungated=0
unverified=0
report() { printf '  %-9s %-22s %s\n' "$1" "$2" "$3"; }

# A stamp is green iff its JSON says so. COPIED VERBATIM from deploy-live.sh:135 on purpose: the
# provenance leg below asserts the postcondition of deploy-live's OWN target choice, so the two must
# agree on what "green" means or they become two auditors over one population with different state
# models — the exact divergence this repo has already paid for elsewhere. tests/deploy-parity.bats
# pins the two bodies as identical text, so a change to either side fails loudly rather than drifts.
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

# `diff` has THREE outcomes and only two of them are verdicts: 0 = same, 1 = differ, >=2 = COULD NOT
# RUN (unreadable input, or fork exhaustion under load). Collapsing >=2 into "differ" fabricates
# STALE drift about byte-identical files — measured 2026-07-29 with a `diff` that exits 2: an
# identical pair reported `STALE  toolB  copy differs from repo` and the script exited 1 under the
# DRIFT banner. This repo has already paid for exactly this shape once, in a different file: a bare
# `grep -q` whose rc=2 under load (fork exhaustion, measured loadavg 15-48) was read as "no match"
# and fabricated hermeticity LEAKS naming provably clean suites. Fixed there by afaf40de (rc>=2 is a
# NON-VERDICT) + ed4e6c6a (retry the pure predicate before condemning); the whole story is in
# scripts/host-suites.manifest. The retry is why >=2 is rare enough to be worth reporting honestly
# rather than papering over: a transient loses to 3 tries, a real unreadable file survives them.
same_file() {   # <a> <b> → 0 same · 1 differ · 2 NO VERDICT. Callers MUST handle 2 separately.
  local i=0 rc
  while [ "$i" -lt 3 ]; do
    diff -q "$1" "$2" >/dev/null 2>&1; rc=$?
    [ "$rc" -le 1 ] && return "$rc"
    i=$((i + 1))
  done
  return 2
}

for tool in $STRICT_TOOLS; do
  src="$REPO/bin/$tool"; dest="$BINDIR/$tool"
  if [ ! -f "$src" ]; then
    report "SKIP" "$tool" "not in this checkout"
    continue
  fi
  if [ ! -e "$dest" ]; then
    report "MISSING" "$tool" "not deployed → run ./install.sh"
    drift=1
  elif [ -L "$dest" ] && [ "$(cd "$(dirname "$(readlink "$dest")")" && pwd)/$(basename "$(readlink "$dest")")" = "$src" ]; then
    report "LINKED" "$tool" "→ repo (cannot drift)"
  else
    same_file "$src" "$dest"
    case $? in
      # Content matches today, but it is a COPY where a symlink is required: it will drift
      # again on the next repo edit. Actionable now, before the divergence appears.
      0) report "UNLINKED" "$tool" "copy matches but must be a symlink → run ./install.sh"; drift=1 ;;
      1) report "STALE" "$tool" "copy DIFFERS from repo — repo edits are NOT live → run ./install.sh"
         drift=1 ;;
      *) report "NOVERDICT" "$tool" "diff could not run (3 tries) — no claim either way"
         noverdict=1 ;;
    esac
  fi
done

for tool in $COPY_TOOLS; do
  src="$REPO/bin/$tool"; dest="$BINDIR/$tool"
  [ -f "$src" ] || continue
  if [ ! -e "$dest" ]; then
    report "MISSING" "$tool" "not deployed → run ./install.sh"
    drift=1
  else
    same_file "$src" "$dest"
    case $? in
      0) report "OK" "$tool" "copy identical to repo" ;;
      1) report "STALE" "$tool" "copy differs from repo → run ./install.sh"; drift=1 ;;
      *) report "NOVERDICT" "$tool" "diff could not run (3 tries) — no claim either way"
         noverdict=1 ;;
    esac
  fi
done

# The binary actually resolved from PATH is the one every consumer runs — a matching
# ~/bin file is worthless if an earlier PATH entry shadows it.
#
# TWO FACTS WITH DIFFERENT JURISDICTIONS (split 2026-07-29). SHADOWED is a property of the
# DEPLOYMENT and is provable from here: the tool resolves, but to a file that is not the repo's,
# so this caller demonstrably runs code the checkout does not contain. NOPATH is a property of
# THIS PROCESS'S ENVIRONMENT: it says $BINDIR is absent from the PATH we happen to have been
# handed, which is not evidence about the deployment at all. Conflating them made the verdict a
# function of the caller — every daemon/hook caller whose PATH lacks $BINDIR (launchd's does:
# both plists export "$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", no
# $HOME/bin) was told "DRIFT — the code running is not the code in this checkout" while every
# filesystem leg above read LINKED/OK. That is a false alarm on a fail-closed deploy path, and
# it was masked only incidentally, by claude-accounts also being linked into ~/.claude/bin.
#
# So: NOPATH no longer sets drift by itself. The detection is NOT dropped — it becomes its own
# named check that binds where the fact is meaningful, i.e. when the PATH we are inspecting is a
# human's interactive one (stdout on a tty) or when a caller demands it explicitly.
# CC_PARITY_REQUIRE_PATH=1 forces strict, =0 forces advisory; set-but-EMPTY is honoured as unset.
if [ -n "${CC_PARITY_REQUIRE_PATH:-}" ]; then
  require_path="$CC_PARITY_REQUIRE_PATH"
elif [ -t 1 ]; then
  require_path=1                      # a human is reading this: their PATH is the one that matters
else
  require_path=0                      # daemon/hook/captured-output: our PATH is not the subject
fi
for tool in $STRICT_TOOLS; do
  [ -f "$REPO/bin/$tool" ] || continue
  onpath="$(command -v "$tool" 2>/dev/null || true)"
  if [ -z "$onpath" ]; then
    if [ "$require_path" = 1 ]; then
      report "NOPATH" "$tool" "not on PATH — add $BINDIR to PATH"
      drift=1
    else
      report "PATHGAP" "$tool" "not on THIS caller's PATH (add $BINDIR) — not deployment drift"
    fi
  else
    same_file "$REPO/bin/$tool" "$onpath"
    case $? in
      0) ;;
      1) report "SHADOWED" "$tool" "PATH resolves to $onpath, which differs from the repo"; drift=1 ;;
      *) report "NOVERDICT" "$tool" "diff could not run (3 tries) on $onpath — no claim either way"
         noverdict=1 ;;
    esac
  fi
done

# ── EXISTENCE PARITY: every tracked runtime file has a RESOLVING live counterpart ───────────────
# The (subdir, glob) set below mirrors install.sh 1:1 — hooks/*.sh, hooks/lib/*.sh, commands/*.md,
# scripts/*.sh (top level only), scripts/limit-recover/* (all types), bin/cc-*, skills/<name>/* (one
# level: install.sh:197 globs "$skilldir"* and links regular files only). Anything install.sh does
# not link is deliberately NOT asserted, so this can never demand a link that install.sh would not
# create. Live path is always $LIVE/<same relative path> (install.sh preserves the subdir).
# skills/ was MISSING from this leg until 2026-07-28 and the omission was live: skills/video-
# understanding landed 07-27 with no live symlink at all while this assert still returned 0 — the
# per-file-symlink class with the most new files was the one class nothing checked.
# NOT included: top-level lib/. It is tracked, but install.sh has NO lib leg (its only lib glob is
# hooks/lib/*.sh, already covered by the `hooks` pathspec), and asserting a link install.sh would
# never create is exactly the false demand this comment's first rule forbids.
LIVE="${CC_PARITY_LIVE:-$HOME/.claude}"
PENDING_DIRS="${CC_PARITY_PENDING:-$REPO/docs/activation/pending-activation:$LIVE/autonomy/pending-activation}"
# Post-land verification stamps, keyed by TREE sha (deploy-live.sh's contract). Read-only here.
STAMPS="${CC_PARITY_STAMPS:-$LIVE/autonomy/postland/stamps}"
# deploy-live.sh's page dir, resolved through ITS OWN env seam first so the two cannot drift apart if
# the operator relocates it — a reader that hardcodes a writer's default silently stops seeing the
# writer. CC_PARITY_PAGES is the fixture seam, matching every other CC_PARITY_* above. Read-only.
PAGES="${CC_PARITY_PAGES:-${CC_PAGES_DIR:-$LIVE/autonomy/pages}}"
missing=0
pending=0

# STAGED-PENDING is a THIRD state between "linked" and "drift", and it is the repo's own design:
# a settings-wired hook is deliberately left UNLINKED until its staged activation script runs, so
# that the missing link IS the visible signal that the wiring is pending (deploy-link-parity.sh:17,
# scripts/deploy-now.sh — "it never creates a link ... auto-linking would erase that signal").
# This leg had no such notion and reported every unlinked tracked file as MISSING ⇒ DRIFT ⇒ exit 1,
# which convicts the live layer for obeying the design. That made every staged activation a
# permanent false RED: measured 2026-07-30 at 5d85e916, where this assert reported 7 MISSING while
# deploy-link-parity — the correct reporter, same tracked set — read "259 linked · 2 staged-pending
# · 5 actionable". The 2 (hooks/qos-rewrite.sh, scripts/iterm2-perf-parity.sh) were owned by
# un-run activation scripts 22- and 24-; convicting them is the false half, and it recurs on every
# future staging. The 5 genuinely-unlinked files stay MISSING here, exactly as before.
# Semantics are ported from deploy-link-parity.sh's pending_owner() so the two agree by
# construction — a divergence between them is how this bug existed at all.
pending_owner() {   # $1 = repo-relative path → prints the owning activation script, else nothing
  local rel="$1" dir f base rest="$PENDING_DIRS"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    if [ "$rest" = "$dir" ]; then rest=""; else rest="${rest#*:}"; fi
    [ -d "$dir" ] || continue
    for f in "$dir"/*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      # A .done-marked activation no longer excuses an unlinked file: the operator ran the script,
      # so a still-missing link is a real failure, not a pending step.
      [ -e "$f.done" ] && continue
      [ -e "$LIVE/autonomy/pending-activation/$base.done" ] && continue
      # Matched on the REPO-RELATIVE PATH, never the bare basename: an activation script must spell
      # the path to build "$REPO/<path>", and loose basename matching would launder a genuinely
      # inert file into a false all-clear — the silent-failure direction.
      if grep -qF -- "$rel" "$f" 2>/dev/null; then printf '%s\n' "$base"; return 0; fi
    done
  done
  return 0
}
if [ -e "$REPO/.git" ]; then    # a tracked-file listing needs a real checkout; anything else skips
  # CAPTURE THE ENUMERATION AND ITS EXIT STATUS. Inlining `$(git ls-files)` directly in the heredoc
  # below discarded git's rc, so a FAILED listing was indistinguishable from an empty one: the loop
  # ran zero times, `missing` stayed 0, and this leg reported parity — the same non-verdict-as-verdict
  # shape as `diff` above, in the ONE leg that catches the unlinked-new-file class (the class that was
  # live at the time of writing: bin/cc-ctx-audit and hooks/lib/idl-log.sh both tracked and unlinked).
  # Proved 2026-07-29 with `.git` a DANGLING gitfile — exactly what a linked worktree becomes once its
  # main .git is gone: `[ -e "$REPO/.git" ]` passes, ls-files fails, and the assert returned 0 against
  # a deliberately EMPTY live root. Recorded as a non-verdict, never as parity.
  if ! _tracked="$(git -C "$REPO" ls-files -- hooks commands scripts bin skills 2>/dev/null)"; then
    report "NOVERDICT" "(existence)" "git ls-files failed in $REPO — the tracked set is unknown"
    noverdict=1
    _tracked=""
  fi
  # Heredoc, NOT a pipe: the loop must run in THIS shell or its `missing`/`drift` writes are lost.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # NOTE: in a `case` pattern `*` also matches `/`, so each deeper-path exclusion must precede the
    # shallower pattern it would otherwise be swallowed by. Order here is load-bearing.
    case "$rel" in
      hooks/lib/*.sh)            want=1 ;;
      hooks/*/*)                 want=0 ;;   # no other hooks/ subdir is deployed
      hooks/*.sh)                want=1 ;;
      commands/*/*)              want=0 ;;
      commands/*.md)             want=1 ;;
      scripts/limit-recover/*/*) want=0 ;;
      scripts/limit-recover/*)   want=1 ;;
      scripts/*/*)               want=0 ;;   # scripts/ is globbed top-level only
      scripts/*.sh)              want=1 ;;
      bin/cc-*/*)                want=0 ;;
      bin/cc-*)                  want=1 ;;
      skills/*/*/*)              want=0 ;;   # install.sh links skills/<name>/<file>, one level only
      skills/*/*)                want=1 ;;
      *)                         want=0 ;;
    esac
    [ "$want" = 1 ] || continue
    # -e follows symlinks on purpose: a link whose target is gone is as dead as no link at all.
    [ -e "$LIVE/$rel" ] && continue
    # Unlinked BY DESIGN while its staged activation is un-run — reported, never counted as drift.
    _act="$(pending_owner "$rel")"
    if [ -n "$_act" ]; then
      report "PENDING" "$rel" "unlinked BY DESIGN — staged: $_act"
      pending=$((pending + 1))
      continue
    fi
    printf 'MISSING: ln -sf %s %s\n' "$REPO/$rel" "$LIVE/$rel"
    missing=$((missing + 1))
    drift=1
  done <<EOF
$_tracked
EOF
fi
if [ "$missing" -ne 0 ]; then
  printf '\ndeploy-parity-assert: %s tracked runtime file(s) have NO live counterpart under %s.\n' "$missing" "$LIVE" >&2
  # THE REMEDY MUST NOT DESTROY THE STATE THIS SCRIPT JUST REPORTED. ./install.sh globs
  # hooks/*.sh (install.sh:89) and scripts/*.sh (install.sh:200) UNCONDITIONALLY and has no notion
  # of staged-pending whatsoever (`grep -n pending-activation install.sh` → zero hits), so running
  # it while a PENDING file is listed links that file too — erasing the "activation un-run" signal
  # while the activation itself stays un-run, and the operator's own hand-step (which creates that
  # symlink as its step 1, bundled with the settings.json wiring) silently becomes a partial no-op.
  # The classification half of this landed in f0186bbd; the PRESCRIPTION half did not, so the
  # script went on recommending the one command that undoes its own finding. Near-missed
  # 2026-07-30 on the live host (2 PENDING + 5 MISSING): the targeted lines were run instead.
  # A symptom and its prescribed remedy rot independently — both halves have to be checked.
  if [ "$pending" -ne 0 ]; then
    printf 'A bare ff-sync of the checkout can never create these links — run the ln -sf lines above.\n' >&2
    printf 'Do NOT run ./install.sh while a PENDING file is listed below: it globs hooks/*.sh and\n' >&2
    printf 'scripts/*.sh unconditionally, so it would link the staged-pending file(s) too and erase\n' >&2
    printf 'that signal. Run the targeted ln -sf lines, which leave the staged state intact.\n' >&2
  else
    printf 'A bare ff-sync of the checkout can never create these links — run ./install.sh (or the ln -sf lines above).\n' >&2
  fi
fi
# Emitted even when nothing is missing: a silent PENDING count is how "unlinked by design" decays
# into "nobody remembers this is un-run". It is a fact about the queue, never a verdict on parity.
if [ "$pending" -ne 0 ]; then
  printf '\ndeploy-parity-assert: %s file(s) staged-pending (unlinked BY DESIGN, activation un-run) — not drift.\n' "$pending" >&2
fi

# ── THIRD LEG: DEPLOY PROVENANCE — HOW the live checkout reached the commit it is on ────────────
# Both legs above ask "does the LIVE layer match the CHECKOUT?". Neither can answer the question
# ship.md:98 actually assigns to this file — "the check that catches a bare-ff deploy after the
# fact" — because a raw `git merge --ff-only origin/main` in the shared checkout leaves live and
# checkout in PERFECT agreement. It skips the green-stamp gate and skips install.sh, and is then
# indistinguishable from a sanctioned deploy by every quantity either leg above measures.
#
# Measured on the shared checkout 2026-07-31: of the last 30 HEAD reflog entries, 29 were ungated
# advances (`merge origin/main` / `pull --ff-only`) against 2 sanctioned ones. They carried live
# HEAD to ec92e68c — 196 commits ABOVE the newest green-stamped commit 34e725d6 — so deploy-live's
# monotonicity guard now refuses on every 600s tick ("would ROLL BACK the live layer"), 96 refusals
# and counting. The sanctioned lane is DEADLOCKED, and the green-stamp gate is thereby MOOT: the
# verifier can now only ever green a tree the live layer has already been running, unverified.
#
# WHY A NEW LEG RATHER THAN LEANING ON THE EXISTENCE LEG'S `MISSING` LINES: 70d86739 (2026-07-31)
# made deploy-live's link_refresh UNCONDITIONAL, so it repairs exactly those links on every tick,
# INCLUDING the refusing ones. That is correct for availability, and it erases the only residue a
# raw ff used to leave behind — the symptom is now cleaned up on a 600s timer while the ungated
# advance that caused it goes on undetected. Reading the CAUSE is the only thing left that can see
# it, which is why five prior sessions each measured "drift at its historical minimum" and closed.
#
# TWO INDEPENDENT FACTS, separated because they have different causes and different remedies:
#   UNGATED    — the MECHANISM bypassed deploy-live.sh (a raw ff/pull/reset moved HEAD).
#   UNVERIFIED — the CONTENT never passed the green gate. Also true after a deliberate --force or
#                --bootstrap deploy, which is sanctioned in mechanism but unverified in content.
# A healthy deploy trips neither · a raw ff trips both · an operator's --force trips only the second.
#
# SUBJECT DISCIPLINE, the same rule the derivation guard states at the top of this file: skipping is
# correct when a caller has DECLARED the subject. Provenance is a property of the REAL live
# checkout, so it runs on the DERIVED path only — every hermetic fixture declares CC_PARITY_REPO and
# is therefore exempt by construction, which is why this leg cannot false-RED the fixture cases (a
# `git init`'d fixture with no commits would otherwise read as UNGATED on all of them).
# CC_PARITY_PROVENANCE=1/0 forces it either way (set-but-EMPTY honoured as unset) — the same seam
# shape as CC_PARITY_REQUIRE_PATH above, and how the hermetic cases drive this leg at all.
# Snapshot BEFORE this leg can touch `drift`: the closing banner must not tell an operator "the code
# running is not the code in this checkout" when the only finding is provenance — under a raw ff the
# code running IS this checkout, byte for byte, and that sentence sends the reader hunting a content
# difference that does not exist. Two kinds of exit 1, two accurate sentences.
content_drift="$drift"
if [ -n "${CC_PARITY_PROVENANCE:-}" ]; then
  do_provenance="$CC_PARITY_PROVENANCE"
elif [ -z "${CC_PARITY_REPO:-}" ]; then
  do_provenance=1
else
  do_provenance=0
fi
if [ "$do_provenance" = 1 ] && [ -e "$REPO/.git" ]; then
  # The reflog's NEWEST entry is BY DEFINITION the operation that set HEAD to its current value, so
  # it is a record of how the live layer got here, not an inference from the commit graph.
  # Reflogs are local and expire (gc.reflogExpire, 90d default) and a fresh clone has none, so an
  # empty/unreadable one is a NON-VERDICT — never a pass. Same doctrine as `diff` rc>=2 above.
  _how="$(git -C "$REPO" log -g -1 --format=%gs HEAD 2>/dev/null || true)"
  if [ -z "$_how" ]; then
    report "NOVERDICT" "(provenance)" "HEAD reflog empty/unreadable — cannot say how this checkout advanced"
    noverdict=1
  else
    # deploy-live.sh resolves its target to an object name BEFORE merging (`merge --ff-only
    # "$TARGET"`, TARGET from rev-parse), so a sanctioned advance always reflogs a SHA. Every
    # ungated path either names a REF (`merge origin/main`) or is not a merge at all (`pull …`,
    # `reset …`, `checkout …`). That is the entire discriminator, and it holds for --bootstrap and
    # --force too: both reach the same resolved-SHA merge, which is why mechanism and content are
    # scored separately below rather than collapsed into one verdict.
    _sanctioned=0
    case "$_how" in
      "merge "*": Fast-forward")
        _tgt="${_how#merge }"; _tgt="${_tgt%: Fast-forward}"
        # Hex-only and >=7 chars ⇒ an object name. `origin/main` and every other ref spelling this
        # repo uses contains a character outside [0-9a-f], so a ref can never launder into a SHA.
        case "$_tgt" in
          ""|*[!0-9a-f]*) ;;
          *) [ "${#_tgt}" -ge 7 ] && _sanctioned=1 ;;
        esac ;;
      "clone: from "*) _sanctioned=1 ;;   # the checkout's birth — no advance has happened yet
    esac
    if [ "$_sanctioned" = 1 ]; then
      report "GATED" "(provenance)" "HEAD advanced via deploy-live — $_how"
    else
      report "UNGATED" "(provenance)" "HEAD advanced OUTSIDE deploy-live — $_how"
      ungated=1
      drift=1
    fi
  fi
  # CONTENT. After a sanctioned advance HEAD's TREE carries a green stamp BY CONSTRUCTION — that is
  # how deploy-live picked it (first green tree, walking origin/main newest-first). So ONE stamp
  # lookup asserts the gate's postcondition without re-deriving its target selection. Re-deriving it
  # is specifically refused: never re-implement an atomic gate's predicate outside the gate, or the
  # assert quietly becomes a second, divergent gate. (Calling deploy-live --dry-run to ask the
  # arbiter directly is also refused — deploy-live calls THIS script for link_refresh, so that would
  # recurse.) No stamps dir ⇒ the verification net is not active, which is deploy-live's own
  # separate refusal state ⇒ nothing to compare and this leg makes NO claim either way.
  #
  # THE CONTENT FACT IS THREE-VALUED, and the third value is the whole reason this branch exists.
  # "BY CONSTRUCTION" above was true of the SINGLE-TIER gate and was falsified the day the two-tier
  # lane went live: T2 (DEPLOY_LANE_GROUND_UP.md §2.2, deploy-live.sh:568) deploys the newest NOT-RED
  # commit ON PURPOSE once the green cursor is past its staleness budget. That advance is sanctioned
  # in mechanism (resolved-SHA ff ⇒ GATED above) and unverified in content BY DESIGN — so a leg that
  # reads "no green stamp ⇒ DRIFT" convicts the lane of the one thing it just announced.
  #
  # MEASURED 2026-08-07, ~/.claude/autonomy/postland/deploy.log, four consecutive lines:
  #     deploy-live: !!!!! DEGRADED deploy — no GREEN stamp …; taking the newest NOT-RED commit
  #                  instead, authorised by 7h since the live commit was authored (budget 6h) !!!!!
  #     deploy-live: deployed 38e2513b0cce → 488742fcb66a: …
  #     deploy-live: post-deploy host checks: 8 suite(s) from host-suites.manifest …
  #     deploy-live:   RED  tests/deploy-parity-live.bats — 1 failing
  # The lane declared the state, deployed, then ran the suite that reds on exactly that state, paged
  # the operator and filed backlog 13ba97f1701d. The alarm restates the banner four lines above it —
  # zero bits, and it fires on EVERY degraded deploy, which on this machine is the normal tier (the
  # green cursor produced 2 greens in 85 verifier runs against ≈63 commits/day).
  #
  # WHAT MAKES IT THE THIRD STATE RATHER THAN A PASS: the discriminator is a record the ACTUATOR
  # wrote — deploy-live.sh:715 emits deploy-degraded-<sha12>.page AFTER the merge specifically so it
  # "can never claim one that did not" happen. This leg reads it; it does NOT re-derive the degrade
  # predicate (lag budget, RED walk-back, kill switch) — re-implementing an atomic gate's predicate
  # outside the gate is how an assert quietly becomes a second, divergent gate, which the paragraph
  # above already refuses for target selection. Sha-keyed, so the page can only vouch for the exact
  # commit the lane moved to.
  #
  # FAIL-CLOSED, AND NOT AN EXCUSE FOR --force. Page absent ⇒ nothing is laundered: the flow falls
  # through to UNVERIFIED ⇒ drift, unchanged. That is what keeps the sibling case honest — a --force
  # deploy is GATED and unverified and writes NO degrade page, so it still exits 1 (the leg's own
  # `--force's shape ⇒ GATED but UNVERIFIED` test is the pin, and it stays red on this branch by
  # construction). This state is REPORTED, never silent: the operator sees the line here, and the
  # lane's own page is the escalation channel that already exists — a second page would double-fire.
  if [ -d "$STAMPS" ]; then
    _tree="$(git -C "$REPO" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
    _sha="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "$_tree" ]; then
      report "NOVERDICT" "(verification)" "cannot resolve HEAD tree in $REPO — no claim about verification"
      noverdict=1
    elif is_green "$STAMPS/$_tree.json"; then
      report "VERIFIED" "(verification)" "HEAD tree carries a GREEN post-land stamp"
    elif [ -n "$_sha" ] && [ -f "$PAGES/deploy-degraded-${_sha:0:12}.page" ]; then
      report "DEGRADED" "(verification)" "no green stamp, but deploy-live DECLARED this advance degraded (${_sha:0:12}) — sanctioned, not drift"
    else
      report "UNVERIFIED" "(verification)" "HEAD tree $_tree has NO green stamp — this tree never passed the gate"
      unverified=1
      drift=1
    fi
  fi
fi
# THE REMEDY IS NOT "RE-RUN THE DEPLOY". Nothing here can be repaired by advancing again, and the
# one command that looks like it would (a raw ff to origin/main) is the cause. So this block names
# the consequence and hands over a READ-ONLY diagnostic, per the same rule the existence leg learned
# the hard way: a prescription that undoes the state the script just reported is worse than none.
if [ "$ungated" -ne 0 ] || [ "$unverified" -ne 0 ]; then
  printf '\ndeploy-parity-assert: PROVENANCE — the live layer did not get here through the deploy gate.\n' >&2
  if [ "$ungated" -ne 0 ]; then
    printf '  A raw ff/pull moved the shared checkout. It advances FILES but creates NO symlinks, so any\n' >&2
    printf '  brand-new tracked file lands unlinked and silently does nothing (ship.md:98).\n' >&2
  fi
  if [ "$unverified" -ne 0 ]; then
    printf '  The tree now LIVE never earned a green post-land stamp — nothing vouches for what is running.\n' >&2
    printf '  While live HEAD sits ABOVE the newest green-stamped commit, deploy-live.sh refuses every\n' >&2
    printf '  tick (the target "is not a descendant of live HEAD"): the sanctioned lane is not merely idle.\n' >&2
  fi
  printf '  Ask the gate itself (read-only, mutates nothing):  bash %s/scripts/deploy-live.sh --dry-run\n' "$REPO" >&2
  # QUOTE NO EXACT REFUSAL STRING BEYOND THE STABLE CLAUSE ABOVE. This block used to quote
  # "would ROLL BACK the live layer" verbatim as what the reader would find in deploy.log. That
  # message was reworded on 2026-08-07 (deploy-live.sh now names the real hazard — `--ff-only` exits 0
  # without moving the tree, so the lane would report a deploy that never happened), and this printf
  # went stale the moment it landed: it sent the operator looking for a string that no longer exists.
  # An operator-facing diagnostic that quotes another file's output is a cross-file coupling with no
  # test holding it — so quote only the durable predicate clause, never the whole sentence.
  #
  # THE PROGNOSIS BELOW ALSO CHANGED — TWICE, and the second correction is the one that bites.
  # Until 2026-08-07 this said the condition "does NOT clear on its own" because the green gate was
  # structurally unsatisfiable at the fleet's commit rate (3h verify vs ~7min between commits), and
  # naming an unreachable cure is how an alarm becomes furniture. The 08-07 rewrite kept that as its
  # characterisation of the single-tier gate — "that was correct for the single-tier gate" — and it
  # was NOT. DEPLOY_GATE_CONVERGENCE.md §7 withdrew exactly this claim 53 minutes after it was first
  # written (ban 0d03c584 16:14 → retraction 397cad30 17:07, 2026-07-31), so the doc that was being
  # cited as the authority for it already said the opposite; nothing connected the two, and the dead
  # mechanism was carried forward through a rewrite that touched the very lines holding it.
  #
  # What §7 measured: the claim came from testing a TREE sha with a COMMIT predicate
  # (merge-base --is-ancestor), which exits 128 for every input — including the tip's own tree as a
  # positive control — so it could only ever print 0. Re-derived, the gate's predicate is CORRECT
  # and commit rate was never the mechanism: deploy-live scans back CC_DEPLOY_SCAN commits and takes
  # the FIRST green, so lag is designed for. The single-tier gate's real limitation is narrower —
  # it has no STALENESS BUDGET, so it waits for a green instead of degrading past one — and what
  # withholds that green is §7.4's churning red set.
  #
  # Why the distinction is worth these lines: commit rate is UNFIXABLE, so naming it hands the
  # reader a permanent --force at the exact moment they are deciding what to do about a broken
  # deploy, and it discourages the triage that actually clears the lane. Cite the SECTION, never the
  # doc's head — that head is still a title asserting the withdrawn claim. Carry no number that can
  # rot: the doc holds those and can be re-measured, this file cannot.
  # BOTH doc references are load-bearing and the remedy test below pins both.
  # DEPLOY_GATE_CONVERGENCE.md §7 is why a green is withheld and how to triage it;
  # DEPLOY_LANE_GROUND_UP.md is the two-tier remedy that removes the waiting altogether.
  printf '  Whether this clears on its own depends on which advancer is LIVE: the two-tier lane\n' >&2
  printf '  (DEPLOY_LANE_GROUND_UP.md §2.2) degrades past its staleness budget and clears by itself;\n' >&2
  printf '  the older single-tier gate has no such budget, so it waits for a GREEN. That wait is NOT\n' >&2
  printf '  permanent and NOT a commit-rate limit: deploy-live scans back CC_DEPLOY_SCAN commits and\n' >&2
  printf '  takes the FIRST green, so a green on ANY tree in that window releases the lane. What\n' >&2
  printf '  withholds one is a CHURNING red set — mostly machine-state-coupled suites convicting on a\n' >&2
  printf '  loaded box, not on the tree. Triage that, do not wait for it:\n' >&2
  printf '    docs/plans/DEPLOY_GATE_CONVERGENCE.md §7   (§7.4 the mechanism · §7.8 how to triage it)\n' >&2
  printf '  Read §7 FIRST — its title and §1-§5 are withdrawn by §7 itself. In flakes.jsonl a 1-of-3\n' >&2
  printf '  row is ALREADY acquitted.\n' >&2
  printf '  Check which is live:  grep -c CC_DEPLOY_DEGRADE %s/scripts/deploy-live.sh\n' "$HOME/.claude" >&2
  printf '  A raw ff is not a workaround for a red corpus — it IS this finding.\n' >&2
fi

# ORDER IS THE DOCTRINE: a NAMED failure outranks a non-verdict. Real drift was actually observed on
# some tool, so it is reported as drift even if a different tool's comparison could not run — the
# same rule deploy-live.sh's host_checks applies (R6: a named failure is the only red; an rc that
# names zero failures is a CUT, a fact about the machine, never a claim about the subject).
if [ "$drift" -ne 0 ]; then
  if [ "$content_drift" -ne 0 ]; then
    printf '\ndeploy-parity-assert: DRIFT — the code running is not the code in this checkout.\n' >&2
  else
    printf '\ndeploy-parity-assert: DRIFT — the code running IS this checkout, but it never came\n' >&2
    printf 'through the deploy gate. Nothing above is a content difference; see PROVENANCE.\n' >&2
  fi
  exit 1
fi
if [ "$noverdict" -ne 0 ]; then
  printf '\ndeploy-parity-assert: NO VERDICT — a comparison could not run, and every leg that DID\n' >&2
  printf 'run found parity. This is not a parity result: re-run it (typically transient load).\n' >&2
  exit 3
fi
exit 0
