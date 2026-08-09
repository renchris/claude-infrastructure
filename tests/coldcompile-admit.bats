#!/usr/bin/env bats
# coldcompile-admit.sh + cc-ignition-gate — the Wave C cold-compile admission serializer (§S6.5).
#
# A PreToolUse hook signals its effect through the JSON it prints, NOT through its exit code: every
# path exits 0 by contract (a hook failure must never block a tool), so "did nothing" and "did
# something" are distinguished ONLY by stdout. Every assertion below keys on the emitted envelope,
# and "untouched" always means EMPTY OUTPUT — never exit status.
#
# The gate is the same shape in reverse: it ALWAYS exits 0 (fail-open is its hard contract), so its
# verdict lives in the `verdict=` token on stderr and in the telemetry row, never in $?. A test that
# asserted on the gate's exit code would pass for every possible implementation, including one that
# does nothing at all.
#
# Hermetic: $HOME is fixtured, the process census comes from a FIXTURE FILE via CC_IGNITION_PS_FILE,
# and every table fixture lives in $BATS_TEST_TMPDIR. Two things are deliberately tested against the
# REAL shipped artifacts instead, because they ARE the deliverable and a fixture would test nothing
# about them: config/coldcompile.patterns (its three rows and their command-position anchoring) and
# the disjointness of the two shipped hooks.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/coldcompile-admit.sh"
  GATE="$REPO/bin/cc-ignition-gate"
  QOS="$REPO/hooks/qos-rewrite.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"          # never read the operator's live ~/
  export CC_IGNITION_LOG="$D/gate.jsonl"
  export CC_COLDCOMPILE_GATE="$GATE"               # pin the gate: the emitted string is asserted
}

run_hook() { # $1 = the agent's command
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK"
}
run_hook_at() { # $1 = hook path, $2 = command  (for mutants and for the qos disjointness probe)
  jq -n --arg c "$2" '{tool_input:{command:$c}}' | bash "$1"
}
cmd_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null; }

# A process-census fixture. Rows are `<pid> <etime> <comm> <args…>`, exactly what
# `ps -Awwo pid=,etime=,comm=,args=` prints.
ps_fixture() { # $1 = name, then whole rows
  local out="$D/$1.ps"; shift
  : > "$out"
  while [ "$#" -gt 0 ]; do printf '%s\n' "$1" >> "$out"; shift; done
  printf '%s' "$out"
}
NODE=/usr/local/bin/node
FRESH_NEXT='  123    00:15 /usr/local/bin/node /usr/local/bin/node /repo/node_modules/.bin/next dev -p 3000'
OLD_SERVER='  124 01:02:03 /usr/local/bin/node next-server (v16.2.6)'
A_SHELL='  200    05:00 /bin/zsh /bin/zsh -lc echo hi'

# ── the hook: coverage over the shapes the corpus actually contains ────────────────────────────
# 231 of the 232 real ignition commands in ~/.claude/logs/bash-commands.log{,.gz} are COMPOUND, so
# these are not hypotheticals — each is a live corpus shape.

@test "01 compound cd && backgrounded next dev is gated, original preserved verbatim" {
  run run_hook 'cd /repo && (npx next dev -p 3717 > /tmp/d.log 2>&1 &) ; sleep 25'
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$GATE --class next-dev ; cd /repo && (npx next dev -p 3717 > /tmp/d.log 2>&1 &) ; sleep 25" ]
}

@test "02 leading VAR= assignment is gated — the one SIMPLE ignition shape in the corpus" {
  run run_hook 'PW_BASE_URL=http://localhost:3862 pnpm design:gate'
  [ "$(cmd_of "$output")" = "$GATE --class pkg-script ; PW_BASE_URL=http://localhost:3862 pnpm design:gate" ]
}

@test "03 nohup/env/setsid wrappers do not hide the ignition" {
  run run_hook 'nohup env PORT=3950 pnpm dev >/tmp/bs-dev.log 2>&1 &'
  [ -n "$(cmd_of "$output")" ]
  run run_hook '(setsid env PORT=3950 pnpm dev > /tmp/w7-dev.log 2>&1 &)'
  [ -n "$(cmd_of "$output")" ]
}

@test "04 a multi-line command is gated, and the gate is a separate statement on line 1" {
  local c
  c="$(printf 'cd /repo\nexport PATH=/x:$PATH\npnpm build > /tmp/b.log 2>&1')"
  run run_hook "$c"
  [ "$(cmd_of "$output")" = "$GATE --class pkg-script ; $c" ]
}

