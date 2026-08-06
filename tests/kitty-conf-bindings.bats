#!/usr/bin/env bats
# config/kitty.conf — the bindings that carry iTerm2 muscle memory into kitty, pinned against
# kitty's OWN config loader rather than against the file's text.
#
# WHY NOT grep THE FILE. A grep asserts that a line was typed, which is not the property that
# matters. kitty silently ignores an option it does not recognise and silently misplaces a pane
# when `--location=vsplit` is used outside the `splits` layout — both of which leave the text
# looking perfect. Every assertion below therefore goes through `kitty.config.load_config`, i.e.
# the same parse the running terminal performs, so a rename or a removed option in a future kitty
# fails here instead of at the operator's fingertips.
#
# THE LOAD-BEARING ONE IS ⌘⇧D. kitty ships a macOS default of cmd+shift+d -> close_window. Both it
# and ours survive into the keymap with identical (empty) conditions and the LAST one wins; ours is
# last only because a user config loads after the defaults. If that order ever inverts — an
# `include` that loads earlier, a kitty change, a careless re-order — then ⌘⇧D stops splitting the
# pane and starts CLOSING it. That is a destructive inversion with no error message, so it gets a
# test with a mutant control that proves the test can actually catch it.
#
# THE CLOSE CHORDS (⌘W / ⌃⇧W / ⌘⇧W) CARRY THE SAME HAZARD, and it has already fired once for real:
# each sits on a chord kitty ALREADY binds to a silent, unconditional close, and on 2026-08-04 one
# ⌘W killed a live Claude Code session with no prompt. The conf now routes all three through a
# confirm helper — so, exactly as with ⌘⇧D, what these tests pin is WHICH definition is last, with
# its own mutant control. An assertion here that reads `close_window` is not merely stale; it is
# asserting the destructive state the config exists to prevent.
#
# Assertions are `[ ]` / `|| false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and would be
# silently DEAD anywhere but a body's last line (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  # Fixture HOME before touching kitty. Without this the loader would see the OPERATOR's
  # ~/.config/kitty, so a stray local override there could silently decide this suite's verdict —
  # the assertions are about the config file in THIS repo and must not depend on the machine.
  # (The repo's hermeticity ratchet blocks the unfixtured form outright, and was right to.)
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CONF="$REPO/config/kitty.conf"
  KITTY="$(command -v kitty 2>/dev/null || true)"
  [ -n "$KITTY" ] || KITTY=/Applications/kitty.app/Contents/MacOS/kitty
  [ -x "$KITTY" ] || skip "kitty is not installed — these tests assert against its real config parser"
}

# Emit a flat key=value report from kitty's own parse of $1. The conf path travels in the
# ENVIRONMENT, never interpolated into the python source: a path is attacker-ish input to a code
# string, and interpolating it would make the probe's own quoting the weakest link.
#
# Everything lives inside one function with its imports INSIDE it, because kitty's `+runpy` execs
# the argument in a scope where module-level names are NOT visible to nested functions — a
# module-level `import` plus a helper function raises NameError. Cost one debugging cycle to learn.
probe() {
  CC_TEST_CONF="$1" "$KITTY" +runpy '
def main():
    import os
    from kitty.config import load_config
    o = load_config(os.environ["CC_TEST_CONF"])
    km = o.keyboard_modes[""].keymap
    def binds(mods, key):
        for k, v in km.items():
            if getattr(k, "mods", None) == mods and getattr(k, "key", None) == key:
                return [getattr(a, "definition", "") for a in v]
        return []
    print("drag_tolerance=%s" % o.window_drag_tolerance)
    print("drag_threshold=%s" % o.drag_threshold)
    print("layouts=%s" % ",".join(o.enabled_layouts))
    # mods bits: 1=shift, 2=alt, 4=ctrl, 8=cmd -- so 5=ctrl+shift, 9=cmd+shift, 10=cmd+opt,
    # 11=cmd+opt+shift. These were read off the parse below, NOT off the GLFW header, where the
    # CONTROL and ALT bits are the other way round. Guessing there probes an EMPTY chord, and an
    # empty chord fails every assertion for a reason that has nothing to do with the config.
    # keys: 100=d, 98=b, 119=w, 111=o, 57350=left.  Arrows are not ASCII, hence the 5-digit code.
    for label, mods, key in (("cmd_d",8,100), ("cmd_shift_d",9,100), ("cmd_shift_b",9,98),
                             ("cmd_w",8,119), ("ctrl_shift_w",5,119), ("cmd_shift_w",9,119),
                             ("cmd_shift_o",9,111), ("cmd_opt_o",10,111), ("cmd_opt_shift_o",11,111),
                             ("cmd_opt_shift_left",11,57350)):
        b = binds(mods, key)
        print("%s_n=%d" % (label, len(b)))
        print("%s_last=%s" % (label, b[-1] if b else ""))
main()
' 2>&1
}

