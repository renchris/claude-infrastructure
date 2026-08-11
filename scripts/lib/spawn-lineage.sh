# shellcheck shell=bash
# spawn-lineage.sh — carry a spawn lineage ACROSS the pane boundary, and bound its generations.
# SOURCED, never executed.
#
#   cc_lineage_resolve                 → sets CC_LINEAGE_ROOT_CUR / _GEN_CUR / _BASIS for THIS process
#   cc_lineage_child_env               → prints the `--env K=V` argv a kitty launch must carry, one
#                                        token per line, so the child inherits root and gen+1
#   cc_lineage_admit <caller> <sid> <what>  → 0 ADMIT / 9 REFUSE, on the generation cap
#   cc_lineage_root / _gen / _reason / _basis  → accessors for the caller's message
#
# ── WHY THIS EXISTS: THE PROCESS TREE IS SEVERED, SO LINEAGE CANNOT BE INFERRED ────────────────
# Backlog bffbce207f12 asked for a per-lineage spawn bound and named its own first step a PROBE,
# because the whole design is vacuous if the environment does not cross a spawn. That probe ran
# 2026-08-11 and is recorded in docs/research/spawn-lineage-probe-2026-08-11.md. Three arms, each
# with a positive control, on kitty 0.48.2:
#
#   arm                                             result
#   in-process Agent subagent                       subagent Bash PPID == the LEAD's own claude pid
#                                                   (81973, byte-identical) — ONE OS process
#   kitty pane, caller exports the var only         ABSENT in the pane          ← does NOT cross
#   kitty pane, launch carries `--env K=V`          present                     ← control, crosses
#   kitty pane, launch carries `--copy-env`         present                     ← crosses on demand
#   kitty pane, `--env` through `zsh -l -i -c`      present                     ← the real pane shape
#
# Two facts follow, and they point in opposite directions:
#
#  1. AN IN-PROCESS SUBAGENT CANNOT BE STAMPED AT ALL. It is not a child process — it shares the
#     lead's, so its environment IS the lead's environment and there is no per-child slot to write
#     a different generation into. A PreToolUse hook cannot mutate its caller's env either. So the
#     `depth+1` half of the filed design is unreachable on that surface *by construction*, which is
#     the same verdict hooks/agent-teams-enforce.sh reached from the other side: Claude Code does
#     not expose the Agent tool to subagents, so nothing nests there and the population is empty.
#     The filed design named the Agent tool as the chokepoint. The probe says it is the wrong one.
#
#  2. ACROSS A PANE, AN EXPLICIT STAMP IS THE *ONLY* CARRIER. kitty remote-control launches a pane
#     as a child of the kitty DAEMON, not of the caller, so the OS process tree is cut at exactly
#     the edge the cascade crosses. That is not a hypothesis — it is visible in the fleet's own
#     records: across all 1085 rows of logs/pane-spawns.jsonl, the `ancestry` field contains
#     `claude` AT MOST ONCE (distribution {0:671, 1:415}) and every chain terminates at a kitty pid.
#     A pane spawned BY a pane is therefore INDISTINGUISHABLE from a top-level one in the process
#     tree, and any bound that reads ancestry is blind by construction rather than measuring a
#     shallow fleet (memory `cap-whose-population-is-empty`, and the sibling trap in
#     `positive-control-the-denominator`). `--env` is what survives the cut.
#
# ── WHY A THIRD LINEAGE INSTRUMENT, WHEN THE LEASE ALREADY SPANS THE CASCADE ───────────────────
# It does not replace the lease (scripts/lib/worker-claim-gate.sh) — it covers the population the
# lease CANNOT see. `cc_worker_claim_admit` keys on the cwd being `wt-<12 lowercase hex>` and
# returns 0 (abstain) for anything else, which is correct for it: no worktree, no item, no lease.
# Measured on the same 1085 rows, that abstention is most of the fleet, and the fan-outs on the
# far side of it are the BIGGEST ones:
#
#   cwd class                            spawns   distinct claude spawners   max fan-out by one
#   dispatch wt-<12hex>  (lease binds)      214             40                      7
#   shared repo root     (lease abstains)   303             23                     21   ← 5 sessions ≥10
#
# So the bound that exists works, and the population it cannot reach is the one with the widest
# fan-outs. Identity is still the right instrument (quantity resets at the session edge — memory
# `counter-resets-at-the-boundary-the-runaway-crosses`); this simply supplies an identity where the
# ledger has none to offer.
#
# ── WHAT IS ENFORCED, AND WHAT IS ONLY RECORDED ────────────────────────────────────────────────
# GENERATION is enforced, because it is the axis that SEPARATES the bands. Ordinary work is one
# generation of fan-out; the 2026-08-07 runaway was three, then a fourth. WIDTH per root is only
# COUNTED, deliberately: the widest legitimate observation (21 panes from one repo-root session)
# and the pathological one are not separated by any threshold this data supports, and a bound whose
# threshold sits inside the survived band can only produce false refusals (memory
# `threshold-must-separate-fatal-from-survived`, `bound-must-fit-the-band-not-the-bench`). The
# counter ships so the NEXT reader has the distribution the threshold needs; it never refuses.
#
# THE GENERATION LADDER, and why the default is 3 rather than the sibling gate's 2:
#   gen 0  a pane the operator started by hand (the desk). Unstamped.
#   gen 1  a session the desk fired or split.                     ← wave lead
#   gen 2  a session THAT session fired.                          ← per-phase dispatched session,
#                                                                   the documented default locus
#   gen 3  that session's own teammates.                          ← sanctioned: "teammates remain
#                                                                   correct INSIDE such a session"
#   gen 4  REFUSED.
# CLAUDE.md § Agent Teams sanctions every rung through 3, so a cap of 2 — which is what the lease
# gate chose for its own different question — would refuse the documented pattern. The cap sits one
# rung beyond the deepest sanctioned shape, which is the narrowest place it can sit without
# deleting a capability (memory `guard-universalization-deletes-a-capability-silently`).
#
# FAIL OPEN, NEVER SILENTLY. Every path that cannot decide ADMITS and writes one IDL row carrying a
# distinct `basis`, so "unstamped" and "could not read the stamp" are never the same value (memory
# `sensor-default-off-makes-blindness-the-shipping-path`). A refusal here is only ever produced by
# a stamp this library itself wrote and could parse.

