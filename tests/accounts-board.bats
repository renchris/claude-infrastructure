#!/usr/bin/env bats
# accounts-board — the zero-token SessionStart board (DESK_ROUTER_AND_STARTUP_V1 W3.6).
#
# Subjects: hooks/accounts-board.sh (the reader) and bin/claude-accounts `--readout --narrow` +
# `--keepwarm` (the renderer and the producer).
#
# THE ASSERTION THIS SUITE EXISTS FOR is the CHANNEL, and it has three arms because there are
# three ways to be wrong and only one of them is loud:
#   · top-level `systemMessage`          → reaches the terminal, 0 model tokens.        (the goal)
#   · `hookSpecificOutput.systemMessage` → SILENTLY IGNORED. No error, no output, no clue.
#   · `additionalContext`                → works, and BILLS the board as input tokens
#                                          on every session start and every /clear.
# So "it renders" is not sufficient evidence of correctness and "it does not render" would not
# even be reached by a nested payload — hence one positive arm and two negative arms, asserted
# separately because they are different failures. M1 mutates the hook into the nested form and
# requires the positive arm to flip: without that, arms 2 and 4 could both be passing over a hook
# that emits nothing at all.
#
# The second load-bearing assertion is NEGATIVE — the hook must fork NO claude-accounts, because
# `--readout` measures 5.33s against a 5s hook timeout (§2.7) and calling it recreates the
# 21-29s-hook-killed-by-its-own-timeout defect W0 had just removed. A negative assertion is
# worthless without a positive control that the fixture COULD have seen the call, so test 12 is
# that control and it is not optional.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOOK="$REPO/hooks/accounts-board.sh"
  export CA_BIN="$REPO/bin/claude-accounts"
  export D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_ACCOUNTS_BOARD="$D/board.txt"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# A board with a recognisable, unique token, so "the board reached the payload" cannot be
# satisfied by any other text the hook happens to print.
BOARDTOK="ZZBOARDPAYLOADZZ"
mk_board() {
  cat > "$CC_ACCOUNTS_BOARD" <<EOF
Claude Max accounts · cached 12s · Tue 16:05
    account          5h    wk   Fbl  wk ↻   login
➤   next2            6%   48%   21%  3d 11h 26d 12h
$BOARDTOK
EOF
}

age_board() {  # <seconds-old> — exact, via utime; `touch -t` cannot express "N seconds ago"
  python3 -c "import os,sys,time;t=time.time()-float(sys.argv[2]);os.utime(sys.argv[1],(t,t))" \
    "$CC_ACCOUNTS_BOARD" "$1"
}

# Feed the payload as STDIN, through a function — never by interpolating the JSON into a
# `bash -c` string. `{"source":"startup"}` at the head of a command string is parsed by bash as a
# BRACE GROUP, so the hook receives empty stdin and the case silently tests the no-payload path
# instead of the one it names. That is how the first draft of this suite had cases 2 and 3 passing
# green while asserting nothing about `source` at all.
emit() {  # <source> → payload JSON in $D/out.json, hook's rc as the return
  printf '{"source":"%s","hook_event_name":"SessionStart"}' "${1:-startup}" \
    | "$HOOK" > "$D/out.json" 2> "$D/err.txt"
}
jqv() { jq -r "$1" < "$D/out.json"; }   # <filter> → its value, for `run`

# ── the channel ───────────────────────────────────────────────────────────────────────────────

@test "1 emits exactly ONE parseable JSON object" {
  mk_board
  run emit startup
  [ "$status" -eq 0 ]
  # `[ -s … ] && { …; false; }` is the inverted form the dead-assertion ratchet flags: on the GOOD
  # case (no stderr) the `&&` list itself returns 1, so the condition has to be the NEGATIVE one
  # with `||` — the idiom every other assertion in this file uses.
  [ ! -s "$D/err.txt" ] || { echo "wrote to stderr: $(cat "$D/err.txt")"; false; }
  # `jq -e .` over the whole stream would ACCEPT a concatenation of two objects (jq reads a
  # stream), which is exactly the shape a hook that emitted twice produces. Counting inputs is
  # what distinguishes one object from two.
  run jqv 'empty'                       # parses at all?
  [ "$status" -eq 0 ] || { echo "unparseable: $(cat "$D/out.json")"; false; }
  run bash -c "jq -s 'length' < '$D/out.json'"
  [ "$output" = "1" ] || { echo "emitted $output objects: $(cat "$D/out.json")"; false; }
}

