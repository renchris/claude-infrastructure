# C — Alternative sources for weekly-limit utilization over time (esp. pre-2026-08-10)

date: 2026-08-25 · READ-ONLY · no config modified, no telemetry enabled, no new authenticated call made

---

## Headline

**The retrospective series is recoverable, but not from any store that holds a limit percentage —
it has to be RECONSTRUCTED from transcript token records via the already-fitted exchange rate, and
that reconstruction now validates out-of-sample at R² = 0.700 / RMSE 1.54 pp on 272 held-out
intervals.** No vendor surface, no OTel metric, no sibling log, and no third-party tool carries
weekly-limit % for any moment before 2026-08-10T05:58Z. What *does* exist is 715,076 assistant
usage records spanning **2026-07-11 → 2026-08-25** across all four accounts (382,477 of them
pre-08-10, carrying 389.7M output tokens), and `exchange-rate.md` already priced the meter
(1 weekly pp ≈ 780K Opus-5 output tokens). Multiplying the first by the second reproduces the
ledger it was never fitted on. A second, weaker source — 44 live `claude-accounts --json` readings
captured inside tool_results between 2026-07-25 and 2026-08-09 — gives sparse *direct* anchor
points to calibrate the reconstruction against.

## Verdict table

| # | Source | Verdict | The evidence that settles it |
|---|---|---|---|
| 1 | `api/oauth/usage` — **dropped fields** | **EXISTS + INSUFFICIENT** | Point-in-time only; no history field anywhere in the payload. ~40 fields returned, 5 read. |
| 1b | `api/oauth/usage` — **as a retrospective source** | **ABSENT** | Nothing in the schema is a series. |
| 2 | Native OTel | **ABSENT (both ways)** | Off in 5/5 config dirs, and the binary contains **zero** quota-shaped metric names. Cannot be enabled retroactively. |
| 3a | Transcripts — **limit/rate-limit messages** | **ABSENT** | 0 real usage-limit events in 6,734 transcripts. All 11 canonical-string hits are meta. |
| 3b | Transcripts — **captured `--json` readings** | **EXISTS + USABLE (sparse)** | 44 clean pre-08-10 readings, 2026-07-25 → 08-09, all 4 accounts; median error **0 pp** vs ledger on overlap. |
| 3c | Transcripts — **token records + exchange rate** | **EXISTS + USABLE — the answer** | 715,076 usage records back to 2026-07-11; out-of-sample R² 0.700, RMSE 1.54 pp, bias +10.5%. |
| 4 | `ccusage` / `claude-monitor` | **ABSENT** | Not installed; and both are strictly weaker instruments. |
| 5 | Cloud sessions (#175) | **EXISTS + INSUFFICIENT** | Repo's own 08-19 research: cloud consumes the *same* meter. Not separately attributable. |
| 6 | Sibling log stores | **ABSENT** | 11 candidate stores audited; `weekly_pct` count = 0 in every one but the ledger. |
| 7 | `/insights` | **EXISTS + INSUFFICIENT (untried)** | Shipped in the live binary, never run; local-history-derived so retro-capable, but approximate and it spends quota. |
| 8 | claude.ai web Usage panel | **UNVERIFIED** | Not probed — brief forbade authenticating. The one place server-side history could exist. |

---

## 1 · The vendor surface — every field returned vs every field kept

**Do not re-capture this.** A verbatim HTTP-200 body for account `next` is already committed at
`docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md:66-98` (captured 2026-08-16 ~10:30Z;
all four accounts returned structurally identical payloads). I read the parsing code against that
capture rather than issuing a call.

**How we call it.** `bin/claude-accounts:680-714` `fetch_usage()` — GET `usage_endpoint`
(`accounts.json` → `https://api.anthropic.com/api/oauth/usage`), headers `Authorization: Bearer
<keychain accessToken>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-cli/2.1.183`,
12 s timeout, 2 retries with half-to-full jittered backoff on 429.

**What we read — 5 fields, via one 7-line function.** `pick()` at `:846-853` walks `limits[]`
only, matching `kind` ∈ {`session`, `weekly_all`, `weekly_scoped`} (Fable filtered on
`scope.model.display_name`), taking `percent` + `resets_at`. `:1223-1233` reads
`extra_usage.is_enabled` and `extra_usage.used_credits`. That is the entire read surface.

**What we persist.** `record_utilization()` at `:2478-2540` writes 14 fields per account per sweep:
`ts, acct, k, k_work, k_src, session_pct, weekly_pct, fable_pct, session_reset_at,
weekly_reset_at, credits_on, credits_used, auth` (+ an error flag).

**What is DROPPED — no consumer on this box reads any of it:**

| Dropped | Why it matters |
|---|---|
| `five_hour.*` / `seven_day.*` **top-level bucket map** | The parallel view of the same numbers. Carries `utilization` as a **float**; we take `limits[].percent` as an **int**. |
| `limit_dollars` / `used_dollars` / `remaining_dollars` | The fields that **name the unit**. `null` on Max today. If Anthropic ever populates them the absolute size of a weekly allowance becomes readable, and nothing here would notice. |
| **`seven_day_opus` / `seven_day_sonnet`** | **Per-model sub-caps.** `null` today, but the live 2.1.220 binary carries both strings (8 and 10 occurrences) — the client knows about them. If a sub-cap is ever switched on it lands in a field we never look at, and the first symptom is an unexplained refusal. |
| 8 codenamed buckets — `seven_day_oauth_apps`, `seven_day_cowork`, `seven_day_omelette`, `tangelo`, `iguana_necktie`, `omelette_promotional`, `cinder_cove`, `amber_ladder` | All `null`. Unshipped or other-surface meters. |
| **`nimbus_quill`** | **Not null** — `{utilization: 0.0, resets_at: null, …}`. A live bucket, currently at zero, rendered nowhere. |
| `limits[].severity`, `.is_active`, `.group` | `severity` is the vendor's own escalation verdict; we re-derive urgency from `percent` + `resets_at` instead of reading what the server already decided. |
| `spend.*` (`used.amount_minor`, `currency`, `exponent`, `cap`, `balance`, `auto_reload`, `can_purchase_credits`, `can_toggle`, `disclaimer`) | `exponent: 2` is the **authoritative** statement that the credits unit is cents — the fact `accounts.json` `_spend` had to learn the hard way from a $176.91 mis-render. `can_toggle:false` is the machine-readable form of "overage is org-disabled". |
| `extra_usage`: `monthly_limit`, `utilization`, `currency`, `decimal_places`, `disabled_reason`, `user_disabled`, `spend_limit_reached`, `credits_ever_enabled`, `daily`, `weekly` | `spend_limit_reached` and `disabled_reason` are exactly the breach signals `accounts.json` `_spend` says must be surfaced. |
| `member_dashboard_available` | — |

**The finding that matters for THIS brief: there is no history field.** Not a series, not a
sparkline, not a previous-window value. Every bucket is a single current `utilization` + `resets_at`.
**The vendor surface cannot answer retrospectively, and un-dropping every field above would not
change that.**

**New, not in prior work — the binary and our tool read DISJOINT halves of the payload.**
String-scan of the live 2.1.220 Mach-O (`~/.claude-220/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`,
negative control `ZZZ_NEG_CTL_NOT_PRESENT` = 0):

```
utilization 32 · seven_day 23 · five_hour 18 · seven_day_sonnet 10 · resets_at 8
seven_day_opus 8 · api/oauth/usage 2 · weekly_scoped 2
weekly_all 0 · limit_dollars 0 · remaining_dollars 0 · nimbus_quill 0
```

The binary reads the **top-level bucket map**; `claude-accounts` reads the **`limits[]` array**
(`weekly_all` appears 0 times in the binary). The server sends a superset of both. Consequence: the
two disagree about which fields exist, so a schema change on either side is invisible to the other —
and `pick()` fails **silently to `(None, None)`**, which `_excluded()` then treats as a correctly
excluded row. A renamed `kind` reads as a quiet outage, not an error.

## 2 · Native OTel — absent, and absent in the direction that matters

**Not enabled anywhere.** `ENABLE_TELEMETRY|OTEL_` = 0 in all five `settings.json`
(`~/.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`), 0 in `~/.claude.json`, 0 in the
process env, 0 in `~/.zshrc`. **Positive control** on the same files: `"hooks"` = 41–42 each. The
zero is real, not an instrument failure. (Config dirs enumerated from `accounts.json` itself:
next→`~/.claude-next`, next2→`-secondary`, next3→`-tertiary`, next4→`-quaternary`. Note
`~/.claude-next/projects` is a **symlink** to `~/.claude/projects`, so `next`'s transcripts live
under `~/.claude` — a `find` that does not follow symlinks reads `.claude-next` as empty.)

**The pipeline is real in the shipped binary** — `claude_code.token.usage`, `.cost.usage`,
`.session.count`, `.active_time.total`, `.code_edit_tool.decision` all present (2 occurrences each);
`CLAUDE_CODE_ENABLE_TELEMETRY` 10, `OTEL_METRICS_EXPORTER` 9, `OTEL_LOGS_EXPORTER` 10.

**But it carries no denominator.** `claude_code.limit` = 0, `claude_code.quota` = 0,
`claude_code.rate_limit` = 0, `weekly_limit` = 0 in the binary. This is stronger than the prior
finding, which established the absence from the *vendor docs*; here it is established from the
*executable*. **Token counts are not limit %** — OTel counts what you spent, never what you are
allowed, and the conversion between them is exactly the exchange rate, which OTel does not carry.

**And it is structurally useless for this brief anyway:** telemetry is emitted at run time. Enabling
it today produces nothing about July. Worth enabling for the *forward* numerator (it is token-free by
construction) but it is not an answer to "what happened before 08-10".

## 3 · Transcripts — the only pre-08-10 source, in three distinct layers

Corpus: **6,749 `.jsonl` files** / 9.6 GB across the four account roots. Positive control
`cache_read_input_tokens` = 6,497 (96%); negative control `ZZZ_NOT_PRESENT_XYZ` = 1 (this session's
own transcript — the self-contamination hazard, quantified rather than assumed).

### 3a · Limit / rate-limit messages — ABSENT

| Anchor | Files | Real events |
|---|---|---|
| `usage limit reached\|<epoch>` (canonical machine string) | 6 files / 11 records | **0** |
| `rate_limit_error` | 16 files / 37 records | **0** |
| `anthropic-ratelimit-*` | 20 | 0 |
| `retry-after` | 41 | 0 |
| `rate_limits` field | 22 | 0 |

Every hit is meta. The 11 canonical-string records classify as: 9 agents grepping for the string or
quoting the prior research's own finding (6 of them dated 2026-08-16, the research wave that searched
for it), and 2 that are an alternation pipe inside a **hook's regex**
(`…credit balance too low|usage limit reached|mcp server auth…`) — a `|` that is regex syntax, not
the epoch separator. The `rate_limit_error` hits are the CC binary's own error enum being dumped by
agents reading its strings, plus research quotes.

