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
# browsermcp-wrapper.sh left this list when the server was retired (2026-08-11) — a parity list that
# names a file the repo no longer ships reports drift forever, which is how a guard stops being read.
COPY_TOOLS="${CC_PARITY_COPY:-claude-latest claude-update claude-versions claude-kimi}"

drift=0
noverdict=0
ungated=0
unverified=0
report() { printf '  %-9s %-22s %s\n' "$1" "$2" "$3"; }

# ── PER-CLASS ACCOUNTING (2026-08-10, P6) ───────────────────────────────────────────────────────
# The legs below report PER FILE, which is right for acting on a miss and useless for answering the
# question this script exists to answer: "is every class install.sh deploys actually covered?". The
# 5-of-19 hole (§2.E) survived five sessions of readers precisely because a per-file report over a
# 5-class pathspec is INDISTINGUISHABLE from a per-file report over a 19-class one when both are
# clean — absence of a row for `agents/*.md` reads exactly like parity for `agents/*.md`. The table
# renders every class WITH ITS COUNTS, so an unenumerated class shows up as a class that is not
# there rather than as silence. One row per class; the counts are the evidence.
#
# bash 3.2 (the BSD box) has no associative arrays, so rows accumulate as TAB-delimited text and are
# folded once at render time, in first-seen order.
CLS_ROWS=""
cls_row() {   # <class-label> <live|miss|pending|drift>
  [ -n "$1" ] || return 0
  CLS_ROWS="$CLS_ROWS$1	$2
"
}
cls_table() {
  [ -n "$CLS_ROWS" ] || return 0
  printf '\n  class parity (install.sh deploy classes · tracked ⇒ live)\n'
  printf '%s' "$CLS_ROWS" | awk -F'\t' '
    $1 == "" { next }
    { if (!(($1) in seen)) { seen[$1]=1; order[++n]=$1 }
      t[$1]++; if ($2=="live") l[$1]++; else if ($2=="pending") p[$1]++
               else if ($2=="drift") d[$1]++; else m[$1]++ }
    END { for (i=1; i<=n; i++) { c=order[i]
            # DRIFT is its own state, never folded into "missing": the root-SSOT drift class is a
            # file that EXISTS live and is the wrong KIND (a copy where a link is required), so
            # counting it as missing would contradict the very leg that just found it — and the
            # "N tracked runtime file(s) have NO live counterpart" summary below would be false.
            # The segment is appended ONLY when non-zero, so every clean class renders byte-
            # identically to before this state existed.
            s = (m[c]+0 > 0) ? "MISS" : ((d[c]+0 > 0) ? "DRIFT" : ((p[c]+0 > 0) ? "PEND" : "ok"))
            printf("  %-9s %-22s %d tracked · %d live · %d missing%s%s\n",
                   s, c, t[c], l[c]+0, m[c]+0,
                   (d[c]+0 > 0) ? sprintf(" · %d drifted", d[c]) : "",
                   (p[c]+0 > 0) ? sprintf(" · %d staged-pending", p[c]) : "") } }'
}

# ── FILING: a verdict that only PRINTS reaches nobody (2026-08-10, P6) ──────────────────────────
# The UNGATED provenance finding has printed on every tick for weeks and filed nothing, so it lives
# only in a log nobody folds into a close: measured 601 refusals with zero escalation. A finding
# that is not in a STORE is not surfaced — the same law the close protocol states for operator-only
# steps ("prose is where it gets buried"). These file into cc-backlog, the sanctioned store, which a
# renderer already reads.
#
# THREE PROPERTIES, each one load-bearing:
#  1. SUBJECT DISCIPLINE — filing runs on the DERIVED path only, exactly like the provenance leg. A
#     fixture that declares CC_PARITY_REPO is exempt by construction, so no hermetic case can write
#     into the operator's real ledger. CC_PARITY_FILE=1/0 forces it (set-but-EMPTY honoured as
#     unset), which is how the hermetic cases drive this at all.
#  2. DAMPED BY CONDITION KEY — the trigger is a recurring STATE, not an event, so the filed TITLE
#     carries no sha/timestamp/count. cc-backlog's id is a hash of project+title+source, so a
#     constant title IS the condition key: a re-file is idempotent on the same id. (`needs` has no
#     --condition flag; a stable title reaches the same place without reaching into another tool's
#     argument parser.) The local marker below then stops us SHELLING OUT 144×/day and stops the
#     DONE-GUARD from re-announcing on stderr into deploy.log at every tick.
#  3. FAILS NO WIDER THAN ITSELF — every path returns 0. This function can never set `drift`, change
#     an exit code, or block link_refresh's consumption of the MISSING lines. A parity leg that
#     could break the advance path would be a converger that stops convergence.
# FILED_DIR is bound once $LIVE is resolved (it defaults under it); declared here only so `set -u`
# cannot trip on a use before that binding.
FILED_DIR=""
FILE_TTL_MIN="${CC_PARITY_FILE_TTL_MIN:-360}"            # 6h: re-assert a standing condition, do not spam
BACKLOG_BIN_P="${CC_PARITY_BACKLOG_BIN-$HOME/.claude/bin/cc-backlog}"
file_need() {   # <condition-slug> <operator-facing step sentence>   → always 0
  local slug="$1" step="$2" marker
  [ -n "$slug" ] && [ -n "$step" ] || return 0
  if [ -n "${CC_PARITY_FILE:-}" ]; then
    [ "$CC_PARITY_FILE" = 1 ] || return 0
  elif [ -n "${CC_PARITY_REPO:-}" ]; then
    return 0                       # a declared fixture subject never writes to a real store
  fi
  [ -n "$BACKLOG_BIN_P" ] && [ -x "$BACKLOG_BIN_P" ] || return 0
  marker="$FILED_DIR/$slug"
  # Damped: a marker younger than the TTL means this condition was filed recently and the row is
  # already open. `find -mmin` rather than stat(1) — BSD and GNU stat disagree on every flag.
  if [ -f "$marker" ] && [ -z "$(find "$marker" -mmin "+$FILE_TTL_MIN" 2>/dev/null)" ]; then
    return 0
  fi
  mkdir -p "$FILED_DIR" 2>/dev/null || return 0
  if "$BACKLOG_BIN_P" needs "$step" --project claude-infrastructure >/dev/null 2>&1; then
    : > "$marker" 2>/dev/null || true
    report "FILED" "($slug)" "operator-owned step filed to cc-backlog — it renders at the next close"
  fi
  return 0
}

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
# The (subdir, glob) set below mirrors install.sh 1:1 — hooks/*.sh, hooks/*.py, hooks/lib/*.sh,
# commands/*.md, agents/*.md, lib/*.{sh,zsh} (top level only), scripts/*.sh (top level only),
# scripts/lib/*.sh, scripts/limit-recover/* (all types), bin/cc-*, bin/desk-*, skills/<name>/* (one
# level: install.sh globs "$skilldir"* and links regular files only), the two root-config SSOTs
# (model-config.yaml, providers.json), and vendor/<plugin>/ as ONE DIRECTORY link. Anything
# install.sh does not link is deliberately NOT asserted, so this can never demand a link that
# install.sh would not create. Live path is always $LIVE/<same relative path> (install.sh preserves
# the subdir) — that invariant is what lets deploy-live.sh's link_refresh consume the MISSING lines
# verbatim, and it holds for every SYMLINK class. It does NOT hold for install.sh's COPY classes,
# which is why those get their own leg below and never an `ln -sf` line.
# skills/ was MISSING from this leg until 2026-07-28 and the omission was live: skills/video-
# understanding landed 07-27 with no live symlink at all while this assert still returned 0 — the
# per-file-symlink class with the most new files was the one class nothing checked.
#
# WIDENED 2026-08-10 (P6, docs/research/land-architecture-100p-2026-08-10.md §2.E). The pathspec was
# `hooks commands scripts bin skills` — 5 of install.sh's ~19 deploy classes — and deploy-live's
# link_refresh consumes ONLY this leg's output, so the tick-driven ADD-repair was scoped to exactly
# those five. Everything else (agents/, lib/, vendor/, bin/desk-*, hooks/*.py, scripts/lib/*.sh, the
# root-config SSOTs) reached the live layer only when `install.sh` ran, and install.sh runs only
# after a SUCCESSFUL advance — a lane that had refused 601 consecutive times on the measured host.
# A brand-new file in any of those classes was therefore inert until a green stamp released the
# lane: not stale-but-present (which is what a lag budget is for) but ABSENT, and every consumer
# guard on it (`[ -f x ] && . x`, `command -v fn && fn`) a silent skip. Measured in parity on
# 2026-08-10 across all classes, so this widening is a latent hole closed, not an outage repaired.
#
# The prior version of this comment ended "NOT included: top-level lib/ … install.sh has NO lib leg".
# That was true when written and FALSE from 931641a4 onward (install.sh:360 globs lib/*.zsh and
# lib/*.sh). A rule stated as a permanent fact about another file rots the moment that file changes,
# so the enumeration is now pinned against install.sh's own loops by a test rather than by prose.
LIVE="${CC_PARITY_LIVE:-$HOME/.claude}"
PENDING_DIRS="${CC_PARITY_PENDING:-$REPO/docs/activation/pending-activation:$LIVE/autonomy/pending-activation}"
# Post-land verification stamps, keyed by TREE sha (deploy-live.sh's contract). Read-only here.
STAMPS="${CC_PARITY_STAMPS:-$LIVE/autonomy/postland/stamps}"
# deploy-live.sh's page dir, resolved through ITS OWN env seam first so the two cannot drift apart if
# the operator relocates it — a reader that hardcodes a writer's default silently stops seeing the
# writer. CC_PARITY_PAGES is the fixture seam, matching every other CC_PARITY_* above. Read-only.
PAGES="${CC_PARITY_PAGES:-${CC_PAGES_DIR:-$LIVE/autonomy/pages}}"
# Damping markers for file_need() above — under $LIVE so a fixture live root isolates them with
# everything else, and so the operator's own damping state is co-located with the deploy state it
# describes rather than in /tmp (which a reboot wipes, turning a damper into a re-filer).
FILED_DIR="${CC_PARITY_FILED_DIR:-$LIVE/autonomy/parity-filed}"
missing=0
pending=0
orphans=0

