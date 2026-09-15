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
# GREEN HERE HAS BEEN SHOWN TO MEAN SOMETHING. This file has twice been rebaselined onto a conf
# that moved under it, and a rebaselined suite can go green by asserting nothing — so on 2026-08-10
# every asserted site was mutation-checked: one one-line mutation of config/kitty.conf per site
# (drop the map, drop `splits` from enabled_layouts, restore kitty's 2.0 drag tolerance, set
# drag_threshold 0, contest a chord with a duplicate binding), each run against a throwaway repo
# skeleton holding a COPY of this file, and positive-controlled by running the unmutated copy
# first. Every one of them turned this suite red except the single documented survivor recorded at
# the ⌘⌥⇧O test. Re-derive it that way rather than trusting this paragraph, and never repair a red
# here by relaxing an assertion to match the conf — that is the move that produced both rebaselines
# (backlog 7174eb206d25: a vanished symptom does not void the item).
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
                             ("cmd_opt_shift_left",11,57350), ("cmd_opt_b",10,98)):
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

# cmd+shift+b is the OVERLAY, and the history is why. The built-in takes a row from the grid, so
# every press SIGWINCHes every child twice — the jitter. `window_title_bar_min_windows 1` killed the
# jitter by nailing the bars open and thereby killed the chord, which the operator refused. A padding
# reservoir paid one row permanently to buy an occasional bar, which he also refused: "Having a
# permanent row for a no CLS show/hide row is not the answer." Every in-grid option is one of those
# two, because the bar needs one cell of pixels and inside the grid it can only take or reserve.
# The overlay draws ABOVE the grid (graphics protocol z=1), so the grid never changes at all.
# INVERTED 2026-09-15, DELIBERATELY, and the previous assertion is quoted rather than deleted
# because it is the record of a decision the operator reversed, not a bug: it demanded
# `cmd_shift_b_last=launch` and forbade `toggle_window_title_bars` on this chord. He then asked
# for ONE title bar on ⌘⇧B that is draggable and shows the hand cursor, and the overlay is a
# graphics placement — PIXELS above the grid, absent from kitty's hit-test — so it can never be
# either. Draggable ⇒ real bar. The chord therefore ENDS IN the built-in now, and must still
# wipe the overlay first or the two stack, which is the photograph that started this.
@test "cmd+shift+b is the ONE bar — overlay cleared, then the real draggable bars" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # ENDS IN the built-in: without this the drag gesture does not exist at all.
  echo "$output" | grep -qE '^cmd_shift_b_last=.*toggle_window_title_bars$' || {
    echo "⌘⇧B no longer reaches the real title bars — drag-to-reorder is GONE from the chord"
    echo "the operator asked for it on"
    echo "$output"; false; }
  # …and CLEARS THE OVERLAY FIRST, so exactly one bar is on screen and it is the hit-tested one.
  # Order matters: after the toggle it would clear a strip the hold loop has already re-asserted.
  echo "$output" | grep -qE '^cmd_shift_b_last=combine :.*kitty-pane-title-overlay\.py off.*: toggle_window_title_bars$' || {
    echo "⌘⇧B no longer clears the overlay before showing the real bars — the two stack, and"
    echo "the operator grabs the painted one, which can never drag"
    echo "$output"; false; }
  grep -q 'kitty-pane-title-overlay.py' "$CONF" || { echo "overlay script not referenced"; false; }
}

# The overlay script must EXIST and parse. A binding pointing at a missing or broken script is the
# silent-dead-key failure this suite was created for: kitty reports nothing when a launch target
# fails, so only a test can see it.
@test "the overlay script referenced by the title-bar chords exists and is valid python" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  [ -f "$script" ] || { echo "missing: $script"; false; }
  [ -x "$script" ] || { echo "not executable: $script"; false; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$script" \
    || { echo "overlay script does not parse"; false; }
}

# The chord runs under `launch --type=background`, whose PATH is kitty's own plus /usr/bin:/bin —
# so `python3` there is SYSTEM python, which ships no Pillow. The script must therefore find a
# capable interpreter itself. This cost a full land to learn: the script resolved its socket, found
# all four panes, then died on ModuleNotFoundError where nothing could see it.
@test "the overlay can reach a python with Pillow, as the background launch would" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  grep -q '_ensure_pil' "$script" || { echo "no interpreter guard in the overlay"; false; }
  found=0
  for c in /usr/local/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
    [ -x "$c" ] || continue
    if "$c" -c 'import PIL' 2>/dev/null; then found=1; break; fi
  done
  [ "$found" -eq 1 ] || { echo "no interpreter on this box has Pillow — titles cannot render"; false; }
}

