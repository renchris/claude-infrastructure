#!/usr/bin/env bash
# recycle-escalate.sh — a recycle failure leaves an incident record, and a NEW failure class gets one
# research session (docs/research/selfrecycle-latency-2026-10-26/REPORT.md D5).
#
# Every terminal failure arm of the recycle already writes a ledger row, and the self form leaves a
# retry ticket that hooks/boundary-handoff.sh turns into a re-run. Neither says WHY the class keeps
# happening: the retry is for this pane, nobody is asked about the cause. So each failure also
# counts into ~/.claude/autonomy/recycle-incidents/<class>.json (count, last ts, evidence paths), and
# the first occurrence of a class inside 24 h fires one session whose goal is a root-cause doc with a
# proposed fix. Bounded twice — one fire per class per CC_RECYCLE_ESCALATE_CLASS_S (86400), three
# per rolling day overall (CC_RECYCLE_ESCALATE_DAY_MAX) — because a class that fails on every pane
# would otherwise fire a session per pane. Kill switch CC_RECYCLE_ESCALATE=off.
#
# Holds that are the DESIGNED answer to operator or ownership state (a draft in the composer, the
# reconciler's fence, a focused pane, a lock another recycle holds) are counted but never fired on:
# their cause is known and correct. The list is CC_RECYCLE_ESCALATE_SKIP (space-separated classes).
#
# Sourced by scripts/handoff-fire.sh; defines functions only, never exits or fails its caller. Under
# bats with no CC_RECYCLE_ESCALATE_FIRE_BIN it never fires: forty suites drive the hold arms, and each
# would otherwise start a real session.

HF_ESCALATE_SKIP_DEFAULT="recycle-held-draft recycle-held-fenced recycle-held-focused recycle-held-new-prompt recycle-held-locked recycle-held-launch-lock recycle-held-busy recycle-held-subagents"

hf_escalate_dir() { printf '%s' "${CC_RECYCLE_INCIDENT_DIR:-$HOME/.claude/autonomy/recycle-incidents}"; }

# Bounded by WALL time (5 s), never by a try count: at load ~130 fifty tries with their forks outlast
# the 30 s stale threshold, and a live writer's lock was broken as stale (measured in this suite).
hf_escalate_lock() { # $1=dir → 0 lock held (release with hf_escalate_unlock) · 1 busy
  local l="$1/.lock" end m now
  end=$(( $(date +%s) + 5 ))
  while :; do
    mkdir "$l" 2>/dev/null && return 0
    now="$(date +%s)"
    m="$(stat -f %m "$l" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) m="$(stat -c %Y "$l" 2>/dev/null)" ;; esac
    case "$m" in ''|*[!0-9]*) m="$now" ;; esac
    if [ $((now - m)) -gt 30 ]; then rmdir "$l" 2>/dev/null || true; continue; fi
    [ "$now" -lt "$end" ] || return 1
    /bin/sleep 0.2
  done
}
hf_escalate_unlock() { rmdir "$1/.lock" 2>/dev/null || true; }

