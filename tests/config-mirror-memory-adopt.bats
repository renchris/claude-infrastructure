#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# SC2317/SC2329 ("command appears unreachable" / "function never invoked") are the standard bats
# false-positives: the linter cannot see that `@test` bodies are invoked by the bats runner, so
# every one of them reads as dead code. File-level, because it is a property of the harness.
# (NB: no comment line here may BEGIN with the linter's own name — it parses as a directive,
# SC1073/SC1072, and aborts the scan of this entire file.)
#
# _cc_sync_memory_mirror — the ADOPT branch, and the merge branch it must not weaken.
#
# WHY THIS SUITE EXISTS. The operator's router picks a Claude account by live quota headroom, so
# accounts are used indiscriminately; per-project memory is therefore shared by symlinking
# <acct>/projects/<slug>/memory at ~/.claude's canonical copy while the sibling transcripts stay
# isolated. That worked only for slugs account 1 had already seen. A project FIRST touched on a
# non-primary account wrote a real memory/ dir there, and every later mirror run skipped it —
# `(( convert )) || continue` — waiting for a --convert that no automation ever issues
# (config-mirror-assert.sh runs the mirror in default mode at SessionStart). Measured 2026-08-22:
# 13 slugs invisible to every other account.
#
# The skip is CORRECT when both sides hold memory (a union merge is a real decision, not something
# to do under a live session) and WRONG when canonical is absent (nothing to merge, so the move is
# lossless). These tests pin BOTH halves, because a fix that only proves the new branch would
# equally pass if it had deleted the merge gate — so "--convert is still required when both sides
# hold memory" is the load-bearing negative control, not a courtesy test.

setup() {
  # Hermetic $HOME: this suite drives a mirror whose every path is $HOME/.claude*, and whose
  # isolate-set keys are built from $HOME at source time. Without this the run would read — and
  # MOVE — the operator's live project memory. Enforced by ship-land's hermeticity ratchet.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"

  # A slug stranded on $1 (an account dir name) with a memory file whose content is unique to it.
  strand() {
    mkdir -p "$HOME/$1/projects/$2/memory"
    printf 'from-%s\n' "$1" > "$HOME/$1/projects/$2/memory/$3"
  }
  canonical() {
    mkdir -p "$HOME/.claude/projects/$1/memory"
    printf 'from-canonical\n' > "$HOME/.claude/projects/$1/memory/$2"
  }
  # Run the mirror exactly as SessionStart does: DEFAULT mode, no --convert.
  sync_safe() {
    zsh -fc "source '$MIRROR'; _cc_sync_memory_mirror \"\$HOME/$1\""
  }
  sync_convert() {
    zsh -fc "source '$MIRROR'; _cc_sync_memory_mirror --convert \"\$HOME/$1\""
  }
}

@test "ADOPT: safe mode links a slug whose canonical memory does not exist" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mkdir -p "$HOME/.claude/projects"
  strand .claude-secondary proj-alpha note.md

  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]

  d="$HOME/.claude-secondary/projects/proj-alpha/memory"
  c="$HOME/.claude/projects/proj-alpha/memory"

  # THE RED-PROOF ASSERTION. Pre-fix the `continue` fires and $d is still a real directory, so
  # this fails; nothing in the fixture references a symbol the fix introduces, so the pre-fix run
  # genuinely EXECUTES and fails rather than erroring out or skipping.
  if [ ! -L "$d" ]; then
    echo "REGRESSION: stranded memory was not adopted — $d is still a real dir, invisible to every other account" >&2
    return 1
  fi
  [ -f "$c/note.md" ]
  # Readable from the OTHER side of the link — the writing session keeps reading its own memory.
  [ "$(cat "$d/note.md")" = "from-.claude-secondary" ]
}

@test "ADOPT: nothing is lost — dotfiles and subdirectories move too" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mkdir -p "$HOME/.claude/projects"
  d="$HOME/.claude-tertiary/projects/proj-beta/memory"
  mkdir -p "$d/sub"
  printf 'index\n'  > "$d/MEMORY.md"
  printf 'hidden\n' > "$d/.hidden"
  printf 'deep\n'   > "$d/sub/deep.md"

  run sync_safe .claude-tertiary
  [ "$status" -eq 0 ]

  c="$HOME/.claude/projects/proj-beta/memory"
  # A glob that silently drops dotfiles is the obvious way to write this move and loses .hidden.
  [ -f "$c/MEMORY.md" ]
  [ -f "$c/.hidden" ]
  [ -f "$c/sub/deep.md" ]
  [ -L "$d" ]
}