# ── the split bindings ───────────────────────────────────────────────────────────────

@test "cmd+d splits vertically (pane to the RIGHT, iTerm2 Split Vertically)" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The trailing kitty-split-cwd.sh is part of the assertion, not incidental. --cwd=current alone
  # lands the split in the POOL WORKTREE the source pane is running from, not the main checkout
  # (config/kitty.conf §3 measured all four --cwd special values agreeing on the worktree), so the
  # helper does the redirect that no kitty option can. Dropping it re-opens that bug silently.
  #
  # -F, not a regex: the expected definition carries a literal ${HOME}. kitty stores the launch
  # definition VERBATIM and expands it only at launch time, so this stays independent of the
  # fixtured HOME — but it must be matched as text, and the single quotes stop the shell too.
  echo "$output" | grep -qxF 'cmd_d_last=launch --location=vsplit --cwd=current ${HOME}/.claude/bin/kitty-split-cwd.sh' || { echo "$output"; false; }
}

@test "cmd+shift+d splits horizontally and NOT close_window — the last-wins inversion guard" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # n=2 is expected and healthy: kitty's default close_window plus ours. What must hold is WHICH
  # of the two is last, because that is the one that fires.
  # An exact whole-line match already excludes close_window, so a separate negative assertion here
  # would be redundant — and the destructive case is proven positively by the MUTANT CONTROL below,
  # which is stronger evidence than a negative that can pass for the wrong reason.
  # The helper tail and the -F are load-bearing for the same reasons given on ⌘D above.
  echo "$output" | grep -qxF 'cmd_shift_d_last=launch --location=hsplit --cwd=current ${HOME}/.claude/bin/kitty-split-cwd.sh' || { echo "$output"; false; }
}

@test "MUTANT CONTROL: dropping our cmd+shift+d line lets close_window win, and the guard sees it" {
  # Without this the guard above could be vacuous — it would pass on any config that merely fails
  # to bind close_window. Strip only our hsplit line and prove the inversion actually appears.
  MUT="$BATS_TEST_TMPDIR/mutant.conf"
  grep -v 'launch --location=hsplit' "$CONF" > "$MUT"
  # `! A || { …; false; }` is the live form for a NEGATIVE assertion. `A && { …; false; }` is
  # and-absorbed by errexit (dead), and the mechanical `A && { …; false; } || false` repair is worse
  # still: it fails on BOTH branches. Verified by running it — it turned three passing tests red.
  ! grep -q 'location=hsplit' "$MUT" || { echo "mutation did not apply"; false; }
  run probe "$MUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The mutant MUST exhibit exactly the failure the guard is written to catch.
  echo "$output" | grep -qx 'cmd_shift_d_last=close_window' || {
    echo "CONTROL FAILED — the guard cannot distinguish the destructive config:"; echo "$output"; false; }
}

@test "the splits layout is enabled — without it --location=vsplit is silently ignored" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q '^layouts=splits' || { echo "$output"; false; }
}

# ── the drag gestures ────────────────────────────────────────────────────────────────

@test "window_drag_tolerance is raised above kitty's default so a divider is grabbable" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  TOL=$(echo "$output" | sed -n 's/^drag_tolerance=//p')
  [ -n "$TOL" ] || { echo "no drag_tolerance in probe output"; echo "$output"; false; }
  # kitty's default is 2.0 against a 0.5pt border — technically draggable, practically not.
  # A large negative value is kitty's documented OFF switch, so guard that end too.
  awk -v t="$TOL" 'BEGIN { exit !(t > 2.0 && t < 40) }' || { echo "drag tolerance $TOL is not a usable grab region"; false; }
}

@test "cmd+shift+b toggles window title bars — the only handle for drag-to-reorder" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_shift_b_last=toggle_window_title_bars' || { echo "$output"; false; }
}

@test "drag_threshold stays non-zero — 0 disables ALL dragging in kitty" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # Written to a file rather than piped: `cmd | grep -q PAT` can report FALSE ON A MATCH under
  # pipefail, because grep exits at the first hit and the producer is SIGPIPEd (141). This repo has
  # already lost a production poller to that inversion, so a negative assertion never uses a pipe.
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/probe.out"
  ! grep -qx 'drag_threshold=0' "$BATS_TEST_TMPDIR/probe.out" || { echo "drag_threshold=0 disables dragging entirely"; false; }
  grep -q '^drag_threshold=' "$BATS_TEST_TMPDIR/probe.out" || { echo "$output"; false; }
}

