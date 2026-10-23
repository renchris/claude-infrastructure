#!/usr/bin/env bats
# handoff-fire.sh self-close — a claude NESTED inside another session's pane must never close it
# (docs/plans/pane-end-of-life-2026-10-22.md Wave A, items A1-A3; REPORT.md root cause 1).
#
# THE INCIDENT, 2026-10-22 23:16:36Z. Lead 666022fd (pane 16) ran `claude -p --resume 570d3917` from
# its own Bash tool. The child inherited KITTY_WINDOW_ID=16, finished its work, and ran
# `self-close --terminal`. pane_ownership answered "mine" because pane 16's launched pid is an
# ancestor of every process in the child, /exit was typed into the lead's composer, and pane 16 was
# closed with the lead mid-turn. cc-registry/16.json named the lead (pid alive) the whole time.
#
# PINNED HERE:
#   A1  ancestry is "mine" only when the pane's registered live claude is THIS process's own claude;
#       a live tenant that is a strict ancestor of our claude makes it not-mine, and the refusal
#       names both sessions. Keyed on the pid, so a /clear (same pid, new session id) is still ours.
#   A2  a headless run (its claude has no tty) never takes its pane from the environment: it uses
#       the open fire stamp whose transcript is its own, writes only records, and types nothing.
#   A3  the watcher re-reads the registry at the close instant and aborts if the pane now holds a
#       different live session.
#
# The ancestry is a ps shim; the one LIVE pid (the tenant) is a `sleep` this suite starts and stops.
# Nothing here reaches a real pane: $HOME, the registry, the fired dir and the it2 shim are fixtured.

load helpers/cc-stub

setup() {
  command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; return 1; }
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  unset KITTY_WINDOW_ID CLAUDE_CODE_ENTRYPOINT
  export IT2_WRAPPER_NO_KITTY=1 CC_TERM=iterm2
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-registry" "$HOME/.claude/cc-roles"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/.claude-next"
  FIRED="$HOME/.claude/cc-fired"; mkdir -p "$FIRED"; export CC_FIRED_DIR="$FIRED"
  export CC_REGISTRY_DIR="$HOME/.claude/cc-registry"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox" CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pane-close-queue"
  export CC_SELF_CLOSE_INTENT_DIR="$BATS_TEST_TMPDIR/intent"
  export HF_HANDOFFS_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"
  IT2LOG="$BATS_TEST_TMPDIR/it2.log"; export IT2LOG
  # The it2 shim: lists the one pane, records every other call (a close, a send) and succeeds.
  # CC_SHIM='' keeps it a plain file: handoff-fire reads the shim's own REAL_IT2= line as text.
  CC_SHIM='' cc_stub "$HOME/.claude/bin" it2 "$(printf '#!/bin/bash\nREAL_IT2="%s"\nif [ "$1 $2" = "session list" ]; then echo %s; exit 0; fi\necho "$*" >> "$IT2LOG"\nexit 0' \
    "$HOME/.claude/bin/it2" "'[{\"id\":\"PANE16\"}]'")"
  cc_stub "$HOME/.claude/bin" cc-in-kitty $'#!/bin/bash\nexit 1'

  # THE ONE LIVE PROCESS: the pane's tenant claude. kill -0 must succeed on it, so it is real.
  sleep 600 & LEADPID=$!; export LEADPID
  LEAD="666022fd-0000-4000-8000-000000000016"; CHILD="570d3917-0000-4000-8000-000000000085"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  # THE ANCESTRY. NESTED=1: hf → 9001 bash → 9002 claude (the child) → 9003 bash → LEADPID claude.
  #               NESTED=0: hf → 9001 bash → LEADPID claude (the tenant's own Bash tool).
  # The pane's tty belongs to LEADPID; the child's tty is $CHILD_TTY (?? = headless).
  cc_stub "$SHIM" ps - <<'SH'
#!/usr/bin/env bash
fmt="" pid="" seen_p=0 args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in -o) fmt="$fmt${2:-}"; shift 2 ;; -p) pid="${2:-}"; seen_p=1; shift 2 ;; *) shift ;; esac
done
if [ "$seen_p" = 1 ] && [ "$fmt" = "ppid=" ]; then
  case "$pid" in
    9001) if [ "${NESTED:-1}" = 1 ]; then echo 9002; else echo "$LEADPID"; fi ;;
    9002) echo 9003 ;;
    9003) echo "$LEADPID" ;;
    "$LEADPID") : ;;
    *) echo 9001 ;;
  esac
  exit 0
