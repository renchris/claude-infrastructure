# R1 — Per-window (split pane) visual differentiation in kitty 0.48.2 / macOS

Empirical. Every row below was RUN on the live binary (`kitty 0.48.2 created by Kovid Goyal`,
`/opt/homebrew/bin/kitty` → `/Applications/kitty.app`). Rows marked UNVERIFIED are doc-only.
Screenshots: `/tmp/kitty-probe-evidence/*.png` (see § Evidence).

Two instances were used:
- **LIVE** (pid 97084, `unix:/tmp/kitty-97084`) — the operator's 15–16 Claude panes. Read-only +
  two reversible global colour probes, both reverted and verified (§ Cleanup).
- **PROBE** — a second, isolated kitty launched with `--config /tmp/kprobe-kitty.conf
  --listen-on unix:/tmp/kprobe-sock`, used for every *config-file* experiment so the live
  instance was never reloaded. Killed at the end.

---

## 0. Environment facts that constrain every design (read these first)

| Fact | Evidence | Why it matters |
|---|---|---|
| Config SSOT is `~/Development/claude-infrastructure/config/kitty.conf`, deployed by symlink to `~/.config/kitty/kitty.conf` | file header line 1 | any config-based mechanism is a diff to that file |
| **`~/.config/kitty/kitty.conf` is a DANGLING SYMLINK right now** → `/private/tmp/adn-land.v9Ngbj/config/kitty.conf`, which does not exist | `readlink -f`; `cat` → No such file | see next two rows |
| **A kitty CONFIG WATCHER is running**: `kitten __watch_conf__ 97084 100 /etc/xdg/kitty/kitty.conf ~/.config/kitty/kitty.conf` | `ps -axo pid=,command=` | any mtime touch of that path triggers a live reload |
| The live instance still holds the SSOT's colours (`active_border_color #6194f3`, `inactive_border_color #3a4555`) which are **not** kitty defaults (`#00ff00` / `#cccccc`) | `kitty @ get-colors` | kitty loaded the config at startup, before the symlink broke. **A reload today would fall back to defaults and repaint the whole fleet in highlighter green.** Do not run `kitty @ load-config` until the symlink is repointed. |
| **A config reload WIPES per-window `set-colors` state** (measured) but NOT logos, user-vars or bell state | PROBE A/B, § 3 | decides the durability ranking below |
| `window_padding_width 2 4`, `window_border_width 1pt`, `draw_minimal_borders` on (default) | config §7d | borders are ~2 device px hairlines between panes only |
| `tab_bar_min_tabs 1` is **deliberately NOT set** (config line 390-395: costs one text row per OS window) | config | the tab bar is **invisible today** — every OS window holds exactly one tab |
| `inactive_text_alpha` is **deliberately NOT set** — operator standing rule *"never dim data"* (config §7e) | config line 751 | any fg-dimming proposal is pre-refused by policy |
| The operator's layout is 4–5 OS windows × **1 tab each** × 2–6 splits | `kitty @ ls` | **per-TAB signals are per-OS-WINDOW signals here**, and are currently unrendered |

---

## 1. Mechanism table

Scope key: **W** = per split window · **T** = per tab · **O** = per OS window · **G** = global.

