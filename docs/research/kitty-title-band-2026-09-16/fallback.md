# The no-restart fallback: how good can the CURRENT kitty instance get?

Axis: assume we may NOT restart the operator's kitty (pid 597) and therefore may NOT change C code.
Determine the best achievable ⌘⇧B under that constraint, and whether it is worth building as an interim.

All file:line citations are marked with the tree they were read in:
`482` = `~/kitty-482` @ `2cb1d95c3` (v0.48.2 — the build the operator actually runs);
`dev` = `~/kitty-dev` @ `1d67ecd47` (master/nightly-21).

**Status legend:** CONFIRMED (measured or read directly) · REFUTED · UNMEASURED.

---

## 0. Headline

**The fallback is better than the brief assumed, and the reason is one five-line fact:
`Window.padding` in the C layer is used in EXACTLY five places — its own setter, and the four
mouse hit-test edge functions. It touches NO rendering path at all.**

```
$ cd ~/kitty-482 && grep -rn "padding\.top\|padding\.left\|padding\.bottom\|padding\.right\|->padding" kitty/*.c kitty/*.h | grep -v "OPT("
kitty/state.c:1194:        window->padding.left = left; window->padding.top = top; window->padding.right = right; window->padding.bottom = bottom;
kitty/mouse.c:251:    return w->render_data.geometry.left - w->padding.left;
kitty/mouse.c:256:    return w->render_data.geometry.right + w->padding.right;
kitty/mouse.c:261:    return w->render_data.geometry.top - w->padding.top;
kitty/mouse.c:266:    return w->render_data.geometry.bottom + w->padding.bottom;
```
(482, exact command + exact output.)

That makes `set_window_padding` a **pure hit-test control surface, callable from Python**, which
the brief's arithmetic did not account for. It is the difference between "the fallback gets a/b/d
and cannot ever get c" and "the fallback may get a/b/c/d". Sections 1 and 3 establish and test it.

---

## 1. Can a kitten monkeypatch `Window.set_geometry` to give a zero-row band? — the mechanism

### 1.1 What `set_geometry` does today (482 `kitty/window.py:1050-1146`)

```python
1056:        show_tb = self.show_title_bar and new_geometry.ynum > 1
1058:        if show_tb:
1059:            render_ynum = new_geometry.ynum - 1          # <-- THE STOLEN ROW
1060:            cell_width, cell_height = cell_size_for_window(self.os_window_id)
1061:            if position == 'top':
1062:                render_top = new_geometry.top + cell_height   # <-- THE SHIFT
1063:                render_bottom = new_geometry.bottom
1064:                tb_top = new_geometry.top
1065:                tb_bottom = new_geometry.top + cell_height
```
then, unconditionally:
```python
1076:        if self.needs_layout or new_geometry.xnum != self.screen.columns or render_ynum != self.screen.lines:
1077:            self.screen.resize(max(0, render_ynum), max(0, new_geometry.xnum))
...
1080:        current_pty_size = (self.screen.lines, self.screen.columns, ..., max(0, render_bottom - render_top))
1082:        if current_pty_size != self.last_reported_pty_size:
1084:                update_ime_position = self.resize_child(current_pty_size)   # <-- SIGWINCH
```
and then two independent C calls:
```python
1093:        set_window_render_data(os_window_id, tab_id, id, self.screen,
                                   g.left, render_top, g.right, render_bottom, ...)   # content rect
1124:            set_window_title_bar_render_data(os_window_id, tab_id, id,
                                   self._title_bar_screen.screen,
                                   tb_geom.left, tb_geom.top, tb_geom.right, tb_geom.bottom)  # band rect
```

**These two rects are set independently and neither C setter validates the other.**
`set_window_title_bar_render_data` (482 `kitty/state.c:1006-1016`) is nine lines: it parses four
unsigned ints, calls `init_window_render_data`, sets `reload_all_gpu_data = true`. No clamping, no
overlap check, no relation to `render_data.geometry`.

### 1.2 The patch shape

A monkeypatch that, when `show_title_bar` is true, sets

| field | stock | patched |
|---|---|---|
| `render_ynum` | `ynum - 1` | `ynum`  (no row stolen) |
| `render_top`  | `top + cell_height` | `top`   (no shift) |
| `render_bottom` | `bottom` | `bottom` |
| `tb_top` / `tb_bottom` | `top` / `top + cell_height` | unchanged |

leaves `current_pty_size` identical to the no-title-bar case, so line 1082's comparison is FALSE
and `resize_child()` is never called ⇒ **no SIGWINCH, no PTY resize, no reflow**. The band rect is
still handed to C, so the bar still renders — now over content row 1 instead of above it.

### 1.3 Does the band actually cover the content? — draw order

Yes, and it is unconditional. 482 `kitty/child-monitor.c:906-919`, inside `render_prepared_os_window`:

```c
906:    for (unsigned int i = 0; i < tab->num_windows; i++) {
907:        Window *w = tab->windows + i;
908:        if (w->visible && WD.screen) {
...
911:            draw_cells(&WD, os_window, is_active_window, false, num_of_visible_windows == 1, w);   // CONTENT
913:            WindowRenderData *trd = &w->window_title_render_data;
914:            if (trd->screen && trd->geometry.right > trd->geometry.left && trd->geometry.bottom > trd->geometry.top)
915:                draw_cells(trd, os_window, i == tab->active_window, true, false, NULL);            // BAND
```
The band is drawn **after** the content, in the same pass, for the same window. `draw_cells`
(482 `kitty/shaders.c:1411-1451`) is a pure 2D quad draw into a viewport:
```c
1447:    save_viewport_using_top_left_origin(ui.screen_left, ui.screen_top, ui.screen_width, ui.screen_height, ui.full_framebuffer_height);
1448:    if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
1449:    else draw_cells_without_layers(&ui, srd->vao_idx);
1450:    restore_viewport();
```
and `save_viewport_using_top_left_origin` (482 `kitty/gl.c:164-174`) is a bare `glViewport` — no
depth test involved, no scissor. Later draw wins inside the overlapping rect. The band's own
background is opaque (`WindowTitleBarScreen` sets `default_bg` from
`window_title_bar_*_background`, 482 `kitty/window_title_bar.py:135-145`), so row 1 is fully
painted over, not blended.

The GPU-upload guard at 482 `kitty/child-monitor.c:851-856` uses the identical non-empty-rect
predicate, so the band's cell data is uploaded on the same condition it is drawn on.

**CONFIRMED by source. Empirical confirmation in §2.**

### 1.4 Is `set_geometry` reachable from a kitten in a RUNNING kitty?

