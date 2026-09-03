#!/usr/bin/env bats
# pipefail-sigpipe-lint — the RATCHET that stops `producer | early-exit-consumer` under pipefail.
#
# The scar is in-tree history: cc-relogin-poll's capability probe was
#     if "$ACCOUNTS_BIN" -h 2>/dev/null | grep -q -- '--login-status'; then
# and `ec9a43a9` fixed it. `grep -q` exits on the match, the producer takes SIGPIPE on its next
# write, and pipefail promotes that 141 — so the `if` reads FALSE for a flag that IS advertised.
# The poller exited 3 DETECTION-UNAVAILABLE with the surface in front of it, and separately faked a
# WINDOW-CAPPED that narrowed a declared T-7d window to 72h. Both were misread as deploy lag.
#
# Four properties are proved here, and all four matter:
#   • it DISCRIMINATES — red on the real scar shapes, green on every legitimate form in the tree.
#     The builtin producer splits ON ITS ARGUMENT and BOTH halves are pinned here: a LITERAL is one
#     bounded write and must stay green (a false red there is as fatal as a miss), while a
#     variable-sourced one is unbounded by inspection and must be red. Until 2026-08-17 test 3
#     asserted the second case GREEN on the strength of a 4 KiB measurement — see test 7;
#   • the MECHANISM is real and the FIX repairs it — asserted by running actual bash, not by
#     re-reading the detector. A lint for a race nobody re-measures is a lint for a rumour;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/pipefail-sigpipe-lint.sh"
  ALLOW="$REPO/scripts/pipefail-sigpipe-allow.txt"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX/scripts"
}

mkfile() { # $1=name $2=body  [$3=set line]
  { echo '#!/bin/bash'; echo "${3:-set -euo pipefail}"; printf '%s\n' "$2"; } > "$FIX/scripts/$1.sh"
}
census() { CC_PIPEFAIL_ROOT="$FIX" CC_PIPEFAIL_ALLOWLIST=/dev/null bash "$LINT" --census 2>/dev/null; }

