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

## Phase 0 — Agent Team Orchestration

### Execution locus per wave

| Wave | Locus | Why (T and L only) |
|---|---|---|
| W1 — the 6 confirmed | **S** ×4 dispatched sessions | default |
| W2 — the 20 leads, source-settleable half | **S** ×3 | default |
| W3 — the 20 leads, deployment-fact half | **L** lead-inline | each is a *read* of live infra (IAM policy, deployed env, Turso token scope) plus one operator question; there is no code to own, and splitting a question set across sessions duplicates the asking |
| W4 — the 2 structural facts | **S** ×2 | default |
| W5 — the 19 uncovered surfaces | **S** ×1 (a Cloudflare enumeration, not an edit wave) | default |

**Locus S recipe** (every S wave, verbatim):
`scripts/handoff-fire.sh --prompt-file <brief> --worktree <branch> --notify-back <lead-uuid> --account auto --split-right --goal '<end state> — proven by <command the session prints>; do not <constraint>'`, lead arms `cc-await-ping` in background.

### Task size band

Every brief is written to **40–150K output ≈ 30–75 min ≈ 60–110 turns ≈ 3–6 files**. Never below
20K. Split above 300K or 10 files. The band is a sizing target and does NOT relax the agent-teams
caps: ≤150-line brief body, reading list ≤5 files, split any deliverable >500 LOC.

### Team roster, dependency graph, worktrees

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

### Lead context budget + succession point

- **Reserved for leading: ≥50%.** The lead writes briefs, adjudicates verdicts and merges; it does
  not implement. W3 is the single exception and is deliberately small.
- **Succession point: after W2 lands.** The lead recycles (`handoff-fire.sh --recycle`) before W4,
  because W4 is the largest wave and the lead entering it above ~50% fill cannot adjudicate a
  cross-cutting refactor. If fill reaches ~50% earlier, recycle at the nearest wave boundary
  instead — the plan file is the bridge.

---

## Wave 1 — the 6 confirmed findings

Each unit: fix, add a regression test that FAILS on the pre-fix code (prove it by running it against
`git stash`ed source or the parent commit), run the three gates, land.

### W1a — `operationBuilder.ts`, three findings, one owner

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

### W1b — `deleteUser`, and the only migration in W1

**#2 (high).** `databaseActions.ts:581` deletes the user and credential rows only. No migration
declares FK or `ON DELETE` for the identity-keyed tables, so a removed member keeps live push
delivery and a later invitee under the freed handle inherits their list access.

**Two routes — pick in the brief, state the choice in the commit:** (a) application-level cascade
inside one transaction; (b) schema FKs with `ON DELETE`. (b) is the durable fix and is a **schema
migration on a live multi-tenant fleet** — it is a G2 escalation surface, so W1b STOPS and asks
before any `DROP`/destructive step. (a) is landable now and is the safe first increment. Do both in
order, never (b) alone.

### W1c — revocation fails open

**#1 (medium).** `lib/auth/session.ts:159`
`if (row && (user.credentialsVersion ?? 0) < row.credentialsVersion)` — `row` is absent in exactly
the case the check exists for, so a deleted user (including a deleted platform operator) stays
signed in for the cookie's life. Fix: absent row ⇒ revoked. The audit searched for a legitimate flow
depending on the fail-open and found none — re-run that search before landing, and record it.

### W1d — admin gate reads the sealed cookie role

**#5 (medium).** Four actions authorize on the cookie's sealed role, not the live DB role:
`tenantConfigActions.ts:37,:78` and `venueRoleActions.ts:67,:127`. A just-demoted admin keeps
privilege-administration authority until cookie expiry — including `updateTenantConfig`, which can
set `enableVenueScoping` false and no-op every per-venue gate in the tenant. The repo's own
`accessActions.hasAdminAccess` re-reads the live role and its comment names this defect verbatim;
commit `2850782c6` applied it to a read path. **Fix = extend that existing helper to these four call
sites.** No new mechanism.

---

## Wave 2 / Wave 3 — the 20 leads, each to a verdict

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

## Wave 4 — the two structural facts

**W4a — no runtime schema validation anywhere in the action surface.** No zod, no valibot; every
server-action parameter type is erased at runtime. Finding #6 is downstream of this. Introduce
validation at the action boundary, starting with the actions W1 touched, then the rest of
`src/app/actions/`. Sized to split: this is >500 LOC and >10 files, so it is a wave of units, not
one unit — decompose it in its own Phase 0 block before firing.

**W4b — authorization tables key on `user.username`, a recyclable TEXT handle.** Findings #2 and
leads 6 and 10 are downstream. Re-key to the immutable `user.id`. This is a schema migration plus a
data backfill on a live fleet — G2, operator-gated, and it lands only after W1b's migration.

---

## Wave 5 — the 19 surfaces this run did not cover

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