@test "05 the separator is ';' and never '&&' — a comment-leading command must stay valid shell" {
  # `gate && # …` is an && with no right operand: a syntax error that would break the agent's
  # command outright. `gate ; # …` is fine. The emitted line is handed to bash -n to prove it.
  local c out
  c="$(printf '# start the dev server\ncd /repo && pnpm dev &')"
  run run_hook "$c"
  out="$(cmd_of "$output")"
  [ -n "$out" ]
  printf '%s' "$out" | bash -n
}

# ── the hook: what it must NOT touch ───────────────────────────────────────────────────────────

@test "06 a mention is not a run — command-position anchoring holds" {
  # COMPOUND mentions deliberately. A SIMPLE `git grep …` would be declined by the qos-disjointness
  # rule before the table is ever consulted, so it would pass this case without saying one word
  # about the anchoring — the vacuous shape case 07 exists to rule out.
  run run_hook 'cd /repo && git grep -n "pnpm dev" -- docs'
  [ -z "$(cmd_of "$output")" ]
  run run_hook 'cd /repo && echo "=== does next dev write into .next root? ==="'
  [ -z "$(cmd_of "$output")" ]
}

@test "07 MUTATION CONTROL — a word-anchored table DOES gate a mention (the check can fail)" {
  # Without this the case above passes vacuously: a hook that emitted nothing ever would satisfy it.
  # The mutant is the pre-calibration table shape — word-anchored instead of command-anchored — and
  # it must convict the SAME command case 06 acquits. The prose mention is the one the control can
  # reach: a QUOTED `"pnpm dev"` is not preceded by whitespace, so even the loose ERE misses it,
  # and a control built on it would have been inert. This is verbatim a corpus row.
  local t="$D/loose.patterns"
  printf 'next-dev\t%s\n' '(^|[[:space:]])(npx[[:space:]]+)?next[[:space:]]+dev([[:space:]]|$)' > "$t"
  CC_COLDCOMPILE_PATTERNS="$t" run run_hook 'cd /repo && echo "=== does next dev write into .next root? ==="'
  [ -n "$(cmd_of "$output")" ]
}

@test "08 next start is not an ignition — it serves a prebuilt app and compiles nothing" {
  run run_hook 'cd /repo && next start -p 3000'
  [ -z "$(cmd_of "$output")" ]
}

@test "09 already gated ⇒ never gated twice" {
  run run_hook "$GATE --class next-dev ; cd /repo && pnpm dev"
  [ -z "$(cmd_of "$output")" ]
}

@test "10 kill switch, empty table and empty gate seam each disable the hook verbatim" {
  CC_COLDCOMPILE_ADMIT=off run run_hook 'cd /repo && pnpm dev'
  [ -z "$(cmd_of "$output")" ]
  CC_COLDCOMPILE_PATTERNS= run run_hook 'cd /repo && pnpm dev'
  [ -z "$(cmd_of "$output")" ]
  CC_COLDCOMPILE_GATE= run run_hook 'cd /repo && pnpm dev'
  [ -z "$(cmd_of "$output")" ]
}

@test "11 a gate that is not executable is never named — a bad rewrite costs the agent's command" {
  CC_COLDCOMPILE_GATE="$D/does-not-exist" run run_hook 'cd /repo && pnpm dev'
  [ -z "$(cmd_of "$output")" ]
}

@test "12 a class carrying shell metacharacters is refused, not interpolated" {
  local t="$D/evil.patterns"
  printf '%s\t%s\n' 'x; rm -rf /' '(^|[;&|(])[[:space:]]*pnpm[[:space:]]+dev' > "$t"
  CC_COLDCOMPILE_PATTERNS="$t" run run_hook 'cd /repo && pnpm dev'
  [ -z "$(cmd_of "$output")" ]
}

# ── disjointness with qos-rewrite.sh, observed on the SHIPPED artifacts ────────────────────────

