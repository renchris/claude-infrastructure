# RESO_SECURITY_100P — every finding of the 2026-09-22 Cloudflare audit, driven to done

**Scope (frozen):** every unit the Cloudflare `security-audit` run left open on reso — the **6
confirmed** findings fixed and regression-pinned, the **20 needs_validation** leads each resolved to
CONFIRMED-and-fixed or REJECTED-with-evidence, the **2 structural facts** underneath them closed,
and the **19 surfaces the run did not cover** (17 out_of_scope + 1 deferred + 1 blocked) enumerated
rather than inherited as "covered". Nothing is optional. A lead that cannot be settled from source
is settled from the deployed fact, not dropped.

Source of record: `claude-infrastructure/docs/research/cf-audit-reso-actions-2026-09-22.md`
(landed; 6 confirmed / 20 leads / 8 rejected, enumeration of `src/app/actions/` COMPLETE at reso
`f87d878d0`). Artifacts: `~/security-audit-skill/reso-src-app-actions/run-1/` (96 files).
Method rules this plan obeys: `.claude/commands/exhaust-improvements.md` § Pass kind (P1–P5).

**Why this plan lives in claude-infrastructure and not in reso `docs/plans/`.** It was written
there first and refused at the land gate by `E3-add-requires-delete`: reso's `docs/` is under an
active consolidation programme (`DOCS_CONSOLIDATION_100P`, status open) that holds the corpus at
171/180 files and taxes every addition with a retirement. The only `status: complete` plan there,
`DEVICE_ENROLLMENT_BUILD.md`, carries 774 lines including *"Known issues carried forward, not
silently dropped"* and *"Traps that cost the research session real time"* — deleting it to buy shelf
space would destroy exactly what the INTEGRATE-never-overwrite rule protects. The superseded draft
that would have been the honest payment, `DEVICE_ENROLLMENT_100P.md`, was already retired by that
same programme. `.claude-plans/` is gitignored in reso, so a plan there would not survive a fresh
worktree — which is the one property a multi-wave programme plan must have. So it lives beside its
own source of record, `docs/research/cf-audit-reso-actions-2026-09-22.md`, and every wave brief
cites it by absolute path. If the consolidation programme later opens a slot, moving it is one
`git mv` and a retirement.

---

## Status — updated 2026-09-22 (INTEGRATE-only; nothing below is deleted)

| Wave | State | Evidence |
|---|---|---|
| **W1 — the 6 confirmed** | ✅ **DONE, all six landed on reso trunk** | #1 `88c951bf9` · #2 `1e07c9035` · #3 `6e5465a4e` · #4 `04157d23f` · #5 `4a6457901` · #6 `c8999cbce` |
| **W2/W3 — the 20 leads** | ✅ **all 20 adjudicated to verdicts** — 13 CONFIRMED · 5 REJECTED · 2 split. Fixes NOT driven, deliberately (below) | `docs/research/cf-audit-reso-lead-verdicts-2026-09-22.md` |
| **W4a-7a — de-action the non-auth published modules** | ✅ **DONE, landed** — 6 endpoints removed + the exact-path ratchet | reso `ae0edbf6d` |
| **W4 — the 2 structural facts** | **W4a ✅ DONE** — every W4a unit landed in W6 (below); the action boundary is validated and de-actioned: **92 → 65 registered Server Actions, 28 → 3 outside `src/app/actions/`** (fresh build census at reso `f12e70559`, positive control ✓). **W4b ⛔ operator-gated** — decision `fa0a110c1592` | § Wave 6 |
| **W5 — the 19 uncovered** | ✅ **DONE, landed** | `fa6539057`, `docs/research/cf-audit-reso-uncovered-surfaces-2026-09-22.md` |
| **W6 — release the held units** | ✅ **DONE — all 8 units landed on reso trunk, each fix with a regression test red on its parent** (2026-09-23). W6-sync `c38d6b230` `db2d2c0a1` `43de03d9a` `52dee0cfe` `754a4693d` · W4a-1 `d05d243e2` `a9ef80482` `22a2e323c` `490aa1b4d` · W4a-6 `1b5c9f2f6` `217be7a6c` `b86fcd583` `25849ec6f` `c5655be5b` · W4a-5 `eabed52dc` `8430c32e6` `0b1bb2f41` · W4a-3 `c11b6fe20` `ebf055350` `b3d937d09` · W4a-4 `354e4b0d3` `ba51f76d6` `8a7a92a12` · W4a-7b `57df1cc63` `88d570828` · W4a-2 `3a94da90b`. **Final verification on a clean worktree at reso `f12e70559`:** 78 touched paths all present by `git ls-tree`; `CI=true VITEST_TIMEOUT_FACTOR=4 pnpm test:unit` 419 files / 5275 passed / 0 failed; `pnpm build` rc 0; census rc 0. Found and fixed beyond the briefs: an open redirect in `redirectToSubdomain` (W4a-3). No `/deploy`, no schema migration, guest_consent untouched | § Wave 6 |
| **W6 lead reads** | ✅ both done and landed `6e10e8d72`: **venue scoping is ON in live tenant `key`** (leads 5, 14, 15 live, not latent; lead 11 stays REJECTED on one leg) · **the deployed AWS key is `guestlistAdmin` with `AdministratorAccess`** (lead 7 impact = worst case) | verdict doc § MEASURED 2026-09-22 |
| **W6 operator filings** | ✅ lead 9 rotation → decision `bf9093e859b8` · W4b re-key → decision `fa0a110c1592` · AWS key re-scope → operator step `436d0883bd2d` | `cc-decide list --open` · `cc-backlog list --blocked` |
| **W6 grown scope** | W4a-6 owns `lib/auth/platform-email.ts`, `.env.example`, `scripts/setup/bootstrap-region.pure.ts` (its `isPlatformEmail` is now an EXACT allowlist, so `PLATFORM_OPERATOR_EMAILS` must be set before the next `/deploy` — filed on land) · W4a-5 owns `lib/operational-detail.ts` · W4a-7b owns 3 import re-points (`formActions.ts`, `lib/useConditionalPasskeyLogin.ts`, `lib/runPasskeyUpgrade.ts`) | peer mail 2026-09-22 |
| **ship-land.sh:890 ref-lock fix** | ✅ **landed** reso `c8eed1e25` (red on parent, 29/29 green) — it bit twice more during W6, which is its own receipt | — |
| **W6 lead follow-ons** | ✅ `qa-nightly-probe.test.ts` bound fixed ports and rejected concurrent lands → port 0, reso `0c0b1b37c` · the watermark-race 503 (lead 12) was counted by the push route's permanent-failure canary → transient, reso `f12e70559` · operator step `48717fa6f3ed`: set `PLATFORM_OPERATOR_EMAILS` before the next `/deploy` · operator's landing-congestion question → dedicated research session (pane 621) writing `docs/research/reso-landing-architecture-2026-09-22.md` | — |
| **W5 follow-on** | ✅ one confirmed hole from W5's own candidate set CLOSED on trunk: `setGuestSession` is no longer a registered Server Action | reso `sec-w3a-tenantctx` |

