#!/usr/bin/env bats
# BACKLOG FRESHNESS — a probe that CAN run is not a probe that HAS run.
#
# THE DEFECT THIS SUITE PINS. `run_falsifier` had exactly ONE call site — bin/cc-premise's claim
# path — so a row nobody ever tried to claim had never had its probe executed at all: 205 of 327
# live rows, measured 2026-08-12. Nothing anywhere recorded the difference, because there was no
# field for it, so `backlog-ratchet.sh` measured COVERAGE (a property of the row: can it self-check?)
# and a store could read 100% covered and 0% ever-executed and still print a clean bill of health.
# Age made it worse rather than better: the store's clock is DAYS and reads p50 2.0 for the same
# population the tree's clock reads p50 384 COMMITS, because this repo lands ~156 commits/day.
#
# WHAT IS ASSERTED HERE, and each is a BEHAVIOUR, never an internal:
#   · the stamp exists, falls as passes run, and is REFUSED when a pass would empty it
#   · decay is measured from FILING (firstTs), so a reopen cannot launder a stale row fresh
#   · an unreadable repo reports UNKNOWN, never zero
#   · a falsified row can be RETIRED, and a claimed one cannot
#   · `reopen` re-asks the premise and records it, which before this it never did
#
# ── RED-PROOF, MEASURED 2026-08-12 — read this before trusting a green board ─────────────────────
# The whole suite was replayed against the REAL pre-fix artifact (`git archive origin/main`, sha
# 53caadb3b), not against a hand-written approximation of it (memory:
# control-must-replay-the-real-artifact). Result: 18 of 21 RED.
#
# THE THREE THAT PASSED ON PRISTINE ARE CONTROLS, NOT HOLES, and each is named so nobody re-derives
# this. They cannot red on pristine BY CONSTRUCTION — pristine had no re-read on reopen at all, so
# "reopen is quiet" and "the re-read cannot refuse" are trivially true there. Their job is to fail on
# a FUTURE change, and each was proven able to (one mutant per SITE, memory:
# per-site-mutation-attributes-coverage):
#
#   mutant                                      kills          proves
#   reopen prints on every verdict              16             the ambient-alarm defect is fenced
#   arm reverts to unblock-only (literal)       15, 17         reopen really is in the arm
#   the re-read `||` becomes `return 9`         17, 19         a sensor cannot wedge a recovery path
#
# ⚠️ That third row is why case 19 tests THREE spellings of failure. Its first version fixtured only
# an ABSENT premise binary — which skips the block at `[ -x ]` and therefore never reaches the `||`
# that carries the exit code — so the `return 9` mutant survived it untouched and was caught only by
# case 17, a test about something else. A repro milder than the harness EXONERATES (memory:
# prescribed-repro-weaker-than-the-harness). 19 now also fixtures a binary that exits 3 (cc-premise's
# NORMAL blocking verdict, i.e. the common path) and one that exits 127.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  CP="$REPO/bin/cc-premise"
  # OWN $HOME before anything else: the stamp file, the IDL and the sweep marker all default under
  # it, and a suite that writes the operator's live ~/.claude/autonomy is a suite that can corrupt
  # the very census it is testing.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_VALIDATED="$BATS_TEST_TMPDIR/validated.json"
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/worktrees"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  # THE REPO IS A FIXTURE, not the checkout under test. The second clock is "how many commits landed
  # since this row was filed", so a suite reading the real repo would assert against a number that
  # changes every time somebody lands — the published-figure decay this repo has already been bitten
  # by (memory: published-figure-decays-with-its-source). A three-commit fixture makes the count
  # exact and stable.
  FIXREPO="$BATS_TEST_TMPDIR/fixrepo"; mkdir -p "$FIXREPO"
  git -C "$FIXREPO" init -q -b main
  git -C "$FIXREPO" config user.email t@t; git -C "$FIXREPO" config user.name t
  export CC_BACKLOG_REPO="$FIXREPO" CC_PREMISE_REPO="$FIXREPO"
}

# fixcommit <iso-ts> — one commit on the fixture repo at an exact committer time, so the
# commits-since-filing count below is arithmetic rather than a race with the wall clock.
fixcommit() {
  local ts="$1"
  echo "$ts" >> "$FIXREPO/log"
  git -C "$FIXREPO" add -A
  GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" git -C "$FIXREPO" commit -qm "c $ts"
}

