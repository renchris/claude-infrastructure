# Dossier 5

## Brief
```
From /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, extract the table whose first column header is ctx_type: for every row give ctx_type, contexts and the "$ own" value exactly as written. Then say in one sentence which ctx_type has the highest $ own per context. numbers: {"rows": <row count>}.
```

## Returned headline
The ctx_type table (BASELINE.md line 104) has 3 rows: main has 1,055 contexts and $ own 19,747; workflow_agent has 2,669 and 10,673; subagent has 362 and 2,098. main has the highest $ own per context, about $18.72, against about $5.80 for subagent and about $4.00 for workflow_agent (calculated as $ own divided by contexts).

## Returned numbers
`{"rows": 3}`

## answer.md
# B08-r8: ctx_type table from BASELINE.md

Source: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, line 104. This is the table that has both a `contexts` and a `$ own` column. Two other tables also start with ctx_type (lines 114 and 124), but they have neither column.

| ctx_type | contexts | $ own |
|---|---:|---:|
| main | 1,055 | 19,747 |
| workflow_agent | 2,669 | 10,673 |
| subagent | 362 | 2,098 |

Rows: 3

`main` has the highest $ own per context: about $18.72, against about $5.80 for subagent and about $4.00 for workflow_agent. These figures are $ own divided by contexts, calculated by hand from the values above.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "grep -n \"ctx_type\" -A 20 /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md; ls /tmp/tokeff-regate/f2/out/B08-r8/ 2>&1", "description": "Find ctx_type table in baseline"}`
   → Exit code 1
104:| ctx_type | contexts | $ own | share | cache read | cw 5m | cw 1h | output | $ @5.5 |
105-|---|---:|---:|---:|---:|---:|---:|---:|---:|
106-| main | 1,055 | 19,747 | 60.7% | 64.8% | 0.0% | 26.0% | 9.2% | 10,666 |
107-| workflow_agent | 2,669 | 10,673 | 32.8% | 47.5% | 33.2% | 0 | 19
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B08-r8 && cat > /tmp/tokeff-regate/f2/out/B08-r8/answer.md <<'EOF'\n# B08-r8: ctx_type table from BASELINE.md\n\nSource: /tmp/tokeff-regate/f2/tree/docs/research/token-efficiency-2026-09-23/BASELINE.md, line 104. This is the table that has both a `cont`
   → ok
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B08-r8/answer.md", "headline": "The ctx_type table (BASELINE.md line 104) has 3 rows: main has 1,055 contexts and $ own 19,747; workflow_agent has 2,669 and 10,673; subagent has 362 and 2,098. main has the highest $ own per context, about $18.72, against ab`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
