#!/usr/bin/env bats
# capacity-marginal — the sampler that must REFUSE to state a marginal its own controls cannot
# support (backlog 193ae8ddce72; DoD docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §5).
#
# WHAT THIS SUITE IS FOR. The item this script answers exists because the repo published four
# values for marginal load per ACTIVE session spanning 30x, and every one of them came from an
# instrument that always answers. The deliverable is therefore NOT "a number" and not even "a
# script that computes a number" — it is a control that can FAIL, and a control is only known to be
# able to fail once something has watched it do so. So the first test here replays the exact census
# shape that killed this wave's own headline (flat at 19-20 across a 2.2x load range,
# corr = -0.05) and asserts the script refuses; the second plants a known coefficient and asserts
# it is recovered. A suite with only the second test would certify a rubber stamp.
#
# WHY FIXTURES AND NOT THE LIVE BOX. Every control arm is a property of a SERIES, so the subject is
# a file, not a machine. Testing this against the live box would make the suite pass or fail on how
# busy the operator is — the one input a gate corpus may never depend on.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO/scripts/capacity-marginal.sh"
  D="$BATS_TEST_TMPDIR"
  # Hermetic HOME: nothing here writes to it today, but `sample` resolves spawn-presence.sh, which
  # reads the operator's beat directory. A probe must never see the live fleet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # `run --preflight` reaches cc_sp_active, and spawn-presence.sh reaches the capacity-admit gate,
  # which refuses on LIVE load / headroom / session census. None of that is this suite's subject:
  # left on, these tests would go red by how busy the operator's box is — the one input a gate
  # corpus may never depend on (see this file's header).
  export CC_ADMIT_GATE=off
  hdr() { printf '#ts\tload1\tunit\ttotal_run\tclaude_run\tactive\tresident\n' > "$1"; }
}

# One row: <file> <ts> <load1> <total_run> <claude_run> <active> [unit]
row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t14\n' "$2" "$3" "${7:-proc}" "$4" "$5" "$6" >> "$1"
}

# ── THE CONTROL MUST BE ABLE TO FAIL ────────────────────────────────────────────────────────────

@test "POSITIVE CONTROL: the census shape that killed the wave's own headline is REFUSED" {
  # docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §2: "REFUTED as a number — the census
  # failed a correlation control it never ran: corr(load, R-procs) = -0.05, flat at 19-20 R procs
  # across a 2.3x load range." Replayed here at 60 s spacing so n_eff is NOT the reason it fails —
  # the correlation has to be what refuses, or this test proves the wrong thing.
  local f="$D/flat.tsv"; hdr "$f"
  local i ts=1000000 load
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')"
    row "$f" "$ts" "$load" "$(( 19 + i % 2 ))" "$(( 2 + i % 3 ))" "$(( 3 + i % 4 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2 DYNAMICS   FAIL"* ]] || false
  [[ "$output" == *"does not track the load it apportions"* ]] || false
  [[ "$output" == *"NO-ATTRIBUTION"* ]]
}

@test "a refused window emits NO quotable coefficient" {
  # The failure mode this whole file exists to stop is a number escaping a failed control and being
  # quoted six weeks later with its provenance gone. The withheld fit is printed in parentheses,
  # explicitly labelled withheld, and the string a reader greps for — "VERDICT: MARGINAL" — must
  # not appear at all.
  local f="$D/flat2.tsv"; hdr "$f"
  local i ts=1000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 12 + 14 * i / 39 }')" 19 3 4
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" != *"VERDICT: MARGINAL"* ]] || false
  [[ "$output" == *"withheld"* ]]
}

