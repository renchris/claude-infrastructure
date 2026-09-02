#!/usr/bin/env bats
# cc-dispatch MULTI-PROJECT COVERAGE (backlog item f7abcbdee98c).
#
# THE DEFECT UNDER TEST. The pull filtered `.project == $PROJECT` — the ONE project the launchd plist
# pins. An open item in any other project was not deferred, not skipped, not decided: it was
# INVISIBLE, and therefore indistinguishable from an empty backlog. Measured live 2026-07-29: 19 such
# items (doc_classifier 7, reso-management-app 7, "/" 5), the oldest undrained for 8 days — and the 5
# OLDEST open items in the entire ledger were among them.
#
# PAIRED RED-PROOF, same discipline as tests/cc-dispatch-v2.bats: every behavioural test runs the
# same fixture against the shipped bin/cc-dispatch AND against the PRISTINE pre-change tree recovered
# with `git archive` from a pinned immutable sha, and the pristine half must FAIL the assertion the
# new half passes. The control IS the artifact, byte for byte — never a hand-typed approximation
# (memory: control-must-replay-the-real-artifact).
#
# WHY A PINNED SHA: once this lands, origin/main:bin/cc-dispatch BECOMES the new version and every
# "the old tree does not do this" assertion would invert and go red fleet-wide. 67c86d89 is this
# branch's merge-base and an ancestor of origin/main forever.
#
# THE TWO CLAIMS THAT MATTER MOST, because they are what makes multi-project dispatch SAFE rather
# than merely wider:
#   · test "repo per item" — a foreign item's worktree is cut from ITS OWN repo. The pre-change
#     warm_worktree hardcoded `CC_DISPATCH_REPO:-$HOME/Development/claude-infrastructure`, so a
#     doc_classifier item would have been provisioned from THIS repo and a worker fired into it
#     holding this repo's standing-land authorization. That is worse than undrained.
#   · test "uncovered items are LOUD" — a project with no conf row still gets a per-pass record.
#     Coverage that fails silently is the defect; coverage that fails loudly is a work item.
#
# ABSENCE ASSERTIONS CARRY A POSITIVE CONTROL (memory: absence-alarm-needs-existence-evidence): the
# "no uncovered records" and "no spawn" halves are only evidence because the same harness is shown
# observing those effects when the condition is reversed.

BASE_SHA="67c86d89"   # immutable ancestor of origin/main; carries the pre-change bin/cc-dispatch

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

  git -C "$REPO" archive "$BASE_SHA" bin/cc-dispatch 2>/dev/null | tar -x -C "$C/pristine"
  PRISTINE="$C/pristine/bin/cc-dispatch"
  chmod +x "$PRISTINE" 2>/dev/null || true
  # FAIL LOUD if the control could not be recovered: an absent binary writes nothing, so every RED
  # half would pass VACUOUSLY and the suite would silently stop being a proof.
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-projects.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
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
  # wave-plan stub: places EXACTLY what it was handed, and emits the SAME fire_line shape the real
  # planner does — a --prompt-file the actuator must compose and a --cwd it must provision. Both are
  # what the per-item repo/brief assertions read.
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; printf '%s' "\$2" > "$C/wave.json"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt"),"--cwd",(\$d+"/wt/wt-"+.id)] } ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit "\${STUB_SPAWN_RC:-0}"
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"

  CONF="$C/dispatch-projects.conf"
  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECTS_CONF="$CONF" \
         CC_DISPATCH_PROJECT="proj-a" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_SID="bats"
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────
# seed_items <project:count> ... — one open item per count, ids "<project>-<n>", ts ascending in the
# order given so the S7 key (thrash ASC, then oldest ts) is deterministic across projects.
seed_items() {
  local spec p n i out="[]" t=1
  for spec in "$@"; do
    p="${spec%%:*}"; n="${spec##*:}"
    for ((i=1; i<=n; i++)); do
      out="$(printf '%s' "$out" | jq -c --arg p "$p" --arg id "$p-$i" --arg ts "2026-07-2${t}T00:00:0${i}Z" \
        '. + [{id:$id, project:$p, status:"open", title:("work for "+$p), ts:$ts}]')"
    done
    t=$((t + 1))
  done
  printf '%s' "$out" > "$C/items.json"
}
conf() { printf '%s\n' "$@" > "$CONF"; }
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; rm -rf "$C/pages" "$C/wave.json" "$C/dispatch.lock" "$C/wt" "$C"/brief-*.txt; }

