#!/bin/bash
# lr-composer-snapshot.sh — keep the raw screen of a pane whose draft held a recovery (D6.7).
#
# LIMIT_RECOVER_FLEET_V2 W6b, ruling 6: draft stash stays off, so the only record of an operator's
# unsent draft at the moment a recovery refused to touch it is what THIS file writes. Until now the
# one writer was bin/it2-kitty's close guard, which saves `get-text` PLAIN, and at least 8 historical
# holds survive only as '<unreadable>'. Plain text also loses the one attribute that separates a
# draft from Claude Code's own faint prompt suggestion (SGR 2), so the ANSI rendering is what is kept.
#
# IT TYPES NOTHING. Every call is a read (`kitty @ get-text --ansi`), bounded by cc-tui's transport,
# and a failure writes nothing and says so — a hold must never become a keystroke because a snapshot
# could not be taken.
#
# Sourceable (functions below) and executable (CLI at the bottom), so the Python reconciler can call
# it for its HOLD-DRAFT substate with a plain argv:
#   lr-composer-snapshot.sh snap <pane> <sid> <reason> [--focused 0|1] [--limited 0|1]
#       → the .ansi path on stdout, rc 0 · rc 1 nothing captured (no transport, bad id, empty read)
#   lr-composer-snapshot.sh row <file.ansi>
#       → the de-fainted composer rows, spaces and non-ASCII KEPT, one per line; rc 1 no input box
#   lr-composer-snapshot.sh count
#       → the revisit counter: genuine one-line drafts in unfocused limited panes (see lcs_count)
# Store: $LR_COMPOSER_SNAP_DIR, default ~/.claude/logs/composer-snapshots/, plus index.jsonl there.

LCS_DIR_DEFAULT="${HOME:-}/.claude/logs/composer-snapshots"

_lcs_dir() { printf '%s' "${LR_COMPOSER_SNAP_DIR:-$LCS_DIR_DEFAULT}"; }

# cc-tui.sh is the transport (socket authority, bounded RPC, id validation). Resolved beside this
# file first, then the live layer, like every other sibling library here.
_lcs_load_tui() {
  local here c
  command -v cc_tui_rpc >/dev/null 2>&1 && return 0
  here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" 2>/dev/null && pwd)"
  for c in "${LCS_CC_TUI:-}" "$here/cc-tui.sh" "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/cc-tui.sh" "${HOME:-}/.claude/scripts/lib/cc-tui.sh"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    # shellcheck disable=SC1090  # runtime-resolved sibling
    . "$c" 2>/dev/null && command -v cc_tui_rpc >/dev/null 2>&1 && return 0
  done
  return 1
}

