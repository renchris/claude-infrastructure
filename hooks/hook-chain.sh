#!/usr/bin/env bash
# hook-chain.sh — ONE process for a whole hook chain (§8.5.4 fork storm, §12.5).
#
# ── THE PROBLEM ────────────────────────────────────────────────────────────────────────────────
# Measured 2026-07-31 at load 0.75/core (a HEALTHY box — this is the FLOOR, not the worst case):
#
#   PreToolUse/Bash   6 processes  232 ms   ← curl-gate.py 46 · validate-bash 79 · worktree-guard 33
#                                             keychain 25 · rm-safe 25 · ship-rail 24
#   PostToolUse/Bash  2 processes  136 ms   ← log-bash 35 · waiting-recycle 101
#   ── total per Bash tool call: 8 processes, 368 ms ──
#
# Floor probes at the same load: bash fork+exec 11 ms · python3 startup 38 ms · jq startup 13 ms.
# ⚠ THOSE THREE FLOOR FIGURES ARE INFLATED ~4x — they include the measuring wrapper's own fork.
# The derived claim ("~93 ms is interpreter startup, ~78 ms is six redundant jq") is therefore
# WRONG; it is kept here only because it is the reasoning the build followed. See MEASURED OUTCOME
# below for the corrected model before using any number in this block.
#
# §8.5.4 shows why this is the dominant term we own: forks/s is O(N), cost-per-fork is O(load), and
# load is O(forks/s) — O(N^2). Unlike iTerm2/WindowServer/XProtect (~2.4 unsheddable cores, §8.5.7)
# this is entirely ours. §8.5.4's structural answer is a long-lived per-session broker, with the
# BOUNDED FALLBACK being exactly this: collapse the chain into one process. This is that fallback.
#
# ── ⛔ MEASURED OUTCOME: THE NAIVE COLLAPSE DOES NOT PAY. READ BEFORE WIRING THIS UP. ──────────
# This dispatcher is CORRECT and heavily tested, but it is **deliberately NOT wired into
# settings.json**, because measuring it falsified the premise above. Recorded here so the next
# reader does not rebuild it:
#
#   REAL 6-guard chain, serial (today)   174 ms      dispatcher exec mode     ~180 ms
#   6 no-op members, serial               60 ms      dispatcher source mode    41 ms
#
# It wins on trivial members and loses on the real ones. Three reasons, all measured:
#
#  1. THE 11-15 ms "fork+exec" FIGURE IS A MEASUREMENT ARTIFACT. Timing `bash -c 'exit 0'` from a
#     wrapper measures the WRAPPER's own fork too. The MARGINAL cost of an extra exec inside an
#     already-running shell is ~2-4 ms for a page-cached binary. Measured directly: a guard's whole
#     `INPUT=$(cat); CMD=$(printf|jq)` preamble is 19 ms in a fresh bash, and replacing BOTH forks
#     with builtins saves 4 ms — not the ~24 ms/guard the floor probes implied. So the headline
#     "93 ms of interpreter startup + 78 ms of redundant jq" above is inflated roughly 4x.
#  2. SOURCING IS NOT UNIFORMLY CHEAPER. Sourcing a large member costs bash the same parse it would
#     do after an exec, minus only process creation. Measured: git-worktree-guard -3 ms and
#     keychain-guard -8 ms (cheaper), but validate-bash.sh +48 ms (94 -> 142 ms) — the chain's
#     biggest member is its worst case, so the chain total does not improve.
#  3. WALL-CLOCK CANNOT ADJUDICATE THIS ON THIS BOX. Load oscillated 10.6 -> 24.0 DURING these runs
#     at constant session count — §8.5.7's documented 2x swing. Every delta above is inside that
#     noise band, which is itself the finding: the collapse's benefit is proportional to
#     cost-per-fork, which is O(load), so it only pays in the high-load regime it exists to
#     prevent — and therefore cannot be validated by measurement at normal load.
#
# What IS worth doing, in measured order of value, is recorded in the plan's §12.7 — headed by the
# fact that curl-gate.py costs 46 ms of every Bash call (26% of this chain) while being incapable
# of deciding anything outside one project.
#
# ── THE DESIGN ─────────────────────────────────────────────────────────────────────────────────
# One process reads stdin once, then runs every member of a named chain in order, and aggregates
# their decisions with the harness's own precedence. Members are UNCHANGED and stay independently
# runnable — the dispatcher feeds each the identical payload on stdin.
#
#   exec mode (DEFAULT)   — each member is fork+exec'd exactly as the harness does today, so the
#                           process model is unchanged. Default because source mode is not proven
#                           faster (see MEASURED OUTCOME).
#   source mode (opt-in)  — each member runs in a SUBSHELL (fork, no exec), skipping the per-member
#                           interpreter startup. Members are isolated: shell options, IFS and
#                           `exit` cannot escape a subshell into the next member.
#
# ── THE SAFETY LAW ─────────────────────────────────────────────────────────────────────────────
# This dispatcher fronts SIX SAFETY GATES (curl egress, bash validation, worktree, keychain, rm,
# push). Memory `decision-moved-out-of-the-guarded-unit`: moving a decision out of the guarded unit
# can leave the suite green while the invariant is un-fixed. Therefore:
#
#   1. THERE IS NO SKIP MODE. No value of any env var makes this run fewer members than the
#      registry lists. "Disabled" degrades to legacy fork+exec, never to skip — a kill switch that
#      silently disarms six guards is worse than no kill switch. Pinned by the NO-SKIP-SPELLING
#      test (memory `denylist-enumerates-spellings-not-the-class`).
#   2. INERTNESS IS LOUD. A missing registry, an empty registry, or a member absent from disk
#      REFUSES (exit 2) naming the exact revert. It never admits. §12.2's rule for capacity_gate
#      applies verbatim: a silent admit is the failure mode, not the safe default.
#   3. EVERY MEMBER ALWAYS RUNS. The harness runs every hook in a matcher group even when one
#      blocks, so this does too — short-circuiting would drop the side effects of later members.
#
# Escape hatch, deliberately NOT an env var (that would be a skip spelling): revert the chain's
# settings.json entry to the original per-hook entries. `--emit-settings <chain>` prints them.
#
# ── KNOWN SEMANTIC DIFFERENCE (do not discover this later) ─────────────────────────────────────
# Per-member timeouts are lost. Today settings.json can carry a `timeout` per hook entry; collapsed,
# the harness applies ONE timeout to the dispatcher, so a member that hangs starves the members
# after it (the harness still bounds the whole chain, so a hang is not unbounded). The chain's
# settings.json timeout must therefore be >= the SUM of the member timeouts it replaces;
# `--emit-settings` computes that. Restoring true per-member bounds needs a shared watchdog rather
# than a `timeout` fork per member (which would spend back the win) — named, not silently deferred.
#
# Usage:  hook-chain.sh <chain-name>      run a chain (payload on stdin)
#         hook-chain.sh --selftest        RED-proofed self-check
#         hook-chain.sh --emit-settings <chain>   print the settings.json entry for this chain
#         hook-chain.sh --list            list registered chains
#
# Env:  CC_HOOK_CHAIN_MODE=source|exec    (default EXEC; any other value degrades to exec)
#       CC_HOOK_CHAIN_DISABLED=<any>      alias for mode=exec — NEVER a skip
#       CC_HOOK_CHAIN_DIR                 registry dir (default $CLAUDE_CONFIG_DIR/config/hook-chains.d)
#       CC_HOOK_CHAIN_MEMBER_DIR          member dir  (default $CLAUDE_CONFIG_DIR/hooks)

