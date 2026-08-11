#!/usr/bin/env bats
# cc-premise — the claim-time premise check (CONCURRENCY_PROGRAM.md §S3).
#
# WHAT THIS FILE IS REALLY GUARDING. The predicate's first cut matched "a refuting verb within 120
# chars of the id" and, against the live store, produced 370 hits where 24 were real — it convicted
# an OPEN item (tmux debug logging) of being superseded by an item about pane visibility. Every
# refusal assertion below is therefore PAIRED with a near-miss control that must NOT refuse: a bare
# citation, a `wt-<id>` worktree path, an `UN-RETRACTS`, a correction filed before its target. A
# suite that only asserted the positives would go green on a predicate that refuses everything, and
# refusing everything is precisely the failure mode that matters here — these items are real work
# and a false refusal strands it (memory: control-must-replay-the-real-artifact, alarm-polarity).
#
# The DIRECTION tests (self-duplicate) are the other half. "DUPLICATE of X" says the SPEAKER is
# redundant and X is canonical; reading it the other way round would refuse claims on exactly the
# live item that should be worked. Both directions are asserted in the same test so an inversion
# cannot pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-premise"
  CB="$REPO/bin/cc-backlog"
  # $HOME first: cc-premise defaults its store under $HOME, so an unfixtured suite would read the
  # operator's live ledger and its verdicts would depend on whatever the desk is doing. The explicit
  # CC_BACKLOG_FILE is kept alongside it deliberately — it says WHICH store this suite means, so a
  # default that later moves out from under $HOME cannot silently un-fixture the file
  # (memory: unfixtured-sensor-executes-the-deployed-subject).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # CC_PREMISE_REPO is pinned EXPLICITLY EMPTY, not unset. An unset variable now defaults to
  # cc-premise's own checkout — that default is what makes the git arms run in production, where no
  # caller exports the variable — and a suite reading a real repo would make these verdicts depend
  # on that repo's history. Empty is the explicit "no repo" that keeps the refutation tests
  # hermetic. The git arms are exercised below against a fixture repo this suite builds and owns.
  export CC_PREMISE_REPO=
  : > "$CC_BACKLOG_FILE"
}

# mkrepo — a fixture checkout with a real `origin/main`, so the git arms can be tested against a
# history this file OWNS. Testing them against the operator's trunk would make the assertions decay
# the next time somebody moves a file (memory: control-calibrated-to-implementation-decays).
mkrepo() {
  local r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r/tests" "$r/bin"
  printf 'x\n' > "$r/tests/deploy-parity.bats"
  git -C "$r" init -q -b main .
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
  git -C "$r" add -A
  git -C "$r" commit -qm seed
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$r"
}

# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. These return non-zero directly and so fail anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# add <id> <title> — one well-formed `add` record. Ids are hand-chosen so the relationships under
# test are explicit in the file rather than emerging from a hash.
add() { printf '{"id":"%s","ts":"%s","event":"add","project":"claude-infrastructure","title":%s,"source":"t"}\n' \
          "$1" "${3:-2026-08-01T00:00:00Z}" "$(printf '%s' "$2" | jq -Rs .)" >> "$CC_BACKLOG_FILE"; }

verdict() { printf '%s' "$1" | sed -n 's/^verdict=//p'; }

# A stamp strictly AFTER cc-backlog's own `now`, seeded RELATIVE to the clock rather than written
# down. The claim-side tests pair a real `seed_claimable` (which the shipping verb stamps at now)
# with a hand-written corrector, and `find_correctors` requires the corrector to be dated at or
# after its target — so the corrector needs a future stamp to be reachable at all.
#
# A hardcoded one satisfies that only until the clock arrives: `2026-08-09T00:00:00Z` was written
# here, and on 2026-08-09 all four of those tests would have flipped RED with no code change, the
# fixture having silently reversed its own meaning. `ship-land.sh`'s wall-clock ratchet caught it at
# the gate. The `+` in `-v+2d` is load-bearing: bare `date -v 2d` SETS the day rather than adding.
future_ts() { date -u -v+2d +%Y-%m-%dT%H:%M:%SZ; }

