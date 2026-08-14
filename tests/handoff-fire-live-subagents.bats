#!/usr/bin/env bats
# L1-b — a --recycle (and a self-close) must not SILENTLY kill this session's in-flight Agent-tool
# subagents. Plan: docs/plans/MASTER_SESSION_LIFECYCLE.md § L1-b.
#
# THE DEFECT, observed 2026-08-14 (chris-resume): a lead spawned an Agent-tool subagent, then
# recycled its own pane. `--recycle` types /exit, which interrupts the in-flight turn and SIGKILLs
# the process group; a subagent runs IN-PROCESS, so it died mid-run with its deliverable unwritten.
# No pre-flight refusal, no ledger row, no line in the successor's brief — the successor learned of
# the loss only because the human operator remembered.
#
# RED-PROOF, measured (pristine = the pre-change script recovered from the PINNED sha 4e39debcf, via
# HF_OVERRIDE; runbook below): cases 1, 2, 3, 4, 5 and 8 FAIL there — 6 red, 2 green. On that tree
# `--allow-live-subagents` is not a flag at all, there is no `subagents:` field in the dry-run
# readout, no refusal of any kind and no successor-brief trailer: the recycle proceeds and says
# nothing, which is the whole defect.
#   · Case 6 PASSES on both trees BY DESIGN — the POSITIVE CONTROL. It pins that a session with no
#     in-flight subagent is not slowed, warned or refused, so this suite cannot degrade into an alarm
#     that fires on every recycle (memory: alarm-polarity-and-attention-budget).
#   · Case 7 also passes on pristine, but VACUOUSLY — it asserts the absence of a refusal, and on a
#     tree with no gate nothing refuses. It is a behaviour pin for the kill switch on the FIXED tree,
#     not a red-proof case, and it is named here so nobody later reads its green as evidence.
#
# 🚨 RUN THE PRISTINE COPY FROM THE REPO'S OWN scripts/ DIR, never /tmp. handoff-fire.sh resolves its
# libs relative to its own location, so a copy in /tmp dies at `cc_acct_name_for_dir_basename:
# command not found` and every case reds — including the positive control. The first proof of this
# suite read 8/8 RED that way and looked like a perfect red-proof; it was measuring the copy's broken
# lib resolution, and it would have "proved" the guard on a tree that already had it (memory:
# prescribed-repro-weaker-than-the-harness — a repro is an ENVIRONMENT claim before it is a logic one).
#
#   git show 4e39debcf:scripts/handoff-fire.sh > scripts/.hf-pristine-tmp.sh
#   HF_OVERRIDE="$PWD/scripts/.hf-pristine-tmp.sh" ~/.claude/bin/cc-bats --formatter pretty \
#     tests/handoff-fire-live-subagents.bats ; rm -f scripts/.hf-pristine-tmp.sh
#
# THE FIXTURE MIRRORS THE MEASURED ON-DISK SHAPE, not an invented one. Claude Code writes, per
# subagent, BOTH of:
#   <config>/projects/<slug>/<sid>/subagents/agent-<id>.jsonl       (the running transcript)
#   <config>/projects/<slug>/<sid>/subagents/agent-<id>.meta.json   ({agentType,description,toolUseId})
# and the completion discriminator is the LAST QUOTED stop_reason in the .jsonl: "end_turn" once the
# agent has stopped, "tool_use" (or absent) while it is live. Measured 2026-08-14 on a real session
# running four subagents — three finished, one still in flight — which is the positive and negative
# control in one sample. The streaming `"stop_reason":null` partials are why the predicate takes the
# last QUOTED value rather than the last line.

