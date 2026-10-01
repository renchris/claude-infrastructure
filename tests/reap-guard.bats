#!/usr/bin/env bats
# reaper-safety — reap-guard: the standalone REAP|DEFER decision module. The tool's --selftest RED-proves
# R-a/b/c with real git fixtures; these bats add CLI-level regression on the exit-code contract
# (0=REAP, 10=DEFER) and the outcome-record.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/scripts/reap-guard.sh"
  export CC_REAP_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
  NOW="$(date +%s)"
}
mkgit() { # <dir> [<committer-epoch>]
  # `git -C ""` is a NO-OP, not an error — an empty <dir> would write this identity into the cwd repo.
  : "${1:?mkgit: repo path required}"
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo seed > "$1/a.txt"; git -C "$1" add a.txt
  if [ -n "${2:-}" ]; then GIT_AUTHOR_DATE="@$2" GIT_COMMITTER_DATE="@$2" git -C "$1" commit -qm seed
  else git -C "$1" commit -qm seed; fi
}

@test "selftest passes and runs all 16 checks (a zero-check suite must not 'pass')" {
  run "$G" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 16 ]
}

@test "R-a: a just-born teammate (clean tree, within grace) → DEFER (exit 10), not reaped" {
  mkgit "$BATS_TEST_TMPDIR/young"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/young" --member young --spawn-time "$NOW" --grace-s 300
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
}

@test "R-b: past grace, clean, products since spawn → REAP (exit 0)" {
  mkgit "$BATS_TEST_TMPDIR/prod"                                    # commit now (newer than spawn below)
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/prod" --member prod --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
}

@test "R-b: past grace, clean, NO products since spawn → DEFER (exit 10) — the just-born ambiguity" {
  mkgit "$BATS_TEST_TMPDIR/np" "$((NOW-5000))"                      # commit predates spawn
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/np" --member np --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
}

@test "R-c: every decision writes an outcome record with the decision (no silent reap)" {
  mkgit "$BATS_TEST_TMPDIR/prod"
  "$G" decide --worktree "$BATS_TEST_TMPDIR/prod" --member prod --spawn-time "$((NOW-1000))" --grace-s 60 >/dev/null
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-prod-*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REAP" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "finished" ]
}

@test "preserved: a dirty tree still DEFERs (the module only ADDS safety, removes no existing defer)" {
  mkgit "$BATS_TEST_TMPDIR/dirty"; echo change >> "$BATS_TEST_TMPDIR/dirty/a.txt"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/dirty" --member dirty --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 10 ]
}

# ── R-d operator-adoption hold (2026-07-25): the 2026-07-24 reaper incident class, on the TeammateIdle
#    path the c063ca0 fix never touched. Reads WHO drove the last turn (ce_last_interactive_age). ──
utx() { # <transcript> <ago-seconds> — append a real operator user prompt <ago>s before now
  local f="$1" ago="$2" ts
  ts="$(date -u -v-"${ago}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( $(date +%s) - ago ))" +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"type":"user","isMeta":false,"message":{"role":"user","content":"operator here"},"timestamp":"%s"}\n' "$ts" >> "$f"
}

@test "R-d: adopted teammate (operator prompt AFTER spawn, within hold) → DEFER even with products" {
  mkgit "$BATS_TEST_TMPDIR/adopt"                                   # products since spawn (commit now)
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$BATS_TEST_TMPDIR/proj/slug"
  utx "$BATS_TEST_TMPDIR/proj/slug/sid-adopt.jsonl" 120            # operator typed 120s ago
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/adopt" --member adopt --spawn-time "$((NOW-3600))" --grace-s 60 --session-id sid-adopt
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
}

@test "R-d: finished teammate (only the spawn brief, no post-spawn operator prompt) → REAP" {
  mkgit "$BATS_TEST_TMPDIR/fin"                                     # products since spawn
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$BATS_TEST_TMPDIR/proj/slug"
  utx "$BATS_TEST_TMPDIR/proj/slug/sid-fin.jsonl" 3600             # the ONLY prompt is the brief, at ~spawn
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/fin" --member fin --spawn-time "$((NOW-3600))" --grace-s 60 --session-id sid-fin
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
}

@test "R-d: --session-id given but transcript UNRESOLVABLE → DEFER (fail-closed)" {
  mkgit "$BATS_TEST_TMPDIR/unres"                                   # products, clean, past grace
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj-empty"; mkdir -p "$BATS_TEST_TMPDIR/proj-empty"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/unres" --member unres --spawn-time "$((NOW-3600))" --grace-s 60 --session-id sid-missing
  [ "$status" -eq 10 ]
}

