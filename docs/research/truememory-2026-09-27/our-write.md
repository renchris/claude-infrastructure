# OUR WRITE/CAPTURE PATH — notes (axis for the TrueMemory study)

Date: 2026-09-27. Worker: read-only against the repo and every memory store. Scratch scripts and raw
outputs are in /tmp/tm-research/: `our_write_measure.py/.out`, `our_write_dups.py/.out`,
`our_write_transcripts.py/.out` (infra-only first pass), `our_write_transcripts2.py/.out` (all projects,
all 4 accounts), `our_write_nn_sample.txt` (manual dup sample).
Labels: **MEASURED** = I ran it or read it this run (command named). **CLAIMED** = a doc/comment says so
and I did not re-verify. **ESTIMATED** = a method is named.

Repo root abbreviated `CI/` = /Users/chrisren/Development/claude-infrastructure.
Store roots: `INFRA` = ~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory,
`RESO` = ~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory.

---

## 0. One-paragraph verdict

Our capture path has **no deterministic capture at all**. Every memory body that exists was written because
the model, mid-session, decided to call Write/Edit (or Bash) on a memory path. Everything we built around it
(nudge, PreToolUse budget gate, PostToolUse drain, rotor, /compact-memory, lint) governs **where a write goes
and how big the index is**, not **whether a write happens** or **whether it is a duplicate / contradicts an
existing memory**. Measured on 4,528 main sessions over 6 weeks: **5.3% of sessions write any memory**;
headless `sdk-cli` sessions (54% of sessions) write it **0.29%** of the time; 1-prompt sessions (78% of
sessions) **1.2%**. The periodic nudge cannot reach **93%** of sessions by construction. The stores are
clean in the ways a write-time check was built for (frontmatter 100% valid in infra, lexical duplicates
~0%, dangling index links 0) and weak in the ways nothing checks: 70–88% of topics are not on the
auto-loaded surface, the "grep MEMORY.md first" dedup rule can only see that 12–30%, 37–40% of topics have
zero inbound links, 41 rules-file bullets carry links that only resolve from another directory, and
`superseded_by:` (the one machine-readable death signal) has been adopted by **0** files. TrueMemory's
Stop-hook extraction + encoding gate + embedding dedup (0.92) + correction detection address exactly the
"whether" and "duplicate/contradiction" halves we do not have.

---

## 1. The write path as built (read, with file:line)

### 1.1 Who is told to write, and when
- **Product (Claude Code) auto-memory instruction** — the primary capture instruction lives in the CC binary
  system prompt (types user/feedback/project/reference). We do not control it. CLAIMED by
  CI/hooks/memory-nudge.sh:504-512 ("the rest is in the Claude Code binary").
