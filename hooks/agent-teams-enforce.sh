#!/bin/bash
# PreToolUse hook on Agent tool — enforces Agent Teams for implementation tasks.
#
# DENY: Background subagents with implementation keywords (code-writing) are blocked.
#       Model receives clear instructions to retry with team_name set.
# ALLOW+NUDGE: Foreground agents without team_name get a reminder.
# ALLOW SILENT: Agents with team_name, known read-only types, research prompts.

set -uo pipefail

# PATH hardening — scripts/unattended-path-lint.sh governs this line.
# The allowlist read below resolves `yq` by bare name, and yq is Homebrew-only. A hook inherits its
# Claude Code process's PATH, which for a spawned session need not carry Homebrew, so that read can
# silently return nothing and fall through to the hardcoded default on the next line. That default
# is a MODEL ID: the SSOT exists precisely so the allowlist tracks model-config.yaml, and a fallback
# firing in production means the anti-drift read never happened and the value freezes at whatever
# was hardcoded. APPEND, never prepend — this can only add reach, never change resolution order.
PATH="$PATH:$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin"
export PATH

command -v jq &>/dev/null || exit 0

INPUT=$(cat)

# Extract Agent tool parameters
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // empty')
RUN_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // empty')

# ── DUPLICATE-WORKER ADMISSION ────────────────────────────────────────────────────────────────
# The SECOND consumer of the duplicate-worker lease (backlog 5deb4418a648). The first
# (hooks/check-edit-boundary.sh, PreToolUse|Write|Edit|MultiEdit) stops a duplicate from CORRUPTING
# the worktree. This one stops it from SPENDING THE FLEET — a different cost, on an earlier event.
#
# WHY A SECOND POINT AT ALL. scripts/lib/worker-claim-gate.sh sited itself at the write because the
# repo's own incident log says *"the collision becomes real when either starts writing"*. That is
# true of damage to the REPO and false of damage to the BUDGET, and the budget is what the filed
# item measures: *"one full worker slot plus its subagents"*, on a duplicate that *"spawned 5
# analysis subagents before detecting the duplication"*. The gate's own header records the extreme
# of the same shape — *"the population arrived by Agent-tool fan-out instead — 224 spawns over 3
# generations"*. Fan-out PRECEDES the first write in a worker's normal order (orient, then edit), so
# a write-only gate is by construction blind to the whole cost until after it has been paid.
#
# WHY HERE AND NOT AT THE FIRE — the filed item blamed the dispatcher, and the journals acquit it.
# Reconstructed 2026-08-10 from the surviving logs of the 2026-08-07 incident on item 149789b69fc4:
# `logs/dispatch-fires.log` holds exactly ONE record for that item (22:20:54Z, pid 17968, matching
# its single ledger claim at 22:20:16Z), and `cc-fired/by-cwd/` was never overwritten, so nothing
# re-entered handoff-fire's front door for that worktree. One claim, one fire, one worker. What the
# item counted as a second dispatch — "worker 13189 fired 22:20:40Z (+24s)" — is that same worker's
# own process start, i.e. fire latency, not a second fire.
#
# The duplicates were a RECURSIVE TEAMMATE CASCADE. `logs/pane-spawns.jsonl` records the lineage:
# the dispatched worker (claude 13189, pane 499) split six panes; one of those (claude 51435) split
# six more; one of THOSE became the item's "worker 34512" at 22:28:27Z, which split five more —
# three generations, 91+ full CLI sessions in ONE worktree in ~38 minutes. Every row carries
# `chain:"it2-kitty"`, bare, where a real fire stamps `chain:"handoff-fire.sh>it2-kitty"`: these
# spawns go around the door that does the claim bookkeeping. That is the item's own sentence — "the
# lease cannot refuse what never calls claim" — with the actor corrected from the dispatcher to the
# Agent tool, which is the surface this hook already sits on.
#
# WHY THE TWO CAPS BELOW CANNOT SEE IT, though they were built for the same 224-spawn blow-up.
# `CC_SPAWN_MAX_DEPTH` reads the harness's own `spawnDepth` and `CC_SPAWN_MAX_PER_SESSION` charges a
# per-SESSION counter — and every step of this cascade crosses a session boundary. A pane-backed
# teammate is a new CLI session: it has no parent agent meta, so it "reads as the top level" (:238)
# at depth 0, with a fresh budget of 60. Both counters RESET at exactly the edge the cascade
# traverses, so 91 sessions can each stay perfectly inside a cap of 2 and 60. The item lease does
# not reset — it is one id across all 91 — which is why identity is the instrument that sees this
# and quantity is not. The caps bound one lineage's width; this bounds whether the lineage was ever
# entitled to exist.
#
# The consequence is that the recursion terminates at generation 2: the lease HOLDER still fans out
# normally (it reclaims as `noop-already-ours`), and every session it spawns into its own worktree
# is refused the moment IT tries to fan out further. Deliberately not stronger — refusing the
# holder's own first generation would break ordinary Agent Teams use, and the runaway measured here
# is the recursion, not the first fan-out.
#
# Keying on the lease rather than on a list of spawn sites is also what keeps this from becoming a
# denylist over spellings of "a session arrives" (memory `denylist-enumerates-spellings-not-the-
# class`): a same-day census found four other paths that fire with no claim, and the largest
# producer has no shell file to patch at all, because it is the model calling `Agent`. Every arrival
# path, present and future, converges on one observable — a session running in `wt-<id>` that does
# not hold the lease — and that is what the library already keys on.
#
# WHY IT PRECEDES THE CAPACITY TERM BELOW, which is otherwise this hook's first act:
#   · COST — the not-a-worker branch is forkless by construction (parameter expansion only), and
#     the overwhelming majority of Agent calls on this box are not in a dispatch worktree. Capacity
#     forks to measure the machine. Cheapest correct refusal first.
#   · TRUTH — capacity's refusal is TRANSIENT ("shed and retry, it releases on budget expiry"); this
#     one is TERMINAL ("you are the duplicate, stand down"). Handing a duplicate the transient
#     sentence tells it to come back, when the correct answer is that it must never run. The
#     identity fact outranks the resource fact, so it is answered first.
#
# NO REFUSAL BUDGET, inherited deliberately from the library and NOT from capacity-admit beside it:
# a capacity refusal denies a machine state that admitting can relieve, whereas admitting here MINTS
# the second worker this exists to prevent. The bound lives in the lease (incumbent dies, or
# `cc-backlog reap` ages the claim out), which is the only thing that knows when the fact stops
# being true. Same resolution order and same fall-through contract as the capacity term below —
# symlink-resolved sibling FIRST, so the term goes live on the trunk fast-forward rather than
# waiting behind a deploy it cannot trigger (the deployed-layer-bootstrap-circle).
_ateh_wcg_self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _wcg in "$(dirname "$_ateh_wcg_self")/../scripts/lib/worker-claim-gate.sh" \
            "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/worker-claim-gate.sh" \
            "${HOME:-}/.claude/scripts/lib/worker-claim-gate.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_wcg" ] && . "$_wcg" 2>/dev/null && break