@test "R-d: transcript RESOLVES but is CORRUPT → DEFER (fail-closed — the empty-answer split)" {
  # Before the 2026-07-25 split, ce_last_interactive_age answered "" for an unreadable transcript
  # exactly as it does for "nobody typed", so this teammate was REAPED on absence of evidence. The path
  # RESOLVES here (so :140-143's unresolvable leg never fires) — only the split catches this world.
  mkgit "$BATS_TEST_TMPDIR/corrupt"                                 # products, clean, past grace
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$BATS_TEST_TMPDIR/proj/slug"
  printf 'not json at all\nhalf a record {"type":"user"\n\001\002 binary junk\n' \
    > "$BATS_TEST_TMPDIR/proj/slug/sid-corrupt.jsonl"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/corrupt" --member corrupt --spawn-time "$((NOW-3600))" --grace-s 60 --session-id sid-corrupt
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-corrupt-*.json' | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "adoption-unreadable" ]      # R-c: the refusal is auditable
}

@test "R-d: an EMPTY transcript → DEFER (zero records proves nothing about operator presence)" {
  mkgit "$BATS_TEST_TMPDIR/empty"
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$BATS_TEST_TMPDIR/proj/slug"
  : > "$BATS_TEST_TMPDIR/proj/slug/sid-empty.jsonl"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/empty" --member empty --spawn-time "$((NOW-3600))" --grace-s 60 --session-id sid-empty
  [ "$status" -eq 10 ]
}

@test "R-d: no --session-id → hold skipped, existing REAP path intact (back-compat)" {
  mkgit "$BATS_TEST_TMPDIR/nocid"                                   # products, clean, past grace
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/nocid" --member nocid --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
}

# ── TREE SCOPE (2026-08-04): the exit-code CONTRACT, at the CLI level ────────────────────────────
# The hook's call site reads codes, not prose — `if ! decide` collapses every non-zero into one
# DEFER, so an own-footprint hold that came back as a bare 10 would be indistinguishable from a
# birth-grace hold and would keep the SURFACE text lying about the cause. These pin the split.

@test "scope=shared + verdict=clean: a SIBLING's dirt no longer DEFERs (exit 0)" {
  mkgit "$BATS_TEST_TMPDIR/shc"; echo sib > "$BATS_TEST_TMPDIR/shc/sibling.txt"
  git -C "$BATS_TEST_TMPDIR/shc" update-ref refs/wip/shc/LAST HEAD
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/shc" --member shc --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope shared --tree-verdict clean
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
}

@test "scope=shared + verdict=dirty-mine → DEFER with the DISTINCT exit 11 (not the generic 10)" {
  mkgit "$BATS_TEST_TMPDIR/shm"; echo sib > "$BATS_TEST_TMPDIR/shm/sibling.txt"
  git -C "$BATS_TEST_TMPDIR/shm" update-ref refs/wip/shm/LAST HEAD
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/shm" --member shm --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope shared --tree-verdict dirty-mine
  [ "$status" -eq 11 ]
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-shm-*.json' | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "dirty-tree-mine" ]
}

@test "scope=shared + verdict=unknown → DEFER 11, fail-closed (ignorance never licenses a close)" {
  mkgit "$BATS_TEST_TMPDIR/shu"; echo sib > "$BATS_TEST_TMPDIR/shu/sibling.txt"
  git -C "$BATS_TEST_TMPDIR/shu" update-ref refs/wip/shu/LAST HEAD
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/shu" --member shu --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope shared
  [ "$status" -eq 11 ]                                # --tree-verdict omitted ⇒ unknown is the DEFAULT
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-shu-*.json' | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "dirty-tree-unattributable" ]
}

@test "POSITIVE CONTROL: scope=owned is byte-identical — a dirty tree still DEFERs with exit 10" {
  # The relaxation must reach ONLY the shared case. Same fixture, same verdict, owned scope: the old
  # code, the old reason. Without this, `--tree-verdict clean` could quietly disarm every dedicated
  # worktree's dirty-tree defer and nothing would report it.
  mkgit "$BATS_TEST_TMPDIR/own"; echo sib > "$BATS_TEST_TMPDIR/own/sibling.txt"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/own" --member own --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope owned --tree-verdict clean
  [ "$status" -eq 10 ]
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-own-*.json' | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "dirty-tree" ]
}

@test "an unknown --tree-scope VALUE is a usage error (exit 2), never a silent fallback to owned" {
  # A typo'd scope defaulting to `owned` would restore the whole-tree read on a shared cwd — the
  # exact defect the flag removes — while every log line claimed the new policy was in force.
  mkgit "$BATS_TEST_TMPDIR/bad"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/bad" --member bad --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope Shared
  [ "$status" -eq 2 ]
}

@test "wiring: teammate-auto-shutdown.sh passes --tree-scope AND --tree-verdict (a default is not a decision)" {
  # Both flags default to the fail-closed answer, so a hook that stopped passing them would not go
  # red anywhere — it would just quietly defer forever again, which is the pre-fix behaviour.
  # Anchored to the `decide` invocation itself (which spans two lines), never to a bare occurrence
  # of the flag — a match anywhere in the file would also be satisfied by a comment or dead code.
  run bash -c "grep -A2 -F '\"\$REAP_GUARD\" decide ' '$REPO/hooks/teammate-auto-shutdown.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'--tree-scope "$_tree_scope"'* ]] || false
  [[ "$output" == *'--tree-verdict "$TREE_VERDICT"'* ]] || false
}

