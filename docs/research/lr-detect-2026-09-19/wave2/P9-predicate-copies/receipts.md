# P9 — predicate copies: receipts

Unit: P9-predicate-copies · 2026-09-19 · repo read-only at /Users/chrisren/Development/claude-infrastructure
Premise under test: "One shared limit predicate can replace the copies."
Verdict: **PARTIAL** — the copies are real (16 sites) and they genuinely disagree, but they are not
one predicate wearing 16 hats. They answer three different *questions* over two different *input
domains*. A single SSOT is correct for exactly one of those questions (membership + sub-kind over
transcript JSONL) and would be wrong for the other two.

---

## R1 — the census: every copy, with file:line and exact pattern

| # | site | exact pattern / test | question it answers | input domain |
|---|---|---|---|---|
| 1 | `scripts/limit-recover/lr-fleet.sh:108` | `LIMIT_RE="You've (hit\|reached) your (session\|weekly\|fast\|monthly spend\|Fable)? ?limit"` | membership (limit) | transcript JSONL |
| 2 | `scripts/limit-recover/lr-fleet.sh:122` | `NET_RE="(Can't reach the API server\|ENOTFOUND\|ECONNREFUSED\|ETIMEDOUT\|socket hang up)"` | membership (network) | transcript JSONL |
| 3 | `scripts/limit-recover/lr-fleet.sh:123` | `BLOCK_RE="($LIMIT_RE\|$NET_RE)"` | cheap scan pre-filter | transcript JSONL |
| 4 | `scripts/limit-recover/lr-fleet.sh:143` `lf_kinds_of()` | python `re` over LIMIT_RE/NET_RE, **envelope-gated** (`type==assistant` ∧ `isApiErrorMessage`) | sub-kind (limit\|network\|other), last + all | transcript JSONL |
| 5 | `scripts/limit-recover/lr-lib.sh:55` (in `lr_tier_from_transcript`) | `if "hit your" in txt or "reached your" in txt:` | "where did the limit fall" (tier pick boundary) | transcript JSONL |
| 6 | `scripts/limit-recover/lr-lib.sh:152` (in `lr_last_api_error`) | `"limit" if "You've hit your" in txt else "other"` | sub-kind for the recover-inject hook | transcript JSONL (128 KB tail) |
| 7 | `scripts/limit-recover/lr-reset-poller.sh:566` | `SPEND_RE="(hit\|reached) your monthly spend limit"` (used `grep -iE`) | sub-kind (billing) | transcript JSONL tail |
| 8 | `scripts/limit-recover/lr-reset-poller.sh:746` | `grep -E "You've hit your (session\|weekly) limit"` ∧ `isApiErrorMessage:true` | membership pre-filter | transcript JSONL tail |
| 9 | `scripts/limit-recover/lr-reset-poller.sh:771` | `e.get('kind') in ('session','weekly','fable')` | sub-kind allowlist — **structurally dead for `fable`**, see R5 | lr-audit JSON |
| 10 | `scripts/limit-recover/lr-audit.py:75-79` + `:244 classify_limit_text` | `LIMIT_PREFIXES` = session/weekly/monthly_spend, matched with **`text.startswith(prefix)`** | sub-kind (authoritative) | transcript JSONL |
| 11 | `scripts/limit-recover/lr-audit.py:81 RESET_RE` | `r"resets (?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2}(?::\d{2})?(?:am\|pm)) \(([^)]+)\)"` | **reset time, parsed from English prose** | transcript JSONL |
| 12 | `bin/cc-classify:312` `recent_api_limit()` | `grep -qiE 'session limit\|weekly limit\|usage limit\|limit ·\|resets\|monthly spend limit\|spend limit\|billing'` over `isApiErrorMessage` content, `tail -n 60` | reap-safety veto ("NEVER reap") | transcript JSONL |
| 13 | `scripts/desk-invariant.sh:156` `cap_stunned()` | `grep -qiE 'monthly spend limit\|spend limit\|session limit\|weekly limit\|usage limit\|limit ·\|resets\|cannot determine the safety\|temporarily unavailable\|billing'`, **raw tail, NO envelope** (deliberate, `:149-152`) | stun observation incl. classifier outage | transcript JSONL raw tail |
| 14 | `scripts/handoff-fire.sh:9236` | shell glob `*"usage limit"*` → `rate-limited` | account-probe verdict | **CLI stdout** |
| 15 | `scripts/cloud-ceiling-probe.sh:212` | `grep -iE 'usage limit\|rate limit\|quota\|too many\|weekly limit\|limit reached\|exceeded\|429'` | probe verdict | **CLI stdout** |
| 16 | `scripts/lib/cloud-create.sh:174` | `grep -qiE 'limit\|quota\|rate.?limit\|exceeded'` → `refused-quota` | create-refusal class | **CLI stdout** |

