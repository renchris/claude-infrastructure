---
status: open
---

# ACCOUNT/QUOTA ROUTING & RELOGIN — V2 (ground-up rebuild, row 7)

**Scope (frozen):** zero work stranded by a login cliff, and routing decisions read LIVE quota
rather than a remembered one — under the standing constraint that cliffs are hard walls and the
4 accounts are isolated from each other. Measured, landed, and verified by disk-truth acceptance
reads.

Methodology: the `ground-up` skill. Exemplars read first: `LAND_PIPELINE_V2.md` (row 1),
`SESSION_LIFECYCLE_V2.md` (row 2 — the cell-falsification shape).

**Prior row-7 docs this INTEGRATES with, never replaces:** `RELOGIN_AUTOMATION_PLAN.md`
(the 2026-07-24..26 build + its post-mortems), `RELOGIN_BUILD_CONTRACT.md` (the frozen
`cc-relogin` CLI contract), `docs/runbooks/RELOGIN_ACTIVATION.md`.

---

## Phase 0 — orchestration

**Solo, not an Agent Team — deliberately.** The rebuild's whole content is a *seam* between four
functions in ONE file (`bin/claude-accounts`: `_excluded` / `score_general` / `score_fable` /
`ranked`) plus two small consumers. Disjoint file ownership — the precondition that makes a
teammate wave pay — does not exist here: every mechanism below writes the same 40-line region of
the same file. Splitting it would manufacture the same-hunk conflict the worktree rule exists to
avoid. (The session was also instructed not to spawn subagents; Phase 1's decisions were taken
from first-hand reads, which the skill prescribes for load-bearing calls regardless.)

Build order = land order, one atomic land per mechanism, continuously:
M1 → M2 → M3 → M4 → map row. Each land is gate-green before the next begins.

---

## §1 Phase 1 — the standing-constraint cell, RE-DERIVED

**Cell as inherited:** *"login cliffs are hard walls; 4 isolated accounts."*

**Verdict: CONFIRMED — and sharpened.** This is the campaign's first row whose cell survived
contact with primary disk truth. It is also *insufficient as stated*, in the row-10 shape: both
halves are true, and neither expresses the property that actually decides whether work gets
stranded. The rename is at the end of this section.

The anchor I was told to re-verify rather than inherit (memory
`reference-claude-accounts-tooling`: `refreshTokenExpiresAt` anchors to the last INTERACTIVE
`/login` and no token refresh extends it) is **TRUE**, proven twice from two independent primary
sources. I did not quote the memory; both proofs are below and both are reproducible.

### Proof 1 — cross-sectional, from the credential store (macOS Keychain)

Read directly from each account's keychain item
(`Claude Code-credentials-<sha256(NFC(config_dir))[:8]>`, account `chrisren`), metadata only.
Design of the test: *if a refresh extended the refresh-token lifetime, then accounts whose
access tokens were minted at about the same time would carry refresh-token expiries at about the
same time.* All four accounts were holding freshly-granted access tokens:

| account | access `expiresAt` | LOGIN `refreshTokenExpiresAt` | T− |
|---|---|---|---|
| next  | 2026-07-30T06:53:44Z | **2026-08-02T20:21:49Z** | **+90.30 h = 3.76 d** |
| next4 | 2026-07-30T09:46:58Z | 2026-08-23T20:24:13Z | +594.34 h = 24.76 d |
| next3 | 2026-07-30T09:14:57Z | 2026-08-24T02:22:06Z | +600.30 h = 25.01 d |
| next2 | 2026-07-30T08:38:32Z | 2026-08-25T03:20:31Z | +625.28 h = 26.05 d |

- access-expiry spread across the four: **0.120 d (2.9 h)** — every account had refreshed recently.
- login-expiry spread across the four: **22.291 d**.

A refresh that reset the refresh-token clock would collapse the second spread to approximately
the first. It is **186× wider**. ⇒ the refresh does not reset the wall.

A second, independent signal in the same payloads: the **millisecond component of `expiresAt`
and `refreshTokenExpiresAt` is identical per account** (next `…364`/`…364`, next4 `…518`/`…518`,
next3 `…092`/`…092`, next2 `…648`/`…648`). Both fields are therefore computed from ONE
`Date.now()` at the grant — i.e. the server returns `refresh_token_expires_in` as a **countdown
toward a fixed absolute wall**, re-expressed at every refresh rather than reset by it. Four of
four matching by chance is ~1e-12.

### Proof 2 — longitudinal, from the heal log (`~/.claude/logs/claude-accounts.log`)

51 heal events, 2026-07-13 .. 07-28. `next3`'s history is decisive:

```
OK   2026-07-19T08:19   OK 2026-07-19T16:31   OK 2026-07-20T00:38
OK   2026-07-22T21:46   OK 2026-07-23T06:11   OK 2026-07-23T14:27
FAIL-BURST n=24  2026-07-24T17:29 → 07-25T01:11  (7.7 h)
   reasons = ['Login failed: Request failed with status code …', 'timeout of 30000ms …']
OK   2026-07-28T14:59        ← 93.5 h after the burst began
```

**Six successful refresh grants (Jul 19–23) did not move next3's wall; the refresh token died on
Jul 24 anyway.** If each refresh had reset a ~30-day lifetime, next3 would have been good until
~Aug 22. Recovery required an interactive login: 24 automated re-attempts inside 7.7 h all failed,
and the account was unusable for **93.5 hours**.

Caveat stated honestly: this log records only heals that `claude-accounts` itself performed — the
`claude` binary's own in-session refreshes never appear here. That weakens nothing above (the six
logged OKs provably happened), but it means log *gaps* are not evidence of no refresh.

### What the cell gets right, and the one thing it does not say

- "hard wall" — **right, and stronger than 'hard'.** Past the stamp, every refresh grant returns
  `invalid_grant` by construction; `bin/claude-accounts:28` already documents that the heal is
  skipped rather than burned. Nothing automated recovers it.
- "4 isolated accounts" — **right, and it is the asset, not just the constraint.** Isolation is
  what makes a cliff survivable: 3 accounts carry load while the 4th is quiesced.
- **What it omits, and what actually decides the outcome: the cliff is a KNOWN ABSOLUTE
  TIMESTAMP already sitting in the credential store, ~30 days per account, at a per-account
  phase.** A cliff is not a random event to be defended against; it is a *scheduled maintenance
  date the system can already read*. Every hour of the 30 days is available to prepare, and the
  system uses none of them.

**Renamed cell:** *"a login cliff is a scheduled, already-readable per-account deadline — so the
only failure is failing to ACT on a date the system already holds; and because 4 accounts are
isolated, acting is always affordable."*

### The falsified inherited claim this exposes

`docs/plans/RELOGIN_AUTOMATION_PLAN.md:266` states: *"The cliff is closed until roughly
2026-08-23 — which is the next natural window to prove cc-relogin against, with no deadline
pressure."* **FALSIFIED.** `next` — the operator's #1 spend-priority account
(`accounts.json:_order`) — cliffs **2026-08-02T20:21:49Z**, three weeks earlier than the plan
says, and it is the NEAREST cliff of the four. The prior session generalized from next3 and next4
("both carrying refresh-token expiries ~28 days out"), and the surface it checked
(`--login-status`, exit 0) is filtered at 72 h, so next's then-8-day-out cliff was invisible to
it. The same filter defect described in §5/M2 produced a wrong verdict for a *human* session, not
just for the poller. **The next natural window to prove `cc-relogin` against is not Aug 23 — it is
`next` in under 4 days.**

---

## §2 Measured constants (every row re-derived from primary disk truth, 2026-07-30)

| # | Constant | Value | Source |
|---|---|---|---|
| C1 | login-cliff period | ~30 d/account, bounded **[26.1, 30.0] d** | keychain stamps vs the login window bracketed by `claude-accounts.log` (next3 login ∈ [07-25T01:11, 07-28T14:59], cliff 08-24T02:22) |
| C2 | access-expiry spread, 4 accounts | 0.120 d | keychain `expiresAt` |
| C3 | login-expiry spread, 4 accounts | 22.291 d | keychain `refreshTokenExpiresAt` |
| C4 | `next` cliff (nearest) | 2026-08-02T20:21:49Z = **T−90.30 h** | keychain |
| C5 | next4 / next3 / next2 cliffs | T−594.34 h / T−600.30 h / T−625.28 h | keychain |
| C6 | live sessions `k` per account | next **6** · next4 **6** · next3 **5** · next2 **6** (min 5) | `claude-accounts --no-heal --json` |
| C7 | `cc-relogin`'s precondition | `k == 0` exactly (`k != 0` ⇒ `EXIT_REFUSED`) | `bin/cc-relogin:563-565` |
| C8 | accounts satisfying C7 right now | **0 of 4** | C6 ∧ C7 |
| C9 | measured cliff outage | **93.5 h** (07-24T17:29 → 07-28T14:59) | `claude-accounts.log` |
| C10 | doomed refresh retries inside it | **24 in 7.7 h** | same |
| C11 | successful refreshes that did NOT move next3's wall | **6** | same |
| C12 | `login_warn_h` — the `--login-status` filter | **72.0 h** | `accounts.json:login_warn_h`; applied `bin/claude-accounts:1697,1700` |
| C13 | poller trigger / escalation | **T−7 d (168 h)** / **T−48 h** | `bin/cc-relogin-poll:52`; `bin/claude-accounts:1515-1516` |
| C14 | **fraction of the poller's declared window it cannot see** | **96 h of 168 h = 57.1 %** | C12 vs C13 |
| C15 | `cc-relogin-poll` log lines, all-time | **2**, both 2026-07-26, both `nothing due` | `~/.claude/logs/cc-relogin-poll.log` |
| C16 | `com.claude.relogin` in launchd | **not loaded**; no plist in `~/Library/LaunchAgents`; label **absent** from `launchd/fleet.manifest` (0 hits; positive control `postland` = 3) | `launchctl list`; `ls`; `grep` |
| C17 | login-cliff references in the ROUTING path (`_excluded`/`score_general`/`score_fable`/`ranked`) | **0** (positive control: same region references `session_pct` 2×) | `bin/claude-accounts:762-832` |
| C18 | `route.jsonl` records | 252 (232 plan · 16 cliff-stop · 2 cliff-kimi-offer · 2 refused); fields **`ts,slot,outcome,detail` only** | `~/.claude/route/route.jsonl`; `bin/cc-route:67-71` |
| C19 | quota-percentage **denominator** | **server-side** — `limits[].percent` off `oauth/usage`; no local cap constant exists | `bin/claude-accounts:452-458` (`pick`) |
| C20 | remembered quota in routing | **structurally barred** — every `inherit_lastgood` path leaves `row["error"]`, and `_excluded()` bails on `error` first | `bin/claude-accounts:462-470, 763-764` |
| C21 | routing quota freshness | cache TTL **90 s**; **600 s** grace only on the lock-contention degrade path; `--fresh` never degrades | `accounts.json:cache_ttl_s,cache_grace_s` |
| C22 | `login_expires_at` in the durable ledger | **ABSENT for 4 of 4 accounts** (ledger carries only quota) | `~/.claude/logs/claude-accounts-lastgood.json` |
| C23 | deploy lag, shared checkout | **0** (`HEAD..origin/main`) at 2026-07-30T02:0xZ — the sawtooth was collapsed | `git rev-list --count HEAD..origin/main` |
| C24 | my `bin/` artifacts' deploy mode | **symlinks** into the checkout ⇒ **landing == deploying** | `readlink ~/.claude/bin/{claude-accounts,cc-route,cc-relogin}` |
| C25 | `model-config.yaml` deploy mode | live `~/.claude/model-config.yaml` is a **REAL FILE**, not a symlink; repo SSOT is `templates/model-config.yaml`; currently **byte-identical** (`cmp` clean) | `ls -l`; `cmp` |
| C26 | `login_expires_h` staleness | **cannot go stale from cache** — re-derived from the absolute stamp after every `get_data()` | `bin/claude-accounts:1059-1082` (`refresh_login_countdown`) |

