<!-- markdownlint-configure-file {
  "MD013": false
} -->

# V4: Adversarial review of V3's verdict on the NVIDIA GTC 2026 VSS talk (2026-10-24)

The operator asked whether https://www.youtube.com/watch?v=3yPQHcEZDaI (GTC 2026 S81836, "Visual AI Agents for Real-Time Video Understanding", 33:37) is "applicable and helpful or no?". V3 (`V3-applicability-verdict.md`) answered "partly". This file tries to overturn V3 in both directions. It does not edit V3.

**Inputs read:** V3, V1, V2, and R5 §2. I spot-checked V3's own cites in the parity REPORT, `skills/video-understanding/SKILL.md` (SK), `E3-judgement.md`, `E2b-watcher-full-pipeline.md`, `v2-spec.md`, `SESSION-STATE.md` and the agentsync PLAN. I also re-read three talk frames from V1's ingest (`/tmp/vss-talk-2026-10-24/hires/s0975.png`, `s1385.png`, `s1490.png`) and its yt-dlp logs.

**Primary sources fetched today** into `/tmp/v4-skeptic-src/`:
- the repo, through `gh api`: releases, the tree, `critic.py`, the `vss-ask-video` skill, the CLI README, the LVS configs and the OCR config;
- `docs.nvidia.com/vss/3.3.0/*.md`, through curl;
- the HF API and model pages;
- build.nvidia.com pages and the docs.api.nvidia.com Omni reference;
- the NVIDIA API Trial Terms PDF and the NVIDIA Software and Model Evaluation License;
- the Cosmos 3 technical report PDF;
- three arXiv abstracts.

Line numbers refer to those copies.

**Labels:** **MEASURED** means I fetched, counted or computed it today, and the source is named. **DOCUMENTED** means a vendor page, card or paper says it. **INFERRED** is my judgement. Every conviction percentage is INFERRED.

## 0. Does V3 survive?

**Yes, on every adopt-or-not ruling.** VSS cannot run on the Mac, and neither VSS nor Cosmos fits the meeting case. Several of V3's supporting reasons, though, are wrong, stale or weaker than the ones available. Re-checking turned up stronger reasons, so the "No" rulings get firmer. **The pattern-borrowing side is oversold.** B1, V3's lead recommendation at 80%, targets errors its VSS mechanism cannot fix. B4 rests on a mis-sourced number.

