#!/usr/bin/env bats
# READINESS AS A PRECONDITION OF ADMISSION — W1 of the READINESS wave
# (docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md § "READINESS (2026-08-11)", R1–R3).
#
# WHAT IS UNDER TEST. Readiness has four properties and only one — premise currency — was checked at
# CONSUMPTION. The other three were checked by a BATCH, and a batch over a growing stream must be
# re-run forever: that treadmill is the one-time triage this repo keeps re-minting. W1 moves the
# check to the admission seam, keys the verdict on the TRUNK SHA rather than on age, and ships it
# advisory-first so the would-block rate can be measured before it becomes a wall.
#
# THE ONE ASSERTION THIS SUITE EXISTS FOR is case 7: 🚨 AN EMPTY PATH SET IS ALWAYS VOID. The naive
# reading walks straight into it — with no cited paths the intersection with any diff is empty, so
# "trunk did not move under this item" is TRUE and the item reads permanently ready. That sentence
# is vacuous, and a verdict that can never be falsified is the fail-open trap this stack keeps
# paying for. Case 8 is its MUTANT control, so a green case 7 credits the guard rather than the
# fixture (memory: per-site-mutation-attributes-coverage).
#
# CONTROLS. Every RED half replays the REAL pre-change artifact recovered with `git archive` from a
# PINNED sha — never a hand-typed approximation (memory: control-must-replay-the-real-artifact). The
# sha is pinned rather than `origin/main` for the reason the v2 suite gives: the moment this work
# lands, `origin/main` BECOMES the new version and every "the old tree fails this" assertion would
# invert and go red for the whole fleet. 76fc7eca is this branch's base and an ancestor of main
# forever, so the control stays the control.
#
# ⚠️ THE WHOLE-SUITE RED-PROOF IS THE WEAK KIND, AND SAYING SO IS THE POINT. Replayed against
# `git show origin/main:bin/cc-dispatch` + `:bin/cc-venue` in a scratch tree, 30 of 30 go RED — but
# they go red because `make_lib` cannot find `readiness_verdict` there and setup() refuses, i.e. it
# proves the MECHANISM is new, not that each assertion binds to the behaviour it names. What proves
# THAT is in-suite and per-site: the three MUTANTS (8 · 26 · 29), the two cases that run the real
# pre-fix binary inside a WORKING harness (6 · 23), and `scripts/bats-assert-liveness.py` reporting
# 0 dead assertions for this file. A reader should not have to infer that distinction.
#
# HERMETIC. $HOME is fixtured, every actuator is stubbed through cc-dispatch's env seams, and the
# git repo the verdict is computed against is a temp clone — nothing here reads or writes the
# operator's live ledger, live ~/.claude, or the real repo.

