#!/usr/bin/env bats
# spawn-lineage — the stamp that crosses a pane boundary, and the generation cap it feeds.
#
# WHY THIS SUITE EXISTS. Backlog bffbce207f12 asked for a per-lineage spawn bound and named its own
# first step a PROBE, because the design is vacuous if the environment does not cross a spawn. The
# probe (docs/research/spawn-lineage-probe-2026-08-11.md) found that it does not cross by itself and
# DOES cross under an explicit `--env`. Everything here pins that answer into the two sites that
# depend on it, so a later change cannot quietly return the mechanism to the vacuous state.
#
# EVERY CLAIM IS PAIRED WITH ITS OPPOSITE. A suite that only asserts refusals cannot tell a working
# cap from a gate that refuses everything, and one that only asserts admissions cannot tell a
# working cap from an inert one. So each refusal test has an admitting control on the same command,
# differing in exactly the axis under test (memory `control-must-replay-the-real-artifact`).
#
# Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/spawn-lineage.sh"
  K="$REPO/bin/it2-kitty"
  VB="$REPO/hooks/validate-bash.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_LINEAGE_STATE_DIR="$BATS_TEST_TMPDIR/lineage"
  export CC_LINEAGE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"

  # HERMETICITY, and it is not theoretical for THIS suite. Once this feature lands, every pane the
  # box creates carries CC_SPAWN_ROOT and CC_SPAWN_GEN — so a developer running bats inside such a
  # pane inherits a live stamp, and the "unstamped" cases would silently test the stamped path
  # instead. The sibling suite tests/it2-kitty-argv-spawn.bats records the identical trap for
  # CC_PANE_CMD (item 4c5eddc16c2d), where three tests went red only when bats ran inside a pane the
  # feature had created. Same class, unset for the same reason.
  unset CC_SPAWN_ROOT CC_SPAWN_GEN CC_LINEAGE_GATE CC_LINEAGE_MAX_GEN

  # ...and the SAME class one layer out, which scripts/test-hermeticity-lint.sh named on this
  # suite's first run — the half the comment above did not cover. bin/it2-kitty READS these two, and
  # this repo injects them into every pane it launches, so bats run from a fired pane would hand the
  # subject a caller's intent: :626 reads an ambient CC_PANE_CMD as its own, takes the pre-delivered
  # branch, and the legacy-typed stamp case would silently stop testing the typed path. Unset in
  # setup() rather than in fake_kitty(), because the library-only tests never call fake_kitty.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE

  # handoff-fire's capacity_gate() reads live machine load and this box lives above its ceiling; a
  # test naming self-close must not have its verdict decided by what else is running.
  export CC_FIRE_CAPACITY_GATE=off

  # Seams that do NOT resolve under $HOME — an absolute /tmp default (5a) or a bare name the subject
  # would EXECUTE off the operator's PATH (5b). Fixturing $HOME alone does not redirect either, so
  # they are pinned into the test tmpdir. An absent path is the right value: these sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
}

# ── the library: what a stamp means, and what an ABSENT one must not mean ────────────────────────

@test "unstamped process resolves to generation 0 and mints a well-formed root" {
  run bash -c ". '$LIB'; cc_lineage_resolve; printf '%s|%s|%s' \"\$CC_LINEAGE_GEN_CUR\" \"\$CC_LINEAGE_ROOT_CUR\" \"\$CC_LINEAGE_BASIS\""
  [ "$status" -eq 0 ]
  gen="${output%%|*}"; rest="${output#*|}"; root="${rest%%|*}"; basis="${rest#*|}"
  [ "$gen" = "0" ]
  # `p<pid>` when a claude ancestor is found, `u<pid>` when not — the suite must pass in both, so it
  # pins the FORMAT, never a value that depends on who ran it.
  printf '%s' "$root" | grep -qE '^[pu][0-9]+$' || false
  [ "$basis" = "unstamped" ] || [ "$basis" = "root-fallback" ]
}

@test "a stamped generation below the cap is admitted" {
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=1; . '$LIB'; cc_lineage_admit pane-spawn s1 'pane spawn'"
  [ "$status" -eq 0 ]
}

@test "a stamped generation AT the cap is refused" {
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=3; . '$LIB'; cc_lineage_admit pane-spawn s1 'pane spawn'"
  [ "$status" -eq 9 ]
}

@test "the cap is the only difference: gen 3 admits when the ladder is raised" {
  # The control for the test above. Same generation, same root — only CC_LINEAGE_MAX_GEN moves. If
  # this failed, the refusal above would be evidence of a gate that refuses regardless of the cap.
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=3 CC_LINEAGE_MAX_GEN=9; . '$LIB'; cc_lineage_admit pane-spawn s1 'pane spawn'"
  [ "$status" -eq 0 ]
}