# dec [extra-predicate] → count of decision records. Interpolated INSIDE select(...): appended after
# the closing paren it becomes a truthiness expression that counts the WHOLE file.
dec()      { jq -rs "[.[]|select(.action==\"decision\"${1:-})]|length" "$C/idl.jsonl" 2>/dev/null || echo 0; }
# projects  = every project this pass said ANYTHING about (queued or uncovered).
# qprojects = only the projects actually IN THE QUEUE (admit/defer). The distinction is the whole
# point of the change: an uncovered project is now VISIBLE (so it appears in `projects`) while still
# not being dispatched (so it must NOT appear in `qprojects`). Asserting coverage with the wrong one
# of these passes vacuously in both directions.
projects()  { jq -rs '[.[]|select(.action=="decision")|.project]|sort|unique|join(",")' "$C/idl.jsonl" 2>/dev/null; }
qprojects() { jq -rs '[.[]|select(.action=="decision" and .verdict!="skip")|.project]|sort|unique|join(",")' "$C/idl.jsonl" 2>/dev/null; }
# `grep -c .` prints 0 AND exits 1 on an empty file, so a bare `|| echo 0` emits "0\n0" and every
# numeric comparison dies with "integer expression expected".
spawns()   { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }

# same_repo <worktree-path> <repo-path> — is that worktree backed by that repo?
#
# Both sides are resolved PHYSICALLY before comparing. $BATS_TEST_TMPDIR lives under /var/folders,
# which on macOS is a symlink to /private/var/folders: git reports the resolved form while the
# fixture holds the unresolved one, so a raw string compare asserts $TMPDIR's SHAPE rather than the
# repo identity and fails on a correct result (memory: two-normal-forms-of-one-path).
same_repo() {
  local got want
  got="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  got="${got%/.git}"; got="${got%/}"
  got="$(cd "$got" 2>/dev/null && pwd -P)" || return 1
  want="$(cd "$2" 2>/dev/null && pwd -P)" || return 1
  [ "$got" = "$want" ]
}

# mkrepo <project> → a real git repo, so warm_worktree's `rev-parse --git-dir` gate and its
# `worktree add` are exercised for real rather than stubbed away (that gate is what refuses a
# mis-resolved repo).
#
# The remote refs are REQUIRED, not decoration: warm_worktree branches off the repo's origin/HEAD
# (falling back to origin/main), so a fixture repo with no remote-tracking refs makes `worktree add`
# fail and EVERY spawn assertion here would read 0 — a fixture defect that looks exactly like the bug
# under test. `refs/remotes/origin/HEAD` is set explicitly so the per-repo base resolution is what
# actually gets exercised.
mkrepo() {
  local d="$C/repos/$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main 2>/dev/null
  git -C "$d" -c user.email=b@x -c user.name=b commit -q --allow-empty -m init 2>/dev/null
  git -C "$d" update-ref refs/remotes/origin/main HEAD 2>/dev/null
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main 2>/dev/null
  printf '%s' "$d"
}

# ── coverage: the set spans projects ──────────────────────────────────────────────────────────────
@test "coverage: items in EVERY conf-declared project are decided; the PRISTINE tree decides only the pinned one" {
  seed_items proj-a:2 proj-b:3 proj-c:1
  conf "proj-b  repo=$C/repos/proj-b" "proj-c  repo=$C/repos/proj-c"

  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 6 ] || false
  [ "$(projects)" = "proj-a,proj-b,proj-c" ] || false
  # every foreign item is a REAL recorded deferral, not a skip: it is in the queue.
  [ "$(dec ' and .verdict=="defer" and .project=="proj-b"')" -eq 3 ] || false
  [ "$(dec ' and .verdict=="defer" and .project=="proj-c"')" -eq 1 ] || false

  # RED: the pre-change filter saw ONLY proj-a. The other 4 items produced no record of any kind —
  # not deferred, not skipped: invisible.
  fresh; CC_DISPATCH_CEILING=0 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(dec)" -eq 2 ] || false
  [ "$(projects)" = "proj-a" ] || false
}

@test "coverage: CC_DISPATCH_PROJECT is unioned in unconditionally — a conf that omits it cannot un-cover the pinned project" {
  seed_items proj-a:2 proj-b:1
  conf "proj-b  repo=$C/repos/proj-b"          # deliberately no proj-a row
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .project=="proj-a"')" -eq 2 ] || false
}

