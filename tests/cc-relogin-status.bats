#!/usr/bin/env bats
# Relogin observability (RELOGIN_BUILD_CONTRACT §6) — the three read-only surfaces:
#   1. claude-accounts --relogin-status  the per-account renewal board (+ --json)
#   2. cc-blockers                       the class-C relogin-blocked row, additive to safeguard-blocked
#   3. rotate-autonomy-logs.sh           bounds the cc-relogin*.log family
#
# Hermetic by construction: a scratch SSOT + a PRE-SEEDED shared cache (so the board never sweeps
# an endpoint, never reads a real keychain and never heals), a temp IDL board via CC_REAPER_IDL,
# a temp poller log via CC_RELOGIN_POLL_LOG, and a temp $HOME for rotation. Nothing here signs in.
#
# The load-bearing case is §2 version tolerance: the login_expires_* fields are NOT on every build,
# and a board that cannot see them must say UNKNOWN — a confident wrong "OK" is worse than useless.

# NEGATIVE ASSERTIONS GO THROUGH THESE — never a bare `!`. A bare `! cmd` is a SILENT NO-OP
# unless it is the final line of a @test: POSIX exempts `!`-inverted pipelines from errexit, so
# bats' set -e never trips and the assertion is dead (shellcheck SC2314). Probed on this box:
# `@test { ! true; [ 1 -eq 1 ]; }` PASSES. These helpers are plain simple commands, so a
# non-zero return aborts the test from ANY position, and they do NOT call `run` — a helper that
# did would clobber $output/$status for every assertion after it.
refute_grep() { # <extended-regex> <text> — the pattern must NOT appear
  if grep -qE -- "$1" <<<"$2"; then
    echo "refute_grep: pattern '$1' unexpectedly PRESENT in: $2" >&2
    return 1
  fi
  return 0
}
refute_glob() { # <glob...> — no matching path may exist (unmatched glob arrives literal ⇒ pass)
  local g
  for g in "$@"; do
    [ -e "$g" ] && { echo "refute_glob: '$g' unexpectedly exists" >&2; return 1; }
  done
  return 0
}

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite):
  # the subject resolves its own state under ~, so unfixtured this suite reads/writes the
  # operator's LIVE layer. Everything this suite asserts is already redirected elsewhere.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  C="$REPO/bin/cc-blockers"
  ROT="$REPO/scripts/rotate-autonomy-logs.sh"
  export D="$BATS_TEST_TMPDIR"    # exported: one test splits streams via a `bash -c` subshell
  export CA_CFG="$D/accounts.json"
  export CACHE="$D/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$D/lastgood.json"
  export CC_RELOGIN_POLL_LOG="$D/cc-relogin-poll.log"
  export CC_REAPER_IDL="$D/idl.jsonl"
  # ── the two cc-blockers seams a hermetic $HOME does NOT cover ─────────────────────────────────
  # Every other sensor in bin/cc-blockers keys off $HOME (beacon hook, reap alarm, team roots,
  # watchdog, land log, postland, DEPLOY_REPO→cc-fleet) or off $CC_REAPER_IDL (dispatch-inert has
  # no premise without a `cc-dispatch` actor row), so the two exports above already silence them.
  # These two do NOT resolve through $HOME, which is exactly why they were missed:
  #
  #   CC_PERMPEND_DIR    defaults to the ABSOLUTE /tmp/cc-permission-pending — the operator's live
  #                      beacon dir. Every pending approval on this machine became an extra
  #                      `permission-pending` row in the SAME --json array these tests count, so
  #                      `jq 'length' = 2` read 2 + (however many sessions happen to be waiting)
  #                      and the all-clear message never rendered (a board with rows has no
  #                      all-clear path). That is the whole of the 4-test failure: three --json
  #                      length assertions and the empty-board message.
  #   CC_BLOCKERS_ACCOUNTS_BIN  defaults to bare `claude-accounts`, resolved on PATH. Every test
  #                      here seeds a relogin-blocked row, which is precisely the condition
  #                      drop_stale_relogin asks about — so unfixtured this suite EXECUTES the
  #                      operator's deployed claude-accounts once per test and lets their live
  #                      login state decide which rows survive. Latent today only because the
  #                      fixtures carry `login_expires_at` while the gate reads `.deadline`, so it
  #                      fails open; a fixture that ever gains a deadline field would flip the
  #                      verdict by machine (memory unfixtured-sensor-executes-the-deployed-subject).
  #
  # Both point at paths that do NOT exist: the alarm and the drop gate each fail open on an absent
  # input, which is the deterministically-silent baseline the sibling tests/cc-blockers.bats also
  # chooses. This suite fixtures $HOME and STILL was not hermetic — scripts/test-hermeticity-lint.sh
  # RULE 1 only asks whether $HOME is fixtured, so it is blind to an absolute or PATH-resolved seam
  # by construction and reported this file clean throughout.
  export CC_PERMPEND_DIR="$D/permpend"
  export CC_BLOCKERS_ACCOUNTS_BIN="$D/absent-claude-accounts"
  # scratch SSOT — dead endpoints + a config_dir with no keychain item, so a sweep (if one ever
  # happened) would be offline and deterministic. Three accounts so state precedence is testable.
  python3 - "$CA_CFG" "$CACHE" <<'PY'
