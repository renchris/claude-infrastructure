#!/usr/bin/env bats
# TSV field-collapse — docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md · cc-backlog 1a941c28a079
#
# Tab is an IFS-*whitespace* character, so `IFS=$'\t' read` collapses a RUN of delimiters into one.
# Any empty field therefore does NOT produce an empty variable — it shifts every later field one
# position LEFT, silently, with no error and a zero exit status. Every producer feeding such a read
# must guarantee non-empty cells AT THE EMITTER; the read side cannot be repaired.
#
# Three layers here:
#   §1  the MECHANISM — locks the premise (including the two corrections to the finding doc), so a
#       future reader cannot "simplify" a fix away on a wrong belief about how bash 3.2 splits.
#   §2  per-SITE regressions — each drives the real tool/function with a deliberately empty middle
#       field. Every one of these fails on origin/main.
#   §3  the repo-wide GUARD — enumerates every `IFS=$'\t' read` in bin/ hooks/ scripts/ and requires
#       each file to either carry the padding def or be named in the reviewed exemption table. This
#       is what stops the convention being re-derived (or forgotten) at site 25.
#
# Assertion style: `[ ]` never `[[ ]]`, and negations go through run+status — a bare `!` and a
# non-final `[[ ]]` are both silently dead in bats unless they are the last line of a @test
# (cc-backlog 94edb2fa9f14 / 63929c8d6072: 212 dead assertions across the suite).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh). Not box-ticking: the session-index cases
  # source hooks/lib/session-index-helpers.sh, whose SESSION_INDEX_DB / SESSION_INDEX_LOG resolve
  # to $HOME/.claude/… — so an un-fixtured run of this very file can write the LIVE search index.
  # Proven during this sweep: an end-to-end smoke of hooks/session-index-end.sh under the real
  # $HOME reached the live DB path before an early exit happened to spare it. Fixture, don't hope.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C"
  PAD=$'\037'
}

# refute_grep <pattern> — fails if the pattern IS present in $output. A bare `! grep` would be a
# silent no-op anywhere but the final line of a @test (SC2314), hence the explicit returns.
refute_grep() {
  printf '%s' "$output" | grep -q -- "$1" && return 1
  return 0
}

# probe <body> — run a bash snippet from a FILE rather than through `bash -c '…'`. The mechanism
# under test is made of control bytes and $'…' quoting; nesting that inside a quoted -c argument is
# how you end up testing your own escaping instead of bash's word-splitting.
probe() {
  printf '#!/bin/bash\n%s\n' "$1" > "$C/probe.sh"
  run bash "$C/probe.sh"
}

# ─── §1 · the mechanism ────────────────────────────────────────────────────────────────────────

@test "mechanism: an empty middle field shifts every later field LEFT under IFS=tab" {
  probe 'printf "acct\tREQUIRED\t\t2026-08-01\t12\tclaude-next\n" |
         { IFS=$'\''\t'\'' read -r a b c d e f; printf "%s|%s|%s|%s" "$c" "$d" "$e" "$f"; }'
  [ "$status" -eq 0 ]
  # c SHOULD be the empty field and f SHOULD be claude-next. It is neither.
  [ "$output" = "2026-08-01|12|claude-next|" ]
}

@test "mechanism: padding the empty cell restores every column to its own variable" {
  probe 'printf "acct\tREQUIRED\t-\t2026-08-01\t12\tclaude-next\n" |
         { IFS=$'\''\t'\'' read -r a b c d e f; printf "%s|%s|%s|%s" "$c" "$d" "$e" "$f"; }'
  [ "$status" -eq 0 ]
  [ "$output" = "-|2026-08-01|12|claude-next" ]
}

