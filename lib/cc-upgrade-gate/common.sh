#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# cc-upgrade-gate/common.sh — the FROZEN contract shared by every probe.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# Sourced by scripts/cc-upgrade-gate.sh BEFORE any check*.sh. Teammates CONSUME these helpers and
# NEVER edit this file. Each probe file defines exactly one `check_NN` function that:
#   • reads the gate env (below),
#   • performs a SELF-EVIDENCING probe (assert on the artifact — modelUsage, argv, exit — never a claim),
#   • calls `emit_result <n> <slug> <PASS|FAIL|SKIP> <evidence> [detail]` EXACTLY ONCE,
#   • returns 0 (status travels in the JSON, not the exit code; the orchestrator aggregates + fails-closed).
#
# Gate env (set by the orchestrator, read-only for probes):
#   GATE_BIN        candidate claude binary (absolute path)
#   GATE_MODEL      model id under test (e.g. claude-opus-5)
#   GATE_ACCOUNTS   space-separated account names (e.g. "next next2"); [0] = primary
#   GATE_RETRIES    bounded-retry budget for flaky probes (default 3)
#   GATE_RESULTS    JSONL sink — emit_result appends one line here (machine truth)
#   STUB_LOG        where build_stub_binary records argv+env (effect-read probes)
#   GATE_SPAWN      1 = run the expensive spawn probes (#7/#8/#9) live; 0 = they SKIP (fast iteration)
#
# Status vocabulary:  PASS (green) · FAIL (red → verdict RED, fail-closed) · SKIP (n/a, carries reason,
#   NEVER drags the verdict red).
# ───────────────────────────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2086  # $GATE_ACCOUNTS is a deliberate space-split word list, never quoted.

# ---- account name → config dir (verified 2026-07-24; see the plan's "Verified facts") ---------------
gate_cfg_for() {
  case "$1" in
    next)  printf '%s\n' "$HOME/.claude-next" ;;
    next2) printf '%s\n' "$HOME/.claude-secondary" ;;
    next3) printf '%s\n' "$HOME/.claude-tertiary" ;;
    next4) printf '%s\n' "$HOME/.claude-quaternary" ;;
    *)     printf '%s\n' "" ;;
  esac
}

gate_primary_account() { set -- $GATE_ACCOUNTS; printf '%s\n' "$1"; }

# ---- headless probe: run the candidate binary in --print JSON mode (the seed-finding invocation) -----
# Usage: gate_headless <config_dir> <model> <prompt> [extra flags…]
# Echoes raw JSON to stdout. Returns non-zero only on transport failure (no JSON at all).
gate_headless() {
  local cfg="$1" model="$2" prompt="$3"; shift 3
  local out
  # </dev/null is load-bearing: without it `--print` blocks ~3s waiting on stdin (and can hang a
  # tool-driving turn entirely). Redirecting makes every probe deterministic and prompt.
  out="$(CLAUDE_CONFIG_DIR="$cfg" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 \
         "$GATE_BIN" --model "$model" --print --output-format json "$@" "$prompt" </dev/null 2>/dev/null)"
  printf '%s' "$out"
  # transport check: did we get a JSON object back at all?
  printf '%s' "$out" | head -c 1 | grep -q '{'
}

# ---- bounded retry for flaky probes (auto-mode classifier is transiently flaky) ----------------------
# Usage: retry <n> <cmd…>   — runs cmd up to n times, 2s backoff, returns cmd's last rc.
retry() {
  local n="$1"; shift
  local i=0 rc=1
  while [ "$i" -lt "$n" ]; do
    if "$@"; then return 0; fi
    rc=$?; i=$((i + 1))
    [ "$i" -lt "$n" ] && sleep 2
  done
  return "$rc"
}

# ---- JSON assertion primitives (read JSON on stdin) --------------------------------------------------
# NOTE: these read PIPED JSON from stdin, so they use `python3 -c` — NEVER `python3 - <<'PY'` (the
# heredoc would BE stdin and shadow the pipe → json.load reads empty → always exit 2. The stdin-eater
# trap; see memory blind-check-generators-stdin-and-sid-keys). Probes that pass all data via argv
# (emit_result, the aggregator) may use a heredoc; anything reading the pipe must use -c.
#
# json_has_model <model> : exit 0 iff modelUsage carries <model> AND is_error is falsey (no demotion).
json_has_model() {
  python3 -c '
import sys, json
model = sys.argv[1]
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(2)
mu = o.get("modelUsage") or {}
sys.exit(0 if (model in mu and not o.get("is_error")) else 1)
' "$1"
}

