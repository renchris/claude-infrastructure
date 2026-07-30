#!/bin/bash
# lead-crash-watchdog.sh — SessionStart hook that spawns a detached watchdog
# daemon per claude session. If the lead process dies while it has an active
# team, the watchdog:
#   1. Appends a shutdown_request envelope to each teammate inbox
#   2. Writes a CRASH_REPORT.md in the team dir
#   3. Fires a macOS notification + terminal bell
#
# This prevents the routines-v1 scenario from repeating: lead died mid-session,
# 3 teammates blocked on permission prompts, no recovery signal.
#
# Kill switch: export LEAD_CRASH_WATCHDOG_DISABLED=1
#
# Exit: always 0 (hook must never block session startup).

set -euo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled hook. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: LCW_OSA_TIMEOUT_S · LCW_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
LCW_OSA_TIMEOUT_S="${LCW_OSA_TIMEOUT_S:-5}"
if [ -n "${LCW_OSA_TIMEOUT_BIN+set}" ]; then
  LCW_OSA_TB="${LCW_OSA_TIMEOUT_BIN}"
else
  LCW_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { LCW_OSA_TB="$_c"; break; }
  done
fi
lcw_osa() {
  if [ -z "$LCW_OSA_TB" ] || [ ! -x "$LCW_OSA_TB" ]; then "$@"; return $?; fi
  "$LCW_OSA_TB" -k 3 "$LCW_OSA_TIMEOUT_S" "$@"
}


