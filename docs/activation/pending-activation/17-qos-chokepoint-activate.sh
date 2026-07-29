#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 17-qos-chokepoint  —  install the `bats` QoS shim so EVERY gate run lands in the BACKGROUND band
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: one idempotent symlink — ~/.claude/bin/bats → <checkout>/bin/cc-bats.
#   ~/.claude/bin is ALREADY position 1 on PATH (verified 2026-07-29; /opt/homebrew/bin is 16), and
#   per-file symlinks into the checkout are already this repo's live-layer convention, so NO .zshrc
#   edit is required — which matters, because editing the shell rc is a classifier-blocked C10 step.
#
# WHY: Darwin's BACKGROUND band was the repo's chosen answer to gate-vs-interactive contention, but
#   it was applied inside ONE CALLER (scripts/postland-verify.sh). Census of the live box:
#
#       72 of 103 live bats procs at pri=31 (full interactive priority)
#       coverage: 30% of procs, 0% of CPU
#
#   The bypassing invocation is the ORDINARY one — a session typing
#   `timeout 5400 bats tests/postland-verify.bats`, exactly as CLAUDE.md instructs before a commit.
#   With ~30 concurrent sessions, a 2403-test corpus at full priority is what turns the box laggy.
#   The shim moves the policy from the caller (which is measured to forget 70% of the time) to the
#   tool (which cannot).
#
# WHY C10 (agent stages; operator fires): this shadows `bats` for EVERY session on the machine. It is
#   reversible with a single `rm`, but it changes behaviour for ~30 live sessions, so the operator
#   owns the moment it goes live. Nothing here loads a launchd job or touches settings.json.
#
# NOT admission control. The shim never waits, sleeps, or polls load (R1: a shedder that WAITS
#   amplifies — gate_admit cost ~2h sleeping/run and 5 concurrent gates self-starved). Demotion only.
#
# AFTER LOAD — kill switches (no revert needed):
#   CC_BATS_QOS=off <cmd>     per-invocation bypass
#   rm ~/.claude/bin/bats     full uninstall, instantly
# Mark done:  touch <this file>.done
# Verify:     <checkout>/scripts/qos-census.sh          (needs >=2 concurrent gate runs to judge;
#                                                        reports NO-BURST rc 3 on a quiet box)
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/bin/cc-bats"
DEST="$HOME/.claude/bin/bats"
CENSUS="$REPO/scripts/qos-census.sh"

echo "== 17-qos-chokepoint =="
[ -f "$SRC" ] || { echo "✗ missing in checkout: $SRC (is the checkout on a trunk with this commit?)" >&2; exit 1; }
[ -x "$SRC" ] || { echo "✗ not executable: $SRC" >&2; exit 1; }

echo "Will do: [0] selftest — prove the shim resolves the REAL bats through a 'bats'-named symlink"
echo "             (self-shadowing is the whole design; a naive resolver fork-bombs here)"
echo "         [1] ln -sfn $SRC → $DEST"
echo "         [2] re-verify: 'bats --version' works, and a probe run lands at pri<=10"
echo
echo "  PATH position check:"
_pos=$(printf '%s' "$PATH" | tr ':' '\n' | grep -n "^$HOME/.claude/bin$" | head -1 | cut -d: -f1)
_hb=$(printf '%s' "$PATH" | tr ':' '\n' | grep -n "^/opt/homebrew/bin$" | head -1 | cut -d: -f1)
echo "    ~/.claude/bin at position ${_pos:-ABSENT} · /opt/homebrew/bin at ${_hb:-ABSENT}"
if [ -z "$_pos" ]; then
  echo "    ✗ ~/.claude/bin is NOT on this shell's PATH — the shim would never be reached." >&2
  echo "      Run this from an interactive login shell (it is added by ~/.zshrc:267)." >&2
  exit 1
fi
if [ -n "$_hb" ] && [ "$_pos" -gt "$_hb" ]; then
  echo "    ✗ ~/.claude/bin comes AFTER /opt/homebrew/bin — the real bats would win. Not activating." >&2
  exit 1
