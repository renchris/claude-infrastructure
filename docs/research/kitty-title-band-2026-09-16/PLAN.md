# The kitty pane title band — implementation plan

Synthesis of the 12-axis wave in this directory. Every axis file is cited by name; nothing here
restates one. Claims marked **[V]** were re-verified by me against `~/kitty-482` @ `2cb1d95c3`
(tag v0.48.2 — the build the operator actually runs) while writing this; everything else carries
its axis citation.

---

## 0. VERDICT

**(a), (b) and (c) can all be met, together, by one C patch to v0.48.2; (d) is met at the wrong
weight for free and needs three more edits plus one operator ruling.** The mechanism is the lead's
design, corrected in four places: the band is drawn by `render_a_bar` from `draw_cells` **after**
the layers fork (not inside `draw_cells_with_layers`), it gets its **own** `WindowBarData`, the
dead `needs_render` cache is repaired **first**, and `tabs.py`'s force-show loop is **suppressed**
or requirement (c) breaks requirement (a) on every drag.

| | Met | By what | Residual |
|---|---|---|---|
| **(a)** zero top margin, zero shift | **YES** | band drawn outside the cell grid over content row 1; no `render_ynum -= 1`, no PTY resize, no SIGWINCH | row 1 is **covered**, not moved. Worst stratum measured: **3 of 4** live panes are alt-screen TUIs where row 1 is permanently occupied (`redteam.md` verification; my own live `kitty @ ls` below) |
| **(b)** fixed under scroll | **YES, free** | `border_rect` is derived every frame from `srd->geometry` (pixels), never from a cell, a placement or a scrollback offset — `render-a-bar.md` claim 15 **[V]** shaders.c:871-873 ← :1434-1444 | none. This is the requirement today's PNG overlay structurally cannot meet (`live-deploy.md` verification: placements are scrolled by `grman_scroll_images` from the C parser path and Python has no hook) |
| **(c)** hand cursor + drag + no-op persistence | **YES** | a new FIRST arm in `mouse_region()`'s per-window loop setting `ans.in_title_bar`, keyed on a new `Window.title_band_height` that the painter writes. No-op persistence is **free** because the state lives in an option, not in `force_show_title_bars` (`drag-semantics.md` claim 8) | top **12 px** of the band is the border-resize handle (`window_drag_tolerance 6` pt @144 dpi) — pre-existing, unchanged; presses in the band do not reach the application; row-1 text selection is lost while the band is up |
| **(d)** SF Pro Semibold | **PARTIAL free / full = 3 edits + 1 ruling** | `render_a_bar` → `draw_window_title` → `cocoa_render_line_of_text` is CoreText, not the cell font. But it is **`kCTFontUIFontSystem` at REGULAR weight** (`font.md` claim 2), sized from the band's pixel height alone, giving worst-case ink/band **0.979** — *tighter than the 0.93 the operator rejected in writing as "oversized to its container"* | Semibold + a decoupled font box + a band-height option. §4 files this as a class-C decision with a contact sheet, because at a one-cell band you can have his accepted air **or** his accepted cap height, not both |

**The structural problem, stated plainly: none of this can be live in pid 597.** A C patch needs a
rebuilt binary and `kitty @ load-config` reaches options, fonts and keymaps only (`redteam.md` F14).
§5 gives the best no-restart behaviour — which is better than the brief assumed, because a Python
route to (c) exists and was measured — and §6 gives a switchover that never takes more than one
session down at a time. **The live fleet is 2 OS windows / 4 panes, not the brief's 5 / 9** — I
re-read it: `osw 4` (77×47, 77×47), `osw 5` (51×47, 103×47), three of the four in alternate screen.

---

## 1. RULINGS — where the axes disagreed

### R1. Placement: `draw_cells`, after the fork — NOT `draw_cells_with_layers`, NOT `has_ui`
`render-a-bar.md` (claim 4), `redteam.md` (F1 + MUST 1) and `toggle-liveness.md` (claim 5) converge,
and `toggle-liveness` alone got it wrong on the remedy — it prescribes adding `has_title_band(w)` to
the `has_ui` disjunction. **[V]** That would pin `os_window->needs_layers` true forever
(shaders.c:1316-1319, ORed at child-monitor.c:770/781/786), costing a full-viewport offscreen render
+ blit every frame for every OS window — forbidden by the goal's own latency clause. The band also
must not live *inside* `draw_cells_with_layers`, or it draws only when something else happens to
force layers on, which on this box is *the PNG daemon being replaced* (`redteam.md` F1 corollary:
the diff that deletes 1179 lines of Python is the diff that makes the band invisible).

**[V]** The correct site is between shaders.c:1449 and :1450 — after the if/else, inside the
existing `save_viewport_using_top_left_origin` / `restore_viewport` pair:
```
1448:    if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
1449:    else draw_cells_without_layers(&ui, srd->vao_idx);
   +     draw_window_title_band(&ui);          /* <-- here */
1450:    restore_viewport();
```
`render_a_bar` manages its own scissor and viewport absolutely from `ui->screen_left/top` against
`full_framebuffer_height`, so it is correct anywhere inside that pair.

