# Per-frame cost of the proposed `render_a_bar` title band

Axis: **Latency and memory — make the band cost ~zero per frame.**
Agent: perf. Date: 2026-09-16.

Trees, and the convention used everywhere below:
* `482:` = `~/kitty-482`, detached at **v0.48.2 (2cb1d95c3)** — the build the operator actually runs.
* `dev:` = `~/kitty-dev`, git master `1d67ecd47` (nightly-21).

Every claim carries a `tree:file:line` or the exact command and its real output.
Anything I could not measure is marked **UNMEASURED** and is not upgraded to a conclusion.

---

## 0. Answer first

**The brief's suspicion is CONFIRMED, and it is worse than "an upload per frame": `render_a_bar`
creates, uploads and destroys a GL texture on *every call*, unconditionally, entirely outside the
`needs_render` guard that protects the CPU-side text layout.** Measured on this box, that costs
**109.9 us per pane per frame** at his 77-column panes — **3.0% of a core, continuously, on the
render thread, to re-upload bytes that did not change** (6.6% at a 12-pane fleet). Roughly **half of
that is not bandwidth at all** but `glGenTextures`/`glDeleteTextures` object churn, which is why
"upload less often" is not the fix on its own.

The fix is small, local and complete: give the band its **own** `WindowBarData` (it currently shares
one with the URL bar and the window-number overlay — §2.1), move the texture id out of a file-scope
`static ImageRenderData` into that struct, upload only when the CPU buffer was re-rendered, and free
it in `release_gpu_resources_for_window`. **Measured post-fix steady state: 0.011 us per pane per
frame** — four orders of magnitude down, i.e. the cost is removed rather than reduced.

