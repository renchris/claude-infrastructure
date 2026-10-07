# computer-toolset quickstart: what the code says

Source: every file under `/tmp/browser-sdk/cq/computer-toolset` read in full (11 files, 1,078 lines, measured with `wc -l`). Nothing was run. Cites are `file:line` relative to that directory. "NOT STATED" means these files do not say it.

Scope warning: this quickstart covers the **computer** toolset only. It never mentions a browser toolset, Browser Use, Browserbase, E2B or Daytona. Anything about those is NOT STATED here.

## 1. What it does end to end

1. You start a passwordless VNC server on a throwaway desktop (README.md:27-32).
2. `run.py` / `run.ts` joins the command line into one task string, with a default task of "Open a terminal, run date, and tell me today's date and time zone." (python/run.py:45, typescript/run.ts:30-31).
3. It builds an Anthropic client and the example driver `VncComputer`, which connects to the VNC server and does the RFB handshake at construction (python/run.py:47-50, typescript/run.ts:32-50).
4. It passes the driver object itself as the only entry in `tools` to the SDK's beta tool runner (python/run.py:57-62, typescript/run.ts:53-58).
5. The SDK runs the agent loop. The model calls each desktop action as its own tool, and the driver runs each call on the desktop (README.md:3).
6. The script iterates the runner and prints every model message until the model finishes (python/run.py:63-64, typescript/run.ts:59-61).
7. Before every action except `screenshot`, a `confirm` callback prints the call and runs it only on a `y` answer (python/run.py:33-38, typescript/run.ts:39-49).
8. The script, not the tool runner, closes the driver (python/run.py:54-56, typescript/run.ts:51, 62-65).

The driver is described as showing the interface and "not production code" (README.md:5, python/vnc_computer.py:4).

## 2. Exact SDK calls, type strings, flags, models, versions

### Tool type string and names
- Toolset type string: `computer_toolset_20260801`, stated only in prose (README.md:3). The code never writes this string; it comes from the SDK base class.
- "You declare one toolset entry in `tools`" (README.md:3).
- Toolset name on a tool call: `toolset_name="computer"` (python/exercise.py:39, typescript/exercise.ts:43).
- Base class: `BetaAbstractComputerToolset20260801` (python/vnc_computer.py:28, 72; typescript/vnc-computer.ts:23, 98).

### Beta flags
- NOT STATED. Neither `run.py` nor `run.ts` passes a `betas` argument or a beta header. The only "beta" is the namespace `client.beta.messages` (python/run.py:57, typescript/run.ts:53). Whether the SDK adds a beta header itself is NOT STATED.

### Model
- Default `claude-sonnet-5-5`, overridable with env `MODEL` (python/run.py:58, typescript/run.ts:54, README.md:64). No other model id appears.

### Python SDK calls
- `from anthropic import Anthropic, AnthropicError` (python/run.py:27)
- `from anthropic.tools.computer import BetaComputerConfirmContext` (python/run.py:28)
- `from anthropic.tools import ToolError` (python/vnc_computer.py:26)
- `from anthropic.tools.computer import BetaAbstractComputerToolset20260801, BetaScreenshotResult, BetaToolsetCallContext` (python/vnc_computer.py:27-31)
- Input types from `anthropic.types.beta`: `BetaComputerScreenshotInput`, `BetaComputerDoubleClickInput`, `BetaComputerKeyInput`, `BetaComputerLeftClickInput`, `BetaComputerMouseMoveInput`, `BetaComputerRightClickInput`, `BetaComputerScrollInput`, `BetaComputerTripleClickInput`, `BetaComputerTypeInput`, `BetaComputerWaitInput` (python/vnc_computer.py:32-43)
- `client.beta.messages.tool_runner(model=..., max_tokens=4096, tools=[computer], messages=[{"role": "user", "content": task}])` (python/run.py:57-62)
- The driver is a context manager: `with computer:` (python/run.py:56)
- Direct entry point with no model: `computer.tool_result(tool_use)` where `tool_use = BetaToolUseBlock(type="tool_use", id=..., name=..., input=..., toolset_name="computer")` (python/exercise.py:39-40), with `BetaToolResultBlockParam, BetaToolUseBlock` from `anthropic.types.beta` (python/exercise.py:30)

