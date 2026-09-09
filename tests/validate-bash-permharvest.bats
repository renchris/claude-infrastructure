#!/usr/bin/env bats
# validate-bash PERMHARVEST arms — the chokepoint on `cc-permission-harvest --apply`, and the
# decision log that makes a refusal attributable.
#
# Subject: hooks/validate-bash.sh, two arms (docs/plans/PERMISSION_HARVEST.md §3.3, §5):
#   (a) a DENY when one clause's argv names the tool (by BASENAME) and carries --apply. Permission
#       config is authorization; an agent widening its own allowlist is the one act no later guard
#       can police, so the apply belongs to the operator's typed `yes` at cc-do. The tool's own env
#       check is a courtesy an agent can unset on the same line — a PreToolUse hook cannot be.
#   (b) deny()/warn() each append ONE JSONL line {ts, sid, decision, reason} — because
#       bash-commands.log is written AFTER those helpers have exited, so the audit corpus holds,
#       by construction, nothing this hook ever refused, and 80% of what read as a rule gap was a
#       hook asking (§10 B1-3, B2-1).
#
# Every DENY is paired with the control that differs by one lever, because a guard that always
# fires discriminates nothing (MEMORY.md alarm-polarity-and-attention-budget):
#   deny --apply             ↔ --check (the mutant the message names) · the report form
#   deny bash -c "…"         ↔ bash -c "echo …" (inert head one level down)
#   deny second && clause    ↔ --apply in a DIFFERENT clause from the tool
#   deny (any spelling)      ↔ the same words inside a commit message, an echo, a grep pattern
# and the UNCLEAR path is shown to fail in the SAFE direction, twice, by two different causes.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  # Ambient seams pinned (this repo's recurring latent-unhermetic class): the hook sources
  # hooks/lib/*.sh by a $HOME fallback chain, logs under $HOME, and reads the checkout seam.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$D/shared"
  export CC_VB_DECISION_LOG="$D/decisions.jsonl"
  unset VALIDATE_BASH_LEGACY VALIDATE_BASH_DISABLED
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# probe <command> [session-id] — drive the hook with a PreToolUse payload; $output is its stdout.
probe() {
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" \
    "{tool_name:\"Bash\", tool_input:{command:\$c}, session_id:\$s}" | "$0"' \
    "$HOOK" "$1" "${2:-sid-permharvest}"
}
# probe_nosid <command> — the same payload with NO session_id key at all
probe_nosid() {
  run bash -c 'jq -nc --arg c "$1" "{tool_name:\"Bash\", tool_input:{command:\$c}}" | "$0"' "$HOOK" "$1"
}
decision() { # → deny | ask | none
  if [ -z "$output" ]; then echo none; return; fi
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
logged() { wc -l < "$CC_VB_DECISION_LOG" 2>/dev/null | tr -d ' '; }

@test "DENIES: cc-permission-harvest --apply — and the reason names the boundary, cc-do, and --check" {
  probe "cc-permission-harvest --apply"
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  reason | grep -q 'AUTHORIZATION'
  reason | grep -q 'cc-do'
  reason | grep -q -- '--check'
}

@test "DENIES: the absolute-path spelling under HOME (basename decides, not the text)" {
  probe '$HOME/.claude/bin/cc-permission-harvest --apply'
  [ "$(decision)" = deny ]
  probe "/Users/someone/.claude/bin/cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
}

@test "DENIES: interpreter prefix, tilde path and CONFIRM=1 together — spelling is irrelevant" {
  probe "CONFIRM=1 /usr/bin/python3 ~/.claude/bin/cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
}

@test "DENIES: --apply with further arguments (--only) is still --apply" {
  probe "cc-permission-harvest --apply --only 'Bash(gh pr view:*)'"
  [ "$(decision)" = deny ]
}

@test "DENIES: the tool in a SECOND clause (position in the line is not the test)" {
  probe "cc-permission-harvest --check && cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
}

@test "DENIES: a bash -c wrapper (argv one level down)" {
  probe 'bash -c "cc-permission-harvest --apply"'
  [ "$(decision)" = deny ]
  probe "sh -c 'CONFIRM=1 cc-permission-harvest --apply'"
  [ "$(decision)" = deny ]
}

@test "DENIES: sudo and command substitution are the same invocation" {
  probe "sudo cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
  probe 'x=$(cc-permission-harvest --apply); echo "$x"'
  [ "$(decision)" = deny ]
}

@test "DENIES: a newline is a command separator, so echo cannot lend its inertness to the next line" {
  probe "$(printf 'echo about to apply\ncc-permission-harvest --apply')"
  [ "$(decision)" = deny ]
}

@test "DENIES: xargs assembling --apply from stdin is the invocation it assembles" {
  probe "printf -- --apply | xargs cc-permission-harvest"
  [ "$(decision)" = deny ]
}

@test "PASSES: --check — the read-only mutant the message points at" {
  probe "cc-permission-harvest --check"
  [ "$status" -eq 0 ]
  [ "$(decision)" = none ]
}

@test "PASSES: the report form, cc-permission-harvest 30 --json --out dir" {
  probe "cc-permission-harvest 30 --json --out /tmp/permharvest-out"
  [ "$(decision)" = none ]
}

@test "PASSES: --apply in a DIFFERENT clause from the tool (two invocations, neither is this rule)" {
  probe "cc-permission-harvest --check && echo --apply"
  [ "$(decision)" = none ]
}

@test "PASSES: the words inside a commit message — text is not execution" {
  probe 'git commit -m "feat(permission-harvest): deny cc-permission-harvest --apply in-session"'
  [ "$(decision)" = none ]
}

@test "PASSES: an inert head (echo) and a grep for the string" {
  probe "echo cc-permission-harvest --apply"
  [ "$(decision)" = none ]
  probe "grep -n 'cc-permission-harvest --apply' hooks/validate-bash.sh"
  [ "$(decision)" = none ]
}

@test "PASSES: bash -c whose inner head is inert (the nested read is a read, not a substring match)" {
  probe 'bash -c "echo cc-permission-harvest --apply"'
  [ "$(decision)" = none ]
}

@test "PASSES: a heredoc BODY written through cat is a document, not argv" {
  probe "$(printf 'cat > notes.md <<EOF\nnever run cc-permission-harvest --apply in a session\nEOF\n')"
  [ "$(decision)" = none ]
}

@test "DENIES: a heredoc BODY feeding python3 is code, refused on the presence of both literals" {
  probe "$(printf 'python3 - <<PY\nimport subprocess\nsubprocess.run(["cc-permission-harvest", "--apply"])\nPY\n')"
  [ "$(decision)" = deny ]
}

@test "UNCLEAR fails SAFE (1): an unbalanced quote drops to the whitespace split and still refuses" {
  probe 'cc-permission-harvest --apply "'
  [ "$(decision)" = deny ]
}

@test "UNCLEAR fails SAFE (2): a python3 that cannot run drops to the whitespace split and still refuses" {
  mkdir -p "$D/nopy"
  printf '#!/bin/bash\nexit 1\n' > "$D/nopy/python3"; chmod +x "$D/nopy/python3"
  PATH="$D/nopy:$PATH" probe "cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
  # …and the same fallback keeps the inert-head and separate-clause controls
  PATH="$D/nopy:$PATH" probe "echo cc-permission-harvest --apply"
  [ "$(decision)" = none ]
  PATH="$D/nopy:$PATH" probe "cc-permission-harvest --check && echo --apply"
  [ "$(decision)" = none ]
}

@test "deny() appends ONE parseable line: ts numeric, sid from the payload, decision=deny, reason capped at 200" {
  probe "cc-permission-harvest --apply" "sid-abc-123"
  [ "$(decision)" = deny ]
  [ "$(logged)" -eq 1 ]
  line="$(head -1 "$CC_VB_DECISION_LOG")"
  printf '%s' "$line" | jq -e . >/dev/null
  [ "$(printf '%s' "$line" | jq -r '.decision')" = deny ]
  [ "$(printf '%s' "$line" | jq -r '.sid')" = sid-abc-123 ]
  [[ "$(printf '%s' "$line" | jq -r '.ts')" =~ ^[0-9]{9,}$ ]] || false
  now="$(date -u +%s)"
  ts="$(printf '%s' "$line" | jq -r '.ts')"
  [ $((now - ts)) -lt 120 ]
  # THE CAP IS 200 BYTES, AND THE CODEPOINT COUNT IS THEREFORE ≤ 200, NEVER EXACTLY IT. Hooks run
  # with LANG unset here, so bash slices bytes; this reason carries one em-dash inside the first
  # 200 bytes, so the line is 198 codepoints. Pinning `-eq 200` would pin the number of em-dashes
  # in a MESSAGE — a fixture of the prose, not of the mechanism — and the first reword would go
  # red for no defect. What must hold is the bound, a prefix of the real reason, and above all
  # VALIDITY: `jq -e .` on the line is the assertion that matters, because the cut lands
  # mid-sequence about one time in three and a lone continuation byte does not truncate the
  # record, it DELETES it from every jq reader (MEMORY.md parse-failures-are-verdicts-not-noise).
  rlen="$(printf '%s' "$line" | jq -r '.reason | length')"
  [ "$rlen" -le 200 ]
  [ "$rlen" -ge 190 ]
  logged_reason="$(printf '%s' "$line" | jq -r '.reason')"
  [ "${logged_reason}" = "$(reason | cut -c1-"${#logged_reason}")" ]
  printf '%s' "$logged_reason" | iconv -f UTF-8 -t UTF-8 >/dev/null   # no half a character survived
  [ "$(printf '%s' "$line" | jq -r 'keys | sort | join(" ")')" = "decision reason sid ts" ]
}

@test "CONTROL: a reason whose 200-BYTE cut lands mid-character still yields a parseable line" {
  # The mutant this pins: drop the iconv trim in log_decision and this line becomes invalid UTF-8,
  # jq -e fails, and the record is gone rather than short. Built from the rm-guard ask, whose
  # reason interpolates the target — so the em-dash count before byte 200 is under the test's
  # control rather than the message author's.
  probe "rm -r $(printf 'á%.0s' $(seq 1 120))" "sid-mb"
  [ "$(decision)" = ask ]
  line="$(head -1 "$CC_VB_DECISION_LOG")"
  printf '%s' "$line" | jq -e . >/dev/null
  printf '%s' "$line" | jq -r '.reason' | iconv -f UTF-8 -t UTF-8 >/dev/null
  [ "$(printf '%s' "$line" | jq -r '.reason' | LC_ALL=C wc -c | tr -d ' ')" -le 201 ]
}

@test "warn() appends decision=ask (git reset --hard), one line, parseable" {
  probe "git reset --hard HEAD~1" "sid-warn"
  [ "$(decision)" = ask ]
  [ "$(logged)" -eq 1 ]
  line="$(head -1 "$CC_VB_DECISION_LOG")"
  printf '%s' "$line" | jq -e . >/dev/null
  [ "$(printf '%s' "$line" | jq -r '.decision')" = ask ]
  [ "$(printf '%s' "$line" | jq -r '.sid')" = sid-warn ]
  printf '%s' "$line" | jq -r '.reason' | grep -q 'git reset --hard'
}

@test "a reason carrying a double quote from the command still yields a parseable line" {
  probe 'rm -r "q\"uote-dir"' "sid-q"
  [ "$(decision)" = ask ]
  line="$(head -1 "$CC_VB_DECISION_LOG")"
  printf '%s' "$line" | jq -e . >/dev/null
  printf '%s' "$line" | jq -r '.reason' | grep -q 'q"uote-dir'
}

@test "an allowed command appends NOTHING — the modal path pays no journal line" {
  probe "echo hello" "sid-ok"
  [ "$(decision)" = none ]
  [ ! -f "$CC_VB_DECISION_LOG" ]
}

@test "a payload with no session_id logs the '-' placeholder, never an empty field" {
  probe_nosid "cc-permission-harvest --apply"
  [ "$(decision)" = deny ]
  [ "$(head -1 "$CC_VB_DECISION_LOG" | jq -r '.sid')" = - ]
}

@test "an unwritable decision log costs the journal line, never the refusal (fail-open)" {
  : > "$D/not-a-dir"
  CC_VB_DECISION_LOG="$D/not-a-dir/decisions.jsonl" probe "cc-permission-harvest --apply"
  [ "$status" -eq 0 ]
  [ "$(decision)" = deny ]
  [ ! -f "$D/not-a-dir/decisions.jsonl" ]
}

@test "the default log path is under HOME/.claude/logs, created on first use" {
  unset CC_VB_DECISION_LOG
  probe "cc-permission-harvest --apply" "sid-default"
  [ "$(decision)" = deny ]
  [ -f "$HOME/.claude/logs/validate-bash-decisions.jsonl" ]
  [ "$(jq -r '.sid' "$HOME/.claude/logs/validate-bash-decisions.jsonl")" = sid-default ]
}

# ── THE QUOTING BYPASS (2026-09-09) ─────────────────────────────────────────────────────────────
#
# Every arm above keeps both literals intact, so none of them could see the class below: the arm
# was ENTERED by `[[ "$CMD" == *cc-permission-harvest* && "$CMD" == *--apply* ]]` over the RAW
# command, which is exactly the SPELLING test the hook's own comment argues against. Bash removes
# quotes before exec and the hook did not, so eight spellings skipped the tokenizer, the fail-safe
# fallback and the deny — MEASURED at decision=none while a PATH stub proved bash still ran the
# tool with `--apply` in argv. `--apply` is one apostrophe from open is not a chokepoint.
#
# Each is paired below with the control that differs by ONE lever, because the fix (deleting
# quote characters from a probe copy, and refusing an unresolvable `$` in a clause that names the
# tool) over-blocks if it is not bounded.

@test "DENIES: the tool name split by an empty single-quote pair — bash removes it, so must the gate" {
  probe "cc-permission-har''vest --apply"
  [ "$(decision)" = deny ]
}

@test "DENIES: the tool name split by an empty double-quote pair" {
  probe 'cc-permission-har""vest --apply'
  [ "$(decision)" = deny ]
}

@test "DENIES: the tool name split by a backslash escape" {
  probe 'cc-permission-harve\st --apply'
  [ "$(decision)" = deny ]
}

@test "DENIES: --apply split by a double-quote pair" {
  probe 'cc-permission-harvest --ap"p"ly'
  [ "$(decision)" = deny ]
}

@test "DENIES: --apply split by a single-quote pair" {
  probe "cc-permission-harvest --app'l'y"
  [ "$(decision)" = deny ]
}

@test "DENIES: --apply carried in a variable — shlex cannot resolve it, so the clause is refused" {
  probe 'X=--apply; cc-permission-harvest $X'
  [ "$(decision)" = deny ]
}

@test "DENIES: the TOOL carried in a variable — the head itself is unresolvable" {
  probe 'TOOL=cc-permission-harvest; $TOOL --apply'
  [ "$(decision)" = deny ]
}

@test "DENIES: the dollar-single-quote form, which posix shlex leaves sigil-prefixed" {
  probe "\$'cc-permission-harvest' --apply"
  [ "$(decision)" = deny ]
}

@test "DENIES: the dollar-double-quote form on the flag" {
  probe 'cc-permission-harvest $"--apply"'
  [ "$(decision)" = deny ]
}

@test "DENIES: env -u stripping the tool's own guard, composed with a split literal" {
  # The tool's CLAUDECODE check is a courtesy message, and `env -u` is a one-token defeat of
  # anything in the environment. With the hook skipped there was nothing left at all; this arm
  # pins that the hook is not skippable by the same trick.
  probe 'env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT CONFIRM=1 cc-permission-har""vest --apply'
  [ "$(decision)" = deny ]
}

@test "PASSES: a variable in a --check run — the dollar rule is scoped, not a blanket refusal" {
  # PHA_PROBE deletes `$` too, so `--out "$OUT"` cannot manufacture the literal; and even when a
  # command DOES carry both literals, a `$` in somebody else's clause is not this rule.
  probe 'cc-permission-harvest --json --out "$OUT"'
  [ "$(decision)" = none ]
  probe 'grep -n -- --apply $SOMEFILE && cc-permission-harvest --check'
  [ "$(decision)" = none ]
}

@test "PASSES: the split spellings inside a commit message are still text, not argv" {
  # The pole that keeps the quote-stripping honest: folding quotes must not turn a QUOTED mention
  # into an invocation. The rm guard's first cut blocked its own fix from being committed.
  probe 'git commit -m "deny cc-permission-har''vest --apply"'
  [ "$(decision)" = none ]
  probe 'echo "run cc-permission-harvest --ap\"p\"ly yourself"'
  [ "$(decision)" = none ]
}
