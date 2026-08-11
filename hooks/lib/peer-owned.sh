#!/usr/bin/env bash
# peer-owned.sh — SSOT oracle: "are this tree's unlanded commits owned by a DIFFERENT, still-LIVE
# session?"  The 📦 counterpart of hooks/lib/session-writes.sh, and it exists for the same reason:
# a ledger that reads FACTS is right to, but a guard that CONVICTS on those facts must first ask
# whose they are.
#
# ── THE DEFECT (measured 2026-08-03) ─────────────────────────────────────────────────────────────
# completion-assert.sh's 📦 term counts `trunk..HEAD` and convicts the closing session for whatever
# it finds. In a SHARED checkout that is routinely the wrong session. Session
# claude-infrastructure-323 (pid 21049) — a read-only research turn, clean tree, ZERO files written
# — was blocked 3 of 3 for two commits (5dbaf901 7h old, a33e854f 10h old) authored by
# claude-infrastructure-234 (pid 68327), which had been running ~17h and was still alive.
#
# Neither answer the guard would accept was available:
#   · "/ship to land it" — the hook's own instruction — means landing a live peer's ungated commits
#     from the shared checkout, which .claude/CLAUDE.md forbids by name (incident 2026-07-11:
#     dfacccd's five files were rebase-dropped by a concurrent land of a branch that session never
#     created, while `git rev-list origin/main..HEAD` read 0 — "looks landed", files absent).
#   · stay blocked forever, because `genuine` enumerates credential / sudo / destructive-migration /
#     external-info / value-fork, and peer-ownership is not one of those spellings.
# The escape hatch could not express the true state, so the only compliant close was a rule
# violation. That is the denylist-enumerates-spellings-not-the-class shape (MEMORY.md): the guard
# was not wrong about the git facts, it was missing a state.
#
# Handing ownership back over the wire does not help either, and the incident proves it: the
# sibling WAS notified (`cc-notify verdict=delivered uuid=234 line=1`) and accepted the work. The
# count did not move, because the hook reads git, not the mailbox. A state that only a message can
# express is invisible to every sensor; this file makes it a disk-truth read instead.
#
# ── WHY LIVENESS IS THE DISCRIMINATOR, AND NOT AGE OR AUTHORSHIP ALONE ───────────────────────────
# "These commits are not mine" CANNOT be the whole test. The fleet's commonest succession —
# `/handoff` and `handoff-fire.sh --recycle` — hands a predecessor's committed-but-unlanded work to
# a SUCCESSOR whose whole job is to land it. That successor did not author those commits either, so
# exonerating on non-authorship alone would silently retire the 📦 rung for precisely the case it
# was built for. What separates the two is whether anyone else is still holding the work:
#
#   · handoff / recycle successor → the predecessor is DEAD (it retired INTO this session). Nobody
#     else will ever land those commits ⇒ CONVICT. Unchanged, and that is the point.
#   · concurrent sibling in a shared checkout → the author is ALIVE and still owns its own work
#     ⇒ LIVE-PEER-OWNED. Not this session's to land, and landing it is the forbidden act.
#
# So the peer must be alive NOW *and* must have been running when the commit was made. Drop either
# half and this stops discriminating: liveness alone lets any long-lived pane launder a
# predecessor's stranded commits, and precedence alone re-admits the dead predecessor.
#
# ── THE PREDICATE — a conjunction, every term POSITIVE evidence ──────────────────────────────────
#   (1) NON-AUTHORSHIP, proved either of two independent ways (either suffices):
#       (1a) every unlanded commit predates this session's start — an ordering fact that no tool
#            residue can defeat: a session cannot have made a commit that existed before it did; or
#       (1b) this session provably wrote no file AND ran no commit-producing git command. (1b) is
#            what covers the measured incident, whose session may well have outlived the commits.
#   (2) A LIVE PEER: a cc-registry session that is not this one, whose cwd is inside this same repo,
#       whose process is alive, and whose start PRECEDES the oldest unlanded commit.
# Any term unresolvable ⇒ rc 2 ⇒ the caller stays exactly as strict as it was. Ignorance never
# exonerates (MEMORY.md lookup-miss-is-not-absence).
#
# ── THREE STATES, NEVER TWO (the session-writes.sh contract, deliberately identical) ─────────────
#   rc 0  live-peer-owned  — the conjunction holds; a one-line evidence string on stdout
#   rc 1  not peer-owned   — a term was definitely refuted
#   rc 2  cannot-tell      — no jq/git, unreadable registry, unresolvable session start, …
# rc 1 and rc 2 are the SAME disposition for the caller (convict) and are still kept apart: the
# next person debugging a conviction needs to know whether a term was refuted or never read.
#
# ── WHAT THIS DOES *NOT* DO ─────────────────────────────────────────────────────────────────────
# It does not touch scripts/wrap-ledger.sh and it does not change a RUNG. The ledger still computes
# 📦, /wrap and operator-readout.sh still render it, and the commits are still visibly unlanded —
# which is correct, because they ARE. The only thing withheld is the Stop-hook BLOCK, i.e. the
# demand that THIS session act on them. Re-deriving UNLANDED here instead would give two auditors
# over one population with no shared state model (MEMORY.md make-the-actuator-the-arbiter,
# sibling-auditors-must-share-the-state-model); asking a second, independent question about
# OWNERSHIP is the same move `_ca_mine` already makes for authorship.
#
# ── KNOWN COVERAGE RESIDUE (named, not silently absorbed) ────────────────────────────────────────
#   · (1b)'s command scan reads the transcript's Bash `command` strings. A commit made by a SCRIPT
#     the session ran (`bash scripts/foo.sh`, where foo.sh commits) is invisible to it — the same
#     class of residue session-writes.sh names for `sed -i`. It costs coverage, never correctness:
#     the miss direction is "cannot prove non-authorship" ⇒ no exoneration ⇒ strict.
#   · A registry row whose cwd is spelled logically where git answers physically will not match, so
#     a real peer can go unseen ⇒ strict.
#   · PID REUSE. Liveness is `kill -0`, which is the oracle bin/cc-sessions:234 calls authoritative,
#     and a dead row is RETAINED for CC_REG_RETAIN_H (24h) as forensics — so a reused pid inside
#     that window reads as alive. A bespoke second identity check here was tried and rejected twice:
#     `ps -o comm=` cannot be fixtured (a copied /bin/sleep is SIGKILLed on arm64 — it is a platform
#     binary and the copy leaves the sealed volume), and a process-start-vs-startedAt check is
#     unsatisfiable by any fixture whose peer must predate a commit. Both would also have given this
#     file a liveness model no sibling shares, which is the defect MEMORY.md
#     sibling-auditors-must-share-the-state-model names. So the residue is NAMED rather than
#     half-closed: it needs a dead peer, its row unswept, its pid reused, its cwd still matching,
#     and this session to have provably neither written nor committed — and the cost is one
#     withheld nudge over commits this session must not land anyway.
# The first two residues fail toward CONVICTION, which preserves the guard. The third does not, and
# is bounded as above rather than pretended away.
#
# Env seams (tests): CC_REGISTRY_DIR · SESSION_WRITES_LIB · PEER_OWNED_TIMEOUT_S
# Pure function definitions only — no side effects on source (safe under `set -u`).

