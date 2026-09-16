# Drag, drop targeting and the no-op-drag persistence requirement

Axis: what happens end-to-end when the user presses on an **overlay title band** and drags a pane to
another slot, and what it takes to satisfy requirement (c)'s second half — *"the title stays toggled on
if the title was dragged but placed in the same position (a no-op drag)."*

**Trees.** `~/kitty-482` = detached at v0.48.2 (`2cb1d95c3`) — **the build the operator runs**.
`~/kitty-dev` = master `1d67ecd47`. Every citation below names its tree. They diverge materially in
this exact code, and the brief's premises describe **master**, not the shipped build.

Status legend: **CONFIRMED** = read in the named tree at the named line, or a command + its output.
**UNMEASURED** = not executed (no kitty build was run; the brief forbids it).

---

## 0. Three corrections to the brief's premises, before anything else

### 0.1 `_pointer_in_title_bar_of` DOES NOT EXIST in v0.48.2 — CONFIRMED

```
$ cd ~/kitty-482 && grep -rn "_pointer_in_title_bar_of" .
(no output)
$ cd ~/kitty-dev && grep -n "_pointer_in_title_bar_of" kitty/tabs.py
2102:    def _pointer_in_title_bar_of(self, win: 'Window', y: int) -> bool:
2182:        if self._pointer_in_title_bar_of(dest_window, y):
2234:        if self._pointer_in_title_bar_of(dest_window, y):
```

In **v0.48.2 the test is INLINED TWICE**, with two *different* spellings, and neither is a helper:

* `~/kitty-482 kitty/tabs.py:1993-2003` — inside `on_window_drop_move` (the hover/highlight path):
  ```python
  if dest_window.show_title_bar:
      _, ch = cell_size_for_window(self.os_window_id)
      g = dest_window.geometry
      tb_top = g.top if opts.window_title_bar == 'top' else g.bottom - ch
      if tb_top <= rel_y < tb_top + ch:
          self._set_drag_target_window(dest_window.id, 5)   # quadrant 5 == SWAP
          return
  ```
* `~/kitty-482 kitty/tabs.py:2062-2075` — inside `on_window_drop` (the commit path), written as its own
  loop over `active_tab` rather than reusing `_find_window_at`, and guarded by
  `getattr(win, 'show_title_bar', False)`.

**Consequence for the change list:** a patch against v0.48.2 must edit **two** sites, not one, and the
honest first move is to *extract the master helper* (backport `_pointer_in_title_bar_of`) so there is one
predicate. Master already did exactly this refactor; we are patching the older shape.

### 0.2 v0.48.2 and master disagree on the COORDINATE SPACE of the hit test — CONFIRMED

`~/kitty-482 kitty/tabs.py:1928-1941` (`_find_window_at`):
```python
central = viewport_for_window(self.os_window_id)[0]
rel_x = x - central.left
rel_y = y - central.top
...
if g.left <= rel_x < g.right and g.top <= rel_y < g.bottom:
```

`~/kitty-dev kitty/tabs.py:2081-2100` (same function) replaces that with:
```python
# Window geometry is already relative to the OS window.
rel_x, rel_y = x, y
```
plus a `if not win.is_visible_in_layout: continue` guard that v0.48.2 **lacks**.

So master asserts, in a comment, that window geometry is in OS-window coordinates and that v0.48.2's
`- central.top` subtraction is **wrong** (it double-subtracts the tab-bar offset whenever the tab bar is
on top). Master's `_pointer_in_title_bar_of(win, y)` correspondingly takes a **raw** `y`, while
v0.48.2's inlined copies compare against `rel_y`.

**This is load-bearing for us.** Our band's hit rect must be expressed in whichever space the call site
actually uses, and on the shipped build those two call sites already disagree with master. Any patch
that copies master's helper verbatim into v0.48.2 **inherits master's coordinate convention into
v0.48.2's callers and will mis-target by the tab-bar height.** The change list below keeps v0.48.2's
`rel_*` convention and says so at each hunk. **UNMEASURED:** which convention is empirically right on
the operator's build — I did not run kitty. Resolve this with one print before shipping.

### 0.3 `show_title_bar = True` cannot be made "zero-row" — CONFIRMED, and it settles the design

`~/kitty-482 kitty/window.py:1050-1063` (`Window.set_geometry`):
```python
show_tb = self.show_title_bar and new_geometry.ynum > 1
if show_tb:
    render_ynum = new_geometry.ynum - 1
    ...
    render_top = new_geometry.top + cell_height
```
`show_title_bar` **is** the row-stealing flag: it is read in exactly one place and its only effect is
`render_ynum -= 1`, i.e. the PTY resize + SIGWINCH + content shift the operator has rejected.
Its only writer is `~/kitty-482 kitty/layout/base.py:408-415`:
```python
min_windows = get_options().window_title_bar_min_windows
visible_groups = tuple(all_windows.iter_all_layoutable_groups(only_visible=True))
force_show = all_windows.force_show_title_bars
show_title_bar = force_show or (min_windows > 0 and len(visible_groups) >= min_windows)
for wg in visible_groups:
    for w in wg.windows:
        w.show_title_bar = show_title_bar
```

⇒ **The design needs a SECOND, INDEPENDENT flag.** `show_title_bar` must stay **False** for every window
while the overlay band is up (that is what buys requirement (a)). Call the new one
`Window.overlay_title_bar: bool`. Every drag/drop predicate that today asks `show_title_bar` must be
changed to ask `show_title_bar or overlay_title_bar` — *not* to "set show_title_bar True but zero-row",
which is not expressible without changing `set_geometry`, and changing `set_geometry` re-opens (a).

---

## 1. Does `start_window_drag` still produce a correct thumbnail with `show_title_bar = False`? — YES

**Answer: yes, and it is MORE correct than today, not less. `start_window_drag` never reads
`show_title_bar`.** CONFIRMED.

`~/kitty-482 kitty/tabs.py:1883-1910`, the whole function, reads exactly: `get_window_being_dragged()[0]`,
`boss.window_id_map`, `opts.window_title_bar_min_windows` (only for the force-show loop, §3),
`w.title`, four colour options, `draw_single_line_of_text`, `start_drag_with_data`. No branch on
`show_title_bar`.

The thumbnail is assembled from **two independent sources**, and only one of them is geometry-dependent:

1. **`pixels`** — the pane screenshot, produced in C by `request_callback_with_thumbnail` →
   `thumbnail_callback` (`~/kitty-482 kitty/child-monitor.c:862-896`). The region is
   ```c
   region.left = w->render_data.geometry.left;   region.top = w->render_data.geometry.top;
   region.right = w->render_data.geometry.right; region.bottom = w->render_data.geometry.bottom;
   ```
   i.e. **`render_data.geometry`, the CELL-GRID rect**, which `Window.set_geometry`
   (`~/kitty-482 kitty/window.py:1056-1063`) shrinks by one cell when `show_title_bar` is True.
2. **`title_pixels`** — drawn fresh by `draw_single_line_of_text` (`~/kitty-482 kitty/glfw.c:3082`,
   the same CoreText path the proposed band uses) and **prepended**:
   `thumbnails = ((title_pixels + pixels, width, title_height + height),)` (`tabs.py:1903`).

So with `show_title_bar = False` the pane screenshot is the **full** window rect and the title strip is
still prepended. **Nothing breaks.** Today, with a native bar up, the screenshot *excludes* the bar row
(render geometry is shrunk) and the prepended strip supplies it; the composition is "strip + content".
With the band it is "strip + content **including the row the band covers**".