Consumers that inherit rather than own a copy:
- `hooks/recover-inject.sh:94-102` — reads `lr_last_api_error`'s `$_kind` and branches `[ "$_kind" = limit ]`; inherits copy #6's blind spot verbatim.
- `hooks/net-recover-arm.sh:122-140` — sources `lr-lib.sh` + `lr-probe.sh`; no own predicate.
- **`hooks/stop-failure-marker.sh` — owns NO text predicate at all.** It keys on the structured `error` field (`:74 ERR="$(jqs '.error // .reason // ""')"`, `:92 CAUSE_KEY`). This is the shape the SSOT should take.

---

## R2 — the copies disagree, on one string, five ways

```
$ FABLE="You've reached your Fable limit. Run /usage-credits to continue"
  lr-fleet:108  LIMIT_RE          => MATCH
  lr-fleet:122  NET_RE            => NO-MATCH
  poller:746    pre-filter        => NO-MATCH   (poller blind)
  lr-lib:152    kind              => "other"
  lr-audit      classify_limit_text => "other_api_error"
  cc-classify:312 recent_api_limit  => NO-MATCH
```

Full 6-text × 9-predicate matrix (`/tmp/p9matrix.py`, reproduced in R7):

```
text        lr-fleet:108 | NET_RE | poller:746 | SPEND_RE | lr-lib:152 | lr-lib:55 | lr-audit        | cc-cls:312 | desk:156
five_hour   Y            | .      | Y          | .        | limit      | Y         | session         | Y          | Y
seven_day   Y            | .      | Y          | .        | limit      | Y         | weekly          | Y          | Y
spend       Y            | .      | .          | Y        | limit      | Y         | monthly_spend   | Y          | Y
fable       Y            | .      | .          | .        | other      | Y         | other_api_error | .          | .
server_529  .            | .      | .          | .        | other      | .         | server_529      | .          | .
network     .            | Y      | .          | .        | other      | .         | other_api_error | .          | .
```

Note the intra-file disagreement: **`lr-lib.sh:55` and `lr-lib.sh:152` are 97 lines apart in ONE
file and split on Fable** — `:55` accepts `"reached your"`, `:152` does not.

---

## R3 — measured recall of every copy over 209 REAL rate-limit records

Corpus: every `isApiErrorMessage:true` record in all four config stores.

```
$ grep -rh 'isApiErrorMessage":true' ~/.claude*/projects/*/*.jsonl > /tmp/p9all.jsonl
$ wc -l /tmp/p9all.jsonl
     565 /tmp/p9all.jsonl

-- error x apiErrorStatus --
  ('rate_limit', 429)            209
  ('server_error', None)         146
  ('server_error', 529)           86
  ('authentication_failed', 401)  44
  ('authentication_failed', None) 38
  ('invalid_request', None)       21
  ('oauth_org_not_allowed', 403)   6
  ('unknown', 400)                 5
  ('invalid_request', 400)         4
  (None, None)                     3
  ('unknown', None)                2
  ('server_error', 500)            1
```

Ground truth = the 209 `error=="rate_limit"` records.

```
ground truth: error=='rate_limit' records = 209
  lr_fleet     209/209  recall 100.0%  MISSES 0
  poller       190/209  recall  90.9%  MISSES 19
  lr_lib_kind  190/209  recall  90.9%  MISSES 19
  lr_audit     190/209  recall  90.9%  MISSES 19
  cc_classify  190/209  recall  90.9%  MISSES 19
  struct       209/209  recall 100.0%  MISSES 0     <- error=='rate_limit' && apiErrorStatus==429
```

**All 19 misses are the same string**, the Fable cap. Four independent copies lose the same 9.1%.

False-positive check in the other direction, over the 356 non-`rate_limit` api-error records:

```
non-rate_limit api-error records matching cc-classify:312 regex: 0 {}
...matching desk-invariant:156 regex:                            0 {}
```

So the wide text regexes cost nothing in precision *inside the envelope*; they only under-recall.

---

## R4 — the structural key exists, is 100%-recall, and is consumed by NOTHING

```
$ grep -rn "quotaLimits\|resetsAt\|rateLimitType\|unifiedRateLimit" \
    --include='*.sh' --include='*.py' --include='*.bats' --include='*.md' . | grep -v node_modules
(zero lines)
$ # positive control on the same tree:
$ grep -rn "isApiErrorMessage" --include='*.py' scripts/limit-recover/ | wc -l
       5
```

A real record (`error=='rate_limit'`, cw 2.1.260):

```json
{"error":"rate_limit","apiErrorStatus":429,
 "quotaLimits":{"status":"rejected","resetsAt":1789025400,
   "unifiedRateLimitFallbackAvailable":false,"rateLimitType":"five_hour",
   "overageStatus":"rejected","overageDisabledReason":"org_level_disabled",
   "isUsingOverage":false,"lowPriorityOffer":"control",
   "lowPriorityRetryAfterSeconds":20,"lowPriorityMaxWaitSeconds":1200}}
```

Coverage of the structured field over the 209:

```
  rate_limit total: 209 | with quotaLimits: 180  (86.1%)
  rateLimitType: [('five_hour', 167), (None, 29), ('seven_day', 13)]
```

The 29 without `quotaLimits`: **19 Fable** + 10 older-binary session/weekly rows.

**Consequence for `lr-audit.py:81 RESET_RE`:** for 180 of 209 records the reset is already an
epoch integer, and the shipped code instead parses English prose (`resets 7:50pm (America/Vancouver)`)
through `zoneinfo`, with a `return None` on `ZoneInfo is None` and a bare `except` swallowing
`ValueError/KeyError/OSError` (`:239-240`). Every one of those failure modes vanishes on `resetsAt`.

---

## R5 — the real Fable record exists on disk, and the safety gate's obligation is stale

`scripts/limit-reset-safety-gate.sh:114-121` declares:

> LR-blind — DECLARED, not closed … The FABLE-scoped limit message's verbatim shape has never been
> captured (no real fixture exists). … OBLIGATION: the first real Fable-limit capture must be
> fixture-ized into $SUITE

It has been captured, 19 times, on this box:

```
TEXT   : "You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."
error  : rate_limit
status : 429
quotaLimits present: False | value: None
errorDetails: "429 {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",
               \"message\":\"This request would exceed your account's rate limit...\"},\"request_id\":\"req_011Cev...\"}"
version: 2.1.260
top-level keys: [apiErrorStatus, cwd, entrypoint, error, errorDetails, gitBranch,
                 isApiErrorMessage, isSidechain, message, parentUuid, requestId,
                 sessionId, session_id, timestamp, type, userType, uuid, version]
```

And no test anywhere pins it:

```
$ grep -rc "Fable limit" tests/*.bats | grep -v ':0'
(no output => zero fixtures in the entire bats suite)
```

The safety gate's own escape hatch ("IF the Fable message carries the weekly prefix it parks as
kind=weekly (covered)") is **refuted by the capture**: the text starts `You've reached your Fable`,
so `classify_limit_text`'s `startswith` returns `other_api_error` and the session is NEVER PARKED.

**A DOUBLY DEAD BRANCH.** `lr-reset-poller.sh:771` filters `e.get('kind') in ('session','weekly','fable')`
— but:

```
$ grep -cn "fable" scripts/limit-recover/lr-audit.py
0
```

`lr-audit.py` contains the token `fable` zero times, so it can never emit `kind=='fable'`. The
branch is unreachable from the producer *and* unreachable from the `:746` pre-filter. Someone wrote
the consumer for a producer change that never landed.

---

## R6 — test inventory: which copies are pinned

```
lr_last_api_error          tests/net-recover-arm.bats
lr_tier_from_transcript    tests/lr-lib.bats
lf_kinds_of                (no by-name pin; exercised indirectly via lr-fleet.bats --locate)
NET_RE                     tests/net-recover-arm.bats
SPEND_RE                   (no by-name pin; behaviour pinned by lr-reset-poller.bats:154-179 spend fixtures)
classify_limit_text        (no by-name pin)
RESET_RE                   tests/lr-reset-poller.bats
recent_api_limit           (no by-name pin; exercised via cc-classify.bats:145/386/794/1078)
cap_stunned                (no pin found, by name or by fixture)
```

