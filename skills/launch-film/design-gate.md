# A design gate for launch films, and three lessons from a cut film

Beside `SKILL.md` §8, for films drawn by a web page or canvas. Written after a 2026-09-28 film passed every encoding
check and was rejected on sight as "looks very broken": type struck through by rule lines, a card caught
mid-transform, frames with no subject, type too small to read at 1080p. None of those checks measured design.

## 1. Make the page report its own layout, then gate on it

The composition already draws every element itself, so it can also say what it drew. Give the page one more hook next
to `__render`:

```js
window.__layout = (t) => { LAYOUT = { texts: [], lines: [], rects: [] }; renderAt(t); const L = LAYOUT; LAYOUT = null; return L }
// inside the draw code, one record per call:  texts {x, y, w, h, px, role}, lines {x1, y1, x2, y2, w}, rects {..., moving}
```

Coordinates in 1080p CSS px, because 1080p is the size a film is judged at. `kit/design_gate.py` drives it through
`render.mjs eval`, samples the first, middle and last frame of every shot plus every 6th frame, and fails on:

| | defect | rule |
|---|---|---|
| D1 | text crossed by a line | no text box touches a line segment (its own stroke width + 2 px) |
| D2 | text on text | the headline/card lines overlap no other text box |
| D3 | unreadable type | every read ≥ 28 px at 1080p; a headline ≥ 72 px; the product name ≥ 84 px |
| D4 | out of frame | headline and card lines inside the safe area |
| D5 | mid-transform text | no moving shape covers a text box |
| D6 | a film-specific invariant | e.g. the one line every shot is framed on sits at the same place in every frame |

**Mutation-test the gate before trusting it.** Push the headline onto the line and remove its clear band; the gate must
fail (it failed 319 frames on v3), then pass again on the real page. A gate that has never failed proves nothing, and
the previous film's gates had never failed.

**Read the clock from the cue export, and say what ran.** Duration, beats and splices come from the film's own cue
file, never from constants. The 2026-10 gate kept its 25.0 s story clock and its old beat list after the edit spliced
in 255 close-up frames and a restage removed two cuts. Its film-mode frame count expected 1,500 frames against a
1,755-frame master, so its "DESIGN PASS" on the final was the page-layout check alone. A gate prints which checks ran
and the frame count it read; a pass with a skipped section is a fail.

It earned its place twice in one build: D5 caught the opening collapse sliding over the `❯`, and D3 would have caught
panes that re-tiled wider between captures (their type shrank below the others) had the contact sheet not caught it
first.

## 2. Capturing a product's live UI (when UI is a beat, not the carrier)

A whole film of real UI read as "very "tutorial"" (2026-10-03), and real screens in a dark set as "so dark, b-roll
abstract and gloomy" (2026-10-01). When a beat does need a real pane, `kitty @ get-text --match id:<n> --extent screen
--ansi` returns a live pane's screen with its real colours. Claude Code runs on the alternate screen, so there is **no
scrollback**: `--extent all` returns the screen and nothing more. To collect varied real states, poll snapshots (a
detached script every ~45 s, deduplicated by hash, only panes whose cwd is the product's) and freeze the pool before
the final build, because panes re-tile and a "latest capture" changes size under you. Leave out panes whose content
names another project, a person or a customer.

## 3. Hard cuts and motion blur do not mix

`render.mjs --sub N` averages N subframes spread across ±¼ frame. A hard cut that falls inside that window blends two
shots into a ghosted frame. A film made of cuts renders at `--sub 1` (it is also N× faster: v3's 1368 4K frames took
about 3 minutes); keep blur for films whose motion is continuous, or place every cut at a mid-frame time.

## 4. zsh does not split an unquoted variable

The Bash tool is zsh. `node render.mjs stills $T` with `T="0.3 1.0 …"` passes one argument, renders one `t-NaN.png`,
and a purity check over it "passes" with one frame compared. Use an array (`T=(0.3 1.0 …)`, reverse with `${(Oa)T}`)
or `${=T}`, and assert the frame count the check compared.
