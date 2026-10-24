# V1 — NVIDIA GTC 2026 S81836 "Visual AI Agents for Real-Time Video Understanding", watched

Source: https://www.youtube.com/watch?v=3yPQHcEZDaI (33:37; NVIDIA Omniverse channel, uploaded 2026-03-30). Speakers on the title slide: Roopa Prabhu and Adam Ryason, NVIDIA [0:05]. Adam presents 0:00–13:22, 16:42–18:10, 23:33–24:31 and 29:50–end. Roopa presents the architecture and workflow deep dives (13:23–16:42, 18:12–23:33, 24:32–29:50).

Labels: **MEASURED** means I read it off the frame or measured it myself. **DOCUMENTED** means the speaker or a slide says it (vendor claim). **INFERRED** is my reasoning. Timestamps are [mm:ss] into the talk.

## 0. Verdict for us

**As software: not applicable. As design evidence: somewhat helpful, mostly confirming what we already do.**

| Question | Answer | Basis |
|---|---|---|
| Can it run on our Apple-Silicon Macs? | **No.** Every number in the talk is on H100-SXM or RTX-Pro 6000 SE. The cloud trial is "two RTX Pros" [31:53]. The ingestion layer is DeepStream / NVDEC / cuVS. | DOCUMENTED (slides 20:05, 24:45, 26:05; speech 31:53). R5 §2 already found that the docs list no macOS support. |
| Does it fit the corporate "nothing may be uploaded" meeting case? | Only if the company runs its own NVIDIA GPU servers. On the Mac itself, no. Brev / Launchable is cloud. | DOCUMENTED [30:05, 31:37]; INFERRED for the policy fit |
| Is it meant for meetings? | **No.** It is built for physical-space CCTV: warehouses, cities, soccer, subway platforms, factory SOPs. Its CV layer (RT-DETR detectors, multi-camera 3D tracking, BEV) has nothing to detect in a Teams screen-share. Audio comes up exactly once, as a partner remark (Kaltura "video and audio" [12:42]). ASR, diarization and OCR are never mentioned. | MEASURED (full transcript plus every slide) |
| Does it integrate with Claude Code? | **Yes, at this talk only as the coding tool.** The "DeepStream coding agents" demo is literally **Claude Code v2.1.52, Opus 4.6, Claude Enterprise** writing a DeepStream multi-camera tracking app [16:15]. The speakers also say VSS tools are standalone microservices "a claw" can call [10:10], and that the release ships "agent skills" [11:14]. No MCP slide; the word MCP is never said. | MEASURED (frame at 16:15); DOCUMENTED [10:10, 11:14] |
| What is worth taking? | Three patterns that our skill or spec can copy for free, listed in §8: a per-attribute VLM critique with pass/fail before answering; planner decomposition into embedding queries plus hard metadata filters plus weighted rank fusion; and a report that carries a keyframe plus a time span for every event. | INFERRED |

This talk is about **VSS 3.0** (March 2026, "released pretty much yesterday" [10:38], early access, "GA later this spring" with source [32:20]). R5's entry describes **VSS 3.3.0** (2026-10-21), which is 7 months newer and names different models (Cosmos3 Nano Reasoner, Nemotron 3.5 Lightning) plus the `vss` CLI and agentskills.io skills. Where the two differ, R5 is the current state and this talk is history.

## 1. Method (what was actually watched)

