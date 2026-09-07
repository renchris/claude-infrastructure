#!/usr/bin/env bats
# config-change — the out-of-band config tripwire written by hooks/config-change.sh
# (HOOK_SURFACE_100P § 3 row 24, W3-D).
#
# Harness laws followed here:
#   L1  the golden fixtures are the LITERAL captured `ConfigChange` payloads from
#       /tmp/hs/log/session.tsv and session114.tsv (§ 3a row 24), transcribed field-for-field and
#       INLINED. `prompt_id` is present in one and absent in the other, and both shapes are
#       fixtured, because the suite must not pin a field the harness does not always send.
#   L2  every assertion keys on a failure-DISTINCT value. `json_ok` is asserted at FOUR outcomes
#       from the same handler over four real files, so a tripwire that always says the same thing —
#       the shape a presence-only check degenerates into (memory: gate-on-presence-is-cleared-by-
#       any-string) — cannot pass.
#   L3  assertions are `[ ]` / `grep` / `jq -e` — never `[[ ]]`, `(( ))` or a non-last `&&` element.
#   L4  both arms of every fail-open door are fixtured.
#
# 🚨 THE ADOPTION CONSTRAINT IS DECISION-CLASS. `ConfigChange` gates config/skill HOT-RELOAD: a
# handler that emits anything on stdout silently freezes reload for the rest of the session. There
# is a per-path stdout assertion below for the same reason as in the PermissionDenied suite — the
# subject holds the property by having no writer, so only these arms can catch a regression.
#
# THE MID-WRITE ARM IS DETERMINISTIC, NOT TIMED. The hook fires ON the write, so a read can land on
# a half-written file and see invalid JSON that is valid milliseconds later — the failure class
# memory `peer-worktree-read-midwrite-parses-as-a-code-defect` records, and the reason the subject
# re-checks once. Racing a real writer would make this suite flaky and prove nothing; instead a jq
# STUB on PATH fails the first file-parse and delegates every other call to the real jq, so the
# window is reproduced exactly and the recovery is asserted rather than hoped for.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/config-change.sh"
  REAL_JQ="$(command -v jq)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CONFIG_CHANGE_LOG="$HOME/.claude/logs/config-change.jsonl"
  export CONFIG_CHANGE_MAX_BYTES=1048576
  export CONFIG_CHANGE_RECHECK_SEC=0
  export CONFIG_CHANGE_MAX_PARSE_BYTES=2097152
  LOG="$CONFIG_CHANGE_LOG"
  OUT="$BATS_TEST_TMPDIR/stdout.txt"
  ERR="$BATS_TEST_TMPDIR/stderr.txt"
  PAY="$BATS_TEST_TMPDIR/payload.json"
  CFG="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CFG/.claude/commands"
}

# the LITERAL 2.1.220 capture (settings.local.json, source=local_settings, WITH prompt_id)
payload_for() { # <file_path> [source]
  jq -cn --arg fp "$1" --arg src "${2:-local_settings}" \
    '{session_id:"11111111-2222-4333-8444-555555555555",
      transcript_path:"/Users/x/.claude/projects/-Users-x-Development-wt-ptuf2/11111111.jsonl",
      cwd:"/Users/x/Development/wt-ptuf2",
      prompt_id:"77c407cd-ec1e-42cc-929e-5ffbf1d3a203",
      hook_event_name:"ConfigChange", source:$src, file_path:$fp}'
}

# the LITERAL 2.1.114 capture — same event, NO prompt_id
payload_114() { # <file_path>
  jq -cn --arg fp "$1" \
    '{session_id:"33333333-4444-4555-8666-777777777777",
      transcript_path:"/Users/x/.claude/projects/-Users-x-Development-wt-ptuf2/33333333.jsonl",
      cwd:"/Users/x/Development/wt-ptuf2",
      hook_event_name:"ConfigChange", source:"local_settings", file_path:$fp}'
}

cc_rows() { if [ -f "$LOG" ]; then grep -c '"hook":"config-change","sid"' "$LOG" || true; else echo 0; fi; }

feed() {      printf '%s' "$1" > "$PAY"; run_pay; }
feed_from() { "$@"            > "$PAY"; run_pay; }
run_pay() {
  : > "$OUT"; : > "$ERR"
  run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
}

