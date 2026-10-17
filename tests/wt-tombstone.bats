#!/usr/bin/env bats
# wt-tombstone.bats — the tombstone core (scripts/lib/wt-tombstone.sh, DESIGN load-root-cause-2026-10-17
# §3.7 items 2, 7 and 8; WP-9).
#
# WHAT IS LOAD-BEARING. A tombstone is only worth writing if a later restore can use it, so the cases pin
# the RECORD rather than the call: residue byte-identical and kept out of the tree (mv) or left in it
# (clone), a head that survives `reflog expire` + `gc --prune=now` when trunk only has it by patch-id, a
# reflog-only commit that survives the same, and a failure that undoes itself. The "RED control" case is
# the premise: the same removal without a tombstone loses the residue.
#
# HERMETIC: a bare fixture origin, a clone and linked worktrees, all under $BATS_TEST_TMPDIR, with HOME and
# every WT_* store pointed inside it. No case touches a real worktree or a real ledger.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/projects"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset WT_TRUNK WT_NOW CC_WTGC_DISPOSAL_LOG _WT_TOMBSTONE_SH _WT_PARK_SH
  export WT_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl" WT_TOMB_DIR="$BATS_TEST_TMPDIR/tombs" \
         WT_STATE_DIR="$BATS_TEST_TMPDIR/state" WT_CONFIG_ROOTS="$HOME/.claude"
  export WT_EVENTS_FILE="$WT_STATE_DIR/wt-events.jsonl" WT_WAKE_FILE="$WT_STATE_DIR/worktree-gc.wake" \
         WT_PARK_INDEX="$WT_STATE_DIR/wt-parked" WT_PARK_ROOT="$BATS_TEST_TMPDIR/parked"
  LIB="$BATS_TEST_DIRNAME/../scripts/lib/wt-tombstone.sh"
  CLI="$BATS_TEST_DIRNAME/../bin/wt-tombstone"
  T="$BATS_TEST_TMPDIR"
  git init -q --bare -b main "$T/origin.git"
  git init -q -b main "$T/main"
  cd "$T/main" || return 1
  printf 'node_modules/\n.venv/\n.next/\n__pycache__/\n.env*\nbrag-output/\nasset-workspace/\n.claude/settings.local.json\n' > .gitignore
  mkdir -p .claude && echo '{"permissions":{}}' > .claude/settings.json && echo base > f.txt
  git add -A && git commit -qm base
  git remote add origin "$T/origin.git" && git push -q -u origin main
  git remote set-head origin main
  echo 'SECRET=1' > .env.local
  echo '{"permissions":{"allow":["Bash(ls)"]}}' > .claude/settings.local.json
  # shellcheck source=../scripts/lib/wt-tombstone.sh
  . "$LIB"
}

mkwt() { # <name> → a linked worktree on branch <name> at main's tip, provisioned like new-worktree.sh
  git -C "$T/main" worktree add -q -b "$1" "$T/wts/$1" main
  cp "$T/main/.env.local" "$T/wts/$1/.env.local"
  cp "$T/main/.claude/settings.local.json" "$T/wts/$1/.claude/settings.local.json"
  printf '%s' "$T/wts/$1"
}

commit_in() { echo "$2" > "$1/$2.txt"; git -C "$1" add "$2.txt"; git -C "$1" commit -qm "$2"; }

lastrow() { tail -1 "$WT_LEDGER"; }

tree_sums() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum); }

@test "row: every schema key present, repo set, a fast-forward-landed head gets no durable ref" {
  w="$(mkwt ff1)"
  run wt_tombstone "$w" lab test --mode clone
  [ "$status" -eq 0 ]
  row="$(lastrow)"
  for k in ts event id actor reason repo path branch head trunk landed sids mode preserved preserved_list \
           caches_skipped identical_skipped lockfiles tomb_ref reflog_refs logs_head wip_ref checkpoint_ref \
           parked_path branch_tip preserved_at destroyed_ignored; do
    printf '%s' "$row" | jq -e --arg k "$k" 'has($k)' >/dev/null || { echo "missing $k"; false; }
  done
  [ "$(printf '%s' "$row" | jq -r .repo)" = "$(cd "$T/main" && pwd -P)" ]
  [ "$(printf '%s' "$row" | jq -r .landed)" = true ]
  [ "$(printf '%s' "$row" | jq -r .tomb_ref)" = null ]
  [ "$(printf '%s' "$row" | jq -r .trunk)" = origin/main ]
}

