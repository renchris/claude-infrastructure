#!/bin/bash
# lr-upgrade.sh — move an IDLE live session onto the CURRENT launcher binary + model, IN PLACE:
# same pane, same session uuid, same account, same effort, same permission mode.
#
# WHY THIS EXISTS (measured 2026-09-22, pane 567). Moving 14 sessions from 2.1.260/claude-opus-5 to
# 2.1.280/claude-opus-5-5 took ~5 h and six operator-run scripts. /limit-recover moves a LIMITED
# session to ANOTHER account; nothing did "same account, new binary+model". The hand-stitched path
# hit seven defects in a row; the ones this file answers by construction:
#   1. auto mode refuses one session acting on another live one ⇒ the ACTOR is this script, spawned
#      by the launchd reset poller (lr-reset-poller.sh, kind "upgrade"), outside every session;
#   2. an idle session never reads cc-notify mail ⇒ nothing here asks a session to do anything; the
#      relaunch is driven from outside, by handoff-fire's remote in-place recycle;
#   3. capacity-admit refused the relaunch AFTER /exit, stranding 3 panes at a bare shell ⇒ the
#      probe runs BEFORE anything is typed, the admission is minted as a one-shot token the launcher
#      redeems, sessions go one at a time, and a post-exit refusal is RETYPED (bounded) — never
#      CC_ADMIT_GATE=off, which the resumed claude would inherit for its whole life;
#   4. a non-ASCII prompt became invalid UTF-8 under printf %q and killed sed ⇒ the launcher is
#      REFUSED unless it is pure ASCII (lru_mint_launcher);
#   6. a resume-mode recycle died on the prompt trailer ⇒ fixed in handoff-fire.sh itself.
# (5 — `bash ~/.claude/…` missing a prefix allow rule — does not arise: no command is handed to a
# session. 7 — cc_tui_submit rc 4 — does not arise: no prompt is typed into a live composer; the
# relaunch goes into a bare shell, the path that worked every time.)
#
#   lr-upgrade.sh --census [--all | <pane|sid8>]   TSV, one row per live registry row (read-only)
#   lr-upgrade.sh --drive <sid> <pane> [--requested-by P] [--req-id ID]   one session, synchronous
#   lr-upgrade.sh --drain                           the serial queue the poller hands requests to
#   lr-upgrade.sh --auto-enqueue                    the poller's tick: queue every `upgrade` row
#   lr-upgrade.sh --pin-target <sid> <opus|fable|id|clear>  per-session target override (24h TTL)
#
# Census columns: pane sid binary model target effort perm cfg cwd pid disposition
# Dispositions: upgrade · current · self · teammate · duplicate · lead-with-teammate · no-transcript
#               · mid-turn · background-job · composer-occupied · composer-unknown · stale-row
#
# bash 3.2 (launchd runs /bin/bash): no associative arrays, no mapfile, no ${x,,}.
set -uo pipefail

_LRU_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
LRU_DIR="$(cd "$(dirname "$_LRU_SELF")" && pwd)"

# ── seams (every default resolves to the live machine; tests set each one) ──────────────────────
LRU_STATE="${LRU_STATE:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}}"
LRU_REG_DIR="${LRU_REG_DIR:-${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}}"
LRU_CFG_ROOT="${LRU_CFG_ROOT:-$HOME}"                       # an account "claude-x" lives at $ROOT/.claude-x
LRU_MODEL_CONFIG="${LRU_MODEL_CONFIG:-${LR_MODEL_CONFIG:-$HOME/.claude/model-config.yaml}}"
LRU_CLAUDE_BIN_CMD="${LRU_CLAUDE_BIN_CMD:-$LRU_DIR/../../bin/cc-claude-bin}"
LRU_HF_BIN="${LRU_HF_BIN:-$LRU_DIR/../handoff-fire.sh}"
LRU_FIRE_RESUME="${LRU_FIRE_RESUME:-$LRU_DIR/lr-fire-resume.sh}"
LRU_TUI_LIB="${LRU_TUI_LIB:-$LRU_DIR/../lib/cc-tui.sh}"
LRU_CA_LIB="${LRU_CA_LIB:-$LRU_DIR/../lib/capacity-admit.sh}"
LRU_LR_LIB="${LRU_LR_LIB:-$LRU_DIR/lr-lib.sh}"
LRU_IT2_BIN="${LRU_IT2_BIN:-$HOME/.claude/bin/it2}"
LRU_NOTIFY_BIN="${LRU_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"
LRU_SELF_SID="${LRU_SELF_SID-${CLAUDE_CODE_SESSION_ID:-}}"
LRU_RETYPE_MAX="${LRU_RETYPE_MAX:-5}"; case "$LRU_RETYPE_MAX" in ''|*[!0-9]*) LRU_RETYPE_MAX=5 ;; esac
LRU_RETYPE_GAP_S="${LRU_RETYPE_GAP_S:-20}"; case "$LRU_RETYPE_GAP_S" in ''|*[!0-9]*) LRU_RETYPE_GAP_S=20 ;; esac
LRU_ENGAGE_S="${LRU_ENGAGE_S:-200}"; case "$LRU_ENGAGE_S" in ''|*[!0-9]*) LRU_ENGAGE_S=200 ;; esac
LRU_GAP_S="${LRU_GAP_S:-10}"; case "$LRU_GAP_S" in ''|*[!0-9]*) LRU_GAP_S=10 ;; esac
UPG_QUEUE="$LRU_STATE/upgrade-queue"
UPG_RUNS="$LRU_STATE/upgrade"
UPG_RESULTS="$LRU_STATE/results"
UPG_CLAIMED="$LRU_STATE/claimed"
UPG_LOCK="$LRU_STATE/upgrade-drain.lock"
UPG_MUTEX_DIR="$LRU_STATE/runs/by-sid"

lru_say() { printf 'lr-upgrade: %s\n' "$*" >&2; }