done
if command -v cc_worker_claim_admit >/dev/null 2>&1; then
  _ateh_cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$_ateh_cwd" ] || _ateh_cwd="$PWD"
  CC_WCLAIM_SID="$(printf '%s' "$INPUT" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')" \
    cc_worker_claim_admit agent-tool "$_ateh_cwd" "${SUBAGENT_TYPE:-subagent} spawn" || {
      jq -n --arg r "$(cc_worker_claim_reason)" \
            --arg i "$(cc_worker_claim_item)" \
            --arg h "$(cc_worker_claim_holder)" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("DUPLICATE WORKER — subagent spawn refused. This session does not hold the lease on item \($i). \($r). Another LIVE session (\($h)) is doing this work right now, and fanning out multiplies the duplication instead of discovering it: one dispatch that fanned out from a duplicate reached 224 spawns over 3 generations, and a second reached 5 analysis subagents before it noticed it was the third worker on one item. DO NOT retry, and DO NOT re-word the prompt — the refusal is a FACT about a live lease, not a throttle, and it is read from your working directory, not from your text. STAND DOWN: stop work, and retire this pane with `$HOME/.claude/scripts/handoff-fire.sh self-close --terminal` (it refuses a dirty tree, which is the intended safety). If you believe the incumbent is DEAD, do not force it — the lease self-releases the moment its claimer dies or `cc-backlog reap` ages it out, and the next spawn is then admitted automatically. Override for this session only: CC_WCLAIM_GATE=off. Rule: backlog 5deb4418a648, docs/plans/CONCURRENCY_PROGRAM.md#s4.")
        }
      }'
      exit 0
    }
else
  # Inertness is LOUD, never a silent admit — and LOUD MEANS THE LEDGER, verbatim from the capacity
  # term's reasoning below: this hook runs on EVERY Agent call, so stderr would be noise that gets
  # tuned out, and it would corrupt this hook's own JSON contract (bats merges stderr into $output).
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
    '{ts:$ts,hook:"worker-claim-gate",sid:"?",disposition:"abstained",reason:"duplicate-worker",
      gate:"worker-claim-gate",verdict:"admit",basis:"absent",caller:"agent-tool",
      what:"subagent spawn",detail:"scripts/lib/worker-claim-gate.sh unreachable — spawn UNGATED for duplicate workers"}' \
    >> "${CC_WCLAIM_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null || true
fi

# ── MACHINE-CAPACITY ADMISSION ────────────────────────────────────────────────────────────────
# MACHINE_CAPACITY_V2 §12.1 measured the coverage of the one hardware term in the tree and found
# the `Agent` tool BYPASSES it — and named that the one that matters most: *"it is the highest-
# volume spawn surface. Its two PreToolUse hooks bind policy (agent-teams-enforce.sh) and frontier
# budget (frontier-spawn-gate.sh), never hardware. So the spawn-cap PATTERN is proven here; it is
# keyed on the wrong resource."* This is that pattern, keyed on the right one.
#
# WHY IT LIVES IN THIS HOOK RATHER THAN A NEW ONE. A new hook file needs a new settings.json entry,
# which is a C10 operator hand-step, which lands in the pending-activation queue — where 11 scripts
# are currently ROTTING >24h unrun. A gate that ships INERT is the generator this repo documented
# on 2026-08-07 (docs/research/inertness-generator-2026-08-07.md): eight analyses reached correct
# conclusions that changed nothing because the conclusion never reached an ENFORCING store. This
# hook is ALREADY registered on PreToolUse|Agent, so the term goes live on the trunk fast-forward
# with the rest of the diff. Enforcement rides the deploy; it does not wait behind a human.
#
# WHY THE LOAD TERM IS OFF HERE — a deliberate per-caller policy, not a weakened gate. §8.5.7
# measured loadavg swinging 2.05x at CONSTANT session count (dominated by the TUI renderer,
# WindowServer, XProtect), and §12.2 measured 2.16/core — over the 2.0 ceiling — on a box with 13
# sessions, 24 GB free and 0 B compressor, i.e. perfectly healthy. Binding THAT proxy to the
# highest-volume spawn surface is precisely the fleet-wide refusal §12.2 refuted. Memory headroom
# is the sheddable, session-attributable quantity §8.5.2's retraction asked for: a subagent's
# footprint IS reclaimable by not spawning it, so this term's refusal can actually change what it
# reads — which the loadavg term's cannot.
#
# BOUNDED (§9 of the inertness-generator doc, the narrowed law): CC_ADMIT_BUDGET consecutive
# refusals, then the next evaluation ADMITS and pages. A wave can be throttled; it can never be
# permanently blocked by this.
#
# ABSENT LIBRARY, OR ADMIT ⇒ FALL THROUGH, never exit. Every policy check below this line
# (model allowlist, brief-size cap, delivery-contract, impl-keyword deny) must still run: a
# capacity library that went missing must not be able to silently disarm Agent Teams enforcement.
#
# RESOLUTION ORDER — the SYMLINK-RESOLVED sibling FIRST, and that ordering is the difference between
# a gate that works and a gate that waits. ~/.claude/hooks/*.sh are symlinks into the checkout, so
# resolving $0's link reaches the repo's own scripts/lib/ and the term goes live the moment the file
# does. A $CLAUDE_CONFIG_DIR-first lookup would find nothing until install.sh re-globs the new file
# on the next deploy — i.e. the gate would ship ABSENT and stay that way behind a deploy it cannot
# trigger, which is the deployed-layer-bootstrap-circle. (Verified: this is not hypothetical — the
# config-dir path does not exist until deploy, so config-dir-first meant ABSENT on every spawn.)
_ateh_self="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _ca in "$(dirname "$_ateh_self")/../scripts/lib/capacity-admit.sh" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh" \
           "${HOME:-}/.claude/scripts/lib/capacity-admit.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_ca" ] && . "$_ca" 2>/dev/null && break
