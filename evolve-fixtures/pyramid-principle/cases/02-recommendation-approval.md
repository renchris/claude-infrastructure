## input
Deliverable: approval memo. Objective: decide whether to adopt library Y to replace our current X.

"We're considering replacing our hand-rolled CSV parser (X) with library Y. Y handles edge cases
like quoted commas and BOM that X chokes on. But Y adds 180KB to the bundle and we'd have to
rewrite ~6 call sites. X has caused 3 prod bugs last quarter, all malformed-input related. Y is
MIT licensed, actively maintained. We don't have benchmarks comparing parse speed. The migration
is maybe 2 days. We process CSVs only on admin upload, not on the hot path."

## expected_behavior
Strong (4-5): States the recommendation UP FRONT as the controlling claim (e.g. "Adopt Y — it
eliminates the malformed-input bug class at acceptable cost"). Then 3-5 non-overlapping reasons
(correctness win / cost / risk) covering all input facts. Explicitly MARKS the gap ("no parse-speed
benchmark") rather than inventing one. Weighs the 180KB against the input's own framing that CSV
parsing is admin-only / off the hot path. Ends with a clear ask + timeline (2 days) and a
risk+mitigation line.

Weak (1-2): hedges with no recommendation, fabricates a benchmark, ignores the bundle-size cost,
or omits the off-hot-path mitigation. House style: apply the structure but do NOT name the
framework in the body.