### TypeScript SDK calls
- `import Anthropic from '@anthropic-ai/sdk'` (typescript/run.ts:26)
- `BetaAbstractComputerToolset20260801, ToolError, type BetaScreenshotResult, type BetaComputerToolsetOptions, type BetaToolsetCallContext` from `@anthropic-ai/sdk/helpers/beta/toolsets` (typescript/vnc-computer.ts:22-28)
- Input types from `@anthropic-ai/sdk/resources/beta` (typescript/vnc-computer.ts:29-39)
- `client.beta.messages.toolRunner({ model, max_tokens: 4096, tools: [computer], messages: [{ role: 'user', content: task }] })` (typescript/run.ts:53-58)
- Direct entry point: `computer.toolResult({ type: 'tool_use', id, name, input, toolset_name: 'computer' })` (typescript/exercise.ts:38-44), described as running "the same pipeline as the tool runner" (typescript/exercise.ts:10)

### Not passed to the runner
- No system prompt, no `betas`, no iteration cap, no thinking settings, no display-size setting. `max_tokens` is 4096 in both (python/run.py:59, typescript/run.ts:55).

### Package versions
| Package | Version | Cite |
| --- | --- | --- |
| `anthropic` (Python) | `>=1.12.0` | python/requirements.txt:2 |
| `pillow` | `>=10` | python/requirements.txt:3 |
| `typing_extensions` | `>=4.14` | python/requirements.txt:4 |
| `@anthropic-ai/sdk` | `^0.132.0` | typescript/package.json:15 |
| `pngjs` | `^7.0.0` | typescript/package.json:16 |
| `tsx` | `^4.19.0` | typescript/package.json:21 |
| `typescript` | `5.8.3` | typescript/package.json:22 |
| `@types/node` | `^20.17.6` | typescript/package.json:19 |
| `@types/pngjs` | `^6.0.1` | typescript/package.json:20 |
| Node | `>=20` | typescript/package.json:7, README.md:26 |
| Python | 3.10+ | README.md:26 |

`package-lock.json` is git-ignored, so exact resolved versions are NOT STATED (.gitignore:4).

## 3. The driver interface, as the VNC example implements it

### Shape
- Subclass the abstract toolset and override one method per tool, named after the tool (python/vnc_computer.py:149-217, typescript/vnc-computer.ts:223-324).
- Python signature: `def <tool>(self, context: BetaToolsetCallContext, input: <BetaComputer...Input>)`, returning `None`, or `BetaScreenshotResult` for `screenshot` (python/vnc_computer.py:150-152, 176).
- TypeScript: `protected override <tool>(_ctx: BetaToolsetCallContext, input: ...)`, returning `void` or a Promise. Methods may be sync or async (typescript/vnc-computer.ts:261-264, 289, 300).
- Naming difference: Python overrides `type` (python/vnc_computer.py:208); TypeScript overrides `type_` (typescript/vnc-computer.ts:309). The TypeScript `screenshot()` takes no arguments (typescript/vnc-computer.ts:223).
- Constructor: SDK toolset options (`configs`, `confirm` "and the rest") pass through to `super()` unchanged (python/vnc_computer.py:73-77, typescript/vnc-computer.ts:92-95, 121). `configs` is named but never used; what it does is NOT STATED.
- Python connects in `__init__` (python/vnc_computer.py:79-83). TypeScript uses a private constructor plus `static async connect()` (typescript/vnc-computer.ts:104-122).
- `close()` must call `super.close()` and then release the transport (python/vnc_computer.py:119-123, typescript/vnc-computer.ts:124-127).
- A method you do not override is a tool the SDK reports as disabled, does not offer to the model, and refuses if called (python/vnc_computer.py:6, python/exercise.py:120, typescript/exercise.ts:109, README.md:81).
- Errors: raise `ToolError` for a mistake the model should see; it comes back as a `tool_result` with `is_error` (python/vnc_computer.py:68, 128; python/exercise.py:116-119). Connection and protocol failures raise `RuntimeError` / `Error` instead (python/vnc_computer.py:116, 160, 166; typescript/vnc-computer.ts:175-177, 235, 248). How the SDK treats a non-`ToolError` exception mid-run is NOT STATED.
- What the SDK supplies: tool schemas, refusal of unimplemented tools, the tool runner (README.md:81).

### Full tool list per the README (17)
Implemented (10): `screenshot`, `left_click`, `right_click`, `double_click`, `triple_click`, `mouse_move`, `scroll`, `type`, `key`, `wait` (README.md:81).
Left out (7): `zoom`, `left_click_drag`, `left_mouse_down`, `left_mouse_up`, `middle_click`, `hold_key`, `cursor_position` (README.md:87).