@test "residue: allowlisted caches skipped, lockfile-gated caches checked, provisioning copies cmp-filtered" {
  w="$(mkwt res1)"
  mkdir -p "$w/node_modules/.pnpm" "$w/sub/node_modules/x" "$w/.next/cache" "$w/pkg/__pycache__" \
           "$w/brag-output" "$w/asset-workspace"
  echo 'lock: 1' > "$w/pnpm-lock.yaml"; git -C "$w" add pnpm-lock.yaml; git -C "$w" commit -qm lock
  cp "$w/pnpm-lock.yaml" "$w/node_modules/.pnpm/lock.yaml"
  echo m > "$w/sub/node_modules/x/m.js"; echo n > "$w/.next/cache/n"; echo p > "$w/pkg/__pycache__/a.pyc"
  echo '{"brag":1}' > "$w/brag-output/x.json"; head -c 4096 /dev/urandom > "$w/asset-workspace/render.png"
  echo 'EDITED=1' > "$w/.env.dev"
  echo '{"permissions":{"allow":["Bash(ls)","Bash(make)"]}}' > "$w/.claude/settings.local.json"
  cp "$w/brag-output/x.json" "$T/x.json.orig"; cp "$w/asset-workspace/render.png" "$T/render.orig"
  cp "$w/.claude/settings.local.json" "$T/sl.orig"
  run wt_tombstone "$w" lab residue
  [ "$status" -eq 0 ]
  id="$output"; row="$(lastrow)"
  for r in brag-output asset-workspace .env.dev .claude/settings.local.json sub/node_modules; do
    printf '%s' "$row" | jq -e --arg r "$r" '.preserved_list | index($r) != null' >/dev/null || { echo "not residue: $r"; false; }
  done
  for c in node_modules .next pkg/__pycache__; do
    printf '%s' "$row" | jq -e --arg c "$c" '.caches_skipped | index($c) != null' >/dev/null || { echo "not cache: $c"; false; }
  done
  printf '%s' "$row" | jq -e '.identical_skipped == [".env.local"]' >/dev/null
  printf '%s' "$row" | jq -e '.lockfiles["pnpm-lock.yaml"] | length == 64' >/dev/null
  [ "$(printf '%s' "$row" | jq -r .preserved)" = "$id/residue" ]
  cmp "$WT_TOMB_DIR/$id/residue/brag-output/x.json" "$T/x.json.orig"
  cmp "$WT_TOMB_DIR/$id/residue/asset-workspace/render.png" "$T/render.orig"
  cmp "$WT_TOMB_DIR/$id/residue/.claude/settings.local.json" "$T/sl.orig"
  [ ! -e "$w/brag-output" ] && [ ! -e "$w/.claude/settings.local.json" ] || false # mv: gone from the tree
  [ -d "$w/node_modules" ] && [ -f "$w/.env.local" ] || false              # caches and identical copies stay
  [ "$(stat -f %Lp "$WT_TOMB_DIR/$id")" = 700 ]
  [ "$(stat -f %Lp "$WT_TOMB_DIR/$id/residue.list")" = 600 ]       # what the tombstone writes is 0600;
  [ "$(stat -f %Lp "$WT_TOMB_DIR/$id/logs-HEAD")" = 600 ]          # residue keeps its own mode for an exact restore
}

@test "residue: node_modules whose lock diverged is residue, not cache" {
  w="$(mkwt res2)"
  mkdir -p "$w/node_modules/.pnpm"
  echo 'lock: 1' > "$w/pnpm-lock.yaml"; echo 'lock: 2' > "$w/node_modules/.pnpm/lock.yaml"
  run wt_tombstone "$w" lab diverged --mode clone
  [ "$status" -eq 0 ]
  lastrow | jq -e '(.preserved_list | index("node_modules")) != null and (.caches_skipped | index("node_modules")) == null' >/dev/null
}

