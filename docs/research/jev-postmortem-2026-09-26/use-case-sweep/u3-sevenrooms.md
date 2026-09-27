# U3: sevenrooms-bridge, Jev use cases

**What the repo does.** It is a one-way bridge. A reso-website guestlist sign-up (a DynamoDB `guestlist-api` INSERT) becomes a SevenRooms manager-guestlist row. The repo also holds an offline analysis stack over a frozen six-year guestlist mirror (`~/.sevenrooms-mirror/guestlist.sqlite`, 126,076 rows, last night 2026-08-22). No part of the repo syncs data both ways, fuzzy-matches records or reconciles statuses.

**Existing LLM calls: zero.** Measured with `rg -i "openai|anthropic|generateText|llm|gpt"` excluding node_modules and dist. The only hits for "claude" are `~/.claude` paths and substring matches such as `restoreAllMocks`.

**Volume anchors.**
- Live sign-ups run at about 0.2 per day. Source: the measured figure in `docs/AWS_NOTIFICATION_AUDIT.md:39`.
- The source table has held 186 records in its whole life. Of those, 47 carry a non-empty `messageToHost`. Source: `docs/NOTES_CONVENTION.md:80`.
- Mirror counts, measured by read-only python3/sqlite3 queries against the local DB:
  - 83,922 rows have a note, across 6,282 distinct note strings.
  - 2026 has 648 distinct notes, and 146 of them cover 95% of noted rows.

## Ranked use cases

| # | Name | Plug-in (file:line) | Judgment (question → keys) | Consumer | Volume | Replaces · known miss | Business value | Privacy | Effort | Conviction |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Door-note comp/perk classifier: an independent second opinion on `is_comp_v2` | `scripts/analysis/build_db.py:54` (COMP_RE), `:60` (DRINK_RE), `:123` (CHANNELS), applied at `:341-348` | **choice** "What does this door note grant?" → `comp_cover_with_deadline` / `comp_cover_all_night` / `drink_only` / `cover_and_drink` / `no_perk_instruction` / `party_mix_code` / `partner_or_ticketing_label` / `other_logistics`. **boolean** "Names an outside partner, brand or ticketing source?" | build_db.py → the `nights`/`hist` views → `docs/SCORECARDS/PROMOTERS.md:77`, `VENUE_KPI.md:507` and the comp ceilings in `PLAYBOOK_2027.md`. Operator comp-policy decisions. | One-off pass over 6,282 distinct notes, measured. Estimated from ~300 tokens/call: under $0.10 and about 7 h at 14.8 calls/min. After that it re-runs only when the mirror is re-swept. No recurring sweep exists. | A keyword regex stack. **Measured miss:** COMP_RE scored Twelve West's bare `10:30` notes (2,866 rows, 32.0% of its 2026 venue-year) as full price, a 32-point error on the comp share (`build_db.py:69-83`). The same fix flipped a regression sign from −0.107 to +0.042 (`TWELVE_WEST.md:290`). Remaining gaps, measured: 373 unclassified noted rows in 2026; 2,003 rows comp-flagged only via bare `gl` (32 distinct strings); 27 drink-only notes counted as cover comps. | Catches the next vocabulary drift before it silently re-sizes the comp giveaway that venue policy is set on. | internal. Notes are promoter-written; a few contain third-party names ("invited by …"). | 4-6 | 30% |
| 2 | Guest-message triage before it reaches the door list | `src/map/mapper.ts:36` (PLACEHOLDER_NOTE) and `:83` (`buildNote([... signup.messageToHost])`) | **choice** "What is this guest message to the host?" → `occasion` / `request_needing_host_action` / `test_or_junk` / `empty_placeholder` / `chit_chat`. Drop the message on `empty_placeholder`/`test_or_junk` at p≥0.95. Log and page on `test_or_junk` without refusing the booking. | The mapper's note builder, which the door iPad reads. The operator alert path (`handler.ts:695` neighbourhood). | About 0.2 sign-ups/day, of which ~25% carry a message. Estimated: ~1-2 calls/week. | A whole-string placeholder regex. Its own header says it caught 1 of 54 non-empty messages. The documented noise it misses: `:)`, `My message`, `MESSAGE`, `ayy`, `another test again` (`NOTES_CONVENTION.md:81`). The synthetic-guest guard only recognises RFC-reserved email domains. | A cleaner door row for website guests. Also an early flag when a test sign-up with a real-looking address reaches production. | customer PII (guest free text; send the message only, never the name or email) | 4 (Lambda needs a fail-open network call and a gateway key in Secrets Manager) | 12% |

## Rejected candidates

- **Reservation matching and read-back.** `judgeReadBack` (`src/channels/manager.ts:719`) and the scorecard match on the reservation/entity id we created. That is deterministic, and by design an unreadable id means *inconclusive*.
- **Guest identity dedup.** `guest_key` at `build_db.py:156` knowingly over-merges: 14.3% of keyed rows fall under keys seen at both clubs on the same night. The only inputs are first and last name, and email is filled 0% historically, so Jev has no signal beyond the strings. It would also mean shipping 126k guest names out.
- **Promoter identity merge.** 32 display names hold 2+ login keys. The login key is authoritative, and 436 keys can be reviewed by hand once.
- **Status reconciliation.** ARRIVED / NOT_RECONCILED / NO_ENTRY is an enum. NO_ENTRY was used 17 times in six years, so there is nothing to judge.
- **Venue mapping.** `src/map/venues.ts` maps 3 distinct titles exactly and fails loudly. A fuzzy judge could book the wrong venue.
- **Tags, VIP, allergy, bottle intent.**
  - Tags have no text column, and the VIP suffix appears on 86 rows in six years. `PLAYBOOK_2027.md:360` formally refuses features built on them.
  - Nightclub guestlists carry no allergy field.
  - Bottle intent could only come from `messageToHost`, which has about 47 non-empty values in its lifetime. Folded into #2.
- **Live note-entry classifier** (`docs/RESO_TELEMETRY_DESIGN.md:589`, "comp til 1030 → [✓ Comp cover · until 22:30]"). It is unbuilt and belongs in a reso app repo, not here. Its deadline half is regex-trivial: two values cover 96.1% of 40,390 parsed deadlines.
- **Replacing the synthetic-guest refusal.** Commit `b03a348` explicitly chose a non-heuristic predicate so that a real guest can never be dropped. A probabilistic refusal reintroduces exactly that risk. The advisory-only version is folded into #2.
- **PII gate name detection** (`scripts/analysis/pii_sweep.py`). Asking an external judge "is this a guest name?" would send suspected guest names off-machine, which defeats the gate.
- **Error and alarm classification.** It is keyed on structured `errorName`/`kind`/`status` fields by design (`handler.ts:51-83`), so there is no free text to judge.
- **House-note derivation** (`notes-ema.py`). It is a deterministic recency-weighted ranking, not a judgment.

**Bottom line.** The live bridge has no judgment worth a network hop at 0.2 events/day. The one real, if modest, case is offline: #1 re-labels the frozen mirror's 6,282 distinct door notes once, cheaply, as an independent check on the regex that already mis-sized a venue's comp share by 32 points.
