# Notes: "Browser and computer use with the SDK toolsets" (docs page)

Source: /tmp/browser-sdk/browser-use-sdk.md (1,276 lines, 74,362 bytes; measured with `wc -l -c`). All 1,276 lines read.
Page URL: https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-sdk (L3).
Cites are line numbers in that file. "NOT STATED" means this page does not say it; several such items are pushed to linked pages that were not part of this brief.

## 0. Corrections to the framing in the brief

- The page does NOT describe ready-made drivers shipped in the SDK. "The SDK doesn't include a browser, a desktop, a ready-made driver, or a URL policy." (L11; repeated for the computer class at L836.)
- "Driver" on this page means YOUR subclass of the SDK's abstract toolset class (L42, L836). Browser Use, Browserbase, Daytona, and E2B appear only as "Partner integrations" that "publish their own integrations with the SDK toolsets" (L17-19), with outbound links and no configuration detail (L21-38).
- The page never uses the strings `computer_toolset_20260801`, `computer_20251124`, or any `type` string for the `tools` entry, and never names a beta header.

## 1. Names, type strings, beta headers

- Two SDK classes, both beta (L14):
  - Browser: `BetaAbstractBrowserToolset20260801` (L42, L52, L161). Backs the "browser use tool" (L7).
  - Computer: `BetaAbstractComputerToolset20260801` (L836, L855, L928). Backs the "computer use tool" (L7).
  - Python async variants: `BetaAsyncAbstractBrowserToolset20260801`, `BetaAsyncAbstractComputerToolset20260801` (L1247).
- `toolset_name` values carried on each call: `browser` or `computer` (L1180). Read from the instance as `browser.toolset_name` (Python, L425) or `browser.toolsetName` (TypeScript, L469).
- Wire `type` strings for the tools entry: NOT STATED. Only the `20260801` suffix in the class names is visible.
- Beta headers: NOT STATED. Examples call `client.beta.messages.tool_runner` / `client.beta.messages.create` with no `betas` argument (L141, L415, L248, L460).
- `computer_toolset_20260801` versus `computer_20251124`: NOT STATED (neither string appears).

## 2. Model support

- Every example uses `model="claude-opus-5-5"` (L142, L249, L416, L461, L914, L1000, L1191, L1214).
- A supported-model list: NOT STATED.
- Claude Haiku 5.5, Sonnet 5.5, Fable 5.1: NOT STATED (never mentioned). Opus 5.5 appears only as the example model ID.
- Only model-related limit: "The API rejects an image over the model's limits" (L1083, L1256).

## 3. SDK entry points and versions

- Minimum SDK versions (Python or TypeScript): NOT STATED. Install commands: NOT STATED.
- Python imports:
  - `from anthropic import Anthropic` (L49)
  - `from anthropic.tools import ToolError` (L50)
  - `from anthropic.tools.browser import BetaAbstractBrowserToolset20260801, BetaBrowserNavigateResult, BetaBrowserState, BetaScreenshotResult, BetaToolsetCallContext, BetaURLContext` (L51-58); also `BetaLocalFilePolicy` (L651), `BetaConfirmContext` (L709), `BetaNavigationRefused`, `BetaDialogDismissed` (L367).
  - `from anthropic.tools.computer import BetaAbstractComputerToolset20260801, BetaComputerCursorPositionResult, BetaScreenshotResult, BetaToolsetCallContext` (L854-859); also `BetaComputerConfirmContext` (L1121).
  - Input types from `anthropic.types.beta` (L59-64, L343, L860-866, L1016).
- TypeScript imports:
  - `@anthropic-ai/sdk` (L159)
  - `@anthropic-ai/sdk/helpers/beta/toolsets` for both abstract classes, result/context types, `ToolError` (L160-168, L927-933)
  - `@anthropic-ai/sdk/helpers/beta/toolsets/node` for `BetaNodeFilePolicy` (L668)
  - `@anthropic-ai/sdk/resources/beta` for input types and `BetaBrowserMemberName` / `BetaBrowserMemberInput` / `BetaComputerMemberName` / `BetaComputerMemberInput` (L169-173, L321-324, L844)
