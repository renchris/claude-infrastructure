#!/bin/bash
# migration-class: c10
# migration-step: convert ~/.claude-next/hooks from a forked real directory into a symlink to ~/.claude/hooks — the busiest account (bare `claude`) silently misses every hook file added since its fork, permanently, while the other three config dirs converge for free. Needs every .claude-next pane closed, which only you can do; the script refuses under a live pane and refuses unless the conversion is provably lossless.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0013-claude-next-hooks-unfork.sh
# migration-subject: ~/.claude-next/hooks
# migration-verify: [ "$(readlink "$HOME/.claude-next/hooks" 2>/dev/null)" = "$HOME/.claude/hooks" ]
# migration-conflict: [ -L "$HOME/.claude-next/hooks" ] && [ "$(readlink "$HOME/.claude-next/hooks")" != "$HOME/.claude/hooks" ]
#
# The verify/conflict pair is spelled with a LITERAL $HOME/.claude-next, not $CC_CLAUDE_DIR.
# registration-state.sh re-runs each verifier once per config dir with CC_CLAUDE_DIR re-aimed; this
# effect is SINGULAR (it is a fact about one dir, not a per-dir setting), so a CC_CLAUDE_DIR spelling
# would manufacture a permanent `partial` — migrations/README.md § "Mind the per-config-dir loop".
# The conflict arm separates the two ways unsatisfied can read, because they need opposite fixes:
# absent-or-real-dir = "not delivered, run this", symlink-elsewhere = someone aimed it somewhere on
# purpose and this script must not overwrite that.
#
# ══ 0013 — un-forking .claude-next/hooks ══════════════════════════════════════════════════════════
# Backlog: 11da376d60e3.  Measured 2026-08-17.
#
# WHAT IS WRONG. ~/.claude-next/hooks is a FORKED REAL DIRECTORY; .claude-secondary, .claude-tertiary
# and .claude-quaternary each symlink hooks -> ~/.claude/hooks. lib/config-mirror.zsh:78-81 runs in
# safe mode by default and `continue`s on a forked real dir rather than converting it — deliberately,
# because converting mv's the dir aside and is unsafe under live panes. The consequence is that
# .claude-next misses EVERY hook file added since its fork, forever, while the symlinked three
# converge for free. `claude` — the bare launcher, i.e. the busiest account — defaults to
# CLAUDE_CONFIG_DIR=~/.claude-next (~/.zshrc:460), so the drifting dir is the DEFAULT one.
# Measured today: 78 entries in ~/.claude/hooks, 53 in ~/.claude-next/hooks. Absent from the default
# account: mailbox-wake-arm.sh, mailbox-drain.sh, operator-readout.sh, subagent-stop.sh,
# session-beat.sh, escalation-watch.sh, keychain-guard.sh, handed-off-session-guard.sh, +17 more.
#
# WHAT ACTUALLY READS $CLAUDE_CONFIG_DIR/hooks, stated so the blast radius is not overclaimed. NOT
# harness hook dispatch: all 78 hook commands in .claude-next/settings.json are spelled
# `~/.claude/hooks/…` or an absolute /Users/chrisren/.claude/hooks/… path, so the settings surface
# already reaches the canonical dir. The readers are the 55 in-repo call sites that resolve a
# sibling at RUNTIME as "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/…" (handoff-fire.sh:2005,
# scripts/lib/pane-spawn-log.sh's callers, …). In .claude-next those resolve to a path that does not
# exist, and every one of them is guarded — `[ -f x ] && . x`, `command -v f && f …` — so the miss is
# a SILENT skip, not an error. That is the inertness face this migration closes.
#
# WHY THE ROW'S OWN BLOCKER IS REFUTED, AND WHY THE SYMLINK IS THE WHOLE FIX. The row (and 0009's
# SCOPE note) says the gap cannot be swept because deciding whether each absence is a fork artifact
# or a deliberate omission is a per-file judgment. There is no such judgment to make, because the
# fork holds NO CONTENT OF ITS OWN. Measured today over the whole tree: 0 regular files anywhere
# under ~/.claude-next/hooks — 52 depth-1 symlinks into the checkout plus a real lib/ dir holding 4
# more symlinks — and the reverse gap (present in .claude-next only) is EMPTY. So it is a strict
# subset whose every entry is already a link to the same target ~/.claude/hooks links to. Nothing
# can be lost, and no hook is "activated in the default account that nobody chose" — the settings
# entries that dispatch hooks already point at ~/.claude/hooks (above), so this changes what the 55
# runtime-resolution sites FIND, not what the harness runs.
#
# …AND WHY THAT MEASUREMENT IS NOT TRUSTED. Every number above is today's. This script re-derives
# all of it at run time and REFUSES on any divergence, naming the paths. A `cmp` sweep alone would
# be VACUOUS here: cmp follows symlinks, so link-into-src vs the src file it points at compares
# equal by construction and would pass whatever the tree looked like. The predicate therefore
# classifies each entry — link-with-the-same-target, or resolved-byte-identical, or a directory
# whose children are walked separately — and treats everything else, including a dangling link, as
# a REFUSAL rather than a pass.
#
# WHY c10 AND NOT mechanical. The precondition is "zero live .claude-next panes", a state only the
# operator can create — and the runner has exactly two outcomes, both wrong for a wait:
#   rc 0   → ledgered `applied`, never re-run (scripts/deploy-migrations.sh:327,357). A converge that
#            refused because panes were live would record the conversion as done and it would never
#            happen — the inert-diode generator this whole directory exists to abolish.
#   rc ≠ 0 → `failed`: stops every later migration, climbs an attempts counter, pages, and blocks the
#            close protocol's ✅ fleet-wide (:335-345, wrap-ledger.sh counts failed/*.json). On the
#            busiest account panes are live nearly always, so that is a permanent red over a
#            non-event.
# There is no third `deferred` state, so the honest class is the one that means operator-owned: it
# STAGES, files itself once into cc-backlog, and waits. Promotion is still the one-word diff.
#
# WHAT WINDOW REMAINS — stated honestly, because no filesystem here makes this atomic. rename(2)
# cannot replace a non-empty directory with a symlink (ENOTDIR), so the swap is unavoidably TWO
# renames: mv the real dir to its backup, then rename the pre-built symlink into place. Between them
# ~/.claude-next/hooks does not exist, for the duration of one rename in the same directory —
# sub-millisecond, no I/O on the entries themselves. The link is built FIRST at a temp path in the
# same parent, so the ordering buys failure-atomicity, not a shorter window: if the symlink cannot be
# created the real dir has not moved yet and nothing is touched. A reader that resolves
# $CLAUDE_CONFIG_DIR/hooks/x inside that window takes its existing guarded skip — the same skip it
# has been taking for all 25 missing files since the fork. That is the whole exposure, and it is why
# the live-pane refusal is a gate rather than a warning.
#
# REVERSIBLE. The dir is MOVED to $HOME/.claude-next/hooks.premirror-bak.<stamp> (the spelling
# lib/config-mirror.zsh --convert already uses), never deleted, and the exact restore command is
# printed. IDEMPOTENT: a second run finds the symlink and reports a no-op.
#
# Seams, so a test can exercise every arm against a throwaway tree:
#   CC_SRC_CONFIG        source config dir (default $HOME/.claude)
#   CC_DST_CONFIG        target config dir (default $HOME/.claude-next)
#   CC_UNFORK_PS         ps command used by the live-pane probe (default: /bin/ps -wwEo command=)
#   CC_UNFORK_ALLOW_LIVE=1  convert even under live panes (explicit override; never a default)
# bash 3.2-safe.
set -uo pipefail

