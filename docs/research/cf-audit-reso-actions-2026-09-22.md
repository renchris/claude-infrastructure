# Cloudflare security-audit — reso `src/app/actions/` — 2026-09-22

**6 CONFIRMED findings (2 high, 4 medium) and 20 needs_validation, over 8 rejected candidates; the
enumeration of `src/app/actions/` COMPLETED** — both independent coverage critics returned
`stop: true` with no missing units and no reassignments, all 41 in-scope source files were opened,
all 69 ledger units are terminal, and every one of the 34 candidates carries a verifier verdict, so
nothing is left unvalidated. The run is nonetheless **partial coverage OF THE REPOSITORY**, by
design: it is a scoped pass over one directory, and it names 17 out-of-scope surfaces, 1 deferred
unit and 1 blocked unit rather than absorbing them.

Target: reso `origin/main` = `f87d878d06a0fe89f8916601fb3a5ee3d2f645a9`, clean worktree, read-only.
Tool: `cloudflare/security-audit-skill` @ `c1c8a8c` (MIT), FULL AUDIT MODE, profile `standard`.
Artifacts: `~/security-audit-skill/reso-src-app-actions/run-1/` (96 files, outside the target).

---

## The 6 confirmed findings

Each is named in plain English first. Severity is the record's own `overall_severity`.

1. **Removing an account ends none of its sessions.** The session revocation check treats a missing
   user row as "not revoked", so a deleted user — including a deleted *platform operator* — stays
   signed in for the life of their cookie. `lib/auth/session.ts:159` reads
   `if (row && (user.credentialsVersion ?? 0) < row.credentialsVersion)`; `row` is absent in exactly
   the situation the check exists for. **medium** ·
   `session.revocation-check-skipped-when-user-row-absent`

2. **`deleteUser` deletes the user and credential rows and nothing else**, so removing a member
   revokes neither their authorization rows nor their push delivery, and frees their username for
   re-issue. No migration declares a FOREIGN KEY or ON DELETE cascade for the identity-keyed tables.
   A removed staff member keeps receiving live operational pushes, and a later invitee registering
   under the freed handle inherits the departed principal's list access. **high** ·
   `databaseActions.deleteUser.identity-keyed-rows-survive-user-removal` ·
   `src/app/actions/auth/databaseActions.ts:581`

3. **Guest erasure uses the client's guest id as a SQLite `instr()` substring pattern over the whole
   append-only `mutation_log`**, so passing a JSON key name as the id irreversibly redacts unrelated
   audit rows tenant-wide, across every venue and user, in one request and with no restore path.
   The only gate is `isManagerOrAbove`; the only type check is `typeof !== 'string'`. **high** ·
   `replicache/guest-erasure-mutation-log-redaction-uses-unvalidated-id-as-substring-pattern` ·
   `src/app/actions/replicache/operationBuilder.ts:1599-1605`

4. **Guest erasure leaves the guest's E.164 phone number behind.** `guest_channel_binding` and the
   queued recipients and bodies in `guest_message_outbox` are keyed on `guest_profile_id` and no
   production code path ever deletes from them — inside a cascade whose own header cites PIPEDA and
   which goes as far as redacting the server-only mutation log. **medium** ·
   `replicache/guest-erasure-omits-consent-binding-and-message-outbox` ·
   `src/app/actions/replicache/operationBuilder.ts:1494`

5. **Four admin-gated server actions authorize on the session cookie's sealed role**, not the live
   DB role, so a just-demoted admin keeps privilege-administration authority until the cookie
   expires — including `updateTenantConfig`, which can set `enableVenueScoping` false and turn every
   per-venue gate in the tenant into a no-op. The repo's own `accessActions.hasAdminAccess` re-reads
   the live role and its comment names this defect verbatim; commit `2850782c6` applied that fix to
   a read path. These are the call sites it did not reach. **medium** ·
   `actions.admin-gate-reads-sealed-cookie-role-not-live-db-role` ·
   `tenantConfigActions.ts:37,:78` · `venueRoleActions.ts:67,:127`