# ── the golden payloads ─────────────────────────────────────────────────────────────────────────
@test "a real 220 ConfigChange payload writes exactly ONE row and nothing on stdout" {
  printf '{"hooks":{}}' > "$CFG/.claude/settings.local.json"
  feed_from payload_for "$CFG/.claude/settings.local.json"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(cc_rows)" -eq 1 ]
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "the 114 capture, which carries no prompt_id, is handled identically" {
  printf '{"hooks":{}}' > "$CFG/.claude/settings.local.json"
  feed_from payload_114 "$CFG/.claude/settings.local.json"
  [ "$status" -eq 0 ]
  run jq -e '.sid == "33333333-4444-4555-8666-777777777777" and .kind == "settings" and .json_ok == "yes"' "$LOG"
  [ "$status" -eq 0 ]
}

# ── THE TRIPWIRE ITSELF: four files, four verdicts, one handler ─────────────────────────────────
# A settings file that no longer parses disables every hook registered in it — all 90 in the live
# file — with zero log output. That is the fact this hook exists to make observable, so `json_ok`
# must be a MEASUREMENT of the named file and not a field that is always filled in.
@test "a VALID settings file records json_ok=yes and is not re-checked" {
  printf '{"hooks":{"Stop":[]}}' > "$CFG/.claude/settings.json"
  feed_from payload_for "$CFG/.claude/settings.json"
  run jq -e '.json_ok == "yes" and .rechecked == false and .kind == "settings"' "$LOG"
  [ "$status" -eq 0 ]
}

@test "an INVALID settings file records json_ok=no — the hazard this hook exists for" {
  printf '{"hooks":{"Stop":[},}' > "$CFG/.claude/settings.json"
  feed_from payload_for "$CFG/.claude/settings.json"
  run jq -e '.json_ok == "no" and .rechecked == true' "$LOG"
  [ "$status" -eq 0 ]
}

@test "a DELETED settings file records json_ok=absent, never a silent yes" {
  feed_from payload_for "$CFG/.claude/settings.json"
  run jq -e '.json_ok == "absent" and .kind == "settings"' "$LOG"
  [ "$status" -eq 0 ]
}

# A skill/command markdown is a real ConfigChange — the capture's second row is
# `source:"skills"`, `file_path:".../commands/hsprobe.md"` — and it is NOT JSON. Asserting anything
# about its syntax would be a fabricated fact, so the honest verdict is `unchecked`.
@test "a non-settings file is recorded but NOT parsed — json_ok=unchecked" {
  printf '# a command\n' > "$CFG/.claude/commands/hsprobe.md"
  feed_from payload_for "$CFG/.claude/commands/hsprobe.md" skills
  run jq -e '.kind == "other" and .json_ok == "unchecked" and .source == "skills"' "$LOG"
  [ "$status" -eq 0 ]
}

# ⚠️ the classification is keyed on the PATH, not on `source`, because this event's `source` enum
# has never been read out of the binary. Two files with the SAME source must classify differently.
@test "classification keys on the file path, not on source — same source, two kinds" {
  printf '{}' > "$CFG/.claude/settings.local.json"
  feed_from payload_for "$CFG/.claude/settings.local.json" local_settings
  [ "$(jq -r '.kind' "$LOG")" = "settings" ]
  : > "$LOG"
  printf '# x\n' > "$CFG/.claude/commands/hsprobe.md"
  feed_from payload_for "$CFG/.claude/commands/hsprobe.md" local_settings
  [ "$(jq -r '.kind' "$LOG")" = "other" ]
}

# ── the mid-write window, reproduced deterministically ──────────────────────────────────────────
@test "a file that parses on the RE-CHECK is recorded yes, with rechecked=true" {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  COUNTER="$BATS_TEST_TMPDIR/jq.count"; : > "$COUNTER"
  cat > "$STUB/jq" <<STUBEOF
#!/bin/bash
# fail ONLY the first \`jq -e . <file>\` — the half-written read — and delegate everything else
if [ "\$1" = "-e" ] && [ "\$2" = "." ] && [ -n "\${3:-}" ] && [ -f "\$3" ]; then
  n=\$(cat "$COUNTER" 2>/dev/null || echo 0); n=\$((n+1)); printf '%s' "\$n" > "$COUNTER"
  if [ "\$n" -eq 1 ]; then exit 1; fi
fi
exec "$REAL_JQ" "\$@"
STUBEOF
  chmod +x "$STUB/jq"
  printf '{"hooks":{"Stop":[]}}' > "$CFG/.claude/settings.json"
  payload_for "$CFG/.claude/settings.json" > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'PATH="$5:$PATH" bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR" "$STUB"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  run jq -e '.json_ok == "yes" and .rechecked == true' "$LOG"
  [ "$status" -eq 0 ]
}

# ── the bound: never read an unbounded file from a hook ─────────────────────────────────────────
@test "a settings file past the parse cap is bounded, not parsed" {
  printf '{"hooks":{}}' > "$CFG/.claude/settings.json"
  export CONFIG_CHANGE_MAX_PARSE_BYTES=4
  feed_from payload_for "$CFG/.claude/settings.json"
  [ "$(jq -r '.json_ok' "$LOG")" = "too-large" ]
}

# ── the field-extraction defect this handler was written to avoid ───────────────────────────────
# `@tsv` + `read` collapses runs of tab (a tab IS IFS whitespace), so an absent leading field shifts
# every later field LEFT — the defect measured on hooks/file-changed.sh. With `file_path` absent,
# a shifted reader would put the SOURCE where the path belongs.
@test "a payload with no file_path does not shift the other fields" {
  feed '{"hook_event_name":"ConfigChange","session_id":"sid-x","source":"local_settings"}'
  [ "$status" -eq 0 ]
  run jq -e '.source == "local_settings" and .file_path == "" and .kind == "unknown"
             and .sid == "sid-x" and .json_ok == "unchecked"' "$LOG"
  [ "$status" -eq 0 ]
}

@test "a file path carrying a space and a quote survives into the row intact" {
  D="$CFG/.claude/o'd d"; mkdir -p "$D"
  printf '{}' > "$D/settings.json"
  feed_from payload_for "$D/settings.json"
  [ "$(jq -r '.file_path' "$LOG")" = "$D/settings.json" ]
  [ "$(jq -r '.json_ok' "$LOG")" = "yes" ]
}

# ── the event gate: a mis-registration must be INERT ─────────────────────────────────────────────
# Without it this handler on any other event would re-read and re-parse a settings file per
# dispatch — a per-tool-call file read from a hook, plus a ledger of events that never happened.
@test "a non-ConfigChange payload is refused — the event name gates the ledger" {
  printf '{}' > "$CFG/.claude/settings.json"
  feed "{\"hook_event_name\":\"FileChanged\",\"session_id\":\"s\",\"file_path\":\"$CFG/.claude/settings.json\"}"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(cc_rows)" -eq 0 ]
}

# ── fail-open doors ─────────────────────────────────────────────────────────────────────────────
@test "empty stdin exits 0 and writes nothing at all" {
  feed ''
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

@test "malformed JSON exits 0, writes NO row, and leaves an abstain marker" {
  feed 'not json {{{'
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(cc_rows)" -eq 0 ]
  grep -q '"abstain":"malformed-json"' "$LOG"
}

@test "no jq on PATH exits 0 and abstains rather than writing a bogus row" {
  payload_for "$CFG/.claude/settings.json" > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'PATH=/bin bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(cc_rows)" -eq 0 ]
  grep -q '"abstain":"no-jq"' "$LOG"
}

@test "the kill switch makes it wholly inert — no row, no marker, no output" {
  payload_for "$CFG/.claude/settings.json" > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'CC_CONFIG_CHANGE_DISABLED=1 bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

@test "stdout is EMPTY on every payload class — a byte here freezes config hot-reload" {
  printf '{}' > "$CFG/.claude/settings.json"
  for p in \
    "{\"hook_event_name\":\"ConfigChange\",\"session_id\":\"s\",\"source\":\"local_settings\",\"file_path\":\"$CFG/.claude/settings.json\"}" \
    '{"hook_event_name":"ConfigChange","session_id":"s","source":"skills","file_path":"/nope/x.md"}' \
    '{"hook_event_name":"SessionStart","session_id":"s"}' \
    '{"hook_event_name":"ConfigChange"}' \
    'not json {{{' \
    '' ; do
    printf '%s' "$p" > "$PAY"
    : > "$OUT"; : > "$ERR"
    run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
    [ "$status" -eq 0 ]
    [ ! -s "$OUT" ]
  done
}

# ── the ledger is BOUNDED ───────────────────────────────────────────────────────────────────────
@test "the ledger rotates at its cap instead of growing without limit" {
  export CONFIG_CHANGE_MAX_BYTES=200
  printf '{}' > "$CFG/.claude/settings.json"
  payload_for "$CFG/.claude/settings.json" > "$PAY"; bash "$HOOK" < "$PAY"
  [ ! -f "$LOG.1" ]
  bash "$HOOK" < "$PAY"
  [ -f "$LOG.1" ]
  [ "$(cc_rows)" -eq 1 ]
}

@test "the handler is executable and is a bash script" {
  [ -x "$HOOK" ]
  head -1 "$HOOK" | grep -q '^#!/bin/bash'
}

@test "this wave registers NOTHING — the handler name appears in no settings file in the repo" {
  run grep -rl 'config-change\.sh' "$REPO/settings-templates" "$REPO/.claude"
  [ "$status" -ne 0 ]
}
