#!/usr/bin/env bash
# lr-lib.sh — the ONE home for the limit-recover predicates that more than one caller needs
# (LIMIT_RECOVER_100P, 2026-09-09). Source, don't execute. Pure functions; no side effects at load.
#
# Callers: scripts/limit-recover/lr-handoff.sh (the per-session front end), lr-reset-poller.sh (the
# launchd daemon), lr-fleet.sh (the fleet driver). Two spellings of one predicate is how sibling
# auditors end up disagreeing about one population (memory: sibling-auditors-must-share-the-state-
# model) — the tier read, the liveness census, the transplant read and the engagement oracle all
# used to be re-derived per caller, and each divergence was an incident:
#   · tier: the poller minted tier-less launchers, so every unattended Fable recovery landed on Opus
#     (measured 2026-09-09 on 52e35019: transcript said claude-fable-5-1/xhigh, argv said opus/high);
#   · liveness: `pgrep -f "resume <sid>"` is blind to a fresh launch's argv, so the poller resumed a
#     session whose original pane was alive — two writers, one transcript, one account.
# shellcheck shell=bash

[ -n "${LR_LIB_LOADED:-}" ] && return 0 2>/dev/null
LR_LIB_LOADED=1

# THE PREDICATE MODULE, for the two python readers below (LIMIT_DETECT_100P W4 step 3). BASH_SOURCE,
# never $0: this file is SOURCED, so $0 is the caller — a hook, the poller, lr-fleet — and through
# the ~/.claude per-file symlink farm its dirname is not where our sibling module sits. Both readers
# already fork one python; the module is imported INSIDE that fork, so this costs no extra process.
: "${LR_LIB_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"

# ── the four account stores ──────────────────────────────────────────────────────────────────────
lr_config_dirs() { # → one config dir per line; ~/.claude and ~/.claude-next are ONE account (mirror)
  if [ -n "${LR_CONFIG_DIRS:-}" ]; then printf '%s\n' "$LR_CONFIG_DIRS" | tr ':' '\n'; return 0; fi
  # DEDUPED BY THE DIRECTORY THE SCAN ACTUALLY READS, not by the config dir's own name.
  # `~/.claude-next/projects` is a SYMLINK to `~/.claude/projects` on this box, so every consumer
  # walked 421 of 2,579 transcript files TWICE — 16.3% of the census, paid on the hot path
  # (U14 §1.1, 2026-09-19). lr-fleet dedupes AFTERWARDS, by row, at lf_dedup_mirror; that corrects
  # the OUTPUT and cannot recover the work, and every other caller pays the full double walk with
  # no dedupe at all. The identity is `pwd -P` of `projects/`: two stores that resolve to one
  # directory hold one population however they are spelled. FIRST spelling wins, so `.claude` beats
  # its `.claude-next` mirror — the same direction lf_dedup_mirror already keeps, and the one the
  # in-repo account map names.
  local h key seen=""
  for h in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -d "$h/projects" ] || continue
    # `cd && pwd -P` is a builtin pair — no fork, and no dependency on a `realpath`/`readlink -f`
    # that is not on every PATH this library is sourced from. An unreadable dir keeps its own path
    # as the key rather than collapsing onto the empty string, which would drop every later store.
    key="$(cd "$h/projects" 2>/dev/null && pwd -P)"; [ -n "$key" ] || key="$h/projects"
    case "$seen" in *"|$key|"*) continue ;; esac
    seen="$seen|$key|"
    printf '%s\n' "$h"
  done
  return 0
}

# ── TIER: what the session was ACTUALLY running when it hit the limit ────────────────────────────
# The transcript carries (message.model, effort) per assistant turn; argv carries only the LAUNCH
# tier and the registry row carries neither. The tail of a transcript may belong to a rescuer (a
# same-account duplicate appending by path), so the pick is the last NON-ERROR turn BEFORE the last
# limit error, and only when there is no limit error at all the last turn overall.
lr_tier_from_transcript() { # $1=cfg $2=sid → "model effort" on stdout / rc 1 when nothing on disk
  local f
  for f in "$1"/projects/*/"$2".jsonl "$1"/projects/*/"$2".jsonl.handed-off; do
    [ -f "$f" ] || continue
    /usr/bin/python3 - "$f" "$LR_LIB_DIR" <<'PY' && return 0
import json, sys
try:
    sys.path.insert(0, sys.argv[2])
    from lr_predicate import classify_text
except Exception:                       # module unreachable: degrade to the pre-W4 test,
    classify_text = None                # never to "this session never hit a limit"


def _is_limit(d, m):
    # classify_TEXT, not classify_record, and the difference is recall. This branch has ALREADY
    # established the envelope (we are inside isApiErrorMessage), which is the exact case the
    # module documents classify_text for: hand the envelope back and T1 decides, omit it and the
    # text does. classify_record is T1-STRICT, so a record carrying the envelope and a cap
    # sentence but no structured error field reads limit=False — and the tier read would then
    # pick the LAST turn overall, which on a rescued transcript is the rescuer's tier. That is
    # the exact incident this function exists to prevent.
    c = m.get("content")
    t = c if isinstance(c, str) else " ".join(
        x.get("text", "") for x in (c or []) if isinstance(x, dict))
    if classify_text is not None:
        return classify_text(t, error=d.get("error"),
                             api_error_status=d.get("apiErrorStatus"))["limit"]
    return "hit your" in t or "reached your" in t
last_limit = None; turns = []
for line in open(sys.argv[1], errors="replace"):
    if '"assistant"' not in line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant":
        continue
    ts = d.get("timestamp") or ""
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    if d.get("isApiErrorMessage"):
        # THE MODULE, not a substring pair. This site and lr_last_api_error below sat 97 lines apart
        # in ONE file and disagreed about Fable: this one caught it (it tested "reached your") and
        # that one did not, so the tier read and the kind read described different deaths.
        if _is_limit(d, m):
            last_limit = ts
        continue
    model = m.get("model") or ""
    if not model or model.startswith("<synthetic"):
        continue
    turns.append((ts, model, d.get("effort") or ""))
if not turns:
    sys.exit(1)
pick = None
if last_limit:
    before = [t for t in turns if t[0] < last_limit]
    pick = before[-1] if before else None
if pick is None:
    pick = turns[-1]
print(pick[1], pick[2])
PY
  done
  return 1
}

