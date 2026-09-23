#!/usr/bin/env bats
# agents-omit-claudemd — lever 3 of docs/research/opus55-feature-adoption-2026-09-22/README.md.
#
# The four research-shaped subagents run with `omitClaudeMd: true` (CC 2.1.271+): measured on
# 2.1.280, the flag removes exactly 85,704 first-turn tokens from every spawn in this repo (the
# user CLAUDE.md, the project rules and the memory index), and across 302 real deep-research
# spawns that block was ~30% of a spawn's cache_creation + output, i.e. of its quota draw.
#
# What this suite pins, and why each case is here:
#   1. the flag is present, in the FRONTMATTER (the loader reads nothing else), on all four;
#   2. every agent that runs without CLAUDE.md and can WRITE (Write, Edit or Bash) carries the
#      operating contract CLAUDE.md used to supply — delivery, never-overwrite, never-mutate-git,
#      stop-on-issue. Dropping the instructions without moving these in is the unsafe half-change;
#   3. descriptions load into EVERY session's agent listing, so the change may not grow them.
#
# Hermetic: reads only files in this checkout.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AGENTS="$REPO_ROOT/agents"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# Print the frontmatter block (between the first two `---` lines) of $1.
frontmatter() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$1"
}

@test "1: the four research subagents declare omitClaudeMd: true in their frontmatter" {
  for a in deep-research deep-research-sonnet frontier-derivation research-decomposition-critic; do
    f="$AGENTS/$a.md"
    [ -f "$f" ] || { echo "missing $f"; false; }
    frontmatter "$f" | grep -qx 'omitClaudeMd: true' \
      || { echo "$a: no 'omitClaudeMd: true' in frontmatter"; false; }
  done
}

@test "2: every omitClaudeMd agent that can write carries the operating contract" {
  n=0
  for f in "$AGENTS"/*.md; do
    fm="$(frontmatter "$f")"
    grep -qx 'omitClaudeMd: true' <<<"$fm" || continue
    tools="$(sed -n 's/^tools: *//p' <<<"$fm")"
    # An agent with no tools line inherits all tools, which includes the writers.
    if [ -n "$tools" ] && ! grep -qE '(^|, *)(Write|Edit|Bash)(,|$)' <<<"$tools"; then
      continue
    fi
    n=$((n + 1))
    body="$(cat "$f")"
    if grep -qE '(^|, *)(Write|Edit)(,|$)' <<<"$tools" || [ -z "$tools" ]; then
      for marker in 'Deliver to a file' 'Never overwrite' 'Never mutate git' 'Stop on issue'; do
        grep -qF "$marker" <<<"$body" || { echo "$(basename "$f"): writer without contract clause '$marker'"; false; }
      done
    else
      # Bash-only agents: either the full contract, or an explicit read-only constraint.
      if ! grep -qF 'Never mutate git' <<<"$body" && ! grep -qF 'READ-ONLY' <<<"$body"; then
        echo "$(basename "$f"): Bash-capable, runs without CLAUDE.md, states neither the contract nor READ-ONLY"; false
      fi
    fi
  done
  [ "$n" -ge 3 ] || { echo "expected >=3 write-capable omitClaudeMd agents, found $n"; false; }
}

@test "3: the adoption did not grow the agent descriptions every session loads" {
  # Ceilings = the byte lengths on 2026-09-22, before and after this change (it touched none).
  # Growing one is allowed only by raising its ceiling here, in the open.
  check() {
    local len
    len="$(sed -n 's/^description: //p' "$AGENTS/$1.md" | wc -c | tr -d ' ')"
    [ "$len" -le "$2" ] || { echo "$1: description is $len bytes > ceiling $2"; return 1; }
  }
  check deep-research 1367
  check deep-research-sonnet 885
  check frontier-derivation 532
  check research-decomposition-critic 342
}
