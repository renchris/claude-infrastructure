#!/usr/bin/env bats
# handoff-fire: the headless anchor probe has THREE states, and only ONE of them may mint a window.
#
# Regression under test (2026-07-30). `resolve_headless_anchor` returned 1 both when it had
# DETERMINED that iTerm2 holds no panes and when the probe had FAILED to determine anything
# (it2py's bare `except Exception: sys.exit(1)`, or hf_bounded's 124 on timeout). The caller's
# `ares="$(resolve_headless_anchor || true)"` then discarded the status entirely and branched on
# emptiness, so BOTH fell through to the fresh-window fallback. Measured effect: ~12 undestroyable
# iTerm2 windows/hour while 39 panes were live the whole time, self-amplifying because each leaked
# window congests the API the next probe depends on.
#
# These assertions are structural (they read the shipped source), because the failing path needs a
# congested live iTerm2 to reproduce and cannot be summoned in CI. A structural guard that cannot
# fail is worthless, so each one is paired with a RED control proving it fails on the old text.

setup() {
  # HERMETIC: fixture $HOME before anything else. These assertions only read the shipped source,
  # but handoff-fire.sh reads $HOME/.claude/cc-roles/desk, and an unfixtured suite would run
  # against the operator's live ~/ — which the repo's test-hermeticity ratchet rejects outright.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/cc-roles"
  # Pin the capacity gate off: handoff-fire refuses a net-new fire above 2.0/core, and this box
  # lives well above that, so an ambient suite would go red-by-LOAD rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off

  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  FIRE="$REPO/scripts/handoff-fire.sh"
  [ -f "$FIRE" ] || skip "handoff-fire.sh not found at $FIRE"
}

# ── the probe distinguishes the three states ──────────────────────────────────────────

@test "anchor probe emits a parseable NO-LIVE-SESSION token instead of a bare rc=1" {
  # The python must ANNOUNCE emptiness on stdout. rc alone cannot carry it: the heredoc's
  # `except Exception: sys.exit(1)` produces the identical status.
  grep -q 'NO-LIVE-SESSION' "$FIRE"
  # and it must be appended to `out` (stdout), not merely printed to stderr
  grep -A2 'no live iTerm2 session to anchor to' "$FIRE" | grep -q 'out.append("NO-LIVE-SESSION")'
}

@test "resolve_headless_anchor maps the token to 1 and every other failure to 2" {
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$FIRE'"
  [ "$status" -eq 0 ]
  # determined-empty -> 1
  echo "$output" | grep -q 'NO-LIVE-SESSION) return 1'
  # probe failure -> 2 (never 1, which would re-enable the mint)
  echo "$output" | grep -q 'return 2'
  # a non-zero it2py status must NOT be collapsed into the empty verdict
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$FIRE' | grep -qE 'it2py anchor .*\|\| return 1'"
  [ "$status" -ne 0 ]
}

@test "the probe no longer swallows its own failure silently" {
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$FIRE'"
  # an inconclusive result must say so on stderr — a silent probe failure is unfalsifiable later
  echo "$output" | grep -qi 'inconclusive'
}

# ── the caller honours them ───────────────────────────────────────────────────────────

@test "caller captures the status rather than discarding it with || true" {
  run bash -c "grep -n 'resolve_headless_anchor' '$FIRE' | grep -v '^.*#' | grep -v 'resolve_headless_anchor()'"
  [ "$status" -eq 0 ]
  # the old, leaking shape must be gone. `run` + explicit status, never a bare `! cmd` — a bare
  # negation cannot fail a bats test, which is what tests/bats-assert-liveness.bats ratchets on.
  run grep -q 'resolve_headless_anchor || true' "$FIRE"
  [ "$status" -ne 0 ]
  # the status must be bound to a variable
  grep -q 'ares="$(resolve_headless_anchor)" || arc=$?' "$FIRE"
}

@test "ONLY the determined-empty state may reach spawn_frontmost" {
  # Absolute line numbers from the shipped file — no sed ranges, whose quoting silently ran to EOF
  # and made this assertion vacuous on its first draft.
  elif_line=$(grep -n 'elif \[ "\$arc" != 1 \]; then' "$FIRE" | head -1 | cut -d: -f1)
  refuse_line=$(grep -n 'anchor probe INCONCLUSIVE' "$FIRE" | head -1 | cut -d: -f1)
  # the window fallback that MATTERS is the first SURFACE="window" AFTER the elif — the one at the
  # top of the file is the --window flag parser and is not part of this path
  window_line=$(grep -n 'SURFACE="window"' "$FIRE" | awk -F: -v e="$elif_line" '$1>e {print $1; exit}')

  [ -n "$elif_line" ]
  [ -n "$refuse_line" ]
  [ -n "$window_line" ]

  # inconclusive arm comes first, and refuses before anything can be minted
  [ "$elif_line" -lt "$refuse_line" ]
  [ "$refuse_line" -lt "$window_line" ]

  # and it returns non-zero rather than falling through into the fallback
  run bash -c "sed -n '${refuse_line},$((refuse_line+5))p' '$FIRE'"
  echo "$output" | grep -q 'return 1'
}

# ── RED controls: each guard must be able to FAIL ─────────────────────────────────────

