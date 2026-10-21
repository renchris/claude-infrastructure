#!/usr/bin/env bash
# restore-note.sh — recovery delivery for a restored session (W3 P4, 2026-10-05; plan
# docs/research/session-durability-2026-10/W3-build-plan.md § P4 and § Amendment B).
#
# WHY: on 2026-10-01 a restore typed a recovery prompt into 31 panes. 30 did not submit, and the
# bare-CR pass that followed submitted 28 of them and spent 6.8M tokens, mostly on "nothing
# pending". Typing is the wrong transport and "every session" is the wrong audience. So:
#
#   TIER 1, every restored session: an INBOX NOTE saying what died with the old process. It costs no
#     turn. hooks/mailbox-drain.sh session-start hands it to the session as context at resume.
#   TIER 2, only a session with real open work (INTERRUPTED or WAKE-LOST) on an account with quota:
#     the recovery prompt as a LAUNCH ARGUMENT (`claude --resume <sid> "<prompt>"`, through
#     reso-resume-one --prompt-file). Nothing is typed. Piloted 2026-10-05 in a private tmux server:
#     one user record with the nonce, an assistant reply 6 s later.
#   FALLBACK, a prompt whose nonce never reached the transcript: bin/cc-wake (the session's own
#     messaging socket), then a verified paste. Never a blind CR, and a send's rc 0 is never taken
#     as submitted: the transcript or the inbox receipt decides.
#
#   rn_cut_phrase <restart|crash|reboot> <epoch>      "Kitty was restarted at 13:29" …
#   rn_lost_phrase <lost.json> <sid>                  what died, as one clause ("" when nothing)
#   rn_advice <lost.json> <sid>                       the per-kind instructions ("" when none apply)
#   rn_reason_phrase <lost.json> <sid>                why this session is woken although nothing it
#                                                     ran died: owner, promise, unblocked, mail ("" if none)
#   rn_note_text <kind> <epoch> <lost.json> <sid>     the whole tier-1 note, one line
#   rn_send_note <sid> <text>                         cc-notify --mailbox-only --no-wake; rc is its rc
#   rn_nudge_wanted <verdict> <sid> <exhausted-sids>  rc 0 when this row gets a prompt file
#   rn_prompt_text <kind> <epoch> <lost.json> <sid> <verdict> <nonce>
#   rn_write_prompt <dir> <sid> <text>                writes <dir>/<sid>.txt, prints the path
#   rn_nonce                                          R-<8 hex>
#   rn_confirm <sid> <nonce> [cwd]                    prints "user=N assistant=N"; rc 0 confirmed ·
#                                                     1 submitted, no reply yet · 2 not submitted
#   rn_fallback <sid> <prompt-file> <nonce> [cwd]     prints "verdict=<…> via=<…>"; rc 0 delivered
#   (cwd, the row's worktree, lets the transcript be found by its path instead of by a glob)
#
# The lost items come from cc-resume-classify.py --lost-json, which reads the transcript and the
# heartbeat's hb.bg.tsv as they stood at the cut. Nothing here reads live state to decide what was lost.
#
# Off switch: CC_RESTORE_NUDGE=off — no prompt file and no fallback; the notes still go out.
# /bin/bash 3.2 safe: launchd runs boot-resume.sh. Sourced: defines functions only.
# Seams: CC_NOTIFY_BIN · CC_WAKE_BIN · CC_RESTORE_PASTE_CMD · CC_REGISTRY_DIR · CC_RESTORE_PROJECT_ROOTS ·
#   CC_RESTORE_WAKE_WAIT_S · CC_RESTORE_NOTE_MAX (items named per kind, default 4) · CC_RESTORE_TX_CACHE

