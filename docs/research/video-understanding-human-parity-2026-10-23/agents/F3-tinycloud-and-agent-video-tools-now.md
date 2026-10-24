# F3: Tinycloud and agent video tools, as of 2026-10-23

Question: what has changed since the 2026-10-06 teardown about tools that give a coding agent (Claude in particular) video
understanding, and does any of it change the October conclusions?

Labels: **MEASURED** = I ran the named command today. **DOCUMENTED** = a vendor page, README or paper says it (not
tested by us). **INFERRED** = my reasoning. Dollar figures marked ESTIMATED give their method.

Scratch copies of the fetched pages are in `/tmp/f3-fetch/` (they will not survive a reboot; the URL is the citation of
record). Nothing was installed, no account was created, nothing was uploaded.

## 0. The October baseline (what we concluded then)

- Claude has image input and no video input, so every route is a transcode into text plus stills
  (`~/.claude/research-artifacts/meeting-video-2026-10-06/model-understanding.md:15`, `:36`).
- Tinycloud is a launcher plus skills over Cloudglue's cloud. The agent never looks at frames: visual understanding comes
  back as text written on the server, and the meeting recipe is speech-only by default
  (`.../tinycloud-internals.md:98`, `:109`). It uploads the whole file and its path (`.../tinycloud-internals.md:141-142`).
  Ruling: borrow the design, run on-device (`.../tinycloud-internals.md:209`).
- Gemini is the cheapest cloud route at about $0.11 to $0.81 per video-hour, and its agentic mode was already known
  (`.../video-api-alternatives.md:13`, `:65`; `.../model-understanding.md:35`).
- Motion: frame-sampling VLMs are blind to it, and local opencv probes measure it
  (`docs/research/agent-video-understanding-2026-07-26.md:223-246`, `:252-254`).

## 1. Tinycloud and Cloudglue: nothing shipped since 2026-09-01

| Claim | Evidence | Label |
|---|---|---|
| The latest Tinycloud is still **0.3.25** (2026-09-01T02:22Z), on the stable channel, with no beta and 26 versions in total. There has been no release for 52 days, against the roughly one release every 3 days seen until September. | `npm view @cloudglue/tinycloud --json`; `curl https://media.cloudglue.dev/tinycloud-dist/manifest.json` (channels `{'stable': '0.3.25', 'beta': None}`) | MEASURED |
| The last commit to `cloudglue/tinycloud` is 2026-09-01 ("Prepare for tinycloud 0.3.25: describe prompts") | `api.github.com/repos/cloudglue/tinycloud/commits` | MEASURED |
| Cloudglue's other repos show only Dependabot fixes since September: `cloudglue-mcp-server` (2026-10-20) and `cloudglue-js` (2026-10-21). The last feature commit is `describe_config.prompt` (spec v0.7.32, 2026-08-31). | `api.github.com/repos/cloudglue/{cloudglue-mcp-server,cloudglue-js}/commits` | MEASURED |
| The newest public Cloudglue changelog entry is **2026-08-29, v0.7.32, "Describe Prompts"** | https://docs.cloudglue.dev/changelog.md | DOCUMENTED |
| Pricing is unchanged: 4 credits per minute for describe, extract, transcribe and indexing, in packs from $15/1000 to $600/60000 credits. That is $2.40 to $3.60 per video-hour (ESTIMATED: 240 credits × pack rate), the same as October (`.../video-api-alternatives.md:26`). | https://cloudglue.dev/pricing | DOCUMENTED |
| Modality conversion is unchanged: video becomes server-written text (speech, visual scene description, scene text, audio description, summary), plus thumbnail URLs. The agent reads JSON. Cloudglue makes no motion or spatial claim beyond shot/chapter segmentation and per-segment visual description. | `.../tinycloud-internals.md:107-109` | DOCUMENTED (Oct teardown) |
| The cofounder's open-source `kdr/overcast` (Apache-2.0, Tinycloud as the default perception backend) is still at v0.0.15. Its last commit to main and its npm publish are both 2026-08-05. Later pushes are Dependabot and test branches only. | `api.github.com/repos/kdr/overcast/{releases,branches}`; `npm view @kdrrr/overcast` | MEASURED |
| A web search found no October launch, GA or pricing change for Tinycloud | WebSearch "Cloudglue tinycloud video agent October 2026"; https://tinycloud.cloudglue.dev/ | DOCUMENTED (absence) |