**Denominator discipline (the harness trap, discharged).** Every ratio this row consumes is named
here with its denominator: `session_pct`/`weekly_pct`/`fable_pct` are the **server's own
percentages** off `limits[].percent` (C19) — the denominator is the plan's limit, held
server-side, and no local constant divides anything, so the row-8 hardcoded-1M-window failure
mode is structurally absent. `login_expires_h` is a **countdown**, and its durable form
`login_expires_at` is an **absolute stamp** that is re-derived rather than served from cache
(C26) — so this row's one time-ratio has a recorded denominator (the wall-clock stamp) by
construction. `*_reset_h` are likewise derived from stored absolute `*_reset_at` stamps
(`bin/claude-accounts:669-671` and the comment above them). **The one ratio with NO durable
denominator is C22's absence** — see M3.

---

## §3 Phase 1 — branch-graveyard sweep

Run for row 7's own paths, **with a positive control asserted before believing any negative**
(the coordinator's pointer named artifacts for rows 2, 6, 8, 9, 10, 11 and explicitly *none* for
row 7, flagged as known-incomplete rather than evidence).

- **Positive control PASSED.** `git log --all --oneline --diff-filter=A -- bin/cc-route` →
  `e2742035`; `git log --oneline --all -- launchd/staged/com.claude.relogin.plist` → `8a1e49ab`
  + siblings. The sweep re-finds files known to exist, so its negatives are meaningful.
- **Result: NOTHING TO TAKE.** Commits touching row-7 paths and NOT on `origin/main`:
  `fix/infra-perfection` **0** · `tm/gates` **0** · `tm/hygiene` **0** · `preland-backup-infra`
  **0** · `tm/growth` **1**.
- The four 55-ahead branches are *behind* on row 7, not ahead: `origin/main..fix/infra-perfection`
  shows `D bin/cc-relogin`, `D bin/cc-relogin-poll`, `D commands/relogin.md`,
  `D docs/plans/RELOGIN_AUTOMATION_PLAN.md` — taking from them would **delete** the subsystem.
  This is the inverse of row 12's find, and only running the sweep distinguishes the two.