- **CLAUDE.global.md "Memory Hygiene — Anti-Capture List"** CI/CLAUDE.global.md:89-111 — SKIP transient
  errors (:95), env one-offs, lucky paths, negative tool-claims (:99), anything already indexed (:103: "grep
  `MEMORY.md` first; update the existing entry"). Prose only; no mechanism enforces it at write time
  (MEASURED: grep of hooks/ for any content check on memory writes finds none — the only PreToolUse memory
  logic is size/entry-length in CI/hooks/lib/memory-index-budget.sh:238-341 and path canonicalisation in
  CI/hooks/backup-before-write.sh:48-60).
- **hooks/memory-nudge.sh** (UserPromptSubmit, registered `~/.claude/settings.json` t=5 — MEASURED via jq):
  - fires on prompt `COUNT % INTERVAL == 0`, INTERVAL default 12 (CI/hooks/memory-nudge.sh:46, :496-502);
    on an over-cap index also on prompt 1 (:498-499).
  - counter per session id in `$CFG/state/nudge-<sid>.count`, pruned after 1 day (:57-66).
  - text (:560): FIRST create topic file with frontmatter, THEN pointer (order inverted 2026-09-03, rationale
    :551-559: the pointer can be refused by the gate, the body must survive); durable generalizable RULE →
    `.claude/rules/agent-operating-lessons-situational.md` as a ≤420-char hook + full body in
    `docs/lessons/<slug>.md`; SKIP list embedded.
  - names the physical index path (fix of 2026-09-27, :118-134) because the symlinked spelling triggered a
    permission prompt auto mode cannot approve.
  - It is also a **rotor trigger**: at ≥ LIMIT-1500 units it runs `cc-memory-rotate` once per index-state per
    day (:219-295).
- **harvest** — CI/hooks/harvest-skill-end.sh (SessionEnd): logs a candidate row for sessions with
  message_count ≥12 and non-empty commands_run (:46-47) to `~/.claude/skills-pending/_candidates.jsonl`
  (:49-59). No model call. CI/commands/harvest-skill.md: human runs `/harvest-skill`, drafts to
  skills-pending, "If nothing qualifies, STOP" (:19), never writes ~/.claude/skills (:28).

### 1.2 What happens at the write
- **PreToolUse Write|Edit|MultiEdit → backup-before-write.sh** (settings t=10, MEASURED):
  - rewrites a symlinked memory path to its physical path via `updatedInput` (CI/hooks/backup-before-write.sh:48-60)
    — kill switch `CC_MEMPATH_CANON=off`.
  - sources `lib/memory-index-budget.sh`; `mib_verdict` **denies** a write whose result exceeds the 25,000-unit
    / 200-line cap AND grows the file, or pushes one index line past the 300-unit per-entry cap
    (CI/hooks/lib/memory-index-budget.sh:22-33 invariant, :238-341 verdict; entry cap
    CI/hooks/lib/memory-index-measure.sh:98-99 `MEMORY_ENTRY_LIMIT:-300`). Fail-open on every unknown (:35-40).
  - **Blind to Bash** (CI/hooks/memory-index-drain.sh:5-17, CLAIMED "measured 1 in 6 index writes").
- **PostToolUse Bash|Write|Edit|MultiEdit → memory-index-drain.sh** (settings t=10, MEASURED):
  - stat gate (mtime+size) then `cc-memory-rotate --drain-oversized --rules-file <situational rules>`
    (CI/hooks/memory-index-drain.sh:94-126, :259); then whole-index rotation if over either cap (:297-331).
    Shared 7s budget across both rotor calls (:141-230).
- **bin/cc-memory-rotate** (1,606 lines): moves index lines VERBATIM to the situational rules file (routing,
  since 2026-09-04) or to `archive/MEMORY_ARCHIVE_*-COLD.md` (CI/bin/cc-memory-rotate:25-41). route_veto keeps
  PINNED and feedback-/reference-/user- lines out of routing (:33, :154, :414). Hubs ≥4 inbound `[[links]]`
  kept hot (:68).
- **/compact-memory** (CI/commands/compact-memory.md, 840 lines): SAFE-AUTO archive of closed entries + orphan
  re-index (E1/E2/E3 exclusion, :97-243); PROPOSE-ONLY shortening and **near-duplicates** (:325-329:
  "show both descriptions side by side … NEVER auto-merge"), dropped-token audit gate (:274-302). The
  `superseded_by:` frontmatter key is the only rotor-readable "this entry is dead" signal (:81-93).
- **Lessons tier**: CI/.claude/rules/agent-operating-lessons.md:1-33 (hook ≤~350 chars + body in
  docs/lessons/<slug>.md; new lessons → situational file :33). Enforced at land by
  CI/scripts/rules-hook-budget-lint.sh (bodyless `(.)` refused, >420 chars refused, resident-add refused
  without RULES_RESIDENT_ADD_OK=1; :4-60, BUDGET :71).
- **Worktrees**: CI/scripts/worktree-memory-link.sh:4-24 symlinks a worktree's memory/ to the primary's.
  The nudge resolves the index via `--git-common-dir` (CI/hooks/memory-nudge.sh:68-117).

### 1.3 What the machinery costs (MEASURED `git log --oneline -- <f> | wc -l`, `wc -l`)
| file | commits | lines |
|---|---|---|
| hooks/memory-nudge.sh | 22 | 566 |
| commands/compact-memory.md | 25 | 840 |
| bin/cc-memory-rotate | 19 | 1,606 |
| hooks/lib/memory-index-budget.sh | 8 | 386 |
| hooks/memory-index-drain.sh | 6 | 342 |
| hooks/lib/memory-index-measure.sh | 3 | 182 |
| bin/cc-memory-dropped-token-audit | 2 | 236 |
~4,158 lines / 85 commits are devoted to **index budget and placement**; 0 lines to dedup-at-write,
contradiction-at-write, or automatic extraction.

---

## 2. Measurements

### 2.1 Store topology (MEASURED, python os.path.islink over ~/.claude*/projects/*/memory)
- `~/.claude/projects`: 2,313 memory dirs, **2,299 real / 14 symlinks** (all 14 are worktree slugs →
  infra (9) or reso (5)). Only **36** real stores are non-empty; **1,674** topic files total.
- `~/.claude-next/projects` is a symlink to `~/.claude/projects`; secondary/tertiary/quaternary have 0–1 real
  memory dirs and 2,319–2,395 symlinks. → **one physical store per project** (confirms plan C15,
  CI/docs/plans/MEMORY_KNOWLEDGE_V2.md:102-106).
- No capture was lost to a worktree-keyed store: the only non-empty real stores with `worktree`/`tmp` in the
  slug are 4 probe stores (`-private-tmp-memprobe*`, a scratchpad probe).
- INFRA: 497 top-level .md (495 topics + MEMORY.md + `memory-index-compaction-economics.md`), 21 archive .md.
  RESO: 838 top-level .md (836 topics + MEMORY.md + MEMORY-ARCHIVE.md), 11 archive .md.
- Live index (MEASURED `mim_measure_file`, CI/hooks/lib/memory-index-measure.sh): INFRA **23,448/25,000
  units, 151/200 lines**; RESO **22,347 units, 103 lines**. Limits: 25,000 units, 200 lines, 300/entry.

### 2.2 Creation rate (MEASURED, st_birthtime per topic file; mtime agrees within ±7/week)
INFRA births/ISO-week: W28 1 · W29 21 · W30 34 · **W31 133** · W32 59 · W33 50 · W34 50 · W35 25 · W36 20 ·
W37 68 · W38 14 · W39 20 (range 2026-07-11 → 09-27; the Jul-11 floor coincides with the store's symlink
date, so earlier history may have been re-birthed by a move — birthtimes before W29 are not trustworthy).
Peak days: 07-30 45, 07-29 37, 07-31 34.
RESO births/week: steady 20–98/week from W12, peak **W25 98**; recent W36 20 · W37 28 · W38 19 · W39 30.
ALL 36 stores, last 12 weeks: 34 · 60 · 92 · **196** · 130 · 93 · 111 · 91 · 49 · 116 · 55 · 66.
→ ~50–200 new memory files/week fleet-wide; ~15–70/week in infra. Mean infra ≈ 41/week over 12 weeks.
Distinct `originSessionId` values: INFRA 338 sessions wrote 424 stamped files (max 4 per session);
RESO 549 sessions / 727 files (max 7). i.e. capture is ~1.25 files per writing session.

### 2.3 Who writes, and does the nudge matter (MEASURED, our_write_transcripts2.py over 4,528 main-session
transcripts with ≥1 prompt, 4 accounts, window 2026-08-16 → 09-27; sidechains excluded)
| metric | value |
|---|---|
| sessions writing ≥1 memory file (Write/Edit/MultiEdit) | **238 / 4,528 = 5.3%** |
| by entrypoint | cli 231/2,077 = **11.1%**; sdk-cli (headless/dispatched) **7/2,447 = 0.29%** |
| by session length (human-text prompts) | 1 prompt: 42/3,515 = **1.2%** · 2–11: 77/710 = 10.8% · 12–49: 110/283 = 38.9% · 50+: 9/20 = 45% |
| sessions that received ≥1 periodic nudge | 434 / 4,528 = **9.6%** |
| P(write \| nudged) vs P(write \| never nudged) | **31.8%** vs **2.4%** (confounded with length) |
| memory write calls after a nudge in same session | 242/600 = 40.3%; **144 (24%) in the nudge's own turn or the next** |
| topic-file creates (Write "created successfully") | 291; Edit/MultiEdit on topic files 120 |
| index writes via tools | 188; **via Bash `>>`/tee -a/sed -i: 65 in 43 sessions (26% of index writes)** |
| topic writes via Bash (`cat >` / `> …/memory/x.md`) | ~62 in 45 sessions (regex, approximate; ~18% of topic creations) |
| rules-file writes / docs/lessons writes | 31 in 16 sessions / 31 in 25 sessions |
| PreToolUse budget-gate refusals seen in tool_results | 30 |
| "MEMORY INDEX DRAINED" contexts seen | 11 |
Write targets by store (calls, sessions): reso 211/87 · infra 170/88 · personal 72/18 · sevenrooms-bridge 50/14 ·
reso-web-app 36/5 · voiceink 17/4 · mac-bootstrap 9/4 · memprobe 7/7.
Infra-only first pass (our_write_transcripts.out, 374 sessions): 12.6% wrote; 33 of 46 topic-writing sessions
never touched MEMORY.md through a tool (some via Bash, some edits to existing topics); median prompt# at first
memory write = 14.
Note: my prompt count (human text, !isMeta) under-counts the hook's counter (every UserPromptSubmit incl.
teammate/task notifications), which is why 434 sessions were nudged while only 303 have ≥12 counted prompts.

