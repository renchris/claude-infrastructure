# kitty title-band SIGSEGV — the crash population is FIVE, not one (2026-09-16)

Follow-on to cc-backlog `bf6af099a712`, whose receipt cites a single crash. It cites the last
one. **The operator's kitty (`/Applications/kitty.app`) crashed five times today**, in two
clusters and with **three distinct fault addresses** — so this is a family of near-NULL
dereferences reached from Python, not one bad line.

| time | fault addr | top frames | binary |
|---|---|---|---|
| 13:56:59 | `0x0` | `? <- cfunction_call <- _PyEval_EvalFrameDefault` | /Applications |
| 13:57:17 | `0x0` | `? <- cfunction_call <- _PyEval_EvalFrameDefault` | /Applications |
| 13:58:06 | `0x8` | `fast_data_types+816344 <- +596680 <- +821436` | /Applications |
| 13:58:14 | `0x8` | identical to 13:58:06 | /Applications |
| 20:13:49 | `0x20` | `fast_data_types+840952 <- cfunction_call` | /Applications |

Two further reports today are NOT this bug and should not be counted: 15:10:07 is a sandbox
(`/private/tmp/*/kitty`) dying in `destroy_window <- destroy_mock_window`, i.e. a test tearing
down a mock; 18:14:46 is a sandbox dying in `objc_msgSend <- glfwPostEmptyEvent <- io_loop`, a
different (threading) fault on the event loop.

**Why the count matters.** Four crashes inside 75 seconds at 13:56–13:58 is a reproduction that
already happened, and the 13:58 pair share a signature byte-for-byte. A root-cause hunt aimed
only at the 20:13:49 signature (`+840952`, `0x20`) is aimed at one member of the family, and the
two earlier addresses (`0x0`, `0x8`) are different offsets into presumably different structs.

🚨 **ATTRIBUTION, STATED HONESTLY — the 13:5x cluster is NOT attributed to this work.** Only the
20:13:49 crash has a contemporaneous observer tying it to a chord press. For the 13:5x four, all
that is established is: the binary is `/Applications/kitty.app` (so not one of the sandbox
builds), the thread is the main thread, and the fault family matches. The nearest commit in time
is `27f3978ae` 13:52, a cv-review research commit with nothing to do with kitty. Do not write
these four into the band's account without a trigger; equally, do not drop them — five crashes of
the operator's terminal in one day is the fact, whatever caused them.

**And the two clusters have DIFFERENT ENTRY PATHS, which is the sharpest thing here.** All four
13:5x crashes run `builtin_exec <- PyEval_EvalCode` — code executed through `exec()`, which is
how a kitty `--watcher` module or a kitten is loaded. The 20:13:49 crash has no `builtin_exec` at
all; it is two nested `slot_tp_call <- _PyObject_Call_Prepend` frames, i.e. `__call__` chains on
objects, which is the shape of a `combine :` chord dispatching its actions. So these are not one
bug seen five times. A cure verified against one entry path has not been verified against the
other.

## Ruled out, with the evidence

- **"The shim's cached title-bar screen is too narrow for a widened pane."** REFUTED by reading
  `kitty/window_title_bar.py`: `WindowTitleBarScreen.layout()` calls `self.screen.resize(1,
  ncells)` on every layout, so the cell buffer tracks the geometry. Do not re-derive this.
- **"A NULL window falls through the lookup."** REFUTED: `WITH_WINDOW` (kitty/state.c:52) is a
  guarded loop — the body only executes on a found window.

## Live hypotheses, strongest first

1. **`set_window_title_bar_render_data` type-checks nothing.** `kitty/state.c:1150` parses its
   `Screen *` with `PA("KKKOIIII", ...)` — format `O`, which accepts ANY `PyObject *` with no
   type check — then hands it straight to `init_window_render_data`, which does `Py_CLEAR
   (d->screen)` and `d->screen = Py_NewRef(screen)`. Both are refcount writes through that
   unchecked pointer. This is the function the config's own §616 note already fingered for
   "validates nothing against the content rect".
