#!/usr/bin/env bats
# lr-handoff.sh — THE VOLUNTARY DISPOSITION AND THE CAUSE IT THREADS
# (VOLUNTARY_ACCOUNT_SWITCH §5 DEC-3, §6).
#
# WHAT THIS SUITE IS FOR. A voluntary move and a limit recovery run the SAME engine, and the one
# thing that must differ between them is a FIELD: `--transplant-cause` to handoff-fire (whose
# in-flight-subagent gate is forced OFF for a limit, because a limit-blocked lead's subagents died
# with it — and must NOT be for a healthy one) and `--cause` to lr-transplant (recorded on the lock
# and the tombstone, branched on by nothing).
#
# 🚨 THE CASE THAT MATTERS MOST IS THE **LIMIT** ONE, NOT THE VOLUNTARY ONE. handoff-fire's ABSENT
# case is the SAFE branch and answers an ungated caller with a loud refusal, so the flag has to be
# emitted on BOTH paths — a `--voluntary`-only emitter would leave every existing recovery
# (lr-fleet --one, the reset poller, cc-lr recover) meeting that refusal. "The limit path still
# passes it" is the window this wave must keep closed, and it is pinned first below.
#
# RED PROOFS vs EQUIVALENCE GUARDS, labelled per case. The cause-threading and verdict cases are
# RED PROOFS — the pre-change subject emits neither flag and no verdict= line at all. The negative
# invariant and the counted-pin cases are RATCHETS over the subject's own source text: they pass
# before and after by construction, and they exist to kill a future edit, not to prove this one.
#
# Hermeticity: $HOME, $CLAUDE_CONFIG_DIR, TMPDIR, the registry and cc-notify are fixtures; every
# tool lr-handoff shells out to is stubbed under the fixture $HOME, so no case can transplant a
# live session, type into a pane, or mail the operator. Harness shape copied from
# tests/lr-handoff-close-source.bats, which is the four-stub fire harness for this script.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  # capacity-admit reads LIVE load, memory and the session census, so an unpinned run is red
  # by BOX rather than by subject — and intermittently, which is the worst polarity available
  # (test-hermeticity RULE 2). The gate is not this suite's subject anywhere.
  export CC_ADMIT_GATE=off
  export LRH_LIVE_PARSER_CHECK=off
  # The precheck's own arms are the subject of ONE case below (the NOTMOVED verdict); everywhere
  # else it is off, because its capacity leg reads the REAL box and would make these cases red by
  # LOAD rather than by their subject.
  export LRH_PRECHECK=off

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export HF_LOG="$BATS_TEST_TMPDIR/handoff-fire.log"; : > "$HF_LOG"
  export TX_LOG="$BATS_TEST_TMPDIR/lr-transplant.log"; : > "$TX_LOG"
  export NOTIFY_LOG="$BATS_TEST_TMPDIR/cc-notify.log"; : > "$NOTIFY_LOG"

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  mkdir -p "$HOME/.claude/scripts/limit-recover" "$HOME/.claude/bin" "$HOME/.claude/projects" \
           "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain"

  # handoff-fire stub, pinned through CC_HANDOFF_FIRE_BIN. It answers BOTH roles this script uses
  # it for: the read-only precondition probe, and the recycle. Without the pin the subject would
  # resolve the real handoff-fire.sh beside itself and type /exit into a live pane.
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
# lr-handoff hands a flag to the probe only when the live handoff-fire PARSES it, which it decides
# by grepping this file for the flag's case label: --account-evidence) --operator-intent)
printf '%s\n' "$*" >> "${HF_LOG:?}"
case " $* " in
  *" --probe-recycle-preconditions "*)
    printf 'live_subagents: 0\n'
    [ -z "${HF_PROBE_SHELL_ROOT_ANSWER:-}" ] || printf 'shell_root: %s\n' "$HF_PROBE_SHELL_ROOT_ANSWER"
    printf 'verdict: %s\n' "${HF_PROBE_VERDICT:-OK}"
    exit "${HF_PROBE_RC:-0}" ;;
