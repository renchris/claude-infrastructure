# Requirement (d): the system sans-serif face, exactly

**Axis:** what face, weight, size and vertical metrics the `render_a_bar` route actually produces on
this macOS box, and what it costs to make it the operator's SF Pro **Semibold** title face.

**Trees read.** `~/kitty-482` = `2cb1d95c3accadd536bd66ba6bda044973440177` (tag `v0.48.2`, the build the
operator runs). `~/kitty-dev` = `1d67ecd47c0bd68951868c363baa92039d936572` (master). Every citation below
names its tree. **Both trees are byte-identical in the three functions that decide the face**
(`ensure_ui_font`, `cocoa_render_line_of_text`, `render_a_bar`), modulo clang-format and one extra
`draw_rounded_rect` parameter in master — so nothing here is version-sensitive.

**Headline, stated first.** The route gives the right FAMILY for free (`.AppleSystemUIFont` → SF Pro)
and the WRONG WEIGHT (Regular, not Semibold); the weight is a two-line change. **The real work is the
SIZE, and it is not a dial at all.** The macOS path derives the type size from the destination buffer's
pixel height and nothing else, so worst-case ink is pinned at **`ink/band = 0.966` at every band
height** — tighter than the 0.93 the operator has already rejected in writing as *"oversized to its
container"*. Rendered through kitty's own code path, an ordinary accented title **touches the band's
top edge in Regular and both edges in Semibold**. Switching the face to Semibold without also
decoupling size from band height therefore makes (d) look **worse**, not better.

---

## 1. The exact face, verbatim

### 1.1 The macOS branch of `draw_window_title`

`~/kitty-482 kitty/glfw.c:1082-1091` (identical shape in `~/kitty-dev`):

```c
bool
draw_window_title(double font_sz_pts UNUSED, double ydpi UNUSED, const char *text, color_type fg, color_type bg, uint8_t *output_buf, size_t width, size_t height, size_t *actual_width) {
    static char buf[2048];
    strip_csi_(text, buf, arraysz(buf));
    if (actual_width) {
        size_t text_w = cocoa_text_width_for_single_line(buf, height);
        if (text_w > 0 && text_w < width) width = text_w;
        *actual_width = width;
    }
    return cocoa_render_line_of_text(buf, fg, bg, output_buf, width, height);
}
```

🚨 **`font_sz_pts` and `ydpi` are both `UNUSED` on the Apple branch.** `render_a_bar` passes
`ui->os_window->fonts_data->font_sz_in_pts` and `logical_dpi_y`
(`~/kitty-482 kitty/shaders.c:856`) and the macOS implementation **throws both away**. The only
size input that survives is `height` — the pixel height of the destination buffer. This is the single
most consequential fact on this axis: **on macOS the bar's type size is a function of the bar's pixel
height and of nothing else.** (The Linux/FreeType branch at `~/kitty-482 kitty/glfw.c:1138` *does* use
them — so any reasoning ported from the non-Apple branch is wrong here.)

### 1.2 The font object: `CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, …)`

`~/kitty-482 kitty/core_text.m:922-943` (master: `kitty/core_text.m:1018-1039`, byte-identical):

```c
static bool
ensure_ui_font(size_t in_height) {
    static size_t for_height = 0;
    if (system_ui_font) {
        if (for_height == in_height) return true;
        CFRelease(system_ui_font);
    }
    system_ui_font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL);
    if (!system_ui_font) return false;
    CGFloat line_height = MAX(1, floor(CTFontGetAscent(system_ui_font) + CTFontGetDescent(system_ui_font) + MAX(0, CTFontGetLeading(system_ui_font)) + 0.5));
    CGFloat pts_per_px = CTFontGetSize(system_ui_font) / line_height;
    CGFloat desired_size = in_height * pts_per_px;
    if (desired_size != CTFontGetSize(system_ui_font)) {
        CTFontRef sized = CTFontCreateCopyWithAttributes(system_ui_font, desired_size, NULL, NULL);
        CFRelease(system_ui_font);
        system_ui_font = sized;
        if (!system_ui_font) return false;
    }
    for_height = in_height;
    return true;
}
```

Declared `static CTFontRef system_ui_font = nil;` at `~/kitty-482 kitty/core_text.m:40`.

**The face is therefore:**

| property | value | why |
|---|---|---|
| family | the macOS **system UI font** — `.AppleSystemUIFont`, which resolves to SF Pro Text / SF Pro Display by optical size | `kCTFontUIFontSystem` |
| weight | 🚨 **Regular.** There is no weight argument; `CTFontCreateUIFontForLanguage` returns the default (Regular) member of the system family. `CTFontCreateCopyWithAttributes(…, desired_size, NULL, NULL)` changes only the **size** — the matrix and descriptor args are `NULL`, so the weight is carried through unchanged | the call, verbatim above |
| size | `in_height × (default_size / default_line_height)` — i.e. scaled so the font's own line box is exactly `in_height` **pixels** | the `pts_per_px` arithmetic above |
| unit | the `CGBitmapContext` is created 1 px per unit (`CGBitmapContextCreate(rgba_output, width, height, 8, 4*width, …)`, `~/kitty-482 kitty/core_text.m:948`) with **no** CTM scale — so CTFont "points" here are **device pixels** | no `CGContextScaleCTM` anywhere in `cocoa_render_line_of_text` |
| cascade | the bundled **Nerd Font** is added as a cascade list (`kCTFontCascadeListAttribute`) for symbol fallback only — it does not change the primary face | `~/kitty-482 kitty/core_text.m:966-983` |

**So requirement (d) splits cleanly in two and the two halves have very different costs:**
family = **already correct, free**; weight = **Regular, not Semibold — needs a code change**;
size = **derived from the bar height, not configurable, and at our metrics it is much too large**.

---

## 2. Selecting SF Pro Semibold — measured, all five routes