@test "1: the lint's own --selftest passes (59/59, both directions)" {
  # 32 -> 34 on 2026-09-02: clause 3's head/tail producer arm gained r16/r17, the FIRE controls for
  # the g11/g12 pair that had pinned only the GREEN direction. Updated deliberately, per the line
  # below, and the two new arms are attribution-proved: reverting the arm to its pre-fix `-?[1-9]`
  # makes exactly these two go red and nothing else.
  #
  # 34 -> 37 later the same day (the NINTH correction): the same arm gained r18/r19/g17, which pin
  # it on the axis its own REASON is denominated in. The reason is "a LINE-oriented consumer cannot
  # exit mid-line", and every arm above tried only line-oriented consumers — so the arm was green
  # against `head -c` and `read -n`, which is_early also admits and which exit mid-line. r18/r19 are
  # those two consumers; g17 is the discrimination cell, same producer and same consumer COMMAND
  # WORD as r18 with only the flag differing, and it must stay GREEN. Attribution-proved the same
  # way: reverting the one changed line makes exactly r18 and r19 red, g17 and r16/r17 unaffected
  # (~/.claude/autonomy/mut284-pin.sh, seven gated predictions, subject restored by sha256).
  #
  # 37 -> 39 on 2026-09-03 (the TENTH correction): r18/g17 are both TWO-stage pipelines, where the
  # consumer OF THE PRODUCER and the LAST stage are the same segment — so they pin the ninth
  # correction's predicate and say nothing about its REFERENT. The call site passed seg[n] where the
  # reason names seg[2]. r20/g18 are the same two consumers at THREE stages, where those differ:
  # keyed on seg[n], r20 was GREEN (a false negative — a byte-oriented consumer in the MIDDLE, 20/20
  # orphaned) and g18 was RED (a false positive — a line-oriented middle drains the producer, 0/20).
  # The same referent failing in OPPOSITE directions is what makes it the call site's bug rather
  # than is_byteearly's. Attribution-proved the same way: reverting the one changed line makes
  # exactly r20 and g18 fail and nothing else (~/.claude/autonomy/mut285-pin.sh).
  #
  # 39 -> 41 on 2026-09-03 (the ELEVENTH correction), and it also RENAMES g18 to r22 and flips its
  # expectation. Two things were wrong one rung above the tenth correction. First, clause 2 still
  # read seg[n] while clause 3 read the first pair, so the conjunction described a PAIR THAT DOES
  # NOT EXIST for n >= 3; the ladder now walks the n-1 adjacent pairs and reports the first that
  # orphans. Second — and this is what flips g18 — every ground-truth cell from the eighth
  # correction on measured "the PRODUCER status", i.e. seg[1], while this lint's verdict is about
  # the PIPELINE status, and pipefail is denominated in EVERY stage. Re-measured on g18's own
  # fixture with all three statuses read in the same trial: seg1 0/20, seg2 20/20, PIPELINE 20/20.
  # The paragraph above is therefore right that a line-oriented middle drains the producer and wrong
  # that this makes the line green — the middle is then orphaned itself. r21/g19 are the new pair:
  # an early exit in the MIDDLE with a DRAINING last stage, which the seg[n] ladder could not see at
  # all, and its discrimination cell. Attribution-proved: reverting the block makes exactly r21, r22
  # and nothing else fail (~/.claude/autonomy/mut286-pin.sh).
  #
  # 41 -> 44 on 2026-09-03 (the TWELFTH correction). The eleventh made clauses 2 and 3 agree about
  # WHICH adjacent pair they judge. Clause 5 runs BEFORE that loop, drops the whole LINE, and was
  # keyed on a || occurring anywhere in seg[n] — while clause 3b, twelve lines below, tests the same
  # token and ALSO requires a group opener, because a || inside a group returns the GROUP's status.
  # So the two clauses agreed about the token and disagreed about its SCOPE, and g14 already pinned
  # the producer-side half while nothing pinned its mirror. Measured with the producer and the last
  # command held constant and only the bracketing varying: `cat BIG | { grep -q N || true; }` is
  # 20/20 non-zero at PIPESTATUS [141 0], byte-identical to the unmitigated shape, because the group
  # returns 0 and pipefail takes the max over every stage. r23/r24 are the brace and paren
  # spellings; g20 is the widening bound — a group in the last stage with the || OUTSIDE it still
  # swallows (0/20), so "any group opener disqualifies" would mint a correct line. Attribution-
  # proved: reverting the block makes exactly r23, r24 and nothing else fail
  # (~/.claude/autonomy/mut287-pin.sh). Census 125 -> 125, LOST=0, NEW=0.
  #
  # 44 -> 48 on 2026-09-03 (the THIRTEENTH correction), and this title was ALSO stale at 41/41 while
  # the assertion below read 44 — a pin whose title is a completeness claim nobody re-counts, which
  # is method 211 pointed at this very file. The twelfth correction taught clause 5 to ask what
  # BRACKETS a ||. Clause 3b is the sibling it learned that from and was still two PRESENCE tests
  # with no relation between them: a `{` somewhere and a `||` somewhere. An operator has two
  # operands, and the exoneration is sound only when the PIPELINE IS THE LEFT one. Measured with the
  # producer and the last command held constant and only the operand position varying, 20 trials per
  # cell: `{ false || printf | grep -q; }` is 20/20 orphaned while `{ printf | grep -q || true; }` is
  # 0/20. r25 is the live site this exonerated — hooks/hook-chain.sh:264, drained in the same commit
  # — r26 is the same two characters inside a quoted awk program where neither is an operator, g21
  # is the ( ) spelling of g14 that the brace-character test MINTED, and g22 is the discrimination
  # cell. Attribution-proved: reverting the one changed line makes exactly r25, r26 and g21 fail and
  # nothing else (~/.claude/autonomy/mut288-pin.sh). Census 125 -> 126 -> 125 across the repair and
  # its drain, LOST=0, NEW=0 net; the allowlist is untouched.
  #
  # 48 -> 53 on 2026-09-03 (the FOURTEENTH correction; landed as the thirteenth in its own branch
  # and renumbered on rebase, which is why its arm names start at r27). Every arm before these
  # spells the pipeline on the line whose status is read; clause 4 asked its question of that line,
  # and a function's LAST command hands its status to the CALLER, one frame up, on a line the clause
  # never looks at. That is the ec9a43a9 scar moved one frame: the same predicate written as a named
  # helper read GREEN. Measured with producer and consumer held constant (`cat BIG` 202,506 B |
  # `grep -q NEEDLE`, 20 trials, "the `if` took the FALSE branch on a match that IS present"):
  # inline anchor 20/20, function-final 20/20 byte-identical, a `:` after the pipeline 0/20,
  # `return 0` after it 0/20. r27 is the subject; g23 is the CALLER cell (same function called bare
  # — nothing reads the rc, so FINAL alone cannot be the trigger, and firing on it would have minted
  # the tree's three `x="$(fn)"` helpers); g24 is the FINAL cell; g25/r28 pin the three-state
  # consumed() the clause needs — `local v=$(p|q)` masks whoever calls (0/20) while the same
  # substitution as a plain assignment is final and does reach the caller (20/20). Attribution-
  # proved, three mutants, each failing exactly its own arms and nothing else: dropping the 4c
  # emission fails exactly r27+r28; dropping the caller half fails exactly g23; undoing the
  # consumed() reorder fails exactly g25. Census 125 -> 126 -> 125: the one site revealed
  # (hooks/validate-plan-structure.sh:29) is DRAINED in the same diff, so the allowlist does not
  # move. LOST=0 throughout.
  #
  # 53 -> 56 on 2026-09-03 (the FIFTEENTH correction), and it is UPSTREAM of every one above: they
  # all ask what the clause LADDER mis-judges, and the ladder judges seg[], which is whatever the
  # split produced. qmask() emitted a `\|` VERBATIM, so the stage split cut on a pattern byte and
  # the clauses were handed a boundary that does not exist. The defect is NOT "quoted pipes leak" —
  # that reading was written down as a prediction and REFUSED: an unescaped `|` inside double quotes
  # is masked correctly, and the backslash arm short-circuits the arm that would have masked it. So
  # the escape which declares a pipe not to be an operator is the one thing that made this read it
  # as one. Measured with producer and consumer held byte-identical at `cat "$f" | grep -c …` — the
  # DRAINED form this lint prescribes as the fix — and only the pattern varying: `grep -c
  # "warn\|read "` was RED while `grep -c "warn"`, `grep -c "warn\|xyz "`, `grep -c "warn|read "`
  # and the single-quoted spelling were all GREEN. The RED cell is the ratchet reporting its own
  # remedy, which is a6449cebc's class. g26 is that cell, g27 is the reason's bound (the alternation
  # is not the variable; where the invented boundary LANDS is), and r29 is the widening bound — a
  # real violation carrying the same escaped pipe must stay RED. Only g26 attributes: reverting the
  # two backslash arms makes exactly g26 fail and nothing else, with a six-arm GREEN column asserted
  # unaffected (~/.claude/autonomy/mut289-pin.sh, subject restored by sha256). Census 125 -> 125,
  # KEYS 116 -> 116, LOST=0, NEW=0; the allowlist is untouched.
  #
  # The FOURTEENTH correction asked the same question of its own new consumer and answered it the
  # other way — collect_caller's header reasons that over-splitting there is BOUNDED, because it can
  # only invent a command WORD. True, and silent about THIS consumer, where an invented boundary
  # invents a STAGE. Same fault, one consumer over, with an exposure nobody had asked about.
  #
  # 56 -> 59 on 2026-09-03 (the SIXTEENTH correction), and it is the CALLER half of the fourteenth.
  # collect_caller names command WORDS, so a function called inside a substitution — `v="$(f)"`,
  # whose first word is `v="$` — never entered callrd, and clause 4c is its only consumer. The
  # clause therefore DROPPED a function-final early-exit pipeline whose caller reads the rc, which
  # is a fail-OPEN, and its census read 0 so the drop looked like an empty class.
  # What made it findable was instrumenting the 4c state machine rather than counting its output:
  # 85 pipelines arm `pend`, 82 are cleared by a following code line, 3 reach the closing brace —
  # and all 3 of those 3 are called ONLY through a substitution, so the clause could see none of
  # the population it exists for. The five arms pinning 4c all call f as a bare word.
  # r30 (a $? capture) and r31 (condition position) are the two reading forms; g32 is the
  # discrimination cell — a bare `v="$(f)"` reads no status and stays GREEN, so the widening cannot
  # pass by convicting every substitution call. Attribution proved: reverting the one extractor arm
  # makes exactly r30+r31 fail and nothing else (~/.claude/autonomy/mut291-pin.sh, subject restored
  # by sha256). Census 125 -> 125, KEYS 116 -> 116, LOST=0, NEW=0 keyed on (path, TEXT) with
  # CC_PIPEFAIL_ROOT pinned on both arms; the allowlist is untouched.
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep '59/59' >/dev/null \
    || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

@test "2: RED on the ec9a43a9 scar, byte-for-byte" {
  mkfile scar "if \"\$ACCOUNTS_BIN\" -h 2>/dev/null | grep -q -- '--login-status'; then :; fi"
  run census
  printf '%s' "$output" | grep 'scripts/scar.sh:' >/dev/null || { echo "$output"; false; }
}

@test "3: the builtin producer splits on its ARGUMENT — literal GREEN, variable RED" {
  # Until 2026-08-17 this test asserted the variable form GREEN, citing "229 of 367 sites" and the
  # 4 KiB 0/200 measurement. That measurement is of a SIZE, not of a command word: the same printf is
  # 10/10 FALSE once the write passes 64 KiB (test 7). Left as it was, this control certified the bug.
  # Both halves are asserted, because "flags the variable one" alone would also pass against a lint
  # that flagged every builtin producer — which is the false positive the old title feared.
  mkfile lit1 "if printf '%s\\n' 'ready' | grep -q ready; then :; fi"
  mkfile lit2 "if echo done | grep -q done; then :; fi"
  run census
  [ -z "$output" ] || { echo "a pure-LITERAL builtin producer was flagged: $output"; false; }
  rm -f "$FIX/scripts/lit1.sh" "$FIX/scripts/lit2.sh"
  mkfile var1 "if printf '%s' \"\$MSG\" | grep -qE \"\$TELLS\"; then :; fi"
  run census
  printf '%s' "$output" | grep 'scripts/var1.sh:' >/dev/null \
    || { echo "a VARIABLE-sourced builtin producer was not flagged: $output"; false; }
}

@test "4: GREEN on both canonical fixes (drained grep, and awk NR<=N for head -N)" {
  mkfile fix1 "if git status --porcelain | grep . >/dev/null; then :; fi"
  mkfile fix2 "v=\$(git log --oneline | awk 'NR<=1')"
  run census
  [ -z "$output" ] || { echo "a FIX was flagged as a violation: $output"; false; }
}

@test "5: GREEN on the neutralise fix — { p || true; } keeps the early exit" {
  mkfile fix3 "{ strings -a \"\$b\" 2>/dev/null || true; } | grep -q 'X' && return 0" 'set -uo pipefail'
  run census
  [ -z "$output" ] || { echo "the neutralise idiom was flagged: $output"; false; }
}

@test "6: MECHANISM — the scar really does read FALSE on a match, and the fix really repairs it" {
  # Not a re-read of the detector: real bash, real SIGPIPE, real pipefail. The producer must still
  # be writing when the consumer exits, so the payload after the match is what makes it fire.
  seq 1 200000 > "$BATS_TEST_TMPDIR/big.txt"
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep -q '^1\$'"
  [ "$status" -ne 0 ] || { echo "the defect did NOT reproduce — this suite proves nothing"; false; }
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep '^1\$' >/dev/null"
  [ "$status" -eq 0 ] || { echo "the drain fix did not repair the pipeline (status=$status)"; false; }
  run bash -c "set -uo pipefail; { cat '$BATS_TEST_TMPDIR/big.txt' || true; } | grep -q '^1\$'"
  [ "$status" -eq 0 ] || { echo "the neutralise fix did not repair the pipeline (status=$status)"; false; }
  # and the fix must still be able to say NO
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep '^NOPE\$' >/dev/null"
  [ "$status" -ne 0 ] || { echo "the fix returns TRUE on a non-match — it is not a predicate"; false; }
}

@test "7: MECHANISM — the builtin exemption is a SIZE, not a command word (both sides of 64 KiB)" {
  # This is the empirical basis for clause 3's builtin exemption, and for its 2026-08-17 narrowing.
  # The exemption is real BELOW the pipe buffer and false above it, so both arms are asserted: an
  # exemption keyed on `printf`/`echo` alone would be sound on the first and wrong on the second.
  run bash -c 'set -uo pipefail; V="MATCHME$(head -c 4096 /dev/zero | tr "\0" x)"; printf "%s" "$V" | grep -q MATCHME'
  [ "$status" -eq 0 ] || { echo "builtin producer took SIGPIPE at 4 KiB — the exemption is unsound"; false; }

  # A payload well UNDER the pipe buffer still fits one write; 64 KiB does not. The command word
  # cannot decide it — a variable's length is not readable off the line, so the ARGUMENT decides.
  #
  # THIS ARM WAS 63488 AND IT WAS FLAKY, for a reason worth keeping (backlog 418628734437, measured
  # here 2026-08-24 at loadavg 11-15). Two corrections to what this comment used to claim:
  #
  # (1) THE SIZE WAS NOT WHAT IT SAID. `head -c 63488` is 62 KiB of payload, but `fold -w 80` adds
  #     794 newlines and the MATCHME prefix adds 9, so the arm actually wrote 64290 bytes — 1246
  #     under the 65536 buffer, not the ~2 KiB of headroom "62 KB" implies. The arithmetic omitted
  #     the framing it had itself introduced.
  # (2) "Deterministic on this box (0/10 and 10/10), because the boundary is the buffer rather than
  #     a scheduling race" WAS FALSE — measured 9/40 nonzero on this very arm, i.e. it red an
  #     innocent land ~22% of the time. The transition is a GRADED BAND, not a step, which is the
  #     signature of a race and not of a boundary:
  #       writes 60750 -> 1/40 · 62775 -> 3/40 · 64290 -> 9/40 and 12/40 · 64800 -> 12/40
  #       · 65200 -> 6/40 · 65821 -> 120/120
  #     Whether the producer sees EPIPE depends on whether grep exits before the write completes, so
  #     near the buffer it is genuinely probabilistic.
  #
  # ── 2026-09-03: A SINGLE TRIAL IS THE WRONG INSTRUMENT FOR THIS, AND MOVING THE SIZE IS NOT THE
  #    CURE. Both halves measured; row 418628734437 is OPEN and owns them. ───────────────────────
  # The remedy this arm carried — 57344, "0/120 at loadavg 15.3, with 7.4 KB of margin" — was true
  # at the load it was measured at and does not generalise. Re-measured 2026-09-03 at loadavg 44,
  # which is the load the LAND GATE actually runs at, N=200 per size:
  #
  #       raw 40960 (written 41481)   4/200 = 2.0%   every failure exit 141, silent
  #       raw 57344 (written 58069)   4/200 = 2.0%   every failure exit 141, silent
  #       raw 65821 (written 66652)  20/20  = 100%   the saturated control, instrument proven live
  #
  # The rate is FLAT from 40 KiB to 57 KiB. So under load this is not a buffer-edge band that more
  # byte margin escapes: it is a scheduling race whose rate does not depend on the sub-buffer size
  # at all, and a curve across 4096/16384/32768/40960/49152/57344 at N=60 is consistent with one
  # uniform low rate rather than with a floor (the only nonzero cell was 40960, BELOW two cells
  # that read clean — which is what noise looks like, not a boundary).
  # That exhausts the row's candidate (b) "move it away from the edge". What survives is its
  # candidate (a): ASSERT A RATE. It is also the stronger claim, because the property this arm
  # exists to prove is a rate DIFFERENCE — sub-buffer essentially always survives, over-buffer
  # essentially never does — and sampling each side once cannot state that.
  #
  # 18/20 and 0/20 are chosen from the measurement, not from taste: at the measured p = 0.02 the
  # sub-buffer side fails this gate about 0.07% of the time against 2% for a single trial, a ~30x
  # reduction, while the over-buffer side saturates and needs no slack. If the sub-buffer side ever
  # drops below 18/20, that is a real finding about the exemption and not a flake — read the
  # per-trial exit codes before touching this number, because 141 is SIGPIPE and anything else is a
  # different defect entirely.
  sub_ok=0
  for _i in $(seq 1 20); do
    if bash -c 'set -uo pipefail; V="MATCHME
$(head -c 57344 /dev/zero | tr "\0" x | fold -w 80)"; printf "%s\n" "$V" | grep -q MATCHME' >/dev/null 2>&1; then
      sub_ok=$((sub_ok+1))
    fi
  done
  [ "$sub_ok" -ge 18 ] || { echo "builtin producer survived UNDER the pipe buffer only $sub_ok/20 — the literal exemption would be unsound too"; false; }

  over_ok=0
  for _i in $(seq 1 20); do
    if bash -c 'set -uo pipefail; V="MATCHME
$(head -c 131072 /dev/zero | tr "\0" x | fold -w 80)"; printf "%s\n" "$V" | grep -q MATCHME' >/dev/null 2>&1; then
      over_ok=$((over_ok+1))
    fi
  done
  [ "$over_ok" -eq 0 ] || { echo "builtin producer survived 128 KB on $over_ok/20 trials — clause 3's NARROWING is over-scoped and 127 sites are false positives"; false; }
}

@test "8: the tree as it stands is GREEN against the committed allowlist" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "9: the ratchet blocks a NEW violation in an allowlisted file" {
  # A bare path allowlist would exempt the whole file; the count is what keeps protecting it.
  local first count tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  count="$(awk -F'\t' -v p="$first" '$1==p {print $2}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow.txt"
  awk -F'\t' -v p="$first" -v n="$((count-1))" \
    'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=n} {print}' "$ALLOW" > "$tmp"
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "a file over its allowlisted count did not go RED: $output"; false; }
}