# q=2 is MANDATORY in every graphics escape the script emits. With q=0 the terminal's reply is
# delivered into the PROGRAM's stdin — an acknowledgement lands in whatever is running in the pane.
@test "every graphics escape in the overlay suppresses responses (q=2)" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  bad="$(grep -n '033_G' "$script" | grep -v 'q=2' || true)"
  [ -z "$bad" ] || { echo "graphics escape without q=2:"; echo "$bad"; false; }
}

# THE TILDE TRAP, kept although the binding that taught it is gone — it applies to every script
# binding in this file. kitty expands ENVIRONMENT VARIABLES in a map's command but NOT `~`: a tilde
# path throws inside kitty's own remote-control handler and the chord silently does nothing — no
# beep, no message, no reaction. That shipped once, on cmd+shift+b, and cost the operator a dead key.
@test "no map command uses a tilde path — a tilde in a binding dies silently" {
  printf '%s\n' "$(grep -E '^[[:space:]]*map[[:space:]]' "$CONF")" > "$BATS_TEST_TMPDIR/maps.out"
  ! grep -qE '^[[:space:]]*map[[:space:]].*[[:space:]]~/' "$BATS_TEST_TMPDIR/maps.out" || {
    echo "tilde path in a binding — kitty will not expand it and the chord will do nothing:"
    grep -nE '^[[:space:]]*map[[:space:]].*[[:space:]]~/' "$BATS_TEST_TMPDIR/maps.out"; false; }
  # and the positive half: the script bindings that DO exist use the ${HOME} form
  grep -qE '^[[:space:]]*map[[:space:]].*\$\{HOME\}/' "$BATS_TEST_TMPDIR/maps.out" || {
    echo "no \${HOME}-form script binding found — this guard is vacuous"; false; }
}

@test "MUTANT CONTROL: a tilde path is visible to the tilde guard" {
  MUT="$BATS_TEST_TMPDIR/mutant-tilde.conf"
  sed 's|\${HOME}/|~/|' "$CONF" > "$MUT"
  grep -qE '^[[:space:]]*map[[:space:]].*[[:space:]]~/' "$MUT" || {
    echo "CONTROL FAILED — mutation did not produce a tilde binding"; false; }
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
  #
  # THE ABSENCE OF ⌘⌃O IS DELIBERATELY NOT ASSERTED, and this is the one mutation the suite lets
  # live: re-adding `map cmd+ctrl+o detach_tab ask` to the conf leaves every test here green. That
  # is correct scope, not a hole. The retirement was a keymap-SHAPE choice — the conf's own reason
  # at §4b is "⌃ is unused by hand here", with all three O-chords probed FREE — so a returning ⌘⌃O
  # is a redundant second route to an action that still works, not the silent destructive inversion
  # the ⌘⇧D and ⌘W guards exist for. An absence assertion would instead go red the next time ⌘⌃ is
  # deliberately used for anything, i.e. it would be a tripwire on the conf's own next change.
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

# ── the overlay's two 2026-09-14 refinements: size, and the keypress budget ──────────────
#
# SIZE WAS NOT THE FREE DIAL IT LOOKED LIKE. Three rounds of "too small" were answered by
# restyling inside one cell; the fourth was answered by making the band two cells, which put the
# label at 1.46x the body's cap height and drew "way too big". Rendered at 1:1 against real body
# text, a two-cell band with SMALLER type reads worse than either extreme — the slab is what
# dominates — so the band went back to one cell and the type sits at that cell's ceiling. What is
# worth pinning is therefore NOT "bigger than the body" (at one cell that is unreachable) but that
# nothing is left on the table: the em is at the largest that fits, and the face is not the body's,
# which is what makes this read as a header at all. `measure` uses the script's OWN renderer, so it
# cannot drift from what is drawn.
#
# ── THE TWO CASES BELOW WERE INVERTED 2026-09-15; THE PARAGRAPH ABOVE IS KEPT AS THE RECORD ──
# They asserted `headroom <= 1` and `BAND_CELLS == 1`: between them they pinned the type AGAINST
# its own band (ink 0.93 of band, 1px of air) as the contract. The operator then asked for exactly
# that to be removed — "one unit larger, the band and the text together, so the text doesn't look
# oversized to its boundary container" — so the suite demanded the state the cure had to delete,
# and would have blocked it. Note WHY the old reasoning held: its decisive comparison was "a
# two-cell band with SMALLER type", which is a real finding and still true; a two-cell band with
# MODESTLY LARGER type was never in that comparison. It was rendered at 1:1 on 2026-09-15 across
# seven candidates and it is what shipped. What is pinned now is the proportion, in both
# directions — the label must OUTRANK the body and must NOT touch its band — because those are the
# two ways this has actually been wrong, three rounds in one direction and one in the other.
pil_python() {
  for c in /usr/local/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
    [ -x "$c" ] || continue
    if "$c" -c 'import PIL' 2>/dev/null; then echo "$c"; return 0; fi
  done
  return 1
}

@test "the title type breathes inside its band and outranks the body, in another register" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  PY="$(pil_python)" || skip "no interpreter with Pillow"
  run "$PY" "$script" measure
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q 'VERDICT BREATHING' || { echo "$output"; false; }
  # AIR IN PIXELS, asserted here and not only inside the script that computes it. This was
  # a 0.45-0.68 RATIO for one commit, and a ratio cannot express the choice that is actually
  # available: 0.79 is 6px of air at a 58px band and 19px at a 90px band, and the 90px band
  # was rejected on sight. The gap is what the eye reads.
  air="$(echo "$output" | sed -n 's/.*air \([0-9][0-9]*\) px above and below.*/\1/p')"
  [ -n "$air" ] || { echo "no air figure in the INK-TO-BAND line"; echo "$output"; false; }
  [ "$air" -ge 4 ] || {
    echo "only ${air}px of air each side — this shipped at 1px and was reported as the label"
    echo "looking oversized to its container; 4 is the floor that state fails"
    echo "$output"; false; }
}

