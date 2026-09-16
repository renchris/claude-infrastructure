# Beginning a kitty window drag from a front-end-drawn region — implementation research

**Date:** 2026-09-16. **Phase 1 of 3** (research → plan → implement). This file is the whole of
phase 1's output: twelve research axes plus 32 adversarial verdicts, synthesised. A fresh session
with none of that context should be able to plan the implementation from this file alone.

**Refs measured throughout.** kitty **master `1d67ecd47c0bd68951868c363baa92039d936572`** (2026-09-16,
shallow depth 1 — no blame or bisect available) and kitty **v0.48.2
`2cb1d95c3accadd536bd66ba6bda044973440177`** (`git describe` → `v0.48.2`), both at
`scratchpad/kitty-src/`. Plus the **installed frozen build** `/Applications/kitty.app/Contents/MacOS/kitty`,
which self-reports `0.48.2` and is the binary the operator's live instance (pid 97084) runs. Our repo
is `/private/tmp/wt-kitty-overlay` @ `feat/kitty-title-overlay`, HEAD `a49280bd9`.

🚨 **Read the version tag on every citation.** The two refs are byte-identical on the load-bearing
routing path and differ materially in five other places. A line number quoted without its ref will
land a reader in a different function — this happened repeatedly during phase 1 and cost real time.

---

## 1. THE VERDICT

**The capability is reachable today on stock kitty 0.48.2 with config only, and was driven end to
end on the shipped binary** — `set_window_being_dragged` is exported to Python, `mouse.c` routes
every subsequent motion and release to the title-bar drag handler on that flag alone regardless of
where the pointer is, a `mouse_map` can dispatch the `kitten` action, a custom kitten whose
`handle_result` carries `no_ui = True` runs synchronously inside the kitty process holding the
`Boss` object, and on macOS `_glfwPlatformStartDrag` fabricates an `NSEvent` when none is live, so
no real press is even required. The honest verdict is therefore **the patch buys correctness and
cost, not capability** — and the skeptics narrowed even that: the drag *threshold*, which the first
pass called unreachable config-only, was **reproduced on the shipped binary** by a ten-line wrapper
(3 px no trip, 4 px no trip, 9 px trips, against `drag_threshold 5`), so what the patch actually
buys is the press-instant origin, the absence of a per-press file-read + `compile()` + `exec()`, a
supported binding instead of a monkeypatch of two private methods whose spelling already drifted
between the refs, and the ability for an out-of-region press to *pass through* to the program.
**Phase 3 therefore has two deliverables, not one: (A) a config-only prototype buildable today, and
(B) an upstream patch adding one bindable action.** A's single biggest risk is the **wedge**: there
is no C-side clear of `window_being_dragged` anywhere in either tree (positive-controlled grep), the
only mouse-driven clear is a LEFT release through that same routing arm, and a flag left set routes
every mouse event in every OS window to the title-bar handler permanently — after which a bare
pointer move past `drag_threshold` starts a real system drag with no button held. B's single biggest
risk is that it must **write down an invariant kitty never had to**: today `window_being_dragged` is
set at exactly one site reachable only from the title-bar arm, while the three competing drag states
are set only on paths a title-bar press cannot reach, so their mutual exclusion is emergent from the
router — a content-area press runs inside the arm that sets them and breaks it.

---

## 2. THE MECHANISM

This is the section to write code from. Every `file:line` below was read in the named ref.

### 2.1 How a `mouse_map` press reaches an action

```
AppKit -mouseDown:                     master glfw/cocoa_window.m:1036-1039   v0.48.2 :1022-1027
  → _glfwInputMouseClick               master glfw/input.c:320-329            (no queue)
  → mouse_button_callback              master kitty/glfw.c:659-689            v0.48.2 :570-594
        sets osw->mouse_button_pressed[button] = true  (master :681 / v:588)
        THEN calls mouse_event(button, mods, action)   (master :686 / v:590)
  → mouse_event()                      master kitty/mouse.c:1317              v0.48.2 :1264
```

`mouse_event()` is one gate chain followed by one if/else-if arm chain. Order matters, and four
gates precede every arm:

| # | master | v0.48.2 | gate / arm | consumes |
|---|---|---|---|---|
| 1 | mouse.c:1330 | :1273 | `global_state.redirect_mouse_handling` | **unconditional `return`** |
| 2 | mouse.c:1347 | :1283 | `global_state.active_drag_in_window` | motion + its own button's release |
| 3 | mouse.c:1371 | :1308 | `global_state.tracked_drag_in_window` | motion + LEFT release under SGR tracking |
| 4 | mouse.c:1405 | :1341 | `global_state.active_drag_resize` | **unconditional `return`** at master:1416 / v:1352 |
| 5 | mouse.c:1418 | :1354 | `MouseRegion r = mouse_region(true, true);` | — |
| 6 | mouse.c:1423 | :1358 | `r.in_tab_bar \|\| global_state.tab_being_dragged.id` → `handle_tab_bar_mouse` | yes, **anywhere on screen** while a tab drag is live |
| **7** | **mouse.c:1427** | **:1362** | **`(r.in_title_bar && r.window) \|\| global_state.window_being_dragged.id` → `handle_window_title_bar_mouse`** | **yes** |
| 8 | mouse.c:1433 | :1370 | `r.window_border` → `drag_resize_start` | — |
| 9 | mouse.c:1463 | :1389 | `else if (w)` → `handle_event` | **the ONLY route to the mousemap** |
| 10 | — | :1392-1400 | **v0.48.2 ONLY** — LEFT press over no window, clamped into `closest_window_for_event` and dispatched | yes |

Arms 6–10 are one `if / else if` chain, so **arm 7 and arm 9 are mutually exclusive.** That single
fact generates most of the hazards in § 3.5.

Inside arm 9:

```
handle_event                           master mouse.c:948-958
  → handle_button_event                master mouse.c:900-937                 v0.48.2 :864-905
        clear_potential_drag(...)      master :907
        if (handle_scrollbar_mouse(…)) return;   master :909    v0.48.2 :873   ← earlier return
        (focus switch to the pressed window)     master :911 region            v0.48.2 :875-877
        if (!set_mouse_position(w,&a,&b)) return;   master :917   v0.48.2 :883  ← the padding swallow
        [CORRECTED 2026-09-16 by §10.4: this line read "v0.48.2 ONLY" and carried v0.48.2's
         :875-877 under a master label. set_mouse_position has the identical early return in
         BOTH refs — verified by grep at master mouse.c:917 and v0.48.2 mouse.c:883.]
        arm_potential_drag(w, button)  master :918  (LEFT only, master :893-899)
        if (!dispatch_mouse_event(w, button, …, screen->modes.mouse_tracking_mode != 0))  master :921 / v:894
  → dispatch_mouse_event               master mouse.c:206-229                 v0.48.2 :212-226
        PyObject_CallMethod(…, "on_mouse_event", "{si si si sO}",
            "button", "repeat_count", "mods", "grabbed")        ← NO COORDINATES
  → Window.on_mouse_event              master kitty/window.py:1413-1420       v0.48.2 :1395-1402
        action = get_options().mousemap.get(ev)
        return get_boss().combine(action, window_for_dispatch=self, dispatch_type='MouseEvent')
  → Boss.combine                       master kitty/boss.py:2087              v0.48.2 :1908
        resolve_aliases(defn, 'mouse_map')   master :2091 / v:1912
  → Boss.dispatch_action               master kitty/boss.py:2032-2066         v0.48.2 :1851-1889
        f = getattr(self, key_action.func, None)                    ← BOSS FIRST, bare getattr
        …  f = getattr(tab, key_action.func, getattr(window, key_action.func, None))
```

Four properties of that chain an implementer must hold:

- **The `MouseEvent` key carries no position.** `('button','mods','repeat_count','grabbed')`, verified
  on the shipped binary and byte-identical in `kitty/types.py:115-119` (v0.48.2) / `:121-125` (master).
  A mapped action learns where the press was only by asking afterwards.
- **`grabbed` is part of the lookup KEY**, computed in C from `screen->modes.mouse_tracking_mode != 0`
  (master mouse.c:921 / v:894), and `parse_mouse_map` emits one `MouseMapping` per declared mode
  (master `kitty/options/utils.py:1634-1639` / v:1556-1561). An `ungrabbed`-only map is invisible in
  a pane whose program has mouse tracking on — measured one-variable (V27): with `ungrabbed` only the
  kitten ran once; after changing only that field to `ungrabbed,grabbed` it ran twice.
- **The return value decides whether the child also sees the press.** `passthrough is not True` ⇒
  consumed (master boss.py:2047-2048, :2059-2062); that bool reaches C at master mouse.c:224
  (`handled = callback_ret == Py_True`). Returning `None` consumes; returning literal `True` passes
  through. Define the action on **exactly one** of Boss/Tab/Window, because a `True` return from the
  Boss arm falls through and calls the Window arm **a second time**.
- **`press` is synchronous; `click`/`doubleclick` are not.** `dispatch_possible_click` (master
  mouse.c:842-861) arms a main-loop timer at `OPT(click_interval)` and
  `send_pending_click_to_window` (master :808-838) dispatches later. Trigger-count map at
  `kitty/options/utils.py:60`: `{'doubleclick': -3, 'click': -2, 'release': -1, 'press': 1}`. **A drag
  must arm on `press`.**

### 2.2 How a window drag arms, runs and drops

**The state.** One global struct, one Python setter/getter pair:

```c
/* master kitty/state.h:657-661   ·   v0.48.2 kitty/state.h:531-534 */
struct { id_type id; bool drag_started; double x, y; } window_being_dragged;

/* master kitty/state.c:1996-2008  ·  v0.48.2 kitty/state.c:1762-1774 */
#define wbd global_state.window_being_dragged
set_window_being_dragged(...) { zero_at_ptr(&wbd); PyArg_ParseTuple(args, "|Kpdd", &wbd.id, &wbd.drag_started, &wbd.x, &wbd.y); }
get_window_being_dragged(...) { return Py_BuildValue("KOdd", wbd.id, wbd.drag_started ? Py_True : Py_False, wbd.x, wbd.y); }
```

All four setter args are optional: a bare `set_window_being_dragged()` is the documented **clear**,
and a partial call (two args) **zeroes x and y as a side effect**. `K` is the kitty **window** id,
not an OS-window id. There is a single `id`, so exactly one window drag can be armed process-wide.
Measured on the shipped binary: `set(12345, False, 10.0, 20.0)` reads back verbatim; `set(999, True)`
reads back `(999, True, 0.0, 0.0)`; a 5-argument call raises `TypeError: function takes at most 4
arguments`; a string id raises `TypeError` with the state unchanged.

**The five stages, and their version deltas:**

| stage | master | v0.48.2 | notes |
|---|---|---|---|
| 1. arm (PRESS) | tabs.py:2021-2027 | tabs.py:1868-1874 | `set_active_window(...)`, then `if threshold: set_window_being_dragged(window_id, False, x, y)` |
| 2. route | mouse.c:1427 + 961-967 | mouse.c:1362 + 930-938 | **byte-identical modulo whitespace** — verified by direct read |
| 3. promote (MOTION) | tabs.py:2008-2017 | tabs.py:1855-1864 | `dist_sq > threshold²` → `set_window_being_dragged(id, True, start_x, start_y)` + thumbnail |
| 4. thumbnail | `boss.request_thumbnail(...)` boss.py:1560-1590, C callback string `'thumbnail_ready'` boss.py:1589 | `request_callback_with_thumbnail("start_window_drag", os_window_id, window_id)` tabs.py:1862 | **THE ONE REAL DELTA.** `Boss.request_thumbnail` / `Boss.thumbnail_ready` are master-only and measured ABSENT from the shipped 0.48.2 build |
| 5. start | tabs.py:2036-2062 → glfw.c:3684 | tabs.py:1883-1910 → glfw.c:3214 | force-show bars, draw the title strip, compose the MIME payload, `start_drag_with_data` |

The C wrapper that carries stage 2 into Python, verbatim (master mouse.c:961-967; v0.48.2 :930-938
differs only by a line wrap):

```c
handle_window_title_bar_mouse(Window *w, int button, int modifiers, int action) {
    OSWindow *osw = global_state.callback_os_window;
    if (!osw) return;
    if (button > -1 || global_state.window_being_dragged.id) {
        call_boss(handle_window_title_bar_mouse, "KKddiii", osw->id, w->id, osw->mouse_x, osw->mouse_y, button, modifiers, action);
    }
}
```

**Motion (`button == -1`) is forwarded only because the flag is set** — motion over an idle title bar
is deliberately dropped. `tw` is the window **under the pointer**, not the dragged one; Python ignores
that argument on the motion path and reads the id from the global instead, which is why the current
code works across windows.

The thumbnail hop lands via `state.c:1777-1795` (v0.48.2) storing the callback, then
`child-monitor.c:923-925` firing it inside `draw_os_window()` immediately before
`swap_window_buffers`, then `Boss.start_window_drag` (v boss.py:1435) →
`TabManager.start_window_drag` (v tabs.py:1883) → `start_drag_with_data` (v tabs.py:1906).

**The drop side reads only the window id and the live pointer.** Payload is
`{f'application/net.kovidgoyal.kitty-window-{os.getpid()}': str(window_id).encode()}` (master
tabs.py:2057 / v:1904); `Boss.on_drop` reads exactly that key (master boss.py:2212-2218 / v:1991-1997)
and calls `tm.on_window_drop(x, y, window_id)`. Detach-on-drop-outside is `Boss.on_drag_source_finished`
(master boss.py:2260-2284 / v:2027-2045), gated on `was_dropped`, which is **masked in C** to mean
*dropped and not onto one of our own OS windows* (master glfw.c:1093-1094, identical at v:958).

**Every clear of the flag** (exhaustive; both refs have the same six):

| site (master / v0.48.2) | trigger |
|---|---|
| tabs.py:2030 / :1877 | LEFT release through arm 7 — **the only mouse-driven one** |
| tabs.py:2040 / :1887 | `start_window_drag`: the dragged window vanished |
| tabs.py:2062 / :1909 | `start_window_drag`: `start_drag_with_data` raised `OSError` |
| tabs.py:2206 / :2039 | `on_window_drop` |
| boss.py:2216 / :1996 | `on_drop` carrying the window MIME key |
| boss.py:2273 / :2038 | `on_drag_source_finished` |

🚨 **There is NO C-side clear, in either tree.** Positive-controlled grep (V2): the tab equivalent
`zero_at_ptr(&global_state.tab_being_dragged)` exists at master mouse.c:981 / v:951, so the
instrument works; the same grep for `window_being_dragged` returns nothing. Nor does window or tab
teardown clear it (V5) — so if the dragged window closes while the flag is set **and** the pointer is
over no window, arm 7 resolves `tw == NULL` (master :1429-1431) and calls nothing at all. That is the
one genuinely unrecoverable state.

### 2.3 The precise reason a drag armed from anywhere still routes correctly

Four independent facts, each re-verified:

1. **Arm 7's condition is a DISJUNCTION with no title-bar term in the second operand.** Read directly
   in both trees this session:
   `} else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {`
   — master mouse.c:1427, v0.48.2 mouse.c:1362, byte-identical.
2. **Nothing in either tree gates on bar visibility.** `window_title_render_data` is read in `mouse.c`
   at **exactly one line** — master:1115 / v:1072, inside `mouse_region`'s hit test. Every other read
   in either tree is a rendering path in `child-monitor.c` or a test fixture in `dnd.c`. Neither the
   drag state machine nor the routing touches it (V7). *(This narrows, and corrects, our own
   `config/kitty.conf:541-511` claim that the drag machinery "hangs off real title-bar render data".
   Only the HIT TEST needs a real bar.)*
3. **A pointer over no window still resolves.** `window_for_window_id` (master state.c:174-185 /
   v:155-166) scans every OS window × tab × window, so the drag survives the pointer leaving the
   originating OS window.
4. **No reader anywhere tests whether the press was inside a title bar.** Exhaustive census: C reads
   only `.id` (master mouse.c:964, 1427, 1430; v:933, 1362, 1365-1366); Python reads `.x/.y` at
   exactly ONE site per version (master tabs.py:2009 → used at :2012; v:1856 → :1859), under the gate
   `if dragged_window_id and not drag_started:`; every other Python reader takes `[0]`, `[1]` or
   `[:2]`. `_pointer_in_title_bar_of` (master tabs.py:2102) looks like a counter-example and is not —
   it is a **drop-TARGET** test, used at :2182 and :2234 against the destination window and the live
   pointer.

**On this box the first disjunct is structurally dead**, which strengthens the approach rather than
weakening it: `window_title_bar_min_windows 0` (config/kitty.conf:1245) leaves the bar render
geometry empty, and mouse.c:1114-1119 requires `trd->geometry.right > trd->geometry.left &&
trd->geometry.bottom > trd->geometry.top` to set `in_title_bar`. The second disjunct is the only live
route here (V2).

🚨 **The invariant this breaks, stated because nobody upstream wrote it down.** `window_being_dragged`
is today set at exactly one site (master tabs.py:2026), reachable only through arm 7. The three
competing drag states are set only on paths a title-bar press cannot reach:

| state | written at | reachable only from |
|---|---|---|
| `active_drag_in_window` | master mouse.c:1237 (`mouse_selection`), :639/:644 (scrollbar) | arm 9 |
| `tracked_drag_in_window` | master mouse.c:134 (`encode_mouse_button`, LEFT PRESS) | arm 9, and only when `dispatch_mouse_event` returned FALSE |
| `active_drag_resize` | master mouse.c:1461 | arm 8 |

So "at most one drag state is live" is an **emergent property of the router**, never asserted. A
`mouse_map` action that sets `window_being_dragged` from a content-area press runs inside arm 9 and
therefore breaks it. `active_drag_resize` is the one that cannot coexist — its only writer sits in
the `else if (r.window_border)` branch, mutually exclusive with the content branch, and while it is
set the gate returns unconditionally for every event, so the arming press could never be delivered.