# The finding doc's original repro concluded "a non-whitespace IFS does not work on macOS bash 3.2".
# Its repro used `IFS=$"\001"` — LOCALE-TRANSLATION quoting, not ANSI-C `$'...'` — so IFS was the
# four literal characters \ 0 0 1 and of course never matched the data. The conclusion survives for
# \001 anyway, but for an unrelated reason (bash uses \001 as its internal CTLESC), and it is FALSE
# in general: \037 splits correctly and preserves empties. bin/cc-board depends on exactly that.
# Both facts are locked here because the doc's stated reason and its real reason differ.
@test "mechanism: IFS=\$'\\001' does NOT split — bash's internal CTLESC, not a general rule" {
  # The separators are rendered as "." so the assertion is byte-accurate: \001 is invisible in a
  # terminal, and reading the raw output is how one concludes the field was "xy" when it is in fact
  # the WHOLE undivided line, control bytes and all.
  probe 'printf "x\001\001y\n" > "$0.d"
         IFS=$'\''\001'\'' read -r p q r < "$0.d"
         printf "%s|%s|%s" "${p//$'\''\001'\''/.}" "$q" "$r"'
  [ "$status" -eq 0 ]
  # not "x||y", and not "xy||" either — nothing split at all.
  [ "$output" = "x..y||" ]
}

@test "mechanism: IFS=\$'\\037' DOES split and preserves the empty cell (cc-board relies on this)" {
  probe 'printf "x\037\037y\n" > "$0.d"
         IFS=$'\''\037'\'' read -r p q r < "$0.d"; printf "%s|%s|%s" "$p" "$q" "$r"'
  [ "$status" -eq 0 ]
  [ "$output" = "x||y" ]
}

