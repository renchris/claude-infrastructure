# W1b route (b) — schema FOREIGN KEYs with ON DELETE — OPERATOR RULING REQUIRED

**Status: NOT LANDED. Not started. This is the packet, nothing else.**
Route (a) — the application-level cascade — is landed and closes both live arms today.
Route (b) is the durable fix and is a G2 escalation surface: it is a schema migration on a
live 8-tenant fleet, and every step of it is a destructive table rebuild.

---

## 0. The pragma question — MY FIRST VERDICT HERE WAS WRONG, and the correction is WORSE for route (b), not better

**What I wrote first, and it is REFUTED:** that `PRAGMA foreign_keys` is OFF by default and
per-connection, that `drizzle/db.ts` never sets it, and therefore that route (b) would land
**inert** — a green migration with zero behaviour change.

**Measured against that** (lead, 2026-09-22, on a local `sqld` 0.24.32 driven by
`@libsql/client` 0.17.4 over http — no credentials, no production, no reso database touched):

| probe | result |
|---|---|
| fresh `execute('PRAGMA foreign_keys')`, nobody having set it | **`{foreign_keys: 1}` — ON** |
| same, on every subsequent execute | `1` |
| setting it ON in a standalone execute | no change; already `1` |
| read inside a write transaction | `1` |
| **`PRAGMA foreign_keys=OFF` in its own execute, read back in another** | **`1` — IT DID NOT TAKE** |
| **same, set and read in ONE batch / one request** | **`1` — IT DID NOT TAKE** |

So the libsql **server** default is ON. The mechanism half of my claim was right (a declared
constraint does nothing unless enforcement is on, and it is per-connection); the *default* half
was a statement about SQLite's C library, which is not the layer reso runs on. **"Route (b) would
land inert" is FALSE.** It also explains the client behaviour that prompted the re-check:
`client.migrate()` brackets its batch with `PRAGMA foreign_keys=off … on`
(`hrana.js:241-268`, reached from `http.js:165` and `ws.js:170`) — a bracket only meaningful
against an ON default.

🚨 **The second half of that measurement is a NEW BLOCKING PROBLEM for §2, not a clearance.**
`PRAGMA foreign_keys=OFF` **cannot be set at all over this client protocol** on that server
version. SQLite's 12-step table rebuild **requires** foreign keys to be OFF while the table is
swapped — and §2 is four table rebuilds. If the pragma is unsettable on this path, the
`PRAGMA foreign_keys=OFF … ON` bracket in `drizzle/migrations/0050_mixed_menace.sql:8,21` and in
`client.migrate()` is a **NO-OP**, and a rebuild run while constraints exist and are enforced is
**not safe as written**.

**Why nothing is broken today:** reso declares **ZERO** foreign keys —
`grep 'references(' drizzle/schema.ts` → 0 hits, and `FOREIGN KEY|REFERENCES` in
`lib/generated/schema-ddl.ts` → 0 hits. There is nothing to enforce, so the unsettable pragma
costs nothing right now. **It becomes live the moment route (b) adds the first constraint** —
i.e. exactly this migration, and from its second table onward.

**The residual, stated honestly:** measured on **local `sqld` 0.24.32**, not on Turso's hosted
build, which may differ. That is now the one fact in this packet worth asking the operator for,
and it has replaced the question I originally opened this section with.

---

## 1. The tables, and what each one may legally take

Derived from `drizzle/schema.ts`, not from the finding record. `user` carries TWO keys and the
column type tells you which: INTEGER → `user.id`, TEXT → `user.username`.

| table.column | type → target | ON DELETE it can take | note |
|---|---|---|---|
| `credential.user_id` | INTEGER → `user.id` | **CASCADE** | route (a) already removes these |
| `push_subscription.user_id` | TEXT → `user.username` | **CASCADE** | the delivery arm |
| `user_venue_role.user_id` | TEXT → `user.username` | **CASCADE** | the per-venue authority arm |
| `share.user_id` | TEXT → `user.username` | **CASCADE** | a grant TO the principal |
| `replicache_client_group.user_id` | TEXT → `user.username`, nullable | **SET NULL is WRONG** — see below | ephemeral sync state |
| `list.owner_id` | TEXT → `user.username`, NOT NULL | ❌ **neither** | see below |
| `promoter.user_id` | INTEGER → `user.id`, NOT NULL | ❌ **not CASCADE** | see below |
| `item.user_id` | TEXT → `user.username`, `DEFAULT '(Booked by User)'` | ❌ none | a sentinel default means the column is not a reference |
| `invitation.{inviting,accepted_by,revoked_by}_user_id` | INTEGER → `user.id` | SET NULL only | audit trail; CASCADE would erase invitation history |
| `mutation_log.user_id`, operator-session log, push-delivery log, `guest_profile.created_by_user_id`, `captured_by_user_id`, `comped_by`, `granted_by`, `assigned_by` | TEXT usernames | ❌ **none, deliberately** | append-only audit MUST outlive the principal |