@test "2 the board rides the TOP-LEVEL systemMessage key" {
  mk_board; emit startup
  run jqv '.systemMessage // empty'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BOARDTOK"* ]] || { echo "board text absent from .systemMessage: $output"; false; }
}

@test "3 the board is NOT in additionalContext — anywhere in the payload" {
  mk_board; emit startup
  # Recursive, not a fixed path: additionalContext lives under hookSpecificOutput today, and an
  # assertion pinned to one path would be silently satisfied by the same key at another.
  run jqv '[.. | objects | .additionalContext? // empty] | join("")'
  [ "$status" -eq 0 ]
  [[ "$output" != *"$BOARDTOK"* ]] || { echo "BILLED: board text found in additionalContext"; false; }
}

@test "4 the board is NOT under hookSpecificOutput.systemMessage (the ignored form)" {
  mk_board; emit startup
  run jqv '.hookSpecificOutput.systemMessage // empty'
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "nested systemMessage present — this form is SILENTLY IGNORED"; false; }
}

@test "5 MUTANT: nesting systemMessage flips tests 2 and 4 (so neither is vacuous)" {
  mk_board
  # Exactly the documented wrong shape, in a COPY of the real hook. If test 2 still passed against
  # this, it would be asserting nothing about WHERE the payload lives — only that some text came out.
  sed 's/{systemMessage:\$m}/{hookSpecificOutput:{hookEventName:"SessionStart",systemMessage:$m}}/' \
    "$HOOK" > "$D/mutant.sh"
  chmod +x "$D/mutant.sh"
  ! diff -q "$HOOK" "$D/mutant.sh" >/dev/null || { echo "mutation did not apply — the emit shape moved"; false; }

  printf '{"source":"startup"}' | "$D/mutant.sh" > "$D/out.json" 2>/dev/null
  run jqv '.systemMessage // empty'
  [[ "$output" != *"$BOARDTOK"* ]] || { echo "test 2 would pass on the NESTED form — it is vacuous"; false; }
  # ...and it DOES land in the ignored place, so the mutant is the intended one and test 4 sees it
  run jqv '.hookSpecificOutput.systemMessage // empty'
  [[ "$output" == *"$BOARDTOK"* ]] || { echo "mutant did not nest it — mutation is wrong"; false; }
}

# ── staleness: visible, in two bands ──────────────────────────────────────────────────────────

@test "6 a MISSING board degrades to one labelled line — no crash, no silence, no numbers" {
  rm -f "$CC_ACCOUNTS_BOARD"
  run emit startup
  [ "$status" -eq 0 ]
  run jqv '.systemMessage'
  [[ "$output" == *"unavailable"* ]] || { echo "missing board not labelled: $output"; false; }
  [[ "$output" == *"keepwarm"* ]] || { echo "does not name the producer: $output"; false; }
}

@test "7 an EMPTY board is labelled, not printed as a blank banner" {
  : > "$CC_ACCOUNTS_BOARD"
  run emit startup
  [ "$status" -eq 0 ]
  run jqv '.systemMessage'
  [[ "$output" == *"EMPTY"* ]]
}

@test "8 STALE band: numbers still shown, but under an explicit age label" {
  mk_board; age_board 600            # > CC_BOARD_STALE_S (300), < CC_BOARD_HARD_S (3600)
  run emit startup
  [ "$status" -eq 0 ]
  run jqv '.systemMessage'
  [[ "$output" == *"STALE"* ]] || { echo "stale board NOT labelled: $output"; false; }
  [[ "$output" == *"10m"* ]] || { echo "age not stated: $output"; false; }
  [[ "$output" == *"$BOARDTOK"* ]] || { echo "labelled band should still show the board"; false; }
}

@test "9 HARD band: the numbers are WITHHELD, not merely labelled" {
  mk_board; age_board 7200           # > CC_BOARD_HARD_S
  run emit startup
  [ "$status" -eq 0 ]
  run jqv '.systemMessage'
  [[ "$output" == *"withheld"* ]] || { echo "hard band not declared: $output"; false; }
  # THE POINT: a board this old can describe a 5h window that has already ended, so showing the
  # figures under a warning is not good enough — they must not be shown.
  [[ "$output" != *"$BOARDTOK"* ]] || { echo "ancient numbers were PRINTED: $output"; false; }
}