# Under a bats harness an unset seam never falls through to the real tool: a test once reached the
# live kitty that way (1deb094d2; restore-heartbeat.sh carries the same guard).
_rn_under_bats() { [ -n "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; }

# This file's real directory. ~/.claude/scripts/lib/ holds per-file symlinks into the checkout, so a
# path derived from the unresolved name would point into ~/.claude, where bin/ and handoff-fire.sh
# are not siblings in the same way. Resolve the links first (no `readlink -f`: BSD has none).
_rn_self_dir() {
  local p="${BASH_SOURCE[0]}" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  cd "$(dirname "$p")" 2>/dev/null && pwd
}

_rn_bin() { # <override> <name> → an executable path, or ""
  local c
  if [ -n "$1" ] || _rn_under_bats; then
    [ -n "$1" ] && [ -x "$1" ] && printf '%s' "$1"
    return 0
  fi
  for c in "$1" "$HOME/.claude/bin/$2" "$(_rn_self_dir)/../../bin/$2"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  command -v "$2" 2>/dev/null || true
}

rn_nonce() { printf 'R-%s' "$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"; }

rn_cut_phrase() { # <restart|crash|reboot> <epoch>
  local at; at="$(date -r "$2" +%H:%M 2>/dev/null || printf '?')"
  case "$1" in
    restart) printf 'Kitty was restarted at %s' "$at" ;;
    crash)   printf 'Kitty was lost in a crash at %s' "$at" ;;
    *)       printf 'The Mac rebooted at %s' "$at" ;;
  esac
}