import json, sys
cfg_path, cache = sys.argv[1], sys.argv[2]
acct = lambda n: {"name": n, "config_dir": "/tmp/ca-relogin-nonexistent-" + n,
                  "launcher": "claude" + n[4:],   # next->claude, next2->claude2 (launcher consolidation)
                  "email": n + "@example.com", "mailbox": n + "@example.com", "dia_profile": n.upper()}
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache, "cache_ttl_s": 900,
  "frontier": {"scoped_display_name": "Fable", "coupling": 0.5, "deadline_margin_h": 2.0,
               "end_date_inclusive": True, "credits_authorized": False},
  "router": {"S_CUT": 0.85, "S_SOFT": 0.5, "SF_FLOOR": 0.05, "KMAX": 8, "KFLOOR": 0.1,
             "MARGIN_H": 0.5, "EPS_H": 0.25, "WEEKLY_FLOOR": 0.005, "FABLE_FLOOR": 0.02,
             "JB_BONUS": 1.25},
  "accounts": [acct("next"), acct("next2"), acct("next3")],
}, open(cfg_path, "w"))
PY
}

# seed the SHARED CACHE with exactly these rows — the board then reads them like any other mode,
# with zero network, zero keychain and zero heal. <rows-json>
# RELATIVE EXPIRIES, NOT ABSOLUTE DATES. `login_expires_at` may be written as `+<N>h` / `-<N>h`
# and is resolved to now±N hours at seed time.
#
# WHY (trunk went red 2026-07-27T01:00Z, blocking every FULL-selection land): these fixtures used
# to pin absolute instants — `2026-07-29T00:00:00Z` annotated "100h", `2026-07-26T00:00:00Z`
# annotated "12h". claude-accounts RE-DERIVES login_expires_h from login_expires_at on every read
# (see the note above the JSON test), so the annotation is decorative and WALL-CLOCK decides the
# assertion. The suite therefore passed only while real time sat in the intended band: 2026-07-29
# drifted to T-47h, crossed RELOGIN_ESCALATE_H=48, and the "DUE" cases began reporting ESCALATE —
# permanently, since the date only gets closer. A test whose verdict depends on the day it is run
# is not a test; anchoring to now makes the band the fixture claims the band it actually gets.
seed() {
  python3 - "$CA_BIN" "$CACHE" "$1" <<'PY'
import importlib.machinery, importlib.util, json, re, sys, time
from datetime import datetime, timedelta, timezone
bin_, cache, rows_json = sys.argv[1], sys.argv[2], sys.argv[3]
loader = importlib.machinery.SourceFileLoader("ca", bin_)
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
cfg = ca.load_cfg()
rows = json.loads(rows_json)
now = datetime.now(timezone.utc)
for r in rows:
    m = re.fullmatch(r"([+-]\d+(?:\.\d+)?)h", str(r.get("login_expires_at", "")))
    if m:
        hours = float(m.group(1))
        r["login_expires_at"] = (now + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
        r["login_expires_h"] = hours
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": True,
           "rows": rows, "prev": None,
           "window": {"active": False, "end": None, "permanent": False, "deadline": None}},
          open(cache, "w"))