@test "10: the DOWNWARD half fires — fixing a site without lowering the count is RED" {
  # Without this, the allowlist silently becomes a permanent exemption list.
  local first count tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  count="$(awk -F'\t' -v p="$first" '$1==p {print $2}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow2.txt"
  awk -F'\t' -v p="$first" -v n="$((count+1))" \
    'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=n} {print}' "$ALLOW" > "$tmp"
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "a fixed-but-not-delisted file did not go RED: $output"; false; }
  printf '%s' "$output" | grep 'was FIXED' >/dev/null \
    || { echo "the downward message did not name the cause: $output"; false; }
}

@test "11: own-scope narrows what BLOCKS without narrowing what is REPORTED" {
  local first tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow3.txt"
  awk -F'\t' -v p="$first" 'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=0} {print}' "$ALLOW" > "$tmp"
  # not in this land's diff ⇒ advisory, exit 0
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" CC_PIPEFAIL_OWN="some/other/file.sh" bash "$LINT"
  [ "$status" -eq 0 ] || { echo "an out-of-land file BLOCKED: $output"; false; }
  # in this land's diff ⇒ blocking, exit 1
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" CC_PIPEFAIL_OWN="$first" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "an in-land file did not block: $output"; false; }
}

@test "12: a broken detector is a LOUD non-verdict (exit 2), never a clean tree" {
  # This failure actually happened while writing the lint: one apostrophe inside the single-quoted
  # awk string truncated the program, and --census printed 0 sites. A silent-green detector is
  # strictly worse than no detector, so it must be impossible to reach.
  local broken="$BATS_TEST_TMPDIR/broken.sh"
  sed "s/^DETECT_AWK='/DETECT_AWK='function bad( { syntax error here/" "$LINT" > "$broken"
  run bash "$broken" --census
  [ "$status" -eq 2 ] || { echo "a broken detector exited $status, not 2: $output"; false; }
}

