#!/usr/bin/env bash
# wrap-ledger.sh — pure-read Session-Close ledger computer (P0-2 / T-P6-1).
#
# THE DEFECT it closes (G-P6-4): the resident Session-Close Protocol claims the readout is
# "un-fakeable" because "the agent runs the git/gate reads itself" — but the tool that runs
# them (`/wrap`) never existed, so the readout was self-report from memory: a model could emit
# "✅ Complete" having read nothing. This script IS that tool: it computes the worst-open rung
# and the --full ledger from LIVE git/gate/DoD facts ONLY, so the rung reports facts.
#
# ── OUTPUT MODES ──
#   wrap-ledger.sh            → one-line human readout (the worst-open rung sentence)   [default]
#   wrap-ledger.sh --machine  → KEY=value lines for hooks (RUNG=… DIRTY=… UNLANDED=… …)
#   wrap-ledger.sh --full     → the dense SESSION LEDGER block (per CLAUDE.md §Session Close)
#
# ── RUNG (worst-open, priority ⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅) ──
#   This ledger computes the five FACT-derivable rungs {🔧, 📦, 🚀, 👤, ✅}. ⛔ (needs-a-decision) and
#   📤 (out-of-context) are model-state, NOT derivable from git — the model overlays them; when
#   present they dominate. Derivation:
#     🔧  dirty tree ∨ gate ran-but-stale-on-HEAD ∨ DoD remainder > 0   (loose ends / unverified)
#     📦  clean ∧ verified-or-n/a ∧ committed-but-unlanded (ahead>0 ∨ git-cherry '+')  (parked)
#     🚀  landed, but the LIVE LAYER (the store behaviour actually reads) is behind PAST its
#         converge budget, ∨ a migration FAILED to reach its enforcing store — landed and INERT
#     👤  ✅-eligible on the git facts, but THIS SESSION filed operator-only step(s) still unrun
#     ✅  clean ∧ not-stale ∧ landed ∧ remainder = 0 ∧ no unrun operator step from this session
#         ∧ the conclusion is observable in the enforcing store (or that question is inapplicable)
#   committed-but-unlanded is ALWAYS 📦, NEVER a silent ✅ — the FM1 park-and-call-it-done hazard.
#   A DoD file that is ABSENT is reported out loud ("no durable DoD"); a ✅-eligible git state with
#   no DoD is NOT silently upgraded to a clean ✅ (completeness is unverifiable without the DoD).
#
#   👤 (G-CS-1): ✅ claims "safe to close, nothing unsaved", and CLAUDE.md's own ✅ definition
#   already requires "no operator step this session created left unrun" — but nothing COMPUTED
#   that, so a close read ✅ while steps only the operator can run sat filed and unrun. 👤 counts
#   `cc-backlog list --blocked --json` rows whose `.session` equals the CURRENT session id, and
#   NOTHING else: the standing pile (~200 blocked items) already has a home in operator-readout's
#   counted ◆ line, and a rung that counted it would fire at every close forever — an alarm that
#   always fires carries exactly as many bits as one that cannot (MEMORY.md alarm-polarity).
#   Session id: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable. Unresolvable ⇒
#   YOURS=0 + YOURS_SRC=none and the rung stays ✅ — an unknown session NEVER manufactures a 👤.
#
#   🚀 (face 4, "✅ moves one store right"): ✅ used to terminate at TRUNK, but behaviour lives one
#   edge further out. ~/.claude is a tree of per-file SYMLINKS into the LIVE checkout
#   (~/Development/claude-infrastructure), so what this machine EXECUTES is that checkout's working
#   tree, not origin/main. A session could therefore close "✅ Complete & live on trunk" while every
#   hook, script and launchd job on the box still ran code from 91 commits ago — measured 2026-08-07
#   (deploy-live.sh header: 534 identical converger refusals, 276 launchd runs all exit 1, ZERO
#   pages). The conclusion was landed and INERT. So ✅ now asserts one more thing: that the
#   conclusion is observable in the store behaviour actually reads.
#
#   APPLICABILITY IS THE LOAD-BEARING GUARANTEE. This ledger runs in EVERY repo, and the live-layer
#   question only exists for the repo the live layer is a checkout OF. So the check applies IFF
#   $WRAP_LIVE_REPO's `origin` URL is byte-equal to THIS repo's. Different origin ⇒ LIVE_SRC=n-a
#   (positively inapplicable); unreadable/not-a-repo/no-origin ⇒ LIVE_SRC=unknown; BOTH leave the
#   rung EXACTLY as it was. Same law as YOURS_SRC=none: an unresolvable sensor never manufactures a
#   rung. A session in another repo cannot tell this code exists.
#
#   BOUNDED, by the same alarm-polarity law as 👤. The converger (deploy-live.sh --auto) runs on a
#   600s launchd tick, so a session that lands and closes within the minute ALWAYS sees live < HEAD.
#   A rung that fired there would fire at EVERY write-close and carry exactly zero bits. Only lag
#   PAST the converge budget is news: WRAP_LIVE_BUDGET_COMMITS (25) or WRAP_LIVE_BUDGET_MIN (60,
#   measured from HEAD's commit time), whichever trips FIRST — mirroring CC_DEPLOY_MAX_LAG_COMMITS /
#   CC_DEPLOY_MAX_LAG_HOURS in deploy-live.sh. Within budget the fact is ATTACHED to the ✅ readout
#   ("live layer converging") instead of spending a rung. A FAILED migration
#   ($CC_MIGRATIONS_STATE/failed/*.json — the converger reporting it could NOT put a landed
#   conclusion into settings.json / a plist / PATH) trips 🚀 immediately, with no budget: no tick
#   clears it, so it is not a timing artifact.
#
#   LADDER POSITION: 📦 and 🚀 are the two "the value is not where it needs to be" rungs, in store
#   order branch → trunk → live, so 🚀 sits directly below 📦. 👤 asks a different question (the
#   OPERATOR's queue) and ranks below both.
#
# ── LAW ── fail-LOUD, never fail-silent-open: outside a git repo (or on a read error) this exits
#   non-zero with a stderr note and NEVER prints RUNG=✅. A consumer that can't get a ledger must
#   treat that as "cannot confirm", not as "complete". Pure-read: writes nothing anywhere — which is
#   why the live-layer read never fetches (see compute_live_layer).
#
# Env seams (tests): WRAP_TRUNK · WRAP_DOD_DIR · WRAP_DOD_FILE · WRAP_GATE_GREEN ·
#                    WRAP_SESSION_ID · CC_BACKLOG_BIN · WRAP_LIVE_REPO ·
#                    WRAP_LIVE_BUDGET_COMMITS · WRAP_LIVE_BUDGET_MIN · CC_MIGRATIONS_STATE
set -uo pipefail