setup() {
  # Both terms of the single capacity_gate() exit 9 — it reads live loadavg and this box sits well
  # above the ceiling (test-hermeticity-lint rule 2 requires these in the setup BODY).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$SRC/scripts/handoff-fire.sh}"
  # PHYSICAL $HOME — $BATS_TEST_TMPDIR lives under a /var → /private/var symlink and the script
  # resolves paths with `pwd -P`. Assigned in TWO steps on purpose: `export HOME="$(…)"` is SC2155
  # (the bats-shellcheck ratchet) while the hermeticity ratchet matches `export HOME=` or
  # `HOME="$BATS…`, so the one-liner that satisfies either gate reds the other.
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  mkdir -p "$HOME/.claude/bin"
  # Seams that must NOT resolve under the fixture $HOME. Every one of these sensors fails open on a
  # miss, so an absent path is the right value.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # The it2 shim only has to EXIST (a dry run never invokes it); handoff-fire probes it with sed.
  printf 'REAL_IT2="/nonexistent/it2"\nPYTHON_BIN="/usr/bin/python3"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"

  # BARE pane id, no `w0t0p0:` prefix. cc_sid_for_pane keys the registry row on the pane id VERBATIM
  # as handed to --session-id — it does not strip a `wNtNpN:` prefix — so a prefixed fixture writes
  # its row under one name and is looked up under another, and every case silently degrades into the
  # fail-open branch (case 5's state) while still exiting 0. That is a vacuous pass, not a green.
  PANE="FIXTUREPANE"
  SID="11111111-2222-3333-4444-555555555555"
  # The pane→sid hop the gate makes: cc_sid_for_pane reads this registry row. Without it the gate
  # takes its documented fail-open branch, which is a DIFFERENT case (pinned by case 5).
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"session_id":"%s","paneUUID":"%s"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  # The projects-root seam (same shape as CC_SESSIONS_DIRS): the gate globs <root>/*/<sid>.
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"
  SADIR="$CC_PROJECTS_DIRS/-fixture-slug/$SID/subagents"
  mkdir -p "$SADIR"

  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — live-subagent fixture payload." > "$PAYLOAD"
}

# mkagent <id> <live|done> <description> — one subagent, in the measured on-disk shape.
mkagent() {
  local id="$1" state="$2" desc="$3"
  printf '{"agentType":"general-purpose","description":"%s","toolUseId":"toolu_%s","spawnDepth":1}\n' \
    "$desc" "$id" > "$SADIR/agent-$id.meta.json"
  # A couple of ordinary records, then the terminal one. The trailing `"stop_reason":null` partial is
  # deliberate on BOTH branches: it is what the live harness actually flushes last, and it is the
  # reason the predicate reads the last QUOTED stop_reason instead of the last line.
  {
    printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}\n'
    printf '{"type":"user","message":{"role":"user"}}\n'
    if [ "$state" = "done" ]; then
      printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}\n'
    else
      printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}\n'
    fi
    printf '{"type":"assistant","message":{"role":"assistant","stop_reason":null}}\n'
  } > "$SADIR/agent-$id.jsonl"
}

# fire <args…> — the real script as a RECYCLE of the fixture pane, ambient gates pinned off.
# --account IS PINNED, and that is hermeticity rather than tidiness. With no explicit account the
# recycle pre-pass derives one from $CLAUDE_CONFIG_DIR — which exists on a desk shell and is GONE
# under the off-box runner's `env -i` (scripts/offbox-run.sh:131), so the script exits 1 at "can't
# derive this session's account" BEFORE it ever reaches the readout these cases assert. Every case
# that expects a rc-0 dry run then fails there for a reason that has nothing to do with the gate,
# while the three refusal cases keep passing because they exit 4 earlier — a suite that is green on
# one machine and red on another, which is exactly the ambient coupling the off-box gate exists to
# catch (memory: hermetic-in-stubs-not-in-interpreter).
fire() {
  run env CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      bash "$HF" --prompt-file "$PAYLOAD" --session-id "$PANE" --recycle --account next "$@"
}

@test "1 a recycle with a live subagent is REFUSED, and the refusal names the agent" {
  mkagent aaaa1111 live "rewrite the ironsession module"
  fire --dry-run
  [ "$status" -eq 4 ] || { echo "expected exit 4, got $status: $output"; false; }
  echo "$output" | grep -q "recycle REFUSED" || false
  echo "$output" | grep -q "1 Agent-tool subagent(s)" || false
  echo "$output" | grep -q "rewrite the ironsession module" || false
}

@test "2 the refusal names the PARTIAL TRANSCRIPT that survives the kill" {
  mkagent aaaa1111 live "rewrite the ironsession module"
  fire --dry-run
  [ "$status" -eq 4 ] || { echo "expected exit 4, got $status: $output"; false; }
  # The whole point of the RECORD half: the deliverable is unreachable, not absent.
  echo "$output" | grep -q "partial transcript (survives this session)" || false
  echo "$output" | grep -q "agent-aaaa1111.jsonl" || false
}