**Three columns cannot take a cascade, and this is why route (b) never removes the need for
application logic:**

- **`list.owner_id`** — `ON DELETE CASCADE` here **destroys real guest lists**. `SET NULL` is
  impossible (NOT NULL). `RESTRICT` makes `deleteUser` fail outright for any user who owns a
  list. The only correct behaviour is REASSIGNMENT, which no constraint can express — route (a)
  does it (to the removing admin, with `row_version + 1` so clients re-pull).
- **`replicache_client_group.user_id`** — `SET NULL` looks right and is a **regression**:
  `validateAndClaimOwnership` (`sharedActions.ts:105-129`) treats a null owner as "legacy,
  unclaimed" and lets the next caller atomically CLAIM the group. `SET NULL` converts a
  stale-owner row into an adoptable one. Route (a) removes the group and its dependent
  `replicache_client` / `replicache_cvr` rows instead.
- **`promoter.user_id`** — the finding's remediation says remove the promoter row. **Rejected in
  route (a), on evidence.** `promoter.id` is referenced by
  `guest_profile.created_by_promoter_id`, `guest_profile.preferred_promoter_id`,
  `reservation.promoter_id`, `reservation.secondary_promoter_id` and
  `promoter_event.promoter_id`, and **no product path in the repo removes a promoter row**.
  Cascading it would orphan guest and revenue data — the same defect class, on worse data. Its
  arm is also the one the finding record itself excludes from claimed impact (its
  §CORRECTIONS (a)): it needs the deleted user to have held `MAX(user.id)` AND the next
  registrant's invitation role to be `promoter`. §5 closes it by construction and is the right
  answer.

---

## 2. The migration, and what it destroys

**SQLite has no `ALTER TABLE … ADD CONSTRAINT`.** Every constraint requires the full 12-step
table rebuild. The repo has the precedent — `0050_mixed_menace.sql`, which carries
`-- lint:allow-drop-table` because `scripts/lint-migrations.sh:153-158` blocks a bare table drop
as data loss.

Next migration number is **0095** (journal `idx` 94 = `0094_spotty_lenny_balinger`).

🚨 **AND THE BRACKET IN THAT SQL MAY BE A NO-OP — see §0.** Every rebuild below opens with
`PRAGMA foreign_keys=OFF`, copied from the `0050_mixed_menace.sql` precedent. Measured on local
sqld 0.24.32, that pragma **does not take** over the libsql client protocol. For the FIRST table
that is harmless (no constraints exist yet), but from the SECOND onward the constraints added by
the earlier statements ARE live and enforced while a referenced table is dropped and renamed.
**Nobody has established what that does on Turso's hosted build, and that question blocks §2.**

Per table, four statements plus index recreation. Shape, for `push_subscription`:

```sql
-- lint:allow-drop-table
-- lint:allow-dml
PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_push_subscription` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`endpoint` text NOT NULL,
	`auth` text NOT NULL,
	`p256dh` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `user`(`username`) ON UPDATE cascade ON DELETE cascade
);
--> statement-breakpoint
INSERT INTO `__new_push_subscription`("id","user_id","endpoint","auth","p256dh","created_at")
  SELECT "id","user_id","endpoint","auth","p256dh","created_at" FROM `push_subscription`;--> statement-breakpoint