SRC_CONFIG="${CC_SRC_CONFIG:-$HOME/.claude}"
DST_CONFIG="${CC_DST_CONFIG:-$HOME/.claude-next}"
SRC="$SRC_CONFIG/hooks"
DST="$DST_CONFIG/hooks"

say()  { printf '0013: %s\n' "$1"; }
deny() { printf '0013: REFUSING — %s\n' "$1" >&2; }

# ── 0. preconditions ──────────────────────────────────────────────────────────────────────────────
[ -d "$DST_CONFIG" ] || { say "$DST_CONFIG absent — nothing to do (not a fleet config)"; exit 0; }
if [ ! -d "$SRC" ] || [ -L "$SRC" ]; then
  deny "$SRC is not a real directory — the link would have nothing sound to point at"; exit 1
fi

# ── 1. idempotence / conflict ─────────────────────────────────────────────────────────────────────
if [ -L "$DST" ]; then
  cur="$(readlink "$DST" 2>/dev/null)"
  if [ "$cur" = "$SRC" ]; then
    say "hooks -> $SRC already — no-op"; exit 0
  fi
  deny "hooks is already a symlink, but to '$cur', not '$SRC'. Somebody aimed it there deliberately;
      this script does not overwrite that. Re-point it by hand if that is stale."; exit 1