# ── ENGAGEMENT after a baseline: the one thing a husk can never produce ──────────────────────────
# A content-bearing, NON-ERROR assistant turn newer than the baseline, in the named store's copy.
# `isApiErrorMessage` is the limit hitting again; "No response requested." is the synthetic entry a
# resume inserts; neither is a turn. Byte-identical core to handoff-fire.sh's resume_engaged (the
# parity test in tests/lr-lib.bats pins that).
lr_engaged_after() { # $1=cfg $2=sid $3=baseline (UTC, %FT%T) → 0 engaged / 1 not
  local cfg="${1:-}" sid="${2:-}" t0="${3:-}" f
  { [ -n "$cfg" ] && [ -n "$sid" ]; } || return 1
  for f in "$cfg"/projects/*/"$sid".jsonl; do
    [ -f "$f" ] || continue
    /usr/bin/python3 - "$f" "$t0" <<'PY' && return 0
import json, sys
f, t0 = sys.argv[1], sys.argv[2]
for line in open(f, errors="replace"):
    if '"assistant"' not in line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant" or d.get("isApiErrorMessage"):
        continue
    if (d.get("timestamp") or "") <= t0:
        continue
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content")
    txt = c if isinstance(c, str) else (json.dumps(c) if c else "")
    if not txt.strip() or txt.strip() == "No response requested.":
        continue
    sys.exit(0)
sys.exit(1)
PY
  done
  return 1
}

# ── THE DEATH RECORD: Q3 predicate 2, for any caller that needs it cheaply ───────────────────────
# "The LAST assistant record is an api error" — ANY `error` value, not just the quota spellings
# (docs/plans/NONLIMIT_RESUME_LADDER.md § W1.1 Q3). Three callers had already grown their own
# spelling of this before it lived here: lr-fleet's inline census python, lr-audit.py's
# scan_lead_transcript, and hooks/recover-inject.sh. That is exactly the divergence this file
# exists to prevent — see the header's liveness and tier incidents.
#
# TAIL-BOUNDED ON PURPOSE. A UserPromptSubmit hook runs on EVERY prompt, so it cannot afford a full
# pass over a transcript that grows to tens of MB. The predicate only ever asks about the LAST
# assistant record, so a fixed tail answers it exactly; a caller that needs the whole population of
# delegations must use `lr-audit.py --ledger-only` instead, which reads the file once.
#
# THE ENVELOPE IS THE GATE, never the text: `type:"assistant"` + `isApiErrorMessage:true`. That pair
# is what makes a text-widened read safe -- a session merely DISCUSSING "ENOTFOUND" or quoting a
# limit message in prose (this repo does constantly, including the session that wrote this) is not a
# synthetic api-error record and can never match. `No response requested.` turns are skipped for the
# same reason lr_engaged_after skips them: they are not a real turn.
lr_last_api_error() { # $1=transcript → "<uuid>\t<error>\t<kind>\t<timestamp>"; rc 1 when the last assistant record is NOT an api error
  local f="${1:-}" bytes="${LR_TAIL_BYTES:-131072}"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  tail -c "$bytes" "$f" 2>/dev/null | /usr/bin/python3 -c '
import hashlib, json, sys
try:
    sys.path.insert(0, sys.argv[1])
    from lr_predicate import classify_text
except Exception:
    # THE MODULE IS UNREACHABLE. Degrade to the pre-W4 text test, never to rc 1: rc 1 from this
    # function means "the last assistant record is NOT an api error", so an import failure would
    # tell every caller that a capped fleet is a healthy one. The apostrophe is spelled with chr
    # because this whole block is a single-quoted shell argument.
    classify_text = None
last = None
for line in sys.stdin:
    if "\"assistant\"" not in line: continue
    try: d = json.loads(line)
    except Exception: continue          # a tail starts mid-record; a partial line is not a verdict
    if d.get("type") != "assistant": continue
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    c = m.get("content")
    txt = c if isinstance(c, str) else " ".join(
        x.get("text", "") for x in (c or []) if isinstance(x, dict))
    if txt.strip() == "No response requested.": continue
    last = (d, txt)
if last is None or not last[0].get("isApiErrorMessage"):
    sys.exit(1)
d, txt = last
# The LATCH KEY. A death record carries a uuid in practice, but a latch that silently degrades to
# "no key" would re-emit on every prompt forever, so fall back to a digest of the fields that
# identify this record. Never fall back to a constant: that would latch the FIRST death for the
# life of the session and go silent on every later one.
uid = d.get("uuid") or "sha-" + hashlib.sha256(
    ((d.get("timestamp") or "") + "\x00" + txt[:400]).encode("utf-8")).hexdigest()[:24]
# EXACTLY FOUR TAB FIELDS, and that is load-bearing rather than tidy. net-recover-arm.sh line 195
# strips every character up to the last TAB and keeps what is left, so it takes the LAST field
# whatever the last field happens to be, and feeds it to a string compare against a turn timestamp.
# A fifth column was measured turning that read into the literal entrypoint value, after which the
# asyncRewake never fires (judge Da-latency FATAL 2). So the module widens what field 3 KNOWS and
# changes nothing about the shape: a Fable cap now prints limit, which is what stops
# recover-inject.sh line 101 telling the operator it is NOT a quota message.
# NOTE for the next editor: this block is a single-quoted python argument, so a dollar sign or a
# backtick anywhere in these comments raises a NEW shellcheck SC2016 on a file that has none.
if classify_text is not None:
    # The envelope is already established above, so this is classify_text with the envelope
    # handed back, exactly as the module documents. T1 rules when the record carries a
    # structured error; the text rules when it does not, which keeps the pre-W4 recall.
    kind = "limit" if classify_text(txt, error=d.get("error"),
                                    api_error_status=d.get("apiErrorStatus"))["limit"] else "other"
else:
    kind = "limit" if ("You" + chr(39) + "ve hit your") in txt else "other"
print("%s\t%s\t%s\t%s" % (uid, d.get("error") or "unknown", kind,
                          d.get("timestamp") or "-"))
' "$LR_LIB_DIR" || return 1
}

# ── Q3 predicate 3: a NON-SUCCESS task-notification in the tail ──────────────────────────────────
# The harness's third and last way to end delegated work: fail the task. Shape is quoted, not
# inferred -- a real record from this repo's corpus (docs/research/pane-theft-composer-guard.md:33):
#   {"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n
#    <task-id>bfpgwlzqu</task-id>\n<tool-use-id>toolu_01RwHg...</tool-use-id>\n
#    <output-file>...</output-file>\n<status>killed</status>\n<summary>...</summary>\n
#    </task-notification>"}
# Status vocabulary measured over 300 recent transcripts: completed 5979 · failed 358 · killed 180 ·
# running 29 · stopped 4. `running` is the only non-terminal value, and `completed` is the only
# success -- so this fires on failed/killed/stopped and stays quiet on the other two.
#
# TAIL-BOUNDED for the same reason as lr_last_api_error, and with the same consequence: this answers
# "did something just fail" cheaply, and CANNOT answer "which delegations are still open" -- that
# needs the whole file, so a caller confirms with `lr-audit.py --ledger-only` before acting.
lr_tail_nonsuccess_notification() { # $1=transcript → "<task_id>\t<tool_use_id>\t<status>"; rc 1 when none
  local f="${1:-}" bytes="${LR_TAIL_BYTES:-131072}"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  tail -c "$bytes" "$f" 2>/dev/null | /usr/bin/python3 -c '
import json, re, sys
TID = re.compile(r"<tool-use-id>\s*([^<\s]+)\s*</tool-use-id>")
TASK = re.compile(r"<task-id>\s*([^<\s]+)\s*</task-id>")
ST = re.compile(r"<status>\s*([^<\s]+)\s*</status>")
hit = None
for line in sys.stdin:
    if "<task-notification>" not in line: continue
    try: d = json.loads(line)
    except Exception: continue
    # Both carriers: the queue-operation ENQUEUE (.content) and the delivered user record.
    body = d.get("content")
    if not isinstance(body, str):
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        c = m.get("content")
        body = c if isinstance(c, str) else " ".join(
            x.get("text", "") for x in (c or []) if isinstance(x, dict))
    if not isinstance(body, str) or "<task-notification>" not in body: continue
    s = ST.search(body)
    status = (s.group(1) if s else "")
    if status in ("completed", "running", ""): continue
    t, k = TASK.search(body), TID.search(body)
    hit = ((t.group(1) if t else "-"), (k.group(1) if k else "-"), status)
if hit is None: sys.exit(1)
print("%s\t%s\t%s" % hit)
' || return 1
}

# ── LIVENESS: the registry, not argv ─────────────────────────────────────────────────────────────
# One line per LIVE process holding the sid: "<pane>\t<pid>\t<account>\t<cwd>". A row whose pid is
# dead is a stale row and is skipped; a row is written by the session's own SessionStart hook
# (hooks/session-register.sh) and is the only store keyed by pane that names the sid.
lr_registry_live_rows() { # $1=sid → rows on stdout; rc 0 when at least one is live, 1 when none
  local sid="${1:-}" regdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}" f pid pane acct cwd n=0
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  for f in "$regdir"/*.json; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in .*) continue ;; esac
    [ "$(jq -r '.session_id // .sessionId // empty' "$f" 2>/dev/null)" = "$sid" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    pane="$(jq -r '.paneUUID // empty' "$f" 2>/dev/null)"; [ -n "$pane" ] || pane="$(basename "$f" .json)"
    acct="$(jq -r '.account // empty' "$f" 2>/dev/null)"
    cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
    # PAD AT THE EMITTER. Tab is IFS-whitespace, so an empty cell does not read back empty — it
    # shifts every later column LEFT, silently, exit 0. `account` is the one non-last cell that can
    # be absent from a registry row (`.account // empty`); `pane` falls back to the filename and
    # `pid` is digit-validated above, so both are non-empty by construction, and `cwd` is LAST.
    printf '%s\t%s\t%s\t%s\n' "$pane" "$pid" "${acct:--}" "$cwd"; n=$((n + 1))
  done
  [ "$n" -gt 0 ]
}

# ── LIVENESS, SCOPED TO ONE STORE (W5-A, 2026-09-20) ─────────────────────────────────────────────
# lr_registry_live_rows above answers "is a process holding this sid", full stop — it takes ONLY a
# sid and cannot say WHICH store answered. The poller's transplant arm needs the other question:
# "did the SUCCESSOR, on the target store, actually come up?" A row on the SOURCE account answers
# that with a yes that means the opposite (that row IS the husk), so the unscoped predicate is not
# merely imprecise there, it is inverted.
#
# THE ACCOUNT FOLD IS NOT OPTIONAL, and it is lifted from lr_husk_state's own derivation for the
# same measured reason: hooks/session-register.sh writes `.account` as `basename $CLAUDE_CONFIG_DIR`
# with the leading dot stripped, and `~/.claude` and `~/.claude-next` are ONE account — a session
# started under CLAUDE_CONFIG_DIR=~/.claude-next registers as `claude-next` while its transcripts
# enumerate under `~/.claude`. Two of the three husks W10 measured carried exactly that mismatch, so
# a literal string compare would answer "no successor" for a common transplant target on this box.
lr_registry_live_rows_in_cfg() { # $1=sid $2=cfg dir → matching rows on stdout; rc 0 when >=1 is live
  local sid="${1:-}" cfg="${2:-}" want rows r_pane r_pid r_acct r_cwd n=0
  [ -n "$sid" ] && [ -n "$cfg" ] || return 1
  want="$(basename "${cfg%/}")"; want="${want#.}"
  case "$want" in claude-next) want=claude ;; esac
  rows="$(lr_registry_live_rows "$sid" 2>/dev/null)" || return 1
  # A heredoc, never a pipe: a `while` on the right of `|` runs in a subshell and its counter never
  # escapes (memory: assignment-inside-command-substitution-never-escapes).
  while IFS=$'\t' read -r r_pane r_pid r_acct r_cwd; do
    [ -n "$r_pane" ] || continue
    case "$r_acct" in claude-next) r_acct=claude ;; esac
    [ "$r_acct" = "$want" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$r_pane" "$r_pid" "$r_acct" "$r_cwd"; n=$((n + 1))
  done <<EOF
$rows
EOF
  [ "$n" -gt 0 ]
}

# ══ THE CORRECTED CAPACITY PROBE — ONE function, two callers (W2, 2026-09-19) ══════════════════
# Lifted VERBATIM out of lr-fleet.sh's lf_capacity_wait (226b73888) because a second caller appeared:
# lr-handoff's pre-transplant check. Two spellings of one probe is how the fleet and the launcher
# came to measure different gates in the first place (U05 §3.3) — the defect this whole wave is
# about — so the probe lives HERE and both callers take it.
#
# ── THE PHANTOM-ACTIVE CORRECTION (2026-09-19) — why a recovery could never be admitted ─────────
# A usage-limit kill ends the turn WITHOUT running the Stop hook, so hooks/session-beat.sh never
# writes the `stop` beat and the session's `kind:"prompt"` beat freezes on disk. Its pid stays alive
# (the TUI is sitting at its prompt), so cc_sp_active's liveness leg — which correctly discards a
# DEAD session's frozen beat — has nothing to discard, and the blocked session is counted mid-turn
# forever. spawn-presence.sh's own header calls this shape "a gate that tightens monotonically on
# its own accidents"; the limit kill is the door its pid check cannot close.
#
# MEASURED 2026-09-19: eight panes blocked on one account's 5-hour limit held frozen `prompt` beats
# aged 2360-4168 s with live pids. cc_sp_active read 12 against a ceiling of 8, so EVERY
# `lr-fleet --recover` attempt was refused for its full 600 s budget. The census inflated BY the
# blocked sessions was gating the recovery OF those blocked sessions.
#
# DIRECTION: this only ever SUBTRACTS sessions proven blocked — a live pid whose beat is a frozen
# `prompt` AND whose last assistant word is a usage-limit error. A session mid-retry after a network
# error is NOT subtracted (its turn may genuinely still be running, 93-101 min measured), an
# unreadable transcript is NOT subtracted, and the ceiling itself is untouched.
lr_phantom_actives() { # → count of live sessions whose mid-turn beat is a usage-limit corpse
  local dir b sid pid kind cfg tx n=0 rest ekind row
  dir="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
  [ -d "$dir" ] || { printf '0'; return 0; }
  for b in "$dir"/*.json; do
    [ -f "$b" ] || continue
    # ONE jq pass per beat. An empty field becomes `_`, which no check below accepts, because a
    # tab is IFS whitespace and `read` would otherwise collapse it and shift the next field left.
    row="$(jq -r 'if type=="object" then [(.kind // ""), (.pid // ""), (.sid // "")]
                  | map(tostring | if . == "" then "_" else . end) | @tsv else empty end' "$b" 2>/dev/null)" || continue
    IFS=$'\t' read -r kind pid sid <<<"$row" || continue
    [ "$kind" = prompt ] || continue
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue          # dead ⇒ the census already discards it
    case "$sid" in ''|*[!A-Za-z0-9-]*) continue ;; esac
    while IFS= read -r cfg; do
      [ -n "$cfg" ] || continue
      for tx in "$cfg"/projects/*/"$sid".jsonl; do
        [ -f "$tx" ] || continue
        IFS=$'	' read -r _ _ ekind rest <<<"$(lr_last_api_error "$tx" 2>/dev/null)" || ekind=""
        # break 2 leaves this beat's config-dir scan; break 3 left the per-beat loop and capped n at 1.
        [ "$ekind" = limit ] && { n=$((n + 1)); break 2; }
      done
    done <<EOF
$(lr_config_dirs)
EOF
  done
  printf '%s' "$n"
}