# add_row <title> [falsifier] → the id of a row filed at an explicitly OLD timestamp.
#
# The ts is rewritten rather than taken from `now`, because every assertion about decay needs a
# filing time that PRECEDES the fixture commits. A row filed "now" is zero commits old by
# construction and could not distinguish a working counter from one wired to a constant.
add_row() {
  local title="$1" fals="${2:-}" id
  if [ -n "$fals" ]; then
    id="$("$CB" add --title "$title" --project probe --source test --falsifier "$fals")"
  else
    id="$("$CB" add --title "$title" --project probe --source test)"
  fi
  # Backdate the row's ONLY record. `add` writes one line; rewriting its ts in place is what makes
  # firstTs old, and it is done through jq so the record stays byte-valid JSON.
  local tmp="$BATS_TEST_TMPDIR/bl.tmp"
  jq -c --arg i "$id" 'if .id == $i then .ts = "2020-01-01T00:00:00Z" else . end' \
    "$CC_BACKLOG_FILE" > "$tmp" && mv "$tmp" "$CC_BACKLOG_FILE"
  printf '%s' "$id"
}

# ── THE STAMP ────────────────────────────────────────────────────────────────────────────────────

@test "1 a store nothing has validated reports EVERY live row as never-validated" {
  add_row "row one" >/dev/null
  add_row "row two" >/dev/null
  run "$CB" freshness --never
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "2 recording a pass makes the never-validated count FALL — the DoD's two readings" {
  local a b
  a="$(add_row "row one")"; b="$(add_row "row two")"
  run "$CB" freshness --never
  [ "$output" = "2" ]                       # reading 1
  printf '{"id":"%s","verdict":"clear"}\n' "$a" | "$CB" validated --batch --sha deadbeef
  run "$CB" freshness --never
  [ "$output" = "1" ]                       # reading 2 — falling
  printf '{"id":"%s","verdict":"clear"}\n{"id":"%s","verdict":"clear"}\n' "$a" "$b" \
    | "$CB" validated --batch --sha deadbeef
  run "$CB" freshness --never
  [ "$output" = "0" ]
}

@test "3 the recorded verdict and its trunk sha both survive into the census" {
  local a; a="$(add_row "row one")"
  printf '{"id":"%s","verdict":"falsified"}\n' "$a" | "$CB" validated --batch --sha cafe1234
  run "$CB" freshness --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.rows[0].validatedVerdict')" = "falsified" ]
  [ "$(printf '%s' "$output" | jq -r '.rows[0].validatedSha')" = "cafe1234" ]
}

@test "4 a batch matching NO known id is REFUSED and the previous snapshot stands" {
  # THE CATASTROPHIC READING THIS PREVENTS: an empty pipe (a crashed producer, a mis-set store path)
  # would otherwise write an empty snapshot, and every row would report as never-validated — which is
  # indistinguishable from the real finding this whole mechanism exists to report.
  local a; a="$(add_row "row one")"
  printf '{"id":"%s","verdict":"clear"}\n' "$a" | "$CB" validated --batch --sha aaa1111
  run "$CB" freshness --never
  [ "$output" = "0" ]
  run bash -c 'printf "{\"id\":\"nosuchrow0000\",\"verdict\":\"clear\"}\n" | "$0" validated --batch' "$CB"
  [ "$status" -eq 3 ]
  [[ "$output" == *"REFUSED"* ]]
  run "$CB" freshness --never
  [ "$output" = "0" ]                       # the good snapshot is still there
}

@test "5 an empty stdin is REFUSED for the same reason and writes nothing" {
  local a; a="$(add_row "row one")"
  printf '{"id":"%s","verdict":"clear"}\n' "$a" | "$CB" validated --batch --sha aaa1111
  run bash -c ': | "$0" validated --batch' "$CB"
  [ "$status" -eq 3 ]
  run "$CB" freshness --never
  [ "$output" = "0" ]
}

# ── THE SECOND CLOCK ─────────────────────────────────────────────────────────────────────────────

@test "6 decay is counted in COMMITS since filing, not in days" {
  local a; a="$(add_row "row one")"       # filed 2020-01-01
  fixcommit "2021-01-01T00:00:00Z"
  fixcommit "2021-01-02T00:00:00Z"
  fixcommit "2021-01-03T00:00:00Z"
  run "$CB" freshness --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.rows[0].commitsSinceFiling')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.commits_since_filing.p50')" = "3" ]
}

