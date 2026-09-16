# `draghold` — synthetic CGEvent drag driver for kitty window drags

A ~60-line macOS C program that posts a left-button mouse drag slowly enough for kitty to begin a
**window drag**, holds at the target so the screen can be photographed mid-drag, then releases.
It is the **only automated route to the mouse leg of a drag** — `kitty @ action` cannot start one,
because a window drag is begun by AppKit from a real event, not by a remote-control command.

It regression-proofs the drag feature. It does not ship it.

---

## Why this file exists at all — the failure it closes

Phase-1 § 6.4 of `docs/research/kitty-drag-action-implementation-2026-09-16.md` recorded this driver
as *"no longer exists in the repo … it survives only as a sentence"*, and instructed:
*"Rebuild it, commit it, and record its invocation, or the next session pays for it again."*

Both halves of that sentence needed correcting, and the correction is the point:

- **It was never IN the repo.** Verified on this branch, and re-verified by W8:
  `git log --all --diff-filter=A -- '*draghold*'` returns **nothing**, and
  `git log --all -S'CGEventCreateMouseEvent'` returns **zero commits on any branch**. There is no
  branch graveyard for it; no `cherry-pick` recovers it.
- **It did not survive only as a sentence.** It survived as CODE — in a
  `/private/tmp/claude-501/<session-uuid>/scratchpad/` directory, which is **per-session and
  reaped, and does not survive a reboot**. Four calling harnesses carrying the invocation § 6.4 says
  was never recorded survived beside it.

The rule this repo already had, from the overlay doc's own tool docstring:

> *annotation that lives in a one-off HTML file is lost on the next render by construction;
> annotation that lives in the command is not.*

So **the invocation is committed here, in this file, not left in a log.** Recording the source
without the working parameters would lose them again — which is exactly the failure being closed.

---

## Provenance and recovery receipts

| file | what it is |
|---|---|
| `draghold-original.c` | the ORIGINAL, recovered **byte-identical**, sha256 `4a43327b652af4a7f9ab315c8b3b8361547fe5108e7beb82aa71658b174f8402` — matching the hash recorded independently in the Q18 probe write-up before this recovery |
| `draghold.c` | that original with the **event loop unchanged** (identical event order, identical timings, identical argv contract — so every recovered harness drives it without edit) plus `--help` / `--dry-run` / `--check`, a verification surface that moves no cursor |
| `build.sh` | the exact compile line |
| `harness-verdict2.sh` | **the instrument that produced the § I9 table below** — screen-flood letter reader, `move_window` control, and the anti-blind-aim ABORT. Committed per the Q18 ruling. Kept verbatim except for two `# shellcheck disable=SC2034` directives and a header banner. 🚨 **Do not run it unmodified** — its socket `/tmp/kitty-vd-$$` matches the `/tmp/kitty-*` glob this repo's tooling scans, and it does not strip the inherited `KITTY_LISTEN_ON`/`KITTY_PID`; both are named in its banner |

`harnesses/` holds the other five recovered callers — `verdict`, `reorder`, `middrag`
(the one that photographed the drag thumbnail), `armcount`, `hislive` — committed for the same
reason as everything else here: they lived only in a reapable scratchpad and do not survive a
reboot. Each carries a RECOVERED-AS-IS banner and a file-level shellcheck directive; their bodies
are unchanged. 🚨 **`harnesses/harness-hislive.sh` is armed to drive the operator's LIVE kitty**
(`SOCK=unix:/tmp/kitty-97084`) and is committed with a refusal guard that exits 9 — it is a
readable record of the technique, not a runnable script. Nothing in it was deleted.

The two surviving copies of the original were diffed against each other and are identical
(`diff` clean, same md5 `97f4a8fa82a539d8ad56f1442064c0ef`). The two compiled binaries differ only
in their build id; the binary is deliberately **not** committed — it is per-arch and the source is
the artifact. `./build.sh` reproduces it.

---

## Build

```sh
./build.sh
# which runs exactly:
#   clang -O2 -Wall -Wextra -o draghold draghold.c -framework ApplicationServices
```

Compiles clean, **zero warnings under `-Wall -Wextra`**, to a Mach-O 64-bit arm64 executable.

Verify it without moving a cursor:

```sh
./draghold --check      # Accessibility grant + display geometry + cursor position. Posts nothing.
./draghold --dry-run 400 300 900 300 3000 4     # prints the full event plan. Posts nothing.
```

`--check`'s `verdict=CAN-POST` / `CANNOT-POST-events-will-be-dropped` is the **negative control for
the whole instrument**: posting to `kCGHIDEventTap` needs Accessibility permission, macOS grants it
to the **parent application** (whatever launched this), not to this binary, and an untrusted parent
makes every post silently dropped — a run that then looks exactly like *"the drag did not start"*.
🚨 The `CANNOT-POST` branch is written but **unexercised** (no untrusted parent was available);
a session that sees it should confirm the branch before believing it.