@test "13: WIRED AT THE CHOKEPOINT — ship-land's run_gate invokes the lint" {
  # A lint enforced only by its own suite is post-hoc detection: gate-select will not pick this
  # suite up when the edited file is a PRODUCER rather than the lint.
  grep 'pipefail-sigpipe-lint' "$REPO/scripts/ship-land.sh" >/dev/null \
    || { echo "ship-land.sh does not invoke pipefail-sigpipe-lint — the ratchet is not a gate"; false; }
}

@test "14: the allowlist may only ever SHRINK — it is regenerable from the tree" {
  run bash "$LINT" --regen
  [ "$status" -eq 0 ]
  # regen must reproduce the committed list exactly, or the committed list is stale
  printf '%s\n' "$output" | grep -v '^#' | awk 'NF' > "$BATS_TEST_TMPDIR/regen.txt"
  grep -v '^#' "$ALLOW" | awk 'NF' > "$BATS_TEST_TMPDIR/committed.txt"
  run diff -u "$BATS_TEST_TMPDIR/committed.txt" "$BATS_TEST_TMPDIR/regen.txt"
  [ "$status" -eq 0 ] || { echo "committed allowlist is stale vs the tree:"; echo "$output"; false; }
}

# ── the scan's non-verdict must survive the COMMAND SUBSTITUTION (backlog 57ff249657e0) ──────────
#
# Test 12 above already proved a dead scan exits 2 — but only through `--census`, where scan() runs
# in THIS shell. That is the one entry point where `exit 2` was never in danger, so it stood as a
# vacuous guard for the two that were: `--scan` and `--regen` both read scan through `$( … )`, and
# `exit` cannot leave a command substitution. It ends the subshell and hands back a status, which
# `|| true` discarded. `hits` was then empty — indistinguishable from a clean tree.
#
# Measured on the pre-fix file, 2026-08-14, ROOT=/nonexistent: `--scan` exited 1 (a claim about the
# tree) and named 16 grandfathered files as newly FIXED, none of which the operator had touched.

