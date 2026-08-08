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
  # EVERY AMBIENT RUNG IS PINNED NEUTRAL FOR EVERY TEST THAT DOES NOT OWN IT — a hermeticity fix, not
  # a way to hide a rung. This pin used to cover rung 7 alone, on the stated grounds that "load is the
  # only input in this file that is a property of the RUNNING BOX rather than of a fixture". THAT
  # CLAIM WAS FALSE, and it is the whole bug: SIX of the seven rungs read the live box, so a dozen
  # tests below asserted an exact verdict or rc against whatever else the machine happened to be
  # doing. The verdict is a MAX (see classify), so an ambient rung can only ever RAISE it — which
  # makes every OK-asserting and WARN-asserting test in this file a hostage to box weather.
  #
  # It came due on (ii): five postland RED rows, 2026-07-31..08-08, all adjudicated 1-of-3 by the
  # retry ladder and re-filed as a fresh backlog item each time. Measured here 2026-08-08 on an IDLE
  # box, each ambient rung and its distance from its own WARN floor:
  #   headroom 27.91 GB (warn <8) · pressure 1 (warn >=2 — ONE step) · max-proc 2.41 GB (warn >3) ·
  #   segments 7.8% (warn >=45) · coalition 215 procs (warn >=500) · swap delta 0 MB (alarm >=256)
  # Injecting pressure=2 and NOTHING else turns (ii)'s own command into WARN rc 1. During a
  # full-corpus postland run — 268 suites, ~2.4 h, dozens of live sessions — several of those are
  # ordinary readings, which is why this suite goes red exactly when it has to be trustworthy.
  #
  # WHAT THIS PINS IS THE CLASSIFICATION FLOOR, NEVER THE INSTRUMENT. Every reader still runs for
  # real, so a broken one still reports SKIPPED (rungs 1,3-7) or NO-DATA (headroom, rung 2) and the
  # tests that assert on those still fail. Rung 2's floors go to 0 rather than 9999 for exactly that
  # reason: headroom must still be READ, or (ii)'s "never null" assertion would be vacuous.
  # Each rung-owning test sets its own floors explicitly and overrides this — which is also why the
  # two selftests clear the pins: their probes hard-code expectations true only at shipped defaults.
  export CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999   # rung 7 scheduler
  export CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0                              # rung 2 headroom (still read)
  export CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999            # rung 3 kernel pressure
  export CC_CAP_PROC_WARN_GB=999999                                      # rung 4 per-proc outlier
  export CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999          # rung 5 compressor segments
  export CC_CAP_COAL_WARN=999999 CC_CAP_COAL_ALARM=999999                # rung 6 coalition population
  export CC_CAP_SWAP_DELTA_MB=999999                                     # rung 1 swap growth

  # The same pins as an `env -u` argument list, for the two selftests, which must run at the SHIPPED
  # defaults (see (i)). An ARRAY rather than a string: `env $(f)` needs word-splitting to work, which
  # is both a shellcheck finding and the exact hazard this suite bans elsewhere. Derived by hand from
  # the exports above — keep the two in step; a pin missing here silently re-tautologises a selftest.
  UNPIN=( -u CC_CAP_LOAD_WARN_PER_CORE -u CC_CAP_LOAD_ALARM_PER_CORE
          -u CC_CAP_WARN_GB            -u CC_CAP_ALARM_GB
          -u CC_CAP_PRESSURE_WARN      -u CC_CAP_PRESSURE_ALARM
          -u CC_CAP_PROC_WARN_GB       -u CC_CAP_SEG_WARN_PCT
          -u CC_CAP_SEG_ALARM_PCT      -u CC_CAP_COAL_WARN
          -u CC_CAP_COAL_ALARM         -u CC_CAP_SWAP_DELTA_MB )
}

# sysctl stub for rung 7. It is reached through CC_CAP_SYSCTL, not through PATH, because rung 7
# resolves /usr/sbin/sysctl by absolute path on purpose (D4) — so a PATH stub, which is how every
# other instrument in this suite is faked, would silently fail to intercept it and the test would
# pass against the live box's real load without ever noticing.
mk_sysctl_stub() { # $1 = 1-minute load, $2 = ncpu
  STUBS="${STUBS:-$BATS_TEST_TMPDIR/stubs}"
  mkdir -p "$STUBS"
  cat > "$STUBS/sysctl-load" <<SC
#!/bin/bash
case "\$*" in
  *hw.ncpu*)    echo '$2' ;;
  *vm.loadavg*) echo '{ $1 $1 $1 }' ;;   # braces included — the real output shape, see read_load
  *)            exec /usr/sbin/sysctl "\$@" ;;