---

## THE INVOCATION — this is the part § 6.4 asked for

Recovered from four harnesses, all of which resolve `HOLD="$(dirname "$0")/draghold"`:

```sh
"$HOLD" <src_x> <bar_y> <dst_x> <dst_y>  400 120     # the reorder test
"$HOLD" <src_x> <bar_y> <dst_x> <bar_y> 3000 120     # long hold, for the mid-drag capture
```

🚨 **`hold_ms=400` (or `3000`) and `steps=120` — note `steps` is 120, three times the binary's
built-in default of 40.** A commit recording only the source loses these.

Verbatim call sites, as recovered:

```sh
harness-middrag.sh:43   "$HOLD" "$SX" "$BARY" $(( WX + COLW + COLW/2 )) "$BARY" 3000 120
harness-hislive.sh:73   "$HOLD" $(( WX + COLW/2 )) "$BARY" $(( WX + COLW*2 + COLW/2 )) "$BARY" 400 120 2>/dev/null
harness-armcount.sh:93  "$HOLD" "$P1" "$BARY" "$P3" "$BARY" 400 120 2>/dev/null; sleep 1.8
harness-reorder.sh:43   "$HOLD" "$2" "$BARY" "$3" "$4" 400 120 2>/dev/null
harness-verdict2.sh:86  "$HOLD" "$1" "$2" "$3" "$4" 400 120 2>/dev/null; sleep 1.8
harness-verdict.sh:78   "$HOLD" "$1" "$2" "$3" "$4" 400 120 2>/dev/null
```

### Aiming — the part that actually went wrong, twice

- **x is the column centre**: `WX + COLW/2`, `WX + COLW + COLW/2`, `WX + COLW*2 + COLW/2`, with
  `COLW = WW/3`, taking `WX/WY/WW` from System Events:
  ```sh
  osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$KPID"') to get {position, size} of window 1'
  ```
- **y is FOUND, never assumed.** `screencapture -x -o -l<platform_window_id>`, then scan rows for the
  configured pane-bar colours (`#2f62d8` / `#3f5590`, tolerance 14) **starting below `CHROME = 60`
  device px** so a match cannot land on the macOS title bar. `harness-verdict2.sh` **aborts** rather
  than aiming blind: `ABORT: no pane title bar found in the capture — refusing to aim blind`.
- **Divide the found row by `SCALE = PNGW / WW` before adding it to `WY`** — the capture is device
  pixels, CGEvent takes points.

🚨 **`WY + 14` presses macOS's own title bar, not kitty's.** `hide_window_decorations` is not set,
so the top ~28 pt of the window is OS chrome; a mid-drag capture once caught the whole OS WINDOW
sliding across the screen, which is exactly what dragging chrome does.

### Coordinate space and button numbering

CGEvent global display **POINTS** (not device pixels), origin **top-left** of the main display —
the same space System Events reports, which is why they compose without conversion.

`kCGMouseButtonLeft` + `kCGEventLeftMouse{Down,Dragged,Up}` is self-consistent CoreGraphics
numbering. It is **not** GLFW's (LEFT=0 RIGHT=1 MIDDLE=2) and **not** kitty's `mouse_button_map`
`b1/b2/b3` strings; those two traps live on the kitty side of the boundary.

---

## Reading the verdict — three instruments, ascending strength

1. **AppKit delegate callbacks via `kitty --debug-input`** — the strongest, because they prove
   *AppKit really began a session*, not kitty's belief about itself. Grep the debug output for:
   ```
   Dragging session started at:
   Dragging session moved to:
   Dragging session ended at:
   ```
   The file is `glfw/cocoa_window.m`, **not** the sibling `kitty/cocoa_window.m`, and the line
   numbers differ by ref — verified by W8 against both checkouts:

   | ref | path | started / moved / ended |
   |---|---|---|
   | master `1d67ecd` (`/private/tmp/kitty-dev`) | `glfw/cocoa_window.m` | **4287 / 4293 / 4321** |
   | v0.48.2 `2cb1d95` (`/private/tmp/kitty-482`) | `glfw/cocoa_window.m` | **4367 / 4375 / 4408** |

   🚨 `--debug-input` is **not side-effect-free** (phase-1 § 5.12).
   🚨 `--version` cannot tell you which build you are running (master still says 0.48.2). Use
   `kitty +runpy 'import kitty; print(kitty.__file__)'`.
2. **`kitty @ ls` → per-window `neighbors`** — proves the layout actually changed, one JSON call,
   no capture. This is the instrument § I9's correction established. The `windows` **array** is
   creation-order and structurally blind to a reorder; `neighbors` is the layout adjacency.
3. **The screen-flood letter reader** (`harness-verdict2.sh`) — needed only if `neighbors` is
   unavailable.

Whichever is used: **drive `move_window left/right` first and require the reading to move.**

---

## The refutation this tool rests on — § I9's measured table, quoted