set -uo pipefail

CFG_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CHAIN_DIR="${CC_HOOK_CHAIN_DIR:-$CFG_ROOT/config/hook-chains.d}"
MEMBER_DIR="${CC_HOOK_CHAIN_MEMBER_DIR:-$CFG_ROOT/hooks}"

# ── mode resolution: the ONLY two destinations are `source` and `exec` ─────────────────────────
# Assigns MODE directly. `mode="$(resolve_mode)"` would be a command-substitution FORK to compute
# a pure-bash string — on the hottest path in the system, where the whole point is not forking.
resolve_mode() {
  if [ -n "${CC_HOOK_CHAIN_DISABLED:-}" ]; then MODE='exec'; return; fi
  # DEFAULT IS exec, NOT source — see MEASURED OUTCOME above. source mode is implemented, tested
  # and available, but it is not the default because it is not proven faster and is measurably
  # SLOWER for the chain's largest member. Opt in explicitly to experiment.
  case "${CC_HOOK_CHAIN_MODE:-exec}" in
    source) MODE='source' ;;
    *)      MODE='exec'   ;;   # exec, empty, garbage — all degrade to the SAFE legacy path
  esac
}

refuse() { # <msg>  — loud inertness: block, never admit
  printf 'hook-chain: REFUSING (this chain fronts safety gates; admitting would run none of them)\n%s\n' "$1" >&2
  printf 'Fix: restore the per-hook entries in settings.json for this chain, or repair the registry.\n' >&2
  printf '     %s --emit-settings <chain>   prints the collapsed entry\n' "${BASH_SOURCE[0]}" >&2
  exit 2
}