@test "3 a FINISHED subagent does not refuse — only in-flight ones count" {
  # The negative control for the oracle itself. Without this, a gate that refused on the mere
  # PRESENCE of a subagents/ dir would pass case 1 while being useless (every session that ever
  # spawned an agent could then never recycle).
  mkagent bbbb2222 "done" "a subagent that already returned"
  fire --dry-run
  [ "$status" -eq 0 ] || { echo "expected 0, got $status: $output"; false; }
  echo "$output" | grep -q "subagents: none in flight" || false
}

@test "4 --allow-live-subagents proceeds, LOUDLY, and the dry-run readout says what dies" {
  mkagent aaaa1111 live "rewrite the ironsession module"
  mkagent cccc3333 live "second in-flight agent"
  mkagent bbbb2222 "done" "already returned"
  fire --dry-run --allow-live-subagents
  [ "$status" -eq 0 ] || { echo "expected 0, got $status: $output"; false; }
  echo "$output" | grep -q "proceeding with 2 IN-FLIGHT subagent(s)" || false
  # Exactly 2 — the finished one must not be counted into the loss.
  echo "$output" | grep -q "subagents: 2 IN FLIGHT — WOULD BE KILLED" || false
}

@test "5 an UNRESOLVABLE session id fails OPEN but never silently" {
  # Fail-closed here would deadlock every recycle on a box with a stale registry — a strictly worse
  # outage than the loss the gate prevents. So it proceeds AND announces that it could not check.
  mkagent aaaa1111 live "would have been caught"
  rm -f "$CC_REGISTRY_DIR/${PANE##*:}.json"
  fire --dry-run
  [ "$status" -eq 0 ] || { echo "expected 0, got $status: $output"; false; }
  echo "$output" | grep -q "in-flight-subagent check SKIPPED" || false
}

@test "6 POSITIVE CONTROL: a session that never spawned a subagent is untouched" {
  # Passes on pristine trunk too, by construction — this is what stops the suite from certifying an
  # alarm that fires on every recycle. No subagents/ dir at all: the commonest case by far.
  rm -rf "$CC_PROJECTS_DIRS"
  fire --dry-run
  [ "$status" -eq 0 ] || { echo "expected 0, got $status: $output"; false; }
  # `if …; then …; fi`, never `grep -q … && { …; false; }`: bats runs bodies under `set -eET`, and a
  # non-last element of an `&&` list is EXEMPT from errexit — so the `&& { false; }` form is a DEAD
  # assertion here and a spurious failure when it happens to land last (both were observed writing
  # this suite; scripts/bats-assert-liveness.py exists for exactly this).
  if echo "$output" | grep -q "recycle REFUSED"; then echo "refused a clean session"; false; fi
  echo "$output" | grep -q "surface:  (recycle" || false
}

@test "7 the env kill switch disables the gate for blind callers" {
  # hooks/waiting-recycle.sh fires --recycle with `|| true` into /dev/null and then TELLS THE MODEL
  # the recycle fired. A refusal it cannot read is a wedge, not a no-op, so a blind caller needs a
  # pre-arranged disposition rather than a refusal.
  mkagent aaaa1111 live "would have been caught"
  run env CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      CC_RECYCLE_SUBAGENT_GATE=off \
      bash "$HF" --prompt-file "$PAYLOAD" --session-id "$PANE" --recycle --account next --dry-run
  [ "$status" -eq 0 ] || { echo "expected 0, got $status: $output"; false; }
  if echo "$output" | grep -q "recycle REFUSED"; then echo "kill switch did not disarm the gate"; false; fi
}

@test "8 self-close is gated too — the same loss, the other door" {
  # A self-close ends the session exactly as a recycle does, so it kills in-flight subagents exactly
  # as a recycle does. It already refuses over live TEAMMATES; that gate is structurally blind to
  # in-process subagents, which have no pid, no argv and no tty for its ps oracle to find.
  mkagent aaaa1111 live "rewrite the ironsession module"
  # --allow-origin-close because the ORIGIN gate fires FIRST (exit 2) and a fixture pane has no
  # fired-peer stamp. That ordering is deliberate upstream and is not what this case is about; the
  # override gets us past it to the gate under test, and nothing else in the run depends on it.
  run env CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off \
      bash "$HF" self-close --terminal --session-id "$PANE" --dry-run --allow-origin-close
  [ "$status" -eq 4 ] || { echo "expected exit 4, got $status: $output"; false; }
  echo "$output" | grep -q "self-close REFUSED" || false
  echo "$output" | grep -q "rewrite the ironsession module" || false
}
