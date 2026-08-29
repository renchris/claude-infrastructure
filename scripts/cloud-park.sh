#!/usr/bin/env bash
# cloud-park.sh — a cloud worker's ONLY way to park its own backlog row.
#
#   scripts/cloud-park.sh <backlog-id> --needs "<the operator-only step>" [--why "<prose>"]
#   scripts/cloud-park.sh --selftest
#
# WHY THIS EXISTS. Every cloud dispatch brief ends with the same two fallbacks: park the row with
# `cc-backlog block <id> --needs "<step>"`, then wake the desk with `cc-notify --role desk`. NEITHER
# IS REACHABLE FROM A CLOUD VM. The backlog store is ~/.claude/autonomy/backlog.jsonl, which exists
# only on the operator's box; the verbs answer `unknown id` / `role-unset` and return 3, writing
# nothing. So the one instruction that would take an operator-gated row OUT of the dispatch wave is
# inert in the venue the wave dispatches into, the row stays `open`, and the next pass fires it
# again — measured on backlog f85fce7c26f5, ten dispatches, ten branches, one unchanged verdict
# (docs/research/cloud-land-arm-step-2026-08-25.md §6.6, corrected 2026-08-29 for the exit codes).
#
# THE CHANNEL IS THE BRANCH, because a VM has no other. CLOUD_OBSERVABILITY.md §14 already
# established that for the CLOSE — a worker that finds its row cured lands a verdict artifact, and
# `cloud-return.sh` step 8 turns the landed path into `cc-backlog done`. This is the same rail for
# the other terminal disposition: a landed `docs/parks/<id>.md` turns into `cc-backlog block <id>
# --needs "<step>"`. The desk stays the only writer of the ledger; the VM states the fact, in the one
# medium it can push, and the fact is content-verified on trunk before it is acted on.
#
# ── THE FILE IS AN APPEND-ONLY LOG, AND THE ENTRY NAMES ITS BRANCH ──────────────────────────────
# Both properties are load-bearing and neither is decoration:
#
#   · APPEND-ONLY, because a park is a statement made by one dispatch and the next dispatch's
#     statement must not delete it. The row's history — which venues tried, what each could not do —
#     is exactly what stops an eleventh dispatch re-deriving the tenth's finding.
#   · `branch:`, because the file OUTLIVES the park. Once the operator unblocks the row and it is
#     re-dispatched, `docs/parks/<id>.md` is still on trunk; a reader keyed only on its existence
#     would re-park the new dispatch the moment it landed anything, and the row would never leave
#     `blocked`. cloud-return honours the LAST entry only when its `branch:` is the branch of the
#     dispatch being returned, so a stale entry is inert by construction rather than by cleanup.
#
# ── WHAT IT REFUSES ─────────────────────────────────────────────────────────────────────────────
# A park that cannot be acted on is worse than no park: it lands, reads as done, and leaves the row
# in the wave anyway. So a malformed one is refused HERE, at the only point where a human is looking
# at it, rather than discovered by an unattended sweep on the operator's box at 3am:
#   · an id that is not the store's 12-hex shape — free text would be passed to a verb that takes a
#     key, and `cc-backlog block "cc-offload brief.txt"` is not a park.
#   · an empty `--needs`, which `cc-backlog block` itself rejects at rc 2.
#   · a multi-line `--needs`. The reader takes ONE line; a second line would be silently dropped,
#     and a step whose second half is invisible is the shape of an operator running the wrong thing.
#   · a detached HEAD, or a branch this dispatch does not actually sit on — the entry's whole
#     scoping property is that `branch:` is a fact, not an intention.
#
# It does NOT commit, land, or notify. The park is finished by the ordinary rails — commit the file,
# `/ship` it — and the operator learns of it through cloud-return's wake, which is the same channel
# a landed close uses.
#
# EXITS: 0 written · 2 usage/refusal · 3 not a work tree.
set -uo pipefail

SELF="$0"; while [ -L "$SELF" ]; do _t="$(readlink "$SELF")"; case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac; done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"

PARK_DIR="docs/parks"

# ── the two pure functions the selftest drives with no repo at all ───────────────────────────────

# park_id_ok — the store's key shape, and nothing else. 12 lowercase hex, exactly as cloud-return's
# own guard at step 8 spells it (a second spelling of a key shape is a second thing to drift).
park_id_ok() { # <id>
  case "$1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
    *) return 1 ;;
  esac
}

# park_needs_ok — one non-empty line. The newline test is the whole point: a `--needs` carrying a
# second line writes a `needs:` field the reader truncates, and the truncation is silent.
park_needs_ok() { # <needs>
  [ -n "${1:-}" ] || return 1
  # COUNT the newlines rather than glob for one. `case "$1" in *"$(printf '\n')"*)` looks like the
  # obvious spelling and is a tautology: command substitution strips trailing newlines, so the
  # pattern collapses to `**` and matches EVERY value — the guard would have refused its own
  # documented example. `printf '%s'` adds no trailing newline, so `wc -l` here counts only embedded
  # ones (memory: a guard whose pattern is empty is a guard that always fires).
  [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -eq 0 ] || return 1
  # a value that is only whitespace is empty as far as the operator reading it is concerned
  case "$1" in *[![:space:]]*) return 0 ;; *) return 1 ;; esac
}

# park_entry — the entry, as one block. It sits ABOVE --selftest because a definition is a statement:
# the selftest exits before the bottom of the file is ever reached, so a function declared down there
# would not exist to be asserted against — which is the shape of a suite that passes by not running.
park_entry() { # <stamp> <branch> <needs> <why>
  printf '## %s\n\n' "$1"
  printf 'branch: %s\n' "$2"
  printf 'needs: %s\n' "$3"
  [ -n "${4:-}" ] && printf '\n%s\n' "$4"
  printf '\n'
}