@test "13 no command makes BOTH shipped hooks emit — and the probe is not vacuous" {
  # Two PreToolUse hooks both emitting updatedInput for one call have no documented resolution on
  # 2.1.220, so the design refuses to depend on one. This asserts the property by RUNNING both
  # shipped hooks, rather than by re-implementing either one's rule.
  #
  # THE POSITIVE CONTROL IS THE POINT. qos-rewrite fails open when taskpolicy(8) or cc-bats is
  # missing, so a bare "neither emitted" sweep would pass on a box where qos can never emit at all
  # — a non-verdict wearing a pass's clothes. `shellcheck …` is a row in the SHIPPED
  # config/qos-batch.patterns and a simple command, so qos must emit for it; if it does not, this
  # environment cannot answer the question and the test says so.
  local ctl
  ctl="$(cmd_of "$(run_hook_at "$QOS" 'shellcheck scripts/x.sh')")"
  [ -n "$ctl" ] || skip "qos-rewrite cannot emit here (no taskpolicy) — disjointness is untestable"
  [ -z "$(cmd_of "$(run_hook "shellcheck scripts/x.sh")")" ]

  local c
  for c in 'cd /repo && (npx next dev -p 3717 > /tmp/d.log 2>&1 &) ; sleep 25' \
           'PW_BASE_URL=http://localhost:3862 pnpm design:gate' \
           'nohup env PORT=3950 pnpm dev >/tmp/bs.log 2>&1 &' \
           'pnpm dev' \
           'npm install' \
           'du -sh /repo' \
           'uv run pytest -m load'; do
    local a b
    a="$(cmd_of "$(run_hook "$c")")"
    b="$(cmd_of "$(run_hook_at "$QOS" "$c")")"
    if [ -n "$a" ] && [ -n "$b" ]; then
      echo "BOTH hooks emitted for: $c"; false
    fi
  done
}

# ── the gate: the predicate ────────────────────────────────────────────────────────────────────

@test "20 an ignition younger than the settle window is an incumbent ⇒ busy" {
  local f; f="$(ps_fixture busy "$FRESH_NEXT" "$OLD_SERVER" "$A_SHELL")"
  CC_IGNITION_PS_FILE="$f" run bash "$GATE" --class next-dev --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=busy"* ]] || false
  [[ "$output" == *"incumbent pid=123"* ]]
}

@test "21 a long-lived next-server is NOT an incumbent — the burst is over, the lock must not be" {
  local f; f="$(ps_fixture clear "$OLD_SERVER" "$A_SHELL")"
  CC_IGNITION_PS_FILE="$f" run bash "$GATE" --class next-dev --check
  [ -z "$output" ]
  [ "$(jq -r 'select(.verdict=="admit") | .reason' "$CC_IGNITION_LOG" | tail -1)" = "clear node_n=1" ]
}

@test "22 MUTATION CONTROL — a settle window of 0 makes the incumbent invisible" {
  # Pins that case 20 is detecting the AGE test and not merely the presence of a next-shaped row.
  local f; f="$(ps_fixture busy2 "$FRESH_NEXT" "$A_SHELL")"
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_SETTLE_S=0 run bash "$GATE" --check
  [ -z "$output" ]
}

@test "23 a process that merely MENTIONS a cold compile in its argv is not an incumbent" {
  # This fleet's argv carries whole briefs, and this gate is prefixed onto the commands of the very
  # sessions that talk about it — an unanchored match would deadlock the fleet against its own
  # vocabulary (memory: pgrep-f-matches-agent-briefs). Two rows, two different defences:
  #   the bash row is caught by ARGV0 ANCHORING alone (argv[0] is not node/next-shaped);
  #   the claude row is caught by anchoring AND by the argv0 claude exclusion.
  local f
  f="$(ps_fixture brief \
      '  301    00:05 /bin/bash bash -lc echo starting next dev now' \
      '  300    00:05 /Users/x/.claude/bin/claude claude --prompt run next dev cold compile now')"
  CC_IGNITION_PS_FILE="$f" run bash "$GATE" --check
  [ -z "$output" ]
}

@test "24 MUTATION CONTROL — an UNANCHORED ignition ERE convicts that same bash row" {
  # Without this, case 23 passes for any gate that never fires. The mutant is the substring match
  # the header refuses. It is aimed at the BASH row on purpose: the claude row is ALSO excluded by
  # argv0, so a mutant aimed there would be masked by the other defence and prove nothing about
  # anchoring (the first draft of this control did exactly that and reported a false negative).
  local m="$D/gate-unanchored"
  sed -e "s|^IGNITION_ERE='.*'$|IGNITION_ERE='next[[:space:]]+dev'|" "$GATE" > "$m"
  grep -q "IGNITION_ERE='next\[\[:space:\]\]+dev'" "$m"     # the mutant must have APPLIED
  local f
  f="$(ps_fixture brief2 '  301    00:05 /bin/bash bash -lc echo starting next dev now')"
  CC_IGNITION_PS_FILE="$f" run bash "$m" --check
  [[ "$output" == *"verdict=busy"* ]]
}

