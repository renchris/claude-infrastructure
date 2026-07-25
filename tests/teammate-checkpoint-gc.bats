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
# Harness laws: L1 refs are created by real `git update-ref` against a real repo with real
# committer dates; L2 assertions key on the failure-distinct survivors (a "delete everything" bug
# and a "delete nothing" bug both go RED); L3 `[ ]` / `grep -q` only; L4 each rule has a
# must-delete AND a must-survive fixture.

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
  [ -f "$WD/.gc-stamp" ]
  mkref erin 20260101T000000Z 40
  mkref erin 20260102T000000Z 39
  mkref erin 20260103T000000Z 38
  mkref erin 20260104T000000Z 37
  fire Stop
  [ "$(refs_for erin)" -eq 4 ]
}

@test "an expired stamp re-arms the sweep" {
  fire Stop
  touch -t "$(date -u -v-3d +%Y%m%d0000 2>/dev/null || date -u -d '3 days ago' +%Y%m%d0000)" "$WD/.gc-stamp"
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
  [ -f "$WD/.gc-stamp" ]
  [ ! -e "$WT/.gc-stamp" ]
}
