# TrueMemory: encoding gate, salience and dedup (the "what is worth storing" axis)

Source: shallow clone `/tmp/truememory-src` at `063e5b8`. All `file:line` references are relative to
`/tmp/truememory-src/`. The paper is arXiv 2605.04897, "Storage Is Not Memory" (Adler, Zehavi). Its
HTML was fetched to `/tmp/tm-research/gate-scratch/paper.txt`.

Evidence labels:
- **MEASURED-RUN**: I executed it. The scripts are in `/tmp/tm-research/gate-scratch/`: `probe.py`,
  `probe2.py`, their `*_out.json`, and copied tests under `tests/`.
- **MEASURED-READ**: I read the code and the behaviour follows directly from it.
- **CLAIMED**: stated only in a README, CHANGELOG, docstring or the paper.

Probe environment: the real TrueMemory modules are imported through a symlink shim
(`gate-scratch/shim/truememory/*` -> source files). The embedder is the **edge tier**, model2vec
`minishlab/potion-base-8M`, which is what `truememory/vector_search.py:259-261` loads for edge. The
Memory object is a stub whose `search_vectors` returns true cosine top-k. **Caveat:** Base/Pro use
Qwen3-Embedding-0.6B (`vector_search.py:11,278`). PE and cosine numbers under Base/Pro will differ.
I did not measure them.

---

## 0. Where the gate sits in the write path

The production write path runs in five steps:

1. Transcript at Stop.
2. **LLM extractor** turns it into atomic facts (`truememory/ingest/pipeline.py:455-458`). The
   extractor prompt is at `truememory/ingest/extractor.py:70-112`.
3. **EncodingGate.evaluate(fact, category)** (`pipeline.py:471-479`).
4. **check_duplicate** runs under a process lock (`pipeline.py:511-518`).
5. ADD, UPDATE (in place) or SKIP.

A second, eager path runs on UserPromptSubmit (`truememory/ingest/hooks/user_prompt_submit.py:437-537`):
- a regex pre-filter, `_STORABLE_RE` (`:176-189`) and `_detect_storable_content` (`:329-`)
- a cosine > 0.85 near-dup short-circuit (`:505-513`)
- the gate (`:516-520`)
- check_duplicate (`:531-536`)

This path is off in "standard" intensity (`:444-445`).

**The real first-line "worth storing" filter is the LLM extractor prompt, not the gate.**
`extractor.py:78-95` has an EXTRACT list and a DO NOT EXTRACT list. The DO NOT EXTRACT list is:
- transient debugging details
- code snippets
- greetings and filler
- things obvious from the codebase or git
- the assistant's own suggestions (only USER-stated facts)

That is nearly the same as our anti-capture list (see section 8). The extractor also emits
`confidence` and `source_role` (`extractor.py:101-102`). **Neither is used by any gate.** The only
consumer is a trace entry (`pipeline.py:472`), found by grep: MEASURED-READ.

**Paper vs code mismatch (MEASURED-READ plus paper text).**
- The paper puts the gate on raw events, preserved verbatim. Its thesis is that "extraction at
  ingestion is the wrong primitive" (paper.txt:79, :112-114).
- The shipped Claude Code pipeline gates LLM-extracted facts (`pipeline.py:455-479`).
- The paper states the gate is **disabled in every reported benchmark**, and that "the gate's
  contribution to end-to-end accuracy therefore remains unmeasured" (paper.txt:128, :479, :489).

---

## 1. The gate decision (truememory/ingest/encoding_gate.py)

The documented formula is `0.25*n + 0.20*s + 0.30*p >= 0.30` with a salience floor of 0.10
(`:43-45`). The actual computation is `score = clamp((0.25n + 0.20s + 0.30p) / 0.75)`
(`:231-232, :262-267`). The raw-weighted threshold is therefore **0.225, not 0.30**.
- The docstring omits the normalisation. The paper mentions it (paper.txt:127).
- MEASURED-RUN P10: `norm = 0.75`, effective raw threshold 0.225.

Decision order in `evaluate` (`:242-331`):

1. **PE degraded, so fail OPEN** (`:271-275`). If the embedder failed once, every fact passes for the
   life of the gate object. The flag is never reset: `reset_batch` (`:660-666`) does not clear
   `_pe_available`.