@test "mechanism: jq's split(\"\\t\") does NOT collapse runs — only \`read\` does" {
  # Load-bearing: hooks/plan-index-update.sh folds its TSV with jq split(), which is why that fold
  # is correct as written and must not be "fixed" to match the read side.
  run jq -rn '"a\t\tc" | split("\t") | length'
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

# ─── §2 · per-site regressions (each fails on origin/main) ─────────────────────────────────────

@test "cc-decide: a class-C packet with no veto_deadline renders what_plain in the WHAT column" {
  export CC_DECISIONS_DIR="$C/decisions" CC_IDL="$C/idl.jsonl"
  mkdir -p "$CC_DECISIONS_DIR"
  cat > "$CC_DECISIONS_DIR/p1.json" <<'JSON'
{"id":"p1","class":"C","status":"open","veto_deadline":"","what_plain":"UNIQUEWHATTEXT"}
JSON
  run bash "$REPO/bin/cc-decide" list --all
  [ "$status" -eq 0 ]
  # Before the fix what_plain slid into the 20-char DEADLINE column and was TRUNCATED, so the full
  # string never appeared anywhere on the line.
  printf '%s' "$output" | grep -q 'UNIQUEWHATTEXT'
  # and it must be in the last (WHAT) field, not the deadline field
  run bash -c "printf '%s' \"\$(CC_DECISIONS_DIR='$CC_DECISIONS_DIR' CC_IDL='$CC_IDL' bash '$REPO/bin/cc-decide' list --all)\" | awk -F'\\\\|' '{print \$5}'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'UNIQUEWHATTEXT'
}

@test "cc-decide: a packet with no status key does not shift class into the status column" {
  export CC_DECISIONS_DIR="$C/decisions" CC_IDL="$C/idl.jsonl"
  mkdir -p "$CC_DECISIONS_DIR"
  cat > "$CC_DECISIONS_DIR/p2.json" <<'JSON'
{"id":"p2","class":"B","veto_deadline":"2026-09-09T00:00:00Z","what_plain":"NOSTATUSPACKET"}
JSON
  run bash "$REPO/bin/cc-decide" list --all
  [ "$status" -eq 0 ]
  # field 2 is CLASS; on origin/main the missing .status shifted "B" into field 1 and the id into 2.
  run bash -c "printf '%s' \"\$(CC_DECISIONS_DIR='$CC_DECISIONS_DIR' CC_IDL='$CC_IDL' bash '$REPO/bin/cc-decide' list --all)\" | awk -F' *\\\\| *' '{print \$2}'"
  [ "$status" -eq 0 ]
  [ "$output" = "B" ]
}

@test "cc-backlog: an item with an empty project keeps its title in the TITLE column" {
  # `.needs` is the LAST cell, so an unblocked item alone does not discriminate — the collapse only
  # bites when an EARLIER cell is empty. `.project` is that cell (fold defaults it to "").
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  printf '%s\n' '{"id":"i1","ts":"2026-07-01T00:00:00Z","event":"add","project":"","title":"TITLETOKEN"}' \
    > "$CC_BACKLOG_FILE"
  run bash "$REPO/bin/cc-backlog" list --open
  [ "$status" -eq 0 ]
  # origin/main renders: "open | i1 | TITLETOKEN | "   (title in the PROJECT column, title blank)
  run bash -c "CC_BACKLOG_FILE='$CC_BACKLOG_FILE' bash '$REPO/bin/cc-backlog' list --open | awk -F' *\\\\| *' '{print \$4}'"
  [ "$status" -eq 0 ]
  [ "$output" = "TITLETOKEN" ]
}

@test "cc-backlog: a blocked item with an empty project still renders its needs marker" {
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  {
    printf '%s\n' '{"id":"i2","ts":"2026-07-01T00:00:00Z","event":"add","project":"","title":"T2"}'
    printf '%s\n' '{"id":"i2","ts":"2026-07-02T00:00:00Z","event":"block","needs":"OPERATORSTEP"}'
  } > "$CC_BACKLOG_FILE"
  run bash "$REPO/bin/cc-backlog" list --blocked
  [ "$status" -eq 0 ]
  # origin/main renders "blocked | i2 | T2 | OPERATORSTEP" — the operator step masquerading as the
  # TITLE, the real title in the project column, and the "⟵ needs:" marker gone entirely.
  printf '%s' "$output" | grep -q '⟵ needs: OPERATORSTEP'
  printf '%s' "$output" | grep -q '| T2  ⟵'
  # and the sentinel must never leak to the operator
  refute_grep "$PAD"
}

@test "cc-board: an accounts row missing weekly_pct does not slide FABLE into the WK column" {
  mkdir -p "$C/bin" "$C/tele"
  cat > "$C/bin/claude-accounts" <<'STUB'
#!/bin/bash
[ "${1:-}" = "--json" ] && printf '%s\n' '{"rows":[{"acct":"next","session_pct":3,"fable_pct":24}]}'
exit 0
STUB
  chmod +x "$C/bin/claude-accounts"
  printf '%s\n' '{"session_id":"S1","ts":'"$(date +%s)"',"used_pct":10,"config_dir":"/x/.claude-next","cwd":"/w","pid":""}' \
    > "$C/tele/S1.json"
  run env PATH="$C/bin:$PATH" CC_TELEMETRY_DIR="$C/tele" bash "$REPO/bin/cc-board"
  [ "$status" -eq 0 ]
  # 5h=3, WK unknown (?), FABLE=24 — NOT 5h=3, WK=24, FABLE blank.
  printf '%s' "$output" | grep -qE '3% +\?% +24%'
}

@test "cc-value: a telemetry row with an empty config_dir stays ACTIVE (freshness not shifted)" {
  mkdir -p "$C/tele"
  printf '%s\n' '{"session_id":"S9","ts":'"$(date +%s)"',"used_pct":5,"config_dir":"","pid":""}' \
    > "$C/tele/S9.json"
  run env CC_TELEMETRY_DIR="$C/tele" CC_VALUE_REPOS="$C" bash "$REPO/bin/cc-value" --json
  [ "$status" -eq 0 ]
  # Before the fix the freshness BOOLEAN landed in $pid and $fresh was blank, so the row was
  # counted inactive. active_sessions is the honest fleet count downstream of that read.
  run jq -r '.fleet.active_sessions' <<< "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "cc-context: a telemetry row with an empty model does not slide cwd into effort" {
  mkdir -p "$C/tele"
  printf '%s\n' '{"session_id":"SCTX0000","ts":'"$(date +%s)"',"used_pct":7,"window":1000000,"model":"","effort":"max","cwd":"/CWDTOKEN"}' \
    > "$C/tele/SCTX0000.json"
  # Assert POSITIONALLY. A bare grep for "max /CWDTOKEN" matches the SHIFTED row too (there the two
  # strings are simply in the model+effort columns instead of effort+cwd) — the assertion has to
  # count columns, not spot substrings. origin/main gives NF=6, f7 empty; fixed gives NF=7.
  run bash -c "CC_TELEMETRY_DIR='$C/tele' bash '$REPO/bin/cc-context' | tail -1 |
               awk '{print NF\"|\"\$5\"|\"\$6\"|\"\$7}'"
  [ "$status" -eq 0 ]
  [ "$output" = "7|?|max|/CWDTOKEN" ]
}

@test "cc-audit: an empty hook key does not invent a hook named after its own count" {
  export CC_IDL="$C/idl.jsonl"
  : > "$CC_IDL"
  i=0
  while [ "$i" -lt 12 ]; do
    printf '%s\n' '{"ts":"2099-01-01T00:00:00Z","hook":"","disposition":"abstained"}' >> "$CC_IDL"
    printf '%s\n' '{"ts":"2099-01-01T00:00:00Z","hook":"realhook","disposition":"fired"}' >> "$CC_IDL"
    i=$((i + 1))
  done
  # The --json branch parses with jq split("\t"), which does NOT collapse — so --json was already
  # correct on origin/main and asserting there proves nothing. The HUMAN path is the read that
  # collapses: on origin/main it renders a phantom hook literally named "12" (its own total),
  # carrying abstained=0 for 12 records that were ALL abstentions — the inert-detector reporting
  # a hook that does not exist, and reporting it healthy.
  run bash "$REPO/bin/cc-audit" abstain
  [ "$status" -eq 0 ]
  refute_grep 'ok  *[0-9][0-9]*  *total='
  printf '%s' "$output" | grep -q 'ok   realhook'
}

@test "cc-audit: the padding sentinel never leaks into the rendered rows or --json" {
  export CC_IDL="$C/idl.jsonl"
  printf '%s\n' '{"ts":"2099-01-01T00:00:00Z","hook":"","disposition":"abstained"}' > "$CC_IDL"
  run bash "$REPO/bin/cc-audit" abstain
  refute_grep "$PAD"
  run bash "$REPO/bin/cc-audit" abstain --json
  [ "$status" -eq 0 ]
  refute_grep "$PAD"
}

@test "session-index lookup: an entry with an empty summary and gitBranch keeps every column" {
  mkdir -p "$C/proj"
  cat > "$C/proj/sessions-index.json" <<'JSON'
{"entries":[{"sessionId":"S1","summary":"","firstPrompt":"FIRSTPROMPT","gitBranch":"",
             "created":"2026-07-01T00:00:00Z","modified":"2026-07-02T00:00:00Z","messageCount":42}]}
JSON
  run bash -c "source '$REPO/hooks/lib/session-index-helpers.sh' 2>/dev/null
    E=\$(session_index_lookup_sessions_index '$C/proj' S1)
    IFS=\$'\t' read -r S FP GB CR MD MC <<< \"\$E\"
    printf '%s|%s|%s|%s|%s|%s' \"\$(session_index_unpad \"\$S\")\" \"\$(session_index_unpad \"\$FP\")\" \\
      \"\$(session_index_unpad \"\$GB\")\" \"\$(session_index_unpad \"\$CR\")\" \\
      \"\$(session_index_unpad \"\$MD\")\" \"\$(session_index_unpad \"\$MC\")\""
  [ "$status" -eq 0 ]
  # origin/main gave: FIRSTPROMPT|2026-07-01…|2026-07-02…|42||  — the message COUNT in created_at.
  [ "$output" = "|FIRSTPROMPT||2026-07-01T00:00:00Z|2026-07-02T00:00:00Z|42" ]
}

@test "session-index enriched: a transcript with tool calls but no assistant text keeps its columns" {
  cat > "$C/t.jsonl" <<'JSON'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/y.py"}},{"type":"tool_use","name":"Bash","input":{"command":"pytest -q"}}]}}
JSON
  run bash -c "source '$REPO/hooks/lib/session-index-helpers.sh' 2>/dev/null
    E=\$(session_index_extract_enriched '$C/t.jsonl')
    IFS=\$'\t' read -r AT FC CR <<< \"\$E\"
    printf '[%s][%s][%s]' \"\$AT\" \"\$FC\" \"\$CR\""
  [ "$status" -eq 0 ]
  # origin/main stored the FILE LIST as assistant_text and the COMMANDS as files_changed.
  [ "$output" = "[ ][/x/y.py][pytest -q]" ]
}

@test "session-index enriched: a missing transcript still emits three held-open columns" {
  run bash -c "source '$REPO/hooks/lib/session-index-helpers.sh' 2>/dev/null
    E=\$(session_index_extract_enriched '$C/does-not-exist.jsonl')
    IFS=\$'\t' read -r AT FC CR <<< \"\$E\"
    printf '[%s][%s][%s]' \"\$AT\" \"\$FC\" \"\$CR\""
  [ "$status" -eq 0 ]
  [ "$output" = "[ ][ ][ ]" ]
}

@test "plan-index reconcile: an entry with an empty path does not resurrect firstIndexed as a path" {
  # firstIndexed is deliberately a REAL file here. With a plain timestamp both branches drop the
  # row ([ -f "$p" ] fails either way) and the test proves nothing; with a real path, origin/main
  # shifts it into $p and INDEXES a plan the entry never named.
  export CC_PLAN_INDEX="$C/plans-index.json" CC_PLANS_DIR="$C/plans" CC_PLAN_SCAN_ROOTS="/nonexistent"
  mkdir -p "$C/plans"
  printf '# p\n' > "$C/plans/real.md"
  cat > "$CC_PLAN_INDEX" <<JSON
{"version":1,"generated":"2026-07-01T00:00:00Z",
 "plans":{"ghost":{"path":"","firstIndexed":"$C/plans/real.md"}}}
JSON
  run bash "$REPO/hooks/plan-index-update.sh" reconcile
  [ "$status" -eq 0 ]
  run jq -r '.plans | keys | length' "$CC_PLAN_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "plan-index reconcile: a surviving entry keeps its firstIndexed after the un-pad" {
  # No-regression guard for the un-pad, NOT a defect regression: this path is correct on
  # origin/main too (firstIndexed is the last cell). It exists so the un-pad cannot silently
  # blank the carry-forward.
  export CC_PLAN_INDEX="$C/plans-index.json" CC_PLANS_DIR="$C/plans" CC_PLAN_SCAN_ROOTS="$C/plans"
  mkdir -p "$C/plans"
  printf '# p\n' > "$C/plans/p.md"
  cat > "$CC_PLAN_INDEX" <<JSON
{"version":1,"generated":"2026-07-01T00:00:00Z",
 "plans":{"$C/plans/p.md":{"path":"$C/plans/p.md","firstIndexed":"2026-01-01T00:00:00Z"}}}
JSON
  run bash "$REPO/hooks/plan-index-update.sh" reconcile
  [ "$status" -eq 0 ]
  run jq -r --arg k "$C/plans/p.md" '.plans[$k].firstIndexed' "$CC_PLAN_INDEX"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-01-01T00:00:00Z" ]
}

@test "boot-resume: a registry entry with no account is still resumed after a reboot" {
  # Drives the REAL script through its own stub seams (same ones tests/boot-resume.bats uses) — an
  # inline copy of the fixed jq would only be testing itself. On origin/main the empty .account
  # shifted cwd→acct, sid→cwd and name→sid, so transcript_mtime was called with every argument
  # wrong, the entry failed its recency filter, and the session was never resumed.
  export CC_REGISTRY_DIR="$C/reg" CC_ROLES_DIR="$C/roles" CC_IDL="$C/idl.jsonl"
  export CC_BOOT_RESUME_STATE_DIR="$C/state" CC_BOOTTIME_OVERRIDE=1784800000
  export CC_BOOT_RESUME_MODE=resume
  mkdir -p "$CC_REGISTRY_DIR" "$CC_ROLES_DIR" "$C/wt"
  echo "desk-pane-uuid" > "$CC_ROLES_DIR/desk"

  for s in notify launch select keepalive launchctl mtime; do :; done
  export CC_NOTIFY_BIN="$C/stub-notify" CC_RESUME_LAUNCH_BIN="$C/stub-launch"
  export CC_RESUME_SELECT_BIN="$C/stub-select" CC_KEEPALIVE_BIN="$C/stub-keepalive"
  export CC_LAUNCHCTL_BIN="$C/stub-launchctl" CC_TRANSCRIPT_MTIME_BIN="$C/stub-mtime"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$CC_NOTIFY_BIN"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$CC_RESUME_LAUNCH_BIN"
  printf '#!/bin/bash\nprintf "started\\n" >> "$0.log"\n' > "$CC_KEEPALIVE_BIN"
  printf '#!/bin/bash\nexit 0\n' > "$CC_LAUNCHCTL_BIN"
  # transcript_mtime answers "recent" ONLY for the correct (acct, sid, cwd) triple — which is the
  # whole discriminator: under the shift it is called with the cwd as the account and the NAME as
  # the sid, so it returns the stale default and the ghost is dropped.
  cat > "$CC_TRANSCRIPT_MTIME_BIN" <<SH
#!/bin/bash
[ "\$1" = "" ] && [ "\$2" = "SIDTOKEN" ] && [ "\$3" = "$C/wt" ] && { echo 1784799900; exit 0; }
echo 1
SH
  # identity pass-through select, mirroring tests/boot-resume.bats
  cat > "$CC_RESUME_SELECT_BIN" <<'SH'
#!/bin/bash
while [ $# -gt 0 ]; do
  case "$1" in
    --candidate) a="${2%%:*}"; rest="${2#*:}"; s="${rest%%:*}"; c="${rest#*:}"
                 printf '%s\t%s\t%s\t\n' "$a" "$s" "$c"; shift 2 ;;
    *) shift ;;
  esac
done
SH
  chmod +x "$CC_NOTIFY_BIN" "$CC_RESUME_LAUNCH_BIN" "$CC_RESUME_SELECT_BIN" \
           "$CC_KEEPALIVE_BIN" "$CC_LAUNCHCTL_BIN" "$CC_TRANSCRIPT_MTIME_BIN"

  # startedAt predates the fixed boot epoch ⇒ a genuine ghost. NO "account" key at all.
  cat > "$CC_REGISTRY_DIR/r1.json" <<JSON
{"paneUUID":"P1","name":"","cwd":"$C/wt","pid":999999,"startedAt":1784799000000,"session_id":"SIDTOKEN"}
JSON
  run bash "$REPO/scripts/boot-resume.sh"
  [ "$status" -eq 0 ]
  # the ghost was counted AND handed to the launcher
  run grep -c . "$CC_RESUME_LAUNCH_BIN.log"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c 'SIDTOKEN' "$CC_RESUME_LAUNCH_BIN.log"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# NB this one is a CONTRACT guard, not a defect regression: lr-select rejects a --candidate with an
# empty acct or sid at parse time, and filters a candidate whose cwd is missing, so today no empty
# cell can reach column 1-3 and `branch` (the only routinely-empty cell) is LAST. The padding is
# therefore belt-and-braces — said plainly rather than dressed up with a test that cannot go red.
# What this DOES lock is that the padded emitter still round-trips to the same four values.
@test "lr-select: a winner row round-trips through the pad with branch empty" {
  # lr-select filters any candidate with no transcript, so build the real fixture its own suite
  # uses: $LR_SELECT_HOME/<store>/projects/<slug-of-cwd>/<sid>.jsonl. The head record deliberately
  # carries NO gitBranch, which is the empty middle cell under test.
  export LR_SELECT_HOME="$C/home"
  local wt="$C/wt" slug dir
  slug="$(printf '%s' "$wt" | tr '/' '-')"
  dir="$LR_SELECT_HOME/.claude-next/projects/$slug"
  mkdir -p "$dir" "$wt"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-07-21T06:00:00Z"}\n' "$wt" > "$dir/SID1.jsonl"
  printf '{"type":"assistant","timestamp":"2026-07-21T06:05:00Z"}\n' >> "$dir/SID1.jsonl"

  probe "python3 '$REPO/scripts/limit-recover/lr-select.py' \\
           --candidate 'next:SID1:$wt' --recency-min 0 --quiet > \"\$0.d\"
         IFS=\$'\t' read -r acct sid cwd br < \"\$0.d\"
         unpad() { [ \"\$1\" = \$'\037' ] || printf '%s' \"\$1\"; }
         printf '[%s][%s][%s][%s]' \"\$(unpad \"\$acct\")\" \"\$(unpad \"\$sid\")\" \\
           \"\$(unpad \"\$cwd\")\" \"\$(unpad \"\$br\")\""
  [ "$status" -eq 0 ]
  [ "$output" = "[next][SID1][$wt][]" ]
}

@test "idl-abstain-alarm: an empty hook key does not invent a hook named after its own count" {
  export CC_IDL="$C/idl.jsonl"
  : > "$CC_IDL"
  i=0
  while [ "$i" -lt 12 ]; do
    printf '%s\n' '{"ts":"2099-01-01T00:00:00Z","hook":"","disposition":"abstained"}' >> "$CC_IDL"
    i=$((i + 1))
  done
  run env CC_IDL="$CC_IDL" bash "$REPO/scripts/idl-abstain-alarm.sh"
  # origin/main renders `HEALTHY 12  total=12 abst=0 … blind=  (0%)` — a hook named after its own
  # total, declared HEALTHY, with abst=0 for 12 records that were ALL abstentions and an EMPTY
  # blind count. The summary counts it as a real hook (hooks=1). The exit code is the alarm
  # verdict, not a test signal, so the assertions are on the render + the summary.
  refute_grep 'HEALTHY  *[0-9][0-9]*  *total='
  refute_grep "$PAD"
  printf '%s' "$output" | grep -q 'hooks=0'
}

# ─── §3 · the repo-wide guard ──────────────────────────────────────────────────────────────────

# Files that read TSV with `IFS=$'\t' read` but legitimately carry no padding def. Each needs a
# REASON, and a reviewed exemption is cheaper than re-deriving the analysis at every future edit.
# Format: <path>|<reason>
tsv_exemptions() {
  cat <<'EOF'
bin/cc-blockers|already padded on feat/relogin-observability (0dac237) — that stream owns the file; a second fix here would only conflict
hooks/session-index-sweep.sh|consumer only; its producer (session_index_extract_enriched) pads at the emitter. The file is being rewritten on fix/infra-perfection, which deletes both reads
scripts/lead-deathwatch.sh|reads a watch-file and the kqueue helper's output — neither is a jq producer, and both emit fixed-arity rows
scripts/desk-recycle-invariant.sh|resolve_desk guarantees all three cells non-empty before printing (cfg falls back to the CC default root; an empty cwd returns 1)
scripts/relogin-probes/e1-concurrent-logins.sh|producer REFUSES on an empty identity field rather than emitting one (all four are required), so non-empty is guaranteed at the source instead of padded — the same discharge as desk-recycle-invariant above
EOF
}

@test "guard: every file reading IFS=tab TSV either pads at the emitter or is a reviewed exemption" {
  cd "$REPO"
  unpadded=""
  for f in $(grep -rlF "IFS=\$'\t' read" bin hooks scripts 2>/dev/null | sort); do
    # A file participates in the convention if it PADS at its own emitter (`def cell(ph):` /
    # `def cell:` / the python `_cell` helper) or if it is a pure CONSUMER that UN-PADS what an
    # upstream emitter padded (session_index_unpad / a local unpad()). Either is a deliberate,
    # greppable statement that the author considered the collapse; neither is accidental.
    if grep -qE 'def cell(\(ph\))?:|def _cell' "$f"; then continue; fi
    if grep -qE 'session_index_unpad|unpad\(\)|TSV_PAD' "$f"; then continue; fi
    # bin/cc-relogin-poll pads with an equivalent awk idiom instead of a jq def — `norm <n>` right-
    # fills the row to n fields and substitutes "-" for every empty, `dash` un-pads on read. That is
    # the same guarantee reached another way, and the recognizer must not demand one house style:
    # this guard exists to catch UNPADDED readers, not to enforce a spelling.
    if grep -qE '^norm\(\)|^dash\(\)' "$f"; then continue; fi
    if tsv_exemptions | grep -q "^$f|"; then continue; fi
    unpadded="$unpadded $f"
  done
  [ -z "$unpadded" ] || printf 'unpadded TSV reader(s) with no reviewed exemption:%s\n' "$unpadded" >&2
  [ -z "$unpadded" ]
}

@test "guard: every exemption still names a file that exists and still reads IFS=tab TSV" {
  cd "$REPO"
  stale=""
  while IFS='|' read -r path reason; do
    [ -n "$path" ] || continue
    if [ ! -f "$path" ]; then stale="$stale $path(missing)"; continue; fi
    grep -qF "IFS=\$'\t' read" "$path" || stale="$stale $path(no-longer-reads-tsv)"
    [ -n "$reason" ] || stale="$stale $path(no-reason)"
  done < <(tsv_exemptions)
  [ -z "$stale" ] || printf 'stale exemption(s):%s\n' "$stale" >&2
  [ -z "$stale" ]
}

@test "guard: no padding sentinel is ever left in a tracked source file as a raw byte" {
  # The sentinel belongs in a shell $'\037' / jq $pad / python "\x1f" literal — never as a raw
  # control byte pasted into source, which is invalid inside a JSON string literal for jq.
  #
  # NOT `grep -rlP`: BSD grep (/usr/bin/grep on macOS) rejects -P outright with exit 2, and the
  # `2>/dev/null || true` this case used to carry swallowed that straight into a PASS — the scan
  # would report "clean" under a stock PATH precisely when it had never run at all. It only ever
  # worked here because `grep` on this box happens to be ugrep. That is the same silent direction
  # as the defect this whole file exists to pin, one layer up in the guard itself.
  #
  # `git grep` is portable, and it scopes the scan to TRACKED files — which is what the claim is
  # actually about. A plain `-r` scan also trips over untracked build artefacts: the working
  # __pycache__/lr-select.cpython-311.pyc legitimately contains a 0x1f byte.
  #
  # Exit 1 is the PASS: 0 = a sentinel IS present, 1 = ran and found none, >1 = the scan failed.
  cd "$REPO"
  run git grep -lF -- "$PAD" -- bin hooks scripts tests
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  # …and prove that same scan can still SEE a raw sentinel, so the silence above is evidence of
  # absence rather than evidence of a detector that stopped detecting.
  printf 'x%sy\n' "$PAD" > "$C/planted.txt"
  cd "$C"
  run git grep --no-index -lF -- "$PAD"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
