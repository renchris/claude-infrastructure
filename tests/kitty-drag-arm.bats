#!/usr/bin/env bats
# kitty-drag-arm — W7's coupling test: THE LANDED DIFF ARMS NOTHING.
#
# WHAT THIS GUARDS. config/kitty.conf's section 8 ends with `globinclude drag-arm.d/*.conf`. That
# one line is live in the operator's 11-13-pane terminal ~100ms after the shared checkout advances:
# ~/.config/kitty/kitty.conf is a SYMLINK into that checkout and kitty runs a
# `kitten __watch_conf__ <pid> 100` child that resolves symlinks whole and SIGUSR1s kitty on ANY
# write to that directory. Arming therefore happens at CONVERGE time, not at test time
# (docs/plans/KITTY_DRAG_ACTION.md § 2).
#
# The whole safety argument is that the glob matches NOTHING in the tracked tree. That is one
# sentence, it is invisible in review, and any of these would break it silently:
#   - someone renames drag.conf.example -> drag.conf "to make it work"
#   - someone uncomments the arming line inside the example
#   - someone adds config/drag-arm.d/anything.conf
#   - someone moves the globinclude up the file, where a later section 3/6 line overrides it
#   - kitty-setup.sh starts symlinking the live drop-in back into the repo, so that ARMING becomes
#     an edit to a tracked file that a land or a deploy-live fast-forward can clobber
# None of those errors. Each one either arms the operator's live terminal from a landed diff, or
# takes his armed state out of his hands. This suite is the only thing that says so.
#
# MEASURED 2026-09-16 on the operator's own kitty 0.48.2, by PARSING configs
# (`kitty +runpy 'from kitty.config import load_config; …'`) — no window launched, no live socket
# touched, nothing signalled:
#   - `globinclude` is real here:  kitty.conf.utils.include_keys
#       -> ('include', 'globinclude', 'envinclude', 'geninclude')
#   - a glob matching NOTHING is SILENT: directory absent / directory empty / present but
#     ZERO-BYTE drag.conf each gave rc=0, 0 bytes of stderr, mousemap unchanged at 32.
#     POSITIVE CONTROL on the instrument: a drop-in holding a bad directive DID speak (64 bytes,
#     "Ignoring unknown config key"), so the silence is informative. Note the channel is STDERR —
#     `accumulate_bad_lines` stayed empty even then.
#     NEGATIVE CONTROL: a drop-in holding one real mouse_map took the mousemap 32 -> 34, so the
#     glob is not a no-op.
#   - the real edited config/kitty.conf parses at rc=0 with 0 bytes of stderr, with
#     config/drag-arm.d/ present and holding only drag.conf.example — i.e. the `.example` suffix
#     is genuinely invisible to the glob, not merely believed to be.
#   - the glob resolves relative to the path kitty is GIVEN, not the resolved symlink target:
#     loading via a symlinked kitty.conf read the LIVE-side drop-in (0.99) where loading via the
#     real path read the checkout-side one (0.11), and emptying both fell back to kitty's own
#     default (-1.0). That is why the live drop-in belongs at ~/.config/kitty/drag-arm.d/.
#   - placement is load-bearing: with the globinclude LAST the drop-in won cmd+shift+left, with it
#     FIRST the top-level line won. Case 2 pins LAST for that reason.
#
# ASSERTION LIVENESS. A bare `! grep -q …` mid-body is DEAD under bats' errexit and always passes,
# so every negative here is written `if grep -q X f; then … return 1; fi`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CONF="$REPO/config/kitty.conf"
  ARMDIR="$REPO/config/drag-arm.d"
  EXAMPLE="$ARMDIR/drag.conf.example"
  SETUP="$REPO/scripts/kitty-setup.sh"
}

@test "kitty.conf carries the globinclude drop-in directive" {
  grep -Eq '^[[:space:]]*globinclude[[:space:]]+drag-arm\.d/\*\.conf[[:space:]]*$' "$CONF" || {
    echo "config/kitty.conf has no 'globinclude drag-arm.d/*.conf' line."
    echo "Without it the drop-in is never read and arming does nothing."
    false; }
}