- Run entry points: tool runner `client.beta.messages.tool_runner(...)` (Python, L141) / `client.beta.messages.toolRunner(...)` (TypeScript, L248), or a hand-written loop over `client.beta.messages.create` (L415, L460). "Each class runs with the tool runner or in a loop you write." (L14)
- Per-SDK guides linked: `browser-toolset.md` and `computer-toolset.md` in anthropic-sdk-python and anthropic-sdk-typescript (L14, L1247).
- Reference example: "minimal CDP example" at github.com/anthropics/claude-quickstarts/tree/main/browser-toolset, Python and TypeScript, controls Chromium over CDP, "isn't production code" (L11).

## 4. Driver interface

General rules
- Subclass the abstract class and write one method per member tool (L7, L343). Each method receives `(context: BetaToolsetCallContext, input: <typed input>)` (L343).
- Nothing is mandatory except the browser state report. "A member you don't implement is sent to the API as disabled. If Claude calls it anyway, the SDK returns an error, and the run continues." (L263)
- TypeScript: write members as methods, not arrow-function fields, because the SDK finds them on the prototype; the `type` member is spelled `type_` (L345, L972-973, L1018).
- Pass the driver instance itself as the `tools` entry (L263); in a hand-written TypeScript loop, `browser.toJSON()` (L403, L463).
- `close()`: override, call `super().close()` first "so no call is still using the browser when it closes" (L109-112, L221-224). "The runner never closes the toolset, so one instance can serve several runs. Close it when you're done." (L263). Python supports `with` (L140).
- Per-member input field lists: NOT STATED here; deferred to the browser-use-tool "Member tools" page (L343) and the computer-use-tool pages (L841, L849).

Browser class: required state report
- `_browser_state(self, context) -> BetaBrowserState` in Python (L72); in TypeScript a `browserState` constructor option (L183-191, L1243). "the state report that every driver needs" (L42).
- Returns `tabs` (each `tab_id`, `title`, `url`, `active`) and `state_changes` (L73-84, L184-190).
- Called "after each call that returns a result, including refused and failed calls" (L361).
- `state_changes` holds opened tabs, download events, `BetaNavigationRefused` per navigation your request hook blocked, `BetaDialogDismissed(kind, message)` per native dialog dismissed (L363-367). TypeScript shapes: `{ type: "navigation_refused" }`, `{ type: "dialog_dismissed", kind, message }` (L367). `download_failed` state change has an `error` field (L692).
- When any tab is open, exactly one must be active; every member taking `tab_id` must act on that tab (L371).
- If `_browser_state` raises anything, even `ToolError`, the SDK raises `ToolsetUsageError` and the run stops (L383).

Browser members named on this page and their returns (table L351-357)
| Member | Args shown | Return | Claude reads |
|---|---|---|---|
| `navigate` | `input.url` ("back", "forward", "reload", or a URL as Claude wrote it), `input.tab_id` (L89-92) | `BetaBrowserNavigateResult(url, status, title)` (L93-95) | `Navigated to {url} — {title} (HTTP {status})` (L354) |
| `screenshot` | `input.tab_id` (L100) | `BetaScreenshotResult(data=<base64>, media_type="image/png")`; TS `{ data, mediaType }` (L101, L210) | One image block (L353) |
| `zoom` | NOT STATED | `BetaScreenshotResult` | One image block (L353) |
| `left_click` | `input.target`, `input.tab_id` (L107) | None, or one line of text | `Clicked.` then the line (L106, L357) |
| `new_tab`, `switch_tab` | NOT STATED | A tab entry | The `browser_state` block alone (L355) |
| `list_tabs` | NOT STATED | List of tab entries | `browser_state` block alone (L355) |
| `close_tab` | NOT STATED | Nothing | `browser_state` block alone (L355) |
| `read_page`, `get_page_text`, `find`, `read_console`, `read_network`, `javascript_exec` | NOT STATED | A string | The string, or `(empty)` (L356) |
| `type` (`type_` in TS), `file_upload`, every other member | NOT STATED | Nothing, or one line of text | Short confirmation, then the line in its own text block (L357) |
- Full browser member list: NOT STATED on this page.
- A successful result ends with a `browser_state` block; an error result carries none (L349).