# ONE evaluation, no waiting — the WAIT belongs to the caller (the fleet loops on it; lr-handoff
# takes a single reading and parks). rc 0 = would admit, 9 = would refuse (CC_ADMIT_REASON set).
#
# THE LOAD TERM IS OFF, CALL-SCOPED. Not a weaker gate: it is the term whose INPUT is wrong
# (capacity-admit.sh:149-156 — an additional RESIDENT session moves load1 by ~0, so no ceiling value
# can make it correct). It is already OFF on the operator's own fire (handoff-fire.sh:6075) and on
# the Agent tool (agent-teams-enforce.sh:229); leaving it ON here put the retracted term on exactly
# the unattended path whose own header calls a standing refusal an outage. MEASURED 2026-09-19: 10
# of 10 lr-fire-resume refusals were term=load, and at 17:52:54 the box read 33.33 GB reclaimable,
# 3.18% segments and 2 active while this term refused at 4.15/core. An explicit CC_ADMIT_LOAD_TERM=on
# restores the old behaviour verbatim, ceiling and all.
#
# THE SEGMENT CEILING IS RAISED, CALL-SCOPED, FOR THE SAME REASON (operator ruling 2026-10-04: "we
# are self-recycling each one, taking one down to re-up the same one"). Every caller of this probe
# is a SWAP: the old process exits — releasing its compressed pages — before its replacement starts,
# so a swap does not grow the compressor pool the 50% spawn ceiling guards. MEASURED 2026-10-04: 12
# account moves refused at 60.5% segments, every one of them net-zero. 90% keeps a floor below the
# 100% observed at panic. LR_SEGMENT_PCT carries the value to the launcher so both ends evaluate one
# gate; an explicit CC_ADMIT_MAX_SEGMENT_PCT still wins.
#
# A LIBRARY THAT CANNOT BE REACHED IS LOUD, NEVER SILENT: a recovery must not be blocked because a
# telemetry library is missing, and it must never proceed without saying that it is ungated.
lr_capacity_probe_corrected() { # $1=caller $2=what → 0 would-admit / 9 would-refuse
  local caller="${1:-lr-recover}" what="${2:-recovery}" raw ph self=0 corrected rc=0
  command -v cc_capacity_probe >/dev/null 2>&1 || {
    echo "${caller}: capacity probe unavailable (scripts/lib/capacity-admit.sh not sourced) — proceeding UNGATED" >&2; return 0; }
  # THE SUBJECT DOES NOT COUNT AGAINST ITS OWN SWAP (2026-10-04). A probe run from inside a session's
  # tool call (the SELF switch verb) is by construction running in a session that is MID-TURN, so the
  # census counts the subject itself; after the swap that same session is the one active turn, so the
  # move is net-zero on this term too. Measured: pane 35 refused at "7 mid-turn, ceiling 7" with
  # itself among the 7. Daemon callers carry no CLAUDE_CODE_SESSION_ID and are unaffected.
  # Under-refuse direction only. Kill switch LR_SELF_ACTIVE_CORRECTION=off.
  [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ "${LR_SELF_ACTIVE_CORRECTION:-on}" != off ] && self=1
  # Left UNSET on any unreadable leg, so the probe then sees exactly what it saw before this existed.
  unset CC_SP_ACTIVE_OVERRIDE
  if [ "${LR_FLEET_PHANTOM_CORRECTION:-on}" != off ] && command -v cc_sp_active >/dev/null 2>&1; then
    raw="$(cc_sp_active 2>/dev/null || true)"
    ph="$(lr_phantom_actives 2>/dev/null || true)"
    case "${raw:-x}${ph:-x}" in
      *[!0-9]*) : ;;
      *) if [ $(( ph + self )) -gt 0 ] && [ "$raw" -gt 0 ]; then
           corrected=$(( raw - ph - self )); [ "$corrected" -lt 0 ] && corrected=0
           export CC_SP_ACTIVE_OVERRIDE="$corrected"
           echo "${caller}: active census ${raw} includes ${ph} limit-corpse beat(s) and ${self} for the subject itself — probing at ${corrected}" >&2
         fi ;;
    esac
  fi
  CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" \
    CC_ADMIT_MAX_SEGMENT_PCT="${CC_ADMIT_MAX_SEGMENT_PCT:-${LR_SEGMENT_PCT:-90}}" \
    cc_capacity_probe "$caller" "$what" || rc=$?
  unset CC_SP_ACTIVE_OVERRIDE
  return "$rc"
}

# ══ THE RUN'S STATE — append-only, one line per transition (W2, 2026-09-19) ═════════════════════
# The store is the run's OWN bundle dir, which the chain already mints, so there is no parallel tree
# to keep in step (D2-FT #16 refused an `index.jsonl` upsert: an unlocked read-modify-write loses
# updates). Readers compute the state as the LAST line; a terminal line is sticky against a later
# non-terminal one from a stale writer.
#
# NO `|| true` ANYWHERE ON THE WRITE (D3-FT R10). A failed append is reported on stderr and returns
# non-zero: a state log that silently drops lines is worse than none, because its silence reads as
# "nothing happened". And every field is jq-encoded — ONE malformed line aborts a `jq -rs` slurp,
# which then reads as "no records" (the same invariant capacity-admit's emitter keeps).
#
# ≤ 1 KB PER RECORD, ENFORCED AT THE WRITER. O_APPEND is atomic only up to the stdio buffer, so a
# record longer than it goes out as several write() calls and a concurrent appender splices into the
# middle of it (repo lesson: append-atomicity-ends-at-the-stdio-buffer). The detail is truncated
# here rather than trusted to be short.
#
# THE MUTEX IS A BELT, NOT THE GUARANTEE: the size cap is what makes the append atomic. The lock is
# bounded (2 s) and STOLEN when it is older than that, because a crashed writer must not be able to
# silence every later transition of the run.
lr_state_append() { # $1=run dir $2=state $3=stage $4=detail → 0 written / 1 LOUD failure
  local run="${1:-}" state="${2:-}" stage="${3:-}" detail="${4:-}" lock f n=0
  [ -n "$run" ] || { echo "lr_state_append: no run dir — state '$state' NOT recorded" >&2; return 1; }
  [ -n "$state" ] || { echo "lr_state_append: no state — nothing recorded for $run" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "lr_state_append: jq is not on PATH — state '$state' NOT recorded (a raw append would risk a malformed line)" >&2; return 1; }
  mkdir -p "$run" 2>/dev/null || { echo "lr_state_append: cannot create $run — state '$state' NOT recorded" >&2; return 1; }
  detail="$(printf '%s' "$detail" | cut -c1-600)"
  f="$run/events.jsonl"
  lock="$run/.events.lock"
  while ! mkdir "$lock" 2>/dev/null; do
    n=$((n + 1))
    if [ "$n" -ge 20 ]; then
      echo "lr_state_append: $lock held for >2s — stealing it (a crashed writer must not silence a run)" >&2
      rm -rf "$lock" 2>/dev/null || true
      mkdir "$lock" 2>/dev/null || break
      break
    fi
    sleep 0.1
  done
  if ! jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg run "$run" --arg st "$state" \
            --arg stg "$stage" --arg d "$detail" --arg w "${0##*/}:$$" --arg a "${LR_ATTEMPT:-1}" \
            '{ts:$ts,run:$run,state:$st,stage:$stg,detail:$d,writer:$w,attempt:$a}' >> "$f" 2>/dev/null; then
    rmdir "$lock" 2>/dev/null || true
    echo "lr_state_append: FAILED to append '$state' to $f — the run's state log is incomplete" >&2
    return 1
  fi
  rmdir "$lock" 2>/dev/null || true
  return 0
}

