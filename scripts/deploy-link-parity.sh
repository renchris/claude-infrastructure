#!/bin/bash
# deploy-link-parity.sh — report checkout files that have NO live per-file symlink.
#
# Why: ~/.claude/{hooks,commands,scripts,bin,skills} are REAL directories of PER-FILE symlinks
# into the checkout. A fast-forward therefore updates every file that ALREADY has a link — and
# deploys nothing at all for a file the checkout gained. The new file is landed, current, and
# completely inert, with no signal anywhere:
#   - 2026-07-20 scripts/desk-arm-live.sh was in the checkout and in the ff, but
#     ~/.claude/scripts/desk-arm-live.sh did not exist. The desk-recycle-invariant's own
#     fix-command and the operator's command both died on "No such file or directory".
#   - 2026-07-21 the autofiring lr-reset-poller nearly shipped fail-closed for the same reason.
# `git rev-list HEAD..origin/main` reads 0 in both cases: landed ≠ deployed.
#
# REPORT-ONLY, BY DESIGN — it never creates, removes or repairs a link. A blanket "link every
# unlinked file" would be WRONG: a settings-wired hook is deliberately left unlinked until its
# staged activation script runs (that script does the symlink AND the settings.json wiring as one
# C10 operator step). Auto-linking would strip the only visible signal that the wiring is pending.
# Such files are classified PENDING and are NOT failures; everything else unlinked is.
#
# SCOPE: the per-file SYMLINK surfaces install.sh deploys. The COPY surfaces (~/bin launchers,
# statusline.sh, CLAUDE.md, rules/, launchd/) drift by CONTENT, not by topology, and belong to
# scripts/deploy-parity-assert.sh. The two scripts partition the deployed surface; neither
# duplicates the other.
#
# THE OTHER DIRECTION (2026-08-08) — STRAY: a live REAL FILE that is in no checkout at all. Every
# leg above walks checkout→live, so it can only ever ask "did this landed file get deployed?" and is
# structurally blind to a file that entered the live layer without ever being in the repo:
#   - bin/cc-mail sat live and unversioned for 5 DAYS while this script read "0 actionable"; a peer
#     session working in another repo had hand-placed it into ~/.claude/bin, which is on PATH.
#     bin/cc-thread was the same failure a day earlier. Two occurrences, one blind spot.
# An unversioned executable on PATH is one `rm -rf ~/.claude` from being lost, is invisible to every
# reviewer, and — because ~/.claude/bin is shared by every session — silently becomes a dependency
# of peers that cannot see where it came from.
#
# WHY THIS IS NOT A BARE live→checkout DIFF, which is the trap the item shipped with. The live layer
# legitimately holds real files the checkout does not: ~/.claude/bin/it2 is cp'd from the tracked
# bin/it2-wrapper under a DIFFERENT NAME (install.sh:593). Convicting it would repeat the failure
# this repo has already paid for — a sibling auditor that did not model the design and so convicted
# the live layer for obeying it (memory sibling-auditors-must-share-the-state-model). So the copy-
# deploy state is modelled FIRST and the match is by CONTENT, never by path: a real file whose bytes
# are in ANY tracked file is versioned, whatever it is called. Only what content-matching cannot see
# — a compiled binary, deliberate residue — needs a row in config/live-only.manifest, and each row
# names a witness that must still exist and still mention it, so a dissolved reason FAILS LOUD
# rather than silently exempting (memory discovery-critic-premise-goes-stale).
#
# AND THE THIRD STATE, WHICH IS NEITHER (2026-08-31) — UNCONVERGED: a live real file whose bytes are
# in no INDEX but ARE in the TRUNK REF's tree. The two states above are asked of one checkout, and a
# checkout is not the world: the live symlink source sits behind origin/main for exactly as long as
# a land goes unconverged, so a file landed this morning reads as "in NO checkout — unversioned".
# It is versioned; the reader is behind. Separated because the two states take OPPOSITE remedies —
# a stray wants adopting or deleting, an unconverged file wants the converger and must NOT be
# cp'd/added into a checkout that already has it on trunk. See content_is_on_trunk().
#
# STRAY SCOPE is the EXECUTED surfaces only — bin, hooks, hooks/lib, scripts, scripts/lib,
# scripts/backlog-consolidation, scripts/limit-recover, lib. Measured 2026-08-08, not assumed —
# and scripts/backlog-consolidation was added 2026-09-01, not because anything here was re-argued
# but because the FORWARD walk gained seven classes on 2026-08-31 and this sentence could not see
# that happen. A scope claim is falsified by its siblings growing, so the sweep's list is now pinned
# against the walk's by a test arm rather than by this paragraph (see the NOT-STRAY-SWEPT block).
#   · SYMLINKS are excluded entirely. Links into this checkout are the forward walk's and
#     sweep_orphans' business; a link pointing anywhere else is explicitly not ours to judge
#     (tests/deploy-link-parity.bats:156). Cost of honouring that: a hand-placed link to a non-repo
#     path is missed. The defect that recurred twice was a hand-placed real FILE.
#   · PROMPT-DOCUMENT surfaces: skills/ and agents/ ARE swept as of 2026-08-19; commands/ is not.
#     The exclusion was carried by a wall estimate that measured the wrong span, and the correction
#     runs the OTHER way from the last two: the wall is 5 lines, not 82 and not 20.
#       — 20 was a stale DIRECTORY count (siblings f542c8b2c, 8b33db9e6, ab62d3a08 tracked the rest;
#         5 third-party survivors remain, each with a durable reason in skills/LOCAL_ONLY.md).
#       — 82 corrected the UNIT (this leg reports files, and those 5 dirs hold 82 real files) but
#         counted RECURSIVELY while sweep_strays is non-recursive and skips subdirectories. It
#         visits depth 1 only: exactly 5 real files, one SKILL.md per dir. react-best-practices
#         contributes 1 here, not 59. A span that does not equal its consumer's span is not a
#         measurement of that consumer (memory assertion-span-must-equal-its-subject).
#     So 5 declarations absorb the whole wall and the alarm-polarity objection dissolves rather
#     than strengthening. Depth-1 coverage is also the RIGHT span for the defect class: a skill IS
#     its top-level SKILL.md, so a newly hand-placed unversioned skill is always caught. Nested
#     content inside an already-declared skill is deliberately not audited.
#     agents/ is flat and holds exactly one real file (the Motion plugin's motion-reviewer.md).
#   · DIRECTORIES are skipped (hooks/lib and scripts/lib are structural; __pycache__ is bytecode
#     residue of the *.py hooks). Neither is a hand-placed tool.
#
# Usage:  deploy-link-parity.sh [--all] [--quiet]
#   --all     also list files that ARE correctly linked (default: only findings)
#   --quiet   print nothing when there is nothing actionable (for hooks/cron callers)
# Exit 0 = nothing actionable (PENDING-only still counts as clean) · 1 = actionable gap
#        · 3 = missing prerequisite.
#
# Covered by tests/deploy-link-parity.bats, whose fixtures drive it via CC_LINKPARITY_REPO /
# CC_LINKPARITY_CONFIG / CC_LINKPARITY_BINDIR / CC_LINKPARITY_PENDING / CC_LINKPARITY_MANIFEST /
# CC_LINKPARITY_TRUNK (fully hermetic — no case reads the real ~/.claude or the real checkout).
set -uo pipefail