@test "15: --scan on an unusable ROOT is a NON-VERDICT (exit 2), not a tree claim" {
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --scan
  [ "$status" -eq 2 ] || { echo "expected 2 (non-verdict), got $status: $output"; false; }
  printf '%s' "$output" | grep -F 'NON-VERDICT' >/dev/null \
    || { echo "the non-verdict was not announced: $output"; false; }
}

@test "16: a dead scan may never FABRICATE the ratchet's downward half" {
  # The inversion, and the reason this is worse than a lost verdict: against a NON-EMPTY allowlist,
  # empty hits read as cur=0 < alw=N for every grandfathered file, so the lint did not merely fail
  # to judge — it asserted that 16 sites had been fixed, and exited 1 to make it stick.
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --scan
  if printf '%s' "$output" | grep -F 'was FIXED but its allowlist count was not lowered' >/dev/null; then
    echo "a dead scan fabricated the downward half — it judged files it never read: $output"; false
  fi
}

@test "17: --regen on an unusable ROOT writes NOTHING (it is invoked as > the allowlist)" {
  # The destructive half, and the one the broken --scan report actively PRESCRIBED: its FIX line
  # says "Regenerate with: … --regen > scripts/pipefail-sigpipe-allow.txt". The shell truncates the
  # destination before the script runs, so on a dead scan the old form wrote four header lines and
  # zero rows at exit 0 — a well-formed allowlist declaring every grandfathered site clean.
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --regen
  [ "$status" -eq 2 ] || { echo "expected 2 (non-verdict), got $status: $output"; false; }
  # stdout is what lands in the file; stderr is diagnosis. `run` merges them, so assert on the
  # stream that actually matters, captured on its own.
  env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --regen 2>/dev/null > "$BATS_TEST_TMPDIR/regen-dead.txt" || true
  [ ! -s "$BATS_TEST_TMPDIR/regen-dead.txt" ] \
    || { echo "a dead --regen still wrote an allowlist:"; cat "$BATS_TEST_TMPDIR/regen-dead.txt"; false; }
}

@test "18: CONTROL — the healthy tree is unmoved by the non-verdict plumbing" {
  # A guard that could only ever return 2 would be indistinguishable from a broken lint. This pins
  # the other direction: on the real tree, --scan still judges and --regen still reproduces the
  # committed allowlist byte-for-byte (test 14 asserts the content; this asserts they still RUN).
  run bash "$LINT" --scan
  [ "$status" -eq 0 ] || { echo "healthy --scan is no longer green: $status $output"; false; }
  run bash "$LINT" --regen
  [ "$status" -eq 0 ] || { echo "healthy --regen no longer exits 0: $status $output"; false; }
  printf '%s\n' "$output" | grep -v '^#' | awk 'NF' | grep -c . > "$BATS_TEST_TMPDIR/n.txt"
  [ "$(cat "$BATS_TEST_TMPDIR/n.txt")" -gt 0 ] \
    || { echo "healthy --regen produced no rows — the guard is firing on a good tree"; false; }
}