esac
exit "${HF_RC:-0}"
STUB
  chmod +x "$STUB/handoff-fire.sh"
  export CC_HANDOFF_FIRE_BIN="$STUB/handoff-fire.sh"

  # cc-notify stub — the verdict's mail lane. Pinned so a case can never reach the operator's inbox.
  cat > "$STUB/cc-notify" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${NOTIFY_LOG:?}"
exit "${NOTIFY_RC:-0}"
STUB
  chmod +x "$STUB/cc-notify"
  export CC_NOTIFY_BIN="$STUB/cc-notify"

  cat > "$HOME/.claude/scripts/limit-recover/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent",
           "transcript_sha256": "deadbeef",
           "counts": {"gaps": 0}}, open(out, "w"))
PY
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-preseed-env.sh"
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh"
  # lr-transplant stub — RECORDS ITS ARGV, which is the whole point of half this suite, and writes
  # the transplant.json shape the caller reads back.
  cat > "$HOME/.claude/scripts/limit-recover/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TX_LOG:?}"
[ "${TX_RC:-0}" = 0 ] || exit "${TX_RC}"
printf '{"ok":true,"sid":"stub","slug":"stub","target_transcript":"/dev/null"}\n'
exit 0
STUB
  chmod +x "$HOME/.claude/scripts/limit-recover/"*.sh

  export PATH="$STUB:$PATH"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  SID="0000aaaa-0000-4000-8000-00000000cafe"
  # The registry row is what admits --source-pane: it must name the sid being transplanted.
  printf '{"session_id":"%s"}\n' "$SID" > "$CC_REGISTRY_DIR/31.json"
}

# `run`'s $output merges stderr, which is where every verdict= line and every refusal lives.
fire() { # rest = extra args
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --cwd "$BATS_TEST_TMPDIR/plain" \
      --launch --in-place --source-pane 31 "$@"
}
# $1 = pattern (may start with a dash — hence -e, never a bare argument), $2 = the text.
# THE BUG THIS SHAPE REMOVES: every call site used to pass a leading `--` separator, which is just
# an ARGUMENT here, so $1 became "--" and the real pattern became the haystack. Five cases failed
# on a helper, not on the subject. Keep the dash handling INSIDE the helper.
count() { printf '%s\n' "$2" | grep -c -e "$1" || true; }

# ── 1. the cause is threaded, and the LIMIT path is the one that must not break ─────────────────

@test "LIMIT path (no --voluntary) passes --transplant-cause limit and --cause limit" {
  # RED PROOF. The pre-change subject emits NEITHER flag, and handoff-fire's landed gate treats
  # ABSENT as the safe branch that implies nothing — so without this line every existing recovery
  # on the box meets a loud refusal. This case is the window being kept closed.
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--transplant-cause limit' "$HF_LOG" || { cat "$HF_LOG"; false; }
  grep -q -- '--cause limit' "$TX_LOG" || { cat "$TX_LOG"; false; }
  [ "$(count '--transplant-cause voluntary' "$(cat "$HF_LOG")")" -eq 0 ]
}

@test "VOLUNTARY path passes --transplant-cause voluntary and --cause voluntary" {
  # RED PROOF, the mirror arm. Two arms are what make this a control rather than a smoke test: a
  # subject that hardcoded either value would pass one of these cases and fail the other.
  fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--transplant-cause voluntary' "$HF_LOG" || { cat "$HF_LOG"; false; }
  grep -q -- '--cause voluntary' "$TX_LOG" || { cat "$TX_LOG"; false; }
  [ "$(count '--cause limit' "$(cat "$TX_LOG")")" -eq 0 ]
}

@test "the flag's NAME does not contain --in-place, and the emitted argv carries exactly one" {
  # THE COUNTED PIN, at its own subject. tests/lr-fleet.bats:320 asserts `grep -c -- '--in-place'`
  # equals 1 over lr-handoff's emitted argv log, so a voluntary flag spelled with that substring
  # would redden a SIBLING suite — the failure mode own-scope gating is blind to (repo lesson:
  # own-scope-gate-is-blind-to-a-counted-pin-elsewhere). RATCHET, not a red proof.
  [ "$(count '--in-place' '--voluntary')" -eq 0 ]
  fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # handoff-fire is handed --recycle, never --in-place; that substring belongs to lr-handoff's own
  # argv, which lr-fleet's stub logs. Assert the count over what THIS run emitted downstream.
  [ "$(count '--in-place' "$(cat "$HF_LOG" "$TX_LOG")")" -eq 0 ]
}