- **Media:** 1920x1080 avc1 (format 137) plus opus audio, 164 MB, 2016.7 s at 29.97 fps (MEASURED, ffprobe). The installed yt-dlp 2026.07.04 got **HTTP 403** on every format; `uvx --from 'yt-dlp[default]@latest'` (2026.10.21) downloaded it at once. The skill's "check yt-dlp is CURRENT" warning bit again.
- **Transcript:** **whisper-cli large-v3-turbo** (not the auto-subs) over the whole file in one background call: 254.8 s of compute for 33.6 min, at a load average of about 125 (MEASURED). The prompt was seeded with NVIDIA product names. Mishearings that remained: "DPOW" = DeepHow, "Qion" = KION, "Kuvis" = cuVS, "NIMS/NEMS" = NIMs, "Tau" = TAO, "LLS" = LVS, "Brave Launchables" = Brev Launchables, "mnemotron" = Nemotron, "GPO-accelerated" = GPU-accelerated. Auto-subs were downloaded but not used.
- **Slide map:** per-frame luma difference (skill one-liner) found 90 cuts at threshold ≥ 8. Then a 20 s sweep of 101 frames, each extracted with its own `-ss` so the labels are exact, laid out as 5 sheets of 4x5.
- **Full-resolution reads:** 27 frames at 1920x1080, one per Read, covering every distinct slide and the demo frames. Three slides were read only at 960 px (agenda, "How AI Agents Work", sessions list); their text is large and was legible.
- **Artifacts:** `/tmp/vss-talk-2026-10-24/` (`asr.srt`, `asr.json`, `asr.txt`, `hires/*.png`, `sheet_part_*.jpg`, `demo1_sheet.png`, `lumadiff.npy`).

## 2. Talk structure (slides as shown)

| Time | Slide / segment | Key content (MEASURED from the frame unless marked) |
|---|---|---|
| 0:05 | Title | "Visual AI Agents for Real-Time Video Understanding [S81836]", Roopa Prabhu and Adam Ryason (the slide spells NVIDIA as "NIVIDIA" under Adam) |
| 0:45 | Agenda | Intro to Vision AI; Agentic Workflows (Search, Video Summarization, Alert Contextualization); Developer Journey |
| 1:25 | Automating Physical Spaces | 10M factories, 40M power-line miles, 570M farms, 12K cities, 1.5B vehicles, 2B commercial cameras |
| 2:45 | Challenges | Low search accuracy ("limited to trained attributes, unverified results"); real-time alert fatigue; manual reporting is tedious |
| 6:25 | VSS overview | **<5s** agentic deep search with VLM critique; **<1s** contextual verified alerts; **60x** summarization speedup. Example card: "Does the operator complete assembly steps 1-9? … operator missed two steps … STEP 8 (Missed Step)" |
| 9:05 | How AI agents work | Thinking, I/O prompt, tool use, computer use, other agents, memory |
| 10:45 | VSS 3 features | VSS Agent → Search Agent (critique/plan/solve), Alert Agent, Reporting Agent; tools Cosmos Reason, Cosmos Embed, C-RADIO, RAG. Features: Agentic Search; Video Summarization & Report Generation; Contextual Verified Alerts; Industry-Scale Blueprint Examples; Modular Architecture; **Agent Skills** |
| 11:45 | Partners | See §6 |
| 13:25 | High-level architecture | See §3 |
| 14:45 | Agent workflows | Three compositions, see §3 |
| 15:25–16:42 | DeepStream coding agents and demo | See §4 |
| 16:53–18:10 | Deep-search demo (soccer) | See §5 |
| 18:25–23:33 | Deep-search deep dive (4 slides) | See §3.2 |
| 23:35–24:31 | Summarization demo | See §5 |
| 24:45 | Summarization & report slide | LVS latency table, §7 |
| 26:05 | Verified contextual alerts | §3.3, §7 |
| 27:05 | Sim-Train-Deploy | Omniverse + Cosmos (synthetic data) ↔ TAO fine-tuning of VFM/VLM ↔ NIMs + VSS microservices + Blueprint |
| 28:45 | "Claw slide" | NemoClaw / OpenShell / OpenClaw, §4 |
| 30:05 | Get started | Explore (free, build.nvidia.com) → Trial (Launchable, "starting at $10/hour", code "vss-3-gtc2026" for $30 Brev credit) → Build (GitHub; public CSPs, DGX Cloud, on-prem) → Deploy (NIMs; "For NVIDIA AI Enterprise licensing, contact your account manager") |
| 33:25 | Other GTC sessions (Mar 17–18) | — |

