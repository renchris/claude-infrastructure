# `/outlook-cleanup` — Outlook Inbox Cleanup Skill

End-to-end Outlook cleanup as a single slash command. Auto-detects which phase you're in and runs the next step. Re-invokable any time.

## Install

Already installed at `~/.claude/skills/outlook-cleanup/`. Verify:

```bash
ls ~/.claude/skills/outlook-cleanup/
# Expected: SKILL.md  bin/  rules/  templates/  README.md
```

## Usage

```
/outlook-cleanup                              # auto-detect phase, advance to next step
/outlook-cleanup --status                     # print current state, don't advance
/outlook-cleanup --dry-run                    # preview the next destructive step
/outlook-cleanup --data-dir /path/to/data     # override default data directory
/outlook-cleanup --folder _ToReview-2026-05-21  # target a specific quarantine batch
```

## 7-Phase Pipeline

```
AUTH → INVENTORY → CLASSIFY → RESCUE → QUARANTINE → SOAK (7d) → PURGE → AUDIT
```

The skill auto-detects which phase you're in by reading file state:

| Phase | Detection | Next action |
|---|---|---|
| AUTH_REQUIRED | No `~/.cache/outlook-cleanup-token.json` | Run `pipeline.py auth` (interactive device flow) |
| NEEDS_INVENTORY | No `messages.jsonl` | Stream Inbox → JSONL |
| NEEDS_CLASSIFY | No `classifications.jsonl` | Spawn Sonnet subagent waves |
| CLASSIFY_IN_PROGRESS | `classified < inventoried` | Resume from checkpoint |
| NEEDS_RESCUE_AUDIT | Classify done, no rescues applied | Run `apply_rescues.py --dry-run`, confirm, apply |
| NEEDS_QUARANTINE | No `executions.jsonl` | Dry-run preview, confirm, move to `_ToReview-DATE` |
| QUARANTINE_IN_PROGRESS | `moved < DELETE - 5` (tolerance) | Resume (idempotent) |
| SOAK_IN_PROGRESS | `days_soaked < 7` for any batch | Print named purge date; STOP |
| READY_TO_PURGE | All batches ≥7 days soaked | Confirm-by-count, then hard delete |
| PURGE_IN_PROGRESS | `deleted < expected * 0.95` | Resume |
| READY_FOR_AUDIT | Purge done, no audit flag | Run three-way reconcile |
| COMPLETE | All batches purged + audited | Offer to start new run |

## Bundled Components

```
~/.claude/skills/outlook-cleanup/
├── SKILL.md                  # main orchestration prompt (Claude reads this)
├── bin/
│   ├── detect.py             # phase detector → JSON
│   ├── cost.py               # pre-flight cost estimator (Path A vs B)
│   ├── deterministic.py      # extended pre-classification (saves ~20% LLM cost)
│   └── apply_rescues.py      # applies YAML rescue rules with audit log
├── rules/
│   └── rescue.yaml           # 13 rescue rules + 2 ABSTAIN-flip rules (disabled)
├── templates/
│   └── classify-brief.md     # 40-line Sonnet subagent brief template
└── README.md                 # this file
```

## Hard Constraints (encoded in SKILL.md)

1. Per-message content-based DELETE decisions (no sender allowlists)
2. No blanket deletions (no "delete older than N days")
3. Soft-move first, hard-delete only after 7-day soak (wall-clock real time)
4. Keep-list domains untouchable: `factorytown.com`, `canadianprotein.com`, `justthrivehealth.com`
5. Destructive ops require explicit confirmation (no auto-execute)
6. Rescue audit BEFORE quarantine (catches false-positives)
7. Sonnet for subagents (Haiku context overflow with CLAUDE.md preamble)

## Cost Estimates

| Inbox size | Path A (API key) | Path B (subagents) |
|---|---|---|
| 5K | ~$1 | ~$2 |
| 10K | ~$2 | ~$5 |
| 36K | ~$6 | ~$15 |
| 100K | ~$17 | ~$50 |

**Path A** = `pipeline.py classify` direct, uses `ANTHROPIC_API_KEY` (console.anthropic.com balance). Cheaper, faster, but needs API key.

**Path B** = Skill orchestrates Sonnet subagents in parallel waves. Uses claude.ai usage credits (chat product). Slower per dollar but no API key needed.

## Extending the Rescue Rules

Add a new rule to `rules/rescue.yaml`:

```yaml
- id: my-new-rescue
  description: "What this catches"
  priority: 20             # lower = higher priority
  enabled: true
  match:
    domain: example.com
    subject_regex: '(?i)\bspecific\s+phrase\b'
  conjunction: ALL         # or ANY
  promo_guard:
    enabled: true
    block_subject_regex: '(?i)% off'
  action: RESCUE_TO_KEEP
  audit_tag: my-new-rescue
```

Then re-run rescue dry-run to see if it would catch more:

```bash
python3 ~/.claude/skills/outlook-cleanup/bin/apply_rescues.py \
  --data-dir /path/to/data \
  --rules ~/.claude/skills/outlook-cleanup/rules/rescue.yaml \
  --dry-run
```

## Multi-Batch Support

Run cleanup repeatedly over weeks. Each run creates its own `_ToReview-YYYY-MM-DD` folder. The detector handles them independently:

```
SOAK PARTIAL: Batch 1 (2026-05-21) ready to purge; Batch 2 (2026-06-15) 4 days remaining
  → /outlook-cleanup --folder _ToReview-2026-05-21 to purge just Batch 1
```

## Failure Recovery

| Failure mode | Recovery |
|---|---|
| Classify subagent crashes | Re-run `/outlook-cleanup` — resumes from checkpoint |
| Quarantine partial move (transient 429/504) | Re-run `/outlook-cleanup` — idempotent on `executions.jsonl` |
| Purge interrupted | Re-run `/outlook-cleanup` — already-deleted messages naturally skipped |
| YAML rule edit broke parser | Restore from `~/.claude/backups/rescue.yaml__*.bak` |
| Classifications file corrupted | Backups at `<data-dir>/classifications.jsonl.bak-YYYYMMDD-HHMMSS` |

## Empirical Constants (encoded in scripts)

| Param | Value | Source |
|---|---|---|
| Sonnet subagent shard size | 500 messages | Hard cap (Sonnet output ≈ 32K tokens) |
| Parallel wave size | 10 subagents | 12 - 2 retry slots |
| Retry attempts per shard | 2 (500 → 2×250 → deterministic) | Avoids context compounding |
| Soak duration | 7 days wall-clock | User-defined safety window |
| Quarantine tolerance | 5 messages | Allows transient 429/504 |
| Graph batch size | 4 (mailbox concurrency ceiling) | Microsoft-documented limit |
| Avg msg size (default) | 389 chars | Empirical from 2026-05-21 run |
| Default delete rate | 8% | Empirical from same run |

## See Also

- `/Users/chrisren/Development/personal/outlook-cleanup/pipeline/pipeline.py` — original implementation this skill wraps
- `/Users/chrisren/Development/personal/outlook-cleanup/synthesis-100th-percentile-2026-05-21.md` — architecture rationale
- Memory file: `~/.claude/projects/-Users-chrisren-Development-personal/memory/project_outlook_quarantine_2026-05-21.md`