# ── 2. the MANIFEST records the disposition as a FIELD, never as a state ────────────────────────

@test "MANIFEST carries trigger and reason beside the in_place flags" {
  fire --voluntary --reason 'idle on a perishable account'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local bundle; bundle="$(printf '%s\n' "$output" | tail -1)"
  [ -f "$bundle/MANIFEST.json" ] || { echo "no MANIFEST at $bundle"; false; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["trigger"]=="voluntary", d; assert d["reason"]=="idle on a perishable account", d; assert d["in_place"] is True, d' "$bundle/MANIFEST.json"
}

@test "MANIFEST.trigger is limit by default, so an unflagged caller records what it actually did" {
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local bundle; bundle="$(printf '%s\n' "$output" | tail -1)"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["trigger"]=="limit", d' "$bundle/MANIFEST.json"
}

@test "NEGATIVE INVARIANT: no predicate branches on the cause — it is a field and nothing else" {
  # RATCHET over the subject's own source text (§5 DEC-3). A new STATE value would fall into
  # klass()'s permissive `return "run"` default and render as in-flight forever; a predicate that
  # BRANCHED on the cause would re-create that by the back door. The only admitted reads are the
  # derivation itself, the two argv appends, the verdict line, and comments.
  local body; body="$(grep -vE '^[[:space:]]*#' "$HANDOFF")"
  # NARROWED TO WHAT THE INVARIANT ACTUALLY FORBIDS: the cause as the SUBJECT of a comparison.
  # The first draft of this ratchet matched any `[`/`[[`/`case` line mentioning LRH_CAUSE and duly
  # convicted the variable's OWN derivation — a ratchet whose first red is its subject's definition
  # is measuring the wrong thing, not finding a bug.
  [ "$(printf '%s\n' "$body" | grep -cE 'case[[:space:]]+"?\$\{?LRH_CAUSE' || true)" -eq 0 ] || {
    printf '%s\n' "$body" | grep -nE 'case[[:space:]]+"?\$\{?LRH_CAUSE'; false; }
  [ "$(printf '%s\n' "$body" | grep -cE '(\[\[?.*\$\{?LRH_CAUSE.*(==|!=)|(==|!=)[[:space:]]*"?\$\{?LRH_CAUSE)' || true)" -eq 0 ] || {
    printf '%s\n' "$body" | grep -nE '(\[\[?.*\$\{?LRH_CAUSE.*(==|!=)|(==|!=)[[:space:]]*"?\$\{?LRH_CAUSE)'; false; }
  # and the cause is never handed to lr_state_append as a STATE token
  [ "$(printf '%s\n' "$body" | grep -cE 'lrh_state[[:space:]]+"?\$\{?LRH_CAUSE' || true)" -eq 0 ]
}

# ── 3. the verdict vocabulary (§6) ──────────────────────────────────────────────────────────────

@test "verdict SWITCHED-UNPROVEN is mailed BEFORE the recycle fires, because /exit kills this process" {
  # RED PROOF. On the SELF form the recycle types /exit into this pane's own TUI and Claude Code
  # reaps the process group of the in-flight tool call, so a verdict emitted after the fire is
  # unreachable on the commonest voluntary path there is. Ordering is the assertion: the mail must
  # already be on disk by the time handoff-fire is invoked with --recycle.
  fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q 'verdict=SWITCHED-UNPROVEN' "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  grep -q 'armed' "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  # mandatory fields, on every token
  grep -qE 'verdict=[A-Z-]+ from=[^ ]+ to=next2 proven=(yes|no) trigger=voluntary' "$NOTIFY_LOG" \
    || { cat "$NOTIFY_LOG"; false; }
  # PANE-keyed, never sid-keyed: the recycle changes the sid by construction
  grep -q '^31 ' "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  [ "$(count "$SID" "$(head -1 "$NOTIFY_LOG" | cut -d' ' -f1)")" -eq 0 ]
}

@test "verdict SWITCHED proven=yes only when engagement was AWAITED, never from rc 0 alone" {
  # RED PROOF against the obvious implementation, which reads rc 0 as success. Without --await,
  # rc 0 means the /exit landed and the watcher took over — ARMED, not engaged — and that is a
  # different claim. Same subject, two arms, one variable.
  fire --voluntary                                    # --source-pane ⇒ --await is the default
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=SWITCHED from="*"proven=yes"* ]] || { echo "$output"; false; }
  : > "$NOTIFY_LOG"
  LR_INPLACE_AWAIT=0 fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(count 'verdict=SWITCHED ' "$output")" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=SWITCHED-UNPROVEN"*"proven=no"* ]] || { echo "$output"; false; }
}

@test "verdict STRANDED when the transplant is DONE and the recycle did not verify — rescue, not retry" {
  # RED PROOF, and the load-bearing split of the whole vocabulary: the source is a tombstoned husk
  # and NO successor is carrying the session. Today this hides inside lr-fleet's PARTIAL beside
  # NOTMOVED's PARKED, and the two demand opposite actions.
  # the confirm ran: the source is retired (D7.1 — an unretired one is NOTMOVED, not STRANDED)
  mkdir -p "$HOME/.claude/projects/-fx"; : > "$HOME/.claude/projects/-fx/$SID.jsonl.handed-off"
  HF_RC=7 fire --voluntary
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=STRANDED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"proven=no"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RESCUE"* ]] || { echo "$output"; false; }
  grep -q 'verdict=STRANDED' "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
}

@test "verdict NOTMOVED when the precheck refuses: nothing moved, so a retry is safe" {
  # RED PROOF. NOTMOVED is claimed only where it is PROVABLE — every arm of lrh_precheck returns 6
  # before the transplant runs, so no lock, no tombstone and no keystroke exist. The transplant log
  # being EMPTY is the check that makes the claim checkable rather than asserted.
  LRH_PRECHECK=on HF_PROBE_RC=5 HF_PROBE_VERDICT='REFUSED:not-limited' fire --voluntary
  [ "$status" -eq 6 ]
  [[ "$output" == *"verdict=NOTMOVED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"untouched"* ]] || { echo "$output"; false; }
  [ ! -s "$TX_LOG" ] || { echo "the transplant ran on a NOTMOVED verdict: $(cat "$TX_LOG")"; false; }
}

@test "verdict FAILED when lr-transplant exits non-zero: its rc 2 cannot separate REFUSED from FATAL" {
  # RED PROOF. The obvious implementation calls this NOTMOVED, which ASSERTS the source is
  # untouched — and that engine answers rc 2 for REFUSED and FATAL alike, so only the tombstone
  # knows (repo lesson: two-causes-one-rc-ask-a-lower-layer). FAILED overclaims nothing.
  TX_RC=2 fire --voluntary
  [ "$status" -eq 2 ]
  [[ "$output" == *"verdict=FAILED"* ]] || { echo "$output"; false; }
  [ "$(count 'verdict=NOTMOVED' "$output")" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ] || { echo "the recycle ran after a failed transplant"; false; }
}

@test "a RECONCILER-placed voluntary move mails nothing into the pane it is moving (W5b canary 3)" {
  # The mail is for cc-lr switch, where the session asked. A placed move's subject asked nothing,
  # and the mail woke it mid-move: its inbox watcher fired, it took a turn before the /exit, and the
  # last read held it. The verdict stays on stderr (the reconciler's actuator log).
  LR_PLACED_BY=reconciler fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=SWITCHED"* ]] || { echo "$output"; false; }
  [ ! -s "$NOTIFY_LOG" ] || { echo "the placed move mailed its subject: $(cat "$NOTIFY_LOG")"; false; }
}

@test "the LIMIT path emits its verdict to stderr and mails NOTHING — lr-fleet owns that lane" {
  # A second mailer over one population is two auditors that disagree the first time they derive
  # differently (repo memory: sibling-auditors-must-share-the-state-model). lr-fleet.sh:1163-1172
  # already mails the limit verdict to the requester; this path must not double it.
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict="*"trigger=limit"* ]] || { echo "$output"; false; }
  [ ! -s "$NOTIFY_LOG" ] || { echo "the limit path mailed: $(cat "$NOTIFY_LOG")"; false; }
}

@test "an unreachable cc-notify degrades the verdict to stderr and never fails the switch" {
  # FAIL-QUIET ON THE MESSENGER, LOUDLY. A mail lane that is down says nothing about the move, and
  # a move that has already happened must not be reported as a failure because we could not
  # announce it. The line still exists on stderr, so the claim is never lost, only demoted.
  NOTIFY_RC=1 fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"cc-notify to pane 31 FAILED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=SWITCHED"* ]] || { echo "$output"; false; }
}

# ── 4. the explicit --in-place path keeps the SELF probe's subject ──────────────────────────────

@test "an EXPLICIT --in-place still names the self pane, so killed_inflight stays recordable" {
  # RED PROOF. lrh_resolve_implied_pane is the sole writer of LRH_SELF_PANE and runs only on the
  # IMPLIED path (its guard is `IN_PLACE -ne 1`), so a caller that STATES --in-place — which
  # `cc-lr switch` does, because switch is in-place by definition and must not inherit
  # LR_INPLACE_DEFAULT=off — left the probe with no pane to name and lr-ingest-verify clause A6
  # refusing every fast path. SOURCE_PANE must stay EMPTY (downstream reads that as "recycle
  # yourself"); only the read-only probe gets an id.
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      CLAUDE_CODE_SESSION_ID="$SID" KITTY_WINDOW_ID=198 LRH_PRECHECK=on \
      "$HANDOFF" --sid "$SID" --target next2 --cwd "$BATS_TEST_TMPDIR/plain" \
      --launch --in-place --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"precheck (self, pane 198)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"killed_inflight=0"* ]] || { echo "$output"; false; }
  grep -q -- '--source-pane 198 --source-session' "$HF_LOG" || { cat "$HF_LOG"; false; }
  # the RECYCLE is the self form: it is handed no --source-pane at all. Read the recycle line on
  # its own — the probe invocation above it DOES carry --source-pane 198, and a whole-log grep
  # would read that as the recycle's (repo lesson: assertion-span-must-equal-its-subject).
  local rcy; rcy="$(grep -e '--recycle' "$HF_LOG" || true)"
  [ -n "$rcy" ] || { cat "$HF_LOG"; false; }
  [ "$(count '--source-pane' "$rcy")" -eq 0 ] || { echo "$rcy"; false; }
  # and the verdict still reaches a pane, because the self pane is the address
  grep -q '^198 ' "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
}

# ── 5. FAIL-FAST: a --voluntary move of a HEALTHY peer cannot pass the probe, so refuse first ────
# (2026-09-23 incident: `lr-handoff --voluntary --source-pane P` on a healthy peer was accepted by
# argv, then refused REFUSED:not-limited at the precheck — after the driver had waited hours.)
vol_tx() { # $1 = healthy | limit — the pane's transcript under the SOURCE config dir
  mkdir -p "$HOME/.claude/projects/-fx"
  case "$1" in
    healthy) printf '{"type":"assistant","timestamp":"2026-09-23T10:00:00.000Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}\n' ;;
    limit)   printf '{"type":"assistant","timestamp":"2026-09-23T10:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}\n' ;;
  esac > "$HOME/.claude/projects/-fx/$SID.jsonl"
}

