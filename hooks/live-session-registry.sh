#!/bin/bash
# live-session-registry.sh — durable per-worktree liveness registry for worktree-gc.
#
# WHY: the reaper's cwd/lsof liveness scan is flaky — live `claude` procs routinely
# report cwd=/ (verified 2026-06-19), so a single bad pass made a LIVE session's
# worktree look dead and it was reaped (project-worktree-gc-event-driven-2026-06-18).
# This records a POSITIVE, durable signal: the session's `claude`-ancestor PID. The
# reaper keeps any worktree whose registry PID is alive (`kill -0`) — deterministic,
# independent of cwd/lsof timing. Crash-safe: a dead PID is swept by kill -0, so a
# session that dies without SessionEnd self-heals (entry goes stale → ignored/removed).
#
# Wired on SessionStart (register) + SessionEnd (unregister) in ~/.claude/settings.json.
# Scope: only ~/Development/.worktrees/* (the reaper's reapable domain). Global (not
# project) so it is live for EVERY session immediately — no per-worktree-checkout lag.
# Fail-safe: never blocks the session (always exit 0). bash 3.2-safe.
REG_DIR="$HOME/.reso/live-sessions"
input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

ev=$(printf '%s' "$input"  | jq -r '.hook_event_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty'            2>/dev/null)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty'     2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# Only sessions sitting in a reapable worktree matter.
case "$cwd" in
  "$HOME/Development/.worktrees/"*) ;;
  *) exit 0 ;;
esac
base=$(basename "$cwd")
mkdir -p "$REG_DIR" 2>/dev/null

if [ "$ev" = "SessionEnd" ]; then
  # Only remove if it's ours (basename is unique per worktree, but match sid to be safe).
  if [ -f "$REG_DIR/$base" ]; then
    have=$(cut -f2 "$REG_DIR/$base" 2>/dev/null)
    { [ -z "$sid" ] || [ "$have" = "$sid" ]; } && rm -f "$REG_DIR/$base" 2>/dev/null
  fi
  exit 0
fi

# Register (SessionStart / Resume / Clear — anything non-End): walk up to the durable
# `claude` ancestor PID (NOT the /bin/sh hook shim — the teammate-lifecycle $PPID lesson).
pid="$PPID"; cpid=""; i=0
while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
  c=$(ps -o comm= -p "$pid" 2>/dev/null); c="${c##*/}"
  case "$c" in
    claude|claude.exe|claude-*) cpid="$pid"; break ;;
  esac
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  i=$((i + 1))
done
[ -z "$cpid" ] && cpid="$PPID"   # fallback: still a live descendant anchor

# ── TENANCY GATE: a cwd is not a tenancy either (backlog 55e1e65c7548) ─────────────────────────
# Same defect as session-register.sh's pane row, one key over: a nested `claude` (a `claude -p`
# probe, an upgrade-gate check, any script that shells out to the CLI) inherits the session's CWD,
# so it lands on the SAME worktree row and — until this gate — wrote its own pid over the tenant's.
# Measured 2026-08-08 with a fixtured $HOME and a two-tier ancestry: row pid 94327 (alive) became
# 94337, dead before the probe returned.
#
# That is worse here than it looks, because this row is a POSITIVE proof and nothing else replaces
# it. worktree-gc.sh:361-372 `registry_live()` returns NOT-LIVE on a dead pid, so the worktree falls
# back to the cwd/lsof oracle — the flakiness this file's header says it exists to eliminate ("live
# `claude` procs routinely report cwd=/ … a single bad pass made a LIVE session's worktree look dead
# and it was reaped"). One throwaway probe silently disarms the guard for the session that fired it.
#
# Refuse ONLY when the incumbent pid is a live ANCESTOR of ours: a nested claude got this cwd by
# inheriting it from the process that owns the worktree, so ancestry IS the proof the row is not
# ours. A live-but-unrelated pid (basename collision across the repos sharing ~/Development/
# .worktrees, or a recycled pid) is NOT an ancestor and still writes, so this cannot wedge a
# worktree — the failure mode the row exists to prevent, which a blunter test would re-create.
inc=""
if [ -f "$REG_DIR/$base" ]; then
  inc=$(cut -f1 "$REG_DIR/$base" 2>/dev/null)
  case "${inc:-}" in ''|*[!0-9]*) inc="" ;; esac
fi
if [ -n "$inc" ] && [ "$inc" != "$cpid" ] && kill -0 "$inc" 2>/dev/null; then
  walk=$(ps -o ppid= -p "$cpid" 2>/dev/null | tr -d ' '); i=0
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 16 ]; do
    if [ "$walk" = "$inc" ]; then
      # Journalled into the shared IDL so cc-digest/cc-discover's inert-gate census can see this
      # guard fire at all; a silent no-op is indistinguishable from a gate that never runs.
      idl="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
      mkdir -p "$(dirname "$idl")" 2>/dev/null || true
      jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
             --arg sid "${sid:-?}" --arg base "$base" --arg inc "$inc" \
        '{ts:$ts,hook:"live-session-registry",sid:$sid,disposition:"refused",
          reason:("worktree " + $base + " held by live ancestor pid " + $inc + " — nested session, not the tenant")}' \
        >> "$idl" 2>/dev/null || true
      exit 0
    fi
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
fi

# ATOMIC (tmp+mv), never `> "$REG_DIR/$base"` directly. `>` is O_TRUNC — the file is emptied by one
# syscall and refilled by a later one, so a reader landing in that gap sees ZERO bytes. That reader is
# worktree-gc: it `cut -f2`s an empty file → empty pid → `kill -0 ""` fails → this LIVE session's
# worktree reads as dead and is REAPED. That is precisely the single-bad-read flakiness the header
# above says this file exists to eliminate, re-introduced at one-printf width by the write itself.
# `mv` within a directory is an atomic rename: a reader sees either the old row or the new one, never
# a partial. Matches the sibling writers (session-register.sh:81, cc-decide) — this was the ONE
# non-atomic shared write left in the repo (a15/D5). Fail-safe: on a write failure the mv is skipped
# and the PREVIOUS row survives, which is strictly better than a truncated one; tmp is cleaned either way.
_tmp="$REG_DIR/.$base.$$"
if printf '%s\t%s\t%s\n' "$cpid" "$sid" "$cwd" > "$_tmp" 2>/dev/null; then
  mv -f "$_tmp" "$REG_DIR/$base" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
else
  rm -f "$_tmp" 2>/dev/null
fi
exit 0
