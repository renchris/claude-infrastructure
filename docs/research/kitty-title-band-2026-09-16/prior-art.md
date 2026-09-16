# Prior art audit — the sibling `mouse_drag_window` patch, the repo record, and what to reuse

**Axis:** audit the sibling session's patch and the repo record; what to reuse.
**Date:** 2026-09-16. **Author:** research agent (read-only on every tree named below).

**Trees read, with the identity of each:**

| short name | path | identity, as measured |
|---|---|---|
| **sibling worktree** | `/Users/chrisren/Development/.worktrees/kitty-drag-impl` | `git log --oneline -1` → `48fdf7b59 docs(kitty): a synthetic input event has no sandbox…`; `git status --porcelain` → **empty** (nothing uncommitted; read-only was preserved) |
| **~/kitty-482** | `/Users/chrisren/kitty-482` | `git rev-parse --short HEAD` → `2cb1d95c3` (tag `v0.48.2`) — **the build the operator runs** |
| **~/kitty-dev** | `/Users/chrisren/kitty-dev` | git master, `1d67ecd47` (per the brief; re-verified in §6) |
| **shared checkout** | `/Users/chrisren/Development/claude-infrastructure` | `config/kitty.conf` — read-only |

Every file:line below is tagged with the tree it was read in. Anything I could not measure is marked
**UNMEASURED** rather than reasoned into a verdict.

---

## §1 — What `mouse_drag_window` is, exactly

### 1.1 The one-sentence summary

It is a **bindable mouse action** that ARMS kitty's existing window-drag state machine from a press
anywhere in a window (or from the first *N* text rows), instead of requiring the press to land in a
real, hit-tested window title bar. It composes no drag of its own: it sets
`window_being_dragged = (window_id, drag_started=False, press_x, press_y)` and returns, and kitty's
own motion handler promotes it to a real drag once the pointer passes `drag_threshold`.

### 1.2 Arguments

One optional positional integer, `rows`, default `0`.

* `0` (or bare) — the whole window is draggable.
* `N > 0` — the press is consumed **only** when `cell_y < N`, i.e. within the first *N* rows of the
  window's **text area**. Presses below pass through to the program.
* Negative or unparseable ⇒ `log_error` and fall back to `0` (never raises).

The docstring states the row origin explicitly, and it is the sentence that matters most for the
title-band design: *"the rows are counted from the top of the window's **text area**, so when a
window title bar is visible, row one is the first row below it."*
(`kitty-mouse-drag-window.patch`, the `window.py` hunk; identical text in the v0.48.2 patch.)

### 1.3 Every file it touches

**Master patch** (`docs/patches/kitty-mouse-drag-window.patch`, 551 lines, 7 files) — hunk headers
from `grep -E '^@@'`:

| file | hunks | what |
|---|---|---|
| `docs/changelog.rst` | `@@ -202,6 +202,10 @@` | one changelog bullet under `0.49.0 [future]` |
| `kitty/fast_data_types.pyi` | `@@ -1605,6 +1605,16 @@` | `class MousePressData(TypedDict)` + 2 function stubs |
| `kitty/options/utils.py` | `@@ -508,6 +508,22 @@` | the `@func_with_args('mouse_drag_window')` parser |
| `kitty/state.c` | `@@ -1979,6 +1979,47 @@`, `@@ -2035,6 +2076,8 @@` | 2 new C accessors + 2 method-table rows |
| `kitty/tabs.py` | `@@ -2199,47 +2199,55 @@` | the **Q5 `on_window_drop` ordering fix** (`try/finally`) |
| `kitty/window.py` | 4 import hunks + `@@ -2054,6 +2058,64 @@` | the `@ac('mouse', …)` action itself |
| `kitty_tests/window_drag.py` | `@@ -0,0 +1,230 @@` | new file, 8 test units |

**v0.48.2 backport** (`docs/patches/kitty-mouse-drag-window-v0.48.2.patch`, 250 lines, **6** files):

| file | hunks | delta vs master |
|---|---|---|
| `kitty/fast_data_types.pyi` | `@@ -1582,…` | same content, different line |
| **`kitty/glfw.c`** | `@@ -587,6 +587,10 @@` | **BACKPORT-ONLY** — the write site for `mouse_left_press_x/y` |
| `kitty/options/utils.py` | `@@ -460,…` | identical parser |
| `kitty/state.c` | `@@ -1745,…`, `@@ -1798,…` | same 2 accessors, v0.48.2 brace/format style |
| **`kitty/state.h`** | `@@ -445,6 +445,7 @@` | **BACKPORT-ONLY** — the `OSWindow` field itself |
| `kitty/window.py` | 4 import hunks + `@@ -1994,…` | identical action |

**Dropped from the backport, each with a stated reason** (patch header + PR § Backport notes):
`kitty/shaders.c` (a different master-only feature reading the same field), **`kitty/tabs.py` (the
Q5 fix — a real, acknowledged gap, see §4.4)**, `docs/changelog.rst`, `kitty_tests/*` (v0.48.2 has no
`kitty_tests/base.py`).

### 1.4 The option-parsing hunk, quoted verbatim

`kitty/options/utils.py`, master `@@ -508,6 +508,22 @@` / v0.48.2 `@@ -460,6 +460,22 @@` — **byte-identical in both patches**:

```python
@func_with_args('mouse_drag_window')
def mouse_drag_window(func: str, rest: str) -> FuncArgsType:
    rows = 0
    rest = rest.strip()
    if rest:
        try:
            rows = int(rest)
        except Exception:
            log_error(f'Invalid number of rows for mouse_drag_window: {rest}')
        else:
            if rows < 0:
                log_error(f'The number of rows for mouse_drag_window must be non-negative, not: {rows}')
                rows = 0
    return func, [rows]
```

Note what this is for: without a `@func_with_args` entry, `parse_key_action('mouse_drag_window 2')`
raises `KeyError: Unknown action`. The PR demonstrates that with a negative control on an action that
lacks one (`toggle_window_title_bars 2` → `KeyError`) — PR § Verification row 6.

### 1.5 The C routing hunks, quoted verbatim

There is **no new C routing** — that is the patch's central design decision. The C side adds only two
*read/clear accessors*; all routing is the pre-existing title-bar drag path. `kitty/state.c`
(v0.48.2 form, `@@ -1745,6 +1745,41 @@`):

```c
static PyObject*
get_mouse_press_data_for_window(PyObject *self UNUSED, PyObject *args) {
    // The data needed to start a drag of the specified window: the cell the
    // mouse is over, the position, in OS Window pixels, of the last left button
    // press in the OS Window containing it, and whether some other mouse drag
    // is already in progress. The OS Window is resolved from the window, never
    // from the OS Window the current callback is for, since actions are not
    // always dispatched from within a callback.
    id_type window_id;
    PA("K", &window_id);
    Window *window = window_for_window_id(window_id);
    OSWindow *osw = os_window_for_kitty_window(window_id);
    if (!window || !osw) Py_RETURN_NONE;
    const bool drag_in_progress = global_state.active_drag_in_window || global_state.tracked_drag_in_window;
    return Py_BuildValue("{sI sI sd sd sO}",
            "cell_x", window->mouse_pos.cell_x,
            "cell_y", window->mouse_pos.cell_y,
            "left_press_x", osw->mouse_left_press_x,
            "left_press_y", osw->mouse_left_press_y,
            "drag_in_progress", drag_in_progress ? Py_True : Py_False);
}

static PyObject*
clear_click_queue_for_window(PyObject *self UNUSED, PyObject *args) {
    // Forget the presses recorded for the specified button in the specified
    // window, so that a press whose release is consumed elsewhere does not make
    // the next press count as a multi-click.
    id_type window_id;
    int button;
    PA("Ki", &window_id, &button);
    Window *window = window_for_window_id(window_id);
    if (window && 0 <= button && button < (ssize_t)arraysz(window->click_queues)) window->click_queues[button].length = 0;
    Py_RETURN_NONE;
}
```

Method-table registration (`@@ -1798,6 +1833,8 @@`):

```c
 static PyMethodDef module_methods[] = {
     M(os_window_focus_counters, METH_NOARGS),
     M(get_mouse_data_for_window, METH_VARARGS),
+    M(get_mouse_press_data_for_window, METH_VARARGS),
+    M(clear_click_queue_for_window, METH_VARARGS),
```

The **backport-only** C hunks — the two that make the backport a real port rather than a smaller one.
`kitty/state.h` `@@ -445,6 +445,7 @@`:

```c
     double mouse_x, mouse_y;
+    double mouse_left_press_x, mouse_left_press_y;
```

`kitty/glfw.c` `@@ -587,6 +587,10 @@`, inside `mouse_button_callback`:

```c
         global_state.callback_os_window->mouse_button_pressed[button] = action == GLFW_PRESS ? true : false;
+        if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS) {
+            window->mouse_left_press_x = window->mouse_x;
+            window->mouse_left_press_y = window->mouse_y;
+        }
         if (is_window_ready_for_callbacks()) mouse_event(button, mods, action);
```

### 1.6 The Python action, and its four guards

`kitty/window.py` (master `@@ -2054,6 +2058,64 @@`, v0.48.2 `@@ -1994,6 +1998,64 @@` — **the method body
is byte-identical between the two patches**):

```python
    def mouse_drag_window(self, rows: int = 0) -> bool | None:
        # Returning True means the press was not consumed and is passed on.
        if self.current_mouse_event_button != GLFW_MOUSE_BUTTON_LEFT:
            return True
        threshold = get_options().drag_threshold
        if not threshold:  # dragging is disabled
            return True
        data = get_mouse_press_data_for_window(self.id)
        if data is None or data['drag_in_progress']:
            return True
        if rows > 0 and data['cell_y'] >= rows:
            return True
        get_boss().set_active_window(self, switch_os_window_if_needed=True)
        # The drag is armed but not started, the motion handler starts it once
        # the pointer has moved farther than drag_threshold from this position.
        set_window_being_dragged(self.id, False, data['left_press_x'], data['left_press_y'])
        # The release is consumed by the drag handler, so the presses recorded
        # for this button must be forgotten, otherwise the next press counts as
        # a double click. Same hazard and cure as in handle_potential_drag().
        clear_click_queue_for_window(self.id, GLFW_MOUSE_BUTTON_LEFT)
        return None
```

Four refusals, each pass-through (`return True`): non-left button · `drag_threshold == 0` ·
another drag already in progress or no press data · press below the `rows` band.

### 1.7 Documented constraints on how it may be BOUND (these bind the new design)

From the `@ac()` docstring, verbatim:

> Map this to the press of the left mouse button. Mapping it to a different button will leave the
> drag armed after the button is released. For the same reason, do not use this action as anything
> other than the first action of a `combine`, since the rest of a combine runs after the mouse event
> that triggered it has been fully processed.

**Consequence for the title-band design: `mouse_drag_window` must be the FIRST element of any
`combine`, and must be bound to `left press`.** Our existing ⌘⇧B binding is a `combine` of two
`launch --type=background` calls — a band binding cannot simply be appended to it.