lr_state_current() { # $1=run dir → the last recorded state on stdout; rc 1 when the run has none
  local run="${1:-}" f last
  [ -n "$run" ] || return 1
  f="$run/events.jsonl"
  [ -s "$f" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  last="$(tail -1 "$f" 2>/dev/null | jq -r '.state // empty' 2>/dev/null)" || return 1
  [ -n "$last" ] || return 1
  printf '%s' "$last"
}

lr_resume_procs() { # $1=sid → pids of `--resume <sid>` processes (the argv census), one per line; rc 0 when any
  local sid="${1:-}" out
  [ -n "$sid" ] || return 1
  # THE PATTERN MUST NOT RIDE IN ARGV. `awk -v s="--resume $sid"` puts the very string being searched
  # for into the awk process's OWN command line, and `ps -axo command=` — started concurrently in the
  # same pipeline — prints it, so `index($0, s)` matched AWK ITSELF and this census answered YES for
  # every sid ever asked about. Measured 2026-09-09: `lr-fleet --locate` called a session with one
  # registry pane DUPLICATE and a session with none RESUMING, and the poller retired parked records
  # as already-running. pgrep excludes itself; a hand-rolled `ps | awk` does not (memory:
  # pgrep-excludes-the-callers-ancestors — a census is in its own population unless it says otherwise).
  # The sid travels in the ENVIRONMENT, which ps does not print.
  out="$(ps -axo pid=,ppid=,command= 2>/dev/null | LR_RP_SID="$sid" awk 'index($0, "--resume " ENVIRON["LR_RP_SID"]) { print $1"\t"$2 }' || true)"
  [ -n "$out" ] || return 1
  # ONE SESSION IS ONE PROCESS, NOT A CHAIN. A resume is launched through bin/cc-close-attrib, which
  # stays alive as the PARENT of the real `claude` and carries the whole command line in its own
  # argv — so this census saw TWO processes for ONE session. Measured 2026-09-09: `lr-fleet
  # --duplicates` called b418b97a a split brain over pids 16125 (the wrapper) and 16212 (its child),
  # one pane, one session — and its prescription was to retire a LIVE pane. Keep only the leaves:
  # a pid that is the PARENT of another pid in this set is the wrapper, not the session.
  out="$(printf '%s\n' "$out" | awk -F'\t' '{ pid[NR]=$1; par[$2]=1 } END { for (i=1;i<=NR;i++) if (!(pid[i] in par)) print pid[i] }')"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

lr_holder_count() { # $1=sid → number of DISTINCT live holders (registry panes + --resume leaves); overlap counted ONCE
  # THE OVERLAP IS THE WHOLE POINT. A resumed session's own registry pid IS a `--resume <sid>`
  # process, so `nrows + nprocs` double-counts a singly-held session. Measured 2026-09-19: sid
  # 09e64dcb had ONE registry row (pane 111, pid 37018) and one resume pid — 37018, the same
  # process — and `--locate`'s un-deduped `[ $n -gt 1 ] || lr_resume_procs` called it DUPLICATE,
  # so `--recover` PARKED a live limit-blocked pane. Its printed prescription (`--duplicates`)
  # already subtracted the overlap and answered "no session is held by more than one live
  # process", leaving the session unrecoverable with no next action and no culprit. One predicate,
  # one arithmetic, both callers — a second copy is how the two answers diverged in the first place.
  local sid="${1:-}" rows procs total
  [ -n "$sid" ] || { printf '0\n'; return 0; }
  rows="$(lr_registry_live_rows "$sid" 2>/dev/null || true)"
  procs="$(lr_resume_procs "$sid" 2>/dev/null || true)"
  # DISTINCT PIDS — the cardinality of {registry live pids} UNION {resume leaves}, which is what
  # "holder" means. The previous form was `rows + procs` minus the row/proc OVERLAP, and that is
  # right ONLY for the overlap it was written for (a row and a leaf naming the SAME process). It
  # was blind to the other way one process appears twice: the registry is PANE-keyed, so a session
  # that changed panes leaves TWO live rows carrying ONE pid (§ 11 #2, pane-keyed overwrite). With
  # no resume leaf there is nothing to subtract against, so that counted 2, `--locate` said
  # DUPLICATE, and `--recover` PARKED a recoverable pane — the same failure the overlap fix was
  # written to end, reached through the other door. Measured before this change: two pane rows over
  # one live pid and no leaf returned 2 where the truth is 1.
  # `bin/cc-limited:724` has always taken a pid SET, which is why the both-paths `parity` diff is
  # what surfaced the disagreement. A set makes BOTH overlaps one arithmetic, so no subtraction is
  # left to get wrong — and the documented contract this serves is processes, not rows:
  # `--duplicates` is "sessions held by MORE than one live process" (lr-fleet.sh:13-15).
  total="$( { printf '%s\n' "$rows" | awk -F'\t' 'NF && $2 != "" { print $2 }'
              printf '%s\n' "$procs"; } | grep -E '^[0-9]+$' | sort -u | grep -c . || true )"
  printf '%s\n' "$total"
}