2. **Contradiction bypass** (`:277-281`). The fact is always stored if
   `_is_contradiction(fact, category)` holds (`:166-179`), meaning any of:
   - category == correction
   - both " not " and " but " appear
   - `has_update_markers`
3. **Salience floor.** `salience < 0.10` means SKIP regardless of score (`:286-288`).
4. **Per-category threshold.** `threshold + override`, floored at 0.10 (`:290-293`). The overrides
   (`:146-152`) are:

   | Category | Override |
   |---|---|
   | correction | -0.06 |
   | decision | -0.04 |
   | relationship | -0.04 |
   | event | -0.04 |
   | activity | -0.02 |

   The CHANGELOG lists only the first three (CHANGELOG.md:346-347), so the doc has drifted.

Defaults can be overridden through env vars `TRUEMEMORY_GATE_W_NOVELTY`, `_W_SALIENCE`, `_W_PE` and
`_SALIENCE_FLOOR` (`:217-228`). `TRUEMEMORY_GATE_THRESHOLD` is read only by the Stop hook
(`truememory/ingest/hooks/stop.py:53,380`). The per-prompt path constructs `EncodingGate` with the
default 0.30 (`user_prompt_submit.py:517`), so the env threshold does not apply there (MEASURED-READ).
`TRUEMEMORY_GATE_ENABLED=0` disables the gate (`pipeline.py:403-408`).

`log_batch_summary` counts "passed" as `score >= self.threshold` (`:626`). That ignores the floor, the
bypass and the category offsets. MEASURED-RUN P12: summary said passed=3, actual encoded=2 ("ok" had
score 0.339 but was floored).

`_explain` (`:581-618`) writes a human-readable reason string, e.g.
`ENCODE score=0.39 (n=.., s=.., p=..) threshold=0.30 — partially novel`, and it goes into the trace.
**This is one of the better ideas: every admit or reject carries its signal breakdown.**

### 1a. Signal 1: novelty by compression (`:337-423`)

How it works:
- Retrieve top-10 by `search_vectors` (`:365-376`) and drop directives (`:383`).
- Concatenate their contents into `M` and compute
  `novelty = (|gz(M + " " + f)| - |gz(M)|) / |gz(f)|`, clamped to [0.05, 1] (`:398-419`).
- Empty store gives 1.0 (`:387-396`). An exception gives 0.5 (`:421-423`).

CLAIMED: AUC 0.788 vs 0.484 for cosine inversion in a "120-variant sweep" (`:14-19`, `:350-356`,
paper.txt:119). The sweep and data are not in the repo (see section 6).

Measured findings:
- **Dead branch.** The "trivially short" branch `if c_fact < 10: return 0.05` (`:407-408`) cannot
  fire. gzip's fixed overhead makes `len(gzip.compress(b""))` 20 bytes and `b"ok"` 22 bytes
  (MEASURED-RUN P1). The paper repeats the "below 10 bytes" claim (paper.txt:119).
- **Novelty is length-confounded.** The ~20-byte header sits in the denominator.
  - MEASURED-RUN P3, same novel sentence truncated against a fixed 3-fact memory: 9 chars gives 0.207,
    23 gives 0.326, 50 gives 0.443, 73 gives 0.524, 107 gives 0.615.
  - Short facts can never look very novel, even when entirely new.
- **What it does catch is near-verbatim restatement of something already in the top-10.**
  - MEASURED-RUN P9: exact duplicate scores n=0.081, paraphrase 0.17-0.20, unrelated 0.44-0.51.
  - P5: 7 of 8 lightly reworded copies of stored lessons were rejected.

### 1b. Signal 2: salience (`:429-453`, which delegates to `encoding_salience.encoding_salience_d`)

Variant D is used in production (`encoding_salience.py:295-302`). It routes on length:

**At most 50 chars: `_speech_act_score`** (`encoding_salience.py:265-292`). The checks run in order:

| Order | Test | Score |
|---|---|---|
| 1 | exact noise set `_NOISE_EXACT_V23` (`:219-243`) | 0.02 |
| 2 | question (ends with `?` or starts with what/how/...) | 0.2 |
| 3 | `_COMMITMENT_RE` (`:245-262`) | 0.8 |
| 4 | `_COMMITMENT_PATTERNS` (`:56-70`) | 0.7 |
| 5 | correction words / `_UPDATE_VERBS` (`:50-54`) / "actually ... not" | 0.6 |
| 6 | greeting **prefix** `^(?:hey\|hi\|hello\|yo\|sup\|what's up\|howdy)` | 0.05 |
| 7 | reaction **prefix** `^(?:haha\|lol\|lmao\|omg\|wow\|damn\|ugh\|yikes)` | 0.08 |
| 8 | 5 or more alphabetic words | 0.5 |
| 9 | otherwise | 0.25 |

**Over 50 chars: L3 retrieval salience** `truememory.salience.compute_message_salience`
(`salience.py:195-209`). It is a logistic regression over 13 features (`salience.py:153-188`) with
weights from `data/l3_weights.json`.

CLAIMED: speech-act AUC 0.726 on short messages and 96% "S4 recall" (`encoding_salience.py:216-217`).
The CHANGELOG says 0.733 (CHANGELOG.md:330). The two sources disagree.

Measured findings:
- **Prefix-regex bug.** Items 6 and 7 have no word boundary. Any fact of 50 chars or fewer that
  starts with hi/hey/yo/sup/hello/howdy or haha/lol/omg/wow/damn/ugh/yikes, and that has no
  commitment or update cue, scores 0.05 or 0.08. That is **below the 0.10 floor, so it is always
  rejected**. MEASURED-RUN P2, all rejected with the "salience below floor" reason:
  - "Supabase is the primary database"
  - "History file lives in ~/.zsh_history"
  - "Yosemite trip is booked for June"
  - "Hidden files are shown in Finder"
  - "Supervisor restarts the worker"
  - "Wowza streaming server runs on 1935"
  - "Hey is the default mail client"
  - "Lolcat ...", "Omgpop ...", "Damnation ..."

  "Homebrew prefix is /opt/homebrew" passed only because "ho" is not in the list.
- **Category is ignored by variant D.** It takes `category` but never uses it (`:295-302`).
  MEASURED-RUN P11: identical salience 0.3291 for general, correction and decision. The docstring
  (`encoding_gate.py:21-25`) says salience "adds a category weight from the LLM extractor". That is
  true only for the fallback path (`encoding_gate.py:451-453`). In production, category enters only
  through threshold offsets and the correction bypass.
- **Over 50 chars, salience is essentially a length meter.** L3 weight for `f_length = log(1+L)/7` is
  8.54 against bias -6.03 (`data/l3_weights.json:18-33`). MEASURED-RUN P4, plain text with no
  numbers: 51 chars gives 0.23, 100 gives 0.40, 200 gives 0.61, 300 gives 0.72.
- The L3 model was fit for **retrieval utility**, not encoding worth:
  - `"training_dataset": "locomo_short_horizon_200"`, `"training_auc": 0.719`, coefficients are the
    mean across 10-fold LOCO-CV and the bias comes from a full-data fit (`data/l3_weights.json:34-36`).
  - CHANGELOG.md:371-376: "trained on LoCoMo retrieval-utility labels (+0.045 AUC, p=0.012 vs
    hand-tuned)" (CLAIMED).
  - test_l3_salience.py:13-15 cites n=5882 and `_working/memorist/l3_salience/REPORT.md`, which is
    gitignored (.gitignore:99).

### 1c. Signal 3: prediction error by embedding pair difference (`:473-553`)

How it works:
- PE is 0 if the fact is in the noise set, shorter than 3 chars, or there are no search results
  (`:488-494`).
- Take the nearest memory `m`. If `cos(f, m) < 0.2`, PE is 0 (`:524-530`).
- Otherwise PE = `1 - cos(E(f + " [SEP] " + m), E(m + " [SEP] " + m))` (`:532-541`).
- A model load or encode failure sets `_pe_available=False`, so the gate fails OPEN (`:496-509`,
  `:544-553`).

CLAIMED: AUC 0.730 standalone and gate AUC 0.816, independent of novelty (r=0.30) and salience
(r=0.23), over a "200-variant sweep across 10 paradigms" (`:27-33`, `:482-486`). The CHANGELOG says
gate AUC 0.810 (CHANGELOG.md:332-333), again a disagreement.