@test "NEGATIVE CONTROL: a planted coefficient is recovered and all three controls PASS" {
  # Ambient (the 87.3% confounder B3 measured) moves on its own; Claude's attributed census carries
  # a planted 0.25 runnable procs per ACTIVE session; load1 = 1.30 x census. Expected marginal
  # 0.25 x 1.30 = 0.325 load units. If the estimator cannot recover a coefficient that IS there,
  # a refusal from it proves nothing.
  local f="$D/planted.tsv"; hdr "$f"
  local i ts=2000000 act amb cl tot load
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    row "$f" "$ts" "$load" "$tot" "$cl" "$act"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 LEVEL      PASS"* ]] || false
  [[ "$output" == *"C2 DYNAMICS   PASS"* ]] || false
  [[ "$output" == *"C3 IDENTIFY   PASS"* ]] || false
  # Recovered within 5% of the planted 0.325.
  local got; got="$(printf '%s\n' "$output" | awk '/VERDICT: MARGINAL/ { print $3 }')"
  run awk -v g="$got" 'BEGIN { exit !(g > 0.309 && g < 0.342) }'
  [ "$status" -eq 0 ]
}

# ── EACH CONTROL, FAILING FOR ITS OWN REASON ────────────────────────────────────────────────────

@test "C2 fails as UNINFORMATIVE (not refuting) when the window holds too few independent samples" {
  # B3's own defect, by name: three windows of 2.5-4 min against load1's 60 s time constant is
  # ~2.5 independent observations, so its negative correlation was undecided rather than refuting.
  # Here the correlation is near-perfect and the window is still refused — n_eff, never n.
  local f="$D/short.tsv"; hdr "$f"
  local i ts=3000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 5 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2 DYNAMICS   FAIL"* ]] || false
  [[ "$output" == *"uninformative, not refuting"* ]]
}

@test "C2 names a CONSTANT census for what it is — the instrument, not the box" {
  local f="$D/const.tsv"; hdr "$f"
  local i ts=4000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 15 * i / 39 }')" 20 4 "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"census is CONSTANT"* ]]
}

@test "C3 fails when the ACTIVE count never moves — a slope needs a regressor" {
  # The 1.89 defect's smaller sibling: fitting a marginal across one level of the thing whose
  # marginal is being fitted.
  local f="$D/flatact.tsv"; hdr "$f"
  local i ts=5000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" 4 5
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C3 IDENTIFY   FAIL"* ]] || false
  [[ "$output" == *"1 level"* ]]
}

@test "C3 fails, and says how many rows were blind, when no row carries an ACTIVE count" {
  # cc_sp_active records `-` when unmeasurable rather than 0, so a dead sensor can never read as a
  # quiet box. The analyzer has to carry that distinction through instead of coercing it to zero.
  local f="$D/noact.tsv"; hdr "$f"
  local i ts=6000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" 4 -
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C3 IDENTIFY   FAIL"* ]] || false
  [[ "$output" == *"0 row(s) carry an ACTIVE count (40 unmeasurable)"* ]]
}

@test "C1 fails on a window that never moved — a ratio agreeing at one load has reproduced nothing" {
  local f="$D/quiet.tsv"; hdr "$f"
  local i ts=7000000
  for i in $(seq 0 39); do
    row "$f" "$ts" "10.0$(( i % 9 ))" "$(( 8 + i % 2 ))" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 LEVEL      FAIL"* ]] || false
  [[ "$output" == *"load span"* ]]
}

@test "C1 fails a ratio that drifts across the load range — the x1.553 single-point-fit defect" {
  # A8's x1.553 R-procs->load factor was fitted at ONE load and B3 reproduced none of it
  # (0.913 / 1.077 / 1.235). Here the census tracks load's RANK perfectly — C2 passes — while the
  # ratio drifts 2x across the tertiles, and C1 alone refuses.
  local f="$D/drift.tsv"; hdr "$f"
  local i ts=8000000 load tot
  for i in $(seq 0 39); do
    load="$(awk -v i="$i" 'BEGIN { printf "%.2f", 10 + 30 * i / 39 }')"
    tot="$(awk -v l="$load" 'BEGIN { printf "%.3f", l / (0.8 + l / 40) }')"
    row "$f" "$ts" "$load" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 LEVEL      FAIL"* ]] || false
  [[ "$output" == *"C2 DYNAMICS   PASS"* ]] || false
  [[ "$output" == *"swing"* ]]
}

# ── DATA HYGIENE ────────────────────────────────────────────────────────────────────────────────