# ── THE PER-SID RUN CLAIM: ONE FORMAT, ONE TAKER, ONE STEAL RULE (D2, 2026-09-28) ─────────────────
# `<root>/<sid>.active` is the one-actuator-per-session mutex, and three writers take it: cc-lr
# recover, lr-fleet's pool and the reset poller. Until 2026-09-28 each had its own copy, and the
# poller's wrote NO holder file. On 2026-09-28 its REROUTE arm retook the claim for 415a3aac in that
# shape, its detached driver then died (a bare-flipped checkout), and the empty directory refused
# the retry ("names no pid; 421s old") until a 30-minute TTL — the operator ran the rmdir by hand.
#
# The contract, for every taker:
#   · the holder file ALWAYS names a pid, written atomically (tmp + mv), and the taker RE-STAMPS it
#     with the dispatched driver's pid, so the claim lives exactly as long as the work;
#   · holder ALIVE → refuse · holder DEAD → steal at once, loudly ("alive" is (pid, lstart): see
#     lr_pid_lstart below);
#   · NO holder (a legacy claim, or a taker between mkdir and its stamp) → steal once it is older
#     than LR_CLAIM_ORPHAN_GRACE_S (default 10 s, which covers the stamp window) AND no live
#     recovery process names the sid in its argv. Not after 30 minutes: an orphan is a fact, not age.
#   · every failure path releases its own claim, and a release removes ONLY a claim whose holder
#     names the releasing pid.
# Why the "no live process" test is a recovery-DRIVER census and not lr_holder_count: a limit-blocked
# session's own claude stays alive in its pane, so the session-holder count is >= 1 for exactly the
# sessions this claim exists to recover; that count cannot tell a live recovery from an orphan.
# Stealing goes through a rename, so two concurrent stealers cannot both delete a fresh claim.
lr_claim_holder_pid() { # $1=claim dir → the holder's pid on stdout; rc 1 when no holder names one
  local p
  p="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$1/holder" 2>/dev/null | sed -n '1p')"
  [ -n "$p" ] || return 1
  printf '%s' "$p"
}
lr_claim_age_s() { # $1=dir → age in seconds, 999999 when unreadable
  local m
  m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true)"
  case "${m:-x}" in ''|*[!0-9]*) printf '999999' ;; *) printf '%s' $(( $(date +%s) - m )) ;; esac
}
# THE HOLDER IS (pid, lstart), NOT A PID (F1, 2026-10-04). This box forks ~1,162 pids/s, so the pid
# space wraps about every 86 s and a dead holder's pid is soon some unrelated LIVE process: `kill -0`
# then reads the claim as held-live for as long as that stranger runs. lstart is the rendering
# lr_recon/store.py's proc_lstart writes into the same holder file (TZ=UTC LC_ALL=C, runs of blanks
# collapsed), so a claim stamped by either side is judged the same way by both.
#   · pid alive and the recorded lstart is its lstart  → the holder, alive;
#   · pid alive under a DIFFERENT lstart               → the pid was reused: the holder is dead;
#   · no recorded lstart (a holder stamped before this) → judged by its pid alone, as before. Not
#     "unproven ⇒ steal": the takers that stamp their OWN pid (lr-upgrade's drain, the poller,
#     cc-lr) are not in lr_claim_drivers' census, so a drain that was mid-drive when this deployed
#     would have had its claim stolen and a second typer started in its pane. A legacy holder is
#     gone as soon as the process that wrote it is, so the old blindness ends with those processes;
#   · the pid's lstart cannot be read while kill -0 succeeds → held: only an affirmative mismatch steals.
# Kill switch LR_CLAIM_LSTART=off: pid-only judgment, as before.
lr_pid_lstart() { # $1=pid → its start time, normalised; empty when there is no such process
  TZ=UTC LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s '[:blank:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}
# The same identity for the plain mkdir locks that keep a `pid` file (lr-upgrade's drain lock,
# lr-fleet's admit lock and --one slots): the taker writes `lstart` beside `pid`, and the judge
# reads both. A lock with no `lstart` file (taken by a pre-F1 process) keeps the pid-only judgment.
lr_pidlock_stamp() { # $1=lock dir [$2=pid, default $$] → writes pid and lstart; rc 1 when pid cannot be written
  local p="${2:-$$}"
  printf '%s\n' "$p" > "$1/pid" 2>/dev/null || return 1
  lr_pid_lstart "$p" > "$1/lstart" 2>/dev/null || true
}
lr_pidlock_live() { # $1=lock dir → 0 its holder is alive · 1 dead, reused or unnamed
  local p l cur
  p="$(cat "$1/pid" 2>/dev/null || true)"
  case "${p:-x}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null || return 1
  [ "${LR_CLAIM_LSTART:-on}" = off ] && return 0
  l="$(tr -s '[:blank:]' ' ' < "$1/lstart" 2>/dev/null | sed -e 's/^ //' -e 's/ $//')"
  [ -n "$l" ] || return 0
  cur="$(lr_pid_lstart "$p")"
  [ -z "$cur" ] || [ "$cur" = "$l" ]
}
lr_claim_holder_lstart() { # $1=claim dir → the holder's recorded lstart on stdout (empty for a legacy holder)
  sed -n 's/.*"lstart":"\([^"]*\)".*/\1/p' "$1/holder" 2>/dev/null | sed -n '1p'
}
lr_claim_holder_state() { # $1=claim dir $2=holder pid → live | dead | reused
  local hl cur
  kill -0 "$2" 2>/dev/null || { printf 'dead'; return 0; }
  [ "${LR_CLAIM_LSTART:-on}" = off ] && { printf 'live'; return 0; }
  hl="$(lr_claim_holder_lstart "$1")"
  [ -n "$hl" ] || { printf 'live'; return 0; }
  cur="$(lr_pid_lstart "$2")"
  if [ -n "$cur" ] && [ "$cur" != "$hl" ]; then printf 'reused'; else printf 'live'; fi
}
lr_claim_stamp() { # $1=dir $2=sid $3=pid $4=by [$5=pane] → writes the holder atomically; rc 1 on failure
  local t="$1/.holder.$$.$RANDOM"
  printf '{"sid":"%s","pane":"%s","pid":%d,"ts":"%s","by":"%s","lstart":"%s"}\n' \
    "$2" "${5:--}" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$4" "$(lr_pid_lstart "$3")" > "$t" 2>/dev/null \
    && mv -f "$t" "$1/holder" 2>/dev/null && return 0
  rm -f "$t" 2>/dev/null; return 1
}
lr_claim_drivers() { # $1=sid → pids of live limit-recover drivers naming the sid, minus this process's ancestry
  local sid="${1:-}" anc p
  [ -n "$sid" ] || return 1
  # A forked subshell of lr-fleet.sh carries lr-fleet's argv, so the caller and its whole ancestry
  # are excluded — a taker must never read ITSELF as the live driver it is waiting on.
  p="${BASHPID:-$$}"; anc=" $p "
  while p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" && [ -n "$p" ] && [ "$p" -gt 1 ]; do anc="$anc$p "; done
  # The sid rides in the ENVIRONMENT, never in awk's argv (lr_resume_procs above: a pattern in argv
  # matches the census itself).
  ps -axo pid=,command= 2>/dev/null | LR_CD_SID="$sid" LR_CD_ANC="$anc" awk '
    index($0, ENVIRON["LR_CD_SID"]) && $0 ~ /limit-recover\/lr-(fleet|handoff|fire-resume|transplant)\.sh/ \
      && index(ENVIRON["LR_CD_ANC"], " " $1 " ") == 0 { print $1 }'
}
lr_claim_take() { # $1=root $2=sid $3=by [$4=pane] [$5=pid] → claim path on stdout; rc 0 taken · 1 held · 2 cannot create
  local root="$1" sid="$2" by="$3" pane="${4:--}" pid="${5:-$$}" d hp age grace drv tomb thp
  d="$root/$sid.active"
  mkdir -p "$root" 2>/dev/null || { echo "lr-claim: verdict=cannot-create root=$root" >&2; return 2; }
  if ! mkdir "$d" 2>/dev/null; then
    if hp="$(lr_claim_holder_pid "$d")"; then
      case "$(lr_claim_holder_state "$d" "$hp")" in
        live)
          echo "lr-claim: verdict=held-live sid=${sid:0:8} pid=$hp claim=$d — already being recovered by pid $hp; one actuator per session" >&2; return 1 ;;
        reused)
          echo "lr-claim: verdict=stolen-pid-reused sid=${sid:0:8} pid=$hp claim=$d — pid $hp is alive but started at '$(lr_pid_lstart "$hp")', not the holder's '$(lr_claim_holder_lstart "$d")': the holder is DEAD and its pid was reused — stealing it" >&2 ;;
        *)
          echo "lr-claim: verdict=stolen-dead-holder sid=${sid:0:8} pid=$hp claim=$d — held by pid $hp, which is DEAD — stealing it" >&2 ;;
      esac
    else
      hp=""
      grace="${LR_CLAIM_ORPHAN_GRACE_S:-10}"; case "$grace" in ''|*[!0-9]*) grace=10 ;; esac
      age="$(lr_claim_age_s "$d")"
      if [ "$age" -lt "$grace" ]; then
        echo "lr-claim: verdict=held-fresh-orphan sid=${sid:0:8} age=${age}s claim=$d — no holder yet, inside the ${grace}s stamp window" >&2; return 1
      fi
      drv="$(lr_claim_drivers "$sid" | tr '\n' ' ')"
      if [ -n "${drv// /}" ]; then
        echo "lr-claim: verdict=held-orphan-driver-alive sid=${sid:0:8} pids=${drv% } claim=$d" >&2; return 1
      fi
      echo "lr-claim: verdict=stolen-orphan sid=${sid:0:8} age=${age}s claim=$d — no holder file and no live recovery process names the sid" >&2
    fi
    tomb="$d.stolen.$$.$RANDOM"
    mv "$d" "$tomb" 2>/dev/null || { echo "lr-claim: verdict=lost-race sid=${sid:0:8} claim=$d" >&2; return 1; }
    # What we renamed must be what we judged: a peer may have stolen and re-stamped in between.
    thp="$(lr_claim_holder_pid "$tomb" 2>/dev/null || true)"
    if [ "$thp" != "$hp" ]; then
      mv "$tomb" "$d" 2>/dev/null || rm -rf "$tomb" 2>/dev/null
      echo "lr-claim: verdict=lost-race sid=${sid:0:8} claim=$d — a peer re-took it first" >&2; return 1
    fi
    rm -rf "$tomb" 2>/dev/null || true
    mkdir "$d" 2>/dev/null || { echo "lr-claim: verdict=lost-race sid=${sid:0:8} claim=$d" >&2; return 1; }
  fi
  if ! lr_claim_stamp "$d" "$sid" "$pid" "$by" "$pane"; then
    rm -rf "$d" 2>/dev/null
    echo "lr-claim: verdict=cannot-create sid=${sid:0:8} claim=$d — the holder could not be written" >&2; return 2
  fi
  printf '%s' "$d"
}
lr_claim_restamp() { # $1=root $2=sid $3=from-pid $4=to-pid $5=by [$6=pane] → rc 0 re-stamped · 1 not ours
  local d="$1/$2.active"
  [ "$(lr_claim_holder_pid "$d" 2>/dev/null)" = "$3" ] || return 1
  lr_claim_stamp "$d" "$2" "$4" "$5" "${6:--}"
}
lr_claim_release() { # $1=root $2=sid [$3=pid] → removes the claim IFF its holder names pid (default $$)
  local d="$1/$2.active"
  [ -d "$d" ] || return 0
  [ "$(lr_claim_holder_pid "$d" 2>/dev/null)" = "${3:-$$}" ] || return 0
  rm -rf "$d" 2>/dev/null || true
  return 0
}
# The driver pid `lr-fleet --one --detach` prints on its DETACHED line, or rc 1.
lr_detached_driver_pid() { # stdin = lr-fleet's output
  sed -n 's/.*driver pid \([0-9][0-9]*\).*/\1/p' | sed -n '1p' | grep -E '^[0-9]+$'
}