fi
echo "    ✓ shim dir precedes Homebrew"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  # PROPAGATE CC_REPO into the printed command. Without this the hint drops the very override that
  # made the dry run succeed, so an operator who copy-pastes it gets the fail-loud "missing in
  # checkout" path instead — handing back a command that does NOT work (memory
  # feedback-silver-platter-exact-commands). Only emitted when CC_REPO was actually set, so the
  # common case stays a clean one-liner.
  _pfx=""
  [ -n "${CC_REPO+set}" ] && _pfx="CC_REPO=$REPO "
  echo "    CONFIRM=1 ${_pfx}bash $HOME/.claude/autonomy/pending-activation/17-qos-chokepoint-activate.sh"
  exit 0
fi

# ── [0] selftest: resolution through a 'bats'-named symlink, WITHOUT installing ────────────────
echo "[0] selftest"
_tmp=$(mktemp -d) || { echo "✗ mktemp failed" >&2; exit 1; }
trap 'rm -rf "$_tmp"' EXIT
ln -sfn "$SRC" "$_tmp/bats"
_out=$(PATH="$_tmp:$PATH" timeout 20 "$_tmp/bats" --version 2>&1) || {
  echo "  ✗ selftest FAILED — shim could not resolve the real bats: $_out" >&2; exit 1; }
printf '%s' "$_out" | grep -qi '^Bats ' || {
  echo "  ✗ selftest FAILED — unexpected --version output: $_out" >&2; exit 1; }
echo "  ✓ resolves the real bats through a self-named symlink ($_out)"

# ── [1] install ───────────────────────────────────────────────────────────────────────────────
echo "[1] live symlink"
mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
  echo "  = $DEST (already linked)"
elif [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  echo "  ✗ $DEST exists and is NOT a symlink — refusing to clobber a real file." >&2; exit 1
elif ln -sfn "$SRC" "$DEST"; then
  echo "  → $DEST"
else
  echo "  ✗ failed: $DEST" >&2; exit 1
fi

# ── [2] re-verify the LIVE install (effect, not intent) ────────────────────────────────────────
echo "[2] verify live"
_v=$(timeout 20 bats --version 2>&1) || { echo "  ✗ 'bats --version' broke after install: $_v" >&2; exit 1; }
printf '%s' "$_v" | grep -qi '^Bats ' || { echo "  ✗ unexpected: $_v" >&2; exit 1; }
echo "  ✓ bats --version → $_v"

cat > "$_tmp/probe.bats" <<'EOF'
@test "activation probe" { /bin/sleep 5; }
EOF
bats "$_tmp/probe.bats" >/dev/null 2>&1 &
_bp=$!
sleep 2
_bad=0; _seen=0
for _pid in $(pgrep -P "$_bp" 2>/dev/null) "$_bp"; do
  _pri=$(ps -p "$_pid" -o pri= 2>/dev/null | tr -d ' ')
  [ -n "$_pri" ] || continue
  _seen=$((_seen + 1))
  [ "$_pri" -gt 10 ] 2>/dev/null && _bad=$((_bad + 1))
done
kill "$_bp" 2>/dev/null || true
wait "$_bp" 2>/dev/null || true
if [ "$_seen" -eq 0 ]; then
  echo "  ⚠ could not observe the probe's processes — install is in place but UNPROVEN. Re-run the census during a real gate burst." >&2
elif [ "$_bad" -gt 0 ]; then
  echo "  ✗ probe ran but $_bad/$_seen procs were NOT demoted (pri>10). Investigate before trusting this." >&2
  exit 1
else
  echo "  ✓ probe run fully demoted ($_seen/$_seen procs at pri<=10)"
fi

echo
echo "✓ 17-qos-chokepoint ACTIVE."
echo "  Uninstall:  rm $DEST"
echo "  Bypass one run:  CC_BATS_QOS=off bats <args>"
echo "  Coverage (needs >=2 concurrent gate runs; NO-BURST rc 3 on a quiet box):"
echo "      $CENSUS"
echo
echo "  Mark done:  touch $HOME/.claude/autonomy/pending-activation/17-qos-chokepoint-activate.sh.done"
