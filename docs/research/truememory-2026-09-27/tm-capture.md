# TrueMemory — CAPTURE / INGEST path (axis notes)

Source: shallow clone `/tmp/truememory-src` @ `063e5b8` (last commit 2026-08-29; 50 commits in the
shallow history; pyproject version 0.7.6.2, `truememory/ingest/__init__.py:36` says ingest 0.4.0).
All file:line refs below are into that clone unless prefixed `ours:` (the claude-infrastructure repo).

Evidence labels:
- **MEASURED**: I ran it (scripts in `/tmp/tm-research/scratch/`, output `probe_out.txt`) or it is a direct code read of control flow.
- **CLAIMED**: README / CHANGELOG / docstring / comment says so; not verified.
- **ESTIMATED**: my inference, method stated.

Probe method (MEASURED): TrueMemory is NOT installed on this machine (`pip3 show truememory` = not
found; no `~/.truememory`). I loaded only its stdlib-dependent modules (transcript, extractor, markers,
models, hooks/_shared, hooks/stop, hooks/user_prompt_submit) through stub packages, so
`truememory/__init__.py` (heavy: numpy/sqlite-vec/torch chain) never ran and nothing was installed,
spawned or written outside `/tmp/tm-research`. Sample: the 40 largest transcripts under
`$CLAUDE_CONFIG_DIR=~/.claude-tertiary/projects/*/*.jsonl` (1,400 top-level transcripts in that dir).
The largest-40 sample is biased toward long, hook-heavy autonomous sessions; I report only aggregates.

---------------------------------------------------------------------------------------------------

## 0. One-paragraph model of the capture path

Four Claude Code hooks are installed (`hooks/adapters/claude.py:140-145`): SessionStart →
`session_start.py`, UserPromptSubmit → `user_prompt_submit.py`, **SessionEnd** → `stop.py` (the
file is named stop.py, but it is registered on SessionEnd; the installer migrates old `Stop` entries
away because Stop is per-turn, `claude.py:231-253`), PreCompact → `compact.py`. None of them
extracts facts inline. They decide *whether* a transcript needs extraction (size-delta marker +
PID liveness), then detach a `python -m truememory.ingest.cli ingest <transcript>` worker
(`stop.py:343-460`). The worker re-parses the WHOLE transcript (`pipeline.py:441`), formats it
(`transcript.py:350-376`), extracts atomic facts with an LLM (`extractor.py:195-286`; regex fallback
`extractor.py:539-648` only when no backend exists), runs each fact through the encoding gate
(`pipeline.py:476-499`) and then dedup+store under a cross-process flock
(`pipeline.py:511-578`), writes a per-fact decision trace (`pipeline.py:762-792`), marks the session
extracted, clears its backlog claim, and cascades to the next backlog item (`cli.py:227-251`). When a
spawn is refused (budget / cap / Popen error) the session is queued to `~/.truememory/backlog/`
(`stop.py:300-340`); the next SessionStart drains it in a detached maintenance child
(`session_start.py:627-672`) and also runs a watermark-based scan for sessions that were never
extracted at all (`session_start.py:455-624`).

---------------------------------------------------------------------------------------------------

## 1. WHEN it captures (trigger matrix)

