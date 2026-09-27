# U5 — personal, agent-secrets, mac-bootstrap, hammerspoon-config

Scope: ~/Development/personal. `git log --since=30.days | wc -l` gives **220** commits, not 225; 158 of them are `docs:`. Read-only; no ms365 or network calls. One deviation: I ran a single `sqlite3 -readonly` COUNT on chat.db. It returned 0 and I used nothing from it.

## Ranked table

| # | Name | Plug-in | Judgment | Consumer | Volume | Replaces (cost / miss) | Value | Privacy | Effort | Conviction |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Outlook incremental classify | `outlook-cleanup/pipeline/pipeline.py:269` (Path A); `claude-private/skills/outlook-cleanup/SKILL.md:115-116` (Path B) | choice, map below | `pipeline.py quarantine` (moves DELETE into `_ToReview-*`) | ~490 new mails/month (estimated). Measured: 461.8/mo mean still in the Inbox for 2025-05..2026-04, from python over messages.jsonl | Sonnet-subagent shard. The skill's own `cost.py` puts it at **$0.63/run** API-equivalent (~160K in / 10K out tokens), paid from claude.ai quota. Miss rate: rescue rules flipped **1,667 of 4,554** (36.6%) LLM DELETEs back to KEEP (rescue-audit json) | Runs unattended with no Claude session. Returns calibrated probabilities where Sonnet returned the rationale-free ABSTAIN | operator's own mail (banks, health, landlord). Not customer PII | ~6 h | 30% |
| 2 | Outlook ABSTAIN backlog | same code, a one-shot over `verdict=="ABSTAIN"` ids | same | same | **2,716** ABSTAIN (measured), plus ~2,000 uninventoried since 05-21 (estimated, 4 months × 490) | Nothing. Today an ABSTAIN is never acted on | Resolves 7.4% of the inbox that sits undecided forever | same | +1 h on #1 | 25% |

No other candidate qualifies (see Rejected).

## Re-verified numbers (measured: python over files in ~/Development/personal/outlook-cleanup)

- **Verdicts: confirmed.** classifications.jsonl has 36,470 rows (36,470 unique ids). KEEP 30,867 · DELETE 2,887 · ABSTAIN 2,716.
- **Sources: confirmed.** `sonnet-subagent` 31,837 · `deterministic-fallback` 2,808 · `sonnet-subagent+rescue` 1,663 · `keep-list` 158 · `deterministic-fallback+rescue` 4. Every ABSTAIN has `source=sonnet-subagent`.
- **Correction:** the "293 chars" median is **subject+bodyPreview**. bodyPreview alone has median 255, which is also its maximum because Graph truncates it at 255. Subject median is 41. Subject+preview+from averages 317 chars.
- **New finding:** the label `sonnet-subagent` overstates how much LLM judgment happened. **3,900** of those rows carry templated keyword rationales. **681** are KEEP because of the substring `"rma"`, and **0** of the 681 contain RMA as a whole word (a regex test, `\bRMA\b`). Some shards ran keyword scripts: the "regex with known misses" Jev replaces.
- **Quarantine: confirmed.** executions.jsonl shows 2,885 moves ok (plus 1×504 and 1×429). state.json has `purge_ts: null` and there is no deletions.jsonl, so nothing has been purged in 128 days since 2026-05-22.
- **Inventory: confirmed.** `last_inventory_ts` is 2026-05-21T22:04Z. The newest message is dated 2026-05-21T22:01Z.

## Outlook plug-in spec

**Where**
- **Path A.** At `pipeline.py:269` (`batch.append(msg)`), call Jev once per message before batching. If the answer is confident, write the verdict with `source:"jev"`; otherwise append the message to the Haiku batch (`_flush_batch`, :284).
- **Path B (the skill).** Add `bin/jev_prefilter.py` between SKILL.md:115 (deterministic.py) and :116 (sharding). It appends `source:"jev"` rows, so sharding skips those ids.
- **Transport.** Pipe `{state, questions}` into claude-infrastructure's `scripts/jev/evaluate.mjs` via subprocess. (cross-repo Node dependency).
- **Order is unchanged.** keep-list, deterministic.py and rescue.yaml still run, so a rescue still overrides a Jev DELETE.

**State** (~80 tokens): `From: <addr>\nSubject: <s>\n<bodyPreview>`. Only that message's own content, which satisfies hard constraint #1.

