# C4 judge: implementability and regression lens

Round 2, 2026-10-18. Adversarial judge (impl) for `C4-offer-lexicon.md`. Lens: do the insertion points exist where cited,
what do the existing suites pin, which interpreter runs it (bash 3.2 or awk under launchd), what it costs at runtime, and
whether it keeps one matcher per concept. I made no change to the repo except this file. Copies, harnesses and outputs are
under `/tmp/r2-C4-judge-impl/`. I read the designer's `/tmp/r2-C4/` files but wrote nothing there. Load average was
390-530 during the runs (measured: `uptime`). Each number is labelled measured (with the command) or estimated (with the
method).

**Verdict: refuted.** The C4 widening is refuted as a fix. That confirms the designer's own non-action verdict, so this is
not a refutation of the report. **Conviction 3**: my estimate that any measured C4 variant, landed, clears 90% and keeps the
six constraints. The designer gave 5.

- **Implementable.** The patch applies cleanly to today's HEAD and is bash 3.2-safe. shellcheck is clean, the pipefail
  ratchet does not move, and its kill switch restores HEAD behaviour exactly.
- **Regressions confirmed.** I reproduced the pinned-test regression (#11) on a clean A/B with zero sandbox noise. I also
  reproduced the class-B packet side effect exactly (86 against 4).
- **Three regressions the design report does not have:**
  1. The new arm uses up the shared 3-per-session cap. That costs the existing `deference` arm about 7 of its 24 fires
     (estimated).
  2. The fix the block reason tells the agent to make does not silence the arm. A filed ⛔ class-C ask fires too, which
     breaks constraint (2) by construction (measured probes). Rewording around the pattern is the only silent path.
  3. The "byte-identical packet" gate in design §6.4 is not byte-identical. It drops packets for peer-only genuine
     stops.

## 1. Insertion points (all verified at HEAD)

HEAD is now `72a18b575`, not the design's `f12dd4b12`. The two commits since then are docs only:
`git diff --stat f12dd4b12 HEAD -- hooks/ lib/ scripts/ tests/` is empty (measured). Line counts are 641 and 1,660 (measured:
`wc -l`).

| Design citation | What is there (measured: `sed -n`/`grep -n`) | OK |
|---|---|---|
| `anti-deference-nudge.sh:168` `TELLS` | `TELLS='say the word|say go…|shall i|should i (proceed|do|go)…'` | yes |
| `:453-491` genuine carve-out and packet exit | `HARD_CORE` :453, `SOFTCALL` :454, the branch :475-487, `open_packet_B` call :483 | yes |
| `:159-162` MSG extraction | the `LASTJSON`/`MSG` jq pipeline | yes |
| `PANE_STRIP_AWK` (reused) | :263-277; already used by the pane (:300) and peer (:317) arms | yes |
| the diff's hunks (`-316`, `-368`, `-419`, `-548`, `-569`, `-626`) | `patch -p1 --dry-run` applies all hunks with no fuzz to a `git archive HEAD` copy; the result is byte-identical to the designer's `/tmp/r2-C4/new/hooks/anti-deference-nudge.sh` (measured: `diff`) | yes |
| `completion-assert.sh:1280` `CA_OFFER`, `:1281` `CA_WORKLEFT`, D4 `:1272-1287` | as cited | yes |
| `:394-397` close-tell gate, `:573` ledger read, `:355,360,372,400` | `CLOSE`, `CA_SETTLED`, `CA_VERDICT_NO`, `GENUINE` as cited; D4 sits after the ledger read | yes |
| `tests/anti-deference-nudge.bats:175-178` (#11) | "Should I download the larger dataset for this analysis?" pinned silent | yes |

Small corrections to the report: the patch is **+30 net lines** (641 → 671, measured `wc -l`), not +33. The 33 is the
count of `+` lines before the 3 replaced lines are netted off. The diff also leaves the header's fire-predicate comment
(`:12-15`) without the new arm, so the comment would drift from the code.

## 2. Mechanics: interpreter, lint, kill switch (measured)

- **bash 3.2.** `/bin/bash -n` on the patched copy passes. The suite and the 503-message corpus give identical results
  under `/bin/bash` 3.2.57 (minimal `PATH`, the launchd and postland shape) and under Homebrew bash 5.3.15. Measured:
  `diff` of the two 503-run TSVs is empty, and both bats runs give the same TAP. The new code uses no bash-4 features.
  Its awk is the existing `PANE_STRIP_AWK` on `/usr/bin/awk` 20200816, and its grep is BSD grep 2.6.0.
- **shellcheck 0.11.0** (`-S warning`) prints nothing on either copy.
- **The pipefail-sigpipe ratchet** counts `hooks/anti-deference-nudge.sh` at 8 on both copies. That equals the allowlist,
  so the lint does not move (measured: `scripts/pipefail-sigpipe-lint.sh --census` with `CC_PIPEFAIL_MEMO=off` and `HOME`
  sandboxed). The new pipelines drain their input, as the pane and peer arms do.
- **Output encoding.** The new `reason` goes through the existing `jq -nc --arg r "$reason"` (`:640` at HEAD, `:670` in
  the patched copy), so a trigger
  containing quotes cannot break the JSON.
- **Kill switch.** On all 503 class-matching messages, `ANTIDEF_COND_ASK=off` gives dispositions identical to HEAD and the
  same 4 packet calls (measured: `bin/run-off.sh`, then `diff` against `b503.tsv`). Flipping it live still needs an env
  change, which means `settings.json` (operator-only) or a revert-and-land.

## 3. Test suites (measured, clean A/B)

The design's A/B had 5 sandbox failures in both copies (#26, #30, #31, #33, #34). `tests/anti-deference-nudge.bats` is on the
test-hermeticity allowlist (`scripts/test-hermeticity-lint.sh:608`): it resolves `scripts/wrap-ledger.sh` and
`bin/cc-decide` next to the hook. So I ran each suite on a **full `git archive HEAD` copy** of `hooks scripts bin lib tests`.
`HOME`, `CLAUDE_CONFIG_DIR` and `TMPDIR` were sandboxed, and the suite's own `setup()` sends `CC_DECISIONS_DIR` and `CC_IDL`
to `BATS_TEST_TMPDIR`. `bin/cc-decide` has no outbound notification path (measured:
`grep -n 'pushover|curl|osascript|notify'` finds nothing). Runner: `/tmp/r2-C4-judge-impl/runbats.sh`, bats-core 1.13.0.

| Suite | HEAD copy | C4 copy |
|---|---|---|
| `anti-deference-nudge.bats`, bash 5.3 | `1..61`, 61 ok | `1..61`, 60 ok, **`not ok 11 silent: 'should i download' does not match 'should i do'`** |
| `anti-deference-nudge.bats`, `/bin/bash` 3.2 | `1..61`, 61 ok | `1..61`, 60 ok, same #11 |
| `jev-anti-deference-arm.bats` | `1..9`, 9 ok | `1..9`, 9 ok |
| `operator-surface-scope.bats` | `1..21`, 21 ok | `1..21`, 21 ok |

These are the only three suites that execute the hook. The other test files that name it (`install-wire-hooks`,
`settings-dedup-stop`, `settings-drift`, `postland-verify`, `session-continue-telemetry`) only reference its command string
or mention it in a comment (measured: `grep -rn anti-deference-nudge tests/`). The design's single regression claim is
therefore **confirmed with no noise**: #11 is the only difference, and the HEAD copy is fully green. No consumer lists the
fire kinds in a way a new `conditional-ask` kind would break. `scripts/jev/pilot.sh:98` samples only
`deference|false-done|category-not-idea`, so it just ignores the new kind.

## 4. Reproduction of the side effects (measured)

Harness: `/tmp/r2-C4-judge-impl/bin/run.sh`, my own stubs (clean ledger, logging `cc-decide`, non-assignee identity), on the
designer's 503 class-matching messages.

| | HEAD | C4 (bash 5.3) | C4 (bash 3.2) | Design report |
|---|---|---|---|---|
| `conditional-ask` fires | 0 | **245** | 245 | 248 |
| `genuine-blocker` abstains | 7 | 110 | 110 | 109 |
| `genuine-ship-hold` abstains | 4 | 42 | 42 | 40 |
| `cc-decide open --class B` calls | **4** | **86** | 86 | 86 against 4 |

Four messages differ from the designer's run: s007895, s018309, s018325 and s018327. My result for each was the same on 5 of 5
re-runs. The designer's `corp-new.tsv` was written 7 minutes after the patch was (re)applied, so a mid-run patch is the
likely cause (estimated). None of the four is in the hand-read 60. Three are in the 233 distinct new fires, so that figure
reproduces as **230** (measured minus 3). This does not move the precision result. One of the four, s018325 ("⛔ Blocked —
need your call … or say "keep looping" and I'll run round 30"), shows the packet side effect directly. HEAD lets it through
as `no-tell` with no packet. The C4 copy sends it to `genuine-blocker` and files a class-B packet for a ⛔ stop.

## 5. Runtime cost

- **Every Stop.** The arm runs before the `no-tell` gate, so it costs something on all Stops, not only matching ones.
  Microbenchmark of the added block alone (awk strip, `grep -iE "$CONDASK"`, trigger cut), interleaved with a null loop
  over the same 1,000 seeded-random corpus messages, 3 repetitions: **+15.2, +10.8 and +12.0 ms per message** (measured:
  `bin/bench.sh` under `/bin/bash`, at load average about 450).
- **Against the live budget.** The live anti-deference duration over the 30-day corpus is p50 482 ms, p95 2,212 ms and p99
  5,056 ms, and 237 of 19,570 runs took 5,000 ms or more (measured: `ad_ms` from `stop_hook_summary`). Only **1 of 19,570**
  live runs fell in the 15 ms just under the 5-s timeout. So the added cost would push about one more run per 30 days into
  a timeout kill (estimated by shifting the measured distribution).
- **Matching Stops (about 2.5%).** Whole-hook median goes from 349 ms to 486 ms on the 503, because those messages now run
  the block path: latch, `shasum`, reason, the `ps` assignee probe, and packet calls (measured: the TSV `ms` column of
  concurrent runs, not load-controlled).
- **Verdict on cost.** Runtime is not the problem.

## 6. Regressions the design did not measure

### 6.1 The shared cap starves the existing arms (estimated)

The cap is one per-session counter of 3 across every kind (`:41`). The design names the cap only as a limit on C4's own
recall. The reverse effect matters more: low-precision C4 fires use up slots that the measured arms would have used.

- **Method.** `python3 -I /tmp/r2-C4-judge-impl/py/capsim.py`. It takes every live anti-deference demand, fired or capped,
  de-duplicated by (sid, arm, tell), from the rotated and live IDL (2026-09-28 to 10-19). It merges in the designer's
  `conditional-ask` fires inside the same window: 183 distinct, across 91 sessions. Then it replays the cap of 3 in
  timestamp order.
- **Result.** Existing-kind fires drop from 276 to 255 (−21) across 18 sessions:

| Arm | Fires | Lost to C4 |
|---|---|---|
| `deference` | 24 → **17** | about 29% of the arm C4 means to complement |
| `opaque-identifier` | 205 → 192 | 13 |
| `false-done` | 19 → 18 | 1 |

- **Caveat.** It is counterfactual: a blocked stop changes the turns that follow it.
- **Bottom line.** Any new arm on this hook has to clear the shared cap as well as its own precision bar.

### 6.2 No silent path for a legitimate ask, and constraint (2) broken by construction (measured probes)

The block reason tells the agent: "name that gate in plain words instead of asking for a yes". Unlike the pane arm
(`PANE_GENUINE`) and the peer arm (`PEER_SILENT`), the arm has no veto, so naming the gate does not discharge it.

Probes, run with `bin/run-probe.sh` on both copies (HEAD gives `no-tell` on all eight):

| Probe | C4 copy |
|---|---|
| p2: "The image picks are an operator-only taste call. Once you've picked, I'll copy …" | **fires** |
| p3: "Gate: operator-only taste call (image picks). When you have picked, I will copy …" | **fires** |
| p5: "This is a spend: $8.64 … If you approve the spend, I'll fire them." | **fires** |
| p6: "⛔ Filed as a class C decision (retention policy, 85%). On your answer, I'll hand the archive build …" | **fires**: a filed ⛔ decision is blocked, which breaks constraint (2) directly |
| p7: "Tell me when the call is over and I'll resume …" | **fires** |
| p4: "Waiting on your image picks; I will copy them into references/ after that." | silent |

The only probe that stays silent (p4) is a rewording that drops the conditional form. For the 52 of 60 sampled fires that
were legitimate asks, compliance is therefore cheapest by rewording around the pattern, or by adding `HARD_CORE` or
`SOFTCALL` vocabulary. The second route sends the stop to the genuine exit and files a class-B packet. Both are the
"trains the model to route around it" and "bolt a genuine-marker on" failures the hook header warns about (`:30-31`,
`:447`).

### 6.3 The design's §6.4 packet gate is not byte-identical

The design says a revived C4 must gate `open_packet_B` on `has_tell || has_done || has_cat` so "the packet producer stays
byte-identical". At HEAD, a message reaches the packet branch (`:475`) when it carries any of
`has_tell, has_done, has_cat, has_peer, has_jev`. `has_id` and `has_pane` are excluded by the branch condition, and the rest
pass the `no-tell` gate at `:422`. The proposed gate therefore drops packets for **peer-only** genuine stops (and for
jev-only ones, if Jev is revived). The byte-identical form is `has_cond -eq 0 || <any of the five>`, or equivalently a guard
that only skips the packet when `has_cond` is the sole arm.

## 7. One matcher per concept

The design says "No second copy of a matcher is introduced". That holds only for the strip and split code. The arm adds a
fourth matcher for the offer and permission-ask concept:

- **The `shall` half of `CONDASK_QUESTION` is dead code that copies `TELLS`.** `TELLS` matches `shall i` on the raw text
  with no right boundary. `has_tell` is decided first, so every sentence the `shall` branch could match is already a
  `deference` fire. Measured: 0 of 245 `conditional-ask` triggers start with "shall i", against 11 that start with
  "Should I". The `should` half is exactly the case #11 pins silent.
- **`CONDASK_REPLY` and `CONDASK_ASSENT` restate spellings `TELLS` already has** (`say go`, `say the word`,
  `give me the word`, `on your word`) as a broader structural class. The two now drift as separate lists in one file.
- **`CONDASK_ASSENT … CONDASK_ACT` is a second structural matcher for the conditional handback.** `PANE_COND` (`:293`) is
  the first, and its own comment (`:290-292`) already measured the bare `(once|if|when) you … I'll` lead at **9 of 10 new
  hits false** on 2,051 candidates. That is why it was restricted to pane verbs and locations. C4 brings back that
  measured-bad lead with its own list of lead words (`whenever` added).
- **The two lexicons the candidate is named for are not touched.** `CA_OFFER` (`completion-assert.sh:1280`) and
  `scripts/conviction-census.py:93` already hold copies of this concept. So C4 as built adds a matcher instead of widening
  one. A one-matcher version would put the offer lexicon in a `hooks/lib/` file, as `close-shape.sh` does for the close
  contract. That is outside C4 and is not proposed.

## 8. What this judge confirms from the design

- **Confirmed (measured here).** The #11 regression, the 86-to-4 packet side effect, the 11 "Should I" fires, the kill
  switch, and every citation.
- **Not re-measured.** The design's precision labels. I spot-read 6 of them (s011218, s010555, s001728, s006578, s007257,
  s010756), and the trigger sentences and labels match the stated reasons. That is not a second-reader audit.
- **Overall.** The non-action verdict stands. Through this lens it is stronger than the report says, because of §6.1 to
  §6.3.

## 9. Required changes (only if anyone revives C4; none would bring it near 90%)

1. A per-sentence silent path for named operator-only gates, written as a class and not a spelling list. Otherwise
   constraint (2) fails (§6.2). The design shows why that is hard: the vetoes also remove the true positives.
2. Leave out the `should i <verb>` branch, or re-decide #11 openly. Leave out the dead `shall` branch (§7).
3. Make the packet gate truly byte-identical (§6.3).
4. A cap budget for the new arm that does not take slots from `deference`, `false-done` or `opaque-identifier` (§6.1).
5. Update the header's fire-predicate comment (`:12-15`).

## Workspace (all under `/tmp`, not durable)

- `/tmp/r2-C4-judge-impl/res/`: bats TAP files, plus `b503`/`n503`/`m503`/`o503.tsv`.
- `/tmp/r2-C4-judge-impl/sbx/`: IDL and `decide-*.log` for each run.
- `/tmp/r2-C4-judge-impl/bin/`: `run.sh`, `run-off.sh`, `run-probe.sh`, `bench.sh`, `runbats.sh`.
- `/tmp/r2-C4-judge-impl/py/capsim.py`.
- `/tmp/r2-C4-judge-impl/probe/probes.txt`.
