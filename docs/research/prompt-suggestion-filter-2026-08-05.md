# Quantifying Claude Code's prompt-suggestion content filter

**Date:** 2026-08-05 · **Subject:** Claude Code 2.1.220 · **Backlog:** `ec6b36c18d05`
**Predecessor:** session `05ed2d55` (recap/auto-suggest gate investigation), memory
[[gate-default-decides-failure-direction]], [[init-state-is-not-runtime-state]]

The predecessor established that both grey-text features are gate-ON fleet-wide and that
`cache_cold` blocks only ~10% of turns, then stopped at one open question: *is the 12-rule content
filter the dominant reason auto-suggest stays rare?* It named the only readout — the `reason`
attribute of the `tengu_prompt_suggestion` telemetry event — and recorded that we do not collect it.

**Answer, in one line: the filter is effectively a ONE-rule filter, and that rule rejects about two
thirds of everything a perfect suggester could produce.** `too_many_words` (>12 words) accounts for
87–95% of all content rejections; the other eleven rules together account for the remainder.

---

## 1. What the item asked for, and what turned out to be true

| Premise (as filed) | Verdict |
|---|---|
| The `reason` field is the only readout | **True** — and it is emitted for every suppression, unsampled |
| "we do not collect it" | **True at the time; no longer** — it is recoverable from a store that already exists on disk |
| Collecting it needs the documented telemetry pipeline | **False** — that pipeline structurally cannot carry it (§2) |

Two things were built:

- `bin/cc-suggest-filter` — runs the ladder locally over a real corpus. Needs nothing installed,
  no model calls, no config change. This produced the headline number (§3).
- `bin/cc-1p-events` — reads the actual `reason` field out of Claude Code's own first-party event
  spool, and provides the local sink for collecting it at volume (§4).

---

## 2. Why the documented telemetry pipeline can never carry it

`tengu_*` events go through `M(name, meta)` → a single install-once analytics sink (`SEi`/`fMt`) →
`cv_` → `Per` → `nJi(ERe, …)` → `ERe.emit(…)`. `ERe` is an OTel logger built in `ino()` over a
**privately constructed** LoggerProvider whose exporter (`eJi`) posts to Anthropic.

