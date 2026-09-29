#!/bin/bash
# lr-transplant.sh — move a Claude Code session to another account's config dir
# (same session uuid, so --resume and Workflow resumeFromRunId journals keep working).
#
# Usage: lr-transplant.sh --sid SID --from CFGDIR --to CFGDIR
#                         [--task-list ID] [--keep-source] [--force]
#                         [--phase admit|confirm|unconfirm|fold-stub|abort]
#                         [--cause limit|voluntary] [--record-id R] [--watcher-record F]
#                         [--source-pid PID --source-lstart LSTART]   (unconfirm)
#
# Copies: <slug>/<sid>.jsonl + <slug>/<sid>/ (subagents, workflows, journals)
#         + tasks/<task-list>/ when given.
# Safety: split-brain lock at ~/.reso/limit-recover/locks/<sid>.lock, tombstone
#         JSON next to the source transcript, and — only once a caller has
#         ASSERTED the source is quiesced — the source transcript renamed to
#         *.jsonl.handed-off.
#         The lock EXPIRES only through lr-lock.py (TTL + release verb): past
#         LR_LOCK_TTL_S, and only when the disk proves it guards no successor.
#
# TWO PHASES, because a HEALTHY source keeps appending after the copy:
#   --phase admit    copy + sha-verify + lock + tombstone, and NEVER retire.
#   --phase confirm  re-copy + re-verify + retire. Run it immediately before the
#                    source is told to /exit. Idempotent, and it runs UNDER the
#                    admit's lock (it never re-acquires one).
#   no --phase       the legacy single-shot run. It copies and verifies exactly
#                    as before and does NOT retire: nothing asserted quiescence.
#
# CUSTODY PHASES — each undoes or repairs a confirm, and each runs under the admit's lock:
#   --phase unconfirm  the source never exited: restore <sid>.jsonl from .handed-off, file the
#                      target copy as evidence, drop the lock.
#   --phase fold-stub  a stub <sid>.jsonl reappeared beside .handed-off: append it to both copies.
#   --phase abort      an unconfirmed move is given up: file the target copy as evidence, drop the lock.
# Every rename here is link-then-unlink (`ln A B && unlink A`): it can never overwrite B.
#
# THE REFUSAL CONTRACT (every refusal added for the custody phases; W3 dispatches on <reason>):
#   exit 2 · stderr `lr-transplant: REFUSED (<reason>) — <why>` · stdout
#   {"ok":false,"reason":"<reason>","detail":"<short>","sid":"…"} — and the source is byte-identical.
#   stub-beside-retired  <sid>.jsonl sits beside <sid>.jsonl.handed-off; a retire would overwrite one
#   lock-mismatch        no lock, a lock naming another store or record id, or the wrong state for
#                        this phase (detail says which)
#   target-held          a live process holds the session, or the target moved on since the confirm
#   stub-present         unconfirm would restore <sid>.jsonl over a stub that already exists
#   source-dead          unconfirm restores only for a LIVE source; nobody would write to it
#
# Output: one JSON object on stdout.
# Exit: 0 ok · 2 REFUSED / FATAL (nothing further attempted) · 3 usage.
set -euo pipefail

SID="" FROM="" TO="" TASK_LIST="" KEEP_SOURCE=0 FORCE=0 PHASE="" CAUSE="" RECORD_ID="" WATCHER_RECORD=""
SOURCE_PID="" SOURCE_LSTART=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sid) SID="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --task-list) TASK_LIST="$2"; shift 2 ;;
    --keep-source) KEEP_SOURCE=1; shift ;;
    --force) FORCE=1; shift ;;
    # `--phase` and `--cause` answer to the USAGE rc (3), not to the REFUSED rc (2): a bad value is
    # the caller mistyping a flag, not this script declining to act on a real request. The pre-existing
    # arg errors below keep their rc 2 — changing them would move a contract nothing asked to move.
    --phase)
      [[ $# -ge 2 ]] || { echo "lr-transplant: --phase needs a value (admit|confirm|unconfirm|fold-stub|abort)" >&2; exit 3; }
      PHASE="$2"
      case "$PHASE" in
        admit|confirm|unconfirm|fold-stub|abort) ;;
        *) echo "lr-transplant: --phase must be admit, confirm, unconfirm, fold-stub or abort (got '$PHASE')" >&2; exit 3 ;;
      esac
      shift 2 ;;
    # The record id names the recovery that owns this move; it lands on the lock beside the actuator
    # that holds it, so a second actuator can tell its own claim from a live stranger's.
    --record-id)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "lr-transplant: --record-id needs a value" >&2; exit 3; }
      RECORD_ID="$2"; shift 2 ;;
    --watcher-record)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "lr-transplant: --watcher-record needs a value" >&2; exit 3; }
      WATCHER_RECORD="$2"; shift 2 ;;
    # The reconciler names the source process it recorded (architecture §C, "unconfirm (new)"), so
    # unconfirm restores only for THAT process, never for a pid the OS has since handed to another.
    # The W5 rig's first real UNCONFIRM died here 64 times with "unknown arg --source-pid".
    --source-pid)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "lr-transplant: --source-pid needs a pid" >&2; exit 3; }
      SOURCE_PID="$2"; shift 2 ;;
    --source-lstart)
      [[ $# -ge 2 ]] || { echo "lr-transplant: --source-lstart needs a value" >&2; exit 3; }
      SOURCE_LSTART="$2"; shift 2 ;;
    # A FIELD, never a state token (DEC-3). It is recorded on the lock and the tombstone so an
    # artifact read weeks later says WHY the session moved; nothing in this script branches on it,
    # and no state/klass predicate anywhere may — a new STATE value would fall into klass()'s
    # permissive `return "run"` default and render as in-flight forever.
    --cause)
      [[ $# -ge 2 ]] || { echo "lr-transplant: --cause needs a value (limit|voluntary)" >&2; exit 3; }
      CAUSE="$2"
      case "$CAUSE" in
        limit|voluntary) ;;
        *) echo "lr-transplant: --cause must be limit or voluntary (got '$CAUSE')" >&2; exit 3 ;;
      esac
      shift 2 ;;
    *) echo "lr-transplant: unknown arg $1" >&2; exit 2 ;;
  esac
done
[[ -n "$SID" && -n "$FROM" && -n "$TO" ]] || { echo "lr-transplant: --sid/--from/--to required" >&2; exit 2; }
[[ -n "$RECORD_ID" ]] || RECORD_ID="${LR_RECORD_ID:-}"
[[ -n "$WATCHER_RECORD" ]] || WATCHER_RECORD="${HF_WATCHER_RECORD:-}"
# The actuator this run acts for: the caller, unless it names a longer-lived process that owns it.
LRT_HOLDER_PID="${LR_HOLDER_PID:-$PPID}"

# OPTIONAL FIELDS, ABSENT WHEN UNASKED — not defaulted. Both fragments carry their own leading comma
# and are appended immediately before a closing brace, so with neither flag every record this script
# writes (receipt, lock, tombstone) is byte-identical to the pre-change one. That is what keeps the
# tombstone/lock shapes the rest of the fleet matches on (`"to":"` by literal string, in three
# readers) unchanged, and it is why an absent `cause` is omitted rather than written as "".
LRT_CAUSE_JSON=""
[[ -z "$CAUSE" ]] || LRT_CAUSE_JSON=",\"cause\":\"$CAUSE\""
LRT_PHASE_JSON=""
[[ -z "$PHASE" ]] || LRT_PHASE_JSON=",\"phase\":\"$PHASE\""