# THE PLACEMENT IS QUANTISED; THE BAND IS NOT. That distinction is the whole of the 2026-09-15
# second round, and this case asserted the conflation for one commit: it demanded BAND_CELLS be a
# whole number and read that as the band's height, which made one cell and two the only two
# headers available — 45px was "oversized to its container" and 90px was "too large", with nothing
# between them. A placement shorter than the rows it spans part-paints the last row and the glyph
# tops under it read as clipped; that is what must be whole. Everything below the band is painted
# the terminal's own background, so the covered-but-unbanded row reads as a blank line.
#
# So what is pinned is the pair: the placement lands on whole cells, and the band fits inside it.
@test "the placement is whole cells and the band fits inside it" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  grep -qE '^BAND_FILL_CELLS = [0-9.]+' "$script" || {
    echo "BAND_FILL_CELLS is gone — the band height must stay a continuous dial, or the only"
    echo "headers available are one cell and two, both of which were rejected"; false; }
  PY="$(pil_python)" || skip "no interpreter with Pillow"
  run "$PY" "$script" measure
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # measure prints both numbers; the script itself asserts the whole-cell property, and the
  # regex here pins that it is still REPORTING both rather than collapsing back to one.
  echo "$output" | grep -qE 'band [0-9]+ px in a [0-9]+ px placement \([12] whole cell\(s\)\)' \
    || { echo "$output"; false; }
  echo "$output" | grep -q 'on a whole-cell placement' || { echo "$output"; false; }
  band="$(echo "$output" | sed -n 's/.*band \([0-9][0-9]*\) px in a.*/\1/p')"
  cover="$(echo "$output" | sed -n 's/.*in a \([0-9][0-9]*\) px placement.*/\1/p')"
  [ "$band" -le "$cover" ] || { echo "band $band exceeds its placement $cover"; false; }
  [ $(( cover % 45 )) -eq 0 ] || { echo "placement $cover is not a whole number of 45px cells"; false; }
}

# THE KEYPRESS MUST NOT PAY FOR PILLOW. The whole ~0.5s the operator felt was process startup —
# interpreter, a re-exec into a Pillow-capable python, the PIL import, `kitty @ ls`, the first
# `ps` — and none of it was work. The client half therefore imports os and sys and nothing else
# at module scope, and reaches the daemon over a unix socket. A stray top-level `from PIL import`
# or `import subprocess` would silently put ~60ms back on every press with no visible symptom.
@test "the keypress path imports nothing but os and sys at module scope" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  run python3 -c '
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
bad = []
for n in tree.body:
    if isinstance(n, ast.Import):
        bad += [a.name for a in n.names if a.name not in ("os", "sys")]
    elif isinstance(n, ast.ImportFrom):
        bad.append(n.module or "?")