# ── the predicate ────────────────────────────────────────────────────────────────────────────────

@test "an item nothing refers to is clear, and does not block" {
  add aaaaaaaaaaaa "plain work item, nobody has corrected it"
  run "$CP" check aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "SUPERSEDES <id> refuses (exit 3) — and a bare CITATION of the same id does not" {
  add bbbbbbbbbbbb "the original claim about rung 6"                     2026-08-01T00:00:00Z
  add cccccccccccc "SUPERSEDES bbbbbbbbbbbb — its remedy is refuted"     2026-08-02T00:00:00Z
  run "$CP" check bbbbbbbbbbbb
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = superseded ]
  # THE CONTROL, and it must carry a COMPETING VERB or it proves nothing. The measured live defect
  # was not "an id with no verb near it" — it was a composed status note whose refuting verb governs
  # a DIFFERENT id in the same sentence, which a proximity window hands to every id present. This
  # fixture is that shape verbatim (after 9ff11a116387 → da18f179ac50): a real `SUPERSEDES` aimed at
  # one id, and a bare citation of ours 40 chars later. A window predicate refuses both; a directed
  # one refuses only the id the verb actually takes as its object.
  add dddddddddddd "SUPERSEDES 999999999999 — root cause already filed+BLOCKED as eeeeeeeeeeee, this item is the independently-fixable CONSEQUENCE" 2026-08-02T00:00:00Z
  add eeeeeeeeeeee "the root cause item"                                  2026-08-01T00:00:00Z
  run "$CP" check eeeeeeeeeeee
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "a CORRECTION of one sub-claim ADVISES but never blocks — the item still holds live work" {
  # §S3's flagship case (23eccae755a9): one refuted sub-claim, a live regression beside it.
  # Refusing here would strand the work the item exists to do, so `corrected` must exit 0 AND
  # must still hand the reader the disproof.
  add 111111111111 "auth-error rate regressed 20x; separately 2.1.220 is 3.4x worse" 2026-08-01T00:00:00Z
  add 222222222222 "CORRECTION to backlog item 111111111111: the 3.4x claim is FALSE — time-confounded" 2026-08-02T00:00:00Z
  run "$CP" check 111111111111
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = corrected ]
  printf '%s' "$output" | grep -q "222222222222"
  printf '%s' "$output" | grep -q "DISPROOF IS THE DELIVERABLE"
}

@test "DUPLICATE names the SPEAKER as redundant, never the target — both directions asserted" {
  add 333333333333 "post-land RED: tests/deploy-parity.bats @ aae7e801677a"                  2026-08-01T00:00:00Z
  add 444444444444 "post-land RED: tests/deploy-parity.bats @ 469e65402ce3 DUPLICATE of blocked 333333333333 — STAND DOWN" 2026-08-02T00:00:00Z
  # the SPEAKER is the stale one
  run "$CP" check 444444444444
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = self-duplicate ]
  printf '%s' "$output" | grep -q "333333333333"
  # …and the TARGET is canonical and must stay claimable. An inverted reading refuses this one,
  # which would block the only item actually holding the work.
  #
  # ASSERTED AS `clear`, not as "not superseded". The weaker pair of refutes used to pass while this
  # fixture's own verdict was `suspect` — the path arm was fabricating "tests/deploy-parity.bats is
  # not on origin/main" about a file that has never moved, and an assertion that only names the two
  # blocking verdicts cannot see a third one appear (memory: assertion-span-must-equal-its-subject).
  run "$CP" check 333333333333
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "wt-<id> is a WORKTREE PATH, not a reference to the item" {
  # Shape of the live false positive (191d1fc4143c → 21c6b3ab5532, an OPEN item): a refuting verb
  # aimed at one id, and our id appearing only as the worktree the work happened IN.
  add 555555555555 "tmux server running with DEBUG LOGGING"                          2026-08-01T00:00:00Z
  add 666666666666 "SUPERSEDES 878787878787 — self-close has a second blocker. VERIFIED in reso wt-555555555555, pane D2AD" 2026-08-02T00:00:00Z
  run "$CP" check 555555555555
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  # ISOLATING THE wt- GUARD ITSELF. The directed matcher alone already rejects the line above (no
  # filler joins `wt-` to a verb), so that assertion would stay green with the guard deleted and
  # would be claiming coverage it does not have. The id→predicate direction is where the guard is
  # the ONLY thing standing: a worktree path followed by a refuting predicate.
  add 565656565656 "worker item"                                                     2026-08-01T00:00:00Z
  add 676767676767 "ran in wt-565656565656 which was WRONG about the ceiling"        2026-08-02T00:00:00Z
  run "$CP" check 565656565656
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=superseded"
}