**The plan's own Phase 0 was overtaken and that is recorded rather than hidden.** W1 ran as four
dispatched sessions as written, and W5 ran in parallel as written. W2/W3 did **not** need the
planned 3 dispatched sessions plus a lead-inline pass: an 8-axis read-only adjudication wave settled
all 20 in one pass, because a lead needs a *verdict*, not an owner — the owner is only needed once a
verdict says CONFIRMED. The W2/W3 split by "source-settleable vs deployment-fact" also did not
survive contact: the decisive instrument turned out to be a **build**, not a deployment read.

🚨 **Why 13 CONFIRMED leads landed 0 fixes, and why that is compliance rather than timidity.**
reso's own calibration note 5 (`.claude/commands/exhaust-improvements.md`) reads verbatim:
*"Auth/sync findings → queue + escalate, never silently land mid-sweep."* Every remaining CONFIRMED
lead is auth-, authz- or sync-class. This plan's § Known issues already said the same thing in its
own words. Three of them have fixes that are byte-identical on the normal path and were still not
driven for that reason; they are named in the verdict doc under § Three fixes are landable-now.

**The one measurement that closes or arms four leads at once** is the live value of
`tenant_config.enable_venue_scoping` per tenant DB. Leads 5, 14 and 15 arm the moment it flips on;
lead 11 closes twice over if it is off everywhere. `venue-authz.ts:63-64` asserts it is off in a
comment — a claim with a shelf life, not a measurement.

### What is left, and what blocks it

*Recorded 2026-09-22 by the cloud worker on backlog item `0c82f0811877`.* Section headings below were marked from the table above (they all read PENDING because only the
table carried state). **No remaining unit can be advanced by a claude-infrastructure worker.** Every
open unit edits reso, and each one waits on one of two operator acts:

1. **Operator ruling on calibration note 5 for the 13 CONFIRMED leads** (auth/authz/sync class).
   It releases W4a-1, W4a-2, W4a-3, W4a-6 and W4a-7b, and the three landable-now fixes (leads 12
   second half, 13, 17). W4a-4 and W4a-5 are not auth-class, but they carry leads 16 and 5, so they
   need a reso-scoped session.
2. **The live `tenant_config.enable_venue_scoping` read per tenant DB, plus the W4b go/no-go**
   (username → id re-key plus backfill across 8 live tenant DBs, G2).

Until one of those happens, re-dispatching this plan finds nothing to do. Park it with
`cc-backlog block`. Do not reopen it.

### The correction this programme owes its own source of record — DONE (W4a re-scoped to the build census; § W4a — Phase 0 decomposition)

Structural fact #1 — every export of a `'use server'` module is a network-reachable POST endpoint —
is directionally right and **too strong**. Next registers only what its build graph reaches, and
`reso scripts/audit-server-actions.mjs` now reads that off the build with a mandatory positive
control. It refuted the stated attack vector of leads 3, 4 and 14 and confirmed leads 1 and 18.
**W4a should be re-scoped against that census**: the action boundary needing runtime validation is
92 registered exports, not every export of 35 modules.

---

---

## Phase 0 — Agent Team Orchestration — SUPERSEDED (overtaken as recorded in § Status; W4a carries its own Phase 0 block)

### Execution locus per wave — SUPERSEDED (see § Status)