Computer class
- No state report, no URL policy, no file policy (L840).
- "17 tools" total; list lives on the computer-use-tool page (L849, L1266). Names that appear here: `screenshot`, `cursor_position`, `left_click`, `type`, `key`, `hold_key`, `zoom`, `wait`, `right_click`, `middle_click`, `double_click`, `triple_click`, `left_click_drag`, `left_mouse_down`, `left_mouse_up` (L1016, L1123-1133, L1176); a scroll tool is implied by `scroll_amount` (L1081, L1089) but not named.
- Example signatures (L874-900): `screenshot(context, BetaComputerScreenshotInput) -> BetaScreenshotResult`; `cursor_position(context, BetaComputerCursorPositionInput) -> BetaComputerCursorPositionResult(x, y)`; `left_click(context, BetaComputerLeftClickInput) -> None` with `input.coordinate` = `[x, y]` or None (click at cursor) and `input.text` = modifier to hold such as "shift"; `type(context, BetaComputerTypeInput)` with `input.text`; `key(context, BetaComputerKeyInput)` with `input.text`, `input.repeat`.
- Four tools take no input fields: `screenshot`, `cursor_position`, `left_mouse_down`, `left_mouse_up` (L1016).
- Returns (L1093-1097): `screenshot`/`zoom` -> one image block; `cursor_position` -> `X={x},Y={y}`; everything else -> short confirmation plus optional line.

Optional `execute` override (both classes)
- Signature `execute(context, name, input)`; call the parent's `execute` (L300, L310-312, L327-333). Code before runs after URL policy, file policy, and `confirm`, and may change the input, which the SDK does not re-check; code after may change the result (L300).
- Side effect: SDK then counts every member as implemented, so Claude is offered every default-on member; turn unserved ones off with `configs` (L302). For the computer class it counts as implementing `type`, `key`, `hold_key` (L842).
- `context.tool_use.id` (Python) / `ctx.toolUse?.id` (TS) gives the call ID (L314, L334).

Constructor options (L1236-1245; fixed after construction, L1247)
| Python | TypeScript | Sets | Class |
|---|---|---|---|
| `configs` | `configs` | Which members are enabled | both |
| `confirm` | `confirm` | Callable approving/refusing each call | both |
| `url_policy` | `urlPolicy` | Called before each `navigate` to a URL | browser only |
| `file_policy` | `filePolicy` | Upload roots, download path exposure | browser only |
| `tool_configs` | `toolConfigs` | Fields for the `tools` entry, e.g. `cache_control` | both |
| `_browser_state` method | `browserState` | State report | browser only |

## 5. Supported drivers and configuration

- Shipped drivers: none (L11, L836).
- Partner integrations, links only, no configuration on this page (L19-38):
  - Browser Use: docs.browser-use.com/open-source/customize/integrations/toolsets-for-claude; quickstart in browser-use/browser-use `examples/integrations/toolsets-for-claude` (L23-24)
  - Browserbase: Stagehand docs `claude-cua-toolset-quickstart`; repo browserbase/claude-cua-toolset (L28-29)
  - Daytona: guide `claude-draws-daytona-sandbox` (L33)
  - E2B: docs.e2b.dev/agents/claude-toolsets; cookbook example `anthropic-computer-use-orangehrm-js` (L37-38)
- How each partner is configured (keys, endpoints, packages): NOT STATED.
- Backends the page suggests for your own driver: a wrapper around "a browser automation library, such as Playwright" (L42); request hook via Playwright `context.route("**/*", ...)` (L616, L627); desktop via "a VNC client or `xdotool`" (L849); Chromium over CDP in the quickstart repo (L11).

## 6. How the loop runs