@test "the globinclude is the LAST directive in kitty.conf — measured last-wins" {
  # Includes apply in file order and the last writer of a trigger wins. Measured both directions
  # on cmd+shift+left (mods=9): globinclude LAST -> the drop-in won; globinclude FIRST -> the
  # top-level line won. Moving this block up would let a section 3/6 binding silently override the
  # operator's armed chord, with nothing erroring.
  last="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" | tail -1)"
  echo "last non-comment line: [$last]"
  [[ "$last" =~ ^[[:space:]]*globinclude[[:space:]]+drag-arm\.d/\*\.conf[[:space:]]*$ ]]
}

@test "config/drag-arm.d/drag.conf.example exists" {
  [ -f "$EXAMPLE" ] || { echo "missing: $EXAMPLE"; false; }
}

@test "the example's NAME cannot match the glob — this is the safety property, not a convention" {
  # `.example` is what makes the tracked tree inert BY CONSTRUCTION rather than by anyone
  # remembering to keep it empty: even if config/drag-arm.d/ were symlinked into the live config
  # dir, or a sandbox pointed KITTY_CONFIG_DIRECTORY at this repo's config/, kitty could not
  # include a file whose name does not match *.conf.
  base="$(basename "$EXAMPLE")"
  case "$base" in
    *.conf) echo "$base matches *.conf — it would be INCLUDED by the globinclude"; return 1 ;;
  esac
  [ "$base" = "drag.conf.example" ]
}