@test "FAIL-FAST: --voluntary --source-pane on a HEALTHY pane refuses before planning and names cc-lr move" {
  # RED PROOF: the unfixed subject reaches the transplant (LRH_PRECHECK=off here) and exits 0.
  vol_tx healthy
  fire --voluntary
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr move --sid ${SID:0:8} --to next2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=NOTMOVED"* ]] || { echo "$output"; false; }
  # nothing was planned: no transplant, no recycle, no bundle
  [ ! -s "$TX_LOG" ] || { cat "$TX_LOG"; false; }
  [ ! -s "$HF_LOG" ] || { cat "$HF_LOG"; false; }
  [ ! -d "$HOME/.reso/limit-recover/$SID" ] || { ls -R "$HOME/.reso/limit-recover/$SID"; false; }
}

@test "FAIL-FAST is scoped: a LIMIT-blocked pane with --voluntary, and a healthy pane without it, are not refused by it" {
  # EQUIVALENCE GUARD — kills a fail-fast keyed on --voluntary alone, or on the pane alone.
  vol_tx limit
  fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vol_tx healthy
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"cc-lr move --sid"* ]] || { echo "$output"; false; }
}

@test "FAIL-FAST kill switch LRH_VOLUNTARY_FAILFAST=off restores the old path" {
  vol_tx healthy
  LRH_VOLUNTARY_FAILFAST=off fire --voluntary
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── 5b. OPERATOR INTENT: the operator's cc-lr move admits a healthy pane (design-swap-v3 D1/F11) ──
# This section un-pins, on purpose, the rule section 5 pinned: a healthy peer could only move
# itself. A healthy pane with NEITHER evidence nor an intent is still refused (the case above).
intent() { # [jq filter to break the valid file] → path of the intent for $SID, pane 31, next → next2
  local d="$HOME/.reso/limit-recover/move/b1/intent"; mkdir -p "$d"
  jq -nc --arg sid "$SID" --argjson exp "$(( $(date +%s) + 600 ))" \
    '{kind:"cc-lr-move",batch:"b1",sid:$sid,pane:"31",from:"next",to:"next2",requested_by:"t",ts:0,expires_epoch:$exp,plan_row_sha:"x"}' \
    | jq -c "${1:-.}" > "$d/$SID.json"
  chmod 600 "$d/$SID.json"
  printf '%s' "$d/$SID.json"
}

@test "[RED] INTENT: a valid operator intent admits a --voluntary move of a healthy pane" {
  vol_tx healthy
  fire --voluntary --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"voluntary move admitted on operator intent"* ]] || false
  [ -s "$TX_LOG" ]
}

