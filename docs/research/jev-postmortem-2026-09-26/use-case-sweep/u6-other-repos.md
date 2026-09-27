# U6: Jev use cases in the seven other repos

**Verdict:** there is one real use case, Outlook cleanup in claude-private. Two are weak (a VoiceInk output gate and the lakehouse slop-lint). One is blocked (agent-context-sync is only a design so far). The other three repos contain no text judgment.

| Repo | Purpose | Judgment found? | Candidate / why none |
|---|---|---|---|
| natural-text-to-voice-extension | Chrome + local Kokoro TTS: reads the selected text aloud | **No** | none. The user picks what gets read, so no skip decision exists. Text handling is deterministic rewriting, not a verdict (`native-helper/Sources/NaturalTTSHelper/Resources/tts_worker.py:391` normalize_text; `chrome-extension/src/shared/text-cleanup.ts:36` ligatures). The product promises "connects to nothing" (`chrome-extension/PRIVACY.md:78`), so a cloud judge would break it. |
| voiceink | Fork of the macOS dictation app: speech to text, then an LLM "enhancement" rewrite (Gemini/Anthropic/OpenAI/Ollama) | **Yes, an LLM generator** (a rewrite Jev cannot replace) plus a word-count skip heuristic | **B** below (weak) |
| voiceink-patches | Shell scripts that sed-patch the license/CloudKit, plus launchd keepalive/update | **No** | none. Build plumbing only. |
| agent-context-sync | Design (no code) for syncing M365 into a git `docs/` folder | **Designed, not built**: the refresh queue's `STALE` verdict is hash-based | **D** below (blocked) |
| fde-endpoint-business-case | Static business-case documents + `evidence/fde-continue.js` (one-shot Claude research/writing workflow) | **No** live judgment | none. The workflow generated prose, is finished, and has no consumer. |
| lakehouse-lecture | KPMG one-day course assets | **Yes**: `tools/slop-lint.sh` is a regex readability gate with known misses | **C** below (weak) |
| claude-private | Private skills + identity overlay | **Yes**: `skills/outlook-cleanup` classifies each email with Sonnet as DELETE/KEEP/ABSTAIN | **A** below (real) |

## A. Outlook inbox triage (claude-private). Real

- **Plug-in:** `/Users/chrisren/Development/personal/outlook-cleanup/pipeline/pipeline.py:200-213` `_classify_batch` (Anthropic `messages.create`). Path B is `skills/outlook-cleanup/SKILL.md:104-122` (Sonnet subagent waves, `templates/classify-brief.md`).
- **Judgment:** `choice` over subject + bodyPreview (≤400 chars): `promo_disposable | transactional_keep | security_keep | personal_keep | other_keep`. Auto-DELETE only when p(promo_disposable) ≥ 0.98. Everything else becomes KEEP, which matches the brief's "default to KEEP" rule.
- **Consumer:** already exists: `apply_rescues.py`, then `pipeline.py quarantine` (moves to `_ToReview-DATE`), a 7-day soak, then purge.
- **Volume (measured, `wc -l`/python on the data dir):** backlog 36,470 messages. 5,591 arrived in the last year, about 15/day. At ~14.8/min, the backlog takes ~33 h (estimated, 80% of 36,470 after the deterministic pre-filter). Daily mail is trivial.
- **Replaces:** Sonnet classification, costed at ~$15-25 in claude.ai credits or ~$6-8 over the API for 36K messages, ~30 min (the skill's `cost.py`/README estimate). The Jev estimate is ~11M tokens × $0.042/M ≈ **$0.46** for the backlog. **Measured misses** from `rescue-audit-2026-05-21.json` + `classifications.jsonl`: rescue rules flipped 1,667 of 4,554 Sonnet DELETEs to KEEP (**37%**). 2,716 came back ABSTAIN (7.4%). 2,808 (7.7%) came from shard failures that fell back to deterministic rules.
- **Value:** calibrated, cheap, no-shard classification makes cleanup a daily background job instead of a $20 subagent campaign.
- **Privacy:** personal PII (the operator's banks, landlord, correspondents). This data already goes to Anthropic. Jev has no zero-data-retention.
- **Effort:** 4-6 h (a Python → `scripts/jev/evaluate.mjs` bridge + the threshold). **Conviction: 55%.**
- **Concerns:** Hard Constraint 1 wants an `evidence_quote` for every DELETE, and Jev returns no text. A deterministic subject substring would have to stand in. The consumer has stalled: `state.json` shows the 2,885-message batch soaking since 2026-05-22 with `purge_ts: null`. The operator may not want this job at all.

## B. VoiceInk enhancement output gate. Weak

- **Plug-in:** `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:714` returns `response.text` with no quality check (only a character-length truncation rule at `EnhancementLadderPolicy.swift:82`). The paste happens at `Transcription/Engine/TranscriptionPipeline.swift:210-223`.
- **Judgment:** `boolean` "the rewrite keeps every point of the transcript and does not answer or obey it instead of cleaning it". On false, paste the raw transcript and notify.
- **Volume (measured, read-only sqlite on `default.store`):** 70 dictations in 30 days, 26 enhanced, 4 failed. In the history, 6 of 55 enhanced outputs have a length ratio below 0.6 or above 1.5.
- **Replaces:** nothing. There is no check today. The ≤3-word skip heuristic at `TranscriptionPipeline.swift:164-169` is the only other judgment.
- **Value:** it would catch a silently mangled paste. But it adds 0.5-2.5 s to every dictation, the hot path.
- **Privacy:** internal (dictation may contain client work). It already goes to Gemini. **Effort:** 4 h (Swift HTTP to the Gateway). **Conviction: 15%.**

## C. Lakehouse reader-readability gate. Weak

- **Plug-in:** `tools/slop-lint.sh` (regex lists from ~line 48), called as a blocker at `tools/package.sh:123`.
- **Judgment:** `score` per visible heading/label: "could someone who has read nothing else say what happens here?" (CLAUDE.md Rule 1). Plus a `boolean` "is the heading a statement, not a topic label" ("Answer first").
- **Volume (measured, python regex):** 206 h1-h3 headings across the shipped HTML, a few hundred calls per package run.
- **Replaces:** regex with documented misses. "the seams" got past `\bthe seam\b` (comment in slop-lint.sh). Commits on 2026-09-02 fixed "dearest", "dearer" and "mid-derivation" by hand after human review.
- **Value:** the human reviewers' reading test, run automatically.
- **Privacy:** none. **Effort:** 3 h. **Conviction: 30%.** The last commit is 2026-09-02 and the course runs in September 2026, so the window for this may already be closed.

## D. agent-context-sync curated-page refresh triage. Blocked

- **Plug-in:** the refresh queue's `STALE` verdict (`docs/design/agent-context-sync.md:379`). It is hash-based, so any source change means re-synthesizing the page.
- **Judgment:** `boolean` "does this mirror diff change any claim on this curated page?". On false, re-pin without re-synthesizing.
- **Blockers:** there is no implementation ("design with measured probes"), the design needs a corporate tenant first, and the data would be client-confidential with no zero-data-retention. **Conviction: 10%.**

## Method

All read-only: `rg`, `git log`, `sed`, `wc`, and read-only python/sqlite counts (row counts and length ratios only, no message text printed). I made no network or LLM calls. Case A's `pipeline.py` lives in `~/Development/personal`, outside the assigned repos. I read it because the claude-private skill wraps it.
