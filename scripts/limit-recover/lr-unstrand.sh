#!/bin/bash
# lr-unstrand.sh --sid <sid> [--dry-run] — the remedy for a STRANDED tombstone, in the SAME pane
# (lr-wake 2026-10-18, h defect 5; Wave G).
#
# THE STATE. A transplant wrote <sid>.HANDOFF.json and renamed the source transcript .handed-off,
# the successor never started (its copy gained no bytes), and the old process still sits in its
# pane, where the handed-off guard refuses every prompt. 3e929a81 sat like that in pane 23 for ~10 h
# while a drain, the poller and a reconciler cohort each re-drove it. The reconciler names the state
# (lr_recon census.stranded_tombstone, event `stranded-tombstone`) and pages once with this command.
#
# THE REMEDY is the one that worked by hand: `/exit` (no background work, so no modal), then
# `lr-fire-resume.sh <target> <cwd> <sid>` typed into the SAME pane's shell. Never a recycle, never a
# new pane. Every precondition is re-read here from disk and the pane, and any doubt refuses with
# nothing typed:
#   rc 0  done (or --dry-run: the plan printed, nothing typed)
#   rc 2  usage
#   rc 3  not this state: no tombstone, the successor wrote bytes, it is not quiet long enough, a
#         live copy runs on the target, no old process in a pane, or the pane's root is not a shell
#         (an /exit there would close the pane)
#   rc 4  another driver holds runs/by-sid/<sid>.active
#   rc 6  REFUSED: background work, or a composer that is not provably empty (a draft, rail text,
#         an unreadable box or the bg-work modal). Nothing typed.
#   rc 7  /exit was sent but the old process did not end (a modal came up, or it timed out): the
#         modal is NOT answered here; it is paged.
#
# Seams (tests): CC_REGISTRY_DIR · LR_STATE_DIR · LRU_PS_SNAPSHOT · LR_UNSTRAND_TUI_LIB ·
# LR_UNSTRAND_FIRE_RESUME · LR_STRANDED_QUIET_S (600) · LR_UNSTRAND_EXIT_WAIT_S (60) ·
# LR_UNSTRAND_CFG_DIRS (newline list; default lr_config_dirs). bash 3.2-safe.
set -uo pipefail

SID="" DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sid) SID="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "lr-unstrand: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$SID" in ''|*/*|*' '*) echo "usage: lr-unstrand.sh --sid <sid> [--dry-run]" >&2; exit 2 ;; esac

LR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$LR/lr-lib.sh"
# shellcheck source=/dev/null
. "$LR/lr-upgrade.sh"   # source-only: lru_snapshot · lru_bg_kind · lru_composer · lru_unreadable_disp
TUI_LIB="${LR_UNSTRAND_TUI_LIB:-$LR/../lib/cc-tui.sh}"
# shellcheck disable=SC2034  # read by lr-upgrade.sh's lru_composer / lru_unreadable_disp
LRU_TUI_LIB="$TUI_LIB" LRU_COMPOSER=on
FIRE="${LR_UNSTRAND_FIRE_RESUME:-$LR/lr-fire-resume.sh}"
STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
REG="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
QUIET="${LR_STRANDED_QUIET_S:-600}"; case "$QUIET" in ''|*[!0-9]*) QUIET=600 ;; esac

say() { printf 'lr-unstrand: %s %s\n' "${SID:0:8}" "$*"; }
refuse() { say "REFUSED — $2; nothing typed"; exit "$1"; }
epoch() { # ISO-8601 Z → epoch (BSD date, then GNU)
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || date -u -d "$1" +%s 2>/dev/null
}
fsize() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null; }
fmtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
key() { (cd "${1%/}/projects" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# 1. The tombstone, in a store it does not hand off to.
dirs="${LR_UNSTRAND_CFG_DIRS:-$(lr_config_dirs 2>/dev/null)}"
TOMB="" SRC="" TO=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  for f in "$c"/projects/*/"$SID".HANDOFF.json; do
    [ -f "$f" ] || continue
    t="$(jq -r '.handed_off_to // empty' "$f" 2>/dev/null)"
    [ -n "$t" ] && [ "$(key "$t")" != "$(key "$c")" ] || continue
    TOMB="$f" SRC="$c" TO="$t"; break 2
  done
done <<EOF
$dirs
EOF
[ -n "$TOMB" ] || refuse 3 "no handed-off tombstone names this session"
TS="$(jq -r '.ts // empty' "$TOMB")"; TS_E="$(epoch "$TS")"
SUCC="$(jq -r '.target_transcript // empty' "$TOMB")"; CONFIRM="$(jq -r '.confirm_len // empty' "$TOMB")"
[ -f "$SUCC" ] || for SUCC in "$TO"/projects/*/"$SID".jsonl; do [ -f "$SUCC" ] && break; SUCC=""; done
[ -n "$TS_E" ] && [ -n "$SUCC" ] || refuse 3 "the tombstone names no time or no successor copy"
now="$(date +%s)"
[ $(( now - TS_E )) -ge "$QUIET" ] || refuse 3 "handed off ${TS}, under ${QUIET}s ago; the successor may still be starting"
case "$CONFIRM" in ''|*[!0-9]*) ;; *) [ "$(fsize "$SUCC")" -le "$CONFIRM" ] || refuse 3 "the successor copy grew past the confirmed $CONFIRM bytes: it ran" ;; esac
[ "$(fmtime "$SUCC")" -le $(( TS_E + 5 )) ] || refuse 3 "the successor copy was written after the handoff: it ran"