Live nudge counters (MEASURED `cat ~/.claude*/state/nudge-*.count`, ≤1 day of sessions): ~/.claude 641 counters,
**556 (86.7%) exactly 1**, 28 (4.4%) reached ≥12; secondary 19/6, tertiary 13/3, quaternary 28/9.
Plan baseline (CLAIMED, MEMORY_KNOWLEDGE_V2.md:110-121, Jul 28–30): 93.1% never reached.

### 2.4 Frontmatter validity (MEASURED, our_write_measure.py)
- INFRA 495/495 parse; type feedback 134 · project 258 · reference 103 · **user 0**; all use the nested
  `metadata:` block (type/node_type/originSessionId/modified); name≠filename 1; description >300 chars
  26 (5.2%). Description p50 176 chars, p90 266, p99 500; body p50 2,531 chars, p90 5,894, p99 16,066.
- RESO: 4 files with no frontmatter (bottle-image-pipeline, bottle-service-plan, lost-in-dreams-rum-improvements,
  slide-out-status-controls-final); 1 file missing name+description+type
  (project-home-login-cls-first-pull-gate-2026-06-08.md); **148 name≠filename** (older legacy top-level
  `type:`/`originSessionId:` schema, 148 files); description >300 chars 59 (7.1%). type reference 392 ·
  project 261 · feedback 177 · user 1.