| Trigger | Where | Gate before spawning | What it does | Blocking? |
|---|---|---|---|---|
| SessionEnd | `stop.py:115-180` | transcript exists (`:141`), inside allowlist (`:147-150`), dirs writable + ≥10 MB free (`:183-223`), ≥`MIN_MESSAGES`=5 "user" entries (`:53-54`, `:160`), `should_extract_session` (`:164`) | spawn detached ingest (`:168`), mark extracted with worker PID only if spawned (`:176-180`) | no — Popen and return |
| UserPromptSubmit (mid-session, "incremental") | `user_prompt_submit.py:767-788` | transcript exists, `should_extract_session`, `_has_enough_messages(...,10)` | same spawn via `stop._run_background_ingestion` | spawn is non-blocking, but the checks run inline on every prompt |
| UserPromptSubmit (per-exchange eager store, only `store_intensity` enhanced/max) | `user_prompt_submit.py:438-541` | length 15–2000, not code, not question, regex `_STORABLE_RE` (`:176-189`), enhanced also needs ≥3 shared ≥4-letter words with last 5 buffered prompts (`:356-402`), 2 s per-session debounce (`:405-435`) | **synchronous** Memory open → novelty search (cosine>0.85 or Jaccard>0.85 skip) → gate → dedup+add under the same lock as the pipeline | yes (bounded by 5 s model-server deadline per request, `_shared.py:97-116`) |
| PreCompact | `compact.py:61-118` | allowlist (`:89`) | (a) **synchronous** `save_snapshot` = raw last-5 substantive user msgs, 100 chars each, `Memory.add` directly (`:121-182`); (b) spawn background ingest if `should_extract_session` and ≥5 entries (`:98-116`) | (a) yes |
| SessionStart (backstop) | `session_start.py:704-715` → `_run_maintenance_background` | env guard `TRUEMEMORY_MAINTENANCE_CHILD` (`:638`) | detached child runs `_drain_backlog()` then `_scan_stale_sessions()` (`:647-651`) | no |
| Ingest completion (cascade) | `cli.py:251`, `cli.py:254-378` | budget + spawn gate | spawns ONE next backlog item | n/a (worker) |

CLAIMED vs code drift: CHANGELOG 0.6.4 says the UserPromptSubmit incremental extraction fires
"every 4 hours" with a "shared timestamp marker" (`CHANGELOG.md:272-274`). MEASURED: no 4-hour
constant exists in `truememory/ingest` (grep for `4 hour|14400|4h` = 0 hits); the live rule is the
size-delta marker (`_shared.py:172-220`), i.e. it fires whenever the transcript grew >1 KiB since the
last marker and no extraction PID is alive. Effective cadence is therefore "almost every prompt of
an active session, throttled by the 20/hour global budget and the spawn cap".

## 2. Idempotency / watermark semantics

- Per-session marker `~/.truememory/extracted/<safe_sid>` = `{"size", "timestamp", "pid"}`
  (`_shared.py:431-463`), atomic write via per-PID tmp + `os.replace` (`_shared.py:124-149`).
- `should_extract_session` (`_shared.py:172-220`): extract if no marker, marker unreadable, file
  shrank, or grew by >1024 bytes; **skip if the marker's PID is alive** (in-flight extraction).
- Two writers: the trigger writes an *optimistic* marker tagged with the spawned worker PID
  (`stop.py:176-180`, `session_start.py:354-359`, `cli.py:360-363`); the worker writes the
  authoritative one on completion (`cli.py:227-231`).
