#!/usr/bin/env bats
# handoff-fire.sh pre-fire account sweep (Part A2, desk-anti-hitl-2026-07-19 rec. 2).
# Before a fire, `claude-accounts --fresh` auto-heals; each still-broken account is either
# Phase-1 headless-relogin'd (token-invalid + refresh token + zero live sessions) or bridge-lined
# (logged-out / keychain-error / revoked). Everything is stubbed — no real accounts / keychain /
# iTerm / network. The `account-sweep` subcommand is the pure test surface: it prints the embeddable
# bridge section to stdout (nothing when all routable) + a summary to stderr; `run` captures both,
# so "no bridge" is asserted as the ABSENCE of the "## ACCOUNT STATE" header.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. The per-test pins
  # below predate this and are the shape the hermeticity ratchet rejects: they leave every OTHER test in
  # the file reading live machine state. handoff-fire.sh's capacity_gate reads the box's loadavg AND
  # (M10) its memory headroom — the two TERMS of one exit 9 (handoff-fire.sh:4487) — so both are pinned
  # here, for the whole file. tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh rule 1) — the SAME "pinned, not ambient" rule as
  # M11 above, applied to the other ambient input. Every ACCOUNT seam below was already
  # stubbed, which is what made this file LOOK hermetic — and is why it was grandfathered rather
  # than fixed. But the two `--dry-run` tests drive the WHOLE fire path, and that path resolves its
  # state under `~` and APPENDS a row to $HOME/.claude/logs/handoffs.jsonl (handoff-fire.sh:414,463).
  # MEASURED 2026-08-08 by running this suite under an EMPTY $HOME: `.claude/logs/handoffs.jsonl`
  # appeared in it — so unfixtured, every run of this suite had been writing into the operator's LIVE
  # handoff audit trail. Same shape as the session-continue.bats leak recorded in
  # scripts/host-suites.manifest, and found the same way: give the suite an ABSENT $HOME and read
  # what appears in it, never by inspection.
  # PHYSICAL form, as in tests/handoff-fire-launcher-map.bats: /tmp is a symlink to /private/tmp on
  # Darwin, and the fire path compares paths it has already resolved.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  HOME="$(cd "$HOME" && pwd -P)"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  # NOTE this fixture was IMPOSSIBLE until the same commit's handoff-fire.sh fix: fixturing $HOME is
  # exactly what removes the ~/.claude/bin/it2 shim, and the REAL_IT2/PYTHON_BIN resolvers then
  # aborted the whole script under `set -euo pipefail` with the evidence swallowed. The two dry-run
  # tests died there — a red indistinguishable from a real regression. That is the defect behind
  # backlog 2f71dded07f2, and it is why no it2 shim is seeded here: the fallback now works.
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

@test "token-invalid with an UNMEASURED live count (k null) → NOT eligible, and says so honestly" {
  # The producer emits `k: null` when it could not read `ps` (claude-accounts concurrency returns
  # None rather than an all-zero count). This sweep re-spells heal()'s rotation-safety gate, and
  # `(.k // 0)` used to read that null as ZERO — the one value that UNLOCKS a headless token
  # redeem. So an unread `ps` would have authorised exactly the rotation race the gate exists to
  # prevent: the loser holds a retired token, i.e. a logout manufactured by a missing measurement.
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":null}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "healed via Phase-1" || false   # the redeem was NEVER attempted
  ! echo "$output" | grep -q "FAILED" || false
  echo "$output" | grep -q "UNMEASURABLE"
  # ...and it must NOT claim a live session it never observed — unknown is its own reason.
  ! echo "$output" | grep -q "unmeasured live session" || false
  echo "$output" | grep -q "stranded=1"
}

@test "token-invalid with an INHERITED live count (k_stale) → NOT eligible; a 600s-old zero is not proof" {
  # claude-accounts inherit_k (desk-router-abstention-2026-09-01 §4) now carries the previous
  # sweep's pane count onto a row whose own `ps` census failed, marked `k_stale`. That is right for
  # ROUTING — the alternative was excluding all four accounts at once and silently concentrating
  # every launch on the pinned one — and it means `.k` is a NUMBER where this gate used to receive
  # null. So the fix re-opened the exact hole the case above closed, through a second door: `k: 0`
  # is the one value that unlocks a headless token redeem, and this row now carries it.
  #
  # This gate is the opposite kind of consumer from the router. It redeems a refresh token,
  # irreversibly, on the claim that NOBODY holds it — and a zero measured up to 600s ago is not
  # that claim, because a session can start in a second. The loser of that race holds a retired
  # token: a logout manufactured by a measurement nobody re-took. So the gate keys on the MARKER,
  # not on the type, and an inherited count refuses exactly as a null one does.
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0,"k_stale":true}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  # `grep P >/dev/null`, not `grep -q P`: the pipefail-SIGPIPE ratchet holds this file at its
  # grandfathered count, and that list may only SHRINK. The drained form is what it asks for.
  ! echo "$output" | grep "healed via Phase-1" >/dev/null || false  # the redeem was NEVER attempted
  ! echo "$output" | grep "FAILED" >/dev/null || false
  echo "$output" | grep "UNMEASURABLE" >/dev/null
  echo "$output" | grep "stranded=1" >/dev/null
}

@test "the SAME row with a live k:0 still heals — the refusal keys on staleness, not on caution" {
  # The control for the case above, and the reason it is not merely "refuse whenever k is 0". A
  # gate that refused every zero would strand every genuinely idle account behind a browser
  # relogin forever, which is the failure mode the Phase-1 path exists to remove. One field
  # separates the two fixtures.
  rows '{"rows":[{"acct":"next2","auth":"token-invalid","k":0,"k_stale":false}]}'
  info next2 "{\"config_dir\":\"/x\",\"keychain_service\":\"svc\",\"keychain_state\":\"present\",\"claude_bin\":\"$BIN/claude-heal-ok\",\"oauth_scopes\":\"a b\",\"has_refresh_token\":true}"
  run bash "$HF" account-sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep "healed via Phase-1 headless relogin" >/dev/null
  echo "$output" | grep "stranded=0" >/dev/null
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
