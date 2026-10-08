# Re-ask classifier over-flagging: what to do after row 15 failed on v3 (2026-10-06)

Decision `aba630ebe329` (how to stop the classifier flagging ordinary prompts as re-asks). Researched by workflow `wf_aa8c940c-e38` (8 agents: five evidence slots, two adversarial critics, one synthesis; no sealed set opened). The synthesis agent's file write was refused by the harness, so this file is its structured return, verbatim; the slot and critic files beside it are the evidence. The operator ruled 2026-10-06: "ultracode on each /explain-decisions. then proceed with all recommendations" — so the recommendation below, including its five-part ruling, is adopted as wave E1h.

## Recommendation (conviction 78%)

Don't tune the two haiku calls. Run one measure-first wave (E1h) with every lever open, gated by a selection-and-stop rule that is fixed before the first call. Spend a fresh sealed read only on a configuration that clears that rule. Land the false-relay cost limits now, in parallel.

The steps, in order:
1. One operator ruling (contents below).
2. Build a representative tuning base:
   - a fresh 'other' sample, drawn by keyed hash from the same miner output, history included, that v4 will be drawn from;
   - a fresh regex-matched sample;
   - sealed v2 (sealed-v2.enc) retired to tuning data. It has been read twice and may not carry another verdict.
   - v1's tuning rows.
3. Run every candidate arm to completion on that base:
   - haiku 4.5 fast (thinking off) and careful (thinking on);
   - Sonnet 5.5 thinking off and thinking on;
   - Haiku 5.5, if it ships before the run starts.

   Then replay every join rule offline.
4. Apply the pre-registered rule. If no configuration clears it, stop: record it and spend no sealed data.
5. If one clears it: land it, then make one composite read:
   - v4 'other' and regex-matched, read for the first time;
   - regex-missed fresh in v4 if at least 400 unused candidates exist at the seal, otherwise v3's 25 counted items as a disclosed second read;
   - v3's 2 counted pushback items as a disclosed second read.

The operator ruling covers five things:
- (a) The REPORT section 4.1 model edit, applied only if a non-haiku_latest configuration wins.
- (b) Retiring sealed v2 to tuning data. This is irreversible.
- (c) The disclosed second reads of v3 pushback, and of regex-missed if the count rule calls for it.
- (d) Keeping the 'other' frame as all of the operator's prompts, with only a fidelity fix for strings the live hook never receives.
- (e) The section 4.2 edits for a one-word 'misrouted' override and for not carrying a relay label into envelope turns.

Expected outcome: about 35-40% that row 15 passes in this wave. Otherwise the result is a clean stop with per-configuration numbers, from which the operator can set the 'other' floor before any further read rather than after seeing a result.

The report file could not be written; see report_file. The full synthesis is in these fields.


**Conviction:** 78


## Why
 1. No rule over the two haiku calls reaches 0.90 on v3-like 'other'.
   - The algebra needs no gold: wrong non-relay labels = correct relays - 1. So the non-relay labels were at least 95% exact if 7 or fewer of the relays were right, and the failure is relay votes: 36 relays (26 fast, 10 careful), 35 misses. A pass needs 134/148, so at most about 13-15 of the 36 relays may remain.
   - Careful-confirms, the only rule that keeps the careful call's sensitivity, has a best case of 0.895-0.913 and a likely case of 0.81-0.86.
   - The careful call shares the fast call's errors. On the 14 tuning over-flags (E1c paired calls) it confirmed 6, vetoed 2 and was silent on 6 within 8.5 s. Given unlimited time it relayed 9 of the 14.
   - Rules that drop the careful call's lone relays cut borderline relays from 19/26 to 9-10/26, and they put regex-missed at risk, which has 0 misses to spare.
   - The brief lever is weak on the record: 8/56 went to 5/56 over-flags, at a cost of 1 recall row and 1 exact-label row.
   - Every tuning-chosen haiku configuration then read lower on held-out data (0.91 to 0.88/0.72; 0.93 to 0.76).
   - New: haiku 4.5 has a retirement floor of 2026-10-15, and Haiku 5.5 is due within weeks (model-config.yaml:140, 1475-1482). The router follows haiku_latest (router.py:292-308), so a haiku 4.5 fix expires within weeks.

