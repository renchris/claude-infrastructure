# The toggle: how ⌘⇧B ON/OFF propagates with zero cost and zero shift

Axis owner: research agent "toggle-liveness". Date 2026-09-16.
Trees read: `~/kitty-482` = **v0.48.2** (`2cb1d95c3`, the build the operator runs) and `~/kitty-dev`
= master (`1d67ecd47`). **Every file:line below names its tree.** Anything I could not run is marked
`UNMEASURED`.

**Bottom line up front:** use a **new kitty action** that flips a **process-global C-side flag** and
marks **every OS window** dirty. Do **not** use `kitty @ load-config`, and do **not** copy the
`toggle_window_title_bars` shape. Evidence and the exact conf lines are in §7.

---

## 0. The three candidate mechanisms, priced

| | Mechanism | Relayout? | PTY resize / SIGWINCH? | Reaches all OS windows? | Survives an unrelated config reload? |
|---|---|---|---|---|---|
| R1 | `kitty @ load-config <variant>.conf` (today's `kitty-pane-title-toggle.sh` pattern) | **YES — every tab of every OS window** | **Not inherently** (§1.4) — but *today's* variant pair DOES: MEASURED §5.2, every pane of every OS window went 22 -> 21 rows, because the variant flips `window_title_bar_min_windows`. The relayout itself is unconditional either way. | yes (MEASURED §5.2) | **yes, but inverted** — a reload re-reads the file, so state = whichever file was last loaded |
| R2 | new kitty ACTION flipping a **per-tab** bool (the `toggle_window_title_bars` shape) | yes, per tab, via `Tab.relayout()` | no | **NO — one tab manager only** (§2.1, MEASURED §5.1) | survives a reload, but **LOST** on any drag (`tabs.py:1918-1926`) and on every new tab / new OS window (MEASURED §5.5) |
| R3 | **new kitty ACTION flipping a process-global C bool + `mark_os_window_dirty` on every OS window** | **no** | no | yes | **yes** — the flag lives outside `Options`, so `set_options()` cannot touch it |

R3 is the recommendation. R1 and R2 are both refuted below on measured code paths.

---

## 1. The option route (`kitty @ load-config`) — CONFIRMED EXPENSIVE, and the cost is not the parse

### 1.1 The remote command is a thin wrapper on `Boss.load_config_file`

`~/kitty-482/kitty/rc/load_config.py:67-74` — `response_from_kitty` calls
`boss.load_config_file(*paths, apply_overrides=not payload_get('ignore_overrides'), overrides=...)`.
Nothing else. So `kitty @ load-config` costs exactly what `Boss.load_config_file` costs.

`--ignore-overrides` being load-bearing is confirmed by the option's own help text at
`~/kitty-482/kitty/rc/load_config.py:41-44`: *"By default, any config overrides previously specified
at the kitty invocation command line **or a previous load-config-file command** are respected."*
And in `~/kitty-482/kitty/boss.py:3206`, `final_overrides = old_opts.config_overrides if apply_overrides else ()`
— overrides accumulate across reloads unless you pass the flag. The existing
`scripts/kitty-pane-title-toggle.sh` learned this correctly.

### 1.2 What `Boss.load_config_file` actually does — `~/kitty-482/kitty/boss.py:3199-3221`

```
load_config(*paths, ...)          # re-parse every config file from disk
clear_font_caches()               # kitty/fonts/render.py
self.apply_new_options(opts)      # <- the expensive part, §1.3
open_actions.clear_caches()
guess_mime_type.clear_mime_cache()
store_effective_config()          # writes a file
tab_bar.clear_caches()
```

### 1.3 `apply_new_options` — `~/kitty-482/kitty/boss.py:3146-3188`, the real bill

Per call, unconditionally, **whether or not any option actually changed**:

| Line (`~/kitty-482/kitty/boss.py`) | Work |
|---|---|
| 3151 `set_options(...)` + 3152 `apply_options_update()` | replaces the whole global `Options` object, C side re-reads it |
| 3156 `set_font_family(opts)` | re-resolves and re-renders the font family |
| 3158-3162 **per OS window**: `os_window_font_size(id, opts.font_size, True)` then `tm.resize()` | see §1.4 — `force=True` is the killer |
| 3165-3166 `cocoa_clear_global_shortcuts()` (macOS) | drops every global shortcut |
| 3167 `self.mappings.update_keymap()` | rebuilds every keybinding |
| 3169 `cocoa_recreate_global_menu()` (macOS) | rebuilds the whole macOS menu bar |
| 3171-3172 **per tab manager**: `tm.apply_options()` → per tab → **per window** `window.apply_options(...)` | `~/kitty-482/kitty/tabs.py:2126-2133` and `:268-272` |
| 3178-3186 **per window**: `w.refresh(reload_all_gpu_data=True)` | full GPU data re-upload for every window in the process |
| 3187 `load_shader_programs.recompile_if_needed()` | shader check |

### 1.4 `os_window_font_size(..., force=True)` — the hidden per-window cost

`~/kitty-482/kitty/boss.py:3160` passes `force=True`. In
`~/kitty-482/kitty/state.c:1299-1317` the `force` flag defeats the `new_sz != current` early-out:

```c
if (new_sz > 0 && (force || new_sz != os_window->fonts_data->font_sz_in_pts)) {
    on_os_window_font_size_change(os_window, new_sz);
    send_prerendered_sprites_for_window(os_window);
    resize_screen(os_window, os_window->tab_bar_render_data.screen, false);
    for (... every tab ...) for (... every window ...)
        resize_screen(os_window, w->render_data.screen, true);
```

So a `load-config` that changes **nothing** still re-sends the prerendered sprite atlas for every OS
window and runs `resize_screen` over every window in the process.

**Good news, and it is the one thing that saves R1 from being disqualifying:** `resize_screen` here is
**not** a PTY resize. `~/kitty-482/kitty/state.c:492-499`:

```c
resize_screen(OSWindow *os_window, Screen *screen, bool has_graphics) {
    if (screen) {
        screen->cell_size.width  = os_window->fonts_data->fcm.cell_width;
        screen->cell_size.height = os_window->fonts_data->fcm.cell_height;
        screen_dirty_sprite_positions(screen);
        if (has_graphics) screen_rescale_images(screen);
    }
}
```

No `lines`/`columns` change, no `SIGWINCH`. It dirties every sprite position (forcing a full
re-upload of cell data on the next frame) and rescales every graphics image. Expensive, not
destructive.

### 1.5 Does the relayout change rows? Only if the option touches `show_title_bar`

`tm.resize()` (`~/kitty-482/kitty/tabs.py:1342-1347`) calls `tab.relayout()` for **every** tab, which
runs the layout (`~/kitty-482/kitty/tabs.py:499-506`). The layout's `__call__`
(`~/kitty-482/kitty/layout/base.py:404-416`) is where the row is stolen:

```python
min_windows = get_options().window_title_bar_min_windows
visible_groups = tuple(all_windows.iter_all_layoutable_groups(only_visible=True))
force_show = all_windows.force_show_title_bars
show_title_bar = force_show or (min_windows > 0 and len(visible_groups) >= min_windows)
for wg in visible_groups:
    for w in wg.windows:
        w.show_title_bar = show_title_bar
```

and `Window.set_geometry` (`~/kitty-482/kitty/window.py:1050-1090`) consumes it:

```python
show_tb = self.show_title_bar and new_geometry.ynum > 1
if show_tb:
    render_ynum = new_geometry.ynum - 1        # <-- THE STOLEN ROW
    ...
if self.needs_layout or new_geometry.xnum != self.screen.columns or render_ynum != self.screen.lines:
    self.screen.resize(max(0, render_ynum), max(0, new_geometry.xnum))   # <-- SIGWINCH path
```

**This is the whole arithmetic of the problem, located exactly:** `~/kitty-482/kitty/window.py:1058`
(`render_ynum = new_geometry.ynum - 1`) and `:1078` (`self.screen.resize(...)`). An option that does
**not** feed `show_title_bar` cannot reach line 1078, so it **cannot** cause a SIGWINCH. A band drawn
outside the cell grid does not feed it. **So R1 is not wrong about shift — it is wrong about cost.**

### 1.6 The one cheap thing in the relayout path

`~/kitty-482/kitty/window.py:1081-1089`:

```python
if current_pty_size != self.last_reported_pty_size:
    ... resize_child(...)                       # SIGWINCH
else:
    mark_os_window_dirty(self.os_window_id)     # <-- just a redraw
```

A relayout that changes no geometry falls into the `else` and costs exactly **one dirty flag**. That
is the primitive R3 uses directly, without paying for the other 40 lines of `apply_new_options`.

### 1.7 Verdict on R1

**REFUTED as the toggle mechanism.** It works, it does not shift content, and it does reach every OS
window — but its per-press bill is a full config re-parse, a font-family re-resolve, a macOS menu-bar
rebuild, a keymap rebuild, a prerendered-sprite re-send per OS window, a `screen_dirty_sprite_positions`
+ `screen_rescale_images` per window, a relayout of every tab, and a `reload_all_gpu_data` refresh of
every window. Against a goal that says *"lowest to zero latency and memory pressure"*, that is the
wrong end of the scale by three orders of magnitude. It is also **not the correct persistence model**
— see §4.

---

## 2. The action route

### 2.1 `toggle_window_title_bars` reaches ONE OS window — CONFIRMED, the repo record is right

`~/kitty-482/kitty/boss.py:3492-3505`:

```python
def toggle_window_title_bars(self) -> None:
    tm = self.active_tab_manager          # <-- singular
    if tm is None:
        return
    ...
    currently_forced = any(t.force_show_title_bars for t in tm)
    for t in tm:                          # <-- every tab of THAT ONE OS window
        ...
        t.force_show_title_bars = not currently_forced
        t.relayout()
```

and `~/kitty-482/kitty/boss.py:1616-1624`:

```python
@property
def active_tab_manager(self) -> TabManager | None:
    os_window_id = current_focused_os_window_id()
    if os_window_id <= 0: os_window_id = last_focused_os_window_id()
    if os_window_id <= 0:
        q = current_os_window()
        if q is not None: os_window_id = q
    return self.os_window_map.get(os_window_id)      # <-- ONE TabManager
```

One `TabManager` == one OS window (`self.os_window_map` is keyed by OS-window id). **VERIFIED: one press
of `toggle_window_title_bars` does not reach the other 4 OS windows.** It does reach every *tab* of the
focused OS window, which is more than the brief assumed — but not the other OS windows.

The correct scope for us is `Boss.all_tab_managers`, `~/kitty-482/kitty/boss.py:547-548`:

```python
@property
def all_tab_managers(self) -> Iterator[TabManager]:
    yield from self.os_window_map.values()
```

kitty itself uses exactly this when it *does* mean "everywhere" — the drag-start path at
`~/kitty-482/kitty/tabs.py:1890-1897` and `_clear_force_show_title_bars` at
`~/kitty-482/kitty/tabs.py:1918-1926` both iterate `boss.all_tab_managers`. So the fan-out idiom
already exists in-tree and is not an invention.

### 2.2 Why the `force_show_title_bars` shape is the wrong shape anyway — three defects

**(a) It is cleared by any drag, from anywhere.** `~/kitty-482/kitty/tabs.py:1918-1926`
(`_clear_force_show_title_bars`) and `~/kitty-482/kitty/boss.py:2035-2040`
(`on_drag_source_finished`) both walk *every* tab manager and set `force_show_title_bars = False` +
`relayout()`. Called from `on_window_drop` (`~/kitty-482/kitty/tabs.py:2035`), from a failed
`start_drag_with_data` (`~/kitty-482/kitty/tabs.py:2001`), and from `on_drag_source_finished`. This
is the exact failure the operator has already rejected: requirement (c) says the title must stay ON
after a no-op drag. The existing conf-swap route dodges it by holding the bars up with
`window_title_bar_min_windows`, which `Layout.__call__` consults independently of `force_show`
(`~/kitty-482/kitty/layout/base.py:410-411`). **Any new mechanism must be equally immune — i.e. it
must not live in `force_show_title_bars`.**

**(b) It is per-`Tab`, so a new tab does not inherit it.** `~/kitty-482/kitty/tabs.py:184`
`force_show_title_bars: bool = False` is a Tab field with a False default. A tab created after the
toggle starts OFF. Same for a new OS window.

**(c) It routes through `Tab.relayout()`, which is a full layout pass.**
`~/kitty-482/kitty/tabs.py:499-506` → `self.current_layout(self.windows)` → `Layout.__call__` →
`set_geometry` on every window group. For a band drawn outside the cell grid that is pure waste: the
geometry does not change, so every window falls into the `else: mark_os_window_dirty(...)` branch at
`~/kitty-482/kitty/window.py:1088` and the entire layout computation was spent to set one bool.

### 2.3 The right precedent is already in the tree: `Screen.set_window_char` (visual window select)

This is the closest analogue kitty ships, and it does exactly what we want:

| | Evidence (`~/kitty-482`) |
|---|---|
| Python sets a C field on the Screen, per window | `kitty/boss.py:1721` `window.screen.set_window_char(ch)`; cleared at `kitty/boss.py:365` `w.screen.set_window_char()` |
| The C setter is 4 lines and marks the screen dirty, nothing else | `kitty/screen.c:4963-4969`: `self->display_window_char = text[0]; self->is_dirty = true;` |
| The field lives on `Screen`, **not** in `Options` | `kitty/screen.h:172` `char display_window_char;` |
| The draw path reads it per frame as a plain predicate | `kitty/shaders.c:933-937` `has_window_number(w, screen) { return w != NULL && screen->display_window_char != 0; }` |
| **It already calls `render_a_bar` with the window TITLE** | `kitty/shaders.c:943`: `title_bar_height = render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false);` |

**No relayout. No option change. No PTY resize. No SIGWINCH.** `is_dirty` propagates to a redraw via
`cell_prepare_to_render` → `send_cell_data_to_gpu` returning `true`
(`~/kitty-482/kitty/shaders.c:822-828`) → `needs_render = true` in `prepare_to_render_os_window`
(`~/kitty-482/kitty/child-monitor.c:816`).

> Note for the lead's design axis, not mine: `kitty/shaders.c:943` means **an SF-Pro window-title bar
> drawn outside the cell grid at the top of a pane is already reachable in stock 0.48.2 today** — it is
> merely gated behind `screen->display_window_char != 0` (i.e. only during visual window select).
> That is the smallest possible proof that `render_a_bar` works in that position.

### 2.4 🚨 The trap that will silently eat the band: `needs_layers`

`render_a_bar`'s consumers are only reached from `draw_cells_with_layers`
(`~/kitty-482/kitty/shaders.c:1380-1382`). The other branch,
`draw_cells_without_layers` (`~/kitty-482/kitty/shaders.c:1344-1346`), is a single
`call_cell_program(CELL_PROGRAM, ...)` and draws **no** UI chrome at all. The branch is chosen at
`~/kitty-482/kitty/shaders.c:1448`:

```c
if (ui.os_window->needs_layers) draw_cells_with_layers(&ui, srd->vao_idx);
else draw_cells_without_layers(&ui, srd->vao_idx);
```

`needs_layers` is computed per frame in `prepare_to_render_os_window`
(`~/kitty-482/kitty/child-monitor.c:756-760`, `:770`, `:781`, `:786`), and the per-window term is
`screen_needs_rendering_in_layers` at `~/kitty-482/kitty/shaders.c:1316-1320`:

```c
const bool has_ui = w && ((screen->start_visual_bell_at | screen->start_drag_overlay_at)
    || has_scrollbar(w, screen) || has_progress_bar(screen)
    || has_hyperlink_target(os_window, w, screen) || has_window_number(w, screen)
    || w->window_logo.id);
```

**A new band predicate MUST be added to this disjunction.** If it is not, the toggle will appear to
work on some panes and do nothing on others — specifically it will work only where something *else*
(a scrollbar, an image, a logo, alpha < 1) happens to have forced layers on — which reads as a flaky
toggle and is the hardest class of bug to attribute. On this machine `background_opacity` is not set
so `effective_os_window_alpha == 1`, and a pane with no images and no scrollbar would take the
fast path. **This is the single highest-risk implementation detail on my axis.**

---

## 3. Immediate visibility — what makes it one frame, not "next redraw"

### 3.1 The dirty plumbing, end to end

| Step | Evidence (`~/kitty-482`) |
|---|---|
| Python entry point | `kitty/fast_data_types.pyi:1397` `def mark_os_window_dirty(os_window_id: int) -> None`; exported at `kitty/state.c:1718` `K(mark_os_window_dirty)` and `kitty/state.c:1832` |
| The setter | `kitty/state.c:594-599`: `WITH_OS_WINDOW(os_window_id) os_window->needs_render = true;` |
| Consumed, and **cleared**, once per frame | `kitty/child-monitor.c:754-755`: `bool needs_render = os_window->needs_render; os_window->needs_render = false;` |
| Per-OS-window gate on actually drawing | `kitty/child-monitor.c:982`: `if (needs_render) render_prepared_os_window(...)` |
| The loop that visits every OS window | `kitty/child-monitor.c:1000-1008`: `for (i = 0; i < global_state.num_os_windows; i++) { ... render_os_window(w, now, ...) }` |

**Consequence for the toggle:** `render()` walks every OS window on every tick, but only draws the
ones whose `needs_render` is set. So `mark_os_window_dirty` must be called **once per OS window** —
i.e. `for tm in boss.all_tab_managers: mark_os_window_dirty(tm.os_window_id)`. Marking only the
focused one leaves the other 4 OS windows showing the stale state until something else happens to
dirty them (a keystroke, output from a child, a cursor blink). On an idle pane that can be seconds.

### 3.2 Does the key press itself produce a frame? YES

`~/kitty-482/kitty/glfw.c:523-537` — `key_callback` ends with `request_tick_callback()` at
`kitty/glfw.c:537` (the `is_window_ready_for_callbacks()` line is 535, the tick request follows in the
same callback; `request_tick_callback` is defined at `kitty/glfw.c:165`). The tick runs
`process_global_state` (`~/kitty-482/kitty/child-monitor.c:1394-1424`) which calls
`render(now, input_read)` at `kitty/child-monitor.c:1407`.

### 3.3 The one bound: `repaint_delay`

`~/kitty-482/kitty/child-monitor.c:988-995`:

```c
monotonic_t time_since_last_render = ... now - last_render_at;
if (!input_read && time_since_last_render < OPT(repaint_delay) && !global_state.thumbnail_callback.os_window) {
    set_maximum_wait(OPT(repaint_delay) - time_since_last_render);
    return;
}
```

kitty's `repaint_delay` **default** is 10 ms (`~/kitty-482/kitty/options/types.py:639`
`repaint_delay: int = 10`; parsed as `positive_int` at `kitty/options/parse.py:1243-1244`) — but
**the operator overrides it to 16 ms**: `claude-infrastructure/config/kitty.conf:747` reads
`repaint_delay 16`, with the reasoning at `:744` (*"kitty's default 10ms = up to 100 FPS. The displays
are 60Hz, so frames 11-100..."*). `input_read` here means *child PTY output was parsed*, not *a key was
pressed*, so the worst case for a keyboard-driven toggle on this machine is **one repaint_delay =
16 ms**, and `set_maximum_wait` guarantees the loop comes back for it. That is one 60 Hz frame.

**Measured bound: UNMEASURED end-to-end.** I did not build kitty (§6 safety rule), so the 16 ms figure
is derived from source plus the operator's own config value, not timed. What *is* CONFIRMED is that there is no polling, no timer and no
second-order debounce anywhere on this path — unlike today's overlay daemon, which re-asserts on a
**2-second** timer.

### 3.4 What this buys against today's overlay

| | Today (`scripts/kitty-pane-title-overlay.py`) | R3 |
|---|---|---|
| Resident process | Python + Pillow daemon | none |
| Timer | 2 s re-assert | none |
| Transport per press | unix socket + PNG per pane | one C bool + N dirty flags |
| Latency to visible | up to 2 s (re-assert cadence) on the failure path | ≤ `repaint_delay` (10 ms) |

---

## 4. Persistence — what survives what

### 4.1 The auto-reload watcher, traced end to end

| Step | Evidence (`~/kitty-482`) |
|---|---|
| Watcher is spawned once, at startup | `kitty/boss.py:1418-1421`: `if opts.auto_reload_config >= 0 and not hasattr(self, 'config_reload_watcher_process') ...  subprocess.Popen([kitten_exe(), '__watch_conf__', str(os.getpid()), str(int(opts.auto_reload_config*1000))] + list(opts.all_config_paths))` |
| Debounce default | `kitty/options/types.py:534` `auto_reload_config: float = 0.1` → **100 ms**, matching the brief |
| Watcher resolves symlinks of the *directory* | `tools/watch/api.go:78-84` `resolve_path` → `filepath.EvalSymlinks(dir)` then rejoins the basename |
| What it sends | `tools/watch/api.go:222-225` `signal_kitty_to_reload_config` → `unix.Kill(kitty_pid, unix.SIGUSR1)` |
| Signal is latched | `kitty/child-monitor.c:1537-1538` `case SIGUSR1: ss->reload_config = true;` |
| Latch is drained on the next read pass | `kitty/child-monitor.c:509-511` |
| And dispatched | `kitty/child-monitor.c:573-575`: `if (reload_config_called) call_boss(load_config_file, NULL);` |

So an unrelated reload is **`Boss.load_config_file()` with no arguments**, which resolves
`paths = paths or prev_paths` where `prev_paths = old_opts.all_config_paths`
(`~/kitty-482/kitty/boss.py:3202-3204`), with `apply_overrides=True`.

### 4.2 🚨 A finding that matters for the EXISTING toggle script, not just for R3

`~/kitty-482/kitty/config.py:192` sets `opts.all_config_paths = paths` — **the paths passed to this
load**, not the original ones. So after
`kitty @ load-config --ignore-overrides ~/.config/kitty/kitty-title-on.conf`, kitty's idea of "my
config" becomes `('~/.config/kitty/kitty-title-on.conf',)` **permanently**, and the next SIGUSR1
(from `deploy-live` fast-forwarding `config/kitty.conf`, or any edit) reloads *that* file.

It happens to be harmless today, and only by luck: `config/kitty-title-on.conf` line 57 is
`include kitty.conf`, so reloading the variant still picks up the real config. **If that `include`
were ever dropped, an unrelated config edit would silently replace the operator's entire
configuration with two lines.** Meanwhile the watcher child is still watching the *original*
`all_config_paths` (it is spawned once, guarded by `not hasattr(...)`, `kitty/boss.py:1418`), so the
watch set and the reload set diverge after the first toggle. **Recorded as a latent defect of R1,
independent of which mechanism is chosen.** UNMEASURED at runtime — established from source only.

### 4.3 Persistence matrix

| Event | R1 (conf swap) | R2 (`force_show_title_bars`) | **R3 (global C flag)** |
|---|---|---|---|
| Unrelated config reload (SIGUSR1 / `deploy-live`) | **survives** — the variant file is now `all_config_paths` (§4.2) and it `include`s the real config | **survives** — `apply_new_options` never resets the Tab field; the relayout at `kitty/tabs.py:502` re-reads `self.force_show_title_bars` | **survives** — the flag is not in `Options`, so `set_options()` (`kitty/boss.py:3151`) cannot touch it |
| New window in an existing tab | survives (option is global) | survives (bool is on the Tab) | survives (flag is global) |
| **New tab** | survives | **LOST** — `kitty/tabs.py:184` default is `False` | survives |
| **New OS window** | survives | **LOST** — never set on that tab manager | survives |
| Layout change (`next_layout` etc.) | survives | survives | survives — the flag is not layout state |
| Tab switch | survives | survives | survives |
| **Any drag, incl. a no-op drag** | **survives** (held by `window_title_bar_min_windows`, not `force_show`) | **LOST** — `_clear_force_show_title_bars`, `kitty/tabs.py:1918-1926` | survives — nothing in-tree clears a new global |
| kitty restart | lost (state file desyncs; the script documents this itself) | lost | lost unless persisted; see §5.3 |

The "new tab" and "new OS window" rows are what kill R2 outright, and the drag row is what kills it
for requirement (c).

### 4.4 Why R3's flag must NOT live in `Options`

`~/kitty-482/kitty/boss.py:3151` `set_options(opts, ...)` **replaces the whole options object**. Any
toggle state stored as an option is therefore reset to whatever the config file says on every
reload — which is precisely what makes R1 need a second config file and a state file on disk. A
runtime global in `global_state` (`~/kitty-482/kitty/state.h`) or a per-`Screen` field
(`kitty/screen.h:172` is the precedent) is untouched by `set_options`, so it needs neither.

---

## 5. MEASURED — one sandbox kitty 0.48.2 instance, the operator's binary

**Rig.** `/Applications/kitty.app/Contents/MacOS/kitty` (the same 0.48.2 the operator runs),
`--config /private/tmp/ktb-toggle/base.conf --listen-on unix:/private/tmp/ktb-toggle/sock
--instance-group ktbtoggle`. Every remote command prefixed
`env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID` with an explicit
`--to unix:/private/tmp/ktb-toggle/sock`. The operator's live pid 597 was never written to. Sandbox
config mirrors the live one on the settings that matter (`font_family Monaco`, `font_size 18.0`,
`modify_font cell_height 94%`, `window_padding_width 0 5 0 5`, `window_title_bar_min_windows 0`,
`repaint_delay 16`, `window_border_width 1pt`, `draw_minimal_borders no`, `placement_strategy top`),
with `auto_reload_config -1`. Row counts read from `kitty @ ls` → `windows[].lines`.

### 5.1 `toggle_window_title_bars` reaches ONE OS window — MEASURED

Two OS windows, two panes each, focus on OSW2:

```
--- BASELINE ---                         OSW1 rows=[22, 22]   OSW2 rows=[22, 22]  (focused)
--- action toggle_window_title_bars ---  OSW1 rows=[22, 22]   OSW2 rows=[21, 21]
--- action toggle_window_title_bars ---  OSW1 rows=[22, 22]   OSW2 rows=[22, 22]
```

**CONFIRMED by measurement, not only by source:** the unfocused OS window never moved. The focused one
lost exactly one row per pane — i.e. the PTY resize / SIGWINCH the operator has rejected.

### 5.2 `kitty @ load-config` reaches ALL OS windows — MEASURED

Same rig, one command each way:

```
load-config --ignore-overrides on.conf    (window_title_bar_min_windows 1)
    OSW1 rows=[21, 21]   OSW2 rows=[21, 21]
load-config --ignore-overrides base.conf  (window_title_bar_min_windows 0)
    OSW1 rows=[22, 22]   OSW2 rows=[22, 22]
```

So R1's *reach* is correct and R2's is not. R1 dies on cost (§5.3), not on reach.

### 5.3 The cost of a `load-config` that changes NOTHING — MEASURED, with a reproduced control

The client-side RPC round trip is ~30-50 ms and swamps wall-clock timing, so I measured **kitty's own
cumulative CPU** (`ps -o time= -p <sandbox pid>`) across 100 identical remote commands per arm.
`base.conf` was loaded over `base.conf` — an **identical** config, zero option changes — so the number
is pure `apply_new_options` overhead.

**At 2 OS windows / 4 panes:**

| Arm | 100 calls | per call | above floor |
|---|---|---|---|
| A `kitty @ ls` (RPC floor) | 0:00.76 → 0:00.93 = **0.17 s** | 1.7 ms | — |
| B `kitty @ load-config --ignore-overrides base.conf` | 0:00.93 → 0:02.20 = **1.27 s** | 12.7 ms | **+11.0 ms** |
| C `kitty @ action toggle_window_title_bars` (a real relayout **with** a PTY resize) | 0:02.21 → 0:02.50 = **0.29 s** | 2.9 ms | **+1.2 ms** |
| D `kitty @ ls` again — **control re-run** | 0:02.50 → 0:02.67 = **0.17 s** | 1.7 ms | — |

**Arm D reproduced arm A to the centisecond (0.17 s both times).** That is the positive control that
makes the B/C separation a reading rather than drift.

**Headline: a no-op `load-config` costs ~9× the full relayout it is meant to replace, and ~7.5× the
RPC floor.** R1 is not a cheap way to avoid a relayout — it is an expensive way to *do* one, plus a
config parse, a font re-resolve, a macOS menu-bar rebuild, a keymap rebuild and a full GPU reload.

**Scaling — the cost is mostly FIXED, not per-pane.** Grown to 3 OS windows / 13 panes:

| Arm | 100 calls | per call | above floor |
|---|---|---|---|
| A2 `kitty @ ls` | 0:02.87 → 0:03.13 = 0.26 s | 2.6 ms | — |
| B2 `load-config base.conf` | 0:03.13 → 0:04.61 = **1.48 s** | 14.8 ms | **+12.2 ms** |

4 panes → 13 panes moved the differential only 11.0 → 12.2 ms. The bulk is the fixed work in
`~/kitty-482/kitty/boss.py:3146-3188` (parse, fonts, `cocoa_recreate_global_menu`,
`mappings.update_keymap`), not the per-window loop. So the operator's 9-pane / 5-OS-window instance
will pay roughly the same ~12 ms per press — **every press, for a toggle whose entire job is to set
one bool.**

> Honest limit: this is kitty-side CPU on an idle sandbox, measured at 10 ms `ps` resolution over 100
> calls. It is a ratio between arms measured the same way in the same minute, which is what the claim
> needs. It is **not** a latency-to-visible figure; see §3.3, which is UNMEASURED.

### 5.4 Persistence across an unrelated config reload — MEASURED, and it confirms §4.2

`Boss.load_config_file()` with **no paths and `apply_overrides=True`** is exactly what the SIGUSR1
watcher invokes (`~/kitty-482/kitty/child-monitor.c:573-575` → `call_boss(load_config_file, NULL)`).
A bare `kitty @ load-config` with no `--ignore-overrides` is byte-identical to that call
(`~/kitty-482/kitty/rc/load_config.py:67-74`), so it is a faithful stand-in. 3 OS windows, 13 panes:

```
state 0 (OFF)                      OSW1=[22,22] OSW2=[22,22] OSW3=[22 x9]
load-config --ignore-overrides on.conf
                                   OSW1=[21,21] OSW2=[21,21] OSW3=[21 x9]
BARE 'kitty @ load-config'   (= the watcher's reload)
                                   OSW1=[21,21] OSW2=[21,21] OSW3=[21 x9]   <- ON SURVIVED
BARE again
                                   OSW1=[21,21] OSW2=[21,21] OSW3=[21 x9]   <- and again
load-config --ignore-overrides base.conf
                                   OSW1=[22,22] OSW2=[22,22] OSW3=[22 x9]
BARE after OFF
                                   OSW1=[22,22] OSW2=[22,22] OSW3=[22 x9]   <- OFF survived
```

**CONFIRMED: after one `load-config <variant>`, kitty's `all_config_paths` IS the variant file**
(`~/kitty-482/kitty/config.py:192`), so every later reload — including the one `deploy-live` triggers
by fast-forwarding `config/kitty.conf` — reloads the variant. The state is sticky in both directions.
Good for R1's persistence; **and it is the latent hazard of §4.2**, because the operator's whole
configuration now hangs off `config/kitty-title-on.conf:57` `include kitty.conf`. Drop that one line
and an unrelated config edit replaces the entire config with two settings.

### 5.5 `force_show_title_bars` is NOT inherited by a new tab or a new OS window — MEASURED

Bars forced ON in OSW3 (9 panes), then new containers created while ON:

```
A. baseline            OSW3 [(tab 3, [22 x9])]
B. toggle_window_title_bars
                       OSW3 [(tab 3, [21 x9])]                    <- ON
C. launch --type=tab   OSW3 [(tab 3, [20 x9]), (tab 4, [21])]
D. launch --type=os-window
                       OSW3 [(tab 3, [20 x9]), (tab 4, [21])],  OSW4 [(tab 5, [22])]
```

Reading C: creating a second tab makes the **tab bar** appear, which costs one row from every window
in that OS window — hence tab 3 going 21 → 20. The new tab 4 sits at **21**, i.e. the
tab-bar-present baseline **with no title bar**. Tab 3 at 20 has both. So the new tab did **not**
inherit the forced bars. Reading D: OSW4 is at **22** — no tab bar, no title bar, a clean baseline.

**CONFIRMED: R2 loses the toggle on every new tab and every new OS window.** Together with the
drag-clear (`~/kitty-482/kitty/tabs.py:1918-1926`) that is three independent ways for R2 to silently
fall out of sync with what the user last pressed.

---

## 6. RECOMMENDATION — R3: one C action, one process-global flag, one dirty sweep

### 6.1 Why this shape and not the other two

| Requirement | R1 conf swap | R2 per-tab bool | **R3 global flag** |
|---|---|---|---|
| reaches every pane of every tab of every OS window | yes (§5.2) | **no** (§5.1) | yes — the draw path reads a process global |
| no relayout | **no** — 1 relayout per tab, per press | **no** | **yes** — nothing calls `Layout.__call__` |
| no PTY resize / SIGWINCH | yes, *if* the band steals no rows | yes, same caveat | yes |
| cost per press | **~12 ms kitty CPU** (§5.3) | ~1.2 ms + a PTY resize | one bool write + N `needs_render` writes |
| survives a drag | yes | **no** (`tabs.py:1918-1926`) | yes |
| survives a new tab / OS window | yes | **no** (§5.5) | yes |
| survives an unrelated reload | yes, via a fragile `include` (§4.2, §5.4) | yes | yes, structurally (§4.4) |
| needs a state file on disk | **yes** — and it desyncs on restart, as the script's own comment admits | no | no |

R3 is the only column with no "no".

### 6.2 The exact change set (v0.48.2 line numbers)

**(1) `kitty/state.h` — the flag.** Add beside the existing runtime bool
`bool redirect_mouse_handling;` at `~/kitty-482/kitty/state.h:499`:

```c
bool show_window_title_bands;
```

It must go in `GlobalState`, **not** in `Options`. `set_options` at
`~/kitty-482/kitty/state.c:943-963` writes only `is_apple`, `has_render_frames`, `is_wayland`,
`debug_rendering`, `debug_font_fallback`, `opts` and `options_object` — so a new `GlobalState` field
is untouched by every config reload, which is the whole of §4.4.

**(2) `kitty/state.c` — the setter, which also does the dirty sweep.** Model it on
`~/kitty-482/kitty/state.c:1697-1700` (`redirect_mouse_handling`), registered at
`~/kitty-482/kitty/state.c:1816`:

```c
PYWRAP1(toggle_window_title_bands) {
    int mode = -1;  // -1 toggle, 0 off, 1 on
    PA("|i", &mode);
    global_state.show_window_title_bands = (mode < 0) ? !global_state.show_window_title_bands : (mode != 0);
    for (size_t i = 0; i < global_state.num_os_windows; i++)
        global_state.os_windows[i].needs_render = true;      // <-- EVERY OS window, §3.1
    if (global_state.show_window_title_bands) Py_RETURN_TRUE;
    Py_RETURN_FALSE;
}
```

Doing the sweep in C rather than as N Python `mark_os_window_dirty(...)` calls is strictly better: one
call, no per-OS-window Python/C boundary crossing, and it cannot forget a window. The loop shape is
copied from `render()` at `~/kitty-482/kitty/child-monitor.c:1000-1001`. Register with
`MW(toggle_window_title_bands, METH_VARARGS)` next to line 1816, and add the stub to
`kitty/fast_data_types.pyi` beside `mark_os_window_dirty` at line 1397.

Returning the resulting bool means **C owns the single source of truth**. No Python mirror, no state
file, and the restart desync documented at length in
`claude-infrastructure/scripts/kitty-pane-title-toggle.sh` (its own comment: *"after a kitty restart
the file may still read `on` while the fresh instance is showing the OFF config … One dead press"*)
cannot occur.

**(3) `kitty/shaders.c` — the predicate, in BOTH places.** A new
`static bool has_title_band(Window *w) { return global_state.show_window_title_bands && w && w->title; }`
next to `has_window_number` at `~/kitty-482/kitty/shaders.c:933-937`, then:

- 🚨 add `|| has_title_band(w)` to the `has_ui` disjunction in `screen_needs_rendering_in_layers`,
  `~/kitty-482/kitty/shaders.c:1316-1320`. **Without this the toggle is silently a no-op on any pane
  that has no scrollbar, no image, no logo and no progress bar**, because
  `draw_cells_without_layers` (`~/kitty-482/kitty/shaders.c:1344-1346`) draws no UI chrome at all.
  This is the single highest-risk detail on this axis (§2.4).
- add `draw_title_band(ui);` to `draw_cells_with_layers` beside `draw_window_number(ui);` at
  `~/kitty-482/kitty/shaders.c:1382`. The body is one line — `render_a_bar(ui, &ui->window->title_bar_data, ui->window->title, false)`
  — which is **already written and already shipping** at `~/kitty-482/kitty/shaders.c:943`.

**(4) `kitty/boss.py` — the action.** Anywhere near `toggle_window_title_bars`
(`~/kitty-482/kitty/boss.py:3480-3505`):

```python
@ac('win', '''
    Toggle a per-window title band drawn outside the cell grid

    Unlike :ac:`toggle_window_title_bars` this steals no text row, causes no relayout
    and no PTY resize, and applies to every window of every tab of every OS Window.
    ''')
def toggle_window_title_band(self, which: str = 'toggle') -> None:
    from .fast_data_types import toggle_window_title_bands
    toggle_window_title_bands({'off': 0, 'on': 1}.get(which, -1))
```

No registration is needed beyond the method itself: `Boss.dispatch_action` resolves an action by
`getattr(self, key_action.func, None)` at `~/kitty-482/kitty/boss.py:1865`, and an **argless** action
name is accepted by `parse_key_action` with no validation at all
(`~/kitty-482/kitty/options/utils.py:1172-1176`: `if len(parts) == 1: return KeyAction(func, ())`).

> ⚠️ **Trap that falls straight out of that line:** because an argless action name is never validated,
> a typo in the `map` line is a **silent no-op** — no config error, no bad-config-lines dialog, no log
> entry. `map cmd+shift+b toggle_window_title_bands` (plural — the C function's name) would parse
> cleanly and do nothing forever. Only the `on`/`off` forms, which carry an argument, would raise
> `Unknown action` (`~/kitty-482/kitty/options/utils.py:1180`). Verify the binding fires before
> believing it.

### 6.3 What it costs per press

One bool write, plus `num_os_windows` bool writes (5 on this machine). No Python loop, no layout, no
`set_geometry`, no `screen.resize`, no `resize_child`, no config parse, no font work, no menu rebuild.
The next tick redraws — and the tick is already requested by the key press itself
(`~/kitty-482/kitty/glfw.c:537` `request_tick_callback()` at the end of `key_callback`). Bound to
visible: one `repaint_delay`, which the operator's `config/kitty.conf:747` sets to **16 ms**
(kitty's default is 10 ms, `~/kitty-482/kitty/options/types.py:639`). UNMEASURED end-to-end — no build
was made — but there is no timer, no debounce and no polling anywhere on that path, against today's
overlay daemon's **2-second** re-assert.

### 6.4 The two things the toggle must ALSO reach, named so they are not forgotten

1. **The hit test.** `mouse_region` at `~/kitty-482/kitty/mouse.c:1067-1081` tests
   `contains_mouse(win)` first and only falls to the title-bar band in the `else if`. Whatever
   band-hit-test arm the design adds must be gated on the same `global_state.show_window_title_bands`
   — `mouse.c` already reads `global_state` and `OPT(...)` freely (e.g. `OPT(scrollbar_interactive)`
   at `~/kitty-482/kitty/mouse.c:1085`), so the global is reachable there for free. A per-tab or
   per-Options flag would not be.
2. **`render_a_bar` re-uploads its texture every frame.** `~/kitty-482/kitty/shaders.c:860-868`:
   `glGenTextures` → `glTexImage2D(...)` → draw → `free_texture(&data.texture_id)` on **every call**,
   even when `bar->buf` is unchanged (the text-render cache at `:851-858` is skipped, the upload is
   not). At 9 panes × ~1000 px × 47 px × 4 B that is ~1.7 MB of PBO traffic per frame while the band
   is ON. Not a toggle defect and not mine to fix, but it is the reason the toggle **must** actually
   turn the band OFF rather than draw it transparently — flagged for the render axis.

---

## 7. The exact conf lines

Replace `claude-infrastructure/config/kitty.conf:535` — today's two-`launch` combine chord —
with a single action:

```conf
# ⌘⇧B — the per-pane title band. One kitty action, one process-global flag, one dirty sweep.
# No relayout, no PTY resize, no SIGWINCH, no config reload, no state file, no daemon.
# Reaches every pane of every tab of every OS Window (kitty/state.c, the needs_render sweep).
map cmd+shift+b toggle_window_title_band

# Deterministic forms, for scripts and for recovering from a desync (there is none, but):
#   kitty @ action toggle_window_title_band on
#   kitty @ action toggle_window_title_band off
```

**Nothing else changes.** Specifically:

- `window_padding_width 0 5 0 5` **stays as it is.** The reservoir/paired-padding machinery
  (`config/kitty-title-on.conf`, `scripts/kitty-pane-title-toggle.sh`) exists only to compensate a
  stolen row. R3 steals no row, so there is nothing to compensate. Both files become dead and should
  be retired **only after** R3 is live — they are the working fallback until then.
- `window_title_bar_min_windows 0` **stays as it is.** It governs the real, row-stealing bars and
  must keep governing them, because ⌘⌥B (`config/kitty.conf:537+`) still uses them for the
  deliberate reorder drag. R3 is orthogonal to it.
- `auto_reload_config` stays at its default 0.1 s. R3 needs no protection from a reload (§4.4), so
  the `deploy-live` fast-forward of `config/kitty.conf` is a non-event for the band.
- The overlay daemon `scripts/kitty-pane-title-overlay.py` and the toggle script
  `scripts/kitty-pane-title-toggle.sh` are both retired by this, along with their socket, their 2 s
  timer, their Pillow dependency and their on-disk state file.

### 7.1 Optional follow-on: a startup default, done so it cannot eat the toggle

If the operator later wants the band ON by default at launch, add `window_title_band yes|no` as a
real option **and seed the global only when the option's value CHANGED across the reload**. kitty
already computes exactly that shape in the same function —
`~/kitty-482/kitty/boss.py:3147-3149`:

```python
bg_before = get_options().background
...
configured_color_scheme_changed = bg_before.is_dark != opts.background.is_dark
```

So in `apply_new_options`, capture `band_before = get_options().window_title_band` before
`set_options(...)` and only call the setter when `band_before != opts.window_title_band`. An
unrelated reload (value unchanged) then leaves the runtime toggle exactly where the user put it,
while a deliberate edit to `kitty.conf` does take effect. **Seeding it unconditionally would
re-introduce R1's defect** — every `deploy-live` config fast-forward would silently snap the band
back to the configured default, mid-session, with no tell.

I would ship R3 without the option first. It is strictly less code and there is no evidence the
operator wants a launch default — ⌘⇧B has always been a press.

---

## 8. What I did not measure

| Claim | Status |
|---|---|
| Latency from keypress to the band appearing | **UNMEASURED.** Derived from source as ≤ one `repaint_delay` = 16 ms on this config. Needs a build. |
| That `render_a_bar` at the top of a window draws correctly with no relayout | **UNMEASURED.** `~/kitty-482/kitty/shaders.c:943` proves the call exists and compiles in that position; it does not prove the geometry is right for a band at `screen_top`. The lead's design axis owns this. |
| The `needs_layers` trap (§2.4) actually biting | **UNMEASURED** — it is a source reading of `~/kitty-482/kitty/shaders.c:1344-1346` + `:1448`. It cannot be tested without a build. Treat it as the first thing to check if the toggle looks flaky. |
| `~/kitty-dev` (master) divergence on any of the above | **UNMEASURED.** I read v0.48.2 only, as that is the build the operator runs. Every citation above names `~/kitty-482`. Anyone porting to master must re-read `shaders.c`, `child-monitor.c` and `boss.py` there — the brief warns the trees differ materially, and `docs/patches/kitty-mouse-drag-window-v0.48.2.patch` already documents three v0.48.2-vs-master divergences in these exact files. |
| Per-press cost of R3 | **UNMEASURED** (no build). The R1 and R2 numbers in §5.3 are measured; R3's is an operation count, not a timing. |

---

## 9. Appendix — the rig, verbatim, so every number in §5 is re-derivable

### 9.1 Sandbox setup (safe: never touches pid 597)

```bash
mkdir -p /private/tmp/ktb-toggle
cat > /private/tmp/ktb-toggle/base.conf <<'EOF'
font_family Monaco
font_size 18.0
modify_font cell_height 94%
window_padding_width 0 5 0 5
window_title_bar_min_windows 0
window_title_bar_align left
window_border_width 1pt
draw_minimal_borders no
placement_strategy top
repaint_delay 16
auto_reload_config -1
confirm_os_window_close 0
enabled_layouts splits,stack
allow_remote_control yes
map ctrl+f1 toggle_window_title_bars
EOF
printf 'include base.conf\nwindow_title_bar_min_windows 1\n' > /private/tmp/ktb-toggle/on.conf

env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID nohup \
  /Applications/kitty.app/Contents/MacOS/kitty \
  --config /private/tmp/ktb-toggle/base.conf \
  --listen-on unix:/private/tmp/ktb-toggle/sock \
  --instance-group ktbtoggle --title KTB-TOGGLE-SANDBOX \
  -o allow_remote_control=yes >/private/tmp/ktb-toggle/kitty.log 2>&1 &

K() { env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
      /Applications/kitty.app/Contents/MacOS/kitty @ --to unix:/private/tmp/ktb-toggle/sock "$@"; }
```

Teardown was `K action quit` (kitty's own `@ac('win', 'Quit, closing all windows')`,
`~/kitty-482/kitty/boss.py:2191`) — verified gone, and the live instance re-read afterwards and
unchanged. Note `kitty @ close-os-window` is **not** a subcommand in 0.48.2 (measured:
`Error: close-os-window is not a known subcommand for @`); the action is the route.

### 9.2 The CPU-time instrument, and the instrument that FAILED first

**Failed first — recorded because it would otherwise be re-attempted.** Wall-clock timing of the
remote command is useless here: `/usr/bin/time -p` over 10 runs each gave
`ls` 0.03-0.05 s, `load-config` 0.03-0.05 s, `action toggle_window_title_bars` 0.03 s — **the three
arms are indistinguishable**, because the ~30-50 ms client-side RPC (process spawn + socket) swamps
everything and `time -p` resolves only to 10 ms. A null result from that instrument is a fact about
the client, not about kitty.

**What worked** — kitty's own cumulative CPU across 100 calls:

```bash
SPID=$(pgrep -f "listen-on unix:/private/tmp/ktb-toggle/sock" | head -1)
cput() { ps -o time= -p "$1" | tr -d ' '; }
a0=$(cput $SPID); for i in $(seq 1 100); do K ls >/dev/null; done; a1=$(cput $SPID)
b0=$(cput $SPID); for i in $(seq 1 100); do K load-config --ignore-overrides /private/tmp/ktb-toggle/base.conf; done; b1=$(cput $SPID)
c0=$(cput $SPID); for i in $(seq 1 100); do K action toggle_window_title_bars; done; c1=$(cput $SPID)
d0=$(cput $SPID); for i in $(seq 1 100); do K ls >/dev/null; done; d1=$(cput $SPID)
```

Raw output, 2 OS windows / 4 panes:

```
ARM A: 100 x (kitty @ ls)                     0:00.76 -> 0:00.93     (0.17 s)
ARM B: 100 x (load-config base.conf)          0:00.93 -> 0:02.20     (1.27 s)
ARM C: 100 x (action toggle_window_title_bars) 0:02.21 -> 0:02.50    (0.29 s)
ARM D: 100 x (kitty @ ls)  [control re-run]   0:02.50 -> 0:02.67     (0.17 s)
```

3 OS windows / 13 panes:

```
ARM A2: 100 x (kitty @ ls)                    0:02.87 -> 0:03.13     (0.26 s)
ARM B2: 100 x (load-config base.conf)         0:03.13 -> 0:04.61     (1.48 s)
```

The A/D pair reproducing at 0.17 s is the positive control. Arm B loads an **identical** config over
itself, so its excess is pure `apply_new_options` and nothing else.

### 9.3 Why this is a ratio, not an absolute

Every arm ran on the same idle sandbox within the same few minutes, through the same client, against
the same binary. The claim it supports is *"a no-op `load-config` costs ~9× a full relayout"*, which
is a within-rig comparison. It does **not** support any absolute latency claim, and §3.3 is marked
UNMEASURED for exactly that reason.

---

## ADVERSARIAL VERIFICATION

Verifier: adversarial agent, 2026-09-16. Method: every `file:line` re-opened in the tree it names
(`~/kitty-482` @ `2cb1d95c3`, `~/kitty-dev` @ `1d67ecd47`), and every measured claim re-run on a
fresh sandbox kitty 0.48.2 (`/private/tmp/ktb-adv-toggle/sock`, instance-group `ktbadv`, pid 30360,
torn down with `@ action quit`). The operator's live pid 597 was read once, read-only, and never
written. **No citation was found in the wrong tree.** All eight claims' citations resolve within ±2
lines of where they are cited.

**Headline: the design survives. The cost argument's arithmetic does not, and §2.4's stated failure
mode is wrong in a way that would send a debugger to the wrong granularity — and would be MASKED
during validation by the very daemon §7 says to retire last.**

### What I re-measured and UPHELD

| Claim | Verdict | My evidence |
|---|---|---|
| 1 — `toggle_window_title_bars` reaches one OS window | **UPHELD, and now with the positive control the original lacked** | Reproduced exactly (2 OSW × 2 panes, focus OSW2: `OSW1 [22,22] OSW2 [22,22]` → press → `OSW1 [22,22] OSW2 [21,21]` → press → back). The original ran only the negative direction. I added the arm that could have refuted it: focus **OSW1**, press → `OSW1 [21,21] OSW2 [22,22]`. The instrument can see OSW1 move; it is the action that does not reach across. |
| 3 — `load-config` reaches all OS windows | **UPHELD** | Reproduced: `on.conf` → `OSW1 [21,21] OSW2 [21,21]`; `base.conf` → both `[22,22]`. |
| 4 — `force_show_title_bars` not inherited; cleared by any drag | **UPHELD** | Inheritance reproduced to the row: forced ON in OSW3 (9 panes) → `tab3 [21×9]`; `launch --type=tab` → `tab3 [20×9], tab4 [21]`; `launch --type=os-window` → `OSW4 tab5 [22]`. Drag-clear re-read: `~/kitty-482/kitty/tabs.py:1918-1926` walks `boss.all_tab_managers`, and `on_window_drop` calls it **unconditionally at the top of the function, before any drop-position test** (`~/kitty-482/kitty/tabs.py:2032` region) — so a no-op drop clears it too. Confirmed, not merely asserted. |
| 6 — a `GlobalState` flag survives `set_options` | **UPHELD, exact** | `~/kitty-482/kitty/state.c:943-963` writes only the seven named fields; `bool redirect_mouse_handling;` is at `state.h:499`, setter `state.c:1697-1700`, registered `state.c:1816`. |
| 7 — `set_window_char` is the right precedent | **UPHELD with one correction (below)** | `screen.c:4963-4969`, `screen.h:172`, `boss.py:1721`, `boss.py:365`, `shaders.c:933-936`, `shaders.c:943` all say what is claimed. |
| 8 — `os_window_font_size(force=True)` is not a PTY resize | **UPHELD, exact** | `state.c:1299-1317`, `state.c:492-499`; the SIGWINCH path is `window.py:1059` (`render_ynum = ynum - 1`) → `window.py:1077` (`screen.resize`), cheap fall-through `window.py:1088`. (Cited as 1058/1078; off by one.) |
| §4.2 / §5.4 — a variant load makes `all_config_paths` sticky | **UPHELD** | Reproduced: after `load-config --ignore-overrides on.conf`, two successive **bare** `kitty @ load-config` calls (byte-identical to the SIGUSR1 watcher's `load_config_file(NULL)`) left every pane at 21. Then `base.conf`, then bare → 22. Sticky in both directions. `config.py:192` is exact. |
| §3.3 — `input_read` is PTY output, not a key press | **UPHELD, exact** | `child-monitor.c:1399-1407`: `input_read` is set only by `process_pending_resizes` and `parse_input`. A key press does not set it, so the ≤ one `repaint_delay` bound is the right worst case. `config/kitty.conf:747` really is `repaint_delay 16`; `options/types.py:639` really is `10`. |

### OVERTURNED — claim 2, the cost arithmetic

The **conclusion** (do not use `kitty @ load-config`) stands and is if anything stronger. Three of
the four numbers supporting it do not.

**(a) `kitty @ ls` is not an RPC floor — it is a 31 KB JSON serialization, and using it as the floor
is what produced the "+1.2 ms relayout" figure.** Measured: `kitty @ ls` = 1.7–1.9 ms/call of kitty
CPU and returns 31,243 bytes. A genuine minimal round trip (`kitty @ ls --match id:99999`, which
errors *inside kitty*, rc=1) = **0.40–0.45 ms/call**, reproduced as a bracketing control on both
sides of every arm below. So the report's "**+11.0 ms above floor**" should read *+12.3 ms above a
0.4 ms floor*, and "**7.5× the RPC floor**" should read **~20–35× the RPC floor**.
*(A cheaper candidate floor — `kitty @ env` — reads 0.00 s over 300 calls twice, and I discarded it
rather than publish it: `env` with no argument aborts **client-side** with rc=0 and never reaches
kitty. A floor arm that never contacts the subject is a blind instrument, and it would have made the
overturn look twice as large as it is.)*

**(b) "The cost is mostly FIXED, not per-pane" is REFUTED.** Paired, one variable, same minute,
floor re-run either side:

| | floor | `load-config` no-op | `toggle_window_title_bars` |
|---|---|---|---|
| 4 OS windows / 15 panes | 0.45 ms | **15.75 ms** | 1.70 ms |
| 1 OS window / 2 panes | 0.40 ms | **8.10 ms** | 1.00 ms |

**+94 % for 2 → 15 panes.** The report's basis for "fixed" was 11.0 → 12.2 ms across 4 → 13 panes
(+11 %) — which is *inside* the noise band its single-shot protocol could not see (below). The
practical consequence inverts the report's inference: the operator does **not** "pay roughly the same
~12 ms"; he pays more as he opens panes. (Aside: the brief's "5 OS windows, 9 panes" is stale — pid
597 read 2 OS windows / 4 panes today.)

**(c) The single-shot protocol cannot support a point estimate.** Eight `load-config` arms on one
box, one binary, one instance, inside 30 minutes, at fixed pane counts for six of them, spanned
**5.3 – 28.5 ms/call** — a 5.4× range — while the floor and the toggle arm stayed stable to ±0.1 ms.
The report's `~11-12 ms` is a legitimate draw from that distribution, not a property of the
operation. Anyone re-running this must bracket every arm with a re-run floor (the report did do this
for `ls`, which is the one piece of its protocol I would keep) **and** hold pane count and OS-window
visibility fixed.

**(d) The "9×" headline is right, by luck.** Ratio of *totals* against a valid floor: **9.3× at 15
panes, 8.1× at 2 panes.** So the recommendation's load-bearing number survives — but it was derived
by subtracting an over-heavy floor from both arms, which is why its "+1.2 ms full relayout" is wrong
(that arm's true total is 1.0–1.7 ms, of which 0.4 ms is transport). Fix the derivation, keep the
number.

**(e) One mechanism hypothesis tested and REFUTED, recorded so it is not re-attempted.** I suspected
the bill was really the renders triggered by `w.refresh(reload_all_gpu_data=True)`
(`~/kitty-482/kitty/boss.py:3186`). Discriminating arm, one variable, control-bracketed: same conf
loaded over itself with `repaint_delay 1000` instead of `16` → 12.50 ms vs 15.95 ms, control re-run
16.25 ms. Throttling rendering 60× removes only ~22 % of the cost. **The report's attribution —
parse, font re-resolve, `cocoa_recreate_global_menu`, keymap rebuild — is correct.**

Also incomplete rather than wrong: the §1.3 table omits `set_layout_options(opts)` and
`set_default_env(...)` at `~/kitty-482/kitty/boss.py:3153-3154` and the `theme_colors.refresh()`
block at `:3170-3175`. Direction unchanged.

### OVERTURNED — claim 5's failure MODE (the edit itself is upheld, and is the right #1 risk)

`needs_layers` is **one bool per OS WINDOW**, not per pane: `~/kitty-482/kitty/state.h:436`
`bool focused_at_last_render, needs_render, needs_layers;`. It is OR-accumulated in
`prepare_to_render_os_window` at `~/kitty-482/kitty/child-monitor.c:757-786` over (i) OS-window-level
terms — `!supports_framebuffer_srgb`, `effective_os_window_alpha < 1`, `live_resize.in_progress`,
a background image; (ii) the **tab-bar** screen (`:770`); (iii) `cursor_trail` (`:781`); and (iv)
`screen_needs_rendering_in_layers` for every visible window of the **active tab only** (`:786`).
The branch at `~/kitty-482/kitty/shaders.c:1448` then reads that single OS-window bool for every
pane it draws.

> **Corrected claim.** Omitting `has_title_band(w)` from the `has_ui` disjunction does **not** make
> the toggle "work on some panes and not on others". It makes it **all-or-nothing per OS WINDOW**,
> and it flips with transient state: a scrollbar that appears on hover (`has_scrollbar` →
> `w->scrollbar.is_hovering`, `shaders.c:823-834`), `screen->scrolled_by > 0`, a hyperlink hovered
> with the configured modifier, a visual bell, a cursor trail, a live resize, **or any graphics image
> anywhere in the active tab**. The diagnostic signature to look for is *"the band appears and
> disappears across a whole OS window as I move the mouse or scroll"* — not *"it's flaky per pane"*.

🚨 **NEW RISK the report does not name, and it inverts the validation order §7 prescribes.**
`grman_has_images` (`~/kitty-482/kitty/graphics.c:2497`) returns true if a screen holds **any**
placement. The operator's overlay daemon is **running right now** — pid 97219,
`~/.claude/scripts/kitty-pane-title-overlay.py daemon --initial=toggle` — and it places a PNG in
every pane. So on the live instance, and in any sandbox where that daemon is up, `needs_layers` is
already TRUE everywhere, and an R3 build that **omits the mandatory disjunction edit would validate
perfectly** — then break on the day the daemon is retired, which is exactly the order §7 recommends
("retire … only AFTER R3 is live"). **Validate R3 with the overlay daemon STOPPED**, or the one
highest-risk detail on this axis is structurally unobservable during acceptance.

### NEW — the change set is FIVE edits, not four, and the missing one is MEASURED

§7's documented deterministic forms do not work as written. Measured on the sandbox, with both
controls:

```
kitty @ action toggle_window_title_bars on   -> rc=0, NOTHING HAPPENS,
                                                and kitty opens a window titled
                                                'Failed to parse action'
kitty @ action definitely_not_an_action_xyz  -> rc=1  Error: Unknown action:  (positive control)
kitty @ action toggle_window_title_bars      -> rc=0, rows 22 -> 21           (negative control)
```

Mechanism: with an argument, `parse_key_action` (`~/kitty-482/kitty/options/utils.py:1177-1180`)
looks the name up in `func_with_args`, finds nothing, and raises `KeyError`. `Boss.combine`
(`~/kitty-482/kitty/boss.py:1913-1915`) catches it, calls `show_error(...)` — which spawns a real
window — and **returns True**, so `rc/action.py:74`'s `if not consumed` never fires and the RPC
reports success. And because `parse_map` (`utils.py:1473-1488`) stores the action **string** and
`resolve_aliases` parses it lazily (`utils.py:1256`), a `map cmd+shift+b toggle_window_title_band on`
line **passes config load silently and fails on every key press** with that same error window.

> **Corrected recommendation.** The bare form `map cmd+shift+b toggle_window_title_band` is fine.
> The `on`/`off` forms require a **fifth edit**: a `@func_with_args('toggle_window_title_band')`
> parser in `~/kitty-482/kitty/options/utils.py` returning `(func, [which])`. Until that exists,
> delete the two `kitty @ action toggle_window_title_band on|off` lines from §7's conf block — as
> written they are a documented command that reports success and opens an error window.
> (§6.2's trap note is right that a *typo* in a map line is silent; it is wrong that the on/off forms
> "would raise Unknown action" usefully — they raise it where nothing surfaces it to the caller.)

### NEW — §6.2's `draw_title_band` would thrash a cache it shares with the URL bar

`~/kitty-482/kitty/state.h:276` gives each Window **one** `WindowBarData title_bar_data` (plus
`url_target_bar_data`, used only to cache the sanitized URL *object*). `draw_hyperlink_target`
renders through `&window->title_bar_data` (`shaders.c:929`) and so does `draw_window_number`
(`:943`). `render_a_bar`'s cache key is `bar->last_drawn_title_object_id != title` (`:851`). With the
band drawn **every frame**, hovering a hyperlink alternates two different title objects through one
cache slot, so every frame takes the miss branch and re-runs `draw_window_title` → CoreText
(`:854-855`) — not merely the per-frame texture upload §6.4 already flags. They would also occupy the
same top viewport. **Fix: add a dedicated `WindowBarData title_band_data;` beside `state.h:276` and
render the band through that.**

### NEW — two macOS render gates missing from §3.1, and what they imply

`render_os_window` returns early, **without clearing `needs_render`**, when
`!should_os_window_be_rendered(w)` (`~/kitty-482/kitty/child-monitor.c:952`; defined
`~/kitty-482/kitty/glfw.c:2578` as *potentially visible* **and** *swaps allowed*) and, because
`has_render_frames` is true on Apple (`state.c:951-953`), when `w->render_state != RENDER_FRAME_READY`
(`child-monitor.c:956-966`, re-requested after 250 ms).

Consequence, and it is a **simplification** of the recommendation rather than a defect: because the
flag is a process global read per frame, nothing can desync — an OS window that is occluded, minimised
or on another Space simply picks the band up when it next renders. **The `needs_render` sweep is an
immediacy optimisation, not a correctness requirement**, so the ≤ one `repaint_delay` bound in §6.3
should be stated as *≤ one `repaint_delay` for OS windows that are currently renderable*.

### NEW — two guards dropped when §6.2 quotes `shaders.c:943`

The shipped call is guarded at `~/kitty-482/kitty/shaders.c:941`:
`if (ui->window->title && PyUnicode_Check(ui->window->title) && (requested_height > (ui->cell_height + 1) * 2))`.
§6.2's predicate is `w && w->title` and its draw body is the bare `render_a_bar(...)` line. But
`render_a_bar` calls `PyUnicode_AsUTF8(title)` at `:854` with **no type check** of its own, so a
non-`str` title is a NULL deref. **Copy the guard, not just the line** — including the minimum-height
test, which is what stops the band being drawn into a pane too short to hold it. Note also
`render_a_bar` returns `cell_height + 2 + 2*border_width` (`:838`, `:871-873`), i.e. **51 px at this
config, not one 45 px cell** — the band is taller than the row it covers. That belongs to the render
axis, but it is the number §6.4's "~1.7 MB/frame" estimate is built on and it checks out.

### Minor corrections

- §2.1's quoted `toggle_window_title_bars` body omits `~/kitty-482/kitty/boss.py:3501`
  `if not naturally_visible:` — the action is a **no-op on any tab whose bars are already naturally
  visible**. This does not change its reach, but it means arm C of §5.3 is not uniformly "a full
  relayout", and it is part of why that arm's cost moves.
- `~/kitty-dev` (master) carries byte-identical logic for `screen_needs_rendering_in_layers`
  (`shaders.c:1742-1747`), the title `render_a_bar` call (`shaders.c:1367`),
  `redirect_mouse_handling` (`state.h:622`) and the `needs_render, needs_layers` fields
  (`state.h:539`) — so R3 **ports** to master, but every line number differs by ~400. The report was
  right to scope to v0.48.2; an upstream PR needs the master line numbers re-derived, not translated.

### Verdict

**Ship R3 — the mechanism is sound and every structural claim under it verified.** Before writing
code, apply: the fifth edit (or delete the on/off lines), the dedicated `WindowBarData`, the copied
`PyUnicode_Check` + height guards, and — the one that decides whether acceptance means anything —
**kill the overlay daemon before testing, or `needs_layers` will hide the bug you are testing for.**
