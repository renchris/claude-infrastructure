---
status: open
created: 2026-08-16
supersedes-for-operation: BACKLOG_SELF_DRAINING_2026-08-12.md (its status log remains the evidence record), CLOUD_BACKLOG_PIPELINE.md (its architecture remains the cloud-lane reference)
---

# BACKLOG_DRAIN_24_7 — SSOT plan: drain cc-backlog to zero, and keep it there

Scope (frozen): root-cause the false "drained to zero" reading; reconcile the ledger to disk
truth with zero lost work; then design, implement, verify, and START a 24/7 two-lane drain
pipeline — Claude Cloud for off-box-eligible rows, ONE self-recycling goal-armed local session
for everything else — with claim-time freshness re-validation and consolidation-before-fire,
such that the backlog trends DOWN (closes ≥ files, week over week) instead of net-filing.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave** (S = dispatched handoff session · T = in-session teammates ·
L = lead-inline):

| Wave | Locus | What |
|---|---|---|
| W-R1 ledger reconcile | **L** | cc-backlog ops only (reap dead leases, per-branch re-land fold, reopen false closes) — no code writes; the lead already holds the forensics. |
| W-R2 stranded-content recovery | **S** | one dispatched session; lands/retires every unlanded branch + refs/land/failed pin by CONTENT verdict. |
| W-P1 pipeline fixes | **S** | one dispatched session per independent fix cluster (dispatcher un-wedge + venue policy; drain-chain self-perpetuation; inflow conservation; premise-pass repair). |
| W-P2 go-live | **L** | the lead fires the cloud lane + the local drain session and verifies first-drain evidence. |

Lead context budget: recycle at ≤60% fill; succession point = any wave boundary; this plan +
the ledger are the full disk state — a successor needs nothing from this context.

## §1 Root cause — why "resolved / drained to zero" was false (2026-08-16 forensics, 8-agent wave)

1. **No whole-backlog zero was ever claimed on disk.** Every zero was per-EFFORT and counted
   only `open`, silently excluding `blocked`: "master-stranded-work at ZERO open" (0 open,
   **4 blocked**, 83e32b012); recycle #9 "master-account-facts at 0 open" (**17 blocked**,
   e830cf050) followed by the session self-certifying *"Good to close — nothing of yours is
   pending"* at 2026-08-16T05:56Z. Blocked rows hold real work: e.g. cb6701bf2217's fix commit
   `674232c8` (wt-cb6701bf2217) is NOT on origin/main.
2. **The drain chain terminated by design this morning.** The local drain (9 recycles, account
   next4, pane 463, 2026-08-13T03:56Z → 2026-08-16T06:45Z) switched recycle #9's goal from the
   global DoD to an effort-scoped condition; the goal cleared, the operator interrupted, and
   **no recycle #10 fired**. Nothing chains effort N's clear into effort N+1's fire.
3. **Net-filing.** +426 rows over 5 days (1,129 filed / 503 closed, 42d27a758); 21-day totals
   1,530 adds vs 1,117 dones. Open trajectory 109 (Jul 26) → **578 peak (Aug 15)** → 568 now;
   never under 188 since Aug 1. Inflow is 70% model-filed — pumped by our own close gates
   (dispatch-assert.sh:191,225 and completion-assert D1/D4 refuse a close until follow-on is
   FILED; the Follow-On Gate governs *pursue*, not *file*) — and 24% ship-land's re-land
   generator (185 rows/7d; 39 duplicates for ONE stuck branch).