# ── moving a pane out of its tab (§4b), i.e. onto another monitor ────────────────────
#
# These are pinned for the same reason as everything above: the failure is SILENT. A pane can only
# reach a second monitor by being detached into an OS window that sits there, and if the binding
# quietly stops resolving there is no error — the key simply does nothing, which is exactly how
# `move_window` on an axis with no neighbour already behaves. `_n=1` is the collision guard: it
# asserts our binding is the ONLY one on that chord, so a future kitty default landing on ⌘⇧O
# (the ⌘⇧D hazard, one key over) turns this red instead of silently taking the chord.

@test "cmd+shift+o detaches a pane into a chosen tab — the only cross-OS-window route" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_shift_o_last=detach_window ask' || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_shift_o_n=1' || { echo "chord is contested — see the ⌘⇧D hazard"; echo "$output"; false; }
}

@test "cmd+opt+o detaches to a new OS window and cmd+opt+shift+o moves the whole tab" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # detach_tab is on ⌘⌥⇧O, not ⌘⌃O: the ⌘⌃ chords were retired wholesale (1d507193) to keep the
  # arrow-family shape ⌘⌥ = neighbour, ⌘⇧ = move, ⌘⌥⇧ = move to edge. Probing the retired chord
  # reads n=0 and an empty definition, which fails as a missing binding rather than a moved one.
  echo "$output" | grep -qx 'cmd_opt_o_last=detach_window' || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_opt_shift_o_last=detach_tab ask' || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_opt_o_n=1' || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_opt_shift_o_n=1' || { echo "$output"; false; }
}

@test "move_to_screen_edge is bound — move_window cannot place a pane with no neighbour to swap" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # ⌘⌥⇧← for the same reason as detach_tab above — ⌘⌃ retired in 1d507193.
  echo "$output" | grep -qx 'cmd_opt_shift_left_last=layout_action move_to_screen_edge left' || { echo "$output"; false; }
}

# ── the close bindings, which share the ⌘⇧D hazard ───────────────────────────────────
#
# All three close chords route through kitty-confirm-close instead of kitty's own close action,
# because a bare close is unconditional and silent and once cost a live session (header, above).
# kitty ALREADY binds a close to each of the three — a DIFFERENT one per chord, which is why each
# is named separately below rather than matched by a shared pattern:
#     ⌘W  -> close_tab      ⌃⇧W -> close_window      ⌘⇧W -> close_os_window
# So each is a last-wins pair exactly like ⌘⇧D, and n=2 is the healthy reading. The count is
# deliberately NOT asserted: kitty dropping one of its own defaults would take a chord to n=1 with
# our helper still last and the behaviour unchanged, and a test that went red on that would be
# reporting a benign upstream change as a regression.

@test "the close chords ask first — the confirm helper wins over kitty's silent close" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # -F for the same reason as the split bindings: the definition carries a literal ${HOME}.
  echo "$output" | grep -qxF 'cmd_w_last=launch --type=background ${HOME}/.claude/bin/kitty-confirm-close window' || { echo "$output"; false; }
  echo "$output" | grep -qxF 'ctrl_shift_w_last=launch --type=background ${HOME}/.claude/bin/kitty-confirm-close window' || { echo "$output"; false; }
  echo "$output" | grep -qxF 'cmd_shift_w_last=launch --type=background ${HOME}/.claude/bin/kitty-confirm-close os-window' || { echo "$output"; false; }
}

@test "MUTANT CONTROL: dropping the confirm helper lets the silent close win, and the guard sees it" {
  # Without this the guard above is vacuous in the same way the ⌘⇧D one would be: it would pass on
  # any config that merely fails to bind a close at all. Strip our three helper lines and prove the
  # unprompted kill actually reappears as the WINNING definition on all three chords.
  MUT="$BATS_TEST_TMPDIR/mutant-close.conf"
  grep -v 'kitty-confirm-close' "$CONF" > "$MUT"
  ! grep -q 'kitty-confirm-close' "$MUT" || { echo "mutation did not apply"; false; }
  run probe "$MUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_w_last=close_tab' || {
    echo "CONTROL FAILED — the guard cannot distinguish the silent-close config:"; echo "$output"; false; }
  echo "$output" | grep -qx 'ctrl_shift_w_last=close_window' || { echo "$output"; false; }
  echo "$output" | grep -qx 'cmd_shift_w_last=close_os_window' || { echo "$output"; false; }
}
