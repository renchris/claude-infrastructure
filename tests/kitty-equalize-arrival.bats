#!/usr/bin/env bats
# Panes even themselves out — on REMOVAL (kitty does it) and on ARRIVAL (we do it).
#
# THE SPLIT THIS SUITE PINS, because it is the whole design and it is not obvious:
#   removal  kitty's Tab.detach_window -> post_window_removal_update -> layout.on_window_removed,
#            whose body is `if layout_opts.equalize_on_close: return self.equalize_biases()`.
#            Config-only, no process, no poll. Covers close AND move-out.
#   arrival  kitty has NO on_window_added hook, so every caller that CREATES or RE-HOMES a pane
#            squares up the destination itself. Three callers, one idiom.
#
# 🚨 THE IDIOM IS `--self`, AND `--match` IS THE TRAP IT REPLACES. `equalize` is a TAB-level
# action and kitty routes tab actions through the FOCUSED tab, so
# `kitty @ action --match id:N layout_action equalize` returns rc 0, writes nothing to stderr and
# DOES NOTHING. Measured 2026-09-19 as a three-arm control (source / destination / an untouched
# third tab): --match left the destination at spread 100, --self took it to spread 0, and neither
# touched the control. A test that asserted a return code here would pass on the broken form —
# kitty also exits 0 on an unknown action name — so the live verifier asserts COLUMN WIDTHS out of
# `kitty @ ls` instead: scripts/checks/kitty-equalize-verify.sh.
#
# WHAT THIS FILE CAN AND CANNOT DO. The conf assertion runs kitty's real parser and carries a
# mutant control. The caller assertions are structural: they pin the idiom at each site so a
# future edit cannot quietly regress one to the bare or --match form. Behaviour under a running
# kitty belongs to the verifier above, which needs a live terminal and is therefore not in CI.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # bin/it2-kitty READS these, and this repo injects them into every pane it launches — so every
  # descendant of a fired pane carries them, bats included. Inheriting one makes the suite behave
  # differently when an agent runs it from a fired pane than anywhere else, which surfaces as a
  # genuine-looking trunk red. Taking a position is mandatory (test-hermeticity ratchet); these
  # assertions are static reads of the file, so the position is "absent".
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CONF="$REPO/config/kitty.conf"
  KITTY="$(command -v kitty 2>/dev/null || true)"
  [ -n "$KITTY" ] || KITTY=/Applications/kitty.app/Contents/MacOS/kitty
}

# Resolve the FIRST enabled layout through kitty's own loader and layout factory, so a rename or
# a dropped option in a future kitty fails here rather than at the operator's fingertips.
probe_opt() {
  CC_TEST_CONF="$1" "$KITTY" +runpy '
def main():
    import os
    from kitty.config import load_config
    from kitty.layout.interface import create_layout_object_for
    o = load_config(os.environ["CC_TEST_CONF"])
    print("layouts=%s" % ",".join(o.enabled_layouts))
    l = create_layout_object_for(o.enabled_layouts[0], 1, 1)
    print("equalize_on_close=%s" % l.layout_opts.equalize_on_close)
main()'
}

@test "removal: kitty's own parser resolves equalize_on_window_close to True" {
  [ -x "$KITTY" ] || skip "kitty is not installed — this asserts against its real config parser"
  run probe_opt "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'equalize_on_close=True' || { echo "$output"; false; }
}

@test "removal: the splits and stack layouts both survive carrying the option" {
  [ -x "$KITTY" ] || skip "kitty is not installed"
  run probe_opt "$CONF"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The option rides ON the splits entry, so a careless edit can drop `stack` (⌘⇧Z zoom) or turn
  # `splits` into an unknown layout name. Both entries are asserted, not just the first.
  echo "$output" | grep -q '^layouts=splits:equalize_on_window_close=yes,stack$' || { echo "$output"; false; }
}

@test "CONTROL: without the option kitty resolves it False — the guard can actually fail" {
  [ -x "$KITTY" ] || skip "kitty is not installed"
  MUT="$BATS_TEST_TMPDIR/mutant.conf"
  sed 's/^enabled_layouts splits:equalize_on_window_close=yes,stack$/enabled_layouts splits,stack/' "$CONF" > "$MUT"
  grep -qx 'enabled_layouts splits,stack' "$MUT" || { echo "mutation did not apply"; false; }
  run probe_opt "$MUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qx 'equalize_on_close=False' || {
    echo "CONTROL FAILED — this suite cannot distinguish the unfixed config:"; echo "$output"; false; }
}

@test "arrival: kitty-pane-menu equalizes the destination with --self and an explicit window id" {
  M="$REPO/bin/kitty-pane-menu"
  grep -q '"action", "--self", "layout_action", "equalize"' "$M" || { echo "the --self form is gone"; false; }
  grep -q '"KITTY_WINDOW_ID": str(wid)' "$M" || {
    echo "KITTY_WINDOW_ID is not set explicitly — --self would resolve to no window, because a"
    echo "launch --type=background child is handed an EMPTY KITTY_WINDOW_ID."; false; }
}