# Parsed with bash builtins, NOT sed. A fork-reduction tool that forks `sed` (and `mktemp`) before
# doing any work pays ~22 ms of fixed cost — measured, and it ate the ENTIRE per-member saving at
# n=6 (dispatcher 51 ms vs serial 56 ms). Every fork on this path must justify itself.
read_registry() { # <chain> -> members on stdout, one per line
  local chain="$1"
  local f="$CHAIN_DIR/$chain"   # separate `local`: a second assignment in ONE `local` may not see the first
  [ -f "$f" ] || refuse "registry not found: $f"
  [ -r "$f" ] || refuse "registry not readable: $f"
  local line out=''
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                 # strip comment
    while [ "${line% }" != "$line" ] || [ "${line%$'\t'}" != "$line" ]; do line="${line%[ $'\t']}"; done
    line="${line#"${line%%[![:space:]]*}"}"   # strip leading space
    [ -n "$line" ] && out+="$line"$'\n'
  done < "$f"
  [ -n "$out" ] || refuse "registry is EMPTY: $f (a chain that runs zero guards is not a pass)"
  REG="$out"
}

# ── decision precedence: deny > ask > allow ────────────────────────────────────────────────────
# NORMALIZE, then match — never enumerate spellings (memory `denylist-enumerates-spellings-not-
# the-class`). The live chain emits BOTH shapes: keychain-guard uses `jq -nc` (compact,
# `"permissionDecision":"deny"`) while validate-bash / rm-safe-allowlist / ship-rail-push-allow
# print a pretty heredoc (`"permissionDecision": "deny"`, with a space). A two-spelling case
# statement read the pretty form as rank 0 — i.e. it silently lost three guards' verdicts. Caught
# by the live-parity corpus's anti-vacuity check, which reported 0 triggers where 5 were expected.
rank_of() {
  local n="${1//[[:space:]]/}"
  case "$n" in
    *'"permissionDecision":"deny"'*)  printf '3' ;;
    *'"permissionDecision":"ask"'*)   printf '2' ;;
    *'"permissionDecision":"allow"'*) printf '1' ;;
    *) printf '0' ;;
  esac
}

