#!/usr/bin/env bats
# cc-dispatch F3 — THE LOCAL WORKTREE GATE MUST NOT JUDGE A CLOUD FIRE (backlog e86e500e96c0,
# docs/plans/CLOUD_BACKLOG_PIPELINE.md §A2a).
#
# The dispatcher provisions a local worktree at `--cwd` and then freshness-gates it (the M2 arm,
# pinned by tests/cc-dispatch-firegate.bats). Both steps run AFTER the venue is resolved, and the
# cloud actuator chosen downstream is `cc-offload up --via api --task <brief>` — which never touches
# that directory, because the VM clones from origin. cc-wave-plan is a pure planner with no venue
# awareness at all (bin/cc-wave-plan:715 emits `--cwd` unconditionally), so every cloud row arrives
# carrying one and was judged on a filesystem its fire would never use.
#
# WHY IT IS WORTH A SUITE: since the A1 change gave that refusal a BLOCKED exit, the loss is no
# longer a retry loop but an operator-gated row. Measured at the time of the fix, all three rows the
# gate had blocked carried venuePlan=cloud and none was local, while the live dispatcher runs
# CC_DISPATCH_VENUE_ONLY=cloud — i.e. the only lane it admits is the one the gate cannot speak about.
#
# THREE ARMS, and the middle one is the reason this is a guard and not a loosening:
#   FIRES    — a cloud row with an unblockable stale worktree fires anyway, via the offload actuator.
#   SCOPED   — the SAME fixture with no venuePlan is still blocked. The gate is intact for local.
#   ARGV     — `--cwd` is still in the argv, so the declaration still names the wt- branch. Stripping
#              the flag is the obvious reading of F3 and it silently breaks `fire_branch`.
#
# EVERY ARM IS A PAIR against the PRISTINE pre-change artifact recovered with `git archive`, matching
# tests/cc-dispatch-firegate.bats. A hand-typed approximation of the old code proves nothing about
# the old code (memory: control-must-replay-the-real-artifact).
#
# WHY A PINNED SHA AND NOT origin/main: the moment this lands, `origin/main:bin/cc-dispatch` BECOMES
# the fixed version and the RED halves would invert and go green vacuously.
BASE_SHA="ba082bc4b"   # immutable ancestor of origin/main; carries the pre-F3 (venue-blind) gate

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine" "$C/wt"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

  git -C "$REPO" archive "$BASE_SHA" bin/cc-dispatch 2>/dev/null | tar -x -C "$C/pristine"
  PRISTINE="$C/pristine/bin/cc-dispatch"
  chmod +x "$PRISTINE" 2>/dev/null || true
  # FAIL LOUD if the control could not be recovered: an absent binary writes nothing, so every RED
  # half would pass VACUOUSLY and this suite would silently stop being a proof.
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-venue-worktree.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
    return 1
  fi

  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*) jq -c . "$C/items.json" ;;
      *) jq -c --slurpfile b "$C/blocked.json" '[ .[] | select((.id|tostring) as \$i | (\$b[0]|index(\$i))==null) ]' "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  block)  printf 'block %s\n'  "\$2" >> "$C/backlog.log"
          jq -c --arg i "\$2" '. + [\$i] | unique' "$C/blocked.json" > "$C/blocked.tmp" \
            && mv "$C/blocked.tmp" "$C/blocked.json"
          echo "\$2" ;;
esac
exit 0
EOF
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\$items" | jq -c --arg d "$C" \
  '[ .[] | {id, account:"next3", fire_line:["--prompt-file",(\$d+"/brief-"+.id+".txt"),"--cwd",(\$d+"/wt/wt-"+.id)] } ]'
EOF
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit 0
EOF
  # The managed cloud actuator. It prints a session id and NOTHING that looks like an existing
  # declaration, so cloud_declare falls through to the cc-cloud leg the ARGV arm asserts on.
  cat > "$C/stubs/offload" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/offload.log"
echo "created session_r87probe"
exit 0
EOF
  cat > "$C/stubs/cloud" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/cloud.log"
exit 0
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn" "$C/stubs/offload" "$C/stubs/cloud"

  CONF="$C/dispatch-projects.conf"
  printf 'proj  repo=%s\n' "$C/repos/proj" > "$CONF"
  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_OFFLOAD_BIN="$C/stubs/offload" \
         CC_DISPATCH_CLOUD_BIN="$C/stubs/cloud" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECTS_CONF="$CONF" \
         CC_DISPATCH_PROJECT="proj" \
         CC_DISPATCH_MAX_SPAWN=9 \
         CC_DISPATCH_SID="bats"
  echo '[]' > "$C/items.json"; echo '[]' > "$C/blocked.json"
}

items() { printf '%s' "$1" > "$C/items.json"; }
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; : > "$C/offload.log"; : > "$C/cloud.log"
          rm -rf "$C/pages" "$C/dispatch.lock" "$C"/brief-*.txt; }
lines() { local n; n="$( { grep -c . "$1" 2>/dev/null || true; } | head -1 )"; echo "${n:-0}"; }

