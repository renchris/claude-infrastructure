#!/usr/bin/env bats
# cc-history-union — the account-agnostic prompt-history union (backlog 4b0095d1ee73).
#
# THE DEFECT. `history.jsonl` is per-account (isolated in lib/config-mirror.zsh), and the only
# thing that reads it — the session index's gap-fill, via CLAUDE_HISTORY — read account 1's copy
# alone. Measured 2026-09-09: 14,966 prompts and 1,614 otherwise-unindexed sessions sat in
# .claude-secondary / -tertiary / -quaternary, reachable by no path.
#
# Harness laws: L1 fixtures are real JSONL in the real record shape, read by the shipped script;
# L2 every assertion is failure-DISTINCT — each case dies under ONE named mutation of the subject
# and the mutation is stated in the case's comment, because a new tool has no pre-fix arm to be red
# against and a case that cannot name its mutant is decorative; L3 `[ ]` / `grep -q` only;
# L4 the two directions of the helpers' fallback are both asserted, so neither "always union" nor
# "never union" can pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  UNION="$REPO/bin/cc-history-union"
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary"

  # Account 1: two prompts. Account 2 (secondary): one prompt only it holds, and it is the OLDEST,
  # so a union that merely appends non-canonical sources after canonical ones is caught by the
  # ordering case rather than passing by luck.
  cat > "$HOME/.claude/history.jsonl" <<'JSONL'
{"display":"canonical second","pastedContents":{},"project":"/p/one","sessionId":"s-a1-2","timestamp":3000}
{"display":"canonical first","pastedContents":{},"project":"/p/one","sessionId":"s-a1-1","timestamp":2000}
JSONL
  cat > "$HOME/.claude-secondary/history.jsonl" <<'JSONL'
{"display":"ONLY-IN-SECONDARY","pastedContents":{},"project":"/p/two","sessionId":"s-a2-1","timestamp":1000}
JSONL
  cat > "$HOME/.claude-tertiary/history.jsonl" <<'JSONL'
{"display":"ONLY-IN-TERTIARY","pastedContents":{},"project":"/p/three","sessionId":"s-a3-1","timestamp":4000}
JSONL
  OUT="$HOME/.claude/history-union.jsonl"
}

# ── The defect itself ─────────────────────────────────────
# Mutant: read only $HOME/.claude/history.jsonl (the pre-fix CLAUDE_HISTORY default). Dies here.
@test "union carries records that exist ONLY on a non-canonical account" {
  run "$UNION"
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' <<< "$output"
  grep -q 'ONLY-IN-SECONDARY' "$OUT"
  grep -q 'ONLY-IN-TERTIARY' "$OUT"
  grep -q 'canonical first' "$OUT"
}

# Mutant: drop the sort (emit in read order). Dies here — canonical is read first but holds
# timestamp 3000/2000 while secondary holds 1000, so read order is NOT timestamp order.
@test "records are timestamp-sorted across accounts, not merely concatenated" {
  run "$UNION"
  [ "$status" -eq 0 ]
  run python3 -c "
import json,sys
ts=[json.loads(l)['timestamp'] for l in open(sys.argv[1]) if l.strip()]
print('ORDER-OK' if ts==sorted(ts) else 'ORDER-BAD')
print(ts[0])
" "$OUT"
  grep -q 'ORDER-OK' <<< "$output"
  grep -q '^1000$' <<< "$output"
}

# Mutant: dedupe on path instead of realpath (or omit dedupe). Dies here — .claude-next is a
# SYMLINK to account 1's file on the real box, so a path-keyed dedupe reads it twice and doubles
# every account-1 record.
@test "a source shared by symlink is read exactly once" {
  ln -s "$HOME/.claude/history.jsonl" "$HOME/.claude-secondary/history.jsonl.link"
  mkdir -p "$HOME/.claude-next"
  ln -s "$HOME/.claude/history.jsonl" "$HOME/.claude-next/history.jsonl"
  run "$UNION"
  [ "$status" -eq 0 ]
  grep -q 'sources=3' <<< "$output"
  run grep -c 'canonical first' "$OUT"
  [ "$output" -eq 1 ]
}

# Mutant: `except: continue` on a parse failure. Dies here — the count must reach the verdict.
@test "an unparseable record is COUNTED in the verdict, never silently dropped" {
  printf 'this is not json\n' >> "$HOME/.claude-tertiary/history.jsonl"
  run "$UNION"
  [ "$status" -eq 0 ]
  grep -q 'unparseable=1' <<< "$output"
  # and the good records around it still land
  grep -q 'ONLY-IN-TERTIARY' "$OUT"
}

