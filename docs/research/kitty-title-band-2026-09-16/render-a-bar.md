# The `render_a_bar` top-title-band patch — exact design

**Axis:** the drawing half of a native top title band for every kitty window, taking ZERO cells from
the grid.
**Tree of record:** `~/kitty-482`, detached at `v0.48.2` (`2cb1d95c3` — verified
`git log --oneline -1` => `2cb1d95c3 version 0.48.2`). Every `file:line` below is that tree unless
explicitly marked `~/kitty-dev` (master `1d67ecd47`).
**Date:** 2026-09-16. **Built:** NO (brief forbids it). Everything marked UNMEASURED is UNMEASURED.

---

## 0. Headline, before the detail

The design in the brief is **sound and the geometry is already there** — `render_a_bar`'s
`along_bottom=false` branch *is* a top band and needs no arithmetic change at all. But two things
the brief did not know change the patch materially, and one of them is a cost the operator's own
"lowest to zero latency and memory pressure" clause makes load-bearing:

1. **`render_a_bar`'s only two callers both live inside `draw_cells_with_layers`, and
   `draw_cells_without_layers` is a two-line function that draws nothing but cells**
   (`kitty/shaders.c:1345-1347`). Every overlay in kitty — scrollbar, progress bar, URL bar, window
   number, visual bell — is reachable only on the layered path. The layered path renders the WHOLE
   OS window into an offscreen `GL_RGBA16` texture and blits it back
   (`kitty/shaders.c:1638-1692`). A title band that is always visible would pin `needs_layers` true
   forever, i.e. permanently disable kitty's fast direct-to-default-framebuffer path for every OS
   window that has the band on. **That is the real cost of this design and the brief does not
   mention it.** §1 gives the placement that avoids it and the one thing that placement needs
   proving.
2. **`title_bar_data` is already double-booked**, and worse than the brief thought: the URL bar
   (`draw_hyperlink_target`) keeps its *text* in `url_target_bar_data` but renders through
   **`window->title_bar_data`** (`kitty/shaders.c:929` — `render_a_bar(ui, &window->title_bar_data,
   bd->last_drawn_title_object_id, ...)`). So `title_bar_data` is the shared *pixel buffer* for two
   different texts already. A third consumer that is permanently on will thrash it every frame. A
   new `WindowBarData` field is required, not optional. §3.
3. **The band is 51 device px tall on this machine, not 45.** `bar_height = cell_height + 2` and the
   border adds `2 * border_width` on top of that. With cell 45 px and `border_width` 2 px the band's
   `border_rect.height` is **51 px**, so it covers content row 1 (45 px) *plus the top 6 px of row
   2*. §2 has the arithmetic and the two ways to make it exactly one cell.

A fourth item, in the operator's favour: **nothing in the drawing half needs the hit test.** The
band is drawn at a fixed viewport every frame from `srd->geometry`, so it satisfies (a) zero rows
and (b) fixed-under-scroll by construction. (c) is a separate C change in `kitty/mouse.c` and is
the sibling session's axis; §6 states exactly what the drawing half must export for it.

---

## 1. Where in the draw path the call belongs

### 1.1 The per-window draw loop

`kitty/child-monitor.c:898-925`, `render_prepared_os_window()`:

- `:906` — tab bar: `draw_cells(&TD, os_window, true, true, false, NULL)`
- `:909-911` — counts `num_of_visible_windows`
- `:912-922` — the per-window loop; `:915` `draw_cells(&WD, os_window, is_active_window, false,
  num_of_visible_windows == 1, w)` draws the window's cells
- `:918-920` — **the existing row-stealing title bar**: `WindowRenderData *trd =
  &w->window_title_render_data;` then `draw_cells(trd, ...)` if its geometry is non-empty. This is
  ⌘⌥B's bar: a *separate `Screen`* with its own geometry, drawn as cells. That is exactly why it
  costs a row — it is a real grid.

### 1.2 `draw_cells` and the layers fork

`kitty/shaders.c:1411-1451`. It builds the `UIRenderData` at `:1434-1444`:

```c
UIRenderData ui = {
    .screen_width = srd->geometry.right - srd->geometry.left,
    .screen_height = srd->geometry.bottom - srd->geometry.top,
    .cell_width = os_window->fonts_data->fcm.cell_width,
    .cell_height = os_window->fonts_data->fcm.cell_height,
    .screen_left = srd->geometry.left, .screen_top = srd->geometry.top,
    .full_framebuffer_width = os_window->viewport_width,
    .full_framebuffer_height = os_window->viewport_height,
    .window = window, .screen = screen, .os_window = os_window, ...
};
```

then `:1445-1450`:

```c
save_viewport_using_top_left_origin(
    ui.screen_left, ui.screen_top, ui.screen_width, ui.screen_height, ui.full_framebuffer_height);
if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
else draw_cells_without_layers(&ui, srd->vao_idx);
restore_viewport();
```

**`draw_cells_without_layers` is `kitty/shaders.c:1344-1348` and is three lines:**

```c
static void
draw_cells_without_layers(const UIRenderData *ui, ssize_t vao_idx) {
    call_cell_program(CELL_PROGRAM, ui, vao_idx, true, DRAW_BOTH_BG);
}
```

No overlays. All of them — `draw_visual_bell`, `draw_drag_preview_overlay`, `draw_progress_bar`,
`draw_scrollbar`, `draw_hyperlink_target`, `draw_window_number` — are called only from
`draw_cells_with_layers`, `kitty/shaders.c:1377-1383`.

### 1.3 How an overlay forces the layered path today (and why that matters)

`kitty/shaders.c:1315-1320`:

```c
bool
screen_needs_rendering_in_layers(OSWindow *os_window, Window *w, Screen *screen) {
    const bool has_ui = w && ((screen->start_visual_bell_at | screen->start_drag_overlay_at)
        || has_scrollbar(w, screen) || has_progress_bar(screen)
        || has_hyperlink_target(os_window, w, screen) || has_window_number(w, screen)
        || w->window_logo.id);
    ...
    return has_ui || grman_has_images(grman);
}
```

Every overlay has a `has_*()` predicate in this OR-chain, and `kitty/child-monitor.c:757-759,
770, 781, 786` ORs the result over the tab bar and **every visible window** into one OS-window-wide
`os_window->needs_layers`:

```c
os_window->needs_layers = (
    !global_state.supports_framebuffer_srgb || effective_os_window_alpha(os_window) < 1.f ||
    os_window->live_resize.in_progress || (background_image_for_os_window(os_window) != NULL)
);
```

So the *idiomatic* patch — add `has_window_title_band(w, screen)` to the `has_ui` chain and call
`draw_window_title_band(ui)` from `draw_cells_with_layers` — is four lines and works. **And it
permanently disables the non-layered path.** `kitty/shaders.c:1638-1667` shows what that buys:
a global `layers_render_texture` sized to the largest viewport, `GL_RGBA16` internal format
(`:684-694`), a per-OS-window FBO, a full `clear_current_framebuffer()`, and at
`:1670-1692` a full-viewport `BLIT_PROGRAM` quad every frame. On a 5-OS-window / 9-pane retina
setup that is one shared texture of `4 (or 8) bytes × max(viewport_w × viewport_h)` plus a
full-screen blit per frame per window, forever.

> **UNMEASURED:** I did not build, so I have not measured the frame-time delta between the layered
> and non-layered paths on this box, nor confirmed that `global_state.supports_framebuffer_srgb` is
> true on this machine's GL stack (if it is false, `needs_layers` is *already* permanently true and
> the whole cost objection evaporates). Both are one build + one `kitty --debug-rendering` away.
> Until measured, treat "the band forces layers" as a CONFIRMED code path with an UNMEASURED cost.

### 1.4 The answer: draw it in `draw_cells`, after the fork, not inside either branch

```
draw_cells()                           kitty/shaders.c:1411
  save_viewport_using_top_left_origin(...)          :1445
  if (needs_layers) draw_cells_with_layers(...)     :1448
  else              draw_cells_without_layers(...)  :1449
  >>> draw_window_title_band(&ui);   <<< HERE       (new line, before :1450)
  restore_viewport()                                :1450
```

**Exact function: `draw_cells`. Exact line: a new statement between `kitty/shaders.c:1449` and
`kitty/shaders.c:1450`** — after the `if/else`, before `restore_viewport()`.

Why there and not inside `draw_cells_with_layers`:

- **It must be inside the saved viewport.** `render_a_bar` calls
  `enable_scissor_using_top_left_origin(border_rect, sh)` (`:876`) and
  `save_viewport_using_top_left_origin(...)` (`:880`) itself, and those are absolute — computed from
  `ui->screen_left/top` against `ui->full_framebuffer_height`, not relative to the current viewport.
  So strictly it does not *need* the outer viewport. But `restore_viewport()` at `:882` pops back to
  whatever was current, and the outer `save/restore` pair is what makes that well-defined. Placing
  the call between `:1449` and `:1450` keeps it inside that pair with zero new state management.
- **It is drawn last, so it is on top of the cells** — which is the whole point: it covers content
  row 1 rather than displacing it.