- `superseded_by:` present in **0** files of either store (MEASURED grep) although compact-memory.md:81-93 made it
  the rotor's death signal on 2026-09-05. `PINNED` appears in **0** index lines of either store.
- Body CORRECTED/SUPERSEDED/REFUTED/RETRACTED markers: INFRA 28 (5.6%), RESO 79 (9.4%) — corrections are
  appended in place, never structurally linked.

### 2.5 Duplication (MEASURED + ESTIMATED)
- Token-Jaccard on name+description (stopwords removed, tokens >2 chars): INFRA **0 pairs ≥0.4** of 122,265;
  RESO **2 pairs ≥0.4**, 0 ≥0.5, of 349,030. Exact duplicate descriptions: 0/0. Cross-store infra×reso ≥0.5: 0;
  identical filenames: 0.
- TF-IDF (1–2 gram, sublinear) cosine with **positive control** (10 synthetic paraphrases per store, 30% word
  drop + clause rotation): control caught 10/10 at 0.4–0.5, 8/10 at 0.6. Real pairs: INFRA 0 at ≥0.4 (head
  and body); RESO 3 pairs/6 files at head ≥0.4, 0 at ≥0.5; body 0 at ≥0.4. Nearest-neighbour head cosine
  p50/p90/p99: INFRA 0.08/0.14/0.24; RESO 0.10/0.20/0.38. Cross-store ≥0.35: 0.
