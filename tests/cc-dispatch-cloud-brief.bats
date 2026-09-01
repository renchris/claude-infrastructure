#!/usr/bin/env bats
# cc-dispatch — THE CLOUD RIDER: the brief a CLOUD worker gets must be executable in a cloud VM
# (backlog 0c8b39b67665; CLOUD_OBSERVABILITY.md §8 step 2, §14, §15).
#
# WHY THIS EXISTS. §4.1 fixes the absence contract by CONTRACT and nothing else: "the session's
# brief requires its first act to be pushing that branch — an empty commit is enough". That single
# sentence is the sole basis on which C1 NOT-STARTED reads as "never booted"; strip it and `no ref`
# conflates a session that never started with a live one that has not pushed yet, which is exactly
# the ambiguity §4.1 was written to resolve. It was PROSE-ONLY for the whole life of the pipeline —
# no fire path emitted it — and the dispatcher's brief is the only channel to a cloud VM, since
# there is no inbound path to one.
#
# MEASURED FROM INSIDE A CLOUD VM this dispatcher fired (2026-09-01, branch
# claude/fire-20260901T200442Z-37476-1, three minutes in, alive and working):
#
#   git ls-remote --heads origin <declared branch>  → rc=0, EMPTY   §4.2 REACHABLE + ABSENT
#   cc-backlog done <id> --evidence …               → "unknown id", writes nothing
#   cc-notify --role desk "…"                       → verdict=unresolvable enqueued=0
#
# So the incumbent brief handed an off-box worker three terminal dispositions and all three were
# no-ops, while the one act that would have made the session observable was never asked for. This
# suite pins the replacement, and its SCOPING arms are the point: the rider keys on `$venue` — the
# label read off the argv that will actually run — never on the PLAN, so a cloud-planned row that
# fires locally (CC_FIRE_CLOUD unset) must still get the local brief.
#
# The dispatcher is driven END TO END with stubs and the composed brief file is read back, so this
# replays the real artifact rather than an approximation of it
# (memory: control-must-replay-the-real-artifact). The harness is lifted from
# tests/cc-dispatch-supersession.bats, which drives the same compose seam.
#
# RED-PROOF: case 5 replays the identical cloud fixture against the PRISTINE pre-change artifact
# recovered with `git archive`, which cannot carry the rider. A pinned sha, not origin/main — the
# moment this lands origin/main becomes the fixed version and the red half would invert and go
# green vacuously (the reason tests/cc-dispatch-venue-worktree.bats pins one too).
BASE_SHA="0d6293152"   # immutable ancestor of origin/main; carries the venue-blind brief

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  [ -x "$DISP" ] || skip "bin/cc-dispatch not found at $DISP"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

  git -C "$REPO" archive "$BASE_SHA" bin/cc-dispatch 2>/dev/null | tar -x -C "$C/pristine"
  PRISTINE="$C/pristine/bin/cc-dispatch"
  chmod +x "$PRISTINE" 2>/dev/null || true
  # FAIL LOUD if the control could not be recovered: an absent binary writes no brief, so the RED
  # half would pass VACUOUSLY on an empty file and stop being a proof.
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-cloud-brief.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
    return 1
  fi

  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*) echo '[]' ;;
      *) cat "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
esac
exit 0
EOF
  # The planner emits the --prompt-file the actuator writes. No --cwd and no --worktree: this suite
  # is about the BRIEF, and a cloud fire never touches a local directory anyway (F3).
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt")] } ]'
EOF
  # Both actuators are stubbed, because the venue SELECTS between them and either may be reached.
  for s in spawn offload cloud custody; do
    cat > "$C/stubs/$s" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/$s.log"
exit 0
EOF
  done
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn" \
           "$C/stubs/offload" "$C/stubs/cloud" "$C/stubs/custody"

  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_OFFLOAD_BIN="$C/stubs/offload" \
         CC_DISPATCH_CLOUD_BIN="$C/stubs/cloud" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECT="proj-a" \
         CC_DISPATCH_MAX_SPAWN=1 \
         CC_DISPATCH_SID="bats"
  unset CC_FIRE_CLOUD
}

# item <venuePlan-json-fragment-or-empty> — writes the one-row ledger the stub serves.
item() {
  printf '[{"id":"itemone","project":"proj-a","status":"open","title":"work","ts":"2026-07-21T00:00:00Z"%s}]' \
    "${1:-}" > "$C/items.json"
}

