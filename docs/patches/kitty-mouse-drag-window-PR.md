# PR body draft — `mouse_drag_window`

> 🚨 **NOT POSTED, AND POSTING IS NOT AN AGENT'S CALL.** This file is a draft for the operator to
> review and submit if he chooses. Nothing in this phase opened an issue, a PR or a comment.

---

## Add a `mouse_drag_window` action so a window drag can be started from any mouse region

Today a kitty window can only be dragged by its title bar, so a drag requires
`window_title_bar_min_windows`/`toggle_window_title_bars` to have put a real, hit-tested bar on
screen. That makes dragging unavailable to anyone whose layout does not carry permanent title bars,
and it couples "I want to rearrange panes" to "I want a row of chrome on every window".

This adds one bindable mouse action:

```
mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window
mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window 2
```

The optional argument restricts the action to the first *N* rows of the window's text area, counted
from the top, so a front end that draws its own header can make just that band draggable and let
every press below it through untouched.

**This was pre-blessed.** From PR #9450, 2026-03-05:

> draggable window title bars would be an important feature, possibly with a mappable action … this
> belongs in a separate PR after this one is merged

## How it works

The action does **not** compose a drag. It arms one, with `drag_started=False`, and then gets out of
the way: kitty's existing motion handler promotes it to a real drag once the pointer has travelled
further than `drag_threshold`, and calls `start_window_drag` itself. That keeps `drag_threshold`
honoured, keeps the drag preview and the unwind path identical to a title-bar drag, and means this
patch adds no second copy of the payload-building code.

Four guards, each for a failure that is easy to hit:

- **Left button only.** The release is consumed by the drag handler, whose clear path is gated on
  `GLFW_MOUSE_BUTTON_LEFT`, so arming from another button would leave the flag set with nothing able
  to clear it. Bound to another button the action returns without arming, and the doc text says so.
- **Refuses when `drag_threshold` is 0.** At zero the promotion test can never pass, so arming would
  set a flag only a left release could clear — and `drag_threshold` documents itself as "a value of
  zero disables all dragging", which an action should not quietly override.
- **Refuses while a drag is already in progress**, rather than re-arming underneath one.
- **Clears the click queue for its button.** The release is swallowed by the drag handler, so the
  press has been recorded and `dispatch_possible_click` never runs — without this the *next* plain
  click reads as a double click and selects a word. Same hazard and same cure as
  `handle_potential_drag()`.

The start coordinates come from a new window-keyed accessor rather than from
`global_state.callback_os_window`. That matters for one specific reason: any non-first action of a
`combine` runs on a zero-delay timer *after* the GLFW callback has returned, at which point that
pointer is NULL — and the press coordinates are never cleared, so reading them through the OS-window
path there would not fail, it would succeed at the origin of some *previous* press. Stale is worse
than NULL, so the action reads the press data for the window it was dispatched on. The doc text also
prohibits using it as a non-first `combine` element, but the code is safe without that advice.

**Title bars.** Starting a drag forces title bars visible for the duration — this action inherits
that from `start_window_drag` and never calls it directly, so the behaviour is whatever the
title-bar drag already does. Happy to change it if you would rather the action suppressed it.

**One note on `Tab`/`TabManager` lifetime.** The armed state is a window id plus coordinates, not a
pointer, so a tab reallocation between arming and promotion cannot leave a dangling reference; no
guard is added for it.

## Tests

`kitty_tests/window_drag.py`, 8 units:

- the action is bindable in `mouse_map` (catches a rename that breaks the documented config line)
- it arms the drag — asserted on `get_window_being_dragged()`, not on the dispatcher's return value
- **an unimplemented action name is not consumed and writes nothing** — the control that makes the
  previous test mean anything
- the four guards each refuse
- crossing `drag_threshold` starts the drag and a sub-threshold move does *not* request a thumbnail
  — the only test that does the distance arithmetic, so a wrong coordinate space cannot hide
- the payload, plus the `OSError` path clearing the state
- no window ⇒ no crash, state untouched
- the row restriction passes the press through instead of consuming it

## Checks

`ruff check .`, `./test.py type-check` and `./test.py --module window_drag` (8 tests, OK) all
clean. No default `mouse_map` ships — the action is inert until a user binds it.