**Question** `verdict` (choice):
- `KEEP_TRANSACTIONAL`: order, receipt, shipping, refund, RMA, statement, tax, lease
- `KEEP_SECURITY`: OTP, sign-in, password, 2FA
- `KEEP_PERSONAL`: a person writing to a person, or a Re:/Fwd: thread
- `KEEP_SUBSTANTIVE`: editorial the user reads
- `DELETE_PROMO`: sale, discount, "last chance", "we miss you"
- `DELETE_NOISE`: generic social or product notification with no action

**Auto-apply thresholds** (both groups are summed probabilities)
- **DELETE:** P(DELETE_*) ≥ **0.98**. This is the only calibration datum available: 97.8% precision at p≥0.98 on the phishing benchmark. The action is a reversible quarantine move (7-day soak, 30-day recovery).
- **KEEP:** P(KEEP_*) ≥ **0.90**. KEEP is a no-op; the cost of an error is one promo left in the inbox.
- **Otherwise:** write ABSTAIN. For incremental runs I recommend *not* sending that remainder to Sonnet. A Sonnet shard's ~50K-token preamble is fixed, so escalating a small remainder forfeits most of the saving.

**What Sonnet still handles.** The first full re-classify, if the operator wants one, and any ABSTAIN remainder they choose to escalate. Jev emits no free text, so `evidence_quote` becomes the subject and `rationale` becomes `"jev DELETE_PROMO p=0.99"`. The operator must accept that under constraint #1.

**Calls and cost** (estimated: ~600 tokens/call × $0.042/M = $0.000025; one call per message)
- Monthly, 490 calls: **$0.012**, ~33 min at 14.8/min.
- Backlog, 2,716 + ~2,000: **$0.12**, ~5.3 h.
- Full 36,470 re-run: **$0.92**, ~41 h. The skill's own estimate for the same run is $36.99 on the Sonnet path or $9.56 on the Haiku path (`cost.py`).

**Quota saved** (estimated from `cost.py` constants)
- Per monthly run: one Sonnet subagent shard of ~160K input + 10K output tokens, plus the lead session's orchestration. That is ≈$0.63 API-equivalent per run, ≈$7.6/year.
- Per backlog pass: 5 shards, ≈$3.13.
- Trivial in dollars; the gain is classification without an interactive Claude session.

**Coverage is unmeasured.** The phishing benchmark auto-decided only 7% at p≥0.98. Before wiring, run a shadow pass over a stratified 2,000-row sample of the existing verdicts (~$0.05, ~2.3 h) and measure coverage and agreement at each threshold. Exclude the 3,900 keyword-template rows from the gold set.

**Blockers and concerns**
1. `evaluate.mjs:58` defaults ZDR to on and fails closed, but our plan has no ZDR. Sending personal mail would need `CC_JEV_ZDR=0` and an explicit operator decision: the file's own header says it is "NOT a licence to send private corpora".
2. The pipeline is stalled at a **human** step (soak review / purge since 05-22), not at classification. Jev does not move it forward.
3. Nothing is scheduled today: there is no personal launchd job (checked `ls ~/Library/LaunchAgents`). Unattended runs would need a new job, and inventory needs an MSAL token.

## Other personal automations (item 2)

| Automation | Classifies text? | Volume |
|---|---|---|
| `msg` (bin/msg) | No. It is a read-only FTS/SQL query tool with no triage consumer | `msg stats` (measured): 215,227 unique messages, 1,242 live since the 2026-08-15 sign-in (≈30/day, estimated) |
| financial-ssot `build_ssot.py` | No. It passes through the bank's own category and buckets the rest as "Uncategorized" | `raw/` and `out/` are empty (measured `ls`), so 0 |
| Transcript speaker arbiter (`bin/apply-arbiter`, `apply-splits`) | Yes, LLM speaker labels | 2 interviews, one-off, superseded by `apply-reseg` (docs/research/mario-interview-transcripts-2026-09-12.md:109) |
| Receipts / calendar / notes | None found | Receipts are handled inside Outlook cleanup. The outlook plan records zero meetings |

## Rejected

- **`msg` triage.** No consumer; would be a new build over third parties' texts.
- **financial-ssot categorisation.** Never run (0 rows).
- **Speaker arbiter.** One-off, superseded, needs long context.
- **car-transport triage.** Manual phone checklist, one July episode.
- **voicemail-archive.** 95 archived records with no consumer.
- **mb-hpc-price-watch.** Structured JSON/table diff; deterministic.
- **agent-secrets.** Only a `doctor --redact` regex; secrets must not go to a third-party judge.
- **mac-bootstrap.** Only model is the VoiceInk *rewrite* generator, deliberately local-only (Ollama).
- **hammerspoon-config.** Screenshot, paste and Dock hotkeys. No text judgment.