`set_geometry` is a plain method on `kitty.window.Window` (482 `kitty/window.py:1050`), called from
the layout code as `w.set_geometry(...)`. A kitten running with `--type=background` executes in the
kitty process's own Python (`kitty.boss` is importable), so
`kitty.window.Window.set_geometry = patched` rebinds it for every existing and future Window
object — the call site resolves the attribute on the class at call time. No C symbol is touched.

The remaining question is whether anything C-side caches or re-derives `render_ynum` — it does not:
`screen.resize()` is the only thing that changes `screen->lines`, and it is called from this same
Python function.

---

## 2. MEASURED: the zero-row band works in a running instance — CONFIRMED

### 2.1 Rig

Sandbox kitty 0.48.2 from the same `/Applications/kitty.app` the operator runs, launched with an
isolated socket and an isolated instance group so it can never touch pid 597:

```
env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID nohup \
  /Applications/kitty.app/Contents/MacOS/kitty \
  --config /private/tmp/ktb-fallback/sandbox.conf \
  --listen-on unix:/private/tmp/ktb-fallback/sock \
  --instance-group ktbfallback -o allow_remote_control=yes --title KTB-FALLBACK-SANDBOX &
```
`sandbox.conf` mirrors the live config on every value that matters here (Monaco 18,
`modify_font cell_height 94%`, `window_padding_width 0 5 0 5`,
`window_title_bar_min_windows 0`, `window_title_bar_align left`, the four title-bar colours,
`window_border_width 1pt`, `draw_minimal_borders no`, `placement_strategy top`,
`window_drag_tolerance 6`).

Two panes (hsplit). Pane A runs a **SIGWINCH-trapping bash** (`/private/tmp/ktb-fallback/winch.sh`)
that appends `rows`/`cols` on every WINCH, so a PTY resize cannot happen silently.

### 2.2 How the patch is injected into a RUNNING kitty — CONFIRMED

**A `--watcher` module is arbitrary in-process Python.** 482 `kitty/launch.py:520-542`:
`runpy.run_path(path, run_name='__kitty_watcher__')` at module scope, then `on_load(boss, {})`.

```
kitty @ --to unix:… launch --type=overlay --watcher /private/tmp/ktb-fallback/patch_v1.py sh -c 'sleep 0.5'
```
→ `/private/tmp/ktb-fallback/patch.log` contains `PATCHED OK` / `relayout done`.

**NEGATIVE, measured:** `launch --type=background --watcher …` returns a window id but **never runs
the watcher** (no `patch.log` written). A background launch creates no Window, so `load_watch_modules`
is not reached. The injection must be `--type=overlay` (or any real-window type). This matters
because the existing ⌘⇧B binding uses `--type=background`.

Caching caveat, from the same source: `watcher_modules[path]` memoises by path (482
`kitty/launch.py:523,533`), so re-loading the SAME path is a no-op. Use a fresh path per revision.

### 2.3 The four-step measurement

| step | state | `kitty @ ls` lines (win1/win2) | SIGWINCH in pane A |
|---|---|---|---|
| 0 | baseline, bars OFF (`min_windows 0`) | 11 / 11 | — (start rows=11) |
| 1 | **stock** bars ON (`min_windows 1`) | **10 / 10** | **WINCH 1 rows=10** |
| 2 | back to OFF | 11 / 11 | WINCH 2 rows=11 |
| 3 | inject `patch_v1.py` | 11 / 11 | none |
| 4 | **patched** bars ON (`min_windows 1`) | **11 / 11** | **NONE** |

Raw `winch-A.log` after step 4:
```
PANE A start rows=11 cols=71
WINCH 1 rows=10 cols=71 at 17:53:00.374622000     <- step 1, stock
WINCH 2 rows=11 cols=71 at 17:53:06.635675000     <- step 2, back to off
                                                   <- step 4 produced NOTHING
```

**Step 1 is the positive control**: the same config swap, on the same rig, in the same session,
does cost a row and does fire SIGWINCH when the patch is absent. So step 4's silence is the
patch working, not the instrument being dead.

### 2.4 The bar is actually DRAWN — screenshot, not inference

`screencapture -x -o -l1462 shot-patched-ON.png` (the sandbox OS window's `platform_window_id`
from `kitty @ ls`). Both panes carry a full-width blue `#2f62d8` band with white text
(`chrisren@MacBookPro:/private/tmp/ktb-fallback`, `winch.sh`) at their very top, and the content
below is unshifted: pane 1's screen still holds 11 lines (`kitty @ get-text --extent=screen`
returns `ROW2…ROW11` + prompt), with `ROW2` **behind** the band rather than pushed down.

So: **the band covers content row 1 instead of displacing it, in a running instance, from Python
alone.** Requirement (a) — no top margin, no content layout shift — is **CONFIRMED MET.**

---

## 3. Requirement (b) — does the band scroll? — CONFIRMED IT DOES NOT

The band is not an annotation on the content screen; it is its **own `Screen` object**, one line
tall, **scrollback 0**, created at 482 `kitty/window_title_bar.py:120-127`:
```python
120:class WindowTitleBarScreen:
122:        self.screen = Screen(None, 1, 10, 0, cell_width, cell_height)   # lines=1, cols=10, scrollback=0
123:        self.screen.reset_mode(DECAWM)
125:    def layout(self, geometry):
126:        ncells = max(4, (geometry.right - geometry.left) // self.cell_width)
127:        self.screen.resize(1, ncells)
```
It is uploaded and drawn from its own `vao_idx` at its own fixed pixel rect every frame
(482 `kitty/child-monitor.c:851-856` upload, `:913-915` draw). Nothing in the content screen's
scroll path can reach it: no cell anchoring, no graphics placement, no id to free.

**MEASURED.** With the patch live and bars ON, pane 1 was driven through every case that kills the
current graphics-protocol overlay:

| stress | result |
|---|---|
| 400 lines of fast output (continuous scroll) | band fixed at pane top, mid-stream capture |
| `clear` (screen clear — the thing that frees a graphics placement) | band unaffected |
| 60 more lines after the clear | band unaffected |
| `kitty @ scroll-window --match id:1 20-` (into scrollback) | **band still at pane top, unmoved** |

`shot-scrollback.png` shows the scrollbar indicator engaged (we are 20 lines back in history),
`AFTERCLEAR-32…41` in the viewport, and the blue band pinned at row 1 of each of the two panes.

**No re-assert timer is involved** — there is nothing to re-assert. This is the single biggest
qualitative win over the ⌘⌥B graphics overlay, which the repo record documents as blinking and
moving because kitty frees its placement on clear/scroll and a 2 s daemon re-sends it.

### 3.1 Pixel proof of (a): the ONLY thing that changes is one cell-tall band

Static content in both panes; three captures of the same OS window
(`screencapture -x -o -l1462`): patched-ON → OFF → ON again.

