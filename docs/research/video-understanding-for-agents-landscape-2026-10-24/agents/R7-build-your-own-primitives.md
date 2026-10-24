# R7: Build-your-own primitives for an agent video pipeline (2026-10-24)

Axis: the open-source stack you assemble yourself, local first, so that Claude Opus 5.5 in Claude Code can "watch" a video.
Claude has no video or audio input, so each primitive below turns one channel into text, numbers or a small set of images.
Ranked by value to that pipeline. Apple Silicon viability and license are given for each.

**What this extends.** The 2026-10-23 probe (`../../video-understanding-human-parity-2026-10-23/`) already measured
these: whisper.cpp large-v3-turbo, FluidAudio Parakeet TDT v3 and community-1 diarization, Apple Vision OCR, ffmpeg
scene cuts, and opencv motion probes (P1:40-50, P1:63-68, P1:101-104, P2:126-177, E1:27, E3:138). This file does not
repeat those numbers except as baselines. What it adds is the 2026 release state of every primitive class in the brief,
the new entrants found (NeMo-Speech.cpp, Nemotron 3.5 ASR, OmniShotCut, SAM 3.1, PE-A-Frame, PP-OCRv6, Surya's VLM
rewrite, torchcodec 0.17, pyannote Precision-3 pricing), and which of them actually run on this Mac.

**Method and labels.** GitHub metadata comes from `gh api repos/<r>` and `gh api "repos/<r>/releases?per_page=1"`, run
2026-10-24 (MEASURED; star counts are a snapshot). Model-card facts come from `huggingface.co/api/models/<id>` and the
raw `README.md` (DOCUMENTED). Local availability comes from `command -v`, `brew list --versions` and `python3 -c import`
(MEASURED). Nothing was installed, uploaded or signed up for.

**This machine** (MEASURED, `sysctl machdep.cpu.brand_string`, `brew list --versions`):
- Apple M1 Max.
- On PATH: `whisper-cli` (whisper.cpp **1.9.2**, latest is 1.9.5), `fluidaudiocli`, ffmpeg **9.0.1**, yt-dlp 2026.7.4.
- `python3 -c "import cv2"` gives 4.13.0. Under `python3 -I` only torch 2.4.1 imports.
- Absent: transformers, mlx, mlx-vlm, mlx-audio, PySceneDetect, PyAV, torchcodec, decord, faster-whisper, WhisperX,
  pyannote, ultralytics, supervision, PaddleOCR, Surya, docTR, `nemo-speech`.

---

## Narrative

1. **Speech is still the richest channel, and in October 2026 the strongest local speech primitives are NVIDIA models
   running through Apple-native or ggml runtimes, not Whisper.**
   - Whisper large-v3 sits at about 7.4% average WER on the Open ASR Leaderboard and Parakeet TDT 0.6B v3 at about 6.3%.
     The top of the board (Cohere Transcribe, Granite Speech 4.1, Canary-Qwen 2.5B) is about 5.3-5.6%. These figures are
     secondary, from openwhispr.com. The live results dataset is gated (`hf-audio/open-asr-leaderboard-results` returned
     "Invalid username or password").
   - Our own meeting measurements agree with that order: Parakeet TDT v3 20.8% WER, best Whisper setting 24.5%, and
     Parakeet hallucinated nothing over digital silence (P1:42-44).
   - Two runtimes now package Parakeet with diarization behind one local CLI on a Mac:
     - **FluidAudio** (CoreML on the Neural Engine) is already installed here.
     - **NVIDIA NeMo-Speech.cpp** is new (created 2026-07-15, v0.2.0 on 2026-10-02, Metal backend). It runs
       `nemo-speech transcribe x.wav --diarize --json`.

2. **Diarization moved in September 2026.**
   - NVIDIA Nemotron 3 Diarization (2026-09-23, OpenMDW-1.1, up to 8 speakers, streaming and offline) claims about half
     the DER of pyannote community-1 under NVIDIA's own forced-alignment protocol (P2:177).
   - Locally it only tied community-1 (P2:178). It is not yet a proven upgrade on our audio.
   - pyannote's hosted Precision-3 costs €0.112/h on the Developer plan (pyannote.ai/pricing, 2026-10-24). That is a cheap
     cloud fallback, but audio leaves the machine.

3. **Shot structure is cheap and under-served.**
   - PySceneDetect 0.7.2 (2026-10-12) now publishes benchmarks. Its best detector reaches F1 91.6 on BBC hard cuts, only
     73.9 on short-form AutoShot clips, and **14-26% recall on fades** for every detector except histogram.
   - That matches our measured gap: the scene filter is a lower bound, and claude-eyes catches 0 of 8 dissolves (E1:27,
     F3:61).
   - **OmniShotCut** (MIT, v1.5 weights 2026-09-03) is the first maintained open model that labels dissolves, wipes and
     fades. TransNetV2 and AutoShot have had no commit since 2023.