What this means (INFERRED): the October ruling stands. Development has visibly paused, which weakens the case for
depending on Tinycloud and leaves the design ideas (`.../tinycloud-internals.md:181-199`) as the durable value.

## 2. Claude itself: still no video input

| Claim | Evidence | Label |
|---|---|---|
| The Claude API takes JPEG, PNG, GIF and WebP images. "Animations are unsupported, and only the first frame is used." The page never mentions video. | https://platform.claude.com/docs/en/build-with-claude/vision | DOCUMENTED |
| On Claude 4.7 and later (Opus 5.5 included), images are high-resolution tier: 2,576 px long edge, 4,784 visual tokens, cost `ceil(w/28)×ceil(h/28)`. A request holding more than 20 images forces every image to 2000 px or less per side. The limit is 600 images per request. | same page | DOCUMENTED |
| Because of that 20-image rule, in a multi-frame watch session the practical long edge is 2000 px, not 2576 (INFERRED from the rule above). The July doc's 1568 px figure (`agent-video-understanding-2026-07-26.md:64`) is the standard tier and is stale for Opus 5.5. October already corrected it (`.../model-understanding.md:36`). | | INFERRED |
| The Claude Code CHANGELOG at 2.1.310 contains no video-input feature. The only "video" hit is a fix for playing audio or video files in a cloud session's Outputs card. The local CLI here is 2.1.291. | `curl raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \| grep -i video` (line 1595); `claude --version` | MEASURED |
| Third-party coverage of Opus 5.5 "video" is about Opus 5.5 *making* video with code (Remotion, Three.js), not watching it | WebSearch results, e.g. https://www.dsebastien.net/2026-10-04-claude-opus-5-5-ask-for-a-video-get-a-program-you-can-edit/ | DOCUMENTED (secondary) |

## 3. Tool-by-tool: how each gives an agent video understanding

