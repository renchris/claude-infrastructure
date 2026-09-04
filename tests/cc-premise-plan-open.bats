#!/usr/bin/env bats
# cc-premise, the `plan-open` arms: a DERIVED falsifier + the title-snapshot contract.
#
# WHY THESE TWO ARMS EXIST, and they answer opposite halves of one decay.
#
# cc-discover's C2 critic mints one backlog item per plan that `find-plan.sh --list-open` reports,
# so such an item's ENTIRE claim is "this plan is still open" and its title is a copy of the plan's
# H1 on the day it was minted. Nothing re-reads either fact.
#
#   plan has since gone terminal  ⇒ the item's whole reason for existing is gone ⇒ REFUSE (rc 3).
#                                   cc-dispatch has enforced this since 2026-07-31, but only at the
#                                   DISPATCHER — the desk, a peer session and a hand claim all
#                                   bypassed it. Deriving it here totalizes it at the actuator.
#   plan is still open            ⇒ the work is live, so refusing would strand it — but the TASK
#                                   line the worker reads is a stale snapshot. Measured on
#                                   `a50e6ab779e8`: titled "advance README hero banner" for twelve
#                                   days after that banner landed, while the plan stayed genuinely
#                                   open, so every other signal in cc-premise passed. The remedy is
#                                   to hand the worker TODAY's remaining sections, advisory only.
#
# EVERY REFUSAL BELOW IS PAIRED WITH A CONTROL THAT MUST NOT REFUSE — a still-open plan, an absent
# dodRef, an unresolvable helper, and (the load-bearing one) an item whose source is NOT plan-open
# but which merely CITES a complete plan as its DoD. That last shape is real: `791345455b58` is a
# 358-site pipefail defect filed by a human, and a guard keyed on "the dodRef plan is complete"
# alone would silently close it (bin/cc-dispatch:842-846).
#
# The helpers are the REAL scripts/find-plan.sh and scripts/plan-phase-scan.sh, resolved exactly the
# way the shipping code resolves them. A stubbed approximation would pass while the real helper's
# verb, exit codes or JSON field names drifted (memory: control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PREMISE="$REPO/bin/cc-premise"
  BACKLOG_BIN="$REPO/bin/cc-backlog"
  TMP="$(mktemp -d)"
  # HERMETIC $HOME, not merely a redirected store: both subjects DEFAULT under ~/.claude, and the
  # helper resolver's SECOND candidate is $HOME/.claude/scripts — so an unfixtured $HOME would let
  # the operator's deployed copy answer instead of this checkout's, silently testing another
  # version. With $HOME empty, only the co-versioned sibling can resolve, which is the arm we mean.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$TMP/backlog.jsonl"
  export CC_BACKLOG_IDL="$TMP/idl.jsonl"
  export CC_BACKLOG_KICK=off
  # Pin the git arms INERT — not under test here, and leaving them live would make every assertion
  # a function of whatever this worktree's HEAD happens to be.
  export CC_PREMISE_REPO=""
  PLANS="$TMP/plans"; mkdir -p "$PLANS"
}

teardown() { rm -rf "$TMP"; }

# add <title> <source> [dodRef] [falsifier] — through the SHIPPING verb, so these tests exercise the
# real record shape (id = hash of project+title+source) rather than a hand-written approximation.
add() {
  "$BACKLOG_BIN" add --project p --title "$1" --source "$2" \
    ${3:+--dod-ref "$3"} ${4:+--falsifier "$4"} 2>/dev/null
}

# plan <name> <status> [extra heading lines…] → prints the path
plan() {
  local f="$PLANS/$1.md" st="$2"; shift 2
  { printf -- '---\nstatus: %s\n---\n\n# The %s plan\n\n' "$st" "$1"
    local ln; for ln in "$@"; do printf '%s\n\n' "$ln"; done
  } > "$f"
  printf '%s' "$f"
}

verdict() { printf '%s' "$1" | sed -n 's/^verdict=//p'; }
# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. This returns non-zero directly and so fails anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# ── D1a · the derived falsifier ──────────────────────────────────────────────────────────────────