Several slides carry the footer "NVIDIA CONFIDENTIAL. DO NOT DISTRIBUTE." (15:25, 28:45, 33:25), even though the recording is public (MEASURED).

## 3. Architecture

### 3.1 Three layers (slide 13:25, speech 13:31–14:37)

1. **Real-Time Video Intelligence (RTVI) microservices.** Camera or video goes into GPU feature extraction, from streams and stored video. They "scale to hundreds of cameras real-time" [13:43] (DOCUMENTED). There are three sub-services (slide 20:05):
   - **RT-CV:** RT-DETR (EfficientViT/L2), optionally with RADIO-CLIP attribute embeddings.
   - **RT-Embed:** Cosmos-Embed-1-448p. Its pipeline is NVDEC decode → preprocessing → Cosmos Embed inference → MsgBroker.
   - **RT-VLM:** Cosmos Reason 2, producing dense captions.

   All of them publish to a message bus. Embeddings go to a **vector DB on cuVS**; video goes to Video Storage / VMS.
2. **Downstream Analytics.** Continuous processing for insights: Behavior Analytics, plus Alert Verification in the alert workflow. It feeds **Elasticsearch**.
3. **Vision-based Agent Tools.** A "Video Agent" runs a Plan / Tool-Use / Reflect loop with three tools: Deep Search, Report Generation and Video Summarization. Its NIMs are **NVIDIA Nemotron v2 9b** (LLM) and **Cosmos Reason 2 8b** (VLM).

The speaker says the layers "are independent. They scale independently. They are modular. You can replace them with your own components" [14:24] (DOCUMENTED).

The workflows compose these blocks as follows (slide 14:45):

| Workflow | Agent tools | Downstream | RTVI |
|---|---|---|---|
| Agentic search | Nemotron Nano v2 + Cosmos Reason 2; Search + Critique | Behavior Analytics | RT Embed + RT CV |
| Long video summarization | Nemotron Nano v2 + Cosmos Reason 2; Video Summarization + Report Generation | — | RT VLM |
| Alert contextualization | Nemotron Nano v2 + Cosmos Reason 2; Report Generation | Behavior Analytics + Alert Verification | RT CV |

### 3.2 Agentic deep search (slides 18:25, 20:45, 21:45, 23:05)

- **Ingestion** extracts event embeddings, object embeddings and CV metadata, then applies "spatial and temporal filtering" before the DB [19:26].
- **Step 1, Plan:** the LLM decomposes the query. Worked example on the slide: "Find a man pushing a cart wearing a beige shirt between 1 pm and 2 pm at Endeavor heart" splits into:
  - "man pushing cart", sent to Cosmos Embed and the Video Embedding DB;
  - sensor filter "Endeavor heart";
  - dateTime filter 2009-06-15T13:00–14:00;
  - "man" and "beige shirt", sent to RADIO-CLIP and the Attribute Embedding DB.
- **Step 2, Tool use:** the two embedding searches are combined by **Weighted Rank Fusion / Reranking** into top-k videos.
- **Step 3, Reflect:** "Video Retrieval & Temporal Merging" → top-k clips → **VLM Critique** (Cosmos Reason with a prompt) → user.
  - Its output is "a clear pass/fail signal with reasoning" and it "reasons over actions, attributes, time and space" (slide 21:45).
  - The VLM "tells you exactly which attributes of the query matched" [22:22], and the critic can re-run the search loop [22:39] (DOCUMENTED).
- **Performance table** (slide 23:05): Plan, Nemotron Nano 9b v2: 0.74 s · Embedding retrieval, Cosmos Embed: 0.006 s · RADIO-CLIP: 0.065 s · Reflect, Cosmos Reason 2 8b: 1.06 s. The trace comes from the NeMo Agent Toolkit [23:19]: total `search` 2.17 s, with 5 `video_understanding` critic calls running in parallel at 0.95–1.13 s each. The slide gives no hardware.

### 3.3 Summarization (LVS) and alerts

