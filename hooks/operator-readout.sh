#!/usr/bin/env bash
# operator-readout.sh — Stop hook: the SILVER-PLATTER close renderer (operator crux 2026-07-20).
#
# THE DEFECT it closes: at turn close, operator-owned manual steps lived scattered across three
# stores (pending-activation/ · decisions/ · backlog --blocked) plus git state, surfaced only as
# model PROSE — a discipline, not a construction. A close could bury "run X" under paragraphs
# (the operator's literal complaint: steps must be silver-plattered — the exact single-line
# command, ambiguity eliminated), and a model could simply not mention them. This hook renders
# the close block BY CONSTRUCTION from disk truth — Pyramid-ordered: ONE governing state line
# (wrap-ledger rung + facts), then numbered `▶ <exact runnable command>` lines, capped, counted.
#
# ── DELIVERY ── pure-advisory {"systemMessage": …} — NEVER {decision:"block"}. This hook informs
#   the OPERATOR; it must never re-prompt the model (zero loop risk; composes with the model-facing
#   Stop arms: session-continue owns 🔧 auto-continue, completion-assert polices false-done,
#   boundary-handoff advises handoff). Bare-systemMessage-on-Stop is the proven channel
#   (session-continue.sh cap message precedent).
#
# ── FIRE PREDICATE ── steps>0 ∨ RUNG=📦. Silent otherwise: 🔧 with no operator step is the
#   MODEL's job (auto-continue), ✅/read-only needs no block (protocol: suppress on read-only).
#   📦 always renders — committed-but-unlanded is the invisible-risk state (parked work is lost
#   work if never surfaced).
#
# ── DAMPING (boundary-handoff B-2 lesson: never quiet in the dangerous state) ── latch on
#   hash(rendered block): ANY change re-renders immediately; unchanged re-asserts only after TTL
#   (default 900s) — chatty interactive turns stay quiet, but a returning operator always finds
#   the block at the close they actually read.
#
# ── STEP SOURCES (disk truth, machine-wide; each independently fail-open) ──
#   deploy-lag   shared checkout ON trunk but behind its origin/main → the exact ff-sync command
#                (deploy-lag incident 2026-07-20: landed ≠ live; ordered FIRST — activations abort
#                on a stale checkout)
#   activation   pending-activation/*.sh with no .done marker → `bash <p> && touch <p>.done`
#                (CONFIRM=1-prefixed when the script gates on it — `&&` keeps a dry-run or failed
#                run from falsely marking done)
#   decisions    cc-decide store, open class-C (human-gated): run_command (board vocabulary,
#                forward-compatible with feat/board-runnable-commands) → staged_artifact_path
#                (`bash <p>`) → first-sentence prose fallback. Open class-B is NEVER itemized —
#                one summary line only when defaults auto-fire within 24h (the early-veto window).
#   backlog      cc-backlog list --blocked --json → run/run_command if present, else needs-prose.
#   Line marks: `▶` = run this exact command · `◆` = judgment/decision (no single command exists).
#
# ── SAFETY (house pattern) ── every hook path exits 0; jq/read failure → abstain; B-3 one IDL
#   {fired|abstained:<reason>} line per invocation; kill-switch CC_OPREADOUT_DISABLE=1;
#   compose-guard abstains while session-continue's 🔧 loop is armed (lib/continue-sentinel SSOT).
#
# ── MODES ── (default, stdin JSON) hook mode · `--render [--cwd <d>]` prints the block to stdout
#   with no damping/state/IDL — /wrap's pull surface and the bats harness call this; ONE renderer
#   serves push + pull so the surfaces cannot drift.
#
# Env seams (tests): CC_OPREADOUT_DISABLE · CC_OPREADOUT_MAX · CC_OPREADOUT_TTL_S ·
#   CC_OPREADOUT_NOW (epoch) · CC_OPREADOUT_STATE_DIR · CC_ACTIVATION_DIR · CC_DECISIONS_DIR ·
#   CC_BACKLOG_FILE · CC_BACKLOG_BIN · WRAP_LEDGER_BIN · WRAP_TRUNK (passes through) ·
#   CC_SHARED_CHECKOUT · CC_IDL · CC_CONTINUE_SENTINEL
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${CC_OPREADOUT_STATE_DIR:-$CFG/state/operator-readout}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
ACT_DIR="${CC_ACTIVATION_DIR:-$HOME/.claude/autonomy/pending-activation}"
DEC_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
BLG_FILE="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
MAX="${CC_OPREADOUT_MAX:-6}"
TTL="${CC_OPREADOUT_TTL_S:-900}"
NOW="${CC_OPREADOUT_NOW:-$(date +%s 2>/dev/null || echo 0)}"
SID="?"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