fi
if [ "$seen_p" = 1 ] && [ "$fmt" = "tty=" ]; then
  IFS=, read -r -a l <<< "$pid"
  for p in "${l[@]}"; do
    case "$p" in "$LEADPID") echo ttysMINE ;; 9002) echo "${CHILD_TTY:-??}" ;; *) echo '??' ;; esac
  done
  exit 0
fi
if [ "$seen_p" = 1 ] && [ "$fmt" = "comm=" ]; then
  case "$pid" in
    "$LEADPID") echo /Users/x/.claude-293/node_modules/.bin/claude ;;
    9002) echo claude ;;
    9001|9003) echo /bin/bash ;;
    *) exec /bin/ps "${args[@]}" ;;
  esac
  exit 0
fi
exec /bin/ps "${args[@]}"
SH
  cc_stub "$SHIM" osascript - <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do case "$1" in -e) shift 2 2>/dev/null || shift ;; -) shift ;; *) uuid="$1"; shift ;; esac; done
if [ -n "$uuid" ]; then [ "$uuid" = PANE16 ] && printf '/dev/ttysMINE'; exit 0; fi
printf 'PANE16\t/dev/ttysMINE\n'
SH
  cc_stub "$SHIM" git $'#!/usr/bin/env bash\n[ "${1:-}" = rev-parse ] && exit 1\nexit 0'
  export PATH="$SHIM:$PATH"

  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"; WORK="$(cd "$WORK" && pwd -P)"
  if ( cd "$WORK" && /usr/bin/git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    echo "FIXTURE BROKEN: \$WORK is inside a git repo" >&2; return 1
  fi
  reg PANE16 "$LEAD" "$LEADPID"
  stamp PANE16 ""                        # pane 16 has a stamp too (the stale 16.json of the incident)
}

teardown() { [ -n "${LEADPID:-}" ] && kill "$LEADPID" 2>/dev/null; return 0; }

reg() { jq -n --arg p "$1" --arg s "$2" --argjson pid "$3" '{paneUUID:$p, session_id:$s, pid:$pid}' > "$CC_REGISTRY_DIR/$1.json"; }
stamp() { # <pane> <transcript>
  jq -n --arg p "$1" --arg c "$WORK" --arg t "$2" \
    '{paneUUID:$p, cwd:$c, firedBy:"nested-suite", firedAt:"2026-10-22T00:00:00Z", selfRetire:true,
      schema:2, originClass:"fired-peer", transcript:(if $t == "" then null else $t end),
      closedAt:null, succession:null}' > "$FIRED/$1.json"
}
sc() { # self-close from $WORK, iTerm2 pane PANE16 claimed by the environment
  run env ITERM_SESSION_ID="w0t0p0:PANE16" /bin/bash -c 'cd "$1" || exit 99; shift; exec /bin/bash "$@"' \
      _ "$WORK" "$HF" self-close --terminal "$@"
}
units() {
  hf_bounded() { "$@"; }
  export REG_DIR="$CC_REGISTRY_DIR"   # read by the extracted units, not by this body
  local f
  for f in own_ancestry_pids own_claude_pid pane_nested_holder pane_tenant_mismatch hf_self_headless; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
  done
}

# ── A1: the nested claude is refused, and both sessions are named ────────────────────────────────