# The composer rows of an --ansi screen: the text between the LAST TWO full-width border rows (the
# parse cc-tui.sh and handoff-fire.sh already share), FAINT runs dropped (CC's suggestion text is
# SGR 2; typed input never is), escapes stripped. Unlike cc_tui_composer it does NOT drop non-ASCII
# and does NOT collapse spaces: this is what the operator wrote, quoted to them in a page, and a
# draft in any script is still a draft (D6.8's hole, from the reading side). Only the known chrome
# goes: the leading ❯ prompt glyph and U+00A0. Trailing blanks and blank rows are trimmed.
lcs_draft_rows() { # $1=file with the --ansi screen → rows on stdout; rc 0 parsed · 1 no input box
  local f="${1:-}" span rc b12='────────────'
  [ -f "$f" ] || return 1
  span="$(LC_ALL=C perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)?|\e.//g' "$f" | LC_ALL=C awk -v b="$b12" -v u='─' '
    function border(s,   t) {                 # a full rule, or a LABELED one: "── label ─" from column 0
      if (index(s, b) > 0) return 1
      t = s; sub(/[ \t\r]+$/, "", t)
      return (index(t, u u) == 1 && length(t) > 3 * length(u) && substr(t, length(t) - length(u) + 1) == u)
    }
    { if (border($0)) { b2 = b1; b1 = NR } }
    END { if (b1 == 0 || b2 == 0 || b1 - b2 < 2) exit 9; print (b2 + 1) "," (b1 - 1) }')" && rc=0 || rc=$?
  [ "$rc" = 0 ] || return 1
  LC_ALL=C sed -n "${span}p" "$f" | LC_ALL=C perl -ne '
    my ($d, $o) = (0, "");
    while (/\G(?:\e\[([0-9;:]*)m|\e\[[0-?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)?|\e.|([^\e]))/gcs) {
      if (defined $1) {
        my @p = split /;/, $1, -1; @p = ("") unless @p;
        for (my $i = 0; $i < @p; $i++) {
          my ($c) = split /:/, $p[$i], 2; $c = "" unless defined $c;
          if ($c eq "" || $c eq "0" || $c eq "22") { $d = 0 }
          elsif ($c eq "2") { $d = 1 }
          elsif ($c =~ /^[345]8$/ && $p[$i] !~ /:/) {
            my $m = defined $p[$i + 1] ? $p[$i + 1] : "";
            $i += $m eq "5" ? 2 : $m eq "2" ? 4 : 0;
          }
        }
      } elsif (defined $2) { $o .= $2 unless $d }
    }
    $o =~ s/\xc2\xa0/ /g;                 # U+00A0 is chrome, rendered as a space
    $o =~ s/^\s*\xe2\x9d\xaf\s?//;        # the leading prompt glyph (U+276F) and its one space
    $o =~ s/[\r\n]+$//; $o =~ s/\s+$//;
    print "$o\n" if length $o;'
  return 0
}

# snap <pane> <sid> <reason> [--focused 0|1] [--limited 0|1] → path on stdout · rc 1 nothing captured
lcs_snap() {
  local pane="${1:-}" sid="${2:-}" reason="${3:-hold}" focused="" limited="" dir f ts rows n=0
  shift 3 2>/dev/null || true
  while [ $# -gt 0 ]; do
    case "$1" in --focused) focused="${2:-}"; shift 2 ;; --limited) limited="${2:-}"; shift 2 ;; *) shift ;; esac
  done
  case "$pane" in ''|*[!0-9]*) echo "lr-composer-snapshot: pane '$pane' is not a kitty window id — nothing captured" >&2; return 1 ;; esac
  _lcs_load_tui || { echo "lr-composer-snapshot: scripts/lib/cc-tui.sh unreachable — nothing captured" >&2; return 1; }
  dir="$(_lcs_dir)"; mkdir -p "$dir" 2>/dev/null || { echo "lr-composer-snapshot: cannot create $dir" >&2; return 1; }
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  reason="$(printf '%s' "$reason" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
  f="$dir/$ts-win$pane-${sid:0:8}-$reason.ansi"
  if ! cc_tui_rpc get-text --match "id:$pane" --extent screen --ansi > "$f" 2>/dev/null || [ ! -s "$f" ]; then
    rm -f "$f" 2>/dev/null
    echo "lr-composer-snapshot: get-text --ansi of pane $pane returned nothing — nothing captured" >&2
    return 1
  fi
  rows="$(lcs_draft_rows "$f" 2>/dev/null || true)"
  [ -n "$rows" ] && n="$(printf '%s\n' "$rows" | grep -c .)"
  # ONE JSONL row per capture, the revisit counter's population. jq builds it so a draft's quotes
  # and bytes cannot re-shape the record.
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg pane "$pane" --arg sid "$sid" --arg reason "$reason" --arg file "$f" \
          --argjson rows "$n" --arg focused "$focused" --arg limited "$limited" --arg row "${rows%%$'\n'*}" \
      '{ts:$ts, pane:$pane, sid:$sid, reason:$reason, file:$file, rows:$rows,
        focused:$focused, limited:$limited, first_row:$row}' >> "$dir/index.jsonl" 2>/dev/null || true
  fi
  printf '%s\n' "$f"
}

# THE REVISIT COUNTER (D6.7 / resolution 7). Decision 6 reopens at 3 or more: genuine ONE-line drafts
# in UNFOCUSED, LIMITED panes. Multi-line drafts, focused panes, hints (no row after de-fainting) and
# stray keystrokes (reason names them) do not count, and a capture whose focus or limit was not
# recorded does not count either — an unknown is not a qualifying case.
lcs_count() {
  local idx; idx="$(_lcs_dir)/index.jsonl"
  [ -f "$idx" ] || { echo 0; return 0; }
  jq -s '[ .[] | select(.rows == 1 and .focused == "0" and .limited == "1"
                        and ((.reason // "") | test("stray"; "i") | not)) ] | length' "$idx" 2>/dev/null || echo 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    snap)  shift; lcs_snap "$@" ;;
    row)   shift; lcs_draft_rows "$@" ;;
    count) lcs_count ;;
    *) echo "usage: lr-composer-snapshot.sh snap <pane> <sid> <reason> [--focused 0|1] [--limited 0|1] | row <file> | count" >&2; exit 2 ;;
  esac
fi
