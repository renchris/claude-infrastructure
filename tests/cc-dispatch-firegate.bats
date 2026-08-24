#!/usr/bin/env bats
# cc-dispatch M2 FIRE GATE — nothing fires until it is provably current, provably unclaimed, and
# lands in a provably fresh tree (backlog 1b00d62958a6, docs/plans/BACKLOG_CONSOLIDATION_2026-08-09
# §M2). Three arms, all at the DECISION/ADMISSION chokepoint plus worktree provisioning:
#
#   RANK      — the queue was FIFO-oldest-first because the schema carries no priority and no
#               severity field. Rank is now DERIVED every pass (land-rail > in-degree > recurrence,
#               then oldest), so nothing is typed and nothing can go stale.
#   CLUSTER   — a slot is spent per CLUSTER, not per ROW, so N rows naming one root cause admit ONE
#               worker and the other slots go to different work.
#   FRESHNESS — a reused branch and a pre-existing worktree directory both bypassed the base
#               entirely, so a worker could be handed a tree cut from a trunk that had since moved.
#
# EVERY TEST IS A PAIR, matching tests/cc-dispatch-v2.bats: the same fixture runs against the shipped
# bin/cc-dispatch AND against the PRISTINE pre-change tree recovered with `git archive` from a pinned
# sha, and the pristine half must FAIL the assertion the new half passes. The control IS the
# artifact, byte for byte — a hand-typed approximation of the old code proves nothing about the old
# code (memory: control-must-replay-the-real-artifact).
#
# WHY A PINNED SHA AND NOT origin/main: the moment this lands, `origin/main:bin/cc-dispatch` BECOMES
# the new version and every "the old tree does not do this" half inverts and goes red fleet-wide.
BASE_SHA="a7bf7068"   # immutable ancestor of origin/main; carries the pre-M2 bin/cc-dispatch

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
  # half would pass VACUOUSLY and this suite would silently stop being a proof.
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-firegate.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
    return 1
  fi

  # backlog stub. `list --all` answers with the WHOLE fold — the rank map reads it for the citation
  # graph and for recurrence, and `live_workers` reads the same call for the claimed count, so the
  # stub must serve both from one fixture or the two would disagree about the store.
  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*)
        [ -n "\${STUB_LIST_ALL_RC:-}" ] && exit "\$STUB_LIST_ALL_RC"
        jq -cs --argjson n "\${STUB_LIVE:-0}" \
          '.[0] + [range(\$n) | {id:"c\(.)", project:"proj", status:"claimed", title:"held"}]' \
          "$C/all.json" ;;
      # The default (\`--open\`) list EXCLUDES anything this run blocked, because the real cc-backlog
      # does: \`block\` folds to status "blocked" and cc-dispatch's wave predicate is status=="open".
      # Modelled here rather than asserted away, so a two-pass test can prove the A1 property that
      # actually matters — the row does not come BACK — instead of only proving a record was written.
      *) jq -c --slurpfile b "$C/blocked.json" '[ .[] | select((.id|tostring) as \$i | (\$b[0]|index(\$i))==null) ]' "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  # \`block\` is the A1 exit from the claim→release loop, so the stub must be able to RECORD it and to
  # REFUSE it. Recording it is what lets a test tell "left the pool" from "went round again"; refusing
  # it (STUB_BLOCK_RC) is what pins the fail-open half — a store that will not block must degrade to
  # the incumbent reopen, never strand the row as \`claimed\` with no owner.
  block)  printf 'block %s\n'  "\$2" >> "$C/backlog.log"
          [ -n "\${STUB_BLOCK_RC:-}" ] && exit "\$STUB_BLOCK_RC"
          jq -c --arg i "\$2" '. + [\$i] | unique' "$C/blocked.json" > "$C/blocked.tmp" \
            && mv "$C/blocked.tmp" "$C/blocked.json"
          echo "\$2" ;;