@test "MERGE GATE INTACT: safe mode still refuses when BOTH sides hold memory" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  canonical proj-gamma note.md
  strand .claude-secondary proj-gamma note.md

  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]

  d="$HOME/.claude-secondary/projects/proj-gamma/memory"
  # This is the control that keeps the fix honest: an over-broad adopt would clobber or link away
  # a real memory dir under a live session without ever computing the union.
  if [ -L "$d" ]; then
    echo "REGRESSION: safe mode converted a slug that needs a MERGE — the union was never computed" >&2
    return 1
  fi
  [ -d "$d" ]
  [ "$(cat "$d/note.md")" = "from-.claude-secondary" ]
  [ "$(cat "$HOME/.claude/projects/proj-gamma/memory/note.md")" = "from-canonical" ]
  [ ! -e "$d.premirror-bak" ]
}

@test "MERGE GATE INTACT: --convert still merges, backs up, and links" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  canonical proj-delta shared.md
  strand .claude-secondary proj-delta only-on-two.md

  run sync_convert .claude-secondary
  [ "$status" -eq 0 ]

  d="$HOME/.claude-secondary/projects/proj-delta/memory"
  c="$HOME/.claude/projects/proj-delta/memory"
  [ -L "$d" ]
  [ -f "$c/shared.md" ]                     # canonical's own copy survives
  [ -f "$c/only-on-two.md" ]                # the account-2-only file is folded in
  [ -d "$d.premirror-bak" ]                 # reversible
  [ "$(cat "$c/shared.md")" = "from-canonical" ]
}

@test "ORDERING: one slug stranded on TWO accounts — the second becomes a merge, not a nest" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mkdir -p "$HOME/.claude/projects"
  strand .claude-tertiary   proj-eps t.md
  strand .claude-quaternary proj-eps q.md

  run sync_safe .claude-tertiary
  [ "$status" -eq 0 ]
  run sync_safe .claude-quaternary
  [ "$status" -eq 0 ]

  c="$HOME/.claude/projects/proj-eps/memory"
  dq="$HOME/.claude-quaternary/projects/proj-eps/memory"

  # The first adopt makes canonical real, so the SECOND account is now a genuine merge and must be
  # left for --convert. The failure this pins is silent: a plain `mv "$d" "$c"` when canonical
  # already exists moves the source INSIDE it, producing "$c/memory" that no reader looks at.
  if [ -e "$c/memory" ]; then
    echo "REGRESSION: the second account's memory was nested at \$c/memory — invisible to every reader" >&2
    return 1
  fi
  [ -f "$c/t.md" ]                          # first mover became canonical
  [ -d "$dq" ]                              # second is untouched, still a real dir
  [ ! -L "$dq" ]
  [ "$(cat "$dq/q.md")" = "from-.claude-quaternary" ]

  # ...and --convert then completes it, losing neither side.
  run sync_convert .claude-quaternary
  [ "$status" -eq 0 ]
  [ -L "$dq" ]
  [ -f "$c/t.md" ]
  [ -f "$c/q.md" ]
}

@test "ADOPT is scoped: an already-shared slug is left alone (idempotent)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  mkdir -p "$HOME/.claude/projects"
  strand .claude-secondary proj-zeta note.md

  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]
  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]

  d="$HOME/.claude-secondary/projects/proj-zeta/memory"
  c="$HOME/.claude/projects/proj-zeta/memory"
  [ -L "$d" ]
  [ -f "$c/note.md" ]
  # A second pass that re-adopted would have nested the link's own target under itself.
  [ ! -e "$c/memory" ]
  [ "$(cat "$d/note.md")" = "from-.claude-secondary" ]
}