- Who executes: your driver methods, in the process that runs the SDK. "The SDK routes each call, runs the policies you pass, asks your approval callback, and builds each `tool_result`." (L7). Tool runner and `tool_result`/`toolResult` both run the toolset in the calling code's process (L816).
- Order of checks before a call: URL policy, file policy, `confirm`, then any pre-`execute` code, then the member (L300, L397). Disabled members are refused before your code runs (L296).
- Screenshots: the driver returns base64 image data plus media type; Claude gets one image block (L100-101, L353). "The SDK never reads or resizes an image." (L1083)
- Results: built by the SDK from the member's return value; browser successes end with the `browser_state` block (L349).
- Ordering: "Calls on one toolset run one at a time: You can't turn this off." (L1253, L398). A failed call stops that toolset's later calls in the same turn (L398); skipped calls are answered with `is_error`, the `toolset_name`, and exact text (L498):
  - Browser: `Not executed: an earlier action in this turn failed.` (L409)
  - Computer: `Not executed: an earlier computer action in this turn failed.` (L843)
  - With both toolsets, only later calls to the SAME toolset are skipped (L1180).
- Early start: `stream=True` + `run_tools_eagerly=True` (TS `stream: true`, `runToolsEagerly: true`) lets a call start while the response streams (L393). Checks still run first, including `confirm` mid-stream (L397). A started call cannot be undone if the response is cut off (e.g. `max_tokens`) or the loop stops; Claude never reads its result (L399). Default without it: calls run after the response ends (L391).
- Stop conditions: in the hand-written loop, stop when the response has no tool calls for this toolset, or at `MAX_TURNS = 10` (example constant, L410, L427-428, L452, L471). Tool-runner stop conditions and a max-steps setting: NOT STATED (deferred to the tool-runner page, L1269-1270).
- `pause_turn`: NOT STATED.
- Errors (table L377-381):
  - `ToolError` -> Claude reads its message as an error result; run continues.
  - `ToolsetUsageError` -> Claude reads nothing; run stops. Raised for configuration errors, SDK misuse during a call, a call after `close`, or any exception from the state report; not caught by the tool runner (L383).
  - Any other exception -> `ClassName: message` (Python) or `Error: message` (TS) as an error result; run continues.
  - Refused by `confirm`: error result, run continues; text `The user did not grant permission to run 'type'. Do not retry it unless the user asks you to.` (L1174)
  - An oversized image is rejected by the API, "which ends the run" (L1083).
- Both toolsets in one request: pass both instances in `tools`; runner routes by `toolset_name` (L1180).

## 7. Browser toolset versus computer toolset

| Topic | Browser | Computer |
|---|---|---|
| Targeting | `left_click` takes `input.target` (L107); page-reading members `read_page`, `get_page_text`, `find` return strings (L356) | Pixel coordinates in the screenshots you return (L877, L1022) |
| Tabs | `new_tab`, `switch_tab`, `list_tabs`, `close_tab`; `tab_id` on members; one active tab (L355, L371) | None |
| Navigation | `navigate` with URL or "back"/"forward"/"reload" (L89) | None |
| State report | Required after every call (L361) | None (L840) |
| URL policy | `url_policy` option (L527) | None (L840) |
| Downloads | Reported as state changes; path shown only if `expose_download_paths` and inside download dir (L363, L684) | NOT STATED |
| File upload | `file_upload`, off by default, needs `confirm` and a file policy (L647, L697) | None (no file policy, L840) |
| JS / console / network | `javascript_exec` (off by default), `read_console`, `read_network` (L356, L697) | None |
| Default enablement | `javascript_exec`, `file_upload` off by default (L697); `read_console` shown being enabled (L284) | Every implemented tool on by default (L841) |
| `confirm` requirement | Required if `javascript_exec` or `file_upload` enabled (L697) | Required if `type`, `key`, or `hold_key` implemented and not disabled (L842, L1104) |
| `confirm` context | `context.member`, `context.input`, `context.tab_url` / `ctx.tabURL` (L723-727, L766-769) | Tool and input only, not the screen (L1110, L1255) |
| Coordinate scaling | NOT STATED | Driver converts both ways; keep screenshot size fixed with the display's aspect ratio (L1024, L1081) |

- The words "DOM" and "accessibility tree" do not appear; what `target` is and what `read_page` returns: NOT STATED here (deferred to the browser-use-tool page, L343).

## 8. Authentication, cookies, logged-in sessions, attaching to a browser