esac
exit 0
EOF
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
  printf 'proj  repo=%s\n' "$C/repos/proj" > "$CONF"
  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECTS_CONF="$CONF" \
         CC_DISPATCH_PROJECT="proj" \
         CC_DISPATCH_MAX_SPAWN=9 \
         CC_DISPATCH_SID="bats"
  : > "$C/items.json"; echo '[]' > "$C/items.json"; echo '[]' > "$C/all.json"
  # NOT reset by fresh(): a block must SURVIVE into the next pass or the two-pass no-reclaim test
  # would be measuring the harness rather than the fix.
  echo '[]' > "$C/blocked.json"
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────
# items <json> — the dispatchable set AND, by default, the whole fold. Kept as one call so a test
# cannot accidentally rank against a fold that does not contain the items it is ranking.
items() { printf '%s' "$1" > "$C/items.json"; printf '%s' "$1" > "$C/all.json"; }
# fold <json> — override the `list --all` answer only (extra rows that cite, or are done).
fold()  { printf '%s' "$1" > "$C/all.json"; }
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; rm -rf "$C/pages" "$C/wave.json" "$C/dispatch.lock" "$C"/brief-*.txt; }

# queue → the admit/defer ids in journalled position order, comma-joined.
queue()    { jq -rs '[.[]|select(.action=="decision" and .verdict!="skip")]|sort_by(.position)|map(.id)|join(",")' "$C/idl.jsonl" 2>/dev/null; }
admits()   { jq -rs '[.[]|select(.verdict=="admit")]|sort_by(.position)|map(.id)|join(",")' "$C/idl.jsonl" 2>/dev/null; }
reasons()  { jq -rs "[.[]|select(.action==\"decision\" and .reason==\"$1\")]|map(.id)|sort|join(\",\")" "$C/idl.jsonl" 2>/dev/null; }
waveids()  { jq -r '[.[].id]|join(",")' "$C/wave.json" 2>/dev/null; }
spawns()   { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }

# mk_repo <dir> — a real git repo with an origin whose main carries two commits. The freshness arm
# reads actual refs, so it cannot be stubbed: `merge-base --is-ancestor` is the subject.
mk_repo() {
  local d="$1" o="$1.origin"
  rm -rf "$d" "$o"; mkdir -p "$d" "$o"
  git -C "$o" init -q --bare -b main
  git -C "$d" init -q -b main
  # The identity is TRANSIENT — `git -c` on the commit, never `git config` into a file. `git -C ""`
  # is a documented no-op, so an all-expansion target writes the identity into whatever repo this
  # process is standing in; ~100 linked worktrees here share ONE .git/config, and one such line
  # re-authored 9 commits on this trunk and 214 on reso (2026-08-05). A form that cannot persist at
  # all beats a guarded one that can.
  echo one > "$d/f"; git -C "${d:?repo path required}" add f
  git -C "${d:?repo path required}" -c user.email=t@t -c user.name=t commit -qm one
  git -C "$d" remote add origin "$o"; git -C "$d" push -q origin main
  git -C "$d" fetch -q origin
  git -C "$d" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
# advance_trunk <dir> — origin/main gains a commit the local branches do not have.
advance_trunk() {
  local d="$1"
  echo two >> "$d/f"
  git -C "${d:?repo path required}" -c user.email=t@t -c user.name=t commit -qam two
  git -C "$d" push -q origin main
  git -C "$d" reset -q --hard HEAD~1        # local main falls behind, as the shared checkout does
  git -C "$d" fetch -q origin
}

# ══ RANK ══════════════════════════════════════════════════════════════════════════════════════════

@test "rank: a land-rail item outranks an OLDER ordinary one — the pristine tree drains strictly oldest-first" {
  # `old` is the oldest by ts and would head a FIFO queue. `rail` is the newest AND is a
  # postland-verify row: the land rail itself is red, and everything else lands through it.
  items '[{"id":"old","project":"proj","status":"open","title":"an ordinary undrained thing","ts":"2026-07-01T00:00:00Z"},
          {"id":"mid","project":"proj","status":"open","title":"another ordinary undrained thing","ts":"2026-07-02T00:00:00Z"},
          {"id":"rail","project":"proj","status":"open","source":"postland-verify","title":"post-land RED some suite","ts":"2026-08-01T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "rail,old,mid" ] || false

  # RED: the pre-M2 tree has no rank at all, so the newest item is LAST — which is exactly how the
  # six master items that fix the ordering ended up at queue positions 294-299 of 305.
  fresh; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(queue)" = "old,mid,rail" ] || false
}

@test "rank: in-degree lifts a cited item above an older uncited one, and it is counted over the WHOLE fold (not just the open set)" {
  items '[{"id":"aaaaaaaaaaaa","project":"proj","status":"open","title":"the uncited older thing","ts":"2026-07-01T00:00:00Z"},
          {"id":"bbbbbbbbbbbb","project":"proj","status":"open","title":"the cited newer thing","ts":"2026-07-09T00:00:00Z"}]'
  # the citer is DONE — the common shape, since "supersedes X" / "DUPLICATE of Y" is written into a
  # done or blocked record. Restricted to open-vs-open the live store yields a 5x weaker signal.
  fold '[{"id":"aaaaaaaaaaaa","project":"proj","status":"open","title":"the uncited older thing"},
         {"id":"bbbbbbbbbbbb","project":"proj","status":"open","title":"the cited newer thing"},
         {"id":"cccccccccccc","project":"proj","status":"done","title":"closed; this work depended on bbbbbbbbbbbb"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "bbbbbbbbbbbb,aaaaaaaaaaaa" ] || false

  # CONTROL for "counted over the whole fold": drop the DONE citer and the edge disappears with it,
  # so the order reverts to oldest-first. Without this the assertion above would also pass if the
  # rank map were reading nothing at all and the tie were breaking on input order.
  fold '[{"id":"aaaaaaaaaaaa","project":"proj","status":"open","title":"the uncited older thing"},
         {"id":"bbbbbbbbbbbb","project":"proj","status":"open","title":"the cited newer thing"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "aaaaaaaaaaaa,bbbbbbbbbbbb" ] || false

  # RED: no rank in the pristine tree, so the citation is invisible and oldest wins either way.
  fold '[{"id":"aaaaaaaaaaaa","project":"proj","status":"open","title":"the uncited older thing"},
         {"id":"bbbbbbbbbbbb","project":"proj","status":"open","title":"the cited newer thing"},
         {"id":"cccccccccccc","project":"proj","status":"done","title":"closed; this work depended on bbbbbbbbbbbb"}]'
  fresh; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(queue)" = "aaaaaaaaaaaa,bbbbbbbbbbbb" ] || false
}

@test "rank: a SELF-citation is not an edge, and thrash still outranks every derived term" {
  # self-reference: an item whose title contains its own id must not rank itself up.
  items '[{"id":"dddddddddddd","project":"proj","status":"open","title":"see dddddddddddd for the background","ts":"2026-07-01T00:00:00Z"},
          {"id":"eeeeeeeeeeee","project":"proj","status":"open","title":"an ordinary later thing","ts":"2026-07-02T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "dddddddddddd,eeeeeeeeeeee" ] || false   # oldest-first, i.e. no self-lift

  # thrash is FIRST in the key and must stay there: a land-rail item that keeps failing to spawn
  # still sinks, or the highest-ranked item re-burns the same slot every pass forever.
  items '[{"id":"rail","project":"proj","status":"open","source":"postland-verify","title":"post-land RED some suite","ts":"2026-07-01T00:00:00Z"},
          {"id":"calm","project":"proj","status":"open","title":"an ordinary quiet thing","ts":"2026-08-01T00:00:00Z"}]'
  printf '%s\n' '{"actor":"cc-dispatch","action":"failed","id":"rail"}' \
                '{"actor":"cc-dispatch","action":"failed","id":"rail"}' > "$C/idl.jsonl"
  CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "calm,rail" ] || false
}

