#!/usr/bin/env bats
# research-zero-allowed-prompts.bats — REPORT.md §8 item 2
# (docs/research/upfront-research-exhaustion-2026-09-30/): a gap-finding prompt with a positive
# quota ("Find 2-3 gaps", "List 3", "name 1-3 missing axes") can never return "nothing", so a
# stop rule that waits for a quiet round is unreachable. Every research-facing prompt must allow
# zero, and inside an active program the open-ended "what is missing?" is the frame critique's.
#
# The detector runs over EVERY agents/*.md plus the research skill, not a fixed list of lines,
# so a quota reintroduced anywhere in those prompts fails here.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never the operator's live ~/
  # A count of gaps/axes/dimensions demanded up front: "find|list|name N[-M] …" or "N-M axes|gaps".
  QUOTA='\b(find|list|name)[[:space:]]+[1-9]([-–][0-9])?\b|\b[1-9][-–][0-9][[:space:]]+(gaps|axes|missing|dimensions)\b'
}

prompts() {
  ls "$REPO"/agents/*.md
  printf '%s\n' "$REPO/skills/research-subagents/SKILL.md"
  ls "$REPO"/skills/research-program/SKILL.md "$REPO"/skills/research-program/briefs/*.md   # wave B2
}

@test "positive control: the detector catches every quota spelling the report cited" {
  local s
  for s in 'Find 2-3 gaps. Investigate them.' 'name 1-3 plausible axes the decomposition is' \
           'MISSING — name 1-3 missing axes' 'and why not? List 3 with reasons.' 'List 3.' \
           '- **NEGATIVE SPACE** — 2-3 axes adjacent to yours'; do
    printf '%s\n' "$s" | grep -qiE "$QUOTA" || { echo "detector missed: $s"; return 1; }
  done
  # …and does not fire on an upper bound or a zero-allowed wording
  ! printf '%s\n' 'name the missing axes, up to 3 — zero is a valid answer' | grep -qiE "$QUOTA"
}

@test "no research prompt demands a positive count of gaps, axes or dimensions" {
  local hits
  hits="$(prompts | while IFS= read -r f; do grep -HniE "$QUOTA" "$f"; done || true)"
  [ -z "$hits" ] || { printf 'quota still present:\n%s\n' "$hits"; return 1; }
}

@test "each gap-finding site states that zero is a valid answer" {
  grep -qi 'zero is a valid answer' "$REPO/agents/deep-research.md"
  grep -qi 'zero is a valid answer' "$REPO/agents/deep-research-sonnet.md"
  grep -qi 'zero is a valid answer' "$REPO/agents/research-decomposition-critic.md"
  grep -qi 'zero missing is valid' "$REPO/agents/research-decomposition-critic.md"   # the return format too
  grep -qi 'none is a valid' "$REPO/agents/frontier-derivation.md"
  [ "$(grep -ci 'none is a valid answer' "$REPO/skills/research-subagents/SKILL.md")" -ge 3 ]
}

@test "inside an active program the negative-space trigger is scoped to the frame critique" {
  local f="$REPO/skills/research-subagents/SKILL.md"
  grep -q 'research-program.sh is-active' "$f"
  grep -qi 'frame critique' "$f"
}
