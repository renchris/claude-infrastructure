# Dossier 3

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type table has 3 rows. main has 1,055 contexts and $ own 19,747; workflow_agent has 2,669 and 10,673; subagent has 362 and 2,098. main has the highest $ own per context, at about $18.72, compared with about $5.80 for subagent and about $4.00 for workflow_agent.

## Returned numbers
`{"rows": 3}`

## answer.md
# ctx_type table — BASELINE.md (lines 104-108, "Billing type by context type")

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3

**Highest $ own per context: `main`** — 19,747 / 1,055 ≈ $18.72 per context, against subagent ≈ $5.80 (2,098 / 362) and workflow_agent ≈ $4.00 (10,673 / 2,669).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "description": "Locate ctx_type table in BASELINE.md"}`
   → 104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_type | overall
2. `Bash: {"command": "sed -n 98,113p /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "description": "Print the ctx_type table"}`
   → | of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cache-writes.m
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r6 && cat > /tmp/tokeff-regate/f2/out/B08-r6/answer.md <<'EOF'\n# ctx_type table — BASELINE.md (lines 104-108, \"Billing type by context type\")\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md\n\n| ctx_ty`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r6/answer.md", "headline": "The ctx_type table has 3 rows. main has 1,055 contexts and $ own 19,747; workflow_agent has 2,669 and 10,673; subagent has 362 and 2,098. main has the highest $ own per context, at about $18.72, compared with about $5.80 for `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
