#!/usr/bin/env bats
# THE SELF-CLOSE WATCHER'S RETYPE, PINNED (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/
# REPORT.md Wave A: "Self-close watcher … Pin it with a test only"). z-critic G1.6 and d-adversarial
# asked whether __selfclose's sc_exit_unblock has the recycle watcher's pre-commit race. Its
# empty-composer retype is already what Wave A makes the recycle watcher's: never before 40 s, once,
# and through hf_exit_readback (the undo and the receipt). This pins that, so a later edit cannot
# regress it into the recycle's old arm; the order of its foreground's own gates is not under test.
#
# A PIN, NOT A FIX: every case passes on origin/main (2a636f1b8) by design. Mutants, each red: drop
# the `-lt 40` floor (1) · drop the `_retyped` latch (2) · retype with a raw send instead of
# hf_exit_readback (3, no read-back CR gate).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs"; export HOME
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    for f in hf_bounded hf_bounded_s composer_content recycle_nudge_decision hf_exit_readback \
             composer_residue_dir composer_residue_record; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
    sed -n '/^  sc_exit_unblock() {/,/^  }/p' "$HF"
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  grep -q 'sc_exit_unblock() {' "$FUNCS" || { echo "sc_exit_unblock not extracted" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
  export ST="$BATS_TEST_TMPDIR/state"; mkdir -p "$ST"; : > "$ST/composer"; : > "$ST/sends"
  # it2: the composer is a file; a typed line lands in it, a CR submits it. Every send is recorded.
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session read") printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$(cat "$ST/composer")" ;;
  "session send")
    p="${!#}"; printf 'send %q\n' "$p" >> "$ST/sends"
    case "$p" in $'\r') : > "$ST/composer" ;; *) printf '%s' "$(cat "$ST/composer")$p" > "$ST/composer" ;; esac ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BATS_TEST_TMPDIR/sleep"; chmod +x "$BATS_TEST_TMPDIR/sleep"
  # shellcheck disable=SC2034  # read by the extracted functions
  export HF_SLEEP="$BATS_TEST_TMPDIR/sleep" HF_TIMEOUT_S="" HF_TIMEOUT_BIN="" SID=SC-PANE
  # shellcheck disable=SC2034  # the self-close loop's own state
  _retyped=0
}

@test "1 an empty composer before 40 s: no key at all (the calling turn may still hold the queued /exit)" {
  # shellcheck disable=SC2034
  waited=35
  sc_exit_unblock
  [ "$SC_XU" = hold:composer-empty ] || { echo "SC_XU=$SC_XU"; false; }
  [ ! -s "$ST/sends" ] || { cat "$ST/sends"; false; }
}

@test "2 from 40 s: ONE retype through hf_exit_readback (type, read back, CR), then never again" {
  # shellcheck disable=SC2034
  waited=45
  sc_exit_unblock
  [ "$SC_XU" = retype:composer-empty ] || { echo "SC_XU=$SC_XU"; cat "$ST/sends"; false; }
  [ "$(cat "$ST/sends")" = "$(printf 'send /exit\nsend %s' "\$'\\r'")" ] || { cat "$ST/sends"; false; }
  # shellcheck disable=SC2034
  waited=60
  sc_exit_unblock
  [ "$SC_XU" = hold:composer-empty ] || { echo "SC_XU=$SC_XU"; false; }
  [ "$(grep -c . "$ST/sends")" = 2 ] || { cat "$ST/sends"; false; }
}

@test "3 a retype that does not read back is held: no CR, and the box is not touched further" {
  # A draft lands in the box between our type and the read-back: the read ends `/exitab`.
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session read") printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$(cat "$ST/composer")" ;;
  "session send") p="${!#}"; printf 'send %q\n' "$p" >> "$ST/sends"; printf '%s' "$(cat "$ST/composer")${p}ab" > "$ST/composer" ;;
esac
exit 0
SH
  # shellcheck disable=SC2034
  waited=45
  sc_exit_unblock
  [ "$SC_XU" = "hold:retype-read-back=/exitab" ] || { echo "SC_XU=$SC_XU"; cat "$ST/sends"; false; }
  ! grep -qxF "send \$'\\r'" "$ST/sends" || { cat "$ST/sends"; false; }
}

@test "4 a composer holding exactly /exit gets the CR it is missing, at any time" {
  printf '/exit' > "$ST/composer"
  # shellcheck disable=SC2034
  waited=5
  sc_exit_unblock
  [[ "$SC_XU" == enter:composer-exit* ]] || { echo "SC_XU=$SC_XU"; false; }
  [ "$(cat "$ST/sends")" = "send \$'\\r'" ] || { cat "$ST/sends"; false; }
}