BASE_SHA="76fc7eca"   # immutable ancestor of origin/main; carries the pre-W1 cc-dispatch + cc-venue

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  VENUE="$REPO/bin/cc-venue"
  [ -f "$DISP" ] || skip "bin/cc-dispatch not found"
  [ -f "$VENUE" ] || skip "bin/cc-venue not found"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine"
  export HOME="$C/home"

  # the pre-change controls, recovered from git (never hand-edited)
  git -C "$REPO" archive "$BASE_SHA" bin/cc-dispatch bin/cc-venue bin/cc-eligible bin/cc-premise 2>/dev/null | tar -x -C "$C/pristine"
  PRISTINE="$C/pristine/bin/cc-dispatch"
  PRISTINE_VENUE="$C/pristine/bin/cc-venue"
  chmod +x "$PRISTINE" "$PRISTINE_VENUE" "$C/pristine/bin/cc-eligible" "$C/pristine/bin/cc-premise" 2>/dev/null || true
  # FAIL LOUD if the control could not be recovered: without this every RED half would run an absent
  # binary that writes nothing, and each "the old tree does NOT do this" assertion would pass
  # VACUOUSLY — the exact way a control silently stops being a control.
  if [ ! -x "$PRISTINE" ] || [ ! -x "$PRISTINE_VENUE" ]; then
    echo "cc-dispatch-readiness.bats: cannot recover the pristine controls from $BASE_SHA — the RED-proof cannot run." >&2
    return 1
  fi

  # ── the repo the verdict is computed AGAINST: a real clone with a real origin/main ─────────────
  mkdir -p "$C/up/bin" "$C/up/scripts"
  git init -q -b main "$C/up"
  echo a > "$C/up/bin/alpha.sh"; echo b > "$C/up/scripts/beta.sh"; echo z > "$C/up/scripts/other.sh"
  git -C "$C/up" add -A
  git -C "$C/up" -c user.email=t@t -c user.name=t commit -qm init
  git clone -q "$C/up" "$C/work"
  BASE0="$(git -C "$C/work" rev-parse origin/main)"

  # ── the ledger the path set is read out of ─────────────────────────────────────────────────────
  LEDGER="$C/backlog.jsonl"
  cat > "$LEDGER" <<'JSONL'
{"id":"aaaaaaaaaaaa","ts":"2026-08-01T00:00:00Z","event":"add","project":"proj","title":"fix bin/alpha.sh and beta.sh and docs/nope.md","source":"x"}
{"id":"bbbbbbbbbbbb","ts":"2026-08-01T00:00:00Z","event":"add","project":"proj","title":"investigate the flaky intermittent thing, no citation anywhere","source":"x"}
JSONL
  export CC_BACKLOG_FILE="$LEDGER"

  # ── stubs ─────────────────────────────────────────────────────────────────────────────────────
  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*) jq -cn --argjson n "\${STUB_LIVE:-0}" '[range(\$n)|{id:"c\(.)",status:"claimed"}]' ;;
      *) cat "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  done)   printf 'done %s\n'   "\$2" >> "$C/backlog.log" ;;
  venue)  printf 'venue %s\n'  "\$2" >> "$C/backlog.log" ;;
esac
exit 0
EOF
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; printf '%s' "\$2" > "$C/wave.json"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c '[ .[] | {id, account:"next3", fire_line:["--prompt-file","/dev/null"]} ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit 0
EOF
  # cc-venue stub — the two verbs cc-dispatch calls, each observable and each failable on demand.
  # \$STUB_PATHS is the ANSWER; \$STUB_PATHS_RC is how "could not ask" is expressed.
  cat > "$C/stubs/venue" <<EOF
#!/bin/bash
case "\$1" in
  paths)
    [ "\${STUB_PATHS_RC:-0}" = 0 ] || exit "\$STUB_PATHS_RC"
    [ -n "\${STUB_PATHS:-}" ] && printf '%s\n' "\${STUB_PATHS}"
    exit 0 ;;
  label) printf 'label %s\n' "\$2" >> "$C/venue.log"; exit "\${STUB_LABEL_RC:-0}" ;;
esac
exit 2
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn" "$C/stubs/venue"

  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_VENUE_BIN="$C/stubs/venue" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECT="proj" \
         CC_DISPATCH_REPO="$C/work" \
         CC_DISPATCH_PROJECTS_CONF="$C/absent.conf" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_WT_FRESH=off \
         CC_DISPATCH_SID="bats"

  # ── the LIB: the readiness functions EXTRACTED FROM THE SHIPPED FILE and executed, so the unit
  # cases replay the real artifact rather than a paraphrase of it.
  LIB="$C/lib.sh"
  make_lib "$DISP" "$LIB"
  seed_items 1
}