---

## §2 — What it gives us, and what it does NOT

**Verdict in one line: it gives the DRAG half of (c) and NOT the hand cursor on hover; it gives
NOTHING for (a), (b) or (d).** It is a complement to the render_a_bar design, not a substitute.

### 2.1 (c) drag half — **YES, and it is the right primitive**

Bound as `mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window 1`, a press in row 1 of a
pane's text area arms the identical drag that a title-bar press arms. Everything downstream is
kitty's own code, unmodified:

* the promotion at `drag_threshold`, the drag preview, the thumbnail, the OS drag payload;
* the drop classifier (`on_window_drop`) — reorder within a layout, move to another tab, move to
  another OS window, detach into a new OS window;
* **the no-op drag survives**: the drop lands on `dest_window is None or dest_window.id == window_id`
  → "Dropped on empty space or self" → returns without moving anything
  (`kitty-mouse-drag-window.patch`, the `tabs.py` hunk, master). This is requirement (c)'s
  "stays toggled ON if dropped in the same position" — but see §2.5, the title-bar visibility caveat.

Crucially for us: the action's `rows` argument exists **for exactly our case**. Its own docstring:

> This is intended for programs that draw their own header at the top of the window, for instance
> with the :doc:`graphics protocol </graphics-protocol>`, which kitty has no way of knowing about

So the sibling has already generalised the "front-end draws its own band, make just that band
draggable" case into an upstreamable action. **REUSE THIS.** It is the drag half of (c) for a
render_a_bar band too, because the band occupies the top of the window and `rows 1` selects it.

