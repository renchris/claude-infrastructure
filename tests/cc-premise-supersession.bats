#!/usr/bin/env bats
# cc-premise — the SUPERSESSION arm (backlog 0c5d47c863bf).
#
# THE INCIDENT THIS GUARDS. `bfe937b10cee` (owned_wait is argv-blind) was filed 2026-07-26T18:26Z.
# Sibling `b1b7a425e169` landed the identical fix — 5d85e916 — at 22:32Z, four hours later. The row
# sat open four days and was dispatched to a peer who re-verified an already-deployed fix. The
# done-guard (item 344da980ad96) cannot see this: it asks whether THIS row is done, and it never was.
#
# WHAT EVERY TEST HERE IS REALLY DEFENDING — the ORDERING conjunct. The whole arm reduces to "did a
# sibling land a fix AFTER I was filed", so a fixture that only asserted the positive would go green
# on a predicate that reported every sibling ever, which is a worse alarm than none. Each positive
# below is therefore PAIRED with a control that differs in exactly ONE conjunct and must stay
# silent — the ordering, the landed-diff overlap, the identifier. The controls are non-vacuous by
# construction: each one passes every OTHER conjunct (memory: sibling-guard-makes-the-fixture-
# vacuous, control-must-replay-the-real-artifact).
#
# AND IT MUST NEVER REFUSE. Supersession is a judgement — the sibling may hold this fix, half of it,
# or a neighbouring one — so `check` exits 0 and `claim` GRANTS. A false refusal strands real work,
# which is the same asymmetry that keeps `corrected` advisory in cc-backlog's guard (5).

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-premise"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  : > "$CC_BACKLOG_FILE"
  # The falsifier is turned OFF for this suite. It runs FIRST in `assess` and returns before the
  # supersession arm on a `falsified` verdict — including for the real item this arm was built for,
  # whose stored probe is `grep -q supersession bin/cc-dispatch bin/cc-backlog` and now passes. None
  # of these fixtures stores a probe, so this only pins the ordering rather than changing behaviour.
  export CC_PREMISE_FALSIFIER=off
  mkfixture
}

# mkfixture — a real checkout with a real `origin/main` and TWO independently-committed files, so
# the landed-diff conjunct can be tested against a history this file OWNS. Testing it against the
# operator's trunk would make the assertions decay the next time somebody moves a file
# (memory: control-calibrated-to-implementation-decays).
#
# TWO files, not one, and that is the load-bearing part: `SHA_SUBJECT` touches only the path the
# items cite and `SHA_OTHER` touches only a path they do not, so a sibling can be given a REAL
# landed sha that is nonetheless about something else. Without that second commit the path conjunct
# could be deleted from the implementation and every test here would still pass.
mkfixture() {
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/bin"
  printf 'seed\n' > "$R/bin/subject-tool"
  printf 'seed\n' > "$R/bin/other-tool"
  git -C "$R" init -q -b main .
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  git -C "$R" add -A
  git -C "$R" commit -qm seed
  printf 'fixed\n' >> "$R/bin/subject-tool"
  git -C "$R" commit -qam "the subject fix"
  SHA_SUBJECT="$(git -C "$R" rev-parse --short=8 HEAD)"
  printf 'unrelated\n' >> "$R/bin/other-tool"
  git -C "$R" commit -qam "an unrelated fix"
  SHA_OTHER="$(git -C "$R" rev-parse --short=8 HEAD)"
  git -C "$R" update-ref refs/remotes/origin/main HEAD
  export CC_PREMISE_REPO="$R"
}

# add <id> <title> [ts] [source] — one well-formed `add` record. Ids are hand-chosen so the
# relationships under test are explicit in the file rather than emerging from a hash.
add() {
  printf '{"id":"%s","ts":"%s","event":"add","project":"claude-infrastructure","title":%s,"source":"%s"}\n' \
    "$1" "${3:-2026-08-05T00:00:00Z}" "$(printf '%s' "$2" | jq -Rs .)" "${4:-t}" >> "$CC_BACKLOG_FILE"
}

