# A6 — LEAD 6 (invitation does not pin username) and LEAD 10 (Replicache client-group ownership)

Adjudicated 2026-09-22 against `origin/main` of `reso-management-app`, read-only via
`git show origin/main:<path>`. No edits, no commits, no index touched.

---

## 0. VERDICTS

| Lead | Verdict | One-clause evidence |
|---|---|---|
| **6** — invitee claims a removed user's surviving venue-role grants | **REJECTED-AS-CURED-BY-`1e07c9035`** (forward-only; see §6 for the residuals) | `deleteUser` now deletes every `user_venue_role` row keyed on the departing handle inside the removal transaction — `src/app/actions/auth/databaseActions.ts:700-706` (`tx.delete(userVenueRole).where(eq(userVenueRole.userID, handle))`) |
| **10** — client groups bound to a username and never released | **REJECTED-AS-CURED-BY-`1e07c9035`** (forward-only; and the "never released" half was the whole lead) | same transaction deletes the group plus its `replicache_client` / `replicache_cvr` children — `databaseActions.ts:746-756` |

Both leads' *structural* premise is true and unchanged (authorization keys on the recyclable
`user.username` TEXT handle). What each lead asserts as the exploitable consequence — that the
grant ROWS **survive** removal, freeing the handle to be re-claimed with its authority intact — is
what `1e07c9035` closed, on 2026-09-22, in the same audit cycle that produced these leads.

**Do not re-derive the cure. It is on trunk.**

---

## 1. The landed cure — `1e07c9035` "fix(auth): deleteUser revokes the departed principal, not just their row"

Three files, no schema change, no migration: `databaseActions.ts` (+227/-17) and two test files
(`deleteUserRevocation.test.ts` new, 459 lines, proven red on parent `d10b8c1cc`;
`credentialLifecycle.test.ts` harness DDL).