- **It runs on BOTH paths**, so `screen_needs_rendering_in_layers` needs no new arm and the fast
  path survives.

🚨 **The one thing this placement needs proving, and I could not prove it without a build.**
`render_a_bar` has only ever run on the layered path, so its colour handling is calibrated for it.
Two specific hazards:

- `blank_canvas(ui->bg_alpha, bg, false)` at `:877` passes `for_final_output = false`, which writes
  **premultiplied linear** clear colour (`:1390-1396`). On the layered path the target is the
  `GL_RGBA16` texture and `GL_FRAMEBUFFER_SRGB` is off (`call_cell_program` at `:1339-1341` enables
  it only `if (for_final_output)`, and the layered calls all pass `false`). On the **non**-layered
  path the target is the default framebuffer and the cell program enables `GL_FRAMEBUFFER_SRGB`
  around its own draw only. A linear clear colour written to a default framebuffer with SRGB
  conversion off will be **visibly wrong** (too dark). The fix is almost certainly to pass
  `for_final_output = !ui->os_window->needs_layers` down into `blank_canvas`, and to wrap the
  `draw_graphics` + `draw_rounded_rect` calls in `glEnable/glDisable(GL_FRAMEBUFFER_SRGB)` on the
  non-layered path, exactly as `call_cell_program` and `draw_borders` (`:1502-1504`) already do.
- The texture upload at `:869` uses `GL_SRGB_ALPHA` as the internal format, so the sampler already
  linearises the bar's own pixels; that part is path-independent.

**Verdict on §1:** the call belongs in `draw_cells` after the layers fork; that placement is what
makes the feature cheap instead of expensive; and the sRGB handling on the non-layered path is the
single piece of this patch that **must** be measured on a real build rather than reasoned about. If
it proves intractable, the fallback is the four-line idiomatic patch (call from
`draw_cells_with_layers` + a `has_window_title_band` arm in `screen_needs_rendering_in_layers`),
which is certainly correct and certainly costs the blit.

---

## 2. The geometry maths for a TOP band

### 2.1 What `render_a_bar` already computes

`kitty/shaders.c:837-846` and `:871-874`:

```c
unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));   // :838
unsigned bar_height   = ui->cell_height + 2;                                    // :839
unsigned bar_width    = ui->screen_width - 2 * border_width;                    // :840
...
Viewport border_rect = {
    .height = bar_height + 2 * border_width,
    .left   = ui->screen_left,
    .width  = ui->screen_width,
    .top    = ui->screen_top };                                                 // :871-872
if (along_bottom) border_rect.top += ui->screen_height - border_rect.height;    // :873
```

**So the expression for the top band is the unmodified default:**

```
border_rect.left   = ui->screen_left
border_rect.top    = ui->screen_top
border_rect.width  = ui->screen_width
border_rect.height = ui->cell_height + 2 + 2*ceil(box_drawing_scale[1] * dpi / 72)
```

i.e. **call `render_a_bar(ui, bar, title, /*along_bottom=*/false)` and the geometry is done.** No
new arithmetic. This is already what `draw_window_number` does at `kitty/shaders.c:943`
(`render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false)`).

The inner text quad is inset by the border on all sides, `:880-881`:

```c
save_viewport_using_top_left_origin(
    border_rect.left + border_width, border_rect.top + border_width, bar_width, bar_height, sh);
```

`Viewport` is `{unsigned left, top, width, height}` (`kitty/gl.h:32`) and both
`enable_scissor_using_top_left_origin` and `save_viewport_using_top_left_origin` take
`full_framebuffer_height` to flip into GL's bottom-left origin — so `top` here is genuine
top-left-origin device pixels, same space as `srd->geometry`.

### 2.2 The numbers on THIS machine

`thickness_as_float`, `kitty/shaders.c:304-310`:

```c
double pts = OPT(box_drawing_scale)[level];         // level 1
double dpi = (logical_dpi_x + logical_dpi_y) / 2.0;
return pts * dpi / 72.0;
```

`box_drawing_scale` default is `0.001, 1, 1.5, 2` (`kitty/options/definition.py:231-233`), so
level 1 = **1.0 pt**. Note this is `box_drawing_scale`, **not** the config's
`window_border_width 1pt` — `render_a_bar`'s border is independent of the window border option and
happens to coincide at the default.

Taking the brief's `dpi 144 / scale 2 / cell 45 device px` as given (I did not measure the live
instance's DPI myself — **UNMEASURED by me**, stated in the brief):

| quantity | expression | value |
|---|---|---|
| `border_width` | `ceil(1.0 * 144 / 72)` | **2 px** |
| `bar_height` | `cell_height + 2` = `45 + 2` | **47 px** |
| `bar_width` | `screen_width - 2*2` | `screen_width - 4` px |
| `border_rect.height` | `47 + 2*2` | **51 px** |
| `border_rect.top` | `ui->screen_top` | top of the cell grid |

🚨 **51 px against a 45 px cell. The band overhangs content row 1 by 6 px** — it covers all of row 1
and the top 6 px of row 2, clipping the ascenders of row 2's glyphs. For the URL bar and the window
number this is invisible (they are transient). For a permanently-on title band it is a visible
defect and the operator's (a) "no content layout shift" will read as satisfied while the second row
looks shaved.

Two cures, both small:

- **Cure A (preferred, no new geometry):** make the band exactly one cell by shrinking the text
  canvas: `bar_height = ui->cell_height - 2*border_width` and leave `border_rect.height =
  bar_height + 2*border_width == ui->cell_height`. On this machine: `bar_height = 45 - 4 = 41`,
  `border_rect.height = 45`. Exactly row 1, no overhang. Costs 6 px of glyph height inside the
  band (41 px of a 45 px cell), which for a sans title at SF Pro Semibold is comfortable.
- **Cure B:** drop the rounded border for the title band (pass a flag, skip `:884`
  `draw_rounded_rect`), set `border_width = 0` for this consumer, and `bar_height = ui->cell_height`.
  Exactly one cell, full glyph height, no border. This also removes a `ROUNDED_RECT_PROGRAM` draw
  per window per frame. Aesthetically this is probably what the operator wants — the real ⌘⌥B title
  bars have no rounded border either.

I recommend **Cure B** for the title band and leaving `render_a_bar`'s existing behaviour untouched
for its two current callers, by adding a parameter rather than editing the shared maths (see §7).

### 2.3 No gap, no overlap — against our actual config

Our config is `window_padding_width 0 5 0 5` (top 0, right 5, bottom 0, left 5) and
`placement_strategy top`.

- **vs. the cell grid.** `ui->screen_top = srd->geometry.top` and `geometry` is the **cell grid
  rect, padding excluded** — proven by `kitty/mouse.c:249-267`, where the padded rect is
  reconstructed as `geometry.left - padding.left` … `geometry.bottom + padding.bottom`. So the band
  starts exactly at the first pixel of row 1. **No gap.** ✅
- **vs. the top padding.** With top padding 0 there is no strip above the grid for the band to
  leak into, and the band does not try to — it starts *at* `screen_top` and grows downward. If the
  operator ever restores a top padding, the band would sit *below* it rather than in it; that is a
  design choice to note, not a bug. (`window_padding_width`'s first value is top — the config's
  `0 5 0 5` is top/right/bottom/left.)
- **vs. the window border.** `window_border_width 1pt` with `draw_minimal_borders no`. Borders are
  drawn *before* any cells, `kitty/child-monitor.c:903-905` (`draw_borders(...)` at the top of
  `render_prepared_os_window`), and their rects live **outside** `geometry` — they are laid out by
  the Python layout layer into `tab->border_rects` and hit-tested separately
  (`kitty/mouse.c:1010-1037`). Since our band is clamped to `[screen_left, screen_left +
  screen_width) × [screen_top, screen_top + height)`, it is strictly inside the grid and **cannot
  overlap a border**. ✅
- **vs. the tab bar.** The tab bar is a separate `WindowRenderData` (`tab_bar_render_data`,
  `kitty/state.h:438`) drawn by its own `draw_cells` call at `kitty/child-monitor.c:906`, and the
  central region is computed by `os_window_regions()` (used at `kitty/mouse.c:992`) so that the
  windows' geometries never intersect the tab bar's. The band is inside a window's geometry, so
  **no overlap with the tab bar**, whatever `placement_strategy` or `tab_bar_edge` say. ✅
- **vs. the left/right padding of 5.** `border_rect.width = ui->screen_width`, i.e. the full grid
  width, so the band stops 5 px short of the pane edge on each side. Whether that is wanted is
  taste; to run the band edge-to-edge over the padding you would set
  `border_rect.left = ui->screen_left - window->padding.left` and
  `width = ui->screen_width + padding.left + padding.right`. **This is safe only because our top
  padding is 0** — extending horizontally does not touch another window, since the padding belongs
  to this window. I would not do it in v1.

---

## 3. Which `WindowBarData` — and the freeing

### 3.1 `title_bar_data` is already double-booked, worse than the brief said

