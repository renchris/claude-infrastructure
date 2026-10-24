# R3: Open-weight video VLMs you can run locally (as of 2026-10-24)

Axis: open-weight video-capable VLMs and omni models that an agent builder can run on their own hardware, with Apple Silicon (MLX) first. This extends `../../video-understanding-human-parity-2026-10-23/` (REPORT.md lines 48-51; F1 §3; F2; P1:124). It does not repeat them. Those docs already cover Qwen3-VL's 2 fps default and lack of audio, Qwen3-Omni's audio+video input, and our measured result that Qwen3-VL-4B-4bit called real motion "not moving" on 2 of 2 probes.

Method: Hugging Face model API and raw model cards fetched with `curl` (createdAt, lastModified, downloads, license tag). GitHub API and raw source for mlx-vlm and llama.cpp. arXiv HTML for the Molmo2, Video-MME-v2 and Keye-VL-2.0 papers. One vendor benchmark PNG (MiniCPM-V 4.7), read as an image. Nothing was installed, run or uploaded, so **no number below is our own model measurement** unless labelled MEASURED. Where this file says MEASURED, it means a fact retrieved by a command (for example a `curl` of the HF API or a grep of source). It does not mean we ran inference.

Caveat on dates: HF `createdAt` is when the repo was created. A repo can be created privately before the model's public release.

---

## 1. Narrative (what changed since our 2026-10-23 report)