4. **The standing dispatcher drains nothing.** launchd `com.claude.dispatcher` runs
   `CC_DISPATCH_VENUE_ONLY=cloud` — explicitly warned against in 42d27a758 ("parks the local
   majority indefinitely", ~86% parked) — and the cloud leg is WEDGED in a claim→spawn-fail→
   release loop on 3 worktrees whose HEAD lacks origin/main (wt-ce7651b02a17, wt-62599dd76a60,
   wt-ee1ac85c6ff6). Fleet-wide: 2,462 claims → 1,543 releases (63%), 507 dones (21%). The
   churn the operator saw as "activity" was claim-thrash, not work: only **12 done→reopen
   cycles ever** — false re-closes are NOT the mechanism; failed claims are.
5. **Instrument residue** (of ~45 documented bugs, most fixed on trunk): find-plan.sh
   plan_status() reads only YAML frontmatter so a finished plan re-mints "advance" rows for
   days (e830cf050); 27 of 628 dones in 7d carry EMPTY evidence; the premise/freshness pass is
   wired (autonomy-sweep, 6h cadence) but has **validated 0 rows in production** (every run
   rc-124 bound-exceeded or rc-0 `note=unparsed`); backlog-ratchet coverage regression is live
   as of this hour (33.8 high-water, assert rc=1).

**One-line answer:** the backlog was never drained — a per-effort "0 open" close (blind to its
blocked tail) was read as program completion, the drain chain had no cross-effort successor, and
inflow (hook-pumped filing + a failed-land minter) outran the drain 4 days out of 5 while the
standing dispatcher was pointed at the ~14% cloud-eligible slice and wedged even there.

## §2 True state — 2026-08-16T09:00Z

- **568 live rows** (269 open · 298 blocked · 1 claimed-by-dead-PID) of 2,149 ever filed;
  1,581 done. Store: `~/.claude/autonomy/backlog.jsonl` (10,550 records, fold = last wins).
- Age: 92 ≤2d · 306 3-6d (the 08-10..13 cohort) · 118 7-13d · 52 ≥14d · oldest 07-20.
- Grouping: 381 rows under the 10 master-* conditions (convergence-deadlock 84 · product-repos
  58 · fire-gate 58 · fleet-footprint 56 · session-lifecycle 41 · enforcing-store 33 ·
  operator-gated 24 · account-facts 17 · verification-integrity 6 · stranded-work 4);
  **ungrouped regrew 7 → 123** (W2 floor is 50 — breached).
- Blocked (298): ~101 operator credential/sudo/auth gates · ~142 carry an executable `run`
  field (one-command operator actions) · 69 legacy re-land rows collapsing onto ~15-20
  branches · 28+6 operator decisions · 11 dependency-holds · 9 stale-marked.
- Validation: 151/568 carry a falsifier (26.6%) · 325 condition-only · 92 never-validated.
- Cloud eligibility: ~8.8-14% of the pile (79% of labelled refusals name THIS MACHINE as the
  work's subject — structurally local). 195 rows unlabelled (venue backfill needed).
- Quota: next4 weekly reset 09:00Z today (fresh); next/next2/next3 at 3%/0%/16% weekly.
  All four accounts auth ok — a 24/7 lane has headroom.
- Consolidation-2026-08-09 verdicts fully applied (117/117 PRUNE, 44/45 MERGE, 110/110 links;
  the 1 regex-missed MERGE (e27d37eac4cd) was later captured by grouping). M1-M6 all reached
  done 2026-08-10, deliberately mass-reopened 2026-08-12 as standing umbrellas.

## §3 Reconciliation worklist (W-R1 + W-R2) — zero lost work

R1 (**L**, ledger ops):
- R1.1 Reap the dead-PID lease: 1d25b0e07668 held by `Chriss-MacBook-Pro-3-75161` (PID dead
  since ~07:43Z). Mechanism: cc-backlog's stale-claim reap (by=cc-backlog-reap precedent).
- R1.2 Per-branch fold of the 69 legacy re-land rows: keep ONE row per branch whose content is
  genuinely unlanded (S3 audit precedent: 34 of 43 protected real work; 39-row bulk-close
  precedent fc4db521/aa1886a5e). Verdict per branch by CONTENT: `git merge-base --is-ancestor`
  on EVERY pinned sha + `git cherry` requiring no `+` (bug-4-corrected arm).
- R1.3 Reopen the one proven-false close: b59eb997d035 (evidence claims a test case is "GONE";
  tests/test-hermeticity-lint.bats:151 still carries it) — reopen with the refutation as
  evidence, or re-close on TRUE evidence if the underlying work is genuinely moot.
- R1.4 Audit the 27 evidence-less dones (7d window, e.g. c864e1b81989): identify the writer,
  spot-verify 5 by content; file the "done requires --evidence" gate as a P1 item (→ P1.4).
- R1.5 Regroup the 123 ungrouped rows (sweep already detects; run the grouping pass to fold
  them under masters/minor groups so the drain walks efforts, not strays).

R2 (**S**, content recovery — the full stranded-work enumeration is the dispatched session's
first deliverable; forensics agent for this axis died mid-run and is being re-run):
- R2.1 Every `refs/land/failed/*` pin: verdict LANDED / REAL / UNKNOWN by content (slash→dash
  sanitisation trap applies); land or retire each.
- R2.2 Known-stranded: wt-cb6701bf2217 (`674232c8`, unattended-path-lint work, parked 6d behind
  trunk-red row 11d3a3cd8507); the 3 dispatcher-refused worktrees (rebase or retire).
- R2.3 Close each recovered branch's re-land row(s) with the landed sha as evidence.

## §4 Pipeline architecture (W-P1)

**Lane A — Claude Cloud, 24/7, for the off-box-eligible slice (~8-14% + backfill).**
Already built end-to-end and launchd-live: cc-venue → cc-dispatch (300s) → `cc-offload up
--via api` (POST /v1/sessions) → custody/goal/wake → cloud-return.sh auto-land →
cloud-refusal-route.sh. Fixes required before it counts as a lane:
- A1 **Un-wedge**: clear/rebase the 3 refused worktrees; add the rule "a claim that cannot
  fire because its worktree HEAD lacks origin/main FIRST rebases or retires the worktree —
  never re-claims into it" (the retry loop is the defect; 63% release rate is its fleet echo).
- A2 **Prove ONE dispatcher-driven cloud land end-to-end** (session pushes a ref; cloud-return
  lands it; row closes on content). The lane has never once done this — the only session ever
  created sat NOT-STARTED past its boot budget. Until this probe passes, cloud is a paper lane.
- A3 **Venue backfill**: cc-venue the 195 unlabelled rows so the eligible slice is fully known.
- A4 Keep `CC_DISPATCH_VENUE_ONLY=cloud` on the DAEMON (it is the cloud lane; the local
  majority is Lane B's job — the 42d27a758 warning is answered by Lane B existing, not by
  flipping the daemon to local and colliding with the drain session's leases).

**Lane B — ONE local self-recycling goal-armed session, 24/7, for everything else.**
The proven local-drain design (9 recycles) plus the one missing property — self-perpetuation:
- B1 **Chained recycle, no terminal goal.** Per recycle: goal = effort-scoped, provable,
  quotable (*"<current effort> reaches 0 open — proven by cc-backlog list --open --json | jq
  … printing 0; then fire the next recycle with handoff-fire --recycle"*). The recycle FIRE is
  part of the goal's constraint clause, so a cleared effort cannot strand the chain; the
  session picks the next effort smallest-first from the live fold (next: enforcing-store 33 →
  session-lifecycle 41 → fleet-footprint 56 → product-repos 58 → fire-gate 58 →
  convergence-deadlock 84 — re-read at each boundary; read master-convergence-deadlock's plan
  note before opening it).
- B2 **Freshness at claim, mechanically**: before working any row, run its falsifier against a
  pristine origin/main worktree (exit 0 ⇒ retracting → close on that evidence, don't build);
  re-measure dated titles; adjudicate landedness by content. This is the operator's
  "no stale ticket fires against an updated repo" requirement, and it is the drain's proven
  row-picking mechanism — keep it verbatim.
- B3 **Account rotation**: fire with `--account auto` (claude-accounts --rank general) at every
  recycle so the chain survives any one account's weekly cliff; next4 is fresh as of 09:00Z.
- B4 **Blocked-row platter**: the ~142 one-command operator rows render via the existing
  cc-do/operator-readout rail at every drain close; the drain never burns turns on them.
- B5 **Conservation**: each recycle reports filed vs closed and must close ≥ it files
  (42d27a758's named-but-never-implemented rule) — enforced in the recycle brief + goal
  constraint ("do not end the recycle net-positive on filings").

**Inflow control (the other half of "drain"):**
- C1 re-land minter: pre-fix-branch-bytes leak — the retry executes the BRANCH's old
  ship-land.sh (`git checkout $BRANCH && bash scripts/ship-land.sh`); make the retry command
  invoke TRUNK's ship-land against the branch so aa1886a5e's brake + 40613b786's rc-5 screen
  actually govern retries of old branches.
- C2 find-plan.sh plan_status(): read the status LOG/body, not frontmatter alone — kills the
  4-day "advance a finished plan" re-mint class.
- C3 done-with-evidence: `cc-backlog done` warns (then refuses, ratcheted) on empty
  --evidence.
- C4 premise-pass repair: it has validated 0 rows ever (420s rc-124 + `unparsed` on the one
  completing run). Fix the bound to fit the Background band it runs in (bound-fits-the-band)
  and the --json parse; prove ≥1 production pass that RECORDS validations.

## §5 Verification before mass fire (W-P1 exit gate)

1. Cloud probe: one real row through Lane A end-to-end (ref pushed, landed by content, row
   closed). 2. Local probe: one recycle boundary crossed unattended (effort clears → next
   recycle fires itself, goal re-armed, verified in the fired transcript). 3. Freshness probe:
   one stale row auto-closed by falsifier-retraction at claim. 4. Conservation visible: the
   recycle's close prints filed/closed. Only then W-P2.

## §6 Operating invariants

- The drain's unit of "done" is CONTENT ON TRUNK (ls-tree/diff), never a count, never a stamp.
- "0 open" is never reported without its blocked tail: the drain's close line format is
  `<effort>: N open / M blocked (K operator-gated)`.
- The chain is alive ⟺ a fire-drain-recycle-N brief younger than 24h exists OR a drain session
  holds a live lease — checked by autonomy-sweep; a dead chain files ONE condition-keyed row
  (`local-drain-chain-dead`), never a duplicate storm.
- Weekly report: adds vs closes; net-positive week ⇒ the INFLOW list (C1-C4) gets the next
  fix, not more drain horsepower.