print(" ".join(bad))
' "$script"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ] || { echo "module-scope imports beyond os/sys: $output"; false; }
}

# A STALE pid->tty MAPPING DOES NOT DEGRADE, IT PAINTS INTO A STRANGER'S TERMINAL. This code's
# output is raw escape sequences written into a device file, and pids are reused within minutes.
# So the cache is keyed by (pane_id, pid) — which a reused pid alone cannot re-mint — and pruned
# to the panes kitty just listed, so a returning pid is re-resolved rather than answered from
# memory. Asserted against the real function, with a hand-built cache entry standing in for the
# dead pane.
@test "the tty cache is keyed by pane AND pid, and pruned to the panes kitty just listed" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  PY="$(pil_python)" || skip "no interpreter with Pillow"
  run "$PY" - "$script" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("kto", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# a pane that has died, whose pid is about to be reused by a different pane
m._TTY_CACHE[(11, 4242)] = "/dev/ttys099"
out = m.pane_ttys([{"id": 12, "pid": 4242}])       # same pid, NEW pane id
assert (11, 4242) not in m._TTY_CACHE, "dead pane kept its tty in the cache"
assert out.get((12, 4242)) != "/dev/ttys099", "a reused pid inherited the dead pane's tty"
print("ok")
PYEOF
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q '^ok$' || { echo "$output"; false; }
}

# THE EM NOW SITS ABOVE THE FONT'S OWN ascent+descent, which is only safe because strip_png
# solves the baseline from the ACTUAL string's ink and steps the em down when that ink would not
# fit. Without both halves this clips silently — PIL draws past the image edge without complaint —
# so the property is asserted on RENDERED PIXELS, against the worst string we could be handed
# (accented capitals plus descenders) and a stacked-diacritic case beyond it.
@test "no title clips the band — ink stays inside it, accents and descenders included" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  PY="$(pil_python)" || skip "no interpreter with Pillow"
  run "$PY" - "$script" <<'PYEOF'
import importlib.util, io, sys
from PIL import Image
spec = importlib.util.spec_from_file_location("kto", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
H, C = m.band_geometry(45)
for t in ("\u25d0 Kitty pane-title overlay refinements",
          "\xc5\xc9\xce\xd5\xdc Kitty gjpqy accented worst case",
          "\u25d1 \xddg\u0135 Q extreme stack",
          "\u2733 CPAP"):
    im = Image.open(io.BytesIO(m.strip_png(1694, H, t, True, C))).convert("RGB")
    px = im.load()
    assert im.size[1] == C, "placement is %d px, expected %d" % (im.size[1], C)
    # only the BAND rows are searched for ink: below it the strip is ground by design, and
    # searching there would read every pixel of the blank row as "ink touching the edge".
    rows = [y for y in range(H) if any(px[x, y] != m.BAND_LIVE for x in range(0, 1694, 2))]
    assert rows, "no ink at all for %r" % t
    assert rows[0] >= 1 and rows[-1] <= H - 2, \
        "ink %d..%d touches the band edge for %r" % (rows[0], rows[-1], t)
    # and the covered-but-unbanded rows must be the terminal ground, not band colour —
    # that is what makes the row read as blank instead of as a half-painted header.
    for y in range(H, C):
        assert px[4, y] == m.GROUND, "row %d below the band is %r, not the ground" % (y, px[4, y])
print("ok")
PYEOF
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q '^ok$' || { echo "$output"; false; }
}