# STAGED-PENDING is a THIRD state between "linked" and "drift", and it is the repo's own design:
# a settings-wired hook is deliberately left UNLINKED until its staged activation script runs, so
# that the missing link IS the visible signal that the wiring is pending (deploy-link-parity.sh:17 —
# "it never creates a link ... auto-linking would erase that signal"). scripts/deploy-now.sh carried
# that sentence too until it became a thin front-end onto deploy-live.sh; the design outlived it,
# because deploy-live's link_refresh consumes THIS leg's MISSING verdict, so the PENDING files
# `continue`d below are exactly why an auto-linking deploy path can exist without erasing the signal.
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
  # This pathspec is the walk's INPUT and it is the FIRST of the two gates a class passes. It lists
  # ten entries where install.sh globs from twelve top-level directories: githooks/ and launchd/ are
  # absent BY DESIGN, because install.sh COPIES those two classes (into .git/hooks + the git template,
  # and into ~/Library/LaunchAgents) rather than linking them into $CFG. The NOT-PER-FILE arms in the
  # case block below declare the same exclusion at the second gate — stated twice on purpose, since a
  # class dropped by an input filter alone leaves no reason behind anywhere a reader will look.
  if ! _tracked="$(git -C "$REPO" ls-files -- hooks commands scripts bin skills agents lib vendor model-config.yaml providers.json 2>/dev/null)"; then
    report "NOVERDICT" "(existence)" "git ls-files failed in $REPO — the tracked set is unknown"
    noverdict=1
    _tracked=""
  fi
  # The two accumulators the ORPHAN sweep below reads. They are filled by the SAME walk that emits
  # MISSING, which is the whole point: the reverse sweep's scope is DERIVED from the want-list, not
  # maintained beside it. See the sweep's own header for why a second directory list is a defect.
  _claimed=""   # rels this walk owns — the sweep defers to it rather than double-claiming a path
  _odirs=""     # live-relative dirs the want-list populates — the sweep visits exactly these
  # Heredoc, NOT a pipe: the loop must run in THIS shell or its `missing`/`drift` writes are lost.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # NOTE: in a `case` pattern `*` also matches `/`, so each deeper-path exclusion must precede the
    # shallower pattern it would otherwise be swallowed by. Order here is load-bearing.
    # `cls` is the install.sh class this path belongs to; it feeds the per-class table below, so a
    # class that is enumerated but never counted cannot hide (want=0 rows are counted as "not
    # deployed by install.sh" and simply never appear).
    cls=""
    case "$rel" in
      hooks/lib/*.sh)            want=1; cls='hooks/lib/*.sh' ;;
      hooks/*/*)                 want=0 ;;   # no other hooks/ subdir is deployed
      hooks/*.sh)                want=1; cls='hooks/*.sh' ;;
      # install.sh:272 globs hooks/*.py too — settings.json wires curl-gate.py and
      # enforce-email-formatting.py BY PATH, so an unlinked python hook is a wiring that resolves to
      # nothing. This leg matched only *.sh, so the class install.sh added in 2026-07-25 was never
      # asserted by the check that exists to catch exactly that omission.
      hooks/*.py)                want=1; cls='hooks/*.py' ;;
      commands/*/*)              want=0 ;;
      commands/*.md)             want=1; cls='commands/*.md' ;;
      # agents/ — NAME-invoked surfaces (`subagent_type: "deep-research"`) with zero grep-able
      # callers, so an unlinked agent file is a spawn that silently resolves to nothing.
      # install.sh:271 states the hazard in its own words: "a brand-new tracked file is not linked at
      # all, however current the checkout."
      agents/*/*)                want=0 ;;
      agents/*.md)               want=1; cls='agents/*.md' ;;
      # top-level lib/ — install.sh:360 globs lib/*.zsh AND lib/*.sh (both extensions are
      # load-bearing: .zsh for zsh-only libs, .sh for the bash/zsh-portable ones a bats suite
      # sources). Subdirs (lib/cc-upgrade-gate/) are NOT globbed and must not be demanded.
      lib/*/*)                   want=0 ;;
      lib/*.sh|lib/*.zsh)        want=1; cls='lib/*.{sh,zsh}' ;;
      scripts/limit-recover/*/*) want=0 ;;
      scripts/limit-recover/*)   want=1; cls='scripts/limit-recover/*' ;;
      # scripts/lib/*.sh is its own install.sh loop (:475) and must precede the scripts/*/* catch-all
      # that would otherwise swallow it — the ordering hazard this block's first note names.
      scripts/lib/*/*)           want=0 ;;
      scripts/lib/*.sh)          want=1; cls='scripts/lib/*.sh' ;;
      # scripts/lib/*.py — the THIRD instance of the defect the note below records, and the first
      # where NEITHER side had the class. There, an auditor lagged an installer. Here install.sh's
      # scripts/lib loop globbed *.sh ONLY, so when pty-run.py landed in that same directory on
      # 2026-08-08 (769ea1fca82f, on trunk) the installer never linked it and this leg scored it
      # want=0 via the scripts/*/* catch-all — and :508's `[ "$want" = 1 ] || continue` skips a
      # want=0 path in BOTH directions, so neither check could see it. Two siblings agreed over an
      # absence because both were keyed on the same EXTENSION: an auditor built to mirror the
      # deployer 1:1 catches the deployer's DRIFT but never its OMISSION.
      #
      # MEASURED 2026-08-24 (backlog 70cc9f44040f's generalisation clause, made concrete): 11 of 12
      # files in scripts/lib were live and pty-run.py had been absent for 16 days. The LIVE
      # scripts/lib/cloud-create.sh resolves CC_CLOUD_PTY_RUN against its OWN source dir (:125), so
      # it computed $HOME/.claude/scripts/lib/pty-run.py and its fail-CLOSED guard at :190 returned
      # "refused-harness  no pty allocator at …" without ever reaching the binary — for every
      # scheduled cloud create, since com.chrisren.autonomy-sweep.plist and com.claude.dispatcher
      # .plist both export CC_FIRE_CLOUD=on. Fail-closed was the right polarity and still invisible:
      # the refusal is a classification a scheduled caller consumes, not a page a human reads.
      # want=1 here is also what re-arms link_refresh() over the class, exactly as below.
      scripts/lib/*.py)          want=1; cls='scripts/lib/*.py' ;;
      # scripts/backlog-consolidation/*.py — SAME ordering hazard as scripts/lib above, and it bit.
      # install.sh gained this class on 2026-08-12 (6d96bf560) but this auditor did not, so the two
      # disagreed about the same population: the installer wanted the files live, the assert scored
      # them want=0 via the catch-all below and reported PARITY OK over their absence. That is the
      # divergence memory `sibling-auditors-must-share-the-state-model` names, and here it had a
      # second cost — `link_refresh()` repairs exactly the assert's own MISSING lines, so it is the
      # ONE mechanism that can install a new class WITHOUT an advance, and a want=0 verdict silently
      # disabled it. deploy-live then short-circuits at "at trunk tip — nothing to deploy" and never
      # re-runs install.sh either, so the class could not reach the live layer by ANY path until an
      # unrelated commit happened to land. Measured: `bash ~/.claude/scripts/backlog-grouping-sweep.sh`
      # answered "no grouper at …/backlog-consolidation/group.py (fail-open)" with rc 0.
      # .py, not .sh: this directory's executables are Python (install.sh globs it accordingly).
      scripts/backlog-consolidation/*/*)  want=0 ;;
      scripts/backlog-consolidation/*.py) want=1; cls='scripts/backlog-consolidation/*.py' ;;
      scripts/*/*)               want=0 ;;   # scripts/ is globbed top-level only
      # scripts/*.py — a class the MAP does not deploy, DECLARED here rather than left to the
      # catch-all. install.sh's scripts/ leg globs scripts/*.sh ONLY, so the 25 top-level .py files
      # (measured 2026-08-31) match neither scripts/*/* nor scripts/*.sh and fell through to
      # `*) want=0` below — the same silent default that hid hooks/*.py, scripts/lib/*.py,
      # scripts/backlog-consolidation/*.py and bin/ms365-* until each one bit, each recorded above.
      # The want=0 VERDICT is correct; the missing part was the reason. The harm is REFUTED, not
      # merely unmeasured: the consumer census over these paths counted DOCUMENTATION, and the one
      # live consumer resolves through its own symlink back into the checkout and answers rc 0.
      # So this is an exclusion carrying its reason, NOT a step towards widening the deploy — do not
      # add scripts/*.py to install.sh on the strength of this arm.
      scripts/*.py)              want=0 ;;
      scripts/*.sh)              want=1; cls='scripts/*.sh' ;;
      # bin/desk-* is a SEPARATE glob in install.sh:621, added because the cc-* glob does not cover
      # it and nothing else linked it: ~/.claude/bin/desk-register did not exist at all while
      # commands/desk.md's first step invoked it.
      # bin/ms365-* is the THIRD family to arrive this way (2026-08-31). bin/ms365-reply-splice.py
      # landed 2026-08-25 and matched neither glob, so it fell to the `*) want=0` default below and
      # was scored NOT-EXPECTED-LIVE — the same silent disabling this leg's backlog-consolidation
      # comment describes twenty lines up. It existed on trunk and in NO live location, while the
      # live enforce-email-formatting.py hook told the model to run it at RECIPE step 3c.
      # These arms and install.sh's glob list are ONE enumeration written in two files;
      # tests/ms365-reply-splice.bats derives the families from install.sh and asserts every one of
      # them is claimed here, so the next family cannot land in only one of the two again.
      bin/cc-*/*|bin/desk-*/*|bin/ms365-*/*) want=0 ;;
      bin/cc-*)                  want=1; cls='bin/cc-*' ;;
      bin/desk-*)                want=1; cls='bin/desk-*' ;;
      bin/ms365-*)               want=1; cls='bin/ms365-*' ;;
      skills/*/*/*)              want=0 ;;   # install.sh links skills/<name>/<file>, one level only
      skills/*/*)                want=1; cls='skills/*/*' ;;
      # Root-config SSOTs, each its own install.sh line (:436, :445) rather than a loop. accounts.json
      # is deliberately ABSENT: install.sh:428 links it, but it is gitignored (it holds real email
      # addresses), so it can never appear in a tracked-file listing and asserting it here would
      # demand a link over a file this leg cannot see.
      model-config.yaml|providers.json) want=1; cls='root SSOT (link)' ;;
      # vendor/ is a DIRECTORY-link class, deliberately not per-file (install.sh:546 — a per-file
      # loop "would silently fail to link every BRAND-NEW file on the next re-vendor"). Handled by
      # its own loop below; per-file demands here would contradict install.sh outright.
      vendor/*)                  want=0 ;;
      # ── SECOND INSTALLER ── a class install.sh does not deploy because ANOTHER installer does.
      # MEASURED 2026-08-31 by method 238. #264 scored the DETECTOR against install.sh and #265
      # scored THIS FILE against it, but BOTH auditors derive their populations FROM install.sh, so
      # neither can see a class install.sh itself omits (memory: positive-control-the-denominator).
      # Scored instead against the independent population `git ls-files`: install.sh's 19 globs plus
      # its 18 literal installs deploy 629 of 2,247 tracked files, and the residue names a SECOND
      # AUTHOR. scripts/kitty-setup.sh links six bin/ files into $CFG/bin ITSELF (:216, :220, :225,
      # :236-238) and compiles bin/kitty-pane-menu-native.swift into $CFG/bin (:245). install.sh
      # RUNS it (:1204-1215) but never enumerates its classes, and neither auditor names it at all.
      #
      # THE CITATION IS ONE-WAY, and that is why this stayed invisible. kitty-setup.sh:218-220 knows
      # about install.sh and says so — "install.sh's bin/cc-* glob also deploys it … ln -sfn makes
      # the overlap a no-op" — while nothing points back. So these targets sat in the gap between
      # THREE gates, each correct in its own terms: the STRAY leg excludes symlinks and defers to
      # the forward walk (config/live-only.manifest's "NOT COVERED, DELIBERATELY" clause), the
      # forward walk's class set comes from install.sh, and this block scored them at the reasonless
      # `*) want=0` below. #265 found a class dropped by TWO gates; this is one dropped by THREE,
      # where the third gate explicitly hands responsibility to the first.
      #
      # want=0 AND NOT want=1, deliberately: kitty-setup.sh is CONDITIONAL — it runs on kitty hosts
      # only — so demanding these links anywhere else would be wrong, and link_refresh() would mint
      # them where nothing wants them. This is a DECLARATION, not a step toward widening the deploy.
      # The cost it makes visible is real and stays: being want=0, link_refresh() can never restore
      # one, so a deleted ~/.claude/bin/kitty-pane-menu is repaired by nothing and reported by
      # nothing, where a deleted bin/cc-* is relinked automatically. That asymmetry is now written
      # down instead of being a silent property of a default. The COMPILED artifact
      # bin/kitty-pane-menu-native is already declared from the other side, by
      # config/live-only.manifest's build row naming kitty-setup.sh as its producer.
      # tests/deploy-parity.bats derives kitty-setup.sh's targets from its own `ln -sfn` lines and
      # asserts each one is claimed-or-declared here, so a seventh target cannot land silently.
      bin/it2-kitty|bin/kitty-*)  want=0 ;;
      # ── NOT-PER-FILE ── install.sh classes deliberately NOT deployed as per-file links into $CFG.
      # MEASURED 2026-08-31 by method 236 pointed at this file — #264 ran the same method against the
      # DETECTOR (scripts/deploy-link-parity.sh) and this is the REPAIRER, the holder nobody had
      # measured. install.sh globs 19 deploy classes; this block CLAIMED 16, declined vendor/ with a
      # stated reason, and these two fell to the REASONLESS `*) want=0` below. Both verdicts were
      # already CORRECT — no outage is being repaired here. The reasonless want=0 is itself the
      # defect: it is indistinguishable from the oversight that hid four earlier classes in this very
      # block, and an omission carries no reason while a declaration does.
      #   githooks/*       install.sh COPIES these into <repo>/.git/hooks and ~/.git-template/hooks
      #   launchd/*.plist  install.sh COPIES these into ~/Library/LaunchAgents
      # Neither destination is $CFG/<rel>, so demanding a per-file link here would be WRONG rather
      # than merely noisy. These two arms are also unreachable from THIS walk today — the _tracked
      # pathspec above lists neither directory — and that is precisely why they are written down:
      # the exclusion now holds at BOTH gates instead of resting on the input filter alone.
      # tests/deploy-parity.bats derives install.sh's class list from install.sh's own for-headers
      # and asserts every class lands in EXACTLY ONE of claimed-or-declared, so neither a new class
      # nor a deleted arm can drift into an accident. Same shape, and the same reason, as
      # scripts/deploy-link-parity.sh's NOT-PER-FILE block.
      githooks/*)                want=0 ;;
      launchd/*.plist)           want=0 ;;
      # ── LITERAL INSTALLS ── install.sh's SINGLETON deploy sites, as opposed to its glob loops.
      # MEASURED 2026-09-01 by method 246 pointed at the two coverage ARMS rather than at this
      # block. Both of them — tests/deploy-parity.bats's CLASS COVERAGE arm and
      # tests/deploy-link-parity.bats's forward-walk arm — build their map from install.sh's
      # `for … in "$REPO_DIR"/…` LOOP HEADERS, and both say so in their own comments. So the map
      # is install.sh's 19 GLOBS, and install.sh's LITERAL link_file/copy_file calls are in
      # NEITHER coverage population. This file's own line 556 already counts them as a separate
      # population ("its 19 globs plus its 18 literal installs"), which is the tell: the file knew
      # about a second enumeration that no arm gated.
      # Measured: 8 literal-source sites, of which githooks/pre-commit was already declared above,
      # model-config.yaml and providers.json are CLAIMED as root SSOTs, and the five below fell to
      # the REASONLESS `*) want=0`. All eight verdicts were already CORRECT and all eight
      # destinations were correctly deployed at 2026-09-01T02:41Z — no outage is being repaired
      # here, exactly as with githooks/launchd above. The reasonless want=0 is the defect, for the
      # same reason it was there: an omission carries no reason while a declaration does, and this
      # is the population in which bin/ms365-reply-splice.py's silent NOT-EXPECTED-LIVE would
      # recur without any arm going red.
      #   accounts.json          install.sh:537 LINKS it, but it is GITIGNORED (real email
      #                          addresses), so the _tracked walk feeding this case can never
      #                          emit it — the reason already written at the root-SSOT arm above,
      #                          now holding at the gate instead of only in prose beside it.
      #   statusline.sh          install.sh:807 COPIES it to $CFG/statusline.sh — the COPY leg's
      #   bin/it2-wrapper        install.sh:814 COPIES it to $CFG/bin/it2, a RENAMED destination.
      #                          Both are scored under COPYMISS/COPYSTALE, deliberately not the
      #                          `MISSING: ln -sf` shape link_refresh() consumes.
      #   bin/claude-accounts    install.sh:477 and :501 link these into $HOME/bin, which is NOT
      #   bin/dia-cdp-launch.sh  under $LIVE at all, so a per-file demand here would be WRONG
      #                          rather than noisy. tests/deploy-parity.bats's HOME/bin CLAIM
      #                          COVERAGE arm is what owns that surface.
      # tests/deploy-parity.bats now derives this population from install.sh's own link_file /
      # copy_file call sites — a THIRD extractor, deliberately not the for-header one — and asserts
      # every literal source lands in claimed-or-declared, so a ninth literal install cannot land
      # in only one of the two files again.
      accounts.json)             want=0 ;;
      statusline.sh)             want=0 ;;
      bin/it2-wrapper)           want=0 ;;
      bin/claude-accounts|bin/dia-cdp-launch.sh) want=0 ;;
      # ── RAW INSTALLS ── install.sh's THIRD deploy mechanism: a bare `run ln` / `run cp` that
      # calls NEITHER link_file NOR copy_file.
      # MEASURED 2026-09-01 by method 247 pointed at the remedy method 246 had just landed. That
      # remedy added a THIRD extractor to tests/deploy-parity.bats keyed on install.sh's singleton
      # `link_file`/`copy_file` call sites — and a key on TWO VERB NAMES is itself a shape claim, so
      # it inherited a blind spot of exactly the kind it exists to close. install.sh places bytes
      # THREE ways, not two: 19 `for … in "$REPO_DIR"/…` globs · 8 singleton link_file/copy_file
      # literals · and 3 RAW `run ln`/`run cp` sites, which partition 1/1/1 by their SOURCE:
      #   install.sh:776  "$vsrc"                        loop-driven, and its for-header IS one of
      #                   the 19 — so this one is reachable from the existing map.
      #   install.sh:797  "$REPO_DIR/CLAUDE.md"          namable in the very units both extractors
      #                   use, and in NEITHER population. It reached the reasonless `*) want=0`
      #                   below AND is absent from the _tracked pathspec above: dropped by BOTH
      #                   gates, the same three-gate shape as the kitty-setup.sh block.
      #   install.sh:703  "$HOME/.claude/scripts/restore-file.sh" → "$HOME/bin/restore-file"
      #                   a LIVE-PATH source, so it is not namable in $REPO_DIR units AT ALL and no
      #                   extractor keyed on $REPO_DIR can ever produce it, whatever its verb. That
      #                   is the sharper half: a shape the map cannot express is one no member of
      #                   the population can ever demonstrate.
      # The want=0 verdict is CORRECT and UNCHANGED — install.sh:797 COPIES CLAUDE.md to
      # $CFG/CLAUDE.md as a REAL file deliberately (its own comment: "a symlink into the repo would
      # break across branch switches"), so a `MISSING: ln -sf` demand here would be WRONG rather
      # than merely noisy. This arm is also unreachable from THIS walk today, exactly as the
      # githooks/launchd pair is, and that is precisely why it is written down: the exclusion now
      # holds at BOTH gates instead of resting on the input filter alone.
      # No outage is being repaired. Both destinations were read individually at 2026-09-01T03:16Z:
      # ~/.claude/CLAUDE.md is a real file byte-identical to the repo copy and ~/bin/restore-file is
      # a symlink to the live script. This closes a DETECTOR gap, as githooks/*, launchd/*.plist and
      # the literal installs each did before it.
      # tests/deploy-parity.bats derives this population from install.sh's own `run ln`/`run cp`
      # lines — a FOURTH extractor, keyed on the SHAPE of a byte-placing line rather than on either
      # verb name — and asserts both partitions SUM, so a raw deploy of a new shape cannot land
      # silently in only one of the two files again.
      CLAUDE.md)                 want=0 ;;
      *)                         want=0 ;;
    esac
    [ "$want" = 1 ] || continue
    # Recorded BEFORE any verdict below, so every want=1 path is claimed however it is scored —
    # LINKED, PENDING, MISSING or NOVERDICT alike. A path claimed here can never also be swept as
    # an ORPHAN, which is what stops one file producing a prune AND a relink in the same tick.
    _claimed="$_claimed $rel"
    case "$rel" in
      */*) _odirs="$_odirs ${rel%/*}" ;;
      *)   _odirs="$_odirs ." ;;        # a root SSOT — its directory is the live root itself
    esac
    # ── root SSOTs: EXISTENCE IS NOT ENOUGH (2026-08-12, consolidation audit 02 / b13787e71c9f) ──
    # Every other class here asks "is there a live counterpart?", and for a per-file surface of
    # hundreds that is the right question: the failure class is a BRAND-NEW tracked file nobody
    # linked. The two root SSOTs fail the other way. `model-config.yaml` is the file the audit found
    # split-brained — a 36 KB REAL file at ~/.claude/model-config.yaml carrying the whole Opus 5
    # activation, drifting for four days against a repo copy that claimed SSOT and that no consumer
    # read. §5's prescribed fix was three parts: one versioned file, an install.sh link, "and add a
    # drift assert so the split cannot silently recur". The first two landed; this is the third, and
    # its absence was measurable: the class was already NAMED `root SSOT (link)` while `-e` follows
    # a symlink, so a real, drifted live file scored `ok  root SSOT (link)  2 tracked · 2 live · 0
    # missing`, exit 0. The assert nearest the failure reported parity over it.
    #
    # Scoped to this class deliberately, not widened to every class above: a symlink CANNOT drift,
    # so link-ness is the property that makes the SSOT claim true, and install.sh (:445, :454) links
    # exactly these two by `link_file`. The verdict vocabulary is the strict-tools leg's, unchanged
    # (LINKED / UNLINKED / STALE) — a copy that matches TODAY is still drift, because it will
    # diverge on the next repo edit and nothing would say so. That is the audit's whole finding.
    #
    # PENDING is checked BEFORE the verdict, not after: `20-model-config-ssot-activate.sh` is the
    # staged, un-run operator step that performs precisely this swap, and it is C10 (mutates the
    # live layer). Convicting the live host for obeying a design that is waiting on the operator is
    # the false-RED this leg already learned once (see pending_owner's own scar above).
    if [ "$cls" = 'root SSOT (link)' ] && [ -e "$LIVE/$rel" ]; then
      _lt=""
      if [ -L "$LIVE/$rel" ]; then
        _lt="$(readlink "$LIVE/$rel")"
        case "$_lt" in /*) ;; *) _lt="$(dirname "$LIVE/$rel")/$_lt" ;; esac
        _lt="$(cd "$(dirname "$_lt")" 2>/dev/null && pwd)/$(basename "$_lt")"
      fi
      if [ "$_lt" = "$REPO/$rel" ]; then
        cls_row "$cls" live
        continue
      fi
      _act="$(pending_owner "$rel")"
      if [ -n "$_act" ]; then
        report "PENDING" "$rel" "live copy is not the link YET — staged: $_act"
        cls_row "$cls" pending
        pending=$((pending + 1))
        continue
      fi
      same_file "$REPO/$rel" "$LIVE/$rel"
      case $? in
        0) report "UNLINKED" "$rel" "live copy matches but must be a symlink → run ./install.sh"
           cls_row "$cls" drift; drift=1 ;;
        1) report "STALE" "$rel" "live copy DIFFERS from the repo SSOT — split-brain is ACTIVE → run ./install.sh"
           cls_row "$cls" drift; drift=1 ;;
        *) report "NOVERDICT" "$rel" "diff could not run (3 tries) — no claim either way"
           cls_row "$cls" live; noverdict=1 ;;
      esac
      continue
    fi
    # -e follows symlinks on purpose: a link whose target is gone is as dead as no link at all.
    if [ -e "$LIVE/$rel" ]; then cls_row "$cls" live; continue; fi
    # Unlinked BY DESIGN while its staged activation is un-run — reported, never counted as drift.
    _act="$(pending_owner "$rel")"
    if [ -n "$_act" ]; then
      report "PENDING" "$rel" "unlinked BY DESIGN — staged: $_act"
      cls_row "$cls" pending
      pending=$((pending + 1))
      continue
    fi
    printf 'MISSING: ln -sf %s %s\n' "$REPO/$rel" "$LIVE/$rel"
    cls_row "$cls" miss
    missing=$((missing + 1))
    drift=1
  done <<EOF
$_tracked
EOF

  # ── vendor/<plugin>/ — ONE DIRECTORY symlink per plugin, never per-file ────────────────────────
  # install.sh:546-565 links the DIRECTORY (`ln -sfn $REPO/vendor/<n> $LIVE/vendor/<n>`) precisely so
  # a re-vendor cannot leave new files unlinked. Emitting `ln -sf` here rather than `ln -sfn` is
  # correct and NOT a divergence: deploy-live's link_refresh only ever acts on a dest that failed
  # `-e`, and with no existing dest the two spellings are identical. `-n` matters only when the dest
  # is already a dir symlink being RE-pointed, which is exactly the non-monotone case this leg never
  # reports and link_refresh never performs.
  # Derived from the tracked listing (not a `vendor/*/` glob) so an untracked scratch dir under
  # vendor/ can never manufacture a demand — the same subject discipline as every leg above.
  _vseen=""
  while IFS= read -r rel; do
    case "$rel" in vendor/*/*) ;; *) continue ;; esac
    _vn="${rel#vendor/}"; _vn="${_vn%%/*}"
    [ -n "$_vn" ] || continue
    case " $_vseen " in *" $_vn "*) continue ;; esac
    _vseen="$_vseen $_vn"
    if [ -e "$LIVE/vendor/$_vn" ]; then cls_row 'vendor/*/ (dir link)' live; continue; fi
    _act="$(pending_owner "vendor/$_vn")"
    if [ -n "$_act" ]; then
      report "PENDING" "vendor/$_vn" "unlinked BY DESIGN — staged: $_act"
      cls_row 'vendor/*/ (dir link)' pending
      pending=$((pending + 1))
      continue
    fi
    printf 'MISSING: ln -sf %s %s\n' "$REPO/vendor/$_vn" "$LIVE/vendor/$_vn"
    cls_row 'vendor/*/ (dir link)' miss
    missing=$((missing + 1))
    drift=1
  done <<EOF
$_tracked
EOF

  # ── ORPHAN: the live link whose repo source was DELETED (backlog 456d5c61f4c8) ─────────────────
  # THE FORWARD WALK CANNOT SEE THIS CLASS, BY CONSTRUCTION, and that is the whole finding. Every
  # leg above iterates the TRACKED listing and asks "is there a live counterpart?". A file DELETED
  # from the repo leaves that listing, so the walk never visits it again — while its live symlink
  # survives, still resolving for `command -v` and then failing with ENOENT at exec. Nothing on the
  # machine reported it: this assert had no converse leg, and deploy-live.sh consumes this assert.
  #
  # Measured 2026-08-23 on the operator's live layer — TWO orphans, both from ordinary deletions:
  # ~/.claude/bin/cc-cloud-watch (source deleted by 799c3282a) and ~/.claude/bin/browsermcp-wrapper.sh
  # (deleted by 47cc3f279). The second is the one that matters for triage: it was minted FOUR DAYS
  # AFTER the row was filed, so this is a live generator, not a one-off residue.
  #
  # WHY THE SCOPE IS DERIVED, NOT LISTED. scripts/deploy-link-parity.sh already carries a correct
  # sweep_orphans() (landed 2026-08-08, one day after the row) — and it is a detector with no owner:
  # census 2026-08-23 found ZERO execution sites for that script anywhere in scripts/, bin/, hooks/,
  # launchd/ or settings.json, so its verdict has never once reached the live layer. Porting its
  # hardcoded directory list here would have re-created the "two auditors over one population with
  # different state models" divergence this file has already paid for twice (see the
  # backlog-consolidation note above, and pending_owner's scar). Instead the sweep visits exactly
  # the directories the want-list populated on THIS run, so a class added above gains orphan
  # coverage with no edit here and the two directions cannot drift apart.
  #
  # THE PRICE, STATED RATHER THAN HIDDEN: a directory whose LAST tracked file was deleted
  # contributes no rel, so it is not swept. That is a real hole and it is the correct one to accept
  # — the alternative is the second list.
  #
  # WHAT THIS MAY CLAIM IS DELIBERATELY NARROW, because the consumer DELETES. Three conditions, all
  # required: it is a SYMLINK (a real file is deploy-link-parity's STRAY question, a different
  # remedy), it does NOT RESOLVE (so the path is already inert — removing it cannot break a caller
  # that works today), and its target is INSIDE THIS CHECKOUT (a link into someone else's tree is
  # explicitly not ours to judge, same scope clause deploy-link-parity.sh:49 states). Unquoted
  # $_odirs word-splitting is safe here for the same reason link_refresh's field-splitting is:
  # tracked runtime paths are space-free by contract.
  _oseen=""
  for _od in $_odirs; do
    case " $_oseen " in *" $_od "*) continue ;; esac
    _oseen="$_oseen $_od"
    if [ "$_od" = "." ]; then _odir="$LIVE"; else _odir="$LIVE/$_od"; fi
    [ -d "$_odir" ] || continue
    for _l in "$_odir"/*; do
      # NO MUTANT CAN RED THIS LINE ALONE, and that is a property of the input space, not a gap in
      # the suite: a real file passes `-e` and a non-matching glob literal fails the $REPO scope
      # check, so the two guards below already decide every reachable case. It stays because it is
      # the primary statement of what this leg may claim, and its consumer deletes — but it is
      # defence in depth, not a discriminating guard, and calling it "covered" would be false.
      [ -L "$_l" ] || continue                              # real file ⇒ STRAY's question, not ours
      [ -e "$_l" ] && continue                              # it RESOLVES ⇒ healthy ⇒ never claimed
      _orel="${_l#"$LIVE"/}"
      case " $_claimed " in *" $_orel "*) continue ;; esac  # the forward walk owns it (it is a MISS)
      _ot="$(readlink "$_l")"
      case "$_ot" in "$REPO"/*) ;; *) continue ;; esac      # points elsewhere ⇒ not ours to judge
      printf 'ORPHAN: rm -f %s\n' "$_l"
      report "ORPHAN" "$_orel" "live link → deleted repo source; resolves to nothing"
      orphans=$((orphans + 1))
      drift=1
    done
  done
fi
if [ "$orphans" -ne 0 ]; then
  printf '\ndeploy-parity-assert: %s live symlink(s) under %s point at a repo source that no longer exists.\n' "$orphans" "$LIVE" >&2
  printf 'Each still resolves for command -v and then fails with ENOENT at exec. Run the rm -f lines\n' >&2
  printf 'above, or let deploy-live.sh prune them on its next tick (it re-derives the predicate itself).\n' >&2
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

# ── FOURTH LEG: COPY CLASSES — what install.sh deploys by cp, never by ln ───────────────────────
# The existence leg above asserts SYMLINK classes and hands each miss to deploy-live's link_refresh
# as a literal `ln -sf`. Five install.sh classes are COPIES, and for them that remedy is not merely
# unhelpful, it is the bug: install.sh:289 records that githooks shipped as symlinks for six hours
# and calls it "a critical bug" — a link into the working tree dangles on any branch switch in the
# shared checkout, and git fails OPEN on a dangling hook, so the gate silently stops existing. So
# these are reported under their OWN verdict tokens and are DELIBERATELY never emitted as
# `MISSING: ln -sf`: the tick-driven repairer must not be able to convert a copy class into a link.
# Their remedy is ./install.sh, at operator cadence, which is where it already lives.
#
# What that costs, stated plainly: these classes get DETECTION, not tick-driven repair. That is the
# honest half of P6 — the advance-gated converger still owns them — and it is a strict improvement
# on the prior state, where they had neither.
#
# Seams (all fixture-drivable, all "set-but-EMPTY ⇒ skip this class" so a non-global or alt-config
# deployment can turn off a class that does not apply to it rather than read a false miss):
#   CC_PARITY_GITHOOKS — colon-separated hook dirs (default: the checkout's own + ~/.git-template)
#   CC_PARITY_LAUNCHD  — LaunchAgents dir (default: ~/Library/LaunchAgents)
# ── WHICH SIDE IS AHEAD — the question "DIFFERS" does not answer, and the one the REMEDY needs ────
# MEASURED 2026-08-24. deploy-live reported "2 copy-class file(s) DIFFER from this checkout —
# CLAUDE.md launchd/*.plist" as ONE condition with ONE remedy (run install.sh). Inspected, the two
# drifted OPPOSITE ways: the plist's checkout was ahead and live stale (repair correct), while for
# CLAUDE.md the LIVE file was ahead by an operator-authored rule that had never been tracked — and
# install.sh copies repo→live unconditionally, so the prescribed repair would have SILENTLY DELETED
# it. `diff` answers "are these the same", never "which one is the original", so every caller that
# turned a difference into "repo edits are NOT live" was asserting a direction it had not measured.
#
# THE DISCRIMINATOR IS GIT, and it is the only thing on hand that knows what the file HAS been.
# Hash the LIVE bytes and ask whether that blob appears anywhere in the tracked path's history:
#   reachable   ⇒ live is a PAST revision of this file — genuinely BEHIND, and repair is safe.
#   unreachable ⇒ repo→live would REGRESS the live layer, so it must not wear staleness's token.
#
# READ `ahead` EXACTLY: "these bytes are not in THIS CHECKOUT'S history", which is narrower than
# "never tracked anywhere". It covers two states, and lumping them would repeat this row's own
# mistake, so say both: (1) UNLANDED EDITS — someone edited the live copy and never landed it (the
# CLAUDE.md case above); (2) A NEWER LANDED REVISION the checkout has not fetched — real on this
# machine, because deploy-live deliberately runs from the newest GREEN commit while trunk moves on,
# so the live layer can legitimately be ahead of the checkout asking the question. Verified both
# 2026-08-24 against the live pair. They differ in remedy — land the edits vs. fetch the checkout —
# but they agree on the only thing this token has to protect: do NOT copy repo→live over it.
#
# A file that is both behind AND locally edited also matches nothing, so it reports `ahead` — again
# the safe direction, because the claim that matters is "do not blindly copy over this".
#
# THREE PROCESSES REGARDLESS OF HISTORY DEPTH: one `log` to name every commit that touched the path,
# piped into ONE `cat-file --batch-check` to resolve them all. The naive shape (a `rev-parse` per
# commit) forks once per commit and this runs on files with hundreds.
#
# `grep -c`, NEVER `grep -q`: this file is `set -o pipefail`, and an early-exiting consumer SIGPIPEs
# `cat-file`, so the pipeline would report FAILURE on exactly the input it just matched.
#
# FAILS TO `unknown`, never to a direction. No git, an untracked path, an unreadable file — each
# means we cannot say which side is original, and the caller must then warn rather than prescribe.
copy_direction() {   # <repo src> <live dest> → behind | ahead | unknown. Never fails, never mutates.
  local src="$1" dest="$2" rel h hits
  case "$src" in "$REPO"/*) rel="${src#"$REPO"/}" ;; *) printf 'unknown'; return 0 ;; esac
  command -v git >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  [ -r "$dest" ] || { printf 'unknown'; return 0; }
  h="$(git -C "$REPO" hash-object -- "$dest" 2>/dev/null || true)"
  case "$h" in ''|*[!0-9a-f]*) printf 'unknown'; return 0 ;; esac
  git -C "$REPO" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  # NO COMMITS ⇒ UNKNOWN, never `ahead`. A path can be TRACKED (staged) yet have no history at all —
  # a fresh checkout, a file added but not yet committed. Git then knows nothing about what this file
  # HAS been, and "no past revision matches" would be an artefact of an empty search space rather
  # than a finding. Reporting `ahead` there would fire the loud branch on every such file.
  local commits
  commits="$(git -C "$REPO" log --format="%H:$rel" -- "$rel" 2>/dev/null || true)"
  [ -n "$commits" ] || { printf 'unknown'; return 0; }
  hits="$(printf '%s\n' "$commits" \
            | git -C "$REPO" cat-file --batch-check='%(objectname)' 2>/dev/null \
            | grep -cxF "$h" 2>/dev/null || true)"
  case "$hits" in ''|*[!0-9]*) hits=0 ;; esac
  if [ "$hits" -gt 0 ]; then printf 'behind'; else printf 'ahead'; fi
  return 0
}

copy_verdict() {   # <label> <src> <dest> — reports, sets drift/noverdict. Never emits an ln -sf line.
  local label="$1" src="$2" dest="$3"
  [ -f "$src" ] || return 0                 # not in this checkout ⇒ nothing to assert
  if [ ! -e "$dest" ]; then
    report "COPYMISS" "$label" "deployed by cp, and it is NOT there → run ./install.sh"
    cls_row "$label" miss; drift=1; return 0
  fi
  same_file "$src" "$dest"
  case $? in
    0) cls_row "$label" live ;;
    1) case "$(copy_direction "$src" "$dest")" in
         behind)
           report "COPYSTALE" "$label" "copy DIFFERS from repo — repo edits are NOT live → run ./install.sh" ;;
         ahead)
           # A DIFFERENT CONDITION WITH A DIFFERENT REMEDY, so it gets its own token. install.sh
           # copies repo→live, so prescribing it here is prescribing the deletion.
           report "COPYAHEAD" "$label" "the LIVE copy carries bytes NOT in this checkout's history (unlanded live edits, or a newer landed revision this checkout has not fetched) — install.sh copies repo->live and would REGRESS it → land the live edits or fetch this checkout FIRST" ;;
         *)
           report "COPYSTALE" "$label" "copy DIFFERS from repo, direction UNKNOWN (git could not answer) — verify which side is original BEFORE running ./install.sh" ;;
       esac
       cls_row "$label" miss; drift=1 ;;
    *) report "NOVERDICT" "$label" "diff could not run (3 tries) — no claim either way"
       cls_row "$label" live; noverdict=1 ;;
  esac
  return 0
}
copy_verdict 'statusline.sh'   "$REPO/statusline.sh"   "$LIVE/statusline.sh"
copy_verdict 'bin/it2-wrapper' "$REPO/bin/it2-wrapper" "$LIVE/bin/it2"

# githooks/ — dest is the CHECKOUT'S OWN hook dir plus the clone template, neither of them under
# $LIVE, so this class breaks the "$LIVE/<same rel>" invariant twice over. install.sh's foreign-hook
# rule is mirrored exactly: a hook that is NOT ours (no content marker) is left alone by install.sh,
# so demanding parity over it would be a false demand this script could never satisfy.
GITHOOK_DIRS="${CC_PARITY_GITHOOKS-}"
if [ -z "${CC_PARITY_GITHOOKS+set}" ]; then
  _ghc="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$_ghc" ] && GITHOOK_DIRS="$_ghc/hooks"
  GITHOOK_DIRS="${GITHOOK_DIRS:+$GITHOOK_DIRS:}$HOME/.git-template/hooks"
fi
_gh_ours() { grep -q 'cc-git-identity-gate\|commit-msg — reject' "$1" 2>/dev/null; }
_gh_one() {   # <src> <dest>
  if [ -e "$2" ] && ! _gh_ours "$2"; then
    report "FOREIGN" "githooks/*" "$2 is a foreign hook — install.sh leaves it alone, so neither do we"
    return 0
  fi
  copy_verdict 'githooks/*' "$1" "$2"
}
if [ -n "$GITHOOK_DIRS" ] && [ -d "$REPO/githooks" ]; then
  _rest="$GITHOOK_DIRS"
  while [ -n "$_rest" ]; do
    _d="${_rest%%:*}"; if [ "$_rest" = "$_d" ]; then _rest=""; else _rest="${_rest#*:}"; fi
    [ -n "$_d" ] || continue
    for _gh in "$REPO"/githooks/*; do
      [ -f "$_gh" ] || continue
      _gh_one "$_gh" "$_d/$(basename "$_gh")"
    done
    # pre-merge-commit is pre-commit's body under git's OTHER name for the merge path; without it a
    # `git merge`/`git pull` commit is ungated by hook name alone (install.sh:326).
    [ -f "$REPO/githooks/pre-commit" ] && _gh_one "$REPO/githooks/pre-commit" "$_d/pre-merge-commit"
  done
fi

# launchd/*.plist — COPIES into ~/Library/LaunchAgents. EXISTENCE and CONTENT only: activation is
# manifest-gated (DAEMON_FLEET_V2 §4.1) and is emphatically not this script's business. Nothing here
# calls launchctl, reads the override db, or has any opinion about whether a job is loaded — a
# parity assert that could bootout a daemon would be a far larger hazard than the drift it detects.
LAUNCHD_DIR="${CC_PARITY_LAUNCHD-$HOME/Library/LaunchAgents}"
if [ -n "$LAUNCHD_DIR" ] && [ -d "$REPO/launchd" ]; then
  for _pl in "$REPO"/launchd/*.plist; do
    [ -f "$_pl" ] || continue
    copy_verdict 'launchd/*.plist' "$_pl" "$LAUNCHD_DIR/$(basename "$_pl")"
  done
fi

# ── ~/.claude/CLAUDE.md — the highest-consequence live file, and the last one with no sensor ─────
# It is read as USER MEMORY by every session on this machine, so a divergence changes how every
# agent behaves — and until now nothing measured it. It sat outside all three legs above: the
# existence leg's pathspec never included it, it is a real file rather than a symlink (deliberately:
# a link into the repo would break across branch switches), and the provenance leg says nothing
# about content. §2.E of the P6 investigation recorded it as "no converger and no detection"; the
# tree corrects half of that — install.sh:583-587 DOES have a cp leg — but that leg runs only after
# a successful advance, i.e. it was famine-blocked for the same 601 refusals as everything else.
# So: no TICK-DRIVEN converger, and, until this leg, no detection at all. It was in parity when
# measured only because a session had hand-synced it 34 minutes earlier.
#
# DETECTION ONLY, by explicit decision (P6 brief). Copying it here is refused for a reason that is
# not squeamishness: the DIRECTION is a judgment. The project's own rule is that a land in this repo
# must be followed by hand-applying the same edits to the live file, so a divergence can equally
# mean "the repo advanced" or "the live file holds an edit not yet committed", and a converger that
# guessed would silently destroy operator work in the second case. That makes it genuinely
# operator-owned, which is the only thing that licenses a `needs` row rather than just doing it.
if [ -f "$REPO/CLAUDE.md" ]; then
  if [ ! -e "$LIVE/CLAUDE.md" ]; then
    report "CLAUDEMD" "CLAUDE.md" "the live global instructions are ABSENT → run ./install.sh"
    cls_row 'CLAUDE.md (copy)' miss; drift=1
    # The tilde is PROSE — this string is a sentence an operator reads in a backlog row, not a path
    # anything expands. SC2088 cannot tell those apart; spelling it $HOME here would put a literal
    # /Users/... into the ledger and make the row machine-specific.
    # shellcheck disable=SC2088
    file_need "claude-md-absent" \
      "~/.claude/CLAUDE.md is absent — deploy the global instructions (repo claude-infrastructure/CLAUDE.md); no session is reading them"
  else
    same_file "$REPO/CLAUDE.md" "$LIVE/CLAUDE.md"
    case $? in
      0) cls_row 'CLAUDE.md (copy)' live ;;
      1) report "CLAUDEMD" "CLAUDE.md" "live global instructions DIVERGE from the repo — every session reads the live copy"
         cls_row 'CLAUDE.md (copy)' miss; drift=1
         # Deliberately no sha/count in the title: the trigger is a standing STATE, so the constant
         # title is the condition key (see file_need). A count would mint a new row on every edit.
         file_need "claude-md-diverged" \
           "reconcile ~/.claude/CLAUDE.md with claude-infrastructure/CLAUDE.md — they diverge, and which side is authoritative is your call (diff them; the live copy is what every session actually reads)" ;;
      *) report "NOVERDICT" "CLAUDE.md" "diff could not run (3 tries) — no claim either way"
         cls_row 'CLAUDE.md (copy)' live; noverdict=1 ;;
    esac
  fi
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
    #
    # ⚠️ DO NOT TRY TO "ATTRIBUTE" A RESOLVED-SHA FF AGAINST deploy.log — IT IS NOT AN ATTRIBUTION
    # INSTRUMENT, and reading it as one has now produced a filed bug and a second session's
    # escalation of it. deploy.log is the launchd job's StandardOutPath, and deploy-live.sh has no
    # log wiring of its own (its say() prints to stdout), so deploy.log records `--auto` runs and
    # NOTHING ELSE. A session running the sanctioned converge BY HAND — which validate-bash.sh's own
    # deny message instructs, and which `--force` uses as the documented escape hatch precisely when
    # the auto lane is refusing — writes its `deployed X → Y` line to a terminal that is then gone.
    # Measured on the shared checkout 2026-08-24: 71 resolved-SHA ffs against 43 `deployed` lines,
    # i.e. 28 sanctioned advances this log structurally cannot see. Backlog 7e2e0ab9c358 read that
    # gap as "a NON-deploy-live actor scores GATED, so the leg launders" and asked for the leg to be
    # TIGHTENED before the actor was named. The actor is deploy-live itself, invoked manually;
    # tightening against that population would RED every manual converge. Closed refuted 2026-08-24.
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
      # PRINTING IS NOT SURFACING (2026-08-10, P6). This verdict is the one thing that can see an
      # ungated advance at all — link_refresh cleans up its symptom on a 600s timer, so the cause is
      # invisible everywhere else — and for weeks it did nothing but print into a log, beside 601
      # deploy refusals that also escalated to nobody. Five prior sessions each read "drift at its
      # historical minimum" and closed. A finding that reaches no store reaches no close.
      # Operator-owned because the remedy is a HABIT, not a command: the fix is that sessions stop
      # hand-pulling in the shared checkout (8 of 15 live sessions were cwd'd there, in violation of
      # the project rule). No `--run` is offered — there is no command that repairs this, and the
      # remedy that LOOKS like one (another ff) is the cause. Same rule the remedy block below
      # states: a prescription that undoes the state the script just reported is worse than none.
      file_need "deploy-ungated-advance" \
        "sessions are advancing the shared checkout by hand (a raw git pull/merge outside deploy-live) — that skips the deploy gate AND install.sh, so brand-new tracked files land unlinked and silently do nothing; the fix is that sessions work in their own worktree, not a command to run"
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

# THE CLASS TABLE, rendered last so it summarises everything above it. On stdout, like every other
# report line: deploy-live's link_refresh consumes ONLY lines matching `^MISSING: ln -sf `, so this
# cannot perturb the repair path (a test pins that). It is emitted on EVERY run, including a clean
# one — that is the point. A per-file report says nothing about a class it was never told to
# enumerate, so "no rows for agents/*.md" and "agents/*.md is in parity" looked identical for the
# whole time the 5-of-19 hole was open. A class that is not in this table is a class nothing checks.
cls_table

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