# mk_repo <dir> — a real git repo with an origin whose main carries a commit. The freshness arm reads
# actual refs, so it cannot be stubbed: `merge-base --is-ancestor` is the subject.
mk_repo() {
  local d="$1" o="$1.origin"
  rm -rf "$d" "$o"; mkdir -p "$d" "$o"
  git -C "$o" init -q --bare -b main
  git -C "$d" init -q -b main
  echo one > "$d/f"; git -C "${d:?repo path required}" add f
  git -C "${d:?repo path required}" -c user.email=t@t -c user.name=t commit -qm one
  git -C "$d" remote add origin "$o"; git -C "$d" push -q origin main
  git -C "$d" fetch -q origin
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
advance_trunk() {
  local d="$1"
  echo two >> "$d/f"
  git -C "${d:?repo path required}" -c user.email=t@t -c user.name=t commit -qam two
  git -C "$d" push -q origin main
  git -C "$d" reset -q --hard HEAD~1
  git -C "$d" fetch -q origin
}
# stale_wt <id> — a pre-existing worktree that CARRIES ITS OWN COMMIT, so the gate's fast-forward
# escape is unavailable and the only pre-fix exit is the block.
stale_wt() {
  local id="$1" d="$C/repos/proj"
  git -C "$d" branch "wt-$id" origin/main
  git -C "$d" worktree add -q "$C/wt/wt-$id" "wt-$id"
  echo mine > "$C/wt/wt-$id/mine"; git -C "$C/wt/wt-$id" add mine
  git -C "$C/wt/wt-$id" -c user.email=t@t -c user.name=t commit -qm mine
  advance_trunk "$d"
}

# ══ FIRES — the venue-blind gate no longer judges a cloud fire ════════════════════════════════════

@test "F3: a CLOUD row fires through the offload actuator even though its local wt- tree is unblockably stale" {
  mk_repo "$C/repos/proj"; stale_wt cl
  items '[{"id":"cl","project":"proj","status":"open","title":"off-box work","venuePlan":"cloud"}]'

  fresh; CC_FIRE_CLOUD=on CC_DISPATCH_CEILING=9 CC_DISPATCH_CLOUD_CEILING=9 "$DISP" --once >/dev/null 2>&1
  # the managed cloud actuator ran, with this item…
  [ "$(lines "$C/offload.log")" -eq 1 ] || false
  grep -q -- '--item cl' "$C/offload.log" || false
  # …and the local gate neither blocked it nor sent it round again.
  ! grep -q 'block cl'  "$C/backlog.log" || false
  ! grep -q 'reopen cl' "$C/backlog.log" || false
  # the local spawn path was NOT taken — this is an off-box fire, not a fallback.
  [ "$(lines "$C/spawn.log")" -eq 0 ] || false
  # and the tree it was judged on is untouched: skipping the gate is not licence to rebase it.
  [ -f "$C/wt/wt-cl/mine" ] || false

  # RED: the pristine tree blocks the row on that directory and the cloud actuator never runs at all.
  echo '[]' > "$C/blocked.json"
  fresh; CC_FIRE_CLOUD=on CC_DISPATCH_CEILING=9 CC_DISPATCH_CLOUD_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  grep -q 'block cl' "$C/backlog.log" || false
  [ "$(lines "$C/offload.log")" -eq 0 ] || false
}

# ══ SCOPED — and it is a venue guard, not a hole in the gate ══════════════════════════════════════

@test "F3 SAFETY: the SAME stale tree still blocks a LOCAL row — the gate is scoped, not disabled" {
  mk_repo "$C/repos/proj"; stale_wt lo
  # byte-identical fixture to the arm above except the venue plan, which is the whole point.
  items '[{"id":"lo","project":"proj","status":"open","title":"on-box work"}]'

  fresh; CC_FIRE_CLOUD=on CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  grep -q 'block lo' "$C/backlog.log" || false
  [ "$(lines "$C/spawn.log")" -eq 0 ] || false
  [ "$(lines "$C/offload.log")" -eq 0 ] || false
  # the work in the tree is untouched, exactly as the M2 arm requires.
  [ -f "$C/wt/wt-lo/mine" ] || false

  # …and it blocks for the same reason on the pristine tree: this arm must NOT discriminate. It is
  # here to prove the fix did not widen, so an inverted verdict here means the guard leaked.
  echo '[]' > "$C/blocked.json"
  fresh; CC_FIRE_CLOUD=on CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  grep -q 'block lo' "$C/backlog.log" || false
}

# ══ ARGV — the flag survives, because the declaration's branch is derived from it ═════════════════

@test "F3: --cwd stays in the argv — the cloud declaration still names the wt- branch" {
  mk_repo "$C/repos/proj"; stale_wt cl
  items '[{"id":"cl","project":"proj","status":"open","title":"off-box work","venuePlan":"cloud"}]'

  fresh; CC_FIRE_CLOUD=on CC_DISPATCH_CEILING=9 CC_DISPATCH_CLOUD_CEILING=9 "$DISP" --once >/dev/null 2>&1
  # fire_branch falls back to the basename of --cwd when no --worktree is present. Strip the flag to
  # implement F3 and this declares an EMPTY branch, so the reconcile watches a ref that never exists.
  grep -q -- '--branch wt-cl' "$C/cloud.log" || false
  grep -q -- '--item cl'      "$C/cloud.log" || false
}