hf_escalate_detach() { # $1=log $2...=command → prints the detached child's pid (own session, stdin /dev/null)
  /usr/bin/python3 - "$@" <<'PY'
import subprocess, sys
log = open(sys.argv[1], "ab", buffering=0)
p = subprocess.Popen(sys.argv[2:], stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
print(p.pid)
PY
}

hf_escalate_brief() { # $1=brief path $2=class $3=count $4=pane $5=sid $6=detail $7=doc $8=evidence (newline list)
  {
    printf '# Recycle incident: %s\n\n' "$2"
    # shellcheck disable=SC2016  # the backticks are markdown in the brief, not a command substitution
    printf 'A recycle (scripts/handoff-fire.sh --recycle) failed with class `%s` (occurrence %s in the incident record).\n' "$2" "$3"
    printf 'Pane: %s · session: %s\n\nDetail: %s\n\n' "${4:--}" "${5:--}" "$6"
    printf '## Evidence\n'
    if [ -n "$8" ]; then printf '%s\n' "$8" | sed 's/^/- /'; else printf -- '- (no evidence paths were recorded)\n'; fi
    printf -- '- the incident record: %s/%s.json\n' "$(hf_escalate_dir)" "$2"
    printf -- "- the ledger rows: grep '\"%s\"' ~/.claude/logs/handoffs.jsonl | tail -20\n\n" "$2"
    printf '## Deliverable\n'
    # shellcheck disable=SC2016  # markdown backticks, as above
    printf 'In ~/Development/claude-infrastructure (your own worktree), write `%s`: the root cause of this\n' "$7"
    printf 'failure class from the evidence above, the evidence that proves it, and a proposed fix with\n'
    printf 'file:line references. Land the doc with the project-local /ship. Research and the doc only:\n'
    printf 'do not change scripts/handoff-fire.sh, and do not type into any pane but your own.\n'
  } > "$1"
}

hf_recycle_escalate() { # $1=class $2=pane $3=sid $4=detail [$5...=evidence paths] → always 0
  local cls="${1:-}" pane="${2:-}" sid="${3:-}" detail="${4:-}" d f now n=0 first=0 lastfire=0 verdict="" pid="" \
        ev="" p day ymd doc brief fire_bin daycount=0 rec tmp
  [ "${CC_RECYCLE_ESCALATE:-on}" != off ] || return 0
  cls="$(printf '%s' "$cls" | LC_ALL=C tr -cd 'a-z0-9-')"
  [ -n "$cls" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  shift 4 2>/dev/null || shift $#
  for p in "$@"; do [ -n "$p" ] && [ -e "$p" ] && ev="${ev:+$ev
}$p"; done
  d="$(hf_escalate_dir)"; f="$d/$cls.json"; now="$(date +%s)"
  mkdir -p "$d" 2>/dev/null && chmod 700 "$d" 2>/dev/null || true
  [ -d "$d" ] || return 0
  if ! hf_escalate_lock "$d"; then echo "→ escalate: $cls lock-busy"; return 0; fi
  if [ -f "$f" ] && ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    mv -f "$f" "$f.corrupt.$now" 2>/dev/null || true
  fi
  if [ -f "$f" ]; then
    n="$(jq -r '.count // 0' "$f")"; first="$(jq -r '.first_ts // 0' "$f")"; lastfire="$(jq -r '.last_fire_ts // 0' "$f")"
  fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  case "$first" in ''|*[!0-9]*|0) first="$now" ;; esac
  case "$lastfire" in ''|*[!0-9]*) lastfire=0 ;; esac
  n=$((n + 1))
  day="${CC_RECYCLE_ESCALATE_CLASS_S:-86400}"; case "$day" in ''|*[!0-9]*) day=86400 ;; esac
  if [ -f "$d/fires.log" ]; then
    daycount="$(awk -v t="$((now - 86400))" '$1 + 0 > t { c++ } END { print c + 0 }' "$d/fires.log" 2>/dev/null || echo 0)"
  fi
  ymd="$(date -u +%Y-%m-%d)"
  doc="docs/research/recycle-incident-$cls-$ymd.md"
  fire_bin="${CC_RECYCLE_ESCALATE_FIRE_BIN:-$HOME/.claude/scripts/handoff-fire.sh}"
  case " ${CC_RECYCLE_ESCALATE_SKIP-$HF_ESCALATE_SKIP_DEFAULT} " in
    *" $cls "*) verdict="skip-designed-hold" ;;
  esac
  if [ -z "$verdict" ] && { [ -n "${BATS_TEST_FILENAME:-}" ] || [ -n "${BATS_RUN_TMPDIR:-}" ]; } && [ -z "${CC_RECYCLE_ESCALATE_FIRE_BIN:-}" ]; then
    verdict="suppressed-under-test"
  fi
  if [ -z "$verdict" ] && [ "$lastfire" -gt 0 ] && [ $((now - lastfire)) -lt "$day" ]; then verdict="deduped-class"; fi
  if [ -z "$verdict" ] && [ "$daycount" -ge "${CC_RECYCLE_ESCALATE_DAY_MAX:-3}" ]; then verdict="day-cap"; fi
  if [ -z "$verdict" ]; then
    brief="$d/$cls-$ymd.brief.md"
    if [ ! -x "$fire_bin" ]; then
      verdict="fire-failed:no-fire-bin"
    elif ! hf_escalate_brief "$brief" "$cls" "$n" "$pane" "$sid" "$detail" "$doc" "$ev" 2>/dev/null; then
      verdict="fire-failed:brief-unwritable"
    else
      pid="$(hf_escalate_detach "$d/$cls-$ymd.fire.log" env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID "$fire_bin" \
              --prompt-file "$brief" --worktree "recycle-incident-$cls-$(date -u +%Y%m%d)" \
              --repo "$HOME/Development/claude-infrastructure" --account auto --split-right --no-notify-back \
              --goal "$doc is on origin/main with a root cause and a proposed fix — proven by the session printing git ls-tree origin/main -- $doc; do not edit scripts/handoff-fire.sh" 2>/dev/null)" || pid=""
      case "$pid" in ''|*[!0-9]*) verdict="fire-failed:no-pid"; pid="" ;; *) verdict="fired" ;; esac
    fi
  fi
  if [ "$verdict" = fired ]; then
    lastfire="$now"
    printf '%s %s\n' "$now" "$cls" >> "$d/fires.log" 2>/dev/null || true
  fi
  rec="$(jq -n --arg cls "$cls" --argjson n "$n" --argjson first "$first" --argjson now "$now" \
           --arg pane "$pane" --arg sid "$sid" --arg detail "$detail" --arg ev "$ev" --argjson lf "$lastfire" \
           --arg v "$verdict" --arg doc "$doc" --arg pid "$pid" --slurpfile old <(cat "$f" 2>/dev/null || true) '
    ($old[0] // {}) as $o
    | {class: $cls, count: $n, first_ts: $first, last_ts: $now, last_pane: $pane, last_sid: $sid,
       last_detail: $detail,
       evidence: ((($o.evidence // []) + ($ev | split("\n") | map(select(length > 0))))
                  | reduce .[] as $e ([]; if any(.[]; . == $e) then . else . + [$e] end) | .[-10:]),
       last_fire_ts: $lf,
       fires: ((($o.fires // []) + (if ($v == "fired" or ($v | startswith("fire-failed")))
                                    then [{ts: $now, verdict: $v, doc: $doc, pid: $pid}] else [] end))[-10:]),
       last_verdict: $v}' 2>/dev/null)" || rec=""
  if [ -n "$rec" ]; then
    tmp="$f.tmp.$$"
    if printf '%s\n' "$rec" > "$tmp" 2>/dev/null; then mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null; fi
  fi
  hf_escalate_unlock "$d"
  echo "→ escalate: $cls count=$n fire=$verdict${pid:+ pid=$pid} record=$f"
  return 0
}
