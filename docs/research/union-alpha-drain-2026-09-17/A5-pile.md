# A5 — What is actually IN the backlog pile, and is any of it a job for a free, tool-less LLM?

Snapshot: `~/.claude/autonomy/backlog.jsonl`, **21,025 events · 3,582 ids · 0 parse failures**, read
2026-09-16 23:38 PDT / 2026-09-17T04:40Z. Fold taken from the tool itself (`cc-backlog list --all
--json`), never re-derived — `bin/cc-backlog:6400` documents that a hand-rolled fold over `$g[-1]`
mis-reads 53 rows. Store was READ-ONLY throughout: no `add`, `claim`, `block`, `falsify`, `link` or
`done` was issued. The only commands executed against the world were seven **existing** falsifier
probes (all pure `grep`/`test`/`awk` reads) and three read-only reporters (`cc-backlog dups`,
`cc-premise coverage`, `cc-do --list`).

---

## VERDICT

**No. There is no free-model-shaped job in the blocked pile, and the reason is structural rather
than a matter of degree.**

Three independent facts each settle it on their own:

1. **The pile is not text awaiting processing; it is 207 operator-only steps awaiting a human.**
   `source == "needs"` on **207 of 308 blocked rows (67%)**. `cc-backlog needs` exists *by
   definition* to file a step the agent cannot take — credential, sudo, GUI, physical, or a value
   call. A further 228 of 308 (74%) already carry the condition slug `master-operator-gated`. The
   classification job the brief hypothesises is **already done, mechanically, continuously** — 759
   link events to that one slug, the most recent at 2026-09-17T04:00Z, still arriving hourly.

2. **The whole input fits in one context window, so there is no volume to rent capacity for.**
   Every blocked row's title + needs text is **294,882 chars ≈ 74K tokens**. The entire live pile
   (346 rows, all fields) is **321,650 chars ≈ 80K tokens**. A week of free capacity is being
   proposed for a corpus that one ordinary Opus call reads in a single pass with 90% of its window
   to spare. This is the counter-case's hardest number and nothing in §4 survives it.

3. **The machine has already refused the best candidate job in writing, with a stated reason.**
   `bin/cc-premise` `cmd_coverage` docstring, verbatim: *"live = open OR claimed (**blocked rows
   excluded — they are not in the wave**), minus `source=="needs"`, whose `--run` **PERFORMS the
   operator step it would be probing and so has no machine oracle by design**."* "Draft falsifier
   commands for the blocked pile" is not an unbuilt feature. It is a deliberately-declined one.

**The one candidate that does survive, and it is not the pile:** a **false-closure audit of the
3,236 `done` rows' `evidence` strings** — 3,263,235 chars ≈ **816K tokens**, the only corpus here
too large for one window, with a known-positive base rate (the 2026-09-16 audit measured *21 of 29*
cloud closures citing evidence about a branch their session never touched) and a **cheap mechanical
verifier** (each flagged row names a sha/branch; `git merge-base --is-ancestor` settles it in one
call). Its payoff is the thing that is actually scarce: reopened rows are genuine drainable work,
and the drainable queue today is **29 rows**, not 47. See §4.1.

**And the correction the brief needs:** the drainable queue is not 47 and not even 37.
`cc-dispatch:1921` filters on `status=="open"` **and** membership in
`scripts/dispatch-projects.conf` `{claude-infrastructure, doc_classifier, reso-management-app}`.
Eight of the 37 open rows (6 `sevenrooms-bridge`, 1 `personal`, 1 `voiceink`) are outside that set
and are structurally undrainable too. **True drainable queue = 29, of which 28 are
`claude-infrastructure`.**

---

## 1 · Census — confirm/correct the 296/47 split

| | audit (2026-09-16 11:49) | now (2026-09-17T04:40Z) | Δ |
|---|---|---|---|
| events | 20,528 | **21,025** | +497 |
| ids | 3,525 | **3,582** | +57 |
| live (non-done) | 343 | **346** | +3 |
| `blocked` | 296 | **308** | **+12** |
| `open` | 47 | **37** | **−10** |
| `claimed` | (in the 47) | 1 | — |
| `done` | — | 3,236 | — |
| **drainable after project filter** | (not computed) | **29** | — |

**The split is confirmed and has worsened in ~17 hours.** Blocked +12, open −10. The audit's
finding that blocked enters 3.6× faster than it leaves (6.77/d in, 1.87/d out) is reproduced on a
same-day interval. `blocked` is at a new all-time high of 308.

### Live rows by project

| project | live | open | blocked | in dispatch set |
|---|---|---|---|---|
| claude-infrastructure | 196 | 28 | 167 | ✅ |
| reso-management-app | 82 | 1 | 81 | ✅ |
| personal | 37 | 1 | 36 | ❌ |
| sevenrooms-bridge | 11 | 6 | 5 | ❌ |
| doc_classifier | 9 | 0 | 9 | ✅ |
| reso *(alias)* | 5 | 0 | 5 | ❌ (conf: "NOT a project — an ALIAS") |
| voiceink | 4 | 1 | 3 | ❌ |
| lakehouse-lecture | 1 | 0 | 1 | ❌ |
| reso-web-app | 1 | 0 | 1 | ❌ |

### Age

| status | n | age med / p90 / max (days) | days since last touch: med / p90 / max |
|---|---|---|---|
| blocked | 308 | **24 / 40 / 59** | **11 / 32 / 35** |
| open | 37 | 4 / 24 / 26 | 0 / 22 / 24 |
| claimed | 1 | 5 | 0 |

Bucketed blocked age: 0–7 d = 64 · 7–30 d = 135 · **30–60 d = 109**. A third of the pile is over a
month old, against the FILED rule's own p90-of-9.3-days rot standard.

---