# extract <file> <fn> — ONE function body, verbatim. A plain `/^f() {/,/^}/` range is WRONG here and
# silently so: this file writes several helpers as ONE-LINERS (`now_iso() { …; }`), whose closing
# brace is not at column 0, so the range runs on to the next `^}` and swallows everything between —
# including the module-level `is_uint "$CEILING"` guard, which then dies on an unbound variable and
# takes every case with it. The one-liner is detected and taken alone.
extract() {
  local first
  first="$(grep -n "^$2() {" "$1" | head -1 | cut -d: -f1)"
  [ -n "$first" ] || return 1
  if sed -n "${first}p" "$1" | grep -qE '\}[[:space:]]*(#.*)?$'; then
    sed -n "${first}p" "$1"
  else
    sed -n "${first},/^}/p" "$1"
  fi
}

# make_lib <cc-dispatch path> <out> — every function the readiness verdict reaches, plus the globals
# it reads. A missing extraction would make a case run against an empty library and pass vacuously,
# so the guard below refuses to emit a library that lost one.
make_lib() {
  local src="$1" out="$2" f
  {
    echo 'set -uo pipefail'
    for f in now_iso die3 is_uint resolve_bin conf_repo project_repo \
             ready_trunk_sha ready_last_sha ready_paths ready_moved ready_relabel \
             readiness_verdict idl idl_readiness ready_rate_pct venue_label_new; do
      extract "$src" "$f" || { echo "make_lib: $f not found in $src" >&2; return 1; }
    done
    cat <<GLOBALS
IDL="\${CC_DISPATCH_IDL}"
PROJECT="proj"
PASS_ID="bats-pass"
READY_GATE="\${CC_DISPATCH_READY_GATE:-advisory}"
READY_MAX=6
READY_CHECKED=0; READY_VOID=0; READY_UNKNOWN=0
PROJECTS_CONF="\${CC_DISPATCH_PROJECTS_CONF}"
_self="${src}"
GLOBALS
  } > "$out"
  grep -q '^readiness_verdict() {' "$out" || {
    echo "make_lib: readiness_verdict was not extracted from $src — every unit case would pass vacuously" >&2
    return 1
  }
}
lib() { bash -c ". '$LIB'; $*"; }

# seed_items <n> [venuePlan] — n open rows with GENUINELY DISTINCT titles. Not cosmetic: the
# admission loop normalises a title by replacing every measurement with `#`, so "work 1"/"work 2"
# collapse to one INFERRED cluster and the second row defers as a cluster-sibling before readiness
# is ever reached — which silently halves every count this suite asserts.
seed_items() {
  jq -cn --argjson n "$1" --arg vp "${2-local}" \
    '[range(1;$n+1)|{id:("i"+(tostring)),project:"proj",status:"open",
       title:(["alpha bravo charlie","delta echo foxtrot","golf hotel india","juliet kilo lima"][.-1]),
       venuePlan:$vp,lastTs:"2026-08-01T00:00:00Z"}]' \
    > "$C/items.json"
}
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; : > "$C/venue.log"; rm -rf "$C/pages" "$C/wave.json" "$C/dispatch.lock"; }
# land <path> — move trunk by touching exactly one file, so "trunk moved UNDER this item" and
# "trunk moved elsewhere" are two different fixtures rather than two readings of one.
land() {
  echo "$RANDOM" >> "$C/up/$1"
  git -C "$C/up" add -A
  git -C "$C/up" -c user.email=t@t -c user.name=t commit -qm "touch $1"
  git -C "$C/work" fetch -q origin
}
rec() { jq -rs "[.[]|select(.action==\"readiness\"${1:-})]|length" "$C/idl.jsonl" 2>/dev/null || echo 0; }
dec() { jq -rs "[.[]|select(.action==\"decision\"${1:-})]|length" "$C/idl.jsonl" 2>/dev/null || echo 0; }
spawns() { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }

# ── cc-venue paths — the invalidation basis, read out of cc-premise's own extractor ───────────────

@test "1 paths prints the item's usable cited set — a bare basename resolves to its ONE trunk file" {
  run env CC_PREMISE_REPO="$C/work" "$VENUE" paths aaaaaaaaaaaa
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"bin/alpha.sh"* ]] || false
  [[ "$output" == *"scripts/beta.sh"* ]] || false   # cited bare as `beta.sh`
}

@test "2 CONTROL: a path-SHAPED token that is not on trunk is excluded — an empty intersection means something" {
  run env CC_PREMISE_REPO="$C/work" "$VENUE" paths aaaaaaaaaaaa
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"docs/nope.md"* ]] || false
}

@test "3 an item citing nothing exits 0 with ZERO lines — that is an ANSWER, not a failure" {
  run env CC_PREMISE_REPO="$C/work" "$VENUE" paths bbbbbbbbbbbb
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
}