- Guidance is to avoid signed-in profiles: "Use a browser profile that isn't signed in to any account whose data or actions you wouldn't hand to Claude." (L271, L813). "Keep credentials out of the environment, and start from a fresh browser profile." (L809)
- `javascript_exec` "runs with the page's own authority: its cookies, its storage, and its signed-in sessions." (L813)
- URLs reach Claude as written, so "a user name or password in a URL" reaches Claude (L373).
- Attaching to an existing browser: mentioned only as a category, "one you reach at a DevTools URL" under remote browsers (L822), and CDP in the quickstart repo (L11). How to pass a CDP endpoint, reuse a persistent profile, or import cookies: NOT STATED.
- A DevTools port on loopback is reachable by pages inside the same container and "shows a list of the browser's open tabs and the address that controls each one" (L643).
- Hosted-browser secrets: keep the provider API key and the session connection URL (which can contain a key) out of logs, tool results, and error text; provider session recordings are another copy of everything Claude saw and typed (L832).

## 9. Safety guidance

- Threat: "A page, or text injected into one, can try to reach internal services or pull files off the host. It can also try to trigger actions with real effects." (L502). Treat page text, screenshots, console and network entries, tab titles, download names as untrusted (L818); for desktop, window titles and clipboard text too (L1113).
- Six browser steps (L504-509): URL policy; intercept requests in the driver; egress policy on the container; confine uploads/downloads; gate with `confirm`; isolate the host per session. SDK enforces 1, 4, 5; the rest is yours (L511).
- URL policy (domain allow list): a function `url_policy(context: BetaURLContext, url) -> None`; raise `ToolError` to refuse (L527-529). Without one "the SDK checks no URL, and the API doesn't filter the URLs Claude opens" (L520). Called only for `navigate` to a URL, not back/forward/reload (L593), and not for clicks, redirects, form posts, or subresources (L597, L607, L1251). `url_policy=None` / `urlPolicy: null` refuses every navigate; TS `undefined` means unset (L603). SDK does not check schemes; driver must refuse `javascript:`, `view-source:`, `data:`, `file:` (L522-524). The example policy is explicitly not production grade (L595).
- Request interception: check each request in the automation library's hook with the same function (L609). It misses WebSocket handshakes, service-worker requests, and redirect hops; block service workers (L633).
- Egress: block link-local and private ranges incl. `169.254.169.254`, allow only needed hosts, DNS only to the container resolver (L639-641). Rules outside the container cannot see loopback (L270, L643).
- Human confirmation: `confirm(context) -> bool`, called before every call when supplied; with none, nothing is asked (L697-699). Escape non-printable-ASCII in the URL and input before showing a person (L699). TS `confirm: null` refuses every call (L697). Approvals are based on the last state report and the page can change (L797, L1252). Purchases, sent messages, accepted terms are ordinary `left_click`/`type` calls, so gate those members too if needed (L797, L1110). To fail closed on desktop, approve only `screenshot`, `zoom`, `cursor_position`, `wait` (L1176).
- `javascript_exec`: do not enable without egress limits (L799). A `javascript:` URL in `navigate` runs script even with `javascript_exec` off (L524, L801).
- Files: with no file policy every upload naming a path or document ID is refused (L647). `BetaLocalFilePolicy(upload_roots, download_dir, expose_download_paths)` / `BetaNodeFilePolicy({uploadRoots, downloadDir, exposeDownloadPaths})` (L659-663, L675-679); resolves symlinks, refuses paths outside roots (L684). Download dir mode `0700`, mounted `noexec,nosuid,nodev`, out of reach of other tools; do not read or run a download until a person decides (L690-693).
- Sandboxing: dedicated minimal-privilege container or VM per session, non-root, read-only root filesystem, no host mounts beyond upload/download dirs, no shared filesystem with other tools (L805-810). Run the API-calling code outside the browser container because it holds the API key and conversation (L816).
- Remote/hosted browsers: URL policy, interception, and `confirm` still run in your process (L822); provider controls egress, so the request hook is your only network check (L824); shipped file policy does not protect a remote browser, keep `file_upload` off and have it refuse downloads (L826-830). "The SDK can't detect that a browser is remote." (L828)
- Desktop five steps (L1109-1113): isolate; gate with `confirm`; keep terminals, run dialogs, launchers off the desktop; refuse out-of-range input (point outside screenshot, multi-minute `wait`, huge `repeat`/`scroll_amount`) rather than clamping; treat the screen as untrusted. SDK does not limit `duration`, `repeat`, `scroll_amount` (L1089).
- Error text can leak local paths; the SDK does not hide them (L385, L387, L845).
- Prompt-injection classifiers: "don't currently run on browser toolset requests sent through Amazon Bedrock" (L514).