**One cosmetic residual, CONFIRMED by reading the render order.** `thumbnail_callback` is invoked from
`render_prepared_os_window` (`~/kitty-482 kitty/child-monitor.c:922-925`) **after** all `draw_cells`
calls for the frame. `render_a_bar` is called from `draw_hyperlink_target` / `draw_window_number`
(`~/kitty-482 kitty/shaders.c:911, 943`) inside `draw_cells`'s UI pass (`shaders.c:1381`), i.e. **before**
the screenshot is taken. A band drawn the same way will therefore be **in the framebuffer when the
screenshot is read**, so the drag thumbnail would show the band **twice**: once baked into row 1 of the
screenshot, once as the prepended strip.

Two one-line cures, pick one:
* **(A) Drop the prepended strip when the band is on.** In `start_window_drag`, skip the
  `draw_single_line_of_text` composition if `w.overlay_title_bar` — the screenshot already contains a
  correctly-rendered, correctly-coloured band. Cheapest, and it removes a CoreText render per drag.
* **(B) Shave the band row off the screenshot region.** Requires a C change in `thumbnail_callback` and
  a way to tell it the band height. Not worth it.

**Recommend (A).** It is strictly less work at drag time and the result is pixel-identical to what the
user sees.

**UNMEASURED:** I did not build kitty, so I have not seen a thumbnail. The claim "nothing breaks" is a
read of the data flow, which is complete and has no branch on the flag; the double-band claim is a read
of call order in one file and is the one I would verify first with a screenshot.

---

## 2. `_pointer_in_title_bar_of` — the exact change, and whether SWAP is what we want

### 2a. The exact change (v0.48.2 shape — TWO sites, not one)

First, **backport the helper** so the predicate exists once. Insert after `_find_window_at`
(`~/kitty-482 kitty/tabs.py:1941`), keeping **v0.48.2's `rel_y` convention** (§0.2):

```python
    def _pointer_in_title_bar_of(self, win: 'Window', rel_y: int) -> bool:
        """rel_y is relative to the CENTRAL region, matching v0.48.2's _find_window_at."""
        from .fast_data_types import cell_size_for_window
        _, ch = cell_size_for_window(self.os_window_id)
        g = win.geometry
        opts = get_options()
        if win.show_title_bar:
            # Native bar: it OWNS a cell row, which set_geometry already removed from the
            # render rect. Its band is that row.
            tb_top = g.top if opts.window_title_bar == 'top' else g.bottom - ch
            return tb_top <= rel_y < tb_top + ch
        if getattr(win, 'overlay_title_bar', False):
            # Overlay band: it OVERLAPS content row 1 (or the last row). Same rect arithmetic,
            # but g.top IS content row 1 because set_geometry did not shrink anything.
            band_h = ch + 2 + 2 * self._band_border_px()   # must equal render_a_bar's border_rect.height
            tb_top = g.top if opts.window_title_bar == 'top' else g.bottom - band_h
            return tb_top <= rel_y < tb_top + band_h
        return False
```

`band_h` must be the **same arithmetic `render_a_bar` uses**, or the hit rect and the painted rect
disagree and the bar becomes grabbable a few pixels off. From `~/kitty-482 kitty/shaders.c:838-873`:

```c
unsigned border_width = (unsigned)ceil(thickness_as_float(ui->os_window, 1));
unsigned bar_height = ui->cell_height + 2;
Viewport border_rect = { .height = bar_height + 2 * border_width, ... };
return border_rect.height;
```

⇒ **`band_h = cell_height + 2 + 2 * ceil(thickness_as_float(os_window, 1))`.**
`thickness_as_float` is **not** `window_border_width` — it is `box_drawing_scale[level] * dpi / 72`
(`~/kitty-482 kitty/shaders.c:304-310`), and `box_drawing_scale` defaults to
`(0.001, 1.0, 1.5, 2.0)` (`~/kitty-482 kitty/options/types.py`), which the operator does not override
(`grep -n box_drawing_scale config/kitty.conf` → no match). So level 1 = 1.0pt, at dpi 144 that is
`ceil(1.0*144/72) = 2px`, and `band_h = 45 + 2 + 2*2 = 51px`, i.e. **6px taller than a cell** —
so a hit rect of exactly one cell would be wrong by 6px and the top 6px of the band would fall through
to the terminal. Expose the number from C rather than recomputing it in Python: add a
`window_title_band_height(os_window_id)` to `fast_data_types` returning `border_rect.height` so the two
can never drift. **This is the single most likely source of a "the bar is grabbable but only sometimes"
bug, and it is arithmetic, not luck.** CONFIRMED from `shaders.c:838-873`.

Then replace both inlined copies:

* **Hunk 2 — `~/kitty-482 kitty/tabs.py:1993-2003`** (hover/highlight, `on_window_drop_move`). Replace
  the ten lines from `if dest_window.show_title_bar:` through the `return` with:
  ```python
  if self._pointer_in_title_bar_of(dest_window, rel_y):
      self._set_drag_target_window(dest_window.id, 5)   # 5 == swap highlight
      return
  ```
  (`rel_y` is already in scope at `tabs.py:1992`.) This also deletes the now-dead
  `cell_size_for_window` import and `opts` read at 1995-1998.

* **Hunk 3 — `~/kitty-482 kitty/tabs.py:2062-2075`** (commit, `on_window_drop`). Replace the bespoke
  loop with the shared pair:
  ```python
  dest_window = self._find_window_at(x, y)
  dest_in_title_bar = dest_window is not None and self._pointer_in_title_bar_of(dest_window, rel_y)
  ```
  This is **not cosmetic**: v0.48.2's loop at 2066-2076 lacks `_find_window_at`'s
  `central.left <= x < central.right` bounds check and lacks master's `is_visible_in_layout` guard, so
  in a Stack layout it can pick an *overlaid* window by iteration order. Master fixed this
  (`~/kitty-dev kitty/tabs.py:2090-2093`). Backport the guard with the helper.

### 2b. Is SWAP-on-title-drop the behaviour we want? — **Yes for the title band. NO as the only behaviour.**

The two outcomes are, in v0.48.2:
* **title-bar drop ⇒ SWAP** — `src_tab.swap_windows(w, dest_window)` (`tabs.py:2085-2086`), which is
  `move_window_to_group` + `relayout` (`tabs.py:1770-1776`). Exchanges the two panes' slots. Geometry of
  every *other* pane is untouched.
* **body drop ⇒ DIRECTIONAL INSERT** — `boss._insert_window_in_direction(w, dest_window, direction)`
  (`tabs.py:2100`), which **splits** the destination, changing the tree.

The operator's words are *"draggable to re-position among split panes"*. **Re-position** is swap, not
split: the pane count must not change and the other panes must not move. So the band's primary verb is
right. Keeping the body-drop insert is also right — it is how you *re-shape* the layout — and it is
reachable because the band only covers one row.

**The asymmetry to be aware of:** with the band, the SWAP target is a **51px strip at the top of each
pane**, whereas today with native bars it is a full cell row that is visually distinct. The user has to
aim at a strip that sits over content. Mitigation already present in the code: the hover path sets
quadrant 5, and `_set_drag_target_window` (`tabs.py:1943-1964`) draws a **full-window** drag overlay for
quadrant 5 via `set_window_drag_overlay(..., 5)`, so the feedback is the whole pane lighting up, not the
strip. That is good feedback and needs no change.

**One thing DOES need a change for parity:** `_set_drag_target_window` at `tabs.py:1958-1960` also does
`new_w.is_drag_target = True; new_w.update_title_bar(is_active=True)` to tint the *native* bar.
`update_title_bar` returns immediately when `_title_bar_screen is None`
(`~/kitty-482 kitty/window.py:1151-1153`), which is exactly the overlay case — so **the band will not
tint**. Harmless (no crash, CONFIRMED by the early return), but it loses an affordance. The fix is in
the band's own renderer: read `window->is_drag_target` in the band's `render_a_bar` call and pick the
active colours, the same way `update_title_bar` folds `self.is_drag_target` into `is_active`
(`window.py:1168`).

