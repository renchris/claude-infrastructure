#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# cc-upgrade-gate.sh <binary-path> <model> [accounts…]
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# The CC-upgrade REGRESSION GATE. Validates every "way we work" against a candidate (binary version +
# model) as headless, self-evidencing probes → per-check PASS/FAIL/SKIP + an overall GREEN/RED verdict.
# Machine-readable JSON on stdout; a human summary on stderr; exit 0 (GREEN) / 1 (RED). FAIL-CLOSED.
#
# WHY: operator mandate — "we ALWAYS upgrade immediately to a new model IF all our ways of working
# continue to work." This replaces hand-waved soak + presumption with evidence. The opus-5 episode
# (a PRESUMED demotion that was actually fine) is the exact failure mode this eliminates: every check
# verifies the ARTIFACT (modelUsage / argv / exit), never a claim.
#
# The 14 checks live one-per-file in lib/cc-upgrade-gate/check*.sh and are AUTO-DISCOVERED (each defines
# a `check_NN` function). Adding a probe is a new FILE, never an edit here — that is what makes the
# multi-teammate build collision-free.
#
# Usage:
#   scripts/cc-upgrade-gate.sh ~/.claude-219/node_modules/.bin/claude claude-opus-5 next
#   scripts/cc-upgrade-gate.sh <bin> <model> next next2 next3 next4      # full multi-account sweep
# Env:
#   GATE_RETRIES=<n>   bounded retry for flaky probes (default 3)
#   GATE_SPAWN=0       SKIP the expensive spawn probes (#7/#8/#9) for fast iteration (default 1 = live)
#   NO_COLOR=1         plain reporters
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
LIB="$REPO/lib/cc-upgrade-gate"
# common.sh always loads from the real LIB; the CHECK-discovery dir is overridable so hermetic tests
# can point at a temp dir of stub probes without globbing the real (or half-written) sibling checks.
CHECKS_DIR="${CC_UPGRADE_GATE_CHECKS:-$LIB}"

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

[ $# -ge 2 ] || { echo "✗ need <binary-path> <model> [accounts…]" >&2; usage; }

export GATE_BIN="$1"; shift
export GATE_MODEL="$1"; shift
export GATE_ACCOUNTS="${*:-next}"
export GATE_RETRIES="${GATE_RETRIES:-3}"
export GATE_SPAWN="${GATE_SPAWN:-1}"

# ---- preflight: the gate's own dependencies (fail-closed) -------------------------------------------
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 required" >&2; exit 2; }
[ -f "$LIB/common.sh" ] || { echo "✗ missing $LIB/common.sh" >&2; exit 2; }
if [ ! -x "$GATE_BIN" ]; then
  # a stub/symlink is fine; only a truly missing binary is fatal
  [ -e "$GATE_BIN" ] || { echo "✗ candidate binary not found: $GATE_BIN" >&2; exit 2; }
fi

# ---- shared state ----------------------------------------------------------------------------------
GATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/cc-upgrade-gate.XXXXXX")"
export GATE_RESULTS="$GATE_TMP/results.jsonl"
export STUB_LOG="$GATE_TMP/stub.log"
: >"$GATE_RESULTS"
: >"$STUB_LOG"
trap 'rm -rf "$GATE_TMP"' EXIT

# shellcheck source=/dev/null
. "$LIB/common.sh"

BIN_VERSION="$("$GATE_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
BIN_VERSION="${BIN_VERSION:-unknown}"

echo "== cc-upgrade-gate ==" >&2
echo "  binary:   $GATE_BIN ($BIN_VERSION)" >&2
echo "  model:    $GATE_MODEL" >&2
echo "  accounts: $GATE_ACCOUNTS" >&2
echo "  spawn:    $([ "$GATE_SPAWN" = 1 ] && echo 'live (#7/#8/#9 exercised)' || echo 'SKIP (#7/#8/#9)')" >&2
echo >&2

# ---- source every probe file (auto-discovery from CHECKS_DIR) --------------------------------------
shopt -s nullglob
for f in "$CHECKS_DIR"/check*.sh; do
  # shellcheck source=/dev/null
  . "$f" || echo "⚠️  failed to source $(basename "$f") — its check will register as MISSING" >&2
done
shopt -u nullglob

# ---- run each discovered check_NN in order, crash-guarded -------------------------------------------
checks="$(declare -F | awk '{print $3}' | grep -E '^check_[0-9][0-9]$' | sort -u)"
[ -n "$checks" ] || { echo "✗ no check_NN probes discovered under $LIB" >&2; exit 2; }

for fn in $checks; do
  n="${fn#check_}"
  before="$(wc -l <"$GATE_RESULTS" | tr -d ' ')"
  "$fn" || true
  after="$(wc -l <"$GATE_RESULTS" | tr -d ' ')"
  if [ "$after" -le "$before" ]; then
    emit_result "$n" "$fn" FAIL "probe emitted no result (crashed / did not call emit_result)" ""
  fi
done

# ---- aggregate → verdict + machine JSON (stdout) + human summary (stderr) ---------------------------
echo >&2
python3 - "$GATE_RESULTS" "$GATE_BIN" "$BIN_VERSION" "$GATE_MODEL" "$GATE_ACCOUNTS" <<'PY'
import json, sys
results_path, binary, version, model, accounts = sys.argv[1:6]
checks = []
with open(results_path) as fh:
    for line in fh:
        line = line.strip()
        if line:
            checks.append(json.loads(line))
checks.sort(key=lambda c: c["check"])
counts = {"pass": 0, "fail": 0, "skip": 0}
for c in checks:
    counts[c["status"].lower()] = counts.get(c["status"].lower(), 0) + 1
verdict = "RED" if counts["fail"] else "GREEN"
report = {
    "gate": "cc-upgrade-gate",
    "binary": binary, "binary_version": version, "model": model,
    "accounts": accounts.split(),
    "verdict": verdict,
    "counts": counts,
    "checks": checks,
}
# machine JSON → stdout
print(json.dumps(report, indent=2))
# human summary → stderr
def w(s): sys.stderr.write(s + "\n")
w("── summary ─────────────────────────────────────────────")
for c in checks:
    mark = {"PASS": "✓", "FAIL": "✗", "SKIP": "○"}.get(c["status"], "?")
    w(f"  {mark} #{c['check']:>2} {c['slug']:<26} {c['evidence']}")
w("────────────────────────────────────────────────────────")
w(f"  {counts['pass']} pass · {counts['fail']} fail · {counts['skip']} skip")
w(f"  VERDICT: {verdict}  ({model} on {binary} {version})")
if verdict == "RED":
    w("  ⇒ PARK the upgrade. Failing ways-of-working named above. Do NOT activate.")
else:
    w("  ⇒ ALL GREEN. Ways of working hold — safe to activate (see cc-upgrade-gate skill).")
sys.exit(1 if verdict == "RED" else 0)
PY
rc=$?
exit "$rc"