@test "4 cc-premise unimportable ⇒ exit 4 UNKNOWN — never an empty path set" {
  run env CC_PREMISE_REPO="$C/work" CC_VENUE_PREMISE_BIN="$C/no-such-premise" "$VENUE" paths aaaaaaaaaaaa
  [ "$status" -eq 4 ] || false
  [[ "$output" == *"UNKNOWN"* ]] || false
}

@test "5 an unreadable repo ⇒ exit 4 UNKNOWN — a dead sensor may not convict every item in the store" {
  run env CC_PREMISE_REPO="$C/no-such-repo" "$VENUE" paths aaaaaaaaaaaa
  [ "$status" -eq 4 ] || false
  [[ "$output" == *"UNKNOWN, not an empty path set"* ]] || false
}

@test "6 RED: the pre-W1 cc-venue has no paths verb at all — this producer is new" {
  run env CC_PREMISE_REPO="$C/work" "$PRISTINE_VENUE" paths aaaaaaaaaaaa
  [ "$status" -eq 2 ] || false
}

# ── readiness_verdict — the conjunction, keyed on the trunk sha ───────────────────────────────────

@test "7 THE FAIL-OPEN TRAP: an EMPTY path set is VOID (cites-nothing), never always-fresh" {
  # An item citing nothing intersects no diff, so the naive reading calls it permanently ready.
  run env STUB_PATHS="" "$C/stubs/venue" paths i1
  [ "$status" -eq 0 ] && [ -z "$output" ] || false      # the fixture really does answer "nothing"
  STUB_PATHS="" run lib 'readiness_verdict i1 proj local ""'
  [ "$status" -eq 0 ] || false
  [[ "$output" == void* ]] || false
  [[ "$output" == *cites-nothing* ]] || false
}

@test "8 MUTANT for case 7: with the empty-set arm deleted the same fixture reads READY — the guard is what fails it" {
  # One mutant, one site. Deleting the `-z \$paths` arm is the minimal edit that re-opens the trap;
  # if case 7 still passed against this library the assertion would be crediting something else.
  MUT="$C/mutant.sh"
  sed 's/elif \[ -z "\$paths" \]; then/elif false; then/' "$LIB" > "$MUT"
  ! cmp -s "$LIB" "$MUT" || { echo "mutation did not apply — the control is inert" >&2; false; }
  STUB_PATHS="" run bash -c ". '$MUT'; readiness_verdict i1 proj local ''"
  [[ "$output" != *cites-nothing* ]] || false
}

@test "9 no prior verdict ⇒ void no-prior-verdict, and the basis sha is recorded so the NEXT pass can ask" {
  STUB_PATHS="bin/alpha.sh" run lib 'readiness_verdict i1 proj local ""'
  [[ "$output" == void* ]] || false
  [[ "$output" == *no-prior-verdict* ]] || false
  [[ "$output" == *"$BASE0"* ]] || false   # readyAt = today's trunk sha: self-repairing, not a stall
}

@test "10 trunk moved UNDER a cited path ⇒ void trunk-moved, whatever the item's age" {
  lib "idl_readiness i1 ready '' $BASE0 proj"
  land bin/alpha.sh
  STUB_PATHS="bin/alpha.sh" run lib 'readiness_verdict i1 proj local ""'
  [[ "$output" == void* ]] || false
  [[ "$output" == *trunk-moved* ]] || false
}

@test "11 trunk moved ELSEWHERE ⇒ READY — the verdict is keyed on the path intersection, never on a clock" {
  lib "idl_readiness i1 ready '' $BASE0 proj"
  land scripts/other.sh                     # a real trunk move that this item does not cite
  [ "$(git -C "$C/work" rev-parse origin/main)" != "$BASE0" ] || false   # the move really happened
  STUB_PATHS="bin/alpha.sh" run lib 'readiness_verdict i1 proj local ""'
  [[ "$output" == ready* ]] || false
  [[ "$output" == *"$BASE0"* ]] || false    # the basis is PINNED, not rolled forward on every read
}

