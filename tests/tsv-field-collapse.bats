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
  probe 'printf "acct\tREQUIRED\t\tWHEN\t12\tclaude-next\n" |
         { IFS=$'\''\t'\'' read -r a b c d e f; printf "%s|%s|%s|%s" "$c" "$d" "$e" "$f"; }'
  [ "$status" -eq 0 ]
  # c SHOULD be the empty field and f SHOULD be claude-next. It is neither.
  [ "$output" = "WHEN|12|claude-next|" ]
}

@test "mechanism: padding the empty cell restores every column to its own variable" {
  probe 'printf "acct\tREQUIRED\t-\tWHEN\t12\tclaude-next\n" |
         { IFS=$'\''\t'\'' read -r a b c d e f; printf "%s|%s|%s|%s" "$c" "$d" "$e" "$f"; }'
  [ "$status" -eq 0 ]
  [ "$output" = "-|WHEN|12|claude-next" ]
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
  # Seed the deadline RELATIVE to now (scripts/test-walltime-lint.sh): an absolute future stamp
  # silently changes meaning as the clock advances — cc-decide re-derives expiry from it, so the
  # fixture would flip on a calendar boundary with no code change. SIGNED offset: bare `date -v 720H`
  # SETS the hour rather than adding to it.
  deadline="$(date -u -v+720H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$CC_DECISIONS_DIR/p2.json" <<JSON
{"id":"p2","class":"B","veto_deadline":"$deadline","what_plain":"NOSTATUSPACKET"}
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
  # `if` rather than `[ … ] && …`: scripts/bats-assert-liveness.py once scanned .bats files
  # line-wise with no heredoc tracking, so the `&&` form inside this STUB body counted as a
  # non-final dead assertion in a @test and turned the dead-assertion RATCHET red. It tracks
  # both now — heredoc bodies are skipped, and statements are joined across continuations — so
  # this is no longer forced. Left as an `if` because it is equally clear either way.
  cat > "$C/bin/claude-accounts" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "--json" ]; then
  printf '%s\n' '{"rows":[{"acct":"next","session_pct":3,"fable_pct":24}]}'
fi
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

@test "assignee-pane-residency: a member with an EMPTY name keeps its pane id in the PANE column" {
  # `.name // "?"` is the defect, not the fix: jq's `//` fires on null/false only and "" is TRUTHY,
  # so an empty-STRING name sails through the default and emits an empty cell 2 of 4. The row then
  # collapses to team=<team> name=<paneId> pane=<joinedAt>.
  #
  # The discriminator is the joinedAt MILLISECONDS, which the render never prints (it reads into
  # `_joined` and drops it). It can only reach the output by being shifted into `pane` — so its
  # presence is the collapse and nothing else. Asserting on "401" instead would pass VACUOUSLY:
  # the pane id is in the output either way, just in the wrong column.
  mkdir -p "$C/teams/session-aa" "$C/state"
  local old_ms; old_ms=$(( ($(date +%s) - 86400) * 1000 ))
  printf '{"members":[{"name":"","tmuxPaneId":"401","joinedAt":%s}]}\n' "$old_ms" \
    > "$C/teams/session-aa/config.json"
  printf '401\n' > "$C/wins"
  printf '#!/bin/bash\ncat "%s/wins"\n' "$C" > "$C/it2"; chmod +x "$C/it2"
  printf '#!/bin/bash\nexit 1\n'                > "$C/ps";  chmod +x "$C/ps"

  run env CC_RESIDENCY_TEAM_GLOB="$C/teams/*/config.json" \
          CC_RESIDENCY_IT2_BIN="$C/it2" CC_RESIDENCY_PS_BIN="$C/ps" \
          CC_RESIDENCY_STATE_DIR="$C/state" \
          bash "$REPO/scripts/assignee-pane-residency.sh"
  # the member must still be SEEN — a fix that merely dropped the row would also refute the ms
  printf '%s' "$output" | grep -q 'resident members:'
  refute_grep "$old_ms"
}

@test "thrash-block-recover: an id-less ledger record does not name an item after its own verdict" {
  # `jq -R 'fromjson? // empty'` drops lines that are not JSON; a line that IS valid JSON but has no
  # `id` survives, groups under a null key and emits an empty first cell. Unpadded that reads back as
  # id="RECOVER", verdict="1" — a table row naming an item after its own verdict, while the summary
  # counts it as a HOLD. Dry run by default, so this asserts the RENDER, which is where it shows.
  local B="$C/backlog.jsonl"
  {
    # (a) the id-less group — same block shape, so it reaches the emitter on merit, not by accident
    printf '{"ts":"2026-08-07T22:20:00Z","event":"claim","by":"w1"}\n'
    printf '{"ts":"2026-08-07T22:20:10Z","event":"reopen","by":"w1"}\n'
    printf '{"ts":"2026-08-07T22:20:20Z","event":"block","by":"cc-backlog-reap","needs":"persistent thrash — 2 fast claim cycles"}\n'
    # (b) POSITIVE CONTROL — a well-formed group that must still be recovered, so a fix that simply
    #     stopped emitting rows cannot pass this test
    printf '{"id":"aaaa11112222","ts":"2026-08-07T22:30:00Z","event":"claim","by":"w2"}\n'
    printf '{"id":"aaaa11112222","ts":"2026-08-07T22:30:10Z","event":"reopen","by":"w2"}\n'
    printf '{"id":"aaaa11112222","ts":"2026-08-07T22:30:20Z","event":"block","by":"cc-backlog-reap","needs":"persistent thrash — 2 fast claim cycles"}\n'
  } > "$B"

  run env CC_BACKLOG_FILE="$B" bash "$REPO/scripts/thrash-block-recover.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^aaaa11112222 '   # the real item still renders, still RECOVER
  refute_grep '^RECOVER'                             # …and no row is named after a verdict
  refute_grep '^HOLD'
}