@test "19: a comment naming a heredoc opener does not mute the REST OF THE FILE" {
  # The 2026-08-27 defect. The detector's heredoc tracker is its only file-level LATCHING state and
  # its opener test ran BEFORE its comment test, so a comment that merely NAMED an opener armed it,
  # no terminator ever arrived, and every later line was consumed as heredoc BODY. Measured on the
  # unfixed tree: 10 of 402 scanned files latched at EOF, 5 real sites swallowed across 2 of them.
  #
  # THE DISTANCE IS THE POINT, and it is why this arm exists beside the lint's own --selftest arms:
  # those build two-line fixtures, which cannot tell a one-line slip apart from an UNBOUNDED mute.
  # The real culprits sat 241 and 30 lines above their victims. This plants the scar 200 lines below
  # the comment, so a fix that only cured the adjacent line would still fail here.
  {
    echo '#!/bin/bash'; echo 'set -euo pipefail'
    printf '%s\n' '# a note about `python3 - <<PY` and the bug it once had'
    i=0; while [ "$i" -lt 200 ]; do echo ": filler $i"; i=$((i+1)); done
    printf '%s\n' 'if git status --porcelain 2>/dev/null | grep -q .; then :; fi'
  } > "$FIX/scripts/muted.sh"
  # `grep -c` EXITS 1 on a legitimate zero, so a bare `n="$( … grep -c … )"` fails the test on the
  # very reading this arm exists to catch. Keep the substitution inside `[ ]`, where its status is
  # discarded, and re-take it only to build the message.
  [ "$(census | grep -c 'scripts/muted\.sh:')" -eq 1 ] \
    || { echo "expected 1 hit 200 lines below the comment, detector said \
$(census | grep -c 'scripts/muted\.sh:' || true) — the file is muted"; census | sed 's/^/  /'; false; }
  true
}

@test "20: REACHABILITY — the detector reaches the TAIL of the file the mute actually hid" {
  # Arm 19 pins the shape on a synthetic fixture; this pins it on the real subject, because a
  # fixture can satisfy a rule the live file still defeats. scripts/limit-recover/lr-reset-poller.sh
  # was invisible from its :357 comment to EOF and carries NO allowlist row, so its sites had never
  # once been judged — the failure was silent in the only direction that matters for a ratchet: a
  # NEW violation added below a latch point is born invisible, with no row to record it.
  #
  # A TRIPWIRE rather than a pattern (memory: probe-that-acts-on-absence-must-confirm-presence):
  # copy the real file, append a known scar to its END, and ask the detector. A green here means the
  # detector cannot see the tail of that file, whatever its census count says.
  [ -f "$REPO/scripts/limit-recover/lr-reset-poller.sh" ] \
    || skip "subject absent — this arm asserts about a specific file"
  mkdir -p "$FIX/scripts/limit-recover"
  cp "$REPO/scripts/limit-recover/lr-reset-poller.sh" "$FIX/scripts/limit-recover/lr-reset-poller.sh"
  printf '%s\n' 'if git status --porcelain 2>/dev/null | grep -q .; then :; fi' \
    >> "$FIX/scripts/limit-recover/lr-reset-poller.sh"
  [ "$(census | grep -c 'lr-reset-poller\.sh:')" -ge 1 ] \
    || { echo "the detector cannot reach the tail of lr-reset-poller.sh — it is muted again"; false; }
  # CONTROL, so the arm cannot pass vacuously on an unrelated pre-existing hit: the UNAPPENDED copy
  # must read 0. If it does not, this file has regained a live `grep -q` and the tripwire proves
  # nothing about reachability. The substitution stays inside `[ ]` — `grep -c` exits 1 on the zero
  # this control is asserting, so a bare assignment would fail the test on the PASSING reading.
  cp "$REPO/scripts/limit-recover/lr-reset-poller.sh" "$FIX/scripts/limit-recover/lr-reset-poller.sh"
  [ "$(census | grep -c 'lr-reset-poller\.sh:')" -eq 0 ] \
    || { echo "control failed: the unappended file already reads \
$(census | grep -c 'lr-reset-poller\.sh:' || true) hit(s), so arm 20 is vacuous"; false; }
  true
}

@test "21: GATE ONE — the stage split is QUOTE-AWARE, pinned in both directions" {
  # Every clause this suite exercises judges `last`, and `last` is chosen by the stage split. That
  # split used to be `split(work, seg, "|")` with no quote awareness, so a consumer whose OWN
  # pattern contains a `|` never reached the clause ladder: seg[n] was a fragment of the regex,
  # is_early() read false on it, and the line was dropped before any clause rendered a verdict.
  # It now runs through qmask(). ONE VARIABLE BETWEEN THE TWO FIXTURES: same producer, same
  # early-exiting consumer, same position; only the alternation differs — so BOTH must be reported,
  # and the pair is what says the fix is about the SPLIT and not about the pattern.
  #
  # This arm was written by #280 asserting the opposite, deliberately, so that the link which fixed
  # the split could not land without inverting it. That is the whole point of pinning a known gap.
  mkfile alt   "if cat \"\$F\" | grep -qE 'aaa|bbb'; then :; fi" 'set -uo pipefail'
  mkfile noalt "if cat \"\$F\" | grep -qE 'aaa'; then :; fi"     'set -uo pipefail'
  run census
  [ "$status" -eq 0 ]
  # THE FIRE HALF FIRST. Without it, a passing arm is indistinguishable from a census that reports
  # nothing at all — which is the failure mode this whole file exists to refuse.
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/noalt\.sh')" -eq 1 ] \
    || { echo "the plain form was not reported either — this arm is vacuous"; echo "$output"; false; }
  # AND THE HALF THAT WAS BLIND UNTIL 2026-09-02.
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/alt\.sh')" -eq 1 ] \
    || { echo "the alternation form is hidden again — the split has lost its quote awareness"; echo "$output"; false; }
  true
}