### 2c. Quadrant 5 and quadrant 6 become visually IDENTICAL with a band — CONFIRMED

`~/kitty-482 kitty/shaders.c:795-820` `draw_drag_preview_overlay`:
```c
case 5: break;   // full window + title bar highlight (title bar hover)
case 6: break;   // full window, no title bar highlight (body hover)
```
Both fall through to the same full-window tint; the **only** thing distinguishing them is the title-bar
highlight, which is applied in Python by `_set_drag_target_window` → `update_title_bar(is_active=True)`
(`~/kitty-482 kitty/tabs.py:1958-1960`) and which **returns immediately when `_title_bar_screen is
None`** (`~/kitty-482 kitty/window.py:1151-1153`) — the overlay case.

⇒ With the band, a **swap** preview (quadrant 5) and a **full-window drop** preview (quadrant 6, used by
layouts whose `drag_overlay_mode` is `full`) look the same. The user cannot tell which verb they are
about to commit. The fix is the same one as §2b's last paragraph — make the band read
`window->is_drag_target` and paint its active colours — and it is now **two** reasons for one small
change, not one.

---

## 3. `force_show_title_bars` with an option-driven band — and the no-op-drag guarantee

### 3a. The headline: an OPTION-driven band satisfies (c)'s second half BY CONSTRUCTION

**Nothing in the press → motion → drop path writes the band's state, so a no-op drag cannot turn it
off.** That is the whole answer, and it is a property of *where the state lives*, not of any code we add.

Contrast the two existing mechanisms:

| Mechanism | State lives in | Cleared by a drop? |
|---|---|---|
| ⌘⌥B native bars (`window_title_bar_min_windows 1`) | a global **option** | **No** — `start_window_drag` skips the force loop (`min_w > 0 and visible >= min_w` is True, `tabs.py:1893-1897`), so `_clear_force_show_title_bars` finds `force_show_title_bars` False and does nothing (`tabs.py:1923-1926`) |
| bare `toggle_window_title_bars` | `Tab.force_show_title_bars`, a **per-tab bool** (`tabs.py:184`) | **YES** — `_clear_force_show_title_bars` sets it False and relayouts, on every drop (`tabs.py:1918-1926`) and again in `boss.on_drag_source_finished` (`~/kitty-482 kitty/boss.py:2035-2040`) |

The brief's "min_windows-held bars are immune to `_clear_force_show_title_bars`" is **CONFIRMED**, and the
reason is the table above: the clear function only touches tabs whose bool is True. **Put the band's
state anywhere other than `Tab.force_show_title_bars` and the requirement is met for free.**

### 3b. The ONE change that is actually required — CONFIRMED, and it is not optional

`~/kitty-482 kitty/tabs.py:1890-1897`:
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

**On the operator's live config this fires on every tab of every OS window at every drag start.**
`window_title_bar_min_windows` is `0` (`config/kitty.conf:1245`), so `min_w > 0` is False, the
conjunction is False, and `not False` is **True** for every tab. `force_show_title_bars = True` →
`relayout()` → `layout/base.py:411-412` sets `w.show_title_bar = True` → `window.py:1059`
`render_ynum = ynum - 1` → **one row stolen from every pane in all 5 OS windows / 9 panes, plus a
SIGWINCH to each of the 9 live Claude Code children** — then reverted on drop, for a second storm.

**Hunk 4 — `~/kitty-482 kitty/tabs.py:1890-1897`**, guard the loop:
```python
    min_w = opts.window_title_bar_min_windows
    band_is_up = opts.window_title_bar_overlay          # the new option
    for tm in boss.all_tab_managers:
        tm.mark_tab_bar_dirty()
        if band_is_up:
            continue        # the band is already a drop affordance on every pane; do not steal rows
        for t in tm:
            ...unchanged...
```
`mark_tab_bar_dirty()` is kept — it is unrelated to rows and the tab bar still needs a repaint for the
drag-target `+`.

### 3c. `_clear_force_show_title_bars` — NO CHANGE NEEDED

`~/kitty-482 kitty/tabs.py:1918-1926`. With hunk 4 in place no tab ever has the flag set, so the loop
body never runs and never relayouts. Its other two statements —
`tm._set_drag_target_window(0)` and `tm._set_drag_target_tab(0)` — **must be kept**: they are what clears
the drop highlight and the tab-bar `+`. Same for the duplicate loop in
`~/kitty-482 kitty/boss.py:2035-2040`: leave it, it self-no-ops.

**So the minimal set for Q3 is exactly ONE hunk.** Everything else about `force_show_title_bars` becomes
dead weight for the band path and correctly stays alive for the native path.

### 3d. 🚨 The residual this analysis found, which is NOT about the band and IS a content shift

`tab_bar_should_be_visible` (`~/kitty-482 kitty/tabs.py:1287-1289`):
```python
if self.tab_being_dropped is not None or self.window_drag_over_me:
    return True  # keep tab bar visible in the dest
```
and `on_window_drop_move` (`tabs.py:1976-1979`):
```python
if not self.window_drag_over_me:
    self.window_drag_over_me = True
    if not self.tab_bar_hidden:
        self.layout_tab_bar()
        self.resize(only_tabs=True)
```

**`resize(only_tabs=True)` still relayouts every window.** `~/kitty-482 kitty/tabs.py:1342-1347`:
```python
def resize(self, only_tabs: bool = False) -> None:
    if not only_tabs:
        if not self.tab_bar_hidden:
            self.layout_tab_bar()
    for tab in self.tabs:
        tab.relayout()        # <- runs unconditionally; only_tabs only skips layout_tab_bar
```
The flag's name says the opposite of what it does.

**Measured, this machine, read-only against the live instance:**
```
$ kitty @ --to unix:/tmp/kitty-597 ls   (summarised)
OSWindow 4  tabs: 1   tab 4  windows: 2  layout splits
OSWindow 5  tabs: 1   tab 5  windows: 3  layout splits
```
Every OS window has **one** tab. `tab_bar_min_tabs` is **not set** in `config/kitty.conf` (grep for
`^tab_bar_min_tabs` → no match) and its default is `2`
(`~/kitty-482 kitty/options/definition.py:2142`, `kitty/options/types.py: tab_bar_min_tabs: int = 2`),
so **the tab bar is currently hidden on every OS window**, and `tab_bar_style` is unset, so
`tab_bar_hidden` is False.

⇒ On drag start, `window_drag_over_me` flips the tab bar **visible**, the central region shrinks by one
tab-bar height, and every pane relayouts smaller — **a content shift during every drag, reverted on
drop.** It is upstream behaviour, it predates us, and it is invisible today only because window drag is
effectively unreachable on this config. **The moment the band makes drag easy, this becomes the
user-visible cost of every drag.** CONFIRMED by reading; **UNMEASURED** as pixels (no build run).

Three dispositions, operator's call — I am not choosing one for them:
* **(i) Accept it.** It is transient and upstream. Cost: two reflows of 9 live agent sessions per drag.
* **(ii) `tab_bar_min_tabs 1`.** Removes the flip by making the bar permanent. Costs a permanent row —
  the same class of thing already rejected twice.
* **(iii) Suppress the bump for window drags when the source and destination OS window are the same and
  the layout has >1 pane** — i.e. when the user is re-positioning inside one window and provably does
  not need the `+`. One line at `tabs.py:1976`. Narrow, and it keeps the `+` for cross-window detach.

---

## 4. The double-press rename prompt — YES it fires from our band, and it is worse from a band

**Does it fire?** Yes, unconditionally, if the band's mouse events are routed through
`handle_window_title_bar_mouse` — which they must be, because that function *is* the drag arming
(§ state machine). CONFIRMED at `~/kitty-482 kitty/tabs.py:1875-1881`:

```python
dragged_window_id, drag_started = get_window_being_dragged()[:2]
set_window_being_dragged()
if not drag_started and self.recent_title_bar_mouse_events.click_count() == 2:
    self.recent_title_bar_mouse_events.clear()
    if (w := boss.window_id_map.get(window_id)) is not None:
        w.set_window_title()
```
`Window.set_window_title()` with no argument calls `get_boss().get_line(...)` — a **modal line-editor
overlay window** titled *"Rename window"* (`~/kitty-482 kitty/window.py`, `Window.set_window_title` → `get_boss().get_line(...)`). Nothing in that path
consults `show_title_bar`; the only gate is *"the drag never started"*, i.e. the pointer moved less than
`drag_threshold` (default **5** px, `kitty/options/types.py`) between press and release.

The double-press test is `MouseEvents.click_count()` (`~/kitty-482 kitty/tabs.py:113-119`): two
press/release pairs on the **same `object_id`** (the window id), each within `click_interval`, each
moving <5px, with the two inner events <2px apart.

**Should it be suppressed? My recommendation: yes, for the band, and NOT because rename is bad.**

The argument is about what the rect *is*:
* A **native** title bar is a dedicated cell row. A double-click there cannot have been aimed at
  anything else — there is nothing else there. Rename is a good default.
* The **band** sits **over content row 1** and is 51px tall (§2a) against a 45px cell, so it also
  covers ~6px of content row 2. A double-click in the terminal is the universal *select-a-word* gesture.
  With the band up, every double-click on the top line of a pane silently opens a modal rename prompt
  instead of selecting a word. Across 9 live agent panes that is a recurring surprise, and the modal
  **steals focus and keyboard input** until dismissed.

The band's whole premise is that it does not cost a row; the price of that is that its rect is
double-booked with content. Actions that are safe on a dedicated row are not automatically safe on a
double-booked one.

**Hunk 5 — `~/kitty-482 kitty/tabs.py:1877`**, one condition:
```python
        if not drag_started and self.recent_title_bar_mouse_events.click_count() == 2 \
                and not getattr(boss.window_id_map.get(window_id), 'overlay_title_bar', False):
```
Or, if the operator wants rename kept, gate it behind a new option
`window_title_bar_overlay_double_click_renames no` (default `no`) so the behaviour is recoverable
without a rebuild. Rename remains reachable from `set_window_title` as a keybinding and from remote
control either way — **nothing is lost, only a gesture is moved.**

**A second, larger consequence of the same double-booking, stated so it is not discovered later:**
the band swallows **all** left-button input in its rect, not just double-clicks. `mouse_region` returns
`in_title_bar = true` and `~/kitty-482 kitty/mouse.c:1354-1368` then routes the event to
`handle_window_title_bar_mouse` and **never** to `handle_event` → the terminal. It also calls
`set_currently_hovered_window(... r.in_title_bar ? 0 : w->id ...)` at `mouse.c:1355`, so mouse-tracking
applications stop receiving hover in that strip. **Text selection starting on row 1 is lost while the
band is up.** That is inherent to "a bar that costs no row", not a defect of this design, and it is the
honest price to put in front of the operator beside requirement (a).

---

## 5. The no-op drop path, traced line by line — CONFIRMED, no swap, no band disturbance

Pointer is released over the **same pane it was picked up from**, inside kitty.

1. **`~/kitty-482 kitty/boss.py:1981` `Boss.on_drop`** — the mime key
   `application/net.kovidgoyal.kitty-window-<pid>` is present ⇒ `tm.on_window_drop(x, y, window_id)`,
   then `set_window_being_dragged()` (clears), then
   `for q in self.all_tab_managers: q.on_window_drop_move()` with **default args**.
2. **`~/kitty-482 kitty/tabs.py:2026` `TabManager.on_window_drop`**
   * `self.window_drag_over_me = True` (2034)
   * `self._clear_force_show_title_bars()` (2035) — with **hunk 4** applied, no tab has the flag, so this
     does `_set_drag_target_window(0)` + `_set_drag_target_tab(0)` and **no relayout**.
   * `set_window_being_dragged()` (2039), `mark_tab_bar_dirty()` (2040)
   * not in tab bar (2045-2052); **is** in central (2055-2057)
   * `rel_x, rel_y` computed (2059-2060)
   * the destination loop (2066-2076) finds `dest_window` = the dragged window itself
   * **2078-2082:**
     ```python
     if dest_window is None or dest_window.id == window_id:
         if active_tab is not w.tabref():
             boss._move_window_to(w, target_tab_id=active_tab.id)
         return
     ```
     Same tab ⇒ the inner `if` is False ⇒ **bare `return`.**

   ⇒ **`swap_windows` is never reached. `_insert_window_in_direction` is never reached.
   `relayout()` is never called from this function. CONFIRMED.**
   Note this branch fires on `dest_window.id == window_id` **before** the title-bar test, so *"dropped
   on my own band"* and *"dropped on my own body"* are the same no-op. That is the behaviour we want and
   it needs no change.
3. **Back in `Boss.on_drop`:** `q.on_window_drop_move()` for every tab manager, `is_dest=False` ⇒
   `~/kitty-482 kitty/tabs.py:1967-1974`: clears both drag targets, then
   ```python
   if self.window_drag_over_me:
       self.window_drag_over_me = False
       if not self.tab_bar_hidden:
           self.layout_tab_bar(); self.resize(only_tabs=True)
   ```
   **This IS a relayout of every tab** (§3d — `resize(only_tabs=True)` still calls `tab.relayout()`).
   It is the *un-doing* of the tab-bar bump taken at drag start, so it returns the geometry to exactly
   where it started. **It cannot turn the band off** (the band's state is an option, not per-tab
   geometry) and it restores the pre-drag row count — but it is the second of the two reflows in §3d.
4. **`~/kitty-482 kitty/boss.py:2027` `on_drag_source_finished`** runs at some point around this.
   Its whole body is guarded by `if get_window_being_dragged()[0] == window_id` (2034). `on_drop`
   already cleared that to 0, so on the in-kitty path **the entire body is skipped** — including the
   `_move_window_to(window, target_os_window_id='new')` detach at boss.py:2051. CONFIRMED.

   🚨 **UNMEASURED ORDERING HAZARD, and it is the one I would test first.** The comment at
   `~/kitty-482 kitty/tabs.py:2029-2033` states in kitty's own words that *"on_drag_source_finished can
   run before the on_drop data transfer completes"*. If that ordering occurs on macOS, then at
   `boss.py:2034` the dragged id is **still set**, `was_dropped` is true, `was_canceled` false, and
   total windows > 1 ⇒ **the pane is detached into a NEW OS WINDOW on what the user performed as a
   no-op drag.** I did not build or run kitty, so I cannot say which ordering macOS produces. kitty
   defends against the *symptom* of this race (the tab-bar visibility half) and not against this branch,
   which suggests the ordering does not normally occur — but *"suggests"* is not a measurement.
   **Test: drag a pane a few px and drop it on itself; if an OS window appears, this is live.**

**Verdict on Q5: on the no-op path nothing relayouts on account of the band, no swap runs, and the band
is untouched.** The only relayout is the tab-bar-visibility un-bump, which is symmetric with the bump at
drag start and is the §3d residual, not a band problem.

---

## 6. The hunk without which none of the above runs: the C hit test

**CONFIRMED, and it matches the brief:** `~/kitty-482 kitty/mouse.c:1067-1082`
```c
for (unsigned int i = 0; i < t->num_windows; i++) {
    Window *win = t->windows + i;
    if (contains_mouse(win) && win->render_data.screen) {          // <- tested FIRST
        ans.window_idx = i; ans.window = win; break;
    } else if (detect_title_bar && win->visible) {                  // <- unreachable for our band
        const WindowRenderData *trd = &win->window_title_render_data;
        ...
    }
}
```
`contains_mouse` (`mouse.c:270-273`) is `window_left(w) <= x < window_right(w) && window_top(w) <= y <
window_bottom(w)`, and the band is inside that rect, so the `else if` is dead for it. Without a C change
there is **no hand cursor and no drag**, exactly as the brief states.