| Wave | Locus | Why (T and L only) |
|---|---|---|
| W1 — the 6 confirmed | **S** ×4 dispatched sessions | default |
| W2 — the 20 leads, source-settleable half | **S** ×3 | default |
| W3 — the 20 leads, deployment-fact half | **L** lead-inline | each is a *read* of live infra (IAM policy, deployed env, Turso token scope) plus one operator question; there is no code to own, and splitting a question set across sessions duplicates the asking |
| W4 — the 2 structural facts | **S** ×2 | default |
| W5 — the 19 uncovered surfaces | **S** ×1 (a Cloudflare enumeration, not an edit wave) | default |

**Locus S recipe** (every S wave, verbatim):
`scripts/handoff-fire.sh --prompt-file <brief> --worktree <branch> --notify-back <lead-uuid> --account auto --split-right --goal '<end state> — proven by <command the session prints>; do not <constraint>'`, lead arms `cc-await-ping` in background.

### Task size band — SUPERSEDED (see § Status)

Every brief is written to **40–150K output ≈ 30–75 min ≈ 60–110 turns ≈ 3–6 files**. Never below
20K. Split above 300K or 10 files. The band is a sizing target and does NOT relax the agent-teams
caps: ≤150-line brief body, reading list ≤5 files, split any deliverable >500 LOC.

### Team roster, dependency graph, worktrees — SUPERSEDED (see § Status)

**Single owner per file is the hard constraint here** — three of the six confirmed findings live in
ONE file (`operationBuilder.ts`), so they cannot be three units.

| Unit | Owns (single owner) | Fixes | Worktree / branch | blockedBy |
|---|---|---|---|---|
| **W1a** | `src/app/actions/replicache/operationBuilder.ts` | #3 erasure substring pattern · #4 erasure omits phone/outbox · #6 client-supplied `actual_spend` | `sec-w1a-opbuilder` | — |
| **W1b** | `src/app/actions/auth/databaseActions.ts` + **the migration journal (sole owner)** | #2 `deleteUser` leaves identity-keyed rows, frees username | `sec-w1b-deluser` | — |
| **W1c** | `lib/auth/session.ts` | #1 revocation check fails open on absent user row | `sec-w1c-revocation` | — |
| **W1d** | `tenantConfigActions.ts` · `venueRoleActions.ts` | #5 admin gate reads sealed cookie role | `sec-w1d-livehrole` | — |
| **W2a–c** | per-lead, disjoint | leads 1–15 source-settleable subset | `sec-w2{a,b,c}-*` | W1 land |
| **W3** | no files | leads needing a deployed fact | — | W2 |
| **W4a** | runtime schema validation at the action boundary | structural fact 1 | `sec-w4a-schema` | W1, W2 |
| **W4b** | authz keys `user.username` → `user.id` + migration | structural fact 2 | `sec-w4b-userid` | W1b (migration order) |
| **W5** | audit artifacts only | the 19 uncovered units | `sec-w5-enumerate` | — (parallel with W1) |

**Spawn wave order.** W1a·W1b·W1c·W1d and W5 fire together (5 concurrent, under the 6 cap, disjoint
files). W2a–c fire after W1 lands. W3 is lead-inline after W2. W4a·W4b fire last — they touch
everything W1 touched, so they must rebase onto landed W1.

**Merge discipline.** Rebase onto `origin/main`, `--ff-only`, serialized, **smallest diff first**,
each gated by `pnpm typecheck` + `pnpm lint` + `pnpm test:unit`. `git rerere` is on. W1b owns the
migration journal alone; W4b's migration lands only after W1b's.

### Lead context budget + succession point — SUPERSEDED (see § Status)

- **Reserved for leading: ≥50%.** The lead writes briefs, adjudicates verdicts and merges; it does
  not implement. W3 is the single exception and is deliberately small.
- **Succession point: after W2 lands.** The lead recycles (`handoff-fire.sh --recycle`) before W4,
  because W4 is the largest wave and the lead entering it above ~50% fill cannot adjudicate a
  cross-cutting refactor. If fill reaches ~50% earlier, recycle at the nearest wave boundary
  instead — the plan file is the bridge.

---

## Wave 1 — the 6 confirmed findings — DONE (all six on reso trunk, § Status)

Each unit: fix, add a regression test that FAILS on the pre-fix code (prove it by running it against
`git stash`ed source or the parent commit), run the three gates, land.

### W1a — `operationBuilder.ts`, three findings, one owner — DONE `6e5465a4e` `04157d23f` `c8999cbce`

1. **#3 (high) — guest erasure redacts unrelated audit rows tenant-wide.**
   `operationBuilder.ts:1599-1605` passes the client's guest id into a SQLite `instr()` substring
   match over the whole append-only `mutation_log`. Only gate `isManagerOrAbove`; only check
   `typeof !== 'string'`. **Fix direction:** match on the id as a *value*, not a substring — the
   record's own remediation is in `findings.json`; read it before re-deriving. **Decision to
   surface, do not take silently:** this path is irreversible and has no restore, so the fix must
   also answer whether a redaction should be transactional + logged.
2. **#4 (medium) — erasure leaves the E.164 phone and queued message bodies.**
   `guest_channel_binding` and `guest_message_outbox` key on `guest_profile_id` and no production
   path deletes from them. Fix inside the same cascade at `:1494`. **Do NOT** delete the
   `guest_consent` row — the audit narrowed the finding in the target's favour on this point
   (consent revocation is a column by design; CTIA §5.1.2 names captured IP as opt-in evidence).