Even *unfixed*, the design beats what it retires on every axis except CPU, where it is a wash
(3.0% vs the daemon's ~3.3%) — and "a wash against a Python daemon" is not the operator's bar.
Sections 1-5 make it exact; §7 is the implementation checklist.

---

## 1. CONFIRMED — `render_a_bar` uploads a full RGBA texture on every call

### 1.1 The code

`482:kitty/shaders.c:836-888` is the whole function. The relevant shape:

```c
836  static unsigned
837  render_a_bar(const UIRenderData *ui, WindowBarData *bar, PyObject *title, bool along_bottom) {
838      unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
839      unsigned bar_height = ui->cell_height + 2;
840      unsigned bar_width  = ui->screen_width - 2 * border_width;
841      if (!bar->buf || bar->width != bar_width || bar->height != bar_height) {
842          free(bar->buf);
843          bar->buf = malloc((size_t)4 * bar_width * bar_height);   // CPU buffer: cached, resize-keyed
847          bar->needs_render = true;
848      }
852      if (bar->last_drawn_title_object_id != title || bar->needs_render) {
856          draw_window_title(...)                                   // CoreText: GATED. good.
858          bar->last_drawn_title_object_id = Py_NewRef(title);
859      }
860      static ImageRenderData data = {.group_count=1};               // <-- file-scope static
861      gpu_data_for_image(&data, -1, 1, 1, -1);
862      glGenTextures(1, &data.texture_id);                           // <-- EVERY CALL
863      glBindTexture(GL_TEXTURE_2D, data.texture_id);
864      glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
865-868  glTexParameteri x 4
869      glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB_ALPHA, bar_width, bar_height, 0,
                      GL_RGBA, GL_UNSIGNED_BYTE, bar->buf);           // <-- FULL UPLOAD, EVERY CALL
870      bind_program(GRAPHICS_PROGRAM);
876-878  enable_scissor / blank_canvas / disable_scissor
880-883  save_viewport / draw_graphics / restore_viewport
884      free_texture(&data.texture_id);                               // <-- glDeleteTextures, EVERY CALL
886      draw_rounded_rect(...)
887      return border_rect.height;
888  }
```

**The `needs_render` / `last_drawn_title_object_id` guard ends at line 859.** Lines 860-884 are
unguarded. There is no code path through this function that draws without also creating, filling
and destroying a texture object. `bar->needs_render` is never consulted below line 852, and the
struct has nowhere to keep a texture id anyway:

```
482:kitty/state.h:220-226
typedef struct WindowBarData {
    unsigned width, height;
    uint8_t *buf;
    PyObject *last_drawn_title_object_id;
    hyperlink_id_type hyperlink_id_for_title_object;
    bool needs_render;
} WindowBarData;
```

No `GLuint texture_id`. That absence is the whole bug: the CPU buffer is cached in the struct, the
GPU copy of it is not, so the two are re-synchronised by brute force on every draw.

### 1.2 `static ImageRenderData data` is a second, separate defect

`482:kitty/shaders.c:860` — `data` is **file-scope static, shared by every window and every OS
window**. Today that is survivable only because the two existing consumers are transient and
mutually exclusive in practice. Made always-on across N panes, a single shared `ImageRenderData`
holding a texture id that is generated and deleted inside one call is a structure that *cannot* hold
per-window state at all. The cache fix therefore requires moving the texture id out of it regardless
of the upload question. (`gpu_data_for_image` only rewrites the four vertex corners, so the rest of
`data` is inert — but `texture_id` is not.)

### 1.3 The geometry, MEASURED not assumed

kitty's `ui->cell_width` / `ui->cell_height` / `ui->screen_width` are all in **device pixels**
(`482:kitty/shaders.c:1434-1444`: `cell_width = os_window->fonts_data->fcm.cell_width`,
`full_framebuffer_width = os_window->viewport_width`).

I measured the cell size directly rather than deriving it, by starting a **sandbox** kitty
(own socket, own config, never the operator's instance) carrying the operator's exact font
settings and reading `TIOCGWINSZ` from the child, which kitty fills with device pixels:

```
$ /Applications/kitty.app/Contents/MacOS/kitty --config <operator font settings> \
      --listen-on unix:/private/tmp/ktb-perf/sock --instance-group ktbperf python3 probe.py
$ cat /private/tmp/ktb-perf/winsize.txt
rows=35 cols=108 xpixel=2376 ypixel=1575 cellw=22.0000 cellh=45.0000
```

**cell_width = 22 device px, cell_height = 45 device px.** Exactly integral, so `xpixel =
columns * cell_width` holds and a pane's `screen_width` is `columns * 22`.
(45 device px agrees with the brief's figure; 22 device px agrees with the arithmetic already
recorded at `config/kitty.conf:1118` — "whatever of a pane's slot does not fill a whole 22px cell".)

`border_width` = `ceil(thickness_as_float(os_window, 1))` = `ceil(box_drawing_scale[1] * dpi / 72)`
= `ceil(1.0 * 144 / 72)` = **2 device px**
(`482:kitty/shaders.c:838`, `482:kitty/shaders.c:305-310`, default `box_drawing_scale = (0.001, 1.0,
1.5, 2.0)` at `482:kitty/options/types.py:548`; **not overridden** — `grep box_drawing_scale
config/kitty.conf` returns nothing).

Therefore, per pane:

| quantity | formula | value |
|---|---|---|
| `bar_height` | `cell_height + 2` | **47 px** |
| `bar_width`  | `columns*22 - 2*border_width` | `columns*22 - 4` |
| upload bytes | `bar_width * bar_height * 4` | see below |

### 1.4 The operator's real panes, read live

Read-only, from his instance (the one command the brief permits aiming at it):

```
$ kitty @ --to unix:/tmp/kitty-597 ls
osw 4 tab 4 active=True windows=2 cols=[77, 77]
osw 5 tab 5 active=True windows=3 cols=[51, 51, 51]
total panes 5 · panes in ACTIVE tabs (= the ones that render) 5
```

| pane class | cols | `screen_width` | `bar_width` | bytes per `glTexImage2D` |
|---|---|---|---|---|
| 2-way split  | 77 | 1694 px | 1690 px | `1690*47*4` = **317,720 B** (310.3 KiB) |
| 3-way split  | 51 | 1122 px | 1118 px | `1118*47*4` = **210,184 B** (205.3 KiB) |
| full width   | 157| 3454 px | 3450 px | `3450*47*4` = **648,600 B** (633.4 KiB) |

### 1.5 The per-frame call count — and why it is per **OS window**, not per pane

The band would be drawn from the same place `draw_window_number` / `draw_hyperlink_target` are,
i.e. the tail of `draw_cells_without_layers` (`482:kitty/shaders.c:1377-1382`), which
`draw_cells` runs **once per visible window per frame** from
`render_prepared_os_window` (`482:kitty/child-monitor.c:909-921`).

The damage gate is one level ABOVE that, and it is **per OS window**
(`482:kitty/child-monitor.c:968-982`): `needs_render` is computed from `redraw_count`,
`live_resize`, `viewport_size_dirty`, `prepare_to_render_os_window`, active-window/tab/focus
change. **If any one pane in an OS window has new bytes, every visible pane in that OS window's
active tab is re-drawn** — there is no per-pane damage rect. That is what makes this cost
structural rather than occasional on this operator's machine: he runs 9 Claude Code sessions
streaming tokens, so at least one pane per OS window has new content essentially continuously.

Frame ceiling is `repaint_delay`, which he has set to **16 ms** (`config/kitty.conf:747`,
raised from kitty's default 10 for exactly this reason) → **62.5 frames/s per OS window**.

**Steady state today (5 panes, 2 OS windows), if the band is always on:**

| | per frame | per second @ 62.5 fps |
|---|---|---|
| OS window 4 (2 x 77-col) | 2 uploads, 635,440 B | 125 uploads, **39.7 MB/s** |
| OS window 5 (3 x 51-col) | 3 uploads, 630,552 B | 187 uploads, **39.4 MB/s** |
| **both** | **5 uploads, 1,265,992 B (1.21 MiB)** | **312 uploads, 79.1 MB/s** |

**Projected at the brief's 12-pane fleet** (12 panes of 51 cols): 2,522,208 B = 2.41 MiB per
fleet-frame, **750 texture create/upload/destroy cycles per second, 157.6 MB/s.**

And note what is being spent: in the steady state **not one byte of that has changed** since the
previous frame. `bar->buf` is byte-identical; the guard at line 852 correctly skips the CoreText
re-render; and then lines 862-884 re-upload the identical bytes anyway.

### 1.6 MEASURED: what that upload actually costs, on this box

Bytes are not a cost until something moves them, so I measured the exact GL sequence rather than
estimating it. `/private/tmp/ktb-perf/glbench2.c` opens a headless CGL core-profile context on this
machine and runs three arms differing in **one** thing — where the texture lives:

* **A** = today's `render_a_bar`: `glGenTextures` + 4x `glTexParameteri` + `glTexImage2D` + `glDeleteTextures`
* **B** = texture cached in the struct, but re-uploaded every frame (`glTexSubImage2D`)
* **C** = texture cached and **not** re-uploaded — the post-fix steady state (`glBindTexture` only)

Pipelined (one `glFinish` at the end of the whole arm, which is how kitty actually works — it
finishes once per frame at swap), N=2000 per arm:

```
# GL_RENDERER=Apple M1 Max   GL_VERSION=4.1 Metal - 89.4

bar_width 1690 (77-col pane)          bar_width 1118 (51-col)        bar_width 3450 (full width)
A  109.873 us/call                    A   87.668 us/call             A  218.412 us/call
B   57.319 us/call                    B   38.595 us/call             B  116.302 us/call
C    0.011 us/call                    C    0.011 us/call             C    0.011 us/call
```

A serialized run (`glbench.c`, `glFinish` per iteration) gives 103.9 / 56.8 / 0.022 us at 1690 —
within 6% of the pipelined numbers, which tells us something important: **the driver's texture
upload is synchronous on the calling thread**, so this is not latency that pipelining hides.

**Two things fall out of this decomposition, and the second is the surprise:**

1. **C is effectively free — 0.011 us, four orders of magnitude below A.** The fix does not
   *reduce* the steady-state GPU cost of the band, it *removes* it.
2. **`A - B` is ~52 us at 1690 px, ~49 us at 1118 px, ~102 us at 3450 px.** Roughly half the cost,
   and at the two smaller sizes it is *flat in the byte count*. That half is
   `glGenTextures`/`glDeleteTextures` — **driver texture-object churn, not bandwidth**. So "cache the
   bytes" is not the whole fix and "upload less often" is not either: the *object* must stop being
   created and destroyed per frame. A design that kept `glTexImage2D` but hoisted the id would still
   leave ~55 us/pane/frame on the table.

**Steady-state cost of the band on the operator's live layout, unfixed:**

| | per frame | per second @ 62.5 fps | share of one core |
|---|---|---|---|
| OS window 4 (2 x 77-col) | 219.7 us | 13.7 ms | 1.37% |
| OS window 5 (3 x 51-col) | 263.0 us | 16.4 ms | 1.64% |
| **both, today (5 panes)** | **482.7 us** | **30.2 ms** | **3.0%** |
| projected, 12 x 51-col panes | 1052 us | 65.8 ms | **6.6%** |

Against a 16 ms frame budget that is 1.4-1.6% of the budget per OS window — it will not drop
frames. But it is ~3% of a core burned **continuously, on the render thread, to re-upload bytes
that did not change**, and it scales linearly with pane count and pane width. On the operator's
stated bar ("lowest to zero latency and memory pressure") this is the defect, and it is the one
thing in the proposed design that is not already free.

**Post-fix, the same table reads 0.055 us per fleet-frame, i.e. 0.0003% of a core.**

### 1.7 master is identical — the defect is unfixed upstream

`dev:kitty/shaders.c:1254-1311` is the same function: same file-scope `static ImageRenderData data`
(1285), same `glGenTextures` (1287) / `glTexImage2D` (1294) / `free_texture` (1307), and
`dev:kitty/state.h` carries the same six-field `WindowBarData` with no texture id. The only diff is
cosmetic reformatting plus a changed `draw_rounded_rect` signature (1309). So a caching fix is
**new work against master**, not a backport, and it will not collide with something already landed.

---

## 2. The caching fix, named exactly

### 2.1 🚨 First, a blocker the brief did not anticipate: the band must NOT share `title_bar_data`

`482:kitty/shaders.c:929`:

```c
WindowBarData *bd = &window->url_target_bar_data;     // line 916 - state kept HERE
...
render_a_bar(ui, &window->title_bar_data, bd->last_drawn_title_object_id, along_bottom);
```

The URL bar keeps its *state* in `url_target_bar_data` but renders into **`title_bar_data`**.
`draw_window_number` (`482:kitty/shaders.c:943`) also renders into `title_bar_data`. So **three
consumers already share one buffer**, and `url_target_bar_data.buf` is never allocated at all.

Today that is harmless because all three are transient and effectively mutually exclusive. Add a
**fourth, always-on** consumer and it stops being harmless: every hyperlink hover and every
window-number overlay would overwrite the band's cached pixels and its cached texture, forcing a
full CoreText re-render plus a re-upload on the next frame and again when the hover ends. The cache
would be thrashed to zero at exactly the moments the user is interacting.

**Required: the always-on band gets its OWN field.** Add to `482:kitty/state.h:276`:

```c
WindowBarData title_bar_data, url_target_bar_data, window_band_data;
```

Everything below then applies to `window_band_data` and, for free, fixes the other two.

### 2.2 The struct change

`482:kitty/state.h:220-226` becomes:

```c
typedef struct WindowBarData {
    unsigned width, height;
    uint8_t *buf;
    PyObject *last_drawn_title_object_id;
    hyperlink_id_type hyperlink_id_for_title_object;
    bool needs_render;
    GLuint texture_id;          // NEW: 0 = none. Owned by this struct.
    unsigned tex_width, tex_height;  // NEW: what is actually ON the GPU right now
    color_type drawn_fg, drawn_bg;   // NEW: the colours the pixels were drawn with
    bool drawn_focused;              // NEW: which colour set was used
} WindowBarData;
```

`GLuint` is `unsigned int`; `state.h` does not include a GL header today, so either include
`kitty/gl.h` or declare the field `unsigned int` — kitty already stores texture ids as plain
`GLuint` in `WindowLogoRenderData`, so following that is fine.

`tex_width`/`tex_height` are **separate from** `width`/`height` on purpose: `width`/`height`
describe the CPU buffer, and there is a window in which the CPU buffer has been reallocated but the
texture has not yet been re-created. Keying the upload decision on the CPU dimensions would make
that window invisible.

### 2.3 The render change

Replace `482:kitty/shaders.c:860-869` and `884` with:

```c
    static ImageRenderData data = {.group_count=1};
    gpu_data_for_image(&data, -1, 1, 1, -1);
    if (!bar->texture_id) {
        glGenTextures(1, &bar->texture_id);
        glBindTexture(GL_TEXTURE_2D, bar->texture_id);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        bar->tex_width = bar->tex_height = 0;            // storage not allocated yet
    } else glBindTexture(GL_TEXTURE_2D, bar->texture_id);
    if (rerendered) {                                    // true iff the 852 block ran
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        if (bar->tex_width != bar_width || bar->tex_height != bar_height) {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB_ALPHA, bar_width, bar_height, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, bar->buf);      // reallocate
            bar->tex_width = bar_width; bar->tex_height = bar_height;
        } else {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, bar_width, bar_height,
                            GL_RGBA, GL_UNSIGNED_BYTE, bar->buf);   // same storage
        }
    }
    data.texture_id = bar->texture_id;
```

and **delete the `free_texture(&data.texture_id)` at line 884.** `draw_graphics` binds
`group->texture_id` itself (`482:kitty/shaders.c:658`), so assigning `data.texture_id` is all the
plumbing that is needed.

`rerendered` is a `bool` set inside the existing `if` at line 852 — note that the block can `return
0` on failure, so it must be set **after** `draw_window_title` succeeds, never before.

The `glTexImage2D` vs `glTexSubImage2D` split matters: `glTexImage2D` re-specifies storage (the
driver may allocate a new backing store and orphan the old one); `glTexSubImage2D` writes into
existing storage. The measured gap is the B arm minus the storage-realloc part, and since a resize
is rare it is fine to pay `glTexImage2D` there.

### 2.4 Teardown — the exact function, and why it is the right one

**`release_gpu_resources_for_window()` — `482:kitty/state.c:327-334`.** Add:

```c
    if (w->window_band_data.texture_id) free_texture(&w->window_band_data.texture_id);
    w->window_band_data.tex_width = w->window_band_data.tex_height = 0;
    if (w->title_bar_data.texture_id)   free_texture(&w->title_bar_data.texture_id);
    w->title_bar_data.tex_width = w->title_bar_data.tex_height = 0;
```

`free_texture` (`482:kitty/shaders.c:2038-2041`) already does `glDeleteTextures` + zero the id,
which is exactly the contract needed (zeroed ⇒ the next draw lazily re-creates).

**Every caller already makes the GL context current, and I checked all three:**

| path | makes context current | then reaches |
|---|---|---|
| `remove_window` | `482:kitty/state.c:454` | `remove_window_inner` → `destroy_window` → `release_gpu_resources_for_window` (`state.c:429`) |
| `detach_window` | `482:kitty/state.c:478` | `release_gpu_resources_for_window` directly (`state.c:479`) |
| `remove_tab_inner` | `482:kitty/state.c:541` | `destroy_tab` → `remove_window_inner` → ... (`state.c:531`) |

So no new context management is needed. **Do not** put the `free_texture` in `destroy_window`
alongside the `free(bar->buf)` at `state.c:426` — that would also be reached from
`destroy_mock_window` (`482:kitty/state.c:1568-1573`) and from `finalize()`'s detached-window loop
(`482:kitty/state.c:1881-1886`), neither of which has a context current. `finalize()` already states
the house rule for shutdown in a comment: *"we leak the texture here since it is not guaranteed that
freeing the texture will work during shutdown and the GPU driver should take care of it when the
OpenGL context is destroyed."* Follow it.

🚨 **`detach_window` is not a corner case for THIS feature — it is requirement (c).** Dragging a
pane between OS windows runs `detach_window` → `add_detached_window` (a `memcpy` of the whole
`Window` struct, `482:kitty/state.c:468-472`) → later `attach_window` (`482:kitty/state.c:502-521`,
another `memcpy` back, then `create_gpu_resources_for_window`, which does **not** know about the
band). Releasing + zeroing in `release_gpu_resources_for_window` and re-creating lazily on the next
draw is what makes that path correct with no extra code in `attach_window`.

For completeness: kitty creates every OS window's GL context with `common_context =
os_windows[0].handle` as the share group (`482:kitty/glfw.c:1822, 1884`), so texture objects *are*
shared across OS windows and a stale id would not become invalid — but releasing on detach is still
right, because a detached window can sit in `detached_windows` indefinitely holding VRAM for a band
nobody is drawing.

### 2.5 Invalidation triggers — MEASURED: today there are exactly TWO, and both are insufficient

`grep -rn "needs_render" ~/kitty-482/kitty/*.c` over the whole tree: `WindowBarData.needs_render` is
**set in exactly two places** — `482:kitty/shaders.c:847` (the CPU buffer was resized) and
`482:kitty/shaders.c:925` (the hovered hyperlink id changed). Nothing else in kitty ever invalidates
a bar. Same in master (`dev:kitty/shaders.c:1264, 1349`).

| trigger | covered today? | what must change |
|---|---|---|
| **title text changes** | ✅ `bar->last_drawn_title_object_id != title` (852). Pointer identity, and it is **safe**: the struct holds a strong ref (`Py_NewRef`, 858), so the old `str` cannot be freed and its address cannot be recycled under a different string. | nothing |
| **pane resize / split / layout change** | ✅ `bar->width != bar_width \|\| bar->height != bar_height` (841) → realloc + `needs_render = true` | nothing; also set `tex_width=tex_height=0`… no — leave them, §2.3 compares them and re-specifies storage |
| **pane MOVED, same size** (a no-op drag, requirement (c)) | ✅ by omission — nothing changes, so nothing re-renders. Correct and free. | nothing |
| **DPI / scale change** (external monitor) | ✅ *indirectly*: changes `cell_height` ⇒ `bar_height` ⇒ 841 fires. On macOS `draw_window_title` marks `font_sz_pts` and `ydpi` `UNUSED` (`482:kitty/glfw.c:1083`) and sizes the UI font from `height` alone (`482:kitty/core_text.m:922-941`), so height *is* the DPI carrier. | nothing, but add an explicit trigger anyway — see below |
| **colour change** (`kitty @ set-colors`, an OSC 10/11, a theme, `load-config`) | ❌ **NOT COVERED.** `fg`/`bg` are recomputed every call at 850 but the guard at 852 never compares them. The band would keep stale colours indefinitely. Invisible today only because the two existing consumers are transient. | store `drawn_fg`/`drawn_bg`; add `\|\| bar->drawn_fg != fg \|\| bar->drawn_bg != bg` to the 852 guard. This one line covers `set-colors`, OSC, themes and `load-config` **at once**, because they all land in the same colour profile. |
| **focus change (active vs inactive band colour)** | ❌ **NOT COVERED**, and it is load-bearing here: the operator's config sets different active/inactive colours (`window_title_bar_active_background #2f62d8` / `inactive_background #3f5590`). Nothing sets `needs_render` on focus change. | the `drawn_fg`/`drawn_bg` comparison covers it **if** the band's colours are derived from focus. Add `drawn_focused` too if the band ever differs by more than colour. `482:kitty/child-monitor.c:980` already forces an OS-window re-render on focus change, so the frame will happen; only the *re-render* decision is missing. |
| **font change** (`font_family`, `font_size`, `⌘+`/`⌘-`) | ⚠️ **PARTIAL.** Almost always changes `cell_height` ⇒ 841 fires. A font change that keeps the same cell height in device px would leave stale pixels. | set `needs_render = true` on all three bars from kitty's existing font-reload path. |
| **option reload** (`kitty @ load-config`, the operator's `⌘⌥B` route) | ❌ **NOT COVERED** for anything but colour. | set `needs_render = true` on all bars from the options-reload path. |
| **band toggled on/off** (⌘⇧B) | n/a today | on OFF, do **not** free the texture: the user will toggle it back. Free it only in `release_gpu_resources_for_window`. A band that is off simply is not drawn; the idle cost of a retained texture is measured in §5. |

Three of those are one line (`drawn_fg`/`drawn_bg`); two need a `needs_render = true` in an existing
reload path. **None of them is in the per-frame path**, which is the property that matters: the
invalidation set is entirely event-driven.

---

## 3. CPU side — CONFIRMED gated, and priced

### 3.1 The gate is real

`draw_window_title` (`482:kitty/glfw.c:1083-1092`, the macOS branch) →
`cocoa_render_line_of_text` (`482:kitty/core_text.m:945-999`) is called **only** from inside the
`if` at `482:kitty/shaders.c:852`. **CONFIRMED gated** by
`last_drawn_title_object_id != title || needs_render`. This is the one thing in `render_a_bar` that
is already right, and it is why the GPU half is the whole defect.

What it does per un-gated call (`482:kitty/core_text.m:945-999`):
`CGColorSpaceCreateDeviceRGB` → `CGBitmapContextCreate` **over `bar->buf` directly** (no extra
allocation — good) → `ensure_ui_font` → clear + fill → build a nerd-font cascade
(`CFArrayCreate` + `CFDictionaryCreate` + `CTFontDescriptorCreateWithAttributes` +
`CTFontCreateCopyWithAttributes`, **all four per call**) → `NSAttributedString` →
`CTLineCreateWithAttributedString` (full shaping) → `CTLineDraw` → release everything.

### 3.2 MEASURED: what one re-render costs

`/private/tmp/ktb-perf/ctbench.m` replicates that function line-for-line and times it on this box
with one of the operator's real titles (`" ✳ Kitty window drag implementation phase 3"`), N=500:

```
1690x47 : full cocoa_render_line_of_text  60.472 us/call   (cascade block  10.585 us of it)
1118x47 : full cocoa_render_line_of_text  55.750 us/call   (cascade block  12.727 us of it)
```

So a title re-render costs **~60 us of CPU**, of which ~11-13 us is the nerd-font cascade copy that
is rebuilt from scratch on every call and could trivially be cached beside `system_ui_font`.
Worth doing, but it is not the bottleneck: at 60 us per *change* this path is an order of magnitude
cheaper than the 110 us per *frame* the ungated GPU path spends.

### 3.3 MEASURED: how often does it actually fire on this operator's machine?

This matters, because the design's whole claim is that the CoreText path is rare. His pane titles
carry spinner-looking glyphs (`✳`, `◐`, `◑`), which raised the obvious worry that they animate.
Sampled over his live RC socket (one socket connection per sample, no process spawns —
`/private/tmp/ktb-perf/titlesample.py`):

```
sampled 40 times over 4.44s  (111 ms interval) : 0 title changes across all 5 panes
sampled 60 times over 30.70s (512 ms interval) : 0 title changes across all 5 panes
```

**0 changes in 35 s of wall time across 5 panes.** The glyphs are *state* markers, not animation.
UNMEASURED beyond that window — this bounds the rate at <0.03 changes/s/pane during the sample and
does not prove titles never churn. But even the pathological case is survivable: if a title changed
on **every** frame, the CoreText path would add 60 us/pane/frame — still *less* than the 110 us the
unfixed GPU path spends on every frame regardless.

### 3.4 What else must invalidate it

Everything in the §2.5 table. The two that are genuinely missing and would produce visibly wrong
pixels in an always-on band are **colour change** and **focus change**, and both are covered by the
single `drawn_fg`/`drawn_bg` comparison. One further item belongs here rather than in §2.5:

⚠️ **`ensure_ui_font` is a process-wide singleton keyed on height alone**
(`482:kitty/core_text.m:922-941`: `static CTFontRef system_ui_font; static size_t for_height`). If
two OS windows run different font sizes — which kitty allows, and which `kitty @ set-font-size`
without `--all` produces — then `for_height` never matches and **every single call does
`CFRelease` + `CTFontCreateUIFontForLanguage` + `CTFontCreateCopyWithAttributes`**. Today that is
unreachable (the bars are transient); with an always-on band across OS windows of differing font
size it becomes a per-re-render font rebuild. Not a per-frame cost while the title is stable, so it
is a latent sharp edge rather than a blocker — but it should become a small keyed cache
(`height -> CTFontRef`) in the same patch. **UNMEASURED** (I did not build a two-height arm).

---

## 4. Before / after — against the daemon this retires

### 4.1 The daemon, measured live

It **is** running:

```
$ ps -axo pid,ppid,rss,etime,%cpu,command | grep kitty-pane-title-overlay
97219  1  44864  48:53  0.0  .../Python.framework/.../Python \
      /Users/chrisren/.claude/scripts/kitty-pane-title-overlay.py daemon --initial=toggle
```

**RSS 44,864 KB = 43.8 MiB.** CPU sampled directly rather than trusting `%CPU`:

```
$ A=$(ps -o time= -p 97219); sleep 30; B=$(ps -o time= -p 97219)
0:03.65 -> 0:03.66 over 30 s        => 0.01 s / 30 s = 0.033% of one core
lifetime: 3.66 s CPU over 49:37 (2977 s) = 0.12% of one core
```

🚨 **That 0.033% is the IDLE reading — it is not the cost of the feature.** The band is currently
OFF (no `~/.claude/autonomy/kitty-title-overlay.state`, and its log's last line is 17:16 while it is
now ~17:50). I deliberately did **not** turn it on, because doing so writes escape sequences into
the operator's nine live agent panes. The ON-state figures below are therefore derived from the
code with the component costs measured separately, and are labelled as such.

### 4.2 The daemon's ON-state work, from its own constants

`scripts/kitty-pane-title-overlay.py:997`:
`HOLD, HOT_POLL, COLD_POLL, HOT_FOR = 0.35, 1.5, 15.0, 120.0`

* **`HOLD = 0.35 s`** — the accept loop's timeout; on every timeout with the band on it calls
  `paint_frames(st["frames"])` (`:1081`). So the re-assert rate is **2.86 paints/s**, not the
  "2-second timer" the brief assumed. **The brief's figure is REFUTED, in the direction of more
  cost** (5.7x more often).
* **`HOT_POLL = 1.5 s`** — `warm_loop` (`:1012-1019`) runs `targets()` → `kitty_ls(sock)`, which is
  `subprocess.run(["kitty","@","ls"])` (`:kitty_ls`), i.e. **a full process spawn every 1.5 s**.

Measured spawn cost, against my sandbox instance (10 runs):
```
kitty @ ls spawn: min 28.3 ms  median 31.6 ms  max 39.5 ms
```
**31.6 ms of CPU every 1.5 s = 2.1% of one core, continuously**, purely to re-read a pane list.

* Pillow is **not** re-run per poll: `strip_png` is memoised in `_PNG_CACHE` (`:432, :446-449`), so
  rasterisation is paid once per distinct `(width, band_h, text, live, cover_h)`. Good for CPU —
  and a leak, see §5.

### 4.3 The cost the daemon pushes INTO kitty, which is the part nobody counted

`place()` (`:813-853`) transmits **by file path** (`t=f`), so the tty payload is only **251 B**
per pane per paint — that is measured and documented in the script's own header, and it is a real
win over inline base64 (14,142 B). **The brief's "per-pane PNG transmissions" overstates the wire
cost.**

But the bytes were never the cost. The payload is `a=d,d=I` (delete the stored image) followed by
`a=T,f=100,t=f` (transmit from file). Deleting first is mandatory
(`:815-819`: "kitty keys image DATA by id"), so **kitty must re-open, re-read and re-decode the PNG
on every single paint.** kitty decodes with libpng (`482:kitty/png-reader.c:50-122`,
`png_read_image`).

Measured on the operator's **actual** strip files, libpng via PIL (same decoder family), 20 reps each:

```
strip-7102.png  14221 B  1694x90 RGB  decode 0.843 ms
strip-7104.png  12049 B  1122x90 RGB  decode 0.665 ms
strip-7106.png   8239 B  1694x90 RGB  decode 0.629 ms
...
mean decode 0.770 ms over 6 strips
```

**0.77 ms per pane per paint, inside kitty's own main loop.** Note also the strips are **90 px
tall** — two cells — so the resulting placement upload is `1694*90*4` = **609,840 B**, nearly 2x the
C band's 317,720 B.

At `HOLD = 0.35 s`:

| | 5 panes (today) | 12 panes |
|---|---|---|
| libpng decodes in kitty's main loop | 11.0 ms/s = **1.1% of a core** | 26.4 ms/s = **2.6% of a core** |
| worst case in ONE frame, if a paint lands on a frame | 3.9 ms (24% of the 16 ms budget) | **9.2 ms (58% of the budget)** |

That last row is the real indictment: the overlay's re-assert can eat over half a frame budget in
one go, and it is *not* synchronised to the frame — which is a mechanism for the blinking the
operator already reports.

### 4.4 The table

Steady state, band ON, operator's 5 panes. "Fixed band" = §2 applied.

| | overlay daemon (today) | C band, **unfixed** | C band, **fixed** |
|---|---|---|---|
| resident processes | **1** (Python 3.11 + Pillow) | 0 | 0 |
| resident RSS | **43.8 MiB** (measured) | 0 | 0 |
| extra RSS inside kitty | 0 | 5 x `bar->buf` = **1.21 MiB** | same **1.21 MiB** |
| extra VRAM | 5 placements x 609,840 B = **2.91 MiB** (derived) | 0 (created+destroyed per frame) | 5 textures = **1.21 MiB** |
| process spawns/s | **0.67** (`kitty @ ls` @ 1.5 s) | 0 | 0 |
| timer wakeups/s | **2.86** (HOLD) **+ 0.67** (warm) = **3.5** | 0 (rides the existing frame) | 0 |
| bytes to the terminal/s | **3,586 B/s** (5 x 251 B / 0.35 s) | 0 | 0 |
| file I/O /s | **14.3 PNG reads/s** by kitty + 0 writes (cached) | 0 | 0 |
| CPU in the daemon | **2.1%** of a core (spawn) + ~0.1% | 0 | 0 |
| CPU in kitty's main loop | **1.1%** of a core (libpng) | **3.0%** of a core (GL) | **~0%** (0.055 us/frame) |
| **total CPU attributable** | **~3.3% of a core** | **~3.0% of a core** | **~0.0%** |
| worst single-frame hit | **3.9 ms** (24% of budget) | 0.48 ms (3.0%) | ~0 |
| satisfies (b) fixed on scroll | ❌ | ✅ | ✅ |
| satisfies (c) hit-test/drag | ❌ | ✅ (with the C change) | ✅ |

**The unfixed C band is roughly a wash against the daemon on CPU** — 3.0% vs 3.3% — which is the
finding that justifies the brief. It wins on every other axis (no process, no 43.8 MiB, no spawns,
no wakeups, no tty bytes, no file I/O, 8x smaller worst-case frame hit, and it actually satisfies
(b) and (c)), but on the operator's *stated* bar — "lowest to zero latency and memory pressure" —
trading a 3.3% Python daemon for a 3.0% GL churn is not the answer. **§2 is what makes it the
answer: 3.3% -> ~0%, 43.8 MiB -> 0, and 1.21 MiB of VRAM that never moves.**

---

## 5. Allocations that grow per window and are not freed

I walked every allocation the band path touches. Result: **the current C code leaks nothing — but
the proposed design adds exactly one leak, and it is the texture.** The list, with the free site for
each:

| allocation | grows per | freed where | verdict |
|---|---|---|---|
| `bar->buf` (`482:kitty/shaders.c:843`) | window | `destroy_window` `482:kitty/state.c:426, 428`; also `destroy_fake_window_contents` `482:kitty/dnd.c:2385, 2387` (test-only path) | ✅ no leak |
| `bar->last_drawn_title_object_id` (strong ref, `:858`) | window | `Py_CLEAR` at `482:kitty/state.c:425, 427` | ✅ no leak |
| `screen->last_rendered_window_char.canvas` (`482:kitty/shaders.c:952`) | window | `free()` in the Screen dealloc, `482:kitty/screen.c:704` | ✅ no leak |
| `static ImageRenderData data` (`:860`) | nothing — file-scope static, fixed size | n/a | ✅ but see §1.2, it cannot hold per-window state |
| `static char titlebuf[2048]` (`:853`) | nothing — function-scope static | n/a | ✅ |
| `gpu_data_for_image` / `draw_graphics` | nothing — they only write scalars (`482:kitty/graphics.c:1161-1167`) and bind+draw (`482:kitty/shaders.c:651-667`) | n/a | ✅ |
| **`bar->texture_id` — PROPOSED** | **window** | **nowhere, unless §2.4 is applied** | 🚨 **would leak `bar_width*bar_height*4` of VRAM per window, forever** |

### 5.1 The one real hazard the fix introduces

Without the `release_gpu_resources_for_window` change in §2.4, every pane closed, every tab closed,
and every pane **detached during a drag** (requirement (c)!) orphans one texture. At the operator's
sizes that is 205-310 KiB of VRAM per closed pane, unbounded. On a machine where panes are created
and destroyed all day by agent sessions this is the kind of leak that shows up as "kitty is using
2 GB after a week" and is attributed to anything but a title bar. **§2.4 is not optional polish; it
is the other half of the fix.**

### 5.2 Two properties that are not leaks but should be stated rather than discovered

**(a) The band's memory is O(windows ever rendered), not O(visible windows).** `draw_cells` runs
only for `w->visible` windows in the *active* tab (`482:kitty/child-monitor.c:912-921`), so a pane
in a background tab never allocates — but once it has been visible once, `bar->buf` (and, post-fix,
its texture) is retained until the window dies. Switching away from a tab reclaims nothing. At
205 KiB + 205 KiB (RAM + VRAM) per pane: a 40-pane session that has visited every tab holds
**~8.2 MiB RAM + ~8.2 MiB VRAM** permanently. That is acceptable and it is the right trade (a
toggle must be instant), but it should be a documented property, not a surprise.

**(b) Toggling the band OFF must NOT free anything.** The operator toggles with ⌘⇧B; freeing on
"off" would make the next "on" pay a `malloc` + a 60 us CoreText render + a full `glTexImage2D` per
pane — i.e. it would reintroduce exactly the cost being removed, at the one moment latency is
visible. Retain both; free only in `release_gpu_resources_for_window`. The retained idle cost is
row (a).

### 5.3 Live resize is the one case the cache cannot help

During a live resize `bar_width` changes every frame, so line 841 frees + reallocs, sets
`needs_render`, and the fix's `tex_width != bar_width` branch re-specifies storage — ~60 us CoreText
+ ~110 us `glTexImage2D` per pane per frame, i.e. the unfixed cost. That is correct and unavoidable
(the pixels genuinely changed) and it is dwarfed by what kitty already does on a resize. Naming it
so a future reader does not mistake a resize profile for a broken cache.

### 5.4 In the component being RETIRED: one genuine unbounded leak

`_PNG_CACHE` (`scripts/kitty-pane-title-overlay.py:432`, read at `:446-449`) is a plain `dict`
keyed on `(width, band_h, text, live, cover_h)` with **no eviction and no bound**. Every distinct
title string ever rendered is retained with its full PNG bytes for the daemon's lifetime
(`IDLE_EXIT = 6 * 3600`). The strips measure 7.6-16.7 KiB each
(`du -sh ~/.claude/autonomy/kitty-title-strips/` → 292K over 22 files), so a day of agent sessions
renaming their panes accumulates tens of MiB inside a process that already holds 43.8 MiB. It is not
worth fixing — the daemon is what this design deletes — but it belongs in the ledger of what goes
away.

---

## 6. What I could not measure

Marked UNMEASURED rather than reasoned into a conclusion:

* **The daemon's ON-state CPU and RSS.** It is currently off and turning it on writes escape
  sequences into nine live agent panes. §4.2/§4.3 derive the ON-state from the daemon's own
  constants with each component measured separately (spawn 31.6 ms, libpng 0.77 ms, tty 251 B);
  the composition is arithmetic, not a reading.
* **The per-frame cost of the residual draw calls** — `blank_canvas` under scissor, one
  `draw_graphics` quad, one `draw_rounded_rect` — which remain after the fix. These are 3 ordinary
  draw calls per pane against the ~6-10 kitty already issues per pane; I did not build an FBO arm to
  time them. The §1.6 "C" arm (0.011 us) measures the *upload* being gone, not the *draw* being
  free. Expect the post-fix band to cost single-digit microseconds per pane per frame, not zero —
  but the 110 us it replaces is gone.
* **`ensure_ui_font` thrash across OS windows of differing font size** (§3.4). Structurally real
  from the code; I did not build a two-height arm.
* **Whether kitty's libpng path matches PIL's decode time** (§4.3). Both use libpng
  (`482:kitty/png-reader.c:50-122`); I used PIL as the instrument and label it a proxy.
* **The operator's real frame rate.** I used the `repaint_delay 16` ceiling (62.5 fps) as the
  steady-state rate because at least one pane per OS window is streaming continuously and
  `needs_render` is per-OS-window. I did not instrument `os_window->render_calls`, which would need
  a build. Every per-second figure scales linearly if the true rate is lower; the per-frame figures
  do not.

---

## 7. The checklist for whoever implements this

1. Add `window_band_data` as a **third** `WindowBarData` on `Window` (`482:kitty/state.h:276`).
   Do not share `title_bar_data` — §2.1.
2. Add `texture_id`, `tex_width`, `tex_height`, `drawn_fg`, `drawn_bg` to `WindowBarData`
   (`482:kitty/state.h:220-226`).
3. In `render_a_bar` (`482:kitty/shaders.c:836-888`): hoist the texture out of the file-scope
   `static ImageRenderData`, create it lazily, upload **only** when the CPU buffer was re-rendered,
   prefer `glTexSubImage2D` when the size is unchanged, and **delete line 884**.
4. Extend the guard at line 852 with `|| bar->drawn_fg != fg || bar->drawn_bg != bg`, and store them
   when the render succeeds. This is what makes `set-colors`, OSC 10/11, themes, `load-config` and
   **active/inactive focus colour** all correct at once.
5. Set `needs_render = true` on all bars from the existing **font-reload** and **options-reload**
   paths.
6. Free the texture in `release_gpu_resources_for_window` (`482:kitty/state.c:327-334`) — **not** in
   `destroy_window` — because all three reaching callers already make the GL context current
   (`state.c:454, 478, 541`) and the two that do not reach it (`destroy_mock_window`, `finalize`)
   must not delete GL objects. §2.4.
7. Cache the nerd-font cascade font beside `system_ui_font` (`482:kitty/core_text.m:966-982`) —
   ~11-13 us per re-render, cheap to take.
8. Regression to pin: **a frame in which no title, size, colour or focus changed must issue zero
   `glTexImage2D`/`glTexSubImage2D` calls for the band.** That is the property, and it is the one a
   future refactor will silently break.


---

## 8. Housekeeping

Sandbox instance used for the cell-size measurement (§1.3): kitty pid 61821, socket
`/private/tmp/ktb-perf/sock` (deliberately outside the `/tmp/kitty-*` glob), instance-group
`ktbperf`. Its child is `probe.py`, which ends with `time.sleep(600)`, so the instance
**self-terminates ~10 minutes after launch** and `confirm_os_window_close 0` lets it exit without a
prompt. `kitty @ close-window` did not match it (no window matcher resolved from outside the
instance) and this brief forbids `kill`/`pkill`, so it was left to expire. Nothing else was
started, and the operator's instance (pid 597) received **only** read-only `ls` calls — 5 process
spawns plus 100 direct RC-socket `ls` requests for the title-rate sample in §3.3.

Instruments: `instruments-perf/` beside this file (scoped away from `instruments/`, which sibling
agents are also writing into). Everything in §1.6, §3.2 and §4 re-derives from three `clang` lines
in `instruments-perf/README.md`.

---

## ADVERSARIAL VERIFICATION

*Independent re-measurement and re-reading, 2026-09-16, same box (Apple M1 Max, GL_RENDERER
"Apple M1 Max", GL_VERSION "4.1 Metal - 89.4"). New instrument: `instruments-perf/glbench3.c`
(copied into the tree so a reboot cannot reap it — `/private/tmp` did exactly that to this
project's phase-1 artifacts earlier today). Build and run:*

```
clang -O2 -DGL_SILENCE_DEPRECATION -o glbench3 glbench3.c -framework OpenGL
./glbench3 <bar_width> 47 2000 <bar_width+4> 1575
```

**Bottom line: the RECOMMENDATION survives and is strengthened; three of its supporting claims do
not.** Unfixed, the band costs **~3.6% of a core**, which is *worse* than the daemon's 3.3% — so
"roughly a wash" (§1.6, §4.4, headline) is wrong in the direction that makes landing the cache fix
in the same commit **more** urgent, not less. Fixed, it costs **~0.18% of a core**, not ~0% — a 20x
win over the daemon, not an infinite one. The three overturned claims are §1.6's object-churn
attribution, §7 step 6's stated reason, and the focus half of §2.2.

### V.1 The instrument the report lacked

`glbench3` adds two arms to the report's A/B/C:

* **D** — `glGenTextures` + bind + 5 `glTexParameteri`/`glPixelStorei` + `glDeleteTextures`, **no
  upload**. Isolates *object* churn from *bandwidth*. This is the arm §1.6's claim 2 needed and did
  not have.
* **E / F** — the **whole steady state of `render_a_bar` after / before the fix**, into a real
  1575-row FBO: cached-or-fresh texture, `bind_program`, scissor, `blank_canvas` (`glClear`),
  `save_viewport`, `draw_graphics` quad, `restore_viewport`, `draw_rounded_rect` quad at its own
  scissored viewport (`482:kitty/shaders.c:327`). **F deletes the texture *after* the draw that
  sources it, as `482:kitty/shaders.c:884` does.** GL call sequence is faithful; the fragment
  shaders are simplified, so E/F are CPU-side figures.

Medians of 5 reps, load 14.6–22.3 throughout (µs/call, N=2000/arm):

| bar_width | A (report's) | **D object churn** | B | C (report's "fix") | **E post-fix** | **F pre-fix** |
|---|---|---|---|---|---|---|
| 1118 (51 col) | 68.8 | **1.13** | 36.7 | 0.0102 | **6.86** | **105.3** |
| 1690 (77 col) | 99.0 | **1.13** | 55.6 | 0.0105 | **7.04** | **136.5** |
| 2262 (103 col) | 136.6 | **1.12** | 75.0 | 0.0111 | **8.07** | **194.4** |
| 3450 (full) | 192.6 | **1.11** | 112.7 | 0.0102 | **8.58** | **256.9** |

The report's own instruments reproduce for what they measure: `glbench2 1690 47 2000` → A 103.7 /
B 56.6 / C 0.010 (report 109.9 / 57.3 / 0.011); `glbench 1690 47 2000` → A 99.4–101.6 (report 103.9).
Arms A, B, C are sound readings. **What they were taken to mean is where this fails.**

### V.2 OVERTURNED — §1.6 claim 2: the flat term is 1.1 µs, not ~50 µs, and it is not object churn

> *"`A - B` is ~52 µs … Roughly half the cost, and at the two smaller sizes it is flat in the byte
> count. That half is `glGenTextures`/`glDeleteTextures` — driver texture-object churn, not
> bandwidth … A design that kept `glTexImage2D` but hoisted the id would still leave ~55 µs/pane/
> frame on the table."*

**Measured directly, object churn is 1.12 µs** — and it *is* the flat term, holding to ±2% across a
3.1x byte range (1.13 / 1.13 / 1.12 / 1.11). That is **1.1% of A at 1690 px**, not ~50%.

`A − B` is **not** flat and does not reproduce as flat: 32.1 / 42.4 / 61.6 / 79.9 µs at
1118 / 1690 / 2262 / 3450. It scales with the byte count (bytes ×1.51 → `A−B` ×1.32; bytes ×2.04 →
`A−B` ×1.88). The report's "flat at the two smaller sizes" was two points 7% apart in a quantity my
five-rep medians put 32% apart — a two-point read of a sloped line.

**Corrected claim.** Of A's ~99 µs at 1690 px: **1.1 µs is `glGenTextures`/`glDeleteTextures`
object churn, ~42 µs is storage (re)allocation inside `glTexImage2D`, and ~56 µs is the byte
upload itself.** The driver defers all storage until `glTexImage2D` — which is exactly why D is
nearly free and why naming the expensive half "object churn" misattributes it. **§7 step 3 is
unaffected and still correct** (hoist the object, upload only on re-render, prefer
`glTexSubImage2D`), but an implementer reading §1.6 would conclude that hoisting the id is the big
win. It is worth 1.1%. *Not uploading* is worth the other 98.9%.

### V.3 OVERTURNED — the headline: the fix REDUCES the cost by ~95%, it does not REMOVE it

> *"C is effectively free — 0.011 µs, four orders of magnitude below A. The fix does not reduce the
> steady-state GPU cost of the band, it removes it." … "Post-fix, the same table reads 0.055 µs per
> fleet-frame, i.e. 0.0003% of a core."*

**Arm C is at the instrument's own noise floor and measures nothing.** The report's `glbench.c`
prints the proof three lines above it: `Z control (glFinish only) 0.0093 µs/iter` against
`C … net 0.0126 µs`. C is an empty loop containing one `glBindTexture` of an **already-bound**
texture, which the driver discards. It models no part of the post-fix `render_a_bar`.

§6 concedes this in terms (*"the §1.6 'C' arm measures the upload being gone, not the draw being
free … expect single-digit microseconds"*) — and then §1.6's table, the §4.4 comparison and the
executive summary all use 0.011 µs anyway. That contradiction is the defect: **the table is what an
implementer will quote.**

**Corrected claim, and §6's own prediction confirmed.** The post-fix steady state is **6.9–8.6 µs
per pane per frame** (arm E), **~660x the 0.011 µs stated**. It is fixed draw-call overhead — two
program binds, ~8 uniform updates, two `glDrawArrays`, a scissored `glClear`, four viewport changes
— and it scales only weakly with width (6.86 → 8.58 over 3.1x), so it will not be optimised away.

**And today is worse than reported.** Arm F (the real thing, deleting after the draw) is
**136.5 µs at 1690 px against the reported 109.9 — 36% higher.** Arm A deletes a texture nothing has
drawn from; kitty deletes one an in-flight draw still references (`482:kitty/shaders.c:880-884`), and
the driver must defer. `F − E` = 98.4 / 129.5 / 186.3 / 248.3 µs is the cost the fix actually removes.

### V.4 PARTLY OVERTURNED — §1.6's fleet table: right structure, stale inputs, two wrong columns

The **structural half is CONFIRMED by direct read**, and it is the load-bearing half:
`needs_render` is computed per **OSWindow** (`482:kitty/child-monitor.c:969-982`) and
`render_prepared_os_window` then loops **every visible window in the active tab**
(`482:kitty/child-monitor.c:910-921`). One streaming pane does redraw its whole tab. Panes in
*inactive tabs* cost nothing (`:901`) — worth stating, since the projection to 12 panes assumes
they are all in one tab.

Three corrections:

**(a) The inputs are already stale.** Read live and read-only just now, the fleet is **2 OS windows:
osw4 = 2 × 77 cols, osw5 = 1 × 51 cols + 1 × 103 cols** — not `2 × 77 + 3 × 51`. Pane geometry turns
over in hours. A baked `482.7 µs` is a perishable fact in a tracked file, the shape this repo's own
ship-policy table exists to avoid. **Publish the per-pane-per-frame column and the one command that
re-reads the layout**, not the sum.

**(b) Both totals are wrong**, in opposite directions:

| | report | **corrected (arm F / arm E, live layout)** |
|---|---|---|
| per fleet-frame, unfixed | 482.7 µs | **572.7 µs** |
| per fleet-frame, post-fix | 0.055 µs | **29.0 µs** |
| share of one core @ 62.5 fps, unfixed | 3.0% | **3.58%** |
| share of one core @ 62.5 fps, post-fix | 0.0003% | **0.18%** |

On the report's own assumed layout the figures are 588.9 µs / 34.7 µs — the conclusion does not turn
on which layout you use.

**(c) "continuously" is unsupported, and there is now a cheap falsifiable prediction.** `render()`
returns early whenever no input was read and `repaint_delay` has not elapsed
(`482:kitty/child-monitor.c:992`), so 62.5 fps is a **ceiling**, not a rate. §6 marks the true frame
rate UNMEASURED; the headline says "continuously" without the hedge. A bound the report could have
taken for free: **the live kitty (pid 597) is at 4.2–4.5% of a core right now**, with four agent
panes streaming, no band and the daemon off. Adding the unfixed band's 3.58% would be an **~80%
increase in kitty's entire process CPU** — a prediction anyone can check with `ps -o %cpu -p 597`
before and after, and the honest way to state the claim.

### V.5 OVERTURNED — §7 step 6: the stated reason is vacuous (the placement is still right)

> *"The correct teardown home is `release_gpu_resources_for_window`, not `destroy_window`: all three
> reaching callers already make the GL context current, while `destroy_mock_window` and
> `finalize()`'s detached-window loop do not."*

`release_gpu_resources_for_window` has **exactly two call sites**: `482:kitty/state.c:479`
(`detach_window`) and **`482:kitty/state.c:429` — inside `destroy_window` itself**. So both
context-free callers the claim names, `destroy_mock_window` (`:1570`) and `finalize` (`:1883`), reach
it **through `destroy_window`**. The two functions have *identical* exposure to the context-free
paths; one calls the other unconditionally. The stated discriminator does not exist.

**Corrected claim — same placement, different and checkable reason.** It is safe because
`free_texture` zeroes the id (`482:kitty/shaders.c:2038-2041`) and every context-free path is
*necessarily preceded* by a context-ful release that zeroed it: a mock window never renders, and a
detached window went through `detach_window` → `release_gpu_resources_for_window` before `finalize`
ever sees it. This is precisely the `vao_idx > -1` invariant already sitting in that function
(`:329-333`), and today it holds. **Write the guard as `if (bar->texture_id)`, and pin the invariant
as a test** — it breaks the day any *rendered* window reaches `finalize` without passing through
`detach_window`, and `finalize`'s own comment (`:1891-1894`, "not guaranteed that freeing the texture
will work during shutdown") says what that costs. Also reconcile with §5 claim 11, which calls
`detach_window` a path that *hits* the new leak: under step 6 it is the path that **covers** it.

### V.6 PARTLY OVERTURNED — §2.2 (`needs_render`): colour half right, focus half is a conflation

The colour half **stands and is the real finding**: `fg`/`bg` are recomputed every call
(`482:kitty/shaders.c:849-851`) and never compared in the guard at `:852`, so `set-colors`, OSC 10/11,
a theme change and `load-config` all leave stale pixels. `needs_render` is set in exactly two places
(`:847`, `:925`; master `:1264`, and the `draw_hyperlink_target` site). Confirmed by
`grep -rn needs_render kitty/*.c` — every other hit is `CursorTrail` or `OSWindow`, different structs.

**The focus half does not.** `render_a_bar` takes its colours from `screen->color_profile`'s
`default_fg` / `default_bg` — the **terminal's** colours, which focus does not change. The operator's
`window_title_bar_active_background` / `inactive_background` are consumed in the **Python** layer
(`482:kitty/tabs.py:1899-1900`, `482:kitty/window_title_bar.py:52`) and reach the screen through
`window_title_render_data` + `draw_cells` (`482:kitty/child-monitor.c:917-919`) — a path
`render_a_bar` never touches. **So focus produces no wrong pixels today; there is no existing defect
here.** This matters for step 4: a `drawn_fg`/`drawn_bg` compare only fixes focus *if the band is
first made focus-dependent*, which is new work the checklist does not list. Add it, or the band ships
in one colour for focused and unfocused panes — and requirement (c) makes the focused pane change
constantly.

### V.7 PARTLY OVERTURNED — §2.1 (`title_bar_data` sharing): right remedy, three wrong details

Sharing is real and a separate `WindowBarData` is the right call. But:

* **Two existing consumers, not three.** `render_a_bar` has exactly two call sites in either tree
  (`482:kitty/shaders.c:929`, `:943`). The band would be the third.
* **`draw_window_number` does not thrash a title band.** `:943` passes `ui->window->title` — the
  *same* `PyObject` the band would pass — so `bar->last_drawn_title_object_id != title` is false and
  the guard holds. **Only the URL bar thrashes**, because `:929` passes a different object into the
  same buffer.
* **"on every hyperlink hover" is wrong twice.** `show_hyperlink_targets` defaults to **`never`**
  (`482:kitty/options/types.py:666`), and the operator sets it to **`cmd`**
  (`config/kitty.conf:855`), so `has_hyperlink_target` is true only while ⌘ is the last-seen modifier
  **and** the mouse is over a hyperlink. Rare on this box, impossible on a stock one. The remedy
  stands on upstream-correctness grounds, not on measured thrash.

### V.8 UPHELD

* **§1.1 (claim 1)** — every citation re-opened in the tree it names and says what the claim says:
  `482:kitty/shaders.c` guard `:852`, `glGenTextures :862`, `glTexImage2D :869`, `free_texture :884`;
  `482:kitty/state.h:220-226` has no texture field. Master: `:1264`, `:1287`, `:1294`, `:1307`, and
  the function bodies are line-for-line equivalent apart from `draw_rounded_rect`'s signature. **New
  upstream work, not a backport — confirmed.**
* **§1.5 (claim 5), and strengthened.** Cell 22 × 45 device px; `bar_height = cell_height + 2 = 47`
  (`:838`); `border_width = ceil(1.0 pt × 144/72) = 2`. The step the TIOCGWINSZ measurement could not
  reach, now closed from source: `screen_width = geometry.right − geometry.left`
  (`482:kitty/shaders.c:1435`) and `right = xstart + cell_width × xnum`
  (`482:kitty/layout/base.py:175-180`) — **padding lives in `spaces` and is excluded**, so
  `bar_width = cols × 22 − 4` exactly. 1690 at 77 cols. ✓
* **§4 (claim 9), REFUTED-verdict correct.** `HOLD … = 0.35` at
  `scripts/kitty-pane-title-overlay.py:997`, used as the accept timeout at `:1081` with the repaint at
  `:1086` → 2.86 paints/s. `place()` at `:853` transmits `a=T,f=100,t=f` with a base64'd path. Both
  halves read directly.
* **§4 (claim 10), with one scope note.** `hot = st["on"] or (now − touched) < HOT_FOR` (`:1017`), so
  **while the bars are ON the daemon is permanently HOT** and `HOT_POLL = 1.5 s` holds. The 2.1% is
  the right figure for the right comparison condition. Flagging only because the daemon's own comment
  at `:992` says *"measured 0.2%"* — that is the COLD-state figure at `COLD_POLL = 15 s`
  (31.6 ms / 15 s = 0.21%), and a reader who finds it will wrongly think the report is 10x high.
* **§5 (claim 11)** — the free-site audit checks out (`482:kitty/state.c:425-428`, `:429`,
  `detach_window :473-486`, `gpu_data_for_image` allocates nothing at
  `482:kitty/graphics.c:1161-1167`). Subject to the §V.5 reconciliation above.

### V.9 What I could not measure

* **The operator's true frame rate.** Needs an instrumented build (`os_window->render_calls`), which
  the brief forbids. The 4.2–4.5% whole-process reading in §V.4(c) bounds it from outside but does not
  resolve it. **Every per-second and per-core figure in this document — mine included — is a ceiling.**
* **Arm E's fragment cost under kitty's real shaders.** My shaders are trivial; the GL call sequence
  and count are faithful. E is therefore a good CPU-side figure and a floor on total cost. The band is
  ~95K fragments, so the GPU-side delta should be small, but I did not measure it.
* **Whether a real `render_a_bar` in a live frame behaves as arm F.** F reproduces the
  delete-after-draw ordering, which is the property arm A missed, but in a full frame the driver is
  juggling far more state. F is a model, better than A, still a model.

### V.10 What the recommendation should now say

Ship the band; land the cache fix in the **same** commit — for a stronger reason than the report
gives. **Unfixed it is 3.58% of a core against the daemon's 3.3%: not a wash, a regression.** Fixed
it is **~0.18%** — 20x better than the daemon and ~7 µs/pane/frame, which is the single-digit
microseconds §6 predicted and is a fair reading of "zero". Change §7 step 3's rationale from "the
object must stop being created" to "the upload must stop happening" (object churn is 1.1 µs, §V.2),
give step 6 the `if (bar->texture_id)` invariant instead of the false call-site argument (§V.5), and
add the step the checklist is missing: **make the band's colours focus-dependent**, since today
`render_a_bar` has no focus dependence at all and step 4 silently assumes one (§V.6).

*Instrument: `instruments-perf/glbench3.c`. Everything above re-derives from one `clang` line and
`./glbench3 1690 47 2000 1694 1575`. All source citations re-opened in the tree named; no build of
kitty was run; the live instance was touched only by a read-only `kitty @ ls` and `ps`.*
