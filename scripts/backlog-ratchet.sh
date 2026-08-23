#!/usr/bin/env bash
# backlog-ratchet.sh — the two standing numbers that make backlog rot VISIBLE before it is a pile.
#
# WHY THIS EXISTS. On 2026-08-09 a one-time triage adjudicated 460 open items and closed 161 of them
# as dead or absorbed — 35%. That pass cost ten agents and a night. The reason it was ever needed is
# that nothing measured the decay: no number moved as the store rotted, so the only signal was the
# operator eventually feeling the pain and asking for a heroic sweep. A sweep is not a mechanism.
# Without a standing measurement the next pile is invisible until it is the same size.
#
# THE TWO NUMBERS, and why exactly these:
#
#   falsifier coverage   — what fraction of open items can re-check themselves at claim time
#                          (`cc-backlog add --falsifier`, re-run by cc-premise). This is the ONLY
#                          property that makes an item self-validating rather than believed, so it
#                          is the leading indicator: coverage rising means future items cannot rot
#                          silently, whatever happens to the ones already filed.
#   age at close          — how long a closed item sat before somebody adjudicated it. The lagging
#                          indicator. Reported as MEDIAN **and p75**, and the pair is the point:
#                          measured on the live store 2026-08-10 the median is 0.1 days while p75 is
#                          2.2 and max is 19.7. A median-only report would have read "healthy" for
#                          exactly the population this script exists to catch, because most items
#                          are machine-generated and close within hours — they drown the human-filed
#                          tail where rot actually accumulates. Pick the statistic that can MOVE
#                          when the problem appears (MEMORY.md: alarm-polarity-and-attention-budget).
#
# WHY IT IS A CENSUS AND NOT (YET) A GATE. Coverage is currently near zero: the `--falsifier` field
# landed in a7bf7068 and no generator emits one yet (master M2 wires that). A gate armed today would
# red on every run, and an alarm that always fires carries exactly as many bits as one that never
# does (MEMORY.md: alarm-polarity-and-attention-budget) — it would be read past by the time it
# started meaning something. So: report always, and `--assert` blocks ONLY on a downward move
# against the recorded high-water mark. That arms itself the moment coverage becomes non-trivial,
# with no flag day and nothing to remember.
#
# NO COMMITTED BASELINE, deliberately. A checked-in expected-value file is a permanent exemption
# list wearing a number (the same failure test-hermeticity-lint's own comment warns a ratchet must
# never become). The high-water mark lives in a state file that is regenerated from the store, so
# losing it costs one run, never a wrong verdict.
#
# ── 2026-08-11 · THE RATCHET WAS DEAD, AND HAD NEVER ONCE BEEN GREEN (READINESS W0) ──────────────
# Measured on the live store: `coverage_high_water` sat at **100.0%** while live coverage was 51.5%,
# so `--assert` returned rc=1 on EVERY run, and all 3 `ratchet_rc` values `autonomy-sweep` had ever
# journalled were `"1"` — which the sweep documents as "ratchet saw coverage FALL". The alarm this
# file exists to be had degenerated into the exact defect its own header warns about two paragraphs
# up: one that always fires carries as many bits as one that cannot. Backlog coverage decayed from
# 32.5% to 28.7% across a single day with nothing to show for it, because the only instrument
# watching had been red the whole time and nobody could tell that read from any other.
#
# Two independent causes, and BOTH had to be fixed for either to matter:
#
#   1. THE TARGET WAS UNREACHABLE. 100% coverage is not an attainable state of this population and
#      never was: the 2026-08-11 CURRENCY pass deliberately left 103 items unprobed (investigations,
#      design calls, multi-part conditions a single token would half-retract), and the `needs` class
#      has no machine oracle at all — its `--run` PERFORMS the operator step, so running it as a
#      probe would execute the thing it tests. A high-water the population cannot reach makes GREEN
#      structurally impossible, so the ratchet can only ever be red. Hence CEILING below: prove the
#      healthy event CAN happen before you let a number latch as the target
#      (MEMORY.md: cap-whose-population-is-empty).
#   2. THE TARGET WAS RECORDED FROM A POPULATION NOBODY VERSIONED. Whatever read produced 100.0%,
#      nothing in the state file said WHAT had been counted, so no later run could tell a genuine
#      regression from a change of denominator. `denominator_version` fixes that permanently.
#
# ⚠️ A THIRD CAUSE WAS PROPOSED HERE AND MEASURED FALSE — recorded because the mistake is the
# instructive part. The first draft of this fix asserted that "168 open `needs` rows sit in `live`
# and dilute a firing-readiness metric they are not part of", and added `$probeable` to remove them.
# Measured against the fold: **`needs` rows are born BLOCKED** (bin/cc-backlog:544 — the verb
# deliberately files them blocked and skips the dispatch kick), so `live` = open ∨ claimed had
# ALREADY excluded 167 of the 168; the exclusion removes **zero** rows today and the coverage number
# never moved. The 505-row figure that motivated it came from `cc-backlog list --open`, whose
# projection INCLUDES 198 blocked rows — so the denominator under suspicion was the analyst's, not
# this script's. Correct numbers: 304 open + 3 claimed = 307, of which 157 carry a probe.
# `$probeable` is KEPT as defence-in-depth — one `needs` row is currently open, proving a reopen can
# put the class back into `live` — but it is a guard against a future reclassification, NOT a fix for
# a present dilution, and the census prints the excluded count so it can never again be assumed
# non-zero (MEMORY.md: positive-control-the-denominator, committed here by the person invoking it).
#
# WHY A DENOMINATOR VERSION RATHER THAN A QUIET RE-BASELINE. Changing what is counted makes the old
# high-water incomparable, not merely stale — and silently re-baselining is the one thing a ratchet
# must never do (the very next paragraph of this header). `denominator_version` in the state file
# makes the reset an explicit, dated event: a version bump resets the mark and SAYS SO, while a fall
# under an unchanged version still reds exactly as before.
#
# ── 2026-08-15 · THE NUMERATOR COULD NOT SEE TWO OF THE THREE PROBE ARMS (item e08ad9ab1ff6) ─────
# The header above defines coverage as "what fraction of open items CAN re-check themselves" and
# calls it "a property of the ROW". The implementation counted `select(.falsifier != "")` — the
# STORED field alone — while the consumer that actually re-checks a row, cc-premise `assess`,
# composes THREE arms and records which fired in `probe_kind`: stored, derived-plan,
# derived-postland. So this file and cc-premise disagreed about the one question both claim to
# answer, over one population.
#
# THAT INVERTED THE ALARM RATHER THAN MERELY BLURRING IT. `post-land RED:` rows store no probe ON
# PURPOSE — cc-premise derives that predicate, and postland-verify's own `--falsify-red` header
# records that storing an equal probe there would "shadow a tested, documented arm and buy nothing
# but a second implementation to keep in sync". postland-verify is also the highest-volume generator
# in the fleet: one row per failing suite per red run. Those rows sat in the DENOMINATOR and could
# never reach the NUMERATOR, so **every red trunk mechanically depressed coverage** even though no
# row had lost any ability to re-check itself — and `--assert` went RED on exactly that. Its
# remediation line then said "Add --falsifier to the generator that regressed", which for that
# population is the one change its sibling documents as harmful. An alarm firing on the wrong event
# and prescribing a forbidden cure is what this file's own header exists to prevent
# (memory: alarm-polarity-and-attention-budget).
#
# THE FIX IS THE ONE THIS REPO HAS ALREADY PAID FOR TWICE: ONE ARBITER PER FACT. The `freshness`
# block below is this file applying it once already — cc-backlog owns the fold, so the ratchet asks
# it rather than re-deriving. Coverage now does the same and asks `cc-premise coverage`, which
# classifies each live row by ARM and by SOURCE without executing anything. `denominator_version`
# goes to 3, because the NUMERATOR changed and a v2 mark measures a different thing.
#
# The RED also NAMES THE GENERATOR now. It used to say "the generator that regressed" and name none,
# leaving the reader to find it — and, for the postland population, to find that none had.
#
# Usage:
#   backlog-ratchet.sh              census to stdout, always exit 0
#   backlog-ratchet.sh --json       machine-readable, for a hook or a dashboard
#   backlog-ratchet.sh --assert     exit 1 iff coverage fell below the high-water mark
#
# EXIT CODES — three, and the third is why the engine guard below is fail-CLOSED (backlog 2366f99e04a7):
#   0  measured: coverage is at or above the high-water mark (census/json always 0)
#   1  --assert only: coverage fell below it
#   2  COULD NOT MEASURE — bad usage, or THE ENGINE IS ABSENT (no jq)
#
# Knobs (all defaulted; each exists because an unguarded latch is how this file died once):
#   CC_RATCHET_MAX_HW   ceiling on a recordable high-water   (default 95.0 — 100 is unreachable)
#   CC_RATCHET_MIN_N    floor on the denominator that may set one (default 20 — a degenerate
#                       read of 1-of-1 must never latch 100% as the fleet's target)
set -uo pipefail

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
STATE="${CC_RATCHET_STATE:-$HOME/.claude/autonomy/backlog-ratchet.json}"
# ── THE THIRD NUMBER (W1, backlog b585e86ea4e4): EXECUTION, not capability ───────────────────────
# This file's own header says coverage is "what fraction of open items CAN re-check themselves". It
# is a property of the ROW, and it was the only number here — so a store could read 100% covered and
# 0% ever-executed and this census would print a clean bill of health over it. That was not
# hypothetical: `run_falsifier` had exactly ONE call site, the claim path, and 205 of 327 live rows
# had never been claimed, so their probe had most likely never run at all.
#
# NEVER-VALIDATED is the missing half and it is deliberately NOT part of the ratchet's assert. The
# assert exists to catch a REGRESSION against a high-water mark; this number starts at 100% of the
# store and falls as the currency pass works through it, so asserting on it would red for months
# while the mechanism was working exactly as designed. It is a CENSUS line — reported every run,
# gating nothing (memory: alarm-polarity-and-attention-budget: prove the healthy event can happen
# before you let a number gate).
VALIDATED="${CC_BACKLOG_VALIDATED:-$HOME/.claude/autonomy/backlog-validated.json}"
MODE="census"
case "${1:-}" in
  --json)   MODE="json" ;;
  --assert) MODE="assert" ;;
  --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  "") : ;;
  *) printf 'backlog-ratchet: unknown arg %s\n' "$1" >&2; exit 2 ;;
