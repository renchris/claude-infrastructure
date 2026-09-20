# An absence in your own records bounds the RECORDS, not the world

**The rule.** When a search comes back empty and you are about to write *"there is no way to do
X"*, stop and list the stores you actually searched. If every one of them is a store **we write**
— a config file, our mailbox, our message archive, our database — then the finding is *"we have no
record of X"*, which is a fact about our bookkeeping. Turning it into *"X is impossible"* requires
at least one store **we do not write**, and for anything involving a real-world counterparty that
store is the public web. Name the un-searched store in the verdict line, or do not write the
verdict.

## The incident

`fleet.bottle-menu-cross-contamination` (mission board) carries a live money defect: the
`heist-2026` bottle preset seeds **20 prices 6–40% under Heist's own printed menu**, and The Key
serves a 60/60 copy of that preset, so the under-prices are live in **two rooms of a paying
tenant** (backlog `05f63af4e918`). Its cheapest closing action is one sentence to the venue: *which
list is authoritative?*

On 2026-09-16 a session recorded the blocker as:

> THERE IS NO RECORDED CONTACT FOR THEM ANYWHERE: no leadDomains on the tenant … no email thread in
> the mailbox, no SMS thread … So the money defect this row names **cannot be closed by any agent
> action** — it needs the operator to name who to ask.

Three searches, all correct, all negative:

| store searched | result | who writes it |
| --- | --- | --- |
| `lib/config/tenants.ts` `leadDomains` | absent for `key` | **us** |
| the Outlook mailbox | no thread | **us** (inbound, but our archive) |
| `msg` (iMessage/SMS) | zero hits for "heist", "the key collection" | **us** |

The word that did the damage is **ANYWHERE**. Every store in that table is one we keep. The venue
keeps its own, and it had been publishing an address the whole time. The row then sat 16 days as
operator-gated, and the operator was gated on a question — *"who do we ask?"* — that a search
engine answers in one query.

**Found on 2026-09-20 in four calls:** the group's own operating restaurant publishes
`osetra@thekeycollection.ca` and a phone number on a page signed *"Presented to you by: THE KEY
COLLECTION"*, and `thekeycollection.ca` carries live Google Workspace MX + SPF. Committed with the
retained bytes at `reso data/venue-research/key-collection/`, and the tenant now carries
`leadDomains: ['thekeycollection.ca']` (reso `bd6c89b32`).

## Why the negative was so convincing

Because it was **three** negatives, and they felt like independent confirmation. They are not
independent — they are three views of one thing, *our own filing*. Three correlated nulls read as
overwhelming and carry barely more information than one.

The same absence had a **second** effect that nobody connected: with no `leadDomains`, every
registrant from that venue classified as `'other'` in `lib/alerts/lead-classify.pure.ts`. So the
missing field was simultaneously the reason we "could not find" the decision-maker and the reason
the alert that would have *surfaced* them was suppressed. An empty field can be both the symptom
and the cause, and the loop is invisible from inside either one.

## The second half — your own stores can also be UNREADABLE, which is a third state

Chasing the same contact, the business mailbox `chris@reso.gl` returned
`Failed to acquire token … Please re-login`. That is neither "a thread exists" nor "no thread
exists"; it is **no verdict**, and it demands the opposite action from either (fix the instrument,
do not conclude). It is the same shape as
[[empty-vs-no-surface]]: an emptiness check cannot separate *empty* from *absent*, and here it
cannot separate *empty* from *unreadable*. The correct move was to NOT write the cold email — a
first contact that duplicates a live thread in the mailbox you could not open is worse than
waiting a day.

## The tell, and the cheap check

The tell is a superlative in a negative finding: **anywhere · nothing · no way · cannot be done by
any agent**. Each one silently widens a measured absence into a universal claim.

The check costs one command. Before filing any "we cannot reach / cannot obtain / there is no"
row about an external party, run the obvious public query. For a business that is: its own site
(and the **Wayback** copy, because the live one is often a parked lander), its sibling venues'
sites, the domain's **MX records** — mail can be live while the website is dead — and a plain
search for the domain. Four calls. Against 16 days of a paying customer being under-charged, the
price of the check is not a consideration.

## Companions

[[store-silence-is-evidence-only-if-it-has-a-writer]] — the same family: silence is only evidence
where something would have written. That one asks whether the store has a writer *at all*; this one
asks whether **we** are the only writer, which is the case that feels fully searched.
[[zero-claim-must-name-its-excluded-strata]] — a "0 open" that hides a stratum reads as all-done;
here the excluded stratum was every store outside the company.
[[one-armed-adjudication-only-convicts]] — asymmetric evidence that can only convict.
[[reference-a-refusal-bounds-the-tool-not-the-world]] — a refusal bounds the TOOL; this bounds the
RECORDS. Both get read as facts about the world.
[[empty-vs-no-surface]] — the unreadable-mailbox half above.
[[resident-policy-must-not-restate-perishable-facts]] — the same row's `whyNotNow` also asserted
"landing/deploying in reso spends money", false since the 2026-08-02 cut-over and refuted live by
`scripts/land-status.sh` on the day this was written.