# ── TRANSPLANT: where did this session go? ───────────────────────────────────────────────────────
# Reads the split-brain lock lr-transplant.sh writes. Prints the target config dir when the lock
# names a target OTHER than $2 and that target still holds the transcript (the successor exists);
# rc 1 otherwise (never transplanted, or transplanted and the successor is gone — both mean "this
# store's copy is the one to act on").
lr_transplanted_to() { # $1=sid $2=this cfg → target cfg on stdout / rc 1
  local sid="${1:-}" here="${2:-}" state="${LR_STATE_DIR:-$HOME/.reso/limit-recover}" lock to to_real here_real
  lock="$state/locks/$sid.lock"
  [ -f "$lock" ] || return 1
  to="$(sed -n '/"to":"/{s/.*"to":"\([^"]*\)".*/\1/p;q;}' "$lock")"
  [ -n "$to" ] || return 1
  to_real="$(cd "$to" 2>/dev/null && pwd -P || printf '%s' "$to")"
  here_real="$(cd "$here" 2>/dev/null && pwd -P || printf '%s' "$here")"
  [ "$to_real" != "$here_real" ] || return 1
  ls "$to"/projects/*/"$sid".jsonl >/dev/null 2>&1 || return 1
  printf '%s' "$to"
}

# ── WHERE DID THIS SESSION GO — LOCK *OR* TOMBSTONE (W10b, 2026-09-20) ──────────────────────────
# lr_transplanted_to above reads the split-brain LOCK and never a tombstone, and its header explains
# why: a same-account `--mark` writes a SUPERSEDED tombstone and no lock, so reading tombstones
# would make a same-account duplicate look like a transplant.
#
# 🚨 THAT IS CORRECT ABOUT THE FILES AND WRONG ABOUT THE FLEET. Measured 2026-09-20, on the exact
# three panes W10 was written for: ~/.reso/limit-recover/locks held ONE lock for the whole box, and
# it belonged to an unrelated session written two hours earlier. Panes 110 and 126 each had a
# transplant tombstone, a retired `<sid>.jsonl.handed-off` source, and a live successor copy under
# ~/.claude-tertiary — and NO lock. The tombstone even NAMES the lock path, and that path does not
# exist. So locks are transient on this box and tombstones are durable, and a husk predicate keyed
# only on the lock is INERT against its own motivating population: lr_husk_state returned 1 for all
# three panes it exists to find, with every unit test green, because the fixtures were built to the
# predicate's own assumption (memory: an-imported-threshold-can-sit-above-the-model-s-output-range).
#
# The discriminator that made the lock the right read is NOT the file — it is "does it name a
# DIFFERENT store". A transplant tombstone carries handed_off_to = another config dir plus a
# target_transcript; a `--mark` SUPERSEDED tombstone names THIS store (and carries
# superseded_by_pid). Testing for a different store keeps the same-account case out, so the
# tombstone can be read safely. Lock first — it is the stronger evidence when it exists.
lr_transplant_target() { # $1=sid $2=this cfg → target cfg on stdout / rc 1
  local sid="${1:-}" here="${2:-}" tomb to to_real here_real pd
  [ -n "$sid" ] && [ -n "$here" ] || return 1
  if to="$(lr_transplanted_to "$sid" "$here" 2>/dev/null)"; then printf '%s' "$to"; return 0; fi
  here_real="$(cd "$here" 2>/dev/null && pwd -P || printf '%s' "$here")"
  for tomb in "$here"/projects/*/"$sid".HANDOFF.json; do
    [ -f "$tomb" ] || continue
    to="$(sed -n '/"handed_off_to":"/{s/.*"handed_off_to":"\([^"]*\)".*/\1/p;q;}' "$tomb")"
    [ -n "$to" ] || continue
    to_real="$(cd "$to" 2>/dev/null && pwd -P || printf '%s' "$to")"
    # SAME store ⇒ a same-account `--mark`, never a transplant. This is the whole safety property.
    [ "$to_real" != "$here_real" ] || continue
    # the successor must actually be there — a tombstone pointing at nothing is not a move
    for pd in "$to"/projects/*/"$sid".jsonl; do
      [ -f "$pd" ] || continue
      printf '%s' "$to"; return 0
    done
  done
  return 1
}

# ── HUSK: a LIVE pane on a store whose session has already MOVED (W10, LIMIT_RECOVER_100P § 10) ──
# The state neither plan modelled. A transplant leaves the SOURCE pane standing — the process is
# alive, the composer is empty, the last thing on its screen is the limit error — while the session
# itself is being worked on somewhere else. Measured 2026-09-19: panes 110 (pid 95369), 126 (48984)
# and 150 (17221) were all in exactly that state, and `--locate` listed none of the three.
#
# `bin/cc-husk-sweep` models the OTHER husk — a bare shell where a session used to be. This one is
# the opposite shape: the process is real, and what is stale is its CLAIM on the session.
#
# THE CONJUNCTION IS THREE PARTS AND ALL THREE ARE REQUIRED:
#   (a) a LIVE registry row for the sid whose ACCOUNT is this store's — without it a COMPLETED
#       transplant whose source pane is already gone reads as a husk on the strength of the
#       successor's own liveness, and the actuator would be aimed at the survivor.
#   (b) `lr_transplant_target` — the LOCK or, when it is gone, the transplant TOMBSTONE names a
#       target other than this store AND the successor copy is on disk. Locks proved transient on
#       this box (1 fleet-wide, for an unrelated sid) while tombstones are durable, so a lock-only
#       read was inert against the three panes W10 exists for; see that function's header. The
#       same-account `--mark` case is excluded by the DIFFERENT-store test, not by the file kind.
#   (c) NO recovery in flight for the sid. This is the conjunct the critic pass added (§ 10.3 item
#       4) and it is what keeps every in-progress recovery from reading as a husk: lr-transplant.sh
#       never deletes the lock, and the source row stays live until the typed `/exit` lands, so
#       (a) ∧ (b) alone is true of every recovery during its own relaunch window.
#
# 🚨 AGE ALONE IS NOT THE GUARD, and the lock's own mtime is not evidence either way. The lock is
# written once, at the START of the transplant, and never touched again — so a young lock does not
# mean a watcher is running and an old lock does not mean one finished. The two signals below are
# the ones that name a live actor: a `__recycle` watcher PROCESS, and a handoffs.jsonl row.
#
# ⚠️ Stated residual: lr-transplant.sh writes NO handoffs.jsonl row, so for a transplant-driven
# recovery leg (c2) is silent by construction and (c1) is the only live-actor signal. Measured on
# the three panes above: 0 handoffs.jsonl rows naming any of their sids. Leg (c2) covers the
# recycle path (`prev_sid` / `firing_sid` on the recycle-* classes), which is the other carrier.
lr_husk_state() { # $1=sid $2=this cfg → rc 0 when the sid on CFG is a HUSK, rc 1 otherwise
  local sid="${1:-}" here="${2:-}" rows pane="" here_acct racct row_pane row_acct hlog min_age
  [ -n "$sid" ] && [ -n "$here" ] || return 1
  # The kill switch's OFF state IS the pre-W10 census, byte for byte: no row is ever a husk, so
  # lf_locate's husk arm is unreachable and every disposition is the one it printed before.
  [ "${LR_HUSK_RETIRE:-on}" != off ] || return 1

  # (b) is tested FIRST although the contract lists it second, and the ordering is a cost decision,
  # not a semantic one: `lr_transplanted_to` opens with a single `[ -f "$lock" ]`, so a sid with no
  # lock — which is nearly all of them — costs one stat. Leg (a) forks jq once per registry file.
  # lf_locate calls this per transcript over ~2,600 of them; the cheap leg has to be the gate.
  lr_transplant_target "$sid" "$here" >/dev/null 2>&1 || return 1

  # (a) hooks/session-register.sh:158 writes the account as `basename $CLAUDE_CONFIG_DIR` with the
  # leading dot stripped, so the row's account and this config dir's basename are the same string
  # by construction — EXCEPT across the mirror. `~/.claude` and `~/.claude-next` are ONE account
  # (lf_dedup_mirror says so), lr_config_dirs keeps the `.claude` spelling and drops `.claude-next`,
  # and a session started under CLAUDE_CONFIG_DIR=~/.claude-next registers as `claude-next`. That is
  # not a corner: 2 of the 3 measured husks (panes 110 and 126) carry account `claude-next` while
  # their transcripts enumerate under `~/.claude`, so without this fold two thirds of the population
  # this function exists for would still be invisible.
  here_acct="$(basename "${here%/}")"; here_acct="${here_acct#.}"
  case "$here_acct" in claude-next) here_acct=claude ;; esac
  rows="$(lr_registry_live_rows "$sid" 2>/dev/null)" || return 1
  # A heredoc, never a pipe: a `while` on the right of `|` runs in a subshell and its assignment
  # never escapes (memory: assignment-inside-command-substitution-never-escapes).
  while IFS=$'\t' read -r row_pane _ row_acct _; do
    [ -n "$row_pane" ] || continue
    racct="$row_acct"; case "$racct" in claude-next) racct=claude ;; esac
    [ "$racct" = "$here_acct" ] || continue
    pane="$row_pane"; break
  done <<EOF
$rows
EOF
  [ -n "$pane" ] || return 1

  # (c1) a live `__recycle` watcher — handoff-fire.sh detaches one per recycle and its argv is
  # `… __recycle <pane> <tty> <cmdfile> <launch-dir> <prev-sid> …`, so the pane is the field right
  # after the verb and the retiring sid rides further along.
  #
  # 🚨 THE PATTERN MUST NOT RIDE IN ARGV. A hand-rolled `ps | awk` puts the very string it searches
  # for into awk's OWN command line, which the concurrent `ps` PRINTS — so the census matches ITSELF
  # and answers YES for every pane ever asked about (docs/lessons/census-matches-itself.md; the same
  # receipt is written out at lr_resume_procs above). `pgrep` excludes itself; this does not. Both
  # needles travel in the ENVIRONMENT, which ps does not print.
  if ps -axo command= 2>/dev/null | LR_HK_SID="$sid" LR_HK_PANE="$pane" awk '
      { for (i = 1; i < NF; i++)
          if ($i == "__recycle" && ($(i+1) == ENVIRON["LR_HK_PANE"] || index($0, ENVIRON["LR_HK_SID"]))) f = 1 }
      END { exit(f ? 0 : 1) }'; then
    return 1
  fi

  # (c2) a handoffs.jsonl row naming the sid, younger than the `--await` bound. The recycle classes
  # carry the retiring session as `prev_sid` and the driver as `firing_sid`; a substring test over
  # the line covers both without pinning a key name a future emitter could rename.
  hlog="${CC_HANDOFF_LOG:-$HOME/.claude/logs/handoffs.jsonl}"
  min_age="${LR_HUSK_MIN_AGE_S:-900}"
  if [ -f "$hlog" ] && grep -Fq "$sid" "$hlog" 2>/dev/null; then
    LR_HK_SID="$sid" LR_HK_MIN="$min_age" /usr/bin/python3 -c '
import json,os,sys
from datetime import datetime,timezone
sid=os.environ["LR_HK_SID"]
try: win=float(os.environ.get("LR_HK_MIN") or 900)
except Exception: win=900.0
now=datetime.now(timezone.utc)
rc=1
try: fh=open(sys.argv[1])
except OSError: sys.exit(1)
with fh:
    for l in fh:
        if sid not in l: continue
        try: d=json.loads(l)
        except Exception: continue
        ts=d.get("ts")
        if not isinstance(ts,str): continue
        try: t=datetime.fromisoformat(ts.replace("Z","+00:00"))
        except Exception: continue
        if (now-t).total_seconds() < win: rc=0; break
sys.exit(rc)' "$hlog" && return 1
  fi

  return 0
}

# ── A CHECKOUT FLIPPED TO core.bare=true: HEALED BY THE DRIVER, NEVER BY A HUMAN (D1, 2026-09-28) ─
# `git worktree add|remove` against a shared checkout can leave core.bare=true on it while every
# working file stays on disk (memory: worktree-ops-can-bare-the-shared-checkout). Every work-tree git
# op then dies rc 128, and on 2026-09-28 one of them (`rev-parse --show-toplevel`, an INFORMATIONAL
# read) killed a recovery under `set -e`; the lead's own `git config core.bare false` was refused by
# the auto-mode classifier, so the operator typed it. This runs inside the DETACHED driver, outside
# every classifier, so the repair needs nobody.
#
# It repairs only when all three discriminators from that memory hold, and degrades otherwise:
#   1. `rev-parse --is-inside-work-tree` is not true AND core.bare reads true on THIS checkout;
#   2. working files are present: the git dir is `<top>/.git` and <top> holds something besides it
#      (a real bare conversion removes the files; a genuinely bare repo has no `.git` entry at all);
#   3. the HEAD reflog records normal work-tree operations (commit/checkout/merge/rebase/reset/pull).
# A linked worktree is never the subject: git ignores the common core.bare there (measured on 2.54).
# .git/config is copied aside first, and the verdict is read back by DIFFERENT calls than the unset.
# Prints ONE line `lr-bare: verdict=<v> ...` on stderr. rc 0 = usable work tree (healthy or healed),
# 1 = still not a work tree (degrade), 2 = not a git checkout at all. LR_BARE_REPAIR=off: detect only.
lr_heal_bare_checkout() { # $1=dir → rc 0/1/2 and one verdict line on stderr
  local dir="$1" gd top ent bak err rc=0 try
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "lr-bare: verdict=not-a-repo dir=$dir" >&2; return 2; }
  if [ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then return 0; fi
  if [ "$(git -C "$dir" config --bool --get core.bare 2>/dev/null)" != true ]; then
    echo "lr-bare: verdict=refused-not-bare-flag dir=$dir — not a work tree, but core.bare is not true; leaving it" >&2; return 1
  fi
  gd="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || gd=""
  case "$gd" in */.git) top="${gd%/.git}" ;; *)
    echo "lr-bare: verdict=refused-no-dotgit dir=$dir gitdir=${gd:-?} — a genuinely bare layout; leaving it" >&2; return 1 ;;
  esac
  ent="$(find "$top" -mindepth 1 -maxdepth 1 ! -name .git 2>/dev/null | awk 'NR<=1')"
  if [ -z "$ent" ]; then
    echo "lr-bare: verdict=refused-no-working-files dir=$top — core.bare=true and nothing checked out (a real conversion?); leaving it" >&2; return 1
  fi
  if ! grep -Eq $'\t(commit|checkout|merge|rebase|reset|pull|cherry-pick|am|revert)' "$gd/logs/HEAD" 2>/dev/null; then
    echo "lr-bare: verdict=refused-no-worktree-reflog dir=$top — the HEAD reflog shows no work-tree operation; leaving it" >&2; return 1
  fi
  if [ "${LR_BARE_REPAIR:-on}" = off ]; then
    echo "lr-bare: verdict=detected-repair-off dir=$top — core.bare=true on a checkout with a working tree (LR_BARE_REPAIR=off)" >&2; return 1
  fi
  bak="$gd/config.lr-bare-backup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  if ! cp -p "$gd/config" "$bak" 2>/dev/null; then
    echo "lr-bare: verdict=refused-backup-failed dir=$top — could not copy $gd/config aside; not repairing without a backup" >&2; return 1
  fi
  # `git worktree add|remove` holds config.lock while it flips the key, so a lost lock is retryable.
  for try in 1 2 3; do
    err="$(git -C "$top" config --unset core.bare 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && break
    [ "$try" -lt 3 ] && sleep 1
  done
  if [ "$(git -C "$top" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
     && [ "$(git -C "$top" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$top" && pwd -P)" ]; then
    echo "lr-bare: verdict=healed dir=$top — REPAIRED core.bare=true (a worktree add/remove flips it); backup $bak" >&2
    return 0
  fi
  echo "lr-bare: verdict=repair-failed dir=$top — the unset did not restore a work tree (git exited $rc${err:+: $err}); backup $bak" >&2
  return 1
}