@test "INTENT kill switch: LR_OPERATOR_INTENT=off refuses the same valid intent, nothing planned" {
  vol_tx healthy
  LR_OPERATOR_INTENT=off fire --voluntary --operator-intent "$(intent)"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:intent-invalid"*"switched-off"* ]] || false
  [ ! -s "$TX_LOG" ]
}

@test "INTENT: an expired intent is refused before planning" {
  vol_tx healthy
  fire --voluntary --operator-intent "$(intent '.expires_epoch = 1')"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:intent-invalid"*"expired"* ]] || false
  [ ! -s "$TX_LOG" ]
}

@test "INTENT: an intent for another pane, another source or another target is refused" {
  vol_tx healthy
  fire --voluntary --operator-intent "$(intent '.pane = "99"')"
  [ "$status" -eq 6 ]
  [[ "$output" == *"pane-mismatch"* ]] || false
  fire --voluntary --operator-intent "$(intent '.from = "next4"')"
  [ "$status" -eq 6 ]
  [[ "$output" == *"from-mismatch"* ]] || false
  fire --voluntary --operator-intent "$(intent '.to = "next3"')"
  [ "$status" -eq 6 ]
  [[ "$output" == *"to-mismatch"* ]] || false
  [ ! -s "$TX_LOG" ]
}

