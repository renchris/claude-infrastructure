# P3-quotalimits — receipts

Unit: is `quotaLimits` a reliable structured source for reset time and cap class?
Date: 2026-09-19. Read-only. All commands run from `~`.

**Verdict: PARTIAL.** Where `quotaLimits` is emitted it is *perfect* — 408/408 of its
`resetsAt` values agree with the prose to the minute, and `rateLimitType` matches the
independently-derived text class 408/408 with zero crossings. But it is **emitted for only
two of the four cap classes**: it is absent on the Fable cap (35/35 events on the CURRENT
binary 2.1.260) and on monthly-spend, and absent on every CLI ≤ 2.1.220. So it is a
**complete source for `five_hour`/`seven_day` on 2.1.260 and a partial source overall**;
a text fallback is mandatory and is what the shipped code gets wrong.

---

## 0. Corpus and the two dedup traps

```
$ rg --no-messages -n --with-filename '"apiErrorStatus"' .claude/projects \
    .claude-next/projects .claude-secondary/projects .claude-tertiary/projects \
    .claude-quaternary/projects > apierr.pl.raw
=> 1306 lines, 2.1M, 1.75s wall
```

**Trap 1 — symlink double-count.** `.claude-next/projects` is a symlink to
`.claude/projects` (memory: *two-roots-one-symlink-double-counts*):

```
$ readlink -f ~/.claude-next/projects
=> /Users/chrisren/.claude/projects
```

**Trap 2 — the same logical event is copied into several files.** Deduping by
`(realpath, lineno)` still leaves 917 "records" across 767 files but only 77 sessionIds,
because a `.jsonl` and its `.handed-off` twin (and salvage copies) each hold the record.
The correct event identity is the record's own `uuid`:

```
$ python3 a10.py
raw matched lines 1305 -> UNIQUE events by uuid 596
copies per unique event: max 4  median 2
```

**Every number below is unique-by-uuid.** The structural separation is identical under all
three dedup choices, which is why the conclusion is robust; only the magnitudes move.

Corpus: **596 unique api-error events**, 2026-07-11T07:56Z .. 2026-09-19T20:29Z,
CLI 2.1.114 / 2.1.183 / 2.1.215 / 2.1.219 / 2.1.220 / 2.1.260, across 4 real config dirs.

---

## 1. `error == "rate_limit"` ⟺ `apiErrorStatus == 429`, exactly

```
$ python3 a10.py   # (error, apiErrorStatus) over 596 unique events
   ('rate_limit', '429')            490
   ('server_error', '529')           69
   ('authentication_failed', '401')  25
   ('unknown', '400')                 5
   ('oauth_org_not_allowed', '403')   3
   ('server_error', '500')            2
   ('invalid_request', '400')         2
```

490/490 both directions. No other error class ever carries 429, and no rate_limit ever
carries another status. **This pair is the gate; nothing downstream needs the text to
decide *whether* it is a limit.**

## 2. …and it is COMPLETE: no limit hides in a status-less api error

346 api-error records carry `isApiErrorMessage:true` with **no** `apiErrorStatus` key at all
(transport-level failures never got an HTTP status):

```
$ rg '"isApiErrorMessage":true' <4 dirs> | grep -vc 'apiErrorStatus'   => 348
$ grep -c '"error":"rate_limit"'            /tmp/noStatus.jsonl        => 0
$ grep -ci "hit your\|reached your\|spend limit" /tmp/noStatus.jsonl   => 0
```

