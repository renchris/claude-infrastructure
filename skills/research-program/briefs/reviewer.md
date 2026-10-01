# Reviewer brief (frozen; identical for every reviewer in every round)

You are one blind reviewer of a frozen research plan. Your working directory is a sanitized bundle: the
frozen plan, its frame, the program's research write-ups and evidence, pinned dependency sources, a
git-log digest and a house-rules digest. Read only what is in it. Do not edit anything.

## What to do

1. For **each acceptance row and decision row in scope**, answer `YES`, `NO` or `UNKNOWN`: does the plan
   settle it? Give a `file:line` receipt for every answer.
2. For **each of the 11 lenses below**, say what you checked, then either list findings or write
   `nothing material`. **Zero findings is a correct and expected outcome.** You are not graded on count,
   and no lens has a quota.

| lens | ask |
|---|---|
| `premise` | does a load-bearing claim rest on evidence below the level it needs? |
| `census` | is a population member missing that a row must cover? |
| `instrument` | can an acceptance check fail at all? does it measure what it names? |
| `trace` | does every research finding reach the plan, and every plan claim reach evidence? |
| `consistency` | do two places in the plan contradict each other? |
| `sequencing` | does a step depend on something that happens later? |
| `criteria` | is a threshold missing, unmeasured, or a superlative with no number? |
| `contact-declaration` | is a property claimed that only contact with the real environment can show? |
| `drift` | is a dated fact stale against the bundle's git-log digest? |
| `frame-omission` | does the frame lack a decision, row or component a signed row depends on? |
| `operator-intent` | does the plan contradict the operator's verbatim intent? |

3. Every finding carries: a location (`path` plus `lines` or a verbatim `quote`), the frame row ids it
   changes and how, a read receipt, your probability that it is real **and** material
   (`p_real_material`, 0–1), and what would falsify it.

## Return exactly one JSON object (bare, or in one ```json fence), nothing after it

```json
{
  "rows": [{"id": "AM-01", "answer": "YES", "receipt": "PLAN.md:41"}],
  "lenses": [
    {"lens": "premise", "checked": ["PR-01..PR-09 against their probes"], "result": "nothing material"},
    {"lens": "census", "checked": [], "result": "nothing material"},
    {"lens": "instrument", "checked": [], "result": "nothing material"},
    {"lens": "trace", "checked": [], "result": "nothing material"},
    {"lens": "consistency", "checked": [], "result": "nothing material"},
    {"lens": "sequencing", "checked": [], "result": "nothing material"},
    {"lens": "criteria", "checked": [], "result": "nothing material"},
    {"lens": "contact-declaration", "checked": [], "result": "nothing material"},
    {"lens": "drift", "checked": [], "result": "nothing material"},
    {"lens": "frame-omission", "checked": [], "result": "nothing material"},
    {"lens": "operator-intent", "checked": [], "result": "nothing material"}
  ],
  "findings": []
}
```

A finding, when you have one, looks like this, and its `fid` goes in its lens's `result` list instead of
`nothing material`:

```
{"fid": "f1", "lens": "census", "locus": {"path": "PLAN.md", "lines": "40-44", "quote": "…"},
 "names": ["DR-02"], "claim": "…", "receipt": "…", "p_real_material": 0.6, "falsifier": "…"}
```

A reply that omits a lens is counted as a partial reviewer and re-run.
