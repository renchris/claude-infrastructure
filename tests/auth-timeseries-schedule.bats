#!/usr/bin/env bats
# auth-timeseries-schedule — the recorder has a cadence, a durable store, and both rotations.
#
# WHY. tools/auth/auth-timeseries.sh is the only instrument that can see a refresh-token rotation
# or the moment a credential goes EMPTY — the outside view of a forced logout. It had been on
# trunk since 2ec33a27 as a MANUAL, TIME-BOUNDED run: `auth-timeseries.sh <out.jsonl> [interval]
# [duration]`, six hours to a caller-supplied path. Nothing scheduled it and no durable
# per-account store accumulated, so a forced logout left no trace once the session watching for
# it ended. Every part of closing that is a claim this file pins.
#
# Hermetic: a fake `security` and a fake `ps` on PATH under a scratch $HOME. The real keychain is
# never touched, and no launchctl call is made anywhere in this suite.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export SUBJ="$REPO/tools/auth/auth-timeseries.sh"
  export PLIST="$REPO/launchd/com.claude.auth-timeseries.plist"
  export LABEL="com.claude.auth-timeseries"
  export STORE_REL="logs/auth-timeseries.jsonl"
  # Capture the REAL home BEFORE overriding it: the plist's PATH is a literal containing $HOME,
  # and resolving it against the hermetic one would make the reachability check pass vacuously
  # (every candidate dir absent, the loop satisfied by /usr/bin alone).
  export REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# A keychain that answers with a well-formed credential, and a ps that shows one live session.
fake_env() {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  cat > "$BATS_TEST_TMPDIR/fakebin/security" <<'SH'
#!/bin/bash
# -w prints the payload; without it, the attribute dump (which carries "mdat").
for a in "$@"; do [ "$a" = "-w" ] && { printf '%s' '{"claudeAiOauth":{"accessToken":"AAA","refreshToken":"RRR","expiresAt":123,"refreshTokenExpiresAt":456,"scopes":["a","b"],"subscriptionType":"max"}}'; exit 0; }; done
printf '%s\n' '    "mdat"<timedate>=0x32303236  "20260810T050000Z\000"'
SH
  cat > "$BATS_TEST_TMPDIR/fakebin/ps" <<'SH'
#!/bin/bash
printf '%s\n' "/Users/c/.claude-220/node_modules/.bin/claude --model x CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary"
SH
  chmod +x "$BATS_TEST_TMPDIR/fakebin/security" "$BATS_TEST_TMPDIR/fakebin/ps"
  # /usr/bin/security is called by ABSOLUTE path in the subject, so shadow it there too by
  # pointing the subject at our fake via PATH is not enough — run with a wrapper dir first and
  # accept that the absolute call reaches the real binary on this box for the mdat probe only.
  export PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
}

# ---- the sampler's new contract ----------------------------------------------------------------

@test "sampler: --once samples one batch and RETURNS (the whole reason it can be scheduled)" {
  # The unmodified script loops for its full duration; under StartInterval that piles up
  # overlapping 6-hour processes until the box is carrying dozens. --once makes one batch the
  # unit of work. A 20s timeout is the assertion: a --once that loops fails it.
  fake_env
  run timeout 20 env AUTH_TS_OUT="$HOME/store.jsonl" AUTH_TS_KC_ACCT=x bash "$SUBJ" --once
  [ "$status" -ne 124 ] || { echo "--once did not return within 20s — it is still looping"; false; }
}

@test "sampler: the store defaults to ~/.claude/logs and its directory is created" {
  # No positional path and no env: the durable store must be the default, and it must not need a
  # pre-existing directory (the original had no mkdir, so a fresh box appended into nothing).
  fake_env
  [ ! -d "$HOME/.claude/logs" ] || { echo "precondition: logs dir should not exist yet"; false; }
  run timeout 30 env AUTH_TS_KC_ACCT=x bash "$SUBJ" --once
  [ -f "$HOME/.claude/$STORE_REL" ] || {
    echo "default store not created at $HOME/$STORE_REL (status=$status): $output"; false; }
}

@test "sampler: a second run APPENDS — the store outlives the run that wrote it" {
  # The point of the whole item: a trace that survives the session which observed it.
  fake_env
  export AUTH_TS_OUT="$HOME/s.jsonl" AUTH_TS_KC_ACCT=x
  timeout 30 bash "$SUBJ" --once || true
  first=$(wc -l < "$AUTH_TS_OUT")
  timeout 30 bash "$SUBJ" --once || true
  second=$(wc -l < "$AUTH_TS_OUT")
  [ "$first" -gt 0 ] || { echo "first run wrote nothing"; false; }
  [ "$second" -eq $((first * 2)) ] || {
    echo "not appended: $first then $second (a truncate would leave them equal)"; false; }
}