Every limit fixture in the suite uses the `hit your` spelling:

- `tests/lr-reset-poller.bats:101` session · `:168,:179` monthly spend
- `tests/lr-reset-poller-inplace.bats:64,:131` session (`:131` carries `error:"rate_limit"`, `apiErrorStatus:429`, but **no `quotaLimits`**)
- `tests/lr-lib.bats:33` · `tests/lr-fleet.bats:51,208,267` · `tests/cc-classify.bats:145,386,794,1078`
- `tests/lr-team-audit.bats:68,194` · `tests/recover-inject.bats:149,159` · `tests/handoff-recycle-remote-resume.bats:351`

So the suite is green *and* four copies are 9.1% blind, because the suite never asks the question.

Relevant negative-control fixture that must survive any SSOT change:
`tests/lr-reset-poller.bats:441-474` (LR-o) — a HEALTHY session whose only limit text is the
`/limit-recover` **skill description** in its `skill_listing` attachment. This session's own
transcript is a live instance of that trap: it was one of three hits for
`grep -rl "reached your Fable limit" ~/.claude*/projects/*/*.jsonl`, purely because the brief quotes
the string.

---

## R7 — reproduction

```bash
# the matrix
python3 /tmp/p9matrix.py                     # source inlined in R2
# the corpus + recall
grep -rh 'isApiErrorMessage":true' ~/.claude*/projects/*/*.jsonl > /tmp/p9all.jsonl
# the real fable record
grep -h 'isApiErrorMessage":true' /tmp/p9all.jsonl | grep -i "fable limit" | head -1
# a structured record
grep -h '"quotaLimits"' /tmp/p9all.jsonl | head -1
```

---

## PROPOSAL — the SSOT, and why it is three tiers and not one regex

The premise ("one shared predicate replaces the copies") is **PARTIAL** because the 16 sites split
on two axes that a single regex cannot span:

**Axis A — input domain.** Copies 14/15/16 (`handoff-fire.sh:9236`, `cloud-ceiling-probe.sh:212`,
`cloud-create.sh:174`) classify **CLI stdout from `claude -p`**, where there is no `error` field, no
`isApiErrorMessage` envelope, and no `quotaLimits`. They can only ever be text, and they are
*correctly* wider than the transcript copies (a probe may see an SDK-shaped error string). Folding
them into a JSONL SSOT would be a category error. They get their own small tier.

**Axis B — direction of safety.** Copies 12/13 (`cc-classify:312`, `desk-invariant:156`) are
**vetoes**: a match means "do not reap / this pane is stunned". Their safe failure is a FALSE
POSITIVE. Copies 8/10 (poller pre-filter, `classify_limit_text`) are **actuators**: a match means
"park it and spawn a process at the reset". Their safe failure is a FALSE NEGATIVE. One shared
predicate tuned for either direction is wrong for the other — which is exactly why
`desk-invariant.sh:149-152` documents its divergence from `cc-classify` as deliberate.

So: **ONE membership+sub-kind SSOT over transcript JSONL**, with the veto sites consuming it plus
their own documented widening, and the CLI sites left alone.

### The SSOT, as one Python module with a thin bash shim

`scripts/limit-recover/lr_predicate.py` — pure, no I/O, importable; plus
`scripts/limit-recover/lr-predicate.sh` exposing `lr_classify_record` / `lr_classify_tail` for the
bash callers (the repo already uses this exact shim shape — `lf_kinds_of` at `lr-fleet.sh:144` is a
bash function wrapping an inline `/usr/bin/python3 -c`).

Three tiers, evaluated in order, each cheaper and more certain than the next:

