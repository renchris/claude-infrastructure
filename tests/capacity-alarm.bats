#!/usr/bin/env bats
# capacity-alarm.bats — row 13 M6 (MACHINE_CAPACITY_V2.md §4). The ceiling alarm.
#
# The properties that matter, in priority order:
#   1. A broken instrument reports NO-DATA, never a false OK. ("could not measure" != "fine")
#   2. Every rung is reachable — proven by a positive control, not asserted.
#   3. It NEVER waits, sleeps, or polls (R1: a shedder that waits amplifies; the landed
#      capacity_gate is the cautionary case at REFUSE 10/10).
#   4. The session counter actually sees the population (pgrep silently returned 0 here).
#
# `|| false` on every non-final [[ ]]/[ ] chain — errexit-exempt assertions are DEAD (memory
# bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  ALARM="$REPO/scripts/capacity-alarm.sh"
  # Hermeticity ratchet: the alarm's default log lives under $HOME.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_CAP_LOG="$BATS_TEST_TMPDIR/cap.jsonl"
}

@test "(i) selftest GREEN — all four rungs + NO-DATA are reachable (positive control, R6)" {
  run /bin/bash "$ALARM" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ "selftest GREEN" ]] || false
  # each rung must be named, so a silently-unreachable rung cannot hide behind an aggregate pass
  [[ "$output" =~ "→ OK" ]] || false
  [[ "$output" =~ "→ WARN" ]] || false
  [[ "$output" =~ "→ ALARM" ]] || false
  [[ "$output" =~ "→ NO-DATA" ]] || false
}