> **`./autoformat` was NOT run for this draft, deliberately.** On this machine it panicked the
> kernel twice in one afternoon: it walks every top-level directory except `dist`/`build`/`bypy`/
> `3rdparty`, so it formats the vendored ~300 MB `dependencies/` tree, and ten parallel
> `clang-format` workers over the multi-MB `simde` macro headers each grew to 1-19 GB RSS until the
> VM compressor hit its segment limit. Its cache is only written on completion, so every re-run
> formats everything again. The changed files were formatted individually instead. A skip-tuple
> entry for `dependencies` looks upstream-worthy and is not proposed here.

---

## Backport notes (v0.48.2)

**The delta is the finding.** `docs/patches/kitty-mouse-drag-window-v0.48.2.patch` is not the master
patch with the line numbers moved; it carries two hunks master does not need and drops three master
hunks that v0.48.2 cannot take. Built and verified in a v0.48.2 checkout at `2cb1d95` (tag
`v0.48.2`), incremental `make` ≈ 13 s.

### What v0.48.2 LACKS and the backport must ADD — 5 lines, and they are load-bearing

`OSWindow.mouse_left_press_x/y` is master-only. Verified rather than assumed:

```
$ grep -rn "mouse_left_press" kitty/ glfw/ ; echo "rc=$?"     # in the v0.48.2 tree
rc=1
```

| | master `1d67ecd` | v0.48.2 `2cb1d95` | the backport |
|---|---|---|---|
| the field | `kitty/state.h:552`, on `OSWindow` | **absent** | added after `double mouse_x, mouse_y;` (`state.h:447`) |
| the write site | `kitty/glfw.c:682-685`, in the `GLFW_MOUSE_BUTTON_LEFT && GLFW_PRESS` branch, **before** `mouse_event(button, mods, action)` | **absent** | added at the equivalent place — immediately after pristine `glfw.c:589` |

The equivalent branch was found by reading, not by line number: v0.48.2's `mouse_button_callback`
has no `refresh_mouse_position_for_hit_test` call and its `has_received_cursor_pos_event` block is
shaped differently, but the two lines the hunk anchors on —
`global_state.callback_os_window->mouse_button_pressed[button] = …` followed by
`if (is_window_ready_for_callbacks()) mouse_event(button, mods, action);` — are byte-identical in
both refs, so the insertion point is unambiguous.

🚨 **A backport that exposes the field without the write site is not a smaller backport, it is a
broken one that passes its own test.** `set_window_being_dragged(id, False, 0.0, 0.0)` arms the drag
at the origin, and `get_window_being_dragged()` then reads `[id, False, 0.0, 0.0]` — a non-zero
window id, which is the assertion a state-read test makes. It looks exactly like success. That is
why the verification below reads the *coordinates* and checks them against the press point.

### What v0.48.2 ALREADY HAS — every symbol the ported `state.c` touches

Each checked in the v0.48.2 tree before writing the hunk; none differed. **Line numbers are
PRISTINE v0.48.2** (before this patch is applied), each re-read from `git archive HEAD` rather than
from the patched tree, so a reader can follow them into an unpatched checkout:

| symbol | v0.48.2 | note |
|---|---|---|
| `window_for_window_id` | `state.h:618` | same signature |
| `os_window_for_kitty_window` | `state.h:579` | same signature |
| `global_state.active_drag_in_window` / `.tracked_drag_in_window` | `state.h:495` | same names, same struct |
| `Window.click_queues` | `state.h:273`, `ClickQueue click_queues[8]` | `arraysz()` works |
| `PA(fmt, …)` | `state.c:881` | same macro |
| `M(name, arg_type)` method-table macro | `state.c:1795` | same |
| `set_window_being_dragged` | `state.c:1764`, `PyArg_ParseTuple(args, "\|Kpdd", …)` | **the 4-argument call in `window.py` binds unchanged** |
| `window->mouse_pos.cell_x/cell_y` | used by `get_mouse_data_for_window`, `state.c:1738` | same |
| `GLFW_MOUSE_BUTTON_LEFT` in `fast_data_types` | `fast_data_types.pyi:197` | already exported |
| `get_options().drag_threshold` | `options/types.py:576`, default `5` | same |
| `Boss.set_active_window(window, switch_os_window_if_needed=…)` | `boss.py:645` | same keyword |
| `'mouse'` in `actions.groups` | `actions.py:26` | **the docstring's group is valid** |