@test "10 the band thresholds are the knobs, not decoration — a tightened bar reclassifies" {
  # Guards against the bands being unreachable except at the defaults: the SAME 60s-old board
  # must land in all three classes as the bars move around it.
  mk_board; age_board 60
  emit startup;                                        run jqv '.systemMessage'
  [[ "$output" == *"$BOARDTOK"* && "$output" != *"STALE"* ]] || { echo "not fresh at defaults: $output"; false; }
  CC_BOARD_STALE_S=10 emit startup;                    run jqv '.systemMessage'
  [[ "$output" == *"STALE"* ]] || { echo "did not reclassify to STALE: $output"; false; }
  CC_BOARD_STALE_S=10 CC_BOARD_HARD_S=20 emit startup; run jqv '.systemMessage'
  [[ "$output" == *"withheld"* ]] || { echo "did not reclassify to HARD: $output"; false; }
}

@test "11 a compact SessionStart is silent — the board marks a beginning, not a mid-task event" {
  mk_board
  run emit compact
  [ "$status" -eq 0 ]
  [ ! -s "$D/out.json" ] || { echo "fired on compact: $(cat "$D/out.json")"; false; }
  # ...while the three that DO mean "a session is starting" all fire
  for s in startup clear resume; do
    emit "$s"; run jqv '.systemMessage // empty'
    [[ "$output" == *"$BOARDTOK"* ]] || { echo "source=$s did not fire"; false; }
  done
}

# ── the load-bearing negative: no inline claude-accounts call ─────────────────────────────────

# A witness that records ANY execution, planted at BOTH plausible invocation paths: on $PATH
# (a bare `claude-accounts`) and at $HOME/.claude/bin (the absolute form the rest of this repo
# uses). Covering only one leaves the other as a silent way to reintroduce the 5.33s call.
plant_witness() {
  export WITNESS="$D/witness"; rm -f "$WITNESS"
  mkdir -p "$D/shim" "$HOME/.claude/bin"
  printf '#!/bin/sh\necho "$@" >> "%s"\n' "$WITNESS" > "$D/shim/claude-accounts"
  cp "$D/shim/claude-accounts" "$HOME/.claude/bin/claude-accounts"
  chmod +x "$D/shim/claude-accounts" "$HOME/.claude/bin/claude-accounts"
}

@test "12 POSITIVE CONTROL: the witness fixture CAN detect a claude-accounts call" {
  plant_witness
  # If THIS fails, test 13 proves nothing whatsoever — it becomes a check that cannot fail.
  # Both planted paths are exercised, because test 13 claims both are covered.
  PATH="$D/shim:$PATH" claude-accounts --readout >/dev/null 2>&1 || true
  [ -s "$WITNESS" ] || { echo "witness blind to a PATH call — test 13 would be vacuous"; false; }
  rm -f "$WITNESS"
  "$HOME/.claude/bin/claude-accounts" --readout >/dev/null 2>&1 || true
  [ -s "$WITNESS" ] || { echo "witness blind to an absolute-path call — half of test 13 is vacuous"; false; }
}

@test "13 the hook forks NO claude-accounts — it is a file read, never a 5.33s sweep" {
  plant_witness; mk_board
  PATH="$D/shim:$PATH" run emit startup
  [ "$status" -eq 0 ]
  [ ! -s "$WITNESS" ] || { echo "HOOK CALLED claude-accounts: $(cat "$WITNESS")"; false; }
  # ...and on the degrade path too, where a "well, just fetch it live then" fallback is tempting
  # and would put the 5.33s call on exactly the sessions that have no cached board to fall back on.
  rm -f "$CC_ACCOUNTS_BOARD"
  PATH="$D/shim:$PATH" run emit startup
  [ ! -s "$WITNESS" ] || { echo "hook called claude-accounts on the MISSING-board path"; false; }
}

@test "14 the hook is fast enough to be nowhere near its 5s timeout" {
  mk_board
  local t0 t1
  t0="$(python3 -c 'import time;print(time.time())')"
  emit startup
  t1="$(python3 -c 'import time;print(time.time())')"
  # 1s is a deliberately loose ceiling: measured cost is ~65ms (two jq forks). The bar this
  # defends is the 5.33s inline call, not a performance-regression budget.
  run python3 -c "import sys;sys.exit(0 if float(sys.argv[2])-float(sys.argv[1]) < 1.0 else 1)" "$t0" "$t1"
  [ "$status" -eq 0 ] || { echo "hook took >1s — check it is not calling claude-accounts"; false; }
}

