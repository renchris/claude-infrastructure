# Upstream feature request for kitty — a bindable mouse action that begins a window drag

**Status: DRAFT FOR THE OPERATOR'S REVIEW. Not posted anywhere. No GitHub issue has been opened.
Nothing has been sent.** Written 2026-09-16 at the operator's request, in this file only. The
operator reads § 3 and decides; if he approves, § 4 says how to post it and what to expect.

The ask, in one sentence: kitty should expose a bindable mouse action that begins a window drag
at the pointer, so a front-end can put the drag-to-reorder gesture on a region it draws itself.

## 1. Prior-art search — verdict: nobody has asked for this, but the maintainer predicted it

Searched 2026-09-16 with `gh search issues`, `gh search prs` and a GraphQL discussion search over
`kovidgoyal/kitty`, open and closed, then read the hits in full. Queries: "window title bar font",
"window_title_bar", "toggle_window_title_bars", "drag to reorder", "drag reorder window", "title
bar height", "custom title bar", "drag window mouse action", "window title font", "mouse_map drag",
"title bars", "window titles drag", "drag windows", "rearrange windows mouse", "move window drag",
"window title bar", "titlebar window", "drag split", "window title bar drag", "drag window title",
"title bars drag reorder"; discussions: "window title bar", "drag reorder window", "title bar font".

| Item | What it is | Why it matters here |
|---|---|---|
| Discussion #9448 (2026-02-01, Ideas) | mcrmck's interest check for per-window labels in splits | Origin of the feature. Maintainer: dedicating space to titles "is not a very good tradeoff", but an option defaulting to off "is fine by me". |
| PR #9450 (merged 2026-03-05) | "Add optional window title bars for window splits" | Introduced `window_title_bar*`, `window_title_template`, and the `draw_window_title(data)` hook. Maintainer, in review: *"I am 100% certain other people are going to want to make the bars interactive… And drag them around to re-order… Whole can of worms."* and *"draggable window title bars would be an important feature, possibly with a mappable action that when triggered shows the title bars and then auto hides them after the drag operation is completed."* |
| Issue #9619 (closed 2026-03-08, enhancement) | mcrmck's design questions for the drag | Maintainer answered the drop model (drop on a bar = swap, drop in a quadrant = insert in that direction, all layouts, across tabs and OS windows) and closed it: "feel free to ask if you have more questions". |
| PR #9626 (merged 2026-03-28) | "Add draggable window title bars" | Shipped in 0.48: the drag, `toggle_window_title_bars`, the drop overlay, tab-bar targets, detach on drop outside. Changelog 0.48.0: "Allow drag and drop of windows to re-arrange them… See `toggle_window_title_bars` (#9626)". |
| Issue #8907 (closed same day, 2025-08-17) | "Add option to change window title font in visual_window_select_characters modes" | Maintainer: *"I am afraid I am not interested in making this configurable, sorry. A proportional font rather than the terminal font was deliberately chosen"*. The nearest precedent for a bar-font option, and it was declined. |
| Issues #9620, #10222 | Bugs in the window drag (segfault with `window_title_bar_min_windows 1`; "+" tab drop on Wayland) | Both fixed; the drag is a maintained feature, not an experiment. |
| Issue #7407 (2024) | "Customize Window Title Bar like macOS Default Terminal" | About the OS window title; unrelated. |

**No issue, PR or discussion asks for either of the two things below** — a mappable action that
begins a window drag, or a font/height option for the window title bar. The closest thing on the
tracker is the maintainer's own sentence in #9450 quoted above.

**Master has not moved on this since 0.48.2.** Read at `1d67ecd47c0b` (2026-09-16T11:51Z):
`kitty/options/definition.py` still defines exactly the seven `window_title_bar*` options and no
font or height option; the `0.49.0 [future]` changelog section has no title-bar entry; the only
mappable action that starts any drag is still `debug → test_dragging`, which starts a text drop
with the kitty logo as the drag image. One relevant precedent did land for 0.49: `mouse_selection
drag_or_normal_select`, a `mouse_map` action that begins a drag-and-drop (of the selection) at the
pointer, gated by `drag_threshold`. It is the exact shape of the ask, applied to text instead of
windows.

**Recommendation: open a NEW issue with the Feature request template, cross-referencing #9450,
#9619 and #9626.** Not a comment on #9619 — that is a contributor's implementation Q&A, closed six
months ago, and a comment there gets no label and no fresh eyes. Not a discussion — the concrete
API belongs on the tracker, where #8907 and the like live.

## 2. Conventions checked

