# A4 — A batch Jev pass over the plan corpus: is "this section names a thing that does not exist" a real deliverable?

Measured 2026-09-21 against `~/Development/claude-infrastructure` @ `5acaeea16`. Read-only; no Jev
call was made (the agent cannot make one — `CC_JEV_ZDR=0` is classifier-refused). Every number below
was produced end-to-end with the grep half only, which is the point: **the hybrid was proved without
spending a single call.**

---

## VERDICT (up front)

**NO as the four-day primary deliverable. YES as a ~60-call, 20-minute rider on a harness another
arm is already paying for.** Three findings drive it, and the first two invert the brief's own model.

1. **The brief has the two halves backwards.** It proposed *Jev narrows the population, grep is
   exact.* Measured, it is the reverse: the grep narrows **5,733 → 59 (97×)**, and Jev's only
   irreducible job is adjudicating that 59-row residue. This is not a quibble — it is the entire
   budget argument. Jev-first over every section costs **1,415 calls / 4–12 h** for this repo alone
   and **~13,000 calls / 36–108 h** machine-wide, which fails refutation (d) outright. Grep-first
   costs **59 calls / 10–30 min** here and **~540 / 1.5–4.5 h** machine-wide. Same output.

2. **Refutation (a) very nearly lands: the grep's precision is ~7%, and almost all of the repair is
   ALSO grep.** Of 59 grep-absent (section, identifier) pairs I adjudicated **all 59 by hand**:
   **4 are genuine rot.** Of the 55 false positives, ~20 are identifiers belonging to *other
   checkouts* (reso, doc_classifier, kitty upstream) and ~3 are *git branch names* — both killed by a
   caller-side resolution rule with zero model calls. That leaves ~24 needing a *reading*, of which
   ~14 are sections that **state the absence themselves** and ~10 are **design proposals**. Jev's
   real contribution is 24 → ~6 candidates. A human reads 24 rows in ten minutes.

3. **Refutation (c) fires at the corpus level and does NOT fire at the residue level — say which one
   you mean.** Genuinely-rotten *sections* are **2–3 of 1,059 = 0.2%**, near zero, because this
   corpus is unusually self-correcting (see § Why the base rate is so low). But the base rate *inside
   the grep residue* is **4/59 = 6.8%**, which is a perfectly workable operating point. The arm is
   not inert; it is **low-yield**: ~4 findings per repo.

**The test — "does it produce something whose ABSENCE WE WOULD NOTICE?"** Marginally yes for two of
the four hits (below), and those two are exactly the cost class
`spec-named-mechanism-may-be-prose-only` was written about. But four findings is not what four days
should buy, and ~85% of the four are reachable without Jev. **Ship the grep half. Hold the Jev half
until a harness exists for another arm, then add it for 59 calls.**

---

## 1. Corpus table

`docs/plans` in `claude-infrastructure`, recursive:

| | Value |
|---|---|
| plan files | **105** (`docs/plans/**/*.md`) — 90 at top level, 15 in subdirs |
| total bytes | **8,220,678** |
| file bytes | min 2,051 · p25 21,598 · **med 35,684** · p75 65,322 · p90 122,407 · max 2,940,578 |
| files with zero `## ` headings | 4 |
| `## ` (L2) sections | **958** |
| L2 section bytes | min 71 · p25 1,242 · **med 2,675** · p75 6,095 · p90 12,314 · p95 16,825 · p99 47,398 · max 2,813,368 |
| L2 sections > 12,000 B | 101 (of which 77 carry `### ` subsections) |
| L2 sections < 400 B | 41 |

Outlier worth naming: `BACKLOG_DRAIN_24_7.md` is **2.97 MB in 8 sections** — an append-only *log*
wearing a plan's file extension, and a single section of it is 2.81 MB. Any chunking rule that does
not carry a hard byte cap dies on this one file.