# ── Temp-slug exclusion (startup-hooks-2026-10-18 unit 1.1) ──────────────────────────────────────
# ~95% of projects/ are throwaway headless-run slugs (-private-var-folders-*, -private-tmp*). They
# must be excluded INSIDE both globs: a per-slug skip in the loop still stats and hashes every entry
# and keeps 50-86% of the walk (docs/research/startup-hooks-2026-10-18/gap-G1.md). Test (d) is the
# form pin — the only assertion a loop-level `case` skip fails.
temp_fixture() {
  canonical -private-var-folders-ab-T-tmp.X1 note.md
  canonical -private-tmp-claude-run-7 note.md
  mkdir -p "$HOME/.claude-secondary/projects/-private-tmp-stranded/memory"
  printf 'temp\n' > "$HOME/.claude-secondary/projects/-private-tmp-stranded/memory/t.md"
  canonical proj-control note.md
  canonical -Users-x-private-tmp-lookalike note.md
}

@test "TEMP SLUGS: (a) no memory link is created under a temp slug" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude-secondary/projects/-private-var-folders-ab-T-tmp.X1/memory" ]
  [ ! -e "$HOME/.claude-secondary/projects/-private-tmp-claude-run-7/memory" ]
}

@test "TEMP SLUGS: (b) a stranded real memory dir under a temp slug is not adopted" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]
  d="$HOME/.claude-secondary/projects/-private-tmp-stranded/memory"
  [ -d "$d" ]
  [ ! -L "$d" ]
  [ ! -e "$HOME/.claude/projects/-private-tmp-stranded" ]
}

@test "TEMP SLUGS: (c) the control slug is still linked" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/projects/proj-control/memory" ]
}

@test "TEMP SLUGS: (d) form pin — temp slugs never enter the slug hash" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  run zsh -fxc "source '$MIRROR'; _cc_sync_memory_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  # zsh traces `slugs[${sp:t}]=1` with its subscript UNEXPANDED, so a grep for `slugs[-private-` is
  # blind (it passes a loop-level `case` skip too — measured 2026-10-18 against that mutant). What the
  # trace does expand is the loop variable: `sp=<path>`. A temp slug the glob let through shows up
  # there, whatever the loop then does with it.
  n=$(printf '%s\n' "$output" | grep -c '> sp=.*/-private-' || true)
  if [ "$n" -ne 0 ]; then
    echo "REGRESSION: $n temp slug(s) were globbed — the exclusion must live inside the glob, not the loop" >&2
    return 1
  fi
  # Positive control: the same trace does show real slugs being globbed, so the 0 above is not blind.
  printf '%s\n' "$output" | grep -q '> sp=.*/proj-control$'
}

@test "TEMP SLUGS: (e) a slug that merely contains -private-tmp is still linked" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  run sync_safe .claude-secondary
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/projects/-Users-x-private-tmp-lookalike/memory" ]
}

# ── --slug: one slug, same rules (startup-hooks-2026-10-18 unit 5.7) ─────────────────────────────
# config-mirror-assert.sh links the session's own slug inline with --slug and leaves the rest to a
# detached sweep, so --slug must touch the named slug and nothing else, and must refuse what the
# full walk excludes.
@test "--slug: links and adopts only the named slug; temp and path-like slugs are refused" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  temp_fixture
  canonical proj-other note.md
  strand .claude-secondary proj-stranded note.md
  slug() { zsh -fc "source '$MIRROR'; _cc_sync_memory_mirror --slug '$1' \"\$HOME/.claude-secondary\""; }

  run slug proj-control
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude-secondary/projects/proj-control/memory")" = "$HOME/.claude/projects/proj-control/memory" ]
  [ ! -e "$HOME/.claude-secondary/projects/proj-other/memory" ]          # not walked
  [ ! -L "$HOME/.claude-secondary/projects/proj-stranded/memory" ]       # not walked

  run slug proj-stranded                                                 # the ADOPT branch, one slug
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/projects/proj-stranded/memory" ]
  [ -f "$HOME/.claude/projects/proj-stranded/memory/note.md" ]

  run slug -private-tmp-claude-run-7
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude-secondary/projects/-private-tmp-claude-run-7/memory" ]
  run slug -private-tmp-stranded
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.claude-secondary/projects/-private-tmp-stranded/memory" ]
  run slug ../proj-other
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude-secondary/projects/proj-other/memory" ]
  [ ! -e "$HOME/.claude-secondary/proj-other" ]

  # --convert and --slug combine in either order
  run zsh -fc "source '$MIRROR'; _cc_sync_memory_mirror --slug proj-other --convert \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/projects/proj-other/memory" ]
}