Measured findings (MEASURED-RUN P9, edge model, memory "Alice works at Google as a software engineer"):
- Consistent paraphrases: PE 0.012 and 0.017.
- Contradictions:
  - "Alice quit Google and joined Anthropic": 0.219
  - "Alice no longer works at Google": 0.063
  - "**Alice works at Microsoft as a software engineer**": 0.052
- Unrelated "The build cache lives in /tmp": **0.213**.

So on the edge tier, PE barely separates contradiction from unrelated text. Worse, the
marker-free update "Alice works at Microsoft ..." was **rejected** (score 0.228 < 0.30): a real
knowledge update, dropped at the gate because it used no correction vocabulary. The marker-bearing
"no longer" version passed only through the bypass.

### 1d. Correction bypass and the shared marker vocabulary (truememory/ingest/markers.py)

`UPDATE_MARKERS` (`:30-55`) includes: actually, correction:, no longer, not anymore, changed to/from,
switched to/from, moved to, used to (be), instead of, wrong about, was/is wrong, not true, that's
incorrect, updated, replaced, formerly, previously.

The compiled patterns add (`:72-84`):
- `now (is|uses|...)`
- `was ... now`
- number change `\d… (to|->|→) \d…`
- **`(since|as of|starting|effective) \w+`**

Issue #649: gate and dedup import the same predicate (`encoding_gate.py:67-70`, `dedup.py:31-34`).
Asserted by identity in `tests/test_issue_649_dedup_gate_hygiene.py:48-56`.

Breadth: 10 of our 185 lesson hooks (5.4%) trip the bypass (MEASURED-RUN P6). Triggers include
"no longer", "since", "longer than", "instead". None of my 20 anti-capture negatives tripped it.
"since"/"starting"/"as of" make almost any dated sentence a "correction", which then **also** changes
dedup behaviour (section 3).

---

## 2. Whole-gate behaviour on our own corpus (MEASURED-RUN, probe.py and probe2.py, edge tier)

Corpus:
- **KEEP**: 185 lesson hook lines (text after the link) from
  `.claude/rules/agent-operating-lessons*.md`, scored leave-one-out against the other 184. Median
  length is 239 chars. Plus 8 short MEMORY.md-style project facts I wrote.
- **SKIP**: 20 hand-written anti-capture exemplars, 5 each of transient error, env/worktree one-off,
  lucky path, and unverified negative tool-claim. Plus 8 lightly reworded copies of stored lessons as
  duplicates. The store is all 185 lessons.

| Class | n | Encoded | Median score |
|---|---|---|---|
| lesson (KEEP) | 185 | **178 (96%)** | 0.477 |
| short project fact (KEEP) | 8 | **0 (0%)** | 0.265 |
| transient error (SKIP) | 5 | 2 | 0.264 |
| env one-off (SKIP) | 5 | 0 | 0.265 |
| lucky path (SKIP) | 5 | 0 | 0.258 |
| unverified negative tool-claim (SKIP) | 5 | 0 | 0.261 |
| duplicate (SKIP) | 8 | 1 | 0.239 |

That looks like good separation. The length controls show it is **length separation**:
- **P13**: the same anti-capture content rewritten verbosely at 232-248 chars is encoded
  **5 of 5** (scores 0.42-0.52, salience 0.66-0.91).
- **P14**: our 185 durable rules in **short form** (their link titles, median 28 chars, e.g. "Gate
  refusal ≠ gate result") are encoded **2 of 185**.
- **P15**: Pearson r(log(1+len), score) is **0.876** over the 221 P5 rows. Encode rate by length:

  | Length | Encoded |
  |---|---|
  | 50 or fewer | 0/19 |
  | 51-100 | 21/36 |
  | 101-200 | 21/26 |
  | over 200 | 139/140 |

Conclusion (measured on the edge tier and my labelled set, n small for the negatives): on
Claude-Code-style engineering facts, **the gate's content-sensitive parts are (a) compression novelty
for near-verbatim repeats and (b) the correction bypass. Everything else is a length prior.** Nothing
in it can recognise "transient", "env-specific", "lucky" or "unverified negative". Those classes are
semantic and about provenance; the gate's features are lexical (chat noise lists, life events,
arousal words, numbers, caps).

---

## 3. Dedup (truememory/ingest/dedup.py)

The pipeline runs dedup after the gate. The docstring says it is "adapted from Mem0's two-stage
pattern" (`:5-6`).