```
T0  ENVELOPE (unchanged, mandatory)   type=="assistant" and isApiErrorMessage is true
    -> this is what makes LR-o hold; never relax it, never text-grep outside it.

T1  STRUCTURAL MEMBERSHIP              error == "rate_limit"        [209/209, 0 FP]
      sub-kind + reset from quotaLimits when present  [180/209]
        rateLimitType "five_hour" -> kind=session,  resets_at = quotaLimits.resetsAt (epoch)
        rateLimitType "seven_day" -> kind=weekly,   resets_at = quotaLimits.resetsAt (epoch)
      other structural errors map without text too:
        error=="authentication_failed"    -> kind=auth_cliff        (no reset; transplant)
        error=="server_error" & status==529 -> kind=server_529      (transient)
        error=="server_error" & no status   -> kind=network         (confirm with NET_RE)
        error=="oauth_org_not_allowed"      -> kind=org_blocked

T2  TEXT FALLBACK (only when T1 leaves kind unresolved — 29/209 today)
      re.search (NOT startswith) over the envelope-gated content text:
        r"You've (?:hit|reached) your (?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit"
          scope "monthly spend" -> kind=monthly_spend (NO reset -> class-B packet, never park)
          scope in {session,weekly,fast} -> that kind; reset via RESET_RE prose parse
          any other capitalised scope   -> kind=model_scoped, model=<scope>   <- Fable lands here
                                            BY CONSTRUCTION, and so does the next model name
```

T2's `[A-Z][a-z]+` scope group is the whole point: it is what makes the predicate survive the *next*
model-scoped cap without an edit. The current Fable miss is not "we forgot Fable", it is "the
pattern enumerated a closed set of scopes over an open-ended product surface". `lr-fleet.sh:108`
already widened by adding `Fable` as a literal — that fixes today and re-breaks on `Sonnet limit`.

`lr_classify_record(obj) -> {kind, membership, resets_at_utc, resets_source, model, text, raw_error}`
with `resets_source ∈ {quotaLimits, prose, none}` — so a consumer can see *why* it trusts a reset,
and a prose-parsed reset can be audited separately from an epoch one.

### Migration order (each step independently landable and red-provable)

1. **Land the module + fixtures only. No call sites change.** Ship `lr_predicate.py`, the shim, and
   `tests/lr-predicate.bats` with the red-proof fixtures below. Net-new file; no behaviour moves.
   *Gate: the new suite is green and every existing suite is untouched.*
2. **`lr-audit.py` adopts T0+T1+T2 inside `classify_limit_text`/`parse_reset`.** This is the
   authoritative producer; everything downstream reads its JSON. It is also the only site where
   `startswith` → `search` is a behaviour change, so it goes alone.
   *Gate: `tests/lr-reset-poller.bats` + `tests/lr-team-audit.bats` green unchanged (existing
   fixtures all still classify identically), plus the new fable fixture now yields `kind=model_scoped`.*
3. **Delete `lr-reset-poller.sh:746`'s inline pre-filter and `:771`'s allowlist.** Replace the
   pre-filter with `error=="rate_limit"` ∧ envelope (cheaper — a field equality, not a regex over a
   20 KB tail) and the allowlist with "kind has a reset". This retires the dead `'fable'` branch
   rather than fixing it, and closes `limit-reset-safety-gate.sh`'s LR-blind.
   *Gate: LR-o negative control still parks nothing; new fable fixture parks with a reset.*
4. **`lr-lib.sh:152` (`lr_last_api_error`) delegates its kind to the shim.** One-line change; fixes
   `hooks/recover-inject.sh` by inheritance, and closes the `:55` ↔ `:152` intra-file split.
   *Gate: `tests/net-recover-arm.bats`, `tests/recover-inject.bats`.*
5. **`lr-fleet.sh` copies 1/3/4 delegate.** Its LIMIT_RE is already 100%-recall, so this is a
   de-duplication with no behaviour delta — do it last, when the shim has three consumers proving it.
   *Gate: `tests/lr-fleet.bats` byte-identical `--locate` output on the existing fixtures.*
6. **Veto sites (`cc-classify:312`, `desk-invariant:156`): consume, then widen explicitly.**
   `recent_api_limit` becomes `membership != none` OR its existing regex (union, never replacement —
   a veto must not *lose* coverage). `cap_stunned` keeps its no-envelope raw grep and *adds* the
   union, with its `:149-152` comment updated to say the divergence is now additive.
   *Gate: `tests/cc-classify.bats` green; a new fable fixture must classify `rate-limited`, i.e.
   never reapable — this is the highest-consequence fix in the whole migration (see below).*
7. **Leave `handoff-fire.sh:9236`, `cloud-ceiling-probe.sh:212`, `cloud-create.sh:174` alone**, and
   add a one-line comment at each naming the SSOT and why it does not apply (different input domain).
   A lint that asserts "no new transcript-JSONL limit regex outside `lr_predicate.py`" belongs here.