@test "12 an unlabelled venue ⇒ void venue-unlabelled, and the REPAIR ran — re-derived in place" {
  run lib 'readiness_verdict i1 proj "" ""'
  [[ "$output" == void* ]] || false
  [[ "$output" == *venue-unlabelled* ]] || false
  grep -q '^label i1$' "$C/venue.log" || false
}

@test "13 an INFERRED cluster is unresolved; a DECLARED one is not — only a filer can say five rows are one effort" {
  STUB_PATHS="bin/alpha.sh" run lib 'readiness_verdict i1 proj local inferred'
  [[ "$output" == void* ]] || false
  [[ "$output" == *cluster-unresolved* ]] || false
  STUB_PATHS="bin/alpha.sh" run lib 'readiness_verdict i1 proj local declared'
  [[ "$output" != *cluster-unresolved* ]] || false
}

@test "14 cc-venue unreachable ⇒ UNKNOWN paths-unreadable, never void — a dead sensor cannot block" {
  STUB_PATHS_RC=4 run lib 'readiness_verdict i1 proj local ""'
  [[ "$output" == unknown* ]] || false
  [[ "$output" == *paths-unreadable* ]] || false
}

@test "15 the repair is NOT run for cites-nothing — a re-derivation cannot make an item cite a file" {
  STUB_PATHS="" run lib 'readiness_verdict i1 proj local ""'
  [[ "$output" == *cites-nothing* ]] || false
  [ ! -s "$C/venue.log" ] || false
}

# ── the admission seam ────────────────────────────────────────────────────────────────────────────

@test "30 a DRY pass does not repair — the repair writes to the operator live ledger" {
  seed_items 1 ""                       # unlabelled ⇒ the repair arm is the one that would fire
  fresh; "$DISP" --dry-run >/dev/null 2>&1
  [ ! -s "$C/venue.log" ] || false
  # positive control on the same fixture: the WRITING pass does repair, so the absence above is
  # about the dry lane and not about an unreachable arm.
  fresh; env STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  grep -q '^label i1$' "$C/venue.log" || false
}

@test "16 --dry-run prints a readiness verdict per candidate AND admits exactly as before" {
  seed_items 2
  fresh; run env STUB_PATHS="bin/alpha.sh" "$DISP" --dry-run
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | grep -c '^READY: i')" -eq 2 ] || false
  [[ "$output" == *"PLAN: 2 dispatchable"* ]] || false
  [[ "$output" == *"2 admit, 0 defer"* ]] || false      # advisory changes NOTHING about admission
  [ ! -s "$C/idl.jsonl" ] || false                       # a dry pass still writes nothing
}

@test "17 ADVISORY: a void item is journalled AND admitted anyway" {
  seed_items 1
  fresh; env STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(rec ' and .state=="void"')" -eq 1 ] || false
  [ "$(rec ' and .id=="i1" and .reason=="cites-nothing"')" -eq 1 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 1 ] || false
  [ "$(spawns)" -eq 1 ] || false
}

@test "18 ENFORCE: a void item DEFERS as not-ready — never dropped, never marked done" {
  seed_items 1
  fresh; env CC_DISPATCH_READY_GATE=enforce STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="defer" and (.reason|startswith("not-ready:"))')" -eq 1 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 0 ] || false
  [ "$(spawns)" -eq 0 ] || false
  ! grep -q '^done ' "$C/backlog.log" || false          # R3: a gate that shreds work is worse
  ! grep -q '^claim ' "$C/backlog.log" || false
}

@test "19 ENFORCE: the slot a void item did not spend goes to the NEXT candidate, it is not lost" {
  # i1 cites nothing (void); i2 is handed a path AND a prior basis, so it is ready. One free slot.
  cat > "$C/stubs/venue" <<EOF
#!/bin/bash
case "\$1" in
  paths) [ "\$2" = i1 ] || printf 'bin/alpha.sh\n'; exit 0 ;;
  label) printf 'label %s\n' "\$2" >> "$C/venue.log"; exit 0 ;;
