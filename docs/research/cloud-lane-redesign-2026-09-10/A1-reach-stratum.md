# A1 — reach under SPLIT over the agent-drainable stratum (read serially on the lead; spawn refused by capacity-admit at 8 mid-turn)

Population: every non-done row with status open (32) or claimed (4) = 36, from `cc-backlog list --open --json` at 2026-09-10 ~21:00Z ($S/open.json), joined to `cc-eligible sweep --json` ($S/eligible-sweep.json). No sampling — the whole stratum was read (title, needs, evidence, whyNotNow, run).

Verdicts: (a) implementable off-box with hermetic tests, verify on-box · (a*) same but only after a config change (cross-repo attach or a `gh` token) · (b) the implementation itself needs this Mac · (c) not agent work now (operator step, money, or a not-yet-true precondition).

| id | status | bucket | verdict | reason |
|---|---|---|---|---|
| 1dd6fbb6766c | claimed | eligible | a | plan-advance bookkeeping; the plan is on trunk; a verdict artifact closes it |
| 1f6208064577 | open | eligible | a | script change to the desk router; the ps census it fixes is verified on-box |
| 2a65b9bf722d | claimed | eligible | c | not-yet-true: waits on an upstream GrowthBook flag |
| 4236edc78a72 | open | eligible | b | resume + escalation ladder is about live panes on this box |
| 64c150ba2a8e | open | eligible | b | "the two 24/7 drains, measured" — the stores (backlog.jsonl, idl.jsonl) exist only on this box; HELD BY A LIVE CLOUD WORKER |
| badb132df232 | open | eligible | a | CV pipeline code + tests; corpus location to confirm; HELD BY A LIVE CLOUD WORKER |
| c18e7ea9e6b1 | open | eligible | b | DRAIN CIRCUIT plan — launchd/sweep on this box; HELD BY A LIVE CLOUD WORKER |
| 17c6789a42da | open | box | b/c | shared-checkout unlanded commits; another session live; not-yet-true |
| 1bf260340259 | open | box | a* | sevenrooms sidecar TS code; needs the other repo attached; device-trust verify on-box |
| 54ef3956c409 | open | box | b | re-land of a local worktree branch via /ship |
| 5a5a3073626c | open | box | b | re-land of a CLOUD branch whose ship-land was SIGTERM-cut — the return arm's own failure surfacing as a row |
| 5a629c6465d1 | open | box | c | not-yet-true: no weekly harvest exists yet |
| 5b612e3e594d | open | box | c | not-yet-true: depends on an unlanded branch; the index DB is local |
| 775afca94edc | open | box | b | /limit-recover — panes and transplant on this box |
| c5153cf3e5b9 | open | box | b | harness reaping of background bash on this box |
| c692d7edd4be | claimed | box | b | re-land (peer reported it already landed as 823398c2e) |
| d9403b2ac16d | open | box | b | live layer converge; shared checkout; not-yet-true |
| dec14f831373 | open | box | b | re-land of a local branch |
| f5c3cfb86e2e | open | box | a | hook code + bats; the live-session verification is on-box |
| fa685176f3d2 | open | box | b | re-land of a local branch |
| 1a4d38c15feb | open | cross-repo | c | /compact-memory is human-gated; file is under ~/.claude, not a repo |
| 3502995b34f8 | open | cross-repo | c | money + a message to a third party |
| 3c3bdc5be447 | open | cross-repo | b | sidecar restart root-cause needs the production logs |
| 6b8e28d3bf0e | open | cross-repo | c | money |
| 6d32f757986f | open | cross-repo | c | phone call |
| 76bad7b8ac42 | open | cross-repo | c | /compact-memory, human-gated |
| 9e95d2743bbf | open | cross-repo | c | negotiation with a third party |
| b44d993ecdc4 | open | cross-repo | a* | add `npm test` to sevenrooms-bridge CI — pure repo work; the cleanest cloud row in the pile, refused only for being another repo |
| b70d1c5b91aa | open | cross-repo | c | written request to a landlord; deadline passed |
| 8e67a1fa2d40 | open | deep-history | a | bats ratchet over install.sh — repo content; deepen removes the class |
| 9f8a985115a9 | open | deep-history | a | pure repo test (cc-read-twitter parse_id) |
| e794e0a5a1f1 | open | offbox-lane | a*/c | implementation in sevenrooms-bridge is repo work; the Lambda redeploy is the operator's timing call |
| f8b71a8e0ff0 | claimed | offbox-lane | a* | measured from `gh run list` — needs a gh token in the VM |
| d6d7edef60a3 | open | spawn-rail | a | handoff-fire code + bats; the live fire is the on-box verify |
| 45a0073b9ea4 | open | visual | a* | build-correlated flake in sevenrooms-bridge; reproducible in a Linux VM with that repo |
| c6d897731567 | open | visual | a* | same family as above |

## Summary

| stratum | n | (a) | (a*) config-dependent | (b) box | (c) not agent work now |
|---|---|---|---|---|---|
| open + claimed | 36 | 7 | 6 | 13 | 10 |

- Reachable under SPLIT with no config change: **7/36 = 19% (Wilson 95% CI 10–35%)**.
- Reachable under SPLIT after cross-repo attach (5 rows) + a `gh` token (1 row): **13/36 = 36% (CI 22–53%)**.
- Today's classifier admits 7/36 (19%) — but **3 of its 7 admits are (b)** (64c150ba2a8e, c18e7ea9e6b1, 4236edc78a72): plan-advance rows about this box's own drain machinery whose titles carry no local-only spelling. Two of those three are HELD BY LIVE CLOUD WORKERS right now. Classifier precision on admits ≈ 4/7; the split verdict and the classifier agree on only 4 rows.
- The (b) class is not "box-shaped work" in general: **5 of 13 are `re-land <branch>` rows** (the landing arm's own failures, one of them a cloud branch cut by SIGTERM), 3 are plan-advance rows about the drain, 2 are the shared-checkout/live-layer converge, 3 are genuine box investigations.
- The (c) class is 10/36: 6 are the operator's personal errands mis-filed under project=personal with no `needs` (they read `open` but no agent can do them), 4 are not-yet-true preconditions.

## Blocked stratum (260 rows) — by contract, not by reading
Every blocked row carries a non-empty `needs` (D-backlog-floor.md §1), i.e. was filed through the operator-only gate; D's seeded reads found 7/8 unmatched rows operator-only and 10/15 of a random sample operator-owned. The 15 eligible-but-blocked rows are the same shape (permission grants, a value call, re-lands of local worktrees, a 3.5 GB rm the agent is denied). Venue does not touch them: (c) for the purpose of this question, with D's samples as the receipt.

## Adversarial self-pass
What a VM could get wrong on the seven (a) rows without the box: 1f6208064577 fixes a ps-census bug it cannot reproduce (it can only reason from the code — the fix must be verified on-box before landing, which is exactly the split's second half); badb132df232's image corpus may live only on this disk (if so it drops to (b)); f5c3cfb86e2e and d6d7edef60a3 change hooks whose only true test is a live session — bats can pin the predicate but not the harness wiring. None of these flip the verdict under SPLIT, because the split's premise is that the box verifies; all four would flip to (b) under the CURRENT design, where the VM's push is landed unverified.
