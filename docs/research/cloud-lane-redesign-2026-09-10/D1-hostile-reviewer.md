# D1 — Hostile review of the cloud-lane decision frame (2026-09-10)

**Frame defect.** The brief prices the lane as a DRAIN; its plan defines it as a CAPACITY valve (`docs/plans/CLOUD_BACKLOG_PIPELINE.md` §4: "routing to cloud is a CAPACITY decision, not a cost one"). Both denominators load the dice: yield per FIRE is 88/688 = 12.8%, per ITEM 77 of 160 declared items carry land evidence = 48% (`.decl item=` ∩ `.returned`/`.retired`); "379 stranded" reads 25 of 426 on the lane's own instrument (`e924e89f8dd1`).

## (i) Strongest case per option

**RETIRE.** Demand is gone: 63 agent-drainable rows, p90 16.8 d, none over 30 d (D §3); local closes ~100/day (A §2). Cloud substitutes: cost is Max-quota tokens (plan §4), all four accounts read "on pace to fill" (`claude-accounts --readout`: next 100% LIMITED, next2 95%), and 124c4da06 prices each fire as "pile-additive at ~0.81x the price of a local session that would have closed the row". Latency: median land lag 1.78 d (`bin/cc-cloud:148`) versus premise-dead 23.4% past a week, 4.2% under a day (`backlog-drain-netpositivity-2026-08-25.md:45-50`).

**REPAIR.** The lane delivers: 131 `Cloud-session:` commits on origin/main since 08-08 (5.1% of 2,583; 10 this week, e.g. SSRF fix e5c9c46fa). The fire collapse is downstream of the return arm: 100% of cloud skips since 09-09 read `already-declared` (IDL, 1,285 rows). Today's blocker is one line: 13 of 19 sessions examined since 09-08 pushed with `paths=` empty, which `cloud-reconcile.sh:171` returns 1 on and `:848` skips (`cc-cloud show`: STALLED, paths empty). The live pass is 30 min into one ship-land gate (pid 67452, land-lock FREE) under a 5,400 s bound whose SIGTERM already made ship-land file re-land row `5a5a3073626c` for that branch.

**REDESIGN.** The VM's one structural edge: no iTerm2 pane, the local lane's binding constraint (B §5: 73 spawn refusals, 551 unplaced). Pre-screened cloud work lands real fixes 53–56% vs local 33–45% (A §4, n=113/17); a cold VM caches 0.72x local (A/B §2). Pane-free, latency-tolerant, verdict-shaped work (hermetic.yml: 59/60 greens off-box, C §7; 14 of 22 September DROP subjects are `docs(verdict|research)`) never touches the 700–3,900 s land gate.

## (ii) Three dimensions the brief omits

1. **Demand.** All three questions price supply; seven eligible rows against ~100 local closes/day means a perfect arm lands a week of local output, once. Measure: `cc-backlog fold --as-of` open series (338→63 in 9 d, D §1).
2. **Contention on the box's serialized resource.** Every cloud return is a full ship-land gate HERE (`cloud-return.sh:53`; median 344 s, max 3,977 s); Q1's split moves MORE verification onto it, slowing the productive lane. Measure: `land-lock.sh --status` hold time under `cloud-reconcile --land`.
3. **Trust boundary.** 131 VM commits sit on trunk re-authored as the operator (`git log --grep Cloud-session --format='%an <%ae>'`); the identity gate refuses `noreply@anthropic.com` ON PURPOSE (`cloud-refusal-route.sh:223`); `cloud-inbox.py:34` refuses VM-composed commands as RCE; the undeclared-paths fix is parked on "landing content nobody declared, which the peer-WIP ruling forbids" (`e924e89f8dd1`). Every Q1 widening (gh, multi-repo, browser) widens an unreviewed remote author's reach; RETIRE zeroes it.

## (iii) The one measurement

Whether cloud tokens draw down the SAME weekly window — asserted (plan §4), never attributed (A/B §5.6: "cannot attribute consumption per arm"). n=1 says shared: the only session with control-plane evidence fired on `next` at 100% weekly and reads `status_bucket=failed ran=1`, never pushed. Shared ⇒ a 0.81x-priced substitute at ≤48% item yield: RETIRE or narrow REDESIGN. Separate ⇒ free capacity: REPAIR at any yield.

`bin/cc-cloud inbox --all` (writes `.cp` sidecars — lead's call), then `for f in ~/.claude/autonomy/cloud/*.cp; do paste <(grep -h ^account= "${f%.cp}.decl") <(grep -h ^status_bucket= "$f"); done | sort | uniq -c`. `failed` clustering on next/next2 (100%/95%), not next3 (52%), proves a shared pool.
