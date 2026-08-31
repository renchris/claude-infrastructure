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
# STRAY SCOPE is the EXECUTED surfaces only — bin, hooks, hooks/lib, scripts, scripts/lib,
# scripts/limit-recover, lib. Measured 2026-08-08, not assumed:
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
# CC_LINKPARITY_CONFIG / CC_LINKPARITY_BINDIR / CC_LINKPARITY_PENDING / CC_LINKPARITY_MANIFEST
# (fully hermetic — no case reads the real ~/.claude or the real checkout).
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
LINES=""
FIXES=""
SEEN=""     # repo-relative paths the forward walk claimed; the STRAY leg defers to them

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
    [ -e "$f" ] || continue          # no match, or a dangling link — sweep_orphans owns those
    [ -L "$f" ] && continue          # every symlink belongs to the forward walk / sweep_orphans
    [ -d "$f" ] && continue          # structural dirs and __pycache__ residue are not tools
    base="$(basename "$f")"; rel="$d/$base"
    # Already classified by the forward walk (it reported SHADOW) — one file, one verdict, one remedy.
    printf '%s' "$SEEN" | grep -qxF -- "$rel" && continue
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
        note "STRAY" "$rel" "live and executable, in NO checkout — unversioned, invisible to review"
        fix "cp \"$CFG/$rel\" \"$REPO/$rel\" && git -C \"$REPO\" add \"$rel\"    # or rm it, or declare it in config/live-only.manifest"
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
# Single-file links install.sh makes by name rather than by glob.
check_one "accounts.json"       "$CFG/accounts.json"
check_one "bin/claude-accounts" "$BINDIR/claude-accounts"

for d in hooks hooks/lib commands scripts scripts/limit-recover bin; do sweep_orphans "$CFG/$d"; done
for d in "$CFG"/skills/*/; do [ -d "$d" ] && sweep_orphans "$d"; done

# The EXECUTED surfaces only — see STRAY SCOPE in the header. scripts/lib and lib are swept here but
# are not in the forward walk above; that asymmetry is deliberate, not an oversight. The two
# directions answer different questions, and "is anything live here unversioned?" stands on its own.
for d in bin hooks hooks/lib scripts scripts/lib scripts/limit-recover lib; do sweep_strays "$d"; done

# PROMPT-DOCUMENT surfaces. skills/ is NESTED where every executed surface is flat, so the sweep is
# driven one level down — sweep_strays lists a single directory and skips subdirectories, so passing
# "skills" itself would visit nothing at all and read as a clean pass over an unswept surface.
for d in "$CFG"/skills/*/; do [ -d "$d" ] && sweep_strays "skills/$(basename "$d")"; done
sweep_strays "agents"

# --- report -------------------------------------------------------------------------------------
if [ "$findings" -eq 0 ] && $QUIET; then exit 0; fi

printf 'link parity: %s → %s\n' "$REPO" "$CFG"
[ -n "$LINES" ] && printf '%s' "$LINES"
# live-extra is counted, never hidden: it is what makes "0 actionable" mean "we looked at the live
# side too", rather than "we only ever walked the checkout". Its own count going UP unexplained is
# the signal that a copy-deploy surface grew.
printf '  %d linked · %d staged-pending · %d live-extra · %d actionable\n' \
  "$linked_n" "$pending_n" "$extra_n" "$findings"

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
