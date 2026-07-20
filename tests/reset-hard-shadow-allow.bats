#!/usr/bin/env bats
# reset-hard-shadow-allow.sh — state-predicated PreToolUse(Bash) hook that auto-allows the ONE
# reflog-reversible reset shape (`git reset --hard origin/main|@{u}`) ONLY when the tree is clean
# AND cwd is a linked worktree AND (for an ALLOW, not just a would-allow log) the arm sentinel is
# present. Safety is the whole point, so this matrix pins BOTH directions exhaustively: every
# dirty-tree / primary-checkout / non-repo / compound / other-target / flagged / kill-switched
# variant DEFERS, and SHADOW (unarmed) never emits a decision — it only logs a would-allow.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/reset-hard-shadow-allow.sh"
  WORK="$(mktemp -d)"
  export CC_RESET_HARD_STATE_DIR="$WORK/state"
  export CC_RESET_HARD_LOG="$WORK/soak.jsonl"

  # bare origin ← primary (main, one commit) → two linked worktrees (one clean, one dirty)
  git init -q --bare "$WORK/origin.git"
  git init -q "$WORK/primary"
  git -C "$WORK/primary" config user.email t@t.test
  git -C "$WORK/primary" config user.name  tester
  git -C "$WORK/primary" commit -q --allow-empty -m init
  git -C "$WORK/primary" branch -M main
  git -C "$WORK/primary" remote add origin "$WORK/origin.git"
  git -C "$WORK/primary" push -q -u origin main
  git -C "$WORK/primary" worktree add -q -b feat/x "$WORK/linked" main
  git -C "$WORK/primary" worktree add -q -b feat/y "$WORK/dirty" main
  echo change > "$WORK/dirty/untracked.txt"
  mkdir -p "$WORK/norepo"

  LINKED="$WORK/linked"; DIRTY="$WORK/dirty"; PRIMARY="$WORK/primary"; NOREPO="$WORK/norepo"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

arm()    { "$H" arm --confirm >/dev/null 2>&1; }
disarm() { "$H" shadow        >/dev/null 2>&1; }

