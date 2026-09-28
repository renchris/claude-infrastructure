#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # file-wide: each @test is its own subshell by design; nothing crosses tests
# memory-nudge.sh — the ruling-shaped prompt SHADOW classifier (truememory #26).
#
# Every typed prompt is scored and logged under its own IDL name `memory-nudge:ruling` (X2); a
# match also appends one labeller-ready row to $HOME/.claude/state/ruling-shadow.jsonl (X4). It is a
# SHADOW: the hook's stdout must be byte-identical with and without a match, which the first case
# proves against both a neutral prompt and the pre-change hook replayed from a PINNED sha.
# Wave E judges it on that log (docs/plans/TRUEMEMORY_ADOPTION.md:222).
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

# The last trunk commit before the shadow existed. Pinned, never a moving ref: a control replayed
# from origin/main compares the change to itself the moment it lands.
PRE_SHA=abaf1e990

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/memory-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  unset CC_RULING_SHADOW MEMORY_NUDGE_INTERVAL CLAUDE_PROJECT_DIR
  SHADOW="$HOME/.claude/state/ruling-shadow.jsonl"
  IDX="$BATS_TEST_TMPDIR/mem/MEMORY.md"; mkdir -p "$(dirname "$IDX")"
  printf -- '- [A](a.md) — one\n- [B](b.md) — two\n' > "$IDX"
  CWDX="$BATS_TEST_TMPDIR/cwd"; mkdir -p "$CWDX"
}

payload() { jq -cn --arg s "$1" --arg c "$CWDX" --arg p "$2" \
  '{session_id:$s,cwd:$c,prompt:$p,hook_event_name:"UserPromptSubmit"}'; }
# run_hook <hook-path> <sid> <prompt> — stdout into $OUT.
run_hook() { OUT="$(payload "$2" "$3" | MEMORY_INDEX_PATH="$IDX" bash "$1")"; }
# The last memory-nudge:ruling IDL row, as one field.
ruling() { jq -rs --arg f "$1" '[.[] | select(.hook == "memory-nudge:ruling")] | last | .[$f] // ""' "$CC_IDL"; }
shadow_n() { if [ -f "$SHADOW" ]; then wc -l < "$SHADOW" | tr -d ' '; else echo 0; fi; }
ruling_n() { jq -s '[.[] | select(.hook == "memory-nudge:ruling")] | length' "$CC_IDL"; }