- `tm/growth`'s single hit is `64fd57b0 fix(docs): mark the 16 pane-id hits the live-corpus
  assertion reaches` — **row 2's** pane-id documentation, matched only because it touches a file
  under a shared test glob. **REJECTED on merits:** not account-routing work. (The dispatch brief
  independently bars taking from `tm/growth`.)
- **Verdict:** the coordinator's "none for row 7" pointer is **correct**, now verified rather
  than inherited.

---

## §4 Phase 2 — INVARIANTS vs ARCHITECTURE

First principles is not amnesia. Sorted from MEMORY.md + the incident docs.

### INVARIANTS (properties any design here must keep — numbered requirements)

| R | Invariant | Why (source) |
|---|---|---|
| R1 | **A cliff is a STOP, never a silent down-tier and never a blind fire.** | `bin/cc-route:30-32`; inherited unchanged. |
| R2 | **"Cannot see" ≠ "nothing to do."** Missing detection is UNKNOWN/exit 3, never OK/exit 0. | `bin/claude-accounts:1519-1523`; memory `named-failure-vs-no-verdict`. |
| R3 | **Missing data is not headroom.** A row without live quota is EXCLUDED, never routed on a remembered number. | `bin/claude-accounts:462-470`; already holds (C20) — must SURVIVE this rebuild. |
| R4 | **Credentials are never retried unattended into a wall,** and no token/credential is ever printed into a plan, a fixture, a log or a commit message. | `accounts.json:_secrets`; C10 shows what a doomed retry loop costs. |
| R5 | **Absence-is-loud requires EXISTENCE EVIDENCE.** An alarm about a producer that never ran must be gated on the producer's world existing. | memory `absence-alarm-needs-existence-evidence`. |
| R6 | **A built mechanism must be an ENFORCED mechanism that FAILS LOUD when inert.** ~100 % abstain ⇒ inert by construction. | memory `feature-durability-mechanism-not-memory`; C15/C16 are exactly this failure. |
| R7 | **Existence evidence comes from the DECLARATION, not from the subject's success.** | memory `daemon-fleet-v2`; `launchd/fleet.manifest` header. |
| R8 | **Every new mechanism ships an env kill switch** — never revert-as-plan. | `ground-up` skill Phase 3. |
| R9 | **Never widen an override to fit a category you failed to name.** A fail-closed widening must fit its population. | memory `inventory-before-building`, `third-state-skips-the-unnamed-gate`. |
| R10 | **A metric with no producer is unfalsifiable** — record the INPUTS of a decision, not only its output. | row 2's M-2; C18 is the same shape. |
| R11 | **Never turn a survivable condition into a fleet-wide STOP.** A gate whose refusal is permanent under normal load is an outage, not a safeguard. | memory `metric-zero-by-refusing-gate`, `load-is-not-a-function-of-session-count`; row 13's self-retracted ⛔. |
| R12 | **Consume other rows' mechanisms FAIL-SOFT.** Landed ≠ live; check existence evidence, never a status cell. | campaign rule; row 4's inert oracle. |

### ARCHITECTURE (the incumbent's mechanisms — inherited from nothing, kept only on merit)

**KEPT, on merit:**
- `cc-relogin`'s three non-negotiable guards — need-check, `k == 0`, the shared heal lock
  (`bin/cc-relogin:555-570`). The `k == 0` gate is **CORRECT and stays**: a running `claude`
  owns the token lifecycle and a relogin racing it has its rotation discarded. §8 rejects
  relaxing it.
- `cc-authbrowser`'s dedicated per-account Chrome profile, which made the CDP consent gate
  structurally unreachable. This is what makes unattended re-auth possible at all.
- `_excluded()` bailing on `row["error"]` first (R3, C20) — the "live quota" half of the frozen
  scope is *already* architecturally satisfied; the rebuild must not regress it.
- `refresh_login_countdown()` re-deriving the countdown from the absolute stamp (C26).
- The `staged` expect value in `launchd/fleet.manifest` — "declared, decision pending: surfaced,
  never silent" is exactly the honest state for an un-activated job.

**REJECTED as architecture (kept only as a fact to route on):** the belief that surfacing the
cliff to a human is the row's job. §5.

---

## §5 The design — THE INVERSION

> **Row 7 PRODUCES the cliff, RENDERS the cliff, and never ROUTES on it.**

Every `login_expires_*` read in `bin/claude-accounts` lives in a producer (`probe_account`), a
re-deriver (`refresh_login_countdown`), or a renderer (`render_table`, `relogin_row`,
`render_relogin_status`). The four functions that decide **which account works** —
`_excluded`, `score_general`, `score_fable`, `ranked` — do not mention it once (C17,
positive-controlled). The subsystem whose entire job is "which account works" treats the one
fact that determines whether an account will *still* work as a display string.

And the mirror: the only mechanism that ACTS on the cliff (`cc-relogin-poll` → `cc-relogin`) can
fire only at `k == 0`, and **routing is the only thing that determines `k`.** All four accounts
sit at k = 5–6 (C6/C8), so the autonomous path is **0-by-construction**: it has never once been
able to act, and 168 hourly chances at a window that never opens is still zero.

So the subsystem holds both halves of the answer and has never connected them: the fact it
refuses to route on, and the lever that fact needs. **The structural change is one sentence:
make the login cliff a first-class routing term.** That single change

1. steers new work away from an account that is about to die (**nothing stranded**), and
2. *manufactures* the `k == 0` window `cc-relogin` has never found (**the cliff becomes
   recoverable**),

because draining an account IS a routing decision. The cliff stops being a warning a human reads
and becomes a scheduling input. If the new design were the old one with bigger constants, Phase 1
would not be finished; it is not — it moves a fact across the producer/decider boundary.

### M1 — cliff-aware routing (the inversion) · `bin/claude-accounts`

Two bands, both driven by the **absolute** stamp's derived `login_expires_h`, sharing the
poller's existing constants so no new number is invented:

- **SOFT band — `login_expires_h ≤ CC_ROUTE_CLIFF_SOFT_H` (default 168 h = the poller's T−7 d,
  C13).** Multiply the account's score by `CC_ROUTE_CLIFF_SOFT_FACTOR` (default 0.25) in both
  `score_general` and `score_fable`. The account keeps serving and keeps its quota available; it
  simply loses ties. Effect: new-session inflow falls for 5 days, so `k` decays on its own
  instead of being fought at the deadline. **No capacity is discarded a week early** — that
  distinction is the whole reason this is a multiplier and not an exclusion.
- **DRAIN band — `login_expires_h ≤ CC_ROUTE_CLIFF_DRAIN_H` (default 48 h = the poller's
  escalation point, C13).** `_excluded()` returns `login-cliff-drain`. No new work is routed
  here; existing sessions finish; `k → 0`; `cc-relogin` gets its window. The drain band and the
  operator's board row now begin at **the same instant** — the operator is told at exactly the
  moment routing starts preparing.

Three properties that are the design, not decoration:

- **R11 / YIELD — never manufacture a false cliff.** `login-cliff-drain` is a *policy* reason, so
  `reason_class()` maps it to exit 2, which `cc-route` turns into `⛔ QUOTA CLIFF` exit 4
  (`bin/cc-route:163-183`) — a fleet-wide STOP consumed by row 5. But a cliff-drained account
  **still works**; refusing to route to it must never be reported as "no account has headroom".
  So `ranked()` **re-admits** the drained accounts when the cliff term is what emptied the
  candidate set, and records that it did. A drain is a preference, and preferences yield to
  necessity. Without this clause M1 would convert a survivable 4-account cliff schedule into a
  dispatch outage — row 13's exact self-retracted mistake.
- **R9 / FAIL-OPEN on absence.** `login_expires_h is None` ⇒ **no cliff term at all** for that
  row. The field is not on every build (`bin/claude-accounts:1519`), and a fail-CLOSED reading
  would exclude the entire fleet on an older binary. Absence of the cliff fact is not evidence
  of a cliff.
- **R8 / kill switch.** `CC_ROUTE_CLIFF_TERM=off` disables both bands and restores byte-identical
  prior behaviour.

### M2 — the poller's detection window must match its own policy · `bin/claude-accounts`, `bin/cc-relogin-poll`

`cc-relogin-poll:14-16` states the design decision explicitly — *"WHY T−7d, not the 72h warn:
`cc-relogin` can only act when the account has ZERO live sessions (k==0), so a login deadline is
otherwise one fragile attempt. A 7-day window turns it into ~168 hourly chances"* — and then
lines 102-119 wire detection to `--login-status`, which pre-filters at `login_warn_h = 72`
(C12). **The implementation silently reverts the decision the comment defends.** 57.1 % of the
declared window is unreachable (C14), and it is unreachable through the leg the ladder
*prefers*: the richer `json-fields` fallback, which carries every account's raw
`login_expires_h`, is only reached when the narrower leg is *absent*. The fallback is richer than
the primary.

Live proof, this minute, of two surfaces disagreeing about one fact:

```
$ claude-accounts --relogin-status   → exit 1   "next  DUE  2026-08-02T20:21:49  90  cc-relogin next"
$ claude-accounts --login-status     → exit 0   (empty)
```

**Fix:** `--login-status` accepts an explicit `--window-h N`; `cc-relogin-poll` passes its own
`TRIG_DAYS × 24`. Contract safety, all three pinned by tests:

- the **default stays 72** (`login_warn_h`), so every existing caller is byte-identical;
- exit codes **0 / 1 / 2 unchanged**;
- the TSV stays **6 fields** — `cc-relogin-poll:80` (`norm 6`) parses it positionally and an
  added column would slide `hours`/`launcher` into the wrong variables.

This also closes the human-facing half: the `RELOGIN_AUTOMATION_PLAN.md:266` verdict falsified in
§1 was produced by reading the 72 h-filtered surface and concluding "no cliff for a month".

### M3 — make the cliff DURABLE, and the routing decision FALSIFIABLE

- **(a) The cliff is only readable while the account is healthy.** `login_expires_at` exists
  nowhere durable (C22): the last-good ledger records quota and not the cliff. So at the exact
  moment an account breaks — keychain read fails, item missing, payload corrupt —
  `--relogin-status` renders **UNKNOWN** and the poller has **no deadline**, i.e. the data
  vanishes precisely when it is needed. Fix: carry `login_expires_at` (an absolute stamp, never
  the decaying `_h`) into `claude-accounts-lastgood.json` beside the quota, and have
  `inherit_lastgood` restore it. R3 is preserved exactly: an inherited cliff **does not** make a
  row routable — the row still carries `error`, so `_excluded()` still bails. It only means the
  cliff stays *visible* and the poller still has a deadline to act on.
- **(b) `route.jsonl` records the decision but none of its inputs** (C18), so "did routing read
  live quota, and did it see the cliff?" is **unanswerable from disk** — the frozen scope's
  second clause is currently unfalsifiable, which is this campaign's most-repeated defect (R10).
  Fix: `cc-route`'s `record()` gains `cliff_h`, `cliff_band` (`none|soft|drain`) and
  `quota_as_of` alongside `detail`. Additive JSONL keys — existing `jq` consumers
  (`bin/cc-route:277-296`, `tests/cc-route.bats`) select by `.outcome`/`.detail` and are
  unaffected.

### M4 — declare the poller so its inertness is LOUD (R6, R7)

`com.claude.relogin` is absent from `launchd/fleet.manifest` (C16), so row 12's fleet state
function never evaluates it: the poller can stay dark forever with **nothing saying so**. That is
R6's failure verbatim, and R7 gives the fix — existence evidence comes from the declaration.
One manifest row, using the value the manifest already defines for exactly this state:

```
com.claude.relogin | staged | 3600 | ~/.claude/logs/cc-relogin-poll.log | 7 | 20-relogin-poll-activate.sh
```

`staged` emits exactly ONE `UNDECIDED` row — "declared, decision pending: surfaced, never
silent" — not a daemon-fault row. Plus the staged activation script + runbook pointer, plattered
for the operator (C10 boundary: agents drive TO activation, never run it).

**Seam, declared not assumed:** the manifest is row 12's SSOT and its committed-manifest test
hard-codes the label count (`tests/cc-fleet.bats:535`, `[ "$n" = 21 ]`), so declaring a row
requires bumping it to 22 — which that test's own comment establishes as the convention ("the
count moves with the repair rather than the repair being hidden behind a looser count"). Row 12's
comment block also deliberately keeps two *other* staged plists out of the manifest because they
"would claim coverage that does not exist" (deathwatch has no producer; the reconciler's roster is
unwired) — **that reasoning does not apply here**: `cc-relogin-poll` has a real producer
(`cc-relogin-poll.log`) and a real declared cadence (3600 s). Row 12's LINT is untouched; only a
row is added. **Raised with the coordinator before landing** rather than decided alone.

### M5 — `/limit-recover` could not be reached by the failure it recovers · `commands/limit-recover.md`

`Scope (grown): +an auth-cliff trigger and decision branch in /limit-recover.` **Follow-On Gate
PASS** — F1 net-positive (it is the LAST stranding path left in the frozen scope: M1 stops *new* work
reaching a dying account, and nothing addressed work already in flight when the wall arrives) · F2
grounded in this session's disk read of the file (every trigger named a QUOTA event; zero auth
vocabulary) · F3 a docs edit to a command row 7 owns, no escalation surface · F4 one line plus one
section.

Every trigger in `limit-recover`'s description named a quota event — 5-hour, weekly, Fable,
monthly-spend — so a session killed by its account's **login cliff** matched none of them, while the
transplant machinery in that very file is precisely the right recovery. **The capability existed and
the failure that needed it could not reach it** — the row's own shape, one layer up.

The substantive content is ONE branch, not a synonym list: **"wait for the reset" does not exist on a
cliff.** A cap has `resets_at`; past `refreshTokenExpiresAt` every grant is refused by construction
(C9/C10/C11: six refreshes did not move the wall, 24 re-attempts failed, 93.5 h down until a human
logged in). Hence: never wait, never retry the grant · transplant is the only zero-loss path ·
`cc-relogin` runs **in parallel, not first** (it needs `k == 0`, so it cannot run while the work is
still on the account — repairing first inverts the dependency and strands the work for the whole
repair) · last healthy account ⇒ genuine STOP-ASK with a salvage bundle taken while waiting.
`~/.claude/commands/limit-recover.md` is a **symlink** into the checkout, so no activation step.

### M6 — a trunk repair, taken because it reds the gate for every lander

`Scope (grown): +declare the trunk's undeclared com.claude.scratchpad-reaper plist.` **Follow-On Gate
PASS** — F1 (both the three-way coverage lint and `tests/cc-fleet.bats` were RED on *pristine*
origin/main, blocking every land, not just mine) · F2 (all four fields read from disk: not installed,
not loaded, `StartInterval 21600`, and `auto` verified a REAL sensor because
`scripts/scratchpad-reaper.sh:157` echoes a per-run summary — unlike `com.claude.relogin`'s, which is
why that row names its per-tick log explicitly) · F3 (a manifest declaration; no activation) · F4
(one row plus the count convention this file already documents). Not row 7's artifact; repaired
rather than allowlisted, exactly as `com.claude.capacity-alarm` was two commits earlier in the same
file. `owner_row 11` is marked PROVISIONAL in the manifest — the field is routing metadata and
changes no verdict, so its real owner can correct it in isolation.

### What this design does when a dependency is DARK (R12 — fail-soft, mandatory)

| Dependency | Owner | If landed-but-inert / dark |
|---|---|---|
| `com.claude.relogin` LaunchAgent (C16) | 7 (mine), operator activates | **M1 still works alone.** Cliff-aware routing needs no daemon: it runs inside every `--route`/`--rank` call. The account is drained and protected even with zero automation running; recovery then needs one operator `cc-relogin <acct>`, plattered. M1 is deliberately the mechanism that does not depend on activation. |
| row 12's fleet alarm / `bin/cc-fleet` | 12 | M4's row goes unread — no worse than today (C16 = invisible). M1/M2/M3's acceptance reads are independent of it. |
| row 4's session-beat oracle (inert, verified) | 4 | `k` already comes from `claude-accounts`' own process attribution (`bin/claude-accounts:250`), not from the beat store. No new dependency taken. |
| row 10's board render of the `relogin-blocked` row | 10 | The escalation is *also* written to `idl.jsonl` and to `cc-relogin-poll.log`; acceptance reads target the JSONL, not the render. |
| row 5's `cc-wave-plan` (consumer of my contract) | 5 | Unchanged exit codes ⇒ nothing to degrade. M1's yield clause (R11) exists so row 5 never sees a manufactured exit 4. |
| deploy (C23 = 0 today, a sawtooth) | 1 | All of M1–M3 land in **symlinked** files (C24) ⇒ landing == deploying, no activation step. The one non-symlink is `model-config.yaml` (C25), which **this rebuild does not modify** — noted so a successor does not walk into it. |

---

## §6 Failure-mode table — every OBSERVED mode → its structural answer

Every row is a mode measured on this machine, not a hypothetical. A mode without an answer is an
unfinished design.