@test "rank kill switch + fail-open: CC_DISPATCH_RANK=off and an unreadable fold both restore the incumbent order" {
  local fx='[{"id":"old","project":"proj","status":"open","title":"an ordinary undrained thing","ts":"2026-07-01T00:00:00Z"},
             {"id":"rail","project":"proj","status":"open","source":"postland-verify","title":"post-land RED some suite","ts":"2026-08-01T00:00:00Z"}]'
  items "$fx"
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "rail,old" ] || false                    # positive control: the switch has an effect

  fresh; CC_DISPATCH_RANK=off CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "old,rail" ] || false

  # FAIL-OPEN: `list --all` fails ⇒ rank map {} ⇒ every term 0 ⇒ incumbent order, and the pass still
  # decides every item. A ranking failure must never cost a decision (I6).
  fresh; STUB_LIST_ALL_RC=1 CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(queue)" = "old,rail" ] || false
  [ "$(jq -rs '[.[]|select(.action=="decision")]|length' "$C/idl.jsonl")" -eq 2 ] || false
}

# ══ CLUSTER ═══════════════════════════════════════════════════════════════════════════════════════

@test "cluster: three rows of ONE condition admit ONE worker and the freed slot goes to different work" {
  # a real repo, because this test follows the admitted set all the way to the SPAWN — the wave and
  # the journal agreeing is necessary but not sufficient; what matters is how many workers start.
  mk_repo "$C/repos/proj"
  # `--condition` is the filer DECLARING one piece of work across three rows. Two free slots.
  items '[{"id":"c1","project":"proj","status":"open","condition":"one-condition","title":"the condition seen at first size","ts":"2026-07-01T00:00:00Z"},
          {"id":"c2","project":"proj","status":"open","condition":"one-condition","title":"the condition seen at second size","ts":"2026-07-02T00:00:00Z"},
          {"id":"c3","project":"proj","status":"open","condition":"one-condition","title":"the condition seen at third size","ts":"2026-07-03T00:00:00Z"},
          {"id":"other","project":"proj","status":"open","title":"an entirely unrelated piece of work","ts":"2026-07-04T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=2 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "c1,other" ] || false
  [ "$(reasons cluster-sibling)" = "c2,c3" ] || false
  # the WAVE is the admitted set, not the head slice — a sibling the journal deferred must not
  # reappear in the wave, or the pass would contradict its own decision records.
  [ "$(waveids)" = "c1,other" ] || false
  [ "$(spawns)" -eq 2 ] || false

  # RED: the pre-M2 tree spends a slot per ROW, so both slots go to the SAME condition and the
  # unrelated work is deferred behind it.
  fresh; CC_DISPATCH_CEILING=2 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(admits)" = "c1,c2" ] || false
  [ "$(waveids)" = "c1,c2" ] || false
}

@test "cluster: rows re-keyed by a MEASUREMENT in the title cluster without any --condition (the sha-keyed post-land shape)" {
  # 18 `tests/deploy-parity.bats` rows differing only by sha are one root cause. The id hash is
  # project+title+source, so each sha minted its own row; normalising the measurement out is what
  # folds them back to one dispatch unit.
  items '[{"id":"s1","project":"proj","status":"open","source":"postland-verify","title":"post-land RED: tests/deploy-parity.bats @ 3e423b762e60","ts":"2026-07-01T00:00:00Z"},
          {"id":"s2","project":"proj","status":"open","source":"postland-verify","title":"post-land RED: tests/deploy-parity.bats @ bda59c54c4","ts":"2026-07-02T00:00:00Z"},
          {"id":"s3","project":"proj","status":"open","source":"postland-verify","title":"post-land RED: tests/deploy-parity.bats @ f60b7ca220ee","ts":"2026-07-03T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "s1" ] || false
  [ "$(reasons cluster-sibling)" = "s2,s3" ] || false

  # RED: three workers at one root cause.
  fresh; CC_DISPATCH_CEILING=3 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(admits)" = "s1,s2,s3" ] || false
}

@test "cluster SAFETY: an absent discriminator is not sameness — no title, and byte-identical titles, do NOT cluster" {
  # (a) NO TITLE. The first cut keyed on the normalised title unconditionally, so every untitled row
  # shared the key `proj norm:` and collapsed into one cluster — eight v2 assertions went red and
  # they were right (memory: lookup-miss-is-not-absence).
  items '[{"id":"n1","project":"proj","status":"open","ts":"2026-07-01T00:00:00Z"},
          {"id":"n2","project":"proj","status":"open","ts":"2026-07-02T00:00:00Z"},
          {"id":"n3","project":"proj","status":"open","ts":"2026-07-03T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "n1,n2,n3" ] || false
  [ -z "$(reasons cluster-sibling)" ] || false

  # (b) BYTE-IDENTICAL TITLES. A measurement is not what split these — something else did, and the
  # normaliser has no evidence about what. (Two such rows cannot exist in the live store at all:
  # same project+title+source ⇒ same id hash ⇒ one row.)
  items '[{"id":"t1","project":"proj","status":"open","title":"work for the project","ts":"2026-07-01T00:00:00Z"},
          {"id":"t2","project":"proj","status":"open","title":"work for the project","ts":"2026-07-02T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=2 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "t1,t2" ] || false
  [ -z "$(reasons cluster-sibling)" ] || false

  # (c) DIFFERENT PROJECTS never cluster, however alike the titles read.
  printf 'proj  repo=%s\nproj2 repo=%s\n' "$C/repos/proj" "$C/repos/proj2" > "$CONF"
  items '[{"id":"p1","project":"proj","status":"open","title":"post-land RED: tests/deploy-parity.bats @ 3e423b762e60","ts":"2026-07-01T00:00:00Z"},
          {"id":"p2","project":"proj2","status":"open","title":"post-land RED: tests/deploy-parity.bats @ bda59c54c4","ts":"2026-07-02T00:00:00Z"}]'
  fresh; CC_DISPATCH_CEILING=2 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "p1,p2" ] || false
}

@test "cluster: the deferral reason is its OWN token, never at-ceiling — and the kill switch restores per-row admission" {
  items '[{"id":"c1","project":"proj","status":"open","condition":"one-condition","title":"the condition at one size","ts":"2026-07-01T00:00:00Z"},
          {"id":"c2","project":"proj","status":"open","condition":"one-condition","title":"the condition at other size","ts":"2026-07-02T00:00:00Z"}]'
  # Slots are FREE (ceiling 9), so a cluster deferral here can only be about the cluster. Reporting
  # it as `at-ceiling` would feed cc-blockers' SATURATED premise gate evidence that the fleet is
  # full, which it is not.
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(reasons cluster-sibling)" = "c2" ] || false
  [ -z "$(reasons at-ceiling)" ] || false

  fresh; CC_DISPATCH_CLUSTER=off CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(admits)" = "c1,c2" ] || false
  [ -z "$(reasons cluster-sibling)" ] || false
}

# ══ FRESHNESS ═════════════════════════════════════════════════════════════════════════════════════

@test "freshness: a reused wt- branch that is BEHIND the base and carries no commits is fast-forwarded, not silently reused" {
  mk_repo "$C/repos/proj"
  # the leftover of a failed spawn: a wt- branch at the OLD trunk, no worktree, no commits of its own
  git -C "$C/repos/proj" branch "wt-ff" origin/main
  local stale; stale="$(git -C "$C/repos/proj" rev-parse wt-ff)"
  advance_trunk "$C/repos/proj"
  [ "$stale" != "$(git -C "$C/repos/proj" rev-parse origin/main)" ] || false   # the base really moved

  items '[{"id":"ff","project":"proj","status":"open","title":"a piece of work to be done"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(git -C "$C/repos/proj" rev-parse wt-ff)" = "$(git -C "$C/repos/proj" rev-parse origin/main)" ] || false
  [ "$(spawns)" -eq 1 ] || false

  # RED: the pristine tree checks the old branch tip out and fires into it — the branch never moves.
  git -C "$C/repos/proj" worktree remove --force "$C/wt/wt-ff" 2>/dev/null || true
  git -C "$C/repos/proj" branch -f wt-ff "$stale"
  fresh; rm -rf "$C/wt"; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(git -C "$C/repos/proj" rev-parse wt-ff)" = "$stale" ] || false
  [ "$(spawns)" -eq 1 ] || false                       # …and it fired anyway, onto the stale tree
}

@test "freshness: a reused branch that CARRIES COMMITS is refused, not rebased — the item reopens with a recorded failure" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-work" origin/main
  git -C "$C/repos/proj" worktree add -q "$C/scratch" wt-work
  echo mine > "$C/scratch/mine"; git -C "$C/scratch" add mine
  git -C "$C/scratch" -c user.email=t@t -c user.name=t commit -qm mine
  git -C "$C/repos/proj" worktree remove --force "$C/scratch"
  local mine; mine="$(git -C "$C/repos/proj" rev-parse wt-work)"
  advance_trunk "$C/repos/proj"

  items '[{"id":"work","project":"proj","status":"open","title":"a piece of work to be done"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  # NOT fired, NOT rebased, NOT deleted — an unattended dispatcher must not destroy work it did not
  # create. The claim is released so the item is visible again rather than stranded as `claimed`.
  [ "$(spawns)" -eq 0 ] || false
  [ "$(git -C "$C/repos/proj" rev-parse wt-work)" = "$mine" ] || false
  grep -q 'reopen work' "$C/backlog.log" || false
  jq -rs '[.[]|select(.action=="failed")]|length' "$C/idl.jsonl" | grep -qx 1 || false

  # RED: the pristine tree fires a worker straight into the stale, commit-carrying branch.
  fresh; rm -rf "$C/wt"; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false
}

