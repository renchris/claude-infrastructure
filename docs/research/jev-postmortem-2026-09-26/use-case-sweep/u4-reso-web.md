# U4 — reso-web-app (www.reso.gl): Jev use cases

**Verdict:** no strong use case. The repo is a Next.js 15 marketing and guestlist site with two
write endpoints (`/api/guestlist`, `/api/newsletter`). It has **zero LLM calls** (measured:
`rg -i "openai|anthropic|ai-sdk|generateText|claude|llm|gpt|gemini|bedrock" src scripts` returns only
llms.txt builders and CLAUDE.md mentions), **zero TODO/FIXME** (measured: `rg -i "TODO|FIXME|XXX|HACK" src scripts`),
and one free-text field a person types (`messageToHost`). Volume is the binding constraint: 219
guestlist rows all-time, 19 in 2026-09 (measured, `docs/research/RUM_VS_SYNTHETIC_2026-09-19.md:52-54`,
from a full DynamoDB scan). About 3.8 sessions/day (same doc).

## Ranked use cases

| # | Name | Plug-in (file:line) | Judgment | Consumer | Volume | Replaces (cost / miss rate) | Business value | Privacy | Effort | Conviction |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Guest-note triage (`messageToHost`) | `src/pages/api/guestlist.ts:110` (before the Put: add a `noteIntent` attribute). Or downstream at `~/Development/sevenrooms-bridge/src/map/mapper.ts:83`, where the note goes into SevenRooms `notes` | choice: `none` · `routine_eta` · `large_party_or_bottle` · `change_or_cancel` · `accessibility_or_safety` · `complaint` · `off_topic_or_abuse` | The bridge's booking-mode fork (`SR_BOOKING_MODE=request` vs reservation): send non-routine notes to operator review instead of auto-booking. Could also flag the BCC email to contact@example.com | Measured: 54 of 185 records carry a non-empty note (the mapper comment says 131 of 185, 71%, are empty; `replay-production.mjs`). Estimated ~5-6 notes/month at the Sept rate (19 × 29%) | Nothing automated. Today the note is passed verbatim to door staff, and the operator reads it in the BCC email. Human cost is seconds per month. No miss rate on record | Keeps a "change my booking" or "party of 20, bottle service?" note from being booked silently as a plain guestlist row once the bridge goes live | Customer PII (free text next to name/email/phone; Jev needs the note only, but it may contain PII) | 3-4 h (call, attribute, bridge branch, tests) | 15% |
| 2 | Plausible-guest screen | `src/lib/signup-guard.ts:123` (`screenSignup`, a 4th check after the email cap) | boolean: "is this a real person's reservation?" over name, email domain, phone shape, note, party size | 422 refusal, or a quarantine flag that the bridge skips | Same 19/month (measured). Spam seen: **none**. No junk or bot rows are documented in this repo or in the bridge docs (measured: `rg -i "junk|spam|bogus|fake"` over both repos' docs) | The heuristics (honeypot, 3 s timer, 5/day per email). Their known miss is stated in the file (`signup-guard.ts:3-8`): "do NOT stop a determined attacker… Real protection is a challenge (Turnstile/hCaptcha)… declined for now" | Stops a fake name reaching a real venue's door list and, when the bridge is live, a real SevenRooms reservation | Customer PII (full guest record) | 3 h | 8% |

**Why #1 ranks first and is still weak:** it is the only real text judgment on a customer-facing
path, and it has a consumer that is waiting for it (the request-vs-reservation fork in
`docs/plans/SIGNUP_TO_SEVENROOMS_AUTOMATION_PLAN.md:123`). At about 6 notes a month, a person
reading the BCC email is cheaper than any integration. It becomes worth building only if traffic
grows by 10× or more, or if the bridge goes live in reservation mode with no human in the loop.
The consumer is really in `sevenrooms-bridge`, so the owner of that repo's sweep should confirm it.

**Why #2 is below it:** a text judge does not fix the stated miss. A determined bot types plausible
names, and a challenge (Turnstile) is the known fix. There is no observed abuse to calibrate against.

## Rejected candidates

- **Newsletter sign-up screening** (`src/pages/api/newsletter.ts:58`). The payload is an email
  address with no guard at all (the file itself says so). There is nothing for a judge to read
  beyond an address, and a regex or honeypot fits better. Volume is unknown (no counter).
- **Contact / inquiry triage.** There is no contact form. `/contact` is static prose that points to
  `contact@example.com` (`src/pages/contact.tsx`). Inbound mail sits outside this repo.
- **Search / intent routing.** There is no site search. The MCP `reso_get_venue` tool takes a slug
  enum with 2 values (`src/lib/mcp.ts:94-97`), so there is nothing to route.
- **Review / feedback sentiment.** There are no reviews. `aggregateRating` is deliberately omitted
  (`src/lib/__tests__/structured-data.test.ts:83`). `rating`/`numberOfReviews` are static venue props.
- **Content moderation of user text.** The only user text is `messageToHost`, covered by #1. It is
  never published on the site.
- **SEO / content checks** (for example "does this copy make an unverifiable claim", which
  `docs/plans/HUMAN_SEO_VISUAL_REBUILD.md:72` raises as spam-policy exposure). The content is about
  10 static prose pages that change a few times a quarter. One-off review by Claude in a session
  beats a standing judge. It has no runtime consumer.
- **i18n quality.** Single locale (`en-CA`, `src/lib/seo.ts:10`). Nothing to check.
- **Agent-readiness / llms.txt drift.** Already deterministic: unit tests plus
  `scripts/verify-agent-readiness.sh` (138 assertions). The outputs are generated from one source,
  so drift is structurally prevented and a probabilistic judge adds nothing.
- **Layout / visual regressions.** Image and DOM judgments, not text of 16 KB or less. The
  layout-oracle already covers them deterministically.

## Evidence notes

- Volumes are measured by earlier sessions' DynamoDB scans cited above. This sweep did not query
  AWS (per the rules). The ~5-6 notes/month figure is estimated (Sept rate × non-empty share).
- Privacy: every candidate on a live path sends customer free text to Vercel under standard
  retention (hobby plan, no zero-data-retention). For #1, send the note alone, never the identity fields.