done
#
# ── §W3 item 3 (2026-08-12): THE LOAD TERM STAYS OFF, AND ITS PLACE IS TAKEN BY A CHARGED TERM ────
# The item asks to "re-enable the load term for the Agent tool, OR charge its panes somewhere", and
# names why the first half must not be done naively: the reasoning above is sound for a THRESHOLD, so
# re-adding a loadavg ceiling here would re-commit the fleet-wide refusal §12.2 refuted. What was
# missing is that NOTHING ELSE was charged either — this hook gated on memory headroom ALONE, so the
# highest-volume spawn surface on the box contributed to no count anywhere.
#
# It now charges the term that IS stable enough to be charged: the `ps`-derived live SESSION-TREE
# census, against a ceiling of 54 — pool-floor.sh's measured machine floor, replacing the `~15`
# folklore that no code ever read (scripts/lib/spawn-presence.sh § THE CEILING). A session count does
# not swing 2.05x at constant session count the way loadavg does — that is definitionally impossible —
# and unlike loadavg it is attributable (each spawn adds exactly one tree) and sheddable (closing the
# pane removes it). Both new refusals arrive through cc_capacity_admit's existing budget, so a wave can
# be throttled and can never be permanently blocked.
#
# WAVE D ADDED TWO MORE TERMS AND THIS PATH INHERITS BOTH BY DEFAULT (backlog 1c45598a91be), which
# is deliberate rather than incidental: `segments` and `active` are switchable exactly like the load
# term, and this is the ONE surface where leaving them ON matters most. The Agent tool is the
# highest-volume spawn path on the box, and axis 10's F3 names the failure it produces — a wave that
# fans out while other sessions are mid-turn is how "~10 active" gets breached, and no term keyed on
# RESIDENCY can see it. The load term stays off here for the reason above; `active` is the honest
# replacement for what the load term was reaching for, measured in the dimension that is
# attributable to what is being spawned.
#
# CC_ADMIT_SID IS WHAT MAKES THE RESERVE FAIR, and it is why the session id is passed. The reserve is
# waived entirely when the SPAWNING session is itself operator-driven (`presence:"self"`): an operator
# fanning out is the operator spending their own slots, and a gate that refused that would be the
# reserve turned against its beneficiary. Autonomy driving itself while the operator works elsewhere is
# the population this yields — which is the DoD of the wave, stated as a mechanism.
if command -v cc_capacity_admit >/dev/null 2>&1; then
  _ateh_sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
  if ! CC_ADMIT_LOAD_TERM=off CC_ADMIT_SID="${_ateh_sid:-?}" \
       cc_capacity_admit agent-tool "${SUBAGENT_TYPE:-subagent} spawn"; then
    jq -n --arg r "$(cc_capacity_admit_reason)" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("MACHINE CAPACITY — subagent spawn refused. \($r). Read the term named in that sentence: `headroom` means the box is genuinely out of reclaimable memory (free+speculative+inactive+purgeable is what a new process can take WITHOUT swapping; below the floor the whole box swaps and every live session slows). `segments` means the VM compressor is already deep in a burst — the term that saw 100% of the segment limit at the panic while headroom still read 29.79 GB and admitted; adding a session there adds demand to the one dimension that actually kills the box. `active` means too many sessions are MID-TURN right now (ceiling 8): residency is nearly free, but 2.5-5 runnable threads arrive with every ACTIVE session, so this is the ceiling the whole design point rests on — the fix is to let the running turns finish, not to close panes. `reserve-headroom`, `reserve-active` or `reserve-slots` means something different and more specific — the box had room, and this spawn is YIELDING to the operator, who is at the keyboard right now. That reserve is a floor of local capacity autonomy may never take (BACKLOG_SELF_DRAINING §W3): it is waived automatically for a session the operator is driving, so if you are seeing it, this session is autonomy. DO NOT retry in a loop — every refusal here is BOUNDED and releases itself after CC_ADMIT_BUDGET consecutive refusals (it then admits and pages), so a retry storm only spends the budget that protects you. Instead: shed first (close finished panes, let the running wave drain, reduce the fan-out width), then spawn. Run this work SERIALLY on the lead if it cannot wait — that is the correct answer while the operator is working. Override for one spawn: CC_ADMIT_GATE=off. Lower the bar: CC_ADMIT_MIN_HEADROOM_GB=<n>, CC_ADMIT_MAX_SEGMENT_PCT=<n>, CC_ADMIT_ACTIVE_CEILING=<n>. Drop the reserve for one spawn: CC_ADMIT_RESERVE_TERM=off. Rule: MACHINE_CAPACITY_V2 §12.1 + §W3 (backlog 8ae4b508f274) + Wave D (backlog 1c45598a91be).")
      }
    }'
    exit 0
  fi
else
  # Inertness is LOUD, never a silent admit (§12.2's rule for capacity_gate, applied verbatim) —
  # but LOUD HERE MEANS THE LEDGER, NOT stderr. This hook runs on EVERY Agent call on the box, so a
  # stderr line would print on every spawn in every session: noise that gets tuned out, which is the
  # opposite of loud (memory `alarm-polarity-and-attention-budget` — an alarm that always fires
  # carries the same zero bits as one that cannot). It also lands in the hook's own output stream,
  # where it corrupts the JSON contract: it broke 6 cases in tests/agent-teams-enforce.bats with a
  # jq parse error, because bats' `run` merges stderr into $output.
  # A row in the IDL is greppable, timestamped, damped by nature, and lands in the SAME store the
  # gate's own verdicts do — so one query answers "was the Agent path gated?" across both states.
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
    '{ts:$ts,hook:"capacity-admit",sid:"?",disposition:"abstained",reason:"capacity",
      gate:"capacity-admit",verdict:"admit",basis:"absent",caller:"agent-tool",
      what:"subagent spawn",detail:"scripts/lib/capacity-admit.sh unreachable — spawn UNGATED for hardware"}' \
    >> "${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null || true
fi