MODE="readout"
SESSION_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --machine) MODE="machine" ;;
    --full)    MODE="full" ;;
    --readout|"") MODE="readout" ;;
    --session) shift; SESSION_FLAG="${1:-}" ;;
    --session=*) SESSION_FLAG="${1#--session=}" ;;
    -h|--help) printf 'usage: wrap-ledger.sh [--machine|--full|--readout] [--session <sid>]\n'; exit 0 ;;
    *) printf 'wrap-ledger: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

die_notrepo() {
  printf 'wrap-ledger: not inside a git work tree (%s) — cannot compute a ledger.\n' "$PWD" >&2
  # Emit a structured, NON-✅ machine line so a consumer parsing stdout still sees "unknown".
  [ "$MODE" = "machine" ] && printf 'RUNG=?\nTRUNK=none\nERROR=not-a-git-repo\n'
  exit 3
}

command -v git >/dev/null 2>&1 || { printf 'wrap-ledger: git not found.\n' >&2; exit 3; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die_notrepo

# ── Trunk ref: explicit override → origin/HEAD → origin/main → origin/master → none ──
TRUNK="${WRAP_TRUNK:-}"
if [ -z "$TRUNK" ]; then
  # `git rev-parse --abbrev-ref origin/HEAD` PRINTS "origin/HEAD" ON STDOUT EVEN WHEN IT FAILS
  # fatally — rev-parse echoes the argument back before erroring. With `|| true` swallowing the rc,
  # TRUNK was assigned that bogus ref, and the `[ -n "$TRUNK" ]` guards below then SKIPPED the
  # origin/main and origin/master fallbacks as "already resolved". The verify on :77 blanked it
  # again, so a repo with a perfectly good origin/main reported TRUNK=none ⇒ AHEAD=0 ⇒ UNLANDED=0
  # ⇒ RUNG=✅ for work that was never landed. That is a false ✅ on parked work — the exact FM1
  # hazard this ledger exists to prevent — and it is SILENT: the output cannot distinguish "landed"
  # from "found no trunk to compare against".
  # Measured 2026-08-01: 66 of 436 clones on this machine have no refs/remotes/origin/HEAD (cloning
  # from a bare/mirror never sets it), so this was live rather than theoretical.
  # `symbolic-ref -q` is the probe that actually answers the question — it prints NOTHING on failure.
  TRUNK="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$TRUNK" ] || { git rev-parse --verify -q origin/main >/dev/null 2>&1 && TRUNK="origin/main"; }
  [ -n "$TRUNK" ] || { git rev-parse --verify -q origin/master >/dev/null 2>&1 && TRUNK="origin/master"; }