**Instrument.** `/private/tmp/ktb-font/w.m`, a 100-line standalone ObjC program compiled with
`clang -o w w.m -framework Foundation -framework CoreText -framework AppKit`. It replicates
`ensure_ui_font` exactly and then asks CoreText for the PostScript name and `kCTFontWeightTrait`
of each candidate. Box: macOS 15.7.9 (24G830) — printed by the probe itself. **No kitty build was
run** (per the brief's build ban); this measures the same CoreText APIs kitty calls, in the same
process shape.

Actual output, at `size = 40.7333` (the size the route derives for our 45 px cell — see §3):

```
  kCTFontUIFontSystem                ps=.SFNS-Regular    size= 40.733 weight=+0.0000 cap= 28.700
  kCTFontUIFontEmphasizedSystem      ps=.SFNS-Bold       size= 40.733 weight=+0.4000 cap= 28.700
  NSFont systemFontOfSize:weight:Semibold ps=.SFNS-Semibold size= 40.733 weight=+0.3000 cap= 28.700
  NSFont ... Medium                  ps=.SFNS-Medium     size= 40.733 weight=+0.2300 cap= 28.700
  NSFont ... Bold                    ps=.SFNS-Bold       size= 40.733 weight=+0.4000 cap= 28.700
  CTFontCreateCopyWithAttributes(w=0.3) ps=.SFNS-Semibold size= 40.733 weight=+0.3000 cap= 28.700
  CopyWithSymbolicTraits(Bold)       ps=.SFNS-Bold       size= 40.733 weight=+0.4000 cap= 28.700
  NSFontWeight: Regular=+0.0000 Medium=+0.2300 Semibold=+0.3000 Bold=+0.4000
```

**CONFIRMED — two routes reach `.SFNS-Semibold` and they are equally short.**

- `[NSFont systemFontOfSize:sz weight:NSFontWeightSemibold]` — AppKit. `cocoa_render_line_of_text`
  already imports and uses AppKit (`NSColor colorWithCalibratedRed:…`, `~/kitty-482 kitty/core_text.m:963`),
  so this adds **no new framework and no new header**.
- `CTFontCreateCopyWithAttributes(system_ui_font, sz, NULL, desc)` where `desc` carries
  `kCTFontTraitsAttribute → {kCTFontWeightTrait: 0.3}` — pure CoreText, ~8 lines.

**REFUTED as a route to Semibold:** `kCTFontUIFontEmphasizedSystem` and
`CTFontCreateCopyWithSymbolicTraits(…, kCTFontTraitBold, …)` both land on **`.SFNS-Bold`
(weight +0.40)**, one step past Semibold. The overlay's own record picked Semibold deliberately over
Bold; neither of these can express it.

**Note the cap heights are IDENTICAL (28.700) across all seven rows.** SF Pro's weights share cap
height, ascent and descent — only stroke weight and advance change (worst-case advance 223.22 →
233.06 px, +4.4%). So **switching Regular→Semibold changes nothing about the vertical layout in §3**;
it is a pure ink-weight change, and the size question below is orthogonal and much harder.

### 2.1 The smallest clean change

`ensure_ui_font` has no weight input at all. The minimal diff adds one and threads a new option
through. Sketch against `~/kitty-482`:

**(i) The option.** `kitty/options/definition.py`, beside the existing `window_title_bar_*` block
(`~/kitty-482 kitty/options/definition.py:1999-2010`):

```python
opt('window_title_bar_font_weight', 'semibold',
    option_type='window_title_bar_font_weight',
    long_text='Weight of the system UI face used for window title bars on macOS. '
              'One of regular, medium, semibold, bold. Ignored on other platforms.')
```
→ a `float` in `Options` (regular 0.0, medium 0.23, semibold 0.30, bold 0.40 — the measured
`NSFontWeight` values above), landing in `OPT(window_title_bar_font_weight)` via the usual
`kitty/state.h` `Options` struct + `kitty/state.c` `PYWRAP` unpack.

**(ii) `ensure_ui_font` takes the weight and re-keys its cache.** `~/kitty-482 kitty/core_text.m:922`:

```c
 static bool
-ensure_ui_font(size_t in_height) {
-    static size_t for_height = 0;
+ensure_ui_font(size_t in_height, double weight) {
+    static size_t for_height = 0;
+    static double for_weight = -2.0;   // -2 is outside [-1,1], so the first call always misses
     if (system_ui_font) {
-        if (for_height == in_height) return true;
+        if (for_height == in_height && for_weight == weight) return true;
         CFRelease(system_ui_font);
     }
-    system_ui_font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0.f, NULL);
+    system_ui_font = (CTFontRef)CFRetain((CFTypeRef)[NSFont systemFontOfSize:13.0 weight:(CGFloat)weight]);
     if (!system_ui_font) return false;
     CGFloat line_height = MAX(1, floor(CTFontGetAscent(system_ui_font) + CTFontGetDescent(system_ui_font) + MAX(0, CTFontGetLeading(system_ui_font)) + 0.5));
     CGFloat pts_per_px = CTFontGetSize(system_ui_font) / line_height;
     CGFloat desired_size = in_height * pts_per_px;
     …
-    for_height = in_height;
+    for_height = in_height; for_weight = weight;
     return true;
 }
```

🚨 **Two traps in that one hunk, both measured, both easy to ship broken:**

1. **The cache key.** `for_height` is a `static` and the existing code returns early on a height
   match alone. Add the weight to the key or the first bar rendered at a given height pins the weight
   for the life of the process — including across a `kitty @ load-config`. A `static double for_weight`
   initialised to a value **outside** the legal weight range `[-1, 1]` is what makes the first call
   miss; `0.0` would be a legal weight and would make a `regular` config silently skip creation.
2. **The literal `13.0`.** `CTFontCreateUIFontForLanguage(…, 0.f, …)` means *"the system's default UI
   size"*, which the probe measured as **13.0 pt** on this box — but that is a platform default, not a
   constant. `[NSFont systemFontOfSize:0 weight:…]` does **not** mean the same thing (0 is a literal
   zero-size request there). The non-hardcoding spelling is
   `[NSFont systemFontOfSize:[NSFont systemFontSize] weight:w]`. It does not matter numerically —
   `pts_per_px` is a *ratio* and cancels the base size exactly — but it matters to the next reader,
   and a hardcoded 13.0 is the kind of perishable constant this repo keeps getting bitten by.

**(iii) Callers.** Three call sites, all in `~/kitty-482 kitty/core_text.m` —
`:951` (`cocoa_render_line_of_text`), `:1002` (`cocoa_text_width_for_single_line`), `:1016`
(`render_single_ascii_char_as_mask`). Sites 951 and 1002 must pass the SAME weight or the width
measured for elision will not match the width drawn (Semibold is ~4.4 % wider, measured above); site
1016 draws the big window-number letter and should keep `OPT(...)` too or explicitly pass
`NSFontWeightRegular` — a deliberate choice either way, not a default.

**Total: one option, one parameter, three call sites. No new framework, no new file, no dependency.**
UNMEASURED: I did not compile kitty, so this diff is *sketched and type-checked by reading*, not built.

---

## 3. Vertical metrics — and the finding that changes the design

### 3.1 The size is not a free dial. It is `band_height × 0.8667`, and nothing else.

`ensure_ui_font(in_height)` is called with **the destination buffer's own height**
(`~/kitty-482 kitty/core_text.m:951`: `if (!ensure_ui_font(height)) return false;` inside
`cocoa_render_line_of_text(…, const size_t height)`), and `render_a_bar` passes
`bar_height = ui->cell_height + 2` as that height (`~/kitty-482 kitty/shaders.c:839 and :856`). The font
size is then `in_height × (default_size / default_line_box)`.

Measured on this box: default UI font is **13.0 pt** with ascent 12.568, descent 2.742, leading 0.000,
so `floor(12.568 + 2.742 + 0 + 0.5) = 15` and **`pts_per_px = 13/15 = 0.8666667`**.

🚨 **Therefore the ratio of type size to band height is a CONSTANT of the implementation.** Sweeping
band height 20→50 px and measuring the worst-case ink of `"ÅÉÎÕÜ gjpqy"` (accented capitals plus
every descender — the same worst case the shipped Pillow overlay sizes against):

```
  band=38px em= 32.93 worstink= 36.70 ink/band=0.966 cap/body=0.851
  band=42px em= 36.40 worstink= 40.56 ink/band=0.966 cap/body=0.940
  band=45px em= 39.00 worstink= 43.46 ink/band=0.966 cap/body=1.007
  band=47px em= 40.73 worstink= 45.39 ink/band=0.966 cap/body=1.052   <- what render_a_bar does
  band=50px em= 43.33 worstink= 48.28 ink/band=0.966 cap/band=1.119
```

**`ink/band = 0.966` at EVERY height.** Making the band taller makes the type proportionally taller;
it buys **zero** air. (`cap/body` is against Monaco at em 36 = `font_size 18.0` on a 2× display, the
operator's body face, measured `cap = 27.281 px`.)

### 3.2 What the band actually looks like at our 45 px cell — rendered, not reasoned

**Instrument.** `/private/tmp/ktb-font/r.m` is a faithful replica of `cocoa_render_line_of_text`
(same `CGBitmapContextCreate` flags, same `CGContextSetShouldSmoothFonts`, same
`CGContextSetTextPosition(ctx, 0, descent)`, same `CTLineDraw`) minus the Nerd-Font cascade, which
only adds fallback glyphs and cannot move the primary face. It renders into a real 900×47 RGBA buffer
and then reports **which pixel rows carry ink**. Actual output:

```
== Regular (kCTFontUIFontSystem, SHIPPED) ==
   H=47    claude-infrastructure
     ink rows (top-origin): 7..37 of 47   -> top gap 7 px, bottom gap 9 px, ink/band 0.660
     leftmost ink column: 17 px
   H=47   ÅÉÎÕÜ gjpqy
     ink rows (top-origin): 0..45 of 47   -> top gap 0 px, bottom gap 1 px, ink/band 0.979
     leftmost ink column: 8 px
   H=47   ~/Development — main
     ink rows (top-origin): 1..37 of 47   -> top gap 1 px, bottom gap 9 px, ink/band 0.787
     leftmost ink column: 10 px
== Semibold (NSFontWeightSemibold 0.30) ==
   H=47   ÅÉÎÕÜ gjpqy
     ink rows (top-origin): 0..46 of 47   -> top gap 0 px, bottom gap 0 px, ink/band 1.000
```

**The numbers, stated plainly.**

| quantity | value at `cell_height = 45 px` | source |
|---|---|---|
| `bar_height` (buffer height) | **47 px** = `cell_height + 2` | `~/kitty-482 kitty/shaders.c:839` |
| derived em | **40.733 device px** = 20.37 logical pt at scale 2 | probe §2, `desired_size` |
| ascent / descent / leading | 39.381 / 8.592 / 0.000 | probe |
| font's own line box | **47.973 px — 0.97 px TALLER than the 47 px buffer** (the `floor()` in `ensure_ui_font` rounds the base line box *down* from 15.311 to 15, so every derived size is ~2 % large) | probe |
| baseline | y = `descent` = **8.592 px from the BOTTOM** = 38.41 px from the top | `~/kitty-482 kitty/core_text.m:992`: `CGContextSetTextPosition(ctx, 0, descent);` |
| cap height | **28.700 px** → cap top at 9.71 px from the top | probe |
| cap/body (vs Monaco em 36) | **1.052** | probe |
| left inset | **8 px** of ink from the texture's own x = 0 (the `" %s"` prefix is one space, advance 8.71 px Regular / 8.52 px Semibold), **+ `border_width`** because the texture is drawn at `border_rect.left + border_width` (`~/kitty-482 kitty/shaders.c:880-881`). `border_width = ceil(thickness_as_float(os_window, 1)) = ceil(box_drawing_scale[1] × dpi/72) = ceil(1.0 × 144/72) = 2 px`. **Total ≈ 10 px.** | probe + `~/kitty-482 kitty/shaders.c:305-310, 838`, `kitty/options/types.py:548` |
| vertically centred? | **No — it is BOTTOM-ANCHORED at the descent.** It merely *looks* centred because the font was sized so `ascent + descent ≈ band`. There is no centring term anywhere in the function. | the one-line `CGContextSetTextPosition` above |

🚨 **THE FINDING. `ink/band = 0.966` is the geometry the operator has already rejected, in writing,
as "oversized to its container" — and the route cannot do better.** The shipped Pillow overlay's own
record (`~/Development/claude-infrastructure/scripts/kitty-pane-title-overlay.py:228-234`) tabulates
the exact ladder he ruled on:

```
     band   em   ink(worst)  ink/band   air/side   cap/body
     45px   38     42px        0.93        1px       0.96    <- "oversized to its container"  REJECTED
     62px   42     46px        0.74        8px       1.04    <- the accepted setting, live today
     90px   46     51px        0.57       19px       1.14    <- "too large"  REJECTED
```

`render_a_bar` delivers **0.966 / ~1 px air** — *tighter than the 0.93 he rejected*. And the direct
pixel render above shows it is not a margin-of-error matter: a title containing an accented capital
and a descender **touches the top edge at row 0** in Regular and **touches BOTH edges** in Semibold,
i.e. it is at or past clipping. A perfectly ordinary title — `~/Development — main` — already sits
1 px off the top.

**So: switching the face to Semibold, on its own, makes requirement (d) LOOK WORSE, not better,
because Semibold's slightly larger ink pushes an already-flush band into contact with its edges.**
Weight and size are not separable deliverables here.

### 3.3 The cure, measured

Two things have to be decoupled: (1) the size the font is derived at must stop being the buffer
height, and (2) the baseline must be centred instead of resting on the descent. Both are two-line
changes in `~/kitty-482 kitty/core_text.m`:

```c
-cocoa_render_line_of_text(const char *text, const color_type fg, const color_type bg, uint8_t *rgba_output, const size_t width, const size_t height) {
+cocoa_render_line_of_text(const char *text, const color_type fg, const color_type bg, uint8_t *rgba_output, const size_t width, const size_t height, const size_t font_box_height) {
     …
-    if (!ensure_ui_font(height)) return false;
+    if (!ensure_ui_font(font_box_height ? font_box_height : height)) return false;
     …
-    CGContextSetTextPosition(ctx, 0, descent);
+    CGContextSetTextPosition(ctx, 0, (height - (ascent + descent)) / 2.0 + descent);   // centre the line box in the band
     CTLineDraw(line, ctx);
```

`(height - (ascent + descent)) / 2.0 + descent` reduces **exactly** to the current `descent` when
`font_box_height == height` (because the derived font has `ascent + descent ≈ height`), so the existing
URL-bar and window-number consumers are unaffected to within the 0.97 px rounding noted above — it is
a strict generalisation, not a behaviour change for them.

Rendered through the same replica, worst case `" ÅÉÎÕÜ gjpqy"`, Semibold, band still **47 px**:

```
   frac=0.70 fontbox=33px em=28.60 baseline=12.69  ink rows 6..39   top 6  bottom 7  ink/band 0.723
   frac=0.74 fontbox=35px em=30.33 baseline=12.04  ink rows 6..40   top 6  bottom 6  ink/band 0.745   <- matches the accepted 0.74
   frac=0.78 fontbox=37px em=32.07 baseline=11.38  ink rows 5..41   top 5  bottom 5  ink/band 0.787
   frac=0.82 fontbox=39px em=33.80 baseline=10.73  ink rows 3..42   top 3  bottom 4  ink/band 0.851
```

`frac = 0.74` reproduces the operator's accepted **0.74 ink-to-band with 6 px of air on each side,
inside a one-cell band**, and the centring term is what makes the two gaps equal (6/6) rather than
the shipped 0/1.

⚠️ **The honest residual: you cannot have BOTH his accepted air AND his accepted type size in a
47 px band.** At `frac = 0.74` the em is 30.33 px and **cap/body drops to 0.78** — the label's caps
become noticeably *smaller* than the body text's, where the accepted setting has them at **1.04**.
To hold cap/body ≈ 1.04 you need em ≈ 40, whose worst ink is 44.6 px, which needs a band of
44.6 / 0.74 ≈ **60 px ≈ 1.34 cells** — which is exactly the 62 px the overlay converged on
independently. The two records agree to within 3 %.

**So the third dial — `bar_height`, hardcoded as `ui->cell_height + 2` at `~/kitty-482
kitty/shaders.c:839` — is the one that has to move**, and moving it is out of my axis (it is the
geometry/hit-test axis: a 62 px band overpaints 1.38 content rows instead of 1.04). What is on my
axis is the measurement that settles it: **`cell_height + 2` is not a neutral default, it is a
specific and already-rejected point on the operator's own ladder.**

---

## 4. Colour — and the one field that has to be plumbed

### 4.1 What it does today

`~/kitty-482 kitty/shaders.c:849-851`:

```c
#define RGBCOL(which, fallback) ( 0xff000000 | colorprofile_to_color_with_fallback(ui->screen->color_profile, ui->screen->color_profile->overridden.which, ui->screen->color_profile->configured.which, ui->screen->color_profile->overridden.fallback, ui->screen->color_profile->configured.fallback))
    color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
#undef RGBCOL
```

Both `which` and `fallback` are `default_fg` / `default_bg`, so the macro degenerates to *"the
terminal's own foreground and background"*. Those same two values are used in **three** places —
the text colours handed to `draw_window_title`, the `blank_canvas(ui->bg_alpha, bg, false)` that
paints the whole `border_rect`, and the `draw_rounded_rect(..., fg, bg, 0.f)` stroke.

**Consequence for us, unmodified:** every pane's title band would be `#1e1e24` on `#e6e6e6` — the
terminal ground — and **identical on every pane**, so the focused pane would be indistinguishable
from the eight idle ones. That is the single job the operator's palette exists to do.

### 4.2 The four options already exist, on both sides of the boundary

- Python: `window_title_bar_{active,inactive}_{foreground,background}`, `Color | None`
  (`~/kitty-482 kitty/options/types.py:722-726`), all four set in
  `~/Development/claude-infrastructure/config/kitty.conf:1260-1263`.
- **C: already on the `Options` struct** — `~/kitty-482 kitty/state.h:76` declares
  `window_title_bar_active_foreground, window_title_bar_active_background,
  window_title_bar_inactive_foreground, window_title_bar_inactive_background` as `color_type`, and
  `~/kitty-482 kitty/options/to-c-generated.h:1023-1024` fills them with `color_or_none_as_int(val)`,
  which is **`0` when the option is unset** (`~/kitty-482 kitty/options/to-c.h:26-29`).

So `OPT(window_title_bar_active_background)` is readable from `render_a_bar` **today, with no new
option and no new plumbing.** That is the good half.

### 4.3 The bad half — activeness is NOT in `UIRenderData`. VERIFIED, and it is one field.

The brief asks me to verify that the call site knows which window is active. **It does not — but its
caller does.**

- `draw_cells(const WindowRenderData *srd, OSWindow *os_window, bool is_active_window, bool is_tab_bar, bool is_single_window, Window *window)` — `~/kitty-482 kitty/shaders.c:1411`. `is_active_window` is a parameter.
- `UIRenderData` is built at `~/kitty-482 kitty/shaders.c:1434-1444` and **`is_active_window` is not among its 17 fields** (struct at `~/kitty-482 kitty/shaders.c:34-42`).

🚨 **And the obvious proxy does not work.** `ui->inactive_text_alpha` is in the struct and is 1.0 for
an active window — but `inactive_text_alpha` **defaults to 1.0**
(`~/kitty-482 kitty/options/types.py:595`) and the operator does not set it
(`grep -n inactive_text_alpha config/kitty.conf` → no match), so on this box it is **1.0 for active
and inactive alike** and carries zero bits. Using it would produce a band that is correct on a
machine that dims inactive text and silently wrong on ours.

Add the field. It is genuinely one line in each of three places:

```c
 typedef struct UIRenderData {
     …
     float bg_alpha, inactive_text_alpha;
-    bool has_background_image;
+    bool has_background_image, is_active_window;
 } UIRenderData;                                   // kitty/shaders.c:34-42
…
     UIRenderData ui = {
         …
-        .inactive_text_alpha = current_inactive_text_alpha, .has_background_image = has_bgimage(os_window),
+        .inactive_text_alpha = current_inactive_text_alpha, .has_background_image = has_bgimage(os_window),
+        .is_active_window = is_active_window,
     };                                            // kitty/shaders.c:1434
```

### 4.4 The colour diff for `render_a_bar`

```c
 #define RGBCOL(which, fallback) ( 0xff000000 | colorprofile_to_color_with_fallback(…) )
     color_type fg = RGBCOL(default_fg, default_fg), bg = RGBCOL(default_bg, default_bg);
 #undef RGBCOL
+    if (is_window_title) {   // new bool parameter; false for the URL bar and the window-number bar
+        const color_type ofg = ui->is_active_window ? OPT(window_title_bar_active_foreground)
+                                                    : OPT(window_title_bar_inactive_foreground);
+        const color_type obg = ui->is_active_window ? OPT(window_title_bar_active_background)
+                                                    : OPT(window_title_bar_inactive_background);
+        if (ofg) fg = 0xff000000 | ofg;
+        if (obg) bg = 0xff000000 | obg;
+    }
```

Gated on a new `bool is_window_title` parameter so the **URL-target bar and the window-number bar keep
the terminal palette they have today** — they are not title bars and must not silently repaint.

**With the operator's config this yields, verbatim:** active `fg = 0xffffffff`, `bg = 0xff2f62d8`;
inactive `fg = 0xfff4f6fd`, `bg = 0xff3f5590`. Those are the values I used in the §3.2 pixel render,
so the ink measurements there are already at the real contrast.

⚠️ **Two residuals, stated rather than hidden.**

1. **The fallback chain diverges from the real title bar's.** `~/kitty-482 kitty/window_title_bar.py:141-143`
   falls back to `active_tab_background` / `inactive_tab_foreground` when the option is unset. Those
   four tab colours are **not on the C `Options` struct** (`grep -n 'active_tab_background' kitty/state.h`
   → no match), so C cannot reproduce that chain without adding them. The `if (ofg)` form above falls
   back to the terminal default instead. Harmless here (all four are set), and it is a real behaviour
   difference for anyone who sets only the tab colours — say so in the option docs rather than papering
   over it.
2. **`0` is both "unset" and "pure black."** That ambiguity is `color_or_none_as_int`'s, not this
   diff's, and it already affects `cursor_trail_color` (`~/kitty-482 kitty/options/to-c.h:300`). A user
   asking for `#000000` gets the terminal default. Inherited, not introduced — but do not pretend it
   is not there.

---

## 5. The rounded border — not wanted, and one line to remove

`~/kitty-482 kitty/shaders.c:886`, the last statement of `render_a_bar`:

```c
    // finally draw border with transparent bg
    draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
```

Read the arguments against the signature (`~/kitty-482 kitty/shaders.c:313-318`):
`thickness_level = 1` → `thickness_as_float(os_window, 1) = box_drawing_scale[1] × dpi/72 = 1.0 × 144/72 =`
**2.0 px**; `corner_radius_px = ui->cell_width` ≈ **22 px** at our metrics; `srgb_color = fg` — the
**text** colour; `bg_alpha = 0.f`.

The shader (`~/kitty-482 kitty/rounded_rect_fragment.glsl`) draws `outer − inner`, i.e. a **stroke, not
a fill**, and with `background_color.a = 0` everything inside the stroke passes through untouched.

**So what it actually paints on a title band is a 2 px `#ffffff` outline, with 22 px rounded ends,
around a full-pane-width 51 px rectangle.** That is right for a URL hint — a floating pill — and wrong
for a title band, which wants to read as chrome flush to its pane, exactly as the shipped overlay's
flat strip does.

**Suppression: delete the call.** It is the final statement and its return value is unused; nothing
downstream depends on it. Do **not** try to suppress it by passing `thickness_level = 0` — that yields
`box_drawing_scale[0] = 0.001 pt → 0.002 px` (`~/kitty-482 kitty/options/types.py:548`), which the
shader's `smoothstep(-1, 1, …)` still resolves to a faint but non-zero alpha, and it costs a full
program bind, a uniform upload and a quad draw for an invisible result. Gate it on the same
`is_window_title` bool as §4.4 so the URL bar keeps its pill:

```c
-    draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
+    if (!is_window_title) draw_rounded_rect(ui->os_window, border_rect, sh, 1, ui->cell_width, fg, bg, 0.f);
```

**What remains after removing it is correct and wanted:** `blank_canvas(ui->bg_alpha, bg, false)` has
already filled the whole `border_rect` (`bar_height + 2 × border_width` = 51 px) with `bg`, and the text
texture is drawn inset by `border_width` = 2 px, so you are left with a flat band carrying a 2 px
bg-coloured margin on every side. ⚠️ One caveat from the same line: `blank_canvas` takes
`ui->bg_alpha`, the OS-window alpha — under a transparent `background_opacity` the band inherits that
transparency. The operator runs opaque, so UNMEASURED here and worth a line in the option docs.

⚠️ **Also on my axis and easy to miss: the band does not span the pane.** `border_rect.left = ui->screen_left`
and `.width = ui->screen_width` are the **cell grid**, so with `window_padding_width 0 5 0 5` the 5 pt
(= 10 px) of left and right padding stays unpainted. The shipped overlay paints edge to edge. Whether
that matters is the geometry axis's call, but the two surfaces will not look the same until someone
decides it.

---

## 6. `render_a_bar` vs the shipped Pillow overlay, on requirement (d)

The overlay's constants are read from
`~/Development/claude-infrastructure/scripts/kitty-pane-title-overlay.py`:
`UI_FONT = "/System/Library/Fonts/SFNS.ttf"`, `UI_VARIATION = "Semibold"` (`:274-275`),
`TYPE_RATIO = 0.678` of a `BAND_FILL_CELLS = 1.378` band → **em 42 px in a 62 px band** (`:246, :276`),
`TRACKING = 0.6` (`:308`), `SYMBOL_FONT = Menlo` with a `.notdef` probe (`:310-318`).

| | Pillow overlay (shipped, accepted) | `render_a_bar` **as it stands** | `render_a_bar` **+ §2–§5** |
|---|---|---|---|
| family | SF Pro (`SFNS.ttf`) | **SF Pro** (`.AppleSystemUIFont`) ✅ | SF Pro ✅ |
| weight | **Semibold** | **Regular** ❌ | **Semibold** ✅ (`.SFNS-Semibold`, weight +0.30, measured §2) |
| em (device px) | 42 | **40.73** — within 3 % of the accepted em, but not selectable | selectable |
| cap/body (vs Monaco em 36) | 1.04 | **1.052** ✅ | 1.04 at a 60–62 px band; **0.78** if the band stays at 47 px ⚠️ |
| band height | 62 px painted / 90 px covered | **47 px**, hardcoded `cell_height + 2` | needs `bar_height` to become an option |
| ink / band (worst case) | **0.74** — the accepted value | **0.966**, and *constant at every band height* ❌ | 0.745 at `frac 0.74` (measured §3.3) ✅ |
| air above/below ink | 8 px each | **0 px / 1 px** — Regular *touches the top edge*; Semibold touches **both** ❌ | 6 px / 6 px ✅ |
| vertical placement | baseline solved from the real string's ink | bottom-anchored at `descent`, no centring term | centred: `(h − (asc+desc))/2 + desc` |
| left inset | tuned in the renderer | 8 px (one space) + 2 px border ≈ **10 px**, fixed | same, or drop the `" %s"` prefix and inset explicitly |
| tracking | +0.6 px | **none** — CoreText default | would need `kCTKernAttributeName`; not done here, UNMEASURED |
| `✳ ◐ ◑ ✻ ✶` coverage | hand-built Menlo fallback + `.notdef` probe, ~90 lines | **automatic and correct** ✅ | ✅ |
| cost | resident Python + Pillow daemon, 2 s timer, socket, PNG per pane | one `CTLine`, cached on title identity, one GL texture per changed title | same |

### 6.1 Glyph coverage — the one axis where this route is strictly BETTER, measured

Every Claude Code pane title starts with one of `✳ ◐ ◑ ✻ ✶`, and the overlay's own comment
(`kitty-pane-title-overlay.py:310-315`) records that **SF Pro carries none of them** and that PIL draws
`.notdef` striped boxes rather than raising. I checked the bundled Nerd Font the cascade list adds
(`~/kitty-482 kitty/fonts/render.py:213`, file at
`/Applications/kitty.app/Contents/Resources/kitty/fonts/SymbolsNerdFontMono-Regular.ttf`) with
`fontTools`: `U+2733 ✳`, `U+25D0 ◐`, `U+25D1 ◑`, `U+273B ✻`, `U+2736 ✶` are **all ABSENT** from it too.
So the cascade list does not save us either.

**CoreText's own automatic fallback does.** Building the attributed string exactly as
`cocoa_render_line_of_text` does and dumping `CTLineGetGlyphRuns`
(`/private/tmp/ktb-font/g.m`) — actual output:

```
  run 1  font=ZapfDingbatsITC          text=✳   glyphs=1 notdef=0
  run 3  font=.HiraKakuInterface-W4    text=◐   glyphs=1 notdef=0
  run 5  font=.HiraKakuInterface-W4    text=◑   glyphs=1 notdef=0
  run 7  font=ZapfDingbatsITC          text=✻   glyphs=1 notdef=0
  run 9  font=ZapfDingbatsITC          text=✶   glyphs=1 notdef=0
  run 10 font=.SFNS-Regular            text= — • claude  glyphs=11 notdef=0
```

**Zero `.notdef` across the whole string** — CTLine does system-wide fallback that a `CFArray` cascade
list only *augments*. And the fallbacks are optically in register with SF Pro without any
cap-matching (`/private/tmp/ktb-font/h.m`, em 40.733, SF cap = 28.70, baseline y = 0):

```
  ✳ via ZapfDingbatsITC       ink h=28.26  y=[ 0.00..28.26]
  ✻ via ZapfDingbatsITC       ink h=29.18  y=[-0.50..28.68]
  ✶ via ZapfDingbatsITC       ink h=29.16  y=[-0.48..28.68]
  ◐ via .HiraKakuInterface-W4 ink h=31.67  y=[-1.54..30.13]
  H via .SFNS-Regular         ink h=28.70  y=[ 0.00..28.70]
```

ZapfDingbats lands at 98–102 % of SF's cap height and on the baseline; HiraKaku's `◐` is 10 % oversized
and sits 1.5 px low. **This deletes ~90 lines of the overlay's most fragile machinery** — the
`.notdef` probe, the `SYMBOL_FONT`, the cap-height matching and the shared-baseline anchor
(`kitty-pane-title-overlay.py:400-427`) — for free.

### 6.2 The honest verdict on (d)

**(d) is PARTLY met by this route as it stands, and FULLY met by it with ~30 lines of change — but the
30 lines are not the ones the design assumed.**

- ✅ **Family: fully met, free, today.** `.AppleSystemUIFont` → SF Pro, the operator's own face,
  chosen by the same reasoning the overlay records (`:271` *"SF Pro is the macOS system UI face, so a
  label set in it reads as chrome by convention"*).
- ✅ **Glyph coverage: fully met and strictly better than the incumbent**, measured above.
- ❌→✅ **Weight: not met today (Regular), fully met with the two-line change in §2.1.** No new
  framework, no dependency. This is the part everyone expected to be the work, and it is the easy part.
- ⚠️ **Size and vertical fit: NOT met, and not met by any configuration of the route as written.**
  `ink/band` is pinned at **0.966** by construction (§3.1), tighter than the 0.93 the operator
  rejected in writing as *"oversized to its container"*; the direct pixel render (§3.2) shows an
  ordinary accented title **touching the band's top edge** in Regular and **both edges** in Semibold.
  Fixable — `(h − (asc+desc))/2 + desc` plus a separate font-box height reproduces his accepted 0.74
  exactly (§3.3) — but it takes **three** changes (font-box height, centring, and un-hardcoding
  `bar_height` at `~/kitty-482 kitty/shaders.c:839`), not one.

🚨 **The decision-changing sentence, if only one survives:** *switching the face to Semibold without
also decoupling size from band height makes the band WORSE than it is now* — Semibold's ink reaches
`ink/band = 1.000` in the 47 px band, i.e. flush against both edges. **Weight and size are one
deliverable on this route, not two.**

**Nothing on this axis refutes the lead's design.** The route does give the right face, for free, with
better glyph handling than the thing it replaces and no resident daemon. What it does not give for free
is the *size*, and that has a measured cure with a measured cost (cap/body 0.78 in a one-cell band, or
cap/body 1.04 in a ~1.35-cell band — the same trade the overlay already resolved in favour of the
taller band).

---

## Instruments, so every number above is re-derivable

All three are standalone, compile in under a second, and **do not build or run kitty**:

| file | what it measures | build + run |
|---|---|---|
| `/private/tmp/ktb-font/m.m` | replicates `ensure_ui_font`; dumps face, size, asc/desc/leading, cap, x-height and the derived baseline for a sweep of band heights | `clang -o m m.m -framework Foundation -framework CoreText -framework AppKit && ./m` |
| `/private/tmp/ktb-font/w.m` | the seven weight-selection routes; worst-case ink; the band-height sweep that shows `ink/band` is constant; cap/body vs Monaco em 36 | same, `w` |
| `/private/tmp/ktb-font/r.m` | faithful replica of `cocoa_render_line_of_text` into a real 900×47 RGBA buffer; reports which **pixel rows** carry ink, for shipped and for the proposed decoupled/centred variant | same, `r` |
| `/private/tmp/ktb-font/g.m`, `h.m` | `CTLineGetGlyphRuns` fallback resolution and per-symbol ink register for `✳ ◐ ◑ ✻ ✶` | same, `g` / `h` |

They live in `/private/tmp` and will not survive a reboot — this box reaped `/private/tmp` once
already today. Copy them into the worktree if any of these numbers must be re-derived later.

## What I did NOT measure

- **Nothing here was run inside a real kitty.** The brief bans a build and the operator's instance is
  live with nine working sessions. Every claim is either a source citation or a CoreText measurement in
  a standalone process using the same APIs and the same arithmetic. The one thing this cannot rule out
  is a difference introduced by kitty's GL upload path — `glTexImage2D(..., GL_SRGB_ALPHA, ...)`
  (`~/kitty-482 kitty/shaders.c:869`) treats the premultiplied CoreText output as sRGB, which will
  shift perceived weight slightly. **UNMEASURED**, and it affects the *look* of the weight, not which
  face is selected.
- **Tracking.** The overlay adds +0.6 px; `cocoa_render_line_of_text` sets no `kCTKernAttributeName`.
  Adding it is one attribute in the dictionary, but I did not measure what it does to the widths that
  `cocoa_text_width_for_single_line` returns for elision. **UNMEASURED.**
- **`window_title_bar_align`.** `left|center|right` exists for the real title bars; `render_a_bar`
  always draws from x = 0. Not measured, not on this axis, but it will not honour the operator's
  `window_title_bar_align left` for free — it happens to agree by accident.
- **Text elision.** `render_a_bar` passes `NULL` for `actual_width`, so
  `cocoa_text_width_for_single_line` is never called and a title wider than the pane is simply **clipped
  by the texture**, mid-glyph, with no ellipsis. The real title bars elide in Python. **UNMEASURED**
  what that looks like; it is a visible difference and it is on the geometry axis's plate.

---

## ADVERSARIAL VERIFICATION

**Verifier's brief:** refute, do not confirm. Every `file:line` below was re-opened in the tree it
names. Every measurement was re-run on a **new** instrument (`/private/tmp/ktb-adv/adv.m`,
`adv2.m`, `adv3.m`), not by re-reading `/private/tmp/ktb-font/*`. Box: macOS 15.7.9 (24G830),
printed by the probe.

🚨 **The headline of this verification: the write-up's own closing sentence — "Nothing here was run
inside a real kitty. The brief bans a build" — rests on a false premise. A build was never needed,
and I ran the real path.** `draw_single_line_of_text` is exported to Python
(`~/kitty-482 kitty/glfw.c:3080-3107`, registered at `:3270`, typed at
`kitty/fast_data_types.pyi:1608`), it computes `height = fonts_data->fcm.cell_height + padding_y`
with `padding_y` defaulting to **2** — byte-for-byte the same 47 px band `render_a_bar` builds at
`~/kitty-482 kitty/shaders.c:839` — and kitty's own Python already calls it
(`kitty/tabs.py:1783`, `:1901`, `kitty/window.py:1414`). It is reachable **in-process with no C
build** through the `watcher` option, which `load_watch_modules` imports into the kitty process
(`~/kitty-482 kitty/launch.py:516-556`). The write-up cites `glfw.c:3100` for claim 1 — that line is
*inside this function* — and did not notice that the function is what makes the whole axis
buildlessly measurable.

**What I ran.** A sandbox kitty (`--config NONE -o font_family=Monaco -o font_size=18.0
-o "modify_font=cell_height 94%" -o watcher=…`, own minimized window, never the operator's pid 597),
whose watcher called `draw_single_line_of_text` and dumped the raw RGBA. Actual output:

```
worstcase w=900 h=47   real_half w=900 h=47   real_sext w=900 h=47   negctrl w=900 h=47
padding_y=0 -> height=45      padding_y=2 -> height=47      padding_y=6  -> height=51
padding_y=15 -> height=60     padding_y=17 -> height=62
```

Ink rows scanned out of those real buffers, beside my standalone replica of the same function:

| string | **real kitty binary** | my replica | write-up's `r.m` |
|---|---|---|---|
| `ÅÉÎÕÜ gjpqy` Regular | ink **1..46**, top 1, **bot 0**, 0.9787 | 1..46, 1/0, 0.979 | **0..45, top 0, bot 1**, 0.979 |
| `◐ ~/Development — main` | 8..45, 8/1, 0.8085 | 8..45, 8/1, 0.809 | (not measured) |
| `✳ claude-infrastructure` | 9..39, 9/7, 0.6596 | 9..39, 9/7, 0.660 | (not measured) |
| `xxx` (negative control) | 17..38, 17/8, 0.4681 | 17..38, 17/8, 0.468 | (not measured) |

My replica agrees with the shipping binary **row for row on all four strings**. That is the
positive control this axis never had, and it is what lets the rest of this section overturn numbers
rather than merely doubt them.

### OVERTURNED

**1. Claim 4 — "ink/band is CONSTANT at 0.966 for every band height from 20 px to 50 px."
REFUTED as a measurement; the instrument could not have come out any other way.** Every row of that
table satisfies `worstink = 1.1144 × em` and `em = 0.86667 × band` exactly (38→36.70, 47→45.39), so
the identical 0.966 column is *algebra over a font bounding box*, not a render. **Corrected claim:**
the LINEARITY is real and I confirm it far more strongly than the write-up did — `em/band` is
exactly **0.86667** and `cap/em` exactly **0.7046** at every height from 12 px to 140 px, with the
PostScript name pinned at `.SFNS-Regular` across a 10× size range (so there is *no* optical-size
switch to worry about). But **rendered** worst-case ink/band is neither 0.966 nor constant. Measured
unclipped (drawn into a buffer padded 60 px each side, ink threshold swept 2→32 with identical
results): **1.100 at band 20, 1.043 at 23, 1.039 at 26, 1.000 at 29–35, 0.974 at 38, 0.979 at 47,
0.968 at 62** — and at bands ≤ 26 px the glyph is *genuinely clipped outside the buffer*. The
direction is against the route, not for it: at our 47 px band the true figure is **0.979 Regular /
1.000 Semibold**, worse than the 0.966 quoted and worse than the 0.93 the operator rejected.

**2. Claim 6 — "touches the top edge in Regular (top gap 0 px, bottom gap 1 px)." REFUTED against
the shipping binary: it touches the BOTTOM.** Real kitty gives `ink rows 1..46 of 47, top gap 1,
bottom gap 0`; the write-up's replica gives `0..45, top 0, bottom 1`. Same 46 rows of ink, same
0.979 — **the write-up's replica sits one row high relative to the code it replicates.**
**Corrected claim:** in Regular the worst case is flush against the **bottom** edge; in Semibold it
is flush against **both** (`0..46`, confirmed by my replica, which the binary validates). The
write-up's §6.2 decision sentence ("an ordinary accented title touching the band's top edge") names
the wrong edge. This matters because §3.3's cure is a *vertical* change validated on that same
replica — its cure numbers happen to be right (I reproduce `frac=0.74 → ink 6..40, 6/6 air, 0.745`
exactly), but they were validated by an instrument that disagrees with the binary in the very axis
being changed.

**3. Claim 9 — "reduces exactly to the current `descent` … a strict generalisation, existing
consumers unaffected." REFUTED as stated.** Measured at `font_box == height` for three URL-bar
strings: `old_baseline = 8.592`, `new_baseline = 8.106`, **DELTA = −0.487 px**, identically for all
three. **Corrected claim:** it is a **half-pixel upward shift of the URL-target bar**, not a no-op —
because the derived font's line box is 47.973 px inside a 47 px buffer, exactly the ~2 % the
write-up itself notes two paragraphs earlier and then discards. Immaterial in size; the problem is
that "strict generalisation" is the sentence that would let this land without anyone looking at the
URL bar.

**4. Claim 11's consumer description — "both via `WindowBarData` fields on the `Window` struct
(`title_bar_data`, `url_target_bar_data`)." REFUTED.** Both existing consumers pass
**`&window->title_bar_data`** as the bar: `~/kitty-482 kitty/shaders.c:929`
(`draw_hyperlink_target`, which reads the *title object* from `url_target_bar_data` but renders into
`title_bar_data`) and `:943` (`draw_window_number`). `url_target_bar_data.buf` is never rendered
into at all. They are called back-to-back at `~/kitty-482 kitty/shaders.c:1381-1382`.
`WindowBarData` (`~/kitty-482 kitty/state.h:220-226`) holds **one** `buf` and **one**
`last_drawn_title_object_id`. **Corrected claim, and it is a live defect in the proposed design:** a
*permanent* title band that reuses `title_bar_data` shares one 900×47 buffer and one title-identity
cache with the hyperlink bar, so hovering a hyperlink makes the two alternate and forces a **full
CoreText re-render plus texture upload every frame** for the duration of the hover. Today this is
near-harmless only because the two consumers are nearly mutually exclusive in time. **Add a sixth
change to the set: the title band gets its own `WindowBarData`.**

**5. The "~4.4 % wider" figure behind §2.1's trap 2. Understated ~1.5× for realistic strings.**
Re-measured at band 47: `ÅÉÎÕÜ gjpqy` +4.41 % (I reproduce it), `◐ ~/Development — main` +4.30 %,
but **`claude-infrastructure` +6.82 %**. **Corrected claim:** and the trap does not bind where the
write-up puts it — `render_a_bar` passes **`NULL`** for `actual_width`
(`~/kitty-482 kitty/shaders.c:856`), so `cocoa_text_width_for_single_line` is *never called on the
title path*. Sites `:951` and `:1002` must agree only for the Python
`draw_single_line_of_text(max_width=True)` consumer (`kitty/window.py:1414`, the drag thumbnail) and
`glfw.c:3100`.

**6. Minor citation drift.** `BAND_FILL_CELLS` is at `kitty-pane-title-overlay.py:242`, not `:246`.
And the operator's ladder is **six** rows at `:227-233`, not three: the two interior rows `54px/0.81`
and `58px/0.79` and `68px/0.71` are the ones that show the *accepted band range* is 54–68 px at
ink/band 0.71–0.81 — a range, not a point, which is useful when pricing change 3.

### UPHELD (each re-measured or re-opened, with a control)

- **Claim 1** verbatim at `~/kitty-482 kitty/glfw.c:1083` (`double font_sz_pts UNUSED, double ydpi
  UNUSED`) against the FreeType branch at `:1137-1144` which *does* compute
  `px_sz = font_sz_pts * ydpi / 72` and clamps it to `3 * height / 4`. Upheld exactly.
- **Claim 2** upheld: `ensure_ui_font` at `:923-940`, `CTFontCreateUIFontForLanguage(kCTFontUIFontSystem,
  0.f, NULL)` at `:929`; re-measured `ps=.SFNS-Regular weight=+0.0000`.
- **Claim 3** upheld by independent re-measurement: `NSFont systemFontOfSize:weight:Semibold` →
  `.SFNS-Semibold +0.3000`; `CTFontCreateCopyWithAttributes` + `kCTFontWeightTrait 0.3` →
  `.SFNS-Semibold +0.3000`; `kCTFontUIFontEmphasizedSystem` and `CopyWithSymbolicTraits(Bold)` both
  → `.SFNS-Bold +0.4000`. **Strengthened:** cap/ascent/descent are *identical* (28.700 / 39.381 /
  8.592) across all four weights, so the weight change is metric-neutral exactly as claimed — the
  1 px the render moves is ink, not metrics.
- **Claim 5** upheld and promoted from arithmetic to measurement: the in-kitty `padding_y` sweep
  returns **45** at `padding_y=0`, so `cell_height = 45` and `bar_height = 47` are now measured, not
  derived from dpi reasoning. `em = 40.733`, `cap = 28.700`, `pts_per_px = 13/15` all reproduced.
- **Claim 7** upheld; citation accurate (see drift note above).
- **Claim 8** upheld verbatim at `~/kitty-482 kitty/core_text.m:992`.
- **Claim 10** upheld — and corroborated from an unexpected direction: `padding_y=17 → height 62`,
  the overlay's accepted band, is reachable *today with no geometry change at all* the moment
  `bar_height` becomes an option.
- **Claim 11's colour facts** all upheld: `~/kitty-482 kitty/state.h:75-76` carries all four
  `window_title_bar_*` colours; `kitty/options/to-c-generated.h:1022-1025`;
  `kitty/options/to-c.h:26-29` (`None → 0`); `config/kitty.conf:1260-1263` exact. **The residual is
  real:** `grep -c active_tab_background ~/kitty-482/kitty/state.h` → **0**, so the Python fallback
  chain at `kitty/window_title_bar.py:140-144` genuinely cannot be reproduced in C.
- **Claim 12** upheld: `draw_cells` takes `bool is_active_window` (`shaders.c:1411`); `UIRenderData`
  (`shaders.c:34-42`) has 17 fields and none is it; the build at `:1434-1444` omits it;
  `inactive_text_alpha` defaults 1.0 (`types.py:595`) and is unset in the operator's config, and
  `draw_cells`' own `current_inactive_text_alpha` computation collapses to 1.0 for both states under
  that default. Zero bits, as claimed.
- **Claim 13** upheld and **strengthened**: I re-ran the run/notdef dump **with the Nerd-Font
  cascade the write-up's replica omitted**. `✳ ◐ ◑ ✻ ✶ — • claude` → 20 glyphs, **0 notdef**,
  `ZapfDingbatsITC` for ✳✻✶ and `.HiraKakuInterface-W4` for ◐◑. Positive control that the cascade is
  actually live in my probe: a private-use Nerd glyph resolves to `SymbolsNFM`.
- **The two-tree claim** upheld exactly as written. I extracted the three functions from both trees
  and diffed them: `ensure_ui_font` **byte-identical**; `cocoa_render_line_of_text` differs only in
  clang-format; `render_a_bar` differs only in clang-format **plus** master's
  `draw_rounded_rect(border_rect, sh, (float)thickness_as_float(…), …, 0, 0.f)` taking the thickness
  as a float and two extra trailing args. Nothing on this axis is version-sensitive.

### NEW RISKS the axis did not name

- 🚨 **The proposed design already exists in shipped code.** `draw_window_number`
  (`~/kitty-482 kitty/shaders.c:938-943`) already calls
  `render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false)` — *the window's own
  title, through `render_a_bar`, at the top of the window* — gated on
  `screen->display_window_char != 0`, i.e. the visual window-select overlay
  (`kitty/boss.py:1687`, `kitty/tabs.py:1027-1041`). So the implementation is nearer "ungate and
  parameterise an existing call" than "add a call site" — **and the operator can look at the exact
  disputed geometry in his live kitty today**, with no build and no patch, by binding
  `focus_visible_window` and pressing it. That is the cheapest possible resolution of the
  0.966-vs-0.93 argument and nobody proposed it.
- **The shared `WindowBarData`** (overturned item 4) — a per-frame re-render on hyperlink hover.
- **The centring term is string-dependent, and I positive-controlled that it can move.**
  `CTLineGetTypographicBounds` returns the max over runs, so `(height − (asc+desc))/2 + desc` varies
  with the title's content. It does **not** move for the Claude symbol set or for CJK (all
  39.381 / 8.592), but it does for others: `ﷺ` → 40.773 / 9.825, `🙂` → desc 8.605. Two panes whose
  titles differ that way would sit on baselines up to ~1.3 px apart. Deriving the font box from a
  *fixed* font rather than from the line removes it; the write-up's formula does not.
- **Housekeeping:** my sandbox kitty (pid 97060, title `KTB-ADV-SANDBOX`) is still resident with
  zero windows, because `macos_quit_when_last_window_closed` defaults to `no`. The brief forbids me
  to signal any process, so it is left for the operator to quit. It is not the live instance (597)
  and holds no windows. A second `KTB-ADV-SANDBOX` (pid 30360, `/private/tmp/ktb-adv-toggle/`)
  belongs to a sibling session, not to me.

### Verdict on the recommendation

**ADOPT, substantially unchanged — changes 1-5 all survive verification, and change 3's "band height
must become the third dial" is the correct and load-bearing finding.** Two amendments and one
re-ordering:

1. **Add change 6:** the title band gets its own `WindowBarData`; it may not share
   `window->title_bar_data` with `draw_hyperlink_target`.
2. **Amend change 1's rationale:** the centring term is *not* a no-op for existing consumers
   (−0.487 px), and it reads string-dependent line metrics. Say so in the option docs, or size the
   font box from a fixed font.
3. **Re-order the "next measurement".** Do not build the contact sheet from a standalone replica.
   Build it from `fast_data_types.draw_single_line_of_text` inside a sandbox kitty loaded via
   `watcher` — it is kitty's own renderer, it settles `cell_height`, dpi, the Nerd cascade and the
   `padding_y`↔`bar_height` relationship by construction rather than by argument, and it costs one
   config line. The write-up's "UNMEASURED" list (sRGB upload shift, tracking, elision) is reachable
   the same way.

Nothing here refutes the lead's design. What it refutes is the *evidence base*: three of the four
numbers this axis leans on came from instruments that could not have produced a different answer,
and the one number that decides a vertical change named the wrong edge.