**Hunk 1 (C) — `~/kitty-482 kitty/mouse.c:1067`**, add an arm *before* `contains_mouse`:
```c
    for (unsigned int i = 0; i < t->num_windows; i++) {
        Window *win = t->windows + i;
        if (detect_title_bar && win->visible && win->overlay_title_bar_height &&
                w->mouse_x >= win->render_data.geometry.left && w->mouse_x < win->render_data.geometry.right &&
                w->mouse_y >= win->render_data.geometry.top &&
                w->mouse_y < win->render_data.geometry.top + win->overlay_title_bar_height) {
            ans.in_title_bar = true; ans.window = win; ans.window_idx = i;
            break;
        }
        if (contains_mouse(win) && win->render_data.screen) { ...unchanged... }
        else if (...) { ...unchanged native arm... }
    }
```

Everything downstream is then **already written**: `~/kitty-482 kitty/mouse.c:1354-1368` sets
`mouse_cursor_shape = POINTER_POINTER` (the hand — requirement (c) first half, free) and calls
`handle_window_title_bar_mouse`, which `mouse.c:930-936` forwards to the Python
`TabManager.handle_window_title_bar_mouse`. **No other C change is needed for the drag.**

🚨 **Use `render_data.geometry.top`, NOT `window_top(w)`.** `window_top` is
`render_data.geometry.top - w->padding.top` (`mouse.c:260-262`) while `render_a_bar` draws at
`ui->screen_top`, the **cell-grid** top. They coincide today only because the operator's
`window_padding_width 0 5 0 5` has top padding 0 (`config/kitty.conf:1109`). Key the hit rect on the
grid, or the band becomes mis-hit by exactly `padding.top` for anyone who sets one.

### The field that makes the hit rect and the painted rect unable to drift

`render_a_bar` **already returns its own height** — `return border_rect.height;`
(`~/kitty-482 kitty/shaders.c:887`), where
`border_rect.height = cell_height + 2 + 2*ceil(thickness_as_float(os_window, 1))`
(`shaders.c:838-871`), where `thickness_as_float` reads **`box_drawing_scale[1]`** (default 1.0pt,
not overridden here), **not** `window_border_width` (`shaders.c:304-310`). At dpi 144 that is
**45 + 2 + 2·2 = 51px**, i.e. **6px taller than one cell** — so any hit rect written as "one cell" is
wrong by 6px at the top of every pane.

⇒ Add `unsigned overlay_title_bar_height;` to `struct Window` (`~/kitty-482 kitty/state.h:262-276`,
beside `WindowBarData title_bar_data`), **write it from the band's draw call with `render_a_bar`'s
return value, and zero it when the band is not drawn.** Then:
* the C hit test reads that field (hunk 1) — cannot drift from the paint;
* `_pointer_in_title_bar_of` reads it through a one-line `fast_data_types` getter — cannot drift either,
  and §2a's hand-recomputation of the formula is deleted;
* `overlay_title_bar_height != 0` **is** the "band is up" predicate, so there is no second source of
  truth about visibility.

This is the single design decision that turns "the bar is grabbable, but sometimes a few pixels off"
from a likely bug into an unrepresentable state.

---

## 7. The state machine: press → motion → drop

States are `global_state.window_being_dragged` (`~/kitty-482 kitty/state.h:531-534`:
`{id, drag_started, x, y}`), which is the **only** drag state, and it is global, not per-window.

```
                         ┌──────────────────────────────────────────┐
     IDLE  ──press──────►│ ARMED   id=W, drag_started=False, (x,y)   │
       ▲                 └──────────────────────────────────────────┘
       │                      │                        │
       │        release,      │ motion, dist² >        │ motion, dist² ≤ threshold²
       │        no 2nd click  │ drag_threshold² (=25)  │  (stay ARMED, nothing sent)
       │                      ▼                        │
       │                 ┌──────────────────────────────────────────┐
       │                 │ DRAGGING  drag_started=True, OS DnD live  │
       │                 └──────────────────────────────────────────┘
       │                      │                    │
       │   release +          │ drop inside kitty  │ drop outside / cancelled
       └── 2nd click ⇒ RENAME │                    │
                              ▼                    ▼
                    on_drop → on_window_drop   on_drag_source_finished
                    (SWAP | INSERT | NO-OP)    (detach to new OS window | nothing)
```

**PRESS** — `mouse.c:1362` matches `r.in_title_bar && r.window` (hunk 1 made the band reach this),
sets the hand cursor, calls `handle_window_title_bar_mouse`. Python
(`~/kitty-482 kitty/tabs.py:1864-1874`): records the event, activates the window
(`boss.set_active_window`), and `set_window_being_dragged(window_id, False, x, y)` ⇒ **ARMED**.
*Nothing is drawn, nothing relayouts, no row moves.*

**MOTION** — `mouse.c:933` forwards motion **only** while `window_being_dragged.id` is set (`button > -1
|| global_state.window_being_dragged.id`), so an un-armed hover costs nothing. Python
(`tabs.py:1855-1863`) compares `dist²` to `drag_threshold²` (default 5 ⇒ 25 px²). Below it: **stay
ARMED, no work**. Above it: `set_window_being_dragged(id, True, ...)` ⇒ **DRAGGING**, and
`request_callback_with_thumbnail("start_window_drag", ...)` marks the OS window dirty
(`~/kitty-482 kitty/state.c:1777-1791`) so the **next frame** screenshots the pane and calls back into
`start_window_drag` (§1).

**start_window_drag** (`tabs.py:1883-1910`): force-show loop — **suppressed by hunk 4** — then composes
`title_pixels + pixels` and hands it to `start_drag_with_data`. Failure path (`OSError`) clears the drag
and calls `_clear_force_show_title_bars`, which with hunk 4 is a clean no-op.

**DRAG MOTION** — `boss.on_drop_move` → `q.on_window_drop_move(window_id, is_dest, x, y)` for every tab
manager (`~/kitty-482 kitty/boss.py:1976-1979`). First entry into a manager sets `window_drag_over_me`
and **relayouts** (§3d). Then: over the tab bar ⇒ highlight a tab; over a pane's band ⇒
`_set_drag_target_window(id, 5)` = **swap** highlight (hunk 2 is what makes the band count here); over a
pane's body ⇒ quadrant 1-4 = **directional insert** preview; over itself ⇒ cleared.

**DROP, three terminal outcomes:**
* **on another pane's band** ⇒ `swap_windows` (`tabs.py:2085-2086`) — pane count unchanged, only the two
  slots exchange. *This is "re-position among split panes".*
* **on another pane's body** ⇒ `_insert_window_in_direction` (`tabs.py:2100`) — splits the destination.
* **on itself (the NO-OP)** ⇒ bare `return` at `tabs.py:2078-2082`, reached **before** the title-bar
  test. No swap, no insert, no relayout from this function. **The band is not touched by any of the
  three**, because its state is an option and none of them writes an option.

**RELEASE WITHOUT DRAG** — `tabs.py:1875-1881`: clears the drag state; if this was the **second** click
within `click_interval`, <5px, same window ⇒ `w.set_window_title()` ⇒ **modal rename prompt** (§4, hunk
5 suppresses it for the band).

---

## 8. Consolidated change list