`.github/ISSUE_TEMPLATE/feature_request.md` (label `enhancement`) has four headings, reproduced
verbatim in the draft: *Is your feature request related to a problem? Please describe.* / *Describe
the solution you'd like* / *Describe alternatives you've considered* / *Additional context*.
`CONTRIBUTING.md` asks for a search of existing reports first (done, § 1), version + OS + config
for bugs (given anyway), and says plainly: *"bugs and feature requests are often closed quickly as
they are either fixed or deemed wontfix/invalid… Feel free to continue to post to a closed bug
report… Being closed does not mean you will not get any more responses."* For code: *"If it's a
large/controversial change, open an issue beforehand to discuss it."* This IS that issue.

## 3. The draft, verbatim — copy from the first line of the title to the last line of the block

Title:

```
Mouse action to start a window drag from the pointer, so custom-drawn window chrome can carry drag-to-reorder
```

Body:

```markdown
**Is your feature request related to a problem? Please describe.**

Since 0.48 a kitty window can be dragged to re-order it, move it to another tab or detach it
(#9626). The only thing that begins that drag is a left press inside the built-in window title
bar. That bar is one row of the terminal's monospace font, allocated from the cell grid, and it
can be styled by colour and alignment only.

A front-end can draw a better header itself with the graphics protocol — a proportional face, a
chosen size, its own band height — and it costs the grid nothing, because a placement paints over
the glyphs instead of taking a row, so no window is resized and nothing gets a SIGWINCH. But that
header is pixels; kitty does not know it exists, so it cannot be dragged. Today you must choose
between the typography and the gesture. The two properties are orthogonal in principle and are
coupled only because the region that starts a drag is private to the title bar.

**Describe the solution you'd like**

A mappable mouse action that begins a window drag for the window under the pointer, usable from
`mouse_map`, unmapped by default (like `toggle_window_title_bars`):

    mouse_map ctrl+alt+left press grabbed,ungrabbed mouse_drag_window

Semantics: on the press, the window under the pointer becomes the drag source, exactly as a press
inside its title bar does today. Once the pointer has moved farther than `drag_threshold` the
existing drag starts — thumbnail, drop overlay and quadrant insert, tab-bar targets, detach on a
drop outside kitty. Nothing about drop handling changes. With a modifier chord the action works
whether or not the program in the window has grabbed the mouse, the same way
`click_url_or_select_grabbed` does, which matters because the windows in question usually run a
full-screen TUI.

The region is then the front-end's to draw, and the title bars do not need to be visible for the
drag from my side. If the drop-on-a-bar-to-swap target needs them, force-showing them for the
duration of the drag, as `start_window_drag` does today, is fine.

Reading master (1d67ecd4), the machinery already seems factored for this and I mention it only
as an observation, not a claim about the size of the patch: `TabManager.handle_window_title_bar_mouse`
on a left press does `set_active_window` + `set_window_being_dragged(window_id, False, x, y)`;
its motion branch promotes that past `drag_threshold` via `request_thumbnail` →
`Boss.start_window_drag`; and `mouse.c` routes motion and release to that handler whenever
`global_state.window_being_dragged.id` is set, independent of the title-bar hit test. The
action may amount to running that press branch for the window under the pointer.

**Describe alternatives you've considered**

1. A `window_title_bar_font` (and height) option, so the built-in bar carries the typography and
   the drag stays where it is. That would also dissolve the problem. It is the larger change: the
   bar is a one-row `Screen` rendered through the terminal font pipeline, so a proportional face
   at another size means separate text rendering and a bar that is no longer one cell high. The
   mouse action costs kitty no font plumbing and serves every front-end that draws its own chrome,
   so it is the smaller and more general change; the option would be a fine second choice.

2. Everything that can be done on 0.48.2 as shipped, each tried and measured (details under
   Additional context):
   - `toggle_window_title_bars` — drags, but takes a row (30 → 29) and the bar is monospace.
   - Holding the bars up with `window_title_bar_min_windows 1` and paying for the row out of
     `window_padding_width` — drags, no shift, still monospace and one cell high.
   - Styling the bar through the template's `bold`/`italic` and pointing `italic_font` at the
     wanted face — the font matcher takes monospace only; four spellings all fell back to Menlo
     Italic.
   - `draw_window_title(data)` in `window_title_bar.py` — returns a string, so it can change the
     text but not the face or the height, and no path feeds graphics data to the bar's `Screen`.
   - Drawing the header as a graphics placement over the window — perfect typography, zero
     resize, and no drag, because a placement is not in kitty's hit test.

**Additional context**

Environment: kitty 0.48.2 (Homebrew cask), macOS (Darwin 24.6.0), Monaco 18, 2x display.

Measurements, all on that build:

1. Bindable window actions, read off the live binary via `kitty.actions.get_all_actions()`:
   `win -> set_window_title, move_window, move_window_backward, move_window_forward,
   move_window_to_top, detach_window, toggle_window_title_bars`. There is no action that begins
   a drag. `debug -> test_dragging` exists and is a debug hook.

2. The drag hit region is set internally: `kitty.window.Window.update_title_bar` renders the
   bar, takes the renderer's `.geometry`, and passes it to
   `fast_data_types.set_window_title_bar_render_data`. Drag state lives behind
   `set_window_being_dragged` / `set_window_drag_overlay`. None is documented or reachable from a
   kitten, a `mouse_map`, or remote control.

3. The bar cannot be styled to match: `window_title_bar` exposes exactly 7 options
   (`window_title_bar`, `_min_windows`, `_active_foreground`, `_active_background`,
   `_inactive_foreground`, `_inactive_background`, `_align`) — no font, no height, no size. Its
   template formatter exposes `fg`, `bg`, `bold`, `italic`, `nobold`, `noitalic`, `reset`. So the
   only face lever is bold/italic -> `bold_font`/`italic_font`, and kitty's matcher takes
   monospace only. Four spec forms, one variable, all fell back to Menlo Italic
   (monospace: True):

       italic_font /System/Library/Fonts/SFNS.ttf   -> "font was not found, falling back to Menlo"
       italic_font family="SF Pro"                  -> Menlo Italic
       italic_font family="SF Pro Text"             -> Menlo Italic
       italic_font postscript_name=SFPro-Semibold   -> Menlo Italic

4. Our pixels cannot reach the bar: a graphics placement is addressed to a window's `Screen`,
   and the title bar is a separate `Screen` built in `kitty.window_title_bar` and drawn by
   `draw_attributed_string` (text + SGR). No template, no custom `draw_window_title(data)` —
   which returns a STRING exposed as `{custom}` — no kitten and no remote-control path feeds APC
   bytes to that `Screen`. `Screen` does carry graphics data internally (`rescale_images`,
   `update_only_line_graphics_data`), which is why this is an API gap and not a design
   impossibility.

5. `window_title_bar` accepts only `top|bottom`, and the bar is allocated from the cell grid in
   both: bare `toggle_window_title_bars` measured 30 -> 29 rows at a fixed padding.

Prior art (searched issues, PRs and discussions on 2026-09-16): #9448, #9450, #9619, #9626. In
#9450 you wrote "I am 100% certain other people are going to want to make the bars interactive";
this is the adjacent case — the interactivity shipped, and the ask is to let a front-end supply
the region it starts from. Nothing on the tracker asks for a font option on the bar or for a
mappable drag start. The new `mouse_selection drag_or_normal_select` action is the same shape
applied to text, which is what suggested a mouse action rather than an option.

Not asking for: a graphics or pixel path into the title-bar `Screen`; permanently visible bars;
any change to `toggle_window_title_bars`, to the drop model, or to defaults; anything
macOS-specific.

If the shape is acceptable I can attempt the PR; asking first since it is a design question
about where a drag may begin.
```