## 2 · The blocked pile — why each row is blocked

### 2a. The four-class `--why-not-now` schema is essentially unused

| field | blocked rows carrying it | % |
|---|---|---|
| `needs` (free text) | 308 | 100% |
| `whyNotNow` (the four-class field) | **22** | **7.1%** |
| `run` (exact operator command) | 142 | 46.1% |
| `falsifier` | 22 | 7.1% |
| `dodRef` | 43 | 14.0% |
| `conviction` | 20 | 6.5% |

Of the 22 `whyNotNow` values: **21 `needs-human`, 1 `not-yet-true`, 0 `needs-credential`,
0 `no-capacity`.** **305 of 308 `needs` strings carry no class prefix at all** (3 do:
`decide:` ×2, `sevenrooms-bridge:` ×1). The schema the CLAUDE.md FILED rule mandates is carried by
7% of the pile — the gate is enforced at `cc-backlog add --why-not-now`, and 67% of the pile
arrived through `cc-backlog needs`, which does not take that flag.

### 2b. But the pile IS classified — by condition slug, not by `whyNotNow`

| condition (blocked rows only) | n | % of 308 |
|---|---|---|
| **`master-operator-gated`** | **228** | **74.0%** |
| `master-product-repos` | 18 | 5.8% |
| `master-account-facts` | 13 | 4.2% |
| `master-enforcing-store` | 6 | 1.9% |
| `master-stranded-work` / `-fleet-footprint` / `-fire-gate` / `-convergence-deadlock` | 4 each = 16 | 5.2% |
| 13 singleton slugs | 13 | 4.2% |
| **(none)** | **14** | 4.5% |

**95.5% of blocked rows are already grouped.** 759 `link` events point at
`master-operator-gated` alone (228 blocked + 468 done + 1 open), and they are still arriving — 4 in
the hour 2026-09-17T00, 4 at T01, 2 at T02, 2 at T03, 1 at T04. This is live, continuous machinery,
not a stale one-off.

### 2c. By actual blocker — non-exclusive regex tallies over `needs`

| blocker | n | can a tool-less LLM supply it? |
|---|---|---|
| operator ruling / value call / policy fork | **128** | **No** — it is the operator's preference |
| migration / activation flip / `--force` | 41 | **No** — self-modification, agent-refused by 3 arms |
| credential / auth / token / login | 38 | **No** |
| send/communicate to a third party (customer, vendor, support) | 32 | **No** — needs the operator's identity |
| external precondition ("after X lands", "until then") | 23 | **No** — needs the world to change |
| physical / GUI gesture (drag, ⌘⇧B, iPhone, by eye) | 17 | **No** |
| sudo / root | 5 | **No** |
| *no regex hit* | 108 | see below |

First-match-priority collapse: operator ruling 100 · credential 36 · physical 17 · migration 16 ·
precondition 14 · third-party 12 · sudo 5 · **unmatched 108**.

The 108 unmatched are **not** a residue of legible agent work. Reading them: *answer the permission
prompt hanging pane 616* · *apply the 6 harvested allow rules in
`proposal-20260913T091825Z.json`* · *open stalled cloud session `session_01M676…` in the browser* ·
*restart fseventsd (7.04 GB resident)* · *schedule a reboot of this Mac* · *land the 2 unpushed
commits in the SHARED checkout*. These are **operator ACTIONS without a decision word in them** —
the regex missed the class, not the class the agent could take.

**Answer to the question as posed:** ~**128 blocked on a human decision**, ~**156 blocked on a human
ACTION** (credential · sudo · GUI · migration · third-party send · permission prompt · reboot),
~**23 on an external precondition**, ~**0 blocked on nothing legible.** Every one of the 308 has a
legible blocker; what almost none of them has is a *machine-answerable* one.

### 2d. The "orphan" 14 — the rows with no condition at all

These are the strongest test of "blocked on nothing legible", and they fail it hardest. All 14 are
personal-life or lead-reply items: book apartment #348 at The Goodwin (needs a payment card) ·
phone Ahmed about the room · call Vista Real leasing about a U-Box in the lot · request binding
quotes from Sherpa + Ship a Car Direct · confirm Cox StraightUp is ordered · ask Narek and Emilia
for receipt amounts · cable the iPhone 16e to the Mac and tick *Encrypt local backup* · enable Text
Message Forwarding (six-digit code) · revoke corporate apps under Local Network on the work phone ·
ask KPMG HR which office · **reply to Zayden Path's Instagram DM with the `join.reso.gl` overview
link for the Evolve Nanaimo owner**. That last one is stranded customer-lead value; none of the 14
is text work.

---

## 3 · Falsifiability — how much is dead weight a script should clear?

**22 of 308 blocked rows (7.1%) carry a falsifier.** I re-ran the seven that are pure read
(`grep`/`test`/`awk`, no mutation) plus the six `plan-phase-scan.sh --falsify` arms:

```
exit!0 still-live  ecde9a7f8f62   exit!0 still-live  eed2530a4165
exit!0 still-live  ee1ac85c6ff6   exit!0 still-live  7b762bcbbe11
exit!0 still-live  a9dc3cf6cc2b   exit!0 still-live  159c2211b0f2
exit!0 still-live  6a428f48fd2e
plan-scan CLOUD_OBSERVABILITY / DESK_ROUTER_AND_STARTUP_V1 / MASTER_ACCOUNT_FACTS /
          MASTER_PRODUCT_REPOS / MULTI_PROVIDER_PLANS / START_LATENCY_ROUTER  =>  '' (all)
```

**0 of 13 retract.** Not one probe-carrying row is currently dead weight.

That is not luck, and it is the finding that closes the "a script should be clearing this" theory:

- `cc-backlog falsify` **runs the probe before storing it** and **refuses (rc 5) any probe that
  exits 0 against a live row** — exit 0 is the retracting direction. A stale probe cannot be filed.