⚠️ **This corrects the prior work's positive control.** The 2026-08-16 wave asserted "0 canonical
hits, **positive control**: 25 `rate_limit_error` records (next 4, next2 11, next3 9, next4 1)". The
0 replicates and is right. The control does not: those `rate_limit_error` records are meta too, so
the scan's "it can find things" demonstration was itself an artifact. The claim survives; its warrant
does not. Use `cache_read_input_tokens` (6,497/6,749) as the control instead.

**Net: the fleet has never hit a usage wall in the recorded corpus.** Which is itself a finding — the
pre-08-10 weekly series has no censoring at 100% and no reset-by-exhaustion events to model.

### 3b · Captured `claude-accounts --json` readings — sparse but EXACT

Sessions that ran `claude-accounts --json` left the parsed rows in a `tool_result`, timestamped by
the transcript record. Extraction with a purity filter (require an `"acct":"nextN"` object carrying
`weekly_pct`; if the object carries its **own** `ts` it is an echoed ledger row and is stamped with
that instead of the record time):

- **156 deduped readings, 2026-07-25T00:57Z → 2026-08-24T07:30Z**
- **50 pre-08-10** (44 `live`, 6 `echo`), across **all four accounts**
  (next 19, next4 15, next3 11, next2 5)
- pre-08-10 days covered: 07-25, 07-26, 07-29, 07-30, 07-31, 08-01, 08-02, 08-05, 08-06, 08-08, 08-09

