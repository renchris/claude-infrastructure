# Launch video: what it shows

Source: https://video.twimg.com/amplify_video/2107925353373085696/vid/avc1/1280x720/j1GSyiOhsIrmgSx7.mp4?tag=29
Local copy: /tmp/browser-sdk/launch.mp4 (4,699,588 bytes, measured with `ls -la`)
Frames: /tmp/browser-sdk/frames/f-001.png to f-030.png (30 frames, measured with `ls | wc -l`)

## File facts (measured with ffprobe)

- Duration 60.05 s, 1280x720, H.264 video, AAC stereo audio at 48 kHz.
- Audio track exists and is not silent: mean -15.5 dB, max -2.0 dB (measured with `ffmpeg -af volumedetect`).

## Transcript

There is no transcript. `whisper` and `mlx_whisper` are not installed. `whisper-cli` is installed at
/Users/chrisren/bin/whisper-cli, but the only model file found on the machine is
/opt/homebrew/share/whisper-cpp/for-tests-ggml-tiny.bin (575 KB, a test stub, not real weights), so
no usable transcription was possible. I did not download a model. Whether the audio is speech or
only music is NOT STATED by anything I could read; all findings below come from on-screen text.

## Timestamps

Frames were taken one every 2 seconds. Times below are estimated as 2 x (frame number - 1) seconds,
accurate to roughly plus or minus 1 second. Text that scrolled past between sampled frames is not
captured.

## Sequence in one paragraph

Three numbered figures, all run by `CLAUDE-HAIKU-5-5`, then an end card. FIG 1 (0-15 s): the computer
toolset rotates a 3D model of a router, zooms on its underside label, reads the serial number, types
it into a form and saves. FIG 2 (16-23 s): the same computer toolset and driver work a map page by
scrolling and dragging, then click a marker and zoom on its popup. FIG 3 (24-51 s): the browser
toolset reads a CRM page into element refs, fills a lead form by ref from three scanned handwritten
cards, hits a stale-ref error and recovers. End card (52-59 s): title, two install commands, two
toolset version strings.

## Frame-by-frame, verbatim on-screen text

### FIG 1: computer toolset, 3D viewer (f-001 to f-008, about 0-15 s)

Header, f-001 to f-003: `VIEWER3D.HTML · 1280×800` and `CLAUDE-HAIKU-5-5  COMPUTER TOOLSET → DRIVER`
Header, f-004 to f-008: `VIEWER3D.HTML · 1280×800` and `COMPUTER TOOLSET · CLAUDE-HAIKU-5-5`

f-001 (about 0 s). Caption: "FIG 1  Computer use in the Claude SDK: each action is a typed call."
Page shows a dark router seen from below with a label. Log panel:

    ▶ screenshot
    ✓ image/png 366 KB
    ▶ left_click_drag
      [500, 300] → [500, 150]
    BetaComputer
      LeftClickDragInput
    → driver.left_click_drag()
    ✓ Dragged.
    ▶ wait
    ✓ Waited 1s.

f-002 (about 2 s). Same caption. Log adds:

    ▶ wait
      1 s
    ✓ Waited 1s.
    ▶ screenshot
    ✓ image/png 394 KB

f-003 (about 4 s). Same caption. Log:

    ✓ image/png 394 KB
    › The underside label is now visible. I'll zoom in on the viewer to read the serial number accurately.
    ▶ scroll
      "up" × 5  at [490, 440]
    BetaComputer
      ScrollInput
    → driver.scroll()
    ✓ Scrolled up.

f-004 (about 6 s). Caption: "FIG 1  Scroll zooms. zoom rereads one region." The page's side panel is
visible: "Received 2026-10-02", "Serial  not recorded", "The serial number is printed on the
compliance label on the underside of the unit.", a "Reset view" button, a "Serial number" field.
Label on the router reads "NORTHWIND NX-200", "Edge router · Model NX-200-8P", "Input 12V 2.5A · Made
in Portugal", "S/N NX2-7K4-1185". Log:

    ✓ Scrolled up.
    ▶ wait
      1 s
    ✓ Waited 1s.
    ▶ screenshot