3. **#6 (medium) — `createReservation` writes client-supplied `actual_spend`** verbatim on INSERT
   and on tombstone-resurrection UPDATE (`:3106`), propagating into `guest_profile.total_spend` and
   auto-tier thresholds. Three sibling modules already declare the column server-derived — follow
   that precedent; the repo already classed the identical shape on the adjacent column as a defect.

### W1b — `deleteUser`, and the only migration in W1 — DONE route (a) `1e07c9035`; route (b) is W4b

**#2 (high).** `databaseActions.ts:581` deletes the user and credential rows only. No migration
declares FK or `ON DELETE` for the identity-keyed tables, so a removed member keeps live push
delivery and a later invitee under the freed handle inherits their list access.

**Two routes — pick in the brief, state the choice in the commit:** (a) application-level cascade
inside one transaction; (b) schema FKs with `ON DELETE`. (b) is the durable fix and is a **schema
migration on a live multi-tenant fleet** — it is a G2 escalation surface, so W1b STOPS and asks
before any `DROP`/destructive step. (a) is landable now and is the safe first increment. Do both in
order, never (b) alone.

### W1c — revocation fails open — DONE `88c951bf9`

**#1 (medium).** `lib/auth/session.ts:159`
`if (row && (user.credentialsVersion ?? 0) < row.credentialsVersion)` — `row` is absent in exactly
the case the check exists for, so a deleted user (including a deleted platform operator) stays
signed in for the cookie's life. Fix: absent row ⇒ revoked. The audit searched for a legitimate flow
depending on the fail-open and found none — re-run that search before landing, and record it.

### W1d — admin gate reads the sealed cookie role — DONE `4a6457901`

**#5 (medium).** Four actions authorize on the cookie's sealed role, not the live DB role:
`tenantConfigActions.ts:37,:78` and `venueRoleActions.ts:67,:127`. A just-demoted admin keeps
privilege-administration authority until cookie expiry — including `updateTenantConfig`, which can
set `enableVenueScoping` false and no-op every per-venue gate in the tenant. The repo's own
`accessActions.hasAdminAccess` re-reads the live role and its comment names this defect verbatim;
commit `2850782c6` applied it to a read path. **Fix = extend that existing helper to these four call
sites.** No new mechanism.

---

## Wave 2 / Wave 3 — the 20 leads, each to a verdict — IN PROGRESS (20/20 verdicts in; 13 CONFIRMED fixes held for the operator ruling)

A lead is not a finding. Each resolves to **CONFIRMED → fix (W1 discipline)** or **REJECTED → the
evidence that rejects it**, recorded in the audit doc. Dropping one is out of scope of this plan.

**The split is by what blocks them, which the audit already counted:** 19 of 20 carry the no-sandbox
blocker *and* a deployment/data-state/third-party fact; 1 carries only the latter.

- **W2 (S ×3, source-settleable):** leads whose decisive fact is in the repo once someone traces it
  — 3 (`consumeInvitationAndRegister` never tests `verified`), 6 (invitation pins email+role but not
  username), 10 (client-group ownership bound to username), 11 (pull resolves visibility tenant-wide
  while push is per-venue), 12/13 (idempotency watermark read outside its transaction; gap-consume
  persists a client-chosen watermark), 14 (`createEvent` unchecked `table_map_id`), 15 (erasure
  cascade hard-deletes cross-venue behind a tenant-global check), 17 (`toClientSafeMutationError`
  two-entry denylist), 20 (web-push fan-out unbounded, limiter meters calls not messages).
- **W3 (L, deployment facts + operator questions):** 2 (`deleteDatabase` guard vs shared parent
  schemas), 4 (`initializeDB` unauthenticated, composes the libsql URL from caller input), 7
  (`invokeLambdaFunction` branch vs target tenant), 8 (platform-operator authority from a
  tenant-writable email string), 9 (public Pusher channels with a repo-literal publish credential),
  18 (`getPlatformDB` ungated, returns a control-plane client), 19 (`LOCAL_TEST_*` repoint the
  tenant DB ahead of the sealed tenant), 1 (WebAuthn expected-challenge setter), 5 (tonight seed
  ungated), 16 (`saveSubscription` endpoint URL validation).
  **These need facts only the operator can supply or authorize reading:** the deployed scope of
  `TURSO_PLATFORM_API_AUTH_TOKEN`, the IAM policy behind `AWS_ACCESS_KEY_ID`, whether `LOCAL_TEST_*`
  exist in the deployed env, and whether any live tenant has `enable_venue_scoping` on. W3's
  deliverable is those questions asked as ONE batch with the measurement each answer unblocks — not
  a series of stop-asks.

⚠️ **Leads 4, 8, 9, 18 and 19 describe unauthenticated or credential-returning surfaces.** If any
confirms, it is a stop-surface-now, ahead of the rest of this plan.

---

## Wave 4 — the two structural facts — IN PROGRESS (W4a-7a + W4a-8 landed `ae0edbf6d`; rest ruling-gated)

**W4a — no runtime schema validation anywhere in the action surface.** No zod, no valibot; every
server-action parameter type is erased at runtime. Finding #6 is downstream of this. Introduce
validation at the action boundary, starting with the actions W1 touched, then the rest of
`src/app/actions/`. Sized to split: this is >500 LOC and >10 files, so it is a wave of units, not
one unit — decompose it in its own Phase 0 block before firing.