## 4. Notes for the operator — outside the issue, not to be posted

- **One decision, and it is yours: post it or not.** If yes, `gh issue create --repo
  kovidgoyal/kitty --label enhancement` with the title and body above, or paste them into the
  Feature request template on the web. Nothing here does that for you; this session did not and
  will not.
- **The last paragraph offers a PR.** Keep it if you are willing to have that follow-up land on
  you; cut it if not. Everything else in the draft stands without it.
- **Expect a fast close, and read it correctly.** CONTRIBUTING says requests are often closed
  quickly either way, and that the thread stays live afterwards. #8907 is the calibration: a
  bar-font ask was declined the same day with a reason. The draft leads with the mouse action for
  that reason and names the font option only as the second choice.
- **Voice.** First person singular, no deadline, no tooling named. The measurements are quoted
  as taken on 0.48.2 (§ 3 items 1–5, verbatim from the record); the master-branch observations
  are dated and marked as observations, so a maintainer who knows better can correct them
  without the request resting on them.
- **What this would buy us, once it exists:** `cmd+shift+b` keeps the styled overlay (SF Pro
  Semibold, no PTY resize) AND a chord press on that overlay begins the real drag, so the two
  chords in `config/kitty.conf` § 3b collapse back into one. Until then the record there stands:
  one chord cannot do both, and it is structural.

## 5. Sources this draft rests on

- `config/kitty.conf` § 3 and § 3b in this repo — the full measurement record, including the
  two claims refuted within hours (the "no fourth point" closure and the "dead on this machine"
  reading), which is why every number above is cited from the record rather than re-derived.
- `docs/research/kitty-pane-title-overlay-2026-09-14.md` § G — the overlay mechanism.
- kitty upstream, read 2026-09-16: `.github/ISSUE_TEMPLATE/feature_request.md`,
  `CONTRIBUTING.md`, `docs/changelog.rst`, `kitty/options/definition.py`, `kitty/boss.py`,
  `kitty/tabs.py`, `kitty/mouse.c`, `kitty/state.c`, `kitty/window_title_bar.py` at master
  `1d67ecd47c0b`; issues #9619, #8907, #7407; PRs #9450, #9626; discussion #9448.
