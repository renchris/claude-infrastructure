#!/usr/bin/env bats
# xvendor-review.bats — the cross-vendor review envelope (scripts/xvendor-review.sh; design
# docs/research/lead-keeps-working-2026-10-24.md §3.9 and §7.7, with the step-0 corrections in its header).
#
# WHAT IS LOAD-BEARING. The stub `codex` models what step 0 MEASURED on the real one, not what its flags
# advertise: a model command may read a path only when $CODEX_HOME/config.toml carries the "xvr" profile
# listing that path's root AND no -s/--sandbox flag is on argv (-s overrides the profile; no profile reads
# everything). So "the token is absent from the output" is a verdict on what the wrapper wrote and passed,
# and re-adding `-s read-only` to the wrapper turns the secret case red.
#
# HERMETIC: HOME, CODEX_HOME, TMPDIR, the IDL and the fixture repo all live under $BATS_TEST_TMPDIR, and the
# only `codex` on PATH is the stub. No case makes a model call.

load helpers/cc-stub

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset CC_XVR_METER_STOP CC_XVR_TIMEOUT_S CC_XVR_LOCK_WAIT_S CC_XVR_LOCK_POLL_S OPENAI_BASE_URL
  T="$BATS_TEST_TMPDIR"
  SUT="$BATS_TEST_DIRNAME/../scripts/xvendor-review.sh"
  export TMPDIR="$T/tmp" CC_IDL="$T/idl.jsonl" CODEX_HOME="$HOME/.codex"
  export XVR_STUB_DIR="$T/stub" XVR_TEST_REAL_HOME="$HOME" OPENAI_API_KEY=sk-test-not-real
  mkdir -p "$TMPDIR" "$XVR_STUB_DIR" "$CODEX_HOME/sessions"
  printf 'SECRET-TOKEN-4f9e\n' > "$HOME/secret"
  printf '{"tokens":{"account_id":"acct-1","refresh_token":"r1"}}\n' > "$CODEX_HOME/auth.json"
  chmod 600 "$CODEX_HOME/auth.json"
  printf 'Review this code.\n' > "$T/prompt.txt"

  git init -q -b main "$T/repo"
  mkdir -p "$T/repo/.claude" "$T/repo/secrets" "$T/repo/notes" "$T/repo/src"
  echo committed > "$T/repo/a.txt"; echo key > "$T/repo/secrets/key.pem"; echo pem > "$T/repo/top.pem"
  echo private > "$T/repo/notes/private.md"; echo public > "$T/repo/notes/public.md"; echo code > "$T/repo/src/x.sh"
  printf '# private material\nsecrets/\n*.pem\nnotes/private.md\n\n' > "$T/repo/.claude/xvendor-review.exclude"
  git -C "$T/repo" add -A && git -C "$T/repo" commit -qm base
  echo DIRTY > "$T/repo/a.txt"; echo wip > "$T/repo/untracked.txt"

  cc_stub "$T/bin" codex - <<'EOF'
#!/bin/bash
# Stub codex. Logs argv and env, then emulates the measured permission-profile semantics.
log="$XVR_STUB_DIR/calls.log"
oak=unset; [ -n "${OPENAI_API_KEY+x}" ] && oak=set
obu=unset; [ -n "${OPENAI_BASE_URL+x}" ] && obu=set
{ printf 'argv:'; printf ' [%s]' "$@"; printf '\n'
  printf 'env: HOME=%s CODEX_HOME=%s OPENAI_API_KEY=%s OPENAI_BASE_URL=%s\n' "$HOME" "$CODEX_HOME" "$oak" "$obu"; } >> "$log"