fi
if [ ! -e "$DST" ]; then
  # No fork to preserve and nothing to move: the plain link is the whole job.
  if ln -s "$SRC" "$DST" 2>/dev/null && [ -d "$DST" ]; then
    say "hooks was absent — linked -> $SRC"; exit 0
  fi
  deny "hooks was absent and the link could not be created at $DST"; exit 1
fi
if [ ! -d "$DST" ]; then
  deny "$DST exists but is neither a directory nor a symlink — refusing to guess"; exit 1
fi

# ── 2. LOSSLESSNESS, re-derived now (never trusted from the header) ───────────────────────────────
# One pass over every entry the fork holds, at any depth. An entry is safe to drop only if the
# canonical dir already carries something equivalent. `cmp` is used ONLY as the content arm and never
# alone: it follows symlinks, so for a link-into-src it is a tautology (see the header).
gap="" ; diverge="" ; n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  rel="${p#"$DST"/}"
  s="$SRC/$rel"
  n=$(( n + 1 ))
  if [ ! -e "$s" ] && [ ! -L "$s" ]; then
    gap="$gap
      $rel"
    continue
  fi
  if [ -L "$p" ]; then
    dt="$(readlink "$p" 2>/dev/null)"; st="$(readlink "$s" 2>/dev/null)"
    [ -n "$dt" ] && [ "$dt" = "$st" ] && continue          # identical wiring
    if cmp -s "$p" "$s" 2>/dev/null; then continue; fi      # different spelling, same bytes
    if [ ! -r "$p" ]; then
      diverge="$diverge
      $rel (dangling link -> ${dt:-?})"
    else
      diverge="$diverge
      $rel (link -> ${dt:-?}; canonical is ${st:-a file}, and the bytes differ)"
    fi
    continue
  fi
  if [ -d "$p" ]; then
    # A real dir carries no bytes of its own; its children are separate entries in this same walk.
    [ -d "$s" ] && continue
    diverge="$diverge
      $rel (directory here, but not a directory in the canonical dir)"
    continue
  fi
  if cmp -s "$p" "$s" 2>/dev/null; then continue; fi
  diverge="$diverge
      $rel (regular file whose bytes differ from the canonical one)"
done <<EOF
$(find "$DST" -mindepth 1 2>/dev/null)
EOF

if [ -n "$gap" ]; then
  deny "the reverse gap is NOT empty — these exist only in $DST and would be LOST:$gap
      Nothing was touched. Copy them into $SRC (they belong to the whole fleet) or delete them, then re-run."
  exit 1
fi
if [ -n "$diverge" ]; then
  deny "these entries are NOT equivalent to the canonical dir and would be LOST:$diverge
      Nothing was touched. Reconcile each against $SRC, then re-run."
  exit 1
fi
say "losslessness re-verified: $n entries, reverse gap empty, every one equivalent to $SRC"

# ── 3. LIVE-PANE GATE ─────────────────────────────────────────────────────────────────────────────
# The argv rules mirror claude-accounts concurrency() (bin/claude-accounts:268-315): argv[0] must be
# the claude binary in any spelling, headless one-shots are skipped, and attribution uses the LAST
# CLAUDE_CONFIG_DIR= match because `ps -E` appends the environment AFTER argv — an earlier match can
# be prompt text merely mentioning it (MEMORY: pgrep-f-matches-agent-briefs).
#
# It deliberately does NOT mirror that function's mirrors_default clause, which counts a session with
# no CLAUDE_CONFIG_DIR (or ~/.claude) toward the .claude-next account. That clause is right for its
# own question — auth is SHARED, so a token rotation hurts those sessions too — and wrong for this
# one: hooks are NOT shared, and a session running under ~/.claude reads ~/.claude/hooks and cannot
# observe this swap at all. Two gates over one population must share the state model or they disagree
# for reasons neither records, so the difference is named here rather than inherited silently.
# Consequence if it were inherited: on this box nearly every session counts as .claude-next, and the
# gate would refuse forever.
live_count() {  # → count on stdout; 255 = could not determine
  local out line t0 d head_args i
  # shellcheck disable=SC2086  # deliberate word-split: the seam carries a command AND its flags
  out="$( ${CC_UNFORK_PS:-/bin/ps -wwEo command=} 2>/dev/null )" || { echo 255; return; }
  [ -n "$out" ] || { echo 255; return; }
  local n=0
  while IFS= read -r line; do
    # shellcheck disable=SC2086  # deliberate word-split: we want argv as fields
    set -- $line
    [ $# -gt 0 ] || continue
    t0="$1"
    case "$t0" in
      claude|*/claude|*claude.exe|*cli.js*) ;;
      *) continue ;;
    esac
    # headless one-shots are not interactive panes. Built by iteration, not "$2 $3 …": under `set -u`
    # a 2-token argv would abort the whole migration on an unbound positional.
    shift
    head_args=""; i=0
    while [ $# -gt 0 ] && [ "$i" -lt 6 ]; do head_args="$head_args $1 "; shift; i=$(( i + 1 )); done
    case "$head_args" in *' -p '*|*' --print '*|*' --version '*) continue ;; esac
    d="$(printf '%s\n' "$line" | tr ' ' '\n' | grep '^CLAUDE_CONFIG_DIR=' | tail -1)"
    d="${d#CLAUDE_CONFIG_DIR=}"
    # shellcheck disable=SC2088  # the tilde is a LITERAL to be matched, not a path to expand: a
    # launcher may export CLAUDE_CONFIG_DIR=~/.claude-next unexpanded, and ps then reports those
    # bytes. This is the one place that spelling has to be recognised rather than produced.
    case "$d" in "~/"*) d="$HOME/${d#\~/}" ;; esac
    [ -n "$d" ] || continue          # no config dir ⇒ reads ~/.claude ⇒ not our population
    [ "${d%/}" = "${DST_CONFIG%/}" ] && n=$(( n + 1 ))
  done <<EOF