run_chain() { # <chain>
  local chain="$1"; local MODE; resolve_mode; local mode="$MODE"
  # Builtin read, NOT `payload="$(cat)"` — that is a fork+exec of cat (~11 ms) on the hottest path
  # in the system. `read -d ''` returns non-zero at EOF, which is the normal case here.
  local payload=''
  IFS= read -r -d '' payload || true

  # NOTE: read_registry's `refuse` runs in whatever subshell wraps it, so its exit 2 CANNOT stop
  # this shell on its own — capture the status and re-refuse here. Read via `< <(...)` instead and
  # a missing registry silently yields an empty chain, i.e. the dispatcher ADMITS with zero guards
  # run. That is the §12.2 silent-admit failure, and the selftest caught it here on first run.
  local REG=''; read_registry "$chain"     # sets REG; refuses (exit 2) on its own if unusable

  local members=(); local m
  while IFS= read -r m; do [ -n "$m" ] && members+=( "$m" ); done <<<"$REG"
  [ "${#members[@]}" -gt 0 ] || refuse "chain '$chain' resolved to ZERO members"

  # pre-flight: every member must exist and be executable BEFORE any runs, so a broken registry
  # refuses as a unit rather than half-running the chain
  for m in "${members[@]}"; do
    [ -e "$MEMBER_DIR/$m" ] || refuse "chain '$chain' member ABSENT on disk: $MEMBER_DIR/$m"
    [ -x "$MEMBER_DIR/$m" ] || refuse "chain '$chain' member NOT EXECUTABLE: $MEMBER_DIR/$m"
  done

  # $$ + $RANDOM instead of mktemp: mktemp is a fork+exec (~11 ms) on the hottest path in the
  # system. The file is opened O_TRUNC by `: >` below and lives under a private-by-default TMPDIR;
  # it holds a member's stderr for microseconds, never a secret at rest.
  local errf="${TMPDIR:-/tmp}/hook-chain.$$.$RANDOM.err"
  # The payload is written ONCE and every member is redirected from it. A per-member here-string
  # (`. "$path" <<<"$payload"`) makes bash materialise a fresh temp file PER MEMBER — measured as
  # the reason the real 6-guard chain showed no win (177 ms) while 6 no-op members did (60->41 ms).
  local payf="${TMPDIR:-/tmp}/hook-chain.$$.$RANDOM.in"
  # shellcheck disable=SC2064  # expand NOW: the trap must survive these going out of scope
  trap "rm -f '$errf' '$payf'" EXIT
  : > "$errf" || refuse "cannot write scratch file: $errf"
  printf '%s' "$payload" > "$payf" || refuse "cannot write scratch file: $payf"

  local best_out='' best_rank=0 blocked=0 block_err='' out rc
  for m in "${members[@]}"; do
    local path="$MEMBER_DIR/$m"
    : > "$errf"
    if [ "$mode" = source ] && [ "${m##*.}" = sh ]; then
      # ONE fork, no exec. The command substitution IS already a subshell, so an inner `( … )`
      # would be a second redundant fork — 2 forks/member instead of 1, on the hottest path.
      # `set -e`/`set -u`/IFS/`exit` set by the member are contained by that subshell, so member N
      # cannot change member N+1's behaviour — pinned by the isolation and early-exit tests.
      out="$( set +eu +o pipefail; IFS=$' \t\n'; unset CDPATH
              # shellcheck disable=SC1090  # runtime-resolved member path, by design
              . "$path" <"$payf" 2>"$errf" )"; rc=$?
    else
      out="$( "$path" <"$payf" 2>"$errf" )"; rc=$?
    fi

    if [ "$rc" -eq 2 ]; then
      blocked=1
      block_err+="[$m] $(cat "$errf" 2>/dev/null)"$'\n'
    elif [ "$rc" -ne 0 ]; then
      # non-blocking member error: surface its stderr, never let it decide the chain
      printf '[%s exit %s] %s\n' "$m" "$rc" "$(cat "$errf" 2>/dev/null)" >&2
    else
      [ -s "$errf" ] && cat "$errf" >&2
    fi

    if [ -n "$out" ]; then
      local r; r="$(rank_of "$out")"
      # strictly-greater keeps the FIRST member at a given rank, matching a stable serial chain
      if [ "$r" -gt "$best_rank" ]; then best_rank="$r"; best_out="$out"
      elif [ "$best_rank" -eq 0 ] && [ -z "$best_out" ]; then best_out="$out"; fi
    fi
  done

  if [ "$blocked" -eq 1 ]; then
    printf '%s' "$block_err" >&2
    exit 2
  fi
  [ -n "$best_out" ] && printf '%s' "$best_out"
  exit 0
}

emit_settings() { # <chain> — the collapsed settings.json entry, with the summed timeout
  local chain="$1" n=0 line
  local REG=''; read_registry "$chain"
  while IFS= read -r line; do [ -n "$line" ] && n=$((n+1)); done <<<"$REG"
  printf '{ "type": "command", "command": "~/.claude/hooks/hook-chain.sh %s", "timeout": %s }\n' \
    "$chain" "$(( n * 10 + 10 ))"
  printf '# replaces %s member entries; timeout is the SUM bound (see KNOWN SEMANTIC DIFFERENCE)\n' "$n" >&2
}