# `pwd -P`, not `pwd`. Every comparison this script makes against $FROM resolves the OTHER side
# physically (`pwd -P` below, python realpath on the next two lines), so a LOGICAL $FROM compares a
# resolved path against an unresolved one and misses on any symlinked config dir. That is a live
# miss, not a theoretical one: ~/.claude-next/projects is a symlink to ~/.claude/projects on this
# box. The second-hop test (`the lock's owner IS this --from`) is the site that cannot be sound
# without it.
FROM=$(cd "${FROM/#\~/$HOME}" && pwd -P)
TO=$(cd "${TO/#\~/$HOME}" && pwd)
FROM_PROJ_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$FROM/projects")
TO_PROJ_REAL=$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$TO/projects")
if [[ "$FROM_PROJ_REAL" == "$TO_PROJ_REAL" ]]; then
  echo "lr-transplant: REFUSED — source and target share the same projects/ store ($FROM_PROJ_REAL); nothing to transplant (same account)" >&2
  exit 2
fi

# ══ IDEMPOTENT ON A SAME-TARGET RETRY (W11, LIMIT_RECOVER_100P § 10) ════════════════════════════
# W11 makes a failed recovery RETRYABLE instead of prescribing a hand-spawned window. A retry only
# helps if the transplant leg is a no-op the second time, so this refuses nothing that has already
# happened exactly as asked: the lock names THIS target and the target copy is there.
#
# 🚨 THREE SITES, NOT TWO. The plan named the two refusals below (`$DST already exists`, `lock
# exists`) and a retry after a SUCCESSFUL transplant reaches NEITHER: lr-transplant renames the
# source to `<sid>.jsonl.handed-off` when the driver is not the session itself, so the glob finds
# nothing and the run dies at "no transcript $SID under $FROM/projects" — which is the shape an
# rc-4 retry actually has. The check therefore sits ABOVE the source lookup and covers all three.
#
# SAFE BY CONSTRUCTION: a lock naming a DIFFERENT target still refuses (that is a genuine split
# brain), a $DST with no lock still refuses (unexplained target file), --force still overrides, and
# where a live source copy still exists the target must be at least as COMPLETE as it — a truncated
# target is not a finished transplant, and returning ok over one would strand the tail of a session.
#
# ══ AND CUSTODY: A RE-LIMITED TARGET CAN BE MOVED AGAIN (W5-B) ═════════════════════════════════
# The lock above answers "has THIS move already happened". It could not answer "may this session
# move ON", and that is the state a second limit produces: A→B lands, B hits its own limit hours
# later, and `--from B --to C` is refused twice over — once here as a split brain naming B, and
# again at the bare `-e "$LOCK"` refusal below. The lock therefore records CUSTODY, not just a
# destination: `owner` is the store that holds the session now, `chain` is every store it has been
# through in order, and `ts_first` is when the FIRST claim was taken. A move whose `--from` IS the
# current owner is a hop and is accepted; every other mismatch refuses exactly as before.
#
# `ts` is REFRESHED on the hop and `ts_first` is the field that remembers. bin/cc-limited:969 reads
# `ts` as the age of the claim (`NOW - ts <= CLAIM_GRACE_S` ⇒ in grace), so carrying the original
# forward would render a freshly-claimed second hop as an overdue claim the moment it was taken.
#
# LR_STATE_DIR is honoured. Every READER of this lock already resolves it that way —
# lr-lib.sh:511, lr-fire-resume.sh:244, lr-fleet.sh:69, bin/cc-limited:88, hooks/recover-inject.sh:55
# — and this WRITER was the one place that hardcoded $HOME, so a fleet run with LR_STATE_DIR set
# wrote its locks where none of them looked. Unset (production today) the path is unchanged.
LOCK_DIR="${LR_STATE_DIR:-$HOME/.reso/limit-recover}/locks"
mkdir -p "$LOCK_DIR"
LOCK="$LOCK_DIR/$SID.lock"

lrt_rp() { # the physical path when it exists, the string itself when it does not
  if [[ -d "$1" ]]; then (cd "$1" && pwd -P); else printf '%s' "$1"; fi
}
lrt_lock_str() { # $1=field → its string value, empty when the lock or the field is absent
  [[ -e "$LOCK" ]] || return 0
  sed -n "/\"$1\":\"/{s/.*\"$1\":\"\([^\"]*\)\".*/\1/p;q;}" "$LOCK"
}
lrt_lock_chain() { # → the recorded hop chain, one store per line; empty when absent or unparseable
  [[ -e "$LOCK" ]] || return 0
  python3 - "$LOCK" 2>/dev/null <<'PY' || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(0)
if isinstance(d, dict) and isinstance(d.get("chain"), list):
    for x in d["chain"]:
        if isinstance(x, str) and x:
            print(x)
PY
}
lrt_lock_owner() { # who holds the session NOW: `owner`, falling back to `to` for a pre-W5-B lock
  local _o
  _o="$(lrt_lock_str owner)"
  [[ -n "$_o" ]] || _o="$(lrt_lock_str to)"
  printf '%s' "$_o"
}