The premise that would have killed this tool was the overlay doc's **§ I7** claim that
*"an **NSDraggingSession** is begun by AppKit from a real event and a synthesised stream may be
unable to start one at all. That is a mechanism, not a shrug: it predicts exactly this result."*

**That claim was WITHDRAWN by § I9 of the same file**, in bold —
*"The drag DOES reorder. Every negative in §§ I7-I8 was read from a blind instrument"* — on a
measured four-row table, quoted verbatim from
`docs/research/kitty-pane-title-overlay-2026-09-14.md` (the § I9 table):

```
CONTROL  move_window left            ABC -> ACB      (and right -> ABC)
DRAG     pane1 title -> pane3 title  ABC -> CBB      REORDERED
DRAG     pane1 title -> pane2 title  CBB -> BCB      REORDERED
DRAG     pane1 title -> pane3 body   BCB -> CAC      REORDERED
```

Three drags reordered panes **with a `move_window` control passing in the same run** — which is what
makes it a reading rather than a stub returning success. § I9's own closing rule:
***control the VERDICT instrument, not just the actuator.***

§ I11 goes further and withdraws the whole §§ I7-I10 line: the drag was never broken; the negatives
were about the wrong object. **So a run of this driver that reports no reorder should be suspected of
a blind verdict instrument or a bad aim before it is read as a feature defect.**

### What is NOT measured, stated so it is not re-derived as a story

§ I9 item 1 says the predecessor *"warps, presses, moves and releases in milliseconds"* and that
draghold's slowness is what made the drag start. **Read side by side, the sources do not say that.**
The predecessor `drag.m`:

| | `drag.m` (predecessor) | `draghold.c` |
|---|---|---|
| warp first | **no** — posts `MouseMoved` only | **yes** — `CGWarpMouseCursorPosition` |
| hover before press | 120 ms | 250 ms |
| **press dwell** | **160 ms** | **120 ms — SHORTER** |
| per-step | 18 ms × 30 = 540 ms | 12 ms × 40 = 480 ms |
| at target | fixed 200 ms | `hold_ms`, 400–3000 ms |

The predecessor is not "milliseconds"; its press dwell is **longer** and its motion slower per step.
The real deltas are the **warp** and the **hold**. **Which delta makes the drag start is UNMEASURED**
— isolating it needs a warp-vs-no-warp A/B at fixed aim, firing real events at a sandbox kitty.

⇒ **Keep the timings, because they are known-good. Do not spend a session tuning dwell on that
sentence.**

---

## 🚨 Safety — read before running anything here

This binary posts to the **system-wide HID event tap**. It is not scoped to one application, it
**moves the real cursor**, and it holds the left button down for the whole drag.

| | Rule |
|---|---|
| **1** | **Never run it while anyone is using the machine.** A drag at `400 120` captures the cursor for ~2.2 s; at `3000 120` for ~4.8 s. Check first: `ioreg -c IOHIDSystem \| awk '/HIDIdleTime/ {print $NF/1000000000" s idle"; exit}'` |
| **2** | **Never point it at the operator's live kitty.** Launch a sandbox instance and aim inside that window only. |
| **3** | Sandbox launch must use its **own** `KITTY_CONFIG_DIRECTORY`, a socket **outside** the `/tmp/kitty-*` glob (`bin/cc-kitty-socket` scans it), and must strip the inherited vars: `env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID`. Unix socket paths cap at ~104 chars — use a short one like `/tmp/kdw8.sock`. |
| **4** | **Never write to `~/.config/kitty`** — it symlinks into the shared checkout, and a live `__watch_conf__` child SIGUSR1s the operator's kitty ~100 ms after any write there. |
| **5** | `--check` and `--dry-run` post nothing and are always safe. Use them to verify the tool; the cursor position read back by `--check` before and after a `--dry-run` is the control that proves it. |
| **6** | The harnesses call `screencapture -C`, which captures the **whole screen**, not one window. |

### The live reproduction, ready to paste

Not run by W8 — `--check` reported `accessibility_trusted=YES` (so the posts would land) while
`HIDIdleTime` read **131 s**, i.e. the operator was at the machine. Firing was declined on that
measurement, per rule 1. To reproduce a drag when the machine is genuinely free:

```sh
cd tools/draghold && ./build.sh && \
env -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_WINDOW_ID \
  KITTY_CONFIG_DIRECTORY=/private/tmp/kdw8-conf \
  /private/tmp/kitty-482/kitty/launcher/kitty --debug-input \
  --listen-on unix:/tmp/kdw8.sock -o allow_remote_control=yes 2>/private/tmp/kdw8-debug.log &
# then split to 3 panes, find WX/WY/WW via System Events, find BARY by bar colour (above), and:
#   ./draghold $(( WX + COLW/2 )) "$BARY" $(( WX + COLW*2 + COLW/2 )) "$BARY" 400 120
grep -c 'Dragging session started at:' /private/tmp/kdw8-debug.log    # the verdict
```