2. Only a stronger model has a measured precision effect, but its evidence is thin where row 15 scores.
   - For it: Sonnet 5.5 thinking off relayed 1/56 neither-relay rows against haiku's 8/56, 7 to 0 paired (p about 0.016), and fits the 9 s limit (cold median 2.77 s, p90 4.71 s).
   - Against it: all 7 discordant rows are rows the raters split on, and only 1 is 'other'. On the 42 agreed rows every arm relays 1/42.
   - New count: v1 tuning holds only 4 regex-missed relay-gold rows, and Sonnet got 3 of them. That is the stratum with 0 slack on a v3 re-read. Borderline relays: 7/13 per rep.
   - Estimated v3 'other' with Sonnet as the only relay voter: 0.95 (CI 0.82-0.98). It is the leading candidate, not a proven fix.

3. The data that would decide this can be built within the method in days, and waiting fixes nothing.
   - v1 tuning is 100% transcript prompts, while the pool v3 was drawn from is 82% prompt history. P(0/21 relays | v3's rate) = 0.02.
   - Fresh 'other' is plentiful: about 25,000 unused, gaining about 1,000 a week.
   - Retired v2 adds 34 regex-missed, 24 regex-matched and 5 pushback relay-gold items plus 36 'other' items, all mined with history and already excluded from v3.
   - A fully fresh set waits on pushback: February-April 2027 at best.
   - A re-read of v3's re-ask strata is a real test: P(all pass) = 0.48 / 0.82 / 0.94 at a true recall of 0.96 / 0.98 / 0.99.

4. Independently, a false relay is costly, and capping that cost needs nothing from row 15.
   - It blocks every tool for the turn, the Stop check can force up to 2 more certificate-only replies, and the label persists through background-agent turns.
   - Once a program is certified, that is about 0.2-0.24 of ordinary prompts, or about 3-10 a day (estimated).
   - The router is idle today: the one program, TM2, is only registered.
- 78 1. Measure first, every lever open (Sonnet 5.5 leading, Haiku 5.5 added if it ships), with a pre-registered stop rule, then a composite read (fresh v4 'other' and regex-matched, minimal disclosed reuse of v3). Cost limits land now :: One ruling now. The relay notice and the narrowed --requires-gate are live in days; the 'misrouted' override and the no-carry rule follow under the ruling. In about 1-2 weeks: a certified router (about 35-40%), or a clean stop with per-configuration numbers and no sealed data spent. Sealed v2 is use
- 10 2. Adopt Sonnet 5.5 thinking off as the relay voter now, on v1 evidence, then the composite read :: About a week sooner. But a likely FAIL on regex-missed (3/4 on its only tuning rows) or on 'other' (CI down to 0.82), which uses up v4 and the method's one re-test (REPORT §6.5 cap row "Router recall below its threshold (gate row 15)"). Needs the section 4.1 model edit either way
- 4 3. Precision pass on the haiku 4.5 pair (careful-confirms or a tighter brief) :: Estimated 'other' 0.81-0.87, with a ceiling near 0.90: a likely FAIL. Any pass expires when haiku 4.5 retires (floor 2026-10-15) or haiku_latest flips to Haiku 5.5
- 3 4. Wait for a fully fresh certification set :: No row-15 pass before February-April 2027 at best, held up by pushback (1 prompt in 4 weeks). The classifier is unchanged when it comes
- 3 5. Lower the 'other' floor :: Passes on paper now, but about 1 in 4 ordinary program prompts are falsely relayed (3-10 a day). A floor at or below 0.76 chosen after seeing 0.76 fits the instrument to the result. Only a floor set from a cost argument before a fresh read is defensible, and that is option 1's fallback if it stops
- 2 6. Run uncertified :: Not possible without a method change: row 15 is PASS/FAIL only, the certificate needs every row (gate.py:212-215), and REPORT §6.5 cap row "Router recall below its threshold (gate row 15)" forbids issuing one. It also buys nothing, because no program is in a blocking state


## Build scope (wave E1h)
 Wave E1h. Locus: one dispatched session (S). Track A uses two teammates on disjoint files; Tracks B and C are run by the lead (strictly ordered around sealed files).

Frozen limits: never change row 15's thresholds or the 9 s limit; never read tuning-v2.jsonl; never tune on v3 or v4.

Track A: false-relay cost limits (parallel)
- A1. Operator-visible notice on every relay turn (tooling).
  - Where: router.py cmd_prompt and context_for, about lines 612-720.
  - Today the router sends a notice only on the third fallback in a row (router.py:714-719).
- A2. Narrow --requires-gate in typed prompts to the routed program's slug (router.py:105, 528-530, 588-600).
  - Machine envelopes are unchanged.
- A3. One-word 'misrouted' override, under the ruling.
  - One-shot, accepted only right after a relay turn; it relabels that turn 'other'.
  - Research tools stay denied; it never maps to work-order.
  - It is counted in operator-readout.
  - The Stop check still checks a reply that opens with yes/no (router.py:1085-1093).
  - Needs the section 4.2 text edit.
- A4. No relay label carried into envelope turns, under the ruling.
  - Needs the section 4.2 edit at REPORT:798-799.
  - tests/research-router.bats:229-236 flips.
- Tests: red-then-green in tests/research-router.bats.

Track B: tooling (red-then-green in research-kit-heldout.bats and research-router-heldout.bats)
- B1. Frame fidelity in the miner (only if ruled, and before any draw).
  - Verify what UserPromptSubmit receives for a '!' line and for a paste.
  - Then add heldout-candidates.py --live-frame: expand history pastedContents or drop the row, and drop '!' lines.
  - Why: today the miner reads the history 'display' string only (line 153). 7.2% of the 'other' pool carries placeholders and 4.3% are '!' lines.
- B2. New verb 'heldout.py draw' (draws a fresh sample that excludes every sealed set).
  - Usage: --candidates C --strata other,regex-matched --take other=340,regex-matched=150 --exclude tuning.jsonl --out tuning-v4.jsonl.
  - It drops every prompt in v1-v3 and in every --exclude file, using seen_key as heldout.py:153-168 does.
  - It orders the rest by a domain-separated HMAC ('take|'+prompt). This must not be seal's split hash, or every taken prompt lands on one side of the split.
  - It writes the clear tuning file.
  - Mine uncapped first: the miner's first-N in sha order (heldout-candidates.py:186-187) re-picks prompts already sealed.
- B3. heldout-rate.py --tuning F --out L.
  - Rates a clear tuning file with the same brief, two vendor families and the batch-retry rule. Prints no prompt.
- B4. 'heldout.py --set v2 retire --out F', under the ruling.
  - Decrypts v2 with its rater labels to a clear file outside the repo and records the retirement in the reads ledger.
  - sealed-v2.enc stays byte-identical (sha1 e00d6f8969d1).
  - evaluate --set v2 refuses from then on.
- B5. Subset seal and a pinned composition.
  - seal --strata subset and --take S=N|all: the emptiness check at heldout.py:176-182 applies only to the declared strata, and the set stores its strata.
  - router-heldout/instrument.json maps each stratum to a set.
  - current_set() and evaluate(name=None) read the instrument (heldout.py:101-106, 292-293):
    - each stratum is scored from its own set;
    - MIN_SET and the fallback share are pooled across sets;
    - --record rows carry the set.
  - Gate row 15 (gate_rows_b.py:357) picks the composition up with no change to its call.
- B6. Reads ledger.
  - Every evaluate appends to router-heldout/reads.jsonl.
  - The notes print 'stratum X of set vN: read k times before'.
  - The notes also print, never blocking: the false-relay rate on agreed non-relay items in every stratum, and 'other' split by history and transcript.
- Unchanged: the thresholds and the bytes of sealed v1 and v3.

Track C: measurement, selection, read (lead)
- C1. Draw, rate and commit the tuning counts before any classifier call.
  - Draw about 340 'other' (about 184 agreed) and about 150 regex-matched, then rate them (B3).
  - Add retired v2 and v1 tuning.
- C2. Tuning run. Harness in docs/research/router-classifier-e1h-*/, extending e1c-tune.py.
  - Arms: haiku 4.5 fast, haiku 4.5 careful, Sonnet 5.5 thinking off (E1b brief), Sonnet 5.5 thinking on (as-built brief), and Haiku 5.5 off and on if released before C2 starts.
  - Briefs are frozen.
  - Every call runs to completion (30 s cap); arms start together per row.
  - Reps: 1 on the fresh and v2 rows, 2 on v1.
  - Per-call data is committed with no prompt text.
  - Estimated: 4,000-6,000 calls, 2-3 hours.
- C3. Offline replay of a frozen rule list, for each fast arm X and careful arm Y:
  - X alone;
  - union(X, Y) by E1g's rule;
  - careful-confirms(X, Y);
  - X relays and Y may only veto.

  Then apply rule 1. A STOP is recorded and goes back to the operator.
- C4. On a selection:
  - router.py takes a per-kind model key and a selectable join rule (router.py:292-335, 517-579). classifier_config (router.py:338-344) then changes, so ping exits 2 until the daemon restarts.
  - Check that the warm daemon parses Sonnet's stream; the CLI prints an unrecognized-model warning on stderr.
  - Measure the canary's cost: one call per kind every 900 s, about 96 a day (classifier-warm.py:90).
  - If a non-haiku_latest model wins, make the REPORT section 4.1 named edit at REPORT:775.
  - Tests: research-classifier-warm.bats and research-router.bats; /bin/bash 3.2 for the runner.
  - Land, converge with CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh, and file the restart through migration 0059 as one operator step.
- C5. Warm latency check on 100 tuning rows through the live daemon.
- C6. Seal and rate v4 (SETS gains v4), then commit the dry-run counts and instrument.json before the read.
  - Usage: heldout.py --set v4 seal --strata other,regex-matched[,regex-missed] --take other=520,regex-matched=all[,regex-missed=all] --fraction 1.0 --exclude tuning.jsonl --exclude tuning-v4.jsonl.
- C7. One read through a git archive snapshot of the landed commit.
  - Record the verdict, the per-stratum numbers, the ledger lines and the second-read disclosure in RESEARCH_PROGRAM_BUILD.md under E1h.


## Pre-registered rules

Both rules are committed before any tuning call.

**RULE 1**: selection and stop, on tuning data only. Agreed means both raters gave the same label. Borderline rows are those where the raters split and one said completeness or pushback.

A configuration is eligible only if all three hold:
- E1 'other': exact-label rate >= 0.95 on the agreed 'other' rows of the fresh sample plus retired v2 (about 220 rows).
  - Why the margin: the tuning-to-held-out drop on record; a winner's-curse allowance of 0.02-0.04; and v4 needing a true rate of about 0.92 to pass 0.90 nine times in ten at about 280 agreed.
- E2 recall: relay recall >= 0.98 pooled over all agreed relay-gold tuning rows, and >= 0.95 within regex-missed (about 38 rows from v2 and v1).
- E3 borderline: relay rate >= 0.50 on borderline rows. That is the raters' own relay rate on the prompts they split on.
  - This deliberately replaces E1g's 17/26 bar as a gate.
  - Disclosed: Sonnet's v1 figure, 14/26, was known when this anchor was chosen.

Selection among eligible configurations:
1. the highest borderline rate, ties within 0.05;
2. then the highest 'other';
3. then a haiku_latest model over others (no section 4.1 edit);
4. then the lower warm median latency.

Latency, on the selected configuration through the warm daemon (100 rows): fallback <= 0.03 at 9 s and p90 <= 7.5 s. If it fails, take the next eligible configuration.

STOP: with no eligible configuration, nothing is landed, v4 is not sealed and no second read happens. The table goes to the operator. Rule 1 uses no v3 data. The v3 router-side splits that circulated during E1h are disclosed as known.

**RULE 2**: one certification read, with row 15's thresholds unchanged. PASS means 'heldout.py evaluate' over the pinned instrument exits 0:
- 'other' >= 0.90 on v4 (first read);
- regex-matched recall >= 0.95 on v4 (first read);
- regex-missed recall >= 0.95:
  - on v4 if at least 400 regex-missed candidates are unused by any sealed set or tuning file at the v4 seal;
  - otherwise on v3's 25 counted items, as a disclosed second read;
- pushback recall >= 0.95 on v3's 2 counted items (disclosed second read);
- fallback <= 0.10, and at least 40 agreed items.

There is no re-read on FAIL. That spends the method's '1 repair and 1 re-test' (REPORT §6.5 cap row "Router recall below its threshold (gate row 15)"). No v3 stratum is read a third time.

