#!/usr/bin/env bats
# gate-manifest.sh — the C1..C10 pre-signed ruling-class manifest (axis c, P1/P2/P4/P7).
#   The operator PRE-SIGNS in-class ruling CLASSES at wave start; an in-class ruling then
#   auto-ratifies + auto-stamps a `Ratified-By: operator (pre-signed class Cn, manifest ...)`
#   trailer; an out-of-class ruling STOP-ASKs. gate-classify.sh (P3) says A|B|C on the SURFACE;
#   this is the G-manifest gate (class ∈ current NON-EXPIRED manifest) — they compose.
#
#   THE ASYMMETRY (load-bearing, mirrors gate-classify + cc-bind): {C1-C5,C7} pre-signable;
#   {C6 money, C8 go} conditional (out-of-class BY DEFAULT); {C9 /ship, C10 self-mod} PERMANENT
#   exclusion — never signable, never stampable. check/stamp FAIL-CLOSED: any doubt (no manifest,
#   expired, out-of-class) is a LOUD non-zero, NEVER a silent pass.
#
# Exit: check/stamp → 0 in-class · 1 out-of-class OR indeterminate (fail-closed) · 2 usage.
#       sign → 0 written · 2 refused/usage (LOUD).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GM="$REPO/scripts/gate-manifest.sh"
  export CC_GATE_MANIFEST_DIR="$BATS_TEST_TMPDIR/gate-manifest"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Deterministic clock for every expiry comparison. ISO-8601-Z sorts lexi == chrono.
  export CC_NOW="2026-07-19T12:00:00Z"
}

# helper: sign a normal in-class wave that is valid for an hour past CC_NOW
sign_ok() { bash "$GM" sign --wave "${1:-W1}" --classes "${2:-C1,C3,C7}" --expiry "2026-07-19T13:00:00Z"; }

# ── P1 registry — the C1..C10 signability map is data, complete, and correct ────
@test "classes lists all ten C1..C10" {
  run bash "$GM" classes
  [ "$status" -eq 0 ]
  for c in C1 C2 C3 C4 C5 C6 C7 C8 C9 C10; do
    echo "$output" | grep -qE "(^|[^0-9])$c([^0-9]|$)" || { echo "missing $c"; false; }
  done
}

@test "classes marks {C1-C5,C7} presignable, {C6,C8} conditional, {C9,C10} excluded" {
  run bash "$GM" classes
  for c in C1 C2 C3 C4 C5 C7; do echo "$output" | grep -E "(^|[^0-9])$c([^0-9]|$)" | grep -qi presignable || { echo "$c not presignable"; false; }; done
  for c in C6 C8;             do echo "$output" | grep -E "(^|[^0-9])$c([^0-9]|$)" | grep -qi conditional || { echo "$c not conditional"; false; }; done
  for c in C9 C10;            do echo "$output" | grep -E "(^|[^0-9])$c([^0-9]|$)" | grep -qi excluded    || { echo "$c not excluded"; false; }; done
}

# ── P2 sign — writes a manifest for the pre-signable set ────────────────────────
@test "sign a presignable set writes a manifest with wave, classes, expiry" {
  run sign_ok W5 "C1,C3,C7"
  [ "$status" -eq 0 ]
  f="$CC_GATE_MANIFEST_DIR/W5.json"
  [ -f "$f" ]
  run jq -r '.wave' "$f";                        [ "$output" = "W5" ]
  run jq -r '.classes | sort | join(",")' "$f";  [ "$output" = "C1,C3,C7" ]
  run jq -e 'has("signed_at") and has("expiry") and has("by")' "$f"; [ "$status" -eq 0 ]
}

@test "sign normalizes lowercase class tokens to canonical Cn" {
  run bash "$GM" sign --wave W6 --classes "c1,c3" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 0 ]
  run jq -r '.classes | sort | join(",")' "$CC_GATE_MANIFEST_DIR/W6.json"
  [ "$output" = "C1,C3" ]
}

# ── THE ASYMMETRY — sign REFUSES the excluded + conditional classes, LOUD ───────
@test "sign REFUSES C10 (self-mod) — LOUD, no manifest written" {
  run bash "$GM" sign --wave WX --classes "C1,C10" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "C10"
  [ ! -f "$CC_GATE_MANIFEST_DIR/WX.json" ]
}

@test "sign REFUSES C9 (/ship) — permanent exclusion" {
  run bash "$GM" sign --wave WX --classes "C9" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "C9"
}

@test "sign REFUSES C6 (money) without --allow-conditional" {
  run bash "$GM" sign --wave WX --classes "C1,C6" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "conditional"
  [ ! -f "$CC_GATE_MANIFEST_DIR/WX.json" ]
}