`check_duplicate` (`:117-245`):
1. `search_vectors(fact, limit=3)`, dropping directives (`:153-160`). Directives are never
   UPDATE/SKIP targets (#587).
2. **Score-space contract.** An absolute threshold is trusted only when `score_space == "cosine"`
   (`:169-176`). Relative, FTS or fused scores go to the LLM or to a word-overlap heuristic
   (`:228-231`). This is a nice guard (#632).
3. **Cosine > 0.92**:
   - a correction (category or markers) goes to the LLM, else to heuristic UPDATE (`:184-195`)
   - otherwise, with an LLM, the LLM decides (`:203-204`)
   - without an LLM:
     - digit-run multisets differ (`_has_divergent_numbers`, `:103-114`, #687): ADD (`:205-215`)
     - otherwise: SKIP (`:216-222`)
4. With an LLM config, **every** top candidate goes to the LLM regardless of score
   (`:237-238`, rationale `:135-141`: Model2Vec similarities are compressed). The LLM prompt is
   `:69-83` and returns add, update or skip plus merged text.
5. Without an LLM, score < 0.15 gives ADD (`:242-243`). Otherwise `_heuristic_dedup` (`:323-409`):

   | Condition | Action | Lines |
   |---|---|---|
   | is_correction | UPDATE | `:341-348` |
   | new is a substring of old | SKIP | `:351-358` |
   | old is a substring of new | UPDATE | `:360-367` |
   | Jaccard > 0.60, new not shorter | UPDATE | `:372-389` |
   | Jaccard > 0.60, new shorter | SKIP | `:372-389` |
   | sim > 0.75 and markers | UPDATE | `:393-400` |
   | otherwise | ADD | `:402-409` |

6. LLM parse failure gives ADD (`:285-287`). LLM error falls back to heuristic with sim 0.7
   (`:258-264`). This is fail-open toward keeping.

UPDATE is an **in-place overwrite**. `_update_fact` calls `Memory.update`, which goes through
`engine.update` to `storage.update_message`, which runs `UPDATE messages SET ...`
(`pipeline.py:732-759`, `client.py:282-294`, `storage.py:1178`). So the docstring claim "the old
memory is superseded (not deleted)" (`dedup.py:11`) is false for this path: the old text is gone
(MEASURED-READ).

Measured findings:
- **#687 fix is band-limited** (MEASURED-RUN P7, heuristic path). "Project deadline is October 16th"
  against "...15th" gives:

  | Score | Action |
  |---|---|
  | 0.99, 0.93 | ADD |
  | 0.90, 0.60, 0.20 | **UPDATE** (Jaccard 67%) |
  | 0.10 | ADD |

  The real edge-tier cosine for that pair is 0.878, which lands in the UPDATE band. The test
  (`tests/test_issue_687_dedup_near_token.py:45-53`) pins only the 0.99 case.
- **Cross-subject overwrite, i.e. data loss** (MEASURED-RUN P8, no LLM):

  | New fact | Old fact | Cosine | Result |
  |---|---|---|---|
  | "Alice has worked at Google since 2020" | "Bob has worked at Google since 2020" | 0.81 | UPDATE: Bob's row overwritten (Jaccard 75%) |
  | "Staging DB was migrated to Postgres 16 as of March" | "Production DB ..." | 0.9235 | "as of" marker, so treated as a correction: UPDATE, production row overwritten |
  | "The iOS app switched to SwiftUI" | "The macOS app ..." | 0.87 | SKIP: iOS fact dropped as a "shorter restatement" |

  With an LLM config these go to the LLM instead. The heuristic path is the fallback whenever no
  LLM is detected (`pipeline.py:393-400`).

---

## 4. Predictive coding and surprise (truememory/predictive.py, truememory/l5_boost.py)

**This is not a write gate.** It is a retrieval-time ranking signal. The module docstring says so
explicitly: "We do not delete low-surprise messages ... This is a ranking signal, not a hard filter"
(`predictive.py:16-24`). The gate's PE used to delegate here and no longer does (CHANGELOG.md:341-343).

`extract_facts` (`predictive.py:141-207`) builds fingerprints:
- `num:` numbers with units, `entity:` capitalised runs, `date:` dates
- `event:` a 5-word window around an event keyword
- `def:` "X is Y"

`compute_surprise_score` (`:210-307`) combines:
- noise, giving 0.05
- no facts, giving 0.1/0.2/0.3 by length
- all facts known, giving 0.1
- otherwise `0.6 * new/total + length bonus (up to 0.15) + detail bonus (up to 0.15) + event bonus (up to 0.10)`

`build_surprise_index` (`:310-366`) deletes all rows and rescans every message chronologically
(`:334-339`). It runs at consolidation (`engine.py:1105-1111`, `:1576-1586`), costing O(N) per
consolidate.

Fingerprint quality (MEASURED-RUN): "Uses bun, not npm; deadline October 15 for ClickHouse migration"
yields `{entity:uses, entity:october, date:october 15}`. The sentence-initial word counts as an
entity. CamelCase "ClickHouse" is missed because `_PROPER_NOUN_RE` (`:72-74`) wants `[A-Z][a-z]+`
with a word boundary.

L5 boost (`l5_boost.py:70-137`): `score *= (1 + alpha * surprise)` with alpha defaulting to 0.2
(`:22`). Summary, profile and contradiction rows are blocklisted (`:16-18`).
- CHANGELOG.md:357-360 says alpha was "tuned via Modal alpha sweep" (CLAIMED).
- The test header (`tests/test_l5_surprise_rerank.py:11-16`) records the research result as
  "+2.0 pts P@10 (McNemar p≈0.06, not yet significant) ... recommended shipping α=0 default and
  flipping after Modal validation at p<0.05". No artefact in the repo shows that validation
  happened, yet the default is 0.2.

---

## 5. Retrieval-side salience (truememory/salience.py), for completeness

`filter_by_salience` (`:354-406`) drops search results with salience below `min_salience`, default
0.10. Exemptions: entity-rescue ids (#582) and contradiction-sourced rows (#633). This is the
"L4 salience guard". It is a read-time filter, not a write gate, but it uses the same L3 scorer.

---

## 6. How weights and thresholds were fit, and on what data

| Artefact | Fit | Data | Used in production? |
|---|---|---|---|
| `data/l3_weights.json` | Logistic regression over 13 features. Coefficients are the mean of 10-fold LOCO-CV; the bias is a full-data fit. Training AUC 0.719 (`:34-36`). | "locomo_short_horizon_200", retrieval-utility labels. n=5882 is claimed at test_l3_salience.py:13. | **Yes.** It is gate salience for facts over 50 chars and read-time salience. |
| `data/encoding_salience_weights.json` `variant_a` | LR over the same 13 features. Training AUC 0.8708 (`:34`). | "GateLoCoMo" (named in `encoding_salience.py:9-10`), not in the repo | **No.** Only tests call `encoding_salience_a` (grep). |
| `variant_e` | LR over 15 encoding features. Training AUC 0.8919 (`:72`). The length weight is 9.42, and the `f_category_boost` weight is -0.022, i.e. category is useless (`:54-70`). | GateLoCoMo | **No.** Only tests. |
| Speech-act scores (0.02/0.2/0.8/0.7/0.6/0.05/0.08/0.5/0.25) | Hand-set constants. "Validated via 50-variant sweep" (`encoding_salience.py:216-217`). | GateLoCoMo | Yes |
| Gate weights 0.25/0.20/0.30, threshold 0.30, floor 0.10 | "multi-hundred-config sweep across weights, thresholds, and salience floors" (CHANGELOG.md:333-334); "200-variant sweep" (paper). | GateLoCoMo, described only as a "held-out evaluation set" (paper.txt:479) | Yes |
| Category offsets | "#123" (CHANGELOG.md:346-347) | same | Yes |
| Gate PE / novelty AUCs | 120- and 200-variant sweeps | same | Yes |

Reproducibility (MEASURED-READ):
- The sweep scripts and results are **gitignored**: `benchmarks/gate_eval/salience_sweep.py`,
  `run_salience_sweep.py`, `run_combination_sweep.py`, `run_weight_threshold_sweep.py`,
  `results/*.json` (.gitignore:83-89, :116-120). So are `_working/` (.gitignore:99), where the
  MEMORIST reports live.
- `benchmarks/gate_eval/` does not exist in the clone (`ls benchmarks` shows beam, locomo and
  longmemeval only).
- The paper does not describe GateLoCoMo's construction. My grep of paper.txt found no
  "GateLoCoMo".
- The only hints at labels are docstring fragments: "S4 recall" (`encoding_salience.py:217`) and
  "N2 noise, issue #118" (`:230`). This suggests a graded signal/noise labelling of LoCoMo chat
  messages: casual human-to-human chat, not agent/engineering facts.

**Every gate number is CLAIMED and unreproducible from the public repo.** The paper itself says the
gate's end-to-end effect is unmeasured (paper.txt:489).

---

## 7. Is there a gate-eval harness? What does it measure?

`tests/test_gate_eval_harness.py` exists (81 lines). It is **scaffolding smoke only**. Its docstring
reads: "verify the harness's structural plumbing ... WITHOUT actually running an LLM-driven candidate
end-to-end (that's reserved for Phase 9)" (`:1-8`).

It checks four things:
1. candidate discovery finds `v05_baseline_nogate` and `v05_gate_threshold` (`:25-30`)
2. `datasets/short_horizon_200.json` has 200 QA, seed 42, and category in {1,2,3,4} (`:33-50`)
3. the `Candidate` ABC is abstract (`:53-63`)
4. baseline construction is lazy (`:66-73`)

The module is `skipif(not benchmarks/gate_eval)` (`:21-22`). MEASURED-RUN: **4 of 4 skipped** in the
public repo ("benchmarks/ not present in CI").

The implied design is a downstream-QA A/B (gate vs no gate on a 200-question LoCoMo subset),
comparing candidates. That design is the right instrument, but its code and results are private.

Unit-test quality of the gate suite (MEASURED):
- **169 of 169 pass** with the real edge model (copied tests; shim; `pytest -q tests`). Pipeline
  tests (#649, L5 rerank, gate-enabled env, PE v044) also pass: **46 passed, 4 skipped**, in the
  sandbox venv via `uv run --with pytest`.
- **All 5 PE v044 tests also pass with the embedder DEAD** (HF cache pointed at a nonexistent dir,
  gate degraded open). They are vacuous without a model: contradiction PE >= consistent PE holds as
  0 >= 0 (`tests/test_encoding_gate_pe_v044.py:70-100`).
- `test_encoding_gate_category_threshold.py:26`: the assertion sits inside an `if` whose condition is
  false. MEASURED-RUN: score 0.40, so the branch never runs.
- `:41-53` "threshold floor" passes via the correction **bypass**, not the 0.10 floor.
- `test_encoding_gate_salience_floor.py:71`: `assert ... or True`, which cannot fail.
- `test_encoding_gate_pe_floor.py:18-35` documents a PE formula (`surprise*0.9`) that no longer
  exists.
- `test_encoding_salience.py:86-112` is named "AUC" but checks mean(signal) > 5 x mean(noise).
- `test_issue_585_encoding_gate_pe.py:40-44`: a `with patch(...): pass` no-op.

---

## 8. Our human-written anti-capture list vs TrueMemory's learned/heuristic gate

Our rule, embedded in `hooks/memory-nudge.sh:560` and `commands/harvest-skill.md:24-26`, is to skip:
- transient errors
- environment/worktree-specific one-offs
- lucky paths
- negative tool-claims (verify before encoding)
- anything already covered, i.e. duplicates

| Our rule | TrueMemory equivalent | Where | Effective? |
|---|---|---|---|
| transient errors | Extractor prompt "Transient debugging details (error messages, stack traces, temp fixes)" | `extractor.py:90` | Prompt-level only. **The gate has no feature for it**; verbose transient errors pass 100% (P13). |
| env / worktree one-offs | none (closest: "Things obvious from the codebase or git history", `:93`) | | No |
| lucky paths | none | | No |
| unverified negative tool-claims | none. `source_role` and `confidence` exist (`extractor.py:101-102`) but are unused (`pipeline.py:472`) | | No |
| duplicates | compression novelty (near-verbatim), dedup ADD/UPDATE/SKIP with LLM arbitration, 0.85-cosine pre-check on the prompt path | sections 1a and 3 | **Yes, for near-verbatim.** Paraphrase relies on the LLM. |
| (ours has no equivalent) chat noise ("ok", "lol", greetings) | noise sets, speech-act scores, salience floor | `encoding_salience.py:219-292` | Irrelevant to us; we never write chat noise. |
| (ours has no equivalent) corrections are high value | correction bypass, category offsets, correction never SKIPped at dedup | `encoding_gate.py:277-281`, `dedup.py:184-195` | Yes, but over-broad via "since/as of/starting/actually" |
| "only USER-stated facts" / not the assistant's suggestions | extractor instruction | `extractor.py:94` | Prompt-level only |

Conceptual difference:
- **Our list is about provenance and durability.** Was this verified, will it recur, is it
  environment-bound?
- **TrueMemory's gate is about information and redundancy.** Is it new relative to the store, is it
  "important" chat, does it contradict?

The two are nearly orthogonal. TrueMemory's durability judgement lives entirely in the LLM extractor
prompt, which is the same mechanism we use: model judgement under a written rule. **TrueMemory does
not show that a numeric gate can replace our list.** On our corpus it reduces to a length prior plus
a near-duplicate detector.

---

## 9. What transfers (first-pass ideas; nothing here was built)

1. **Compression-novelty duplicate check before writing a topic file.** Compute
   `(gz(M+f) - gz(M)) / gz(f)`, where M is the concatenated nearest existing topic files (grep or
   name/description match; top-k). Warn if below about 0.2-0.25.
   - Cost: stdlib gzip, milliseconds, no model.
   - It measurably caught 7/8 near-copies (P5) and the exact duplicate (P9 n=0.08).
   - Correct for gzip header bias: subtract about 20 bytes, or compare against a length-matched
     random baseline.
   - Use it as a nudge or report, not an auto-drop.
2. **Admit/reject reason strings with a signal breakdown**, as in `_explain`. Each memory write or
   refusal would log `why` (duplicate-of X, correction-of Y, category) to a ledger, so write-side
   behaviour is auditable. It fits the MEMORY_KNOWLEDGE_V2 "measurement exists at all" thesis.
3. **Correction-first asymmetry.** Corrections bypass the gate and are never SKIPped at dedup. They
   are routed to supersede. Our analogue: a memory write that contradicts an existing topic file
   must edit or supersede that file, never append a sibling. That means a lint that finds same-topic
   files with opposing claims.
   - Borrow the **idea**, not TM's marker list: "since/as of/starting/actually" are far too broad
     (P6, P8).
4. **Numeric-divergence guard** (`_has_divergent_numbers`). When our compaction or harvest merges
   two memory lines, refuse to treat lines whose digit runs differ as duplicates. The multiset
   compare is trivial.
   - Apply it consistently across all similarity bands, unlike TM (P7).
5. **Score-space contract.** Never compare a relative or fused score to an absolute threshold
   (`dedup.py:169-176`). This matters if we ever add a similarity check over MEMORY.md.
6. **Extractor-prompt shape.** An EXTRACT/DO NOT EXTRACT list, each fact tagged `category`,
   `confidence` and `source_role` (user vs inferred), with "write as a fact, not a quote"
   (`extractor.py:78-102`). This is directly comparable to our nudge. The transferable upgrade is
   to **make `source_role` and verification status load-bearing**, which TM does not do:
   - `inferred` or unverified negative claims route to a pending or quarantine tier, not the index.
   - This operationalises our "verify before encoding" clause.
7. **A gate-eval harness done properly.** TM's own conclusion is that write gates are unmeasurable
   without a downstream A/B, and its harness is private or skipped. Our version:
   - A labelled set of past memory candidates (KEEP/SKIP by our anti-capture classes).
   - A replay that scores any rule or nudge change by precision/recall on that set.
   - Length-matched controls, because P13/P14 show a length confound will fake success.
8. **Don't import:**
   - speech-act and chat-noise salience (tuned on LoCoMo chat; misfires on "Supabase ...", P2)
   - L3 length-driven salience
   - edge-tier pair-difference PE (does not separate contradiction from unrelated, P9)
   - the fail-open-forever PE degradation
   - in-place UPDATE overwrite without history (`storage.py:1178`)

Scratch artefacts: `/tmp/tm-research/gate-scratch/`, which holds:
- `probe.py`, `probe_out.json`, `probe2.py`, `probe2_out.json`
- `shim/` and `tests/` (copied)
- `paper.txt`
- `venv/`, a local model2vec venv