| # | Observed failure mode | Evidence | Structural answer |
|---|---|---|---|
| F1 | An account is routed work, then dies at its cliff mid-flight; the work is stranded. | C17 (routing is cliff-blind) + C9 (93.5 h outage) | **M1** — cliff enters `_excluded`/scoring. Work is steered off the account 48 h before the wall. |
| F2 | The autonomous re-login path can never fire: it needs `k == 0`, the fleet never has it. | C6/C7/C8 — 0 of 4 accounts | **M1's DRAIN band manufactures the window.** Routing is the only `k` lever; the fix is in the same subsystem. |
| F3 | The poller's declared T−7 d trigger is capped at 72 h by the surface it consumes. | C12/C13/C14 — 57.1 % unreachable; live `exit 1` vs `exit 0` divergence | **M2** — `--login-status --window-h N`; the poller asks for its own window. Default unchanged. |
| F4 | The poller is not scheduled and NOTHING reports that. | C15 (2 log lines, all-time) + C16 (label undeclared) | **M4** — declare `staged` in the fleet manifest ⇒ exactly one `UNDECIDED` row. R6/R7. |
| F5 | A human session read the 72 h surface and concluded "no cliff for a month", 3 weeks early. | §1, `RELOGIN_AUTOMATION_PLAN.md:266` vs C4 | **M2** — the same fix; the defect was never poller-specific. |
| F6 | The cliff becomes UNKNOWABLE at the exact moment the account breaks. | C22 — ledger carries quota, not the cliff | **M3(a)** — `login_expires_at` into the last-good ledger; R3 preserved (`error` still excludes). |
| F7 | "Did routing read live quota / see the cliff?" cannot be answered from disk. | C18 — 4 fields, none of them an input | **M3(b)** — record `cliff_h`, `cliff_band`, `quota_as_of`. R10. |
| F8 | 24 doomed refresh grants fired into a dead wall in 7.7 h. | C10 | **Already correct, kept:** past the stamp the heal is skipped by construction (`bin/claude-accounts:28`). M2 makes the *pre*-cliff window actionable so the post-cliff loop is not the only behaviour. |
| F9 | A cliff-drain exclusion is reported to row 5 as a fleet QUOTA CLIFF (exit 4). | `bin/cc-route:163-183` + `reason_class` mapping policy⇒2 | **M1's YIELD clause (R11)** — `ranked()` re-admits drained accounts when the cliff term emptied the set, and records it. Pinned by test. |
| F10 | An older binary without `login_expires_*` has its whole fleet cliff-excluded. | `bin/claude-accounts:1519` (field not on every build) | **M1's FAIL-OPEN rule (R9)** — `None` ⇒ no cliff term. Pinned by test. |
| F11 | The `staged` plist is invisible to the manifest's three-way lint because the lint globs `launchd/*.plist` only. | `tests/cc-fleet.bats:538` glob | **M4** declares it explicitly; the plist deliberately stays in `launchd/staged/` so `install.sh`'s glob cannot auto-activate it (`8a1e49ab`). |
| F12 | Routing serves a 600 s-old quota number on the lock-contention degrade path with no record of the age. | C21 + C18 | **M3(b)** records `quota_as_of`, making the degrade path *visible* rather than silent. The 90 s TTL itself is kept (§8 R-3). |
| F13 | A **days**-formatted deadline was parsed as hours — 24× under. A T−90 h account computed T−3 h, escalated 3 days early, and poisoned the deadline-keyed dedup state on every tick. | `hours_secs` was `${1%%.*}` + an integer test; `"3.7d"` → `"3"` → 3 h. Reproduced live the moment M2 widened the window | **M2b** — `hours_secs` is unit-aware over `fmt_h`'s full vocabulary (`m`/`h`/`d`/`now`/`99d+`), and REFUSES what it does not recognise rather than truncating. Float maths via `awk` (`$(( ))` is integer-only; macOS ships bash 3.2). |
| F14 | The defect in F13 was **invisible to its own test suite** because the fixture was more parseable than the producer: ISO in `when`, a bare integer in `hours`, where the real tool emits `_fmt_when()` and `fmt_h()`. `hours_secs` was never executed by any test. | `tests/cc-relogin-poll.bats` `build()`, pre-M2 | **M2b** — the fixture is now the producer's LITERAL emission via `fmt_h_like`/`fmt_when_like` mirrors. This also exposed 3 pre-existing "ladder 1" tests as **vacuous** (they now fail on the pristine tree, correctly). Memory `fixture-shape-parity-with-real-producer`. |
| F15 | A `"0m"` deadline — under an hour, the most urgent shape there is — was REFUSED by the parser and the row silently dropped. | same parser | **M2b** — minutes are parsed; `"now"` and a negative value resolve to 0 (act immediately). |
| F16 | A **REQUIRED** row whose cause is not its deadline (next3's real 2026-07-24 shape: a rejected grant with time still on the stamp ⇒ both deadline columns `"—"`) was `continue`d — the account that most needed the poller was invisible to it. | `bin/claude-accounts:1858-1866` fills the deadline columns only when the deadline drives the verdict | **M2b** — REQUIRED resolves to a **NOW** deadline, which is that surface's own documented verdict ("action required NOW"), not a fabricated one. EXPIRING with no deadline stays correctly skipped — pinned as a discriminating control. |
| F17 | A drain reason MASKS the binding reason, flipping the data-vs-policy exit code from 3 to 2 — hiding a data outage as a policy refusal. | Found by this row's own suite against its own first cut of M1 | **M1** — `ranked()` reports the yield pass's reasons whenever the cliff was not the binding constraint. |
| F18 | A new bats suite runs against the operator's live `~/.claude`. | `ship-land`'s hermeticity ratchet refused M1's first land (exit 6) | **Fixed at the source** — `export HOME="$BATS_TEST_TMPDIR/home"` in `setup()`, never an allowlist entry. Overriding the three explicit path env vars is NOT sufficient: the subject also derives the relogin-poll log and the `CLAUDE_CONFIG_DIR` fallback from `$HOME`. |

---

## §7 Acceptance criteria — as DISK-TRUTH READS

Each is a command whose output decides the claim. No narration.

| AC | Claim | Read | Pass |
|---|---|---|---|
| AC1 | The cliff is a routing term, not a render string. | `grep -c 'login_expires_h' <(sed -n '/^def _excluded/,/^def ranked/p' bin/claude-accounts)` | **≥ 1** (was **0**, C17) |
| AC2 | An account inside the DRAIN band is excluded with a NAMED policy reason. | `CC_ROUTE_CLIFF_DRAIN_H=100 claude-accounts --route general 2>&1 >/dev/null \| grep -c login-cliff-drain` | **≥ 1** — verified live 2026-07-30: `next` (T−90 h) excluded, route still returned `next3` at exit 0 |
| AC3 | The drain NEVER manufactures a fleet cliff (R11/F9). | `CC_ROUTE_CLIFF_DRAIN_H=999999 cc-route lead >/dev/null; echo $?` — unpiped | **0**, never 4 |
| AC4 | Absence of the cliff field disables the term, not the fleet (R9/F10). | `tests/account-cliff-routing.bats` — the `login_expires_h: null` fixture still ranks | test green |
| AC5 | The poller can see its own declared window (F3). | `claude-accounts --login-status --window-h 168 > /tmp/ls; echo $?; grep -c next /tmp/ls` | exit **1**, count **≥ 1** while `next` is at T−90 h (C4). **Verified live 2026-07-30:** `--window-h 72` → rc 0, 0 rows; `--window-h 168` → rc 1, `next EXPIRING login-expiry Sun 13:21 3.7d claude-next` |
| AC6 | The default window is unchanged for every existing caller. | `diff <(claude-accounts --login-status) <(claude-accounts --login-status --window-h 72)` | **empty** — verified live |
| AC6b | A malformed window is a USAGE error, never a silent fallback to 72 and never a verdict. | `claude-accounts --login-status --window-h nope >/dev/null 2>&1; echo $?` | **64** — outside the 0/1/2 verdict range, so a `rc <= 2` consumer cannot read it as an answer |
| AC6c | A days-formatted deadline is not read as hours (the latent 24× error, F13). | `tests/cc-relogin-poll.bats` "a DAYS-formatted deadline is not read as hours" — and live: the poller against a `--window-h`-capable binary reports `hours_left` **88** for `next`, not 3 | test green; `escalated == false` |
| AC7 | The cliff survives a broken account (F6). | `jq -r 'to_entries[]\|"\(.key) \(.value.login_expires_at // "ABSENT")"' ~/.claude/logs/claude-accounts-lastgood.json` | **4 of 4 non-ABSENT** (was 0 of 4, C22) |
| AC8 | A routing decision records its own inputs (F7). | `tail -1 ~/.claude/route/route.jsonl \| jq -e 'has("cliff_h") and has("cliff_band") and has("quota_as_of")'` | exit **0** |
| AC9 | The dark poller is DECLARED, so its inertness is readable (F4). | `grep -c '^com\.claude\.relogin *|' launchd/fleet.manifest` | **1** (was 0, C16) |
| AC10 | Nothing regressed on the frozen `cc-route` contract. | `bash scripts/route-safety-gate.sh; echo $?` — unpiped | **0** |
| AC11 | Remembered quota is still barred from routing (R3/C20 must not regress). | `tests/account-cliff-routing.bats` control: a row with `error` set is excluded even when the ledger supplies a cliff | test green |
| AC12 | The whole corpus is green through the shared box. | `bin/cc-bats tests/<suites> > /tmp/out 2>&1; echo $?` then `grep -c '^not ok' /tmp/out` | rc **0** and `not ok` count **0** |

**ACCRUING, named honestly (not claimable this session):** the end-to-end proof that a DRAIN band
actually reaches `k == 0` before T−0 requires `next`'s real cliff, **2026-08-02T20:21:49Z**
(C4) — 3.76 days out. Read then: `~/.claude/logs/cc-relogin-poll.log` for an `ATTEMPT` line
(today: 0 all-time, C15) and the keychain stamp moving past Aug 2. That is the first real window
in which any of this can be observed, and §1 establishes it is 3 weeks earlier than the plan on
disk claimed.

---

## §8 Rejected alternatives (with reasons — prevents relitigating)

| # | Alternative | Rejected because |
|---|---|---|
| A1 | **Relax `cc-relogin`'s `k == 0` gate** (relogin while sessions run) so the poller can finally act. | The gate is CORRECT, not conservative: a running `claude` owns the token lifecycle and re-checks liveness *under the lock* precisely because "a relogin racing a running CC has its rotation discarded" (`bin/cc-relogin:563-575`). Relaxing it trades a predictable cliff for silent credential corruption across live sessions. The window must be **created**, not stolen. |
| A2 | **Auto-fire `cc-relogin` on `--login-status` exit 2.** | Deliberately refused by the prior build (`RELOGIN_AUTOMATION_PLAN.md:301`) and by R4: credentials are the one place an unattended retry loop must not be invented — and C10 shows 24 doomed retries in 7.7 h is the observed cost of getting that wrong. M1 changes the *precondition* instead, so the existing gated path can finally succeed. Revisit after several unattended successes, as that plan says. |
| A3 | **Hard-exclude an account for the whole T−7 d window.** | Throws away ~25 % of fleet capacity for 7 days out of every 30, per account — and with four accounts at staggered phases that is a near-permanent tax. A multiplier (SOFT) gets the same inflow reduction at no capacity cost; only the last 48 h needs a hard stop. |
| A4 | **Just raise `login_warn_h` from 72 to 168.** | It is the *shared* human-warning constant; widening it changes the dashboard, the handoff sweep (`bin/claude-accounts:1495`) and the `/accounts` readout for everyone, to fix one consumer's window. A per-call `--window-h` fixes the consumer without moving a constant six other surfaces read. Also would not fix F1/F2 at all. |
| A5 | **A new cliff-watcher daemon.** | The fleet already has a poller for exactly this (C13) that has never fired; a second daemon adds another thing that can be dark (C15/C16) and another label to leave undeclared. The defect is not a missing daemon, it is a precondition no daemon can satisfy. Fix the precondition. |
| A6 | **Force `--fresh` on every routing call so quota is provably live.** | `--fresh` takes the single-flight lock and can legitimately be held for MINUTES (`bin/claude-accounts:931-935`); making the hot routing path do that turns every dispatch into a lock queue — and it is the exact fail-closed-as-amplifier shape in memory `fail-closed-degradation-as-amplifier`. The 90 s TTL is right; what was missing is the *record* of the age (M3b). |
| A7 | **Record the quota `percent` denominator explicitly** (the row-8 fix, applied here). | Nothing to fix: the denominator is server-side and never appears locally (C19) — inventing a local one would *create* the row-8 defect. Named in §2 so the check is on the record rather than skipped. |
| A8 | **Revert-as-plan instead of a kill switch.** | Banned by R8. All three new behaviours are env-gated. |
| A9 | **Move `com.claude.relogin.plist` from `launchd/staged/` into `launchd/`** so the existing three-way lint sees it. | `install.sh` globs `launchd/*.plist`; the plist was moved to `staged/` *by structure, not conditional* (`8a1e49ab`) exactly so it cannot be auto-installed. Moving it back would let a routine install ACTIVATE credentials automation — an operator decision (C10). Declare it in the manifest instead (M4). |

---

## §9 Seams consumed (contracts, not redesigns)

| Seam | Owner | This rebuild's posture |
|---|---|---|
| `cc-route` exit codes **0 plan · 2 usage · 3 blind/no-data · 4 cliff**, pinned by `scripts/route-safety-gate.sh:33-50` + `tests/cc-route.bats` | 7 (mine), **consumed by 5** | **NOT changed.** No code added, none altered. M3(b) adds JSONL *keys*; M1's yield clause exists specifically so row 5 never sees a manufactured 4 (F9). AC10 re-runs the gate. |
| fire-time ranking `claude-accounts --rank` | consumed by row **2**'s `handoff-fire` | Output *ordering* may change (that is the point); the contract — one account name per line, `none` on refusal, exit 0/2/3 — is untouched. M1's yield guarantees a name is still returned whenever one exists. |
| `bin/cc-wave-plan` | **5** | Consumer only. Unchanged surface. |
| `launchd/fleet.manifest` semantics + the parity lint | **12** | I add ONE `staged` row (mine, `owner_row = 7`) and bump that file's own documented label count. Lint untouched. Coordinator asked before landing. |
| `idl.jsonl` class-C row schema (`kind: relogin-blocked`) | **10** renders, **7** produces | Producer unchanged. |
| `~/.claude/CLAUDE.md` / `model-config.yaml` non-symlink trap | **8** ruled | **Not touched by this rebuild.** Recorded as C25 so a successor does not assume symlink. |

---

## §10 Kill switches (R8)

| Switch | Default | Effect when set |
|---|---|---|
| `CC_ROUTE_CLIFF_TERM=off` | `on` | M1 fully disabled — both bands; routing byte-identical to pre-rebuild. |
| `CC_ROUTE_CLIFF_SOFT_H` | `168` | SOFT band edge (hours). `0` disables the soft band only. |
| `CC_ROUTE_CLIFF_DRAIN_H` | `48` | DRAIN band edge (hours). `0` disables the drain band only. |
| `CC_ROUTE_CLIFF_SOFT_FACTOR` | `0.25` | SOFT-band score multiplier. `1.0` = no deprioritization. |
| `--window-h N` (M2) | `login_warn_h` (72) | Per-call `--login-status` window; omitted ⇒ prior behaviour exactly. A malformed N exits **64** (usage), deliberately outside the 0/1/2 verdict range. |
| `--trigger-days N` (existing) | `7` | The poller's policy AND now the window it asks for — one constant, not two that can silently disagree. |
| `CC_ROUTE_RECORD_INPUTS=off` | `on` | M3(b) reverts `route.jsonl` to the 4-field record. |

---

## §11 Status

- **2026-07-30 — Phase 1 complete, cell CONFIRMED-and-renamed** (§1). 26 measured constants
  (§2). Graveyard swept with a passing positive control: **nothing to take** (§3).
  Coordinator pinged with the findings and the M4 seam question; ping **read** (`acked=26`), no
  objection to the M4 plan.
- **M1 LANDED** — cliff-aware routing + the yield. 17 tests, **12 RED-proved** against a pristine
  `git archive` tree at the derived pre-fix rev `5597bd2a`; the 5 green-on-both are
  contract-preservation tests (R3 non-regression, exhausted-stays-exhausted, the data-vs-policy
  exit split), named as such. Regression **104/104, 0 not-ok** across `claude-accounts-core`,
  `claude-accounts`, `cc-route`, `cc-relogin-status`, `claude-accounts-fresh-lock-bound`,
  `effort-parity`; `scripts/route-safety-gate.sh` green (frozen 0/2/3/4 contract untouched).
  Verified live against the real fleet before landing: `next` (T−90 h) enters the SOFT band and
  scores exactly ×0.25; `CC_ROUTE_CLIFF_DRAIN_H=100` excludes it and routing still returns
  `next3` at exit 0; draining ALL FOUR still returns an account at exit 0 with the YIELDED notice
  — **the R11 property proven on production data, not only in a fixture**.
- **M2 LANDED** — `--login-status --window-h N` + the poller asking for its own window.
- **M3(b) built** — `route-meta:` on stderr + `route.jsonl` carrying `cliff_band` / `cliff_h` /
  `cliff_at` / `quota_age_s` / `quota_cached` / `cliff_yielded`. 7 RT-h checks in **`cc-route`'s own
  selftest**, which is the enforcement chokepoint (`scripts/route-safety-gate.sh:46` gates on
  `cc-route selftest`, not on a sibling suite — memory
  `enforcement-must-live-at-the-chokepoint`). 26/26 green. **2 of the 7 RED-prove** via a true
  differential — same stub, same SSOT fixture, only the subject binary differs: pristine
  `ebf916f4` records `["detail","outcome","slot","ts"]`, current records those plus the five input
  fields. The other **5 are contract-preservation** checks, named as such (fail-soft on an
  old producer, the R8 kill switch, and three pinning stdout unchanged).
- **M4 built** — `com.claude.relogin` declared `staged` in `launchd/fleet.manifest` with a per-tick
  evidence sensor and `ok_exits 0,5`; label count 21→22 in row 12's own convention; activation
  staged in **both** the repo SSOT and the live operator queue, dry-run executed.
- **M3(a) NOT BUILT** — deliberately, per the mid-build reprioritization above. It is visibility and
  history, not a stranding fix. Recorded as remainder **R-8** rather than left as a silent gap.

### §11.1 CLOSE — 2026-07-30, against the frozen DoD

**12 lands, every sha re-resolved from `origin/main` by `merge-base --is-ancestor` AFTER ship-land's
rebases** (it rebased four times; the pre-rebase shas in earlier commit messages are dead):
design **cb930804** · M1 **e7badb54** · learnings **7724dfa4** · M2 **434a391e** · M3b **7cb5f548** ·
M4 **b15942c3** · status **16b3bba5** · trunk repair **8c73747e** · SSOT-guard fix **9240c071** ·
M5 **a0392fb7** · growths **cb01df65** · map row **dd1d55a3**.

**PROVEN (disk reads).** 176 tests green in ONE run across 7 suites, `not ok` count **0** —
`account-cliff-routing` · `cc-relogin-poll` · `cc-fleet` · `cc-route` · `claude-accounts-core` ·
`claude-accounts` · `cc-relogin-status`. Plus `cc-route selftest` 26/26, `scripts/route-safety-gate.sh`
2 met / 0 failed, and **row 5's `cc-wave-plan selftest` 63/63** — the consumer seam verified rather
than assumed. **24 new tests RED-proved** against pristine `git archive` trees at *derived* pre-fix
revs (M1 12 of 17 vs `5597bd2a`; M2 10 of 43 vs `d54b8a74`; M3b 2 of 7 vs `ebf916f4` via a
same-stub/different-subject differential). Every green-on-both case is named contract-preservation,
never counted as a RED-proof. Content-verified on trunk by path with a positive control against a
path known absent. AC1-AC6c, AC8-AC12 met; **AC7 NOT met** (see below).

**IN FLIGHT / operator-owned.** One C10 command, plattered, staged in both the repo SSOT and the live
queue, dry-run already executed:
`CONFIRM=1 bash ~/.claude/autonomy/pending-activation/21-relogin-poll-activate.sh`.

**ACCRUING (time-dependent, and where it will be read).**
- The drain→`k == 0`→re-login chain end-to-end needs `next`'s real cliff, **2026-08-02T20:21:49Z**.
  Read then: an `ATTEMPT` line in `~/.claude/logs/cc-relogin-poll.log` (today: **0** all-time) and the
  keychain stamp moving past Aug 2. **`cc-relogin`'s Phase 2 has never driven a live OAuth flow — that
  first run is a SUPERVISED test, not a routine one.**
- `route.jsonl`'s new input fields accrue per routing decision; the R-3 question (how often the 600 s
  degrade path is served) becomes answerable once records accumulate: `jq` over `quota_age_s`.