@test "sign REFUSES C8 (next-wave-go) without --allow-conditional" {
  run bash "$GM" sign --wave WX --classes "C8" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
}

@test "sign ALLOWS C6 WITH --allow-conditional (deliberate operator opt-in)" {
  run bash "$GM" sign --wave W7 --classes "C1,C6" --allow-conditional --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 0 ]
  run jq -r '.classes | sort | join(",")' "$CC_GATE_MANIFEST_DIR/W7.json"
  [ "$output" = "C1,C6" ]
}

@test "sign still REFUSES C10 even WITH --allow-conditional (never demotable)" {
  run bash "$GM" sign --wave WX --classes "C10" --allow-conditional --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
}

@test "sign REFUSES an unknown class token" {
  run bash "$GM" sign --wave WX --classes "C1,C11" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
  run bash "$GM" sign --wave WX --classes "C0" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
  run bash "$GM" sign --wave WX --classes "garbage" --expiry "2026-07-19T13:00:00Z"
  [ "$status" -eq 2 ]
}

@test "sign requires --wave and --classes" {
  run bash "$GM" sign --classes "C1" --expiry "2026-07-19T13:00:00Z"; [ "$status" -eq 2 ]
  run bash "$GM" sign --wave WX --expiry "2026-07-19T13:00:00Z";      [ "$status" -eq 2 ]
}

# ── P4/G-manifest check — in-class passes, everything else FAILS CLOSED ──────────
@test "check an IN-CLASS class → exit 0" {
  sign_ok W1 "C1,C3,C7"
  run bash "$GM" check C1; [ "$status" -eq 0 ]
  run bash "$GM" check C7; [ "$status" -eq 0 ]
}

@test "check an OUT-OF-CLASS class (not in the signed set) → exit 1 fail-closed" {
  sign_ok W1 "C1,C3,C7"
  run bash "$GM" check C2
  [ "$status" -eq 1 ]
}

@test "check with NO manifest at all → exit 1 fail-closed, LOUD" {
  run bash "$GM" check C1
  [ "$status" -eq 1 ]
  echo "$output" | grep -qiE "no .*manifest|out-of-class|not pre-signed"
}

@test "check C9 / C10 are NEVER in-class → exit 1 even alongside a signed manifest" {
  sign_ok W1 "C1,C3,C7"
  run bash "$GM" check C9;  [ "$status" -eq 1 ]
  run bash "$GM" check C10; [ "$status" -eq 1 ]
}

@test "check normalizes case — 'c10' cannot sneak past the exclusion" {
  sign_ok W1 "C1,C3,C7"
  run bash "$GM" check c10; [ "$status" -eq 1 ]
  run bash "$GM" check c1;  [ "$status" -eq 0 ]
}

# ── P7 per-wave expiry — a STALE manifest ⇒ all out-of-class ────────────────────
@test "check an EXPIRED manifest → exit 1 (P7: stale ⇒ all out-of-class)" {
  bash "$GM" sign --wave W3 --classes "C1,C3,C7" --expiry "2026-07-19T11:00:00Z"  # 1h BEFORE CC_NOW
  run bash "$GM" check C1
  [ "$status" -eq 1 ]
  echo "$output" | grep -qiE "expired|stale|out-of-class"
}

@test "check honours --expiry +Nh convenience (future) → in-class right after signing" {
  run bash "$GM" sign --wave W8 --classes "C1" --expiry "+2h"
  [ "$status" -eq 0 ]
  run bash "$GM" check --wave W8 C1
  [ "$status" -eq 0 ]
}

# ── P4 auto-stamp — the Ratified-By trailer, and the P6-backstop-grep invariant ──
@test "stamp an IN-CLASS class prints a Ratified-By trailer, exit 0" {
  sign_ok W5 "C1,C3,C7"
  run bash "$GM" stamp --wave W5 C1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^Ratified-By: '
  echo "$output" | grep -qE 'C1'
  echo "$output" | grep -qE 'W5'
}

@test "P6 INVARIANT: the trailer contains the literal 'pre-signed class' (ship-land grep key)" {
  sign_ok W5 "C1,C3,C7"
  run bash "$GM" stamp --wave W5 C3
  [ "$status" -eq 0 ]
  # ship-land.sh's backstop is `git log --grep 'pre-signed class'` — the trailer MUST contain it
  echo "$output" | grep -qF 'pre-signed class'
}

@test "stamp an OUT-OF-CLASS class REFUSES — exit 1, LOUD, NO trailer on stdout" {
  sign_ok W5 "C1,C3,C7"
  run bash "$GM" stamp --wave W5 C2
  [ "$status" -eq 1 ]
  ! echo "$output" | grep -qE '^Ratified-By: '
}