# ── SPAWN BUDGET + DEPTH CAP ──────────────────────────────────────────────────────────────────
# The fleet-footprint invariant: NO COMPONENT OWNS ITS OWN TEARDOWN, so nothing bounds a fan-out
# either. One historical dispatch reached 224 Agent spawns / 167 sessions with no cap ANYWHERE —
# and that horde is the measured ignition of the kernel watchdog panics (4 in 7 days to
# 2026-08-09; docs/research/crash-rootcause-2026-08-09.md §1). A panic destroys every live
# session at once, so this is the highest-blast-radius gate in the tree.
#
# WHY HERE, AND WHY ABOVE EVERY ALLOW PATH. This is THE actuator: the one PreToolUse hook on the
# Agent tool, already registered, so the cap goes live on the trunk fast-forward rather than
# waiting behind a C10 operator step (the inertness generator — an advisory cap is exactly what
# let 224 spawns happen). It sits above the read-only-type skip (Explore|Plan|…) and above both
# research branches ON PURPOSE: a 224-wide fan-out is overwhelmingly *research* subagents, so a
# cap placed below those skips would be blind to the only shape that has ever caused the harm.
#
# TWO TERMS, AND ONLY ONE OF THEM IS LOAD-BEARING TODAY.
#
#  1. BUDGET, keyed on `.session_id`. MEASURED 2026-08-09: an in-process Agent subagent does NOT
#     get its own session_id — its transcript rows and its PostToolUse audit lines both carry the
#     LEAD's id (`~/.claude/logs/bash-execution.log` tags a subagent's Bash calls with the lead's
#     sid). That makes a session-keyed counter aggregate lead + every descendant into ONE bucket,
#     which is useless for a depth and exactly right for a budget: the whole fan-out charges the
#     same account, so 224 is reachable only by spending 224. This term binds unconditionally.
#
#  2. DEPTH, derived from `.transcript_path`. The harness ALREADY computes it: a subagent's
#     transcript lives at <session-dir>/subagents/agent-<id>.jsonl beside an
#     agent-<id>.meta.json carrying {"agentType","toolUseId","spawnDepth"}. So depth is a READ,
#     not an invention — `CC_SPAWN_DEPTH`-style env propagation (MEASURED 2026-08-11, see below;
#     it is not merely unnecessary here, it is impossible here) is not needed. The ONE unknown is
#     whether a nested hook
#     invocation is handed the SUBAGENT's transcript_path or the LEAD's. Nothing in this repo
#     logs transcript_path, so it cannot be answered from disk today.
#
#     That unknown is INSTRUMENTED, NEVER ASSUMED. Every evaluation writes one IDL row carrying
#     the observed transcript shape and derived depth, so the first real nested spawn after this
#     lands answers the question permanently, in a store, with no further probe. If the answer is
#     "the lead's path", this term is silently inert — and the rows say so out loud rather than
#     letting a depth cap be believed into existence. The budget term is unaffected either way.
#     (memory: sensor-default-off-makes-blindness-the-shipping-path — one value must never mean
#     both "answered no" and "could not ask", so basis is `depth-read` vs `depth-unavailable`.)
#
#     ── ANSWERED 2026-08-11 (backlog f2617b0480df), AND THE ANSWER IS NEITHER BRANCH ────────────
#     The instrumentation did its job: 43 evaluations across 15 sessions, 2026-08-10T08:10:21Z →
#     2026-08-11T02:05:06Z, read from the IDL *and its gzip archives*. Every single one is
#     `basis=depth-toplevel`, depth 0, transcript = a session path. Not one subagent path.
#
#     The reason is not that hooks are handed the lead's transcript. It is that THERE IS NO NESTED
#     HOOK INVOCATION TO HAND ANYTHING TO: Claude Code does not expose the Agent tool to subagents
#     at all. Probed directly — a `general-purpose` subagent instructed to make one Agent call got
#     back "No such tool available: Agent. Agent is disabled for this session, in subagents as well
#     as here." Corroborated on disk, independently and predating the probe:
#     ~/.claude/agents/deep-research.md:105 ("Claude Code harness silently does not expose the
#     Agent tool to subagents") and CLAUDE.md § Research Subagents ("nested fan-out is not
#     operational in stock Claude Code").
#
#     So THIS TERM'S POPULATION IS EMPTY BY CONSTRUCTION, and `depth-toplevel` at 43/43 is not a
#     measurement that the fan-out is shallow — it is the only value reachable. Read it that way.
#     The term STAYS: it costs nothing, it is the correct cap the day nesting returns (deep-
#     research.md:128 records `--teammate-mode tmux` restoring the Agent tool to teammates, GH
#     #31977), and removing it would delete a guard that is right rather than wrong. But it must
#     never be cited as the reason a fan-out is bounded in depth.
#
#     ── AND THE ENV ROUTE IS NOT A FALLBACK EITHER, ON THIS HALF (backlog bffbce207f12, probed
#     2026-08-11) ─────────────────────────────────────────────────────────────────────────────────
#     The filed design's remedy for this term was to stamp `CC_SPAWN_ROOT`/`CC_SPAWN_DEPTH` on the
#     child instead of reading the harness. For an IN-PROCESS subagent that is not merely
#     unnecessary, it is unreachable: its Bash forks from the LEAD'S OWN process — probed pid 81973
#     on both sides, byte-identical — so it has no environment of its own to stamp, and a PreToolUse
#     hook cannot mutate its caller's. There is no per-child slot at any depth.
#
#     But that verdict covers only the in-process half of this tool's traffic. A NAMED Agent call
#     mints a PANE, which is a real session with a real environment — and env DOES cross that
#     boundary under an explicit `--env` (it does not cross by itself, and `--source-window` does
#     not copy it either; all four arms with positive controls in
#     docs/research/spawn-lineage-probe-2026-08-11.md). So the lineage bound is reachable on exactly
#     the population the correction below identifies, and it is implemented as § SPAWN-LINEAGE
#     GENERATION CAP further down this file, fed by a stamp bin/it2-kitty puts on the launch.
#
#     WHERE THE GENERATION BOUND ACTUALLY LIVES, therefore: neither term here can see the 224-spawn
#     / 167-session / 3-generation runaway — depth has no population, and the budget resets at
#     exactly the edge the cascade traverses (every step MINTED A NEW CLI SESSION). The lease is
#     what spans that edge, so the bound is a worker-claim-gate consumer on the surface the spawns
#     cross. THAT SURFACE IS THIS ONE, AND THE BOUND IS THE `cc_worker_claim_admit agent-tool` CALL
#     BELOW (834fa840).
#
#     ⚠️ CORRECTED 2026-08-11 (backlog 6f24f9c49e3e). This paragraph shipped saying the runaway
#     "crossed SESSION boundaries via pane splits executed as ordinary Bash" and sent the reader to
#     hooks/validate-bash.sh § DUPLICATE-WORKER PANE-SPAWN ADMISSION for the bound. Both halves were
#     wrong. The 324 bare `chain:"it2-kitty"` rows are not Bash-invoked splits: a bare chain says
#     only that handoff-fire.sh was absent, and Claude Code's own teammate-pane backend invokes
#     `it2-kitty` DIRECTLY for any Agent call carrying a name/team_name. Measured over the cascade
#     window: 187 named Agent calls vs 180 such spawns, ~1:1 per minute; ZERO Bash calls invoking a
#     pane tool across all 167 transcripts; ancestry `it2-kitty ← claude` with no tool shell between
#     (179/180), against `kitty-split-launch.sh ← zsh ← claude` 16/16 as the same log's positive
#     control. So the fan-out this hook refuses IS the generational edge, and the validate-bash.sh
#     term — which is a real guard on a real, smaller population — could not have seen this cascade.
#     Full evidence and the re-derivation commands live in that block's § WHICH SURFACE THE CASCADE
#     ACTUALLY CROSSED. Case 13 of tests/worker-claim-gate-coverage.bats red-proofs the call below.
#
#     INDEPENDENTLY RE-DERIVED 2026-08-11 (bffbce207f12) before building on it, because a bound
#     placed on the wrong surface is the defect this whole thread keeps re-discovering. Same log,
#     the discriminating leg and its control: bare `chain:"it2-kitty"` rows carry
#     `ppid_comm=claude` 319/324, while the session-invoked `chain:"kitty-split-launch.sh"` rows
#     carry `ppid_comm=zsh` 16/16. A Bash tool call necessarily puts its own shell between, so the
#     first shape cannot be one. Confirmed.
#
# REFUSAL IS HARD, NOT BOUNDED — deliberately UNLIKE capacity-admit above. That gate bounds its
# refusals because memory pressure is transient and a wave must never be permanently blocked by a
# reading. A spawn budget is the opposite: it bounds a quantity the caller chose, and a budget
# that expires into an admit is not a budget. This follows the shape already proven in
# hooks/frontier-spawn-gate.sh:52-63 (per-session cap, hard refusal, "do NOT retry"). Attempts
# are charged, not admissions — a model re-trying a denied spawn in a loop IS the pathology, so a
# retry storm must reach the wall faster, never slower.
_sb_sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
_sb_tp="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
_sb_state="${CC_SPAWN_STATE_DIR:-$HOME/.claude/autonomy/spawn-budget}"
_sb_idl="${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
_sb_max="${CC_SPAWN_MAX_PER_SESSION:-60}"
_sb_maxdepth="${CC_SPAWN_MAX_DEPTH:-2}"