### Input fields seen in the code
- `coordinate`: `[x, y]`; optional on clicks (python/vnc_computer.py:137-139, 177; typescript/vnc-computer.ts:207, 211)
- `text`: on clicks and scroll it is a modifier chord held during the action; on `key` it is the key or chord; on `type` it is the text (python/vnc_computer.py:141, 182, 198, 202, 209)
- `scroll_direction`: `up` / `down` / `left` / `right`; `scroll_amount`: integer (python/vnc_computer.py:60, 198; typescript/vnc-computer.ts:296-297)
- `repeat`: on `key`, defaults to 1 (python/vnc_computer.py:203, typescript/vnc-computer.ts:303)
- `duration`: on `wait`, in seconds (python/vnc_computer.py:217, typescript/vnc-computer.ts:323)
- `region`: on `zoom`, e.g. `[0, 0, 100, 100]` (python/exercise.py:121). The driver does not implement it.

### Connection and handshake
- TCP to `host:port`, default `127.0.0.1:5900` (python/vnc_computer.py:76-79, typescript/vnc-computer.ts:105, 131).
- Accepts RFB 3.7 or newer and speaks at most 3.8 (python/vnc_computer.py:91-94, typescript/vnc-computer.ts:134-141).
- Requires security type 1 (None, no password), else fails (python/vnc_computer.py:95-99, typescript/vnc-computer.ts:142-148).
- ClientInit sends `1` = shared session, "so a person can watch the same desktop" (python/vnc_computer.py:102, typescript/vnc-computer.ts:152).
- Reads width and height from ServerInit; rejects screens over 1920 wide or 1200 tall (python/vnc_computer.py:48, 83-87, 103; typescript/vnc-computer.ts:42-43, 153-161).
- SetPixelFormat: 32 bits per pixel, depth 24, little-endian, true colour, max 255 per channel, shifts red 0 / green 8 / blue 16, so pixels arrive as R, G, B, X (python/vnc_computer.py:107-109, typescript/vnc-computer.ts:45-47, 162).
- SetEncodings: Raw only (python/vnc_computer.py:110, typescript/vnc-computer.ts:163).
- Timeout: 10 seconds. Python sets it on the socket (python/vnc_computer.py:78-79); TypeScript applies it per read (typescript/vnc-computer.ts:44, 169-178).

### Each method and what it sends over VNC
| Tool | What it sends | Cite |
| --- | --- | --- |
| `screenshot` | Sleeps 0.5 s, sends FramebufferUpdateRequest (type 3, incremental 0, whole screen), skips Bell (type 2) and ServerCutText (type 3) messages, reads Raw rectangles into a full frame, encodes PNG, returns base64 | python/vnc_computer.py:150-173; typescript/vnc-computer.ts:223-259 |
| `mouse_move` | One PointerEvent (type 5, button mask 0, x, y) | python/vnc_computer.py:125-130, 176-178; typescript/vnc-computer.ts:186-193, 289-292 |
| `left_click` | Move, modifiers down, PointerEvent mask 1 then mask 0, 10 ms sleep, modifiers up in reverse | python/vnc_computer.py:137-147, 181-182; typescript/vnc-computer.ts:206-221, 261-266 |
| `right_click` | Same with mask 4 | python/vnc_computer.py:59, 185-186; typescript/vnc-computer.ts:268-273 |
| `double_click` | Left press and release 2 times, 10 ms apart | python/vnc_computer.py:189-190; typescript/vnc-computer.ts:275-280 |
| `triple_click` | Left press and release 3 times | python/vnc_computer.py:193-194; typescript/vnc-computer.ts:282-287 |
| `scroll` | Press and release of a wheel button (up 8, down 16, left 32, right 64), `scroll_amount` times, at the coordinate, modifiers held | python/vnc_computer.py:60, 197-198; typescript/vnc-computer.ts:294-298 |
| `key` | Splits `text` on `+`; KeyEvent (type 4) down in order, up in reverse; repeated `repeat or 1` times | python/vnc_computer.py:132-135, 201-205; typescript/vnc-computer.ts:196-200, 300-307 |
| `type` | Per character: KeyEvent down then up, 12 ms sleep; `\n` becomes Return, `\t` becomes Tab | python/vnc_computer.py:208-213; typescript/vnc-computer.ts:309-320 |
| `wait` | Local sleep of `duration` seconds; nothing is sent | python/vnc_computer.py:216-217; typescript/vnc-computer.ts:322-324 |

