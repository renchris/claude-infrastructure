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

## §2.1 Execution log (INTEGRATE-only; newest first)

- **2026-08-18 ~02:35Z — lead (pane 102): W-R3's tally derived NON-MUTATINGLY after both its
  sessions wedged; and the measurement that says this pipeline cannot reach zero as specified.**

  **THE STUCK-BRANCH TALLY — conservation-complete, and the enumeration it corrects was WRONG BY
  TWO.** Oracle: `git cherry origin/main <branch>` over every `refs/remotes/origin/claude/fire-*`,
  read-only, no cherry-pick and no `reset --hard`. Population **83** refs, partitioned:
  **51 RETIRE-ABLE** (zero unlanded commits — every commit content-present in main) ·
  **32 OUTSTANDING** (≥1 unlanded commit), holding **37 commits** · **0 landed by this effort**.
  51 + 32 = 83, conserved. W-R3's own 18:21 enumeration (`/tmp/r3-commits.txt`) listed 35 commits
  over 31 branches and **missed two** — `4da7836cf` (2026-08-18T01:18:36Z, postland bisect
  no-verdict) and `60eaebef7` (2026-08-13, autonomy-sweep wedge). So the true population is **37/32,
  not 35/31**, and any tally that had summed to 35 would have "conserved" against a denominator
  that was already short. Controls run because a uniform verdict indicts the instrument: `git
  cherry origin/main origin/main` and `…origin/main~5` both report 0 `+`, while outstanding
  branches report 1–2 — the oracle discriminates. Artifact: `/tmp/r3-TALLY.txt`.

  **WHY THE LEAD DERIVED IT AT ALL: BOTH W-R3 SESSIONS ARE WEDGED ON A MODAL NO AGENT MAY ANSWER,
  AND THE TWO SAFETY BELTS THAT SHOULD HAVE CLEARED THEM BOTH DECLINED — CORRECTLY.** Panes 275
  (sid `3492adf8`, fired 18:18:27) and 276 (sid `79e3867f`, 18:22:29) are BOTH live claude
  processes in the SAME worktree `fix/cloud-branch-debris` — two writers, one git index — and both
  sit at the same `PreToolUse` confirmation for `git reset --hard`. Neither can advance:
  * `cc-pane send 276 2` (answer the modal) → **denied by the auto-mode classifier**. Cross-pane
    keystroke injection is not available to an agent, so the modal is structurally operator-only.
  * `cc-teardown cloud-branch-debris-276` → **DEFER `tty-busy` (exit 10)**, "refusing collateral
    close": a process on the pane tty sits outside the target claude tree. That belt is right, and
    it means **a session wedged at a modal cannot be torn down by the autonomous path at all** —
    `--force-adopted` is operator-CLI-only and does not address `tty-busy` anyway.
  Zero-loss verified before proposing anything: both trees clean, 0 commits ahead of origin/main,
  276's scratchpad probe-wt clean at `c13572ad2`; the enumeration survives in `/tmp`. **No third
  R3 was fired** — the goal forbids duplicate work and the two wedged clones still hold the branch.
  The generalisation: **a permission modal is a liveness state no belt models.** The session is
  neither idle (teardown's precondition) nor working (the supervisor logs it `permission_pending`
  and does nothing with it); `lead-supervisor` has been re-logging these two every 30 s for 18+
  minutes with no actor able to consume the signal. Filed as an operator step (`135e62b5ff49`).

  **AND THE STRUCTURAL FINDING THAT REFRAMES THE PROGRAM'S OWN TARGET: THE DRAIN IS WORKING AND
  THE NUMBER STILL RISES, BECAUSE `block` OUTRUNS `unblock` 171:26.** Ledger flow, last 24 h:
  `done 134 · add 97 · block 171 · unblock 26`. Open went 429 → 431 while recycle #18 closed four
  rows — not a stall, an accounting fact: `cc-backlog list --open` = **431 = 273 open + 153 blocked
  + 5 claimed**, and blocked rows are operator-gated, so **the 24/7 pipeline structurally cannot
  drain 153 of the 431 no matter how well it runs**. Agent-actionable open is **278**. Two
  consequences, and the plan should pick one deliberately rather than let the number decide:
  (a) the recycle brief (§4.1) grows an explicit **unblock/triage pass** over the blocked pool, so
  something on the agent side can retire operator-gated rows that have gone stale; or (b) the
  program's success metric becomes **agent-actionable-open**, and `list --open` stops being quoted
  as progress. Until one lands, "drains to zero and stays there" is unreachable by construction —
  the target is measured against a pool the drain has no verb for. Filed as `eb41813aa373`.

  **Cloud lane, unchanged and green:** `session_018in35KSYj7iLV7jZCNuCnj` **RETURNED** at
  09:04:28Z — `goal:"MET"`, `content_verified:true`, 4 research docs, backlog `c33f3b1cb278` marked
  done, custody discharged. The account-`next` 401 cured exactly as designed: by a session
  launching on `next`, never by forced rotation.