@test "INTENT: a symlink to a valid intent is refused" {
  vol_tx healthy
  f="$(intent)"; mv "$f" "$f.real"; ln -s "$f.real" "$f"
  fire --voluntary --operator-intent "$f"
  [ "$status" -eq 6 ]
  [[ "$output" == *"not-regular"* ]]
}

@test "INTENT: a session whose last record is a non-limit api error is refused despite a valid intent" {
  mkdir -p "$HOME/.claude/projects/-fx"
  printf '{"type":"assistant","timestamp":"2026-09-23T10:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"API Error: Connection error."}]}}\n' > "$HOME/.claude/projects/-fx/$SID.jsonl"
  fire --voluntary --operator-intent "$(intent)"
  [ "$status" -eq 6 ]
  [[ "$output" == *"REFUSED:intent-api-error"* ]] || false
  [ ! -s "$TX_LOG" ]
}

@test "INTENT: --operator-intent without --voluntary is a usage error" {
  fire --operator-intent "$(intent)"
  [ "$status" -eq 2 ]
}

@test "[RED] INTENT reaches the probe with its target, beside --voluntary" {
  vol_tx healthy
  f="$(intent)"
  LRH_PRECHECK=on fire --voluntary --operator-intent "$f"
  [ "$status" -eq 0 ]
  grep -e '--probe-recycle-preconditions' "$HF_LOG" | grep -q -e "--operator-intent $f --intent-target next2 --voluntary"
}