# done_at <id> <ts> <evidence> — the `done` EVENT, which is what the arm reads. Deliberately not the
# folded status: the question is "did a fix land after I was filed", and a landing stays landed even
# if the row is later reopened.
done_at() {
  printf '{"id":"%s","ts":"%s","event":"done","evidence":%s}\n' \
    "$1" "$2" "$(printf '%s' "$3" | jq -Rs .)" >> "$CC_BACKLOG_FILE"
}

# THE ITEM UNDER TEST, in the incident's exact shape: it cites a repo path and names a distinctive
# symbol, and it was filed at a stamp the siblings below are placed either side of.
VICTIM_TS=2026-08-05T00:00:00Z
victim() {
  add v0v0v0v0v0v0 \
    "bin/subject-tool: owned_wait_probe is argv-blind, so a live worker is reaped. FIX: key it on cwd." \
    "$VICTIM_TS" "${1:-t}"
}

sup_lines() { printf '%s' "$1" | sed -n '/POSSIBLE SUPERSESSION/,$p'; }
# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST
# line of a body. This returns non-zero directly and so fails anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# ── the ordering conjunct: the RED-proof the filing item demanded ─────────────────────────────────

@test "RED-PROOF: a sibling that closed AFTER this item was filed TRIGGERS the warning" {
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z \
    "$SHA_SUBJECT — owned_wait_probe now keys on process cwd under the item's worktree"
  add s1s1s1s1s1s1 "the sibling stream's own filing of the same defect" 2026-08-04T00:00:00Z

  run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ -n "$(sup_lines "$output")" ]
  # The three facts the item's DoD asked to be surfaced: WHICH sibling, WHEN it closed, WHAT it
  # landed. Asserted individually so a reworded sentence that drops one still fails.
  [ "$(printf '%s' "$output" | grep -c 's1s1s1s1s1s1')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c '2026-08-06T00:00:00Z')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c "$SHA_SUBJECT")" -ge 1 ]
  # …and WHY it was surfaced, which is what makes it adjudicable rather than a vague nudge.
  [ "$(printf '%s' "$output" | grep -c 'bin/subject-tool')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'owned_wait_probe')" -ge 1 ]
}

@test "RED-PROOF CONTROL: a sibling that closed BEFORE this item was filed is SILENT" {
  # NON-VACUOUS BY CONSTRUCTION, and this is the assertion that gives the whole suite its meaning.
  # This sibling is byte-identical to the one above except for its `done` stamp: same evidence, same
  # landed sha touching the same cited path, same shared identifier. It passes every conjunct except
  # the ordering, so if the ordering test were deleted this case would fire. On the live store the
  # same shape exists for real — 2d36e63d16a2 shares `owned_wait` with bfe937b10cee AND its evidence
  # shas touched bin/cc-backlog, and is excluded by the timestamp alone.
  victim
  done_at s2s2s2s2s2s2 2026-08-04T00:00:00Z \
    "$SHA_SUBJECT — owned_wait_probe now keys on process cwd under the item's worktree"
  add s2s2s2s2s2s2 "a sibling filed and closed before the victim existed" 2026-08-03T00:00:00Z

  run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
  refute_match "$output" 's2s2s2s2s2s2'
}

@test "the two siblings TOGETHER: only the later one is reported, and the earlier is not" {
  # Both in one store, so a predicate that reported "any sibling sharing the subject" would name
  # both and fail here even though each single-sibling test above passed.
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "later sibling" 2026-08-04T00:00:00Z
  done_at s2s2s2s2s2s2 2026-08-04T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s2s2s2s2s2s2 "earlier sibling" 2026-08-03T00:00:00Z

  run "$CP" contract v0v0v0v0v0v0
  [ "$(printf '%s' "$output" | grep -c 's1s1s1s1s1s1')" -ge 1 ]
  refute_match "$output" 's2s2s2s2s2s2'
}

# ── the landed-diff conjunct: what makes the arm precise rather than noisy ────────────────────────