@test "coverage: an ABSENT conf is byte-identical to the pre-change behaviour (single pinned project)" {
  seed_items proj-a:2 proj-b:3
  rm -f "$CONF"
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(qprojects)" = "proj-a" ] || false
  local new; new="$(dec ' and .verdict!="skip"')"
  fresh; CC_DISPATCH_CEILING=0 "$PRISTINE" --once >/dev/null 2>&1
  [ "$new" -eq "$(dec)" ] || false
}

@test "coverage: CC_DISPATCH_PROJECT accepts a LIST (comma or space separated)" {
  seed_items proj-a:1 proj-b:1 proj-c:1
  rm -f "$CONF"
  fresh; CC_DISPATCH_PROJECT="proj-a,proj-b" CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(qprojects)" = "proj-a,proj-b" ] || false
  fresh; CC_DISPATCH_PROJECT="proj-a proj-c" CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(qprojects)" = "proj-a,proj-c" ] || false
}

# ── the fail-loud half: not covered ⇒ recorded, never silent ──────────────────────────────────────
@test "uncovered: an undeclared project's open items are recorded skip/project-not-dispatched every pass; the PRISTINE tree records NOTHING for them" {
  seed_items proj-a:1 proj-zz:4
  conf "proj-a  repo=$C/repos/proj-a"

  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="skip" and .reason=="project-not-dispatched"')" -eq 4 ] || false
  [ "$(dec ' and .verdict=="skip" and .project=="proj-zz"')" -eq 4 ] || false
  # it is a SKIP, not a deferral: an undeclared project is not in the queue, and the record says so.
  [ "$(dec ' and .verdict=="defer" and .project=="proj-zz"')" -eq 0 ] || false
  # and the summary counts them, so a pass total can never read as "nothing to see"
  [ "$(jq -rs '[.[]|select(.action=="summary")][0].skipped' "$C/idl.jsonl")" -eq 4 ] || false

  fresh; CC_DISPATCH_CEILING=0 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(dec ' and .project=="proj-zz"')" -eq 0 ] || false
  [ "$(dec ' and .reason=="project-not-dispatched"')" -eq 0 ] || false
}

@test "uncovered POSITIVE CONTROL: with EVERY project declared, zero project-not-dispatched records are written" {
  seed_items proj-a:1 proj-zz:4
  conf "proj-a  repo=$C/repos/proj-a" "proj-zz  repo=$C/repos/proj-zz"
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .reason=="project-not-dispatched"')" -eq 0 ] || false
  [ "$(dec ' and .verdict=="defer"')" -eq 5 ] || false     # the harness DOES see these 5 as queued
}

@test "uncovered: a skip= row is a DECLARATION, not dispatch — its items still surface as uncovered" {
  seed_items proj-a:1 proj-skipme:2
  conf "proj-a  repo=$C/repos/proj-a" "proj-skipme  skip=no landing rails"
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .project=="proj-skipme" and .verdict=="skip"')" -eq 2 ] || false
  [ "$(dec ' and .project=="proj-skipme" and .verdict=="defer"')" -eq 0 ] || false
}

@test "uncovered: a malformed (path-shaped) dispatchable label is REFUSED, so \"/\" can never be a dispatch target" {
  seed_items proj-a:1
  # the live corrupt producer labels, as they actually appear in the ledger
  printf '%s\n' "proj-a  repo=$C/repos/proj-a" "/  repo=/" "/tmp/wt-x  repo=/tmp/wt-x" > "$CONF"
  fresh
  run env CC_DISPATCH_CEILING=0 "$DISP" --once
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | grep -q "refusing a malformed dispatchable project label" || false
  # and the refusal is total: the label never enters the QUEUE
  [ "$(qprojects)" = "proj-a" ] || false
}

@test "conf parse: an inline # comment after repo= is stripped; an EMPTY repo= is not a declaration" {
  seed_items proj-b:1 proj-c:1
  local rb; rb="$(mkrepo proj-b)"
  conf "proj-b  repo=$rb   # the trailing note a human writes" "proj-c  repo="
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  # comment stripped ⇒ the row IS a declaration and its item is queued
  [ "$(dec ' and .project=="proj-b" and .verdict=="defer"')" -eq 1 ] || false
  # empty value ⇒ NOT a declaration. It must stay LOUD rather than silently falling through to the
  # ~/Development/<project> convention, which would dispatch a project nobody declared.
  [ "$(dec ' and .project=="proj-c" and .verdict=="skip" and .reason=="project-not-dispatched"')" -eq 1 ] || false
}