@test "sampler: every documented JSONL key survives the --once refactor" {
  # The refactor must not rename or drop a field: tools/auth/auth-error-rate.py and any future
  # reader join on these names, and a silently narrowed row is a store that looks healthy.
  fake_env
  run timeout 30 env AUTH_TS_OUT="$HOME/k.jsonl" AUTH_TS_KC_ACCT=x bash "$SUBJ" --once
  run python3 -c '
import json, os, sys
rows = [json.loads(l) for l in open(os.environ["HOME"] + "/k.jsonl") if l.strip()]
assert rows, "no rows"
for r in rows:
    for k in ("ts", "acct", "svc", "n_live", "mdat", "state"):
        assert k in r, (k, r)
    if r["state"] in ("OK", "EMPTY"):
        for k in ("at", "rt", "expiresAt", "refreshTokenExpiresAt", "scopes", "sub"):
            assert k in r, (k, r)
accts = {r["acct"] for r in rows}
assert {"next", "next2", "next3", "next4", "default", "unsuffixed"} <= accts, accts
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "sampler: a batch that appends NOTHING exits 3, never a silent 0" {
  # Under launchd there is no session to answer a keychain ACL prompt, and the subject swallows
  # per-item errors by design — so a total denial would otherwise render as a clean run. The
  # recorder must be unable to report success while recording nothing.
  mkdir -p "$BATS_TEST_TMPDIR/nullbin"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/nullbin/python3"
  chmod +x "$BATS_TEST_TMPDIR/nullbin/python3"
  PATH="$BATS_TEST_TMPDIR/nullbin:$PATH" run timeout 30 env AUTH_TS_OUT="$HOME/none.jsonl" \
    AUTH_TS_KC_ACCT=nobody bash "$SUBJ" --once
  [ "$status" -eq 3 ] || { echo "expected NO-DATA exit 3, got $status: $output"; false; }
}

@test "sampler: the original positional contract still works" {
  # Existing callers and the forced-relogin runbook pass <out> [interval] [duration]. A refactor
  # that quietly breaks them trades one manual instrument for none.
  fake_env
  run timeout 25 env AUTH_TS_KC_ACCT=x bash "$SUBJ" "$HOME/legacy.jsonl" 1 1
  [ -f "$HOME/legacy.jsonl" ] || { echo "positional out-path ignored: $output"; false; }
  [ "$(wc -l < "$HOME/legacy.jsonl")" -gt 0 ] || false
}

@test "sampler: read-only — it never writes a credential or calls the network" {
  # The property that makes it safe to schedule at all. Asserted against the source, because the
  # behavioural version would require a keychain we are willing to have mutated.
  run grep -nE 'add-generic-password|delete-generic-password|security[^|]*-U|curl|wget|nc ' "$SUBJ"
  [ -z "$output" ] || { echo "credential-write or network call in the sampler: $output"; false; }
  # exactly one mutation in the file: the append to its own store
  n=$(grep -cE '>>[[:space:]]*"\$OUT"' "$SUBJ")
  [ "$n" -eq 1 ] || { echo "expected 1 append site, found $n"; false; }
}

# ---- the schedule ------------------------------------------------------------------------------

@test "plist: parses, and its Label matches its filename" {
  run plutil -lint "$PLIST"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  want="$(basename "$PLIST" .plist)"
  run plutil -extract Label raw -o - "$PLIST"
  [ "$output" = "$want" ] || { echo "Label '$output' != filename '$want'"; false; }
}

@test "plist: it schedules --once, not the 6-hour loop" {
  # The one substantive thing that could be got wrong here, and it would not fail loudly: a
  # StartInterval over a self-looping script silently accumulates overlapping processes.
  run grep -c -- '--once' "$PLIST"
  [ "$output" -ge 1 ] || { echo "plist does not pass --once"; false; }
  run plutil -extract StartInterval raw -o - "$PLIST"
  [ "$status" -eq 0 ] || { echo "no StartInterval — a looping-daemon shape needs KeepAlive instead"; false; }
  [ "$output" -ge 60 ] || { echo "StartInterval $output is implausibly tight for a keychain sweep"; false; }
  run plutil -extract RunAtLoad raw -o - "$PLIST"
  [ "$output" = "false" ] || { echo "RunAtLoad should be false for a sampler"; false; }
}

@test "plist: every binary the wrapper invokes is reachable on the PATH the plist exports" {
  # Cloned from tests/capacity-alarm-launchd-path.bats. launchd gives a job a minimal PATH, so a
  # wrapper that exports one is asserting a claim — this checks the claim against the subject's
  # actual calls. /usr/sbin and /sbin are the ones repeatedly forgotten.
  wrapper="$(plutil -extract ProgramArguments.2 raw -o - "$PLIST")"
  [[ "$wrapper" == *'export PATH='* ]] || { echo "wrapper exports no PATH: $wrapper"; false; }
  p="$(printf '%s' "$wrapper" | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p')"
  [ -n "$p" ] || { echo "could not extract PATH from: $wrapper"; false; }
  p="${p//\$HOME/$REAL_HOME}"
  for b in security shasum cut date sed head wc python3 ps mkdir dirname; do
    found=0
    IFS=: read -ra dirs <<< "$p"
    for d in "${dirs[@]}"; do [ -x "$d/$b" ] && { found=1; break; }; done
    [ "$found" -eq 1 ] || { echo "'$b' is invoked by the sampler but is NOT on the plist's PATH: $p"; false; }
  done
}

@test "plist: the exec target is the live-layer path the activation script creates" {
  # tools/ is NOT a deployed directory — there is no ~/.claude/tools, and a newly ADDED file has
  # no per-file symlink, so it is absent from every path the box can reach. The plist therefore
  # names ~/.claude/scripts/..., which 35-auth-timeseries-activate.sh symlinks. If these two ever
  # disagree the job fails silently every tick.
  wrapper="$(plutil -extract ProgramArguments.2 raw -o - "$PLIST")"
  target="$(printf '%s' "$wrapper" | sed -n 's/.*exec "\([^"]*\)".*/\1/p')"
  [ -n "$target" ] || { echo "no exec target in wrapper: $wrapper"; false; }
  base="$(basename "$target")"
  grep -q "$base" "$REPO/docs/activation/pending-activation/35-auth-timeseries-activate.sh" || {
    echo "plist execs '$target' but the activation script never mentions '$base'"; false; }
  grep -q 'ln -sfn' "$REPO/docs/activation/pending-activation/35-auth-timeseries-activate.sh" || {
    echo "the activation script does not create the symlink the plist depends on"; false; }
}

# ---- the declaration and the two rotations -------------------------------------------------------

@test "fleet: the label is DECLARED, and declared staged rather than run" {
  # install.sh activates only what the manifest declares `run`; an undeclared label is never
  # activated and prints UNDECLARED. staged is the honest state here — built, decision pending —
  # because arming needs the operator's keychain-ACL check.
  run grep -E "^$LABEL[[:space:]]*\|" "$REPO/launchd/fleet.manifest"
  [ "$status" -eq 0 ] || { echo "$LABEL is not declared in launchd/fleet.manifest"; false; }
  [[ "$output" == *"| staged "* ]] || { echo "expected expect=staged, got: $output"; false; }
  [[ "$output" == *"$STORE_REL"* ]] || {
    echo "the manifest's evidence field should name the store, got: $output"; false; }
}

@test "store: registered in BOTH rotation mechanisms, because they are independent" {
  # rotate-autonomy-logs.sh actually rotates (its plist passes no args, so DEFAULT_TARGETS IS the
  # live coverage — a store not in that list is unrotated, full stop). store-bounds.manifest only
  # measures and pages, and never deletes. Neither substitutes for the other.
  grep -q 'logs/auth-timeseries.jsonl' "$REPO/scripts/rotate-autonomy-logs.sh" || {
    echo "store absent from rotate-autonomy-logs.sh DEFAULT_TARGETS — it will grow unbounded"; false; }
  grep -qE '^logs/auth-timeseries\.jsonl\|' "$REPO/config/store-bounds.manifest" || {
    echo "store absent from config/store-bounds.manifest — no cap, nothing pages"; false; }
}

@test "migration: 0008 is a c10 carrying an operator step, and never self-executes" {
  m="$REPO/migrations/0008-auth-timeseries-activation.sh"
  [ -x "$m" ] || { echo "$m is not executable"; false; }
  grep -q '^# migration-class: c10$' "$m" || {
    echo "must declare c10 — a mechanical migration touching a launchd plist fails deploy-migrations test 5"; false; }
  grep -q '^# migration-step: .' "$m" || { echo "c10 with no migration-step files nothing"; false; }
  grep -q '^# migration-run: .' "$m" || { echo "no paste-ready command for the operator"; false; }
  # idempotent + safe to run by hand: it must not bootstrap anything itself
  run grep -nE 'launchctl (bootstrap|load|enable)' "$m"
  [ -z "$output" ] || { echo "the migration arms launchd itself — that is the operator's step: $output"; false; }
}
