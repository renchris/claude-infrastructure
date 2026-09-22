# Adjudication artifacts — the 20 cloudflare leads, 2026-09-22

The eight per-axis evidence files behind
[`../cf-audit-reso-lead-verdicts-2026-09-22.md`](../cf-audit-reso-lead-verdicts-2026-09-22.md).
That document is the verdict register; these are its receipts — every claim carries a `file:line`
into reso `origin/main`, plus the fix spec, the DO-NOT-FIX check and, where one was run, the
adversarial pass.

**Why they are committed.** They were produced into `/tmp`, which is swept. This repo already
learned that lesson once and wrote it down in `../codex-security-scans/LEDGER.md`: *"They were
produced into `$TMPDIR/…`, which is swept. Losing them costs the whole scan — the coverage ledger,
the severity reasoning, and the seal."* Same reasoning, same disposition.

| file | leads | headline |
|---|---|---|
| `A1-tenantcontext.md` | 18, 19 | `getPlatformDB` is a live ungated action, but the token cannot cross the wire — `createClient` returns a class instance the flight serializer refuses |
| `A2-databaseactions.md` | 2, 4 | `initializeDB` is not registered; the live endpoint on the same sink is `getNamedDB`, and `drizzle/db.ts:131` interpolates an unvalidated string into the libsql authority |
| `A3-platform-authority.md` | 8 | the tenant-admin → platform-operator chain, link by link — no link breaks |
| `A4-push-pusher.md` | 9, 16, 20 | the Soketi publish secret is a repo literal and is the LIVE identity by executable proof; three SSRF bypasses all hold |
| `A5-webauthn.md` | 1, 3 | the expected-challenge setters are registered; lead 3's insert is bounded by an invite-token CAS |
| `A6-username-key.md` | 6, 10 | both cured by `1e07c9035`, plus the 22-column identity table and four residuals the cure does not reach |
| `A7-replicache.md` | 11, 12, 13, 17 | lead 11 is by-design; 12's replay vector is the product's own 30s abort-and-retry |
| `A8-scoping.md` | 5, 7, 14, 15 | lead 15 is NOT cured and its implied remedy is inverted — raise the gate, never narrow a PIPEDA erasure |

⚠️ **Read these as adjudications, not as gospel.** One of them (`A5`) reasoned from `'use server'`
plus `export` to a network attack on `consumeInvitationAndRegister`; the registered-action census
and the caller's own `verified` check both refute that vector, and the verdict register records
lead 3 as REJECTED on those grounds. The underlying observation in that file is still correct and
still worth reading — its conclusion is not. Where an artifact and the register disagree, the
register is the later word and says why.