PY
}

rl() { # append a relogin-blocked class-C row: <ts> <acct> <state> <when> <recover_cmd>
  jq -nc --arg ts "$1" --arg a "$2" --arg s "$3" --arg w "$4" --arg cmd "$5" \
    '{ts:$ts,actor:"cc-relogin-poll",kind:"relogin-blocked",acct:$a,state:$s,
      login_expires_at:$w,recover_cmd:$cmd}' >> "$CC_REAPER_IDL"; }

sg() { # append a safeguard-blocked row (the pre-existing kind): <ts> <pane> <name> <cmd>
  jq -nc --arg ts "$1" --arg p "$2" --arg n "$3" --arg cmd "$4" \
    '{ts:$ts,actor:"cc-reaper",kind:"safeguard-blocked",pane:$p,name:$n,account:"claude-quaternary",
      blocked_model:"Fable 5",refusal:"safeguards flagged this message",recover_cmd:$cmd}' \
    >> "$CC_REAPER_IDL"; }

# ── 1. claude-accounts --relogin-status ────────────────────────────────────────────────────────

@test "OK: every account outside the attempt window → exit 0, no next action" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+400h"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'next .*OK'
  # The contract is "the board SURFACES the expiry instant", not which instant — the fixture is
  # now relative, so assert the shape (ISO-8601 Z) rather than a literal that would re-pin the
  # suite to a wall-clock date.
  echo "$output" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
}

@test "DUE: inside the 7d attempt window → exit 1 + the exact cc-relogin command" {
  seed '[{"acct":"next2","auth":"ok","login_expires_at":"+100h"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 1 ]                       # 100h < 168h trigger, > 48h escalate
  echo "$output" | grep -q 'DUE'
  echo "$output" | grep -q 'cc-relogin next2'
}

@test "ESCALATED: inside the 48h escalation window → exit 2" {
  seed '[{"acct":"next3","auth":"ok","login_expires_at":"+12h"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ESCALATED'
  echo "$output" | grep -q 'cc-relogin next3'
}

@test "ESCALATED: an already-expired login window (login_expired) → exit 2" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"-5h","login_expired":true}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'ESCALATED'
}

@test "ESCALATED: a logged-out account is never UNKNOWN, even with no login_* fields" {
  seed '[{"acct":"next","auth":"logged-out","error":"logged-out"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]                       # auth exists on EVERY build — past the cliff already
  echo "$output" | grep -q 'ESCALATED'
}

# ── the §2 case: the detection surface is absent on this build ─────────────────────────────────

@test "UNKNOWN: login_* fields absent → NOT a confident OK, exit 3, loud named surface" {
  seed '[{"acct":"next","auth":"ok"},{"acct":"next2","auth":"healed"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -ne 0 ]                       # the load-bearing assertion: never 0-with-a-wrong-OK
  [ "$status" -eq 3 ]                       # DETECTION-UNAVAILABLE
  echo "$output" | grep -q 'UNKNOWN'
  # Assert the STATE COLUMN, not the blob: the §2 warning itself ends "Reporting UNKNOWN, NOT
  # OK", so a blob-wide `no OK anywhere` check is simply wrong. (It was also DEAD as a bare
  # non-final `!` — it passed for both reasons at once, which is the whole hazard.)
  refute_grep '^[a-z0-9]+ +OK ' "$output"   # no account row may render state OK
  echo "$output" | grep -qE '^next +UNKNOWN '
  echo "$output" | grep -qE '^next2 +UNKNOWN '
  echo "$output" | grep -q 'DETECTION-UNAVAILABLE'
  echo "$output" | grep -q 'login_expires_h' # names the missing surface (§2)
  # The warning must name a RECOVERY THAT EXISTS. It used to say the fields were absent because
  # this build lacked them ("branch feat/accounts-login-cliff") — true when written, false since
  # that branch landed, and a landed branch is not something the operator can go land. R-4.
  echo "$output" | grep -q -- '--fresh'
  [[ "$output" != *"feat/accounts-login-cliff"* ]]
}

