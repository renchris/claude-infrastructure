# E1h slot: method rules — may a disclosed second read of v3's re-ask strata, combined with a fresh sealed `other` sample, certify a changed configuration?

Worktree read: `/Users/chrisren/Development/.worktrees/wt-cc-024434-55635` at HEAD `ff3e87fb7` (E1g done). The brief's
`git pull --ff-only` was NOT run: this worker's rules forbid any git mutation (a pull is a merge into the worktree).
HEAD already carries the E1g record, so nothing the brief names is missing. No sealed set, key, `tuning-v2.jsonl` or
miner output was opened. `/tmp/e1h-research/cands.jsonl` (a sibling's file, 7 MB) was not read. Router-side reading
files were tallied for labels only.

## 1. Short answer

**Yes, it is acceptable under the method's written rules, provided it is disclosed. But it needs an operator ruling,
because every wave scope since E1b has made it one, and it needs tooling that does not exist yet.**

- The method has no cap on how many times a sealed set may be read. Its held-out test is "never used to write or
  tune it" (REPORT:606). Gate row 15 is itself built to re-read the newest set on every `gate.sh run`.
- The "one read" and "no second read" lines are build-plan conventions scoped to a wave ("in this wave"). They are
  not method text.
- The closest precedent supports a disclosed second read under an operator ruling. E1d/E1e read v2 a second time
  under ruling `2137be2c1d33`, by a configuration whose call path had been chosen knowing the first read.
- `heldout.py` cannot evaluate a combination today:
  - `seal` refuses a set that lacks any stratum.
  - `evaluate` reads exactly one set and fails a stratum with no agreed item.
  - Gate row 15 always reads the newest sealed set.

## 2. The rules, with citations

### 2.1 What makes a set "held-out"
- REPORT = `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`.
- **REPORT:606 (row 15).** The text is: "This run: the re-ask router (§4.1) labels a held-out set of at least 40
  completeness and pushback phrasings, drawn from your transcripts and **never used to write or tune it**, with a
  recall of at least 0.95. The set size and the threshold are **assumed inputs** until the calibration run measures
  the router (§6.6) … **After one repair and one re-test**, a recall still below the threshold fails the row."
  - The criterion for held-out is about tuning, not about how many times the set is read.
  - The method's 40 counts completeness and pushback phrasings across strata. `heldout.py:304` applies 40 to all
    agreed items.
- **REPORT:1078 (§6.5 caps table).** "Router recall below its threshold (gate row 15) | 1 repair and 1 re-test |
  Gate row 15 fails, and no certificate issues until the router is fixed as tooling (§8, item 5), not as research
  on the program."
  - This is the only count-like rule the method has on row 15.
  - Read literally, it allows one repair (E1h's configuration change) and one re-test (a second read).
  - It is written for recall, at a program's gate. The `other` floor came later (§10 item 11, below).
  - Its fallback is "fixed as tooling", which has no count limit.
- **REPORT:1379-1381 (§10 items 11-13).** These are acceptance requirements for the build (REPORT:6-8).
  - Item 11 adds "a minimum correct-label rate" on non-completeness prompts and "a maximum fallback rate", with **no
    number**.
  - Item 12 adds the strata, with ≥ 0.95 recall in each.
  - Item 13 requires a sealed, two-rater set read by gate.sh at run time.
- **Gate row 15 re-reads by design.** `scripts/research-kit/lib/gate_rows_b.py:351-362` calls
  `heldout.evaluate(CC_RESEARCH_ROUTER)` with no set argument on every `gate.sh run`.
  - `heldout.py:101-106` `current_set()` then picks the newest sealed set.
  - So, under the method, a certified router's set is read again at every program's gate. Repeated reads by a fixed
    router are built in.
  - The integrity concern is choosing a configuration from what a read showed.
- **`skills/research-program/` has no rule on held-out reads, sealed sets or row-15 thresholds.** Measured:
  `grep -rn -iE "held-out|heldout|sealed|row 15|router|threshold|assumed input"` over the skill dir. The only hits
  are rubric (b) and unrelated "sealed" mutants/dirs. The same is true of `scripts/research-kit/RECORDS.md`: no
  held-out rule.

### 2.2 Read-count rules: they exist only as build-plan conventions
BUILD = `docs/plans/RESEARCH_PROGRAM_BUILD.md`.

| where | text (paraphrase unless quoted) | scope |
|---|---|---|
| `heldout.py:21-22` | "a sealed set is sealed once" (re-running `seal` cannot fish a different split) | sealing, not reading |
| `heldout.py:24-33` | v1 "read three times while the classifier was being configured"; v2 "read twice … the second time by a configuration chosen knowing the first read, so wave E1g seals v3 … for one read" | history and rationale, no rule |
| BUILD:478-479, 502-504 | E1b disclosure: v1 read three times since sealing; E1c: v1 "cannot carry a verdict" (3 reads, strata too small) | the reason for minting v2 |
| BUILD:552 | "No second read of v2 follows **in this wave** under any outcome." | E1c only |
| BUILD:609-611 | "A later read of v2 is biased by that much and must say so." | allows it with disclosure |
| BUILD:639-646 | E1d scope, operator ruling `2137be2c1d33` "build-warm": "read sealed v2 exactly once more … record … the second-read disclosure" | **operator-approved second read** |
| BUILD:689-691, 726-727 | labeling configuration byte-for-byte E1c's `on-pre`; "only the call path changed" | the precedent's condition |
| BUILD:774-778 | E1e: "the decision to build and activate the warm path was made knowing the first read's numbers … v2 … should not carry a **third** verdict for any configuration chosen with these numbers in hand" | caps v2 at two reads, by convention |
| BUILD:888 | E1g scope: "never read v1 or v2; never tune on v3" | E1g |
| BUILD:992 | "v3 is not read again **in this wave** under any outcome" | E1g only |
| BUILD:1028-1032 | v3 disclosure: anyone choosing a configuration "knows that `other` read 0.76 … a second read is biased by that" | anticipates a disclosed second read |
| BUILD:975-977 | `tuning-v2.jsonl` is now sealed v3 content in the clear; "must not be read by anyone who builds the classifier" | still binding |

**Conclusion on read counts.**
- The method sets no numeric limit (searched REPORT, the skill and the kit headers).
- The practice the build plan has set, and the operator has ruled on once, is:
  - one pre-registered read per set;
  - at most one further read, disclosed as biased, under an operator ruling;
  - no third verdict for a configuration chosen with the earlier numbers in hand.
- A second read of v3's re-ask strata fits inside that practice. A third would not.

### 2.3 Thresholds as operator inputs
- **The method text fixes only recall ≥ 0.95 and the set size ≥ 40, and calls both assumed inputs.** Citations:
  REPORT:606; §6.6 at REPORT:1091-1105, where the calibration run measures "the re-ask router's recall on held-out
  phrasings (gate row 15)".
- **The router is still uncalibrated.** `docs/research/research-calibration/REPORT.md:101` ("0.95 assumed | pending"),
  `:198` and `:257`; also BUILD:100.
- **The `other` ≥ 0.90 floor and the fallback ≤ 0.10 cap are not in the method text.** §10 item 11 gives no number
  (REPORT:1379). They were set at build time.
  - Measured: `git log -S MIN_OTHER_CORRECT -- scripts/research-kit/heldout.py`. The first commit is `92cf72197`,
    2026-10-01.
  - They are labeled "Assumed inputs until the calibration run measures the router (§6.6)" (`heldout.py:60-69`), and
    `evaluate` prints the same (`heldout.py:400-403`).
- **Changing a threshold is a material change.** Rubric (b): "changes an acceptance row's verdict or threshold"
  (REPORT:635; `skills/research-program/RUBRIC.md:13`).
- **Method changes must follow ruling 8.** "Change only named sections, from measured results" (REPORT:1193 and
  REPORT:6-8). Ruling `1bf69e5c1775` overrode that freeze only for four named changes (REPORT:1199-1208).
- **Who decides.** E1b names the thresholds "the operator's call" (BUILD:489). Every wave scope since E1b says
  "never change row 15's thresholds" (BUILD:444, 499, 645, 682, 887). The 9 s limit is likewise an operator ruling
  (`4bf73c4e55d5`, REPORT:1210-1213).
- **The classifier model is a method parameter.** §4.1 says the classifier is `haiku_latest` (REPORT:775). E1b
  option (c), "a different classifier model or thinking budget", is "a §4.1 method parameter" (BUILD:488).
- **Certification needs every row.** `scripts/research-kit/lib/gate.py:212-215` writes a certificate only when every
  row is PASS or FILED, and row 15 returns only PASS or FAIL (`gate_rows_b.py:358-362`). Row 15 is not in the
  "stated on the certificate, never blocking" list (REPORT:608-612).

### 2.4 How much of v3's re-ask strata is already known, and how much slack it leaves
- **What the first read disclosed** (BUILD:998-1008):
  - recall: regex-matched 47/47, regex-missed 24/25, pushback 2/2;
  - 0 fallbacks.
  - The per-id router labels and paths are in `reading-v3-2026-10-05{,.paths}.jsonl`, with no prompts and no gold.
  - Without the prompts, no one can tune against those ids.
- **Slack at ≥ 0.95** (computed: ceil(0.95·n)):

  | stratum | first read | needed to pass | misses allowed |
  |---|---|---|---|
  | regex-matched | 47/47 | 45 of 47 | 2 |
  | regex-missed | 24/25 | 24 of 25 | 0 more |
  | pushback | 2/2 | 2 of 2 | 0 |

  A configuration that loses one more regex-missed relay, or either pushback relay, fails.
- **Labels move between reads of the same configuration.** In E1e, 22 of 151 items that were answered twice changed
  label (BUILD:766-770).
- **Estimated chance of passing on these sizes** (exact binomial, assuming the true recall is constant):

  | true recall | regex-missed (n=25) | regex-matched (n=47) | pushback (n=2) |
  |---|---|---|---|
  | 0.96 | 0.74 | 0.71 | 0.92 |
  | 0.98 | 0.91 | 0.93 | 0.96 |

  So a second read is a real test, not a formality.
- **Router-side tally of the v3 record** (measured, python over `reading-v3-2026-10-05.jsonl`, labels only):
  - `other`: 28 completeness and 8 pushback (36 relays), 47 other, 34 work-order, 15 research-order, 10 new-idea,
    6 concern (n = 148 counted).
  - regex-missed: 50 relays among 180 counted, with 25 relay-gold. So about 25 or more relays went to non-relay-gold
    items that row 15 does not score.
  - regex-matched: 58 relays among 114 counted, with 47 relay-gold.
  - **Row 15 measures over-relay only in stratum `other`.**
- **Bias of the second read, stated plainly:**
  - **Selection.** The re-ask strata are being reused because they passed. Had they failed, E1h would be a
    different design. 73/74 is therefore an optimistic estimate of the union's recall.
  - **Direction.** A precision pass that can only demote relay labels cannot raise recall. The second read then
    measures how many true relays the pass removed. That is the right question, and it is biased only through the
    selection above, as long as the pass is designed without v3 knowledge beyond the published aggregates.
  - **Tuning on v3.** A configuration tuned against the v3 `other` result (0.76; 26 fast and 10 careful relays) is
    "chosen with these numbers in hand". That is the BUILD:776-778 condition. Any fresh sealed `other` read
    escapes it, and v3's re-ask strata do not depend on it.

## 3. Does heldout.py support "fresh `other` + reused strata"? No. What it would take.

**Today:**
- `seal` refuses a split missing any stratum: `heldout.py:176-182` (`missing = [s for s in STRATA if not any(...)]`).
  So an `other`-only (or `other` + regex-matched) v4 cannot be sealed.
- `seal` also drops every candidate already in an earlier set (`heldout.py:153-160`). So v3's re-ask items cannot be
  copied into v4. A copy would also hide where they came from.
- `evaluate` loads one set (`heldout.py:292-293`) and fails any stratum with "no agreed item to measure"
  (`heldout.py:352-353`).
- Gate row 15 calls `evaluate` with no set (`gate_rows_b.py:357`), so a newer v4 would become the set row 15 reads
  (`heldout.py:101-106`).
- `heldout-rate.py` takes `--set` from `heldout.SETS` (`heldout-rate.py:74`), so it rates any new set name.
- Nothing records how many times a set was read. Reads appear only in BUILD prose and in the `heldout.py` header.

**Minimal tooling change (one wave, red-then-green tests in `tests/research-kit-heldout.bats` /
`research-router-heldout.bats`):**
1. **`seal --strata other[,regex-matched]`.** Let a set hold a declared subset of strata. Check `missing` against the
   declared subset, keep the dedupe against every earlier set and `--exclude` file, and store `strata` in the set.
2. **A pinned composition that both `evaluate` and gate row 15 resolve.**
   - Either `evaluate --from v3:regex-matched,regex-missed,pushback --from v4:other`, or (better, since gate row 15
     passes no arguments) a committed or keychain-adjacent `instrument.json` naming the set per stratum.
   - `current_set()` / `evaluate(name=None)` would read the instrument instead of "the newest set".
   - Valid items are pooled across sets for `MIN_SET` and the fallback share. Each stratum is scored from its named
     set only.
   - Notes and `--record` rows carry the set per item.
3. **A read ledger.** Append `{set, strata, router commit/hash, started, verdict}` to `router-heldout/reads.jsonl`
   on every `evaluate`, and print "stratum X of set vN: read k times before" in the notes. This turns the
   "disclosed" in "disclosed second read" from prose into something the gate prints.
4. **Unchanged:** `MIN_RECALL`, `MIN_OTHER_CORRECT`, `MAX_FALLBACK`, `ROUTER_TIMEOUT_S`, the two-rater same-label
   rule, and sealed v1, v2 and v3 bytes.
5. **Candidates.** The miner keeps the first N per stratum in sha order (BUILD:1039-1040;
   `heldout-candidates.py:29`). The fresh `other` needs a cap above v3's 400 so that it gets past already-sealed
   prompts. Seal-time dedupe removes the rest.

**Sizing the fresh `other`** (estimated):
- At v3's agreement rate (148 of 273 = 0.54), about 500 sealed `other` gives about 270 agreed.
- Exact-binomial chance of reading ≥ 0.90:

  | n agreed | true 0.88 | true 0.90 | true 0.92 | true 0.94 |
  |---|---|---|---|---|
  | 148 | 0.21 | 0.48 | 0.79 | 0.97 |
  | 300 | 0.16 | 0.55 | 0.91 | 1.00 |

- A configuration needs a true rate of about 0.92 or more to pass reliably.
- A fresh `other` pool can also give a **tuning split** (`seal --fraction < 1`, HMAC-chosen). That is the first
  `other` tuning set that is not v1's 44 rows, which have overstated `other` every time (BUILD:1021-1023,
  1037-1038). It is allowed by every rule above.

## 4. What each option needs under these rules

| option | method / ruling needed | certification path under the rules | tooling | notes |
|---|---|---|---|---|
| **precision-pass** (demote or recheck relay labels on non-re-asks) | A router change "fixed as tooling" (REPORT:1078; §8 item 5). No method edit if the model (haiku) and the 9 s limit hold. By precedent, an operator ruling for the wave and for the disclosed second read (as `2137be2c1d33`, `b18c74a4f8e1`) | Pre-register the configuration on tuning data only: v1 tuning, E1c/E1g per-call data, and a **new fresh-`other` tuning split**. Never `tuning-v2.jsonl`, never v3. Then one read: v4 `other` (first read) + v3 re-ask strata (second read, disclosed) | §3 items 1-3 | Can only lower recall, and regex-missed and pushback have 0 slack on v3. An exact-label `other` also needs non-relay confusions (work-order vs other) to be right (`heldout.py:341-342`). The pass must lift `other` from 113 to at least 134 of 148-equivalent |
| **stronger-model** (a different model for the fast and/or careful call) | A §4.1 method parameter (REPORT:775; BUILD:488), so a ruling-8 named-section edit from measured results plus an operator ruling. It must also fit the 9 s limit of ruling `4bf73c4e55d5` | Same composition. But a new model changes recall too, so the second read of v3's re-ask strata carries more weight (and less bias: v3 says nothing about the new model except through the selection decision) | §3 items 1-3 | Latency must be re-measured on tuning (BUILD:448-452, 740-742) |
| **lower-the-floor** (`other` < 0.90) | Material under rubric (b) (REPORT:635, RUBRIC.md:13). The operator's call (BUILD:489), against every wave's "never change row 15's thresholds". A priced edit under ruling 8 that names `heldout.py:65-69` and §10 item 11. The 0.90 itself was never method text (REPORT:1379; commit `92cf72197`) | Re-scoring v3's existing reading needs no new read, but choosing a floor at or below 0.76 after seeing 0.76 is fitting the instrument to the result. That is the clearest breach of "from measured results" in spirit. A cleaner form: set the new floor from a cost argument before any further read, then read fresh `other` | none (constants) | §4.1's "a wrong fallback costs one turn without research tools" (REPORT:783-784) understates a false relay: a relay label blocks **every** tool that turn (REPORT:766-767). At 36/148 that is about 1 in 4 ordinary program-session prompts (estimated from v3) |
| **run-uncertified** | No waiver exists. Row 15 is PASS/FAIL only (`gate_rows_b.py:358-362`), the certificate needs every row (`gate.py:212-215`), and "no certificate issues until the router is fixed" (REPORT:1078). Moving row 15 to "stated, never blocking" (REPORT:608) or printing "router uncertified" is a method change: rubric (b), ruling 8, operator ruling | none | a row-15 status change (FILED or printed) | The router is already live (E1g), so the hook runs either way. "Uncertified" here means programs proceed without a certificate, or with a printed caveat |
| **wait-for-population** | None: a fresh set is held-out by every rule (REPORT:606) | A new full set v4 once the pool supports all strata | none beyond today's | Pool per brief: about 419 regex-matched, about 13 regex-missed, 0 pushback. v3 needed 326 sealed regex-missed to get 25 relay-gold (BUILD:973, 1001), and the whole year-deep history held 49 pushback prompts, all used (BUILD:894-896). Estimated: regex-missed takes months at the v2→v3 gain of 8 per day-ish (BUILD:895-896, a one-day sample); pushback has no foreseeable date. `seal` refuses a set with no pushback (`heldout.py:176`) |

**Hybrid the rules allow.** A fresh regex-matched stratum is also possible: about 419 unused gives about 330 agreed
and about 135 relay-gold at v3 rates (estimated). Only regex-missed and pushback would then rest on the second read
of v3, which narrows the disclosed reuse to 27 items (25 + 2).

## 5. Caveats
- The brief's `git pull --ff-only` was skipped (git mutation forbidden to this worker). HEAD `ff3e87fb7` already
  holds E1g's record.
- Decision records `2137be2c1d33` and `b18c74a4f8e1` themselves (`~/.claude/autonomy/decisions/*.json`) were not
  opened: they are not on the brief's read list. Their content is taken from BUILD:639-646 and 874-875.
- The pool counts (419 / 13 / 0 / 25,000) are the brief's and were not re-measured; the miner was not run.
- The `other` miss composition (relay over-flags against non-relay confusions) cannot be split without gold labels.
  There are 36 relays and 35 misses, so at least 1 relay was correct and the number of non-relay misses equals
  (correct relays − 1).