# json_get <dotted.key> : print a scalar value (or compact JSON for dict/list); empty if absent.
json_get() {
  python3 -c '
import sys, json
try:
    o = json.load(sys.stdin)
except Exception:
    sys.exit(2)
cur = o
for k in sys.argv[1].split("."):
    cur = cur.get(k) if isinstance(cur, dict) else None
if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(",", ":")))
else:
    print(cur)
' "$1"
}

# ---- stub binary for effect-read probes (launcher / depth) ------------------------------------------
# Writes an executable at <path> that RECORDS its argv + selected env to $STUB_LOG, then exits 0.
# Lets a probe run the REAL launcher body against a fake binary and assert what the launcher passed —
# an effect-read, not a grep.
build_stub_binary() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'STUB'
#!/usr/bin/env bash
{
  echo "ARGV: $*"
  echo "SPAWN_DEPTH=${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH-<unset>}"
  echo "CONFIG_DIR=${CLAUDE_CONFIG_DIR-<unset>}"
  echo "DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER-<unset>}"
  echo "PWD=$PWD"
  echo "---"
} >>"${STUB_LOG:?STUB_LOG must be set for the stub binary}"
# emit minimal valid JSON so a caller that parses --output-format json does not choke
case " $* " in *" --output-format json "*) echo '{"is_error":false,"result":"stub","modelUsage":{}}' ;; esac
exit 0
STUB
  chmod +x "$path"
}

# ---- extract a shell FUNCTION body from a file (for launcher effect-reads) ---------------------------
# Usage: extract_function <name> <file>  — prints the `name() { … }` block (brace-balanced, top level).
extract_function() {
  local fn="$1" file="$2"
  awk -v f="$fn" '
    $0 ~ "^"f"\\(\\)" {inf=1}
    inf {print}
    inf && /^\}/ {exit}
  ' "$file"
}

# ---- result emission + live reporters ----------------------------------------------------------------
_gate_color() { [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; }
ok()   { if _gate_color; then printf '\033[32m  ✓ %s\033[0m\n' "$*" >&2; else printf '  ✓ %s\n' "$*" >&2; fi; }
bad()  { if _gate_color; then printf '\033[31m  ✗ %s\033[0m\n' "$*" >&2; else printf '  ✗ %s\n' "$*" >&2; fi; }
skip() { if _gate_color; then printf '\033[33m  ○ %s\033[0m\n' "$*" >&2; else printf '  ○ %s\n' "$*" >&2; fi; }
info() { printf '  · %s\n' "$*" >&2; }

# need <tool> : 0 if present, 1 if absent (probe decides to SKIP).
need() { command -v "$1" >/dev/null 2>&1; }

# emit_result <n> <slug> <PASS|FAIL|SKIP> <evidence> [detail]
# Appends one JSON line to $GATE_RESULTS (machine truth) and prints a colored one-liner to stderr.
# NOTE: the status arg uses a local named `st`, NOT `status` — `status` is a read-only special var in
# zsh, so `local status` aborts the function when these helpers are sourced into a zsh shell (as the
# verify path does). The gate itself runs under bash, but keep this zsh-safe for source-based checks.
emit_result() {
  local n="$1" slug="$2" st="$3" evidence="$4" detail="${5:-}"
  python3 - "$n" "$slug" "$st" "$evidence" "$detail" >>"$GATE_RESULTS" <<'PY'
import json, sys
n, slug, status, evidence, detail = sys.argv[1:6]
print(json.dumps({"check": int(n), "slug": slug, "status": status,
                  "evidence": evidence, "detail": detail}))
PY
  case "$st" in
    PASS) ok   "#$n $slug — $evidence" ;;
    FAIL) bad  "#$n $slug — $evidence" ;;
    SKIP) skip "#$n $slug — $evidence" ;;
    *)    info "#$n $slug — $evidence" ;;
  esac
}