@test "22: GATE ONE — what the widening cost is RECORDED, not merely done" {
  # #280 measured this gap and declared it; this arm used to pin that declaration. The gap is now
  # closed, so what has to be load-bearing is the other half: the MEASUREMENT that made the fix
  # safe to land. A widening that mints findings on the real tree is a repo-wide land outage
  # (a6449cebc's shape), so the numbers that say it minted none are the reason this could ship.
  [ "$(grep -c 'WHAT IT COST TO LAND' "$LINT")" -ge 1 ] \
    || { echo "the landed-measurement block is gone from the lint"; false; }
  # keyed on the FUNCTION, not on prose: a reword may not silently remove the mechanism.
  #
  # COMMENT LINES ARE STRIPPED ON ALL FOUR COUNTS, 2026-09-03 (the FIFTEENTH correction). These two
  # were BARE while the two below already stripped, and the paragraph between them names exactly why
  # the bare form is wrong — so this arm documented the scar and then defended against it on half of
  # itself. It refused a correct file when the fifteenth correction's comment named the splitting
  # call while explaining what the split cuts on: count 2, arm red, nothing wrong with the file.
  # The dodge available at that moment was to reword the comment, which is the move this suite and
  # the lint header both forbid — key on the ARTIFACT'S SHAPE, never reword around a needle. So the
  # needle moved instead. The population these counts want is THE MECHANISM, and a comment is not
  # the mechanism; stripping is the right population and not a weakening. Proved still able to fire:
  # remove the call from the code line and the stripped count reads 0, so the arm still fails.
  [ "$(grep -vE '^[[:space:]]*#' "$LINT" | grep -c 'function qmask')" -eq 1 ]
  [ "$(grep -vE '^[[:space:]]*#' "$LINT" | grep -c 'split(qmask(work), seg')" -eq 1 ]
  # and the quote-BLIND spelling must be gone from the split itself — COMMENT LINES STRIPPED FIRST.
  # A bare count here reads 1 and refuses a correct file, because the block above documents the old
  # spelling by quoting it. That is this suite's own recurring scar: a grep that counts a token also
  # matches the sentence explaining it, so the fixed file convicts itself.
  [ "$(grep -vE '^[[:space:]]*#' "$LINT" | grep -c 'split(work, seg')" -eq 0 ]
  # and the control that proves the strip did not simply mute the check:
  [ "$(grep -vE '^[[:space:]]*#' "$LINT" | grep -c 'split(qmask(work), seg')" -eq 1 ]
  true
}

@test "23: GATE ONE — the mask does not eat an OPERATOR pipe (the LOST direction)" {
  # qmask() masks pipes inside quotes so the split cuts only on shell operators. The failure mode
  # in the OTHER direction is a mask that is too greedy: mask an operator pipe and the line reads
  # as no pipeline at all, so it is dropped — a site LOST rather than gained, and a census that
  # SHRINKS looks like progress. Measured LOST = 0 over the whole tree when this landed; this arm
  # is the fixture that keeps saying so.
  #
  # The middle stage carries the alternation, so a mask that swallowed the two real `|` around it
  # would leave n = 1 and the line would never be judged.
  mkfile mid "if cat \"\$F\" | grep -E 'aaa|bbb' | grep -q ccc; then :; fi" 'set -uo pipefail'
  run census
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/mid\.sh')" -eq 1 ] \
    || { echo "an operator pipe was masked — the site was LOST, not gained"; echo "$output"; false; }
  true
}

@test "24: the canonical fix for the newly-visible class is GREEN" {
  # All thirteen sites this widening revealed were drained with the same one-token cure the header
  # prescribes: `grep -qE PAT` becomes `grep -E PAT >/dev/null`. If that form were itself flagged
  # the fix would have nowhere to go and the ratchet could only ever grow.
  #
  # ITS FIRE CONTROL IS WHAT MAKES THIS ARM REAL, and that was not obvious when it was written. The
  # second assertion alone IS vacuous pre-fix: the quote-blind split cut inside the pattern and
  # never reached clause 2, so the drained twin read 0 for the wrong reason. It was written down as
  # a deliberate zero on exactly that reading — and the red-proof's rc-93 gate refused the
  # prediction, because the FIRE control in front of it is ALSO alternation-shaped, so pre-fix it
  # catches the vacuity itself and this arm goes red for the right reason.
  # A vacuity guard whose own subject is affected by the fix turns a deliberate zero into a genuine
  # red. Predict on the WHOLE arm, never on the assertion you happen to be thinking about.
  mkfile drained "if cat \"\$F\" | grep -E 'aaa|bbb' >/dev/null; then :; fi" 'set -uo pipefail'
  mkfile early   "if cat \"\$F\" | grep -qE 'aaa|bbb'; then :; fi"          'set -uo pipefail'
  run census
  [ "$status" -eq 0 ]
  # the FIRE control: the undrained twin must be reported, or "green" here means nothing.
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/early\.sh')" -eq 1 ] \
    || { echo "the undrained twin was not reported — this arm is vacuous"; echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/drained\.sh')" -eq 0 ]
  true
}