# Every validator failure ADMITS (capacity-admit's convention, :301-306) — a gate that cannot
# read its own configuration must not become a fleet-wide refusal.
case "$_sb_max"      in ''|*[!0-9]*) _sb_max=60 ;; esac
case "$_sb_maxdepth" in ''|*[!0-9]*) _sb_maxdepth=2 ;; esac

# Derive depth. A path matching */subagents/agent-*.jsonl IS a subagent transcript; its sibling
# meta.json carries the harness's own spawnDepth. Anything else reads as the top level.
_sb_depth=0; _sb_basis=depth-unavailable
case "$_sb_tp" in
  */subagents/agent-*.jsonl)
    _sb_meta="${_sb_tp%.jsonl}.meta.json"
    if [ -r "$_sb_meta" ]; then
      _sb_d="$(jq -r '.spawnDepth // empty' "$_sb_meta" 2>/dev/null)"
      case "$_sb_d" in ''|*[!0-9]*) : ;; *) _sb_depth="$_sb_d"; _sb_basis=depth-read ;; esac
    fi
    # A subagent transcript whose meta is unreadable still proves we are BELOW the top level.
    [ "$_sb_basis" = depth-unavailable ] && { _sb_depth=1; _sb_basis=depth-inferred; }
    ;;
  ?*) _sb_basis=depth-toplevel ;;
esac

_sb_row() { # <verdict> <detail>  — one row per return path, no silent branch
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
         --arg sid "${_sb_sid:-?}" --arg v "$1" --arg b "$_sb_basis" --arg d "$2" \
         --arg tp "$_sb_tp" --argjson dep "${_sb_depth:-0}" \
    '{ts:$ts,hook:"spawn-budget",sid:$sid,disposition:(if $v=="refuse" then "refused" else "admitted" end),
      reason:"spawn-budget",gate:"spawn-budget",verdict:$v,basis:$b,caller:"agent-tool",
      what:"subagent spawn",depth:$dep,transcript:$tp,detail:$d}' \
    >> "$_sb_idl" 2>/dev/null || true
}

if [ "${CC_SPAWN_GATE:-on}" = off ]; then
  _sb_row admit "gate-off"
elif [ -z "$_sb_sid" ]; then
  # No session identity ⇒ nothing to key a budget on ⇒ admit, loudly. Never a silent pass.
  _sb_row admit "no-session-id — spawn UNGATED for budget"
else
  mkdir -p "$_sb_state" 2>/dev/null
  # Bound the store in place: a counter file per session accumulates forever otherwise, which is
  # the same never-retired-residue defect this whole effort exists to close. 7 days is well past
  # any single session's life.
  find "$_sb_state" -name '*.count' -type f -mtime +7 -delete 2>/dev/null || true

  _sb_safe="$(printf '%s' "$_sb_sid" | tr -c 'A-Za-z0-9._-' '_')"
  _sb_file="$_sb_state/$_sb_safe.count"
  _sb_n=0; [ -f "$_sb_file" ] && _sb_n="$(cat "$_sb_file" 2>/dev/null)"
  case "$_sb_n" in ''|*[!0-9]*) _sb_n=0 ;; esac
  _sb_n=$((_sb_n + 1))
  printf '%s\n' "$_sb_n" > "$_sb_file" 2>/dev/null || true

  if [ "$_sb_depth" -ge "$_sb_maxdepth" ]; then
    _sb_row refuse "depth $_sb_depth >= cap $_sb_maxdepth"
    jq -n --argjson dep "$_sb_depth" --arg cap "$_sb_maxdepth" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("SPAWN DEPTH CAP — this agent is already \($dep) level(s) deep and the cap is \($cap). A subagent spawning a subagent is how one dispatch reached 224 spawns / 167 sessions, which is the measured ignition of the kernel watchdog panics that destroy every live session at once. DO NOT retry and do NOT re-word the prompt — depth is read from the harness own spawnDepth, not from your text. Instead: RETURN your findings to the agent that spawned you and let IT decide whether to fan out further; that agent has budget you do not. If this genuinely needs one more level, the parent must spawn it. Override for one spawn: CC_SPAWN_MAX_DEPTH=<n>. Rule: master item 66ef300dd0b4 (fleet footprint).")
      }
    }'
    exit 0
  fi

  if [ "$_sb_n" -gt "$_sb_max" ]; then
    _sb_row refuse "budget $_sb_n/$_sb_max"
    jq -n --argjson n "$_sb_n" --arg cap "$_sb_max" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("SPAWN BUDGET EXHAUSTED — this session has attempted \($n) agent spawns against a cap of \($cap). The budget is charged per SESSION and an in-process subagent shares its lead session id, so every descendant of this session spends the same account: the number above is the whole tree, which is exactly the quantity that reached 224 and panicked the box. DO NOT retry in a loop — attempts are charged, not admissions, so a retry storm only reaches the wall faster. Instead: do the remaining work SERIALLY on this agent, or narrow the fan-out to the few axes that actually change the answer, or hand the rest to a fresh dispatched session (scripts/handoff-fire.sh) which carries its own budget. Override for this session: CC_SPAWN_MAX_PER_SESSION=<n>. Rule: master item 66ef300dd0b4 (fleet footprint).")
      }
    }'
    exit 0
  fi

  _sb_row admit "budget $_sb_n/$_sb_max depth $_sb_depth/$_sb_maxdepth"