- Concrete duplicates found (RESO):
  - `reference-vitest-default-reporter-prints-no-console-log.md` (born 09-06 23:43) and
    `reference-vitest-default-reporter-swallows-console.md` (born 09-06 03:06): **same rule, both indexed hot**,
    written 20 h apart — passed the "grep MEMORY.md first" rule despite both being in MEMORY.md.
  - `reference-a-same-geometry-remount-is-invisible-to-shift-and-box-assertions.md` (19:33:21, no
    originSessionId, **not indexed, not archived — genuine orphan**) and `…-to-every-shift-assertion.md`
    (19:34:32, indexed): same session 71 s apart; the first draft was abandoned on disk.
- ESTIMATED semantic duplicate rate (manual judgment of 25 random INFRA entries vs their TF-IDF nearest
  neighbour, our_write_nn_sample.txt): 0/25 duplicates, 1/25 subsumption
  (`lint-blindness-composes-and-hides-the-next-defect` contains `shellcheck-prose-comment-aborts-analysis`),
  several **thematic families not linked lexically** (e.g. four "control" rules:
  control-calibrated-to-implementation-decays / control-fixture-must-reach-the-bugs-regime /
  control-population-must-be-stable / positive-control-the-denominator — TF-IDF did not pair any of them).
  Conclusion: **lexical dup rate ≈0–1%**; the real defect is **fragmentation into many near-sibling
  aphorisms**, which a lexical detector cannot see and an embedding detector (TrueMemory dedup 0.92 +
  novelty 0.85, /tmp/truememory-src/truememory/client.py:190, ingest/dedup.py:184) is designed to. No local
  sentence-embedding model is cached (MEASURED `ls ~/.cache/huggingface/hub`), so an embedding-based rate
  was NOT measured.

### 2.6 Links and reachability (MEASURED)
- `[[wikilinks]]` (code spans stripped): INFRA 1,910 in 488 files, **40 broken (2.1%)** → 32 truly missing,
  3 resolve in CI/docs/lessons/, 6 in another project's store, 1 empty `[[]]`. RESO 1,431 in 656 files,
  **16 broken (1.1%)** → 15 missing (e.g. `[[RUM_100P_INVESTIGATION]]`, `[[GUEST_BOOK_PRODUCTION_REVIEW]]` —
  repo doc names, not memory names).