| V3 ruling | V3 | After this review | Main reason |
|---|---|---|---|
| U1a: adopt VSS for the skill | No, 98% | **No, ~98%** (unchanged) | The Mac is not a host, and a local GPU is needed even with both models remote (re-fetched). The evaluation licence also limits the microservices to "internal test and evaluation purposes, without use in production and in systems with NVIDIA GPUs" (§1 #7) |
| U1b: adopt Cosmos Reason locally | No, 92% | **No, ~93%, on better evidence** | A de facto Mac path *does* exist for Cosmos-Reason2: it has the Qwen3-VL-8B architecture (§2 a2). But NVIDIA's own Table 10 puts Reason2-8B *below* Qwen3-VL-8B on OCR and hallucination, and Cosmos3-Nano gains nothing on the spatial benchmarks REPORT cites |
| U1c-B1: per-criterion critic | Yes, 80% | **45-50% as written; ~65% if reframed** (§3 b1) | All 5 target errors are outside what the VSS critic checks. Three are audio inferences that SK's audio-probe prose already covers. One is a sampling miss and one a small-region read. No published evidence that the critic works |
| U1c-B4: hard filters plus semantic search | 65% | **~55%; fix the citation** | The 42.9% figure is a vendor paper's router, not "our meeting work". VSS fuses both channels in 52 of 121 benchmark queries |
| U1c-B2, B3, B5 | 75 / 70 / 85% | Unchanged | B2 gains a second NVIDIA data point: Cosmos-Reason2's card recommends 4 fps input |
| U2: meetings on the corporate Mac | No, 95% | **No, ~97%, with the reasons replaced** | V3 leans on agentsync's own non-goals. Stronger external reasons exist: the licence, keyframes adding only 1.5 of 18 points in our meeting experiments, a 1280x720 default VLM input, and no ASR or screen OCR |
| U3: landscape rank | First for camera fleets | **First in that niche still**, but three supporting claims are wrong | "Ships monthly" is false. "Alpha" is a 3.0.0 label. The skills are Early Access and "not intended for use in production" |
| U4: was watching worth it? | The docs alone would have settled it (85%) | Unchanged | The yt-dlp "new failure mode" is overstated: the failed run printed yt-dlp's own "older than 90 days" warning |
| *(not in V3)* | — | **Free hosted Nemotron-3-Nano-Omni endpoint** for public clips with no identifiable people (§2 a1) | Optional one-hour probe for the laughter and audio-event gap. 40% it is worth it. Never for meetings |

## 1. Load-bearing facts, re-checked against primary sources today

| # | V3 claim | Primary source today | Result |
|---|---|---|---|
| 1 | The Mac is not a deployment host | `getting-started/quickstart.md:181-182`: "A Windows or Mac machine can be used as the browser or coding-agent client, but it is not the validated Docker Compose deployment host" | **CONFIRMED** (MEASURED, curl) |
| 2 | A local NVIDIA GPU is needed even with a remote LLM and VLM | `getting-started/prerequisites.md:356-411`. The H100 table needs 1 GPU for base with "Remote LLM + VLM". The GB300 note says a remote model "does not remove the GPU required by the profile services" | **CONFIRMED** |
| 3 | Minimum host: 18 cores, 128 GB, 1 TB | `prerequisites.md:198-200` (x86 systems) | **CONFIRMED** |
| 4 | "Edge platforms run only the base and alert profiles" (V3 §3) | `prerequisites.md:413-447`. DGX Spark and AGX Thor also run **search** when both the LLM and the VLM are remote. LVS is "not supported on these edge platforms" | **CORRECTED** (V2 had it right; V3 compressed it) |
| 5 | "No ASR, no OCR and no diarization" | **Repo tree** (`gh api …/git/trees/develop?recursive=1`, 11,010 paths): nothing for Whisper, Riva or diarization.<br>**Parakeet:** `rt-vlm/…/patches/apply_vllm_parakeet_transformers5_patch.py` patches a Parakeet config with `llm_hidden_size`/`projection_hidden_size`. That is an omni model's audio encoder, not an ASR service.<br>**OCR:** `warehouse-3d-app/deepstream/configs/config-ocr.yaml` ships **OCDNet + OCRNet** in TensorRT, with 224x224 detection input, `max_candidate: 1`, a 32x100 recognizer and CTC decoding | **PARTLY CORRECTED.** No ASR and no diarization is right. "No OCR" is literally false. What exists reads object labels inside the warehouse DeepStream pipeline; it is not screen or document OCR. The verdict is unaffected |
| 6 | "Its long-video summarizer writes at most 100 tokens per 10 s chunk" | **Where 100 appears:** "Output max tokens 100" is the **VSS 3.2 benchmark configuration** (`appendix/performance/agent-workflows/video-summarization-performance.md:25-36`).<br>**Shipped default:** `dev-profile-lvs/vss-agent/configs/config.yml:108-111` sets `chunk_duration: 10`, `num_frames_per_chunk: 20`, `vlm_input_width: 1280`, `vlm_input_height: 720`.<br>**No caption cap:** none is set in the three LVS configs I read (grep) | **CORRECTED.** 100 tokens is a test setting, not a product cap. The stronger fact for us is the **1280x720 default VLM input**: SK:57-58 requires 1080p or more for on-screen text |
| 7 | Licensing: the repo is Apache-2.0, the microservices are under an evaluation licence, and AI Enterprise is needed for local NIM | **Licence page:** `appendix/license-information.md` puts "blueprint deployment files and scripts" under Apache-2.0 and "blueprint microservices" under the NVIDIA Software and Model Evaluation License. README:108 requires AI Enterprise for local NIM.<br>**The licence itself** (fetched, last modified 2025-02-26) allows use "only for internal test and evaluation purposes, without use in production and in systems with NVIDIA GPUs". It also grants NVIDIA a "perpetual, irrevocable" licence to "commercialize … any Derivatives created by or for you" | **CONFIRMED and STRONGER than V3 says.** V3 names the licence but not its production bar or its grant-back. One nuance runs the other way, see §2 a5 |
| 8 | No authentication and no TLS | `appendix/known-limitations.md`: inter-component connections "do not implement TLS/HTTPS"; "MCP servers and various tools lack authentication" | **CONFIRMED** |
| 9 | The trial terms forbid confidential data and allow training on what is sent | Trial Terms PDF (`pdfinfo`: created 2025-10-07):<br>§1.2 "limited trial purposes only and without use … in production";<br>§2.6(a) no "confidential information … personal data (unless expressly permitted by an API Service)";<br>§3.3(iv) NVIDIA collects "User Content and Generated Content to improve NVIDIA products and services, including AI models" | **CONFIRMED** |
| 10 | Cosmos3-Nano trails Qwen3-VL-8B on DocVQA, OCRBench-v2 and HallusionBench | Cosmos 3 report (arXiv 2606.02800, "Cosmos 3: Omnimodal World Models for Physical AI", 2026-06-01), Table 10, `pdftotext` lines 3101-3136: DocVQA 94.2 vs 95.6, OCRBench-v2 60.1 vs 64.1, HallusionBench 45.3 vs 50.5, VideoPhy2 45.6 vs 28.2, MVBench 73.2 vs 69.1. Report text: "Nano and Super are initialized from pre-trained Qwen3-VL weights" | **CONFIRMED**, including "its own base model". The table is vendor-run |
| 11 | `critic.py:131-254` holds the prompt and `:292-310` the verdict logic, under Apache-2.0 | `libs/vss/core/src/vss_core/search_core/critic.py` on `develop`, SPDX Apache-2.0 | **CONFIRMED** |
| 12 | The `vss-ask-video` ladder and fps rules | `skills/operations/vss-ask-video/SKILL.md`: route steps 1-8 at about lines 112-130, fps block at 210-228 | **CONFIRMED** |
| 13 | 24 skills "validated using Claude Opus 5" | `vision-agent/agent-skills.md:16`. There are 24 `SKILL.md` files under `skills/`; two more under `services/vios/.cursor/` are internal | **CONFIRMED, but V3 omits `agent-skills.md:15`:** "released as **Early Access** and are not intended for use in production environments" |
| 14 | LVS runs at about 13x real time on one H100 | `video-summarization-performance.md:59-63`: 60 min in 265 s, which is 13.6x (MEASURED arithmetic) | **CONFIRMED** |
| 15 | "VSS ships monthly: v3.3.0 came out 2026-10-21" | `gh api …/releases`: v2.4.1 2026-01-28, v3.1.0 03-18, v3.2.0 06-16, v3.2.1 07-23, v3.3.0 10-21. The gaps are 49, 90, 37 and 90 days | **WRONG.** Commits are continuous (last push 2026-10-24T03:07Z), but releases come every 1-3 months |
| 16 | "The search workflow is labelled 'alpha'" (R9:264) | "This is an alpha feature" appears in the **3.0.0** release notes (`release-notes.md:1072`). The 3.3.0 search page (`vision-agent/agent-workflows/search.md`, 1,645 lines) has 0 hits for alpha, beta or preview (grep) | **STALE**, and it undersells VSS. "No recall figure" still holds: `search-performance.md` has 0 hits for recall, precision or accuracy |
| 17 | "In our meeting work a channel router picked correctly on on-screen intent only 42.9% of the time (v2-spec.md:812)" | `v2-spec.md` has **no** "42.9" (grep, 0 hits). The figure is from `td-published-method.md:127` and `v2-reconciliation.md:393`, which quote **arXiv 2507.13374 Table 5** (CloudGlue's paper; a GPT-4.1 single-label router) | **MIS-ATTRIBUTED** (§3 b2) |
| 18 | P1, P2 and P3 have landed | PLAN:180 "P1 — Screens (done, 2026-10-08)", :233 P2 "(done, 2026-10-07)", :264 P3 "(done, 2026-10-08)" | **CONFIRMED** |
| 19 | The talk frames: Claude Code v2.1.52 with Opus 4.6 [16:15]; plan 0.74 s, reflect 1.06 s, trace 2.17 s [23:05]; LVS 277 s for 60 min [24:45] | Re-read `s0975.png`, `s1385.png`, `s1490.png` | **CONFIRMED** (MEASURED). How V3 interprets the numbers is a separate question (§3 b4) |

## 2. Direction (a): where V3 dismissed too fast

### a1. Hosted NIM endpoints: ruled out for the wrong reason in U1

V3 §1.2 says "Hosted use is ruled out" because of the terms on confidential data. That only binds *confidential* content. U1 is "any video", and the skill already sends public content off the machine to Gemini (SK:142-143).

- **What is hosted today** (MEASURED, page text from curl):
  - `build.nvidia.com/nvidia/cosmos3-nano-reasoner`: "Downloadable · Free Endpoint", and it accepts `.mp4`.
  - `build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`: "Input Modalities Video, Audio, Image, Text", "Free Endpoint Available", through an OpenAI-compatible `integrate.api.nvidia.com/v1/chat/completions`.
  - The Omni reference page (`docs.api.nvidia.com/nim/reference/nvidia-nemotron-3-nano-omni-30b-a3b-reasoning`, MEASURED text) gives these input limits:
    - video: "mp4, up to 2 minutes. For 1080p videos, sample up to 1 FPS / 128 frames … 720p … 2 FPS / 256 frames";
    - audio: "wav, mp3 files (up to 1 hour)".
- **What still limits it** (INFERRED reading of §1.2, §2.6(a) and §3.3(iv); not legal advice):
  - The service is for trial use only, and NVIDIA may train on what is sent.
  - "Personal data" is excluded unless the service expressly permits it. A talk or interview shows identifiable faces and voices.
  - So the clean case is content with no people in it: screen recordings, product demos, synthetic films. Meetings are excluded on every count.
- **Cosmos3-Nano hosted:** no reason to prefer it over Claude reading frames plus the Gemini tier, given Table 10 (INFERRED). U1b is unchanged.
- **Omni hosted:** this one has a real use.
  - It is free and hears and sees in one pass, so it bears on REPORT's paralinguistics hole: laughter could not be grounded (REPORT:37) and audio-event tagging is untested (REPORT:146, row 9).
  - It is cheaper to try than the local route V3 points to, a 30B model on mlx-vlm with unmeasured RAM.
  - It is not VSS, and the talk does not show it.
  - **Action (optional):** a one-hour probe on a clip that is people-free or self-owned. 40% that it is worth doing.

### a2. Cosmos Reason on Apple Silicon: a de facto path exists, and the ruling survives on better evidence

- **The talk's model can load where SK's Qwen3-VL loads** (INFERRED; not run):
  - The Cosmos-Reason2-8B card says the model is post-trained from Qwen3-VL-8B-Instruct "with the same architecture". It was tested only on Linux, needs at least 32 GB of GPU memory, and recommends "FPS=4 for input video to match the training setup". (DOCUMENTED. HF page read through WebFetch, because the raw README is gated.)
  - `hzang/Cosmos-Reason2-2B-4bit` has `architectures: Qwen3VLForConditionalGeneration` and `model_type: qwen3_vl`, and ships `video_preprocessor_config.json` (MEASURED, HF `config.json` and tree API).
  - `prithivMLmods/Cosmos-Reason2-8B-GGUF` has Q8_0 plus `mmproj` vision projectors and 1,558 downloads. There are also mradermacher GGUFs for 8B and `mlx-community/Cosmos-Reason1-7B-4bit` (MEASURED, HF API).
  - So V3's "no supported Mac path" is true only of NVIDIA support.
- **But it is a downgrade on our deciding axis.** NVIDIA's Table 10 (8B block, `cosmos3.txt:3101-3136`) compares Reason2-8B with Qwen3-VL-8B:

  | Benchmark | Reason2-8B | Qwen3-VL-8B |
  |---|---|---|
  | DocVQA | 94.3 | 95.6 |
  | InfoVQA | 79.8 | 83.4 |
  | **OCRBench-v2** | **56.6** | **64.1** |
  | **HallusionBench** | **42.0** | **50.5** |
  | VideoPhy2 | 37.1 | 28.2 |
  | MVBench | 70.1 | 69.1 |

  V3 cited only Cosmos3-Nano's row. The talk's own model loses more on OCR (-7.5) than Cosmos3-Nano does (-4.0). **U1b stays No.**
- **V3's 8% residual does not reach REPORT's 3-D spatial gap either.** REPORT row "3-D spatial reasoning" cites VSI-Bench and MMSI-Video. In Table 10, Cosmos3-Nano scores 54.9 vs 55.1 on VSI-Bench and 27.2 vs 28.8 on MMSIVideoBench.

### a3. MCP: nothing to overturn

- VA-MCP's tools (`docs/assets/static/va_mcp_tools.csv`, fetched) are `get_incident`, `get_incidents`, `get_sensor_ids`, `get_places`, `get_fov_histogram`, `get_average_speeds` and `analyze`.
  - All of them query an analytics database. None asks a question of a video.
- The Orchestrator MCP deploys the stack.
- The Docs MCP (`docs.nvidia.com/vss/_mcp/server`) serves documentation only.
- Everything except the Docs MCP needs a running deployment.
- Side note (MEASURED): the public tree carries NVIDIA-internal Claude Code config, `services/vios/.claude/commands/setup-maas-mcp.md`. That is an ecosystem signal only. I treated its content as data.

### a4. Cheap patterns V3 skipped

- **Drop near-duplicate frames before a local-VLM call.** This is Adaptive EVS's idea (`release-notes.md:67`) applied to our local VLM tier.
  - V3 says it is "the same idea as our luma diff". But SK uses luma diff only to find cuts.
  - SK:145-146 records the local VLM returning an empty generation at 9,732 tokens and working at 3,547.
  - Filtering frames on the luma diff already computed would take a few lines. INFERRED, 45%.
- **Supports B2:** Cosmos-Reason2's "FPS=4 … to match the training setup" is a second NVIDIA data point that VSS's 2 fps "inspect" ceiling is low.
- **Nothing else:** 3.3.0's BM25 search over VLM tags (`release-notes.md:128`) is a text channel over model output. That is B3's index idea, without OCR.

### a5. An organization-owned NVIDIA box for U2

- DGX Spark runs `dev-profile-base` with a local LLM and RT-VLM on one GPU (`prerequisites.md:413-420`). A desk-side box the company owns would count as "organization-hosted" (SESSION-STATE.md:75-76).
- **Still No:**
  - The evaluation licence bars production; production needs AI Enterprise (README:108; talk [30:05]).
  - There is no ASR and no screen OCR.
  - LVS is not supported on edge platforms (`prerequisites.md:446-447`).
  - Our meeting experiments measured pictures as the minor channel: "Images added 1.5 points of 18 … not distinguishable from zero (p = 0.50 and 0.25)" (v2-spec.md:21). VSS is a stack for the visual channel.
- **A licensing nuance that runs the other way:** README:166 says Apache-2.0 applies to "the repository", and the repository contains microservice source under `services/` (MEASURED, tree). Building from source might avoid the *container* evaluation licence for some components. DeepStream, TensorRT and the NIMs keep their own terms (INFERRED, untested). This does not matter for the Mac.

## 3. Direction (b): where V3 oversells

### b1. B1, the per-criterion critic: 80% is too high, and it is aimed at errors it cannot fix

1. **What the VSS critic is.** It "verifies search results" (`search.md:42`, `:1435`). It is a precision filter applied to each retrieved clip, with criteria taken from the query.
   - Its prompt forbids criteria that come from what is visible: "Never add a criterion that merely describes what you see" (`critic.py:150`).
   - Our 5 errors were details inside *descriptive* answers. Q19 asks "What is his face and hand posture while it plays?" (`/tmp/vu-2026-10-23/exam-questions.md:41`). That has no true/false criterion.
   - Catching "lips closed" requires a criterion drawn from the *answer*, which the VSS prompt rules out.
2. **Error by error** (from V3's own cites):
   - **Q3, Q12, Q18 (audio inferences).** SK's numeric-probe prose already covers them (SK:154-158), and REPORT row 4 claims the same three (REPORT:141). B1 counts them a second time.
   - **Q23.** E2b sampled 46:56.0, 56.6, 57.2, 57.8 and 58.3 (E2b:116). The knuckle contact is at 46:58.00 (E3 audit A6), between two samples. That is a **sampling miss**, which is B2's job.
   - **Q19.** E2b read 2 frames, t=2154.6 and 2155.8 (E2b:112). The auditor used **2x crops** of the webcam bubble at 4 instants and saw teeth in 3 (E3:233). That is a read of a small region, so the fix is a crop rule, not a criterion check (INFERRED).
   - **Net:** the VSS mechanism directly addresses 0 of the 5 (INFERRED). A rule of "one fresh piece of evidence per claim" would address Q19 and Q23.
3. **No evidence the critic works.**
   - The talk claims "increased precision with the VLM verification" [23:05] and gives no number.
   - `search-performance.md` has no precision or recall figure (grep).
   - Today's web search found no third-party evaluation of VSS.
4. **The literature cuts against re-judging.**
   - Intrinsic self-correction without external feedback often does not help and can hurt (Huang et al., arXiv 2310.01798, abstract fetched).
   - Verification helps when the checks are answered independently (Chain-of-Verification, arXiv 2309.11495, abstract fetched).
   - For Claude acting as its own critic, any gain has to come from **new evidence**: a new crop, a denser step, a probe number. Re-judging the same frames will not supply it.
5. **The validation plan is underpowered.** On 5 items one flip moves the score by 20 points, against REPORT's 8-point noise warning (R5 §3). Use every sub-claim stated at confidence 70 or more across the 24-item exam, or a fresh exam.

**Recommendation:** reframe B1 as **a claim-level re-check with fresh evidence**.
- List the answer's checkable sub-claims, at most 3.
- Fetch one new piece of evidence for each:
  - a 2x crop for small regions;
  - a step of 0.25 s or less around contact events;
  - a probe number for audio.
- Mark anything not re-confirmed UNVERIFIED.
- Credit VSS for the `subject:` anchor and the UNVERIFIED state (Apache-2.0), and CoVe for the method.

Conviction: 45-50% for V3's version, ~65% for the reframed one.

### b2. B4's 42.9% figure is mis-sourced, and VSS does not do what V3 says

- **The figure is not ours.** It comes from CloudGlue's paper (arXiv 2507.13374, Table 5): a GPT-4.1 single-label router sent OCR-intent queries to OCR 42.9% of the time (`td-published-method.md:127`). That is a vendor's self-reported experiment, not "our meeting work". The cite `v2-spec.md:812` does not contain it.
- **VSS does not pick one channel.** Its router applies deterministic rules to fields the LLM extracts, and one of its routes is `fusion`, which searches both. On H100 it chose `fusion` for 52 of 121 queries (`search-performance.md:49`, `:74-78`). V3's "do not copy its rule-based choice of one channel" mischaracterises it.
- B4's substance, "always search both", stays right. Conviction ~55%.

### b3. U3's supporting claims

- **"Ships monthly"** is false (§1 #15). Better: "5 releases in 2026, 37-90 days apart; commits daily".
- **"The strongest Claude Code integration of any GPU stack"** names no comparison set (INFERRED claim). It also omits that the skills are "Early Access … not intended for use in production environments" (`agent-skills.md:15`).
- **"Alpha"** is stale (§1 #16). This one *undersells* VSS.
- **Scope.** The "first choice" ranking was made only against R5's research systems: DVD, MMCTAgent and VideoRAG. R6:48 names Azure Video Indexer's Arc edition as an on-premises indexer (not re-fetched today). For camera fleets VSS still leads (INFERRED). For organization-hosted meeting video with ASR and OCR, VSS is not the comparator.

### b4. Two of the talk's "contradictions" are partly unfair

- **"60x to 100x"** [6:48]. Today's docs give these times on the 4×4 H100 topology (8 GPUs; `video-summarization-performance.md:42-48`):

  | Video | Time | Speed |
  |---|---|---|
  | 60 min | 64.7 s | 55.6x |
  | 120 min | 119 s | 60.5x |
  | 720 min | 615 s | 70.2x |

  (MEASURED arithmetic.) The slide's 277 s (s1490) is a single-GPU figure. The fault is **unstated hardware, 8 GPUs against 1**, not a contradiction. Note that the docs' run used VSS 3.2 with Cosmos3, not the talk's 3.0 with Reason2.
- **"The plan and reflect adds some latency, but it's still under a second"** [23:05]. This reads plausibly as each step: 0.74 s and 1.06 s. V3 takes it as their sum, 1.8 s. Weak evidence either way.
- **The discount that holds:** the talk gives no accuracy number at all, including for the critic's claimed precision gain.

### b5. U2 rests on the weakest of the available reasons

- **V3's reason is internal.** "The converter's contract" cites agentsync's own non-goals (v2-spec.md:79-90), which the team can revise.
- **The argument misplaces the VLM call.** A VSS VLM call would sit in the *answering* layer, beside Claude's keyframe reads, not in the evidence package.
- **Stronger reasons exist outside the project** (all re-checked today):
  - the evaluation licence's bar on production (§1 #7);
  - keyframes measured as the minor channel, 1.5 of 18 points (v2-spec.md:21);
  - the 1280x720 default VLM input (§1 #6);
  - no ASR and no screen OCR (§1 #5).
- The ruling is unchanged, and the conviction goes up.

### b6. U4: the yt-dlp "new failure mode" is overstated

- `/tmp/vss-talk-2026-10-24/dl.log:1` reads "WARNING: Your yt-dlp version (2026.07.04) is older than 90 days!" (MEASURED). That is the same root cause SK:52 already names: "check yt-dlp is CURRENT".
- **What is new:**
  - the symptom: HTTP 403 on the media;
  - the **partial-success trap**: both subtitle tracks were written (`dl.log:8-17`) before the 403 (`dl.log:18`).
- Action 1 is still worth doing. Reword it as "a new symptom plus a trap", not a new cause.

### b7. Small citation slips

- **B2's Q23 cite:** V3 has "resolved at a 0.4 s step (E3-judgement.md:176)". Q23 is at E3:177, and the audit's frames are 0.15-0.25 s apart (E3 A6 table).
- **REPORT row cited for B5:** REPORT:134 is the preamble of the borrow table. It does say the `/tmp` scripts will not survive a reboot, so the substance stands.

## 4. Changes to V3's action list

| V3 # | Change |
|---|---|
| 1 (yt-dlp) | Keep. Reword as "symptom: HTTP 403 after the subtitles succeed; cause: a stale build; trap: falling back to transcript only" |
| 2 (B1) | **Reframe** as a claim-level re-check that fetches fresh evidence per claim (§3 b1). Validate on 20 or more sub-claims, paired, twice. Credit CoVe for the method and VSS for the schema |
| 3 (B5) | Keep. The three probes are 416, 719 and 1,620 bytes (MEASURED `ls -la`). Trivial |
| 4 (B2) | Keep. Add "crop small regions to 2x before claiming facial or hand detail", which is what fixes Q19 |
| 5 (B3, B4) | Keep. Fix the 42.9% citation and drop "rule-based choice of one channel" |
| new | Optional: one-hour probe of the free Omni endpoint on a clip that is people-free or self-owned, for audio events and laughter (40%) |
| new | Optional: drop near-duplicate frames by luma diff before local-VLM calls (45%) |
| synthesis | Replace "ships monthly" and drop "alpha". Add the Early Access, not-for-production caveat. Edge platforms run search too, with remote models. "No OCR" becomes "no screen or document OCR" |

## 5. Caveats

- No VSS component, CLI, model or endpoint was run, here or in V1-V3. Every capability claim about Omni and Cosmos is DOCUMENTED.
- Table 10 and the Reason2 card are vendor-run benchmarks.
- I read the Reason2-8B card through a WebFetch summary, because the raw README is gated. Its VideoPhy2 figure (36.8 vs 28.24) agrees with Table 10 (37.1 vs 28.2) to within 0.3 points.
- The readings of the trial terms and the evaluation licence are mine, not counsel's.
- One web search ("NVIDIA VSS … independent evaluation … 2026") found only NVIDIA pages. Absence from one search engine bounds that search, not the world.
- `/tmp/v4-skeptic-src/`, `/tmp/vss-talk-2026-10-24/` and `/tmp/vu-*` will not survive a reboot.

## Sources

- **Repo:** https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization (`develop` at today's fetch). Files: releases API, recursive tree, `README.md`, `libs/vss/core/src/vss_core/search_core/critic.py`, `skills/operations/vss-ask-video/SKILL.md`, `libs/vss/cli/README.md`, `deploy/docker/developer-profiles/dev-profile-lvs/vss-agent/configs/config.yml`, `deploy/docker/services/video-summarization/configs/config.yaml`, `deploy/docker/industry-profiles/warehouse-operations/warehouse-3d-app/deepstream/configs/config-ocr.yaml`, `services/rtvi/rt-vlm/docker/rtvi_vlm/patches/apply_vllm_{parakeet_transformers5,qwen3_omni_audio}_patch.py`, `docs/assets/static/va_mcp_tools.csv`, `docs/api-gateway-mcp.mdx`
- **VSS 3.3.0 docs** (`.md` exports): https://docs.nvidia.com/vss/3.3.0/getting-started/quickstart.md, …/getting-started/prerequisites.md, …/vision-agent/agent-skills.md, …/appendix/license-information.md, …/appendix/known-limitations.md, …/appendix/performance/agent-workflows/video-summarization-performance.md, …/appendix/performance/agent-workflows/search-performance.md, …/vision-agent/agent-workflows/search.md, …/vision-agent/agent-workflows/video-summarization.md, …/release-notes.md
- **Licence and terms:** https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-and-model-evaluation-license/ ; https://assets.ngc.nvidia.com/products/api-catalog/legal/NVIDIA%20API%20Trial%20Terms%20of%20Service.pdf
- **Hosted endpoints:** https://build.nvidia.com/nvidia/cosmos3-nano-reasoner ; https://build.nvidia.com/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning ; https://build.nvidia.com/nvidia/video-search-and-summarization ; https://docs.api.nvidia.com/nim/reference/nvidia-nemotron-3-nano-omni-30b-a3b-reasoning
- **Hugging Face:** https://huggingface.co/nvidia/Cosmos-Reason2-8B ; https://huggingface.co/api/models/nvidia/Cosmos3-Nano ; …/nvidia/Cosmos-Reason2-2B ; …/hzang/Cosmos-Reason2-2B-4bit (config.json) ; …/prithivMLmods/Cosmos-Reason2-8B-GGUF (tree) ; …/Hob-forge/Cosmos3-Nano-GGUF ; HF search API for `cosmos-reason`, `cosmos3` and `Cosmos-Reason1`
- **Cosmos 3 report:** https://research.nvidia.com/labs/cosmos-lab/cosmos3/technical-report.pdf ; https://arxiv.org/abs/2606.02800 (Table 10; architecture text at `cosmos3.txt:885-894`)
- **Papers:** https://arxiv.org/abs/2310.01798 (self-correction) ; https://arxiv.org/abs/2309.11495 (Chain-of-Verification) ; https://arxiv.org/abs/2503.05977 (VLM-as-judge reliability; general caution only)
- **Web search:** "NVIDIA VSS video search summarization blueprint independent evaluation accuracy review 2026". Hits included https://docs.nvidia.com/vss/2.4.0/content/byov_accuracy_eval.html (NVIDIA's own harness, not an evaluation)
- **Local:** V1, V2, V3, R5 §2, R6:48 and R9:264 in this directory; `docs/research/video-understanding-human-parity-2026-10-23/{REPORT.md,agents/E3-judgement.md,agents/E2b-watcher-full-pipeline.md}`; `skills/video-understanding/SKILL.md`; `~/.claude/research-artifacts/meeting-video-2026-10-06/{v2-spec.md,SESSION-STATE.md,td-published-method.md,v2-reconciliation.md}`; `~/Development/agent-context-sync/docs/plans/meeting-video.md`; `/tmp/vss-talk-2026-10-24/{dl.log,hires/s0975.png,hires/s1385.png,hires/s1490.png,asr.txt}`
