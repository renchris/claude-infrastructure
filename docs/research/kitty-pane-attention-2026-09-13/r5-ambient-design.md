# R5 — Ambient "this pane is waiting for YOU" · design research

Measured on the live desktop 2026-09-13. Every number below is an instrument reading, not an
estimate; the commands are given so each is re-derivable.

---

## 0. The verdict, first

**Ship: `WARM WASH` — a whole-pane background lift to `#26242e`, armed by Claude Code's own
Stop hook, announced by kitty's native eased visual bell, and reinforced by a re-themed
`bell_border_color #f6c177`. Exactly one pane at a time wears the strong tier.**

**Polarity: mark the WAITING pane — but rank, never threshold.** The strong treatment is always
worn by exactly one pane (the longest-waiting), so the signal carries ~4.4 bits whether one pane
waits or ten. That is what makes it immune to the operator's own alarm-polarity rule.

The two runners-up are §9.2 (`GOLD FRAME`, border-only) and §9.3 (`RECEDE`, the
Ghostty/WezTerm inverse-polarity move). Both are worse, for reasons that are measured, not
aesthetic.

---

## 1. Ground truth that changes the answer

Five facts were assumed away in the brief. Each one moves the design.

### 1.1 The desktop is kitty 0.48.2, not iTerm2

```
ps -axo command= | grep -iE '/(iTerm|kitty|Ghostty|WezTerm)'
```

kitty 0.48.2 is the only terminal GUI running. `iTermServer-3.6.11` is alive but there is **no
iTerm.app GUI process** — the `it2` infrastructure all over this repo is dormant for the desktop.
Every iTerm2-specific mechanism (badges, `OSC 1337 RequestAttention`, per-profile dimming,
`SetColors`) is unavailable. This axis has to be designed against kitty's capability set.

### 1.2 The blue divider the operator described is real, and it is 4 physical pixels

Live colors, read from the running process:

```
kitten @ get-colors --match id:<pane>
  background              #1e1e24
  active_border_color     #6194f3      ← "blue instead of gray"
  inactive_border_color   #3a4555      ← the gray
  bell_border_color       #ff5a00      ← a THIRD state nobody is using
```

Sampled out of a real screenshot of the operator's desktop (full-height constant non-background
columns, `window_border_width 1pt` at 2× retina):

| divider | rendered | rel. luminance | WCAG vs bg | width |
|---|---|---|---|---|
| background | `#1e1e24` | 0.01332 | — | — |
| inactive | `#3c4554` | 0.05857 | **1.71:1** | 4 px |
| active (blue) | `#546ca0` | 0.15148 | **3.18:1** | 4 px |

### 1.3 …and 4 pixels is below the peripheral resolution limit almost everywhere on this screen

Built-in Liquid Retina XDR, 3456×2234 over 344.4 × 222.6 mm ⇒ 0.0997 mm/px. At 55 cm the screen
subtends **32.1° × 22.0°**, so a corner sits ~20.8° off fixation. Peripheral minimum-angle-of-
resolution ≈ `1 + ecc/2.3` arcmin:

| feature | arcmin | resolvable out to |
|---|---|---|
| 1pt border (4 px, today) | 2.5 | **3.4°** |
| 2pt border (8 px) | 5.0 | 9.2° |
| 3pt border (12 px) | 7.5 | 14.9° |
| 4pt border (16 px) | 10.0 | 20.6° |
| a whole pane (860 × 2100 px) | 531 × 1250 | entire field |

**This is the mechanical explanation of the operator's complaint.** The blue divider is only
resolvable within ~3.4° of where they are already looking. It cannot draw the eye because the eye
has to be there already. No amount of *contrast* fixes this — the defect is *spatial frequency*,
and peripheral vision is a low-spatial-frequency channel. Any treatment whose answer is "make the
line a nicer colour" is dead on arrival.

### 1.4 Per-pane background IS settable; per-pane border colour IS NOT

Tested with a positive control, three panes in one tab:

```
kitten @ set-colors --match id:335 background=#26242e
  → 334 #1e1e24 · 335 #26242e · 336 #1e1e24      ISOLATED ✓

kitten @ set-colors --match id:335 inactive_border_color=#f6c177
  → all three still #3a4555                      GLOBAL ✗ (silently ignored, exit 0)
```

Border colours are OS-window-global. **The only per-pane border channel kitty offers is the bell
state**, which swaps that pane's border to the global `bell_border_color`. So the border can be
binary (armed / not) but never parameterised, while the background is freely parameterisable —
and the background is exactly the channel §1.3 says is the strong one. Mechanism and perception
agree, which is rare and worth taking.

Also per-pane: `set-window-logo --match`, `set-spacing`, `set-user-vars`, `set-background-image`.