4. **Spatial grounding means SAM 3.1, and it is CUDA-first.**
   - SAM 3 / 3.1 (Meta, 2025-11 and 2026-03-27, custom "SAM License", gated) takes a text phrase and returns masks and
     track IDs for every instance across a video. That is the most agent-friendly spatial primitive, because the agent
     can call it with a noun.
   - Officially it needs CUDA 12.6+. On a Mac the routes are `transformers` (it ships `sam3_video` and
     `sam3_tracker_video`) or a 45-star MLX port. Neither has been tested here.
   - Grounding DINO is effectively superseded (no push since 2024-08).
   - YOLO26 and the trackers are fast, but YOLO is AGPL-3.0. RF-DETR (Apache-2.0) is the permissive detector.

5. **On-screen text is the highest-yield visual primitive** (OCR raised screen questions from 0.17-0.25 to 0.83, P1:76).
   - Apple Vision stays first on a Mac: zero install, positions included, and measured here.
   - PaddleOCR 3.7 / PP-OCRv6 (2026-06-11, Apache-2.0) is the cross-platform choice. Vendor claims: 6.1x faster on M4
     (tiny tier), and better than Qwen3-VL-235B and GPT-5.5.
   - Surya 0.22 has become a VLM served by llama.cpp, with weights limited to organisations under $5M revenue.

6. **Non-speech audio now has an open-vocabulary, timestamped primitive.**
   - Meta **PE-A-Frame** (Apache-2.0) returns start and end times for a free-text sound description, at 40 ms frames.
     That is a better fit for an agent than the fixed 527-class AudioSet taggers (PANNs, BEATs) or CLAP clip scores.
   - Apple SoundAnalysis (300+ classes, built in) is the zero-install baseline.
   - Newest evidence for the PE-A-Frame card is 2025-12-23, which is older than 6 months.

7. **Embeddings matter for search and dedup, not for understanding.**
   - SigLIP 2 frame embeddings (Apache-2.0, 2025-02) support "find the frame where X" text-to-frame search and
     near-duplicate pruning before images reach Claude.
   - Clip-level encoders (VideoPrism, InternVideo-Next, PE-Video, V-JEPA 2, PE-AV) give retrieval or action features, but
     no text an agent can read. Most date from 2025, so their newest evidence is older than 6 months.

8. **Decoding is solved by ffmpeg plus PyAV 19 / torchcodec 0.17.** decord's last release was 2021-06; do not adopt it.

**What to adopt here, in order (INFERRED from the evidence above):**
- Keep FluidAudio Parakeet plus community-1 as the default speech and diarization path. Keep whisper.cpp for languages
  outside Parakeet's 25.
- Add Apple Vision optical flow and SoundAnalysis through one small Swift CLI.
- Trial OmniShotCut for dissolves, and NeMo-Speech.cpp / Nemotron 3 as a second-opinion diarizer.
- Treat SAM 3.1, CoTracker/TAPNext and the video encoders as CUDA-box tools. Call them only when a question needs masks,
  tracks or retrieval.

---

## Comparison table

