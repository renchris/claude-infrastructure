# Evidence for the zero-shift pane title band

Each image is a capture of a SANDBOX kitty, never the operator's live terminal.

| file | what it shows |
|---|---|
| `patched-band-system-font.png` | the band drawn by the C patch. The title is in the macOS system sans face (CoreText, via `render_a_bar` -> `draw_window_title` -> `cocoa_render_line_of_text`), the body below it is Monaco — the two faces in one frame is the point. The band is exactly one cell tall and flush at the top; the content below it has not moved. |
| `patched-cursor-hand-vs-ibeam.png` | LEFT: pointer over the band with the band ON — a hand. RIGHT: the same screen point with the band OFF — an I-beam. Same app, same activating click, one variable. The right half is what makes the left half evidence. |
| `shim-cursor-hand-vs-ibeam.png` | the same A/B for the Python shim on a STOCK, unpatched kitty. This is the pair the research left unmeasured, because posting synthetic events needed an instrument the research axis declined to build. |

The pointer was verified to be at the sampled coordinate by an independent reading
(`draghold --check` prints `cursor_now=`) in the same run as each capture, so a missing cursor
could not be read as "no hand".