6. **`createReservation` writes a client-supplied `actual_spend` verbatim** on both its INSERT and
   its tombstone-resurrection UPDATE, with no status validation, so a manager can mint a terminal
   reservation carrying a forged revenue figure that propagates into `guest_profile.total_spend` and
   the auto-tier thresholds. Three sibling modules declare this column server-derived with no human
   write path; the repository already classed the identical shape on the adjacent column as a
   security defect. **medium** ·
   `replicache/create-reservation-writes-client-supplied-actual-spend` ·
   `src/app/actions/replicache/operationBuilder.ts:3106`

**The posture these sit in.** reso's server-action surface is defended by a real, deliberate control
set, and most of what this run found is an *inconsistency* in that set rather than an absent one —
three modules were deliberately moved OFF the `use server` surface with headers stating the rule, and
`eslint-rules/no-ungated-db-export.mjs` is a purpose-built build-time backstop. Two structural facts
do cut across the whole scope: **there is no runtime schema validation anywhere in it** (no zod, no
valibot — every action parameter type is erased at runtime), and **several authorization tables key
on `user.username`, a recyclable TEXT handle, rather than on the immutable `user.id`**. Findings 2
and 6 are downstream of those two facts respectively.

---

## The 20 needs_validation, and why they are not verdicts

These are candidates whose decisive fact is **not settleable from source on this host**. They are
recorded as leads, not as findings, and must not be read as confirmed.

| # | Lead |
|---|---|
| 1 | The WebAuthn expected-challenge slot has a network-callable setter, so a captured assertion could be replayed to obtain a session as its owner |
| 2 | `deleteDatabase`'s serving guard is scoped to the tenant manifest, so shared parent-schema databases the platform token can also destroy pass it unconditionally |
| 3 | `consumeInvitationAndRegister` takes the WebAuthn verifier's OUTPUT as a parameter, never tests `verified`, and inserts the caller-supplied credential |
| 4 | `initializeDB` is an unauthenticated Server Action whose caller-supplied database identifier and group compose the libsql URL and select the group-wide Turso token |
| 5 | The venue-reachability gate on the home SSR seed has one consumer; `tonight[].event` and `getTonightEntriesSeed` ship the identical event rows ungated |
| 6 | An invitation pins email and role but not username, and username is the venue-authorization key, so an invitee can claim a removed user's surviving venue-role grants |
| 7 | `invokeLambdaFunction` picks its authorization branch from `crossTenant` while the target tenant rides separate unvalidated arguments, so the tenant-admin branch reaches a sibling tenant |
| 8 | Platform-operator authority is decided by an email string a tenant admin writes into their own tenant's user table, and `sendInvitation` hands that admin the raw invite token |
| 9 | The poke channels are public Pusher channels whose PUBLISH credential is a repository literal the source asserts is the live identity for most tenants |
| 10 | Replicache client-group ownership is bound to the username string and never released, so a re-registered username inherits a departed user's client groups |
| 11 | Replicache pull resolves read visibility from the tenant-global `user.role` while push resolves it per venue, so a venue-demoted user is still sent the whole tenant's guest CRM |
| 12 | The idempotency watermark that authorizes a push is read outside the transaction that applies it, so a replayed push re-applies a bottle order's relative inventory arithmetic |
| 13 | On the gap-error consume path the push batch persists the client-chosen mutation id as the durable watermark, so every mutation id inside the gap is silently skipped forever |
| 14 | `createEvent` writes a client-supplied `table_map_id` with no existence or venue-coherence check, so the cross-map binding gate can be satisfied against another venue's floor plan |
| 15 | The guest-erasure cascade hard-deletes reservations, bottle orders and stored bottles in every venue behind a tenant-global manager check, while every direct path to those rows is venue-gated |
| 16 | `saveSubscription` stores a caller-supplied push endpoint URL with no validation; the send-time host deny-list is passed by a trailing-dot FQDN, a private-pointing public DNS name, or a non-443 port |
| 17 | `toClientSafeMutationError` is a two-entry denylist returning every other error verbatim, contradicting its own docblock at the push path's catch-all boundary |
| 18 | `getPlatformDB` is an ungated Server Action that builds the Turso control-plane client from `TURSO_PLATFORM_API_AUTH_TOKEN` and returns it |
| 19 | `LOCAL_TEST_SUBDOMAIN` / `LOCAL_TEST_GROUP` repoint the tenant database ahead of both the `NODE_ENV` branch and the authenticated session's own sealed tenant |
| 20 | The web-push fan-out has no per-user row cap and no concurrency bound, and its one limiter meters calls rather than messages while failing open on a 50 ms store budget |

