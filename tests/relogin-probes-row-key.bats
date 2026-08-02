#!/usr/bin/env bats
# E1/E3 probe row lookup — the field the probes key their live-state reads on.
#
# THE DEFECT THIS PINS (observed live 2026-08-02): `row()` in e1 and e3 selected the account row
# with `x.get("name") == acct`, but `claude-accounts --json` has never emitted a `name` key — the
# row's account field is `acct`. A lookup keyed on a field that does not exist can only MISS, and
# the miss returned "" for EVERY field:
#   * the `[[ "$K" == "0" ]]` precondition refused with a blank count (`k= live sessions`), so E1
#     — the ★ highest-value probe, and the one verdict the whole relogin rollout waits on — could
#     never run at all; and
#   * both verdict reads (after_auth_no_heal / after_auth_healed) would have recorded an empty
#     string as an OBSERVATION, i.e. a fictional verdict transcribed as fact.
# So the fix is two-part and both parts are pinned below: key on `acct`, AND make a missing row
# FATAL rather than "" — an absent row must never be readable as an empty observation.
#
# Hermetic: every case runs the probe's own extracted `row()` against a FIXTURE json on stdin.
# Nothing here sweeps an endpoint, reads a keychain, or signs anything in.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # HERMETIC $HOME. The subjects this suite executes — e1-concurrent-logins.sh and
  # e3-warm-profile-authorize.sh — default to `$HOME/.claude/accounts.json` and
  # `$HOME/.claude/auth-profiles` (e1:24, e3:28,32). Today the leak is LATENT: the tests only
  # awk the `row()` function out and run it against $FIX, so nothing reads those paths. That is
  # precisely why it must be pinned now rather than later — the suite is one edit away from
  # executing a probe for real, and at that moment it would read the operator's live account
  # config instead of a fixture, silently. No seeding is needed because nothing under $HOME is
  # read on the current paths; if a future test does execute a probe, seed it here.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  E1="$REPO/scripts/relogin-probes/e1-concurrent-logins.sh"
  E3="$REPO/scripts/relogin-probes/e3-warm-profile-authorize.sh"
  # A fixture shaped like the real --json: rows keyed on `acct`, NO `name` key anywhere.
  FIX='{"rows":[{"acct":"next3","k":0,"auth":"ok"},{"acct":"next","k":4,"auth":"ok"}]}'
}

# Run the probe's real row() by sourcing only its definition — no eval, and the probe body
# never executes (we stop at the closing brace of the function).
run_row() { # <script> <acct> <field> <json>
  local src acct field json fn
  src="$1"; acct="$2"; field="$3"; json="$4"
  fn="$BATS_TEST_TMPDIR/row.sh"
  awk '/^row\(\)/{p=1} p{print} p&&/^ *printf .%s. "\$_v"; \}$/{exit}' "$src" > "$fn"
  # The extraction must have TERMINATED on the function's closing line. Without this the awk
  # runs to EOF on any shape it does not recognise, `$fn` becomes the whole file tail, and
  # sourcing it fails — which a "must be non-zero" assertion would score as a PASS. That is a
  # harness failure wearing the result's clothes, so it is checked separately and loudly.
  [ -s "$fn" ] || { echo "HARNESS: extracted no row() from $src" >&2; return 99; }
  tail -n1 "$fn" | grep -q 'printf .%s. "\$_v"; }$' \
    || { echo "HARNESS: row() extraction from $src did not terminate at the function's closing line — refusing to score this as a result" >&2; return 99; }
  ACCT="$acct" bash -c '
    die() { echo "e: $*" >&2; exit 1; }
    . "$1"
    row "$2" "$3"' _ "$fn" "$field" "$json"
}

@test "e1 row() resolves a real account by its acct key" {
  run run_row "$E1" next3 k "$FIX"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "e1 row() reads a non-numeric field correctly" {
  run run_row "$E1" next k "$FIX"
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

# THE CONTROL — the pre-fix code returned "" here with status 0, which is exactly how a blank
# `k=` reached the refusal message and how an empty verdict would have been recorded. If this
# ever passes with status 0 again, the fix has been reverted.
@test "e1 row() DIES on a missing row — never returns an empty observation" {
  run run_row "$E1" nosuchacct k "$FIX"
  [ "$status" -ne 0 ]
  [ "$status" -ne 99 ]   # 99 = harness could not extract row(); that is not a result
  [ "$output" != "" ]
}

@test "e3 row() resolves a real account by its acct key" {
  run run_row "$E3" next3 auth "$FIX"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "e3 row() DIES on a missing row — never returns an empty observation" {
  run run_row "$E3" nosuchacct auth "$FIX"
  [ "$status" -ne 0 ]
  [ "$status" -ne 99 ]   # 99 = harness could not extract row(); that is not a result
}

# The durable form: the next probe to grow a live-state read must not re-introduce the class.
@test "no relogin probe keys an account lookup on a name field" {
  run grep -rn 'get("name")' "$REPO/scripts/relogin-probes/"
  [ "$status" -ne 0 ]
}

# Guards the fixture itself against the real contract drifting back: if claude-accounts ever
# emits `name` again, this suite's premise needs re-deriving rather than silently passing.
@test "claude-accounts --json documents acct as the row account key" {
  run grep -c '"acct"' "$REPO/bin/claude-accounts"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}