| Tool (date of latest change) | How it reaches Claude | Modality conversion | Local or cloud; price | Spatial / motion claim |
|---|---|---|---|---|
| **Tinycloud / Cloudglue** (0.3.25, 2026-09-01) | Shell CLI with 8 skills; Claude Code plugin; MCP server (dependency bumps only) | Video goes to the server and comes back as text; the agent reads JSON and never sees frames | Cloud; $2.40-3.60/h (ESTIMATED, section 1) | None beyond shots/chapters and text scene descriptions (DOCUMENTED) |
| **TwelveLabs Pegasus 1.6** (launched **2026-10-06**) | Claude Code plugin (MCP, slash commands, skills, hooks). Its feature work was last synced 2026-05-14 and it defaults to Pegasus 1.5. | Server-side video LLM returns text or JSON, timestamped segments and in-segment events; Marengo 3.5 embeddings for search | Cloud. Analyze input $1.75 per video-hour plus $7.50/1M output tokens. 2 h per call (4 h source with a window), 10 GB, 261,120-token context. | **Strongest motion claim found:** egocentric video, action labelling, "Trajectory and next-action prediction" in teleoperated video (DOCUMENTED, untested) |
| **TwelveLabs Jockey** (GA **2026-10-15**; web search added 2026-10-09) | **claude.ai Connector** ("Jockey by TwelveLabs"), also ChatGPT; Agents API | Videos are uploaded into a hosted "knowledge store", and an agent searches and reasons across it, returning clips with timestamps | Cloud. New billing from 2026-10-15: Free $0 (3 GB), Plus $29/mo (50 GB), Pro $99/mo (200 GB), Enterprise. Jockey overage $2/1M tokens; storage overage $0.065/GB-month. | Cross-video search and subject tracking ("find every moment where someone enters a room") (DOCUMENTED) |
| **Gemini API** (video doc updated 2026-10-13) | No Claude path of its own; reached through skills or MCP servers that hold a `GEMINI_API_KEY` (rows below) | Native video: frames at 1 FPS by default (66 tokens/frame low, 258 high) plus audio at 32 tokens/s. In agentic mode the model "navigates the timeline", loading transcript, frames or audio on demand. | Cloud. 3.8 Flash $0.75/1M input until 2026-12-31, then $1.50. 3.5 Flash-Lite $0.30. Paid tier: not used for training; free tier: used. | 1 FPS "may miss details in videos with rapid motion or quick scene changes"; "Higher resolutions improve ... fine text or ... small details" (DOCUMENTED) |
| **Gemini 4 Argon** (**new**: blog 2026-10-13; CNBC 2026-10-01; model page updated 2026-10-14) | Same as Gemini above | Text, image, video, audio and PDF in; text out; 1,048,576-token context; agentic video "supported and defaults to static" on its model page | Cloud, paid tier only. $2/1M input and $10/1M output until 2026-11-30, then **$4 and $20 from 2026-12-01**. ESTIMATED: one hour at low resolution is 360K tokens, so $0.72 now and $1.44 after the change (3600 s × 100 tokens/s × price). | "Major improvements in spatial reasoning"; ERQA (3D physical/spatial) 87%, "outperforms all other frontier models". **No video benchmark published.** (DOCUMENTED, vendor) |
| **bradautomates/claude-video** `/watch` (v0.3.2, 2026-09-25; **19,112 stars**) | Agent Skill and Claude Code plugin; also Codex and 50+ hosts | **Local engine:** yt-dlp, then ffmpeg scene-aware frames (cap 100 in `balanced`), 16×16 dedup, captions or WhisperX/Groq/OpenAI; Claude Reads the JPEGs. **Gemini engine (added v0.3.0):** uploads the whole video to Gemini agentic and relays its text answer. | Local engine free apart from Claude image tokens. ESTIMATED: 100 frames × 209 tokens (512×288) ≈ 21K tokens ≈ $0.08 on Opus 5.5 at $4/1M. Gemini engine: Google pricing. | None. Its README warns that 16×16 dedup "cannot preserve every code edit" and that default frames are 512 px wide (DOCUMENTED) |
| **moritzkremb/claude-eyes** (**new**: created 2026-10-15; 60 stars; MIT) | Agent skill plus `eyes` CLI with `--json`; MCP server only on the roadmap | Five-track index: contact sheets at 0.5-4 fps, cuts, words said (whisper.cpp, word times within about 0.05 s), words shown with screen position (Apple Vision OCR), and loudness/silence/palette. Navigate with `search`, `crop --box` (full resolution), `burst` (8 frames in 1 s), `frames --at/--range`. | **Fully local**: "Nothing is uploaded". Optional ElevenLabs transcription in the cloud. | Spatial: on-screen text *position*, region crops. Motion-adjacent: burst; cut detection 88 of 92 cuts on 7 test edits; it **misses dissolves (0 of 8)**. Its "editing DNA" covers cuts per minute and shot lengths. No optical flow. (DOCUMENTED) |
| **jordanrendric/claude-video-vision** (v1.4.0, 2026-10-06; 1,410 stars) | MCP server plus Claude Code plugin (`video_watch` and others) | ffmpeg frames go to Claude as images. Audio goes through Gemini (speech and non-speech events), local Whisper, or OpenAI. "Claude adjusts fps, time range, and resolution", e.g. the original fps for "the first second". | Local or cloud depending on the audio backend. Default `frame_resolution` 512. | Adaptive fps only (DOCUMENTED) |
| **subh05sus/video-understanding-skill** (**new**: 2026-10-20; 0 stars) | Agent skill | Local copy of Gemini's Think-Act-Observe loop with Claude as the agent: a map (segments, cuts, "where it's fast or still", speech vs music), search, frames on demand, re-watching fast parts at 8-12 fps, OCR zoom, a memory per video | Local, no key | Motion-adjacent: fast/still map plus dense re-watch (DOCUMENTED, unadopted) |
| **AAyberkU/video-watch** (2026-10-21), **HinkoK/watch-skill** (2026-10-07) | Agent skills | video-watch: transcript plus non-speech sound map plus stills, all local. watch-skill: wraps claude-video 0.3.2, takes speech from captions and sends the picture to Gemini, falling back along a chain of free models. | Local / cloud | None (DOCUMENTED) |
| **VideoDB**, **Memories.ai** | Hosted MCP and skills (October row) | As in October | No new public price found | No 2026-10 changes found. `video-db/skills` last pushed 2026-09-11 (MEASURED, GitHub API). |
| **OpenAI GPT-6 Astra** (released 2026-09-03 per secondary sources) | n/a | Text and image input only, per secondary sources; video explicitly not supported | n/a | n/a (DOCUMENTED, secondary only; OpenAI's own docs not reached) |

Sources for the table:
- Twelve Labs: https://docs.twelvelabs.io/v1.3/docs/get-started/release-notes.md (Oct 6, 9, 15, 22 entries),
  https://docs.twelvelabs.io/v1.3/docs/concepts/models/pegasus/pegasus-1-6.md (lines 17, 21, 26, 44, 54 of the fetched
  copy), https://docs.twelvelabs.io/v1.3/agents/get-started/start-with-jockey.md, https://www.twelvelabs.io/pricing,
  https://www.twelvelabs.io/overage, and the plugin README at
  https://github.com/twelvelabs-io/twelve-labs-claude-code-plugin (commits via the GitHub API, MEASURED).
