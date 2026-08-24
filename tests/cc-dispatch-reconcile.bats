#!/usr/bin/env bats
# cc-dispatch — EVERY ADMITTED ID REACHES A TERMINAL RECORD (cloud-lane fix #3).
#
# THE DEFECT, MEASURED. Pass 20260824T083341Z-71481 on the non-venue-filtered lane journalled
# `admitted:12` and then, for those twelve ids, NOTHING — no wave-plan placement, no claim, no skip,
# no failure — and summarised `fired:0 failed:0 abstained:0`. Twelve items every ~5 minutes, all
# day, and the summary read exactly like a healthy pass over an empty queue. That is a silent zero
# over a population the pass could name and did not (memory: zero-claim-must-name-its-excluded-
# strata), and it is why the lane read as "nothing eligible" rather than "twelve items dropped".
#
# THE HOLE IS STRUCTURAL, not a missing arm. The spawn loop iterates the PLAN (`i < n`) and breaks
# at MAX_SPAWN, so every admitted id the planner did not place falls out of the pass unnamed —
# including the whole wave when the planner returns an empty array with rc 0, which is what
# happened. The wall verdicts (capacity / auth / unknown / capped) drop them the same way.
#
# THE FIX asserts the pass against itself: ADMITTED_IDS is what it let in, TERMINAL_IDS is what it
# accounted for, and the difference is journalled per id as `action:"unplaced"` and counted into the
# summary as `unplaced`. `admitted == admitted_terminal + unplaced` then holds BY CONSTRUCTION — the
# assertion with teeth is that `unplaced` is 0 on a healthy pass, and that a non-zero value arrives
# with the ids attached instead of as a silent all-zero summary.
#
# THE CONTROL IS THE REAL ARTIFACT. bd5eab33e is this branch's parent and an immutable ancestor of
# origin/main forever, so it stays the control after this lands. It is pinned as a LITERAL sha and
# not `origin/main`, which advances past this fix on landing and would compare the fix to itself.

BASE_SHA="bd5eab33e"   # immutable ancestor of origin/main; carries the pre-fix bin/cc-dispatch

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
  # FAIL LOUD if the control could not be recovered. Without this the RED halves run an absent
  # binary that writes nothing, and every "the old tree does NOT do this" assertion passes
  # VACUOUSLY — the exact way a control silently stops being a control.
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-reconcile.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
    return 1
  fi

  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*) jq -cn --argjson n "\${STUB_LIVE:-0}" '[range(\$n) | {id:"c\(.)", status:"claimed"}]' ;;
      *) cat "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
esac
exit 0
EOF
  # wave-plan stub. \$STUB_WP_PLAN selects the SHAPE of the answer, which is the whole subject here:
  #   full  — place every item it was handed (the healthy planner)
  #   empty — return `[]` with rc 0. THE MEASURED CASE: a successful call that places nothing, which
  #           is what pass 20260824T083341Z-71481 received.
  #   half  — place only the first item, so the admitted set and the plan differ by a KNOWN amount.
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; printf '%s' "\$2" > "$C/wave.json"; shift 2 ;; *) shift ;; esac; done
rc="\${STUB_WP_RC:-0}"
if [ "\$rc" = 0 ]; then
  case "\${STUB_WP_PLAN:-full}" in
    empty) printf '[]' ;;
    half)  printf '%s' "\$items" | jq -c '[ .[0:1][] | {id, account:"next3", fire_line:["--prompt-file","/dev/null"]} ]' ;;
    *)     printf '%s' "\$items" | jq -c '[ .[]        | {id, account:"next3", fire_line:["--prompt-file","/dev/null"]} ]' ;;
  esac
fi
exit "\$rc"
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit "\${STUB_SPAWN_RC:-0}"
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"

  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECT="/repo/proj" \
         CC_DISPATCH_MAX_SPAWN=12 \
         CC_DISPATCH_SID="bats"
}

seed_items() { jq -cn --argjson n "$1" '[range(1;$n+1)|{id:("i"+(tostring)),project:"proj",status:"open",title:"t"}]' > "$C/items.json"; }
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; rm -rf "$C/pages" "$C/wave.json" "$C/dispatch.lock"; }

sum() { jq -rs "[.[]|select(.action==\"summary\")][-1].$1" "$C/idl.jsonl" 2>/dev/null; }
unplaced_recs() { jq -rs '[.[]|select(.action=="unplaced")]|length' "$C/idl.jsonl" 2>/dev/null || echo 0; }

# ── the measured case, replayed ───────────────────────────────────────────────────────────────────

@test "1 a wave the planner places NOTHING is journalled per id, not summarised as all-zeros" {
  # This is pass 20260824T083341Z-71481 in a fixture: 12 admitted, planner returns [] with rc 0.
  seed_items 12
  fresh; CC_DISPATCH_CEILING=12 STUB_WP_PLAN=empty "$DISP" --once >/dev/null 2>&1
  [ "$(sum admitted)" -eq 12 ]
  [ "$(sum unplaced)" -eq 12 ]
  [ "$(sum admitted_terminal)" -eq 0 ]
  [ "$(unplaced_recs)" -eq 12 ]
  # each record NAMES its id — a count is not a fact, and the id is what makes the loss actionable
  [ "$(jq -rs '[.[]|select(.action=="unplaced")|.id]|sort|unique|length' "$C/idl.jsonl")" -eq 12 ]

  # RED against the real pre-fix artifact: the identical fixture summarises all-zeros with no field
  # to notice by and no per-id record anywhere.
  fresh; CC_DISPATCH_CEILING=12 STUB_WP_PLAN=empty "$PRISTINE" --once >/dev/null 2>&1
  [ "$(sum admitted)" -eq 12 ]
  [ "$(sum unplaced)" = null ]
  [ "$(unplaced_recs)" -eq 0 ]
  [ "$(sum fired)" -eq 0 ] && [ "$(sum failed)" -eq 0 ]
}