@test "conf parse: an unreadable conf degrades to the pinned project alone — narrower, never a wider blind fire" {
  seed_items proj-a:1 proj-b:1
  # THE UNREADABILITY IS A DANGLING SYMLINK, NOT A MODE BIT (ported from tests/cc-venue.bats:186,
  # 2026-08-29, which fixed the identical defect one file over). Mode bits do not apply to uid 0, so
  # under root `chmod 000` leaves the conf READ FINE: proj-b parses, the dispatch set is WIDER than
  # the pinned project, and the case fails while the behaviour it guards is correct. It did not skip
  # under root, it INVERTED — and every cloud dispatch of this repo runs as root, so this reds the
  # land gate for any diff whose smoke scope reaches bin/cc-dispatch, a false RED about the machine
  # wearing a verdict about the diff (the 6-vs-9 confusion the land pipeline exists to keep apart).
  #
  # `[ -r ]` FOLLOWS the link, and no uid is exempt from a target that does not exist — so the
  # construction means the same thing for root and for the operator. It is also the SAME branch the
  # mode bit was reaching for (conf_rows' `[ -r "$PROJECTS_CONF" ] || return 0` guard), which a
  # directory would NOT have been: `[ -r ]` is true of a readable directory, and the degrade would
  # then come from awk failing further down. Keeping the branch is the point of the spelling.
  ln -s "$BATS_TEST_TMPDIR/no-such-conf-target" "$CONF"
  [ ! -r "$CONF" ] || { echo "fixture broken: the conf is still readable as uid $(id -u)"; false; }
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  rm -f "$CONF"
  [ "$(qprojects)" = "proj-a" ] || false
  [ "$(dec ' and .project=="proj-b" and .verdict=="skip"')" -eq 1 ] || false
}

# ── the safety half: the repo is resolved PER ITEM ────────────────────────────────────────────────
@test "repo per item: a foreign item's worktree is cut from ITS OWN repo — the PRISTINE tree cuts every one from claude-infrastructure" {
  seed_items proj-b:1
  local rb; rb="$(mkrepo proj-b)"
  conf "proj-b  repo=$rb"
  # the pre-change hardcoded fallback, made real so the control can actually take it
  local rci; rci="$(mkrepo claude-infrastructure)"
  mkdir -p "$HOME/Development"; ln -sfn "$rci" "$HOME/Development/claude-infrastructure"

  fresh; CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false
  # the worktree exists AND belongs to proj-b's repo, not to claude-infrastructure
  [ -d "$C/wt/wt-proj-b-1" ] || false
  same_repo "$C/wt/wt-proj-b-1" "$rb" || false

  # RED: the pre-change actuator resolved ONE global repo. Point CC_DISPATCH_PROJECT at proj-b so the
  # old filter admits the item at all, and its worktree is cut from claude-infrastructure — a worker
  # fired into the wrong tree.
  fresh; CC_DISPATCH_PROJECT=proj-b CC_DISPATCH_CEILING=6 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false
  same_repo "$C/wt/wt-proj-b-1" "$rci" || false
}

@test "repo per item: an UNRESOLVABLE repo refuses and reopens — never a fire into the wrong tree" {
  seed_items proj-b:1
  conf "proj-b  repo=$C/repos/does-not-exist"
  fresh
  run env CC_DISPATCH_CEILING=6 "$DISP" --once
  [ "$(spawns)" -eq 0 ] || false
  grep -q '^reopen proj-b-1$' "$C/backlog.log" || false
  [ "$(jq -rs '[.[]|select(.action=="failed")]|length' "$C/idl.jsonl")" -eq 1 ] || false
  printf '%s' "$output" | grep -q "declare its repo= in" || false
}

@test "repo per item: CC_DISPATCH_REPO overrides the PINNED project only — it cannot speak for a foreign one" {
  seed_items proj-a:1 proj-b:1
  local rb rx; rb="$(mkrepo proj-b)"; rx="$(mkrepo override)"
  # proj-a gets a real repo too, for the SIDE EFFECT only: without one the override could "win"
  # merely because the convention path does not exist, which would prove nothing. Its path is never
  # read — the assertion is that proj-a resolves to $rx, not to its own repo.
  mkrepo proj-a >/dev/null
  conf "proj-b  repo=$rb"                      # proj-a has no row → CC_DISPATCH_REPO applies to it
  fresh; CC_DISPATCH_REPO="$rx" CC_DISPATCH_CEILING=6 CC_DISPATCH_MAX_SPAWN=2 "$DISP" --once >/dev/null 2>&1
  same_repo "$C/wt/wt-proj-a-1" "$rx" || false
  same_repo "$C/wt/wt-proj-b-1" "$rb" || false
}