if [[ "${LEAD_CRASH_WATCHDOG_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/lead-crash-watchdog.log"

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ── death classification helpers (top-level so the daemon subshell inherits them,
#    and so `lead-crash-watchdog.sh --classify <sid>` is unit-testable) ───────────
# A pid death with the pid-file still present is EITHER a deliberate self-recycle
# (handoff-fire --recycle / self-close kills the pane with no clean SessionEnd) OR a
# genuine crash (jetsam OOM, abort, external kill). kill -0 cannot tell them apart, so
# thousands of "LEAD CRASH" lines accumulated conflating both. This separates them from
# disk truth and, on a real crash, attributes the cause. Bias: unsure ⇒ CRASH (a hidden
# crash is worse than a spurious alert).
find_transcript() {
  local sid="$1" base hit
  # account roots are env-overridable for tests (default: the 4 live account dirs)
  local bases="${CC_ACCOUNT_BASES:-$HOME/.claude $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary}"
  # shellcheck disable=SC2086  # intentional word-split over space-separated bases
  for base in $bases; do
    # shellcheck disable=SC2012  # glob-ls + head -1 is deliberate (fixed sid-keyed pattern, no exotic names)
    hit=$(ls "$base"/projects/*/"$sid"*.jsonl 2>/dev/null | head -1)
    [[ -n "$hit" ]] && { printf '%s' "$hit"; return 0; }
  done
  return 1
}

# ── close-record join (bin/cc-close-attrib) ─────────────────────────────────────────────
# The launcher's exec-wrapper writes ~/.claude/logs/close-records/<pid>-<epoch>.json on exit
# with the binary's REAL exit_code/signal. Keyed by the SAME pid the watchdog sees as the dead
# lead (PPID of SessionStart), it turns an "abrupt-unknown" GUESS into an attributed FACT.
find_close_record() {
  local pid="$1" dir="${CC_CLOSE_RECORDS_DIR:-$HOME/.claude/logs/close-records}"
  [[ -n "$pid" ]] || return 1
  # shellcheck disable=SC2012  # ls -1t is deliberate (newest-first mtime on a fixed pid pattern)
  ls -1t "$dir/${pid}-"*.json 2>/dev/null | head -1
}

# Read one scalar field from a close-record without requiring jq (matches "key":123 or "key":"v").
close_record_field() {
  local f="$1" key="$2" v
  [[ -f "$f" ]] || return 0
  v=$(grep -oE "\"$key\":(\"[^\"]*\"|[0-9]+)" "$f" 2>/dev/null | head -1)
  v=${v#*:}; v=${v#\"}; v=${v%\"}
  printf '%s' "$v"
}

# marker_owns_sid <marker-file> <sid> → 0 iff this teardown marker is evidence about THIS session.
#
# A marker body carries the sid it was written FOR. That matters only on the pane-keyed lookup: an
# in-place `handoff-fire --recycle` keeps the SAME pane and registers a NEW session on it, so for up
# to the 30-min freshness window the pane carries the PREDECESSOR's marker while the registry row
# already resolves to the SUCCESSOR. Accepting it blind classifies a GENUINE crash of the successor
# as a deliberate teardown — a SILENT miss, strictly worse than the false CRASH this ladder exists to
# prevent (a false CRASH pages; a false RECYCLE is swallowed). So a marker naming a DIFFERENT
# non-empty sid is not evidence here.
#
# An EMPTY sid is the legitimate pane-only case and is still ACCEPTED: the real self-close path blanks
# SESSION_ID and the writer's registry recovery can miss, which is exactly the 2026-07-23 incident
# shape — rejecting it would regress that fix. Unreadable/absent field ⇒ empty ⇒ accepted (fail-open,
# matching this ladder's bias: never invent a crash).
marker_owns_sid() {
  local f="$1" want="$2" got
  [[ -f "$f" ]] || return 1
  got=$(grep -oE '"sid":"[^"]*"' "$f" 2>/dev/null | head -1)
  got=${got#*:}; got=${got#\"}; got=${got%\"}
  [[ -z "$got" || "$got" == "$want" ]]
}

# EXIT<TAB>SIGNAL<TAB>RECORD_PATH<TAB>VERSION for a pid's newest close-record (empty if none).
# Used by handle_crash to enrich the crash row AND by the --close-fields test entrypoint.
close_record_summary() {
  local pid="$1" cr
  [[ -n "$pid" ]] || return 0
  cr=$(find_close_record "$pid") || return 0
  [[ -n "$cr" ]] || return 0
  printf '%s\t%s\t%s\t%s' \
    "$(close_record_field "$cr" exit_code)" \
    "$(close_record_field "$cr" signal)" \
    "$cr" \
    "$(close_record_field "$cr" version)"
}

# exit code → CLASS<TAB>CAUSE (ground truth). Non-numeric/absent ⇒ return 1 (no override).
#   0/130/143 (SIGINT/SIGTERM) = clean-exit · 137 (SIGKILL) = killed-oom-or-force ·
#   139 (SIGSEGV) = binary-crash · any other nonzero = error-exit.
map_exit_class() {
  case "$1" in
    0|130|143)    printf 'RECYCLE\tclean-exit' ;;
    137)          printf 'CRASH\tkilled-oom-or-force' ;;
    139)          printf 'CRASH\tbinary-crash' ;;
    ''|*[!0-9]*)  return 1 ;;
    *)            printf 'CRASH\terror-exit' ;;
  esac
}

# ── jetsam attribution, anchored to the DEATH — not to "now" (audit 2026-07-22, root cause 4) ─────────
# The check used to be `find … -mmin -6`, i.e. "was any JetsamEvent written in the last 6 minutes OF
# NOW". On the LIVE path now ≈ the death, so it read correctly. On `cc-crash-report --backfill`, which
# re-classifies up to 90 HISTORICAL deaths, "now" is whenever the report happens to run — so the same
# expression answered a question about the present for every death in the past:
#   · one unrelated jetsam kill in the last 6 minutes relabelled EVERY backfilled death jetsam-oom,
#     deliberate recycles included — and jetsam OUTRANKS the recycle evidence, so those flips are
#     silent and total (the recycle text is never even consulted);
#   · a death 3 days ago that WAS jetsam-killed could never match, because its report is long past
#     any now-relative window.
# The window is now two-sided around the death, which is what the documented contract ("a JetsamEvent
# within ~6 min of death", cc-crash-report:15) always claimed: a report is written AT or shortly after
# the kill, while the watchdog notices up to one 30s poll late, so the truth can fall on either side.
JETSAM_WINDOW_S="${CC_JETSAM_WINDOW_S:-360}"     # ±6 min, the interval the old -mmin -6 approximated
jetsam_near_death() { # $1=death epoch → 0 iff a JetsamEvent report lies within ±JETSAM_WINDOW_S of it
  local death="$1" f mt d out
  case "$death" in ''|*[!0-9]*) return 1 ;; esac   # unparseable death ⇒ do not claim jetsam (never invent a cause)
  local jdirs="${CC_JETSAM_DIRS:-/Library/Logs/DiagnosticReports $HOME/Library/Logs/DiagnosticReports}"
  # BOUNDED: DiagnosticReports is a system dir this crash path does not control. Reuse the timeout
  # binary already resolved at the top of this file; absent ⇒ unbounded, as everywhere else here.
  # The window is applied in bash rather than by find: BSD find REJECTS `-newermt @epoch` ("Can't parse
  # date/time"), the same trap lead-supervisor.sh records, and a two-sided window needs two references
  # anyway. `-mmin` cannot express "near an arbitrary past instant" at all.
  # shellcheck disable=SC2086  # intentional word-split over space-separated dirs (matches the old call)
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    out=$("$LCW_OSA_TB" -k 3 "${LCW_JETSAM_SCAN_TIMEOUT_S:-10}" find $jdirs -name 'JetsamEvent-*.ips' -print 2>/dev/null || true)
  else
    out=$(find $jdirs -name 'JetsamEvent-*.ips' -print 2>/dev/null || true)
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    mt=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)   # BSD stat, then GNU fallback
    case "$mt" in ''|*[!0-9]*) continue ;; esac
    d=$(( mt > death ? mt - death : death - mt ))
    # explicit `if`, never `[[ … ]] && return`: a non-final [[ ]] in an && list is errexit-EXEMPT, so a
    # false compare would silently fall through instead of continuing the loop (the dead-assertion class)
    if [[ "$d" -le "$JETSAM_WINDOW_S" ]]; then return 0; fi
  done <<< "$out"
  return 1
}

# ── when did this session die? — the anchor jetsam attribution is judged against ────────────────────
# Deliberately NOT parsed from the watchdog log: the daemon writes its "LEAD CRASH detected" lines with a
# bare `echo` into an already-redirected stdout, so — unlike the hook's log() lines — they carry NO
# timestamp at all. A parser keyed on one would match 0 of the 3064 historical detections and turn
# backfill into a silent no-op that still printed a confident summary.
#
# Disk evidence instead, most precise first:
#   1. the close-record epoch — the launcher's exec-wrapper names it <pid>-<epoch>.json at the moment the
#      binary exits. This is the exact death instant, not a proxy.
#   2. the transcript mtime — its last write is the last thing the session did before dying. Available
#      for essentially every historical death, which is what backfill needs.
#   3. now — the LIVE daemon's answer. It detects within one 30s poll, far inside a ±6-min window, and
#      it must not be "corrected" to a transcript mtime: a session idle for hours before being killed has
#      an old transcript but died just now, and anchoring to the mtime would MISS its real jetsam report.
# So the live path (no argument) keeps using now, and backfill asks for `auto` to walk 1→2→3.
resolve_death_epoch() { # $1=sid  $2=pid  → epoch on stdout
  local sid="$1" pid="${2:-}" cr base ep t mt
  if [[ -n "$pid" ]]; then
    cr=$(find_close_record "$pid") || cr=""
    if [[ -n "$cr" ]]; then
      base=$(basename "$cr" .json); ep="${base#*-}"          # <pid>-<epoch>.json; pid holds no dash
      case "$ep" in ''|*[!0-9]*) ep="" ;; esac
      [[ -n "$ep" ]] && { printf '%s' "$ep"; return 0; }
    fi
  fi
  t=$(find_transcript "$sid" 2>/dev/null || true)
  if [[ -n "$t" && -f "$t" ]]; then
    mt=$(stat -f%m "$t" 2>/dev/null || stat -c%Y "$t" 2>/dev/null || echo "")
    case "$mt" in ''|*[!0-9]*) mt="" ;; esac
    [[ -n "$mt" ]] && { printf '%s' "$mt"; return 0; }
  fi
  date +%s
}

classify_death() {
  # prints: CLASS<TAB>CAUSE<TAB>transcript_kb<TAB>records   (CLASS = RECYCLE|CRASH)
  # $3 = when this session died, for jetsam attribution: an EPOCH, the literal `auto` (derive from disk —
  # what cc-crash-report --backfill passes, since its deaths are historical), or omitted ⇒ NOW, which is
  # correct for the live daemon and is what every pre-existing caller gets unchanged.
  local sid="$1" pid="${2:-}" death="${3:-}" t body kb=0 recs=0
  if [[ "$death" == "auto" ]]; then death=$(resolve_death_epoch "$sid" "$pid"); fi
  case "$death" in ''|*[!0-9]*) death=$(date +%s) ;; esac
  # 0) CLOSE-RECORD FIRST — per-pid ground truth OUTRANKS every heuristic below (incl. jetsam:
  #    137 already IS the SIGKILL/OOM case; a clean exit for THIS pid is clean even if some other
  #    process tripped a JetsamEvent). Absent record ⇒ fall through to the existing ladder.
  if [[ -n "$pid" ]]; then
    local cr ec cls
    cr=$(find_close_record "$pid") || cr=""
    if [[ -n "$cr" ]]; then
      ec=$(close_record_field "$cr" exit_code)
      if cls=$(map_exit_class "$ec"); then
        t=$(find_transcript "$sid" 2>/dev/null || true)
        if [[ -n "$t" ]]; then
          kb=$(( $(stat -f%z "$t" 2>/dev/null || echo 0) / 1024 ))
          recs=$(wc -l < "$t" 2>/dev/null | tr -d ' ')
        fi
        printf '%s\t%s\t%s' "$cls" "${kb:-0}" "${recs:-0}"; return 0
      fi
    fi
  fi
  t=$(find_transcript "$sid") || { printf 'CRASH\tno-transcript\t0\t0'; return 0; }
  kb=$(( $(stat -f%z "$t" 2>/dev/null || echo 0) / 1024 ))
  recs=$(wc -l < "$t" 2>/dev/null | tr -d ' ')
  # 1) JETSAM FIRST — a JetsamEvent report within ~6 min OF THIS DEATH is an unambiguous system OOM
  #    kill and OUTRANKS any recycle text (a kill mid-recycle is still a kill). Because it outranks
  #    everything, a mis-anchored window is not a mild inaccuracy: it silently overwrites good evidence.
  if jetsam_near_death "$death"; then
    printf 'CRASH\tjetsam-oom\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 1.5) DELIBERATE TEARDOWN — a fresh marker handoff-fire.sh writes the moment a session
  #      CHOOSES to recycle/self-close: the durable structured signal that supersedes the
  #      brittle prose-grep below (incident 2026-07-23: a real self-close read as a false
  #      CRASH). Keyed by session id, else pane uuid (resolved via the registry). Fresh =
  #      mtime <30 min. Jetsam (above) still outranks — a kill mid-teardown is still a kill.
  local tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  local reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  local reg_hit pane
  if find "$tdir" -maxdepth 1 -name "$sid.json" -mmin -30 2>/dev/null | grep -q .; then
    printf 'RECYCLE\tdeliberate-teardown\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # registry row is pretty-printed ("session_id": "<sid>" — note the space); match it
  # whitespace-tolerantly. head -1 + `|| true`: a no-match grep must not trip set -e/pipefail
  # (classify_death runs bare at the --classify entrypoint, not in an || context).
  reg_hit=$(grep -lE "\"session_id\":[[:space:]]*\"$sid\"" "$reg_dir"/*.json 2>/dev/null | head -1) || true
  if [[ -n "$reg_hit" ]]; then
    pane=$(basename "$reg_hit" .json)
    # marker_owns_sid: an in-place --recycle leaves the PREDECESSOR's marker on a pane the registry
    # now resolves to the SUCCESSOR — a marker naming a different session must not absolve this one.
    if find "$tdir" -maxdepth 1 -name "$pane.json" -mmin -30 2>/dev/null | grep -q . \
       && marker_owns_sid "$tdir/$pane.json" "$sid"; then
      printf 'RECYCLE\tdeliberate-teardown\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
    fi
  fi
  # 2) DELIBERATE RECYCLE — the disposition/self-close phrases and the successor-brief
  #    text a session emits when it CHOOSES to recycle (incl. the brief written into the
  #    trailing last-prompt record). Bare "handoff-fire"/"self-close" are excluded —
  #    infra-dev sessions discuss them without firing, which would mask a real crash.
  body=$(tail -c 16000 "$t" 2>/dev/null || true)
  if printf '%s' "$body" | grep -qiE 'DISPOSITION: *CLOSE|Firing as the last action|the recycle IS the continuation|retiring this pane|becomes the successor|a recycle keeps|recycle keeps (this|the) pane|recycled at [0-9]+%|— recycled|Context Stewardship free-win'; then
    printf 'RECYCLE\tdeliberate-self-close\t%s\t%s' "${kb:-0}" "${recs:-0}"; return 0
  fi
  # 3) otherwise a genuine but un-attributed crash (large context ⇒ likely OOM)
  local cause="abrupt-unknown"
  [[ "${kb:-0}" -gt 4096 ]] && cause="suspected-oom-large-context"
  printf 'CRASH\t%s\t%s\t%s' "$cause" "${kb:-0}" "${recs:-0}"
}

# GC the teardown marker(s) for a session. Called ONLY from the owner-guarded pidfile-rm
# blocks below — we just deleted OUR pid's pidfile, so the recycle/self-close is fully handled
# and the marker has served its purpose. Removes the sid-keyed marker and, if cheaply resolvable
# via the session registry, its pane-keyed alias. Never call elsewhere: a stale marker is
# harmless (30-min freshness window), but deleting one mid-recycle could unmask a real crash.
gc_teardown_marker() {
  local sid="$1"
  local tdir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  local reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  local reg_hit pane
  rm -f "$tdir/$sid.json" 2>/dev/null || true
  reg_hit=$(grep -lE "\"session_id\":[[:space:]]*\"$sid\"" "$reg_dir"/*.json 2>/dev/null | head -1) || true
  [[ -n "$reg_hit" ]] || return 0
  pane=$(basename "$reg_hit" .json)
  rm -f "$tdir/$pane.json" 2>/dev/null || true
}

# ── ASSIGNEE HARVEST (leg a) ─────────────────────────────────────────────────────
# HARVEST BEFORE TEARDOWN. When the lead dies, its assignees' final reports exist in exactly one
# place: their own transcript JSONL on disk. They are NOT in any inbox and never will be — a
# named assignee's final text is "the return to lead", and the lead only ever receives
# `idle_notification {idleReason: available}`; the report itself is never delivered as a message
# (memory: wave-report-harvest-from-disk, measured across a full 16-agent wave). A crashed lead
# cannot receive even that. So the ONLY correct source is disk truth, and the ONLY correct
# ordering is harvest-then-teardown: cc-teardown closes the pane, and a closed pane's session is
# gone — a report not harvested first is a report lost. Observed 2026-07-26 on team
# session-a3f68174: 8 assignees, every final report reachable only by hand-digging transcripts.
#
# member_transcript <name> <cwd> → path of the assignee's transcript, or empty.
# TWO ordered strategies, both keyed on disk truth, never on a notification:
#   1. CWD-SLUG (cheap, targeted). CC stores a session's transcript under
#      <account>/projects/<cwd-with-slashes-turned-to-dashes>/<sessionId>.jsonl, and a team member
#      carries its own `.cwd`. That maps straight to the directory to search, so this never walks
#      the 5638-session corpus. Within it, the file is disambiguated by `"agentName":"<name>"` —
#      several assignees can share one worktree (measured: wt-pool-3 held sq-a1 and sq-c1).
#   2. BOUNDED MACHINE-WIDE (fallback) for an assignee whose cwd was force-removed by the dying
#      lead — exactly the observed incident — so the slug dir may not resolve. Time-capped, and a
#      cap that expires yields NO path: it ABSTAINS rather than guessing a wrong transcript.
# NEWEST wins: an assignee that was re-fired has more than one transcript and only the last one
# carries its final report.
#
# Returns empty for BOTH "proven absent" and "could not look" — the CALLER distinguishes them
# (see harvest_member), because a missing transcript is a real outcome (bsm-schema, joined
# 2026-06-07: worktree and transcript both long rotated away) while an unreadable probe is not.
LCW_ACCOUNT_BASES_DEFAULT="$HOME/.claude $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
member_transcript() {
  local name="$1" cwd="${2:-}" base slug d hit newest="" bases
  bases="${CC_ACCOUNT_BASES:-$LCW_ACCOUNT_BASES_DEFAULT}"
  [[ -n "$name" ]] || return 0
  # 1 — cwd-slug dirs. Both the raw cwd and its PHYSICAL resolution are tried: the transcript dir
  # is named from the cwd CC recorded, and a worktree reached through a symlinked parent records
  # differently than `pwd -P` reports. Trying both only ever ADDS a candidate.
  if [[ -n "$cwd" ]]; then
    local pcwd; pcwd=$(cd "$cwd" 2>/dev/null && pwd -P 2>/dev/null) || pcwd=""
    # SLUG ENCODING: CC replaces BOTH '/' and '.' with '-'. The dot matters here and is easy to
    # miss — every dispatch worktree lives under `.worktrees`, which encodes to `--worktrees`, so a
    # slash-only slug resolves NOTHING for exactly the paths this harvest runs against. Measured
    # against a real assignee (sq-c1-registers, wt-pool-3): slash-only → no match, slash+dot →
    # the transcript. A detector that silently finds nothing looks identical to "no report exists"
    # (memory: effect-read-predicate-red-proof — positive-control every detector).
    local dcwd="${cwd//\//-}" dpcwd="${pcwd//\//-}"
    for base in $bases; do
      for slug in "${dcwd//./-}" "${dpcwd//./-}"; do
        [[ -n "$slug" ]] || continue
        d="$base/projects/$slug"
        [[ -d "$d" ]] || continue
        while IFS= read -r hit; do
          [[ -n "$hit" ]] || continue
          if [[ -z "$newest" || "$hit" -nt "$newest" ]]; then newest="$hit"; fi
        done < <(grep -l "\"agentName\":\"$name\"" "$d"/*.jsonl 2>/dev/null || true)
      done
    done
  fi
  [[ -n "$newest" ]] && { printf '%s\n' "$newest"; return 0; }
  # 2 — bounded machine-wide fallback (the lead force-removed the cwd). BOUNDED: this grep walks
  # every account's project corpus, and an unbounded walk inside a crash path would hang the
  # watchdog exactly when it is most needed (memory: bounding-external-calls). A cut yields no
  # path ⇒ abstain, never a wrong one.
  #
  # Seam: LCW_HARVEST_FALLBACK — UNSET ⇒ fallback runs. SET, including set to EMPTY ⇒ honored
  # verbatim, so `LCW_HARVEST_FALLBACK=` genuinely disables the corpus walk. `${VAR:-}` cannot tell
  # unset from set-empty, and a seam that cannot turn a thing OFF is not a seam (memory:
  # claimed-outcome-vs-checked-outcome). This also lets strategy 1 be tested in ISOLATION — without
  # it the fallback silently rescues a broken slug encoding and the dot-encoding bug looks fixed.
  if [[ -n "${LCW_HARVEST_FALLBACK+set}" && -z "${LCW_HARVEST_FALLBACK}" ]]; then return 0; fi
  local roots=() found
  for base in $bases; do [[ -d "$base/projects" ]] && roots+=("$base/projects"); done
  [[ ${#roots[@]} -gt 0 ]] || return 0
  if [[ -n "$LCW_OSA_TB" && -x "$LCW_OSA_TB" ]]; then
    found=$("$LCW_OSA_TB" -k 5 "${LCW_HARVEST_SCAN_TIMEOUT_S:-20}" \
      grep -rl --include='*.jsonl' "\"agentName\":\"$name\"" "${roots[@]}" 2>/dev/null || true)
  else
    found=$(grep -rl --include='*.jsonl' "\"agentName\":\"$name\"" "${roots[@]}" 2>/dev/null || true)
  fi
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    if [[ -z "$newest" || "$hit" -nt "$newest" ]]; then newest="$hit"; fi
  done <<< "$found"
  [[ -n "$newest" ]] && printf '%s\n' "$newest"
  return 0
}

# last_assistant_text <transcript> — the assignee's FINAL report: the last assistant message's
# joined text blocks. One streaming pass in python3 (a transcript runs to hundreds of MB and must
# never be slurped). Prints nothing when the file holds no assistant text.
#
# Why the LAST assistant record and not a tail-grep: a mid-run harvest catches interim narration
# rather than the report (measured 442 chars mid-run vs 16,152 final), and tool_use/thinking
# blocks carry no `.text`, so only `content[].text` on `message.role=="assistant"` is joined.
last_assistant_text() {
  local t="$1"
  [[ -n "$t" && -f "$t" ]] || return 0
  "${LCW_PYTHON_BIN:-python3}" - "$t" <<'PY' 2>/dev/null || true
import json, sys
last = ""
try:
    with open(sys.argv[1], "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or '"assistant"' not in line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get("message") or {}
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = "\n".join(
                    b.get("text", "") for b in content
                    if isinstance(b, dict) and b.get("type") == "text" and b.get("text")
                )
            else:
                continue
            if text.strip():
                last = text
except Exception:
    pass
sys.stdout.write(last)
PY
}

# harvest_team_reports <team_dir> <sid> — leg (a). Enumerate the team's assignees from
# config.json and write each one's final report out of its transcript into <team_dir>/HARVEST/.
#
# RUNS BEFORE ANY TEARDOWN, and that ordering is the whole point: cc-teardown closes the pane and
# kills the process, and a closed pane cannot be harvested. Harvest is also strictly
# non-destructive — it only ever creates files under <team_dir>/HARVEST/ — so it is safe to run
# unconditionally on a positive death verdict, and it is what makes the close leg safe to run at
# all (the report is already on disk before anything is reaped).
#
# Emits status.tsv: member <TAB> paneId <TAB> state <TAB> bytes <TAB> transcript. THREE states,
# because "no report" has two different causes and only one of them is a real outcome:
#   HARVESTED     report text recovered and written.
#   EMPTY         transcript found, but it holds no assistant text (assignee died before its
#                 first turn) — a real, proven outcome.
#   NO-TRANSCRIPT no transcript resolved: either genuinely rotated away (bsm-schema, joined
#                 2026-06-07) or the probe could not look. NOT proof a report never existed.
# Leg (b) reads this file and closes ONLY panes whose row is HARVESTED or EMPTY — a
# NO-TRANSCRIPT member is never torn down, because tearing it down would destroy the last place
# its report could still be found.
harvest_team_reports() {
  local team_dir="$1" sid="$2"
  local cfg="$team_dir/config.json"
  [[ -f "$cfg" ]] || { echo "[watchdog $sid] harvest: no config.json in $team_dir"; return 0; }
  local hdir="$team_dir/HARVEST"
  mkdir -p "$hdir" 2>/dev/null || true
  local status="$hdir/status.tsv"
  : > "$status" 2>/dev/null || true

  local n_h=0 n_e=0 n_n=0 name pane cwd
  while IFS=$'\t' read -r name pane cwd; do
    [[ -n "$name" ]] || continue
    [[ "$name" == "team-lead" ]] && continue
    [[ "$pane" == "-" ]] && pane=""      # '-' is jq's placeholder for absent (see the query above)
    [[ "$cwd"  == "-" ]] && cwd=""
    local tpath report_file text bytes=0 state
    tpath=$(member_transcript "$name" "$cwd" 2>/dev/null || true)
    if [[ -z "$tpath" ]]; then
      state="NO-TRANSCRIPT"; n_n=$((n_n + 1))
    else
      text=$(last_assistant_text "$tpath" 2>/dev/null || true)
      if [[ -n "$text" ]]; then
        report_file="$hdir/$name.md"
        {
          echo "# Final report — $name"
          echo
          echo "- **Team**: $(basename "$team_dir")"
          echo "- **Lead session**: $sid (crashed)"
          echo "- **Pane**: ${pane:-?}"
          echo "- **Worktree (cwd)**: ${cwd:-?}"
          echo "- **Transcript**: $tpath"
          echo "- **Harvested**: $(date '+%Y-%m-%d %H:%M:%S') — from DISK TRUTH (last assistant"
          echo "  message in the transcript), never from a notification: a named assignee's final"
          echo "  text is never delivered as a message, and this lead crashed before it could"
          echo "  receive even an idle notification."
          echo
          echo "---"
          echo
          printf '%s\n' "$text"
        } > "$report_file" 2>/dev/null || true
        bytes=$(wc -c < "$report_file" 2>/dev/null | tr -d ' ') || bytes=0
        state="HARVESTED"; n_h=$((n_h + 1))
      else
        state="EMPTY"; n_e=$((n_e + 1))
      fi
    fi
    # '-' placeholders, never an EMPTY field: `IFS=$'\t' read` COALESCES consecutive whitespace-IFS
    # runs (tab included), so an in-process member with no pane would emit two adjacent tabs, drop
    # the empty column and shift every later field LEFT — the reader would see state="HARVESTED" as
    # the PANE and try to tear it down. Caught by test (ix).
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${pane:--}" "$state" "${bytes:-0}" "${tpath:--}" \
      >> "$status" 2>/dev/null || true
    echo "[watchdog $sid] harvest $name → $state (${bytes:-0}B)"
  # jq emits '-' for an absent/empty field rather than "" for the SAME reason the writer below does:
  # `IFS=$'\t' read` coalesces adjacent tabs, so a member with no tmuxPaneId (an in-process
  # assignee) would have its CWD read as its PANE and handed to cc-teardown as a teardown target.
  # Caught by test (ix-b) asserting the producer's literal emission.
  done < <(jq -r '.members[]? | select(.name != "team-lead")
                  | [ .name,
                      ((.tmuxPaneId // "") | if . == "" then "-" else . end),
                      ((.cwd        // "") | if . == "" then "-" else . end) ] | @tsv' \
                 "$cfg" 2>/dev/null || true)

  echo "[watchdog $sid] harvest complete: $n_h harvested, $n_e empty, $n_n no-transcript → $hdir"
  return 0
}

# close_orphaned_panes <team_dir> <sid> — leg (b). Close each orphaned assignee's pane through
# bin/cc-teardown, never raw it2/osascript: only cc-teardown re-observes both legs and treats a
# surviving pane as FAIL LOUD rather than a false success (a close that returns 0 is not a closed
# pane). Observed cost of not doing this: 8 assignees alive holding 3.4GB after their lead died.
#
# STRUCTURAL PRECONDITION — harvest first. This reads leg (a)'s status.tsv and refuses outright
# when it is missing: no harvest ⇒ no teardown, because a closed pane cannot be harvested. A
# NO-TRANSCRIPT member is NEVER closed either — its pane is the last place its report could still
# be found, and "we could not look" is not "there was nothing there".
#
# DEFAULT OFF — armed only by LCW_ORPHAN_CLOSE=1. cc-teardown's own header bars wiring it RAW into
# any hook/settings/launchd (that fires it with no gate in front = C10); cc-reaper is the one
# sanctioned PRE-GATED autonomous caller. This watchdog is spawned FROM a SessionStart hook, so
# arming an automatic pane-killer here by default is precisely the wiring that rule forbids — and
# a newly-wired MUTATING step defaults OFF regardless (memory: append-only-store-safety-rules).
# Arming is therefore an operator step, staged in autonomy/pending-activation/.
#
# UNARMED IS NOT SILENT. The enumeration, the eligibility gate and the plan all still run and are
# logged and written to close-plan.tsv, so the un-reaped panes are visible and countable instead
# of the feature looking done while abstaining ~100% of the time (memory:
# feature-durability-mechanism-not-memory — a built feature must FAIL LOUD when inert).
close_orphaned_panes() {
  local team_dir="$1" sid="$2"
  local hdir="$team_dir/HARVEST" status="$team_dir/HARVEST/status.tsv"
  if [[ ! -f "$status" ]]; then
    echo "[watchdog $sid] close: REFUSE — no HARVEST/status.tsv (harvest never ran); a closed pane cannot be harvested"
    return 0
  fi
  local armed=0
  [[ "${LCW_ORPHAN_CLOSE:-0}" == "1" ]] && armed=1
  # Seam: LCW_TEARDOWN_BIN — UNSET ⇒ resolve one. SET, including set to EMPTY ⇒ honored verbatim, so
  # `LCW_TEARDOWN_BIN=` genuinely disables the actuator. `${VAR:-}` cannot tell unset from set-empty
  # (memory: claimed-outcome-vs-checked-outcome), and here that gap is not cosmetic: a `${VAR:-}`
  # read falls through to `command -v cc-teardown`, which resolves the operator's REAL
  # ~/.claude/bin/cc-teardown — so a caller intending to DISABLE the actuator would instead fire it
  # at live panes. Caught by test (xii) doing exactly that.
  local tdbin
  if [[ -n "${LCW_TEARDOWN_BIN+set}" ]]; then
    tdbin="$LCW_TEARDOWN_BIN"
  else
    tdbin=$(command -v cc-teardown 2>/dev/null || true)
    [[ -n "$tdbin" ]] || { [[ -x "$HOME/.claude/bin/cc-teardown" ]] && tdbin="$HOME/.claude/bin/cc-teardown"; }
  fi
  local plan="$hdir/close-plan.tsv"; : > "$plan" 2>/dev/null || true
  local n_elig=0 n_skip=0 n_ok=0 n_defer=0 n_refuse=0 n_fail=0 n_unres=0
  local member pane state bytes tpath

  while IFS=$'\t' read -r member pane state bytes tpath; do
    [[ -n "$member" ]] || continue
    # '-' is the writer's placeholder for an absent value (see harvest_team_reports: an EMPTY TSV
    # field would be coalesced away by `read` and shift every later column left).
    [[ "$pane"  == "-" ]] && pane=""
    [[ "$tpath" == "-" ]] && tpath=""
    # Not a closable pane: the lead's own sentinel, or an in-process assignee with no pane.
    if [[ -z "$pane" || "$pane" == "leader" ]]; then
      echo "[watchdog $sid] close: skip $member (no pane / in-process)"
      n_skip=$((n_skip + 1)); continue
    fi
    # NEVER close what was not harvested — the pane is the last place the report survives.
    if [[ "$state" == "NO-TRANSCRIPT" ]]; then
      echo "[watchdog $sid] close: SKIP $member pane=$pane — NO-TRANSCRIPT (report unrecovered; refusing to destroy the last copy)"
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "SKIP-UNHARVESTED" "" >> "$plan" 2>/dev/null || true
      n_skip=$((n_skip + 1)); continue
    fi
    n_elig=$((n_elig + 1))
    # POSITIVE done-evidence, derived — never inferred from silence. Names the death evidence and
    # the harvest that already happened, so cc-teardown's gate is judging facts, not a claim.
    local ev="lead-crash-watchdog: lead session $sid DEAD (positive evidence: watchdog pid failed kill -0); assignee '$member' orphaned with no lead to report to; final report HARVESTED to $hdir/$member.md (${bytes:-0}B, state=$state) from $tpath BEFORE teardown"
    if (( armed )) && [[ -n "$tdbin" ]]; then
      local trc=0 tout=""
      # --assignee-of: an assignee pane has NO session-registry row (134/134 measured across every
      # team dir on this machine), so a bare call could only ever come back REFUSE unknown-target —
      # which the rc==2 arm below counted as a *trusted* policy refusal. That made this whole leg a
      # 100%-abstain no-op: built, tested, landed, incapable of closing one pane. The flag lets
      # cc-teardown re-prove the target from positive it2 + argv evidence instead.
      # --assignee-sid: leg (a) already resolved this member's transcript, and the file is named
      # <sid>.jsonl — so we can hand cc-teardown the assignee's OWN session id. Without it the
      # operator-adoption belt silently no-ops (find_transcript "" returns nothing), i.e. a safety
      # gate would be BYPASSED rather than passed. Supply the identity; keep the gate armed.
      local asid=""
      [[ -n "$tpath" ]] && { asid="$(basename "$tpath")"; asid="${asid%.jsonl}"; }
      # Captured, not discarded: the outcome has to be CHECKED, not claimed. rc 2 alone cannot
      # distinguish "a safety gate declined" from "the actuator could not even SEE the target"
      # (memory: claimed-outcome-vs-checked-outcome — parse a structured reason token).
      tout=$("$tdbin" "$pane" --done-evidence "$ev" \
               --assignee-of "$sid" ${asid:+--assignee-sid "$asid"} 2>&1) || trc=$?
      case "$trc" in
        0)  n_ok=$((n_ok + 1));     echo "[watchdog $sid] close: $member pane=$pane TORN DOWN + effect-verified (rc 0)" ;;
        10) n_defer=$((n_defer + 1)); echo "[watchdog $sid] close: $member pane=$pane DEFER — cc-teardown's gate says work-unsafe (rc 10); left alone" ;;
        2)  # UNRESOLVED is NOT a policy refusal — it means our own resolution wiring is blind, the
            # exact failure that made this leg inert. It must never be absorbed into the trusted
            # refuse bucket (memory: feature-durability-mechanism-not-memory / named-failure).
            if [[ "$tout" == *"reason_kind=unknown-target"* || "$tout" == *"reason_kind=assignee-unproven"* ]]; then
              n_unres=$((n_unres + 1))
              echo "[watchdog $sid] close: $member pane=$pane UNRESOLVED — cc-teardown could not SEE this pane (not a safety verdict; the close leg is BLIND here): ${tout##*cc-teardown: }"
            else
              n_refuse=$((n_refuse + 1)); echo "[watchdog $sid] close: $member pane=$pane REFUSE (rc 2); left alone"
            fi ;;
        5)  n_fail=$((n_fail + 1)); echo "[watchdog $sid] close: $member pane=$pane FAIL LOUD — acted but the pane SURVIVED (rc 5)" ;;
        *)  n_fail=$((n_fail + 1)); echo "[watchdog $sid] close: $member pane=$pane cc-teardown rc=$trc (unexpected); left alone" ;;
      esac
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "rc=$trc" "$ev" >> "$plan" 2>/dev/null || true
    else
      local why="unarmed"; [[ -n "$tdbin" ]] || why="cc-teardown-unavailable"
      echo "[watchdog $sid] close: WOULD-CLOSE $member pane=$pane ($why — set LCW_ORPHAN_CLOSE=1 to arm)"
      printf '%s\t%s\t%s\t%s\n' "$member" "$pane" "WOULD-CLOSE($why)" "$ev" >> "$plan" 2>/dev/null || true
    fi
  done < "$status"

  if (( armed )); then
    echo "[watchdog $sid] close complete: $n_ok torn down, $n_defer defer, $n_refuse refuse, $n_unres UNRESOLVED, $n_fail FAIL, $n_skip skipped"
    # A leg that resolved NOTHING is not a leg that had nothing to do. Say so at the same volume as
    # a failure, so inertness can never again read as a clean run (this is the signal whose absence
    # let 100%-abstain look like success for three days).
    if (( n_unres > 0 )); then
      echo "[watchdog $sid] close BLIND: $n_unres of $n_elig eligible pane(s) could not be resolved by cc-teardown — these assignees are STILL RUNNING and no safety gate judged them; this is a wiring failure, not a verdict"
    fi
  else
    echo "[watchdog $sid] close UNARMED: $n_elig orphaned pane(s) left RUNNING, $n_skip skipped — plan in $plan (arm: LCW_ORPHAN_CLOSE=1)"
  fi
  return 0
}

# Test/debug entrypoints for the two team-level legs (both are top-level for the same reason the
# classify helpers are: the daemon subshell inherits them AND they stay unit-testable).
if [[ "${1:-}" == "--harvest-team" ]]; then
  harvest_team_reports "${2:-}" "${3:-}"; exit 0
fi
if [[ "${1:-}" == "--close-panes" ]]; then
  close_orphaned_panes "${2:-}" "${3:-}"; exit 0
fi

# Test/debug entrypoint: resolve+print one member's harvested report (name, cwd).
if [[ "${1:-}" == "--harvest-member" ]]; then
  _t=$(member_transcript "${2:-}" "${3:-}")
  [[ -n "$_t" ]] || { echo "NO-TRANSCRIPT"; exit 0; }
  echo "TRANSCRIPT $_t"; last_assistant_text "$_t"; echo; exit 0
fi

# Test/debug entrypoint (CC never passes args to this SessionStart hook): classify a
# session id (+ optional pid, to join its close-record) and exit, without spawning the
# daemon or reading stdin.
if [[ "${1:-}" == "--classify" ]]; then
  # $4 = death epoch (optional; omitted ⇒ now). cc-crash-report --backfill passes the timestamp of the
  # watchdog-log line that recorded the death, so a historical death is judged against ITS OWN moment.
  classify_death "${2:-}" "${3:-}" "${4:-}"; echo; exit 0
fi
# Debug/test entrypoint: print a pid's close-record enrichment (EXIT<TAB>SIGNAL<TAB>PATH<TAB>VERSION).
if [[ "${1:-}" == "--close-fields" ]]; then
  close_record_summary "${2:-}"; echo; exit 0
fi

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo '')
LEAD_PID="${PPID:-$$}"

if [[ -z "$SESSION_ID" ]]; then
  log "no session_id from hook input — using PID $LEAD_PID as key"
  SESSION_ID="pid-$LEAD_PID"
fi

# ── SINGLE-INSTANCE GUARD (audit 2026-07-22 root cause 4, S1) ─────────────────────────────────────
# SessionStart fires on startup AND resume AND clear AND compact, and this hook spawned a daemon
# UNCONDITIONALLY on every one of them. Nothing retired the previous incarnation, so a long-lived pane
# accumulated watchers over its life — all polling the same lead pid, all independently entitled to
# declare its death. That is the count inflation the audit measured in the watchdog log: 3064 "LEAD
# CRASH detected" lines over 2597 distinct pids, one pid recorded 19 times. Per-death consequences
# multiply with it — a duplicated ledger row, a duplicated shutdown_request into every teammate inbox,
# a duplicated teardown of the same panes.
#
# The guard needs both halves of the question, because "a daemon already exists for this sid" has two
# opposite answers:
#   · SAME lead pid  ⇒ a genuine duplicate SessionStart (resume/clear/compact inside one process).
#                      The incumbent is watching the right pid. SKIP — spawning again adds a watcher,
#                      never coverage.
#   · DIFFERENT pid  ⇒ the sid moved to a NEW process. The incumbent is now watching a pid that is gone
#                      (or, worse, RECYCLED to an unrelated process, which reads as alive forever), so
#                      it would either declare a CRASH for a session that is alive or never fire again.
#                      RETIRE it, then spawn fresh. Skipping here would leave the live session unwatched.
#
# Identity is {pid, start-time}, never a bare kill -0: the OS recycles pids, and a recycled pid reads as
# a live daemon — which would make this guard silently skip spawning and leave a session with NO watcher
# at all (strictly worse than the duplication it exists to prevent). Same discipline as the pid-identity
# checks in lead-supervisor.sh and cc-teardown's teardown pin.
DAEMON_FILE="$WATCHDOG_DIR/$SESSION_ID.daemon"
daemon_alive() { # $1=daemon-file → 0 iff it records a LIVE process that is still the one we recorded
  local f="$1" dpid dstart cur
  [[ -f "$f" ]] || return 1
  IFS=$'\t' read -r dpid dstart < "$f" 2>/dev/null || return 1
  case "$dpid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$dpid" 2>/dev/null || return 1
  cur=$(ps -o lstart= -p "$dpid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
  [[ -n "$cur" && -n "$dstart" && "$cur" == "$dstart" ]]
}
# PREV_LEAD must be read BEFORE the pidfile is rewritten below — it is the only record of which process
# the incumbent daemon is actually watching.
PREV_LEAD=$(cat "$WATCHDOG_DIR/$SESSION_ID.pid" 2>/dev/null || true)
if daemon_alive "$DAEMON_FILE"; then
  if [[ -n "$PREV_LEAD" && "$PREV_LEAD" == "$LEAD_PID" ]]; then
    log "watchdog ALREADY RUNNING for session=$SESSION_ID pid=$LEAD_PID — duplicate SessionStart, not spawning a second daemon"
    exit 0
  fi
  # sid re-registered under a new process ⇒ the incumbent is stale. Kill by the VERIFIED identity only,
  # so a recycled pid can never make this signal a stranger.
  IFS=$'\t' read -r _stale_pid _ < "$DAEMON_FILE" 2>/dev/null || _stale_pid=""
  if [[ -n "$_stale_pid" ]]; then
    kill "$_stale_pid" 2>/dev/null || true
    log "retired stale watchdog daemon pid=$_stale_pid for session=$SESSION_ID (was watching lead ${PREV_LEAD:-<none>}, now $LEAD_PID)"
  fi
fi

# Record session→PID mapping for orphan-reaper to consult
echo "$LEAD_PID" > "$WATCHDOG_DIR/$SESSION_ID.pid"
echo "$SESSION_ID" > "$WATCHDOG_DIR/$SESSION_ID.id"
log "registered session=$SESSION_ID pid=$LEAD_PID"

# Spawn detached watchdog daemon. Uses setsid + nohup + disown to survive
# the hook process exit; daemon itself polls via kill -0 every 30s.
(
  # Self-contained daemon. Exits cleanly when:
  #   (a) lead PID gone AND any owned team handled, or
  #   (b) the pid file is removed (session ended cleanly)

  exec </dev/null >>"$LOG_FILE" 2>&1
  trap '' HUP

  local_watchdog() {
    local pid="$1" sid="$2"
    local pid_file="$WATCHDOG_DIR/$sid.pid"

    while :; do
      # pid file gone = clean shutdown elsewhere
      [[ -f "$pid_file" ]] || { echo "[watchdog $sid] pid file gone — exit"; return 0; }
      # lead process gone = crash detected
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "[watchdog $sid] LEAD CRASH detected pid=$pid"
        handle_crash "$pid" "$sid"
        return 0
      fi
      sleep 30
    done
  }

  CRASH_JSONL="$HOME/.claude/logs/claude-crashes.jsonl"

  handle_crash() {
    local pid="$1" sid="$2"
    local affected_team_dirs=()

    # ── ONE handler per death (belt to the single-instance guard's braces) ──
    # The guard above stops watchers ACCUMULATING; this stops two that already coexist from both
    # processing one death. The existing pid-equality pidfile removal at the end of this function
    # already de-dupes SEQUENTIAL handlers (a later daemon finds no pidfile and takes its clean-exit
    # branch), but it removes the pidfile only AFTER team handling — so two daemons waking inside that
    # window both proceed, and the death is recorded twice, the shutdown_requests injected twice, the
    # same panes torn down twice. mkdir is the atomic claim; the loser says so and returns without
    # duplicating anything. Keyed by sid AND pid so a later, genuinely different death still claims.
    local claim="$WATCHDOG_DIR/$sid.death-$pid.d" claim_mtime claim_age
    if ! mkdir "$claim" 2>/dev/null; then
      # A claim older than 10 min means its holder died mid-handling (same stale-reclaim idiom as the
      # inbox lock below); reclaim it so a crash is never left permanently unhandled by a dead handler.
      claim_mtime=$(stat -f%m "$claim" 2>/dev/null || echo 0)
      claim_age=$(( $(date +%s) - ${claim_mtime:-0} ))
      if [[ "${claim_mtime:-0}" -gt 0 && "$claim_age" -ge 600 ]]; then
        echo "[watchdog $sid] reclaiming a stale death-claim for pid=$pid (holder gone ${claim_age}s)"
      else
        echo "[watchdog $sid] death of pid=$pid already claimed by another handler — not duplicating"
        return 0
      fi
    fi

    # Classify the death + snapshot cause BEFORE team handling, so solo AND team
    # deaths land in the structured crash ledger honestly (classify_death + find_transcript
    # are defined at top level and inherited by this subshell).
    local _cls class cause kb recs mem_free concurrent
    _cls=$(classify_death "$sid" "$pid")
    class=$(printf '%s' "$_cls" | cut -f1)
    cause=$(printf '%s' "$_cls" | cut -f2)
    kb=$(printf '%s' "$_cls" | cut -f3)
    recs=$(printf '%s' "$_cls" | cut -f4)
    mem_free=$(/usr/bin/memory_pressure 2>/dev/null | awk -F'[: ]+' '/free percentage/{print $(NF)}' | tr -d '%' || true)
    # grep -c exits 1 on zero matches (true when the dead session was the LAST claude proc);
    # `|| true` keeps that from tripping `set -e` and aborting handle_crash before the crash
    # record AND the team-recovery below run. grep still prints "0" to stdout.
    # shellcheck disable=SC2009  # ps|grep is deliberate: one pattern counts BOTH binary names portably
    concurrent=$(ps aux 2>/dev/null | grep -cE '[c]laude\.exe|[n]ode_modules/\.bin/claude' || true)
    # claude_version — THE decisive field: the crash rate is version-correlated (a regression
    # onset at 2.1.207: 2.1.183=0.02% → 2.1.207=4.76% → 2.1.215=1.56%, all mid-Bash in-process
    # deaths, NOT transcript size). Read from the transcript tail (every record carries it), cheap.
    local cver="?" tpath sterr=""
    tpath=$(find_transcript "$sid" 2>/dev/null || true)
    [[ -n "$tpath" ]] && cver=$(tail -c 65536 "$tpath" 2>/dev/null | grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' | tail -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "?")
    # stderr_log — join to the launcher's per-pid stderr capture (names the exact mechanism).
    # shellcheck disable=SC2012  # ls -1t is deliberate (newest-first mtime order on our own fixed pattern)
    sterr=$(ls -1t "$HOME/.claude/logs/stderr/"*"-${pid}.log" 2>/dev/null | head -1 || true)
    # close-record enrichment (bin/cc-close-attrib): the per-pid exit_code/signal/version + the
    # path to the (secret-safe) stderr_tail. exit_code/signal are the decisive attribution fields;
    # when the transcript never carried a version, the close-record's fills the "?".
    local cr_summary cr_exit="" cr_sig="" cr_path="" cr_ver=""
    cr_summary=$(close_record_summary "$pid")
    if [[ -n "$cr_summary" ]]; then
      cr_exit=$(printf '%s' "$cr_summary" | cut -f1)
      cr_sig=$(printf '%s' "$cr_summary" | cut -f2)
      cr_path=$(printf '%s' "$cr_summary" | cut -f3)
      cr_ver=$(printf '%s' "$cr_summary" | cut -f4)
      [[ "$cver" == "?" && -n "$cr_ver" ]] && cver="$cr_ver"
    fi
    printf '{"ts":"%s","sid":"%s","pid":%s,"class":"%s","cause":"%s","claude_version":"%s","transcript_kb":%s,"records":%s,"mem_free_pct":"%s","concurrent_claude":%s,"stderr_log":"%s","exit_code":"%s","signal":"%s","stderr_tail_path":"%s","version":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "${pid:-0}" "$class" "$cause" "${cver:-?}" "${kb:-0}" "${recs:-0}" "${mem_free:-?}" "${concurrent:-0}" "${sterr:-}" "${cr_exit:-}" "${cr_sig:-}" "${cr_path:-}" "${cr_ver:-}" \
      >> "$CRASH_JSONL" 2>/dev/null || true
    echo "[watchdog $sid] death class=$class cause=$cause (${kb}KB/${recs}recs mem_free=${mem_free:-?}% concurrent=${concurrent})"
    # A deliberate recycle is not a crash — only alert on a genuine crash.
    if [[ "$class" == "CRASH" ]]; then
      lcw_osa osascript -e "display notification \"Session ${sid:0:8} crashed — ${cause}. See claude-crashes.jsonl\" with title \"Claude Crash\" sound name \"Basso\"" 2>/dev/null || true
    fi

    # Which teams had this session as lead? Scan ALL team roots — CC writes
    # $CLAUDE_CONFIG_DIR/teams/<team>/, so *2/*3-launcher leads (claude-next2 /
    # claude-fable2 → ~/.claude-secondary; claude-next3 / claude-fable3 →
    # ~/.claude-tertiary) keep their team state only under that account's teams/
    # (memory: teammate-shutdown-secondary-config-dir-2026-06-09). The dir each
    # config was FOUND in is carried through — never re-derived from a root.
    for team_config in "$HOME/.claude/teams"/*/config.json "$HOME/.claude-secondary/teams"/*/config.json "$HOME/.claude-tertiary/teams"/*/config.json; do
      [[ -f "$team_config" ]] || continue
      local team_dir
      team_dir=$(dirname "$team_config")
      local team_name
      team_name=$(basename "$team_dir")
      [[ "$team_name" == "_archive" ]] && continue
      local lead_sid
      lead_sid=$(jq -r '.leadSessionId // empty' "$team_config" 2>/dev/null)
      if [[ "$lead_sid" == "$sid" ]]; then
        affected_team_dirs+=("$team_dir")
      fi
    done

    if [[ ${#affected_team_dirs[@]} -eq 0 ]]; then
      echo "[watchdog $sid] crash — no teams affected (lead had no active team)"
      # rm-race guard: only reap the pidfile if it still holds OUR pid — a resume/re-fire may have
      # overwritten it with the successor incarnation's LIVE pid, and deleting that silently disarms
      # a live session (frontier finding: 125 proven cross-incarnation disarms).
      if [[ "$(cat "$WATCHDOG_DIR/$sid.pid" 2>/dev/null)" == "$pid" ]]; then
        rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id" "$WATCHDOG_DIR/$sid.daemon"
        gc_teardown_marker "$sid" || true
      fi
      rmdir "$claim" 2>/dev/null || true      # release the death-claim (never leave a dir per death)
      return 0
    fi

    echo "[watchdog $sid] crash affects ${#affected_team_dirs[@]} team(s): ${affected_team_dirs[*]}"

    # ORDER IS LOAD-BEARING: harvest (a) → shutdown_request → close panes (b). cc-teardown kills
    # the process and closes the pane, and a closed pane cannot be harvested — so the reports come
    # off disk FIRST, unconditionally, and only then is anything reaped.
    for team_dir in "${affected_team_dirs[@]}"; do
      write_crash_report "$team_dir" "$pid" "$sid"
      harvest_team_reports "$team_dir" "$sid"
      send_shutdown_requests "$team_dir" "$sid"
      close_orphaned_panes "$team_dir" "$sid"
    done

    lcw_osa osascript -e "display notification \"Lead crashed. ${#affected_team_dirs[@]} team(s) affected. See CRASH_REPORT.md\" with title \"Claude Code Watchdog\" sound name \"Basso\"" 2>/dev/null || true
    printf '\a' >/dev/tty 2>/dev/null || true

    # rm-race guard (see above): never delete a pidfile a successor incarnation now owns.
    if [[ "$(cat "$WATCHDOG_DIR/$sid.pid" 2>/dev/null)" == "$pid" ]]; then
      rm -f "$WATCHDOG_DIR/$sid.pid" "$WATCHDOG_DIR/$sid.id" "$WATCHDOG_DIR/$sid.daemon"
      gc_teardown_marker "$sid" || true
    fi
    rmdir "$claim" 2>/dev/null || true        # release the death-claim (never leave a dir per death)
  }


  write_crash_report() {
    local team_dir="$1" pid="$2" sid="$3"
    local team_name
    team_name=$(basename "$team_dir")
    local team_root
    team_root=$(dirname "$team_dir")
    local report="$team_dir/CRASH_REPORT.md"

    {
      echo "# Lead Crash Report"
      echo ""
      echo "- **Team**: $team_name"
      echo "- **Lead PID**: $pid (dead at $(date '+%Y-%m-%d %H:%M:%S'))"
      echo "- **Lead session**: $sid"
      echo ""
      echo "## Members"
      jq -r '.members[] | "- \(.name) (agentId=\(.agentId), cwd=\(.cwd // "?"))"' \
        "$team_dir/config.json" 2>/dev/null || echo "- (unable to parse config.json)"
      echo ""
      echo "## Last 5 inbox messages per member"
      for inbox in "$team_dir/inboxes"/*.json; do
        [[ -f "$inbox" ]] || continue
        local member
        member=$(basename "$inbox" .json)
        [[ "$member" == "team-lead" ]] && continue
        echo ""
        echo "### $member"
        jq -r '.[-5:] | .[] | "- [\(.timestamp // "?")] from=\(.from // "?"): \(.summary // (.text | tostring | .[0:200]))"' \
          "$inbox" 2>/dev/null || echo "(unable to parse)"
      done
      echo ""
      echo "## Harvested assignee reports"
      echo ""
      echo "Final reports are recovered from DISK TRUTH (each assignee's transcript) into"
      echo "\`$team_dir/HARVEST/\` — one \`<member>.md\` per assignee, plus \`status.tsv\`."
      echo "They are NOT in any inbox: a named assignee's final text is never delivered as a"
      echo "message, so the transcript is the only place it exists. Read these BEFORE respawning —"
      echo "finished work must never be re-run."
      echo ""
      echo "## Recovery"
      echo ""
      echo "1. Start a new claude session. Do NOT \`claude --resume\`."
      echo "2. Archive this team dir: \`mv $team_dir $team_root/_archive/$team_name-\$(date +%s)\`"
      echo "3. Respawn from disk truth: \`python3 ~/.claude/scripts/limit-recover/lr-audit.py --team $team_name --salvage-dir /tmp/lr-salvage-$team_name\` — VERBATIM respawn briefs land in salvage/teams/$team_name/<member>.json (.respawn_call). Read deliverables already on disk first (never re-run finished work); course-change respawns via \`cc-respawn\`."
      echo "4. Check teammate worktrees for uncommitted work: \`git reflog refs/checkpoints/<member>/\` (if teammate-checkpoint.sh was active)."
      echo ""
    } > "$report"

    echo "[watchdog] wrote $report"
  }

  send_shutdown_requests() {
    local team_dir="$1" sid="$2"

    for inbox in "$team_dir/inboxes"/*.json; do
      [[ -f "$inbox" ]] || continue
      local member
      member=$(basename "$inbox" .json)
      [[ "$member" == "team-lead" ]] && continue

      local envelope
      envelope=$(jq -n \
        --arg from "watchdog" \
        --arg text "{\"type\":\"shutdown_request\",\"reason\":\"lead crashed — see CRASH_REPORT.md\"}" \
        --arg summary "LEAD CRASH — shutting down" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
        '{from:$from, text:$text, summary:$summary, timestamp:$ts, read:false}')

      # Append to inbox array. jq read-modify-write is NOT atomic, and team-orphan-reaper.sh
      # appends to the SAME inbox under the SAME lock name ("$inbox.lock.d") — an unguarded
      # race drops one append. mkdir is atomic → use it as the mutex: acquire ≤2s (20×0.1s);
      # a lock dir older than 10s ⇒ a crashed holder, reclaim it; on give-up append lock-free
      # (a duplicate shutdown_request is harmless, a hung watchdog is not). rmdir after mv.
      local lockd="$inbox.lock.d" have_lock=0 i lock_age lock_mtime now_s
      for (( i=0; i<20; i++ )); do
        if mkdir "$lockd" 2>/dev/null; then have_lock=1; break; fi
        lock_mtime=$(stat -f%m "$lockd" 2>/dev/null || echo 0)
        now_s=$(date +%s)
        lock_age=$(( now_s - lock_mtime ))
        if (( lock_mtime > 0 && lock_age >= 10 )); then
          rmdir "$lockd" 2>/dev/null || true   # stale holder — reclaim on the next iteration
        fi
        sleep 0.1
      done

      local tmp
      tmp=$(mktemp)
      if jq --argjson env "$envelope" '. += [$env]' "$inbox" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$inbox"
        echo "[watchdog] shutdown_request → $member"
      else
        rm -f "$tmp"
        echo "[watchdog] WARN: failed to inject shutdown_request for $member"
      fi
      if (( have_lock )); then rmdir "$lockd" 2>/dev/null || true; fi
    done
  }

  local_watchdog "$LEAD_PID" "$SESSION_ID"
) </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!
disown

# Record the daemon's {pid, start-time} so the next SessionStart can tell a live incumbent from a
# recycled pid. Written by the PARENT (the subshell cannot portably read its own lstart before doing
# work) and best-effort: an unwritable file degrades to today's behaviour — a duplicate spawn — never
# to a missing watcher. If lstart is unreadable the identity is left unverifiable, which daemon_alive
# treats as NOT alive: it re-spawns rather than risk skipping and leaving a session unwatched.
WATCHDOG_START=$(ps -o lstart= -p "$WATCHDOG_PID" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')
printf '%s\t%s\n' "$WATCHDOG_PID" "$WATCHDOG_START" > "$DAEMON_FILE" 2>/dev/null || true

log "spawned watchdog daemon pid=$WATCHDOG_PID for session=$SESSION_ID pid=$LEAD_PID"
exit 0