fi

# ── SPAWN-LINEAGE GENERATION CAP ──────────────────────────────────────────────────────────────
# The bound the two terms above cannot supply, on the surface the correction in the DEPTH note
# identifies (backlog bffbce207f12, building on 6f24f9c49e3e). Depth has no population because
# nothing nests in-process; the budget resets at the session edge the cascade crosses. This one
# neither nests nor resets: it rides an environment stamp that survives the pane boundary, so it is
# the same lineage on both sides of the edge.
#
# SCOPED TO PANE-MINTING CALLS ONLY, and that scoping is the whole correctness argument. A NAMED
# Agent call is what Claude Code's teammate-pane backend turns into a new CLI session — measured
# `ppid_comm=claude` on 319 of 324 bare `chain:"it2-kitty"` rows, against `ppid_comm=zsh` 16/16 on
# the session-invoked control. An UNNAMED call is an in-process subagent: it mints no session, it
# has no environment of its own (its Bash forks from this very process — probed pid 81973 on both
# sides), and the harness does not expose the Agent tool to it, so it cannot begin a generation at
# all. Charging one a generation would refuse ordinary read-only research fan-out — the single
# largest legitimate consumer of this tool — to bound a thing it cannot do (memory
# `guard-universalization-deletes-a-capability-silently`).
#
# WHY IT DOES NOT DUPLICATE THE LEASE TERM AT THE TOP OF THIS FILE. That term asks "is this session
# entitled to be working this item at all", and abstains wherever the cwd is not `wt-<12 hex>` —
# which, measured over all 1085 rows of logs/pane-spawns.jsonl, is most of the fleet, and the side
# carrying the widest fan-outs: the shared repo root shows 303 spawns across 23 sessions with a
# maximum of 21 by ONE session, against a maximum of 7 inside dispatch worktrees. This term asks a
# different question — "how deep is this lineage" — and can answer it where there is no item.
#
# The stamp is written by bin/it2-kitty onto the launch, above all three of its launch branches;
# scripts/lib/spawn-lineage.sh derives and reads it. Enforced identically on the Bash pane-spawn
# surface (hooks/validate-bash.sh), which covers the smaller session-invoked population.
# FAIL OPEN, LOUDLY: unreachable library, absent stamp, or unparseable stamp all ADMIT and record a
# distinct `basis`, so "unstamped" never reads the same as "could not ask".
_lin_named="$(printf '%s' "$INPUT" | jq -r '.tool_input.name // .tool_input.team_name // empty' 2>/dev/null)"
if [ -n "$_lin_named" ] && [ "${CC_LINEAGE_GATE:-on}" != off ]; then
  for _lin_lib in "$(dirname "$_ateh_self")/../scripts/lib/spawn-lineage.sh" \
                  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/spawn-lineage.sh" \
                  "${HOME:-}/.claude/scripts/lib/spawn-lineage.sh"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [ -f "$_lin_lib" ] && . "$_lin_lib" 2>/dev/null && break
  done
  if command -v cc_lineage_admit >/dev/null 2>&1; then
    if ! cc_lineage_admit agent-tool "${_sb_sid:-?}" "teammate pane spawn"; then
      jq -n --arg r "$(cc_lineage_reason)" --arg g "$(cc_lineage_gen)" \
            --arg root "$(cc_lineage_root)" --arg cap "${CC_LINEAGE_MAX_GEN:-3}" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: ("SPAWN GENERATION CAP — teammate spawn refused. This session is generation \($g) of spawn lineage \($root) and the cap is \($cap): \($r). A NAMED Agent call is turned into a whole new CLI session by the teammate-pane backend, so it starts a generation — and generation is read from an environment stamp this machine wrote when your pane was created, NOT from your text, so re-wording the prompt changes nothing. The ladder the cap protects is desk → wave lead → dispatched phase session → the teammates of that session; you are one rung past it, and past it is where a fan-out stops being a wave and becomes the recursion that reached 224 spawns / 167 sessions in ~38 minutes and ignited the kernel watchdog panics that destroy every live session at once. INSTEAD: drop the name/team_name and run this as an in-process subagent if it is read-only work (those mint no session and are not capped), do it SERIALLY in this session, or RETURN your findings to the session that spawned you and let IT widen — it has generations you do not. Override for this session only: CC_LINEAGE_GATE=off, or raise the ladder with CC_LINEAGE_MAX_GEN=<n>. Rule: backlog bffbce207f12, docs/research/spawn-lineage-probe-2026-08-11.md.")
        }
      }'
      exit 0
    fi
  else
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
      '{ts:$ts,hook:"spawn-lineage",sid:"?",disposition:"abstained",reason:"spawn-lineage",
        gate:"spawn-lineage",verdict:"admit",basis:"absent",caller:"agent-tool",
        what:"teammate pane spawn",detail:"scripts/lib/spawn-lineage.sh unreachable — teammate spawn UNGATED for lineage"}' \
      >> "${CC_LINEAGE_IDL:-${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}}" 2>/dev/null || true
  fi
fi