@test "UN-RETRACTS is not RETRACTS — a negated verb must not refuse" {
  add 777777777777 "the original kitty finding"                             2026-08-01T00:00:00Z
  add 888888888888 "THIS PARTIALLY UN-RETRACTS 777777777777: its conclusion is correct" 2026-08-02T00:00:00Z
  run "$CP" check 777777777777
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=superseded"
}

@test "a correction cannot precede its subject — an earlier item never refutes a later one" {
  add 999999999999 "SUPERSEDES abcabcabcabc"       2026-08-01T00:00:00Z
  add abcabcabcabc "filed AFTER the text above"    2026-08-05T00:00:00Z
  run "$CP" check abcabcabcabc
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "a refutation is dated by the EVENT that wrote it, not by its author's add order" {
  # Measured: 6 of 64 correctors in the live store were ADDED BEFORE their target — the refuting
  # sentence arrived later, in a `done`/`block` event on an older item. An ordering test keyed on
  # add-time drops all six. The corrector below is older than its target by four days; only the
  # per-record timestamp makes this reachable.
  add 0a0a0a0a0a0a "an older item, filed first"        2026-08-01T00:00:00Z
  add 0b0b0b0b0b0b "the target, filed later"           2026-08-05T00:00:00Z
  printf '{"id":"0a0a0a0a0a0a","ts":"2026-08-06T00:00:00Z","event":"done","evidence":"SUPERSEDES 0b0b0b0b0b0b — measured and refuted"}\n' >> "$CC_BACKLOG_FILE"
  run "$CP" check 0b0b0b0b0b0b
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = superseded ]
  # THE CONTROL for the same seam: text written BEFORE the target existed still cannot refute it,
  # or the ordering test has simply been deleted rather than corrected.
  add 0c0c0c0c0c0c "SUPERSEDES 0d0d0d0d0d0d"           2026-08-01T00:00:00Z
  add 0d0d0d0d0d0d "filed after that text was written" 2026-08-05T00:00:00Z
  run "$CP" check 0d0d0d0d0d0d
  [ "$status" -eq 0 ]
}

# ── the git arms (cited paths / shas) ────────────────────────────────────────────────────────────

@test "the path arm convicts a genuinely ABSENT path and stays silent on a PRESENT one" {
  # assigned before export: `export X="$(cmd)"` makes the exit status that of `export`, hiding a
  # failed mkrepo behind a green line (SC2155) — and a silently empty repo would disable the very
  # arm this test exists to exercise.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "fix tests/deploy-parity.bats — it is red"   2026-08-01T00:00:00Z
  add 2b2b2b2b2b2b "fix bin/no-such-tool-at-all — it is red"    2026-08-01T00:00:00Z
  # PRESENT on the fixture's trunk ⇒ silence. This is verbatim the sentence the shipping code
  # fabricated for 80 live items.
  run "$CP" check 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  # ABSENT ⇒ the arm must still speak. Without this half, the fail-open fix below could equally
  # have been "delete the arm" and the suite would go green on a sensor that reports nothing at all
  # (memory: per-site-mutation-attributes-coverage).
  run "$CP" check 2b2b2b2b2b2b
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "no-such-tool-at-all"
  # …and `suspect` ADVISES, never refuses: a dead pointer is not a dead premise (this repo lands by
  # rebase, so 45 of 61 non-ancestor shas have a patch-id twin already on trunk).
  refute_match "$output" "verdict=superseded"
}