@test "RED CONTROL: the pre-fix source shape fails every structural guard above" {
  tmp="$BATS_TEST_TMPDIR/prefix.sh"
  cp "$FIRE" "$tmp"
  # reconstruct the ORIGINAL two lines that carried the defect
  perl -0pi -e 's/    ares="\$\(resolve_headless_anchor\)" \|\| arc=\$\?/    ares="\$(resolve_headless_anchor || true)"/' "$tmp"
  perl -0pi -e 's/    NO-LIVE-SESSION\) return 1 ;;\n//' "$tmp"

  # the leaking caller shape is now present again → the guard that forbids it must trip
  grep -q 'resolve_headless_anchor || true' "$tmp"
  # and the status-capture shape is gone → its guard must trip
  run grep -q 'ares="$(resolve_headless_anchor)" || arc=$?' "$tmp"
  [ "$status" -ne 0 ]
  # and the token mapping is gone → its guard must trip
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$tmp' | grep -q 'NO-LIVE-SESSION) return 1'"
  [ "$status" -ne 0 ]
}

@test "RED CONTROL: a probe failure must not be spellable as the empty verdict" {
  # If someone reintroduces `|| return 1` on the it2py call, the dedicated guard must catch it.
  tmp="$BATS_TEST_TMPDIR/regress.sh"
  cp "$FIRE" "$tmp"
  # The sabotaged line now also carries the pane cap as argv[3] (room-aware anchoring). This
  # pattern must TRACK the real line — when it did not, the substitution silently no-op'd, no
  # regression was produced, and the control failed instead of proving anything. A control that
  # can no longer reproduce the defect is inert, which is worse than absent.
  perl -0pi -e 's/^  out="\$\(it2py anchor .*\|\| rc=\$\?$/  out="\$(it2py anchor "\$desk" 2>\/dev\/null)" || return 1/m' "$tmp"
  # prove the sabotage actually landed before asserting on it
  grep -q 'it2py anchor "\$desk" 2>/dev/null)" || return 1' "$tmp"
  run bash -c "sed -n '/^resolve_headless_anchor()/,/^}/p' '$tmp'"
  # the regressed text matches the forbidden pattern the real guard rejects
  echo "$output" | grep -qE 'it2py anchor .*\|\| return 1'
}

# ── the shipped script still parses ───────────────────────────────────────────────────

@test "handoff-fire.sh remains syntactically valid" {
  run bash -n "$FIRE"
  [ "$status" -eq 0 ]
}

# ── Metal-gate room awareness (2026-07-30) ────────────────────────────────────────────
# iTerm2 kills Metal for a WHOLE TAB at sessions.count >= 6. The operator needs ~30 sessions
# VISIBLE at all times, so the degrade may never be a background tab (invisible AND always
# CPU-rendered) — it must be a window (foreground tab => keeps Metal, and it stays swipeable).

@test "the pane cap defaults to 5, not 6 — -ge 6 permits a 6th pane and kills Metal" {
  grep -q 'CC_FIRE_MAX_PANES:-5' "$FIRE"
  run grep -q 'CC_FIRE_MAX_PANES:-6' "$FIRE"
  [ "$status" -ne 0 ]
}

@test "the anchor probe is told the cap, so it can prefer a tab with room" {
  grep -q 'it2py anchor "$desk" "${CC_FIRE_MAX_PANES:-5}"' "$FIRE"
  # and the python must actually consume argv[3] as the cap
  grep -q 'cap = int(sys.argv\[3\])' "$FIRE"
}

@test "anchor prefers a tab with ROOM before falling back to a full one" {
  run bash -c "sed -n '/ROOM-AWARE ANCHORING/,/if cand is None:/p' '$FIRE'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '_has_room'
  echo "$output" | grep -q 'len(t2.sessions) < cap'
}

@test "overflow degrades to a WINDOW, never a background tab" {
  elif_line=$(grep -n 'every tab is at the cap' "$FIRE" | head -1 | cut -d: -f1)
  [ -n "$elif_line" ]
  # within the overflow arm, the surface must be window and must NOT be bg-tab
  run bash -c "sed -n '${elif_line},$((elif_line+12))p' '$FIRE'"
  echo "$output" | grep -q 'SURFACE="window"'
  run bash -c "sed -n '${elif_line},$((elif_line+12))p' '$FIRE' | grep -q 'SURFACE=\"bg-tab\"'"
  [ "$status" -ne 0 ]
}

@test "the overflow arm MINTS the window itself — SURFACE alone would hit no case arm" {
  # spawn()'s SURFACE=window dispatch is above this point and the case has no `window` arm,
  # so setting SURFACE without spawning would silently launch nothing.
  line=$(grep -n 'every tab is at the cap' "$FIRE" | head -1 | cut -d: -f1)
  run bash -c "sed -n '${line},$((line+14))p' '$FIRE'"
  echo "$output" | grep -q 'spawn_frontmost'
  echo "$output" | grep -q 'it2_land'
}

@test "the dry-run preview mirrors all three states, not two" {
  run bash -c "sed -n '/dry_anchor_note()/,/^      else\$/p' '$FIRE'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INCONCLUSIVE'
  echo "$output" | grep -q 'DETERMINED to hold zero live panes'
  # the old collapsing shape must be gone from the preview
  run grep -q 'resolve_headless_anchor 2>/dev/null || true' "$FIRE"
  [ "$status" -ne 0 ]
}
