#!/usr/bin/env bats
# scripts/automode-land-probe.sh — the verdict half (judge), driven by a stub `claude` that plays
# the permission harness: it emits the stream-json a headless auto-mode session emits, and either
# RUNS the probe's command in the probe's scratch repo (an allow) or refuses it. The subject is the
# probe's judgment of the git SIDE EFFECTS, so each case pins one way a verdict could lie:
# an opened gate read as PASS, an inert rule read as PASS, a non-auto session or an un-attempted
# command read as a gate, and a hook denial (no permission_denied event) missed.
#
# RED-proof: "a hook deny counts as gated" failed on the first cut of judge(), which read denials
#   only from permission_denied events — a validate-bash.sh deny emits none (measured on 2.1.284,
#   2026-10-03), so NEG-NOVERIFY reported FAIL over a commit that never happened.
#
# Hermetic: scratch HOME and TMPDIR; PATH is the stub dir + /usr/bin:/bin (no fnm, so the positive
# arm uses its bare `bash scripts/ship-land.sh` form); AUTOMODE_PROBE_BIN points at the stub.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$HOME" "$TMPDIR" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  export AUTOMODE_PROBE_BIN="$BATS_TEST_TMPDIR/bin/claude" CLAUDE_CONFIG_DIR="$HOME/.claude-stub"
  cat > "$AUTOMODE_PROBE_BIN" <<'STUB'
#!/bin/bash
# STUB_POLICY: allow-pos (the healthy harness) | allow-all | deny-all | hook-deny-noverify | wrong-mode | wrong-cmd
[ "${1:-}" = --version ] && { echo 'stub (Claude Code)'; exit 0; }
prompt=""
while [ $# -gt 0 ]; do case $1 in -p) prompt=$2; shift 2 ;; *) shift ;; esac; done
cmd=$(printf '%s\n' "$prompt" | sed -n '/^<<<CMD$/,/^CMD>>>$/p' | sed '1d;$d')
mode=auto; [ "$STUB_POLICY" = wrong-mode ] && mode=default
issued=$cmd; [ "$STUB_POLICY" = wrong-cmd ] && issued='echo something else'
jq -cn --arg m "$mode" '{type:"system",subtype:"init",permissionMode:$m}'
jq -cn --arg c "$issued" '{type:"assistant",message:{content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]}}'
verdict=deny
case $STUB_POLICY in
  allow-all) verdict=allow ;;
  allow-pos|wrong-mode|wrong-cmd) case $cmd in *ship-land.sh*) verdict=allow ;; esac ;;
  hook-deny-noverify) case $cmd in *ship-land.sh*) verdict=allow ;; *--no-verify*) verdict=hook ;; esac ;;
esac
case $verdict in
  allow) out=$(bash -c "$issued" 2>&1)
         jq -cn --arg o "$out" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",content:$o}]}}' ;;
  hook)  jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",is_error:true,content:"PreToolUse:Bash hook error: --no-verify blocked"}]}}' ;;
  deny)  jq -cn '{type:"system",subtype:"permission_denied",decision_reason_type:"rule"}'
         jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",is_error:true,content:"denied"}]}}' ;;
esac
STUB
  chmod +x "$AUTOMODE_PROBE_BIN"
}

probe() { run bash "$REPO/scripts/automode-land-probe.sh" "$@"; }
line() { printf '%s\n' "$output" | grep -E "^  $1 +$2 " >/dev/null; }

@test "healthy harness: land line runs, hand push and --no-verify stay gated ⇒ PASS rc 0" {
  STUB_POLICY=allow-pos probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line POS PASS
  line NEG-PUSH PASS
  line NEG-NOVERIFY PASS
  [[ "$output" == *"verdict=PASS"* ]] || false
}

@test "an opened gate (the hand push and the --no-verify commit both run) ⇒ FAIL rc 1, never PASS" {
  STUB_POLICY=allow-all probe
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  line POS PASS
  line NEG-PUSH FAIL
  line NEG-NOVERIFY FAIL
  [[ "$output" == *"remote_advanced=yes"* ]] || false
}

@test "an inert rule (the land line refused) ⇒ POS FAIL rc 1" {
  STUB_POLICY=deny-all probe
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  line POS FAIL
  line NEG-PUSH PASS
  line NEG-NOVERIFY PASS
}

@test "a hook deny counts as gated although it emits no permission_denied event" {
  STUB_POLICY=hook-deny-noverify probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  line NEG-NOVERIFY PASS
  [[ "$output" == *"denied_by=hook committed=no"* ]] || false
}

@test "no verdict without auto mode or without the exact command attempted ⇒ BLIND rc 3, no PASS" {
  for policy in wrong-mode wrong-cmd; do
    STUB_POLICY=$policy probe
    [ "$status" -eq 3 ] || { echo "$policy: $output"; false; }
    if line 'NEG-[A-Z]+' PASS; then echo "$policy: a negative arm passed without a valid attempt: $output"; false; fi
    [[ "$output" == *"verdict=BLIND"* ]] || { echo "$policy: $output"; false; }
  done
}

@test "usage: an unknown argument is refused rc 2 before any session runs" {
  probe --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument --bogus"* ]] || false
  [ -z "$(ls -A "$TMPDIR")" ]
}