cfg="$CODEX_HOME/config.toml"
allowed() { # <path> -> 0 if a model command could read it under what the wrapper wrote
  local d p root
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  p="$d/$(basename "$1")"
  grep -q '^default_permissions = "xvr"$' "$cfg" 2>/dev/null || return 0   # no profile: reads unconfined
  while IFS= read -r root; do
    case "$p" in "$root"/*) return 0 ;; esac
  done <<<"$(sed -n 's|^"\(/[^"]*\)" = "read"$|\1|p' "$cfg")"
  return 1
}
case "$1" in
  login) printf '%s\n' "${XVR_STUB_LOGIN:-Logged in using ChatGPT}" >&2; exit 0 ;;
  sandbox)
    shift; prof=""
    while [ $# -gt 0 ]; do case "$1" in -P) prof="$2"; shift 2 ;; -C) shift 2 ;; --) shift; break ;; *) shift ;; esac; done
    case "${XVR_STUB_SANDBOX:-deny}" in
      leak) exec "$@" ;;
      broken) echo "Error: failed to load config" >&2; exit 1 ;;
    esac
    if [ "$prof" != xvr ] || ! grep -q '^\[permissions\.xvr\.filesystem\]$' "$cfg" 2>/dev/null; then
      echo "Error: unknown permission profile '$prof'" >&2; exit 1
    fi
    last="${!#}"
    allowed "$last" && exec "$@"
    echo "$1: $last: Operation not permitted" >&2; exit 1 ;;
  exec)
    shift; sflag=0; dir=""
    while [ $# -gt 0 ]; do
      case "$1" in -s|--sandbox|-s*|--sandbox=*) sflag=1 ;; -C) dir="$2"; shift ;; esac
      shift
    done
    cp "$cfg" "$XVR_STUB_DIR/config.seen" 2>/dev/null
    ls -A "$CODEX_HOME" > "$XVR_STUB_DIR/codex-home.ls"
    printf '%s\n' "$dir" > "$XVR_STUB_DIR/export.path"
    (cd "$dir" && find . -type f | LC_ALL=C sort) > "$XVR_STUB_DIR/export.ls"
    cp "$dir/a.txt" "$XVR_STUB_DIR/export-a.txt" 2>/dev/null
    secret="$XVR_TEST_REAL_HOME/secret"
    if [ "$sflag" = 1 ] || allowed "$secret"; then cat "$secret"; else echo "cat: $secret: Operation not permitted"; fi
    case "${XVR_STUB_AUTH:-}" in
      same)  printf '{"tokens":{"account_id":"acct-1","refresh_token":"r2-rotated"}}\n' > "$CODEX_HOME/auth.json" ;;
      other) printf '{"tokens":{"account_id":"acct-OTHER","refresh_token":"r9"}}\n' > "$CODEX_HOME/auth.json" ;;
      junk)  printf 'not json\n' > "$CODEX_HOME/auth.json" ;;
    esac
    if [ -n "${XVR_STUB_ROLLOUT:-}" ]; then
      mkdir -p "$CODEX_HOME/sessions/2025/01/01"
      printf '{"payload":{"rate_limits":{"primary":{"used_percent":%s,"window_minutes":10080,"resets_at":%s},"secondary":null}}}\n' \
        "$XVR_STUB_ROLLOUT" "$(( $(date +%s) + 86400 ))" > "$CODEX_HOME/sessions/2025/01/01/rollout-xvr-run.jsonl"
    fi
    echo "REVIEW: stub review of $dir"
    exit "${XVR_STUB_EXEC_RC:-0}" ;;
esac
echo "stub codex: unhandled $*" >&2; exit 64
EOF
  export PATH="$T/bin:$PATH"
}

rollout() { # <name> <rate_limits json|-> — "-" writes a line with no rate_limits
  mkdir -p "$CODEX_HOME/sessions/2025/01/01"
  if [ "$2" = - ]; then printf '{"payload":{"type":"turn"}}\n' > "$CODEX_HOME/sessions/2025/01/01/rollout-$1.jsonl"
  else printf '{"payload":{"rate_limits":%s}}\n' "$2" > "$CODEX_HOME/sessions/2025/01/01/rollout-$1.jsonl"; fi
}
weekly() { # <used> [resets_at] → a rate_limits object with one weekly primary window
  printf '{"primary":{"used_percent":%s,"window_minutes":10080,"resets_at":%s},"secondary":null}' \
    "$1" "${2:-$(( $(date +%s) + 86400 ))}"
}
review() { run "$SUT" "$T/repo" "$T/prompt.txt" "$@"; }
exec_called() { grep -q '^argv: \[exec\]' "$XVR_STUB_DIR/calls.log" 2>/dev/null; }

@test "79% runs: review on stdout, one IDL row with the meter, the sha and the confinement" {
  rollout r1 "$(weekly 79)"
  review
  [ "$status" -eq 0 ]
  [[ "$output" == *"REVIEW: stub review of"* ]] || false
  [ "$(wc -l < "$CC_IDL" | tr -d ' ')" -eq 1 ]
  jq -e --arg sha "$(git -C "$T/repo" rev-parse HEAD)" \
    '.tool == "xvendor-review" and .rc == 0 and .meter_before == 79 and .rev == $sha
     and .confine == "codex-permission-profile"' "$CC_IDL"
}

@test "80% refuses with rc 5 and codex exec is never launched" {
  rollout r1 "$(weekly 80)"
  review
  [ "$status" -eq 5 ]
  ! exec_called || false
  jq -e '.rc == 5 and .meter_before == 80' "$CC_IDL"
}

@test "CC_XVR_METER_STOP moves the stop" {
  rollout r1 "$(weekly 50)"
  CC_XVR_METER_STOP=40 review
  [ "$status" -eq 5 ]
}

@test "a rollout with no rate_limits fails closed with rc 4" {
  rollout r1 -
  review
  [ "$status" -eq 4 ]
  ! exec_called || false
  run "$SUT" --meter
  [ "$status" -eq 4 ]
}

@test "no rollouts at all: runs, with a never-used note" {
  review
  [ "$status" -eq 0 ]
  [[ "$output" == *"never used"* ]] || false
  exec_called
  jq -e '.meter_before == null' "$CC_IDL"
}

@test "the 10080-minute window is chosen over a shorter primary" {
  rollout r1 "{\"primary\":{\"used_percent\":95,\"window_minutes\":300,\"resets_at\":$(( $(date +%s) + 3600 ))},\"secondary\":{\"used_percent\":10,\"window_minutes\":10080,\"resets_at\":$(( $(date +%s) + 86400 ))}}"
  run "$SUT" --meter
  [ "$status" -eq 0 ]
  [[ "$output" == *"used_percent=10 window_minutes=10080 source=$CODEX_HOME/sessions/"* ]] || false
  review
  [ "$status" -eq 0 ]
}

@test "a 95% reading whose resets_at has passed counts as 0 and says window expired" {
  rollout r1 "$(weekly 95 "$(( $(date +%s) - 3600 ))")"
  review
  [ "$status" -eq 0 ]
  [[ "$output" == *"window expired"* ]] || false
  jq -e '.meter_before == 0' "$CC_IDL"
}

@test "argv carries no -s/--sandbox; the stub sees no OPENAI_API_KEY and HOME = CODEX_HOME = the temp home" {
  review --model gpt-test
  [ "$status" -eq 0 ]
  line="$(grep '^argv: \[exec\]' "$XVR_STUB_DIR/calls.log")"
  [[ "$line" == *"[--skip-git-repo-check] [-C] [$(cat "$XVR_STUB_DIR/export.path")] [-m] [gpt-test]"* ]] || false
  ! grep -E '\[(-s|--sandbox|--add-dir|--approve-for-me|--dangerously[^]]*)\]' "$XVR_STUB_DIR/calls.log" || false
  ! grep -q 'OPENAI_API_KEY=set' "$XVR_STUB_DIR/calls.log" || false
  ! grep -q 'OPENAI_BASE_URL=set' "$XVR_STUB_DIR/calls.log" || false
  env_line="$(grep -A1 '^argv: \[exec\]' "$XVR_STUB_DIR/calls.log" | tail -1)"
  ch="${env_line#*HOME=}"; ch="${ch%% *}"
  [[ "$env_line" == *"CODEX_HOME=$ch "* ]] || false
  [ "$ch" != "$HOME" ]
  [ "$(cat "$XVR_STUB_DIR/codex-home.ls")" = "$(printf 'auth.json\nconfig.toml')" ]
}

@test "config.toml held default_permissions = xvr naming only :minimal and the export" {
  review
  [ "$status" -eq 0 ]
  exp="$(cat "$XVR_STUB_DIR/export.path")"
  grep -qx 'default_permissions = "xvr"' "$XVR_STUB_DIR/config.seen"
  grep -qx '\[permissions.xvr.filesystem\]' "$XVR_STUB_DIR/config.seen"
  [ "$(grep -c '= "read"$' "$XVR_STUB_DIR/config.seen")" -eq 2 ]
  grep -qx '":minimal" = "read"' "$XVR_STUB_DIR/config.seen"
  grep -qxF "\"$exp\" = \"read\"" "$XVR_STUB_DIR/config.seen"
  [ "$exp" = "$(cd "$exp" 2>/dev/null && pwd -P || echo "$exp")" ]
}

@test "read confinement: the model's cat of \$HOME/secret does not reach the output" {
  review
  [ "$status" -eq 0 ]
  [[ "$output" != *"SECRET-TOKEN-4f9e"* ]] || false
  [[ "$output" == *"Operation not permitted"* ]] || false
}

@test "a confinement that lets the canary through: rc 6 and codex exec never launched" {
  XVR_STUB_SANDBOX=leak review
  [ "$status" -eq 6 ]
  ! exec_called || false
  grep -q '^argv: \[sandbox\] \[-P\] \[xvr\]' "$XVR_STUB_DIR/calls.log"
  jq -e '.rc == 6' "$CC_IDL"
}

@test "a canary probe that errors without a sandbox denial (profile not loaded): rc 6" {
  XVR_STUB_SANDBOX=broken review
  [ "$status" -eq 6 ]
  ! exec_called || false
}

@test "the export holds committed bytes only, minus the exclude list" {
  review
  [ "$status" -eq 0 ]
  ls_="$(cat "$XVR_STUB_DIR/export.ls")"
  [[ "$ls_" == *"./a.txt"* && "$ls_" == *"./notes/public.md"* && "$ls_" == *"./src/x.sh"* ]] || false
  [[ "$ls_" != *untracked.txt* ]] || false
  [[ "$ls_" != *secrets* && "$ls_" != *.pem* && "$ls_" != *private.md* ]] || false
  [ "$(cat "$XVR_STUB_DIR/export-a.txt")" = committed ]
}

@test "an exclude path with .. or an absolute path refuses with rc 2" {
  printf '../outside\n' > "$T/repo/.claude/xvendor-review.exclude"
  review
  [ "$status" -eq 2 ]
  ! exec_called || false
  printf '/etc/hosts\n' > "$T/repo/.claude/xvendor-review.exclude"
  review
  [ "$status" -eq 2 ]
}

@test "a non-ChatGPT login refuses with rc 3 and codex exec is never launched" {
  XVR_STUB_LOGIN="Logged in using an API key - sk-***" review
  [ "$status" -eq 3 ]
  ! exec_called || false
}

@test "a rev that is not a commit refuses with rc 2" {
  review --rev deadbeefdeadbeef
  [ "$status" -eq 2 ]
  ! exec_called || false
}

@test "temp dirs, canary and lock are gone afterwards, on success and on refusal" {
  review
  [ "$status" -eq 0 ]
  XVR_STUB_SANDBOX=leak review
  [ "$status" -eq 6 ]
  [ -z "$(ls -A "$TMPDIR")" ]
  [ -z "$(find "$HOME/.cache" -name 'xvr-canary.*' 2>/dev/null)" ]
}

@test "codex's own rc passes through" {
  XVR_STUB_EXEC_RC=7 review
  [ "$status" -eq 7 ]
  jq -e '.rc == 7' "$CC_IDL"
}

@test "a refreshed same-account auth.json is copied back atomically with mode 0600" {
  XVR_STUB_AUTH=same review
  [ "$status" -eq 0 ]
  jq -e '.tokens.refresh_token == "r2-rotated"' "$CODEX_HOME/auth.json"
  [ "$(stat -f '%Lp' "$CODEX_HOME/auth.json")" = 600 ]
  [ -z "$(find "$CODEX_HOME" -maxdepth 1 -name '.auth.json.xvr.*')" ]
}

@test "a different-account or invalid auth.json is never copied back" {
  XVR_STUB_AUTH=other review
  [ "$status" -eq 0 ]
  jq -e '.tokens.account_id == "acct-1" and .tokens.refresh_token == "r1"' "$CODEX_HOME/auth.json"
  XVR_STUB_AUTH=junk review
  [ "$status" -eq 0 ]
  jq -e '.tokens.refresh_token == "r1"' "$CODEX_HOME/auth.json"
}

@test "the run's rollout is copied back so the next meter read sees its spend" {
  rollout r0 "$(weekly 20)"
  touch -t 202501010000 "$CODEX_HOME/sessions/2025/01/01/rollout-r0.jsonl"
  XVR_STUB_ROLLOUT=81 review
  [ "$status" -eq 0 ]
  [ -f "$CODEX_HOME/sessions/2025/01/01/rollout-xvr-run.jsonl" ]
  run "$SUT" --meter
  [[ "$output" == *"used_percent=81 "* ]] || false
  review
  [ "$status" -eq 5 ]
}

@test "a held lock: the second call waits, then reads the meter again" {
  rollout r1 "$(weekly 10)"
  mkdir "$TMPDIR/xvr-meter.lock" && echo "$$" > "$TMPDIR/xvr-meter.lock/pid"
  # Keyed on the script's own "waiting" line, not on a sleep: under load a fixed delay can release the
  # lock before the script reaches it, and then nothing about waiting is tested.
  CC_XVR_LOCK_POLL_S=0.2 CC_XVR_LOCK_WAIT_S=120 "$SUT" "$T/repo" "$T/prompt.txt" > "$T/held.out" 2>&1 3>&- &
  pid=$!
  for _ in $(seq 1 600); do grep -q 'waiting' "$T/held.out" && break; sleep 0.2; done
  grep -q "meter lock held by pid $$: waiting" "$T/held.out"
  printf '{"payload":{"rate_limits":%s}}\n' "$(weekly 95)" > "$CODEX_HOME/sessions/2025/01/01/rollout-r1.jsonl"
  rm -f "$TMPDIR/xvr-meter.lock/pid"; rmdir "$TMPDIR/xvr-meter.lock"
  rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 5 ]
  ! exec_called || false
}

@test "a lock held past CC_XVR_LOCK_WAIT_S refuses with rc 4; a dead holder's lock is taken" {
  rollout r1 "$(weekly 10)"
  mkdir "$TMPDIR/xvr-meter.lock" && echo "$$" > "$TMPDIR/xvr-meter.lock/pid"
  CC_XVR_LOCK_POLL_S=0.2 CC_XVR_LOCK_WAIT_S=1 review
  [ "$status" -eq 4 ]
  ! exec_called || false
  [ -d "$TMPDIR/xvr-meter.lock" ]
  sh -c 'exit 0' & dead=$!; wait "$dead"
  echo "$dead" > "$TMPDIR/xvr-meter.lock/pid"
  review
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale meter lock"* ]] || false
  [ ! -e "$TMPDIR/xvr-meter.lock" ]
}