$out
EOF
  echo "$n"
}

k="$(live_count)"
if [ "$k" = "255" ]; then
  if [ "${CC_UNFORK_ALLOW_LIVE:-0}" = "1" ]; then
    say "live-pane probe could NOT run — proceeding on CC_UNFORK_ALLOW_LIVE=1"
  else
    deny "the live-pane probe could not run, so this cannot prove nobody is reading $DST.
      A probe that acts on a non-verdict is worse than no probe. Nothing was touched.
      Re-run once ps is available, or pass CC_UNFORK_ALLOW_LIVE=1 if you know the account is idle."
    exit 1
  fi
elif [ "$k" -gt 0 ]; then
  if [ "${CC_UNFORK_ALLOW_LIVE:-0}" = "1" ]; then
    say "$k live session(s) under $DST_CONFIG — proceeding anyway on CC_UNFORK_ALLOW_LIVE=1"
  else
    deny "$k live session(s) are running under CLAUDE_CONFIG_DIR=$DST_CONFIG.
      Replacing a directory means it stops existing for one rename, and a live session may resolve a
      path through it in that window. Nothing was touched.
      Close that account's panes (bare \`claude\`, or claude-next*) and re-run, or pass
      CC_UNFORK_ALLOW_LIVE=1 to accept the window deliberately."
    exit 1
  fi
else
  say "live-pane gate: 0 sessions under $DST_CONFIG"
fi

# ── 4. CONVERT — build the link first, then two renames ───────────────────────────────────────────
stamp="$(date +%Y%m%d%H%M%S)" || { deny "date failed; a backup with no stamp would overwrite the only pre-migration copy"; exit 1; }
BAK="$DST.premirror-bak.$stamp"
TMPLINK="$DST_CONFIG/.hooks.unfork.$$"

[ -e "$BAK" ] && { deny "backup path $BAK already exists — refusing to overwrite it"; exit 1; }
rm -f "$TMPLINK" 2>/dev/null
if ! ln -s "$SRC" "$TMPLINK" 2>/dev/null; then
  deny "could not create the replacement symlink at $TMPLINK — the fork has NOT been moved"; exit 1
fi
if ! mv "$DST" "$BAK"; then
  rm -f "$TMPLINK" 2>/dev/null
  deny "could not move the fork aside to $BAK — nothing changed"; exit 1
fi
# ── the window is HERE: $DST does not exist between these two renames ──
if ! mv "$TMPLINK" "$DST"; then
  mv "$BAK" "$DST" 2>/dev/null && deny "the link could not be renamed into place; the fork was RESTORED to $DST" \
    || deny "the link could not be renamed into place AND the fork could not be restored. It is at: $BAK"
  rm -f "$TMPLINK" 2>/dev/null
  exit 1
fi

# ── 5. verify BY CONTENT, then print the one restore command ──────────────────────────────────────
cur="$(readlink "$DST" 2>/dev/null)"
if [ "$cur" != "$SRC" ] || [ ! -d "$DST" ]; then
  mv "$BAK" "$DST" 2>/dev/null
  deny "post-conversion verify FAILED (readlink='$cur'); the fork was restored to $DST"; exit 1
fi
say "converted: hooks -> $SRC  (was a forked real dir; backup at $BAK)"
say "restore with: rm -f \"$DST\" && mv \"$BAK\" \"$DST\""
exit 0