# MUTATION CONTROL for this test: revert `if status not in ("complete", "superseded")` to
# `if status not in ("superseded",)` in run_derived_plan_falsifier — verified RED (status 0,
# verdict=clear) on 2026-08-10. Deleting the whole `run_derived_plan_falsifier` call in `assess`
# reddens it the same way.
@test "plan-open + plan COMPLETE -> REFUSES with verdict=falsified" {
  p="$(plan finished complete '## S1 · something')"
  id="$(add 'advance the finished plan' plan-open "$p")"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = falsified ]
  # the contract must say the probe was DERIVED and name the plan + the status it read, or a reader
  # cannot tell a measured re-run from an inferred one — which is the whole difference between this
  # arm and a stored falsifier.
  printf '%s' "$output" | grep -q "DERIVED FALSIFIER"
  printf '%s' "$output" | grep -q "$p"
  printf '%s' "$output" | grep -q "status: complete"
}

# ── D1b · the sweep's CLAIMED skip, and the one verdict it must not cover ────────────────────────
# `--close-falsified` skips a CLAIMED row because a STORED probe is a runtime reading taken at one
# instant, and closing on one races a worker seconds from landing. The derived plan verdict is not a
# sample — it is one read of the plan's own frontmatter — and a row claimed on the premise "this
# plan is open" over a plan that is finished is the exact row that rots: it cannot be dispatched, so
# nothing re-asks it, and the stale premise is what keeps someone holding it. Live instance:
# a507762b0a0d (STOP_CHAIN_WAVE2.md), claimed and unretractable.
#
# MUTATION CONTROL: delete the `_derived_only` branch (restore the unconditional claimed skip) and
# the first test below goes RED with `closed_falsified: 0`; drop the `not (falsifier)` clause and
# the second goes RED, because a claimed row with its OWN stored probe would then be closed too.