@test "stamp on an EXPIRED manifest REFUSES — exit 1" {
  bash "$GM" sign --wave W3 --classes "C1" --expiry "2026-07-19T11:00:00Z"
  run bash "$GM" stamp --wave W3 C1
  [ "$status" -eq 1 ]
}

@test "stamp C9/C10 REFUSES unconditionally — exit 1" {
  sign_ok W5 "C1,C3,C7"
  run bash "$GM" stamp --wave W5 C10; [ "$status" -eq 1 ]
  run bash "$GM" stamp --wave W5 C9;  [ "$status" -eq 1 ]
}

# ── current — the active-manifest view ─────────────────────────────────────────
@test "current prints the active (newest non-expired) manifest" {
  sign_ok W5 "C1,C3,C7"
  run bash "$GM" current
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "W5"
  echo "$output" | grep -qE "C1"
}

@test "current with only an EXPIRED manifest → exit 1 (nothing active)" {
  bash "$GM" sign --wave W3 --classes "C1" --expiry "2026-07-19T11:00:00Z"
  run bash "$GM" current
  [ "$status" -eq 1 ]
}

# ── audit trail — sign/check/stamp append to the IDL ───────────────────────────
@test "sign, check and stamp each log a line to CC_IDL" {
  sign_ok W5 "C1"
  bash "$GM" check --wave W5 C1 || true
  bash "$GM" stamp --wave W5 C1 || true
  [ -f "$CC_IDL" ]
  grep -q '"tool":"gate-manifest"' "$CC_IDL"
  grep -q '"verb":"sign"'  "$CC_IDL"
  grep -q '"verb":"check"' "$CC_IDL"
  grep -q '"verb":"stamp"' "$CC_IDL"
}

# ── P6 backstop — surfaces auto-stamped ratifications in a range, never blocks ──
@test "backstop surfaces a commit carrying a stamped 'pre-signed class' trailer" {
  repo="$BATS_TEST_TMPDIR/repo"; mkdir -p "$repo"; cd "$repo"
  git init -q; git config user.email t@t; git config user.name t
  git commit -q --allow-empty -m "base"
  base="$(git rev-parse HEAD)"
  # a real auto-stamp trailer, produced by the tool itself, on a committed ruling
  sign_ok WB "C1" >/dev/null
  trailer="$(bash "$GM" stamp --wave WB C1)"
  git commit -q --allow-empty -m "feat: an in-class change" --trailer "$trailer"
  run bash "$GM" backstop "$base..HEAD"
  [ "$status" -eq 0 ]                                  # NON-BLOCKING — always exit 0
  echo "$output" | grep -qi "backstop"
  echo "$output" | grep -qi "EARLY-VETO"
  echo "$output" | grep -qF "an in-class change"
}

@test "backstop is silent (but still exit 0) when the range has no stamped rulings" {
  repo="$BATS_TEST_TMPDIR/repo2"; mkdir -p "$repo"; cd "$repo"
  git init -q; git config user.email t@t; git config user.name t
  git commit -q --allow-empty -m "base"
  base="$(git rev-parse HEAD)"
  git commit -q --allow-empty -m "chore: nothing ratified here"
  run bash "$GM" backstop "$base..HEAD"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "backstop"
}

@test "backstop outside a git repo is a quiet no-op (exit 0)" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$GM" backstop "HEAD~1..HEAD"
  [ "$status" -eq 0 ]
}

@test "backstop ignores a PROSE mention of 'pre-signed class' with no class digit (trailer-precise)" {
  repo="$BATS_TEST_TMPDIR/repo3"; mkdir -p "$repo"; cd "$repo"
  git init -q; git config user.email t@t; git config user.name t
  git commit -q --allow-empty -m "base"
  base="$(git rev-parse HEAD)"
  # a commit that MENTIONS the phrase in prose (no 'C<n>' trailer) must NOT be surfaced as a ratification
  git commit -q --allow-empty -m "docs: explain the pre-signed class mechanism in the readme"
  run bash "$GM" backstop "$base..HEAD"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi "backstop"
}

# ── selftest + usage ───────────────────────────────────────────────────────────
@test "selftest proves RED-on-out-of-class + GREEN-on-in-class with no side effects" {
  before="$(ls -1 "$CC_GATE_MANIFEST_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  run bash "$GM" selftest
  [ "$status" -eq 0 ]
  after="$(ls -1 "$CC_GATE_MANIFEST_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$before" = "$after" ]   # no manifests written into the real dir
}

@test "usage: -h exits 0; a bogus verb exits 2" {
  run bash "$GM" -h;        [ "$status" -eq 0 ]
  run bash "$GM" frobnicate; [ "$status" -eq 2 ]
}