@test "mixed census units are NO-DATA, never pooled" {
  # Process-unit and thread-unit censuses have different ratios (1.30-1.55 vs 0.913). Pooling them
  # would produce a ratio that is neither, and C1 would then certify the average of two wrongs.
  local f="$D/mixed.tsv"; hdr "$f"
  local i ts=9000000 tot
  for i in $(seq 0 39); do
    tot=$(( 10 + i % 12 ))
    row "$f" "$ts" "$(awk -v t="$tot" 'BEGIN { printf "%.2f", 1.3 * t }')" "$tot" "$(( 2 + i % 5 ))" "$(( 2 + i % 5 ))" \
        "$( [ $(( i % 2 )) -eq 0 ] && echo proc || echo thread )"
    ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"mix census units"* ]]
}

@test "an unreadable or near-empty input is NO-DATA (3), never a zero coefficient" {
  run bash "$M" analyze --in "$D/absent.tsv"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NO-DATA"* ]] || false
  local f="$D/thin.tsv"; hdr "$f"; row "$f" 1 10 8 2 3
  run bash "$M" analyze --in "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"usable row"* ]]
}

@test "--json emits parseable JSON whose verdict matches the text verdict" {
  local f="$D/planted2.tsv"; hdr "$f"
  local i ts=2000000 act amb cl tot load
  for i in $(seq 0 39); do
    act=$(( 2 + i % 6 ))
    amb="$(awk -v i="$i" 'BEGIN { printf "%.3f", 9 + 6 * ((i * 7) % 11) / 10 }')"
    cl="$(awk -v a="$act" 'BEGIN { printf "%.3f", 0.25 * a }')"
    tot="$(awk -v a="$amb" -v c="$cl" 'BEGIN { printf "%.3f", a + c }')"
    load="$(awk -v t="$tot" 'BEGIN { printf "%.3f", 1.30 * t }')"
    row "$f" "$ts" "$load" "$tot" "$cl" "$act"; ts=$(( ts + 60 ))
  done
  run bash "$M" analyze --in "$f" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.verdict == "MARGINAL" and .c1_level and .c2_dynamics and .c3_identify' >/dev/null
}

# ── THE ATTRIBUTION ─────────────────────────────────────────────────────────────────────────────

@test "attribution walks ancestry: a session's jq/ugrep forks count as the session's load" {
  # B3 measured the forks a session spawns at ~3x claude.exe's own threads, so a census that
  # attributed only the launcher process would undercount Claude by two thirds. 200 is a session
  # (2 runnable descendants), 500 is an idle session with one uninterruptible child, and kitty +
  # mediaanalysisd are runnable but not ours.
  cat > "$D/ps.txt" <<'EOF'
  100     1 S    /sbin/launchd
  200   100 R    /Users/x/.claude-220/node_modules/.bin/claude
  201   200 R    jq
  202   200 S    bash
  203   201 R    ugrep
  300   100 R    /Applications/kitty.app/Contents/MacOS/kitty
  400   100 R    mediaanalysisd
  500   100 S    /Users/x/.claude-220/node_modules/.bin/claude
  501   500 D    node
EOF
  run env CC_MARG_PS_OVERRIDE="$D/ps.txt" bash -c '
    set -uo pipefail
    CC_MARG_EXEC_RE="\.claude-[0-9]+/node_modules/|claude\.exe$"
    '"$(sed -n '/^census_row() {/,/^}/p' "$REPO/scripts/capacity-marginal.sh")"'
    census_row'
  [ "$status" -eq 0 ]
  # total runnable 6 (200,201,203,300,400,501) · Claude-owned 4 (200,201,203,501) · resident 2
  [ "$output" = "6 4 2" ]
}

@test "the RESIDENT census reads the executable path, never argv" {
  # DoD §5, verbatim: count "by executable path, never argv — argv reads 30-33 against a true
  # 15-16, because briefs mention the path". A future edit swapping comm= for args= would double
  # the denominator of every capacity claim and change no test but this one.
  run grep -noE 'ps -[ae]xo [a-z=,]+' "$REPO/scripts/capacity-marginal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"comm="* ]] || false
  [[ "$output" != *"args="* ]]
}