- Gemini: https://ai.google.dev/gemini-api/docs/video-understanding (agentic section, fetched copy lines 614-625; 1 FPS
  caveat, line 1001), https://ai.google.dev/gemini-api/docs/pricing (updated 2026-10-22),
  https://ai.google.dev/gemini-api/docs/models/gemini-4-argon, and
  https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-argon/.
- Skills: https://github.com/bradautomates/claude-video (CHANGELOG.md:16-19; README.md:132, 193-198, 267),
  https://github.com/moritzkremb/claude-eyes (README.md:7, 76-80, 92, 142; ROADMAP.md),
  https://github.com/jordanrendric/claude-video-vision (README.md:9, 16, 76-88, 160),
  https://github.com/subh05sus/video-understanding-skill, https://github.com/AAyberkU/video-watch,
  https://github.com/HinkoK/watch-skill.
- Star counts and dates: `api.github.com/repos/<name>` and the GitHub search API, MEASURED 2026-10-23.
- OpenAI: https://bibigpt.co/features/gpt-6-astra-explained and https://www.cometapi.com/de/models/openai/gpt-6-astra/
  (both secondary).

## 4. Flags: what changes the October conclusions

1. **No change to the core conclusion.** Claude still has no video input (section 2, DOCUMENTED and MEASURED). Every
   agent tool found either feeds Claude stills plus text, or hands the video to a cloud model and relays its text.
   "Watching like a human" is still a transcode, as in `model-understanding.md:15`.
2. **New egress trap in the most-installed skill.** Since v0.3.0, claude-video's `--engine auto` picks Gemini whenever a
   `GEMINI_API_KEY` resolves, and it looks in the environment, then `~/.config/watch/.env`, then the cwd `.env`. Local
   files are then uploaded to Google's Files API (README.md:193-198, DOCUMENTED). If a key happens to be in the
   environment, a meeting recording would leave the machine without any prompt (INFERRED). The October table described
   it only as "frames + transcript handed to the agent" (`.../local-replication.md:152`). That row is now incomplete.
   Pin `--engine local` or `WATCH_ENGINE=local` if it is ever used near private recordings.
