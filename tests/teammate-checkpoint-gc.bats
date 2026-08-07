#!/usr/bin/env bats
# teammate-checkpoint-gc — the fixed per-tool-call hook must GC what it accumulates (audit 09 D-10).
#
# `matcher: ""` on PostToolUse means teammate-checkpoint.sh runs on EVERY tool call in EVERY
# session. Each invocation writes `~/.claude/watchdog/cp-<sid>.count` and creates append-only
# `refs/checkpoints/<member>/<ts>` refs — and unlike memory-nudge.sh:26 (`-mtime +1 -delete`) or
# completion-assert.sh (`.fired`, `-mtime +7 -delete`) it GC'd nothing: 76 orphan cp-*.count files
# live, and this repo alone already exceeds 1000 checkpoint refs (a real git-performance cost).
#
# Contract pinned here: GC is DAMPED to at most once/day via a stamp file, costs ONE fork on the
# common (already-swept) path, deletes cp-*.count older than 2 days, and prunes checkpoint refs
# older than 14 days while ALWAYS keeping the newest 3 per member.
#
# EXTENDED 2026-08-06 (cc-backlog 700269d9c450) after the landed sweep still let the store reach
# 6,101 refs / 613 KB packed-refs. Three further clauses are pinned, one per measured defect:
#   · BATCHED — deletion is ONE `update-ref --stdin` transaction, never one fork per ref. The old
#     shape cost 5.69 s per 500 deletes against this hook's `"timeout": 10` in settings.json, so
#     the sweep was SIGKILLed mid-pass every day and the stamp blocked retry for 24 h.
#   · PER-DIRECTORY DAMPER — one machine-wide stamp let the first session to fire in ANY repo
#     consume the day's sweep for EVERY repo.
#   · RANK CAP — age alone cannot bound a member producing hundreds of refs/day (every root
#     session keys on the repo basename, so ~20 sessions shared one member holding 2,630 refs, all
#     inside the 14-day window where the age rule cannot reach them).
#
# Harness laws: L1 refs are created by real `git update-ref` against a real repo with real
# committer dates; L2 assertions key on the failure-distinct survivors (a "delete everything" bug
# and a "delete nothing" bug both go RED); L3 `[ ]` / `grep -q` only; L4 each rule has a
# must-delete AND a must-survive fixture; L5 the batching clause is asserted on the MECHANISM (a
# counting `git` shim), because a store small enough to fit a test also fits the old fork-per-ref
# loop — a survivor count alone could not fail on the pre-fix code.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/teammate-checkpoint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/watchdog" "$HOME/.claude/logs"
  WD="$HOME/.claude/watchdog"
  WT="$BATS_TEST_TMPDIR/wt-team-alice"
  mkdir -p "$WT"
  git -C "$WT" init -q
  git -C "$WT" config user.email t@t; git -C "$WT" config user.name t
  printf 'seed\n' > "$WT/seed.txt"
  git -C "$WT" add -A >/dev/null; git -C "$WT" commit -qm seed
  BASE="$(git -C "$WT" rev-parse HEAD)"
}

payload() { # <event>
  jq -nc --arg e "$1" --arg c "$WT" \
    '{session_id:"sid-gc",hook_event_name:$e,tool_name:"Bash",cwd:$c}'
}

fire() { payload "${1:-Stop}" | bash "$HOOK" >/dev/null 2>&1; }

# create a checkpoint ref for <member>/<stamp> with a committer date <days> ago
mkref() { # <member> <stamp> <days-ago>
  local sha d
  d="$(date -u -v-"$3"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$3 days ago" +%Y-%m-%dT%H:%M:%SZ)"
  sha="$(GIT_COMMITTER_DATE="$d" GIT_AUTHOR_DATE="$d" git -C "$WT" commit-tree "$BASE^{tree}" -p "$BASE" -m "cp $2" 2>/dev/null)"
  git -C "$WT" update-ref "refs/checkpoints/$1/$2" "$sha"
}

refs_for() { git -C "$WT" for-each-ref --format='%(refname)' "refs/checkpoints/$1" | grep -c . || true; }
has_ref()  { git -C "$WT" show-ref --verify --quiet "refs/checkpoints/$1/$2"; }