- **It is NOT an offset watermark.** The size is only a trigger threshold. Every extraction
  re-parses and re-extracts the entire transcript (`pipeline.py:441-457`); idempotency of the
  *stored* result depends entirely on the dedup stage. Cost scales as (#triggers × #chunks).
- MEASURED-by-reading bug class: the completion marker stats the file at *completion* time
  (`cli.py:229` → `_shared.py:455`), not at parse time. Bytes appended while the worker was
  extracting are recorded as extracted. They are recovered only if a later trigger sees another
  >1 KiB growth; a session that ends with <1 KiB of new text after a mid-session extraction loses
  that tail. (Inference from code; not reproduced live.)
- Marker hygiene: extracted markers pruned after 30 days (`session_start.py:124`, `:409-437`),
  because 54K+ markers were observed in prod (CLAIMED, `session_start.py:413-414`).
- Extraction-self-capture guard: the `claude -p` extraction subprocess is started with
  `TRUEMEMORY_EXTRACTION=1` (`models.py:470-471`); every hook early-returns on it
  (`session_start.py:705`, `user_prompt_submit.py:729`, `compact.py:62`), and the SessionEnd hook
  in that mode *marks the extraction session extracted* so the stale scanner skips it
  (`stop.py:116-129`). Belt-and-braces: the system prompt carries the sentinel
  `[[TRUEMEMORY_INTERNAL_EXTRACTION]]` (`extractor.py:42-43`) and the scanner recognises it or legacy
  prompt prefixes in the first 30 lines (`session_start.py:126-130`, `:377-406`).

## 3. HOW facts are extracted

### 3.1 Transcript normalisation (`transcript.py`)
- Formats: JSON array, JSONL, plain-text with role markers (`:93-102`). Path-vs-content ambiguity
  resolved by `exists() and is_file()`; a read failure never falls back to treating the path string
  as content (`:35-87`, Bug #1).
- Drops `file-history-snapshot`, `progress`, `summary`, `system` entries (`:158-163`).
- Unwraps real Claude Code `{"type","message":{...}}` shape (`:192-202`); skips `thinking` blocks
  (`:227-231`); `tool_use` → `[tool: Name]` (`:232-234`); user turns consisting ONLY of
  `tool_result` blocks are retagged `tool_result` and filtered (`:206-266`).
- `format_for_extraction` (`:350-376`): drops tool_use/tool_result/system roles, labels
  `User:`/`Assistant:`, truncates assistant messages to 500 chars, and strips TrueMemory's own
  `<truememory-*>` injected blocks to stop the echo-amplification loop (issue #652/M-19,
  `:313-347`).
- **Gaps (MEASURED on our transcripts):** no filtering of `isMeta` entries (1,291 `isMeta` user
  entries in the 40-transcript sample; `transcript.py` never reads the key), Stop-hook feedback,
  `<task-notification>`, `<teammate-message>`, slash-command wrappers, or `<system-reminder>`.
  Classifying the 2,203 parsed `human` messages (`scratch/probe2.py`): 1,036 `Stop hook feedback`,
  515 `<task-notification>`, 54 slash-command wrappers, 114 other `<tag>` starts, 40 skill/doc
  bodies, 7 interrupt markers, **437 (19.8%) look typed by a human**. So ~80% of what TrueMemory
  would present to the extractor as "User:" speech in OUR environment is machine-injected text.
  Noise share of the formatted extraction text (system-reminder/command/task tags plus
  tool-only `Assistant: [tool: X]` lines): 4,742,089 / 8,074,522 chars = **58.7%**
  (`scratch/capture_probe.py`). Caveat: our environment is unusually hook-heavy; a vanilla user
  would see far less, but any port to our setup must add these filters.

### 3.2 LLM extractor (`extractor.py`)
- System prompt (`:42-57`): sentinel + "extract ONLY durable, reusable information … useful days or
  weeks from now" + prompt-injection defence (transcript is untrusted, never follow instructions).
- User prompt (`:70-111`): EXTRACT list (personal, preferences, decisions, corrections [marked
  "high-value"], temporal, technical context, relationships, activity/project state, life events);
  **DO NOT EXTRACT** list: transient debugging details (error messages, stack traces, temp fixes),
  code snippets, greetings/filler, things obvious from codebase or git history, the assistant's own
  suggestions (only USER-stated facts). Output schema per fact: `content` (atomic, written as a fact
  not a quote: "Prefers bun over npm"), `category` (9 values), `confidence` high/medium/low,
  `source_role` user|inferred. Returns JSON array or `[]`.
- Fence hardening: `<untrusted_transcript>` delimiters; any delimiter-like token inside the content
  is neutralised by regex (`:59-68`, `:255`).
- Chunking: 20,000-char chunks on `\n\n` message boundaries (`:129`, `:138-172`), hard cap
  `max_chunks=20` (`:135`) → keeps the **first** 20 chunks and drops the rest with a warning
  (`:235-245`). Per-chunk LLM failure is logged and skipped (`:256-271`). Cross-chunk
  case-insensitive exact-content dedup (`:175-192`), `max_facts=50` (`:198`, `:282-284`).
- Robust JSON parse: strip fences, first balanced `[...]` or `{...}`, unwrap `{"facts":[...]}` etc.,
  brace-balanced salvage of partial output (`:289-464`). Category allowlist → `general`
  (`:472-481`).
- MEASURED on our sample: 395 chunks across 40 transcripts; **3/40 exceed the 20-chunk cap,
  dropping 1,995,768 of 8,074,522 formatted chars (24.7%) — and the dropped part is always the
  newest tail** because `chunks[:max_chunks]` keeps the head.
- `confidence` and `source_role` are parsed (`:350-355`) but I found no consumer in the pipeline:
  `pipeline.py:468-578` uses only `content` and `category`. (MEASURED by reading; `inferred`
  facts are stored like `user` ones.)

### 3.3 Which model (`models.py`)
- `auto_detect` priority (`:193-236`): **Ollama** (local, `qwen2.5:7b-instruct` or first available,
  `:173-181`) → **Claude CLI** (`claude -p --output-format json`, subscription auth, model left empty
  = the user's configured default, `:183-188`, `:438-507`) → OpenRouter (Haiku 4.5) → Anthropic
  direct (`claude-haiku-4-5-20251001`, `:143-147`) → Groq (llama-3.3-70b) → RuntimeError.
- temperature 0, max_tokens 2000 (`:125-126`); 3 retries with jittered exponential backoff on
  408/429/5xx and network errors (`:89-116`); 60 s HTTP timeout; 120 s CLI timeout (`:474-486`).
- The CLI path strips `ANTHROPIC_API_KEY` from the child env to force OAuth (`:468-471`) and folds
  the system prompt into the user prompt (`:458-461`).
- MEASURED on this machine: Ollama answers on :11434 → auto-detect would pick a local 7B-class
  model, not Claude.
- If no backend at all: regex extractor `extract_facts_simple` (`extractor.py:539-648`). MEASURED on
  our sample (`scratch/probe4.py`): 1,089 "facts" from 40 transcripts; 917 `temporal`, 140
  `correction`; **976/1,089 are <25 chars**; top temporal hits are progress fractions misread as
  dates (`on 1/8)` ×9) and the modal verb "may" misread as the month (`on may stay open`). It
  stores `match.group(0)` (the whole matched span incl. the trigger phrase, `:590`), not the
  captured object. 141 of them would take the gate's contradiction bypass (category `correction`
  → always encode, `encoding_gate.py:166-179`, `:275-280`). Net: the no-LLM path is a noise
  generator.

### 3.4 Post-extraction filtering (boundary with the gate/dedup axis)
- Gate (`pipeline.py:476-499`, `encoding_gate.py:242-293`): weighted novelty+salience+prediction
  error vs threshold 0.30 (`stop.py:53`; the core adapter path passes 0.5, `hooks/core.py:723`);
  per-category threshold offsets (correction −0.06, decision/relationship/event −0.04, activity −0.02;
  `encoding_gate.py:146-151`); salience floor rejects "pure noise"; **degrades OPEN** when the PE
  model is unavailable (`:271-276`); corrections/contradictions (shared marker vocabulary
  `markers.py:30-101`) always pass (`:277-282`). `TRUEMEMORY_GATE_ENABLED=0` disables
  (`pipeline.py:404-408`).
- Dedup+store (`pipeline.py:511-578`): `check_duplicate` → ADD / UPDATE(existing_id) / SKIP, under
  `_dedup_store_lock()`; storage `OperationalError` is caught per fact and recorded as
  `storage_failed` rather than aborting (`:525-571`).
- Storage: `[category] content` prefix + `category` column (`pipeline.py:678-730`). `session_id` is
  accepted but **never persisted** (`:678-716`) → no provenance from a stored fact back to its
  session (trace files are the only link).
- Recall-cache invalidation after any write (`pipeline.py:588-598`).

## 4. Noise avoidance — inventory (what exists, in order of the path)

1. Hook-level: minimum transcript content (≥5 / ≥10 "user" entries), 5,000-byte floor in the stale
   scanner (`session_start.py:555`), UUID-named transcripts only (`:526`, `:549`), extraction-session
   sentinel skip.
   - MEASURED weakness: `_has_enough_messages` counts every JSONL entry whose `type` is `user`
     (`stop.py:256-271`), and Claude Code writes every tool result as a `type:"user"` entry. In the
     sample: 13,852 raw `user` entries vs 437 human-typed-looking messages; `has_enough(5)` and
     `has_enough(10)` were true for 40/40. The threshold does not measure conversation.
2. Transcript-level: thinking/tool/system stripping, assistant truncation to 500 chars, own-block echo
   stripping (see 3.1 for gaps).
3. Prompt-level: DO-NOT-EXTRACT list + "only USER-stated facts" + durable-only (3.2).
4. Gate-level: novelty/salience/PE threshold + salience floor (3.4).
5. Dedup-level: ADD/UPDATE/SKIP with optional LLM arbitration.
6. Per-exchange eager path: interrogative + quoted-span stripping + code regex + novelty search
   (`user_prompt_submit.py:329-353`, `:505-513`). MEASURED: `_detect_storable_content` fired on
   19/2,203 human-role messages in the sample; **16 of the 19 were `Stop hook feedback` messages**,
   2 typed-like, 1 other tag. Recall-cue regex `has_update_markers` hit 168/2,203 (7.6%).
7. Negative example: the PreCompact snapshot (`compact.py:121-182`, and the adapter twin
   `hooks/core.py:637-682`) stores raw recent user text (100 / 500 chars per message) with a
   `[session_snapshot …]` tag straight through `Memory.add`, which has **no gate and no dedup**
   (`client.py:75-150`; only exact-content directive dedup). Every compaction adds a row of
   transient "Recent topics" text — precisely the class our anti-capture rule forbids.
   `migrate_memory_md.py:5-6` likewise claims "the encoding gate handles deduplication" while calling
   bare `Memory.add` (`:170-173`).

## 5. Races, locks, drain semantics

- Spawn gate (`hooks/core.py:381-443`): exclusive `flock` on `~/.truememory/.spawn.lock`, exact
  live-PID count from `.spawn_pids` (psutil, zombie-aware, `:332-378`), yields `len(live) < cap`;
  caller must `register_spawned_pid` inside the gate. Replaced an earlier pgrep count that raced
  between Popen and process-table visibility (`:385-388`). Windows: `msvcrt.locking` (`:401-428`).
- Adaptive cap (`hooks/core.py:241-318`): ceiling = cores−1 (edge, ≤5) or (RAM−2 GB)/model-GB
  (base/pro, ≤6); drops to 1 on `memory_pressure` critical (<15% free) or swap growth >0.5 GB,
  halves after 2 consecutive "warn" readings, ramps +1 per 120 s when healthy; state persisted 300 s.
  Env override `TRUEMEMORY_SPAWN_CAP` bypasses. Defect: `_get_spawn_cap()` (and its
  `_save_cap_state` write) runs before the flock is taken (`:397` vs `:432-433`) although the helper
  docstrings say "must be called while holding the spawn flock" (`:177`, `:198`).
- Hourly extraction budget (`_shared.py:257-340`): flock'd JSON counter, default 20/hour
  (`:82`), consumed BEFORE the spawn gate; drainers refund the slot when the gate denies
  (`session_start.py:310-320`, `cli.py:330-338`, M-71) — but the **SessionEnd/prompt/compact path
  does not refund** (`stop.py:402-428`), so a cap-denied spawn burns budget there.
- Dedup-store lock (`pipeline.py:141-297`): `flock` is the authority; lock-file PID is diagnostic;
  after acquiring, re-stat the path and compare inode to the fd (retry ≤5) to defeat
  unlink-while-held splits; a live holder is never "stale" regardless of age (M-31,
  `:107-138`). Degrades open if the lock cannot be opened. SQLite `busy_timeout` as fallback
  (`:300-332`).
- Backlog queue (`stop.py:300-340`): `backlog/<sid>.json` {transcript_path, session_id, user_id,
  db_path, queued_at, reason}; never re-queue if a `.processing` claim exists (M-15, `:321-327`).
  Reasons recorded: `extraction_budget_exhausted`, `spawn_cap_reached:…`, `popen_failed:…`,
  `stale_session_recovery`. Policy (CLAIMED + code): **never fall back to inline ingestion**
  because inline blocked Claude Code shutdown 10–60 s (`stop.py:309-313`, `CHANGELOG.md:415`).
- Drain (`session_start.py:234-374`, and cascade `cli.py:254-378`):
  1. `cleanup_stale_processing`: a `.processing` older than 30 min whose `claimed_pid` is dead is
     renamed back to `.json` (`_shared.py:408-428`).
  2. Take ≤3 markers (`_DRAIN_CAP`, `session_start.py:120`, `:259`); cascade takes 1 (`cli.py:294`).
  3. Claim by atomic `rename(.json → .processing)`; a losing racer gets FileNotFoundError and moves
     on (`:266-270`).
  4. Corrupt JSON → quarantined to `.corrupt` so a poison pill cannot permanently occupy a drain slot
     (`_shared.py:387-405`, M-14).
  5. Missing transcript → drop; outside allowlist → drop (`session_start.py:289-300`).
  6. Budget exhausted → un-claim and stop; spawn denied → refund, un-claim, stop.
  7. Spawn; record PID into the claim; write an optimistic extracted marker with the worker PID so
     the SessionEnd hook will not start a parallel ingest (M-34, `:352-359`).
  8. The claim is **left in place**; the worker deletes it only on confirmed success
     (`_shared.py:353-384`, `cli.py:233-249`); a crashed worker leaves it for step 1 (issue #422).
  9. On success the worker spawns the next item (self-sustaining chain; SessionStart is the
     backup kick-starter, `cli.py:254-262`).
- Defects in the drain: order is `sorted(glob("*.json"))` = by session-UUID filename, not FIFO by
  `queued_at` (`session_start.py:259`); the SessionEnd hook prunes *every* file in `backlog/` older
  than 30 days, silently discarding queued work (`stop.py:202`, `:86-96`); the cascade path does not
  apply the M-90 allowlist the SessionStart drain applies (`cli.py:317-321` vs
  `session_start.py:297-300`); the cascade sends the worker's stdout/stderr to DEVNULL
  (`cli.py:352-357`) so cascaded failures leave no log; `core._queue_to_backlog` lacks the M-15
  in-flight guard (`hooks/core.py:803-825`).
- "Success" means "did not crash": LLM failures are swallowed per chunk (`extractor.py:256-271`),
  so an ingest in which every chunk failed returns 0 facts, the CLI still marks the session
  extracted and deletes the backlog claim (`cli.py:222-249`), and the session is effectively lost
  unless it grows by >1 KiB later. Exit code 3 only fires for "no backend at all" (`cli.py:217-220`).
- Stale-session scanner (`session_start.py:455-624`): non-blocking `flock(LOCK_EX|LOCK_NB)` on
  `.last_stale_scan` (a second concurrent scanner just returns, `:470-476`); runs at most every
  15 min (`:121`, `:484`); watermark = timestamp of the last scan, first run looks back 24 h
  (`:497-499`); scans `~/.claude/projects/*/*.jsonl` via `os.scandir` without following symlinks;
  skips files < 5,000 B, files with an extracted marker, files with a backlog claim, and extraction
  transcripts; queues ≤3 per scan (`:123`, `:585-600`). **M-37 watermark discipline**: when the cap
  stops the scan early the watermark is held at the scan cutoff instead of advancing to `now`, so
  deferred candidates stay inside the next window (`:501-507`, `:607-616`). Marker pruning moved
  before the early returns so it cannot be skipped (SRE-03, `:489-495`).

## 6. Latency budgets on hooks

Claude Code facts (from the hooks reference captured at `/tmp/tm-research/_cc_hooks.md`:428,
:1331, :923): command-hook default timeout 600 s, lowered to 30 s on UserPromptSubmit; **SessionEnd
hooks share a 1.5 s budget** unless a per-hook `timeout` raises it (max 60 s); a timed-out
UserPromptSubmit hook's output is discarded; `additionalContext` is capped at 10,000 chars.
TrueMemory's installer sets **no `timeout` and no `async`** on any hook (`claude.py:175-186`).

TrueMemory's own budgets (code): recall/model-server per-request deadline 5 s
(`_shared.py:97-116`, env `TRUEMEMORY_HOOK_RECALL_TIMEOUT`), recall cache TTL 300 s
(`_shared.py:74-79`), per-exchange store debounce 2 s (`user_prompt_submit.py:407`), SessionStart
maintenance and stale scan pushed to detached children because daemon threads die with the hook
(issue #557/#558, `session_start.py:627-701`), no inline ingest fallback, pgrep timeout 1 s
(`stop.py:291-297`), `memory_pressure` timeout 5 s (`hooks/core.py:128-132`).

MEASURED component latencies on this Mac (`scratch/probe3.py`, two runs):
- `import truememory.ingest.hooks.stop` via stubs: 0.011–0.022 s (the real install additionally
  executes `truememory/__init__.py`, which eagerly imports ~20 modules incl. numpy; numpy alone
  measured 0.039–0.042 s; full package import cost is ESTIMATED at a few hundred ms — not
  measurable without installing).
- `_has_enough_messages` on the largest transcript (32.9 MB): 0.127–0.141 s; median (0.5 MB):
  0.003 s. It reads and JSON-parses the whole file, and on UserPromptSubmit it runs on nearly every
  prompt of a grown session.
- Spawn-cap probes: `memory_pressure` 0.014–0.025 s, three `sysctl` calls 0.014–0.018 s each.
- ESTIMATED SessionEnd total (sum of the above + Popen + dir pruning): well under 1 s here, so it
  likely fits the 1.5 s shared budget on this machine, but it shares that budget with every other
  SessionEnd hook (ours: session-index-end + harvest-skill-end). If killed before Popen, nothing is
  queued; the stale scanner is then the only recovery.
- PreCompact `save_snapshot` and the enhanced/max per-exchange store open the DB and embed
  synchronously (model-server bound; ESTIMATED 0.1–5 s, capped by the 5 s deadline per request).

## 7. Hook output channel (affects whether captured memory is ever seen)

Both context-emitting hooks print `{"additionalContext": ...}` at the TOP level of the JSON
(`session_start.py:751-753`, `user_prompt_submit.py:830-831`). The documented schema puts
`additionalContext` inside `hookSpecificOutput` with `hookEventName` (`_cc_hooks.md:986-1001`,
:933); stdout that starts with `{` is parsed as JSON, not added as plain text (`_cc_hooks.md:792-802`).
Unless Claude Code tolerates the undocumented top-level key, the injection is silently dropped.
NOT measured live (I did not install hooks). TrueMemory's own tests assert the top-level shape
(`tests/ingest/test_onboarding.py:61`, `tests/ingest/test_recall_debounce.py:140`), i.e. they test
their output against itself, not against Claude Code. `grep hookSpecificOutput truememory/` = 0 hits.

## 8. Environment fit with OUR setup (MEASURED)

- Hardcoded roots: transcript allowlist `~/.claude/projects` (+ `TRUEMEMORY_TRANSCRIPT_DIR`
  override) (`_shared.py:34-45`); stale scanner `~/.claude/projects` only (`session_start.py:517`);
  installer writes `~/.claude/settings.json` (`claude.py:33-34`); migrate auto-detect `~/.claude`
  (`migrate_memory_md.py:31-42`). `is_allowed_transcript` on our sampled paths: **0/40 allowed**
  (they live under `~/.claude-tertiary`). Transcript counts by config dir (`find -maxdepth 2`):
  `~/.claude` 999, `-secondary` 868, `-tertiary` 1,401, `-quaternary` 1,277, `-next` 0 →
  **~78% of our 4,545 top-level transcripts are outside TrueMemory's roots**; the SessionEnd hook
  would silently skip them (`stop.py:148-150`).
- ours: `bin/cc-reaper:710` TERMs launchd-parented bash older than 600 s (lesson commit
  157a76c84). TrueMemory's detached workers are python processes, so the pattern ("detach a python
  worker, not a bash loop") is compatible with our reaper.
- ours: the nudge reaches 6.9% of sessions and 79.1% of transcript bytes are in sessions it never
  reaches (`docs/plans/MEMORY_KNOWLEDGE_V2.md` §1.3, C18–C20). TrueMemory's capture does not depend
  on the model cooperating mid-session, which is exactly the reach gap.
- ours: V2 plan rejects autonomous mutation of the unbacked store (R2) and autonomous skill drafting
  (R3). Any port must write *candidates* to a staging ledger, never MEMORY.md/topic files directly.

## 9. Efficacy evidence (what is actually measured upstream)

- The LoCoMo benchmark scripts bypass the capture path entirely: they dump raw conversation
  messages to JSON and call `engine.ingest(tmp_json)` (`benchmarks/locomo/scripts/bench_truememory_base.py:225-230`),
  i.e. no LLM extractor, no encoding gate, no dedup, no hooks. Benchmark scores therefore say
  nothing about capture quality. (MEASURED by reading.)
- The gate-eval harness tests skip because `benchmarks/gate_eval/` is not in the repo
  (`tests/test_gate_eval_harness.py:22-23`; `ls benchmarks` = beam, locomo, longmemeval).
- Capture-path tests exist and are mostly regression tests for specific bugs (issue-numbered:
  #422 backlog claim, #557/#558 async drain/scan, #560 watermark, #561 recall debounce, #586
  heuristic extractor, M-14/M-15/M-34/M-37/M-71/M-90 in code comments), plus
  `tests/ingest/test_transcript_real_format.py` against a real-format fixture
  (`tests/ingest/fixtures/sample_real_claude_code_transcript.jsonl`). I did not run them (heavy
  deps not installed). They establish that the plumbing behaves as designed, not that the stored
  facts are useful.
- The code comments document real production incidents (54K markers, 10–60 s shutdown blocks,
  poison-pill markers, double-ingest races, echo loops). CLAIMED, but the defensive code for each
  is present and specific.

## 10. Transfer ideas for our file-based workflow (first pass)

1. **Transcript-driven candidate harvester at SessionEnd, with a stale-scan backstop.** A python
   worker, detached from a SessionEnd hook that only enqueues (keeping us inside the 1.5 s budget),
   extracts durable-fact CANDIDATES into a staging ledger (for example
   `~/.claude/projects/<slug>/memory/_candidates.jsonl`, or next to `skills-pending`), never into
   MEMORY.md. A SessionStart / launchd drainer plus a watermark scan over ALL of our config dirs
   covers sessions whose SessionEnd never fired. `/compact-memory` or a `/review-candidates` command
   promotes them by hand. This closes the V2 reach gap (C19 93.1% unreached) without breaking R2/R3.
2. **Byte-offset watermark instead of size-delta re-extraction.** Store
   `{parsed_through_offset, size, pid}` per session; extract only appended JSONL lines (plus a small
   overlap for context). This fixes TrueMemory's full re-extract cost, the completion-time marker
   hole, and the 20-chunk head-keep tail drop.
3. **Extraction prompt = our anti-capture rule, stated to the model.** Reuse their structure
   (durable-only, atomic "fact not quote", category/confidence/source_role, untrusted-fence with
   delimiter neutralisation) and replace their DO-NOT list with ours: transient errors, env
   one-offs, lucky paths, unverified negative tool-claims, duplicates of existing
   MEMORY.md/topic/lessons entries (pass the index's `name`/`description` lines as the dedup
   context). Actually USE `source_role` and `confidence` (TrueMemory drops them).
4. **Input filters TrueMemory lacks.** Drop `isMeta`, `Stop hook feedback`, `<task-notification>`,
   `<teammate-message>`, slash-command wrappers, `<system-reminder>`, skill bodies, and our own
   injected nudges/index text (their `<truememory-*>` echo-strip generalised). Measured: this
   removes ~80% of "User:" messages and ~59% of formatted chars in our sample.
5. **Per-candidate decision trace.** Adopt their trace (`fact, category, gate{score,reason},
   dedup{action,existing_id}, action`) plus a `trace`/`facts --all` style viewer, so every rejected
   candidate says why. It makes anti-capture auditable and gives `/compact-memory` evidence.
6. **Queue/drain primitives worth copying verbatim in spirit:** atomic `rename` claim, claim left
   until confirmed success, stale reclaim = age AND dead PID, corrupt-marker quarantine, drain cap
   per trigger, refund-on-deny budget, never inline on failure, M-37 hold-the-watermark-when-capped.
   Fix their gaps when porting: FIFO by `queued_at`, no silent 30-day prune of queued work, the
   allowlist on every path, logs on every path.
7. **Recursion guard for any `claude -p` summariser we spawn:** env flag checked first by all of
   our hooks (nudge, harvest, session-index, drain) plus a prompt sentinel the scanner recognises, and
   mark the extraction session done so it is never harvested itself.
8. **Global concurrency + hourly budget** for background extractors (flock'd PID file, not pgrep).
   Their adaptive `memory_pressure`/swap cap is optional; a fixed cap of 1–2 is enough for us.
9. **Cheap live trigger as a nudge upgrade, not a writer.** Their `_STORABLE_RE` +
   interrogative/quote stripping could fire our memory nudge on a prompt that states a
   preference/correction/"from now on" rule instead of every 12th prompt, but only after filter 4:
   16/19 of its hits in our sample were Stop-hook feedback. Low recall; treat it as an
   opportunistic prompt, never an auto-store.
10. **Do not copy:** the regex no-LLM extractor, the PreCompact raw snapshot (for us PreCompact
    should only *enqueue* an offset extraction), the bare `Memory.add` bypass paths, top-level
    `additionalContext` output, hardcoded `~/.claude` roots, "no crash = success" completion.

## 11. Red flags (compact)

See the structured return. Each flag above carries its file:line.