- **2026-08-18 ~01:47Z — recycle #18: `master-session-lifecycle` 20 open → `16 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 0 / closed 4. Four commits, ONE land.**
  Two clusters, both entirely on the lead. **The spawn gate refused all three teammate briefs**
  ("Background subagents cannot write code — use TeamCreate/team_name"), where #17 lost 1 of 4 and
  #16 lost 2 of 5. `TeamCreate` does not exist on 2.1.220 and the Agent schema has no `team_name`,
  so the instruction is unreachable; per the standing brief the rows were taken inline rather than
  re-worded. A successor should budget for the gate being FULLY closed, not partly.
  - **Kitty keepalive (`71c2c19d6c63` · `a94c9e5722f7` · `d591c8d990b5`, `d3af4367` + `d09cec4c`).**
    The idle-pane arm was iTerm2-only, so on a kitty fleet it was inert. **Cause correction: the row
    says "bin/it2 already diverts" and there is no `bin/it2`** — the divert is `bin/it2-wrapper`
    (split/close for teammate panes, not a send path) and the kitty adapter is a third file,
    `bin/it2-kitty`. None of it was reachable anyway: `IT2` defaults to the REAL python it2 binary,
    so **the send path resolved PAST every divert** — "0 kitty references" understated it. The arm
    now drives `bin/it2-kitty` and matches markers on window **cwd**, not scrollback (a long-running
    pane scrolls its worktree name off and silently stops matching). `d591c8d990b5`'s third skip
    predicate — never nudge a pane awaiting ITS OWN armed watcher — landed with it, and the three
    predicates are declared ONCE and rendered into both the AppleScript `contains` clauses and the
    kitty grep, per `hooks/lib/pane-modal.sh`'s standing warning that a copied screen predicate rots
    independently. Docs carried a **second stale interface**: Phase 4 still prescribed capturing pane
    ids into `/tmp/reso-keepalive-ids.txt`, an interface gone since `410f920c`.
  - **Engine capacity gate (`eda267ff4b14`, `3296d71d`).** §12.1's last bypass: a direct call to
    `bin/reso-resume-one` spawned against no admission check. Gated in its own body, same shape as
    the launcher's, exit 9 = shed. **The row did not name the interaction that matters** — the
    launcher already runs this gate and the consecutive-refusal BUDGET is shared state, so a naive
    second gate double-spends it and releases the bound early on a box that never settled;
    `CC_ADMIT_DONE` marks the admission that already happened. `capacity-admit-coverage` case 25 was
    **inverted exactly as its own text instructed** ("will redden the moment that lands, which is
    when it should be rewritten to assert the gate") — an instructed inversion, not a relaxation.
  - 🚨 **TWO OF THIS WAVE'S OWN NEW ASSERTIONS ASSERTED NOTHING, and only the land gates said so**
    (`d8f4340f`). (a) `A && { …; false; }` is errexit-absorbed and therefore dead;
    `bats-assert-liveness-fix.py` **DECLINED** to repair it (split across two lines, no faithful
    re-flow), so it was hand-rewritten and proven live in both directions with a mutant — a negative
    assertion whose condition is already false cannot distinguish "revived" from "always passes".
    (b) the kitty arm made `bin/it2-kitty` a subject, and it reads `CC_PANE_CMD_INTERACTIVE` —
    injected into every pane this repo launches, so the suite would go red only when run from a
    fired pane. Both fixed at the source the lints prescribe; the allowlist was not touched.
  - 🚨 **A CASE CAN PASS PRE-FIX BECAUSE THERE IS NOTHING THERE TO BREAK.** The
    no-double-evaluation case went GREEN against the pre-gate engine while its three siblings
    correctly reddened: an engine with **no** gate also fails to evaluate one twice, so *suppressed*
    and *never there* are the same observation from the marker's side. Caught only by running the
    red-proof per case rather than per file. Same shape bit the absent-library case, unreachable
    from a checkout because the engine's first search path is its own sibling `scripts/lib/`. Both
    now carry a control that must SHED. **Ask of every green pre-fix case whether its subject even
    exists yet.**
  - Instrument note for the successor: `71c2c19d6c63`'s stored falsifier reads
    `$HOME/.reso/bin/reso-keepalive`, a symlink into the SHARED CHECKOUT — so it retracts against the
    tracked subject immediately but not through the symlink until the land converges that checkout.
    Landed ≠ live, per the ledger's `🚀` rung; read which surface a falsifier names.

- **2026-08-18 ~01:40Z — both lanes PROVEN end-to-end; the chain is 8 recycles deep; open
  568 → 427.**
  DRAIN CHAIN #12-#17 (all unattended): stranded-work 0/5 · verification-integrity 0/1 ·
  enforcing-store 0/11 (16 closed in #14 alone) · session-lifecycle 32→20 in progress;
  conservation printed every recycle; survived a 3.75h ENOTFOUND route outage (#16, lead did
  the refused rows itself). Notable chain lands: b5f685081 (the 789-pin retry burn — ship-land
  discarded rerere-staged resolutions), cc-close-attrib EINTR fd-9 launch-kill find (#13).
  S4 COMPLETE — and its refutation is the finding: the daemon env was FINE (109 real rows vs 6
  abstains interleaved; my tail sample was an abstain burst — a tail of an interleaved log is
  not the population). TWO real causes: (1) postland-verify's THROWAWAY-WORKTREE copy of
  cloud-return.sh held the return lock (deployed-copy gate `case $0 in $_cc_cfg/*` could not
  discriminate — postland mints worktrees UNDER the config dir); exact-path gate + behavioural
  test landed ba69a4510; (2) account next's OAuth ACCESS token expired — HTTP 401, discriminated
  same-call-same-second (next=401, others=404-authenticated). Sensor un-muted (54aa27cd6 — a
  bare command substitution was discarding every diagnostic), reaped-TMPDIR fix 33cf5df17.
  **PRODUCTION PROOF: 3 cloud sessions returned end-to-end — landed, content-verified, goals
  MET, custody discharged** (016cCpabd…, 01ByarSY…, 01GsPHLD…). Their "unknown id" row-close
  failures were the rogue copy's environment (all 3 ids hold 7-8 store hits; all 3 rows now
  fold done) — lookup-miss ≠ absence, cured by the exact-path gate.
  A2 residual: session_018in35… is RETURN-READY (ref pushed db0981de6) behind next's 401; the
  relogin gate refuses on live-session grounds (endpoint k counts CLOUD sessions; zero local
  processes on next) — refusal honored, G2 credential surface untouched; second-order gap filed
  8636b8f829fe (health gate blind to expired access token). Cure in motion: W-R3 fired ON
  account next (launch = native token refresh) to clear S4's two handed-back blockers (39 stuck
  cloud branches: 15 rc=65 stale worktrees + 18 rc=70 VM-doc conflicts). Fire saga: 2×
  "never-engaged" verdicts were the DETECTOR missing a width-wrapped marker + pane 275 stalled
  at a settings.json hooks-update modal (sibling of the fixed .mcp.json class — filed
  8ea3acef7d64, condition fired-session-startup-modal); 276 is the working session
  (goal-arm unreachable on both — brief carries the DoD); 275 refused by teardown's adoption
  belt, left for reaper GC.
- **2026-08-18 ~00:40Z — recycle #17: `master-session-lifecycle` 27 open → `20 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 1 / closed 7. Ten commits, ONE land.**
  Seven rows: three on the lead (`471d2f3f98df` cc-announce, `08c746312188` handoff-disposition,
  `8370af320af5` comms-strand-report), two from teammate t2 (`aa8aed0d713a` cc-roles + the phone
  leg) and t4 (`dcf58e1ba056` cc-classify), two from t3 (`ac914e8982b8` + `fc54aeebec4a`,
  waiting-recycle — one file, one owner). The one filing (`ebbf3adfb4d0`, linked to
  `master-verification-integrity`, NOT to the effort being drained) is below.

  **THE FINDING FOR #18: THE WATCHER, THE ROLE AND THE MAILBOX ALL PROVED THAT AN IDENTITY IS
  PLURAL, AND EVERY ONE OF THESE BUGS IS A PROBE THAT LEARNED ONLY ONE SPELLING OF IT.** Three
  independent rows this recycle turned out to be the same shape, and none of them said so:
  * `08c746312188` — `handoff-disposition.sh` asked `pgrep -f "cc-await-ping.*$uuid"`. The wake
    floor arms that watcher with **no id in argv, deliberately** (`session-continue.sh:595`), so
    the tool can derive the key itself and cover the whole set. The probe therefore reported
    `false` over a *running* watcher and told a pane awaiting a peer that it was close-eligible.
  * `8370af320af5` — a mailbox box key is written in **two** spaces (pane id, and the registry's
    `session_id`); the strand report adjudicated against pane ids only. Measured live: of 534
    boxes it called dead, **eight belonged to sessions alive at that instant, including the
    session running the report**. Under kitty the spaces are not even the same shape (`131` vs a
    36-char uuid), so the match could never have succeeded by luck.
  * `aa8aed0d713a` / `dcf58e1ba056` — the same lesson twice more: a role that is only an address
    with no liveness, and two auditors keying tenancy on `startedAt` vs `cwd`.
  The generalisation to carry: **when a probe asks "is X live?", ask which of X's names it is
  asking about, and whether the thing being observed chose that name.** In every case here the
  producer picked one spelling for a good reason and the consumer hard-coded another.

  **AND THE COROLLARY THAT ALMOST HID IT: `8370af320af5`'s POSITIVE CONTROL PASSED THROUGHOUT.**
  It asked whether *this pane's* id was in the *pane* list. It was. So the control certified the
  oracle on the one axis that could not fail, while being structurally blind to the axis that
  did — the report has shipped a wrong live/dead split for as long as both spaces have existed.
  A control has to be independent of what it certifies; the fix makes the registry a REQUIRED
  second oracle on the same fail-closed terms as the first (unreadable ⇒ `verdict=unknown`, no
  numbers), because with it unread every uuid-keyed box is fabricated-dead.

  **A PARTIAL REFUTATION, RECORDED RATHER THAN SMOOTHED OVER.** `8370af320af5` also claimed the
  headline `dead_never_surfaced` figure was wrong. It is not — 14873 before, 14873 after. The
  eight misclassified boxes hold no never-surfaced lines *at this instant*, so the classification
  error never reached that number. The mechanism for it to be wrong is real (a live session's box
  with unread mail would count as stranded loss) but the count itself is currently sound. What the
  fix actually corrects is the box classification (live 10 → 18) and the blind control.

  **A ROW RE-MEASURED, STILL OPEN, AND GENUINELY NOT MINE — `85a82455de9a`.** Two of its three
  asserted paths have converged since filing (`commands/resume-sessions.md` and
  `~/.reso/bin/reso-resume-one` are now symlinks; the latter was a real pre-vendor copy). The
  third, `~/.claude/bin/reso-resume-one`, is still ABSENT. `deploy-live.sh` refuses correctly —
  *no GREEN tree is a DESCENDANT of live HEAD* — and reports the lag as "inside the degrade
  budget (25/6h)", which is exactly the reading CLAUDE.md warns against: **an ADD gets no budget**,
  so a lag of 11 is a breach at 1 for this row. Left open, un-mutated, and named here so #18 does
  not re-derive it. Only `postland-verify.sh` advances that stamp; this recycle's own land adds
  more un-stamped commits above the pin.

  **THE FILING (1).** `ebbf3adfb4d0` — peer mail paged this chain with a post-land RED naming
  `tests/cc-wait.bats` at culprit `0f55846f7de4`. That commit changes **one file,
  `docs/plans/BACKLOG_DRAIN_24_7.md`, +88 lines and no code** — it cannot reach a bats subject.
  The suite is 19/19 green at `origin/main` HEAD with its plan line present, and the page's own
  env recorded `load 16.45`. So a contention flake was bisected and the nearest commit elected as
  culprit. A bisect must be able to return NO VERDICT; a candidate that touches no file the test
  loads is not a candidate. Filed to `master-verification-integrity`, not here.

  **PROCESS NOTES FOR #18.** (a) The spawn gate deterministically refused one of four teammate
  briefs with the unreachable "use TeamCreate/team_name" instruction — that row was taken on the
  lead immediately, per §4.1; do not re-word. (b) `cc-bats` REFUSED twice mid-recycle while
  teammates held execution roots — **no `1..N` plan line, so no verdict**; every suite below was
  re-run until it emitted one. (c) All three teammates returned real discriminator pairs this
  time, unlike #16 where the lead had to write both controls — the briefs demanded the REMOVE half
  FIRST and named it as the deliverable, and t2 went further and proved its *mutant* was the gated
  variant rather than a merely-broken file.

  **GATES (run this turn, on the merged branch, not recalled).** `cc-announce-alarm-body 1..5` ·
  `cc-announce 1..18` · `announce-before-retire 1..21` · `handoff-disposition-watching 1..5` ·
  `handoff-disposition 1..24` · `comms-strand-report-identity 1..6` · `comms-strand-report 1..9` ·
  `cc-classify-origin-unify 1..10` · `cc-classify 1..69` · `cc-roles-liveness 1..18` ·
  `cc-notify 1..87` · `waiting-recycle-disarm-ttl 1..6` · `waiting-recycle-account-neutral 1..5` ·
  `waiting-recycle 1..114`. 402 tests, zero `not ok`, every plan line present.

- **2026-08-17 ~17:30Z — recycle #16: `master-session-lifecycle` 32 open → `27 open / 1 blocked
  (1 operator-gated `source: needs`; 0 cloud-venue)`. filed 0 / closed 5. Six commits, ONE land,
  `ef98781de`; content-verified on `origin/main` (`git diff` empty on all 9 paths).**
  The effort is an order of magnitude larger than #14's and #15's, so this is a multi-recycle
  effort as briefed; five rows closed is the advance, not the finish.

  **THE FINDING THAT SHOULD CHANGE HOW #17 READS A ROW: A ROW CAN NAME THE RIGHT BUG AND THE WRONG
  CAUSE, AND THE WRONG CAUSE HIDES THE DANGEROUS HALF.** Row `567a4d90ca89` said validate-bash
  *"convicts a benign rm because an unrelated `$HOME/.claude` string sits elsewhere in the same
  command."* The bug is real. The cause is not the string — it is the **separator**. `rm_argv_scan`
  split clauses on a PIPELINE_OPS set that included `;`, but tokenized with `shlex.split()`, a WORD
  splitter, which only ever sees an operator the writer surrounded with whitespace. `&&` and `|` are
  conventionally spaced and worked; `;` is conventionally **glued** to the word before it, was never
  a token, and so the entire next clause became targets of the rm. That failed in BOTH directions:
  the filed false positive (a build-artifact delete refused because a later clause names `$HOME`)
  **and an unfiled false NEGATIVE — a recursive delete of `~` glued to `; echo hi` was DOWNGRADED
  out of the deny to ASK.** Spelled with a space before the `;`, the identical command DENIES. The
  row would never have found that; only probing the row's claim in the opposite direction did
  (memory `guard-proxy-fails-in-both-directions`). **So: reproduce a row's SYMPTOM, then re-derive
  its CAUSE yourself, then ask what the corrected cause predicts that the row never claimed.**

  Same shape twice more, both times caught by a test rather than by reading:
  - **A KEEP that passes for the wrong reason is indistinguishable from a KEEP that works.** Writing
    the worktree-gc control, the recent-write signal appeared green twice while never being
    consulted: a plain untracked file trips the *dirty-tree* gate, and committing a `.gitignore`
    inside the worktree leaves the branch *unlanded* — two OTHER gates held the tree. Only the
    REMOVE half of each discriminator pair exposed it. Write the REMOVE half first.
  - **An arm with no test seam cannot be tested, and reads as tested.** The custody floor probed
    `$(dirname $0)/../bin/cc-custody` and so resolved the REAL binary out of the checkout — a suite
    could only ever exercise it against the operator's LIVE store. Before the `CC_CUSTODY_BIN` seam,
    the three "must block" cases failed and the two "must NOT block" cases passed **vacuously**.
    That asymmetry is the signature: if the negative half of a pair is the only half passing, the
    subject is not being reached.

  **A CORRECTED MEASUREMENT CLOSED A ROW WITHOUT THE FIX IT ASKED FOR.** `22705859d07d` filed two
  halves. The performance half is **REFUTED**: `d31fee77f` landed 2026-08-11 14:42, the same day the
  row was measured, and `find_active_list` now runs 0.11 s on the live 2,640-dir store, so the 5 s
  hook timeout cannot fire and `rc=124` — the mechanism the row named — is unreachable. Its stored
  falsifier cannot see this either way (it greps for a per-directory loop that is still present and
  now pure-bash). The **correctness** half survived that fix untouched, because it was never about
  the timeout: a missing index, an unparseable index and a genuinely-unmapped project were
  byte-identical AND rc-identical, so every consumer read "no task list" off a question never
  answered — and `setup-task-symlinks.sh` DELETES a good `_current` symlink on that verdict. Fixed
  three-state on the **exit-status** channel, the only one that survives the command substitution
  every caller wraps the function in.

  **OPERATIONAL, FOR #17 — the wave died to the ROUTE, not to itself.** Five teammates were briefed;
  the spawn gate deterministically refused two of them ("Background subagents cannot write code"),
  and the surviving three all died within two minutes of each other on
  `API Error: Unable to connect to API (ENOTFOUND)` — the local-route signature
  (memory `mass-tls-hostname-mismatch-indicts-the-local-route`), which also cost this session ~3.75 h
  of wall clock. Two of the three had COMMITTED before dying and lost nothing; the third had 111
  lines uncommitted, recovered only because the lead banked it. **Keep telling teammates to commit
  early — it is what makes a network death survivable.** Both refused rows were then done by the
  lead, so the refusal cost time, not scope.

  Rows closed: `567a4d90ca89` (validate-bash tokenizer) · `63484cfeab2a` (worktree-gc occupancy,
  two signals, decorrelation measured not assumed) · `9581119669f9` (custody floor attributed by
  `originatorPane`/`notifyBack`, not cwd) · `2d0074dae889` (`clear` reports what it actually did) ·
  `22705859d07d` (task-helpers three-state verdict + perf half refuted).
  Suites run by the lead this turn, because the land's smoke gate answered **FULL** (its fail-closed
  "cannot decide") and made no direct-suite claim: `rm-argv-normalize` 1..15 · `worktree-gc` 1..97
  (was 1..89) · `wake-floor` 1..43 · `session-continue` 1..27 · `task-helpers-verdict` 1..9 ·
  `rm-safe-allowlist` · `validate-bash-{payload-parse,differential,audit-log,goal-guard}` — all
  green, every plan line present.

- **2026-08-17 ~13:50Z — recycle #15: `master-enforcing-store` 1 open → `0 open / 11 blocked
  (10 operator-gated, 1 cloud-venue build)`. filed 1 / closed 2. Eight commits, two lands,
  `6644273f3`; content-verified on `origin/main`.**
  The condition's last row was `8942f3b1506d` (R-3, HOOK_CHAIN_COST): *"validate-bash.sh does 12
  grep forks bash can do natively (~42 ms) — BLOCKED on a differential corpus proving identical
  verdicts on every DANGER pattern first."*

  **The row was ADJUDICATED, not implemented, and that was its own instruction.** The corpus is
  what the row blocks itself on, so the corpus is the deliverable and the optimization was only
  ever whatever the corpus authorized. Built
  (`scripts/validate-bash-differential.sh`, `tests/validate-bash-differential.bats`, 31 site rows ×
  66 cases = **1,672 scored pairs, 56 diverging**), it authorizes almost nothing: **10 of 30 sites
  are safe to convert, 20 are not, and on the modal path exactly 1 of the 10 always-executed greps
  is convertible** — a ~2.6 ms prize, not 42 ms, against a gate carrying the
  `denylist-enumerates-spellings` scar.

  🚨 **THE TRANSFERABLE FINDING: the blocker was not subtlety, it was a SILENT SEMANTIC INVERSION,
  and it fails in BOTH directions.** `\b` is a word boundary in the BSD grep this hook resolves and
  a **literal `b`** in bash's `=~`, whose `regcomp` has no such escape and drops the backslash.
  Measured with every other axis held out, plus a control:
  `'\bconfig\b'` vs `git config --get x` → grep MATCH, bash **no** (*the guard goes silent*) ·
  vs `git bconfigb --get x` → grep no, bash **MATCH** (*the guard fires on noise*) ·
  and `'config'` vs the same input → both MATCH (control: without `\b` they agree). **13 of 27
  predicate sites carry one.** Second cause: `grep` anchors `^`/`$` **per line**, bash `=~` over the
  **whole string**, and `$CMD` is routinely multi-line here — which is exactly why `61826e193`
  (heredoc bodies are stdin, not argv) had to exist. *An equivalence you can only check by reading
  is one you have not checked; both causes are invisible in a diff and loud in a corpus.*

  **The premise decayed in BOTH directions AT ONCE — this sharpens #14's lesson rather than
  repeating it.** #14 found the UNIT decays before the VALUE. Here the count decayed **upward**
  (12 → **14** grep forks) while the ms decayed **downward** (42 → **36.7**), so the two errors
  partly cancel and the headline scalar still looks about right. It is not: 4 of the 14 live in
  `hooks/lib/is-true-flag.sh`, a file the row never names and its stated precondition does not
  cover. **The durable unit is the exec count, not the millisecond** — counts were byte-identical
  across three independent runs while the wall clock moved with load inside ten minutes.

  **Three things larger than R-3 that R-3 did not contain**, all from the census
  (`docs/research/validate-bash-fork-census-2026-08-17.md`): `grep` is **51%** of the modal path,
  not the whole story (24 externals, 14 of them grep) · one `python3` exec is **24.45 ms, 9.3× a
  grep**, the most expensive fork in the file · and the hook parsed **the same stdin payload three
  times**. The last one was filed (`054499f0c342`) and then **done** in the same recycle:
  **+7.02 ms median paired, 113/120 pairs**, plus the audit logger's own `mkdir`+`date`
  (**+2.28 ms, 96/120**) — **~9.3 ms off a 71.9 ms modal path, 13%**, with no danger pattern
  touched.

  🚨 **A NULL RESULT WAS AN ARTEFACT OF THE EXPERIMENTAL DESIGN, not of the change.** The logger
  lever first measured **blocked A-then-B at n=41: 67.36 vs 67.59 ms — no saving, nominally
  slower**, and would have been reported as a refutation of my own work. **Interleaved paired** runs
  at n=120 resolve the same change at **+2.28 ms, 80% paired wins**. Load drifts over minutes and a
  blocked design charges that drift to whichever variant ran second. *At small effect sizes the
  DESIGN, not the sample size, decides whether the effect is visible at all — and a null from a
  design that cannot resolve the effect is not evidence of absence.*

  **A guard that could not fire, caught only by a mutant.** The TSV arity guard added for the
  field-collapse ratchet first lived inside `build_payloads`, whose one caller is
  `NCASES="$(build_payloads)"` — a **command substitution, i.e. a subshell** — so its `exit 2` ended
  the subshell and the parent ran on with `NCASES` empty. A deliberately malformed corpus produced a
  **full clean run at exit 0**. Hoisted to top level; both guards now proven in both directions.
  Same family as `dispatching-alarm-can-be-the-defect`: *ask where the guard's exit actually lands.*

  **FIVE ratchets fired across four land attempts, every one a real bug in this land's own diff** —
  budget for this, it is the norm, not bad luck. shellcheck (SC2004; three SC2016 hits were
  intentional and took reasoned disables) · test-hermeticity (`validate-bash-differential.bats`
  ran against the operator's live `~/`) · bats dead-assertion (**9** assertions errexit could not
  reach; fixed with `scripts/bats-assert-liveness-fix.py`, never by hand) · self-path (all three new
  harnesses derived a root from an unresolved `$0`; through the live per-file symlinks they would
  have read `~/.claude`, found no fixtures, and **reported nothing rather than failed**) · TSV
  field-collapse. **The self-path gate's own message read `--selftest FAILED — the detector no
  longer discriminates`, which reads as a broken lint. It was not**: the selftest's last arm asserts
  GREEN on the real tree, and the real tree was dirty *because of my diff*. Attribute before you
  drive — and a gate accusing itself may be accusing you.

  **The corpus caught ME, which is the point of building it.** Collapsing the payload parse shifted
  every line below it by +28, and the differential's coverage and drift assertions **refused to
  score** until the site inventory was re-pinned. Three of my own controls also failed first: a
  `sed` whose `|` delimiter collided with a `|` in its replacement; two anchors that correctly
  detected the stamp had MOVED to the new top-of-file parse; and an anti-vacuous mutant that deleted
  the stamp instead of freezing it — **the fallback silently repaired it, so the control was
  measuring the fallback, not the change**. Each failure was a real defect in the control.

  **Blocked tail, stated by stratum** (`zero-claim-must-name-its-excluded-strata`): 8 are
  `source: needs` operator-platter rows, 1 needs root (`memorystatus_control`), 1 needs a `launchctl
  enable` in the user domain — **10 operator-gated** — and **1 is a cloud-venue build item**
  (`02ba4e52389a`), which is outside this lane's non-cloud contract. #14's close said "11
  operator-gated"; that was one too generous. Also noted, not closed: `5436396f405c`'s agent-typed
  half is now enforced live by #14's FF-GATE (`17ecae6c6`), but a human-typed advance remains
  unhooked, so its `needs` row stands.

- **2026-08-17 ~11:30Z — recycle #14: `master-enforcing-store` 17 open → `1 open / 11 blocked
  (11 operator-gated)`. filed 0 / closed 16 (15 done + 1 blocked). Nine commits, one land,
  `7c08a4bbf` + the row-6 doc; content-verified on `origin/main`.**
  Six of the seventeen rows retired for ZERO code on re-validation. **The transferable finding is
  that a row's premise decays in BOTH directions, and the UNIT decays before the VALUE.**

  **The unit, not the number, was wrong twice — and both times the convenient reading was the
  wrong one.** `1c16b58d9d3b` measured MEMORY.md in raw BYTES against a 24.4 KB limit; the repo had
  already replaced that instrument (2026-08-15, `7a56de4c54ab`) with **25,000 stripped CHARACTERS**,
  and `hooks/memory-nudge.sh:22` marks its own old figure SUPERSEDED in a comment. Measured with the
  canonical `hooks/lib/memory-index-measure.sh`: **23,112 chars / 140 lines against 25,000 / 200** —
  92.4%, not breaching, and `cc-memory-rotate`'s `ROTATE_AT` is `LIMIT-1500` = 23,500, so the
  actuator sat **388 chars from firing on its own**, wired 5/5. It is a 13-row near-duplicate family
  across `memory-index-near-cap` / `memory-index-over-budget`, every one measuring bytes against the
  dead limit; three are still open under other conditions and `7c266e16fc94`'s "OVER its limit,
  trailing entries SILENTLY dropped" is a **false alarm** under the corrected measure.
  `a78f0fa4223a` asked to prune "one-shot exact-matches": 63.2% of patterns ARE exact — but
  **exactness is not deadness**, and the teammate REFUSED the row's own predicate on measurement and
  shipped a provable-redundancy one instead (245/2399 = 10.2%), re-measuring 59/2036 → 63/2399 on
  the way.

  **A falsifier can be POLARITY-BLIND to the remedy that actually shipped.** `7d18f9c26f1f`'s probe
  was `test -x scripts/team/verify-team.sh` — it could only retract if that script were RESTORED,
  the opposite of the row's own other sanctioned remedy ("fix both or delete the arm"), which is
  what landed (`2d7b125d6` deleted the arm and its vacuous suite; `cb6314be1` fixed the
  `VERIFY_EXIT=$?`-after-`|| true` half). Its rc 1 was a NON-VERDICT, not a defence of the row.

  **Three ratchets caught the LEAD, and all three were real bugs — budget a land cycle for them.**
  (a) pipefail-SIGPIPE caught my own `git ls-tree … | grep -q .`: `-q` exits early, SIGPIPEs the
  producer, and under `pipefail` the condition **reads FALSE on a MATCH** — a path that IS present
  would have been reported absent. (b) The bats dead-assertion ratchet caught my ANTI-VACUOUS arm
  being itself vacuous — a `!` negation MID-test is dead because errexit skips it. (c) My own
  wrapped prose line beginning `# shellcheck read each bare …` was parsed as a malformed directive
  and aborted the whole file, which that lint's `--selftest` caught. **Four land attempts for one
  land.**

  **A teammate corrected the lead's instrument, and that is the methodological keeper.** I screened
  the `.claude-next` hooks fork with `cmp -s` and reported "52 identical" — **`cmp` FOLLOWS
  SYMLINKS**, so a link-into-the-checkout compares equal BY CONSTRUCTION and the sweep was vacuous.
  The conclusion survived for a better reason (0 regular files of its own, empty reverse gap), and
  `migrations/0013` now classifies each entry (same link target / resolved-byte-identical /
  directory) and refuses on anything else, with arm 6 pinning exactly that.

  **Lands.** `ee05adc63` (`bf63ce9f91fd` — `code_locality_warn`: a DISPATCHABLE label can still name
  a repo without the code; 0 misfiled among the 13 path-bearing rows, 36 of 49 UNMEASURED and said
  so) · `dcd16bd32` (`61d8605a25fc` — install.sh; the value is `$HOME`-derived while the write is
  `--global`, and git resolves `--global` through `GIT_CONFIG_GLOBAL`/`XDG_CONFIG_HOME` first, so
  they are not bound to the same HOME; discriminator is the passwd DB via getpwnam, not a path
  denylist) · `4063d5679` (`a78f0fa4223a`) · `963dbd0a2` (`70cc9f44040f` — grouping-sweep fail-CLOSED;
  **exit 2 is a measured choice**: `--assert` is this script's own stored falsifier and cc-premise
  reads exit 0 as THE CONDITION IS GONE, so an absent engine did not merely fail to measure, it
  RETRACTED the escalation row — 2 is already in `_FALSIFIER_UNASKABLE_RCS`, and autonomy-sweep's
  consumer was fixed in the same diff) · `11b85f97b` (`a148bd3bc3e6` — cc-premise gated on the
  ITEM's project, not the SHA's, so every meta-item about another repo minted `verdict=suspect`;
  now widens to sibling repos on a miss and keeps THREE states, and a real fixture leak was caught:
  unpinned, the widening reached the operator's real checkouts where the "resolves nowhere" token
  resolves) · `7b1049846` (`7ea31ffa1a08` — migration 0014; the trace question its filing gated on
  is SETTLED: **352 subagent transcripts exist**, so it is a harvest-index gap, not data loss) ·
  `17ecae6c6` (`8c6606b6f048` — FF-GATE; the class was DETECTED and enforced by nothing, and the
  quiet since 08-12 is not a fix: `5626e682f` removed deploy-now's raw ff on 08-10 and ungated
  advances continued two more days) · `7c08a4bbf` (`11da376d60e3` — migration 0013) ·
  the row-6 doc (`f5b31e05b0f7`).

  **`f5b31e05b0f7` — GROUND-UP row 6 reconciled, and the campaign's last row now self-heals.**
  `docs/plans/GUARDRAIL_HOOKS_V2.md` (262 lines) exists and is `status: open`, so the `plan-open`
  generator — which takes an OPEN PLAN DOC as input and was structurally blind to the one row that
  never had one — can now mint dispatcher-reachable rows for it. STEP -1 against `origin/main`, 18
  days after the payload was composed: **8 of 12 claims MET or SUPERSEDED**. The whole graveyard
  cherry-pick step is DEAD WORK (all five files on trunk, proven with a negative control beside the
  positive); row 13's inbound remainder is SUPERSEDED because **row 13 falsified its own premise**
  (contaminated denominator; clean instrument 92/92 = 100%); the payload's "`/goal` DOES NOT EXIST"
  inferred absence-of-FEATURE from absence-of-a-slash-command-FILE. **What still FAILS is what the
  row was commissioned for, and it got WORSE**: 62→**79** distinct `(event,script)` pairs, 4→**7**
  drifting, every one missing from `.claude-next` ALONE, because registration writes four files and
  skips the fifth — and `settings-drift-assert.sh` is correct, has a `--selftest`, and has **zero
  live callers**. Root cause is A8: all five `settings.json` are REAL FILES with distinct inodes, so
  hooks converge for free via per-file symlinks and `settings.json` does not converge at all.

  **THE ONE ROW LEFT OPEN, and the instrument defect that stopped it.** `8942f3b1506d` (R-3,
  HOOK_CHAIN_COST) is BLOCKED by its own terms on "a differential corpus proving identical verdicts
  on every DANGER pattern first". Its premise is stale — it says 12 grep forks / ~42 ms;
  `hooks/validate-bash.sh` is now **1012 lines with 32 grep sites**. A teammate built the right
  harness (a shim dir on `PATH`, one wrapper per external, logging each exec) and it **self-destroyed
  on a defect worth inheriting**: every shim body is `exec grep "$@"` while `PATH="$S/shim:$PATH"`,
  so the bare name re-resolves to the shim and self-execs forever — the 772,768 `grep` lines in its
  fork log are ONE INFINITE SELF-EXEC, not a measurement, and the same defect is in `shim/pwd`.
  `measure.sh` already used absolute `/usr/bin/*` for its OWN accounting, so the author knew the
  hazard for the harness and not for the shims. **Fix: `exec /usr/bin/grep "$@"` inside each shim.**
  (Same class as `self-identity-guard-must-fully-resolve`.) Nothing was committed; the row is handed
  to #15 with the corrected instrument.

  **Instrument note for every successor: `cc-backlog list --open` FOLDS IN BLOCKED ROWS.** It
  reported 27 for this condition when the true open count was 17. Filter on `.status=="open"`
  explicitly, and use `(.condition//"")` — a null condition makes a bare `test()` throw.

  **Not claimed as live.** Both new migrations are **c10 by design** (0013 gated on zero live
  `.claude-next` panes — that account HAD live panes at land time; 0014 registers subagent-stop):
  they stage and wait for a human, and `registration-state.sh` reports them `not-delivered`. The
  land's smoke gate SHED (`selector answered FULL … the verifier proves the tree`), so the
  behavioural evidence is that the lead re-ran all nine touched suites in-turn: **115 assertions, 0
  failures**. `deploy-live.sh` was run and **declined**: no GREEN tree is a descendant of live HEAD
  `12b4740c8` (newest green is BEHIND it), lag 23 commits / 2h inside the 25/6h degrade budget — so
  the shared checkout is 23 behind and none of these nine commits are live yet. Not filed as a new
  row: the platter already renders that deploy-lag line, and double-filing it would be net-filing.

- **2026-08-17 ~08:47Z — recycle #13: `master-verification-integrity` at `0 open / 1 blocked
  (1 operator-gated)`. Every one of the four rows was diagnosed WRONG in its own filing, and each
  was wrong in a different way — that is the transferable finding, not any single fix.**
  Lands: **`60b395923`** (0be0bd2c0b65), **`8c2705236`** (67a7d78c1134), **`d862e80af`**
  (ff3f38d6eeed), **`1d77c6d69`** (6a7eb069e703). **filed 2 / closed 4.**

  **The four rows, and what each filing got wrong.**
  · `0be0bd2c0b65` — ship-land RESTATED two lints' judged populations as hardcoded pathspecs, each
  under a comment asking the next author to keep them in step by hand. Nothing executes a comment,
  and the drift fails silently toward advisory (an own-set that MISSES a file does not error — an
  empty own-set is the legitimate spelling of "this land touches nothing I judge"). Both lints now
  answer `--print-scope`; ship-land DERIVES each own-set via `lint_own_scope`. An unanswerable lint
  is rc 2 → `arm_nonverdict` (GATE_KILLED, exit 9), never an empty own-set — that distinction is
  the same defect by a new route, and it is exactly what a future `|| true` would reintroduce.
  Control 9/9 RED at `33cf5df17`, 9/9 GREEN after. **Measured while doing it: the derivation
  NARROWS permgate's own-set** (its actuation globs, not all of `scripts/*`) — behaviour-preserving,
  since a file the lint does not judge can produce no finding.
  · `67a7d78c1134` — RETRACTED on measurement. The cure (`f1b813f6d`, dead-assertion analyzer +
  ratchet) landed 2026-07-25, **18 days BEFORE the row was filed**. 🚨 **The row's `2,561` counted
  `[[` OCCURRENCES, and the cure idiom `[[ … ]] || false` matches the same grep — so the metric
  could never reach zero and the row could never close by being worked.** Live proof the ratchet is
  enforcing rather than merely present: **it took THIS recycle's own land RED** for 6 dead
  assertions in the suite written above.
  · `ff3f38d6eeed` — the builtin-producer exemption cited `printf '%s' "$VAR"` at 0/200 to exempt
  every builtin. **That row measured a SIZE, not a command word.** Re-measured here: 0/10 at 62 KB,
  10/10 FALSE at 64 KiB and above — the boundary is the pipe buffer. Exemption now discriminates on
  the ARGUMENT (literal exempt, variable/substitution/backtick in scope). Census 30 → 157 sites,
  regenerated ratchet, tree green today. **The selftest's own fixtures were the trap:** g1/g2 were
  variable-sourced builtins asserted GREEN, so left alone the control would have certified the bug.
  · `6a7eb069e703` — the flake's stated hypothesis pointed at a `>(tee)` procsub that `61101fb28`
  had already deleted, and the obvious culprit (`52d93432b`, wait/liveness order) landed **9 days
  before the row was filed**, which is what proved a third cause. It is `exec 9> "$TEE_FIFO"`: a
  blocking `open(2)`, bash's SIGCHLD handler is not `SA_RESTART` and bash does not retry, so a
  background child dying in that window aborts it with EINTR and the next line's `2>&9` kills the
  child subshell before it can exec. **Not a flaky test — every eval-track session launches through
  this wrapper, so an interrupted open lost the SESSION.**

  **THE PATTERN ACROSS ALL FOUR, worth more than the fixes:** a filed row's DIAGNOSIS decays faster
  than its SYMPTOM. Two rows named a mechanism that had already been deleted or fixed; one row's
  metric counted its own cure; one row's cited measurement was of a different variable than the one
  it was used to exempt. Re-validate the premise against trunk before building — `#13` spent its
  first 40 minutes doing exactly that and it retired one row for zero code.

  **Cloud lease, and why the condition sat blocked for 90 minutes.** `67a7d78c1134` was held by a
  **cloud**-venue claim, and `claimer_live` returns rc 2 (UNRESOLVED, correctly — this box's oracles
  cannot see a cloud worker) so the CONDITION lease refused every sibling row. `cloud-return`
  abstained: **HTTP 401, account `next`'s OAuth token expired.** The abstain is right (a sensor that
  could not run is not a verdict) but MUTE — it names the account, not the cause; filed
  `c70f3bd06106`. Landed the VM's work by the local half (`cloud-reconcile` → conflict in the plan
  doc → cherry-picked and INTEGRATED both sections in date order), then closed the row on evidence
  re-derived HERE, independent of the VM's report. Do NOT read the board's `next token stale — heal
  skipped` as a gap: it has a stated policy (a live session owns the token lifecycle).

  **Filed (2):** `5fc8ff411a7c` — six MORE ship-land arms restate a pathspec; measured that none of
  their five lints has a runtime env seam, which is why they were left out of scope AND is the whole
  of their defence; cheap to close now the mechanism exists. `c70f3bd06106` — the mute abstain above.

- **2026-08-17 ~07:45Z — the chain is PROVEN self-perpetuating; recovery is COMPLETE; the cloud
  return path is the last leg (S4 fired, pane 154).**
  DRAIN CHAIN: recycle #10 closed master-account-facts at `0 open / 16 blocked (16
  operator-gated)` and fired #11 unattended; #11 closed master-operator-gated at `0 open / 25
  blocked`, conservation 1/1, and fired #12 — **two unattended boundaries = §5 gate (2) PROVEN;
  all four §5 gates now hold.** Chain lands so far: 9d8965faa+9dd286cb3 (install.sh nested-skills
  converger bug), dc47200cc (reap blocks are machine non-verdicts), f5d4a552e (cc-do was
  discarding .run for all 51 blocked rows), e7640e016. #11 found the operator-gated pile is a
  GENERATOR, not 30 judgment calls; the second generator (desk-land refile loop) is filed
  981a403a05fa as #12's pick.
  W-R2 COMPLETE, zero loss: **12/12 stranded branches resolved** (9 landed: 1817ca740 b4d0a3d0f
  f81808f5b 896973916 764f96963 c037c1aa1 73ceb76aa dbaba83ac 76d5dc100 · 3 retired-by-content
  with evidence); paid clawd-bmo assets landed 1e040c79c; blocked re-land rows **30 → 2**
  (neither ours). T1 reaper verdict confirmed at 39× enrichment + fixture repro, fix LIVE.
  Honest conservation: R2 personally +5 (population still drained); 8 branches needed real fixes
  (4 pre-existing on pristine trunk, each control-confirmed). All 12 shas verified ancestors by
  the lead. Custody for this cwd: fully discharged.
  CLOUD LANE: dispatcher now CREATES sessions that RUN (session_018in35KSYj7iLV7jZCNuCnj, item
  c33f3b1cb278, worker_status=running) — but the RETURN path abstains every poll ("control plane
  unreadable") while the identical read succeeds interactively (same ids, same accounts, rc=0) —
  a daemon-environment failure with a muted callee (cloud-return.sh:156 discards stderr). **S4
  fired** (pane 154, fix/cloud-return-daemon): un-mute the abstain, fix the daemon env, prove
  real return rows; the running session is the live A2 end-to-end probe. Also shed: two
  pane-less claude processes of completed S2/R2 sessions (TERMed after the reap-safe
  certificate: complete + custody discharged + pane gone + work content-verified).
- **2026-08-17 ~07:40Z — recycle #12 closed master-stranded-work at 0 open / 5 blocked (5
  operator-gated). Filed 2 / closed 4.** The live retry burn is DIAGNOSED and its cause is
  landed, after 789 `refs/land/failed/*` pins that had only ever been COUNTED.
  **Cause 1 — the lander threw away a resolution git had already applied (fixed, `b5f685081`).**
  Every retry died at ship-land **exit 5 = rebase conflict**, in 2-4 s, `head:"?"` (land.log,
  06:18Z batch); the driver is `cloud-reconcile.sh:559`, which relaxes
  `SHIP_LAND_SESSION_BRANCH_RE` so `claude/*` gets past desk-land's session-branch guard.
  Replaying one by hand showed why the count grew instead of the queue draining: `git rebase`
  exits non-zero the moment a conflict STOPS it, *including* when `rerere.autoupdate` (a global
  setting here, and referenced in NO script in the tree before this) has already replayed a
  recorded resolution and staged every path. `claude/fire-20260816T094145Z-41172-1` stopped with
  both conflicts staged, **zero unmerged paths and zero markers, and rebased clean in ONE
  `--continue`.** A retry can never re-apply a resolution the lander discards — which is exactly
  why 112 attempts on one branch changed nothing. `rebase_onto_trunk()` now asks whether anything
  is ACTUALLY unresolved instead of reading the exit code, and refuses in BOTH directions
  (unmerged paths keep exit 5; staged conflict markers refuse rather than land `<<<<<<<` on
  trunk). Measured while writing it: rerere itself *cannot* reach that second arm — it records
  ZERO postimages when markers remain — so the arm is fail-closed cover for a non-rerere stager
  and `tests/land-rerere-continue.bats` pins the reachable population instead
  (memory: cap-whose-population-is-empty). Mutant-attributed: only the rerere case reds.
  **Cause 2 — the queue was re-landing work that had already landed better.** All three demoted
  re-land rows retract on same-moment content evidence, none of them by commit count:
  `e96021115661` SUPERSEDED (trunk carries `--idle-scoped` ×5 and `mailbox_wake_idle_scoped` ×2,
  and trunk's files are LARGER than the branch's — 864/767, 518/380); `12f5beab9361` SUPERSEDED
  (trunk has the `wt-slug` pattern, the SIGPIPE fix as a variable capture at
  `test-hermeticity-lint.sh:1074` with the branch's own rationale at `:1061`, and now a
  systematic `scripts/pipefail-sigpipe-lint.sh` ratchet for the whole class); `1201e5884d2c`
  ALREADY LANDED 06:19:16Z, head `55e473a8` verified an ancestor of origin/main. **`git cherry`
  printed `+` for all of them** — it compares patch-ids and is blind to a superseding LARGER
  version (memory: landedness-over-commits-is-blind-to-staged-content), which is how #11's
  content adjudication could be right about the commit and wrong about the work.
  **Question 2 stays the operator's, and NOT because it is a value call in the abstract.**
  `ship-land.sh:897` files via the `needs` verb, which files ALREADY BLOCKED, so the row lands on
  the operator platter; these rows need a rebase, a supersession check or a gate fix — no
  credential, no GUI, nothing physical — so they fail CLAUDE.md's operator-step test and *should*
  be agent work. The one-verb fix is a TRAP: the recurrence brake that collapses one stuck branch
  into one row lives in `needs` **and nowhere else** (`cc-backlog --help`:462), so swapping in
  `add` would drop it and resurrect the 41-rows-for-one-branch explosion the brake exists to
  stop. Blocked as `981a403a05fa` with both options and the recommendation: **`needs --role
  agent`** — keep the brake, change the audience.
  Also filed: `44750ff72ae7` — `validate-bash`'s `git add -f` rule DENIED a plain
  `git add f.txt` in a fixture repo mid-investigation; same denylist-by-spelling class the
  memory of that name already records, and it now has a concrete innocent to pin as a control.

- **2026-08-17 ~05:30Z — W-P2 GO-LIVE: the drain chain is running.** (S3's own landed entry
  below carries the full root cause; this entry is the go-live record.) **First GREEN since
  08-15: `416a7191dea8` (475 suites, failing=[], run_s 2374); deploy-live ADVANCED on the
  VERIFIED tier — `origin/main..live = 0`.** Every W-P1 fix is now LIVE.
  Production evidence: the dispatcher's first live passes turned the stale-worktree case into
  claim→refuse→BLOCK (one cycle, wt-02ba4e52389a, 05:01Z) with zero churn on the three old ids;
  a cloud admission is in flight (row e2af8839be87, claim 04:46Z) = the A2 end-to-end probe;
  the lead's postland-red page at 6200a8698 was A/B-exonerated (findings=1 identically at
  parent/self/main). The rc-124 elapsed-discriminator content is on main (cherry `-`; branch
  sha 52e388369).
  **LOCAL DRAIN CHAIN FIRED: recycle #10, pane 131, worktree drain/recycle-10** — brief
  /tmp/fire-drain-recycle10.txt per §4.1 (chain constraint IN the goal; smallest-effort-first
  from the live fold; falsifier-first row picking; conservation printed per recycle; true-zero
  termination clause). §5 gate status: (1) convergence ✓ · (3) freshness ✓ (138 validated /
  5 closed in production) · (4) conservation structural in the goal · (2) the unattended recycle
  boundary proves on the chain's FIRST self-recycle (#10→#11) — watch for it. R2 (pane 106)
  still out: 7/12 stranded branches landed, T2 continuing; ledger shows rows closing with
  "re-land of the stalled cloud session's …" landed evidence.
- **2026-08-16 ~21:53Z — W-P1/S3 landed: the verifier was blocked by a FALSE prelint red, not by
  the ladder bound this wave was briefed against.** Landed `6ce67de91` · `e334bf6c1` · `2f84bf743`
  (content-verified on origin/main, 3 paths). The next sweep ran the corpus at 21:56:12Z —
  475 suites at `2f84bf7437fb` — the first corpus since 11:35Z.
  - **Root cause.** From 11:35Z every sweep logged `corpus SKIPPED — pre-corpus whole-tree lint(s)
    already red`, so **no GREEN stamp could exist at all**, deploy-live fell back to its degraded
    age-authorised path, and the bisect elected innocent lands as culprits (backlog `354c73ebd400`).
    The single finding was `ship-land.sh:3680 BRANCH — assigned inside a $( ) child`, chained to
    write_decision_packet ":584 assigns BRANCH". Line 584 is `ID="$id" BRANCH="$branch" … python3`
    — a command-PREFIX env assignment, which bash discards after the command returns (MEASURED for
    an external command AND for a function: `f(){ :; }; V=inside f` leaves V unset). It assigns no
    global; the trap's BRANCH was never stale. The lint's prescribed remedy — "return through a
    global out-parameter" — would have introduced the very global the lint exists to forbid.
  - **The brief's premise was refuted by measurement, twice.** `ladder UNPROVEN for
    tests/autonomy-sweep.bats — our own 5400s bound fired` preceded 16 cuts, but retry_once has
    TWO bounds (FILE_TO=300s per named test · RETRY_TO=5400s whole-file fallback), rc 124 is
    identical from either, and the message named RETRY_TO unconditionally. **A 5400s bound cannot
    fire in the runs that logged it — `run_s=3364` and `run_s=3538`.** The suite is not slow: at
    the ladder's exact band (`nice -n 5`, `taskpolicy -c utility`) it measures **77.09s /
    55-of-55** in-worktree and **69.79s / 55-of-55 in a PRISTINE detached worktree at origin/main
    under live contention**, slowest case 4159ms. A whole session was dispatched against a
    90-minute suite that does not exist. The bound is now an out-parameter named per leg, with one
    test per leg (anchor-checked: both fail against the pre-fix line, pass after).
  - **Also on the critical path:** `--mutants` scored the detector BLIND for obeying its own
    contract — its picker chooses a global the trap READS, while the detector also requires a
    DESTRUCTIVE use — making tests/subshell-cleanup-lint.bats a permanent red the corpus could
    never clear. The lint now arbitrates its own case through `--loose`; blind 2 → 0, testable
    10 → 11.
  - **Learning (generalisable).** A guessed figure in a cut message is not cosmetic — it is the
    rung the next reader stands on, and here it set an entire wave's brief. Ask WHOSE bound fired
    before sizing it (memory: *exoneration-bound-must-fit-what-it-bounds*,
    *repeat-verdict-indicts-the-diagnosis*). And a lint whose prescribed remedy manufactures its
    own defect class is worse than a silent one.
- **2026-08-16 ~20:30Z — W-P1 returns collected; convergence is the last gate; S3 fired.**
  S1 COMPLETE: C1 `46a86deb7` (re-land retry runs TRUNK's pipeline via throwaway origin/main
  worktree — extract-to-temp and checkout-into-tree both proven unworkable), C2 `944abba49`
  (cc-discover screens plan-open candidates through plan-phase-scan --falsify pre-mint,
  fail-open), C3 `672f34757` (done-with-empty-evidence warns, `verdict=done-without-evidence`);
  7 regression cases red→green; conservation 0 filed / 1 closed.
  S2 COMPLETE with BOTH production proofs: premise pass beat
  `premise_rows_validated:138, closed:5` — first non-zero in its production history (root cause
  refuted the brief: the pass runs at UTILITY, and 'unparsed' was `_die_open` exiting 0 with
  `verdict=unknown` on stdout); dispatcher no-reclaim proven on two consecutive LIVE passes,
  zero claim→release on the 3 wedged ids, "refusing to fire" lines gone (works while live layer
  is stale because `blocked` is a STORE state). The two content-holding worktrees are BLOCKED
  with exact salvage commands (row `925d843f6665`); wt-c07fb00eb9b6 was ff'd + fired in prod.
  R2 T1 LANDED `a87f32c66` — the SIGTERM-143 land killer was cc-reaper's garbage arm (land path
  not whitelisted + a vacuous `^bash$` kill-time re-check defeated by 41-min PID wraps), 39×
  reaper-shadow correlation on lands. **T1 also REFUTED the lead's postland hypothesis**: the
  postland cuts are 21 reaper / 17 sig9 / 18 machine-pressure / 35 unnamed / **16 = postland's
  OWN 5400s ladder bound firing on tests/autonomy-sweep.bats re-runs — including the last 5
  consecutive cuts**. That ONE suite-vs-bound mismatch is now the sole gate on convergence
  (live layer 25+ behind, every fix above landed-but-not-live). → **S3 fired** (pane 111,
  branch fix/postland-ladder-bound): reproduce the ladder's exact re-run, name the tail cases,
  fix by mechanism, prove one REAL postland verdict + a deploy-live advance.
  R2 T2 in flight: `1817ca740` (40416-1) + `b4d0a3d0f` (64880-1) landed, 7 branches to go.
  Custody: this cwd holds only fire-r2-recovery open; ~10 stale `cloud-session_*` debts from
  the dispatcher's old cwd are A2 evidence (cloud sessions that never returned) — cloud-lane
  cleanup item, not this session's.

- **2026-08-16 ~09:30Z — waves fired.** W-P1/S1 (inflow C1+C2+C3) → pane 105, branch
  fix/backlog-inflow-c123; W-P1/S2 (C4 premise-pass + A1 dispatcher un-wedge) → pane 104, branch
  fix/backlog-machinery-c4a1; W-R2 (recovery) → pane 106, branch fix/backlog-recovery-r2. All
  next3, goals armed+verified, notify-back custody to pane 102 (lead). First fire attempt was
  REFUSED by the capacity gate at 2.12/core — the fleet's load is system indexing + daemon
  fork-storms, and the wedged dispatcher is part of it; admitted at 1.94-1.99/core.
- **2026-08-16 — W-R1 lead ops done:** stale-claim `reap` ran (0 reopened — the one dead-PID
  claim 1d25b0e07668 is venue=cloud, so host-local oracles correctly decline it; lapses on lease
  TTL). b59eb997d035 re-asserted done with CORRECTED evidence (the case is not "gone" — it lives
  rewritten at tests/test-hermeticity-lint.bats:151 citing the row; substance stood, prose was
  false). **A3 done:** `cc-venue run --apply` over all 269 open rows — **10 cloud / 259 local**
  (160 ineligible-box · 23 spawn-rail · 22 branch-banking · 18 offbox-lane · 17 visual ·
  12 deep-history · 5 premise-suspect · 1 github · 1 premise-superseded). The cloud lane's real
  slice of TODAY'S pile is 10 rows (3.7%), not the planning-era 8-14%: Lane B is the drain.
- **2026-08-16 — stranded-work enumeration complete** (9th forensics agent): 543
  refs/land/failed pins → 333 landed-by-content · 131 REAL-UNLANDED collapsing to **7 fire
  branches** · 79 ambig. **12 claude/fire-* branches carry ~2,000 genuinely-unlanded lines**;
  5 of them have NO protecting row; 14 blocked rows guard already-landed content; 1
  false-retraction (93323-1: rows auto-closed on a retraction a LATER amend invalidated).
  Live bleed: every retry dies uniformly `SIGTERM-143` (fresh pins 08:35-08:55Z today) —
  hypothesis: bin/cc-reaper's orphan-bash arm (ppid-1 bash ≥600s off-whitelist) kills detached
  lands that take 20-80 min. W-R2's T1 verifies against the reaper log before fixing.

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

#### A2 forensics 2026-08-17 — the return path is NOT the blocker; the LAND is (W-P2/S4)

**The premise this session was fired on is refuted, and the refutation is the finding.** The
brief read *"every daemon poll abstains"* and posed the question as a daemon-environment defect
— keychain unreadable from launchd, PATH/python3 divergence, config-dir resolution. All three
are false, and the ledger the brief quoted is what falsifies them:

| Hypothesis | Discriminating measurement | Verdict |
|---|---|---|
| the daemon's env cannot read the control plane | a probe launchd job with the sweep's OWN `ProgramArguments` (`/bin/zsh -lc`, `ProcessType Background`, same PATH export) ran the exact `cloud-create-api.py --account next4 --verify …` call: **rc=0**, `{"worker_status":"idle"}` | **REFUTED** |
| the login keychain locks under launchd | `security show-keychain-info login.keychain-db` → **`no-timeout`** — it never auto-locks | **REFUTED** |
| every poll abstains | `return.jsonl` by hour: 2026-08-17T00 = **109 real rows vs 6 abstains**; T05 = 73 vs 0; T06 = 14 vs 13. Abstains and real reads **interleave inside the same hour** | **REFUTED** — the brief sampled one abstain burst at the file's tail |
| the abstain bursts are a box-wide network loss | the two abstain classes (`control plane unreadable` / `state UNKNOWN` = `ls-remote failed`) occur in **disjoint minutes**, never the same pass | **REFUTED** |

What the bursts *are* stays open, and is now self-naming rather than re-derivable: 13 abstains
spanned ≤2 s ⇒ **~0.11 s each against a measured 0.52 s for a real API round trip**, i.e. an
instant local failure, hitting all four accounts at once and self-clearing by the next pass.
That is as far as history can be read, because the sensor recorded no cause — which is A2's
first fix and is landed (below).

**What actually blocks A2: 39 sessions are stuck in LAND REFUSAL, re-refused every pass.** The
sweep reads the control plane, computes RETURN-READY, calls the lander, and the lander says no —
which is why ~10 custody debts sit open for days (custody stays OPEN on an unlanded result *by
design*) and why `land-refused` is the ledger's dominant outcome (102 rows in one hour). The 39
artifacts classify into four causes, and **none is a cloud-return defect**:

| n | rc | cause | owner |
|---|---|---|---|
| 15 | 65 | the cloud branch is **CHECKED OUT in a stale worktree** (e.g. `/private/tmp/wt-land-31568-1`) — cloud-reconcile refuses to force, correctly | **A1** (reap the stale `wt-land-*` worktrees) |
| 18 | 70 | **rebase CONFLICT** on a plan doc the VM edited days ago (e.g. `BACKLOG_SELF_DRAINING_2026-08-12.md`) | **W3** refusal routing — a genuine conflict a VM must resolve |
| 5 | 70 | `mktemp: mkstemp failed on …/postland-run.VRdnYH/…` — the re-author step inherited a **TMPDIR pointing at a reaped postland-verify scratch dir**, so `cloud-reconcile.sh:424` could not compose the rewritten messages | a real, separate bug: the re-author must not trust an inherited TMPDIR |
| 1 | 143 | killed from outside — already handled as a non-verdict | — |

**Then the instrument fired, and both remaining causes named themselves within the hour.**

**(1) The abstain is an EXPIRED OAuth ACCESS TOKEN on one account — not the daemon's
environment.** The first live abstain after the fix landed, verbatim from `return.jsonl`:

```json
{"ts":"2026-08-17T07:58:12Z","id":"session_018in35KSYj7iLV7jZCNuCnj","outcome":"abstain",
 "why":"control plane unreadable",
 "err":"cloud-create-api: HTTP 401 from /v1/code/sessions/session_018in35KSYj7iLV7jZCNuCnj
        {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",
        \"message\":\"OAuth access token has expired. Re-authenticate to continue.\"}}",
 "rc":"4","account":"next"}
```

Discriminator, same call, same second, four accounts: **`next` → 401; `next2`/`next3`/`next4` →
404** (authenticated, and correctly reporting a session that is not theirs). So this is one
account's token, not a daemon-environment property — which is what every earlier hypothesis had
assumed. It also explains the bursty, all-account, self-clearing history: **the cloud lane's
token is refreshed only when a LOCAL Claude Code session on that account happens to take a turn**,
so an account whose session sits idle starves the cloud reads until something wakes it.
`cc-relogin next` REFUSES, and the refusal is principled — `next` has a live session, and a
relogin that rotates the token out from under a running CC has its rotation discarded, which *is*
a logout. Filed for the operator as `8636b8f829fe`, together with the second-order gap it exposes:
**cc-relogin's health gate keys on the LOGIN deadline (319 h away ⇒ "healthy") and is blind to an
expired ACCESS token**, so the board will keep prescribing "no re-auth needed" while every cloud
read 401s. **A2 is therefore blocked on exactly one named thing**, and the ledger says so itself
rather than needing this analysis re-derived.

**(2) The pass writing to the live store was never the daemon — it was postland-verify's
throwaway worktree.** Caught in the act at 2026-08-17T07:56Z, holding the live `.return.lock`:

```
RUNNING: /Users/chrisren/.claude/autonomy/postland/wt-run-61088/scripts/cloud-return.sh
```

The gate meant to stop exactly this read `case "$0" in "$_cc_cfg"/*`. postland-verify mints its
worktrees **under the config dir** (`$_cc_cfg/autonomy/postland/wt-run-NNNNN/`), so a verifier
copy's `$0` matches that prefix just as well as the deployed copy's does — the discriminator could
not discriminate, and **every postland run of this suite has been landing branches, closing backlog
rows and spending quota against live state.** This is the *same* incident the guard's own comment
records from 2026-08-11 (four concurrent passes out of `wt-run-54668`); it was never actually
closed, because the guard written to close it tested a prefix that contains its own harness
(memory: `guard-refusal-fires-on-its-own-harness`).

Three previously-loose facts collapse into this one cause: the refusal artifacts dying on
`mkstemp … postland-run.VRdnYH/…` (a verifier's private TMPDIR, reaped when its run ended); the
**absence of any `cloud-return` row in the sweep's own IDL journal** while `return.jsonl` filled up;
and the bursty, non-300s cadence of the ledger. The arm that should have caught it was a **grep for
`case "$0" in` over the source text**, which stayed green the whole time — text cannot show which
paths a pattern admits. The gate is now an exact-path comparison, and the behavioural arm runs the
real script from both locations with a recording stub plus a positive control.

**Landed this session** (`54aa27cd6`, content-verified on `origin/main`): the abstain row now
names its cause. `worker_status()` ran the status bin under `2>/dev/null` and folded every
failure into rc 2, so **384 rows read exactly `{"why":"control plane unreadable"}`** and could
not tell rc 127 (no python3) from rc 3 (a locked keychain) from rc 1 (an expired grant) — three
unrelated repairs. Capturing stderr alone would have changed nothing: the caller wrote
`ws="$(worker_status …)"`, a command substitution, so any global the sensor set died with that
subshell. The answer therefore moved to `WS_STATUS` and the sensor is now called **bare**, which
is what makes `WS_ERR`/`WS_RC` reachable at all. Rows carry `err`, `rc` and `account`; two bats
arms pin it, both verified to fail against the pre-fix artifact replayed from git.

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

### §4.1 Lane B recycle-fire template (SSOT — the drain session regenerates its per-recycle brief from THIS)

Fire command (from any claude-infrastructure checkout; the drain session runs this ON ITSELF at
every pause-point — end of effort, ~60% context fill, or any natural seam):

    bash scripts/handoff-fire.sh --recycle --prompt-file /tmp/fire-drain-recycle<N>.txt \
      --account auto \
      --goal '<effort E> reaches 0 open rows (blocked tail reported, not hidden) — proven by
      cc-backlog list --open --json | jq output printed showing 0 open for condition <E>, plus the
      filed-vs-closed tally for this recycle (closed >= filed); then recycle #<N+1> is FIRED
      (handoff-fire --recycle) as the LAST action and its engagement line is printed; do not end
      the recycle net-positive on filings and do not close any row without same-moment content
      evidence'

Brief body invariants (regenerate the specifics each recycle; never drop these):
1. Pick the smallest live master-* effort from the CURRENT fold (never a remembered order);
   claim its CONDITION (one lease covers the group).
2. Per row: run the stored falsifier against a pristine origin/main worktree FIRST (exit 0 =
   retracting → close on that evidence); re-measure dated titles; landedness by CONTENT.
3. Close line format: `<effort>: N open / M blocked (K operator-gated)` — a zero without its
   blocked tail is the exact defect that produced this plan (§1.1).
4. Conservation: close ≥ file, printed in the close.
5. Operator-gated rows: platter via the cc-do/operator-readout rail, never burn turns on them.
6. THE CHAIN IS THE DELIVERABLE: firing recycle #N+1 (or, at true zero live rows, writing the
   chain-complete entry in this plan) outranks finishing one more row. A recycle that runs out
   of context mid-effort still fires its successor with the effort in-flight.

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