ALL=false
QUIET=false
while [ $# -gt 0 ]; do
  case "$1" in
    --all)   ALL=true; shift ;;
    --quiet) QUIET=true; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Resolve a path through every symlink hop, then absolutise it. macOS ships bash 3.2 and a
# readlink with no -f, so this is hand-rolled. Load-bearing for BASH_SOURCE below: this script is
# itself deployed AS a symlink (~/.claude/scripts/deploy-link-parity.sh), so an unresolved
# BASH_SOURCE would put the repo root at ~/.claude — not a checkout — and every leg would compare
# against nothing and exit 0 vacuously.
_resolve() {
  local p="$1" t d n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd)" || { printf '%s\n' "$p"; return 0; }
  printf '%s/%s\n' "$d" "$(basename "$p")"
}

if [ -n "${CC_LINKPARITY_REPO:-}" ]; then
  REPO="$CC_LINKPARITY_REPO"
else
  # A linked worktree must compare the CANONICAL checkout (the live symlink source), never
  # itself — live links target the shared checkout, so a self-rooted comparison from a worktree
  # reads every correct link as a finding. --git-common-dir is ".git" in the main checkout and an
  # absolute main-.git path in a linked worktree; outside git, fall back to self.
  _self="$(_resolve "${BASH_SOURCE[0]}")"
  _self_root="$(cd "$(dirname "$_self")/.." && pwd)"
  _common="$(git -C "$_self_root" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$_common" in
    "")  REPO="$_self_root" ;;
    /*)  REPO="$(cd "$_common/.." && pwd)" ;;
    *)   REPO="$(cd "$_self_root/$_common/.." && pwd)" ;;
  esac
fi
CFG="${CC_LINKPARITY_CONFIG:-$HOME/.claude}"
BINDIR="${CC_LINKPARITY_BINDIR:-$HOME/bin}"
# Activation scripts are staged in the repo AND mirrored live (the live dir is where the operator's
# .done markers land). Both are scanned: some staged scripts exist in only one of the two.
PENDING_DIRS="${CC_LINKPARITY_PENDING:-$REPO/docs/activation/pending-activation:$CFG/autonomy/pending-activation}"
MANIFEST="${CC_LINKPARITY_MANIFEST:-$REPO/config/live-only.manifest}"

[ -d "$REPO" ]  || { echo "deploy-link-parity: no checkout at $REPO" >&2; exit 3; }
[ -d "$CFG" ]   || { echo "deploy-link-parity: no config dir at $CFG" >&2; exit 3; }

findings=0
pending_n=0
linked_n=0
extra_n=0
unmapped_n=0
unmapped_scanned=0   # non-vacuity denominator: 0 unmapped is the HEALTHY value, so an enumeration
                     # that resolved nothing must not render as one. See sweep_unmapped below.
LINES=""
FIXES=""
SEEN=""     # repo-relative paths the forward walk claimed; the STRAY leg defers to them
ORPHANED="" # live-relative paths sweep_orphans already reported; the reverse leg defers to them

note() { LINES="${LINES}$(printf '  %-9s %-44s %s' "$1" "$2" "$3")"$'\n'; }
fix()  { FIXES="${FIXES}  ▶ $1"$'\n'; }

# A file is PENDING — deliberately unlinked — when a staged activation script that has NOT been
# marked .done names it. Matched on the REPO-RELATIVE PATH, never the bare basename: an activation
# script must spell the path to build "$REPO/<path>", and loose basename matching would launder a
# genuinely-inert file into a false all-clear (the silent failure direction).
pending_owner() {
  local rel="$1" dir f base rest="$PENDING_DIRS"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    if [ "$rest" = "$dir" ]; then rest=""; else rest="${rest#*:}"; fi
    [ -d "$dir" ] || continue
    for f in "$dir"/*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      # Done-marked activations no longer excuse an unlinked file: the operator ran the script,
      # so a still-missing link is a real failure, not a pending step.
      [ -e "$f.done" ] && continue
      [ -e "$CFG/autonomy/pending-activation/$base.done" ] && continue
      if grep -qF -- "$rel" "$f" 2>/dev/null; then printf '%s\n' "$base"; return 0; fi
    done
  done
  return 0
}

_claimed() {  # $1 = repo-relative path · whole-line membership in the forward walk's own ledger
  # THE ONE READER OF SEEN, and it is a pure-builtin `case` rather than the
  # `printf '%s' "$SEEN" | grep -qxF -- "$rel"` this file carried until 2026-08-31.
  #
  # That spelling is the fail-OPEN pipeline the pipefail ratchet exists to stop, and here the
  # inversion is silent in the WRONG direction: under this file's own `set -uo pipefail`, `grep -q`
  # exits the instant it MATCHES, the producer takes SIGPIPE, pipefail promotes the pipeline's rc to
  # 141, and the `&& continue` that defers to the forward walk never fires — so a path the walk
  # already claimed is classified a SECOND time. That is exactly the double-classification the SEEN
  # ledger was introduced to prevent, and the comment introducing it says so.
  #
  # FEED MEASURED 2026-09-01T00:0xZ ON THE REAL LAYER: SEEN is 12,113 bytes at 458 claimed paths,
  # against a two-stage builtin SAFE floor of 37,121 B (racy from 55,721). So it was LATENT, with
  # about 3.1x of headroom — roughly 1,400 claimed paths. Latent is not safe: SEEN grows with the
  # deployed surface, monotonically, and nothing announces the crossing. The arm pinning "a SHADOW
  # is classified ONCE" was green over the defect for its whole life because its fixture's SEEN is a
  # few hundred bytes; a behavioural arm sized from the measured regime now sits beside it.
  #
  # Defined HERE, above both readers, not beside its second one: bash resolves a function at CALL
  # time, so a definition below sweep_strays would be `command not found` on every real run while
  # every fixture whose forward walk claims nothing stays green.
  case $'\n'"$SEEN" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

_orphaned() {  # $1 = live-relative path · whole-line membership in sweep_orphans's own ledger
  # The SECOND deferral ledger in this file, and it exists for the same reason as the first: two
  # legs now sweep for a dangling link, so without a claim the one link is classified TWICE.
  #
  # Same pure-builtin `case` as _claimed — never `printf '%s' "$ORPHANED" | grep -qxF`, which is the
  # fail-OPEN pipeline drained from this file on 2026-08-31: under `set -uo pipefail` grep exits on
  # the MATCH, the producer takes SIGPIPE, pipefail promotes the rc to 141, and the `&& continue`
  # that defers never fires — so the deferral inverts precisely when it is needed.
  #
  # Defined HERE, above both readers, not beside its second one: bash resolves a function at CALL
  # time, so a definition below sweep_unmapped would be `command not found` on every real run while
  # every fixture whose sweep_orphans reports nothing stays green.
  case $'\n'"$ORPHANED" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  return 1
}

check_one() {  # $1 = repo-relative path · $2 = absolute live destination
  local rel="$1" dest="$2" src tgt act
  src="$REPO/$rel"
  [ -f "$src" ] || return 0
  # Claim this path for the forward walk. The STRAY leg below sweeps the same live directories, so
  # without a claim a live REAL file that shadows a tracked one is classified twice — SHADOW here and
  # COPY (or STRAY) there — inflating the tally and printing two lines for one file with one remedy.
  # Recorded rather than re-derived: the forward walk's globs are the map of record, and a second
  # hand-written copy of them is precisely how two auditors over one population come to disagree.
  SEEN="${SEEN}${rel}"$'\n'
  if [ -L "$dest" ]; then
    tgt="$(_resolve "$dest")"
    if [ "$tgt" = "$src" ]; then
      linked_n=$((linked_n + 1))
      $ALL && note "LINKED" "$rel" "→ live"
      return 0
    fi
    if [ ! -e "$dest" ]; then
      note "DANGLING" "$rel" "live link → $tgt, which does not exist"
    else
      note "MISLINKED" "$rel" "live link → $tgt (not this checkout)"
    fi
    fix "ln -sfn \"$src\" \"$dest\""
    findings=$((findings + 1))
    return 0
  fi
  if [ -e "$dest" ]; then
    note "SHADOW" "$rel" "live path is a REAL file, not a link — repo edits are NOT live"
    fix "ln -sfn \"$src\" \"$dest\"    # replaces a real file — inspect it first"
    findings=$((findings + 1))
    return 0
  fi
  act="$(pending_owner "$rel")"
  if [ -n "$act" ]; then
    note "PENDING" "$rel" "unlinked BY DESIGN — staged: $act"
    pending_n=$((pending_n + 1))
    return 0
  fi
  note "UNLINKED" "$rel" "landed in the checkout but NOT live — silently inert"
  fix "ln -sfn \"$src\" \"$dest\""
  findings=$((findings + 1))
}

# The mirror case: a live link whose checkout target was renamed or deleted. Unreachable by
# iterating repo files (the file is gone), and just as inert — a rename lands BOTH halves.
sweep_orphans() {
  local d="$1" l tgt
  [ -d "$d" ] || return 0
  for l in "$d"/*; do
    [ -L "$l" ] || continue
    [ -e "$l" ] && continue
    tgt="$(readlink "$l")"
    case "$tgt" in "$REPO"/*) ;; *) continue ;; esac
    # Claim it for this leg. The reverse leg below sweeps the SAME dangling class over the whole
    # live tree, so without a claim one broken link is reported twice with one remedy — the exact
    # double-classification the SEEN ledger was introduced to prevent, one leg over.
    ORPHANED="${ORPHANED}${l#"$CFG"/}"$'\n'
    note "ORPHAN" "${l#"$CFG"/}" "→ $tgt (gone from the checkout)"
    fix "rm \"$l\""
    findings=$((findings + 1))
  done
}

# --- STRAY: a live REAL FILE whose content is in no tracked file and which no row declares --------
#
# The tracked-content set is built LAZILY — only once a real-file candidate actually appears, which
# on a healthy machine is never. Two code paths, each internally consistent about its hash:
#   · a real checkout → `git hash-object` the live file and look the blob up in `git ls-files -s`.
#     ONE git call for the whole set, and the comparison is git's own content identity, so a copy
#     under a different name (it2 ← bin/it2-wrapper) matches exactly.
#   · no git (the hermetic fixtures) → shasum both sides. Never mix the two: a git blob hash carries
#     a header and can never equal a bare content digest, so a mixed comparison would report every
#     legitimate copy as a STRAY — a false RED on the one case this leg exists to NOT convict.
TRACKED_SET=""
TRACKED_MODE=""
_load_tracked() {
  [ -n "$TRACKED_MODE" ] && return 0
  if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    TRACKED_MODE="git"
    TRACKED_SET="$(git -C "$REPO" ls-files -s 2>/dev/null | awk '{print $2}')"
  else
    TRACKED_MODE="hash"
    TRACKED_SET="$(find "$REPO" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
                     -exec shasum -a 1 {} + 2>/dev/null | awk '{print $1}')"
  fi
  return 0
}

content_is_tracked() {  # $1 = absolute live file → 0 if its bytes are in a tracked checkout file
  local h
  _load_tracked
  if [ "$TRACKED_MODE" = "git" ]; then
    h="$(git -C "$REPO" hash-object -- "$1" 2>/dev/null)" || return 1
  else
    h="$(shasum -a 1 < "$1" 2>/dev/null | awk '{print $1}')" || return 1
  fi
  [ -n "$h" ] || return 1
  # -c AND NEVER -q, and the reason is measured on this exact line (2026-08-19). Under the
  # `set -uo pipefail` at the top of this file, `grep -q` exits the instant it matches; the producer
  # is then killed by SIGPIPE and the PIPELINE's rc becomes 141 — so a MATCH returned FALSE, and
  # because this pipeline is the function's LAST statement that inverted rc was its RETURN VALUE.
  # Every caller read "these bytes are in no tracked file". Live effect: ~/.claude/bin/it2 — a real
  # file cp'd from the tracked bin/it2-wrapper under a different name, byte-identical (blob
  # 1df5cbff) — was reported STRAY, which is precisely the case config/live-only.manifest's header
  # names as "a false RED on the one case this leg exists to NOT convict".
  #
  # A BUILTIN PRODUCER IS NOT EXEMPT, contrary to the folklore. It is exempt only while what it
  # writes fits the 64 KiB pipe buffer, and $TRACKED_SET is one 40-char line per tracked file —
  # 2,035 lines / ~83 KB on this repo today, i.e. already past it, and growing. The failure also
  # gets MORE likely the EARLIER the match is found, so the healthiest inputs fail hardest.
  # pipefail-sigpipe-lint.sh's own header records the same measurement (64 KiB → 10/10).
  # Counting consumes the whole stream, so there is no early exit and no signal to invert.
  local n
  n="$(printf '%s\n' "$TRACKED_SET" | grep -cxF -- "$h" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt 0 ]
}

# --- UNCONVERGED: the bytes ARE versioned; this checkout simply has not caught up ----------------
#
# STRAY's message is ABSOLUTE — "in NO checkout — unversioned, invisible to review" — but its
# evidence is `git ls-files -s` over ONE checkout, and that reference MOVES. The live symlink source
# is the shared checkout, and it sits behind origin/main for exactly as long as a land goes
# unconverged. Measured 2026-08-31T22:04Z: the shared checkout was SIX commits behind origin/main,
# and skills/outbound-drafting/SKILL.md — landed on trunk that morning — was reported STRAY, its
# blob absent from the index (2,248 objects) and present in origin/main's tree (2,249).
#
# Two costs, and the second is the worse one. The verdict is false; and the printed Fix reads
# `cp … && git -C <checkout> add …`, i.e. stage a file that is ALREADY on trunk, into the shared
# checkout this repo's own .claude/CLAUDE.md opens by forbidding anyone to commit in. A remedy
# computed from an incomplete classification does not merely mislabel — it prescribes.
#
# So ask the REF before convicting. No git, no resolvable ref, or an empty tree falls through to
# STRAY, which is the safe direction: this clause can only ever RE-LABEL a finding, never remove
# one. The count and the exit status are deliberately unchanged — a file whose bytes reach the live
# layer without a link is still drift, and laundering it to clean would be a weaker gate wearing a
# fix's clothes. What changes is which of two opposite remedies gets printed.
TRUNK_REF="${CC_LINKPARITY_TRUNK:-origin/main}"
TRUNK_SET=""
TRUNK_MODE=""
_load_trunk() {
  [ -n "$TRUNK_MODE" ] && return 0
  TRUNK_MODE="none"
  # Only the git path has a ref at all. The hermetic no-git branch hashes bare content, and a git
  # blob hash can never equal a bare digest — mixing them is the exact fault the header names.
  [ "$TRACKED_MODE" = "git" ] || return 0
  git -C "$REPO" rev-parse --verify --quiet "$TRUNK_REF^{commit}" >/dev/null 2>&1 || return 0
  TRUNK_SET="$(git -C "$REPO" ls-tree -r "$TRUNK_REF" 2>/dev/null | awk '{print $3}')"
  [ -n "$TRUNK_SET" ] || return 0
  TRUNK_MODE="git"
  return 0
}

content_is_on_trunk() {  # $1 = absolute live file → 0 if its bytes are in $TRUNK_REF's tree
  local h n
  _load_tracked
  [ "$TRACKED_MODE" = "git" ] || return 1
  _load_trunk
  [ "$TRUNK_MODE" = "git" ] || return 1
  h="$(git -C "$REPO" hash-object -- "$1" 2>/dev/null)" || return 1
  [ -n "$h" ] || return 1
  # -c AND NEVER -q, for the measurement written out against content_is_tracked above: TRUNK_SET is
  # one 40-char line per tracked object — 2,249 lines / ~92 KB on this repo today, already past the
  # 64 KiB pipe buffer where a matching `grep -q` takes the producer down with SIGPIPE and pipefail
  # returns the MATCH as false. Counting consumes the whole stream, so nothing can invert.
  n="$(printf '%s\n' "$TRUNK_SET" | grep -cxF -- "$h" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt 0 ]
}

# --- REFERENCE PROVENANCE: how current is the index every absence verdict is computed against? ----
#
# content_is_on_trunk() above fixed the CLASSIFICATION half of the stale-reference problem: it asks
# the trunk ref before calling a landed file unversioned. This is the half that fix could not perform
# for itself. Every absence verdict this script prints — STRAY's "in NO checkout", UNLINKED, the
# tracked-set legs — is evidence about $REPO's index, and $REPO is the shared checkout, which lags
# origin/main for exactly as long as a land goes unconverged. Nothing in the output has ever said so,
# so a reader has no reason to ask, and the number that would answer them is one rev-list away.
#
# THE MEASUREMENT THAT FORCED THIS, 2026-08-31T22:31Z. The clause above landed on trunk at 22:0xZ and
# the destination went on printing the pre-fix verdict for the whole of the next link, because THE
# READER IS DELIVERED BY THE SAME LAGGING PATH AS THE FILES IT AUDITS: ~/.claude/scripts/deploy-link-
# parity.sh is a per-file symlink into $REPO's WORKING TREE (the header 200 lines up already relies on
# that fact to resolve BASH_SOURCE). $REPO was 8 commits behind origin/main; its copy of this file
# carried ZERO occurrences of content_is_on_trunk against trunk's 3; and so a live run at the real
# destination, with no seam set, reported skills/outbound-drafting/SKILL.md as STRAY and printed the
# cp//git add remedy the clause above exists to suppress. Auditor and subject share one lag, and the
# converger declines to close it while the commits above the live sha are un-stamped.
#
# So the reference states its own currency. This changes NO verdict, NO finding count and NO exit
# status — it is a caveat, not a leg — and it prints ABOVE the findings, because a qualifier that
# changes how a list is read is worthless underneath that list.
#
# Three answers, deliberately distinct, and 0 is not the fallback for any failure: a lag of 0 IS the
# healthy state, so a failed read rendering as 0 would be indistinguishable from a converged
# reference (memory: fail-safe-default-mimics-the-healthy-state). "n-a" is the hermetic/no-git case,
# where the question does not exist; "unknown" is a git reference whose ref or count could not be
# read, which is a fact worth printing rather than swallowing.
reference_lag() {   # echoes: an integer · "unknown" · "n-a"
  local n
  _load_tracked
  [ "$TRACKED_MODE" = "git" ] || { printf 'n-a\n'; return 0; }
  git -C "$REPO" rev-parse --verify --quiet "$TRUNK_REF^{commit}" >/dev/null 2>&1 || { printf 'unknown\n'; return 0; }
  # No pipeline: rev-list --count emits exactly one integer, and routing it through `head` would put
  # a second rc in front of the only one that means anything.
  n="$(git -C "$REPO" rev-list --count "HEAD..$TRUNK_REF" 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) printf 'unknown\n' ;; *) printf '%s\n' "$n" ;; esac
}

# A declared row is honoured ONLY while its witness still exists AND still mentions the artifact.
# Prints "OK<TAB>why" when live, "STALE<TAB>witness" when the reason has dissolved, nothing when no
# row matches. The three outcomes are distinct on purpose: a row whose producer was renamed away must
# become a finding, not a permanent licence — that is how an exemption outlives the design it encodes.
declared_owner() {  # $1 = live-relative path
  local rel="$1" path kind witness why stem base dir
  [ -f "$MANIFEST" ] || return 0
  while IFS="$(printf '\t')" read -r path kind witness why; do
    case "$path" in ''|'#'*) continue ;; esac
    # A short row cannot be honoured: with no witness there is nothing to re-verify, so the row is
    # skipped and its file falls through to STRAY. That is the safe direction — a malformed manifest
    # loses its exemptions rather than silently granting unverifiable ones.
    [ -n "$witness" ] || continue
    base="${path##*/}"; dir="${path%/*}"
    case "$base" in
      \**) stem="${base#\*}"
           [ "$dir/${rel##*/}" = "$rel" ] || continue
           case "$rel" in *"$stem") ;; *) continue ;; esac
           # A WHOLE-DIRECTORY row (`skills/motion/*`) has no literal remainder, so the witness
           # stem would be the empty string — and `grep -F ''` matches every line, which silently
           # degrades the witness check into "does the witness file exist" and kills the anti-rot
           # device the manifest is built on. Fall back to the row's own directory name, which is
           # what a whole-directory exemption is actually about: skills/motion/* stays honoured
           # only while its witness still says "motion".
           [ -n "$stem" ] || stem="${dir##*/}" ;;
      *)   stem="$base"
           [ "$path" = "$rel" ] || continue ;;
    esac
    if [ -f "$REPO/$witness" ] && grep -qF -- "$stem" "$REPO/$witness" 2>/dev/null; then
      printf 'OK\t[%s] %s\n' "$kind" "$why"
    else
      printf 'STALE\t%s\n' "$witness"
    fi
    return 0
  done < "$MANIFEST"
  return 0
}

