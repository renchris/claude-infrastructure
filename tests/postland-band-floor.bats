#!/usr/bin/env bats
# postland-band-floor.bats — the invariant that decides which lever moves the postland lane's
# wall-clock (backlog 70dff02dcf4a, LAND_PIPELINE_V2.md §8).
#
# THE FACT BEING PINNED. Darwin has two ways to put a process at PRI 4, and they are NOT the same
# mechanism:
#
#   taskpolicy -c background   a CLAMP.      A child's own `-c utility` LIFTS it to PRI 20.
#   taskpolicy -b              a TASK ROLE.  A child's own `-c utility` reads PRI 4 — no escape.
#
# launchd `ProcessType Background` applies the SECOND one. That asymmetry is the whole reason the
# postland corpus's own `nice -n 19 taskpolicy -c background` prefix never set its band: $BATS_BIN is
# the bare name `bats`, which PATH-resolves to bin/cc-bats, whose default band is `utility`, and
# cc-bats OVERRIDES the inherited clamp. So the corpus ran at PRI 20 everywhere the role was absent,
# and at PRI 4 only under the launchd job — a 3.19x wall-clock split between two populations of the
# same corpus, misread for twelve days as two independent levers.
#
# WHY IT NEEDS A GUARD RATHER THAN A COMMENT. The decision it justifies is a plist edit
# (launchd/com.claude.postland-verify.plist now execs through `taskpolicy -c utility` instead of
# declaring `ProcessType Background`). If a future macOS makes the task role liftable from inside,
# that edit stops being necessary and the reasoning behind it stops being true — and nothing else on
# this box would notice, because everything downstream reads PRI and would simply see 20. This suite
# goes RED in that world, which is the point: re-derive rather than inherit.
#
# NOT DUPLICATED FROM tests/qos-chokepoint.bats. That suite proves cc-bats reaches PRI 20 (iv) and
# has a positive control that it can see PRI 31 (v). Neither asserts the ASYMMETRY — (v) only names
# the one-way ratchet in a comment, as the reason its own control is skippable. The asymmetry is what
# this file adds, plus the end-to-end shape the corpus actually runs.
#
# PROOF DISCIPLINE inherited from qos-chokepoint.bats, non-negotiable:
#   · non-final `[[ ]]` / `(( ))` are errexit-EXEMPT and DEAD as assertions — every one gets `|| false`
#   · PRI is read from ps (what the kernel DID), never from the exec line (what we INTENDED)
#   · clamp assertions test the EXACT value, never `<= N`: Darwin decays a busy undemoted proc as low
#     as PRI 17, so a range up to 20 would pass on undemoted work
#   · descendants are walked from a CAPTURED root pid, never grepped box-wide — a global `bats` grep
#     picks up a sibling session's run and proves nothing about ours (memory pgrep-f-matches-agent-briefs)
#
# RED-PROOF: swap the `-b` in the asymmetry test for `-c background` and it goes red (the clamp IS
# liftable); point the chain test at the real bats instead of cc-bats and it goes red (nothing lifts
# the inherited clamp). Both mutations were run.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SHIM="$REPO/bin/cc-bats"
  TP=/usr/sbin/taskpolicy
  TMP="$BATS_TEST_TMPDIR"
  # HERMETICITY: fixture $HOME first (the repo's test-hermeticity ratchet), and clear the ambient
  # CC_BATS_* seams — every one of them is read from the environment, so an unfixtured run's verdict
  # would depend on HOW the suite was invoked. Running this suite THROUGH cc-bats would otherwise set
  # CC_BATS_ACTIVE=1 and make the shim under test hit its own re-entrancy guard.
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/logs"
  unset CC_BATS_ACTIVE CC_BATS_QOS CC_BATS_QOS_MODE CC_BATS_QOS_BAND CC_BATS_QUIET \
        CC_BATS_BAND CC_BATS_TASKPOLICY CC_BATS_REAL CC_BATS_SEED 2>/dev/null || true
  # cc-bats' ADMISSION deferral (rc 75) runs NOTHING when the box is busy, which would make the chain
  # test read "(none sampled)" under load and convict on an absence. postland-verify.sh exports the
  # same 0 for the same reason (see its BATS_BIN note) — 0 is cc-bats' own documented kill switch.
  export CC_BATS_MAX_ROOTS=0
  mkdir -p "$TMP/t"
  printf '@test "occupies the scheduler long enough to be sampled" {\n  /bin/sleep 6\n}\n' > "$TMP/t/slow.bats"
}

# _pri_of_clamped <taskpolicy args...> — spawn /bin/sleep under the given prefix, return its PRI.
# The pid is CAPTURED, never searched for.
_pri_of_clamped() {
  local pid pri
  "$@" /bin/sleep 5 &
  pid=$!
  /bin/sleep 1
  pri=$(ps -o pri= -p "$pid" 2>/dev/null | tr -d ' ')
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  printf '%s' "$pri"
}

# _descendant_pris <root pid> — PRI of every real-bats process beneath OUR root, one per line.
_descendant_pris() {
  local cur next kids cmd out=""
  cur="$1"
  while [ -n "$cur" ]; do
    next=""
    for p in $cur; do
      kids=$(pgrep -P "$p" 2>/dev/null | tr '\n' ' ')
      [ -n "$kids" ] || continue
      next="$next $kids"
      for k in $kids; do
        cmd=$(ps -o command= -p "$k" 2>/dev/null)
        case "$cmd" in
          *bats-exec-test*|*bats-exec-file*) out="$out$(ps -o pri= -p "$k" 2>/dev/null | tr -d ' ')