Machine-wide context (the brief's 963): `find-plan.sh --list-open` reports **61 open/in-progress
plans across 13 checkouts**, of which 9 are claude-infrastructure's; the rest sit in `reso-web-app`,
`doc_classifier`, `reso-management-app`, `lakehouse-lecture`, `sevenrooms-bridge` and 20+ worktrees.
Worktrees duplicate their parent's plans verbatim, so the true distinct population is materially
below 963 and any pass must dedupe on content hash or it pays 3× for `FLOOR_PLAN.md`.

---

## 2. The chunking rule (exact, with its byte cap)

```
UNIT = one L2 section.
  1. Split each file on /^## /m. A file with no L2 heading is ONE unit (its first 12,000 B).
  2. If a unit exceeds 12,000 B and contains /^### /m, re-split it on /^### /m;
     the text before the first ### stays as its own unit.
  3. Hard-truncate every unit at 12,000 B (head -c 12000). No exceptions.
  4. Drop units that are whitespace-only.
```

Measured outcome on this corpus: **1,415 units**, median 2,264 B, p95 11,030 B, max (pre-truncation)
2,813,368 B. After step 2, **48 units still exceed 12,000 B and 9 exceed 32,000 B** — step 3 is
therefore load-bearing, not belt-and-braces.

**Why 12,000 B and not the 32,000-token ceiling.** 12,000 B ≈ 3,000 tokens, ~9% of the state ceiling.
The ceiling is not the binding constraint; *reading quality over a truncated tail* is. Copy
`rank-memory.sh`'s `CC_JEV_RANK_CAP_B` idiom (3,000 B there) as `CC_JEV_PLAN_CAP_B`, default 12000,
so the cap is tunable without touching the splitter. A truncated unit must be **flagged in its JSONL
row** (`truncated:true`) — a verdict over a tail the model never saw is a verdict about the cap.

---

## 3. The identifier extractor (the grep half, stated exactly)

Only **backtick-delimited** spans are considered; a token is an identifier if it matches one of six
anchored shapes:

| kind | regex | count (distinct) |
|---|---|---|
| `path` | `^(?:scripts\|hooks\|bin\|tests\|commands\|skills\|migrations\|agents\|docs)/[\w./-]+$` | 936 |
| `file` | `^[\w.-]+\.(?:sh\|py\|mjs\|js\|ts\|json\|yaml\|yml\|bats)$` | 390 |
| `flag` | `^--[a-z][a-z0-9-]{2,}$` | 274 |
| `env` | `^(?:CC\|CLAUDE\|JEV)_[A-Z0-9_]{2,}$` | 220 |
| `func` | `^[a-z][\w]*_[\w]+\(\)$` (needle drops the `()`) | 133 |
| `cmd` | `^cc-[a-z0-9-]+$` | 98 |

**2,051 distinct identifiers · 5,733 (section, identifier) pairs · 1,059 of 1,415 units carry ≥1.**

**Presence test (and getting it wrong doubles your false-positive rate).**
`present = needle ∈ HAYSTACK  ∨  (kind=path ∧ os.path.exists)  ∨  (kind=file ∧ basename ∈ tracked)`
where HAYSTACK = every tracked non-binary file < 2 MB **except `docs/plans/**`** — 62.5 MB, 3,348
files, one `in` scan, **9.7 s for all 2,051**. Do not use `grep -rIF -f patterns`: BSD grep with 2,051
fixed patterns over this tree did not finish in 120 s and produced an empty file.

> **The haystack bug that cost me a doubled absent-count, recorded because it will recur.** My first
> pass excluded all of `docs/` (reasoning: the plans are in there, and a plan mentioning its own
> identifier would self-certify). That read **178 absent pairs**. Including `docs/` *minus*
> `docs/plans/` — and adding filesystem-existence for `path` and a tracked-basename index for
> `file` — read **59**. The 119-pair difference is almost entirely `docs/activation/pending-activation/*.sh`
> and `docs/lessons/*.md`, which are *real deployed artifacts that happen to live under docs/*.
> **Excluding a directory from the haystack is a claim that nothing executable lives there.** Verify
> it before making it.

### Result at corpus scale

| | pairs | absent | rate |
|---|---|---|---|
| all | 5,733 | **59** | **1.0%** |
| `file` | 1,181 | 15 | 1.3% |
| `path` | 2,410 | 20 | 0.8% |
| `env` | 342 | 10 | 2.9% |
| `flag` | 960 | 9 | 0.9% |
| `cmd` | 655 | 3 | 0.5% |
| `func` | 185 | 2 | 1.1% |
| **units with ≥1 absent** | 1,059 | **44** | **4.2%** |

**Recall gap, measured:** 302 identifier-shaped paths appear *outside* backticks corpus-wide
(vs 5,733 backticked pairs) — a ~5% blind spot. Accepted: un-backticked mentions are overwhelmingly
prose-flow references, and widening the extractor past backticks is what produces the
`scripts/X.sh` / `tsconfig.json` class of noise.

---

## 4. The 15 hand-labels, with the grep result for each

Labels are mine, on the brief's three candidate questions.
**(a)** claims DONE/LANDED/RUNNING (vs proposed)? · **(b)** names a checkable artifact? ·
**(c)** describes a rottable STATE (S) vs a DECISION with rationale (D)?

| # | plan · section | B | a | b | c | identifiers | grep-absent | genuine rot? |
|---|---|---|---|---|---|---|---|---|
| S1 | RELOGIN · `Verified facts (established 2026-07-25 — do NOT re-derive)` | 2,588 | **Y** | Y | **S** | 4 | 0 | — |
| S2 | RELOGIN · `bin/cc-relogin — CLI contract (FROZEN, pre-spawn)` | 5,987 | N (spec) | Y | D | 9 | 0 | — |
| S3 | RELOGIN · `2026-07-25 — BUILT (feat/cc-relogin)` | 1,922 | **Y** | Y | **S** | 5 | 0 | — |
| S4 | RELOGIN · `2026-07-26 — CONVERGED + LANDED` | 7,715 | **Y** | Y | **S** | 10 | 1 | **no** — `docs/relogin-research` is a *branch name* beside `relogin-design2`; extractor FP |
| S5 | GATE · `2. What is REFUTED — do not re-litigate` | 2,255 | N | Y | D | 2 | 0 | — |
| S6 | GATE · `3. Phase 1 — the per-suite runner (do this first)` | 5,653 | mixed | Y | **S** | 3 | 1 | **no** — `CC_GATE_ADMIT_TOTAL_WAIT`, and the section's own next line is a `> SUPERSEDED 2026-07-30 — NO LONGER EXISTS; do not port it` blockquote |
| S7 | GATE · `7. OPEN — the scoped tier's safety premise has never once been true` | 9,349 | N (open) | Y | **S** | 6 | 0 | — |
| S8 | GATE · `8. FIXED — the liveness ratchet false-positives on A && false` | 4,007 | **Y** | Y | **S** | 1 | 0 | — |
| S9 | GATE · `9. MEASURED — Phase 1 did not unblock landing` | 7,377 | **Y** | Y | **S** | 6 | 0 | — |
| S10 | USAGE_TELEMETRY · `§0 The admissibility rule` | 2,272 | N | **N** | **D** | 0 | — | — (pure decision; correctly un-checkable) |
| S11 | USAGE_TELEMETRY · `§1 Opening state (measured 2026-08-16)` | 2,988 | **Y** | **N** | **S** | 0 | — | **unreachable by this check** — a measured state claim naming no artifact |
| S12 | USAGE_TELEMETRY · `§3 Design` | 7,394 | N | Y | D | 1 | 0 | — |
| S13 | MASTER_SESSION_LIFECYCLE · `Definition of done` | 224 | N | **N** | D | 0 | — | — |
| S14 | MCP_CONFIG_SSOT · `The mechanism — native, already shipped` | 1,285 | **Y** | Y | **S** | 5 | 2 | **no** — `cli.js` and `.claude.json` are vendor/`$HOME` artifacts outside any checkout |
| S15 | MCP_CONFIG_SSOT · `Status log` | 7,056 | **Y** | Y | **S** | 14 | 3 | **no** — `scripts/ms365-mcp-wire.sh` is absent (added `3aa963042` 2026-08-15, deleted 2026-09-08) **but line 414 of the same section says "`scripts/ms365-mcp-wire.sh` is now `scripts/mcp-ssot-wire.sh`"** |

**Hand-label yield: 7 grep-absent identifiers across 15 sections, 0 genuine rot.**

Three of those fifteen are the whole story:

- **S6 and S15 are the corpus's signature failure mode.** In both, the identifier is genuinely gone
  from the tree, and **the section itself already says so**, 400–900 characters away, in a blockquote
  (S6) or a bullet (S15). A grep reports 1 and 7 hits respectively; a *reader* of either section is
  in no danger whatsoever. This is the single strongest argument for a model in the loop — and it is
  also why the model's question cannot be (a), (b) or (c).
- **S11 is the check's blind spot.** "§1 Opening state (measured 2026-08-16, before any change)"
  asserts a *state* — the most rottable thing in the corpus — and names **zero** checkable
  identifiers. `b=N` ⇒ the arm cannot reach it, by construction, no matter how good the model is.

---

## 5. All 59 grep-absent pairs, adjudicated by hand

| class | n | reachable without Jev? | example |
|---|---|---|---|
| **A · foreign checkout** (reso, doc_classifier, kitty, next, sevenrooms) | ~20 | **YES** — resolve against every known checkout | `useCWV.ts`, `eslint.config.mjs`, `selection_drag.py`, `scripts/setup/provision-venue.ts`, `--bs-cap` |
| **B · the section STATES the absence** | ~14 | **no** — needs reading | `CC_CE_DENOM` ("…and **does not exist**"), `commands/goal.md` ("There is no `commands/goal.md` in any dir"), `CC_PAYLOAD_SLASH_GATE` ("**is gone**"), `scripts/lr-fire-resume.sh` ("does not exist — the file is `scripts/limit-recover/lr-fire-resume.sh`"), `idl-inert-check.sh` ("**Name:** `idl-log.sh`, not `idl-inert-check.sh`") |
| **C · design proposal, correctly unbuilt** | ~10 | **partly** — heading heuristic | `CC_OPREADOUT_PERCLASS`, `CC_DISPATCH_ORACLE_TIMEOUT_S`, `--auto-revert`, `--dirty-mine`, `venue_policy()`, `migrations/NNNN-start-latency-activation.sh` (a literal `NNNN` placeholder) |
| **D · git branch name / ephemeral store / scratchpad rig** | ~8 | **YES** — `git rev-parse --verify` + a `/tmp` filter | `cc-154540-9309`, `cc-025105-23721`, `docs/l3l4-readout-evidence`, `2729a36a8240.json`, `feed2.sh`, `content-check.sh` |
| **E · unlanded-branch inventory** (the section's *subject* is what is absent) | ~3 | **partly** | `tests/handoff-fire-daemon-window.bats (backup/daemon-window)` |
| **F · GENUINE ROT** | **4** | — | below |

### The four genuine hits

1–3. **`CROSS_SESSION_COMMS_V2.md`, acceptance table.** Rows A4, A6 and A7 are each marked
**`PROVEN`** and cite `tests/mailbox-pull-adopt.bats`, `tests/cc-notify-verdict.bats`,
`tests/mailbox-close-disposition.bats` as the evidence. **None of the three exists in `tests/`**
(nearest live siblings: `mailbox-drain.bats`, `mailbox-forward.bats`, `cc-notify.bats`,
`notify-back.bats`). A future session auditing that plan's acceptance would find three cited proofs
missing and have to re-derive whether the behaviour is guarded at all. *This is the highest-value
finding in the pass, and all three sit in ONE section.*

4. **`MASTER_FIRE_GATE.md:201`** — *"the admission-time repair inside `ready_state()` (`:1519`)"*.
`grep -c ready_state bin/cc-dispatch` → **0**. The function is **`readiness_verdict()`**, opening at
`bin/cc-dispatch:1514`. A precise, confident, wrong `file:function:line` citation — the exact shape
of `spec-named-mechanism-may-be-prose-only`, and the reason a reader's grep returns nothing and they
conclude the mechanism was never built.

*(Marginal fifth: `cc-register` in `HANDOFF_FAILURE_DETECTION_V2.md:105`, listed among existing
"durable pull-based operator rails", with zero non-plan occurrences anywhere. Probably never built;
I did not promote it because the sentence is a parenthetical gloss, not an existence claim.)*

**Grep-alone precision: 4/59 = 6.8%. Genuinely-rotten sections: 2–3 of 1,059 = 0.2%.**

---

## 6. Why the base rate is so low — and it is a finding, not a null

The resident rule set makes plan docs **INTEGRATE-never-overwrite**. The measured consequence is that
this corpus is **append-only *with corrections appended in place***. Sections do not go stale
silently; they accrete a `SUPERSEDED 2026-07-30 —` blockquote, a `WITHDRAWN — §7.2` strikethrough, a
`**RE-MEASURED 2026-08-20**` bold line, or a `is now \`X\`` sentence, **inside the same section**.

Class B (14 of 59) is that convention working exactly as designed. The corpus's real hazard is
therefore *not* "names a thing that does not exist" — the convention already largely handles it — but
**a section that contradicts a later section of the same plan**, where both are true-as-of-their-date
and a reader lands on the wrong one. That is a genuine Jev-shaped question (pairwise, expensive, and
outside this brief's scope) and is the better arm if this corpus is to be read at all.

**Secondary hazard this check cannot see, named for honesty:** an identifier that *exists* but is not
*wired* — a hook file present in `hooks/` and absent from `settings.json`, an activation script with
no `.done`, a migration staged and never run. The grep says PRESENT and the section's "running"
claim is still false. This is `a-gate-s-surface-is-not-its-traffic` /
`registration-precondition-must-assert-version-not-executability`, it is almost certainly larger than
the 4 hits above, and it is **also not a model job** — it is a second caller-side grep against the
registration surfaces.

---

## 7. The caller-side rule (grep-first, Jev-last)

```
STAGE 1 — extract        1,415 units → 5,733 (section, identifier) pairs.        [0 calls, ~15 s]
STAGE 2 — resolve        present in HAYSTACK ∪ fs ∪ basename-index?              [0 calls, ~10 s]
                         → 59 absent pairs.
STAGE 3 — cheap kills    (all deterministic, no model)                           [0 calls, ~30 s]
   3a  resolve against every checkout in ~/Development and ~/Development/.worktrees  → kills class A
   3b  `git rev-parse --verify <tok>` and `git branch -a --list` on every remote     → kills class D-branch
   3c  drop tokens matching /^\/tmp|scratchpad|^[0-9a-f]{12}\.json$|NNNN|^X\./        → kills class D-rest
                         → ~24 pairs survive.
STAGE 4 — Jev            ONE call per surviving pair. state = the unit (≤12,000 B)
                         + a trailer naming the identifier verbatim.             [~24 calls, 5-10 min]
STAGE 5 — caller rule    REPORT the pair iff  exists=true  AND  disclosed=false.
                         → expect ~6 rows, of which ~4 are genuine.
```

Report format is `rank-memory.sh`'s: one JSONL row per pair
(`{plan, section, identifier, kind, exists, disclosed, verdict}`), a summary table, **nothing
mutated**. Eviction — here, *correcting a plan* — stays a human read of the list, for the same reason
`rank-memory.sh` refuses to edit `MEMORY.md`: a wrong correction to a plan is invisible until the day
the missing sentence would have fired.

### The literal Jev spec

```json
{
  "state": "<the section text, head -c 12000>\n\n---\nIDENTIFIER IN QUESTION: `<tok>`",
  "questions": {
    "exists": {
      "type": "boolean",
      "instructions": "This is one section of an engineering plan document. Considering ONLY the text above, does it claim that the IDENTIFIER IN QUESTION currently exists as a working part of THIS repository's codebase?",
      "criteria": {
        "true": "the text asserts the named thing is built, landed, shipped, running, tested, wired or in use right now",
        "false": "the text proposes it as future work, marks it (new)/planned/design, attributes it to a DIFFERENT repository or an external tool, names it only as a branch, a temporary scratch file or an example placeholder, or merely quotes it while discussing something else"
      }
    },
    "disclosed": {
      "type": "boolean",
      "instructions": "Considering ONLY the text above, does it anywhere state that the IDENTIFIER IN QUESTION was removed, renamed, replaced, superseded, withdrawn, never built, or is absent from the codebase?",
      "criteria": {
        "true": "the text itself corrects or retracts the identifier - for example 'SUPERSEDED', 'WITHDRAWN', 'no longer exists', 'is now <other name>', 'does not exist', 'appears 0 times', 'not built here'",
        "false": "the text contains no such correction or retraction anywhere"
      }
    }
  }
}
```

Two booleans, one call, no `score`, no strings, no lists. `exists` is question (a) rewritten to be
**per-identifier rather than per-section** — the brief's (a) is a property of the section, but S6,
S14 and S15 each mix a DONE claim with a proposal and a foreign reference in one section, so a
section-level answer cannot route any of them. Question (b) is redundant: the extractor already *is*
the (b) test, mechanically and for free. Question (c) is interesting and **not decision-relevant
here** — every rottable-state section that names no artifact (S11) is unreachable by this arm anyway,
so (c) buys nothing the pipeline can act on.

`disclosed` is the question this repo actually needs, and **it is the one the brief did not ask for.**
It is what separates S6 and S15 (harmless) from CROSS_SESSION_COMMS_V2 (real), and no grep does it —
the disclosure is prose, sits up to ~900 B from the identifier, and is spelled at least six
different ways in the 14 class-B pairs.

---

## 8. Call budget and wall clock

At the free tier's ~6 calls/min with `rank-memory.sh`'s 3 s gap and exponential backoff, its own
estimator brackets a run at **N/6 to N/2 minutes**.

| arm | population | calls | wall clock | fits 4 days? |
|---|---|---|---|---|
| Jev-first, all sections, **this repo** | 1,415 units | **1,415** | 4–12 h | yes, but spends the whole window |
| Jev-first, all sections, **machine-wide** | ~13,000 units (963 plans × 13.5) | **~13,000** | **36–108 h** | **NO** — refutation (d) |
| **Hybrid, this repo** | 59 absent pairs | **59** (24 after stage 3) | **10–30 min** | **trivially** |
| **Hybrid, machine-wide** | ~540 absent pairs | **~540** (~220 after stage 3) | **1.5–4.5 h** | **trivially** |
| Hybrid, the 61 open plans only | ~35 absent pairs | **~35** | ~6–18 min | trivially |

The 24× budget gap between Jev-first and hybrid is the decisive number in this document. **The full
corpus is affordable only in the hybrid order.** Note also that the machine-wide figure must dedupe
on content hash first: `find-plan.sh --list-open` shows `FLOOR_PLAN.md` in three worktrees,
`ONE_CLICK_UX_README_PLAN.md` in three, `HUMAN_SEO_VISUAL_REBUILD.md` in three — a naive pass pays
3× for identical bytes.

**The defensible four-day subset, if this arm is run at all:** the **61 open/in-progress plans**
named by `find-plan.sh --list-open`, deduped by content hash, cross-repo resolution ON. ~35 calls,
under twenty minutes, and it is the only stratum where a stale identifier can still mislead someone —
a closed plan's rot costs nothing because nobody is working from it.

---

## 9. Adversarial pass — what a hostile reviewer says I did not check

**(i) "Your extractor's recall is the real story, not its precision."** Checked: 302 identifier-shaped
paths sit outside backticks, a ~5% blind spot (§3). Widening past backticks is what mints
`scripts/X.sh` and `tsconfig.json`. Residual accepted and stated.

**(ii) "You never tested whether Jev will ANSWER on this content."** This is the strongest open risk
and I could not close it — the agent cannot make a call. It matters: the envelope warns that **Jev
anchors on domain reputation and that unusual content in a reputable wrapper disqualifies a task**,
and plan sections are materially more hostile-looking than the memory topic-files `rank-memory.sh`'s
198 calls exercised. `RELOGIN_AUTOMATION_PLAN.md` §`Verified facts` discusses reading **browser cookie
SQLite databases per profile**, attaching to **CDP on port 9222**, and **scraping `code#state` off an
OAuth authorize page**. `MCP_CONFIG_SSOT.md` discusses credential caches. `KITTY_DRAG_ACTION.md`
carries patches against a third-party binary. A safety-driven refusal returns **verdict-less**, which
is **byte-identical to a rate-limit exhaustion**, which is the exact failure `rank-memory.sh`'s
`CC_JEV_RANK_MAX_CONSEC_SKIP` abort exists to catch. **Mitigation, and it must be in the brief for
whoever runs this:** the pipeline sends only the ~24 stage-3 survivors, so a probe of the *specific*
sections about to be sent is cheap — run 3 of them by hand first, and treat a skip on a
credential-adjacent section as a population exclusion to report, never as a silent zero. The abort
must additionally distinguish `reason` values rather than counting all skips alike.

**(iii) "Rot might not be rare — your check might just be narrow."** Conceded, and it is the honest
reading. §6 names the two classes this arm structurally cannot reach: *cross-section contradiction
within one plan* (which the append-only convention actively creates) and *present-but-unwired*
(`hooks/x.sh` exists, `settings.json` never registers it). Both are plausibly larger than 4 findings.
The first is genuinely Jev-shaped and is the better arm; the second is a second grep. Neither is what
the brief proposed, and I am reporting the proposed arm's measured yield rather than substituting a
more flattering one.

**(iv) "Your 15 sections were cherry-picked from plans you had already opened."** Partly true — they
come from 5 plans I chose for being open and structurally varied. That is why §5 adjudicates **all 59
corpus-wide absent pairs**, not just the 7 in the hand-label set. The hand-labels test the *questions*;
the 59 test the *rate*.

**(v) "You measured one repo and extrapolated to 963."** Stated as an extrapolation throughout
(13.5 units/plan, ~540 absent pairs). It is very likely an **over**-estimate of yield: the
INTEGRATE-never-overwrite convention is strongest in this repo and weakest in the reso/doc_classifier
plans, but those plans are also the ones whose identifiers this checkout cannot resolve at all
without stage 3a.

---

## 10. If it is built anyway

Copy `scripts/jev/rank-memory.sh` structurally and without improvisation — its shape is the proven
one and every guard in it was bought by a failed run:

- the **`CC_JEV_ZDR != 0` static refusal** before call 1, naming the 403;
- the **one-call preflight** with a trivial boolean, refusing the batch if it returns no verdict;
- **exponential backoff** on `reason == "rate-limited"`, `CC_JEV_*_RETRIES`/`_BACKOFF`/`_GAP`;
- **visible skips** (`printf 'x'`) and **abort on N consecutive verdict-less calls** — extended, per
  (ii), to branch on `reason` so a safety refusal is distinguishable from exhaustion;
- **JSONL to `~/.claude/autonomy/`, `mkdir -p` checked, fail loud** — the run that reported
  "SCORED 2 of 2" over a file it never created is in that script's comments;
- **`--yes` on the command line**, so consent lands in shell history rather than in a prompt a
  non-TTY channel cannot deliver;
- **never mutate the subject.** `rank-memory.sh` refuses to touch `MEMORY.md`; this must refuse to
  touch a plan. It reports; a human corrects.

Name it `scripts/jev/audit-plans.sh`, verb `cc-jev plans`. Stages 1–3 must be runnable and
independently useful **with `--no-jev`** — on this corpus that alone produces the 24-row list a human
reads in ten minutes, and it is the half I would actually ship.