- **Landed ≠ live.** The shared checkout was 30 behind trunk mid-session, so `~/.claude/bin/*`
  symlinks still served the old binary. No activation step exists for any of M1/M2/M3b/M5 — they go
  live on the checkout's fast-forward. Effect-read: `grep -c cliff_band ~/.claude/bin/claude-accounts`.

**NOT DONE, stated plainly.** **AC7 / M3(a)** — `login_expires_at` is still absent from the last-good
ledger (4 of 4 accounts), so the cliff remains unreadable for an account whose keychain read fails.
Demoted on measured grounds, not forgotten: remainder **R-8** carries its ~10-line shape and the R3
constraint it must preserve. The *action* path is covered (F16); the *history* is not.

**The unfalsifiable-claim ceiling, named rather than papered over.** Two of this row's headline claims
cannot be proven this session by construction, and both are recorded as ACCRUING above rather than
asserted: that a drain actually reaches `k == 0` in time, and that unattended re-auth works at all.
Everything else is a disk read.

### §11.2 THE LIVE WINDOW RAN — 2026-08-08, and it REFUTED the headline claim

§11.1 named two claims as unprovable by construction and deferred both to `next`'s real cliff on
**2026-08-02T20:21:49Z**. That date has passed. The reads it specified are now available, and the
answer is not the one the design expected.