@test "UNKNOWN: the machine surface agrees — zero OK rows, every row UNKNOWN" {
  # The positive form of the assertion above, on the surface a consumer actually parses.
  seed '[{"acct":"next","auth":"ok"},{"acct":"next2","auth":"healed"}]'
  run bash -c '"$CA_BIN" --relogin-status --json 2>/dev/null'
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq '[.rows[] | select(.state=="OK")] | length')" = "0" ]
  [ "$(echo "$output" | jq '[.rows[] | select(.state=="UNKNOWN")] | length')" = "2" ]
  [ "$(echo "$output" | jq -r '.state')" = "UNKNOWN" ]
}

@test "UNKNOWN outranks OK: a partially-blind board never reports all-clear" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+400h"},
         {"acct":"next2","auth":"ok"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 3 ]                       # one blind account is enough to withhold "all clear"
}

@test "act-now outranks cannot-see: DUE + UNKNOWN → exit 1" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+100h"},
         {"acct":"next2","auth":"ok"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 1 ]
}

# An UNAGEABLE stamp, not merely a missing _h. refresh_login_countdown() (landed on trunk in
# e4ed592) now re-derives login_expires_h from login_expires_at after EVERY get_data(), because a
# served countdown decays from the instant it is cached. So "at present, h absent" is no longer a
# state the classifier can observe for a PARSEABLE stamp — it self-heals. The branch under test is
# still live, and still matters: hrs_until() returns None on an unparseable stamp, so an `at` we
# cannot age must read UNKNOWN rather than silently OK. That is the invariant this test always
# meant; only the seed needed to move to the case that still reaches it.
@test "an UNAGEABLE login_expires_at → UNKNOWN (cannot age it), not OK" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"not-a-timestamp"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'UNKNOWN'
}

# ── last attempt, read from the poller's log ───────────────────────────────────────────────────

@test "last attempt: JSONL poller row (ts + result), latest wins" {
  printf '%s\n' '{"ts":"2026-07-24T10:00:00Z","acct":"next","result":"FALLBACK-REQUIRED"}' \
                '{"ts":"2026-07-25T11:00:00Z","acct":"next","result":"PROVEN"}' \
                '{"ts":"2026-07-25T11:30:00Z","acct":"next2","result":"ERROR"}' > "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+100h"}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_result')" = "PROVEN" ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_ts')" = "2026-07-25T11:00:00Z" ]
}

@test "last attempt: a missing poller log is UNKNOWN ('never'), never an error" {
  rm -f "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+400h"}]'
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]                       # absent log does not change the renewal state
  echo "$output" | grep -q 'never'
}

@test "last attempt: a plain-text (non-JSON) poller line is still read" {
  printf '%s\n' 'THIS IS NOT JSON' '2026-07-25T12:00:00Z next3 attempt failed: BROWSER-FAILED' \
    > "$CC_RELOGIN_POLL_LOG"
  seed '[{"acct":"next3","auth":"ok","login_expires_at":"+12h"}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 2 ]
  [ "$(echo "$output" | jq -r '.rows[0].last_attempt_ts')" = "2026-07-25T12:00:00Z" ]
  echo "$output" | jq -r '.rows[0].last_attempt_result' | grep -q 'BROWSER-FAILED'
}

# ── --json shape + read-only posture ───────────────────────────────────────────────────────────