@test "sweep: a CLAIMED plan-open row is closed on the DERIVED verdict (not a sampled probe)" {
  p="$(plan claimed-finished complete '## S1 · something')"
  id="$(add 'advance the claimed finished plan' plan-open "$p")"
  "$BACKLOG_BIN" claim "$id" --by bats-holder --force >/dev/null 2>&1
  [ "$("$BACKLOG_BIN" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = claimed ]

  run "$PREMISE" sweep --json --close-falsified 5
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" -ge 1 ]
  # `done` QUOTED — bare, shellcheck reads it as the loop keyword (SC1010); the .bats gate blocks.
  [ "$("$BACKLOG_BIN" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "done" ]
}

@test "sweep: a CLAIMED row carrying its OWN stored probe is still skipped (the sample guard holds)" {
  # THE CONTROL, and it is the whole safety argument: the widening must be keyed on "this verdict
  # came from the frontmatter", never on "this row is a plan-open row". A stored probe on a claimed
  # row keeps the original guard, whatever its source field says.
  p="$(plan claimed-probed complete '## S1 · something')"
  id="$(add 'claimed row with its own probe' plan-open "$p" 'true')"
  "$BACKLOG_BIN" claim "$id" --by bats-holder --force >/dev/null 2>&1

  run "$PREMISE" sweep --json --close-falsified 5
  [ "$status" -eq 0 ]
  [ "$("$BACKLOG_BIN" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = claimed ]
}

@test "plan-open + plan SUPERSEDED -> REFUSES with verdict=falsified" {
  p="$(plan replaced superseded '## S1 · something')"
  id="$(add 'advance the replaced plan' plan-open "$p")"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = falsified ]
  printf '%s' "$output" | grep -q "status: superseded"
}

# THE PRIMARY CONTROL. Without it, an arm that refused every plan-open item would pass both tests
# above — and a blanket refusal strands exactly the live work the plan is still carrying.
@test "plan-open + plan still OPEN -> does NOT refuse" {
  p="$(plan live open '## S1 · a section still to do')"
  id="$(add 'advance the live plan' plan-open "$p")"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "verdict=falsified"
}

@test "FAIL-OPEN: a dodRef that is not an existing file cannot refuse" {
  # Two shapes, both live in the store: an item whose dodRef points at a plan that has since been
  # deleted, and one whose dodRef is a code reference rather than a path. Neither is readable, and
  # an unreadable premise is "I could not tell", never "it is finished".
  a="$(add 'advance a plan that was deleted' plan-open "$PLANS/no-such-plan.md")"
  b="$(add 'advance something keyed on a code ref' plan-open 'bin/cc-dispatch:831')"
  for id in "$a" "$b"; do
    run "$PREMISE" check "$id"
    [ "$status" -eq 0 ]
    refute_match "$output" "verdict=falsified"
  done
  # …and an item carrying NO dodRef at all takes the same path.
  c="$(add 'advance a plan with no dodRef recorded' plan-open)"
  run "$PREMISE" check "$c"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "FAIL-OPEN positive control: an unresolvable or non-answering find-plan.sh cannot refuse" {
  # THE SENSOR-FAILURE HALF, and it is the one that must never convict. The plan below IS complete,
  # so the arm would refuse if it could ask — every failure here is therefore a real positive
  # control on the fail-open path rather than a vacuous pass over a clear item.
  p="$(plan alsofinished complete '## S1 · something')"
  id="$(add 'advance a complete plan we cannot ask about' plan-open "$p")"
  # sanity: with the real helper it DOES refuse, so the two assertions below are separating
  # "could not ask" from "asked and got no", not merely observing a dead arm.
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]

  # (i) helper unresolvable
  CC_PREMISE_FINDPLAN_BIN="$TMP/no-such-helper.sh" run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"

  # (ii) helper answers exit 2 — find-plan.sh's DECLARED "could not read the file at all", which
  # prints the word `unknown` while doing so. Keying on the word instead of the exit code would
  # collapse "the frontmatter says unknown" into "I could not ask"; this stub is that distinction.
  printf '#!/bin/sh\necho unknown\nexit 2\n' > "$TMP/fp2.sh"; chmod +x "$TMP/fp2.sh"
  CC_PREMISE_FINDPLAN_BIN="$TMP/fp2.sh" run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"

  # (iii) an explicitly EMPTY override disables the arm — how a suite pins it inert, matching the
  # CC_PREMISE_REPO discipline. Without this, "unset means default" and "empty means off" could
  # silently become one branch.
  CC_PREMISE_FINDPLAN_BIN="" run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

# THE SCOPING TEST, and it is the load-bearing one of the file. A terminal dodRef is NOT evidence
# about a HUMAN-filed item — it falsifies only an item whose whole reason for existing was that the
# plan was open. `791345455b58` in the live store is a real 358-site pipefail defect that merely
# CITES a complete plan as its DoD; keying on the dodRef alone would have closed it silently.
@test "source is NOT plan-open -> a complete dodRef plan proves nothing" {
  p="$(plan cited complete '## S1 · something')"
  id="$(add 'a real defect that merely cites a complete plan as its DoD' relogin-verify "$p")"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "verdict=falsified"
  # …and the advisory arm is scoped identically: no plan snapshot rides a human-filed item's brief.
  run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A STORED PROBE IS THE ITEM OWNER'S OWN QUESTION ABOUT THEIR OWN CONDITION; the plan's frontmatter
# is a coarser proxy. A proxy must never outrank the measurement it stands in for — so a stored
# falsifier reporting STILL LIVE has to win over a derived one that would refuse.
@test "a STORED falsifier wins over the derived one on a plan-open item" {
  p="$(plan storedwins complete '## S1 · something')"
  id="$(add 'advance a complete plan whose own probe is live' plan-open "$p" 'false')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  # The STORED arm's own wording is the sentinel that it, and not the derived arm, did the render.
  # `false` exits 1 — an ordinary "asked, answered no" — so the ordinary arm speaks (see
  # tests/cc-premise-falsifier.bats for why non-zero is NOT REFUTED rather than a confirmation).
  printf '%s' "$output" | grep -q "NOT REFUTED"
  refute_match "$output" "DERIVED FALSIFIER"
}

@test "the shared kill switch CC_PREMISE_FALSIFIER=off disables the derived probe too" {
  # A derived probe is still a probe: an operator who turns falsification off must not be left with
  # one still running. Asserted rather than assumed, because the two arms are different functions.
  p="$(plan switched complete '## S1 · something')"
  id="$(add 'advance a complete plan with falsification off' plan-open "$p")"
  CC_PREMISE_FALSIFIER=off run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

# ── D1b · the title-snapshot contract (backlog 82a6c1894384) ─────────────────────────────────────

# MUTATION CONTROL for this test: revert the `if not lines` gate in cmd_contract to the incumbent
# `if verdict in ("clear", "unknown") or not lines` — verified RED (empty output) on 2026-08-10,
# because this arm leaves the verdict `clear` on purpose. Deleting the `lines.extend(
# plan_remaining_lines(ent))` call in `assess` reddens it the same way.
@test "plan still OPEN -> the contract names TODAY's remaining sections, and check still exits 0" {
  # ⚠️ FIXTURE HAZARD, learned by watching this test go green for the wrong reason: plan-phase-scan
  # matches DONE as a CASE-INSENSITIVE SUBSTRING of the heading, so an innocent "still to be done"
  # scans as DONE and the whole section list empties — the assertions below then pass or fail on a
  # property of the wording rather than of the code. Every PENDING heading here is worded to contain
  # no `done`, and the DONE control is explicit.
  p="$(plan remaining open \
        '## S1 · the section that still awaits work' \
        '## S2 · the landed one — DONE' )"
  id="$(add 'advance a stale title that says something finished' plan-open "$p")"

  run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  # the worker must be told the TASK line above is a snapshot…
  printf '%s' "$output" | grep -q "PLAN-OPEN SNAPSHOT"
  # …and handed the plan's actual remaining work, named. This is the assertion that fails if the
  # arm is absent: the item's own title says nothing about S1.
  printf '%s' "$output" | grep -q "the section that still awaits work"
  printf '%s' "$output" | grep -q "$p"
  # the DONE section must NOT be presented as remaining work, or the block is just the plan's ToC.
  refute_match "$output" "the landed one"

  # ADVISORY ONLY. It appends lines and touches neither the verdict nor the exit code — a snapshot
  # is never a refusal, and making this block would strand every live plan in the store.
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
}

@test "silence, never a fabrication: an open plan with no scannable sections emits nothing" {
  # plan-phase-scan.sh emits the document H1 as a section spanning the whole file, so a plan with no
  # sub-headings yields exactly one PENDING row that is the plan's TITLE. Emitting it would put the
  # very snapshot-title this arm distrusts back at the top of its own remedy — and it would make the
  # contract fire on every plan-open item, which is the same as not being there.
  p="$(plan bare open)"
  id="$(add 'advance a plan with no sections at all' plan-open "$p")"
  run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silence when plan-phase-scan.sh cannot be run at all" {
  p="$(plan unscannable open '## S1 · the section that still awaits work')"
  id="$(add 'advance a plan we cannot scan' plan-open "$p")"
  # a helper that is not there, and one that fails — neither may invent a finding.
  CC_PREMISE_PLANSCAN_BIN="$TMP/no-such-scan.sh" run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '#!/bin/sh\nexit 1\n' > "$TMP/scanfail.sh"; chmod +x "$TMP/scanfail.sh"
  CC_PREMISE_PLANSCAN_BIN="$TMP/scanfail.sh" run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # …and unparseable output is the third way to fail, which must also be silence rather than a crash.
  printf '#!/bin/sh\necho not json\n' > "$TMP/scanjunk.sh"; chmod +x "$TMP/scanjunk.sh"
  CC_PREMISE_PLANSCAN_BIN="$TMP/scanjunk.sh" run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the remaining-work list is BOUNDED and says so — a silent cap reads as completeness" {
  local hs=() i
  for i in $(seq 1 14); do hs+=("## S$i · pending section number $i"); done
  p="$(plan manysections open "${hs[@]}")"
  id="$(add 'advance a plan with many pending sections' plan-open "$p")"
  run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "showing the first 8"
  # the TOTAL rides the same line, so a reader can see what was withheld
  printf '%s' "$output" | grep -q "14 of 15 section"
  [ "$(printf '%s' "$output" | grep -c 'pending section number')" -eq 8 ]
}
