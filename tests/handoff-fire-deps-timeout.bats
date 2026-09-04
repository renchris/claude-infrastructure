#!/usr/bin/env bats
# Regression guard: the cold-fire dep install must be TIME-BOUNDED, not merely exit-tolerant.
#
# INCIDENT (2026-09-03): a cold fire of wt-mem-drain into claude-infrastructure parked for 4m17s
# on `npm ci`. Nothing was broken — 0.83s CPU across the whole run, one ESTABLISHED socket to the
# registry, node_modules frozen at 11132 KB, while curl reached registry.npmjs.org in 0.15s from
# the same box. npm simply sat on the socket. Because the fire types `bash <deps> ; <launcher>`,
# the pane's entire visible state until the script returns is the package manager's own braille
# progress spinner, so the operator read it as a hung SESSION and opened an investigation. The
# session had not started at all.
#
# WHY THE EXISTING `;` DOES NOT COVER THIS: the `;`-not-`&&` construction (handoff-fire.sh, cold
# path) guarantees that an install which EXITS NONZERO still launches the session. It says nothing
# about one that never exits. That is the same end state as the 2026-07-29 `go`→`god` park — no
# session, no error, no timeout, a parked pane — reached through a hang instead of an exit code.
#
# THE INVARIANT: the generated deps script must return within its ceiling even when the install
# chain never terminates, and must still run the chain unbounded when no timeout binary exists
# (a missing bound may never make a fire WORSE than it is today).

setup() {
  # M11 — pin the capacity/headroom gates off; an unpinned suite goes RED on a busy box.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"
  # Fixturing $HOME does NOT redirect an absolute /tmp default, nor a bare name the subject then
  # executes off the operator's live PATH. Pin each seam handoff-fire.sh reaches for; an ABSENT
  # path is the right value here, since these sensors fail open on one.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # The real minting block, executed rather than read — a source-scan would pass on a preamble
  # that never reaches the file.
  MINT="$(sed -n '/^    WT_DEPS="\$(mktemp/,/^    chmod +x "\$WT_DEPS"/p' "$HF")"
  [ -n "$MINT" ] || { echo "could not extract the deps-file minting block — the sed drifted"; false; }
}

# A chain that never terminates on its own. This is what a wedged package manager looks like to
# the script: not an error, just absence.
HANG='sleep 300'

@test "a NON-TERMINATING install chain still returns, inside its ceiling" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 \
    || skip "no timeout binary on this host; the bound is documented as unavailable here"
  # shellcheck disable=SC2034
  local WT_INSTALL="$HANG"
  eval "$MINT"
  [ -x "$WT_DEPS" ] || { echo "minting produced no executable script"; false; }
  local start elapsed
  start=$SECONDS
  CC_DEPS_TIMEOUT=2 bash "$WT_DEPS" >/dev/null 2>&1
  elapsed=$((SECONDS - start))
  # 2s ceiling + 10s KILL grace + slack. A pre-fix tree runs the full 300s and never gets here.
  [ "$elapsed" -lt 20 ] || { echo "deps script ran ${elapsed}s against a 2s ceiling — unbounded"; false; }
}

@test "RED-PROOF: the SAME fixture with the bound removed does NOT return" {
  # Proves the guard discriminates rather than passing vacuously. Reconstruct the pre-fix shape —
  # shebang + chain, no preamble — and show the identical fixture hangs through it.
  command -v timeout >/dev/null 2>&1 || skip "needs timeout to bound the control itself"
  local prefix; prefix="$BATS_TEST_TMPDIR/prefix.sh"
  { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$HANG"; } > "$prefix"
  chmod +x "$prefix"
  run timeout 5 bash "$prefix"
  [ "$status" -eq 124 ] || { echo "the control fixture terminated on its own (status $status) — it does not model a wedged install"; false; }
}

@test "the ceiling is overridable and defaults to 180s" {
  grep -q 'CC_DEPS_TIMEOUT:-180' "$HF" || { echo "the default ceiling is not 180s"; false; }
}

@test "TERM is followed by KILL, so an install that ignores TERM cannot outlive the ceiling" {
  grep -q '"\$_to" -k 10 "\${CC_DEPS_TIMEOUT:-180}"' "$HF" \
    || { echo "the bound does not follow TERM with KILL (-k)"; false; }
}

@test "with NO timeout binary the chain still runs, unbounded — never worse than before" {
  # shellcheck disable=SC2034
  local WT_INSTALL='echo reached-the-chain'
  eval "$MINT"
  # Strip the PATH so neither timeout nor gtimeout resolves; the preamble must fall through.
  run env PATH=/usr/bin:/bin bash "$WT_DEPS"
  [ "$status" -eq 0 ] || { echo "fell over with no timeout binary (status $status): $output"; false; }
  grep -q 'reached-the-chain' <<<"$output" \
    || { echo "the install chain did not run in the no-timeout fallback: $output"; false; }
}

@test "the bound does not re-enter itself (no fork bomb via re-exec)" {
  # The re-exec re-runs the SAME file; without the CC_DEPS_BOUNDED guard that recurses forever.
  grep -q 'CC_DEPS_BOUNDED:-' "$HF" || { echo "no re-entry guard on the re-exec"; false; }
  grep -q 'CC_DEPS_BOUNDED=1' "$HF" || { echo "the re-exec does not set the guard it reads"; false; }
  # shellcheck disable=SC2034
  local WT_INSTALL='echo once'
  eval "$MINT"
  run bash "$WT_DEPS"
  [ "$status" -eq 0 ] || false
  [ "$(grep -c 'once' <<<"$output")" -eq 1 ] \
    || { echo "chain ran more than once — the re-entry guard leaks: $output"; false; }
}

@test "the typed command is unchanged — the bound lives in the FILE, not the typed line" {
  # The 2026-07-29 invariant (no correctable word in command position) must survive this change.
  local cold; cold="$(sed -n '/^    WT_INSTALL=/,/^    CMD=/p' "$HF")"
  local cmdline; cmdline="$(grep '^    CMD=' <<<"$cold" | head -1)"
  [ -n "$cmdline" ] || false
  ! grep -q 'timeout' <<<"$cmdline" \
    || { echo "the bound leaked into the TYPED command: $cmdline"; false; }
  grep -q 'bash \$(printf %q "\$WT_DEPS")' <<<"$cmdline" \
    || { echo "the typed command no longer invokes the deps file: $cmdline"; false; }
}
