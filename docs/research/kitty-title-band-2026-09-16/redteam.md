# Red team: the zero-row `render_a_bar` title band

**Axis:** adversarial red team of the whole proposed design.
**Date:** 2026-09-16.
**Trees read:** `~/kitty-482` @ `2cb1d95c3` (= v0.48.2, the build the operator RUNS) and
`~/kitty-dev` @ `1d67ecd47` (master/nightly-21). Every file:line below names its tree.
**Verdict up front, in one sentence:** the design's *central premise is correct and survived my
best attack on it* — there really is no third place to put the bar, and `render_a_bar` really is
the right machinery — but **as specified it is dead on arrival for three independent reasons**, and
the two most likely to ship are the kind that look like they work while you are developing.

1. **It never draws.** The only call site for `render_a_bar` is inside `draw_cells_with_layers`,
   which the operator's config does not reach (`background_opacity = 1.0`, measured live). **F1.**
2. **It cannot be "live for currently-open sessions"** — that is a stated requirement and a C
   patch structurally cannot meet it. **F14.**
3. **Requirement (c) breaks requirement (a).** Kitty's window-drag *begins* by forcing the real
   one-row title bars on in every tab in the fleet, so every drag costs two whole-fleet content
   shifts. Neither the design nor the sibling's `mouse_drag_window` patch escapes this. **F9.**