**The cadence works. The executor does not.** The C10 activation ran, so the poller has been
ticking hourly since 2026-07-30, and `~/.claude/logs/cc-relogin-poll.log` now holds **6 ATTEMPT
lines** where §11.1 recorded 0 all-time. The drain→`k == 0` half of the chain is therefore
**PROVEN on production data**: the poller caught real zero-session windows and invoked
`cc-relogin` four separate times against `next` before its deadline. Every later leg failed.

| # | Tick | Result | What it actually was |
|---|---|---|---|
| 1 | 2026-07-30T20:36:03Z | `PROVEN (0)` | deadline "moved" `…48.963` → `…49.116` = **+0.153 s** |
| 2 | 2026-07-30T21:36:31Z | `BROWSER-FAILED (4)` | `cc-authbrowser --start` exit 4 |
| 3 | 2026-07-30T22:37:18Z | `PROVEN (0)` | deadline "moved" `…48.815` → `…49.195` = **+0.380 s** |
| 4 | 2026-07-31T05:39:01Z | `REFUSED (2)` | 4 live sessions — the k==0 gate, correctly |

Attempts 1 and 3 are the finding. Both reported success; both left the wall on the **same second**,
two hours apart. `verify()` tested `new > old`, and §1's own confirmed cell says why that can never
decide it: the server returns a **countdown to a FIXED wall, re-expressed from a fresh `Date.now()`
at every refresh**, so a successful refresh always creeps the absolute stamp a few hundred
milliseconds without renewing anything. The oracle was satisfied **by construction**. Worse, `run()`
returns `EXIT_PROVEN` the moment `verify()` says ok — so **phase 2, the browser OAuth that is the
only leg that resets the wall, was never reached.** The code's own comment already stated the
correct model ("a refresh grant does not move the login deadline … Escalate, never stop here"); the
comparison could not express it.

**`next` was saved by a human.** Its cliff is now `2026-08-30T15:03:18Z` — about 30 days after
**2026-07-31 ~23:00Z**, which is exactly when it dropped out of the poller's T-7d window (T-45h at
22:48, "nothing due" at 23:48). No `ATTEMPT` in that hour and no `heal next:` line: an interactive
login moved it. So the first end-to-end test of the automation ended with the automation reaching
the account four times, declaring victory twice, and the operator doing the work.

**R-1 is ANSWERED, and phase 2 is no longer unexercised.** It ran unattended once (attempt 2) and
failed at `cc-authbrowser --start`. The supervised-first-run caution stands, but the reason has
changed: it is not that phase 2 has never run, it is that phase 2 has never *succeeded*.

**Three sites shared one root defect; all three are fixed.** The error is comparing two
re-expressions of a fixed wall with exact arithmetic, when the wall's real movements are ~30 days:

- **`f001ae29` · `bin/cc-relogin`** — `verify()`'s `>` (the table above). A renewal must now clear
  `CC_RELOGIN_DEADLINE_EPSILON_H` (12 h). The stamps were also being compared as **strings**, so an
  unparseable one read as lexicographically "moved"; they are parsed now.
- **`7c7a6676` · `bin/cc-relogin-poll`** — the same error with the opposite sign: `!=` on the state
  key. `$DL` is derived as `NOW + hours_secs(<fmt_h text>)`, so it *cannot* repeat across ticks —
  every tick read "the deadline moved → fresh cycle". Hence all six ATTEMPT lines reading `#1`, an
  **unreachable** `MAX_ATTEMPTS` arm, and dedup failure (next2 was paged twice in two hours on the
  `dl=NOW` path, where dedup was structurally impossible). The class-C row raised for `next` on
  2026-07-31T20:47:13Z told the operator **"no k==0 window caught in 0 attempt(s)"** — after four.
- **`33b374a7` · `scripts/relogin-probes/e3-warm-profile-authorize.sh`** — the worst-placed copy.
  E3's `PROVEN` verdict is the documented authorization to activate the cadence, and its `UNVERIFIED`
  branch exists *precisely* to catch "cc-relogin exited 0 but the deadline did not verifiably move …
  its verify-by-EFFECT gate is not doing its job". It could not: the watchdog computed the verdict
  with the same bare `>` as the subject. It now uses its **own** epsilon variable, deliberately not
  the executor's, so one mis-set knob cannot blind both.

**R-6 is re-classified, and this is the transferable lesson.** It was filed as "a named limit, not a
bug" because ±1.2 h of `fmt_h()` quantization is immaterial against a 48 h escalation threshold.
That reasoning is correct **for a threshold and wrong for an identity**: the same quantization that
cannot change a comparison's answer destroys a key's stability. R-6 was the direct cause of the
poller defect and was on file, correctly measured, for the whole window.

**Why 176 green tests never saw any of it.** Each suite modelled the jitter away. `cc-relogin.bats`
moved its "moved" fixtures by *hours* and held its "did not move" fixtures *exactly equal* — the
production case, +153 ms, was modelled by neither. `cc-relogin-poll.bats` **pins the clock**
(`CC_RELOGIN_POLL_NOW`), and the poller defect exists only because the clock advances, so repeated
ticks in the suite were identical by construction. This is the same F14/R-7 class the row already
named — *a fixture more forgiving than the producer it models* — landing twice more, in the two
suites most responsible for this behaviour.

**Still accruing.** No account has yet been renewed by the automation, so the executor's end-to-end
claim remains unproven — it is now blocked on `cc-authbrowser`, not on the oracle. The next real
window is `next` / `next4` at **2026-08-30**, ~22 days out; `next2` 2026-08-31, `next3` 2026-09-03.
`route.jsonl`'s `quota_age_s` series (R-3) keeps accruing.

### Learnings — three defects the build itself surfaced (each cost a real land or gate cycle)

1. **My own suite caught a masking bug in my own first cut of M1.** `_excluded()` returns the
   drain reason *before* `score_general` can reach `no-weekly-data`, so a fleet that was really
   DATA-BLIND reported the drain instead — `policy` (exit 2, "do not fire blind") where the truth
   was `data` (exit 3, "callers may degrade to a proxy"). Wrong verdict, in the direction that
   HIDES an outage. `ranked()` now reports the **yield pass's** reasons whenever the cliff was not
   the binding constraint. Pinned by two tests plus a CLI-level exit-3 test.
2. **The land gate refused M1 once, correctly.** `ship-land`'s hermeticity ratchet found that
   `tests/account-cliff-routing.bats` did not fixture `$HOME` — overriding
   `CLAUDE_ACCOUNTS_JSON`/`_LASTGOOD`/`cache_file` is NOT sufficient, because the subject also
   derives the relogin-poll log path and the `CLAUDE_CONFIG_DIR` fallback from `$HOME`. Fixed at
   the source, never via the allowlist. *Expect your own gates to catch your own defects.*
3. **Widening the window immediately exposed a latent 24× deadline error — and the reason it had
   been invisible is a FIXTURE/PRODUCER PARITY failure.** `cc-relogin-poll`'s `hours_secs()` was
   `${1%%.*}` plus an integer test, which strips the fraction *and the unit* in one step: `"3.7d"`
   → `"3"` → **3 hours**. A T−90 h account computed T−3 h, escalated three days early, and
   poisoned the state file's deadline-keyed dedup on every tick. It survived because
   `tests/cc-relogin-poll.bats` fixtured the `--login-status` TSV with an **ISO stamp** in `when`
   and a **bare integer** in `hours`, while the real `claude-accounts` emits `_fmt_when()`
   (`"Sun 13:21"` — never ISO) and `fmt_h()` (`"30m"` / `"41.5h"` / `"3.7d"` / `"now"` /
   `"99d+"`). So `iso_epoch()` always succeeded and **`hours_secs()` — the function that actually
   derives the deadline in production — was never executed by any test.** The fixture is now the
   producer's literal emission (with `fmt_h_like`/`fmt_when_like` mirrors), which also revealed
   that three pre-existing "ladder 1" tests had been passing **vacuously**: on the pristine tree
   they now fail, because the pristine poller genuinely cannot see a 100 h deadline through a
   72 h-filtered surface. Memory: `fixture-shape-parity-with-real-producer`.
   Two further drops fixed in the same pass: `"0m"` (a <1 h deadline — the most urgent shape of
   all) was **refused** by the parser and the row silently `continue`d; and a **REQUIRED** row
   whose cause was not its deadline — next3's real 2026-07-24 shape, a rejected grant with time
   still on the stamp, both deadline columns `"—"` — was also `continue`d, so the account that
   most needed the poller was invisible to it. REQUIRED now resolves to a NOW deadline, which is
   that surface's own stated verdict rather than a fabricated one; EXPIRING with no deadline is
   still correctly skipped (discriminating control).

### Reprioritization, mid-build — M3(a) is smaller than §5 claimed

§5 framed M3(a) (the cliff into the durable ledger) as closing a fail-closed hole: "the data
vanishes precisely when it is needed." Verified at code level, that is **half right and the wrong
half is the important one.** `probe_account` returns early on `kstate != "present"` — before
`login_expires_at` is ever set (`bin/claude-accounts:588-594` vs `:603`) — so a broken account
genuinely carries no cliff data. **But the ACTION path does not need it:** `relogin_row` already
renders `logged-out`/`token-invalid` as ESCALATED from a field present on every build, and M2b's
F16 fix makes a REQUIRED row with no parseable deadline resolve to a NOW deadline, so the poller
now acts on exactly that account. M3(a) is therefore **visibility and history** — the operator's
"when was this account's login due", and a durable series that would let the ~30 d period (C1) be
measured rather than bracketed — not a stranding fix. Ranked below M3(b) and M4 accordingly, and
if it does not land this session it is a named remainder, not a silent gap.

### Correction to C23/C24 — "landing == deploying" is CONDITIONAL

C23 measured deploy lag **0** at 02:0xZ. By 03:0xZ the shared checkout was **30 behind**
`origin/main` (the sawtooth, climbing again). `~/.claude/bin/*` are symlinks into that checkout's
**working tree**, so landing deploys **only once the checkout fast-forwards** — there is no
per-file activation step, but there is a lag. Effect-read at 03:0xZ:
`grep -c cliff_band ~/.claude/bin/claude-accounts` → **0** while `git show origin/main:` → **5**.
So M1/M2 are landed and content-verified on trunk and **not yet live**. This was observable in the
system's own behaviour within the hour: `cc-relogin-poll` run against the *deployed*
`claude-accounts` found no `--window-h`, took its fail-soft path, and logged
`WINDOW-CAPPED … does NOT cover T-7d` — the R12 degradation working exactly as designed, against
a real dark dependency rather than a hypothetical one.

## §12 Remainders — named, with owner and reason