2. **Two owners of one render-data slot.** The shim writes `window_title_render_data` from
   `_patched_set_geometry` (scripts/kitty-title-band-watcher.py:141) using its own cached
   `_title_bar_screen`. The chord raises `window_title_bar_min_windows` to 1, at which point
   STOCK kitty renders native title bars for the same windows and writes the same slot with its
   own screen. The shim's design assumes it is the only writer — its docstring says it runs
   kitty's set_geometry "with the bar switched OFF" precisely to avoid that.
3. **Stale `cell_width`.** `WindowTitleBarScreen.__init__` captures `cell_width` once;
   `layout()` computes `ncells` from that captured value forever. The shim only ever constructs
   the screen once (`if self._title_bar_screen is None`). After any font-size or DPI change the
   cached width no longer matches the real cells, so `ncells` and the pixel geometry disagree.

## The sandbox harness works, and its null is NOT a refutation

A sandbox kitty can be driven through the chord's exact action with **no synthetic input**: the
chord's second half is `kitty @ load-config --ignore-overrides <half that sets min_windows 1>`,
which is a remote-control call. Recipe (socket deliberately OUTSIDE the `/tmp/kitty-*` glob,
because that glob is the safety predicate the live-kitty refusals key on):

    ~/k482/kitty/launcher/kitty --config <sbx>/kitty.conf --listen-on unix:/tmp/ktb-sbx-repro.sock \
        --session <sbx>/session --start-as=minimized
    kitty @ --to unix:/tmp/ktb-sbx-repro.sock launch --type=overlay --watcher <copy of watcher.py> sh -c 'sleep 0.2'
    kitty @ --to unix:/tmp/ktb-sbx-repro.sock load-config --ignore-overrides <sbx>/on.conf

Result: shim confirmed installed (`installed pid=33416` in the shared watcher log), survived
geometry churn with bars off, and **survived the min_windows flip**. Three reasons that null
does not refute anything, all of which the next run must fix:

- **The window was MINIMIZED** — chosen so it could not steal the operator's focus. If the fault
  is reached through the render path, a window that never renders holds the axis under test
  constant. This is the `control-fixture-must-reach-the-bugs-regime` shape.
- **Only the chord's SECOND half ran.** The real chord is `combine :
  kitty-pane-title-overlay.py off --all : kitty-pane-title-toggle.sh toggle`. The first half was
  not driven, because those wrappers resolve their own target and mis-targeting them would hit
  the operator's live kitty.
- **Two panes, trivial content.** The real instance had many panes in nested splits.

## A sibling reached the same call independently

`997bfe85c` (branch `fix/resume-classify-anchor`, 20:21, NOT landed) commits the same two
`# DISARMED-` prefixes, differing only by two comment lines asserting "This is LANDED, not a
dangling working-tree edit". That claim was false when written — the commit never reached trunk —
and becomes true once this land does. Two sessions converging on one call is evidence for the
call, not duplicated work.

## A repro is the ONLY route to a function name

`/Applications/kitty.app/.../kitty.fast_data_types.so` carries 664 symbols and every one is an
undefined import — zero local text symbols — so the shipped offsets (`+840952`, `+816344`) can
never be resolved. The sandbox build `~/k482/kitty/fast_data_types.so` retains 1670 text
symbols, including `_pyset_window_title_bar_render_data`. So a crash reproduced in the sandbox
symbolizes itself; one reproduced in the shipped build never will. (Offsets do NOT transfer
between the two builds — do not map `+840952` onto a sandbox address.)

## Next experiment

Re-run the harness with the sandbox window VISIBLE, several nested splits, and both halves of
the chord driven at the sandbox socket. If it reproduces, the backtrace names the function and
hypothesis 1/2/3 collapses to one. If it does not, the next variable is the drag path
(`force_show_title_bars`), which is what makes the currently-live shim dangerous.