# ── the brief names the item's OWN project and its REAL rails ─────────────────────────────────────
@test "brief: rails are read from the project — /ship is promised only where .claude/commands/ship.md exists" {
  seed_items proj-b:1 proj-c:1
  local rb rc; rb="$(mkrepo proj-b)"; rc="$(mkrepo proj-c)"
  mkdir -p "$rb/.claude/commands"; printf 'ship\n' > "$rb/.claude/commands/ship.md"
  conf "proj-b  repo=$rb" "proj-c  repo=$rc"

  fresh; CC_DISPATCH_CEILING=6 CC_DISPATCH_MAX_SPAWN=2 "$DISP" --once >/dev/null 2>&1
  grep -q 'land ONLY via the project-local /ship' "$C/brief-proj-b-1.txt" || false
  # proj-c has NO ship rail: the brief must NOT name one, and must say what to do instead
  ! grep -q 'via the project-local /ship' "$C/brief-proj-c-1.txt" || false
  grep -q 'NO /ship rail' "$C/brief-proj-c-1.txt" || false
  # each brief names its OWN project, never the pinned one
  grep -q 'project proj-b' "$C/brief-proj-b-1.txt" || false
  grep -q 'project proj-c' "$C/brief-proj-c-1.txt" || false

  # RED: the pre-change brief hardcoded the /ship rail for every project and labelled every item with
  # the pass's pinned project.
  fresh; CC_DISPATCH_PROJECT=proj-c CC_DISPATCH_CEILING=6 "$PRISTINE" --once >/dev/null 2>&1
  grep -q 'land ONLY via the project-local /ship' "$C/brief-proj-c-1.txt" || false
}

# ── the brief tells the worker to re-check the item against TRUNK before it reads anything ───────
@test "brief: the FIRST STEP is a content check against origin/main — a stale premise reads green in a stale tree" {
  # BACKLOG 6110fc45141e. A worker was fired into a worktree 735 commits behind trunk; the post-land
  # RED it carried reproduced FAITHFULLY there, because the fix had landed on trunk eight days
  # earlier and was absent from that tree. Failure live, file matched, diagnosis correct — and the
  # diff would have REVERTED two landed generalisations. The fire-time gates now make the STALE TREE
  # impossible; this rail covers the half that is not a git question at all: a tree that is perfectly
  # fresh while the ITEM is stale, its cure having landed while the row sat in the queue. Both end in
  # a diff that reverts trunk, so the worker is told to re-check at CONSUMPTION either way.
  seed_items proj-b:1
  local rb; rb="$(mkrepo proj-b)"; conf "proj-b  repo=$rb"
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1

  grep -q 'FIRST STEP — read what this item cites on TRUNK, never in your own tree' "$C/brief-proj-b-1.txt" || false
  # the exact command, and the item's OWN repo in it — a rail naming no command is a wish
  grep -q "git -C $rb fetch origin -q && git rev-list --count HEAD..origin/main" "$C/brief-proj-b-1.txt" || false
  grep -q "git show origin/main:<path>" "$C/brief-proj-b-1.txt" || false
  # and the disposition when the check FIRES: close it on trunk's sha, never re-derive the cure
  grep -q 'If the cure is already on trunk, the item is DONE' "$C/brief-proj-b-1.txt" || false
  # NO BACKTICK EXECUTED AT COMPOSE TIME: these lines are double-quoted shell strings, so a backtick
  # in the rail would have substituted a COMMAND and written its output into the worker's brief.
  ! grep -q '`' "$C/brief-proj-b-1.txt" || false

  # RED: the pre-change tree composes the same brief with no such step, so a worker reads its own
  # tree first and has nothing telling it not to. PINNED to proj-b, because that tree dispatches
  # only the pinned project (test 1) — without the pin it would compose nothing and the absence
  # assertion below would pass for the wrong reason.
  fresh; CC_DISPATCH_PROJECT=proj-b CC_DISPATCH_CEILING=6 "$PRISTINE" --once >/dev/null 2>&1
  [ -s "$C/brief-proj-b-1.txt" ] || false           # positive control: it DID compose a brief
  ! grep -q 'FIRST STEP' "$C/brief-proj-b-1.txt" || false
}

