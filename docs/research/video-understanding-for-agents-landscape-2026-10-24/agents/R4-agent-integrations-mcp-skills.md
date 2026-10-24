<!-- markdownlint-configure-file {
  "MD013": false
} -->

# R4: How video gets into coding and general agents (MCP servers, skills, CLIs, SDKs), as of 2026-10-24

Axis: the integration layer, meaning the MCP servers, Claude Code skills and plugins, other coding-agent CLIs, agent SDKs and browser agents that put video in front of an agent. For each one this file records the transcode it does (local frames plus ASR, or a relay to a cloud model), its egress behaviour, its adoption and its last commit.

This file extends `docs/research/video-understanding-human-parity-2026-10-23/agents/F3-tinycloud-and-agent-video-tools-now.md` (F3) and does not repeat it. F3 already covers claude-video, claude-eyes, claude-video-vision, video-understanding-skill, video-watch, HinkoK/watch-skill, the TwelveLabs plugin and Jockey, Tinycloud, VideoDB and Memories.ai. Here those rows are re-measured only where something changed or where a new egress fact turned up.

Labels: **MEASURED** = I ran the named command today (2026-10-24). **DOCUMENTED** = a vendor page, README or source file says it; not tested by us. **INFERRED** = my reasoning. Star counts and commit dates come from `gh api repos/<repo>` and `gh api repos/<repo>/commits?per_page=1`, wrapped in `/tmp/r4-scripts/meta2.sh` (MEASURED 2026-10-24). Scratch copies of READMEs are in `/tmp/r4-fetch/readmes/` and will not survive a reboot; the URL is the citation of record. Nothing was installed, no account was created and no video was uploaded.

## 0. Baseline this axis builds on (not re-derived)

- Opus 5.5 has no video or audio input. Claude Code caps a Read image at 2000 px a side and holds about 600 media items before stripping the oldest (F1, MEASURED there).
- The local design that holds up is "index once, then navigate and zoom": contact sheets, a word-timed transcript, OCR with positions, crops, bursts and a cut list. Our own pipeline scored 23-24 of 24 on time-windowed probes (REPORT.md, MEASURED there).
- The egress trap F3 found is that `claude-video --engine auto` uploads to Gemini whenever a `GEMINI_API_KEY` resolves (F3 §4.2). This file widens that finding (§3).

## 1. Narrative

**There are three ways in, and only one keeps pixels on the machine.** Every integration found reaches the agent in one of three ways:

- **(a) Local transcode into stills plus text that Claude reads itself.** claude-video local engine, claude-real-video, claude-video-vision, mcp-video-analyzer, watch-skill, claude-eyes, videoctx, ffmpeg-skill.
- **(b) Relay to a cloud video model that writes the answer as text.** Gemini through claude-video's Gemini engine, Gemini CLI, watch-any-video, OpenRouter MCP; TwelveLabs Pegasus and Jockey; Memories.ai; VideoDB; Valossa; BibiGPT; Diffusion Studio credits.
- **(c) A browser agent taking screenshots of a playing page.** Playwright MCP, Chrome DevTools MCP, Claude in Chrome. This gives no audio and no deliberate frame choice.

Only (a) keeps the picture local, and only (a) lets Opus 5.5 see pixels itself rather than another model's description of them. Route (b) is the only one that gives *native* audio-visual perception, because Gemini hears the soundtrack. The price is that the whole file leaves the machine. (Taxonomy INFERRED from the per-entry evidence below.)

**What is new since F3 (2026-10-23):**

1. **claude-real-video ("crv") is a second large local skill and MCP that F3 missed.** It has 2,257 stars, first commit 2026-06-30, v0.10.7 on 2026-09-26, and a Claude Code marketplace entry (MEASURED). It is local by design, with scene-change selection plus dedup. Its paid closed add-on, **crv Pro ($29 one-time)**, claims per-shot camera-motion labels (static, pan, tilt, zoom, handheld) and burst frames on high-motion shots (DOCUMENTED, vendor). F3 said motion measurement "still has no packaged competitor". That needs a caveat now: a packaged *claim* exists, it is paid and closed-source, and nobody has evaluated it.
2. **Gemini CLI is the cheapest native-video sidecar a Claude agent can call.** Its `read_file` tool sends a video file of 20 MB or less inline as base64 `inlineData` to Gemini (DOCUMENTED, source `packages/core/src/utils/fileUtils.ts`, `case 'video'` branch, `MAX_FILE_SIZE_MB = 20`, main as of 2026-10-23). Claude Code can shell out to `gemini -p` with an `@clip.mp4` path. That is a native video-plus-audio relay with no MCP server at all. Two catches:
   - The CLI docs now list only "text, images, audio, and PDF". The docs lag the code.
   - "API-key-free" Gemini bridge MCPs that reuse Gemini CLI's Google-account OAuth are forbidden by Gemini CLI's own terms ("Directly accessing the services powering Gemini CLI ... using third-party software ... is a violation", `docs/resources/tos-privacy.md`, DOCUMENTED).