f-005 (about 8 s). Same caption. An orange bracket frames the label. Log:

    ▶ zoom
      region [340, 340, 700,…      (rest cut off on screen)
    BetaComputer
      ZoomInput
    → driver.zoom()
    ✓ BetaScreenshotResult

f-006 (about 10 s). Caption: "FIG 1  A second zoom, closer. Serial read." A smaller bracket frames the
serial line. Log:

    → driver.zoom()
    ✓ BetaScreenshotResult
    ▶ zoom
      region [390, 390, 600,…      (rest cut off on screen)
    ✓ image/png 23 KB

f-007 (about 12 s). Caption: "FIG 1  Click, type, Save." Page shows "Serial number" field with
placeholder "NX2-…" and a "Save" button. Log:

    ✓ image/png 23 KB
    › The serial reads NX2-7K4-1185. I'll type it into the field and save.
    ▶ left_click
      [1096, 379]
    ✓ Clicked.
    ▶ typ          (mid-animation; the word is being typed out, presumably "type")

f-008 (about 14 s). Same caption. Field now holds "NX2-7K4-1185"; page says "Saved. Serial matches the
shipment record." Log:

    ▶ left_click
      [1238, 379]
    ✓ Clicked.
    ▶ wait
      1 s
    ✓ Waited 1s.
    ▶ screenshot
    ✓ image/png 412 KB

### FIG 2: computer toolset, map (f-009 to f-012, about 16-23 s)

Header, f-009 and f-010: `COMPUTER TOOLSET → DRIVER`, `MAP.HTML · 1280×800`, `CLAUDE-HAIKU-5-5`
Header, f-011 and f-012: `MAP.HTML · 1280×800` and `COMPUTER TOOLSET · CLAUDE-HAIKU-5-5`

f-009 (about 16 s). Caption: "FIG 2  Same driver, now a map: scroll, drag." Page: "Harbor services
map", "Drag to pan, scroll or +/− to zoom. Click a marker for details. Markers and their names appear
as you zoom in." Legend: Hospital, Ferry, Market, Museum, Park office. Place names: Port Avery,
Westmarch, Calder Bay. Footer: "zoom 1.1× · 800 m per 100 px". Log:

    ▶ screenshot
    ✓ image/png 84 KB
    › Port Avery is in the top-right. I'll zoom in on it by scr      (still typing)
    ▶ scrol                                                          (still typing)

f-010 (about 18 s). Same caption. Map is zoomed on Port Avery. Log:

    ▶ screenshot
    ✓ image/png 82 KB
    › Port Avery is near the top-right edge. I'll pan it toward the center and zoom further.
    ▶ left_click_drag
      [1050, 300] → [700, 500]
    BetaComputer
      LeftClickDragInput
    → driver.left_click_drag()

f-011 (about 20 s). Caption: "FIG 2  Five more notches, then click the marker." Red and blue markers
now visible at Port Avery. Log: "› The service markers are now visible" (still typing).

f-012 (about 22 s). Same caption. A popup is open and bracketed in orange: "Port Avery ferry
terminal", "Address 1 Quay Road, Port Avery", "Phone (0191) 555 0144", "Hours Sailings 06:40, 09:15,
12:30, 16:05, 19:20". Log:

    ▶ screenshot
    ✓ image/png 78 KB
    ▶ zoom
      region [816, 410, 10…      (rest cut off on screen)
    ✓ image/png 14 KB

### FIG 3: browser toolset, CRM lead entry (f-013 to f-026, about 24-51 s)

f-013 and f-014 (about 24-27 s). Full-screen dark panel. Caption: "FIG 3  read_page: every field gets
a ref." A highlight bar moves down the rows (on "Full name" in f-013, on "Plan interest" in f-014).

    ▶ read_page   filter "all"
    BetaBrowserReadPageInput  → str
    …  14 refs above the form: nav, inbox, scan controls
    - textbox "Full name" [ref_15] value=""
    - textbox "Company" [ref_16] value=""
    - textbox "Email" [ref_17] value="" type=email
    - textbox "Phone" [ref_18] value=""
    - textbox "Role / title" [ref_19] value=""
    - combobox "Plan interest" [ref_20] value="Choose…"
    - spinbutton "Seats" [ref_25] value="" type=number
    …  16 rows between: labels, options, 2 radios
    - textbox "Notes" [ref_28] value=""
    - button "Clear" [ref_29]
    - button "Save lead" [ref_30]

Header, f-015 to f-019: `CRM.HTML · 1280×800` and `CLAUDE-HAIKU-5-5  BROWSER TOOLSET → DRIVER`
Header, f-020 to f-026: `CRM.HTML · 1280×800` and `BROWSER TOOLSET · CLAUDE-HAIKU-5-5`

f-015 (about 28 s). Caption: "FIG 3  form_input fills a field by ref. No coordinates, no keys." Page:
left, a scanned card "NORTHWIND CLOUD / Booth lead card · DevDays 2026 / #01" with handwriting: Name
Priya Raman, Company Halcyon Freight, Email priya.raman@halcyonfreight.example, Phone (415) 555-0142,
Role Ops lead, Interested in: Team checked (Starter, Enterprise unchecked), Team size (seats) 40,
Follow up by: Email circled, Notes "Wants SSO + audit log. Demo week of Nov 10." Right, an empty form
(Full name, Company, Email, Phone, Role / title, Plan interest "Choose...", Seats, Follow up by
Email/Phone, Notes, Clear, Save lead) and a table "NAME COMPANY PLAN SEATS / No leads entered yet."
Source line: "Source: DevDays 2026 booth · typed from the scanned card on the left". Log:

    ▶ screenshot
    ✓ image/png 225 KB
    ▶ read_page
      filter "all"
    BetaBrowserReadPageInput
    ✓ str  56 lines
    ▶ zoom
      region [320, 190, 750, 4…      (rest cut off on screen)

f-016 (about 30 s). Same caption. Log:

    ▶ zoom
      region [320, 190, 750, 4…
    ✓ image/png 46 KB
    ▶ zoom
      region [320, 420, 750, 6…
    ✓ image/png 40 KB
    › Card 1 reads clearly: Priya Raman, Halcyon Freight, Team plan, 40 se      (still typing)
    ▶ for                                                                       (still typing)

f-017 (about 32 s). Same caption. Form now filled: Priya Raman, Halcyon Freight,
priya.raman@halcyonfreight.example, (415) 555-0142, Ops lead, Plan interest "Team". Log:

    ▶ form_input
      ref_18 ← "(415) 555-0142"
    ✓ Set the value of ref_…
    ▶ form_input
      ref_19 ← "Ops lead"
    ✓ Set the value of ref_…
    ▶ form_input
      ref_20 ← "Team"
    ✓ Set the value of ref_…
    ▶ form_i          (still typing)

f-018 (about 34 s). Caption mid-typing: "FIG 3  Stale ref: a ToolError". Page: Follow up by Email
selected, Notes "Wants SSO + audit log. Demo week of Nov 10." Log:

      ref_26
    ✓ Clicked.
    ▶ form_input
      ref_28 ← "Wants SSO + au…
    ✓ Set the value of ref_…
    ▶ screenshot
    ✓ image/png 244 KB
    › All fields match the card. Saving, then      (still typing)

f-019 (about 36 s). Caption: "FIG 3  Stale ref: a ToolError. find recovers it." Page: "SCANNED CARDS"
sidebar (Card 1 entered, Card 2 to do, Card 3 to do), "Card 2 of 3", zoom controls "− 100% +", "Next
card ▸", form heading "New lead", toast "Saved Priya Raman", table row "Priya Raman / Halcyon Freight
/ Team / 40". Card 2 (#02): Marcus Odell, Brightline Clinics, m.odell@brightline.example,
312-555-0187, IT director, Enterprise checked, 250 seats, Phone circled, Notes "HIPAA question - send
security whitepaper first." Log:

      ref_30
    ✓ Clicked.
    ▶ wait
      1 s
    ✓ Waited 1s.
    ▶ left_click
      ref_8
    BetaBrowser
      LeftClickInput
    → driver.left_click()
    ✕ unknown or stale ref …      (rest cut off on screen)

The `find` call that the caption says recovers the ref is not visible in any sampled frame.

f-020 (about 38 s). Caption: "FIG 3  Card two, same refs, at speed." No log panel. Card 2 enlarged
with an orange bracket around the plan, seats and notes area; form empty; table shows the Priya Raman
row.

f-021 (about 40 s). Same caption. Card 2 now marked entered; card 3 shown (cursive, red ink); table
now also has "Marcus Odell / Brightline Clinics / Enterprise / 250".

f-022 (about 42 s). Same caption. Motion-blurred transition frame; no readable text beyond the header
and caption.

f-023 (about 44 s). Caption: "FIG 3  Too small to read: it enlarges the scan." Page: left nav "Dash,
Leads, Accts, Rpts"; "Card 3 of 3"; zoom control now reads "175%"; card #03: Name Lena Vogt, Company
Tidewater Studio, Email lena@tidewater.example, Phone +1 206 555 0119. Orange bracket around
company, email and phone.

f-024 (about 46 s). Caption mid-typing: "FIG 3  Three handwrit". Form filled: lena@tidewater.example,
+1 206 555 0119, Founder, Starter, 6, Email selected, Notes "Tiny team, price sensitive. Loved the
mobile app."

f-025 (about 48 s). Caption: "FIG 3  Three handwritten cards. 67 calls, 46 seconds, no typos." Form is
empty again (saved); cursor on "Save lead".

f-026 (about 50 s). Same caption. Card "3 of 3" at 175%, empty "New lead" form.

### End card (f-027 to f-030, about 52-59 s)

f-027 (about 52 s). Pixel-art Claude Code mascot and the title: "Computer use and browser use, in the
Claude SDKs."

f-028 (about 54 s). Adds two terminal pills: `$ pip install anthropic` and `$ npm install @anthropic`
(still typing).

f-029 and f-030 (about 56-59 s). Final state:

    Computer use and browser use,
    in the Claude SDKs.
    $ pip install anthropic
    $ npm install @anthropic-ai/sdk
    FIG 1-3   COMPUTER_TOOLSET_20260801   BROWSER_TOOLSET_20260801

## Identifiers seen, collected

- Model label: `CLAUDE-HAIKU-5-5` (shown upper case in the header on every demo frame). It is a
  header label, not a code string; the exact API model id string is NOT STATED.
- Toolset version labels (end card, upper case): `COMPUTER_TOOLSET_20260801`,
  `BROWSER_TOOLSET_20260801`. The exact lower-case `type` strings as sent to the API are NOT STATED.
- Header labels: `COMPUTER TOOLSET → DRIVER`, `BROWSER TOOLSET → DRIVER`.
- Computer toolset actions shown: `screenshot`, `left_click_drag`, `wait`, `scroll`, `zoom`,
  `left_click`, and one cut off at `typ` (presumably `type`).
- Browser toolset actions shown: `screenshot`, `read_page` (with `filter "all"`), `zoom`,
  `form_input`, `left_click` (by ref), `wait`. `find` is named in a caption only.
- Type names shown: `BetaComputer` / `LeftClickDragInput`, `BetaComputer` / `ScrollInput`,
  `BetaComputer` / `ZoomInput`, `BetaScreenshotResult`, `BetaBrowserReadPageInput` (`→ str`),
  `BetaBrowser` / `LeftClickInput`. Each pair is printed on two lines; whether the real class name
  is the two joined (for example `BetaComputerLeftClickDragInput`) is likely but NOT STATED.
- Driver method calls shown: `driver.left_click_drag()`, `driver.scroll()`, `driver.zoom()`,
  `driver.left_click()`.
- Error name: `ToolError` (caption), with message starting "unknown or stale ref".
- Element ref format: `ref_8`, `ref_15` … `ref_30`.
- Install commands: `pip install anthropic`, `npm install @anthropic-ai/sdk`.
- Viewport: all three demo pages are labeled `1280×800`.

## Claims made on screen

1. "Computer use in the Claude SDK: each action is a typed call." (f-001 to f-003)
2. "Scroll zooms. zoom rereads one region." (f-004, f-005)
3. "A second zoom, closer. Serial read." (f-006)
4. "Same driver, now a map: scroll, drag." (f-009, f-010)
5. "read_page: every field gets a ref." (f-013, f-014)
6. "form_input fills a field by ref. No coordinates, no keys." (f-015 to f-017)
7. "Stale ref: a ToolError. find recovers it." (f-019)
8. "Card two, same refs, at speed." (f-020 to f-022)
9. "Too small to read: it enlarges the scan." (f-023)
10. "Three handwritten cards. 67 calls, 46 seconds, no typos." (f-025, f-026). This is the only
    performance number in the video. What the 46 seconds covers (wall clock of the whole run or
    something else) is NOT STATED.
11. "Computer use and browser use, in the Claude SDKs." (f-027 to f-030)

## NOT STATED in the video frames

- No import lines, no client construction, no agent-loop code and no source code of any kind. Only
  action logs, type names and install commands appear.
- No driver vendor is named. Browser Use, Browserbase, E2B and Daytona do not appear; only the word
  `DRIVER` and `driver.<method>()` calls.
- No beta header string, no exact tool `type` string, no exact model id string.
- No SDK version numbers, no pricing, no token counts, no cost figures.
- No statement of where the browser runs (local or cloud) or which browser engine is used.
- Which driver ran the demo pages.
- Any comparison with other models or with earlier computer-use tools.
- The full region arguments to `zoom` and the full stale-ref error text (both cut off on screen).