- A click with no coordinate uses the last pointer position the driver set, starting at (0, 0), because VNC cannot report the pointer (python/vnc_computer.py:81-82, 139; typescript/vnc-computer.ts:102, 211; README.md:83).

### Coordinate scaling
- None. Model coordinates are used as screen pixels one to one, and the screenshot is sent at native size (README.md:88, python/vnc_computer.py:8, 47).
- A point outside `0 <= x < width, 0 <= y < height` raises `ToolError` "(x, y) is outside the WxH screen"; it is refused, not clamped (python/vnc_computer.py:126-128, typescript/vnc-computer.ts:187-190).
- The README says a larger screen "may need scaling to fit the model's image limits, and then the coordinates scaled back" (README.md:88). The exact image limits are NOT STATED.

### Screenshot format and size
- PNG, base64 string, returned as `BetaScreenshotResult(data=...)` / `{ data: ... }`. No media type, width or height is passed in the result (python/vnc_computer.py:171-173, typescript/vnc-computer.ts:256-258).
- Python writes RGB PNG via Pillow from RGBX (python/vnc_computer.py:172). TypeScript writes RGBA via pngjs with alpha forced to 255 (typescript/vnc-computer.ts:254-258).
- Pixel size is the whole screen as is, at most 1920x1200 (python/vnc_computer.py:48). The README's example server is 1280x800 (README.md:30).
- Wire cost: about 4 MB of raw pixels per screenshot at 1280x800 (README.md:90). Encoded PNG size is NOT STATED.
- The model sees it as a `tool_result` image block with a base64 source (python/exercise.py:43-45, typescript/exercise.ts:78-82).

### Key mapping
- Names are case-insensitive and map to X11 keysyms: `return`/`enter` 0xFF0D, `tab` 0xFF09, `escape` 0xFF1B, `backspace` 0xFF08, `delete` 0xFFFF, `insert` 0xFF63, `home` 0xFF50, `end` 0xFF57, `page_up` 0xFF55, `page_down` 0xFF56, `space` 0x20, `left` 0xFF51, `up` 0xFF52, `right` 0xFF53, `down` 0xFF54, `shift` 0xFFE1, `ctrl`/`control` 0xFFE3, `alt` 0xFFE9, `super`/`cmd`/`win` 0xFFEB (python/vnc_computer.py:51-57, typescript/vnc-computer.ts:50-74).
- `f1` to `f12`: 0xFFBE to 0xFFC9 (python/vnc_computer.py:56, typescript/vnc-computer.ts:79-80).
- A single character is its own keysym up to 0xFF; beyond Latin-1 it is `0x01000000 | codepoint` (python/vnc_computer.py:65-66, typescript/vnc-computer.ts:86-88).
- Anything else raises `ToolError` "unknown key ...; use a single character or a name such as Return, Page_Up or F5" (python/vnc_computer.py:67-68, typescript/vnc-computer.ts:81-85).
- Chords use `+`, e.g. `ctrl+s` (README.md:81). Consequence: a literal `+` cannot be a chord member. That is a reading of the split at python/vnc_computer.py:202, not something the files state.
- Known gap: `shift+a` types `a` (README.md:92).

## 4. What exercise.py / exercise.ts test

No API key and no model (README.md:68). They build the driver with a `confirm` that approves everything (python/exercise.py:83-88, typescript/exercise.ts:73-74) and send hand-built `tool_use` blocks through `tool_result` / `toolResult`. Eight checks, in order:

1. `screenshot` returns an image that is a PNG (8-byte signature) whose IHDR size equals the screen size (python/exercise.py:70-75, 93-94; typescript/exercise.ts:77-84).
2. `left_click` at the screen center is answered (python/exercise.py:95-98, typescript/exercise.ts:85-88).
3. `type` with `hello` is answered (python/exercise.py:99, typescript/exercise.ts:89).
4. `key` with `Return` is answered (python/exercise.py:100, typescript/exercise.ts:90).
5. `wait` with duration 1 is answered (python/exercise.py:101, typescript/exercise.ts:91).
6. A second `screenshot` differs from the first, retried up to 5 times with 1 s waits because `x11vnc` lags (python/exercise.py:102-113, typescript/exercise.ts:92-101).
7. `left_click` at `[width, height]`, one pixel off screen, is refused with `is_error` and text containing "outside" (python/exercise.py:114-119, typescript/exercise.ts:102-108).
8. `zoom` with `region [0, 0, 100, 100]` is refused with `is_error`, by the SDK, before the driver runs (python/exercise.py:120-122, typescript/exercise.ts:109-111).