@test "7 a REOPEN does not launder a stale row fresh — the anchor is firstTs, not lastTs" {
  # THE BUG THIS PINS: `lastTs` is the last thing that HAPPENED to a row, so a reap, a self-release
  # or a routine reopen moves it. Anchoring decay there makes 374 machine reopens a day read as 374
  # rows filed today, and the store's oldest rows report as its newest.
  local a; a="$(add_row "row one")"
  fixcommit "2021-01-01T00:00:00Z"
  fixcommit "2021-01-02T00:00:00Z"
  "$CB" reopen "$a" --force >/dev/null 2>&1
  run "$CB" freshness --json
  [ "$(printf '%s' "$output" | jq -r '.rows[0].commitsSinceFiling')" = "2" ]
}

@test "8 an unreadable repo reports UNKNOWN, never zero commits of decay" {
  # A sensor that cannot be asked must SAY so. "0 commits since filing" is the strongest possible
  # claim of freshness and would be produced here by the repo simply not being there.
  add_row "row one" >/dev/null
  CC_BACKLOG_REPO="$BATS_TEST_TMPDIR/not-a-repo" run "$CB" freshness
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNKNOWN"* ]]
  [[ "$output" != *"p50 0"* ]]
  CC_BACKLOG_REPO="$BATS_TEST_TMPDIR/not-a-repo" run "$CB" freshness --json
  [ "$(printf '%s' "$output" | jq -r '.git_readable')" = "false" ]
  [ "$(printf '%s' "$output" | jq -r '.commits_since_filing')" = "null" ]
}

# ── THE PASS ─────────────────────────────────────────────────────────────────────────────────────

@test "9 sweep --record stamps a row whose probe RAN and said still-live, not just the dead ones" {
  # Recording only the interesting verdicts would leave the census unable to tell "checked, still
  # live" from "never checked" — which is the exact blindness the wave was filed for.
  add_row "still live" "exit 1" >/dev/null
  run python3 "$CP" sweep --record --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.validated_recorded')" = "1" ]
  run "$CB" freshness --never
  [ "$output" = "0" ]
}

@test "9b A ROW WITH NO PROBE IS NEVER STAMPED — the false-freshness trap this wave exists to avoid" {
  # 🚨 THE LOAD-BEARING CASE. `assess` returns `clear` both for "a probe ran and the condition is
  # still live" and for "there is no probe, so nothing was asked". Stamping the second would drive
  # never-validated to ZERO across a store where ~400 of 564 rows had had nothing run against them —
  # a metric that reports fresh forever and hides the staleness it was built to expose. That is not a
  # hypothetical: it is what happened to `lastTs` when a sibling wave rewrote 70% of the store in one
  # hour as link bookkeeping, and the decay p50 then read 8 commits against a true ~361.
  add_row "no probe at all"  >/dev/null
  add_row "also no probe"    >/dev/null
  add_row "this one is real" "exit 1" >/dev/null
  run python3 "$CP" sweep --record --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.assessed')" = "1" ]           # only the probed row
  [ "$(printf '%s' "$output" | jq -r '.unprobed')" = "2" ]           # and the gap is REPORTED
  [ "$(printf '%s' "$output" | jq -r '.validated_recorded')" = "1" ]
  run "$CB" freshness --never
  [ "$output" = "2" ]                                                # NOT zero
}

@test "10 sweep --close-falsified RETIRES a row a probe just proved dead" {
  # A falsified row REFUSES every claim and nothing closed it: permanently live, permanently
  # unfireable, consuming a dispatch consideration forever. 19 rows were in that state on the live
  # store when this landed.
  local dead; dead="$(add_row "dead row" "true")"
  run python3 "$CP" sweep --record --close-falsified 5 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" = "1" ]
  run "$CB" list --all --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$dead" '.[]|select(.id==$i)|.status')" = "done" ]
  [[ "$(printf '%s' "$output" | jq -r --arg i "$dead" '.[]|select(.id==$i)|.evidence')" == *"falsifier passed"* ]]
}