sweep_strays() {  # $1 = live-relative directory
  local d="$1" f base rel verdict why
  [ -d "$CFG/$d" ] || return 0
  for f in "$CFG/$d"/*; do
    [ -e "$f" ] || continue          # no match, or a dangling link — the two legs below own those
    # Every symlink belongs to the forward walk, sweep_orphans or sweep_unmapped. That used to name
    # only the first TWO, and the omission was load-bearing rather than stylistic: sweep_orphans
    # sweeps a hand-written directory list, so for the 68 live symlinks outside it a broken link was
    # deferred here to a leg that never ran. Named in THREE parts now because a deferral is only as
    # true as the scopes it defers to, and the third one derives from the territory.
    [ -L "$f" ] && continue
    [ -d "$f" ] && continue          # structural dirs and __pycache__ residue are not tools
    base="$(basename "$f")"; rel="$d/$base"
    # Already classified by the forward walk (it reported SHADOW) — one file, one verdict, one remedy.
    _claimed "$rel" && continue
    if content_is_tracked "$f"; then
      extra_n=$((extra_n + 1))
      $ALL && note "COPY" "$rel" "real file, but its bytes are tracked — deployed by copy"
      continue
    fi
    verdict="$(declared_owner "$rel")"
    why="${verdict#*"$(printf '\t')"}"
    case "$verdict" in
      OK*)
        extra_n=$((extra_n + 1))
        $ALL && note "DECLARED" "$rel" "live-only by design — $why"
        ;;
      STALE*)
        note "STALE-DECL" "$rel" "declared live-only, but its witness $why is gone or no longer names it"
        fix "review config/live-only.manifest: the row for $rel no longer has a producer"
        findings=$((findings + 1))
        ;;
      *)
        if content_is_on_trunk "$f"; then
          # Versioned after all — this checkout is just behind. Never print the cp/add remedy here:
          # the file is already on the ref, and the checkout it names is the one nobody may commit in.
          note "UNCONVERGED" "$rel" "bytes ARE on $TRUNK_REF — versioned, but this checkout has not converged"
          fix "bash \"$REPO/scripts/deploy-live.sh\"    # already on $TRUNK_REF — converge; do NOT cp/add it into the checkout"
        else
          note "STRAY" "$rel" "live and executable, in NO checkout — unversioned, invisible to review"
          fix "cp \"$CFG/$rel\" \"$REPO/$rel\" && git -C \"$REPO\" add \"$rel\"    # or rm it, or declare it in config/live-only.manifest"
        fi
        findings=$((findings + 1))
        ;;
    esac
  done
}

# --- the per-file symlink surfaces install.sh deploys (install.sh is the map of record) --------
for f in "$REPO"/hooks/*.sh;      do check_one "hooks/$(basename "$f")"     "$CFG/hooks/$(basename "$f")"; done
for f in "$REPO"/hooks/lib/*.sh;  do check_one "hooks/lib/$(basename "$f")" "$CFG/hooks/lib/$(basename "$f")"; done
for f in "$REPO"/commands/*.md;   do check_one "commands/$(basename "$f")"  "$CFG/commands/$(basename "$f")"; done
for f in "$REPO"/scripts/*.sh;    do check_one "scripts/$(basename "$f")"   "$CFG/scripts/$(basename "$f")"; done
for f in "$REPO"/scripts/limit-recover/*; do
  check_one "scripts/limit-recover/$(basename "$f")" "$CFG/scripts/limit-recover/$(basename "$f")"
done
# bin/ is THREE families, not one. install.sh:815 globs cc-*, desk-* and ms365-*, and the header
# above calls install.sh the map of record — so a family it globs and this walk does not is a
# restatement that has silently drifted. Measured 2026-08-31T01:39:00Z: this line globbed cc-*
# alone and therefore visited 78 of 78 cc-* files and 0 of the 3 desk-*/ms365- ones, so no
# check_one ever ran for them. That is a blind spot in exactly the leg whose founding scar (:8-9)
# is a live symlink that did not exist — and at that moment ~/.claude/bin/ms365-reply-splice.py
# was in fact absent, with the live email hook prescribing it. Derived coverage is pinned by
# tests/ms365-reply-splice.bats, which reads install.sh's families and asserts each is walked here.
for f in "$REPO"/bin/cc-* "$REPO"/bin/desk-* "$REPO"/bin/ms365-*; do check_one "bin/$(basename "$f")"       "$CFG/bin/$(basename "$f")"; done
for d in "$REPO"/skills/*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  for f in "$d"*; do check_one "skills/$n/$(basename "$f")" "$CFG/skills/$n/$(basename "$f")"; done
done
# The seven classes below were absent from this walk until 2026-08-31, and the reason they were
# missed is the generalisation of the bin/ fix directly above it. That fix asked "who else holds a
# copy of the bin/ enumeration?" and answered THREE files. The question it did not ask is the one
# that matters more here: of every class install.sh globs, how many does THIS walk visit at all?
# Measured 2026-08-31T02:10:51Z by extracting both files' own `for ... in` headers and running
# them: install.sh globs 19 classes and this walk covered 9. Ten were unvisited, every one of them
# non-empty on trunk, so no check_one had ever run for 29 tracked files across seven per-file
# classes — hooks/*.py, agents/*.md, lib/*.{sh,zsh}, scripts/lib/*.{sh,py} and
# scripts/backlog-consolidation/*.py. All 29 were correctly linked at that moment (measured:
# 29 of 29 symlinks resolving into the deploy checkout), so this is a DETECTOR gap being closed,
# not an outage being repaired — and a detector gap is only ever visible when something else breaks.
# A blind spot is per-CLASS, not per-holder; fixing one family leaves the rest of the map unread.
for f in "$REPO"/hooks/*.py;    do check_one "hooks/$(basename "$f")"   "$CFG/hooks/$(basename "$f")"; done
for f in "$REPO"/agents/*.md;   do check_one "agents/$(basename "$f")"  "$CFG/agents/$(basename "$f")"; done
for f in "$REPO"/lib/*.sh;      do check_one "lib/$(basename "$f")"     "$CFG/lib/$(basename "$f")"; done
for f in "$REPO"/lib/*.zsh;     do check_one "lib/$(basename "$f")"     "$CFG/lib/$(basename "$f")"; done
for f in "$REPO"/scripts/lib/*.sh; do check_one "scripts/lib/$(basename "$f")" "$CFG/scripts/lib/$(basename "$f")"; done
for f in "$REPO"/scripts/lib/*.py; do check_one "scripts/lib/$(basename "$f")" "$CFG/scripts/lib/$(basename "$f")"; done
for f in "$REPO"/scripts/backlog-consolidation/*.py; do
  check_one "scripts/backlog-consolidation/$(basename "$f")" "$CFG/scripts/backlog-consolidation/$(basename "$f")"
done

# FORWARD-WALK EXCLUSIONS. install.sh globs these three classes too, and for each of them a
# per-file "$CFG/<rel>" parity question is the WRONG question — they deploy to a different ROOT or
# by a different MODEL, so walking them here would mint a finding per member against a live layer
# that is in fact correct. They are listed rather than merely omitted because an omission carries
# no reason, and a reasonless omission is indistinguishable from the oversight this block exists to
# end: tests/deploy-link-parity.bats reads BOTH the walk above and this list, and asserts every
# class install.sh globs appears in exactly one of them. A class added to install.sh tomorrow and
# to neither is a RED, which is what stops the next family landing in only some of the holders.
#   NOT-PER-FILE /githooks/*       copies into <repo>/.git/hooks and ~/.git-template/hooks (install.sh's githooks leg)
#   NOT-PER-FILE /launchd/*.plist  copies into ~/Library/LaunchAgents (install.sh's LaunchAgents leg)
#   NOT-PER-FILE /vendor/*/        ONE directory symlink per plugin, deliberately not per file (install.sh's vendor leg)

# Single-file links install.sh makes by name rather than by glob.
check_one "accounts.json"       "$CFG/accounts.json"
check_one "bin/claude-accounts" "$BINDIR/claude-accounts"

for d in hooks hooks/lib commands scripts scripts/limit-recover bin; do sweep_orphans "$CFG/$d"; done
for d in "$CFG"/skills/*/; do [ -d "$d" ] && sweep_orphans "$d"; done

# The EXECUTED surfaces only — see STRAY SCOPE in the header. Until 2026-08-31 this comment read
# "scripts/lib and lib are swept here but are not in the forward walk above; that asymmetry is
# deliberate, not an oversight". Both halves have to be corrected, and the second is the instructive
# one. The FACT was true and is now false — both are forward-walked as of the block above. The
# JUSTIFICATION never covered what it claimed to: it argues that the stray direction stands on its
# own, which is a reason to sweep MORE, and no reason at all for the forward direction to cover
# LESS. Calling the gap deliberate is what stopped anyone counting it for three weeks, and the walk
# above measured it at ten classes. A sentence that declares an asymmetry intentional must say which
# DIRECTION it is defending; this one defended the wrong one.
# The remaining asymmetry is real and is stated positively: this sweep visits the EXECUTED set —
# commands/ and the three NOT-PER-FILE classes are out of its scope for the reasons the header and
# the exclusion block above give, not by omission.
#
# AND THE LIST BELOW IS THE FIFTH RESTATED ENUMERATION OF THE LIVE LAYER IN THIS FILE, WHICH IS WHY
# IT HAD SILENTLY FALLEN BEHIND THE FIRST (2026-09-01). The paragraph above corrects a claim about
# this sweep's scope, and the widening it describes was the FORWARD walk's: seven classes were added
# there on 2026-08-31 and neither live-side sweep followed. That is not a second oversight, it is the
# same one — a scope sentence measured 2026-08-08 is not falsified by anything it says, it is
# falsified by a SIBLING enumeration growing, and no reader of either one can see the other move.
# Derived from both files' own loop headers and diffed: the forward walk visits eleven live
# directories, this sweep reached nine, and of the two it did not reach, commands/ is DECLARED below
# and scripts/backlog-consolidation was owned by nobody. Measured behaviourally rather than argued:
# a hermetic fixture with one unversioned real file planted per scope class reported the plant in
# scripts/ and in scripts/lib/ and said NOTHING about the one in scripts/backlog-consolidation/ —
# the bin/cc-mail defect class, in a directory the forward walk had just declared part of the
# deployed surface. 0 real files live there today (5 symlinks), so this closes a DETECTOR gap rather
# than repairing an outage, and a detector gap is only ever visible when something else breaks.
#
# The declaration below is what stops the next widening re-opening it. tests/deploy-link-parity.bats
# pins install.sh's classes against the forward walk and has since 2026-08-31; it had no counterpart
# in this direction, so the walk could grow and this line could not notice. The new arm derives BOTH
# sides from their own loop headers and requires every forward-walked directory to be swept here or
# declared NOT-STRAY-SWEPT — never merely absent, because an omission carries no reason.
#   NOT-STRAY-SWEPT commands   prompt documents: live-only content there is the NORMAL path, not a
#                              defect (see STRAY SCOPE in the header). The config ROOT is not a
#                              member of this question at all — install.sh reaches it by singleton
#                              link_file calls with no loop header, and it holds 338 real files
#                              (settings.json and its backups, measured 2026-09-01T02:04Z), which is
#                              what sweeping it would convict.
for d in bin hooks hooks/lib scripts scripts/lib scripts/backlog-consolidation scripts/limit-recover lib; do sweep_strays "$d"; done

# PROMPT-DOCUMENT surfaces. skills/ is NESTED where every executed surface is flat, so the sweep is
# driven one level down — sweep_strays lists a single directory and skips subdirectories, so passing
# "skills" itself would visit nothing at all and read as a clean pass over an unswept surface.
for d in "$CFG"/skills/*/; do [ -d "$d" ] && sweep_strays "skills/$(basename "$d")"; done
sweep_strays "agents"

# ── THE REVERSE DIRECTION — UNMAPPED (2026-08-31) ───────────────────────────────────────────────
# Every leg above is driven by a MAP: check_one by the hand-written glob headers at :466-523, and
# both live-side sweeps by their own hand-written directory lists. :151 already states the hazard —
# "the forward walk's globs are the map of record, and a second hand-written copy of them is
# precisely how two auditors over one population come to disagree" — and SEEN exists to keep those
# auditors in step. Nothing had ever asked the question SEEN can answer: does the map cover the
# TERRITORY? It does not.
#
# MEASURED 2026-08-31T23:56:23Z against the live layer, with the reverse walk's own totals: 512
# distinct checkout paths carry a per-file live symlink, the forward walk claimed 458, and the 54 it
# never visits partition into five classes that sum to it —
#   39  skills/<name>/<subdir>/...  install.sh:745-754 links every file under a skill RECURSIVELY
#                                   (`find "$skilldir" -type f`); the walk at :482-485 is
#                                   `for f in "$d"*`, ONE level. One class, two enumerations, two
#                                   depths. (tests/…:496 pins depth-1 for the STRAY leg only — that
#                                   is an honest scope for "did an unversioned file appear", and it
#                                   says nothing about the forward direction.)
#    5  bin/kitty-* · bin/it2-kitty deployed by scripts/kitty-setup.sh, the SECOND installer, which
#                                   no coverage arm reads at all.
#    2  model-config.yaml           install.sh:545 and :554 link them BY NAME. The singleton block
#       providers.json              at :520-523 carries two of install.sh's SEVEN
#                                   `link_file "$REPO_DIR/<x>"` sites.
#    6  bin/claude-* · bin/it2-wrapper  live-linked into this checkout by NO installer in the tree.
#                                   RE-MEASURED 2026-09-01: the five claude-* names DO appear in
#                                   install.sh:458, but that loop `copy_file`s them to ~/bin, where
#                                   all five are REAL FILES today — a different root and a different
#                                   model. it2-wrapper is copied to $CFG/bin/it2, a different NAME.
#                                   So no producer creates these six links, install.sh cannot
#                                   restore one, and link_refresh() (which lives in deploy-live.sh,
#                                   not install.sh) repairs only install.sh's own classes. Stated
#                                   with the destinations because "the name appears in install.sh"
#                                   and "install.sh deploys this path" are different claims.
#    2  tools/auth/auth-timeseries.sh · scripts/cloud-create-api.py   (:469 globs scripts/*.sh only)
#
# WHY A NEW LEG RATHER THAN A WIDER WALK. tests/deploy-link-parity.bats:623 already asserts that
# every class install.sh globs is walked or declared NOT-PER-FILE, and it is GREEN over all five of
# the above, because its population is `grep -E '^[[:space:]]*for [A-Za-z_]+ in ' install.sh`. A
# singleton `link_file` has no loop header and a second installer is never read, so those classes
# are not UNCOVERED by that arm — they are not MEMBERS OF ITS QUESTION. Widening the walk fixes
# today's five and leaves the sixth to the same blind extractor. This leg derives from the
# TERRITORY, so it cannot go stale: a class added to any producer tomorrow surfaces the moment its
# first file is deployed, whether or not anyone remembers to widen a glob.
#
# THE UNMAPPED COUNT IS NOT COUNTED INTO `findings`, DELIBERATELY, AND THAT IS THE PART TO CHECK
# RATHER THAN TRUST. A member that RESOLVES is by construction correctly linked — a gap in the map,
# not a deployment failure — and its remedy is a walk-or-declare decision rather than a per-file
# command. Folding 54 correct files into a report that reads "3 actionable" would bury the three
# real ones (memory: alarm-polarity-and-attention-budget). It is counted in the summary line for
# exactly the reason live-extra is: so the number is visible without being an alarm.
#
# A member that does NOT resolve is the opposite case and IS a finding, added 2026-09-01. The two
# are one walk because they are one enumeration of the territory, but they are two verdicts: an
# unmapped-but-linked file executes correctly and merely goes unaudited, while an unmapped-and-
# BROKEN one does not execute at all. Keeping the second out of `findings` to protect the first's
# quietness would be the alarm-budget argument used to silence the actionable half of its own
# population.
sweep_unmapped() {
  local l tgt rel
  # The prune set is the non-deployed stores; everything remaining under $CFG is a candidate. A
  # resolving directory symlink is rejected by the -f test below (the vendor/ leg, declared
  # NOT-PER-FILE above) — but only AFTER the dangling arm has run, because a broken link is broken
  # whatever its target was going to be, and -f cannot tell those two states apart.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    tgt="$(readlink "$l" 2>/dev/null)" || continue
    case "$tgt" in "$REPO"/*) ;; *) continue ;; esac
    # DANGLING, and this is the leg that owns it for the whole tree. sweep_orphans reports the same
    # class, but only inside its own hand-written directory list — six names plus skills/*/, ONE
    # level deep. That list is the fourth restated enumeration of the live layer in this file and
    # the one no arm quantifies over, so its gaps were silent in every column:
    #   · the forward walk cannot reach a dangling link at all — check_one returns at
    #     `[ -f "$src" ]`, since a renamed-away target is exactly a repo file that no longer exists,
    #     which is the founding reason sweep_orphans exists;
    #   · sweep_strays skips every symlink, deferring in a comment to "the forward walk /
    #     sweep_orphans" — a partition claim naming two owners, true only inside their scopes;
    #   · and the `[ -f "$tgt" ]` test that used to stand here dropped the broken ones BEFORE
    #     unmapped_scanned counted them, so they were absent even from the non-vacuity denominator
    #     built to stop a failed enumeration rendering as the healthy 0.
    # MEASURED 2026-09-01T01:18Z: 514 live symlinks resolve into this checkout and sweep_orphans's
    # scope reaches 446 of them, missing 68 — 12 under scripts/lib, 5 under lib, 5 under
    # scripts/backlog-consolidation, 4 agents, ~37 in skills subdirectories, and model-config.yaml,
    # providers.json and accounts.json at the config root. A hermetic run with one broken link
    # planted per class reported ONE of five and printed "0 unmapped" over the other four.
    # 0 of the 68 were dangling at that moment, so this closes a detector gap rather than repairing
    # an outage — and a detector gap is only ever visible when something else breaks.
    # Deriving from the TERRITORY is what makes it hold: a directory added to any producer tomorrow
    # is covered the moment its first link is deployed, with no list to keep in step.
    if [ ! -e "$tgt" ]; then
      _orphaned "${l#"$CFG"/}" && continue
      note "ORPHAN" "${l#"$CFG"/}" "→ $tgt (gone from the checkout)"
      fix "rm \"$l\""
      findings=$((findings + 1))
      continue
    fi
    # A resolving DIRECTORY symlink is not an unmapped file: the vendor/ leg is declared
    # NOT-PER-FILE above and deploys one directory link per plugin, deliberately. The test stays
    # `-f` for that reason and no longer doubles as the dangling filter, which is what hid the case
    # above inside a guard that reads as being about file type.
    [ -f "$tgt" ] || continue
    unmapped_scanned=$((unmapped_scanned + 1))
    rel="${tgt#"$REPO"/}"
    _claimed "$rel" && continue
    unmapped_n=$((unmapped_n + 1))
    $ALL && note "UNMAPPED" "$rel" "live-linked, but no forward-walk glob visits it — deployed by a producer no coverage arm reads"
  done < <(find "$CFG" -type l \
                -not -path "$CFG/projects/*"    -not -path "$CFG/backups/*" \
                -not -path "$CFG/logs/*"        -not -path "$CFG/autonomy/*" \
                -not -path "$CFG/cc-registry/*" -not -path "$CFG/mailbox/*" 2>/dev/null)
  return 0
}
sweep_unmapped

# 0 unmapped is the HEALTHY reading — "the map covers the territory" — so a failed enumeration must
# never render as one. If the reverse walk resolved NO link into this checkout at all, the question
# was asked and not answered, and the field is `?` (memory: alarm-must-key-on-the-store-not-the-
# sensor; #271's LIVE_STALE carries the identical law for the identical reason).
if [ "$unmapped_scanned" -gt 0 ]; then UNMAPPED_SHOWN="$unmapped_n"; else UNMAPPED_SHOWN="?"; fi

# --- report -------------------------------------------------------------------------------------
if [ "$findings" -eq 0 ] && $QUIET; then exit 0; fi

printf 'link parity: %s → %s\n' "$REPO" "$CFG"

# The reference's own currency, stated before the verdicts it qualifies. Silent at a lag of 0 unless
# --all asks: an advisory that fired on every clean run would carry exactly as much information as
# one that could not fire at all (memory: alarm-polarity-and-attention-budget), and the positive
# reading still has to be reachable on demand or "no line" means both "current" and "never checked".
REF_LAG="$(reference_lag)"
case "$REF_LAG" in
  n-a) : ;;   # no git reference — the question is not applicable, which is not the same as "0"
  0)   if $ALL; then printf '  reference: %s is CURRENT with %s\n' "$REPO" "$TRUNK_REF"; fi ;;
  unknown)
       printf '  reference: %s — cannot read %s, so the lag is UNKNOWN and no absence verdict below is attributable\n' \
         "$REPO" "$TRUNK_REF" ;;
  *)   printf '  reference: %s is %s commit(s) BEHIND %s — every absence verdict below is computed against THIS index, and this script may itself be a stale copy of it\n' \
         "$REPO" "$REF_LAG" "$TRUNK_REF" ;;