# ── 5c. THE MOVE LANE'S PLACEMENT, SWAP ADMISSION AND --no-replace (F10, F13, F14) ────────────────
@test "[RED] a cc-lr-move placement mails nothing into the pane it is moving" {
  vol_tx healthy
  LR_PLACED_BY=cc-lr-move fire --voluntary --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=SWITCHED"* ]] || false
  [ ! -s "$NOTIFY_LOG" ]
}

@test "control: LR_PLACED_BY_MOVE=off replays the old behaviour — the verdict is mailed to the pane" {
  vol_tx healthy
  LR_PLACED_BY=cc-lr-move LR_PLACED_BY_MOVE=off fire --voluntary --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  grep -q '^31 ' "$NOTIFY_LOG"
}

@test "[RED] a cc-lr-move placement skips the router read; without it the router is asked" {
  vol_tx healthy
  printf '#!/bin/bash\necho asked >> "%s/rank.log"\necho next2\n' "$BATS_TEST_TMPDIR" > "$STUB/claude-accounts"; chmod +x "$STUB/claude-accounts"
  mkdir -p "$HOME/bin"; cp "$STUB/claude-accounts" "$HOME/bin/claude-accounts"
  f="$(intent)"
  CC_ACCOUNTS_BIN="$STUB/claude-accounts" LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move fire --voluntary --operator-intent "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LR_PLACED_BY=cc-lr-move: the router check is skipped"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/rank.log" ]
}

@test "[RED] SWAP: LR_ADMIT_MODE=swap with --no-prompt runs no capacity decision and the launcher carries the mode" {
  vol_tx healthy
  LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move LR_ADMIT_MODE=swap fire --voluntary --no-prompt --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LR_ADMIT_MODE=swap with --no-prompt: no capacity probe and no admission token"* ]] || false
  grep -rqx 'export LR_ADMIT_MODE=swap' "$HOME/.reso/limit-recover"
}

@test "SWAP control: LR_ADMIT_SWAP=off, or no --no-prompt, keeps the capacity decision and writes no mode" {
  vol_tx healthy
  LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move LR_ADMIT_MODE=swap LR_ADMIT_SWAP=off fire --voluntary --no-prompt --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"no capacity probe and no admission token"* ]] || false
  ! grep -rq 'LR_ADMIT_MODE' "$HOME/.reso/limit-recover" || false
  LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move LR_ADMIT_MODE=swap fire --voluntary --operator-intent "$(intent)"
  [[ "$output" == *"LR_ADMIT_MODE=swap is ignored without --no-prompt"* ]] || false
  ! grep -rq 'LR_ADMIT_MODE' "$HOME/.reso/limit-recover"
}

@test "[RED] --no-replace: a probe that says shell_root: no is HELD:no-shell before anything moves" {
  vol_tx healthy
  HF_PROBE_SHELL_ROOT_ANSWER=no LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move fire --voluntary --no-prompt --no-replace --operator-intent "$(intent)"
  [ "$status" -eq 6 ]
  [[ "$output" == *"HELD:no-shell"* ]] || false
  [ ! -s "$TX_LOG" ]
}