# ── the rail's trunk reads are PRECEDED by the horizon check that makes them answerable ──────────
@test "brief: the deepen precondition comes BEFORE the trunk reads — a shallow clone answers all three wrong and silently" {
  # BACKLOG_DRAIN_24_7 § "the fourth lock" + its 2026-09-01 addendum. The rail above tells the
  # worker to settle the item against trunk before writing anything. A dispatched worker's checkout
  # arrives SHALLOW at depth 50, and all three prescribed reads then answer from inside that horizon
  # in ONE direction — landed reads as never-landed — while reporting nothing about the truncation:
  # `merge-base --is-ancestor` exits 1 both for "no" and for "I cannot see that far", and
  # `git log <sha>..origin/main` prints nothing for both. So the rail's own cure inverts into the
  # hazard it exists to close: the worker re-derives a landed fix and the diff REVERTS trunk.
  # Measured twice on ONE row (564d151b76e5): 11 of its 13 commits were re-derivation of a cure
  # already on trunk, stranded across 11 branches. cloud-venue-provision.sh carries the correct arm
  # and never runs in that VM — the brief is the only surface that reaches the worker in time.
  seed_items proj-b:1
  local rb; rb="$(mkrepo proj-b)"; conf "proj-b  repo=$rb"
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  local b="$C/brief-proj-b-1.txt"

  # the guard and the cure, both runnable as typed and both naming the item's OWN repo
  grep -q "git -C $rb rev-parse --is-shallow-repository" "$b" || false
  grep -q "git -C $rb fetch --unshallow" "$b" || false
  # --deepen is REFUSED on purpose: a deeper wrong horizon is still a wrong horizon, and a partial
  # cure puts the silent failure back with a green line above it.
  ! grep -q -- '--deepen' "$b" || false

  # ORDERING IS THE WHOLE PROPERTY — a precondition printed after the reads it protects is not a
  # precondition. Assert the deepen offset precedes the first trunk-read offset in the composed text.
  local deepen_at read_at
  deepen_at="$(grep -bo -- '--is-shallow-repository' "$b" | head -1 | cut -d: -f1)"
  read_at="$(grep -bo -- 'rev-list --count HEAD..origin/main' "$b" | head -1 | cut -d: -f1)"
  [ -n "$deepen_at" ] && [ -n "$read_at" ] || false
  [ "$deepen_at" -lt "$read_at" ] || false

  # RED — and the baseline has to be TRUNK, not $PRISTINE. $PRISTINE predates the staleness rail
  # entirely (the sibling cell above asserts it composes no FIRST STEP at all), so it would go red
  # here for the wrong reason: absence of the whole rail, not absence of the guard within it. The
  # defect this cell pins is narrower and lives on CURRENT trunk — a rail that HAS the three trunk
  # reads and nothing making them answerable. Read trunk's own composer and assert exactly that
  # pair. Skipped rather than failed where trunk is unreachable: a control we could not read is not
  # a control, and a network-less box must not be told its tree regressed.
  local trunk_rail
  if ! trunk_rail="$(git -C "$REPO" show origin/main:bin/cc-dispatch 2>/dev/null)"; then
    skip "origin/main:bin/cc-dispatch unreadable here — the RED control needs trunk's own composer"
  fi
  printf '%s' "$trunk_rail" | grep -q 'rev-list --count HEAD..origin/main' || false  # the reads ...
  ! printf '%s' "$trunk_rail" | grep -q -- '--is-shallow-repository' || false        # ... unguarded
}

