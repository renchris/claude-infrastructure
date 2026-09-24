# Dossier 8

## Brief
```
From /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type table has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098); main has the highest $ own per context at about $18.72, against about $5.80 for subagent and about $4.00 for workflow_agent (divided with python3).

## Returned numbers
`{"rows": 3}`

## answer.md
# B08-r5: ctx_type table from BASELINE.md

Source: /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, line 104 ("Billing type by context type", MEASURED, `census.md`).

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3

$ own per context (computed with python3 from the values above):
- main: 19,747 / 1,055 = about 18.72
- workflow_agent: 10,673 / 2,669 = about 4.00
- subagent: 2,098 / 362 = about 5.80

`main` has the highest $ own per context, at about $18.72 per context. That is about 3.2x subagent (about $5.80) and about 4.7x workflow_agent (about $4.00).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls -la /tmp/tokeff-gate/f2/out/B08-r5/ 2>&1", "description": "Locate ctx_type table and check output dir"}`
   → 104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
114:| ctx_type | static attachments, median (p90) | system + tools (2.1.280) | static total | mean prefix per response | static share of a mean request | static share of that ctx's $ |
124:| ctx_type | overall
2. `Bash: {"command": "sed -n 95,113p /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md", "description": "Print the ctx_type cost table"}`
   → | Worker contexts (subagent + workflow agents) | 12,771 | 39.3% | 7,652 | `census.md` |
| Stop-hook forced continuation turns (3,029; 1,973 waste-likely = $939) | 3,623 | 11.1% | 1,649 | `hooks.md` |
| Cache rewrites after a miss (36% of write $) | 3,316 | 10.2% | 2,404 | `cache-writes.md` |
| of wh
3. `Bash: {"command": "python3 -c \"print(19747/1055, 10673/2669, 2098/362)\"; cat > /tmp/tokeff-gate/f2/out/B08-r5/answer.md <<'EOF'\n# B08-r5: ctx_type table from BASELINE.md\n\nSource: /tmp/tokeff-gate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, line 104 (\"Billing type by context type\"`
   → 18.717535545023697 3.998875983514425 5.795580110497237
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B08-r5/answer.md", "headline": "The ctx_type table has 3 rows: main (1,055 contexts, $ own 19,747), workflow_agent (2,669, 10,673) and subagent (362, 2,098); main has the highest $ own per context at about $18.72, against about $5.80 for subagent and about $4`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