### 1.5 The killer: 20 of 21 panes are fully occluded right now

```
kitten @ ls        # 21 panes · 5 OS windows · 17 running Claude Code
```

Every kitty OS window is sized 1728×1080 logical — the **full screen** — and they are stacked.
At the moment of measurement, **1 pane was visible and 20 were occluded**. Mission Control
confirms the shape: this is a window-stack workflow, not a tiled one.

**No in-pane visual treatment can signal a pane in a background OS window.** This is not a caveat,
it is the dominant fact, and it forces a two-tier answer:

- **Tier A — intra-window** (the panes of the front OS window): the visual treatment. This is what
  the operator asked for and what §9 ranks.
- **Tier B — cross-window** (everything else): needs an OS-level channel. kitty's tab bar is
  unavailable here (`tab_bar_min_tabs 2`, and every window has exactly one tab), so the only
  routes are the Dock (`window_alert_on_bell`, currently **on** by default) and the window title
  (`macos_show_window_title_in all`, so it reaches the menu bar and Mission Control).

Tier B is a separate deliverable. Do not let a beautiful Tier-A treatment disguise the fact that
it reaches ~1/20th of the panes at any instant.

### 1.6 kitty's built-in state signals cannot detect "waiting" for a Claude Code pane

`kitten @ ls` exposes `needs_attention`, `has_activity_since_last_focus`, `at_prompt`,
`last_cmd_exit_status`, `last_focused_at`, `user_vars` per window. Measured across 17 live
Claude Code panes:

```
needs_attention = True : 0 / 17
activity-since-focus   : 0 / 17
at_prompt = True       : 0 / 17
```

`at_prompt` is false even for panes sitting at Claude Code's input box, because the TUI does not
emit shell-integration prompt marks. **Every terminal-side heuristic is blind here** — including
tmux's `monitor-silence`, which is the canonical prior art for this exact problem (§2.1).

This is good news. The producer must be Claude Code's own hooks, which know the *semantic* state
exactly — `Stop` = turn ended and the operator is the blocker; `Notification` = permission prompt;
`UserPromptSubmit` = they answered. A hook-driven signal has no false-positive class that a
silence timer would have. The channel is also uncontended: nothing in this repo emits BEL today
(`grep -rln 'needs_attention\|bell_border' hooks bin scripts` → empty).

---

## 2. Prior art in terminals

### 2.1 tmux — the most complete vocabulary, and the clearest lesson

Verified from the local man page:

| option | what it does |
|---|---|
| `monitor-activity [on\|off]` | flag a window on any output |
| `monitor-bell [on\|off]` | flag on BEL |
| `monitor-silence [interval]` | **flag when a window produces NO output for N seconds** |
| `activity-action` / `bell-action` / `silence-action` `[any\|none\|current\|other]` | scope the alert |
| `visual-activity` / `visual-bell` / `visual-silence` `[on\|off\|both]` | status-line message vs. terminal bell |
| `window-status-activity-style`, `window-status-bell-style` | styling of the flagged status entry |
| `pane-border-style`, `pane-active-border-style` | the divider colours |
| `pane-border-lines`, `pane-border-status [off\|top\|bottom]`, `pane-border-format` | **a per-pane text strip** |
| `window-style`, `window-active-style` | whole-pane fg/bg for inactive vs active |

**Right:** tmux is the only one of these tools that modelled *silence* as a first-class alert
condition — it understood that "stopped producing output" is the interesting event, not activity.
And `window-style` / `window-active-style` is the same whole-pane-background channel this document
recommends, arrived at independently ~15 years ago.

**Wrong / noisy:** `monitor-silence` is notoriously unusable in practice for exactly the reason
the brief anticipates — it fires on every legitimately idle pane, so it is either off or it is
constant. The lesson is not "silence detection is bad"; it is that **a timing heuristic cannot
distinguish idle-and-waiting from idle-and-fine, and only a semantic producer can** (§1.6).
`pane-border-status` is the other genuinely good idea: a one-line strip per pane, which is a real
area rather than a hairline.

### 2.2 kitty — the only one with a native third border state

- `bell_border_color #ff5a00` — *"The color for the border of inactive windows in which a bell has
  occurred."* A per-pane, terminal-rendered, auto-clearing-on-focus attention state. Almost nobody
  uses this and it is the best primitive on the box.
- `visual_bell_duration 0.0` — *"Flash the screen when a bell occurs… The flash is animated, fading
  in and out over the specified duration. The easing function used for the fading can be
  controlled… different easing functions for the fade-in and fade-out."* Syntax: `0.4 ease-out`,
  or two functions for asymmetric in/out. **This is a native, compositor-rendered, eased one-shot
  transition, free of charge.**