lrt_refuse() { # $1=reason $2=detail $3=plain why → the frozen refusal contract (header), then exit 2
  echo "lr-transplant: REFUSED ($1) — $3" >&2
  printf '{"ok":false,"reason":"%s","detail":"%s","sid":"%s"}\n' "$1" "$2" "$SID"
  exit 2
}
# ONE lstart FORM, SPACE-COLLAPSED, on both sides of every comparison. `ps` pads a single-digit day
# (`Sep  9`) and the lr_recon store writes the collapsed form (`Sep 9`), so a raw compare would read
# a LIVE watcher or actuator recorded by the reconciler as dead on days 1-9 of every month — and a
# dead verdict is what lets abort move a target copy. Collapsing both sides accepts either writer.
lrt_norm() { # $1=an lstart string → trimmed, runs of blanks collapsed to one space
  printf '%s' "$1" | tr -s '[:blank:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}
lrt_lstart() { # $1=pid → its start time as `ps` renders it in UTC, normalised; empty when there is none
  lrt_norm "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null || true)"
}
lrt_live() { # $1=pid $2=recorded lstart → rc 0 iff THAT process is alive (an empty lstart judges the pid alone)
  local _l
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]] || return 1
  kill -0 "$1" 2>/dev/null || return 1
  _l="$(lrt_norm "$2")"
  [[ -n "$_l" ]] || return 0
  [[ "$(lrt_lstart "$1")" == "$_l" ]]
}
lrt_holders() { # $1=config dir → one `pid<TAB>procStart` row per sessions/*.json naming $SID; malformed skipped
  python3 - "$1" "$SID" 2>/dev/null <<'PY' || true
import glob, json, os, sys
for p in sorted(glob.glob(os.path.join(sys.argv[1], "sessions", "*.json"))):
    try:
        with open(p) as fh:
            d = json.load(fh)
    except Exception:
        continue
    if not isinstance(d, dict) or d.get("sessionId") != sys.argv[2]:
        continue
    pid = d.get("pid")
    pid = str(pid) if isinstance(pid, int) and not isinstance(pid, bool) else (pid if isinstance(pid, str) else "")
    if not pid.isdigit():
        continue
    ps = d.get("procStart")
    ps = ps.replace("\t", " ").strip() if isinstance(ps, str) else ""
    # TSV pad at the emitter (tsv-pad-lint): an empty procStart would shift nothing, but `-` says so.
    print("%s\t%s" % (pid, ps or "-"))
PY
}
lrt_held() { # $1=config dir → rc 0 when a LIVE process holds $SID under it
  local _p _l
  while IFS=$'\t' read -r _p _l; do
    [[ "$_l" != "-" ]] || _l=""
    lrt_live "$_p" "$_l" && return 0
  done < <(lrt_holders "$1")
  return 1
}
lrt_lock_json() { # $1=key or key.sub → that scalar off the lock; empty when the lock, the key or a scalar is absent
  [[ -e "$LOCK" ]] || return 0
  python3 - "$LOCK" "$1" 2>/dev/null <<'PY' || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(0)
for k in sys.argv[2].split("."):
    d = d.get(k) if isinstance(d, dict) else None
if d is not None and not isinstance(d, (bool, dict, list)):
    print(d)
PY
}
lrt_holder_json() { # → `,"record_id":R,"holder":{…}` with its own leading comma; empty with no record id
  [[ -n "$RECORD_ID" ]] || return 0
  python3 - "$RECORD_ID" "${LR_ATTEMPT:-}" "$LRT_HOLDER_PID" "$(lrt_lstart "$LRT_HOLDER_PID")" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PY'
import json, sys
rid, att, pid, lst, at = sys.argv[1:6]
holder = {"record_id": rid, "attempt": int(att) if att.isdigit() else None, "role": "actuator",
          "pid": int(pid) if pid.isdigit() else None, "lstart": lst, "at": at}
c = (",", ":")
sys.stdout.write(',"record_id":%s,"holder":%s' % (json.dumps(rid, ensure_ascii=False),
                                                   json.dumps(holder, ensure_ascii=False, separators=c)))
PY
}
lrt_link_rename() { # $1=path $2=new path → link-then-unlink; rc 1 with NOTHING changed when $2 exists
  [[ ! -e "$2" && ! -L "$2" ]] || return 1
  ln "$1" "$2" 2>/dev/null || return 1
  unlink "$1"
}
lrt_retired() { # → the first <FROM>/projects/*/<sid>.jsonl.handed-off, empty when none
  local _c
  for _c in "$FROM"/projects/*/"$SID".jsonl.handed-off; do [[ -f "$_c" ]] && { printf '%s' "$_c"; return 0; }; done
  return 0
}
lrt_stub() { # → the <sid>.jsonl that sits beside a .handed-off in the same slug dir, empty when none
  local _c
  for _c in "$FROM"/projects/*/"$SID".jsonl.handed-off; do
    [[ -f "$_c" && -e "${_c%.handed-off}" ]] && { printf '%s' "${_c%.handed-off}"; return 0; }
  done
  return 0
}
lrt_assert_lock() { # every custody phase runs under the admit's lock: present, owned by TO, and the caller's
  local _o _id
  [[ -e "$LOCK" ]] || lrt_refuse lock-mismatch no-lock "no custody lock at $LOCK; this phase runs only under an admit's lock"
  _o="$(lrt_lock_owner)"
  [[ -n "$_o" && "$(lrt_rp "$_o")" == "$(lrt_rp "$TO")" ]] \
    || lrt_refuse lock-mismatch owner-mismatch "the lock names ${_o:-no owner} as the owner, not $TO"
  _id="$(lrt_lock_json record_id)"
  # A legacy lock carries no record id and passes; so does a caller that names none.
  if [[ -n "$_id" && -n "$RECORD_ID" && "$_id" != "$RECORD_ID" ]]; then
    lrt_refuse lock-mismatch record-id-mismatch "the lock belongs to record $_id, not $RECORD_ID"
  fi
}
lrt_size() { wc -c < "$1" | tr -d ' '; }
lrt_sha() { shasum -a 256 "$@" | cut -d' ' -f1; }
lrt_sha_cat() { cat "$@" | shasum -a 256 | cut -d' ' -f1; }
# EVIDENCE, NEVER DELETION. The target copy an unconfirm/abort disowns is moved into a directory made
# fresh for this run, so the `mv` has nothing to overwrite. A tombstone left by an EARLIER cycle at
# the renamed path is filed there too, so the link-then-unlink rename below always has a free name.
lrt_file_evidence() { # $1=kind (unconfirmed|aborted) $2=slug $3=tombstone (may be absent) → sets EVIDENCE
  EVIDENCE="$LOCK_DIR/$SID.$1-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir "$EVIDENCE" 2>/dev/null || { EVIDENCE="$EVIDENCE.$$"; mkdir "$EVIDENCE"; }
  [[ ! -e "$TO/projects/$2/$SID.jsonl" ]] || mv "$TO/projects/$2/$SID.jsonl" "$EVIDENCE/"
  [[ ! -d "$TO/projects/$2/$SID" ]] || mv "$TO/projects/$2/$SID" "$EVIDENCE/"
  if [[ -e "$3" ]]; then
    [[ ! -e "$3.$1" ]] || mv "$3.$1" "$EVIDENCE/"
    lrt_link_rename "$3" "$3.$1" || { echo "lr-transplant: FATAL — could not rename $3 to $3.$1" >&2; exit 2; }
  fi
}