# ── the dispatcher reports its OWN vintage, so "landed" and "ran" stop being one claim ────────────
@test "brief: the dispatcher stamps the blob sha of its own bytes, and the stamp is the REAL hash" {
  # backlog 485f8f87eb5f, eighth dispatch. Every remedy for that row's re-dispatch loop — the park
  # interlock, refresh_trunk, the admission-gate record — changed bytes that reach the loop's
  # ACTUATOR only through the per-file symlink layer, whose convergence has no ordering relation to
  # the landing. Three consecutive sections asserted "this fires on the next claim" from a reading of
  # SOURCE. Measured on the eighth fire: its brief's staleness_rail was byte-identical to 22b8824c^
  # and differed from trunk, so the live dispatcher predated a commit that had been on trunk for at
  # least 45 minutes. That measurement was only possible because a prose string happened to have
  # changed — a fingerprint with 21 days of resolution, which could date the binary but could NOT
  # say whether refresh_trunk (landed inside that interval) was live. This makes the stamp explicit.
  seed_items proj-b:1
  local rb; rb="$(mkrepo proj-b)"; conf "proj-b  repo=$rb"
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  local b="$C/brief-proj-b-1.txt"

  grep -q 'DISPATCHER VINTAGE — the bytes that composed this brief are bin/cc-dispatch blob ' "$b" || false
  # the comparison is RUNNABLE AS TYPED and names the item's OWN repo, never the pinned one
  grep -q "git -C $rb rev-parse origin/main:bin/cc-dispatch" "$b" || false
  # the disposition when the two differ — a convergence fact to REPORT, not a defect to re-fix
  grep -q 'landed is not live' "$b" || false

  # THE LOAD-BEARING ASSERTION IS NOT THE TEXT, IT IS THE VALUE. A stamp that names a blob nobody
  # can resolve is worse than no stamp: it reads as a measurement. Assert the emitted object name is
  # the real hash of the very binary that composed the brief.
  local stamped real
  stamped="$(grep -o 'bin/cc-dispatch blob [0-9a-f]\{40\}' "$b" | head -1 | awk '{print $3}')"
  real="$(git hash-object -- "$DISP")"
  [ -n "$stamped" ] && [ -n "$real" ] || false
  [ "$stamped" = "$real" ] || false

  # NO BACKTICK: same rule as the rail above — these are double-quoted shell strings, so a backtick
  # would command-substitute at compose time and write its OUTPUT into the worker's brief.
  ! grep -q '`' "$b" || false

  # ORDERING — the stamp qualifies the rail's own conclusion ("if the cure is on trunk, close on
  # it"), which is right for a cure in the ITEM and wrong for one in this machinery. A qualifier
  # printed before the claim it qualifies is not one.
  local rail_at stamp_at
  rail_at="$(grep -bo 'If the cure is already on trunk' "$b" | head -1 | cut -d: -f1)"
  stamp_at="$(grep -bo 'DISPATCHER VINTAGE' "$b" | head -1 | cut -d: -f1)"
  [ -n "$rail_at" ] && [ -n "$stamp_at" ] || false
  [ "$rail_at" -lt "$stamp_at" ] || false

  # FAIL-OPEN, AND IT SAYS SO. An omitted line is indistinguishable from a dispatcher too old to
  # emit one — the "three outcomes, one silence" defect this rail keeps rediscovering. Extracted
  # rather than driven, because $_self is always readable in-process: run the function alone with
  # the path unresolved and assert it NAMES the uncertainty at rc 0.
  local fn="$C/stamp-fn.sh"
  sed -n '/^dispatcher_stamp() {$/,/^}$/p' "$DISP" > "$fn"
  [ -s "$fn" ] || false                      # positive control: the function was actually extracted
  run bash -c ". '$fn'; _self=''; dispatcher_stamp"
  [ "$status" -eq 0 ] || false
  [[ "$output" == unknown* ]] || false

  # RED — trunk's own composer, for the deepen cell's reason: $PRISTINE predates the whole brief rail
  # and would go red for the wrong reason. Skipped rather than failed where trunk is unreachable.
  local trunk_src
  if ! trunk_src="$(git -C "$REPO" show origin/main:bin/cc-dispatch 2>/dev/null)"; then
    skip "origin/main:bin/cc-dispatch unreadable here — the RED control needs trunk's own composer"
  fi
  printf '%s' "$trunk_src" | grep -q 'staleness_rail=' || false        # it DOES compose a brief ...
  ! printf '%s' "$trunk_src" | grep -q 'DISPATCHER VINTAGE' || false   # ... with no vintage in it
}

# ── one queue: cross-project fairness under the existing S7 key ───────────────────────────────────
@test "one queue: the OLDEST item wins across projects — a long-undrained foreign item outranks the incumbent's whole queue" {
  # proj-b's items are seeded FIRST, so they carry the oldest ts — this is the live shape: the 5
  # oldest open items in the real ledger are the undrained doc_classifier ones.
  seed_items proj-b:2 proj-a:5
  conf "proj-b  repo=$C/repos/proj-b"
  fresh; CC_DISPATCH_CEILING=2 "$DISP" --once >/dev/null 2>&1
  [ "$(jq -rs '[.[]|select(.verdict=="admit")|.project]|join(",")' "$C/idl.jsonl")" = "proj-b,proj-b" ] || false
  [ "$(jq -rs '[.[]|select(.verdict=="admit")|.position]|join(",")' "$C/idl.jsonl")" = "1,2" ] || false
  # ONE fleet-wide queue: positions are a single sequence across projects, never per-project
  [ "$(jq -rs '[.[]|select(.action=="decision")|.position]|sort|join(",")' "$C/idl.jsonl")" = "1,2,3,4,5,6,7" ] || false
}

