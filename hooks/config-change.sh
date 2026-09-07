#!/bin/bash
# config-change.sh — the OUT-OF-BAND CONFIG TRIPWIRE: one line per settings/skill file the harness
# saw change mid-session, and — for a settings file — whether it still PARSES (HOOK_SURFACE_100P
# § 3 row 24, W3-D).
#
# WHY IT EARNS ITS COST. `ConfigChange` is the only in-session signal that a config file changed
# OUT OF BAND, and it names the file. That is a direct tripwire for this plan's own headline hazard:
# **one malformed entry silently disables every hook registration in that settings file — all 90 of
# them in `~/.claude/settings.json`, including every fact-bound Stop gate and the land gate — with
# zero log output** (§ 1, § 4). Nothing else observes that moment. A poll would have to re-read
# every config file on a timer to find what this event hands over for free, and it would find it
# minutes late.
#
# 🚨 THE ADOPTION CONSTRAINT: THIS EVENT IS DECISION-CLASS. The handler MUST exit 0 with EMPTY
# stdout, or it silently freezes config/skill hot-reload for the whole session. There is no writer
# to stdout below and `tests/config-change.bats` asserts the property per path.
#
# MEASURED PAYLOAD (2.1.114 AND 2.1.220 · headless `-p`, /tmp/hs/log/session.tsv + session114.tsv):
#   {session_id, transcript_path, cwd, hook_event_name:"ConfigChange", source, file_path}
#   + optional `prompt_id` (present in one capture, absent in another — do not key on it).
#
# ⚠️ `source` IS RECORDED VERBATIM AND NOTHING IS KEYED ON IT. The plan's § 3a row lists the one
# value its writeup quotes, `local_settings`. The captures hold TWO: `local_settings` for
# `.claude/settings.local.json` and **`skills`** for `.claude/commands/hsprobe.md`. Nobody has read
# this event's value list out of the binary's hook metadata, so its enum is UNBOUNDED as far as this
# handler knows — and a tripwire keyed on an unmeasured enum is a tripwire that silently stops
# covering the case it was built for the first time a value is added. The classification below is
# therefore keyed on the FILE PATH, which is measured and self-describing, and `source` rides along
# as data for whoever does read that enum later.
#
# WHAT `json_ok` MEANS, AND ITS ONE FALSE-POSITIVE MODE. For a settings file the handler re-reads
# the named file and records whether it parses. That is the whole tripwire: an invalid
# `settings.json` is registration-death with no other symptom. But the hook fires ON the write, so a
# read can land MID-WRITE and see a truncated file that is invalid for a few milliseconds and valid
# forever after — the failure class memory `peer-worktree-read-midwrite-parses-as-a-code-defect`
# records. So a first FAILING parse is re-checked once, after a short bounded sleep, and the row
# carries `rechecked` so a reader can tell a settled verdict from a single sample. A first PASSING
# parse is never re-checked: a file that parses cannot become the hazard by being read again, and
# paying the sleep on the common path would tax every config write.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e`. Empty stdin, malformed JSON, a wrong event name, an absent
# jq, an unreadable target file, an unwritable log — every one exits 0 having emitted nothing.
#
# Env seams (tests): CONFIG_CHANGE_LOG · CONFIG_CHANGE_MAX_BYTES · CONFIG_CHANGE_RECHECK_SEC ·
#                    CONFIG_CHANGE_MAX_PARSE_BYTES
# Kill switch: CC_CONFIG_CHANGE_DISABLED=1
set -uo pipefail

[ "${CC_CONFIG_CHANGE_DISABLED:-0}" = "1" ] && exit 0

LOG="${CONFIG_CHANGE_LOG:-$HOME/.claude/logs/config-change.jsonl}"
MAX_BYTES="${CONFIG_CHANGE_MAX_BYTES:-1048576}"
RECHECK_SEC="${CONFIG_CHANGE_RECHECK_SEC:-0.25}"
MAX_PARSE_BYTES="${CONFIG_CHANGE_MAX_PARSE_BYTES:-2097152}"   # 2 MiB; the live file is ~100 KB
case "$MAX_BYTES"       in ''|*[!0-9]*) MAX_BYTES=1048576 ;; esac
case "$MAX_PARSE_BYTES" in ''|*[!0-9]*) MAX_PARSE_BYTES=2097152 ;; esac

IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0

LOGDIR="${LOG%/*}"
ensure_dir() { [ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null || true; }

abstain() {
  local ts
  ensure_dir
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')"
  printf '{"ts":"%s","hook":"config-change","abstain":"%s"}\n' "$ts" "$1" >> "$LOG" 2>/dev/null || true
  exit 0
}

command -v jq >/dev/null 2>&1 || abstain "no-jq"

# The event gate. It is what makes a mis-registration inert: this handler pointed at any other event
# writes nothing, rather than minting a config-change row (and a settings re-read) per dispatch.
FIELDS="$(printf '%s' "$INPUT" | jq -er '
  select(.hook_event_name == "ConfigChange")
  | @sh "SID=\(.session_id // "-") SOURCE=\(.source // "-") FILE_PATH=\(.file_path // "") CWD=\(.cwd // "-")"
' 2>/dev/null)" || FIELDS=""
if [ -z "$FIELDS" ]; then
  if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then abstain "malformed-json"; fi
  exit 0
fi
# `@sh` + eval, NOT `@tsv` + read: a tab IS an IFS whitespace character, so `read` collapses runs of
# it and an absent leading field shifts every later field LEFT — the defect measured on
# hooks/file-changed.sh (memory: ifs-whitespace-collapses-empty-fields).
eval "$FIELDS"
SID="${SID:--}"; SOURCE="${SOURCE:--}"; CWD="${CWD:--}"; FILE_PATH="${FILE_PATH:-}"

# ── classify on the PATH, per the header ─────────────────────────────────────────────────────────
BASE="${FILE_PATH##*/}"
KIND="other"
case "$BASE" in settings.json|settings.local.json|settings.*.json) KIND="settings" ;; esac
[ -n "$FILE_PATH" ] || KIND="unknown"

# ── the tripwire: does the named settings file still parse? ──────────────────────────────────────
# "unchecked" is the honest verdict for a non-settings file — a skill or command markdown is not
# JSON and asserting anything about its syntax here would be a fabricated fact.
JSON_OK="unchecked"
RECHECKED="false"
if [ "$KIND" = "settings" ]; then
  if [ ! -e "$FILE_PATH" ]; then
    JSON_OK="absent"                     # a DELETE is a real ConfigChange and a real event to see
  elif [ ! -r "$FILE_PATH" ]; then
    JSON_OK="unreadable"
  else
    FSIZE="$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)"
    case "$FSIZE" in ''|*[!0-9]*) FSIZE=0 ;; esac
    if [ "$FSIZE" -gt "$MAX_PARSE_BYTES" ]; then
      JSON_OK="too-large"                # a bound, not a verdict: never read an unbounded file here
    elif jq -e . "$FILE_PATH" >/dev/null 2>&1; then
      JSON_OK="yes"
    else
      # the mid-write window — one bounded re-check, then the verdict is settled
      sleep "$RECHECK_SEC" 2>/dev/null || true
      RECHECKED="true"
      if jq -e . "$FILE_PATH" >/dev/null 2>&1; then JSON_OK="yes"; else JSON_OK="no"; fi
    fi
  fi
fi

ROW="$(jq -cn --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')" \
  --arg sid "$SID" --arg src "$SOURCE" --arg fp "$FILE_PATH" --arg kind "$KIND" \
  --arg ok "$JSON_OK" --argjson re "$RECHECKED" --arg cwd "$CWD" \
  '{ts:$ts,hook:"config-change",sid:$sid,source:$src,file_path:$fp,kind:$kind,
    json_ok:$ok,rechecked:$re,cwd:$cwd}' 2>/dev/null)" || ROW=""
[ -n "$ROW" ] || exit 0
case "$ROW" in '{'*) ;; *) exit 0 ;; esac

ensure_dir
SIZE="$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
if [ "$SIZE" -ge "$MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi

printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
exit 0