- **LVS** (slide 24:45): Video → VMS → RT VLM (Cosmos Reason 2) writes dense captions to a database. The agent then uses Video IO & Storage, Report Generation and Long Video Summarization tools with Nemotron Nano v2 (LLM) and Cosmos Reason 2 (VLM). The slide claims "Event context and temporal coherence … limiting hallucination". This is the chunk → caption → aggregate design R5 describes (DOCUMENTED). The talk does not give a chunk length, a sampling fps or a context size.
- **Alerts** (slide 26:05): the video stream goes over RTSP to RTVI CV; CV metadata goes to Kafka; Behavior Analytics emits events; the Alert Verifier (VLM) emits verified alerts into the Video Analytics DB; the agent then reports. Demo frame: a subway platform with person masks (one red), captioned "Person standing far left has one foot on or near the line."

## 4. "Coding agents and pipelines" segment [15:20–16:42], and the claw slide [28:27–29:50]

- **Slide title:** "Customize Your Real-Time Video Intelligence With A Prompt — With DeepStream Coding Agents". The RTVI box is circled; the video on the slide is captioned "Update RTVI With A Multi-Camera Tracking Pipeline".
- **What the demo actually shows** (MEASURED, frames 15:53–16:36):
  - VS Code opens `deepstream-mv3dt-app`. It contains about 20 C source files (`deepstream_source_bin.c`, `deepstream_tracker_bin.c`, …), YAML tracker configs and deployment scripts (`check_prerequisites.sh`). The overlays read "Meant 1,000s Of Lines Of Code", "Spread Across Tens Of Files", "Including Deployment Scripts".
  - It then cuts to **a Claude Code terminal: "Claude Code v2.1.52 · Opus 4.6 · Claude Enterprise · /dli/task/workspace", with `/model` set to `opus (claude-opus-4-6)`**. The prompt reads: "Build a real-time multi-camera object tracking application for a warehouse or retail environment using NVIDIA DeepStream. 4 IP cameras … single globally consistent ID … Outputs: live Bird's Eye View map …; tiled 4-camera feed with 3D bounding boxes; REST API; Kafka event stream." The overlay says "Now, Simply Define Your Requirements."
  - The result is a single `pipeline.py` on **pyservicemaker** (`Pipeline, Probe, Receiver, SourceConfig …`) with nvtracker, nvmultistreamtiler, a Kafka msg-meta probe, a FrameCapturer, a BEVRenderer and CrossCameraTracker imports. Overlays: "To Generate A Deployable Pipeline" and "Ready for VSS With No Performance Loss". The last shot is the tiled 12-camera warehouse view plus the BEV map, captioned "Real-Time Multi-Camera Tracking From A Prompt".
- **Claim vs. demo:** "our new coding agent can do this just with a prompt" [16:13] (DOCUMENTED). The footage is an **edited marketing cut**: overlays, cuts, no run time shown, no evidence the generated app ran unedited (MEASURED). INFERRED: the "DeepStream coding agent" is Claude Code plus DeepStream-specific context (DLI workspace path), not an NVIDIA model.
- **Agent integration claims:**
  - "You can have a claw connect and communicate to these specific tools. Each of these tools are being provided as standalone microservices" [10:10–10:19].
  - The release is modular "to allow for also agent skills to be connected to it" [11:14].
  - "VSS isn't going to be giving you the agent … VSS is giving you all of the vision accelerated tools that you need to bring into … your own agents" [30:04] (all DOCUMENTED).
- **Claw slide** (28:45): "Embedding Visual intelligence into everyday workflows with NVIDIA NemoClaw". Bullets: embed VSS agents into existing workflows; deliver insights into operational tools; auto-generate incident summaries; closed-loop autonomous actions; "Run autonomous agents safely with Nvidia NemoClaw OpenShell secure sandboxed runtime environment for OpenClaw". The screen shows a chat app (Slack-like) with bot "brev-claw-rtx-6000": "Subscribed to road incidents in SJ Downtown", then an incident card (INC-2026-0054, stalled_vehicle, severity medium, PCAM-DT-009, a description, an attached test_incident.mp4) (MEASURED).
- MCP is not named anywhere in the talk (MEASURED, transcript search). R5 documents MCP and a `vss` CLI for 3.3.0; those came later.