@test "freshness: a PRE-EXISTING worktree directory is checked too — the path warm_worktree never sees" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-pre" origin/main
  mkdir -p "$C/wt"
  git -C "$C/repos/proj" worktree add -q "$C/wt/wt-pre" wt-pre
  advance_trunk "$C/repos/proj"
  local stale; stale="$(git -C "$C/wt/wt-pre" rev-parse HEAD)"

  items '[{"id":"pre","project":"proj","status":"open","title":"a piece of work to be done"}]'
  # The directory already exists, so warm_worktree is never called — this is a second, independent
  # hole and needs its own guard. THE GUARD IS PROVEN BY THE TREE MOVING, not by a refusal: A1 gave
  # this site warm_worktree's own resolution for the case where nothing can be lost, so a clean
  # worktree carrying nothing is fast-forwarded IN PLACE and the work fires on this same pass.
  # (Before A1 this asserted zero spawns + a reopen; that refusal was correct about the tree and
  # wrong about the exit — the row went straight back into the pool it had just been pulled from.)
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(git -C "$C/wt/wt-pre" rev-parse HEAD)" = "$(git -C "$C/repos/proj" rev-parse origin/main)" ] || false
  [ "$(spawns)" -eq 1 ] || false
  # …and it fired because it was made fresh, never because the check was skipped: no block, no reopen.
  ! grep -q 'block pre'  "$C/backlog.log" || false
  ! grep -q 'reopen pre' "$C/backlog.log" || false

  # RED: the pristine tree fires into the stale pre-existing tree without looking at it — the tree
  # never moves, which is exactly the difference this test exists to name.
  git -C "$C/wt/wt-pre" reset -q --hard "$stale"
  fresh; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(git -C "$C/wt/wt-pre" rev-parse HEAD)" = "$stale" ] || false
  [ "$(spawns)" -eq 1 ] || false
}