| # | Mechanism | Exact command / config | Scope | Runtime? | Reversible? | Survives config reload? | Latency | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **Per-window background** | `kitty @ set-colors --match id:N background=#141821` | **W** ✅ | yes | yes, but **no per-window `--reset`** (`--reset` implies `--all --configured`) — you must re-set the base value explicitly | ❌ **WIPED** (→ `#1e1e24`) | 54 ms | Works, looks good at a 3–6 % delta (see shot 2). Fragile. |
| 2 | Per-window foreground | `kitty @ set-colors --match id:N foreground=#8a8f98` | **W** ✅ | yes | as above | ❌ wiped | 54 ms | Works and reads clearly as "dimmed", but it **dims data** → refused by operator policy. |
| 3 | **Border colours** | `kitty @ set-colors --match id:N inactive_border_color=#e0a030` | **G** ❌ | yes | yes | ❌ wiped | 54 ms | 🚨 **`--match` is SILENTLY IGNORED.** rc=0, and the colour applies to **every** window. Proven: setting it matched to id:322 turned windows 325/326/327 magenta too. Also **`get-colors` does not report the change** (reports the configured value) — a silent no-op *and* a blind instrument. |
| 4 | **Bell / `needs_attention` border** | `printf '\a' > /dev/ttysNNN` (the pane's tty) | **W** ✅ | yes | yes (clears when the window is focused) | ✅ **survives** | 32 ms | 🥇 The only genuine per-window border state. Exactly 2 px columns changed, measured. Colour comes from the global `bell_border_color` (default `#ff5a00`). |
| 5 | **Window logo** | `kitty @ set-window-logo --match id:N --position=left --alpha=0.55 /path.png` ; clear with `… none` | **W** ✅ | yes | yes | ✅ **survives** | 63 ms | 🥇 The most beautiful. Drawn **under** text, over background; survives the **alternate screen** (verified). `--position` ∈ 9 anchors; `--alpha` 0–1. |
| 6 | `window_logo_scale` | kitty.conf only, e.g. `window_logo_scale 100 0` | **G** | ❌ conf-only | n/a | n/a | — | Not on the `set-window-logo` CLI. `100 0` = width 100 % of the pane → a 10 px rail floods the whole pane (garish, shot 5). Leave at default `0 -1` (natural size) and size the PNG instead. |
| 7 | **Per-window title bar** | conf: `window_title_bar_min_windows 1` (+ `window_title_bar top\|bottom`, `_align`, `_active_background`, `_active_foreground`, `_inactive_background`, `_inactive_foreground`) ; text via `kitty @ set-window-title --match id:N "◆ waiting for you"` | **W** ✅ | text yes; bar itself conf-only | yes | bar = conf; title text survives | 55 ms | 🥇 A real per-pane header with kitty's own active/inactive treatment, **plus** it auto-renders 🔔 on bell and `[45%]` from OSC 9;4. **Costs one text row per pane** — the same currency the config already refuses to spend on the tab bar. New in 0.46.0. |
| 8 | **Progress bar (OSC 9;4)** | pane emits `printf '\033]9;4;1;70\a'` (state;percent); conf `progress_bar left\|right\|top\|bottom\|hidden` (**default `top` — already on**) | **W** ✅ | yes | yes (`\033]9;4;0;0\a`) | ✅ survives | 32 ms | 🥇 A slim rounded rail on one pane's edge, styled by `scrollbar_*` (`scrollbar_handle_color`, `_width`, `_radius`, `_handle_opacity`). Gorgeous. **States 1/2/3/4 do NOT change colour** (measured: all `(97,121,182)`) — colour is global; only presence/fill is per-window. New in 0.47.0. |
| 9 | **Visual bell** | conf `visual_bell_duration 0.4 linear ease-out` + `visual_bell_color #3b5bdb`; fire with `printf '\a' > /dev/ttysNNN` | **W** ✅ | fire yes, style conf-only | auto-decays | ✅ | 32 ms | Full-pane translucent wash on **one** pane (verified, shot 4). A *transition* signal, not a state. Pairs perfectly with #4 (same BEL gives flash **and** persistent border). |
| 10 | **Per-window spacing** | `kitty @ set-spacing --match id:N margin=6` ; revert `margin=default` | **W** ✅ | yes | yes | not measured (UNVERIFIED) | 59 ms | Side effect worth knowing: a margin makes kitty draw a **complete rectangle** around that pane instead of only shared separators. Combined with #4 this yields a full orange box around the pane that wants you. |
| 11 | **User variables** | `kitty @ set-user-vars --match id:N CC_STATE=waiting` **or**, from inside the pane, `printf '\033]1337;SetUserVar=CC_STATE=%s\007' "$(printf waiting\|base64)"` | **W** ✅ | yes | yes | ✅ survives | 60 ms | Not visual on its own — it is the **state store + selector**: `--match var:CC_STATE=waiting` works (verified). This is how a repaint daemon re-derives state after a wipe. |
| 12 | `--match` selectors | `id: title: pid: cwd: cmdline: num: env: var: state: neighbor: session: recent:` ; window states = `active focused needs_attention parent_active parent_focused focused_os_window self overlay_parent` | — | — | — | — | — | `state:needs_attention` and `var:x=y` are both live. Boolean `and/or/not` supported. |
| 13 | Background opacity | `kitty @ set-background-opacity --match id:N 0.75` | **O** ❌ | yes | yes | — | — | 🚫 **Per-OS-window only.** kitty's own help: *"affects all kitty windows in a single OS window."* Verified: matching id:2 changed the whole OS window's `background_opacity` to 0.75. Also refuses entirely without `dynamic_background_opacity yes` (error message, rc=1). |
| 14 | Background image | `kitty @ set-background-image --match … /path` | **O** ❌ | yes | yes | — | — | 🚫 Per-OS-window (help: *"for the specified OS windows"*). Not usable per split. |
| 15 | `inactive_text_alpha` | conf `inactive_text_alpha 0.75` (0.47+: negative values switch inactive-vs-unfocused semantics) | **G**, applied per focus | conf-only | — | — | — | Works — measured brightest glyph 230→203 on unfocused panes. **Wrong axis** (focus, not state) and **banned by operator policy**. |
| 16 | Tab colour | `kitty @ set-tab-color --match id:T active_bg=#d08030 inactive_bg=#7a4a18` (also `active_fg`, `inactive_fg`, `NONE` to revert) | **T** | yes | yes | — | — | rc=0, but **invisible today** (`tab_bar_min_tabs 2`, one tab per OS window). Would become a per-OS-window aggregate light if the bar were enabled. |
| 17 | Tab title aggregate | conf `tab_title_template` already carries `{bell_symbol}{activity_symbol}{num_windows}` | **T** | conf | — | — | — | Verified in PROBE: a bell in **any** child pane renders 🔔 on the tab, and `[5]` shows the pane count. So a per-tab aggregate of child-window state **does** exist — it just needs `tab_bar_min_tabs 1` (one row per OS window) to be seen. |
| 18 | `tab_bar_style custom` | conf, a Python module implementing `draw_tab` | **T** | conf | — | — | — | UNVERIFIED (not run). Doc-supported; would allow arbitrary per-tab aggregate rendering. Irrelevant while the bar is hidden. |
| 19 | `create-marker` | `kitty @ create-marker --match id:N text 1 ERROR` / `remove-marker` | **W** ✅ | yes | yes | — | — | Per-window text highlight using `mark1_*` colours. Highlights *text*, i.e. paints over content — garish for a status signal. Not pursued. |
| 20 | OSC 133 prompt marks | shell integration; surfaces as `at_prompt` in `kitty @ ls` | **W** | — | — | — | — | Reported per window (`at_prompt`, `last_cmd_exit_status`). **Useless here**: a Claude Code pane is never "at a shell prompt" — it is a long-running TUI. `at_prompt=False` on every live pane. |
| 21 | OSC 777 / OSC 9 / OSC 99 notifications | `printf '\033]777;notify;title;body\a'` | — | yes | — | — | — | Produces a macOS Notification Center banner, **not** a pane visual. Out of band for "which pane is waiting". |
| 22 | `window_alert_on_bell` (default `yes`) | conf | app-level | — | — | — | — | Makes kitty request macOS user attention (dock bounce) on a bell. With 13+ panes belling this is noise — set `window_alert_on_bell no`; the **border still turns `bell_border_color`** (that is `bell_on_tab`/border logic, independent of the OS alert). |
| 23 | macOS dock **badge** | — | — | — | — | — | — | 🚫 kitty exposes no badge API. Not in the option set (`kitty +runpy` over `Options`), not in remote control. |
| 24 | Pulse/flash an OS window | — | — | — | — | — | — | Only `window_alert_on_bell` (dock bounce). No per-OS-window pulse. Per-*pane* flash exists — that is #9. |
| 25 | `kitty @ action` | `kitty @ action <mappable action>` | varies | yes | — | — | — | Runs any mapped action; no action exists that sets a per-window colour beyond the ones above. UNVERIFIED in depth. |

---

## 2. IMPOSSIBLE — do not design around these

1. **Arbitrary per-window border colour.** `set-colors --match id:N <any>_border_color` exits **0**
   and changes the colour for **every window**. There are exactly **three** border states per
   window — focused (`active_border_color`), unfocused (`inactive_border_color`), bell
   (`bell_border_color`) — and only the third is addressable without stealing focus.
2. **Per-split background opacity / translucency.** `set-background-opacity` is per-OS-window by
   design and documentation. Same for `set-background-image`.
3. **Per-window `set-colors --reset`.** `--reset` implies `--all --configured`. Reverting one
   window means re-asserting the base values on that window by hand.
4. **A macOS dock badge, or any per-pane OS-level indicator.** Not in kitty.
5. **Per-window colour state surviving a config reload.** Measured: wiped. And the reload trigger
   on this box is an mtime touch of a file inside a checkout a dozen sessions write to.
6. **Colour-coding by OSC 9;4 progress *state*.** States 1/2/3/4 all render the same colour.
7. **Per-TAB signals helping inside one tab.** Every OS window here holds one tab with 2–6 splits;
   the tab bar is not even rendered.

---

## 3. Durability matrix (the finding that should drive the design)

Measured in PROBE: set each, then `kitty @ load-config <conf>`, then re-read.

| State | Before | After reload |
|---|---|---|
| `set-colors background=#141821` | `#141821` | **`#1e1e24` — WIPED** |
| `set-window-logo` | rail visible | **rail still visible** |
| `needs_attention` (bell) | `True` | **`True`** |
| `user_vars` | `{'CC_STATE':'waiting'}` | **unchanged** |

⇒ **Build the steady-state signal out of logo + bell + user-vars, not out of `set-colors`.** If
`set-colors` is used at all, a watcher must re-apply it from `--match var:CC_STATE=…` after any
reload.

---

## 4. Ranked shortlist — the three most beautiful / subtle

### 🥇 1. Window-logo edge rail — *the closest thing to "a border colour of my own"*

A 6 px-wide PNG, full pane height, soft-faded at top and bottom, drawn under the text at the pane's
left edge. It reads as a warm hairline belonging to that pane only. Nothing else on screen moves.
Costs **zero rows and zero columns**. Survives config reloads and the alternate screen.

```bash
# make the rail once (6 x 1600 px, amber, eased at both ends)
python3 - <<'PY'
from PIL import Image
w,h=6,1600
im=Image.new('RGBA',(w,h),(0,0,0,0)); px=im.load()
for y in range(h):
    t=y/(h-1); fade=min(1.0, min(t,1-t)*6)
    for x in range(w):
        px[x,y]=(224,160,74,int(255*fade*(1.0 if x<w-2 else 0.45)))
im.save('/Users/chrisren/.claude/assets/pane-rail-amber.png')
PY

# mark a pane as WAITING FOR YOU
kitty @ set-window-logo --match id:317 --position=left --alpha=0.55 \
  /Users/chrisren/.claude/assets/pane-rail-amber.png

# clear it when the pane goes back to work
kitty @ set-window-logo --match id:317 none
```

Aesthetic: **subtle**. Verified at alpha 0.55 in `/tmp/kitty-probe-evidence/kitty-candidates.png`
(3rd pane). Keep `window_logo_scale` at its default `0 -1`; do **not** set `100 0` (it floods the
pane — 2nd pane of `kprobe-inst-small`). A blue/cool variant is the natural "working" state, but
prefer *absence* for working: one marked pane in a grid of plain ones is the strongest read.

### 🥈 2. OSC 9;4 progress rail — *the same look, driven from inside the pane, zero remote control*

`progress_bar` already defaults to `top` in 0.48.2, so this is live today with no config change;
`progress_bar left` gives the vertical rail. Styled by the scrollbar knobs, so it is rounded and
anti-aliased — visibly nicer than a flat image. Presence and fill are per-window; colour and edge
are global.

```bash
# from INSIDE the pane (a Claude Code Stop hook is the natural emitter):
printf '\033]9;4;3;0\a'      # indeterminate  -> a small travelling segment  = "waiting"
printf '\033]9;4;1;70\a'     # normal, 70%    -> a 70%-filled rail
printf '\033]9;4;0;0\a'      # clear

# optional, in kitty.conf:
progress_bar            left
scrollbar_handle_color  #e0a04a
scrollbar_width         0.6
```

Aesthetic: **very subtle**, arguably the most refined of the three (`kprobe-pb2.png`). Caveat: it
semantically means *progress*; using indeterminate-forever for "waiting" is a mild abuse, and the
colour cannot differ per pane.

### 🥉 3. Bell → `bell_border_color` (+ optional soft visual-bell wash)

The only mechanism that reaches kitty's **own** border system, i.e. the literal reference quality
bar: blue = focused, grey = not, **orange = wants you**. One byte. Clears automatically the moment
the operator focuses the pane — semantically perfect. Survives reloads.

```bash
# arm: write one BEL to the pane's own tty (find it from the window's pid)
printf '\a' > /dev/ttys044

# read back which panes are flagged
kitty @ ls | python3 -c 'import json,sys;[print(w["id"],w["needs_attention"]) for o in json.load(sys.stdin) for t in o["tabs"] for w in t["windows"]]'
kitty @ set-colors --match state:needs_attention …      # selector works

# in kitty.conf, to tune it:
bell_border_color      #e0a04a     # softer than kitty's default #ff5a00
window_alert_on_bell   no          # keep the border, drop the dock bounce
visual_bell_duration   0.35 linear ease-out
visual_bell_color      #2a3550     # a single gentle wash at the moment of transition
enable_audio_bell      no
```

Add `kitty @ set-spacing --match id:N margin=4` to turn the hairline into a **complete rectangle**
around that pane (verified, `kprobe-4.png`, 2nd pane) — the strongest read of the three, and still
only 4 px of screen.

Aesthetic: **subtle at the right colour, garish at kitty's stock `#ff5a00`.** The default orange
against this dark slate theme is the same charge sheet the config already wrote about `#00ff00`.

---

### Honourable mention (not top-3 only because of its cost)

**Per-window title bar** (`window_title_bar_min_windows 1`) is the most *informative* option by a
distance: a real header strip per pane, kitty's own focused/unfocused colour treatment, arbitrary
runtime text (`kitty @ set-window-title --match id:N "◆ waiting for you"`), and it auto-renders 🔔
on bell and `[45%]` from OSC 9;4. See `kprobe-tb2.png` and `kprobe-pb-small`. It costs **one text
row per pane** — at 30 panes that is 30 rows, and the config has already refused a one-row-per-OS-
window tab bar on exactly that ground. Offer it, do not assume it.

---

## 5. Hazards found (adversarial pass)

1. 🚨 **Writing to a live pane's tty races the program writing to the same tty.** Every
   `printf … > /dev/ttysNNN` recipe above splices bytes into the pane's output stream. If that
   lands mid-escape-sequence while Claude Code is repainting, the pane renders corrupt. Safe
   variants, in order: (a) have the **program itself** emit (a Claude Code hook writing to its own
   stdout — atomic w.r.t. its own output), (b) use `kitty @` remote control, which is race-free but
   cannot ring the bell or emit OSC 9;4. Only the tty path can do #2 and #3 from outside.
2. 🚨 **`kitty @ load-config` on the live instance today would fall back to kitty's stock theme**
   (dangling symlink) — pure-green active borders across the fleet. Repoint the symlink at the
   repo SSOT *before* anyone reloads, and note the watcher can trigger it without a human.
3. **`set-colors` border args are a silent no-op with `--match`** and **`get-colors` will not tell
   you** — two blind instruments in the same call. If a design ever depends on reading a border
   colour back, it cannot.
4. **A bell fired at the pane that is already focused sets nothing** — `needs_attention` stays
   `False` (measured). Correct semantics, but a daemon must not treat "armed" as guaranteed.
5. **`window_logo_scale` is global**, so a design cannot mix a rail logo and a wash logo.
6. Adding a logo/title bar did not measurably change anything at 4 panes; **behaviour at 30 panes
   is UNVERIFIED** (one GPU texture per logo).

---

## 6. Evidence (PNGs, full-res, on disk)

| File | Shows |
|---|---|
| `/tmp/kitty-probe-evidence/kprobe-shot2.png` | per-window `background` (#141821 cool, #1a1410 warm) and per-window `foreground` dim, side by side with an untouched pane |
| `…/kprobe-shot3.png` | three window logos at once: centred glow, left rail, corner dot |
| `…/kprobe-4.png` | `set-spacing margin=6` → full rectangle border; green bell border on the belled pane |
| `…/kprobe-vbell.png` | visual bell wash on exactly one pane + orange bell border + 🔔 on the tab |
| `…/kprobe-tb2.png` | per-window title bars, active (blue-slate) vs inactive (grey) |
| `…/kprobe-pb2.png` | OSC 9;4 progress rails on the left edge of two panes |
| `…/kitty-candidates.png` | the three shortlisted candidates side by side at tasteful settings |

Pixel-level proofs (not screenshots): the bell changed **exactly two device-pixel columns**
(x=2593–2594, `(60,69,84)` → `(236,102,43)`) with every other column byte-identical; the
`--match id:322 inactive_border_color=#ff00ff` probe turned **all three** other panes'
borders `(234,51,247)`, which is what proves the global scope.

---

## 7. Cleanup / census

| | OS windows | Windows |
|---|---|---|
| **START** (`/tmp/kitty-ls-START.json`) | 4 (ids 14, 63, 64, 65) | **16** — tab 14 held 2, tab 63 held 5, tab 64 held 7, tab 65 held 2 (the brief said 13; the live count was 16) |
| **END** (`/tmp/kitty-ls-END.json`) | 5 (ids 14, 63, 64, 65, **68**) | **15** |

I created and destroyed: LIVE os-window **67** with windows **322, 325, 326, 327** (gone — verified
absent from the end census), and a **separate kitty process** (pid 4103, 7 windows, own socket) —
killed, socket removed, no `kprobe` process remains.

**The 16 → 15 delta is operator/fleet churn, not mine**, and is itemised: win 285 and win 320
(a sibling `deep-research` pane) exited; win 129 moved out of OS window 63 into a **new** OS window
68; win 338 (`AI enhancement fail error limit size`) is new. All 4 of my window ids and my whole OS
window are gone.

Global state restored and verified by read-back:
`active_border_color #6194f3 · inactive_border_color #3a4555 · bell_border_color #ff5a00 ·
background #1e1e24 · foreground #e6e6e6` — identical to the repo SSOT. Focus returned to window 161
(the window focused when I started).
