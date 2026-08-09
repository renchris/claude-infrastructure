#!/usr/bin/env bash
# gate-cleanup.sh — kill THIS worktree's stuck gate processes, and only this worktree's.
#
#   scripts/gate-cleanup.sh [--worktree <path>] [--dry-run] [--force] [--grace <s>] [--quiet]
#
# WHY THIS EXISTS (backlog a0718a5d78b3, measured 2026-07-26). Peer sessions were killing each
# other's landing gates with worktree-UNSCOPED patterns:
#
#     pkill -9 -f bats-core/bats          ← matches EVERY concurrent session's gate, machine-wide
#     pkill -f "ship-land.sh --trunk main"
#
# Every bats command line on this box contains `/libexec/bats-core/bats`, so those patterns are
# machine-wide by construction, not by accident. The desk's cross-session sweep tied victim gates
# to actor commands with a 3-5s lag twice over, across >=8 broad-pkill events in 5 sessions in 24h.
# The victims mis-read their own SIGKILL as an OOM/jetsam kill and propagated that wrong theory
# into their block reasons (jetsam was REFUTED: 68% memory free, zero memorystatus kills). Because
# ship-land reported a killed gate as "GATE RED" (fixed alongside this, see ship-land.sh exit 9),
# the kills became false convictions, which re-blocked items, which made the dispatcher retry,
# which raised load, which produced more kills — the 2026-07-26 runaway (f8e40b4c577d).
#
# SCOPE MODEL — two signals, unioned, so neither one's blind spot leaks:
#   (1) cwd containment — a process whose CWD is at/under the worktree. This is what makes the
#       scope REAL rather than textual: the worktree is a filesystem fact, and a `pkill -f <name>`
#       pattern is not (another worktree's path can contain your worktree's name as a substring).
#   (2) descendants of (1) — a bats test frequently `cd`s into its own BATS_TEST_TMPDIR (under
#       /tmp), so cwd alone MISSES the very children that hold the CPU. Ancestry recovers them,
#       and ancestry cannot escape the worktree because every root came from (1).
# A process matching neither is somebody else's and is never signalled, whatever its argv says.
#
# SELF-PRESERVATION: this script, its shell, and every ANCESTOR of it are excluded. Cleanup must
# never take out the session that ran it (a bare `pkill -f bats` run from inside a bats suite kills
# its own caller, which is one way the observed events cascaded).
#
# SIGNALS: TERM first, then KILL to survivors after --grace seconds (default 5). `--force` skips
# straight to KILL. `--dry-run` prints the selection and signals nothing — run it first when in
# doubt; the listing shows each pid's cwd so the scope claim is auditable, not asserted.
#
# Exit: 0 = ran (including "nothing to clean") · 2 = usage/precondition error.
# Env: CC_GATE_CLEANUP_PS (test seam — a `ps -eo pid=,ppid=,command=` substitute)
#      CC_GATE_CLEANUP_CWD (test seam — a `<pid>` → cwd resolver substitute)

set -uo pipefail

WORKTREE=""; DRY=0; FORCE=0; GRACE=5; QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --dry-run|-n) DRY=1; shift ;;
    --force|-9) FORCE=1; shift ;;
    --grace) GRACE="${2:-5}"; shift 2 ;;
    --quiet|-q) QUIET=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "✗ gate-cleanup: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$GRACE" in ''|*[!0-9]*) echo "✗ gate-cleanup: --grace wants integer seconds" >&2; exit 2 ;; esac

if [ -z "$WORKTREE" ]; then
  WORKTREE="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$WORKTREE" ] && { echo "✗ gate-cleanup: not inside a git worktree — pass --worktree <path>" >&2; exit 2; }
fi
[ -d "$WORKTREE" ] || { echo "✗ gate-cleanup: '$WORKTREE' is not a directory" >&2; exit 2; }
# Physical path: the containment test below is a string prefix, so a symlinked or /private-prefixed
# spelling of the same directory would silently match NOTHING (macOS /tmp → /private/tmp).
WORKTREE="$(cd "$WORKTREE" && pwd -P)"

say() { [ "$QUIET" = "1" ] || printf '%s\n' "$1" >&2; }

ps_all() {  # → "<pid> <ppid> <command…>" per line
  if [ -n "${CC_GATE_CLEANUP_PS:-}" ]; then "$CC_GATE_CLEANUP_PS"; else ps -eo pid=,ppid=,command=; fi
}

cwd_of() {  # <pid> → its cwd, or empty when unknowable (a process we may not inspect)
  if [ -n "${CC_GATE_CLEANUP_CWD:-}" ]; then "$CC_GATE_CLEANUP_CWD" "$1"; return 0; fi
  lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}

