# The C hit test: hand cursor + native drag for a TOP overlay band

Axis: make a rect **inside** a window's own content area (covering content row 1) behave like a
title bar for the mouse — `POINTER_POINTER` on hover, left press routed to
`handle_window_title_bar_mouse` so the native window drag arms.

**Tree read for every claim below: `~/kitty-482`, detached at `v0.48.2` (`2cb1d95c3`), verified
`git log -1` → `2cb1d95c3accadd536bd66ba6bda044973440177 (HEAD, tag: v0.48.2) version 0.48.2`.**
Where a claim is about `~/kitty-dev` (master `1d67ecd47`) it is labelled inline. Nothing here was
executed against a running kitty — **no build was run** (brief rule 6), so every dynamic claim is
marked UNMEASURED and every static claim carries a `file:line`.

> **Line numbers in the brief are off by ~30 against this tree.** The brief cites `mouse_region()`
> at `mouse.c:1019` and the title-bar arm at `:1072`; in `~/kitty-482` `mouse_region()` begins at
> **`kitty/mouse.c:988`** and the arm is at **`:1070-1080`**. `:1072`, `:1133`, `:1172`, `:1356`,
> `:1362` are all correct. I use this tree's real numbers throughout.

---

## 0. The verdict in one paragraph

The reorder is **not** a reorder. Putting the band test before `contains_mouse()` *inside the same
per-window loop iteration* is correct and provably inert for the existing stolen-row bar — but
**only if the new arm reads a NEW geometry field that is zero unless the overlay option is on**.
Reusing `window_title_render_data` and moving its test above `contains_mouse` **does change an
existing verdict**, in an exactly-characterisable stratum: every window whose
`effective_padding('top') > 0`, where the bottom `padding.top` pixels of today's stolen-row title
bar are currently claimed by `contains_mouse` and would flip to `in_title_bar`. That stratum is
empty on the operator's machine (`window_padding_width 0 5 0 5` → top padding 0) and empty under
kitty's defaults, which is exactly why it would ship unnoticed and be wrong for other users. The
patch below therefore uses a new field and is inert by construction, not by arithmetic.

The second finding is that `in_title_bar == true` for a point inside a window's content rect is
**already an expressible state in v0.48.2** — `scroll_event()` at `kitty/mouse.c:1499` calls
`mouse_region(false, true)` and then uses `r.window` while completely ignoring `r.in_title_bar`, so
a scroll over today's title bar already scrolls that window. Nothing in the file asserts the two
are mutually exclusive. The consumers that matter are enumerated in §2; the one that needs an
explicit decision is `set_currently_hovered_window()` at `:1356`, which will now send the
application a **mouse-leave** every time the pointer crosses into the band.

The third finding is the wedge (§4): `handle_tab_bar_mouse()` has an explicit C-side recovery that
zeroes `global_state.tab_being_dragged` on an orphaned release (`kitty/mouse.c:941-953`), and
`handle_window_title_bar_mouse()` (`kitty/mouse.c:929-937`) **has no counterpart**. That asymmetry
is pre-existing. The patch does not change the escape path, but it does multiply the number of
places a press can arm the sticky state, so the same per-arming leak probability now applies to a
much larger target. A 12-line C-side recovery mirroring the tab-bar one is proposed and is
independent of the rest.

---

## 1. The reorder in `mouse_region()` — and the proof it is inert

### 1.1 What the loop does today (`~/kitty-482 kitty/mouse.c:1067-1081`, verbatim)

```c
1067        for (unsigned int i = 0; i < t->num_windows; i++) {
1068            Window *win = t->windows + i;
1069            if (contains_mouse(win) && win->render_data.screen) {
1070                ans.window_idx = i; ans.window = win; break;
1071            } else if (detect_title_bar && win->visible) {
1072                const WindowRenderData *trd = &win->window_title_render_data;
1073                if (trd->screen && trd->geometry.right > trd->geometry.left && trd->geometry.bottom > trd->geometry.top) {
1074                    if (w->mouse_x >= trd->geometry.left && w->mouse_x < trd->geometry.right &&
1075                            w->mouse_y >= trd->geometry.top && w->mouse_y < trd->geometry.bottom) {
1076                        ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
1077                        break;
1078                    }
1079                }
1080            }
1081        }
```

`contains_mouse()` is `~/kitty-482 kitty/mouse.c:269-273` and uses the **padded** rect:

```c
270 contains_mouse(Window *w) {
271     double x = ..., y = ...;
272     return (w->visible && window_left(w) <= x && x < window_right(w) && window_top(w) <= y && y < window_bottom(w));
```
with `window_top(w) = w->render_data.geometry.top - w->padding.top` (`:262-264`) and the three siblings at `:250-267`.

### 1.2 The naive reorder DOES change an existing verdict — the padding stratum

Where the stolen-row bar lives, in Python:

- `~/kitty-482 kitty/window.py:1058-1062` (`position == 'top'`):
  `render_top = new_geometry.top + cell_height`, `tb_top = new_geometry.top`,
  `tb_bottom = new_geometry.top + cell_height`.
- `render_top` is what is pushed as `render_data.geometry.top`
  (`kitty/window.py:1093-1105` → `set_window_render_data` → `kitty/state.c:1199-1211`).
- `tb_top/tb_bottom` are pushed as `window_title_render_data.geometry`
  (`kitty/window.py:1124-1131` → `set_window_title_bar_render_data` → `kitty/state.c:1006-1016`).
- `w->padding.top` is set independently by `update_effective_padding()`
  (`kitty/window.py:860-868`) from `effective_padding('top')` (`kitty/window.py:846-857`), and
  `set_window_padding` (`kitty/state.c:1189-1197`) stores it **verbatim** — nothing anywhere
  subtracts the title-bar row from it, which is what makes the overlap real rather than
  compensated-for.

So today, for a window with a top stolen-row bar:

```
title band      = [ g.top ,                        g.top + cell_height )
contains_mouse  = [ g.top + cell_height - pad_top, ... )
```

**The two overlap in exactly the bottom `pad_top` pixels of the title bar.** Because
`contains_mouse` is tested FIRST at `:1069`, those pixels are classified as *content* today.
Swapping the two tests flips them to `in_title_bar`. That is a genuine behaviour change, silently
invisible on this machine and under kitty's defaults:

| config | `pad_top` | flipped pixels |
|---|---|---|
| operator's live `window_padding_width 0 5 0 5` (`config/kitty.conf`) | 0 px | **0** — invisible |
| kitty default `window_padding_width 0` | 0 px | **0** — invisible |
| any user with e.g. `window_padding_width 6` at dpi 144 | 12 px | 12 of the bar's 45 px |

⇒ **Do not reorder the existing arm.** The patch below adds a *separate* arm keyed on a field that
is zero unless the new option is on, so inertness is by construction, not by this arithmetic.
UNMEASURED: no build was run; the overlap is derived from the four `file:line` sites above.

### 1.3 Creation order vs layout order — the question is moot, and here is why

`t->windows` is an append-only array (`~/kitty-482 kitty/state.c:378-384`,
`tab->windows[tab->num_windows++]`), i.e. **insertion order**, not spatial order. The loop at
`:1067` walks it linearly and `break`s on first match, so order would matter **iff two visible
windows' hit rects could overlap.** They cannot:

- `window_geometry()` (`~/kitty-482 kitty/layout/base.py:175-180`) stores `spaces=Edges(...)` from
  `layout_dimension()`'s `before_space`/`after_space` (`:140-152`).
