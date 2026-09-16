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