The only cosmetic difference is style: master has been through a `clang-format` pass that writes
`static PyObject *` and one argument per line; v0.48.2 writes `static PyObject*` with packed
`Py_BuildValue` arguments. The backport follows **v0.48.2's** local style, so the hunk reads as
native to the file it lands in.

### What was deliberately NOT ported, and why

1. **`kitty/shaders.c:2583-2584`** reads `mouse_left_press_x/y` on master to feed `mouse_pos[2..3]`
   to custom shaders. That is a different master-only feature. Not ported.
2. **`kitty/tabs.py` — the Q5 `on_window_drop` ordering fix. LEFT OUT, and this is a real gap, not
   a shrug.** The brief said to port it *if it applies cleanly*; it does not, because v0.48.2's
   `on_window_drop` is a materially different function. Measured, not assumed:

   | | master | v0.48.2 |
   |---|---|---|
   | marks the drop target | `self.set_drag_over_me(True)` | `self.window_drag_over_me = True` (**no `set_drag_over_me`**) |
   | finds the window under the pointer | `self._find_window_at(x, y)` | an inline loop over `active_tab` computing `rel_x/rel_y` from `central` |
   | title-bar hit test | `self._pointer_in_title_bar_of(dest_window, y)` | an inline `tb_top/tb_bottom` computed from `cell_size_for_window` + `opts.window_title_bar` |
   | drop direction | `self._drop_direction_for(dest_window, x, y)` | **absent** |

   `grep -c` in `kitty/tabs.py`: `_pointer_in_title_bar_of` **0**, `_drop_direction_for` **0**,
   `set_drag_over_me` **0** — all three exist only on master. The master hunk's context does not
   occur in the file at all.

   ⚠️ **The hazard the Q5 fix closes is nonetheless PRESENT in v0.48.2**, and a future reader should
   know that rather than infer from this omission that it is absent. v0.48.2 calls
   `self._clear_force_show_title_bars()` at `tabs.py:2035`, **before** it reads `win.geometry` and
   `win.show_title_bar` in the classification loop — so the drop is classified against a relayout
   the user never saw. The equivalent minimal transform is to move that call into a `finally:`
   wrapping everything from `central, tab_bar = viewport_for_window(...)` to the end of the method.
   It is left out here because this wave's deliverable is the action, and because guessing at a
   rewritten classifier is exactly what the brief forbade.
3. **`docs/changelog.rst`** — a local build, not an upstream submission.
4. **`kitty_tests/window_drag.py`** — there is no test wave and cannot be one:
   `ls kitty_tests/base.py` → `No such file or directory` in v0.48.2 (on master it is the module the
   test imports `BaseTest` from). Verification is the sandbox and the state read, below.

### Verification — what was run, and the control that makes each reading mean something

Build identity, never `--version` (master at `1d67ecd` also declares `Version(0, 48, 2)`):

```
$ kitty/launcher/kitty +runpy 'import kitty; print(kitty.__file__)'
/Users/chrisren/k482/kitty/launcher/kitty.app/Contents/MacOS/../../../../../kitty/__init__.py
# negative control — the operator's installed build, same command:
/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/kitty/__init__.pyc
```

Sandbox: own `KITTY_CONFIG_DIRECTORY`, own socket outside the `/tmp/kitty-*` glob,
`mouse_map left press grabbed,ungrabbed mouse_drag_window`. Presses posted as real CGEvents.