| # | Tree / file:line (v0.48.2) | Change | Why it is required |
|---|---|---|---|
| **1** | `kitty/mouse.c:1067` | New arm **before** `contains_mouse`, keyed on `win->overlay_title_bar_height` and `render_data.geometry.top` | Without it the band is inside `contains_mouse` and the title-bar arm is unreachable ⇒ **no hand cursor, no drag**. The only mandatory C change. |
| **1b** | `kitty/state.h:262-276` + the band's draw site | Add `unsigned overlay_title_bar_height;` to `struct Window`; store `render_a_bar`'s **return value**; zero it when not drawn | Hit rect and painted rect become the same number by construction (51px, not 45px). Also the single "band is up" predicate. |
| **2** | `kitty/tabs.py:1941` (new) | Backport `_pointer_in_title_bar_of` from `~/kitty-dev kitty/tabs.py:2102`, keeping **v0.48.2's `rel_y`** convention, extended with the `overlay_title_bar` arm | v0.48.2 has **no** such helper — the test is inlined twice, differently (§0.1) |
| **3** | `kitty/tabs.py:1993-2003` | Replace the inlined hover test with the helper | Hover highlight must recognise the band ⇒ quadrant 5 (swap) preview |
| **4** | `kitty/tabs.py:2062-2075` | Replace the bespoke loop with `_find_window_at` + the helper | Drop commit must recognise the band; **also fixes** the missing bounds check and the missing `is_visible_in_layout` guard that master added (`~/kitty-dev kitty/tabs.py:2090-2093`) |
| **5** | `kitty/tabs.py:1890-1897` | `if band_is_up: continue` before the force-show loop | **The only change Q3 actually needs.** Otherwise every drag steals a row from all 9 panes in all 5 OS windows and SIGWINCHes 9 live agent sessions, twice |
| **6** | `kitty/tabs.py:1877` | `and not ...overlay_title_bar` on the double-click condition | Stops an accidental modal rename on every double-click over content row 1 (§4). Optional but recommended |
| **7** | `kitty/tabs.py:1903` | Skip the prepended `draw_single_line_of_text` strip when the band is up | The screenshot already contains the band ⇒ otherwise the thumbnail shows it twice (§1) |
| — | `_clear_force_show_title_bars`, `boss.on_drag_source_finished`'s clear loop, `toggle_window_title_bars` | **NO CHANGE** | They key on `Tab.force_show_title_bars`, which hunk 5 keeps permanently False for the band path; they self-no-op |

**Requirement (c) second half — "stays toggled on after a no-op drag" — needs ZERO dedicated code.**
It falls out of hunk 5 plus the choice to store the band's state in an option rather than in
`Tab.force_show_title_bars` (§3a). There is nothing to test for, nothing to restore, and no
"re-assert after drop" timer.

## 9. What I did not measure

* **No kitty build was run** (the brief forbids it). Every claim is a read of named source, or a
  read-only `kitty @ ls` against pid 597.
* **The `on_drag_source_finished` / `on_drop` ordering on macOS (§5 step 4)** — if the source-finished
  callback wins the race, a no-op drag detaches the pane into a new OS window. kitty's own comment says
  the race exists. **Highest-value single test.**
* **Which coordinate convention is right on v0.48.2 (§0.2)** — master calls v0.48.2's `- central.top`
  subtraction wrong in a comment. One `print` of `central.top` and `win.geometry.top` settles it.
* **51px vs 45px band height** — read from `shaders.c:839-871`; not observed as pixels.
* **The §3d tab-bar bump as a visible shift** — read from the code + a live `ls` showing 1 tab per OS
  window and `tab_bar_min_tabs` defaulting to 2; not observed as pixels.

---

## 10. Which option should hold the band's state

`window_title_bar` is `typing.Literal['top', 'bottom']` in v0.48.2
(`~/kitty-482 kitty/options/types.py:43, 721`), so it is a **position**, not an on/off. Two shapes work;
they differ in what a `load-config` costs.

* **(A) A new boolean `window_title_bar_overlay yes|no`** (default `no`). `window_title_bar` keeps
  meaning *top/bottom* and the band reuses it for its edge — which is why `_pointer_in_title_bar_of`
  (§2a) branches on `opts.window_title_bar` in both arms. ⌘⇧B becomes a `load-config` of a two-line
  drop-in, exactly like today's ⌘⌥B pair, **but with no `window_padding_width` compensation needed**
  because the band steals no row. **Recommended.**
* **(B) Extend the Literal to `'top' | 'bottom' | 'overlay-top' | 'overlay-bottom'`.** One option
  instead of two, but every existing `opts.window_title_bar == 'top'` comparison in the tree becomes a
  latent bug — there are such comparisons in both inlined hit tests this patch is already rewriting
  (`tabs.py:1997`, `tabs.py:2069`), and a `grep` would be needed for the rest.

Either way the state is a **global option**, which is the property §3a depends on: a drop cannot write
it, so the no-op-drag requirement is satisfied without a single line of code aimed at it.

**One caveat on the toggle itself, not on the drag:** `load-config` runs `apply_options` →
`tab.relayout()` everywhere. With the band that relayout changes **no geometry** (nothing sets
`show_title_bar`, nothing changes padding), so it is a repaint, not a reflow, and requirement (a) holds
through the toggle by the same argument that makes it hold through a drag. **UNMEASURED** — worth one
`kitty @ ls` row-count before and after, which is the same instrument
`config/kitty-title-on.conf` already used for the ⌘⌥B pair.

---

## ADVERSARIAL VERIFICATION

Adversarial pass, 2026-09-16. Every `file:line` below was re-opened in the tree it names. No kitty
build was run (brief forbids it); the one live instrument used was read-only
`kitty @ --to unix:/tmp/kitty-597 ls`. **Method note:** where the report marked something UNMEASURED I
first asked whether it was *statically decidable* rather than reaching for the experiment it prescribed.
Two of the three "settle this by measurement first" items turned out to be decidable from source, and one
of them prescribed a risky live drag on a terminal carrying the operator's agent sessions.

**Net: 11 of 15 claims upheld, 1 refuted outright, 3 materially corrected, 2 new risks found — one of
them created by the report's own flagship recommendation (1b).** The design survives. Three of the seven
hunks need their wording changed, and the recommendation's ordered pre-work list (a)/(b) should be
deleted rather than performed.

### OVERTURNED

#### O1. Claim 15 (the `on_drag_source_finished` race) is REFUTED — and step (a) must not be run

The claim: *"if on_drag_source_finished wins the race against on_drop, a no-op drag detaches the pane
into a NEW OS window … the one defect that would ship undetected."* The recommendation makes settling it
by live experiment the **first** thing to do: *"drag a pane a few px and drop it on itself — if an OS
window appears, the race is live."*

**The detach is unreachable for any in-kitty drop, independent of callback ordering.** Two separate
guards, either sufficient:

**(i) C already forces `was_dropped` False for a drop landing on one of our own OS windows.** The value
Python receives is not `ds.was_dropped` — `~/kitty-482 kitty/glfw.c:958`:

```c
call_boss(on_drag_source_finished, "OOsiOO", \
    ds.was_dropped && !global_state.drop_dest.os_window_id ? Py_True : Py_False, ...
```

`drop_dest.os_window_id` is set to the destination OS window at `glfw.c:874` in the `GLFW_DROP_DROP` arm,
and is cleared **only** by `GLFW_DROP_LEAVE` (`glfw.c:855`), which comes from `draggingExited:`
(`~/kitty-482 glfw/cocoa_window.m:1643-1649`) — and AppKit does not send `draggingExited:` to the view
that handled the drop in `performDragOperation:`. So for an in-kitty drop the Python-visible
`was_dropped` is **False**, `boss.py:2044`'s `if was_dropped and not was_canceled:` is False, and the
detach at `boss.py:2050` is unreachable. This guard does not care which callback runs first.