# Teammate spawns (team_name set) MUST use a Max-plan auto-mode-allowlisted model.
# Allowlist is read from the SSOT (~/.claude/model-config.yaml
# .auto_mode_allowlist.non_firstParty_max — claude-opus-4-8 as of 2026-06-09) so
# this hook can never drift from a model bump again (pre-2026-06-09 it hardcoded
# opus-4-7 and would have rejected the swept 4-8 manifests). Off-allowlist models
# silent-demote to acceptEdits and break team parallelism. Teams run BOTH launcher
# tracks (stable 2.1.114 + claude-next eval); frontier models (claude-fable-5)
# become teammate-eligible the moment they're verified into the SSOT allowlist —
# until then they risk silent auto-mode demotion, so they're denied here. Blocks
# the 2026-04-17 failure mode (stale plan hardcoding Sonnet for "mechanical"
# teammates).
# Rule: memory/feedback-agent-team-models.md + model-upgrade skill.
if [ -n "$TEAM_NAME" ] && [ -n "$MODEL" ]; then
  ALLOWED=$(yq -r '.auto_mode_allowlist.non_firstParty_max[]' "$HOME/.claude/model-config.yaml" 2>/dev/null)
  [ -n "$ALLOWED" ] || ALLOWED="claude-opus-4-8"   # fallback if yq/config unavailable
  ALLOWED_FLAT=$(echo "$ALLOWED" | tr '\n' ' ')
  MODEL_BASE="${MODEL%%\[*}"                        # strip [1m]-style suffixes
  ALLOW_OK=0
  case "$MODEL_BASE" in
    *-*)  # full model ID — must match an allowlisted ID exactly
      for m in $ALLOWED; do
        [ "$MODEL_BASE" = "$m" ] && ALLOW_OK=1
      done
      ;;
    *)    # bare family alias (opus, fable, …) — allowed iff the allowlist
          # contains a model of that family (alias resolves to it)
      for m in $ALLOWED; do
        case "$m" in claude-"$MODEL_BASE"-*) ALLOW_OK=1 ;; esac
      done
      ;;
  esac
  if [ "$ALLOW_OK" -ne 1 ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Teammate spawn rejected: model='$MODEL' is not on the Max-plan auto-mode allowlist (${ALLOWED_FLAT}). Use model='opus' (alias) or an allowlisted ID for all teammates. Off-allowlist models silent-demote to acceptEdits and break team parallelism. Frontier models (claude-fable-5) become teammate-eligible only after verification into the SSOT allowlist (~/.claude/model-config.yaml auto_mode_allowlist.non_firstParty_max) — verify with one test spawn on the eval track, then append it there; this hook follows the SSOT automatically. Rule: memory/feedback-agent-team-models.md."
  }
}
EOF
    exit 0
  fi
fi

# Emit an allow + advisory skill-pointer (same pattern as the impl-nudge below). The resident
# CLAUDE.md invariants carry the CORE discipline; these pointers ensure the full-detail skill
# loads at the actual spawn point. Additive/advisory only — never denies.
emit_allow_ctx() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"%s"}}\n' "$1"
}

# If team_name is set (with valid or absent model), this is an Agent Team — allow + point to skill.
#
# G-P13-4 — brief-count guard. The teammate brief IS the `prompt`. An oversized brief burns the
# teammate's context before any work and drives the GH #49593 /compact crash → wave stall (FM2).
# The Agent-Teams discipline caps a brief at 150 lines (tightened from 200 after the tp-assignee
# crash 2026-05-03); ~250 lines is the empirically-observed crash size (a 21-agent synthesis dumped
# inline). Graduated response, both thresholds env-overridable:
#   >  WARN (150) → allow, but INJECT a hard warning naming the split rule. Near-misses over 150 are
#                   common and can be legitimate, so warn — don't block.
#   >= DENY (250) → deny. No legitimate brief is this large; blocking forces the split and prevents a
#                   near-certain crash (the exact FM2 wave-stall the guard exists to stop).
# Line count via `grep -c ''` — exact even when the prompt has no trailing newline (wc -l undercounts
# that case by one). Dynamic reasons are jq-built, never raw %s-interpolated (malformed-JSON class).
if [ -n "$TEAM_NAME" ]; then
  BRIEF_WARN="${AGENT_TEAMS_BRIEF_WARN_LINES:-150}"
  BRIEF_DENY="${AGENT_TEAMS_BRIEF_DENY_LINES:-250}"
  BRIEF_LINES=$(printf '%s' "$PROMPT" | grep -c '' || true)
  SKILL_PTR="AGENT-TEAMS SKILL: spawning a teammate. If not already loaded, invoke the agent-teams skill for the full brief discipline (150-line brief cap, pre-grep line ranges, verbatim stop-on-issue clause, phase checkpoints), runtime detection, per-teammate effort + model-pinning, lifecycle + graceful-shutdown, and crash recovery. The resident CLAUDE.md invariant carries the core; the skill carries the detail."

  if [ "$BRIEF_LINES" -ge "$BRIEF_DENY" ]; then
    jq -n --arg n "$BRIEF_LINES" --arg warn "$BRIEF_WARN" --arg deny "$BRIEF_DENY" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Teammate brief is \($n) lines — at/over the \($deny)-line hard cap. An oversized brief burns the teammate context before any work and drives the GH #49593 /compact crash → wave stall (the tp-assignee 2026-05-03 failure mode). SPLIT into 2-3 teammates along domain boundaries (target ≤\($warn) lines each; pre-grep line ranges instead of pasting file bodies; defer visual verification to a separate Explore subagent), then re-spawn. Env override: AGENT_TEAMS_BRIEF_DENY_LINES. Rule: agent-teams skill § Brief Discipline.")
      }
    }'
    exit 0
  fi

  if [ "$BRIEF_LINES" -gt "$BRIEF_WARN" ]; then
    jq -n --arg n "$BRIEF_LINES" --arg warn "$BRIEF_WARN" --arg ptr "$SKILL_PTR" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: ("BRIEF OVER CAP: this teammate brief is \($n) lines, over the \($warn)-line Agent-Teams cap. Oversized briefs risk the GH #49593 /compact crash → wave stall. Prefer splitting into 2-3 teammates by domain (≤\($warn) lines each), pre-greping line ranges instead of pasting file bodies, and deferring visual verification to a separate Explore subagent. " + $ptr)
      }
    }'
    exit 0
  fi

  emit_allow_ctx "$SKILL_PTR"
  exit 0