- `WindowGroup.decoration()` (`~/kitty-482 kitty/window_list.py:123-127`) is
  `margin + border*mult + padding`, and `layout_dimension` derives each `space_*` from exactly those
  decorations — with the first/last window getting `space ≥ decoration` (`:143-149`).
- Therefore `padding ≤ space` on every edge, so
  `window_right(A) = A.right + A.pad.right ≤ boundary` and
  `window_left(B) = B.left − B.pad.left ≥ boundary`, and `contains_mouse` uses `x < window_right`,
  so the boundary pixel belongs to B alone.
- Overlay windows share a group's geometry but only one is `visible`
  (`~/kitty-482 kitty/layout/base.py:404-416` sets `show_title_bar` over
  `iter_all_layoutable_groups(only_visible=True)`); `contains_mouse` gates on `w->visible` at `:272`.

**Consequence, and this is the load-bearing statement for the patch:** the overlay band is a subset
of its own window's content rect, and content rects are pairwise disjoint. So adding a band test
ahead of `contains_mouse` **cannot change which window is selected** — for any point, the window
that wins is the same one `contains_mouse` would have picked. Only the *classification* of points
inside a band changes, from content to `in_title_bar`. Iteration order is irrelevant.

### 1.4 Where the band rect comes from — read it off the painter, never recompute it

`render_a_bar()` (`~/kitty-482 kitty/shaders.c:836-887`) occupies, for `along_bottom == false`:

```c
838    unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
839    unsigned bar_height = ui->cell_height + 2;
871    Viewport border_rect = {.height = bar_height + 2*border_width,
871                            .left = ui->screen_left, .width = ui->screen_width, .top = ui->screen_top};
886    return border_rect.height;
```

and `ui->screen_left/top/width` are literally the window's render geometry
(`~/kitty-482 kitty/shaders.c:1434-1440`: `.screen_width = srd->geometry.right - srd->geometry.left`,
`.screen_left = srd->geometry.left`, `.screen_top = srd->geometry.top`).

So the painted band is:

```
left   = w->render_data.geometry.left
right  = w->render_data.geometry.right
top    = w->render_data.geometry.top
bottom = top + cell_height + 2 + 2*ceil(thickness_as_float(os_window, 1))
```

🚨 **The band is TALLER than one cell.** On this machine (`font_size 18`, `modify_font cell_height 94%`
⇒ cell 45 device px; `box_drawing_scale` level 1 default `1.0pt` at dpi 144 ⇒
`thickness_as_float = 2.0`, `border_width = 2`), the band is `45 + 2 + 4 = **51 device px**` — it
covers content row 1 entirely **plus the top 6 px of row 2**. Any hit test that assumes "one cell"
is wrong by 6 px. UNMEASURED (derived from the three constants above; no build run).

⇒ The hit test must not recompute this. `render_a_bar` already **returns the height it drew** and
returns `0` on every not-drawn path (`:843` malloc failure, `:854` `!title`, `:856`
`draw_window_title` failure). Store that return value on the `Window` and read it back. Zero drift
between painter and hit test, 4 bytes of state, no arithmetic duplicated.

### 1.5 The patch's shape

Add `unsigned title_band_height` to `Window`; the new draw site writes `render_a_bar(...)`'s return
value into it every frame **and writes 0 on the not-drawn path**; the hit test reads it. With the
option off nothing ever writes it, it stays `0`, and the new `if` short-circuits on its very first
term — the loop body is then byte-for-byte the current one. **That is the proof of inertness, and it
does not depend on any geometry argument.**

---

## 2. Every consumer of `MouseRegion.in_title_bar` and of `r.window`, and what changes

There are exactly **six** `mouse_region()` call sites in `~/kitty-482 kitty/mouse.c`
(`grep -n 'mouse_region(' kitty/mouse.c` → `988` decl, `1119`, `1130`, `1169`, `1274`, `1354`, `1499`).
Three pass `detect_title_bar = false` and are therefore **structurally unreachable by the new arm**.

| # | site | args | new arm fires? |
|---|---|---|---|
| 1 | `focus_in_event()` `:1119` | `(false, false)` | **no** |
| 2 | `update_mouse_pointer_shape()` `:1130` | `(false, true)` | yes |
| 3 | `enter_event()` `:1169` | `(false, false)` | **no** |
| 4 | `mouse_event()` redirect path `:1274` | `(false, false)` | **no** |
| 5 | `mouse_event()` main path `:1354` | `(true, true)` | yes — this is the one that matters |
| 6 | `scroll_event()` `:1499` | `(false, true)` | yes |

### 2.1 `:1356` `set_currently_hovered_window(w && !r.window_border && !r.in_title_bar ? w->id : 0, …)`

With `in_title_bar` true this passes **0**, so `set_currently_hovered_window()`
(`~/kitty-482 kitty/mouse.c:183-209`) runs its "left window" block for the pane under the band:

- `:187` `update_scrollbar_hover_state(left_window, false)` — scrollbar un-hovers.
- `:190` `screen_mark_url(left_window->render_data.screen, 0, 0, 0, 0)` — **URL/hyperlink highlight
  is cleared.** This is the answer to "URL/hyperlink hover": moving into the band un-highlights,
  which is correct and identical to today's stolen-row bar.
- `:191` `drop_left_child(left_window)` — a hovered drop target is released.
- `:192-198` `encode_mouse_event(left_window, 0, LEAVE, modifiers)` and the escape code is written
  to the child.