@test "FAIL-OPEN: a repo that cannot ANSWER reports nothing — 'could not ask' is never 'absent'" {
  # THE MEASURED DEFECT, and the reason it shipped invisibly. `_git` returns None both for "git
  # answered: absent" and for "git could not be asked", and the path arm read both as absent — so
  # with no readable repo it convicted every cited path containing a slash: 156 `suspect` items
  # against a true 76, i.e. 80 false sentences riding real workers' briefs. Neither cc-backlog nor
  # cc-dispatch sets CC_PREMISE_REPO, so that WAS the shipping configuration.
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo"
  add 1a1a1a1a1a1a "fix tests/deploy-parity.bats — it is red" 2026-08-01T00:00:00Z
  for bad in "" "$BATS_TEST_TMPDIR/not-a-repo" "$BATS_TEST_TMPDIR/does-not-exist-at-all"; do
    CC_PREMISE_REPO="$bad" run "$CP" check 1a1a1a1a1a1a
    [ "$status" -eq 0 ]
    [ "$(verdict "$output")" = clear ]
    refute_match "$output" "not at that location"
  done
}

@test "a bare basename is not convicted just because it is not at the repo ROOT" {
  # `deploy-live.sh` lives at `scripts/deploy-live.sh`; resolving it as a root path fails and reports
  # a live file as missing. The basename fallback is what stops that, and it needs the git arm ON to
  # be reachable at all — under the old unset default this path was never executed by any test.
  r="$(mkrepo)"
  mkdir -p "$r/scripts" && printf 'x\n' > "$r/scripts/deploy-live.sh"
  git -C "$r" add -A && git -C "$r" commit -qm add-script
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  export CC_PREMISE_REPO="$r"
  add 3c3c3c3c3c3c "the converger deploy-live.sh refuses" 2026-08-01T00:00:00Z
  run "$CP" check 3c3c3c3c3c3c
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "a UUID is not two shas — a session id does not read as a dead pointer" {
  # THE MEASURED DEFECT. `\b[0-9a-f]{7,40}\b` shreds `7868b45e-ce67-4ac1-a8dd-0bc670bf7fa6` at the
  # hyphens into `7868b45e` and `0bc670bf7fa6`, and both were announced as absent commits — on the
  # very item filed to report it. A transcript under ~/.claude-tertiary/ is absent from git BY
  # CONSTRUCTION, so this is a finding that can never be anything but false.
  r="$(mkrepo)"; export CC_PREMISE_REPO="$r"
  add 4d4d4d4d4d4d "measured on session 7868b45e-ce67-4ac1-a8dd-0bc670bf7fa6 (6.2MB transcript)"
  run "$CP" check 4d4d4d4d4d4d
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "7868b45e"
  refute_match "$output" "0bc670bf7fa6"
}

@test "a naming word BOUND to the token suppresses it — an unbound twin still speaks" {
  # The fragment cited alone, which the UUID test cannot reach: item 311062ef8e9a's body says
  # "MEASURED on sid 7868b45e" with no UUID anywhere. Only the bound noun discriminates.
  r="$(mkrepo)"; export CC_PREMISE_REPO="$r"
  add 5e5e5e5e5e5e "MEASURED on sid 7868b45e: the oracle is per-SESSION"
  run "$CP" check 5e5e5e5e5e5e
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  # THE PAIRED CONTROL, and it is the half that matters. Suppression sized to "any 8-hex token
  # looks like an id" would silence the arm entirely, and this suite would go green on a sensor
  # that reports nothing (memory: per-site-mutation-attributes-coverage). The SAME token, unbound,
  # must still be resolved and still be convicted.
  add 6f6f6f6f6f6f "the fix in 7868b45e was reverted"
  run "$CP" check 6f6f6f6f6f6f
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "7868b45e"
}

@test "a token with no git word is HEDGED, not called a sha — and one with a git word is not" {
  # The false signal this arm was reported for is the WORD "SHA": the advice that follows was
  # generically correct, but it points a worker at "premise refuted" for evidence that was never
  # in git. What cannot be classified must concede it, and 75 of 182 live findings are that case.
  r="$(mkrepo)"; export CC_PREMISE_REPO="$r"
  add 7a7a7a7a7a7a "run-control=1d9a6a21 came back red"
  run "$CP" check 7a7a7a7a7a7a
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "CITED HEX TOKEN 1d9a6a21"
  printf '%s' "$output" | grep -q "IGNORE THIS LINE"
  # …and the confident wording is still REACHABLE. Without this half the fix could equally have
  # been "hedge everything", which throws away the arm's signal on a real dead pointer.
  add 8b8b8b8b8b8b "the commit 1d9a6a21 never landed"
  run "$CP" check 8b8b8b8b8b8b
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "CITED SHA 1d9a6a21"
  refute_match "$output" "CITED HEX TOKEN"
  # BOTH wordings keep the rebase advice — it was correct before this change and is unaffected.
  printf '%s' "$output" | grep -q "lands by REBASE"
}

@test "FAIL-OPEN: an unreadable store answers unknown and exits 0, never blocks" {
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/does-not-exist.jsonl"
  run "$CP" check aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = unknown ]
}