@test "CC_LINEAGE_GATE=off admits a generation that would otherwise be refused" {
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=3 CC_LINEAGE_GATE=off; . '$LIB'; cc_lineage_admit pane-spawn s1 'pane spawn'"
  [ "$status" -eq 0 ]
}

@test "an UNPARSEABLE stamp admits, and says so with its own basis" {
  # The two not-a-number states must never collapse into the same value as "no stamp at all"
  # (memory `sensor-default-off-makes-blindness-the-shipping-path`): one means the carrier is
  # working and the pane is top-level, the other means the carrier is broken.
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=notanumber; . '$LIB'; cc_lineage_admit pane-spawn s1 'x'; printf '%s' \"\$CC_LINEAGE_BASIS\""
  [ "$status" -eq 0 ]
  [ "$output" = "gen-unparseable" ]
}

@test "an implausible generation admits rather than becoming a permanent wall" {
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=9999; . '$LIB'; cc_lineage_admit pane-spawn s1 'x'; printf '%s' \"\$CC_LINEAGE_BASIS\""
  [ "$status" -eq 0 ]
  [ "$output" = "gen-implausible" ]
}

@test "only a stamp the library itself parsed can refuse — a corrupt one never does" {
  # Pairs with the cap test: at the same numeric generation, a parseable stamp refuses and an
  # unparseable one admits. That is what makes the refusal a fact rather than a guess.
  run bash -c "export CC_SPAWN_ROOT=p123 CC_SPAWN_GEN=' 3'; . '$LIB'; cc_lineage_admit pane-spawn s1 'x'"
  [ "$status" -eq 0 ]
}

# ── the carrier contract: a child must be exactly one generation deeper ──────────────────────────

@test "child env inherits the root and increments the generation" {
  run bash -c "export CC_SPAWN_ROOT=p777 CC_SPAWN_GEN=2; . '$LIB'; cc_lineage_child_env | tr '\n' ' '"
  [ "$status" -eq 0 ]
  [ "$output" = "--env CC_SPAWN_ROOT=p777 --env CC_SPAWN_GEN=3 " ]
}

@test "child env of an unstamped process starts the ladder at 1, not 0" {
  # If this emitted 0 the ladder would never advance and the cap would be permanently unreachable —
  # the exact inert-gate failure the probe was run to avoid.
  run bash -c ". '$LIB'; cc_lineage_child_env | grep CC_SPAWN_GEN="
  [ "$status" -eq 0 ]
  [ "$output" = "CC_SPAWN_GEN=1" ]
}

@test "per-root width is COUNTED but never refuses" {
  # Width is instrumentation, not a gate: the bands are not separated yet. Charge it well past any
  # plausible threshold and the verdict must still be admit.
  run bash -c "export CC_SPAWN_ROOT=p555 CC_SPAWN_GEN=1; . '$LIB'
    for i in \$(seq 1 40); do cc_lineage_admit pane-spawn s1 'x' || exit 1; done
    cat \"\$CC_LINEAGE_STATE_DIR/p555.count\""
  [ "$status" -eq 0 ]
  [ "$output" = "40" ]
}

# ── the stamp site: bin/it2-kitty must put it on EVERY launch branch ─────────────────────────────

fake_kitty() {
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_RUNNER
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""
for a in "$@"; do
  case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac
done
case "$verb" in
  launch) echo 42 ;;
  ls)     echo '[{"id":1,"tabs":[{"id":1,"windows":[{"id":42,"title":"t","cwd":"/tmp","pid":9}]}]}]' ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

@test "split stamps the lineage onto the launch" {
  fake_kitty
  run env CC_SPAWN_ROOT=p900 CC_SPAWN_GEN=1 "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--env CC_SPAWN_ROOT=p900' "$KLOG" || false
  grep -q -- '--env CC_SPAWN_GEN=2' "$KLOG" || false
}

@test "the LEGACY typed split carries the stamp too" {
  # The reason the stamp is appended above the branch instead of inside one. The armed and
  # pre-delivered branches each build their own `--env … --` tail; the typed fallback builds none,
  # and it is the degraded path a runaway is most likely to be on. A stamp placed in either of the
  # other two would leave this one — and only this one — untracked.
  fake_kitty
  run env CC_KITTY_ARGV_SPAWN=0 CC_SPAWN_ROOT=p901 CC_SPAWN_GEN=1 "$K" session split -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--env CC_SPAWN_ROOT=p901' "$KLOG" || false
  grep -q -- '--env CC_SPAWN_GEN=2' "$KLOG" || false
}

@test "an unstamped caller still stamps its child at generation 1" {
  fake_kitty
  run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  grep -q -- '--env CC_SPAWN_GEN=1' "$KLOG" || false
  grep -qE -- '--env CC_SPAWN_ROOT=[pu][0-9]+' "$KLOG" || false
}