@test "clone mode leaves the tree byte-identical; mv + wt_residue_restore round-trips" {
  w="$(mkwt cl1)"
  mkdir -p "$w/brag-output"; echo b > "$w/brag-output/b.json"
  before="$(tree_sums "$w")"
  run wt_tombstone "$w" guard raw --mode clone --event guard-snapshot
  [ "$status" -eq 0 ]
  [ "$(tree_sums "$w")" = "$before" ]
  [ "$(lastrow | jq -r .event)" = guard-snapshot ]
  run wt_tombstone "$w" lab mv
  [ "$status" -eq 0 ]; id="$output"
  [ ! -e "$w/brag-output/b.json" ]
  run wt_residue_restore "$id" "$w"
  [ "$status" -eq 0 ]
  [ "$(tree_sums "$w")" = "$before" ]
}

@test "durable sha: a rebase-landed head (patch-equal, not an ancestor) survives branch delete + gc" {
  w="$(mkwt rb1)"
  commit_in "$w" feature
  x="$(git -C "$w" rev-parse HEAD)"
  git -C "$T/main" cherry-pick "$x" >/dev/null && git -C "$T/main" commit -q --amend -m "feature (rebased)" \
    && git -C "$T/main" push -q origin main
  run wt_tombstone "$w" lab rebased
  [ "$status" -eq 0 ]; id="$output"
  [ "$(lastrow | jq -r .landed)" = true ]
  [ "$(lastrow | jq -r .tomb_ref)" = "refs/wt-tombstone/$id/head" ]
  git -C "$T/main" worktree remove --force "$w"
  git -C "$T/main" branch -D rb1 >/dev/null
  git -C "$T/main" reflog expire --expire=now --all && git -C "$T/main" gc -q --prune=now
  [ "$(git -C "$T/main" rev-parse "refs/wt-tombstone/$id/head")" = "$x" ]
  git -C "$T/main" cat-file -e "$x^{commit}"
}