@test "a ruling fires in shadow: one row, and stdout is byte-identical to a neutral prompt and to the pre-change hook" {
  local p="we just go through 'at least 4mb' images on google images" neutral pre
  neutral="$(printf '%*s' "${#p}" '' | tr ' ' 'n')"
  [ "${#neutral}" -eq "${#p}" ]
  export MEMORY_NUDGE_INTERVAL=1   # a FIRE turn, so the compared stdout is the full nudge, not empty
  MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st-a" run_hook "$HOOK" s-a "$p"; local a="$OUT"
  [ "$(ruling disposition)" = "fired" ]
  [ "$(ruling reason)" = "ruling" ]
  [ "$(ruling pattern)" = "we-adverb" ]
  [ "$(shadow_n)" = "1" ]
  [ "$(jq -r '.class' "$SHADOW")" = "ruling" ]
  MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st-b" run_hook "$HOOK" s-a "$neutral"; local b="$OUT"
  [ "$(ruling reason)" = "no-match" ]
  [ -n "$a" ]
  [ "$a" = "$b" ]
  # The pre-change hook, replayed from the pinned sha beside the current libs.
  pre="$BATS_TEST_TMPDIR/pre/hooks"; mkdir -p "$pre"
  git -C "$REPO" show "$PRE_SHA:hooks/memory-nudge.sh" > "$pre/memory-nudge.sh"
  ln -s "$REPO/hooks/lib" "$pre/lib"
  MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st-c" run_hook "$pre/memory-nudge.sh" s-a "$p"
  [ "$OUT" = "$a" ]
}

@test "restatement: 'remember: always run the linter'" {
  run_hook "$HOOK" s-r "remember: always run the linter"
  [ "$(ruling disposition)" = "fired" ]
  [ "$(ruling reason)" = "restatement" ]
  [ "$(ruling pattern)" = "remember" ]
  [ "$(jq -r '.class' "$SHADOW")" = "restatement" ]
}

@test "no-match: 'remember when we fixed X?' is a recollection, not a rule" {
  run_hook "$HOOK" s-w "remember when we fixed X?"
  [ "$(ruling disposition)" = "abstained" ]
  [ "$(ruling reason)" = "no-match" ]
  [ "$(shadow_n)" = "0" ]
}

@test "restatement: 'don't forget, i told you twice' (restatement is tried before the imperative)" {
  run_hook "$HOOK" s-t "don't forget, i told you twice"
  [ "$(ruling reason)" = "restatement" ]
  [ "$(ruling pattern)" = "i-told-you" ]
}

@test "no-match: 'I don't think that's right'" {
  # `don't` is a ruling only sentence-initially or after "we"; here "I" precedes it. Nothing strips
  # the apostrophe (TrueMemory's quoted-span regex would have eaten "'t think that'"), so the
  # contraction reaches the matcher intact and still does not match.
  run_hook "$HOOK" s-i "I don't think that's right"
  [ "$(ruling disposition)" = "abstained" ]
  [ "$(ruling reason)" = "no-match" ]
  [ "$(shadow_n)" = "0" ]
}

@test "restatement: 'from now on use pnpm'" {
  run_hook "$HOOK" s-f "from now on use pnpm"
  [ "$(ruling reason)" = "restatement" ]
  [ "$(ruling pattern)" = "from-now-on" ]
}

@test "a sentence-initial imperative after a full stop is a ruling" {
  run_hook "$HOOK" s-s "ok thanks. Never push to main from a worktree"
  [ "$(ruling reason)" = "ruling" ]
  [ "$(ruling pattern)" = "sentence-imperative" ]
}

@test "machine-authored text is not typed: tags, briefs over 4,000 chars, handoff pings" {
  local big
  big="$(printf '%*s' 5000 '' | tr ' ' 'a') we always do this"
  run_hook "$HOOK" s-n "<task-notification>we always ship</task-notification>"
  [ "$(ruling reason)" = "not-typed" ]
  run_hook "$HOOK" s-n "$big"
  [ "$(ruling reason)" = "not-typed" ]
  run_hook "$HOOK" s-n "HANDOFF-PING from 42: we always reply"
  [ "$(ruling reason)" = "not-typed" ]
  [ "$(ruling disposition)" = "abstained" ]
  [ "$(ruling_n)" = "3" ]
  [ "$(shadow_n)" = "0" ]
}

@test "a payload with no prompt field abstains no-prompt (could-not-observe)" {
  OUT="$(printf '{"session_id":"s-np","cwd":"%s"}' "$CWDX" | MEMORY_INDEX_PATH="$IDX" bash "$HOOK")"
  [ "$(ruling reason)" = "no-prompt" ]
  [ "$(shadow_n)" = "0" ]
}

@test "kill switch CC_RULING_SHADOW=off: abstains kill-switch, writes no shadow row, same stdout" {
  export MEMORY_NUDGE_INTERVAL=1
  MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st-on" run_hook "$HOOK" s-k "we always rebase"; local on="$OUT"
  [ "$(shadow_n)" = "1" ]
  CC_RULING_SHADOW=off MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st-off" run_hook "$HOOK" s-k "we always rebase"
  [ "$(ruling disposition)" = "abstained" ]
  [ "$(ruling reason)" = "kill-switch" ]
  [ "$(shadow_n)" = "1" ]
  [ "$OUT" = "$on" ]
}

@test "the shadow row: excerpt <= 300 chars on one line, length and sha1 of the prompt, sid and cwd" {
  local p
  p="$(printf '%*s' 1500 '' | tr ' ' 'x')"$'\n\n'"the rule is: rebase, never merge"$'\n'"$(printf '%*s' 1500 '' | tr ' ' 'y')"
  run_hook "$HOOK" s-e "$p"
  [ "$(shadow_n)" = "1" ]
  local ex
  ex="$(jq -r '.excerpt' "$SHADOW")"
  [ "${#ex}" -le 300 ]
  [ "$(printf '%s' "$ex" | wc -l | tr -d ' ')" = "0" ]
  printf '%s' "$ex" | grep -qF 'the rule is: rebase'
  [ "$(jq -r '.pattern' "$SHADOW")" = "the-rule-is" ]
  [ "$(jq -r '.prompt_len' "$SHADOW")" = "${#p}" ]
  [ "$(jq -r '.prompt_sha1' "$SHADOW")" = "$(printf '%s' "$p" | shasum -a 1 | cut -d' ' -f1)" ]
  [ "$(jq -r '.sid' "$SHADOW")" = "s-e" ]
  [ "$(jq -r '.cwd' "$SHADOW")" = "$CWDX" ]
}

@test "every eligible prompt writes exactly one memory-nudge:ruling IDL row carrying the sid" {
  run_hook "$HOOK" s-idl "plain question about nothing"
  run_hook "$HOOK" s-idl "we never force-push"
  [ "$(ruling_n)" = "2" ]
  [ "$(ruling hook)" = "memory-nudge:ruling" ]
  [ "$(ruling sid)" = "s-idl" ]
}

@test "X1: the hook run through a symlink in a temp dir still resolves its IDL lib" {
  local d="$BATS_TEST_TMPDIR/live/hooks"; mkdir -p "$d"
  ln -s "$HOOK" "$d/memory-nudge.sh"
  run_hook "$d/memory-nudge.sh" s-l "we always rebase"
  [ "$(ruling disposition)" = "fired" ]
  [ "$(shadow_n)" = "1" ]
}

@test "MEMORY_NUDGE_INTERVAL=0 still exits first: no counter, no ruling row, no shadow row" {
  export MEMORY_NUDGE_INTERVAL=0
  run_hook "$HOOK" s-z "we always rebase"
  [ -z "$OUT" ]
  [ ! -f "$CC_IDL" ]
  [ "$(shadow_n)" = "0" ]
}

# alarm_run <idl> <nudge-dir> — the abstain alarm's sweep with the registry's denominators on fixtures.
alarm_run() {
  run env CC_IDL="$1" CC_ABSTAIN_LOG="$BATS_TEST_TMPDIR/abstain.log" CC_ABSTAIN_NMIN=10 CC_ABSTAIN_CENSUS=0 \
      MEMORY_NUDGE_INTERVAL=12 CC_EXPECTED_SESSION_INDEX_LOG="$BATS_TEST_TMPDIR/none.log" \
      CC_EXPECTED_NUDGE_STATE_DIRS="$2" "$REPO/scripts/idl-abstain-alarm.sh" --run
}

@test "registry: memory-nudge:ruling is judged against the RAW prompt counters, not count/interval" {
  local nd="$BATS_TEST_TMPDIR/nudge" idl="$BATS_TEST_TMPDIR/alarm-idl.jsonl" i
  mkdir -p "$nd"; printf '30' > "$nd/nudge-a.count"
  printf '{"ts":"%s","hook":"other-hook","sid":"x","disposition":"fired","reason":"x"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$idl"
  alarm_run "$idl" "$nd"
  [ "$status" -eq 1 ]                                   # RED: 30 prompts counted, none scored
  printf '%s' "$output" | grep -q 'SILENT  *memory-nudge:ruling .*D=30 '
  # 30 prompts scored by the real hook: every counted prompt wrote one row, so the branch reads OK.
  for ((i = 0; i < 30; i++)); do
    payload s-den "prompt number $i" | CC_IDL="$idl" MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/den" \
      MEMORY_INDEX_PATH="$IDX" bash "$HOOK" > /dev/null
  done
  [ "$(cat "$BATS_TEST_TMPDIR/den/nudge-s-den.count")" = "30" ]
  alarm_run "$idl" "$nd"
  printf '%s' "$output" | grep -q 'OK  *memory-nudge:ruling  *rows=30  *D=30 '
}