# ── the SSOT: which model is "current" ──────────────────────────────────────────────────────────
# One awk per key, scoped to its block and stopping at the next top-level key — the same shape as
# lr-fire-resume.sh's lr_resolve_opus_model, and for its reason: `opus_prior` sits on the next line,
# and an unscoped grep would answer the question with the id being replaced.
lru_ssot() { # $1=block $2=key → value; rc 1 when absent
  local v
  [ -f "$LRU_MODEL_CONFIG" ] || return 1
  v="$(awk -v blk="$1:" -v key="$2:" '
    $1 == blk && /^[^[:space:]]/ { f = 1; next }
    f && /^[^[:space:]#]/ { exit }
    f && $1 == key { print $2; exit }
  ' "$LRU_MODEL_CONFIG" 2>/dev/null | tr -d "\"' ")"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}
# ── A PER-SESSION TARGET PIN (2026-09-23) ────────────────────────────────────────────────────────
# "Fable keeps Fable" is the right DEFAULT — a Fable session is usually a frontier-ladder stage-2
# lead, and converting every one on the poller's auto-enqueue would break the ladder fleet-wide.
# It is wrong for ONE session the operator has ruled should move to Opus (2026-09-23: "self-recycle
# our v2.1.280 Fable 5.1 / Opus 5 sessions into v2.1.280 Opus 5.5 sessions" — pane 480 was the only
# live Fable one, and the census called it `current` forever). So the override is per SID, a file
# rather than a flag: the census, the auto-enqueue and the drainer's execution-time re-check all read
# it through this one function, so no request schema and no drain plumbing changes.
#   * The value must be one of the SSOT's two targets (opus_latest, frontier model) — a pin can
#     choose between them, never name an arbitrary id into a launcher.
#   * It expires after LRU_PIN_TTL_MIN (default 1440): a pin left behind must not drag a session the
#     operator later put back on Fable onto Opus a week later.
UPG_PINS="$LRU_STATE/upgrade-target"
lru_pinned_target() { # $1=sid → the pinned model on stdout; rc 1 when no live, valid pin
  local f v
  [ -n "${1:-}" ] || return 1
  f="$UPG_PINS/$1"
  [ -f "$f" ] || return 1
  [ -n "$(find "$f" -mmin -"${LRU_PIN_TTL_MIN:-1440}" 2>/dev/null)" ] || return 1
  v="$(head -1 "$f" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$v" ] || return 1
  if [ "$v" = "$(lru_ssot versions opus_latest)" ] || [ "$v" = "$(lru_ssot frontier_access model)" ]; then
    printf '%s' "$v"; return 0
  fi
  return 1
}
lru_target_model() { # $1=current model [$2=sid] → the model this session should be on
  lru_pinned_target "${2:-}" && return 0
  case "$1" in
    *fable*) lru_ssot frontier_access model ;;      # Fable keeps Fable: a binary-only move
    *)       lru_ssot versions opus_latest ;;       # Opus (and an argv with no --model) → opus_latest
  esac
}

# ── argv parsing: the LAST occurrence wins, as the CLI's own parser does ────────────────────────
# Measured on the fleet: `--effort high --effort max` is a real argv (pane 564). Taking the first
# would relaunch that session one rung down.
# …but ONLY A WELL-FORMED VALUE COUNTS. ps joins argv with spaces, so a positional PROMPT that merely
# mentions `--effort` is indistinguishable from the flag — measured: pane 564's brief mentions
# "--effort (set-teammate-effort.sh", which a bare last-wins read took as its effort. $3 is the
# value's shape (an ERE); a candidate that does not match it is text, not a flag.
lru_flag() { # $1=argv $2=flag $3=value ERE → the value of the LAST well-formed occurrence
  printf '%s\n' "$1" | head -1 | LRU_F="$2" LRU_RE="^(${3:-.+})$" awk '{
    n = split($0, a, " "); v = ""
    for (i = 1; i <= n; i++) {
      c = ""
      if (a[i] == ENVIRON["LRU_F"] && i < n) c = a[i+1]
      else if (index(a[i], ENVIRON["LRU_F"] "=") == 1) c = substr(a[i], length(ENVIRON["LRU_F"]) + 2)
      if (c != "" && c ~ ENVIRON["LRU_RE"]) v = c
    }
    print v }'
}
LRU_RE_MODEL='claude-[a-z0-9][a-z0-9.-]*(\[1m\])?'
LRU_RE_EFFORT='low|medium|high|xhigh|max'
LRU_RE_PERM='default|acceptEdits|plan|bypassPermissions|auto|dontAsk'

# ── is the transcript AT REST — the same rule as handoff-fire.sh's hf_transcript_at_rest ────────
# Duplicated rather than sourced: handoff-fire is a 13k-line script with load-time side effects.
# Both copies are pinned to one fixture set (tests/lr-upgrade.bats + handoff-recycle-same-account).
lru_at_rest() { # $1=transcript → 0 at rest · 1 in flight · 2 unreadable
  local tx="${1:-}" last
  [ -n "$tx" ] && [ -f "$tx" ] && command -v jq >/dev/null 2>&1 || return 2
  last="$(tail -n 400 "$tx" 2>/dev/null \
    | jq -rc 'select((.type=="assistant" or .type=="user") and ((.isSidechain // false)|not))
              | "\(.type) \(.message.stop_reason // "-")"' 2>/dev/null | tail -n 1)"
  [ -n "$last" ] || return 2
  [ "$last" = "assistant end_turn" ] && return 0
  return 1
}

