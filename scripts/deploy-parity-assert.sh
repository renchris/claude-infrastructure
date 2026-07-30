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
# READ-ONLY: compares and reports. It never installs, copies, or repairs anything.
# Exit 0 = parity · 1 = drift (actionable: re-run ./install.sh) · 3 = NO VERDICT — the repo under
# assertion could not be resolved, so nothing was compared (see the derivation guard below). Both 0
# and 1 CLAIM a comparison happened; this state must never borrow either exit code.
# Covered by tests/deploy-parity.bats, whose fixtures drive it via CC_PARITY_REPO /
# CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY / CC_PARITY_LIVE / CC_PARITY_PENDING
# (fully hermetic — no host deps).
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
report() { printf '  %-9s %-22s %s\n' "$1" "$2" "$3"; }

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

# ORDER IS THE DOCTRINE: a NAMED failure outranks a non-verdict. Real drift was actually observed on
# some tool, so it is reported as drift even if a different tool's comparison could not run — the
# same rule deploy-live.sh's host_checks applies (R6: a named failure is the only red; an rc that
# names zero failures is a CUT, a fact about the machine, never a claim about the subject).
if [ "$drift" -ne 0 ]; then
  printf '\ndeploy-parity-assert: DRIFT — the code running is not the code in this checkout.\n' >&2
  exit 1
fi
if [ "$noverdict" -ne 0 ]; then
  printf '\ndeploy-parity-assert: NO VERDICT — a comparison could not run, and every leg that DID\n' >&2
  printf 'run found parity. This is not a parity result: re-run it (typically transient load).\n' >&2
  exit 3
fi
exit 0
