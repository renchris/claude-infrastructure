#!/usr/bin/env bats
# transcript-norm — hooks/lib/transcript_norm.py and its first consumer, the session index
# (docs/research/truememory-2026-09-27.md §3.14).
#
# The session-index context text was 64% machinery: 78 of 122 selected messages were Stop-hook
# feedback, skill bodies or peer messages, because its filter dropped only `<`-leading text. The lib
# fixes that, and a failed import falls back to the OLD filter so the index never dies. That makes
# the fallback a silent revert of the fix, so this suite tests the CONSUMER, not only the lib:
#   §1  both extractors, fed a transcript carrying every machinery shape, keep only the typed prompt;
#   §2  with the lib unimportable, the same call still returns (the old contaminated text, which is
#       what proves the fixture discriminates) AND logs `norm=fallback:` plus a BLIND IDL row;
#   §3  the lib resolves through a symlinked helpers file (X1), and is reported once per process;
#   §4  the lib's own tiers, iter_turns, and cc-suggest-filter's typed_prompt through the lib.
# The fixture is built from real record SHAPES (field names measured on live transcripts
# 2026-09-28: origin.kind, promptSource, isMeta), with no private text.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export SESSION_INDEX_LOG="$HOME/.claude/logs/session-index.log"
  export SESSION_INDEX_DB="$HOME/.claude/session-index.db"
  unset SESSION_INDEX_NORM_DIR
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  FX="$REPO/tests/fixtures/transcript-norm/11111111-2222-4333-8444-555555555555.jsonl"
  TYPED="Refactor the widget parser so it streams records instead of buffering them."
}

# One fresh bash per call, sourcing the helpers the way hooks/session-index-end.sh does, so "once
# per process" is exercised the way production sees it. $1 = helpers path, $2 = function.
extract() { bash -c '. "$1"; "$2" "$3" 5' _ "$1" "$2" "$FX"; }
norm_rows() { jq -c 'select(.hook == "session-index:norm")' "$CC_IDL"; }

# ══ §1 the consumer keeps only the typed prompt ═══════════════════════════════════════════════

@test "extract_context: only the typed prompt survives; norm=lib is logged and IDL-rowed" {
  run extract "$HELPERS" session_index_extract_context
  [ "$status" -eq 0 ]
  [ "$output" = "$TYPED" ]
  grep -q '] norm=lib caller=extract_context$' "$SESSION_INDEX_LOG"
  [ "$(norm_rows | jq -r '[.disposition, .reason, .caller] | join(" ")')" = "fired lib extract_context" ]
}

@test "extract_all: context_text is only the typed prompt; the other four columns are unchanged" {
  run extract "$HELPERS" session_index_extract_all
  [ "$status" -eq 0 ]
  # cut, not `IFS=$'\t' read`: files_changed is empty here, and read collapses a run of tabs.
  [ "$(printf '%s' "$output" | cut -f1)" = "$TYPED" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "I will list the directory first to see which fixtures exist here. Streaming the parser now; the buffer goes away and records flow one at a time." ]
  [ "$(printf '%s' "$output" | cut -f3)" = "" ]
  [ "$(printf '%s' "$output" | cut -f4)" = "ls /tmp/fixture-dir" ]
  [ "$(printf '%s' "$output" | cut -f5)" = "8" ]
  grep -q '] norm=lib caller=extract_all$' "$SESSION_INDEX_LOG"
  [ "$(norm_rows | jq -r '[.disposition, .reason, .caller] | join(" ")')" = "fired lib extract_all" ]
}

# ══ §2 the fallback is loud ═══════════════════════════════════════════════════════════════════

@test "extract_context, lib unimportable: still returns, logs norm=fallback, writes a BLIND row" {
  mkdir -p "$BATS_TEST_TMPDIR/nolib"
  SESSION_INDEX_NORM_DIR="$BATS_TEST_TMPDIR/nolib" run extract "$HELPERS" session_index_extract_context
  [ "$status" -eq 0 ]
  # The old filter, verbatim: machinery leaks back in, which is what makes §1 a real discriminator.
  printf '%s' "$output" | grep -q '^Stop hook feedback: '
  printf '%s' "$output" | grep -q 'Base directory for this skill'
  grep -q '] norm=fallback:ModuleNotFoundError caller=extract_context$' "$SESSION_INDEX_LOG"
  [ "$(norm_rows | jq -r '[.disposition, .reason, .norm] | join(" ")')" = "abstained norm-import-failed fallback:ModuleNotFoundError" ]
}

@test "extract_all, lib unimportable: context_text falls back, logs norm=fallback, writes a BLIND row" {
  mkdir -p "$BATS_TEST_TMPDIR/nolib"
  SESSION_INDEX_NORM_DIR="$BATS_TEST_TMPDIR/nolib" run extract "$HELPERS" session_index_extract_all
  [ "$status" -eq 0 ]
  printf '%s' "$output" | cut -f1 | grep -q '^Stop hook feedback: '
  [ "$(printf '%s' "$output" | cut -f4)" = "ls /tmp/fixture-dir" ]
  grep -q '] norm=fallback:ModuleNotFoundError caller=extract_all$' "$SESSION_INDEX_LOG"
  [ "$(norm_rows | jq -r '[.disposition, .reason] | join(" ")')" = "abstained norm-import-failed" ]
}