@test "arrival: the menu equalizes only after the move actually succeeded" {
  # Ungated, a failed move (destination died between the pop and the pick) would square up the
  # SOURCE tab — a visible change from an action that did not happen.
  run python3 - "$REPO/bin/kitty-pane-menu" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
calls = [n for n in ast.walk(tree)
         if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "equalize_tab_of"]
assert len(calls) == 1, f"expected exactly one equalize_tab_of call, found {len(calls)}"
# It must sit in the `else` (success) arm of a returncode test, never in the bare body.
ok = False
for n in ast.walk(tree):
    if isinstance(n, ast.If) and any(
            isinstance(c, ast.Call) and getattr(c.func, "id", "") == "equalize_tab_of"
            for c in ast.walk(ast.Module(body=n.orelse, type_ignores=[]))):
        ok = "returncode" in ast.dump(n.test)
assert ok, "equalize_tab_of is not gated on the detach-window returncode"
print("gated")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "arrival: it2-kitty squares up the tab a fired pane lands in" {
  I="$REPO/bin/it2-kitty"
  grep -q 'export KITTY_WINDOW_ID="\$new"; kt action --self layout_action equalize' "$I" || {
    echo "the split path no longer equalizes on arrival"; false; }
  # A subshell, not a `VAR=x kt …` prefix: kt is a shell FUNCTION and in bash such an assignment
  # SURVIVES the call, leaking a stale KITTY_WINDOW_ID into everything below it.
  grep -q '^    ( export KITTY_WINDOW_ID=' "$I" || { echo "the assignment is not subshell-scoped"; false; }
}

@test "no caller uses the bare or --match form, which silently equalize the wrong tab or none" {
  # Bare: aims at whatever the operator is focused on. --match: rc 0 and no effect at all.
  #
  # SEARCHED OVER CODE, NOT TEXT, and that distinction is the test working. The first draft of this
  # assertion grepped the files raw and failed on bin/kitty-pane-menu's own DOCSTRING — the prose
  # that warns about `--match` contains the string it forbids. Stripping is the fix, but only in
  # the safe direction: python goes through `tokenize` so comments and string literals are dropped
  # exactly, and shell drops WHOLE-LINE comments only. A cruder `sed 's/#.*//'` would truncate code
  # containing a literal '#', and for a must-NOT-contain assertion that can only manufacture a
  # false PASS — the one failure direction a guard may never have.
  run python3 - "$REPO" <<'PY'
import io, pathlib, re, sys, tokenize
root = pathlib.Path(sys.argv[1])
BARE  = re.compile(r'@ action layout_action equalize')
MATCH = re.compile(r'action\s+--match\s+\S+\s+layout_action\s+equalize')

def code_of(path: pathlib.Path) -> str:
    src = path.read_text(errors="replace")
    if src.startswith("#!") and "python" in src.splitlines()[0]:
        out = []
        try:
            for tok in tokenize.generate_tokens(io.StringIO(src).readline):
                if tok.type not in (tokenize.COMMENT, tokenize.STRING):
                    out.append(tok.string)
        except (tokenize.TokenError, IndentationError, SyntaxError):
            return src          # unparseable: fall back to the STRICTER raw text
        return " ".join(out)
    return "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))

SKIP_DIR = {"__pycache__", ".git", "node_modules", "vendor"}
SKIP_EXT = {".md", ".json", ".png", ".pyc", ".pyo", ".so", ".dylib"}

bad = []
for d in ("bin", "scripts"):
    for f in sorted((root / d).rglob("*")):
        # POPULATION FIRST. The first version walked everything and convicted
        # bin/__pycache__/kitty-pane-menu.cpython-311.pyc — COMPILED BYTECODE that embeds the very
        # docstring warning about `--match`, which no source-stripper can reach. An untracked build
        # artifact is not a caller; it cannot use the wrong form because it is not code anyone runs.
        # Binaries are also excluded by CONTENT (a NUL probe), not only by extension, so an
        # unfamiliar artifact cannot re-open the same hole under a name this list does not know.
        if not f.is_file() or f.suffix in SKIP_EXT or SKIP_DIR & set(f.parts):
            continue
        try:
            if b"\0" in f.open("rb").read(4096):
                continue
        except OSError:
            continue
        code = code_of(f)
        if BARE.search(code):
            bad.append(f"{f.relative_to(root)}: bare form — equalizes the FOCUSED tab, not its own")
        if MATCH.search(code):
            bad.append(f"{f.relative_to(root)}: --match form — returns rc 0 and does nothing")
print("\n".join(bad) if bad else "clean")
sys.exit(1 if bad else 0)
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