# ══ A1 — THE REFUSAL NEEDED AN EXIT (docs/plans/BACKLOG_DRAIN_24_7.md §4 A1) ══════════════════════
# The M2 guard above refuses correctly and then `self_release`s, so the row returns to the pool, is
# re-ranked, re-claimed, re-probed against the same unchanged directory and refused again. Nothing in
# that cycle can make the tree fresh, so it is unbounded: 141 claims / 129 reopens in 24 h, one id at
# 50 claims / 48 releases. These three tests pin the exit — BLOCKED, which cc-dispatch excludes from
# the wave — and the safety rule that decides which rows may take the fast-forward instead.

@test "A1: a pre-existing worktree CARRYING COMMITS is blocked, not reopened — and a second pass does not re-claim it" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-own" origin/main
  mkdir -p "$C/wt"
  git -C "$C/repos/proj" worktree add -q "$C/wt/wt-own" wt-own
  echo mine > "$C/wt/wt-own/mine"; git -C "$C/wt/wt-own" add mine
  git -C "$C/wt/wt-own" -c user.email=t@t -c user.name=t commit -qm mine
  local mine; mine="$(git -C "$C/wt/wt-own" rev-parse HEAD)"
  advance_trunk "$C/repos/proj"

  items '[{"id":"own","project":"proj","status":"open","title":"a piece of work to be done"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  # not fired, and the work is untouched — an unattended dispatcher may not rebase or delete a tree
  # it did not create.
  [ "$(spawns)" -eq 0 ] || false
  [ "$(git -C "$C/wt/wt-own" rev-parse HEAD)" = "$mine" ] || false
  grep -q 'block own' "$C/backlog.log" || false
  jq -rs '[.[]|select(.action=="failed")]|length' "$C/idl.jsonl" | grep -qx 1 || false

  # THE PROPERTY THAT MATTERS: the next pass does not claim it again. A refusal that reopens is a
  # loop; a refusal that blocks is an exit. Without this half the test would pass on the incumbent
  # behaviour too, since that also spawns nothing on the first pass.
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  ! grep -q 'claim own' "$C/backlog.log" || false
  [ "$(spawns)" -eq 0 ] || false

  # RED: the pristine tree never blocks anything — it reopens, which is the loop.
  echo '[]' > "$C/blocked.json"
  fresh; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  ! grep -q 'block own' "$C/backlog.log" || false
}