@test "--json: documented shape (exit, state, detection, per-account rows)" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+100h"},
         {"acct":"next2","auth":"ok","login_expires_at":"+400h"}]'
  run "$CA_BIN" --relogin-status --json
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.exit')" = "1" ]            # the exit code is DATA too
  [ "$(echo "$output" | jq -r '.state')" = "DUE" ]
  [ "$(echo "$output" | jq -r '.detection')" = "available" ]
  [ "$(echo "$output" | jq '.rows | length')" = "2" ]
  [ "$(echo "$output" | jq -r '.rows[0].acct')" = "next" ]
  [ "$(echo "$output" | jq -r '.rows[0].state')" = "DUE" ]
  [ "$(echo "$output" | jq -r '.rows[0].next_action')" = "cc-relogin next" ]
  [ "$(echo "$output" | jq -r '.rows[1].state')" = "OK" ]
  # login_expires_h is DERIVED from login_expires_at on every read (refresh_login_countdown,
  # e4ed592), so the seeded 100 is deliberately overwritten and asserting that literal would be
  # asserting the seed rather than the behaviour. Assert the contract that survives: the field is
  # present and numeric. Its VALUE is a function of now(), so pinning a number here would also be
  # a clock-dependent flake. The semantic claim this row makes is `.state == "DUE"`, asserted above.
  echo "$output" | jq -e '.rows[0].login_expires_h | numbers' >/dev/null
  echo "$output" | jq -e '.rows[0] | has("last_attempt_ts") and has("reason")' >/dev/null
}

@test "--json: detection=unavailable, and the loud line goes to stderr — stdout stays parseable" {
  seed '[{"acct":"next","auth":"ok"}]'
  # Split the streams: a machine consumer pipes stdout to jq, so the §2 warning must NOT land
  # there and corrupt it — but it must still be emitted, unmissably, on stderr.
  run bash -c '"$CA_BIN" --relogin-status --json 2>"$D/err.txt"'
  [ "$status" -eq 3 ]
  [ "$(echo "$output" | jq -r '.detection')" = "unavailable" ]
  [ "$(echo "$output" | jq -r '.rows[0].state')" = "UNKNOWN" ]
  [ "$(echo "$output" | jq -r '.rows[0].login_expires_at')" = "null" ]
  grep -q 'DETECTION-UNAVAILABLE' "$D/err.txt"
  refute_grep 'DETECTION-UNAVAILABLE' "$output"
}

@test "read-only: a cache hit is served as-is — no re-sweep, no cache rewrite" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+400h"}]'
  before="$(cat "$CACHE")"
  run "$CA_BIN" --relogin-status
  [ "$status" -eq 0 ]
  [ "$(cat "$CACHE")" = "$before" ]         # byte-identical ⇒ collect() never ran
}

@test "read-only: --relogin-status NEVER reaches heal() — a status read must not authenticate" {
  # Behavioural, not grep-based. heal() shells out to `claude auth login` — a real credential
  # write — and takes the per-account heal lock, so a status surface that reaches it would
  # authenticate as a side effect of being LOOKED AT (§0: nothing in this build may
  # authenticate, refresh, revoke or write a credential). Stub read_creds to return the exact
  # precondition probe_account heals on (a stale token) and spy on heal().
  # SELF-VALIDATING: the same stubs under plain --json MUST call heal — otherwise the spy is
  # wired wrong and a green result would prove nothing at all.
  rm -f "$CACHE"                      # force a real collect(); a cache hit never probes
  run python3 - "$CA_BIN" "$CACHE" <<'PY'
import importlib.machinery, importlib.util, os, sys
bin_, cache = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("ca", bin_)
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)

calls = []
ca.heal = lambda *a, **k: (calls.append(a), (False, "stubbed — never actually run"))[1]
ca.read_creds = lambda cd, kc: ({"accessToken": "t", "refreshToken": "r",
                                 "expiresAt": 0}, "present")   # expiresAt 0 ⇒ stale ⇒ heal branch live
