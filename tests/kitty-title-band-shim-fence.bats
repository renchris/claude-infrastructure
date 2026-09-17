#!/usr/bin/env bats
# The title-band shim must not install itself unless somebody asked for it by name.
#
# WHY. scripts/kitty-title-band-watcher.py monkey-patches Window.set_geometry so a title bar is
# drawn OVER row 1 instead of being allocated a row. To do that it hands
# set_window_title_bar_render_data a rect that OVERLAPS the content rect -- a state stock kitty
# never produces, because stock reduces render_ynum and pushes render_top down by one cell BEFORE
# making that call (window.py:1113-1135, v0.48.2). state.c:1006 then takes the screen through a
# bare `O` format code, casts it to Screen* with NO type check, and writes
# `screen->reload_all_gpu_data = true`.
#
# On 2026-09-16 kitty 0.48.2 SIGSEGV'd at 20:13:49 -- EXC_BAD_ACCESS at 0x20, main thread, Cocoa
# key dispatch -> Python -> fast_data_types -- and took every pane in the only OS window with it.
# /tmp/kitty-title-band-watcher.log records `installed pid=597`: this shim was in the process that
# died, and in the two earlier crashes that day.
#
# The approach is sound and the C patch (docs/patches/kitty-window-title-band.patch) is the real
# fix; this file is the bridge until a rebuilt kitty exists. But an opt-OUT bridge is one a session
# can inject into the operator's LIVE terminal without anyone deciding to, which is how it got in
# three times in one afternoon. So the fence is the invariant, and this suite is what keeps it.

setup() {
    REPO="${BATS_TEST_DIRNAME}/.."
    SUBJECT="${REPO}/scripts/kitty-title-band-watcher.py"
    PY="$(command -v python3)"
    [ -n "$PY" ] || skip "no python3"
    [ -r "$SUBJECT" ] || skip "subject not readable: $SUBJECT"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

# install() lives inside a real kitty, so the kitty package is stubbed. Window is rebuilt for each
# arm: the shim parks the original on the Window CLASS, so a shared class would let the
# idempotence guard ("already installed") answer instead of the fence, and the test would pass
# for the wrong reason.
_install_returns() {
    local optin="$1"
    OPTIN="$optin" "$PY" - "$SUBJECT" <<'PY'
import importlib.util, os, sys, types

path = sys.argv[1]
for name, attrs in (
    ("kitty", {}),
    ("kitty.window", {}),
    ("kitty.fast_data_types", {"get_options": lambda: types.SimpleNamespace()}),
    ("kitty.tabs", {"TabManager": type("T", (), {})}),
):
    m = types.ModuleType(name)
    for k, v in attrs.items():
        setattr(m, k, v)
    sys.modules[name] = m
sys.modules["kitty.window"].Window = type("W", (), {"set_geometry": lambda self, g: None})

spec = importlib.util.spec_from_file_location("band", path)
band = importlib.util.module_from_spec(spec)
spec.loader.exec_module(band)
band._log = lambda m: None

optin = os.environ.get("OPTIN", "")
os.environ.pop("KITTY_TITLE_BAND_SHIM", None)
if optin:
    os.environ["KITTY_TITLE_BAND_SHIM"] = optin
print("INSTALLED" if band.install() else "REFUSED")
PY
}

@test "the shim REFUSES to install when nobody opted in" {
    run _install_returns ""
    [ "$status" -eq 0 ]
    [[ "$output" == "REFUSED" ]]
}

@test "the shim installs when KITTY_TITLE_BAND_SHIM=1 is set deliberately" {
    # The fence must be a gate, not a wall: the bridge still has to be usable on purpose, or the
    # C patch has nothing to be a bridge to. A test that only proves the refusal would pass
    # against a shim that had simply been deleted.
    run _install_returns "1"
    [ "$status" -eq 0 ]
    [[ "$output" == "INSTALLED" ]]
}

@test "a value other than 1 does NOT open the fence" {
    # `!= "1"` rather than a truthiness test, so KITTY_TITLE_BAND_SHIM=0 cannot read as consent.
    run _install_returns "0"
    [ "$status" -eq 0 ]
    [[ "$output" == "REFUSED" ]]
}

@test "MUTANT: removing the fence makes the unset case install" {
    # Without this, all three cases above are satisfiable by a shim that installs never or always.
    mdir="$(mktemp -d)"
    /usr/bin/sed 's/^    if os.environ.get("KITTY_TITLE_BAND_SHIM") != "1":$/    if False:/' \
        "$SUBJECT" > "$mdir/mutant.py"
    if cmp -s "$SUBJECT" "$mdir/mutant.py"; then
        rm -rf "$mdir"
        false   # the sed matched nothing: the mutant proves nothing, so fail loudly
    fi
    saved="$SUBJECT"
    SUBJECT="$mdir/mutant.py"
    run _install_returns ""
    SUBJECT="$saved"
    rm -rf "$mdir"
    [ "$status" -eq 0 ] || false
    [[ "$output" == "INSTALLED" ]] || false
}
