#!/bin/bash
# rotate-autonomy-logs.sh — size-gated rotation for the append-only autonomy/audit logs that
# grow UNBOUNDED (T-P10-2: idl.jsonl hit 183 MB live; bash-commands.log + bash-execution.log
# ~90 MB each). None of the writers cap their files, and every writer appends per-line via `>>`
# — lead-supervisor.sh:61, hooks/log-bash.sh, hooks/validate-bash.sh all open→write→close on
# EACH call, holding NO persistent fd — so the SAFE rotation is logrotate's `create` mode:
# rename the fat file aside, let the next `>>` recreate it in place (zero data loss, no writer
# signal, no C10 live-writer edit), gzip the rotated copy, and prune to a bounded history.
#
# Each run, for every target file whose size >= ROTATE_MAX_BYTES:
#   1. mv  <f>            -> <f>.<UTC-stamp>       (atomic same-dir rename)
#   2. recreate empty <f> IFF a racing writer has not already (never truncate a live line;
#      preserve the original file mode)
#   3. gzip <f>.<UTC-stamp> -> <f>.<UTC-stamp>.gz  (JSONL/audit text compresses ~10-20x)
#   4. prune: keep the newest ROTATE_KEEP <f>.* rotations, delete older
# Files under threshold are left untouched (idempotent — safe to run every tick). Exactly one
# summary IDL record is emitted per run (rotated >= 0), so "ran but rotated nothing" stays
# distinguishable from "never ran" (the autonomy-sweep B-3 convention).
#
# Targets: default = the three unbounded autonomy logs; override/extend via ROTATE_TARGETS
#   (whitespace/newline-separated absolute paths, no spaces WITHIN a path) or positional args.
#   A missing target is skipped, not an error (its writer may not have created it yet).
#
# Env (tests + ops): ROTATE_TARGETS · ROTATE_MAX_BYTES (default 26214400 = 25 MiB) ·
#   ROTATE_KEEP (default 8) · ROTATE_GZIP (default 1; 0 = leave rotated copy uncompressed) ·
#   CC_IDL (audit sink). BSD+GNU portable, no eval, fail-loud, shellcheck-clean. Always exits 0.
#
# NOTE: default targets + the audit sink hardcode $HOME/.claude — NOT $CLAUDE_CONFIG_DIR — because
# the writers do too (autonomy-sweep.sh, hooks/log-bash.sh: `$HOME/.claude/...`). A session that
# overrides CLAUDE_CONFIG_DIR (auth-isolation worktrees) must NOT redirect rotation off the real
# live logs; use ROTATE_TARGETS to point elsewhere explicitly.
set -uo pipefail

MAX_BYTES="${ROTATE_MAX_BYTES:-26214400}"
KEEP="${ROTATE_KEEP:-8}"
DO_GZIP="${ROTATE_GZIP:-1}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%SZ; }

# portable byte size (0 when absent) — wc -c dodges BSD/GNU stat-format divergence
filesize() { # <path>
  [ -f "$1" ] || { printf '0'; return 0; }
  wc -c < "$1" | tr -d ' '
}

# portable octal mode — BSD stat first, GNU stat next, 644 fallback
filemode() { # <path>
  local m
  m="$(stat -f '%Lp' "$1" 2>/dev/null)" || m=""
  [ -n "$m" ] || m="$(stat -c '%a' "$1" 2>/dev/null)" || m=""
  [ -n "$m" ] || m="644"
  printf '%s' "$m"
}

rotated=0
skipped=0
summary=""

# prune <path>: keep newest KEEP rotations (<path>.*), delete older. Timestamps are fixed-width
# and lexically sortable, so reverse name-sort == newest-first (a trailing .gz sorts after its
# stamp, preserving order). Runs in the current shell (here-string, not a pipe) so the counter sticks.
prune_one() { # <path>
  local f="$1" listing i=0 g
  local -a arr=()
  for g in "$f".*; do [ -e "$g" ] && arr+=("$g"); done
  [ "${#arr[@]}" -le "$KEEP" ] && return 0
  listing="$(printf '%s\n' "${arr[@]}" | sort -r)"
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    i=$((i + 1))
    [ "$i" -le "$KEEP" ] && continue
    rm -f "$g" 2>/dev/null || true
  done <<EOF
$listing
EOF
}

rotate_one() { # <path>
  local f="$1" sz stamp mode
  sz="$(filesize "$f")"
  if [ "$sz" -lt "$MAX_BYTES" ]; then
    skipped=$((skipped + 1))
    return 0
  fi
  stamp="$(now_stamp)"
  mode="$(filemode "$f")"
  # 1. atomic same-dir rename — the fat file is captured; the path is now free
  if ! mv "$f" "$f.$stamp" 2>/dev/null; then
    echo "rotate-autonomy-logs: mv failed for $f — skipping" >&2
    skipped=$((skipped + 1))
    return 0
  fi
  # 2. recreate in place ONLY if a racing writer has not — never truncate a just-written line
  if [ ! -e "$f" ]; then
    : > "$f" 2>/dev/null || true
    chmod "$mode" "$f" 2>/dev/null || true
  fi
  # 3. compress the rotated copy (best-effort; a gzip miss leaves the plain rotation, still pruned)
  if [ "$DO_GZIP" = "1" ] && command -v gzip >/dev/null 2>&1; then
    gzip -f "$f.$stamp" 2>/dev/null || echo "rotate-autonomy-logs: gzip failed for $f.$stamp (left plain)" >&2
  fi
  rotated=$((rotated + 1))
  [ -n "$summary" ] && summary="$summary,"
  summary="$summary{\"file\":\"$(basename "$f")\",\"bytes\":$sz}"
  # 4. bound the history
  prune_one "$f"
}

log_idl() { # <extra-json-fragment>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"rotate-autonomy-logs","rotated":%d,"skipped":%d,"max_bytes":%d,"keep":%d%s}\n' \
    "$(now_iso)" "$rotated" "$skipped" "$MAX_BYTES" "$KEEP" "${1:-}" \
    >> "$IDL" 2>/dev/null || true
}

# ── resolve the target list: positional args > ROTATE_TARGETS > the three defaults ──
DEFAULT_TARGETS="$HOME/.claude/autonomy/idl.jsonl
$HOME/.claude/logs/bash-commands.log
$HOME/.claude/logs/bash-execution.log"

TARGETS=()
if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  while IFS= read -r _line; do
    [ -n "$_line" ] && TARGETS+=("$_line")
  done <<EOF
$(printf '%s' "${ROTATE_TARGETS:-$DEFAULT_TARGETS}" | tr '[:blank:]' '\n')
EOF
fi

for _t in "${TARGETS[@]}"; do
  [ -n "$_t" ] && rotate_one "$_t"
done

# One audit record per run (lands in the freshly-recreated idl.jsonl when idl was a rotated target).
extra=""
[ -n "$summary" ] && extra=",\"files\":[$summary]"
log_idl "$extra"

echo "rotate-autonomy-logs: rotated=$rotated skipped=$skipped (max=${MAX_BYTES}B keep=$KEEP)"
exit 0