@test "A1: STAGED-only content blocks the row — a rev-list count alone would have fast-forwarded over it" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-stg" origin/main
  mkdir -p "$C/wt"
  git -C "$C/repos/proj" worktree add -q "$C/wt/wt-stg" wt-stg
  advance_trunk "$C/repos/proj"
  # The exact shape measured on wt-ee1ac85c6ff6: ZERO commits of its own, so every commit-counting
  # probe reads it as an empty leftover — while it holds four files that exist nowhere on trunk,
  # staged and never committed (memory: landedness-over-commits-is-blind-to-staged-content).
  echo novel > "$C/wt/wt-stg/novel"; git -C "$C/wt/wt-stg" add novel
  [ "$(git -C "$C/wt/wt-stg" rev-list --count origin/main..HEAD)" -eq 0 ] || false

  items '[{"id":"stg","project":"proj","status":"open","title":"a piece of work to be done"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 0 ] || false
  grep -q 'block stg' "$C/backlog.log" || false
  # the staged bytes are still there, and the tree was NOT fast-forwarded out from under them
  git -C "$C/wt/wt-stg" diff --cached --name-only | grep -qx novel || false
  [ "$(git -C "$C/wt/wt-stg" rev-parse HEAD)" != "$(git -C "$C/repos/proj" rev-parse origin/main)" ] || false
}

