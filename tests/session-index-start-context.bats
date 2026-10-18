#!/usr/bin/env bats
# session-index-start.sh — the SessionStart context line. Pinned: a line whose recent entries are all
# "(no summary)", or that has no recent entries at all, is not injected; a line with at least one real
# summary or tag is injected verbatim (docs/research/token-efficiency-2026-09-23/measure/hooks.md §4
# row 3, §5 row 11).
#
# Hermetic: $HOME is a scratch dir; bin/session-search.py is a stub that prints $STUB_CTX; the payload
# carries no session_id, so the backgrounded stub-row writer exits before touching the index.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-index-start.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin"
  : > "$HOME/.claude/session-index.db"
  cat > "$HOME/.claude/bin/session-search.py" <<'PY'
import os, sys
open(os.path.join(os.environ["HOME"], "py-called"), "a").write("1\n")
if os.environ.get("STUB_SLEEP"):
    import time; time.sleep(float(os.environ["STUB_SLEEP"]))
sys.stdout.write(os.environ.get("STUB_CTX", ""))
PY
  # The context query is off by default (unit 1.4); these cases pin the filter, so they opt in.
  export CC_SIS_CONTEXT_INJECT=1
}

run_hook() { run bash -c 'printf "{\"cwd\":\"/tmp/proj\"}" | bash "$0"' "$HOOK"; }

@test "all-'(no summary)' recent entries ⇒ no output" {
  export STUB_CTX='Session index: 6905 sessions. Recent: [today] (no summary) | [today] (no summary) | [1d] (no summary)
Search: claude-search "query"'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no recent entries (index count only) ⇒ no output" {
  export STUB_CTX='Session index: 12 sessions. Search: claude-search "query"'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "one real summary among empties ⇒ the whole line is injected verbatim" {
  export STUB_CTX='Session index: 6905 sessions. Recent: [today] (no summary) | [1d] fix the sweep lock | [2d] (no summary)
Search: claude-search "query"'
  run_hook
  [ "$status" -eq 0 ]
  local c; c="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ "$c" = "$STUB_CTX" ]
}

@test "a tag alone counts as content" {
  export STUB_CTX='Session index: 5 sessions. Recent: [today] (no summary) (#infra)
Search: claude-search "query"'
  run_hook
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF '(#infra)'
}

# ── unit 1.4 (startup-hooks-2026-10-18): the query is gated, and a kill logs as a kill ──────────
@test "1.4: default (flag unset) runs no python3 and injects nothing, even with a rich line" {
  unset CC_SIS_CONTEXT_INJECT
  export STUB_CTX='Session index: 5 sessions. Recent: [1d] real summary'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$HOME/py-called" ]
}

@test "1.4: a TERM during the hook logs failed exit:143, not passed exit:0" {
  export STUB_SLEEP=3 STUB_CTX='' CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  printf '{"cwd":"/tmp/proj","session_id":""}' > "$BATS_TEST_TMPDIR/in.json"
  bash "$HOOK" < "$BATS_TEST_TMPDIR/in.json" >/dev/null 2>&1 &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$HOME/py-called" ] && break; sleep 0.3; done
  kill -TERM "$pid"
  wait "$pid" || true
  grep -q '"disposition":"failed"' "$CC_IDL"
  grep -q 'exit:143' "$CC_IDL"
  ! grep -q '"disposition":"passed"' "$CC_IDL" || false
}