### 2.4 Where the two refs actually differ on this path

**Identical (whitespace/clang-format only):** arm 7 and the whole gate/arm chain, the C wrapper,
`mouse_region`'s title-bar hit test, `handle_tab_bar_mouse`, the struct and its accessors,
`Boss.combine`, `Boss.dispatch_action`, `parse_key_action`, `parse_mouse_map`, `Window.on_mouse_event`,
`show_error`, and `TabManager.{handle_window_title_bar_mouse,start_window_drag}` (the last differing
by exactly one line — hex case `0xff`→`0xFF` aside).

**Real differences that touch this work:**

1. **Thumbnail plumbing.** master queues through `Boss.request_thumbnail` (boss.py:1560-1590, whose
   own comment says `request_callback_with_thumbnail()` supports one in-flight request so all are
   serialised); 0.48.2 calls the C function directly. On master the async window is unbounded and can
   sit behind an RC screenshot request; on 0.48.2 it is one render tick. A patch written against
   master's spelling `AttributeError`s if backported verbatim.
2. **Padding.** master added `clamp_to_window = button > -1 && contains_mouse(w);` (mouse.c:1473), so
   a press in a window's padding maps to the nearest cell. 0.48.2 discards it at mouse.c:883. **But
   the same hunk deleted `closest_window_for_event`** (v mouse.c:1099, :1394), so master loses the
   0.48.2 path that dispatches a LEFT press landing in the **margin**. Master is not a superset;
   master's own changelog says so (master docs/changelog.rst:265-270, under `0.49.0 [future]` at :202).
3. **Refactor-only, but it decides what a patch may call.** `_pointer_in_title_bar_of`,
   `_drop_direction_for`, `set_drag_over_me`, `attach_window_at_edge`, `attach_windows(next_to=…)`,
   `WindowBeingDropped.direction` and `Boss.{request_thumbnail,thumbnail_ready,_update_drag_over,
   _reset_drop_previews,_tab_merge_target}` are **master-only** — all verified absent from the shipped
   0.48.2 build with 13 positive and 2 negative controls (V11).
4. **`handle_potential_drag`.** master factored it out (mouse.c:667) and added the
   `OPT(drag_threshold) <= 0` guard (:668) and `clear_click_queue(w, button)` (:676). 0.48.2 has
   neither, so on 0.48.2 **any movement > 0 px starts a child/URL drag** even at `drag_threshold 0`.
5. **A 0.48.2-only coordinate defect in the drop classifier** — see § 5.9.

---

## 3. DELIVERABLE A — THE CONFIG-ONLY ROUTE

Buildable today on the shipped 0.48.2 binary, no patch, no build. It was driven end to end during
phase 1: an in-process kitten moved the drag state `[0, false, 0.0, 0.0] → [2, true, 0.0, 0.0]`,
requested the thumbnail callback with **no traceback on stderr**, and the state was subsequently
cleared — the signature of a drag lifecycle that ran to completion. *(Honest bound: nobody watched a
pane move. See § 8 Q9.)*

### 3.1 What the kitten is

A custom `.py` kitten in `kitty.constants.config_dir` whose `handle_result` carries `no_ui = True`:

```python
# kitty/boss.py:2325-2326 (v0.48.2)  ==  master kitty/boss.py:2584-2585, verbatim
if end_kitten.no_ui:
    return end_kitten.handle_result(None, w.id if w else 0, self)
```

`self` is the **`Boss`**. `no_ui` is read at `kittens/runner.py:97` (v0.48.2) / `:98` (master). No
subprocess, no overlay window, no round trip — measured in-process (same pid), synchronous
(timestamps 0.27 ms apart), and honouring `window_for_dispatch`: dispatching on window 1 while window
2 was active delivered `target_window_id: 1`, which is exactly what a drag-the-window-under-the-pointer
handler needs (V27). `no_ui` is documented public API (`docs/kittens/custom.rst:178`, decorator at
`kittens/tui/handler.py:340-348`).

⚠️ **The file MUST still define `main()`.** `import_kitten_main_module` does a bare `g['main']`
subscript (`kittens/runner.py:65`) **before** the `no_ui` check, so a handler-only file raises
`KeyError` at press time and opens an error overlay — measured (V27): `nomain_made_overlay: 1`, the
handler never ran.

### 3.2 The `mouse_map` line

```
mouse_map cmd+left press grabbed,ungrabbed kitten kitty-drag-window.py
```

- **`grabbed,ungrabbed`, not `ungrabbed`** — measured one-variable (§ 2.1). Every pane on this box
  runs a TUI that turns mouse tracking on.
- **`press`, not `click`** — a `click` is synthesised only on release, by which time the drag is over.
- **`cmd+left press` is FREE in both modes** on this box, probed against the *loaded* mousemap with
  two positive controls reading TAKEN (§ 7.3).
- 🚨 **Do not use `ctrl+alt+left press`** — the chord in the existing upstream draft
  (`docs/research/kitty-upstream-drag-action-2026-09-16.md:89`). It is kitty's shipped
  `mouse_selection rectangle` default, `kitty/options/definition.py:1285` (v0.48.2) / `:1320` (master).
- **A relative kitten path resolves against `kitty.constants.config_dir`** (`kitty/utils.py:646-651`),
  **not** against `--config`'s directory (V27).
- The line stores as an **unparsed string**; no validation happens at config-parse time (§ 5.7).

### 3.3 What the kitten does, in order

1. **Take the target window from the dispatch.** The `no_ui` handler receives the window id as its
   **THIRD** argument, and it is the pointer's window. The file-level signature an author must write
   is `handle_result(args, answer, target_window_id, boss)` (master `docs/kittens/custom.rst:32`
   and `:61`) — `kittens/runner.py:96` binds the arg list first via
   `partial(handle_result, [kitten] + orig_args)`, so the id lands third, not second.
   [CORRECTED 2026-09-16 by §10.5's sibling finding: this step read "second argument". Writing
    the signature that way gives the wrong arity, which surfaces as a popup on every press with
    no stack trace.]
2. **Optionally gate on the band.** `boss.window_id_map[wid].current_mouse_position()` →
   `get_mouse_data_for_window` → `{cell_x, cell_y, in_left_half_of_cell}` — **cell resolution only**,
   and it returns **`None`** on a window-lookup miss (master state.c:1979 / v:1745 `Py_RETURN_NONE`).
   A naive `['cell_y'] < rows` therefore raises `TypeError`, which `Boss.combine` renders as a
   "Key action failed" popup on **every press** (V28). Guard the `None`.
3. **Refuse to arm when `get_options().drag_threshold == 0`.** At 0 the promotion test
   (`if threshold and dist_sq > …`, master tabs.py:2013 / v:1860) can never pass, so the flag is set
   and only a LEFT release can ever clear it. Measured on the shipped build: armed at threshold 0,
   a huge motion produced no thumbnail call.
4. **Arm.** Two spellings, and they are genuinely different designs — pick one deliberately:

   **(i) THRESHOLD-PRESERVING** (V25, measured on the shipped 0.48.2). Install a wrapper on
   `boss.handle_window_title_bar_mouse` — a plain instance attribute on a class with no `__slots__`,
   which `PyObject_CallMethod` re-resolves by `PyObject_GetAttr` on **every** event — capture the
   first delivered `(x, y)` pixel pair as the origin, and call
   `set_window_being_dragged(wid, False, x, y)` from inside the wrapper. Measured, with the naive
   route as the failing control arm in the same run:

   ```
   ARM A (sentinel start 0,0 — the naive route):  first motion at (600,400) → [1, true, 0,0]  tripped on first motion
   ARM B (wrapper captures the delivered pixels): capture (600,400) → [1,false,600,400]  trips 0
                                                  move 3px            → trips 0
                                                  move 4px            → trips 0
                                                  move 9px            → [1, TRUE, 600, 400]  trips 1
   ```
   kitty stderr for the whole run: empty. **Residual, small and real:** the captured origin is the
   pointer at the FIRST MOTION EVENT after the press, not at the press, because our band is not in
   kitty's hit test so the press itself is never routed to the title-bar handler — roughly one motion
   sample at gesture onset, where hand velocity is near zero.

   **(ii) THRESHOLD-FREE** (A11 F7, measured). `set_window_being_dragged(wid, True, 0, 0)` then
   `request_callback_with_thumbnail("start_window_drag", os_window_id, wid)` — the same call kitty
   itself makes at v tabs.py:1862 once the threshold is crossed. Because nothing ever reads `.x/.y`
   once `drag_started` is True (§ 2.3 fact 4), the coordinates become dead state and the coordinate
   space becomes irrelevant. The drag begins on the press with no dead zone, which for a deliberate
   chord is arguably the wanted semantics.

   ⚠️ **Spelling is ref-dependent.** `Boss.request_thumbnail` is master-only and measured absent from
   the shipped 0.48.2 build (`hasattr` → False, with controls). `request_callback_with_thumbnail` is
   present in both — but its signature is not identical (0.48.2 takes 6 args, `"sK|KpdI"`,
   state.c:1781; master takes 7, `"sK|KpdIp"`, adding `no_scaling`, state.c:2017).

### 3.4 What route A cannot do