ca.fetch_usage = lambda cfg, tok: (None, None)

def drive(argv):
    calls.clear()
    try:
        os.remove(cache)
    except OSError:
        pass
    sys.argv = ["claude-accounts"] + argv
    try:
        ca.main()
    except SystemExit:
        pass
    return len(calls)

status_heals = drive(["--relogin-status"])
json_heals = drive(["--json"])
sys.stderr.write("status_heals=%d json_heals=%d\n" % (status_heals, json_heals))
assert status_heals == 0, "--relogin-status invoked heal() — a status read authenticated"
assert json_heals > 0, "spy never fired even where heal IS reachable — this test proves nothing"
PY
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'status_heals=0'          # the guarantee
  refute_grep 'json_heals=0' "$output"               # …and the spy demonstrably fires
}

@test "plain output always: no ANSI escapes on a machine surface" {
  seed '[{"acct":"next","auth":"ok","login_expires_at":"+12h"}]'
  FORCE_COLOR=1 run "$CA_BIN" --relogin-status
  [ "$status" -eq 2 ]
  refute_grep $'\033' "$output"
  echo "$output" | grep -q 'ESCALATED'      # positive control: the row really did render
}

# ── 2. cc-blockers — the class-C relogin row (additive) ────────────────────────────────────────

@test "cc-blockers renders a relogin-blocked row with its EXACT recover command" {
  rl "2026-07-25T09:00:00Z" "next3" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next3 --debug"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -q 'next3'
  echo "$output" | grep -q 'ESCALATED'
  echo "$output" | grep -q '2026-07-27T00:00:00Z'
  echo "$output" | grep -qF 'cc-relogin next3 --debug'   # verbatim, never paraphrased
}

@test "cc-blockers: safeguard-blocked still renders unchanged alongside relogin (regression)" {
  sg "2026-07-25T09:05:00Z" "725A269A" "wt-pool-2-725A269A" "cc-recover-safeguard 725A269A"
  rl "2026-07-25T09:10:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'SAFEGUARD-BLOCKED'
  echo "$output" | grep -q 'wt-pool-2-725A269A'
  echo "$output" | grep -q 'Fable 5'
  echo "$output" | grep -q 'safeguards flagged this message'
  echo "$output" | grep -qF 'cc-recover-safeguard 725A269A'
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -qF 'cc-relogin next'
}

@test "cc-blockers: a REQUIRED escalation with NO deadline SURVIVES the stale-drop (backlog 8e394583d5d4)" {
  # WHY THIS IS A cc-blockers TEST OF A cc-relogin-poll FIX. drop_stale_relogin retracts a relogin
  # row once the account's live login_expires_at is LATER than the row's deadline. That rule is
  # right for a MEASURED deadline and nonsense for a fabricated one: the pre-fix poller wrote
  # `deadline = NOW` for a REQUIRED row whose deadline the producer deliberately did not publish,
  # and NOW is earlier than any future cliff — so the loudest surface the poller has discarded the
  # row by construction. Measured on next2's real 2026-08-03 shape (grant rejected, cliff 674h out):
  # 1 row raised, 0 rendered. The poller now publishes NO deadline, which lands in this file's own
  # documented fail-open ("$d == null … keep") on the polarity its author chose — "a stale row is
  # noise, a dropped live one is silence".
  #
  # The gate must be ARMED for this to mean anything: setup() points CC_BLOCKERS_ACCOUNTS_BIN at a
  # deliberately ABSENT binary, under which every row is kept vacuously and both arms below would
  # pass without the subject running at all (memory control-must-replay-the-real-artifact).
  local far; far="$(date -u -r "$(( $(date +%s) + 674*3600 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                    || date -u -d "@$(( $(date +%s) + 674*3600 ))" +%Y-%m-%dT%H:%M:%SZ)"
  printf '#!/bin/sh\nprintf %%s %s\n' \
    "'{\"rows\":[{\"acct\":\"next2\",\"login_expires_at\":\"$far\"}]}'" > "$D/ca-far"
  chmod +x "$D/ca-far"; export CC_BLOCKERS_ACCOUNTS_BIN="$D/ca-far"

  # POST-FIX shape: no deadline claimed, so the clock cannot adjudicate and the row is KEPT.
  jq -nc --arg f "$far" '{ts:"2026-08-03T14:34:26Z",actor:"cc-relogin-poll",kind:"relogin-blocked",
    acct:"next2",account:"next2",deadline:"",deadline_known:false,deadline_src:"required",
    state:"REQUIRED",cause:"token-invalid",recover_cmd:"cc-relogin next2"}' > "$CC_REAPER_IDL"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 1 ]
  run "$C"
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -q 'REQUIRED'                    # the STATE column, not 12 chars of prose
  echo "$output" | grep -qF 'cc-relogin next2'

  # MUTATION CONTROL — the PRE-FIX row, byte-for-byte the shape the poller used to write, is
  # dropped by the same run. Without this the assertions above could not tell a working gate from
  # an absent one.
  jq -nc '{ts:"2026-08-03T14:34:26Z",actor:"cc-relogin-poll",kind:"relogin-blocked",
    acct:"next2",account:"next2",deadline:"2026-08-03T14:34:18Z",
    reason:"T-0h to the login deadline (2026-08-03T14:34:18Z)",recover_cmd:"cc-relogin next2"}' \
    > "$CC_REAPER_IDL"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 0 ]
}