# ── the process snapshot: ONE ps, then every question is asked of the snapshot ──────────────────
# THE SELF-MATCH TRAP (brief item, measured 2026-09-22): `ps … | grep -- "--parent-session-id $sid"`
# lists the grep ITSELF, because ps runs concurrently with it and the pattern is in grep's argv — so
# every session read as a lead. Two independent guards, either sufficient:
#   (a) the snapshot is taken FIRST, into a variable, by a ps with no pattern anywhere near it; the
#       filter that runs afterwards is not in the population it filters;
#   (b) a teammate must BE a claude process — argv[0] ending in /claude or /claude.exe — so a grep,
#       an awk, a shell, or a brief that merely MENTIONS the flag can never qualify.
# Patterns reach awk through the ENVIRONMENT, never argv, as lr_resume_procs does (lr-lib.sh).
# Snapshot line: "<pid> <ppid> <lstart: 5 fields> <args…>". LRU_PS_SNAPSHOT (a file) is the test seam.
lru_snapshot() {
  if [ -n "${LRU_PS_SNAPSHOT:-}" ]; then cat "$LRU_PS_SNAPSHOT" 2>/dev/null; return 0; fi
  TZ=UTC LC_ALL=C ps -axww -o pid=,ppid=,lstart=,args= 2>/dev/null
}
# LSTART DIALECT — MATCH THE PRODUCER (hooks/lib/session-busy.sh _sb_lstart_matches carries the
# measurement). The registry row's lstart is written `TZ=UTC ps -o lstart=` in the WRITER's ambient
# locale; the snapshot is the house canon (TZ=UTC LC_ALL=C). Accept either rendering: both are the
# SAME pid at the SAME instant, so no different start instant can equal the record. A bare `ps`
# renders local time, and measured on this box it convicted EVERY live row as stale (5 h offset).
lru_lstart_matches() { # $1=recorded $2=snapshot rendering $3=pid → 0 same process / 1 not
  local rec cur
  rec="$(printf '%s' "$1" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$rec" ] || return 0                          # never recorded ⇒ nothing to disprove
  [ "$rec" = "$(printf '%s' "$2" | tr -s ' ')" ] && return 0
  [ -n "${LRU_PS_SNAPSHOT:-}" ] && return 1           # a fixture has no second dialect to ask
  cur="$(TZ=UTC ps -o lstart= -p "$3" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$cur" ] && [ "$rec" = "$cur" ]
}
# A PROCESS LINE, NOT A CONTINUATION. ps prints an argv containing a newline RAW (a claude launched
# with a multi-line prompt), so its later lines arrive as bare text — and one that happens to start
# with a number would read as a pid. A real line has a C-locale weekday at $3 and a year at $7.
# shellcheck disable=SC2016  # an awk program, deliberately unexpanded by the shell
LRU_PROC_LINE='$1 ~ /^[0-9]+$/ && $3 ~ /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)$/ && $7 ~ /^[0-9][0-9][0-9][0-9]$/'
lru_snap_args() { # $1=snapshot $2=pid → that pid's argv (its first line)
  printf '%s\n' "$1" | LRU_P="$2" awk "$LRU_PROC_LINE"' && $1 == ENVIRON["LRU_P"] { $1=$2=$3=$4=$5=$6=$7=""; sub(/^ +/, ""); print; exit }'
}
lru_snap_lstart() { # $1=snapshot $2=pid → "Tue Sep 22 06:47:13 2026"
  printf '%s\n' "$1" | LRU_P="$2" awk "$LRU_PROC_LINE"' && $1 == ENVIRON["LRU_P"] { print $3" "$4" "$5" "$6" "$7; exit }'
}
lru_has_live_teammate() { # $1=snapshot $2=lead sid → 0 when a live CLAUDE process names it as parent
  printf '%s\n' "$1" | LRU_PAT="--parent-session-id $2" awk "$LRU_PROC_LINE"' && $8 ~ /(^|\/)claude(\.exe)?$/ && index($0, ENVIRON["LRU_PAT"]) { f = 1 }
    END { exit !f }'
}
# THE BACKGROUND-JOB QUESTION HAS THREE ANSWERS, NOT TWO. A child `zsh -c source …shell-snapshots…`
# of the claude pid is a Bash-tool shell that outlived its turn. Measured 2026-09-22 on the three
# idle 2.1.260 sessions carrying one (480 495 503): every one was a `cc-await-ping` INBOX WATCHER —
# the standard idle wake path, parked by nearly every idle session. Treating it as work would make
# this verb upgrade almost nothing. A watcher is not work: its SIGTERM handler mails WAKE-PATH-DOWN
# with re-arm instructions into the pane's inbox, and the relaunched session drains that mail on the
# turn the relaunch starts. So:
#   none     no job                                            → proceed
#   watcher  every job is a watcher (the job's argv names cc-await-ping and its direct children are
#            cc-await-ping or its `| tail`)                     → proceed; the prompt says re-arm it
#   work     anything else                                     → EXCLUDED (background-job)
# LRU_WATCHER_IS_JOB=1 is the kill switch: every job, watchers included, excludes (the brief's letter).
lru_bg_kind() { # $1=snapshot $2=pid → none | watcher | work
  printf '%s\n' "$1" | LRU_P="$2" LRU_STRICT="${LRU_WATCHER_IS_JOB:-0}" awk "$LRU_PROC_LINE"' {
      par[$1] = $2; a = $0; for (i = 1; i <= 7; i++) sub(/^ *[^ ]+/, "", a); sub(/^ +/, "", a); args[$1] = a; bin[$1] = $8 }
    END {
      kind = "none"
      for (j in par) {
        if (par[j] != ENVIRON["LRU_P"]) continue
        if (bin[j] !~ /(^|\/)(zsh|bash)$/ || index(args[j], "shell-snapshots") == 0) continue
        w = (ENVIRON["LRU_STRICT"] != "1" && index(args[j], "cc-await-ping") > 0)
        if (w) for (c in par) if (par[c] == j && args[c] !~ /cc-await-ping/ && bin[c] !~ /(^|\/)tail$/) w = 0
        if (!w) { kind = "work"; break }
        kind = "watcher"
      }
      print kind
    }'
}