# 2. The old process, in a pane, on the source; and no live copy on the target.
src_acct="$(basename "${SRC%/}")"; src_acct="${src_acct#.}"; to_acct="$(basename "${TO%/}")"; to_acct="${to_acct#.}"
PANE="" PID="" SOCK="" CWD=""
for f in "$REG"/*.json; do
  [ -f "$f" ] || continue
  [ "$(jq -r '.session_id // empty' "$f" 2>/dev/null)" = "$SID" ] || continue
  a="$(jq -r '.account // empty' "$f" 2>/dev/null)"; p="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
  case "$p" in ''|*[!0-9]*) continue ;; esac
  kill -0 "$p" 2>/dev/null || continue
  [ "$a" != "$to_acct" ] || refuse 3 "a live copy runs on $to_acct (pid $p): it is not stranded"
  [ "$a" = "$src_acct" ] || continue
  PANE="$(jq -r '.paneUUID // empty' "$f")"; PID="$p"
  SOCK="$(jq -r '.kitty_listen_on // empty' "$f")"; CWD="$(jq -r '.cwd // empty' "$f")"
done
case "$PANE" in ''|*[!0-9]*)
  refuse 3 "no live old process of this session in a kitty pane on $src_acct (the in-pane remedy needs one; a dead session is cc-lr recover's)" ;; esac
[ -n "$CWD" ] && [ -d "$CWD" ] || refuse 3 "its cwd ($CWD) is not a directory"
parent="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"
pcomm="$(ps -o comm= -p "${parent:-0}" 2>/dev/null | tr -d ' ')"
case "${pcomm##*/}" in zsh|-zsh|bash|-bash|sh|-sh|fish|-fish) ;; *)
  refuse 3 "its pane's claude runs under '${pcomm:-?}', not a shell, so /exit would close the pane" ;; esac
[ -z "$SOCK" ] || export CC_TERM_KITTY_TO="$SOCK"

# 3. Background work and the composer, the two refusals that keep the exit modal away.
kind="$(lru_bg_kind "$(lru_snapshot)" "$PID")"
[ "$kind" = none ] || refuse 6 "it has background work ($kind): /exit would raise the 'Background work is running' modal"
crc=0; lru_composer "$PANE" || crc=$?
case "$crc" in
  0) [ -z "$LRU_COMPOSER_TEXT" ] || refuse 6 "its composer is not empty" ;;
  1|3) refuse 6 "its composer holds text (${#LRU_COMPOSER_TEXT} chars); it is never cleared from here" ;;
  *) refuse 6 "its composer could not be read ($(lru_unreadable_disp "$PANE"))" ;;
esac

# lr-fire-resume takes <account|cfg-dir>: the tombstone's own config dir is the unambiguous one.
RESUME="bash $(printf '%q' "$FIRE") $(printf '%q' "${TO%/}") $(printf '%q' "$CWD") $SID"
if [ -n "$DRY" ]; then
  say "PLAN pane $PANE pid $PID: /exit, then in the same pane: $RESUME (stranded since $TS, successor $(fsize "$SUCC") bytes)"
  exit 0
fi

# 4. One driver: the run claim, then the two keystroke steps.
CLAIMS="$STATE/runs/by-sid"
lr_claim_take "$CLAIMS" "$SID" lr-unstrand "$PANE" "$$" >/dev/null 2>&1 || refuse 4 "another driver holds runs/by-sid/$SID.active"
trap 'lr_claim_release "$CLAIMS" "$SID" "$$" >/dev/null 2>&1' EXIT
pl="$(mktemp "${TMPDIR:-/tmp}/lr-unstrand.XXXXXX")" || refuse 6 "no temp file"
printf '/exit' > "$pl"
# shellcheck source=/dev/null
. "$TUI_LIB"
src=0; cc_tui_submit "$PANE" "$pl" >/dev/null 2>&1 || src=$?
case "$src" in 0|5) ;; *) rm -f "$pl"; refuse 6 "/exit was not typed (cc_tui_submit rc $src)" ;; esac
deadline=$(( $(date +%s) + ${LR_UNSTRAND_EXIT_WAIT_S:-60} ))
while kill -0 "$PID" 2>/dev/null; do
  # shellcheck source=/dev/null  # LRU_MODAL_LIB is lr-upgrade.sh's seam
  if cc_tui_screen "$PANE" 2>/dev/null | ( . "$LRU_MODAL_LIB" >/dev/null 2>&1; pane_bgwork_dialog ); then
    rm -f "$pl"
    # shellcheck source=/dev/null
    ( . "$LR/lr-page-once.sh" && lr_page_once "unstrand-modal-$SID" unstrand \
        "pane $PANE ${SID:0:8}: /exit raised the bg-work modal; it is left for you (Stay keeps the work). Then: $RESUME" ) >/dev/null 2>&1
    say "HELD — /exit raised the bg-work modal; not answered, paged"; exit 7
  fi
  [ "$(date +%s)" -lt "$deadline" ] || { rm -f "$pl"; say "HELD — the old process (pid $PID) did not end within ${LR_UNSTRAND_EXIT_WAIT_S:-60}s of /exit"; exit 7; }
  sleep 1
done
sleep "${LR_UNSTRAND_SHELL_SETTLE_S:-2}"
printf '%s' "$RESUME" > "$pl"
cc_tui_type_keys "$PANE" "$pl" >/dev/null 2>&1 && cc_tui_cr "$PANE" >/dev/null 2>&1 \
  || { rm -f "$pl"; say "HELD — the old process exited, but the resume line could not be typed; run it in pane $PANE: $RESUME"; exit 7; }
rm -f "$pl"
say "RESUMED pane $PANE: /exit, then '$RESUME' typed into the same pane"
exit 0