`kitty/state.h:220-226`:

```c
typedef struct WindowBarData {
    unsigned width, height;
    uint8_t *buf;
    PyObject *last_drawn_title_object_id;
    hyperlink_id_type hyperlink_id_for_title_object;
    bool needs_render;
} WindowBarData;
```

and `kitty/state.h:276`: `WindowBarData title_bar_data, url_target_bar_data;`

The two existing consumers:

- `draw_window_number` — `kitty/shaders.c:942-944` renders `ui->window->title` through
  **`ui->window->title_bar_data`**.
- `draw_hyperlink_target` — `kitty/shaders.c:911-934`. It stores the URL *text* and the
  `hyperlink_id_for_title_object` in `window->url_target_bar_data` (`bd`), but at `:929` it renders
  through **`&window->title_bar_data`**:

```c
PyObject *ref = Py_NewRef(bd->last_drawn_title_object_id);  // render_a_bar clears bd->last_drawn_title_object_id
render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom);
Py_DECREF(ref);
```

So `title_bar_data` is *already* the shared RGBA scratch buffer for two different strings, and
`url_target_bar_data` is used only as a text/id cache. (The `Py_NewRef`/`Py_DECREF` dance exists
because `render_a_bar` does `Py_CLEAR(bar->last_drawn_title_object_id)` at `:865` on the bar it was
handed, which here is the *other* struct — a latent footgun that this comment is documenting.)

**Does a third consumer conflict? Yes, and it is the expensive kind of conflict.** `render_a_bar`'s
cache test is `if (bar->last_drawn_title_object_id != title || bar->needs_render)` (`:862`). Two
consumers sharing one `WindowBarData` but passing different `title` objects will **miss the cache on
every single frame in which both are active**, each re-running `draw_window_title()` → CoreText
text shaping and rasterisation into a 47-row RGBA buffer. Today that is rare (window number and URL
bar are both transient and roughly mutually exclusive). A **permanently-on** title band makes it
the steady state: hover a hyperlink with `show_hyperlink_targets` on and you get two full CoreText
rasterisations per window per frame.

### 3.2 Therefore: add a new field

```c
// kitty/state.h:276
-    WindowBarData title_bar_data, url_target_bar_data;
+    WindowBarData title_bar_data, url_target_bar_data, top_title_band_data;
```

This is the minimal change and it makes the band's cache independent, so a steady-state frame with
an unchanged title does **zero** CPU rasterisation work (§4).

### 3.3 What must be freed, and WHERE — the brief named one site, there are TWO

Both must be updated or the band leaks a `malloc`'d RGBA buffer and a `PyObject` reference per
window:

1. **`kitty/state.c:418-434`, `destroy_window()`** — lines `:425-428`:

```c
Py_CLEAR(w->title_bar_data.last_drawn_title_object_id);
free(w->title_bar_data.buf); w->title_bar_data.buf = NULL;
Py_CLEAR(w->url_target_bar_data.last_drawn_title_object_id);
free(w->url_target_bar_data.buf); w->url_target_bar_data.buf = NULL;
```

2. **`kitty/dnd.c:2374-2390`, `destroy_fake_window_contents()`** — lines `:2384-2387`, the
   byte-identical four lines. This is a **v0.48.2-era addition** (fake windows used by the drag-and-
   drop tests) that the brief did not mention. I checked: `grep -n "title_bar_data\|
   url_target_bar_data" kitty/*.c | grep -v shaders.c` returns exactly these two sites and nothing
   else in the whole C tree.

Each needs the two-line pair added:

```c
Py_CLEAR(w->top_title_band_data.last_drawn_title_object_id);
free(w->top_title_band_data.buf); w->top_title_band_data.buf = NULL;
```

**Nothing else needs freeing.** `render_a_bar` allocates a GL texture at `:851` and frees it at
`:883` (`free_texture(&data.texture_id)`) inside the same call — there is no GPU resource with a
lifetime beyond the frame, so `release_gpu_resources_for_window` (`kitty/state.c:429`) is
unaffected. There is no resize hook to add either: `render_a_bar` reallocates its own buffer
whenever `bar->width`/`bar->height` disagree with the requested size (`:841-848`), which is exactly
what a font-size or pane-width change produces.

> **A GPU cost worth naming:** `render_a_bar` does `glGenTextures` + `glTexImage2D` +
> `free_texture` **every frame, for every bar it draws** (`:851-870`, `:883`). Per-frame texture
> churn is acceptable for a transient overlay; for a permanent per-window band across 9 panes it is
> 9 texture create/upload/destroy cycles per frame. Caching the texture id on the `WindowBarData`
> alongside `buf` — upload only when `needs_render` fired — is the obvious optimisation and is
> where the operator's "zero latency and memory pressure" clause actually bites. See §7 hunk 2.
> **UNMEASURED:** I have not profiled this; the claim that it is per-frame is CONFIRMED from the
> code, the claim that it is *costly* is not.

---

## 4. Redraw and no-redraw — and an upstream cache bug this patch MUST fix

### 4.1 The intended mechanism

`kitty/shaders.c:841-868`:

```c
    if (!bar->buf || bar->width != bar_width || bar->height != bar_height) {   // :841
        free(bar->buf);
        bar->buf = malloc((size_t)4 * bar_width * bar_height);
        if (!bar->buf) return 0;
        bar->height = bar_height;
        bar->width = bar_width;
        bar->needs_render = true;                                             // :847
    }
    ...
    if (bar->last_drawn_title_object_id != title || bar->needs_render) {       // :852
        static char titlebuf[2048] = {0};
        if (!title) return 0;
        snprintf(titlebuf, arraysz(titlebuf), " %s", PyUnicode_AsUTF8(title));
        if (!draw_window_title(..., titlebuf, fg, bg, bar->buf, bar_width, bar_height, NULL)) return 0;  // :856
        Py_CLEAR(bar->last_drawn_title_object_id);
        bar->last_drawn_title_object_id = Py_NewRef(title);                    // :858
    }
```

Two intended triggers:

- **Title changed.** The test is `bar->last_drawn_title_object_id != title` — a **pointer**
  comparison against the `PyObject *` the caller handed in, and the bar holds a strong reference
  (`Py_NewRef` at `:858`, released by `Py_CLEAR` at `:857`). So when Python sets
  `window->title` to a *new* string object, the pointer differs and the bar re-rasterises.
  🚨 **Consequence to know: a title that changes to an equal-valued but distinct string object
  re-renders anyway, and a title that is mutated in place would NOT re-render.** Python strings are
  immutable so the second cannot happen; the first means a shell that re-emits an identical OSC 2
  every prompt will re-rasterise every prompt. That is correct-but-wasteful and not worth changing.
- **Geometry changed.** `:841` — pane resized, font size changed, DPI changed. The buffer is
  reallocated and `needs_render` is raised.

### 4.2 🚨 `needs_render` is never cleared — CONFIRMED in BOTH trees

```
$ cd ~/kitty-482 && grep -n "needs_render" kitty/shaders.c
847:        bar->needs_render = true;
852:    if (bar->last_drawn_title_object_id != title || bar->needs_render) {
925:        bd->needs_render = true;
1316:screen_needs_rendering_in_layers(OSWindow *os_window, Window *w, Screen *screen) {
1672:    if (OPT(cursor_trail) && tab->cursor_trail.needs_render) draw_cursor_trail(...);
```

A whole-tree search (`grep -rn "needs_render" kitty/` filtered of the unrelated
`os_window->needs_render` / `cursor_trail` uses) finds **exactly two writes to a
`WindowBarData.needs_render`**, `kitty/shaders.c:847` and `kitty/shaders.c:925`, and **both set it
`true`. Nothing anywhere sets it `false`.** `WindowBarData` starts zeroed, so:

| call | `buf` | realloc branch | `needs_render` | `draw_window_title` runs? |
|---|---|---|---|---|
| 1st | NULL | taken | set **true** | yes |
| 2nd | valid, dims match | skipped | still **true** | **yes** |
| n-th | valid, dims match | skipped | still **true** | **yes** |

**So the `last_drawn_title_object_id` cache is dead code today: every rendered frame re-runs
`draw_window_title()`, i.e. on macOS a full `cocoa_render_line_of_text()` CoreText shape + raster
into the RGBA buffer** (`kitty/glfw.c:1082-1094`).

Same in master: `~/kitty-dev` at `1d67ecd47`, `kitty/shaders.c:1264` sets it true, `:1275` tests it,
nothing clears it. **This is an upstream bug, not a v0.48.2 artifact.**

Today it barely matters — the URL bar and the window-number title are transient and the OS window
only renders a frame when `prepare_to_render_os_window` says something changed
(`kitty/child-monitor.c:979-982`). For a **permanently-on** title band it matters a lot: it is one
CoreText rasterisation per window per rendered frame, forever, which is precisely what the
operator's "lowest to zero latency" clause forbids.

**The fix is one line** and belongs in this patch:

```diff
--- a/kitty/shaders.c
+++ b/kitty/shaders.c
@@ -856,6 +856,7 @@
         if (!draw_window_title(..., bar->buf, bar_width, bar_height, NULL)) return 0;
         Py_CLEAR(bar->last_drawn_title_object_id);
         bar->last_drawn_title_object_id = Py_NewRef(title);
+        bar->needs_render = false;
     }
```

**Check it does not break the two existing callers before landing it:** `draw_hyperlink_target`
raises `bd->needs_render = true` at `:925` on its own `url_target_bar_data`, then renders through
`window->title_bar_data` at `:929` — so the flag it raises is on a *different* struct from the one
`render_a_bar` would now clear. Its real cache key is the `title` pointer, which it swaps on every
hyperlink change, so clearing `needs_render` leaves it correct. `draw_window_number` keys purely on
`ui->window->title`, likewise correct. **UNMEASURED:** I have not run kitty with this line applied;
the reasoning above is from code only, and this is the one change in the patch that could
plausibly cause a *stale* bar rather than a missing one, so it deserves a manual check (resize a
pane while the URL bar is showing).

### 4.3 What must ALSO invalidate, that neither trigger covers

With the fix in §4.2, a steady-state frame costs zero rasterisation. But three state changes alter
the *pixels* without changing either the title pointer or the buffer dimensions, and each therefore
needs an explicit invalidation:

1. **Active ⇄ inactive** (§5). The fg/bg change but the title object does not. Store the last-drawn
   `fg`/`bg` on the `WindowBarData` and compare, or store a `bool last_drawn_active`.
2. **Colour-scheme / config reload.** `load-config` can change the four
   `window_title_bar_*` colours with no title change and no resize.
3. **Alignment** (`window_title_bar_align`) if honoured.

The cheapest correct form is to widen the cache key rather than add invalidation call sites:

```c
if (bar->last_drawn_title_object_id != title || bar->needs_render
        || bar->last_fg != fg || bar->last_bg != bg) { ... bar->last_fg = fg; bar->last_bg = bg; }
```

with `color_type last_fg, last_bg;` added to `WindowBarData` (`kitty/state.h:220-226`). Two
`uint32_t` per window; no new invalidation plumbing; immune to any future colour source.

### 4.4 What makes the OS window render a frame at all

Worth stating because it is what makes requirement (b) — *fixed under scroll* — free. The band is
re-drawn from `srd->geometry` on every frame the OS window renders, and it is **never anchored to a
cell, a graphics placement or a scrollback position**. Scrolling the pane changes the cell
contents; the band's `border_rect` is computed from the window's pixel geometry and is identical
before and after. There is no re-assert timer, no socket, no PNG. That is the whole of (b), and it
falls out of the design rather than being engineered.

Note also `prepare_to_render_os_window` returns
`needs_render || was_previously_rendered_with_layers != os_window->needs_layers`
(`kitty/child-monitor.c:859`) — a *change* in `needs_layers` itself forces a frame. If the band is
placed per §1.4 (outside the layers fork) it does not perturb `needs_layers` at all, so it adds no
frames. If instead it is wired into `screen_needs_rendering_in_layers`, it pins that flag true and
the one-shot extra frame at toggle time is harmless.

---

## 5. Active vs inactive styling — honouring the operator's four colours

### 5.1 What `render_a_bar` takes today

`kitty/shaders.c:848-850`:

```c
#define RGBCOL(which, fallback) ( 0xff000000 | colorprofile_to_color_with_fallback(ui->screen->color_profile, ui->screen->color_profile->overridden.which, ui->screen->color_profile->configured.which, ui->screen->color_profile->overridden.fallback, ui->screen->color_profile->configured.fallback))
    color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
#undef RGBCOL
```

i.e. **the pane's own terminal foreground/background**, forced opaque. Those two values then drive
three things:

- `:856` `draw_window_title(..., fg, bg, ...)` → `cocoa_render_line_of_text(buf, fg, bg, ...)`
  (`kitty/glfw.c:1083-1093`) — both the glyph colour **and** the bar's fill inside the text canvas.
- `:877` `blank_canvas(ui->bg_alpha, bg, false)` — the scissored blank under the bar.
- `:886` `draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f)` —
  border line colour `fg`, fill `bg` (`kitty/shaders.c:313-331`).

So changing `fg`/`bg` at `:849` changes all three coherently. **There is no other colour plumbing
to do.**

### 5.2 The good news: all four options are ALREADY in the C `Options` struct

`kitty/state.h:75-76`:

```c
    color_type url_color, background, foreground, active_border_color, inactive_border_color,
        bell_border_color, tab_bar_background, tab_bar_margin_color,
        window_title_bar_active_foreground, window_title_bar_active_background,
        window_title_bar_inactive_foreground, window_title_bar_inactive_background;
```

converted by `kitty/options/to-c-generated.h:1023-1070` via `color_or_none_as_int`. So
`OPT(window_title_bar_active_background)` is directly readable from `shaders.c` with **no new
option, no new ctype, no Python change.**

Two caveats, both real:

- **`none` encodes as `0`.** `kitty/options/to-c.h:26-29`:
  ```c
  color_or_none_as_int(PyObject *color) { if (color == Py_None) return 0; return color_as_int(color); }
  ```
  So `0` means *unset* and is indistinguishable from `#000000`. The C side must treat `0` as unset,
  exactly as `OPT(cursor_trail_color)` does.
- **The documented fallbacks are NOT reachable from C.** The docs
  (`kitty/options/definition.py:1988-2029`) say each defaults to the corresponding tab-bar colour
  when `none`. I checked: `grep -rn "active_tab_background|active_tab_foreground" kitty/state.h
  kitty/options/to-c-generated.h` returns **nothing** — only `tab_bar_background` reaches C
  (`state.h:75`). So an upstream-quality patch would need to add those four tab colours to the C
  Options too, or fall back to `default_fg`/`default_bg` as today.
  **For this operator it is moot**: `config/kitty.conf` sets
  `window_title_bar_active_background #2f62d8`, `..._active_foreground #ffffff`,
  `..._inactive_background #3f5590`, `..._inactive_foreground #f4f6fd` — all four explicit, so the
  `0` branch is never taken on this machine.

### 5.3 The missing input: `render_a_bar` does not know if the window is active

`UIRenderData` (`kitty/shaders.c:34-42`) has **no** active flag. `draw_cells` receives
`bool is_active_window` and `bool is_single_window` (`:1411`) but uses them only to compute
`current_inactive_text_alpha` (`:1415-1422`) and stores just that float in
`ui.inactive_text_alpha`. Using that float as a proxy for "active" is wrong in two ways: it is
`1.0f` for the tab bar too, and with `inactive_text_alpha 1.0` (a common setting) active and
inactive both read `1.0f`.

**So the plumbing is: add the two booleans to `UIRenderData` and fill them in `draw_cells`.**

### 5.4 The diff

```diff
--- a/kitty/shaders.c
+++ b/kitty/shaders.c
@@ -34,6 +34,7 @@ typedef struct UIRenderData {
     unsigned screen_width, screen_height, cell_width, cell_height, screen_left, screen_top, full_framebuffer_width, full_framebuffer_height;
     Window *window; Screen *screen; OSWindow *os_window;
     GraphicsRenderData grd;
     WindowLogoRenderData *window_logo;
     float bg_alpha, inactive_text_alpha;
     bool has_background_image;
+    bool is_active_window, is_single_window;
     color_type background_color; // RGB only
 } UIRenderData;
```

```diff
@@ -836,7 +837,7 @@
 static unsigned
-render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title, bool along_bottom) {
+render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title, bool along_bottom, bool use_title_bar_colors, bool with_border) {
     unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
-    unsigned bar_height = ui->cell_height + 2;
+    if (!with_border) border_width = 0;                       // §2.2 Cure B: exactly one cell
+    unsigned bar_height = with_border ? ui->cell_height + 2 : ui->cell_height;
     unsigned bar_width = ui->screen_width - 2 * border_width;
@@ -847,9 +848,18 @@
 #define RGBCOL(which, fallback) ( 0xff000000 | colorprofile_to_color_with_fallback(ui->screen->color_profile, ui->screen->color_profile->overridden.which, ui->screen->color_profile->configured.which, ui->screen->color_profile->overridden.fallback, ui->screen->color_profile->configured.fallback))
     color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
 #undef RGBCOL
+    if (use_title_bar_colors) {
+        // OPT() value 0 means "none" (kitty/options/to-c.h:26); fall back to the pane colours.
+        color_type ofg = ui->is_active_window ? OPT(window_title_bar_active_foreground)
+                                              : OPT(window_title_bar_inactive_foreground);
+        color_type obg = ui->is_active_window ? OPT(window_title_bar_active_background)
+                                              : OPT(window_title_bar_inactive_background);
+        if (ofg) fg = 0xff000000 | ofg;
+        if (obg) bg = 0xff000000 | obg;
+    }
-    if (bar->last_drawn_title_object_id != title || bar->needs_render) {
+    if (bar->last_drawn_title_object_id != title || bar->needs_render
+            || bar->last_fg != fg || bar->last_bg != bg) {
         static char titlebuf[2048] = {0};
         if (!title) return 0;
@@ -856,6 +866,9 @@
         if (!draw_window_title(...)) return 0;
         Py_CLEAR(bar->last_drawn_title_object_id);
         bar->last_drawn_title_object_id = Py_NewRef(title);
+        bar->needs_render = false;          // §4.2 — upstream never cleared this
+        bar->last_fg = fg; bar->last_bg = bg;
     }
@@ -884,7 +897,7 @@
-    draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
+    if (with_border) draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
     return border_rect.height;
 }
```

