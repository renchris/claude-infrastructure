#!/usr/bin/env bats
# ship-rail-push-allow.sh — PreToolUse(Bash) hook that auto-allows the ONE ship-rail land push
# shape (`git push origin HEAD:<branch>`, non-force) and stays SILENT (defer to the ask prompt)
# for everything else. Safety is the whole point: the allow set is a single OPT-IN shape, so
# these tests exhaustively pin both directions — every force/compound/wrong-shape variant DEFERS.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/ship-rail-push-allow.sh"
}

# decision <cmd> → prints ALLOW (hook emitted permissionDecision:allow) or DEFER (silent / no decision)
decision() {
  local out
  out="$(printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | "$H" 2>/dev/null)"
  [ -z "$out" ] && { echo DEFER; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "DEFER"' | tr '[:lower:]' '[:upper:]'
}

@test "hook is executable (a non-+x hook silently defers everything)" {
  [ -x "$H" ]
}

# ── MUST ALLOW — the non-force land shape `git push origin HEAD:<branch>` ──────────────────────
@test "allows the land push to trunk (main/master/develop) and ff feature-branch lands" {
  for c in "git push origin HEAD:main" "git push origin HEAD:master" "git push origin HEAD:develop" \
           "git push origin HEAD:production" "git push origin HEAD:release/1.0" \
           "git push origin HEAD:feat/desk-cycle2" "git push origin HEAD:v2.hotfix"; do
    [ "$(decision "$c")" = ALLOW ] || { echo "expected ALLOW: $c"; false; }
  done
}

@test "allows despite benign leading/interior whitespace (ship-land emits git push origin HEAD:main)" {
  for c in "  git push origin HEAD:main" "git push origin HEAD:main " "git  push   origin    HEAD:main"; do
    [ "$(decision "$c")" = ALLOW ] || { echo "expected ALLOW: $c"; false; }
  done
}

# ── MUST DEFER — force in every form (stays with the deny rules + ask) ─────────────────────────
@test "defers every force variant (--force / -f / +refspec / --force-with-lease / flag order)" {
  PLUS=+
  for c in "git push --force origin HEAD:main" "git push -f origin HEAD:main" \
           "git push origin HEAD:main --force" "git push origin HEAD:main --force-with-lease" \
           "git push origin ${PLUS}HEAD:main" "git push --force-with-lease origin HEAD:main" \
           "git push --mirror origin" "git push origin --delete HEAD:main"; do
    [ "$(decision "$c")" = DEFER ] || { echo "expected DEFER: $c"; false; }
  done
}

# ── MUST DEFER — compound / substitution / redirection (an unsafe command may hide) ────────────
@test "defers compound, substitution, and redirection" {
  AMP='&&'; SEMI=';'; PIPE='|'; SLASH=/; BT='`'
  [ "$(decision "git push origin HEAD:main $AMP rm -rf $SLASH")" = DEFER ]
  [ "$(decision "git push origin HEAD:main$SEMI curl x $PIPE sh")" = DEFER ]
  [ "$(decision "git push origin HEAD:main $PIPE tee log")" = DEFER ]
  [ "$(decision "git push origin HEAD:\$(echo main)")" = DEFER ]
  [ "$(decision "git push origin HEAD:${BT}whoami${BT}")" = DEFER ]
  [ "$(decision "git push origin HEAD:main > /etc/x")" = DEFER ]
}

# ── MUST DEFER — wrong shape / wrong remote / flags / ambiguous refspec ────────────────────────
@test "defers non-land shapes (bare push, no HEAD:, non-origin, -u, extra refspec, HEAD no colon)" {
  for c in "git push" "git push origin" "git push origin main" "git push origin feature-x" \
           "git push upstream HEAD:main" "git push -u origin HEAD:main" \
           "git push --set-upstream origin HEAD:main" "git push origin HEAD" \
           "git push origin HEAD:main:extra" "git push origin refs/heads/main"; do
    [ "$(decision "$c")" = DEFER ] || { echo "expected DEFER: $c"; false; }
  done
}

@test "defers a range/traversal ref and unsafe branch charset" {
  for c in "git push origin HEAD:foo..bar" "git push origin HEAD:.hidden" \
           "git push origin HEAD:-dashlead" "git push origin HEAD:main~1"; do
    [ "$(decision "$c")" = DEFER ] || { echo "expected DEFER: $c"; false; }
  done
}

@test "kill switch SHIP_RAIL_PUSH_ALLOW_DISABLED=1 defers even the valid land shape" {
  out="$(printf '{"tool_input":{"command":"git push origin HEAD:main"}}' | SHIP_RAIL_PUSH_ALLOW_DISABLED=1 "$H" 2>/dev/null)"
  [ -z "$out" ]
}