lru_cfg_of() { # $1=account name from the registry → its config dir
  printf '%s/.%s' "${LRU_CFG_ROOT%/}" "$1"
}
lru_transcript() { # $1=cfg $2=sid → path; rc 1 when none
  local f
  for f in "$1"/projects/*/"$2".jsonl; do [ -f "$f" ] && { printf '%s' "$f"; return 0; }; done
  return 1
}

# The composer: read-only kitty RPC through cc-tui.sh.
#   rc 0 empty · 1 occupied (someone's draft) · 2 unknown · 3 THIS RAIL'S OWN abandoned text
# The content read is left in LRU_COMPOSER_TEXT (space-stripped, cc_tui_composer's form).
# LRU_COMPOSER=off skips the read (reported as empty) — for the suite and for a dry run that must
# not touch the terminal; the drive path re-reads regardless, and handoff-fire's own composer gate
# is the backstop at the /exit.
#
# RAIL JUNK (operator ruling 2026-09-22, "zero-human end to end"): pane 405 sat blocked by nothing
# but the prototype's own unsent 'OPUS55-UPGRADE (operator request): relaunch THIS session…' prompt —
# the residue of a cc_tui_submit rc 4. Text a rail typed is not an operator draft. It is recognised
# by an EXACT PREFIX of the space-stripped composer (the form cc_tui_composer returns), never by a
# substring, and only for the markers below; anything else stays `composer-occupied`. The drive
# then files a residue RECEIPT for that exact content, and handoff-fire's composer gate — which
# already scrubs "this rail's OWN abandoned paste" (composer_residue_is_ours) — clears it with its
# own read-back-verified Ctrl-U loop. Nothing here types. LRU_SCRUB_RAIL_JUNK=off: every non-empty
# composer is occupied again.
LRU_RAIL_MARKERS='OPUS55-UPGRADE(
In-placeupgrade:thissessionwasrelaunchedbycc-lrupgrade'
LRU_COMPOSER_TEXT=""
lru_is_rail_junk() { # $1=space-stripped composer content → 0 when it begins with a rail marker
  local m
  [ "${LRU_SCRUB_RAIL_JUNK:-on}" = off ] && return 1
  [ -n "${1:-}" ] || return 1
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$1" in "$m"*) return 0 ;; esac
  done <<EOF
$LRU_RAIL_MARKERS
EOF
  return 1
}
lru_composer() { # $1=pane
  local c
  LRU_COMPOSER_TEXT=""
  [ "${LRU_COMPOSER:-on}" = off ] && return 0
  [ -f "$LRU_TUI_LIB" ] || return 2
  # shellcheck disable=SC1090
  c="$( . "$LRU_TUI_LIB" >/dev/null 2>&1; cc_tui_composer "$1" )" || return 2
  LRU_COMPOSER_TEXT="$c"
  [ -z "$c" ] && return 0
  lru_is_rail_junk "$c" && return 3
  return 1
}
# The receipt handoff-fire's composer gate reads (composer_residue_is_ours): `<ts>\t<content>` in
# the SAME store cc_tui_residue_record writes, keyed on the pane id. Written only for content
# lru_is_rail_junk accepted, and immediately before the recycle that consumes it.
lru_file_rail_receipt() { # $1=pane $2=content
  local d="${CC_COMPOSER_RESIDUE_DIR:-$HOME/.claude/logs/composer-residue}"
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  mkdir -p "$d" 2>/dev/null || return 1
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" > "$d/${1//\//_}"
}

# ── THE SELECTION PREDICATE ──────────────────────────────────────────────────────────────────────
# One row per live registry row. `current` rows are printed too (the dry run is a fleet census).
# Exclusions are checked in order and the FIRST that applies is the disposition, so every skipped
# row names exactly one reason.
lru_census() { # [$1=ref: pane id or sid prefix; empty = all] → TSV rows on stdout; rc 1 none matched
  local ref="${1:-}" snap target_bin f pane pid sid acct cwd lst args rlst bin model tgt eff perm cfg tx disp rows="" n=0
  local sids="" dupsids=""
  snap="$(lru_snapshot)"
  target_bin="$("$LRU_CLAUDE_BIN_CMD" 2>/dev/null || true)"
  [ -n "$target_bin" ] || { lru_say "cannot resolve the current binary ($LRU_CLAUDE_BIN_CMD) — refusing to judge 'current'"; return 2; }
  # pass 1: live rows (pid in the snapshot, lstart agreeing when the row records one)
  for f in "$LRU_REG_DIR"/*.json; do
    [ -f "$f" ] || continue
    pane="$(jq -r '.paneUUID // empty' "$f" 2>/dev/null)"; pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
    [ -n "$pane" ] && [ -n "$pid" ] && [ -n "$sid" ] || continue
    args="$(lru_snap_args "$snap" "$pid")"
    [ -n "$args" ] || continue                                  # not running: not a live row
    rlst="$(jq -r '.lstart // empty' "$f" 2>/dev/null)"
    lst="$(lru_snap_lstart "$snap" "$pid")"
    if ! lru_lstart_matches "$rlst" "$lst" "$pid"; then
      rows="$rows$pane"$'\t'"$sid"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"-"$'\t'"$pid"$'\t'"stale-row"$'\n'
      continue
    fi
    case "$sids" in *" $sid "*) dupsids="$dupsids $sid " ;; esac
    sids="$sids $sid "
    rows="$rows$f"$'\t'"LIVE"$'\n'
  done
  # pass 2: judge each live row
  local out="" line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in *$'\tLIVE') ;; *) out="$out$line"$'\n'; continue ;; esac
    f="${line%%$'\t'*}"
    pane="$(jq -r '.paneUUID' "$f")"; pid="$(jq -r '.pid' "$f")"; sid="$(jq -r '.session_id' "$f")"
    acct="$(jq -r '.account // empty' "$f")"; cwd="$(jq -r '.cwd // empty' "$f")"
    args="$(lru_snap_args "$snap" "$pid")"
    bin="${args%% *}"
    model="$(lru_flag "$args" --model "$LRU_RE_MODEL")"; eff="$(lru_flag "$args" --effort "$LRU_RE_EFFORT")"
    perm="$(lru_flag "$args" --permission-mode "$LRU_RE_PERM")"
    [ -n "$perm" ] || perm=auto
    tgt="$(lru_target_model "$model" "$sid" || true)"
    cfg="$(lru_cfg_of "$acct")"
    if [ -z "$tgt" ]; then disp="no-target-model"
    elif [ "$bin" = "$target_bin" ] && [ "$model" = "$tgt" ]; then disp=current
    elif [ -n "$LRU_SELF_SID" ] && [ "$sid" = "$LRU_SELF_SID" ]; then disp=self
    else
      case " $args " in *" --agent-id "*|*" --agent-id="*) disp=teammate ;; *) disp="" ;; esac
      if [ -z "$disp" ]; then
        case "$dupsids" in *" $sid "*) disp=duplicate ;; esac
      fi
      if [ -z "$disp" ] && lru_has_live_teammate "$snap" "$sid"; then disp=lead-with-teammate; fi
      if [ -z "$disp" ]; then
        tx="$(lru_transcript "$cfg" "$sid" || true)"
        if [ -z "$tx" ]; then disp=no-transcript
        elif ! lru_at_rest "$tx"; then disp=mid-turn
        fi
      fi
      if [ -z "$disp" ] && [ "$(lru_bg_kind "$snap" "$pid")" = work ]; then disp=background-job; fi
      if [ -z "$disp" ]; then
        local crc=0; lru_composer "$pane" || crc=$?
        case "$crc" in 0|3) disp=upgrade ;; 1) disp=composer-occupied ;; *) disp=composer-unknown ;; esac
      fi
    fi
    out="$out$pane"$'\t'"$sid"$'\t'"$bin"$'\t'"${model:--}"$'\t'"${tgt:--}"$'\t'"${eff:--}"$'\t'"$perm"$'\t'"$cfg"$'\t'"${cwd:--}"$'\t'"$pid"$'\t'"$disp"$'\n'
  done <<EOF
$rows
EOF
  # the ref filter, applied to the judged rows so a duplicate is still judged against the fleet
  out="$(printf '%s' "$out" | LRU_REF="$ref" awk -F'\t' 'NF && (ENVIRON["LRU_REF"] == "" || $1 == ENVIRON["LRU_REF"] || index($2, ENVIRON["LRU_REF"]) == 1)' | LC_ALL=C sort -t$'\t' -k1,1n)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# ── THE LAUNCHER — pure ASCII, or refused ────────────────────────────────────────────────────────
# Defect 4: a prompt carrying `—` went through printf %q as $'…\342\200\224…' and a later `sed` in
# handoff-fire (which reads the launcher to extract its tokens) died on "illegal byte sequence".
# The launcher is composed from ASCII-only parts and then CHECKED — a composition rule nothing
# verifies is a comment. The check is byte-level (LC_ALL=C) so it cannot be fooled by a locale.
lru_ascii_only() { # $1=file → 0 pure ASCII / 1 not
  ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$1" 2>/dev/null
}
lru_mint_launcher() { # $1=run dir $2=cfg $3=cwd $4=sid $5=model $6=effort $7=perm $8=admit token → path
  local d="$1" cfg="$2" cwd="$3" sid="$4" model="$5" eff="$6" perm="$7" tok="${8:-}" L sub prompt
  # THE VALUES FIRST, THEN THE FILE. Checking only the file's bytes is locale-dependent: under
  # LC_ALL=C (launchd, CI) printf %q renders a non-ASCII value as $'\342\200\224' — pure ASCII on
  # disk, non-ASCII again the moment the launcher runs. Found by the off-box gate, 2026-09-23.
  if printf '%s' "$d$cfg$cwd$sid$model$eff$perm$tok$LRU_FIRE_RESUME" | LC_ALL=C grep -q '[^ -~]'; then
    lru_say "REFUSED: a launcher value is not pure ASCII (run dir, config dir, cwd, sid, model, effort, mode or token); it would break every sed that reads the launcher"
    return 1
  fi
  mkdir -p "$d" || return 1
  L="$d/launch.sh"
  sub="run:${sid:0:8}:upgrade:$(date -u +%Y%m%dT%H%M%SZ)"
  prompt="In-place upgrade: this session was relaunched by cc-lr upgrade on the current Claude Code binary and model $model (same session, same pane, same account, effort $eff). A background cc-await-ping inbox watcher, if you had one, was ended by the relaunch: re-arm it only if no /goal is live. Continue exactly where you left off; if nothing was pending, reply with one line saying so. $sub"
  {
    printf '#!/bin/bash\n'
    printf '# cc-lr upgrade launcher for %s - regenerable; typed into the pane by handoff-fire.\n' "$sid"
    # shellcheck disable=SC2016  # the launcher expands it at ITS runtime, not here
    printf 'export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"\n'
    printf 'export LR_RUN=%q\n' "$d"
    printf 'export LR_RUN_DIR=%q\n' "$d"
    printf 'export LR_ADMIT_TOKEN=%q\n' "$tok"
    printf 'export LR_SUBMIT_TOKEN=%q\n' "$sub"
    printf 'exec bash %q %q %q %q --model %q --effort %q --permission-mode %q --prompt %q\n' \
      "$LRU_FIRE_RESUME" "$cfg" "$cwd" "$sid" "$model" "$eff" "$perm" "$prompt"
  } > "$L" || return 1
  chmod +x "$L"
  if ! lru_ascii_only "$L"; then
    lru_say "REFUSED: launcher $L is not pure ASCII (a path or value carried a non-ASCII byte); it would break every sed that reads it"
    mv -f "$L" "$L.rejected-non-ascii" 2>/dev/null || true
    return 1
  fi
  printf '%s' "$L"
}

# ── results ──────────────────────────────────────────────────────────────────────────────────────
lru_result() { # $1=sid $2=pane $3=verdict(upgraded|skipped|failed) $4=reason $5=command $6=req id $7=requested_by
  mkdir -p "$UPG_RESULTS" 2>/dev/null || true
  local tmp="$UPG_RESULTS/.upgrade-$1.$$.tmp"
  jq -n --arg sid "$1" --arg pane "$2" --arg v "$3" --arg why "$4" --arg cmd "$5" --arg req "$6" \
        --arg by "$7" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{sid:$sid, pane:$pane, verdict:$v, reason:$why, command:$cmd, req_id:$req, requested_by:$by, ts:$ts}' \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$UPG_RESULTS/upgrade-$1.json"
  printf '%s\t%s\t%s\t%s\n' "$2" "${1:0:8}" "$3" "$4"
  case "$7" in ''|'?'|-) ;; *)
    [ -x "$LRU_NOTIFY_BIN" ] && "$LRU_NOTIFY_BIN" "$7" "CC-LR-UPGRADE pane $2 (${1:0:8}): $3 - $4${5:+ | run: $5}" >/dev/null 2>&1 || true ;;
  esac
}

# The capacity decision, BEFORE anything is typed (defect 3). The probe charges nothing; the mint
# turns its admission into a one-shot token the launcher redeems, so the gate in the pane is the
# SAME decision rather than a second one taken 20 s later under different load.
LRU_TOKEN="" LRU_CAP_WHY=""
lru_capacity() { # $1=sid → 0 admitted (LRU_TOKEN may be set) / 9 refused (LRU_CAP_WHY)
  local rc=0
  LRU_TOKEN="" LRU_CAP_WHY=""
  if [ "${LRU_CAPACITY:-on}" = off ]; then return 0; fi
  if [ ! -f "$LRU_CA_LIB" ]; then LRU_CAP_WHY="capacity-admit.sh unreachable - admitting UNGATED"; return 0; fi
  # shellcheck disable=SC1090
  . "$LRU_CA_LIB" 2>/dev/null || { LRU_CAP_WHY="capacity-admit.sh failed to load - admitting UNGATED"; return 0; }
  if command -v lr_capacity_probe_corrected >/dev/null 2>&1; then
    lr_capacity_probe_corrected lr-upgrade "in-place upgrade of ${1:0:8}" 2>/dev/null || rc=$?
  elif command -v cc_capacity_probe >/dev/null 2>&1; then
    cc_capacity_probe lr-upgrade "in-place upgrade of ${1:0:8}" 2>/dev/null || rc=$?
  fi
  LRU_CAP_WHY="$(cc_capacity_admit_reason 2>/dev/null || true)"
  [ "$rc" = 0 ] || return 9
  command -v cc_capacity_token_mint >/dev/null 2>&1 && LRU_TOKEN="$(cc_capacity_token_mint "$1" 2>/dev/null || true)"
  return 0
}

# THE UPGRADE IS THE PROCESS, NOT THE CONVERSATION. Decided by what now runs: a live
# `--resume <sid>` leaf whose binary is the target and whose --model is the target. Whether the
# relaunched session then ANSWERS the one-line confirmation prompt is a separate, weaker fact —
# measured 2026-09-22 on the first field run: 2 of 3 relaunches came up correctly on 2.1.280 and
# lr-fire-resume's prompt injection reported FAILED:submit in both (~25-column split panes, where
# the composer read-back is width-dependent — the same class as the cc_tui_submit rc 4 failures
# earlier that day). Reporting those as "failed" named a completed move a failure.
lru_resumed_on() { # $1=sid $2=binary $3=model → 0 when a live --resume <sid> leaf runs both
  local p a
  command -v lr_resume_procs >/dev/null 2>&1 || return 1
  for p in $(lr_resume_procs "$1" 2>/dev/null); do
    a="$(ps -o args= -p "$p" 2>/dev/null || true)"
    [ "${a%% *}" = "$2" ] || continue
    [ -z "${3:-}" ] || [ "$(lru_flag "$a" --model "$LRU_RE_MODEL")" = "$3" ] || continue
    return 0
  done
  return 1
}
# lr-fire-resume's own last word about the confirmation prompt, from the run's state log.
lru_submit_state() { # $1=run dir → last state line's state, empty when none
  [ -f "$1/events.jsonl" ] || return 0
  jq -r '.state // empty' "$1/events.jsonl" 2>/dev/null | tail -n 1
}

# ── drive ONE session ────────────────────────────────────────────────────────────────────────────
lru_drive() { # $1=sid $2=pane $3=requested_by $4=req id → prints the result row; rc 0 upgraded · 1 failed · 3 skipped
  local sid="$1" pane="$2" by="${3:-?}" req="${4:-}" row disp bin model tgt eff perm cfg cwd pid
  local mutex run L t0 hflog hrc=0 i cmd target_bin sock binlabel st
  mutex="$UPG_MUTEX_DIR/$sid.active"
  mkdir -p "$UPG_MUTEX_DIR" 2>/dev/null || true
  if ! mkdir "$mutex" 2>/dev/null; then
    lru_result "$sid" "$pane" skipped "busy: another run holds $mutex" "" "$req" "$by"; return 3
  fi
  printf '{"sid":"%s","pane":"%s","pid":%d,"by":"lr-upgrade"}\n' "$sid" "$pane" "$$" > "$mutex/holder" 2>/dev/null || true
  # shellcheck disable=SC2064  # expand now: the mutex path is fixed for this call
  trap "rm -rf '$mutex' 2>/dev/null" RETURN

  # RE-CHECK AT EXECUTION TIME. The request was judged when it was written; the fleet has moved since.
  row="$(lru_census "$pane" 2>/dev/null | LRU_S="$sid" awk -F'\t' '$2 == ENVIRON["LRU_S"]' | head -1)"
  if [ -z "$row" ]; then
    lru_result "$sid" "$pane" skipped "not live: no registry row binds pane $pane to ${sid:0:8} now" "" "$req" "$by"; return 3
  fi
  IFS=$'\t' read -r _ _ bin model tgt eff perm cfg cwd pid disp <<EOF
$row
EOF
  if [ "$disp" != upgrade ]; then
    lru_result "$sid" "$pane" skipped "$disp" "" "$req" "$by"; return 3
  fi
  target_bin="$("$LRU_CLAUDE_BIN_CMD" 2>/dev/null || true)"

  if ! lru_capacity "$sid"; then
    lru_result "$sid" "$pane" skipped "capacity: ${LRU_CAP_WHY:-refused} (nothing typed; re-run later)" "cc-lr upgrade $pane" "$req" "$by"; return 3
  fi
  run="$UPG_RUNS/${sid:0:8}-$(date -u +%Y%m%dT%H%M%SZ)"
  [ -n "$eff" ] && [ "$eff" != - ] || eff=high
  L="$(lru_mint_launcher "$run" "$cfg" "$cwd" "$sid" "$tgt" "$eff" "$perm" "$LRU_TOKEN")" || {
    lru_result "$sid" "$pane" failed "could not mint an ASCII-only launcher in $run (nothing typed)" "" "$req" "$by"; return 1; }
  cmd="cd $(printf %q "$cwd") && bash $(printf %q "$L")"
  hflog="$run/handoff-fire.log"
  # +1 RAIL JUNK: re-read the composer NOW (the census read may be minutes old). Rail junk gets a
  # receipt, so handoff-fire's composer gate scrubs it instead of deferring; anything else that
  # appeared since the census is somebody's draft and stops this session here, untouched.
  local jrc=0; lru_composer "$pane" || jrc=$?
  case "$jrc" in
    0) ;;
    3) lru_file_rail_receipt "$pane" "$LRU_COMPOSER_TEXT" \
         || { lru_result "$sid" "$pane" skipped "composer holds rail junk but its receipt could not be filed (nothing typed)" "" "$req" "$by"; return 3; } ;;
    1) lru_result "$sid" "$pane" skipped "composer-occupied (appeared after the census; nothing typed)" "" "$req" "$by"; return 3 ;;
    *) lru_result "$sid" "$pane" skipped "composer-unknown (unreadable at the last read; nothing typed)" "" "$req" "$by"; return 3 ;;
  esac
  t0="$(date -u +%FT%T)"
  # THE RELAUNCH. handoff-fire's remote form, same-account class: it re-proves the binding, the pin,
  # the account, the absence of a tombstone and the transcript at rest, gates the composer, re-reads
  # the transcript immediately before /exit, types /exit, waits for the shell and types the launcher.
  ( cd "$cwd" 2>/dev/null || cd /; CLAUDE_CONFIG_DIR="$cfg" bash "$LRU_HF_BIN" --recycle --same-account \
      --source-pane "$pane" --source-session "$sid" --resume-launcher "$L" --resume-cfg "$cfg" \
      --resume-cwd "$cwd" --await ) > "$hflog" 2>&1 || hrc=$?
  binlabel="$(printf '%s\n' "$target_bin" | awk -F/ '{ for (i = 1; i <= NF; i++) if ($i ~ /^\.claude-/) { print $i; exit } ; print $NF }')"
  if [ "$hrc" = 0 ] && lru_resumed_on "$sid" "$target_bin" "$tgt"; then
    lru_result "$sid" "$pane" upgraded "now $tgt on $binlabel (effort $eff); confirmed by a fresh assistant turn" "" "$req" "$by"; return 0
  fi
  # NOT ENGAGED. Which side of the /exit are we on? The old process is the discriminator.
  if kill -0 "$pid" 2>/dev/null; then
    lru_result "$sid" "$pane" skipped "handoff-fire refused before /exit (rc $hrc): $(grep -m1 '^!!' "$hflog" 2>/dev/null | cut -c1-200) - session untouched" "" "$req" "$by"; return 3
  fi
  # The old process is gone. Either the relaunch is up (slow engagement) or the pane is at a bare
  # shell. NEVER leave it there: retype the launcher, bounded. capacity-admit admits a given resume
  # after 3 refusals on one budget key (this run's dir), so ≤5 tries is enough and cannot loop.
  i=0
  while ! lru_resumed_on "$sid" "$target_bin" "$tgt"; do
    [ "$i" -ge "$LRU_RETYPE_MAX" ] && break
    i=$((i + 1))
    sock="$(command -v lr_kitty_socket >/dev/null 2>&1 && lr_kitty_socket 2>/dev/null || true)"
    CC_TERM_KITTY_TO="${sock:-${CC_TERM_KITTY_TO:-}}" "$LRU_IT2_BIN" session run -s "$pane" "cd $(printf %q "$cwd") && nocorrect bash $(printf %q "$L")" >/dev/null 2>&1 || true
    local w=0
    while [ "$w" -lt 30 ]; do lru_resumed_on "$sid" "$target_bin" "$tgt" && break; sleep 2; w=$((w + 2)); done
    lru_resumed_on "$sid" "$target_bin" "$tgt" || sleep "$LRU_RETYPE_GAP_S"
  done
  if ! lru_resumed_on "$sid" "$target_bin" "$tgt"; then
    lru_result "$sid" "$pane" failed "pane left at a bare shell after $i retype(s) (handoff-fire rc $hrc; log $hflog)" "$cmd" "$req" "$by"; return 1
  fi
  # RELAUNCHED ON THE TARGET — the upgrade is done. Now the confirmation turn, bounded, and cut
  # short the moment lr-fire-resume itself records that its prompt never reached the transcript.
  local waited=0 retyped=""
  [ "$i" -gt 0 ] && retyped="; ${i} retype(s) after handoff-fire's watcher declined to type"
  while :; do
    if command -v lr_engaged_after >/dev/null 2>&1 && lr_engaged_after "$cfg" "$sid" "$t0"; then
      lru_result "$sid" "$pane" upgraded "now $tgt on $binlabel (effort $eff); confirmed by a fresh assistant turn$retyped" "" "$req" "$by"; return 0
    fi
    st="$(lru_submit_state "$run")"
    case "$st" in FAILED:submit|FAILED*) break ;; esac
    [ "$waited" -lt "$LRU_ENGAGE_S" ] || break
    sleep 5; waited=$((waited + 5))
  done
  lru_result "$sid" "$pane" upgraded "now $tgt on $binlabel (effort $eff)$retyped; confirmation UNCONFIRMED (lr-fire-resume: ${st:-no state}) - the session is idle on the new binary; if its composer still shows the upgrade prompt, press Enter in pane $pane to confirm or Ctrl-U to discard it" "" "$req" "$by"
  return 0
}

# ── the serial drain ─────────────────────────────────────────────────────────────────────────────
# ONE AT A TIME, by construction: a lock dir with a holder pid, stolen only from a dead holder.
lru_drain() {
  local q sid pane by req n=0
  mkdir -p "$UPG_QUEUE" "$UPG_CLAIMED" 2>/dev/null || true
  if ! mkdir "$UPG_LOCK" 2>/dev/null; then
    local hp; hp="$(cat "$UPG_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then lru_say "drain already running (pid $hp)"; return 0; fi
    rm -rf "$UPG_LOCK"; mkdir "$UPG_LOCK" 2>/dev/null || { lru_say "could not take $UPG_LOCK"; return 2; }
  fi
  echo "$$" > "$UPG_LOCK/pid"
  # shellcheck disable=SC2064
  trap "rm -rf '$UPG_LOCK'" EXIT
  while :; do
    # shellcheck disable=SC2012  # names are ours (cc-lr-upgrade-<uuid>.json); ls -tr is the mtime order
    q="$(ls -1tr "$UPG_QUEUE"/*.json 2>/dev/null | head -1)"
    [ -n "$q" ] || break
    sid="$(jq -r '.sid // empty' "$q" 2>/dev/null)"; pane="$(jq -r '.source_pane // empty' "$q" 2>/dev/null)"
    by="$(jq -r '.requested_by // "?"' "$q" 2>/dev/null)"; req="$(jq -r '.req_id // empty' "$q" 2>/dev/null)"
    mv -f "$q" "$UPG_CLAIMED/" 2>/dev/null || rm -f "$q"
    if [ -z "$sid" ] || [ -z "$pane" ]; then lru_say "malformed request $q (no sid/pane) - dropped to claimed/"; continue; fi
    [ "$n" -gt 0 ] && sleep "$LRU_GAP_S"
    lru_drive "$sid" "$pane" "$by" "$req" || true
    n=$((n + 1))
  done
  lru_say "drain done: $n session(s)"
}

# ── +2 THE AUTO-TRIGGER (operator ruling 2026-09-22: zero-human, end to end) ─────────────────────
# Called by the reset poller every tick. When a live session's binary or model differs from the
# launcher pin + SSOT, it is queued like any `cc-lr upgrade` request; the ONE serial drainer then
# re-judges it, probes capacity and relaunches it — one at a time. A model activation therefore
# converges the fleet as sessions go idle, with no invocation at all; a session skipped this tick
# (mid-turn, a lead whose teammate is live) is simply re-judged on the next.
# QUEUE-EMPTY ONLY: nothing is added while the queue holds work or a drainer runs, so a slow drain
# can never stack duplicate requests behind itself.
# KILL SWITCHES (either): LR_UPGRADE_AUTO=off · the file $LRU_STATE/upgrade-auto.off
lru_auto_enqueue() { # → prints one line per queued sid; rc 0 always
  local census hp q n=0 p s d req dest tmp
  [ "${LR_UPGRADE_AUTO:-on}" = off ] && { lru_say "auto: off (LR_UPGRADE_AUTO=off)"; return 0; }
  [ -e "$LRU_STATE/upgrade-auto.off" ] && { lru_say "auto: off ($LRU_STATE/upgrade-auto.off)"; return 0; }
  for q in "$UPG_QUEUE"/*.json; do [ -f "$q" ] && { lru_say "auto: queue not empty - nothing added"; return 0; }; done
  hp="$(cat "$UPG_LOCK/pid" 2>/dev/null || true)"
  if [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then lru_say "auto: drainer running (pid $hp) - nothing added"; return 0; fi
  census="$(lru_census "" 2>/dev/null)" || return 0
  mkdir -p "$UPG_QUEUE" 2>/dev/null || return 0
  while IFS=$'\t' read -r p s _ _ _ _ _ _ _ _ d; do
    [ "$d" = upgrade ] || continue
    req="${s:0:8}-$(date +%s)-auto"
    tmp="$UPG_QUEUE/.auto-$s.$$.tmp"; dest="$UPG_QUEUE/auto-upgrade-$s.json"
    jq -n --arg sid "$s" --arg pane "$p" --arg req "$req" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{kind:"upgrade", sid:$sid, source_pane:$pane, requested_by:"poller-auto", req_id:$req, ts:$ts, origin_class:"lr-upgrade-auto"}' \
      > "$tmp" 2>/dev/null && mv -f "$tmp" "$dest" 2>/dev/null && { printf '%s\t%s\n' "$p" "$s"; n=$((n + 1)); }
  done <<EOF
$census
EOF
  lru_say "auto: $n session(s) queued"
  return 0
}

lru_load_libs() {
  # shellcheck disable=SC1090
  [ -f "$LRU_LR_LIB" ] && . "$LRU_LR_LIB" 2>/dev/null
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # launchd hands us /usr/bin:/bin:/usr/sbin:/sbin; jq, it2 and timeout live elsewhere.
  export PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  lru_load_libs
  case "${1:-}" in
    --census) shift; [ "${1:-}" = --all ] && shift; lru_census "${1:-}"; exit $? ;;
    --drive)  [ $# -ge 3 ] || { lru_say "usage: --drive <sid> <pane> [--requested-by P] [--req-id ID]"; exit 3; }
              _s="$2"; _p="$3"; shift 3; _by="?"; _rq=""
              while [ $# -gt 0 ]; do case "$1" in
                --requested-by) [ $# -ge 2 ] || exit 3; _by="$2"; shift 2 ;;
                --req-id) [ $# -ge 2 ] || exit 3; _rq="$2"; shift 2 ;;
                *) lru_say "unknown arg $1"; exit 3 ;; esac; done
              lru_drive "$_s" "$_p" "$_by" "$_rq"; exit $? ;;
    --pin-target) # <sid> <model|opus|fable> → write the per-session pin; `--pin-target <sid> clear` removes it
              [ $# -ge 3 ] || { lru_say "usage: --pin-target <sid> <opus|fable|model id|clear>"; exit 3; }
              case "$2" in *[!0-9a-f-]*|'') lru_say "--pin-target wants a full session uuid, got '$2'"; exit 3 ;; esac
              case "$3" in
                clear) rm -f "$UPG_PINS/$2"; lru_say "pin cleared for ${2:0:8}"; exit 0 ;;
                opus)  _m="$(lru_ssot versions opus_latest)" ;;
                fable) _m="$(lru_ssot frontier_access model)" ;;
                *)     _m="$3" ;;
              esac
              mkdir -p "$UPG_PINS" || exit 2
              printf '%s\n' "$_m" > "$UPG_PINS/$2.tmp" && mv -f "$UPG_PINS/$2.tmp" "$UPG_PINS/$2" || exit 2
              lru_pinned_target "$2" >/dev/null || { rm -f "$UPG_PINS/$2"; lru_say "REFUSED: '$_m' is neither the SSOT opus_latest nor the frontier model"; exit 2; }
              lru_say "pinned ${2:0:8} → $_m for ${LRU_PIN_TTL_MIN:-1440} min; the poller's auto-enqueue moves it once idle"; exit 0 ;;
    --drain)  lru_drain; exit $? ;;
    --auto-enqueue) lru_auto_enqueue; exit $? ;;
    *) lru_say "usage: --census [--all|<ref>] | --drive <sid> <pane> | --pin-target <sid> <model> | --drain | --auto-enqueue"; exit 3 ;;
  esac
fi