**What blocks them, counted.** 19 of the 20 carry **both** the no-sandbox blocker and at least one
deployment-, data-state- or third-party fact not visible in source; 1 carries only the latter. The
non-sandbox facts are things like: the scope of the deployed `TURSO_PLATFORM_API_AUTH_TOKEN`
(org-wide or one group), whether any live tenant has `tenant_config.enable_venue_scoping` on, the IAM
policy on the role behind `AWS_ACCESS_KEY_ID`, whether `LOCAL_TEST_*` are present in the deployed
environment, whether Next 16.3.5 admits a Server Action POST of a given shape, and whether
`@simplewebauthn` / `web-push@^3.6.7` behave as the trace assumes. Each record carries its own
`validation_plan` naming the one experiment that would settle it.

---

## Method, and the one constraint that shaped every verdict

**No target code was executed, and that is the skill's contract rather than a shortfall.** Measured
on this host, not assumed: nested `sandbox-exec` is refused (`Operation not permitted`); the Docker
daemon is down; there is no podman/lima/colima/bwrap/firejail/nsjail on PATH; the checkout is on the
writable Data volume, not a read-only mount; and macOS cannot enforce a memory ceiling (`ulimit -v
100000` → `setrlimit failed: invalid argument`, i.e. no `RLIMIT_AS`). Independently, the target
worktree has no `node_modules/`, so no test, build or lint binary resolves. Every ledger check is
therefore `method: "source"` with `artifact: null`. **A `confirmed` record in this run rests on
source evidence that settles the invariant without execution**, and a later run on a sandboxed host
can claim things this one structurally cannot.

**The scope is smaller than the brief sized it.** The brief said "112 files, 36,542 lines, ~3.5x the
reference run". The tree is **41 source files / 18,481 lines plus 71 test files / 18,061 lines** —
~1.8x the calibrated reference (claude-infrastructure `hooks/`, 10,459 lines, 9 hunters). The wave
was sized to the source, not the headline. The endpoint surface is **18 modules whose leading
statement is `'use server'`, exposing ~55 exported actions**; in the App Router that directive makes
every export a network-reachable POST endpoint, so the client UI constrains none of them. That
framing is the spine of the run and of most of what it found.

**Agents spent: 29** — 4 reconnaissance, 13 wave-1 hunters, 1 wave-2 hunter, 2 coverage critics, 9
candidate verifiers. Against a pre-reconnaissance budget of 45.

### Validators — both PASS, verbatim

```
$ node validate-findings.cjs        run-1/findings.json
PASS: 34 findings valid

$ node validate-coverage-ledger.cjs run-1/coverage-ledger.json
PASS: 69 coverage units valid
```

### Coverage ledger, its own numbers

| unit status | count |
|---|---|
| `candidate` (produced a candidate finding) | 37 |
| `covered` (checked, no candidate) | 13 |
| `out_of_scope` | 17 |
| `deferred` | 1 |
| `blocked` | 1 |
| **total units** | **69** |

Per-file cross-check, computed independently of the critics by intersecting every `starting_paths` /
`reviewed_paths` in the ledger against `find src/app/actions -type f`: **41 of 41 source files
opened**; 34 of the 71 test files cited individually, the rest discharged by `h13-crosscutting` as a
single sweep unit (grep of all 71 for committed credentials, `libsql://` / `*.turso.io` /
`*.amazonaws.com` URLs, PEM blocks, JWT-shaped strings, `AKIA` ids and `sk_live` keys — zero hits;
every `createClient` takes `:memory:` or a tmp file; all 38 importers of the three test helpers are
themselves tests). **Read that carefully: coverage is per UNIT — a surface × boundary × class tuple
— not per file. A file opened under one attack class was not thereby examined under all of them.**

---

## What this run did NOT cover, by unit