# ── KITTY from ANY context (launchd has no $KITTY_WINDOW_ID) ─────────────────────────────────────
lr_kitty_socket() { # → unix:/tmp/kitty-<pid> of a LIVE kitty, via bin/cc-kitty-socket; rc 1 when none
  [ -n "${CC_TERM_KITTY_TO:-}" ] && { printf '%s' "$CC_TERM_KITTY_TO"; return 0; }
  local c out
  # CC_KITTY_SOCKET_BIN is THE resolver when set (a test pins "no kitty" by pointing it at nothing);
  # it never falls through to the installed one.
  if [ -n "${CC_KITTY_SOCKET_BIN:-}" ]; then
    [ -x "$CC_KITTY_SOCKET_BIN" ] || return 1
    out="$("$CC_KITTY_SOCKET_BIN" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    return 1
  fi
  for c in "${LR_LIB_DIR:-}/../../bin/cc-kitty-socket" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-kitty-socket" "$HOME/.claude/bin/cc-kitty-socket"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if out="$("$c" 2>/dev/null)" && [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
  done
  return 1
}
lr_kitty_bin() {
  local c
  for c in "${CC_TERM_KITTY:-}" "${LR_LIB_DIR:-}/../../bin/cc-kitty-bin" "$HOME/.claude/bin/cc-kitty-bin"; do
    [ -n "$c" ] || continue
    if [ -x "$c" ] && [ "$(basename "$c")" = cc-kitty-bin ]; then out="$("$c" 2>/dev/null)" && [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    elif command -v "$c" >/dev/null 2>&1; then printf '%s' "$c"; return 0; fi
  done
  command -v kitty >/dev/null 2>&1 && { printf 'kitty'; return 0; }
  return 1
}
lr_runner_bin() { # → bin/cc-pane-runner, or rc 1
  local c
  for c in "${CC_PANE_RUNNER_BIN:-}" "${LR_LIB_DIR:-}/../../bin/cc-pane-runner" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-pane-runner" "$HOME/.claude/bin/cc-pane-runner"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ── THE PANE ARGV every recovered window is launched with ────────────────────────────────────────
# RUNNER-ROOTED (MEASURED, docs/research/lr100p-2026-09-09/q-survivability-spawn.md § PA): the window
# runs `$SHELL -l -i -c 'exec "$CC_PANE_RUNNER"'`; bin/cc-pane-runner runs `bash <launcher>` under an
# interactive login shell and then execs a shell. The command arrives by ARGV (no typing race), the
# window SURVIVES a launcher refusal with the message on screen, ~/.zshrc synthesises ITERM_SESSION_ID
# (the registry row is written), and pane_shell_root reads `yes` — the pane is recyclable next time.
# `-- /bin/bash <launcher>` (today's shape) dies with the launcher and is what left panes 625/632
# un-recyclable; it survives only as the fallback when no runner is installed.
# shellcheck disable=SC2034  # this lib's OUTPUT contract, read by lr-handoff.sh / the poller (a directive binds to the NEXT construct only, hence one line)
LR_LAUNCH_TAIL=(); LR_SPAWN_SHAPE=""
# SC2034: LR_LAUNCH_TAIL/LR_SPAWN_SHAPE are this lib's OUTPUT contract, read by lr-handoff.sh and
# the poller — the directive above the declarations binds to that ONE construct, never into here.
# SC2016: the single quotes are the point — $CC_PANE_RUNNER must expand in the SPAWNED shell.
# shellcheck disable=SC2034,SC2016
lr_launch_tail() { # $1=launcher path → fills LR_LAUNCH_TAIL[] and LR_SPAWN_SHAPE (runner|argv)
  local r
  if r="$(lr_runner_bin)"; then
    LR_LAUNCH_TAIL=(--env "CC_PANE_CMD=bash $1" --env "CC_PANE_CMD_INTERACTIVE=1" --env "CC_PANE_RUNNER=$r"
                    -- "${SHELL:-/bin/zsh}" -l -i -c 'exec "$CC_PANE_RUNNER"')
    LR_SPAWN_SHAPE="runner"
  else
    LR_LAUNCH_TAIL=(-- /bin/bash "$1")
    LR_SPAWN_SHAPE="argv"
  fi
}

# ── A VISIBLE kitty window for a recovery, from any context ──────────────────────────────────────
# os-window when there is no anchor; a vsplit BESIDE the anchor pane (never beside the caller) when
# one is given — --source-window pins `current` to the anchor (without it kitty resolves against the
# operator's ACTIVE window: the 2026-08-07 pane-theft class, re-measured 2026-09-09). No --title (it
# is sticky and would freeze the ✳/◐ liveness glyph); provenance rides in --var, which kitty @ ls
# exposes as user_vars and no child can forge. Prints the new window id; rc 1 when nothing launched.
lr_kitty_spawn() { # $1=launcher $2=cwd $3=sid $4=target account [$5=anchor pane id]
  local launcher="$1" cwd="$2" sid="$3" acct="$4" anchor="${5:-}" sock="" kb id
  # A socket addresses a kitty from ANY context (launchd); inside a kitty pane kitty resolves its own
  # listener from the environment, so a missing socket is not a refusal there.
  sock="$(lr_kitty_socket 2>/dev/null || true)"
  { [ -n "$sock" ] || [ -n "${KITTY_WINDOW_ID:-}" ]; } || return 1
  kb="$(lr_kitty_bin)" || return 1
  lr_launch_tail "$launcher"
  local to=(); [ -n "$sock" ] && to=(--to "$sock")
  local common=(--var "lr_continuation_of=$sid" --var "lr_source_pane=${anchor:-}" --var "lr_target_account=$acct")
  local surface=os-window
  case "$anchor" in
    ''|*[!0-9]*)
      id="$("$kb" @ ${to[@]+"${to[@]}"} launch --type=os-window --cwd="$cwd" "${common[@]}" "${LR_LAUNCH_TAIL[@]}" 2>/dev/null)" || return 1 ;;
    *)
      surface=window
      id="$("$kb" @ ${to[@]+"${to[@]}"} launch --type=window --location=vsplit --match "window_id:$anchor" --next-to "id:$anchor" \
            --source-window "id:$anchor" --cwd=current --dont-take-focus "${common[@]}" "${LR_LAUNCH_TAIL[@]}" 2>/dev/null)" || return 1 ;;
  esac
  id="$(printf '%s' "$id" | tr -d '[:space:]')"
  case "$id" in ''|*[!0-9]*) return 1 ;; esac
  # The row belongs HERE, where the surface is actually created — not in each caller. The log's
  # whole inference is "no row ⇒ this tree did not spawn it", and a primitive whose only rows are
  # written by whoever remembered to call afterwards cannot support it (pane-spawn coverage ratchet).
  command -v cc_log_pane_spawn >/dev/null 2>&1 && \
    cc_log_pane_spawn "$surface" kitty "$id" "$cwd" "lr_kitty_spawn ${LR_SPAWN_SHAPE:-?}-rooted continuation_of:${sid:0:8} target:$acct${anchor:+ anchor:$anchor}"
  printf '%s' "$id"
}