fi
git rev-parse --verify -q "$TRUNK" >/dev/null 2>&1 || TRUNK=""   # unresolvable → treat as no upstream

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"

# ── Dirty tree ──
PORC="$(git status --porcelain 2>/dev/null || true)"
DIRTY_N="$(printf '%s' "$PORC" | grep -c . 2>/dev/null || echo 0)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
DIRTY=0; [ "$DIRTY_N" -gt 0 ] && DIRTY=1

# ── Ahead / unlanded-by-content ──
AHEAD=0; CHERRY=0; SHAS=""
if [ -n "$TRUNK" ]; then
  AHEAD="$(git rev-list --count "$TRUNK"..HEAD 2>/dev/null || echo 0)"; case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
  # git cherry prints '+ <sha>' for commits whose patch is NOT present upstream (content-absent).
  if git cherry "$TRUNK" HEAD 2>/dev/null | grep -q '^+ '; then CHERRY=1; fi
  SHAS="$(git rev-list --abbrev-commit "$TRUNK"..HEAD 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/ *$//' || true)"
fi
UNLANDED=0; { [ "$AHEAD" -gt 0 ] || [ "$CHERRY" -eq 1 ]; } && UNLANDED=1

# ── Gate-green marker: green (== HEAD) · stale (present, ≠ HEAD) · none (absent) ──
GATE_FILE="${WRAP_GATE_GREEN:-$(git rev-parse --git-common-dir 2>/dev/null)/gate-green}"
GATE="none"
if [ -f "$GATE_FILE" ]; then
  GATE_SHA="$(head -1 "$GATE_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$GATE_SHA" ] && [ "$GATE_SHA" = "$HEAD_SHA" ]; then GATE="green"; else GATE="stale"; fi
fi

# ── Frozen-DoD remainder (unchecked "- [ ]" items). Absent ⇒ reported, never silently ✅. ──
DOD_FILE="${WRAP_DOD_FILE:-}"
if [ -z "$DOD_FILE" ]; then
  DOD_DIR="${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"
  TOP="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
  DHASH="$(printf '%s' "$TOP" | shasum 2>/dev/null | cut -c1-16)"
  DOD_FILE="$DOD_DIR/${DHASH:-unknown}.md"
fi
DOD="absent"; REMAINDER=0
if [ -f "$DOD_FILE" ]; then
  DOD="present"
  REMAINDER="$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[[:space:]]\]' "$DOD_FILE" 2>/dev/null || echo 0)"
  case "$REMAINDER" in ''|*[!0-9]*) REMAINDER=0 ;; esac