CC_LINEAGE_ROOT_CUR=""
CC_LINEAGE_GEN_CUR=0
CC_LINEAGE_BASIS="unresolved"
CC_LINEAGE_REASON=""

cc_lineage_root()   { printf '%s' "${CC_LINEAGE_ROOT_CUR:-}"; }
cc_lineage_gen()    { printf '%s' "${CC_LINEAGE_GEN_CUR:-0}"; }
cc_lineage_basis()  { printf '%s' "${CC_LINEAGE_BASIS:-unresolved}"; }
cc_lineage_reason() { printf '%s' "${CC_LINEAGE_REASON:-}"; }

cc_lineage_idl_path() { printf '%s' "${CC_LINEAGE_IDL:-${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}}"; }

# One row per return path. jq-built, never %s-interpolated (the malformed-JSON class).
_cc_lineage_emit() { # <verdict> <disposition> <caller> <what> <detail>
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
         --arg v "$1" --arg disp "$2" --arg caller "$3" --arg what "$4" --arg d "$5" \
         --arg root "${CC_LINEAGE_ROOT_CUR:-}" --arg b "${CC_LINEAGE_BASIS:-unresolved}" \
         --arg sid "${CC_LINEAGE_SID:-?}" --argjson gen "${CC_LINEAGE_GEN_CUR:-0}" \
    '{ts:$ts,hook:"spawn-lineage",sid:$sid,disposition:$disp,reason:"spawn-lineage",
      gate:"spawn-lineage",verdict:$v,basis:$b,caller:$caller,what:$what,
      root:$root,gen:$gen,detail:$d}' \
    >> "$(cc_lineage_idl_path)" 2>/dev/null || true
}

# The nearest `claude` ancestor's pid — the only STABLE per-session token available to a shim that
# never sees the hook payload. Deliberately not $PPID: the caller may be several forks deep
# (bash > it2 > it2-kitty). Mirrors the walk in worker-claim-gate.sh rather than sourcing it, so
# this library has no dependency on the lease being reachable; both are bounded, ps-only walks.
_cc_lineage_ancestor_pid() {
  local p="${1:-$$}" hops=0 comm parent
  while [ "$hops" -lt 12 ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    comm="$(ps -o comm= -p "$p" 2>/dev/null | tr -d ' ')"
    case "${comm##*/}" in claude|claude.exe|claude-*) printf '%s' "$p"; return 0 ;; esac
    parent="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$parent" in ''|*[!0-9]*) break ;; esac
    p="$parent"; hops=$((hops + 1))
  done
  return 1
}