fresh() { : > "$C/idl.jsonl"; rm -f "$C"/*.log; rm -rf "$C/pages" "$C/dispatch.lock" "$C"/brief-*.txt; }

# has / hasnt <literal> — the assertion pair, and they are FUNCTIONS on purpose.
#
# bats runs each body under `set -eET`, and bash exempts the `[[ ]]` KEYWORD from errexit: a
# non-final `[[ "$output" == *"x"* ]]` is evaluated, its false result is discarded, and the test
# passes anyway (scripts/bats-assert-liveness.py, which reported eight such no-ops in the first
# draft of this file). A function call is an ordinary simple command, so its failure aborts the
# body wherever it sits — and `hasnt` keeps its `!` INSIDE the function, where the exemption
# applies to the negation but the call site still binds.
has()   { printf '%s\n' "$output" | grep -qF -- "$1"; }
hasnt() { ! printf '%s\n' "$output" | grep -qF -- "$1"; }

# brief <dispatcher-path> — runs one pass and prints the composed brief. Empty output means the
# brief was never written, which every assertion below must be able to tell from a wrong brief.
brief() {
  fresh
  ( cd "$REPO" && "$1" >/dev/null 2>&1 || true )
  cat "$C/brief-itemone.txt" 2>/dev/null || true
}

@test "cloud venue: the brief demands the FIRST ACT push that makes the session observable" {
  item ',"venuePlan":"cloud"'
  export CC_FIRE_CLOUD=on
  run brief "$DISP"
  [ -n "$output" ]
  # §8 step 2 — the act itself, spelled as a runnable command, and BEFORE the staleness rail.
  has "CLOUD VENUE"
  has "git commit --allow-empty"
  has "git push -u origin HEAD"
  # …and WHY, because a worker that does not know the consequence re-orders it away.
  has "NOT-STARTED"
  # ORDERING IS LOAD-BEARING: "first act" is only true if it precedes the FIRST STEP rail.
  local boot_ln step_ln
  boot_ln="$(printf '%s\n' "$output" | grep -n 'CLOUD VENUE' | head -1 | cut -d: -f1)"
  # …matched on the staleness rail's OWN opening, not on the bare token: the rider names it too
  # ("before the FIRST STEP below"), so a loose grep finds the rider and compares a line to itself.
  step_ln="$(printf '%s\n' "$output" | grep -n 'FIRST STEP — read what this item cites' | head -1 | cut -d: -f1)"
  # Three separate `[ ]` statements, not an && chain: `[` is a builtin and IS subject to errexit,
  # but a non-final element of an AND list is absorbed exactly like a `[[ ]]` keyword would be.
  [ -n "$boot_ln" ]
  [ -n "$step_ln" ]
  [ "$boot_ln" -lt "$step_ln" ]
}

@test "cloud venue: the three terminal dispositions route through the branch, not through cc-backlog" {
  item ',"venuePlan":"cloud"'
  export CC_FIRE_CLOUD=on
  run brief "$DISP"
  [ -n "$output" ]
  # §14 — nothing to commit is still a push, as a landed verdict artifact.
  has "NOTHING TO COMMIT"
  has "docs/research/"
  has "git merge-base --is-ancestor"
  # §15 — an operator-gated row parks through the file the desk reads off trunk.
  has "scripts/cloud-park.sh itemone --needs"
  has "docs/parks/itemone.md"
  # …and the verbs that write NOTHING from a VM are gone as instructions. Measured: both return
  # without touching a store, so briefing them is briefing a no-op.
  hasnt "On completion: cc-backlog done"
  hasnt "cc-backlog block itemone --needs"
  hasnt "cc-backlog reopen itemone"
}

@test "cloud venue: the rails tell it to push its branch, not to /ship — the desk lands it" {
  item ',"venuePlan":"cloud"'
  export CC_FIRE_CLOUD=on
  run brief "$DISP"
  [ -n "$output" ]
  # BOTH incumbent spellings are the OPPOSITE of the cloud contract, and the fixture project (no
  # .claude/commands/ship.md) exercises the second one: cloud-return.sh needs the branch pushed and
  # UNLANDED, so "land ONLY via /ship" asks for the desk's job and "never bare-push" forbids the one
  # act §8 step 2 requires — the absence that reads as never-booted.
  hasnt "land ONLY via the project-local /ship"
  hasnt "never bare-push, never land yourself"
  has "PUSH it — that is your completion signal"
  has "Do NOT run /ship"
  has "C10 — never edit settings.json/live hooks/launchd in place."
}

@test "SCOPED: a local fire keeps the incumbent brief verbatim, with no cloud rider" {
  item ''
  run brief "$DISP"
  [ -n "$output" ]
  has "On completion: cc-backlog done itemone --evidence"
  has "cc-backlog block itemone --needs"
  has "cc-backlog reopen itemone"
  hasnt "CLOUD VENUE"
  hasnt "cloud-park.sh"
}

@test "SCOPED: a cloud PLAN that fires locally gets the LOCAL brief — the venue is the argv, not the plan" {
  # THE ARM THAT MATTERS MOST. CC_FIRE_CLOUD is default-off, and an unhonoured plan fires LOCALLY
  # (bin/cc-dispatch journals it and proceeds). Keying the rider on `plan_venue` would hand a
  # locally-fired worker cloud-park.sh — a script that refuses a non-cloud branch — and take away
  # the cc-backlog verbs that DO work there. `$venue` is read off the argv that actually runs, so
  # the brief cannot disagree with what launched (G5's own property, one level up).
  item ',"venuePlan":"cloud"'
  unset CC_FIRE_CLOUD
  run brief "$DISP"
  [ -n "$output" ]
  hasnt "CLOUD VENUE"
  hasnt "cloud-park.sh"
  has "On completion: cc-backlog done itemone --evidence"
}

@test "RED-PROOF: the pristine pre-change dispatcher composes the same cloud fire with no rider" {
  item ',"venuePlan":"cloud"'
  export CC_FIRE_CLOUD=on
  run brief "$PRISTINE"
  # The control must still WRITE a brief — otherwise the absences below prove nothing about it.
  [ -n "$output" ]
  has "TASK — work"
  hasnt "CLOUD VENUE"
  hasnt "git commit --allow-empty"
  hasnt "cloud-park.sh"
  # …and it briefed the three no-ops and the rail that forbids the push, which is the defect stated
  # positively. (The fixture project ships no .claude/commands/ship.md, so the rails string under
  # test here is the second incumbent branch — the one that says "never bare-push".)
  has "On completion: cc-backlog done itemone --evidence"
  has "never bare-push, never land yourself"
}