| Rank | Primitive (latest version, date) | Channel → agent-readable output | Apple Silicon | License | Activity (2026-10-24) | Evidence |
|---|---|---|---|---|---|---|
| 1 | FluidAudio v0.17.7 (2026-10-08) | speech → word-timed text, speakers, VAD | Native: CoreML on the Neural Engine; installed here | Apache-2.0 code; Parakeet CC-BY-4.0 | 3,178★, push 2026-10-21 | MEASURED locally (P1/P2) |
| 2 | whisper.cpp v1.9.5 (2026-10-06) | speech → SRT/JSON, 99 languages | Native Metal; 1.9.2 installed | MIT | 54,606★, push 2026-10-19 | MEASURED locally |
| 3 | NeMo-Speech.cpp v0.2.0 (2026-10-02) + Nemotron 3.5 ASR / Nemotron 3 Diarization | speech → text + 8-speaker diarization JSON, OpenAI-compatible server | Metal backend (installer docs) | Apache-2.0 runtime; OpenMDW-1.1 weights | 197★, push 2026-10-24 | Diarizer tie MEASURED (P2:178); runtime vendor only |
| 4 | Apple Vision (macOS 26: RecognizeText/RecognizeDocuments, optical flow, tracking) | pixels → text with boxes, flow fields, tracked boxes | OS built-in | Apple SDK | ships with the OS | OCR MEASURED (P1:63-68) |
| 5 | PySceneDetect v0.7.2 (2026-10-12) | frames → shot list (CSV/EDL/FCP) | CPU, pip | BSD-3-Clause | 5,285★, push 2026-10-22 | Vendor-run public benchmarks |
| 6 | pyannote.audio 4.0.7 (2026-06-30) community-1 / Precision-3 hosted | speech → RTTM speakers | CPU/MPS (Python) | MIT code; CC-BY-4.0 gated weights | 10,690★, push 2026-10-22 | Vendor DER; community-1 MEASURED via FluidAudio |
| 7 | OmniShotCut v1.5 (2026-09-03) | frames → shots plus transition type (dissolve, fade, wipe) | CUDA-first; 5★ MLX port | MIT (code and weights) | 339★, push 2026-09-09 | Vendor only (paper 2026-04-27) |
| 8 | SAM 3.1 (2026-03-27) | text phrase → masks and track IDs across video | CUDA 12.6+ official; transformers `sam3_video`; 45★ MLX port | SAM License (custom), gated | 12,091★, push 2026-10-23 | Vendor (SA-Co benchmark is Meta's own) |
| 9 | PaddleOCR 3.7.0 / PP-OCRv6 (2026-06-11) | pixels → text + boxes, 50 languages | CPU; vendor claims 6.1x on M4 | Apache-2.0 | 91,584★, push 2026-09-16 | Vendor only |
| 10 | PE-A-Frame (Meta, card 2025-12-23) | audio + free-text query → event start/end | PyTorch CPU/MPS (not tested) | Apache-2.0 | 60,913 downloads; transformers `pe_audio` | Vendor only; older than 6 months |
| 11 | Apple SoundAnalysis (`version1` classifier) | audio → 300+ labels per window | OS built-in | Apple SDK | unchanged since WWDC21 | Vendor only |
| 12 | SigLIP 2 (2025-02) | frame ↔ text embeddings for search and dedup | MPS/MLX; transformers | Apache-2.0 | 1.8M downloads (giant) | Vendor and paper; older than 6 months |
| 13 | YOLO26 (ultralytics 8.4.185, 2026-10-24) + roboflow trackers / RF-DETR 1.11.2 | pixels → class boxes + track IDs | MPS / CoreML export | **AGPL-3.0** (YOLO); Apache-2.0 (RF-DETR, trackers); MIT (supervision) | 62,790★ / 9,883★ / 3,958★ | Vendor COCO numbers |
| 14 | Apple-Silicon speech runtimes: mlx-audio v0.6.1, WhisperKit/SpeakerKit v1.1.1, sherpa-onnx v2.0.0 | speech → text / speakers / audio tags | MLX / CoreML / ONNX CPU | MIT / MIT / Apache-2.0 | 8,095★ / 6,412★ / 15,470★ | Vendor only |
| 15 | faster-whisper 1.2.1 (2025-10-31) / WhisperX 3.8.7rc1 (2026-06-26) | speech → word-aligned text + pyannote speakers | CPU only on Mac (CTranslate2 has no Metal) | MIT / BSD-2-Clause | 26,087★ / 24,812★ | Vendor; faster-whisper release older than 6 months |
| 16 | Point tracking: CoTracker3 / TAPNext++ | query points → 2D trajectories | PyTorch / JAX, GPU-preferred | **CC-BY-NC-4.0** (CoTracker3); Apache-2.0 (tapnet) | 5,164★ (push 2026-03-03) / 2,236★ (push 2026-09-15) | Vendor TAP-Vid |
| 17 | Optical flow: SEA-RAFT / WAFT / MEMFOF (vs OpenCV DIS / Apple Vision) | frames → flow magnitude per frame | GPU-first; OpenCV and Apple run on CPU/ANE | BSD-3-Clause | 719★ / 277★ / 110★; no commit after 2026-03 | Vendor Spring/Sintel |
| 18 | Clip-level video encoders: VideoPrism, InternVideo-Next, PE-Video / PE-AV, V-JEPA 2 | clip → embedding (retrieval, actions) | transformers; MPS untested | Apache-2.0 / Apache-2.0 / Apache-2.0 / MIT | VideoPrism push 2026-10-20 (JAX only) | Vendor; mostly older than 6 months |
| 19 | Decoding: ffmpeg 9.0.1, PyAV 19.0.2 (2026-10-21), torchcodec 0.17.0 (2026-09-30); decord 0.6.0 (2021) | container → frames/PCM at exact timestamps | ffmpeg VideoToolbox; torchcodec CPU wheels on macOS | LGPL/GPL (ffmpeg); BSD-3-Clause; BSD-3-Clause; Apache-2.0 | decord **stale** | n/a |

---

## Entries (ranked)

### 1. FluidAudio (FluidInference): Parakeet TDT v3 + diarization + Silero VAD on the Apple Neural Engine
- **Gives the agent:** a word-timed transcript in 25 European languages plus Japanese, speaker turns (offline
  community-1 clustering, or streaming Sortformer), and VAD. Text is the cheapest thing Claude can read.
- **Path:** audio only. CoreML on the Neural Engine, which "avoid[s] GPU/MPS entirely" (README).
- **Measured here:**
  - Parakeet runs at 145x realtime (P1:50).
  - 20.8% mean WER on 7 AMI/ICSI meetings, against 24.5% for the best Whisper setting (P2:126).
  - 0 hallucinated cues over 35 min of digital silence, where Whisper wrote 71-102 (P1:44).
  - The default diarization threshold put 2,616 of 2,646 s on one speaker; 0.55 fixed it (REPORT:33).
  - The diarizer build mattered more than the model choice (P1:104).
- **Deployment:** local, macOS and iOS. Swift SDK plus `fluidaudiocli`. Apache-2.0 code.
  `FluidInference/parakeet-tdt-0.6b-v3-coreml` is CC-BY-4.0 (card updated 2026-08-19).
  `speaker-diarization-coreml` is "other" (updated 2026-10-12).
- **Maturity:** v0.17.7 (2026-10-08), 3,178★, push 2026-10-21. The README lists 50+ shipping apps (VoiceInk, Spokenly,
  Talat and others) and claims "500k+ monthly downloads" on HF.
- **Claude fit:** Bash CLI → JSON → Read. No egress. Already wired into `skills/video-understanding`.

### 2. whisper.cpp (ggml-org)
- **Gives the agent:** the multilingual fallback (99 languages) and deterministic SRT/JSON output; outputs were
  byte-identical across runs (P1:49).
- **Path:** audio only, 16 kHz WAV, Metal.
- **Measured traps:** loops on 3 of 7 meetings with default settings, filler hallucinated over silence, and invented
  speaker-name prefixes (P2:133-135). These are why the skill ships ASR guardrails.
- **Maturity:** v1.9.5 (2026-10-06, ggml 0.26 maintenance release). 54,606★. Local install is 1.9.2, three patch
  releases behind (MEASURED, `brew list --versions`).
- **Deployment:** local. MIT.
- **Claude fit:** CLI (`whisper-cli`). No egress.

### 3. NVIDIA NeMo-Speech.cpp + Nemotron 3.5 ASR Streaming 0.6B + Nemotron 3 Diarization
- **Gives the agent:** one CLI that runs `nemo-speech transcribe meeting.wav --diarize --json`. The output is
  word-level speaker tags from an 8-speaker diarizer, and a local OpenAI-compatible HTTP server (127.0.0.1:8080) is
  also available.
- **Path:**
  - Audio. 80 ms encoder frames, output resolution in 10 ms steps.
  - Nemotron 3.5 ASR covers 40 language-locales with language ID.
  - The diarizer streams with a 0.32-30.4 s buffer and has no audio length cap when chunked (model card).
- **Deployment:** local. ggml runtime. The installer "selects ... Metal on Apple Silicon" (`docs/install.md`).
  Prebuilt release archives are SHA-256 checked. Runtime Apache-2.0; weights **OpenMDW-1.1**.
- **Maturity:**
  - Repo created 2026-07-15, v0.2.0 (2026-10-02), nightly 2026-10-17, 197★.
  - Nemotron 3 Diarization released 2026-09-23 with 120,820 downloads.
  - nemotron-3.5-asr-streaming-0.6b has 1,143,096 downloads (HF API, 2026-10-24).
- **Evidence:**
  - Vendor: AMI-SDM 11.14% and DIHARD III 12.73% DER, against 19.9% and 20.2% for community-1 (P2:177).
  - Measured here: a tie with community-1 on the private Teams recording, p = 0.12 (P2:178).
  - Throughput: vendor claims 67x realtime on an RTX 4090 and 6x on CPU (Nemotron streaming, Q8_0). No Apple
    figures are published.
- **Claude fit:** CLI or local HTTP. No egress after the model download.
- **Caveat:** the 8-speaker cap.

### 4. Apple Vision framework (OCR, documents, optical flow, object tracking)
- **Gives the agent:**
  - `VNRecognizeTextRequest`: text with bounding boxes. This was the single biggest gain on screen questions (P1:76).
  - `RecognizeDocumentsRequest` (WWDC25 session 272, the macOS 26 generation): lines grouped into paragraphs and parsed
    tables.
  - `VNGenerateOpticalFlowRequest`: dense flow on the Neural Engine and GPU.
  - `VNTrackObjectRequest`: box tracking.
- **Path:** frames from ffmpeg go to the Swift Vision API, which returns JSON.
- **Measured here:**
  - Legibility: 1080p tiled 1.000, 720p 0.76, 360p 0.07 (P1:63).
  - 34% phantom-line jitter on unchanged screens (P1:66).
  - Monospace stays readable at 8 px; proportional fonts fail (P2:§3.1).
- **Deployment:** local, OS built-in, no download.
- **Claude fit:** a small Swift CLI, as in claude-eyes (F3:61). No egress.
- **Gap:** optical flow and tracking from Vision have not been measured here. The motion probes use OpenCV.

### 5. PySceneDetect 0.7.2 (Breakthrough)
- **Gives the agent:** a shot list (start/end timecodes) with which to place contact sheets and targeted frames, plus
  "cuts per minute" editing statistics.
- **Path:** decoded frames. The detectors are content (HSV delta), adaptive, histogram, perceptual-hash and threshold
  (fade to black). Backends are OpenCV, PyAV 19 and MoviePy. v0.7 made variable-frame-rate (VFR) video correct (2026-05-03).
- **Evidence** (vendor-run on public datasets, strict frame-exact, scenedetect.com/benchmarks):
  - BBC Planet Earth: AdaptiveDetector F1 91.6 (R 87.1, P 96.6).
  - AutoShot short-form: 73.9.
  - ClipShots hard cuts: 55.8 (precision 41%).
  - **ClipShots fades: recall 13.7-26.0%** for adaptive, content and hash; histogram reaches 69.7%.
  - v0.7.2 retuned the histogram and hash defaults from these sweeps.
- **Agent implication:** consistent with our measurement that any scene-filter list is a lower bound (168 of about 345
  strong cuts missed, REPORT:138).
- **Deployment:** local, pip, CPU. BSD-3-Clause. Not installed here.
- **Claude fit:** `scenedetect -i v.mp4 detect-adaptive list-scenes`, CSV → Read. No egress.

### 6. pyannote.audio 4 (community-1 open; Precision-3 hosted)
- **Gives the agent:** RTTM "who spoke when" output, and the de facto Python diarization API. WhisperX and Argmax
  SpeakerKit both build on it.
- **Evidence** (vendor, README table "last updated 2025-09", older than 6 months):

  | DER % | 3.1 | community-1 | precision-2 |
  |---|---|---|---|
  | AMI-SDM | 22.7 | 19.9 | 15.6 |
  | DIHARD 3 | 21.4 | 20.2 | 14.7 |

  Speed: community-1 takes 31 s per hour of audio, on unstated hardware.
- **Pricing** (pyannote.ai/pricing, fetched 2026-10-24):
  - Developer plan €19/month: Precision-3 batch €0.112/h, hosted community-1 €0.035/h, Live-1 streaming €0.198/h,
    STT orchestration (Parakeet v3 or Whisper turbo) €0.168/h.
  - Starter plan €99/month: Precision-3 €0.096/h.
  - The model line has moved from precision-2 to Precision-3; no public benchmark for Precision-3 was found.
- **Deployment:** local, MIT code. community-1 weights are CC-BY-4.0 and gated (accept conditions; HF token). The
  hosted API is cloud: audio egress.
- **Maturity:** 4.0.7 (2026-06-30), 10,690★, push 2026-10-22, 4.95M downloads for community-1.
- **Claude fit:** Python script → RTTM → Read. Locally it is already reachable through FluidAudio's CoreML port.

### 7. OmniShotCut (UVA Computer Vision Lab)
- **Gives the agent:** shot ranges **with transition labels** (sudden jump, dissolve, fade, wipe). This fills the
  dissolve blind spot that ffmpeg, PySceneDetect and claude-eyes all share (claude-eyes 0 of 8, F3:61).
- **Path:** a dense video transformer over decoded frames. `mode="clean_shot"` returns hard cuts only;
  `mode="default"` adds labelled transitions.
- **Deployment:** local. "Install PyTorch with CUDA support" (README). An MLX port (`eisneim/OmniShotCut_mlx`) has 5★,
  no license and a last push of 2026-05-04. Code and v1.5 weights are MIT.
- **Maturity:**
  - arXiv 2604.24762 (2026-04-27). v1.5 weights 2026-09-03, 7,673 downloads. 339★, push 2026-09-09.
  - Benchmark and training code are "not yet released" (README checklist).
- **Evidence:** vendor only, on its own OmniShotCutBench, which is unreleased.
- **Predecessors:** TransNetV2 (MIT, 1,061★, last push 2023-12-04; F1 77.9 ClipShots, 96.2 BBC per its paper) and
  AutoShot (MIT, 263★, last push 2023-04-18) are **stale**.
- **Claude fit:** Python script → JSON. No egress. Worth a measured trial on our dissolve set.

### 8. SAM 3 / SAM 3.1 (Meta) + Grounding DINO lineage
- **Gives the agent:** given a noun phrase or exemplar ("the presenter's laptop", "player in red"), it returns masks
  and persistent IDs for **every instance** in every frame. From those, the agent can compute counts, positions, entry
  and exit times and trajectories as numbers. This is the most direct "spatial and temporal grounding as text" primitive.
- **Path:** an 848M-parameter detector plus a SAM 2-style tracker over a JPEG folder or MP4.
  - SAM 3.1 "Object Multiplex" (2026-03-27) adds shared-memory multi-object tracking, "significantly faster".
  - Recent commits (2026-09-18 to 10-07) add an instance cap, streaming eviction of frame outputs, and caller-mask
    conditioning.
- **Deployment:**
  - Official: CUDA 12.6+ GPU.
  - Apple Silicon: transformers ships `sam3`, `sam3_video`, `sam3_tracker_video` and `sam3_lite_text`, but MPS is not
    verified. `Deekshith-Dade/mlx_sam3` has 45★, no license, last push 2026-07-30.
  - License: "SAM License" (custom, last updated 2025-11-19; royalty-free use and redistribution, with trade-control
    terms). Weights are gated (manual approval).
- **Maturity:** 12,091★, push 2026-10-23. facebook/sam3 has 1.84M downloads and sam3.1 has 114,646.
- **Evidence:** vendor only. "75-80% of human performance" on SA-Co, which is Meta's own benchmark.
- **Grounding DINO:** last push 2024-08-12 and last release 2023-04 (**stale**). Grounded-SAM-2 last pushed
  2025-11-11. For open-vocabulary boxes, use SAM 3's detector or transformers' `mm_grounding_dino` / `owlv2`.
- **Claude fit:** run on a CUDA box or a cloud GPU (frames leave the machine), or try transformers on MPS. The output
  is JSON tracks that Claude reads. Overlay renders give Claude visual confirmation.

### 9. PaddleOCR 3.7 / PP-OCRv6 (+ PaddleOCR-VL-1.6)
- **Gives the agent:** cross-platform OCR with boxes, 50 languages in one model (Chinese, English, Japanese and 46
  Latin-script languages). Claimed gains on "digital displays, dot-matrix", which is relevant to screen recordings.
  PaddleOCR-VL-1.6 handles full document parsing.
- **Evidence:** vendor only, from the v3.7.0 notes (2026-06-11):
  - Medium tier: +4.6% detection and +5.1% recognition over PP-OCRv5_server.
  - "surpassing ... Qwen3-VL-235B, GPT-5.5 with only 34.5M parameters".
  - "6.1x on Apple M4 (tiny)".
  - PaddleOCR-VL-1.6: 96.33 on OmniDocBench v1.6 (v3.6.0, 2026-05-28).
- **Deployment:** local, Apache-2.0. Since v3.5 (2026-04-21) it has a Transformers backend, so it runs without
  PaddlePaddle. PaddleOCR.js runs in the browser.
- **Maturity:** 91,584★, push 2026-09-16. PP-OCRv6_medium_rec card dated 2026-06-12.
- **Claude fit:** Python CLI → JSON. Use it when Apple Vision is unavailable (Linux) or for CJK.

**Other OCR, ranked lower:**
- **Surya 0.22.1** (2026-07-20, 21,524★):
  - Layout, OCR and tables are now one VLM served by vllm or llama.cpp on CPU or Apple Silicon.
  - Code is Apache-2.0. Weights use a "modified AI Pubs Open Rail-M" license, free only for research, personal use and
    organisations under $5M funding or revenue.
  - Datalab's own benchmark claims; heavier per frame. Document-oriented, not screen video.
- **docTR 1.1.0** (2026-08-21, 6,393★, Apache-2.0): a mature detection-plus-recognition stack (DBNet/FAST + CRNN/PARSeq),
  PyTorch on CPU/MPS. A permissive fallback; no 2026 accuracy claims found.

### 10. PE-A-Frame and PE-AV (Meta Perception Encoder, audio)
- **Gives the agent:** **open-vocabulary sound-event localization**. You give it a free-text description ("applause",
  "door slam", "music starts") and it returns start and end timestamps, using one embedding per 40 ms (model card). The
  agent can query the soundtrack with words, which fixed-class taggers cannot do.
- **PE-AV** embeds audio, video, audio plus video, and text into one space: 51.6 average retrieval for pe-av-large on
  all frames.
- **Deployment:** local. PyTorch `perception_models` or transformers (`pe_audio`, `pe_audio_video`, `pe_video`).
  Sizes 450M / 560M / 1.4B. Apache-2.0. MPS is not tested.
- **Maturity:** pe-a-frame-large has 60,913 downloads. Card last modified 2025-12-23, **older than 6 months**.
- **Evidence:** vendor only.
- **Claude fit:** a Python script that takes a list of queries and returns spans as JSON. No egress. It answers
  "hearing" questions the skill currently lists as unrecoverable, such as laughter (SK:154-157), although it does not
  give prosody.

### 11. Apple SoundAnalysis (built-in classifier)
- **Gives the agent:** over 300 sound labels with time ranges, multi-label (overlapping sounds), from audio or video
  files, with zero install. The only identifier is `.version1` (WWDC21 10036; community write-ups).
- **Deployment:** local, OS built-in.
- **Evidence:** vendor only. No accuracy figures are published, and the newest evidence is old (2021 API, unchanged).
- **Claude fit:** a small Swift CLI → JSON. The best first audio-event layer on a Mac.
- **Older open taggers, all stale:**
  - PANNs: `audioset_tagging_cnn`, last push 2024-07-25, MIT. A LiteRT export appeared 2026-06-30.
  - BEATs: under `microsoft/unilm`, MIT, no tagged release since 2024.
  - LAION CLAP: last push 2025-05-15, CC0-1.0, though `clap-htsat-fused` still has 7.17M downloads.
  - sherpa-onnx wraps audio tagging for CPU (entry 14).

### 12. SigLIP 2 (Google) frame embeddings
- **Gives the agent:** text-to-frame search ("the frame with the architecture diagram") and near-duplicate pruning
  before images go to Claude. This cuts image tokens; claude-video uses a crude 16x16 dedup instead (F3:60).
- **Path:** per-frame image embeddings. Variable-resolution "naflex" variants keep aspect ratio.
- **Deployment:** local. transformers `siglip2`; MPS or MLX. Apache-2.0.
- **Maturity:** cards dated 2025-02-18 to 2025-02-21 (**older than 6 months**). Still heavily used: the giant variant
  has 1.81M downloads and base-224 has 1.64M.
- **Alternative:** Meta PE-Core (Apache-2.0, 2025-04).
- **Claude fit:** a Python indexer writes a vector file; a query script returns timestamps. No egress.

### 13. YOLO26 (Ultralytics) + roboflow trackers / supervision / RF-DETR
- **Gives the agent:**
  - Fast COCO-class boxes, masks, pose, OBB and depth, with built-in ByteTrack/BoT-SORT track IDs.
  - People counts, dwell time, motion paths as numbers.
  - supervision (MIT, 0.31.1, 2026-10-20) adds zone counting and line crossing.
- **Deployment:** local; MPS and CoreML export.
  - Ultralytics is **AGPL-3.0**; commercial use needs an Enterprise License. YOLO27 is announced but "not yet available".
  - YOLOv12 (sunsmarterjie) is also AGPL-3.0, last release 2025-07.
  - RF-DETR 1.11.2 (2026-10-04, Apache-2.0, 9,883★) is the permissive detector.
  - `roboflow/trackers` (Apache-2.0, 3,958★) gives model-agnostic tracking.
- **Evidence:** vendor COCO mAP (YOLO26n 40.9 mAP at 640 px, per the README).
- **Claude fit:** Python → JSON tracks. Closed-vocabulary, so SAM 3 is better for arbitrary nouns. YOLO is faster on a Mac.

### 14. Apple-Silicon speech runtimes: mlx-audio, Argmax WhisperKit/SpeakerKit, sherpa-onnx
- **mlx-audio** (v0.6.1, 2026-10-20, MIT, 8,095★):
  - Whisper, Parakeet v2/v3, Nemotron 3.5 ASR streaming, Qwen3-ASR, Voxtral, and MOSS-Transcribe-Diarize (timestamped
    with speakers), all on MLX.
  - This makes it the quickest way to A/B-test new ASR models on this Mac.
- **argmax-oss-swift** (formerly WhisperKit; v1.1.1, 2026-10-08, MIT, 6,412★): WhisperKit (Whisper on CoreML),
  SpeakerKit (pyannote on CoreML) and TTSKit. The Pro SDK is paid.
- **sherpa-onnx** (v2.0.0, 2026-10-23, Apache-2.0, 15,470★): ASR, diarization, audio tagging, VAD, punctuation and
  language ID on ONNX CPU across every OS. It is the portable choice when the pipeline must also run on Linux.
- **Apple SpeechAnalyzer** (macOS 26): an OS-native long-form ASR, but only through third-party benchmarks.
  - Inscribe (2026-07, vendor of an app that uses it): 2.12% / 4.56% WER on LibriSpeech clean / other.
  - Argmax: "matches ... mid-tier Whisper" on long-form conversation.
  - Neither source is neutral, and SpeechAnalyzer has not been tested here.
- **Claude fit:** CLI or Swift; all local.

### 15. faster-whisper / WhisperX
- **Gives the agent:** WhisperX adds wav2vec2 forced alignment (accurate word times), VAD batching that "reduces
  hallucination", and pyannote speaker labels. It is the classic Linux/CUDA "one-shot transcript with speakers".
- **Apple Silicon:** weak. The CTranslate2 backend runs on CPU only on a Mac (INFERRED from the CTranslate2 backend
  list). whisper.cpp or FluidAudio are better here.
- **Maturity:**
  - faster-whisper v1.2.1 (2025-10-31, **older than 6 months**, though the repo was pushed 2026-10-23), 26,087★, MIT.
  - WhisperX 3.8.7rc1 (2026-06-26), 24,812★, BSD-2-Clause.
- **Evidence:** vendor ("70x realtime with large-v2" on a GPU).
- **Claude fit:** Python CLI. No egress unless the pyannote hosted API is used.

### 16. Point tracking: CoTracker3 (Meta) / TAPNext++ (DeepMind tapnet)
- **Gives the agent:** dense 2D trajectories of chosen points through occlusion. Useful for "how did X move" or "did
  the camera pan or did the object move", reported as numeric paths.
- **License:**
  - CoTracker3 weights and code are **CC-BY-NC-4.0**: non-commercial only. Card 2024-10; repo push 2026-03-03.
  - tapnet (TAPNext, TAPNext++, BootsTAPIR) is Apache-2.0, 2,236★, push 2026-09-15. TAPNext++ claims "40x longer
    stable tracking".
- **Deployment:** PyTorch / JAX. GPU preferred; Mac viability untested.
- **Evidence:** vendor TAP-Vid only.
- **Claude fit:** niche. For motion questions on this repo's films, `motion-probe.py curve/flow` already answers with
  OpenCV (SK:110-135).

### 17. Optical flow: SEA-RAFT / WAFT / MEMFOF vs classical
- **Gives the agent:** per-frame motion magnitude and direction, which locate cuts, dead air and camera moves.
- **Practical path here:** OpenCV DIS/Farneback (already used by `motion-probe.py flow`) or Apple Vision
  `VNGenerateOpticalFlowRequest`. Learned flow mainly buys sub-pixel accuracy that an agent's questions rarely need.
- **Learned SOTA** (vendor claims; no 2026 Spring leaderboard snapshot found):
  - WAFT (ICLR 2026, BSD-3-Clause, 277★, push 2026-03-26) claims first place on Spring, Sintel and KITTI.
  - MEMFOF (ICCV 2025, 110★, push 2025-12-11) claims 1080p in 2.09 GB.
  - SEA-RAFT: 719★, push 2026-03-26. RAFT: 4,117★, push 2025-08-24.
- **Deployment:** GPU-first PyTorch.
- **Claude fit:** low priority.

### 18. Clip-level video encoders: VideoPrism, InternVideo-Next, PE-Video / PE-AV, V-JEPA 2
- **Gives the agent:** clip embeddings for retrieval, zero-shot action labels and temporal localization training. No
  readable text unless a classifier or text tower is added.
- **VideoPrism** (Google DeepMind):
  - Apache-2.0, JAX/Flax only ("Add PyTorch model support" still unchecked).
  - LvT video-text checkpoints dated 2025-07. Repo push 2026-10-20 (a gelu precision change). 400★.
  - transformers now has a `videoprism` model directory.
- **InternVideo-Next** (2025-12, Apache-2.0 repo). InternVideo3-8B (2026-06) is a VLM and belongs to the open-weight VLM
  axis.
- **V-JEPA 2:** MIT, card 2025-05/08.
- **PE-Video / PE-AV:** Apache-2.0, 2025.
- **Note:** most of these are **older than 6 months**.
- **Claude fit:** only for building a searchable index across many videos. A server-side index is the agent-native
  pattern (see the F3 / Cloudglue rows).

### 19. Decoding: ffmpeg 9, PyAV 19, torchcodec 0.17 (avoid decord)
- **Gives the agent:** frame-exact seeks and timestamps. Every later primitive depends on this. The "sheet labels N/2
  early" trap was a decoding and timestamp issue (REPORT:103).
- **ffmpeg 9.0.1** is installed. It is the CLI substrate and offers VideoToolbox hardware decode on a Mac.
- **PyAV 19.0.2** (2026-10-21, BSD-3-Clause, 3,314★): the Python binding to the ffmpeg libraries. PySceneDetect 0.7.2
  added PyAV 19 support.
- **torchcodec 0.17.0** (2026-09-30, BSD-3-Clause, 1,189★, needs torch ≥ 2.11):
  - New low-level demux/decode/convert API with GIL-free multi-threaded pipelines, and raw YUV/HDR access.
  - Image codecs replace torchvision's since 0.16.
  - macOS gets CPU-only wheels (CUDA on Linux). The local torch 2.4.1 is too old for it.
- **decord 0.6.0:** last release 2021-06-14, last push 2024-07-17. **Stale; do not adopt.**
- **Claude fit:** ffmpeg via Bash is enough. Use torchcodec or PyAV only inside Python model pipelines.

---

## Concerns and gaps
- Several ASR leaderboard numbers are secondary: the HF results dataset is gated, and openwhispr.com sells a dictation
  app built on these models.
- No primitive here was newly measured in this run. The only local measurements are those inherited from the
  2026-10-23 corpus, plus this run's tool-presence checks.
- Apple Silicon viability of SAM 3.1 via transformers on MPS, OmniShotCut, PE-A-Frame and NeMo-Speech.cpp Metal is
  DOCUMENTED or INFERRED, not tested.
- License traps for any commercial use:
  - Ultralytics YOLO: AGPL-3.0.
  - CoTracker3: CC-BY-NC-4.0.
  - Surya weights: capped at $5M revenue.
  - SAM License: custom, with trade-control terms.
  - OpenMDW-1.1 (Nemotron): read it before redistributing.

## Sources
- GitHub API, fetched 2026-10-24, for every repository named above, e.g. https://github.com/FluidInference/FluidAudio,
  https://github.com/NVIDIA/NeMo-Speech.cpp, https://github.com/facebookresearch/sam3,
  https://github.com/UVA-Computer-Vision-Lab/OmniShotCut
- https://huggingface.co/nvidia/Nemotron-3-Diarization ; https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- https://github.com/pyannote/pyannote-audio ; https://www.pyannote.ai/pricing
- https://www.scenedetect.com/benchmarks/ ; https://arxiv.org/abs/2604.24762
- https://github.com/PaddlePaddle/PaddleOCR/releases/tag/v3.7.0 ; https://github.com/datalab-to/surya
- https://huggingface.co/facebook/pe-a-frame-large ; https://huggingface.co/facebook/pe-av-large
- https://developer.apple.com/videos/play/wwdc2025/272/ ; https://developer.apple.com/videos/play/wwdc2021/10036/
- https://openwhispr.com/blog/parakeet-vs-whisper-vs-nemotron (secondary ASR leaderboard figures)
- https://www.gigazine.net/gsc_news/en/20260714-apple-speech-analyzer-benchmark/ ;
  https://www.argmaxinc.com/blog/apple-and-argmax
- https://iclr.cc/virtual/2026/poster/10010386 (WAFT) ; https://arxiv.org/abs/2506.23151 (MEMFOF)
- https://github.com/meta-pytorch/torchcodec/releases/tag/v0.17.0