# ══ `--phase confirm` — THE SECOND HALF OF A TWO-PHASE TRANSPLANT (D2) ══════════════════════════
# THE ASYMMETRY THIS EXISTS FOR. A quota-blocked source cannot append to its transcript after the
# copy, which is why one `cp -p` plus a sha check has always sufficed. A HEALTHY source appends right
# up until `/exit` lands — and `/exit` comes LATER, after a composer gate that can wait up to 180s
# (handoff-fire.sh). The sha check still passes, because it already ran; the successor then resumes a
# transcript missing its tail and the appended bytes are orphaned in the retired store.
#
# So the snapshot is split, and the second half runs when the source is provably quiesced rather than
# when the move was decided. Confirm runs UNDER the admit's lock: it must never try to re-acquire
# one, must never refuse on the `$DST already exists` ground admit itself created, and must be safe
# to re-run — a source already retired is the state confirm was asked to produce, not an error.
#
# It sits HERE, above every refusal site, for that reason. It still inherits the same-projects-store
# refusal above it, which is a fact about the arguments and is wrong for every phase.
#
#   rc 0  the destination is byte-identical to the source AND the source is retired (or already was)
#   rc 2  REFUSED / FATAL — sha mismatch after the re-copy, or the source vanished mid-flight
#   rc 3  usage
if [[ "$PHASE" == confirm ]]; then
  # A STUB BESIDE THE RETIRED COPY is a session that kept writing after its retire. Confirming now
  # would copy the stub over the target and retire it onto `.handed-off`; fold-stub owns that state.
  CONFIRM_STUB="$(lrt_stub)"
  [[ -z "$CONFIRM_STUB" ]] || lrt_refuse stub-beside-retired stub-beside-retired \
    "$CONFIRM_STUB sits beside its .handed-off copy; run --phase fold-stub (or unconfirm) first"
  CONFIRM_HITS=()
  while IFS= read -r line; do [[ -n "$line" ]] && CONFIRM_HITS+=("$line"); done \
    < <(ls "$FROM"/projects/*/"$SID".jsonl 2>/dev/null || true)
  if [[ ${#CONFIRM_HITS[@]} -gt 1 ]]; then
    echo "lr-transplant: REFUSED — multiple copies of $SID under $FROM/projects; disambiguate manually:" >&2
    printf '  %s\n' "${CONFIRM_HITS[@]}" >&2
    exit 2
  fi
  if [[ ${#CONFIRM_HITS[@]} -eq 0 ]]; then
    # THE SHAPE A RE-RUN ACTUALLY HAS. Confirm's own success renames the source, so a second call
    # finds no `<sid>.jsonl` at all — the same trap the W11 idempotence check was written for. A
    # `.handed-off` copy beside it is confirm reporting its own completed work, not a lost transcript.
    CONFIRM_RETIRED=""
    for _c in "$FROM"/projects/*/"$SID".jsonl.handed-off; do
      [[ -f "$_c" ]] && { CONFIRM_RETIRED="$_c"; break; }
    done
    if [[ -n "$CONFIRM_RETIRED" ]]; then
      CONFIRM_DST=""
      for _c in "$TO"/projects/*/"$SID".jsonl; do [[ -f "$_c" ]] && { CONFIRM_DST="$_c"; break; }; done
      printf '{"ok":true,"already_confirmed":true,"sid":"%s","target_transcript":"%s","retired_source":"%s","source_retired":1,"source_retired_reason":"confirm","lock":"%s"%s%s,"confirm_len":%s}\n' \
        "$SID" "$CONFIRM_DST" "$CONFIRM_RETIRED" "$LOCK" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON" \
        "$(lrt_size "$CONFIRM_RETIRED")"
      exit 0
    fi
    echo "lr-transplant: FATAL — --phase confirm found no transcript $SID under $FROM/projects and no retired copy beside it; the source vanished between admit and confirm" >&2
    exit 2
  fi
  # Only the move THIS lock records may be confirmed — checked after the rc-0 re-run above, which
  # reports finished work and must keep answering even once the lock has gone. With NO lock and no
  # record id this is lr-handoff's single-step confirm (--spawn / --close-source never admit), which
  # stays as it was; a caller naming a record always admitted first, so for it a lock is required.
  [[ ! -e "$LOCK" && -z "$RECORD_ID" ]] || lrt_assert_lock
  SRC="${CONFIRM_HITS[0]}"
  SRC_DIR=$(dirname "$SRC")
  SLUG=$(basename "$SRC_DIR")
  DST_DIR="$TO/projects/$SLUG"
  DST="$DST_DIR/$SID.jsonl"
  mkdir -p "$DST_DIR"
  # OVERWRITE, deliberately: the whole point of this phase is that the admit-time copy is stale.
  # An APFS clone first; clonefile refuses an existing DST, and the plain copy then overwrites it.
  cp -c -p "$SRC" "$DST" 2>/dev/null || cp -p "$SRC" "$DST"
  SESSION_DIR_COPIED=0
  if [[ -d "$SRC_DIR/$SID" ]]; then
    # The session dir grows too — subagent transcripts, workflow journals — and for the same reason.
    rsync -a "$SRC_DIR/$SID/" "$DST_DIR/$SID/"
    SESSION_DIR_COPIED=1
  fi
  TASKS_COPIED=0
  if [[ -n "$TASK_LIST" && -d "$FROM/tasks/$TASK_LIST" ]]; then
    mkdir -p "$TO/tasks/$TASK_LIST"
    rsync -a "$FROM/tasks/$TASK_LIST/" "$TO/tasks/$TASK_LIST/"
    TASKS_COPIED=1
  fi
  SHA_SRC=$(shasum -a 256 "$SRC" | cut -d' ' -f1)
  SHA_DST=$(shasum -a 256 "$DST" | cut -d' ' -f1)
  if [[ "$SHA_SRC" != "$SHA_DST" ]]; then
    echo "lr-transplant: FATAL — sha mismatch after the confirm re-copy (src=$SHA_SRC dst=$SHA_DST); the source was NOT retired" >&2
    exit 2
  fi
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  CONFIRM_LEN="$(lrt_size "$DST")"
  TOMBSTONE="$SRC_DIR/$SID.HANDOFF.json"
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"%s,"confirm_len":%s}\n' \
    "$TO" "$DST" "$NOW" "$LOCK" "$LRT_CAUSE_JSON" "$CONFIRM_LEN" > "$TOMBSTONE"
  SOURCE_RETIRED=0
  SOURCE_RETIRED_REASON="keep-source"
  if [[ $KEEP_SOURCE -ne 1 ]]; then
    # Link-then-unlink: a `.handed-off` that appeared since the check above is never overwritten.
    lrt_link_rename "$SRC" "$SRC.handed-off" || lrt_refuse stub-beside-retired stub-beside-retired \
      "$SRC.handed-off already exists; the source was left in place"
    SOURCE_RETIRED=1
    SOURCE_RETIRED_REASON="confirm"
  fi
  # The receipt keeps the SAME SHAPE as the legacy one — lr-handoff.sh redirects this stdout verbatim
  # into the bundle's transplant.json, and lr-ingest-verify reads it there. Custody is read back off
  # the admit's lock rather than recomputed: confirm is the same move, not a new one.
  CONFIRM_CHAIN_JSON=""
  CONFIRM_HOPS=0
  while IFS= read -r _line; do
    [[ -n "$_line" ]] || continue
    CONFIRM_CHAIN_JSON="${CONFIRM_CHAIN_JSON:+$CONFIRM_CHAIN_JSON,}\"$_line\""
    CONFIRM_HOPS=$((CONFIRM_HOPS+1))
  done < <(lrt_lock_chain)
  [[ $CONFIRM_HOPS -eq 0 ]] || CONFIRM_HOPS=$((CONFIRM_HOPS-1))
  CONFIRM_TS_FIRST="$(lrt_lock_str ts_first)"
  [[ -n "$CONFIRM_TS_FIRST" ]] || CONFIRM_TS_FIRST="$NOW"
  printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"source_retired_reason":"%s","lock":"%s","tombstone":"%s","hop":%d,"ts_first":"%s","chain":[%s]%s%s,"confirm_len":%s}\n' \
    "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" \
    "$SOURCE_RETIRED_REASON" "$LOCK" "$TOMBSTONE" "$CONFIRM_HOPS" "$CONFIRM_TS_FIRST" \
    "$CONFIRM_CHAIN_JSON" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON" "$CONFIRM_LEN"
  exit 0
fi

# ══ `--phase unconfirm` — THE SOURCE NEVER EXITED ═══════════════════════════════════════════════
# Confirm retired the source on the promise that `/exit` would follow, and the source is still
# alive. Put its transcript back where it is writing, and file the target copy as evidence so no
# second store can resume it. Restores only for a LIVE source with a quiet target: a dead source has
# nobody to write to the restored path, and a held target is the move having already happened.
if [[ "$PHASE" == unconfirm ]]; then
  UC_RETIRED="$(lrt_retired)"
  if [[ -z "$UC_RETIRED" ]]; then
    for _c in "$FROM"/projects/*/"$SID".jsonl; do
      if [[ -f "$_c" && -e "${_c%.jsonl}.HANDOFF.json.unconfirmed" ]]; then
        printf '{"ok":true,"already_unconfirmed":true,"phase":"unconfirm","sid":"%s","restored":"%s"}\n' "$SID" "$_c"
        exit 0
      fi
    done
    lrt_refuse lock-mismatch not-retired "no $SID.jsonl.handed-off under $FROM/projects — nothing to unconfirm (an unconfirmed move is given up with --phase abort)"
  fi
  UC_SRC="${UC_RETIRED%.handed-off}"
  [[ ! -e "$UC_SRC" ]] || lrt_refuse stub-present stub-present "$UC_SRC already exists beside its .handed-off copy"
  lrt_held "$FROM" || lrt_refuse source-dead source-dead "no live process holds $SID under $FROM"
  # pid 0 is the reconciler's "never recorded": the holder check above is then the whole test.
  if [[ -n "$SOURCE_PID" && "$SOURCE_PID" -gt 0 ]]; then
    lrt_live "$SOURCE_PID" "$SOURCE_LSTART" \
      || lrt_refuse source-dead source-dead "the recorded source $SOURCE_PID ($SOURCE_LSTART) is not alive"
  fi
  ! lrt_held "$TO" || lrt_refuse target-held target-held "a live process holds $SID under $TO"
  lrt_assert_lock
  lrt_link_rename "$UC_RETIRED" "$UC_SRC" || lrt_refuse stub-present stub-present "$UC_SRC appeared before the restore"
  UC_DIR="$(dirname "$UC_SRC")"
  lrt_file_evidence unconfirmed "$(basename "$UC_DIR")" "$UC_DIR/$SID.HANDOFF.json"
  rm -f "$LOCK"
  printf '{"ok":true,"phase":"unconfirm","sid":"%s","restored":"%s","evidence":"%s"}\n' "$SID" "$UC_SRC" "$EVIDENCE"
  exit 0
fi

# ══ `--phase fold-stub` — BYTES WRITTEN AFTER THE RETIRE ════════════════════════════════════════
# A source that wrote once more after confirm re-creates `<sid>.jsonl` holding only that tail. It
# belongs at the end of BOTH copies, and only while nobody holds either: a live writer would keep
# growing it under the fold. Folding appends to the retired copy first, so a re-run after a crash
# recognises retired == target ∥ stub and finishes the target alone.
if [[ "$PHASE" == fold-stub ]]; then
  FS_STUB="$(lrt_stub)"
  if [[ -z "$FS_STUB" ]]; then
    printf '{"ok":true,"nothing_to_fold":true,"phase":"fold-stub","sid":"%s"}\n' "$SID"
    exit 0
  fi
  if lrt_held "$FROM" || lrt_held "$TO"; then
    lrt_refuse target-held holder-live "a live process holds $SID; fold only once both stores are quiet"
  fi
  lrt_assert_lock
  FS_R="$FS_STUB.handed-off"
  FS_T="$TO/projects/$(basename "$(dirname "$FS_STUB")")/$SID.jsonl"
  [[ -f "$FS_T" ]] || lrt_refuse lock-mismatch target-missing "the lock names $TO but $FS_T is absent"
  FS_SHA_R="$(lrt_sha "$FS_R")"
  FS_BYTES="$(lrt_size "$FS_STUB")"
  # A crash between the second append and the unlink leaves both copies equal AND ending in the
  # stub's bytes; appending again would duplicate the tail. Transcript lines carry unique uuids, so a
  # fresh stub never matches the tail it would be appended after.
  if [[ "$FS_SHA_R" == "$(lrt_sha "$FS_T")" && "$(lrt_size "$FS_R")" -ge "$FS_BYTES" ]] \
     && [[ "$(tail -c "$FS_BYTES" "$FS_R" | shasum -a 256 | cut -d' ' -f1)" == "$(lrt_sha "$FS_STUB")" ]]; then
    :
  elif [[ "$FS_SHA_R" == "$(lrt_sha "$FS_T")" ]]; then
    cat "$FS_STUB" >> "$FS_R"
    cat "$FS_STUB" >> "$FS_T"
  elif [[ "$FS_SHA_R" == "$(lrt_sha_cat "$FS_T" "$FS_STUB")" ]]; then
    cat "$FS_STUB" >> "$FS_T"
  else
    lrt_refuse target-held target-advanced "$FS_T no longer matches the retired copy — a resume wrote to the target"
  fi
  FS_SHA="$(lrt_sha "$FS_T")"
  if [[ "$(lrt_sha "$FS_R")" != "$FS_SHA" ]]; then
    echo "lr-transplant: FATAL — after the fold the retired copy and the target differ; the stub $FS_STUB was kept" >&2
    exit 2
  fi
  unlink "$FS_STUB"
  printf '{"ok":true,"phase":"fold-stub","sid":"%s","folded_bytes":%s,"sha256":"%s","confirm_len":%s}\n' \
    "$SID" "$FS_BYTES" "$FS_SHA" "$(lrt_size "$FS_T")"
  exit 0
fi

# ══ `--phase abort` — AN UNCONFIRMED MOVE IS GIVEN UP ═══════════════════════════════════════════
# The source was never retired, so it stays exactly as it is; only the target copy, the tombstone and
# the lock are withdrawn. Refused while anything could still be acting on the move: the actuator the
# lock records (unless that is this caller), a watcher, or a live session on the target.
if [[ "$PHASE" == abort ]]; then
  AB_TOMB=""
  for _c in "$FROM"/projects/*/"$SID".HANDOFF.json; do [[ -f "$_c" ]] && { AB_TOMB="$_c"; break; }; done
  if [[ ! -e "$LOCK" && -z "$AB_TOMB" ]]; then
    printf '{"ok":true,"already_aborted":true,"phase":"abort","sid":"%s"}\n' "$SID"
    exit 0
  fi
  [[ -z "$(lrt_retired)" ]] || lrt_refuse lock-mismatch source-retired "the source is retired to .handed-off; run --phase unconfirm first"
  if [[ -e "$LOCK" ]]; then
    lrt_assert_lock
    AB_HPID="$(lrt_lock_json holder.pid)"
    AB_HLST="$(lrt_lock_json holder.lstart)"
    if [[ "$AB_HPID" != "$LRT_HOLDER_PID" || "$(lrt_norm "$AB_HLST")" != "$(lrt_lstart "$LRT_HOLDER_PID")" ]] \
       && lrt_live "$AB_HPID" "$AB_HLST"; then
      lrt_refuse target-held live-actuator "the actuator the lock records (pid $AB_HPID) is still running"
    fi
  elif [[ "$(lrt_rp "$(sed -n 's/.*"handed_off_to":"\([^"]*\)".*/\1/p' "$AB_TOMB")")" != "$(lrt_rp "$TO")" ]]; then
    lrt_refuse lock-mismatch no-lock "no lock, and the tombstone $AB_TOMB does not name $TO"
  fi
  if [[ -n "$WATCHER_RECORD" && -f "$WATCHER_RECORD" ]]; then
    AB_W="$(python3 - "$WATCHER_RECORD" 2>/dev/null <<'PY' || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(0)
if isinstance(d, dict) and str(d.get("pid", "")).isdigit():
    print("%s\t%s" % (d["pid"], str(d.get("lstart") or "-").replace("\t", " ")))
PY
)"
    if [[ -n "$AB_W" ]]; then
      AB_WPID="${AB_W%%$'\t'*}"
      AB_WLST="${AB_W#*$'\t'}"
      [[ "$AB_WLST" != "-" ]] || AB_WLST=""
      ! lrt_live "$AB_WPID" "$AB_WLST" || lrt_refuse target-held live-watcher "the watcher in $WATCHER_RECORD (pid $AB_WPID) is still running"
    fi
  fi
  ! lrt_held "$TO" || lrt_refuse target-held target-held "a live process holds $SID under $TO"
  AB_SLUG="slug-unknown"
  if [[ -n "$AB_TOMB" ]]; then
    AB_SLUG="$(basename "$(dirname "$AB_TOMB")")"
  else
    for _c in "$FROM"/projects/*/"$SID".jsonl; do [[ -f "$_c" ]] && { AB_SLUG="$(basename "$(dirname "$_c")")"; break; }; done
  fi
  lrt_file_evidence aborted "$AB_SLUG" "$AB_TOMB"
  rm -f "$LOCK"
  printf '{"ok":true,"phase":"abort","sid":"%s","evidence":"%s"}\n' "$SID" "$EVIDENCE"
  exit 0
fi

FROM_REAL="$(lrt_rp "$FROM")"
TO_REAL="$(lrt_rp "$TO")"
LRT_OWNER="$(lrt_lock_owner)"
LRT_OWNER_REAL=""
[[ -z "$LRT_OWNER" ]] || LRT_OWNER_REAL="$(lrt_rp "$LRT_OWNER")"
# THE HOP TEST. A lock whose owner is the store we are moving OFF is custody being handed on, not a
# split brain. (FROM ≠ TO is already guaranteed: the same-projects-store refusal above exits first.)
#
# IT DOES NOT CONSULT $FORCE, deliberately. This is a FACT about the lock, and --force is an
# assertion about the lock being stale; the two refusals below already carry their own `$FORCE -ne
# 1`, so nothing here gates the override. The only thing a FORCE conjunct would change is that a
# forced move off the store the lock ALREADY names would throw away a chain that agrees with it —
# losing the earlier hops' bundles from C3 for no safety gained. A forced move off some OTHER store
# still rebuilds the record, which is right: there the lock and reality disagree. (Found by the
# mutation pass: with the conjunct, the mutant that removed it survived the whole suite, and the
# only case that could have killed it was one asserting the worse behaviour.)
SECOND_HOP=0
if [[ -n "$LRT_OWNER_REAL" && "$LRT_OWNER_REAL" == "$FROM_REAL" ]]; then
  SECOND_HOP=1
fi

lrt_already_done() { # → prints the existing target transcript when THIS transplant already happened
  [[ -e "$LOCK" ]] || return 1
  local _to _to_real _tgt_real _dst _src _sb _db
  _to="$(lrt_lock_owner)"
  [[ -n "$_to" ]] || return 1
  _to_real="$(cd "$_to" 2>/dev/null && pwd -P || printf '%s' "$_to")"
  _tgt_real="$(cd "$TO" 2>/dev/null && pwd -P || printf '%s' "$TO")"
  [[ "$_to_real" == "$_tgt_real" ]] || return 1          # a different target is a real split brain
  # A GLOB, not `ls | head` — the shell already enumerates this and shellcheck is right that parsing
  # ls is the wrong tool (SC2012). An unmatched glob stays literal, which `-f` then rejects.
  local _c
  _dst=""
  for _c in "$TO"/projects/*/"$SID".jsonl; do [[ -f "$_c" ]] && { _dst="$_c"; break; }; done
  [[ -n "$_dst" ]] || return 1
  # Completeness, only when a live source copy survives to compare against. Bytes, not sha: the
  # successor has been APPENDING to the target since the transplant, so the two are legitimately
  # unequal and only "at least as much" is a meaningful test.
  _src=""
  for _c in "$FROM"/projects/*/"$SID".jsonl; do [[ -f "$_c" ]] && { _src="$_c"; break; }; done
  if [[ -n "$_src" ]]; then
    _sb=$(wc -c < "$_src" 2>/dev/null | tr -d ' ' || echo 0)
    _db=$(wc -c < "$_dst" 2>/dev/null | tr -d ' ' || echo 0)
    [[ "${_db:-0}" -ge "${_sb:-0}" ]] || return 1
  fi
  printf '%s' "$_dst"
}
# A lock naming a DIFFERENT target is a split brain, and it must SAY SO here. Once the source has
# been retired to `.handed-off` the run would otherwise fall through to "no transcript under
# $FROM/projects" — true, unhelpful, and pointing at the wrong subject: the reason this session
# cannot be transplanted is not that its transcript is missing, it is that somebody already moved it
# somewhere else. A refusal that names a cause the reader cannot act on costs a whole round trip.
# REFUSAL SITE ONE OF TWO. The hop is exempt here (the lock names the store we are moving OFF), and
# the refusal now names the way forward, because "recover it at its CURRENT target" is unactionable
# advice when the current target is the one that just hit its own limit.
if [[ $FORCE -ne 1 && -e "$LOCK" && $SECOND_HOP -ne 1 ]]; then
  LRT_LOCK_TO="$LRT_OWNER"
  if [[ -n "$LRT_LOCK_TO" ]]; then
    LRT_LOCK_REAL="$LRT_OWNER_REAL"
    LRT_TGT_REAL="$TO_REAL"
    if [[ "$LRT_LOCK_REAL" != "$LRT_TGT_REAL" ]]; then
      echo "lr-transplant: REFUSED — session $SID is already transplanted to $LRT_LOCK_TO, not to $TO ($LOCK). Two targets for one session uuid is the split brain this lock exists to prevent; recover it at its CURRENT target, or move it ON from there with --from $LRT_LOCK_TO --to $TO, or — if the move was abandoned — see what the disk says with 'python3 ${BASH_SOURCE[0]%/*}/lr-lock.py status $SID' and release it with 'lr-lock.py release $SID --why …' (--force here stays the override of last resort)." >&2
      exit 2
    fi
  fi
fi
if [[ $FORCE -ne 1 ]]; then
  if LRT_DONE="$(lrt_already_done)"; then
    # A SAME-TARGET retry by ANOTHER record. While the recorded actuator lives it still owns the
    # move; once it is dead the retry takes the claim over, so the lock names who holds it now. A
    # legacy lock, a caller with no record id, or the same record id is the plain retry above.
    LRT_LOCK_ID="$(lrt_lock_json record_id)"
    if [[ -n "$RECORD_ID" && -n "$LRT_LOCK_ID" && "$LRT_LOCK_ID" != "$RECORD_ID" ]]; then
      if lrt_live "$(lrt_lock_json holder.pid)" "$(lrt_lock_json holder.lstart)"; then
        lrt_refuse lock-mismatch live-actuator "record $LRT_LOCK_ID holds this move and its actuator is still running"
      fi
      python3 - "$LOCK" "$(lrt_holder_json)" <<'PY'
import json, os, sys
lock, frag = sys.argv[1], sys.argv[2]
with open(lock) as fh:
    d = json.load(fh)
d.update(json.loads("{" + frag[1:] + "}"))
tmp = "%s.tmp.%d" % (lock, os.getpid())
with open(tmp, "w") as fh:
    fh.write(json.dumps(d, ensure_ascii=False, separators=(",", ":")) + "\n")
os.replace(tmp, lock)
PY
    fi
    printf '{"ok":true,"already_transplanted":true,"sid":"%s","target_transcript":"%s","lock":"%s","note":"same-target retry — the lock names this target and the copy is present; nothing was moved"%s%s}\n' \
      "$SID" "$LRT_DONE" "$LOCK" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON"
    exit 0
  fi
fi

# Locate the source transcript (exactly one real file). (macOS ships bash 3.2 — no mapfile.)
HITS=()
while IFS= read -r line; do [[ -n "$line" ]] && HITS+=("$line"); done \
  < <(ls "$FROM"/projects/*/"$SID".jsonl 2>/dev/null || true)