### R2. sRGB: implement it, do not gate on it
`render-a-bar.md` shipped a GATE ("build once and look; if wrong, fall back to the layered wiring
and accept the blit"). Its verifier overturned that and is right. **[V]** `draw_borders` already
does the exact dance at shaders.c:1502-1504 (`if (!w->needs_layers) glEnable(GL_FRAMEBUFFER_SRGB)`),
and `blank_canvas` branches linear-vs-sRGB on `for_final_output` (shaders.c:1386-1398). **[V]** The
escape hatch the gate protects is unreachable: on macOS `global_state.supports_framebuffer_srgb` is
**hardcoded true** (gl.c:70-75), so the only hardware that would force layers anyway does not exist
here. And `needs_layers` is recomputed **every frame** and ORed over all visible windows
(child-monitor.c:756-786), so an unfixed band would change colour at runtime when an unrelated pane
gains an image. **Implement the bracket in the same commit as the placement. Strike the
fall-back-to-layered escape from the plan entirely.**

### R3. The four `window_title_bar_*` colours ARE in the C Options struct — their FALLBACK is not
`render-a-bar.md` claim 9 and `font.md` claim 12 say the four colours are already in C; the
render-a-bar verifier says they are "NOT in the C Options struct at all". **[V] The verifier's
summary sentence is wrong and its evidence is right about a different thing.** state.h:75-76
declares all four `window_title_bar_{active,inactive}_{foreground,background}` as `color_type`, and
`to-c-generated.h:1036-1044` converts them. What is **not** in C is the documented *fallback* —
`active_tab_background` / `inactive_tab_foreground` etc. have no C field — and
`color_or_none_as_int` maps `none → 0`, indistinguishable from black.

**Ruling:** honour the four options; treat `0` as unset and fall back to the screen colour
profile's `default_fg`/`default_bg` that `render_a_bar` already computes at shaders.c:849-850.
~4 lines, correct for this operator (who sets all four) and correct-if-different for a stock
config. Document the divergence from the Python fallback chain in the option's `long_text`. Do
**not** replicate `_resolve_color` in C for a first cut.

### R4. The hit test: a new `in_title_bar` arm — NOT the `update_mouse_pointer_shape` pixel test
This is the central disagreement. `hit-test.md` and `drag-semantics.md` want a new first arm in
`mouse_region()`'s loop setting `ans.in_title_bar`. The `prior-art.md` **verifier** overturns that,
arguing the band must LOSE the hit test so presses keep flowing through `opts.mousemap` to the
sibling's `mouse_drag_window` action, with the hand supplied by a `get_scrollbar_hit_type`-style
pixel test in `update_mouse_pointer_shape`'s `else if (r.window)` arm.

**I rule for `hit-test.md`, on evidence the prior-art verifier did not weigh.** **[V]** I read the
sibling action's own body: `# Returning True means the press was not consumed and is passed on.`
A `mouse_map` **replaces** the default action for that chord, and `return True` passes the press to
the *child program* — it does **not** fall through to `mouse_selection normal`. So binding
`mouse_map left press ungrabbed mouse_drag_window 1` breaks text selection in the whole pane, and
the prior-art route is therefore only bindable on a **modifier chord** (`cmd+shift+left`, per that
axis's own overturn — `cmd+left press` shadows the operator's live link-click map at
config/kitty.conf:821). Requirement (c) says *"shows a MOUSE HAND on hover and is DRAGGABLE"* — a
title bar you grab, not a chord you learn. The `in_title_bar` route delivers that with a plain
unmodified left-drag and needs no new drag code at all: **[V]** mouse.c:1362-1368 already routes to
`handle_window_title_bar_mouse`, which arms and starts the drag in tabs.py:1853-1877.

The prior-art verifier's real contribution stands and is folded in as a **complement, not a
substitute**: the sibling's `mouse_drag_window` on `cmd+shift+left` keeps working *below* the band
and is the only drag available before the rebuild (§5).

**Shape of the arm** (taking `hit-test.md`'s design, including its verifier's corrections):
key it on a new `unsigned Window.title_band_height` that `render_a_bar` itself writes (0 on every
not-drawn path), **not** on `OPT(...)` — one struct-local load on the hottest path, zero
painter/hit-test drift, and an inertness proof that needs no geometry argument. Add it as a new
first arm **inside** the loop, do **not** reorder the existing `else if`. The naive reorder would
in fact *fix* a pre-existing upstream bug (at `padding.top >= cell_height` the stolen-row bar is
wholly undraggable — hit-test verifier), but that is a separate upstream fix, not this feature.

### R5. `needs_render` first, `with_border=false` second — they are dependent, not sibling
`render-a-bar.md` listed three "independent" corrections; its verifier ordered them and is right.
**[V]** Tree-wide, `WindowBarData.needs_render` is set true at shaders.c:847 and :925 and is set
false **nowhere** (the only `needs_render = false` in the tree are child-monitor.c:755 (OSWindow)
and cursor_trail.c:149). So the title cache is dead and CoreText re-rasterises every rendered
frame today. `ensure_ui_font` (core_text.m:922-928) caches **one** global `CTFont` keyed on a
static height, so a 45 px band beside a 47 px URL bar would re-create the system font twice per
frame unless the cache is repaired first. **Order: needs_render clear + cache-key widening →
then the geometry change.**

### R6. Its own `WindowBarData`, and the reason is upstream correctness, not measured thrash
**[V]** Both existing consumers render into `window->title_bar_data` (shaders.c:929 — the URL bar,
which keeps *state* in `url_target_bar_data` but renders through the other; and shaders.c:943 — the
window-number overlay). A third, permanently-on consumer sharing it is wrong. `perf.md`'s verifier
correctly narrows the *measured* harm (the window-number overlay renders the identical title
object and does not thrash; only the URL bar does, and only under `show_hyperlink_targets cmd`,
which this operator sets). Add `WindowBarData title_band_data` at state.h:276 and free it in
**both** state.c:425-428 and dnd.c:2384-2387 **[V]** — those are the only two sites in the tree.

### R7. Perf: the cache fix is not optional, it is the difference between a win and a regression
`perf.md` claimed the fix "removes" the cost (0.011 µs); its verifier measured the real post-fix
steady state at **6.9–8.6 µs/pane/frame** and today's in-situ pre-fix cost at **136.5 µs** (worse
than `perf.md`'s 109.9, because kitty deletes a texture an in-flight draw still references).
Fleet arithmetic on the live layout: **572.7 µs/fleet-frame unfixed → 29.0 µs fixed**, i.e. 3.58%
→ 0.18% of a core at the 62.5 fps ceiling. **Unfixed, the band is WORSE than the 3.3% Python
daemon it retires.** Take the verifier's numbers. `perf.md`'s step 6 (teardown in
`release_gpu_resources_for_window`) is right; **[V]** its stated reason is vacuous — that function
is *called by* `destroy_window` at state.c:429, so both context-free callers reach it anyway. Keep
the placement, write the guard as `if (bar->texture_id)`, and state the real invariant: every
context-free path is necessarily preceded by a context-ful release that zeroed the id.

### R8. Suppressing the force-show loop is a REQUIRED edit, not a residual
Three axes found it independently (`drag-semantics.md` claim 6, `redteam.md` F9, `hit-test.md`
verification) and one of them ranks it as the single most expensive miss. **[V]** tabs.py:1889-1896:
`start_window_drag` iterates **every tab of every tab manager** and, when
`not (min_w > 0 and visible >= min_w)` — always true at the operator's `window_title_bar_min_windows 0`
— sets `force_show_title_bars = True` and relayouts. That is the real one-row bar, i.e. a PTY resize
and SIGWINCH for every pane in the fleet, twice per drag. **Requirement (c) would break requirement
(a) on every drag without this edit.** The band is already the drop-target affordance those forced
bars exist to provide.

### R9. The band is 51 px, not one cell — parameterise it
**[V]** shaders.c:838-839: `border_width = ceil(thickness_as_float(os_window, 1))` = 2 px
(`box_drawing_scale[1]` = 1 pt @144 dpi — **not** `window_border_width`, which `prior-art.md`'s
verifier corrected), `bar_height = cell_height + 2`, and `border_rect.height = bar_height +
2*border_width` = 45+2+4 = **51 px**. It covers content row 1 plus the top 6 px of row 2, clipping
row 2's ascenders and painting a 2 px rounded stroke into it. Add a `with_border` mode: border 0,
`bar_height = cell_height`, no `draw_rounded_rect` → exactly 45 px. Do **not** use
`box_drawing_scale` level 0 to zero it (`font.md` claim 14: 0.002 px still resolves to non-zero
alpha at full draw-call cost).

### R10. Option shape: a NEW boolean `window_title_band`, overruling `clean-code.md`'s enum
`clean-code.md`'s verifier ruled A1 — extend `window_title_bar` to
`top|bottom|overlay-top|overlay-bottom` with a ctype, citing `progress_bar` as the structural twin.
That argument is good for a stock upstream world and wrong for ours, for one reason it does not
address: **the band and ⌘⌥B's real bars must coexist and arbitrate.** The C guard that prevents
double-titling is `if (ui->window->window_title_render_data.screen) return;` (the same non-NULL
test child-monitor.c:919 uses), which requires the two features to be *independent* values. An enum
on one option cannot express "band on, Screen bar also available on a different chord". A new
`bool window_title_band` (definition.py `option_type='to_bool', ctype='bool'`, plus
`bool window_title_band;` in state.h's `Options`) also degrades safely on a stock binary: an
**unknown option name** is one accumulated bad line, whereas a rejected enum *value* leaves
`window_title_bar` at its meaningful default. Note `clean-code.md`'s measured hazard and why it
cannot bite us: we never set `window_title_bar_min_windows 1` under this design, so the
`overlay-top + min_windows 1 → top + min_windows 1 → reserved rows everywhere` degrade has no path.

The option is needed on **both** sides of the boundary — C for the paint site, Python for the
tabs.py:1891 suppression — which is why the ctype is not optional.

---

## 2. THE OPTION, THE TOGGLE, THE GUARDS

**Option** (config default OFF): `window_title_band yes|no`.

**Toggle** — take `toggle-liveness.md`'s R3, which is measured and correct:
- **Not** `kitty @ load-config`: a no-op reload costs **8–16 ms** of kitty CPU against a **0.40–0.45 ms**
  RPC floor, and the cost *nearly doubles* with pane count (verifier's paired measurement; the
  report's "fixed cost" claim was refuted). It also makes the loaded variant sticky in
  `all_config_paths`.
- **Not** the `toggle_window_title_bars` per-tab-bool shape: measured to reach **one OS window only**
  and to be lost on every drag, every new tab and every new OS window.
- **Yes**: a new argless kitty action flipping a **process-global C bool** and marking every OS
  window dirty in one call. **[V]** In-tree precedent for exactly this: `bool redirect_mouse_handling`
  at state.h:499, setter at state.c:1697-1700, registered at state.c:1816. Stored in `GlobalState`,
  not `Options`, it structurally survives every config reload (`set_options` writes only seven
  named fields).
- Ship the **bare argless** form only. `toggle-liveness.md`'s verifier measured that
  `kitty @ action <name> on` returns **rc=0 while opening a "Failed to parse action" window**
  unless a `@func_with_args` parser is added. Do not document an `on`/`off` form until that fifth
  edit exists.
- The option seeds the global bool at startup, and on reload **only when the option's value
  changed** (`boss.apply_new_options`, the idiom already at boss.py:3147-3149) — otherwise every
  `deploy-live` config fast-forward snaps the band back mid-session with no tell.

**Guards at the paint site** (all four, in this order):
1. `if (!global_state.show_window_title_bands) return;`
2. `if (!ui->window) return;` — excludes the tab bar and the row-stealing bar screen
3. `if (ui->window->window_title_render_data.screen) return;` — never double-title with ⌘⌥B
4. `if (ui->screen_height <= ui->cell_height * 2) return;` — the `ynum == 1` guard. **[V]**
   `draw_window_number` ships the idiom at shaders.c:942 (`requested_height > (cell_height+1)*2`)
   and `window.py:1056` refuses the same case for the real bar. `redteam.md` F13: reachable via
   `start_resizing_window`, which the operator has bound to ⌘R.

---

## 3. THE EXACT HUNKS

All against `~/kitty-482` @ `2cb1d95c3`. Line numbers are v0.48.2's and were re-read for this plan.

### 3.1 `kitty/state.h`
```c
/* :220-226 — WindowBarData gains a texture cache and a colour cache key */
 typedef struct WindowBarData {
     unsigned width, height;
     uint8_t *buf;
     PyObject *last_drawn_title_object_id;
     hyperlink_id_type hyperlink_id_for_title_object;
     bool needs_render;
+    uint32_t texture_id;          /* 0 == none; freed in release_gpu_resources_for_window */
+    unsigned tex_width, tex_height;
+    color_type drawn_fg, drawn_bg;
 } WindowBarData;

/* :276 — the band's own buffer (R6) */
-    WindowBarData title_bar_data, url_target_bar_data;
+    WindowBarData title_bar_data, url_target_bar_data, title_band_data;

/* Window struct, beside :272 — the painter's own output, read by the hit test (R4) */
+    unsigned title_band_height;   /* px actually drawn this frame; 0 == not drawn */

/* :76 — Options already has the four colours. NO CHANGE. Add only: */
+    bool window_title_band;

/* :499 — beside redirect_mouse_handling, in GlobalState */
+    bool show_window_title_bands;
```

### 3.2 `kitty/shaders.c` — `render_a_bar` (:836-888)
Signature becomes:
```c
static unsigned
render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title,
             bool along_bottom, bool with_border, bool for_final_output,
             color_type fg_override, color_type bg_override)
```
Both existing call sites pass `true, false, 0, 0` for the new trailing args (:929, :943) — a pure
no-op for them.

Five edits inside the body:
1. **:838-839** — `unsigned border_width = with_border ? (unsigned)ceil(thickness_as_float(ui->os_window, 1)) : 0;`
   and `unsigned bar_height = ui->cell_height + (with_border ? 2 : 0);` → the band is exactly one
   45 px cell (R9).
2. **:849-850** — after the existing `RGBCOL` pair: `if (fg_override) fg = fg_override; if (bg_override) bg = bg_override;`
   (R3: `0` is the `none` sentinel, so an unset option falls through to the terminal default.)
3. **:852** — widen the cache key and **clear the flag** (R5):
```c
-    if (bar->last_drawn_title_object_id != title || bar->needs_render) {
+    if (bar->last_drawn_title_object_id != title || bar->needs_render
+            || bar->drawn_fg != fg || bar->drawn_bg != bg) {
         ...
         Py_CLEAR(bar->last_drawn_title_object_id);
         bar->last_drawn_title_object_id = Py_NewRef(title);
+        bar->needs_render = false;
+        bar->drawn_fg = fg; bar->drawn_bg = bg;
+        bar->tex_dirty = true;     /* upload needed */
     }
```
4. **:860-870 + :884** — texture cache (R7). Create the GL object lazily into `bar->texture_id`,
   upload only when the CPU buffer was re-rendered (prefer `glTexSubImage2D` when the size is
   unchanged), and **delete shaders.c:884's `free_texture(&data.texture_id)`**. Also drop the
   file-scope `static ImageRenderData data` for a local.
5. **:876-886** — sRGB + border (R2, R9):
```c
     enable_scissor_using_top_left_origin(border_rect, sh);
-    blank_canvas(ui->bg_alpha, bg, false);
+    blank_canvas(ui->bg_alpha, bg, for_final_output);
     disable_scissor();
     save_viewport_using_top_left_origin(...);
+    if (for_final_output) glEnable(GL_FRAMEBUFFER_SRGB);
     draw_graphics(GRAPHICS_PROGRAM, &data, 0, 1, 1.f);
+    if (for_final_output) glDisable(GL_FRAMEBUFFER_SRGB);
     restore_viewport();
-    free_texture(&data.texture_id);
-    draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
+    if (with_border) {
+        if (for_final_output) glEnable(GL_FRAMEBUFFER_SRGB);
+        draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
+        if (for_final_output) glDisable(GL_FRAMEBUFFER_SRGB);
+    }
     return border_rect.height;
```

### 3.3 `kitty/shaders.c` — `UIRenderData` (:34-42) and `draw_cells` (:1411-1451)
`UIRenderData` gains `bool is_active_window;` — **[V]** it is already a *parameter* of `draw_cells`
(:1411) but never reaches the struct, and the obvious proxy `inactive_text_alpha` is unusable
(measured 1.0 for both states on this box — `font.md` claim 13). Fill it at :1434-1444.

New function, placed beside `draw_window_number` (~:933):
```c
static void
draw_window_title_band(const UIRenderData *ui) {
    if (ui->window) ui->window->title_band_height = 0;
    if (!global_state.show_window_title_bands) return;
    if (!ui->window || !ui->window->title || !PyUnicode_Check(ui->window->title)) return;
    if (ui->window->window_title_render_data.screen) return;      /* ⌘⌥B owns the top row */
    if (ui->screen_height <= ui->cell_height * 2) return;          /* ynum == 1 */
    const bool ffo = !ui->os_window->needs_layers;
    const color_type fg = ui->is_active_window ? OPT(window_title_bar_active_foreground)
                                               : OPT(window_title_bar_inactive_foreground);
    const color_type bg = ui->is_active_window ? OPT(window_title_bar_active_background)
                                               : OPT(window_title_bar_inactive_background);
    unsigned h = render_a_bar(ui, &ui->window->title_band_data, ui->window->title,
                              false, /*with_border=*/false, ffo, fg, bg);
    ui->window->title_band_height = h;
}
```
Call site, between :1449 and :1450 (R1). **No change to `screen_needs_rendering_in_layers`.**

### 3.4 `kitty/state.c`
- **:327-334** `release_gpu_resources_for_window`: `if (w->title_band_data.texture_id) free_texture(&w->title_band_data.texture_id);` (plus the same for the two existing bars, once they cache).
- **:425-428** `destroy_window`: free `title_band_data.buf` and clear its title ref.
- **~:1697-1700 + :1816**: `PYWRAP1(toggle_window_title_bands)` — flip
  `global_state.show_window_title_bands`, then
  `for (i=0;i<global_state.num_os_windows;i++) global_state.os_windows[i].needs_render = true;`
  return the resulting bool. Register with `MW(...)` at :1816; stub beside fast_data_types.pyi:1397.

### 3.5 `kitty/dnd.c:2384-2387`
Free `title_band_data` alongside the other two (the DnD fake windows).

### 3.6 `kitty/mouse.c` — the hit test (R4)
New helper beside `contains_mouse` (~:273):
```c
static bool
mouse_in_title_band(Window *w) {
    if (!w->title_band_height) return false;
    double x = global_state.callback_os_window->mouse_x, y = global_state.callback_os_window->mouse_y;
    const unsigned top = w->render_data.geometry.top;      /* NOT window_top() — no padding term */
    unsigned bottom = top + w->title_band_height;
    if (bottom > w->render_data.geometry.bottom) bottom = w->render_data.geometry.bottom;
    return (w->render_data.geometry.left <= x && x < w->render_data.geometry.right
            && top <= y && y < bottom);
}
```
New FIRST arm inside the loop at :1068, ahead of the existing `if (contains_mouse(win) ...)`:
```c
+            if (win->title_band_height && detect_title_bar && win->visible
+                    && win->render_data.screen && mouse_in_title_band(win)) {
+                ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
+                break;
+            }
             if (contains_mouse(win) && win->render_data.screen) { ... }
             else if (detect_title_bar && win->visible) { /* UNCHANGED */ }
```
**[V]** Keying on `geometry.top` rather than `window_top()` matters: `window_top` subtracts
`padding.top` (mouse.c:261) while the painter draws at `ui->screen_top` — they coincide today only
because the operator's top padding is 0 (`drag-semantics.md` claim 12).

Everything downstream is unchanged stock code: **[V]** mouse.c:1133-1134 gives `POINTER_POINTER`
(the hand) on hover; mouse.c:1362-1368 routes press/motion/release to
`handle_window_title_bar_mouse`, which arms and starts the native drag at tabs.py:1858-1877.

**Separate commit, same wave:** port the tab bar's drag escape hatch (mouse.c:943-955) into
`handle_window_title_bar_mouse` (mouse.c:929-937). `redteam.md`'s verifier correctly narrowed the
severity — tabs.py:1876-1877 *does* clear `window_being_dragged` unconditionally on release, so a
stuck drag costs one swallowed click, not a kitty restart — but it also found the real latched
residual: **nothing on that path clears `force_show_title_bars`**, and no key is bound to the action
that could. With R8 in place that residual is moot for us; land the hatch anyway as an upstream fix.

### 3.7 `kitty/tabs.py` — the required suppression (R8)
```python
# :1890-1897, start_window_drag
         min_w = opts.window_title_bar_min_windows
+        band_up = opts.window_title_band
         for tm in boss.all_tab_managers:
             tm.mark_tab_bar_dirty()
             for t in tm:
                 visible = sum(1 for _ in t.windows.iter_all_layoutable_groups(only_visible=True))
-                if not (min_w > 0 and visible >= min_w):
+                if not band_up and not (min_w > 0 and visible >= min_w):
                     t.force_show_title_bars = True
                     t.relayout()
```
`_clear_force_show_title_bars` (:1918-1926) and boss.py:2035-2040 need **no** change — they only
relayout tabs whose bool is True, which this keeps permanently False (`drag-semantics.md` claim 7).

Two smaller edits in the same file, both justified by the band double-booking content row 1:
- **:1875-1881** — suppress the double-click *rename* when the band is up. Every double-click on a
  pane's top line currently opens a modal "Rename window" prompt instead of selecting a word.
- **:1901-1903** — skip the prepended title strip in the drag thumbnail when the band is up, or the
  band appears **twice** in it (`drag-semantics.md` claim 5); also saves a CoreText render per drag.

### 3.8 `kitty/options/definition.py` + the three generated files
`window_title_band` with `option_type='to_bool', ctype='bool'`, default `no`, long_text enumerating
the behaviour and naming the two known divergences from the Screen bar (colour fallback per R3;
no elision — `render_a_bar` passes `NULL` for `actual_width` so an over-long title is clipped
mid-glyph where the real bar elides in Python). **[V] via `clean-code.md`:** regenerate with
```
KITTY_DEVELOP_FROM=<tree> /Applications/kitty.app/Contents/MacOS/kitty +runpy \
  'import sys; from gen.config import main; main([sys.executable,"config"])'
```
— **without** `KITTY_DEVELOP_FROM` the frozen package silently wins and you regenerate the shipped
definition (that axis's verifier ran the negative control). Commit `options/types.py`,
`options/parse.py`, `options/to-c-generated.h` **in the same commit as the definition**.

### 3.9 Deferred, with reasons
- **Text-width narrowing** (`&actual_width` → glfw.c:1086-1090). `redteam.md` proposed it as the
  highest value-per-line change; its verifier measured the real benefit at **50%** of row-1 ink
  hidden (34% right-aligned), not the claimed 81%, and found four more places in `render_a_bar`
  that must also narrow (the scissor rect, the upload, the draw viewport, the border) plus a
  realloc that then thrashes on every title-width change. **Defer to a second pass**; if taken,
  flipping `window_title_bar_align` to `right` is +16 pp for zero code.
- **A `test_mouse_region` C export** for unit-testing the hit test (precedent: `test_encode_mouse`,
  mouse.c:1664). Propose upstream; if refused, say the hit test is manually verified.

---

## 4. REQUIREMENT (d) — THE OPERATOR'S FORK

`font.md` is the axis with the most decision-changing finding and the one the lead's brief got
backwards. Three facts, all measured (its verifier re-measured them inside a *real* kitty via
`draw_single_line_of_text`, reachable in-process through the `watcher` option with **no build**):

1. The face is **`kCTFontUIFontSystem` at Regular**. There is no weight argument anywhere on the
   path (core_text.m:922-943). The overlay it replaces deliberately selects **Semibold**
   (`kitty-pane-title-overlay.py:275`, chosen after a recorded comparison).
2. On macOS `draw_window_title` **ignores** `font_sz_pts` and `ydpi` (both `UNUSED`, glfw.c:1082-1091);
   type size is a function of the destination buffer's pixel height alone. So `em/band` is a
   constant **0.86667** at every band height from 12 to 140 px — **making the band taller buys zero air.**
3. Rendered worst case at the 47 px band: ink rows **1..46**, flush against the bottom, ink/band
   **0.979** Regular and **1.000** Semibold (flush against both). Shipping the weight change alone
   is a **regression**.

The cure is measured and is a strict generalisation of one line: pass a separate `font_box_height`
to `cocoa_render_line_of_text`, use it for `ensure_ui_font`, and replace
`CGContextSetTextPosition(ctx, 0, descent)` with `(height-(ascent+descent))/2.0 + descent`. At
`font_box == height` this is a **−0.487 px** shift, not a no-op (verifier's correction) — immaterial,
but check the URL bar visually rather than assuming inertness. Weight then needs
`ensure_ui_font(in_height, weight)` built from `[NSFont systemFontOfSize: weight:]`, with the
**weight added to the static cache key** (initialised outside [−1,1], not 0.0).

🔒 **THE FORK — a class-C decision, and it is genuinely the operator's.** In a one-cell (45 px) band
you can have **his accepted air** (ink/band 0.745, 6 px each side) **or his accepted cap height**
(cap/body 1.04), not both — at frac 0.74 cap/body falls to 0.78. Holding 1.04 needs em ≈ 40, hence
a band of **~60 px ≈ 1.34 cells**, which is within 3% of the **62 px** his own overlay converged on
independently. A 1.34-cell band also changes the hit region and overpaints further into row 2.

**Do not guess.** Generate the contact sheet through kitty's own renderer (the verifier's route,
no build), three candidates at 45 px plus one at 60 px, at 1:1 over real Monaco body text — the
exact form that resolved the overlay's own ladder — and file it with
`cc-decide open --class C --conviction <N> --receipt <path> --option … --option …`.
**(d) is explicitly ideal-not-required, so this fork blocks nothing in §9 waves W1–W6.**

---

## 5. LIVE NOW, WITH NO RESTART — the parallel track

The C patch cannot reach pid 597 (`redteam.md` F14). Three live routes exist; they are not
equivalent and the brief's arithmetic excluded the best one.

| Route | (a) | (b) | (c) | (d) | Resting cost | Status |
|---|---|---|---|---|---|---|
| **Today**: ⌘⇧B PNG overlay + ⌘⌥B real bars | ✅ / ✅ | ❌ blinks, re-asserts every 0.35 s | ⌘⌥B only, **costs a row while up** | ✅ Semibold | 45 MB RSS, 0.11% core idle, `kitty @ ls` fork every 1.5 s | live |
| **D-restored**: the consolidated-padding config pair | ✅ | ✅ | ✅ real bars, hand, native drag, **survives a no-op drag** | ❌ Monaco | **one row at ~11% of stacked-pane heights** | built, calibrated, currently disarmed |
| **Python band**: watcher-injected `set_geometry` monkeypatch + padding underflow | ✅ | ✅ | ✅ *geometry proven, pointer unverified* | ❌ Monaco | ~zero; deletes the daemon | measured in a sandbox, **artifact not shippable yet** |

**Ruling: pursue the Python band, keep the overlay running until it is proven, and do not
re-arm D.** Reasons, each traced:

- **D is real and I re-read its record** (config/kitty.conf § 3 and config/kitty-title-on.conf):
  `OFF 22.5 5 0 5 + min_windows 0 ⇄ ON 0 5 0 5 + min_windows 1`, 30/30 rows across six swaps,
  SIGWINCH 0, pixel-verified. `live-deploy.md`'s verifier is right that this refutes that axis's
  "(c) is unreachable from Python ⇒ the switchover is mandatory". But the record also says
  **why it was swapped back on 2026-09-16, and it was not the row** — operator: *"How come we lost
  our font/size styling"*, *"Please fix the font to what we had"*. Re-arming D reintroduces both
  the Monaco face he rejected **and** the resting row he rejected twice.
- **The Python band is strictly better and was measured** (`fallback.md` §2–§4): band drawn over
  content row 1 with `g.ynum == screen.lines == 11` (zero rows lost, zero SIGWINCH), the only
  changed pixels on toggle are one 45 px band per pane, the band does not move across 400 lines of
  scroll + a `clear` + a `kitty @ scroll-window`. And for (c): `window->padding` is a **pure
  hit-test inset** — **[V]** five C references, four of them the mouse edge functions
  (mouse.c:251/256/261/266) and one the setter (state.c:1194); no render path reads it. Pushing
  `padding.top := effective_top − cell_height` (CPython `'I'` takes the unsigned underflow) moves
  `contains_mouse`'s top edge to the band's bottom (measured 2→47 and 502→547) and **changed 0 of
  1 689 600 pixels**. The `else if` title-bar arm then becomes reachable for the band only.

**Four blocking fixes before anything touches pid 597** (`fallback.md`'s own verifier; the last is
the operator's ten seconds, not ours):
1. Wrap the patched `set_geometry` body in `try/except` falling back to the original — an exception
   there propagates through `Tab.relayout` and **takes the layout engine down for the whole OS
   window** (measured: new windows arrive un-laid-out at 24×80, `load-config` tracebacks).
2. Delete all file logging from the hot path — it is a file open+write per window per relayout.
3. Hook the **chokepoint** `Window.update_effective_padding`, not `set_geometry`. Four Python sites
   write `padding` (window.py:825, :875, :886, :1107) and three of them reset it to stock; the patch
   survives today only because a relayout happens to follow. The chokepoint fix was built and
   measured in that axis.
4. Ship an **undo watcher** and the 10-second human hover test. The pointer becoming a hand and the
   press starting a drag are the one thing nobody could measure (no `cliclick`, no pyobjc, and
   synthetic CG events would warp the operator's cursor across his live desktop — the corpus
   already records what a "read-only" input probe cost this week).

Injection is `launch --type=overlay --watcher <abs path>` (`--type=background --watcher` silently
does nothing — launch.py:520-542 runs watchers only when a Window is created), and it works under
the operator's `allow_remote_control socket-only`. ⌘⇧B then becomes one `no_ui` kitten that flips
the patch's own flag — **[V] via `live-deploy.md`**, whose kitten door was reproduced with a
positive control and whose exception path was measured (an error inside a live kitten is caught by
the rc dispatcher and returned; kitty survives).

---

## 6. THE SWITCHOVER

**Do not quit first.** kitty forks a new process per invocation, so:

1. Start the patched build as a **second instance on its own socket**
   (`kitty --instance-group ktb -o listen_on=unix:/tmp/kitty-ktb`).
2. Roll panes across **one at a time**, oldest-value-first, using the snapshot that already resolves
   the whole fleet: `python3 <this dir>/instruments/snapshot.py unix:/tmp/kitty-597 tsv` — it joins
   `kitty @ ls` × `~/.claude*/cc-registry/<window-id>.json` × `reso-resume-one` argv × `lr-select.py`
   and resolved **5/5** panes when `live-deploy.md` ran it.
3. Quit the old instance only when it holds **zero** Claude panes. At most one session is ever down;
   rollback is "quit the new one"; a patched binary that fails to start costs nothing.

**Three traps that will silently misroute the rollout** (all from `live-deploy.md`, claims 15-17):
- Pass `CC_TERM_KITTY_TO` explicitly or every spawn lands back in the **old** kitty —
  `bin/cc-kitty-socket` deliberately returns the **oldest** live instance.
- Pass `--no-liveness` to `lr-select.py` or its hard filters drop already-running sessions, which is
  exactly the switchover population.
- Translate the registry's config-dir basename (`claude-secondary`) to the launcher alias (`next2`)
  via `accounts.json`, or `reso-resume-one` dies.

**What a switchover cannot preserve**, stated so it is not discovered mid-roll: the in-flight turn,
full scrollback, non-Claude pane processes, registry identity/addressability, dispatch identity,
exact split ratios. A `/goal` **does** survive via `--resume`
(`tengu_goal_restored_on_resume`). **The driver is not written and must not be:** its central step
closes live panes, which auto mode's classifier denies to an agent. That step is the operator's
typed `yes`, by construction — hand it over per § Manual-Command Delivery as one gated script.

---

## 7. REPO CHANGES (claude-infrastructure)

**config/kitty.conf**
- Keep `window_padding_width 0 5 0 5` and `window_title_bar_min_windows 0` — the band steals no row,
  so there is nothing to compensate, and ⌘⌥B still needs the real bars.
- ⌘⇧B becomes `map cmd+shift+b toggle_window_title_band` (replacing today's two-`launch` combine).
  **[V]** A new argless action is **never validated at parse time** (options/utils.py:1172-1176), so
  a typo is a silent, permanent no-op with no config error — pin the spelling in a test.
- Arm it through the existing `globinclude drag-arm.d/*.conf` seam **on the live side only**
  (`~/.config/kitty/drag-arm.d/drag.conf`). `clean-code.md`'s verifier measured that
  `tests/kitty-drag-arm.bats` case 5 globs the **working tree** as well as `git ls-files`, so an
  untracked repo-side drop-in fails too.
- Add the new §3c recording this decision, INTEGRATE-never-overwrite: §3 and §3b stay verbatim as
  the record of what was believed, including the "NO FOURTH POINT" refutation and the D measurement.

**scripts/**: retire `kitty-pane-title-overlay.py`, `kitty-pane-title-toggle.sh` and
`config/kitty-title-on.conf` **only after the patched build is live**. `clean-code.md` claim 22:
deleting the overlay script produces a real ORPHAN finding in `deploy-parity-assert.sh` until a
converge sweeps it — expected, not a defect.

**tests/**: `clean-code.md` measured the damage precisely — **17 of 43** cases across
`kitty-title-zero-shift.bats` and `kitty-conf-bindings.bats` lose their subject (19 only if
`min_windows` also moves, which under this design it does not). Handle it as that axis rules:
- **Delete**, with the script, the ~10 cases that test the *overlay script*, not the config.
- **Re-key** the three genuine cases (1, 7, 24) onto one property — *"the chord reaches a
  hit-tested, system-font bar that steals no row"* — which collapses `glance_key()` / `real_bar_key()`
  into one resolver.
- **Refute in place** the `kitty-conf-bindings.bats:116-121` premise that the overlay is "the only
  thing that can carry our face" — **partially**: the band bypasses kitty's monospace matcher, but
  arrives at **Regular**, so mark it partially refuted beside the original words, never delete
  (§4; and `clean-code.md`'s verifier caught exactly this over-claim).
- **Do not repair reds by relaxing assertions** — `kitty-conf-bindings.bats:33-35` names that as the
  move that produced two rebaselines.
- New `kitty_tests/window_title_band.py` upstream, modelled on `kitty_tests/tab_bar.py`'s
  patch-the-C-layer technique, asserting the zero-shift identity directly (`screen.lines` unchanged,
  `(render_top, render_bottom)` unchanged). **[V] via `clean-code.md`:** the window title bar
  subsystem has **zero** test coverage in `kitty_tests` today.

---

## 8. BUILD RECIPE

From `build.md`, whose numbers its verifier independently reproduced:
```bash
export PATH=/opt/homebrew/bin:$PATH        # MANDATORY: bare python3 is 3.11.4, kitty needs >=3.12
cp -R ~/kitty-482 ~/ktb482                 # 22-char durable path; NOT /private/tmp (a reboot reaps it)
cd ~/ktb482
printf 'build/\nfonts/\nkitty.app/\n*.so\n*_generated.go\n' >> .gitignore
git init -q && git add -A && git commit -qm 'baseline: v0.48.2'    # ← BLOCKING, see below
mkdir -p docs/_build/man docs/_build/html   # else `make app` SystemExits at packaging
make            # 16 s full, ~10 s incremental (link-bound: 1 file and 23 cost the same)
make app        # 3-4 s; `make` alone yields a NON-relocatable launcher bundle
```
- 🚨 **`~/ktb482` exists today and has no `.git`** (I checked). Without history there is no
  `git diff`, no branch, no stash, no bisect, and no way to emit a standalone patch of our work.
  `git init` **before the first title-band edit**.
- `~/k482` is **not** a clean baseline (it carries the sibling's drag patch) and neither is `~/kdev`
  (a still-moving master variant). The only stock v0.48.2 is `/Applications/kitty.app`.
- The ~80-char path ceiling binds `./dev.sh` **only** — `make`/`make app` were positively measured
  clean at 97 and 121 chars.
- Identify a build **without executing it**: `strings <fast_data_types.so> | grep -c get_mouse_press_data_for_window`
  (1 = patched, 0 = stock), control `set_window_render_data` (nonzero in both). `--version` cannot
  distinguish anything — master also reports 0.48.2.
- Side-by-side install: copy `kitty.app` to `~/Applications/kitty-patched.app`, set
  `CFBundleIdentifier` to `net.kovidgoyal.kitty-patched`, re-sign adhoc. The Homebrew cask owns only
  `kitty.app` and cannot clobber it.
- **Apply the sibling's `kitty-mouse-drag-window-v0.48.2.patch` FIRST** and write the band patch
  against the result. Zero semantic conflict — it touches `fast_data_types.pyi`, `glfw.c`,
  `options/utils.py`, `state.c`, `state.h`, `window.py`, and its only `state.h` hunk is on
  `OSWindow` (~:448) while ours is on `WindowBarData` (:220) and `Window` (:272).

---

## 9. WAVES

Each wave states its own verdict-printing check. `$K` = `~/ktb482`, `$R` = the claude-infrastructure
worktree. Waves **L1/L2 run in parallel with everything** and block nothing.

| # | What | Files | blockedBy | Check that PRINTS a verdict |
|---|---|---|---|---|
| **W0** | Build tree gets history. `git init` + baseline commit + apply the sibling drag patch as commit 2. | `$K/.gitignore` | — | `cd $K && git log --oneline \| wc -l && git status --porcelain \| wc -l && echo "W0 $( [ -d .git ] && echo PASS \|\| echo FAIL )"` |
| **W1** | The three prerequisite fixes, no new feature: `needs_render=false` + colour cache key; third `WindowBarData` + both frees; texture cache + teardown in `release_gpu_resources_for_window`. | `shaders.c` :852-859, `state.h` :220-226/:276, `state.c` :327-334/:425-428, `dnd.c` :2384-2387 | W0 | `cd $K && make >/dev/null 2>&1; rc=$?; g=$(grep -c 'needs_render = false' kitty/shaders.c); t=$(grep -c 'title_band_data' kitty/state.h kitty/state.c kitty/dnd.c \| awk -F: '{s+=$2}END{print s}'); echo "W1 build_rc=$rc needs_render_clears=$g band_data_sites=$t → $( [ $rc -eq 0 ] && [ $g -ge 1 ] && [ $t -ge 4 ] && echo PASS \|\| echo FAIL )"` |
| **W2** | `render_a_bar` parameterised: `with_border`, `for_final_output`, `fg/bg` overrides; both existing call sites updated to no-op values; `is_active_window` into `UIRenderData`. | `shaders.c` :836-888, :34-42, :1411-1444 | W1 | `cd $K && make >/dev/null 2>&1 && ./kitty/launcher/kitty --version >/dev/null && echo "W2 PASS — builds and starts" \|\| echo "W2 FAIL"` — plus **visual**: launch the patched build in a sandbox, hover a hyperlink with ⌘ and press ⌃⇧F7; both existing bars must look exactly as before. |
| **W3** | The option + the paint call. `window_title_band` in `definition.py` + regenerate 3 files + `Options` field; `draw_window_title_band()`; call at :1449/:1450; all four guards. | `options/definition.py`, `options/{types,parse}.py`, `options/to-c-generated.h`, `state.h`, `shaders.c` | W2 | Sandbox instance, **band ON, PNG daemon STOPPED** (`toggle-liveness.md`'s verifier: the daemon forces `needs_layers` everywhere via `grman_has_images`, so a build missing R1 would validate perfectly until it is retired). `kitty @ ls` line counts identical band-on vs band-off, and a screenshot diff showing exactly one 45 px band per pane. Print `W3 rows_off=<a> rows_on=<b> changed_bands=<n> → PASS iff a==b and n==panes`. |
| **W4** | The toggle: `GlobalState` bool, `PYWRAP1` + `MW(...)`, `.pyi` stub, Boss `@ac` method, `apply_new_options` change-detection. | `state.h` :499, `state.c` ~:1697/:1816, `fast_data_types.pyi`, `boss.py` | W3 | `kitty @ action toggle_window_title_band` twice against a **2-OS-window** sandbox; print per-OS-window band presence each time. `W4 PASS` iff **both** OS windows flip both times (this is exactly what `toggle_window_title_bars` fails, measured). |
| **W5** | The hit test: `Window.title_band_height`, `mouse_in_title_band()`, the new first arm; separate commit for the `window_being_dragged` escape hatch. | `state.h` :272, `mouse.c` :273/:1068, :929-937 | W3 | Compile gate first: `clang -fsyntax-only -Wall -Wextra` on the patched `mouse.c` with a **negative control** (delete the struct field → must error). Then the human 10 s: hover the band → hand; press-drag onto another pane → panes swap; drop in place → **band still up**. Print `W5 syntax=<rc> hand=<y/n> drag=<y/n> noop_persists=<y/n>`. |
| **W6** | Drag-time correctness: suppress the force-show loop; suppress the double-click rename; skip the duplicated thumbnail strip. | `tabs.py` :1890-1897, :1875-1881, :1901-1903 | W5 | SIGWINCH-trapping children in every pane, then one real drag. Print `W6 winch_count=<n> rows_before=<a> rows_after=<b> → PASS iff n==0 and a==b`. This is the check that proves (c) did not break (a). |
| **W7** | *(gated on the §4 ruling; (d) is ideal-not-required)* `font_box_height` + centring in `cocoa_render_line_of_text`; `ensure_ui_font(height, weight)` with weight in the cache key; band-height option if the operator picks the 60 px corner. | `core_text.m` :922-943/:945-999, `glfw.c` :1082-1092, `shaders.c` :839 | W3 + decision | Re-render the four measured strings through `draw_single_line_of_text` in the patched build and print `ink rows`, `top gap`, `bottom gap`, `ink/band` per string. `W7 PASS` iff worst-case ink/band ≤ 0.78 **and** the URL bar is visually unchanged. |
| **W8** | Repo: kitty.conf §3c + the chord; retire the overlay trio; test re-key per §7. | `$R/config/kitty.conf`, `$R/scripts/*`, `$R/tests/kitty-{title-zero-shift,conf-bindings}.bats` | W6 | `cd $R && bats tests/kitty-title-zero-shift.bats tests/kitty-conf-bindings.bats tests/kitty-drag-arm.bats 2>&1 \| tail -3` — **assert the `1..N` plan line is present** before believing a pass. Print `W8 plan=<N> failures=<n>`. |
| **W9** | Switchover: gated operator script per § Manual-Command Delivery. | `/tmp/kitty-switchover.sh` | W8 | Dry-run prints the resolved per-pane roll plan (account, session id, worktree, branch) for **all** live panes and exits 0 without moving anything. `W9 PASS` iff resolved == total. |
| **L1** | *(parallel)* Fix the Python fallback artifact: try/except, no hot-path I/O, hook `update_effective_padding`, ship the undo watcher. | `fallback-instruments/patch_v2.py` → `patch_v3.py` + `patch_undo.py` | — | In a **sandbox**: arm a `FileNotFoundError` at the old log site and confirm the layout engine survives; then `kitty @ ls` rows unchanged, SIGWINCH 0. Print `L1 exception_survived=<y/n> rows=<a,b> winch=<n>`. |
| **L2** | *(parallel, after L1)* Inject into pid 597 under the operator's eye; ⌘⇧B becomes the `no_ui` kitten. | live instance | L1 + operator present | The 10-second hover test on a **live** pane, then `kitty @ ls` rows before/after. Print `L2 rows_before=<…> rows_after=<…> hand=<y/n>`. Undo watcher ready in the same breath. |

---

## 10. RESIDUALS, NAMED

Accepted, not fixed — each is a property of a zero-row band, not a defect of this design:
1. **Row 1 is covered.** Worst stratum is the live one: 3 of 4 panes are alt-screen TUIs where row 1
   is permanently occupied (100%, not the 46.7% `redteam.md` first published — its verifier showed
   that figure is a between-pane mixture with an effective n of ~4).
2. **Top 12 px of the band is the border-resize handle** (`window_drag_tolerance 6` pt @144 dpi),
   pre-empting the band. Unchanged from today's stolen-row bar. Tunable, but the tolerance was
   deliberately raised from 2 to 6 to make border-resize hittable — the two features trade the same
   pixels.
3. **Entering the band sends a mouse-LEAVE to the child** (mouse.c:1356) and clears the URL
   highlight and scrollbar hover. This is what the stolen-row bar does; keep it, document it.
4. **The top ~51 px of every scrollbar becomes ungrabbable** while the band is up.
5. **No elision.** `render_a_bar` passes `NULL` for `actual_width`, so an over-long title is clipped
   mid-glyph where the real bar elides in Python. Most visible regression against the overlay;
   §3.9 has the cure.
6. **One frame of staleness** on a live `load-config` disable, because the hit test keys on the
   painter's output rather than on `OPT(...)`. The trade bought zero painter/hit-test drift.
7. **`~205 KiB` RAM + `~205 KiB` VRAM retained per pane ever rendered**, not reclaimed on tab switch
   and deliberately retained across a ⌘⇧B "off" — freeing would reintroduce the upload cost at the
   one moment latency is visible.
8. **Post-fix cost is 0.18% of a core, not zero.** Say `0.18%`, never "free".