@test "A1: pollution is its OWN axis — a CURRENT worktree carrying foreign content blocks, and staleness is not what convicts it" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-cur" origin/main
  mkdir -p "$C/wt"
  git -C "$C/repos/proj" worktree add -q "$C/wt/wt-cur" wt-cur
  # NO advance_trunk, deliberately. Every other fixture in this arm advances the trunk first, so every
  # one of them reaches the guard through the STALE door — this is the cell none of them enter, and the
  # cell the guard could not see while `wdirty` was read only inside `if [ "$wstate" = stale ]`.
  git -C "$C/wt/wt-cur" merge-base --is-ancestor origin/main HEAD || false
  echo foreign > "$C/wt/wt-cur/foreign"; git -C "$C/wt/wt-cur" add foreign

  items '[{"id":"cur","project":"proj","status":"open","title":"a piece of work to be done"}]'
  fresh; CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>"$C/err.log"
  [ "$(spawns)" -eq 0 ] || false
  grep -q 'block cur' "$C/backlog.log" || false
  # THE DISCRIMINATOR against the sibling stale cases: the refusal must name the axis it actually
  # found. A message about a HEAD that does not contain the base would be false of this tree, and a
  # test that accepted it would pass just as well on the stale path it is meant to be distinct from.
  grep -q 'current but polluted' "$C/err.log" || false
  # the foreign bytes survive — an unattended dispatcher may not clean a tree it did not create
  git -C "$C/wt/wt-cur" diff --cached --name-only | grep -qx foreign || false

  # RED: the pristine tree fires a worker straight into the polluted-but-current directory.
  echo '[]' > "$C/blocked.json"
  fresh; CC_DISPATCH_CEILING=9 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false
}

@test "A1 fail-open: a store that REFUSES the block degrades to the incumbent reopen, never a stranded claim" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-fo" origin/main
  mkdir -p "$C/wt"
  git -C "$C/repos/proj" worktree add -q "$C/wt/wt-fo" wt-fo
  echo mine > "$C/wt/wt-fo/mine"; git -C "$C/wt/wt-fo" add mine
  git -C "$C/wt/wt-fo" -c user.email=t@t -c user.name=t commit -qm mine
  advance_trunk "$C/repos/proj"

  items '[{"id":"fo","project":"proj","status":"open","title":"a piece of work to be done"}]'
  # A block that cannot be written is a thrash — the incumbent behaviour, and strictly better than a
  # row left `claimed` with no owner and no session, which nothing but the reap sweep would ever free.
  fresh; STUB_BLOCK_RC=1 CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 0 ] || false
  grep -q 'reopen fo' "$C/backlog.log" || false
  jq -rs '[.[]|select(.action=="failed" and (.detail|test("reopened")))]|length' "$C/idl.jsonl" | grep -qx 1 || false
}

@test "freshness: three states, not two — an UNANSWERABLE base proceeds, and the kill switch restores the incumbent" {
  mk_repo "$C/repos/proj"
  git -C "$C/repos/proj" branch "wt-unk" origin/main
  local stale; stale="$(git -C "$C/repos/proj" rev-parse wt-unk)"
  advance_trunk "$C/repos/proj"
  items '[{"id":"unk","project":"proj","status":"open","title":"a piece of work to be done"}]'

  # A base ref that does not resolve is "I could not tell", never "stale": the probe never ran, so
  # it may not convict. Starving the queue on a sensor failure is the worse error.
  fresh; rm -rf "$C/wt"; CC_DISPATCH_WT_BASE=refs/heads/no-such-ref CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false

  # kill switch: incumbent behaviour exactly — reuse the stale branch and fire.
  git -C "$C/repos/proj" worktree remove --force "$C/wt/wt-unk" 2>/dev/null || true
  git -C "$C/repos/proj" branch -f wt-unk "$stale"
  fresh; rm -rf "$C/wt"; CC_DISPATCH_WT_FRESH=off CC_DISPATCH_CEILING=9 "$DISP" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 1 ] || false
  [ "$(git -C "$C/repos/proj" rev-parse wt-unk)" = "$stale" ] || false
}