@test "cc-blockers --json: one array carrying both kinds, newest first" {
  sg "2026-07-25T09:05:00Z" "PANE-A" "peer-a" "cc-recover-safeguard PANE-A"
  rl "2026-07-25T09:20:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "relogin-blocked" ]   # newest first
  [ "$(echo "$output" | jq -r '.[1].kind')" = "safeguard-blocked" ]
}

@test "cc-blockers dedup: latest relogin row per acct, both accounts kept" {
  rl "2026-07-25T09:00:00Z" "next" "DUE" "2026-07-27T00:00:00Z" "cc-relogin next"
  rl "2026-07-25T10:00:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next --debug"
  rl "2026-07-25T10:30:00Z" "next2" "ESCALATED" "2026-07-28T00:00:00Z" "cc-relogin next2"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.acct=="next")][0].state')" = "ESCALATED" ]
  [ "$(echo "$output" | jq -r '[.[] | select(.acct=="next")][0].recover_cmd')" = "cc-relogin next --debug" ]
}

@test "cc-blockers: a malformed board line never hides the good rows" {
  printf '%s\n' 'THIS IS NOT JSON at all' >> "$CC_REAPER_IDL"
  printf '%s\n' '"a bare string"' >> "$CC_REAPER_IDL"
  rl "2026-07-25T09:00:00Z" "next" "ESCALATED" "2026-07-27T00:00:00Z" "cc-relogin next"
  sg "2026-07-25T09:01:00Z" "PANE-Z" "peer-z" "cc-recover-safeguard PANE-Z"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'cc-relogin next'
}

@test "cc-blockers: an EMPTY middle field never shifts recover_cmd out of its column" {
  # Tab is IFS-*whitespace*, so `IFS=$'\t' read` collapses a run of tabs: any empty field
  # slides every later field LEFT. Verified raw: 'slug\tacct\tmodel\t\tCMD' parses as
  # refusal=[CMD] cmd=[] — the operator's board dropping the exact command it exists to hand
  # over. Both kinds are padded to non-empty cells, so both must survive an empty field.
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","kind":"safeguard-blocked","pane":"P1","name":"peer-1","account":"","blocked_model":"","refusal":"","recover_cmd":"cc-recover-safeguard P1"}' \
    >> "$CC_REAPER_IDL"
  printf '%s\n' '{"ts":"2026-07-25T09:10:00Z","kind":"relogin-blocked","acct":"next3","state":"","login_expires_at":"","recover_cmd":"cc-relogin next3 --debug"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  # Each command must arrive WHOLE and in the RECOVER column — i.e. at end of its line.
  echo "$output" | grep -qE 'cc-recover-safeguard P1$'
  echo "$output" | grep -qE 'cc-relogin next3 --debug$'
  refute_grep 'cc-recover-safeguard P1 ' "$output"   # not padded mid-row ⇒ not in REFUSAL
}