@test "(ii) healthy box → OK with rc 0 and a numeric headroom" {
  run /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  # headroom must be a NUMBER, never null — null means the instrument silently failed
  ! [[ "$output" =~ \"headroom_gb\":null ]] || false
}

@test "(iii) forced WARN → rc 1" {
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
}

@test "(iv) forced ALARM → rc 2, and ALARM outranks WARN" {
  run env CC_CAP_ALARM_GB=999999 CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
}

@test "(v) THE LOAD-BEARING ONE — a broken instrument reports NO-DATA (rc 3), never a false OK" {
  # A capacity alarm that reads OK when it cannot measure is worse than no alarm: it actively
  # asserts safety. This is why the verdict set has four members rather than a boolean.
  run env CC_CAP_PYTHON=/nonexistent/python /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"OK\" ]] || false
}

@test "(vi) POSITIVE CONTROL for (v): the SAME code path yields OK with a working instrument" {
  # Without this, (v) could pass because the script always says NO-DATA.
  run /bin/bash "$ALARM" --json --no-append
  [[ "$output" =~ \"verdict\":\"OK\" ]] || [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
}

# ── the session census (M9a) — a POPULATION CONTROL, not a tautology ─────────────────────────────
#
# WHAT WAS WRONG WITH THE TEST THIS REPLACES. It computed `expected` with the IDENTICAL grep the
# subject used, then asserted the subject matched it. That is a tautology: it passes for EVERY
# possible grep, including the wrong one it was actually running (one pid family of two, 13 of 31
# real trees). A census test must know the right answer INDEPENDENTLY of the census — so the
# population is synthetic, injected through a `ps` stub, and the expected count is a HAND-WRITTEN
# literal that a reader can verify by counting the fixture rows themselves.
#
# THE FIXTURE encodes all three measured defects at once (see the subject's census() prose):
#   3 × claude.exe roots            → counted
#   2 × .bin/claude roots           → counted   (the family the incumbent could not see at all)
#   2 × .bin/claude in-family kids  → NOT counted (children of an already-counted tree)
#   2 × `bash cc-close-attrib …/.bin/claude` → NOT counted (argv MENTIONS a claude path; measured
#       live as 23 such procs inflating a whole-argv grep from 60 to 83). One of them is given
#       ppid 1 deliberately: it proves a PPID-in-family subtraction ALONE cannot exclude it, and
#       only matching at the command position can.
#   2 × unrelated procs             → NOT counted
# ⇒ 5 trees, 3 exe + 2 bin. Hand-written. Never computed from the subject's pattern.
mk_stubs() {
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  cat > "$STUBS/population.txt" <<'POP'
  101     1 /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id a1
  102     1 /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id a2
  103     1 /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id a3
  201     1 /U/.claude/node_modules/.bin/claude --permission-mode default --model claude-opus-5
  202     1 /U/.claude/node_modules/.bin/claude --permission-mode auto --model claude-opus-5
  203   201 /U/.claude/node_modules/.bin/claude --child-of-201-same-family
  204   103 /U/.claude/node_modules/.bin/claude --child-of-103-other-family
  301     1 bash /U/.claude/bin/cc-close-attrib /U/.claude/node_modules/.bin/claude --mentions-only
  302   999 bash /U/.claude/bin/cc-close-attrib /U/.claude/node_modules/@anthropic-ai/claude-code/bin/claude.exe
  401     1 /usr/sbin/mDNSResponder
  402     1 /Applications/iTerm.app/Contents/MacOS/iTerm2
POP
  cat > "$STUBS/rss.txt" <<'RSS'
  501 2097152 iTerm2
  502 1048576 WindowServer
  503  524288 node
RSS
  cat > "$STUBS/ps" <<STUB
#!/bin/bash
case "\$*" in
  *rss*) cat "$STUBS/rss.txt" ;;
  *)     cat "$STUBS/population.txt" ;;
esac
STUB
  chmod +x "$STUBS/ps"
}

# top(1) stub — <mb> for the largest proc, so the outlier rung is exercised deterministically instead
# of depending on whatever the real box happens to be running.
#
# The two trailing rows are kept DELIBERATELY SMALL. The first draft gave them realistic sizes
# (1676M WindowServer) and they silently outranked the parameter, so `mk_top_stub 900` produced a max
# of 1676 — the fixture was not testing the number it claimed to. Rows descend, as `top -o mem` emits.
mk_top_stub() { # $1 = MB for the largest process (must dominate the fixed rows below)
  cat > "$STUBS/top" <<TOP
#!/bin/bash
echo 'Processes: 700 total, 4 running'
echo ''
echo 'PID    MEM   COMMAND'
echo '501    ${1}M big-proc'
echo '502    64M small-two'
echo '503    32M small-three'
TOP
  chmod +x "$STUBS/top"
}

@test "(vii) THE POPULATION CONTROL — a stubbed ps yields a HAND-WRITTEN 5 trees, both families" {
  mk_stubs
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -ne 64 ] || false
  # 5 is written here by hand from the fixture above — NOT derived from the subject's own matcher.
  # The leading comma is load-bearing: `"sessions":` also occurs as the TAIL of
  # `"est_room_sessions":`, so an unanchored match can silently assert against the wrong field.
  [[ "$output" =~ ,\"sessions\":5, ]] || false
  [[ "$output" =~ ,\"sessions_exe\":3, ]] || false
  [[ "$output" =~ ,\"sessions_binclaude\":2, ]] || false
}

@test "(vii-b) RED CONTROL — both rejected matchers give provably WRONG answers on this fixture" {
  # Without this, (vii) could pass for a census that is wrong in some other way, or for a fixture so
  # bland that every implementation satisfies it. So both matchers this row rejected are RUN against
  # the fixture and shown to disagree with the hand-written 5 — that is what makes it discriminating.
  mk_stubs
  # (a) the incumbent: ONE family, whole-argv. Wrong TWICE over — it misses the 2 .bin/claude roots
  #     AND counts row 302, a `bash cc-close-attrib` wrapper that merely names a claude.exe path.
  one_family="$(PATH="$STUBS:$PATH" ps -eo args | grep -cE 'claude-code/bin/claude\.exe' || true)"
  [ "$one_family" -eq 4 ] || false
  # (b) both families but still whole-argv: 9 — the 4 extras are the 2 mention-only wrappers and the
  #     2 in-family children. This is the matcher the brief prescribed; it overcounts by 80%.
  whole_argv="$(PATH="$STUBS:$PATH" ps -eo args \
                 | grep -cE 'claude-code/bin/claude\.exe|node_modules/\.bin/claude' || true)"
  [ "$whole_argv" -eq 9 ] || false
  # (c) and a PPID-in-family subtraction cannot rescue (b): row 301's parent is pid 1, so it survives.
  #     Only matching at the command position excludes it.
  [ "$one_family" -ne 5 ] || false
  [ "$whole_argv" -ne 5 ] || false
  # …the subject agrees with neither wrong answer.
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  ! [[ "$output" =~ ,\"sessions\":4, ]] || false
  ! [[ "$output" =~ ,\"sessions\":9, ]] || false
}

@test "(vii-c) live smoke — against the REAL box the census sees at least the one-family count" {
  # The stub proves the arithmetic; this proves the instrument is pointed at the real world. Stated as
  # an inequality on purpose: the two families are disjoint, so trees >= the single-family count
  # ALWAYS holds, while equality would be a flake every time a session starts or exits between the
  # two reads. Valid on a box with genuinely zero sessions too.
  floor="$(ps -eo args 2>/dev/null | grep -cE 'claude-code/bin/claude\.exe' || true)"
  run /bin/bash "$ALARM" --json --no-append
  [ "$status" -ne 64 ] || false
  got="$(printf '%s\n' "$output" | sed -n 's/.*[,{]"sessions":\([0-9]*\),.*/\1/p')"
  [ -n "$got" ] || false
  [ "$got" -ge "$floor" ] || false
}

@test "(vii-d) the disjoint-family invariant holds on the real box: trees == exe + bin" {
  # A miscount that double-counts or drops a family breaks this sum even when each number alone looks
  # plausible. Cheap, and it is the one assertion a plausible-looking wrong census cannot satisfy.
  run /bin/bash "$ALARM" --json --no-append
  t="$(printf '%s\n' "$output" | sed -n 's/.*[,{]"sessions":\([0-9]*\),.*/\1/p')"
  e="$(printf '%s\n' "$output" | sed -n 's/.*[,{]"sessions_exe":\([0-9]*\),.*/\1/p')"
  b="$(printf '%s\n' "$output" | sed -n 's/.*[,{]"sessions_binclaude":\([0-9]*\),.*/\1/p')"
  [ -n "$t" ] || false
  [ -n "$e" ] || false
  [ -n "$b" ] || false
  [ "$t" -eq "$((e + b))" ] || false
}

# ── the two new rungs (M9-ext pressure level, M9b per-proc outlier) ───────────────────────────────

@test "(xix) kernel pressure level >=2 floors WARN on an otherwise-healthy box" {
  # The rung exists because the swap rung is LAGGING: 2.56 GB of swap was in use on 2026-07-26 and
  # the file was later reset by a reboot, so "swap 0" is not evidence the ceiling was never reached.
  # Headroom here is the real box's (healthy, ~27 GB), so a WARN can only come from the new rung.
  mk_stubs
  cat > "$STUBS/sysctl" <<'SC'
#!/bin/bash
case "$*" in
  *memorystatus_vm_pressure_level*) echo 2 ;;
  *swapusage*) echo 'vm.swapusage:  total = 4096.00M  used = 0.00M  free = 4096.00M' ;;
  *) exec /usr/sbin/sysctl "$@" ;;
esac
SC
  chmod +x "$STUBS/sysctl"
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
  [[ "$output" =~ \"pressure_level\":2 ]] || false
}

@test "(xx) kernel pressure level >=4 reaches ALARM" {
  mk_stubs
  cat > "$STUBS/sysctl" <<'SC'
#!/bin/bash
case "$*" in
  *memorystatus_vm_pressure_level*) echo 4 ;;
  *swapusage*) echo 'vm.swapusage:  total = 4096.00M  used = 0.00M  free = 4096.00M' ;;
  *) exec /usr/sbin/sysctl "$@" ;;
esac
SC
  chmod +x "$STUBS/sysctl"
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
}

@test "(xxi) an UNREADABLE pressure level is a SKIPPED rung, never NO-DATA" {
  # The distinction the header argues for: NO-DATA belongs to the one instrument the verdict cannot
  # exist without (vm_stat headroom). Demoting a fully-valid headroom verdict to NO-DATA because a
  # supplementary sysctl is missing on some macOS build would destroy a working alarm to report the
  # absence of a bonus. The level logs as null and the verdict stands.
  mk_stubs
  cat > "$STUBS/sysctl" <<'SC'
#!/bin/bash
case "$*" in
  *memorystatus_vm_pressure_level*) exit 1 ;;
  *swapusage*) echo 'vm.swapusage:  total = 4096.00M  used = 0.00M  free = 4096.00M' ;;
  *) exec /usr/sbin/sysctl "$@" ;;
esac
SC
  chmod +x "$STUBS/sysctl"
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"pressure_level\":null ]] || false
}

@test "(xxii) top_procs is on EVERY row, not only on a breach — the trend is the instrument" {
  # A leak is diagnosed across rows, not from one sample. If the rows only carried footprints when
  # something was already wrong, the log could never show the slope that precedes the breach.
  mk_stubs
  mk_top_stub 900
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false                       # OK row…
  [[ "$output" =~ \"top_procs\":\[\{\"pid\": ]] || false   # …still carries the rows
  [[ "$output" =~ big-proc ]] || false
  [[ "$output" =~ \"max_proc_gb\":0.88 ]] || false    # 900 MB, reported not gated
}

@test "(xxiii) a per-proc outlier above the floor reaches WARN and the PAGE NAMES the pid" {
  # Naming the process is the whole value of the rung — a page that says "something is large" sends
  # the operator hunting. 5000 MB = 4.88 GB against the 3 GB default floor.
  mk_stubs
  mk_top_stub 5000
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages-outlier"
  run env PATH="$STUBS:$PATH" CC_CAP_LOG="$BATS_TEST_TMPDIR/out.jsonl" /bin/bash "$ALARM" --quiet
  [ "$status" -eq 1 ] || false
  page="$CC_PAGES_DIR/capacity-alarm.page"
  [ -f "$page" ] || false
  run grep -c 'PER-PROC OUTLIER' "$page"
  [ "$output" -ge 1 ] || false
  run grep -c 'pid 501' "$page"
  [ "$output" -ge 1 ] || false
}

@test "(xxiv) the outlier rung CANNOT reach ALARM — it is a lead to follow, not a box-in-trouble" {
  # Alarm-not-gate, at the rung level: one big process must never be able to escalate the verdict to
  # the level that means the box is swapping. A regression that made it ALARM would break this.
  mk_stubs
  mk_top_stub 60000
  run env PATH="$STUBS:$PATH" /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 1 ] || false
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
  ! [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
}

@test "(xxv) top(1) unavailable → the ps fallback still yields footprints, never a silent blank" {
  # The fallback is deliberately a WORSE instrument (ps rss overcounts shared pages), used only when
  # the better one is missing. It can therefore only raise a false WARN, never hide a real one —
  # which is the right direction for a fallback to be wrong in.
  mk_stubs
  run env PATH="$STUBS:$PATH" CC_CAP_TOP=/nonexistent/top /bin/bash "$ALARM" --json --no-append
  [ "$status" -ne 64 ] || false
  [[ "$output" =~ \"top_procs\":\[\{\"pid\": ]] || false
  ! [[ "$output" =~ \"max_proc_gb\":null ]] || false
}

@test "(xxvi) the selftest names the NEW rungs too — census, pressure and outlier all controlled" {
  # (i) guards the four verdicts; this guards that the rungs ADDED here are equally positive-
  # controlled, so a future edit cannot make one unreachable behind an aggregate GREEN.
  run /bin/bash "$ALARM" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ pressure=\'2\' ]] || false
  [[ "$output" =~ pressure=\'4\' ]] || false
  [[ "$output" =~ maxproc=\'9\' ]] || false
  [[ "$output" =~ "disjoint-family sum" ]] || false
}

@test "(viii) R1 — never sleeps, polls, or waits on load (EXECUTABLE lines only)" {
  # TWO defects the first version of this test had, both caught by running it:
  #  1. It matched the script's OWN PROSE — the header says "NEVER refuses, blocks, queues, sleeps,
  #     or polls-until-clear", so the guard convicted the very documentation of the property it
  #     checks. Text is never evidence (memory detector-matching-its-own-skill-description). Comments
  #     are therefore stripped before matching.
  #  2. It passed VACUOUSLY against a tree with no capacity-alarm.sh at all, because grep on a
  #     missing file also returns non-zero. Hence the existence guard.
  [ -f "$ALARM" ] || false
  run bash -c "sed 's/#.*//' '$ALARM' | grep -nE '\\bsleep\\b|while.*load|until.*load|loadavg'"
  [ "$status" -ne 0 ] || false
}

@test "(ix) POSITIVE CONTROL for (viii): the comment-stripped grep still catches a real sleep" {
  # Proves the stripping did not defang the guard: a genuine executable sleep must still be found,
  # while the same word inside a comment must not.
  printf '# we never sleep here\nsleep 5\n' > "$BATS_TEST_TMPDIR/bait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/bait.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -eq 0 ] || false
  printf '# we never sleep here\n:\n' > "$BATS_TEST_TMPDIR/clean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/clean.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -ne 0 ] || false
}

@test "(x) kill switch CC_CAPACITY_ALARM=off → rc 0 and NO log write" {
  run env CC_CAPACITY_ALARM=off CC_CAP_LOG="$BATS_TEST_TMPDIR/ks.jsonl" /bin/bash "$ALARM" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$BATS_TEST_TMPDIR/ks.jsonl" ] || false
}

@test "(xi) appends a durable row by default; --no-append writes nothing" {
  log="$BATS_TEST_TMPDIR/a.jsonl"
  run env CC_CAP_LOG="$log" /bin/bash "$ALARM" --quiet
  [ -f "$log" ] || false
  run grep -c '"verdict":' "$log"
  [ "$output" -ge 1 ] || false
  log2="$BATS_TEST_TMPDIR/b.jsonl"
  run env CC_CAP_LOG="$log2" /bin/bash "$ALARM" --quiet --no-append
  [ "$status" -ne 64 ] || false          # non-vacuity: it really ran
  [ ! -f "$log2" ] || false
}

@test "(xii) unknown arg → rc 64, never a silent ignore" {
  run /bin/bash "$ALARM" --definitely-not-a-flag
  [ "$status" -eq 64 ] || false
}

@test "(xiii) it is an ALARM, not a GATE — the header says so and no refusal verb exists" {
  # The design boundary this row exists to protect: refusing spawns on a load proxy was measured to
  # be a permanent outage. Anything that turns this reporter into a gate must break a test.
  run grep -qE 'ALARM, NOT A GATE' "$ALARM"
  [ "$status" -eq 0 ] || false
  run grep -nE '^\s*(exit 9|refuse|REFUSE)\b' "$ALARM"
  [ "$status" -ne 0 ] || false
}

# ── the page channel (M6 wiring) ─────────────────────────────────────────────────────────────────

@test "(xiv) WARN/ALARM writes ONE fixed-slug page; OK REMOVES it (self-clearing)" {
  # Self-clearing is the point. Observed 2026-07-29 on the deploy channel: a `deploy-host-red` page
  # from 15:35 was still on disk hours after the condition cleared (its lint re-ran 16/16 green), so
  # the board reported a problem that no longer existed. A page whose condition has passed is
  # misinformation, not history — the append-only jsonl keeps the record.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  page="$CC_PAGES_DIR/capacity-alarm.page"

  # force WARN → page raised
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
  [ "$status" -eq 1 ] || false
  [ -f "$page" ] || false
  run grep -c 'capacity WARN' "$page"
  [ "$output" -ge 1 ] || false

  # back to OK → page retracted
  run /bin/bash "$ALARM" --quiet
  [ "$status" -eq 0 ] || false
  [ ! -f "$page" ] || false
}

@test "(xv) the page slug is FIXED — a repeated alarm overwrites, never accumulates" {
  # The unslugged channel has 490 files on disk. A job on a 10-minute interval must not add to that,
  # so damping is by construction (one path) rather than by a separate damper.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages2"
  for _ in 1 2 3; do
    run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
    [ "$status" -eq 1 ] || false
  done
  n="$(find "$CC_PAGES_DIR" -name '*.page' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || false
}

@test "(xvi) NO-DATA also retracts a stale page — never assert a condition we cannot see" {
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages3"
  page="$CC_PAGES_DIR/capacity-alarm.page"
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
  [ -f "$page" ] || false
  run env CC_CAP_PYTHON=/nonexistent/python /bin/bash "$ALARM" --quiet
  [ "$status" -eq 3 ] || false
  [ ! -f "$page" ] || false
}

@test "(xvii) CC_CAP_PAGE=off suppresses the page but still logs (channel and record are separate)" {
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages4"
  log="$BATS_TEST_TMPDIR/p4.jsonl"
  run env CC_CAP_PAGE=off CC_CAP_WARN_GB=999999 CC_CAP_LOG="$log" /bin/bash "$ALARM" --quiet
  [ "$status" -eq 1 ] || false
  [ ! -f "$CC_PAGES_DIR/capacity-alarm.page" ] || false
  [ -f "$log" ] || false                      # the durable record is unaffected by the page switch
  run grep -c '"verdict":"WARN"' "$log"
  [ "$output" -ge 1 ] || false
}

@test "(xviii) --no-append writes NEITHER the log nor a page (a dry read stays a dry read)" {
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages5"
  log="$BATS_TEST_TMPDIR/p5.jsonl"
  run env CC_CAP_WARN_GB=999999 CC_CAP_LOG="$log" /bin/bash "$ALARM" --quiet --no-append
  [ "$status" -eq 1 ] || false                 # verdict still reported
  [ ! -f "$log" ] || false
  [ ! -f "$CC_PAGES_DIR/capacity-alarm.page" ] || false
}
