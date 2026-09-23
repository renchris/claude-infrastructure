#!/bin/bash
# lr-transplant.sh — move a Claude Code session to another account's config dir
# (same session uuid, so --resume and Workflow resumeFromRunId journals keep working).
#
# Usage: lr-transplant.sh --sid SID --from CFGDIR --to CFGDIR
#                         [--task-list ID] [--keep-source] [--force]
#                         [--phase admit|confirm] [--cause limit|voluntary]
#
# Copies: <slug>/<sid>.jsonl + <slug>/<sid>/ (subagents, workflows, journals)
#         + tasks/<task-list>/ when given.
# Safety: split-brain lock at ~/.reso/limit-recover/locks/<sid>.lock, tombstone
#         JSON next to the source transcript, and — only once a caller has
#         ASSERTED the source is quiesced — the source transcript renamed to
#         *.jsonl.handed-off.
#
# TWO PHASES, because a HEALTHY source keeps appending after the copy:
#   --phase admit    copy + sha-verify + lock + tombstone, and NEVER retire.
#   --phase confirm  re-copy + re-verify + retire. Run it immediately before the
#                    source is told to /exit. Idempotent, and it runs UNDER the
#                    admit's lock (it never re-acquires one).
#   no --phase       the legacy single-shot run. It copies and verifies exactly
#                    as before and does NOT retire: nothing asserted quiescence.
#
# Output: one JSON object on stdout.
# Exit: 0 ok · 2 REFUSED / FATAL (nothing further attempted) · 3 usage.
set -euo pipefail

SID="" FROM="" TO="" TASK_LIST="" KEEP_SOURCE=0 FORCE=0 PHASE="" CAUSE=""
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
      [[ $# -ge 2 ]] || { echo "lr-transplant: --phase needs a value (admit|confirm)" >&2; exit 3; }
      PHASE="$2"
      case "$PHASE" in
        admit|confirm) ;;
        *) echo "lr-transplant: --phase must be admit or confirm (got '$PHASE')" >&2; exit 3 ;;
      esac
      shift 2 ;;
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
      printf '{"ok":true,"already_confirmed":true,"sid":"%s","target_transcript":"%s","retired_source":"%s","source_retired":1,"source_retired_reason":"confirm","lock":"%s"%s%s}\n' \
        "$SID" "$CONFIRM_DST" "$CONFIRM_RETIRED" "$LOCK" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON"
      exit 0
    fi
    echo "lr-transplant: FATAL — --phase confirm found no transcript $SID under $FROM/projects and no retired copy beside it; the source vanished between admit and confirm" >&2
    exit 2
  fi
  SRC="${CONFIRM_HITS[0]}"
  SRC_DIR=$(dirname "$SRC")
  SLUG=$(basename "$SRC_DIR")
  DST_DIR="$TO/projects/$SLUG"
  DST="$DST_DIR/$SID.jsonl"
  mkdir -p "$DST_DIR"
  # OVERWRITE, deliberately: the whole point of this phase is that the admit-time copy is stale.
  cp -p "$SRC" "$DST"
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
  TOMBSTONE="$SRC_DIR/$SID.HANDOFF.json"
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s"%s}\n' \
    "$TO" "$DST" "$NOW" "$LOCK" "$LRT_CAUSE_JSON" > "$TOMBSTONE"
  SOURCE_RETIRED=0
  SOURCE_RETIRED_REASON="keep-source"
  if [[ $KEEP_SOURCE -ne 1 ]]; then
    mv "$SRC" "$SRC.handed-off"
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
  printf '{"ok":true,"sid":"%s","slug":"%s","target_transcript":"%s","sha256":"%s","session_dir_copied":%s,"tasks_copied":%s,"source_retired":%s,"source_retired_reason":"%s","lock":"%s","tombstone":"%s","hop":%d,"ts_first":"%s","chain":[%s]%s%s}\n' \
    "$SID" "$SLUG" "$DST" "$SHA_DST" "$SESSION_DIR_COPIED" "$TASKS_COPIED" "$SOURCE_RETIRED" \
    "$SOURCE_RETIRED_REASON" "$LOCK" "$TOMBSTONE" "$CONFIRM_HOPS" "$CONFIRM_TS_FIRST" \
    "$CONFIRM_CHAIN_JSON" "$LRT_PHASE_JSON" "$LRT_CAUSE_JSON"
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
      echo "lr-transplant: REFUSED — session $SID is already transplanted to $LRT_LOCK_TO, not to $TO ($LOCK). Two targets for one session uuid is the split brain this lock exists to prevent; recover it at its CURRENT target, or move it ON from there with --from $LRT_LOCK_TO --to $TO, or pass --force if you have established that lock is stale." >&2
      exit 2
    fi
  fi
fi
if [[ $FORCE -ne 1 ]]; then
  if LRT_DONE="$(lrt_already_done)"; then
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
  cat "$LOCK" >&2; exit 2
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
for s, ts in out:
    print("%s\t%s" % (s, ts))
PY
)"
  if [[ -n "$LRT_TOMB_WALK" ]]; then
    LRT_PRED=""
    while IFS=$'\t' read -r _s _ts; do
      [[ -n "$_s" ]] || continue
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
printf '{"sid":"%s","from":"%s","to":"%s","ts":"%s","pid":%d,"host":"%s","owner":"%s","ts_first":"%s","chain":[%s]%s%s}\n' \
  "$SID" "$FROM" "$TO" "$NOW" "$$" "$(hostname -s)" "$TO" "$LRT_TS_FIRST" "$LRT_CHAIN_JSON" \
  "$LRT_CUSTODY_JSON" "$LRT_CAUSE_JSON" > "$LOCK"

mkdir -p "$DST_DIR"
cp -p "$SRC" "$DST"
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
