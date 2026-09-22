# "Every export is an endpoint" is a claim about a BUILD GRAPH, and the build already answers it

**The shape.** A security audit's structural fact read: *in the Next.js App Router, the
`'use server'` directive makes every export of a module a network-reachable POST endpoint.* It
is in the framework docs, it is what the directive means, and it is **too strong** — because
the compiler's reachability analysis is part of the predicate. Next registers only the exports
its build graph actually reaches. Five of that audit's twenty leads inherited the sentence as a
premise and built attacks on top of it.

**What measuring it changed.** One `pnpm build`, read off `.next/server/server-reference-manifest.js`:

- `getPlatformDB`, `setGuestSession`, `setChallengeToCookieStorage` — **registered**. Two leads
  confirmed, and one live unauthenticated session-minting endpoint found and closed.
- `initializeDB`, `consumeInvitationAndRegister`, `createEvent`, `migrateDB`,
  `initializeDatabase` — **not registered**. The stated attack vector of three leads refuted.

One adjudicator had reasoned from `'use server'` + `export` to *"a holder of an invite token
POSTs the action id"*. There was no action id. Its underlying observation was still true and
worth keeping — the function never re-tests `verified` — but the exploit did not exist, and the
caller's own `verified` check (`lib/auth/register.ts:135-137`) bounded it a second time.

**Two properties of this class of question, both generalizable.**

1. **The decisive instrument was a BUILD, not a deployment read.** The audit had split its
   leads into "source-settleable" and "needs a deployment fact" and put this question in the
   second bucket, where it sat blocked. It was in neither: it was settleable by compiling. When
   a question is blocked, re-ask which artifact answers it before accepting the blocker —
   source, build output and live state are three different stores, and a plan that names only
   two will park work that the third answers cheaply.

2. **When every interesting result is a NEGATIVE, the positive control is mandatory, not
   polite.** Every useful finding here has the form "X is *not* registered" — and a broken
   parser produces those in bulk, silently, and convincingly. This was not hypothetical: an
   earlier pass matched `registerServerReference\s*\(` and got 0 of 92, because the emitted
   call is `(0,t.registerServerReference)(`. It was caught only because a known-live action was
   checked first and came back ABSENT, which convicted the instrument instead of the subject.
   The shipped script therefore exits 2 rather than reporting when its control is missing.

**The trap inside the instrument.** `server-reference-manifest.js` carries `filename` and
`exportedName`. The sibling `.json` is keyed by hashed action id and carries **no names at
all** — so grepping a name in the `.json` proves nothing and reads exactly like a clean
negative.

**And the verdict has a shelf life.** "Not registered" is a fact about *that build*: a later
import from a reachable graph registers an export with no change to the export itself. It also
does not mean *unreachable* — `consumeInvitationAndRegister` and `createEvent` are both still
reached through a route handler and the sync push path respectively. What is refuted is the
direct-action POST, which is narrower than "safe" and must be written down as such.

**Companions.** [[one-armed-adjudication-only-convicts]] — the first pass could confirm and
never acquit. [[spec-named-mechanism-may-be-prose-only]] — a cited mechanism can exist only in
prose. [[published-figure-decays-with-its-source]] — for the shelf life.

Measured 2026-09-22, reso `next@16.3.5`: 92 registered actions, 64 inside `src/app/actions/`
and 28 outside it. Instrument landed as reso `scripts/audit-server-actions.mjs` (`ed145bc7d`).
Record: `docs/research/cf-audit-reso-lead-verdicts-2026-09-22.md`.