## 5. Demos: what the screen shows vs. what is claimed

| Demo | On screen (MEASURED) | Claimed (DOCUMENTED) | Notes (INFERRED) |
|---|---|---|---|
| Deep search, soccer [16:53–18:10] | UI "VSS BLUEPRINT \| Vision (Search)", "Hi, I'm Vision Agent". The pipeline diagram reads Query → Video Agent (Plan → Act → Reflect); **LLM: Qwen 3.5 (Planning)**; Attributes: **C-RADIO, SigLIP2**; Actions: Cosmos Embed; Elasticsearch KNN vector DB; VIOS clip retrieval; **VLM: Qwen 3.5 (Critique)**. Query "Show me when a player on the blue team scores a goal". Five clips with similarities 0.55, 0.51, 0.50, 0.47, 0.46: top two **Confirmed** (✓ blue team player ✓ scores a goal), three **Rejected**. Follow-up "Which player scored it?" answered: "Player 2 (Blue team) scored … second goal … at 110s-120s … Player 1 … making the score 2-1." | Works on streamed video; features embedded on arrival; results fused across embedding spaces and validated [17:08–17:39] | **The demo stack is Qwen 3.5, not the Nemotron + Cosmos Reason 2 the slides name**, so the models are swappable in practice. Sensor "FinalSoccerScoreboard-Mask-720p" with start time 2025-01-01T00:00:25 suggests a synthetic or staged clip. |
| Summarization / report [23:35–24:31] | UI "VSS BLUEPRINT \| Vision (LVS)", "Developer Agent". Upload `warehousee.mp4` (2:20). Prompt "Generate a pdf report summarizing all events happening in the warehouse with timestamp using LVS." A human-in-the-loop dialog asks for a scenario (default "traffic monitoring"); tool `lvs_video_understanding`. Output: Markdown + PDF report. PDF `vss_report_20260313_183502.pdf`, 3 pages, agent `vss_agent 26.1.2-01de6bc-prod.245`, "6 event(s) were detected", event 1 "[0.0s-9.0s]: A man wearing a plaid shirt and jeans walks through the aisle between the shelves" with a keyframe | Intermediate tool calls and reasoning are shown for debugging [24:15] | A 2:20 clip, not an hour. No latency is shown for it. |
| Coding agent [15:52–16:38] | §4 | §4 | Edited cut |
| Alerts [26:05] | Looping clip in the slide (subway masks) | <1 s verified alerts | No live UI shown |
| Claw [28:45] | Static screenshot of a Slack-like incident bot | Closed-loop actions | Screenshot only |

## 6. Partner results (slide 11:45; all DOCUMENTED vendor claims, no method given)

DeepHow: worker training, "80% faster onboarding time" · KION: warehouse operations, no number · Linker Vision: city operations, "80% reduction in incident response times" (the speaker said "incident reporting … fatigue" [12:25]) · Kaltura: media management, "Analyze video 30x faster with 95% cost reduction" (the speaker added "video and audio" [12:42]) · Pegatron: manufacturing, "67% reduction in defects" · VAST: "Ingesting & retrieving from petabytes of NHL archives".

## 7. Numbers, hardware and internal consistency