esac
exit 2
EOF
  chmod +x "$C/stubs/venue"
  seed_items 2
  fresh
  lib "idl_readiness i2 ready '' $BASE0 proj"
  CC_DISPATCH_READY_GATE=enforce CC_DISPATCH_CEILING=5 CC_DISPATCH_MAX_SPAWN=1 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .id=="i1" and .verdict=="defer"')" -eq 1 ] || false
  [ "$(dec ' and .id=="i2" and .verdict=="admit"')" -eq 1 ] || false
}

@test "20 the summary carries the would-block RATE over a stated denominator — the flip is a measurement" {
  seed_items 2
  fresh; env STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  run jq -rs '[.[]|select(.action=="summary")][0]|[.ready_gate,(.ready_checked|tostring),(.ready_void|tostring),(.ready_unknown|tostring),(.ready_would_block_pct|tostring)]|join("|")' "$C/idl.jsonl"
  [ "$output" = "advisory|2|2|0|100" ] || false
  # …and it is a REAL number over a REAL population, not 0-because-unreachable: the same field reads
  # 0% when the same harness feeds ready items, which is what makes 100 above evidence of anything.
  fresh
  lib "idl_readiness i1 ready '' $BASE0 proj"; lib "idl_readiness i2 ready '' $BASE0 proj"
  env STUB_PATHS="bin/alpha.sh" "$DISP" --once >/dev/null 2>&1
  run jq -rs '[.[]|select(.action=="summary")][0]|(.ready_would_block_pct|tostring)' "$C/idl.jsonl"
  [ "$output" = "0" ] || false
}

@test "21 READY_MAX bounds the checks — past the budget the verdict is UNKNOWN, which never blocks even in enforce" {
  seed_items 3
  fresh; env CC_DISPATCH_READY_GATE=enforce CC_DISPATCH_READY_MAX=1 CC_DISPATCH_CEILING=9 \
    CC_DISPATCH_MAX_SPAWN=3 STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(rec ' and .reason=="budget-spent"')" -ge 1 ] || false
  [ "$(rec ' and .state=="void"')" -eq 1 ] || false        # exactly ONE real check was spent
  [ "$(dec ' and .verdict=="admit"')" -ge 1 ] || false     # budget-spent items still admitted
}

@test "22 off computes no verdict at all — the incumbent shape is one env var away" {
  seed_items 2
  fresh; env CC_DISPATCH_READY_GATE=off STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(rec)" -eq 0 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 2 ] || false
  run jq -rs '[.[]|select(.action=="summary")][0]|(.ready_checked|tostring)' "$C/idl.jsonl"
  [ "$output" = "0" ] || false
}

@test "23 RED: the pre-W1 dispatcher journals no readiness record and no ready_* summary fields" {
  seed_items 2
  fresh; env STUB_PATHS="" "$PRISTINE" --once >/dev/null 2>&1
  [ -s "$C/idl.jsonl" ] || false                            # the control DID run and DID journal
  [ "$(rec)" -eq 0 ] || false
  run jq -rs '[.[]|select(.action=="summary")][0]|has("ready_would_block_pct")' "$C/idl.jsonl"
  [ "$output" = false ] || false
}

# ── cc-venue's missing caller: the write path ─────────────────────────────────────────────────────

# ── the field split at the seam ───────────────────────────────────────────────────────────────────
# FOUND BY THIS SUITE, not reasoned about: adding two fields to the admission loop's delimited read
# turned an invisible property of tab into a silent column shift. Tab is IFS *whitespace*, so bash
# `read` collapses a RUN of them — a row with no cluster key delivered its `venuePlan` into
# `$dclus`, and two unrelated items then "clustered" on the string `local`. The dispatcher deferred
# real work as a phantom sibling and only ONE readiness verdict was ever computed. Both halves are
# pinned, because the wrong behaviour was a plausible-looking pass.