@test "26 this fleet's own sessions never inflate the burst census" {
  # The argv0 claude exclusion's real load-bearing job is TERM 2, not term 1: a `claude` session
  # whose comm is node would otherwise be counted as a node process, and 150 resident sessions
  # would hold the gate permanently busy at any sane BURST_N — the gate would strand the fleet at
  # exactly the residency it exists to make possible.
  local f="$D/fleet.ps" i
  : > "$f"
  for i in 1 2 3 4 5; do
    printf '  %d 30:00 %s %s /Users/x/.claude/bin/claude-next --prompt work\n' $((500+i)) "$NODE" /Users/x/.claude/bin/claude >> "$f"
  done
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_BURST_N=2 run bash "$GATE" --check
  [ -z "$output" ]
  [ "$(jq -r 'select(.verdict=="admit") | .reason' "$CC_IGNITION_LOG" | tail -1)" = "clear node_n=0" ]
}

@test "25 the burst term fires on node-process count alone, with no incumbent present" {
  # Term 2 exists because term 1 is blind to an OLD next-server re-storming on mass invalidation.
  local f="$D/burst.ps" i
  : > "$f"; for i in 1 2 3 4 5; do printf '  %d 10:00 %s %s /srv/w.js\n' $((400+i)) "$NODE" "$NODE" >> "$f"; done
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_BURST_N=3 run bash "$GATE" --check
  [[ "$output" == *"burst node_n=5 limit=3"* ]] || false
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_BURST_N=9 run bash "$GATE" --check
  [ -z "$output" ]
}

# ── the gate: fail-open, always, and never silently ────────────────────────────────────────────

@test "30 an unreadable census ADMITS — fail-open is the hard contract" {
  CC_IGNITION_PS_FILE="$D/nope.ps" run bash "$GATE" --check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "31 the wait budget running out ADMITS, and says so with a parseable verdict token" {
  # The one outcome that must never be silent: it is the residual the compressor sentinel holds.
  local f; f="$(ps_fixture stuck "$FRESH_NEXT")"
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_WAIT_S=2 CC_IGNITION_INTERVAL_S=1 run bash "$GATE" --class next-dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=admit-timeout"* ]] || false
  [ "$(jq -r 'select(.verdict=="admit-timeout") | .waited_s' "$CC_IGNITION_LOG" | tail -1)" = "2" ]
}

@test "32 a cleared incumbent releases the wait — admit-after-wait, not admit-timeout" {
  local f; f="$(ps_fixture flip "$FRESH_NEXT")"
  ( sleep 2; printf '%s\n' "$A_SHELL" > "$f" ) &
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_WAIT_S=20 CC_IGNITION_INTERVAL_S=1 run bash "$GATE" --class next-dev
  wait
  [[ "$output" == *"verdict=admit-after-wait"* ]]
}

@test "33 the kill switch costs nothing — no census, no telemetry row" {
  local f; f="$(ps_fixture off "$FRESH_NEXT")"
  CC_IGNITION_GATE=off CC_IGNITION_PS_FILE="$f" run bash "$GATE" --check
  [ -z "$output" ]
  [ ! -s "$CC_IGNITION_LOG" ]
}

@test "34 a non-numeric seam falls back to its default rather than breaking the caller" {
  local f; f="$(ps_fixture nan "$FRESH_NEXT")"
  CC_IGNITION_PS_FILE="$f" CC_IGNITION_SETTLE_S=abc CC_IGNITION_WAIT_S=xyz run bash "$GATE" --check
  [[ "$output" == *"verdict=busy"* ]]      # default settle=90 ⇒ the 15 s incumbent still counts
}

@test "35 telemetry stays slurpable when a reason would carry quotes" {
  # ONE malformed line aborts a downstream `jq -rs` slurp, which then reads as "no records" and
  # silently flips a census green. Every field is jq-encoded for exactly this.
  local f; f="$(ps_fixture q "$OLD_SERVER")"
  CC_IGNITION_PS_FILE="$f" bash "$GATE" --class 'next-dev' --check >/dev/null 2>&1
  run jq -rs 'length' "$CC_IGNITION_LOG"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ── the shipped table is itself a deliverable ─────────────────────────────────────────────────

@test "40 every shipped row is TAB-separated, class-clean, and a valid ERE" {
  local t="$REPO/config/coldcompile.patterns" line f1 ere n=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    f1=${line%%$'\t'*}; ere=${line#*$'\t'}
    [ "$f1" != "$line" ]                                   # a TAB, not spaces
    printf '%s' "$f1" | grep -qE '^[A-Za-z0-9-]+$'
    printf 'x' | grep -qE "$ere" || true                   # compiles (match or not, never an error)
    [ "$?" -le 1 ]
    n=$((n + 1))
  done < "$t"
  [ "$n" -eq 3 ]
}