if [ "${1:-}" = "--selftest" ]; then
  checks=0; fails=0
  ok() { checks=$((checks+1)); "$@" || { fails=$((fails+1)); echo "  FAIL: $*"; }; }
  no() { checks=$((checks+1)); "$@" && { fails=$((fails+1)); echo "  FAIL (expected refusal): $*"; }; return 0; }

  ok park_id_ok f85fce7c26f5
  no park_id_ok F85FCE7C26F5           # the store writes lowercase; an upper-case key misses
  no park_id_ok f85fce7c26f            # 11
  no park_id_ok f85fce7c26f5a          # 13
  no park_id_ok "cc-offload brief.txt" # free text — `item` is free text by contract
  no park_id_ok ""

  ok park_needs_ok "bash scripts/cloud-land-arm-diagnose.sh"
  no park_needs_ok ""
  no park_needs_ok "   "
  no park_needs_ok "$(printf 'run this\nand also this')"

  # the entry the writer emits must be readable by the reader's own idiom (sed 's/^needs: *//p'),
  # which is the seam where a format change would go unnoticed on both sides at once
  entry="$(park_entry 2026-08-29T00:00:00Z claude/fire-x 'bash scripts/x.sh' 'because')"
  checks=$((checks+1))
  [ "$(printf '%s\n' "$entry" | sed -n 's/^needs: *//p' | tail -1)" = "bash scripts/x.sh" ] \
    || { fails=$((fails+1)); echo "  FAIL: the emitted entry's needs: is not readable by the reader's idiom"; }
  checks=$((checks+1))
  [ "$(printf '%s\n' "$entry" | sed -n 's/^branch: *//p' | tail -1)" = "claude/fire-x" ] \
    || { fails=$((fails+1)); echo "  FAIL: the emitted entry's branch: is not readable by the reader's idiom"; }

  if [ "$fails" -eq 0 ]; then
    echo "cloud-park --selftest: $checks/$checks — the id shape is the store's own (case, both lengths, free text and empty all refused), a needs of one non-empty line is required and a two-line one refused, and the entry this writer emits is parsed by the same two idioms cloud-return reads it with."
    exit 0
  fi
  echo "cloud-park --selftest: FAILED ($fails of $checks)."
  exit 1
fi

usage() { sed -n '2,5p' "$SELF" >&2; }

ID=""; NEEDS=""; WHY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --needs) NEEDS="${2:-}"; shift 2 || shift ;;
    --why)   WHY="${2:-}";   shift 2 || shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "cloud-park: unknown argument '$1'" >&2; usage; exit 2 ;;
    *) [ -z "$ID" ] || { echo "cloud-park: one backlog id, not two ('$ID' then '$1')" >&2; exit 2; }
       ID="$1"; shift ;;
  esac
done

[ -n "$ID" ] || { echo "cloud-park: a backlog id is required." >&2; usage; exit 2; }
park_id_ok "$ID" || {
  echo "cloud-park: '$ID' is not a backlog id — the store's key is 12 lowercase hex characters." >&2
  echo "  A park writes a file the desk hands to \`cc-backlog block\`, which takes a key; free text there is not a park." >&2
  exit 2; }
park_needs_ok "$NEEDS" || {
  echo "cloud-park: --needs \"<the operator-only step>\" is required, and it must be ONE non-empty line." >&2
  echo "  The reader takes one line. A second line would be dropped in silence, which is how an operator ends up running half a step." >&2
  exit 2; }

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "cloud-park: $ROOT is not a git work tree — a park's only channel is a branch." >&2; exit 3; }

BRANCH="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -n "$BRANCH" ] || {
  echo "cloud-park: HEAD is detached, so this park could not name the branch it belongs to." >&2
  echo "  The branch is what keeps the entry from re-parking a LATER dispatch of the same row; without it the file is a permanent block." >&2
  exit 2; }

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FILE="$ROOT/$PARK_DIR/$ID.md"
mkdir -p "$ROOT/$PARK_DIR" || { echo "cloud-park: cannot create $ROOT/$PARK_DIR" >&2; exit 3; }

# The header is written once, on the file's first entry — a per-entry banner would bury the log it
# introduces. A QUOTED heredoc, not printf: this prose is full of `backticks`, which are command
# substitution inside double quotes and SC2016 noise inside single ones.
if [ ! -f "$FILE" ]; then
  { printf '# park log — cc-backlog %s\n\n' "$ID"
    cat <<'HDR'
Written by a cloud worker that could not advance this row, because the verb that would have parked
it (`cc-backlog block`) cannot reach the store from a cloud VM. See `scripts/cloud-park.sh` for why
this file is the channel and `docs/research/cloud-land-arm-step-2026-08-25.md` §6.6 for what it
replaces.

APPEND ONLY. `scripts/cloud-return.sh` reads the LAST entry and honours it only when its `branch:`
names the branch of the dispatch it is returning — so an entry written by an earlier dispatch is
inert, and this file can never block a row it is not about.

HDR
  } >"$FILE"
fi

park_entry "$STAMP" "$BRANCH" "$NEEDS" "$WHY" >>"$FILE"

echo "cloud-park: parked $ID on branch $BRANCH"
echo "  file : $PARK_DIR/$ID.md"
echo "  needs: $NEEDS"
echo
echo "The park is NOT in effect until this file is on trunk — the ledger's only writer is the desk."
echo "Finish it the ordinary way:"
echo "    git add $PARK_DIR/$ID.md && git commit && /ship"
echo "cloud-return's next pass reads it and calls: cc-backlog block $ID --needs \"$NEEDS\""