@test "backlog-consolidation-trigger: a cluster with an empty project keeps its title in the TITLE column" {
  # `cc-backlog add` without --project mints items whose project folds to "", and .key groups ON the
  # project — so a cluster of them is a cluster of empty cells, and the threshold guarantees at
  # least $th of them before anything renders. Cell 1 is a jq array LENGTH and cell 3 is LAST, so
  # `.project` is the only empty-reachable non-final cell, and it is the one that bites.
  local B="$C/backlog.jsonl" i
  for i in 1 2 3 4 5; do
    printf '{"id":"cluster%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"","title":"EMPTYPROJTITLE"}\n' "$i"
  done > "$B"
  run env CC_BACKLOG_FILE="$B" bash "$REPO/scripts/backlog-consolidation-trigger.sh" --threshold 5
  [ "$status" -eq 0 ]
  # origin/main renders "  5x  [EMPTYPROJTITLE]  " — the title in the PROJECT column, title blank.
  printf '%s' "$output" | grep -q '5x  \[-\]  EMPTYPROJTITLE'
  refute_grep '\[EMPTYPROJTITLE\]'
}

@test "cc-offload ls: a declaration with an empty state still renders its own columns" {
  # `(.state // "UNKNOWN")` substitutes for null and NEVER for "", so an empty state emitted an
  # empty cell. Four cells were empty-reachable that way (id · state · age_s · branch) and none is
  # last. This one is not merely a shifted render: `read -r id st age acct br url ret` left `ret`
  # unset, and origin/main dies on `[: next2: integer expression expected` then `next2: unbound
  # variable` — the tally line never prints at all.
  mkdir -p "$C/bin"
  printf '#!/bin/bash\ncat "$CC_FIXTURE_ROWS"\n' > "$C/bin/cc-cloud"; chmod +x "$C/bin/cc-cloud"
  printf '%s\n' '{"id":"sess-keep","state":"","age_s":12,"account":"next2","branch":"claude/x","url":"https://u"}' \
    > "$C/rows.ndjson"
  run env CC_FIXTURE_ROWS="$C/rows.ndjson" CC_OFFLOAD_CLOUD_BIN="$C/bin/cc-cloud" \
      bash "$REPO/bin/cc-offload" ls
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'sess-keep .*UNKNOWN'
  printf '%s' "$output" | grep -q 'next2'
  # the tally is the line the crash swallowed, so its presence is what proves the row survived
  printf '%s' "$output" | grep -q '1 UNKNOWN'
  refute_grep 'unbound variable'
}

# ─── §3 · the repo-wide guard ──────────────────────────────────────────────────────────────────

# THE RECOGNIZER AND THE REVIEWED EXEMPTION TABLE NOW LIVE IN scripts/tsv-pad-lint.sh, and these
# cases DRIVE that file rather than re-implementing it (2026-08-10, backlog e146d30857b4). Every
# exemption line moved across VERBATIM — nothing about the rule changed; where it is ENFORCED did.
#
# Why it had to move: this suite could only ever fail AFTER an unpadded reader landed. gate-select's
# `cited_only` (:280) requires a DIRECT edge's evidence to live in a suite's EXECUTABLE text, and
# this file named offenders only inside its exemption heredoc — so a BRAND-NEW script was named
# nowhere, its failure was exonerable-as-adjacent, and the land passed. The guard consequently
# re-reddened three times with a completely different offender set each time and ZERO overlap
# between them (six on 2026-07-31, six more by 2026-08-07, two more on 2026-08-10) — the measurement
# that says per-file remediation is a treadmill rather than a run of bad luck. The lint runs at the
# land gate itself, own-scoped, so it blocks the author who introduces the reader and nobody else.
#
# Keeping ONE recognizer is the point. Two auditors over one population that can disagree is its own
# defect class, and here the drift would have been invisible: this suite would have stayed green
# while the gate judged something else (memory: sibling-auditors-must-share-the-state-model).