- `cc-premise sweep --record --close-falsified ${CC_PREMISE_CLOSE_CAP:-25}` is wired into
  `scripts/autonomy-sweep.sh:1490` and runs on the sweep schedule. **The auto-retraction script
  already exists and already runs**, capped at 25 re-probes per pass.
- It works: **190 `done` rows cite `auto-retracted`** in their evidence. Retraction-shaped
  closures all-time: `retract*` 667 · `already` 680 · `REFUTED` 291 · `moot` 185 · `superseded` 159
  · `no longer` 150 (overlapping sets, of 3,236 done).

**And the coverage gap is a design decision, not a hole.** `cc-premise coverage --json`, run live:

```json
{"probeable": 28, "covered": 19, "uncovered": 9, "coverage_pct": 67.9,
 "by_arm": {"stored": 11, "derived-plan": 0, "derived-postland": 8, "none": 9}}
```

`probeable` is **28**, not 308, because the population is defined (`bin/cc-premise` `cmd_coverage`)
as *open OR claimed, blocked excluded, minus `source=="needs"`* — with the reason quoted in §VERDICT
point 3. **The machine does not consider the blocked pile probe-capable, on purpose, because a
`needs` row's `--run` performs the very step a probe would test.**

Staleness language *is* present in the pile — `already` ×55, `MET` ×26, `RE-MEASURED` ×17,
`CORRECTED` ×13, `REFUTED` ×10, `no longer` ×10, `is GONE` ×5, `superseded` ×5 — but reading them
shows the sessions **already did the re-measurement and edited the row in place** ("RE-MEASURED
2026-08-18 and the urgency is GONE **while the decision remains**"). The rows narrate their own
decay correction and stay blocked because the *decision* survived the correction.

**Duplicates: essentially none.** `cc-backlog dups --mode all`: `dodref` 0 groups · `mechanical`
0 groups · `title` **1** group · `family` **1** group — both the same `re-land <branch>` family.
IDs are content-hash keyed (`project+title+source`), so `add` is idempotent **by construction** and
the pile cannot accumulate textual duplicates. **The "dedupe/cluster 3,525 ids" job has nothing to
find.**

### 3a. Fifteen verbatim rows

*(full `needs` text, unedited; `run` and `falsifier` as stored)*

### `b448ceafa0ca` · **blocked** · claude-infrastructure · filed 2026-08-11 · src=`needs` · cond=`master-operator-gated`
- **title:** Activate the interactive account router: claude1 pins account 1, bare claude auto-routes. C10 — edits ~/.zshrc and flips accounts.json's launcher field (both together, with backups); an agent may not self-activate a launcher/shell change. The script refuses until ~/.claude/lib/claude-launcher.zsh is live, which the 600s converger does automatically.
- **needs:** OPERATOR (C10: edits ~/.zshrc AND flips accounts.json's launcher field, together) — activate the interactive account router: claude1 pins account 1, bare claude auto-routes. An agent may not self-activate a launcher/shell change: handoff-fire.sh resolves accounts[N].launcher and TYPES IT INTO A PANE, so the two surfaces must move together or sessions mis-route. Run: CONFIRM=1 bash ~/.claude/docs/activation/pending-activation/36-start-latency-router-activate.sh — it takes backups of both and refuses until ~/.claude/lib/claude-launcher.zsh is live, which the 600s converger does automatically. (Folds in duplicate row 7903c1f92b76, which named this same single gate. This is also the decision plan rows 180d38b29912 (its 'D-A') and 48e14163e78a are waiting on — answering it here answers them.)
- **run:** CONFIRM=1 bash ~/.claude/docs/activation/pending-activation/36-start-latency-router-activate.sh
- **falsifier:** (none)

### `1d11d3104208` · **blocked** · reso-management-app · filed 2026-08-17 · src=`session cc-005315-12167` · cond=`master-operator-gated`
- **title:** DECISION (operator): should the Add-mode guest autosuggest keep replaying PER-NIGHT facts? A suggestion inserts the full composed entry incl. +N (feeds tonight's capacity count) and the note (e.g. 'NC Until 12' — a cover policy granted on a specific night), so accepting last week's entry carries both into tonight. Visible before submit (row text, then styled field), so reflex risk not silent. Alternative: insert the NAME only and let tonight's numbers be typed fresh. Shipped as full-replay in 3fa9455a3; agent leans keep. Failure mode to watch: a comped guest nobody comped.
- **needs:** Your product call: should the Add-mode guest autosuggest keep replaying PER-NIGHT facts (a suggestion inserts the whole composed entry, +N included)? Both behaviours are buildable; which one is right is a judgement about how door staff read a suggestion, not something the code can settle.
- **run:** (none)
- **falsifier:** (none)

### `e4ac885e05c8` · **blocked** · reso-management-app · filed 2026-08-31 · src=`3bf610a6-d353-4dbc-9866-de981373544f` · cond=`master-operator-gated`
- **title:** Apple Developer Program enrolment ($99/yr) + Pass Type ID certificate — gates W4, the Apple Wallet pass layer that the research names THE state layer
- **needs:** Enrol in the Apple Developer Program at https://developer.apple.com/programs/enroll/ — $99/yr, INDIVIDUAL path needs no D-U-N-S and no legal entity, no App Store review and no discretionary entitlement. Then create a Pass Type ID certificate (self-service). This unblocks W4, the Apple Wallet pass layer, which the research names THE reservation state layer and which needs NO carrier registration — so it is independent of the $1400 10DLC decision (6e6572554001) and is the cheaper path to a working guest channel. Note for the build: Apple requires the signing private key NOT live on the Amplify/Fly web tier, and a lapsed Pass Type ID cert silently breaks pass updates, so it needs an expiry alarm.
- **run:** (none)
- **falsifier:** (none)

### `719058e957e0` · **blocked** · reso-management-app · filed 2026-08-28 · src=`needs` · cond=`master-operator-gated`
- **title:** Classify the Denver source maps' black ink, per room: which black is ARCHITECTURE and which is PAGE FURNITURE (legend cards, inset diagrams, logos, the printed page frame), which gaps in The Church's east wall are real openings vs the legend card printed over the wall, and whether each black slab is a wall, a bar counter, a riser or a stage. scripts/checks/wall-trace-audit.py finds the ink but CANNOT classify it — all four are drawn in the same black — and neither can an agent without inventing an answer. Blocks the four confident wall-trace defects (Church main: envelope following the legend card's border down the right side and along the bottom, ring 8 of 'Interior Walls' at 1457,1915 and 1475,1932; a duplicate wall inside the stage-24 enclosure; an invented rect over the stair run. Church balcony: a second rectangle at the document boundary, 25.4% of its trace ink). Open the six overlay PNGs and answer per room; the Vinyl rooftop at 0.0% invented is the shape of a clean answer.
- **needs:** Classify the Denver source maps' black ink, per room: which black is ARCHITECTURE and which is PAGE FURNITURE (legend cards, inset diagrams, logos, the printed page frame), which gaps in The Church's east wall are real openings vs the legend card printed over the wall, and whether each black slab is a wall, a bar counter, a riser or a stage. scripts/checks/wall-trace-audit.py finds the ink but CANNOT classify it — all four are drawn in the same black — and neither can an agent without inventing an answer. Blocks the four confident wall-trace defects (Church main: envelope following the legend card's border down the right side and along the bottom, ring 8 of 'Interior Walls' at 1457,1915 and 1475,1932; a duplicate wall inside the stage-24 enclosure; an invented rect over the stair run. Church balcony: a second rectangle at the document boundary, 25.4% of its trace ink). Open the six overlay PNGs and answer per room; the Vinyl rooftop at 0.0% invented is the shape of a clean answer.
- **run:** (none)
- **falsifier:** (none)

### `c523bfc68ed9` · **blocked** · reso-management-app · filed 2026-08-14 · src=`needs` · cond=`-`
- **title:** reply to Zayden Path (Instagram DM) with the join.reso.gl overview link — he asked 2026-08-13 'send a link to an overview so the owner can see all the functionalities' for the Evolve Nanaimo owner; draft + full thread context in memory project-zayden-evolve-nanaimo-outreach.md
- **needs:** reply to Zayden Path (Instagram DM) with the join.reso.gl overview link — he asked 2026-08-13 'send a link to an overview so the owner can see all the functionalities' for the Evolve Nanaimo owner; draft + full thread context in memory project-zayden-evolve-nanaimo-outreach.md
- **run:** (none)
- **falsifier:** (none)

### `d29e0d9dd4cb` · **blocked** · reso-management-app · filed 2026-08-21 · src=`needs` · cond=`master-operator-gated`
- **title:** Ask Turso support (or Glauber directly): on Scaler with overages enabled, does creating a 7th GROUP hard-refuse or bill as overage, and at what per-unit rate? Separately: do AWS-hosted groups count toward the groups/locations quota, and do Scaler AWS groups still lack SCHEMA DATABASES (the parent-schema model reso uses on all three Fly groups)? Blocks nothing today — reso is at 4 of 6 — but decides the cost shape of every future region.
- **needs:** Ask Turso support (or Glauber directly): on Scaler with overages enabled, does creating a 7th GROUP hard-refuse or bill as overage, and at what per-unit rate? Separately: do AWS-hosted groups count toward the groups/locations quota, and do Scaler AWS groups still lack SCHEMA DATABASES (the parent-schema model reso uses on all three Fly groups)? Blocks nothing today — reso is at 4 of 6 — but decides the cost shape of every future region.
- **run:** (none)
- **falsifier:** (none)

### `a1c97626d34c` · **blocked** · reso-management-app · filed 2026-08-22 · src=`AXIS-4 gate-coverage-inverted (floor-plan audit 2026-08-21), harvested via R-30` · cond=`master-operator-gated`
- **title:** AXIS-4 B6: a floor-plan render defect is not a distinguishable signal — no metric filter keys on $.route="floor-plan". BITTEN: the incident that motivated the module. Fix: 1 metric filter + 1 count alarm. WARNING: quota is 92/100, check first
- **needs:** May I emit ONE synthetic floor-plan render defect in production to prove the beacon chain reaches CloudWatch before an alarm is built on it? Measured us-west-2 /aws/amplify/djnbdqpvc08g4 on 2026-09-04: quota is fine (87 metric filters, not the 92 the row recorded; 13 slots left) and no floor-plan filter exists, so the premise holds. But two things block a mechanical fix. (1) The row's prescribed pattern is wrong: { $.route = "floor-plan" } matches 13 events in 14 days and they are doc-metrics ssr_timing PAGE RENDERS, not defects — that filter would count healthy traffic. The correct pattern is { $.namespace = "error-tracking" && $.route = "floor-plan" }, the four fields lib/floor-plan/reportRenderDefect.ts says CloudWatch keys on. (2) That correct pattern matches ZERO events in 14 days, and from outside I cannot tell 'no defects occurred' from 'the beacon never reaches the log group' — so building the alarm now ships an instrument nobody can prove fires. One synthetic defect settles it; that is a production emission and therefore yours.
- **run:** (none)
- **falsifier:** (none)

### `8c7ebcb056b0` · **blocked** · sevenrooms-bridge · filed 2026-09-12 · src=`(unset)` · cond=`master-operator-gated`
- **title:** deploy to the Lambda — this one ACTIVATES the Mansion 11 PM grant (bbad312) as well as the placeholder-note fix (5b8187e). After it runs, a reso-website sign-up at Mansion is written 'comp til 11' instead of 'comp til 10:30'. Twelve West is unchanged at '10:30'.
- **needs:** this deploy changes what guests are promised at the door, so it is a policy go-ahead rather than a code gate — and deploy.sh also converges the DynamoDB-stream event-source mapping, which should not run during service. Conviction 88 that the change itself is right (docs/NOTES_CONVENTION.md § 2026-09-12); the remaining call is whether you want the extra 30 minutes given away at all.
- **run:** cd ~/Development/sevenrooms-bridge && bash scripts/deploy.sh && bash scripts/preflight-golive.sh
- **falsifier:** both doors closed (after ~03:00 PDT) AND the operator has said go

### `f55f56e4d651` · **blocked** · reso-management-app · filed 2026-09-14 · src=`(unset)` · cond=`deploy-next-security-patch`
- **title:** Deploy the next 16.3.x security patch to production
- **needs:** Run the production deploy AFTER the next 16.3.x security patch lands on origin/main (check: git show origin/main:package.json | grep '"next"' reads 16.3.3 or higher). Command: bash scripts/deploy-release.sh — or /deploy in a session. Operator-only: it spends a real Amplify + Fly deploy and advances production while door staff may be mid-shift. Until it runs, 8 live tenants keep serving next 16.3.0, inside the affected range of two CRITICAL unauthenticated RCE advisories (GHSA-2xp9-vwfh-vxw4 Image Optimization, GHSA-p293-qw3h-jr36).
- **run:** bash scripts/deploy-release.sh
- **falsifier:** (none)

### `95ea18ea9ac0` · **blocked** · personal · filed 2026-08-16 · src=`needs` · cond=`-`
- **title:** iPhone 16e: cable to Mac, Finder > Back up all data to this Mac, TICK 'Encrypt local backup', record password. Closes the 2024-12 to 2026-08 message gap (~20 months). Runbook: ~/Development/personal/iphone-messages-mcp-setup.md 'Closing the gap'
- **needs:** iPhone 16e: cable to Mac, Finder > Back up all data to this Mac, TICK 'Encrypt local backup', record password. Closes the 2024-12 to 2026-08 message gap (~20 months). Runbook: ~/Development/personal/iphone-messages-mcp-setup.md 'Closing the gap'
- **run:** (none)
- **falsifier:** (none)

### `1a003703bc19` · **blocked** · personal · filed 2026-08-16 · src=`b249924c-ae78-46aa-a7fd-7c81e79d4e28` · cond=`-`
- **title:** CALL Ahmed (Manor) — private bedroom now vacant, HE initiated; establish pets/duration/rent
- **needs:** Phone call to Ahmed (not text): 1) does he have pets? 2) is he after a long-term roommate or short-term company? 3) offer rent unprompted, name ~$600-800 4) how long is he good for
- **run:** (none)
- **falsifier:** (none)

### `5cb75cf245f1` · **blocked** · claude-infrastructure · filed 2026-08-10 · src=`needs` · cond=`master-convergence-deadlock`
- **title:** Delete 3 spent raw-ff scripts from the LIVE ~/.claude layer (C10 — unversioned, unreachable from the repo, so no land can fix them). All three raw-ff the shared checkout, which .claude/commands/ship.md:112 forbids: DEPLOY-crash-diagnostics.sh:9 (pull --ff-only; one-shot for ef7f7a4, now an ancestor of trunk = spent), DEPLOY-DESK-RECYCLE-FIX.sh:56 (merge --ff-only; one-shot for 2ebab2b, likewise spent), DEPLOY-NOW.sh.pre-ssot.bak:35 (install.sh's backup of the pre-SSOT real file; scripts/deploy-now.sh is the SSOT and is now a gated front-end). Named as the C10 half of backlog c50158434c7a, whose repo half landed. Agent cannot do this: deleting live-layer files in place is C10-forbidden.
- **needs:** OPERATOR (deletes 3 files from the LIVE ~/.claude layer) — and the safety case is now COMPLETE, so this is a one-second call. RE-VERIFIED 2026-08-18: all three files are still present (DEPLOY-crash-diagnostics.sh, DEPLOY-DESK-RECYCLE-FIX.sh, DEPLOY-NOW.sh.pre-ssot.bak); both one-shot targets are SPENT — `git merge-base --is-ancestor` confirms ef7f7a4 and 2ebab2b are both ancestors of origin/main; and a tree-wide grep across the repo, ~/.claude/hooks, ~/.claude/scripts and ~/.claude/bin finds ZERO remaining references to any of the three names. They are unversioned and unreachable from the repo, so no land can remove them. All three raw-ff the shared checkout, which .claude/commands/ship.md:112 forbids. Run: rm -i ~/.claude/DEPLOY-crash-diagnostics.sh ~/.claude/DEPLOY-DESK-RECYCLE-FIX.sh ~/.claude/DEPLOY-NOW.sh.pre-ssot.bak
- **run:** rm -i ~/.claude/DEPLOY-crash-diagnostics.sh ~/.claude/DEPLOY-DESK-RECYCLE-FIX.sh ~/.claude/DEPLOY-NOW.sh.pre-ssot.bak
- **falsifier:** (none)

### `eed2530a4165` · **blocked** · claude-infrastructure · filed 2026-08-11 · src=`(unset)` · cond=`wtgc-landed-dirt-flip`
- **title:** FLIP WTGC_DISPOSE_LANDED_DIRT=1 once the nightly log has shown the landed-dirt class. Shipped OFF deliberately in 9f0e637b: 32 candidates existed at land time, the janitor had never printed the class once, and the first ON night would reap all 32 before anyone read a line of evidence. Nothing about the predicate is unproven — it asks per-dirty-path ls-tree blob identity against trunk, any uncertainty KEEPS, it uses NO --force (it restores the proven-redundant paths and requires the tree to come out clean, so git's own refusal survives as the last gate), and every liveness/ownership rung still runs ahead of it. This is a timing hold, not a safety hold. FALSIFIER, run it and read the DIRT? block: bash scripts/worktree-gc.sh --dry-run 2>&1 | grep -A1 '^DIRT?' — each candidate now names the gitignored content a disposal would destroy (measured 12/12 carry some: node_modules/, .claude-tasks/, .ruff_cache/, __pycache__/ — all regenerable). Flip by exporting WTGC_DISPOSE_LANDED_DIRT=1 for scripts/worktree-gc-infra-run.sh (env or the launchd plist). Cannot go inert: the class is classified, counted and blast-radius-reported on every nightly run whether or not the switch is on.
- **needs:** Arm the worktree janitor's landed-dirt disposal, or leave it off. The timing precondition you set is MET: the nightly log prints the class on every run (4 runs, all landed_dirt=0; newest 2026-09-04 04:15 'dirt=0 rc=0'), so the 32-candidate blind first night that held it back cannot happen — armed today it would reap nothing. It stays yours only because arming it lets an unattended nightly DELETE worktrees. CORRECTS the --run filed minutes earlier, which named a variable that does not exist: the real line is scripts/worktree-gc-infra-run.sh:418 DISPOSE_LANDED_DIRT="${WTGC_DISPOSE_LANDED_DIRT:-0}".
- **run:** python3 -c "import pathlib; p=pathlib.Path.home()/'Development/claude-infrastructure/scripts/worktree-gc-infra-run.sh'; s=p.read_text(); n=s.replace('WTGC_DISPOSE_LANDED_DIRT:-0','WTGC_DISPOSE_LANDED_DIRT:-1'); assert s!=n, 'anchor not found'; p.write_text(n); print('armed')"
- **falsifier:** grep -q "WTGC_DISPOSE_LANDED_DIRT:-1" scripts/worktree-gc-infra-run.sh || grep -rq WTGC_DISPOSE_LANDED_DIRT launchd/

### `f36bc0986c43` · **blocked** · claude-infrastructure · filed 2026-08-24 · src=`needs` · cond=`master-operator-gated`
- **title:** Cloud session session_01M676dQtsFjboT9vTPFL3Mt (account next2) is STALLED — its branch ref has been frozen at 8b1230dd2 for 63+ min. Open it in the browser to see whether it is alive; if it is dead, close it there, then run 'bash bin/cc-backlog unblock 01ab05685857' locally. Only the browser step is yours — nothing local can close an off-box session. WHY IT MATTERS: 01ab05685857 (postland-verify inert) is what deploy-live waits on, so this stall is the head of the live-layer convergence blockage — four consecutive drain recycles have now closed on a 🚀 they could not clear. DO NOT let the branch be deleted: 8b1230dd2 ('fix(nightly): step 5 read a cut stamp as proof the net was alive', touching scripts/nightly-regression.sh + tests/deploy-live.bats) is NOT an ancestor of origin/main — it is real unlanded work.
- **needs:** Cloud session session_01M676dQtsFjboT9vTPFL3Mt (account next2) is STALLED — its branch ref has been frozen at 8b1230dd2 for 63+ min. Open it in the browser to see whether it is alive; if it is dead, close it there, then run 'bash bin/cc-backlog unblock 01ab05685857' locally. Only the browser step is yours — nothing local can close an off-box session. WHY IT MATTERS: 01ab05685857 (postland-verify inert) is what deploy-live waits on, so this stall is the head of the live-layer convergence blockage — four consecutive drain recycles have now closed on a 🚀 they could not clear. DO NOT let the branch be deleted: 8b1230dd2 ('fix(nightly): step 5 read a cut stamp as proof the net was alive', touching scripts/nightly-regression.sh + tests/deploy-live.bats) is NOT an ancestor of origin/main — it is real unlanded work.
- **run:** open https://claude.ai/code/session_01M676dQtsFjboT9vTPFL3Mt
- **falsifier:** (none)

### `cc48801002bf` · **blocked** · reso-management-app · filed 2026-08-03 · src=`needs` · cond=`master-operator-gated`
- **title:** Approve the history-rewrite tool in Bash permissions — the rewrite step is blocked by the auto-mode classifier on every form tried. Prepared workspace staged at /Users/chrisren/Development/.reso-rewrite-scratch/
- **needs:** Approve the history-rewrite tool in Bash permissions — the rewrite step is blocked by the auto-mode classifier on every form tried. Prepared workspace staged at /Users/chrisren/Development/.reso-rewrite-scratch/
- **run:** (none)
- **falsifier:** (none)


---

## 4 · The free-model-shaped question, candidate by candidate

| # | candidate job | input | verifiable cheaply? | what it unlocks | verdict |
|---|---|---|---|---|---|
| A | **Dedupe / cluster 3,582 ids** | 1.68 MB titles ≈ 420K tok | yes (id set diff) | — | **DEAD.** `dups` finds 2 groups total; ids are content-hash keyed so duplicates cannot accumulate. |
| B | **Classify blocked reasons** | 295 KB ≈ 74K tok | yes (label set) | — | **ALREADY DONE.** 294/308 carry a condition slug; 228 carry `master-operator-gated`; 759 link events, still arriving hourly. |
| C | **Draft falsifier commands** | 295 KB ≈ 74K tok | **yes** — `cc-backlog falsify` runs and refuses exit-0 probes | ~0 rows | **REFUSED BY DESIGN.** `cmd_coverage`: a `needs` row's `--run` performs the step a probe would test ⇒ "no machine oracle by design". 0 of 13 live probes retract today. |
| D | **Detect stale rows** | 295 KB ≈ 74K tok | no — staleness is a claim about the world, not the text | ~0 | **DEAD.** Rows already narrate their own re-measurement; `cc-premise sweep --close-falsified 25` is the wired mechanical arm. |
| E | **Summarise into a triage table** | 295 KB ≈ 74K tok | no (judgment) | operator minutes | **ALREADY RENDERED.** `cc-do --list` = `3 runnable · 349 judgment`, 500 lines, already grouped RUN / YOURS-decisions / YOURS-blocked with every command inline. A second renderer is the exact defect CLAUDE.md § Relay-never-paraphrase bans. |
| F | **Fill in the 31 decision packets missing conviction + receipt** | 43 packets, tiny | no | 43 rulings | **DEAD.** 12 of 43 open packets carry `conviction`+`receipt`; supplying them requires *measurement*, and `cc-decide open --class C` refuses a packet whose options are not measured. A tool-less model can only speculate, which is what the gate exists to reject. |
| **G** | **False-closure audit of `done` evidence** | **3.26 MB ≈ 816K tok** — the only input exceeding one window | **YES** — flagged rows name a sha/branch; `git merge-base --is-ancestor <sha> origin/main` settles each in one call | **reopened rows = genuine drainable work**, against a drainable queue of 29 | **THE ONLY LIVE CANDIDATE.** |

### 4.1 Candidate G, stated properly

- **Input.** 3,180 of 3,236 `done` rows carry an `evidence` string (median 289 chars, p90 1,205,
  max 8,207). Total 3,263,235 chars ≈ **816K tokens** — shardable into ~8 × 100K passes, which is
  the only shape in this whole store that a week of rented capacity is even the right unit for.
- **Known-positive base rate.** The 2026-09-16 audit already measured **21 of 29** cloud-lane
  closures citing evidence about a branch their session never touched, and **47.2% of closure
  volume mechanically not-delivered**. The defect exists at scale and has never been swept
  whole-store.
- **Output is a triage list, not a mutation.** The model emits `id → the sha/branch/file its
  evidence asserts → the claim type`. Nothing is written to the store by the model.
- **The verifier is one command per flagged row** and it fails closed: a sha that is not an
  ancestor of `origin/main` did not land, whatever the evidence says. This is the same test
  CLAUDE.md § S5 already mandates before citing a sha in a close.
- **What it unlocks.** Every confirmed false closure is a row that should be `reopen`ed — and a
  reopened row lands in `status=="open"`, which is the *only* status either drain lane can see.
  Against a drainable queue of **29**, a sweep that recovers even 50 real rows **triples the
  addressable work** — and unlike the blocked pile, those rows are agent-doable by construction,
  because they were filed as agent work in the first place.

**Caveat, and it is not small.** G refills the queue with more `claude-infrastructure` self-work
(§6), because that is what the done corpus is 70% made of. It fixes the *supply* of drainable rows;
it does nothing for the *mix*.

---

## 5 · The counter-case, argued as hard as I can

**The pile's problem is not a lack of text processing. It is a lack of a human.** Six proofs, each
a quote or a number from the store:

1. **207 of 308 blocked rows were filed by the one verb that means "I cannot do this."**
   `source == "needs"`. `cc-backlog needs` is documented as the operator-only gate. There is no
   reading of those 207 rows under which a model supplies the missing thing.

2. **113 of the 228 operator-gated rows already carry the exact command.** They are not
   under-specified; they are un-run. `cc-do --list` renders three of them as `RUN` today:

   ```
   cc-do — 3 runnable · 349 judgment
     RUN  1. deploy-live            [live layer 1 behind origin/main]
            bash /Users/chrisren/.claude/scripts/deploy-live.sh
     RUN  2. 43-autonomy-sweep-band-activate [activation]
            CONFIRM=1 bash /Users/chrisren/.claude/autonomy/pending-activation/43-autonomy-sweep-band-activate.sh
     RUN  3. 42-postgresql14-activate [activation]
            bash /Users/chrisren/.claude/autonomy/pending-activation/42-postgresql14-activate.sh
     YOURS   41 open decision(s)    cc-decide list --open
     YOURS   308 blocked backlog    cc-backlog list --blocked
   ```

   A better-worded backlog does not move that `3 · 349` ratio by one.

3. **The customer repo's blocked pile is 100% value calls and vendor asks.** `reso-management-app`,
   81 blocked, and the texture is: *"Your product call: should the Add-mode guest autosuggest keep
   replaying PER-NIGHT facts?"* · *"Decide which Harbour menu the app should seed"* · *"Enrol in the
   Apple Developer Program … $99/yr"* · *"Ask Turso support (or Glauber directly): on Scaler with
   overages enabled, does creating a 7th GROUP hard-refuse or bill as overage?"* · *"May I emit ONE
   synthetic floor-plan render defect in production…?"* · *"Grant the tenant-drift GitHub OIDC role
   `ssm:GetParameter`…"* · *"Approve the history-rewrite tool in Bash permissions."* Not one is text
   work. Several cost money. Several are irreversible production writes.

4. **The single most text-shaped row in the pile is still not a text job.** `719058e957e0`:
   *"Classify the Denver source maps' black ink, per room: which black is ARCHITECTURE and which is
   PAGE FURNITURE (legend cards, inset diagrams, logos, the printed page frame)…"* — a
   classification task in name, but the subject is **ink on a scanned drawing**. It needs eyes on an
   image and it is explicitly reserved as the operator's ruling (`docs/floor-plan/open.md:1166`:
   *"Do not trace anything at this layer until he rules"*).

5. **Where the machine did try bulk unblocking, it produced churn, not closure.** 776 `unblock`
   events, and **every single one records no reason** (`why`/`reason`/`note` absent on all 776).
   328 are by `cc-backlog-reap` — mechanical, not judgment. **372 ids have been blocked more than
   once; 174 have been blocked three or more times.** Re-adjudicating these rows in bulk is a thing
   this system has already done at volume, and its measured output is a row that gets re-blocked.

6. **The mission board proves the constraint is upstream of the backlog entirely.** Five customer
   deliverables are stale 9–20 days, and **not one of them is an open backlog row.** Their blockers,
   in their own words, are: *"BLOCKED ON THE OPERATOR, one field only: … which guestlist link +
   access info is his to supply"* (Church bottle-menu), *"OPEN IT AND RULE; nothing else blocks this
   row"* (balcony floor-plan), and *"it needs the operator to name who to ask at The Key
   Collection"* (live fleet bottle-menu). **Three of the five highest-value items on this machine
   are each blocked on one sentence from one human.** A week of free model capacity buys zero of
   those sentences.

**Where the counter-case is weakest, stated honestly.** It is a claim about *the pile*, not about
*free capacity*. Candidate G lives outside the pile and survives every argument above, because it
audits what the machine already *claimed to have finished* rather than what it is waiting on. If the
operator wants the capacity spent, G is where it goes — and the case for G is that its input is
816K tokens, which is the only number in this document that a rented week is the right unit for.

---

## 6 · Open-queue quality — deliverables vs. the machine working on itself

All 38 non-done, non-blocked rows, classified by title generator:

| class | n | share | in dispatch set |
|---|---|---|---|
| `re-land <branch>: ship-land could not complete` | **10** (9 open + 1 claimed) | 26% | all ✅ |
| `post-land RED` / `post-deploy HOST RED` / `AUTO-REVERT FAILED` | **10** | 26% | all ✅ |
| kitty terminal chrome (title band, drag, SIGSEGV) | 3 | 8% | ✅ |
| `advance <plan>` (DRAIN CIRCUIT, Non-limit resume) | 2 | 5% | ✅ |
| other `claude-infrastructure` self-tooling (cc-await-ping, handoff-fire gates, upgrade-gate hardcodes, Fable 5.1 pricing, ProposeGoal flag) | 5 | 13% | ✅ |
| **`sevenrooms-bridge`** (CI never runs tests, sidecar restarts, preflight flakes, DOOR telemetry) | **6** | 16% | ❌ **out of dispatch set** |
| `voiceink` (dictation readout) | 1 | 3% | ❌ |
| `personal` (cc-await-ping misattribution) | 1 | 3% | ❌ |
| **`reso-management-app`** — *BytePlus ModelArk US-territory subscription: ask sales whether a US entity can hold one* | **1** | 3% | ✅ |

**30 of 38 (79%) are `claude-infrastructure`, and 23 of 38 (61%) were minted by the machine's own
land/test machinery about itself** (`re-land` + `post-land RED` + kitty). The audit's finding that
*31 of 47 open rows (66%) are that class* is **confirmed and slightly worse** at 61% of a smaller,
more concentrated queue.

**Exactly one open row touches a paying customer's product, and it is a question for a vendor's
sales team** (`a8f3c6eaa960`, filed 2026-08-27, 21 days old, and it self-released with
`releaseReason: "spawn-fail"` at 2026-09-17T04:35Z — it has been picked up and dropped).

### September closure mix — cross-check of the audit's 74%

| project | Sept closures | share |
|---|---|---|
| **claude-infrastructure** | **679** | **76.5%** |
| reso-management-app | 146 | 16.4% |
| reso (alias) | 20 | 2.3% |
| personal | 18 | 2.0% |
| sevenrooms-bridge | 8 | 0.9% |
| doc_classifier | 4 | 0.5% |
| all others (10 labels, incl. 6 `.desk-land-…` garbage project labels) | 13 | 1.5% |
| **total** | **888** | |

**Confirmed, and drifting the wrong way**: the audit measured 73.9% of 882 on 2026-09-16 11:49;
17 hours later it is **76.5% of 888**. All-time: 2,267 of 3,236 done rows (70.1%) are
`claude-infrastructure`.

---

## 7 · Blockers and uncertainties in this analysis

- **`whyNotNow` counts are a floor, not a measure of intent.** 67% of the pile arrived via
  `cc-backlog needs`, which takes no `--why-not-now` flag, so the 7.1% coverage figure measures a
  *producer mismatch*, not 286 authors skipping a required field.
- **My §2c regex tallies are heuristic.** 108 rows matched no pattern; I read a sample of 12 and
  classified them as operator ACTIONS, but I did not hand-read all 108. The direction is safe (they
  are *more* operator-bound than the regex saw, not less) but the per-class split ±15.
- **I ran only 13 of 22 falsifiers** — the 9 skipped were not provably side-effect-free
  (`bats` invocations, `git for-each-ref` loops, an AWS `alarms.sh --verify`). "0 of 13 retract" is
  the honest statement; 0 of 22 is not established.
- **Candidate G's yield is unestimated.** I have the 21/29 cloud base rate from the prior audit and
  the 3,180-row corpus size, but no sample of the general `done` population's evidence quality. The
  "even 50 rows" figure in §4.1 is an illustration, not a measurement. **This is the one number
  that should be pilot-measured before any capacity is committed** — one 100K-token shard, verified
  with `git merge-base`, gives the real rate in under an hour.
- **`personal` and `sevenrooms-bridge` are undrainable for a reason I did not investigate.** They
  are simply absent from `dispatch-projects.conf`, which lists explicit `skip=` reasons for other
  labels but no row at all for these two. Whether that is deliberate or an omission is unresolved,
  and 6 `sevenrooms-bridge` open rows (including *"CI never runs the test suite: 618 tests gate
  nothing and trunk went red unnoticed"*) are stranded by it.