**Cross-validation on the 08-10→08-25 overlap** (±15 min match against the ledger):

| class | n | ≤2 pp | median err | p90 | max |
|---|---|---|---|---|---|
| `echo` (own-ts ledger rows) | 27 | **27/27** | 0 | 0 | 0 |
| `live` (record-ts) | 60 | 38/60 | **0** | 57 | 99 |

Median 0 pp proves the extraction is **exact when the hit is a real reading**. The `live` class runs
~63% pure; the residue is fixture/sample JSON quoted inside transcripts (e.g. `bin/cc-wave-plan`'s
own test rows — "Same accounts, same loads, NO pace fields"), stamped with the reading session's
clock. A stricter gate — require ≥3 sibling accounts in the same record **and** a
`login_expires_at`/`session_reset_at` field on the object — would lift purity; not applied here.

**Density: ~0.9 readings per account-day**, against the ledger's ~228. Good enough to *anchor* a
reconstruction; far too sparse to *be* one.

### 3c · Token records × exchange rate — the actual answer

Every assistant record carries `message.usage` with `output_tokens`,
`cache_creation_input_tokens`, `cache_read_input_tokens`, plus `message.model`.

- **715,076 usage records** over 6,736 files, **2026-07-11 → 2026-08-25**, 37 distinct days
- per account: next 172,943 · next2 182,820 · next3 177,587 · next4 181,726
- **pre-08-10: 21 days, 382,477 records, 389,661,998 output tokens**
- models: `claude-opus-5` 687,442 · `claude-fable-5` 14,354 · `claude-sonnet-5` 5,361 ·
  `claude-opus-4-8` 5,320 · `claude-haiku-4-5` 1,231