@test "11 a CLAIMED row is never auto-closed, however dead its probe reads" {
  # A claim means a worker is on it, and the probe may be answering about work that same worker has
  # just landed. Closing under it destroys the claim's audit trail.
  local dead; dead="$(add_row "dead but held" "true")"
  CC_BACKLOG_ELIGIBLE_GATE=off CC_BACKLOG_PREMISE_GATE=off \
    "$CB" claim "$dead" --by "someworker" --force >/dev/null 2>&1
  run python3 "$CP" sweep --record --close-falsified 5 --json
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" = "0" ]
  run "$CB" list --all --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$dead" '.[]|select(.id==$i)|.status')" = "claimed" ]
}

@test "12 the close cap BINDS and says so — a silent truncation reads as a clean store" {
  add_row "dead one"   "true" >/dev/null
  add_row "dead two"   "true" >/dev/null
  add_row "dead three" "true" >/dev/null
  run python3 "$CP" sweep --record --close-falsified 1 --json
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.close_skipped')" = "2" ]
}

@test "13 --close-falsified without a cap is rc 2, never an unbounded default" {
  # A flag whose DANGEROUS form is the shorter one is a trap: the bare spelling must not mean
  # "close everything".
  run python3 "$CP" sweep --close-falsified
  [ "$status" -eq 2 ]
  run python3 "$CP" sweep --close-falsified notanumber
  [ "$status" -eq 2 ]
}

@test "14 a sweep WITHOUT --record writes no stamp at all" {
  # The control for case 9: if the sweep stamped unconditionally, case 9 would pass over a subject
  # that ignored its own flag.
  add_row "row one" >/dev/null
  run python3 "$CP" sweep --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.validated_recorded')" = "0" ]
  run "$CB" freshness --never
  [ "$output" = "1" ]
}

# ── THE RE-ADMISSION RE-READ (item 5) ────────────────────────────────────────────────────────────

@test "15 REOPEN re-asks the premise — the re-admission path that ran no re-read at all" {
  # Measured 2026-08-12: 374 reopen events against 60 unblock events on the live rows. The guarded
  # verb was the rare one; the amnesia path was 6x its volume and ran no re-read at all.
  #
  # ASSERTED ON THE RE-READ FIRING, NOT ON A STAMP. An earlier version of this test asserted that
  # reopen made never-validated fall — i.e. that the transition WROTE a currency stamp. That was the
  # false-freshness bug in miniature and it is now forbidden: `cc-premise check` exits 0 both when a
  # probe ran and when the row has none, so a stamp written here would mark unprobed rows validated.
  # One producer writes the stamp (the sweep, which can see which arm fired); this verb re-ASKS and
  # surfaces. Case 17 is what proves the ask actually happened.
  local a; a="$(add_row "row one" "true")"
  run "$CB" reopen "$a" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"RE-READ ITS EVIDENCE"* ]]
}

@test "15b a re-admission writes NO currency stamp — a transition is not a measurement" {
  local a; a="$(add_row "row one" "exit 1")"
  run "$CB" freshness --never
  [ "$output" = "1" ]
  "$CB" reopen "$a" --force >/dev/null 2>&1
  "$CB" block "$a" --needs "something" >/dev/null 2>&1
  "$CB" unblock "$a" >/dev/null 2>&1
  run "$CB" freshness --never
  [ "$output" = "1" ]     # still never-validated: no probe result was RECORDED by a transition
}

@test "16 reopen stays SILENT on a clear verdict — 374 advisories a day is an ambient alarm" {
  local a; a="$(add_row "row one" "exit 1")"
  run "$CB" reopen "$a" --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"RE-READ ITS EVIDENCE"* ]]
}

@test "17 reopen SPEAKS when the premise is refuted — that is news, not noise" {
  local a; a="$(add_row "row one" "true")"
  run "$CB" reopen "$a" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"RE-READ ITS EVIDENCE"* ]]
  [[ "$output" == *"PREMISE IS REFUTED"* ]]
}

@test "18 unblock still speaks on a CLEAR verdict — the deliberate verb keeps its full contract" {
  # The control against over-narrowing: making reopen quiet must not make unblock quiet too, or the
  # change would have deleted a capability rather than added one.
  local a; a="$(add_row "row one" "exit 1")"
  "$CB" block "$a" --needs "operator must do something" >/dev/null 2>&1
  run "$CB" unblock "$a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RE-READ ITS EVIDENCE"* ]]
}