The operator-configurable pipeline (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is a **different**
LoggerProvider. Its records are all minted by one template literal — `` body:`claude_code.${e}` ``
— giving 27 curated event bodies (`claude_code.user_prompt`, `.tool_result`, `.api_request`, …).
`cv_` contains no call into it, and `nJi` is only ever invoked as `nJi(ERe, …)`.

**Measured, not inferred.** A live 2.1.220 run with `OTEL_LOGS_EXPORTER=console
OTEL_METRICS_EXPORTER=console` produced 5,979 lines of exporter output containing **zero** `tengu_*`
events — only the `claude_code.*` set. Anyone tempted to re-attempt collection through
`CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_EXPORTER_OTLP_ENDPOINT`, or `BETA_TRACING_ENDPOINT` should
stop here: all three serve the curated set.

Dead ends checked and closed, so they are not re-walked:

- `CLAUDE_INTERNAL_FC_OVERRIDES` — `fGr()` returns before ever reading it; dead code in this build.
- `Yer()` / `setGrowthBookConfigOverride` (`pIg`) — both are `function(){return}` with zero call
  sites, so **both "override" branches of the gate reader are unreachable in 2.1.220**.
- `HTTPS_PROXY` — honoured by the exporter's axios client, but the analytics endpoint defaults to
  `https://api.anthropic.com/api/event_logging/v2/batch`, i.e. **the same host as the API**, and
  `NO_PROXY` matches host[:port] only. There is no path-granular split, so proxying telemetry means
  proxying the API.

## 3. The measurement that needed nothing installed

The ladder (`TM_`) is a pure function of the suggestion string, so it can be run here. The
population used is **what users actually typed next**, harvested from fleet transcripts: a perfect
predictor's output *is* that string, so the rejection rate over that corpus is what the filter
throws away even when the generator is perfect.

`bin/cc-suggest-filter` is a rule-for-rule port, and it is **not trusted on its own** — the node
oracle in `tests/` executes the real `TM_` extracted from the installed binary and the suite asserts
verdict-for-verdict equality over ~1,500 real prompts. That control immediately earned its keep: it
caught a `re.S` in the `meta_wrapped` rule that made Python's `.` match a newline where JS's never
does. The fixtures could not have caught it; exactly one row in 4,968 exposed it.

**Result** (deduped corpus, n=3,206; and a hand-labelled random sample of 100 to calibrate):

| population | shown | suppressed | top reason |
|---|---|---|---|
| all typed prompts, raw (n=3,936) | 19% | **81%** | `too_many_words` 89% of rejects |
| all typed prompts, deduped (n=3,206) | 13% | **87%** | `too_many_words` 95% of rejects |
| **hand-labelled human-typed only (n=70)** | **33%** | **67%** | `too_many_words` **87%** of rejects |
| hand-labelled machine-submitted (n=30) | 0% | 100% | `too_many_words` 93% of rejects |

The honest figure is the third row: **67%**. The corpus is ~30% machine-submitted turns (desk pages,
dispatch briefs, handoff pastes, gate probes) which no structural field distinguishes from typing —
`entrypoint` is `"cli"` for both across 47,502 user records — and those are 100% rejected, which
inflates the raw number. The hand-labelled indices are recorded in the commit so the call is
auditable, and `corpus --dedupe` exists as the automation sensitivity check.

Every other rule is noise by comparison: `prefixed_label`, `multiple_sentences`, `meta_wrapped`,
`done` together account for ~13% of rejections; `has_formatting`, `evaluative`, `claude_voice`,
`too_long`, `too_few_words`, `meta_text`, `error_message` are ≲1% each.

### What this number is, and what it is not

It **is** a ceiling on exact prediction: a suggestion can only ever equal what the user types when
that input is ≤12 words and <100 chars, which is one input in three. The feature is structurally
confined to short-input turns, and no improvement to the generator changes that.

It is **not** the live suppression rate. The generator is explicitly instructed to emit "2-12 words"
and to stay silent when the next step is not obvious, so its real output distribution is shifted
toward compliance — the live `reason` mix likely carries far more `empty`/`done`/`meta_text` (the
model declining) and less `too_many_words` than this table. Establishing that mix requires §4.

## 4. The `reason` field, for real

Claude Code's exporter is a durable queue. When a batch fails to POST it spills to

```
<CLAUDE_CONFIG_DIR>/telemetry/1p_failed_events.<session>.<uuid>.json
```

as JSONL, with `reason` **in the clear** — `Te`/`fe` are identity brand-markers erased at compile
time, and the bundle's real redactor (`GIt`) is never applied to it. `reason` rides in
`event_data.additional_metadata`, base64 of a JSON bag. `bin/cc-1p-events spool|suggest` decodes it.

`tengu_prompt_suggestion` is **not sampled** — `tengu_event_sampling_config` is `{}` on disk and
`nno()` returns `null` (log unconditionally) on a lookup miss — so every suppression event is
emitted. Its second argument, the rejected suggestion text, is accepted by `HY` and **silently
discarded**; not even Anthropic receives it.

**Yield today is 2 events.** Across all six config roots: 56 distinct spool files, 2,841 events,
2 of them `tengu_prompt_suggestion` (both `suppressed` / `cache_cold`, versions 2.1.207 and
2.1.215). That is enough to prove the field is recoverable and to validate the decoder against real
bytes; it is *not* enough to quantify anything, and `suggest` prints its `n` first for that reason.
The store is sparse by construction — a batch only lands there when an export fails.

### Collecting at volume — operator step

`eJi`'s constructor takes `baseUrl` verbatim with no validation, and `skipAuth` drops the bearer
token, so the exporter will post to a plain local server. `cc-1p-events serve` is that server;
`cc-1p-events activation` prints the one config line and its rollback. It is deliberately **not**
self-installing: while applied, first-party telemetry from that config root goes to this machine
instead of Anthropic. It is self-expiring — a successful GrowthBook refresh replaces
`cachedGrowthBookFeatures` wholesale (TTL 6h) — so the failure mode is "collection stops", never
"config stuck". Sessions must restart to pick it up; the exporter is constructed once at startup.

The sink is verified end-to-end in `tests/suggest-filter.bats` by replaying genuine spool records as
the POST body, and both stores are read by the same decoder so there is nothing to drift.

## 5. Limits

- The 67% figure rests on a hand-labelled 100-row sample. It is one labeller's call on an
  unfalsifiable question ("did a human press enter"), reproducible via the recorded seed and index
  list, not a measurement with an error bar.
- The corpus is one operator's fleet, which is unusually agent-heavy. The *shape* of the finding
  (one rule dominates) is robust across every cut; the exact percentage is not portable.
- `too_many_words` counts whitespace-separated tokens, so it is a proxy for length, not for
  linguistic complexity.
- Everything here is pinned to 2.1.220. `tests/fixtures/suggest-ladder-2.1.220.js` is the ladder as
  shipped, and the suite goes RED if the installed binary's copy diverges — re-read `TM_` and fix
  the port before re-pinning.
