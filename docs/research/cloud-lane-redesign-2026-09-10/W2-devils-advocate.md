# W2 — Devil's advocate: REPAIR (narrow) against the memo's RETIRE @ 80%

Read-only. Own measurements: `git log origin/main` per ISO week; `backlog.jsonl` (latest-event fold); `account-utilization.jsonl`.

## (i) Strongest contrary case

The lane works when its arm works: W33 landed **79** `Cloud-session:` commits = 11% of that week's trunk (`git log origin/main --grep='Cloud-session:'`); 131 total, **0** reverts (my grep; D2 §5). Its closures are real fixes 53–56% vs local 33–45% (`A-drain-rates.md:294`). The 12.8% is a latency artifact: 90% landable at +1 h (B1), seven repairs of 1–10 lines, none touching the VM (B2; B3 R1–R4). Repaired, a landed row costs $5–6 vs local $18 on the same meter (memo §4.2).

Demand exists where it matters: only ~37% of closures are real fixes, and on real fixes alone the pool's net is **negative in every window** (−20.9/day 7 d, −34.9/day 30 d, "NEVER" reaches zero — `A-drain-rates.md:25,393–410`). The lane's 108 landed sessions/34 d = 15% of that 21.6/day flow.

Decaying inventory is real and unmeasured by the memo: at the last weekly resets the meters read next 28% · next4 21% · next3 49% · next2 49% — **202–253 pp ≈ 2–2.5 account-weeks stranded in one cycle** (`account-utilization.jsonl`, 09-06T04:06Z, 09-06T09:00Z, 09-08T12:02Z). The memo prices cloud against one day (09-10, +130 pp/20 h, C3 §5) on which nothing stranded.

## (ii) Three weakest links

1. **"10% of closed rows / 5.1% of commits" (§5) — one-sided and historical.** Of 273 done rows matching `cloud` (lead: 313), 146 carry it only in evidence/source, 61 of those citing a cloud session/branch as the *closing* evidence — lane output booked as lane cost; 20 more are auto-minted `re-land claude/fire-*` rows, the symptom of B3's SIGKILL defect. Genuine machinery rows: 89 = **2.9%**. Same file set: maintenance 110 commits vs landed 131, half of it W32–33 build-out. §10 concedes forward maintenance is unmeasurable; §5 spends it as measured.

2. **"Two rows a day" (§3.4) is the classifier's number, charged to REPAIR.** Pre-gate the lane was offered 4.7 items/day (160/34) and landed 2.3 (D1: 48%); at B1's 90% that is 4.2/day with no classifier change. A2: 30 of 36 split-reachable rows need no config change → ~10.8/day on a denylist edit to `bin/cc-eligible` (A3: 0.5 h/class). The memo files that edit under REDESIGN, where it inherits the split's trust and gate-cost objections; "fix arm + denylist, VM scope unchanged" is never priced.

3. **"Conjunction not observed once" (§6) / "cloud displaces local" (§4.1).** Quota headroom + local unable to fire *was* observed: 09-05/06 the dispatcher fired 0 (C3 §1c) and three accounts then reset at 21–49%; 09-08/09, 50 pane-anchor failures at weekly 16–24% (C3 §1c, §6.6). Same-pool (C1, p = 6.5e-06) proves cloud adds no *meter*; displacement also needs no idle meter — true on 09-10, false at every reset. The 5-h cutoff is venue-symmetric (C3 §5.A): a wash.

## (iii) Verdict

**No — 80 → 70, not below.** The three links are accounting and supply errors that erase RETIRE's margin, but the fact that would flip the sign — the VM converting stranded quota — is contradicted by the lane's own 0 declarations on 09-05/06 (C2 §3): the inventory stranded with *both* lanes dark, which indicts the dispatcher, and follow-on 2 captures the pane-free value without a VM. The class-C packet must carry REPAIR-narrow (R1–R4 + the denylist, no scope widening, days) priced at 2.9% / 4–10 rows/day — not the split.