# Mutant: emit without sort_keys / with a timestamp-only sort key. Dies here — a rebuild over
# unchanged inputs must be byte-identical, which is what makes the hourly refresh idempotent.
@test "rebuilding over unchanged sources is byte-identical" {
  run "$UNION"; [ "$status" -eq 0 ]
  cp "$OUT" "$BATS_TEST_TMPDIR/first"
  run "$UNION"; [ "$status" -eq 0 ]
  run cmp -s "$BATS_TEST_TMPDIR/first" "$OUT"
  [ "$status" -eq 0 ]
}

# Mutant: write the union wherever it is told. Dies here — pointing the output at a SOURCE must be
# refused, because the sources are append-only logs owned by Claude Code and this tool is a reader.
@test "refuses to write the union over one of its own sources" {
  CC_HISTORY_UNION_OUT="$HOME/.claude-tertiary/history.jsonl" run "$UNION"
  [ "$status" -ne 0 ]
  grep -q 'out-is-a-source' <<< "$output"
  # the source is untouched
  grep -q 'ONLY-IN-TERTIARY' "$HOME/.claude-tertiary/history.jsonl"
  run wc -l < "$HOME/.claude-tertiary/history.jsonl"
  [ "${output// /}" -eq 1 ]
}

# Mutant: exit 0 with an empty union when discovery finds nothing. Dies here — an empty union
# silently replacing a good one is the failure mode a fail-open write would create.
@test "no readable source is a non-zero verdict, not an empty union" {
  rm -f "$HOME/.claude/history.jsonl" "$HOME/.claude-secondary/history.jsonl" \
        "$HOME/.claude-tertiary/history.jsonl"
  run "$UNION"
  [ "$status" -ne 0 ]
  grep -q 'verdict=no-sources' <<< "$output"
  [ ! -f "$OUT" ]
}

# ── The consumer seam (both directions — L4) ──────────────
# Mutant: point CLAUDE_HISTORY unconditionally at the union. Dies here — with no union built the
# default must still be account 1's own file, so the change can never be WORSE than the pre-fix
# behaviour on a box where the union has not run yet.
@test "CLAUDE_HISTORY falls back to account 1's file when no union exists" {
  [ ! -f "$OUT" ]
  run bash -c "unset CLAUDE_HISTORY; . '$HELPERS' >/dev/null 2>&1; echo \"\$CLAUDE_HISTORY\""
  [ "$status" -eq 0 ]
  grep -q "^$HOME/.claude/history.jsonl$" <<< "$output"
}

# Mutant: never consult the union. Dies here.
@test "CLAUDE_HISTORY prefers the union once it has been built" {
  run "$UNION"; [ "$status" -eq 0 ]
  run bash -c "unset CLAUDE_HISTORY; . '$HELPERS' >/dev/null 2>&1; echo \"\$CLAUDE_HISTORY\""
  [ "$status" -eq 0 ]
  grep -q "^$OUT$" <<< "$output"
}

# Mutant: let the union win over an explicit caller override. Dies here — the env seam is what a
# rehearsal run uses to point at a fixture, so it must outrank the default either way.
@test "an explicit CLAUDE_HISTORY still wins over the union" {
  run "$UNION"; [ "$status" -eq 0 ]
  # `export` and not a `VAR=x . file` prefix: an assignment prefixed to the `.` builtin does not
  # reach the sourced file on bash 3.2 (measured — the variable reads empty inside), so that form
  # would test the harness rather than the subject. Every real caller exports it or passes it as a
  # prefix to an external command, both of which do deliver it.
  run bash -c "export CLAUDE_HISTORY=/tmp/pinned.jsonl; . '$HELPERS' >/dev/null 2>&1; echo \"\$CLAUDE_HISTORY\""
  [ "$status" -eq 0 ]
  grep -q '^/tmp/pinned.jsonl$' <<< "$output"
}

# Mutant: treat an empty union file as usable. Dies here — a zero-byte union (an interrupted or
# failed build) must not shadow a perfectly good account-1 history.
@test "an empty union file does not shadow account 1's history" {
  : > "$OUT"
  run bash -c "unset CLAUDE_HISTORY; . '$HELPERS' >/dev/null 2>&1; echo \"\$CLAUDE_HISTORY\""
  [ "$status" -eq 0 ]
  grep -q "^$HOME/.claude/history.jsonl$" <<< "$output"
}