# The damper stamp is keyed on the producing directory. This MUST replay the hook's derivation
# exactly — its own /private normalization, then the same guarded right-truncation.
#
# A MIRRORED DERIVATION IS THE TRAP THIS FILE ALMOST FELL INTO. The first cut of the hook used a
# bare `${k: -180}`, which in bash yields the EMPTY string for any shorter path — so every dir keyed
# to a bare `.gc-stamp` and the per-directory damper shipped inert. Mirroring that expression here
# made the three stamp-PATH tests pass VACUOUSLY: both sides named the same wrong file. Only the
# behavioural test below — two repos, which needs the keys to actually DIFFER — could fail on it.
# Keep it that way: assert consequences, not just that two copies of a formula agree.
stamp_for() {
  local c="${1#/private}" k; k="${c//\//-}"
  (( ${#k} > 180 )) && k="${k: -180}"
  printf '%s' "$WD/.gc-stamp$k"
}
STAMP() { stamp_for "$WT"; }

@test "orphan cp-*.count files older than 2 days are swept; fresh ones survive" {
  : > "$WD/cp-old.count"; touch -t "$(date -u -v-5d +%Y%m%d0000 2>/dev/null || date -u -d '5 days ago' +%Y%m%d0000)" "$WD/cp-old.count"
  : > "$WD/cp-fresh.count"
  fire Stop
  [ ! -f "$WD/cp-old.count" ]
  [ -f "$WD/cp-fresh.count" ]
}

@test "checkpoint refs older than 14 days are pruned" {
  mkref alice 20260101T000000Z 40
  mkref alice 20260102T000000Z 39
  mkref alice 20260103T000000Z 38
  mkref alice 20260104T000000Z 37
  fire Stop
  [ "$(refs_for alice)" -eq 3 ]
}

@test "the newest 3 per member ALWAYS survive, however old they are" {
  mkref bob 20250101T000000Z 400
  mkref bob 20250102T000000Z 399
  mkref bob 20250103T000000Z 398
  fire Stop
  [ "$(refs_for bob)" -eq 3 ]
  has_ref bob 20250101T000000Z
}

@test "GC is per-member — a second member's newest 3 are not consumed by the first" {
  mkref alice 20260101T000000Z 40
  mkref alice 20260102T000000Z 39
  mkref alice 20260103T000000Z 38
  mkref alice 20260104T000000Z 37
  mkref carol 20260105T000000Z 36
  fire Stop
  [ "$(refs_for alice)" -eq 3 ]
  [ "$(refs_for carol)" -eq 1 ]
}

@test "recent refs beyond the newest 3 survive (age is required, not just rank)" {
  mkref dave 20260701T000000Z 5
  mkref dave 20260702T000000Z 4
  mkref dave 20260703T000000Z 3
  mkref dave 20260704T000000Z 2
  fire Stop
  [ "$(refs_for dave)" -eq 4 ]
}

@test "GC is damped — a second fire in the same day does not re-sweep" {
  fire Stop
  [ -f "$(STAMP)" ]
  mkref erin 20260101T000000Z 40
  mkref erin 20260102T000000Z 39
  mkref erin 20260103T000000Z 38
  mkref erin 20260104T000000Z 37
  fire Stop
  [ "$(refs_for erin)" -eq 4 ]
}

@test "an expired stamp re-arms the sweep" {
  fire Stop
  touch -t "$(date -u -v-3d +%Y%m%d0000 2>/dev/null || date -u -d '3 days ago' +%Y%m%d0000)" "$(STAMP)"
  mkref frank 20260101T000000Z 40
  mkref frank 20260102T000000Z 39
  mkref frank 20260103T000000Z 38
  mkref frank 20260104T000000Z 37
  fire Stop
  [ "$(refs_for frank)" -eq 3 ]
}

@test "checkpointing itself still works (GC change is additive)" {
  printf 'dirty\n' > "$WT/new.txt"
  fire Stop
  git -C "$WT" show-ref --verify --quiet "refs/wip/team-alice/LAST"
}

@test "the GC stamp is never left behind outside the watchdog dir" {
  fire Stop
  [ -f "$(STAMP)" ]
  [ ! -e "$WT/.gc-stamp" ]
}

# ── the three 2026-08-06 clauses ────────────────────────────────────────────────────────────────

@test "deletion is BATCHED — one update-ref transaction, never one fork per ref" {
  local shim="$BATS_TEST_TMPDIR/shim" calls="$BATS_TEST_TMPDIR/git-calls.log" realgit
  realgit="$(command -v git)"            # resolve BEFORE shadowing, or the shim recurses
  mkdir -p "$shim"
  # unquoted delimiter: $calls/$realgit interpolate now, \$* and \$@ stay for the shim to expand
  cat > "$shim/git" <<SHIM
#!/bin/bash
printf '%s\n' "\$*" >> '$calls'
exec '$realgit' "\$@"
SHIM
  chmod +x "$shim/git"
  mkref ivan 20260101T000000Z 40
  mkref ivan 20260102T000000Z 39
  mkref ivan 20260103T000000Z 38
  mkref ivan 20260104T000000Z 37
  mkref ivan 20260105T000000Z 36
  : > "$calls"
  PATH="$shim:$PATH" fire Stop
  [ "$(refs_for ivan)" -eq 3 ]                             # it really did delete
  [ "$(grep -c -- 'update-ref -d' "$calls" || true)" -eq 0 ]   # ...with zero per-ref forks
  [ "$(grep -c -- 'update-ref --stdin' "$calls" || true)" -eq 1 ]
}

@test "the damper is PER-DIRECTORY — a sweep in one repo does not starve another" {
  local WT2="$BATS_TEST_TMPDIR/wt-team-bob" base2 d sha i
  mkdir -p "$WT2"
  git -C "$WT2" init -q
  git -C "$WT2" config user.email t@t; git -C "$WT2" config user.name t
  printf 'seed\n' > "$WT2/seed.txt"
  git -C "$WT2" add seed.txt >/dev/null; git -C "$WT2" commit -qm seed
  base2="$(git -C "$WT2" rev-parse HEAD)"
  d="$(date -u -v-40d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '40 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  for i in 1 2 3 4; do
    sha="$(GIT_COMMITTER_DATE="$d" GIT_AUTHOR_DATE="$d" \
      git -C "$WT2" commit-tree "$base2^{tree}" -p "$base2" -m "cp $i")"
    git -C "$WT2" update-ref "refs/checkpoints/zed/2026010${i}T000000Z" "$sha"
  done
  fire Stop                                                # repo 1 sweeps and takes ITS stamp
  jq -nc --arg e Stop --arg c "$WT2" \
    '{session_id:"sid-gc2",hook_event_name:$e,tool_name:"Bash",cwd:$c}' \
    | bash "$HOOK" >/dev/null 2>&1                         # repo 2, SAME day — must still sweep
  # The SURVIVOR COUNT is deliberately the only assertion: a stamp-path check here would fail
  # first on the pre-fix hook and mask the starvation clause this test exists to prove (the stamp
  # location is already pinned by "damped" and "never left behind"). Pre-fix, repo 1's
  # machine-wide stamp suppresses this sweep entirely and zed keeps all 4.
  [ "$(git -C "$WT2" for-each-ref --format='%(refname)' refs/checkpoints/zed | grep -c .)" -eq 3 ]
}

@test "a member over the RANK CAP is trimmed even when every ref is recent" {
  local i
  for i in 1 2 3 4 5 6 7 8 9; do mkref gina "2026070${i}T000000Z" 1; done
  TEAMMATE_CHECKPOINT_KEEP=5 fire Stop     # scoped to the call, not exported into the whole test
  [ "$(refs_for gina)" -eq 5 ]
  has_ref gina 20260709T000000Z                            # the NEWEST is what survives
}

@test "the rank cap does not trim a member under it" {
  local i
  for i in 1 2 3 4; do mkref hana "2026070${i}T000000Z" 1; done
  TEAMMATE_CHECKPOINT_KEEP=5 fire Stop
  [ "$(refs_for hana)" -eq 4 ]
}