# Bound every read: this runs from a Stop hook, and a wedged read must never hold the close open.
# No `timeout` on PATH ⇒ run unbounded rather than lose the signal (mirrors session-writes.sh:68).
_po_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# _po_session_start <transcript_path> <session_id> → epoch seconds on stdout, rc 0; rc 1 unresolvable
#   THE MINIMUM OF EVERY AVAILABLE ORACLE, never the first one that answers. Both sources can move
#   FORWARD independently — a `/compact` truncates the transcript's early records, and a session
#   absent from the registry contributes nothing — and a start estimate that moves forward makes
#   MORE commits look like they predate this session, i.e. it loosens (1a) in the unsafe direction.
#   Taking the min means no single source moving forward can loosen the term; each can only tighten
#   it. A resumed transcript, whose first record predates this session, is the same safe direction.
_po_session_start() {
  local tp="${1:-}" sid="${2:-}" t_rec="" t_reg="" best="" reg_dir
  command -v jq >/dev/null 2>&1 || return 1

  if [ -n "$tp" ]; then
    case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
    if [ -f "$tp" ]; then
      # `first(inputs | …)` short-circuits INSIDE jq. A `jq … | head -1` would SIGPIPE jq and, under
      # the caller's `set -o pipefail`, hand back rc 141 for a read that in fact succeeded — the
      # pipefail+SIGPIPE shape that already cost this repo a false precondition failure (53d45a09).
      # `.timestamp` is ISO-8601 with fractional seconds, which `fromdateiso8601` rejects, so the
      # fraction is stripped in jq rather than by shelling out to a `date` whose flags differ
      # between BSD and GNU.
      t_rec="$(_po_bounded "${PEER_OWNED_TIMEOUT_S:-5}" jq -rn '
          first(inputs
                | select((.timestamp // "") != "")
                | .timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
        ' "$tp" 2>/dev/null)" || t_rec=""
      case "$t_rec" in ''|*[!0-9]*) t_rec="" ;; esac
    fi
  fi

  reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  if [ -n "$sid" ] && [ "$sid" != "?" ] && [ -d "$reg_dir" ]; then
    # shellcheck disable=SC2016  # $sid is a jq binding (--arg), so shell expansion must NOT happen
    t_reg="$(_po_bounded "${PEER_OWNED_TIMEOUT_S:-5}" jq -rn --arg sid "$sid" '
        first(inputs | select((.session_id // "") == $sid) | ((.startedAt // 0) / 1000 | floor))
      ' "$reg_dir"/*.json 2>/dev/null)" || t_reg=""
    case "$t_reg" in ''|0|*[!0-9]*) t_reg="" ;; esac
  fi

  best="$t_rec"
  if [ -n "$t_reg" ]; then
    if [ -z "$best" ] || [ "$t_reg" -lt "$best" ]; then best="$t_reg"; fi
  fi
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

# _po_wrote_or_committed <transcript_path> → rc 0 it did · rc 1 provably did neither · rc 2 cannot tell
#   Term (1b). Two questions, both answered from the transcript this session owns:
#     · did it write a tracked file?  → delegated to session-writes.sh, which is the SSOT for the
#       file-edit tool list. Re-listing those four tool names here is how the two would drift apart.
#     · did it run a command that could CREATE a commit? → the residue session-writes.sh names by
#       name ("a file written ONLY through Bash is invisible here"). For authorship of a COMMIT the
#       residue is closable, because the commit-producing verbs are a small, stable set and the
#       transcript records every Bash `command` string verbatim.
#   The command match is deliberately OVER-broad (`git log --grep=commit` trips it). Over-matching
#   costs an exoneration; under-matching costs the guard.
_po_wrote_or_committed() {
  local tp="${1:-}" lib rc cmds
  command -v jq >/dev/null 2>&1 || return 2
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 2

  if ! command -v session_writes_paths >/dev/null 2>&1; then
    lib="${SESSION_WRITES_LIB:-}"
    if [ -z "$lib" ] || [ ! -f "$lib" ]; then
      lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/session-writes.sh"
    fi
    [ -f "$lib" ] || lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/session-writes.sh"
    [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/session-writes.sh"
    [ -f "$lib" ] || return 2
    # shellcheck source=lib/session-writes.sh
    # shellcheck disable=SC1091
    . "$lib" 2>/dev/null || return 2
  fi

  session_writes_paths "$tp" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 2 ] && return 2
  [ "$rc" -eq 0 ] && return 0          # it wrote files ⇒ (1b) refuted, no further question needed

  # Sidechain records are INCLUDED, exactly as session-writes.sh includes them: a subagent's commit
  # is this session's commit, and excluding it would attribute the session's own work to nobody.
  # shellcheck disable=SC2016  # jq filter body — no shell expansion intended
  cmds="$(_po_bounded "${PEER_OWNED_TIMEOUT_S:-5}" jq -rn '
      inputs
      | select(.type=="assistant")
      | .message.content[]?
      | select(.type=="tool_use" and .name=="Bash")
      | (.input.command // "")
      | select(. != "")
    ' "$tp" 2>/dev/null)" || return 2

  # `[^;&|]` bounds the scan to ONE command in a chain, so `git log --oneline | grep commit` does
  # not read as a commit — the pipeline's second stage is a different command.
  if printf '%s\n' "$cmds" \
     | grep -qE '(^|[^A-Za-z0-9_-])git[^;&|]{0,160}[^A-Za-z0-9_-](commit|cherry-pick|rebase|merge|revert)([^A-Za-z0-9_-]|$)'; then
    return 0
  fi
  return 1
}

# _po_live_peer <repo_top> <my_session_id> <before_epoch> → peer label on stdout, rc 0; rc 1 none; rc 2 cannot tell
#   Term (2). The registry schema is ~/.claude/cc-registry/<paneUUID>.json written by the
#   session-register.sh SessionStart hook: {paneUUID,name,cwd,account,pid,startedAt,session_id}.
#   Liveness is `kill -0` on the pid — deliberately the same oracle bin/cc-sessions:234 calls
#   authoritative, because one discriminator with two policies is the same defect as two
#   discriminators (MEMORY.md sibling-auditors-must-share-the-state-model). A row with no paneUUID
#   is what that lister sweeps as CORRUPT rather than dead, so it is dropped here too. See PID REUSE
#   under KNOWN COVERAGE RESIDUE for what this deliberately does not close, and why not.
_po_live_peer() {
  local top="${1:-}" sid="${2:-}" before="${3:-}" reg_dir rows pid label
  command -v jq >/dev/null 2>&1 || return 2
  [ -n "$top" ] || return 2
  case "$before" in ''|*[!0-9]*) return 2 ;; esac
  reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
  [ -d "$reg_dir" ] || return 2

  # ONE jq over the whole registry, not one per file: this runs at every qualifying Stop and the
  # live fleet is ~50 rows. Everything cheap and total is filtered here; cwd is NOT, because it
  # needs canonicalisation the shell has to do (below).
  # shellcheck disable=SC2016  # $sid/$before are jq bindings; shell expansion must NOT happen
  rows="$(_po_bounded "${PEER_OWNED_TIMEOUT_S:-5}" jq -rn \
      --arg sid "$sid" --argjson before "$before" '
      inputs
      | select((.paneUUID // "") != "")
      | select((.session_id // "") != $sid)
      | select((.pid // 0) > 0)
      | select(((.startedAt // 0) / 1000 | floor) > 0)
      | select(((.startedAt // 0) / 1000 | floor) <= $before)
      | select((.cwd // "") != "")
      | [(.pid | tostring), (.name // .paneUUID), .cwd]
      | @tsv
    ' "$reg_dir"/*.json 2>/dev/null)" || return 2
  [ -n "$rows" ] || return 1

  while IFS="$(printf '\t')" read -r pid label pcwd; do
    [ -n "$pid" ] || continue
    # CANONICALISE THE PEER'S CWD BEFORE COMPARING IT. `top` came through `pwd -P` (physical), and
    # the registry records cwd as the session was launched with it (logical). On macOS /var is a
    # symlink to /private/var and /tmp to /private/tmp, and this repo's live layer is symlinks
    # throughout, so the two spellings of one directory never compare equal and this loop matches
    # NOTHING — forever, silently, in the fail-strict direction. Not hypothetical: the first run of
    # tests/peer-owned.bats failed all three positive cases on exactly this, while every control
    # still passed, which is what makes it worth writing down. Same trap session_dirty_mine
    # documents; comparing raw first keeps the fork off the common path where both are already
    # physical, and a cwd that no longer resolves falls back to the raw string — a miss, never a
    # false hit.
    case "$pcwd" in
      "$top"|"$top"/*) ;;
      *) pcwd="$(cd "$pcwd" 2>/dev/null && pwd -P 2>/dev/null)" || continue
         [ -n "$pcwd" ] || continue
         case "$pcwd" in "$top"|"$top"/*) ;; *) continue ;; esac ;;
    esac
    kill -0 "$pid" 2>/dev/null || continue
    # `<label>#<pid>`, deliberately whitespace-free: the caller embeds this verbatim in an IDL
    # abstain reason that is scanned field-wise, and a label with spaces in it stops being one field.
    printf '%s#%s\n' "${label:-peer}" "$pid"
    return 0
  done <<EOF
$rows
EOF
  return 1
}

# peer_owned_unlanded <repo_dir> <trunk> <my_session_id> <transcript_path>
#   The whole conjunction. stdout on rc 0 = a one-line evidence string for the caller's IDL.
#   rc: 0 live-peer-owned · 1 not peer-owned · 2 cannot-tell   (see THREE STATES above)
peer_owned_unlanded() {
  local dir="${1:-}" trunk="${2:-}" sid="${3:-}" tp="${4:-}"
  local top oldest newest start peer rc

  command -v git >/dev/null 2>&1 || return 2
  command -v jq  >/dev/null 2>&1 || return 2
  [ -n "$dir" ] && [ -n "$trunk" ] || return 2
  case "$trunk" in none) return 2 ;; esac

  top="$(cd "$dir" 2>/dev/null && _po_bounded 5 git rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2
  top="$(cd "$top" 2>/dev/null && pwd -P 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2

  # COMMITTER date (%ct), not author date: a rebase or cherry-pick rewrites when the commit object
  # entered THIS repo, and "could this session have put it here" is the question being asked.
  oldest="$(cd "$top" 2>/dev/null && _po_bounded 5 git log --format=%ct "$trunk"..HEAD 2>/dev/null | sort -n | head -1)"
  newest="$(cd "$top" 2>/dev/null && _po_bounded 5 git log --format=%ct "$trunk"..HEAD 2>/dev/null | sort -n | tail -1)"
  case "$oldest" in ''|*[!0-9]*) return 2 ;; esac
  case "$newest" in ''|*[!0-9]*) return 2 ;; esac
  # No commits in the range ⇒ UNLANDED was set by the cherry/content check, not by a countable
  # commit. There is nothing to attribute, so this oracle has no verdict to give.

  # ── (1) NON-AUTHORSHIP — (1a) OR (1b) ──
  if start="$(_po_session_start "$tp" "$sid")" && [ "$newest" -lt "$start" ]; then
    :                                        # (1a) every unlanded commit predates this session
  else
    _po_wrote_or_committed "$tp"; rc=$?
    [ "$rc" -eq 2 ] && return 2              # cannot tell ⇒ stay strict
    [ "$rc" -eq 0 ] && return 1              # it wrote or committed ⇒ authorship not excluded
  fi

  # ── (2) A LIVE PEER that predates the oldest unlanded commit ──
  peer="$(_po_live_peer "$top" "$sid" "$oldest")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  [ -n "$peer" ] || return 2

  printf '%s\n' "$peer"
  return 0
}

# ── THE DIRTY TERM'S ORDERING PROOF (2026-08-11) ─────────────────────────────────────────────────
# Everything above answers the 📦 question — whose are these UNLANDED COMMITS. The 🔧 term of
# completion-assert.sh has the identical defect and never got an answer, so it convicted on facts it
# had not attributed. Measured twice, independently:
#   · 2026-08-07, session 44dc8891 in worktree wt-149789b69fc4: ZERO Write/Edit tool calls, yet the
#     Stop hook emitted "the LIVE ledger contradicts it — dirty tree (4 file(s))" and demanded the
#     session drive a SIBLING's in-flight work to done (backlog ce91e9583df1).
#   · 2026-08-08, session a1dd4283 in worktree wt-592061637f80: "dirty tree (8 file(s))", for 8
#     files staged by a PRIOR session before this one started (backlog 9be5e66e1c34, which isolated
#     the cause).
# THE CAUSE IS NOT A BUG IN session-writes.sh — that oracle answers rc 1 = NOT MINE for both. It is
# completion-assert.sh's `_ca_mine`, which DOWNGRADES that rc 1 to rc 2 unless the session is a
# confirmed Agent-Teams assignee ("EXONERATE ONLY ON POSITIVE EVIDENCE": a write-free transcript is
# not innocence, because the work may have gone through Bash — `sed -i`, a heredoc — which the
# oracle cannot see by construction). That rule is CORRECT and must not be widened: the same
# docstring records that exonerating every write-free session silently disabled 9 fixtures.
#
# So this supplies the missing POSITIVE evidence instead, and it is the ordering argument (1a)
# already uses: a session cannot have modified a file that was last modified before the session
# existed. That is an ordering fact no tool residue can defeat — a `sed -i` this session ran would
# stamp an mtime AFTER its start, so the Bash residue cannot be laundered through it.
#
# ── WHY THERE IS NO (1b) HERE ────────────────────────────────────────────────────────────────────
# (1b) closes the commit case by scanning the transcript's Bash strings for commit-producing verbs,
# which works only because that verb set is small and stable. The set of commands that DIRTY a tree
# is not: a redirect, a build, a package install, any script the session ran. Enumerating it would
# be the denylist-enumerates-spellings-not-the-class defect (MEMORY.md), so ordering is the only
# sound proof this term gets.
#
# ── WHY THERE IS NO LIVENESS TERM HERE, THOUGH THE SIBLING ABOVE TURNS ON ONE ────────────────────
# Liveness discriminates for COMMITS because a dead predecessor's unlanded commits really do become
# the successor's to land — /ship is the sanctioned rail for exactly that, so "nobody else will land
# these" is a reason to convict. UNCOMMITTED work has no such rail and the asymmetry is a rule, not
# a preference: CLAUDE.md G4 forbids sweeping another session's changes into a commit whether or not
# that session still lives. There is no dead-author case in which this session should commit the
# dirt, so a liveness term could only withhold exonerations it has no reason to withhold. Its
# absence is the design, not an omission.
#
# ── KNOWN COVERAGE RESIDUE (named, not silently absorbed) ────────────────────────────────────────
#   · Dirt created AFTER this session started, by a live sibling, stays CONVICTED. It has to: this
#     session could equally have made it through Bash, and per the paragraph above there is no
#     bounded verb set that would exclude that. The measured cases are both the older-dirt shape.
#   · A DELETION has no mtime to read, so it is cannot-tell (rc 2), never "old". Treating an absent
#     file as ancient is how this would exonerate a session that had just `rm`'d something.
#   · `_po_session_start` takes the MIN of the transcript's first record and the registry's
#     startedAt. That is the safe direction here too, and for the opposite reason it is safe above:
#     an EARLIER start means FEWER files predate it, i.e. fewer exonerations, i.e. stricter.

# _po_mtime <file> → mtime epoch on stdout, rc 0; rc 1 unreadable/non-numeric
#   BSD `stat -f` first (this fleet is macOS), GNU `stat -c` second. GNU's `-f` means --file-system
#   and can EXIT 0 while printing something that is not an mtime, so the fallback is chosen on the
#   VALUE being numeric rather than on the exit status — an rc-only chain would accept that garbage.
_po_mtime() {
  local f="${1:-}" m
  [ -n "$f" ] || return 1
  m="$(stat -f %m "$f" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m="$(stat -c %Y "$f" 2>/dev/null)" ;; esac
  case "$m" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$m"
}

# dirt_predates_session <repo_dir> <my_session_id> <transcript_path>
#   "Was every dirty path in this tree last modified BEFORE this session started?"
#   stdout on rc 0 = a whitespace-free evidence string for the caller's IDL.
#   rc: 0 all dirt predates this session · 1 refuted (something is at-or-after its start)
#       · 2 cannot-tell   (see THREE STATES above)
dirt_predates_session() {
  local dir="${1:-}" sid="${2:-}" tp="${3:-}"
  local top start porcf rec rel abs mt newest=0 n=0 skip_next=0 rc=0

  command -v git >/dev/null 2>&1 || return 2
  [ -n "$dir" ] || return 2

  top="$(cd "$dir" 2>/dev/null && _po_bounded 5 git rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2

  start="$(_po_session_start "$tp" "$sid")" || return 2
  case "$start" in ''|*[!0-9]*) return 2 ;; esac

  # -z + core.quotePath=false + -uall, and the output goes to a FILE — every one of those is the
  # lesson session_dirty_mine already paid for and documents at length: command substitution strips
  # the NUL delimiters, git's default untracked mode collapses a new directory to one record so its
  # files are never seen, and a path with a space is emitted quoted. Diverging from that shape here
  # would give the two readers of one porcelain stream different ideas of what a dirty path is.
  porcf="$(mktemp "${TMPDIR:-/tmp}/po-porc.XXXXXX" 2>/dev/null)" || return 2
  if ! ( cd "$top" 2>/dev/null && _po_bounded 5 git -c core.quotePath=false status --porcelain -z -uall ) >"$porcf" 2>/dev/null; then
    rm -f "$porcf" 2>/dev/null; return 2
  fi

  while IFS= read -r -d '' rec; do
    [ -n "$rec" ] || continue
    # A rename/copy emits `XY NEW<NUL>OLD<NUL>` — the OLD path arrives as its own bare record with
    # no status prefix, so consume it explicitly rather than letting the 3-char strip mangle it.
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$rec" in [RC]*) skip_next=1 ;; esac
    rel="${rec:3}"
    [ -n "$rel" ] || continue
    abs="$top/$rel"
    if ! mt="$(_po_mtime "$abs")"; then rc=2; break; fi   # deletion / unreadable ⇒ cannot tell
    n=$(( n + 1 ))
    if [ "$mt" -gt "$newest" ]; then newest="$mt"; fi
    # STRICTLY BEFORE. Same-second equality is refuted, not exonerated: mtime granularity is one
    # second here, so `==` cannot distinguish "written just before the session" from "written by it".
    if [ "$mt" -ge "$start" ]; then rc=1; break; fi
  done < "$porcf"
  rm -f "$porcf" 2>/dev/null

  [ "$rc" -eq 0 ] || return "$rc"
  # No records at all ⇒ the tree is not dirty, so there is nothing to attribute and no verdict to
  # give. Returning 0 here would manufacture an exoneration out of an empty population.
  [ "$n" -gt 0 ] || return 2
  printf 'paths=%s,newest=%s,start=%s\n' "$n" "$newest" "$start"
  return 0
}