**(ii) For a pane drag, `Boss.on_drop` is called SYNCHRONOUSLY, so the clear happens first anyway.**
`start_drag_with_data` calls `free_drag_source()` (`glfw.c:3242`, which zeroes the struct) and never sets
`drag_source.from_window` — contrast the client-drag path which does (`glfw.c:3199`). So in
`drop_dest_callback`'s `GLFW_DROP_DROP` arm the self-drag fast path fires
(`glfw.c:880-886`): `ev->from_self && !global_state.drag_source.from_window` ⇒ kitty uses its **own**
`drag_source.drag_data` and invokes `WINDOW_CALLBACK(on_drop, …)` inline, **with no pasteboard round trip
and no `send_data_available_event_on_next_event_loop_tick`** (`glfw/cocoa_window.m:1659`, the async step).
`on_window_drop` therefore clears `set_window_being_dragged()` (`tabs.py:2039`) before the source callback
can run. The async tick the report's hazard implicitly depends on is on the *other* branch.

**Negative control — the guard is not vacuous.** Drop a pane outside kitty: `draggingExited:` fires,
`drop_dest.os_window_id` goes to 0, `was_dropped` arrives True, and the detach at `boss.py:2050` runs.
That is the intended detach-to-new-OS-window feature, so the expression provably *can* be True.

**Why the claim looked live:** its whole evidentiary basis is the comment at
`~/kitty-482 kitty/tabs.py:2029-2033`. Read in full, that comment describes the *tab-bar-visibility*
symptom — *"clearing `window_drag_over_me` and hiding the tab bar for the single-tab case"* — on the
**non-self / Wayland** path. It is not a statement about the macOS pane-drag path, and the report's
inference *"kitty defends only the symptom, not this branch"* inverts it: kitty defends this branch in C,
one layer below where the report looked.

**Corrected claim.** There is no ordering hazard on the in-kitty path. Delete pre-work step (a). Do **not**
ask the operator to drag a pane on the live instance to establish it — the experiment risks a real pane
move on a terminal carrying his sessions to answer a question the source already answers, and a *negative*
result from it would have been weak evidence anyway (one drag cannot sample a race).

#### O2. Claim 2 is right about master and wrong about the remedy — and it is INERT on this machine

Two halves, and the report got the first right, left it "UNMEASURED", and then drew the opposite
conclusion from the second.

**(a) Master is objectively correct; v0.48.2's subtraction IS a bug.** Decidable without a build:
`~/kitty-482 kitty/layout/base.py:194` lays windows out with `layout_dimension(lgd.central.top, …)`, and
`layout_dimension` sets `pos = start_at` (`base.py:132`) — so `Window.geometry` **already includes**
`central.top`. Independently, C's `contains_mouse` (`~/kitty-482 kitty/mouse.c:270-273`) compares
`render_data.geometry` directly against the OS-window-relative `mouse_x/mouse_y`. Two independent reads,
same answer: geometry is OS-window absolute, so `rel_y = y - central.top` double-subtracts.

**(b) But the error is currently ZERO, so the report's "one print to settle it" has a known answer.**
`tab_bar_edge` defaults to `bottom` (`~/kitty-482 kitty/options/definition.py:2041`) and the operator does
not override it (`grep -n 'tab_bar_edge' config/kitty.conf` → no match). `os_window_regions` sets
`central->top = 0` on the bottom-edge branch (`~/kitty-482 kitty/state.c:773`) **and** on the
tab-bar-hidden branch (`state.c:785`). So `central.top ≡ 0` here — in both drag states — and the two
conventions are numerically identical on this machine.

**Corrected claim.** Backport master's helper **with master's convention** (raw `x, y`) and delete
`_find_window_at`'s `- central.left/- central.top` in the same hunk. The report's instruction to *"keep
v0.48.2's `rel_y` convention and say so at each hunk"* preserves a real latent bug and bakes it into the
new band code; it becomes live the moment anyone sets `tab_bar_edge top` (or `left`, which moves
`central.left`). The change is *safe to make now* precisely because both offsets are 0 today — that is the
argument for making it, not against. Delete pre-work step (b); it is answered.

#### O3. Claim 3's count is wrong, and the two extra sites are exactly the ones the patch must widen

Claim: *"`show_title_bar` … is read in exactly one place and its only effect is `render_ynum -= 1`."*

```
$ cd ~/kitty-482 && grep -rn "show_title_bar" kitty/ tools/ | grep -v force_show_title_bars | grep -v min_windows
kitty/tabs.py:1993:            if dest_window.show_title_bar:
kitty/tabs.py:2074:                dest_in_title_bar = getattr(win, 'show_title_bar', False) and (tb_top <= rel_y < tb_bottom)
kitty/window.py:716:    show_title_bar: bool = False  # must be set before calling set_geometry
kitty/window.py:1056:        show_tb = self.show_title_bar and new_geometry.ynum > 1
kitty/layout/base.py:408:        # Set show_title_bar flag on each visible window before layout
kitty/layout/base.py:415:                w.show_title_bar = show_title_bar
```

**Three reads, one writer.** The report contradicts itself: §0.1 and hunks 3-4 quote `tabs.py:1993` and
`tabs.py:2074` as reads of this very flag.

**Corrected claim.** `show_title_bar`'s only *geometric* effect is `render_ynum -= 1` (`window.py:1056`),
which is what makes it unusable as a zero-row flag — the design conclusion stands. But it has two further
reads, both hit tests, and those are precisely the sites that must become `show_title_bar or
overlay_title_bar`. State it as *"one writer, one geometric consumer, two hit-test consumers"*; the
count is the patch's own checklist, so getting it wrong risks missing a site.

#### O4. Claim 5's mechanism holds; its SCALE is ~2× wrong and was measurable

Claim: *"steals a row from all 9 panes in all 5 OS windows and SIGWINCHes 9 live agent sessions."*

```
$ env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID kitty @ --to unix:/tmp/kitty-597 ls
OSWindow 4  tabs: 1   tab 4  windows: 2  layout splits
OSWindow 5  tabs: 1   tab 5  windows: 3  layout splits
$ ps -axo pid=,command= | grep kitty        # one instance only: pid 597 (+ its kitten helpers)
```