@test "one queue: ONE ceiling governs the whole set — widening coverage changes WHICH items fire, never HOW MANY" {
  seed_items proj-a:3 proj-b:3
  conf "proj-b  repo=$C/repos/proj-b"
  fresh; CC_DISPATCH_CEILING=6 STUB_LIVE=4 CC_DISPATCH_MAX_SPAWN=9 "$DISP" --once >/dev/null 2>&1
  # free_slots = 6 - 4 = 2, computed from the GLOBAL claimed fold — not 2 per project
  [ "$(dec ' and .verdict=="admit"')" -eq 2 ] || false
  [ "$(dec ' and .verdict=="defer"')" -eq 4 ] || false
  [ "$(jq -rs '[.[]|select(.verdict=="admit")|.free_slots]|unique|join(",")' "$C/idl.jsonl")" = "2" ] || false
}

# ── the pass lock is shared, which is WHY this is one loop and not N launchd instances ────────────
@test "one pass: the singleton lock is shared across the whole set — a second concurrent pass admits for NO project, it does not run per-project" {
  seed_items proj-a:1 proj-b:1
  conf "proj-b  repo=$C/repos/proj-b"
  fresh
  mkdir -p "$C/dispatch.lock"                       # a held lock with a LIVE owner (this shell)
  printf '%s|%s\n' "$$" "$(ps -o lstart= -p $$)" > "$C/dispatch.lock/owner"
  CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(jq -rs '[.[]|select(.action=="skipped" and .reason=="pass-in-flight")]|length' "$C/idl.jsonl")" -eq 1 ] || false
  # What the shared lock buys is that ADMISSION happens once for the whole set, never once per
  # project — so the read that matters is zero admits and zero spawns, ACROSS both projects.
  # It is deliberately not "zero decisions": since de5e3e24be8f the lock gates admission only, and
  # the loser journals a verdict for every item in the set (that is the A2 5-minute bound). This
  # read was `dec == 0` while the singleton was held across the 414-833 s spawn tail.
  [ "$(dec)" -eq 2 ] || false
  [ "$(dec ' and .verdict=="defer" and .reason=="pass-in-flight"')" -eq 2 ] || false
  [ "$(jq -rs '[.[]|select(.action=="decision")|.project]|sort|unique|join(",")' "$C/idl.jsonl")" = "proj-a,proj-b" ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 0 ] || false
  [ "$(spawns)" -eq 0 ] || false
}

# ── the conf lives in the CHECKOUT, reachable through the deployed symlink ────────────────────────
@test "conf path: resolved through \$0's SYMLINK, so the launchd-deployed entrypoint reads the checkout copy" {
  seed_items proj-a:1 proj-b:2
  # the real deployment shape: ~/.claude/bin/<name> is a per-file symlink into the checkout, and the
  # deployed scripts/ dir does NOT carry the conf (live proof: ~/.claude/scripts/growth-coverage.conf
  # does not exist). A dirname($0)-relative read would find nothing and silently narrow coverage.
  mkdir -p "$C/deployed/bin" "$C/deployed/scripts" "$C/checkout/bin" "$C/checkout/scripts"
  cp "$DISP" "$C/checkout/bin/cc-dispatch"
  printf '%s\n' "proj-b  repo=$C/repos/proj-b" > "$C/checkout/scripts/dispatch-projects.conf"
  ln -sfn "$C/checkout/bin/cc-dispatch" "$C/deployed/bin/cc-dispatch"

  fresh
  # Blank the conf seam so the script must resolve the path ITSELF, exactly as production does.
  # The empty assignment is deliberate, not a missing value: cc-dispatch reads the seam through
  # `${CC_DISPATCH_PROJECTS_CONF:-<default>}`, and `:-` treats empty as unset — so passing it empty
  # is precisely how a caller says "ignore the seam, resolve your own path".
  # shellcheck disable=SC1007
  CC_DISPATCH_PROJECTS_CONF= CC_DISPATCH_CEILING=0 "$C/deployed/bin/cc-dispatch" --once >/dev/null 2>&1
  [ "$(qprojects)" = "proj-a,proj-b" ] || false
}