fi

# ── Operator-only steps THIS SESSION filed (the 👤 rung) ──
# Session id, in order: --session > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID > unresolvable ("").
SID="$SESSION_FLAG"
SID_SRC="flag"
[ -n "$SID" ] || { SID="${WRAP_SESSION_ID:-}"; SID_SRC="WRAP_SESSION_ID"; }
[ -n "$SID" ] || { SID="${CLAUDE_SESSION_ID:-}"; SID_SRC="CLAUDE_SESSION_ID"; }
[ -n "$SID" ] || SID_SRC=""

# cc-backlog resolution: env seam first (test stub), then the sibling search order.
_resolve_backlog_bin() {
  if [ -n "${CC_BACKLOG_BIN:-}" ]; then printf '%s' "$CC_BACKLOG_BIN"; return 0; fi
  local c
  for c in "$(dirname "$0")/../bin/cc-backlog" "$HOME/.claude/bin/cc-backlog" \
           "$(command -v cc-backlog 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Bound the fork: this runs from a Stop hook on every turn close, and a wedged backlog read must
# never hold the close open. No `timeout` on PATH ⇒ run unbounded rather than lose the signal.
_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# YOURS = blocked backlog items whose .session == $SID. ANY failure (no binary, non-zero exit,
# no jq, unparseable json, timeout) ⇒ YOURS=0 + YOURS_SRC=error. Fail-OPEN: a backlog we cannot
# read never blocks a close and never invents an operator step.
YOURS=0; YOURS_SRC="skip"        # skip = not computed (a worse rung already governs)
count_operator_steps() {
  if [ -z "$SID" ]; then YOURS=0; YOURS_SRC="none"; return 0; fi
  local bin json n
  bin="$(_resolve_backlog_bin)" || { YOURS=0; YOURS_SRC="error"; return 0; }
  command -v jq >/dev/null 2>&1 || { YOURS=0; YOURS_SRC="error"; return 0; }
  json="$(_bounded "${WRAP_BACKLOG_TIMEOUT_S:-5}" "$bin" list --blocked --json 2>/dev/null)" \
    || { YOURS=0; YOURS_SRC="error"; return 0; }
  n="$(printf '%s' "$json" | jq -r --arg sid "$SID" \
        '[ .[] | select((.session // "") == $sid) ] | length' 2>/dev/null)" \
    || { YOURS=0; YOURS_SRC="error"; return 0; }
  case "$n" in ''|*[!0-9]*) YOURS=0; YOURS_SRC="error"; return 0 ;; esac
  YOURS="$n"; YOURS_SRC="$SID_SRC"
}

# ── LIVE LAYER — the ENFORCING store, one edge past trunk (the 🚀 rung; see the header) ──
LIVE_REPO="${WRAP_LIVE_REPO:-$HOME/Development/claude-infrastructure}"
LIVE_BUDGET_COMMITS="${WRAP_LIVE_BUDGET_COMMITS:-25}"
LIVE_BUDGET_MIN="${WRAP_LIVE_BUDGET_MIN:-60}"
# A budget that is not a number is a budget nobody can reason about — and `[ 3 -gt "" ]` is a hard
# error thrown from inside a Stop hook. Fall back to the default (deploy-live.sh:81-82 does the same
# for the same reason), never to "unbounded".
case "$LIVE_BUDGET_COMMITS" in ''|*[!0-9]*) LIVE_BUDGET_COMMITS=25 ;; esac
case "$LIVE_BUDGET_MIN"     in ''|*[!0-9]*) LIVE_BUDGET_MIN=60 ;; esac
MIG_DIR="${CC_MIGRATIONS_STATE:-$HOME/.claude/autonomy/migrations}/failed"

# LIVE=1 iff the live layer is VERIFIED at/above HEAD. LIVE_SRC carries why: ok · behind · n-a
# (positively inapplicable) · unknown (could not read) · skip (not computed — a worse rung governs).
LIVE=0; LIVE_SRC="skip"; LIVE_SHA=""; LIVE_LAG=0; MIG_FAILED=0; LIVE_BREACH=0

