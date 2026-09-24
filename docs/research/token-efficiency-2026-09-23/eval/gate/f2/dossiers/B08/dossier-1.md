# Dossier 1

## Brief
```
From /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type billing table has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098). main has the highest $ own per context, about $18.72, compared with about $5.80 for subagent and $4.00 for workflow_agent.

## Returned numbers
`{"rows": 3}`

## answer.md
# B08-r3 — ctx_type table (BASELINE.md, lines 104-108, "Billing type by context type")

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3.

$ own per context (computed): main 19,747 / 1,055 ≈ $18.72; subagent 2,098 / 362 ≈ $5.80; workflow_agent 10,673 / 2,669 ≈ $4.00.

**main has the highest $ own per context (≈ $18.72, about 3.2x subagent and 4.7x workflow_agent).**

Note: the file has two other tables whose first header is also `ctx_type` (line 114, static tokens; line 124, cache hits). Neither has `contexts` or `$ own` columns, so the brief can only mean the line-104 billing table.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "description": "Locate ctx_type table in baseline doc"}`
   → 104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_type | overall
2. `Bash: {"command": "sed -n 98,113p /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "description": "Print the ctx_type table"}`
   → | of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 | `cache-writes.md` |
| Tool errors incl. recovery turns ($636 preventable) | 1,184 | 3.6% | 642 | `tool-errors.md` |
| Agent START writes (setup re-written by every sibling) | 1,760 | 5.4% | 1,362 | `cache-writes.m
3. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B08-r3 && cat > /tmp/tokeff-gate/f2/out/B08-r3/answer.md <<'EOF'\n# B08-r3 — ctx_type table (BASELINE.md, lines 104-108, \"Billing type by context type\")\n\n| ctx_type | contexts | $ own |\n|---|---:|---:|\n| main | 1,055 | 19,747 |\n| workflow_agent | `
   → # B08-r3 — ctx_type table (BASELINE.md, lines 104-108, "Billing type by context type")

| ctx_type | contexts | $ own |
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B08-r3/answer.md", "headline": "The ctx_type billing table has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098). main has the highest $ own per context, about $18.72, compared with about $5.80 for subagent `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
