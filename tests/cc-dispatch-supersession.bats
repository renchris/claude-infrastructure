#!/usr/bin/env bats
# cc-dispatch — the SUPERSESSION surfacing (backlog 0c5d47c863bf).
#
# THE PREDICATE ITSELF LIVES IN cc-premise and is proved in tests/cc-premise-supersession.bats. What
# this file guards is the DISPATCHER'S half of the item's DoD: that when a sibling row may already
# hold an item's fix, the wave says so where somebody can act on it, and that it still dispatches.
#
# WHY BOTH HALVES ARE ASSERTED SEPARATELY. The contract already rides the worker's brief — that seam
# predates this change — but the brief is read by the WORKER, and the fact "dispatching this at all
# may have been the mistake" is only actionable to whoever is watching the wave, who never sees the
# prompt file. So the finding is additionally printed and JOURNALLED, and a test that checked only
# the brief would pass while both of those were dropped (memory:
# conclusion-must-reach-the-enforcing-store).
#
# AND IT MUST NOT BECOME A SKIP. Supersession is a heuristic judgement handed to the worker, not a
# verdict: retracting the item here would re-create the plan-open gate's failure mode on a signal
# that is right about one candidate in two. The "still spawns" assertion is the one that pins that.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

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
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt")] } ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit 0
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"

  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECT="proj-a" \
         CC_DISPATCH_MAX_SPAWN=1 \
         CC_DISPATCH_SID="bats" \
         CC_DISPATCH_PREMISE_BIN="$C/stubs/premise"
  printf '[{"id":"itemone","project":"proj-a","status":"open","title":"work","ts":"2026-07-21T00:00:00Z"}]' \
    > "$C/items.json"
}

# premise_stub <contract-body> — stands in for cc-premise's `contract` verb.
#
# STUBBED ON PURPOSE, and this is the seam that keeps the two files honest about their own subject.
# Driving the real predicate here would make every assertion below depend on the git history and the
# ledger shape that tests/cc-premise-supersession.bats already owns — so a change to the SCORING
# would red this file, which tests none of it. What is under test here is one conditional in
# cc-dispatch: does a contract carrying the marker get printed and journalled. The marker string is
# the consumed contract between the two, so a stub emitting it is the real interface
# (memory: assertion-span-must-equal-its-subject).
premise_stub() {
  cat > "$C/stubs/premise" <<EOF
#!/bin/bash
[ "\$1" = contract ] || exit 0
cat <<'BODY'
$1
BODY
EOF
  chmod +x "$C/stubs/premise"
}

fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; rm -rf "$C/pages" "$C/dispatch.lock" "$C"/brief-*.txt; }
notes() { jq -rs '[.[]|select(.action=="note")|.detail]|join("\n")' "$C/idl.jsonl" 2>/dev/null; }
spawns() { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

@test "a supersession contract is PRINTED, JOURNALLED, and the item is still dispatched" {
  premise_stub "PREMISE CHECK — verify BEFORE acting.
  POSSIBLE SUPERSESSION — 1 sibling item(s) reached DONE after this one was filed (2026-07-20T00:00:00Z).
    sib000000000 done 2026-07-21T00:00:00Z — its landed fix touched bin/x, which this item cites"
  fresh
  run "$DISP" --once
  # PRINTED — for whoever is watching the wave, who never opens the worker's prompt file.
  [ "$(printf '%s' "$output" | grep -ci 'possible supersession')" -ge 1 ]
  # JOURNALLED — an unrecorded near-miss cannot be counted later, and counting them is how anyone
  # learns whether this arm is earning its noise.
  [ "$(notes | grep -c 'possible supersession')" -ge 1 ]
  [ "$(notes | grep -c 'itemone')" -ge 1 ]
  # STILL DISPATCHED — not a skip, not a retraction. This is the assertion that keeps the arm
  # advisory; if it ever became a gate, this goes red rather than silently starving the queue.
  [ "$(spawns)" -eq 1 ]
  # …and the contract still reached the brief, which is where the WORKER reads it.
  grep -q 'POSSIBLE SUPERSESSION' "$C/brief-itemone.txt"
}

@test "CONTROL: an ordinary contract is neither printed nor journalled as supersession" {
  # The positive above is only evidence because the same harness stays quiet on a contract that
  # carries a different finding. Without this, a print wired unconditionally would pass test 1.
  premise_stub "PREMISE CHECK — verify BEFORE acting.
  CITED PATH(S) not at that location on origin/main: bin/x — moved, renamed, or never landed."
  fresh
  run "$DISP" --once
  refute_match "$output" 'possible supersession'
  [ "$(notes | grep -c 'possible supersession')" -eq 0 ]
  [ "$(spawns)" -eq 1 ]
  # POSITIVE CONTROL on the harness itself: the contract DID reach the brief, so "no supersession
  # line" is evidence about the condition rather than about a premise binary that never ran
  # (memory: absence-alarm-needs-existence-evidence).
  grep -q 'CITED PATH' "$C/brief-itemone.txt"
}

@test "CONTROL: an empty contract leaves the wave exactly as it was" {
  premise_stub ""
  fresh
  run "$DISP" --once
  refute_match "$output" 'possible supersession'
  [ "$(spawns)" -eq 1 ]
}