if [[ ${#HITS[@]} -eq 0 ]]; then
  echo "lr-transplant: no transcript $SID under $FROM/projects" >&2; exit 2
elif [[ ${#HITS[@]} -gt 1 ]]; then
  echo "lr-transplant: REFUSED — multiple copies of $SID under $FROM/projects; disambiguate manually:" >&2
  printf '  %s\n' "${HITS[@]}" >&2; exit 2
fi
SRC="${HITS[0]}"
SRC_DIR=$(dirname "$SRC")
SLUG=$(basename "$SRC_DIR")
DST_DIR="$TO/projects/$SLUG"
DST="$DST_DIR/$SID.jsonl"

if [[ -e "$DST" && $FORCE -ne 1 ]]; then
  echo "lr-transplant: REFUSED — $DST already exists (use --force to overwrite)" >&2; exit 2
fi

# Split-brain lock (one transplant owner per session uuid). LOCK is resolved ABOVE, beside the
# same-target idempotence check that has to read it before the source lookup.
# REFUSAL SITE TWO OF TWO — EXISTENCE, with no target comparison at all. Teaching site one to accept
# a hop and stopping there leaves the hop refused HERE, which is why both carry the exemption.
if [[ -e "$LOCK" && $FORCE -ne 1 && $SECOND_HOP -ne 1 ]]; then
  echo "lr-transplant: REFUSED — lock exists ($LOCK):" >&2
  cat "$LOCK" >&2
  echo "  an abandoned move expires on its own once lr-lock.py can prove it (lr-reset-poller reaps it); to release it now: python3 ${BASH_SOURCE[0]%/*}/lr-lock.py release $SID --why …" >&2
  exit 2
fi
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# READ-MODIFY-WRITE. The write below is a truncating `>`, so everything the hop must carry forward
# is read here, BEFORE it: the first claim's timestamp and the chain of stores already visited.
LRT_TS_FIRST=""
LRT_CHAIN=""
# Present ONLY when custody was rebuilt from tombstones (the lock-less arm below), so every record
# of an ordinary move stays byte-identical, and a reader can tell a proven chain from a lock-carried one.
LRT_CUSTODY_JSON=""
if [[ $SECOND_HOP -eq 1 ]]; then
  LRT_TS_FIRST="$(lrt_lock_str ts_first)"
  [[ -n "$LRT_TS_FIRST" ]] || LRT_TS_FIRST="$(lrt_lock_str ts)"
  while IFS= read -r _line; do [[ -n "$_line" ]] && LRT_CHAIN+="$_line"$'\n'; done < <(lrt_lock_chain)
  if [[ -z "$LRT_CHAIN" ]]; then
    # A pre-W5-B lock carries no chain. Reconstruct what it can still say: its own `from`, then the
    # owner we are moving off. Dropping this would lose the origin store from the chain entirely.
    LRT_PREV_FROM="$(lrt_lock_str from)"
    [[ -z "$LRT_PREV_FROM" ]] || LRT_CHAIN+="$LRT_PREV_FROM"$'\n'
    LRT_CHAIN+="$LRT_OWNER"$'\n'
  fi
elif [[ ! -e "$LOCK" ]]; then
  # ══ A LOCK-LESS HOP (cc-backlog ac7bdd4b2f9d, VOLUNTARY_ACCOUNT_SWITCH §9) ═════════════════════
  # Nothing reaps a lock on purpose, but locks are measured TRANSIENT on this box (lr-lib.sh:609-612:
  # one fleet-wide against three tombstoned husks), so the second hop usually arrives with NO lock.
  # SECOND_HOP is then 0 and the branch above used to start custody at `--from`: A→B, lock gone,
  # B→C wrote `chain=[B,C]` and the A hop was erased — every bundle cut at A then fails C3.
  #
  # The TOMBSTONE is the durable record of each earlier hop: `<store>/projects/*/<sid>.HANDOFF.json`
  # says `handed_off_to`. Walk it BACKWARDS from --from, one predecessor at a time, and prepend.
  # Candidate stores are the fleet's config dirs (LR_CONFIG_DIRS, else lr_config_dirs' defaults).
  #
  # NEVER INVENT: zero predecessors is an origin, and MORE THAN ONE is ambiguous — the walk stops
  # there and keeps only what it proved. Stores are compared by `projects/` realpath, so the
  # `.claude`/`.claude-next` mirror is one store, and a store is visited at most once (a session
  # that returns to a store it left stops the walk rather than looping). `ts_first` is the ORIGIN
  # tombstone's `ts` — the time of the first claim, which is what the field means.
  LRT_CHAIN="$FROM"$'\n'
  LRT_TOMB_WALK="$(python3 - "$SID" "$FROM" "${LR_CONFIG_DIRS:-$HOME/.claude:$HOME/.claude-next:$HOME/.claude-secondary:$HOME/.claude-tertiary:$HOME/.claude-quaternary}" 2>/dev/null <<'PY' || true
import glob, json, os, sys
sid, frm, stores = sys.argv[1], sys.argv[2], [s for s in sys.argv[3].split(":") if s]
key = lambda s: os.path.realpath(os.path.join(s, "projects"))
# store key → (spelling, [(to_key, ts), …]); first spelling wins, as in lr_config_dirs
tombs = {}
for s in stores:
    s = os.path.expanduser(s)
    if not os.path.isdir(os.path.join(s, "projects")):
        continue
    k = key(s)
    if k in tombs:
        continue
    rows = []
    for t in glob.glob(os.path.join(s, "projects", "*", sid + ".HANDOFF.json")):
        try:
            with open(t) as fh:
                d = json.load(fh)
        except Exception:
            continue
        to = d.get("handed_off_to") if isinstance(d, dict) else None
        if isinstance(to, str) and to:
            rows.append((key(to), d.get("ts") if isinstance(d.get("ts"), str) else ""))
    tombs[k] = (s, rows)
cur = key(frm)
seen = {cur}
out = []
while True:
    preds = {}
    for k, (s, rows) in tombs.items():
        if k in seen:
            continue
        for to_k, ts in rows:
            if to_k == cur:
                preds[k] = (s, ts)
    if len(preds) != 1:
        break
    (k, (s, ts)), = preds.items()
    out.insert(0, (s, ts))
    seen.add(k)
    cur = k
# TSV pad at the emitter (tsv-pad-lint): cell 1 is a non-empty store spelling by construction, but
# padding it states that; ts is LAST, so an empty one reads back empty without shifting anything.
def _cell(v, ph):
    v = ("" if v is None else str(v)).replace("\t", " ").replace("\r", " ").replace("\n", " ")
    return v if v else ph
for s, ts in out:
    print("%s\t%s" % (_cell(s, "-"), _cell(ts, "")))
PY
)"
  if [[ -n "$LRT_TOMB_WALK" ]]; then
    LRT_PRED=""
    while IFS=$'\t' read -r _s _ts; do
      [[ -n "$_s" && "$_s" != "-" ]] || continue
      [[ -n "$LRT_TS_FIRST" || -z "$_ts" ]] || LRT_TS_FIRST="$_ts"
      LRT_PRED+="$_s"$'\n'
    done <<< "$LRT_TOMB_WALK"
    if [[ -n "$LRT_PRED" ]]; then
      LRT_CHAIN="$LRT_PRED$LRT_CHAIN"
      LRT_CUSTODY_JSON=",\"custody_from\":\"tombstones\""
    fi
  fi
else
  LRT_CHAIN="$FROM"$'\n'
fi
[[ -n "$LRT_TS_FIRST" ]] || LRT_TS_FIRST="$NOW"
LRT_CHAIN+="$TO"
LRT_CHAIN_JSON=""
LRT_HOPS=0
while IFS= read -r _line; do
  [[ -n "$_line" ]] || continue
  LRT_CHAIN_JSON="${LRT_CHAIN_JSON:+$LRT_CHAIN_JSON,}\"$_line\""
  LRT_HOPS=$((LRT_HOPS+1))
done <<< "$LRT_CHAIN"
LRT_HOPS=$((LRT_HOPS-1))
# The holder fragment is absent without a record id, so an ordinary lock stays byte-identical.
LRT_HOLDER_JSON="$(lrt_holder_json)"
printf '{"sid":"%s","from":"%s","to":"%s","ts":"%s","pid":%d,"host":"%s","owner":"%s","ts_first":"%s","chain":[%s]%s%s%s}\n' \
  "$SID" "$FROM" "$TO" "$NOW" "$$" "$(hostname -s)" "$TO" "$LRT_TS_FIRST" "$LRT_CHAIN_JSON" \
  "$LRT_CUSTODY_JSON" "$LRT_CAUSE_JSON" "$LRT_HOLDER_JSON" > "$LOCK"

mkdir -p "$DST_DIR"
cp -c -p "$SRC" "$DST" 2>/dev/null || cp -p "$SRC" "$DST"
SESSION_DIR_COPIED=0
if [[ -d "$SRC_DIR/$SID" ]]; then
  rsync -a "$SRC_DIR/$SID/" "$DST_DIR/$SID/"
  SESSION_DIR_COPIED=1
fi
TASKS_COPIED=0
if [[ -n "$TASK_LIST" && -d "$FROM/tasks/$TASK_LIST" ]]; then
  mkdir -p "$TO/tasks/$TASK_LIST"
  rsync -a "$FROM/tasks/$TASK_LIST/" "$TO/tasks/$TASK_LIST/"
  TASKS_COPIED=1
fi

SHA_SRC=$(shasum -a 256 "$SRC" | cut -d' ' -f1)
SHA_DST=$(shasum -a 256 "$DST" | cut -d' ' -f1)
if [[ "$SHA_SRC" != "$SHA_DST" ]]; then
  echo "lr-transplant: FATAL — sha mismatch after copy (src=$SHA_SRC dst=$SHA_DST)" >&2; exit 2
fi

# ══ TOMBSTONE + RETIREMENT — THE CALLER ASSERTS IT, THIS SCRIPT NEVER INFERS IT (D3) ════════════
# The guard here used to be `KEEP_SOURCE -ne 1 && "${CLAUDE_CODE_SESSION_ID:-}" != "$SID"` — the
# DRIVER's session id. It is correct exactly once: a session driving its own move recognises itself
# and keeps its transcript. It is WRONG for every OTHER driver, because "the driver is not the
# subject" was being read as "the subject is not live". A third pane moving a HEALTHY session passes
# that guard and renames, BY PATH, a transcript the harness is still appending to.
#
# There is no repair available at this level and none may be invented here: this subsystem has no
# idle/busy predicate (`pane_cc_state` returns `cc` for mid-turn, idle, modal and wedged alike), and
# a `pgrep -f <sid>` census matches any session whose argv merely MENTIONS the sid — including the
# agent briefs that quote it. So the retirement stops guessing and waits to be ASSERTED:
# `--phase confirm` IS the caller saying the subject has stopped writing. An unasserted run keeps the
# source and says so, on stderr and in the receipt.
#
# THE ASYMMETRY IS THE WHOLE ARGUMENT: a kept source costs one husk row, which lr-fleet already
# enumerates and the tombstone below already blocks from resuming; a renamed live transcript costs
# the tail of a working session, silently, with the sha check passing.
TOMBSTONE="$SRC_DIR/$SID.HANDOFF.json"
printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"%s}\n' \
  "$TO" "$DST" "$NOW" "$LOCK" "$LRT_CAUSE_JSON" > "$TOMBSTONE"
SOURCE_RETIRED=0
if [[ $KEEP_SOURCE -eq 1 ]]; then
  SOURCE_RETIRED_REASON="keep-source"
elif [[ "$PHASE" == admit ]]; then
  SOURCE_RETIRED_REASON="admit-phase"
elif [[ "${CLAUDE_CODE_SESSION_ID:-}" == "$SID" ]]; then
  SOURCE_RETIRED_REASON="live-self"
else
  SOURCE_RETIRED_REASON="unasserted-quiesce"
  echo "lr-transplant: the source transcript was NOT retired — nothing has asserted that $SID has stopped writing, and this driver is not that session. The copy, the lock and the tombstone are in place; re-run with --phase confirm once the source is quiesced (that call retires it and is safe to repeat)." >&2
fi

printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"source_retired_reason":"%s","lock":"%s","tombstone":"%s","hop":%d,"ts_first":"%s","chain":[%s]%s%s%s}\n' \
  "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" \
  "$SOURCE_RETIRED_REASON" "$LOCK" "$TOMBSTONE" \
  "$LRT_HOPS" "$LRT_TS_FIRST" "$LRT_CHAIN_JSON" "$LRT_CUSTODY_JSON" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON"
