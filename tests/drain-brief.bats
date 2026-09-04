#!/usr/bin/env bats
# scripts/drain-brief.sh — a drain link's brief is a PURE FUNCTION of the template and its numbers.
#
# WHAT IS PINNED. The old chain regenerated each brief from its predecessor's and accreted to 3,366
# lines with its claim/close instructions spliced out (BACKLOG_ZERO_2026-09-04). The properties that
# stop that recurring: (a) every placeholder is substituted and none survives, (b) the output does
# not depend on any previous brief, (c) a template past the line cap REFUSES rather than shipping a
# longer brief one link at a time, (d) an existing brief is never clobbered silently, (e) the pointer
# stays a pointer (handoff-fire expands it into one argv word — a 250 KB brief there is
# `(eval):2: command too long`, thrown after `/exit` has already killed the caller).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="$REPO/scripts/drain-brief.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_DRAIN_BRIEF_DIR="$BATS_TEST_TMPDIR/briefs"
}

@test "substitutes every placeholder and leaves none behind" {
  run bash "$SUBJECT" --num 300 --lane infra --project claude-infrastructure \
      --worktree /tmp/wt --since 2026-09-04T12:00:00Z --min 3 --print
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '{{')" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^# DRAIN LINK #300 — lane infra · project claude-infrastructure · window opened 2026-09-04T12:00:00Z')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c -- '--num 301 --lane infra --project claude-infrastructure --min 3')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'cd /tmp/wt ')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c -- '--closure-report 2026-09-04T12:00:00Z --min 3')" -ge 2 ]
}

@test "--print writes nothing" {
  run bash "$SUBJECT" --num 300 --print
  [ "$status" -eq 0 ]
  [ ! -d "$CC_DRAIN_BRIEF_DIR" ]
}

@test "writes the brief and a short pointer, and prints the pointer path on STDOUT alone" {
  # stdout is the pointer path and nothing else — a caller captures it with $(…); the summary goes
  # to stderr so it cannot land in the captured value.
  out="$(bash "$SUBJECT" --num 300 --lane infra --since 2026-09-04T12:00:00Z 2>"$BATS_TEST_TMPDIR/err")"
  [ "$out" = "$CC_DRAIN_BRIEF_DIR/fire-pointer-infra-300.txt" ]
  [ "$(grep -c 'drain-brief: wrote' "$BATS_TEST_TMPDIR/err")" -eq 1 ]
  [ -f "$CC_DRAIN_BRIEF_DIR/fire-drain-infra-recycle300.txt" ]
  [ "$(wc -c < "$out" | tr -d ' ')" -lt 400 ]
  [ "$(grep -c 'fire-drain-infra-recycle300.txt in full' "$out")" -eq 1 ]
  [ "$(grep -c 'recycle #300' "$out")" -eq 1 ]
}

# LANE `a` KEEPS THE OLD CHAIN'S FILENAMES so scripts/drain-chain-assert.sh's glob still sees it.
@test "lane a uses the legacy filenames the chain detector globs" {
  out="$(bash "$SUBJECT" --num 300 --lane a 2>/dev/null)"
  [ "$out" = "$CC_DRAIN_BRIEF_DIR/fire-pointer-300.txt" ]
  [ -f "$CC_DRAIN_BRIEF_DIR/fire-drain-recycle300.txt" ]
}

# THE OUTPUT DOES NOT DEPEND ON A PREVIOUS BRIEF. Two generations with the same inputs are
# byte-identical even with a "predecessor" brief full of findings sitting beside them.
@test "the brief is a function of its inputs, never of a predecessor brief" {
  mkdir -p "$CC_DRAIN_BRIEF_DIR"
  printf '## FINDINGS FROM #299\nmethod 271: ...\n' > "$CC_DRAIN_BRIEF_DIR/fire-drain-infra-recycle299.txt"
  a="$(bash "$SUBJECT" --num 300 --lane infra --since 2026-09-04T12:00:00Z --print)"
  b="$(bash "$SUBJECT" --num 300 --lane infra --since 2026-09-04T12:00:00Z --print)"
  [ "$a" = "$b" ]
  [ "$(printf '%s' "$a" | grep -c 'method 271')" -eq 0 ]
}

@test "an existing brief for the same lane and number refuses without --force, and is replaced with it" {
  bash "$SUBJECT" --num 300 --lane infra >/dev/null
  run bash "$SUBJECT" --num 300 --lane infra
  [ "$status" -eq 3 ]
  run bash "$SUBJECT" --num 300 --lane infra --force --since 2026-09-04T12:34:56Z
  [ "$status" -eq 0 ]
  [ "$(grep -c 'window opened 2026-09-04T12:34:56Z' "$CC_DRAIN_BRIEF_DIR/fire-drain-infra-recycle300.txt")" -eq 1 ]
}