# ── the enforcement site: hooks/validate-bash.sh ─────────────────────────────────────────────────

# A non-worktree cwd on purpose: that is the population the lease gate abstains on, and the one this
# term exists to cover. It also isolates the two terms, so a deny here can only be this one.
vb() { # $1=command  → runs the hook, output in $output
  printf '{"tool_name":"Bash","cwd":"%s","session_id":"sid-1","tool_input":{"command":"%s"}}' \
    "$HOME" "$1" | "$VB"
}

@test "a pane spawn at the cap is denied by the hook" {
  run env CC_SPAWN_ROOT=p902 CC_SPAWN_GEN=3 bash -c "$(declare -f vb); VB='$VB'; HOME='$HOME'; vb '\$HOME/.claude/bin/it2-kitty session split -s 7'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
  printf '%s' "$output" | grep -q '"permissionDecision": "deny"' || false
}

@test "the same pane spawn below the cap is NOT denied" {
  run env CC_SPAWN_ROOT=p902 CC_SPAWN_GEN=1 bash -c "$(declare -f vb); VB='$VB'; HOME='$HOME'; vb '\$HOME/.claude/bin/it2-kitty session split -s 7'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

@test "the gate allows its own cure: self-close is never refused" {
  # A guard that forbids the remedy it prescribes re-emits forever (memory
  # `work-item-remedy-can-become-forbidden`). The refusal text tells a capped session to self-close.
  run env CC_SPAWN_ROOT=p902 CC_SPAWN_GEN=9 bash -c "$(declare -f vb); VB='$VB'; HOME='$HOME'; vb '\$HOME/.claude/scripts/handoff-fire.sh self-close --terminal'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

@test "a command that spawns no pane is untouched at any generation" {
  run env CC_SPAWN_ROOT=p902 CC_SPAWN_GEN=9 bash -c "$(declare -f vb); VB='$VB'; HOME='$HOME'; vb 'echo hello'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

# ── the OTHER enforcement site: hooks/agent-teams-enforce.sh ─────────────────────────────────────
#
# The surface the 2026-08-07 cascade actually crossed. A NAMED Agent call is turned into a new CLI
# session by the teammate-pane backend, which invokes bin/it2-kitty directly — so it never becomes a
# Bash tool call and the validate-bash term above is structurally blind to it (`ppid_comm=claude`
# 319/324 on those rows, against `ppid_comm=zsh` 16/16 on the session-invoked control). The two
# terms are siblings on two populations, not one term written twice.

ate() { # $1=extra tool_input json  → runs the Agent hook
  printf '{"tool_name":"Agent","cwd":"%s","session_id":"sid-1","tool_input":{"prompt":"do a thing"%s}}' \
    "$HOME" "$1" | "$ATE"
}

@test "a NAMED agent spawn at the cap is denied" {
  ATE="$REPO/hooks/agent-teams-enforce.sh"
  run env CC_SPAWN_ROOT=p903 CC_SPAWN_GEN=3 bash -c "$(declare -f ate); ATE='$ATE'; HOME='$HOME'; ate ',\"name\":\"w1\",\"model\":\"opus\"'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

@test "the same NAMED spawn below the cap is not denied" {
  ATE="$REPO/hooks/agent-teams-enforce.sh"
  run env CC_SPAWN_ROOT=p903 CC_SPAWN_GEN=1 bash -c "$(declare -f ate); ATE='$ATE'; HOME='$HOME'; ate ',\"name\":\"w1\",\"model\":\"opus\"'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

@test "an UNNAMED (in-process) subagent is never capped, even past the ladder" {
  # The scoping control, and the one that protects the tool's largest legitimate use. An unnamed
  # call mints no session, has no environment of its own, and cannot nest — so it cannot begin a
  # generation. If this ever goes red, read-only research fan-out has been refused for a thing it
  # is incapable of doing.
  ATE="$REPO/hooks/agent-teams-enforce.sh"
  run env CC_SPAWN_ROOT=p903 CC_SPAWN_GEN=9 bash -c "$(declare -f ate); ATE='$ATE'; HOME='$HOME'; ate ',\"subagent_type\":\"general-purpose\"'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}

@test "team_name is honoured as well as name — the runtimes spell it differently" {
  ATE="$REPO/hooks/agent-teams-enforce.sh"
  run env CC_SPAWN_ROOT=p903 CC_SPAWN_GEN=4 bash -c "$(declare -f ate); ATE='$ATE'; HOME='$HOME'; ate ',\"team_name\":\"wave-1\",\"model\":\"opus\"'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'SPAWN GENERATION CAP' || false
}