`deleteUser` (`databaseActions.ts:584`) was a two-statement `db.batch` (delete `user` row, delete
that user's `credential` rows). It is now a single `db.transaction` that, keyed on the target's
`username` read inside the transaction (`:690  const handle = target.username`):

| # | Statement | Line | Effect |
|---|---|---|---|
| 1 | `delete(pushSubscription).where(eq(pushSubscription.userID, handle))` | `:696-698` | delivery revoked |
| 2 | `delete(userVenueRole).where(eq(userVenueRole.userID, handle))` | `:704-706` | **per-venue authority revoked — this is LEAD 6's table** |
| 3 | `delete(share).where(eq(share.userID, handle))` | `:712-714` | shared-list grants revoked |
| 4 | `update(list).set({ownerID: remover.username, rowVersion: +1}).where(eq(list.ownerID, handle))` | `:726-735` | owned lists REASSIGNED, not deleted (guest data) |
| 5 | select groups by `eq(replicacheClientGroup.userID, handle)`, then delete `replicache_cvr`, `replicache_client`, `replicache_client_group` by group id | `:746-756` | **LEAD 10's table, released with its children** |
| 6 | `bumpSyncCursor(tx)` | `:768` | C-003 watermark, so connected clients re-pull the ownership change |
| 7 | `delete(credential)` / `delete(user)` | `:771-781` | as before |

Fail-closed guards ahead of it: `ensureAdminAccess()` + `ensurePlatformAccess()` (`:585-596`),
self-deletion refusal (`:600-602`), refusal when the remover's row cannot be resolved
(`:604-607` and `:685-687` — no reassignment target ⇒ write nothing).

The commit deliberately **rejected** the finding's own suggestion to NULL
`replicache_client_group.user_id`, because `validateAndClaimOwnership`
(`src/app/actions/replicache/sharedActions.ts:92-140`) reads a null owner as "legacy, unclaimed"
and lets the next caller atomically CLAIM it — NULLing would have converted a stale-owner row into
an **adoptable** one, i.e. would have *created* LEAD 10 rather than closing it. That reasoning is
correct on the code as read.

---

## 2. Item 1 — every authorization-bearing identity column, by what it actually holds

`drizzle/schema.ts` on `origin/main`. `user.username` is `text('username').unique().notNull()`
(`:25`); `user.id` is `integer('id').primaryKey()` — a bare SQLite rowid alias, no `AUTOINCREMENT`.
`lib/constants/system-actors.ts:5-8` states the house convention in its own words: *"reso's TEXT
identity columns hold `user.username`."*

**Authorization-bearing** = a code path grants or scopes access on the value.

| Table | Column | Line | Holds | Auth-bearing? | In the `1e07c9035` cascade? |
|---|---|---|---|---|---|
| `user_venue_role` | `user_id` TEXT | `:655` | **username** | **YES** — `checkVenueAccess` grants on the bare existence of a `(username, venueID)` row, `lib/auth/venue-authz.ts:324-330` | **YES — deleted** |
| `share` | `user_id` TEXT | `:258` | **username** | **YES** — `accessibleLists` non-admin branch, `src/app/actions/replicache/authContext.ts:208-219`; enforced by `checkListAccess:318` on both Replicache read and write | **YES — deleted** |
| `list` | `owner_id` TEXT | `:242` | **username** | **YES** — same union, `authContext.ts:219` | **YES — reassigned to the removing admin** |
| `replicache_client_group` | `user_id` TEXT (nullable) | `:207` | **username** — `src/app/api/replicache-pull/route.ts:86` does `const { username: userID } = user`, and that value is what reaches `validateAndClaimOwnership(tx, clientGroupID, userID)` (`pullActions.ts:558`; `pushActionsBatch.ts:388,468,714`) | **partly** — sync-ownership integrity, not a data-scoping gate (see §4) | **YES — deleted, with `replicache_client` + `replicache_cvr` children** |
| `push_subscription` | `user_id` TEXT | `:311` | **username** | delivery, not authorization — but it is the disclosure channel | **YES — deleted** |
| `item` | `user_id` TEXT | `:278` | **username** | **no grant**, but it is a RECIPIENT SET: `approval_resolved` recipients are read off surviving `item` rows and fanned out by username, `notificationDispatch.ts:296-303, 328` | **NO — correctly not cascaded (guest data)** ⇒ residual, §6.2 |
| `credential` | `user_id` INTEGER | `:113` | **`user.id`** | yes (passkey ownership) | YES — deleted (as before) |
| `promoter` | `user_id` INTEGER | `:623` | **`user.id`** | yes (promoter scoping) | **NO — deliberately excluded**, see §6.3 |
| `invitation` | `inviting_user_id` / `accepted_by_user_id` / `revoked_by_user_id` INTEGER | `:72,95,97` | **`user.id`** | no (audit + email host line) | NO — a pending invite from a departed admin stays live; the commit surfaces this in its own body |
| `mutation_log` | `user_id` TEXT | `:1615` | username | no (audit / operator-shift reporting) | NO |
| `login_log` | `user_id` TEXT | `:1666` | username | no (audit) | NO |
| `notification_outbox` | `creator_user_id` TEXT | `:1728` | username | no — used only as the `excludeUserID` filter (`notificationDispatch.ts:296`) | NO |
| `notification_delivery` | `user_id` TEXT | `:1767` | username (recipient) | no (delivery log) | NO |
| `user_venue_role` | `granted_by` TEXT | `:659` | username | no (audit) | n/a (row deleted with #1) |
| `promoter_event` | `assigned_by` TEXT | `:675` | username | no (audit; the scoping key is `promoter_id` → `promoter.id`) | NO |
| `bottle_order_item` | `comped_by` TEXT | `:945` | username | no (approval trail) | NO |
| `guest_profile` | `created_by_user_id` TEXT | `:584` | username | no — projection only, `tableServiceActions.ts:633` | NO |
| `guest_consent` | `captured_by_user_id` TEXT | `:1942` | username | no (audit) | NO |
| `reservation` | `created_by` TEXT | `:725` | username | no — projection only, `tableServiceActions.ts:719` | NO |
| `table_map` | `created_by` TEXT | `:426` | username **or** `'1'` **or** `'system:provisioning'` | no — `system-actors.ts` states there are **zero readers** today | NO |
| `artist_profile` | `created_by` TEXT | `:979` | username | no | NO |

**Summary of item 1: five columns carry real authorization on a username. Four of the five
(`user_venue_role.user_id`, `share.user_id`, `list.owner_id`, `replicache_client_group.user_id`)
are in the cascade. The fifth — `item.user_id` — is not, correctly, because it is guest data; it
is a recipient set rather than a grant, and it is the one residual of the class (§6.2).**

---

## 3. Item 2 — LEAD 6, the invitation path, traced end to end

**The invitation does NOT pin a username. That half of the lead is TRUE.**

- `sendInvitation(firstName, lastName, email, role)` — `databaseActions.ts:921-1007`. The INSERT
  (`:983-994`) writes `email`, `firstName`, `lastName`, `role`, `invitingUserID`, `externalID`
  (sha256 of the raw token), `status`, `expiresAt`. **No username column exists on `invitation`**
  (`drizzle/schema.ts:48-109`) and none is written.
- `consumeInvitationAndRegister(inviteToken, email, username, verification, …)` —
  `databaseActions.ts:1279-1420`. `username` is the **third positional parameter, client-supplied**,
  reaching the action from `src/app/api/register/route.ts`. It is normalised
  (`trimmedUsername = username.toLowerCase().trim()`, `:1293`) and length-bounded (≤100, `:1294`),
  and then inserted verbatim (`:1389  username: trimmedUsername`). The only other constraint is the
  `user.username` UNIQUE index. **Every other field of the new user is taken from the consumed
  invitation row** — the code comment at `:1386` says so: *"All user data from DB record, not client
  params"* — email, firstName, lastName and **role** all come from `consumed.*`. Username is the one
  exception, and it is exactly the authorization key.
- `checkUsernameAvailable(username)` — `:1105-1128` — is a pre-auth availability probe against
  `user.username` only. It says "available" for any handle with no live `user` row, including a
  handle that was just freed by a removal.
- **`user.username` is write-once.** Exhaustive grep of `update(drizzleUser)` on `origin/main`
  returns exactly three sites — `:473` (`credentialsVersion` bump), `:832` (`colorMode`), `:870`
  (`role`). **No code path anywhere in the repo mutates `user.username`.** So the ONLY way a handle
  is freed is `deleteUser` (or out-of-band DML, §6.1).

**The concrete sequence the lead asserts, evaluated against trunk:**

1. Platform staff remove user `x.doe` (`deleteUser`, which requires `ensureAdminAccess` **and**
   `ensurePlatformAccess`, `:585-596`).
2. An admin invites a new person; `sendInvitation` pins only their email + role.
3. The invitee registers and types `x.doe` as their username. `checkUsernameAvailable` says yes;
   the UNIQUE index permits it; nothing anywhere reserves a retired handle.
4. **Pre-`1e07c9035`**: the new `x.doe` inherited every `user_venue_role` row of the departed
   `x.doe` (venue-admin/manager on any venue), every `share` row, and ownership of every `list` the
   departed user owned — `checkVenueAccess` and `accessibleLists` never join to `user`.
5. **On trunk**: steps 1-3 still work exactly as described, and step 4 finds **nothing left to
   inherit** — the venue roles, shares and client groups were deleted and the lists reassigned in
   the removal transaction.

Which grants survive after `1e07c9035`? **None that grant anything.** The surviving username-keyed
rows are `item.user_id`, `mutation_log`, `login_log`, `notification_outbox.creator_user_id`,
`notification_delivery`, `guest_profile.created_by_user_id`, `guest_consent.captured_by_user_id`,
`reservation.created_by`, `bottle_order_item.comped_by`, `promoter_event.assigned_by` — all audit,
projection or recipient-set columns; none is read by `checkVenueAccess`, `accessibleLists`,
`checkListAccess` or any other gate. Only `item.user_id` has a live consequence (§6.2).

A further, independent brake on the lead's *other* plausible entry point: `setUserVenueRole`
(`src/app/actions/venueRoleActions.ts`) refuses to write a grant for a username with no live `user`
row — it SELECTs the target and returns `'User not found'` — so an admin cannot pre-seed a grant
onto a handle nobody holds. Combined with write-once usernames, there is no way to create an
orphan `user_venue_role` row through the product on trunk.

---

## 4. Item 3 — LEAD 10, Replicache client-group ownership

- **The ownership column is `replicache_client_group.user_id`, `text('user_id')`, NULLABLE**
  (`drizzle/schema.ts:205-207`; the schema comment says *"Owner of this client group (nullable for
  migration)"*).
- **It holds the USERNAME.** `src/app/api/replicache-pull/route.ts:86` — `const { username: userID }
  = user` — and that string is threaded unchanged into `processPull(pull, userID, db)` (`:277`) →
  `pullForChanges(…, userID, …)` → `validateAndClaimOwnership(tx, clientGroupID, userID)`
  (`pullActions.ts:558`). The push side is identical (`pushActionsBatch.ts:388, 468, 714`).
- **Is it ever released?** Before `1e07c9035`: **no.** Grep of the repo finds no other writer that
  clears or reassigns `replicache_client_group.user_id`. After `1e07c9035`: **yes**, on user removal
  — `databaseActions.ts:746-756` selects the groups by handle and deletes `replicache_cvr`,
  `replicache_client` and `replicache_client_group` in that order (children first) so nothing is
  orphaned.
- **Does `1e07c9035` touch it?** Yes — it is arm (5) of the cascade, and the commit explicitly
  argues why DELETE beats NULL here (NULL is adoptable by `validateAndClaimOwnership`'s Case 2,
  `sharedActions.ts:113-140`).

**Severity note, stated because the lead overstates it.** Inheriting a client group is a
*sync-integrity* defect, not a data leak: the pull recomputes `authContext` fresh from the username
on every request (`pullActions.ts:858 prefetchPullAuthContext(db, userID, …)`) and the CVR is only a
diff basis, so a stale CVR causes under-delivery or spurious deletes on the client, never delivery
of rows the current principal cannot see. The ownership check is a per-device mutation-ordering
guard, not the authorization boundary — the session cookie is. Exploiting it also requires the
attacker to present the departed user's `clientGroupID`, a client-generated id held in that
browser's IndexedDB. So LEAD 10 was real, is closed, and was never the high-severity half of the
pair; LEAD 6's `user_venue_role` arm was.

---

## 5. Item 4 — fixes, sharply split

### (i) Landable-now point fixes

There is **no point fix left to land for either lead as stated** — `1e07c9035` is that point fix and
it is on trunk. The two candidate point fixes the brief names are each already either landed or
refuted:

- *"Pin the username in the invitation"* — **do not do this.** It is not required for either lead
  now that the grants do not survive, it changes a live table (`invitation` gains a column ⇒ a
  migration across 8 tenants, so it is not a point fix at all), and it breaks the WebAuthn
  onboarding UX: the invitee chooses their handle during the ceremony, and the repo's own
  `checkUsernameAvailable` (C-007, `:1098-1104`) exists precisely to let them discover collisions
  before `startRegistration`. Pinning it would also require the inviting admin to know and type a
  handle for someone else. Rejected on evidence, not on effort.
- *"Release client groups in the existing cascade"* — **already done**, `databaseActions.ts:746-756`.

The only genuinely landable-now, in-scope items are the two residuals in §6.2 and §6.4, and both
are small and additive.

### (ii) Operator-gated durable fix — NAMED, NOT DRIVEN

**Re-key authorization off `user.username` onto the immutable `user.id`.** This is a schema
migration plus a data backfill across eight live tenant databases (`user_venue_role`, `share`,
`list`, `replicache_client_group`, `push_subscription`, plus every audit column a report joins on),
in SQLite, where adding a FOREIGN KEY or changing a PK requires a **full table rebuild** — i.e.
destructive table drops on live tenant data, including a dual-write/backfill/cutover window, and
`user.id` is today a bare rowid alias with no `AUTOINCREMENT`, so id reuse is itself a precondition
to fix first.

`1e07c9035`'s own commit body already identifies this as **route (b)**, states it is *"PENDING AN
OPERATOR RULING"*, and records that the packet (exact SQL, tables, backfill, rollback) was handed
back with the work. That is the correct disposition and it is unchanged by this adjudication.
**I am not recommending anyone drive it**, and `exhaust-improvements.md`'s own calibration note 5
says the same thing in general terms: *"Auth/sync findings → queue + escalate, never silently land
mid-sweep."*

---

## 6. Adversarial pass — what the two verdicts do NOT cover

Four things a hostile reviewer would raise. Each was checked with a real read, not assumed.

### 6.1 The cure is FORWARD-ONLY. Pre-existing orphans are still in the live tenant databases.

`1e07c9035` touched three files, all application code and tests — **`git show --stat` confirms no
migration, no backfill script, no reconciliation job**. A grep of `scripts/` for an orphan-row
reconciler over `user_venue_role` or `replicache_client_group` returns nothing. So for **any user
removed before 2026-09-22**, the grant rows keyed on their freed handle are still sitting in the
tenant DB, and LEAD 6's sequence works against those handles exactly as written. Closing that is
**production DML on eight live tenants — operator-gated**, and it is the single most defensible
follow-up to file. A read-only census first (`SELECT uvr.user_id FROM user_venue_role uvr LEFT JOIN
user u ON u.username = uvr.user_id WHERE u.id IS NULL`, and the same shape for `share`, `list`,
`replicache_client_group`, `push_subscription`) is non-destructive and would size the exposure
before anyone proposes a DELETE.

### 6.2 `item.user_id` survives, and it is a live disclosure channel to a re-issued handle.

`approval_resolved` recipients are `item.userID` read off surviving `item` rows
(`notificationDispatch.ts:296-303`) unioned with approvers, and the fan-out is
`inArray(pushSubscription.userID, recipients)` (`:328`). The `approval_pending` set is safe — it
SELECTs `FROM user` (`getApproverUserIDs`, `:47-56`) and therefore self-cleans. So: departed `x.doe`
added items → their `item` rows survive (correctly, guest data) → a **new** `x.doe` registers and
enables push → the new person receives approval-resolved notifications for lists they never touched,
carrying list titles, approver names, per-list AND tenant-wide open-queue counts, and a tenant deep
link. This is LEAD 6's defect class, surviving `1e07c9035`, through a table the cascade rightly does
not delete.

**Landable-now point fix, in one place:** make the `approval_resolved` adder set resolve through
`user` the same way the pending set already does — i.e. in `notificationDispatch.ts` around
`:296-303`, replace the bare `db.select({userID: item.userID}).from(item).where(inArray(item.id,
itemIDs))` with the same shape joined to `user` on `eq(user.username, item.userID)`, projecting
`user.username`, so a handle with no live `user` row yields no recipient. One file, one query,
no schema change, and it mirrors a pattern already in the same module.

### 6.3 `promoter.user_id` holds `user.id`, and `user.id` is reusable.

`promoter.userID` is `integer('user_id')` (`schema.ts:623`) and `user.id` is a bare rowid alias with
no `AUTOINCREMENT`, so SQLite may reissue the max id after a delete. `1e07c9035` deliberately did
**not** cascade `promoter` — correctly: `promoter.id` is referenced by
`guest_profile.created_by_promoter_id`, `guest_profile.preferred_promoter_id`,
`reservation.promoter_id`, `reservation.secondary_promoter_id` and `promoter_event.promoter_id`,
and no product path removes a promoter row, so cascading would orphan guest and revenue data. The
exposure requires the removed user to have held `MAX(user.id)` **and** the next registrant's
invitation role to be `'promoter'`. The durable closure is `AUTOINCREMENT` on `user.id` — a table
rebuild, i.e. item 1 of the operator-gated route (b) packet. **Named, not driven.**

### 6.4 An invitation issued BY a removed admin stays live.

`invitation.inviting_user_id` is INTEGER and is not cascaded; `consumeInvitationAndRegister`'s CAS
(`databaseActions.ts:1360-1371`) matches on token + email + `activeInviteWhere(now)` and never reads
the inviter. So a pending invite created by a since-departed admin is still consumable until its
14-day TTL. The commit surfaces this explicitly rather than taking it silently. It is an authority
question (should removing an admin revoke their outstanding invitations?), not a username-key
question, so it belongs to neither lead — but it is on the same G2 auth surface and is the second
item worth filing.

### 6.5 Deployment fact, stated rather than assumed.

`1e07c9035` landed 2026-09-22. Whether the eight live tenants are **running** it is a deployment
fact I did not and cannot verify read-only without network. Neither verdict is *blocked* on it —
both are verdicts about trunk — but §6.1's orphan residue is real regardless, and if the fleet has
not yet taken the commit then LEAD 6 is live in production in its original form until it does.

---

## 7. Item 5 — DO-NOT-FIX check

Read `.claude/commands/exhaust-improvements.md` § *DO-NOT-FIX landmines* (`:181-190`) on
`origin/main`. Eight landmines: sequential `for…of`+await on Replicache mutations; `<Suspense>`;
mission-control hardcoded `rgba`; F6 warm-at-tap stale-continuity; FloorPlanViewer barrel API;
**share-graph venue-unscoped reads (Decision 4, per-venue RBAC — "a security lens WILL flag it; it
is by-design")**; `getServerActionSession`; park-ui prop spreading.

- **Nothing in either lead, in `1e07c9035`, or in the §6.2 point fix touches any of them.**
- The share-graph landmine is adjacent and worth being explicit about: it says the **venue-unscoped
  READ of the share graph** is intentional. Neither lead nor any fix here narrows a share read —
  `1e07c9035` deletes `share` rows belonging to a *departed principal*, which is a different
  operation on a different axis, and §6.2 changes a *notification recipient set*, not a share read.
  A future session re-deriving "share.user_id is unscoped by venue" from the same structural fact
  **would** be hitting Decision 4 and should stop.
- `exhaust-improvements.md` calibration note 5 additionally governs the disposition of everything
  in §6: *"Auth/sync findings → queue + escalate, never silently land mid-sweep."*

---

## 8. Sources

All paths at `origin/main`, `reso-management-app`.

- `1e07c9035` — the cure (`git show 1e07c9035`)
- `src/app/actions/auth/databaseActions.ts` — `deleteUser` `:584-800`; `sendInvitation` `:921-1007`;
  `checkUsernameAvailable` `:1105-1128`; `consumeInvitationAndRegister` `:1279-1420`
- `drizzle/schema.ts` — `user` `:22-44`; `invitation` `:48-109`; `replicacheClientGroup` `:205-218`;
  `list` `:240`; `share` `:255`; `item` `:271`; `pushSubscription` `:309`; `userVenueRole` `:654-663`
- `lib/auth/venue-authz.ts:300-331` — `checkVenueAccess`
- `src/app/actions/replicache/authContext.ts:190-230, 310-330` — `accessibleLists`, `checkListAccess`
- `src/app/actions/replicache/sharedActions.ts:92-140` — `validateAndClaimOwnership`
- `src/app/api/replicache-pull/route.ts:86, 277` — username → ownership key
- `src/app/actions/replicache/pullActions.ts:558`, `pushActionsBatch.ts:388,468,714`
- `src/app/actions/replicache/notificationDispatch.ts:47-56, 296-303, 328`
- `src/app/actions/venueRoleActions.ts` — `setUserVenueRole` target-exists check
- `lib/constants/system-actors.ts:1-40` — the TEXT-identity-column convention
- `.claude/commands/exhaust-improvements.md:181-190` — DO-NOT-FIX landmines
