#!/usr/bin/env bats
# handoff-fire.sh pre-fire account sweep (Part A2, desk-anti-hitl-2026-07-19 rec. 2).
# Before a fire, `claude-accounts --fresh` auto-heals; each still-broken account is either
# Phase-1 headless-relogin'd (token-invalid + refresh token + zero live sessions) or bridge-lined
# (logged-out / keychain-error / revoked). Everything is stubbed — no real accounts / keychain /
# iTerm / network. The `account-sweep` subcommand is the pure test surface: it prints the embeddable
# bridge section to stdout (nothing when all routable) + a summary to stderr; `run` captures both,
# so "no bridge" is asserted as the ABSENCE of the "## ACCOUNT STATE" header.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN" "$BATS_TEST_TMPDIR/info"

  # stub claude-accounts: `--relogin-info NAME` → info/NAME.json ; any --json/--fresh → the rows file.
  cat > "$BIN/claude-accounts" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
mode=""; acct=""
for a in "$@"; do
  case "$a" in
    --relogin-info) mode=relogin ;;
    --fresh|--json|--rank|--route|general|fable) : ;;
    *) [ "$mode" = relogin ] && acct="$a" ;;
  esac
done
if [ "$mode" = relogin ]; then
  f="$CC_STUB_INFO_DIR/${acct}.json"; [ -f "$f" ] && cat "$f" || echo "{}"; exit 0
fi
cat "$CC_STUB_ROWS_JSON"; exit 0
STUB
  chmod +x "$BIN/claude-accounts"

  # stub `security`: prints a keychain payload carrying a refresh token.
  printf '#!/usr/bin/env bash\necho %s\n' "'{\"claudeAiOauth\":{\"refreshToken\":\"RT-STUB\"}}'" > "$BIN/security-ok"
  # stub `claude` binary: `auth login` succeeds / fails.
  printf '#!/usr/bin/env bash\necho "Login successful."\n' > "$BIN/claude-heal-ok"
  printf '#!/usr/bin/env bash\necho "Error: invalid_grant" >&2\nexit 1\n' > "$BIN/claude-heal-fail"
  chmod +x "$BIN/security-ok" "$BIN/claude-heal-ok" "$BIN/claude-heal-fail"

  export CC_ACCOUNTS_BIN="$BIN/claude-accounts"
  export CC_STUB_INFO_DIR="$BATS_TEST_TMPDIR/info"
  export CC_SECURITY_BIN="$BIN/security-ok"
  export CC_KEYCHAIN_ACCOUNT="tester"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/lock-"
  export HANDOFF_ACCOUNT_SWEEP_THROTTLE_S=0     # no throttle unless a test opts in

  # The sweep filters on .auth_actionable — the CLI's own verdict, derived there from
  # ACTIONABLE_AUTH. Read that list OUT OF THE CLI so these fixtures cannot claim an emission
  # shape the producer does not actually have, and inject it in rows() rather than hand-writing
  # it into every literal: a hand-copied state list is the precise drift this field removed.
  #
  # importlib.util is imported EXPLICITLY below. Importing importlib.machinery binds the parent
  # package but NOT this sibling submodule, so reaching importlib.util worked only where
  # something else on the interpreter startup path had already imported it. Framework 3.11 does;
  # /usr/bin/python3 does not, and there every test in this file died in setup() with
  # "AttributeError: module importlib has no attribute util" — a suite whose green was an
  # accident of which python3 the PATH happened to resolve. Keep the heredoc body free of
  # apostrophes and backticks: it is nested inside "$( ... )", where an odd quote silently
  # breaks the enumeration of the whole file (bats then reports 1..0 rather than a failure).
  CC_ACTIONABLE_JSON="$(python3 - "$REPO/bin/claude-accounts" <<'PY'
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("ca", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(mod)
print(json.dumps(list(mod.ACTIONABLE_AUTH)))
PY
)"
  export CC_ACTIONABLE_JSON
}

rows() {
  local f="$BATS_TEST_TMPDIR/rows.json"
  printf '%s' "$1" | jq -c --argjson act "$CC_ACTIONABLE_JSON" \
    '.rows |= map(. + {auth_actionable: (.auth as $a | ($act | index($a)) != null)})' > "$f" \
    || printf '%s' "$1" > "$f"     # a deliberately malformed fixture stays verbatim
  export CC_STUB_ROWS_JSON="$f"
}
info() { printf '%s' "$2" > "$CC_STUB_INFO_DIR/$1.json"; }

@test "all accounts healthy → no bridge, exit 0, stderr reports healthy" {
  rows '{"rows":[{"acct":"next","auth":"ok","k":0},{"acct":"next2","auth":"healed","k":1},{"acct":"next3","auth":"stale","k":2},{"acct":"next4","auth":"ok","k":0}]}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE" || false # no bridge = all routable
  echo "$output" | grep -q "accounts healthy"
}