@test "A1: a claude nested in the tenant's pane is REFUSED, naming the tenant and the caller (the pane-16 close)" {
  CHILD_TTY=ttys099 CLAUDE_CODE_SESSION_ID="$CHILD" CC_SELFCLOSE_HEADLESS=0 sc --dry-run
  [ "$status" -eq 2 ] || { echo "status $status — pre-fix this printed the close plan for PANE16"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF "pane PANE16 holds live session ${LEAD:0:8} (claude pid $LEADPID); you are $CHILD" || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -qE '^pane: +PANE16$' || false
}

@test "A1 CONTROL: the tenant's own Bash tool still closes its pane, and the tenant line names it" {
  NESTED=0 CLAUDE_CODE_SESSION_ID="$LEAD" sc --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^pane: +PANE16$' || false
  printf '%s\n' "$output" | grep -qF "tenant:    pane PANE16 holds session $LEAD; you are $LEAD" || { echo "$output"; false; }
}

@test "A1 CONTROL: after a /clear (same claude pid, new session id) the pane is still ours" {
  NESTED=0 CLAUDE_CODE_SESSION_ID="11111111-2222-4333-8444-555555555555" sc --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^pane: +PANE16$' || false
}

@test "A1 ABSTAINS: a registry row whose pid is dead convicts nothing (today's verdict stands)" {
  reg PANE16 "$LEAD" 99999999
  CHILD_TTY=ttys099 CLAUDE_CODE_SESSION_ID="$CHILD" CC_SELFCLOSE_HEADLESS=0 sc --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "A1 unit: pane_nested_holder names the tenant only for a live strict ancestor" {
  units
  export NESTED=1; [ "$(pane_nested_holder PANE16)" = "$LEAD $LEADPID 9002" ]
  export NESTED=0; [ -z "$(pane_nested_holder PANE16)" ]
  [ -z "$(pane_nested_holder NO-SUCH-PANE)" ]
}

# ── A2: a headless run resolves its pane from its own fire stamp, or refuses ──────────────────────

@test "A2: a headless run uses its OWN fire stamp's pane, not the environment's, and types nothing" {
  stamp PANE85 "$CC_PROJECTS_DIRS/-p/$CHILD.jsonl"
  CHILD_TTY='??' CLAUDE_CODE_SESSION_ID="$CHILD" sc --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^pane: +PANE85$' || { echo "pre-fix this targeted PANE16"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'headless:  yes' || { echo "$output"; false; }
}

@test "A2: the real headless close writes closedAt on its own stamp, leaves pane 16's alone, and sends no key" {
  stamp PANE85 "$CC_PROJECTS_DIRS/-p/$CHILD.jsonl"
  export COMPLETION_PUSH_BIN="$BATS_TEST_TMPDIR/no-completion-push"
  CHILD_TTY='??' CLAUDE_CODE_SESSION_ID="$CHILD" sc
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'nothing typed, no pane closed' || { echo "$output"; false; }
  [ "$(jq -r '.closedAt != null' "$FIRED/PANE85.json")" = true ] || { cat "$FIRED/PANE85.json"; false; }
  [ "$(jq -r '.closedAt' "$FIRED/PANE16.json")" = null ] || false
  [ ! -s "$IT2LOG" ] || { echo "it2 was driven:"; cat "$IT2LOG"; false; }
}

@test "A2: a headless run with no stamp of its own is REFUSED, nothing typed" {
  CHILD_TTY='??' CLAUDE_CODE_SESSION_ID="$CHILD" sc --dry-run
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'a headless run has no pane of its own' || { echo "$output"; false; }
}

@test "A2 unit: headless is the claude's tty, and the env var decides only when no claude is found" {
  units
  export NESTED=1 CHILD_TTY='??'; hf_self_headless
  export CHILD_TTY=ttys099; ! hf_self_headless || false
  export CLAUDE_CODE_ENTRYPOINT=sdk-cli; ! hf_self_headless || false   # a tty outranks the env var
}

# ── A3: the close instant re-reads the registry ──────────────────────────────────────────────────

@test "A3 unit: pane_tenant_mismatch convicts only a live tenant that is neither our pid nor our session" {
  units
  pane_tenant_mismatch PANE16 "$CHILD" 9002 >/dev/null
  [ "$(pane_tenant_mismatch PANE16 "$CHILD" 9002)" = "$LEAD $LEADPID" ]
  ! pane_tenant_mismatch PANE16 "$CHILD" "$LEADPID" || false       # same pid: a /clear, ours
  ! pane_tenant_mismatch PANE16 "$LEAD" 9002 || false              # same session
  ! pane_tenant_mismatch PANE16 "" "" || false                     # nothing to compare: abstain
  reg PANE16 "$LEAD" 99999999
  ! pane_tenant_mismatch PANE16 "$CHILD" 9002 || false             # dead tenant: abstain
}

@test "A3: the watcher does NOT close a pane that now holds a different live session" {
  run env HF_SC_EXPECT_SID="$CHILD" HF_SC_EXPECT_PID=9002 HF_SELFCLOSE_GRACE_S=0 \
      /bin/bash "$HF" __selfclose PANE16 /dev/ttysNOSUCH "" "" ""
  printf '%s\n' "$output" | grep -qF "pane PANE16 now holds session $LEAD" || { echo "$output"; false; }
  ! grep -q 'close' "$IT2LOG" 2>/dev/null || { echo "pre-fix the watcher closed it:"; cat "$IT2LOG"; false; }
}

@test "A3 CONTROL: the watcher still closes when the tenant is the session the close was for" {
  run env HF_SC_EXPECT_SID="$LEAD" HF_SC_EXPECT_PID="$LEADPID" HF_SELFCLOSE_GRACE_S=0 \
      /bin/bash "$HF" __selfclose PANE16 /dev/ttysNOSUCH "" "" ""
  grep -q 'session close' "$IT2LOG" || { echo "$output"; false; }
}