**17 out-of-scope surfaces**, discovered during the run and recorded as `out_of_scope` units so a
later whole-repo pass turns them into current work rather than inheriting a false "covered":

`amplify.yml#build pipeline` · `drizzle/db.ts#getDBAndGroupForSessionTenant` ·
`drizzle/db.ts#getNamedDB` · `drizzle/rp.ts#getRelayingPartySettings` ·
`lib/auth/**#module 'use server' exports` · `lib/auth/credential-change-notifier.ts#notifyCredentialAdded` ·
`lib/auth/session.ts#getValidatedSessionCached` · `lib/auth/venue-authz.ts#getScopingFlag` ·
`lib/messaging/guest-message-outbox.ts#enqueue and drain` · `lib/venue-resolution.ts#getInitialVenues` ·
`src/app/(app)/**#SSR seed consumers of resolveActiveVenueRow` ·
`src/app/(app)/admin/(settings)/deviceActions.ts#module exports` ·
`src/app/(guest)/t/[claimToken]/_actions#guest claim surface` ·
`src/app/api/notifications/subscribe/route.ts#POST` · `src/app/api/replicache-push/route.ts#POST` (×2) ·
`src/middleware.ts#request middleware`

**1 deferred unit** — `src/app/actions/operationalHistoryActions.ts#getOperatorShiftDetail` against
`lib/operational-detail.ts#formatOperationalDetail`. It surfaced from a wave-1 hunter's `uncovered`
list too late to fund a hunter, and is recorded `deferred` with reason
`late_uncovered_no_remaining_wave` rather than dropped or quietly folded into the sibling unit that
covered the same file under a different attack class.

**1 blocked unit** — `src/app/actions/replicache/pullActions.ts#pull entrypoint` against
`DATA-ISOLATION-AND-LIFECYCLE.md#Missing tenant or owner enforcement`.

**The test surface** was covered by sweep, not per-file (above). **Phase 5 fresh-eyes record
verification** was not run as a separate phase; the two coverage critics and the grouped verifier
pass are what stands in its place, and that is recorded as a deviation rather than absorbed.

---

## Does anything here contradict reso's own by-design list?

**No. Zero findings overturn a DO-NOT-FIX landmine or an FP exclusion** — and four sit close enough
to one that each carries an explicit distinguishing argument rather than an assertion:

- **`replicache-pull-read-path-ignores-per-venue-role`** vs *"share-graph venue-unscoped reads are
  INTENTIONAL (Decision 4)"* — the record tests itself against the item and shows Decision 4 exempts
  **the share graph** and names only list/share/todo, in both places it is stated
  (`appActions.ts:209-215` and `.claude/rules/replicache.md:614-618`). The guest CRM is not that
  graph.
- **`replicache.deleteGuestProfile.cascade-unscoped-by-venue`** — same boundary, same evidence:
  Decision 4 covers venue-unscoped **reads** on the list/share/todo graph; this is a cross-venue
  hard **delete** of reservations, bottle orders and stored bottles.