**➜ [RANKED FAILURE MODES](#ranked-failure-modes) — 20 rows with trigger / symptom / fix.**
**➜ [ATTACKS THAT FAILED](#attacks-that-failed-clean-negatives--evidence-for-the-design) — 5 clean
negatives, including one retraction of my own.**

Evidence discipline: claims are CONFIRMED (file:line or a command + its real output), or marked
UNMEASURED. Nothing here is reasoned into a CONFIRMED. One claim in this document was written
wrong and is corrected in place rather than deleted (F9's paragraph on the sibling patch), and one
proposed mitigation of mine was refuted by the record I was citing and is struck through in place
(F11).

---

## F1 — THE BAND NEVER DRAWS AT ALL ON THE OPERATOR'S CONFIG  (severity: fatal, likelihood: certain)

**This is the answer to brief item 6 (`the single most likely way this ships and quietly does the
wrong thing`), and it is worse than "quietly": it is a feature that works on the developer's box
and is invisible on the target box, for a reason nothing in the diff mentions.**

`render_a_bar`'s only two existing consumers are called from ONE place:

```
~/kitty-482 kitty/shaders.c:1357-1383
static void
draw_cells_with_layers(const UIRenderData *ui, ssize_t vao_idx) {
    ...
    draw_visual_bell(ui);
    draw_drag_preview_overlay(ui);
    draw_progress_bar(ui);
    draw_scrollbar(ui);
    draw_hyperlink_target(ui);     <- render_a_bar consumer
    draw_window_number(ui);        <- render_a_bar consumer
}
```

and `draw_cells_with_layers` is reached only on a branch:

```
~/kitty-482 kitty/shaders.c:1448
    if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
    else draw_cells_without_layers(&ui, srd->vao_idx);
```

`draw_cells_without_layers` (`~/kitty-482 kitty/shaders.c:1344-1348`) is a single
`call_cell_program(CELL_PROGRAM, ...)` and calls **none** of the six UI overlays. So a
`draw_window_title_band(ui)` added beside `draw_window_number(ui)` — the obvious placement, and
the one the design implies — is simply not executed when `needs_layers` is false.

`needs_layers` is computed once per frame per OS window:

```
~/kitty-482 kitty/child-monitor.c:757-760
    os_window->needs_layers = (
        !global_state.supports_framebuffer_srgb || effective_os_window_alpha(os_window) < 1.f ||
        os_window->live_resize.in_progress || (background_image_for_os_window(os_window) != NULL)
    );
```
plus, per screen:
```
~/kitty-482 kitty/child-monitor.c:770, 786
    os_window->needs_layers = os_window->needs_layers || screen_needs_rendering_in_layers(...);
~/kitty-482 kitty/child-monitor.c:781
    os_window->needs_layers = os_window->needs_layers || (OPT(cursor_trail) && tab->cursor_trail.needs_render);
```
and
```
~/kitty-482 kitty/shaders.c:1316-1321
screen_needs_rendering_in_layers(OSWindow *os_window, Window *w, Screen *screen) {
    const bool has_ui = w && ((screen->start_visual_bell_at | screen->start_drag_overlay_at)
        || has_scrollbar(w, screen) || has_progress_bar(screen)
        || has_hyperlink_target(os_window, w, screen) || has_window_number(w, screen)
        || w->window_logo.id);
    ...
    return has_ui || grman_has_images(grman);
}
```

Now evaluate every term against the operator's LIVE config
(`config/kitty.conf`, uncommented lines only — read with
`grep -vE '^\s*#|^\s*$' config/kitty.conf`):

| term | value here | contributes? |
|---|---|---|
| `!supports_framebuffer_srgb` | **false** — hardcoded `true` on macOS, `~/kitty-482 kitty/gl.c:70-73` (`srgb is always supported on macOS ... hardcode to true`) | no |
| `effective_os_window_alpha < 1` | no `background_opacity` in the config at all ⇒ 1.0 | no |
| `live_resize.in_progress` | only while dragging the OS window edge | **transiently yes** |
| `background_image` | not set | no |
| `cursor_trail` | not set | no |
| `visual_bell` / `drag_overlay` | transient | transiently yes |
| `has_scrollbar` | `scrollbar` defaults to `scrolled` (`~/kitty-482 kitty/options/definition.py:530-531`), and `has_scrollbar` (`~/kitty-482 kitty/shaders.c:823-834`) returns true iff `screen->scrolled_by > 0` | **only while scrolled back** |
| `has_progress_bar` | only during an OSC-9;4 progress report | transiently |
| `has_hyperlink_target` | only while hovering a link with ⌘ held (`show_hyperlink_targets cmd`) | transiently |
| `has_window_number` | only during the window-number overlay | transiently |
| `window_logo.id` | not set | no |
| `grman_has_images` | **TRUE TODAY — because the current PNG overlay daemon is putting images.** | **yes, today only** |

### The two ways this ships broken

1. **It works during development and dies on removal of the old daemon.** The band is developed
   *alongside* `kitty-pane-title-overlay.py`, which is a graphics-protocol producer, so
   `grman_has_images()` is true and `needs_layers` is true and the band renders beautifully.
   Retire the daemon — which is the entire point of the design — and `needs_layers` goes false and
   the band vanishes. The diff that breaks it is the diff that *deletes 1179 lines of Python*, so
   nobody will look for a rendering regression in it.
2. **It appears to "work" intermittently forever after, in exactly the pattern that refutes
   requirement (b).** Scroll a pane back ⇒ `has_scrollbar` ⇒ `needs_layers` ⇒ the band appears.
   Scroll to the bottom ⇒ the band disappears. Hover a link with ⌘ ⇒ it appears. Drag the OS
   window edge ⇒ it appears during the resize and vanishes on mouse-up. The operator's stated
   requirement is that the bar is *always fixed and present*; this is a bar that is present only
   when some unrelated overlay happens to be active.

### Fix / mitigation

Two, and only the second is right:

- (wrong, tempting) add the band to `screen_needs_rendering_in_layers`'s `has_ui`. That forces
  **every OS window into layered rendering permanently**, which is the expensive path — it splits
  the cell draw into BG/FG passes (`~/kitty-482 kitty/shaders.c:1361-1371`), disables the
  `GL_FRAMEBUFFER_SRGB` fast path (`~/kitty-482 kitty/shaders.c:1502-1504`) and, per
  `~/kitty-482 kitty/shaders.c:1642,1673`, changes framebuffer setup. That is the exact opposite
  of "lowest to zero latency and memory pressure".
- (right) call the band draw from `draw_cells()` itself, **after** the
  `if (needs_layers) ... else ...` and before `restore_viewport()`
  (`~/kitty-482 kitty/shaders.c:1446-1450`), so it runs on both paths. But then see F3 — it must
  be the last thing drawn and it must restore the viewport itself.

**Status: CONFIRMED by code read. UNMEASURED at runtime** (no build was run; the brief forbids it).

---

## F2 — THE BAND AND THE ⌘-HOVER URL BAR SHARE ONE BUFFER, AND THE BAND WINS  (severity: high, likelihood: certain given the design)

`WindowBarData` is the per-window scratch for a `render_a_bar` client. There are exactly two
fields on `Window`:

```
~/kitty-482 kitty/state.h:220-226, 276
typedef struct WindowBarData { unsigned width, height; uint8_t *buf;
    PyObject *last_drawn_title_object_id; hyperlink_id_type hyperlink_id_for_title_object;
    bool needs_render; } WindowBarData;
...
    WindowBarData title_bar_data, url_target_bar_data;
```

**There is a pre-existing aliasing bug in both trees: the URL bar keeps its STATE in
`url_target_bar_data` but RENDERS THROUGH `title_bar_data`.**

```
~/kitty-482 kitty/shaders.c:916   WindowBarData *bd = &window->url_target_bar_data;
~/kitty-482 kitty/shaders.c:929   render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom);
```
Identical in master:
```
~/kitty-dev kitty/shaders.c:1337  WindowBarData *bd = &window->url_target_bar_data;
~/kitty-dev kitty/shaders.c:1353  render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom);
```

and `draw_window_number` uses `title_bar_data` too:
```
~/kitty-482 kitty/shaders.c:943  title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false);
```

Today this is benign because both consumers are momentary and mutually rare. A **persistent**
title band using `title_bar_data` — the obvious choice, it is literally named for this — makes it
permanent:

`render_a_bar`'s CPU-render cache key is PyObject **pointer identity** of the title:
```
~/kitty-482 kitty/shaders.c:852-859
    if (bar->last_drawn_title_object_id != title || bar->needs_render) {
        ... draw_window_title(...)  /* full CoreText layout + rasterize */
        Py_CLEAR(bar->last_drawn_title_object_id);
        bar->last_drawn_title_object_id = Py_NewRef(title);
    }
```
So with a band passing `window->title` and the URL bar passing the sanitized-URL object through
the *same* `bar`, every frame in which a ⌘-hover URL target is live does **two** full CoreText
renders of a ~1690×47 RGBA buffer per pane instead of zero. Both miss, every frame, forever,
because each one evicts the other's key.

### The worse half: the band ERASES the URL preview

```
~/kitty-482 kitty/shaders.c:915   const bool along_bottom = screen->current_hyperlink_under_mouse.y < 3;
```
The URL bar goes to the **bottom** only when the hovered link is on screen row 0/1/2; for a link
anywhere on row ≥ 3 it is drawn at the **top** — exactly where the proposed band goes. And in
`draw_cells_with_layers` the band would be drawn *after*:
```
~/kitty-482 kitty/shaders.c:1381-1382
    draw_hyperlink_target(ui);
    draw_window_number(ui);
```
so the band overdraws it. The operator's config has `show_hyperlink_targets cmd` and
`underline_hyperlinks always` (`config/kitty.conf`), i.e. he uses this feature. **Result:
⌘-hovering any link below row 3 shows no URL preview at all.**

### Fix
Give the band its **own** `WindowBarData` field (`Window.window_title_band_data`) — not
`title_bar_data` — AND fix the pre-existing `draw_hyperlink_target` aliasing to use `bd` while you
are in there (it is a one-word change and it is upstreamable on its own). Then make the band
**skip drawing entirely** when `has_hyperlink_target(...)` is true and the URL bar is going to the
top, or draw the band first and the URL bar last. The ordering decision must be explicit; the
default ordering is wrong.

**Status: CONFIRMED by code read in both trees. Runtime effect UNMEASURED (no build).**

---

## F3 — THE BAND IS 1.13 CELLS TALL, NOT 1: IT EATS 6 px OF ROW 2  (severity: high, likelihood: certain)

```
~/kitty-482 kitty/shaders.c:838-840
    unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
    unsigned bar_height = ui->cell_height + 2;
    unsigned bar_width = ui->screen_width - 2 * border_width;
~/kitty-482 kitty/shaders.c:871-873
    Viewport border_rect = { .height=bar_height + 2 * border_width, ... };
```
```
~/kitty-482 kitty/shaders.c:303-308
thickness_as_float(os_window, level) { double pts = OPT(box_drawing_scale)[level]; ... return pts * dpi / 72.0; }
~/kitty-482 kitty/options/definition.py:531-533   box_drawing_scale default '0.001, 1, 1.5, 2'
```

On this machine: `box_drawing_scale[1] = 1 pt`, dpi 144 ⇒ `border_width = ceil(1 × 144/72) = 2 px`.
Cell height = 45 device px (`font_size 18.0` × `modify_font cell_height 94%` at dpi 144 — the
figure `config/kitty.conf` § 3 already establishes and the plan says not to re-derive).

Therefore:

| quantity | value |
|---|---|
| `bar_height` (text texture) | 45 + 2 = **47 px** |
| `border_rect.height` (what is blanked + bordered) | 47 + 2×2 = **51 px** |
| one cell | **45 px** |
| **overhang into row 2** | **6 px = 13.3 % of row 2's height** |

`render_a_bar` blanks the whole 51 px to background under a scissor
(`~/kitty-482 kitty/shaders.c:875-878`) and then strokes a rounded border over it
(`~/kitty-482 kitty/shaders.c:885`, `corner_radius_px = ui->cell_width` ≈ 21-22 px here). So the
top 6 px of row 2 are **erased**, and a 2 px horizontal rule is painted 4 px into row 2.

Why this is not cosmetic here: a Claude Code transcript is full of full-cell box-drawing
verticals and brackets — `⏺`, `⎿`, `│`, `─` — which are drawn edge-to-edge in the cell. Every one
of them on row 2 gets a 6 px bite out of its top, and the continuation rails that make the
transcript readable acquire a visible break on the second row of every pane. And the band's own
rounded corners (radius ≈ one cell width) on a 51 px rect render as a pill, floating over content,
which is not the flat one-row bar the design describes.

### Fix
Do not reuse `render_a_bar` unmodified. It needs `bar_height` / `border_rect.height` /
`corner_radius_px` parameterised (or a `bool flush_top` that sets `border_width = 0`,
`bar_height = cell_height`, `corner_radius = 0`). That is a real change to a function with two
existing callers whose appearance you must not alter — so it is an added parameter, not an edit.

**Status: CONFIRMED by arithmetic over code-read constants. The 45 px cell is taken from
`config/kitty.conf` § 3's own measurement, not re-derived here.**

---

## F4 — THE BAND IGNORES ALL FOUR `window_title_bar_*` COLOURS; ACTIVE AND INACTIVE PANES BECOME INDISTINGUISHABLE  (severity: high, likelihood: certain)

```
~/kitty-482 kitty/shaders.c:849-851
#define RGBCOL(which, fallback) ( 0xff000000 | colorprofile_to_color_with_fallback(ui->screen->color_profile, ... ))
    color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
```

`render_a_bar` takes its colours from the **screen's default fg/bg** — here `#e6e6e6` on
`#1e1e24` (`config/kitty.conf`). It never reads `window_title_bar_active_background`,
`..._active_foreground`, `..._inactive_background`, `..._inactive_foreground`, all four of which
the operator has set (`#2f62d8` / `#ffffff` / `#3f5590` / `#f4f6fd`). It also never reads
`window_title_bar_align`, so `center` and `right` would silently do nothing (`left` happens to
match what CoreText does by default).

Consequences, in order of how much they hurt:

1. **The band's background is the same colour as the terminal background.** There is no visual
   band at all — just a row of system-font text sitting where a row of monospace text used to be,
   with a 2 px rounded outline round it. Screenshot-level indistinguishable from "the first line
   of output went weird".
2. **Active vs inactive pane is unmarked.** With 3 panes in OS window 5 and 2 in OS window 4
   (measured, below), the whole point of a per-pane title strip is to see which one has focus.
   `render_a_bar` has no notion of `is_active_window` — it is not even passed into
   `UIRenderData`'s call for the bar; `draw_cells` knows `is_active_window`
   (`~/kitty-482 kitty/shaders.c:1411`) but does not store it on `ui`
   (`~/kitty-482 kitty/shaders.c:1434-1444` — the struct has no such field).
3. `render_a_bar` is also unaware of `inactive_text_alpha`, so an inactive pane's band is drawn at
   full opacity while its cells are dimmed — inverting the intended emphasis.

### Fix
Add `bool is_active` to `UIRenderData` (it is already a parameter of `draw_cells`) and pass
explicit fg/bg into a parameterised `render_a_bar`, reading the four `window_title_bar_*` opts.
Again: a real signature change, not a call-site addition.

**Status: CONFIRMED by code read.**

---

## F5 — PER-FRAME GL TEXTURE CREATE / UPLOAD / DESTROY, PER PANE, FOREVER  (severity: high on the operator's own stated goal, likelihood: certain)

This is the axis the goal statement names explicitly (*"lowest to zero latency and memory
pressure"*), and the design makes it strictly worse than the thing it replaces on one measure and
better on another.

`render_a_bar` re-creates and re-uploads its texture **every single call**, regardless of whether
the CPU buffer was cached:

```
~/kitty-482 kitty/shaders.c:860-882
    static ImageRenderData data = {.group_count=1};
    gpu_data_for_image(&data, -1, 1, 1, -1);
    glGenTextures(1, &data.texture_id);
    glBindTexture(GL_TEXTURE_2D, data.texture_id);
    ...
    glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB_ALPHA, bar_width, bar_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, bar->buf);
    ...
    draw_graphics(GRAPHICS_PROGRAM, &data, 0, 1, 1.f);
    ...
    free_texture(&data.texture_id);
```

The `bar->needs_render` cache at :850 only skips the **CoreText rasterize**. The
`glGenTextures` + `glTexImage2D` + `free_texture` triple is unconditional. That is correct-ish for
a bar that appears for a second while you hover a link. It is wrong for a bar that is up forever
on every pane.

Cost, computed from measured pane geometry (`kitty @ --to unix:/tmp/kitty-597 ls`, run
2026-09-16): OS window 4 = 2 panes × 77 cols × 47 lines; OS window 5 = 3 panes × 51 cols × 47
lines. `repaint_delay 16` (`config/kitty.conf`) ⇒ ≤ 62.5 frames/s.

| | value |
|---|---|
| cell width (Monaco 18 pt @ dpi 144, advance 0.602 em) | ≈ 21–22 px — **UNMEASURED, derived** |
| 77-col pane texture | ≈ 1690 × 47 × 4 B = **≈ 310 KiB / frame / pane** |
| 51-col pane texture | ≈ 1122 × 47 × 4 B = **≈ 206 KiB / frame / pane** |
| all 5 live panes | ≈ 1.24 MiB **per frame** |
| at 62.5 fps during streaming output | **≈ 78 MiB/s of texture upload** |
| GL texture objects created+destroyed | **≈ 310 / s** |

against a static strip of text that, **measured, does not change** (see F6). Frames are only
produced when something needs rendering (`~/kitty-482 kitty/child-monitor.c:859` returns
`needs_render`), so an idle fleet costs nothing — but the operator's five panes are streaming
Claude Code output, which is the case that matters.

For comparison the thing being replaced — the Python/Pillow daemon — re-sends a PNG per pane every
2 s. On **upload bandwidth** the band is roughly 30× worse; on **resident memory and process
count** the band is unambiguously better (no Python, no Pillow, no socket, no timer). The design's
memory-pressure claim is true; its latency/bandwidth claim, as specified, is false.

### Fix
Cache the texture on the `WindowBarData` (add `GLuint texture_id` + a `dirty` flag), upload only
when `needs_render` fired, and `glDeleteTextures` on window close. That is the change that makes
the per-frame cost a single `draw_graphics` with a bound texture — genuinely near-zero. It is
also a change `render_a_bar`'s existing two callers benefit from, so it is upstreamable.

**Status: sizes CONFIRMED by code read; pane counts and column counts MEASURED live; cell width
and therefore the byte figures DERIVED, marked UNMEASURED.**

---

## F6 — CLEAN NEGATIVE: the title-string-churn attack does NOT reproduce

I expected the CPU cache at `~/kitty-482 kitty/shaders.c:852` (keyed on PyObject identity of the
title) to miss constantly, because Claude Code puts an animated spinner glyph in its pane title —
the live `ls` shows three different leading glyphs across panes (`✳`, `◐`, `◑`).

Measured, 66 samples of `kitty @ --to unix:/tmp/kitty-597 ls` at 250 ms over 20.1 s, 5 panes:

```
win 3    title-changes=0    rate=0.00/s  distinct=1  ['◐ Claude Code']
win 4    title-changes=0    rate=0.00/s  distinct=1  ['✳ Forward Deployed Engineer laptop email']
win 5    title-changes=0    rate=0.00/s  distinct=1  ['✳ Kitty window drag implementation phase 3']
win 7    title-changes=0    rate=0.00/s  distinct=1  ['◑ Kernel panic 2026-09-16 investigation']
win 9    title-changes=0    rate=0.00/s  distinct=1  ['◑ Claude Code']
```

**REFUTED.** The glyph is a phase marker, not an animation frame: it changes at phase boundaries,
not per frame. The CoreText render cache holds and the per-frame CPU cost is the texture upload
of F5 only. Recorded because a plausible attack that fails is worth as much as one that lands, and
because the sampling window is short — a 20 s window cannot see a pane that changes title once a
minute, so this bounds the *rate*, not the *existence*, of churn.

---

## F7 — THE HIT TEST CANNOT BE REACHED THE WAY THE DESIGN ASSUMES, AND THE FIRST 12 px OF THE BAND BELONG TO THE BORDER RESIZER  (severity: high, likelihood: certain)

### 7a. The brief's statement of the obstruction is right, and slightly under-stated

```
~/kitty-482 kitty/mouse.c:1067-1082
        for (unsigned int i = 0; i < t->num_windows; i++) {
            Window *win = t->windows + i;
            if (contains_mouse(win) && win->render_data.screen) {
                ans.window_idx = i; ans.window = win; break;
            } else if (detect_title_bar && win->visible) {
                const WindowRenderData *trd = &win->window_title_render_data;
                ...  ans.in_title_bar = true; ...
            }
        }
```
```
~/kitty-482 kitty/mouse.c:269-273
contains_mouse(Window *w) { ... return (w->visible && window_left(w) <= x && x < window_right(w)
     && window_top(w) <= y && y < window_bottom(w)); }
~/kitty-482 kitty/mouse.c:284-286
window_top(Window *w) { return w->render_data.geometry.top - w->padding.top; }
```

`window_padding_width 0 5 0 5` ⇒ `padding.top == 0` ⇒ `window_top(w) == geometry.top` ⇒ the band,
drawn at `ui->screen_top == srd->geometry.top` (`~/kitty-482 kitty/shaders.c:1439`, `:872`), is
**exactly** inside `contains_mouse`. The `else if` is unreachable for it. **CONFIRMED.**

### 7b. But there is a second gate ABOVE that one, and it is the one that actually bites

`mouse_region` runs the border-resize test first, and **returns early** when it hits:

```
~/kitty-482 kitty/mouse.c:1004-1063
        if (detect_borders && num_visible_windows(t) > 1) {
            double dpi = (w->fonts_data->logical_dpi_x + w->fonts_data->logical_dpi_y) / 2.;
            double tolerance = ((long)round((OPT(window_drag_tolerance) * (dpi / 72.0))));
            ...
            if (ans.window_border) { ... return ans; }
```

`window_drag_tolerance 6` (pt) at dpi 144 ⇒ **tolerance = 12 device px**. Every horizontal border
claims 12 px on each side of itself. The band starts at `geometry.top`, i.e. immediately below
the pane's top border. Therefore:

| band region (measured from `geometry.top`) | what `mouse_region` returns | cursor | press does |
|---|---|---|---|
| 0 – 12 px (23.5 % of the 51 px band) | `window_border` set, **early return** | `NS_RESIZE_POINTER` (`~/kitty-482 kitty/mouse.c:1380`) | starts a **border resize drag** (`drag_resize_start`, `~/kitty-482 kitty/mouse.c:1383-1389`) |
| 12 – 51 px | falls through to the window loop | whatever we make it | whatever we make it |

So even after the hit test is made reachable, the top quarter of the band is a resize handle, the
cursor *changes* as the pointer travels down through a single visual band, and a press near the
top edge resizes the split instead of grabbing the title. This is guarded by
`num_visible_windows(t) > 1`, which is true in both of the operator's live tabs (2 and 3 panes,
measured below).

### 7c. The fix, and why the obvious one is wrong

- **Wrong:** reorder the loop to test the band before `contains_mouse`. That does not help — the
  border test already returned. And it makes every pane's row 1 unclickable (F8).
- **Wrong:** shrink `contains_mouse` by the band height. `contains_mouse` is the general
  "which window is the pointer in" predicate used by scroll, click, hover, selection, drag-scroll
  and `closest_window_for_event`. Shrinking it makes the band a dead zone for *everything*, which
  is F8 by another route, and silently changes 10 call sites.
- **Less wrong:** add a dedicated `in_window_title_band` arm INSIDE the window loop, tested
  *before* `contains_mouse` for that window only, plus raise the band's top by `tolerance` or
  lower `window_drag_tolerance`. The operator raised it to 6 deliberately
  (`config/kitty.conf:323-327` — *"a comfortable grab target, which is exactly why
  `window_drag_tolerance` is raised to 6"*), so lowering it is a regression trade, not a free fix.
- **Least wrong, and the one I would ship:** do not hit-test the band at all. Use the sibling
  session's `mouse_drag_window` action from a `mouse_map`, which needs no `mouse_region` change
  (see F9).

**Status: CONFIRMED by code read + arithmetic over the operator's live config.**

---

## F8 — A CLICK-DRAG THAT STARTS ON ROW 1 TEARS THE PANE OUT INSTEAD OF SELECTING TEXT, AT A 5 px THRESHOLD  (severity: high, likelihood: high)

Once the band is hit-tested, a press in it takes this branch:

```
~/kitty-482 kitty/mouse.c:1362-1369
    } else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
        mouse_cursor_shape = POINTER_POINTER;
        Window *tw = r.window;
        if (!tw && global_state.window_being_dragged.id) tw = window_for_window_id(...);
        if (tw) handle_window_title_bar_mouse(tw, button, modifiers, action);
```
which forwards to Python:
```
~/kitty-482 kitty/tabs.py:1868-1874
        if action == GLFW_PRESS:
            if (w := boss.window_id_map.get(window_id)) is not None:
                boss.set_active_window(w, switch_os_window_if_needed=True)
            threshold = get_options().drag_threshold
            if threshold: set_window_being_dragged(window_id, False, x, y)
```
and the very next motion event:
```
~/kitty-482 kitty/tabs.py:1855-1864
        if button == -1:  # motion event
            dragged_window_id, drag_started, start_x, start_y = get_window_being_dragged()
            if dragged_window_id and not drag_started:
                threshold = get_options().drag_threshold
                dist_sq = (x - start_x)**2 + (y - start_y)**2
                if threshold and dist_sq > threshold * threshold:
                    set_window_being_dragged(dragged_window_id, True, start_x, start_y)
                    request_callback_with_thumbnail("start_window_drag", ...)
```

`drag_threshold` defaults to **5** and is not overridden in `config/kitty.conf`
(`~/kitty-482 kitty/options/definition.py`, `opt('drag_threshold', '5', ...)`). Five device pixels.

Consequences, all three of which are regressions against today:

1. **No text selection can begin on row 1.** The press never reaches `handle_event` /
   `handle_button_event`, so `screen_start_selection` is never called. The operator has
   `copy_on_select clipboard` (`config/kitty.conf`) — selecting is his primary mouse gesture.
2. **A 5 px twitch while clicking row 1 starts a system drag-and-drop of the whole pane.** The
   `⌘⇧B` gesture is "show me the titles"; the mouse is then over a band with a hand cursor. This
   is a one-slip pane teleport.
3. **A drag that starts BELOW row 1 and passes upward through the band is safe** — but only
   because of an accident: the selection path is taken earlier, at
   `~/kitty-482 kitty/mouse.c:1289-1296` / `1307-1340`, before `mouse_region` is consulted at
   `:1354`. That is an in-progress-drag short circuit, not a design property of the band. Any
   future reordering of that function silently breaks it. **UNMEASURED at runtime**; CONFIRMED by
   reading the ordering of `mouse_event`.
4. **⌘-hover link detection dies inside the band.** `~/kitty-482 kitty/mouse.c:1356`:
   `set_currently_hovered_window(w && !r.window_border && !r.in_title_bar ? w->id : 0, ...)` — a
   hovered title bar sets the hovered window to 0, and `has_hyperlink_target`
   (`~/kitty-482 kitty/shaders.c:902-908`) requires `global_state.mouse_hover_in_window == w->id`.
   Any link that happens to be on row 1 becomes un-hoverable and un-⌘-clickable. With
   `underline_hyperlinks always` set, it will still be underlined — it just will not respond.

### Fix / mitigation
Make the band's press arm **not** arm a drag by default: require a modifier (e.g. only
`cmd+left` on the band starts a drag; a bare left press falls through to `handle_event` so
selection works). That is a behaviour split `handle_window_title_bar_mouse` does not currently
express and would have to be added. Or — again — F9.

---

## F9 — 🚨 THE DRAG ITSELF PERFORMS THE ONE-ROW CONTENT SHIFT THE WHOLE DESIGN EXISTS TO AVOID, IN **EVERY TAB IN THE FLEET**  (severity: **fatal to requirement (a)**, likelihood: certain)

This is the finding I did not expect and it is the strongest one in this document.

Requirement (c) says the band must be draggable. The design gets drag by routing into kitty's
existing window-drag. Kitty's existing window-drag *begins* by turning on the **real,
cell-consuming title bars**:

```
~/kitty-482 kitty/tabs.py:1883-1899
    def start_window_drag(self, pixels: bytes, width: int, height: int) -> None:
        ...
        opts = get_options()
        min_w = opts.window_title_bar_min_windows
        for tm in boss.all_tab_managers:
            tm.mark_tab_bar_dirty()
            for t in tm:
                visible = sum(1 for _ in t.windows.iter_all_layoutable_groups(only_visible=True))
                if not (min_w > 0 and visible >= min_w):
                    t.force_show_title_bars = True
                    t.relayout()
```
and `force_show_title_bars` is exactly the flag that makes the layout reserve a cell row:
```
~/kitty-482 kitty/layout/base.py:409-415
        min_windows = get_options().window_title_bar_min_windows
        visible_groups = tuple(all_windows.iter_all_layoutable_groups(only_visible=True))
        force_show = all_windows.force_show_title_bars
        show_title_bar = force_show or (min_windows > 0 and len(visible_groups) >= min_windows)
        for wg in visible_groups:
            for w in wg.windows: w.show_title_bar = show_title_bar
        self.do_layout(all_windows)
```
```
~/kitty-482 kitty/tabs.py:499-505
    def relayout(self) -> None:
        if self.allow_relayouts:
            if self.windows:
                self.windows.force_show_title_bars = self.force_show_title_bars
                self.current_layout(self.windows)
```

**Evaluate the guard against the operator's config.** He has `window_title_bar_min_windows 0`.
So `min_w = 0`, and `not (min_w > 0 and visible >= min_w)` is `not (False and …)` = **True for
every tab**, including single-pane tabs, in **every tab manager on the machine**
(`for tm in boss.all_tab_managers`). So the instant a drag passes the 5 px threshold:

- every tab in every OS window gets `force_show_title_bars = True`
- every one of them relayouts ⇒ every pane loses a row ⇒ PTY resize ⇒ SIGWINCH ⇒ **the exact
  content shift the operator has rejected in writing more than once** — and not just in the pane
  being dragged, in all nine.
- the user therefore sees, simultaneously, our zero-row band *and* a real one-row title bar.
- on drop it is undone (`~/kitty-482 kitty/boss.py:2036-2041`,
  `~/kitty-482 kitty/tabs.py:1918-1926 _clear_force_show_title_bars`) ⇒ a **second** shift back.

So the design as specified delivers (a) at rest and violates (a) during every use of (c). Two
full-fleet SIGWINCH storms per drag.

### The sibling's `mouse_drag_window` patch does NOT escape this either

```
/Users/chrisren/Development/.worktrees/kitty-drag-impl/docs/patches/kitty-mouse-drag-window-v0.48.2.patch:240-242
+        get_boss().set_active_window(self, switch_os_window_if_needed=True)
+        set_window_being_dragged(self.id, False, data['left_press_x'], data['left_press_y'])
```
It arms the identical `window_being_dragged` state, so the identical motion handler
(`~/kitty-482 kitty/tabs.py:1855`) fires the identical `start_window_drag`. **Both candidate
routes to requirement (c) carry this defect.** It is a property of kitty's drag, not of either
patch.

**Correction to my own first draft of this paragraph.** I wrote that neither patch mentions
`force_show`. Measured (`grep -c force_show` in that directory): the v0.48.2 backport has **0**
hits, the master patch has **5**, the PR body has **1**. So the sibling *is* aware of the flag —
and reading what it does with it makes this finding stronger, not weaker: the master patch moves
`_clear_force_show_title_bars()` **later**, with the rationale *"The title bars forced visible for
the drag must stay visible until the drop has been classified. Hiding them relayouts every window,
which changes both …"* (`kitty-mouse-drag-window.patch:141-142`). It treats the forced bars as
load-bearing for drop classification and deliberately **extends** their lifetime. Nothing in
either patch or the PR body proposes suppressing them, and the backport that would actually be
applied to the operator's build does not touch them at all.

### Fix
A third change, independent of both: make `start_window_drag` skip the `force_show_title_bars`
loop when the new band option is on — the bars are being forced up *only* so the user can see a
drop target, and the band already supplies that. Concretely, gate lines
`~/kitty-482 kitty/tabs.py:1891-1897` on `not opts.<new_band_option>`. Without this the design
cannot satisfy (a) and (c) simultaneously, and that is the whole brief.

**Status: CONFIRMED by code read. The SIGWINCH is inferred from `relayout()`; I did not observe a
resize on the live fleet — UNMEASURED at runtime, and deliberately not tested, since triggering it
would resize the operator's nine working panes.**

---

## F10 — THE WEDGE: it goes from STRUCTURALLY UNREACHABLE today to reachable several times a day  (brief item 5)

### The asymmetry is in the source, with a comment explaining it

Kitty has a C-side escape hatch for the *tab* drag and **none** for the *window* drag:

```
~/kitty-482 kitty/mouse.c:939-955   handle_tab_bar_mouse
    if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_RELEASE && global_state.tab_being_dragged.id
            && global_state.tab_being_dragged.drag_started && !global_state.drag_source.is_active) {
        // Once a system drag and drop is active the release is consumed by it
        // and never delivered to us, so getting one here means the drag never
        // became a system DND ...
        // Clear the drag state so mouse handling is not redirected to the tab
        // bar forever, and swallow the release as it ended an aborted drag.
        zero_at_ptr(&global_state.tab_being_dragged);
```
```
~/kitty-482 kitty/mouse.c:929-937   handle_window_title_bar_mouse
handle_window_title_bar_mouse(Window *w, int button, int modifiers, int action) {
    OSWindow *osw = global_state.callback_os_window;
    if (!osw) return;
    if (button > -1 || global_state.window_being_dragged.id) {
        call_boss(handle_window_title_bar_mouse, "KKddiii", ...);
    }
}
```
Nine lines, no recovery arm. Upstream knew the class, fixed it for tabs, and left it for windows.

### The exact sequence that wedges

1. `⌘⇧B` — the band is up on every pane.
2. Left-press anywhere in the band of any pane (below the 12 px border zone, F7).
   `~/kitty-482 kitty/tabs.py:1868-1874` ⇒ `set_window_being_dragged(id, False, x, y)`.
3. Move ≥ 5 px (`drag_threshold` 5). `~/kitty-482 kitty/tabs.py:1855-1864` ⇒
   `set_window_being_dragged(id, True, …)` + `request_callback_with_thumbnail("start_window_drag")`.
4. `start_window_drag` (`~/kitty-482 kitty/tabs.py:1883`) sets `force_show_title_bars` fleet-wide
   (F9) and calls `start_drag_with_data` — a real macOS `NSDraggingSession`.
5. **From here the mouse RELEASE is consumed by the DND** — kitty says so itself in the tab-bar
   comment above. The ONLY remaining clearers are:
   - `on_drop` (`~/kitty-482 kitty/boss.py:1993-1998`) — requires the drop to land on a kitty window
   - `on_window_drop` (`~/kitty-482 kitty/tabs.py:2026-2039`)
   - `on_drag_source_finished` (`~/kitty-482 kitty/boss.py:2027-2048`), driven from
     `~/kitty-482 kitty/glfw.c:955-961` `drag_source_callback`'s `finish` macro.
6. If none of those fires — drop onto another Space, onto a non-kitty app that swallows it, an OS
   window closed mid-drag, a cancelled NSDraggingSession that does not call back — then
   `global_state.window_being_dragged.id` stays set forever.

### The symptom, and why it is the worst possible one

`~/kitty-482 kitty/mouse.c:1362` is `|| global_state.window_being_dragged.id`, **unconditional on
position**. So a stuck id routes *every* mouse event in *every* OS window into the title-bar
handler:

- hand cursor everywhere, in every pane
- no click reaches any application, ever
- no text selection anywhere (`copy_on_select clipboard` is dead)
- `force_show_title_bars` never cleared ⇒ every pane in every tab permanently **one row short**
- the only cure is restarting kitty, which means restarting nine live Claude Code sessions

### Is it more reachable with the band than today? YES, and the jump is from ~zero

Today `r.in_title_bar` can only be true when `window_title_render_data.geometry` is non-degenerate
(`~/kitty-482 kitty/mouse.c:1072-1073`), and that geometry is only ever written non-zero when
`show_tb` holds:
```
~/kitty-482 kitty/window.py:1056     show_tb = self.show_title_bar and new_geometry.ynum > 1
~/kitty-482 kitty/window.py:1134-1146  elif self._title_bar_screen is not None:  # writes 0,0,0,0
```
and `show_title_bar` is `force_show or (min_windows > 0 and …)`
(`~/kitty-482 kitty/layout/base.py:409-412`). With `window_title_bar_min_windows 0` and nothing
forcing, **`in_title_bar` is structurally always false on this machine**. There is today no way to
arm `window_being_dragged` at all except `⌘⌥B` (which turns the real bars on) or the sibling's
not-yet-landed `mouse_drag_window` mouse_map.

The band changes that to: an always-live, ~39 px tall, full-pane-width drag-arming strip on
**every pane**, at a 5 px threshold, sitting exactly on the top line of content — which is where
the pointer naturally rests after a scroll-wheel gesture. Reachability goes from **structurally
zero** to **every accidental 5 px drag on row 1**.

### Fix
Port the tab-bar escape hatch to the window path. It is a nine-line paste into
`handle_window_title_bar_mouse` at `~/kitty-482 kitty/mouse.c:929`, using the same predicate
(`action == GLFW_RELEASE && window_being_dragged.drag_started && !drag_source.is_active`) plus a
`_clear_force_show_title_bars` call. **This should land regardless of whether the band ships**, and
it is upstreamable on its own — it is a latent bug in 0.48.2 and master that the sibling's
`mouse_drag_window` action will expose the moment it lands, band or no band.

**Status: CONFIRMED by code read. Not reproduced — reproducing it means wedging the operator's
live fleet. UNMEASURED at runtime, deliberately.**

---

## F11 — WHAT THE BAND DESTROYS: row 1 of every pane, measured on the live fleet  (brief item 1)

Live read, 2026-09-16, `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID kitty @ --to
unix:/tmp/kitty-597 ls` (read-only):

| OS window | tab layout | panes | cols × lines | titles |
|---|---|---|---|---|
| 4 (platform 292) | splits | 2 | 77 × 47 | `✳ Kitty window drag implementation phase 3`, `◐ Claude Code` |
| 5 (platform 414) | splits | 3 | 51 × 47 | `✳ Forward Deployed Engineer laptop email`, `◑ Claude Code`, `◑ Kernel panic 2026-09-16 investigation` |

(The brief says 5 OS windows / 9 panes; **measured now: 2 OS windows / 5 panes**. The fleet
changed between the brief being written and this run. Reported rather than reconciled.)

Every pane reports `in_alternate_screen = False` and `background_opacity = 1.0` — the second of
which is what makes F1 bite.

### Row-1 occupancy census

`kitty @ … get-text --match id:<w> --extent screen | head -1`, 5 panes × 6 rounds at 2 s
(2026-09-16):

```
samples:       30
non-blank:     14          =>  46.7 % of pane-instants have live content on row 1
```
distinct non-blank row-1 contents observed:
```
  ⎿  Stop says: ⚠️  YOUR /goal IS NOT BEING EVALUATED — Claude Code skipped
  without which it read as the run stopping.
⏺ Generator is pre-existing-broken on this tree (19
```

### What is lost

- **One text row of every pane, ~47 % of the time occupied, permanently, while the band is up.**
  Unlike a shell where row 1 is often an old prompt, a Claude Code pane is a *scrolling
  transcript* on the main screen (`in_alternate_screen = False`, measured): every line of output
  passes through row 1 on its way off the top. The band does not hide a static row — it hides a
  **conveyor belt**, so the loss is not 1/47 of the screen, it is 1/47 of *everything the session
  ever printed* while the band is up.
- The three observed row-1 strings are all mid-sentence transcript fragments. Two of them
  (`⎿  Stop says: ⚠️ …`, `⏺ Generator is pre-existing-broken …`) are the **first line of a tool
  result or an assistant turn** — the line that says what the block is. That is the worst single
  line to hide.
- Plus the extra **6 px of row 2** (F3), which eats the top of every full-cell box-drawing glyph
  (`⏺ ⎿ │ ─`) on the second row — and those are the rails that make a Claude Code transcript
  legible.
- Scroll-back is worse, not better: when the operator scrolls up to read, row 1 is arbitrary
  history with no "it's just the oldest line" excuse — and per F1 scrolling back is precisely
  when the band appears.

### Mitigation — and a retraction of my own first draft, in place

~~My first draft proposed drawing the band into reclaimed *padding* instead of over content,
citing `config/kitty.conf` § 3b's finding that rows depend on TOTAL vertical padding and that
`22.5 5 0 5` and `10 5` are both 30 rows.~~ **RETRACTED, on the strength of the record I was
citing.** That measurement was taken when the config was `window_padding_width 10 5`, i.e. 20 pt
of total vertical padding already existed and only had to be *moved*. The live config is
`window_padding_width 0 5 0 5` — **total vertical padding is zero**, so the reservoir would have
to be *created* at a cost of 22.5 pt (one whole cell), and § 3b measures that as one row lost at
rest for roughly 11 % of window heights. The operator has ruled exactly this out in writing:
*"Having a permanent row for a no CLS show/hide row is not the answer."* (`config/kitty.conf`
§ 3b, 2026-09-14). So the design's core claim — **the bar must be drawn outside the grid, over
row 1, because there is no third place** — survives my attack. Recorded because a refuted attack
is evidence for the design.

What survives as a real, cheap mitigation is **narrowing the band to the width of its own text**,
which the existing code already supports and the design does not use:

```
~/kitty-482 kitty/glfw.c:1082-1092   (macOS branch)
draw_window_title(..., size_t *actual_width) {
    ...
    if (actual_width) {
        size_t text_w = cocoa_text_width_for_single_line(buf, height);
        if (text_w > 0 && text_w < width) width = text_w;
        *actual_width = width;
    }
```
`render_a_bar` passes **NULL** for that parameter (`~/kitty-482 kitty/shaders.c:856`), so it always
paints a full-pane-width strip. `dnd.c:1597` and `glfw.c:3100` do pass it. Passing
`&actual_width` and sizing `bar_width` / `border_rect.width` from it turns "100 % of row 1 hidden"
into "≈ the title's own length hidden": for `◐ Claude Code` that is about 15 of 77 columns —
**≈ 19 % of row 1 instead of 100 %**, on the 51-col panes about 29 %. Same band, same font, same
zero rows, one extra argument. This is the single highest value-per-line change available to the
design and it is not in it.

The remaining honest options are: accept the loss; auto-hide the band while the pane is producing
output (which defeats "always fixed"); or `along_bottom` (`render_a_bar` already takes the flag)
— which trades row 1 for the last row, and the last row of a Claude Code pane is its input box.

---

## F12 — RENDERING-ORDER HAZARDS  (brief item 3): two clean negatives and four real ones

### 12a. CLEAN NEGATIVE — scissor/viewport state cannot corrupt the next window

I attacked this and it does not break. The viewport is a real stack, not a single slot:
```
~/kitty-482 kitty/gl.c:156-181
save_viewport_using_bottom_left_origin / save_viewport_using_top_left_origin:
    if (saved_viewports.used >= arraysz(saved_viewports.items)) fatal("Too many nested saved viewports");
restore_viewport:
    if (!saved_viewports.used) fatal("Trying to restore a viewport when none is saved");
```
`render_a_bar` is balanced: one `enable_scissor…`/`disable_scissor` pair
(`~/kitty-482 kitty/shaders.c:875-878`), one `save_viewport…`/`restore_viewport` pair
(`:880-883`), and `draw_rounded_rect` balances its own (`:325-329`). Critically, **all three early
returns are before the first save** (`:844` alloc failure, `:854` null title, `:856`
`draw_window_title` failure), so no path leaks a saved viewport. An imbalance here would be a hard
`fatal()`, not a glitch, so this was worth checking — and it is clean.

One latent hazard to name for the F1 fix: `disable_scissor()` *disables* rather than restoring the
prior scissor state (`~/kitty-482 kitty/gl.c:183-186`). Nothing else has scissor enabled at that
point today. If the band draw is hoisted out of `draw_cells` (which the F1 fix does), the new call
site must be checked for an enclosing scissor. **UNMEASURED — no such site exists yet.**

### 12b. CLEAN NEGATIVE — the tab bar cannot be touched

`os_window_regions` separates central from tab bar (`~/kitty-482 kitty/mouse.c:993`); a window's
`render_data.geometry` lies inside central, and `border_rect` is derived entirely from
`ui->screen_left / screen_top / screen_width` (`~/kitty-482 kitty/shaders.c:872`). The band cannot
reach tab-bar pixels. The tab bar is also drawn first (`~/kitty-482 kitty/child-monitor.c:906`).

### 12c. REAL — the band overpaints the drop-target highlight during the very drag it enables

`draw_drag_preview_overlay` (`~/kitty-482 kitty/shaders.c:796-821`) tints a half or all of the
window with `TINT_PROGRAM` at 25 % (`float a = intensity * 0.25f`), and its quadrant 5 is
documented as *"full window + title bar highlight (title bar hover)"*. It runs at
`~/kitty-482 kitty/shaders.c:1377`, **before** `draw_hyperlink_target` / `draw_window_number`, so
a band added at the end of that list is drawn over it. The band's `blank_canvas` uses
`bg = 0xff000000 | default_bg` — fully opaque — so during a window drag the drop-target tint has
an **opaque un-tinted hole** exactly where the title is. The feature that tells the user where the
pane will land is damaged by the feature that let them start the drag.

### 12d. REAL — the visual bell makes the band flash into existence

`screen->start_visual_bell_at` is one of the terms that forces `needs_layers`
(`~/kitty-482 kitty/shaders.c:1317`). Given F1, on an otherwise non-layered window **the band does
not exist until a bell rings, then appears for the bell's duration and vanishes.** The operator has
`bell_border_color #3a4555` set, so bells are live. `draw_visual_bell` is also at
`~/kitty-482 kitty/shaders.c:1377`, before the bar, so the band punches an opaque hole in the bell
flash as well.

### 12e. REAL (minor) — the band clips the top of the scrollbar

`draw_scrollbar` puts the bar at
`scrollbar_top = window_top_edge + scrollbar_gap_px` where `window_top_edge = ui->screen_top -
spaces.top` (`~/kitty-482 kitty/shaders.c:1013, 1018`), i.e. ≈ `screen_top + 2 px` with
`window_padding_width 0 5 0 5`. That is inside the band's 51 px vertical span, and
`draw_scrollbar` runs first (`:1380`).

Horizontally: `scrollbar_left = screen_left + screen_width + spaces.right − width − gap`, with
defaults `scrollbar_width 0.5`, `scrollbar_gap 0.1` cell widths
(`~/kitty-482 kitty/options/definition.py`) ⇒ ≈ 11 px + 2 px = 13 px against `spaces.right` = 5 pt
= 10 px ⇒ the scrollbar reaches **≈ 3 px into the content area**, so the overlap is real but
small (≈ 27 % of the bar's width, for the top 49 px only). **Cell width DERIVED, so the 3 px is
UNMEASURED.** Why it still matters: per F1, scrolling back is what *creates* the band, so the one
moment the band exists is the one moment the scrollbar also exists, and the band is drawn over the
thumb's top-of-history position. `scrollbar_interactive yes` (default) means the hit region stays
live under it — an invisible but clickable affordance.

### 12f. REAL — window logo, background image, transparency

- `draw_window_logo` runs at `~/kitty-482 kitty/shaders.c:1364`, before the bar ⇒ the band cuts
  the top 51 px off any window logo. Not set here.
- A background image forces `needs_layers` permanently
  (`~/kitty-482 kitty/child-monitor.c:760`), so F1 does not bite — but the band's opaque
  `blank_canvas` punches a rectangular hole in the image on every pane. Not set here.
- `background_opacity < 1`: the band is drawn with `bg = 0xff000000 | …` (alpha forced to 255,
  `~/kitty-482 kitty/shaders.c:849-850`) and `cocoa_render_line_of_text` fills its bitmap with that
  alpha (`~/kitty-482 kitty/core_text.m:957`), so **the band is an opaque strip across an otherwise
  translucent terminal.** `blank_canvas(ui->bg_alpha, …)` does use the window alpha for the clear,
  but the texture drawn over it does not. Measured live: `background_opacity = 1.0`, so this does
  not bite today — it bites the first time the operator tries a translucent window.

### 12g. REAL — sRGB encoding, and it is created BY the F1 fix

`render_a_bar` calls `blank_canvas(ui->bg_alpha, bg, /*for_final_output=*/ false)`
(`~/kitty-482 kitty/shaders.c:877`), and `blank_canvas`'s two branches differ by exactly a
linear↔sRGB conversion (`~/kitty-482 kitty/shaders.c:1386-1400`). `false` is correct **only**
because everything in layers mode is drawn into an offscreen linear texture and blitted
(`~/kitty-482 kitty/shaders.c:1641-1668`, `:1670-1692`). On the direct path the framebuffer is
sRGB-encoding and every drawing call brackets itself: `call_cell_program(..., for_final_output)`
does `glEnable(GL_FRAMEBUFFER_SRGB)` (`~/kitty-482 kitty/shaders.c:1339-1341`) and `draw_borders`
does `if (!w->needs_layers) glEnable(GL_FRAMEBUFFER_SRGB)`
(`~/kitty-482 kitty/shaders.c:1502-1504`).

**So the F1 fix — moving the band draw onto the non-layers path — silently puts a linear-encoded
clear and an `GL_SRGB_ALPHA` texture draw into an sRGB framebuffer with no bracketing.** Predicted
symptom: the band's background renders markedly darker than the terminal background (and the
layers path renders it correctly), i.e. the band changes colour depending on whether a scrollbar
happens to be showing. That is an extremely hard bug to attribute after the fact.
**Mechanism CONFIRMED by the three sites that do bracket; the magnitude is UNMEASURED.**
Fix: bracket the band draw in `glEnable/glDisable(GL_FRAMEBUFFER_SRGB)` when
`!os_window->needs_layers`, exactly as `draw_borders` does.

---

## F13 — BEHAVIOUR UNDER THE NAMED CASES  (brief item 4)

| case | behaviour | evidence | severity |
|---|---|---|---|
| **single-pane OS window** | Band draws (the loop at `~/kitty-482 kitty/child-monitor.c:914` has no window-count guard). But `mouse_region`'s border arm is gated on `num_visible_windows(t) > 1` (`~/kitty-482 kitty/mouse.c:1004`), so the full 51 px is drag-armed, with nothing to reorder it against. A 5 px slip detaches the only pane into a new OS window (`~/kitty-482 kitty/boss.py:2044-2048` `_move_window_to(..., 'new')` — guarded by `total_windows > 1`, so it no-ops; the fleet-wide `force_show` relayout of F9 still happens). | code read | medium |
| **Stack layout** (`enabled_layouts splits,stack`, `⌘⇧Z`) | Only the active window is `visible`, so exactly one band draws and `num_visible_windows == 1` ⇒ same as single-pane. The band shows the *active* pane's title only, so in stack mode the band tells you nothing you did not already know from the tab title — the feature's value goes to zero exactly where pane identity matters most. | code read | medium |
| **overlay window** (`launch --type=overlay`) | The overlay and its parent share a `WindowGroup` and geometry; only the overlay is visible, so the band shows the **overlay's** title, not the underlying session's. The operator reaches overlays constantly: `detach_window ask` (⌘⇧O), `confirm_os_window_close -1`, and `kitty-confirm-close` on ⌘W / ⌃⇧W / ⌘⇧W (`config/kitty.conf`). During any confirm dialog the band relabels the pane. | code read | low |
| **`ynum == 1`** | **Kitty's own title bar refuses this case and the band has no equivalent guard.** `~/kitty-482 kitty/window.py:1056`: `show_tb = self.show_title_bar and new_geometry.ynum > 1`. A one-row pane with the band on has **100 % of its content covered**. `draw_window_number` shows the idiom to copy: `requested_height > (ui->cell_height + 1) * 2` (`~/kitty-482 kitty/shaders.c:942`). Reachable via `start_resizing_window` (⌘R, bound). | code read | **high — must be guarded** |
| **DPI change / moving between monitors** | `cocoa_render_line_of_text` → `ensure_ui_font(height)` is a **process-wide singleton keyed on ONE height**: `static size_t for_height = 0; if (system_ui_font) { if (for_height == in_height) return true; CFRelease(system_ui_font); }` (`~/kitty-482 kitty/core_text.m:922-942`). Two OS windows at different DPI ⇒ different `cell_height` ⇒ different `bar_height` ⇒ **the CTFont is released and recreated twice per frame, forever.** Today this is invisible because no two `render_a_bar` clients are live at once; a persistent per-pane band across two monitors makes it permanent. | code read | **high on a multi-monitor desk** |
| **font size change** (`⌃⇧+`) | Handled: `bar->width/height` mismatch triggers `free(bar->buf); malloc(...)` (`~/kitty-482 kitty/shaders.c:841-848`) and `needs_render = true`. `ensure_ui_font` recreates once. Clean. **But** `config/kitty.conf:1092` records that the 22.5 pt figure silently breaks on a `font_size`/`cell_height` change — the band's `cell_height + 2` tracks automatically, so the band is *better* here than the padding route. | code read | none |
| **window closed mid-drag** | Partly handled: `start_window_drag` clears if `window_id_map.get(window_id) is None` (`~/kitty-482 kitty/tabs.py:1885-1887`), `on_window_drop` likewise (`:2038-2040`), and `on_drag_source_finished` gates on `get_window_being_dragged()[0] == window_id` (`~/kitty-482 kitty/boss.py:2034`). The uncovered path is a **closed OS window**, where `drag_source_callback`'s `finish` may never run — F10. | code read | high (= F10) |
| **two OS windows on different Spaces** | The macOS `NSDraggingSession` crosses Spaces; the drop lands on a window whose `on_drop` may never be delivered to the source process. `start_window_drag` iterates `boss.all_tab_managers` (`~/kitty-482 kitty/tabs.py:1891`) — **all OS windows on all Spaces** get `force_show_title_bars` and a relayout, including ones the user is not looking at, so panes on another Space silently resize. This is the highest-probability F10 trigger. | code read | high |

**All of F13 is CONFIRMED by code read and UNMEASURED at runtime** — every one of these cases would
have to be exercised against the operator's live fleet to measure, and several of them (ynum 1,
mid-drag close, cross-Space drop) are precisely the ones that would wedge it.

---

## F14 — 🚨 A C PATCH CANNOT SATISFY "DEPLOYED AND LIVE FOR ALL CURRENTLY-OPEN KITTY SESSIONS". THAT IS A STATED REQUIREMENT AND THE DESIGN REFUTES IT BY CONSTRUCTION.

The goal statement says, verbatim: *"deployed and LIVE for all currently-open kitty sessions, not
just future ones"*.

Measured, 2026-09-16:
```
$ ps -p 597 -o pid=,lstart=,command=
  597 Wed 16 Sep 16:29:00 2026 /Applications/kitty.app/Contents/MacOS/kitty
$ ls -l /Applications/kitty.app/Contents/MacOS/kitty
-rwxr-xr-x@ 1 chrisren staff 456864 Jul 30 06:51 /Applications/kitty.app/Contents/MacOS/kitty
$ kitty --version
kitty 0.48.2 created by Kovid Goyal
$ brew list --cask | grep -i kitty
kitty
```

The live process has been running since 16:29 today, off a Homebrew-cask binary built 30 July. The
brief's own arithmetic section already states the constraint: *"A kitten CAN monkeypatch the Python
layer of a RUNNING kitty; it CANNOT change C code."* `render_a_bar` is C
(`~/kitty-482 kitty/shaders.c:837`), `mouse_region` is C (`~/kitty-482 kitty/mouse.c:988`), and
`kitty @ load-config` reloads **options only** — `boss.load_config_file` →
`load_config` → `apply_new_options` (`~/kitty-482 kitty/boss.py:3199-3222`, `:3146-3178`). No code
path loads new native code.

So shipping this design means: build a patched kitty, replace `/Applications/kitty.app`, and
**restart kitty** — terminating pid 597 and with it the nine (measured today: five) live Claude
Code agent sessions doing real work. The one thing the current PNG-overlay daemon does *well* is
exactly this: it needs no kitty change at all, so it went live on the running instance.

**This is not a bug in the design; it is a requirement the design cannot meet, and it is not
acknowledged anywhere in the brief's statement of it.** Two secondary consequences:

- **The patch is un-persisted.** `brew upgrade --cask kitty` silently replaces the binary and the
  feature vanishes with no error. It needs `brew pin` or an out-of-Homebrew install, plus something
  that notices when it has been reverted.
- **Bisecting a regression becomes expensive.** Every A/B of the band against stock costs a full
  kitty restart of the operator's working fleet.

### The honest framing
The design should be stated as: *this is the RIGHT long-term answer and it lands on the next kitty
restart; the graphics-protocol overlay remains the only thing that can serve the currently-open
sessions.* Which means the 1179-line Python daemon is not deleted by this work — it is retired at
the next restart. If the design's business case rests on deleting it today, the case is wrong.

---

## F15 — THE TOGGLE IS A FLEET-WIDE FONT-CACHE CLEAR AND RESIZE, NOT A FLAG FLIP

`kitty @ load-config` → `boss.load_config_file` (`~/kitty-482 kitty/boss.py:3199`) unconditionally:
```
        from .fonts.render import clear_font_caches
        clear_font_caches()
        self.apply_new_options(opts)
```
and `apply_new_options` (`~/kitty-482 kitty/boss.py:3146-3160`):
```
        from .fonts.render import set_font_family
        set_font_family(opts)
        for os_window_id, tm in self.os_window_map.items():
            if tm is not None:
                os_window_font_size(os_window_id, opts.font_size, True)
                tm.resize()
```
Every ⌘⇧B press therefore drops the entire glyph cache, re-runs font family resolution, and calls
`tm.resize()` on every OS window on the machine. That is the price of the toggle mechanism the
design inherits — and it is the same price ⌘⌥B pays today, so it is **not a regression**, only an
un-costed part of the design. Recorded because "toggles on and off" reads as free and is not.
`config/kitty.conf:28` independently records that `font_size`/`font_family` do **not** in fact
reach already-open windows through this path, which means the reload does the expensive half and
not the useful half.

---

## THE ANSWER TO BRIEF ITEM 6 — the single most likely way this ships and quietly does the wrong thing

**F1: it is developed while the old PNG daemon is still running, so `grman_has_images()` keeps
`needs_layers` true and the band renders perfectly; the commit that deletes the daemon is the
commit that makes the band invisible, and nobody looks for a rendering regression in a
Python-deletion diff.** Thereafter the band appears only when some *unrelated* overlay forces
layered rendering — you scroll back, hover a link with ⌘, ring a bell, drag the OS window edge —
so it reads as "flaky", the investigation goes to the graphics code, and the actual rule
(`~/kitty-482 kitty/shaders.c:1448`) is one `if` in a different file.

Runner-up, and worse if it lands: **F9**, where the band silently satisfies requirement (a) at rest
and violates it fleet-wide during every exercise of requirement (c) — a defect that only appears
while the user's hand is on the mouse, which is the hardest state in which to notice a one-row
reflow.

---

# RANKED FAILURE MODES

Ranked by (does it break a stated requirement) × (likelihood) × (how hard it is to attribute after
the fact). "Tree" for every file:line is `~/kitty-482` = v0.48.2 unless marked otherwise.

| # | Failure mode | Trigger | Observable symptom | Fix / mitigation | Status |
|---|---|---|---|---|---|
| **1** | **Band never renders** — the draw site is inside `draw_cells_with_layers`, reached only when `needs_layers` (`shaders.c:1448`), and the operator's config makes that false (`background_opacity = 1.0` measured live, no bg image, macOS srgb hardcoded true at `gl.c:70-73`) | ship the band and retire the PNG daemon (which was keeping `grman_has_images()` true) | nothing appears. Then it appears *only* while scrolled back / ⌘-hovering a link / during a bell / during an OS-window resize — reads as "flaky graphics" | call the band from `draw_cells()` after the `if (needs_layers)` branch (`shaders.c:1446-1450`), **not** by adding it to `screen_needs_rendering_in_layers` (that forces the whole fleet onto the expensive layered path permanently) | CONFIRMED (code); runtime UNMEASURED |
| **2** | **"Live for currently-open sessions" is unsatisfiable** — the change is C; `kitty @ load-config` reloads options only (`boss.py:3199-3222`) | ship it | the feature exists only after a kitty restart, killing the live agent sessions; `brew upgrade --cask kitty` silently reverts it | restate the requirement: the band lands at next restart, the overlay daemon keeps serving today. `brew pin` + a parity check | CONFIRMED (measured: pid 597 since 16:29 off a 30-Jul cask binary) |
| **3** | **Every drag forces the real one-row title bars on in every tab in the fleet** — `start_window_drag` sets `force_show_title_bars` and relayouts for all tab managers (`tabs.py:1889-1897`); with `window_title_bar_min_windows 0` the guard is true for *every* tab | press in the band + move 5 px | all nine panes shift down a row (PTY resize + SIGWINCH), then shift back on drop. Requirement (a) violated by requirement (c) | gate `tabs.py:1891-1897` on `not opts.<band_option>` — the bars are forced up only to show a drop target, which the band already supplies. **The sibling's `mouse_drag_window` has the same defect and its master patch deliberately makes the forced bars last *longer*** | CONFIRMED (code); SIGWINCH UNMEASURED (would resize the live fleet) |
| **4** | **Wedge: `window_being_dragged` is never cleared C-side** — `handle_tab_bar_mouse` has an escape hatch (`mouse.c:939-955`), `handle_window_title_bar_mouse` has none (`mouse.c:929-937`) | drag a pane onto another Space / a non-kitty app / close the OS window mid-drag | hand cursor everywhere, **no click or selection reaches any pane in any OS window** (`mouse.c:1362` is unconditional on position), all panes permanently one row short. Cure = restart kitty | paste the tab-bar escape hatch into `handle_window_title_bar_mouse` + `_clear_force_show_title_bars`. **Land this regardless** — it is latent in stock 0.48.2 and master | CONFIRMED (code). Reachability today: **structurally zero** (`in_title_bar` requires non-degenerate `window_title_render_data`, only written when `show_tb`, `window.py:1056` + `layout/base.py:409-412`). With the band: every accidental 5 px drag on row 1 |
| **5** | **Row 1 of every pane is hidden, ~47 % of the time occupied** | band on | the first line of each assistant turn / tool result disappears; a scrolling transcript loses 1/47 of *everything it ever prints* | **narrow the band to its own text width** — `draw_window_title` already computes it via the `actual_width` out-param (`glfw.c:1082-1092`), `render_a_bar` passes NULL (`shaders.c:856`). 100 % of row 1 → ≈19 % on a 77-col pane | **MEASURED**: 14/30 samples non-blank over 5 live panes × 6 rounds × 2 s |
| **6** | **The band is 51 px = 1.13 cells and eats 6 px of row 2** — `bar_height = cell_height + 2`, `border_rect.height = bar_height + 2×border_width`, `border_width = ceil(1 pt × 144/72) = 2` (`shaders.c:838-840, 871-873`; `options/definition.py` `box_drawing_scale '0.001, 1, 1.5, 2'`) | band on | a 6 px bite out of the top of every full-cell glyph on row 2 — `⏺ ⎿ │ ─`, the rails of a Claude Code transcript — plus a 2 px rule 4 px into row 2 and pill-shaped rounded corners (radius = one cell width) | parameterise `render_a_bar` with a `flush_top` mode: `border_width = 0`, `bar_height = cell_height`, `corner_radius = 0`. Must be an added parameter — two existing callers must not change appearance | CONFIRMED (arithmetic over code-read constants) |
| **7** | **Band and ⌘-hover URL bar share `title_bar_data`** — the URL bar keeps state in `url_target_bar_data` but renders through `title_bar_data` (`shaders.c:916` vs `:929`; same in `~/kitty-dev shaders.c:1337` vs `:1353`) | ⌘-hover any link on row ≥ 3 (`shaders.c:915`) | the URL preview is **overdrawn by the band** and invisible; both bars miss the CPU cache every frame, so 2 full CoreText rasterizes per pane per frame | give the band its own `WindowBarData`; fix the pre-existing aliasing at `shaders.c:929` (one word, upstreamable); decide the draw order explicitly. **And add the new field to `destroy_window` (`state.c:418-434`) or leak ≈310 KiB per closed window** | CONFIRMED (code, both trees) |
| **8** | **The top 12 px of the band is a border-resize handle, not a title bar** — `tolerance = round(window_drag_tolerance 6 pt × 144/72) = 12 px`, and `mouse_region` **returns early** when a border matches (`mouse.c:1004-1063`) | hover the top of the band in any tab with >1 visible pane | cursor is `NS_RESIZE` for the top 23.5 % of the band and a hand below it; a press up there resizes the split instead of grabbing the title | raise the band below the tolerance zone, or lower `window_drag_tolerance` (the operator raised it to 6 deliberately — `config/kitty.conf:323-327` — so this is a trade), or drop the hit test entirely and use a `mouse_map` action | CONFIRMED (code + arithmetic) |
| **9** | **No text selection can start on row 1; a 5 px twitch tears the pane out** — the press is consumed by `handle_window_title_bar_mouse` (`mouse.c:1362-1369` → `tabs.py:1868-1874`), `drag_threshold` default 5 | click row 1 | `copy_on_select clipboard` is dead on row 1; an accidental drag detaches the pane; ⌘-hover links on row 1 stop responding (`mouse.c:1356` zeroes the hovered window) | require a modifier for the band's drag arm and let a bare press fall through to `handle_event`. Needs a behaviour split `handle_window_title_bar_mouse` does not currently express | CONFIRMED (code); runtime UNMEASURED |
| **10** | **`ynum == 1` panes are 100 % covered** — kitty's own bar refuses this case (`window.py:1056` `show_tb = … and new_geometry.ynum > 1`); the band has no such guard | `start_resizing_window` (⌘R, bound) a split down to one row | the pane shows only its title, no content, no way to tell it is not hung | copy `draw_window_number`'s idiom: skip when `ui->screen_height <= (ui->cell_height + 1) * 2` (`shaders.c:942`) | CONFIRMED (code) |
| **11** | **`ensure_ui_font` is a process-wide singleton keyed on ONE height** (`core_text.m:922-942`) | two OS windows on monitors of different DPI, both with bands | the system UI CTFont is `CFRelease`d and recreated **twice per frame, forever** | key the cache on height (a tiny map), or round `bar_height` to a shared value | CONFIRMED (code); cost UNMEASURED |
| **12** | **Per-frame texture create / upload / destroy, per pane** — `glGenTextures` + `glTexImage2D` + `free_texture` are unconditional; only the CoreText rasterize is cached (`shaders.c:850-882`) | band on, any pane producing output | ≈1.24 MiB/frame across the 5 live panes ⇒ **≈78 MiB/s** and ≈310 texture objects/s at `repaint_delay 16`, for text that does not change | cache `GLuint texture_id` on the `WindowBarData`, upload only when `needs_render` fired, delete in `destroy_window`. Benefits the two existing callers too — upstreamable | sizes CONFIRMED; byte figures DERIVED from an UNMEASURED cell width |
| **13** | **All four `window_title_bar_*` colours and `window_title_bar_align` are ignored** — `render_a_bar` uses `default_fg`/`default_bg` (`shaders.c:849-851`) and `UIRenderData` has no `is_active` (`shaders.c:34-42`) | band on | the band is the same colour as the terminal; **active and inactive panes look identical**, which is most of the point of a per-pane title | add `bool is_active` to `UIRenderData` (`draw_cells` already receives it, `shaders.c:1409`) and pass explicit fg/bg | CONFIRMED (code) |
| **14** | **sRGB mis-encoding, created BY the fix for #1** — `blank_canvas(..., for_final_output=false)` (`shaders.c:877`) is correct only for the offscreen linear target; the direct path brackets every draw with `GL_FRAMEBUFFER_SRGB` (`shaders.c:1339-1341`, `:1502-1504`) | apply fix #1 | the band's background renders a different (darker) shade than the terminal — **and only when no scrollbar/URL bar/bell is up**, so it changes colour as you scroll | bracket the band draw in `glEnable/glDisable(GL_FRAMEBUFFER_SRGB)` when `!needs_layers`, as `draw_borders` does | mechanism CONFIRMED; magnitude UNMEASURED |
| **15** | **The band overpaints the drop-target tint and the visual bell** — both run before the bar in `draw_cells_with_layers` (`shaders.c:1377-1382`) and the band's bg is forced opaque (`shaders.c:849-850`) | drag a pane; ring a bell | an opaque un-tinted hole in the drop highlight exactly where the title is; on a bell the band *appears* (via #1) and punches a hole in the flash | draw the band before `draw_drag_preview_overlay`, or make it respect `intensity`/alpha | CONFIRMED (code) |
| **16** | **Opaque band on a translucent window** — `bg = 0xff000000 \| …` forces alpha 255 and `cocoa_render_line_of_text` fills with it (`shaders.c:849-850`, `core_text.m:957`) | set `background_opacity < 1` | a solid strip across a translucent terminal | use `ui->bg_alpha` for the texture fill too | CONFIRMED (code). Does **not** bite today — `background_opacity = 1.0` measured live |
| **17** | **Band clips the top of the scrollbar** — `scrollbar_top = screen_top + gap` (`shaders.c:1013, 1018`), drawn first (`:1380`); scrollbar reaches ≈3 px into the content area (`scrollbar_width 0.5` + `scrollbar_gap 0.1` cell widths ≈13 px vs 10 px right padding) | scroll back — which per #1 is also what *creates* the band | the thumb's top-of-history position is hidden while still being clickable (`scrollbar_interactive yes`) | inset the band's right edge by the scrollbar width | CONFIRMED (code); the 3 px is DERIVED from an UNMEASURED cell width |
| **18** | **Overlay windows relabel the pane** — an overlay is the visible window of the group, so the band shows *its* title | ⌘W / ⌃⇧W / ⌘⇧W (`kitty-confirm-close`), ⌘⇧O (`detach_window ask`) | during any confirm dialog every pane's band says something else | read the title from the group's base window, not `ui->window->title` | CONFIRMED (code) |
| **19** | **Stack layout makes the band valueless** — only the active window is visible, so exactly one band draws and it repeats the tab title | ⌘⇧Z (`toggle_layout stack`, bound) | the feature costs a row-1 of content and tells you nothing | none needed; suppress the band in stack layouts | CONFIRMED (code) |
| **20** | **Each toggle is a fleet-wide font-cache clear + resize** — `load_config_file` → `clear_font_caches()` + `apply_new_options` → `set_font_family` + `tm.resize()` per OS window (`boss.py:3199-3222`, `:3146-3160`) | every ⌘⇧B | a perceptible whole-machine hitch per toggle | none available through `load-config`; note that ⌘⌥B already pays this, so it is **not a regression** | CONFIRMED (code) |

---

# ATTACKS THAT FAILED (clean negatives — evidence for the design)

1. **Scissor/viewport corruption of the next window in the loop: REFUTED.** The viewport is a real
   stack with `fatal()` guards (`~/kitty-482 kitty/gl.c:156-181`), `render_a_bar`'s save/restore
   and scissor enable/disable are balanced, and **all three early-return paths precede the first
   save** (`shaders.c:844, 854, 856`). Nothing leaks. See F12a.
2. **The tab bar cannot be reached by the band.** `border_rect` is derived entirely from the
   window's own geometry (`shaders.c:872`), which lies inside `central`. See F12b.
3. **Title-string churn forcing a CoreText re-render every frame: REFUTED by measurement.** I
   expected Claude Code's spinner glyph (`✳ ◐ ◑`, all three observed live) to invalidate the
   PyObject-identity cache at `shaders.c:850` constantly. Measured **0 title changes across 5 panes
   over 66 samples / 20.1 s**. The glyph is a phase marker, not an animation frame. This bounds the
   *rate*, not the existence, of churn — a pane that retitles once a minute is invisible to a 20 s
   window. See F6.
4. **"Draw the band into reclaimed padding instead of over content": REFUTED, and I retract my own
   first draft of it.** The live config is `window_padding_width 0 5 0 5` — total vertical padding
   is **zero**, so a reservoir must be *created* at 22.5 pt (one whole cell), which
   `config/kitty.conf` § 3b measures as one row lost at rest for ~11 % of window heights, and which
   the operator has ruled out in writing: *"Having a permanent row for a no CLS show/hide row is
   not the answer."* **The design's central claim — the bar must be drawn outside the grid, over
   row 1, because there is no third place — survives this attack.** See F11.
5. **Font size change (⌃⇧+) does not break the band.** `bar->buf` is reallocated on a width/height
   mismatch and `needs_render` is set (`shaders.c:841-848`). The band tracks `cell_height`
   automatically, which makes it strictly better here than the fixed-22.5 pt padding route that
   `config/kitty.conf:1092` warns *"silently breaks"* on a font change.

---

# WHAT I COULD NOT MEASURE

Everything here is a code read plus read-only queries against the operator's live instance. **No
kitty was built and nothing was written to pid 597** (per the brief's safety rules). Specifically
UNMEASURED:

- Every rendering claim (F1, F3, F12, F14) at runtime — they are predictions from the call graph.
- Every mouse claim (F7–F10) at runtime — exercising them means clicking in the operator's live
  panes and, for F10, deliberately wedging his fleet.
- `cell_width` for Monaco 18 pt at dpi 144: derived (advance 0.602 em ⇒ ≈21-22 px), never read out
  of a running kitty. Every byte figure in F5 and the 3 px in F12e inherits that.
- The SIGWINCH in F9: inferred from `relayout()` reaching `do_layout`, not observed.
- Whether Claude Code's TUI enables mouse tracking (which would make row-1 clicks meaningful to the
  application as well as to kitty). There is no read-only remote command that reports a screen's
  mouse mode. The operator's `mouse_map … grabbed,ungrabbed` bindings imply he has met both states.
- Fleet size: the brief says 5 OS windows / 9 panes; **measured 2026-09-16: 2 OS windows / 5
  panes.** Reported, not reconciled.


---

## ADVERSARIAL VERIFICATION

**Verifier:** adversarial re-measurement pass, 2026-09-16, independent of the author.
**Method:** every cited `file:line` re-opened in the tree it names (`~/kitty-482` @ `2cb1d95c3`,
`~/kitty-dev` @ `1d67ecd47`); every measurement re-run against the live instance (`unix:/tmp/kitty-597`,
read-only, `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID` on every call).
**Headline:** the three fatal findings (F1, F9, F14) survive intact and their citations are exact.
Three *derived* claims do not survive: F10's consequence, F11's 46.7 % as a decision number, and the
recommendation's "≈ 19 %". One universal ("no third place") needs a scope bound.

### UPHELD — re-read in the named tree, citations exact

- **F1.** `~/kitty-482 kitty/shaders.c:1381-1382` are the only two `render_a_bar` consumers, both
  inside `draw_cells_with_layers`; `:1345-1347 draw_cells_without_layers` is one
  `call_cell_program` and calls none of them; `:1448-1449` is the branch. `needs_layers` terms
  verified verbatim at `kitty/child-monitor.c:757-760, 770, 781, 786` and
  `kitty/shaders.c:1316-1320`; macOS sRGB hardcode at `kitty/gl.c:70-73` (`#ifdef __APPLE__ …
  supports_framebuffer_srgb = true`). Live: `background_opacity 1.0` on both OS windows; config has
  no `background_opacity`, no `background_image`, no `cursor_trail`, no `window_logo`.
  **Corroborated at runtime:** the PNG daemon is running right now
  (`pid 97219 … kitty-pane-title-overlay.py daemon --initial=toggle`), so `grman_has_images()` is
  true today — exactly the corollary-2 trap.
- **F2.** Aliasing exact in both trees: `~/kitty-482 kitty/shaders.c:916` `bd = &window->url_target_bar_data`
  vs `:929 render_a_bar(ui, &window->title_bar_data, …)`; `~/kitty-dev kitty/shaders.c:1337` vs `:1353`.
  `along_bottom = …y < 3` at `:915`; draw order `:1381` then `:1382`. `state.h:276` confirms the two
  fields are distinct. Operator config confirms the precondition (`show_hyperlink_targets cmd`,
  `underline_hyperlinks always`).
- **F3.** `bar_height = cell_height + 2` (`:839`), `border_rect.height = bar_height + 2*border_width`
  (`:871-872`), `border_width = ceil(thickness_as_float(w,1))` (`:838`), `thickness_as_float` =
  `pts * dpi/72` (`:304-310`), `corner_radius = ui->cell_width` (`:886`). 45+2+2·2 = **51 px**.
- **F7/F8.** `mouse_region` runs the border test first and `return ans` at `:1062` (`:1004-1066`);
  `tolerance = round(OPT(window_drag_tolerance) * dpi/72)` at `:1006-1007` (config `6` ⇒ 12 px);
  `contains_mouse` wins the loop at `:1067-1070` with the title-bar test in the `else if` at
  `:1071-1079`; `window_top = geometry.top - padding.top` with `padding.top = 0`
  (`:264-272`, config `window_padding_width 0 5 0 5`). `drag_threshold` default `5`
  (`kitty/options/definition.py:1153-1156`). One gate the section under-states: the border arm is
  also conditioned on `detect_borders && num_visible_windows(t) > 1` (`:1004`), so the 12 px NS_RESIZE
  strip does not exist in a single-pane tab — it appears exactly when the operator splits.
- **F9.** `~/kitty-482 kitty/tabs.py:1889-1897` verbatim; `min_w = 0` ⇒ `not (min_w > 0 and …)` is
  true for every tab in every tab manager; `layout/base.py:409-415` and `tabs.py:499-505` confirm the
  relayout path. Clearers at `boss.py:2036-2041`, `tabs.py:1918-1926`.
- **F9b.** `grep -c force_show`: v0.48.2 backport **0**, master patch **5**, PR body 1. The backport
  arms `set_window_being_dragged(self.id, False, data['left_press_x'], data['left_press_y'])`
  (`kitty-mouse-drag-window-v0.48.2.patch:241`) — the identical state, so the identical motion handler
  reaches the identical `start_window_drag`. Confirmed.
- **F10's asymmetry (not its consequence — see below).** `mouse.c:939-955` escape hatch and
  `:929-937` nine-line handler with no recovery arm, both verbatim. `mouse.c:1362` is unconditional on
  position. `window.py:1056` / `:1134-1146` and `layout/base.py:409-412` confirm F10b: with
  `min_windows 0` and nothing forcing, `in_title_bar` is structurally always false today.
- **F14.** `boss.py:3199-3221 load_config_file` → `:3146-3180 apply_new_options`: options, fonts,
  keymaps, colors. No native-code path exists. A C patch cannot be live for open sessions. The
  RENEGOTIATE recommendation is correct.
- **MUST 4's leak premise.** `state.c:418-434 destroy_window` frees `title_bar_data.buf` and
  `url_target_bar_data.buf` explicitly; a third `WindowBarData` that is not added there does leak.
- **Claim 12 (the retraction), on this config.** `config/kitty.conf` uncommented reads
  `window_padding_width 0 5 0 5` — total vertical padding **0**. The reservoir would have to be
  created, not moved. The retraction is right and the design's core premise survives.

### OVERTURNED — corrected claims

**1. F10's consequence. "Cure = restart kitty" is false; the cure is one click, and the real residual
is a different, likelier defect.**
The author found the C-level asymmetry and stopped one layer too early. The reason the *tab* path
needs a C escape hatch is visible in the Python handler: `tabs.py:1821` `if drag_started: return` —
the tab handler returns on a release **without clearing**. The *window* handler has no such guard:
`tabs.py:1876-1877` reads `dragged_window_id, drag_started = get_window_being_dragged()[:2]` /
`set_window_being_dragged()` and clears **unconditionally** on any left-button non-press event. In the
wedged state `mouse.c:1362` routes every event into that handler, the C guard at `:933`
(`button > -1 || window_being_dragged.id`) passes, and `mouse.c:1364-1367` substitutes the dragged
window when `r.window` is NULL — so the next left press (`tabs.py:1868-1874`, re-arms with
`drag_started=False`) and release (`:1877`, clears) ends it. **Corrected claim:** the window path has a
recovery arm; it is in Python, not C. A stuck `window_being_dragged.id` costs one swallowed click and
the hand cursor until that click, not a kitty restart. **But the sharper residual the section missed:
nothing on that release path clears `force_show_title_bars`.** The only clearers are
`boss.py:2038-2040`, `tabs.py:1910`, `tabs.py:2035` and the `toggle_window_title_bars` action
(`boss.py:3492-3504`) — and that action is **bound to nothing** in `config/kitty.conf` (⌘⌥B is a
`kitty-pane-title-toggle.sh` load-config of `min_windows`, which cannot clear a per-tab
`force_show_title_bars` flag). So the persistent state after an aborted drag is *the fleet one row
short with no bound key that clears it*, which is F9's defect latched, and is both likelier and worse
than the routing wedge. MUST 3 should still land — the paste is nine lines and it is the right place
to also call `_clear_force_show_title_bars()` — but it must be justified on the latched row loss, not
on "restart kitty".
*(Code read only. Not reproduced: reproducing it means arming a drag in the operator's live fleet.)*

**2. F11's 46.7 % is a mixture of a bimodal per-pane state, not a rate, and its stated population
fact is false.**
Re-run, same instrument, 20 rounds × 4 panes = **80 samples, 50.0 % non-blank** — but the per-pane
split is `0/20, 0/20, 20/20, 20/20`: **zero within-pane variance over 40 s**. An earlier 6-round run
of the same panes gave 25.0 % and flipped one pane's verdict entirely. Row-1 occupancy is a *pane
state that persists for minutes*, so the effective n is the number of PANES (4-5), not the number of
samples (30-80); the report's "samples: 30" framing implies a ±18 pp interval it has not earned —
at n=4 panes, 2 occupied, the Wilson 95 % interval is roughly **[0.15, 0.85]**.
And the population claim is falsified: *"Every pane reports `in_alternate_screen = False`"* — measured
minutes later, **3 of 5** and then **3 of 4** panes report `True`, and both panes reading 100 % were
alt-screen panes with a persistent top line. **Corrected claim:** the sizing decision cannot turn on a
fleet mean, because the fleet is bimodal — a main-screen transcript pane loses a *conveyor belt* row
(the report's framing, which is right) while an alt-screen TUI pane loses a *permanently occupied*
row, i.e. 100 %, not 47 %. Decide against the worst stratum. (The instrument is not blind: it returned
both 0 % and 100 % panes in the same run, and preserved leading blank rows, so it can come out the
other way.)

**3. "Change 5 moves 100 % of row 1 hidden to about 19 %" is refuted, measured.**
The band's width is the **title's** rendered width, and the live titles are not `◐ Claude Code`.
Measured on the live fleet (` ` + title, cell-width, vs the pane's columns):

```
win  5  cols  77  title 43 cells =  56%   '✳ Kitty window drag implementation phase 3'
win  3  cols  77  title 14 cells =  18%   '✳ Claude Code'
win  4  cols  51  title 41 cells =  80%   '✳ Forward Deployed Engineer laptop email'
win  9  cols 103  title 14 cells =  14%   '◐ Claude Code'
```
Mean ≈ **42 %**, worst **80 %** — and coverage is *anti-correlated with pane width*, so the narrowest
pane gets the widest band. `draw_window_title` only narrows when `text_w < width`
(`~/kitty-482 kitty/glfw.c:1086-1090`), so an over-long title saturates back to 100 %.
Worse, the quantity that matters is hidden **ink**, not hidden area, and row-1 ink is left-aligned
(first non-space at column 2 in every occupied sample) while `window_title_bar_align left` puts the
band on the left. Measured over 24 occupied row-1 samples (888 non-space cells; autocorrelated across
~2 panes, so treat as a ratio, not a CI):

```
left-aligned  text-width band hides  448/888 =  50% of row-1 ink
right-aligned text-width band hides  304/888 =  34% of row-1 ink
full-width    band                            100% (baseline)
```
**Corrected claim:** change 5 is still the best value-per-line change available — it strictly
dominates a full-width band — but it buys **50 %**, not 81 %, and the *free companion the measurement
actually supports is flipping `window_title_bar_align` to `right`*, worth another 16 pp for zero extra
code. Eliding the title to a fixed column budget is the lever that would beat both.

**4. MUST 4 / SHOULD 5: "one extra argument" understates the work.** Passing `&actual_width` narrows
only the CoreText render. `render_a_bar` uses the full width in four more places that must all be
narrowed or the band stays full-width on screen: the blank scissor rect
(`~/kitty-482 kitty/shaders.c:871-877`, `border_rect.width = ui->screen_width`), the texture upload
(`:869 glTexImage2D(…, bar_width, …)`), the draw viewport (`:880-881`) and the rounded border (`:886`)
— plus the realloc predicate at `:841`, which will now thrash on every title whose rendered width
changes. Direction unchanged; scope corrected.

**5. F1's "wrong tempting fix" costs the wrong thing.** Forcing `screen_needs_rendering_in_layers` does
not "disable the `GL_FRAMEBUFFER_SRGB` fast path" as a separate cost: in the layered path
`call_cell_program` is already called with `for_final_output = false` (`:1358-1371`), so sRGB is simply
deferred to the blit. The real costs are the per-frame per-OS-window FBO round trip and full-viewport
blit (`:1642-1667`, `:1673-1691`). The recommendation (call from `draw_cells()` after the branch,
bracketed in `glEnable/glDisable(GL_FRAMEBUFFER_SRGB)` when `!needs_layers`, mirroring
`draw_borders` at `:1502-1504` — verified verbatim) is correct and unaffected.

### SCOPE BOUND — not a refutation

Claim 12's universal, *"there genuinely is no third place for the bar"*, is established only for
real estate **inside kitty's OS window**: padding (verified 0 vertical today), margins and border
width all pay the same quantised-row cost. A class the report never evaluates is an **out-of-process
overlay** — a borderless always-on-top window/layer tracking each pane rect — which is outside the
grid *and* outside kitty's hit test. I have not measured it and expect it to fail (b) and (c) worse
than the design does, but the claim as written is a universal the evidence does not reach; state it as
*"no third place inside the OS window"*.

### NEW RISK FOUND DURING VERIFICATION

`force_show_title_bars` is also the backing state of the `toggle_window_title_bars` action
(`boss.py:3492-3504`). MUST 2 gates `tabs.py:1891-1897` only, which is correct — but whoever
implements it must not gate `boss.py:3499-3503` as well, or the operator's only mechanism for
clearing a latched forced bar disappears with it. And suppressing the forced bars during a drag does
cost a real affordance: the drop-target highlight rides on those bars
(`tabs.py:1912-1916 _set_drag_target_tab`, `tabs.py:1659` `window_drag_active`). The drop itself is
unaffected — `tabs.py:1928-1935 _find_window_at` resolves on `window.geometry`, not on bar visibility
— so the trade is "visible drop target" against "two fleet-wide content shifts per drag". State it;
do not ship it silently.
