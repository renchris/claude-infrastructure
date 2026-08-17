---
name: outlook-cleanup
description: End-to-end Outlook inbox cleanup via per-message LLM content classification, soft-move quarantine, 7-day soak, and reversible purge. Auto-detects pipeline phase and runs the next step. Re-invokable at any time.
when_to_use: User asks to "clean up inbox", "run outlook cleanup", "delete promo emails", "review quarantine folder", "purge soaked messages", or invokes `/outlook-cleanup` directly. Also when the user mentions catching up on email cleanup or asks "what's next on the email cleanup".
argument-hint: [phase | --status | --dry-run | --confirm | --folder NAME | --data-dir PATH]
arguments: [phase, flags]
allowed-tools: Read Write Edit Bash(python3 *) Bash(python *) Bash(ls *) Bash(wc *) Bash(grep *) Bash(stat *) Bash(date *) Bash(mkdir *) Bash(test *) Bash(echo *) Bash(source *)
disable-model-invocation: false
shell: bash
---

# Outlook Cleanup — Phase-Aware Orchestrator

You are operating a 7-phase email-cleanup pipeline. **NEVER skip the phase detector.** Always start by running the detector and branch from its output.

## Hard Constraints (NEVER violate)

1. **Per-message content basis.** Every DELETE verdict must be justifiable from THAT message's subject + bodyPreview. Sender-allowlist DELETE is forbidden. (User principle: see `~/.claude/projects/-Users-chrisren-Development-personal/memory/feedback_delete_by_content_not_sender.md`)
2. **No blanket deletions.** Reject any "delete everything older than N days" or "delete all from sender X". Each message gets reviewed individually. (User principle: `feedback_no_blanket_delete.md`)
3. **Soft-move first, hard-delete after soak.** Never hard-delete in the same run as classification. The 7-day soak is wall-clock real time — cannot be compressed without explicit `--force-soak` from user.
4. **Keep-list domains untouchable.** `factorytown.com`, `canadianprotein.com`, `justthrivehealth.com` always KEEP regardless of content.
5. **Destructive ops require explicit confirmation.** Quarantine and purge BOTH prompt before executing. Show counts + sample subjects first. `--confirm` flag bypasses prompt, never assume it.
6. **Rescue audit required before quarantine.** Run the rescue pass and surface the rescue count BEFORE moving any messages. User reviews the rescue summary, then confirms.
7. **Subagent classify uses Sonnet not Haiku.** Haiku context (200K) is too small for the subagent preamble. Use Sonnet always.

## Step 0 — Detect current phase

ALWAYS run this first:

!`python3 ${CLAUDE_SKILL_DIR}/bin/detect.py "$ARGUMENTS"`

The detector emits one JSON object: `{phase, data_dir, counts, batches, next_action, anomalies}`. Read its `phase` field and branch to the corresponding section below.

If the user passed `--status`, print the JSON pretty + a 1-line summary and STOP. Do not advance.

If the user passed `--data-dir PATH`, the detector already used it.

## Phase: AUTH_REQUIRED

The MSAL token cache is missing or expired. Tell the user:

```
You need to sign in to Outlook first. Run in your terminal:

  cd <data-dir>/pipeline
  source .venv/bin/activate
  python pipeline.py auth

It will print a device code and URL. Sign in via browser, then re-invoke /outlook-cleanup.
```