Any mismatch fails an assertion and exits non-zero (README.md:77, python/exercise.py:15). Success prints "All calls came back as expected." (python/exercise.py:123, typescript/exercise.ts:116).

Not tested: the confirm-denied path, `right_click`, `double_click`, `triple_click`, `mouse_move`, `scroll`, chords, `repeat`, and the model loop.

Side effect to know: the exercise really clicks the center of the screen and types `hello` + Return into whatever has focus (python/exercise.py:95-100).

## 5. How to run it and what it needs

- `ANTHROPIC_API_KEY` for `run` only; `exercise` needs none (README.md:24, 68).
- An SDK version that has the helpers (README.md:25); versions in section 2.
- Python 3.10+ or Node 20+ (README.md:26).
- A passwordless VNC server, screen at most 1920x1200 (README.md:27). Suggested: TigerVNC, `apt install tigervnc-standalone-server`, then
  `Xvnc :1 -geometry 1280x800 -depth 24 -SecurityTypes None -localhost -rfbport 5900 &` and `DISPLAY=:1 xterm -geometry 160x50 &` (README.md:27-32).
- Alternative: `x11vnc -display :0 -nopw -localhost -forever` on an existing X display; it polls, so a screenshot can be stale (README.md:34).
- Install: `python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt` (README.md:37-39) or `npm install` (README.md:43-44).
- Run: `python run.py "<task>"` or `npm run start -- "<task>"` (README.md:50-51). Exercise: `python exercise.py` or `npm run exercise` (README.md:71-72).
- `run.ts` reads no options, so even `--help` goes to the model; `run.py` answers `--help` itself (README.md:54).
- Env vars: `VNC_HOST` (default `127.0.0.1`), `VNC_PORT` (default `5900`), `MODEL` (default `claude-sonnet-5-5`) (README.md:60-64).
- Docker: there is no Dockerfile or compose file in the quickstart. The only mention is to publish the port to loopback only from a container, `-p 127.0.0.1:5900:5900` (README.md:16). A container image to use is NOT STATED.
- macOS: NOT STATED. All server instructions are X11 / `apt` (README.md:27-34). Whether macOS Screen Sharing works is NOT STATED; the driver would refuse any server that requires a password (python/vnc_computer.py:95-98).
- Cost: `run` makes paid API calls; `exercise` makes none (README.md:68).

## 6. What a custom driver for local macOS Chrome over CDP would have to implement

Judging only from this interface. The CDP method names below are my suggestions and are NOT from these sources; treat them as unverified.

Required by the interface:
1. A subclass of `BetaAbstractComputerToolset20260801` that passes SDK options (`confirm`, `configs`) to `super()` (python/vnc_computer.py:72-77).
2. A connection opened at construction (Python) or in an async factory (TypeScript), and a `close()` that calls `super.close()` first (python/vnc_computer.py:119-123, typescript/vnc-computer.ts:104-127). The caller owns closing; the runner never does (typescript/run.ts:51).
3. `screenshot` returning `BetaScreenshotResult(data=<base64 PNG>)` (python/vnc_computer.py:173). Suggested CDP: `Page.captureScreenshot`.
4. One override per tool you want offered. Minimum useful set, mirroring the example: `left_click`, `right_click`, `double_click`, `triple_click`, `mouse_move`, `scroll`, `key`, `type` (`type_` in TypeScript), `wait`. Suggested CDP: `Input.dispatchMouseEvent` (moved / pressed / released / wheel), `Input.dispatchKeyEvent`, `Input.insertText`.
5. Optional, and each one you add becomes a tool the model is offered: `zoom`, `left_click_drag`, `left_mouse_down`, `left_mouse_up`, `middle_click`, `hold_key`, `cursor_position` (README.md:87). Their input and return shapes are NOT STATED here beyond `zoom`'s `region` (python/exercise.py:121).
6. `ToolError` for model mistakes such as off-screen points and unknown keys (python/vnc_computer.py:68, 128).