- Zero inbound wikilinks: INFRA 183/495 (37%), RESO 337/836 (40%).
- Index links: INFRA 148 bullets / 148 links / **0 dangling**; RESO 102/102/0.
- Hot vs cold: INFRA **148/496 topics (29.8%) indexed hot**, 312 in a demotion record, 36 unreferenced →
  26 cited by rules/CLAUDE (E3) → **10 genuine orphans**, all born **09-09 → 09-15** (the window in which the
  index was at its hard cap — a rules bullet dated 2026-09-09 says "MEMORY.md index is at its hard cap, so
  this rule lives here"). RESO **101/836 (12.1%) hot**, 704 in demotion records, 31 unreferenced → 30 E3 →
  **1 genuine orphan** (the same-session near-duplicate above).
- Rules file (CI/.claude/rules/agent-operating-lessons-situational.md): lint clean (MEASURED
  `bash scripts/rules-hook-budget-lint.sh` → "clean — 17 bullet(s)… / 168 bullet(s)…", rc 0). 144 bullets
  link `../../docs/lessons/`, 144/144 bodies exist, 0 lesson bodies unlinked. BUT **41 bullets carry a
  relative `](x.md)` link that resolves from 0/41 in `.claude/rules/` and 41/41 in INFRA** — rotor-routed
  index lines moved VERBATIM (CI/bin/cc-memory-rotate:40-41) with memory-dir-relative targets; plus 17
  `- demoted 2026-09-06 …` bullets pointing into the untracked store by absolute path. The lint does not
  check link resolution (it only refuses target `.` and >420 chars).

### 2.7 Harvest (MEASURED)
- `_candidates.jsonl`: **20 rows ever** (Jul 11, Aug 8, Sep 1), **20/20 `unreviewed`**. Gate-passing sessions
  in `session-index.db` since 2026-08-16: **149** → candidate logging reached ≈13% of eligible sessions over
  the whole life of the hook and ~1/149 in September. `SKILL.md` drafts in skills-pending: **1**
  (readme-showcase-pipeline). The loop's human step has never been exercised at scale.

---

## 3. Capture failure modes (each with evidence)

F1 **Capture is entirely model-volitional.** No hook extracts anything from a transcript; hooks only nudge or
police size/placement (§1.1–1.2). Result: 5.3% of sessions write (§2.3).

F2 **Headless / dispatched sessions essentially never capture.** sdk-cli 7/2,447 = 0.29% vs cli 11.1%. These
are the autonomous fleet sessions the plan (MEMORY_KNOWLEDGE_V2.md:128-133, C22) calls the
knowledge-producing class.

F3 **The nudge's reach is structurally bounded by prompt count.** INTERVAL=12 (memory-nudge.sh:46); 86.7% of
live counters are at exactly 1; 93.3% of sessions have <12 human prompts. SessionEnd/Stop capture was
rejected (plan R7, :262-265: "SessionEnd fires when the session's context is already gone") — true for an
advisory, false for a transcript extractor, which is what TrueMemory's Stop hook does
(/tmp/truememory-src/truememory/ingest/hooks/stop.py:1-16).

F4 **Nudge effect is real but confounded.** P(write|nudged) 31.8% vs 2.4%; 24% of all write calls land in the
nudge's own/next turn. Nudged sessions are long sessions, so the causal share is unknown (no A/B exists).

F5 **Bash door bypasses the PreToolUse layer.** 26% of index writes and ~18% of topic creations went through
Bash (§2.3) → no backup (backup-before-write only matches Write|Edit|MultiEdit), no path canonicalisation,
no budget gate (only the PostToolUse drain sees it, index-only).

F6 **Pointer refusal → orphaned body.** File-first ordering (memory-nudge.sh:551-559) saves the body but the
pointer can still be refused (30 refusals seen). 10 INFRA orphans all born 09-09..09-15 during the at-cap
window (inference: pointer refused / never retried). Nothing re-indexes except a manual /compact-memory.

F7 **Dedup check has the wrong scope.** CLAUDE.global.md:103 says "grep MEMORY.md first", but only 29.8%
(INFRA) / 12.1% (RESO) of topics are in MEMORY.md; the rest are in cold records or the rules file. Duplicates
occurred even with both copies hot (vitest pair).

F8 **No dedup / novelty / contradiction check at write time.** Near-duplicates are PROPOSE-ONLY in a manual
command (compact-memory.md:325-329). Corrections are appended as prose markers (5.6% / 9.4% of files) rather
than linked; `superseded_by:` adoption 0/1,332.

F9 **Abandoned drafts.** Same-session rewrite leaves the first file on disk (RESO geometry pair, 71 s apart;
first file lacks originSessionId).

F10 **Fragmentation into sibling aphorisms.** 37–40% zero-inbound topics; four+ "control" rules in INFRA not
linked to each other; lexical tools see nothing. This is the defect a consolidation step (TrueMemory
"consolidation") targets.

F11 **Routed lines break their links.** 41 rules bullets have memory-relative links unresolvable from the rules
file; 17 "demoted" bullets point at an untracked store by absolute path (§2.6).

F12 **Schema drift, unvalidated.** RESO: 148 legacy-schema files (name≠filename), 4 without frontmatter, 1
empty; INFRA: descriptions up to ~500 chars (26 >300). No write-time frontmatter validator exists (only the
index entry-length gate).

F13 **Harvest pipeline stalled.** 20 candidates ever, all unreviewed; 1 draft; ~13% of eligible sessions logged.

F14 **Untracked, unbacked store.** Plan R2 (MEMORY_KNOWLEDGE_V2.md:231-237): no repo tracks memory/, so every
automated mutation is refused on safety grounds — which is also why automatic capture was never built.
(Bash writes additionally miss backup-before-write, F5.)

F15 **Budget machinery absorbs the engineering.** ~4,158 lines / 85 commits on size/placement (§1.3), versus
zero on whether/what to capture. Index re-inflation is structural (CLAIMED cc-memory-rotate:10-19: 7–19
entries/day).

---

## 4. What TrueMemory offers this axis (pointers only; other axes own the depth)
- **Automatic capture at Stop** — `truememory/ingest/hooks/stop.py:1-16,115-141` reads `transcript_path` and runs
  extraction in a background subprocess. Directly answers F1–F3 (reach becomes 100% of sessions that end
  cleanly, including sdk-cli).
- **Encoding gate / salience** — `truememory/ingest/encoding_gate.py:131-291` (per-category threshold
  overrides :146, contradiction detection :166). A mechanical analogue of our anti-capture list.
- **Dedup with correction awareness** — `truememory/ingest/dedup.py:86` `_is_correction`, :103
  `_has_divergent_numbers` (numbers that differ are NOT duplicates), :184 cosine >0.92, :248 LLM fallback,
  :323 heuristic fallback. Answers F7–F9.
- **Transcript noise stripping** — `truememory/ingest/transcript.py:318-339` drops wrapped/truncated blocks that
  otherwise re-extract as near-duplicates.

## 5. Applicable to our write path (ranked by evidence; all compatible with human-gated policy)
1. **SessionEnd/Stop transcript extractor that PROPOSES, not writes** — run the extraction over the transcript
   (TrueMemory-style) and write candidates to a staging file (like skills-pending) rather than the store.
   Keeps plan R2 (no automated mutation of an unbacked store) and our human gate, and fixes reach (F1–F3).
2. **Write-time dedup/novelty check over the WHOLE store** (hot + cold + rules + docs/lessons), not
   MEMORY.md — PreToolUse on Write to `memory/*.md` returning additionalContext "nearest existing: X (cos
   0.87)"; advisory, never deny. Addresses F7/F8/F10. Needs an embedding model (none cached locally).