fi

# === DELIVERY-CONTRACT NEGATION GUARD ===
# Fires BEFORE the read-only-type skip and both research branches, because the defect is
# orthogonal to which branch would allow the spawn.
#
# WHY: research-subagents field 7 (the Delivery contract) mandates that every brief name an
# absolute artifact PATH, because a subagent's prose is invisible and only a file is delivered.
# Nothing stopped a lead from ALSO writing "Write NO files" in the same brief — which is meant
# as "do not mutate the repo under investigation" but reads to the subagent as "your delivery
# channel is closed". The two clauses contradict, and the contradiction is silent: the agent
# investigates correctly, reports in prose, goes idle, and the report is stranded in its
# transcript. Observed 2026-08-05: 4 of 5 agents in one wave lost their reports this way; the
# 1 that delivered was the 1 whose brief did not carry the suppression clause.
#
# The suppression clause is legitimate — it is the repo-safety half. The DEFECT is suppression
# with no named delivery path. So the guard fires only on that conjunction, and is advisory.
if [ -n "$PROMPT" ]; then
  WRITE_SUPPRESS='[Ww]rite NO files|write no files|do not write (any )?files|don'"'"'t write (any )?files|writes? nothing to disk|NO (FILES|CODE)( WILL BE)? (WRITTEN|MODIFIED|CREATED)'
  # An absolute path with a report-ish extension = a named delivery channel.
  DELIVERY_PATH='(/[A-Za-z0-9._-]+){2,}\.(md|json|jsonl|txt|csv)'
  if echo "$PROMPT" | grep -qE "$WRITE_SUPPRESS" && ! echo "$PROMPT" | grep -qE "$DELIVERY_PATH"; then
    emit_allow_ctx "🚨 DELIVERY-CONTRACT NEGATION: this brief suppresses file writes but names NO absolute delivery path, so the subagent has no way to reach you. Its prose is invisible — it will investigate correctly, report into its own transcript, and go idle with the findings stranded (observed 2026-08-05: 4 of 5 agents in one wave lost their reports exactly this way). A write-suppression clause scopes to the SUBJECT under investigation; it must never close the delivery channel. FIX THE BRIEF BEFORE RELYING ON THIS AGENT: keep the suppression but scope it ('do not modify the repo under investigation'), and add research-subagents field 7 verbatim — 'Delivery: write your findings to /abs/path/report-<agent>.md — writing the file is MANDATORY and is what done means.' Recovery for an already-stranded report: its findings are in the agent's session JSONL under the project transcript dir; extract the last long assistant text block."
    exit 0
  fi
fi

# If this is a known read-only subagent type, allow silently
case "$SUBAGENT_TYPE" in
  Explore|Plan|claude-code-guide|research-decomposition-critic) exit 0 ;;
esac

# === RESEARCH ESCAPE HATCH ===
# Strong research-only markers override the keyword heuristic. Lead prepends
# any of these phrases to a research-only prompt to bypass false-positives
# (e.g. research about "schema", "migration mechanics", "Phase 0 patterns"
# was previously blocked because those words triggered the impl regex).
# Discriminator is the EXPLICIT marker, not the topic.
RESEARCH_MARKERS='READ[- ]ONLY RESEARCH|RESEARCH[- ]ONLY|NO (FILES|CODE)( WILL BE)? (WRITTEN|MODIFIED|CREATED)|WRITES? NOTHING (TO|ON) DISK|Tool budget:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])+|Tool use limited to:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])'
if echo "$PROMPT" | grep -qEi "$RESEARCH_MARKERS"; then
  emit_allow_ctx "RESEARCH-SUBAGENTS SKILL: fanning out research subagents. If composing a WAVE, invoke the research-subagents skill for the decomposition discipline (decompose before counting, default N=10, question-type + named-entity gates, 7-field briefs INCLUDING the mandatory field 7 Delivery — name the absolute artifact path each subagent WRITES, because a subagent's prose is invisible and only a file is delivered, adversarial-sampling floor, OASIS stop). The resident CLAUDE.md invariant carries the core."
  exit 0
fi

# Check if the prompt contains implementation keywords (case-insensitive)
IMPL_KEYWORDS="implement|create.*file|write.*code|modify|refactor|add.*column|schema|migration|build.*component|fix.*bug|update.*file|delete.*file|edit.*file|new.*route|new.*component|add.*feature|deploy|seed|generate|write.*test|create.*component|add.*hook"
RESEARCH_KEYWORDS="research|explore|investigate|find|search|analyze|audit|verify|check|review|read|look|scan|inspect|evaluate|fetch|report|list|summarize|compare"

# Count implementation vs research keyword matches
IMPL_COUNT=$(echo "$PROMPT" | grep -oEi "$IMPL_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')
RESEARCH_COUNT=$(echo "$PROMPT" | grep -oEi "$RESEARCH_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')

# If clearly research-oriented (more research keywords than implementation), allow silently
if [ "$RESEARCH_COUNT" -gt "$IMPL_COUNT" ] && [ "$IMPL_COUNT" -le 1 ]; then
  emit_allow_ctx "RESEARCH-SUBAGENTS SKILL: research-oriented subagent spawn. If composing a research WAVE, invoke the research-subagents skill for the decomposition discipline (decompose before counting, default N=10, adversarial-sampling floor, OASIS stop, synthesis-bottleneck rules). The resident CLAUDE.md invariant carries the core."
  exit 0
fi

# DENY: Background subagent with implementation keywords — block and redirect to Agent Teams
if [ "$RUN_BG" = "true" ] && [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Background subagents cannot write code. Implementation tasks require Agent Teams for visibility and coordination. To proceed: use TeamCreate first, then spawn agents with team_name parameter set (e.g., team_name='implementation-wave-1'). You ARE authorized to use Agent Teams — this constraint exists to ensure parallel work is coordinated safely. If this task is purely research/exploration with no code changes, rephrase the prompt to clarify."
  }
}
EOF
  exit 0
fi

# ALLOW+NUDGE: Foreground agent without team_name that looks like implementation
if [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "AGENT TEAMS DEFAULT: This agent spawn involves code changes but has no team_name. Per global rules, ALL implementation tasks with 2+ code-writing tasks MUST use Agent Teams (TeamCreate + team_name + worktree isolation). Only research/exploration subagents should run without team_name. You ARE authorized to use Agent Teams."
  }
}
EOF
  exit 0
fi

# Default: allow silently (ambiguous or single-keyword cases)
exit 0
