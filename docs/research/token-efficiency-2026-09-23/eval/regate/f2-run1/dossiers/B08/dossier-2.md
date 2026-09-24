# Dossier 2

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type billing table in BASELINE.md (lines 104-108) has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669 contexts, $ own 10,673) and subagent (362 contexts, $ own 2,098); main has the highest $ own per context at about $18.72, against about $5.80 for subagent and $4.00 for workflow_agent (my division of $ own by contexts, not stated in the source).

## Returned numbers
`{"rows": 3}`

## answer.md
# B08: ctx_type billing table

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108, the "Billing type by context type" table (MEASURED in the source, `census.md`). Values are copied exactly as written.

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3.

The `main` ctx_type has the highest $ own per context: about $18.72 per context, against about $5.80 for subagent and about $4.00 for workflow_agent. I computed these by dividing $ own by contexts; the source table does not state them.

Note: two more tables in the file also have ctx_type as their first header, at lines 114 (static tokens) and 124 (cache hit rate). Neither has a "contexts" or "$ own" column, so the table at line 104 is the only one that fits the brief.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-regate/f2/out/B08-r4/ 2>&1", "description": "Locate the ctx_type table and check output dir"}`
   → Exit code 1
104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_ty
2. `Read: {"file_path": "/tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "offset": 96, "limit": 36}`
   → 96	| Stop-hook forced continuation turns (3,029; 1,973 waste-likely = $939) | 3,623 | 11.1% | 1,649 | `hooks.md` |
97	| Cache rewrites after a miss (36% of write $) | 3,316 | 10.2% | 2,404 | `cache-writes.md` |
98	| of which main thread idle >1h (517 wakes, mean 390k prefix) | 2,102 | 6.5% | 1,528 |
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r4 && cat > /tmp/tokeff-regate/f2/out/B08-r4/answer.md <<'EOF'\n# B08: ctx_type billing table\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108, the \"Billing type by context type\" table (ME`
   → # B08: ctx_type billing table

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, lines 104-108, the "Billing type by context type" table (MEASURED in the source, `census.md`). Values are copied exactly as written.
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r4/answer.md", "headline": "The ctx_type billing table in BASELINE.md (lines 104-108) has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669 contexts, $ own 10,673) and subagent (362 contexts, $ own 2,098); main has the highest $ own per`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