# ── the narrow renderer ───────────────────────────────────────────────────────────────────────

# Fixture rows injected at the documented source-patch anchor (see the note in bin/claude-accounts
# above `rows, wj, cached, prev = get_data(...)`).
#
# THE NAME IS 61 CHARACTERS ON PURPOSE, and the first draft's 20 was a vacuous fixture: at 20 the
# name column overruns its 13 by 7, taking a ~56-cell row to ~63 — still inside the budget. So the
# case would have passed with the truncation deleted, i.e. it tested nothing about the mechanism it
# names. At 61 an untruncated row is ~104 cells and the budget is the only thing holding it, which
# is what test 21 then proves by removing it.
NARROW_FIXTURE='
rows = [
  {"acct": "next-quaternary-extremely-long-account-name-for-width-testing",
   "auth": "ok", "launcher": "claude4", "k": 1,
   "session_pct": 11.0, "weekly_pct": 46.0, "fable_pct": 18.0,
   "session_reset_h": 3.5, "weekly_reset_h": 100.4, "login_expires_h": 447.0,
   "session_reset_at": "2126-01-01T00:00:00+00:00", "weekly_reset_at": "2126-01-05T00:00:00+00:00",
   "login_expires_at": "2126-02-01T00:00:00+00:00", "stale_quota": True},
  {"acct": "next2", "auth": "ok", "launcher": "claude2", "k": 0,
   "session_pct": 6.0, "weekly_pct": 48.0, "fable_pct": 21.0,
   "session_reset_h": 2.0, "weekly_reset_h": 83.5, "login_expires_h": 636.0,
   "session_reset_at": "2126-01-01T00:00:00+00:00", "weekly_reset_at": "2126-01-04T00:00:00+00:00",
   "login_expires_at": "2126-03-01T00:00:00+00:00"},
]
    wj, cached, prev = {}, True, None'

render_narrow() {  # → the board text on stdout
  python3 - "${CA_BIN}" "$@" <<PY
import subprocess, sys
src = open(sys.argv[1]).read()
anchor = "rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)"
new = src.replace(anchor, '''$NARROW_FIXTURE'''.strip())
assert new != src, "source patch did not apply — the anchor moved (see the note at that line)"
p = subprocess.run([sys.executable, "-c", new] + sys.argv[2:], capture_output=True, text=True)
sys.stderr.write(p.stderr)
sys.stdout.write(p.stdout)
sys.exit(p.returncode)
PY
}

# Display CELLS, not characters, and deliberately re-implemented here rather than imported from
# the subject: a width check that calls the subject's own measure agrees with it by construction
# and would certify a broken one.
WIDTH_CHECK='
import sys, unicodedata
bad = []
for i, l in enumerate(sys.stdin.read().splitlines(), 1):
    w = sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in l)
    if w > 76: bad.append((i, w, l))
for i, w, l in bad: print(f"BREACH line {i}: {w} cells: {l!r}")
sys.exit(1 if bad else 0)'