@test "25: GATE ONE — an unpartnered quote opens a context, and the tail is DATA" {
  # THIS ARM EXISTS TO REFUSE A PLAUSIBLE IMPROVEMENT, which is why it pins behaviour nobody has
  # complained about. qmask() enters a quote context on an opening quote whether or not that quote
  # is ever closed on the line, so an unpartnered quote masks every `|` after it and the line is
  # dropped before clause 2 runs. Read cold that looks like a fail-OPEN, and the obvious repair is
  # the contract the sibling masker strip280.awk already uses — "a quote with no partner is a
  # LITERAL, so the tail stays RAW". Measured 2026-09-02, that repair is WRONG FOR THIS TREE.
  #
  # By shell grammar a physical line carrying an unpartnered quote is one of exactly two things: the
  # OPENING line of a multi-line quoted construct, whose tail is genuinely DATA and must not be
  # judged — or the CLOSING line of one, whose tail is genuinely CODE and should be. A line-local
  # masker cannot tell those apart, because the discriminator is on a PREVIOUS line. So this is not
  # a contract worth flipping; it is the visible half of the missing continuation join, which
  # ca97c678b18b owns and pipe258.py already implements.
  #
  # The two fixtures differ in ONE variable — whether an unpartnered quote precedes the pipeline —
  # and the second is the FIRE control: it proves the detector DOES see this exact producer and
  # consumer when they are code, so the first fixture's green cannot be an artefact of a shape the
  # lint never reports.
  mkfile datum "PROG='cat \"\$f\" | grep -q needle"
  mkfile code  "cat \"\$f\" | grep -q needle"
  run census
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/code\.sh')" -eq 1 ] \
    || { echo "the paired-quote twin was not reported — this arm is vacuous"; echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'scripts/datum\.sh')" -eq 0 ] \
    || { echo "a multi-line construct's opening line was judged as code"; echo "$output"; false; }
  true
}

@test "26: MECHANISM — a function's LAST command hands its status to the caller, and the drain repairs it" {
  # Not a re-read of the detector: real bash, real SIGPIPE, real pipefail, one frame up. Test 6
  # proves the inline scar; this proves the SAME scar survives being named, which is the whole of
  # the fourteenth correction. The producer must still be writing when the consumer exits, so the
  # payload after the match is what makes it fire.
  seq 1 200000 > "$BATS_TEST_TMPDIR/big.txt"
  B="$BATS_TEST_TMPDIR/big.txt"
  # the FIRE ANCHOR, inline — if this does not reproduce, the three cells below prove nothing
  run bash -c "set -uo pipefail; if cat '$B' | grep -q '^1\$'; then echo TRUE; else echo FALSE; fi"
  [ "$output" = FALSE ] || { echo "the inline defect did NOT reproduce (got $output)"; false; }
  # ...and the same pipeline as a function's LAST command must be byte-identical to it
  run bash -c "set -uo pipefail; f() { cat '$B' | grep -q '^1\$'; }; if f; then echo TRUE; else echo FALSE; fi"
  [ "$output" = FALSE ] \
    || { echo "the function-final scar did not reproduce — clause 4c pins nothing (got $output)"; false; }
  # the BOUND: one statement from the end, the caller reads the LAST statement instead
  run bash -c "set -uo pipefail; f() { cat '$B' | grep -q '^1\$'; :; }; if f; then echo TRUE; else echo FALSE; fi"
  [ "$output" = TRUE ] \
    || { echo "a non-final pipeline reached the caller — clause 4c's FINAL bound is wrong"; false; }
  # and the prescribed drain must repair it through the function, while still able to say NO
  run bash -c "set -uo pipefail; f() { cat '$B' | grep '^1\$' >/dev/null; }; if f; then echo TRUE; else echo FALSE; fi"
  [ "$output" = TRUE ] || { echo "the drain fix did not repair the function (got $output)"; false; }
  run bash -c "set -uo pipefail; f() { cat '$B' | grep '^NOPE\$' >/dev/null; }; if f; then echo TRUE; else echo FALSE; fi"
  [ "$output" = FALSE ] || { echo "the fix returns TRUE on a non-match — it is not a predicate"; false; }
}

@test "27: the one site the fourteenth correction revealed is DRAINED, and the drain still discriminates" {
  # hooks/validate-plan-structure.sh's has_valid_status is the ec9a43a9 scar moved one frame: the
  # pipeline is the function's last command and `! has_valid_status "$FILE"` reads its status. It is
  # drained in the same diff as the detector that revealed it, which is why the census did not move.
  # Both directions are asserted — a `grep -qiE` that never matches is also "green" to a grep -c.
  H="$REPO/hooks/validate-plan-structure.sh"
  run grep -n "grep -qiE '\^status:" "$H"
  [ "$status" -ne 0 ] || { echo "the early-exit form is back: $output"; false; }
  # ...and the predicate still answers correctly on all three inputs
  printf -- '---\ntitle: x\nstatus: open\n---\nbody\n' > "$BATS_TEST_TMPDIR/ok.md"
  printf -- '---\ntitle: x\n---\nbody\n'               > "$BATS_TEST_TMPDIR/nostatus.md"
  printf -- 'no frontmatter\n'                          > "$BATS_TEST_TMPDIR/none.md"
  fn="$(sed -n '/^has_valid_status() {/,/^}/p' "$H")"
  [ -n "$fn" ] || { echo "has_valid_status could not be extracted — this arm is vacuous"; false; }
  run bash -c "set -uo pipefail; $fn; has_valid_status '$BATS_TEST_TMPDIR/ok.md'"
  [ "$status" -eq 0 ] || { echo "a VALID status line was rejected (status=$status)"; false; }
  run bash -c "set -uo pipefail; $fn; has_valid_status '$BATS_TEST_TMPDIR/nostatus.md'"
  [ "$status" -ne 0 ] || { echo "frontmatter with no status line was accepted"; false; }
  run bash -c "set -uo pipefail; $fn; has_valid_status '$BATS_TEST_TMPDIR/none.md'"
  [ "$status" -ne 0 ] || { echo "a file with no frontmatter at all was accepted"; false; }
}