@test "🚨 the tracked tree contains NO config/drag-arm.d/*.conf — the landed diff arms nothing" {
  # THE assertion of this wave. Two arms on purpose, because they fail in different directions:
  # git ls-files is blind to an untracked file a working tree is about to grow, and a working-tree
  # glob is blind to a file that is tracked but deleted on disk. Either state is a live-terminal
  # arming risk, so both are refused.
  #
  # ARM 1 — the working tree.
  found=""
  for f in "$ARMDIR"/*.conf; do [ -e "$f" ] && found="$found $f"; done
  if [ -n "$found" ]; then
    echo "working tree holds arming drop-in(s):$found"
    echo "config/drag-arm.d/ may hold NOTHING matching *.conf — that glob is live in kitty.conf."
    return 1
  fi
  # ARM 2 — what git would actually land.
  run git -C "$REPO" ls-files -- 'config/drag-arm.d/*.conf'
  [ "$status" -eq 0 ] || { echo "git ls-files failed: $output"; return 1; }
  if [ -n "$output" ]; then
    echo "TRACKED arming drop-in(s): $output"
    return 1
  fi
  # POSITIVE CONTROL on ARM 2, so its empty answer is informative rather than a broken pathspec.
  # It deliberately does NOT control on config/drag-arm.d/* : before this wave is committed the
  # example is untracked, so that query is legitimately empty and the control would convict the
  # instrument for a fact about the commit. Controlling on the same PATHSPEC SHAPE over a
  # directory with known-tracked .conf files proves the mechanism instead — which is the property
  # ARM 2 is relying on.
  run git -C "$REPO" ls-files -- 'config/*.conf'
  echo "control (same pathspec shape, known-tracked dir): $output"
  [ "$status" -eq 0 ] || { echo "control query failed: $output"; return 1; }
  [[ "$output" == *"config/kitty.conf"* ]]
}

@test "the example's arming line is COMMENTED OUT" {
  # An uncommented mouse_map in the example is only one rename away from being live, and reviewers
  # read a commented block as inert. Refuse any mouse_map line that is not behind a '#'.
  if grep -Eq '^[[:space:]]*mouse_map[[:space:]]' "$EXAMPLE"; then
    echo "drag.conf.example carries an UNCOMMENTED mouse_map line:"
    grep -nE '^[[:space:]]*mouse_map[[:space:]]' "$EXAMPLE"
    return 1
  fi
  # Positive control: the commented arming line must actually still be there. Without this the
  # case passes just as well on an empty file, i.e. it would credit deleting the example.
  grep -Eq '^[[:space:]]*#[[:space:]]*mouse_map[[:space:]]' "$EXAMPLE" || {
    echo "no commented-out mouse_map template left in the example — nothing to arm from"; false; }
}

@test "the example refuses to ship a chosen chord — W4 has not ruled" {
  # The plan gates the chord on W4, a hand-driven gate. A concrete chord sitting uncommented in a
  # file named '.example' is the shape someone copies verbatim.
  grep -q 'CHORD' "$EXAMPLE" || { echo "no <CHORD> placeholder — did someone hardcode a chord?"; false; }
}

@test "kitty-setup.sh creates the live drop-in as a REAL dir and REAL file, never a symlink" {
  # Executes ONLY section 1b, extracted, with KCONF_DIR fixtured into the test tmpdir. The whole
  # script is deliberately NOT run: it writes ~/.config/kitty, rc files and ~/.claude/bin symlinks,
  # and ~/.config/kitty is the operator's LIVE terminal config (plan § 2 S1).
  frag="$BATS_TEST_TMPDIR/frag.sh"
  sed -n '/^# ── 1b\. the window-drag ARMING drop-in/,/^# ── 2\./p' "$SETUP" | sed '$d' > "$frag"
  [ -s "$frag" ] || { echo "could not extract section 1b from $SETUP"; false; }
  grep -q 'drag-arm.d' "$frag" || { echo "extracted fragment does not mention drag-arm.d:"; cat "$frag"; false; }

  KCONF_DIR="$BATS_TEST_TMPDIR/kcfg"; mkdir -p "$KCONF_DIR"
  run env KCONF_DIR="$KCONF_DIR" MODE=apply bash -c '
    ok(){ printf "OK %s\n" "$*"; }; no(){ printf "NO %s\n" "$*"; }; info(){ :; }
    . "$1"' _ "$frag"
  echo "fragment output: $output"
  [ "$status" -eq 0 ] || { echo "fragment exited $status"; return 1; }

  [ -d "$KCONF_DIR/drag-arm.d" ] || { echo "drag-arm.d was not created"; return 1; }
  if [ -L "$KCONF_DIR/drag-arm.d" ]; then
    echo "drag-arm.d is a SYMLINK — arming would become an edit to a tracked file"; return 1
  fi
  [ -f "$KCONF_DIR/drag-arm.d/drag.conf" ] || { echo "drag.conf was not created"; return 1; }
  if [ -L "$KCONF_DIR/drag-arm.d/drag.conf" ]; then
    echo "drag.conf is a SYMLINK — a land or deploy-live could clobber the operator's armed state"
    return 1
  fi
  # created EMPTY: the disarmed state
  [ ! -s "$KCONF_DIR/drag-arm.d/drag.conf" ] || {
    echo "drag.conf was created non-empty — setup must never arm anything"
    cat "$KCONF_DIR/drag-arm.d/drag.conf"; false; }
}

@test "kitty-setup.sh never overwrites an existing drag.conf — that file IS the armed state" {
  # Re-running setup must not silently disarm (or arm) the operator's live terminal. The contents
  # of this file are his decision, not the installer's.
  frag="$BATS_TEST_TMPDIR/frag.sh"
  sed -n '/^# ── 1b\. the window-drag ARMING drop-in/,/^# ── 2\./p' "$SETUP" | sed '$d' > "$frag"
  KCONF_DIR="$BATS_TEST_TMPDIR/kcfg2"; mkdir -p "$KCONF_DIR/drag-arm.d"
  printf 'mouse_map cmd+shift+left press grabbed,ungrabbed mouse_selection normal\n' \
    > "$KCONF_DIR/drag-arm.d/drag.conf"
  sentinel="$(cat "$KCONF_DIR/drag-arm.d/drag.conf")"

  run env KCONF_DIR="$KCONF_DIR" MODE=apply bash -c '
    ok(){ printf "OK %s\n" "$*"; }; no(){ printf "NO %s\n" "$*"; }; info(){ :; }
    . "$1"' _ "$frag"
  echo "fragment output: $output"
  [ "$status" -eq 0 ] || { echo "fragment exited $status"; return 1; }

  after="$(cat "$KCONF_DIR/drag-arm.d/drag.conf")"
  [ "$after" = "$sentinel" ]
}

@test "kitty.conf states the disarm rule — emptying, never deletion" {
  # Plan § 2.2 M2, measured: a DELETION does not fire kitty's config watcher, so a doc that says
  # "delete the file to disarm" leaves the binding live. The rule has to travel with the directive.
  grep -q 'DISARM BY EMPTYING THE FILE, NEVER BY DELETING IT' "$CONF" || {
    echo "the disarm rule is missing from config/kitty.conf's section 8"; false; }
}