- **`saveSubscription-stores-unvalidated-push-endpoint-url`** vs FP-exclusion 5 (*"SSRF path-only,
  no host control"*) — the exclusion carves out host control, and here the attacker supplies the
  entire URL, so the host is chosen. It is the carve-out, not the discard.
- **`webpush-fanout-unbounded-limiter-counts-calls-and-fails-open`** vs FP-exclusion 1 (*DoS /
  resource exhaustion*) — the record claims it clears the exclusion **through** its stated
  LLM-cost-amplification / operator-owned-spend exception rather than around it, and says why.

Two confirmed findings explicitly state they are *not* covered by the list rather than leaving it
implied: `actions.admin-gate-reads-sealed-cookie-role-not-live-db-role` distinguishes
*"`getServerActionSession` IS the auth check"* as a claim about **authentication** (undisputed — the
caller is genuinely authenticated) from the **authorization** decision layered on top; and
`session.revocation-check-skipped-when-user-row-absent` searched for a legitimate flow depending on
the fail-open and found none.

One finding was **narrowed in the target's favour** on a by-design reading: the guest-erasure record
does *not* report retention of the `guest_consent` row (capture IP included), because the schema
argues at length that consent revocation must be a column rather than a delete — a deleted row
destroys the evidence that consent existed — and CTIA §5.1.2 names captured IP as part of that
web-opt-in evidence.

`next.config.js`'s deliberately absent `serverActions.allowedOrigins` (H-012, measured inert because
every reso runtime forwards `x-forwarded-host` = the tenant's own subdomain) is **not** reported as a
finding on its own, as the by-design list requires.

---

## Deviations from the skill, recorded rather than hidden

Eight are recorded in full at `run-1/DEVIATIONS.md`. The three a reader should weigh:

1. **Phase-3 verification is GROUPED**, not one fresh agent per candidate. 34 candidates × 1 agent
   each would have exceeded the budget of 45 and left nothing for Phase 5. Each verifier received
   several candidates drawn from hunters it is not — preserving the property the rule protects (the
   verifier did not produce the candidate, and does not see another verifier's conclusion) while
   fitting the budget. The permitted alternative was to validate in fingerprint order until the
   budget ran out and stamp the run `incomplete`; grouping was chosen because it verifies every
   candidate rather than an arbitrary prefix.
2. **Companion blocks were referenced by exact file + heading rather than pasted verbatim** into each
   of 13 hunter prompts (~60 KB each). The substance the rule protects — the hunter having the text,
   and knowing what was excluded and why — is preserved; the transport changed.
3. **Two parent errors in the ledger's `boundary` fields, found by hunters and left visible.**
   (a) a unit named `lib/rate-limit/push-limiter.ts#push rate limit`, a file that does not exist —
   the real control is `checkPushRateLimitDurable` (`lib/rate-limit/durable-limiter.ts:237`);
   (b) a unit named `authContext.ts#checkListAccess`, which with `checkAdmin` and `isAdminOrListOwner`
   is a **dead export with zero callers** — the live gate is `validateListAccess`
   (`operationBuilder-shared.ts:497-505`). `canonical_refs` were left unchanged because `coverage_id`
   derives from them and is the key every hunter result was mapped by; each unit carries a
   `parent_boundary_correction` instead. **Consequence for a reader: a `boundary` value in this
   ledger is the parent's pre-hunt hypothesis about which control governs a surface, and two of them
   were wrong.** Both hunters found and reported against the real control regardless.

---

## Prior coverage — this run inherits nothing

`enumeration_complete[cloudflare, reso]` was **false** before this run: lens G had never run on this
repo, so by reso's own rule **P1** this was a first full enumeration of its scope, and absence may
only be counted inside it. codex-security's reso bundle (`e6ead3ce5_20260729T174332Z`) declares
`includePaths: ["src/app/api/", "middleware.ts", "lib/auth/"]` — verified by reading its
`coverage.json` — so `src/app/actions/` was never covered by it. Under rule **P3** a different
producer's coverage does not transfer, and under **P2** that run's four `no_issue_found` surfaces
(`surface_dev_bypass_routes`, `surface_debug_secret_exposure`, `surface_route_authn`,
`surface_cookie_config`) suppress nothing here, because they are negative searches rather than
positive observations. No prior confirmations were carried, excluded or revalidated.

---

## Provenance note — how this run finished

The session that drove waves 1–3 died at the context ceiling (`Prompt is too long`) with 30 of 34
verifier decisions banked. The last verifier, `v7-data-lifecycle`, had been recorded as OUTSTANDING
because every extraction attempt truncated mid-JSON. **It had in fact completed**: its transcript
finished emitting at 01:15:44, after the last attempt, and a successor session extracted its 4
decisions (3 confirmed, 1 rejected) from disk. **No agent was re-run to finish this audit**, so the
29-agent count is the true cost and the verdicts are the original verifiers' own. Recovery map:
`run-1/RECOVERY.md`.

Full artifacts: `~/security-audit-skill/reso-src-app-actions/run-1/` — `REPORT.md`,
`FINDINGS-DETAIL.md`, `NEEDS-VALIDATION.md` (each `needs_validation` lead with its blockers and its
`validation_plan`), `coverage-ledger.json`, `findings.json`, `DEVIATIONS.md`, `FILE-COVERAGE.md`,
`MERGE-MAP.md`, `hardening-all.json` (86 hardening notes not reported as findings).
