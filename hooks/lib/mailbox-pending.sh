#!/bin/bash
# mailbox-pending.sh — shared inbox-cursor predicates for the v2 non-keystroke comms channel.
#
# ONE cursor, ONE truth. A session's inbox is ~/.claude/mailbox/<uuid>.md (append-only, one
# message per line, written by cc-notify). Delivered-vs-pending is tracked by <uuid>.seen — a
# single integer LINE COUNT. This is the SAME cursor scripts/handoff-disposition.sh reads
# (mailbox_pending) and advances (--ack), so the drain hook and the disposition helper agree by
# construction. The line-count method here (grep -c '') is byte-identical to handoff-disposition's,
# so both compute the SAME cursor for the same file state — never drift them.
#
# Sourced by:
#   hooks/mailbox-drain.sh            — the delivery drain (SessionStart / UserPromptSubmit / Stop)
#   the Stop-blocker yield-guards     — so at most one Stop hook blocks when mail is pending
#
# Functions (all fail-safe: a missing uuid / dir / file → "no pending", never an error):
#   mailbox_file   <uuid>            → echo the .md path
#   mailbox_lines  <uuid>            → current line count of <uuid>.md (0 if absent)
#   mailbox_seen   <uuid>            → the .seen cursor, clamped to [0, lines] (0 if absent/garbage)
#   mailbox_pending_count <uuid>     → max(0, lines - seen)
#   mailbox_has_pending  <uuid>      → exit 0 iff pending_count > 0
#   mailbox_advance_seen <uuid> <n>  → write cursor n (atomic tmp+mv); n defaults to current lines
#   mailbox_mark_draining <uuid>     → touch the breadcrumb (call BEFORE advancing .seen on Stop)
#   mailbox_recently_drained <uuid>  → exit 0 iff breadcrumb younger than CC_DRAIN_BREADCRUMB_TTL
#   mailbox_defer_to_drain <uuid>    → exit 0 iff has_pending OR recently_drained (the yield predicate)
#
# Why the breadcrumb: on a Stop pass the drain advances .seen; another Stop-blocker checking
# "has_pending" AFTER that advance would see none and wrongly proceed to block too. The drain marks
# the breadcrumb BEFORE advancing, and blockers yield on "pending OR recently-drained", so the
# decision is order-independent under parallel hook execution and self-expires (TTL) after the pass.
#
# Env: CC_MAILBOX_DIR (default ~/.claude/mailbox) · CC_DRAIN_BREADCRUMB_TTL seconds (default 2).
# bash 3.2-safe. No `set -e` (sourced into hooks that must not inherit errexit).

_mbx_dir() { printf '%s' "${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"; }
_mbx_valid_uuid() { case "${1:-}" in ''|*[!0-9A-Fa-f-]*) return 1 ;; *) return 0 ;; esac; }

mailbox_file() { printf '%s/%s.md' "$(_mbx_dir)" "${1:-}"; }

# grep -c '' counts lines identically to handoff-disposition.sh (every line matches ''), and matches
# wc -l for files with a trailing newline — cc-notify always writes '…\n', so they never diverge.
mailbox_lines() {
  local u="${1:-}" f
  _mbx_valid_uuid "$u" || { echo 0; return; }
  f="$(mailbox_file "$u")"
  [ -f "$f" ] || { echo 0; return; }
  local n; n="$(grep -c '' "$f" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo "$n"
}

mailbox_seen() {
  local u="${1:-}" f seen lines
  _mbx_valid_uuid "$u" || { echo 0; return; }
  seen="$(_mbx_dir)/$u.seen"
  local p; p=0
  [ -f "$seen" ] && p="$(head -n1 "$seen" 2>/dev/null | tr -dc '0-9')"
  case "$p" in ''|*[!0-9]*) p=0 ;; esac
  # Clamp to [0, lines]: a cursor AHEAD of EOF (file rotated/truncated, or garbage) must never hide
  # real lines — treat as 0 so a regrown mailbox re-delivers rather than silently swallowing. Bias to
  # no-loss over a rare benign re-delivery (notifications are idempotent to read).
  lines="$(mailbox_lines "$u")"
  [ "$p" -gt "$lines" ] 2>/dev/null && p=0
  echo "$p"
}

mailbox_pending_count() {
  local u="${1:-}" lines seen
  lines="$(mailbox_lines "$u")"; seen="$(mailbox_seen "$u")"
  local d=$(( lines - seen ))
  [ "$d" -lt 0 ] && d=0
  echo "$d"
}

mailbox_has_pending() { [ "$(mailbox_pending_count "${1:-}")" -gt 0 ]; }

mailbox_advance_seen() {
  local u="${1:-}" n="${2:-}"
  _mbx_valid_uuid "$u" || return 0
  [ -n "$n" ] || n="$(mailbox_lines "$u")"
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  local dir seen tmp; dir="$(_mbx_dir)"; seen="$dir/$u.seen"
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$u.seen.$$.tmp"
  if printf '%s\n' "$n" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$seen" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

_mbx_breadcrumb() { printf '%s/.%s.draining' "$(_mbx_dir)" "${1:-}"; }

mailbox_mark_draining() {
  local u="${1:-}" bc
  _mbx_valid_uuid "$u" || return 0
  mkdir -p "$(_mbx_dir)" 2>/dev/null || return 0
  bc="$(_mbx_breadcrumb "$u")"
  : > "$bc" 2>/dev/null || true
}

mailbox_recently_drained() {
  local u="${1:-}" bc ttl mt now
  _mbx_valid_uuid "$u" || return 1
  bc="$(_mbx_breadcrumb "$u")"
  [ -f "$bc" ] || return 1
  ttl="${CC_DRAIN_BREADCRUMB_TTL:-2}"
  mt="$(stat -f %m "$bc" 2>/dev/null || stat -c %Y "$bc" 2>/dev/null || echo 0)"
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now - mt ))" -le "$ttl" ]
}

# The yield predicate the OTHER Stop hooks call: yield (exit 0) iff mail is pending OR the drain just
# fired this pass. Order-independent + self-expiring — see the breadcrumb note above.
mailbox_defer_to_drain() {
  local u="${1:-}"
  mailbox_has_pending "$u" && return 0
  mailbox_recently_drained "$u" && return 0
  return 1
}