### W4a — Phase 0 decomposition (added 2026-09-22, after the registered-action census) — IN PROGRESS

The plan sized W4a as *">500 LOC and >10 files, so it is a wave of units, not one unit — decompose
it in its own Phase 0 block before firing."* This is that block.

**The boundary is 92 registered actions, not "every export of 35 `'use server'` modules".** That
number is measured, re-derivable in one command, and roughly a third smaller than the surface the
plan assumed: `pnpm build && node scripts/audit-server-actions.mjs` (landed reso `ed145bc7d`).
**64 inside `src/app/actions/`, 28 outside it** — and those two halves need *opposite* repairs.

🚨 **For the 28 outside, validation is the WRONG fix.** A library module published as a POST
endpoint should stop being an endpoint; adding runtime validation to it hardens a surface that
should not exist and leaves the surface. `setGuestSession` is the worked example: the repair was
deleting the directive and adding `server-only`, not validating its two arguments. reso has already
run this de-actioning sweep three times on its own — `sessionWrite.ts`, `authQueries.ts`,
`credentialDbWrites.ts` are shipped siblings — so this is following an in-repo precedent, not
inventing one.

| Unit | Owns (single owner per file) | Registered actions | Note |
|---|---|---|---|
| **W4a-1** | `auth/databaseActions.ts` | 14 | The largest single file and the invitation/user surface. Alone. Sequence AFTER the lead-8 ruling — that fix lands in `sendInvitation`, in this file |
| **W4a-2** | `auth/cookieActions.ts` | 11 | ⚠️ **Blocked on the lead-1 ruling**, which *moves six of these out* of the module. Validating them first is work the move discards |
| **W4a-3** | `auth/provisionActions.ts` · `auth/domainActions.ts` · `auth/lambdaActions.ts` | 12 | Provisioning + tenant resolution. Carries lead 7's target-vs-branch fix |
| **W4a-4** | `notifications/notificationActions.ts` · `notificationHistoryActions.ts` | 5 | Carries lead 16: lift `api/notifications/subscribe/route.ts:13-40`'s validators into a shared module — this unit's validation already exists, in the sibling writer |
| **W4a-5** | `homeStateActions.ts` · `recapSeedActions.ts` · `listsSeedActions.ts` · `loginHistoryActions.ts` · `navWarmActions.ts` · `operationalHistoryActions.ts` | 10 | The SSR seed/read surface. Carries lead 5 and the one `deferred` unit from W5 |
| **W4a-6** | `tenantConfigActions.ts` · `venueRoleActions.ts` · `auth/accessActions.ts` · `auth/platformActions.ts` · `auth/tenantContext.ts` | 12 | The authz/config surface. Carries leads 2, 18 and 19 |
| **W4a-7a** | `lib/venue-resolution.ts` · `lib/tenant-display.ts` · `(app)/bottle-service/.../_data/seed.ts` | 6 | ✅ **DONE — landed `ae0edbf6d`.** Six live endpoints removed; registered actions 89 → 83. `drizzle/rp.ts` and `lib/feature-flags.ts` were dropped from this unit on measurement: both carry the directive but have **zero registered exports** (tree-shaken), so de-actioning them is hygiene with no live endpoint behind it |
| **W4a-7b** | `drizzle/db.ts` · `lib/auth/{aaguid,login,register,session,upgrade}.ts` | 20 | Same repair, but these ARE auth/session class, so calibration note 5 binds and they wait on the ruling. `drizzle/db.ts` alone publishes 7 exports including `getOpenedDatabaseURL` and `getNamedDB` — the sink lead 4 names |
| **W4a-8** | the ratchet | — | Extend `eslint-rules/no-ungated-db-export.mjs`, which is **structurally blind** here: it fires on a DB-ACCESS signal, so a cookie write, a returned handle and a `migrate()` call all evade it. The exact-path list in `lib/auth/guest-session.test.ts` is the interim ratchet |

**Sequencing.** W4a-7a and W4a-8 were independent of every operator ruling and fired first — they
remove surface rather than harden it, and neither touches an auth module. **Both are now landed**
(`ae0edbf6d`): six endpoints gone, and the ratchet pins the exact remaining set of 13 `'use server'`
modules outside `src/app/actions/` (10 debt, 3 legitimately client-called). W4a-4 and W4a-5 follow. W4a-1, -2, -3, -6 and -7b each carry a
CONFIRMED lead or an auth module and must wait on the ruling that releases it, or they will be
rewritten by it.

⚠️ **The split above is the correction of a first draft of this very block**, which put all 28
outside-exports in one drivable unit. Five of those modules are `lib/auth/*` and one is
`drizzle/db.ts` — de-actioning them is exactly the auth/session change note 5 exists to hold. A
unit list is a claim about risk class, not just about file count.

**Red-proof for every unit in this wave is the same instrument**, and it is cheap:
`node scripts/audit-server-actions.mjs --assert-absent <export>` for a de-action, plus the unit's
own validation tests. Its positive control is mandatory — every result here is a negative.

**W4b is unchanged and remains operator-gated**: re-keying authorization off `user.username` onto
`user.id` is a SQLite table rebuild plus backfill across 8 live tenant DBs. It is already filed as
"route (b), PENDING AN OPERATOR RULING" in `1e07c9035`'s own commit body, and leads 6 and 10 are
cured-in-the-forward-direction only — no backfill shipped, so handles freed before 2026-09-22 still
carry orphan grant rows in live tenants.