@test "2 a PARTIAL plan accounts for both halves — the placed one and the dropped one" {
  # The generalisation of case 1: the hole is `admitted − placed`, not specifically `all of them`.
  seed_items 4
  fresh; CC_DISPATCH_CEILING=4 STUB_WP_PLAN=half "$DISP" --once >/dev/null 2>&1
  [ "$(sum admitted)" -eq 4 ]
  [ "$(sum unplaced)" -eq 3 ]
  [ "$(sum admitted_terminal)" -eq 1 ]
  [ "$(sum fired)" -eq 1 ]
  # the id that DID fire is not also reported unplaced — the two sets are disjoint
  [ "$(jq -rs '[.[]|select(.action=="unplaced")|.id]|index("i1")' "$C/idl.jsonl")" = null ]

  fresh; CC_DISPATCH_CEILING=4 STUB_WP_PLAN=half "$PRISTINE" --once >/dev/null 2>&1
  [ "$(unplaced_recs)" -eq 0 ]
}

@test "3 CONTROL: a healthy pass reports unplaced 0 — the alarm does not fire at every tick" {
  # An alarm that fires on every pass says as little as one that cannot fire at all
  # (memory: alarm-polarity-and-attention-budget). This is also the positive control for cases 1
  # and 2: it proves the same harness reaches a fully-accounted pass, so a non-zero `unplaced`
  # there is evidence about the plan and not about the fixture.
  seed_items 3
  fresh; CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ "$(sum admitted)" -eq 3 ]
  [ "$(sum fired)" -eq 3 ]
  [ "$(sum unplaced)" -eq 0 ]
  [ "$(sum admitted_terminal)" -eq 3 ]
  [ "$(unplaced_recs)" -eq 0 ]
}

@test "4 the invariant holds on every summary: admitted == admitted_terminal + unplaced" {
  seed_items 6
  for shape in full half empty; do
    fresh; CC_DISPATCH_CEILING=6 STUB_WP_PLAN="$shape" "$DISP" --once >/dev/null 2>&1
    run jq -rs '[.[]|select(.action=="summary")]|all(.admitted == (.admitted_terminal + .unplaced))' "$C/idl.jsonl"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
  done
}

@test "5 a WALL leaves no admitted id unnamed either — capacity is not an excuse to go quiet" {
  # The wall verdicts return through their own early exits, which is precisely how the admitted set
  # escaped accounting before. Reconciling inside idl_summary is what covers them by construction
  # rather than one arm at a time.
  seed_items 5
  fresh; CC_DISPATCH_CEILING=5 STUB_WP_RC=4 "$DISP" --once >/dev/null 2>&1
  [ "$(sum admitted)" -eq 5 ]
  [ "$(sum unplaced)" -eq 5 ]
  [ "$(unplaced_recs)" -eq 5 ]

  fresh; CC_DISPATCH_CEILING=5 STUB_WP_RC=4 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(unplaced_recs)" -eq 0 ]
}

@test "6 a JOURNAL-ONLY pass is exempt — --decide admits on paper and fires nothing BY DESIGN" {
  # Without this exemption the reconciliation would report a hole on every decide tick, and the
  # safe activation lane would look permanently broken. `reconciled:false` says which regime the
  # record was written under, so a reader never has to guess why unplaced is 0.
  seed_items 4
  fresh; CC_DISPATCH_CEILING=4 "$DISP" --decide >/dev/null 2>&1
  [ "$(sum admitted)" -eq 4 ]
  [ "$(sum unplaced)" -eq 0 ]
  [ "$(sum reconciled)" = false ]
  [ "$(unplaced_recs)" -eq 0 ]
  # ...and admitted_terminal is NULL, not a number. Deriving ADMITTED−UNPLACED here would report
  # "4 accounted for" over four ids nothing accounted for — a count from a denominator that was
  # never measured, which is the same defect as the cloud record journalling the on-box ceiling.
  [ "$(sum admitted_terminal)" = null ]
  # ...and a real firing pass says so, so the flag discriminates rather than being always-one-value
  fresh; CC_DISPATCH_CEILING=4 "$DISP" --once >/dev/null 2>&1
  [ "$(sum reconciled)" = true ]
}

@test "7 an unplaced id is NOT re-shaped as a failure — it takes no fault counter with it" {
  # Same discipline as the venue refusal: nothing refused these items and nothing broke, so folding
  # them into `failed` would feed thrash_map a fault record for a capacity artefact.
  seed_items 6
  fresh; CC_DISPATCH_CEILING=6 STUB_WP_PLAN=empty "$DISP" --once >/dev/null 2>&1
  [ "$(sum unplaced)" -eq 6 ]
  [ "$(sum failed)" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.action=="failed")]|length' "$C/idl.jsonl")" -eq 0 ]
}