" ;;
        esac
      done
    done
    cur="$next"
  done
  printf '%s' "$out"
}

@test "(i) INSTRUMENT CONTROL: the two clamps land on their calibrated, distinct values" {
  if [ ! -x "$TP" ]; then skip "taskpolicy(8) absent on this host"; fi
  # Without this, every assertion below could pass off a probe that reports one constant. The two
  # clamps must land on their calibrated values and must DIFFER, or the instrument cannot discriminate.
  local util bg
  util=$(_pri_of_clamped "$TP" -c utility)
  bg=$(_pri_of_clamped "$TP" -c background)
  [ "$util" = "20" ] || false
  [ "$bg" = "4" ] || false
  [ "$util" != "$bg" ] || false
  # The undemoted leg is CONDITIONAL, for the same measured reason qos-chokepoint.bats (v) skips its
  # control: a clamp is inherited, so from inside a demoted band an undemoted child is unconstructible
  # and `plain` reads the parent's band rather than 31. Asserting it unconditionally would convict the
  # suite for where it was invoked from — this suite runs inside the corpus, i.e. at PRI 20, every
  # time (memory exoneration-bound-must-fit-what-it-bounds). Where it IS constructible, assert it.
  local own plain
  own=$(ps -p $$ -o pri= 2>/dev/null | tr -d ' ')
  if [ -n "$own" ] && [ "$own" -gt 20 ]; then
    plain=$(_pri_of_clamped env)
    [ "$plain" != "$util" ] || false
    [ "$plain" != "$bg" ] || false
  fi
}

@test "(ii) a -c background CLAMP is LIFTABLE: a child's own -c utility reaches PRI 20" {
  if [ ! -x "$TP" ]; then skip "taskpolicy(8) absent on this host"; fi
  # This is the half that makes postland-verify.sh's own QOS array inert: cc-bats re-clamps out of it.
  local lifted
  lifted=$(_pri_of_clamped "$TP" -c background "$TP" -c utility)
  [ "$lifted" = "20" ] || false
}

@test "(iii) the -b TASK ROLE is NOT liftable: the same child's -c utility still reads PRI 4" {
  if [ ! -x "$TP" ]; then skip "taskpolicy(8) absent on this host"; fi
  # THE LOAD-BEARING ONE. `taskpolicy -b` is the mechanism launchd `ProcessType Background` applies.
  # If this ever reads 20, the plist edit in launchd/com.claude.postland-verify.plist is no longer
  # the lever LAND_PIPELINE_V2 §8 says it is — go re-derive that section, do not adjust this number.
  local pinned
  pinned=$(_pri_of_clamped "$TP" -b "$TP" -c utility)
  [ "$pinned" = "4" ] || false
}

@test "(iv) POSITIVE CONTROL for (iii): (ii) and (iii) differ, so the probe is not returning a constant" {
  if [ ! -x "$TP" ]; then skip "taskpolicy(8) absent on this host"; fi
  # (ii) and (iii) run the IDENTICAL child under two different parents. If the probe were blind to
  # the parent — reading its own band, or a fixed value — they would agree. They must not.
  local lifted pinned
  lifted=$(_pri_of_clamped "$TP" -c background "$TP" -c utility)
  pinned=$(_pri_of_clamped "$TP" -b "$TP" -c utility)
  [ -n "$lifted" ] || false
  [ -n "$pinned" ] || false
  [ "$lifted" != "$pinned" ] || false
}

@test "(v) the REAL corpus chain: cc-bats overrides the inherited -c background to PRI 20" {
  if [ ! -x "$TP" ]; then skip "taskpolicy(8) absent on this host"; fi
  if [ ! -x "$SHIM" ]; then skip "bin/cc-bats absent"; fi
  # The exact shape postland-verify.sh:2322 issues, with the bare `bats` resolved to the shim it
  # actually PATH-resolves to on this box. What is asserted is that the OUTER background clamp does
  # not survive — i.e. the corpus's band is decided downstream of that prefix, not by it.
  ( cd "$TMP/t" && nice -n 19 "$TP" -c background /bin/bash "$SHIM" "$TMP/t/slow.bats" ) >/dev/null 2>&1 &
  local root=$!
  /bin/sleep 3
  local pris
  pris=$(_descendant_pris "$root")
  kill "$root" 2>/dev/null || true
  wait "$root" 2>/dev/null || true
  [ -n "$pris" ] || false                                  # we must have observed something
  # every observed real-bats descendant pinned at the utility clamp — not merely "low"
  local bad
  bad=$(printf '%s\n' "$pris" | grep -c -v -E '^(20)?$' || true)
  [ "$bad" -eq 0 ] || false
}

@test "(vi) the postland plist SSOT declares no darwinbg ProcessType, and does demote explicitly" {
  # The band the scheduled lane gets is decided HERE and nowhere else. Two-sided: absence of the role
  # is not enough — a plist with neither the role nor a clamp would leave the runner at PRI 31, which
  # is the "you foregrounded the verifier" reading §8 explicitly declines. Assert the replacement too.
  local plist="$REPO/launchd/com.claude.postland-verify.plist"
  [ -f "$plist" ] || false
  run grep -qE '<string>Background</string>' "$plist"
  [ "$status" -ne 0 ] || false                             # the task role must be absent
  run grep -q 'taskpolicy -c utility' "$plist"
  [ "$status" -eq 0 ] || false                             # and an explicit demotion present
}