| # | what | reading | why it is a reading and not a stub |
|---|---|---|---|
| 1 | before any press | `window_being_dragged = [0, False, 0.0, 0.0]`, `left_press = (0.0, 0.0)` | establishes that `(0,0)` is the *unarmed* value, which is what makes #2's coordinates load-bearing |
| 2 | LEFT press, `drag_threshold 5` | `window_being_dragged = [1, False, 1000.0, 538.0]` | the press was at screen `(1073,480)`, window origin `(573,183)`, macOS title bar 28 pt, viewport ratio 2 ⇒ predicted `((1073-573)*2, (480-183-28)*2) = (1000, 538)`. **Exact match — the added `glfw.c` write site runs.** `drag_started=False` = armed, not promoted |
| 3 | `drag_threshold 0`, LEFT press | `drag_threshold: 0`, `window_being_dragged = [0, False, 0.0, 0.0]`, **`left_press = (400.0, 500.0)`** | the press coordinates still updated, so the press *arrived* and the action *declined*; without that field this is indistinguishable from an event that never reached kitty |
| 4 | positive control for #3: `drag_threshold 5`, same relative point | `window_being_dragged = [3, False, 400.0, 500.0]` | same instrument, same geometry, only the option differs ⇒ #3's refusal is attributable to `drag_threshold` |
| 5 | RIGHT press bound to the same action | `mouse_drag_window` **was called**: `{'button': 1, 'returned': True, 'state_after': [0, False, 0.0, 0.0]}`; `left_press` stays `(0.0, 0.0)` for that window | a recorder wrapping the action proves it *ran and passed the press on*, not that the binding was missing. The unchanged `left_press` also confirms the new `glfw.c` hunk is correctly gated on `GLFW_MOUSE_BUTTON_LEFT` |
| 6 | the option parser | `'mouse_drag_window abc'` → `log_error` + `args=(0,)`; `'mouse_drag_window -3'` → `log_error` + `args=(0,)`; `'mouse_drag_window 2'` → `args=(2,)`; bare → `args=()` | negative control: `parse_key_action('toggle_window_title_bars 2')` → `KeyError: Unknown action`. That is the failure the `@func_with_args` parser is mandatory to prevent, demonstrated on an action that lacks one |
| 7 | the docstring is structurally valid | `get_all_actions()` returns `{'group': 'mouse', 'short_help': 'Begin dragging the window under the mouse', 'long_help_len': 1731}` | an empty doc raises `IndexError` and an unknown group raises `KeyError` in `kitty/actions.py`; running the function is what rules both out |
| 8 | sandbox stderr | one line, `WARNING: Your system's OpenGL implementation does not have glCopyImageSubData` | no traceback |

Rows 2, 3 and 5 plus the before/after pair were **re-run on a freshly relinked binary** after a
`git stash push -- kitty/` / `git stash pop` round trip (taken to get the type-check control), in a
fourth pristine sandbox, and reproduced identically — `[2, False, 800.0, 500.0]` armed,
`drag_threshold 0` refusing with `left_press = (400.0, 500.0)` still updated, and the right-button
recorder again reading `{'button': 1, 'returned': True}` with that window's `cell_x/cell_y` moved to
the press cell but its `left_press` left at `(0.0, 0.0)`. Sandbox stderr: **0 bytes**.

### Three traps this verification hit, recorded so the next session does not pay for them