```
ON vs OFF changed row runs: [(58, 102), (558, 602)]
ON vs ON2 (idempotence) changed row runs: []
```
Two runs, each **45 rows tall = exactly one cell** (the live cell is 45 device px), one per pane,
at each pane's row 1. **Every other pixel in the 1600×1056 frame is byte-identical.** The content
did not move by one pixel, and two OFF→ON swaps are perfectly idempotent (no creep, unlike the
`23pt`-vs-`22.5pt` 1 px creep the reservoir route has recorded in `config/kitty-title-on.conf`).

And across all of steps 3→4 and the three swaps here, pane A's SIGWINCH log gained **no new entry**.

---

## 4. Requirement (c) part 1 — the hit test. The brief's refutation is right, AND it is escapable

### 4.1 The naive patch does kill the hand cursor — CONFIRMED BY SOURCE, with real numbers

482 `kitty/mouse.c:1067-1081`, `mouse_region()`:
```c
1067:        for (unsigned int i = 0; i < t->num_windows; i++) {
1068:            Window *win = t->windows + i;
1069:            if (contains_mouse(win) && win->render_data.screen) {
1070:                ans.window_idx = i; ans.window = win; break;
1071:            } else if (detect_title_bar && win->visible) {
1072:                const WindowRenderData *trd = &win->window_title_render_data;
1073:                if (trd->screen && trd->geometry.right > trd->geometry.left && trd->geometry.bottom > trd->geometry.top) {
1074:                    if (w->mouse_x >= trd->geometry.left && w->mouse_x < trd->geometry.right &&
1075:                            w->mouse_y >= trd->geometry.top && w->mouse_y < trd->geometry.bottom) {
1076:                        ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
```
and 482 `kitty/mouse.c:250-273`:
```c
250: window_left(Window *w)   { return w->render_data.geometry.left   - w->padding.left;   }
256: window_right(Window *w)  { return w->render_data.geometry.right  + w->padding.right;  }
260: window_top(Window *w)    { return w->render_data.geometry.top    - w->padding.top;    }
265: window_bottom(Window *w) { return w->render_data.geometry.bottom + w->padding.bottom; }
272: contains_mouse(Window *w){ return w->visible && window_left(w) <= x && x < window_right(w)
                                       && window_top(w) <= y && y < window_bottom(w); }
```

Real numbers from the patched sandbox (logged from inside kitty via a probe watcher):
```
win 1 show_tb=True g.top=2   g.bottom=497 g.ynum=11 screen.lines=11 cell_h=45 eff_pad_top=0
      band=[2,47)    contains_mouse_top_stock=2
win 2 show_tb=True g.top=502 g.bottom=997 g.ynum=11 screen.lines=11 cell_h=45 eff_pad_top=0
      band=[502,547) contains_mouse_top_stock=502
```
(That log also independently CONFIRMS the zero-row claim from kitty's own objects:
`g.ynum == screen.lines == 11` with `show_tb=True`.)

Band = `[2,47)`; `contains_mouse` top = `2`. The band is strictly inside the content rect, so line
1069 wins and line 1071's `else if` is **never evaluated for that window**. No `in_title_bar`, so:
no `POINTER_POINTER` (482 `mouse.c:1133-1134`), no routing to `handle_window_title_bar_mouse`
(482 `mouse.c:1362`). **The brief's claim is CONFIRMED for the naive patch.**

### 4.2 …but the two rects are NOT the same field. `padding` is a Python-settable hit-test inset

The headline grep (§0) is the whole argument: `window->padding` is written by exactly one function
and read by exactly four, and all four are the mouse edge functions. **No render path reads it.**
Set

```
padding.top := effective_padding('top') − cell_height
```