esac

# ── THE ENGINE GUARD IS FAIL-CLOSED (backlog 2366f99e04a7) ───────────────────────────────────────
# Same defect and same shape as scripts/backlog-grouping-sweep.sh carried for its entire deployed
# life (fixed in 963dbd0a2). This script is wired into autonomy-sweep.sh:539 as `--assert` on a
# 300 s tick with `>/dev/null 2>&1`, so the one-line stderr below reached nobody and the rc was the
# only thing that left the process.
#
# 🚨 AND HERE THE FAIL-OPEN DID NOT MERELY MISREPORT — IT WOULD HAVE RETRACTED A STANDING ROW.
# `--assert` is registered as a stored falsifier at autonomy-sweep.sh:803 for the row it files
# (condition backlog-ratchet-coverage-regression), and cc-premise's `run_falsifier` reads exit 0 as
# THE CONDITION IS GONE. So an absent jq did not just fail to measure coverage: it told the currency
# pass the coverage regression had cleared, and the closer would retire the alarm on the strength of
# a measurement that never ran. 2 is in cc-premise's `_FALSIFIER_UNASKABLE_RCS` ({2,124,126,127}),
# which renders "UNVERIFIED, not confirmed" — the state this actually is.
#
# 2, NOT A NEW CODE, and this file already agrees: the unknown-arg arm above exits 2 for exactly this
# meaning. A fourth code would land outside that set and render "NOT REFUTED", stranding the same
# consumer (memory: new-enum-member-falls-into-fail-closed-default).
#
# NO FILING HERE, UNLIKE THE TRIGGER SIBLING — a deliberate asymmetry, not an omission. The trigger
# files from `--file`, the mode autonomy-sweep schedules for it. This script's scheduled mode IS the
# falsifier probe, and a probe that writes to the ledger it is being asked about is not a probe. The
# rc reaches its reader anyway: autonomy-sweep journals it as `ratchet_rc`, and jq is absent for both
# siblings at once, so the trigger's own damped page carries the news for the pair.
#
# THE STORE GUARD IS NOT CONVERTED WITH IT: a missing interpreter means the measurement never
# happened, a missing store means there was nothing to measure. 963dbd0a2 drew the same line.
[ -f "$BACKLOG" ] || { printf 'backlog-ratchet: no store at %s — nothing to measure\n' "$BACKLOG" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { printf 'backlog-ratchet: jq missing — CANNOT MEASURE (fail-closed, rc 2)\n' >&2; exit 2; }

# The FOLD, not the raw ledger: an item's current state is its last event, and `falsifier` is
# last-write-wins exactly as cc-premise reads it. Computing this from raw records would double-count
# every item that was ever touched twice.
read -r open_n probe_n fals_n closed_n median_age p75_age <<EOF
$(jq -rs '
  # fold: id -> {status, falsifier, source, first_ts, last_ts}
  (reduce .[] as $r ({};
     .[$r.id] //= {first: ($r.ts // ""), falsifier: "", source: "", status: "open"}
   | .[$r.id].last = ($r.ts // .[$r.id].last)
   | (if ($r.falsifier // "") != "" then .[$r.id].falsifier = $r.falsifier else . end)
   # LAST-NON-EMPTY-WINS, matching the falsifier arm above and cc-premise build_index. `source` is
   # written by `add` and carried forward, but a later record may restate it; an empty one never
   # erases a known class, because that would silently move a row back INTO the denominator.
   | (if ($r.source // "") != "" then .[$r.id].source = $r.source else . end)
   | (if ($r.event // "") == "done"  then .[$r.id].status = "done"
      elif ($r.event // "") == "block" then .[$r.id].status = "blocked"
      elif ($r.event // "") == "reopen" then .[$r.id].status = "open"
      elif ($r.event // "") == "claim"  then .[$r.id].status = "claimed"
      else . end)
  )) as $f
  | ([$f[] | select(.status == "open" or .status == "claimed")]) as $live
  # THE DENOMINATOR IS $probeable, NOT $live. `needs` rows are operator steps with no machine oracle
  # by design (their --run PERFORMS the step), so they can never carry a probe and their presence
  # only dilutes a firing-readiness number they are not part of. Measured 2026-08-11: 168 open
  # `needs` rows, exactly 1 dispatchable. Both counts are emitted so the exclusion is auditable
  # rather than a silent narrowing that flatters the ratio.
  | ([$live[] | select(.source != "needs")]) as $probeable
  | ([$probeable[] | select(.falsifier != "")]) as $covered
  | ([$f[] | select(.status == "done")
        | (((.last // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)
           - (.first // "" | if . == "" then 0 else (sub("\\..*Z$";"Z") | fromdateiso8601? // 0) end)) / 86400)
        | select(. >= 0)] | sort) as $ages
  | "\($live|length) \($probeable|length) \($covered|length) \($ages|length) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)/2|floor] * 10 | round / 10) end) \(if ($ages|length) == 0 then 0 else ($ages[($ages|length)*3/4|floor] * 10 | round / 10) end)"
' "$BACKLOG" 2>/dev/null || echo "0 0 0 0 0 0")
EOF

open_n=${open_n:-0}; probe_n=${probe_n:-0}; fals_n=${fals_n:-0}
closed_n=${closed_n:-0}; median_age=${median_age:-0}; p75_age=${p75_age:-0}

# EXECUTION — how many LIVE rows carry a currency stamp, i.e. have had a probe actually run against
# them. Counted over the same $live population the coverage ratio uses, so the two numbers are
# comparable rather than two ratios of two denominators (the defect READINESS measurement 3 retracted
# itself for). An ABSENT snapshot file means the currency pass has never run — reported as such, and
# never as zero rows validated out of zero, which would read as 100%.
# 🚨 THE DENOMINATOR IS NON-DONE, NOT `$live`, AND THE TWO ARE NOT THE SAME NUMBER. `$live` above is
# open ∨ claimed (346 today) and deliberately excludes BLOCKED rows; the currency pass stamps every
# row that is not `done` (564 today), blocked included, because a blocked row's premise decays like
# any other and `unblock` puts it straight back in the wave. Reusing `$live` here would have printed
# "346 rows, N never validated" beside a `cc-backlog freshness` reading 564 — two auditors over one
# population, disagreeing, with nothing on either to say which population it meant. Both counts are
# emitted so the gap is auditable rather than latent (memory:
# sibling-auditors-must-share-the-state-model, positive-control-the-denominator).
# ASKED OF cc-backlog, NEVER RE-DERIVED HERE. The first version of this block re-implemented the
# fold — copying the mini-reduce this file already uses for coverage — and it drifted IMMEDIATELY:
# it counted 553 non-done rows where `cc-backlog freshness` counted 564, an 11-row gap between two
# auditors over one population, each of which would have been quoted as "the" number. That is the
# defect this repo has now paid for three times (memory: sibling-auditors-must-share-the-state-model;
# and the coverage fold above is itself the surviving instance, kept only because it is load-bearing
# for the high-water mark's comparability). One arbiter per fact: cc-backlog owns the fold, so the
# ratchet asks it.
#
# FAIL-OPEN to UNKNOWN, never to zero. A missing helper, an unreadable store or a jq that is not
# there must report "not measured" — reporting 0 never-validated would be the strongest possible
# claim of health, produced by the sensor being broken (memory:
# sensor-default-off-makes-blindness-the-shipping-path).
validated_n=0; nondone_n=0; never_n=0; validated_src="absent"
# RESOLVE THE SYMLINK CHAIN FIRST, THEN DERIVE. `dirname "${BASH_SOURCE[0]}"/..` is wrong on the
# path this actually runs from: ~/.claude/scripts/ holds per-file SYMLINKS into the checkout, so
# through the live layer the `..` traversal lands on ~/.claude rather than the repo — and it does not
# fail, it silently reads the wrong tree. Caught by scripts/self-path-lint.sh at the land gate. The
# loop below is ship-land.sh's `_resolve_self` verbatim; no `readlink -f`, which is GNU-only and this
# box is BSD.
_rself="${BASH_SOURCE[0]}"
while [ -L "$_rself" ]; do
  _rdir="$(cd "$(dirname "$_rself")" && pwd)"
  _rself="$(readlink "$_rself")"
  case "$_rself" in /*) ;; *) _rself="$_rdir/$_rself" ;; esac
done
_cbin="${CC_RATCHET_BACKLOG_BIN:-$(cd "$(dirname "$_rself")/.." 2>/dev/null && pwd)/bin/cc-backlog}"
if [ -x "$_cbin" ] && command -v jq >/dev/null 2>&1; then
  _fresh="$("$_cbin" freshness --json 2>/dev/null)" || _fresh=""
  if [ -n "$_fresh" ]; then
    read -r nondone_n validated_n never_n <<EOF
$(printf '%s' "$_fresh" | jq -r '"\(.live) \(.validated) \(.never_validated)"' 2>/dev/null || echo "0 0 0")
EOF
    case "${nondone_n:-}"   in ''|*[!0-9]*) nondone_n=0   ;; esac
    case "${validated_n:-}" in ''|*[!0-9]*) validated_n=0 ;; esac
    case "${never_n:-}"     in ''|*[!0-9]*) never_n=0     ;; esac
    # PRESENT means the snapshot FILE exists — never inferred from a non-zero count, because zero
    # validated rows is a legitimate reading of a present-but-empty pass and must not read "absent".
    [ -f "$VALIDATED" ] && validated_src="present"
  fi
fi
# ── THE NUMERATOR IS ASKED, NOT RE-DERIVED (item e08ad9ab1ff6 — full account in the header) ──────
# The jq fold above still owns the LIVE population and the close-age percentiles. It no longer owns
# the numerator: counting `select(.falsifier != "")` sees only the STORED arm, while cc-premise
# `assess` composes three. ONE ARBITER PER FACT — the `freshness` block right above is this file
# already applying that rule, and coverage now follows it.
#
# FAIL-OPEN TO UNKNOWN, NEVER TO THE OLD NUMBER. If cc-premise cannot be asked, this does NOT fall
# back to the stored-only count: that number is systematically LOWER, so a silent fallback would
# compare a stored-only reading against a high-water mark recorded from the composed one and go RED
# on the sensor being broken rather than on the store regressing — a false alarm indistinguishable
# from the true one. Unmeasured coverage is reported as UNKNOWN and `--assert` declines to judge
# (memory: sensor-default-off-makes-blindness-the-shipping-path).
cov_src="premise"; cov_note=""
# The FOLD's own probeable count, kept before the arbiter's may replace it: the `needs`-exclusion
# line below is a statement about THIS file's fold and would go wrong (or negative) if it subtracted
# a denominator computed elsewhere.
fold_probe_n="$probe_n"
_pbin="${CC_RATCHET_PREMISE_BIN:-$(cd "$(dirname "$_rself")/.." 2>/dev/null && pwd)/bin/cc-premise}"
cov_arms=""; cov_gaps=""
if [ -x "$_pbin" ] && command -v jq >/dev/null 2>&1; then
  _cov="$("$_pbin" coverage --json 2>/dev/null)" || _cov=""
  if [ -n "$_cov" ]; then
    read -r p_probe p_cov <<EOF
$(printf '%s' "$_cov" | jq -r '"\(.probeable) \(.covered)"' 2>/dev/null || echo "x x")
EOF
    case "${p_probe:-}" in ''|*[!0-9]*) p_probe="" ;; esac
    case "${p_cov:-}"   in ''|*[!0-9]*) p_cov=""   ;; esac
    if [ -n "$p_probe" ] && [ -n "$p_cov" ]; then
      # BOTH denominators are kept and the divergence is PRINTED rather than reconciled silently —
      # the same positive control the `needs` exclusion earned (memory:
      # positive-control-the-denominator). The arbiter's denominator is the one the ratio uses.
      [ "$p_probe" -ne "$probe_n" ] && \
        cov_note=" · ⚠ denominator differs: ratchet fold ${probe_n}, cc-premise ${p_probe} (ratio uses cc-premise)"
      probe_n="$p_probe"; fals_n="$p_cov"
      cov_arms="$(printf '%s' "$_cov" | jq -r '"\(.by_arm.stored) stored · \(.by_arm["derived-plan"]) derived-plan · \(.by_arm["derived-postland"]) derived-postland"' 2>/dev/null || true)"
      # The generators actually missing a probe, largest gap first — so a RED names the producer to
      # fix instead of leaving the reader to find it, and so a derived-covered generator is never
      # mistaken for one.
      # TOP 3, AND IT SAYS SO WHEN IT TRUNCATES. A silent cap reads as "this is everything", which is
      # the same defect as postland-verify's FAILING[0] filing and as any bounded report that hides
      # its own bound — the tail generators would then be invisible precisely while someone worked
      # the list (memory: no-silent-caps).
      cov_gaps="$(printf '%s' "$_cov" | jq -r '
        [.by_source | to_entries[] | {s:.key, gap:(.value.total - .value.covered), t:.value.total}]
        | map(select(.gap > 0)) | sort_by(-.gap, .s) as $g
        | ($g | length) as $n
        | ($g | .[:3] | map("\(.s) (\(.gap) of \(.t))") | join(" · "))
          + (if $n > 3 then " · +\($n - 3) more generator(s) not shown" else "" end)' 2>/dev/null || true)"
    else
      cov_src="unknown"
    fi
  else
    cov_src="unknown"
  fi
else
  cov_src="unknown"
fi

if [ "$cov_src" = unknown ]; then
  coverage="0.0"
elif [ "$probe_n" -gt 0 ]; then
  coverage=$(awk -v a="$fals_n" -v b="$probe_n" 'BEGIN{printf "%.1f", (a*100)/b}')
else
  coverage="0.0"
fi

# DENOM_VERSION is bumped whenever WHAT IS COUNTED changes. v2 (2026-08-11) excluded the `needs`
# class from the denominator; v3 (2026-08-15) changed the NUMERATOR to the composed
# stored-or-derived count cc-premise owns. A mark recorded under an older version is a number about
# a different measurement, so comparing them would red or green for a reason unrelated to the
# store's health — v3 marks are strictly higher, so carrying a v2 mark forward would be harmless
# while carrying a v3 mark BACK would red forever.
DENOM_VERSION=3
MAX_HW="${CC_RATCHET_MAX_HW:-95.0}"
MIN_N="${CC_RATCHET_MIN_N:-20}"

prev="0.0"; prev_ver=1
if [ -f "$STATE" ]; then
  prev="$(jq -r '.coverage_high_water // "0.0"' "$STATE" 2>/dev/null || echo "0.0")"
  prev_ver="$(jq -r '.denominator_version // 1' "$STATE" 2>/dev/null || echo 1)"
fi
case "${prev_ver:-1}" in ''|*[!0-9]*) prev_ver=1 ;; esac

reset_note=""
if [ "$prev_ver" -ne "$DENOM_VERSION" ]; then
  # An EXPLICIT, dated reset — never a quiet re-baseline. The old mark measured a different
  # population, so carrying it forward would make every future verdict incomparable rather than
  # strict. This is the ONE path on which the mark may fall, and it announces itself.
  reset_note=" · denominator v${prev_ver}→v${DENOM_VERSION}: high-water RESET from ${prev}% (different population)"
  prev="0.0"
fi

# The high-water mark only ever RISES here. A fall is what --assert reports; recording the fall
# would silently re-baseline the ratchet to the regression, which is the one thing a ratchet exists
# to prevent.
#
# TWO GUARDS ON WHAT MAY LATCH, and this file died for want of both (see header, READINESS W0):
#   CEILING — a mark above MAX_HW makes GREEN unreachable, because ~103 live items are deliberately
#             unprobed and never will be. Latching 100% converted this ratchet into an alarm that
#             could only ever be red, for 3-of-3 of every verdict it ever journalled.
#   FLOOR   — a denominator under MIN_N is a degenerate read (a fixture, a half-written store, a
#             transient). 1-of-1 is 100% and must never become the fleet's standing target.
#   UNKNOWN — cc-premise could not be asked, so `coverage` is not a measurement at all. Latching it
#             would record 0.0% (or a stored-only reading) as the fleet's target and permanently
#             re-baseline the ratchet to a sensor failure, which is the one thing it must never do.
hw_block=""
if [ "$cov_src" = unknown ]; then
  hw_block="coverage NOT MEASURED (cc-premise unavailable)"
elif awk -v c="$coverage" -v m="$MAX_HW" 'BEGIN{exit !(c > m)}'; then
  hw_block="ceiling ${MAX_HW}%"
elif [ "$probe_n" -lt "$MIN_N" ]; then
  hw_block="denominator ${probe_n} < floor ${MIN_N}"
fi

if [ -n "$hw_block" ]; then
  prev_note="high-water ${prev}% (NOT raised — ${hw_block})${reset_note}"
elif awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c > p)}'; then
  mkdir -p "$(dirname "$STATE")" 2>/dev/null
  jq -nc --arg c "$coverage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson v "$DENOM_VERSION" \
     '{coverage_high_water:$c, denominator_version:$v, recorded:$ts}' > "$STATE" 2>/dev/null || true
  prev_note="high-water RAISED to ${coverage}%${reset_note}"
else
  # A version reset with no rise still has to PERSIST the new version, or every subsequent run
  # re-announces the reset and the stale v1 mark never actually leaves the file.
  if [ -n "$reset_note" ]; then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null
    jq -nc --arg c "$coverage" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson v "$DENOM_VERSION" \
       '{coverage_high_water:$c, denominator_version:$v, recorded:$ts}' > "$STATE" 2>/dev/null || true
  fi
  prev_note="high-water ${prev}% (unchanged)${reset_note}"
fi

case "$MODE" in
  json)
    jq -nc --arg open "$open_n" --arg probe "$probe_n" --arg cov "$coverage" --arg covered "$fals_n" \
       --arg closed "$closed_n" --arg med "$median_age" --arg p75 "$p75_age" --arg hw "$prev" \
       --arg valn "$validated_n" --arg nevn "$never_n" --arg vsrc "$validated_src" \
       --arg ndn "$nondone_n" --arg csrc "$cov_src" \
       --argjson dv "$DENOM_VERSION" \
       '{live_items:($open|tonumber), probeable_items:($probe|tonumber),
         falsifier_covered:($covered|tonumber),
         falsifier_coverage_pct:($cov|tonumber), closed_items:($closed|tonumber),
         median_days_to_close:($med|tonumber), p75_days_to_close:($p75|tonumber),
         non_done_items:($ndn|tonumber),
         validated_items:($valn|tonumber), never_validated_items:($nevn|tonumber),
         validation_snapshot:$vsrc,
         # "premise" = the composed stored-or-derived count cc-premise owns; "unknown" = the sensor
         # could not be asked, and then coverage_pct is NOT a measurement. A consumer must branch on
         # this rather than read 0.0 as a floor (memory: lookup-miss-is-not-absence).
         coverage_source:$csrc,
         coverage_high_water:($hw|tonumber), denominator_version:$dv}'
    ;;
  assert)
    if [ "$cov_src" = unknown ]; then
      # NOT a pass and not a fail — the sensor did not read. Exiting 0 keeps a broken helper from
      # starving the gate, and saying so keeps it from reading as health.
      printf 'backlog-ratchet: coverage NOT MEASURED — cc-premise could not be asked (%s). No verdict.\n' \
        "$_pbin" >&2
      exit 0
    fi
    printf 'backlog-ratchet: coverage %s%% (%s of %s probeable; %s live) · close median %sd p75 %sd over %s · %s\n' \
      "$coverage" "$fals_n" "$probe_n" "$open_n" "$median_age" "$p75_age" "$closed_n" "$prev_note"
    if awk -v c="$coverage" -v p="$prev" 'BEGIN{exit !(c < p)}'; then
      printf 'backlog-ratchet: RED — falsifier coverage FELL from %s%% to %s%%.\n' "$prev" "$coverage" >&2
      printf '  Items are being filed that cannot re-check themselves, so the store is going back\n' >&2
      printf '  to being believed rather than measured.\n' >&2
      # NAME THE GENERATOR. This line used to read "Add --falsifier to the generator that regressed"
      # and named none — so the reader had to go find it, and for the postland population the honest
      # answer was that no generator had regressed at all. cc-premise reports the gap per source;
      # a generator absent from this list is already covered (possibly by a DERIVED arm) and must
      # NOT be handed a stored probe.
      # No backticks in these format strings: shellcheck reads a backtick inside single quotes as an
      # unexpanded command substitution (SC2016) and the land gate treats that as RED — the same
      # constraint the census render below already carries.
      if [ -n "$cov_gaps" ]; then
        printf '  Uncovered rows by generator (fix these, largest first): %s\n' "$cov_gaps" >&2
        printf '  A generator NOT listed here is already covered — run cc-premise coverage before\n' >&2
        printf '  adding a stored probe, which would shadow a derived arm rather than add anything.\n' >&2
      else
        printf '  No generator has uncovered rows — the fall is a change of POPULATION, not of\n' >&2
        printf '  filing discipline. Compare cc-premise coverage against the recorded mark.\n' >&2
      fi
      exit 1
    fi
    ;;
  *)
    printf 'backlog-ratchet — the two standing numbers\n'
    if [ "$cov_src" = unknown ]; then
      printf '  falsifier coverage : UNKNOWN — cc-premise could not be asked at %s.\n' "$_pbin"
      printf '                       NOT reported as the stored-only count: that number is lower by\n'
      printf '                       construction and would read as a regression that never happened.\n'
    else
      printf '  falsifier coverage : %s%% (%s of %s probeable items can re-check themselves)\n' "$coverage" "$fals_n" "$probe_n"
      [ -n "$cov_arms" ] && printf '                       by arm: %s\n' "$cov_arms"
      [ -n "$cov_gaps" ] && printf '                       uncovered by generator: %s\n' "$cov_gaps"
    fi
    # No backticks in this format string: shellcheck reads a backtick inside single quotes as an
    # unexpanded command substitution (SC2016), and the land gate treats that as RED.
    printf '  denominator         : %s live minus %s needs-class (no machine oracle by design) = %s probeable\n' \
      "$open_n" "$((open_n - fold_probe_n))" "$fold_probe_n"
    [ -n "$cov_note" ] && printf '                       %s\n' "${cov_note# · }"
    printf '  days to close       : median %s · p75 %s (over %s closed items)\n' "$median_age" "$p75_age" "$closed_n"
    if [ "$validated_src" = absent ]; then
      printf '  probes ever RUN     : UNKNOWN — no currency snapshot at %s.\n' "$VALIDATED"
      printf '                        Coverage above says how many rows CAN self-check; nothing here\n'
      printf '                        has measured how many actually did (cc-premise sweep --record).\n'
    else
      printf '  probes ever RUN     : %s of %s NON-DONE rows validated · %s NEVER validated\n' \
        "$validated_n" "$nondone_n" "$never_n"
      printf '                        (non-done = %s, wider than the %s live above: it includes\n' \
        "$nondone_n" "$open_n"
      printf '                         blocked rows, whose premise decays the same and which unblock\n'
      printf '                         puts straight back in the wave)\n'
    fi
    printf '  %s\n' "$prev_note"
    # GUARDED ON cov_src, or it fires on the UNKNOWN path too — where coverage is 0.0 only because
    # nothing was measured, and this note would explain a real near-zero reading that does not exist.
    if [ "$cov_src" != unknown ] && awk -v c="$coverage" 'BEGIN{exit !(c < 1)}'; then
      printf '\n  Coverage is near zero. Generators DO emit probes now (and cc-premise derives one for\n'
      printf '  the plan-open and post-land RED classes), so a near-zero reading here is a real gap —\n'
      printf '  see the per-generator breakdown above for which producer to fix.\n'
    fi
    ;;
esac
exit 0