@test "a bad interval is a usage error, not a busy loop" {
  run bash "$M" sample --interval-s 0 --window-s 1 --out "$D/x.tsv"
  [ "$status" -eq 2 ]
}

# ── `run`: §6's PROTOCOL, AND THE PREFLIGHT THAT KEEPS AN OFF-BOX REFUSAL FROM READING AS A FINDING ─
#
# A triple-FAIL from a box with no fleet is textually identical to a triple-FAIL from the 10-core
# box mid-wave, and only the second one is a finding. §6a of the adjudication doc records exactly
# such an off-box smoke run. These tests pin the two structural ways the answer is unreachable, and
# they are the reason `run` refuses to spend an hour rather than reporting about itself.

@test "run PREFLIGHT refuses a blind ACTIVE sensor — C3 could never pass, however long the window" {
  # cc_sp_active unmeasurable => every row records `-` => C3 fails on "0 row(s) carry an ACTIVE
  # count", which is the shape the C3-blind test above pins. Sampling into that is an hour spent
  # measuring the sensor.
  cat > "$D/ps_fleet.txt" <<'EOF'
  100     1 S    /sbin/launchd
  200   100 R    /Users/x/.claude-220/node_modules/.bin/claude
  300   100 S    /Users/x/.claude-220/node_modules/.bin/claude
  400   100 R    /Users/x/.claude-220/node_modules/.bin/claude
EOF
  # HOME is the hermetic one from setup(), so spawn-presence has no beat directory to read and
  # read_active returns `-` exactly as it does off-box.
  run env CC_MARG_PS_OVERRIDE="$D/ps_fleet.txt" bash "$M" run --preflight
  [ "$status" -eq 5 ]
  [[ "$output" == *"PREFLIGHT FAIL  active"* ]] || false
  [[ "$output" == *"C3 IDENTIFY can never pass"* ]]
}

@test "run PREFLIGHT refuses a fleet too small to produce the ACTIVE levels C3 requires" {
  cat > "$D/ps_one.txt" <<'EOF'
  100     1 S    /sbin/launchd
  200   100 R    /Users/x/.claude-220/node_modules/.bin/claude
EOF
  run env CC_MARG_PS_OVERRIDE="$D/ps_one.txt" CC_MARG_RUN_ACTIVE_OVERRIDE=1 bash "$M" run --preflight
  [ "$status" -eq 5 ]
  [[ "$output" == *"PREFLIGHT FAIL  fleet"* ]] || false
  [[ "$output" == *"1 resident session(s), need >= 3"* ]]
}

@test "run PREFLIGHT passes on a fleet-carrying box and reports the census it will sample" {
  cat > "$D/ps_ok.txt" <<'EOF'
  100     1 S    /sbin/launchd
  200   100 R    /Users/x/.claude-220/node_modules/.bin/claude
  201   200 R    jq
  300   100 S    /Users/x/.claude-220/node_modules/.bin/claude
  400   100 R    /Users/x/.claude-220/node_modules/.bin/claude
  500   100 R    mediaanalysisd
EOF
  run env CC_MARG_PS_OVERRIDE="$D/ps_ok.txt" CC_MARG_RUN_ACTIVE_OVERRIDE=4 bash "$M" run --preflight
  [ "$status" -eq 0 ]
  # 3 resident sessions; runnable 4 (200, 201, 400, 500) of which 3 are ours (200, 201, 400).
  [[ "$output" == *"PREFLIGHT PASS  3 resident session(s), 4 ACTIVE now, 3/4 runnable procs are ours."* ]]
}

# The stopping rule, as a pure function. Tested by extraction — this suite's own header forbids a
# gate test that passes or fails on how busy the operator's box is, and a loop exercised only
# against the live fleet is a loop nobody has checked.
decide() { # <rc> <sig> <prev> <streak> <elapsed> <max> <k>
  bash -c 'set -uo pipefail
'"$(sed -n '/^run_decide() {/,/^}/p' "$M")"'
run_decide "$@"' _ "$@"
}