**W4b — authorization tables key on `user.username`, a recyclable TEXT handle.** Findings #2 and
leads 6 and 10 are downstream. Re-key to the immutable `user.id`. This is a schema migration plus a
data backfill on a live fleet — G2, operator-gated, and it lands only after W1b's migration.

---

## Wave 6 — THE RULING IS GIVEN: release every held unit (added 2026-09-22) — DONE (§ Status)

**Operator directive, 2026-09-22, verbatim: "How about all the other waves until exhaustive
completion?" then "drive to completion please".** That is the escalation reso's calibration note 5
asks for (*"Auth/sync findings → queue + escalate, never silently land mid-sweep"*): the findings
were queued and escalated, and the operator has now directed them landed. So every unit above that
reads "waits on the ruling" is RELEASED. Nothing in this directive releases the three things below
that are not fixes but acts on live infrastructure — see § Still the operator's.

**Execution locus: S, one dispatched session per unit, fired from a lead that holds ≥50% of its
window.** The W4a table above is the roster; two additions and one ownership split make it
complete:

| Unit | Owns (single owner) | Carries | Red-proof |
|---|---|---|---|
| **W4a-1** | `auth/databaseActions.ts` | validation (14) · lead 8 *defence half*: `sendInvitation` refuses a platform-domain email unless the caller is platform · lead 3 debt: re-test `verification.verified` inside `consumeInvitationAndRegister` · W1b packet Q3: removing an admin revokes that admin's pending invitations | tests red on parent |
| **W4a-2** | `auth/cookieActions.ts` (+ `lib/auth/login.ts` if a setter moves there) | lead 1: the expected-challenge setters stop being registered actions — `login.ts:135-137` calls the challenge "the SOLE replay defense" · validation of the rest | `audit-server-actions.mjs --assert-absent` both arms + tests |
| **W4a-3** | `auth/provisionActions.ts` · `auth/domainActions.ts` · `auth/lambdaActions.ts` | lead 7: bind the target `subdomain`/`group` to the sealed tenant unless the caller is platform-authorized for cross-tenant · validation | tests red on parent |
| **W4a-4** | `notifications/notificationActions.ts` · `notificationHistoryActions.ts` · `lib/…/pushTransport.ts` · `notificationDispatch.ts` · `lib/rate-limit/durable-limiter.ts` | lead 16: lift `api/notifications/subscribe/route.ts:13-40`'s validators into one shared module; at send time strip the trailing dot and refuse a non-443 port · lead 20: per-user subscription cap + a concurrency bound on the fan-out | tests red on parent |
| **W4a-5** | the seed/read files listed above | lead 5: gate `tonight[].event` and `getTonightEntriesSeed` with `activeVenueInPullScope` · the W5 `deferred` unit `getOperatorShiftDetail` | tests red on parent |
| **W4a-6** | `tenantConfigActions.ts` · `venueRoleActions.ts` · `auth/accessActions.ts` · `auth/platformActions.ts` · `auth/tenantContext.ts` | lead 8 *core half*: platform authority must not derive from a tenant-writable email — `isPlatformEmail` is a bare `endsWith` after stripping plus-addressing (also closes decision `ef79469fbb12`, "every provisioned tenant's `admin+<sub>@reso.gl` passes the platform gate") · lead 2: the serving guard must also refuse `parent-schema-database-*` · lead 18: `getPlatformDB` off the action surface · lead 19: `LOCAL_TEST_*` refused when `NODE_ENV=production` | `--assert-absent` + tests |
| **W4a-7b** | `drizzle/db.ts` · `lib/auth/{aaguid,login,register,session,upgrade}.ts` | de-action (20 registered exports) · lead 4's sink: validate `organizationName`/`group` against a strict alphabet before they compose a libsql authority. ⚠️ Do NOT add `import 'server-only'` to anything in the tsx-run `drizzle/` DB-setup graph — plain Node cannot resolve it (`databaseActions.ts:68,:93`) | `--assert-absent` + tests |
| **W6-sync** *(new)* | `replicache/pushActionsBatch.ts` · `batchPrefetch.ts` · `operationBuilder.ts` · `operationBuilder-shared.ts` | lead 13: persist `Math.min(mutation.id, prevLastMutationID + 1)` at `pushActionsBatch.ts:462` · lead 12: compare-and-set `WHERE last_mutation_id < N` on the UPSERT at `operationBuilder.ts:3439` AND re-assert the watermark inside the transaction · lead 14: `createEvent` checks `tableMapID` existence + venue coherence exactly as `updateEvent` does at `:1381-1393` · lead 15: RAISE the `deleteGuestProfile` gate to match its cross-venue blast radius — never narrow the deletes (no `venue_id` on `guest_profile`; PIPEDA) · lead 17: `return raw` → a generic line, and rewrite the pass-through test whose premise is false | tests red on parent |

**Lead 8 is split across W4a-1 and W4a-6 on purpose** — its two halves live in two files, and
single-owner-per-file outranks keeping a lead in one unit. W4a-6's half is the fix; W4a-1's is
defence in depth.

🚨 **Two landmines every W6-sync brief must carry verbatim.** (1) DO-NOT-FIX #1: Replicache
mutations apply sequentially with `for…of` + `await` — `Promise.all` there is silent data loss.
(2) lead 12's in-transaction re-assert introduces a new 5xx at the transaction boundary; that is a
sync-contract change the operator has now directed, so state it in the commit body rather than
hide it.