@test "--no-replace control: without the flag, or with shell_root yes/unknown, the precheck proceeds" {
  vol_tx healthy
  HF_PROBE_SHELL_ROOT_ANSWER=no LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move fire --voluntary --no-prompt --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
  HF_PROBE_SHELL_ROOT_ANSWER=unknown LRH_PRECHECK=on LR_PLACED_BY=cc-lr-move fire --voluntary --no-prompt --no-replace --operator-intent "$(intent)"
  [ "$status" -eq 0 ]
}

# ── SONNET 5.5 THINKING IS ACCOUNT-BOUND (2026-09-28) ─────────────────────────────────────────────
# Its thinking blocks are readable only by the account that wrote them; a transplant to another
# account keeps the transcript and silently loses the reasoning. The move is still made — the notice
# lets the operator prefer the brief-based rail. Opus 5.5 is not bound, so it gets no notice.
tier_tx() { # $1 = model id of the last real turn
  mkdir -p "$HOME/.claude/projects/-fx"
  printf '{"type":"assistant","timestamp":"2026-09-23T09:59:00.000Z","effort":"high","message":{"role":"assistant","model":"%s","stop_reason":"end_turn","content":[{"type":"text","text":"working"}]}}\n' "$1" \
    > "$HOME/.claude/projects/-fx/$SID.jsonl"
}
S55_NOTICE="Sonnet 5.5 reasoning does not cross accounts; the resumed session re-derives it (prefer handoff-fire --recycle --account)"

@test "SONNET 5.5: a transcript on claude-sonnet-5-5 moved to another account prints the reasoning notice" {
  tier_tx claude-sonnet-5-5
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$S55_NOTICE"* ]] || { echo "$output"; false; }
}

@test "SONNET 5.5: an Opus 5.5 transcript moved to another account gets no notice" {
  tier_tx claude-opus-5-5
  fire
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"does not cross accounts"* ]] || { echo "$output"; false; }
}

# ── 4. D1 (2026-09-28): the repo guard never aborts a recovery ──────────────────────────────────
# RED PROOF against the pre-change subject: `WT_TOP=$(git rev-parse --show-toplevel)` under
# `set -euo pipefail` died rc 128 on a checkout flipped to core.bare=true, before any bundle existed
# (fleet run one-20260929T030419Z-415a3aac). These cases run the LIMIT path (no --voluntary).
flipped_repo() { # $1=dir
  git init -q "$1" && printf 'a\n' > "$1/a" && git -C "$1" add a \
    && git -C "$1" -c user.email=t@t -c user.name=t commit -qm init \
    && git -C "$1" config core.bare true
}

@test "D1: a flipped-but-healable checkout is healed by the driver and the recovery completes" {
  local d="$BATS_TEST_TMPDIR/repo"; flipped_repo "$d"
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --cwd "$d" --launch --in-place --source-pane 31
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=healed"* ]] || { echo "$output"; false; }
  [ "$(git -C "$d" rev-parse --is-inside-work-tree)" = true ]
  grep -q -- '--recycle' "$HF_LOG"
}

@test "D1: an UNHEALABLE bare state degrades — logged, no abort, the recovery still fires" {
  local d="$BATS_TEST_TMPDIR/repo"; flipped_repo "$d"; : > "$d/.git/logs/HEAD"
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --cwd "$d" --launch --in-place --source-pane 31
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"repo context UNREADABLE"* ]] || { echo "$output"; false; }
  [ "$(git -C "$d" config --bool core.bare)" = true ]
  grep -q -- '--recycle' "$HF_LOG"
}

@test "D1: on a healthy repo the pool/* rename and the dirty-path warning still work" {
  local d="$BATS_TEST_TMPDIR/repo"; flipped_repo "$d"; git -C "$d" config --unset core.bare
  git -C "$d" switch -qc pool/x; printf 'b\n' > "$d/dirty"
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --cwd "$d" --launch --in-place --source-pane 31
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(git -C "$d" branch --show-current)" = "recovered/${SID:0:8}" ]
  [[ "$output" == *"dirty path(s)"* && "$output" == *"dirty"* ]] || { echo "$output"; false; }
}