Behavior the driver must own, because the example shows the SDK does not do it:
- **One coordinate space.** The pixel size of the screenshot must equal the space clicks are sent in, since the example does no scaling (README.md:88). On a Retina Mac a page screenshot can be twice the CSS-pixel size that input events use, so the driver must capture at scale 1 or divide coordinates. (The Retina detail is my inference, NOT STATED in the sources.)
- **Size cap.** Keep the image at or under 1920x1200, or scale down and scale coordinates back (python/vnc_computer.py:47-48, README.md:88).
- **Bounds checks**, refusing rather than clamping (python/vnc_computer.py:126-128).
- **Pointer memory** for clicks with no coordinate (python/vnc_computer.py:81-82, 139).
- **Modifier chords in a click's `text`**, held for the click (python/vnc_computer.py:141-147).
- **Key-name translation.** The model sends X11-style names (`Return`, `Page_Up`, `ctrl+s`, `cmd`, `super`, `F5`) (python/vnc_computer.py:51-57). A CDP driver must map these to its own key codes, and decide what `super`/`cmd`/`win` mean on a Mac.
- **Settling.** The example sleeps 0.5 s before each screenshot, 10 ms between clicks and 12 ms between typed keys because VNC gives no "done" signal (python/vnc_computer.py:146, 153, 213). A CDP driver could wait on real page events instead (my inference).
- **Timeouts and reconnect.** The example fails after 10 s and never recovers (README.md:94).
- **A bound on `wait`**, which the example lacks (README.md:93).

Gaps for a browser, visible from this interface alone:
- The tool list has no navigate, tab, or URL tool (README.md:81, 87). A driver that screenshots only the page viewport gives the model no address bar to click. How a browser gets to a URL through this toolset is NOT STATED. A separate browser toolset may cover it, but these files do not mention one.
- Which tab or window the driver targets, and what happens on popups or new tabs, is the driver's problem; the interface has one screen (python/vnc_computer.py:72-73).
- Whether several driver instances can run side by side in one process is NOT STATED. Each example instance owns one socket to one desktop (python/vnc_computer.py:79).

Useful for us: `exercise` shows a driver can be tested with no API key by calling `tool_result` / `toolResult` directly with hand-built `tool_use` blocks (python/exercise.py:39-40, typescript/exercise.ts:38-44).

## 7. Safety: what the code does and does not do

Does:
- **Per-action confirmation in `run`.** Every call except `screenshot` prints `Allow <member> <json>? [y/N]` and runs only on `y`; anything else, including Enter, is no (python/run.py:33-38, typescript/run.ts:39-49). It uses the toolset's `confirm` option, whose context carries `member` and `input` (README.md:58).
- **Invisible characters are escaped in the prompt**, so hidden text in a call shows (python/run.py:37, typescript/run.ts:42-46).
- **Screenshots run unasked**, reasoned as changing nothing on the desktop (python/run.py:35, typescript/run.ts:40-41).
- **Off-screen coordinates are refused** (python/vnc_computer.py:126-128).
- **Unimplemented tools are refused by the SDK** (python/exercise.py:120-122).
- **Screen size cap** at 1920x1200 on connect (python/vnc_computer.py:84-87).
- **Loopback guidance**: default host `127.0.0.1`; README says to use `-localhost` and loopback-only port publishing because the server has no password (README.md:16).
- **Shared session**, so a person can watch (python/vnc_computer.py:102).
- **Written warning**: screen content steers the model and a focused terminal runs whatever it types; use a throwaway desktop in a sandbox, not your own (README.md:13-14). It points to "Running a computer toolset safely" in the SDK guides (README.md:18). That guide's content was not among the files read.

Does not:
- **No allow list or deny list** of apps, URLs, domains, keys or commands. None appears in any file.
- **No confirmation in `exercise`**; it approves everything (python/exercise.py:83-87, typescript/exercise.ts:73-74).
- **No prompt-injection defense** beyond the warning; screenshots go straight to the model.
- **No VNC authentication or encryption**; the driver requires a passwordless server (python/vnc_computer.py:95-98, README.md:89).
- **No bound on `wait`** (README.md:93), and no step, time or spend cap on the loop (python/run.py:57-64).
- **No sandbox of its own**; isolation is left to you (README.md:14).
- **No logging or audit trail** beyond printing messages to stdout (python/run.py:64, typescript/run.ts:60).
- **No redaction** of screenshots or clipboard. Clipboard messages from the server are skipped, not read (python/vnc_computer.py:157-158).
- **No system prompt** restricting the model (python/run.py:57-62).
- What the model sees when a person answers `N` is NOT STATED in these files.