**Wave order.** Eight units, disjoint files. Fire in two batches of four against the box's
active-session ceiling of 8 (`handoff-fire.sh` refuses past it): batch 1 = W4a-6, W4a-1, W6-sync,
W4a-7b (the critical and high leads); batch 2 = W4a-2, W4a-3, W4a-4, W4a-5. Lands serialized,
smallest diff first.

**Two reads the lead does inline, read-only, while batch 1 runs:**
1. `tenant_config.enable_venue_scoping` in every active tenant DB, via the sanctioned in-process
   bridge `lib/provisioning/group-token-ssm.ts` (a prior session read a tenant DB this way; the
   secret is never hand-read or persisted). Off everywhere ⇒ lead 11 closes twice over; on anywhere
   ⇒ leads 5, 14, 15 are live today, not latent.
2. The IAM policy behind `AWS_ACCESS_KEY_ID`, read-only (`aws iam` get/list only) — lead 7's
   *impact* half. The source fix in W4a-3 lands regardless.

### What wave 1 taught, carried into every W6 fire

- **Pass `--repo ~/Development/reso-management-app` explicitly.** `handoff-fire.sh` resolves the
  repo from the FIRING session's cwd, not from its help text's default; a dry-run is what caught it.
- **A "never engaged" fire verdict was false 2 of 2 times.** Check the worktree for writes and the
  transcript for growth before any re-fire; the real cost is that no `/goal` armed, so send the DoD
  by `cc-notify` in its place.
- **Land with the test band declared: `CI=true VITEST_TIMEOUT_FACTOR=4`.** reso's own
  `vitest.config.ts:9,55` rule is that the caller declares its band; the land path declares none,
  so under concurrent lands every unit reddened on a foreign timeout with zero assertion failures.
  Held for all four W1 units at load ~250.
- **Verify every land by content** (`git ls-tree` + empty `git diff origin/main`): ship-land
  rebases, so a pre-land sha is never an ancestor of trunk.