3. **Close the Bash door for topic creation** by making the nudge/CLAUDE.global instruction say "use Write" and
   by extending the PostToolUse drain's stat-watch to new topic files (backup + frontmatter check) (F5, F12).
4. **Orphan re-pointer** — PostToolUse/rotor pass: a topic file with no index line, no demotion record and no
   E3 citation gets appended to the cold record with a "never indexed" note (F6, F9) — reversible, no loss.
5. **Rotor link rewrite on routing** — rewrite `](x.md)` to an absolute or `memory:`-prefixed target when moving
   a line into `.claude/rules/` (F11), and extend rules-hook-budget-lint to check link resolution.
6. **Structured supersession** — have the write path (nudge text + a validator) require `superseded_by:` /
   `supersedes:` when a correction is written, mirroring TrueMemory's correction detection (F8).

## 6. Not measured / limits
- Semantic duplicate rate with embeddings (no model cached; downloading one was out of scope).
- Causal effect of the nudge (no A/B; only confounded association).
- Anti-capture compliance was flagged heuristically only (INFRA: 1 version-pinned name, 3 worktree-path bodies,
  5 flake-word descriptions; RESO: 224 (26.8%) dated filenames, 9 version-pinned, 22 worktree/tmp-path bodies,
  18 flake-word descriptions). "Negative tool-claim" regex hits (INFRA 37, RESO 41) are mostly rules phrased
  with "cannot", not unverified tool claims — not a compliance rate.
- Transcript window is ~6 weeks (retention); birthtimes before 2026-07-11 in INFRA are likely move-reset.
- Bash topic-write regex is approximate (may include some non-memory redirects that mention memory/ paths).
