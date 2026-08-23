#!/usr/bin/env bats
# ── LANDED IS NOT LIVE: the hook is invoked through a SYMLINK, and its lib may not be ────────────
# Claude Code invokes ~/.claude/hooks/operator-readout.sh, which is a symlink into this repo. The
# hook sources hooks/lib/placeholder.sh to know the ✎ shape. ~/.claude/hooks/lib is a real
# directory of PER-FILE symlinks, so a brand-new lib has no entry there until install.sh runs —
# measured during the change that added it: absent at 21:30, present at 21:34.
#
# In that window the hook resolved the lib to a missing path and took its degrade branch, which
# answers `ph_hit: false` for every row. The ✎ state was INERT on the only path that matters, while
# every in-repo suite stayed green, because those run the repo file whose sibling lib/ is right
# there. The degrade is the RIGHT behaviour (an empty shape makes jq's `test("")` true and turns
# the whole board into ✎) — and that is exactly why its silence needs its own test: a correct
# fallback and a working feature are indistinguishable from in-repo.
#
# So this suite fixtures a $HOME where the hook IS symlinked and the lib symlink is DELIBERATELY
# ABSENT, and proves the fallback chain still finds the lib. Hermetic — it never reads the
# operator's live ~/ — and a stronger test than one against the live install, which would only
# prove that one machine happens to be wired correctly today.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/hooks/lib"
  # The hook: a symlink, as the installer makes it.
  ln -s "$REPO/hooks/operator-readout.sh" "$HOME/.claude/hooks/operator-readout.sh"
  # The lib: NOT symlinked. This is the window under test.
  HOOK="$HOME/.claude/hooks/operator-readout.sh"

  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-cache"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  : > "$CC_BACKLOG_FILE"
}

stub() {  # $1 = the `run` value the store would hold
  local s="$BATS_TEST_TMPDIR/stub"
  cat > "$s" <<EOS
#!/bin/bash
printf '[{"id":"live00000001","title":"Subscribe to the alert topic","needs":"the email address alarms should go to","run":"$1","status":"blocked"}]\n'
EOS
  chmod +x "$s"; printf '%s' "$s"
}

@test "PRECONDITION: the lib symlink really is absent (else the rest proves nothing)" {
  [ ! -e "$HOME/.claude/hooks/lib/placeholder.sh" ] || false
  [ -L "$HOOK" ] || false
}

@test "SYMLINK PATH, lib NOT installed: ✎ still fires — the fallback chain finds it" {
  s="$(stub 'aws sns subscribe --notification-endpoint <your-address>')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '✎' || { echo "NO ✎ — the hook degraded silently. Output: $output"; false; }
  ! echo "$output" | grep -q '▶ aws sns' || false
}

@test "SYMLINK PATH CONTROL: a complete command still renders ▶" {
  s="$(stub 'aws sns subscribe --notification-endpoint ren.chris@outlook.com')"
  CC_BACKLOG_BIN="$s" run "$HOOK" --render --cwd "$BATS_TEST_TMPDIR"
  echo "$output" | grep -q '▶ aws sns' || false
  ! echo "$output" | grep -q '✎' || false
}