3. **Egress set off by environment variables is a pattern across several tools, not one bug.** See §3. The newest README of the most-installed skill (claude-video, 19,117 stars) recommends a *free* Google AI Studio key as the "fastest path". The Gemini API Unpaid Services terms say Google "uses the content you submit ... to provide, improve, and develop" its products and "human reviewers may read, annotate, and process your API input and output" (https://ai.google.dev/gemini-api/terms, last modified 2026-04-28, DOCUMENTED).
4. **Hosted "watch any video" connectors are now a consumer product.** watch-any-video (Wikivec Inc.) is a remote MCP for Claude and ChatGPT that relays to Gemini on the paid tier, at $8/month or $60/year for 20 hours (DOCUMENTED 2026-10-24). Valossa (a long-standing video-recognition vendor) ships a hosted MCP for its media library (DOCUMENTED). These remove all setup, at the cost of a full upload.
5. **Distribution channels say a lot.** These are MEASURED 2026-10-24:
   - The official Anthropic plugin marketplace (`anthropics/claude-plugins-official`, 315 plugins) has **no video-understanding plugin**. Its only video plugins generate video (HyperFrames, Runway).
   - In the official MCP registry, a search for "video" returns 117 distinct server names. By a description regex, about 47 generate or edit video, about 19 transcribe, and only about 17 claim understanding.
   - Smithery returns 147 hits for "video understanding". Almost all are hosted remotes, and the highest use count is BibiGPT at 389.
   - On skills.sh, the top watch-style skills are diffusionstudio `watch` (1,700 installs), oxbshw `watch` (570), claude-real-video (561 plus 498 for its agents variant) and mcp-video-analyzer `video` (220). Generation skills run to hundreds of thousands of installs. bradautomates/claude-video does not show up under that id on skills.sh because it ships through plugin marketplaces.
6. **Codex CLI and Cursor still have no video input.** Codex documents `--image` and pasted images only (https://learn.chatgpt.com/docs/codex/cli, DOCUMENTED). Cursor's current changelog page mentions "video" only for marketplace demo videos (MEASURED: curl plus grep of https://cursor.com/changelog). Both get video only through the same skills. claude-video, crv, mcp-video-analyzer and watch-skill all install into Codex.
7. **SDK level.** In the Claude Agent SDK, custom tools can return `image` blocks, which reach Claude as visual input. `audio` blocks are saved to disk and handed to Claude as a file path (TypeScript) or **dropped with a warning** (Python) (https://code.claude.com/docs/en/agent-sdk/custom-tools, DOCUMENTED). So an MCP server that "returns audio to Claude" gives Claude nothing it can hear. The OpenAI Agents SDK tool output takes `ToolOutputImage` and `ToolOutputFileContent`, with no video type (DOCUMENTED). Claude Code now also saves images returned by MCP tools to a file so that Read and Bash can reopen them (CHANGELOG.md line 1896, MEASURED by grep of the 2.1.310 changelog).

**Resolution trap shared by local servers.** Default frame widths are 512 px (claude-video-vision `frame_resolution`), 512 px (claude-video, per F3), 640 px (crv benchmark) and 800 px (mcp-video-analyzer `--max-width`). All of these are below what dense on-screen text needs. Our own ingest finding was 1080p or more for text (commit `11f8feeb2`). Only crv (`--frame-width 1600`), mcp-video-analyzer (`--max-width 0`) and claude-eyes (`crop --box` at full resolution) document an escape (DOCUMENTED). An agent builder should treat the default width as a cost setting, not a quality setting (INFERRED).

## 2. Comparison table (ranked by importance to an agent builder)

| # | Name | Route | Transcode | Egress by default | Adoption / last commit (MEASURED) | Label |
|---|---|---|---|---|---|---|
| 1 | bradautomates/claude-video `/watch` | Skill + plugin (Claude Code, Codex, 50+ hosts) | Local: yt-dlp, scene frames (cap 100), captions or WhisperX; or Gemini engine (whole video) | **Gemini upload if any `GEMINI_API_KEY` resolves; legacy 0.2.0 `auto` ASR goes to Groq, then OpenAI** | 19,117★; v0.3.2 2026-09-25 | DOCUMENTED |
| 2 | HUANGCHIHHUNGLeo/claude-real-video (crv) | Skill + plugin + MCP (5 tools) + CLI + local web UI | Local scene-change plus dedup frames, Whisper, optional diarization, contact sheets; Pro: camera-motion labels, audio emotion | None (local); Pro `--ai-report` uses your key | 2,257★; v0.10.7 2026-09-26; last commit 2026-10-08 | DOCUMENTED |
| 3 | Gemini CLI `read_file` / `@file` | Shell sidecar from Claude Code | Native: whole file inline (20 MB or less) to Gemini, video plus audio | **Whole file to Google**; terms follow the auth tier | 107,572★; v0.65.0 2026-10-20 | DOCUMENTED (source) |
| 4 | guimatheus92/mcp-video-analyzer | MCP (8 tools) + `/video` plugin + skill + CLI | Captions or sidecar `.vtt`, scene frames (800 px), Tesseract OCR, burst, Whisper fallback | **OpenAI Whisper API if `OPENAI_API_KEY` set and no local whisper; TwelveLabs Pegasus if `TWELVELABS_API_KEY` set** | 101★; v0.11.0 2026-10-13 | DOCUMENTED |
| 5 | jordanrendric/claude-video-vision | MCP (6 tools) + plugin | ffmpeg frames as base64 images to Claude; audio by backend | Config `backend: local` by default; the Gemini backend sends audio to Google | 1,410★; v1.4.0 2026-10-06 | DOCUMENTED |
| 6 | oxbshw/watch-skill (+ DeepWatch) | MCP (39 tools, stdio/HTTP) + skills (25+ hosts) + REST | Frames, OCR, transcripts with absolute timestamps; deterministic verification contracts | None; "holding a provider key does not permit media to leave the machine" | 518★; PyPI 1.4.3 2026-09-08 | DOCUMENTED |
| 7 | moritzkremb/claude-eyes | Skill + `eyes` CLI | Five-track local index; crop, burst, cuts | None | 60★; last commit 2026-10-16 (no change since F3) | DOCUMENTED |
| 8 | TwelveLabs: Claude Code plugin + Jockey connector | Plugin (MCP) / claude.ai connector | Server-side Pegasus/Marengo returns text and segments | **Upload to TwelveLabs** | Plugin 26★, feature commit 2026-05-14 (stale over 5 months); Jockey GA 2026-10-15 | DOCUMENTED |
| 9 | watch-any-video (Wikivec) | Hosted remote MCP | Gemini (paid tier) watches and answers with timestamps | **Upload to Google via vendor**; Q&A kept 7 days, breakdowns 30 days | MCP registry 0.1.0 2026-10-11 | DOCUMENTED |
| 10 | Memories.ai plugin | Plugin + hosted MCP (OAuth) | Server-side index, captions, VLM Q&A | **Upload / index on vendor** | Plugin repo 1★, last commit 2026-07-27 | DOCUMENTED |
| 11 | VideoDB skills / MCP | Skills + hosted MCP | Server-side `spoken_words`, `vlm`, `ocr` artifacts | **Upload; persistent storage by default** (Oct) | video-db/skills 139★, last commit 2026-09-11 | DOCUMENTED |
| 12 | Valossa Assistant MCP | Hosted remote MCP (OAuth) | Server-side detections (things seen, sounds), transcripts, clip export | **Upload to Valossa** | MCP registry 1.0.0 2026-06-25 | DOCUMENTED |
| 13 | sonpiaz/watch-cli | CLI + skill + MCP (npm pending) | Local yt-dlp + ffmpeg frames; ASR and audio Q&A on Kyma | **Audio to Kyma (aggregator) by default**; `WATCH_BROWSER=auto` reads browser cookies | 260★; v0.3.4 2026-09-04 | DOCUMENTED |
| 14 | dunfred/videoctx | MCP + CLI; open `.vctx` index | Local keyframes, PySceneDetect, faster-whisper, optional VLM captions; Claude answers from the text layer | Index local; `ask` calls the Anthropic API | 1★; 0.1.5 2026-10-22 | DOCUMENTED (self-benchmark) |
| 15 | kajisho5/ffmpeg-skill + media-analysis-skill | Skill + MCP | Local probe, scenes, contact sheet (`look.py`), `cropdetect --motion-centre`; deterministic Observation JSON | None ("No cloud · No API keys") | 2,159★, v2.12.0 2026-10-23; media-analysis 6★ | DOCUMENTED |
| 16 | Browser agents: Playwright MCP, Chrome DevTools MCP, Claude in Chrome | MCP / extension | Screenshots of the page; Playwright can *record* `.webm` but not read it | Whatever page the browser loads | Playwright MCP 38,563★ (v0.0.83 2026-09-28); CDT MCP 54,054★ (v1.12.0 2026-10-22) | DOCUMENTED + INFERRED |
| 17 | Claude Agent SDK / OpenAI Agents SDK patterns | SDK custom tools | Image blocks only; Claude SDK audio blocks saved to disk (TS) or dropped (Py) | n/a | Docs current 2026-10 | DOCUMENTED |
| 18 | Codex CLI, Cursor | Coding agents | Images only; video only through skills and MCP above | n/a | Codex 130,714★ rust-v0.164.0 2026-10-23 | DOCUMENTED |
| 19 | YouTube transcript / yt-dlp MCPs (kimtaeyoon83, jkawamoto, anaisbetts, kevinwatt) | MCP | Captions or subtitles only; no pixels | Fetches from YouTube only | 603★ / 492★ / 552★ / 293★; last commits 2026-07-21 / 10-21 / 08-16 / 08-11 | DOCUMENTED |
| 20 | stabgan/openrouter-mcp-multimodal `analyze_video` | MCP (21 tools) | Relays the video file to an OpenRouter model | **Video to OpenRouter**; default model is a `:free` variant | 101★; v5.1.3 2026-10-22 | DOCUMENTED + INFERRED |

## 3. Egress traps (silent or easy-to-miss uploads)

| Tool | What sets it off | What leaves the machine | Label | How to defuse |
|---|---|---|---|---|
| claude-video | `GEMINI_API_KEY` in env, `~/.config/watch/.env`, or **cwd `.env`** with `--engine auto` (the default) | Whole video to Google Files API (deleted after the answer, otherwise expires in 48 h); YouTube URLs go to Google directly | DOCUMENTED README.md:193-198 | `WATCH_ENGINE=local` |
| claude-video (users carried over from 0.2.0) | `auto` ASR fallback kept: "Groq key first, then OpenAI" | Extracted audio to Groq or OpenAI | DOCUMENTED README.md:211 | `--whisper whisperx` or `--no-whisper` |
| claude-video | README calls a *free* AI Studio key the "fastest path" | Under Unpaid Services terms, content may be used to improve Google products and read by human reviewers | DOCUMENTED (README.md:132; Gemini API terms 2026-04-28) | A paid-tier key, or local |
| mcp-video-analyzer | `OPENAI_API_KEY` in the MCP server env and no local `whisper` on PATH | Audio to the OpenAI Whisper API | DOCUMENTED README.md:369-377 | Install local whisper, or unset the key in the server's env block |
| mcp-video-analyzer | `TWELVELABS_API_KEY` set | Direct video URLs registered with TwelveLabs (the README says "no upload", but the URL is fetched server-side) | DOCUMENTED README.md:357-365 | Unset |
| watch-cli | Default backend | Audio to `kymaapi.com` (whisper-v3-turbo; audio Q&A on gemini-3-flash-audio) | DOCUMENTED | `GROQ_API_KEY` or `GOOGLE_AI_KEY` change the provider; there is no local ASR path |
| watch-cli | `WATCH_BROWSER=auto` | Reads cookies from your signed-in browser for yt-dlp (credential exposure, not upload) | DOCUMENTED | Leave unset |
| Gemini CLI as a sidecar | Any `@video.mp4` or `read_file` on a video | Whole file inline to Google; free Google-account login falls under Code Assist for individuals terms | DOCUMENTED (source + tos-privacy.md) | Vertex or paid key; trim the clip first |
| "Key-free" Gemini bridge MCPs (e.g. NotFabii/gemini-bridge-mcp) | Reuse Gemini CLI OAuth | Whole file; **also breaks Gemini CLI terms** | DOCUMENTED (Gemini CLI tos-privacy.md) | Do not use |
| openrouter-mcp-multimodal | `analyze_video` with the default model | Video to OpenRouter, then to a third-party provider; `:free` routes may be served by providers that log prompts | DOCUMENTED (default model) + INFERRED (logging) | Pin a model and provider with a no-logging policy |
| Hosted connectors (watch-any-video, Valossa, Memories.ai, VideoDB, Jockey, BibiGPT, Diffusion Studio "analyze") | Using them at all | Whole video | DOCUMENTED | Use only for public videos |
| Claude Code plugin auto-update | Plugin marketplaces can auto-update (crv says to enable it) | Not egress, but a new version can change engine defaults, as claude-video 0.3.0 did | INFERRED | Pin versions for private work |

Contrast: watch-skill makes "a cloud engine needs its own consent even with the network open" an explicit second switch. crv, claude-eyes, ffmpeg-skill and media-analysis-skill have no cloud path in their free core (DOCUMENTED). Of the local tools reviewed, these are the only ones whose design rules out leaks set off by environment variables (INFERRED).

## 4. Entries (detail)

### 1. claude-video (`/watch`), bradautomates
- **Gives an agent:** a `/watch <url|file> [question]` skill that returns timestamped frames plus transcript, or a Gemini-written answer.
- **Path:** local engine: yt-dlp, then ffmpeg scene-aware frames (cap 100 in `balanced`, 512 px default per F3), 16×16 dedup, captions, then WhisperX, Groq or OpenAI. Gemini engine: the whole video is uploaded to the Files API (24,000,000-byte chunk budget), the answer is relayed, and the file is deleted afterwards (otherwise it expires in 48 h). `--start/--end` clipping is supported (README.md:189-217, 286).
- **Surfaces:** it does not work in Claude Chat or Cowork, and Claude Code on the web runs it on a cloud host. WhisperX "in a cloud session ... does not keep audio on your device" (README.md:182-184, 217).
- **Evidence:** vendor only.
- **Maturity:** 19,117★, created 2026-04-24, last commit and release v0.3.2 on 2026-09-25 (MEASURED).
- URL: https://github.com/bradautomates/claude-video

### 2. claude-real-video (crv), HUANGCHIHHUNGLeo
- **Gives an agent:** `crv <url|file>` writes `frames/*.jpg`, `frames.json`, `transcript.txt/.json` and `MANIFEST.txt`. It also offers `--grid` contact sheets, `--from/--to` windowing, `--frame-width 1600` for small text, `--adaptive` for slow changes, `--text-anchors` (frames forced at subtitle cues) and `--speakers` (local 45 MB diarizer). A SQLite memory (`~/.crv/memory.db`) supports search across watched videos. The MCP server has five tools: `watch_video`, `get_frames`, `search_memory`, `list_watched` and `get_transcript`.
- **Self-measured numbers (DOCUMENTED, vendor):** 3-min 640×360 clip, M4: 170 of 180 frames kept, ~52k image tokens, 23.5 s. A dedup fix in v0.7.16 keeps 10 of 10 action frames of a subject covering under 1% of the frame, against 1 of 10 before.
- **Pro ($29 one-time, closed, sold on Capafy):** `--motion` per-shot camera labels, cuts per minute, 0.2 s bursts on high-motion shots; `--senses` voice emotion, audio events and music BPM. All claimed to run locally. Nobody independent has checked any of it.
- **Maturity:** 2,257★, PyPI 0.10.7 (2026-09-26), skills.sh 561 + 498 installs (MEASURED).
- URL: https://github.com/HUANGCHIHHUNGLeo/claude-real-video

### 3. Gemini CLI as a native-video sidecar, Google
- **Gives an agent:** a Claude agent can run `gemini -p "<question> @clip.mp4"` and get Gemini's native video-plus-audio answer as text.
- **Mechanism:** `detectFileType` classifies `video/*` by MIME with a content check. `case 'video'` base64-encodes the whole file into `inlineData`. Files over 20 MB are refused (`MAX_FILE_SIZE_MB = 20`) (DOCUMENTED, https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/utils/fileUtils.ts).
- **Practical limit:** 20 MB is roughly a few minutes of 1080p, so the agent has to trim or downscale with ffmpeg first (INFERRED).
- **Docs vs code:** the docs page lists only "text, images, audio, and PDF" for `read_file`.
- **Terms:** they depend on the login. Google-account login is Code Assist for individuals; a Gemini API key is unpaid or paid; Vertex is GCP terms (`docs/resources/tos-privacy.md`).
- **Maturity:** 107,572★, v0.65.0 2026-10-20 (MEASURED).

### 4. mcp-video-analyzer, guimatheus92
- **Tools:** 8 MCP tools: `analyze_video`, `analyze_videos`, `get_transcript`, `get_metadata`, `get_frames` (scene change or dense 1 fps), `analyze_moment`, `get_frame_at`, `get_frame_burst`.
- **Output:** JSON with transcript, OCR (Tesseract `eng+por`), timeline and frames (default 800 px wide; `--max-width 0` keeps native width).
- **Inputs:** Loom, YouTube and yt-dlp sites, direct URLs and local files. It uses sidecar `.vtt` files first and skips Whisper on silent tracks.
- **Safety:** SSRF guards block private and metadata addresses.
- **Install routes:** Claude Code `/video` plugin; `npx skills add` for Codex, Cursor and Gemini CLI.
- **Maturity:** 101★, v0.11.0 2026-10-13, last commit 2026-10-21 (Dependabot); skills.sh 220 installs (MEASURED).
- URL: https://github.com/guimatheus92/mcp-video-analyzer

### 5. claude-video-vision, jordanrendric
- **Tools:** 6 tools: `video_watch`, `video_analyze`, `video_detail`, `video_info`, `video_configure`, `video_setup`.
- **Path:** frames go to Claude as base64 images. Audio goes through Gemini (speech plus non-speech events), local whisper.cpp or openai-whisper, or the OpenAI API. Claude picks fps, range and resolution. The sample config shows `backend: local` and `frame_resolution: 512`.
- **Maturity:** 1,410★, v1.4.0 2026-10-06, pushed 2026-10-14 (MEASURED).
- URL: https://github.com/jordanrendric/claude-video-vision

### 6. watch-skill + DeepWatch, oxbshw
- **Perception:** a source is indexed once into frames, OCR and transcripts with absolute timestamps; `ask` answers cite moments.
- **Verification:** contracts on file digests, JSON, SQL, HTTP and DOM return VERIFIED, FAILED, UNVERIFIED or INCONCLUSIVE, judged by a separate process rather than an LLM. "THE LOOP" captures a browser flow, critiques it with a vision model, then fixes and re-verifies.
- **Install:** `pip install 'watch-skill[standard]'`; extras `[ocr]` (~80 MB model) and `[whisper]`; `watch-skill serve` runs a stdio MCP server with 39 tools.
- **Caveat:** `watch-skill doctor` auto-downloads yt-dlp and ffmpeg, a supply-chain consideration (INFERRED).
- **Maturity:** 518★, PyPI 1.4.3 2026-09-08 (MEASURED).
- URL: https://github.com/oxbshw/watch-skill

### 7. claude-eyes, moritzkremb
- **Status:** unchanged since F3 (60★, last commit 2026-10-16, MEASURED). See F3 §3.
- **Why it stays in the ranking:** its region `crop --box` at full resolution and its 88 of 92 cut / 0 of 8 dissolve self-test remain the most specific spatial claims among local skills (DOCUMENTED).

### 8. TwelveLabs: Claude Code plugin + Jockey
- **Plugin:** 26★, pushed 2026-10-08, last feature commit 2026-05-14, defaults to Pegasus 1.5 (MEASURED / F3). That makes the plugin more than 5 months old against Pegasus 1.6 (2026-10-06).
- **Jockey:** GA 2026-10-15 as a claude.ai connector.
- **Prices (F3, 2026-10-23):** Pegasus $1.75 per video-hour input plus $7.50/1M output; Jockey plans $0-$99/mo.
- **Docs:** they expose a docs-only MCP at `https://docs.twelvelabs.io/_mcp/server` (DOCUMENTED, llms.txt line 7). That server is not a video MCP.
- **Not found:** no standalone official `twelvelabs-io/*mcp*` video server repo (`gh api` returned 404 for `twelvelabs-io/twelvelabs-mcp-server`).
- **Third-party paths:** TwelveLabs is also reachable through mcp-video-analyzer (entry 4) and a merged PR in kimtaeyoon83/mcp-server-youtube-transcript (last commit 2026-07-21, "feat/twelvelabs", MEASURED).

### 9. watch-any-video (Wikivec Inc.)
- **Endpoint:** a remote MCP at `https://watchanyvideo.com/api/mcp`. Claude Code adds it with `claude mcp add --transport http`.
- **Tools:** `watch_video`, `upload_video` (one-time link; the browser sends the file straight to Google, up to 2 GB), `check_job`, `ask_video` (free follow-ups from a stored breakdown), `my_usage`, `whoami`.
- **Limits:** YouTube up to about 3 h. TikTok, Instagram, X and private YouTube are not supported.
- **Privacy:** the Gemini API paid tier ("nothing is used to train"); Google deletes files after 48 h; Q&A kept 7 days; breakdowns 30 days.
- **Price (2026-10-24):** Pro $8/mo or $60/yr for 20 h/month.
- **Note:** the vendor itself says "Answers can be wrong". All of this is DOCUMENTED at https://watchanyvideo.com/docs, /pricing and /privacy.

### 10. Memories.ai plugin
- **What it is:** a thin plugin made of skills, commands (`/memories:search`, `:add`, `:analyze`, `:transcribe`) and the hosted MCP `https://mcp.memories.ai/mcp`, with OAuth. "There's no local server to run". It works in Claude Code and Codex.
- **Price (October 2026, F3/Oct research):** $0.05/min to index at 1 fps.
- **Maturity:** plugin repo 1★, last commit 2026-07-27 (MEASURED).
- URL: https://docs.memories.ai/plugin.md

### 11. VideoDB
- **What it is:** skills plus a hosted MCP. It produces separate `spoken_words`, `vlm` and `ocr` artifacts.
- **Price and storage:** pricing is "Talk to us" and storage is persistent by default (October research, not re-verified).
- **Maturity:** `video-db/skills` 139★, last commit 2026-09-11. `video-db/agent-toolkit` last commit 2026-03-13 (**stale, over 6 months**) (MEASURED).

### 12. Valossa Assistant MCP
- **Endpoint:** a remote MCP at `https://mcp-assistant.valossa.com/mcp`, OAuth 2.0, documented for Claude Code, claude.ai, ChatGPT, Cursor, Codex and others.
- **Tools:** import and analyze videos, `find_detections` (exact search of things seen and sounds, with `min_confidence`, `start_s/end_s`), transcripts, clip export, and "ask the assistant". Tools that write data consume quota and prompt for confirmation (DOCUMENTED).
- **Pricing:** not found (valossa.com/pricing returned no prices to curl).

### 13. watch-cli, sonpiaz
- **Command:** `watch <url>` prints VIDEO, FRAMES and TRANSCRIPT paths.
- **Path:** frames come from local ffmpeg (evenly spaced). ASR goes to Kyma by default (`whisper-v3-turbo`), and an `audio-q` command sends audio to `gemini-3-flash-audio` through Kyma.
- **Price claim:** about $0.05 per video-hour (vendor).
- **Maturity:** 260★, v0.3.4 2026-09-04 (MEASURED). The MCP package was "not yet published".
- URL: https://github.com/sonpiaz/watch-cli

### 14. videoctx, dunfred
- **What it is:** an open `.vctx` index (SPEC.md) built from local keyframes, shots, faster-whisper and optional VLM captions. Claude answers from the text layer and pulls frames on demand.
- **Self-reported Video-MME (Oct 2026, query model Claude Opus 4.8, Knowledge-dominated subsets):**
  - short, n=150: 84.7% vs 74.0% uniform sampling vs 70.0% Gemini Flash-Lite native (pilot n=30);
  - medium, n=30: 70.0% vs 80.0% uniform;
  - long, n=30: 83.3% vs 76.7% Flash-Lite.
- **Caveats (the author's own):** n=30 cells wobble by 7-10 points; a text-view bug invalidated v0.2/v0.3. This is the only integration found with a benchmark number on a Claude model, but it is **self-evaluated, small-n and 1★**.
- URL: https://github.com/dunfred/videoctx

### 15. ffmpeg-skill + media-analysis-skill, kajisho5
- **ffmpeg-skill:** 42 standard-library Python tools behind a skill and MCP, mostly for editing. The analysis tools are `probe.py` (VFR, HDR), `scenes.py` (cuts, audio peaks), `look.py` (contact sheet PNG for the agent to inspect) and `cropdetect.py --motion-centre` (per-second motion centroid).
- **media-analysis-skill:** a no-AI "eyes and meters" layer that returns deterministic Observation JSON with sha256 provenance.
- **Maturity:** ffmpeg-skill 2,159★, v2.12.0 2026-10-23. media-analysis-skill 6★, v0.1.1 2026-10-23 (MEASURED).
- **Why it matters:** the motion centroid is a cheap, measured motion signal of the kind July's research said agents need (INFERRED).

### 16. Browser agents
- **Playwright MCP:** `browser_take_screenshot`; `browser_start_video`/`stop_video` *record* a `.webm` at 25 fps by default, which is an output (DOCUMENTED README).
- **Chrome DevTools MCP:** `take_screenshot` and performance traces (DOCUMENTED).
- **Claude in Chrome:** a beta extension on paid plans (secondary source).
- **What reading video amounts to here:** pausing the player, taking screenshots, and reading the YouTube transcript panel from the DOM (INFERRED). No audio reaches the model. Frame timing depends on the agent's step latency, and DRM or canvas players may screenshot black (INFERRED). For video, this is the weakest route.

### 17. Agent SDK patterns
- **Claude Agent SDK:** custom tool results take `text`, `image`, `audio`, `resource` and `resource_link`. PNG, JPEG, GIF and WebP reach Claude visually; other image types are saved to disk. Audio is saved to disk as a path (TypeScript) or dropped with a warning (Python). With `structuredContent` set, text blocks are not forwarded (DOCUMENTED). So a video tool has to return frames as images plus the transcript in text or structuredContent.
- **OpenAI Agents SDK:** tools return `ToolOutputImage` and `ToolOutputFileContent`; video is not mentioned (DOCUMENTED).

### 18. Codex CLI and Cursor
- **Codex CLI:** `--image` and pasted images only (DOCUMENTED). Codex plugin marketplaces carry claude-video, Memories.ai, BibiGPT and "Real Video for Codex" (crv).
- **Cursor:** no video-input entry in the changelog (MEASURED grep). It reaches video through MCP and `npx skills`.

### 19. Transcript-only MCPs
- **Servers:** kimtaeyoon83/mcp-server-youtube-transcript (603★), jkawamoto/mcp-youtube-transcript (492★, v0.8.1 2026-10-21), anaisbetts/mcp-youtube (552★), kevinwatt/yt-dlp-mcp (293★, v0.9.0 2026-05-20).
- **What they give:** captions or subtitles only. On our probe, transcript-only scored 11 of 24 (REPORT.md). The mcptube variant (0xchamin, 163★) last pushed 2026-04-13 (**stale**).

### 20. openrouter-mcp-multimodal, stabgan
- **What it does:** `analyze_video` (describe or Q&A over a video file) through any OpenRouter model, alongside generation tools. It has path sandboxes and SSRF guards. The default model is `google/gemma-4-26b-a4b-it:free`.
- **Maturity:** 101★, v5.1.3 2026-10-22 (MEASURED).
- **Note:** whether a given model actually accepts video is "a property of that model" (README).

## 5. Also seen, not ranked

- **Diffusion Studio `watch` skill:** 1,700 skills.sh installs, 146★ repo. It is a pointer to docs bundled in a desktop video editor. "Analyze & transcribe footage" uses paid credits (Pro $20/mo for 2,500 credits, 2026-10-24), so analysis runs on hosted models (INFERRED from the pricing FAQ).
- **Boson-Video:** 18★, MCP. Local scenes and transcript; the writer and checker models are cloud (Inception, TypeSafe); optional OpenAI frame check.
- **BibiGPT skill:** 130★; hosted; Smithery 389 uses.
- **Small local MCPs:** Azzy-H/mcp-video-frames (4★), yanlingLabs/video-extract-mcp (7★), JazerJu/video-miner (33★, no licence), WebDevBar/watch-video (16★), CFITCorporation/video-watch-skill (22★), chenzixin1/watchless (145★, Codex skill, Tencent cloud ASR per its README).

## 6. Gaps

- None of these tools was run on a video. Every quality number is the vendor's or the author's own.
- Glama's directory API needs an account key and was not searched.
- Valossa and VideoDB prices were not found.
- Whether Gemini CLI's inline video actually yields correct answers was not tested; only the code path was read.