@test "reflog-only unlanded commit gets a ref and survives gc; a patch-equal one gets none; logs/HEAD copied" {
  w="$(mkwt rf1)"
  commit_in "$w" lostA; a="$(git -C "$w" rev-parse HEAD)"
  git -C "$w" reset -q --hard HEAD~1
  commit_in "$w" landedC; c="$(git -C "$w" rev-parse HEAD)"
  git -C "$T/main" cherry-pick "$c" >/dev/null && git -C "$T/main" push -q origin main
  git -C "$w" reset -q --hard HEAD~1
  commit_in "$w" keptB
  git -C "$w" push -q origin rf1:main 2>/dev/null || { git -C "$w" fetch -q origin && git -C "$w" rebase -q origin/main && git -C "$w" push -q origin rf1:main; }
  run wt_tombstone "$w" lab reflog
  [ "$status" -eq 0 ]; id="$output"
  refs="$(lastrow | jq -r '.reflog_refs[]')"
  [ "$(printf '%s\n' "$refs" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ]
  [ "$(git -C "$T/main" rev-parse "$(printf '%s' "$refs" | head -1)")" = "$a" ]
  [ -f "$WT_TOMB_DIR/$id/logs-HEAD" ]
  git -C "$T/main" worktree remove --force "$w"; git -C "$T/main" branch -D rf1 >/dev/null
  git -C "$T/main" reflog expire --expire=now --all && git -C "$T/main" gc -q --prune=now
  git -C "$T/main" cat-file -e "$a^{commit}"
}

@test "a ref that cannot be created returns 2 and puts the moved residue back" {
  w="$(mkwt bad1)"
  commit_in "$w" unlanded
  mkdir -p "$w/brag-output"; echo keep > "$w/brag-output/k.json"
  : > "$(git -C "$T/main" rev-parse --git-common-dir)/refs/wt-tombstone"   # a FILE where the ref dir must go
  n_before="$(wc -l < "$WT_LEDGER" 2>/dev/null || echo 0)"
  run wt_tombstone "$w" lab bad
  [ "$status" -eq 2 ]
  [ "$(cat "$w/brag-output/k.json")" = keep ]
  [ "$(wc -l < "$WT_LEDGER" 2>/dev/null || echo 0)" = "$n_before" ]
}

@test "--wip snapshots tracked and untracked working content; the tree and real index are untouched" {
  w="$(mkwt wip1)"
  echo changed > "$w/f.txt"; echo new > "$w/untracked.txt"; git -C "$w" add f.txt; echo changed-again > "$w/f.txt"
  st="$(git -C "$w" status --porcelain)"; cached="$(git -C "$w" diff --cached)"
  run wt_tombstone "$w" guard raw --mode clone --event guard-snapshot --wip
  [ "$status" -eq 0 ]; id="$output"
  ref="refs/wt-tombstone/$id/wip"
  [ "$(lastrow | jq -r .wip_ref)" = "$ref" ]
  [ "$(git -C "$T/main" show "$ref:f.txt")" = changed-again ]
  [ "$(git -C "$T/main" show "$ref:untracked.txt")" = new ]
  [ "$(git -C "$w" status --porcelain)" = "$st" ]
  [ "$(git -C "$w" diff --cached)" = "$cached" ]
}

@test "--checkpoint-ref points the durable ref at the teammate checkpoint" {
  w="$(mkwt ck1)"
  echo dirty > "$w/f.txt"
  t="$(git -C "$w" write-tree)"; c="$(git -C "$w" commit-tree "$t" -p HEAD -m ck)"
  git -C "$w" update-ref refs/wip/member/LAST "$c"
  run wt_tombstone "$w" teammate-auto-shutdown checkpointed --checkpoint-ref refs/wip/member/LAST
  [ "$status" -eq 0 ]; id="$output"
  [ "$(git -C "$T/main" rev-parse "refs/wt-tombstone/$id/head")" = "$c" ]
  [ "$(lastrow | jq -r .checkpoint_ref)" = refs/wip/member/LAST ]
}

@test "wt_prune_logged: admin-pruned row with head and branch, logs/HEAD copied, then the prune runs" {
  w="$(mkwt pr1)"
  commit_in "$w" gone
  h="$(git -C "$w" rev-parse HEAD)"
  adm="$(git -C "$T/main" rev-parse --path-format=absolute --git-common-dir)/worktrees/pr1"
  rm -rf "$w"
  run wt_prune_logged "$T/main"
  [ "$status" -eq 0 ]
  [ ! -d "$adm" ]
  row="$(lastrow)"
  [ "$(printf '%s' "$row" | jq -r .event)" = admin-pruned ]
  [ "$(printf '%s' "$row" | jq -r .branch)" = pr1 ]
  [ "$(printf '%s' "$row" | jq -r .head)" = "$h" ]
  [ "$(printf '%s' "$row" | jq -r .path)" = "$w" ] || [ "$(printf '%s' "$row" | jq -r .path)" = "$(cd "$T" && pwd -P)/wts/pr1" ]
  id="$(printf '%s' "$row" | jq -r .id)"
  [ -f "$WT_TOMB_DIR/$id/logs-HEAD" ]
}

@test "wt_emit_event: one queue line and the wake file advances" {
  w="$(mkwt ev1)"
  mkdir -p "$WT_STATE_DIR"; touch -t 202001010000 "$WT_WAKE_FILE"
  run wt_emit_event pane-teardown "$w" sid-1
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WT_EVENTS_FILE" | tr -d ' ')" = 1 ]
  jq -e '.ev == "pane-teardown" and .sid == "sid-1" and (.repo | length > 0)' "$WT_EVENTS_FILE" >/dev/null
  [ "$(stat -f %m "$WT_WAKE_FILE")" -gt 1600000000 ]
}