plus, in `draw_cells` (`kitty/shaders.c:1434-1444`), two more initialisers:

```diff
         .inactive_text_alpha = current_inactive_text_alpha, .has_background_image = has_bgimage(os_window),
+        .is_active_window = is_active_window && !is_tab_bar,
+        .is_single_window = is_single_window,
         .background_color = default_bg, .bg_alpha=effective_os_window_alpha(os_window),
```

and the two existing call sites gain `, false, true` (keep today's exact behaviour):
`kitty/shaders.c:929` and `kitty/shaders.c:943`.

**One honest gap:** "active" here means *the tab's active window*, not *the active window of a
focused OS window*. With five OS windows open, all five will paint an active-coloured band. The
real ⌘⌥B bars have the same property (`kitty/tabs.py:1899-1900` picks the active colours from
`opts` with no OS-window focus term), so this matches existing kitty behaviour. If the operator
wants focus-awareness, `ui->os_window->is_focused` is available and would be an `&&`.

---

## 6. All visible windows, or only when >1 is visible?

### 6.1 What kitty's own rule is

`kitty/layout/base.py:404-416`:

```python
min_windows = get_options().window_title_bar_min_windows
visible_groups = tuple(all_windows.iter_all_layoutable_groups(only_visible=True))
force_show = all_windows.force_show_title_bars
show_title_bar = force_show or (min_windows > 0 and len(visible_groups) >= min_windows)
```

So upstream's rule is `min_windows > 0 AND visible >= min_windows`, with `0` meaning **never**
(which is why the operator's config sets `window_title_bar_min_windows 0` and ⌘⌥B flips it to 1).
`force_show_title_bars` is the drag-time override (`kitty/tabs.py:1889-1896`).

### 6.2 Recommendation: draw for ALL visible windows, gated by one new option, default off

The band is not the row-stealing bar and must not inherit its rule. Concretely:

- **Do not reuse `window_title_bar_min_windows`.** It is consumed by the Python *layout* to reserve
  a row; reusing it would couple the free band to the expensive one and make ⌘⌥B and ⌘⇧B fight.
  (The repo has already been bitten by exactly this: `config/kitty.conf` §3's record of the ⌘⌥B /
  ⌘⇧B double-title collision.)
- **Add `window_title_band` (`no`/`yes`, default `no`)** — one new boolean in
  `kitty/options/definition.py` with `ctype='bool'`, readable as `OPT(window_title_band)`. ⌘⇧B then
  becomes a `kitty @ load-config` of a one-line drop-in exactly as ⌘⌥B is today, or better a real
  `toggle_window_title_band` action.
- **Draw it for every visible window when on, including a single pane.** Reasons, in order:
  1. **Requirement (c) needs it.** The hit-test band that gives the hand cursor and the drag must
     exist wherever the user can grab a pane. A single-pane OS window is still draggable *into*
     another OS window — and `mouse_region`'s border arm is itself gated on
     `num_visible_windows(t) > 1` (`kitty/mouse.c:1004`), so with one pane the band is the **only**
     grab surface there would be.
  2. **It costs nothing extra.** The band is drawn inside the pane's own viewport; one pane means
     one band.
  3. **A count-gated band would appear and disappear as panes are split or closed**, which is
     exactly the "it moves / it blinks" complaint that killed the graphics-protocol overlay.
- **Interaction with a single pane:** none of the single-window special-casing bites. `draw_cells`'s
  `is_single_window` argument only feeds `inactive_text_alpha` (`:1418-1421`); it does not gate any
  overlay. `draw_borders` is gated elsewhere (`num_visible_windows`/`draw_minimal_borders`) and the
  band never overlaps a border anyway (§2.3).
- **Do gate on the tab bar.** `draw_cells` is called for the tab bar (`child-monitor.c:906`) and for
  the row-stealing title bar screen (`:919`) with `window == NULL`. The band call must therefore
  begin `if (!ui->window || !ui->window->title) return;` — `is_tab_bar` is not stored in
  `UIRenderData`, but `ui->window == NULL` is exactly the discriminator for both of those calls.
- **And gate on the row-stealing bar being off.** If `window_title_bar_min_windows` is ever ≥1 at
  the same time, both bars would show and the top row would carry the title twice. One line:
  `if (ui->window->window_title_render_data.screen) return;` — the row-stealing bar's screen is
  non-NULL exactly when it is laid out (the same test `child-monitor.c:919` uses).

---

## 7. The patch — drawing half only

Against `~/kitty-482` @ `2cb1d95c3` (v0.48.2). **NOT BUILT, NOT APPLIED** — the brief forbids
building, so this is a reviewed-by-eye diff with exact anchors, not a tested one. Line numbers are
pre-patch v0.48.2 numbers.

Six hunks in three files, plus one new option. The hit test (requirement c) is **not** here.

### Hunk 1 — `kitty/state.h:220-226`, widen `WindowBarData` and add the band's own buffer

```diff
 typedef struct WindowBarData {
     unsigned width, height;
     uint8_t *buf;
     PyObject *last_drawn_title_object_id;
     hyperlink_id_type hyperlink_id_for_title_object;
+    color_type last_fg, last_bg;
     bool needs_render;
 } WindowBarData;
```

```diff
@@ kitty/state.h:276 @@ typedef struct Window {
-    WindowBarData title_bar_data, url_target_bar_data;
+    WindowBarData title_bar_data, url_target_bar_data, top_title_band_data;
```

*Why a new field and not `title_bar_data`: §3.1 — `title_bar_data` is already the shared pixel
buffer for BOTH `draw_window_number` and `draw_hyperlink_target` (`shaders.c:929`, `:943`), and a
third permanently-on consumer would miss the pointer cache every frame.*

### Hunk 2 — `kitty/shaders.c:837-889`, generalise `render_a_bar`

Signature gains two flags; body gains the title-bar colours, the widened cache key, the
`needs_render` clear, and the borderless one-cell mode. Full replacement of `:837-841`,
`:848-859`, and `:884-886` as given in §5.4 and §2.2 Cure B. Restated compactly:

```diff
@@ -836,12 +836,14 @@
 static unsigned
-render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title, bool along_bottom) {
-    unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
-    unsigned bar_height = ui->cell_height + 2;
+render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title, bool along_bottom,
+             bool use_title_bar_colors, bool with_border) {
+    unsigned border_width = with_border ? (unsigned)ceil(thickness_as_float(ui->os_window, 1)) : 0;
+    // with_border: legacy look, border_rect.height == cell_height + 2 + 2*border_width (51px @ cell 45).
+    // !with_border: exactly ONE cell, border_rect.height == cell_height. See §2.2.
+    unsigned bar_height = with_border ? ui->cell_height + 2 : ui->cell_height;
     unsigned bar_width = ui->screen_width - 2 * border_width;
@@ -849,7 +851,16 @@
     color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
 #undef RGBCOL
+    if (use_title_bar_colors) {
+        color_type ofg = ui->is_active_window ? OPT(window_title_bar_active_foreground)
+                                              : OPT(window_title_bar_inactive_foreground);
+        color_type obg = ui->is_active_window ? OPT(window_title_bar_active_background)
+                                              : OPT(window_title_bar_inactive_background);
+        if (ofg) fg = 0xff000000 | ofg;   // 0 == "none", kitty/options/to-c.h:26
+        if (obg) bg = 0xff000000 | obg;
+    }
-    if (bar->last_drawn_title_object_id != title || bar->needs_render) {
+    if (bar->last_drawn_title_object_id != title || bar->needs_render
+            || bar->last_fg != fg || bar->last_bg != bg) {
@@ -857,6 +868,8 @@
         Py_CLEAR(bar->last_drawn_title_object_id);
         bar->last_drawn_title_object_id = Py_NewRef(title);
+        bar->needs_render = false;                  // upstream never cleared this — §4.2
+        bar->last_fg = fg; bar->last_bg = bg;
     }
@@ -884,7 +897,7 @@
-    draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
+    if (with_border) draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
     return border_rect.height;
 }
```

Both existing call sites keep today's behaviour by passing `, false, true`:

```diff
@@ -929 @@ draw_hyperlink_target
-    render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom);
+    render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom, false, true);
@@ -943 @@ draw_window_number
-        title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false);
+        title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false, false, true);
```

### Hunk 3 — `kitty/shaders.c:34-42`, two new `UIRenderData` fields

```diff
 typedef struct UIRenderData {
     unsigned screen_width, screen_height, cell_width, cell_height, screen_left, screen_top, full_framebuffer_width, full_framebuffer_height;
     Window *window; Screen *screen; OSWindow *os_window;
     GraphicsRenderData grd;
     WindowLogoRenderData *window_logo;
     float bg_alpha, inactive_text_alpha;
     bool has_background_image;
+    bool is_active_window, is_single_window;
     color_type background_color; // RGB only
 } UIRenderData;
```

### Hunk 4 — `kitty/shaders.c`, the new draw function (insert after `draw_window_number`, ~`:990`)

```c
static bool
has_window_title_band(const UIRenderData *ui) {
    if (!OPT(window_title_band)) return false;
    // draw_cells is also called for the tab bar and for the row-stealing title-bar
    // screen; both pass window == NULL (kitty/child-monitor.c:906, :919).
    if (!ui->window || !ui->window->visible) return false;
    if (!ui->window->title || !PyUnicode_Check(ui->window->title)) return false;
    // never double up with the row-stealing bar (window_title_bar_min_windows >= 1)
    if (ui->window->window_title_render_data.screen) return false;
    // a pane too short to spare a row for an overlay would hide its only content row
    if (ui->screen_height < ui->cell_height * 2) return false;
    return true;
}

static void
draw_window_title_band(const UIRenderData *ui) {
    if (!has_window_title_band(ui)) return;
    render_a_bar(ui, &ui->window->top_title_band_data, ui->window->title,
                 /*along_bottom=*/false, /*use_title_bar_colors=*/true, /*with_border=*/false);
}
```

*`along_bottom=false` is the top band verbatim — `border_rect.top = ui->screen_top` at
`kitty/shaders.c:871-873`, no arithmetic change (§2.1).*

### Hunk 5 — `kitty/shaders.c:1443-1450`, fill the new fields and call the band

```diff
         .inactive_text_alpha = current_inactive_text_alpha, .has_background_image = has_bgimage(os_window),
+        .is_active_window = is_active_window && !is_tab_bar, .is_single_window = is_single_window,
         .background_color = default_bg, .bg_alpha=effective_os_window_alpha(os_window),
     };
     screen->reload_all_gpu_data = false;
     save_viewport_using_top_left_origin(
         ui.screen_left, ui.screen_top, ui.screen_width, ui.screen_height, ui.full_framebuffer_height);
     if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
     else draw_cells_without_layers(&ui, srd->vao_idx);
+    draw_window_title_band(&ui);
     restore_viewport();
 }
```

**This is the load-bearing placement (§1.4): after the layers fork, so the band works on BOTH
paths and `screen_needs_rendering_in_layers` needs no new arm — the fast direct-to-framebuffer
path survives.**

### Hunk 6 — `kitty/state.c:425-428` and `kitty/dnd.c:2384-2387`, free the new buffer

**Both** sites, identical two lines each:

```diff
     Py_CLEAR(w->url_target_bar_data.last_drawn_title_object_id);
     free(w->url_target_bar_data.buf); w->url_target_bar_data.buf = NULL;
+    Py_CLEAR(w->top_title_band_data.last_drawn_title_object_id);
+    free(w->top_title_band_data.buf); w->top_title_band_data.buf = NULL;
```

`kitty/state.c:418-434` is `destroy_window()`; `kitty/dnd.c:2374-2390` is
`destroy_fake_window_contents()` (the DnD test fake windows — **the brief did not know about this
one**). `grep -n "title_bar_data\|url_target_bar_data" kitty/*.c | grep -v shaders.c` returns
exactly these two sites and nothing else in the C tree, so there is no third place to miss.

### The new option

`kitty/options/definition.py`, beside the `window_title_bar_*` block (`:1941-2031`):

```python
opt('window_title_band', 'no', option_type='to_bool', ctype='bool',
    long_text='Draw each window title as a one-cell-tall band overlaid on the first content row, '
              'outside the cell grid, so it takes no rows and does not shift content.')
```

Then regenerate (`./setup.py build` does the option codegen; `kitty/options/to-c-generated.h` and
`types.py` are generated files). `OPT(window_title_band)` becomes readable from `shaders.c`.

---

## 8. Residuals, refutations, and what the hit-test half needs from this

### 8.1 The design is NOT refuted, with three corrections

| brief's claim | verdict |
|---|---|
| `render_a_bar` draws a one-cell bar outside the grid in the system font as a GL texture | **CONFIRMED** — `shaders.c:837-889`; macOS `draw_window_title` → `cocoa_render_line_of_text`, `glfw.c:1082-1094` |
| existing consumers are `draw_hyperlink_target` and the window-number overlay, via `WindowBarData` on `Window` | **CONFIRMED but sharper** — they share ONE `WindowBarData` (`title_bar_data`); `url_target_bar_data` is only a text cache (§3.1) |
| gives (a) zero rows, (b) fixed, (d) system font "free" | (a) **CONFIRMED**, (b) **CONFIRMED** (§4.4), (d) **CONFIRMED**. **"free" is REFUTED** — three costs: the layers fork (§1.3), per-frame texture churn (§3.3), per-frame CoreText raster from the dead cache (§4.2). Each is fixable inside this patch; none is free. |
| the geometry needs working out for a top band | **REFUTED, in the good direction** — `along_bottom=false` IS the top band already (§2.1) |
| a 1-cell bar | **REFUTED** — it is `cell_height + 2 + 2*border_width` = **51 px** against a 45 px cell, overhanging row 2 by 6 px (§2.2) |

### 8.2 Ranked residual risks

1. **sRGB on the non-layered path — the only thing that can sink the §1.4 placement.** `blank_canvas(..., false)` writes linear colour; the default framebuffer wants sRGB. UNMEASURED. If it cannot be made right, fall back to the layered wiring and accept the blit.
2. **`needs_render = false` could make an existing bar stale.** Reasoned safe (§4.2) but UNMEASURED; check by resizing a pane with the URL bar showing.
3. **Every title change re-rasterises** because the cache key is a `PyObject *` identity, not the string value (§4.1). A shell re-emitting an identical OSC 2 per prompt pays a CoreText raster per prompt. Acceptable; noted so it is not mistaken for a leak.
4. **`window_title_bar_align` is ignored.** `draw_window_title` takes no alignment and `render_a_bar` prefixes a single space (`shaders.c:855`, `" %s"`), i.e. hardcoded left. The operator's config is `window_title_bar_align left`, so **this happens to be exactly right today** and would need work only if centre/right are ever wanted.
5. **Title truncation** is whatever `cocoa_render_line_of_text` does when the text exceeds `bar_width`; `render_a_bar` passes `actual_width = NULL` (`:856`) so the `cocoa_text_width_for_single_line` measuring branch at `glfw.c:1086-1090` is skipped. UNMEASURED — likely a hard clip, not an ellipsis.
6. **Linux/Wayland.** `draw_window_title`'s non-Apple branch is `kitty/glfw.c:1138`. Not read; irrelevant to this operator but relevant to an upstream PR.

### 8.3 What the hit-test half (requirement c) needs from this patch, and why it is genuinely separate

The brief's analysis of `mouse_region` is **CONFIRMED**. `kitty/mouse.c:1067-1081`:

```c
for (unsigned int i = 0; i < t->num_windows; i++) {
    Window *win = t->windows + i;
    if (contains_mouse(win) && win->render_data.screen) {
        ans.window_idx = i; ans.window = win; break;
    } else if (detect_title_bar && win->visible) {
        const WindowRenderData *trd = &win->window_title_render_data;
        ...
```

and `contains_mouse` (`:270-273`) tests the **padded** rect,
`geometry.left - padding.left … geometry.bottom + padding.bottom` (`:249-267`). Our band sits at
`geometry.top`, strictly inside that rect, so `contains_mouse` wins and the `else if` title-bar arm
is **structurally unreachable**. No Python monkeypatch can change it.

**The drawing half exports exactly one thing the hit test needs: the band's height.**
`render_a_bar` already returns `border_rect.height` (`shaders.c:888`), and with Hunk 2's
`with_border=false` that is exactly `ui->cell_height`. So the hit-test patch needs no new geometry
field — it can compute the band rect from data it already has:

```
band = { .left   = w->render_data.geometry.left,
         .top    = w->render_data.geometry.top,
         .right  = w->render_data.geometry.right,
         .bottom = w->render_data.geometry.top + os_window->fonts_data->fcm.cell_height }
```

and must be tested **before** `contains_mouse(win)` in the `:1067` loop, i.e. a new first arm, not
a new `else if`. That is the C change; it is the sibling session's `mouse_drag_window` axis and is
deliberately not in this patch.

**A cheaper interim that needs no hit-test change at all:** the sibling's
`docs/patches/kitty-mouse-drag-window-v0.48.2.patch` adds a `mouse_drag_window` action that can
start a drag from N rows at the top of a window. Bound to a plain `mouse_map left press`, that
gives the *drag* from the band's rows without touching `mouse_region` — leaving only the **hand
cursor** unserved, which is a `set_cursor_shape` call keyed on the same rect. UNMEASURED: I did not
read that patch (brief says do not edit that worktree; I did not read it either, so this is an
inference from the brief's description of it, not a citation).

### 8.4 Requirement scorecard for the drawing half alone

| req | status after this patch |
|---|---|
| (a) toggles with no top margin, no content shift | ✅ — band is drawn over content row 1, grid untouched, no PTY resize, no SIGWINCH |
| (b) fixed under scroll | ✅ — redrawn per frame from pixel geometry, never cell-anchored, no re-assert timer |
| (c) hand cursor + draggable | ❌ — needs the `kitty/mouse.c` change in §8.3. Not in this patch. |
| (d) SF Pro Semibold, not Monaco | ✅ — `cocoa_render_line_of_text` (`kitty/glfw.c:1093`), CoreText system font, free |
| "zero latency / memory pressure" | ⚠️ — only if §1.4's placement holds (no layers blit), §4.2's one-line cache fix lands, and the per-frame texture churn in §3.3 is addressed. Each is CONFIRMED as a code path; none is measured. |

---

## Appendix A — every command run, so each claim is re-derivable

All run with cwd `~/kitty-482` unless the command says otherwise. Nothing was built; no kitty
instance was written to; the live instance (pid 597) was never touched, read or signalled.

```bash
# tree identity
git log --oneline -1                      # => 2cb1d95c3 version 0.48.2
cd ~/kitty-dev && git log --oneline -1    # => 1d67ecd47 Merge branch 'fix-mimepat-guess-mime-type' ...

# §1 the draw path
grep -n "render_a_bar" kitty/*.c kitty/*.h
#  => shaders.c:837 (def), :928-929 (draw_hyperlink_target), :943 (draw_window_number) — 2 callers only
grep -n "draw_cells(" kitty/*.c
#  => child-monitor.c:906, :915, :919 ; shaders.c:1411 (def)
sed -n '1344,1348p' kitty/shaders.c       # draw_cells_without_layers — 3 lines, cells only
sed -n '1358,1384p' kitty/shaders.c       # draw_cells_with_layers — all 6 overlays live here
sed -n '1315,1320p' kitty/shaders.c       # screen_needs_rendering_in_layers — the has_ui OR-chain
sed -n '756,760p'  kitty/child-monitor.c  # needs_layers base condition
sed -n '1638,1692p' kitty/shaders.c       # start/stop_os_window_rendering — the offscreen FBO + blit
sed -n '684,694p'  kitty/shaders.c        # setup_texture_as_render_target — GL_RGBA16

# §2 geometry
sed -n '837,889p' kitty/shaders.c         # render_a_bar body incl. border_rect at :871-873
sed -n '304,310p' kitty/shaders.c         # thickness_as_float = pts * dpi / 72
sed -n '231,233p' kitty/options/definition.py   # box_drawing_scale default '0.001, 1, 1.5, 2'
grep -n "typedef struct Viewport" kitty/gl.h    # :32  {unsigned left, top, width, height}
sed -n '249,273p' kitty/mouse.c           # window_left/top/right/bottom = geometry -/+ padding

# §3 WindowBarData
sed -n '220,226p' kitty/state.h ; sed -n '276p' kitty/state.h
grep -n "title_bar_data\|url_target_bar_data" kitty/*.c | grep -v shaders.c
#  => EXACTLY 2 free sites: state.c:425-428 (destroy_window), dnd.c:2384-2387 (fake windows)

# §4 the cache bug — the load-bearing negative
grep -n "needs_render" kitty/shaders.c
#  => :847 set true, :852 test.  No other WindowBarData write.
grep -rn "needs_render = false" kitty/
#  => cursor_trail.c:149, child-monitor.c:755 ONLY — neither is a WindowBarData.
cd ~/kitty-dev && grep -n "needs_render" kitty/shaders.c
#  => :1264 set true, :1275 test — same bug on master.

# §5 colours
grep -n "window_title_bar" kitty/state.h                      # :76 — all four ARE in C Options
grep -rn "window_title_bar_active_background" kitty/options/to-c-generated.h | head
sed -n '26,29p' kitty/options/to-c.h                          # color_or_none_as_int: None => 0
grep -rn "active_tab_background\|active_tab_foreground" kitty/state.h kitty/options/to-c-generated.h
#  => NOTHING. The documented `none` fallbacks are unreachable from C.
sed -n '1988,2031p' kitty/options/definition.py               # the four opts + their doc'd fallbacks

# §6 when to show
sed -n '404,416p' kitty/layout/base.py    # show_title_bar = force_show or (min_windows>0 and visible>=min)
sed -n '1889,1900p' kitty/tabs.py         # force_show_title_bars during a drag
grep -rn "window_title_band" kitty/       # empty => the new option name is free

# §8 hit test
sed -n '1067,1081p' kitty/mouse.c         # contains_mouse FIRST, title-bar band only in the else-if
sed -n '270,273p'  kitty/mouse.c          # contains_mouse
```

## Appendix B — what I did NOT do

- **Did not build.** Every performance claim is a code-path claim, not a measurement. Explicitly
  UNMEASURED: the layered-vs-direct frame cost; whether `global_state.supports_framebuffer_srgb` is
  true on this box (if false, `needs_layers` is already always on and §1.3's objection dies);
  whether `blank_canvas(..., false)` renders correctly on the non-layered path; whether clearing
  `needs_render` staleness-breaks the URL bar; the CoreText raster cost per frame.
- **Did not touch the live kitty** (pid 597) in any way — not even a read-only `kitty @ ls`. Nothing
  in this axis required it.
- **Did not run `./autoformat`** or any formatter.
- **Did not read** `docs/patches/kitty-mouse-drag-window-v0.48.2.patch` or enter
  `/Users/chrisren/Development/.worktrees/kitty-drag-impl` — the brief says do not edit it, and
  reading it was not needed for the drawing half. §8.3's remark about it is therefore an inference
  from the brief's own description, marked as such.
- **Did not read** the non-Apple branch of `draw_window_title` (`kitty/glfw.c:1138`).

---

## ADVERSARIAL VERIFICATION

**Verifier:** adversarial pass, 2026-09-16. **Method:** every cited `file:line` re-opened in the tree
it names (`~/kitty-482` @ `2cb1d95c3` = v0.48.2, the build the operator runs; `~/kitty-dev` @
`1d67ecd47`). Nothing was built — the brief forbids it — so every statement below is either a code
read or an explicit "could not measure". No write of any kind reached the live instance (pid 597);
the single read used was `kitty @ --to unix:/tmp/kitty-597 ls`.

**Verdict in one line:** the design survives, the placement decision survives and is strengthened,
but **claim 9 is refuted and would have shipped a black-on-black band to anyone on a stock config**,
and **claim 5's "build once and look" gate is the wrong instrument** — the answer is derivable from
two positive controls in the same file, and the residual risk the gate guarded against cannot occur.

### Upheld, citation-exact

| # | Status | Note |
|---|---|---|
| 1 | **UPHELD verbatim** | `shaders.c:871-873` is exactly as quoted; `:943` passes `false`. Top band is free. |
| 2 | **UPHELD**, line drift | `draw_cells_without_layers` is `:1344-1347` (not `-1348`); the six overlay calls are `:1377-1382` (not `-1383`). `grep -n render_a_bar kitty/*.c` ⇒ `:837, :929, :943` and nothing else. Population is complete in both trees (dev: `:1254, :1353, :1367`). |
| 3 | **UPHELD**, mechanism and every line | `:1315-1320`, `child-monitor.c:770/781/786`, `shaders.c:1638-1667`, `:1670-1692`, `:693-694` (`GL_RGBA16`) all read as claimed. Magnitude remains unmeasured, correctly flagged. |
| 4 | **UPHELD and strengthened** | Two facts the report did not check, both favourable: (a) `save_viewport_using_top_left_origin` / `restore_viewport` are a genuine **16-deep stack** (`gl.c:140-181`, `fatal()` on overflow), so nesting inside the `:1446`/`:1450` pair is safe by construction rather than by luck; (b) `draw_borders` runs at `child-monitor.c:904`, **before** every `draw_cells` at `:906/:915/:919`, so a band drawn in `draw_cells` correctly overdraws the border rather than being overdrawn by it. |
| 6 | **UPHELD verbatim** | `:916` `bd = &window->url_target_bar_data`, `:929` renders through `&window->title_bar_data`. A third permanently-on consumer would thrash the shared cache. |
| 7 | **UPHELD in both trees** | v0.48.2 `:847` set true / `:852` test; dev `:1264` / `:1275`. A tree-wide `grep -rn "needs_render"` finds **no** `bar->needs_render = false` anywhere in either tree — the only clears are `cursor_trail.c` and `child-monitor.c`, neither a `WindowBarData`. Cache is dead; CoreText re-rasterises every rendered frame. |
| 10 | **UPHELD verbatim** | `UIRenderData` at `:34-42` has no active flag; `:1415-1422` is the only use of `is_active_window`/`is_single_window`. |
| 11 | **UPHELD verbatim** | Exactly two free sites: `state.c:425-428`, `dnd.c:2384-2387`. |
| 12 | **UPHELD verbatim** | `mouse.c:1067-1081` and `:249-273` read exactly as described. `contains_mouse` uses the padded rect; the title-bar arm is structurally unreachable. |
| 13 | **UPHELD**, mechanism | `ui.screen_left/screen_top` come from `srd->geometry` (`:1439`); `border_rect` derives from those alone. No cell anchor, no placement, no timer. |

### OVERTURNED — 1. Claim 9 is false for every stock config, and the report's evidence could not have said so

> *Claimed:* "All four `window_title_bar_*` options are ALREADY in the C Options struct, so honouring
> them is a 2-line change … no new plumbing."

Three independent defects:

1. **All four options default to `none`**, and `color_or_none_as_int` (`kitty/options/to-c.h:26-29`)
   maps `Py_None` → **`0`**, which in `color_type` is indistinguishable from `#000000`. A C-side
   `OPT(window_title_bar_active_background)` on a stock config returns **black**.
2. **The documented fallback is Python-only and its source is not in C.** `definition.py:1990-2028`
   says each option "Defaults to the corresponding tab bar color … when set to `none`", and that
   resolution lives at `kitty/window_title_bar.py:33-36` (`_resolve_color`), used at `:53-56` and
   `tabs.py:1900`. `grep -n 'active_tab_background\|active_tab_foreground\|inactive_tab_background\|inactive_tab_foreground' kitty/state.h kitty/options/to-c-generated.h` returns **nothing** — the
   four fallback colours are **not in the C `Options` struct at all**. There is no C-side fallback to
   reach for.
3. **`fg`/`bg` in `render_a_bar` is shared by all three consumers.** Changing it at `:850` recolours
   the URL bar (`:929`) and the window-number bar (`:943`) too. It must become a parameter.

**Why the report did not see it:** the claim was validated against a config that sets all four
options (`config/kitty.conf`), i.e. the one configuration in which the defect is invisible. The
evidence could not have come out the other way.

**Corrected claim 9.** Honouring the four colours is **not** a 2-line change and is **not** free.
The band must resolve `0` to something, and the only three honest options are:
(a) fall back to the screen colour profile's `default_fg`/`default_bg` that `render_a_bar` already
computes at `:849-850` — ~4 lines, safe, but the band is then terminal-coloured rather than
tab-bar-coloured (a different, defensible design, and the one that ships correctly for users who
configure nothing); (b) add `active_tab_*`/`inactive_tab_*` to the C `Options` struct and replicate
`_resolve_color` in C — correct, but new plumbing in `definition.py` + `to-c-generated.h`;
(c) resolve in Python and push four already-resolved colours to C. Plus, in all three cases, a new
`fg`/`bg` (or `is_active`) parameter on `render_a_bar` and its two existing call sites.
**On this operator's box (a) and the naive version both work, because all four are set — so a build
on this machine cannot falsify this. Do not let it.**

### OVERTURNED — 2. Claim 5's gate is the wrong instrument, in the expensive direction

> *Recommended:* "GATE: … Build once and look at the band's background; if it is wrong, pass
> `for_final_output = !ui->os_window->needs_layers` … If that proves intractable, fall back to the
> four-line layered wiring and accept the blit."

Two corrections, both of which remove the gate:

**(a) It is not a coin flip — the same file states the rule twice, in code.** `blit_fragment.glsl`
calls `linear2srgb(...)` explicitly, which is positive proof the layer texture holds **linear**
values and that the layered path's `blank_canvas(..., false)` is correct *because of that*. The
matching negative control is `draw_borders` at `shaders.c:1502-1504`:
`if (!w->needs_layers) glEnable(GL_FRAMEBUFFER_SRGB);` … `glDisable`, and `call_cell_program` at
`:1339-1341` doing the same on `for_final_output`. Those are kitty saying, in two places, *"on the
non-layered path you must enable sRGB."* A band drawn there without it writes linear values raw and
renders **too dark** (e.g. `#2f62d8` → linear ≈ `(0.0295, 0.1274, 0.6795)` → written as ≈ `#0821ad`).
This is derivable; it does not need a build to decide.

**(b) The fallback the gate protects is unreachable, and the bug is worse than "might look wrong".**
`child-monitor.c:757-759` — cited by claim 3 but evidently not read — is:

```c
os_window->needs_layers = (
    !global_state.supports_framebuffer_srgb || effective_os_window_alpha(os_window) < 1.f ||
    os_window->live_resize.in_progress || (background_image_for_os_window(os_window) != NULL));
```

Three consequences. First, `!supports_framebuffer_srgb` **forces** the layered path, so the
non-layered path is only ever taken on hardware where `GL_FRAMEBUFFER_SRGB` works — the proposed fix
is *guaranteed available*, and "if that proves intractable" names an impossibility. Second,
`alpha < 1.f` also forces layers, so on the non-layered path `ui->bg_alpha` is always `1.0f`, which
retires the premultiply-vs-alpha question there. Third, and the real cost: **`needs_layers` is
recomputed every frame and ORed over the tab bar and every visible window**, so an unfixed band does
not merely "look wrong" — it **changes colour at runtime** whenever an unrelated pane gains or loses
an image, a scrollbar, a progress bar or a hyperlink hover. That is a far sharper reason to fix it
than the report gives.

**Corrected recommendation.** Implement the sRGB handling **in the same commit as the placement**, not
behind a gate: thread `for_final_output = !ui->os_window->needs_layers` into `render_a_bar`, pass it
to `blank_canvas`, and bracket the `draw_graphics` and `draw_rounded_rect` calls with
`glEnable/glDisable(GL_FRAMEBUFFER_SRGB)` exactly as `draw_borders` does. **Build to verify, never to
decide.** The layered-wiring fallback should be struck from the plan: it costs the blit the operator's
latency clause forbids and it is not needed.

### OVERTURNED — 3. Correction (1) is a *dependant* of correction (3), not a sibling

`ensure_ui_font` (`kitty/core_text.m:922-928`) caches **one global** `CTFontRef system_ui_font` keyed
on `static size_t for_height`, re-creating it (`CTFontCreateUIFontForLanguage` +
`CTFontCreateCopyWithAttributes`) whenever the requested height differs. Setting the new band to
`cell_height` (45) while the URL bar and window-number bar keep `cell_height + 2` (47) puts **two
heights in one frame**, so any frame rendering both re-creates the system font twice.

That is harmless *only once claim 7's `bar->needs_render = false` lands*, because the cached path
never calls `draw_window_title` at all. **Correction (3) is therefore a prerequisite of correction
(1)** — landing (1) alone makes the very per-frame CoreText cost (3) exists to remove strictly worse.
The report presents them as three independent folds.

### New risks the report does not name

1. **`GRAPHICS_PROGRAM` is the wrong program for this texture.** `shaders.py:213-216` compiles
   `GRAPHICS_PROGRAM` with `is_premult=False` ⇒ `TEXTURE_IS_NOT_PREMULTIPLIED=1` ⇒
   `graphics_fragment.glsl:24` **re-premultiplies**. But `cocoa_render_line_of_text` creates its
   context with `kCGImageAlphaPremultipliedLast` (`core_text.m:948`) — already premultiplied. The
   double-premultiply is masked today only because `render_a_bar` forces `bg = 0xff000000 | …`
   (`:850`), making alpha 1 everywhere. **Consequence for this design:** the band can never be made
   translucent without switching to the existing `GRAPHICS_PREMULT_PROGRAM`. Record it as a
   constraint; do not "fix" it blind, since flipping the program changes the URL bar too.
2. **The scorecard's "(a) zero rows / no shift" omits that the band OCCLUDES content row 1.** True of
   the current PNG overlay too, so it is an accepted design point — but it must be stated, because
   "no layout shift" and "nothing is hidden" are different claims and only the first is delivered.
3. **`ui->screen_top` is the cell-grid top, which excludes padding.** At the operator's
   `window_padding_width 0 5 0 5` this is the pane's visual top and all is well. With any non-zero
   top padding the band floats below the pane's visual edge, leaving an unpainted padding strip above
   it. One line in the option's docs, or clamp to `screen_top - padding.top`.

### What I could not measure, and am not going to pretend otherwise

Claim 8's headline **51 px** is arithmetically confirmed from code — `bar_height = cell_height + 2`
(`:839`), `border_rect.height = bar_height + 2*border_width` (`:871`), `border_width =
ceil(box_drawing_scale[1] * dpi / 72)` (`:838` + `:305-310`), `box_drawing_scale` level 1 = `1` pt
(`options/definition.py:232-233`) — but it rests on `cell_height = 45` and `dpi = 144`, which the
report took from the brief and **so did I**. The only sanctioned read of the live instance,
`kitty @ --to unix:/tmp/kitty-597 ls`, reports `columns`/`lines` per window and **no pixel geometry
and no dpi at all**; I dumped every scalar key in its JSON to confirm that. The instrument cannot
answer the question. The *structure* — one cell plus 2 px plus twice the border width — is confirmed
and is what the `with_border=false` correction acts on; the number 51 is conditional on the brief.
