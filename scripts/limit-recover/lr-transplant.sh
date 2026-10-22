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
#   stub-present         unconfirm found a stub <sid>.jsonl and NO live source to fold it for (a live
#                        source's stub is folded into the restore; see --phase unconfirm)
#   source-dead          unconfirm restores only for a LIVE source; nobody would write to it
#
# Output: one JSON object on stdout.
# Exit: 0 ok · 2 REFUSED / FATAL (nothing further attempted) · 3 usage.
set -euo pipefail
# /usr/bin/shasum is a #! perl script (a kernel-memory leak per exec on macOS 15.8.1); this is Mach-O. Linux: coreutils.
CC_SHA256=/sbin/sha256sum; [ -x "$CC_SHA256" ] || CC_SHA256=sha256sum

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
# THE SESSION'S SLUG BEFORE THE GLOB (B4 review F10, 2026-10-20). `projects/*/<sid>…` stats every
# project dir, ~18,400 per store: 1.2-2.4 s a glob at load1 241-247. lr-handoff exports LR_SID_SLUG
# (its --cwd's slug), and the source locate below pins it to the slug it found. lrt_at is lr-lib's
# lr_sid_file, which this script does not source: one stat at the slug, the glob only on a miss, so a
# miss answers exactly as before. The globs that COUNT copies (the locate, confirm's copy check, the
# target-live read before admit) stay globs: "exactly one" and "none" cannot be read off one slug.
# Kill switch: LR_MOVE_LOCATION_FAST=off.
LRT_SLUG=""
if [[ "${LR_MOVE_LOCATION_FAST:-on}" != off && "${LR_SID_SLUG:-}" =~ ^[A-Za-z0-9-]+$ ]]; then LRT_SLUG="$LR_SID_SLUG"; fi

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
# THE RECORDED lstart IS WHATEVER ITS WRITER'S `ps` PRINTED, and an lstart string carries no zone.
# Every store this rail writes renders it `TZ=UTC LC_ALL=C`, and comparing against that one form
# refused a LIVE source as source-dead when the value came from a plain `ps -o lstart= -p PID`
# (2026-10-13, pid 78979: "Sun 11 Oct 14:11:30 2026" in en_CA and "Sun Oct 11 14:11:30 2026" under
# LC_ALL=C, both local time, against "Sun Oct 11 19:11:30 2026" in UTC). Two things differ between
# those renderings, and each is taken out on its own:
#   the ZONE   the process's start is rendered in UTC and in this process's own zone, and the
#              recorded value must equal one of the two;
#   the ORDER  a day-first locale prints `Sun 11 Oct`; lrt_canon puts both sides month-first. It is
#              done on the STRING, never by rendering under the caller's locale, because launchd
#              runs this script under C, where that locale's form cannot be produced at all.
# A recycled pid still has to have started in the same second, in one of the two zones, to pass.
lrt_canon() { # $1=an lstart string → normalised, and month-first when it was day-first
  lrt_norm "$1" | awk '{ if ($2 ~ /^[0-9]+$/ && $3 !~ /^[0-9]/) { t = $2; $2 = $3; $3 = t } print }'
}
lrt_live() { # $1=pid $2=recorded lstart → rc 0 iff THAT process is alive (an empty lstart judges the pid alone)
  local _l
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]] || return 1
  kill -0 "$1" 2>/dev/null || return 1
  _l="$(lrt_canon "$2")"
  [[ -n "$_l" ]] || return 0
  [[ "$(lrt_canon "$(lrt_lstart "$1")")" == "$_l" ]] && return 0
  [[ "$(lrt_canon "$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null || true)")" == "$_l" ]]
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
lrt_at() { # $1=store $2=suffix → the first regular <store>/projects/*/<sid><suffix>, LRT_SLUG's first; empty when none
  local _c
  if [[ -n "$LRT_SLUG" && -f "$1/projects/$LRT_SLUG/$SID$2" ]]; then printf '%s' "$1/projects/$LRT_SLUG/$SID$2"; return 0; fi
  for _c in "$1"/projects/*/"$SID$2"; do [[ -f "$_c" ]] && { printf '%s' "$_c"; return 0; }; done
  return 0
}
lrt_retired() { # → the first <FROM>/projects/*/<sid>.jsonl.handed-off, empty when none
  lrt_at "$FROM" .jsonl.handed-off
}
# ── STALE ROUND-TRIP LEFTOVERS, SET ASIDE (2026-10-04) ──────────────────────────────────────────
# A session that leaves S for T and later COMES BACK to S finds, beside its fresh live copy in S, the
# marker and the `.jsonl.handed-off` of its first departure. Nothing swept them, because a move writes
# the SOURCE's tombstone and never looks at the TARGET: the old marker then makes
# handed-off-session-guard.sh refuse every prompt in the live pane (762a6daa, 8e18da3f — measured
# live), and the old retired copy reads as a stub, so every later confirm off S refuses
# stub-beside-retired. Both newer counterparts carried confirm_len, so a confirm-time sweep of the
# TARGET would have prevented all four live cases. Set aside = link-then-unlink to
# `<name>.stale-<UTCts>` (never over an existing name, never rm). A retired copy is set aside only
# when it is a strict byte PREFIX of the live transcript: any other holds bytes the live one lacks.
# Only at confirm (and in the legacy/admit path, for the SOURCE's own old retired copy), never at
# admit for the target: an aborted admit must leave the target's marker, which is still true then.
# Kill switch LRT_STALE_SETASIDE=off (every arm). Receipts carry `set_aside` only when non-empty.
LRT_SET_ASIDE=""
lrt_setaside_on() { [[ "${LRT_STALE_SETASIDE:-on}" != off ]]; }
lrt_stale_retired() { # $1=a live <sid>.jsonl → rc 0 iff <it>.handed-off is a strict byte prefix of it
  local _r="$1.handed-off" _n
  lrt_setaside_on || return 1
  [[ -f "$1" && -f "$_r" ]] || return 1
  _n="$(lrt_size "$_r")"
  [[ "$(lrt_size "$1")" -gt "$_n" ]] || return 1
  # `head -c N | cmp -s -`, never BSD `cmp -n N`: that reports EOF (rc 1) when N equals the shorter
  # file's size, which is exactly the prefix case (measured on both live shapes).
  head -c "$_n" "$1" | cmp -s - "$_r"
}
lrt_setaside() { # $1=path → renamed to <path>.stale-<UTCts> (.<pid> on collision), recorded in LRT_SET_ASIDE; rc 1 nothing changed
  local _n
  lrt_setaside_on || return 1
  _n="$1.stale-$(date -u +%Y%m%dT%H%M%SZ)"
  [[ ! -e "$_n" && ! -L "$_n" ]] || _n="$_n.$$"
  lrt_link_rename "$1" "$_n" || return 1
  LRT_SET_ASIDE="${LRT_SET_ASIDE:+$LRT_SET_ASIDE,}\"$_n\""
  LRT_LAST_ASIDE="$_n"
}
lrt_set_aside_json() { # → `,"set_aside":[…]` when anything was set aside this run, else nothing
  [[ -z "$LRT_SET_ASIDE" ]] || printf ',"set_aside":[%s]' "$LRT_SET_ASIDE"
}
# THE SWEEP NEVER UNDOES A LATER MOVE (review 2026-10-04). A marker in TO can also be the tombstone
# of a move made AFTER this one: Q→T confirmed, then T→S --keep-source (T stays live, and its
# tombstone is the only thing refusing prompts there), then a stale re-run of the first confirm. An
# unconditional sweep renamed that tombstone and left two live, writable copies. So a marker stays
# when the store it names holds a live <sid>.jsonl, and when its ts is not strictly older than this
# move's reference ts ($2: the custody lock's ts, else the confirm's own time). A missing or
# malformed ts on either side keeps it: the act is a rename, so every unknown keeps.
lrt_iso() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }
# ── THE RETURN HOP, SWEPT AT ADMIT AND UNDONE BY ABORT (2026-10-11, pane 14 / 4d059264) ──────────
# The confirm-time sweep came one step too late for a session moving BACK into a store it left.
# Between admit and confirm, handoff-fire --recycle reads every store's tombstone: the target's old
# marker (T → S) beside the admit's new one (S → T) is A→B→A, which hf_ts_chain_tip refuses as a
# cycle ("no chain tip"), so the recycle stood down and the move was aborted, every time. So the
# admit sweeps the target too (mode `admit`), and RECORDS each rename on the lock as `returned`
# ([{"path","aside"}]): abort and unconfirm, which declare the move did not happen, put both back
# byte-for-byte (lrt_unreturn), which keeps the old rule "an aborted admit leaves the target's
# marker". Two differences from the confirm arm: the source is still live at admit, so a marker
# naming FROM is exempt from the live-copy test (that live copy IS this move's source), and a target
# that already held a live copy before this run is never swept (lrt_admit_sweep's caller checks).
LRT_RETURNED=""
lrt_sweep_target() { # $1=the TARGET slug dir now holding the live copy $2=this move's reference ts [$3=admit] → set aside its stale marker and retired copy
  local _d="$1" _ref="${2:-}" _mode="${3:-}" _m _to _to_real _mts _c _live=""
  lrt_setaside_on || return 0
  _m="$_d/$SID.HANDOFF.json"
  if [[ -f "$_m" ]]; then
    _to="$(sed -n '/"handed_off_to":"/{s/.*"handed_off_to":"\([^"]*\)".*/\1/p;q;}' "$_m")"
    _mts="$(sed -n '/"ts":"/{s/.*"ts":"\([^"]*\)".*/\1/p;q;}' "$_m")"
    _to_real=""
    [[ -z "$_to" ]] || _to_real="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$_to/projects")"
    if [[ -n "$_to" && ! ( "$_mode" == admit && "$_to_real" == "$FROM_PROJ_REAL" ) ]]; then
      _live="$(lrt_at "$_to" .jsonl)"
    fi
    # A marker naming ANOTHER store, in the store just confirmed as the live one, records a departure
    # this move undid. One naming TO itself is a same-account superseded mark: left untouched.
    if [[ -n "$_to" && "$_to_real" != "$TO_PROJ_REAL" ]]; then
      if [[ -n "$_live" ]]; then
        echo "lr-transplant: kept the target marker $_m: the store it names holds a live copy ($_live), so it records a later move" >&2
      elif ! lrt_iso "$_mts" || ! lrt_iso "$_ref" || [[ ! "$_mts" < "$_ref" ]]; then
        echo "lr-transplant: kept the target marker $_m: its ts (${_mts:-none}) is not provably older than this move (${_ref:-none})" >&2
      elif lrt_setaside "$_m"; then
        [[ "$_mode" != admit ]] || LRT_RETURNED+="$_m"$'\t'"$LRT_LAST_ASIDE"$'\n'
      else
        echo "lr-transplant: could not set aside the stale target marker $_m (left in place)" >&2
      fi
    fi
  fi
  if lrt_stale_retired "$_d/$SID.jsonl"; then
    if lrt_setaside "$_d/$SID.jsonl.handed-off"; then
      [[ "$_mode" != admit ]] || LRT_RETURNED+="$_d/$SID.jsonl.handed-off"$'\t'"$LRT_LAST_ASIDE"$'\n'
    else
      echo "lr-transplant: could not set aside $_d/$SID.jsonl.handed-off (left in place)" >&2
    fi
  fi
  return 0
}
lrt_unreturn() { # → put back every `returned` pair the lock records (aside → path, never over an existing name); sets LRT_RESTORED
  local _p _a
  LRT_RESTORED=""
  while IFS=$'\t' read -r _p _a; do
    [[ -n "$_p" && -n "$_a" ]] || continue
    if [[ -e "$_a" ]] && lrt_link_rename "$_a" "$_p"; then
      LRT_RESTORED="${LRT_RESTORED:+$LRT_RESTORED,}\"$_p\""
    else
      echo "lr-transplant: could not restore $_p from $_a (absent, or $_p exists again) — left as it is" >&2
    fi
  done < <(python3 - "$LOCK" 2>/dev/null <<'PY' || true
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(0)
for r in (d.get("returned") if isinstance(d, dict) and isinstance(d.get("returned"), list) else []):
    if isinstance(r, dict) and isinstance(r.get("path"), str) and isinstance(r.get("aside"), str):
        print("%s\t%s" % (r["path"].replace("\t", " "), r["aside"].replace("\t", " ")))
PY
)
}
lrt_restored_json() { [[ -z "${LRT_RESTORED:-}" ]] || printf ',"restored_target":[%s]' "$LRT_RESTORED"; }
lrt_stub() { # → the <sid>.jsonl that sits beside a .handed-off in the same slug dir, empty when none
  local _c
  if [[ -n "$LRT_SLUG" ]] && lrt_stub_at "$FROM/projects/$LRT_SLUG/$SID.jsonl.handed-off"; then return 0; fi
  for _c in "$FROM"/projects/*/"$SID".jsonl.handed-off; do lrt_stub_at "$_c" && return 0; done
  return 0
}
lrt_stub_at() { # $1=a <sid>.jsonl.handed-off → prints its live twin, rc 0, when that twin is a stub
  # a retired copy that is a strict prefix of the live one is a round trip's leftover, not a stub
  lrt_stale_retired "${1%.handed-off}" && return 1
  [[ -f "$1" && -e "${1%.handed-off}" ]] || return 1
  printf '%s' "${1%.handed-off}"
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
lrt_sha() { "$CC_SHA256" "$@" | cut -d' ' -f1; }
lrt_sha_cat() { cat "$@" | "$CC_SHA256" | cut -d' ' -f1; }
# EVIDENCE, NEVER DELETED HERE. The target copy an unconfirm/abort disowns is moved into a directory
# made fresh for this run, so the `mv` has nothing to overwrite. A tombstone left by an EARLIER cycle
# at the renamed path is filed there too, so the link-then-unlink rename below always has a free name.
# The bytes are removed later by ONE reader only, `lr-lock.py evidence-gc` (decision 6d4722735677):
# after 7 days, and only once every file is proven to exist in an account store (a byte-prefix of a
# live .jsonl, identical otherwise). A dir with any uncovered file is kept whole, stamped and paged.
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
  # A glob on purpose, not lrt_at: the copy count below refuses a second copy at any slug.
  CONFIRM_HITS=()
  while IFS= read -r line; do [[ -n "$line" ]] && CONFIRM_HITS+=("$line"); done \
    < <(ls "$FROM"/projects/*/"$SID".jsonl 2>/dev/null || true)
  # A STUB BESIDE THE RETIRED COPY is a session that kept writing after its retire. Confirming now
  # would copy the stub over the target and retire it onto `.handed-off`; fold-stub owns that state.
  # A stub IS a live <sid>.jsonl, so it is one of CONFIRM_HITS: each is tested for a retired twin
  # instead of globbing the `.handed-off` spelling as well (B4 review F10). Still checked before the
  # copy count, so a stub keeps its own refusal.
  CONFIRM_STUB=""
  for _c in ${CONFIRM_HITS[@]+"${CONFIRM_HITS[@]}"}; do
    lrt_stub_at "$_c.handed-off" >/dev/null && { CONFIRM_STUB="$_c"; break; }
  done
  [[ -z "$CONFIRM_STUB" ]] || lrt_refuse stub-beside-retired stub-beside-retired \
    "$CONFIRM_STUB sits beside its .handed-off copy; run --phase fold-stub (or unconfirm) first"
  if [[ ${#CONFIRM_HITS[@]} -gt 1 ]]; then
    echo "lr-transplant: REFUSED — multiple copies of $SID under $FROM/projects; disambiguate manually:" >&2
    printf '  %s\n' "${CONFIRM_HITS[@]}" >&2
    exit 2
  fi
  if [[ ${#CONFIRM_HITS[@]} -eq 0 ]]; then
    # THE SHAPE A RE-RUN ACTUALLY HAS. Confirm's own success renames the source, so a second call
    # finds no `<sid>.jsonl` at all — the same trap the W11 idempotence check was written for. A
    # `.handed-off` copy beside it is confirm reporting its own completed work, not a lost transcript.
    CONFIRM_RETIRED="$(lrt_retired)"
    if [[ -n "$CONFIRM_RETIRED" ]]; then
      CONFIRM_DST="$(lrt_at "$TO" .jsonl)"
      # A re-run heals what an earlier confirm (or one before the sweep existed) left on the target —
      # but only while this move still holds custody: a lock that is gone, or that a later move now
      # owns, means TO's marker may be that later move's tombstone (see THE SWEEP NEVER UNDOES).
      if [[ -n "$CONFIRM_DST" && -e "$LOCK" ]] && _o="$(lrt_lock_owner)" && [[ -n "$_o" && "$(lrt_rp "$_o")" == "$(lrt_rp "$TO")" ]]; then
        lrt_sweep_target "$(dirname "$CONFIRM_DST")" "$(lrt_lock_str ts)"
      fi
      printf '{"ok":true,"already_confirmed":true,"sid":"%s","target_transcript":"%s","retired_source":"%s","source_retired":1,"source_retired_reason":"confirm","lock":"%s"%s%s,"confirm_len":%s%s}\n' \
        "$SID" "$CONFIRM_DST" "$CONFIRM_RETIRED" "$LOCK" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON" \
        "$(lrt_size "$CONFIRM_RETIRED")" "$(lrt_set_aside_json)"
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
  SHA_SRC=$("$CC_SHA256" "$SRC" | cut -d' ' -f1)
  SHA_DST=$("$CC_SHA256" "$DST" | cut -d' ' -f1)
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
    # The source's OWN old retired copy (a round trip's leftover, prefix-proven) is set aside first,
    # after every refusal above, so a refused run still leaves the source byte-identical.
    if lrt_stale_retired "$SRC"; then lrt_setaside "$SRC.handed-off" || true; fi
    # Link-then-unlink: a `.handed-off` that appeared since the check above is never overwritten.
    lrt_link_rename "$SRC" "$SRC.handed-off" || lrt_refuse stub-beside-retired stub-beside-retired \
      "$SRC.handed-off already exists; the source was left in place"
    SOURCE_RETIRED=1
    SOURCE_RETIRED_REASON="confirm"
  fi
  # THE TARGET SWEEP: the store now holding the live copy keeps no marker pointing away from it.
  _ref="$(lrt_lock_str ts)"
  lrt_sweep_target "$DST_DIR" "${_ref:-$NOW}"
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
  printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"source_retired_reason":"%s","lock":"%s","tombstone":"%s","hop":%d,"ts_first":"%s","chain":[%s]%s%s,"confirm_len":%s%s}\n' \
    "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" \
    "$SOURCE_RETIRED_REASON" "$LOCK" "$TOMBSTONE" "$CONFIRM_HOPS" "$CONFIRM_TS_FIRST" \
    "$CONFIRM_CHAIN_JSON" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON" "$CONFIRM_LEN" "$(lrt_set_aside_json)"
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
  # A STUB BESIDE THE RETIRED COPY, AND THE SOURCE IS ALIVE: THE CANCELLED EXIT (2026-10-13, pane 12).
  # `/exit` writes its own three local-command records the moment it is typed, before the
  # background-work dialog it may raise. So a watcher that answers Stay and unconfirms ALWAYS finds
  # a stub: this phase refused stub-present, fold-stub refuses while the source lives, and the
  # session sat half-moved with no undo (c56c729c, move batch 20261013T014855Z). For a live source
  # the stub is the tail of its own transcript, so the restore folds it in (below). With no live
  # source the refusal stands: nobody would write to the restored path, and fold-stub owns that state.
  UC_LIVE=0; ! lrt_held "$FROM" || UC_LIVE=1
  if [[ -e "$UC_SRC" && $UC_LIVE -eq 0 ]]; then
    lrt_refuse stub-present stub-present "$UC_SRC already exists beside its .handed-off copy"
  fi
  [[ $UC_LIVE -eq 1 ]] || lrt_refuse source-dead source-dead "no live process holds $SID under $FROM"
  # pid 0 is the reconciler's "never recorded": the holder check above is then the whole test.
  if [[ -n "$SOURCE_PID" && "$SOURCE_PID" -gt 0 ]]; then
    lrt_live "$SOURCE_PID" "$SOURCE_LSTART" \
      || lrt_refuse source-dead source-dead "the recorded source $SOURCE_PID ($SOURCE_LSTART) is not alive"
  fi
  ! lrt_held "$TO" || lrt_refuse target-held target-held "a live process holds $SID under $TO"
  lrt_assert_lock
  # THE FOLDING RESTORE. The source appends by PATH (its write after the retire made a new file, which
  # is what a stub is), so each pass takes the stub off the path with a rename, appends it to the
  # retired copy, and links the retired copy back onto the path. The link never overwrites: a stub
  # the source wrote in between fails it and the next pass folds that one too. Bytes that reached a
  # set-aside stub after it was read (a write in flight across the rename) are appended to the
  # restored transcript before the stub is unlinked, so the restored file holds every byte written.
  UC_FOLDED=0
  UC_ASIDES=()
  UC_SIZES=()
  UC_TRY=0
  while :; do
    if [[ -e "$UC_SRC" ]]; then
      UC_ASIDE="$UC_SRC.unconfirm-stub-$(date -u +%Y%m%dT%H%M%SZ).$$.$UC_TRY"
      lrt_link_rename "$UC_SRC" "$UC_ASIDE" || lrt_refuse stub-present stub-present "could not set the stub $UC_SRC aside; nothing was restored"
      UC_N="$(lrt_size "$UC_ASIDE")"
      head -c "$UC_N" "$UC_ASIDE" >> "$UC_RETIRED"
      UC_ASIDES+=("$UC_ASIDE"); UC_SIZES+=("$UC_N"); UC_FOLDED=$((UC_FOLDED + UC_N))
    fi
    lrt_link_rename "$UC_RETIRED" "$UC_SRC" && break
    UC_TRY=$((UC_TRY + 1))
    [[ $UC_TRY -lt ${LRT_UNCONFIRM_FOLD_TRIES:-5} ]] \
      || lrt_refuse stub-present stub-present "$UC_SRC kept reappearing across $UC_TRY folds; the retired copy holds every stub folded so far"
  done
  # Counted, not `"${!UC_ASIDES[@]}"`: bash 3.2 under `set -u` calls an empty array unbound.
  _i=0
  while [[ $_i -lt ${#UC_ASIDES[@]} ]]; do
    UC_NOW="$(lrt_size "${UC_ASIDES[$_i]}")"
    if [[ "$UC_NOW" -gt "${UC_SIZES[$_i]}" ]]; then
      tail -c "+$(( UC_SIZES[_i] + 1 ))" "${UC_ASIDES[$_i]}" >> "$UC_SRC"
      UC_FOLDED=$((UC_FOLDED + UC_NOW - UC_SIZES[_i]))
    fi
    unlink "${UC_ASIDES[$_i]}"
    _i=$((_i + 1))
  done
  UC_DIR="$(dirname "$UC_SRC")"
  lrt_file_evidence unconfirmed "$(basename "$UC_DIR")" "$UC_DIR/$SID.HANDOFF.json"
  lrt_unreturn   # the move did not happen: the target's own leftovers from the hop it reversed go back
  rm -f "$LOCK"
  UC_FOLD_JSON=""
  [[ $UC_FOLDED -eq 0 ]] || UC_FOLD_JSON=",\"folded_stub_bytes\":$UC_FOLDED"
  printf '{"ok":true,"phase":"unconfirm","sid":"%s","restored":"%s","evidence":"%s"%s%s}\n' "$SID" "$UC_SRC" "$EVIDENCE" "$(lrt_restored_json)" "$UC_FOLD_JSON"
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
     && [[ "$(tail -c "$FS_BYTES" "$FS_R" | "$CC_SHA256" | cut -d' ' -f1)" == "$(lrt_sha "$FS_STUB")" ]]; then
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
  AB_TOMB="$(lrt_at "$FROM" .HANDOFF.json)"
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
    _c="$(lrt_at "$FROM" .jsonl)"
    [[ -z "$_c" ]] || AB_SLUG="$(basename "$(dirname "$_c")")"
  fi
  lrt_file_evidence aborted "$AB_SLUG" "$AB_TOMB"
  lrt_unreturn   # the move did not happen: the target's own leftovers from the hop it reversed go back
  rm -f "$LOCK"
  printf '{"ok":true,"phase":"abort","sid":"%s","evidence":"%s"%s}\n' "$SID" "$EVIDENCE" "$(lrt_restored_json)"
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
  _dst="$(lrt_at "$TO" .jsonl)"
  [[ -n "$_dst" ]] || return 1
  # Completeness, only when a live source copy survives to compare against. Bytes, not sha: the
  # successor has been APPENDING to the target since the transplant, so the two are legitimately
  # unequal and only "at least as much" is a meaningful test.
  _src="$(lrt_at "$FROM" .jsonl)"
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

# Locate the source transcript (exactly one real file). (macOS ships bash 3.2 — no mapfile.) A glob
# on purpose, not lrt_at: "exactly one" needs every slug, and this is the move's one source walk.
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
[[ "${LR_MOVE_LOCATION_FAST:-on}" == off ]] || LRT_SLUG="$SLUG"   # every later lookup: the located slug
DST_DIR="$TO/projects/$SLUG"
DST="$DST_DIR/$SID.jsonl"

if [[ -e "$DST" && $FORCE -ne 1 ]]; then
  echo "lr-transplant: REFUSED — $DST already exists (use --force to overwrite)" >&2; exit 2
fi
# THE ARRIVAL CHECK SPANS EVERY SLUG (LR_SUSTAINED_LOAD W3; B4 correctness review F4). A copy of
# $SID under ANOTHER slug in the target is not refused by the same-slug test above, so the move
# went through and left the target holding two copies, and the NEXT hop off it died "multiple
# copies … disambiguate manually": a strand only an operator could clear. Refused here, before any
# lock or tombstone, it is one refused attempt and a re-place. One glob per move (1.2-2.4 s at
# load1 241-247, review F10), off the scorer. An unmatched glob stays literal, which -e rejects.
if [[ $FORCE -ne 1 ]]; then
  for _arr in "$TO"/projects/*/"$SID".jsonl; do
    if [[ -e "$_arr" ]]; then
      echo "lr-transplant: REFUSED — $_arr already exists (another slug than $SLUG; use --force to overwrite)" >&2; exit 2
    fi
  done
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
# ══ A COPY THAT DIES RELEASES WHAT THIS RUN TOOK (report lr-reliability-telemetry-speed 2026-10-10,
# ranks 8-9) ════════════════════════════════════════════════════════════════════════════════════
# Everything from the lock write to the sha check runs under `set -euo pipefail`, so a mid-rsync
# death (58d3640a: `mkstempat tool-results/… No such file`, rsync rc 23) exits here holding a lock
# and a partial target copy, with no tombstone. The orphan lock then made the poller retire the
# request as "transplanted" (lr_transplanted_to reads `to` off the lock) while the session sat
# LIMITED, and a lead's mail woke it, not the rail.
# So a run that writes a FRESH lock — no lock and no target transcript before it — arms an EXIT
# trap for that window: on a non-zero exit it moves the partial copy into an evidence dir (not a
# deletion: only `lr-lock.py evidence-gc` frees it, once every file is proven to be in an account
# store; see lrt_file_evidence) and releases the lock, but only a lock that still records THIS pid.
# A lock or a target copy that predates the run (a second hop, a --force over a stale lock or copy)
# is someone else's custody and is left exactly as trunk left it. Disarmed the moment the sha check
# passes.
LRT_CLEANUP=0 LRT_DIR_FRESH=0
# A target that already holds a live copy before this run is never swept at admit (THE RETURN HOP):
# its marker may be a later move's tombstone, which is the hazard THE SWEEP NEVER UNDOES describes.
# A glob on purpose, not lrt_at: a copy at ANY slug is a return hop, and absence needs every slug.
LRT_TO_LIVE_BEFORE=""
for _c in "$TO"/projects/*/"$SID".jsonl; do [[ -f "$_c" ]] && LRT_TO_LIVE_BEFORE="$_c"; done
[[ -e "$LOCK" || -e "$DST" ]] || LRT_CLEANUP=1
[[ -e "$DST_DIR/$SID" ]] || LRT_DIR_FRESH=1
lrt_admit_cleanup() { # $1=the exiting rc → always 0; acts only on a non-zero exit inside the window
  local rc="${1:-0}" ev
  [[ "$rc" -ne 0 && "${LRT_CLEANUP:-0}" -eq 1 ]] || return 0
  [[ -e "$LOCK" && "$(lrt_lock_json pid)" == "$$" ]] || return 0
  ev="$LOCK_DIR/$SID.failed-admit-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir "$ev" 2>/dev/null || { ev="$ev.$$"; mkdir "$ev" 2>/dev/null || return 0; }
  if [[ -e "$DST" ]] && ! mv "$DST" "$ev/" 2>/dev/null; then
    echo "lr-transplant: the admit died (rc $rc) and the partial target copy $DST could not be moved aside — the lock is KEPT so nothing resumes it; release by hand: python3 ${BASH_SOURCE[0]%/*}/lr-lock.py release $SID --why …" >&2
    return 0
  fi
  if [[ $LRT_DIR_FRESH -eq 1 && -d "$DST_DIR/$SID" ]]; then mv "$DST_DIR/$SID" "$ev/" 2>/dev/null || true; fi
  cp "$LOCK" "$ev/lock" 2>/dev/null || true
  rm -f "$LOCK" 2>/dev/null || true
  echo "lr-transplant: the admit died (rc $rc) after this run took the lock and before the tombstone — released the lock and moved the partial target copy to $ev; the source is untouched and a retry is safe" >&2
  return 0
}
[[ $LRT_CLEANUP -eq 0 ]] || trap 'lrt_admit_cleanup "$?"' EXIT
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

SHA_SRC=$("$CC_SHA256" "$SRC" | cut -d' ' -f1)
SHA_DST=$("$CC_SHA256" "$DST" | cut -d' ' -f1)
if [[ "$SHA_SRC" != "$SHA_DST" ]]; then
  echo "lr-transplant: FATAL — sha mismatch after copy (src=$SHA_SRC dst=$SHA_DST)" >&2; exit 2
fi
LRT_CLEANUP=0   # the copy is proven; from here the lock and the target copy are the move's custody

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
# The source's OWN old retired copy (a round trip's leftover, prefix-proven: see STALE ROUND-TRIP
# LEFTOVERS) goes aside here, so the guard's admit allowance and the later confirm see a clean source.
if lrt_stale_retired "$SRC"; then lrt_setaside "$SRC.handed-off" || true; fi
# THE RETURN HOP: the target's leftovers from the departure this move reverses go aside BEFORE the
# source's tombstone exists, so no reader ever sees both ends of the cycle. A keep-source run leaves
# two live copies on purpose and sweeps nothing. The renames land on the lock, where abort, unconfirm
# and lr-lock.py release find them; should that write fail, they are put straight back.
if [[ $KEEP_SOURCE -ne 1 && -z "$LRT_TO_LIVE_BEFORE" ]]; then
  lrt_sweep_target "$DST_DIR" "$NOW" admit
  if [[ -n "$LRT_RETURNED" ]] && ! printf '%s' "$LRT_RETURNED" | python3 -c '
import json, os, sys
lock = sys.argv[1]
with open(lock) as fh:
    d = json.load(fh)
d["returned"] = [{"path": p, "aside": a} for p, a in (l.split("\t", 1) for l in sys.stdin.read().splitlines() if "\t" in l)]
tmp = "%s.tmp.%d" % (lock, os.getpid())
with open(tmp, "w") as fh:
    fh.write(json.dumps(d, ensure_ascii=False, separators=(",", ":")) + "\n")
os.replace(tmp, lock)
' "$LOCK"; then
    while IFS=$'\t' read -r _p _a; do
      [[ -n "$_p" ]] && { lrt_link_rename "$_a" "$_p" || echo "lr-transplant: could not put back $_p from $_a" >&2; }
    done <<< "$LRT_RETURNED"
    LRT_SET_ASIDE=""
    echo "lr-transplant: could not record the target's set-aside leftovers on $LOCK — put them back; the return-hop cycle stays for the confirm sweep" >&2
  fi
fi
TOMBSTONE="$SRC_DIR/$SID.HANDOFF.json"
# The phase rides on the tombstone so handed-off-session-guard.sh can tell a half-done move (admit:
# the source is still the live writer, so a typed prompt belongs there) from a finished one (D7.2a,
# operator ruling 28740361e7dd). A keep-source run never retires its source, so it carries no phase
# and the guard keeps blocking it; without --phase the fragment is empty and the shape is unchanged.
LRT_TOMB_PHASE_JSON="$LRT_PHASE_JSON"
[[ $KEEP_SOURCE -eq 1 ]] && LRT_TOMB_PHASE_JSON=""
printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"%s%s}\n' \
  "$TO" "$DST" "$NOW" "$LOCK" "$LRT_CAUSE_JSON" "$LRT_TOMB_PHASE_JSON" > "$TOMBSTONE"
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

printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"source_retired_reason":"%s","lock":"%s","tombstone":"%s","hop":%d,"ts_first":"%s","chain":[%s]%s%s%s%s}\n' \
  "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" \
  "$SOURCE_RETIRED_REASON" "$LOCK" "$TOMBSTONE" \
  "$LRT_HOPS" "$LRT_TS_FIRST" "$LRT_CHAIN_JSON" "$LRT_CUSTODY_JSON" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON" "$(lrt_set_aside_json)"