@test "ref expiry: refs past cleanupPeriodDays go, residue stays; a restored tombstone keeps its refs" {
  echo '{"cleanupPeriodDays":365}' > "$HOME/.claude/settings.json"
  w="$(mkwt ex1)"; commit_in "$w" one; mkdir -p "$w/brag-output"; echo r > "$w/brag-output/r"
  id1="$(wt_tombstone "$w" lab one)"
  w2="$(mkwt ex2)"; commit_in "$w2" two
  id2="$(wt_tombstone "$w2" lab two)"
  printf '{"ts":"%s","event":"restored","id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id2" >> "$WT_LEDGER"
  WT_NOW=$(( $(date +%s) + 400 * 86400 )) wt_ref_expire "$T/main"
  ! git -C "$T/main" rev-parse -q --verify "refs/wt-tombstone/$id1/head" || false
  git -C "$T/main" rev-parse -q --verify "refs/wt-tombstone/$id2/head"
  [ -f "$WT_TOMB_DIR/$id1/residue/brag-output/r" ]
  jq -e --arg i "$id1" 'select(.event == "ref-expired" and .id == $i)' "$WT_LEDGER" >/dev/null
}

@test "purge refuses without --operator and keeps the residue" {
  w="$(mkwt pg1)"; mkdir -p "$w/brag-output"; echo r > "$w/brag-output/r"
  id="$(wt_tombstone "$w" lab pg)"
  run "$CLI" purge "$id"
  [ "$status" -eq 2 ]
  [ -d "$WT_TOMB_DIR/$id/residue" ]
  run "$CLI" purge "$id" --operator
  [ "$status" -eq 0 ]
  [ ! -d "$WT_TOMB_DIR/$id" ]
}

@test "cleanupPeriodDays: the max over config roots; a root without the key counts 30" {
  mkdir -p "$T/r1" "$T/r2"; echo '{"cleanupPeriodDays":365}' > "$T/r1/settings.json"
  [ "$(WT_CONFIG_ROOTS="$T/r1:$T/r2" wt_cleanup_period_days)" = 365 ]
  [ "$(WT_CONFIG_ROOTS="$T/r2" wt_cleanup_period_days)" = 30 ]
}

@test "wt_tomb_find: by sid or branch, never by path alone when a key is given; sids come from transcripts" {
  w="$(mkwt fd1)"
  slug="$(printf '%s' "$(cd "$w" && pwd -P)" | sed 's#[/.]#-#g')"
  mkdir -p "$HOME/.claude/projects/$slug"; echo '{}' > "$HOME/.claude/projects/$slug/sid-abc.jsonl"
  wt_tombstone "$w" lab fd --mode clone >/dev/null
  p="$(lastrow | jq -r .path)"
  [ "$(lastrow | jq -r '.sids[0]')" = sid-abc ]
  run wt_tomb_find "$p" --sid sid-abc;   [ "$status" -eq 0 ]
  run wt_tomb_find "$p" --sid other;     [ "$status" -eq 1 ]
  run wt_tomb_find "$p" --branch fd1;    [ "$status" -eq 0 ]
  echo 'not json {' >> "$WT_LEDGER"
  run wt_tomb_find "$p";                 [ "$status" -eq 0 ]
}

@test "runs under /bin/bash 3.2 (bin/cc-reaper's interpreter)" {
  w="$(mkwt b32)"; mkdir -p "$w/brag-output"; echo r > "$w/brag-output/r"
  run /bin/bash -c '. "$1" && wt_tombstone "$2" lab bash32' _ "$LIB" "$w"
  [ "$status" -eq 0 ]
  [ -f "$WT_TOMB_DIR/$output/residue/brag-output/r" ]
}

@test "RED control: the same removal with no tombstone loses the residue" {
  w="$(mkwt red1)"; mkdir -p "$w/brag-output"; echo paid > "$w/brag-output/render.json"
  git -C "$T/main" worktree remove --force "$w"
  [ ! -e "$w/brag-output/render.json" ]
  [ -z "$(find "$T" -name render.json -path '*brag-output*' 2>/dev/null)" ]
}

@test "sids: a path with _ and a space maps to Claude Code's slug (every non-alphanumeric is -)" {
  git -C "$T/main" worktree add -q -b odd1 "$T/wts/odd_name with space" main
  w="$(cd "$T/wts/odd_name with space" && pwd -P)"
  slug="$(printf '%s' "$w" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$HOME/.claude/projects/$slug"; echo '{}' > "$HOME/.claude/projects/$slug/sid-odd.jsonl"
  run wt__sids_of "$w"
  [ "$output" = sid-odd ]
}

