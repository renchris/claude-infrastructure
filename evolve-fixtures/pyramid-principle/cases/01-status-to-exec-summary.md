## input
Restructure this into a decision-ready exec summary for the eng lead. Deliverable: exec summary.

"So this week we kept working on the sync stuff. The pull path got a fast-path that skips the
fetch when nothing changed, which is good. We also found the CVR cache key was missing venueID
so two venues could poison each other's cache, fixed that. Oh and there's still the thing where
push rate limiting resets per Lambda invocation so it's not really enforced at the edge. The
fast-path saved maybe 40% of pull cost in local tests. We should probably do the durable rate
limiter next but it needs a DynamoDB table provisioned. Also typecheck is green and all 416
tests pass."

## expected_behavior
A strong restructure (score 4-5) MUST:
- Lead with the bottom line BEFORE any detail (e.g. "Sync pull is faster and cache-correct; one
  known gap remains: edge rate limiting"). The conclusion appears first, not last.
- Group items into 3-5 non-overlapping buckets (e.g. shipped wins / known gap / next action),
  collectively covering every input fact — nothing dropped, nothing double-counted.
- Use statement headings scannable in ~30 seconds (no question headings, no teaser).
- Preserve the one quantified claim ("~40% pull cost") AND its qualifier ("local tests") — do
  NOT inflate it to a general claim or invent new numbers.
- Surface the next action (durable rate limiter) WITH its blocker (DynamoDB table), not as a bare TODO.

A weak output (score 1-2): keeps the rambling order, buries the conclusion, drops the rate-limit
gap, or fabricates metrics. House style: the framework is APPLIED but NOT NAMED in the deliverable
body (no "governing thought / MECE / SCQA / key line").