@test "28 an item with NO cluster key does not inherit its neighbour's field — empty middles survive the split" {
  seed_items 2
  fresh; env STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .reason=="cluster-sibling"')" -eq 0 ] || false   # neither item clusters at all
  [ "$(dec ' and .verdict=="admit"')" -eq 2 ] || false
  [ "$(rec)" -eq 2 ] || false                                     # …so BOTH get a readiness verdict
  [ "$(rec ' and .reason=="venue-unlabelled"')" -eq 0 ] || false  # the label was read, not eaten
}

@test "29 MUTANT for case 28: put the tab back and the same fixture invents a cluster — the separator is what prevents it" {
  MUT="$C/disp-tab"
  sed "s/IFS=\"\$(printf '\\\\037')\" read -r did/IFS=\"\$(printf '\\\\t')\" read -r did/; s/--arg s \"\$(printf '\\\\037')\"/--arg s \"\$(printf '\\\\t')\"/" "$DISP" > "$MUT"
  chmod +x "$MUT"
  ! cmp -s "$DISP" "$MUT" || { echo "mutation did not apply — the control is inert" >&2; false; }
  seed_items 2
  fresh; env STUB_PATHS="" "$MUT" --once >/dev/null 2>&1
  [ "$(dec ' and .reason=="cluster-sibling"')" -eq 1 ] || false
}

# THE TWO CALLERS ARE ASSERTED APART, and this is not fussiness. cc-venue now has TWO callers — the
# write-path labeller (5a) and the admission-time repair (5b) — and BOTH end in `cc-venue label`, so
# the stub's log cannot tell them apart. An absence assertion read off that log would be answering a
# different question from the one it asks. The write-path labeller writes its OWN journal note, so
# these cases key on that: one caller, one signal.
wnote() { jq -rs "[.[]|select(.action==\"note\" and (.detail|test(\"venue labelled on write\")) and (.detail|startswith(\"$1\")))]|length" "$C/idl.jsonl" 2>/dev/null || echo 0; }
seed_unlabelled() { # <id> <lastTs>
  jq -cn --arg id "$1" --arg ts "$2" \
    '[{id:$id,project:"proj",status:"open",title:"a singular unrepeated subject line",lastTs:$ts}]' > "$C/items.json"
}
NOW_TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

@test "24 a row written INSIDE the window is labelled on the decide pass — cc-venue finally has a caller" {
  seed_unlabelled new1 "$(NOW_TS)"
  fresh; "$DISP" --decide >/dev/null 2>&1
  [ "$(wnote new1)" -eq 1 ] || false
}

@test "25 POPULATION BOUND: an OLD unlabelled row is NOT labelled on write — the trickle cannot become a sweep" {
  seed_unlabelled old1 "2026-08-01T00:00:00Z"
  fresh; "$DISP" --decide >/dev/null 2>&1
  [ "$(wnote old1)" -eq 0 ] || false
  # …and the SAME harness demonstrably observes the note when the row is new, so this absence is
  # evidence rather than a broken probe (memory: absence-alarm-needs-existence-evidence).
  seed_unlabelled old1 "$(NOW_TS)"
  fresh; "$DISP" --decide >/dev/null 2>&1
  [ "$(wnote old1)" -eq 1 ] || false
}

@test "26 MUTANT for case 25: widen the window to forever and the OLD row IS labelled — the bound is what excludes it" {
  seed_unlabelled old1 "2026-08-01T00:00:00Z"
  fresh; env CC_DISPATCH_VENUE_NEW_WINDOW_S=999999999 "$DISP" --decide >/dev/null 2>&1
  [ "$(wnote old1)" -eq 1 ] || false
}

@test "27 the labeller rides the WRITE path, not the clock — a --once cron tick runs no labeller" {
  seed_unlabelled new1 "$(NOW_TS)"
  fresh; env STUB_PATHS="" "$DISP" --once >/dev/null 2>&1
  [ "$(wnote new1)" -eq 0 ] || false
  # The admission-time repair is what covers an unlabelled row there, and it IS reached — so the
  # absence above is about the labeller, not about cc-venue being unreachable in this mode.
  [ "$(rec ' and .id=="new1" and .reason=="venue-unlabelled"')" -eq 1 ] || false
  grep -q '^label new1$' "$C/venue.log" || false
}