@test "15 narrow: every rendered row is <=76 display cells, with long account names" {
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  run bash -c "cd '$REPO' && $(declare -f render_narrow); NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --readout --narrow --max-wait 0 | python3 -c '$WIDTH_CHECK'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "16 narrow: the desk pick is on the board — it is what the next bare \`claude\` will do" {
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  run bash -c "cd '$REPO' && $(declare -f render_narrow); NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --readout --narrow --max-wait 0"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"desk (bare claude)"* ]] || { echo "no desk line: $output"; false; }
  # the row marker too — the table must agree with the footer about which account it is
  [[ "$output" == *"➤"* ]]
}

@test "17 narrow: the * inherited-reading suffix survives into the board" {
  # C: a board that silently prints stale numbers is worse than no board. The fixture's first row
  # is stale_quota=True, so its percents must carry `*` here exactly as they do in the chat table.
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  run bash -c "cd '$REPO' && $(declare -f render_narrow); NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --readout --narrow --max-wait 0"
  [[ "$output" == *"11%*"* ]] || { echo "stale suffix lost in narrow: $output"; false; }
}

@test "18 --readout WITHOUT --narrow is untouched — narrow is a mode, not a rewrite" {
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  run bash -c "cd '$REPO' && $(declare -f render_narrow); NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --readout --max-wait 0"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"| account | live | 5h used |"* ]] \
    || { echo "the markdown table header changed: $output"; false; }
}

@test "19 --keepwarm writes the board it claims to write" {
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  export CC_ACCOUNTS_BOARD="$D/produced.txt"; rm -f "$CC_ACCOUNTS_BOARD"
  run bash -c "cd '$REPO' && $(declare -f render_narrow); NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --keepwarm"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the verb REPORTS the path — a producer that silently failed would still exit 0
  [[ "$output" == *"board=$CC_ACCOUNTS_BOARD"* ]] || { echo "keepwarm did not report the board: $output"; false; }
  [ -s "$CC_ACCOUNTS_BOARD" ] || { echo "no board on disk"; false; }
  run bash -c "cat '$CC_ACCOUNTS_BOARD' | python3 -c '$WIDTH_CHECK'"
  [ "$status" -eq 0 ] || { echo "the PRODUCED board breaches the budget: $output"; false; }
  # END-TO-END, and this is the case that would catch the two halves disagreeing about the path:
  # the producer wrote a board, the hook — which shares no code with it — must find and surface it.
  emit startup
  run jqv '.systemMessage'
  [[ "$output" == *"desk (bare claude)"* ]] || { echo "hook did not surface the produced board: $output"; false; }
}

@test "20 the board file is derived from cache_file, so a fixtured run cannot clobber the live one" {
  # Hermeticity, and it is not theoretical: without this the suite would overwrite the operator's
  # real /tmp/claude-accounts-board.txt with fixture accounts, on a surface nobody re-reads.
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  unset CC_ACCOUNTS_BOARD
  run bash -c "cd '$REPO' && CLAUDE_ACCOUNTS_JSON='$D/acct.json' python3 -c '
import importlib.machinery, importlib.util, os, sys
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    \"ca\", importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"])))
importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"]).exec_module(ca)
cfg = ca.load_cfg(need_claude_bin=False)
p = ca.board_path(cfg)
assert p.startswith(os.environ[\"D\"]), p
assert \"/tmp/claude-accounts-board.txt\" != p, p
print(\"OK\", p)'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "21 MUTANT: deleting the name truncation breaches the budget (so test 15 is not vacuous)" {
  export CLAUDE_ACCOUNTS_JSON="$D/acct.json"; mk_cfg
  # _clip is what keeps the 61-char fixture name inside its 13-cell column. Neutered to identity,
  # the row must overrun 76 — if it does not, test 15 is not measuring the truncation at all and
  # a regression there would land green.
  python3 - "$CA_BIN" "$D/nomut.py" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = "def _clip(s, n):"
assert old in src, "the truncation helper moved — this mutant no longer applies"
new = src.replace(old, "def _clip(s, n):\n    return s\n\ndef _clip_disabled(s, n):", 1)
assert new != src
open(sys.argv[2], "w").write(new)
PY
  run bash -c "cd '$REPO' && $(declare -f render_narrow); \
    CA_BIN='$D/nomut.py' NARROW_FIXTURE='$NARROW_FIXTURE' \
    render_narrow --readout --narrow --max-wait 0 | python3 -c '$WIDTH_CHECK'"
  [ "$status" -ne 0 ] || { echo "no breach without truncation — test 15 is vacuous"; false; }
  [[ "$output" == *BREACH* ]] || { echo "expected a width breach, got: $output"; false; }
}

# A minimal hermetic accounts.json: no network endpoints that resolve, cache inside the sandbox.
mk_cfg() {
  python3 - "$D/acct.json" "$D/cache.json" "$REPO/accounts.json" <<'PY'
import json, sys
out, cache, real = sys.argv[1:4]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  # DERIVED from the real SSOT, never hand-copied — a hand-copied block silently diverges the
  # moment a constant is added, and the suite then certifies math production never runs.
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [
    {"name": "next-quaternary-extremely-long-account-name-for-width-testing",
     "config_dir": "/tmp/ca-board-test-nonexistent-a",
     "launcher": "claude4", "email": "a@example.com", "mailbox": "a@example.com", "dia_profile": "A"},
    {"name": "next2", "config_dir": "/tmp/ca-board-test-nonexistent-b",
     "launcher": "claude2", "email": "b@example.com", "mailbox": "b@example.com", "dia_profile": "B"},
  ],
}, open(out, "w"))
PY
}