esac

[ -n "$LINES" ] && printf '%s' "$LINES"
# live-extra is counted, never hidden: it is what makes "0 actionable" mean "we looked at the live
# side too", rather than "we only ever walked the checkout".
#
# TWO CORRECTIONS TO THAT SENTENCE, both measured 2026-09-01T02:04Z by running this script with
# --all and folding its own emitted lines, which nobody had done since the field was added.
#   · IT SUMS TWO CLASSES, and the reading "its count going up means a copy-deploy surface grew"
#     describes only one of them. extra_n = 10 = ONE copy (bin/it2 ← bin/it2-wrapper) plus NINE
#     live-only.manifest declarations. Nine tenths of anything this field does is the MANIFEST, so a
#     row added tomorrow moves it and reads as a copy surface growing. The classes are already
#     distinguished in --all's output (COPY vs DECLARED) and only in the summary are they one number.
#   · ITS POPULATION IS sweep_strays's DIRECTORY LIST, not the live layer. Both increments are inside
#     that sweep, so a copy surface appearing where the sweep does not go moves nothing — which is
#     exactly what happened to scripts/backlog-consolidation. `linked`, `live-extra` and `unmapped`
#     are counts over three DIFFERENT populations (the walk's globs, this sweep's list, and the
#     territory), printed on one line, and only the third derives from the territory.
printf '  %d linked · %d staged-pending · %d live-extra · %s unmapped · %d actionable\n' \
  "$linked_n" "$pending_n" "$extra_n" "$UNMAPPED_SHOWN" "$findings"

if [ "$findings" -gt 0 ]; then
  printf '\n  ✗ deploy parity broken — landed code that does not run, or live code that is in no repo.\n'
  printf '  Fix (review each — nothing is created or deleted blindly):\n%s' "$FIXES"
  printf '  Or deploy every surface at once:  ▶ %s/install.sh\n' "$REPO"
  exit 1
fi
if [ "$pending_n" -gt 0 ]; then
  printf '  ✓ every landed file is live (%d awaiting its staged activation script — not a gap).\n' "$pending_n"
else
  printf '  ✓ every landed file is live.\n'
fi
exit 0