MODE="hook"; RCWD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --render) MODE="render" ;;
    --cwd)    shift; RCWD="${1:-}" ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) : ;;   # tolerate unknown args — a hook must never die on harness argv drift
  esac
  [ $# -gt 0 ] && shift
done

log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built; default {})
  [ "$MODE" = "hook" ] || return 0
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts extra; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field (house rule): a raw " / \ / newline in a value must never be able to
  # emit a malformed IDL line — one bad line aborts the cc-audit jq -rs slurp (reads as "none").
  jq -cn --arg ts "$ts" --arg sid "$SID" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"operator-readout",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }

# ── tiny helpers ─────────────────────────────────────────────────────────────────────────────────
tildify() { printf '%s' "${1/#$HOME/~}"; }   # display+paste-safe: the shell re-expands ~
epoch_to_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                 || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ''; }

# ── the ONE renderer: prints the block (or nothing) for cwd=$1. Sets RUNG + TOTAL for the caller —
#    so hook mode must invoke it via redirection in THIS shell, never `$(…)` (subshell loses them).
RUNG="?"; TOTAL=0
render_block() {
  local cwd="$1"
  local steps_file; steps_file="$(mktemp "${TMPDIR:-/tmp}/opreadout.XXXXXX")" || return 0
  # steps_file: one step per line — mark<TAB>text (mark ∈ {▶,◆}); array-free (bash-3.2-safe).

  # 1 · deploy-lag: shared checkout on trunk but behind its already-fetched origin/main.
  if [ -d "$SHARED" ] && git -C "$SHARED" rev-parse --git-dir >/dev/null 2>&1; then
    local sbr behind
    sbr="$(git -C "$SHARED" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$sbr" = "main" ] || [ "$sbr" = "master" ]; then
      behind="$(git -C "$SHARED" rev-list --count "HEAD..origin/$sbr" 2>/dev/null || echo 0)"
      case "$behind" in ''|*[!0-9]*) behind=0 ;; esac
      [ "$behind" -gt 0 ] && printf '▶\tgit -C %s pull --ff-only   [deploy: live layer %s behind origin/%s]\n' \
        "$(tildify "$SHARED")" "$behind" "$sbr" >> "$steps_file"
    fi
  fi

  # 2 · activations: staged, un-run (no .done marker). CONFIRM-gated scripts get CONFIRM=1 so the
  #     emitted line is the REAL run; `&&` keeps a failed run from falsely touching .done.
  local f disp pre
  if [ -d "$ACT_DIR" ]; then
    for f in "$ACT_DIR"/*.sh; do
      [ -f "$f" ] || continue
      [ -f "$f.done" ] && continue
      disp="$(tildify "$f")"; pre=""
      grep -q 'CONFIRM' "$f" 2>/dev/null && pre="CONFIRM=1 "
      printf '▶\t%sbash %s && touch %s.done   [activation]\n' "$pre" "$disp" "$disp" >> "$steps_file"
    done
  fi

  # 3 · open class-C decisions (human-gated), oldest first. Prefer an exact command; degrade
  #     honestly to the packet's first sentence (◆ = judgment, no single command exists).
  if [ -d "$DEC_DIR" ]; then
    for f in "$DEC_DIR"/*.json; do
      [ -e "$f" ] || continue
      # NB: jq -r renders \t in string literals as REAL tabs — line shape: created<TAB>mark<TAB>text;
      # sort on the created prefix (FIFO), then cut the prefix off. Never @tsv (it \t-escapes fields).
      jq -r '
        select((.status // "") == "open" and (.class // "") == "C")
        | (.id // "?" | .[0:8]) as $id8
        | (.what_plain // "" | gsub("[\n\t]"; " ") | split(". ")[0]) as $s
        | ($s | if length > 110 then .[0:110] + "…" else . end) as $sent
        | (.run_command // "" | gsub("[\n\t]"; " ")) as $run
        | (.staged_artifact_path // "" | gsub("[\n\t]"; " ")) as $staged
        | (if $run != ""      then "▶\t\($run)   [decision C \($id8): \($sent | .[0:60])]"
           elif $staged != "" then "▶\tbash \($staged)   [decision C \($id8): \($sent | .[0:60])]"
           else "◆\t[decision C \($id8)] \($sent)" end) as $line
        | "\(.created // "?")\t\($line)"' "$f" 2>/dev/null
    done | sort | cut -f2- >> "$steps_file"
  fi

  # 4 · blocked backlog: operator-only `needs` steps, with the run command when the item carries one.
  local blg="${CC_BACKLOG_BIN:-}"
  if [ -z "$blg" ]; then
    for f in "$SCRIPT_DIR/../bin/cc-backlog" "$CFG/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog"; do
      [ -x "$f" ] && { blg="$f"; break; }
    done
  fi
  if [ -n "$blg" ] && [ -f "$BLG_FILE" ]; then
    "$blg" list --blocked --json 2>/dev/null | jq -r '
      .[]?
      | (.title // "" | gsub("[\n\t]"; " ") | .[0:60]) as $t
      | (.needs // "" | gsub("[\n\t]"; " ") | .[0:90]) as $n
      | (.run // .run_command // "" | gsub("[\n\t]"; " ")) as $run
      | if $run != "" then "▶\t\($run)   [backlog \(.id // "?"): \($t)]"
        else "◆\t[backlog \(.id // "?")] \($t) — needs: \($n)" end' 2>/dev/null >> "$steps_file"
  fi

  # ── state line from the un-fakeable ledger (cwd repo; skipped cleanly outside a repo) ──
  local state="" wrap="" led="" branch ahead shas dirty_n gate remainder parts
  RUNG="?"
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    wrap="${WRAP_LEDGER_BIN:-}"
    if [ -z "$wrap" ]; then
      for f in "$SCRIPT_DIR/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
        [ -f "$f" ] && { wrap="$f"; break; }
      done
    fi
    [ -n "$wrap" ] && led="$( cd "$cwd" 2>/dev/null && bash "$wrap" --machine 2>/dev/null || true )"
  fi
  if [ -n "$led" ]; then
    lf() { printf '%s' "$led" | grep -E "^$1=" | head -1 | cut -d= -f2-; }
    RUNG="$(lf RUNG)"; [ -n "$RUNG" ] || RUNG="?"
    branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    case "$RUNG" in
      "📦")
        ahead="$(lf AHEAD)"; shas="$(lf SHAS)"
        state="📦 parked — ${ahead} commit(s) on ${branch} unlanded (${shas:-?}) → /ship" ;;
      "🔧")
        dirty_n="$(lf DIRTY_N)"; gate="$(lf GATE)"; remainder="$(lf REMAINDER)"
        parts=""
        [ "${dirty_n:-0}" != "0" ] && parts="${dirty_n} file(s) uncommitted"
        [ "$gate" = "stale" ] && parts="${parts:+$parts · }gate stale on HEAD"
        [ "${remainder:-0}" != "0" ] && parts="${parts:+$parts · }${remainder} DoD item(s) open"
        state="🔧 in progress — ${parts:-loose ends}" ;;
      "✅") state="✅ live on trunk" ;;
    esac
  fi

  # ── class-B early-veto summary (≤24h auto-fire window only; never itemized) ──
  local b_n=0 b_earliest="" horizon b_line=""
  horizon="$(epoch_to_iso $(( NOW + 86400 )))"
  if [ -d "$DEC_DIR" ] && [ -n "$horizon" ]; then
    b_earliest="$(
      for f in "$DEC_DIR"/*.json; do
        [ -e "$f" ] || continue
        jq -r --arg h "$horizon" '
          select((.status // "")=="open" and (.class // "")=="B"
                 and (.veto_deadline // "") != "" and .veto_deadline <= $h)
          | .veto_deadline' "$f" 2>/dev/null
      done | sort | head -1)"
    if [ -n "$b_earliest" ]; then
      b_n="$(
        for f in "$DEC_DIR"/*.json; do
          [ -e "$f" ] || continue
          jq -r --arg h "$horizon" '
            select((.status // "")=="open" and (.class // "")=="B"
                   and (.veto_deadline // "") != "" and .veto_deadline <= $h) | .id' "$f" 2>/dev/null
        done | grep -c .)"
      b_line="${b_n} class-B default(s) auto-fire ≤24h (earliest ${b_earliest}) — veto: cc-decide veto <id>"
    fi
  fi

  # ── compose (Pyramid: governing line → numbered steps → counted footer) ──
  local total shown=0 over
  total="$(grep -c . "$steps_file" 2>/dev/null || echo 0)"; case "$total" in ''|*[!0-9]*) total=0 ;; esac
  TOTAL="$total"
  if [ "$total" -eq 0 ] && [ "$RUNG" != "📦" ]; then rm -f "$steps_file"; return 0; fi

  local hdr
  if [ "$total" -gt 0 ]; then hdr="OPERATOR ▸ ${total} manual step(s)${state:+ · $state}"
  else hdr="OPERATOR ▸ ${state}"; fi
  printf '%s\n' "$hdr"

  local n=0 mark text
  while IFS="$(printf '\t')" read -r mark text; do
    [ -n "$mark" ] || continue
    n=$((n+1)); [ "$n" -gt "$MAX" ] && break
    printf ' %d %s %s\n' "$n" "$mark" "$text"
    shown=$((shown+1))
  done < "$steps_file"
  rm -f "$steps_file"

  over=$(( total - shown )); [ "$over" -lt 0 ] && over=0
  local foot=""
  [ "$over" -gt 0 ] && foot="+${over} more"
  [ -n "$b_line" ] && foot="${foot:+$foot · }${b_line}"
  if [ "$total" -gt 0 ]; then
    if command -v cc-blockers >/dev/null 2>&1; then foot="${foot:+$foot · }board: cc-blockers"
    else foot="${foot:+$foot · }detail: cc-decide list --open · cc-backlog list --blocked"; fi
  fi
  [ -n "$foot" ] && printf ' ─ %s\n' "$foot"
  return 0
}

# ── render mode: the pull surface (/wrap, tests, humans). No damping, no state, no IDL. ──
if [ "$MODE" = "render" ]; then
  command -v jq >/dev/null 2>&1 || { echo "operator-readout: jq required" >&2; exit 2; }
  out="$(render_block "${RCWD:-$PWD}")"
  if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "OPERATOR ▸ no manual steps pending."; fi
  exit 0
fi

# ── hook mode ──
input="$(cat 2>/dev/null || printf '{}')"
[ "${CC_OPREADOUT_DISABLE:-0}" = "1" ] && abstain "disabled"
command -v jq >/dev/null 2>&1 || abstain "no-jq"
SID="$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

# Compose-guard: while session-continue's 🔧 loop is armed the session is mid-drive — the close
# the operator reads comes later; yield (matches boundary-handoff's guard, same sentinel SSOT).
if [ -n "$CWD" ]; then
  if [ -n "${CC_CONTINUE_SENTINEL:-}" ]; then sc="$CC_CONTINUE_SENTINEL"
  else
    sclib="$SCRIPT_DIR/lib/continue-sentinel.sh"
    [ -f "$sclib" ] || sclib="$CFG/hooks/lib/continue-sentinel.sh"
    [ -f "$sclib" ] || sclib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
    sc=""
    if [ -f "$sclib" ]; then
      # shellcheck source=lib/continue-sentinel.sh
      # shellcheck disable=SC1091
      . "$sclib" 2>/dev/null || true
      command -v continue_sentinel_for >/dev/null 2>&1 && sc="$(continue_sentinel_for "$CWD" 2>/dev/null || true)"
    fi
  fi
  { [ -n "$sc" ] && [ -f "$sc" ]; } && abstain "continue-armed"
fi

# Render in THIS shell (temp-file redirect, not $(…)) so render_block's RUNG/TOTAL survive.
TMPB="$(mktemp "${TMPDIR:-/tmp}/opreadout-blk.XXXXXX" 2>/dev/null)" || abstain "no-mktemp"
render_block "${CWD:-}" > "$TMPB" 2>/dev/null
BLOCK="$(cat "$TMPB" 2>/dev/null || true)"; rm -f "$TMPB"
[ -n "$BLOCK" ] || abstain "nothing-to-surface"

# Damping latch: change → render now; unchanged → re-assert only after TTL.
mkdir -p "$STATE_DIR" 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "${CWD:-}" | shasum 2>/dev/null | cut -c1-16)"
HASH="$(printf '%s' "$BLOCK" | shasum 2>/dev/null | cut -c1-16)"
if [ -n "$SKEY" ] && [ -n "$HASH" ]; then
  LATCH="$STATE_DIR/$SKEY.last"
  if [ -f "$LATCH" ]; then
    read -r prev_hash prev_ts < "$LATCH" 2>/dev/null || { prev_hash=""; prev_ts=0; }
    case "$prev_ts" in ''|*[!0-9]*) prev_ts=0 ;; esac
    if [ "$prev_hash" = "$HASH" ] && [ $(( NOW - prev_ts )) -lt "$TTL" ]; then
      abstain "latched-ttl:$(( NOW - prev_ts ))s<${TTL}s"
    fi
  fi
  printf '%s %s\n' "$HASH" "$NOW" > "$LATCH" 2>/dev/null || true
fi

NSTEPS="$(printf '%s\n' "$BLOCK" | grep -cE '^ [0-9]+ (▶|◆)' 2>/dev/null)"
case "$NSTEPS" in ''|*[!0-9]*) NSTEPS=0 ;; esac
case "$TOTAL"  in ''|*[!0-9]*) TOTAL=0  ;; esac
log_idl fired "steps-surfaced" \
  "$(jq -cn --arg rung "$RUNG" --argjson total "$TOTAL" --argjson shown "$NSTEPS" \
      '{rung:$rung,steps_total:$total,steps_shown:$shown}' 2>/dev/null || echo '{}')"
jq -nc --arg m "$BLOCK" '{systemMessage:$m}' 2>/dev/null || true
exit 0
