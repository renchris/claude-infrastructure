# Gap 2: replaying the real misses through fielded FTS5

Date: 2026-09-27. Scope: the 14 operator-voiced memory misses (`our-usage.md:150-166`) and the
hand-confirmed lesson recurrences (`our-usage.md:131`, `SYNTHESIS.md:293`). For each one: was the
answer stored **before** the miss (**gold-missing** vs **captured**)? If it was stored, would the
proposed retriever (#4, fielded FTS5 10-5-1) have surfaced it?

Labels: **MEASURED** = I ran or read it in this pass. **ESTIMATED** = the method is stated.
Nothing outside `/tmp/tm-research/` was written. Every store, repo and DB was read only.
`~/.claude/session-index.db` was opened with `mode=ro`. `claude-search` was not run, because it
INSERTs into `search_log` (`claude-session-search/bin/session-search.py:892`).

## 0. Artifacts (all under `/tmp/tm-research/gap2/`)

| file | what it is |
|---|---|
| `sessprobe.py` / `sessprobe.json` | For each miss session: transcript path, miss timestamp, which MEMORY.md was attached (`instructions` → `AutoMem`), and memory/lesson touches before the miss |
| `bgrep.sh` | Case-insensitive grep over a store, printing birth time, mtime and hit count per file (`/usr/bin/grep`; plain `grep` here is ugrep) |
| `replay.py` | The replay library. It reuses `tm-empirical/harness/common.py` (`terms`, stopwords, `split_frontmatter`, `title_of`), so tokenisation matches the 50-query bake-off exactly. Ranking is fielded FTS5 `bm25(d,0,10,5,1)` over name+H1 / description / body, matching `harness/baselines.py:57-62` |
| `run_replay.py` → `replay_results.json` | 19 cases × 3 scopes × 3 query forms, with a gold-at-time status per gold file |
| `hist_rules.py` | Recurrences replayed against the rules file **as committed at the time**, one row per `- ` hook line (the #4 design's "one row per hook line") |
| `field-queries.json` | The 19 real field queries (operator verbatim + an agent-style form + time-valid gold). This is the seed #5 asked for (`SYNTHESIS.md:268-269`) |
| `dace.txt`, `d71.txt`, `adb-after.txt` | Dialogue excerpts behind #10/#11/#13, #78 and #106 |

**Gold-at-time rule.** A file counts as gold only if it existed before the miss, by its
filesystem **birth time** (`stat -f %B`; store files) or its **first git add** (repo docs). Files
born after the miss are dropped from the index at replay time. Files that were *modified* after the
miss are kept, but flagged, since their current text can contain later additions. No store
history exists to rewind them: `~/.claude/backups` keeps 10 copies per basename and has none of
these files.

**Scopes replayed.**
- **P**: the #4 default. The current project's store (realpath) plus that repo's `docs/lessons/*.md` and `.claude/rules/*.md`.
- **A**: `--all`. Every physical store under `~/.claude/projects` (realpath-deduped, 1,387-1,816 docs at the cutoffs) plus P's rules and lessons.
- **X**: A plus repo docs (`docs/**`, commands, skills, `*/*.md`) for infra, reso and personal (2,339-5,556 docs). This is **not** proposed anywhere. It is here only to show where the answers actually lived.

**Query forms.**
- `op`: the operator's verbatim prompt. This is what a UserPromptSubmit hook (#23) would see.
- `op12`: the first 12 terms of `op` (the #4 cap, `SYNTHESIS.md:235`).
- `ag`: a short keyword query of the kind an agent might type into `cc-memory-search`. **Threat:** I wrote `ag` after I had seen the gold, so treat it as an upper bound. `op` is the only author-independent form.

## 1. Where each miss's answer was, at the moment of the miss (MEASURED)

Times are UTC. The machine is CDT (`date +%Z`). Transcript paths are in `sessprobe.json`.

| # | content | answer before the miss? | evidence | class |
|---|---|---|---|---|
| #10 (08-29 16:58, personal) | read the WhatsApp thread in full, refetch before each draft | **Rule yes, mechanism no.** `feedback_quote_the_thread_not_the_recollection.md` (born 08-26) and `feedback_draft_outbound_messages.md` (08-26) existed. The session had **edited the first one itself at 12:33Z** that day (`sessprobe.json` touches). The root cause, `bin/wa` printing newest-first so `tail` shows the oldest rows, was stored only *after* the complaint, at 17:01Z (`dace.txt`: the append to `whatsapp-db-query-gotchas.md`). | **in-context, not obeyed**, plus a mechanism fact that was gold-missing |
| #11 (08-29 17:03, personal) | "balance cleared before account closes" wrongly implies nothing is due later | Yes. `project_vista_real_moveout.md` (07-22), `moveout-vendor-portal-sweep.md` (08-25). The very next assistant turn states the 21-day itemized statement correctly (`dace.txt:242`), so the fact was in context. The error was in drafting. | **in-context composition error**, not retrieval |
| #13 (08-29 23:41, personal) | "are you sure no steamer?" | Not a cross-session fact. The operator had said "making good progress with steamer" in the same session at 22:46Z (`dace.txt:254`). The agent then advised against steaming quartz, and later reversed (`dace.txt:595-599`). | **not a memory miss** (judgement inside one session) |
| #47 (09-12 15:44, reso wt-pool-7) | "do our own manual Google-images curation again like normal" | **The operator's practice was never stored as a rule, and stored knowledge said the opposite.** 12.5 h earlier the operator typed "we just go through 'at least 4mb' images on google images" (`prompts-typed.jsonl`, 5e498dc5, 03:14Z). The workflow that followed wrote `.claude/rules/bottle-reference-sourcing.md` (first add `ebfc88fc2`, 09-12T04:26Z; path-scoped `paths:` frontmatter), which opens **"Replaces: 'at least 4MB on Google Images.'"** (`git show 44c80a75f:…:24`). "Operator curates, agent does not" became a ruling only on 09-23 (HEAD `bottle-reference-sourcing.md:15`). The review tool's Google-Images link (`cdc9f3e97`) was the only trace of the practice. | **gold-missing preference, overwritten by agent-authored memory** |
| #48 (09-12 19:03, reso wt-pool-7) | "supplementary image input … keep forgetting every single time" | **Yes, since 03-26.** `feedback-dual-ref-learnings.md` documents `--ref-image2` as the supplementary reference ("ref2 provides supplementary signal"). It has been unchanged since. Its only inbound link is the demoted `MEMORY-ARCHIVE.md`. That session had wrongly concluded `--ref-image2` landed "the previous day" (`memwrites.py` output: the 21:33Z append "HAS EXISTED SINCE 2026-03-26, not since 2026-09-11"). | **captured, unreached: a true retrieval miss** |
| #66/#67 (09-16 17:16 / 20:02, kitty) | "we lost click-title-to-drag again … flip-flopping" | **The priority rule was gold-missing.** Nothing in the infra store or lessons before 09-17. The lesson `a-draggable-pane-title-outranks-every-other-title-bar-property-o.md` was born 09-17T19:31 CDT, after the miss. The facts existed only in repo research docs: `docs/research/kitty-pane-title-overlay-2026-09-14.md` ("the drag works in his config", `fe58ca02d`), with the plan and research docs committed between the two prompts. #66 ran in `/private/tmp/wt-kitty-overlay` with the infra MEMORY.md attached (24,187 chars). | **gold-missing (preference ranking); facts outside #4's scope** |
| #78 (09-21 02:18, personal) | "like we did before … at our past visited cafes" | **Yes.** `mac-tether-service-order.md` (last modified 09-13T16:30 CDT, so unchanged since) holds the Houndstooth sitting: café DNS 40 ms beats 1.1.1.1's 76 ms, "the switch trigger is LATENCY, not Mbps", "exhaustive client-side sweep found no local lever left". But it sits under a tether-named topic whose index line (`MEMORY.md:20`) says nothing about cafés. The session found `~/Development/personal/wifi-diagnosis/` (home Wi-Fi, 09-15) by `find -iname '*wifi*'` in 12 s. It then **re-ran a DNS race against 1.1.1.1/8.8.8.8/9.9.9.9** (`d71.txt`, 02:21:49Z), re-deriving a stored finding. | **captured, partial retrieval miss** |
| #88 (09-22 04:33, infra) | "we used it 2-3 times … prompted it to use a diff" | **Yes, in another project's store.** `reso…/memory/project-exhaust-improvements-skill-2026-06-13.md` (06-13), plus the reso command `.claude/commands/exhaust-improvements.md`. The session's cwd was infra. `claude-search` returned a relevant session at rank 1, yet the agent answered "that skill doesn't exist". One operator push later it found three runs via reso git history. Source: the dialogue dump at `~/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/41eee6a5-9f2e-4f8d-a9e7-97077cee73d1/tool-results/bxcl3fb1k.txt`, lines 242-250 (the search result), 271 ("doesn't exist") and 398 ("three runs"). | **captured in another store (scope miss) + surfaced-but-dismissed** |
| #106 (09-26 21:19, reso wt-pool-2) | "retrieve that Dynamic Workflow research from a week ago" | **Gold-missing from every store, lesson, rule and doc.** `pinterest` matches 0 files in any store and 0 rows in `sessions_fts`/`chunks_fts`. The result lived only in workflow JSON under session dirs (`…wt-pool-7/5e498dc5…/workflows/wf_850036ea-183.json`, `…/d83af9ce…/workflows/wf_05868c2b-dcd.json`). The agent recovered it in about 3 min with `find -path '*workflows*' \| xargs grep -il pinterest` (`adb-after.txt`, 21:20-21:25Z). | **gold-missing (undistilled episodic artifact)** |
| #110 (09-27, infra) | "(we may have done this before)" | No: `our-usage.md:159`, `SYNTHESIS.md:44-46`. | **gold-missing (true negative)** |
| #29 (09-09 01:56, infra) | "commands given to a user = something you can't run" | **Resident, plus a copy in another store.** Global `CLAUDE.md:812` (the `▶ Run this:` row is "only when the operator must do something") and `:992-998`. The exact rule is also in the reso store as `feedback-run-this-is-for-what-you-cannot-run.md` (08-26). | **resident, not obeyed** (plus a cross-store copy) |
| #58 (09-14 03:35, voiceink) | "don't jump into implementation until we sign off" | **Gold-missing in voiceink.** `implementation-gating.md` was born 03:36:03Z, **17 s after the prompt**, by the same session (`originSessionId: 61853387`). The nearest earlier capture is reso's Stripe-specific `feedback-exhaustive-research-before-implementation.md` (06-25). No earlier voiceink prompt states it (`prompts-typed.jsonl`). | **gold-missing; the operator's first statement here, captured at once** |
| #70 (09-17 04:34, fde) | "Remember: Pyramid, MECE/SCQA, no mannered prose" | **Mostly gold-missing.** The fde store was **empty**: all its files were born 09-17T19:49Z, 15 h later (`TZ=UTC stat`). The session had no AutoMem attachment. The operator had pasted the same mannered-prose paragraph **twice on 09-16** in infra session 19f6b94b (13:39Z, 16:33Z) and nothing captured it until `feedback-explainer-pages-plain-language.md` (09-26). The Pyramid half was stored in *other* stores: reso `feedback-pyramid-terms-invisible.md` (04-16) and `feedback-minimal-pyramid-output.md` (06-21); personal `feedback_lead_with_the_one_sentence.md`. | **gold-missing (prose rule) + cross-store (Pyramid)**. A pre-emptive restatement, 1.4 min into the session |
| #79 (09-21 02:30, reso wt-pool-2) | "not signed off until human-sourced images + human sign-off on the ranked image" | **Half resident.** `.claude/rules/bottle-generation-ledger.md` (no `paths:`, so always loaded) at `305989f18` says "The agent NEVER signs off … nothing bakes without it" (`:205-206`, `:240-242`). The "human-sourced" half became a ruling only on 09-23. | **resident (sign-off half) + gold-missing (sourcing half)**. A pre-emptive restatement, 2.5 min into a resume brief |

### Tally (14 items; #66/#67 counted once, as in `our-usage.md:166`)

| class | items | n |
|---|---|---|
| **Captured but not surfaced, fixable at #4 default scope** | #48 (clean); #78 (partial) | **2** |
| Captured in *another project's* store (needs `--all`) | #88 | **1** (plus cross-store halves of #29 and #70) |
| **Gold-missing: never stored before the miss** | #47, #58, #66/67, #70, #106, #110 | **6** |
| Stored and in context or resident, not obeyed (adherence) | #10, #11, #29, #79 | **4** |
| Not a cross-session memory miss | #13 | **1** |

`our-usage.md:166` says the misses cluster in personal, episodic and procedural content. That
holds, with a caveat: **none of the four personal ones was a retrieval miss**. #10, #11 and #13
were in-session, and #78 was mostly found. The personal store served these sessions well. The
failures were adherence and a tool-output mechanism (the #10 `tail`).

## 2. Replay through fielded FTS5 (MEASURED, `run_replay.py`, 44 s wall)

Rank of the first time-valid gold file. `—` = not in the top 50. `n/a` = no time-valid gold exists.

| # | P op / op12 / ag | A op / op12 / ag | X op / ag | note |
|---|---|---|---|---|
| #10 | 1 / 1 / 1 | 1 / 1 / 1 | 1 / 1 | already in context |
| #11 | 1 / 1 / 1 | 1 / 1 / 1 | 2 / 5 | already in context |
| #47 | n/a | n/a | runbook 7 / 4 | **top-1 in P and A is `bottle-reference-sourcing.md`, the playbook that says "Replaces … Google Images"**. Retrieval would have reinforced the wrong answer |
| #48 | **1 / 1 / 1** | 1 / 1 / 1 | 1 / 1 | the operator's own words find the March memory at rank 1 |
| #66 | — | — | 3 / 1 | only the research doc (X scope) |
| #67 | — | — | 5 / 2 | same |
| #78 | **4 / 15 / 1** | 2 / — / 1 | 4 / 1 | in the top 5 on verbatim; the 12-term cap drops it (the first 12 terms are SSID, access code and "3 hours") |
| #88 | — | **2 / — / 2** | 1 / 1 | needs `--all` |
| #106 | n/a | n/a | n/a | nothing indexed anywhere |
| #29 | 39 / — / 42 | — / — / **1** | — / 2 | only with an agent-phrased query and `--all` |
| #58 | n/a | n/a (reso Stripe rule not in top 5) | n/a | born 17 s later |
| #70 | n/a (P has 0 docs) | Pyramid: **reso `feedback-pyramid-terms-invisible.md` rank 1** on `op` | — | mannered-prose rule absent |
| #79 | 4 / 45 / 1 | 6 / 46 / 1 | 5 / 1 | the ledger is resident anyway |

**Lesson recurrences** (the symptom or command text is the query; infra scope; cutoff = recurrence time):

| family | gold at the time | rank of the gold hook line (`hist_rules.py`, rules at that commit) | P-scope file rank (op / ag) |
|---|---|---|---|
| never-wrap-ship (`timeout 3000 bash scripts/ship-land.sh`, 09-18) | rules hook, resident | **1** of 130 lines | body 1 / 2 |
| never-wrap-ship (kill message, 09-17T04:59) | rules hook (the body was born 09-17 later) | **1** of 122 | — (the body did not exist yet) |
| never-write-tracked (`cannot rebase: You have unstaged changes`, 09-09T05:05) | rules hook `bb4e8b296` (02:55Z, 2 h earlier) | **1** of 35 | — (the body was born 09-17) |
| worktree-ops-can-bare (`fatal: this operation must be run in a work tree`, 09-06) | memory topic | (not in rules then) | 4 / 2 |
| tab-is-ifs (`while IFS=$'\t' read -r …`, 09-23) | rules hook + body + topic | **2** of 208 | 45 / 1 |
| symlinked-store-invisible-to-find (09-27) | memory topic | — | 4 / 1 |

Every recurrence had its gold captured, and most had it **resident** (`our-usage.md:129`: 71%).
FTS5 ranks that gold 1-4 from the raw symptom text. **So these are trigger misses: no query was
ever issued.** A pull tool (#4) or a prompt hook (#23) does not fire on them. Only a
tool-output path (#6) does. This matches the #6 premise (`SYNTHESIS.md:283-300`).

**Cross-store pollution** (the #4 concern, `SYNTHESIS.md:231-232`). Measured on these real
queries, moving from P to A changed the gold rank as follows:
- unchanged: #10, #11, #48;
- improved: #78 (4 → 2);
- slightly worse: #79 (4 → 6).

`--all` was **required** for #88 and the #70 Pyramid half. On this n=13 it helped more than it hurt.

**Session index** (#18 substrate, `mode=ro`): `sessions` holds 9,422 rows, but `sessions_fts` holds
40 and `chunks_fts` holds 679. `pinterest`, `perrier`, `react doctor`, `truememory` and `image2`
each match 0 rows. The #106 answer is in workflow JSON, which the session indexer does not read.
So #18 could not have helped any episodic miss here, even once #2 is fixed, unless #2 also indexes
`workflows/wf_*.json`. This supports the #18 premise note (`SYNTHESIS.md:562-565`: "agents found
them with find or git log").

## 3. What this does to Finding 1 and the dispositions

**Finding 1 ("our binding problem is retrieval, not capture", `SYNTHESIS.md:26`) is overstated
for the real misses.**

| population | captured and fixable by pull retrieval (#4 default) | captured elsewhere (`--all`) | gold-missing (capture) | captured and delivered, not obeyed | trigger miss (needs #6) |
|---|---|---|---|---|---|
| 14 operator-voiced misses | 2 (#48, #78) | 1 (#88) | 6 | 4 | 0 |
| ~8-12 lesson recurrences | 0 | 0 | 0 | (resident in ~71%) | all |

The consult-rate and bake-off evidence behind Finding 1 is real: the 2.0% consult rate and the
R@5 0.52 → 0.88 gain. But on the misses that actually hurt:
- (a) the largest class is **gold-missing**, and 4 of those 6 (#47, #58, #66/67, #70) are
  **operator rulings or preferences stated in a session and never written down**;
- (b) the recurrences are **delivery or trigger** failures;
- (c) pull retrieval fixes **2-3 of 14**.

The better framing is **"delivery and capture of operator rulings, with retrieval as a cheap
substrate"**. "Retrieval, not capture" does not fit.

**Proposed disposition changes (ESTIMATED, from the tally above; n=14 is small):**

1. **#4 derived-fts5-memory-search: keep build-now, lower its conviction (78 → about 70), and
   re-scope.**
   - It is still cheap, and it closes #48-type misses: a March memory reachable only from a
     demoted archive, found at rank 1 from the operator's own words.
   - Two design changes follow from the replay:
     - **Search `feedback`-type topics across all stores by default.** The #70 Pyramid rule, #29
       and #58's nearest rule all lived in reso or personal while the work ran in fde, infra or
       voiceink. Keep `--all` opt-in for project and reference topics.
     - **Do not apply the 12-term cap to a verbatim prompt**, since it dropped #78 from 4 to 15. Or
       rank the terms by rarity before capping.
   - Its eval must count "retrieval **reinforced** a superseding memory" (#47) as a failure class,
     not as a hit.
2. **#5 memory-eval-harness: no longer blocked on #4 for field queries.**
   `gap2/field-queries.json` is 19 real queries: 13 operator-verbatim plus 6 recurrence symptoms,
   with time-valid gold and a `gold-missing` label on 5. That is the non-agent-authored set #5 wanted
   (`SYNTHESIS.md:268-269`) and the answer to the §5.1 threat (`:719`). Weight tuning (10-5-1 vs
   5-3-1) cannot be settled on it: only 5 of 13 operator items have time-valid gold in P scope.
3. **#26 speech-act-nudge-trigger: raise from experiment (55) to build-now-shadow, into Wave B
   beside #4.**
   - The dominant gold-missing class is operator rulings: #47's practice, #66/67's "draggability is
     primary", #70's prose rule stated twice on 09-16, and #79's sourcing half.
   - The #26 note measured 5 hits and 0 new rules on its narrow regex (`SYNTHESIS.md:648-653`).
     That regex keys on "remember/from now on/i told you". Those are **restatement** words, which
     fire after the miss. The capture moments here were plain imperatives ("WRITE THIS WAY", "we
     just go through at least 4mb…").
   - So the trigger must widen to instruction-shaped operator text, **or** #24's Stage 0 should
     score exactly these four capture moments.
   - I did not measure the precision of a widened regex. That is the open cost.
4. **#24 candidate-extractor-worker: correct its gate text** (`SYNTHESIS.md:639`).
   - "abstains on #70, which was already stored" is time-invalid. The fde store was empty at the
     #70 miss and was born 15 h later.
   - "surfaces the voiceink sign-off rule (#58)" is also weak. The live session stored #58 17 s
     after the prompt.
   - Better Stage-0 targets: session 19f6b94b 09-16 (mannered prose), 5e498dc5 09-12T03:14 (the
     Google-Images practice), and the 09-14/15 kitty sessions (drag priority).
5. **#12 structured-supersession / #27 provenance: add the #47 pattern as a named case.** An
   agent-authored research artifact superseded an **operator practice** with no operator ruling.
   A `Receipt:`/provenance line that marks "Replaces: <operator practice>" as needing a ruling would
   have flagged it. This is the only miss where more retrieval would have done harm.
6. **#18 episodic-session-recall: unchanged (build-later), with one added dependency.** None of
   #78, #88 or #106 needed it: they were found by find or git in 12 s to 3 min, and the index holds
   0 relevant rows. If it is built, #2 must index workflow result JSON (`*/workflows/wf_*.json`), or
   #106-type misses stay invisible to it.
7. **#6 symptom-to-lesson: reinforced.** Every recurrence was captured and FTS-rankable at 1-4 from
   its raw symptom text. The gap is purely the trigger.
8. **#23 userprompt-pointer-recall: stays an experiment.** On verbatim prompts it puts time-valid
   gold in the top 5 for #10, #11, #48, #78 and #79 (P) and for #88 and #70-Pyramid (A). But 3 of
   those 5 P hits (#10, #11, #79) were already in context, so the net new is about 2-4 of 14 per
   month.

**Wave order.** The replay does **not** flip #4 below capture work. #4 stays cheap and is still the
substrate for #5, #16 and #23. It **does** argue for:
- adding #26 (widened, shadow) to Wave B;
- starting #5 now on `field-queries.json` instead of after #4;
- leaving #18 where it is, since its premise holds;
- leaving #24/#25 as experiments whose Stage 0 targets change as in item 4.

"Capture outranks #4" is **not** supported. Capture outranks #23, and it ties #4 on the evidence.

## 4. Caveats

- n=14 operator items and 6 recurrence strings. One analyst classified them. The
  pre-emptive-restatement reading of #70 and #79 is judgement: both came 1.4-2.5 min into a
  session, before any agent error.
- Modified-after-miss gold (#10 `whatsapp-db-query-gotchas`, #11 `project_vista_real_moveout`,
  the #79 ledger, the #47 runbook, the #88 command) was indexed with its **current** text. There is
  no local store history to rewind (that is #11's premise). Their ranks may be optimistic.
- The `ag` queries were written with gold known. Only the `op` column is author-independent.
- Rules files in the P/A/X scopes are one row per file. Only `hist_rules.py` uses one row per hook
  line at the historical commit.
- The regex proxy in `our-usage.md` §4 only sees misses the operator voices. Silent misses (like
  the #78 DNS re-derivation, which the operator never flagged) are not in the 14, and they skew
  toward rank misses. The retrieval share above is therefore a lower bound on retrieval's share of
  *all* misses, not an upper bound.
