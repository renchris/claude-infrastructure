#!/usr/bin/env bash
# cc-tui.sh — type a prompt into a live Claude Code composer and PROVE it landed ON DISK.
# Source, do not execute. No side effects at load. bash 3.2 safe (launchd runs /bin/bash).
# LIMIT_RECOVER_100P W5-E. Design + measurements:
#   docs/research/lr100p-2026-09-19/research/U08-pane-transport.md §4 (the rc table is §4.3 verbatim)
#
# THE ENTRY POINT IS `cc_tui_submit <pane-id> <payload-file>` AND ITS RC IS THE CONTRACT:
#
#   rc 0  submitted AND a user record carrying the payload exists in the session transcript
#   rc 1  no such pane (provably absent), or the send itself failed
#   rc 2  ABSTAINED — composer unreadable / a blocking modal; NOTHING was typed
#   rc 3  HELD — the composer was occupied through the pre-wait (an operator draft); NOTHING typed
#   rc 4  MANGLED — read-back mismatch; the CR was NOT sent; the composer was scrubbed
#   rc 5  CR sent, no transcript record inside the window — CANNOT TELL (never "failed")
#
# WHY THE VERDICT IS A DISK READ AND NOT A SCREEN READ. A TUI screen is a SAMPLE, not a STATE
# (scripts/handoff-fire.sh:2871). The screen tier here decides exactly one thing — whether to press
# Enter — and is never the success oracle. The transcript is append-only ground truth, and the
# oracle is keyed on a BYTE OFFSET taken before the send, never on a timestamp: a timestamp
# baseline read off an empty/never-born store makes every record "after the prompt", which is the
# failure this project already carries as a lesson (a blank baseline acquits everything).
#
# WHAT THIS FILE DUPLICATES, DELIBERATELY. The composer parse, the read-back forms, the scrub loop
# and the residue receipt are COPIES of scripts/handoff-fire.sh:2585/2684/2735/2839, not moves.
# tests/handoff-composer-gate.bats:53-66 sed-extracts fourteen of those functions BY NAME out of
# handoff-fire.sh; relocating one would silently empty a 51-case suite. The duplication is the
# cheaper of the two defects and it is pinned: tests/cc-tui.bats asserts the parse agrees with
# handoff-fire's on the same fixture screens.
#
# WHAT IS NEW HERE, and it is the only genuinely new thing: the BYTE-OFFSET transcript oracle
# (cc_tui_record_after). `grep -rn 'tail -c +' scripts bin hooks` returned zero before this file.
#
# THERE IS NO KILL SWITCH ON THE EMPTINESS GATE OR ON THE SCRUB, and that is a decision, not an
# omission. handoff-fire.sh carries CC_FIRE_COMPOSER_GATE / CC_COMPOSER_SCRUB because both gates
# were retro-fitted onto a path that already had callers and needed an escape hatch. This entry
# point has no legacy caller to rescue, and its whole value is the proof: a caller that can turn
# the gate off gets a blind paste wearing a verified name, which is the 4h+ 2026-08-23 outage
# (handoff-fire.sh:2775-2782) with a better function name. Both defaults there also FAIL OPEN on a
# caller's ambient environment; lifted verbatim they would let any exported `off` disarm this.
# shellcheck shell=bash

[ -n "${CC_TUI_LIB_LOADED:-}" ] && return 0 2>/dev/null
CC_TUI_LIB_LOADED=1

# BASH_SOURCE with `pwd -P`, never $0: this file is SOURCED, and ~/.claude is a PER-FILE symlink
# farm over the checkout, so $0 is the caller and an unresolved dirname splits the sibling lookups
# (memory: symlinked-$0-splits-sibling-sources).
: "${CC_TUI_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"}"

# ── lr-lib.sh is the SOCKET AUTHORITY (lr-lib.sh:675 lr_kitty_socket, :691 lr_kitty_bin) ─────────
# Two spellings of one resolver is how sibling auditors end up disagreeing about one population, so
# this never re-derives the socket; it sources the owner when it can reach it and falls back to the
# same binaries that owner would have called. Sourcing is safe: lr-lib.sh declares no side effects
# at load and is idempotent (LR_LIB_LOADED).
_cc_tui_load_lr() {
  local c
  command -v lr_kitty_socket >/dev/null 2>&1 && return 0
  for c in "${CC_TUI_LR_LIB:-}" \
           "${CC_TUI_DIR}/../limit-recover/lr-lib.sh" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" \
           "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    # shellcheck disable=SC1090
    . "$c" 2>/dev/null && command -v lr_kitty_socket >/dev/null 2>&1 && return 0
  done
  return 1
}