@test "FAIL-OPEN: a malformed ledger line is skipped, not fatal" {
  printf 'not json at all\n' >> "$CC_BACKLOG_FILE"
  add bbbbbbbbbbbb "the original"                        2026-08-01T00:00:00Z
  add cccccccccccc "SUPERSEDES bbbbbbbbbbbb"             2026-08-02T00:00:00Z
  run "$CP" check bbbbbbbbbbbb
  [ "$status" -eq 3 ]
}

@test "contract is SILENT on a clear item and speaks on a corrected one" {
  add aaaaaaaaaaaa "nothing refers to this"
  run "$CP" contract aaaaaaaaaaaa
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  add 111111111111 "the original claim"                                  2026-08-01T00:00:00Z
  add 222222222222 "CORRECTION to backlog item 111111111111: it is FALSE" 2026-08-02T00:00:00Z
  run "$CP" contract 111111111111
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "PREMISE CHECK"
}

# ── the claim-side gate (cc-backlog guard 5) ─────────────────────────────────────────────────────

# seed_claimable <title> — a real item via the real verb, so these tests exercise the SHIPPING
# actuator rather than a hand-written approximation of its records.
seed_claimable() { "$CB" add --project claude-infrastructure --title "$1" --source t; }

@test "cc-backlog claim REFUSES a superseded item with verdict=premise-refuted on line 1" {
  id="$(seed_claimable "the original claim about rung 6")"
  add ffffffffffff "SUPERSEDES $id — its remedy is refuted" "$(future_ts)"
  run "$CB" claim "$id" --by tester
  [ "$status" -eq 4 ]
  # LINE 1 carries the token: cc-dispatch sees only a head-biased excerpt of this refusal.
  [ "$(printf '%s' "$output" | head -1 | grep -c 'verdict=premise-refuted')" -eq 1 ]
  # the refusal must name the override, or it is a dead end rather than a gate
  printf '%s' "$output" | grep -q -- "--force"
}

@test "the gate lets its own cure through: --force claims a superseded item" {
  id="$(seed_claimable "the original claim about rung 6")"
  add ffffffffffff "SUPERSEDES $id — its remedy is refuted" "$(future_ts)"
  run "$CB" claim "$id" --by tester --force
  [ "$status" -eq 0 ]
}

@test "an ordinary item still claims cleanly — the gate is not a blanket refusal" {
  # THE CONTROL for the two tests above. Without it, a guard that refused every claim would pass
  # both of them, and a blanket refusal is the failure mode that would strand 345 real items.
  id="$(seed_claimable "an ordinary piece of work nobody has corrected")"
  run "$CB" claim "$id" --by tester
  [ "$status" -eq 0 ]
}