**2 OS windows, 2 tabs, 5 panes** — not 5 and 9. The figure is the brief's, carried over unchecked, and
the report's own §3d quotes this same two-OS-window `ls` three sections later without reconciling it.
(The "9 live agent sessions" are evidently not all in kitty; this box's dispatch tooling is iTerm2-based.)

Mechanism **CONFIRMED** end-to-end, which is the part that matters: `t.force_show_title_bars = True`
(`tabs.py:1896`) → `WindowList.force_show_title_bars` (`tabs.py:502`) → `layout/base.py:411-415`
`w.show_title_bar = show_title_bar` → `window.py:1056` `render_ynum = ynum - 1` → `window.py:1075-1082`
`self.screen.resize(...)` then `self.resize_child(current_pty_size)` = a real SIGWINCH.

**Corrected claim.** Every tab of every OS window loses a row at drag start and regains it at drop —
today that is 5 panes across 2 OS windows. Pane counts are volatile; state the mechanism and let the
reader run `ls`. Hunk 5 is still required; only its blast-radius sentence changes.

### UPHELD

* **C1** ✓ exact. `_pointer_in_title_bar_of` absent from `~/kitty-482` (grep empty; same grep returns
  `kitty/tabs.py:2102,2182,2234` in `~/kitty-dev`, which positive-controls the instrument). Inlined twice
  in v0.48.2: hover at `tabs.py:1993-2002`, drop at `tabs.py:2066-2076`. Two sites, not one.
* **C4** ✓ exact. `start_window_drag` (`tabs.py:1882-1910`) has no branch on `show_title_bar`;
  `thumbnail_callback` takes its region from `w->render_data.geometry` (`child-monitor.c:866-872`);
  strip prepended at `tabs.py:1903`. The §1 **double-band residual is also confirmed by order**:
  `thumbnail_callback` is invoked at `child-monitor.c:922-925`, *after* the per-window `draw_cells` loop
  at `909-919`, so a band drawn in the UI pass is already in the framebuffer when the screenshot is read.
  Cure (A) is right.
* **C6** ✓ exact (`tabs.py:1918-1926`; `boss.py:2036-2040`). `update_title_bar`'s early return confirmed
  at `window.py:1151-1153`, so §2b's "the band will not tint" holds.
* **C7** ✓ — no option write exists anywhere in the press→motion→drop path. **One precision:** hunk 5 is
  *not* needed for (c). Without it the force-show path toggles `Tab.force_show_title_bars` and native
  bars, never the option, so the band still survives a no-op drag — hunk 5 buys requirement **(a)**
  during the drag, not (c). The headline's *"needs ZERO dedicated code … plus ONE guard hunk"* conflates
  two requirements in one sentence; say instead: *(c) needs zero hunks; (a)-during-drag needs hunk 5.*
* **C8** ✓ exact (`boss.py:1981-1996`; `tabs.py:2026-2082`). Refinement: `dest_in_title_bar` is
  **computed** at `tabs.py:2074`, *before* the self-check at `2078` — it is only **acted on** after. The
  claim is true of the branch taken, not of evaluation order; worth stating precisely because the overlay
  arm being added at 2074 will run on the no-op path even though its result is discarded.
* **C9** ✓ (`tabs.py:1875-1880`; `drag_threshold: int = 5` at `kitty/options/types.py:576`).
* **C10** ✓ mechanism (`tabs.py:1288-1290` → `1310-1312` → `1322-1324` → C `state.c:1149` → `state.c:728`;
  `resize(only_tabs=True)` relayouts every tab at `tabs.py:1341-1346`, the misnomer is real).
  **Sharpening:** because `tab_bar_edge` is `bottom`, the bump shrinks `central.bottom`, not `central.top`
  — the shift is at the bottom edge, and that same fact is what makes O2's coordinate bug inert.
* **C11** ✓ arithmetic exact (`shaders.c:837-839`, `870-871`, `return border_rect.height;` at `887`;
  `thickness_as_float` at `304-310` reading `OPT(box_drawing_scale)[1]`; default `(0.001, 1.0, 1.5, 2.0)`
  at `kitty/options/types.py:548`, not overridden). **Two sharpenings, both strengthening it:**
  1. **The error it warns against is unfalsifiable on this config.** `box_drawing_scale[1]` is **1.0pt**
     and `window_border_width` is **1pt** (`config/kitty.conf:1157`) — both give 2px at this dpi. A patch
     that wrongly used `window_border_width` would be *right by coincidence here*, and any test written
     on this machine cannot discriminate the two formulas. Make the control non-vacuous by moving one of
     them before trusting a green.
  2. **The height is not the constant 51.** `thickness_as_float` reads
     `os_window->fonts_data->logical_dpi_{x,y}` and `bar_height` reads
     `os_window->fonts_data->fcm.cell_height` — **both per-OS-window**. On a 1× display the same config
     yields `45 + 2 + 2·1 = 49px`. Two OS windows exist. So "51" may not be written down anywhere; it
     must be read per window, which is exactly what 1b is for.
* **C12** ✓ exact (`mouse.c:260-262`; `shaders.c:1439` `.screen_top = srd->geometry.top`;
  `config/kitty.conf:1109`).
* **C13** ✓ exact, line-for-line (`mouse.c:1067-1081` with `contains_mouse` first and the title-bar arm in
  the `else if`; `contains_mouse` at `270-273`; `POINTER_POINTER` + `handle_window_title_bar_mouse` at
  `1354-1368`; forwarded to Python at `929-937`).
* **C14** ✓ (`kitty/options/types.py:43` and `:721`).

### NEW RISKS

#### N1. Recommendation 1b, as written, converts a transient RENDER failure into a silent STATE change

1b says: *"Store `render_a_bar`'s own return value into that field and zero it when not drawn … makes
`!= 0` the single 'band is up' predicate … turns the most likely bug into an unrepresentable state."*

`render_a_bar` returns **0 on three failure paths**, not only when the band is deliberately absent
(`~/kitty-482 kitty/shaders.c`): `if (!bar->buf) return 0;` (malloc, `:843`), `if (!title) return 0;`
(`:852`) and `if (!draw_window_title(...)) return 0;` (`:855`). The last two sit inside the
`bar->last_drawn_title_object_id != title || bar->needs_render` re-render block, so they are reachable on
any frame where the title changed — including a window whose title is momentarily unset.

Under 1b that single frame (a) zeroes `overlay_title_bar_height`, so the C arm stops matching and the hand
cursor and drag die, and (b) — because `!= 0` was made the sole "band is up" predicate — makes Python's
`_pointer_in_title_bar_of` overlay arm return False, so the **drop target disappears too**. A CoreText
hiccup is then indistinguishable from the user having toggled the band off, with no error anywhere. That
is the same failure *shape* 1b set out to eliminate, relocated.

**Corrected recommendation.** `border_rect.height` depends only on `ui->cell_height` and
`thickness_as_float(ui->os_window, 1)`, neither of which can fail. Compute it at the **top** of
`render_a_bar` and write it to the window field **before** any early return; keep "band is up" as its own
boolean (the option, or a separate flag), not as `height != 0`. This keeps 1b's genuine property — hit
rect and painted rect are the same number by construction — without overloading one field with two facts.

#### N2. Hunk 1 and hunk 2 key on two different rects that coincide only under the design's premise

Hunk 1 (C) keys the hit band on `win->render_data.geometry.top`; hunk 2's helper (Python) keys it on
`win.geometry.top`. These are **different objects**: `window.py:1075-1097` assigns `self.geometry =
new_geometry` (the full rect) while pushing `render_top/render_bottom` into the C render data, and those
differ by one cell whenever `show_title_bar` is True (`window.py:1056-1063`). They are equal for band
windows *only because the design keeps `show_title_bar` permanently False* — which is the premise, so no
bug today. But it means any later change that lets one window carry both a native bar and the band
desynchronises the two hit rects by exactly one cell, in opposite directions, with both patches looking
locally correct. Make it an assertion at the draw site (band height written only when
`!w->window_title_render_data.screen`), not a comment.

### WHAT I DID NOT MEASURE

* **No kitty build.** Every finding above is a read of named source, plus one read-only `ls`.
* **`cell_height = 45px` and `logical_dpi = 144`** are taken from the brief as established; I did not
  measure them. The 51px figure inherits that dependency — which is the point of C11's sharpening 2.
* **AppKit's `performDragOperation:` → `draggingSession:endedAtPoint:` ordering** was not executed. O1
  deliberately does not rest on it: guard (i) is ordering-independent.
* **The §3d bump as pixels.** Confirmed as a code path and as a real `screen.resize` + `resize_child`;
  not observed as a rendered shift.

### DISPOSITION OF THE RECOMMENDATION'S ORDERED PRE-WORK

* **(a) drag a pane and drop it on itself** — **delete.** Answered in source (O1); the experiment carries
  real risk on the live instance and a null result would be weak evidence.
* **(b) one print of `central.top` vs `win.geometry.top`** — **delete.** Answered in source (O2):
  `central.top ≡ 0` on this config because `tab_bar_edge` is `bottom`. Change the convention to master's
  rather than preserving v0.48.2's.
* **(c) put the §3d tab-bar-visibility bump in front of the operator as a decision** — **keep.** It is a
  genuine value call with no dominant option, it predates this work, and nothing in source settles it.
  Correct its scale to 5 panes / 2 OS windows and note the shift is at the **bottom** edge.
