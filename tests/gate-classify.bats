#!/usr/bin/env bats
# gate-classify.sh — route a STOP-ASK boundary to exactly ONE class A|B|C + reason.
#   C  = a C10/authority-ceiling surface (settings.json/hooks/launchd/plist/permissions/
#        money-path/credentials) — human-only, checked FIRST (never demotable to A).
#   A  = the standing values SETTLE it (ship-at-green verified work / do-both-if-net-positive /
#        time-zero) — auto-decide.
#   B  = DEFAULT. Any doubt routes B (asymmetric — a false-A is the catastrophic branch).
# Input: args ("$*") or stdin. Output: "<CLASS> <reason>" on stdout, exit 0.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GC="$REPO/scripts/gate-classify.sh"
}

cls() { bash "$GC" "$@" | awk '{print $1}'; }

# ── C — every authority-ceiling surface, incl. adversarial phrasings ────────────
@test "settings.json edit → C" {
  [ "$(cls 'edit settings.json to add an allow rule')" = C ]
}

@test "adversarial 'just symlink the settings' → C, NEVER A" {
  run bash "$GC" "just symlink the settings into place, it's trivial"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | awk '{print $1}')" = C ]
  [ "$(echo "$output" | awk '{print $1}')" != A ]
}

@test "adversarial 'quickly tweak the launchd plist' → C" {
  [ "$(cls 'quickly tweak the launchd plist to add the job')" = C ]
}

@test "live hook edit → C" {
  [ "$(cls 'modify the anti-deference hook in place')" = C ]
}

@test "credential request → C" {
  [ "$(cls 'I need your API key to proceed')" = C ]
  [ "$(cls 'please provide the password for the account')" = C ]
}

@test "money-path payment commitment → C" {
  [ "$(cls 'authorize the payment and enter the credit card')" = C ]
  [ "$(cls 'raise the spend cap on the billing account')" = C ]
}

@test "permission-system change → C" {
  [ "$(cls 'add a permission to the allowlist and reload')" = C ]
}

# ── C beats A when BOTH signals are present (asymmetric) ────────────────────────
@test "C wins over A: 'ship the settings.json change at green' → C not A" {
  [ "$(cls 'ship the settings.json change at green')" = C ]
}

# ── A — the standing values settle it ──────────────────────────────────────────
@test "ship verified work at green → A" {
  [ "$(cls 'ship the verified green diff — autonomous at green')" = A ]
}

@test "net-positive / do both → A" {
  [ "$(cls 'this is net-positive, do both')" = A ]
}

@test "time-zero act-now → A" {
  [ "$(cls 'act now, time-zero, do not wait')" = A ]
}

# ── B — default; any doubt ─────────────────────────────────────────────────────
@test "ambiguous novel decision → B (not A)" {
  c="$(cls 'should the module naming scheme be snake or camel here')"
  [ "$c" = B ]
  [ "$c" != A ]
}

@test "value-fork the values do not settle → B" {
  [ "$(cls 'do you prefer approach one or approach two for the API shape')" = B ]
}

# ── B — the monthly-spend case (task 6 acceptance) ─────────────────────────────
@test "monthly-spend (no reset time) routes B, NOT C money-path, NOT A" {
  c="$(cls 'monthly spend cap reached with no reset time — wait or continue on another account')"
  [ "$c" = B ]
}

# ── T-P15-7: the limit-recover CC_UNATTENDED doc's verbatim decision texts route B ─────────────
@test "T-P15-7: limit-recover monthly-spend packet text (verbatim from the doc) → B" {
  [ "$(cls 'monthly spend cap reached on next2 — no reset time')" = B ]
}
@test "T-P15-7: limit-recover 5h/weekly wait-vs-switch text (verbatim from the doc) → B" {
  [ "$(cls 'hit a 5h/weekly limit on next; reset 2026-07-19T03:00:00Z. Wait for reset, or continue cross-account?')" = B ]
}
@test "T-P15-7: a spend-cap RAISE (money commitment) stays C, never auto-signed" {
  [ "$(cls 'raise the spend cap on the billing account')" = C ]
}

# ── stdin path + single-class guarantee ────────────────────────────────────────
@test "reads from stdin when no args" {
  run bash -c "echo 'edit settings.json' | bash '$GC'"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | awk '{print $1}')" = C ]
}

@test "always emits exactly one of A|B|C as the first token" {
  for t in "ship at green" "edit the plist" "maybe refactor this someday" "need your token"; do
    first="$(cls "$t")"
    [[ "$first" =~ ^[ABC]$ ]]
  done
}

@test "reason is non-empty and names the class rationale" {
  run bash "$GC" "edit settings.json"
  echo "$output" | grep -qE 'C .+'
}