🚨 **This is the one consumer whose new behaviour deserves a decision, not just a note.** An
application in mouse-tracking mode (vim, tmux, htop, a TUI) will receive a **mouse-leave** every
time the pointer crosses into the top ~51 px of its own viewport, and a re-enter when it leaves.
For the stolen-row bar that is unambiguously right (the bar is outside the child's viewport). For an
**overlay** band the child's viewport genuinely extends under the band, so the leave is a lie about
geometry — but it is the truthful statement about *who owns the pointer right now*, and it is what
keeps the app from drawing a hover highlight under chrome it cannot see. I recommend keeping it
(no code change at `:1356`) and naming it in the option's documentation. UNMEASURED: no TUI was
driven; derived from `:1356` → `:184-198`.

### 2.2 `:1362` `else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id)`

This arm sets `mouse_cursor_shape = POINTER_POINTER` (`:1363`) and calls
`handle_window_title_bar_mouse(tw, button, modifiers, action)` (`:1368`). Because it is an
`else if` chain, the branches below it are **not** taken. Consequences, each a direct read of the
skipped code:

- **Text selection — not started.** `handle_event()` (`:917-926`) → `handle_button_event()`
  (`:864`) / `handle_move_event()` (`:666`) is the only route to `mouse_selection()` and to
  `set_mouse_position()`. Never reached ⇒ a press in the band starts no selection, a drag in the
  band extends none.
  **But an in-progress selection is unaffected**, and that is important: `mouse_event()` checks
  `global_state.active_drag_in_window` at `:1282` — *before* `mouse_region()` is ever called at
  `:1354` — and returns at `:1291`/`:1301`. So a selection started in content and dragged upward
  through the band keeps working. Clean negative, no fix needed.
- **Mouse reporting to the application — the app does NOT receive the click.** The two writers are
  `handle_move_event:685-686` and `handle_button_event:896-897`, both below `handle_event()`.
  *Should* it? **No.** A title bar that also forwarded the press would make a press-drag ambiguous
  between "move this pane" and "the app's own drag", and it would diverge from the stolen-row bar,
  which also swallows it. This is the same swallow the tab bar performs at `:1358-1360`.
- **Click queues — no entry.** `add_press()` (`:748`) and `dispatch_possible_click()` (`:843`) are
  called only at `handle_button_event:903-906`. Not reached ⇒ no double/triple-click word/line
  selection in the band. Double-click in the band is instead consumed by
  `tabs.py:handle_window_title_bar_mouse` at `~/kitty-482 kitty/tabs.py:1878-1881`, which calls
  `w.set_window_title()` — the rename prompt. That is a **feature** and matches a real title bar.
- **`w->drag_source.initial_left_press`** (`handle_button_event:884-891`) is never armed from the
  band, so the child-side drag-and-drop offer and the URL-drag at `:689-702` cannot start there.
  Correct.
- **Scrollbar hover/drag — a genuine regression, bounded.** `handle_scrollbar_mouse()` is called at
  `:669` (move), `:873` (button) and `:1136` (`update_mouse_pointer_shape`); all three are below
  branches the title-bar arm pre-empts. With `scrollbar` defaulting to `scrolled`
  (`~/kitty-482 kitty/options/types.py:646`) and `scrollbar_interactive` to `true` (`:652`), the
  scrollbar is drawn at the window's right edge over its full height — so **the top ~51 px of the
  scrollbar becomes ungrabbable while the band is on.** Mitigation, if wanted: make the band's
  `right` stop short of the scrollbar hitbox. Not included in this patch; named as a residual.
- **`r.window_border` — the border arm pre-empts the band, not the other way round.** The border
  block runs at `:1004-1066` and `return ans` at `:1062`, *before* the window loop at `:1067`. It
  fires only when `detect_borders && num_visible_windows(t) > 1` (`:1004`) and within
  `OPT(window_drag_tolerance)` converted to px at `:1008-1009`. With the operator's
  `window_drag_tolerance 6` (pt) at dpi 144 that is **12 device px**, so for a pane that is not at
  the top of the layout the band's top 12 px of 51 give `NS_RESIZE_POINTER` and a resize-drag rather
  than the hand. Exactly the same is true of today's stolen-row bar — **unchanged by this patch**,
  worth stating because it will be observed and misread as new.
- **`ans.window` set by the band arm skips the scrollbar fallback at `:1085`.** `if (!ans.window &&
  OPT(scrollbar_interactive))` — but the band is inside its window's content rect, so
  `contains_mouse` already set `ans.window` for that point before the patch. **No change.**

### 2.3 `:1499` `scroll_event()` — `mouse_region(false, true)`, and it ignores `in_title_bar`

`scroll_event` reads only `r.window` (`:1500`) and `r.in_tab_bar` (`:1501`). So a wheel scroll over
the band scrolls the pane beneath it. Two things follow. First, **`in_title_bar == true` for a point
`r.window` also owns is already an expressible, exercised state in v0.48.2** — nothing in the file
assumes the two are exclusive, which is the strongest evidence the new arm does not violate an
invariant. Second, wheel-over-band scrolling is the behaviour a user expects of a thin overlay, so
no change is wanted here.

### 2.4 `:1131-1134` `update_mouse_pointer_shape()`

`in_title_bar` → `POINTER_POINTER` at `:1134`, and the `else if (r.window)` at `:1135` is skipped,
so `screen_mark_url(…, 0,0,0,0)` at `:1139` and `set_mouse_cursor_for_screen()` at `:1140` do not
run. Harmless: the URL mark was already cleared by `:1356` → `:190` on the move that got you there.

### 2.5 `:1116-1124` `focus_in_event()` — a small pre-existing wart the band inherits

It sets `mouse_cursor_shape = TEXT_POINTER` at `:1118` and calls `mouse_region(false, false)`, so it
has no title-bar arm at all. Clicking back into a kitty OS window while the pointer rests on the
band leaves an **I-beam** until the next mouse move re-runs `mouse_event()`. Identical for today's
stolen-row bar. Not fixed here (a one-line `mouse_region(false, true)` + `if (r.in_title_bar)` would
do it, but it changes behaviour for the existing bar and is out of this brief's scope).

### 2.6 `enter_event():1172` `if (!w || r.in_tab_bar || r.in_title_bar) return;`

Dead condition: `enter_event` passes `detect_title_bar = false` at `:1169`, so `r.in_title_bar` can
never be true there — today or after the patch. Noted so a reader does not think it is a consumer.

---

## 3. `update_mouse_pointer_shape()` and the hand cursor on plain hover

**Yes, the band test fires there** — `:1130` passes `detect_title_bar = true`, `detect_borders = false`.
`detect_borders` gates only the border block at `:1004`; the window loop at `:1067` (and therefore
the new arm) is outside that gate. So `POINTER_POINTER` is reached at `:1134`.

🚨 **But the brief's premise about which function produces the hover cursor is wrong, and the real
answer is better.** `update_mouse_pointer_shape()` is reached from exactly one place —
`pyupdate_pointer_shape` (`~/kitty-482 kitty/state.c:1621-1631`) — whose only Python callers are
`set_pointer_shape()` at `~/kitty-482 kitty/window.py:2856` and `:2860`, i.e. **only when a child
application changes the pointer shape via the OSC pointer-shape protocol.** It is a refresh path,
not the hover path.

The ordinary hover path is `mouse_event()` with `button == -1`, which:
1. calls `mouse_region(true, true)` at `:1354`,
2. takes the title-bar arm at `:1362` (the `button > -1 ||` guard is inside
   `handle_window_title_bar_mouse` at `:933`, not on the arm, so a move still sets the shape),
3. assigns `mouse_cursor_shape = POINTER_POINTER` at `:1363`,
4. and applies it at `:1405` `if (mouse_cursor_shape != old_cursor) set_mouse_cursor(...)`.

No button is held on any of that. **So the hand appears on plain hover, from `:1363`, and it also
survives an application pointer-shape change, from `:1134`.** Both paths covered; no extra code.

UNMEASURED: not observed on screen — no build was run. The chain above is four `file:line` reads in
one tree and the `POINTER_POINTER` assignment is literally the same constant the tab bar uses at
`:1359`, which is known to produce a hand today.

---

## 4. The wedge: `global_state.window_being_dragged` has no C-side clear

### 4.1 The asymmetry, confirmed in both trees

```
$ cd ~/kitty-482 && grep -rn "window_being_dragged" kitty/*.c kitty/*.h
kitty/mouse.c:933   if (button > -1 || global_state.window_being_dragged.id) {
kitty/mouse.c:1362  } else if ((r.in_title_bar && r.window) || global_state.window_being_dragged.id) {
kitty/mouse.c:1365  if (!tw && global_state.window_being_dragged.id) {
kitty/mouse.c:1366  tw = window_for_window_id(global_state.window_being_dragged.id);
kitty/state.c:1762  #define wbd global_state.window_being_dragged
kitty/state.c:1764  set_window_being_dragged(...)
kitty/state.c:1771  get_window_being_dragged(...)
kitty/state.h:534   } window_being_dragged;
```

**Four reads in `mouse.c`, zero writes.** The only writer is the Python-facing
`set_window_being_dragged` (`~/kitty-482 kitty/state.c:1763-1768`, which `zero_at_ptr`s then parses
optional args — so a bare call clears it).

Contrast the tab bar, which *does* have a C-side recovery, `~/kitty-482 kitty/mouse.c:943-955`:

```c
943    if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_RELEASE && global_state.tab_being_dragged.id
944            && global_state.tab_being_dragged.drag_started && !global_state.drag_source.is_active) {
...        // Once a system drag and drop is active the release is consumed by it
...        // and never delivered to us, so getting one here means the drag never became a system DND
951        zero_at_ptr(&global_state.tab_being_dragged);
953        if (w) w->tab_bar_data_updated = false;
954        return;
955    }
```

`handle_window_title_bar_mouse` (`~/kitty-482 kitty/mouse.c:929-937`) is the same function with that
block **deleted** — it is 9 lines and forwards unconditionally.

Checked in master too: `~/kitty-dev` at `1d67ecd47`, `kitty/mouse.c:961-967` is the identical
9-line function and `grep -n window_being_dragged kitty/mouse.c` returns only `964`, `1427`, `1430`.
**Upstream has not fixed this.** So the hazard is not a v0.48.2 artefact.

### 4.2 What actually clears it, and the one hole

The Python clears, all reachable only after the C forwards an event:

| clear | file:line (`~/kitty-482`) | when |
|---|---|---|
| ordinary release | `kitty/tabs.py:1876-1877` | any non-motion LEFT event that is not a PRESS — i.e. the release. **This is the common path and it works.** |
| `start_window_drag` failed | `kitty/tabs.py:1887`, `:1909` | `boss.window_id_map` miss, or `start_drag_with_data` raised `OSError` |
| drop inside kitty | `kitty/boss.py:1996`, `kitty/tabs.py:2039` | `on_drop` / `on_window_drop` |
| drop outside / cancelled | `kitty/boss.py:2041` | `on_drag_source_finished` |

The sticky arm at `:1362` (`|| global_state.window_being_dragged.id`) is **what delivers the
release** after the pointer has left the band — it is the mechanism, not the bug. A press-then-
release with no drag arms and disarms cleanly through `tabs.py:1876-1877`.

**The hole** is the state the tab bar's recovery exists for: `drag_started == true`, the system DND
never materialised (or materialised and the platform never delivered `on_drag_source_finished`), and
so the release is consumed by nothing. From that moment `:1362` is true for **every** mouse event in
the OS window, forever: no selection, no clicks, no scrollbar, no resize, every event forwarded to
`tabs.handle_window_title_bar_mouse`, which for `button == -1` just re-checks the drag threshold and
returns. A wedged terminal that still renders. UNMEASURED — I did not reproduce it; the code path is
established from the four sites above plus the tab bar's own comment at `:945-950` asserting the
failure mode exists.

### 4.3 Does the patch widen, narrow, or leave it unchanged?

**Per-arming leak probability: unchanged.** The patch does not touch `:1362`, `:929-937`, or any
clear path. A press in the band arms exactly the same state through exactly the same call, and every
escape route is byte-identical.

**Arming rate: widened, materially.** Today a press can arm `window_being_dragged` only from the
stolen-row bar — which the operator does not use, and which most users never see because
`window_title_bar_min_windows` defaults to `0` (`~/kitty-482 kitty/options/types.py:727`, i.e. the
bar is off). After the patch, every pane grows a permanently-present ~51 px strip across its full
width whose presses arm it. On a 3-pane layout at this machine's geometry that is roughly
`3 × 51 px × pane_width` of newly-arming surface where there was ~none.

So: **the patch does not make a leak more likely per press; it multiplies the presses.** Under a
fixed per-arming failure rate that is the same thing as multiplying the incident rate, and it is the
honest way to state it. A band-scoped press is not special in any other way — it produces an
identical `set_window_being_dragged(window_id, False, x, y)` at `~/kitty-482 kitty/tabs.py:1873`.

### 4.4 The 12-line recovery, recommended and independent of everything else

Mirror the tab bar exactly. This is a **separate commit** — it fixes a pre-existing v0.48.2/master
bug and should not be entangled with the hit-test change, so that if the band is reverted the
recovery survives.

```c
 static void
 handle_window_title_bar_mouse(Window *w, int button, int modifiers, int action) {
     OSWindow *osw = global_state.callback_os_window;
     if (!osw) return;
+    if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_RELEASE && global_state.window_being_dragged.id
+            && global_state.window_being_dragged.drag_started && !global_state.drag_source.is_active) {
+        // Symmetric with handle_tab_bar_mouse(): once a system drag and drop is
+        // active the release is consumed by it and never delivered to us, so
+        // getting one here means the drag never became a system DND. Clear the
+        // drag state so mouse handling is not redirected forever, and swallow
+        // the release as it ended an aborted drag.
+        zero_at_ptr(&global_state.window_being_dragged);
+        call_boss(clear_forced_window_title_bars, NULL);
+        return;
+    }
     if (button > -1 || global_state.window_being_dragged.id) {
```

`call_boss(clear_forced_window_title_bars, NULL)` is needed because `start_window_drag` sets
`t.force_show_title_bars = True` across every tab manager
(`~/kitty-482 kitty/tabs.py:1891-1897`) and only `_clear_force_show_title_bars()`
(`kitty/tabs.py:1918-1926`) undoes it — leaving stolen rows on every pane otherwise. That Python
helper does not exist on `Boss` today and would need a four-line addition; if that is unwanted, drop
the line and accept that an aborted DND leaves the forced bars up until the next relayout.
UNMEASURED: not compiled.

**Precision about `drag_source.is_active`:** it is the guard that distinguishes "release arrived
because the DND never started" from "release will arrive later via the DND". I have not verified its
lifetime on macOS; the tab bar has shipped with it since the same commit, which is the only evidence
offered.

---

## 5. The option: yes, it must be gated — and it must NOT be read from `mouse.c`

### 5.1 Must it be gated?

**Yes, and there is no argument on the other side.** The band swallows the click, suppresses text
selection in the top ~51 px of every pane, sends a spurious mouse-LEAVE to every mouse-tracking
child, and makes the top slice of every scrollbar ungrabbable (§2.2). That is a large behaviour
change to hand every kitty user by default. Default `no`.

### 5.2 Where the option must be readable from C — and the surprise

`window_title_bar` and `window_title_bar_min_windows` **are not in the C `Options` struct at all**:

```
$ cd ~/kitty-482 && grep -n "window_title_bar" kitty/state.h
kitty/state.h:76:  ... window_title_bar_active_foreground, window_title_bar_active_background,
                       window_title_bar_inactive_foreground, window_title_bar_inactive_background;
```

Only the four colours. The position and the min-windows threshold are Python-only, consumed at
`~/kitty-482 kitty/window.py:1055` (`opts.window_title_bar`) and
`~/kitty-482 kitty/layout/base.py:408-412` (`window_title_bar_min_windows`). So the new option does
**not** get a C field for free; it must ask for one.

The mechanism is `ctype=` in the option declaration. `~/kitty-482 kitty/options/definition.py:66-71`:

```python
opt(
    'force_ltr',
    'no',
    option_type='to_bool',
    ctype='bool',
    ...
```

which generates, in `~/kitty-482 kitty/options/to-c-generated.h`, the pair
`convert_from_python_<name>` / `convert_from_opts_<name>` (pattern at `:268-279` for
`scrollbar_interactive`) plus a line in the apply function (`:1571`). The generated setter writes
`opts-><name> = PyObject_IsTrue(val);`, so **a matching field must exist in `Options` in
`kitty/state.h`** or the build fails. Four edits, three of them regenerated:

| file (`~/kitty-482`) | edit |
|---|---|
| `kitty/options/definition.py` | new `opt(...)` with `option_type='to_bool', ctype='bool'` |
| `kitty/options/parse.py`, `types.py`, `to-c-generated.h` | **regenerated** (`python3 setup.py build` runs `gen/config.py`); do not hand-edit |
| `kitty/state.h` `Options` | `bool window_title_bar_overlay;` |

`OPT(window_title_bar_overlay)` is then `global_state.opts.window_title_bar_overlay`
(`~/kitty-482 kitty/state.h:19` `#define OPT(name) global_state.opts.name`).

### 5.3 …but the hit test must not read it

**Read the option once, at the paint site in `shaders.c`, and let the hit test read the painter's
own output.** Reasons, in order of weight:

1. **Zero drift.** `render_a_bar` already returns the exact height it drew and returns `0` on every
   not-drawn path (`~/kitty-482 kitty/shaders.c:843` malloc fail, `:854` `!title`, `:856`
   `draw_window_title` fail). A hit test keyed on that value can never claim a band that was not
   painted, and can never miss one that was. A hit test keyed on `OPT(...)` plus recomputed
   arithmetic can do both — and would silently drift the day `bar_height` changes from
   `cell_height + 2`.
2. **Latency.** `mouse_region()`'s window loop runs on every mouse move for every window in the tab.
   `win->title_band_height` is one `unsigned` load in the same struct the loop is already touching;
   `OPT(...)` is a separate global. Putting the height first in the `&&` chain makes the whole arm a
   single predicted-not-taken branch when the feature is off.
3. **Inertness proof.** With nothing writing the field, the arm is provably dead — no reasoning
   about geometry, padding or option parsing required (§1.5).

**Residual, stated rather than hidden:** the field is one frame stale. Turning the option off via
`kitty @ load-config` leaves the arm live until the next paint. A config reload dirties every
window, so that is one frame (~8 ms at 120 Hz). If that is judged unacceptable, add
`OPT(window_title_bar_overlay) &&` to the arm and accept the extra load; I do not recommend it.

**Contract the paint half must honour** (not in this diff — see §6):

```c
// in draw_cells(), for a normal window, before/after the cell draw as appropriate:
if (window) {
    window->title_band_height = (OPT(window_title_bar_overlay) && window->title)
        ? render_a_bar(&ui, &window->title_bar_data, window->title, false)
        : 0;                                   // <-- the else branch is load-bearing
}
```

The `else 0` is what makes the option dynamically revocable. Omit it and the band stays hit-testable
after it stops being drawn. Note also that `render_a_bar` *shares* `window->title_bar_data` with
`draw_hyperlink_target` (`~/kitty-482 kitty/shaders.c:929`) and `draw_window_number`
(`:943`) — all three use the same `WindowBarData` scratch buffer, so a URL bar and a title band in
the same frame will thrash `bar->last_drawn_title_object_id` and re-rasterise both every frame. That
is a real cost for "zero memory pressure" and argues for giving the band its **own** `WindowBarData`
field. UNMEASURED; flagged for the render axis.

---

## 6. The unified diff — hit-test half only

🚨 **This diff alone is a deliberate no-op.** Nothing in it writes `title_band_height`, so the new
arm never fires and `mouse_region()` behaves exactly as it does today. That is the point: it is
independently landable and independently revertible, and it lets the paint half be reviewed against
a hit test that is already on trunk. Apply against `~/kitty-482` @ `2cb1d95c3` (v0.48.2).

**NOT COMPILED.** No build was run (brief rule 6). Line offsets are from this tree; the hunks are
hand-written and have not been fed to `git apply`.

```diff
--- a/kitty/state.h
+++ b/kitty/state.h
@@ -266,10 +266,15 @@ typedef struct Window {
     WindowRenderData render_data;
     WindowRenderData window_title_render_data;
     WindowLogoRenderData window_logo;
     MousePosition mouse_pos;
     struct {
         unsigned int left, top, right, bottom;
     } padding;
+    // Height in device px of the overlay title band drawn over the TOP of this
+    // window's own content area, as returned by render_a_bar(). Zero when no
+    // band was drawn on the last frame -- which is also how the feature is
+    // switched off: nothing writes this unless window_title_bar_overlay is on,
+    // so the hit test arm in mouse_region() is dead by construction.
+    unsigned title_band_height;
     ClickQueue click_queues[8];
     monotonic_t last_drag_scroll_at;
     uint32_t last_special_key_pressed;

@@ -116,6 +116,7 @@ typedef struct {
     bool force_ltr;
     bool resize_in_steps;
     bool sync_to_monitor;
+    bool window_title_bar_overlay;
     bool close_on_child_death;
     bool window_alert_on_bell;
     bool macos_dock_badge_on_bell;

--- a/kitty/mouse.c
+++ b/kitty/mouse.c
@@ -269,6 +269,28 @@ static bool
 contains_mouse(Window *w) {
     double x = global_state.callback_os_window->mouse_x, y = global_state.callback_os_window->mouse_y;
     return (w->visible && window_left(w) <= x && x < window_right(w) && window_top(w) <= y && y < window_bottom(w));
 }
 
+// The overlay title band is drawn by render_a_bar() over the top of the window's
+// OWN content area, at exactly the window's render geometry (see shaders.c:
+// ui.screen_left/screen_top are srd->geometry.left/top). Its height is whatever
+// render_a_bar() returned on the last frame, so this function and the painter can
+// never disagree about where the band is.
+static bool
+mouse_in_title_band(const Window *w) {
+    const WindowGeometry *g = &w->render_data.geometry;
+    const OSWindow *osw = global_state.callback_os_window;
+    const double x = osw->mouse_x, y = osw->mouse_y;
+    // The band can be taller than one cell (cell_height + 2 + 2*border_width), so
+    // clamp it to the content area: on a one-row window it would otherwise reach
+    // into the gap below and into the next window's hit rect.
+    unsigned bottom = g->top + w->title_band_height;
+    if (bottom > g->bottom) bottom = g->bottom;
+    return g->left <= x && x < g->right && g->top <= y && y < bottom;
+}
+
 static bool
 border_contains_mouse(BorderRect *br, double tolerance, Edge *edges) {
     bool ans = false;

@@ -1067,6 +1089,20 @@ mouse_region(bool detect_borders, bool detect_title_bar) {
         for (unsigned int i = 0; i < t->num_windows; i++) {
             Window *win = t->windows + i;
+            // An overlay title band is INSIDE win's own content rect, so it must be
+            // tested before contains_mouse() or it is unreachable. This cannot change
+            // which window is selected: the band is a strict subset of win's content
+            // rect, and the content rects of distinct visible windows are pairwise
+            // disjoint (layout/base.py guarantees padding <= space on every edge), so
+            // for any point the window that wins here is the same one contains_mouse()
+            // would have picked. Only its CLASSIFICATION changes, from content to
+            // in_title_bar. title_band_height is first in the && chain so that when the
+            // feature is off this whole arm is one predicted-not-taken branch.
+            if (win->title_band_height && detect_title_bar && win->visible
+                    && win->render_data.screen && mouse_in_title_band(win)) {
+                ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
+                break;
+            }
             if (contains_mouse(win) && win->render_data.screen) {
                 ans.window_idx = i; ans.window = win; break;
             } else if (detect_title_bar && win->visible) {
```

Plus, in `kitty/options/definition.py`, beside the existing `window_title_bar_min_windows`
(`~/kitty-482 kitty/options/definition.py:1951-1961`):

```python
opt(
    'window_title_bar_overlay',
    'no',
    option_type='to_bool',
    ctype='bool',
    long_text="""
Draw the window title as a one-line band over the TOP of the window's own content
instead of reserving a text row for it. The band is hit-tested like a real title
bar: hovering it shows a hand pointer and dragging it moves the window. Unlike
:opt:`window_title_bar_min_windows` this steals no row, so toggling it never
resizes the terminal or shifts content. Note that while the band is shown, the
content under it cannot be selected with the mouse, clicks in it are not sent to
the running application, and the top of the scrollbar is not grabbable.
""",
)
```

then regenerate (`python3 setup.py build` runs `gen/config.py`); `parse.py`, `types.py` and
`to-c-generated.h` are generated files and must not be hand-edited.

### 6.1 What I rejected and why

- **Reordering the existing `else if` arm at `:1071-1080` to run before `contains_mouse`.** Changes a
  real verdict for any user with `window_padding_width` top > 0 (§1.2). Invisible on this machine,
  wrong elsewhere.
- **Reusing `window_title_render_data` for the band.** It is written from Python at
  `~/kitty-482 kitty/window.py:1124` / `:1177` and is the stolen-row bar's own geometry; sharing it
  would make the two features mutually exclusive in a way neither option expresses, and would make
  the paint half (C) and the hit test (C) go through a Python round trip for no reason.
- **Computing the band rect in `mouse.c` from `cell_height`.** The band is `cell_height + 2 +
  2*ceil(thickness_as_float(osw,1))` tall (`~/kitty-482 kitty/shaders.c:838-839`, `:871`) — 51 px,
  not 45, on this machine. Any recomputation is a second source of truth that will drift.
- **Reading `OPT(window_title_bar_overlay)` in the hit test.** One extra global load on the hottest
  path to buy one frame of revocation latency (§5.3).
- **A new `MouseRegion` field (e.g. `in_overlay_band`) distinct from `in_title_bar`.** Tempting for
  clarity, but every consumer in §2 wants exactly the title-bar behaviour, and a new field would
  have to be wired into all six call sites — more diff, more chances to miss one, no behaviour gained.

---

## 7. What is UNMEASURED

Everything dynamic. No kitty build was run (brief rule 6), no patched binary exists, and the
operator's live instance (pid 597) was never written to. Specifically unverified by execution:

- that the patch compiles;
- that the hand cursor actually appears (the chain `:1354 → :1362 → :1363 → :1405` is read, not run);
- that a left press in the band starts a native window drag end-to-end through
  `tabs.py:1866-1874 → request_callback_with_thumbnail → start_window_drag`;
- that a no-op drag (press, release, same position) leaves the band on — the mechanism is
  `tabs.py:1876-1881` clearing `window_being_dragged` with `drag_started == False`, but the band's
  persistence depends on the paint half, not on this diff;
- the 51 px band height (derived from three constants);
- the `pad_top` overlap of §1.2 (derived from four `file:line` sites);
- the wedge of §4.2 (the code path is established; the incident was not reproduced);
- `drag_source.is_active`'s lifetime on macOS.

The static claims — every `file:line`, every `grep` output quoted above — are reproducible with the
commands shown, in `~/kitty-482` at `2cb1d95c3`.

---

## Appendix A — verification log

Every command below was run in this session; outputs are quoted where they carry a claim.

```
$ cd ~/kitty-482 && git log -1 --format='%H %d %s'
2cb1d95c3accadd536bd66ba6bda044973440177  (HEAD, tag: v0.48.2) version 0.48.2

$ cd ~/kitty-dev && git log -1 --format='%H %s'
1d67ecd47c0bd68951868c363baa92039d936572 Merge branch 'fix-mimepat-guess-mime-type' of https://github.com/devangpratap/kitty

$ wc -l ~/kitty-482/kitty/mouse.c
    1688 /Users/chrisren/kitty-482/kitty/mouse.c

$ cd ~/kitty-482 && grep -n 'in_title_bar\|mouse_region(\|contains_mouse\|window_title_render_data\|handle_window_title_bar_mouse\|window_being_dragged\|set_currently_hovered_window' kitty/mouse.c
184 set_currently_hovered_window   270 contains_mouse        276 border_contains_mouse
920 set_currently_hovered_window   930 handle_window_title_bar_mouse
933 window_being_dragged           982 in_title_bar (struct field)
988 mouse_region(bool,bool)        1069 contains_mouse        1072 window_title_render_data
1076 in_title_bar = true            1119/1130/1169/1274/1354/1499 mouse_region() call sites
1133 else if (r.in_title_bar)       1172 enter_event guard
1356 set_currently_hovered_window   1362 title-bar arm   1365/1366 window_being_dragged

$ cd ~/kitty-482 && grep -rn "window_being_dragged" kitty/*.c kitty/*.h
# 4 reads in mouse.c, 0 writes; only writer is state.c:1763 set_window_being_dragged

$ cd ~/kitty-dev && grep -n "window_being_dragged" kitty/mouse.c
964 / 1427 / 1430    # identical 3 reads, still no C-side clear on master

$ cd ~/kitty-482 && grep -rn "update_mouse_pointer_shape" kitty/
kitty/mouse.c:1128  kitty/state.c:1628  kitty/state.h:638
$ cd ~/kitty-482 && grep -rn "update_pointer_shape" kitty/
kitty/window.py:2856  kitty/window.py:2860   # only OSC pointer-shape changes reach it

$ cd ~/kitty-482 && grep -n "window_title_bar" kitty/state.h
kitty/state.h:76   # only the 4 colours -- position/min_windows are Python-only

$ cd ~/kitty-482 && grep -n "ctype=" kitty/options/definition.py | head -3
64: ctype='double'   70: ctype='bool'   128: ctype='int'

$ cd ~/kitty-482 && grep -n "scrollbar: \|scrollbar_interactive" kitty/options/types.py
646: scrollbar: choices_for_scrollbar = 'scrolled'
652: scrollbar_interactive: bool = True

$ cd ~/kitty-482 && grep -n "def decoration" -A 5 kitty/window_list.py
123-127: return w.effective_margin(which) + w.effective_border()*border_mult + w.effective_padding(which)
```

Reads (no output quoted, cited inline above): `kitty/mouse.c` 180-300, 900-1200, 1260-1440,
1480-1530; `kitty/state.c` 985-1025, 1199-1225, 1758-1782; `kitty/state.h` 60-145, 180-290, 526-552;
`kitty/shaders.c` 30-45, 300-320, 820-960, 1420-1470; `kitty/window.py` 840-880, 1030-1200,
2845-2865; `kitty/tabs.py` 1840-1930, 2028-2045; `kitty/boss.py` 1960-2050;
`kitty/layout/base.py` 140-200, 400-470.

**Not run:** any build, any patched binary, any write to a kitty instance. The operator's live
kitty (pid 597) was never contacted, not even read-only.

---

## ADVERSARIAL VERIFICATION

Re-measured 2026-09-16 by a second agent. Every `file:line` below was re-opened in the tree it
names. Trees re-identified: `~/kitty-482` → `2cb1d95c3 (tag: v0.48.2)`, `~/kitty-dev` →
`1d67ecd47`. No kitty build was run. Two things WERE executed that the original was not: the
delivered diff was fed to `patch` and `git apply`, and the patched `kitty/mouse.c` was put through
`clang -fsyntax-only -Wall -Wextra` with a control arm and a negative control.

**Verdict: 9 of 10 numbered claims survive re-measurement. The diff does not.** Two findings
overturn parts of the write-up, and one of them defeats the operator's hard requirement (a) on the
normal success path.

### O1 — OVERTURNED. The delivered diff is malformed and applies nowhere. (Claim 10)

Claim 10 says the diff is "compiles-untested". It is worse than that: it is **apply**-untested, and
it does not apply. Three of its four hunk headers state wrong line counts.

| hunk | declared | actual |
|---|---|---|
| `@@ -266,10 +266,15 @@` `state.h` Window | new **15** | new **16** (the comment is 5 lines + 1 field) |
| `@@ -116,6 +116,7 @@` `state.h` Options | 6 / 7 | 6 / 7 ✔ (but `bool force_ltr;` is at **:115**, so the start is off by one) |
| `@@ -269,6 +269,28 @@` `mouse.c` | old 6 / new 28 | old **8** / new **26** |
| `@@ -1067,6 +1089,20 @@` `mouse.c` | old 6 / new 20 | old **5** / new **19** |

Measured, both arms:

```
$ patch -p1 --dry-run < patch.diff
patching file 'kitty/state.h'
patch: **** malformed patch at line 19:      uint32_t last_special_key_pressed;   (rc 2)

$ git apply --check patch.diff
error: corrupt patch at patch.diff:21                                            (rc 128)
```

**Positive control — the CONTENT is fine, only the headers are broken.** Recomputing the four counts
from the hunk bodies and reordering the two `state.h` hunks ascending (they are emitted 266-then-116)
gives `-116,6 +116,7` · `-266,10 +266,16` · `-269,8 +269,26` · `-1067,5 +1089,19`, and that diff
applies cleanly (`git apply` rc 0). The patched translation unit then compiles:

```
control  (unpatched kitty/mouse.c)  clang -fsyntax-only -Wall -Wextra  →  rc 0, no diagnostics
patched  (corrected diff applied)   same flags                        →  rc 0, no diagnostics
negative (same, field deleted from state.h)                           →  2 errors, "no member named
                                                                          'title_band_height'"
```
(`clang -I<python3.11 include> -I/opt/homebrew/include/harfbuzz -I. -Ikitty -I3rdparty`; the negative
control is what proves the check reached the new code rather than passing vacuously.)

**Corrected claim 10:** the diff is semantically a no-op and, once its hunk headers are corrected,
applies cleanly to `~/kitty-482 @ 2cb1d95c3` and passes `clang -fsyntax-only -Wall -Wextra` with no
new diagnostics — verified. As printed it applies to nothing. Re-emit it with `git diff`, never by
hand; a hand-written hunk header is a second source of truth for a count the body already carries.

### O2 — OVERTURNED (the evaluative half). The naive reorder's flip is a BUG FIX, not a regression — and at `padding.top ≥ cell_height` today's title bar is entirely undraggable. (Claim 1, headline)

The arithmetic is CONFIRMED, re-derived from re-read sources (`kitty/window.py:1062` `render_top =
new_geometry.top + cell_height`, `:1064-1065` `tb_top/tb_bottom`, `kitty/window.py:846-857`
`effective_padding` with no title-bar term, `kitty/state.c:1189-1197` storing it verbatim,
`kitty/mouse.c:260-262` `window_top = geometry.top - padding.top`). The two rects do overlap in the
bar's bottom `padding.top` pixels and `contains_mouse` does win them today.

What is wrong is the **sign**. Those pixels are the bottom of a title bar; classifying them as
content is why hovering there gives an I-beam and a press starts a text selection instead of the
hand and the drag. The reorder does not "silently flip them wrongly for other users" — it *fixes*
them for other users.

And the stratum is larger and worse than the write-up states. `window_top(w) = g.top + cell_height −
padding.top`, so when **`padding.top ≥ cell_height`** that rises to or above `tb_top`: `contains_mouse`
then swallows the *entire* stolen-row title bar, the `else if` arm at `kitty/mouse.c:1071-1080` is
unreachable for that window, and the bar has **no hand cursor and cannot be dragged at all**. That is
reachable on stock configs (`window_padding_width 15` at dpi 96 ≈ 20 px against a ~20 px default
cell) and is present in both `~/kitty-482` and `~/kitty-dev`.

**Corrected claim 1:** the overlap is `min(padding.top, cell_height)` pixels, not `padding.top`; it
is a **pre-existing upstream defect in v0.48.2 and master** whereby the bottom of a top stolen-row
title bar is dead to the drag, and completely dead once `padding.top ≥ cell_height`. Reordering the
existing arm would fix it. The recommendation to add a separate arm keyed on a new field still
stands — but on the grounds the write-up already gives and does not lean on (coexistence with the
stolen-row bar, an inertness proof that needs no geometry argument, and not entangling an upstream
bug fix with a new feature), **not** because the reorder would be wrong elsewhere. File the reorder
as its own upstream fix rather than as a rejected option.

### O3 — OVERTURNED BY OMISSION, and this is the expensive one. Every real drag forces stolen-row title bars on every pane — the exact content shift the design exists to avoid.

§2 enumerates the C-side consumers of `MouseRegion` exhaustively and correctly (verified: `grep -n
in_title_bar kitty/*.c kitty/*.h` → `mouse.c` 982, 1076, 1133, 1172, 1356, 1362 and nothing else,
six sites, all covered; the six `mouse_region()` call sites and their argument pairs are verbatim
correct). But the hit test hands the press to `handle_window_title_bar_mouse`, which forwards into
Python, and **the Python side is where requirement (a) dies.**

`~/kitty-482 kitty/tabs.py:1888-1897`, inside `start_window_drag` — reached the moment the pointer
passes `drag_threshold` (`tabs.py:1858-1863`):

```python
min_w = opts.window_title_bar_min_windows
for tm in boss.all_tab_managers:
    tm.mark_tab_bar_dirty()
    for t in tm:
        visible = sum(1 for _ in t.windows.iter_all_layoutable_groups(only_visible=True))
        if not (min_w > 0 and visible >= min_w):
            t.force_show_title_bars = True
            t.relayout()
```

With the operator's `window_title_bar_min_windows 0`, `min_w > 0` is False, so `not False` is True
and **every tab of every tab manager forces stolen-row title bars**. `relayout()`
(`kitty/tabs.py:499-505`) runs the layout, which runs `Window.set_geometry`, which calls
`screen.resize()` + `resize_child()` → PTY resize + SIGWINCH + one row of content shift on every
pane. It is undone on drop (`kitty/tabs.py:2035`, `kitty/boss.py:2036-2039`) — a second relayout and
a second SIGWINCH. Two full content shifts per successful drag, on every pane in every tab.

This is not the aborted-DND cleanup the write-up discusses in §4.4; it is the **normal success
path**. The band delivers the hand cursor and the native drag exactly as claimed, and then the drag
itself re-introduces the one-row shift the whole feature exists to remove.

**Corrected recommendation:** suppressing that force loop when the overlay option is on is a
**required fourth edit**, not a residual — the overlay band is already the drop-target affordance the
forced bars exist to provide. One line in `start_window_drag` (`if not opts.window_title_bar_overlay
and not (min_w > 0 and visible >= min_w):`) plus the matching skip in `_clear_force_show_title_bars`'s
counterpart. Note this makes the option Python-readable too, so the `ctype='bool'` C field of claim 7
is necessary but not sufficient — the option is needed on both sides.

### O4 — OVERTURNED. §5.3 attributes the per-frame re-rasterisation to WindowBarData SHARING. The real cause is that `needs_render` is never cleared, and a private WindowBarData does not fix it.

`grep -n needs_render kitty/*.c kitty/*.h` in **both** trees: `WindowBarData.needs_render` is set
`true` at `~/kitty-482 kitty/shaders.c:847` (on buffer alloc/resize) and `:925` (URL change) and is
**never assigned `false` anywhere**. `~/kitty-dev` is identical (`:1264`, `:1349`, no clear). The
struct is zero-initialised, so the first call allocates, sets it true, and it stays true for the life
of the window. The guard at `:852` is therefore `(cached != title) || true` forever after, and every
subsequent `render_a_bar` call re-runs `draw_window_title()` (CoreText, `:856`), re-uploads with
`glTexImage2D` and `glGenTextures`/`free_texture`s a texture — **every call, unconditionally.**

Today this is invisible because both existing consumers are rare (`draw_hyperlink_target` needs a
hyperlink under the mouse; `draw_window_number` needs `display_window_char != 0`). A band painted
every frame for every window turns it into `windows × fps` CoreText rasterisations and texture
round-trips — directly against "lowest to zero latency and memory pressure".

**Corrected claim:** give the band its own `WindowBarData` *and* clear `needs_render` after a
successful render (or gate the whole call on a title/size/colour change). The private buffer alone
removes the cross-consumer thrash the write-up names and leaves the per-frame cost untouched. Hand
this to the render axis as a blocking item, not a flag.

### N1 — NEW. `render_a_bar` is ALREADY called as a top band with the window's title, at `shaders.c:943`.

`draw_window_number` (`~/kitty-482 kitty/shaders.c:938-950`) contains
`title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false);` —
byte-for-byte the call the design proposes, guarded by `screen->display_window_char != 0`. Two
consequences:

- **Corroboration for claim 8.** `:946` and `:958` use the return value as "vertical space consumed
  at the top" (`letter_y = title_bar_height`), so upstream already treats it the way the hit test
  wants to. Independent support that was available and not cited.
- **A painter/hit-test divergence claim 8 promises cannot exist.** With the option on and a
  window-number overlay up, `render_a_bar` runs **twice per frame on the same `WindowBarData`** —
  guaranteed cache thrash on top of O4 — and the transient band drawn by `draw_window_number` is
  *not* hit-testable unless that site also writes `title_band_height`. "The painter is the single
  source of truth" holds only if **every** painter writes the field. Name the second site.

### N2 — NEW RISK. The inertness proof rests on an upstream bug.

Claim 8's "returns 0 on every not-drawn path" is true today, but `:854 if (!title) return 0;` and
`:856` live **inside** the `if (cached != title || needs_render)` block. They are reached on every
call only because `needs_render` is stuck true (O4). Fix O4 and a call with `title == NULL` against a
warm cache skips both guards, draws the stale cached bitmap, and returns a nonzero height — a
hit-testable band over a title nobody set. The proposed contract's `&& window->title` is what
actually carries this; keep it, and say so in the comment rather than crediting `render_a_bar`.

### N3 — NEW RISK, narrow. Claim 2's disjointness reads one window's padding for the whole group.

The proof is otherwise CONFIRMED verbatim (`~/kitty-482 kitty/layout/base.py:140-152` — `before_space
= before_dec` for `i > 0` and `≥ before_dec` for `i == 0`; `kitty/window_list.py:123-127` —
`decoration = margin + border*mult + padding ≥ padding`; so `padding ≤ space` on every edge). But
`decoration()` reads `self.windows[0]`, while `contains_mouse` reads each window's own
`w->padding`. A group whose **visible** member is an overlay carrying a `patch_edge_width`-modified
padding (`kitty/window.py:871-875`) can therefore have `padding > space` and overlap its neighbour.
Pre-existing and not created by the patch; worth one line in the comment, since the comment asserts
disjointness as unconditional.

### Claims re-measured and UPHELD

- **2** — disjointness and the "cannot change WHICH window is selected" conclusion: upheld, subject
  to N3. Also verified `mouse_region`'s `w` *is* `global_state.callback_os_window`
  (`kitty/mouse.c:991`), so the new helper and the loop read the same OSWindow — a real hazard the
  patch happens to avoid, since the existing title-bar arm uses `w->mouse_x` while `contains_mouse`
  uses the global.
- **3** — `bar_height = ui->cell_height + 2` (`shaders.c:839`), `border_rect.height = bar_height +
  2*border_width` with `.top = ui->screen_top` (`:871-872`), `ui.screen_left/.screen_top =
  srd->geometry.left/.top` (`:1439`), `thickness_as_float = box_drawing_scale[level] * dpi / 72`
  (`:305-310`), `box_drawing_scale` default `(0.001, 1.0, 1.5, 2.0)` (`kitty/options/types.py:548`)
  and **not overridden** in `config/kitty.conf`. So `border_width = 2` and the band is `45 + 2 + 4 =
  51` device px — upheld, conditional on the brief-supplied `dpi 144` / `cell 45 px`, which I did not
  independently measure. `border_rect.left/.width = screen_left/screen_width` confirms the band spans
  the full content width.
- **4** — verbatim correct, including that `detect_borders` gates only the border block at `:1004`
  and that the plain-hover hand comes from `:1362-1363` applied at `:1405`.
- **5** — verbatim correct in both trees (4 reads / 0 writes in `mouse.c`; tab-bar recovery at
  `:943-955`; `handle_window_title_bar_mouse` at `:929-937` is the same function with that block
  absent). The parenthetical "`window_title_bar_min_windows` defaults to 0, i.e. the bar is off" is
  also correct and non-obvious — `kitty/layout/base.py:412` reads `show_title_bar = force_show or
  (min_windows > 0 and len(visible_groups) >= min_windows)`, so `0` disables rather than
  always-enables. (Note §0 cites the recovery as `:941-953` and §4.1 as `:943-955`; the latter is
  right.)
- **6** — verbatim correct.
- **7** — verbatim correct: `definition.py:66-71` `ctype='bool'`; `to-c-generated.h:269-277` +
  `:1571`; `state.h:115-120` is the `bool` cluster the diff targets; `parse.py`, `types.py`,
  `to-c-generated.h` all carry `generated by gen-config.py DO NOT edit`; `gen/config.py` exists.
- **9** — verbatim correct. One refinement and one omission: the LEAVE fires **once per crossing**,
  not per motion event, because `set_currently_hovered_window` is gated on `if
  (global_state.mouse_hover_in_window != window_id)` (`:185`); and passing `0` also suppresses the
  `focus_follows_mouse` `on_cross` branch at `:199-207`, so hovering the band never focus-follows.
  Both argue for keeping the behaviour; add the second to the documentation line.

### Citation calibration

All cited sites exist and say what is claimed; several are off by one or two lines in a way that will
rot a re-check. `window_top`'s body is `mouse.c:259-262` (cited `:262-264` — that range is the *next*
function's opening). `update_scrollbar_hover_state` is `mouse.c:189` (cited `:187`).
`return border_rect.height;` is `shaders.c:887` (cited `:886`, which is `draw_rounded_rect`).
`if (!bar->buf) return 0;` is `shaders.c:844` (cited `:843`, the malloc). `window.py:1058-1062` is
cited for `tb_top`/`tb_bottom`, which are at `:1064-1065`. None of these changes a verdict.