Their shapes are network (`ENOTFOUND` 188, `ECONNRESET`, stalled/closed mid-stream, "computer
went to sleep"), auth (`Not logged in · Please run /login` 29), and `invalid_request`
(safeguards, `Prompt is too long`). **Zero are limits.**

## 3. The separation table — the core measurement

```
$ python3 a10.py     # 490 unique rate_limit events
class          ver       ql_key  errorDetails  rateLimitType   n
fable          2.1.260   False   True          None             35
monthly_spend  2.1.183   False   False         None             14
monthly_spend  2.1.215   False   False         None              1
monthly_spend  2.1.219   False   False         None              1
session        2.1.220   False   False         None             24
session        2.1.260   True    False         five_hour       362
weekly         2.1.220   False   False         None              7
weekly         2.1.260   True    False         seven_day        46
```

Read off it:

* `quotaLimits` present **⟺** (CLI 2.1.260 **and** class ∈ {session, weekly}). 408/408.
* `rateLimitType` ⟺ text class, **zero crossings**: `five_hour` ⟺ "session limit" 362/362,
  `seven_day` ⟺ "weekly limit" 46/46.
* Coverage: **408/490 = 83.3% of all rate_limit events**; on the current binary alone,
  408/443 = **92.1%**, and the entire 7.9% miss is one class — **Fable**.
* The key is **ABSENT**, not null-valued, when missing (`'quotaLimits' in rec` is False).
  A consumer must use `.get()` and treat absent and null alike.

## 4. `resetsAt` vs the prose: 408/408, to the minute, across two timezones

```
$ python3 (a4/final on unique events)
UNIQUE ql-bearing rate_limit events: 408
resetsAt->local vs prose:  AGREE 408  DISAGREE 0  UNPARSEABLE 0
date-prefixed prose form ("Mon DD at ..."): 0
resetsAt minute values: {40:115, 30:136, 20:73, 0:55, 50:17, 10:12}
resetsAt vs the record's own timestamp: future 408, past-or-equal 0
```

Method: parse `resets (H)(:MM)?(am|pm) \((TZ)\)` out of the message text, convert
`quotaLimits.resetsAt` (epoch) into that TZ with `zoneinfo`, compare (hour, minute).

**The prose TZ is not the machine's and is not per-account.** Over the corpus the
parenthetical is `America/Chicago` 838 / `America/Vancouver` 144 — and *both appear inside the
same config dir* (`.claude-secondary`: 78 / 83). A text-only parser must honour the
parenthetical; `quotaLimits.resetsAt` is epoch and immune. `resetsAt` always lands on a
10-minute boundary and is always in the future relative to the record.

## 5. The Fable cap: detectable, but its reset is UNMEASURABLE

Full shape, `~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/2d71c6d8-c8be-4fd6-a1c9-8ec08a892019.jsonl:1252`:

```
error                'rate_limit'      apiErrorStatus 429     version '2.1.260'
quotaLimits          <key absent>
errorDetails         "429 {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",
                      \"message\":\"This request would exceed your account's rate limit.
                      Please try again later.\"},\"request_id\":\"req_011CeynBt3xGLdNM1jwjJ8vm\"}"
text                 "You've reached your Fable limit. Run /usage-credits to continue or
                      switch models with /model."
message.model        '<synthetic>'   (nearest preceding real model: "claude-fable-5-1")
```

* **68 raw / 35 unique events, all on 2.1.260, all 2026-09-10..2026-09-12.** One verbatim
  string, no variants.
* `errorDetails` is the raw upstream body and carries **no reset time**. So for a Fable cap
  there is no reset time *anywhere in the record* — not structured, not in prose.
  A Fable-capped session cannot be scheduled by `resetsAt`; it must be polled, or resolved by
  `/model` (the record's own advice).
* `errorDetails` present ⟺ Fable, **35/35 with 0 false positives among the other 455
  rate_limit events** — a usable structured discriminator. ⚠️ But it is *not* Fable-specific
  in general (2 `invalid_request` "Prompt is too long" events also carry it), it is confounded
  with "quotaLimits absent on 2.1.260", and n=35 over a 2-day window. Treat it as
  **corroborating**, keep the text as the primary Fable key.
* Model identity is recoverable only from the *preceding* real assistant record's
  `message.model`; the error record itself says `<synthetic>`.

## 6. monthly_spend: unmeasured on the current binary

16 unique events, **all on CLI ≤ 2.1.219, last seen 2026-07-25**. `quotaLimits` absent,
`errorDetails` absent. Two verbatim strings:

```
14 x "You've hit your monthly spend limit · raise it at claude.ai/settings/usage"
 2 x "You've hit your monthly spend limit · raise it at claude.ai/settings/usage?from=cc_cli_limit_message"
```

**UNMEASURABLE whether 2.1.260 emits `quotaLimits` for this class** — no monthly_spend event
exists on 2.1.260 in this corpus. Do not assume either way; the text prefix is the only safe key.

## 7. The 529 question: answered, and the shipped guard is DEAD

There is **no** record where `error == "rate_limit"` wears a 529 coat. The 529 class is
`error:"server_error"`, `quotaLimits` absent 0/71, and the word "limit" appears in **0** of
the 71 server_error texts. The two classes are lexically and structurally disjoint.

Actual 529 text (69 events, 2026-08-17..2026-09-03, all 2.1.220):

```
"API Error: 529 Overloaded. This is a server-side issue, usually temporary — try again in a
 moment. If it persists, check https://status.claude.com."
```

**But `lr-audit.py:80` guards against a different string:**

```
$ sed -n '80p' claude-infrastructure/scripts/limit-recover/lr-audit.py
SERVER_529 = "API Error: Server is temporarily limiting requests"
$ rg '"isApiErrorMessage":true' <4 dirs> | grep -c "Server is temporarily limiting requests"
=> 0                      # positive control: "529 Overloaded" => 104 lines
```

That literal occurs in 119 *files* — but only ever as prose (transcripts quoting the source).
It matches **0 api-error records** in a 924-event corpus spanning 2.1.114→2.1.260.
*(A token's presence never establishes its role — the file-count is the trap here.)*
Whether it was correct for a CLI older than 2.1.114 is UNMEASURABLE.

## 8. The key set is NOT stable — use `.get()`, never `[]`

```
$ python3 a6.py   # distinct quotaLimits key-sets
430 x [isUsingOverage, overageDisabledReason, overageStatus, rateLimitType, resetsAt,
       status, unifiedRateLimitFallbackAvailable]
365 x [... same 7 ..., lowPriorityMaxWaitSeconds, lowPriorityOffer, lowPriorityRetryAfterSeconds]
```

The `lowPriority*` trio is a **server-side A/B**, not a version rollout: `lowPriorityOffer`
is `"control"` 365/365, `five_hour` only, `MaxWaitSeconds` 1200 / `RetryAfterSeconds` 20
constant, and the two arms' date ranges **overlap** (with: 09-05..09-19; without: 09-10..09-19).
Constant across all 408: `status="rejected"`, `overageStatus="rejected"`,
`overageDisabledReason="org_level_disabled"`, `isUsingOverage=false`,
`unifiedRateLimitFallbackAvailable=false` — i.e. on this fleet there is **no overage and no
unified fallback to offer**, so neither field can currently discriminate anything.

## 9. Census consequences (adjacent, measured)

* 490 events / **77 distinct sessions**. Median 2 events per session, max 341.
  **Dedupe by sessionId and take the LAST event** — never count records.
* **6 of 77 sessions span more than one limit class** and **10 of 77 carry more than one
  distinct `resetsAt`** (a five_hour cap in the morning, a seven_day one that night). The
  first matching record in a transcript is not the answer; the last one is.

## 10. Two shipped detectors, measured against this corpus

| site | pattern | misses |
|---|---|---|
| `scripts/limit-recover/lr-audit.py:75-79` `LIMIT_PREFIXES` | session / weekly / monthly_spend | **fable — 35/490 events (7.1%), 100% of the current binary's non-structured limits** |
| `scripts/limit-recover/lr-audit.py:80` `SERVER_529` | `"API Error: Server is temporarily limiting requests"` | **matches 0/924 events — dead string** |
| `scripts/limit-recover/lr-reset-poller.sh:746` | `grep -E "You've hit your (session\|weekly) limit"` | **fable AND monthly_spend — 51/490 events (10.4%)** |
| `lr-audit.py:81-83` `RESET_RE` | optional `"Mon DD at "` prefix | not a defect — that form occurs 0/408; the regex is a superset |

Neither shipped detector reads `quotaLimits` at all. Both do text-first on a strict subset of
the strings, so both are strictly worse than the structured field they ignore.

---

## FIXTURES — verbatim, with sid and file:line

```
five_hour  ~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-143039-68221/07e30aeb-bb48-4771-9e0d-feff40ceb4cf.jsonl:210
           sid 07e30aeb-bb48-4771-9e0d-feff40ceb4cf  2026-09-19T20:29:28.332Z  ver 2.1.260
           text "You've hit your session limit · resets 4:30pm (America/Chicago)"
           ql   {"status":"rejected","resetsAt":1789853400,"unifiedRateLimitFallbackAvailable":false,
                 "rateLimitType":"five_hour","overageStatus":"rejected",
                 "overageDisabledReason":"org_level_disabled","isUsingOverage":false,
                 "lowPriorityOffer":"control","lowPriorityRetryAfterSeconds":20,
                 "lowPriorityMaxWaitSeconds":1200}

seven_day  ~/.claude-tertiary/projects/-Users-chrisren-Development-personal/26a195ae-4db4-4b62-add8-a2002fcb5010.jsonl.handed-off:1453
           sid 26a195ae-4db4-4b62-add8-a2002fcb5010  2026-09-15T04:03:48.641Z  ver 2.1.260
           text "You've hit your weekly limit · resets 7am (America/Chicago)"
           ql   {"status":"rejected","resetsAt":1789473600,"rateLimitType":"seven_day",
                 "overageStatus":"rejected","overageDisabledReason":"org_level_disabled",
                 "isUsingOverage":false,"unifiedRateLimitFallbackAvailable":false}
           (note: no lowPriority* keys — the other arm of the A/B)

fable      ~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/2d71c6d8-c8be-4fd6-a1c9-8ec08a892019.jsonl:1252
           sid 2d71c6d8-c8be-4fd6-a1c9-8ec08a892019  2026-09-12T15:26:49.089Z  ver 2.1.260
           text "You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."
           ql   <key absent>   errorDetails present (raw 429 rate_limit_error body, no reset)

monthly    ~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/e0bd7f43-1ae5-448b-bc64-d4876fa4d224.jsonl.handed-off:649
           sid e0bd7f43-1ae5-448b-bc64-d4876fa4d224  2026-07-25T09:05:42.808Z  ver 2.1.219
           text "You've hit your monthly spend limit · raise it at claude.ai/settings/usage?from=cc_cli_limit_message"
           ql   <key absent>

529 (NOT a limit)
           ~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/1a2071b2-98bc-463a-b6b1-3336bbd488e0.jsonl:715
           error "server_error"  apiErrorStatus 529  ver 2.1.220
           text "API Error: 529 Overloaded. This is a server-side issue, usually temporary — try again in a moment. If it persists, check https://status.claude.com."

login cliff (NOT a limit, no apiErrorStatus)
           error "authentication_failed"  ver 2.1.220
           text "Not logged in · Please run /login"                      (29 records)

context wall (NOT a limit, terminal — must never enter a reset queue)
           ~/.claude/projects/-Users-chrisren-Development--worktrees-wt-cc-202600-2515/f0947ae8-1b95-45fa-9a16-d4d2b4e7f902.jsonl:919
           error "invalid_request"  apiErrorStatus 400  ver 2.1.260   text "Prompt is too long"

synthetic (corpus contamination — exclude from any rate)
           error "unknown" 400  text "API Error: 400 {... \"T9 probe: synthetic 400\"}"
```

---

## THE CLASSIFICATION FUNCTION

Shipped at `lr_classify.py` beside this file (107 lines, pure stdlib, no forks, no I/O —
callable from the single-process census prototype without adding a subprocess).

Self-test over the whole corpus:

```
$ python3 selftest.py
unique api-error events tested: 596
rate_limit events: kind CORRECT 490  WRONG 0
non-limit events (correctly excluded): 106
limits MISSED among non-limit verdicts: 0
kind distribution: {'five_hour':386, 'seven_day':53, 'monthly_spend':16, 'fable':35}
source distribution: {'quotaLimits':408, 'text':82}

$ python3 (false-positive arm, the 348 status-less api errors)
unique status-less api-error events: 328  {'not-limit': 328}
```

**924 unique api-error events, 0 misclassifications in either direction.**

⚠️ **Honest limit on that figure.** For the 82 text-fallback events the ground-truth label is
derived from the same text the classifier reads — that arm is circular and proves only that
the regexes are anchored correctly. The **non-circular** validation is the 408 structured
events, where the classifier used `rateLimitType` and the label came from the prose: those two
independent channels agreed 408/408.

Design notes that are load-bearing:

1. **Gate on `error == "rate_limit"` (≡ `apiErrorStatus == 429`), never on the text.** It is
   exact (490/490) and complete (0/328 status-less api errors are limits), and it keeps
   network drops, the login cliff, safeguard refusals and `Prompt is too long` out of the
   recovery queue by construction.
2. **Structured arm first**, because it is the only one that yields an epoch (no TZ parsing,
   no "next occurrence" guess) and the only one that survives a copy-writing change.
3. **Text arm is mandatory, not a nicety** — it is the sole source for `fable` on the *current*
   binary and for every class on ≤2.1.220.
4. **Both arms emit one vocabulary** (`five_hour | seven_day | fable | monthly_spend`) so a
   consumer never branches on provenance; `source` is carried for audit only.
5. `recoverable_by_waiting` is False for `fable` and `monthly_spend` — the caller must route
   those to `/model` and to the operator respectively, not to a reset timer.

## 11. Latency — the structured marker is an exact, sub-second whole-fleet scan

```
$ time rg -l '"apiErrorStatus":429' <4 real project dirs> | wc -l
775
0.76s user 2.53s system 550% cpu  0.597 total
```

**0.60 s wall over the whole corpus**, against the shipped `lr-fleet.sh --locate` at 35.5 s
(lead's measurement today) — ~59x, and with **no text regex in the hot path**: the literal
`"apiErrorStatus":429` is exact by §1 (490/490 both directions) and matched 0 non-limits.
The text arm (§FIXTURES) is then needed only on the ≤8% of hits the structured field misses,
i.e. only after the candidate set is already down to a handful of files.

Suggested composition for the census, cheapest first:
1. `rg -l '"apiErrorStatus":429'` — exact candidate files, sub-second, no forks per hit.
2. Per candidate, read the 128 KB tail once, take the **LAST** such record (§9 — 6/77 sessions
   change class, 10/77 change `resetsAt`), parse with `lr_classify.classify()`.
3. Group by account (config dir) — the operator's stated shape: many sessions cap at once on
   one account, and they will share a `resetsAt` to the minute (§4, §8: `resetsAt` is a
   server-side 10-minute boundary, identical across every session on that account).