# THE OVERLAY SILENTLY COST US THE RE-ORDER DRAG, and nothing here noticed for a whole day.
# kitty's drag-to-reorder handle IS the real window title bar — its drag state hangs off
# `set_window_title_bar_render_data` / `set_window_being_dragged` — so a graphics placement that
# merely LOOKS like a title bar keeps the label and drops the gesture. ⌘⇧B is deliberately NOT
# `toggle_window_title_bars` (the test above pins that, and must keep pinning it), which means the
# action has to live on some OTHER chord or the gesture does not exist at all. That is the hole
# this test fills: the previous suite asserted only where the action must NOT be.
@test "the styled glance survives on ⌘⌥B — the overlay, still zero-shift" {
  run probe "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The overlay did not go away when the chords swapped; it moved. It is the only thing on this
  # box that labels a pane WITHOUT a PTY resize, so losing it to the swap would trade the whole
  # reason it was built for a chord letter.
  echo "$output" | grep -q 'cmd_opt_b_last=launch' || {
    echo "⌘⌥B is no longer the zero-shift overlay — the styled glance is gone"
    echo "$output"; false; }
  # and this chord must NOT reach the built-in: that is the row-stealing jitter the overlay
  # exists to avoid, and it now has its own chord.
  if echo "$output" | grep -qE '^cmd_opt_b_last=.*toggle_window_title_bars$'; then
    echo "the glance chord regressed to the row-stealing built-in"
    false
  fi
}

# THIS CONTROL WAS VACUOUS FOR A DAY AND NOTHING COULD SEE IT. It deleted
# `^map cmd+opt+b toggle_window_title_bars$` — a BARE-action line that stopped existing the
# moment the chord became a `combine`, so `grep -v` removed nothing, the probe read the
# unmutated file, and the exact-match check duly did not fire. A control that mutates nothing
# passes for the same reason a working one does. Re-keyed on the line that is actually in the
# file, and asserted to have REMOVED something before its verdict is believed.
@test "MUTANT CONTROL: dropping the re-order map is visible to that guard" {
  MUT="$BATS_TEST_TMPDIR/mutant-reorder.conf"
  grep -v '^map cmd+shift+b ' "$CONF" > "$MUT"
  # the mutation must have BITTEN — one line fewer, no more, no less
  before="$(wc -l < "$CONF")"; after="$(wc -l < "$MUT")"
  [ "$((before - after))" -eq 1 ] || {
    echo "CONTROL FAILED — the mutation removed $((before - after)) line(s), expected exactly 1"
    false
  }
  run probe "$MUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  if echo "$output" | grep -qE '^cmd_shift_b_last=.*toggle_window_title_bars$'; then
    echo "CONTROL FAILED — the binding survived its own deletion"
    false
  fi
}

# The real bars are the SAME feature as the overlay wearing a different face, so they carry the
# same palette. Asserted through kitty's parser rather than by grepping the file: a colour option
# it does not recognise is dropped silently, which is the failure this whole suite exists for.
@test "the real title bars carry the overlay's palette" {
  CC_TEST_CONF="$CONF" run "$KITTY" +runpy '
def main():
    import os
    from kitty.config import load_config
    o = load_config(os.environ["CC_TEST_CONF"])
    print("align=%s" % o.window_title_bar_align)
    print("active=%s" % (o.window_title_bar_active_background,))
    print("inactive=%s" % (o.window_title_bar_inactive_background,))
main()
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'align=left' || { echo "$output"; false; }
  echo "$output" | grep -q 'active=Color(47, 98, 216)' || { echo "$output"; false; }
  echo "$output" | grep -q 'inactive=Color(63, 85, 144)' || { echo "$output"; false; }
}

# A LONE PANE IS STILL A PANE. The overlay skipped any tab with fewer than two windows, on the
# reasoning that one pane needs no disambiguation — which answers a question nobody asked, since the
# label also says WHAT THE SESSION IS. Operator, 2026-09-14: the chord "doesn't work when there is
# only one split pane in the window". It failed silently: no log line, no error, just nothing drawn.
# Asserted against the real targets() with a stubbed kitty_ls, so it pins behaviour rather than text.
@test "a single-pane tab still gets a title — no minimum-pane guard" {
  script="$(dirname "$CONF")/../scripts/kitty-pane-title-overlay.py"
  PY="$(pil_python)" || skip "no interpreter with Pillow"
  run "$PY" - "$script" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("kto", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.kitty_ls = lambda sock: [{"tabs": [{"is_focused": True, "windows": [
    {"id": 1, "pid": 4242, "title": "lone pane", "is_focused": True}]}]}]
m._TTY_CACHE[(1, 4242)] = "/dev/null"          # stand in for a real tty
got = m.targets(None, False)
assert len(got) == 1, "a lone pane was skipped: %r" % (got,)
assert got[0][1] == "lone pane", got
print("ok")
PYEOF
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -q '^ok$' || { echo "$output"; false; }
}