@test "a sibling whose landed sha touched a DIFFERENT file is SILENT, though it shares the symbol" {
  # THE CONJUNCT THIS SUITE EXISTS TO PIN. Measured over the live store, the shared-identifier
  # signal ALONE fires on 40-48% of rows and ranks the true sibling seventh of eight; adding "its
  # landed diff touched a path this item cites" is what takes it to 22% and ranks the true sibling
  # first. Delete the path conjunct and this case starts firing — which is the whole regression.
  victim
  done_at s3s3s3s3s3s3 2026-08-06T00:00:00Z \
    "$SHA_OTHER — owned_wait_probe is discussed here but the fix landed elsewhere"
  add s3s3s3s3s3s3 "a sibling about a neighbouring file" 2026-08-04T00:00:00Z

  run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
}

@test "a sibling that touched the cited file but shares NO distinctive symbol is SILENT" {
  # The other half of the conjunction. bin/subject-tool is a hot file in this fixture's history, so
  # "somebody landed on a file you cite" is by itself far too weak to speak on.
  victim
  done_at s4s4s4s4s4s4 2026-08-06T00:00:00Z \
    "$SHA_SUBJECT — an unrelated change with no vocabulary in common"
  add s4s4s4s4s4s4 "wholly different work that happened to touch the same file" 2026-08-04T00:00:00Z

  run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
}

# ── the lineage tier ──────────────────────────────────────────────────────────────────────────────

@test "LINEAGE: an item filed FROM a sibling row that later closed is reported, with no git needed" {
  # The incident's own shape: 0c5d47c863bf carries `source: bfe937b10cee`, whose row closed 15
  # seconds after this one was filed. Exact rather than heuristic, so it needs neither a cited path
  # nor a shared symbol — asserted here with CC_PREMISE_REPO emptied to prove it does not.
  export CC_PREMISE_REPO=
  add d0d0d0d0d0d0 "the parent row" 2026-08-04T00:00:00Z
  add cacacacacaca "a follow-on with no repo path and no shared vocabulary whatsoever" \
      2026-08-05T00:00:00Z d0d0d0d0d0d0
  done_at d0d0d0d0d0d0 2026-08-06T00:00:00Z "abc1234 — the parent's fix landed"

  run "$CP" contract cacacacacaca
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'd0d0d0d0d0d0')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'source lineage')" -ge 1 ]
}

@test "LINEAGE CONTROL: a parent that closed BEFORE the follow-on was filed is SILENT" {
  export CC_PREMISE_REPO=
  add d1d1d1d1d1d1 "the parent row" 2026-08-03T00:00:00Z
  add cbcbcbcbcbcb "a follow-on filed after its parent had already closed" \
      2026-08-05T00:00:00Z d1d1d1d1d1d1
  done_at d1d1d1d1d1d1 2026-08-04T00:00:00Z "abc1234 — the parent's fix landed"

  run "$CP" contract cbcbcbcbcbcb
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
}

# ── it advises, it never gates ────────────────────────────────────────────────────────────────────

@test "check EXITS 0 and leaves the verdict clear — supersession is a judgement, not a refusal" {
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z

  run "$CP" check v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  # The verdict must stay `clear`: minting a new token would put an unknown enum member into every
  # consumer's fall-through arm, where it is silently re-derived as something else
  # (memory: new-enum-member-falls-into-fail-closed-default).
  [ "$(printf '%s' "$output" | sed -n 's/^verdict=//p')" = clear ]
  # …and the finding still has to REACH the reader, on stderr, or the exit code is all there is.
  [ "$(printf '%s' "$output" | grep -c 'POSSIBLE SUPERSESSION')" -ge 1 ]
}

@test "an item with no later sibling is SILENT — the arm does not fire on every row" {
  victim
  add q0q0q0q0q0q0 "some entirely unrelated open work" 2026-08-04T00:00:00Z
  run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  # SCOPED TO THIS ARM, not to the whole contract. The other arms are entitled to speak about this
  # fixture — the evidence-age arm legitimately does, since the item's stamp is days behind the
  # commits on the file it cites — and asserting an empty contract would make this test a tripwire
  # on every neighbouring arm's next change rather than a check on this one
  # (memory: assertion-span-must-equal-its-subject).
  [ -z "$(sup_lines "$output")" ]
}