under_worktree() {  # <path> → 0 when at or under $WORKTREE
  case "$1" in "$WORKTREE") return 0 ;; "$WORKTREE"/*) return 0 ;; *) return 1 ;; esac
}

# ── exclusion set: self + every ancestor (never kill the hand holding the knife) ────────────────
PS_SNAPSHOT="$(ps_all)"
ppid_of() { printf '%s\n' "$PS_SNAPSHOT" | awk -v p="$1" '$1==p {print $2; exit}' || true; }
EXCLUDE=" $$ "
_a="$(ppid_of "$$")"
while [ -n "$_a" ] && [ "$_a" != "0" ] && [ "$_a" != "1" ]; do
  case "$EXCLUDE" in *" $_a "*) break ;; esac      # cycle guard: a malformed table must not spin
  EXCLUDE="$EXCLUDE$_a "
  _a="$(ppid_of "$_a")"
done
excluded() { case "$EXCLUDE" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── is_gate_exec: does this command line RUN a gate program (vs merely mention one)? ────────────
# ONLY the first two argv tokens are inspected, and only their BASENAME — `bash /x/y/ship-land.sh`
# and `./scripts/ship-land.sh` both qualify, `--flag ship-land.sh-something` does not.
# WHY SO STRICT: a substring match over the whole command line is exactly the defect this script
# exists to fix, one level up. A Claude session's argv embeds its entire task prompt, so a peer
# session whose brief merely NAMES `ship-land.sh` or `bats` matched a naive `case "$rest" in
# *ship-land.sh*)` — the first draft of this script selected a live peer's `claude` process for
# SIGKILL. That is the same family as `pgrep -f gate-runaway-loop` matching a session that only
# talks about the branch. Text is not evidence of execution.
is_gate_exec() {  # <command line> → 0 when it EXECUTES a gate program
  local t0 t1 b
  t0="${1%% *}"; t1="${1#* }"; t1="${t1%% *}"
  for b in "${t0##*/}" "${t1##*/}"; do
    case "$b" in
      bats|bats-exec-suite|bats-exec-file|bats-exec-test|bats-gather-tests|bats-preprocess|bats-format-*) return 0 ;;
      ship-land.sh|postland-verify.sh) return 0 ;;
    esac
  done
  return 1
}

# ── NEVER-SIGNAL: an interactive Claude session, whatever the selection says ────────────────────
# Belt-and-suspenders behind is_gate_exec. A session pane is never a gate process, and killing one
# is strictly worse than the runaway this script damps — it destroys unpersisted operator context.
# Applied to descendants too: this repo's own suites launch claude binaries in fixtures.
never_signal() {  # <command line> → 0 when this process must never be signalled
  local t0="${1%% *}"
  case "${t0##*/}" in claude|claude-*|node) return 0 ;; esac
  case "$1" in *"/node_modules/.bin/claude"*) return 0 ;; esac
  return 1
}

# ── (1) roots: gate processes whose OWN cwd is inside this worktree ─────────────────────────────
# Two independent conditions, both required: it must RUN a gate program (is_gate_exec) AND live in
# this worktree (cwd containment). Neither alone is a scope.
ROOTS=""
while read -r pid ppid rest; do
  [ -n "${pid:-}" ] || continue
  case "$pid" in ''|*[!0-9]*) continue ;; esac
  excluded "$pid" && continue
  is_gate_exec "$rest" || continue
  never_signal "$rest" && continue
  c="$(cwd_of "$pid")"
  [ -n "$c" ] || continue
  under_worktree "$c" && ROOTS="$ROOTS$pid "
done <<EOF
$PS_SNAPSHOT
EOF

# ── (2) closure: every descendant of a root, whatever its own cwd or argv ───────────────────────
# Iterate to a fixed point rather than recursing: bash 3.2, no arrays needed, and a process table
# that changes under us can only ever add children we then pick up on the next pass.
SELECTED="$ROOTS"
pass=0
while [ "$pass" -lt 12 ]; do
  pass=$(( pass + 1 )); added=0
  while read -r pid ppid rest; do
    [ -n "${pid:-}" ] || continue
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    excluded "$pid" && continue
    never_signal "$rest" && continue
    case " $SELECTED " in *" $pid "*) continue ;; esac
    case " $SELECTED " in *" $ppid "*) SELECTED="$SELECTED$pid "; added=1 ;; esac
  done <<EOF
$PS_SNAPSHOT
EOF
  [ "$added" = "0" ] && break
done

SELECTED="$(printf '%s' "$SELECTED" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
N="$(printf '%s' "$SELECTED" | tr ' ' '\n' | awk 'NF' | wc -l | tr -d ' ')"

if [ "$N" = "0" ]; then
  say "✓ gate-cleanup: nothing to clean — no gate processes in $WORKTREE"
  exit 0
fi

say "→ gate-cleanup: $N process(es) scoped to $WORKTREE"
for p in $SELECTED; do
  say "    $p  cwd=$(cwd_of "$p" || true)  $(printf '%s\n' "$PS_SNAPSHOT" | awk -v q="$p" '$1==q {$1="";$2="";sub(/^ +/,"");print substr($0,1,110); exit}')"
done

if [ "$DRY" = "1" ]; then
  say "→ gate-cleanup: --dry-run — nothing signalled"
  printf '%s' "$SELECTED" | tr ' ' '\n' | awk 'NF'      # stdout = the selection, one pid per line
  exit 0
fi

if [ "$FORCE" = "1" ]; then
  for p in $SELECTED; do kill -9 "$p" 2>/dev/null || true; done
  say "✓ gate-cleanup: SIGKILLed $N process(es)"
  exit 0
fi

for p in $SELECTED; do kill -TERM "$p" 2>/dev/null || true; done
say "→ gate-cleanup: SIGTERM sent; ${GRACE}s grace before SIGKILL"
[ "$GRACE" -gt 0 ] && sleep "$GRACE"
left=0
for p in $SELECTED; do
  if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null || true; left=$(( left + 1 )); fi
done
say "✓ gate-cleanup: $N TERMed, $left needed SIGKILL"
exit 0