and `window_top(w)` returns `g.top + cell_height` — the band's bottom edge — by ordinary unsigned
arithmetic (`padding` is `unsigned int`, 482 `kitty/state.h:270-272`; the setter parses `"IIII"`,
482 `kitty/state.c:1189-1197`, and CPython's `I` converts **without overflow checking**, so
Python's `-45` arrives as `4294967251` and `top − 4294967251 ≡ top + 45 (mod 2^32)`).

The band is then *outside* `contains_mouse`, line 1069 fails, and line 1071's title-bar arm is
reached — for exactly the one cell-tall strip, with the rest of the pane hit-tested as before.

### 4.3 MEASURED: the underflowed padding is accepted and is invisible to rendering

`patch_v2.py` (the §2 patch plus the padding push) injected into the same running sandbox:

```
--- patch2.log ---
PATCHED OK
padding pushed top= -45          (× once per window per relayout)
relayout done
```
Screenshots of the same OS window immediately before and after injection, static content:
```
changed pixels: 0 of 1689600
```
**Zero.** `kitty @ ls` still 11/11 lines; SIGWINCH log gained nothing; kitty's stderr stayed empty.

So: the C layer accepts the value, and — as the 5-site grep predicted and this now confirms
empirically — **it changes nothing that is drawn.** The computed effect is
`contains_mouse_top: 2 → 47` and `502 → 547`, i.e. exactly the two bands excluded.

### 4.4 🚨 UNMEASURED: the pointer itself

**I did not verify that the cursor actually becomes a hand, and I did not verify that a press in
the band starts a drag.** Both need a real pointer inside the sandbox window.

Why not measured, explicitly: this box has no `cliclick` and no `Quartz`/pyobjc, so synthetic
events would mean installing pyobjc and posting CG events — which either warps the operator's
physical cursor across his live 9-session desktop or raises a TCC Accessibility dialog on it.
The repo's own corpus already records a research probe (`kitty @ action test_dragging`) whose
"read-only" verification wrote a payload into a live Claude composer and deferred a succession.
I am not repeating that class of mistake for a claim the source already determines.

**The 10-second human test**, in the sandbox (still running as of writing), is:
hover the mouse over the top 45 px of either pane and look at the cursor; then press-drag it onto
the other pane and release. Expected under `patch_v2.py`: hand cursor, drag thumbnail, panes swap.

Everything *downstream* of `in_title_bar` is unchanged stock code, all of it Python-visible and
read: 482 `mouse.c:1133` (`POINTER_POINTER`), `mouse.c:1362` (routing, which also catches the
release anywhere via `|| global_state.window_being_dragged.id`), 482 `tabs.py:1853-1881`
(`handle_window_title_bar_mouse` → `set_window_being_dragged` → `start_window_drag`), and the drop
target at 482 `tabs.py:2064-2075`, which computes the band as `tb_top, tb_bottom = g.top, g.top + ch`
— **identical to where the patch leaves it**, so a title-bar drop still means "swap positions".

### 4.5 The no-op-drag requirement — CONFIRMED BY SOURCE

`show_title_bar` is computed at 482 `kitty/layout/base.py:409-415`:
```python
412:        show_title_bar = force_show or (min_windows > 0 and len(visible_groups) >= min_windows)
```
and the post-drag cleanup at 482 `kitty/tabs.py:1918-1926` clears **only** `tab.force_show_title_bars`.
So a bar held up by `window_title_bar_min_windows >= 1` survives a no-op drag — the same property
the brief already credits the ⌘⌥B route with, inherited unchanged.

One free bonus: `start_window_drag` (482 `tabs.py:1882-1893`) sets `force_show_title_bars = True`
and **relayouts every tab** while a drag is in flight. Stock, that is a one-row shift on every pane
in the OS window at drag start. Under this patch that relayout costs zero rows and zero SIGWINCH.

---

## 5. Brief item 4 — the mouse_map/kitten drag route, if §4.2 is rejected

If the padding trick is judged too clever to ship, the drag half still has the sibling session's
route: a `mouse_map` chord invoking `scripts/kitty-drag-window.py` (present in the shared checkout
at 37,942 bytes, and in `.worktrees/kitty-drag-impl`), which drives the same Python state machine.

**It is reachable on the live 0.48.2 without any C change** — CONFIRMED by source:
`set_window_being_dragged` / `get_window_being_dragged` are module-level Python functions in
`fast_data_types` (482 `kitty/state.c:1764-1771`, registered at `:1804-1805`), and `Tab`/`TabManager`
already call them (482 `kitty/tabs.py:36,52,1856-1877`).

**Wedge risk is LOW**, and the reason is in the routing line rather than in the kitten:
482 `kitty/mouse.c:1362` reads
```c
} else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
```
Once `window_being_dragged.id` is non-zero, **every** subsequent mouse event in the OS window
routes to `handle_window_title_bar_mouse`, and a left-button RELEASE there unconditionally calls
`set_window_being_dragged()` with no arguments, i.e. clears it (482 `tabs.py:1876-1877`). So the
state cannot outlive the next left-button release. The residual wedge is a drag armed and then
never released (mouse leaves the window and the button is released outside) — recoverable by any
later left click.

**Free chord:** `config/kitty.conf` records ⌘⌥ as used only by the arrows, `o` and `shift+o`, so
`cmd+alt+<letter>` space is open; a `mouse_map` is a separate namespace again. UNMEASURED — I did
not enumerate the live `mouse_map` table.

**But it is strictly worse than §4.2 for this goal**, for a reason that is about the requirement,
not the implementation: requirement (c) asks for a **mouse hand on hover**. A chord cannot produce
a hover affordance. `mouse_cursor_shape` is set only from `mouse_region()`'s verdict
(482 `mouse.c:1127-1144`), which is the very arm a chord bypasses. So the chord route can deliver
the *drag* and can never deliver the *hand*.

---

## 6. Requirement (d) — the font. NOT met, and the lead's placement idea is structurally blocked

### 6.1 The band's text is the cell font

The band is a `Screen` drawn by the cell program, so it renders in Monaco, at the cell metrics.
Visible in every screenshot: the band text is the same face as the content. **(d) is NOT met.**

### 6.2 Can a graphics placement be written INTO the title-bar Screen? — the route is blocked

The lead's idea is mechanically *reachable*: the band's `Screen` is a live Python object
(`window._title_bar_screen.screen`), and 482 `kitty/screen.c:6324-6326` exposes
`test_create_write_buffer` / `test_commit_write_buffer` / `test_parse_written_data`, which
kitty's own test suite composes into `parse_bytes(screen, data)` (482 `kitty_tests/__init__.py:30-36`).
I used exactly that to feed a kitty graphics APC into both panes' band screens, in the running
instance, successfully (no exception, no kitty stderr).

**Result: the placement is accepted and consumes the band's cells, and NO image is drawn.**
Screenshot `gfx-after.png`: each band now shows its text, then a **black rectangle exactly as wide
as the transmitted image** (300 px), then the remaining blue. The band is visibly corrupted and
carries no picture. kitty's stderr printed
`UNSUPPORTED (log once): … unit 0 GLD_TEXTURE_INDEX_2D is unloadable … using zero texture`.

**The structural reason, CONFIRMED BY SOURCE — this is the part that matters even if my probe was
imperfect.** Graphics are drawn only by the layered path:
```c
1345: draw_cells_without_layers(const UIRenderData *ui, ssize_t vao_idx) {
1346:     call_cell_program(CELL_PROGRAM, ui, vao_idx, true, DRAW_BOTH_BG);      // cells ONLY
1347: }
1358: draw_cells_with_layers(...) { ... draw_graphics(GRAPHICS_PROGRAM, ui->grd.images, ...) ... }
1448:     if (ui.os_window->needs_layers) draw_cells_with_layers(...); else draw_cells_without_layers(...);
```
(482 `kitty/shaders.c`.) And `os_window->needs_layers` is ORed from the tab-bar screen
(482 `child-monitor.c:770`) and from every **content** screen (`:786`) — **never from a title-bar
screen's graphics manager.** So an image living only in a band cannot switch on the path that would
draw it. It renders if and only if something *else* in that OS window has already forced layers
(another pane holding an image, a scrollbar, a progress bar, a hyperlink target, a window logo,
a background image, or `background_opacity < 1` — 482 `shaders.c:1316-1320`, `child-monitor.c:757`).
A feature whose visibility depends on an unrelated pane's scrollbar is not shippable.

### 6.3 🚨 My empirical follow-up was INVALID — reported rather than buried

I re-ran the probe with `background_opacity 0.99` to force `needs_layers`, and the band stayed
black. That reading is **worthless**, because in the same run I fed the identical single-chunk
RGBA image into a normal **content** screen as a positive control and *that* did not render either
(sampled pixels all `(0,0,0)`). So `parse_bytes`-from-a-watcher does not place a *renderable* image
even on a screen where graphics certainly work — my instrument is broken, not the subject.

Therefore: **the §6.2 source argument stands; the "still black with layers forced" measurement is
WITHDRAWN as confounded, and whether a title-bar-screen image would render given `needs_layers`
is UNMEASURED.** What IS measured is that the placement blanks the band's cells — which is by
itself a disqualifying side effect, since the band re-renders on every title change
(482 `kitty/window_title_bar.py:150-151`, `erase_in_line` + redraw) and the placement would have
to be re-asserted against it — reintroducing exactly the re-assert loop this design exists to kill.

**Verdict on (d): the fallback delivers Monaco. There is no Python-only route to SF Pro in the
band.** The C design's `render_a_bar` → `cocoa_render_line_of_text` (CoreText) is the only clean one.

### 6.4 The corruption is STICKY — measured

After the graphics probe, a `load-config` (which re-renders every bar via `erase_in_line` +
redraw) and a full relayout (a new `vsplit`), the black rectangle is **still there**: scanning
the bottom-left pane's band at y=580 gives
`[(20,(68,84,140)), (60,(68,84,140)), (120,(244,246,252)), (180,(68,84,140)), (400,(0,0,0)), (700,(68,84,140))]`
— blue bar, white glyph, and a persistent black hole where the placement sits. Clearing it needs
an explicit graphics delete. One more reason (d) does not come from this direction.

### 6.5 One more honest loose end

An explicit graphics delete fed the same way (`\x1b_Ga=d,d=A,q=2\x1b\\`) into all three band
screens, followed by `update_title_bar()` and a relayout, did **not** clear the black rectangle
(re-scanned: still `(0,0,0)` at x=400). So the state is:

* the graphics command reached the band `Screen` far enough to **claim cells** (the black run is
  exactly the transmitted image width, twice, in two panes), and
* not far enough to **render** one, and
* not far enough for a delete to **release** the cells.

That is internally inconsistent enough that I will not build a conclusion on it. **UNRESOLVED:**
whether `parse_bytes`-from-a-watcher is a faithful way to drive the graphics protocol at all.
The §6.2 source argument does not depend on any of it, and is what the verdict on (d) rests on.

---

## 7. New windows, and the cost

### 7.1 The patch holds for windows created AFTER injection — MEASURED

A fresh `vsplit` under the live patch:
```
win 1 lines 11 cols 71      (pre-existing, horizontal neighbour)
win 2 lines 11 cols 35      (pre-existing, split)
win 9 lines 11 cols 35      (NEW)
```
`winch-A.log` gained `WINCH 3 rows=11 cols=35` — **columns only**, rows held at 11, which is
exactly correct for a vsplit. `winch-B.log` for the new pane starts at `rows=11`. Pixel-sampled,
all three panes carry a band (`#3f5590` inactive / `#2f62d8` active) with no row loss anywhere.

`set_geometry` is resolved on the class at call time, so every future window and every future
OS window in that process is covered without re-injection.

### 7.2 Cost — this is the cheapest of the three live options

| | resident process | timer | per-frame work | re-assert |
|---|---|---|---|---|
| ⌘⌥B graphics overlay (today's ⌘⇧B) | Python + Pillow daemon | 2 s | PNG uploads per pane | yes, constantly |
| stock real bars (⌘⌥B route) | none | none | 1 extra `draw_cells` per pane | none |
| **this patch** | **none** | **none** | **1 extra `draw_cells` per pane — identical to stock** | **none** |

The patch adds **nothing at all** to the render loop relative to stock title bars: the same
`send_cell_data_to_gpu` (482 `child-monitor.c:851-856`) and the same `draw_cells` (`:913-915`),
on the same `vao_idx`. Its only added work is four integers of arithmetic per relayout plus one
extra `set_window_padding` call per window per relayout. It **removes** a resident Python+Pillow
process, a 2 s wakeup and a socket.

It also removes a PTY resize per toggle, which is the expensive event in the stock route: no
`resize_child`, no SIGWINCH, no application reflow across 9 live agent panes.

---

## 8. Deploying it on the LIVE instance — and this is the route's unique argument

🚨 **This is the only one of the candidate designs that can reach pid 597 at all.** The C design
needs a new binary, which needs a restart, which kills or forces a transplant of nine live agent
sessions. The operator's requirement is *"deployed and LIVE for all currently-open kitty sessions,
not just future ones"*. A Python monkeypatch is the only thing that satisfies that sentence today.

### 8.1 Injection

```
kitty @ --to unix:/tmp/kitty-597 launch --type=overlay --watcher /abs/path/patch.py sh -c true
```
- `--type=background` **does not work** (measured, §2.2): no Window, so no watcher load.
- `--type=overlay` briefly puts a window over the active pane. That is a visible, ~0.3 s flicker
  in ONE pane, once. It does not touch the child process of that pane.
- 482 `kitty/launch.py:523,533` memoises `watcher_modules[path]`, so a revision needs a new path.

### 8.2 Risks, stated

| risk | severity | mitigation |
|---|---|---|
| The patch is a reimplementation of a 95-line private method; if 0.48.2's body differs from what I read, behaviour diverges silently | HIGH | the patch was written against `~/kitty-482` (`2cb1d95c3`), the exact build, and MEASURED against the same `/Applications/kitty.app` binary |
| A bug in the patched `set_geometry` wedges every pane in the process | HIGH | keep `Window._ktb_orig_set_geometry`; ship an undo watcher that restores it and relayouts. **Test the exact patch in a sandbox first, every time** |
| Underflowed `padding` is a deliberate integer wrap. A future kitty could make `padding` signed, add a consumer, or clamp it | MEDIUM | it is a 5-site surface (§0); re-grep on every kitty upgrade. Failure mode is benign — the hit test reverts to §4.1 (no hand), nothing renders wrong |
| Turning bars on needs `window_title_bar_min_windows 1`, i.e. a `load-config` against the live instance, which relayouts all nine agent panes | LOW **under the patch** | measured: the relayout costs 0 rows, 0 SIGWINCH, 0 changed pixels outside the band. Without the patch this is the thing the repo record deliberately never ran on the live windows |
| Lost on every kitty restart | CERTAIN | it is an interim by construction; re-inject from the ⌘⇧B binding itself, or from a `watcher` line in kitty.conf for future instances |
| `--type=overlay` flicker | LOW | once per injection |

### 8.3 What ⌘⇧B would then be

Two `launch --type=background` calls today. It becomes: ensure the patch is loaded (idempotent
via the `_ktb_patched` guard), then flip `window_title_bar_min_windows` 0↔1 by `load-config` of
the two existing config files. No daemon, no Pillow, no timer, no PNG.

---

## 9. VERDICT

### 9.1 Score against the four requirements

| | requirement | fallback | evidence |
|---|---|---|---|
| **(a)** | toggles with NO top margin and NO content layout shift | **PASS** | 11/11 rows across the toggle, 0 SIGWINCH against a positive control that fires one; pixel diff = two 45 px bands and nothing else; `g.ynum == screen.lines == 11` from inside kitty |
| **(b)** | always FIXED, does not move when content scrolls | **PASS** | its own 1-line, scrollback-0 `Screen` at a fixed pixel rect; survived 400 lines of scroll, a `clear`, and 20 lines of scrollback with zero movement |
| **(c)** | mouse hand on hover + draggable + survives a no-op drag | **PROBABLE PASS, pointer UNMEASURED** | the mechanism is a 5-site field that no render path reads (grep + 0-changed-pixels); computed `contains_mouse_top 2→47` excludes exactly the band; everything downstream is stock code, read line by line. **The cursor itself was not observed** (§4.4) |
| **(d)** | SF Pro Semibold rather than the cell font | **FAIL** | the band is a cell `Screen` ⇒ Monaco. The graphics-into-band route cannot switch on the layered draw path that would render it (482 `shaders.c:1345-1347,1448` + `child-monitor.c:757-786`) and visibly corrupts the bar |

### 9.2 Recommendation

**Build it — as the live interim, and build the C patch anyway.** They are not competing;
they answer different halves of the operator's sentence.

The fallback is far stronger than the brief's framing assumed. It is not "a/b/d without c": on the
evidence here it is **a/b/(c) without d**, it costs *less* per frame than the graphics overlay it
replaces, it deletes a resident Python+Pillow daemon and a 2 s timer, it is ~60 lines of Python
against a method whose stock body I read and re-derived, and — decisively — **it is the only design
that can be made live in pid 597 without killing nine agent sessions.** The single genuinely novel
fact is §0's: `Window.padding` is a pure hit-test inset with no render consumer, so the hit test
and the content rect are separately addressable from Python, which is precisely the separation the
brief's arithmetic assumed was impossible.

Three conditions on that recommendation, in order:

1. **Put a human on the pointer for ten seconds before shipping it.** §4.4 is the one load-bearing
   claim I could not measure without moving the operator's cursor. If the hand does not appear, the
   route degrades to "a/b, no c, no d" — still better than today's ⌘⇧B on (b) and on cost, but no
   longer a candidate for (c), and the C patch becomes the only answer.
2. **Ship the C patch regardless**, because (d) is unreachable from Python and because a
   monkeypatch of a private method plus a deliberate integer underflow is not a thing to own across
   kitty upgrades. `render_a_bar` → `cocoa_render_line_of_text` is the right long-term shape.
3. **Treat the two as a sequence, not a fork**: the fallback goes live today in the running
   instance; the patched binary takes over at the next natural restart, at which point the watcher
   is simply not re-injected.

### 9.3 What I did not do

- Did not touch pid 597 in any way (not even a read beyond what the brief permits).
- Did not simulate mouse input (§4.4).
- Did not build kitty.
- Did not edit `~/kitty-482`, `~/kitty-dev`, `~/.config/kitty`, the shared checkout, or the
  sibling's worktree.

### 9.4 Artifacts (sandbox, `/private/tmp/ktb-fallback/`)

**The sandbox kitty is LEFT RUNNING, with `patch_v2.py` applied and bars ON** — 3 panes, 11 rows
each, socket `unix:/private/tmp/ktb-fallback/sock`, window title `KTB-FALLBACK-SANDBOX`. It is
there so §4.4's one unmeasured claim can be settled in ten seconds: hover the top 45 px of any
pane. (Two of its bands carry the §6 probe's black rectangle; that is my corruption, not the
design's.)


`sandbox.conf` · `sandbox-on.conf` · `patch_v1.py` (zero-row band) · `patch_v2.py` (+ hit-test
padding) · `probe_geom.py` · `probe_gfx*.py` · `winch.sh` · `winch-A.log` / `winch-B.log` ·
`patch.log` / `patch2.log` / `geom.log` / `gfx*.log` · screenshots `shot-*.png`, `diff-*.png`,
`pad-before.png` / `pad-after.png`, `gfx*.png`, `newsplit.png`.

`/private/tmp` does not survive a reboot — this box reaped it once already today. Copy
`patch_v1.py` / `patch_v2.py` into the repo before relying on them.

**Copied out of `/private/tmp` into `fallback-instruments/` beside this file** (the reboot lesson):
`patch_v1.py`, `patch_v2.py`, `probe_geom.py`, `probe_gfx.py`, `winch.sh`, `sandbox.conf`,
`sandbox-on.conf`, plus three screenshots — `evidence-patched-ON.png` (the zero-row band live),
`evidence-scrollback-fixed.png` (band unmoved 20 lines into scrollback),
`evidence-graphics-corrupts-band.png` (the §6 black hole). The whole rig is re-derivable from the
commands quoted inline; nothing here needs the sandbox to still be alive.

---

## ADVERSARIAL VERIFICATION

Adversarial verifier, 2026-09-16. Method: every cited `file:line` re-opened in the tree it names;
every measurement re-run on an **independent rig** (`/private/tmp/ktb-adv-fb/`, my own sandbox
kitty, my own patch file) with a positive control; and the two links the report *computed* rather
than measured (CPython `'I'` conversion, C unsigned underflow) measured directly in C. Nothing was
written to pid 597 — the only contact was the brief-permitted read-only `kitty @ ls`.

**Bottom line: the headline holds and is now measured harder than the report measured it. The
RECOMMENDATION holds. The SHIPPED ARTIFACT does not — `patch_v2.py` as copied into
`fallback-instruments/` will break the layout of every pane in the OS window after the next reboot,
and I reproduced that failure.**

### A. Upheld, with the evidence strengthened

| claim | verdict | what I did beyond re-reading |
|---|---|---|
| 1, 2 (zero rows, zero SIGWINCH) | **UPHELD — independently reproduced** | Fresh sandbox, two WINCH-trapping panes. **Positive control:** stock `min_windows 1` via `load-config` → `win1=10 win2=10`, `WINCH rows=10` in *both* panes. Patch injected → toggle ON → `win1=11 win2=11`, **zero new WINCH entries in either log**, `g.ynum == screen.lines == 11` logged from inside kitty. The instrument demonstrably says "yes" when a row is stolen. |
| 3 (band is its own scrollback-0 Screen) | **UPHELD** | `482 kitty/window_title_bar.py:125` `Screen(None, 1, 10, 0, cell_width, cell_height)` — cited as `:122`, actual `:125`. |
| 4 (naive patch kills the hand) | **UPHELD** | `482 mouse.c:1066-1081`; the title-bar arm does `break` (the report's excerpt stops one line early, but it is there at `:1077`). |
| 6 (unsigned underflow reaches the hit test) | **UPHELD — upgraded from computed to MEASURED** | The report *computed* `contains_mouse_top 2→47`. I measured both links. (i) A C program embedding CPython 3.13: `PyArg_ParseTuple(t, "I")` on `-45` → `rc=1 value=4294967251`; **positive control** `45`→`45`, `0`→`0`; **negative control** `"x"` → `rc=0`, `'str' object cannot be interpreted as an integer` — so the instrument can refuse. (ii) A compiled reproduction of `window_top()`/`contains_mouse()` with the real types: `pushed window_top = 47`, and the boundary is exact — `y=46.9` excluded, `y=47.0` included, `y=497.0` excluded at the bottom as stock. |
| 7 (pointer UNMEASURED) | **UPHELD, and the refusal was correct, not lazy** | I looked for a programmatic way in: `mouse.c:1663-1666` exports `send_mouse_event`, `test_encode_mouse`, `send_mock_mouse_event_to_window`, `mock_mouse_selection` — **all of them bypass `mouse_region()` and go straight to a chosen window**, and nothing in `fast_data_types` sets `os_window->mouse_x/y` or calls `mouse_event()`. There is no way to exercise the hit test from Python in 0.48.2. The human test is the only route. **The residual is smaller than the report states:** the shape chain is fully read — `mouse.c:1363` `POINTER_POINTER` → `glfw.c:1184` `GLFW_POINTER_CURSOR` → `glfw/cocoa_window.m:3489` `C(GLFW_POINTER_CURSOR, pointingHandCursor)`. The only unread link is GLFW motion re-entering `mouse_event` (`glfw.c:587`), which is the same link stock ⌘⌥B bars already exercise. |
| 8 (downstream is stock) | **UPHELD, citations corrected** | `tabs.py:1853` ✓, `:1883` (cited 1882) ✓, `:1918` ✓, `:2069` ✓, `layout/base.py:412` ✓ exact. |
| 9 ((d) fails) | **UPHELD** | `shaders.c:1316-1319` `screen_needs_rendering_in_layers` is fed only `TD.screen` (`child-monitor.c:770`) and `WD.screen` (`:786`). A title-bar screen's grman reaches neither. |

### B. Overturned or materially corrected

**B1 — the headline overstates `padding` as a control surface, and I measured the clobber.**
The 5-site C grep is exactly reproducible (I widened it to every `*.c`/`*.h` in the tree; still five).
But the field is written from **four** Python call sites, and the patch hooks **one**:
`window.py:825` (`on_dpi_change`), `:875` (`patch_edge_width`), `:886` (`apply_options`), `:1107`
(`set_geometry`). I instrumented `Window.update_effective_padding` and ran the real ⌘⇧B path
(`load-config` to `min_windows 1`). The measured write sequence:

```
UEP-STOCK-RESET win=1 top=0
PUSH           win=1 top=-45   (band=[2,47) g.ynum=11 screen.lines=11)
UEP-STOCK-RESET win=2 top=0
PUSH           win=2 top=-45   (band=[501,546) ...)
UEP-STOCK-RESET win=1 top=0     <-- Window.apply_options, NOT hooked, no PUSH after it
UEP-STOCK-RESET win=2 top=0     <-- both panes now hit-tested as stock
UEP-STOCK-RESET win=1 top=0
PUSH           win=1 top=-45    <-- repaired only because Tab.apply_options happens to relayout
UEP-STOCK-RESET win=2 top=0
PUSH           win=2 top=-45
```

**CORRECTED CLAIM:** *`Window.padding` is a Python-settable hit-test inset that the patch SHARES
with stock code. On every `load-config` — i.e. on every ⌘⇧B press — `Window.apply_options`
(`window.py:886`) resets it to the stock value for every pane, and the hack survives only because
`Tab.apply_options` calls `set_enabled_layouts` → `Tab.relayout` afterwards (`tabs.py:268-271`,
`:262-266`, `:499-503`). That ordering is an accident of call order in `boss.py:3160/3171`, not an
invariant, and the report's stated mitigation ("re-grep the 5 C sites on every kitty upgrade")
cannot see it, because the hazard is entirely in Python.*
**FIX, built and measured:** hook the chokepoint — `Window.update_effective_padding` — instead of
relying on `set_geometry` being the last writer. Measured in the same sandbox across an OFF→ON
toggle: last write per window = `CHOKE-PUSH` for both, `CHOKE-STOCK` whenever `show_title_bar` is
false, no ordering assumption, still 11/11 rows and still zero SIGWINCH. The push is idempotent
because it is computed from `effective_padding()` (a config-derived pt value), never from the
current C value — I tested the double-application hypothesis and it does not apply to this patch.

**B2 — "it touches NO rendering path at all" is true of the FIELD and false of the CONCEPT.**
There is a second, parallel padding representation on the render side:
`render_data.geometry.spaces.{left,top,right,bottom}`, read by `shaders.c:1012-1013` (scrollbar)
and `:1180-1181` (progress bar) to compute "window boundaries including padding". The patch moves
`screen_top` up by one cell while leaving `spaces.top` alone, so those two rects now start 45 px
higher than stock — i.e. their top cell is drawn *under* the band.
**CORRECTED CLAIM:** *No render path reads `w->padding`; the render path reads `geometry.spaces`,
and the patch decouples the two by exactly one cell. Cosmetic, and latent today (`scrollbar`
defaults to `scrolled`, `kitty/options/types.py:646`, so it is only drawn while scrolled back), but
it is a second consumer the 5-site grep cannot see and it belongs in the upgrade-watch list.*

**B3 — the hand is reachable for 33 of the band's 45 px, not 45.**
On both motion and click, `mouse_event` calls `mouse_region(true, true)` (`mouse.c:1354`,
`detect_borders = true`). The border branch runs FIRST and `return ans` before the window loop
whenever the pointer is within `window_drag_tolerance` of a border rect (`mouse.c:1003-1063`), and
`borders.py:65` gives **every** window group a top horizontal edge with a non-zero `border_type`.
Tolerance = `round(6 × 144/72)` = **12 device px**; the border rect itself is `[g.top-2, g.top)`.
So `y ∈ [g.top, g.top+12)` resolves to `NS_RESIZE_POINTER` + `drag_resize_start`, and only
`[g.top+12, g.top+45)` reaches `in_title_bar`.
**CORRECTED CLAIM:** *Requirement (c)'s hand and drag are reachable over the lower ~73% of the
band. The top 12 px is a resize handle. This is NOT caused by the patch — stock title bars behave
identically — but it is a cap on (c) that neither the brief nor this report states, and it is a
direct consequence of this repo's own deliberate choice to raise `window_drag_tolerance` from 2 to
6 (`config/kitty.conf:327`) to make border-resize hittable. It is tunable: the two features are
trading the same pixels.* (Tabs with a single visible window are exempt — `detect_borders` is
gated on `num_visible_windows(t) > 1`.)

**B4 — claim 10 as worded is false, and its stake is stale.**
"The only candidate design that can reach the operator's live pid 597 at all" — today's ⌘⇧B
graphics overlay is also pure Python and is live in pid 597 right now.
**CORRECTED CLAIM:** *It is the only design that can reach pid 597 **and satisfy (b)**.*
Separately, measured via the permitted read-only `kitten @ --to unix:/tmp/kitty-597 ls`: pid 597
currently holds **2 OS windows and 4 windows**, not the brief's 5 and 9. Remote control answers, and
`allow_remote_control socket-only` (`config/kitty.conf:107`) does permit `launch --watcher` — the
watcher path is in the remote protocol spec (`482 kitty/rc/launch.py:59`) with no trust gate, and
`resolve_custom_file` (`utils.py:654-658`) accepts an absolute path. So the deployment mechanism is
confirmed; only the size of the stake was overstated.

**B5 — 🚨 the artifact in `fallback-instruments/` is not shippable as copied, and I reproduced the failure.**
`patch_v2.py` calls `log()` — an unguarded `open('/private/tmp/ktb-fallback/patch2.log', 'a')` —
**inside `patched`**, outside `on_load`'s `try`. §9.4 of this very report states that `/private/tmp`
does not survive a reboot and was reaped once today. After a reboot, the first relayout raises
`FileNotFoundError` inside `Window.set_geometry`.
Measured severity (armed deliberately in my sandbox, raising at exactly the point `log()` is called):

```
File "kitty/tabs.py", line 503, in relayout
File "kitty/layout/base.py", line 416, in __call__
File "kitty/layout/tall.py", line 261, in do_layout
File "kitty/window_list.py", line 143, in set_geometry
FileNotFoundError: [Errno 2] ... '/private/tmp/ktb-fallback/patch2.log'
```

`load-config` fails with a traceback; every subsequent relayout dies; **new windows arrive
un-laid-out at the default `24x80` alongside correctly-sized siblings**. kitty itself survives.
Recovery is possible and I verified it: `load_watch_modules` runs *before* `tab.new_window`
(`launch.py:823` then `:825`), so an undo watcher's `on_load` still executes even though its own
launch then raises — restoring `_ktb_orig_set_geometry` and relayouting returned the tab to
`11x71 / 11x35 / 11x35`.
**CORRECTED CLAIM:** *The design is sound; this implementation of it is not. Three blocking changes
before anything is injected into pid 597: (1) wrap the whole patched body in `try/except` falling
back to the original `set_geometry` — an exception there takes the layout engine down for every
pane in the OS window; (2) delete the file logging from the hot path entirely (it is a file open +
write per window per relayout, forever, in the operator's live kitty); (3) ship the undo watcher —
the risk table names it as the mitigation and no such file exists in `fallback-instruments/`.*

### C. New risks and corrections not in the report

1. **Requirement (a) is met by OCCLUSION, and the score table should say so.** The child keeps all
   11 rows and believes row 1 is visible; the band covers it. Nothing shifts, but one line of every
   pane is permanently unreadable while bars are on. This is inherent to "zero rows + no margin"
   (the brief's own arithmetic forces it) and applies equally to the proposed C `render_a_bar`
   design — but "PASS" with no cost line reads as if nothing was given up.
2. **The cost table understates the win.** Today's overlay puts an image in a **content** screen's
   graphics manager, so `grman_has_images` → `screen_needs_rendering_in_layers` (`shaders.c:1319`)
   → `os_window->needs_layers` (`child-monitor.c:786`) forces the whole OS window onto
   `draw_cells_with_layers` every frame, with the extra framebuffer work at `shaders.c:1448, 1642,
   1673`. A title-bar screen never contributes to `needs_layers`. Removing the overlay removes
   **layered rendering**, not merely a daemon and a timer. (The report's per-frame comparison
   against the overlay remains otherwise UNMEASURED — no frame times were taken. The
   "identical to stock" half is sound by construction.)
3. **Use `--keep-focus` on the live injection.** `launch.py:823` wraps `tab.new_window` in
   `Window.set_ignore_focus_changes_for_new_windows(opts.keep_focus)`. Without it the 0.3 s overlay
   takes focus, and any keystroke in flight is delivered to a window that is about to exit.
4. **`window_title_bar bottom` is silently unsupported.** `patch_v2.py` computes `tb_top/tb_bottom`
   for `'bottom'` but gates the padding push on `position == 'top'`, so a bottom bar gets (a) and
   (b) and no hand. Fine for this config; it should be stated, or the push mirrored to
   `padding.bottom`.
5. **Minor measurement correction:** `launch --type=background --watcher` returned **`0`**, not "a
   window id" (§2.2). The substantive finding — the watcher never loads — reproduced exactly, and
   the mechanism is confirmed at `launch.py:790-796` (the background branch never reaches
   `load_watch_modules` at `:823`).
6. **Citation drift, the known repeat offender.** Ranges are right; per-line prefixes drift.
   `window_title_bar.py` cited `120/122/125/126/127` → actual `121/125/128/129`.
   `child-monitor.c` band draw cited `:913-915` → actual `:919`; the loop cited `906-919` → actual
   `910-921`; the upload cited `851-856` → actual `852-856`. `mouse.c:1133-1134` → the two
   `POINTER_POINTER` sites in that function are `:1132` and `:1134`. None of these change a
   conclusion, but a reader checking `:913` finds nothing.

### D. Verdict on the recommendation

**The sequence recommendation stands** — fallback live now, C patch anyway, hand over at the next
restart by not re-injecting. Its three conditions stand, with one added and one re-ordered:

- **Condition 0 (new, BLOCKING, before any contact with pid 597):** fix the artifact per B5 —
  try/except fallback, no file logging, ship the undo watcher. As it sits in the repo today,
  copying `patch_v2.py` into the live instance arms a layout-wide break for the next reboot.
- **Condition 1 (unchanged):** the ten-second human pointer test. I confirmed it cannot be
  automated in 0.48.2 (§A, claim 7). Have the human also hover the **top 12 px** and the **middle**
  of a band separately — B3 predicts a resize cursor in the first and a hand in the second, and
  that is the cheapest possible test of whether my border analysis is right.
- **Condition 1b (new):** hook `update_effective_padding`, not `set_geometry`, for the padding push
  (B1). Built and measured; it removes the only silent-revert path.
- **Conditions 2 and 3 (unchanged):** ship the C patch regardless; hand over at the next restart.

**Score, corrected:** (a) PASS *by occlusion* · (b) PASS · (c) PROBABLE PASS **over ~73% of the
band**, pointer still unmeasured · (d) FAIL.

*Rig left in place for re-derivation: `/private/tmp/ktb-adv-fb/` (sandbox conf, `winch.sh`,
`patch_adv.py` = report's patch + padding-writer instrumentation, `patch_choke.py` = the chokepoint
correction, `patch_boom.py` / `patch_undo.py` = the severity probe and its recovery, `order.log`,
`choke.log`, `winchA.log`, `winchB.log`); `/private/tmp/ktb-verify/` (`pad.c` the C underflow
control, `pyarg.c` the CPython `'I'` control). Both are under `/private/tmp` and will be reaped —
the commands are quoted inline above and the rigs are re-derivable from them.*