@test "the fallback reason is BLIND in the abstain alarm, and the branch has a registry row" {
  grep -q ' norm-import-failed ' <(sed -n '/^_default_blind=(/,/)$/p' "$REPO/scripts/idl-abstain-alarm.sh" | tr '\n' ' ')
  [ "$(awk -F'\t' '$1 == "session-index:norm" { print $2 }' "$REPO/scripts/idl-expected-fires.tsv")" = "denom_sessionend_indexed" ]
}

# ══ §3 X1 self-path, and once per process ═════════════════════════════════════════════════════

@test "X1: helpers sourced through a symlink in a dir without the lib still import it" {
  local d="$BATS_TEST_TMPDIR/live/hooks/lib"
  mkdir -p "$d"
  ln -s "$HELPERS" "$d/session-index-helpers.sh"
  [ ! -e "$d/transcript_norm.py" ]
  run extract "$d/session-index-helpers.sh" session_index_extract_context
  [ "$status" -eq 0 ]
  [ "$output" = "$TYPED" ]
  grep -q '] norm=lib caller=extract_context$' "$SESSION_INDEX_LOG"
}

@test "once per process: three calls in one process write one row; a second process writes one more" {
  bash -c '. "$1"; a=$(session_index_extract_context "$2" 5); b=$(session_index_extract_context "$2" 1); c=$(session_index_extract_all "$2" 5)' _ "$HELPERS" "$FX"
  [ "$(norm_rows | wc -l | tr -d ' ')" = "1" ]
  [ "$(grep -c '] norm=' "$SESSION_INDEX_LOG")" = "1" ]
  extract "$HELPERS" session_index_extract_all >/dev/null
  [ "$(norm_rows | wc -l | tr -d ' ')" = "2" ]
  [ -f "$HOME/.claude/state/session-index-norm.proc" ]
}

# ══ §4 the lib ════════════════════════════════════════════════════════════════════════════════

py() { PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$REPO/hooks/lib" python3 -c "$1"; }

@test "operator_text: origin, then promptSource, then the fallback prefix/envelope/isMeta tier" {
  run py '
import json
from transcript_norm import operator_text as op
U = lambda c, **k: dict(type="user", message=dict(content=c), **k)
cases = [
  (U("typed by hand", origin=dict(kind="human")), "typed by hand"),
  (U("<command-name>/goal</command-name>", origin=dict(kind="human")), None),
  (U("a background task finished", origin=dict(kind="task-notification")), None),
  (U("queued while busy", promptSource="queued"), "queued while busy"),
  (U("injected by the system", promptSource="system"), None),
  (U("<system-reminder>x</system-reminder> real words", ), "real words"),
  (U("<system-reminder>only a reminder</system-reminder>"), None),
  (U("Stop hook feedback: keep going"), None),
  (U("keep going", isMeta=True), None),
  (U("<bash-input>ls</bash-input>"), None),
  (U("Base directory for this skill: /x"), None),
  (U("<teammate-message teammate_id=\"lead\">hi</teammate-message>"), None),
  (U([dict(type="tool_result", content="out")]), None),
  (U([dict(type="text", text="pasted"), dict(type="image")]), "pasted"),
  (dict(type="assistant", message=dict(content="hello")), None),
  (U("no labels at all"), "no labels at all"),
]
bad = [(i, op(r), w) for i, (r, w) in enumerate(cases) if op(r) != w]
print(len(cases), bad)'
  [ "$status" -eq 0 ]
  [ "$output" = "16 []" ]
}

@test "iter_turns: attachments and tool_result turns dropped, assistant text capped, offset resumes" {
  run py '
from transcript_norm import iter_turns
t = list(iter_turns("'"$FX"'"))
print([x.role[0] + ("*" if x.operator else "") for x in t])
long = "x" * 600
import json, os, tempfile
p = tempfile.mktemp()
open(p, "w").write(json.dumps(dict(type="assistant", message=dict(content=[dict(type="text", text=long)]))) + "\n")
print(len(list(iter_turns(p))[0].text)); os.remove(p)
print([x.text for x in iter_turns("'"$FX"'", t[-2].offset)])'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "['u', 'u', 'u', 'u', 'u', 'a', 'u', 'u*', 'a']" ]
  [ "${lines[1]}" = "500" ]
  [ "${lines[2]}" = "['Streaming the parser now; the buffer goes away and records flow one at a time.']" ]
}

@test "cc-suggest-filter imports typed_prompt from the lib through a symlinked self-path" {
  ln -s "$REPO/bin/cc-suggest-filter" "$BATS_TEST_TMPDIR/cc-suggest-filter"
  run "$BATS_TEST_TMPDIR/cc-suggest-filter" self-test
  [ "$status" -eq 0 ]
  [ "$output" = "self-test: 20/20 fixtures agree" ]
  # typed_prompt stays stricter than operator_text: list content is never typing to it.
  run py '
from transcript_norm import typed_prompt, operator_text
r = dict(type="user", message=dict(content=[dict(type="text", text="pasted words")]))
print(typed_prompt(r), operator_text(r))'
  [ "$output" = "None pasted words" ]
}