## 10. Pricing and token overhead

- Pricing, per-screenshot or per-step tokens, tool-definition overhead: NOT STATED.
- Related facts only: `tool_configs` can carry `cache_control` (L1242); a long run can put more than 20 images in one request, and the API then applies a stricter per-image limit (L1083); URLs are cut at 4,096 characters (L373) and computer tool text at 4,096 characters (L845); example screenshot size 1280x720 for a 2560x1440 display (L1030-1031).

## 11. Platform availability

- Claude API: implied by the `Anthropic()` client in every example (L139, L245); no explicit availability statement.
- Amazon Bedrock: implied usable, since the page notes the prompt-injection classifiers do not run on browser toolset requests sent through Bedrock (L514).
- Vertex AI, Microsoft Foundry: NOT STATED.
- Languages: Python and TypeScript only (L7, L14); code groups exclude cURL, CLI, C#, Go, Java, PHP, Ruby (L44).

## 12. Limits and known issues

- Both classes are beta (L14).
- Limitations section (L1251-1256): URL policy sees only `navigate`; approval is based on the last state report; calls on one toolset are serial and that cannot be turned off; SDK does not check tab ID uniqueness or tab count and does not always check one tab is active (the API rejects a bad report); computer `confirm` sees tool and input, not the screen; SDK does not resize computer images.
- Options cannot change after construction (L1247).
- Enabling a member the class does not implement is a configuration error unless `execute` is overridden (L296).
- File policy's overlap check between download dir and upload roots "can miss a symlink" (L684).
- The quickstart CDP example "isn't production code" (L11).

## 13. Code examples, one line each

1. L45-260 Quick start (Py/TS): minimal browser driver (`navigate`, `screenshot`, `left_click`, state report, `close`) with an example host allow-list URL policy, run through the tool runner with early start.
2. L281-293 Enable/disable members: `configs` turning `read_console` on and `navigate` off.
3. L305-338 `TracedBrowser`: `execute` override that times and logs each call and redacts `get_page_text` output.
4. L406-495 Run without the tool runner: hand-written loop with `MAX_TURNS = 10` that answers calls via `tool_result` and marks post-failure calls as not executed.
5. L534-590 URL policy: the quick start's `is_allowed` / `url_policy` shown standalone and passed to the constructor.
6. L612-630 Request interception: Playwright `context.route` hook that aborts requests failing the same `is_allowed`.
7. L650-681 File policy: enabling `file_upload` with `BetaLocalFilePolicy` / `BetaNodeFilePolicy` upload roots and download directory.
8. L704-792 `make_confirm`: asks a person for `javascript_exec` and `file_upload`, remembers approvals per (member, page, exact input), approves the rest.
9. L852-1009 Desktop driver `MyDesktop`: five computer tools (`screenshot`, `cursor_position`, `left_click`, `type`, `key`) with a `confirm` that asks before every call, run through the tool runner.
10. L1027-1078 Coordinate scaling: `to_display` / `to_screenshot` between a 1280x720 screenshot and a 2560x1440 display, refusing out-of-range points.
11. L1120-1171 Computer `confirm`: asks a person before keyboard tools, with a `CLICKS` set available to extend it.
12. L1183-1227 Both toolsets: browser and desktop instances passed together in `tools` with early start.

## 14. Pointers for the items this page defers

- Member tool list and input fields, `browser_state` limits, batch actions, upload document IDs, security considerations: browser-use-tool page (L278, L343, L371, L403, L511, L647).
- 17 computer tools, tool parameters, image size limits, screenshot history: computer-use-tool page (L841, L849, L1083).
- Loop mechanics of the runner: tool-runner page (L14, L1269-1270).