# ── THE FOCUS GATE — one rule for every path that types into a live pane (FLEET_V2 W6, res. 1) ───
# Four paths type into a pane the operator may be looking at: the poller's cc_tui_submit, the
# in-place nudge, the HELD:team wake, and handoff-fire's /exit. Each used to decide focus for itself,
# and a rule spelled four times is four rules (memory: sibling-auditors-must-share-the-state-model).
# This is the ONE copy; callers pass it their own readers when they hold a better transport.
#   focused ∉ {yes}                 → rc 0 proceed. `unknown` (iTerm2, an unreadable kitty) is NOT
#                                     focused: refusing it would gate the whole rail on a signal it
#                                     cannot have — the rule handoff-fire has carried since W2b.
#   focused=yes, LR_MOVE_FOCUSED=off → rc 3, LR_FOCUS_HOLD=HELD:focused. Nothing is read or typed.
#                                     (operator decision 7, ruled 2026-09-30: move focused panes;
#                                     =off is the kill switch, any other value or unset moves.)
#   focused=yes, otherwise          → two composer reads LR_FOCUS_READ_GAP_S apart (default 10);
#                                     either one non-empty or unreadable → rc 3, HELD:draft; then
#                                     focus is re-read and recorded in LR_FOCUS_STATE, so the state
#                                     at the keystroke is the one that gets logged.
# The gate's LAST read is the pre-keystroke check, so a caller runs it with nothing between it and
# the keystroke. Call it directly, never inside `$(…)`: its verdict comes back in globals —
# LR_FOCUS_STATE (yes|no|unknown), LR_FOCUS_HOLD ("" or the verdict), LR_FOCUS_READ (what a failed
# read saw) — and a subshell drops them.
# Readers, by name: $2 prints yes|no|unknown for a pane; $3 answers rc 0 empty · 1 occupied (content
# on stdout) · 2 unreadable. Defaults: lr_pane_focused and lr_focus_composer (kitty).
lr_pane_focused() { # $1=kitty window id → yes|no|unknown on stdout; always rc 0
  local id="${1##*:}" kb sock js v
  case "$id" in ''|*[!0-9]*) echo unknown; return 0 ;; esac
  if [ -n "${LR_FOCUS_LS_FILE:-}" ]; then js="$(cat "$LR_FOCUS_LS_FILE" 2>/dev/null || true)"
  else
    kb="$(lr_kitty_bin 2>/dev/null)" && sock="$(lr_kitty_socket 2>/dev/null)" || { echo unknown; return 0; }
    js="$("$kb" @ --to "$sock" ls 2>/dev/null || true)"
  fi
  # UI focus is the conjunction of the OS window, the tab and the window: kitty flags the active
  # window of EVERY tab in the focused OS window (handoff-fire kt_window_field, measured in the W5
  # rig). An absent flag does not veto; an unparseable listing is `unknown`.
  v="$(printf '%s' "$js" | LR_FW="$id" /usr/bin/python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for ow in d:
    for t in ow.get("tabs", []):
        for w in t.get("windows", []):
            if str(w.get("id")) == os.environ["LR_FW"]:
                print("yes" if bool(w.get("is_focused")) and ow.get("is_focused", True) is not False
                      and t.get("is_focused", True) is not False else "no")
                sys.exit(0)' 2>/dev/null || true)"
  case "$v" in yes|no) echo "$v" ;; *) echo unknown ;; esac
}
lr_focus_composer() { # $1=kitty window id → rc 0 empty · 1 occupied (content on stdout) · 2 unreadable
  local c lib
  if ! command -v cc_tui_composer >/dev/null 2>&1; then
    for lib in "${LR_LIB_DIR:-}/../lib/cc-tui.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-tui.sh" "$HOME/.claude/scripts/lib/cc-tui.sh"; do
      # shellcheck disable=SC1090  # runtime-resolved library ladder
      [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
    done
  fi
  command -v cc_tui_composer >/dev/null 2>&1 || return 2
  c="$(cc_tui_composer "${1##*:}")" || return 2
  [ -z "$c" ] && return 0
  printf '%s' "$c"; return 1
}
# shellcheck disable=SC2034  # LR_FOCUS_* are the verdict globals the caller reads
lr_focus_gate() { # $1=pane [$2=focus reader] [$3=composer reader] → 0 proceed · 3 held (LR_FOCUS_HOLD)
  local pane="${1:-}" fr="${2:-lr_pane_focused}" cr="${3:-lr_focus_composer}" n=0 c rc
  LR_FOCUS_STATE="$("$fr" "$pane" 2>/dev/null || true)"; LR_FOCUS_HOLD="" LR_FOCUS_READ=""
  case "$LR_FOCUS_STATE" in yes|no) ;; *) LR_FOCUS_STATE=unknown ;; esac
  [ "$LR_FOCUS_STATE" = yes ] || return 0
  if [ "${LR_MOVE_FOCUSED:-on}" = off ]; then LR_FOCUS_HOLD="HELD:focused"; return 3; fi
  while [ "$n" -lt 2 ]; do
    [ "$n" = 1 ] && "${LR_SLEEP:-${HF_SLEEP:-sleep}}" "${LR_FOCUS_READ_GAP_S:-${HF_FOCUS_READ_GAP_S:-10}}"
    n=$((n + 1))
    rc=0; c="$("$cr" "$pane")" || rc=$?
    if [ "$rc" != 0 ]; then
      [ "$rc" = 1 ] && [ -n "$c" ] || c="<unreadable>"
      LR_FOCUS_READ="$c"; LR_FOCUS_HOLD="HELD:draft"; return 3
    fi
  done
  LR_FOCUS_STATE="$("$fr" "$pane" 2>/dev/null || true)"
  case "$LR_FOCUS_STATE" in yes|no) ;; *) LR_FOCUS_STATE=unknown ;; esac
  return 0
}

# OPERATOR IDLE TIME (FLEET_V2 W6, D7.5): seconds since the last keyboard/mouse input, logged beside
# every focus read so the later idle-time rule ("move a focused pane only after N s of no input")
# is decided from data. `unreadable` when ioreg fails — from a LaunchAgent it is unmeasured, and a
# guessed 0 would read as "the operator is typing". LR_HID_IDLE_S is the test seam.
lr_hid_idle_s() { # → integer seconds, or `unreadable`; always rc 0
  local v
  if [ -n "${LR_HID_IDLE_S+x}" ]; then v="$LR_HID_IDLE_S"
  else v="$(/usr/sbin/ioreg -c IOHIDSystem 2>/dev/null | awk '/"HIDIdleTime"/ { print int($NF / 1000000000); exit }')"; fi
  case "$v" in ''|*[!0-9]*) echo unreadable ;; *) echo "$v" ;; esac
}

# ── A REAPED WORKTREE'S RECREATION PLAN (2026-10-01) ─────────────────────────────────────────────
# Shared by lr-handoff (which hands the plan to lr-fire-resume's existing recreation) and lr-fleet
# (which parks a session as CWD-GONE only when there is no plan). Three facts, all fail-closed:
#   ROOT    the transcript's FIRST cwd that is an ancestor-or-equal of the session's cwd — a session
#           starts at its worktree root, and its last cwd is often a subfolder
#   BRANCH  the transcript's LAST gitBranch (never HEAD)
#   REPO    the ONE repository holding refs/heads/<branch>, among LRH_REPO_CANDIDATES (colon list)
#           or every ~/Development/*/ — zero or several holders ⇒ no plan, never a guess
# Measured case: the session-durability session's worktree was removed after its work landed; its
# launcher got the missing subfolder and no branch, and lr-fire-resume exited 2 into a husk pane.
lr_reaped_worktree_plan() { # $1=transcript $2=cwd → "root<TAB>branch<TAB>repo", or nothing; rc 0 always
  local tx="$1" cwd="$2" root="" br="" d common seen="" hits="" plan
  [ -f "$tx" ] || return 0
  plan="$(python3 - "$tx" "$cwd" <<'PY' 2>/dev/null
import json, sys
tx, cwd = sys.argv[1], sys.argv[2].rstrip("/")
root, br = "", ""
with open(tx, errors="replace") as fh:
    for ln in fh:
        if '"cwd"' not in ln and '"gitBranch"' not in ln:
            continue
        try:
            d = json.loads(ln)
        except Exception:
            continue
        c = (d.get("cwd") or "").rstrip("/")
        if not root and c and (cwd == c or cwd.startswith(c + "/")):
            root = c
        if d.get("gitBranch"):
            br = d["gitBranch"]
print(f"{root}\t{br}")
PY
  )" || return 0
  root="${plan%%$'\t'*}"; br="${plan#*$'\t'}"
  [ -n "$root" ] && [ -n "$br" ] && [ "$br" != HEAD ] || return 0
  local IFS=:
  for d in ${LRH_REPO_CANDIDATES:-$(printf '%s:' "$HOME"/Development/*/)}; do
    [ -d "$d" ] || continue
    common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
    case ":$seen:" in *":$common:"*) continue ;; esac
    seen="$seen:$common"
    git --git-dir="$common" show-ref --verify --quiet "refs/heads/$br" 2>/dev/null && hits="$hits:${common%/.git}"
  done
  hits="${hits#:}"
  if [ -n "$hits" ] && [ "${hits#*:}" = "$hits" ]; then printf '%s\t%s\t%s' "$root" "$br" "$hits"; fi
  return 0
}