# decision <cmd> <cwd> → ALLOW (hook emitted permissionDecision:allow) or DEFER (silent)
decision() {
  local out
  out="$(printf '{"tool_input":{"command":%s},"cwd":%s}' \
          "$(jq -Rn --arg c "$1" '$c')" "$(jq -Rn --arg d "$2" '$d')" | "$H" 2>/dev/null)"
  [ -z "$out" ] && { echo DEFER; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "DEFER"' | tr '[:lower:]' '[:upper:]'
}

@test "hook is executable (a non-+x hook silently defers everything)" {
  [ -x "$H" ]
}

# ── SHADOW (default, unarmed): the valid shape LOGS would-allow but emits NO decision ─────────
@test "SHADOW default: valid shape on clean linked worktree DEFERS (no decision) and logs would-allow" {
  [ "$(decision "git reset --hard origin/main" "$LINKED")" = DEFER ]
  [ -f "$CC_RESET_HARD_LOG" ]
  grep -q '"decision":"would-allow"' "$CC_RESET_HARD_LOG"
  # and NOT an allow (shadow must never emit/record an allow)
  ! grep -q '"decision":"allow"' "$CC_RESET_HARD_LOG"
}

# ── ARMED: the two proven-reversible targets on a clean linked worktree → ALLOW ───────────────
@test "ARMED: allows 'git reset --hard origin/main' on a clean linked worktree" {
  arm
  [ "$(decision "git reset --hard origin/main" "$LINKED")" = ALLOW ]
}

@test "ARMED: allows 'git reset --hard @{u}' on a clean linked worktree" {
  arm
  [ "$(decision 'git reset --hard @{u}' "$LINKED")" = ALLOW ]
}

@test "ARMED: allows despite benign leading/interior/trailing whitespace" {
  arm
  for c in "  git reset --hard origin/main" "git reset --hard origin/main " "git  reset   --hard    origin/main"; do
    [ "$(decision "$c" "$LINKED")" = ALLOW ] || { echo "expected ALLOW: [$c]"; false; }
  done
}

@test "ARMED: logs an allow event when it allows" {
  arm
  decision "git reset --hard origin/main" "$LINKED" >/dev/null
  grep -q '"decision":"allow"' "$CC_RESET_HARD_LOG"
}

# ── ARMED but a STATE conjunct fails → DEFER ──────────────────────────────────────────────────
@test "ARMED: DEFERS on a DIRTY tree (uncommitted work would be lost — not reflog-reversible)" {
  arm
  [ "$(decision "git reset --hard origin/main" "$DIRTY")" = DEFER ]
}

@test "ARMED: DEFERS in the PRIMARY checkout (not a linked worktree — concurrent-session hazard)" {
  arm
  [ "$(decision "git reset --hard origin/main" "$PRIMARY")" = DEFER ]
}

@test "ARMED: DEFERS in a non-repo directory" {
  arm
  [ "$(decision "git reset --hard origin/main" "$NOREPO")" = DEFER ]
}

# ── ARMED: SHAPE guards — compound / substitution / redirection / newline all DEFER ───────────
@test "ARMED: DEFERS compound, substitution, redirection, newline" {
  arm
  AMP='&&'; SEMI=';'; PIPE='|'; BT='`'; NL=$'\n'
  [ "$(decision "git reset --hard origin/main $AMP rm -rf /" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard origin/main$SEMI curl x $PIPE sh" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard origin/main $PIPE tee log" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard \$(echo origin/main)" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard ${BT}echo origin/main${BT}" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard origin/main > /etc/x" "$LINKED")" = DEFER ]
  [ "$(decision "git reset --hard origin/main${NL}echo x" "$LINKED")" = DEFER ]
}

# ── ARMED: TARGET guards — anything but origin/main | @{u} DEFERS ─────────────────────────────
@test "ARMED: DEFERS every non-allowlisted target" {
  arm
  for t in "HEAD" "HEAD~1" "HEAD^" "origin/develop" "origin/feature-x" "1a2b3c4d" "main" "@{u}x" "origin/main/" "origin/main~1"; do
    [ "$(decision "git reset --hard $t" "$LINKED")" = DEFER ] || { echo "expected DEFER target: [$t]"; false; }
  done
}

# ── ARMED: FLAG / PREFIX / SHAPE guards — extra flag, wrong mode, -C, env-prefix, comment ─────
@test "ARMED: DEFERS extra flags, wrong reset mode, -C redirect, env-prefix, trailing comment, no target" {
  arm
  for c in "git reset --hard --quiet origin/main" "git reset --quiet --hard origin/main" \
           "git reset --soft origin/main" "git reset --keep origin/main" "git reset --hard=origin/main" \
           "git -C /elsewhere reset --hard origin/main" "FOO=1 git reset --hard origin/main" \
           "git reset --hard origin/main # oops" "git reset --hard origin/main extra" \
           "git reset --hard" "git reset --hard "; do
    [ "$(decision "$c" "$LINKED")" = DEFER ] || { echo "expected DEFER: [$c]"; false; }
  done
}

# ── Kill switch + malformed input ─────────────────────────────────────────────────────────────
@test "kill switch RESET_HARD_ALLOW_DISABLED=1 defers even the armed valid shape and writes no log" {
  arm
  out="$(printf '{"tool_input":{"command":"git reset --hard origin/main"},"cwd":%s}' "$(jq -Rn --arg d "$LINKED" '$d')" \
        | RESET_HARD_ALLOW_DISABLED=1 "$H" 2>/dev/null)"
  [ -z "$out" ]
  [ ! -f "$CC_RESET_HARD_LOG" ]
}

@test "malformed JSON input defers without crashing" {
  run bash -c "printf 'not json at all' | '$H'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── CLI: arm requires --confirm; status reflects mode; shadow reverts ─────────────────────────
@test "CLI: bare 'arm' REFUSES (exit 2) and creates no sentinel; 'arm --confirm' arms; 'shadow' reverts" {
  run "$H" arm
  [ "$status" -eq 2 ]
  [ ! -f "$CC_RESET_HARD_STATE_DIR/armed" ]

  run "$H" arm --confirm
  [ "$status" -eq 0 ]
  [ -f "$CC_RESET_HARD_STATE_DIR/armed" ]
  "$H" status | grep -q "mode: ARMED"

  run "$H" shadow
  [ "$status" -eq 0 ]
  [ ! -f "$CC_RESET_HARD_STATE_DIR/armed" ]
  "$H" status | grep -q "mode: SHADOW"
}