@test "logged-out (no refresh token) → bridge line, NO relogin attempt" {
  rows '{"rows":[{"acct":"next","auth":"ok","k":0},{"acct":"next3","auth":"logged-out","error":"logged-out","k":0}]}'
  info next3 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"no-keychain-item","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "## ACCOUNT STATE"
  echo "$output" | grep -q "next3 — logged-out"
  echo "$output" | grep -q "headless relogin N/A"
  echo "$output" | grep -q "account-relogin skill (Phase 2, browser)"
  echo "$output" | grep -q "stranded=1"
}

@test "token-invalid + refresh token + zero live sessions → Phase-1 headless relogin HEALS (no bridge)" {
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE" || false # healed → nothing stranded to embed
  echo "$output" | grep -q "healed via Phase-1 headless relogin"
  echo "$output" | grep -q "stranded=0"
}

@test "token-invalid, relogin FAILS (revoked) → stranded bridge names the failure + Phase 2" {
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-fail\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Phase-1 headless relogin FAILED"
  echo "$output" | grep -q "account-relogin skill (Phase 2, browser)"
  echo "$output" | grep -q "stranded=1"
}

@test "token-invalid but k>0 (live sessions) → NOT eligible, never relogins under a live CC" {
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":2}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "live session(s)"
  ! echo "$output" | grep -q "FAILED" || false        # relogin was NOT attempted
  echo "$output" | grep -q "stranded=1"
}

@test "another heal/login in flight (lock held) → relogin DEFERRED, not counted stranded" {
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  # Hold the EXACT lock claude-accounts heal() would take (interlock proof). The holder
  # announces acquisition with a marker file and we WAIT for it: a fixed `sleep 0.5` raced
  # python's startup on a loaded machine, the sweep then found the lock free, healed instead
  # of deferring, and this test failed while asserting nothing about its own precondition.
  # A concurrency test that does not confirm the contended state is testing the uncontended one.
  local marker="$BATS_TEST_TMPDIR/holder.acquired"
  /usr/bin/python3 -c "
import fcntl, time
f = open('${CC_HEAL_LOCK_PREFIX}next2.lock', 'w')
fcntl.flock(f, fcntl.LOCK_EX)
open('$marker', 'w').close()
time.sleep(10)" &
  local holder=$!
  local waited=0
  while [ ! -e "$marker" ] && [ "$waited" -lt 100 ]; do sleep 0.1; waited=$((waited+1)); done
  [ -e "$marker" ]                                    # precondition, asserted not assumed
  run bash "$HF" account-sweep
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE" || false # deferred ≠ stranded → no bridge
  echo "$output" | grep -qi "deferred"
  echo "$output" | grep -q "stranded=0"
}

@test "throttle: a second (throttled) sweep REUSES the stamp and does NOT re-poll" {
  rows '{"rows":[{"acct":"next3","auth":"logged-out","k":0}]}'
  info next3 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"no-keychain-item","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  export HANDOFF_ACCOUNT_SWEEP_THROTTLE_S=60
  bash "$HF" account-sweep >/dev/null 2>&1            # seed the stamp (force)
  # poison the accounts bin: any re-poll now exits 77 with a POISON marker
  printf '#!/usr/bin/env bash\necho POISON >&2; exit 77\n' > "$BIN/claude-accounts"
  chmod +x "$BIN/claude-accounts"
  run bash "$HF" account-sweep --throttled
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reused"
  ! echo "$output" | grep -q "POISON" || false        # proves no re-poll
  echo "$output" | grep -q "## ACCOUNT STATE"         # cached bridge still surfaced
}

@test "test isolation: under bats WITHOUT a CC_ACCOUNTS_BIN stub, the real sweep is inert" {
  # Existing non-dry fire tests must never poll the real claude-accounts (network + relogin side
  # effect). Unset the stub setup() exported → the bats-env guard must skip, touching nothing.
  rows '{"rows":[{"acct":"next3","auth":"logged-out","k":0}]}'
  run env -u CC_ACCOUNTS_BIN bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "skipped (bats env"
  ! echo "$output" | grep -q "## ACCOUNT STATE"
}

@test "HANDOFF_ACCOUNT_SWEEP=off → sweep skipped entirely" {
  rows '{"rows":[{"acct":"next3","auth":"logged-out","k":0}]}'
  HANDOFF_ACCOUNT_SWEEP=off run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE" || false
  echo "$output" | grep -q "OFF"
}

@test "keychain-error (unreadable item, no refresh token) → bridge line, no relogin" {
  rows '{"rows":[{"acct":"next4","auth":"keychain-error","error":"keychain-error","k":0}]}'
  info next4 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"keychain-error","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next4 — keychain-error"
  echo "$output" | grep -q "headless relogin N/A"
}

