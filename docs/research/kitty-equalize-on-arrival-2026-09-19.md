# Panes that even themselves out — removal is free, arrival costs one call

**2026-09-19 · kitty 0.48.2 · verifier `scripts/checks/kitty-equalize-verify.py` (re-derives every
number below) · guards `tests/kitty-equalize-arrival.bats`**

**Question.** The right-click pane menu (`bin/kitty-pane-menu`) moves a pane into another OS
window. The pane arrives squeezed, and the operator presses ⌘⇧E by hand afterwards, every time.
Can arrival even the panes out automatically, cleanly, with no daemon and no load?

**Answer.** Yes, in two halves that are *not* symmetric — and the asymmetry is the finding.

| half | mechanism | cost |
|---|---|---|
| the tab a pane **leaves** | a kitty layout option, `splits:equalize_on_window_close=yes` | **zero** — one branch on a relayout kitty was already doing |
| the tab a pane **arrives** in | one `kitty @ action --self layout_action equalize` per gesture | one RPC, on an explicit user action |

## 1. Removal is already solved inside kitty, and nothing in our config had it on

`kitty.layout.splits.Splits` carries a layout option whose serialized name is
`equalize_on_window_close` (default `n`). Read out of the shipped bytecode:

```
Tab.detach_window -> Tab.post_window_removal_update
                  -> current_layout.on_window_removed(self.windows)
Splits.on_window_removed:  if self.layout_opts.equalize_on_close: return self.equalize_biases()
```

`detach_window` is the same path a close takes, so one option covers **close pane, ⌘W, move to a
new window, and move to an existing window**. Measured: four panes at `114/57/28/28`, detach one,
tab lands on `76/76/76` instead of the unfixed `114/57/57`.

It is not a watcher and not a poll. There is no process. This is the cheapest half by a wide
margin and it needed one edit to `config/kitty.conf`.

## 2. Arrival has no hook, so it is ours

There is no `on_window_added`. `Tab._add_window` calls `current_layout.add_window(...)`, and the
splits layout adds by **halving the window it lands beside** — so a pane arriving in a 4-pane tab
produces `114/57/28/14/14`. Three callers create or re-home panes and now each squares up its own
destination: `bin/kitty-pane-menu` (the move), `bin/it2-kitty` (every `handoff-fire --split-right`),
`bin/cc-resume-layout.sh` (group recovery, which already equalized — see §4).

## 3. 🚨 `--match` is a silent no-op; `--self` is the only working form

`equalize` is a **tab-level** action (`kitty.tabs.Tab.layout_action`), and kitty routes tab actions
through the focused tab. Three-arm control, one run, source / destination / an uninvolved third tab:

| form | destination | control tab | rc | stderr |
|---|---|---|---|---|
| `kitty @ action layout_action equalize` | untouched — hits whatever is **focused** | — | 0 | empty |
| `kitty @ action --match id:N layout_action equalize` | `114/57/28/14/14` → **unchanged** | untouched | **0** | **empty** |
| `KITTY_WINDOW_ID=N kitty @ action --self layout_action equalize` | `114/57/28/14/14` → **`45/45/45/45/45`** | untouched | 0 | empty |

Two consequences worth keeping:

- **A return code proves nothing here.** kitty exits 0 on an unknown action name *and* on an action
  that resolves to no tab. Assert the column widths from `kitty @ ls`; never the exit status. This
  is why the real proof is a live verifier and not a unit test.
- **`--self` does not move focus.** The alternative — `focus-window` then a bare action — raises the
  destination OS window, which on another macOS Space would drag the operator across Spaces on
  every move. Measured: after `--self` the focused OS window is unchanged.

`--self` reads `KITTY_WINDOW_ID` from the caller's environment, and every caller sets it
**explicitly** rather than inheriting it: a `launch --type=background` child — which is how
`kitty-pane-menu` is started — is handed an **empty** `KITTY_WINDOW_ID` and an empty
`KITTY_LISTEN_ON` (measured), so an inherited value would silently mean "no window".

## 4. What this corrects in the existing tree

- `config/kitty.conf`'s ⌘⇧E note said to use `--self` because a bare `kitty @ action` targets the
  active window. The advice was right; the stated reason was incomplete, and the untested corollary
  — that `--match` is the general fix — is false. Both are now recorded with the control above.
- `bin/cc-resume-layout.sh` aimed its equalize by focusing the head window and sleeping **1 second**
  per group. `--self` aims it directly, so N recovered groups no longer cost N seconds and no longer
  yank the operator through N OS windows.

## 5. The one-time effect of landing, stated rather than discovered

`~/.config/kitty/kitty.conf` is a symlink into this checkout and a `kitten __watch_conf__` child
reloads it ~100 ms after any write, so changing `enabled_layouts` reaches the live terminal by
itself. That is a real options change, so kitty rebuilds each open tab's splits layout **once**:
panes keep identity and order, biases reset (everything equalizes — the requested end state), and
nesting can re-lean (measured: a `114/57/57` tab came back `57/57/114`).

It is a **single event, not a per-reload one.** The obvious worry — that with opts in
`enabled_layouts` every later config edit would re-equalize, destroying a pane the operator had
deliberately widened — was derived from `Tab.set_enabled_layouts`'s `current_layout.name not in
enabled_layouts` guard and is **refuted by measurement**: with a pane manually biased to
`133/47/47`, two reloads of an unchanged conf and one reload after changing an unrelated option all
left the geometry untouched, in both arms. The bytecode reading of `name` as the bare class
attribute was simply wrong; kitty compares the full name including opts.

## 6. Residual

`map cmd+shift+o detach_window ask` can send a pane into an **existing** tab, and that path is
internal to kitty's `ask` kitten — no hook, and `combine` would fire a follow-up action
immediately rather than after the picker resolves. Panes arriving that way are still uneven. Every
other arrival route on this box is covered. Not filed: the menu supersedes that chord for exactly
this gesture, and it is one ⌘⇧E away.