@test "guard: every file reading IFS=tab TSV either pads at the emitter or is a reviewed exemption" {
  # 0 clean · 1 violation, offenders named in $output · 2 NON-VERDICT (bad root / broken scan),
  # which is why this asserts -eq 0 and not -ne 1: a lint that could not run has proved nothing.
  run bash "$REPO/scripts/tsv-pad-lint.sh" "$REPO"
  [ "$status" -eq 0 ]
}

@test "guard: every exemption still names a file that exists and still reads IFS=tab TSV" {
  # The ratchet's other direction, same lint: a stale line reds the run above. A clean tree cannot
  # show that the arm still FIRES, so this drives the lint's own fixtures, which plant all three
  # stale shapes (file gone · no longer reads TSV · no reason) and require each to go red.
  run bash "$REPO/scripts/tsv-pad-lint.sh" --selftest
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'both stale-exemption shapes'
}

@test "guard: the lint's assembled marker finds exactly the readers a literal grep finds" {
  # The lint builds `IFS=$'\t' read` with printf instead of writing it, so it does not match its own
  # scan — which makes the spelling a construction, and a construction can be wrong. Its --selftest
  # cannot catch that: those fixtures are written FROM the same variable, so a corrupted marker
  # produces corrupted fixtures and every case still passes (measured — a mutant spelling it
  # `IFS=$'QQt' read` scored a clean 19/19). The cross-check therefore has to come from an
  # INDEPENDENT spelling, and this file can hold one safely: tests/ is outside the scanned dirs.
  cd "$REPO"
  mine="$(grep -rlF "IFS=\$'\t' read" bin hooks scripts 2>/dev/null | sort | grep -c .)"
  [ "$mine" -gt 0 ]                       # a literal that finds nothing would make this vacuous
  run bash "$REPO/scripts/tsv-pad-lint.sh" "$REPO"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "clean — $mine reader(s)"
}

@test "guard: WIRED — ship-land's gate block invokes the lint" {
  # Enforcement by this suite alone is the post-hoc detection this whole change exists to replace,
  # so the wiring IS part of the claim, not an implementation detail
  # (memory: enforcement-must-live-at-the-chokepoint). Same case the sibling ratchets pin.
  grep -q 'tsv-pad-lint.sh' "$REPO/scripts/ship-land.sh" || {
    echo "the lint is not wired into ship-land.sh — enforcement by this suite alone is detection, not a gate"
    false
  }
}

@test "guard: the lint is executable (a non-executable gate is a silently skipped gate)" {
  # ship-land guards the block with `[[ -x "$TSVPAD_LINT" ]]`, so losing the bit does not fail loudly
  # — it steps over the gate, and every land then goes green on a check that never ran.
  [ -x "$REPO/scripts/tsv-pad-lint.sh" ] || {
    echo "scripts/tsv-pad-lint.sh is not executable — ship-land's [[ -x ]] guard would step over it"
    false
  }
}

@test "guard: the lint's verdict does not depend on the caller's CWD" {
  # scripts/nightly-regression.sh globs scripts/*lint*.sh and runs --selftest where supported, so
  # this file is picked up with no registration — but launchd sets no WorkingDirectory, so the
  # nightly reaches it with CWD=/. A ROOT derived from an unresolved $0, or a relative default,
  # would make the nightly's copy scan nothing and report clean (memory: gate-default-decides-
  # failure-direction). Both entry points are pinned, from the directory the nightly actually uses.
  run bash -c "cd / && bash '$REPO/scripts/tsv-pad-lint.sh' --selftest"
  [ "$status" -eq 0 ]
  run bash -c "cd / && bash '$REPO/scripts/tsv-pad-lint.sh'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'reader(s) under'      # it really scanned, it did not no-op green
}

@test "guard: the padding the RED message prescribes is a shape the recognizer ACCEPTS" {
  # A rule and the message that explains it rot INDEPENDENTLY, and a lint that prints a fix it would
  # itself reject is worse than one that prints nothing (memory: prescribed-remedy-worse-than-the-bug,
  # work-item-remedy-can-become-forbidden). So this drives the round trip rather than comparing two
  # literals: it lifts the prescription out of the lint's OWN refusal, pastes it into the file that
  # earned that refusal, and requires the verdict to flip.
  local t="$C/prescribed"
  mkdir -p "$t/scripts"
  cat > "$t/scripts/z.sh" <<'SH'
#!/bin/bash
while IFS=$'\t' read -r a b c; do :; done
SH
  run env CC_TSVPAD_EXEMPTIONS="" bash "$REPO/scripts/tsv-pad-lint.sh" "$t"
  [ "$status" -eq 1 ]
  local fix
  fix="$(printf '%s' "$output" | grep -F 'def cell(ph):')"
  [ -n "$fix" ]
  # as CODE, not as a comment: the recognizer greps whole files, so pasting the fix into a comment
  # would pass without exercising anything. This is the house shape (bin/cc-backlog's CELL=…).
  printf 'JQPROG=%s\n' "'$fix'" >> "$t/scripts/z.sh"
  run env CC_TSVPAD_EXEMPTIONS="" bash "$REPO/scripts/tsv-pad-lint.sh" "$t"
  [ "$status" -eq 0 ]
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