- **`ship-land.sh:890` misclassifies GitHub's ref-lock CAS rejection** (`cannot lock ref … is at X
  but expected Y`) as "REJECTED and NOT by a race"; re-running IS the fix. Widen that glob — after
  the wave, never while units are landing through the script.

### Still the operator's — not released by the directive, and why

- **Lead 9 — rotate the Soketi publish secret.** Rotation is a live-credential write that must set
  Soketi env/config AND SSM AND the region Fly secrets together, per region; flipping the code half
  first silently breaks pokes for ~6 of 8 tenants. The code half lands only after the rotation.
- **W4b — re-key authorization tables from `user.username` to `user.id`.** A table rebuild plus
  backfill on 8 live tenant DBs, and measured 2026-09-22 on local `sqld 0.24.32`:
  `PRAGMA foreign_keys` defaults ON and **`=OFF` does not take**, so the 12-step rebuild's own
  bracket is a no-op once any FK exists. Needs a ruling AND a hosted-Turso measurement first. W1b's
  packet holds the SQL, backfill and rollback:
  `docs/research/reso-w1b-route-b-fk-packet-2026-09-22.md`.
- **`/deploy`.** Every unit lands; none deploys.

---

## Wave 7 — lead 9, the realtime publish secret — RULED 2026-09-23 · Phases 1+2 DONE (all 5 regions rotated) · Phase 3 in flight

**Operator ruling, 2026-09-23, verbatim:** "Proceed as you recommend for the long-horizon end-game
100th percentile absolute perfection implementation." Decision packet `bf9093e859b8` (conviction 88%
after research: the secret is Soketi's documented default and the client bundle ships the matching
default `app-key`, so it is guessable without the repo; impact is disruption only — forged
`deployment-event` reloads capped at 3 per device per 5 min by `lib/reload-guard.ts:18-19`, forged
pokes cause pull storms, no data read or written; a botched switch degrades to 60 s polling, never an
outage).

**Design (ruled):** a random 32-byte key PER REGION, source of truth SSM SecureString
`/amplify/djnbdqpvc08g4/main/SOKETI_APP_SECRET_<STEM>`; never in a tracked file or `.env.local` (a
laptop needing prod pokes resolves it from SSM at run time, as `resolveGroupToken` does for DB tokens).
Enforcement keys on "is this a deployed server" (`FLY_APP_NAME || AWS_LAMBDA_FUNCTION_NAME`), never
`NODE_ENV`, so `pnpm dev`, `pnpm build`, and a local `pnpm build && pnpm start` keep working. This
supersedes the "code half lands only after the rotation" line above: dual-secret signing makes the
code safe to land FIRST.

| Phase | What | Locus | State |
|---|---|---|---|
| **1** | send-poke signs with `SOKETI_APP_SECRET_<STEM>`, retries once with `_PREVIOUS` on 401/403 (fallback family too); every other publisher (`scripts/notify-deployment.sh`, qa, load, firedrill, smoke) env-sourced; Oregon `soketi-config.json` templated from SSM; bootstrap guard ALLOWS a non-default key, refuses `app-secret`; `scripts/rotate-soketi-secret.sh <region>` with typed-yes gates, `--dry-run`, re-run safety | S — pane 635, brief `/tmp/fire-sec-lead9-rotation.txt` | ✅ **LANDED** reso `36f77a4e0`..`e447e8d79` (34 paths, full unit suite + build green) + follow-up `52d644c97` `b7959d233`: the script reads each server's CURRENT key from the server's own config (Fly `SOKETI_DEFAULT_APP_SECRET` presence + on-machine sha256; Oregon `config.json` sha256 via read-only send-command), never from SSM. Script name is `scripts/rotate-soketi-key.sh` (a user deny rule blocks file tools on `*secret*` paths). Soketi rejects a bad key with HTTP 200 + a `code:401` body — both publishers read the body |
| **2** | Operator runs the script per region, in that region's daytime: SSM → app side (new + `_PREVIOUS`=old, incl. apps whose `_FALLBACK` targets this server) → server side → verify by effect (new 200, old 401) → clear `_PREVIOUS`. **Oregon stops mid-script for one `/deploy`** (Amplify env is baked at build) | operator | ✅ **DONE 2026-09-23** — all 5 regions rotated (dfw, iad, oregon, lax by the operator via `! … --confirm <region>`; sin by the agent at the operator's request, 06:40 SGT after close). Verify-only at reso `4e118b519`: all five ROTATED from the servers' own config. The live runs surfaced four script defects, each fixed with a red-on-parent test: consent needed a keyboard (`--confirm`, `ff98573c2`); an autostopped holder refused the census (`03d51299d`); the `/deploy` check could never pass — `--max-items` prints a `None` paging line — and re-runs restarted holders that already held the key (`44a31e5f1`); a stopped Soketi server refused the key read (`4e118b519`). Their `/deploy` shipped Wave 6 live: `origin/release` `7f84a45c2` → `03d51299d` after a fresh verifier-green stamp (the verifier was unscheduled; production was 162 commits behind) |
| **3** | Remove the literal fallback on deployed servers (fail loud at send time), bootstrap guard REQUIRES a non-default key, drop `_PREVIOUS` handling if unused | S — fire after Phase 2 reports all 5 regions | ▶ **in flight** — pane 644, brief `/tmp/fire-sec-lead9-phase3.txt`; goes live at the next `/deploy` (every deployed holder already carries its key) |

**Found by the Phase 1 dry runs (2026-09-23), recorded so no one trusts SSM again:** SSM already
held `SOKETI_APP_SECRET_LOS_ANGELES` (2025-12-20, non-default), `_SINGAPORE` (2026-01-11 — hashes to the
STOCK key) and `_OREGON_FALLBACK` (2026-03-22, plain String) — written long before this work, never
matched to a server. The LA value is not what `soketi-lax` runs. The first cut of the script inferred
state from SSM and would have called LA "rotated", then kept the stale value as `_PREVIOUS` on a
forced re-run — nudges lost between steps c and d. Fixed in `52d644c97`: the server's own config is the
truth. Phase 3 inventory (from the Phase 1 session): send-poke's 12 literal fallbacks, notify's
`LEGACY_STOCK_KEY`, deploy-soketi-config's legacy branch, `caddy-migration.sh:131` (historical).

Found during the ruling's research, recorded so it is not rediscovered: the checkout's `.env.local`
points Oregon, Los Angeles and Singapore at the PRODUCTION Soketi hosts with the default secret, so a
laptop running against a production tenant can nudge real staff devices today. After Phase 2 those
local nudges are refused (local sync falls back to polling) — deliberately; do not copy the new keys
into `.env.local`.

---

## Wave 5 — the 19 surfaces this run did not cover — DONE `fa6539057`

Not a fix wave: a Cloudflare enumeration over the recorded `out_of_scope` units so a later whole-repo
pass turns them into current work rather than inheriting a false "covered" (P2). The 17 include
`src/middleware.ts#request middleware`, `src/app/api/replicache-push/route.ts#POST`,
`lib/auth/**#module 'use server' exports`, `drizzle/db.ts#getDBAndGroupForSessionTenant`,
`lib/messaging/guest-message-outbox.ts#enqueue and drain`, and the guest claim surface. Plus the
**1 deferred** unit (`operationalHistoryActions.ts#getOperatorShiftDetail`, reason
`late_uncovered_no_remaining_wave`) and the **1 blocked** unit
(`replicache/pullActions.ts#pull entrypoint`).

By P3 this inherits nothing from codex's July bundle, and by P1 it is a full enumeration of its own
scope. Append its row to the cloudflare section of
`claude-infrastructure/docs/research/codex-security-scans/LEDGER.md`.

---

## Known issues / constraints carried into every wave

- **G2 surfaces:** auth/session and destructive migrations are operator-gated. W1b(b), W4b, and any
  confirmed lead touching credentials STOP and ask. Everything else is driven.
- **reso's DO-NOT-FIX list is authoritative.** The audit found zero contradictions and four
  near-misses each carrying a distinguishing argument — re-read § DO-NOT-FIX before any fix, and if
  a fix appears to contradict one, produce the evidence that overturns it or drop the fix.
- **No sandbox on this box.** Nothing executes reso target code during audit work. Fix verification
  is the repo's own gates, which DO run.
- **`/ship` is free, `/deploy` is the operator's.** Every wave lands; none deploys.
- **Regression tests must fail pre-fix.** A test that passes on both arms is an equivalence guard,
  not a red-proof.