Order rationale: producer → parked-actuator → hook → census → veto. Every step's blast radius is
strictly smaller than the step before it, and the veto sites (where a wrong answer reaps live work)
move only after the module has been proven by three other consumers.

### Red-proof fixtures, one per blind spot

Each must FAIL on today's code and PASS after its step. All are envelope-carrying
(`type:assistant`, `isApiErrorMessage:true`) unless stated.

| fixture | record | red today because | asserts |
|---|---|---|---|
| **F1 fable-park** | the verbatim R5 capture (`error:rate_limit`, `status:429`, no `quotaLimits`, text `You've reached your Fable limit. Run /usage-credits to continue or switch models with /model.`) | `classify_limit_text` → `other_api_error`; poller `:746` never matches | `kind=model_scoped`, `model=Fable`, membership=limit, poller parks it |
| **F2 fable-no-reap** | F1's record as the tail of an otherwise clean+landed session | `cc-classify:312` regex misses, so branch 2 (`:817`, the never-reap veto) does not fire and classification falls through to the idle/finished branches. **Not yet measured end-to-end** — but `:818-824`'s own comment records the identical fall-through hazard for safeguard refusals ("otherwise reads finished-teammate → gets auto-reaped as if it had done its work"). This fixture is what turns that into a measurement. | `cc-classify` answers `rate-limited`; `cc-reaper` never reaps |
| **F3 next-model** | F1 with `Fable` → `Sonnet` | even `lr-fleet.sh:108`'s widened LIMIT_RE enumerates `Fable` literally and misses | `kind=model_scoped`, `model=Sonnet` — proves the open-ended scope group |
| **F4 structural-reset** | the R4 record (`quotaLimits.rateLimitType=five_hour`, `resetsAt=1789025400`, **no prose `resets …` in the text**) | `RESET_RE` finds nothing → `parse_reset` returns `None` → poller `[[ -n "$reset" ]] \|\| continue` → **never parked** | `resets_at_utc` derived from the epoch, `resets_source=quotaLimits` |
| **F5 no-zoneinfo** | the `seven_day` structured record, run with `ZoneInfo` forced to `None` | `parse_reset:211` returns `None` unconditionally | reset still resolves (T1 needs no tz database) |
| **F6 spend-packet** | `You've hit your monthly spend limit …`, no reset | (passes today — regression guard) | `kind=monthly_spend`, `resets_at_utc=None`, class-B packet, **never parked** |
| **F7 529-not-limit** | `error:server_error`, `status:529`, text `API Error: Server is temporarily limiting requests` | (passes today — regression guard) | membership≠limit; not parked; `desk-invariant` may still stun-flag it |
| **F8 network-not-limit** | `error:server_error`, text `Can't reach the API server (ENOTFOUND)` | (passes today — regression guard) | `kind=network`; `--recover` still refuses to transplant it |
| **F9 LR-o skill-listing** | a HEALTHY session, **no envelope**, whose `skill_listing` attachment quotes both `You've hit your session/weekly limit` and `You've reached your Fable limit` | today's poller is saved only by the `hit your` spelling; a naive T2 widening without T0 would open a false packet | zero packets, zero parks — **this fixture is what makes the widening safe** |
| **F10 auth-cliff** | `error:authentication_failed`, text `Not logged in · Please run /login` | membership is currently text-only and misses it entirely | `kind=auth_cliff`, no reset, transplant path (no reset to wait for) |

F9 is non-negotiable and must be the first assertion in the suite: every widening step above is only
legal because T0 is mandatory, and F9 is the only test that can catch a T0 regression. It has a live
counterpart — three transcripts on this box match `reached your Fable limit` in prose, one of them
this very research session.

### Latency note (secondary, but it falls out of the same change)

`lr-fleet.sh:193` runs `lf_kinds_of` + `lf_err_age_s` as **two separate `/usr/bin/python3` forks per
hit**, after a `tail -c 20000` + two `grep`s per transcript. T1 replaces the per-hit text scan with a
field equality and lets one process classify the whole fleet, which is the difference the lead
already measured between `lr-fleet --locate` (35.5 s) and the single-process prototype (0.07 s).
The SSOT being a *module* rather than a *regex string* is what makes that consolidation possible.