| R | Remainder | Owner | Why not now |
|---|---|---|---|
| R-1 | ~~**`next`'s real cliff on 2026-08-02T20:21:49Z is the first-ever live test of `cc-relogin` Phase 2**~~ **ANSWERED 2026-08-08 — see §11.2.** The window ran. The cadence half PROVED OUT (6 ATTEMPT lines where §11.1 recorded 0); the executor half FAILED, and `next` was rescued by an interactive login on 2026-07-31 ~23:00Z. Phase 2 *was* driven unattended once and failed at `cc-authbrowser --start` (exit 4), so the caution stands with a changed reason: not "never run" but "never succeeded". Two of the four attempts declared victory on 0.153 s / 0.380 s of re-expression jitter — fixed in `f001ae29`. **Successor remainder R-10.** | 7 + operator | — |
| R-2 | `com.claude.relogin` LaunchAgent activation is a **C10 operator step** (classifier-terminal for agents). | operator | Staged + plattered by M4. |
| R-3 | The 600 s cache-grace degrade path is now *recorded* (M3b) but not *bounded* — nobody counts how often routing serves a 600 s-old number. | 7 | Needs a period of records first; the read is `jq` over `quota_as_of` in `route.jsonl`. |
| R-4 | ~~`RELOGIN_UNKNOWN_ACTION = "land feat/accounts-login-cliff (adds --login-status)"` is **stale**~~ **DONE 2026-08-08 · `1742c4b4`.** Both the constant and the `--relogin-status` DETECTION-UNAVAILABLE warning now name a recovery that exists (`claude-accounts --fresh; if it persists, cc-relogin <acct>`), because on this build UNKNOWN means `probe_account` returned early on `kstate != "present"` (`:588-594` before `:603`), not a missing feature. The test that pinned the old string asserts the opposite now — it had gone stale in lockstep with its subject and was holding the defect in place. | 7 | — |
| R-5 | Session-lifetime distribution is unmeasured, so `CC_ROUTE_CLIFF_DRAIN_H=48` is a *reasoned* default, not a measured one. If 48 h of drain does not reach `k == 0`, behaviour degrades to today's (escalation row at T−48 h) — never worse. | 7 (data lives with 2/4) | Needs row 2/4's session-lifetime data; the design fails soft without it. |
| R-6 | The `--login-status` leg carries the deadline only as `fmt_h()` text, whose days form rounds to 0.1 d — so a deadline derived through that leg is precise to **±1.2 h**. Harmless against a 48 h escalation threshold, but it is a real quantization and it is why the live poller reads T−88 h for a T−90.3 h cliff. The `json-fields` leg carries the raw float. Widening the TSV to carry an ISO stamp would break its frozen 6-field shape (`norm 6` parses positionally), so this is a **named limit, not a bug**. **⚠ RE-CLASSIFIED 2026-08-08 — this was the direct cause of the poller defect (§11.2, fixed in `7c7a6676`).** The "harmless" argument is sound for a THRESHOLD and false for an IDENTITY: ±1.2 h cannot change the answer to `is T-h <= 48`, but it destroys the stability of a key. The poller keyed its attempt counter and its escalation dedup on the deadline derived through this leg, so the quantization made the key change on every tick. The remainder was on file, correctly measured, for the whole live window — what was wrong was the *scope* of its harmlessness claim, not its measurement. The TSV contract stays frozen; the consumer now compares deadlines with a tolerance instead of for equality. | 7 | Fixing the quantization itself still means a 7th field or a new flag; still not worth breaking a frozen contract. |
| R-8 | **M3(a) — `login_expires_at` into the last-good ledger** (AC7). NOT BUILT this session, by the reprioritization above: it is visibility and history (the operator's "when was this login due", and a durable series that would let C1's ~30 d period be *measured* rather than bracketed to [26.1, 30.0] d), not a stranding fix — M2b's F16 already makes the poller act on exactly the account whose cliff is unreadable. ~10 lines: carry the absolute stamp into the `entry` dict beside the quota, restore it in `inherit_lastgood`, and let `refresh_login_countdown` derive `_h` from it for free. **R3 must be preserved exactly:** an inherited cliff must NOT make a row routable — the row still carries `error`, so `_excluded()` still bails. Pinned by the existing AC11 control. | 7 | Ranked below M3(b)/M4 on measured value; named, not silently dropped. AC7 stays UNMET and is reported as such. |
| R-9 | A **load-dependent flake** in this row's own tests was found and fixed (see §11), but the general lesson is unowned: **a bats assertion on a process EXIT CODE is fragile whenever the subject forks a child under the background QoS band `bin/cc-bats` imposes.** Two of this row's tests hit it. The durable fix pattern is to assert the subject's own durable product instead — but nothing enforces or even detects the fragile pattern. | 13 (owns `cc-bats`/QoS) / 1 (owns the gate) | Row 7 fixed its own two instances. A detector would need to know which code paths fork, which is not a lint. |
| R-10 | **The executor's remaining blocker is now `cc-authbrowser`, not the oracle** (§11.2). Phase 2 ran unattended once, 2026-07-30T21:36, and died at `cc-authbrowser <acct> --start` with exit 4 (BROWSER-FAILED) — the transcript was kept at `/tmp/cc-relogin-next.out` and has since been reaped. With `f001ae29` in place a jitter-only phase 1 now correctly falls through to phase 2, so this leg will be reached far more often; if it still cannot start a browser, the automation escalates honestly instead of claiming success, which is strictly better but still not a renewal. **Read at the next window (`next`/`next4` 2026-08-30):** a `BROWSER-FAILED` vs a `PROVEN` in `~/.claude/logs/cc-relogin.log`, and whether `E3` now emits `moved=jitter` where it used to emit `yes`. | 7 | Needs a real cliff to exercise, and `cc-authbrowser`'s exit 4 has no captured transcript to diagnose from — the failure must be reproduced, not inferred. |
| R-11 | **The F16 `REQUIRED → dl=NOW` rule fires on accounts that need nothing.** On 2026-08-03 `next2` was escalated and attempted twice at "T-0h" while holding **674.6 h** (28 days) of cliff; `cc-relogin` refused both with *"no re-auth needed — healthy (auth=stale …)"*. The `--login-status` sweep had classified it REQUIRED via `login_fixable`, and F16 resolves a REQUIRED row with no parseable deadline to NOW. `7c7a6676` stops the repeat-paging (one row per cycle, not per tick), but the **first** row is still raised on an account the actuator immediately declares healthy. The structural question is that escalation is deliberately written BEFORE the attempt (so a hung attempt cannot swallow it) and nothing RETRACTS it when the attempt refutes it. | 7 | The escalate-first ordering is correct and load-bearing; adding a retraction path is a real design change to the class-C board's contract, not a one-liner, and it belongs with row 10 (which renders the board). |
| R-7 | **A campaign-wide question this row can only raise, not answer:** the F14 defect class — *a test fixture more parseable than the producer it claims to model* — is invisible to every gate we have. `hours_secs` had **zero** effective coverage while its suite reported 33 passing tests. Worth a sweep: for every stub that renders a sibling tool's output, does it emit that tool's LITERAL formatting? | 1 (owns `run_gate`) / campaign | Out of row 7's scope; row 7 fixed its own two instances. A lint is conceivable (compare a stub's emitted shape against the producer's formatter) but is a real design problem, not a one-liner. |

## §13 M7 — utilization-maximizing routing (2026-08-10, operator /goal)

**Scope (frozen):** tweak `/handoff` × `/accounts` so concurrent WORKING sessions spread instead
of piling onto one account's 5h window, AND the account whose weekly quota expires soonest
relative to its remaining usage is exhausted first — the fleet was stranding weekly quota at
reset. Execution locus: **L** (lead-inline — one coupled scoring change in one binary + its
suites; no independent parallel units).

**The evidence (one live snapshot exhibits every defect).** 2026-08-10T08:13Z: `next3` held the
fleet's soonest-expiring quota — weekly 81%, reset 27.8h, ~19% about to strand — and was
EXCLUDED from routing (`k=28 ≥ KMAX=8`) while its 5h window sat at 60%: `k` counts PANES
(mostly idle desks), not burn. Every fire inside the 90s rank-cache TTL then took rank[0] =
`next2` (weekly 13%, reset 5 DAYS out). By 09:53Z the inversion had run to its terminal state:
next3 5h-capped at 100% carrying 36 sessions while three accounts with 5-6-day runways sat
nearly idle. The pile-up and the under-exhaustion are one defect seen from two ends. Linear
urgency was also indifferent exactly where it mattered: `0.19/27.3 ≈ 0.87/122.3`.

**The four terms** (all in `bin/claude-accounts`, all fail-soft to pre-M7 behavior on missing
data, each kill-switched):