@test "run STOPS on a PASS — a coefficient ends the protocol, whatever the budget says" {
  run decide 0 - - 0 10 10000 3
  [ "$status" -eq 0 ]
  [[ "$output" == PASS* ]]
}

@test "run calls a refusal STABLE only once the SAME term has refused K windows running" {
  # §6, verbatim: extend "until the verdict stops being NO-ATTRIBUTION OR the refusal repeats with
  # the same term across several windows — which would itself be the finding".
  run decide 1 C2 C2 1 300 10000 2
  [ "$status" -eq 0 ]
  [[ "$output" == "STABLE 2" ]]
}

@test "a MOVING failing term resets the streak and is never reported as the finding" {
  # The load-bearing half of the rule. A window that fails C1, then C2, then C1 has not shown that
  # the process-unit census is the wrong instrument; it has shown a box that changed underneath it.
  # Reporting that as "the finding" would mint exactly the kind of unearned conclusion this whole
  # script exists to refuse.
  run decide 1 C1 C2 5 300 10000 2
  [ "$status" -eq 0 ]
  [[ "$output" == "CONTINUE 1" ]]
}

@test "run gives up as INCONCLUSIVE, never as a finding, when the budget ends on a moving term" {
  run decide 1 C1 C2 4 10000 10000 3
  [ "$status" -eq 0 ]
  [[ "$output" == "INCONCLUSIVE 1" ]]
}

@test "the PASS hand-off RE-GREPS the citation sites instead of listing them" {
  # The 2026-08-26 ban pass found THREE live sites where the doc named two, and the one it missed
  # was spawn-presence.sh — the library that defines the ACTIVE population the coefficient is
  # denominated in. A hard-coded path list in the hand-off would ship that defect a second time.
  run sed -n '/^run_next_steps() {/,/^}/p' "$M"
  [ "$status" -eq 0 ]
  [[ "$output" == *"grep -rl 'marginal-load-per-active-session-2026-08-19'"* ]] || false
  [[ "$output" != *"capacity-admit.sh"* ]] || false
  [[ "$output" != *"agent-teams-enforce.sh"* ]] || false
  [[ "$output" != *"spawn-presence.sh"* ]]
}

@test "the hand-off resolves its own path through symlinks, and never renders zero hits as none" {
  # ~/.claude/scripts/ is a tree of per-file symlinks into the checkout, so an unresolved
  # `dirname "$0"/..` reads ~/.claude — no docs/, no .git — and the re-grep would print an empty
  # list on the ONE path the operator runs: a hand-off asserting "no sites remain" while three do.
  # Here the script is reached through a symlink whose parent has no repo under it, and the output
  # must still say the root is suspect rather than saying nothing.
  mkdir -p "$D/live/scripts" "$D/empty/scripts"
  ln -s "$M" "$D/live/scripts/capacity-marginal.sh"
  cp "$M" "$D/empty/scripts/capacity-marginal.sh"
  handoff() {
    bash -c 'set -uo pipefail
'"$(sed -n '/^_marg_resolve_self() {/,/^}/p' "$M")"'
'"$(sed -n '/^run_next_steps() {/,/^}/p' "$M")"'
run_next_steps "$1"' _ "$1"
  }

  # Reached through a symlink whose own parent tree holds no repo: resolution must hop back into
  # the real checkout and find the live sites there.
  run handoff "$D/live/scripts/capacity-marginal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/lib/spawn-presence.sh"* ]] || false
  [[ "$output" != *"(no live citation site found"* ]] || false

  # A real file in a tree with no sites: zero hits must render as SUSPECT, never as "none". Those
  # two readings differ by whether three live sites still quote a refuted figure.
  run handoff "$D/empty/scripts/capacity-marginal.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no live citation site found"* ]]
}

@test "run rejects a bad budget as a usage error, not a loop that can never terminate" {
  run bash "$M" run --increment-s 900 --max-s 60 --out "$D/y.tsv"
  [ "$status" -eq 2 ]
  run bash "$M" run --repeat-k 0 --out "$D/y.tsv"
  [ "$status" -eq 2 ]
  run bash "$M" run --increment-s abc --out "$D/y.tsv"
  [ "$status" -eq 2 ]
}