cc_tui_socket() { # → the kitty control socket; rc 1 when none can be resolved
  local out c
  [ -n "${CC_TERM_KITTY_TO:-}" ] && { printf '%s' "$CC_TERM_KITTY_TO"; return 0; }
  if _cc_tui_load_lr; then out="$(lr_kitty_socket 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }; return 1; fi
  for c in "${CC_TUI_DIR}/../../bin/cc-kitty-socket" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-kitty-socket" "$HOME/.claude/bin/cc-kitty-socket"; do
    [ -x "$c" ] || continue
    out="$("$c" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  done
  return 1
}

cc_tui_kitty_bin() { # → the kitty binary; rc 1 when none
  local out c
  if _cc_tui_load_lr; then out="$(lr_kitty_bin 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }; fi
  for c in "${CC_TERM_KITTY:-}" "${CC_TUI_DIR}/../../bin/cc-kitty-bin" "$HOME/.claude/bin/cc-kitty-bin"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    case "$(basename "$c")" in
      cc-kitty-bin) out="$("$c" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; } ;;
      *) printf '%s' "$c"; return 0 ;;
    esac
  done
  command -v kitty >/dev/null 2>&1 && { printf 'kitty'; return 0; }
  return 1
}

_cc_tui_timeout_bin() {
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# EVERY kitty call goes through here, bounded, and its failure is INDETERMINATE — never "the pane
# is gone". U08 §6 measured one hard `i/o timeout` in ~12 calls on a healthy box.
# The socket is resolved to a NON-EMPTY value or this refuses: `--to ""` drives the AMBIENT kitty,
# silently, at the wrong pane. (U08 §4.2 spells the variable `CC_KITTY_TO`; the name throughout
# this tree is CC_TERM_KITTY_TO — bin/it2-kitty:206, lr-lib.sh:676. The spec is wrong.)
cc_tui_rpc() { # <kitty @ args…> → rc 0 ok · 2 no transport · else kitty's own rc
  local kb sock tb
  kb="$(cc_tui_kitty_bin)" || return 2
  sock="$(cc_tui_socket)" || return 2
  [ -n "$kb" ] && [ -n "$sock" ] || return 2
  tb="$(_cc_tui_timeout_bin || true)"
  if [ -n "$tb" ]; then "$tb" "${CC_TUI_RPC_TIMEOUT:-10}" "$kb" @ --to "$sock" "$@"
  else "$kb" @ --to "$sock" "$@"
  fi
}

# A kitty window id is an integer. THIS IS A COST GATE AS WELL AS A CORRECTNESS ONE: U08 §6
# measured `get-text --match "id:"` with an empty id at 7.6 SECONDS — ~200x a good call — before
# erroring. Validate before every RPC, never after.
cc_tui_valid_id() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ── EXISTENCE, with the failure DIRECTION the tree already settled ───────────────────────────────
# `kitty @ send-text` EXITS 0 FOR A WINDOW THAT DOES NOT EXIST (bin/it2-kitty:443-446, re-measured
# 2026-08-18), so the send's rc can never carry rc 1. This is the only thing that can.
#   0 present · 1 PROVABLY absent · 2 could not tell ⇒ the caller DELIVERS ANYWAY, exactly as
# prove_target does (bin/it2-kitty:468): an unreadable enumeration is not evidence of absence
# (memory: lookup-miss-is-not-absence).
cc_tui_exists() { # $1=window id → 0/1/2
  local id="${1:-}" out
  cc_tui_valid_id "$id" || return 1
  out="$(cc_tui_rpc ls --match "id:$id" 2>/dev/null)" || return 2
  [ -n "$out" ] || return 2
  printf '%s' "$out" | ID="$id" /usr/bin/python3 -c '
import json,os,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(2)
want=os.environ["ID"]
sys.exit(0 if any(str(w["id"])==want for ow in d for t in ow.get("tabs",[]) for w in t.get("windows",[])) else 1)'
}

cc_tui_screen() { # $1=window id → the pane's screen on stdout; rc 0 read / 1 UNREADABLE
  local id="${1:-}" out
  cc_tui_valid_id "$id" || return 1
  out="$(cc_tui_rpc get-text --match "id:$id" --extent screen 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# ── THE COMPOSER PARSE — a byte-level copy of handoff-fire.sh:2585 composer_content ──────────────
# The input box is the text between the LAST TWO full-width border rows (runs of U+2500). Inside
# it an EMPTY composer renders only non-ASCII ink (the ❯ glyph, cursor artifacts); any draft is
# printable ASCII. The border is matched as a repeated BYTE run and never as a literal TUI phrase —
# a phrase dies at the wrap, a border run is width-invariant (memory:
# tui-literal-phrase-match-is-width-dependent). A torn or boxless screen is rc 1 = UNKNOWN, and
# every caller fails toward NOT typing.
cc_tui_composer() { # $1=window id → stdout: printable content, space-stripped; rc 0 parsed / 1 UNKNOWN
  local id="${1:-}" scr raw rc b12='────────────'
  scr="$(cc_tui_screen "$id")" || return 1
  raw="$(printf '%s\n' "$scr" | LC_ALL=C awk -v b="$b12" '
    { line[NR] = $0; if (index($0, b) > 0) { b2 = b1; b1 = NR } }
    END {
      if (b1 == 0 || b2 == 0 || b1 - b2 < 2) exit 9
      for (i = b2 + 1; i < b1; i++) print line[i]
    }')" && rc=0 || rc=$?
  [ "$rc" = 0 ] || return 1
  raw="$(printf '%s' "$raw" | LC_ALL=C tr -cd '[:print:]')"
  # The never-typed-in placeholder, matched as a WHOLE row only: a real draft that merely STARTS
  # with `Try "` must still read as a draft — a loose match types over operator text.
  if printf '%s' "$raw" | LC_ALL=C grep -qE '^[[:space:]]*Try "[^"]*("|\.\.\.)[[:space:]]*$'; then
    raw=""
  fi
  printf '%s' "$raw" | LC_ALL=C tr -d '[:space:]'
  return 0
}

# ── THE SCRUB — a copy of handoff-fire.sh:2684 composer_scrub_verified ───────────────────────────
# Read-back verified, never fire-and-forget, and it SENDS NOTHING INTO AN UNREADABLE BOX (rc 2,
# returned BEFORE the first keystroke): an unreadable composer is dominated by a blocking
# permission/trust modal, where a keystroke is consumed as the ANSWER to a single-key prompt.
# \x15 (Ctrl-U) is the sanctioned clear — never ESC, which also interrupts the running turn, and
# never `kitty @ send-key ctrl+u`, whose encoding depends on the window's keyboard mode (U08 §3c).
cc_tui_clear() { # $1=id [$2=rounds] → 0 PROVEN empty · 1 could not clear (last content on stdout) · 2 unknown box
  local id="${1:-}" rounds="${2:-${CC_TUI_SCRUB_ROUNDS:-12}}" n=0 c prev crc
  c="$(cc_tui_composer "$id")" && crc=0 || crc=1
  [ "$crc" = 0 ] || return 2
  [ -n "$c" ] || return 0
  prev="$c"
  while [ "$n" -lt "$rounds" ]; do
    n=$((n + 1))
    cc_tui_rpc send-text --match "id:$id" -- $'\x15' >/dev/null 2>&1 || return 1
    /bin/sleep "${CC_TUI_SETTLE:-0.5}"
    c="$(cc_tui_composer "$id")" && crc=0 || crc=1
    [ "$crc" = 0 ] || return 2
    [ -n "$c" ] || return 0
    if [ "$c" = "$prev" ]; then
      # Ctrl-U made no progress ⇒ the cursor sits at the start of an empty line; eat the newline.
      cc_tui_rpc send-text --match "id:$id" -- $'\x7f' >/dev/null 2>&1 || return 1
      /bin/sleep "${CC_TUI_SETTLE:-0.5}"
      c="$(cc_tui_composer "$id")" && crc=0 || crc=1
      [ "$crc" = 0 ] || return 2
      [ -n "$c" ] || return 0
    fi
    prev="$c"
  done
  printf '%s' "$c"
  return 1
}

# ── RESIDUE RECEIPT — the SAME store handoff-fire.sh:2733 writes, on purpose ─────────────────────
# Content-keyed, so a stale receipt cannot authorise a scrub of text that no longer matches it and
# it needs no TTL. Sharing the store is what lets the RECYCLE gate finish a clear this rail could
# not (handoff-fire.sh:2751 composer_residue_is_ours) — and the key space is the same, because on
# this box a "pane uuid" IS a kitty window id (iTerm2 is not running; U08 §6).
cc_tui_residue_dir() { printf '%s' "${CC_COMPOSER_RESIDUE_DIR:-$HOME/.claude/logs/composer-residue}"; }

cc_tui_residue_record() { # $1=id $2=content-as-read → always 0 (never breaks the caller)
  local d; d="$(cc_tui_residue_dir)"
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  mkdir -p "$d" 2>/dev/null || return 0
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$2" > "$d/${1//\//_}" 2>/dev/null || true
  return 0
}

cc_tui_residue_forget() { # $1=id → always 0
  local d; d="$(cc_tui_residue_dir)"
  [ -n "${1:-}" ] || return 0
  rm -f "$d/${1//\//_}" 2>/dev/null || true
  return 0
}

# ── THE READ-BACK FORMS — handoff-fire.sh:2839 paste_readback_ok, over a FILE ────────────────────
# Signature deviation, deliberate: handoff-fire takes the payload as a STRING, which it must,
# because it pastes a shell variable. This rail pastes `--from-file`, and `$(cat f)` eats trailing
# newlines — so the placeholder's `+N lines` would be computed off a payload one newline shorter
# than the bytes actually sent, and a pristine paste would read MANGLED. Count from the file.
_cc_tui_nl_file() { # $1=file → newline count, \r\n|\r|\n each counted ONCE (CC's own regex)
  local s n
  s="$(LC_ALL=C cat "$1" 2>/dev/null; printf x)"; s="${s%x}"
  s="${s//$'\r\n'/$'\n'}"; s="${s//$'\r'/$'\n'}"
  n="${s//[!$'\n']/}"
  printf '%s' "${#n}"
}

cc_tui_readback_expect() { # $1=payload file → the forms a human should look for
  local nl; nl="$(_cc_tui_nl_file "${1:-}")"
  if [ "$nl" -gt 0 ]; then printf 'the text itself (or its scrolled TAIL), or [Pasted text #N +%s lines]' "$nl"
  else printf 'the text itself (or its scrolled TAIL), or [Pasted text #N]'; fi
}

# A short tail proves little, so a match under the floor is no match at all. 64 stripped chars is
# ~1.7 rows of a 40-column composer.
cc_tui_readback_ok() { # $1=payload file $2=space-stripped read-back → rc 0 proven / 1 mismatch
  local f="${1:-}" got="${2-}" want nl ere min="${CC_TUI_TAIL_MIN:-64}"
  want="$(LC_ALL=C tr -cd '[:print:]' < "$f" 2>/dev/null | LC_ALL=C tr -d '[:space:]')"
  [ -n "$want" ] && [ "$got" = "$want" ] && return 0                 # inline form
  # Scrolled-tail form: the composer is height-capped and follows the CURSOR, which after a
  # bracketed paste sits at the END, so a payload taller than the box shows only its tail. Anchored
  # on the TAIL on purpose — a HEAD match is transport truncation and must stay a mismatch.
  if [ -n "$want" ] && [ "${#got}" -ge "$min" ] && [ "${#got}" -lt "${#want}" ] \
     && [ "${want: -${#got}}" = "$got" ]; then
    return 0
  fi
  nl="$(_cc_tui_nl_file "$f")"
  if [ "$nl" -gt 0 ]; then ere="^\[Pastedtext#[0-9][0-9]*[+]${nl}lines\]$"
  else                     ere="^\[Pastedtext#[0-9][0-9]*\]$"; fi
  printf '%s' "$got" | LC_ALL=C grep -qE "$ere"                      # placeholder form, N pinned
}

# ── THE DISK ORACLE ──────────────────────────────────────────────────────────────────────────────
# THE MARKER: the LONGEST maximal run of printable ASCII in the payload, trimmed and capped.
# `tr -c '[:print:]' '\n'` under LC_ALL=C turns every non-ASCII and every newline byte into a line
# break, so every candidate is a CONTIGUOUS SUBSTRING of the payload by construction — which a
# filtered-out or re-assembled line would not be, and `contains()` would then never match. One
# LINE, never the whole payload: CC normalises leading/trailing whitespace on submit, and a
# multi-line needle also has to survive whatever shape `.message.content` takes.
CC_TUI_MARKER_MIN="${CC_TUI_MARKER_MIN:-8}"
CC_TUI_MARKER_MAX="${CC_TUI_MARKER_MAX:-120}"
cc_tui_marker() { # $1=payload file → the needle on stdout; rc 1 when none is long enough to prove anything
  local f="${1:-}" m
  [ -n "$f" ] && [ -f "$f" ] || return 1
  m="$(LC_ALL=C tr -c '[:print:]' '\n' < "$f" 2>/dev/null \
       | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
       | LC_ALL=C awk '{ if (length($0) > n) { n = length($0); s = $0 } } END { if (n > 0) print s }' \
       | LC_ALL=C cut -b "1-${CC_TUI_MARKER_MAX}")"
  [ -n "$m" ] || return 1
  # A needle under the floor cannot distinguish OUR prompt from any other user record written in
  # the same window after the offset, and the expensive direction of this oracle is a FALSE rc 0.
  [ "${#m}" -ge "${CC_TUI_MARKER_MIN}" ] || return 1
  printf '%s' "$m"
}

# THE SESSION, without reading a pixel: ~/.claude/cc-registry/<pane>.json (handoff-fire.sh:372
# REG_DIR) names the session_id, and the transcript is <cfg>/projects/<slug>/<sid>.jsonl.
cc_tui_transcript() { # $1=pane id → the transcript path on stdout; rc 1 when it cannot be resolved
  local id="${1:-}" reg sid cfg f
  [ -n "${CC_TUI_TRANSCRIPT:-}" ] && { printf '%s' "$CC_TUI_TRANSCRIPT"; return 0; }
  reg="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/${id}.json"
  [ -f "$reg" ] || return 1
  sid="$(/usr/bin/python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("session_id") or "")
except Exception: pass' "$reg" 2>/dev/null)"
  [ -n "$sid" ] || return 1
  for cfg in $(cc_tui_config_dirs); do
    for f in "$cfg"/projects/*/"$sid".jsonl; do
      [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
  done
  return 1
}

cc_tui_config_dirs() { # → one account store per line
  local h
  if _cc_tui_load_lr && command -v lr_config_dirs >/dev/null 2>&1; then lr_config_dirs; return 0; fi
  for h in "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -d "$h/projects" ] && printf '%s\n' "$h"
  done
  return 0
}

# THE ORACLE ITSELF. Read ONLY the bytes appended after the baseline and look for a `type:"user"`
# record carrying the needle.
#   · `type == "user"` is load-bearing, not decoration: a prompt REJECTED by CC (the /goal
#     >4000-char cap) lands the text in attachment/system rows and then idles forever, and a
#     transcript can carry our own text in an ASSISTANT record that merely quotes it. Only a user
#     record is the durable artifact "the session ingested this prompt"
#     (handoff-fire.sh:3149 marker_in_user_record says the same thing for the whole file).
#   · the content walk goes through `.text` for the ARRAY form rather than `tostring`, so the
#     needle is matched against the real text instead of against JSON-escaped bytes.
#   · the rc is taken from the printed TOKEN, never from the pipeline: `first(inputs|…)`
#     short-circuits, `tail` then takes SIGPIPE, and under a caller's `set -o pipefail` a 141
#     would invert the verdict on exactly the input that MATCHED (memory: killed-pipeline-empty-
#     output-is-not-a-verdict / claimed-outcome-vs-checked-outcome).
cc_tui_record_after() { # $1=transcript $2=byte offset $3=needle → 0 found / 1 not found or cannot read
  local f="${1:-}" off="${2:-0}" m="${3:-}" out
  [ -n "$f" ] && [ -f "$f" ] && [ -n "$m" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  case "$off" in ''|*[!0-9]*) off=0 ;; esac
  out="$(tail -c "+$((off + 1))" "$f" 2>/dev/null | jq -rn --arg m "$m" '
    def _txt:
      if   type == "string" then .
      elif type == "array"  then map(if type == "string" then . elif type == "object" then (.text? // "") else "" end) | join("\n")
      else tostring end;
    first(inputs
          | select(.type == "user"
                   and (((.message.content? // .content? // "") | _txt) | contains($m)))
          | "1")' 2>/dev/null || true)"
  [ "$out" = 1 ]
}

_cc_tui_size() { # $1=file → its size in bytes, 0 when absent. BSD `wc -c` PADS to width 8 and a
                 # digit guard on that padding zeroes a true count (memory: digit-guard-destroys).
  local n
  [ -f "${1:-}" ] || { printf 0; return 0; }
  n="$(LC_ALL=C wc -c < "$1" 2>/dev/null | LC_ALL=C tr -d '[:space:]')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# ── DELIVERY ─────────────────────────────────────────────────────────────────────────────────────
# `--from-file` + kitty's own `--bracketed-paste=enable`. `--from-file` is the only shape that is
# BYTE-EXACT: plain `send-text -- "$text"` follows PYTHON ESCAPING RULES (kitty's own help), so a
# payload containing \n, \e, \u, \x or a lone backslash is silently reinterpreted on the wire.
cc_tui_type() { # $1=id $2=payload file → 0 delivered / 1 provably absent or the RPC failed
  local id="${1:-}" f="${2:-}" erc=0
  cc_tui_valid_id "$id" || return 1
  [ -n "$f" ] && [ -f "$f" ] || return 1
  cc_tui_exists "$id" || erc=$?
  [ "$erc" = 1 ] && return 1                 # 2 = could not tell ⇒ deliver anyway (prove_target's rule)
  cc_tui_rpc send-text --match "id:$id" --bracketed-paste=enable --from-file "$f" >/dev/null 2>&1 || return 1
  return 0
}

cc_tui_cr() { # $1=id → 0 sent / 1 the RPC failed
  local id="${1:-}"
  cc_tui_valid_id "$id" || return 1
  cc_tui_rpc send-text --match "id:$id" -- $'\r' >/dev/null 2>&1 || return 1
  return 0
}

# ── THE ENTRY POINT ──────────────────────────────────────────────────────────────────────────────
# CC_TUI_LAST is an out-parameter carrying the last OBSERVATION (never a verdict — nothing branches
# on it), for a caller that wants to log what was seen. Deliberately not `local`.
cc_tui_submit() { # $1=pane id $2=payload file → 0..5, per the table at the head of this file
  local id="${1:-}" f="${2:-}"
  local prewait="${CC_TUI_PREWAIT:-30}" preivl="${CC_TUI_PREIVL:-5}"
  local tries="${CC_TUI_READBACK_TRIES:-8}" settle="${CC_TUI_SETTLE:-0.5}"
  local rtries="${CC_TUI_RECORD_TRIES:-30}" rivl="${CC_TUI_RECORD_IVL:-2}"
  local erc=0 t=0 n=0 c crc got marker tpath off sz scrub_rc

  CC_TUI_LAST=""
  if ! cc_tui_valid_id "$id"; then
    CC_TUI_LAST="<bad-id>"
    echo "cc-tui: refusing — '$id' is not a kitty window id (a malformed --match costs 7.6s and hits the wrong pane or none)" >&2
    return 1
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    CC_TUI_LAST="<no-payload>"
    echo "cc-tui: refusing — payload file '$f' does not exist" >&2
    return 1
  fi
  cc_tui_exists "$id" || erc=$?
  if [ "$erc" = 1 ]; then
    CC_TUI_LAST="<absent>"
    echo "cc-tui: refusing to type into window $id — it is not in kitty's window list. kitty's send-text exits 0 for a nonexistent id, so delivering here would report success while the text went nowhere." >&2
    return 1
  fi

  # (1) EMPTINESS PRE-GATE — mandatory, and it is what stops a paste APPENDING to an operator draft
  # and a CR submitting the hybrid. There is no argv for a message into a live composer, so the
  # race with the human's own keystrokes is not removable, only detectable (bin/cc-pane-runner:5-25).
  while :; do
    c="$(cc_tui_composer "$id")" && crc=0 || crc=1
    [ "$crc" = 0 ] && [ -z "$c" ] && break
    if [ "$t" -ge "$prewait" ]; then
      if [ "$crc" = 0 ]; then
        CC_TUI_LAST="$(printf '%.120s' "$c")"
        echo "cc-tui: HELD ${prewait}s — composer occupied: '$(printf '%.80s' "$c")' (an unsubmitted draft; pasting would append to it and a CR would submit the hybrid)" >&2
        return 3
      fi
      CC_TUI_LAST="<unreadable>"
      echo "cc-tui: ABSTAINED — composer unreadable for ${prewait}s (no input box on screen); typing needs the affirmative. Dominant cause: the pane sits on a BLOCKING MODAL, which renders no composer box at all, and a bracketed paste into a single-key prompt is consumed as ANSWERS." >&2
      return 2
    fi
    /bin/sleep "$preivl"; t=$((t + preivl))
  done

  # (2) THE HIGH-WATER MARK, taken BEFORE anything is typed. This is the whole reason the oracle
  # cannot be fooled by a record that was already there.
  tpath="$(cc_tui_transcript "$id" 2>/dev/null || true)"
  off="$(_cc_tui_size "$tpath")"
  marker="$(cc_tui_marker "$f" 2>/dev/null || true)"

  # (3) DELIVER.
  cc_tui_type "$id" "$f" || { CC_TUI_LAST="<send-failed>"; echo "cc-tui: the send-text RPC failed for window $id" >&2; return 1; }

  # (4) SCREEN READ-BACK, POLLED not sampled — a torn frame is an ordinary event on a repainting
  # pane. This tier decides ONLY whether to press Enter; it is never the success oracle.
  while :; do
    /bin/sleep "$settle"
    got="$(cc_tui_composer "$id")" && crc=0 || crc=1
    [ "$crc" = 0 ] && cc_tui_readback_ok "$f" "$got" && break
    n=$((n + 1))
    if [ "$n" -ge "$tries" ]; then
      if   [ "$crc" != 0 ]; then CC_TUI_LAST="<unreadable>"
      elif [ -z "$got" ];   then CC_TUI_LAST="<empty>"
      else                       CC_TUI_LAST="$(printf '%.120s' "$got")"; fi
      # SCRUB HERE, WHERE ATTRIBUTION IS FREE: this path proved the composer EMPTY moments ago and
      # then pasted into it, so the residue is ours by construction. Leaving it was the whole
      # 2026-08-23 outage — the next recycle finds a non-empty composer, correctly refuses, and the
      # chain dies with absence as its only symptom.
      scrub_rc=0; cc_tui_clear "$id" >/dev/null 2>&1 || scrub_rc=$?
      if [ "$scrub_rc" = 0 ]; then cc_tui_residue_forget "$id"
      else                        cc_tui_residue_record "$id" "$CC_TUI_LAST"; fi
      echo "cc-tui: MANGLED — ${tries} read-back(s) saw '$(printf '%.80s' "$CC_TUI_LAST")', expected $(cc_tui_readback_expect "$f"); CR NOT sent (scrub rc $scrub_rc)." >&2
      return 4
    fi
  done

  # (5) SUBMIT. A failed CR leaves a LOADED composer, which is neither "no record" nor a mangle —
  # it is a send that did not happen, so it is rc 1, and the composer is left clean.
  if ! cc_tui_cr "$id"; then
    CC_TUI_LAST="<cr-failed>"
    scrub_rc=0; cc_tui_clear "$id" >/dev/null 2>&1 || scrub_rc=$?
    [ "$scrub_rc" = 0 ] || cc_tui_residue_record "$id" "$(printf '%.120s' "$(cc_tui_composer "$id" 2>/dev/null || true)")"
    echo "cc-tui: the CR RPC failed for window $id — the payload is pasted but UNSUBMITTED (scrub rc $scrub_rc)" >&2
    return 1
  fi

  # (6) THE VERDICT, on disk.
  if [ -z "$marker" ]; then
    CC_TUI_LAST="<no-marker>"
    echo "cc-tui: submitted, but the payload carries no printable-ASCII run of ${CC_TUI_MARKER_MIN}+ bytes to search for — CANNOT TELL whether it landed." >&2
    return 5
  fi
  n=0
  while [ "$n" -lt "$rtries" ]; do
    [ -n "$tpath" ] || tpath="$(cc_tui_transcript "$id" 2>/dev/null || true)"
    if [ -n "$tpath" ] && [ -f "$tpath" ]; then
      sz="$(_cc_tui_size "$tpath")"
      # A transcript that SHRANK was rotated or replaced; an offset into the old one would skip
      # real records. Re-baseline rather than carry a bogus floor.
      [ "$sz" -lt "$off" ] && off=0
      if cc_tui_record_after "$tpath" "$off" "$marker"; then
        CC_TUI_LAST="$tpath"
        return 0
      fi
    fi
    n=$((n + 1))
    /bin/sleep "$rivl"
  done
  CC_TUI_LAST="${tpath:-<no-transcript>}"
  echo "cc-tui: submitted, but no user record carrying the payload appeared in ${tpath:-<no transcript resolved>} within ${rtries} poll(s) x ${rivl}s — CANNOT TELL (this is never 'failed': the session may simply be slow)." >&2
  return 5
}