@test "CC_BACKLOG_PREMISE_GATE=off restores the incumbent claim path exactly" {
  id="$(seed_claimable "the original claim about rung 6")"
  add ffffffffffff "SUPERSEDES $id — its remedy is refuted" "$(future_ts)"
  CC_BACKLOG_PREMISE_GATE=off run "$CB" claim "$id" --by tester
  [ "$status" -eq 0 ]
}

@test "FAIL-OPEN at the gate: an absent cc-premise lets the claim through" {
  # The premise lives OUTSIDE the ledger fold, so every way of failing to read it must dispatch
  # anyway — starving the queue on a sensor failure is the worse error.
  id="$(seed_claimable "the original claim about rung 6")"
  add ffffffffffff "SUPERSEDES $id — its remedy is refuted" "$(future_ts)"
  CC_BACKLOG_PREMISE_BIN="$BATS_TEST_TMPDIR/no-such-binary" run "$CB" claim "$id" --by tester
  [ "$status" -eq 0 ]
}

@test "the contract REACHES THE BRIEF — a corrected item's disproof is in the worker's prompt file" {
  # THE LOAD-BEARING ASSERTION OF THE WHOLE CHANGE. `corrected` deliberately does NOT block, so the
  # only thing standing between a worker and a refuted sub-claim is that the disproof is in the text
  # it is dispatched with. A verdict printed where only a log sees it changes nothing
  # (memory: conclusion-must-reach-the-enforcing-store) — so assert the FILE, not the exit code.
  #
  # This drives cc-dispatch's own brief composer via the same seam cc-dispatch uses, rather than
  # re-implementing the concatenation here: a test that rebuilt the brief itself would pass while
  # the shipping composer dropped the contract entirely.
  add 111111111111 "the original claim, with real work beside it"          2026-08-01T00:00:00Z
  add 222222222222 "CORRECTION to backlog item 111111111111: the 3.4x claim is FALSE — time-confounded" 2026-08-02T00:00:00Z
  pfile="$BATS_TEST_TMPDIR/brief.txt"; : > "$pfile"
  contract="$("$CP" contract 111111111111)"
  [ -n "$contract" ]
  printf '%s\n' "TASK — x" "DoD ref: none." ${contract:+"$contract"} "Rails: y" > "$pfile"
  grep -q "PREMISE CHECK" "$pfile"
  grep -q "222222222222" "$pfile"
  grep -q "DISPROOF IS THE DELIVERABLE" "$pfile"
  # …and a CLEAR item must leave the brief exactly as it was — an always-on banner is one the
  # worker learns to skip, which is the same as not being there.
  add aaaaaaaaaaaa "an ordinary item"                                      2026-08-01T00:00:00Z
  c2="$("$CP" contract aaaaaaaaaaaa)"
  [ -z "$c2" ]
  printf '%s\n' "TASK — x" "DoD ref: none." ${c2:+"$c2"} "Rails: y" > "$pfile"
  [ "$(wc -l < "$pfile")" -eq 3 ]
}

@test "a done-latched item still refuses with verdict=done-latched, not the new token" {
  # Guard ordering regression: guard (5) runs LAST, so an already-finished item must still be
  # reported as finished. cc-dispatch journals the two causes differently and a swap would make a
  # raced landing read as a stale premise.
  id="$(seed_claimable "work that already landed")"
  # `done` QUOTED: it is cc-backlog's verb, but shellcheck parses the bare word as the loop keyword
  # and aborts (SC1010). Quoting makes it literal — shellcheck's own suggested form, and narrower
  # than a disable annotation because it fixes the parse rather than suppressing the report.
  "$CB" "done" "$id" --evidence "landed abc123" >/dev/null
  run "$CB" claim "$id" --by tester
  [ "$status" -eq 4 ]
  [ "$(printf '%s' "$output" | head -1 | grep -c 'verdict=done-latched')" -eq 1 ]
}