| | why |
|---|---|
| **The hand cursor** | `update_pointer_shape(os_window_id)` takes only an OS-window id and merely re-runs kitty's own `update_mouse_pointer_shape()`; it accepts no shape argument (v state.c:1622-1632, `fast_data_types.pyi:1546`). There is no per-region pointer-shape API anywhere. This was attacked directly and held. |
| **A press-instant origin** | No Python **pull** accessor for the OS-window pixel mouse position exists in either ref — confirmed beyond `state.c` by a whole-C-tree grep (89 `Py_BuildValue` sites in v0.48.2, zero mentioning `mouse_x`/`mouse_y`/`global_x`/`global_y`) and by a 677-symbol dump of the shipped binary with a fabricated-name negative control. |
| **Decline a press** | 🚨 `Boss.kitten` (v boss.py:2406 / master :2671) **does not return** `run_kitten_with_metadata`'s value, so `dispatch_action`'s `passthrough` is always `None` and the press is **always consumed** — measured, a handler returning `True` still gave `dispatch_action -> true` (V27). A config-only handler that decides "this press was not in our band" **cannot** pass it through to the program. This is a hard limit of route A, and it is precisely what the patch's `return True` passthrough buys. |
| **Clear the click queue** | `clear_click_queue` is C-only (master mouse.c:660) and not exported, so route A cannot apply the cure kitty itself documents for the swallowed-release hazard (§ 3.5 #5). |
| **Guard against the competing drag states** | There is **no Python getter** for `active_drag_in_window` / `tracked_drag_in_window` / `active_drag_resize` — measured absent from the shipped build with positive controls (V5). Route A cannot check them. |
| **Avoid the per-press compile** | `kittens/runner.py:53-66` does `open()` + `read()` + `compile()` + `exec()` on **every** invocation; there is no cache and no `importlib` memo. **Measured: 0.1945 ms per invocation over 50 invocations** (V27) — negligible in itself, but on the gesture path, and a cost the patch does not pay. |

### 3.5 Every known failure mode of route A

1. 🚨 **THE WEDGE.** `if button != GLFW_MOUSE_BUTTON_LEFT: return` (v tabs.py:1866-1867 / master
   :2019-2020) sits **above** the only mouse-driven clear (v :1877 / master :2030). Measured on the
   shipped binary, positive control first: a **LEFT** release cleared `(99,False,10,20) → (0,False,0,0)`;
   **MIDDLE** and **RIGHT** releases left it untouched. After that, arm 7 routes every mouse event in
   every OS window to the title-bar handler — killing selection, URL detection, border resize and
   click dispatch — until some LEFT press/release lands. **Bind LEFT.**
2. 🚨 **BUTTONLESS SYSTEM DRAG.** Once wedged, the next bare pointer move past `drag_threshold`
   satisfies the motion path and starts a **real system DND with nothing held**. Verified in the
   shipped 0.48.2 bytecode: the motion block contains no `currently_pressed_button` /
   `mouse_button_pressed` reference at all. Measured: `after 2px → no thumbnail; after 500px →
   (99, True, …), thumbnail_calls = 1`. This is the actual damage, and it is worse than the
   "permanently stuck" framing — `end_drag` zeroes `active_drag_in_window` as part of the release it
   steals, so arm 7 is reachable again on the very next event (V5).
3. **Gate 2 steals the release.** `active_drag_in_window` (master mouse.c:1347/1361 / v:1283/1298)
   precedes arm 7; its release arm calls `end_drag` + `dispatch_possible_click` and returns. Reachable
   two ways: a `combine` that also runs `mouse_selection` (which sets the flag **unconditionally**,
   before it even looks at the selection type — master mouse.c:1235-1239), or a second-button press
   during an in-flight selection or scrollbar drag. `tracked_drag_in_window` is near-unreachable for a
   press that fires an action, because its only writer runs **only when `dispatch_mouse_event`
   returned false**. `active_drag_resize` cannot coexist at all (§ 2.3).
4. **The unrecoverable state.** Dragged window closes while the flag is set **and** the pointer is
   over no window ⇒ `tw == NULL` ⇒ nothing is called, ever (§ 2.2).
5. **Swallowed-release residue.** `add_press` ran (master mouse.c:936) but `dispatch_possible_click`
   (:935) never does, so **the next plain click reads as a double click and selects a word**. kitty
   names this hazard and its cure in its own comment at master mouse.c:672-675
   (`clear_click_queue(w, button)`) — for the native-drag case. Route A cannot apply it (§ 3.4).
6. **A double chord-press under threshold pops the rename prompt** — v tabs.py:1878-1881 / master
   :2031-2034 reach `w.set_window_title()`. Our band does not do this today and nobody asked for it.
7. **`cmd+left click → mouse_handle_click link` dies silently** if `cmd+left press` is the chord
   (config/kitty.conf:821): arm 7 swallows the release, so the `click` is never synthesised.
8. **The border-tolerance dead band** — see § 7.4. A press in the top 12 device px of a pane never
   reaches any mousemap.
9. **The force-show cost lands here too.** Route A reaches the same `TabManager.start_window_drag`
   and inherits the row theft and SIGWINCH storm (§ 5.15).
10. **Two uncaught-exception paths leave bars forced up fleet-wide.** `draw_single_line_of_text` can
    raise `KeyError` / `RuntimeError` and `len(title_pixels) // (width*4)` can raise
    `ZeroDivisionError` at `width == 0` — none is an `OSError`, so `except OSError` (master
    tabs.py:2060) does not catch them, and `force_show_title_bars` stays True on every tab with only
    a traceback in the log. On **master** additionally, `child-monitor.c:980`'s `if (!w) return;`
    leaves `thumbnail_request_queue[0]` unpopped with **no timeout**, wedging every future window
    drag, tab drag and `kitten screenshot` for the life of the process (A3 F9).
11. **kitty's GLFW mods are NOT stock GLFW:** SHIFT 0x1, ALT 0x2, CONTROL 0x4, SUPER 0x8
    (`glfw/glfw3.h:487,492,497,502`; confirmed at runtime). Never hardcode a mod integer.
12. **Ref drift.** Route (i) monkeypatches a private method; route (ii) calls a thumbnail API whose
    spelling and arity both changed between 0.48.2 and master. Upstream can break either silently.

---

## 4. DELIVERABLE B — THE UPSTREAM PATCH

The maintainer **pre-blessed this exact feature** (PR 9450, 2026-03-05T02:33:07Z): *"draggable window
title bars would be an important feature, possibly with a mappable action … However, this belongs in
a separate PR after this one is merged."* Quote it in the PR body; it converts the ask from
controversial to requested.

### 4.1 The action's name and signature

**`mouse_drag_window(self, rows: int = 0) -> bool | None`**, group `mouse`, defined on `Window`.
`<rows>` restricts the press to the top `<rows>` rows of the window; omitted or `0` means the whole
window; an out-of-region press returns `True` so the event passes through to the program.

🚨 **Do NOT name it `start_window_drag`.** `Boss.start_window_drag` exists in **both** refs (master
boss.py:1556, v0.48.2 boss.py:1435) with five required positional arguments, and `dispatch_action`
resolves Boss first by bare `getattr` — measured by **executing** the real `dispatch_action` and
`combine` code objects in the shipped interpreter:

```
start_window_drag      [THE COLLISION]                   → TypeError: missing 5 required positional arguments
a_real_zero_arg_action [POSITIVE CONTROL]                → returned True, no exception
no_such_action_xyz     [NEGATIVE CONTROL]                → returned False, no exception
combine(...)                                             → consumed=True, show_error('Key action failed', …)
```

⚠️ **And V26 found the correction that matters most here: the collision is LOUD only for the
`Window` design.** Executed: adding a second `def start_window_drag` to `class Boss` raises nothing
and pops up nothing — Python keeps the last definition, the new action works perfectly, and the
**incumbent title-bar drag silently dies** at thumbnail-callback time with `takes from 1 to 2
positional arguments but 6 were given`. No config error, no popup, nothing a "no errors in the log"
test would catch. (Conversely, the naive "define it on Window and leave Boss alone" plan is the loud
case: Boss shadows Window and the Window arm is never reached.) Also measured: the incumbent does
not strictly need a *rename* — giving its five parameters defaults makes the zero-arg dispatch
succeed — but that is still an edit to the incumbent, so the recommendation is unchanged.

Name candidates probed FREE on the shipped binary: `begin_window_drag`, `drag_window`,
`mouse_drag_window`, `mouse_begin_window_drag`, `start_dragging_window`, `grab_window`,
`move_window_with_mouse` (with `close_window`/`detach_window` as positive controls reading TAKEN and
a fabricated name as the negative control). `begin_window_drag` is free but sits one word from the
taken name — a near-miss typo is an error popup on every press, not a no-op.

**Rename cost of the incumbent differs by ref** (if anyone proposes it): on master it is passed as a
function **object** (tabs.py:2015) and the C callback string is `'thumbnail_ready'` (boss.py:1589), so
a rename is two pure-Python sites; on 0.48.2 the method **name** *is* the C callback string
(tabs.py:1862, snprintf'd at state.c:1786 and later resolved on boss by name), so a rename there must
change the string too.

### 4.2 File by file

| # | file | status | what |
|---|---|---|---|
| 1 | `kitty/window.py` **or** `kitty/boss.py` | **NEEDS-A-DECISION** (which class) / **CERTAIN** (exactly one) | the `@ac(group, """doc""")`-decorated method. `kitty/actions.py:57` scans exactly `(Window, Tab, Boss)`. See § 4.3. |
| 2 | `kitty/options/utils.py` | **CERTAIN iff the action takes any argument** | a `@func_with_args('mouse_drag_window')` parser in the `# Actions {{{` block. Mandatory: `parse_key_action` (master utils.py:1259-1269 / v:1172-1182) does `parser = func_with_args.get(func); if parser is None: raise KeyError(f'Unknown action: {func}')` the moment a `rest` exists. Template: `resize_window` (master utils.py:604-620) — bare positional words, `log_error` + default on anything invalid, **never raise**. `--flag=value` is reserved for kitten-like actions that go through `shlex_parse`. |
| 3 | `docs/changelog.rst` | **CERTAIN** | one bullet at the **TOP** of `0.49.0 [future]` (heading at :202), blank line above and below, 2-space continuation indent, sentence prose, **no `:pull:` reference** — the maintainer moves it into topical position and appends the ref himself (measured on three of his own `Update changelog` commits: `dac035751`, `e1bdb2c66`, `1f20d4319`). |
| 4 | `kitty_tests/window_drag.py` | **CERTAIN a test is wanted** / **NEEDS-A-DECISION** (new file vs a class appended to `tab_drop.py`) | imports `from .base import BaseTest` — **master-only**; on 0.48.2 `BaseTest` lives in `kitty_tests/__init__.py` and `selection_drag.py`/`tab_drop.py` do not exist at all. See § 6.3. |
| 5 | `kitty/state.c` + `kitty/fast_data_types.pyi` | **NEEDS-A-DECISION** | a pixel-position accessor. Required **only** if the action arms with `drag_started=False` to preserve `drag_threshold` semantics. See § 4.4. |
| 6 | `kitty/options/{parse.py,types.py,to-c-generated.h}` (+ `tools/themes/collection.go`, `tools/cmd/at/set_colors.go` for a colour option) | **CERTAIN: not needed** | Regeneration is required **iff `kitty/options/definition.py` changes**, which has **THREE** triggers, not two: a new `opt()`, a default `mma()` mouse mapping, **and a default `map()` keyboard binding** (which creates no option field yet still emits a `KeyDefinition(...)` line into `types.py`). Measured by **executing kitty's real generator** against master with an `@ac` action added: **zero** diff in all five files, while the positive control (one `opt()`) moved all three `kitty/options/` files. They never move as a set — `to-c-generated.h` is written only `if ctypes:` (master `kitty/conf/generate.py:485`). |
| 7 | `docs/actions.rst` · `docs/generated/*` · `tools/cmd/at/kitty_actions_generated.go` · `kitty/rc/action.py` | **CERTAIN: do NOT touch** | `docs/actions.rst` is a 14-line stub ending `.. include:: /generated/actions.rst`, written at doc-build time by `docs/conf.py:697-700` (master) / `:626-628` (v0.48.2); `/docs/generated/` is `.gitignore:25`; the Go file is `.gitignore:6` and absent from both checkouts; `kitty/rc/action.py:74` dispatches by string through `boss.combine`. **Decisive precedent:** `git grep -ln toggle_window_title_bars` returns exactly three tracked files in both refs — `docs/changelog.rst`, `kitty/boss.py`, `kitty/options/definition.py`. |

**Ship no default `mouse_map`.** A default binding would drag `kitty/options/definition.py` and the
regenerated `kitty/options/types.py` into the diff (measured contrast: `toggle_window_title_bars`,
no default mapping, has 0 hits in tracked `types.py`; `start_resizing_window`, which has defaults,
appears at `types.py:937-938` and `:1060`). Without one, `as_rst` simply omits the "Default shortcuts
using this action" line.

### 4.3 Which class and which group — two readings, both reported

| | A12's reading (better evidenced) | A6's reading |
|---|---|---|
| **class / group** | `Window`, group `mouse` | `Boss`, group `win` |
| **argument** | All eight `mouse`-group actions live in one contiguous `# mouse actions {{{` block in `kitty/window.py` (master :2003-2092). Six of the eight carry the `mouse_` prefix, and the two that do not (`paste_selection`, `paste_selection_or_clipboard`) are exactly the two whose behaviour does *not* depend on where the pointer is — the prefix is not decorative. `self` **is** the window under the pointer for a mouse dispatch (window.py:1420) and the active window for a keyboard one (boss.py:2054-2056), with no `window_for_dispatch` line needed. | Boss resolves first (boss.py:2041); the canonical idiom `w = self.window_for_dispatch or self.active_window` already appears five times; `toggle_window_title_bars` — the action this supersedes — is a Boss `win` action (boss.py:3805-3832); the drag machinery is Boss/TabManager-side. |
| **evidence** | Measured: the name-collision probe, the group census (`{'cp':14,'debug':6,'mouse':8,'mk':4,'sc':15,'misc':33,'win':41,'lay':5,'fs':1,'tab':12,'session':3}`), and the A/B across win/mouse/debug showing the ONLY observable difference is the palette category string. | An idiom census plus an argument by adjacency. |

**The group is mechanically inert** and this is now measured, not inferred (V6): a bytecode census of
the **shipped** binary finds zero group references in `Boss.dispatch_action` / `Boss.combine` /
`Boss.drain_actions` / `Window.on_mouse_event` (positive control: the same census finds `'group'`,
`'misc'` in `get_all_actions` and `'get_all_actions'` in `as_rst`); resolution is a bare `getattr`;
the bind step at `kitty/config.py:136-143` stores the action as a plain string with no group attached;
and injecting a synthetic action under `'win'`, `'mouse'` and `'debug'` changes only the palette
category. So the choice buys **discovery only** — where will someone configuring `mouse_map` look?

**Recommendation: A12's.** It is measured where A6's is idiomatic, and the one property a reader must
not miss is that this action's behaviour depends on where the pointer is. A6's `win` framing is the
graceful fallback if the maintainer objects, at the cost of one `window_for_dispatch` line.

### 4.4 The branch point that decides 1 file or 3

🚨 **This is the single design decision phase 2 must take first, because the region argument's cost is
computed differently on each side of it** (V28).

- **Arm with `drag_started=True`** (skip the threshold): x and y become values nothing in either tree
  ever reads. Zero C changes. The drag begins on the press — which for a deliberate chord is a
  feature, not a degradation. But it discards `drag_threshold` semantics, and the option documents
  itself as "A value of zero disables all dragging" (master definition.py:1170).
- **Arm with `drag_started=False`** (preserve the threshold): requires the **press-instant OS-window
  pixel position**, which no Python getter returns. A cell-derived origin is **not** an approximation
  — it is up to one cell off (45 device px on this box) against a 5 px threshold, 9× the threshold, so
  it defeats rather than approximates it. So: a new accessor in `kitty/state.c` plus its
  `fast_data_types.pyi` stub — *and then the region test in PIXELS costs zero further files* (two more
  keys in the very `Py_BuildValue` at master state.c:1966-1980), and pixels are strictly the better
  unit: finer than the cell, matching our header's real 62-in-90 px geometry, and immune to the
  up-to-one-cell skew `pixel_scroll_offset_y` introduces (`pixel_scroll` defaults to **yes** in both
  refs; master mouse.c:322).

⚠️ **Do not price cells as the zero-C baseline against pixels at "+2 files"** — that trade is false in
both directions. Decide the accessor first, then choose the region unit.

### 4.5 Semantics to copy, and the four guards to add

**Copy from the built-in press branch** (master tabs.py:2018-2030 / v:1865-1877):

- Honour `drag_threshold 0` by refusing to arm (`if threshold:` at master :2025 / v:1872).
- Focus the window on press (`boss.set_active_window(w, switch_os_window_if_needed=True)`).
- Rely on the built-in release path to clear the state — no release binding is needed.
- **Document the action as LEFT-button**, because line master:2019 / v:1866 returns for any non-LEFT
  button *before* the clear.

**Add, because a content-area press breaks the emergent invariant (§ 2.3):**

1. Arm **only** for `GLFW_MOUSE_BUTTON_LEFT`, or teach the handler to clear on the arming button.
2. Refuse to arm when `active_drag_in_window` or `tracked_drag_in_window` is already non-zero.
   (`active_drag_resize` needs no guard — it cannot coexist.)
3. Call `clear_click_queue` for its button, since arm 7 swallows the release and kitty already
   documents the double-click consequence at master mouse.c:672-675.
4. 🚨 **Take start coordinates from the OS window under the pointer EXPLICITLY, never from
   `global_state.callback_os_window`.** That pointer is set at glfw.c:268 on callback entry and NULLed
   on every exit (15 sites), and `Boss.drain_actions` runs any non-first action of a `combine` on a
   zero-delay timer **after the callback returned** (boss.py:2943-2950). A C implementation reading it
   there hits NULL — a crash, or with the customary `if (!osw) return;` guard, a silent no-op.

**One inherited hazard to keep the action away from** (V24): `handle_button_event` takes
`Tab *t = osw->tabs + osw->active_tab` **before** the synchronous Python dispatch and dereferences it
after, re-deriving only `w` and re-deriving it *through* the stale `t`, while `add_tab` reallocs
`os_window->tabs` (`ensure_space_for` = `realloc`, data-types.h:287-294). A `combine` chain ending in
`new_tab` reads freed memory, in both refs. Keep the action's synchronous work minimal and free of tab
creation. It stays latent because the drag call itself returns immediately — measured: `real 0.01s`,
with kitty answering a concurrent remote-control round-trip in 0.01s **0.25s into a live session**.

### 4.6 The doc text (A12 §e, ready to paste)

Placed in the `# mouse actions {{{ … # }}}` block of `kitty/window.py` (master :2003-2092), after
`mouse_selection`. Line 1 is `short_help`; everything after the blank line is `long_help`
(`kitty/actions.py:45-53`). Every role target was verified to exist (`:ac:`toggle_window_title_bars``,
`:opt:`drag_threshold``, `:ref:`conf-kitty-mouse.mousemap``, `:doc:`/graphics-protocol``) —
`docs/conf.py:672-674` sets `ac_role.warn_dangling = True` and `docs/Makefile:4-5,9` builds with `-n`
plus `FAIL_WARN`, so a dangling role breaks the docs build.

```python
    @ac(
        'mouse',
        """
        Begin dragging the window under the mouse

        Starts the same drag that pressing in a window title bar starts, so that the window can be
        re-ordered within its layout, moved to another tab or OS Window, or detached into a new OS
        Window, by dropping it. The drag begins only after the mouse has moved farther than
        :opt:`drag_threshold`; setting that option to zero disables this action as well. While the
        drag is in progress kitty temporarily shows window title bars so that other windows can be
        used as drop targets, hiding them again when the drop completes.

        Unlike :ac:`toggle_window_title_bars` this does not require window title bars to be
        visible, so it can be used to drag a window whose title bar is hidden::

            mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window

        Optionally takes the number of rows, counted from the top of the window, within which the
        press must occur. Presses below that region are passed on to the program running in the
        window instead. This is intended for programs that draw their own header at the top of the
        window, for instance with the :doc:`graphics protocol </graphics-protocol>`, which kitty
        has no way of knowing about::

            mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window 2

        Note that the rows are counted from the top of the window's text area, so when a window
        title bar is visible, row one is the first row below it.

        Map this to the press of the left mouse button. Mapping it to a different button will leave
        the drag armed after the button is released.

        For examples, see :ref:`conf-kitty-mouse.mousemap`
        """,
    )
    def mouse_drag_window(self, rows: int = 0) -> bool | None:
        ...
```

🚨 **The docstring is structurally load-bearing and the shipped interpreter runs
`sys.flags.optimize = 2`, so docstrings are stripped in a frozen build.** `@ac` survives that only
because it takes the help as a **string argument**. An **empty** doc raises `IndexError: pop from
empty list` at `kitty/actions.py:49`, and a group outside `groups` raises
`KeyError: Unknown action type: …` at `:53` — each taking the command palette, the docs build and the
Go codegen down with it. Both measured.

Changelog bullet:

```rst
- A new action :ac:`mouse_drag_window` to start dragging the window under the mouse from anywhere
  in it, or from a specified number of rows at its top, so that programs that draw their own
  headers can make them draggable
```

### 4.7 The upstream-acceptance checklist

1. `./autoformat` — the declared `pre_commit` hook (`local-agent.md:6`); runs `ruff format`,
   `gofmt -s -l -w tools kittens`, and `clang-format --style=file:.clang-format` over every
   `.c/.h/.m/.slang`. CI re-checks all three (`.github/workflows/ci.yml:111-115`,
   `ci.py:349-359`). **`.clang-format` and `autoformat` are master-only** — neither exists at v0.48.2.
2. `ruff check .` clean including the `ANN` ruleset (annotate every parameter and return); single
   quotes, 160 columns, no `from __future__ import annotations` anywhere in the tree, PEP 604 unions.
3. `./test.py type-check` clean — the checker is **`ty` (Astral), not mypy**
   (`kitty_tests/main.py:95-102`; there is no `mypy.ini`/`setup.cfg`).
4. `./test.py` clean, and add a test (`CONTRIBUTING.md`).
5. Two literal CI greps: **no trailing whitespace anywhere**, and **no space after ``:code:` ``**
   (`.github/workflows/ci.yml:81-85`).
6. **Price the hot path in the PR body before he asks.** The maintainer's single sharpest recorded
   review objection is exactly this: *"It results in two calls to set_geometry() per window and even
   worse, both calls are no longer no-ops … This is extremely expensive as changing window geometry
   means sending SIGWINCH to the child process which will then proceed to redraw the entire screen."*
   State in one sentence that when the action is unbound or unfired the per-frame and per-event cost
   is zero, and that the action never calls `set_geometry()`.
7. Commit message: capitalised imperative summary, optional `Area: ` prefix, optional body. **No
   Conventional Commits.**
8. Expect a slow merge and expect him to push his own `Update changelog` / `cleanup previous PR`
   commits afterwards — that is the observed norm on essentially every merge.

---

## 5. CORRECTIONS THE SKEPTICS MADE

The verdicts file defaults `refuted=true` whenever a skeptic could not positively confirm a claim, so
most "REFUTED" rows are **confirmations carrying a correction**. Each entry below is labelled with
what actually changes for an implementer.

### 5.1 The coordinate space is DEVICE (framebuffer) pixels, retina-scaled — and `global_x/global_y` are a DIFFERENT origin
**Confirmed with a correction (V1).** `set_window_being_dragged`'s x,y are OS-window **framebuffer**
pixel coordinates: `osw->mouse_x = x * viewport_x_ratio` (master glfw.c:617-618, 625-626, 647-648,
700-701) with `viewport_x_ratio = viewport_width / logical_width` (state.h:522 + glfw.c:232) — i.e.
2× on this retina box. Distinct from `w->mouse_pos.global_x = mouse_x - left` (master mouse.c:305-306),
which is **window-content-relative**. Anyone exposing `global_x/global_y` as a drop-in accessor for
the drag origin would be off by the window's left/top offset. Consequence: every pixel figure in this
document is a device pixel at 2×, and `dpi/72 == 2` on this box (kitty.conf:1040-1042, :451-454).

### 5.2 "The missing getter is the entire gap" — REFUTED, and this changes the patch's shape
**(V1, V8, V16, A1-SKEPTIC.)** The two factual halves survive and were strengthened: no Python **pull**
accessor for the pixel mouse position exists in either ref, and `get_mouse_data_for_window` is
cell-only. But the operative consequence does not follow, because **x and y are not load-bearing**:
read at exactly one site per version under `if … and not drag_started:`, every other Python reader
takes `[0]/[1]/[:2]`, and C reads only `.id`. So a pure-Python action **is** viable with zero C
changes provided it arms with `drag_started=True`. The C accessor is an **option**, required only on
the threshold-preserving branch (§ 4.4).

### 5.3 "The config-only route CANNOT reproduce the drag threshold" — REFUTED, and measured
**(V25.)** The claim read a call site without reading what the callee does with it — and the cited
line **is** the delivery it says does not exist: `call_boss(handle_window_title_bar_mouse, "KKddiii",
osw->id, w->id, osw->mouse_x, osw->mouse_y, …)` hands the pixels to Python, and the threshold at
tabs.py:1859 is **Python arithmetic on a float Python was just given**. Pixels reach Python on **four
push channels** in both refs (v0.48.2 mouse.c:935, :1278, :1343, :1384; master :965, :1342, :1407,
:1452), none of which the original greps covered. Measured reproduction is in § 3.3(i). **What the
patch buys is therefore not the threshold** — it is the press-instant origin, no per-press
read+compile+exec, no monkeypatch of private methods whose spelling already drifted, and a supported
binding.

### 5.4 "A chord press with zero movement begins a drag" — REFUTED for the stock spelling
**(V25.)** The threshold branch is gated on `if button == -1:  # motion event`, and motion reaches
Python only via `cursor_pos_callback` (glfw.c:610-614), which fires on actual pointer movement. No
motion ⇒ `request_callback_with_thumbnail` is never reached ⇒ the release clears the state. Even the
crude sentinel route needed a motion event to trip. Drag-on-zero-movement follows **only** from
choosing `drag_started=True` at press — an implementer's choice, not a constraint.

### 5.5 "Setting the flag is sufficient to arm from anywhere" — MECHANISM CONFIRMED, sufficiency refuted
**(V2, V4, V7.)** The disjunct, the missing title-bar term and the `window_for_window_id` fallback are
all exactly as stated and are whitespace-identical across the refs — so the approach does not
collapse and the router needs no change. But arming is **one necessary step of four**: four early
returns precede arm 7 (the claim's own sibling artifact listed only three, omitting `active_drag_resize`,
the one that returns unconditionally for every event); the tab-bar arm is tested **first** with no
window term, so over the tab bar the armed state is never consulted; promotion needs
`drag_threshold != 0`; and **the flag has no C-side clear at all**.

### 5.6 The action group is inert at dispatch — CONFIRMED, but the census that "proved" it was not exhaustive
**(V6.)** Confirmed at a level stronger than a source read (bytecode census of the shipped binary,
plus an A/B across three groups). But the supporting census's path list was `kitty kittens tools gen`,
which structurally excludes `docs/` and `kitty_tests/`. There are **five** consumers of
`kitty.actions` in both refs, not three: `kitty/actions.py`, `kittens/command_palette/main.py`,
`gen/go_code.py`, `docs/conf.py` (which names none of the four search terms, so the grep could never
have found it), and `kitty_tests/command_palette.py`.

### 5.7 "No test in kitty_tests enumerates actions" — FALSE, and it is a free acceptance gate
**(V6, V9.)** `kitty_tests/command_palette.py` (11 tests, same count in both refs) enumerates **every**
registered action transitively: `collect_keys_data()` → `build_action_lookups()` +
`add_unmapped_actions()` → `get_all_actions()`. A term-keyed grep for `get_all_actions|as_rst` in
`kitty_tests` returns nothing because the test names the kitten entry point. Measured four-arm run on
the shipped binary: a **well-formed** injected action leaves it **11/11 green** and appears in the
palette data; an **empty docstring** → `IndexError` → **10 of 11 RED**; an **unknown group** →
`KeyError` → **10 of 11 RED**; recovery control green. **Use it as the patch's free red-proof, and run
it before any C work.**

### 5.8 "A wrong action name fails loudly" — FALSE in BOTH directions
**(V9, V12, A6 F6.)** Through the **real** `load_config()` path (negative-controlled with two probes
that do log), an unknown **no-arg** action name stores with **zero** `log_error` lines, and even an
unknown action **with** arguments loads clean — its `KeyError` arrives only at dispatch inside
`Boss.combine`, which catches it into a `show_error` popup and **consumes** the event. (`show_error`
on a `__new__`'d Boss silently no-ops rather than exploding, which is strictly worse.) **Consequences:**
a test must assert a **state change** (`get_window_being_dragged()[0] != 0`), never the absence of a
log line; `raise_error=True` is only a partial net, guarding `combine`'s second `try` (execution) and
not its first (resolution); a bare `Mock()` as the fake window or tab answers every attribute and makes
the negative control **vacuous** (use a plain class or `Mock(spec=[])`); and an action that returns
`True` is reported NOT-consumed although it ran. Also measured: **a real, working, implemented action
invoked with an argument it does not accept returns True, never runs, and leaves the state untouched** —
so an action taking a parameter MUST also be registered in `func_with_args`.

### 5.9 The 0.48.2 drop-classifier coordinate defect is THREE functions / SIX lines, not one
**(V11.)** `_find_window_at` (tabs.py:1933, 1934), `on_window_drop_move` — the preview path — (:1992,
:2005), and `on_window_drop` — the action path — (:2057, :2058). **0.48.2's `on_window_drop` does not
call `_find_window_at` at all**; it inlines its own hit-test loop (:2066-2075), proven on the shipped
binary by `co_names`. Master has **zero** such lines (`rel_x, rel_y = x, y`, tabs.py:2087-2088) and
pins it with `test_drop_with_offset_tab_bar`. So a 0.48.2 backport that fixes only the named function
leaves both the preview and the action mis-targeting. Two further corrections: "inert only because
`tab_bar_edge` defaults to BOTTOM" is too narrow — `os_window_regions`'s else branch (v state.c:783-787)
also zeroes `central` whenever the tab bar is hidden or has too few tabs, and **it stops being inert
DURING a drag** because `window_drag_over_me` forces the bar visible; and the measured hit-test error
is **1×** the offset, not 2× (the code subtracts once; the offset is counted twice in the comparison).
Executed A/B sweep of ~20k pointer positions: central (0,0) → 0% disagreement (inert); (0,30) → 8.2%;
(80,30) → 15.6%; (80,0) → 7.9%.

### 5.10 The 0.48.2 padding swallow does NOT bind this project
**(V18.)** The C mechanism is correct — an initial press inside a window's padding returns at
mouse.c:883 before `dispatch_mouse_event`. **But the antecedent is false and structurally so:** our
header is a graphics-protocol placement anchored at **row 1 col 1**
(`scripts/kitty-pane-title-overlay.py:813, :823`), the live top padding is **0**
(`config/kitty.conf:1109 window_padding_width 0 5 0 5`, after HEAD `a49280bd9` deleted the 22.5pt
reservoir), and a placement anchors to a **cell** and grows downward. So the press lands inside the
cell area, `cell_for_pos` succeeds unclamped, and the mousemap fires **on 0.48.2 today** — corroborated
by the three `mouse_map` bindings already working in the content area (config/kitty.conf:182, 183, 772).
**A1's implication that "the box must move to ≥ 0.49.0" is FALSE for the shipped design.** And master's
clamp is a **trade**, not a pure fix: the same hunk deletes `closest_window_for_event`, so master loses
the 0.48.2 path that dispatches a LEFT press landing in the **margin** — master's own changelog says so.

### 5.11 The mousemap IS reachable from inside kitty's built-in title bar, whenever top padding > 0
**(V17.)** `mouse_region`'s window loop tests `contains_mouse(win)` **first** and the title bar only in
the `else if` (v:1069 vs :1071 / master :1110 vs :1114). A top title bar shifts
`render_data.geometry.top` down by one cell (v window.py:1062 / master :1075) while `effective_padding`
has **no title-bar term** (v window.py:857-858), so the bottom `min(padding.top, cell_height)` px of
every built-in bar fall **inside** `contains_mouse` and route to the CONTENT arm. At
`padding.top >= cell_height` the built-in drag becomes unreachable entirely. Today's resting config has
top padding 0, so the overlap is **currently zero** — the reachability of the built-in bar is a
function of configuration, not a fixed property of kitty. Two further corrections in the same verdict:
v0.48.2 has a **fifth** arm the original claim omitted (a LEFT press resolving to no window is clamped
into the closest window and dispatched, v:1392-1400; master deleted it), and **release- and
click-triggered maps never reach the branch chain at all** — the `active_drag_in_window` and
`tracked_drag_in_window` early returns dispatch with no region test, from any pointer position.

### 5.12 AppKit is not the risk — but two adjacent claims are refuted, and one of them has a side effect
**(V23, V24.)** **Confirmed, independently reproduced, with three controls the original lacked:**
AppKit began a full session (`willBegin` → `moved` → `ended`) from a remote-control dispatch with no
mouse event in the stack and no button down. Controls: zero `Dragging session` lines before the first
fire; zero mouse-button events in the entire log; an NSEvent census showing only
FlagsChanged/KeyDown/KeyUp, which forecloses "a real event was in the stack" and forces the synthetic
branch. Two fires with the pointer demonstrably elsewhere reported the **identical, exactly-integral**
start point, which a real-event branch cannot do.

**Refuted #1:** "it ended `operation: None` precisely because nothing was held." Both replications
ended **`with operation: Move`**. The terminal operation is a function of what is **under the pointer**,
not of button state.

🚨 **Refuted #2, and this one is actionable:** `--debug-input` + `test_dragging` is **NOT
side-effect-free** and must not be scripted as "instrument 1, cheapest, moves no cursor".
`operation != None` means a destination **accepted** the drop, and kitty accepts `text/plain` and
**pastes it into the pane under the pointer** (v boss.py:2013-2021 → `Window.on_drop` window.py:2257-2269
→ `paste_with_actions`; the default `paste_actions` does not gate a plain single-line payload). Both
of the skeptic's drop points fell inside the operator's live full-screen kitty window; the probe most
likely pasted the 76-character test string into it twice. **Any plan that scripts this must park the
pointer over a non-accepting target, or use a payload/instance that cannot be dropped into.**

**Refuted #3 (V24):** "a mouse_map action is in a strictly more favourable position than the code that
already ships." kitty **already** begins an `NSDraggingSession` synchronously inside an AppKit
mouse-event handler with the left button physically held — the **URL drag** does exactly that in
shipping 0.48.2 (v mouse.c:689-702 → `screen_open_url` → synchronous `PyObject_CallMethod` →
window.py:1404-1418 → `start_drag_with_data`; on cocoa the carrying event is `-mouseDragged:` →
`[self mouseMoved:event]`; compiled into the shipped build, "Started URL drag" ×2 against a 4/4
positive control). So the mouse_map position is **the same position as shipping code**, which is the
stronger claim and the one to put in the PR. The window-title-bar drag is the exception, not the rule:
it alone defers to the render loop, and it does so to obtain a GPU thumbnail, not to satisfy AppKit.

### 5.13 Wayland's EPERM is a fast-release RACE guard — and macOS is not precondition-free
**(V20.)** The guard is byte-identical in both refs and fires only at `pointer_button_count == 0`
(button already released); the count drops only on a release or at `pointerHandleLeave`, whose own
comment states the pointer cannot leave the surface during an implicit grab. kitty enters the async
hop only after motion past `drag_threshold` **with the button held**, which is why the shipped
title-bar drag works on Wayland; upstream's remedy for the residual race is **detection** —
`wl_display_sync` + up to 3 retries + cancel — present in both refs. **But kitty carries a portable,
macOS-binding EPERM precondition of exactly this kind:** `start_window_drag()` (master glfw.c:3622-3625
/ v:3161-3163) refuses unless LEFT is held **and** the pointer hovers the originating window. It guards
only the escape-code DND entry (sole caller master dnd.c:1830), **not** the `start_drag_with_data`
route the title-bar drag uses — so "macOS has no precondition" holds only for a route the claim never
names, and any implementation reusing that C helper inherits a **LEFT-button-only** requirement that
contradicts A5's "prefer a modified or non-left button" advice. A synchronous start remains a
defensible **preference**, not a requirement — and a stronger one on master, where the hop is
FIFO-queued behind any other in-flight thumbnail request, than on 0.48.2, where it is one render tick.
Its cost is the press-vs-drag distinction, including double-click-to-rename on release.

### 5.14 "Reuse `drag_threshold`" is right — but "kitty rejects new options" is FALSE
**(V21.)** PR 9626's `window_title_bar_drag_threshold` was proposed and is absent from both refs (0
hits tree-wide; the shipped binary reports `present=False` against `drag_threshold present=True,
default=5`). But the **same PR's** `tab_bar_show_new_tab_button` survived merge and is live in the
0.48.2 binary, as did `window_drag_tolerance`, a new float distance option accepted in 0.46.0. The
measured rule is narrow: **kitty dropped the option that DUPLICATED an existing one.** Two further
corrections: the collapse is **not** a master-era change — it shipped in 0.47.0 and is live on this
box, so a local threshold check exercises the same code a master patch would; and the two long_texts
are **not** identical (master adds a sentence about dropping a single-window tab into another tab's
content area). Reuse is also **structural**, not merely conventional: an action that calls
`set_window_being_dragged(window_id, False, x, y)` inherits the threshold trip for free, and inherits
`drag_threshold 0` as a global disable, which the patch should **document as intended**.

### 5.15 The force-show cost is larger than one row, and is not reachable from the action
**Three verdicts converge (V3, V10, V30, V31).**

- **Confirmed and executed:** `start_window_drag` force-shows bars on every tab of every tab manager
  where `not (min_w > 0 and visible >= min_w)` — at `min_w == 0` that is **every tab**, and
  `window_title_bar_min_windows` defaults to 0 in both refs and is set to 0 in our config (:1196).
  `on_window_drop` then calls `_clear_force_show_title_bars()` **before** classifying the pointer
  (master :2202 before :2234; v :2035 before :2074). Executed on the shipped build's own
  `TabManager.on_window_drop`: **force_show + min_windows 0 → INSERT; control at min_windows 1 →
  SWAP**, same drop, same coordinates, one variable. The A/B's positive arm proves the harness can
  emit SWAP, so the INSERT is a verdict and not a blind instrument. The preview draws quadrant 5
  ("swap") over a drop that performs a directional insert.
- 🚨 **The cost is a PTY RESIZE, not a visual row.** `Window.set_geometry` computes
  `render_ynum = new_geometry.ynum - 1` then calls `screen.resize(...)` and `resize_child(...)` →
  SIGWINCH to every child, down at drag start and back up at drag end, **twice per pane in every tab
  of every OS window**. Not touching the PTY is the entire reason our overlay exists.
- **Plus a SECOND row per OS window showing fewer than `tab_bar_min_tabs` tabs** (V31): a window drag
  independently forces the **tab bar** visible (`tab_bar_should_be_visible` returns True the moment
  `window_drag_over_me` is set, v tabs.py:1288-1291), which reaches C as `has_too_few_tabs`
  (state.c:1149) and carves `cell_height + margins` out of the **central** region (state.c:728, 735-736).
  Our config leaves `tab_bar_min_tabs` at the default **2** — the `tab_bar_min_tabs 1` line is
  **commented out** at config/kitty.conf:685 — so every single-tab OS window pays it.
- **Plus at least FOUR relayouts per tab, not two** (V31): the force-show, the tab-bar flip on
  drag-enter, the flip on drag-leave, and the clear. `TabManager.resize(only_tabs=True)` relayouts
  **every** tab (`only_tabs` skips only `layout_tab_bar()`). Relayout is per **TAB**, not per pane.
- **And it clears the operator's bars machine-wide** (V10, V3): `_clear_force_show_title_bars` iterates
  `boss.all_tab_managers` while `toggle_window_title_bars` only ever sets the flag on
  `self.active_tab_manager`. One drag therefore turns the operator's toggled-on bars off across every
  tab of every OS window.
- 🚨 **Suppression is NOT reachable from the action** (V3): `window_being_dragged` is a 4-field struct
  with no room for intent, and the force-show executes inside `TabManager.start_window_drag`, which the
  action never calls — the thumbnail callback does. Suppression means editing shared drag code or
  adding a struct field, i.e. an upstream-acceptability decision.
- **What it buys is even less than "the swap gesture"** (V3): only the drag-over **preview**, because
  the drop decision runs after the clear. The genuine loss is same-tab drops in `axis_x`/`axis_y` and
  Splits layouts; cross-tab both branches land the window in the destination tab, and in a `full`-mode
  layout the fallback **is** a group swap.
- 🚨 **Two readings on how to handle it upstream, and they disagree.** A4 says: describe the divergence
  as pre-existing and out of scope. **V10 refutes that and has better evidence**: at
  `window_title_bar_min_windows 0` no window has a title-bar hit region at all, so **no title-bar drag
  can be started** — the defect requires `toggle_window_title_bars` to have been pressed first, a
  precondition A4 never stated. A content-press action removes that precondition, making it **the first
  path that reaches this divergence in kitty's stock default configuration**. V10's conclusion: ship the
  one-line ordering fix (classify before clearing, or capture `show_title_bar` per window) **with** the
  action. One nuance V10 also supplies against itself: the post-drag clear is **documented behaviour**
  (`toggle_window_title_bars`'s own docstring: *"After any drag operation completes, the bars are
  automatically hidden again"*), so only the **ordering inside `on_window_drop`** is arguably a bug.

### 5.16 The press site is NOT inert — kitty holds a press-position record it never clears on this path
**(V13.)** `Window.drag_source.initial_left_press {double x, y; monotonic_t at}` exists in **both**
versions (master state.h:366-369 / v:324). It is armed by `arm_potential_drag()` on **every** content-area
LEFT press — with no modifier test, so a chord press arms it — immediately **before** the mousemap
dispatch (master mouse.c:918 then :921), and never on a title-bar press. And on the content-press drag
path it is **never cleared**, because `clear_potential_drag()` runs only from `handle_button_event` and
the release is taken by arm 7. So the two entry points leave **different** C state behind. Whether that
ever changes an outcome is **UNKNOWN**. Two more channels cross press→drop that the original claim
denied: `drag_started` gates the entire drop-preview dispatch and the tab-bar "+" button, and the whole
`global_state.drag_source` struct is created by `start_drag_with_data` and consumed by the drop-finished
path. **An implementation must set `drag_started=True` and must route through `start_window_drag`;
hand-rolling the payload yields a drag with no preview and no unwind.**

### 5.17 `Window.current_mouse_position()` can return `None`, and `global_x/global_y` are window-relative
**(V28, V29.)** Confirmed present on the shipped build, with a **version-discriminating** control
(master-only `Window.drag_selection`/`drag_thumbnails`/`mark_unknown` all read False on the same
build), because the original's negative control (`current_mouse_pixel_position`) exists in no version
and could only ever be absent. Corrections: the function has a **second return**, `Py_RETURN_NONE`
(master state.c:1979 / v:1745) when the `(os_window_id, tab_id, window_id)` triple misses; the real
spans are master :1966-1980 and v :1738-1746; `global_x/global_y` are **window-content-relative**
(`mouse_x - g->left`), not screen-global — which is the coordinate space a content-row band actually
wants; and a press **outside the cell grid never reaches a mousemap at all**, so the band must lie
inside the grid, while `cell_x/cell_y` go **stale** on that path and the pixel fields stay fresh.
One attack that **failed**, reported for honesty: staleness is not a risk on a `press` binding —
`set_mouse_position` is called immediately before `dispatch_mouse_event`, so the cell position is fresh
for that very press. **And band scoping need not be an action argument** (V29): kitty already scopes the
adjacent mouse region with a **global option** (`window_drag_tolerance`), so an option is a legitimate
third placement — against A12's per-binding→argument reasoning, which the corpus contains no *region*
precedent either way for.

### 5.18 Regeneration and the "1 file" claim — CONFIRMED by executing the generator, with two corrections
**(V19 SURVIVED, V22 split.)** The operationally load-bearing half — *an `@ac`-only patch needs zero
regenerated files* — was upgraded from a reading to a **measurement**, with a positive control that
fires. Corrections: regeneration has **three** triggers, not two (§ 4.2 row 6); the named three-file
set is not the whole commit obligation (a colour option additionally rewrites two tracked Go tables);
and they never move as a set. `git ls-files` (not `.gitignore`) confirms tracked-ness in both trees,
with a positive control proving the instrument can detect a committed generated file. V19's boundary:
"no committed generated file" holds **only** for an action that adds no default map/mouse_map.
Mechanical caveat: `gen/config.py:76` ends with `os.execl(autoformat)`, and the committed
`to-c-generated.h` is generator output **post**-clang-format, so regenerating without letting
autoformat run leaves a spurious one-blank-line diff — and `autoformat` runs `ruff format` repo-wide
plus `gofmt` plus clang-format, so `python gen config` can dirty tracked files well outside
`kitty/options/`.

### 5.19 Two figures in our own record are wrong and must be fixed before anything is posted
- **"kitty 0.48.2 exposes 7 bindable `win` actions"** — the count is wrong by ~6×. Measured on the
  installed binary with positive and negative controls: **41** `win` actions, **142** total. The
  upstream draft presents the filtered subset of seven under a heading that reads as the whole group
  (`docs/research/kitty-upstream-drag-action-2026-09-16.md:139-142`). A maintainer checks that in one
  command. **The substantive half is confirmed independently:** across all 142, only five mention
  "drag" (`test_dragging`, `detach_tab`, `move_tab_backward`, `move_tab_forward`,
  `toggle_window_title_bars`) and none begins a window drag at the pointer. The instrument can see
  "drag", so the null is informative.
- **The draft's example chord is a kitty default** — `ctrl+alt+left press ungrabbed` is
  `mouse_selection rectangle` (`definition.py:1285` v / `:1320` master). Fix it to `cmd+left press`
  before posting.

> ✅ **DISCHARGED 2026-09-16 by wave W1** (plan Q19 items 1 and 2). Both figures are now corrected in
> `docs/research/kitty-upstream-drag-action-2026-09-16.md`, with the original wording preserved in
> that file's new § 6 rather than silently overwritten. Two things this section got slightly wrong,
> recorded rather than edited away:
>
> 1. 🚨 **The prescribed replacement chord is superseded.** *"Fix it to `cmd+left press`"* is the
>    wrong target now: plan Q12 rules **`cmd+shift+left press`**, and Q11(b) hardens that from a
>    preference to a near-certainty — `cmd+left press` kills `config/kitty.conf:821`, the only
>    link-open gesture that works in a grabbed pane, and collides with `show_hyperlink_targets cmd`
>    so that hold-⌘-preview-then-click becomes hold-⌘-preview-then-DRAG. W1 wrote
>    `cmd+shift+left press`. Do not "restore" `cmd+left`.
> 2. **"`ctrl+alt+left press ungrabbed` is `mouse_selection rectangle`" is right but reads as
>    absolute.** It is TAKEN in `ungrabbed` **only** and **FREE in `grabbed`** — the grabbed
>    rectangle-selection binding is a different chord, `ctrl+shift+alt+left`
>    (`definition.py:1346` v). State the mode, or the next reader probes `grabbed`, finds it free,
>    and reopens the question.

### 5.20 Our own `config/kitty.conf:335-323` closure is HALF REFUTED — mark it in place, never delete
**(A11 F13.)** The three-part sentence *"the overlay … is not in kitty's hit-test and can never carry a
hand cursor or be dragged, however it is drawn"* splits:
- **"not in kitty's hit-test"** — **stands.**
- **"can never carry a hand cursor"** — **stands**, and was attacked directly (§ 3.4).
- **"can never be dragged, however it is drawn"** — **REFUTED.** The band's pixels sit inside an
  ordinary window region, which *is* mouse-mapped; the hit test is **bypassed** by the `||` at
  mouse.c:1362, not satisfied.

> ✅ **DISCHARGED 2026-09-16 by wave W1** (plan Q19 item 3). The refutation is now written into
> `config/kitty.conf` beside the original sentence, which is **left unedited** — the § 3 block there
> carries the `||` at v `mouse.c:1362` verbatim and states which two thirds still stand. The edit is
> **comment-only**; no non-comment line of that file changed, which is the mechanical check plan § 2
> requires of any W1 touch of the live kitty config.

Also note A11's own closing claim that *"0.48.2 vs master is a non-issue for everything this axis
touched"* is refuted in one place (V25): master changed the very thumbnail call A11's own kitten
executed.

### 5.21 The headless wall is real, and the attribution argument for it was wrong
**(V14 SURVIVED with one link replaced.)** The engineering conclusion holds in both refs:
`start_drag_with_data` guards on `if (!w || !w->handle)` (master glfw.c:3691-3695 / v:3221-3222) and
reaches `glfwStartDrag` with **no `in_test_mode` branch**, unlike its sibling
`start_window_drag(Window *w, bool in_test_mode)` (master glfw.c:3619-3625), which skips the handle
requirement and returns before `glfwStartDrag`. Engaging dnd test mode changes nothing — measured with
the test write func proven invoked. **But do NOT use `request_callback_with_thumbnail` as the
discriminator:** it is wrapped in the `WITH_OS_WINDOW` **for-loop macro** and returns `None` for a
nonexistent id exactly as for a fake one. The working discriminator is `set_os_window_icon`, whose
guard is `if (!os_window)` alone: a bogus id gives a clean `KeyError`, the fake-window id **SEGFAULTS**
dereferencing the NULL handle — direct proof that `w != NULL && w->handle == NULL`. And a
kitty-**window**-drag test must patch **`kitty.tabs.start_drag_with_data`** (master tabs.py:2059 /
v:1906), not the `kitty.window.start_drag_with_data` that `selection_drag.py:221` patches for the
text-selection drag.

### 5.22 "`handle_window_title_bar_mouse` has zero coverage BECAUSE the C primitive is missing" — the causal claim is refuted
**(V15.)** Zero coverage is a true **fact** (grep of `kitty_tests` returns nothing in either ref), and
no existing primitive can synthesise a press **routed** to that handler — `mouse_event` has exactly
three callers, all GLFW callbacks; the handler is `static` with one call site; and ctypes cannot reach
it either (`-fvisibility=hidden`, `setup.py:651`; the extension exports 8 symbols and `_mouse_event`
is not among them, against an 8-symbol positive control). **But the "Consequently" is false:** the
handler is pure Python and **fully drivable headless today** with stdlib `unittest.mock` and shipped
exports — measured in the installed binary, press arms `(7, False, 12.0, 8.0)`, supra-threshold motion
promotes to `(7, True, …)` with `thumbnail_calls = 1`, and **four** negative controls (sub-threshold,
unarmed, right button, `drag_threshold 0`) all correctly decline. Two further corrections:
`mouse_event` does **not** hold the hit test — `mouse_region()` is its own function with six callers,
one of which (`update_mouse_pointer_shape`) **is** exported to Python as `update_pointer_shape`
(state.c:2043); it is reachable but not usable, segfaulting against the only Python-creatable OS window
because `os_window_regions` derefs a NULL `fonts_data`. And the exported `mouse.c` method table is
**master-only five entries**; v0.48.2 has **four** (`test_scale_scroll` is master-only, confirmed
absent from the shipped build).

### 5.23 The border-tolerance finding — CONFIRMED by execution, with one load-bearing omission
**(V32 SURVIVED as a precision fix, not a refutation.)** The mechanism is real, identical in both refs,
and the geometry was confirmed by **executing the shipped build's own `kitty.borders.add_borders`**.
The claim named **two** config options where **three** are required, and the omitted one has the
**opposite default**: `draw_minimal_borders` defaults to **True** upstream (v `options/types.py:577`)
and our conf sets it to **`no`** (kitty.conf:1133). That choice is what routes border rects through
`add_borders`, which emits all four edges of **every** group. Under kitty's default the rects come from
`get_minimal_borders`, and `layout/vertical.py`'s `start_offset=1, end_offset=1` trims the first and
last `BorderLine` — so the **topmost pane would have no top border rect and its row 0 would be fully
reachable**. The claim is true of *our* configuration and false as a general conditional.

> 🚨 **CORRECTED 2026-09-16 (W1 / plan Q19 item 8) — the `vertical.py` half of that sentence is off
> this box's code path.** The original stays above; this is the correction beside it. `start_offset`
> / `end_offset` are parameters of `kitty/layout/vertical.py::borders()` (v0.48.2 `:19`), and that
> function is imported by exactly two modules — `layout/interface.py:10` (the registry) and
> `layout/tall.py:27`. **The operator runs `enabled_layouts splits,stack`** (`config/kitty.conf:76`),
> and `layout/splits.py` imports nothing from `.vertical` — it has its **own** `minimal_borders` at
> v `splits.py:703`; `stack.py` has none at all. So the "topmost pane would have no top border rect"
> reasoning describes a layout he does not use, and cannot be used to price remedy (b) for him.
> **The measured splits-layout result is BETTER than this text claims** — see plan § 4.M/Q8(d):
> under `draw_minimal_borders yes`, hsplit drops from a 24 px frame on every pane to a single 12 px
> top edge on non-topmost panes only, **vsplit goes to ZERO**, and the 17 px divider dead zone
> disappears. What the text gets RIGHT and keeps: the claim is true of *our* configuration and false
> as a general conditional, and `draw_minimal_borders` really does default to `True` upstream.

Two smaller
corrections: master's `} else if (r.window_border) {` is at line **1433**, not 1432 (1432 is a `debug()`
call — and our own A10 table carries the same error); and "12 device px" is 2×-display-specific
(`tolerance = round(6 × scale)`, 12 at 2×, 6 at 1×), though the **19.4% fraction is scale-invariant**.
Understated rather than overstated: because **bottom** padding is also 0, the bottom 12 px are eaten
identically — the unreachable region is a **frame**, not a top edge.

---

## 6. BUILD AND TEST

### 6.1 The verified build recipe

```sh
# 1. toolchain — `go` was the ONLY missing dependency                              15s
brew install go                                    # go 1.27.1; go.mod floor is 1.26.0
# `go` MUST be on PATH for EVERY build: dev.sh:9 is `exec go run bypy/devenv.go "$@"`.
# Controlled both ways: without it, `./dev.sh: line 9: exec: go: not found`.

# 2. source at a SHORT path — see the wall below                                    1s
K=/private/tmp/kitty-dev                           # 22 chars
mkdir -p "$K"
(cd <kitty-src>/master && tar cf - --exclude='dependencies/darwin-arm64' .) | (cd "$K" && tar xf -)

# 3. deps + build                                                            14s + 47s
cd "$K"; export PATH="/opt/homebrew/bin:$PATH"
./dev.sh deps                                      # 49.6 MB bundle + 2.36 MB nerd font
./dev.sh build                                     # -> kitty/launcher/kitty, rc=0, ZERO warnings

# 4. iterate                                                                   1s – 9s
$EDITOR kitty/mouse.c && ./dev.sh build            # 9s
./test.py --module mouse                           # 1s   (NOT `./test.py mouse` — that matches METHOD names)
```

Measured iteration table: no-op **1s** · touch a `.py` **2s** · edit `kitty/mouse.c` **9s** · full 89-file
C recompile (`--debug`) **9s** · back to release **12s**. Python edits are effectively free; a C edit
costs ~9s of which ~8s is the fixed link + go-tool step. Codegen is automatic on every build
(`setup.py:1369`, `:1379`, `:1457`), so a new action needs no extra step. Footprint ~2.5 GB total, of
which ~1.6 GB (go caches + Homebrew go) is shared by any future build.

### 6.2 🚨 THE PATH-LENGTH WALL

**`./dev.sh deps` FAILS at the session scratchpad path**, exit 1, first invocation, loudly:

```
error: install_name_tool: changing install names or rpaths can't be redone for:
  …/dependencies/darwin-arm64/python/…/lib-dynload/pyexpat.cpython-314-darwin.so
because larger updated load commands do not fit
```

**Mechanism.** The prebuilt bundle is built at a fixed 31-character prefix
(`bypy/devenv.go:25 macos_prefix = "/Users/Shared/kitty-build/sw/sw"`) and relocated with
`install_name_tool`; rewriting a **longer** load command needs spare Mach-O header padding, and
**exactly one file in the bundle lacks it**. Binary-searched against a **pristine** re-extraction (the
already-half-fixed tree gives a wrong answer — only 2 of its 49 relocatable files still matched the
prefix), with a short-root positive control and a 144-char negative control that reproduced the
failure: **`max_root_len = 106` ⇒ a repo path ceiling of 80 characters**. Every other file tolerates
≥260. The scratchpad root is 144.

**Cure, verified end to end:** build at a short, durable path. `/private/tmp` is subject to macOS's
3-day cleanup of unaccessed files; `~/Development/kitty-dev` (37 chars → root 63) is durable and well
inside the bound. **The tree is location-bound** — moving it afterwards requires `make clean`.
⚠️ The 80 is a property of *that tarball* (rebuilt upstream 2026-09-16 07:51), not of kitty; keep well
under it and let `deps` shout if it changes.

**Both refs build.** v0.48.2: deps 12s, build 27s, rc=0, zero warnings. So **a patched build can be
made of the exact version the operator runs**, which removes a whole class of "does this reproduce on
the installed build" ambiguity. The build systems differ by exactly one line
(`os.Setenv("SLANGC", …)`, master `bypy/devenv.go:396`).

### 6.3 Running it without touching the operator's kitty

Two isolation hazards, both measured:

1. **Config.** `get_config_dir` checks `KITTY_CONFIG_DIRECTORY` first with no validation, else
   `XDG_CONFIG_HOME`, else `~/.config`. Controlled both ways: with the env var → `/private/tmp/kdev/config`;
   **without it → `/Users/chrisren/.config/kitty`**, i.e. a naive dev launch loads the operator's config
   (which sets `allow_remote_control socket-only` and `listen_on unix:/tmp/kitty-{kitty_pid}`).
2. 🚨 **This agent shell already points at the operator's live kitty:** `KITTY_LISTEN_ON=unix:/tmp/kitty-97084`,
   `KITTY_PID=97084`, `KITTY_WINDOW_ID=341`. **Any bare `kitten @ <cmd>` drives the operator's terminal.**

```sh
D=/private/tmp/kdev; mkdir -p "$D/config" "$D/cache" "$D/run"
printf 'allow_remote_control yes\nlisten_on unix:%s/run/sock\nconfirm_os_window_close 0\n' "$D" > "$D/config/kitty.conf"
env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
    KITTY_CONFIG_DIRECTORY="$D/config" KITTY_CACHE_DIRECTORY="$D/cache" \
  /private/tmp/kitty-dev/kitty/launcher/kitty --listen-on "unix:$D/run/sock" --instance-group kdev
# drive it with --to, NEVER bare:
/private/tmp/kitty-dev/kitty/launcher/kitten @ --to unix:$D/run/sock ls
```

- **Put the dev socket OUTSIDE `/tmp/kitty-*`.** `bin/cc-kitty-socket` scans that glob and returns the
  oldest; `scripts/kitty-pane-title-overlay.py:683` globs it and **returns `None` when it finds more
  than one** — a dev instance there would break the overlay's fallback discovery. Verified: the
  recipe above left `/tmp/kitty-*` holding only the operator's socket, and `cc-kitty-socket` still
  resolved it.
- **Do NOT launch `kitty/launcher/kitty.app`** — it carries the **same bundle identifier**
  (`net.kovidgoyal.kitty`) as the installed app. The bare binary is sufficient and avoids
  LaunchServices entirely (kitty sets `NSApplicationActivationPolicyRegular` itself).
- 🚨 **Never prove "I am running the patched build" from `--version`.** Master at `1d67ecd4` still
  declares `Version(0, 48, 2)`, so both report `kitty 0.48.2`. The check that works:
  `kitty +runpy 'import kitty; print(kitty.__file__)'` — a `.py` under the build tree means dev, a
  `.pyc` under `/Applications/kitty.app` means installed.

### 6.4 Can the drag be tested without a human hand? — the honest answer

**Yes, down to but not including the OS handoff.** Four stages:

| stage | headless? | evidence |
|---|---|---|
| 1. synthetic press → region hit test → arm 7 | **NO** | `mouse_event` has exactly three callers, all GLFW callbacks; the handler is `static` with one call site; ctypes is closed by `-fvisibility=hidden`. `send_mock_mouse_event_to_window` takes a **PyCapsule** over a heap `Window` that is *not* in `global_state.os_windows`, and routes to `dispatch_mouse_event` / `handle_mouse_movement_in_kitty` — it never goes near `mouse_event()`. |
| 2. arm + threshold cross + payload | **YES** | Measured three ways: the real `Boss.combine(..., dispatch_type='MouseEvent')` from a real `load_config` mousemap onto a fake window → `(1, False, 12.0, 8.0)` with a negative control returning `False` and leaving `(0, False, 0.0, 0.0)`; the real unbound `TabManager.handle_window_title_bar_mouse` arming and promoting with four negative controls; and the full arm→promote→clear round trip. |
| 3. thumbnail render | **NO** | the C call only sets a global slot and marks the OS window dirty; the callback fires from the render loop. |
| 4. `start_drag_with_data` | **NO** | `!w->handle` ⇒ `KeyError`, no test-mode hatch (§ 5.21). |

**The suite is headless by construction on macOS:** `grep -rln "create_os_window\|glfwCreateWindow\|glfwInit" kitty_tests/`
returns **no files**; upstream CI runs `./test.py` on `macos-latest` with no xvfb and no DISPLAY; the
runner's workers `os.setsid()` and redirect fds 0/1/2 to `/dev/null` with the comment *"Tests must
never depend on the terminal the test suite happens to be run from"*. Measured: the shipped 0.48.2
frozen suite ran **359 tests in 19.388 s**. Master's wall time is **UNKNOWN** — it has ~488 test
methods and a parallel worker pool (`PARALLEL_THRESHOLD = 20`, `min(cpu_count, 8)` subprocess workers
on darwin), and neither clone ships a built launcher.

**The mouse leg specifically needs CGEvents or a hand.** There is no `send-mouse-event` remote-control
command in 0.48.2. Three instruments, ranked:

1. `kitty --debug-input`, grep for `Dragging session started at:` / `moved to:` / `ended at:` — these
   are **AppKit delegate callbacks** (master cocoa_window.m:4287/4293/4321), so they prove AppKit
   really began a session, not kitty's belief about itself. 🚨 **Not side-effect-free** — see § 5.12.
2. `kitty @ ls` → per-window `neighbors` — proves the layout actually changed.
3. A **slow** synthetic CGEvent stream (`draghold`-shaped: 250 ms hover, 120 ms press dwell, slowed
   motion). **This driver no longer exists in the repo** — it survives only as a sentence at
   `docs/research/kitty-pane-title-overlay-2026-09-14.md:840`. Rebuild it, **commit it, and record its
   invocation**, or the next session pays for it again.
4. A hand drag — ground truth, operator-only, needed for feel rather than correctness.

🚨 **Do not budget against a refuted finding.** The brief's premise that "a synthetic CGEvent stream
may be unable to begin an NSDraggingSession at all" (§ I7 of the overlay doc) was **withdrawn by § I9
of that same file**, in bold, with a measured 4-row table (three drags reordered panes, with a
`move_window` control passing in the same run) and a mid-drag capture of kitty's own drag thumbnail and
green drop-target line. Today's probe refutes it a second, independent way (no CGEvent at all).

### 6.5 The test to write

A new `kitty_tests/window_drag.py` importing `from .base import BaseTest` (master-only), or a
`TestWindowDragStart(BaseTest)` class appended to `tab_drop.py`. Helpers: a `_fake_window()`
contextmanager wrapping `dnd_test_create_fake_window()` / `dnd_test_cleanup_fake_window()` that calls
`set_window_being_dragged()` in its `finally` (the state is **process-global**), and the
`kitty_tests/keys.py:688` `Boss.__new__(TestBoss)` idiom.

- **T1** the action is bindable in `mouse_map` — the only test that catches a rename breaking the
  documented config line.
- **T2** 🚨 **the load-bearing one** — the action arms the drag. Assert `get_window_being_dragged()`,
  never `combine`'s return value alone, and pass `raise_error=True` (with § 5.8's caveat that it only
  covers execution).
- **T2-neg** an unimplemented name is not consumed and writes nothing. **This is the control that makes
  T2 mean anything, and a bare `Mock()` destroys it.**
- **T3** threshold crossing starts the drag — drive `handle_window_title_bar_mouse` unbound at a
  distance > `drag_threshold`, assert the thumbnail request fired once and `drag_started` is True; a
  **sub-threshold** move must NOT request one. **This is the only test that does the distance
  arithmetic, so getting the coordinate space wrong is invisible to every other test in the suite.**
- **T4** the payload — patch `kitty.tabs.draw_single_line_of_text` and `kitty.tabs.start_drag_with_data`,
  assert the MIME key and value, then set `side_effect = OSError` and assert the state was cleared.
- **T5** no window ⇒ no crash, state untouched.
- **Passthrough** must be asserted separately: a region-restricted action that consumes when it should
  pass through is invisible to the arming test.
- **Do NOT reach for the `dnd_test_*` family beyond `create/cleanup_fake_window`** — those hooks
  drive `w->drag_source`, the OSC protocol a *client program* uses, and share no state with
  [CORRECTED 2026-09-16 by §10.5: this said "those thirteen hooks", which is wrong for exactly
   one of them. `dnd_test_set_mouse_pos` touches NO `drag_source` field — it writes only
   `w->mouse_pos.{cell_x,cell_y,global_x,global_y}` (master `kitty/dnd.c`, verified), which makes
   it the one headless lever for a region/passthrough test. Do not exclude it with the rest.]
  `global_state.window_being_dragged`.

---

## 7. OUR INTEGRATION

### 7.1 The config change unlocked

```
# The drag lives on the band we draw. `press`, not `click`: promotion happens on MOTION, and a
# `click` is only synthesised on release. `grabbed,ungrabbed` because Claude Code runs in
# essentially every pane and holds the mouse.
mouse_map cmd+left press grabbed,ungrabbed mouse_drag_window
```

**Retires:**

1. `map cmd+opt+b` (config/kitty.conf:601) — its only job is to raise real, hit-tested bars so a pane
   can be dragged.
2. The `combine :` prefix on ⌘⇧B (:502), collapsing it to a single `launch` of the overlay toggle. The
   guard exists only because the two views **stack** (kitty's real bar takes the top row; the overlay
   then paints over the pane's first *content* row, producing the operator's 2026-09-15 "why do we have
   double title" screenshot).
3. `scripts/kitty-pane-title-toggle.sh` (93 lines) and `config/kitty-title-on.conf`, plus their
   `install.sh` and `scripts/deploy-parity-assert.sh` wiring.
4. `tests/kitty-conf-bindings.bats`'s `real_bar_key()` / `glance_key()` role classifier (`:99-127`,
   `:215-261`, `:576`) — it exists solely to arbitrate **two** chords. `tests/kitty-title-zero-shift.bats`
   needs re-reading rather than assuming (it pins the 22.5pt reservoir, which HEAD `a49280bd9` already
   deleted).

⚠️ **Do NOT delete `window_title_bar_align` or the four `window_title_bar_{active,inactive}_{fg,bg}`
colours** (kitty.conf:1210-1214). They look dead once the real bars are never deliberately raised, and
they are not: `TabManager.start_window_drag` paints the **drag thumbnail** in them (master
tabs.py:2052-2053, `opts.window_title_bar_active_foreground or opts.active_tab_foreground`).

### 7.2 What the collapse does NOT buy

**A zero-shift drag.** It buys a zero-shift *glance* plus a drag that still steals a row, resizes every
PTY twice, and fires at least four relayouts per tab (§ 5.15). You stop paying the row for the
**decision** to rearrange; you still pay it for the **rearrange**. Today ⌘⌥B already costs one row and
two PTY resizes per peek (`config/kitty-title-on.conf:53-58` says so in its own words), so this is a
real improvement, just smaller than the draft implies.

Also expect the **rename prompt on a double chord-press**, if the action routes through
`handle_window_title_bar_mouse` verbatim (v tabs.py:1878-1881). Decide before it ships as a surprise.

### 7.3 Chord layout

Probed against the **loaded** mousemap (`load_config(~/.config/kitty/kitty.conf)` inside the shipped
0.48.2 interpreter, looking each candidate up as a `MouseEvent`), 37 entries, two positive controls
both correctly TAKEN, and the instrument distinguishes the two modes:

```
candidate                    grabbed   ungrabbed
left press  (no mods)        FREE      TAKEN       mouse_selection normal
cmd+left click  [POSCTRL]    TAKEN     TAKEN       mouse_handle_click link
right press     [POSCTRL]    TAKEN     TAKEN       launch --type=background …/kitty-pane-menu
cmd+left press               FREE      FREE
cmd+shift+left press         FREE      FREE
cmd+opt+left press           FREE      FREE
ctrl+cmd+left press          FREE      FREE
opt+left press               FREE      FREE
cmd+middle press             FREE      FREE
```

| candidate | verdict |
|---|---|
| **`cmd+left press`** | **best** — free both modes, matches the `cmd+left click` precedent at :772, and the file already records that **kitty ships no `mouse_map` using cmd/super at all** (:179, :768). **Cost: it kills `cmd+left click → mouse_handle_click link`**, because arm 7 swallows the release (§ 3.5 #7). |
| `cmd+shift+left press` | good second; two modifiers is more deliberate. Keeps the link click alive. |
| `cmd+opt+left press` | fine, but `macos_option_as_alt left` (:296) makes left-⌥ a Meta modifier for the app. |
| `ctrl+cmd+left press` | ⚠️ **avoid** — `ctrl`+left-click is macOS's right-click emulation. |
| `opt+left press` | avoid on principle — ⌥ is the modifier this file deliberately hands to the application. |
| `ctrl+alt+left press` | ⛔ **TAKEN** — kitty's shipped `mouse_selection rectangle`. |
| bare `left press` | unusable — binding it removes plain drag-select from every pane. |

**Claude Code changes nothing, and the reason is measured twice.** (1) kitty dispatches the mousemap
**before** forwarding to the child (v mouse.c:894-899) — `grabbed` is the lookup key, not a veto,
which is why our right-click menu works inside live sessions. (2) The live 2.1.260 binary asks for
`?1000h` + `?1006h` **only** — zero `?1002h` (button-event/motion) and zero `?1003h` (any-event),
stable across four installed versions — and kitty's encoder gate forwards only PRESS and RELEASE under
`BUTTON_MODE`. **Motion is never reported to Claude Code**, so the drag gesture takes nothing it uses.
What the chord *does* take is one press+release pair on that one modifier combination.

> 🚨 **CORRECTED 2026-09-16 (W1 / plan Q19 item 9) — leg (2) is a GREP ARTIFACT, and phase 3 must
> not repeat it.** The original stays above. Measured (plan § 4.M/Q11(a)): the live binary's default
> mouse mode is **`full`** = `?1000h ?1002h ?1003h ?1006h` — producer `wH()`, three call sites, with
> both override env vars measured absent on this box. **Motion IS reported to Claude Code, up to the
> press.** The sentence "motion is never reported" is false as written; a grep that finds only
> `?1000h`/`?1006h` found the literals it searched for, not the mode that is actually set.
>
> **The CONCLUSION survives, for a different reason, and phase 3 must carry the reason rather than
> the sentence:** motion is suppressed **during** the drag because kitty's arm 7 short-circuits it
> (v `mouse.c:1362` — the same `||` that makes the whole feature possible), **not** because the
> program never asked for motion. The chord still takes only one press+release pair.
>
> ⚠️ *Honest bound, carried forward from the measurement:* "live mouse mode is `full`" is
> **statically** measured — producer, call sites, and the measured absence of both override env
> vars. The three-arm pty capture came back identical in all arms and is recorded as a NON-VERDICT.

### 7.4 🚨 THE `window_drag_tolerance` × ZERO-TOP-PADDING INTERACTION

**This is the finding that most constrains band-scoping, and it is independent of everything else.**

Three settings together, and **the third has the opposite default upstream**:

| | ours | upstream default |
|---|---|---|
| `window_drag_tolerance` | **6** (kitty.conf:314) | 2.0 |
| `window_padding_width` | **0 5 0 5** — top AND bottom zero (kitty.conf:1060) | 1.0 |
| `draw_minimal_borders` | **no** (kitty.conf:1133) | **yes** |

`mouse_region` expands every border rect by `tolerance = round(OPT(window_drag_tolerance) × dpi/72)`
outward on **all four sides**, and on macOS `dpi/72 == display scale`, so **tolerance = round(6 × 2) =
12 device px** here. The routing order is what makes it bite: `} else if (r.window_border) {` (v
mouse.c:1370 / **master :1433**, *not* 1432) precedes `} else if (w) {` (v :1389 / master :1463), and
`mouse_region` **returns early** with `window_border` set, so the title-bar and content loops are never
reached.

**Therefore, in any tab with more than one visible window** (`if (detect_borders && num_visible_windows(t) > 1)`,
v :1004 / master :1032) **the top 12 device px of every pane — 19.4% of our 62 px painted band, 26.7%
of row 1 — never reach any `mouse_map` at all.** A press there starts a **border resize**. In a
single-pane tab the whole band is reachable, because border detection is skipped entirely.

**Measured by executing the shipped build's own `kitty.borders.add_borders`** on a synthetic group,
with a control:

```
OURS (effective top pad 0px):  top border rect px.bottom = 200 == geometry.top
                               border_contains_mouse(tol=12) covers y < 212  ⇒  12 px of the CELL GRID eaten
CONTROL (top pad 20px):        px.bottom = 180; covers y < 192 < 200         ⇒   0 px eaten
Same run, other edges: bottom 12 px eaten; left 2 px; right 2 px (the 5pt=10px side padding absorbs 10 of 12)
```

So **the unreachable region is a frame, not a top edge**, and the control identifies the two cheapest
remedies:

1. **Top padding ≥ tolerance costs zero reachable px** — but that is exactly the reservoir the operator
   has rejected twice.
2. **`draw_minimal_borders yes`** would fix it for the **topmost pane only**: `layout/vertical.py`'s
   `start_offset=1, end_offset=1` drops the first and last `BorderLine`, so the topmost pane gets no
   top border rect at all.
   > 🚨 **CORRECTED 2026-09-16 (W1 / plan Q19 item 8).** Same defect as § 5.23, and W7 must cite the
   > corrected figures when it quotes this remedy. `vertical.py` is **not on this box's code path**:
   > `enabled_layouts splits,stack` (`config/kitty.conf:76`), `splits.py` never imports `.vertical`
   > and carries its own `minimal_borders` (v `:703`). `vertical.borders()`'s offsets reach only
   > `interface.py:10` and `tall.py:27`. **Measured on the real splits layout** (plan § 4.M/Q8(d)):
   > hsplit → a single 12 px top edge, non-topmost panes only; **vsplit → ZERO**; divider dead zone
   > → gone. So remedy (b) is the front-runner, not the "topmost pane only" partial written here.
   > **Its price, stated because it is the operator's call and not ours:** the active-pane box
   > disappears entirely. That trade is handed to him at W4 with both screenshots, at ~70%
   > conviction he keeps the box — below the threshold at which an agent decides.
3. Lowering `window_drag_tolerance` — but kitty.conf:306-313 argues 6pt is load-bearing for divider
   grabbing at 30 panes.

This is a genuine trade and belongs in the plan, not in a comment.

### 7.5 The band-scoping problem, in the units the argument would use

Our overlay knows its band **to the pixel** and it is **cell-aligned by construction**:

```python
# scripts/kitty-pane-title-overlay.py:241, 245-255
BAND_FILL_CELLS = 1.378          # the PAINTED band, in cells: 62px at a 45px cell
def band_geometry(cell):
    cell = max(int(round(cell)), 1)
    fill = max(int(round(cell * BAND_FILL_CELLS)), 1)
    cover = int(math.ceil(fill / float(cell))) * cell
    return fill, cover
```

The cell size is **not assumed** — it is read per pane from the tty via `TIOCGWINSZ`. Evaluated across
every plausible cell size (16, 22, 30, 36, 44, 45 px), the placement covers **exactly 2 rows** at every
one, painting ~69% of them; the 28 px tail at a 45 px cell is painted in `GROUND = (0x1e,0x1e,0x24)`,
i.e. the terminal background, so it reads as an empty line while hiding the pane's real content row 2.

**So:** the region whose content the overlay *hides* is exactly `cell_y ∈ {0, 1}` — a cell-resolution
predicate, exactly expressible. The region the operator *sees as a bar* is 62 px = `cell_y == 0` plus
the top 17 px of `cell_y == 1`. **Cell resolution cannot express that**: `cell_y <= 1` over-covers the
visible bar by 28 px, `cell_y == 0` under-covers it by 17 px. Neither is paint-exact without a pixel
accessor.

Two further closures worth carrying: `parse_mouse_map` is a **four-field grammar** with `modes`
validated against exactly `{grabbed, ungrabbed}` — **scoping cannot come from the config line**. And
`launch --type=background` (the shape all three of our existing `mouse_map` lines use) receives
**nothing** about where the click was (`grep` over `kitty/launch.py`, `kitty/child.py` → no output), so
the "read the position in a helper script" route is closed; the scope must be in-process.

**A10's read, worth weighing in phase 2: ask for the action UNSCOPED and take it.** Our own config
already ships two unscoped `mouse_map` lines (right press → pane menu, :182-183) that nobody has
complained about, and `drag_threshold 5` means a press that does not move is a no-op. The counter is
§ 3.4: a config-only handler **cannot** decline a press, so if scoping is required, route A cannot
deliver it and only the patch can.

---

## 8. OPEN QUESTIONS FOR THE PLAN PHASE

**Q1 — Do both deliverables ship, and in what order?**
Open because A11's result reframes the project: the capability exists, so B is an improvement rather
than an enabler, and A is shippable to the operator immediately. *Settled by:* a plan-level decision.
The corpus's recommendation is unanimous — **build A first**, because it answers Q9 and Q10 (the only
two questions that can still change B's design), costs ~30 lines plus one config line, and
positive-controls the patch: if A's drag behaves correctly, then B is provably just a faster,
threshold-correct spelling of it.

**Q2 — Arm with `drag_started=True` or `drag_started=False`?**
Open because it decides a 1-file patch versus a 3-file patch, and because the region argument's cost is
computed differently on each side (§ 4.4). *Settled by:* deciding whether `drag_threshold` semantics are
wanted for a deliberate chord at all. If yes, the C accessor lands and pixels become the free and
better region unit; if no, the patch is one Python file.

**Q3 — Does the action take a `rows` argument, take none, or does the region become an OPTION?**
Open: A12 argues per-binding ⇒ argument, A6 argues take none in v1, V29 points out kitty already scopes
the adjacent mouse region with a **global option** (`window_drag_tolerance`), and the corpus contains
**no region precedent either way**. *Settled by:* the PR review, or by resolving Q2 first (a pixel
accessor makes the argument free).

**Q4 — Name, class and group: `mouse_drag_window` on `Window` in `mouse`, or `start_dragging_window` on `Boss` in `win`?**
Open: both are mechanically equivalent, and it is a taste call by the one person who decides.
*Settled by:* the PR body asking, or by following `toggle_window_title_bars`'s precedent. **Settled
facts:** do not name it `start_window_drag`; define it on exactly one class.

**Q5 — Does the `on_window_drop` ordering fix ship with the action?**
Open because A4 and V10 disagree and V10 has better evidence (§ 5.15). *Settled by:* deciding whether
the swap-on-bar gesture matters for our use case at all — under our config it is already unreachable,
and for a header-drag UX the directional insert is arguably more useful.

**Q6 — Does the patch try to suppress the force-show, and how?**
Open because suppression is **not reachable from the action** (§ 5.15) — it means editing shared drag
code or adding a struct field, which is a behaviour change to an existing path and a much harder ask
than a new action. *Settled by:* pricing what it buys (only a preview highlight, since the drop
decision already runs after the clear) against what it costs upstream.

**Q7 — Which band-scoping unit: 2 rows (the placement), 1 row (≈ the painted band), or pixels?**
Open: 2 over-covers the visible bar by 28 px, 1 under-covers by 17 px, pixels are exact but need Q2 to
resolve first. And the *number* must get from the overlay daemon (which computes `band_cells()` per
pane from `TIOCGWINSZ`) into a **static integer in `kitty.conf`** — they agree today at every cell size
but the coupling is **silent**, the same class of silent coupling `tests/kitty-title-zero-shift.bats`
was built to pin. *Settled by:* Q2, plus a decision about whether to pin the coupling with a test.

**Q8 — The `window_drag_tolerance` dead band: accept 19.4%, restore top padding, flip `draw_minimal_borders`, or lower the tolerance?**
Open because every remedy costs something the operator has already weighed (§ 7.4). *Settled by:*
an operator decision, informed by a live probe: an isolated kitty with two stacked panes,
`--debug-input`, pressing at successive y offsets from a pane's top edge and reading the
`window border:` versus `grabbed:` lines. **Note the 12 px is derived, not observed.**

**Q9 — Does a real hand drag from our band work end to end?**
Open and it is the **one thing nobody could test** — it needs a genuine left-button press inside a
sandbox window and real pointer motion; synthesising it moves the operator's real cursor. *Settled by:*
~60 seconds of operator time — in a sandbox instance, `mouse_map cmd+left press grabbed,ungrabbed
kitten begin_drag.py` with the kitten gated on `cell_y == 0`, then a chord-press on a pane's top row
and a drag. **Success = the pane's thumbnail follows the cursor and the pane re-orders on release.**
A second, related unknown it also settles: whether threshold-less behaviour is objectionable in use.

**Q10 — Does the graphics placement survive the drag's relayout?**
Open: `start_window_drag` relayouts every tab, which resizes PTYs, which makes children redraw, and the
overlay's own docstring says kitty frees a placement *"whenever its anchoring cells are cleared or
scrolled away"* (`scripts/kitty-pane-title-overlay.py:25-28`). If it does not survive, the overlay
vanishes mid-drag and the 2 s refresh loop repaints it afterwards — cosmetic, but it should be known
before it arrives as a bug report. *Settled by:* a synthetic drag in an isolated instance with the
overlay up, screenshotting mid-drag.

**Q11 — Does Claude Code bind any ⌘-modified mouse press?**
Open: its SGR encoding carries the modifier bits, so it *could*, and a string grep for `?1000h` cannot
answer it. *Settled by:* running Claude Code in a scratch kitty with no such `mouse_map` and pressing
⌘-left in the composer, or reading the bundle's mouse-event dispatch.

**Q12 — Which chord, and is losing `cmd+left click → mouse_handle_click link` acceptable?**
Open because `cmd+left press` is the best chord on every other axis and silently kills that binding
(§ 3.5 #7). *Settled by:* the operator, or by choosing `cmd+shift+left press` instead.

**Q13 — If band-scoping is required, does that alone decide against route A?**
Open and **nearly settled**: measured, `Boss.kitten` discards its return value, so a config-only
handler **always consumes** the press and cannot pass an out-of-region press through to the program
(§ 3.4). *Settled by:* deciding whether an unscoped chord is acceptable. If it is not, route A is
scope-capable only in the degenerate sense of "arm or do nothing, but always swallow".

**Q14 — Is the buttonless-promotion hazard worth an upstream report on its own?**
Open: the motion path has no button-held test in either ref, so any leaked `window_being_dragged`
escalates to a real system DND with nothing held. It is pre-existing and currently unreachable (the
flag can only be set from a path whose release clears it) — a content-press action is what makes it
reachable. *Settled by:* an upstream judgement call; it strengthens the case for the guards in § 4.5.

**Q15 — Does the `Tab*`-realloc hazard need a note or a guard in the patch?**
Open: `handle_button_event` holds `Tab *t` across the synchronous Python dispatch and dereferences it
after, while `add_tab` reallocs (§ 4.5). It is pre-existing and in both refs. *Settled by:* deciding
whether to mention it in the PR (it is adjacent evidence that the action must stay minimal) or file it
separately.

**Q16 — Patch master, build 0.48.2 locally, or both?**
Open, and **both is cheap** — each build is ~30 s in its own tree, and a patched 0.48.2 is a drop-in
comparison against the operator's daily driver while master is what an upstream PR must target.
*Settled by:* a plan decision. **Constraint:** a test file written against master will not import on
0.48.2 (`kitty_tests/base.py` is master-only), so do **not** verify the patch by running it under
`/Applications/kitty.app`.

**Q17 — Is a test that stops one call short of the OS acceptable upstream?**
Open. Precedent is strong but is a precedent, not policy: `selection_drag.py:221` patches
`kitty.window.start_drag_with_data` and `tab_drop.py:346` patches `kitty.tabs.set_window_being_dragged`
outright. *Settled by:* the PR review. **Related sub-question:** should the patch propose a
`in_test_mode` hatch on `start_drag_with_data`, mirroring the one its sibling already has
(`glfw.c:3619`)? The corpus warns against it — it is scope the feature does not need and it risks the
PR being judged on the wrong diff.

**Q18 — Rebuild and commit the `draghold` CGEvent driver?**
Open: it is the only automated route to the mouse leg and it no longer exists (§ 6.4). *Settled by:*
a plan decision. If yes, **record the invocation, not just the result** — that is the exact failure the
overlay doc's own §J warns about.

**Q19 — Fix the record before anything is posted or landed?**
Three concrete corrections are pending: the `7 → 41` `win`-action count in the upstream draft
(`:139-142`), the `ctrl+alt+left press` example chord (`:89`), and the *"can never be dragged, however
it is drawn"* clause at `config/kitty.conf:335-323` (§ 5.20 — **mark it refuted in place, never
delete; it is the record of what was believed**). Also `config/kitty.conf:541-511`'s render-data
mechanism claim (§ 2.3) and A10's own `1432`/`1433` citation error (§ 5.23). *Settled by:* doing it.

**Q20 — Does the 0.48.2 three-site drop-classifier offset defect warrant an upstream backport report?**
Open: it is inert on this box at the shipped default `tab_bar_edge bottom`, but it stops being inert
during a drag under `tab_bar_edge top` (§ 5.9), and the master fix is two deleted lines that will not
suffice as a backport. Nobody searched the tracker for it. *Settled by:* a search of kitty issues for
the commit that introduced `rel_x, rel_y = x, y`.

**Q21 — Is `window_title_bar_min_windows 1` a better design than the whole feature?**
Open and deliberately not priced: at `min_w > 0 and visible >= min_w` the force-show is skipped
entirely, so the drag costs no row — but that is precisely the ⌘⌥B ON state this feature would delete,
and it means permanently visible monospace bars. *Settled by:* an operator judgement, which has gone
against it twice already.

**Q22 — Does the maintainer want the action to force-show bars?**
Open: his 2026-03-05 wording **couples** them (*"a mappable action that when triggered shows the title
bars and then auto hides them after the drag operation is completed"*), which is suggestive but is not
a decision about *this* action. *Settled by:* the PR review.

**Q23 — Does the docs build pass with the proposed docstring?**
Open: `ac_role.warn_dangling = True` and `-n` is unconditional; every role target was verified to
exist, but `make docs` was never run. *Settled by:* `make docs` in the clone.

**Q24 — Does `combine`'s `drain_actions` timer break a `combine`-based design?**
Open: any non-first action of a `combine` runs on a zero-delay timer **after** the GLFW callback
returned, at which point `global_state.callback_os_window` is NULL and the press's pixel position is
gone (§ 4.5 guard 4). *Settled by:* deciding that the action must never be used as a non-first element
of a `combine`, and saying so in the doc text — or by taking the coordinates from the window rather
than the callback.

---

## 9. SOURCES

**Artifacts** (all under
`/private/tmp/claude-501/-private-tmp-wt-kitty-overlay/8294ff72-2d70-4ad2-86b9-33bc226c6f0e/scratchpad/research/`):

| file | axis |
|---|---|
| `A1-dispatch.md` | `mouse_map` → action dispatch, end to end |
| `A1-SKEPTIC-pixel-gap.md` | adversarial review of A1's "single missing getter" claim |
| `A2-c-routing.md` | C routing of an in-flight window drag |
| `A3-drag-start.md` | the window-drag start sequence and its preconditions |
| `A4-drop-side.md` | does a content-press drag land correctly |
| `A5-macos-appkit.md` | AppKit drag-session constraints |
| `A6-action-registration.md` | registration, documentation, mouse-bindability |
| `A7-build.md` | building kitty from source on this box |
| `A8-tests.md` | can the drag be tested without a hand |
| `A9-upstream-conventions.md` | what an acceptable upstream patch looks like |
| `A10-our-integration.md` | our chords, config delta, band scoping |
| `A11-existing-escape-hatch.md` | **adversarial: is a patch even necessary** |
| `A12-api-design.md` | name, signature, semantics, doc text |
| `_VERDICTS.md` | 32 adversarial verdicts (V1–V32) over the load-bearing claims |

**Refs:**

- kitty **master** `1d67ecd47c0bd68951868c363baa92039d936572` (2026-09-16), shallow depth 1 — no
  blame, no bisect, no `git log -S` available in that tree.
- kitty **v0.48.2** `2cb1d95c3accadd536bd66ba6bda044973440177`, `git describe` → `v0.48.2`. Also
  shallow.
- The **installed frozen build** `/Applications/kitty.app/Contents/MacOS/kitty` (self-reports `0.48.2`;
  `kitty.__file__` under `python-lib.bypy.frozen`), which is what the operator's live instance
  (pid 97084) runs.
- Our repo `/private/tmp/wt-kitty-overlay` @ `feat/kitty-title-overlay`, HEAD `a49280bd9`
  (*"fix(kitty): the top margin was a reservoir bought for the wrong chord"*).

**Companion documents in this repo:**

- `config/kitty.conf` §§ 3 and 3b — the full measurement record, including two claims refuted within
  hours of being written.
- `docs/research/kitty-upstream-drag-action-2026-09-16.md` — the upstream feature-request draft
  (unposted; three corrections pending, § 8 Q19).
- `docs/research/kitty-pane-title-overlay-2026-09-14.md` — the overlay mechanism (§ G), and §§ I7/I9,
  where the "a synthetic CGEvent stream cannot begin an NSDraggingSession" claim was made and then
  withdrawn.

**Date:** 2026-09-16.

---

## 10. Critic pass

**Date:** 2026-09-16, after § 9. Appended, nothing above renumbered or edited. This is the last read
before a fresh session plans on this file. Everything below was measured this session against the two
clones, the shipped binary, and our own repo — no claim here is carried over from an artifact.

### 10.1 What was checked, and what held

**Thirty-one `file:line` citations were opened at the cited line in the named ref.** All of the
following say exactly what the document says they say, in both refs where two are cited:

- **Arm 7**, the whole mechanism: `} else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {`
  at master mouse.c:1427 and v0.48.2 mouse.c:1362 — byte-identical, as claimed.
- **The full gate/arm table of § 2.1**, every row, both columns: master 1317/1330/1347/1371/1405/1416/1418/1423/1427/1433/1463/1473
  and v 1264/1273/1283/1308/1341/1352/1354/1358/1362/1370/1389/1392-1400. The v-only fifth arm at
  v:1392 does require `osw->mouse_button_pressed[button]`, as the row implies.
- **The struct and its accessors**: master state.h:657-661 + state.c:1996-2008; v state.h:531-534 +
  state.c:1762-1774. `"|Kpdd"`, all four args optional, `zero_at_ptr` first — verbatim.
- **The C wrapper**: master mouse.c:961-967, v mouse.c:930-938, differing only by a line wrap.
- **The exhaustive "no C-side clear"**: `grep window_being_dragged` over `kitty/*.c kitty/*.h` in both
  trees returns exactly the sites § 2.3 fact 4 names — master mouse.c:964, 1427, 1430; v mouse.c:933,
  1362, 1365-1366 — all `.id`, plus the setter/getter and the declaration. Nothing else. The positive
  control (`zero_at_ptr(&global_state.tab_being_dragged)`, master :981 / v :951) is present, so the
  null is informative.
- **Every tabs.py line in § 2.2's five-stage table and § 2.2's six-row clear table**: master
  2009/2013/2014/2015/2019/2021/2025/2026/2029/2030/2031/2036/2040/2052-2053/2057/2059/2060/2062 and
  v 1856/1859/1860/1861/1862/1866/1868/1872/1873/1877/1878/1883/1887/1904/1906/1909. Not one is off.
- **`kitty/actions.py`**: :49 `first = lines.pop(0)`, :53 `raise KeyError(f'Unknown action type: ...')`,
  :57 `for cls in (Window, Tab, Boss):`. § 4.2 row 1 and § 4.6's two crash modes are exact.
- **`MouseEvent`** carries `(button, mods, repeat_count, grabbed)` and nothing else — v types.py:115-119,
  master :121-125. **`dispatch_mouse_event`** passes no coordinates and computes
  `handled = callback_ret == Py_True` at master mouse.c:224. Both exact.
- **`Boss.kitten` genuinely discards the return** — v boss.py:2405-2406 / master :2669-2671 is a bare
  `self.run_kitten_with_metadata(...)` with no `return`. § 3.4's "cannot decline a press" is confirmed
  by source, not only by measurement.
- **`no_ui`** at v boss.py:2325-2326 / master :2584-2585; **`kittens/runner.py:65`** is the bare
  `g['main']` subscript; **`:97`** is the `no_ui` read. § 3.1's `main()` requirement is structural.
- **`ctrl+alt+left press ungrabbed mouse_selection rectangle`** at v definition.py:1285 / master :1320.
- **`handle_potential_drag`** master mouse.c:667 with the `OPT(drag_threshold) <= 0` guard at :668 and
  `clear_click_queue` at :660; **`closest_window_for_event`** at v mouse.c:1099/:1394 and **absent from
  master entirely** (tree-wide grep, zero hits) — § 2.4 item 2's "master is not a superset" holds.
- **`parse_key_action`** master utils.py:1259-1269 / v :1172-1182, with the `raise KeyError` at
  master :1267 / v :1180; **`parse_mouse_map`**'s per-mode yield at v :1556-1561 with the
  `{grabbed, ungrabbed}` validation at :1557.
- **Our own repo**: `window_drag_tolerance 6` (:314), the refuted clause (:322-323), the render-data
  claim (:508-511), `map cmd+opt+b` (:552), `mouse_map cmd+left click … link` (:772), the two unscoped
  `mouse_map right press` lines (:182-183), `window_padding_width 0 5 0 5` (:1060),
  `draw_minimal_borders no` (:1133), `window_title_bar_min_windows 0` (:1196),
  `window_title_bar_align` (:1210), the commented-out `tab_bar_min_tabs 1` (:636). All eleven correct.

**§ 7.3's chord table was re-probed independently** on the shipped binary against the live loaded
config, with three positive controls, and reproduced exactly — including the two-mode split:

```
mousemap entries: 37                                   (§ 7.3 says 37)
  cmd+left press             ungrabbed=FREE                      grabbed=FREE
  cmd+left click  [POSCTRL]  ungrabbed=TAKEN(mouse_handle_click link)     grabbed=TAKEN(same)
  right press     [POSCTRL]  ungrabbed=TAKEN(pane menu launch)            grabbed=TAKEN(same)
  cmd+shift+left press       ungrabbed=FREE                      grabbed=FREE
  left press      [POSCTRL]  ungrabbed=TAKEN(mouse_selection normal)      grabbed=FREE
```

⚠️ **Instrument note for whoever re-runs it.** GLFW numbers the buttons **LEFT=0, RIGHT=1, MIDDLE=2**;
`mouse_button_map` in `kitty/options/utils.py:59` maps *names* to the `b1/b2/b3` **strings** and is not
the integer. My first pass used `left=1`, which is RIGHT — and it read `cmd+left press` as TAKEN by the
pane menu. The positive controls are the only reason that did not become a finding: `cmd+left click`
and `right press` both came back FREE, which is impossible given config:772 and :182. **A chord probe
without two known-TAKEN controls cannot tell a free chord from a mis-numbered button.**

**Verdict handling was audited.** All 32 verdicts (V1–V32) are cited somewhere in §§ 1–9, and every
`REFUTED` row I read in full (V1, V4, V5, V16, V17) is represented in § 5 as what it actually is — a
confirmation carrying a correction — with the boolean nowhere mistaken for a kill. § 5's framing
paragraph is correct and § 5.2/§ 5.3/§ 5.5 are faithful compressions of V1/V25/V4. **No inverted
verdict was found.** Two verdict *contents* were dropped; they are 10.3 and 10.5 below.

---

### 10.2 🚨 THE RISK NO ARTIFACT COVERED — landing route A's config line arms the operator's LIVE kitty by itself

**This is the most dangerous gap in the document and it is not in any of the twelve axes.** Every
isolation concern in § 6.3 is about the **dev build**: sockets, env vars, bundle identifiers. Nothing
anywhere asks what happens to the **operator's running instance** when route A's `mouse_map` line is
committed — and the answer is that it arms itself, fleet-wide, with no human in the loop.

**Measured this session, read-only:**

```
$ readlink ~/.config/kitty/kitty.conf
/Users/chrisren/Development/claude-infrastructure/config/kitty.conf      ← the SHARED CHECKOUT

$ ps -axo pid=,command= | grep __watch_conf__
97219 /Applications/kitty.app/Contents/MacOS/kitten __watch_conf__ 97084 100 \
      /etc/xdg/kitty/kitty.conf /Users/chrisren/.config/kitty/kitty.conf
```

That watcher is the operator's live kitty's own child (`97084` is its pid; `100` is the debounce in ms).
Its behaviour is settled by source, not inference:

| step | site | what it does |
|---|---|---|
| spawn | v `kitty/boss.py:1418-1421` | `if opts.auto_reload_config >= 0 … Popen([kitten_exe(), '__watch_conf__', pid, ms] + all_config_paths)` |
| default | v `kitty/options/definition.py:2927-2930` | `opt('auto_reload_config', '0.1', option_type='float')` — **0.1 s, and our config never overrides it** |
| resolve | v `tools/watch/api.go:86-91`, `:110` | `result.Add(safe_eval_symlinks(path))` — `filepath.EvalSymlinks` on the **whole** path, so `~/.config/kitty/kitty.conf` becomes the shared-checkout path |
| watch | v `tools/watch/api.go:133`, `:143-146` | watches `filepath.Dir(p)` — i.e. **`~/Development/claude-infrastructure/config/`** — top-level, 100 ms cooldown |
| act | v `tools/watch/api.go:223-225` | `unix.Kill(kitty_pid, unix.SIGUSR1)` → full config reload |

**So the operator's live 11–13-pane kitty is, right now, watching the directory that `deploy-live.sh`
fast-forwards.** A landed `mouse_map cmd+left press … kitten kitty-drag-window.py` becomes live in that
instance ~100 ms after the shared checkout advances. Route A's two worst failure modes — the **wedge**
(§ 3.5 #1) and the **buttonless system DND** (§ 3.5 #2) — therefore reach every Claude session on the
box at converge time, not at test time.

🚨 **And this repo's own tooling asserts the opposite, which is why nobody looked.** `bin/cc-kitty-reload`'s
header states as fact: *"kitty parses its config at startup and then never looks again. So every config
change was live on disk and inert on screen until the operator quit and relaunched the terminal."* That
premise is **refuted on this box** by the live watcher above. Its *measurement* (SIGUSR1 → 30 rows → 28
rows, 2026-09-15) is sound and its tool is still useful — it reaches an instance whose watcher died, one
started before the config file existed (definition.py:2936 makes that a real exclusion), or one with the
option disabled — but the causal sentence beside the measurement was never tested. Classic
*checker-population-rests-on-an-untested-belief*: the belief lives in a comment and nothing executes it.

**Consequences the plan must take, not optional:**

1. **Route A is not a "try it and see" change to `config/kitty.conf`.** Prototype it in a sandbox
   config dir (`KITTY_CONFIG_DIRECTORY`, § 6.3) exclusively. The line reaches `config/kitty.conf` only
   after Q9 is answered by a real hand drag.
2. **Order the landing.** A `mouse_map … kitten X.py` whose file is not yet in `config_dir` raises
   `FileNotFoundError` inside `import_kitten_main_module` (runner.py:59), which `Boss.combine` catches
   at master boss.py:2102-2106 into `show_error('Key action failed', …)` **and consumes the press** —
   i.e. an error overlay in the operator's live panes on every ⌘-left press until it is fixed. The
   kitten file must be deployed and verified present **before** the line that names it.
3. **Whatever the fix, do not rely on "a land is inert until someone reloads."** It is not, and even if
   the watcher were absent, `deploy-live` calls `cc-kitty-reload` every 600 s.
4. Either **refute cc-kitty-reload's header claim in place** (never delete — it is the record of what
   was believed) or re-measure it; leaving it is how the next session repeats this.

---

### 10.3 🚨 The press-instant origin ALREADY EXISTS on master — § 2.4 and § 4.4 both miss it

§ 4.4 frames the `drag_started=False` branch as needing *"the press-instant OS-window pixel position,
which no Python getter returns"*, and prices it as *"a new accessor in `kitty/state.c` plus its
`fast_data_types.pyi` stub."* The "no getter" half is true. The implied "the value does not exist" half
is **false on master**:

```
master kitty/state.h:552      double mouse_left_press_x, mouse_left_press_y;     ← in OSWindow
master kitty/glfw.c:681-686   global_state.callback_os_window->mouse_button_pressed[button] = …;
                              if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS) {
                                  window->mouse_left_press_x = window->mouse_x;
                                  window->mouse_left_press_y = window->mouse_y;
                              }
                              if (is_window_ready_for_callbacks()) mouse_event(button, mods, action);
master kitty/shaders.c:2583-2584   (its only current reader — a shader uniform)

v0.48.2: `grep -rn mouse_left_press kitty/ glfw/` → rc 1, ZERO hits.
```

Three properties make this load-bearing, all read off those lines:

- It is written **from `window->mouse_x`**, so it is the *same* framebuffer-pixel space
  `set_window_being_dragged` wants (the existing producer at master mouse.c:965 passes `osw->mouse_x`).
  No conversion, no origin mismatch — the trap V1 warns about for `global_x/global_y`.
- It is written at glfw.c:683-684, **three lines before** `mouse_event(...)` at :686. An action
  dispatched from that press therefore reads *this* press's origin, not a stale one.
- It is **master-only**. A patched-0.48.2 build (§ 6.2 proves both refs build; Q16 proposes both) does
  not have the field and would have to add it.

**What changes for the plan:** § 4.4's branch point is not "invent a capture mechanism vs. skip the
threshold." On master it is "expose a field that already exists" — two keys added to the very
`Py_BuildValue` § 4.4 already names, or a three-line getter — which makes the `drag_started=False`
branch materially cheaper than the document prices it and weakens the case for the
`drag_started=True` shortcut. **V4 flagged this explicitly** (*"VERSION DIFFERENCES THE ARTIFACT
MISSED: `OSWindow.mouse_left_press_x/y` exists only in master"*) and the synthesis dropped it. It also
belongs in § 2.4's "Real differences that touch this work" list, which currently has five items and
should have six.

*(Caveat, stated rather than hidden: the field is written on every LEFT press anywhere in the OS
window and is never cleared, so it is a "last left press" value, not a "current gesture" value. For an
action dispatched synchronously from the press that distinction cannot bite; for anything running on
`drain_actions`' timer — § 4.5 guard 4 — it can.)*

---

### 10.4 A claim in § 2.1 that is simply wrong: `set_mouse_position` is **not** v0.48.2-only

§ 2.1's dispatch chain contains the line:

> `v0.48.2 ONLY: if (!set_mouse_position(w,&a,&b)) return;  v:883  ← the padding swallow`

`set_mouse_position` has the identical early return in **master at mouse.c:917**:

```
master: 444 definition · 707 · 917 (handle_button_event) · 1207
v0.48.2: 446 definition · 673 · 883 (handle_button_event) · 1177
```

The *effect* differs (master's `clamp_to_window` at :1473 makes `cell_for_pos` succeed for a padding
press where 0.48.2's returns false) and § 2.4 item 2 states that correctly — but § 2.1, which is the
section the document tells implementers to write code from, asserts the **line** is absent from master.
It is not. Anyone reasoning "master cannot early-return here" will be wrong: master still returns before
`dispatch_mouse_event` whenever `set_mouse_position` fails with the clamp inactive (motion events, or
`contains_mouse(w)` false).

Two smaller mis-citations in the same block, both verified:

- `(focus switch to the pressed window)  master :875-877 region` — master's focus switch is at
  **:911**; :875-877 is **v0.48.2's**. The row is labelled master and carries v's numbers.
- § 3.5 #5 and § 4.5 guard 3 cite the `clear_click_queue` rationale comment as master mouse.c:672-675.
  The comment is **:673-675** and the cure call it prescribes is **:676**; :672 is `Screen *screen = …`.

---

### 10.5 § 6.5 inverts a verdict finding: `dnd_test_set_mouse_pos` is not a `drag_source` hook

§ 6.5 closes with:

> **Do NOT reach for the `dnd_test_*` family beyond `create/cleanup_fake_window`** — those thirteen
> hooks drive `w->drag_source`, the OSC protocol a *client program* uses, and share no state with
> `global_state.window_being_dragged`.

The count is right (13 `METHODB` entries, v dnd.c:2775-2787) and the warning is right for twelve of
them. It is **wrong for `dnd_test_set_mouse_pos`**, which touches no `drag_source` field at all:

```c
/* v0.48.2 kitty/dnd.c:2457-2468  (master :2778-2790, table entry :3128) */
dnd_test_set_mouse_pos(PyObject *self UNUSED, PyObject *args) {
    ...PyArg_ParseTuple(args, "Kiiii", &window_id, &cell_x, &cell_y, &pixel_x, &pixel_y)...
    w->mouse_pos.cell_x = …;  w->mouse_pos.cell_y = …;
    w->mouse_pos.global_x = pixel_x;  w->mouse_pos.global_y = pixel_y;
}
```

Both V1 and V16 identified it by name as the **Python-side writer of the pixel mouse position**, present
in the shipped 0.48.2 build. Those are exactly the fields a region predicate reads — § 5.17 recommends
`global_x/global_y` as *"the coordinate space a content-row band actually wants"*, and § 6.5's own
T-passthrough test (*"a region-restricted action that consumes when it should pass through is invisible
to the arming test"*) has no other headless way to place the pointer inside vs. outside the band.
**The document's blanket warning steers an implementer away from the one hook that makes its own
hardest test writable.** Narrow it to: *the twelve `drag_source`/OSC hooks are off-limits;
`dnd_test_set_mouse_pos` is the region-test lever.*

Related, from V16 and also dropped: a **third** route to a press-instant origin with no C change —
reconstruct it from `Window.geometry` + `cell_size_for_window` + `cell_x/cell_y/in_left_half_of_cell`,
which land in the same space as `osw->mouse_x` (window.py:1092-1105 → state.c:1199-1215 →
mouse.c:298-313). § 4.4's rejection of a cell-derived origin still **stands** and I did not find a way
around it — cell-centering reduces the worst case from one cell (45 px) to half a cell (22.5 px), still
4.5× a 5 px threshold — but the route should be named and rejected rather than absent, because it is the
first thing a reader will reinvent.

---

### 10.6 Three precision defects that each have a concrete failure mode

**(a) § 3.3 step 1 would make a kitten author write the wrong signature.** It says the `no_ui` handler
*"receives the window id as its second argument."* True of the internal call
(`handle_result(None, w.id if w else 0, self)`, boss.py:2326) — but `create_kitten_handler` wraps it as
`partial(handle_result, [kitten] + orig_args)` (runner.py:95), so the file the implementer writes has
kitty's documented four-parameter shape, window id **third**:

```python
# v0.48.2 docs/kittens/custom.rst:177-179
from kittens.tui.handler import result_handler
@result_handler(no_ui=True)
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Boss) -> None:
```

Writing `def handle_result(args, wid, boss)` raises `TypeError` at press time — which `Boss.combine`
turns into a popup on every press, not a visible stack trace. *(The substantive half of step 1 is
confirmed by source, not just by V27: `Window.on_mouse_event` passes `window_for_dispatch=self`
(window.py:1420) → `dispatch_action` sets `self.window_for_dispatch` (boss.py:2043) → `Boss.kitten`
forwards it as `window=` (boss.py:2671) → `run_kitten_with_metadata` takes `w = window` (boss.py:2314).
The id **is** the pointer's window, by construction.)*

**(b) § 2.1's trigger-count map is quoted incomplete.** The real map is

```python
# v0.48.2 kitty/options/utils.py:60
mouse_trigger_count_map = {'doubleclick': -3, 'click': -2, 'release': -1, 'press': 1,
                           'doublepress': 2, 'triplepress': 3}
```

The document drops `doublepress` and `triplepress`. That is not cosmetic here: `doublepress` is a
*press*-family trigger (positive count), so it fires synchronously like `press` and does **not** wait
for `click_interval` — which makes it a live candidate for Q12, since it would leave
`cmd+left click → mouse_handle_click link` (§ 3.5 #7) alive. I measured `cmd+left doublepress` **FREE in
both modes** in the loaded config. Not a recommendation — a deliberate chord probably wants one press —
but the plan should choose from the real vocabulary.

**(c) § 7.3's `ctrl+alt+left press` row is over-broad.** Measured: **TAKEN in `ungrabbed` only, FREE in
`grabbed`** (`mouse_selection rectangle` is declared `ungrabbed`, definition.py:1285). The document's
`⛔ TAKEN` and its advice to avoid it are unchanged and correct — a `grabbed,ungrabbed` binding still
collides on one of its two modes — but § 5.19's instruction to fix the upstream draft should say *which*
mode, or the next reader will find it free and reopen the question. Also cross-reference: § 3.2's last
bullet cites "(§ 5.7)" for the unparsed-string/no-validation claim; that content is in **§ 5.8**.

---

### 10.7 Uncovered: route A's kitten file has no deployment path in THIS repo, and three gates will refuse it

Route A needs a `.py` file in `kitty.constants.config_dir` (§ 3.2) — i.e. `~/.config/kitty/`. No artifact
asked how it gets there. In this repo it cannot simply be written:

- `~/.config/kitty/kitty.conf` is placed by **`scripts/kitty-setup.sh:211,220`** (`SRC_CONF="$REPO/config/kitty.conf"`;
  `ln -sfn "$SRC_CONF" "$KCONF_DIR/kitty.conf"`), a **second installer** that `install.sh:1349-1369`
  merely invokes. A kitten file needs its own `ln -sfn` line there, or it exists only in the repo.
- `tests/deploy-parity.bats` carries **four** arms that derive kitty-setup.sh's deployed set and fail on
  any repo source reaching the reasonless default — by literal source prefix (`:1611`), **by shape**
  (`:2178`), **by action** (`:2297`), plus the aggregate at `:2420`. A new linked source that is not
  simultaneously declared is a **red land gate**, not a warning.
- `scripts/deploy-parity-assert.sh` needs the matching arm; the precedent is its own
  `config/kitty.conf) want=0 ;;` at `:766`, with the reasoning block at `:722-766` explaining why a
  `$HOME/.config/kitty/…` destination must be `want=0` rather than `want=1`.

§ 7.1 already knows this wiring exists — it lists *"their `install.sh` and `scripts/deploy-parity-assert.sh`
wiring"* among what route B **retires**. The **add** side for route A is simply absent. Budget it: one
`ln -sfn`, one `deploy-parity-assert.sh` case arm, and a re-run of `tests/deploy-parity.bats`.

*(Checked and clear: no `.bats` file in this repo asserts anything about `mouse_map` lines or the
`cmd+left` chord — `grep -rn "mouse_map\|cmd+left" tests/*.bats` returns nothing — so adding the binding
reddens no existing chord test. `tests/kitty-conf-bindings.bats`' 30 tests pin `window_drag_tolerance`
(`:179`), `drag_threshold != 0` (`:319`) and the ⌘⇧B / ⌘⌥B role split (`:215`, `:576`, `:606`), all of
which § 7.1 already names.)*

---

### 10.8 Settled here, so the plan phase need not re-ask

| was open / unstated | settled |
|---|---|
| Does the `kitten` action even parse in a `mouse_map`? (all of route A rests on it) | **Yes.** `@func_with_args('run_kitten', 'run_simple_kitten', 'kitten')` at v `kitty/options/utils.py:120-125`. Route A's config line survives `parse_key_action`'s `raise KeyError` at :1180. |
| Is the press-instant pixel origin genuinely absent, so § 4.4's C branch means new capture? | **No — it exists on master** as `OSWindow.mouse_left_press_x/y`, unexposed. § 10.3. |
| Does a landed config change reach the operator's live kitty? | **Yes, in ~100 ms**, via a live `__watch_conf__` child watching the shared checkout. § 10.2. |
| Is `set_mouse_position`'s early return v0.48.2-only? | **No**, master mouse.c:917. § 10.4. |
| Is every `dnd_test_*` hook a `drag_source` hook? | **No**, `dnd_test_set_mouse_pos` writes `w->mouse_pos`. § 10.5. |
| Is `cmd+left press` really free? | **Yes, both modes** — reproduced independently with three positive controls and the correct GLFW button numbering. § 10.1. |
| Would a new `mouse_map` line redden an existing repo test? | **No** — no bats file asserts on `mouse_map`. But the kitten **file** trips three deployment gates. § 10.7. |

### 10.9 What remains open after this pass

1. **Q9 is still the gate, and § 10.2 raises its stakes.** It was already "the one thing nobody could
   test"; it is now also the thing that must be answered **in a sandbox config dir** before the line goes
   anywhere near `config/kitty.conf`.
2. **Q23 (`make docs`) is untouched** — it needs sphinx and a full docs build, outside this pass's
   read-only budget. Still cheap in the clone.
3. **Q11 (does Claude Code bind ⌘-modified mouse presses)** and **Q20 (upstream tracker search for the
   drop-classifier offset)** both need something this box cannot do read-only — a live Claude Code in a
   scratch kitty, and network access to the kitty tracker. Unchanged.
4. **Unmeasured and worth one probe each in phase 2:** whether the `__watch_conf__` reload is
   *partial* (does SIGUSR1 rebuild the mousemap, or only re-read options?) — it decides whether a bad
   `mouse_map` can be withdrawn without restarting the operator's kitty; and whether
   `dnd_test_set_mouse_pos` on a `dnd_test_create_fake_window` window is enough to drive a region
   predicate end to end, which is the difference between § 6.5's passthrough test existing and not.
5. **Not a gap, a caution:** § 2.3's "set at exactly one site (master tabs.py:2026)" is true of the
   *arming* write; the promotion at :2014 is a second `set_window_being_dragged` call. Both are reachable
   only through arm 7, so the emergent-invariant argument is unaffected — but a patch author grepping for
   writers will find two, and should not conclude the document is wrong.