| Term | What it does | Kill |
|---|---|---|
| `URGENCY_EXP` (γ=2) | `score = headroom / T**γ` — deadline-DOMINANT: the required rate weighted by how soon it stops being achievable ("prioritize exhausting the most immediate expiry, especially when remaining is large for the time left" — the operator's sentence as algebra). γ=1 is byte-identical prior math. | `CC_ROUTE_URGENCY_EXP=1` |
| `k_work` | WORKING sessions (transcripts written ≤10min, `working_concurrency()`, realpath-deduped, 2s walk budget → `None` → census fallback) replace the pane census in KMAX/KF. Census keeps display + heal's k==0 gate. | `CC_ROUTE_KWORK=off` |
| phantoms | `--assign <acct>` appended by handoff-fire at pick time (`~/.claude/logs/account-assignments.jsonl`, self-pruned at 400 lines + rotate-autonomy-logs backstop); counted as +1 working session for 15min at RANK time — burst fires walk down the ranking inside the cache TTL. | `CC_ROUTE_ASSIGN=off` |
| 5h projection | SF evaluated at `session_pct + measured burn × lookahead` (burn from the utilization series' newest ≤1.5h pair; lookahead capped at the 5h reset). Soften-ONLY by construction — can cost a tie, can never trip an exclusion or halt the fleet. | `CC_ROUTE_PROJ=off` |

Plus the **pace surface** (the goal's own metric): `pace to 100%: <acct> N%/d over <T> (recent
M%/d — BEHIND)` in the table + readout footers; `weekly_need_pct_per_day` + `burn_wk_ppd` in
`--json`. BEHIND only when measured < needed — no invented thresholds.

**Contracts unchanged:** `--route`/`--rank` stdout shapes, exit 0/2/3 classification,
`no-fable-limit` entitlement semantics, cliff terms and yield, the get_data test anchor. New SSOT
keys are OPTIONAL (`R.get` defaults) — an un-migrated accounts.json routes identically minus M7.

**Verified:** 113 tests green across 6 suites (core +8 M7 tests incl. the frozen snapshot as a
fixture: γ=2 routes it to next3, γ=1 provably inverts; census-fallback; phantom demote/exclude;
projection reset-cap; ledger TTL/prune/malformed; `--assign` CLI) + new
`tests/handoff-fire-assign.bats` (call-site wiring: fires on commit, silent on
dry/recycle/explicit-launcher/hermetic-harness, advisory-never-fatal).

**Learnings.**
- **The kmax raise (4→8, §11) treated the symptom of a category error.** The counter was raised
  because it "sees ALL live sessions" — the honest fix was that a pane census is a CEILING on
  burn, not a measure of it. Charging `k_work` un-excludes the account the goal most needs
  burned while capping true pile-up harder (8 WORKING sessions is a real cap; 8 panes never was).
- **A rank served from a cache needs a write-side decrement or bursts defeat any scoring.** No
  scoring function fixes same-rows→same-answer; the fire itself must charge the account
  (`--assign`), and over-counting during the phantom/real overlap (~13min) errs toward MORE
  spread — the safe direction.
- **M7 made every CLI invocation a reader of two live series** (utilization, assignments), which
  instantly un-hermeticized 2 CLI suites whose fixtures reuse real account names (core test 26
  inherited the REAL fleet's burn rates and flipped its ordering). `CC_UTIL_LOG`/`CC_ASSIGN_LOG`
  pins in setup() + env-overridable paths. Rule: a new ambient input to a CLI is a new fixture
  surface for every suite that drives it.
- **A separate live defect on this box corrupted the build itself** (filed to backlog): text
  passing through the agent Bash tool's zsh gets the bare token `b``a``t``s` rewritten to the
  cc-bats wrapper path — measured corrupting a heredoc-written test literal in tests/ AND /tmp,
  and the operator's own transplant context file. Write/Edit tools bypass the shell and are
  immune (this section is written by one). Workaround adopted: never write file content through
  shell heredocs.

**§13 Remainders:** R13-1 dashboard `live` column still renders the pane census only — k_work is
--json-only until a display slot is designed (82-col budget). R13-2 `pool-floor.sh` should
eventually feed a measured per-session burn coefficient into the projection (today: account's own
recent rate). R13-3 non-handoff-fire spawners (none known: cc-dispatch fires THROUGH
handoff-fire) that grow a direct launch path must add the same `--assign` call.

## §14 M7 wave 2 — the two ends M7 routing does not reach (2026-08-10, same /goal)

**Why a wave 2.** Post-M7 live read (11:0xZ fresh sweep): next3 5h **0%** (window rolled), weekly
**89%** with **23.7h** to reset, **k=36 panes, k_work=0** — the router now puts next3 on top
(0.11/23.2² beats everything ~4×), but routing orders a queue nobody is enqueuing into, and
recycles pin their pane's account by construction. The pile-up and the under-exhaustion each have
a surface M7 did not touch:

- **W2-A `handoff-fire --recycle` account re-pick (the drain).** A recycle relaunches THE SAME
  pane with the SAME launcher (CMD composed at handoff-fire.sh:6279 from `$LAUNCHER`), so an
  account's pile can never shrink at the fleet's commonest seam — the idle free-win recycle. A
  recycle is a FRESH session continuing from DISK (worktree + plan + DoD are account-agnostic;
  no --resume), so account identity is not sticky for correctness — only for auth/launcher
  mechanics. Change: on recycle, consult `claude-accounts --route general`; when the pane's
  CURRENT account is non-routable-or-pressured (excluded, or route names another account and
  current k_eff/5h pressure exceeds it materially), compose the relaunch on the ROUTED account's
  launcher; `--assign` the new account; fail-soft to same-account on any doubt; kill switch
  `CC_RECYCLE_REPICK` (default on). Must-still-pass: recycle engagement scan (multi-account
  transcript resolve already exists, :298), goal re-arm (arm_goal after engage), pre_trust for
  the new config dir (RECYCLE_RELOC arm at :7608 is precedent).
- **W2-B urgency-aware per-account wave bounds (the demand).** `cc-wave-plan` caps every account
  at a flat `CC_WAVE_MAX_PER_ACCT=2` (bin/cc-wave-plan:57) — the urgent-underburned account gets
  the same allowance as a runway-rich one, so a wave cannot concentrate where quota strands.
  Change: derive per-account allowance from the rank it already parses (:293) + the M7 --json
  fields (weekly_need_pct_per_day / burn, k_work, KMAX): the TOP account whose need outruns its
  measured recent burn may take up to `CC_WAVE_MAX_PER_ACCT_URGENT` (default 4, never past
  KMAX−k_eff); everything else keeps the flat 2. Kill switch: unset/equal knobs ⇒ byte-identical
  today's plan.

**Execution locus: S ×2** — two dispatched sessions (this doc §14 is their shared design record),
fired `--account auto` so the M7 router routes them — the implementation wave IS the demand that
burns next3's stranding 11% tonight, and the fires are the first production exercise of the
`--assign` ledger. Origin (this session) holds custody + review; leads return via notify-back.

### §14.2 W2-B — DONE (2026-08-10, `f6b6c4e5`)

**Scope (frozen):** `bin/cc-wave-plan`'s flat per-account cap (`CC_WAVE_MAX_PER_ACCT=2`) becomes
urgency-aware — the TOP-ranked account whose weekly need outruns its measured recent burn may take
up to `CC_WAVE_MAX_PER_ACCT_URGENT` (default 4) tracks, never past `KMAX − k_eff`; every other
account keeps the flat cap. Kill switch: knob at/below the flat cap ⇒ byte-identical plans.

**Why this is the DEMAND half of M7.** §13 made the ROUTER urgency-aware: a fire now picks the
account whose quota is about to strand. It left the WAVE allowancer urgency-blind, so the two halves
disagreed — a wave still handed the expiring account exactly the 2 slots it handed an account with a
six-day runway. §13's own evidence run is the case: `next3` had to burn 11% in under 24h, and no
amount of correct *ranking* moves more than 2 items onto it in one wave. Ranking decides WHERE the
next item goes; the cap decides HOW MANY can go there at all, and only the second one can concentrate
a wave where quota is about to be lost.

**The design — one raised cap, four ways to refuse it.** `RCAP[i]` replaces the single
`MAX_PER_ACCT` in `place_item`; `apply_urgency()` raises exactly one entry. Placement ORDER is
untouched — the urgent account is still chosen by least-load and still de-prioritised while it is
carrying sessions; it just stops being *skipped* sooner. Every degradation path lands on the flat cap,
because each one is a widening and a widening on absent data is a widening on a guess:

| Refusal | Why it degrades to flat, not to urgent |
|---|---|
| knob ≤ flat cap | the kill switch — the SSOT is not even read, so the lane is provably inert |
| no `--json` snapshot, or `.router.KMAX` unreadable | the bound is what keeps the allowance honest; unbounded widening is not the smaller error |
| a row missing EITHER `weekly_need_pct_per_day` or `burn_wk_ppd` | a missing MEASUREMENT is not urgency. These are exactly the fields §13 documents as absent on a thin series, so "absent ⇒ urgent" would have shipped a silent widening the first quiet day |
| `KMAX − k_eff ≤ 0` | floor 0: an account at the concurrency ceiling gets nothing, urgent or not |

BEHIND is the producer's own predicate (measured < needed, `claude-accounts:1396`) and `k_eff` mirrors
`claude-accounts:1219-1221` (k_work where the sweep could measure it, else the pane census — absence
degrades to the STRICTER count — plus phantoms). Both are re-derived in the consumer only because
`--json` emits the terms and not the verdicts; no threshold is invented here.

**KMAX is read from the SSOT file, not from `--json`.** `--json` carries `s_cut` at top level but not
`KMAX`, and `bin/claude-accounts` is read-only for this change. So `cc-wave-plan` reads
`.router.KMAX` from `${CLAUDE_ACCOUNTS_JSON:-~/.claude/accounts.json}` — the same path and the same
env override the producer itself honours (`claude-accounts:127`), so the two sides cannot disagree
about which file is authoritative and one env var fixtures both. A missing or non-integer value is no
bound at all and therefore no urgency, never a hardcoded 8 (the constant is operator-tunable and has
already been hand-raised 4→8 once).

**The widening is never silent** (alarm polarity). One line names the account, need vs burn, the
allowance and the terms that bounded it — on stdout in text mode, on stderr under `--json` so the
machine plan stays pure — and it rides the IDL `fired`/`abstained` detail so the decision is auditable
after the fact. The capacity wall's message now states Σ per-account caps rather than
`accounts × flat`, which stopped being the capacity it enforced.

**Verified:** 21/21 `tests/cc-wave-plan.bats` (4 new urgency cases) + 74/74 in-binary selftest (11 new
urgency checks) + 27/27 `tests/cc-wave-plan-verdict.bats` + 12/12 `tests/cc-dispatch.bats` +
`test-hermeticity-lint` and shellcheck clean. RED-proof re-runnable through the
`CC_WAVE_PLAN_UNDER_TEST` seam (added here, mirroring the verdict suite): against `origin/main`'s
binary the (a)/(c)/(d) cases FAIL and (b) passes — correctly, since (b) asserts the fail-soft, which
is pre-change behaviour. The selftest carries its own control: `CC_WAVE_MAX_PER_ACCT_URGENT=2`
reddens exactly the six positive urgency checks and no others.

**Learnings.**
- **A widening test can pass against a tool that has no widening.** The floor-0 case was first
  fixtured with the full account at `k:8`, and it passed identically against a build with no floor —
  the ORDINARY load penalty (`RLOAD`, seeded from the same `k`) explained the placement on its own.
  Spending the ceiling as 8 PHANTOMS against a census of 0 leaves the load seeds tied, so only the
  floor can move the items. The tell was running the kill-switch control and finding that check still
  green (memory: `control-must-replay-the-real-artifact` — the control has to be able to fail).
- **Byte-identity needs a positive control on the same fixture.** "Armed == killed" is trivially true
  on a fixture nobody is BEHIND on, so the kill-switch test asserts it on the fixture that DOES
  trigger the widening and then asserts armed ≠ killed there — otherwise it passes against a kill
  switch that does nothing.
- **A new SSOT read is a new fixture surface** — the §13 learning, hit again one section later.
  `tests/cc-wave-plan.bats` does not fixture `$HOME` (the verdict suite does), so it would have read
  the operator's live `accounts.json` and let a hand-tunable constant decide its verdicts. Pinned via
  `CLAUDE_ACCOUNTS_JSON` in `setup()`.

**§14.2 Remainders:** R14-1 the allowance is a per-wave cap, not a per-wave TARGET — least-load
placement still spreads first, so an urgent account reaches its 4 only when the wave is large enough
to exhaust the others. Whether urgency should also bias placement ORDER (a load *discount*, not just
a higher ceiling) is a separate change with its own kill switch. R14-2 exactly one account per plan
may hold the allowance; a fleet with two accounts expiring inside the same day is not expressible
today, and deliberately so — a second urgent account is a second widening and wants its own evidence.