Pre-08-10 daily output-token volume (the reconstruction's input):

```
07-11    481 recs   1,149,252 out      08-01  22711  19,680,123
07-12     79           222,688         08-02  21121  19,217,498
07-19   1339         1,398,520         08-03  20892  21,314,017
07-20      2               898         08-04  14484  15,931,226
07-24   1549         2,192,104         08-05  17845  16,702,177
07-25   2422         2,910,483         08-06  14620  14,140,539
07-26  24276        25,352,228         08-07  61199  63,407,352
07-27  27352        27,236,392         08-08  29935  29,409,859
07-28   4413         4,284,580         08-09  22898  23,662,913
07-29  20951        22,214,107
07-30  41076        46,231,271
07-31  32832        33,003,771
```

Coverage is **contiguous from 2026-07-24**; before that it is islands (07-11/12, 07-19/20) with gaps
at 07-13→18 and 07-21→23 — usable-but-holed for the first fortnight of July, dense thereafter.

**THE VALIDATION.** Applying the weekly-fit coefficients from `exchange-rate.md` F6/F7/F8/F9
(pp per 1M tokens — Opus out 1.2823, cc 0.1054, cr 0.0; Fable out 1.6804, cc 0.2996, cr 0.0096) to
hourly token buckets, and testing on **2026-08-17 → 08-25 only — a window disjoint from the
08-10→08-16 interval the coefficients were fitted on** — over 272 within-cycle intervals ≥3 h:

```
actual Δpp:     mean 1.81   sd 2.81   total 491
predicted Δpp:  mean 1.99             total 543
ratio pred/actual = 1.105
R² out-of-sample = 0.700     RMSE = 1.54 pp

  next   n=68  actual 140pp  predicted 138.0  ratio 0.99
  next2  n=68  actual 112pp  predicted 136.6  ratio 1.22
  next3  n=68  actual 146pp  predicted 157.0  ratio 1.08
  next4  n=68  actual  93pp  predicted 111.0  ratio 1.19
```

**This is the load-bearing result.** The in-sample fit was R² 0.82; held out on a later, disjoint
window it retains R² 0.700 with 1.54 pp RMSE and a **+10.5% systematic over-prediction**. The
reconstruction is sound in shape and slightly hot in level — apply a ~0.90 scale factor, or better,
re-anchor per account (next is unbiased at 0.99; next2 and next4 run ~1.2). The bias direction is the
one the exchange-rate work predicted: unmodelled out-of-band usage inflates the pp side, and
cache-read is pinned at zero when it may carry a small positive weight.

**What this buys.** Weekly utilization for all four accounts at **hourly** resolution back to
**2026-07-24** solidly (2026-07-11 with holes) — roughly 17 account-days of history per account that
no store on this box contains, at ±1.5 pp. The 44 direct readings from §3b sit inside that window as
independent anchor points to re-fit the per-account scale against.

**The honest limits.** (i) Reconstruction gives Δpp within a cycle, not absolute level — you need a
reset boundary or one direct anchor per cycle to pin the origin, and §3b supplies those unevenly
(next2 has only 5 pre-08-10 readings). (ii) Coefficients were fitted on the 08-10→16 model mix; July
included more `claude-opus-4-8` (5,320 records) whose weight was never fitted and is here folded into
"opus". (iii) Any usage from claude.ai web/mobile on the same account is invisible to transcripts and
biases the reconstruction **low** in exactly the period we cannot check.

## 4 · Third-party tools — absent, and a downgrade if adopted

`command -v` → **ABSENT** for `ccusage`, `claude-monitor`, `ccm`, `claude-usage`, `cctop`, `ccflare`.
No global npm package, no vendored copy under `~/.claude` or the repo. The only in-repo references
are two docs discussing them (`usage-telemetry-100p-2026-08-16/vendor-ground-truth.md`,
`docs/plans/USAGE_TELEMETRY_100P.md`).

Neither reads a store we do not. `ccusage` parses the **same local transcripts** and converts to
*cost estimates* from cached pricing — it states it cannot track subscription quota.
`claude-monitor` **estimates** plan limits by P90 over a 192-hour history against hardcoded per-plan
token caps. Both are strictly weaker than what is already here: we read the real percentage from the
endpoint and, per §3c, hold a *measured* exchange rate rather than a guessed one. **Adopting either
would replace a measurement with an estimate.** The one idea worth stealing is `ccusage`'s transcript
walker — and §3c already does that job with a validated conversion.

## 5 · Cloud sessions (#175) — one paragraph

The repo's own later research already answers the billing half.
`docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md:338`: *"A cloud working unit
consumes the same 5-hour/weekly meter as a local one at the same rate"* — so the settled ceiling of
9.4 sustained working units is **unchanged by cloud**, and `:34` records that no per-account cloud
concurrency cap is evidenced anywhere, *"the binding limit is quota."* For this brief the consequence
is a **measurement** problem, not a billing one: cloud usage moves the same weekly meter but its
transcripts do not necessarily land in the local account roots, so any period with cloud activity has
token-side under-count while the pp side is complete — the reconstruction reads **low** exactly there.
That is one of two candidate explanations for the per-account bias spread in §3c (next 0.99 vs next2
1.22), and it is testable: cross-reference `~/.claude/logs/account-assignments.jsonl` (352 rows, but
it only starts **2026-08-11**, so it cannot help pre-08-10) or the `cc-offload` fire log. Not pursued
further per brief scope.

## 6 · Sibling stores audited — all ABSENT (the near-misses are instructive)

| Store | Range | `weekly_pct` | Verdict |
|---|---|---|---|
| `account-utilization.jsonl` | 2026-08-10T05:58 → live, 12,533 rows | 12,533 | the incumbent |
| `capacity-alarm.jsonl` | **2026-07-30** → live, 29,110 rows | **0** | memory/compressor telemetry, not quota — the tempting name is wrong |
| `auth-timeseries.jsonl` | 2026-08-24 → live | 0 | token expiry only (`refreshTokenExpiresAt`, `n_live`) |
| `accounts-keepwarm.out.log` | 2026-08-11 → live, 494 KB | 0 | **the near-miss**: the daemon that *drives* the sweep logs only `swept rows=4 age_s=0 took_ms=…` — it held the numbers every 180 s and printed the timing |
| `claude-accounts-lastgood.json` | current only | 4 | single-slot overwrite per account; carries `quota_as_of` but depth **1** |
| `/tmp/claude-accounts-cache.json` | 90 s TTL | 4 + `prev` | depth **2** (one `prev` block), ephemeral |
| `account-assignments.jsonl` | 2026-08-11 → live, 352 rows | 0 | routing decisions only, post-dates the ledger |
| `bash-commands.log` / `bash-execution.log` (+5 rotations to 2026-07-30) | 2026-07-30 → live, 14 MB each | commands only | logs the **command and exit code, never stdout** — a `claude-accounts` invocation is recorded, its output is not |
| `~/.claude/backups/` (802 entries) | — | — | code/config backups; no quota series |
| `~/.claude/history.jsonl` (11 MB) | — | — | prompt history |
| git history of `claude-infrastructure` | 913 doc commits pre-08-11 | — | `account-utilization.jsonl` is **untracked** (`git log --all --` → empty), so no older committed copies. Docs *quote* readings at dates (`git log -S"weekly_pct"` finds ~8 pre-08-11 commits) — same sparse-anecdote class as §3b, already superseded by it |
| iTerm2 session logs | — | — | not configured; no log directory exists |

## 7 · `/insights` — shipped, never run

The live 2.1.220 binary carries `/insights` (2), `usage-data` (4), `report.html` (2). No
`usage-data/` directory exists in any of the five config dirs, so it has **never been run** here.
Per the vendor costs page it writes a local HTML report over ≤200 unseen sessions and is available on
any plan — meaning it is **retrospective-capable**, since it derives from local session history, the
same substrate as §3c. Two reasons it is not the answer: its figures are explicitly *"approximate and
computed from local session history"*, and its analysis **runs through your own account, so its
tokens count against the very plan limit you are measuring**. It would be a cross-check on §3c, not a
replacement — and a self-perturbing one.

## 8 · What I did NOT check — the honest gap

**The claude.ai web Usage panel.** This is the one place where genuinely server-side history could
live, and the only source independent of the local transcript corpus (hence the only one that could
settle the out-of-band-usage bias in §3c). The box has the machinery to read it autonomously —
per-account `cc-authbrowser` CDP ports, the `autonomous-authenticated-web-access` and `dia-agent`
skills. I did not probe it: the brief said do not authenticate anything. Known from the committed
capture: the panel renders `extra_usage.used_credits` as dollars (17691 → $176.91), so it is at
minimum a different *view*; whether it exposes a *time series* is **unverified**. Single
highest-value follow-up, and cheap.

Also unchecked, deliberately: no fresh call to `api/oauth/usage` (the 08-16 committed capture plus
the parsing code answered §1, and a call risks the 429 poll-throttle `fetch_usage` documents at
`:699-707`), and therefore no re-verification that the 08-16 payload schema still holds nine days on.

---

## Recommendations

1. **Build the reconstruction, not another recorder.** §3c is validated out-of-sample. One script —
   walk transcripts → hourly (out, cc, cr) per account per model family → apply coefficients with a
   per-account scale re-fitted against the §3b anchors → emit rows in `account-utilization.jsonl`'s
   own schema with a `src:"reconstructed"` flag. Back-fills 2026-07-24 → 08-10 at ±1.5 pp, zero quota.
2. **Never merge reconstructed rows into the measured ledger unflagged.** They are ±1.5 pp with a
   known +10% bias; the ledger is exact. A `src` field keeps every later analysis able to exclude them.
3. **Un-drop four fields in `pick()`** — `limits[].severity` and `.is_active`, `seven_day_opus`,
   `seven_day_sonnet`. The first two are the vendor's own escalation verdict, which we currently
   re-derive; the last two are per-model sub-caps that are null today and would otherwise arrive as an
   unexplained refusal. Cost: reading fields already inside a response we already parse.
4. **Assert on the payload shape.** `pick()` fails silently to `(None, None)` and a renamed `kind` is
   indistinguishable from a logged-out account. Since the binary and our tool read disjoint halves of
   the payload, neither can detect the other's schema drift. One assertion — "`limits[]` contained
   `weekly_all`" — converts a silent outage into an event.
5. **Probe the web Usage panel** (§8) before concluding no server-side history exists.
6. **Fix the near-miss in `accounts-keepwarm`**: it renders the numbers every 180 s and logs only
   timings. Not a gap now that the ledger exists, but it is the same discard-the-measurement pattern
   `record_utilization`'s own docstring was written to end.

## What would falsify this

- **§3c**: re-run the out-of-sample test on a *third* disjoint window (e.g. 08-26→09-02). If R²
  collapses below ~0.4 the coefficients are period-specific and the July back-fill is not defensible.
  Equally: if per-account scale factors move materially between windows, re-anchoring per account is
  mandatory rather than optional.
- **§3b purity**: apply the stricter gate (≥3 sibling accounts in-record + `login_expires_at`
  present). If clean pre-08-10 readings fall well below 44, the anchor set is thinner than claimed.
- **§1**: if a fresh capture shows `seven_day_opus` or `limit_dollars` populated, the "no history,
  nothing to un-drop" conclusion narrows — those would be new *live* signal, though still not history.
- **§8**: if the web panel exposes a utilization chart with history, §3c stops being the only
  pre-08-10 source and becomes a cross-check on a better one.

---

## Reproduction

Scripts used (scratch, `/tmp/altsrc/`): `scan.py` (anchor census + controls), `extract2.py`
(purity-filtered `--json` reading extraction + per-class cross-validation), `usagecov.py` (token
record coverage), `recon.py` (hourly bucketing + out-of-sample reconstruction test), `meta.py`
(canonical-string meta/real classification), `rle.py` (`rate_limit_error` census).