# Count failed-migration records with ZERO forks — this is a Stop-hook path, and `ls | grep -c`
# spends two processes to answer what a glob already knows. An unmatched glob stays literal in
# bash 3.2 (no nullglob), so `[ -f ]` is what rejects the pattern itself.
_count_failed_migrations() {
  local d f n
  d="$1"; n=0
  [ -d "$d" ] || { printf '0'; return 0; }
  for f in "$d"/*.json; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

# Sets LIVE / LIVE_SRC / LIVE_SHA / LIVE_LAG / MIG_FAILED / LIVE_BREACH. Called ONLY on the
# ✅-eligible path with a resolved trunk (see the rung block) — a worse rung cannot be changed by it.
compute_live_layer() {
  local my_origin live_origin sha lag now ct age_s

  # `git config --get remote.origin.url` is the cheapest probe that answers "same repo?" and it
  # touches no network. It is compared BYTE-EQUAL on purpose: a fuzzy match (ssh-vs-https, .git
  # suffix) would be a second, undertested identity model whose false POSITIVE convicts an
  # unrelated repo — and the whole no-op guarantee for every other repo rests on this one compare.
  my_origin="$(git config --get remote.origin.url 2>/dev/null || true)"

  # Not a work tree (or no such path) ⇒ we could not make the read. Say `unknown`, never `n-a`:
  # n-a is a POSITIVE finding ("this repo is not the live layer's source"), and claiming it for a
  # read that never happened launders a blind spot into a clean bill of health.
  _bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { LIVE_SRC="unknown"; return 0; }

  live_origin="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" config --get remote.origin.url 2>/dev/null || true)"
  if [ -z "$my_origin" ] || [ -z "$live_origin" ]; then LIVE_SRC="unknown"; return 0; fi
  if [ "$my_origin" != "$live_origin" ]; then LIVE_SRC="n-a"; return 0; fi

  sha="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" rev-parse HEAD 2>/dev/null || true)"
  # A repo we can enter but whose HEAD we cannot resolve (unborn branch, corrupt ref) is unknown,
  # not behind — same reason as above. Ditto an unresolvable local HEAD: nothing to compare against.
  if [ -z "$sha" ] || [ -z "$HEAD_SHA" ]; then LIVE_SRC="unknown"; return 0; fi
  LIVE_SHA="$sha"

  # How far the live layer is behind its OWN trunk — the same quantity deploy-live.sh budgets on.
  # $TRUNK is reused deliberately: the applicability gate already proved the two repos share an
  # origin, so they share a trunk ref name. We deliberately do NOT fetch: this script's law is
  # pure-read, and a fetch writes objects and refs into someone else's repo. So this reads the live
  # layer's LAST-FETCHED trunk ref and can only UNDERSTATE the lag — which fails toward ✅, never
  # toward a manufactured 🚀. Keeping that ref fresh is the converger's job, not the ledger's.
  lag="$(_bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" rev-list --count "HEAD..$TRUNK" 2>/dev/null || echo 0)"
  case "$lag" in ''|*[!0-9]*) lag=0 ;; esac
  LIVE_LAG="$lag"

  # --is-ancestor, never equality: the live layer legitimately runs AHEAD of this session's HEAD
  # (it pulls trunk, and trunk moves under it), so an equality test would false-alarm on every
  # healthy box. HEAD_SHA may not exist in the live repo's object store at all — it landed after
  # that repo's last fetch — and --is-ancestor is non-zero for that too, which is exactly right: a
  # sha the live layer has never heard of is definitionally not deployed there. This branch is only
  # reached once the repo is proven READABLE above, so non-zero here means "behind", not "error".
  if _bounded "${WRAP_LIVE_TIMEOUT_S:-5}" git -C "$LIVE_REPO" merge-base --is-ancestor "$HEAD_SHA" "$LIVE_SHA" 2>/dev/null; then
    LIVE=1; LIVE_SRC="ok"
  else
    LIVE_SRC="behind"
  fi

  # A FAILED migration is the converger saying it ran and could NOT put a landed conclusion into its
  # enforcing store. Counted only INSIDE the applicability gate: the migration queue is this repo's
  # mechanism, so a session in another repo must never be convicted by it.
  MIG_FAILED="$(_count_failed_migrations "$MIG_DIR")"

  # ── the budget: whichever trips FIRST (deploy-live.sh:78-82) ──
  # %ct is the COMMITTER date, not the author date, and that is the right clock: an old patch
  # re-committed today has just entered the pipeline and deserves a fresh budget, whereas its author
  # date would start it already expired. `date +%s` can fail on a broken box ⇒ age 0 ⇒ no time trip.
  now="$(date +%s 2>/dev/null || echo 0)"
  ct="$(git log -1 --format=%ct HEAD 2>/dev/null || echo 0)"
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  case "$ct"  in ''|*[!0-9]*) ct=0 ;; esac
  age_s=0
  if [ "$now" -gt 0 ] && [ "$ct" -gt 0 ] && [ "$now" -gt "$ct" ]; then age_s=$((now - ct)); fi

  if [ "$MIG_FAILED" -gt 0 ]; then
    LIVE_BREACH=1
  elif [ "$LIVE_SRC" = "behind" ]; then
    if [ "$LIVE_LAG" -gt "$LIVE_BUDGET_COMMITS" ] || [ "$age_s" -gt "$((LIVE_BUDGET_MIN * 60))" ]; then
      LIVE_BREACH=1
    fi
  fi
  return 0
}

# ── Compute the worst-open FACT rung + its readout ──
#
# GATE IS REPORTED, NEVER THE RUNG (2026-08-03). `gate-green` is a TRUNK-WIDE marker advanced only by
# the singleton postland verifier — the land path structurally cannot move it (ship-land.sh self-noops
# and says so). So a session's own close state was being decided by a fact about the whole repo that
# no session can act on. Measured: the marker had been pinned at 34e725d6 since Jul 29 — a sha that is
# not even an ancestor of HEAD (it lives on fix/accounts-eval-bin-resolver + 4 wt-* branches, never
# main) — while postland's all-time tally is 1 green / 63 red / 2 cut / 1 hung. With everything else
# ✅-eligible (DIRTY_N=0 AHEAD=0 UNLANDED=0 REMAINDER=0) the rung still read 🔧, so RUNG=✅ — and with
# it the whole ✅ SAFE TO CLOSE certificate — was UNREACHABLE in this repo for five days. The operator
# had to ask "are we good to close?" at every single close, which is the exact defect the certificate
# was built to remove.
#
# This restores the documented contract rather than inventing one. CLAUDE.md § Session Close Protocol:
# "Where a background verifier owns the full-suite claim (claude-infrastructure v2), YOUR DIFF GREEN +
# CONTENT-VERIFIED LAND is the standard — waiting on a trunk-wide stamp you do not control is not
# diligence, it is a hang." And: a 🔧 you did not CAUSE is not your loose end — "name it in ONE line,
# surface it, and close on YOUR state."
#
# So the marker still SURFACES (GATE= is emitted below, and operator-readout appends "gate stale on
# HEAD" to a 🔧 raised by a real cause), but it no longer manufactures a 🔧 on an otherwise-clean
# close. Nothing here weakens a rung the session can actually act on: dirty tree, DoD remainder and
# unlanded commits are unchanged and still outrank ✅.
RUNG="✅"; READOUT="✅ Complete & live on trunk — nothing to do."
if [ "$DIRTY" -eq 1 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${DIRTY_N} uncommitted change(s) in the tree; continuing."
elif [ "$REMAINDER" -gt 0 ]; then
  RUNG="🔧"; READOUT="🔧 Loose ends — ${REMAINDER} frozen-DoD item(s) remain; continuing."
elif [ "$UNLANDED" -eq 1 ]; then
  RUNG="📦"; READOUT="📦 Done, but only on a branch (${AHEAD} commit(s) unlanded) — /ship to land it (else lost)."
else
  # ✅-eligible on the git facts. ONLY here do the operator-step count and the live-layer read
  # matter — on the 🔧/📦 paths neither can change the answer, so neither is ever paid for (cost
  # discipline: Stop hook, every close; both report SRC=skip there, so "not counted" stays
  # distinguishable from "counted zero"). A missing trunk means "landed" is unproven, so neither 👤
  # nor 🚀 — both of which ASSERT landed — is computed there; that case keeps its pre-existing
  # ordering below.
  if [ -n "$TRUNK" ]; then compute_live_layer; count_operator_steps; fi
  if [ "$LIVE_BREACH" -eq 1 ]; then
    # 🚀 outranks 👤: "the machine is not running this yet" is a fact about the work itself, where an
    # operator step is a fact about someone's queue.
    RUNG="🚀"
    if [ "$MIG_FAILED" -gt 0 ]; then
      READOUT="🚀 Landed but NOT live — ${MIG_FAILED} migration(s) could not reach the enforcing store; the machine is not running this yet."
    else
      READOUT="🚀 Landed but NOT live — the live layer is ${LIVE_LAG} commit(s) behind and past its converge budget; the machine is not running this yet."
    fi
  elif [ "$YOURS" -gt 0 ]; then
    # 👤 outranks the absent-DoD note: an unrun operator step is a fact, an unverifiable scope is not.
    RUNG="👤"; READOUT="👤 My side is done & landed — ${YOURS} step(s) need you; see the OPERATOR block."
  elif [ "$DOD" = "absent" ]; then
    # ✅-eligible git state, but no durable DoD to confirm the scope was met → say so, never silent ✅.
    RUNG="✅"; READOUT="✅ Clean & landed — but NO durable DoD to confirm scope (completeness unverified; frozen a DoD via ~/.claude/autonomy/dod)."
  elif [ -z "$TRUNK" ]; then
    RUNG="🔧"; READOUT="🔧 Loose ends — no upstream trunk to compare landing against; continuing."
  elif [ "$LIVE_SRC" = "behind" ]; then
    # Behind but INSIDE the converge budget — the normal, expected state for the first minutes after
    # a land. Not a rung (it would fire at every close), but not silent either: the one line says
    # the conclusion is in flight. It ranks last because an absent DoD is the less-verified fact and
    # wins the single line; this one still reaches every consumer via LIVE_SRC/LIVE_LAG below.
    RUNG="✅"; READOUT="✅ Complete & landed — live layer converging (${LIVE_LAG} commit(s) behind; within the converge budget)."
  fi
fi

emit_machine() {
  printf 'RUNG=%s\n' "$RUNG"
  printf 'READOUT=%s\n' "$READOUT"
  printf 'DIRTY=%s\n' "$DIRTY"
  printf 'DIRTY_N=%s\n' "$DIRTY_N"
  printf 'AHEAD=%s\n' "$AHEAD"
  printf 'CHERRY=%s\n' "$CHERRY"
  printf 'UNLANDED=%s\n' "$UNLANDED"
  printf 'LIVE=%s\n' "$LIVE"
  printf 'LIVE_SRC=%s\n' "$LIVE_SRC"
  printf 'LIVE_SHA=%s\n' "$LIVE_SHA"
  printf 'LIVE_LAG=%s\n' "$LIVE_LAG"
  printf 'MIG_FAILED=%s\n' "$MIG_FAILED"
  printf 'GATE=%s\n' "$GATE"
  printf 'DOD=%s\n' "$DOD"
  printf 'DOD_FILE=%s\n' "$DOD_FILE"
  printf 'REMAINDER=%s\n' "$REMAINDER"
  printf 'YOURS=%s\n' "$YOURS"
  printf 'YOURS_SRC=%s\n' "$YOURS_SRC"
  printf 'TRUNK=%s\n' "${TRUNK:-none}"
  printf 'SHAS=%s\n' "$SHAS"
}

emit_full() {
  local trunk_disp="${TRUNK:-none}"
  local gate_disp; case "$GATE" in
    green) gate_disp="✓ green on HEAD" ;;
    stale) gate_disp="✗ stale (ran on an earlier commit; re-run)" ;;
    *)     gate_disp="n/a (no gate-green marker)" ;;
  esac
  local dod_disp
  if [ "$DOD" = "present" ]; then dod_disp="present · remainder: ${REMAINDER} item(s)"
  else dod_disp="ABSENT (no durable DoD — completeness unverifiable) · expected ${DOD_FILE}"; fi
  printf 'SESSION LEDGER  (live git/gate reads · base = %s)\n' "$trunk_disp"
  printf 'Frozen DoD:     %s\n' "$dod_disp"
  printf 'Dirty tree:     %s\n' "$( [ "$DIRTY" -eq 1 ] && printf 'YES — %s file(s)' "$DIRTY_N" || printf 'no' )"
  printf 'Gate-green:     %s\n' "$gate_disp"
  printf 'Committed:      %s ahead of %s   (%s)\n' "$AHEAD" "$trunk_disp" "${SHAS:-none}"
  printf 'Unlanded(content): %s\n' "$( [ "$UNLANDED" -eq 1 ] && printf 'YES — /ship to land (else lost)' || printf 'no — landed' )"
  # The store one edge past trunk. Reported on its own row because "landed" and "running" are two
  # different claims and a ledger that conflates them is how a conclusion ships inert.
  local live_disp; case "$LIVE_SRC" in
    ok)      live_disp="at/above HEAD ($(printf '%s' "$LIVE_SHA" | cut -c1-8))" ;;
    behind)  live_disp="BEHIND — ${LIVE_LAG} commit(s), $( [ "$LIVE_BREACH" -eq 1 ] && printf 'PAST budget' || printf 'within budget (%s)' "$LIVE_BUDGET_COMMITS" )" ;;
    n-a)     live_disp="n/a (this repo is not the live layer's source)" ;;
    unknown) live_disp="unknown (live repo unreadable — not counted)" ;;
    *)       live_disp="not counted (a worse rung governs)" ;;
  esac
  [ "$MIG_FAILED" -gt 0 ] && live_disp="${live_disp} · ${MIG_FAILED} FAILED migration(s) — conclusion never reached its enforcing store"
  printf 'Live layer:     %s\n' "$live_disp"
  local yours_disp; case "$YOURS_SRC" in
    none)  yours_disp="unknown — session id unresolvable (not counted)" ;;
    error) yours_disp="unknown — backlog unreadable (not counted)" ;;
    skip)  yours_disp="not counted (a worse rung governs)" ;;
    *)     yours_disp="$( [ "$YOURS" -gt 0 ] && printf '%s operator-only step(s) filed this session, UNRUN — see the OPERATOR block' "$YOURS" || printf 'none filed this session' )" ;;
  esac
  printf 'Yours (operator): %s\n' "$yours_disp"
  printf 'Rung:           %s\n' "$RUNG"
  printf 'Next:           %s\n' "$(rung_next)"
}

rung_next() {
  case "$RUNG" in
    "🔧") printf 'continue → finish · run-gate · commit (explicit paths)' ;;
    "📦") printf '/ship to land (verified net-positive work is drivable — not a hold)' ;;
    "🚀") printf 'bash scripts/deploy-live.sh — the converger is behind its budget; the conclusion is landed but inert' ;;
    "👤") printf 'surface the OPERATOR block — %s step(s) are the operator'"'"'s (my side is done)' "$YOURS" ;;
    "✅") printf 'complete — nothing to do' ;;
    *)    printf 'model-state (⛔/📤) overrides — surface it' ;;
  esac
}

case "$MODE" in
  machine) emit_machine ;;
  full)    emit_full ;;
  *)       printf '%s\n' "$READOUT" ;;
esac
exit 0