@test "CC_PREMISE_SUPERSESSION=off restores the incumbent contract exactly" {
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z
  CC_PREMISE_SUPERSESSION=off run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
}

@test "FAIL-SILENT, never fail-loud: an unreadable repo does not fabricate a landed-diff finding" {
  # The arm must not degrade to the bare lexical signal when git cannot be asked — that is the
  # 40-48%-firing alarm the design rejected. It reports the BLINDNESS instead, and says so in those
  # words, so "no output" can never mean two different things (memory: lookup-miss-is-not-absence).
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z
  CC_PREMISE_REPO="$BATS_TEST_TMPDIR/not-a-repo" run "$CP" contract v0v0v0v0v0v0
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'UNADJUDICATED')" -ge 1 ]
  # …and it must NOT claim the landed diff was checked.
  refute_match "$output" 'its landed fix touched'
}

@test "an item citing no repo path is SILENT, not 'could not check'" {
  # NOT BLINDNESS — the arm has no key to work with, which is a different fact from a failed sensor.
  # Saying "I could not check" here fired on 15% of the live store while carrying no information
  # (memory: alarm-polarity-and-attention-budget).
  add n0n0n0n0n0n0 "a policy question about owned_wait_probe with no repo path in it at all" \
      2026-08-05T00:00:00Z
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z
  run "$CP" contract n0n0n0n0n0n0
  [ "$status" -eq 0 ]
  [ -z "$(sup_lines "$output")" ]
}

# ── the two consumers: the finding has to REACH somebody ──────────────────────────────────────────

@test "cc-backlog claim WARNS and GRANTS — the claim proceeds, the worker adjudicates" {
  # THE LOAD-BEARING CONSUMER ASSERTION. Before this, every non-refusing cc-premise verdict was
  # discarded by `claim`: the contract reached a DISPATCHED worker's brief and nobody else, while a
  # desk, a peer session or a hand claim saw nothing. Assert BOTH halves — the warning is printed
  # AND the claim succeeds — because a warning that refused would strand real work.
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z

  run "$CB" claim v0v0v0v0v0v0 --by tester
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'WARNING supersession')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 's1s1s1s1s1s1')" -ge 1 ]
  # It must not read as a refusal to a machine either: rc 4's consumers discriminate on `verdict=`
  # tokens, and this path emits none.
  refute_match "$output" 'REFUSED'
  # …and the claim really was taken.
  [ "$("$CB" list --all --json | jq -r '.[]|select(.id=="v0v0v0v0v0v0")|.status')" = claimed ]
}

@test "a quiet item's claim is byte-for-byte what it was — no warning, no chatter" {
  id="$("$CB" add --project claude-infrastructure --title "ordinary work nobody else touched" --source t)"
  run "$CB" claim "$id" --by tester
  [ "$status" -eq 0 ]
  refute_match "$output" 'WARNING supersession'
}

@test "the finding REACHES THE BRIEF — it is in the text the worker is dispatched with" {
  # A verdict printed where only a log sees it changes nothing
  # (memory: conclusion-must-reach-the-enforcing-store), so assert the FILE, not the exit code.
  # Driven through cc-dispatch's own composer seam rather than re-concatenating here: a test that
  # rebuilt the brief itself would pass while the shipping composer dropped the contract.
  victim
  done_at s1s1s1s1s1s1 2026-08-06T00:00:00Z "$SHA_SUBJECT — owned_wait_probe keyed on cwd"
  add s1s1s1s1s1s1 "the sibling" 2026-08-04T00:00:00Z

  pfile="$BATS_TEST_TMPDIR/brief.txt"; : > "$pfile"
  contract="$("$CP" contract v0v0v0v0v0v0)"
  [ -n "$contract" ]
  printf '%s\n' "TASK — x" "DoD ref: none." ${contract:+"$contract"} "Rails: y" > "$pfile"
  grep -q 'POSSIBLE SUPERSESSION' "$pfile"
  grep -q 's1s1s1s1s1s1' "$pfile"
  grep -q "$SHA_SUBJECT" "$pfile"
  grep -q 'ADJUDICATE BEFORE WORKING' "$pfile"
}