1. **The open default moved from Qwen3-VL to Qwen3.5 / 3.6 / 3.8.** All of these are natively multimodal, image plus video, under Apache-2.0. Qwen3.5 shipped 2026-02 (0.8B–397B), Qwen3.6 2026-04 (27B and 35B-A3B), Qwen3.8-27B 2026-08 (MEASURED, HF API). On its own card, Qwen3.6-27B claims Video-MME 87.7 with subtitles and MLVU 86.6. That is within about 1 point of Gemini-3-Pro (88.4 with subtitles) on the same vendor table (DOCUMENTED). The 2025 local default, Qwen3-VL-8B, claims 71.4 without subtitles. None of these models takes audio.
2. **Vendor numbers are inflated relative to third-party runs, by a lot.** On Video-MME without subtitles, Qwen's own card puts Qwen3.6-35B-A3B at 82.5. OpenBMB's "local evaluation using official checkpoints" (instruct mode) gives 75.7, and Qwen3.6-27B 70.2 (DOCUMENTED, MiniCPM-V 4.7 chart). Video-MME-v2 is the benchmark authors' own run, with consistency-grouped questions. There the best open model, Qwen3.5-397B-Think at 512 frames, scores 39.1 non-linear against **90.7 for human experts** and 49.4 for Gemini-3-Pro. The best laptop-scale model, Qwen3.5-27B-Think at 512 frames, scores 31.4 (DOCUMENTED, arXiv 2604.05015 Table 1). Treat every model-card Video-MME score as an upper bound.
3. **Audio+video in one open model is now a real option, but only at about 30B-A3B or larger.** Qwen3-Omni-30B-A3B (2025-09) and NVIDIA Nemotron-3-Nano-Omni-30B-A3B (2026-04) both take a video together with its audio track. Both have MLX code paths in mlx-vlm: `use_audio_in_video` for Qwen3-Omni, `--audio` for Nano Omni (DOCUMENTED from source). MiniCPM-o 4.5 (9B, 2026-02) does full-duplex streaming audio+video. Gemma 4 E2B/E4B/12B take audio, but only up to **30 s**, and video up to **60 s at 1 fps** (DOCUMENTED, Gemma 4 card §7). At 310B-A15B, MiMo-V2.5 (MIT) is the strongest open omni model on Video-MME (87.7, self-reported). It needs about 160+ GB even at 4-bit (ESTIMATED: 310B × 0.5 bytes), so on a Mac it is Mac Studio territory.
4. **Spatial and motion grounding has one standout: Molmo2.** Ai2's Molmo2-4B/8B (Apache-2.0, 2025-12) outputs **points and tracks in video**. In the vendor paper it scores 56.2 J&F on Molmo2-Track against Gemini 3 Pro 44.6 and Qwen3-VL-8B 28.7, and 60.8 against 44.0 on BURST video counting (DOCUMENTED, arXiv 2601.10611 Tables 3 and 5). It is the only open VLM here that emits machine-readable coordinates over time, which an agent can verify. Keye-VL-2.0-30B-A3B (2026-05) claims the best open **temporal grounding**: Charades-TimeLens 58.4 mIoU against Qwen3.5-35B-A3B 49.1 and Gemini 3 Flash 61.19 (DOCUMENTED, vendor report). None of this has been independently replicated, and nothing here addresses our measured "not moving" failure, which concerns motion perception rather than grounding.
5. **Local runtimes caught up.** mlx-vlm v0.7.10 (2026-10-21, 5,652 stars) passes video natively to models whose processor has a `video_processor`. For all other models it **silently falls back to 16 evenly spaced stills at 2 fps** (`mlx_vlm/generate/video.py`). Its docstring warns that without this check, generic HF processors "silently discard" video and "the model then hallucinates an answer with no visual input at all". llama.cpp merged model-agnostic video input on 2026-06-08 (PR #24269). It uses ffmpeg, handles images only (no audio track yet), and added `--video-fps` on 2026-08-27 (PR #24318) (MEASURED, GitHub API).
6. **Traps:** Kimi K2.5's open weights advertise video, but "Chat with video content is an experimental feature and is only supported in our official API for now". Kimi K3 is 2.8T parameters. Meta's Muse Glimmer-30B (Apache-2.0, 2026-08) "is not explicitly optimized for video; video input is processed as individual frames". Qwen3.5-Omni has **no** open weights under the Qwen org on HF (MEASURED: HF API search `author=Qwen&search=Omni` returns only Qwen3-Omni and Qwen2.5-Omni).
7. **For a Claude Opus 5.5 agent** (no native video or audio), these models act as a **local perception sub-model**. Claude calls an OpenAI-compatible localhost server (`mlx_vlm.server`, `llama-server`, vLLM) from a skill, CLI or MCP tool and gets text back: a description, timestamps, points, or a transcript plus events. Nothing leaves the machine after the weights are downloaded. The cost is accuracy. Every local model here sits well below Gemini on Video-MME-v2. Use them for privacy-bound triage and for indexing at timestamp granularity, then let Claude look at frames at 2000 px to verify.

---

## 2. Comparison table

Scores are vendor-reported unless marked. "w/o" means without subtitles. RAM figures are ESTIMATED as params × bits/8 plus about 15%, unless a source is cited.

| # | Model (date) | Params | Video in | Audio | License | Video-MME w/o (vendor) | LVBench | MLVU | Independent | MLX / llama.cpp / vLLM |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Qwen3.6-27B / 35B-A3B (2026-04) | 27B dense / 35B-A3B | native, fps=2 default; up to about 224K video tokens | no | Apache-2.0 | 35B-A3B 82.5 (OpenBMB eval 75.7); 27B 70.2 (OpenBMB eval only) | 35B-A3B 71.4 | 27B 86.6 / 35B-A3B 86.2 | V-MME-v2: Qwen3.5-27B-Think@512f 31.4 non-lin | mlx-community 4-bit yes; mlx-vlm `qwen3_5` native video; llama.cpp video frames; vLLM yes |
| 2 | Qwen3.5 0.8B–122B (2026-02) | 0.8/2/4/9/27/35-A3B/122-A10B/397-A17B | same | no | Apache-2.0 | 9B 78.4, 4B 76.9, 27B 82.8 | 9B 70.0, 27B 73.6 | 9B 84.4 | V-MME-v2 table (above) | same |
| 3 | Qwen3.8-27B (2026-08); 3.8-Flash-Next 125B-A6B | 27B | same | no | 27B Apache-2.0; Flash-Next **qwen-community-1.0** | not on card | 27B 72.4; Flash-Next 76.6 | n/a | OpenBMB eval: 73.4 | mlx-community 4-bit yes |
| 4 | Qwen3-Omni-30B-A3B (2025-09) | 30B-A3B | native, fps=2 at eval | **yes, audio in video** | Apache-2.0 | 70.5 | 50.2 | 75.2 | V-MME-v2 17.1 non-lin (64f) | mlx-community 4-bit; mlx-vlm `use_audio_in_video`; llama.cpp GGUF (audio+vision); vLLM |
| 5 | Nemotron-3-Nano-Omni-30B-A3B (2026-04) | 31B-A3B hybrid Mamba MoE | ≤2 min; 1 fps/128 f at 1080p, 2 fps/256 f at 720p | **yes**, up to 1 h; `use_audio_in_video` in vLLM | NVIDIA Open Model Agreement | 72.2 (press copy of vendor table) | n/a | n/a | none | mlx-vlm `nemotron_h_nano_omni`; mlx-community 4-bit; llama.cpp GGUF; vLLM |
| 6 | Molmo2-4B / 8B (2025-12) | 4B / 8B | 2 fps, up to 384 frames at 378 px | no | Apache-2.0 (data partly non-commercial) | 69.6 / 69.9 | 53.9 / 52.8 | 63.0 / 60.2 (test MCQ) | none | mlx-vlm `molmo2`; mlx-community 4-bit; vLLM example on card |
| 7 | Gemma 4 E2B/E4B/12B/26B-A4B/31B (2026-03 to 05) | 2.3B eff to 31B | frames, **≤60 s at 1 fps** | E2B/E4B/12B, **≤30 s** | Apache-2.0 | none on card; OpenBMB eval 31B 74.1 | n/a | n/a | OpenBMB eval only | llama.cpp official GGUF; mlx-vlm `gemma4` (README documents image and audio only) |
| 8 | MiniCPM-V 4.7 35B-A3B / 1B (2026-10) | 35B-A3B / 1B | 128 main frames; `stack_frames` 3–5 per second | no | Apache-2.0 | 76.4 (4x mode) | n/a | n/a | none | mlx-vlm `minicpmv4_7` (video); llama.cpp GGUF; Ollama; vLLM |
| 9 | MiniCPM-o 4.5 (2026-02) | 9B | up to 10 fps, streaming | **yes, full duplex** | Apache-2.0 | 70.4 | 50.9 | 76.5 | none | llama.cpp-omni / Ollama; mlx-vlm `minicpmo` |
| 10 | Keye-VL-2.0-30B-A3B (2026-05) | 30B-A3B, DSA sparse attention | fps=2 default, 256K context | not stated | Apache-2.0 | 78.3 | n/a | 82.8 | none | official GGUF; no mlx-community; SGLang |
| 11 | MiMo-V2.5 (2026-04) | 310B-A15B | native | **yes** | MIT | 87.7 (self-reported, llm-stats) | n/a | n/a | V-MME-v2: MiMo-v2-Omni +8.7 with audio | SGLang; too large for most Macs |
| 12 | Cosmos-Reason2 2B/8B/32B (2025-12, updated 2026-03) | Qwen3-VL-8B base | 4 fps recommended, 256K | no | NVIDIA Open Model License | n/a | n/a | n/a | none | Transformers; community GGUF |
| 13 | Nemotron 3.5 Super VL 120B-A12B / Bolt 74B-A9B (2026-10) | 120B-A12B / 74B-A9B | ≤2 min, 2 fps/256 f | no | OpenMDW-1.1 | Video-MME-v2 32.85 (Super, vendor) | n/a | n/a | none | mlx-vlm (4-bit Super about 43 GB, <47 GB peak on M5 Max); Bolt 24 GB GGUF |
| 14 | Qwen3-VL 2B–235B (2025-09/10) | 2B–235B | fps=2 | no | Apache-2.0 | 8B 71.4 | 8B 58.0 | 8B 57.6 (test MCQ) | **our MEASURED motion failure**; V-MME-v2 8B 18.2 | full |
| 15 | GLM-4.6V / 4.6V-Flash 9B (2025-12); GLM-4.5V; GLM-4.1V-Thinking | 106B-A12B / 9B | video supported | no | MIT | in image only | | | V-MME-v2: GLM4.5V-Think 21.8; 4.6-Flash 19.8; 4.1V 14.0 | mlx-vlm `glm4v`; mlx-community 4.6V-Flash 4-bit |
| 16 | InternVL3.5 / InternVideo2.5 / VideoChat-Flash (2025) | 1B–241B / 8B / 2–7B | VideoChat-Flash ≤10,000 frames at 16 tok/frame | no | Apache-2.0 | 3.5-8B 66.0; IV2.5 65.1; VC-Flash 65.3 | | 3.5-8B 70.2; IV2.5 72.8; VCF 74.7 | V-MME-v2 3.5-8B 16.4 | **stale (>6 mo)**; llama.cpp InternVL3; few MLX builds |
| 17 | Kimi K2.5 (1T-A32B) / K3 (2.8T-A104B) / Kimi-VL-A3B | huge / 16B-A3B | K2.5 video **API-only** | no | modified-MIT / kimi-k3 / MIT | K2.5 83.2; K3 90.0 (with subtitles) | K2.5 75.9 | K2.5 85.0 | V-MME-v2: K2.5 36.1 (commercial table), KimiVL 19.0 | not local in practice |
| 18 | Eagle 2.5-8B / PerceptionLM-8B / VideoLLaMA3 / LLaVA-Video / SmolVLM2 / Video-XL-2 (2024-25) | 0.25B–8B | 32–512 frames | no | NSCLv1 / FAIR-NC / Apache | Eagle 72.4; PLM 58.3; LLaVA-Video-7B 63.3; SmolVLM2-2.2B 52.1 | Eagle 66.4 | Eagle 77.6 | V-MME-v2: VideoLLaMA3 14.2, LLaVA-Video-7B 9.7 | **stale**; SmolVLM2 has llama.cpp GGUF and MLX |
| R1 | **mlx-vlm** v0.7.10 (2026-10-21) | runtime | native, or 16-still fallback | omni models | MIT | | | | | Apple Silicon |
| R2 | **llama.cpp mtmd video** (2026-06-08 / 08-27) | runtime | ffmpeg frames plus timestamps | not from video yet | MIT | | | | | Mac/CPU/GPU |

---

## 3. Entries (ranked by importance to an agent builder)

### 1. Qwen3.6-27B / Qwen3.6-35B-A3B (Alibaba Qwen), with the Qwen3.5 small sizes
- **What it gives an agent:** a local video Q&A and captioning sub-model with timestamps that runs on a 32–64 GB Mac. It takes the whole clip natively, not stills. Thinking mode is on by default and can be switched off per request. It also has tool calling and agentic GUI skills (OSWorld etc. on the card).
- **Modality path:** native video into the model. fps=2 by default (`do_sample_frames=True`, `fps` adjustable). For hour-scale video the card recommends raising `longest_edge` to 469,762,048, which is about **224K video tokens**. Context is 262,144 natively, extensible to 1M. **No audio.**
- **Params / license:** 27B dense; 35B total with 3B active. Apache-2.0 (MEASURED, HF license tag). Qwen3.5 sizes: 0.8B, 2B, 4B, 9B, 27B, 35B-A3B, 122B-A10B, 397B-A17B, all created 2026-02-16 to 02-28 (MEASURED, HF API).
- **Scores (vendor, from the cards fetched 2026-10-24):**
  - Qwen3.6-27B: VideoMME with subtitles 87.7, VideoMMMU 84.4, MLVU 86.6, MVBench 75.5.
  - Qwen3.6-35B-A3B: 86.6 with subtitles / 82.5 without, VideoMMMU 83.7, MLVU 86.2, MVBench 74.6, LVBench 71.4.
  - Qwen3.5-27B: 87.0 / 82.8, LVBench 73.6, MLVU 85.9.
  - Qwen3.5-9B: 84.5 / 78.4, LVBench 70.0, MLVU 84.4.
  - Qwen3.5-4B: 83.5 / 76.9, LVBench 66.4.
- **Third-party evidence:**
  - OpenBMB's chart (2026-10, a competitor, instruct mode) gives Video-MME without subtitles as 75.70 for 35B-A3B and 70.20 for 27B. That is 7–12 points under the Qwen cards.
  - Video-MME-v2 (arXiv 2604.05015, benchmark authors) gives non-linear scores with subtitles / without: Qwen3.5-27B-Think at 512 frames 31.4 / 19.5; Qwen3.5-9B-Think at 512 frames 26.2 / 19.5; Qwen3.5-35B-A3B-Think at 64 frames 25.8 / 15.6. Human experts score 90.7.
- **Runtimes:** mlx-community has 21–30 conversions per model, including `mlx-community/Qwen3.6-27B-4bit` and `Qwen3.6-35B-A3B-4bit` (MEASURED, HF API). mlx-vlm `qwen3_5` "reuses the Qwen3-VL processor … image, video". vLLM and SGLang serve it with `--media-io-kwargs '{"video":{"num_frames":-1}}'` so that fps can be set. llama.cpp video works through ffmpeg frames.
- **RAM (ESTIMATED):** 27B at 4-bit is about 16 GB. 35B-A3B at 4-bit is about 20 GB. 9B at 4-bit is about 6 GB.
- **Claude fit:** run `mlx_vlm.server` on localhost and call it from a skill or MCP tool such as `video_ask(path, question, fps, range)` that returns text with timestamps. Fully local, no egress.
- **Label:** DOCUMENTED (scores), MEASURED (HF metadata retrieval).

### 2. Qwen3.8-27B and Qwen3.8-Flash-Next (Alibaba Qwen)
- **What it gives an agent:** the newest open Qwen (2026-08-05). It has the strongest agentic and multimodal numbers at 27B: OSWorld-Verified 84.3 and ERQA 65.5. Video support is the same native fps=2 path.
- **Video evidence:**
  - The card publishes **no Video-MME or MLVU**. The only video row is Flash-Next's table, with LVBench 72.4 for 27B and 76.6 for Flash-Next.
  - OpenBMB's chart gives Video-MME without subtitles 73.40, LongVideoBench 60.90 and MotionBench 65.11 for Qwen3.8-27B. On MotionBench that is *below* Qwen3.6-27B (69.11).
- **License trap:** Qwen3.8-27B is Apache-2.0. Qwen3.8-Flash-Next (125B with 6B active, plus a 51B n-gram embedding) is **`qwen-community-1.0`**, not Apache (MEASURED, card front-matter).
- **Runtimes:** 25 mlx-community conversions (MEASURED); vLLM, SGLang.
- **Label:** DOCUMENTED.

### 3. Qwen3-Omni-30B-A3B-Instruct / Thinking / Captioner (Alibaba Qwen)
- **What it gives an agent:** the best-supported open model that **hears the video's audio track while watching**. It handles audio-visual QA, sound-event captioning (the Captioner variant), and "video scene transition" analysis.
- **Path:** native video plus audio (`use_audio_in_video=True`); videos are evaluated at fps=2.
- **License:** front-matter says `license: other` with `license_name: apache-2.0` (MEASURED).
- **Scores (vendor):**
  - Instruct: Video-MME 70.5, LVBench 50.2, MLVU 75.2, WorldSense 54.0.
  - Thinking: DailyOmni 75.8, VideoHolmes 57.3.
  - Independent: Video-MME-v2 non-linear 17.1 / 10.9 for Instruct at 64 frames, and 19.5 / 12.6 for Thinking.
- **Memory (vendor, BF16, CUDA):** 78.85 GB for a 15 s video and 144.81 GB for 120 s. At BF16 this does not fit a laptop.
- **MLX:** `mlx-community/Qwen3-Omni-30B-A3B-Instruct-4bit` exists (5 conversions). mlx-vlm's `qwen3_omni_moe` processor implements `use_audio_in_video`, **default False** (MEASURED, grep of `processing_qwen3_omni_moe.py:94`).
- **llama.cpp:** official GGUF, "audio input, vision input".
- **Maturity:** stale by the 6-month rule (2025-09) and still the open reference. No Qwen3.5-Omni weights exist (see not-found).
- **Label:** DOCUMENTED. Untested by us; RAM at 4-bit with long video is unknown.

### 4. NVIDIA Nemotron-3-Nano-Omni-30B-A3B-Reasoning
- **What it gives an agent:** audio, video, image and text in one model. NVIDIA positions it for "video+speech analysis … dense captions, video search and summarization".
- **Limits (card):**
  - Video: mp4 **up to 2 minutes**. At 1080p, sample up to 1 FPS / 128 frames; at 720p, 2 FPS / 256 frames.
  - Audio: wav/mp3 **up to 1 hour**.
  - vLLM uses `use_audio_in_video: true` and EVS pruning (`--video-pruning-rate 0.5`).
- **Params / license:** 31B Mamba2-Transformer hybrid MoE with about 3B active; C-RADIOv4-H vision encoder and Parakeet speech encoder. NVIDIA Open Model Agreement.
- **Dates and adoption:** released 2026-04-28 (NVIDIA blog). BF16 repo has 199,092 downloads (MEASURED).
- **Scores:** Video-MME 72.2 against Qwen3-Omni 70.5; WorldSense 55.4; DailyOmni 74.1. These come only from a secondary article reproducing NVIDIA's launch table; NVIDIA's blog gives no numbers in its text.
- **MLX:** mlx-vlm `nemotron_h_nano_omni`: `--video clip.mp4 --fps 2` plus `--audio`. Warning: "the checkpoint's default pruning rate of 0.7 can retain only the first frame pair" on very short clips, so use `video_pruning_rate=0`. mlx-community has a 4-bit build. llama.cpp GGUF is listed by NVIDIA.
- **Label:** DOCUMENTED (vendor). Scores are secondary-sourced.

### 5. Molmo2-4B / 8B / O-7B, Molmo2-VideoPoint-4B (Ai2)
- **What it gives an agent:** **pointing, counting and tracking in video**, with outputs of frame index plus x,y scaled to 1000. Claude can parse, plot and cross-check these against frames it views at 2000 px. This is the strongest open answer to "where and when did X move".
- **Path:** native video. `max_fps` 2.0, `num_frames` 384, 378×378 frames, 3×3 pooling (MEASURED, `video_preprocessor_config.json`). The card says tracking is "best with max_fps=8". No audio.
- **Backbone / license:** Qwen3-8B or Qwen3-4B with SigLIP. Apache-2.0, but "trained on third party datasets … academic and non-commercial research use only. Please review".
- **Scores (vendor paper, Table 2):**
  - 8B: Video-MME 69.9 (75.8 with subtitles), MLVU 60.2, LVBench 52.8, MVBench 75.9.
  - Tracking (Table 5): J&F 56.2 against Gemini 3 Pro 44.6 and Qwen3-VL-8B 28.7.
  - Counting (Table 3): BURST-VC 60.8 against 44.0 for Gemini 3 Pro.
  - Card summary: 15-benchmark average 63.1 against Claude Sonnet 4.5 59.6.
  - Caution: the paper's abstract quotes "56.2 vs 41.1 J&F". The table extraction we read puts Gemini at 44.6, so the abstract comparison may not match the tables (WebFetch summary, low confidence).
- **Related, out of scope:** MolmoMotion-4B (2026-06) forecasts 3D point trajectories for robotics and is not a perception tool.
- **Runtimes:** mlx-vlm `molmo2` and `molmo_point`; `mlx-community/Molmo2-8B-4bit`.
- **Label:** DOCUMENTED. Spatial and temporal claims are vendor-only; no independent replication was found.

### 6. Gemma 4 family (Google DeepMind)
- **What it gives an agent:** short-clip understanding plus speech with very wide runtime support: official llama.cpp GGUFs and the largest MLX ecosystem.
- **Limits (card §7):** "Video supports a maximum of **60 seconds** assuming the images are processed at **one frame per second**." Audio is E2B/E4B/12B only, "maximum length of **30 seconds**".
- **Sizes:** E2B (2.3B effective), E4B (4.5B effective), 12B "Unified" (any-to-any, 2026-05-23), 26B-A4B, 31B (2026-03-11). Context is 128K or 256K. Apache-2.0. The 31B has 8.5M downloads (MEASURED).
- **Scores:** no video benchmarks on the cards.
  - OpenBMB eval: Gemma-4-31B Video-MME without subtitles 74.10, LongVideoBench 60.70, MotionBench 62.67.
  - Qwen3.6 card: VideoMMMU 81.6 for 31B and 76.0 for 26B-A4B.
- **MLX:** mlx-vlm `gemma4` README documents image and audio only, not video. Video on MLX is therefore likely the 16-still fallback (INFERRED). llama.cpp lists Gemma 4 under both vision and audio.
- **Label:** DOCUMENTED.

### 7. MiniCPM-V 4.7 (35B-A3B, 1B), MiniCPM-V 4.5 (8B) (OpenBMB)
- **What it gives an agent:** a high-frame-rate, efficient video model that runs on devices.
  - 4.7's `stack_frames` composites N−1 sub-frames per second into a grid next to each main frame, so 3–5 samples per second carry motion cues. `max_num_frames` defaults to 128; `downsample_mode` is 4x or 16x.
  - 4.5's 3D-Resampler packs 6 frames into 64 tokens ("96x compression"). Its card advertises "High-FPS Video".
- **Scores (vendor chart, PNG, 2026-10):** 4.7 35B-A3B Video-MME without subtitles 76.40 (4x) / 74.70 (16x), LongVideoBench 68.90, MotionBench 68.12. The chart claims a higher overall score than Qwen3.6-35B-A3B in less inference time.
- **Dates:** 4.7 repos created 2026-10-06/07; the 35B-A3B has 152K downloads in about 2 weeks (MEASURED).
- **Runtimes:** mlx-vlm `minicpmv4_7` ("supports text, images, multiple images, video", with no PyTorch needed; example `--video … --fps 1 --processor-kwargs '{"max_num_frames": 32}'`). BF16 needs about 71 GB, so convert to 4-bit. Also official GGUF, Ollama, vLLM, SGLang.
- **License:** Apache-2.0.
- **Label:** DOCUMENTED.

### 8. MiniCPM-o 4.5 (OpenBMB)
- **What it gives an agent:** a 9B end-to-end model (SigLIP2 + Whisper-medium + CosyVoice2 + Qwen3-8B) that takes **continuous video and audio streams at the same time** and can speak back. It decides "at a frequency of 1Hz to speak or not". Video up to 10 fps.
- **Scores (vendor):** Video-MME without subtitles 70.4, LVBench 50.9, MLVU 76.5, LongVideoBench 66.0, MotionBench 61.4 (Qwen3-Omni on the same table: 61.7).
- **Dates:** repo created 2026-02-03 and updated 2026-10-16; 397K downloads (MEASURED).
- **Runtimes:** llama.cpp-omni fork, Ollama, vLLM, SGLang; mlx-vlm `minicpmo` (audio output example in the README). Apache-2.0.
- **Agent use:** live-screen or webcam watching. It is less useful for batch QA over a recording than Qwen3-Omni.
- **Label:** DOCUMENTED.

### 9. Keye-VL-2.0-30B-A3B (Kuaishou Kwai-Keye)
- **What it gives an agent:** long-video and **temporal-localization** specialist ("when does X happen").
- **Scores (vendor report, arXiv 2606.10651):**
  - TimeLens mIoU: Charades 58.4, ActivityNet 58.5, QVHighlights 70.1. Qwen3.5-35B-A3B scores 49.1 / 53.2 / 65.7 when re-evaluated at 4 fps.
  - Video-MME without subtitles 78.3 (Qwen3.5-35B-A3B 82.5), MLVU 82.8, LongVideoBench 74.1.
  - Video-MME-v2 accuracy 35.3 at 64 frames rising to 42.4 at 512.
- **Architecture:** DSA sparse attention with 256K context; fps=2 default; `video_total_pixels` budget.
- **License / runtimes:** Apache-2.0. Official GGUF (2026-06-18), SGLang. **No mlx-community conversion** (MEASURED), and the DSA support status in MLX and llama.cpp is unverified.
- **Related:** VideoTemp-o3 (2026-05, MIT) is an "agentic thinking-with-videos" model that grounds a segment, then refines it.
- **Label:** DOCUMENTED.

### 10. Xiaomi MiMo-V2.5 (and V2.5-Pro)
- **What it gives an agent:** the strongest open omni model (text, image, video, audio) on Video-MME: 0.877, rank 4 overall on llm-stats, self-reported (fetched 2026-10-24).
- **Params / license:** 310B total with 15B active; Pro is 1.02T with 42B active. 729M ViT and 261M audio encoder. MIT.
- **Dates / adoption:** repo created 2026-04-27; 144K downloads (MEASURED).
- **Independent signal:** Video-MME-v2 notes the earlier MiMo-v2-Omni gains +8.7 non-linear when given audio.
- **Fit:** SGLang serving on GPU. On a Mac it would need about 175 GB at 4-bit (ESTIMATED), so only a 192 GB+ or 512 GB Mac Studio. Not laptop-local.
- **Related:** MiMo-V2.6-Distill-Qwen-9B (2026-09) exists, but its card gives no video detail.
- **Label:** DOCUMENTED.

### 11. NVIDIA Cosmos-Reason2 (2B / 8B / 32B)
- **What it gives an agent:** physical-world and embodied video reasoning: "spatio-temporal understanding and timestamp precision", 2D/3D point and bounding-box localization. It "recognizes timestamps added at the bottom of each frame".
- **Base / input:** Qwen3-VL-8B; 4 fps recommended; 256K context.
- **Scores (vendor):** Self-Driving 67.85 against 46.38 for base Qwen3-VL-8B; VideoPhy2 36.80 against 28.24.
- **License / runtimes:** NVIDIA Open Model License. Transformers on Hopper/Blackwell; community GGUF only. 2B: 578K downloads; 32B created 2026-04-29 (MEASURED).
- **Fit:** CCTV, robotics and dashcam-style questions, not meetings.
- **Label:** DOCUMENTED.

### 12. NVIDIA Nemotron 3.5 Super VL 120B-A12B / Bolt 74B-A9B (2026-10)
- **What it gives an agent:** large, brand-new VL models with video (mp4 ≤2 min, 2 fps/256 frames, EVS pruning).
- **Scores:** vendor Video-MME-v2 32.85 for Super.
- **Mac fit:** the mlx-vlm README reports Super VL at 4-bit is "approximately 43.1 GB on disk … less than 47 GB peak MLX memory on an M5 Max" for short video. Bolt ships a native 2-bit "24GB" GGUF.
- **Limits:** no audio encoder ("Super VL and Bolt have no audio encoder"). Bolt was trained on an "image-only blend", so video is inherited at best (INFERRED).
- **License:** OpenMDW-1.1.
- **Label:** DOCUMENTED. Under 3 weeks old.

### 13. Qwen3-VL 2B–235B (Alibaba Qwen) [our baseline]
- **What it gives an agent:** still the most widely integrated open video VLM. Qwen3-VL-8B has 4.79M downloads (MEASURED), and Cosmos-Reason2, Molmo2-era comparisons and many wrappers build on it.
- **Path:** fps=2, 256–16,384 visual tokens per video, text-timestamp alignment, no audio.
- **Scores:**
  - Vendor (Molmo2 paper table): Qwen3-VL-8B Video-MME 71.4, LVBench 58.0.
  - Independent: Video-MME-v2 non-linear 18.2 for 8B and 17.6 for 4B.
  - Ours: Qwen3-VL-4B-4bit on mlx-vlm 0.6.7 called a moving mark "not moving" on 2 of 2 probes, and one 9,732-token clip produced an empty generation (MEASURED earlier, `docs/research/agent-video-understanding-2026-07-26.md:223-242`).
- **Status:** superseded by Qwen3.5+ on every vendor benchmark.
- **Label:** MEASURED (prior run) / DOCUMENTED.

### 14. GLM-4.6V / GLM-4.6V-Flash 9B / GLM-4.5V / GLM-4.1V-9B-Thinking (Z.ai)
- **What it gives an agent:** MIT-licensed VLMs with "native multimodal function calling" and video ("long video segmentation and event recognition", GLM-V README). 4.6V is 106B-A12B; 4.6V-Flash is 9B with 128K context. Released 2025-12-07 (MEASURED), so stale by the 6-month rule.
- **Independent scores (Video-MME-v2 non-linear, with / without subtitles):** GLM4.5V-Think 21.8 / 13.3; GLM4.6-Flash 19.8 / 12.7; GLM4.1V-Think 14.0 / 9.4.
- **Newer GLM:** GLM-5.3-Flash (2026-08, 320B-A18B, "first natively multimodal" GLM-5) has no video mention on its card (grep count 0).
- **Runtimes:** mlx-vlm `glm4v`; `mlx-community/GLM-4.6V-Flash-4bit`.
- **Label:** DOCUMENTED.

### 15. InternVL3.5 / InternVideo2.5 / VideoChat-Flash (Shanghai AI Lab / OpenGVLab)
- **What it gives an agent:** research-grade long-video models. VideoChat-Flash uses 16 tokens per frame and accepts up to 10,000 frames (50,000 for the 1M variant). InternVideo2.5 adds dense-vision "long and rich context" modelling.
- **Scores (vendor):** InternVL3.5-8B Video-MME 66.0 / MLVU 70.2; InternVL3.5-241B 72.9 / 78.2; InternVideo2.5-8B 65.1 / MLVU 72.8; VideoChat-Flash-7B@448 65.3 / MLVU 74.7.
- **Independent:** Video-MME-v2 non-linear 16.4 for InternVL3.5-8B and 23.1 for 241B.
- **Freshness:** **stale.** The newest InternVL is 2025-09-28; no InternVL4 exists on HF (MEASURED). Lab activity has moved to Intern-S2 (2026-05 to 09, 397B and "Mobius"), whose cards do not describe video.
- **Runtimes:** llama.cpp supports InternVL3 GGUF; few MLX builds (3, MEASURED). Apache-2.0 (InternVideo2 partly MIT).
- **Label:** DOCUMENTED.

### 16. Kimi K2.5 / K2.6 / K3 and Kimi-VL-A3B (Moonshot)
- **What it gives an agent:** frontier-class open-weight multimodal models that cannot run on a laptop.
  - K2.5: 1T total / 32B active. Qwen3.5 card: Video-MME 87.4 with subtitles / 83.2 without, LVBench 75.9.
  - K3: 2.8T total / 104B active, 1M context. Card: Video-MME with subtitles 90.0.
- **Trap:** the K2.5 card says "Chat with video content is an experimental feature and is only supported in our official API for now". So the open weights do not give you a supported local video path.
- **Kimi-VL-A3B-Thinking-2506:** 16B-A3B, MIT, 2025-06, stale. Video-MME 71.9 with subtitles (vendor); independent Video-MME-v2 non-linear 19.0. Thinking *hurt* it by 3.3 (paper).
- **License:** modified-MIT (K2.5); `kimi-k3` licence.
- **Label:** DOCUMENTED.

### 17. Legacy and research-licensed video LLMs: Eagle 2.5-8B, PerceptionLM-8B, VideoLLaMA3, LLaVA-Video, LLaVA-OneVision-1.5, SmolVLM2, Video-XL-2
- **Eagle 2.5-8B (NVIDIA, 2025-04):**
  - Up to 512 frames at 128K context.
  - Video-MME 72.4 / 75.7, MLVU 77.6, LVBench 66.4, HourVideo 44.5.
  - **NSCLv1: non-commercial research only.**
- **PerceptionLM-8B (Meta FAIR, 2025-04):**
  - Video-MME 58.3, PerceptionTest 82.7, Charades-STA 58.6, TOMATO 33.2, MotionBench 61.4.
  - **FAIR Noncommercial license.**
- **VideoLLaMA3-7B (2025-01):** fps 1, `max_frames` 128; Video-MME-v2 non-linear 14.2.
- **LLaVA-Video-7B (2024-09):**
  - "at most 64 frames"; Video-MME 63.3, MLVU 70.8.
  - Video-MME-v2 non-linear 9.7.
- **LLaVA-OneVision-1.5 (2025-09):** the card describes image training only (a $16K training run).
- **SmolVLM2 2.2B / 500M / 256M (2025-02):**
  - Video-MME 52.1 / 42.2 / 33.7, Apache-2.0.
  - Official llama.cpp GGUF and MLX builds; the 500M model has 1.44M downloads (MEASURED).
  - The only option for edge or phone, but weak.
- **Video-XL-2 (BAAI, 2025-05):** up to 1,300 frames, but pinned to `torch==2.1.2 … cu121`, which makes it impractical on a Mac.
- **Status:** all are **stale (>6 months)**.
- **Label:** DOCUMENTED.

### R1. mlx-vlm (Prince Canuma / Blaizzy), the Apple Silicon runtime
- **What it gives an agent:** `mlx_vlm.generate --video --fps` and an OpenAI-compatible `mlx_vlm.server` with image, audio and video, plus `/v1/audio/transcriptions`.
- **Model dirs (MEASURED):** qwen3_5, qwen3_5_moe, qwen3_vl, qwen3_omni_moe, molmo2, gemma4, gemma3n, minicpmv4_7, minicpmo, nemotron_h_nano_omni, glm4v, internvl_chat, llava_onevision, smolvlm, kimi_vl, kimi_k25, muse_glimmer and more.
- **Video fallback trap:** native video applies only when the processor has a `video_processor`. Otherwise it falls back to `max_frames=16` stills at fps 2.0, sampled across the whole request (`generate/video.py:79-108`).
- **Activity:** v0.7.10 released 2026-10-21; releases v0.7.6 to v0.7.10 all in October 2026; 5,652 stars; last push 2026-10-23 (MEASURED, GitHub API). MIT.
- **Label:** MEASURED (repo facts) / DOCUMENTED (behaviour, read from source).

### R2. llama.cpp libmtmd video input (ggml-org)
- **What it gives an agent:** `llama-server` `/chat/completions` and `llama-mtmd-cli` accept a video file. ffmpeg (not bundled) extracts frames, which are interleaved with text timestamps.
- **History:** PR #24269 merged 2026-06-08; `--video-fps`, `--video-timestamp-interval` and `--video-ffmpeg-dir` arrived in PR #24318, merged 2026-08-27.
- **Limits:** "No audio for now" from the video file. Model-agnostic prompt format; Qwen-VL 3D-conv frame merging comes from PR #21858 (MEASURED, GitHub API PR bodies).
- **Model list:** the docs list Gemma 4, Qwen2/2.5-VL, InternVL3 and SmolVLM2 vision GGUFs, and Qwen3-Omni and Gemma 4 E2B/E4B as audio+vision.
- **Fit:** Metal on Mac; one binary that Claude can shell out to.
- **Label:** MEASURED / DOCUMENTED.

---

## 4. What this means for a Claude Opus 5.5 agent (INFERRED)

- **Best local all-rounder (no audio):** Qwen3.6-35B-A3B or 27B at 4-bit on mlx-vlm. Pin `fps` and raise the video token budget for long clips. Expect third-party accuracy about 7–12 points below the card.
- **Need the audio track in the same pass:** Qwen3-Omni-30B-A3B (mlx-vlm `use_audio_in_video=True`) or Nemotron-3-Nano-Omni (≤2 min video). Both are untested by us, so measure RAM on a 60 s clip first.
- **Need *where* or *how many* over time:** Molmo2-8B points and tracks. Have Claude verify sample points on 2000 px frames.
- **Need *when*:** Keye-VL-2.0 (vendor TimeLens lead). Not on MLX yet.
- **Motion "feel" (easing, choreography, editing rhythm):** no open VLM here offers independent evidence of closing the gap. Video-MME-v2's best open model scores 39.1 against 90.7 for humans. Keep optical-flow and slit-scan probes as the measuring instrument.
- **Integration shape:** a skill that starts `mlx_vlm.server` with one pinned model. An MCP or CLI tool takes `(path, t0, t1, fps, question)` and returns JSON with timestamps or points. Claude does the reasoning and the 2000 px verification. Everything stays local; the only egress is the one-time weight download from HF.

## 5. Not found / dead / caveats

- **Qwen3.5-Omni open weights:** none under `Qwen/` on HF (MEASURED, API search 2026-10-24). Plus and Flash are API-only; a "Light" open variant is rumoured in blogs but unverified.
- **Apollo (Meta, Dec 2024):** the original `Apollo-LMMs` checkpoints are not present. The org now holds only two unrelated 2025-08 repos (MEASURED). Treat as withdrawn.
- **InternVL4:** no such repo (MEASURED).
- **Kimi K2.5 local video:** the API is the only supported path.
- **Muse Glimmer-30B (Meta, 2026-08, Apache-2.0):** "not explicitly optimized for video; video input is processed as individual frames"; "Audio input/output is not supported".
- **GLM-5.3-Flash:** natively multimodal, but its card has no video claims.
- **LLaVA-OneVision-1.5:** the card describes no video capability.
- **Cosmos-Reason2, Eagle 2.5 and PerceptionLM** are gated on HF. Their details were read through WebFetch summaries of the HF pages, which is lower fidelity.
- **Nemotron-3-Nano-Omni scores** come from a secondary article, not a primary NVIDIA table.