# One clause naming what died, grouped by kind. Each kind names at most CC_RESTORE_NOTE_MAX items
# and counts the rest, so one busy session cannot turn the note into a page.
rn_lost_phrase() { # <lost.json> <sid>
  [ -f "$1" ] || return 0
  jq -r --arg sid "$2" --argjson max "${CC_RESTORE_NOTE_MAX:-4}" '
    def short($n): gsub("[[:space:]]+"; " ") | if length > $n then .[0:$n] + "…" else . end;
    def named(f): (map(f) | .[0:$max] | join("; ")) + (if length > $max then "; +\(length - $max) more" else "" end);
    def n($one; $many): if length == 1 then $one else "\(length) \($many)" end;
    (.sessions[$sid].items // []) as $i
    | [ ($i | map(select(.kind == "shell")) | select(length > 0)
          | n("a background shell"; "background shells") + " (" + named((.task_id // "?") + ": " + ((.detail // "") | short(70))) + ")"),
        ($i | map(select(.kind == "watcher")) | select(length > 0)
          | n("an inbox watcher this session armed"; "inbox watchers this session armed") + " (cc-await-ping)"),
        ($i | map(select(.kind == "agent")) | select(length > 0)
          | n("a background subagent"; "background subagents") + " (" + named((.detail // "?") | short(50)) + ")"),
        ($i | map(select(.kind == "workflow")) | select(length > 0)
          | n("a Workflow run"; "Workflow runs") + " (" + named(if .run_id then "\(.run_id): resume it with Workflow({resumeFromRunId: \"\(.run_id)\"})" else "task \(.task_id // "?"), run id not recorded" end) + ")"),
        ($i | map(select(.kind == "monitor")) | select(length > 0)
          | n("a Monitor"; "Monitors") + " (" + named("task \(.task_id // "?"): " + ((.detail // "") | short(50))) + ")"),
        ($i | map(select(.kind == "journal")) | select(length > 0) | .[0]
          | "subagent or workflow work still writing its journal" + (if ((.run_ids // []) | length) > 0 then " (" + ((.run_ids // []) | map("\(.): Workflow({resumeFromRunId: \"\(.)\"})") | join("; ")) + ")" else "" end)),
        ($i | map(select(.kind == "ship")) | select(length > 0) | "a ship-land that was running"),
        ($i | map(select(.kind == "goal")) | select(length > 0) | .[0]
          | "a /goal that was live and not yet met (" + ((.detail // "") | short(120)) + ")"),
        ($i | map(select(.kind == "teammate")) | select(length > 0)
          | n("an Agent Teams member"; "Agent Teams members") + " (" + named(.detail // "?") + ")"),
        ($i | map(select(.kind == "browser")) | select(length > 0)
          | n("an agent-browser session"; "agent-browser sessions") + " (" + named((.detail // "?") + (if (.url // "") != "" then " at \(.url)" else "" end)) + ")"),
        ($i | map(select(.kind == "port")) | select(length > 0)
          | "listening ports " + (map(.detail) | join(" ")) + " (dev servers under this session)")
      ] | join(", ")' "$1" 2>/dev/null
}

# The instructions that only apply when their kind was lost (amendment B gaps 10, 12, 13, 15).
rn_advice() { # <lost.json> <sid>
  [ -f "$1" ] || return 0
  jq -r --arg sid "$2" '
    (.sessions[$sid].items // [] | map(.kind)) as $k
    | [ (if ($k | index("ship")) then "A ship-land was in flight: check git ls-tree origin/main before landing again." else empty end),
        (if ($k | index("watcher")) then "Re-arm cc-await-ping unless a /goal is live." else empty end),
        (if ($k | index("teammate")) then "The Agent Teams members were not respawned: /limit-recover covers the Teams respawn." else empty end)
      ] | join(" ")' "$1" 2>/dev/null
}

# Why a session is woken when nothing it ran died: the classifier's reason kinds (cc-resume-classify.py
# REASONS TO WAKE, 2026-10-21). The prompt quotes the reason itself, so the session acts on what it
# promised, the row the reboot unblocked, or the mail it was sent, rather than on a generic "carry on".
rn_reason_phrase() { # <lost.json> <sid>
  [ -f "$1" ] || return 0
  jq -r --arg sid "$2" '
    def short($n): gsub("[[:space:]]+"; " ") | if length > $n then .[0:$n] + "…" else . end;
    (.sessions[$sid].items // []) as $i
    | [ ($i | map(select(.kind == "owner")) | select(length > 0)
          | "You ran the reboot prep for this restart, so its follow-up is yours."),
        ($i | map(select(.kind == "promise")) | select(length > 0) | .[0]
          | "Before the restart you said: \"" + ((.detail // "") | short(240)) + "\" Do that now."),
        ($i | map(select(.kind == "unblocked")) | .[]
          | "Backlog row \(.id // "?") (" + ((.detail // "") | short(120)) + ") was blocked until `"
            + ((.until // "") | short(120)) + "` passed, and it passes now: the row is unblocked and yours to finish."),
        ($i | map(select(.kind == "mail")) | select(length > 0) | .[0]
          | ((.count // 1) == 1) as $one
          | (if $one then "An unread inbox message is" else "\(.count) unread inbox messages are" end)
            + " waiting for you (newest from \(.from // "?"): \"" + ((.detail // "") | short(160)) + "\"); "
            + (if $one then "read it and act on it." else "read them and act on them." end))
      ] | join(" ")' "$1" 2>/dev/null
}

rn_note_text() { # <kind> <epoch> <lost.json> <sid>
  local lost advice
  lost="$(rn_lost_phrase "$3" "$4")"; advice="$(rn_advice "$3" "$4")"
  printf '[restore] %s. This session was resumed in full. ' "$(rn_cut_phrase "$1" "$2")"
  if [ -n "$lost" ]; then
    printf 'These died with the old process: %s. If any of them still matters, re-run it from disk state; otherwise carry on.' "$lost"
  else
    printf 'Nothing it had running is recorded as lost; carry on.'
  fi
  [ -n "$advice" ] && printf ' %s' "$advice"
  return 0
}

# --mailbox-only: a record, no liveness verdict (the session is not up yet). --no-wake: since
# f37f2be9a cc-notify wakes an idle pane by default, and a note must never cost a turn.
rn_send_note() { # <sid> <text>
  local nb; nb="$(_rn_bin "${CC_NOTIFY_BIN:-}" cc-notify)"
  [ -n "$nb" ] || { echo "restore-note: cc-notify not found — no note for $1" >&2; return 127; }
  "$nb" --mailbox-only --no-wake --from boot-resume "$1" "$2" >/dev/null 2>&1
}

# A prompt costs a turn, so it needs evidence of open work AND an account that can run the turn.
# Only the wake verdicts qualify (prompting every verdict was the 2026-08-24 defect): a reason to wake
# (owner, promise, unblocked, mail) reaches here as WAKE-LOST, and RETIRED, a session that was closing
# itself, never gets a prompt.
rn_nudge_wanted() { # <verdict> <sid> <space-separated exhausted sids>
  [ "${CC_RESTORE_NUDGE:-on}" != off ] || return 1
  case "$1" in INTERRUPTED|WAKE-LOST) ;; *) return 1 ;; esac
  case " $3 " in *" $2 "*) return 1 ;; esac
  return 0
}

# C2-restore-command.md §2.7's text. An INTERRUPTED row is told its turn was cut and to run
# /limit-recover; a WAKE-LOST row finished its turn, so it is told what was lost instead, and why it is
# woken when the reason is not a loss (rn_reason_phrase).
rn_prompt_text() { # <kind> <epoch> <lost.json> <sid> <verdict> <nonce>
  local lost advice why
  lost="$(rn_lost_phrase "$3" "$4")"; advice="$(rn_advice "$3" "$4")"; why="$(rn_reason_phrase "$3" "$4")"
  printf '[restore] %s. This session was resumed in full: same session id, account, model and effort. ' "$(rn_cut_phrase "$1" "$2")"
  printf 'This message comes from the restore tool, not from the operator. '
  if [ "$5" = INTERRUPTED ]; then
    if [ -n "$lost" ]; then printf 'These ran under the old process and died with it: %s, and your last turn was cut off mid-way. ' "$lost"
    else printf 'Your last turn was cut off mid-way. '; fi
    [ -n "$why" ] && printf '%s ' "$why"
    printf 'Run /limit-recover now. '
  else
    if [ -n "$lost" ] || [ -z "$why" ]; then printf 'These ran under the old process and died with it: %s. ' "${lost:-nothing recorded}"; fi
    [ -n "$why" ] && printf '%s ' "$why"
  fi
  printf 'Read finished results from disk, re-run only what is incomplete, and re-arm a watcher or Monitor only if you still need it and no /goal is live. '
  [ -n "$advice" ] && printf '%s ' "$advice"
  printf 'Then continue the task you were on; do not start new work. If nothing was pending, reply with one line saying so. (restore ref %s)' "$6"
}

rn_write_prompt() { # <dir> <sid> <text> → the path
  mkdir -p "$1" 2>/dev/null || return 1
  printf '%s\n' "$3" > "$1/.$2.txt.tmp" 2>/dev/null && mv -f "$1/.$2.txt.tmp" "$1/$2.txt" 2>/dev/null || return 1
  printf '%s' "$1/$2.txt"
}

# FINDING A TRANSCRIPT WITHOUT A GLOB (R6, 2026-10-21). This used to glob every project dir of every
# store on every call: about 73,000 dirs, and ~/.claude-next/projects is a symlink to
# ~/.claude/projects, so that store was scanned twice. At restore load the same glob took 24-46 s, and
# the confirm loop calls this for every prompted row on every round. Now:
#   1. each store root once, by its real path (_rn_roots);
#   2. the direct path, <root>/<slug>/<sid>.jsonl, for every project slug known for the session: the
#      slug of the cwd the caller passes (the row's worktree, / and . turned into -, as
#      restore-heartbeat.sh _hb_transcript does) and the slugs a fallback glob found before, cached per
#      session. A slug, not a path, is cached, so a session the restore relaunched on another account
#      is still found: its new transcript sits under the same slug in another root;
#   3. the glob, only when no direct path exists.
# The newest file wins, as before.
_rn_roots() { # → each project root once, by real path
  local d r seen=" "
  # shellcheck disable=SC2086  # CC_RESTORE_PROJECT_ROOTS is an intentional space-separated dir list
  for d in ${CC_RESTORE_PROJECT_ROOTS:-"$HOME"/.claude/projects "$HOME"/.claude-*/projects}; do
    [ -d "$d" ] || continue
    r="$(cd "$d" 2>/dev/null && pwd -P)" || continue
    case "$seen" in *" $r "*) continue ;; esac
    seen="$seen$r "
    printf '%s\n' "$r"
  done
}

_rn_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

_rn_transcript() { # <sid> [cwd] → the newest transcript of that session across the account stores
  local sid="$1" cwd="${2:-}" cache roots slugs d s f best="" bm=0 m
  cache="${CC_RESTORE_TX_CACHE:-${TMPDIR:-/tmp}/cc-restore-tx-$(id -u)}"
  roots="$(_rn_roots)"
  [ -n "$cwd" ] && slugs="$(printf '%s' "$cwd" | tr '/.' '--')"
  [ -s "$cache/$sid" ] && slugs="$(printf '%s\n%s' "${slugs:-}" "$(cat "$cache/$sid" 2>/dev/null)")"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    while IFS= read -r s; do
      f="$d/$s/$sid.jsonl"
      [ -n "$s" ] && [ -f "$f" ] || continue
      m="$(_rn_mtime "$f")"; [ "$m" -gt "$bm" ] && { bm="$m"; best="$f"; }
    done <<EOF
${slugs:-}
EOF
  done <<EOF
$roots
EOF
  if [ -z "$best" ]; then
    slugs=""
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      for f in "$d"/*/"$sid".jsonl; do
        [ -f "$f" ] || continue
        s="${f%/*}"; slugs="$slugs${s##*/}
"
        m="$(_rn_mtime "$f")"; [ "$m" -gt "$bm" ] && { bm="$m"; best="$f"; }
      done
    done <<EOF
$roots
EOF
    if [ -n "$slugs" ] && mkdir -p "$cache" 2>/dev/null; then
      printf '%s' "$slugs" | sort -u > "$cache/.$sid.$$" 2>/dev/null && mv -f "$cache/.$sid.$$" "$cache/$sid" 2>/dev/null
    fi
  fi
  [ -n "$best" ] && printf '%s' "$best"
  return 0
}

# A user record carrying the nonce shows the prompt was SUBMITTED; a real assistant record after it
# shows a turn RAN. The second half matters: on 10-01 a user record landed on an account at its
# weekly limit and nothing ran (C2-skeptic-code #6).
rn_confirm() { # <sid> <nonce> [cwd] → "user=N assistant=N"; rc 0 confirmed · 1 submitted, no reply · 2 not submitted
  local tx at nu=0 na=0
  tx="$(_rn_transcript "$1" "${3:-}")"
  if [ -n "$tx" ]; then
    at="$(grep -a -n -F -- "$2" "$tx" 2>/dev/null | grep -a '"type":"user"' | head -n 1 | cut -d: -f1)"
    if [ -n "$at" ]; then
      nu="$(grep -a -F -- "$2" "$tx" 2>/dev/null | jq -c 'select(.type == "user")' 2>/dev/null | grep -c . || true)"
      na="$(tail -n "+$((at + 1))" "$tx" 2>/dev/null | grep -a '"type":"assistant"' \
            | jq -c 'select(.type == "assistant" and ((.isApiErrorMessage // false) | not)
                            and ((.message.model // "") != "<synthetic>"))' 2>/dev/null | grep -c . || true)"
    fi
  fi
  printf 'user=%s assistant=%s' "${nu:-0}" "${na:-0}"
  [ "${nu:-0}" -ge 1 ] || return 2
  [ "${na:-0}" -ge 1 ] || return 1
  return 0
}

_rn_pane_of() { # <sid> → the pane of the ONE registry row naming that session, else ""
  local dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}" f p hit="" n=0
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    p="$(jq -r --arg s "$1" 'select(.session_id == $s) | .paneUUID // empty' "$f" 2>/dev/null)"
    [ -n "$p" ] && { hit="$p"; n=$((n + 1)); }
  done
  [ "$n" = 1 ] && printf '%s' "$hit"
}

# The verified paste lives inside scripts/handoff-fire.sh (it2_paste_submit_verified), which is a
# program, not a library. Until it has an entry point, CC_RESTORE_PASTE_CMD names one:
#   <cmd> <pane> <prompt-file>   rc 0 = pasted, read back and submitted (that function's own rc 0)
# With none, the arm abstains and says so. It never falls back to a raw send.
_rn_paste_cmd() {
  if [ -n "${CC_RESTORE_PASTE_CMD:-}" ]; then printf '%s' "$CC_RESTORE_PASTE_CMD"; return 0; fi
  local hf; hf="$(_rn_self_dir)/../handoff-fire.sh"
  # shellcheck disable=SC2016  # a literal pattern: the dollar sign is matched, not expanded
  [ -x "$hf" ] && grep -q '^if \[ "\${1:-}" = "paste-verified" \]' "$hf" 2>/dev/null && printf '%s paste-verified' "$hf"
  return 0
}

# For a prompt that never reached the transcript. cc-wake first: it uses the session's own messaging
# socket, touches no composer and proves itself by the inbox receipt. The verified paste second.
rn_fallback() { # <sid> <prompt-file> <nonce> [cwd] → "verdict=<woken|pasted|unconfirmed> via=<…> [why=…]"
  local sid="$1" pf="$2" nonce="$3" cwd="${4:-}" wb pc pane rc why=""
  [ "${CC_RESTORE_NUDGE:-on}" != off ] || { printf 'verdict=unconfirmed via=none why=CC_RESTORE_NUDGE=off'; return 1; }
  [ -s "$pf" ] || { printf 'verdict=unconfirmed via=none why=no-prompt-file'; return 1; }
  wb="$(_rn_bin "${CC_WAKE_BIN:-}" cc-wake)"
  if [ -n "$wb" ]; then
    # cc-wake only wakes a session with unread mail, so the prompt goes into the inbox first.
    rn_send_note "$sid" "$(cat "$pf")" || why="note-rc-$?"
    rc=0; "$wb" "$sid" --wait "${CC_RESTORE_WAKE_WAIT_S:-60}" --from boot-resume >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] && { printf 'verdict=woken via=cc-wake'; return 0; }
    why="${why:+$why,}cc-wake-rc-$rc"
  else
    why="no-cc-wake"
  fi
  # The wake may have been sent and only its receipt missed the wait: the transcript says whether a
  # turn took the prompt, and a second submit on top of it would run the recovery twice.
  rn_confirm "$sid" "$nonce" "$cwd" >/dev/null 2>&1 && { printf 'verdict=woken via=cc-wake why=%s,transcript' "$why"; return 0; }
  pc="$(_rn_paste_cmd)"; pane="$(_rn_pane_of "$sid")"
  if [ -z "$pc" ]; then why="$why,no-verified-paste-entry-point"
  elif [ -z "$pane" ]; then why="$why,no-single-registry-pane"
  else
    rc=0
    # shellcheck disable=SC2086  # the command may carry its own subcommand word
    $pc "$pane" "$pf" >/dev/null 2>&1 || rc=$?
    # rc 0 says the paste helper read the composer back and sent Enter. Submitted is the transcript's call.
    if [ "$rc" = 0 ] && rn_confirm "$sid" "$nonce" "$cwd" >/dev/null 2>&1; then printf 'verdict=pasted via=paste-verified'; return 0; fi
    [ "$rc" = 0 ] && sleep "${CC_RESTORE_PASTE_SETTLE_S:-15}" && rn_confirm "$sid" "$nonce" "$cwd" >/dev/null 2>&1 \
      && { printf 'verdict=pasted via=paste-verified'; return 0; }
    why="$why,paste-rc-$rc"
  fi
  printf 'verdict=unconfirmed via=none why=%s' "$why"
  return 1
}