@test "19 the re-read cannot FAIL a reopen — a recovery path a sensor can refuse is a wedge" {
  # TWO FAILURE MODES, and the first version of this test only covered the harmless one. An ABSENT
  # binary skips the block entirely (`[ -x ]` is false), so it could never exercise the `||` that
  # actually carries the exit code — a mutant turning that `||` into `return 9` survived this test
  # untouched. The dangerous mode is a binary that EXISTS and exits NON-ZERO, which is cc-premise's
  # NORMAL blocking verdict (rc 3), i.e. the commonest path, not an edge case.
  # (memory: prescribed-repro-weaker-than-the-harness — a milder repro exonerates.)
  local a; a="$(add_row "row one" "true")"
  CC_BACKLOG_PREMISE_BIN="$BATS_TEST_TMPDIR/does-not-exist" run "$CB" reopen "$a" --force
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tail -1)" = "$a" ]

  local b; b="$(add_row "row two" "true")"
  printf '#!/bin/bash\necho "verdict=falsified"\necho "contract" >&2\nexit 3\n' \
    > "$BATS_TEST_TMPDIR/prem3"; chmod +x "$BATS_TEST_TMPDIR/prem3"
  CC_BACKLOG_PREMISE_BIN="$BATS_TEST_TMPDIR/prem3" run "$CB" reopen "$b" --force
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tail -1)" = "$b" ]

  # …and a binary that CRASHES outright. Same rule, third spelling.
  local c; c="$(add_row "row three" "true")"
  printf '#!/bin/bash\nexit 127\n' > "$BATS_TEST_TMPDIR/premcrash"; chmod +x "$BATS_TEST_TMPDIR/premcrash"
  CC_BACKLOG_PREMISE_BIN="$BATS_TEST_TMPDIR/premcrash" run "$CB" reopen "$c" --force
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tail -1)" = "$c" ]
}

# ── THE RATCHET'S THIRD NUMBER ───────────────────────────────────────────────────────────────────

@test "19b decay is also measured from the validated SHA, which no bookkeeping write can bump" {
  # The timestamp axis and the sha axis fail differently. A timestamp is refreshed by ANY writer —
  # which is how a link pass made 70% of the store read fresh — while a sha can only move when
  # somebody re-runs a probe. Both are published; this pins the second.
  local a; a="$(add_row "row one" "exit 1")"
  fixcommit "2021-01-01T00:00:00Z"
  local base; base="$(git -C "$FIXREPO" rev-parse --short HEAD)"
  printf '{"id":"%s","verdict":"clear"}\n' "$a" | "$CB" validated --batch --sha "$base"
  fixcommit "2021-01-02T00:00:00Z"
  fixcommit "2021-01-03T00:00:00Z"
  run "$CB" freshness --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.rows[0].commitsSinceValidation')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.commits_since_validation.p50')" = "2" ]
}

@test "19c an unresolvable validation sha reads UNKNOWN, never zero commits behind" {
  local a; a="$(add_row "row one" "exit 1")"
  fixcommit "2021-01-01T00:00:00Z"
  printf '{"id":"%s","verdict":"clear"}\n' "$a" | "$CB" validated --batch --sha 0000000
  run "$CB" freshness --json
  [ "$(printf '%s' "$output" | jq -r '.rows[0].commitsSinceValidation')" = "null" ]
  [ "$(printf '%s' "$output" | jq -r '.commits_since_validation')" = "null" ]
}

@test "20 the ratchet reports never-validated over the SAME population cc-backlog folds" {
  # Two auditors over one population must not disagree. The first version of the ratchet's block
  # re-implemented the fold and drifted by 11 rows immediately.
  add_row "row one" >/dev/null
  add_row "row two" >/dev/null
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/ratchet.json"
  run bash "$REPO/scripts/backlog-ratchet.sh" --json
  [ "$status" -eq 0 ]
  local nd nv fresh
  nd="$(printf '%s' "$output" | jq -r '.non_done_items')"
  nv="$(printf '%s' "$output" | jq -r '.never_validated_items')"
  fresh="$("$CB" freshness --never)"
  [ "$nd" = "2" ]
  [ "$nv" = "$fresh" ]
}

@test "21 no snapshot reports UNKNOWN, not a healthy zero" {
  add_row "row one" >/dev/null
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/ratchet.json"
  run bash "$REPO/scripts/backlog-ratchet.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"probes ever RUN"* ]]
  [[ "$output" == *"UNKNOWN"* ]]
  run bash "$REPO/scripts/backlog-ratchet.sh" --json
  [ "$(printf '%s' "$output" | jq -r '.validation_snapshot')" = "absent" ]
}