esac
SC
  chmod +x "$STUBS/sysctl-load"
}

@test "(i) selftest GREEN — every rung + NO-DATA is reachable (positive control, R6)" {
  # THE PINS FROM setup() ARE CLEARED HERE, and must be. The selftest's probes hard-code their
  # expected verdicts, so they are only true at the SHIPPED defaults — a property it already had for
  # all six incumbent rungs (`5:0:1:0::::WARN` assumes WARN_GB=8 just as firmly). Deriving the
  # expectations from the live thresholds instead would make the control tautological, which is the
  # exact defect the census note below documents. So the control runs at the defaults, and the
  # ambient neutral-load pin — correct for every OTHER test in this file — is removed for this one.
  run env "${UNPIN[@]}" /bin/bash "$ALARM" --selftest
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
  # CC_CAP_SYSCTL, not PATH. Since 2026-08-08 EVERY sysctl site in the script resolves absolutely
  # (/usr/sbin/sysctl), for the reason rung 7 always did — the plist's PATH is a fact about another
  # file and has been wrong before. A PATH stub is therefore bypassed, and this test would silently
  # start reading the live box's pressure level instead of the 2 it thinks it injected: green on a
  # healthy machine, and a lie either way. The stub's own `*) exec /usr/sbin/sysctl` fall-through
  # keeps every other rung (including rung 7) reading the real values.
  # This test OWNS rung 3, so it states rung 3's floors rather than inheriting setup()'s neutral pin.
  run env PATH="$STUBS:$PATH" CC_CAP_SYSCTL="$STUBS/sysctl" \
          CC_CAP_PRESSURE_WARN=2 CC_CAP_PRESSURE_ALARM=4 /bin/bash "$ALARM" --json --no-append
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
  # Owns rung 3 — states its own floors, per (xix).
  run env PATH="$STUBS:$PATH" CC_CAP_SYSCTL="$STUBS/sysctl" \
          CC_CAP_PRESSURE_WARN=2 CC_CAP_PRESSURE_ALARM=4 /bin/bash "$ALARM" --json --no-append
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
  run env PATH="$STUBS:$PATH" CC_CAP_SYSCTL="$STUBS/sysctl" /bin/bash "$ALARM" --json --no-append
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
  # Owns rung 4 — states the 3 GB floor rather than inheriting setup()'s neutral pin.
  run env PATH="$STUBS:$PATH" CC_CAP_LOG="$BATS_TEST_TMPDIR/out.jsonl" \
          CC_CAP_PROC_WARN_GB=3 /bin/bash "$ALARM" --quiet
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
  # Owns rung 4 — states the 3 GB floor, per (xxiii).
  run env PATH="$STUBS:$PATH" CC_CAP_PROC_WARN_GB=3 /bin/bash "$ALARM" --json --no-append
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
  # Pins cleared for the reason (i) states: the probes are only true at the shipped defaults.
  run env "${UNPIN[@]}" /bin/bash "$ALARM" --selftest
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ pressure=\'2\' ]] || false
  [[ "$output" =~ pressure=\'4\' ]] || false
  [[ "$output" =~ maxproc=\'9\' ]] || false
  [[ "$output" =~ "disjoint-family sum" ]] || false
  # rung 7, and specifically the two probes that are NAMED EVENTS rather than round numbers: the
  # 2026-08-05 fatal sample, and the survived reading that is a known false ALARM. The false-positive
  # population is part of this rung's specification (D4), so a re-derivation has to move a control
  # rather than edit a comment.
  [[ "$output" =~ load=\'2.53\' ]] || false
  [[ "$output" =~ load=\'5.98\' ]] || false
  [[ "$output" =~ "PATH-INDEPENDENT" ]] || false
}

@test "(xxvii) the row PARSES as JSON in EVERY verdict state — including NO-DATA" {
  # The gap every other test in this file shares: they assert with regexes like `"verdict":"NO-DATA"`,
  # and a regex match never requires the surrounding document to be valid JSON. That blindness hid a
  # real defect — on the NO-DATA path the row carried `"est_room_sessions":?`, because the human-facing
  # `?` default is non-empty and so slipped past a `${ROOM:-null}` fallback. NO-DATA rows ARE appended,
  # so one blind sample poisoned the jsonl for every consumer, and the row that says "the instrument
  # broke" was precisely the row nobody could read.
  #
  # So: hand the output to a real parser, in each state that reaches a different branch of the printf.
  # NO-DATA is listed FIRST because it is the state that was broken and the one most likely to regress.
  parse() { printf '%s' "$1" | python3 -c 'import sys,json; json.loads(sys.stdin.read())'; }

  run env CC_CAP_PYTHON=/nonexistent/python /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  parse "$output" || false
  # and the field is the JSON literal null, never a bare `?`
  [[ "$output" =~ \"est_room_sessions\":null ]] || false
  ! [[ "$output" =~ est_room_sessions\":\? ]] || false

  # every other branch, so the fix cannot have traded one broken state for another
  for probe in "OK::" "WARN:CC_CAP_WARN_GB=999999:" "ALARM:CC_CAP_ALARM_GB=999999:CC_CAP_WARN_GB=999999"; do
    want="${probe%%:*}"; envs="${probe#*:}"
    # shellcheck disable=SC2086  # deliberate word-split: each probe's env assignments
    run env ${envs//:/ } /bin/bash "$ALARM" --json --no-append
    [[ "$output" =~ \"verdict\":\"$want\" ]] || false
    parse "$output" || false
  done

  # the ps-rss fallback branch builds top_procs differently — parse that shape too
  mk_stubs
  run env PATH="$STUBS:$PATH" CC_CAP_TOP=/nonexistent/top /bin/bash "$ALARM" --json --no-append
  parse "$output" || false
}

# ── rung 7: the scheduler axis (D4, 2026-08-05) ──────────────────────────────────────────────────
#
# The commissioning directive states the acceptance test itself: "Positive control REQUIRED (a
# synthetic load must turn it red) or the dimension is vacuous." A rung can be vacuous in two
# INDEPENDENT ways and one control cannot cover both, so there are two here:
#   · the ARITHMETIC can be wrong — covered by (xxviii): load injected at the instrument, so parse,
#     ncpu normalisation, classify, rc, row and page are all the real code path.
#   · the WIRE can be dead — covered by (xxxii): the real sysctl, the real box, no stub anywhere.
#     This is the failure that stubs are structurally blind to, and this repo has already shipped it
#     once: the launchd-PATH regression left three rungs reading SKIPPED in every scheduled run while
#     every hand-run and every stubbed test stayed green.
# (xxviii-b) is the negative half of the pair — without it, (xxviii) would pass on a live box that
# happened to be red on some OTHER rung, which is the same vacuity wearing a passing grade.

@test "(xxviii) THE POSITIVE CONTROL — a synthetic load turns the verdict RED (rc 2)" {
  # 25.3 on 10 cores = 2.53/core is not a round number: it is the 2026-08-05 fatal sample, the one
  # this sampler reported OK through because it emitted no CPU field at all.
  mk_sysctl_stub 25.3 10
  run env CC_CAP_SYSCTL="$STUBS/sysctl-load" \
          CC_CAP_LOAD_WARN_PER_CORE=1.5 CC_CAP_LOAD_ALARM_PER_CORE=2.5 \
          /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 2 ] || false
  [[ "$output" =~ \"verdict\":\"ALARM\" ]] || false
  [[ "$output" =~ \"load_1m\":25.3 ]] || false
  [[ "$output" =~ \"ncpu\":10 ]] || false
  [[ "$output" =~ \"load_per_core\":2.53 ]] || false
  # and the row is still a parseable document with the new fields on it (the est_room_sessions
  # lesson: a regex match never requires the surrounding JSON to be valid)
  printf '%s' "$output" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' || false
}

@test "(xxviii-b) NEGATIVE CONTROL for (xxviii) — the same path with a healthy load stays OK" {
  # Without this, (xxviii) proves nothing on a box that was already ALARM for another reason.
  # 4.2 on 10 cores = 0.42/core is this box's measured reading while rung 7 was written.
  mk_sysctl_stub 4.2 10
  run env CC_CAP_SYSCTL="$STUBS/sysctl-load" \
          CC_CAP_LOAD_WARN_PER_CORE=1.5 CC_CAP_LOAD_ALARM_PER_CORE=2.5 \
          /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ \"verdict\":\"OK\" ]] || false
  [[ "$output" =~ \"load_per_core\":0.42 ]] || false
}

@test "(xxix) rung 7 floors, pinned from BOTH sides — 2.5 ALARM / 1.5 WARN / 1.49 OK" {
  # Each floor from below as well as above, so a one-sided edit (raise the alarm, forget the warn)
  # cannot pass. The pair 1.49/1.5 and 2.49/2.5 is the whole threshold, executable.
  for probe in "24.9:1" "25.0:2" "14.9:0" "15.0:1"; do
    mk_sysctl_stub "${probe%%:*}" 10
    run env CC_CAP_SYSCTL="$STUBS/sysctl-load" \
            CC_CAP_LOAD_WARN_PER_CORE=1.5 CC_CAP_LOAD_ALARM_PER_CORE=2.5 \
            /bin/bash "$ALARM" --quiet --no-append
    [ "$status" -eq "${probe#*:}" ] || { echo "load ${probe%%:*} → rc $status, want ${probe#*:}"; false; }
  done
}

@test "(xxx) an unreadable load instrument is SKIPPED — never NO-DATA, never a fabricated idle 0" {
  # Two failure shapes, and the second is the dangerous one. NO-DATA belongs to the single instrument
  # the verdict cannot exist without (vm_stat headroom); demoting a valid memory verdict because a
  # supplementary sysctl died would destroy a working alarm. And a dead sysctl rendering as
  # `load_per_core: 0` would be the launchd-PATH regression exactly — a corpse reporting the
  # healthiest possible value, on the one rung in this file whose sensor is a daemon-context read.
  run env CC_CAP_SYSCTL=/nonexistent/sysctl CC_CAP_LOAD_WARN_PER_CORE=1.5 \
          CC_CAP_LOAD_ALARM_PER_CORE=2.5 /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false
  ! [[ "$output" =~ \"verdict\":\"NO-DATA\" ]] || false
  [[ "$output" =~ \"load_per_core\":null ]] || false
  [[ "$output" =~ \"load_1m\":null ]] || false
  [[ "$output" =~ \"ncpu\":null ]] || false
  ! [[ "$output" =~ \"load_per_core\":0 ]] || false
  # ...and a skipped rung must not MASK a breach another rung found
  run env CC_CAP_SYSCTL=/nonexistent/sysctl CC_CAP_ALARM_GB=999999 CC_CAP_WARN_GB=999999 \
          /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 2 ] || false
}

@test "(xxxi) the load rung owns its own page, and the page NAMES the survived counter-example" {
  # D3: per-rung slugs exist so a NEW crossing is audible inside a standing alarm. And this rung's
  # page carries its own counter-evidence, because its floors are not calibrated — an operator who
  # reads "ALARM" without knowing the box has lived above this number for 42 h will shed sessions
  # that did not need shedding. A page that causes the wrong action is not better than no page.
  mk_sysctl_stub 25.3 10
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages-load"
  run env CC_CAP_SYSCTL="$STUBS/sysctl-load" \
          CC_CAP_LOAD_WARN_PER_CORE=1.5 CC_CAP_LOAD_ALARM_PER_CORE=2.5 \
          CC_CAP_LOG="$BATS_TEST_TMPDIR/load.jsonl" /bin/bash "$ALARM" --quiet
  [ "$status" -eq 2 ] || false
  page="$CC_PAGES_DIR/capacity-alarm-load.page"
  [ -f "$page" ] || false
  grep -q '2.53/core' "$page" || false
  grep -q 'UNCALIBRATED' "$page" || false
  grep -q '5.98/core survived' "$page" || false
}

@test "(xxxii) LIVE non-vacuity — the REAL sysctl on the REAL box crosses a floor set beneath it" {
  # (xxviii) proves the arithmetic through a stub; this proves the WIRE, which no stub can. A dead
  # reader passes every stubbed test ever written for it and then reads SKIPPED forever in
  # production. Asserted as a PAIR against the same live reading, so the redness is attributable to
  # the floor crossing rather than to whatever else the box happens to be doing.
  run env CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999 \
          /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 0 ] || false                              # baseline: nothing else is red
  ! [[ "$output" =~ \"load_per_core\":null ]] || false      # and the instrument really did read
  run env CC_CAP_LOAD_WARN_PER_CORE=0 CC_CAP_LOAD_ALARM_PER_CORE=9999 \
          /bin/bash "$ALARM" --json --no-append
  [ "$status" -eq 1 ] || false                              # same box, floor lowered ⇒ WARN
  [[ "$output" =~ \"verdict\":\"WARN\" ]] || false
}

@test "(viii) R1 — never sleeps, polls, or waits on load (EXECUTABLE lines only)" {
  # TWO defects the first version of this test had, both caught by running it:
  #  1. It matched the script's OWN PROSE — the header says "NEVER refuses, blocks, queues, sleeps,
  #     or polls-until-clear", so the guard convicted the very documentation of the property it
  #     checks. Text is never evidence (memory detector-matching-its-own-skill-description). Comments
  #     are therefore stripped before matching.
  #  2. It passed VACUOUSLY against a tree with no capacity-alarm.sh at all, because grep on a
  #     missing file also returns non-zero. Hence the existence guard.
  #
  # THE `loadavg` ALTERNATIVE WAS REMOVED 2026-08-05, and why is the whole point of this note. R1
  # bans WAITING — "a shedder that waits amplifies". The guard listed `loadavg` beside the wait
  # patterns because the file's header ALSO claimed never to read load at all. Those are two
  # different invariants that happened to share one regex, and enumerating a spelling instead of the
  # class is exactly how a guard outlives the claim it was smuggled into (memory
  # denylist-enumerates-spellings-not-the-class). The claim is now superseded by measurement — four
  # consecutive panics on the scheduler axis — and rung 7 READS vm.loadavg on every tick. R1 itself
  # is untouched: no sleep, no block, no queue, no poll-until-clear, and this guard still proves it.
  # (ix) is what stops the narrowing from having quietly deleted the invariant too.
  [ -f "$ALARM" ] || false
  run bash -c "sed 's/#.*//' '$ALARM' | grep -nE '\\bsleep\\b|while.*load|until.*load'"
  [ "$status" -ne 0 ] || false
}

@test "(ix) POSITIVE CONTROL for (viii): the narrowed grep still catches a sleep AND a wait-on-load" {
  # Proves the stripping did not defang the guard: a genuine executable sleep must still be found,
  # while the same word inside a comment must not.
  printf '# we never sleep here\nsleep 5\n' > "$BATS_TEST_TMPDIR/bait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/bait.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -eq 0 ] || false
  printf '# we never sleep here\n:\n' > "$BATS_TEST_TMPDIR/clean.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/clean.sh' | grep -nE '\\bsleep\\b'"
  [ "$status" -ne 0 ] || false

  # THE PAIR THAT MAKES THE NARROWING SAFE — the discriminator R1 actually cares about. Dropping the
  # `loadavg` term could have taken the wait-on-load invariant with it, and the suite would have gone
  # green either way; a control that cannot fail the same way is not a control. So: a loop that WAITS
  # for load must still be caught, and a bare READ of load — the thing rung 7 now legitimately does —
  # must not be.
  local re='\bsleep\b|while.*load|until.*load'
  printf 'while [ "$load" -gt 20 ]; do :; done\n' > "$BATS_TEST_TMPDIR/waitbait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/waitbait.sh' | grep -nE '$re'"
  [ "$status" -eq 0 ] || false
  printf 'until load_below_ceiling; do :; done\n' > "$BATS_TEST_TMPDIR/untilbait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/untilbait.sh' | grep -nE '$re'"
  [ "$status" -eq 0 ] || false
  printf 'L="$(/usr/sbin/sysctl -n vm.loadavg)"\n' > "$BATS_TEST_TMPDIR/readbait.sh"
  run bash -c "sed 's/#.*//' '$BATS_TEST_TMPDIR/readbait.sh' | grep -nE '$re'"
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

@test "(xv) page slugs are BOUNDED — repeated alarms overwrite/hold, never accumulate" {
  # The unslugged channel has 490 files on disk. A job on a 60 s interval must not add to that, so
  # damping is by construction: ONE combined slug (rewritten each tick) + ONE slug per rung that has
  # crossed (written on ITS transition, held while the state stands — D3). Three identical WARN runs
  # therefore produce exactly TWO files — combined + headroom — and the count must not grow.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages2"
  for _ in 1 2 3; do
    run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
    [ "$status" -eq 1 ] || false
    n="$(find "$CC_PAGES_DIR" -name '*.page' | wc -l | tr -d ' ')"
    [ "$n" -eq 2 ] || false
  done
  [ -f "$CC_PAGES_DIR/capacity-alarm.page" ] || false
  [ -f "$CC_PAGES_DIR/capacity-alarm-headroom.page" ] || false
}

@test "(xv-b) a per-rung page is written on the TRANSITION only — a standing state never resets its clock" {
  # The file's epoch answers "when did this start"; a 60 s rewrite would reset that answer every
  # tick. Run 1 crosses OK→WARN and writes; run 2 holds WARN and must leave the file untouched.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages-trans"
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
  [ "$status" -eq 1 ] || false
  page="$CC_PAGES_DIR/capacity-alarm-headroom.page"
  [ -f "$page" ] || false
  m1="$(stat -f %m "$page")"
  sleep 1
  run env CC_CAP_WARN_GB=999999 /bin/bash "$ALARM" --quiet
  [ "$status" -eq 1 ] || false
  m2="$(stat -f %m "$page")"
  [ "$m1" = "$m2" ] || false
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