3. **The community converged on our design.** claude-eyes (2026-10-15) and video-understanding-skill (2026-10-20)
   implement the same pattern: index once, then local navigate and zoom, with contact sheets, word-timed transcript,
   OCR with positions, crop, burst and cut detection. That is the October on-device plan
   (`.../tinycloud-internals.md:209`; `agent-video-understanding-2026-07-26.md:47-53`). claude-eyes publishes two numbers
   our build can borrow as test cases: 88 of 92 cuts found, and 0 of 8 dissolves (DOCUMENTED). Neither tool does optical
   flow, so the July finding that motion needs measurement (`agent-video-understanding-2026-07-26.md:252-270`) still has
   no packaged competitor (INFERRED from the READMEs).
4. **There is now a new top tier for the off-machine option.** Gemini 4 Argon takes video, claims best-in-class spatial
   reasoning (ERQA 87%) and supports agentic video. It is paid-only, and its price doubles on 2026-12-01 (DOCUMENTED).
   Google published no video benchmark, so whether it is better at video than 3.8 Flash is unknown. The ranking in
   `.../video-api-alternatives.md:69-78` holds; Argon becomes the "quality" variant at roughly $0.72 to $1.44 per hour at
   low resolution (ESTIMATED). A small detail: the video doc's agentic table lists only 3.8 Flash, 3.6 Flash and 3.5
   Flash-Lite, while Argon's model page says agentic is supported. The two vendor pages disagree.
5. **TwelveLabs is now a zero-code Claude route, still in the cloud.** Jockey went GA on 2026-10-15 as a claude.ai
   connector, with flat plans from $29 a month. Pegasus 1.6 adds the strongest motion claim of any vendor here
   (egocentric action labelling, trajectory prediction). The per-hour Pegasus price is unchanged at $1.75 (DOCUMENTED).
   I did not re-check the October privacy finding that customer data is used to improve the service
   (`.../video-api-alternatives.md:16`), so it should still be treated as blocking for private recordings. The Claude
   Code plugin lags behind: it defaults to Pegasus 1.5 and its last feature sync was 2026-05-14 (MEASURED).
6. **Gemini model drift.** `gemini-3.7-flash` (released 2026-08-13) is claude-video's default. Its endpoint
   "automatically routes API requests to `gemini-3.8-flash`", so it is billed at 3.8 Flash rates (https://ai.google.dev/gemini-api/docs/deprecations, DOCUMENTED). 3.8 Flash's
   price doubles on 2027-01-01 (DOCUMENTED, unchanged from October).
7. **Research signal.** DeltaStreamer ("Towards Human-Like Agentic Streaming Video Understanding", arXiv 2610.19849,
   repo created 2026-10-09) and Video-RSI (arXiv, 2026-09-29) are new agentic-video research codebases
   (https://github.com/BBBBchan/DeltaStreamer, https://github.com/bingjunluo/Video-RSI). I read only their READMEs.
   Neither is an agent tool (DOCUMENTED, unread).

## 5. Context: the linked post

The `/read-twitter` link (https://x.com/ycombinator/status/2113654566776709147) is a YC interview posted 2026-10-23
15:31 UTC, about making launch videos. The attached video is 3840×2160 and has 17 chapter marks running to 45:41+.
It is a natural test subject (a talking-head interview with demo inserts), not a tool announcement. MEASURED:
`curl api.fxtwitter.com/ycombinator/status/2113654566776709147`.

## 6. Gaps

- None of the tools above was run on a real video by me. Quality, cut-detection figures and motion claims are the
  vendors' own.
- Not re-verified today: the Twelve Labs and Cloudglue data-use terms, Memories.ai and Reka pricing, VideoDB features.
- OpenAI's video-input status comes from secondary sources only.