- 🚨 **A press aimed at a hardcoded screen point landed in the operator's LIVE kitty.** The operator's
  kitty is FULL SCREEN, so it owns the active Space; the sandbox window silently fell off that Space
  and the topmost window at the press point became his. Neither obvious gate catches this:
  *"is my process frontmost"* is **never** true while a full-screen app holds the display (System
  Events reported the operator's pid regardless), and *"is my window onscreen"* is true even when
  another window sits on top of it. The gate that works asks the question a synthetic press actually
  asks — **which window is topmost AT THIS POINT** — by walking
  `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly)` front-to-back for the first
  `layer == 0` window containing the point, and refusing unless it is the sandbox's own
  `platform_window_id`. It then refused correctly four times.
- **Repeating a press at the IDENTICAL point stops arming, and it looks like a regression.** kitty's
  mousemap is keyed on `repeat_count`, so a second press at the same cell dispatches to
  `mouse_selection word` (`repeat_count=2`) and never reaches `mouse_drag_window` (`repeat_count=1`).
  This produced a *failed positive control* that briefly looked like a defect in the port. Move the
  press point between runs.
- **A filtered read of the harness output turned an ABORT into a false verdict.** `aim.sh … | grep -E
  'press_point|window_being_dragged'` dropped the `ABORT: … refusing to aim blind` line, so a run
  that posted nothing read as "the action was never called" — the exact shape of
  *a gate refusal is not a gate result*. Read the harness output whole.

### Reproducing it

The instruments live in `/tmp` by design (they drive a screen, not the repo) and are ~30 lines each;
what matters is the recipe, so it is recorded here rather than left in a log:

```sh
# 1. apply + build (PATH must carry /opt/homebrew/bin for python3 3.14)
git -C <v0.48.2 checkout> apply docs/patches/kitty-mouse-drag-window-v0.48.2.patch
cd <v0.48.2 checkout> && PATH=/opt/homebrew/bin:$PATH make        # ~13 s incremental

# 2. build identity — NEVER --version
<tree>/kitty/launcher/kitty +runpy 'import kitty; print(kitty.__file__)'

# 3. option parser + docstring, no sandbox needed
<tree>/kitty/launcher/kitty +runpy 'from kitty.options.utils import parse_key_action; print(parse_key_action("mouse_drag_window abc").args)'

# 4. sandbox: own config dir, own socket, and gate every synthetic press on a
#    front-to-back CGWindowList hit test for the sandbox's own platform_window_id.
#    Read state through a no_ui kitten calling get_window_being_dragged() and
#    get_mouse_press_data_for_window(); assert the COORDINATES, not just the id.
```

🚨 `kitty @ close-os-window` does not exist in v0.48.2 (`close-window --match all` does), and a
second launcher started with the same `--instance-group` attaches to the running instance rather
than replacing it, leaving processes that hold the socket open after its windows are gone.

### Checks

`ruff check kitty/window.py kitty/options/utils.py kitty/fast_data_types.pyi` — **All checks
passed.** `./test.py type-check` — **7 diagnostics, rc 1**, and the control is what makes that
readable: the identical run on the tree with the patch stashed (`git stash push -- kitty/`) reports
**the same 7, also rc 1**, and none of them names a file this patch touches. The patch adds zero
diagnostics. There is no `./test.py --module window_drag` arm here; `kitty_tests/base.py` is
master-only, so the suite cannot carry the test.

🚨 **`./autoformat` was NOT run — and on v0.48.2 neither was `clang-format` on the two C files,
deliberately.** `autoformat` panicked this machine's kernel twice in one afternoon (it formats the
vendored ~300 MB `dependencies/` tree). But the narrower `clang-format -i <one changed file>` is
also wrong here, and this is a fact about v0.48.2 rather than a preference: master has since been
through a repo-wide format pass that v0.48.2 predates, so re-formatting the file to `.clang-format`
rewrites the whole thing. Measured:

```
$ clang-format --style=file:.clang-format kitty/state.c | diff - kitty/state.c | wc -l
    1972
$ clang-format --style=file:.clang-format kitty/glfw.c  | diff - kitty/glfw.c  | wc -l
    3590
```

~5,500 diff lines of pure churn against 41 lines of change. The two hunks were written to match the
surrounding v0.48.2 style by hand instead (`static PyObject*`, packed `Py_BuildValue` arguments),
which is why the master patch's `state.c` hunk and this one differ cosmetically.

### Residuals from this wave, stated rather than left to be rediscovered

1. 🚨 **One synthetic left click reached the operator's live kitty** (a plain press-and-release at
   screen `(900,560)`, no motion, so a click and not a drag — it can have moved the text cursor or
   cleared a selection in whatever pane sat there; it typed nothing and submitted nothing). Cause
   and cure are in the first bullet of § Three traps above; the hit-test gate was written in
   response and refused correctly on every subsequent attempt.
2. **Five sandbox `kitty` processes are resident with no windows** — pids 29060, 39463, 40200,
   76063, 97884, all `/Users/chrisren/k482/kitty/launcher/kitty`. Their windows were closed with
   `kitty @ close-window --match all`; the processes survive because a second launcher started with
   the same `--instance-group` attaches to the running instance and keeps the socket open, and this
   wave may not run `kill`. They hold `/tmp/kdw6.sock`, `/tmp/kdw6b.sock` and `/tmp/kdw6c.sock`,
   which are outside the `/tmp/kitty-*` glob and so cannot be confused with the operator's.
3. **The verification instruments live in `/tmp/kdw6/`** (`btnpress.c`, `winbounds.c`, `hittest.c`,
   `aim.sh`, `probe*.py`) and are reaped on reboot by construction. They are ~30 lines each and the
   recipe above is what reproduces them; only `tools/draghold/` was judged worth committing, and it
   already is.