@test "cc-blockers: a field containing a tab/newline cannot break the row either" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","kind":"safeguard-blocked","pane":"P2","name":"peer-2","account":"acct","blocked_model":"Fable 5","refusal":"line one\ttabbed\nline two","recover_cmd":"cc-recover-safeguard P2"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'cc-recover-safeguard P2$'
  [ "$(echo "$output" | grep -c 'peer-2')" -eq 1 ]   # one row, not split across lines
}

@test "cc-blockers: a relogin row missing optional fields still shows acct + command" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","kind":"relogin-blocked","acct":"next4","recover_cmd":"cc-relogin next4"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'next4'
  echo "$output" | grep -qF 'cc-relogin next4'
}

@test "cc-blockers: relogin rows do not disturb the empty-board message" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","actor":"cc-reaper","kind":"surface-page","pane":"P0"}' \
    >> "$CC_REAPER_IDL"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked sessions surfaced'
}

# ── 3. log rotation covers the cc-relogin*.log family ──────────────────────────────────────────

@test "rotation: cc-relogin-poll.log + cc-relogin.log are rotated by default" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  for f in cc-relogin-poll.log cc-relogin.log; do
    head -c 200 < /dev/zero | tr '\0' 'a' > "$H/.claude/logs/$f"
  done
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  for f in cc-relogin-poll.log cc-relogin.log; do
    [ -f "$H/.claude/logs/$f" ]                                    # recreated in place
    [ "$(wc -c < "$H/.claude/logs/$f" | tr -d ' ')" -eq 0 ]        # emptied
    ls "$H/.claude/logs/$f".* >/dev/null                           # a rotation exists
  done
  grep -q '"file":"cc-relogin-poll.log"' "$D/rot-idl.jsonl"
  grep -q '"file":"cc-relogin.log"' "$D/rot-idl.jsonl"
}

@test "rotation: a cc-relogin log under threshold is left untouched" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  head -c 50 < /dev/zero | tr '\0' 'a' > "$H/.claude/logs/cc-relogin-poll.log"
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$H/.claude/logs/cc-relogin-poll.log" | tr -d ' ')" -eq 50 ]
  refute_glob "$H/.claude/logs/cc-relogin-poll.log".*
}

@test "rotation: absent cc-relogin logs are a no-op, never a literal unmatched-glob target" {
  H="$D/home"; mkdir -p "$H/.claude/logs" "$H/.claude/autonomy"
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  refute_glob "$H/.claude/logs/cc-relogin"*   # no file named after the literal glob was created

  # The invariant: an ABSENT cc-relogin log contributes ZERO targets (the glob must not survive
  # as a literal unmatched path). Prove it DIFFERENTIALLY rather than against a hardcoded count.
  # The literal-default list belongs to other work, so any absolute number here turns a sibling
  # adding a default into a spurious red in THIS file — which is exactly what happened: a 6th
  # default landed mid-rebase and reddened the composed tree while both branches were green alone.
  # A differential cannot rot: it only asserts the delta this file is actually responsible for.
  base="$(echo "$output" | sed -n 's/.*skipped=\([0-9]*\).*/\1/p')"
  [ -n "$base" ]                              # guard: the readout shape must still be parseable

  : > "$H/.claude/logs/cc-relogin-poll.log"   # now ONE cc-relogin log exists
  CC_IDL="$D/rot-idl.jsonl" ROTATE_MAX_BYTES=100 HOME="$H" run bash "$ROT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "skipped=$((base + 1))"   # glob adds exactly one, only when present
}