STOP. Do not attempt the auth flow yourself (it's interactive and user-driven).

## Phase: NEEDS_INVENTORY

No `messages.jsonl`. Tell the user the plan:

```
About to inventory the Inbox. This streams every message's metadata
(id, subject, bodyPreview, from, receivedDateTime, inferenceClassification)
to messages.jsonl. ~5 minutes for a 36K inbox. Read-only — no Outlook changes.

Proceed? (yes/no)
```

On `yes`, run:

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py inventory
```

Stream progress. After completion, re-invoke phase detection and continue to next phase.

## Phase: NEEDS_CLASSIFY  /  CLASSIFY_IN_PROGRESS

Run the cost estimator first:

!`python3 ${CLAUDE_SKILL_DIR}/bin/cost.py --data-dir "${DATA_DIR}"`

Show the user: total messages to classify, estimated $ cost, estimated wall time, and the cost source (claude.ai usage credits vs. console.anthropic.com API credits — these are SEPARATE buckets).

Then offer the classification path:

```
Two ways to classify:

A. API key path (~$6-8 from console.anthropic.com balance, ~30 min)
   Requires ANTHROPIC_API_KEY env var. Uses pipeline.py classify directly.

B. Sonnet subagent path (~$15-25 from claude.ai usage credits, ~30 min)
   No API key needed. Spawns 10 parallel Sonnet subagents per wave.

Which? (A/B)
```

### Path A — API key direct

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py classify
```

### Path B — Sonnet subagent orchestration

Critical parameters (from empirical 2026-05-21 run):
- **shard_size = 500** (HARD CAP — Sonnet subagent output token limit is 32K, ≈ 640 verdicts max; use 500 for safety)
- **wave_size = 10** (12 - 2 retry slots)
- **2 retries max** per shard: 500-msg → 2×250-msg → deterministic ABSTAIN fallback
- **Subagents return COUNTS ONLY** (verdicts to file, never to lead — overflows lead context)
- **Brief ≤40 lines** (subagent preamble already eats ~50K tokens; oversized briefs trigger retry loops)
- **Pre-classify deterministically first** via `bin/deterministic.py` (saves ~20% of LLM cost)

Workflow:
1. Run deterministic pre-filter: `python3 ${CLAUDE_SKILL_DIR}/bin/deterministic.py --data-dir "${DATA_DIR}"` → appends keep-list, focus, transactional, OTP, financial doc, blast-promo matches to `classifications.jsonl`
2. Compute remaining LLM-eligible IDs; write 500-msg shards to `${DATA_DIR}/shards/in-NNN.jsonl`
3. Spawn waves of 10 Sonnet subagents in parallel using the brief at `${CLAUDE_SKILL_DIR}/templates/classify-brief.md` (each writes to `out-NNN.jsonl`, returns ONLY `{shard, classified, keep, delete, abstain, output_file}`)
4. On any shard error, retry once with 2×250 sub-shards. On second failure, run deterministic on those 250 msgs.
5. After all waves done, concatenate `out-*.jsonl` into `classifications.jsonl`
6. Verify: `wc -l classifications.jsonl` equals `wc -l messages.jsonl`

Use the Agent tool with `subagent_type: general-purpose`, `model: sonnet`, `run_in_background: true`. Spawn all 10 in one message (parallel). Wait for all task notifications. Aggregate.

## Phase: NEEDS_RESCUE_AUDIT

Classifications complete. Before quarantine, apply rescue rules:

!`python3 ${CLAUDE_SKILL_DIR}/bin/apply_rescues.py --data-dir "${DATA_DIR}" --rules ${CLAUDE_SKILL_DIR}/rules/rescue.yaml --dry-run`

Surface to user:
- N rescues identified (DELETE → KEEP flips)
- Breakdown by rule category (top 10)
- Sample 5 rescued subjects
- Final DELETE count after rescues

Ask:
```
Apply rescues? (yes/no)
[yes flips ~N classifications.jsonl entries from DELETE to KEEP based on the rule file]
```

On `yes`, re-run without `--dry-run`:

!`python3 ${CLAUDE_SKILL_DIR}/bin/apply_rescues.py --data-dir "${DATA_DIR}" --rules ${CLAUDE_SKILL_DIR}/rules/rescue.yaml`

The script writes to `rescues.jsonl` audit log and updates `classifications.jsonl` in place.

## Phase: NEEDS_QUARANTINE  /  QUARANTINE_IN_PROGRESS

Quarantine moves DELETE-verdict messages to `_ToReview-YYYY-MM-DD` folder. Reversible (drag-back in Outlook). Idempotent (skips already-moved IDs in `executions.jsonl`).

First, dry-run preview:

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py quarantine --dry-run
```

Show: count of messages to move + per-sender top 20.

Ask:
```
This will move N messages to _ToReview-YYYY-MM-DD. Reversible by drag-back.
Proceed? (yes/no)
```

On `yes`, run the real quarantine. Stream progress (one line per 100 moves). On completion, write `state.json` entry for this batch's `first_move_ts`.

## Phase: SOAK_IN_PROGRESS

Wall-clock 7-day window. NEVER run purge during this phase unless user passes `--force-soak`.

Surface to user:

```
SOAK IN PROGRESS

Batch     : _ToReview-YYYY-MM-DD  (N messages)
Started   : YYYY-MM-DD
Purge eligible : YYYY-MM-DD (in M days)

ACTION NOW:
  Open Outlook → _ToReview-YYYY-MM-DD folder
  Drag any false positives back to Inbox
  Whatever remains will be hard-deleted by purge

Re-run /outlook-cleanup on or after YYYY-MM-DD to advance to purge.
```

STOP. Do not advance.

If multiple batches exist and SOME are eligible, surface per-batch status and offer to purge the eligible ones via `--folder` flag.

## Phase: READY_TO_PURGE

Soak complete. Confirm before hard-delete:

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py purge --dry-run
```

Show count + sample subjects + Outlook 30-day Recoverable Items fallback note.

Ask:
```
This will PERMANENTLY DELETE N messages.
Recovery: 30 days via Outlook → Deleted Items → Recover Deleted Items.
Confirm by typing "purge N" exactly (replace N with the count).
```

Require literal match including count — prevents reflex approval. On match, run:

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py purge --confirm
```

For multi-batch case, accept `--folder _ToReview-YYYY-MM-DD` to target a specific batch.

## Phase: READY_FOR_AUDIT

Final reconcile:

```bash
cd <data-dir>/pipeline && source .venv/bin/activate && python pipeline.py audit
```

Surface three-way diff: classifications ∩ executions ∩ deletions. Flag any anomalies:
- DELETE verdict, never moved (pipeline gap or user pre-deleted)
- Moved but not deleted (user rescued during soak — expected)
- **CRITICAL** Deleted but not moved (should never happen)
- **CRITICAL** Deleted without classification record

Show false-positive rate (rescues / total moved). If >5%, suggest tightening the next run.

## Phase: COMPLETE

```
Pipeline complete. Next steps:

  Run /outlook-cleanup again whenever you want to clean new mail
  (or re-classify since the last inventory).

  Memory has been updated to reflect this batch's purge timestamp.
```

Mark task complete. Offer to save a project memory entry.

---

## Multi-batch handling

The user may invoke /outlook-cleanup multiple times over weeks. Each quarantine creates a new `_ToReview-YYYY-MM-DD` folder. The detector handles this by reading `state.json[quarantine_batches]` and computing per-batch soak status.

When multiple batches exist:
- Show status table per batch
- For purge, offer `--folder _ToReview-YYYY-MM-DD` to target one
- Default purge with no flag: only batches whose soak is complete

## Error recovery

If the user invokes /outlook-cleanup and the detector finds an anomaly (e.g., `messages.jsonl` exists but is older than `classifications.jsonl`, or `executions.jsonl` contains moves to a folder that doesn't exist in Outlook), surface the anomaly clearly and refuse to advance until the user resolves it.

For partial classify (shard crashed): re-run `python pipeline.py classify` — it resumes from the checkpoint (skips already-classified IDs).

For partial quarantine: re-run `python pipeline.py quarantine` — it reads `executions.jsonl` and only attempts the delta.

For partial purge: re-run `python pipeline.py purge --confirm` — already-deleted messages naturally won't appear in the source folder.

## Files in the data directory

```
<data-dir>/
├── messages.jsonl          # inventory output
├── classifications.jsonl   # verdict per message
├── executions.jsonl        # quarantine move log
├── deletions.jsonl         # purge log
├── rescues.jsonl           # rescue audit log
├── state.json              # per-batch soak timestamps
├── shards/                 # transient classify shards (in-NNN.jsonl, out-NNN.jsonl)
└── pipeline/               # the actual pipeline.py + venv (existing user install)
```

Default `<data-dir>`: `/Users/chrisren/Development/personal/outlook-cleanup/`. Override with `--data-dir PATH`.