- `visual_bell_color none` — *"Set to none will fall back to selection background color. If you
  feel that the visual bell is too bright, you can set it to a darker color."* The docs anticipate
  the subtlety requirement directly.
- `enable_audio_bell yes` (**default, unset in this repo's conf — it will beep**),
  `window_alert_on_bell yes` (**default — bounces the Dock icon on macOS**), `bell_on_tab "🔔 "`,
  `command_on_bell none` (an arbitrary command hook on bell).
- `inactive_text_alpha 1.0` — fades text in every non-active window. Global, not per-pane.
- `window_logo_path` / `window_logo_alpha 0.5` / `window_logo_position` — a per-pane watermark
  image, settable live via `kitten @ set-window-logo --match`.
- `draw_minimal_borders yes` — *"only the borders that separate the window from a neighbor are
  drawn. Note that setting a non-zero `window_margin_width` overrides this and causes ALL borders
  to be drawn."* That override is the lever that turns a shared hairline into a closed rectangle
  per pane (Gestalt closure), at the cost of drawing borders everywhere.

### 2.3 WezTerm and Ghostty — both chose to recede the irrelevant

- **WezTerm:** `inactive_pane_hsb = { saturation = 0.9, brightness = 0.8 }` — **on by default**.
  Inactive panes are desaturated and dimmed in HSV.
- **Ghostty:** `unfocused-split-opacity` (0.15–1.0, default **0.7**), `unfocused-split-fill`
  (default `#000000`), `split-divider-color` (since 1.1.0).

**The transferable observation:** the two best-regarded modern terminals independently converged on
*dim the unfocused* rather than *highlight the important*, and both ship it on by default. That is
the calm-technology move and it is genuinely better taste than a highlight. **But both of them mark
FOCUS, not ATTENTION** — they answer "where am I?", never "where should I go?". Neither has a third
state. kitty does. That is why the recommendation is kitty-shaped and not a port of either.

Ghostty's own tracker also records the community complaint *"Split dividers are hard to see"*
(discussion #3301) and a request for a separate active-split border colour (#2727) — i.e. other
people have walked into §1.3 and asked for a bigger line, which is the wrong fix.

### 2.4 zellij / GNU screen

zellij frames panes and colours the frame of the focused pane; it has no attention state. screen
has `monitor`/`activity`/`bell_msg` — status-line text only. Neither adds anything the tmux row
does not already cover, and neither is installed as the operator's driver.

---

## 3. Prior art outside terminals, and the principles worth stealing

| system | what it does | principle to take |
|---|---|---|
| **macOS Dock: bounce vs. badge** | bounce = motion, demands *now*; badge = static count, waits | **Separate the ONSET from the STATE.** Bounce once, badge forever. The bounce is unignorable and finite; the badge is ignorable and persistent. Almost every failure in this design space is using one where the other belonged. |
| **Slack: unread dot vs. mention badge** | a low-contrast dot = "something happened"; a red numeric badge = "*you* are named" | **Two tiers, and only the rarer one gets colour.** The dot is the same hue as the text; only the mention breaks the palette. |
| **iOS Focus / attention design** | notifications are *batched and delivered on a schedule*, not on arrival | **Latency is a design parameter.** Nothing here needs sub-second delivery; a signal that arrives on a 5 s cadence is calmer and no less useful. |
| **IDE gutter markers** (VCS ribbon, error squiggles) | a thin strip at a *fixed, learned position*, never over the content | **Position is learnable; if the mark is always in the same place, it can be far subtler.** A cue whose location varies must be louder. |
| **CI status dots** (GitHub) | one glyph per commit, shape + colour redundant (✓ / • / ✗) | **Never encode by hue alone** — the shape carries it for CVD and for the periphery equally. |
| **E-ink / ambient displays** (Ambient Orb, Weiser's dangling string) | state is a continuous physical property with no alert event | **The best ambient signals have no "off"** — they are always showing a value, so there is nothing to miss and nothing to dismiss. |

### Calm technology (Weiser & Brown, Xerox PARC, 1996)

Calm technology is *"that which informs but doesn't need our focus or attention."* The three
principles, as stated: attention resides mainly in the **periphery**; the technology **increases
the user's use of their periphery**; and it **moves easily from periphery to centre and back**.
"Periphery" here names *what we are attuned to without attending to explicitly* — attunement, not
detection.

Two clauses bind this design hard:

1. **"Moves easily to the centre AND BACK."** A signal you must dismiss has not moved back — it
   has been *parked* in the centre. The treatment must clear itself. kitty's bell state clears on
   focus, with no dismissal gesture. That is the correct shape.
2. **"Increases the use of the periphery."** The measure of success is *not* that the operator
   sees the signal. It is that they stop scouring last messages — i.e. they come to trust the
   periphery enough to ignore it until it speaks. That trust is destroyed by exactly one thing: a
   false positive. **Precision matters more than recall here**, which is the whole argument for a
   hook-driven producer over a silence timer.

---

## 4. The perceptual science — ranked channels, and the critical finding

### 4.1 The ranking, for a dark terminal desktop at ≤21° eccentricity

| rank | channel | pre-attentive? | survives at 20°? | survives at low amplitude? | verdict |
|---|---|---|---|---|---|
| 1 | **Abrupt onset / new object** | **Yes — uniquely** | Yes | **Yes** | the only channel that *captures* |
| 2 | **Luminance of a large region** | Yes (parallel) | Yes (achromatic is best-preserved) | Yes — see §4.3 | the workhorse |
| 3 | Motion / flicker | Yes | Yes (periphery is motion-biased) | Yes | effective and intolerable (§6) |
| 4 | Size / area | Yes | Yes | n/a — it *is* the amplitude | the multiplier on 2 |
| 5 | Hue — blue↔yellow | Yes | Degrades gently | Moderately | good *secondary* code |
| 6 | Saturation | Weakly | Poorly | No | decorative only |
| 7 | Hue — red↔green | Yes at fovea | **No — gone by 25–30°** | No | **disqualified** (§4.4) |
| 8 | Orientation / shape | Yes at fovea | No (needs acuity) | No | glyphs need the fovea |
| — | Conjunctions (e.g. "amber *and* thin") | **No — serial search** | — | — | never encode this way |

Treisman & Gelade's feature-integration theory is the frame: single-feature targets are
*"registered early, automatically, and in parallel"* and pop out irrespective of set size;
conjunctions require serial binding. So the signal must differ from every other pane on **one**
feature, not a combination. This is the argument against a cue that is "a slightly different
border colour *and* a slightly different width" — that is a conjunction, and conjunctions are
searched one pane at a time, which is precisely the scouring the operator wants to stop doing.

### 4.2 The critical finding: a static subtle cue does NOT pop out

**Jonides & Yantis (1988), "Uniqueness of abrupt visual onset in capturing attention",
*Perception & Psychophysics*.** They asked whether abrupt onset is merely one member of a class of
attention-capturing features, and found it is not: **changes in colour or luminance did not capture
attention the way an abrupt onset did.** A static singleton — however unique — is found by *search*,
not by *capture*, unless it matches what the observer is already looking for (Folk, Remington &
Johnston's contingent-capture qualification).

**This settles the brief's critical question.** A static low-contrast cue can be *findable* but
cannot be *attention-getting*. The transition is what carries the alert; the static state is what
carries the answer once the eye arrives. They are two different jobs and both are needed:

- **onset** → gets the eye off the current pane at all. Must be a change event, ~300–600 ms.
- **persistent state** → survives the onset being missed (the operator was making coffee), and
  answers "which one?" when they look up ten minutes later.

A design with only the onset loses everything the moment attention is elsewhere. A design with only
the static state never interrupts and must be polled by eye — the operator's current situation.
**Ship both.** Almost every "subtle ambient indicator" that fails in practice fails by shipping
only one of them.

### 4.3 Why a "subtle" background lift is not subtle at all, perceptually

At near-black luminances a tiny hex change is a *large* Weber contrast. Background `#1e1e24` has
relative luminance 0.01332:

| tint | rel. L | Weber ΔL/L | fg `#e6e6e6` contrast |
|---|---|---|---|
| `#1e1e24` (none) | 0.01332 | — | 13.29:1 |
| `#232029` | 0.01550 | +16.4% | 12.84:1 |
| `#24212b` | 0.01637 | +22.9% | 12.68:1 |
| **`#26242e`** | **0.01871** | **+40.5%** | **12.24:1** |
| `#282530` | 0.01988 | +49.2% | 12.04:1 |
| `#2a2733` | 0.02182 | +63.8% | 11.71:1 |
| `#2d2936` | 0.02410 | +80.9% | 11.35:1 |

A wash that reads as "did something change?" in a side-by-side swatch is a **+40% luminance step**
spread over ~25% of the screen. Compare the blue divider: a +1037% Weber step over 0.12% of the
screen, invisible past 3.4°. **Area beats contrast in the periphery, by a lot.** That asymmetry is
the single most useful thing in this document.

*Honest caveat:* my "fg loss" flag above fired at an arbitrary 12:1 threshold. Every candidate in
that table keeps foreground contrast above 11:1 — far above WCAG AAA's 7:1. **Legibility is not
the binding constraint anywhere in this range; taste is.** Do not present the tint ceiling as an
accessibility limit, because it is not one.

### 4.4 Red and green are the wrong vocabulary twice over

Peripheral colour research: **red-green cone opponency declines steeply with eccentricity and is
behaviourally absent by 25–30°**, while blue-yellow loss is gradual and tracks achromatic loss.
The screen corners are at ~21°. (The literature is not perfectly unanimous on the steepness
ordering — one line of work reports red-green declining *less* than blue-yellow — but the
mechanistic account, random L/M-cone contribution to parvocellular receptive-field surrounds as
they enlarge, is the better-supported one and points the same way as the CVD evidence below.)

So red/green fails **in the periphery for everyone**, before colour-blindness is even considered.
Then CVD removes it a second time. Vienot-matrix simulation against this background:

| accent | hex | protanopia | deuteranopia | rel. L |
|---|---|---|---|---|
| kitty bell default | `#ff5a00` | `#7c7c0c` | `#a3a300` | 0.286 |
| current blue (`color4`) | `#6194f3` | `#8f8ff3` | `#8888f3` | 0.302 |
| **Rosé Pine gold** | **`#f6c177`** | **`#c8c877`** | **`#d2d274`** | **0.591** |
| Everforest yellow | `#dbbc7f` | `#c0c07f` | `#c6c67e` | 0.526 |
| Nord yellow | `#ebcb8b` | `#cfcf8b` | `#d5d58a` | 0.622 |
| Catppuccin peach | `#fab387` | `#bdbd88` | `#cbcb84` | 0.543 |
| Rosé Pine love (rose/red) | `#eb6f92` | `#858593` | `#a1a18e` | 0.311 |

`#eb6f92` collapses to a desaturated blue-grey under protanopia at rel. L 0.311 — **within 3% of
the blue's luminance**, i.e. the two states become the same colour *and* the same brightness. That
is the concrete disqualification of a rose/red vocabulary.

`#f6c177` under both CVDs stays a bright warm yellow and, crucially, keeps a **~2× luminance ratio
over the blue**. The signal is therefore redundantly coded on hue *and* luminance — the
accessibility gold standard, and the reason it also survives the periphery.

**The correct axis is blue ↔ gold**: it is the tritan (S-cone) axis, intact in both common CVDs,
best-preserved with eccentricity, and semantically *cool→warm* rather than *safe→danger*. It also
reuses a colour the operator already owns (`color4 #6194f3`), so the vocabulary is "the pane got
warmer", not "a new alert colour appeared".

### 4.5 One more constraint from the operator's own screen

In the real screenshot, Claude Code's working spinner already renders in **orange/salmon**
(`✳ Computing…`, `✳ Waddling…`, `▶▶ auto mode on`). **Orange is therefore already taken, and it
means "working".** kitty's default `bell_border_color #ff5a00` would collide with it head-on. The
accent must be clearly *yellower* than that spinner orange — which `#f6c177` is — or the new signal
will read as "more of the same activity".

---

## 5. Alarm polarity — and why the question dissolves

The brief frames it as mark-waiting vs. mark-working, on the theory that working may be rarer. The
base rates say something more awkward: **they invert over the day.** Mid-wave, most panes work and
few wait; at wrap-up, most wait and few work. At the moment of measurement, `needs_attention` was
true on 0 of 17 Claude panes and `at_prompt` on 0 of 17 — the terminal cannot even see the
distinction (§1.6). Either fixed polarity is "always on" for half the day, which is precisely the
operator's own rule: *an alarm that ALWAYS fires says as little as one that cannot.*

**Three reasons the answer is still mark-waiting:**

1. **Only one state has an action attached.** Working has no operator action. Idle-legitimately has
   no operator action. Waiting-on-you has exactly one. A readout should carry the bits that change
   behaviour, and only that state does.
2. **Working already self-announces, for free.** The panes carry a live spinner and a ticking
   elapsed timer — *motion*, which is channel 3 in §4.1 and already effective. Marking working
   would be a second signal on a channel that is not empty. Waiting is the genuinely unmarked
   state: the spinner has simply stopped, and *absence of motion is not a pop-out feature.*
3. **Marking working scales the wrong way.** During a 12-pane wave, mark-working paints 11 panes
   and the christmas tree is immediate. Mark-waiting paints 1.

**But the base-rate problem is real, and the fix is not polarity — it is ranking.**

> **Rank, don't threshold.** At most ONE pane wears the strong treatment: the one that has been
> waiting longest. Everything else waiting wears a weak tier.

A threshold ("tint every pane whose wait > 30 s") degenerates to all-on. A rank cannot: the strong
signal is always exactly 1-of-N, so it always carries ~log₂(21) ≈ **4.4 bits**, whether one pane is
waiting or ten. It is structurally incapable of becoming an alarm that always fires. And it gives
the operator a *queue discipline* for free — the thing to do next is always the marked one.

**Strength scales with wait, as the brief suggests — but as rank, not as amplitude.** Amplitude
escalation ("it gets brighter the longer it waits") is the wrong shape: it means the calm state is
also the *ignorable* state, so the system trains the operator to wait for loud. Two fixed tiers,
assigned by rank, are better:

| tier | who | treatment |
|---|---|---|
| **strong** | the single longest-waiting pane | `#26242e` wash + gold bell border + one-shot fade |
| **weak** | every other waiting pane | `#242130` wash only (Weber +25.8%), no border, no onset |
| **none** | working, or idle-with-no-operator-action | untouched |

One escalation is worth keeping, and it is temporal rather than visual: if the strong pane is still
unattended after ~10 minutes, **re-fire the one-shot onset** (§6). Repeating a finite transition is
calm; making a continuous one louder is not.

---

## 6. Animation — one-shot, not a loop, and the reason is mechanical

**A continuous pulse on an idle pane is indefensible over an 8-hour day**, for three separate
reasons:

1. **Peripheral vision is motion-biased.** That is exactly why a loop works and exactly why it is
   intolerable: it re-captures attention on *every cycle*, forever. A signal that interrupts once
   is information; a signal that interrupts every 2 s is a metronome you learn to suppress — and
   once suppressed it is worse than nothing, because it is still costing attention to suppress.
2. **It violates the calm-tech "and back" clause.** A loop never returns to the periphery.
3. **It costs power and it is measurable.** kitty repaints on damage; a scripted colour loop forces
   continuous repaint of that window at `repaint_delay 16` (60 fps) on a laptop, indefinitely.

**Do not script the fade either.** Measured: `kitten @ set-colors` costs **35.8 ms mean, 22.7–50.4
ms range** per call via subprocess. A 12-step fade is ~430 ms of pure overhead with ±28 ms jitter —
visibly uneven, and 12 process spawns per event.

**Use kitty's native visual bell instead.** It is compositor-rendered at frame rate, eased, and
free:

```
visual_bell_duration  0.4 ease-out
visual_bell_color     #2a2733
```

One BEL byte from the Stop hook produces a 400 ms eased wash with zero subprocesses. `ease-out`
(fast in, slow out) is the right curve for an onset: the *arrival* is what captures, and a slow
departure reads as settling rather than blinking. ~400 ms is the sweet spot — long enough to be
seen as a transition rather than a glitch, short enough not to feel like an animation demanding to
be watched. The brief's suggested ~600 ms is also fine; below ~200 ms it reads as a rendering
artefact and above ~800 ms it starts to feel like a UI.

---

## 7. Palette

Against `#1e1e24` with foreground `#e6e6e6`, the harmonising families are the ones whose own
backgrounds sit near this luminance and whose warm accents are yellow-dominant rather than
red-dominant:

- **Rosé Pine** (`base #191724`, `gold #f6c177`, `iris #c4a7e7`, `foam #9ccfd8`) — the closest
  match to the existing background and the best gold. **Use `#f6c177`.**
- **Everforest** (`yellow #dbbc7f`) — warmer/softer, slightly muddier at this luminance.
- **Nord** (`yellow #ebcb8b`, `frost3 #88c0d0`) — cooler-leaning yellow; fine, marginally less
  distinct from the spinner orange.
- **Catppuccin Mocha** (`peach #fab387`, `mauve #cba6f7`) — peach is too close to the existing
  spinner orange (§4.5); mauve is a good *alternative* accent if a non-warm signal is ever wanted.
- **Tokyo Night** (`orange #ff9e64`) — actively collides with the spinner. Avoid.

**Avoiding the christmas tree.** Three rules, in priority order:

1. **One accent, not a set.** The whole vocabulary is blue (focus, already present) + gold
   (waiting, new). Two colours total. Any third state gets encoded on *amplitude* (weak vs strong
   wash), never on a new hue.
2. **The tint is a wash, not a fill.** A live sibling probe on this desktop rendered a pane at
   roughly `#c8a06a` — a fully saturated tan — and it obliterated the text and screamed across the
   whole screen. That is the failure mode, and it is what "subtle" is protecting against. The
   recommended `#26242e` is +40% luminance and near-zero chroma; it reads as *warmth*, not as
   *colour*.
3. **Never tint a pane that is merely busy.** Any treatment applied to the common state is
   decoration. If more than ~2 panes wear a mark at once, the design has failed regardless of how
   restrained each mark is — which is what §5's ranking enforces structurally.

---

## 8. Failure modes shared by the whole approach

Named up front, because each one is a live risk on this box:

- **`enable_audio_bell` defaults to `yes` and is unset in `config/kitty.conf`.** Arming the bell
  without setting it to `no` will make the machine *beep* on every turn end. This is the single
  most likely way the recommendation ships as a disaster.
- **`window_alert_on_bell` defaults to `yes`** → the Dock icon bounces on every BEL. That is
  *useful* as Tier B (§1.5) and *ruinous* if it fires per-pane across 17 panes. Decide explicitly;
  do not inherit the default.
- **The live `~/.config/kitty/kitty.conf` is a DANGLING SYMLINK** into `/private/tmp/adn-land.v9Ngbj/`,
  a wiped worktree. The running process holds a theme whose backing file no longer exists. A
  restart, or any `load-config`, reverts everything to kitty defaults — including
  `active_border_color #00ff00` (green). **Re-point that symlink at
  `~/Development/claude-infrastructure/config/kitty.conf` before shipping any config-based
  treatment**, or the treatment evaporates at the next restart and nobody will know why.
- **Focus clears the bell state, but focus is not a reply.** If the operator glances at the pane
  without answering, the signal is gone. Mitigation: drive the *persistent* tint from the hook's
  own state (cleared on `UserPromptSubmit`, not on focus) and let the bell carry only the onset.
  The two channels must have different clear conditions, deliberately.
- **Tier B is unsolved by anything in §9.** 20 of 21 panes are invisible. A perfect Tier-A
  treatment is still blind to them.

---

## 9. Ranked treatments

### 9.1 ★ `WARM WASH` — whole-pane background lift (SHIP THIS)

**What changes.** The waiting pane's background lifts from `#1e1e24` to `#26242e` — +40.5% relative
luminance, near-zero added chroma, foreground contrast 13.29:1 → 12.24:1. Announced by a 400 ms
eased visual-bell wash. Reinforced by the bell border in `#f6c177`.

**Exact spec.**

```conf
# config/kitty.conf — the standing half
enable_audio_bell      no                  # MUST: default is yes
window_alert_on_bell   yes                 # Tier B: the Dock is the only cross-window channel
bell_border_color      #f6c177             # was #ff5a00; gold, not safety-orange
window_border_width    2pt                 # 4px -> 8px: resolvable to 9.2deg, not 3.4deg
visual_bell_duration   0.4 ease-out        # native, eased, compositor-rendered
visual_bell_color      #2a2733             # a wash, not a flash
```

```bash
# Stop hook (turn ended; the operator is the blocker) — the onset + the state
printf '\a' > "$TTY"                                     # onset: border + eased flash, 0 subprocesses
kitten @ set-colors --match id:"$PANE" background=#26242e  # state: survives a missed onset

# UserPromptSubmit hook (they answered) — clear the state
kitten @ set-colors --match id:"$PANE" background=#1e1e24
```

Rank enforcement (§5): on arming, sort waiting panes by `last_focused_at` from `kitten @ ls`;
the oldest keeps `#26242e`, every other waiting pane is demoted to `#242130` (+25.8%).
Re-fire the BEL once at ~10 min if still unattended.

**Why this one.** It is the only treatment resolvable at every eccentricity on this screen (§1.3);
it is the only per-pane channel kitty actually exposes (§1.4); it pairs a genuine onset with a
genuine persistent state, which §4.2 says is mandatory; it costs one escape byte plus one 36 ms
call per state change; and it degrades gracefully — if the remote-control socket is down, the bell
half still works with no dependencies at all.

**Failure mode.** A tint on a pane whose content has its own background colours (a `less` pager, a
diff with green/red line fills, an editor) will not lift uniformly — kitty's background colour
applies only to cells using the *default* background. Expect patchy washes in panes showing
full-width coloured output. Claude Code's TUI is mostly default-background, so this is a minor risk
here, but it is the reason this treatment is not universally correct.

### 9.2 `GOLD FRAME` — bell border only (runner-up)

**Spec.** As above minus the `set-colors` calls: `bell_border_color #f6c177`, plus
`window_border_width 3pt` and `window_margin_width 1` (the latter overrides `draw_minimal_borders`
so the waiting pane is enclosed by a *complete rectangle* rather than sharing hairlines — Gestalt
closure, and 4× the line length).

**Why it is good.** Zero remote control, zero state to clear, zero chance of desynchronising from
reality: kitty renders it and kitty clears it. The most *robust* option on the board, and the one
to pick if the hook integration cannot be trusted.

**Failure mode, and why it is second.** 12 px is resolvable only to 14.9° — it still fails at the
screen corners (20.8°). And `window_margin_width 1` draws borders around **every** pane, which adds
permanent chrome to all 21 to mark one. The signal is also *purely* static once the flash ends,
which §4.2 says cannot capture attention. It finds the pane once you are looking; it does not make
you look.

### 9.3 `RECEDE` — dim everything that is not waiting (runner-up)

**Spec.** `inactive_text_alpha 0.75`, optionally with `#1b1b20` backgrounds on non-waiting panes.
The Ghostty/WezTerm move (§2.3), inverted from focus to attention.

**Why it is interesting.** It is the most tasteful option by a distance — nothing is ever added,
only removed — and it is the one that best satisfies "beautiful and subtle". Anything that dims 20
panes to leave 1 at full strength produces an enormous *relative* signal with no new ink at all.

**Failure mode, and why it is third.** Three, and they compound. (a) `inactive_text_alpha` is
**global, not per-pane** (§1.4) — it keys on *focus*, so it cannot be conditioned on waiting at
all; implementing this properly means per-pane `set-colors` on all 20 *other* panes, i.e. 20 calls
× 36 ms per state change, and a desync risk on every one of them. (b) Dimming working panes makes
their output harder to read, and the operator *does* read working panes. (c) It is a pure static
cue — no onset whatsoever (§4.2).

### 9.4 `WATERMARK` — per-pane window logo

`kitten @ set-window-logo --match id:N ~/.claude/assets/waiting.png` with `window_logo_alpha 0.12`,
positioned `top-right`. Large-area (so peripherally resolvable), genuinely beautiful, and per-pane
settable. **Failure mode:** static-only, needs image assets per state, overlays content, and a
glyph's *shape* requires foveal acuity — so at 20° it degrades to an undifferentiated smudge,
which is a luminance cue with extra steps. Strictly dominated by 9.1.

### 9.5 `BOTTOM RULE` — an 8–16 px coloured strip along the pane's bottom edge

The tmux `pane-border-status` idea, painted as a row of gold. **Failure mode:** needs either a
margin trick or cooperation from the pane's own content (Claude Code owns that row and redraws
it). Fragile against a TUI that repaints. A good idea in a tmux world; not cleanly buildable here.

### 9.6 ✗ `PULSE` — continuous breathe (do not ship)

Rejected on §6: re-captures forever, never returns to the periphery, 60 fps repaint on battery, and
35.8 ms/±28 ms jitter per scripted step. Listed only so the ranking is honest about having
considered it.

---

## 10. What I could not verify

- **No visual side-by-side of the candidate tints.** `screencapture -l <platform_window_id>`
  returned `could not create image from window` for a background kitty OS window on this build, and
  `kitten @ focus-window` does not raise the OS window above its siblings. The tint values are
  therefore derived from measured luminance against measured baselines, not confirmed by eye.
  **Before shipping, look at `#26242e` next to `#1e1e24` on the real display** — the numbers say it
  is right, but §7's christmas-tree rule is a taste judgement and taste needs a screenshot.
- **`last_focused_at` semantics under a never-focused pane** were not probed; the rank ordering in
  §5 assumes it is a usable wait proxy. If it is null for panes that have never held focus, the
  hook should stamp its own `set-user-vars waiting_since=<epoch>` instead — which is per-pane
  settable and matchable (`--match var:waiting_since=...`), and is the more robust choice anyway.
- **Tier B (cross-window) is scoped, not designed.** The Dock is identified as the only available
  channel; whether a 17-pane fleet can use it without becoming noise is an open question this
  document does not answer.

---

## Sources

- [kitty configuration](https://sw.kovidgoyal.net/kitty/conf/) — option text quoted from the local
  0.48.2 build via `kitty +runpy`, which is version-exact where the web docs are not.
- [WezTerm — Colors & Appearance](https://wezterm.org/config/appearance.html) (`inactive_pane_hsb`)
- [Ghostty appearance config](https://mintlify.wiki/ghostty-org/ghostty/config/appearance);
  [split dividers are hard to see](https://github.com/ghostty-org/ghostty/discussions/3301);
  [separate active split border colour](https://github.com/ghostty-org/ghostty/discussions/2727)
- tmux(1), local man page — `monitor-*`, `*-action`, `visual-*`, `pane-border-*`, `window-style`
- [Feature integration theory](https://en.wikipedia.org/wiki/Feature_integration_theory) (Treisman
  & Gelade 1980); [Forty years after FIT](https://link.springer.com/article/10.3758/s13414-019-01966-3)
- [Jonides & Yantis 1988, Uniqueness of abrupt visual onset in capturing attention](https://pubmed.ncbi.nlm.nih.gov/3362663/)
- [Red-green colour discrimination in peripheral vision](https://pubmed.ncbi.nlm.nih.gov/8447096/);
  [Red-green and yellow-blue opponent-colour responses as a function of retinal eccentricity](https://www.sciencedirect.com/science/article/abs/pii/004269899290055N)
- [Weiser & Brown, The Coming Age of Calm Technology (1996)](https://calmtech.com/papers/coming-age-calm-technology);
  [Principles of Calm Technology](https://www.caseorganic.com/post/principles-of-calm-technology)