# ── selftest ───────────────────────────────────────────────────────────────────────────────────
selftest() {
  local pass=0 fail=0 T; T="$(mktemp -d "${TMPDIR:-/tmp}/hcst.XXXXXXXX")"
  trap 'rm -rf "$T"' RETURN
  mkdir -p "$T/chains" "$T/hooks"
  export CC_HOOK_CHAIN_DIR="$T/chains" CC_HOOK_CHAIN_MEMBER_DIR="$T/hooks"
  local SELF="${BASH_SOURCE[0]}"
  local PAY='{"tool_input":{"command":"echo hi"}}'
  ck() { # <label> <expected-status> <expected-substring-or-empty> <chain> [env...]
    local label="$1" exp="$2" sub="$3" chain="$4"; shift 4
    local o s
    o="$(printf '%s' "$PAY" | env "$@" "$SELF" "$chain" 2>/dev/null)"; s=$?
    if [ "$s" -eq "$exp" ] && { [ -z "$sub" ] || printf '%s' "$o" | grep -q -- "$sub"; }; then
      printf '  ok   %s\n' "$label"; pass=$((pass+1))
    else
      printf '  FAIL %s (status=%s want=%s out=%s)\n' "$label" "$s" "$exp" "$o"; fail=$((fail+1))
    fi
  }
  mk() { printf '#!/usr/bin/env bash\nINPUT=$(cat)\nprintf %%s %s\nexit %s\n' "'$3'" "$2" > "$T/hooks/$1"; chmod +x "$T/hooks/$1"; }
  local DENY='{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"d"}}'
  local ALLOW='{"hookSpecificOutput":{"permissionDecision":"allow","permissionDecisionReason":"a"}}'
  local ASK='{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"k"}}'

  mk quiet.sh 0 ''; mk deny.sh 0 "$DENY"; mk allow.sh 0 "$ALLOW"; mk ask.sh 0 "$ASK"; mk blk.sh 2 ''; mk err.sh 1 ''

  printf 'quiet.sh\nquiet.sh\n'      > "$T/chains/c_quiet"
  printf 'quiet.sh\ndeny.sh\n'       > "$T/chains/c_deny"
  printf 'allow.sh\ndeny.sh\n'       > "$T/chains/c_conflict"
  printf 'allow.sh\nask.sh\n'        > "$T/chains/c_ask"
  printf 'blk.sh\nallow.sh\n'        > "$T/chains/c_block"
  printf 'err.sh\nquiet.sh\n'        > "$T/chains/c_err"
  printf 'quiet.sh\nghost.sh\n'      > "$T/chains/c_ghost"
  : > "$T/chains/c_empty"

  ck 'all-abstain chain is silent, exit 0'          0 ''       c_quiet
  ck 'lone decision passes through'                 0 '"deny"' c_deny
  ck 'deny beats allow (allow listed FIRST)'        0 '"deny"' c_conflict
  ck 'ask beats allow'                              0 '"ask"'  c_ask
  ck 'exit 2 blocks the chain'                      2 ''       c_block
  ck 'exit 1 does NOT block'                        0 ''       c_err
  ck 'absent member REFUSES'                        2 ''       c_ghost
  ck 'empty registry REFUSES'                       2 ''       c_empty
  ck 'unknown chain REFUSES'                        2 ''       c_nosuch
  ck 'exec mode: deny still beats allow'            0 '"deny"' c_conflict CC_HOOK_CHAIN_MODE=exec
  ck 'garbage mode degrades to exec, still decides' 0 '"deny"' c_conflict CC_HOOK_CHAIN_MODE=garbage
  ck 'DISABLED= degrades to exec, still decides'    0 '"deny"' c_conflict CC_HOOK_CHAIN_DISABLED=1

  # RED-proof: the checks above must be able to FAIL. Drop the guard; the decision must vanish.
  printf 'allow.sh\n' > "$T/chains/c_conflict"
  local o; o="$(printf '%s' "$PAY" | "$SELF" c_conflict 2>/dev/null)"
  if printf '%s' "$o" | grep -q '"deny"'; then
    printf '  FAIL RED-proof: deny survived removing deny.sh — the parity checks are vacuous\n'; fail=$((fail+1))
  else
    printf '  ok   RED-proof: removing the guard removes its decision\n'; pass=$((pass+1))
  fi

  # NO-SKIP-SPELLING: every spelling must still run BOTH members
  printf '#!/usr/bin/env bash\ncat >/dev/null; echo x >> "%s/ran.log"; exit 0\n' "$T" > "$T/hooks/cnt.sh"
  chmod +x "$T/hooks/cnt.sh"; printf 'cnt.sh\ncnt.sh\n' > "$T/chains/c_cnt"
  local sk_ok=1 sp
  for sp in CC_HOOK_CHAIN_DISABLED=1 CC_HOOK_CHAIN_MODE=exec CC_HOOK_CHAIN_MODE=source \
            CC_HOOK_CHAIN_MODE=garbage CC_HOOK_CHAIN_MODE= CC_HOOK_CHAIN_DISABLED=skip; do
    : > "$T/ran.log"
    printf '%s' "$PAY" | env "$sp" "$SELF" c_cnt >/dev/null 2>&1
    [ "$(wc -l < "$T/ran.log" | tr -d ' ')" -eq 2 ] || { sk_ok=0; printf '  FAIL no-skip-spelling: %s\n' "$sp"; }
  done
  if [ "$sk_ok" -eq 1 ]; then printf '  ok   NO-SKIP-SPELLING: every env spelling ran all members\n'; pass=$((pass+1))
  else fail=$((fail+1)); fi

  printf '\n%s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest)      selftest ;;
  --emit-settings) [ $# -ge 2 ] || { echo "usage: --emit-settings <chain>" >&2; exit 64; }; emit_settings "$2" ;;
  --list)          ls -1 "$CHAIN_DIR" 2>/dev/null || { echo "no registry dir: $CHAIN_DIR" >&2; exit 1; } ;;
  ''|-h|--help)    sed -n '1,60p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)               run_chain "$1" ;;
esac