@test "wiring: teammate-auto-shutdown.sh passes --session-id to reap-guard (R-d cannot be bypassed by the hook)" {
  # R-d engages only when a --session-id is supplied. If the live hook stops passing it, every adopted
  # teammate silently reverts to who-blind reaping — so pin the wiring here.
  grep -qE 'decide .*--session-id "\$SESSION_ID"' "$REPO/hooks/teammate-auto-shutdown.sh"
}

# ── R-a' FINISHED-TURN EVIDENCE (2026-09-30): on a SHARED cwd with a clean own footprint, a finished
#    turn after the spawn brief replaces the birth-grace clock. Every case below is YOUNG (age 1000s <
#    grace 3600s) unless it says otherwise, so the clock alone would hold all of them. ──
tbrief() { # <transcript> <ago> — the spawn brief, as the lead's teammate-message
  local ts; ts="$(date -u -v-"$2"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( $(date +%s) - $2 ))" +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"type":"user","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">do X</teammate-message>"},"timestamp":"%s"}\n' "$ts" >> "$1"
}
tdone() { printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}\n' >> "$1"; }
ft_setup() { # <name> — shared-scope fixture: lead's checkout, old seed commit, transcript root
  mkgit "$BATS_TEST_TMPDIR/$1" "$((NOW-5000))"
  export CC_REAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/proj"; mkdir -p "$BATS_TEST_TMPDIR/proj/slug"
  TX="$BATS_TEST_TMPDIR/proj/slug/sid-$1.jsonl"
}
kind_of() { jq -r '.reason_kind' "$(find "$CC_REAP_RECORDS_DIR" -name "reap-$1-*.json" | head -1)"; }

@test "R-a': shared + clean + young + FINISHED turn → REAP (exit 0), recorded shared-finished-turn" {
  ft_setup ftfin; tbrief "$TX" 1000; tdone "$TX"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftfin" --member ftfin --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope shared --tree-verdict clean --session-id sid-ftfin
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
  [ "$(kind_of ftfin)" = "shared-finished-turn" ]
}

@test "R-a' CONTROL: same, but the transcript holds ONLY the spawn brief → DEFER 10 grace-held" {
  ft_setup ftbrief; tbrief "$TX" 1000
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftbrief" --member ftbrief --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope shared --tree-verdict clean --session-id sid-ftbrief
  [ "$status" -eq 10 ]
  [ "$(kind_of ftbrief)" = "grace-held" ]
}

@test "R-a': a turn still MID-TOOL (last record a tool_use) is not a finished turn → grace-held" {
  ft_setup ftmid; tbrief "$TX" 1000
  printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash"}]}}\n' >> "$TX"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftmid" --member ftmid --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope shared --tree-verdict clean --session-id sid-ftmid
  [ "$status" -eq 10 ]
  [ "$(kind_of ftmid)" = "grace-held" ]
}

@test "R-a': shared + dirty-mine + finished turn → DEFER 11 (own dirt still holds; evidence never licenses it)" {
  ft_setup ftmine; tbrief "$TX" 1000; tdone "$TX"; echo mine > "$BATS_TEST_TMPDIR/ftmine/mine.txt"
  # past grace: the dirty-mine leg is what must answer, with its distinct code
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftmine" --member ftmine --spawn-time "$((NOW-1000))" --grace-s 60 \
      --tree-scope shared --tree-verdict dirty-mine --session-id sid-ftmine
  [ "$status" -eq 11 ]
  [ "$(kind_of ftmine)" = "dirty-tree-mine" ]
  # young: the evidence applies only to verdict=clean, so the clock still holds a member with its own dirt
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftmine" --member ftmine2 --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope shared --tree-verdict dirty-mine --session-id sid-ftmine
  [ "$status" -eq 10 ]
  [ "$(kind_of ftmine2)" = "grace-held" ]
}

@test "R-a': OWNED scope + young + finished turn → still DEFER 10 grace-held (unchanged)" {
  ft_setup ftown; tbrief "$TX" 1000; tdone "$TX"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftown" --member ftown --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope owned --tree-verdict clean --session-id sid-ftown
  [ "$status" -eq 10 ]
  [ "$(kind_of ftown)" = "grace-held" ]
}

@test "R-a': shared + finished turn + operator prompt after spawn → DEFER 10 operator-adopted (R-d still runs)" {
  ft_setup ftadopt; tbrief "$TX" 1000; tdone "$TX"; utx "$TX" 120; tdone "$TX"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/ftadopt" --member ftadopt --spawn-time "$((NOW-1000))" --grace-s 3600 \
      --tree-scope shared --tree-verdict clean --session-id sid-ftadopt
  [ "$status" -eq 10 ]
  [ "$(kind_of ftadopt)" = "operator-adopted" ]
}