# THE RATCHET. A template that grows past the cap is the old chain coming back; it refuses to
# generate rather than shipping the longer brief.
@test "a template over the line cap refuses to generate" {
  t="$BATS_TEST_TMPDIR/big.md"
  seq 1 250 | sed 's/^/line /' > "$t"
  CC_DRAIN_TEMPLATE="$t" run bash "$SUBJECT" --num 300 --print
  [ "$status" -eq 5 ]
  [ "$(printf '%s' "$output" | grep -c 'cap is 200')" -eq 1 ]
  # …and the cap is the variable, not the number: the same template passes under a raised cap.
  CC_DRAIN_TEMPLATE="$t" CC_DRAIN_BRIEF_MAX_LINES=300 run bash "$SUBJECT" --num 300 --print
  [ "$status" -eq 0 ]
}

# THE LANE STAMPS ITSELF. Recycle #300 measured cc-backlog's ps-walk lane derivation returning
# EMPTY under load, so its own close counted as another lane's and the floor read UNMET; the
# explicit declaration is what the goal's instrument reads, so the brief must carry it.
@test "the brief exports CC_BACKLOG_LANE=local-drain in its setup" {
  run bash "$SUBJECT" --num 300 --print
  [ "$(printf '%s' "$output" | grep -c '^    export CC_BACKLOG_LANE=local-drain')" -eq 1 ]
}

@test "the shipped template is under the cap with room, and carries the claim/close loop" {
  t="$REPO/scripts/drain-brief.template.md"
  [ "$(wc -l < "$t" | tr -d ' ')" -le 150 ]
  [ "$(grep -c 'cc-backlog claim <id>' "$t")" -eq 1 ]
  [ "$(grep -c 'cc-backlog done <id>' "$t")" -ge 1 ]
  [ "$(grep -c 'drain-pick.sh' "$t")" -ge 1 ]
  [ "$(grep -c 'File nothing' "$t")" -eq 1 ]
}

@test "a placeholder the generator does not know refuses rather than shipping it" {
  t="$BATS_TEST_TMPDIR/odd.md"
  printf 'link {{N}} on {{PLANET}}\n' > "$t"
  CC_DRAIN_TEMPLATE="$t" run bash "$SUBJECT" --num 300 --print
  [ "$status" -eq 6 ]
  [ "$(printf '%s' "$output" | grep -c 'PLANET')" -eq 1 ]
}

@test "argument shapes are validated: number, lane, since, worktree" {
  run bash "$SUBJECT" --num three --print;                                [ "$status" -eq 2 ]
  run bash "$SUBJECT" --num 3 --lane 'In fra' --print;                    [ "$status" -eq 2 ]
  run bash "$SUBJECT" --num 3 --since yesterday --print;                  [ "$status" -eq 2 ]
  run bash "$SUBJECT" --num 3 --worktree relative/path --print;           [ "$status" -eq 2 ]
}

# ── a lane for ANOTHER project lands with THAT repo's rail ──────────────────────────────────────
#
# The drain scripts always come from the claude-infrastructure checkout ($INFRA); the project's own
# gate and landing rail are substituted per project, because a landing cost is a fact only the repo
# can state (global CLAUDE.md § Ship policy). reso's trunk CLAUDE.md § Deploy trigger says a push to
# main ships nothing since 2026-08-02 and names scripts/land-status.sh as the live check.
@test "a reso lane brief calls the infra scripts by absolute path and lands with reso's own rail" {
  run bash "$SUBJECT" --num 1 --lane reso --project reso-management-app --infra /opt/infra --print
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'bash /opt/infra/scripts/drain-pick.sh --project reso-management-app')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'bash /opt/infra/scripts/drain-recycle-fire.sh --closure-report .* --project reso-management-app')" -ge 2 ]
  [ "$(printf '%s' "$output" | grep -c 'bash /opt/infra/scripts/drain-recycle-fire.sh --num 2 --lane reso --project reso-management-app')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'land-status.sh')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'pnpm typecheck')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'ship-land.sh')" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'no §2.1 entry to write')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c '{{')" -eq 0 ]
}

@test "the infra lane brief keeps ship-land and the §2.1 entry" {
  run bash "$SUBJECT" --num 300 --lane infra --project claude-infrastructure --print
  [ "$(printf '%s' "$output" | grep -c 'bash scripts/ship-land.sh')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'gate-select.sh --direct')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'BACKLOG_DRAIN_24_7.md')" -ge 1 ]
  [ "$(printf '%s' "$output" | grep -c 'land-status.sh')" -eq 0 ]
}

@test "an unknown project gets the read-your-own-CLAUDE.md rail, never a guessed land command" {
  run bash "$SUBJECT" --num 1 --lane docclf --project doc_classifier --print
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'read it first')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'ship-land.sh')" -eq 0 ]
}
