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
  export CC_ACCOUNTS_CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/lock-"
  export HANDOFF_ACCOUNT_SWEEP_THROTTLE_S=0     # no throttle unless a test opts in
  echo '{}' > "$CC_ACCOUNTS_CACHE"
}

rows() { printf '%s' "$1" > "$BATS_TEST_TMPDIR/rows.json"; export CC_STUB_ROWS_JSON="$BATS_TEST_TMPDIR/rows.json"; }
info() { printf '%s' "$2" > "$CC_STUB_INFO_DIR/$1.json"; }

@test "all accounts healthy → no bridge, exit 0, stderr reports healthy" {
  rows '{"rows":[{"acct":"next","auth":"ok","k":0},{"acct":"next2","auth":"healed","k":1},{"acct":"next3","auth":"stale","k":2},{"acct":"next4","auth":"ok","k":0}]}'
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE"       # no bridge = all routable
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
  ! echo "$output" | grep -q "## ACCOUNT STATE"       # healed → nothing stranded to embed
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
  ! echo "$output" | grep -q "FAILED"                 # relogin was NOT attempted
  echo "$output" | grep -q "stranded=1"
}

@test "another heal/login in flight (lock held) → relogin DEFERRED, not counted stranded" {
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  # hold the EXACT lock claude-accounts heal() would take (interlock proof)
  /usr/bin/python3 -c "import fcntl,time; f=open('${CC_HEAL_LOCK_PREFIX}next2.lock','w'); fcntl.flock(f,fcntl.LOCK_EX); time.sleep(3)" &
  local holder=$!
  sleep 0.5
  run bash "$HF" account-sweep
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "## ACCOUNT STATE"       # deferred ≠ stranded → no bridge
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
  ! echo "$output" | grep -q "POISON"                 # proves no re-poll
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
  ! echo "$output" | grep -q "## ACCOUNT STATE"
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

@test "last-known quota is sourced from the cache .prev snapshot" {
  rows '{"rows":[{"acct":"next3","auth":"logged-out","k":0}]}'
  info next3 '{"config_dir":"/x","keychain_service":"svc","keychain_state":"no-keychain-item","claude_bin":"/x/claude","oauth_scopes":"a b","has_refresh_token":false}'
  echo '{"prev":{"rows":{"next3":{"weekly_pct":31}}}}' > "$CC_ACCOUNTS_CACHE"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "weekly ~31%"
}

@test "dry-run fire advertises the pre-fire sweep in its readout" {
  local pf="$BATS_TEST_TMPDIR/brief.txt"; echo "resume the desk" > "$pf"
  run bash "$HF" --dry-run --prompt-file "$pf" --session-id "fake:UUID" --account next
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sweep:"
  echo "$output" | grep -qi "claude-accounts --fresh"
}

@test "dry-run fire shows the sweep OFF when disabled" {
  local pf="$BATS_TEST_TMPDIR/brief.txt"; echo "resume the desk" > "$pf"
  HANDOFF_ACCOUNT_SWEEP=off run bash "$HF" --dry-run --prompt-file "$pf" --session-id "fake:UUID" --account next
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "account sweep OFF"
}