⚠️ **One unit mismatch that must be handled, not assumed away.** The action's region test is
`data['cell_y'] >= rows` — a **CELL** test on the window's text area. A render_a_bar band is drawn
**outside** the cell grid, so a pointer that is visually *over the band* is, in cell terms, over
**row 0** of the text area (the band covers row 0's pixels; it does not shift the grid). `rows 1`
therefore selects "the pixels of text row 0", which is exactly the band's footprint — **as long as
the band is exactly one cell tall and top-aligned with row 0**. If the band is drawn at a different
height, or a padding row is introduced, the cell test and the pixel band diverge and the action will
arm from a region that is not the band, or fail to arm from part of it. **This is a real constraint
on the band's geometry, and it is testable.** UNMEASURED: I did not run a pointer over a live
render_a_bar band (none exists yet).

### 2.2 The HAND CURSOR — **NO on hover; YES only after the button goes down**

This is the most decision-relevant finding in this section, and it is measured in C.

The hover path is `update_mouse_pointer_shape()` — **~/kitty-482 `kitty/mouse.c:1127-1144`**:

```c
void
update_mouse_pointer_shape(void) {
    mouse_cursor_shape = TEXT_POINTER;
    MouseRegion r = mouse_region(false, true);
    if (r.in_tab_bar) {
        mouse_cursor_shape = POINTER_POINTER;
    } else if (r.in_title_bar) {
        mouse_cursor_shape = POINTER_POINTER;
    } else if (r.window) {
        ...
```

`POINTER_POINTER` **is** the hand: **~/kitty-482 `kitty/screen.c:2012-2014`** maps CSS
`pointing_hand` / `hand2` / `hand` to it, and **`kitty/glfw.c:1184`** maps it to
`GLFW_POINTER_CURSOR`.

The hand is therefore reachable on hover **only** via `r.in_title_bar`, and `in_title_bar` is set
only in the `else if` arm of `mouse_region()` — **~/kitty-482 `kitty/mouse.c:1067-1080`**:

```c
        for (unsigned int i = 0; i < t->num_windows; i++) {
            Window *win = t->windows + i;
            if (contains_mouse(win) && win->render_data.screen) {
                ans.window_idx = i; ans.window = win; break;
            } else if (detect_title_bar && win->visible) {
                const WindowRenderData *trd = &win->window_title_render_data;
                if (trd->screen && trd->geometry.right > trd->geometry.left && ...) {
                        ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
```

`contains_mouse(win)` is tested **first**. A band drawn over a pane's own row 1 is inside that pane's
rect, so `contains_mouse` is TRUE, the loop `break`s, and the title-bar arm is never evaluated.
**This is the brief's stated arithmetic, and I confirm it at that file:line in v0.48.2.** The
sibling's patch does not touch `mouse_region()` or `update_mouse_pointer_shape()` at all — neither
patch lists `kitty/mouse.c` among its files (§1.3).

**What the action DOES give:** at `kitty/mouse.c:1362-1363` (v0.48.2), inside `mouse_event()`:

```c
    } else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
        mouse_cursor_shape = POINTER_POINTER;
```

Once the action has armed the drag, `global_state.window_being_dragged.id` is non-zero, so the very
next mouse event flips the cursor to the hand. **So: text cursor on hover, hand from the moment you
press.** That is a genuinely different UX from a real title bar and it is a real gap against
requirement (c)'s "shows a MOUSE HAND on hover".

**No config route exists.** `kitty/options/definition.py` (v0.48.2) has exactly three pointer-shape
options — `pointer_shape_when_grabbed:1122`, `default_pointer_shape:1133`,
`pointer_shape_when_dragging:1143` — all **per-window**, none per-region. The only other lever is the
OSC-22 pointer-shape stack (`kitty/screen.c:1971`, `:2059`), which is also whole-pane and is set by
the *program*, not by a region. **A per-region hand cursor requires C.** This is the one requirement
the sibling's work cannot reach, and it is precisely the gap the lead's `mouse_region()` change
closes.

### 2.3 (a) zero layout shift — **NOTHING, and nothing needed**

The action neither draws nor reserves anything. It is inert until a press. It neither helps nor
harms (a). ✅ neutral.

⚠️ **One exception, and it is a live behaviour, not a theory.** The docstring says:

> While the drag is in progress kitty temporarily shows window title bars so that other windows can
> be used as drop targets, hiding them again when the drop completes.

Showing title bars mid-drag **is a relayout** — that is the same row-stealing SIGWINCH that makes
⌘⌥B unacceptable, applied for the duration of a drag. The sibling flags this explicitly in the PR:
*"Happy to change it if you would rather the action suppressed it."* **For our design this is a
DECISION, not a detail:** a drag that momentarily shifts every pane's content by one row, then shifts
it back, arguably violates (a) during the drag. UNMEASURED: I did not observe the shift; it is
asserted by the action's own docs and by `start_window_drag`'s force-show behaviour, which the
sibling's `tabs.py` hunk is entirely about (§4.4).

### 2.4 (b) fixed under scroll — **NOTHING**

The action reads mouse state; it draws nothing. (b) is entirely the drawing layer's problem. ✅ neutral.

### 2.5 (d) SF Pro font — **NOTHING**

Not in scope for a mouse action. ✅ neutral.

### 2.6 Precisely what it does NOT do — the enumerated negative

1. **No hand cursor on hover** (§2.2) — the single hard miss against (c).
2. **Draws nothing.** No band, no text, no font. (a), (b), (d) untouched.
3. **Binds no default.** PR § Checks: *"No default `mouse_map` ships — the action is inert until a
   user binds it."* We must add the `mouse_map` ourselves.
4. **Must be bound to `left press` and must be the first element of a `combine`** (§1.7) — a hard
   constraint on how we wire ⌘⇧B.
5. **Its region test is in CELLS, not pixels** (§2.1) — it cannot express "the band, and only the
   band" if the band is not exactly coincident with text row 0.
6. **Not built, not installed.** Both patches are *files in a repo*. The operator runs
   `/Applications/kitty.app` (Homebrew cask). The sibling's own negative control proves this:
   PR § Verification, the installed build resolves to
   `/Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/…/kitty/__init__.pyc`,
   i.e. a **frozen** build — so **no kitten monkeypatch can add this action to the running kitty**,
   and nothing in either patch is live today.
7. **The v0.48.2 backport deliberately omits the Q5 `on_window_drop` ordering fix**, and the PR
   states the hazard it closes is **present** in v0.48.2 (§4.4). Inheriting the backport inherits
   that bug.
8. **Untested on v0.48.2 as a unit suite** — `kitty_tests/base.py` is master-only, so the 8-unit test
   file exists only for master. v0.48.2's evidence is the 8-row sandbox table in the PR.

---

## §3 — Does the lead's `render_a_bar` top-band patch conflict, or compose?

**Verdict: THEY COMPOSE. On the v0.48.2 backport there is ZERO file overlap with the two files the
band design must change (`kitty/shaders.c`, `kitty/mouse.c`). The only textual collision risk is a
5-line import block in `kitty/window.py` and the `PyMethodDef` table in `kitty/state.c` — both are
trivial, additive, and resolvable by ordering.**

### 3.1 The design target EXISTS IN v0.48.2, not just master — this is load-bearing

The lead's discovery was cited without a tree. I verified it in **the build the operator runs**:

| thing | ~/kitty-482 (v0.48.2, `2cb1d95c3`) | ~/kitty-dev (master, `1d67ecd47`) |
|---|---|---|
| `render_a_bar(const UIRenderData*, WindowBarData*, PyObject *title, bool along_bottom)` | `kitty/shaders.c:836-887` | `kitty/shaders.c:1254` |
| `draw_hyperlink_target` (consumer 1) | `kitty/shaders.c:911-933` | `kitty/shaders.c:1332` |
| `draw_window_number` (consumer 2) | `kitty/shaders.c:938-943` | `kitty/shaders.c:1363-1367` |
| `WindowBarData title_bar_data, url_target_bar_data` | `kitty/state.h:276` (struct at `:220-226`) | present |
| macOS `draw_window_title` → `cocoa_render_line_of_text` | `kitty/glfw.c:1074 (#ifdef __APPLE__)`, function at `:1083`, call at `:1092` | `kitty/glfw.c:1083` per brief |

So the whole mechanism — CoreText text, RGBA upload, `GRAPHICS_PROGRAM` quad at a chosen viewport,
`draw_rounded_rect` border, drawn each frame at a fixed `Viewport` and **never anchored to a cell** —
is already compiled into the operator's build. The `along_bottom` parameter is the existing proof
that the bar's *position* is a free parameter (`shaders.c:871`: `if (along_bottom) border_rect.top +=
ui->screen_height - border_rect.height;`), which is exactly the degree of freedom a top band needs.

### 3.2 File-by-file overlap matrix

| file | sibling master patch | sibling v0.48.2 patch | band design needs it? | verdict |
|---|---|---|---|---|
| `kitty/shaders.c` | **no** | **no** | **YES** — a third `render_a_bar` consumer | ✅ **no conflict** |
| `kitty/mouse.c` | **no** | **no** | **YES** — `mouse_region()` ordering + hover shape | ✅ **no conflict** |
| `kitty/options/definition.py` | **no** | **no** | **YES** — the new option | ✅ **no conflict** |
| `kitty/window.py` | 4 import hunks + 1 method | 4 import hunks + 1 method | **probably** — the `set_geometry` band arithmetic | ⚠️ **import block only** |
| `kitty/state.c` | 2 hunks (`:1979`, `:2035`) | 2 hunks (`:1745`, `:1798`) | **maybe** — if a new accessor is added | ⚠️ **method table only** |
| `kitty/state.h` | — | 1 hunk (`:445`, `OSWindow`) | **maybe** — a field on `Window`, not `OSWindow` | ✅ different struct |
| `kitty/tabs.py` | 1 hunk (`:2199`, `on_window_drop`) | **not ported** | **maybe** (drop classification) | ⚠️ see §4.4 |
| `kitty/options/utils.py` | 1 hunk (`:508`) | 1 hunk (`:460`) | no | ✅ |
| `kitty/glfw.c` | — | 1 hunk (`:587`) | no | ✅ |
| `docs/changelog.rst`, `kitty_tests/*` | yes | — | n/a | ✅ |

### 3.3 The two collisions, named by function, with the resolution

**(i) `kitty/window.py`, the `fast_data_types` import block.** The sibling adds four single-line
imports into the alphabetically sorted `from .fast_data_types import (…)` block — v0.48.2 hunks at
`@@ -44,…`, `@@ -62,…`, `@@ -70,…`, `@@ -85,…`, adding `GLFW_MOUSE_BUTTON_LEFT`,
`clear_click_queue_for_window`, `get_mouse_press_data_for_window`, `set_window_being_dragged`. If the
band design imports anything new from `fast_data_types` (e.g. a geometry setter), it lands in the
same sorted block and `git apply` of the second patch will reject on context. **Resolution: apply the
sibling patch FIRST, then write the band patch against the result.** Zero semantic conflict; it is
pure line drift.

**(ii) `kitty/state.c`, the `PyMethodDef module_methods[]` table.** Sibling adds two rows after
`M(get_mouse_data_for_window, METH_VARARGS),` (v0.48.2 `@@ -1798,6 +1833,8 @@`). Any band accessor
adds a row to the same array. Same resolution, same triviality.

**(iii) `kitty/state.h`.** No conflict by construction: the backport's field goes on **`OSWindow`**
(`:445`, `double mouse_left_press_x, …` after `double mouse_x, mouse_y;`); a band needs state on
**`Window`** (near `:267 WindowRenderData window_title_render_data;` / `:276 WindowBarData
title_bar_data, url_target_bar_data;`) — ~180 lines apart in a different struct.

### 3.4 They are more than compatible — the sibling has *shortened* the band design

Three pieces the band patch now does **not** have to build:

1. **The drag itself.** No new drag state machine, no payload builder, no drop classifier. Bind
   `mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window 1` and the band is draggable.
2. **The `left_press_x/y` field + write site** (v0.48.2 `state.h:445`, `glfw.c:587`). Any
   press-relative work in the band inherits this.
3. **The proof that a Python-dispatched mouse action can arm a C drag correctly**, including the two
   non-obvious guards (the click-queue clear, and the window-keyed rather than callback-keyed press
   read). That reasoning is transferable verbatim.

### 3.5 The one thing the band patch MUST still do in C, and where

Everything above leaves requirement (c)'s **hand cursor on hover** unreached. The single blocking
fact, re-measured: `contains_mouse(w)` — **~/kitty-482 `kitty/mouse.c:270-273`** — tests
`w->render_data.geometry` **inflated by the padding** (`window_top(w) = geometry.top - padding.top`,
`:260-262`). A band drawn over the pane's own row-1 pixels is inside that rect, so the loop at
`:1069` breaks on the `contains_mouse` arm and the `in_title_bar` arm at `:1070-1078` is unreachable.

🚨 **And this stays true even for a band that steals no row.** The row-stealing today happens in
Python, at **~/kitty-482 `kitty/window.py:1050-1068`**:

```python
        show_tb = self.show_title_bar and new_geometry.ynum > 1
        if show_tb:
            render_ynum = new_geometry.ynum - 1          # <-- THE STOLEN ROW
            cell_width, cell_height = cell_size_for_window(self.os_window_id)
            if position == 'top':
                render_top = new_geometry.top + cell_height
                ...
                tb_top = new_geometry.top
                tb_bottom = new_geometry.top + cell_height
```

A band variant that keeps `render_ynum = new_geometry.ynum` and `render_top = new_geometry.top`
while still publishing `tb_top/tb_bottom` through `set_window_title_bar_render_data`
(**`kitty/state.c:1006-1016`**) gets (a) zero shift *and* a populated
`window_title_render_data.geometry` for free — **but `render_data.geometry` then also starts at
`new_geometry.top`, so `contains_mouse` covers the band and the hit test still loses.** The C
ordering change in `mouse_region()` is therefore **not optional and not substitutable**; it is the
irreducible C delta of the whole design. It is also, happily, in a file neither sibling patch opens.

**Where the option lives:** `kitty/options/definition.py` (v0.48.2) already carries the
title-bar family at `:1941 window_title_bar`, `:1952 window_title_bar_min_windows`,
`:1988/:1999/:2010/:2021` the four colours, `:2031 window_title_bar_align` — an
`window_title_bar_overlay`-style boolean belongs beside them, and the row-reservation decision is
read at `kitty/layout/base.py:408-415`.

---

## §4 — Rulings and known issues in `KITTY_DRAG_ACTION.md` that CONSTRAIN the new design

Source: `/Users/chrisren/Development/.worktrees/kitty-drag-impl/docs/plans/KITTY_DRAG_ACTION.md`
(122,272 bytes). § 4 = `:323`, § 6 = `:1503`, § 7 = `:1530`. The § 2 safety block (`:138`) is
included because three of its findings bind harder on the band design than anything in § 4.

**The three the brief names first, each re-verified by me in ~/kitty-482:**

### 4.1 THE WEDGE — `window_being_dragged` has NO C-side clear (**CONFIRMED, independently**)

Plan `:192-197`. I re-ran the positive-controlled grep in **~/kitty-482** rather than trusting it:

```
$ grep -rn "window_being_dragged" kitty/*.c kitty/*.h
kitty/mouse.c:933    if (button > -1 || global_state.window_being_dragged.id) {
kitty/mouse.c:1362   } else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
kitty/mouse.c:1365       if (!tw && global_state.window_being_dragged.id) {
kitty/mouse.c:1366           tw = window_for_window_id(global_state.window_being_dragged.id);
kitty/state.c:1762   #define wbd global_state.window_being_dragged
kitty/state.c:1764   set_window_being_dragged(...)     ← the ONLY writer, and it is Python-driven
kitty/state.c:1771   get_window_being_dragged(...)
kitty/state.h:534    } window_being_dragged;

$ grep -rn "zero_at_ptr(&global_state.tab_being_dragged" kitty/*.c   # POSITIVE CONTROL
kitty/mouse.c:951:        zero_at_ptr(&global_state.tab_being_dragged);
```

The tab equivalent **does** have a C-side clear, so the instrument can find one; the null for
`window_being_dragged` is informative. **Constraint on the band design:** any path that can set the
flag without a guaranteed LEFT release to clear it wedges the whole fleet — every mouse event in
every OS window routes to the title-bar handler (`mouse.c:1362`), killing selection, URL detection,
border resize and click dispatch. This is exactly why `mouse_drag_window`'s guard 1 (left-button
only) is not optional, and why the band must be driven through that action rather than through a
kitten that calls `set_window_being_dragged` itself.

### 4.2 BUTTONLESS SYSTEM DRAG (plan `:198-200`)

Once wedged, the next bare pointer move past `drag_threshold` starts a **real system drag with no
button held** — the motion block has no `mouse_button_pressed` test. **UNMEASURED by me** (I did not
re-read the motion block; the plan says it was verified in the shipped 0.48.2 bytecode).
**Constraint:** the band design must not introduce a second arming path. One armer, the sibling's
action, with its four guards.

### 4.3 "A `mouse_map` kitten ALWAYS consumes the event" — plan § 2.2 **M3**

> **An in-kitten guard is NOT a safety mechanism.** A `mouse_map … kitten …` **always consumes the
> event** regardless of what the kitten returns (`boss.py:2405` discards it) — proven live, with the
> not-consumed channel controlled: `kitten @ action "definitely_not_an_action"` → rc **1**, the
> declining kitten → rc **0**

Plan Q13 (`:560`) restates it: `Boss.kitten` discards its return value, so a config-only handler is
*"arm, or do nothing, but always swallow."*

🚨 **This is the single strongest argument for the band design over anything kitten-based, and it is
already measured — do not re-derive it.** A real action (`mouse_drag_window`) CAN return `True` to
pass the press through; a kitten cannot. Requirement (c) needs a band that is grabbable while
*everything below it still belongs to Claude Code*, and only the action route can express that.
Plan `:571-575` states the consequence in one line: *"Under A, the chord is swallowed everywhere in
the pane… Under B, a press below the header band returns `True` and passes through."*

### 4.4 Q5 — the `on_window_drop` ordering fix, and the gap the backport leaves

Plan Q5 (`:~640`) rules the fix ships **as a separate commit in the same PR**, on evidence that
matters to us: at `window_title_bar_min_windows 0` (**our live setting**) no window has a title-bar
hit region, *"so no title-bar drag can be started"* — the defect needs `toggle_window_title_bars`
first. **A content-press action is the first path that reaches this divergence in stock config.**
`on_window_drop` calls `_clear_force_show_title_bars()` **before** classifying the pointer
(master `:2202` before `:2234`; v0.48.2 `:2035` before `:2074`), so the preview shows "swap" over a
drop that performs a directional insert.

⚠️ **The v0.48.2 backport deliberately does NOT carry this fix** (patch header + PR § Backport notes
item 2), and the PR states the hazard **is present** in v0.48.2 and names the minimal transform:
move `tabs.py:2035`'s clear into a `finally:` wrapping from `central, tab_bar = viewport_for_window(...)`
to the end of the method. **Constraint: if the band design ships on a patched v0.48.2 — which is the
only way the operator gets it — this fix must be written for v0.48.2 by hand. It is open work.**

### 4.5 Every other § 4 ruling that binds, with its one-line consequence

| Q | Ruling | Consequence for the band design |
|---|---|---|
| **Q2** | arm with `drag_started=False`, threshold-preserving; the origin comes from `OSWindow.mouse_left_press_x/y`, **master-only**, added by the backport | ✅ already delivered by the sibling patch; reuse, do not rebuild |
| **Q2 caveat / Q24** | the field is written on **every** left press anywhere in the OS window and is **NEVER cleared** — on `combine`'s `drain_actions` timer it is **STALE, not NULL**, and *"stale is worse than NULL"* (a successful arm at the wrong origin) | 🚨 **the band's `mouse_map` must put `mouse_drag_window` FIRST in any `combine`, and bound to `left press`** — this is the same constraint §1.7 derives from the action's own docstring, arrived at independently |
| **Q3 / Q7** | the region unit is **CELLS**, forced not preferred: `get_mouse_data_for_window` returns only `cell_x`, `cell_y`, `in_left_half_of_cell` (v0.48.2 `state.c:1742-1743`) — there is **no Python read path for pixels** | the band's grab region is expressed as `rows N`, and the band's pixel height must therefore stay locked to a whole number of cells (§2.1) |
| **Q7(d)** | **do NOT scope to one row** for the *overlay* — at a 16px cell `rows=1` collapses to 4px of grabbable band, because `window_drag_tolerance`'s frame is a constant in **device px** while the band shrinks with the font | ⚠️ **this ruling is about the 2-cell PNG overlay, and a render_a_bar band is ONE cell + 2px + borders (`shaders.c:838`, `bar_height = ui->cell_height + 2`). The `rows 2` ruling does NOT transfer.** The band design needs its own re-derivation of the row count; at today's 45px cell `rows 1` = 45px of grab, which is ample, but at a 16px cell it is 16px against a 12px tolerance frame. **Re-measure; do not inherit `2`.** |
| **Q4** | `mouse_drag_window`, on `Window`, group `mouse`; do **not** name it `start_window_drag` (collides with `Boss.start_window_drag`, and a Boss-side collision is **SILENT** — Python keeps the last definition and the incumbent title-bar drag dies at thumbnail-callback time) | naming discipline for any new band action |
| **Q6** | **do NOT suppress the force-show.** Not reachable from the action; what it buys is only the drag-over preview; and it would get the PR judged on the wrong diff | the mid-drag row-steal (§2.3) is **accepted, by ruling** — it is not a defect the band design must fix |
| **Q12** | chord = **`cmd+shift+left press`**, measured FREE in both `grabbed` and `ungrabbed` on the loaded config with two positive controls reading TAKEN. `cmd+left press` is rejected because it **silently kills** `cmd+left click → mouse_handle_click link` (`config/kitty.conf:821`, commit `175eeb7d8`), a binding built to the operator's own complaint. `ctrl+alt+left` is kitty's shipped `mouse_selection rectangle`. `cmd+left doublepress` is a live fourth option (`doublepress` has trigger count **2**, a press-family trigger, so it fires synchronously) | **use `cmd+shift+left press`**; this is measured chord-space, not taste |
| **Q16** | patch **both** trees; **never** prove which build you are running from `--version` (master `1d67ecd` also declares `Version(0, 48, 2)`) — use `kitty +runpy 'import kitty; print(kitty.__file__)'`. **Path-length wall: repo path ≤ 80 chars** or `./dev.sh deps` fails silently (`max_root_len = 106`, binary-searched) | any new build tree must live at a short path |
| **Q17** | a test may stop one call short of the OS; patch **`kitty.tabs.start_drag_with_data`** (master `tabs.py:2059` / v `:1906`) for a *window* drag — **not** `kitty.window.start_drag_with_data`, which is the *text-selection* drag. Do **not** add an `in_test_mode` hatch | test discipline |
| **Q21** | `window_title_bar_min_windows 1` is **ruled NO**, twice against the operator — it is the ⌘⌥B ON state this work exists to delete | do not reopen |
| **Q1** | **both deliverables ship**; the overlay is *"the shipping implementation"* until an upstream release carries the action — *"Phase 3 must not write A as throwaway"* | the render_a_bar band is a **third** deliverable that supersedes both; state that explicitly rather than letting it look like a fourth prototype |

### 4.6 § 6 Definition of done — the four criteria that bind a NEW design

Plan `:1503-1527`. Most of the nine are route-A specific. The four that transfer:

* **#4** — *"A human has driven the gesture"*, and the check is specified to a precision worth
  copying: **"W4's script prints a before/after `neighbors` diff showing the layout changed,
  set-change tested BEFORE order."** (That last clause is the repo's own
  *witness-must-test-the-set-before-the-order* rule.) **No agent can sign off (c).**
* **#5** — it must work *in his live kitty, in his own panes, by his own hand.*
* **#7** — a patched v0.48.2 build must arm the drag, proven by `kitty +runpy 'import kitty; print(kitty.__file__)'`, **never `--version`**.
* **#9** — ***"Nothing in this plan posted anything upstream"*** — no PR, no issue, no comment. The
  operator's call. **This binds the band design identically.**

### 4.7 § 7 Known issues — the seven, and which reach the band design

Plan `:1530-1568`.

| # | Issue | Reaches a render_a_bar band? |
|---|---|---|
| 1 | **The drag still steals a row, and more than one** — PTY resize twice, **≥4 relayouts per tab**, plus a **second** row per OS window showing fewer than `tab_bar_min_tabs` tabs (default **2**; `tab_bar_min_tabs 1` is commented out at `config/kitty.conf:685`) | 🚨 **YES.** This is the residual that survives the whole design: zero shift when idle, a row stolen *during* the drag. § 7.2's own words: *"you stop paying the row for the decision to rearrange; you still pay it for the rearrange."* |
| 2 | **One drag turns the operator's toggled-on bars off across every tab of every OS window** — `_clear_force_show_title_bars` iterates `boss.all_tab_managers` while `toggle_window_title_bars` sets the flag only on `self.active_tab_manager` | **YES if ⌘⌥B remains bound.** If the band replaces ⌘⌥B entirely, this stops mattering — an argument for retiring the ⌘⌥B chord along with the overlay. |
| 3 | **A double chord-press under threshold pops the rename prompt** (v `tabs.py:1878-1881` / master `:2031-2034` reach `w.set_window_title()`) | **YES** — and it is on W4's hand-test list because "a hand finds it in seconds". |
| 4 | **The unrecoverable state**: if the dragged window closes while the flag is set **and** the pointer is over no window, arm 7 resolves `tw == NULL` and calls nothing, ever. Window/tab teardown does **not** clear it | **YES** — inherited wholesale, same C state |
| 5 | **Two uncaught-exception paths leave bars forced up fleet-wide**: `draw_single_line_of_text` can raise `KeyError`/`RuntimeError`, and `len(title_pixels) // (width*4)` raises `ZeroDivisionError` at `width == 0` — **neither is an `OSError`**, so `except OSError` (master `tabs.py:2060`) misses both. On **master** additionally `child-monitor.c:980`'s `if (!w) return;` leaves `thumbnail_request_queue[0]` unpopped **with no timeout**, wedging every future window drag, tab drag and `kitten screenshot` for the process's life | **YES** — and note the band design's own drawing path shares `draw_window_title`, so a `width == 0` band is a live concern |
| 6 | Route A monkeypatches / calls drifting APIs | ❌ N/A — a C patch does not monkeypatch |
| 7 | **The press site is not inert**: `Window.drag_source.initial_left_press` is armed by `arm_potential_drag()` on **every** content-area LEFT press with **no modifier test**, and on the content-press path is **never cleared** (`clear_potential_drag()` runs only from `handle_button_event`, whose release is taken by arm 7). *"Whether that ever changes an outcome is UNKNOWN"* | **YES, and it stays UNKNOWN.** Carry it as an open unknown, not as a settled non-issue. |

### 4.8 The § 2 safety rules, which bind every wave including this one

* **S1** — no wave may write `config/kitty.conf` in a way that changes BEHAVIOUR before the arming wave. Comment-only edits are permitted.
* **S2** — all prototyping in a sandbox `KITTY_CONFIG_DIRECTORY`, never `~/.config/kitty`.
* **S3** — **the kitten/binary lands before the line that names it.** A `mouse_map` naming an absent target raises `FileNotFoundError` → `show_error('Key action failed')` **and consumes the press** — an error overlay on every chord press in his live panes.
* **S4** — never assume a land is inert: `globinclude drag-arm.d/*.conf` is live ~100 ms after converge via kitty's `__watch_conf__` child, and `deploy-live` fires `cc-kitty-reload` every 600 s.
* **M1/M2** — **arm by WRITING the drop-in, disarm by EMPTYING it. A deletion never fires the watcher.**
* **M3** — see §4.3.
* **§ 2.2 verdict** — a SIGUSR1 reload **rebuilds `opts.mousemap` from a fresh empty dict** (`config.py:134`, `:141`), read live at every click (`window.py:1399`), so a bad line is fully withdrawable in ~3 s. **A restart is NOT the recovery path.** ⚠️ But *"the WEDGE is C state, and no config reload clears it"* — the config is withdrawable in 3 seconds; the wedge is cured by a click; **neither cures the other.**

---

## §5 — Every MEASURED number in `config/kitty.conf` §3 / §3b the new design must respect or supersede

Source: `/Users/chrisren/Development/claude-infrastructure/config/kitty.conf` (1,366 lines,
read-only). §3 = `:126-298`. §3b = `:299-607`. Items marked ⧉ live in §7 but are cross-referenced
**by** §3b and are load-bearing here, so they are included with their own line numbers.

### 5.1 Live option values today (grepped from the file, not recalled)

| line | setting | value |
|---|---|---|
| `:327` | `window_drag_tolerance` | **6** (pt) |
| `:978-979` | `font_family` / `font_size` | Monaco / **18.0** |
| `:1032` | `modify_font cell_height` | **94%** |
| `:1109` | `window_padding_width` | **`0 5 0 5`** (top 0, right 5, bottom 0, left 5) |
| `:1157` | `window_border_width` | **1pt** |
| `:1182` | `draw_minimal_borders` | no |
| `:1208` | `placement_strategy` | **top** |
| `:1245` | `window_title_bar_min_windows` | **0** |
| `:1259-1263` | align + 4 colours | left / `#2f62d8` / `#ffffff` / `#3f5590` / `#f4f6fd` |
| `:1345` | `globinclude` | `drag-arm.d/*.conf` |
| `:123` | `listen_on` | `unix:/tmp/kitty-{kitty_pid}` |
| — | `window_title_bar` (top\|bottom) | **NOT SET** → kitty's default `top` |

### 5.2 The measurement table — number, date, source line, and what it binds

| # | Measured number | Date | Line | What it binds on the new design |
|---|---|---|---|---|
| **M1** | **The cell is 45 device px = 22.5 pt** (`font_size 18` × `modify_font cell_height 94%`, at dpi 144 / scale 2) | 2026-09-16 | `:1088-1090`, `:483-486` | `render_a_bar`'s `bar_height = ui->cell_height + 2` (~/kitty-482 `shaders.c:838`) ⇒ a band of **47 px** + 2×`border_width`. **The band is NOT one cell; it is one cell + 2 px + borders.** Every "one cell" assumption inherited from the overlay work must be re-derived. |
| **M2** | **The ~16 pt cell figure is REFUTED.** It came from dividing the deltas of a coarse padding sweep (`top_pad 0/10/17/25`) — *"which measures my sample spacing, not the cell"* | 2026-09-16 | `:487-493` | **Supersede.** Any new quantised measurement must **bisect for the band edge**, never divide deltas. |
| **M3** | **Rows depend on TOTAL vertical padding, not the top term.** `10 5` is top 10 **plus bottom 10** = 20 pt | 2026-09-16 | `:483-486`, `:1075-1077` | any padding arithmetic for a band must sum both edges |
| **M4** | **The 30-row band spans total vertical padding ≈ 3..25 pt** (≈23 wide) at this geometry | 2026-09-16 | `:484-486` | a band that consumes ≤ 2.5 pt of padding budget is free at most heights |
| **M5** | **`window_border_width` = 1 pt = 2 device px**, NOT the "0.5 pt hairline" the prose said. `effective_border()` = `max(1, pt_to_px(1.0))`, `pt_to_px = round(pt*dpi/72)` | 2026-09-16 | `:315-324` (the correction), `:1157` | `render_a_bar` draws a rounded border of `ceil(thickness_as_float(os_window, 1))` px — so the band carries **2 px** of border top and bottom on this box |
| **M6** | **`window_drag_tolerance 6` pt is a constant in DEVICE px**, so the grab frame does not shrink with the font while a band does | 2026-09-15/16 | `:306-314`, plan Q7(d) | at a small cell the tolerance frame can eat most of a one-cell band — **re-derive the band's `rows` argument; do not inherit the overlay's `2`** |
| **M7** | **`window_padding_width 22.5 5 0 5` (the reservoir) was LANDED and then REMOVED 2026-09-16** on the operator's screenshot *"Is there a way to remove the top margin?"* — because 45 px of dead space all day to make a rare gesture zero-shift is *"the permanent cost the operator has rejected twice in this very file"* | 2026-09-16 | `:1097-1108` | 🚨 **The reservoir is CLOSED. A render_a_bar band must consume ZERO padding.** Re-proposing a reservoir re-opens a decision the operator made twice. |
| **M8** | The reservoir's own cost, when it existed: **total vertical padding 20 → 22.5 pt costs one row at ~11% of window heights** (2.5/22.5); measured at **1 of 7** sampled heights (900 px: 39→38) | 2026-09-16 | `:1061-1071` | the quantitative reason M7 is closed |
| **M9** | **A single-pane height sweep returns a CLEAN NULL for a two-pane defect** — 7/7 heights identical single-pane, while 900 px two-pane went `[19,19] → [18,18]` | 2026-09-16 | `:456-463` | **any band height sweep must vary the PANE COUNT**, not just the window height |
| **M10** | **`toggle_window_title_bars` costs exactly ONE row** — isolated instance, `kitty @ ls` around each `load-config`: OFF 30 rows → bare toggle **29 rows** | 2026-09-15 | `:395-399` | the baseline the band must beat: 1 row + PTY resize |
| **M11** | **The config-swap pair holds 29/29/29/29 over 4 swaps** with `min_windows 1` | 2026-09-15 | `:400` | the reservoir route worked; it was rejected on M7, not on mechanics |
| **M12** | **The `0 5 0 5` ⇄ `22.5 5 0 5` pair held 30/30 over 6 swaps, SIGWINCH 0 throughout**; control (forced row change) → 27,27 with SIGWINCH 1→2, *"the counter is live"* | 2026-09-16 | `:495-503` | **the SIGWINCH counter with a positive control is the instrument the band design must use for (a).** Reuse this harness. |
| **M13** | **Pixel evidence for zero shift:** content row 1 at **y 465..644 in BOTH states**; the only changed rows are **y 420..464, one band of 45 px = one cell** | 2026-09-16 | `:503-505` | the acceptance shape for (a): a pixel diff confined to the band's own rows |
| **M14** | **The bar IS drawn** — one variable, fixed `0 5 0 5`: `mw 0 → 31,15,15` vs `mw 1 → 30,14,14` | 2026-09-16 | `:506` | the control that separates "bar drawn" from "bar configured" |
| **M15** | 🚨 **THE NO-OP DRAG RESULT — requirement (c)'s second half, already measured.** Synthetic no-op drag, pane order unchanged, identical drag geometry both arms: **bars up via the action → 29,29 → 30,30, the title VANISHES (the defect); bars up via `min_windows` → 30,30 → 30,30 ×3, bar still at y=221pt** | 2026-09-16 | `:509-517` | **A `force_show_title_bars`-driven bar CANNOT satisfy (c)'s no-op-drag clause; a `min_windows`-driven one can.** `Layout.__call__` computes `show_title_bar = force_show or (min_windows > 0 and visible >= min_windows)` (~/kitty-482 `kitty/layout/base.py:412`), so `_clear_force_show_title_bars` cannot reach a min_windows bar. **A render_a_bar band must be driven by an option read at layout time, NOT by the force-show flag** — otherwise it inherits the vanishing. |
| **M16** | **With `min_windows >= 1` the built-in `toggle_window_title_bars` action becomes INERT on every tab** (two presses, rows unchanged) | 2026-09-16 | `:518-520` | if the band's option is read the same way, ⌘⌥B goes inert — decide deliberately |
| **M17** | 🚨 **SF PRO IS UNREACHABLE ON kitty's REAL BAR** — four spec forms, one variable, all four → **Menlo Italic (monospace: True)**: `italic_font /System/Library/Fonts/SFNS.ttf` → *"font was not found, falling back to Menlo"*; `family="SF Pro"`, `family="SF Pro Text"`, `postscript_name=SFPro-Semibold` → Menlo Italic | 2026-09-16 | `:521-535` | **This is the measured proof that requirement (d) is unreachable through the CELL-GRID bar, and therefore the measured case FOR `render_a_bar`** — which does not use the cell font at all (`draw_window_title` → `cocoa_render_line_of_text`, ~/kitty-482 `glfw.c:1083-1092`). **Cite this as the justification, not as an obstacle.** |
| **M18** | kitty's bar template exposes only **fg · bg · bold · italic · nobold · noitalic · reset** — no font/size/weight | 2026-09-16 | `:522-525` | same |
| **M19** | **SIZE is unreachable independently of face** — the bar is one cell, cell metrics are global, and the overlay band is **1.378 cells** | 2026-09-16 | `:535-536` | a render_a_bar band is `cell_height + 2` px, i.e. **1.044 cells** at 45 px — closer to one cell than the overlay, which is a *point in its favour* for (a) |
| **M20** | **⌘⇧B verified FREE** against the loaded keymap, probe positive-controlled against ⌘D which read TAKEN | (kitty 0.48.2 era) | `:373-374` | the chord is ours; keep it |
| **M21** | **The overlay re-asserts every 2 s** because kitty frees a placement on any clear or scroll *"without telling anyone"* | 2026-09-14 | `:473-476` | the cost the band design deletes — state it as the win |
| **M22** | **Overlay measured on live Claude panes: 4/4 labelled, rows 47 before and after, content unmoved** | 2026-09-14 | `:471-473` | the overlay's (a) is real; the band must match it |
| **M23** | **The `0.5 pt hairline` phrase at `:1100` is CORRECT and must NOT be "fixed"** — it names the stock default as the before-state | 2026-09-16 | `:325-327` | a trap for any future corrector |
| **M24** | **`tab_bar_min_tabs 1` is NOT enabled** — the line is commented out at `:685`, so the default **2** stands, and every single-tab OS window pays a second row during a drag | — | `:680-686`, plan §7.1 | compounds the mid-drag row cost |

### 5.3 The three REFUTED claims in §3b — mark, never delete, and the one third that STANDS

`config/kitty.conf:345-367`, the 2026-09-16 W1 correction:

> **WHAT IS REFUTED:** *"can never be dragged, however it is drawn"*. `v0.48.2 kitty/mouse.c:1362`
> reads `} else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {` and the
> `||` **BYPASSES** the hit test outright once `window_being_dragged` is set…
>
> **WHAT STILL STANDS**, and was attacked directly rather than left unexamined: *"not in kitty's
> hit-test"* (true — `mouse_region`'s title-bar arm tests `window_title_render_data`, which a
> graphics placement never populates) and *"can never carry a hand cursor"* (true — the
> `POINTER_POINTER` shape is set by that same arm, on the hit test the placement cannot pass).

**I independently confirm both surviving thirds** in ~/kitty-482 (§2.2 above): `mouse.c:1069-1078`
and `mouse.c:1127-1144`. 🚨 **And note the asymmetry the band design inherits: a `render_a_bar` band
DOES have a place to populate `window_title_render_data` from (`state.c:1006 set_window_title_bar_render_data`),
which a graphics placement never had — so the "can never carry a hand cursor" clause is refutable
FOR THE BAND, but only together with the `mouse_region()` ordering change (§3.5).** That is the one
claim in this file the new design is positioned to overturn, and it must be marked in place when it is.

`config/kitty.conf:547-560`, the Q19 item-4 narrowing, which is the design's opening stated in the
operator's own file:

> `window_title_render_data` is read in `mouse.c` at **exactly one line** — v0.48.2 `:1072`, master
> `:1115` — and that line is inside `mouse_region()` … **Only the HIT TEST needs a real bar.**
> Neither the drag STATE MACHINE nor the routing touches that struct … That is a narrower gap, and
> a reachable one — which is the plan's whole opening.

### 5.4 The STRUCTURAL claim the band design must explicitly overturn

`config/kitty.conf:562-568`:

> **ONE CHORD CANNOT DO BOTH**, and the reason is structural rather than a missing option. The
> handle has to be a real bar; a real bar takes a text row; taking a row is the PTY resize that IS
> the jitter the overlay exists to remove.

**The middle premise — "a real bar takes a text row" — is exactly what `render_a_bar` falsifies**,
because `render_a_bar` draws at a viewport, not into the cell grid, and `along_bottom` proves the
position is a free parameter (~/kitty-482 `shaders.c:871`). ⚠️ **But the claim is only falsified once
the band ALSO carries the hit test**, i.e. once `mouse_region()` changes. Until then the band is
`render_a_bar`-shaped and still not hit-tested — pixels again, with a nicer producer.
**Mark this claim refuted IN PLACE only after the hit test is measured working, never before.**

### 5.5 The safety facts §3b establishes about the LIVE machine

* `:1345` `globinclude drag-arm.d/*.conf` — the empty drop-in exists **today**. Arm by writing it,
  disarm by **emptying** it (a deletion never fires kitty's `__watch_conf__` watcher; plan § 2.2 M2).
* `:600-606` — **the two chords must clear each other first**, in both directions, or the operator
  gets the double-title screenshot he already sent once (2026-09-15: *"the title above drags but not
  the title below. why do we have double title"*). A band design that keeps either existing chord
  inherits this guard; a design that retires both deletes it.
* `:607-609` — `drag_threshold` is deliberately left at its default **5 px**: *"lowering it turns
  ordinary text selection near a border into an accidental window drag. A value of 0 disables
  dragging entirely."* The sibling's guard 2 refuses to arm at 0, which is consistent.

---

## §6 — Is there an UPSTREAM option that already draws a window title outside the cell grid?

### 6.1 Verdict — a CLEAN NEGATIVE on options, and a LOUD POSITIVE on capability

**There is NO option, in v0.48.2 or on master, that draws a per-window title outside the cell grid.**
The one option family that draws a per-window title (`window_title_bar*`) allocates its row **from the
cells**, in both trees.

🚨 **But the CAPABILITY ships, it is compiled into `/Applications/kitty.app` today, and it is already
user-reachable by a default keybinding.** See §6.4 — this is the most decision-changing thing in this
document and it substantially de-risks the lead's design.

### 6.2 The sweep — exhaustive, by option NAME, both trees

Method: extract **every** `opt('name', …)` from `kitty/options/definition.py` in each tree and diff
the full sets. This is a census of the whole option surface, not a keyword filter.

```
$ grep -oE "^ *'[a-z_0-9]+'," kitty/options/definition.py | tr -d " '," | sort -u | wc -l
     245       # ~/kitty-482  (v0.48.2, 2cb1d95c3)
     251       # ~/kitty-dev  (master, 1d67ecd47)

$ comm -13 opts-482.txt opts-dev.txt      # MASTER-ONLY
custom_shaders
padding_fill_strategy
remap_modifiers
tab_title_max_lines
tab_title_wrap
window_border_radius

$ comm -23 opts-482.txt opts-dev.txt      # v0.48.2-ONLY
(empty)
```

**Master adds exactly six options over v0.48.2 and not one of them draws a title.** Read in full:

* `padding_fill_strategy` (`background` | `neighboring_cell`) colours **only the compensatory
  sub-cell strips**; its own text says *"the intentional padding from `window_padding_width` is
  always drawn using the background color."* It cannot host a band.
* `custom_shaders` is a post-processing pipeline. Nearest miss in the whole sweep — it does receive
  `mouse_pos` uniforms (master `shaders.c:2583-2584`, the same `mouse_left_press_x/y` the backport
  adds) — but it has no access to the window title string and is a full-frame effect, not a band.
* `window_border_radius`, `remap_modifiers`, `tab_title_max_lines`, `tab_title_wrap` — unrelated.

### 6.3 The title-drawing options, and why each fails

| option | tree(s) | why it is not this |
|---|---|---|
| `window_title_bar` | v0.48.2 `definition.py:1941`, master `:2010` — **`choices=('top','bottom')` in BOTH** | the position is a free parameter *within the grid*; both values allocate a cell row. `kitty/window.py:1056-1068` (v0.48.2) does `render_ynum = new_geometry.ynum - 1` for either value. |
| `window_title_bar_min_windows` | v `:1952` / m `:2021` | gates *when* the bar shows; the row cost is unconditional once shown |
| `window_title_template`, `active_window_title_template` | v `:1964`, `:1978` | text content only. `{custom}` runs a `draw_window_title(data)` Python hook from `window_title_bar.py` — still into the same one-row cell Screen |
| `window_title_bar_{active,inactive}_{fore,back}ground`, `window_title_bar_align` | v `:1988-2031` | colour and alignment only — **the measured reason (d) fails on this route**, §5 M17/M18 |
| `hide_window_decorations`, `macos_titlebar_color`, `wayland_titlebar_color`, `macos_show_window_title_in`, `macos_menubar_title_max_length` | both | **OS-WINDOW** chrome, not per-pane |
| `tab_bar_*`, `tab_title_*` | both | the TAB bar, one per OS window |
| `scrollbar*`, `progress_bar` | both | genuinely out-of-grid per-window decorations — **precedent that kitty does draw such things**, but neither carries text |

⚠️ **Naming trap:** the word "overlay" appears 9 times in `definition.py` and **never** means a drawn
band — in kitty's vocabulary an *overlay window* is a full-pane window stacked over another
(`launch --type=overlay`, v `:3719-3763`). Do not read those hits as a hit.

`grep -niE "outside the cell|overlay|above the (cell|grid|content)|z-index|floating"` over
v0.48.2's `definition.py` returns nothing relevant. No action mentions it either: the only
title-bearing `@ac()` in `window.py`/`boss.py`/`tabs.py` is `boss.py:2496`,
*"Show an error message with the specified title and text"*.

### 6.4 🚨 THE CAPABILITY ALREADY SHIPS, AND IT IS ONE KEYPRESS AWAY

`render_a_bar`'s second consumer is not the URL bar. It is the **window-number overlay**, and it
draws **`ui->window->title`** — the window's own title — **at the top, outside the cell grid**:

~/kitty-482 `kitty/shaders.c:938-943`:

```c
static void
draw_window_number(const UIRenderData *ui) {
    if (!has_window_number(ui->window, ui->screen)) return;
    unsigned title_bar_height = 0, requested_height = ui->screen_height;
    if (ui->window->title && PyUnicode_Check(ui->window->title) && (requested_height > (ui->cell_height + 1) * 2)) {
        title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false);
    }
```

`along_bottom = false` ⇒ **top**. Drawn from `draw_cells`' tail (`shaders.c:1381-1382`), after the
cell programs and after the graphics refs — i.e. **on top of content, every frame, at a fixed
viewport, never anchored to a cell.**

**What turns it on:** `has_window_number` is `screen->display_window_char != 0`
(`shaders.c:935`), set at `screen.c:4966`, driven by `Boss.visual_window_select_action`
(`boss.py:1687-1732`) — which kitty binds **by default** to `focus_visible_window` at
**`kitty_mod+f7`** (`definition.py:3971`), with `kitty_mod` defaulting to **`ctrl+shift`**
(`definition.py:3484-3485`). So on the operator's **installed, unpatched** kitty, **⌃⇧F7** should
already paint the title of every **non-active** pane in the tab (see §6.6 — the active pane is
excluded, and 3+ panes are needed) in a system-font band over content row 1, with no relayout.

**Why this matters more than any other finding here:**

1. It is a **live positive control** for (a), (b) and (d) simultaneously, on the shipping build,
   costing one keypress and no patch (in a 3-pane sandbox tab — §6.6). If ⌃⇧F7 shows a clean SF/system-font band with no content
   shift and it does not move on scroll, the entire drawing half of the design is de-risked before
   a line of C is written.
2. It means the band's visual identity, font, border, colours and z-order are **already decided by
   upstream code** — the new option's job shrinks to *"draw this bar persistently, and add a hit
   region"* rather than *"invent a bar"*.
3. It supplies the exact geometry contract: `bar_height = ui->cell_height + 2` and
   `border_rect.height = bar_height + 2*border_width` (`shaders.c:838`, `:870`) — so at this box's
   45 px cell the band is **47 px + 2×2 px = 51 px ≈ 1.13 cells**, *not* one cell. Every "one cell"
   assumption inherited from the overlay work must be re-derived against this (§5 M1).
4. It reveals a guard the new option must reproduce or deliberately drop:
   `requested_height > (ui->cell_height + 1) * 2` — **no bar on a window shorter than ~2 cells.**

🚨 **UNMEASURED — and it is the single highest-value 30-second check in this whole document.** I did
**not** press ⌃⇧F7: the only kitty instance available is the operator's live one with 9 working
agent sessions, and driving it is forbidden by my brief. **A sandbox instance settles it in one
keypress, and it should be the next thing anyone does.** If it does *not* render as described, the
lead's design premise needs re-examination before any C is written.

### 6.5 Changelog sweep

Master `docs/changelog.rst`, all "title bar" hits, and the `0.49.0 [future]` block read in full
(`:198-240`). Nothing adds an out-of-grid per-window title. The relevant entries:

* `:670-671` — *"Allow showing configurable window titles <window_title_bar> for individual kitty
  windows via a window title bar (:pull:`9450`)"* — this **is** the in-grid feature.
* `:507` — *"Allow drag and drop of windows to re-arrange them… See :ac:`toggle_window_title_bars`"*
  (`:pull:`9626``) — the drag machinery the sibling's action hooks into.
* `0.49.0 [future]` adds `custom_shaders`, `window_border_radius`, `remap_modifiers`,
  `padding_fill_strategy`, splits proportional sizing, a `scrollbar` value, `kitten @ screenshot`,
  `kitten @ set-os-window-title`, and `mouse_selection drag_or_normal_select`. **None is this.**

**So the negative is clean and the work is not unnecessary** — but the *drawing* half of it is
substantially already written, and shipping.

### 6.6 How to run the ⌃⇧F7 check correctly (three preconditions, read out of the code)

`Boss.visual_window_select_action`, ~/kitty-482 `kitty/boss.py:1687-1732`:

* **`window.screen.set_window_char(ch)` is called per visible window in the ACTIVE TAB** (`:1713-1721`)
  — not across OS windows. So the bands appear on that tab's panes only.
* 🚨 **≥ 3 VISIBLE PANES IN THE TAB ARE REQUIRED, not 2 — and this is the trap that returns a false
  negative.** `Tab.focus_visible_window` passes
  `only_window_ids=self.all_window_ids_except_active_window` (~/kitty-482 `kitty/tabs.py:1029-1034`),
  so **the active pane is excluded from the candidate set**. With 2 panes the candidate count is 1,
  `len(window_ids) > 1` is false, and `visual_window_select_action_trigger` fires immediately
  (`boss.py:1731-1733`) — focus just moves and **nothing is ever drawn**. kitty's own option text
  says so in as many words (`definition.py:3973-3975`: *"When there are only two windows, the focus
  will be switched directly without displaying the overlay"*). **Split the sandbox to three panes.**
* **The bands appear on the NON-ACTIVE panes only**, for the same reason. `kitty_mod+f8`
  (`swap_with_window`, `tabs.py:1036-1041`) has the identical exclusion.
* **A `only_active_window_visible` layout (i.e. `stack`) routes to an overlay chooser instead**
  (`:1707-1709`) and draws no bands. The live config is `enabled_layouts splits,stack` — **be in
  `splits`.**

It is modal (a `__visual_select__` KeyboardMode), so the bands stay up until a character or `Esc` —
which is exactly the dwell needed to scroll the pane underneath and settle requirement **(b)** in the
same keypress.

---

## §7 — Bottom line: what to REUSE, what to REBUILD, what is still OPEN

### 7.1 REUSE, verbatim

| # | Artifact | Where | Why |
|---|---|---|---|
| R1 | **`mouse_drag_window`, both patches** | `kitty-drag-impl/docs/patches/kitty-mouse-drag-window{,-v0.48.2}.patch` | it IS requirement (c)'s drag half, its `rows` argument was written for exactly a front-end-drawn header, and it adds no new C routing |
| R2 | **`OSWindow.mouse_left_press_x/y` + its `glfw.c` write site** | v0.48.2 patch, `state.h:445` / `glfw.c:587` | 5 lines the band design would otherwise have to discover; the PR proves a field without its write site *passes its own test* |
| R3 | **`render_a_bar` and `draw_window_number`'s call of it** | ~/kitty-482 `shaders.c:836-887`, `:938-943` | the drawing half of the design, already compiled into the operator's build |
| R4 | **The SIGWINCH-counter harness with its forced-row-change positive control** | `config/kitty.conf:495-506` | the instrument that proves (a); it already has a control that moves |
| R5 | **The `min_windows`-vs-`force_show` no-op-drag measurement** | `config/kitty.conf:509-517` | settles (c)'s second half without re-measuring — and dictates that the band must be layout-driven, not force-show-driven |
| R6 | **The four-spec-form SF Pro refutation** | `config/kitty.conf:526-534` | the measured justification for the whole design; cite it, do not re-run it |
| R7 | **The chord `cmd+shift+left press`, and the reasons `cmd+left` / `ctrl+alt+left` are rejected** | plan Q12 | measured chord space, positive-controlled |
| R8 | **The whole § 2 safety regime** (drop-in arming, disarm-by-emptying, file-before-line, the `env -u` prefix, the socket outside `/tmp/kitty-*`) | plan `:138-268` | non-negotiable on this machine |
| R9 | **The `./autoformat` prohibition and the `clang-format` measurement** (`state.c` 1,972 diff lines, `glfw.c` 3,590 on v0.48.2) | PR § Checks | v0.48.2 predates master's repo-wide format pass; hand-match the local style |
| R10 | **The build-identity command** — `kitty +runpy 'import kitty; print(kitty.__file__)'`, never `--version` | plan Q16, PR § Verification | master also declares `Version(0, 48, 2)` |

### 7.2 REBUILD / re-derive — do NOT inherit

| # | Thing | Why it does not transfer |
|---|---|---|
| X1 | **The `rows 2` ruling** (plan Q7) | derived for the 2-cell PNG overlay (`BAND_FILL_CELLS 1.378`). A `render_a_bar` band is `cell_height + 2` px + borders ≈ **1.13 cells** (§6.4). Re-derive the row count, and re-check it against `window_drag_tolerance 6`. |
| X2 | **"one cell" arithmetic anywhere** | the band is 51 px at a 45 px cell, not 45 |
| X3 | **The padding reservoir** | **CLOSED by the operator, twice** (`kitty.conf:1097-1108`, M7). A band that needs padding is a non-starter. |
| X4 | **The Q5 `on_window_drop` ordering fix for v0.48.2** | the backport deliberately omits it and the PR says the hazard is present; the v0.48.2 rewrite is open work |
| X5 | **Any claim that the overlay/band "can never carry a hand cursor"** | true of a graphics placement, refutable for a `render_a_bar` band **only together with the `mouse_region()` change** — mark in place, and only after it is measured |

### 7.3 STILL OPEN — the irreducible new work

1. **`kitty/mouse.c`: the `mouse_region()` ordering change** (v0.48.2 `:1067-1080`) so the band's
   pixels win over `contains_mouse`, plus the hover shape at `update_mouse_pointer_shape()`
   (`:1127-1144`). **Neither sibling patch opens this file. This is the whole C delta.**
2. **`kitty/shaders.c`: a third `render_a_bar` consumer** drawing `ui->window->title` persistently
   rather than during visual select.
3. **`kitty/options/definition.py`: the new option**, beside `window_title_bar*` at `:1941-2031`,
   and the corresponding branch in `kitty/window.py:1050-1068` that does **not** decrement
   `render_ynum`, plus `kitty/layout/base.py:408-415` where `show_title_bar` is decided.
4. **The v0.48.2 `on_window_drop` ordering fix** (X4).
5. **A hand-driven verification of (c)** — plan § 6 DoD #4/#5. **No agent can sign this off.**

### 7.4 UNMEASURED — stated as such, not reasoned into verdicts

| # | Claim | Status |
|---|---|---|
| U1 | **⌃⇧F7 renders a system-font title band over content with no shift on the operator's installed build** | **UNMEASURED — and the highest-value check available.** Derived from code (§6.4/§6.6); I could not press it, because the only kitty here is his live one. |
| U2 | Whether a `render_a_bar` band's pixels align with text row 0 well enough for `mouse_drag_window rows 1` to select exactly the band | **UNMEASURED** — no such band exists yet (§2.1) |
| U3 | The mid-drag force-show relayout actually shifting content | **UNMEASURED by me** — asserted by the action's docstring and by plan § 7.1 |
| U4 | BUTTONLESS SYSTEM DRAG (no `mouse_button_pressed` test in the motion block) | **UNMEASURED by me** — plan `:198-200` says it was verified in 0.48.2 bytecode |
| U5 | Whether `Window.drag_source.initial_left_press` being left armed ever changes an outcome | **UNKNOWN upstream too** — plan § 7.7 records it as an open unknown; do not close it |
| U6 | Whether the sibling's patches apply cleanly to a fresh checkout today | **UNMEASURED** — I did not `git apply --check` anywhere (it would write to a tree I must not touch). The PR reports both were applied and built. |

### 7.5 The one-line answer to the brief's question

**The sibling's work is a complement, not a competitor: it delivers the DRAG and none of the DRAW,
composes with zero semantic conflict, and shortens the band design by an entire subsystem — while the
hand cursor on hover, which it cannot give, turns out to be the only irreducible C change the whole
design needs.** And the drawing half the lead proposed to build is already compiled into the
operator's installed kitty and reachable with ⌃⇧F7.

---

## ADVERSARIAL VERIFICATION

**Verifier:** adversarial agent, 2026-09-16. **Method:** every cited `file:line` re-opened in the tree
it names; every measurable claim re-measured with a control; the one claim the author marked
UNMEASURED (U1 / claim 2) **measured**, in a sandbox kitty instance of my own
(`/private/tmp/ktb-prior-art/sock`, never the operator's pid 597).

**Headline: the report's citations are unusually clean — I found no misattributed line and no wrong
tree in 14 claims. But its central architectural conclusion is wrong, and it misses the one cost
that bears on the operator's "lowest to zero latency and memory pressure" clause.**

### AV.0 — Sandbox instrument, stated so the numbers below are re-derivable

`/Applications/kitty.app` identity confirmed the way plan Q16 demands, never from `--version`:

```
kitty +runpy 'import kitty, kitty.constants as c; print(kitty.__file__); print(c.str_version)'
  -> /Applications/kitty.app/Contents/Resources/Python/lib/kitty-extensions/python-lib.bypy.frozen/kitty/__init__.pyc
  -> 0.48.2
```

Sandbox: own config (`font_family Monaco`, `font_size 18.0`, `modify_font cell_height 94%`,
`window_padding_width 0 5 0 5`, `enabled_layouts splits`, `window_title_bar_min_windows 0`),
own socket, `--instance-group ktbverify`, 3 panes in one `splits` tab, OS window 2420x1938 device px.
Bands were raised with `kitty @ action focus_visible_window`, not a keypress (see AV.7).
Screenshots via `screencapture -x -o -l<platform_window_id>`; diffs by per-row changed-pixel count.

### AV.1 — U1 / claim 2 is no longer UNMEASURED. It renders, and (a), (b), (d) all hold.

**This discharges recommendation item (2). Nobody needs to run it again.**

| requirement | measurement | verdict |
|---|---|---|
| **band exists, top, non-active panes** | before/after diff: two changed bands of **exactly 51 px** at `y 58..108` and `y 999..1049`, each ~1178 of 1210 sampled columns wide — one per **non-active** pane. The active pane got none. | ✅ as predicted |
| **(a) zero layout shift** | `kitty @ ls` lines before → after: `20/10/10` → `20/10/10`. No relayout, no SIGWINCH. | ✅ |
| **(b) fixed under scroll** | 25 lines of child output into the banded pane: **18** content row-bands changed at exactly **45 px pitch** (y 110..146, 155..191, 200..236 …) while the band region `y 58..108` was **byte-identical**. Positive control built in — the content demonstrably moved. | ✅ |
| **(d) system font, not the cell font** | one variable, same band, two 20-character titles: `I`×20 → text run `x 22..219` = **198 px**; `W`×20 → `x 22..790` = **769 px**. **3.88×** for equal character counts ⇒ proportional. A monospace bar would have returned two identical widths, so the instrument could have come out the other way. | ✅ |

**Corrected claim 2:** *not* "should already paint" — it **does**. On the operator's installed,
unpatched 0.48.2, `focus_visible_window` paints each non-active pane's own title in a proportional
system font, in a 51 px band at the top of the pane, over content, with zero relayout, and the band
does not move when the pane below it scrolls.

### AV.2 — OVERTURNED: the `mouse_region()` ordering change is **not** the irreducible C delta, and doing it would be actively harmful

The report (§3.5, and recommendation item 3) says the ordering change is *"not optional and not
substitutable; it is the irreducible C delta of the whole design."* Both halves are wrong.

**It is substitutable, and upstream already ships the substitute.** The hand on hover does not need
`mouse_region()` to change at all — it needs four lines in the arm that already runs.
`update_mouse_pointer_shape()` (~/kitty-482 `kitty/mouse.c:1128-1145`) reaches
`else if (r.window)` and *there* calls `handle_scrollbar_mouse(r.window, -1, MOVE, 0)`, whose
predicate is `get_scrollbar_hit_type(const Window *w, double mouse_x, double mouse_y)`
(`kitty/mouse.c:499-521`) — **a pixel-rectangle test against a sub-region of the window, inside the
window's own `contains_mouse` rect, yielding a distinct hover cursor.** That is precisely the shape a
title band needs, and it is already in the file. A band test placed ahead of the scrollbar test in
that same arm gives the hand with **no** change to hit-test ordering, no new `MouseRegion` field, and
no new consumers. (`mouse_event()` at `:1354+` needs the same test to hold the shape through a
press-hold.)

**And reordering would destroy the property that motivates the whole action route.** A band that wins
over `contains_mouse` sets `r.in_title_bar`, so `mouse_event()` takes the arm at `kitty/mouse.c:1362`
and calls `handle_window_title_bar_mouse()` (`:930`) → `TabManager.handle_window_title_bar_mouse`
(~/kitty-482 `kitty/tabs.py:1853-1881`). That path **never consults `opts.mousemap`**
(`kitty/window.py:1395-1401` is only reached from the `else if (w)` arm), so:

1. `mouse_drag_window` would never run for the band, and its `return True` pass-through — the
   report's own claim 13 / plan M3, *"the single strongest argument for the band design"* — becomes
   **unreachable in the band**. Every press on the band is consumed unconditionally, which is exactly
   the kitten failure mode the action was chosen to escape.
2. It inherits the double-click rename prompt by construction (`tabs.py:1878-1881`,
   `w.set_window_title()`) — plan § 7 known issue #3, which the plan lists as a defect *"a hand finds
   in seconds"*.

**CORRECTED CLAIM.** The irreducible C delta is **a pixel-region hover test in
`update_mouse_pointer_shape()` (and `mouse_event()`), modelled on `get_scrollbar_hit_type`** —
one arm, one file, no reordering. `mouse_region()` must be left alone: the band must *lose* the hit
test so that presses keep flowing through `mousemap` to `mouse_drag_window`, which is the only thing
that can pass a press below the band through to Claude Code. The design is better than the report
thinks, and smaller.

### AV.3 — NEW, and the largest thing the report missed: a persistent band forces the **layered** render path forever

`draw_window_number` / `draw_hyperlink_target` are called **only** from
`draw_cells_with_layers` (~/kitty-482 `kitty/shaders.c:1381-1382`), and the branch above is
`kitty/shaders.c:1448-1449`:

```c
if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
else draw_cells_without_layers(&ui, srd->vao_idx);
```

`needs_layers` is recomputed each frame at `kitty/child-monitor.c:756-758` as
`!supports_framebuffer_srgb || alpha < 1 || live_resize || background_image`, then OR'd with
`screen_needs_rendering_in_layers(...)` per window (`:770`, `:786`), whose `has_ui` disjunction at
`kitty/shaders.c:1316-1317` **includes `has_window_number(w, screen)`** — i.e. the bar's own trigger
is what turns layers on. When it is on, `start_os_window_rendering` (`kitty/shaders.c:1639-1666`)
allocates/binds a full-viewport render target and renders the whole OS window **into an offscreen
framebuffer**, and `stop_os_window_rendering` (`:1669-1695`) blits it back with `BLIT_PROGRAM`.

The operator's live config sets **no** `background_image` and **no** `background_opacity`
(grep over `config/kitty.conf` returns nothing for either), and his sandbox equivalent reported
`background_opacity 1.0` — so today his panes take the **single-pass** path whenever no image,
scrollbar, progress bar, logo or visual-select bar is up. **A permanently-drawn band flips every
such OS window to the indirect framebuffer + full-screen blit, every frame, forever.**

⚠️ **And the ⌃⇧F7 check cannot see this**, because the visual-select band is transient: it
demonstrates the render while hiding the steady-state cost. A control that does not reach the
regime returns a clean null.

**UNMEASURED, and I say why rather than reporting a null from a blind instrument.** I built a CPU
A/B (band on vs off, fixed output load, `ps -o time` delta) and it returned `delta=0.01s` — void on
two independent counts: the load script died on a quoting error (`SyntaxError: unterminated string
literal`, confirmed via `kitty @ get-text`), and the sandbox OS window was `is_focused false` and
probably occluded, which macOS throttles. **Do not quote my 0.01 s.** The right instrument is a
focused, unoccluded window, a load that is verified to have run, and ideally a build with a frame
counter.

**CORRECTED HEADLINE.** *"The drawing half is already compiled in, so it is free"* is true of the
pixels and false of the pipeline: the drawing half is free **only while it is transient**. Making it
persistent buys the band and sells the single-pass renderer. That trade has to be measured before it
is made, and it is the trade the operator's "zero latency and memory pressure" clause is about.

### AV.4 — NEW: a third `render_a_bar` consumer must not reuse `title_bar_data`

`kitty/shaders.c:929` — the URL-target bar renders into **`&window->title_bar_data`**, using
`url_target_bar_data` only for hyperlink-id/title bookkeeping. So the two existing consumers already
share one pixel buffer. `render_a_bar`'s cache key is
`bar->last_drawn_title_object_id != title || bar->needs_render` (`:851`), so two consumers alternating
on one buffer **re-render through CoreText every frame**. Hovering a hyperlink in a pane carrying a
persistent title band would do exactly that. The new option needs its **own** `WindowBarData` field on
`Window` (~/kitty-482 `kitty/state.h:276`), not a share of `title_bar_data`.

### AV.5 — CORRECTED: the band's geometry, measured, and what it does to `rows N`

A vertical colour-run scan through a banded pane (full-block `█` rows printed underneath, so every
cell is fully inked — the control that makes clipping visible):

```
y  57       AA
y  58.. 59  border stroke (205,205,205)
y  61..105  bar interior, 45 px
y 106..108  border stroke
y 109..147  FIRST VISIBLE CONTENT ROW — 39 px of a 45 px cell
```

* Band = **51 device px** = `cell_height(45) + 2` + `2 × border_width(2)` — `shaders.c:839`, `:871-873`,
  `:887`. Confirms M1/claim 11 empirically (1.133 cells).
* **The band fully occludes content row 0 AND the top 6 px of row 1's cell** — measured: the block row
  rendered 39 px of 45. At Monaco 18/94 % the Latin ink starts ~7 px into the cell so nothing visibly
  clips; **a box-drawing, reverse-video or full-block cell on row 1 is visibly clipped.** For a
  persistent band that is a permanent artefact, not a transient one.
* **U2 is now answerable without a prototype.** `mouse_drag_window rows 1` selects `cell_y == 0`, i.e.
  `y 58..102`. The visible band runs to `y 108`. **There is a 6 px (3 pt) strip at the band's bottom
  that looks grabbable and is not** — the hand (if pixel-tested per AV.2) would show there while the
  drag refuses to arm. Fix by clamping the drawn band to `cell_height` in the new consumer, or by
  pixel-testing both, or by accepting the strip. Do not discover it by hand.
* **M5 misattributes the border.** `render_a_bar`'s border is `ceil(thickness_as_float(os_window, 1))`
  and `thickness_as_float` reads **`OPT(box_drawing_scale)[1]`** (`kitty/shaders.c:305-310`,
  default `0.001, 1, 1.5, 2`), **not** `window_border_width`. Both are 1 pt here so the 2 px number is
  right; the lever is not. Setting `window_border_width 0` would not give a borderless band.

### AV.6 — CORRECTED: §6.6's scroll recipe cannot be done from the keyboard

§6.6 ends *"which is exactly the dwell needed to scroll the pane underneath and settle requirement
(b) in the same keypress."* During visual select, `Boss.visual_window_select_action` calls
`redirect_mouse_handling(True)` (~/kitty-482 `kitty/boss.py:1729`), and `mouse_event` diverts all
motion and button events to Python at `kitty/mouse.c:1273-1281`; every **keypress** is captured by the
pushed `__visual_select__` `KeyboardMode`, whose `on_action='end'` terminates the mode. So keyboard
scrolling exits the modal and mouse press/motion never reaches the pane. Only `scroll_event`
(`kitty/mouse.c:1485`) is **not** gated on `redirect_mouse_handling`, so the wheel/trackpad still
scrolls. I settled (b) by a third route that needs no input at all — 25 lines of **child output** —
which is the recipe to publish.

### AV.7 — CORRECTED: "⌃⇧F7 is one keypress away" is not reliable on a Mac

The binding is real and unshadowed (re-verified: `definition.py:3970-3971`, `kitty_mod` default
`ctrl+shift` at `:3484-3485`; `config/kitty.conf` sets no `kitty_mod`, no `clear_all_shortcuts`, no
`f7` map). But on macOS the F-row emits media keys unless *Use F1, F2 … as standard function keys* is
on, so ⌃⇧F7 may reach kitty as nothing at all. **Dispatch the action instead**, which is what I did
and what works: `kitty @ --to unix:<sandbox sock> action focus_visible_window`, in a sandbox
instance, never the operator's.

### AV.8 — An internal inconsistency with a live blast radius

§2.1 and §3.4/R1 both write the example as **`mouse_map cmd+left press grabbed,ungrabbed
mouse_drag_window 1`**. That is the chord plan Q12 rejects, and the report's own recommendation (4)
rejects, because it silently kills `mouse_map cmd+left click grabbed,ungrabbed mouse_handle_click
link` — re-verified live at **`config/kitty.conf:821`**. Under § 2 safety rule S4 a config drop-in is
live ~100 ms after converge, so a copy-paste from the body of this document breaks the operator's own
link-click gesture. **Every example in the document must read `cmd+shift+left press`.**

### AV.9 — Upheld verbatim, re-measured by me, no correction needed

* **Claim 1 / 6** — `draw_window_number` → `render_a_bar(ui, &ui->window->title_bar_data,
  ui->window->title, false)` at `shaders.c:943` (function `:939`, guard `has_window_number` `:934`,
  `render_a_bar` `:837-888`, `along_bottom` reposition `:873`). Exact.
* **Claim 4 mechanism** — `mouse_region()` `:988`, the loop `:1067-1080` with `contains_mouse` first
  and `break`; `update_mouse_pointer_shape` `:1128-1145` reaching the hand only via `in_tab_bar` /
  `in_title_bar`; the armed-drag bypass at `:1362`. Exact. (Its *conclusion* is what AV.2 overturns.)
* **Claim 5** — `grep -E '^diff --git'` on both patches reproduces the file lists exactly; neither
  opens `shaders.c`, `mouse.c` or `options/definition.py`. `state.h` collision ruled out by struct
  (`OSWindow` vs `Window`, `state.h:276`). Exact.
* **Claim 7** — census re-run in both trees: **245** (v0.48.2) vs **251** (master `1d67ecd47`);
  `comm -13` returns exactly the six named; `comm -23` empty. Exact.
* **Claim 8** — the wedge grep and its positive control reproduce line-for-line
  (`mouse.c:933/1362/1365/1366`, `state.c:1762/1764/1771`, `state.h:534`; control
  `mouse.c:951`). Exact.
* **Claim 9** — `layout/base.py:412` `show_title_bar = force_show or (min_windows > 0 and
  len(visible_groups) >= min_windows)`; the no-op-drag measurement is at `config/kitty.conf:505-517`.
  Exact.
* **Claims 10 / 14** — the four-spec SF Pro refutation and the padding-reservoir removal are at
  `config/kitty.conf:519-533` and `:1097-1109` (live value `window_padding_width 0 5 0 5` at `:1109`).
  Exact (the report's `:526-534` / `:521-535` differ by a few lines; non-load-bearing).
* **Claim 12** — the backport header names the Q5 `tabs.py` omission verbatim. Exact.
* **Claim 13** — `Boss.kitten` (`boss.py:2404-2406`) calls `run_kitten_with_metadata` and returns
  `None`; `Window.on_mouse_event` (`window.py:1395-1401`) returns `boss.combine(...)`, so a kitten
  can never return the pass-through. Exact.
* **Claim 3** — the `rows` docstring including *"intended for programs that draw their own header at
  the top of the window"* is verbatim in the master patch. Exact.

### AV.10 — Residue I am leaving behind, named rather than hidden

A **windowless** sandbox kitty (`pid 12236`, socket `/private/tmp/ktb-prior-art/sock`, instance-group
`ktbverify`) is still resident: all three of its windows were closed (`kitty @ ls` → `[]`) but the
macOS app does not exit on last-window-close, and my brief forbids `kill`. It holds no windows and
~0.5 s of total CPU. Its socket does **not** match `/tmp/kitty-*`, so repo tooling is unaffected.
⌘Q on it, or leave it. Screenshots and diffs are in `/private/tmp/ktb-prior-art/`
(`before.png`, `after.png`, `after_scroll2.png`, `blocks.png`) — `/private/tmp` does not survive a
reboot, so re-derive from AV.0 rather than citing those files.