DROP TABLE `push_subscription`;--> statement-breakpoint
ALTER TABLE `__new_push_subscription` RENAME TO `push_subscription`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE INDEX `idx_push_subscription_user_id` ON `push_subscription` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `push_subscription_endpoint_unique` ON `push_subscription` (`endpoint`);
```

Repeat verbatim-shaped for `user_venue_role` (PK `(user_id, venue_id)`, indexes `idx_uvr_user`,
`idx_uvr_venue`), `share` (indexes `idx_share_list_user`, `idx_share_user_id`) and `credential`
(constraint onto `user(id)`, unique indexes on `external_id` and `public_key`).

**So the migration destroys and rebuilds 4 tables on 8 live tenant databases** — including
`credential`, which is the passkey store. That is why this is a stop-ask and not a commit.

**A constraint onto `user(username)` is legal** (the column is `text().unique()`, and SQLite
permits a parent key that is any UNIQUE column, not only the PK) — but it is a constraint onto a
**recyclable** key, which is exactly the root cause. See §5.

---

## 3. Backfill — required, and it must run BEFORE the rebuild

The rebuild's `INSERT … SELECT` copies orphans happily; the constraint only bites afterwards, and
`PRAGMA foreign_key_check` then reports every pre-existing orphan. Every tenant has been running
the defective `deleteUser` for the life of the product, so orphans are expected.

Per tenant, per table, read-only first:

```sql
SELECT COUNT(*) FROM push_subscription  p LEFT JOIN user u ON u.username = p.user_id WHERE u.username IS NULL;
SELECT COUNT(*) FROM user_venue_role    r LEFT JOIN user u ON u.username = r.user_id WHERE u.username IS NULL;
SELECT COUNT(*) FROM share              s LEFT JOIN user u ON u.username = s.user_id WHERE u.username IS NULL;
SELECT COUNT(*) FROM list               l LEFT JOIN user u ON u.username = l.owner_id WHERE u.username IS NULL;
SELECT COUNT(*) FROM replicache_client_group g LEFT JOIN user u ON u.username = g.user_id WHERE g.user_id IS NOT NULL AND u.username IS NULL;
SELECT COUNT(*) FROM credential         c LEFT JOIN user u ON u.id = c.user_id WHERE u.id IS NULL;
```

Those counts are the whole decision input and **nobody has them yet** — I did not run them.
Reading a production tenant is operator-gated here, and `CLAUDE.md` Critical Rule 1 forbids
running SQL against these databases from a session.

Disposition of what they find: `push_subscription` / `user_venue_role` / `share` / orphan
`replicache_client_group` → remove (DML, operator's call). `list` orphans → reassign to a named
tenant admin, never remove. `credential` orphans → these are passkeys with no user; **stop again
before touching them.**

---

## 4. Rollback

There are **no down-migrations in this repo** — `drizzle/migrations/` is forward-only and
`pnpm migrate` is a forward orchestrator. So rollback of a table rebuild is either:

1. **Restore the tenant from a `scripts/db-backup.ts` dump** taken immediately before the run.
   This is the only true rollback, it is per-tenant, and it loses every write since the dump.
2. **Roll forward** with `0096_*` that rebuilds each table again without the constraint — the
   same four destructive rebuilds a second time, with the same blast radius.

There is no cheap third option. Practically: take a per-tenant backup, run canary
(`harbourtwo-database`) first, verify with `PRAGMA foreign_key_check` returning empty and a real
removal through the Members UI, then the fleet.

---

## 5. RECOMMENDATION — and it is NOT route (b) as written

Route (b) puts constraints on `user.username`, which is **a key the product hands back out**.
That makes deletion cascade correctly and leaves the inheritance root cause intact: the handle is
still free, `checkUsernameAvailable` (`databaseActions.ts:912`) still confirms it, and any row
written later under that handle still attaches to whoever holds it.

The durable fix is the plan's own **W4b**: re-key authorization off the recyclable username onto
an immutable id.

1. `user.id` becomes `integer PRIMARY KEY AUTOINCREMENT` (the repo already uses AUTOINCREMENT on
   three tables — `schema.ts:1609,1665,1765`). A freed id is then **never** re-issued, which
   closes the `promoter` arm by construction with no promoter row ever destroyed.
2. `share.user_id`, `list.owner_id`, `user_venue_role.user_id`, `push_subscription.user_id` and
   `replicache_client_group.user_id` re-key onto that id, with a username → id backfill.
3. Constraints become meaningful at that point, and only then.
4. A `retired_username` tombstone table (**additive** — one table creation, no rebuild, no drop,
   no constraint) consulted by both `checkUsernameAvailable:929` and the insert path of
   `consumeInvitationAndRegister:1196`, mirroring the `RETIRED_SUBDOMAINS` tombstone the
   provisioning layer already keeps for released tenant names
   (`scripts/setup/provision-venue.ts:2757`).

**Item 4 is the one piece of this that is cheap, additive and independently valuable, and it is
the only part I would schedule without waiting for the rebuild-safety answer in §0.** The lead
has separately confirmed §5 stands unchanged under the §0 correction.

---

## 6. Three questions that are yours, not mine

1. **Does Turso's HOSTED build behave like local `sqld` 0.24.32 — foreign keys ON by default, and
   `PRAGMA foreign_keys=OFF` unsettable over the client protocol?** If it does, §2's four table
   rebuilds are not safe as written from the second table onward, and route (b) needs a different
   rebuild mechanism before it can be scheduled at all. This is the one fact in this packet that
   cannot be established without a hosted database. (My original framing — "the constraints would
   be inert" — is refuted; see §0.)
2. **Reassignment target for orphaned lists.** Route (a) reassigns to the removing admin (always
   platform staff, and admins already see every list, so it grants nobody anything new). The
   alternative the record names is an explicit tenant-owned sentinel owner. Mine is the smaller
   change; a sentinel is more honest in the UI. Your call.
3. **Invitations issued by a removed admin stay live.** `invitation.inviting_user_id` survives
   removal, so a pending invite created by a departed admin can still be consumed. It is outside
   this finding, it touches the auth surface (G2), and it was not changed. Should removal also
   revoke that admin's pending invitations?