# Resolve THIS process's lineage. Inherit when stamped; mint from the session's claude pid when not.
# Both sites (the stamp in bin/it2-kitty, the bound in hooks/validate-bash.sh) call this, so a
# gen-0 desk and its whole subtree agree on one root without anything having stamped the desk.
cc_lineage_resolve() {
  local raw_root="${CC_SPAWN_ROOT:-}" raw_gen="${CC_SPAWN_GEN:-}" anc

  case "$raw_gen" in
    '')            CC_LINEAGE_GEN_CUR=0; CC_LINEAGE_BASIS="unstamped" ;;
    *[!0-9]*)      CC_LINEAGE_GEN_CUR=0; CC_LINEAGE_BASIS="gen-unparseable" ;;
    *)             CC_LINEAGE_GEN_CUR="$raw_gen"; CC_LINEAGE_BASIS="stamped" ;;
  esac
  # A generation far past any real ladder is corruption, not a deep tree. Refusing on it would turn
  # one bad value into a permanent fleet-wide wall, so it reads as unknown and ADMITS.
  if [ "$CC_LINEAGE_GEN_CUR" -gt 64 ] 2>/dev/null; then
    CC_LINEAGE_GEN_CUR=0; CC_LINEAGE_BASIS="gen-implausible"
  fi

  case "$raw_root" in
    p[0-9]*|u[0-9]*) CC_LINEAGE_ROOT_CUR="$raw_root" ;;
    '')              CC_LINEAGE_ROOT_CUR="" ;;
    *)               CC_LINEAGE_ROOT_CUR=""; CC_LINEAGE_BASIS="root-unparseable" ;;
  esac

  if [ -z "$CC_LINEAGE_ROOT_CUR" ]; then
    if anc="$(_cc_lineage_ancestor_pid "$$")"; then
      CC_LINEAGE_ROOT_CUR="p$anc"
    else
      # No claude ancestor (a launchd job, a bare shell, a test). Still give it an identity so the
      # counter has a key; `u` marks it as un-attributed rather than pretending it is a session.
      CC_LINEAGE_ROOT_CUR="u$$"
      [ "$CC_LINEAGE_BASIS" = "unstamped" ] && CC_LINEAGE_BASIS="root-fallback"
    fi
  fi
  return 0
}

# The argv a kitty launch must carry so the CHILD inherits this lineage one generation deeper.
# One token per line: the caller reads it into an array, so no value has to survive a round of
# shell word-splitting (the Bash-tool shell is zsh, which does not word-split unquoted expansions —
# memory `interactive-grep-is-ugrep-not-usr-bin-grep`).
cc_lineage_child_env() {
  cc_lineage_resolve
  printf -- '--env\n'
  printf -- 'CC_SPAWN_ROOT=%s\n' "$CC_LINEAGE_ROOT_CUR"
  printf -- '--env\n'
  printf -- 'CC_SPAWN_GEN=%s\n' "$((CC_LINEAGE_GEN_CUR + 1))"
}

# 0 ADMIT / 9 REFUSE. Charges the per-root width counter on every admitted spawn (record-only).
cc_lineage_admit() { # $1=caller $2=sid $3=what
  local caller="${1:-unknown}" what="${3:-pane spawn}" cap state key n
  CC_LINEAGE_SID="${2:-?}"
  CC_LINEAGE_REASON=""

  cc_lineage_resolve

  if [ "${CC_LINEAGE_GATE:-on}" = off ]; then
    _cc_lineage_emit admit admitted "$caller" "$what" "gate-off"; return 0
  fi

  cap="${CC_LINEAGE_MAX_GEN:-3}"
  case "$cap" in ''|*[!0-9]*) cap=3 ;; esac   # unreadable configuration ADMITS, never refuses

  # Width: counted, never enforced. See the header — the bands are not separated yet.
  state="${CC_LINEAGE_STATE_DIR:-$HOME/.claude/autonomy/spawn-lineage}"
  n=0
  if mkdir -p "$state" 2>/dev/null; then
    find "$state" -name '*.count' -type f -mtime +7 -delete 2>/dev/null || true
    key="$(printf '%s' "$CC_LINEAGE_ROOT_CUR" | tr -c 'A-Za-z0-9._-' '_')"
    if [ -n "$key" ]; then
      [ -f "$state/$key.count" ] && n="$(cat "$state/$key.count" 2>/dev/null)"
      case "$n" in ''|*[!0-9]*) n=0 ;; esac
      n=$((n + 1))
      printf '%s\n' "$n" > "$state/$key.count" 2>/dev/null || true
    fi
  fi

  # Only a stamp this library wrote and could parse may produce a refusal.
  if [ "$CC_LINEAGE_BASIS" = "stamped" ] && [ "$CC_LINEAGE_GEN_CUR" -ge "$cap" ] 2>/dev/null; then
    CC_LINEAGE_REASON="generation $CC_LINEAGE_GEN_CUR is at/over the cap of $cap (root $CC_LINEAGE_ROOT_CUR, $n spawns charged to it)"
    _cc_lineage_emit refuse refused "$caller" "$what" "gen $CC_LINEAGE_GEN_CUR >= cap $cap width $n"
    return 9
  fi

  _cc_lineage_emit admit admitted "$caller" "$what" "gen $CC_LINEAGE_GEN_CUR/$cap width $n"
  return 0
}