@test "last-known quota is sourced from the durable ledger on --fresh --json (stale_quota + @ recency stamp)" {
  # claude-accounts' inherit_lastgood stamps a broken row with stale_quota + weekly_pct + quota_as_of
  # from its TTL-free ledger; the sweep must read THAT (not the old /tmp cache .prev) and render "@ HH:MM".
  local asof; asof="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"          # captured "now" ⇒ today ⇒ HH:MM stamp
  rows "{\"rows\":[{\"acct\":\"next3\",\"auth\":\"logged-out\",\"error\":\"logged-out\",\"k\":0,\"stale_quota\":true,\"weekly_pct\":31,\"quota_as_of\":\"$asof\"}]}"
  info next3 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"no-keychain-item","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "last-known weekly ~31%"
  echo "$output" | grep -qE "weekly ~31% @ [0-9]{2}:[0-9]{2}"     # recency stamp re-derived from quota_as_of
}

@test "no ledger entry (row carries no stale_quota) → last-known weekly n/a, no /tmp .prev fallback" {
  # A broken account the ledger never recorded: the sweep must NOT fall back to the retired /tmp .prev
  # cache (none is written) — it reports "n/a" honestly.
  rows '{"rows":[{"acct":"next3","auth":"logged-out","error":"logged-out","k":0}]}'
  info next3 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"no-keychain-item","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "last-known weekly n/a"
}

# These two assert on the READOUT's content, so they must not also depend on ambient box load.
# CC_FIRE_CAPACITY_GATE=off is the gate's own documented kill switch (handoff-fire.sh:1286).
#
# Without it both went RED whenever the box was busy: the P0-17 capacity gate refuses a net-new fire
# at >2.0 load/core with exit 9, and a --dry-run is deliberately NOT exempt — it is how
# handoff-fire-capacity-gate.bats observes the gate at all, and reporting the refusal is the honest
# dry-run answer ("what WOULD happen" = refused). So exit 9 here was CORRECT behaviour meeting a test
# that assumed an idle box. These two are the reason 2 of the 15 bats failures on the 2026-07-25/26
# nightly pages survived re-triage; they failed by LOAD, not by code (measured: exit 9 at
# 2.05/core). Neutralising the gate per-test keeps them deterministic without weakening it globally —
# the gate's own suite still proves refuse/admit/fail-open.
@test "dry-run fire advertises the pre-fire sweep in its readout" {
  local pf="$BATS_TEST_TMPDIR/brief.txt"; echo "resume the desk" > "$pf"
  CC_FIRE_CAPACITY_GATE=off run bash "$HF" --dry-run --prompt-file "$pf" --session-id "fake:UUID" --account next
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sweep:"
  echo "$output" | grep -qi "claude-accounts --fresh"
}

@test "dry-run fire shows the sweep OFF when disabled" {
  local pf="$BATS_TEST_TMPDIR/brief.txt"; echo "resume the desk" > "$pf"
  HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off run bash "$HF" --dry-run --prompt-file "$pf" --session-id "fake:UUID" --account next
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "account sweep OFF"
}

@test "an EXPIRED refresh token skips Phase-1 (it cannot succeed) and goes straight to the bridge" {
  # has_refresh_token is true and every other precondition holds — but the token is past its
  # own expiry, so the grant returns invalid_grant by construction. claude-heal-ok would
  # otherwise report success here, which is exactly what makes this fixture the discriminator:
  # a pass means the gate read the expiry, not the mere presence of a token.
  rows '{"rows":[{"acct":"next2","auth":"login-required","k":0}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true,\"refresh_token_expired\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "healed via Phase-1" || false # the 90s subprocess was never spent
  echo "$output" | grep -q "## ACCOUNT STATE"
  echo "$output" | grep -q "next2 — login-required"
  echo "$output" | grep -q "stranded=1"
}

@test "login-required is gated as actionable — a state added after the old hand-copied list" {
  # The retired filter named three auth states literally, so every state introduced later
  # (no-oauth-blob, probe-error, and now login-required) silently passed the gate as healthy.
  rows '{"rows":[{"acct":"next","auth":"ok","k":0},{"acct":"next2","auth":"login-required","k":0}]}'
  info next2 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"present","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":true,"refresh_token_expired":true}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "next2 — login-required"
  ! echo "$output" | grep -q "accounts healthy"
}

@test "version skew: rows without .auth_actionable are NAMED, never read as a healthy fleet" {
  # Written past rows() on purpose — this is the shape an older claude-accounts emits. The
  # filter would match nothing, so the danger is not a crash but a confident "all healthy"
  # over a fleet that cannot authenticate. The gate must announce that it did not run.
  printf '%s' '{"rows":[{"acct":"next3","auth":"logged-out","k":0}]}' > "$BATS_TEST_TMPDIR/rows.json"
  export CC_STUB_ROWS_JSON="$BATS_TEST_TMPDIR/rows.json"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]                                  # degrade, never block a fire
  echo "$output" | grep -q "version skew"
  echo "$output" | grep -q "auth gate SKIPPED"
  ! echo "$output" | grep -q "accounts healthy"        # the claim it must NOT make
}