| Claim | Source | Check |
|---|---|---|
| Max concurrent streams, H100-SXM / RTX-Pro 6000 SE: RT-CV (RT-DETR EfficientViT/L2) 11 / 15; RT-CV + RADIO-CLIP 11 / 15; RT-Embed (Cosmos-Embed-1-448p) 200 / 144; RT-VLM (Cosmos Reason 2) 108 / 59 | slide 20:05 | Per GPU presumably, but not stated. "Hundreds of cameras" [13:43] holds only for embeddings (INFERRED) |
| LVS end-to-end: 10 min video 58 s (H100) / 73 s (RTX-Pro); 60 min video 277 s / 320 s; "1 hour video summarized under 6 min" | slide 24:45 | That is **13x real time (H100) and 11.25x (RTX-Pro)** (INFERRED arithmetic). The "60x Summarization Speedup" [6:25] and "60x to 100x" [6:48] must be against an unstated baseline. |
| Deep search "<5s" | slide 6:25 | The trace shows 2.17 s (slide 23:05). Consistent. |
| "plan and reflect adds some latency, but it's still under a second" | speech [23:05] | **Contradicted by the slide on screen:** 0.74 s + 1.06 s = 1.8 s, and the trace total is 2.17 s (MEASURED) |
| Alerts "sub-second": "0.82 and 1.00 second response on RTX Pro 6000 SE and H100 SXM" | slide 26:05 | 1.00 s is not sub-second, and the RTX Pro is listed as the faster card (MEASURED wording) |
| Hardware named | slides, speech | H100-SXM, RTX-Pro 6000 SE (Blackwell server edition), "two RTX Pros" for the one-click Launchable [31:53], an NCP or cloud inference point [8:29], edge or at-camera extraction [8:22]. **Jetson and DGX Spark are never named in this talk** (MEASURED); R5 has them for 3.3.0. Deployment options: public CSPs, NVIDIA DGX Cloud, on-prem (slide 30:05) |
| Licensing hints | [32:20], slide 30:05 | "Currently in early access … when GA comes later this spring … all the source code for the individual microservices … open source". Trial "starting at $10/hour"; production via NVIDIA AI Enterprise through an account manager. R5 has 3.3.0 as Apache-2.0 code. |

No accuracy benchmark is given anywhere: no recall@k, no QA score and no human comparison. Every performance number is latency or throughput (MEASURED).

## 8. What transfers to our Mac pipeline (INFERRED unless marked)

1. **A per-attribute VLM critique before answering.** VSS checks each retrieved clip against each query attribute and returns pass/fail per attribute, not one relevance score (soccer demo: "✓ blue team player ✗ scores a goal").
   - Our skill's equivalent is a full-res `Read` of the candidate window before claiming.
   - The cheap upgrade is to make that confirm step explicit and itemized in `skills/video-understanding/SKILL.md`: decompose the question into attributes and mark each one confirmed or rejected from the frames.
   - DVD's "always CONFIRM with frame_inspect_tool" (R5) is the same idea. Two independent systems converging on it raises our confidence in it.
2. **Hard filters separated from semantic queries.** The planner pulls out the sensor and datetime as exact filters and sends only the descriptive phrases to embeddings, then fuses by weighted rank. For meeting recordings: the speaker, time window and screen-state id (S6 in `v2-spec.md`) are hard filters; transcript and OCR text are the semantic channel.
3. **Report shape.** One event = a time span + a one-line description + a keyframe. This matches the spec's evidence-package windows. Nothing new, but it confirms the format.
4. **Not transferable:**
   - The CV layer (detectors, tracking, BEV), which has nothing to detect in a screen-share.
   - Dense VLM captioning as the main signal. Our own measurements show OCR of screen text beat transcript-only reading (0.92 vs 0.50 / 0.39, `v2-spec.md` §0), and VSS has no OCR or ASR story at all.
   - Everything CUDA.
5. **Ecosystem signal:** NVIDIA's own demo uses Claude Code as the coding agent, and (per R5) VSS 3.3.0 ships skills naming Claude Code. If the company ever stands up a GPU server, VSS is the most Claude-Code-ready of the GPU stacks, but it would still be CCTV-shaped.

## 9. Caveats

- Speech-only figures depend on whisper. Product names were fixed by hand against the slides.
- At 20 s sampling a sub-20 s slide could be missed. The luma-diff cut list was checked at 15:21, 15:52, 16:38, 18:11, 19:10, 19:46, 23:34 and 24:24, and every cut there resolved to a slide or demo already covered.
- Demo footage is edited. Nothing in it is a timed or reproducible run.
