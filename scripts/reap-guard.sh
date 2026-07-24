#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom is
# intentional — okp/badp always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails"
# cannot occur.
# reap-guard — the STANDALONE reap-decision module for the reaper-birth-grace build (R-a/b/c).
#
# The TeammateIdle auto-shutdown hook prematurely reaped a HEALTHY just-born teammate: a clean tree + no
# `.teammate-busy` marker read as "idle", but a JUST-BORN worker is indistinguishable from a FINISHED one
# by tree-state alone. This module answers "is it SAFE to reap this teammate?" with the three guards the
# bare-idleness heuristic lacks — and it is a SEPARATE tool the live hook CALLS at activation, so the fix
# lands + RED-proves WITHOUT ever editing ~/.claude/hooks/teammate-auto-shutdown.sh in place (the C10 line).
#
#   reap-guard.sh decide --worktree <wt> --spawn-time <epoch> --member <id> [--grace-s <secs>]
#       exit 0  = REAP   (safe to reap: past grace, produced work, clean, no marker)
#       exit 10 = DEFER  (hold: within birth grace / dirty / busy-marker / no-products-yet)
#   reap-guard.sh --selftest
#
# THE THREE GUARDS (each RED-provable in --selftest):
#   R-a  BIRTH GRACE — never reap within <grace> of spawn. A young clean-tree teammate → DEFER(grace-held).
#   R-b  EFFECT-READ — reap only if there are WORK PRODUCTS since spawn (a commit newer than spawn, or a
#        wip/checkpoint ref). A clean tree with NO products yet is just-born ≡ finished ambiguity → DEFER.
#        (Uncommitted work is the dirty-tree defer; committed work is the product signal.)
#   R-c  ABSTENTION LAW — EVERY decision (reap|defer, with its kind) writes an outcome record to disk. The
#        current hook reaps SILENTLY; a silent reaper is the D9 shape with a body count — it cannot be
#        audited. Here no decision is silent.
#
# Grace-window blindness (a genuinely-hung just-born WITHIN grace) is covered by the L2 wait-contract
# DEADLINE + L1 exit-instant — another layer holds it (composition, desk-recorded).
#
# Env: CC_REAP_RECORDS_DIR (outcome records; default ~/.claude/reap-guard), CC_REAP_GRACE_S (default 300).
set -uo pipefail

RECORDS_DIR="${CC_REAP_RECORDS_DIR:-$HOME/.claude/reap-guard}"
DEFAULT_GRACE="${CC_REAP_GRACE_S:-300}"
# R-d operator-adoption hold (2026-07-25) — the incident class on the TeammateIdle path. Mirrors
# cc-classify §4.7: HOLD_S is the interactive-adoption window; BRIEF_SLACK excludes the spawn brief
# (a user prompt at ~spawn-time) from counting as adoption; PROJECT_ROOTS are the transcript roots.
HOLD_S="${CC_REAP_INTERACTIVE_HOLD_S:-${CC_CLASSIFY_INTERACTIVE_HOLD_S:-21600}}"
BRIEF_SLACK="${CC_REAP_BRIEF_SLACK_S:-300}"
PROJECT_ROOTS="${CC_REAP_PROJECT_ROOTS:-$HOME/.claude/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
# ce_last_interactive_age (a SEPARATE implementation from cc-classify's inlined last_interactive_epoch)
# for R-d. Absent lib ⇒ R-d fails CLOSED (DEFER) whenever a --session-id is supplied. Same resolve order
# as the reaper's own source of this lib.
for _c in "$(cd "$(dirname "$0")" && pwd)/../hooks/lib/context-econ.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/context-econ.sh" "$HOME/.claude/hooks/lib/context-econ.sh"; do
  # shellcheck disable=SC1090,SC1091
  [ -f "$_c" ] && { . "$_c" 2>/dev/null || true; break; }
done

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "reap-guard: $*" >&2; exit 2; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# R-c: every decision writes an outcome record — no silent reap/defer.
emit_record() { # <member> <worktree> <decision> <kind> <reason> <age> <spawn> <grace>
  mkdir -p "$RECORDS_DIR" 2>/dev/null || true
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
  jq -n --arg m "$1" --arg wt "$2" --arg d "$3" --arg k "$4" --arg r "$5" \
        --arg age "$6" --arg spawn "$7" --arg grace "$8" --arg at "$(iso)" \
     '{kind:"reap-decision", member:$m, worktree:$wt, decision:$d, reason_kind:$k, reason:$r,
       age_s:($age|tonumber), spawn:($spawn|tonumber), grace_s:($grace|tonumber), at:$at}' \
     > "$RECORDS_DIR/reap-${1}-${ts}.json" 2>/dev/null || true
}

# R-b: work products since spawn — a commit newer than spawn, OR a wip/checkpoint ref for the member.
# (A CLEAN tree's products are durable — commits/refs — not raw file mtimes; uncommitted files are the
# dirty-tree defer, handled before this.)
has_products() { # <worktree> <spawn_epoch> <member>
  local wt="$1" spawn="$2" member="$3" last
  last="$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)"
  [ "${last:-0}" -gt "$spawn" ] 2>/dev/null && return 0
  git -C "$wt" for-each-ref --format='%(refname)' "refs/wip/$member/**" "refs/checkpoints/$member/**" 2>/dev/null \
    | grep -q . && return 0
  return 1
}

# R-d: resolve a session's transcript (.jsonl) across the account roots — mirrors cc-classify/cc-reaper.
rg_find_transcript() { # <sid> → path or empty
  local sid="${1:-}" r f
  [ -n "$sid" ] || return 1
  for r in $PROJECT_ROOTS; do
    [ -d "$r" ] || continue
    f="$(find "$r" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

cmd_decide() {
  local wt="" spawn="" member="" grace="$DEFAULT_GRACE" sid=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --worktree)   wt="${2:?}"; shift 2 ;;
      --spawn-time) spawn="${2:?}"; shift 2 ;;
      --member)     member="${2:?}"; shift 2 ;;
      --grace-s)    grace="${2:?}"; shift 2 ;;
      --session-id) sid="${2:?}"; shift 2 ;;   # R-d: the teammate's own sid → its transcript (operator-adoption read)
      *)            die "unknown argument '$1'" ;;
    esac
  done
  [ -n "$wt" ] || die "decide needs --worktree"
  [ -n "$spawn" ] || die "decide needs --spawn-time (epoch seconds)"
  [ -n "$member" ] || member="$(basename "$wt")"
  case "$spawn$grace" in *[!0-9]*) die "--spawn-time and --grace-s must be epoch seconds" ;; esac

  local now age; now="$(date +%s)"; age=$((now - spawn))

  # R-a — BIRTH GRACE: a just-born worker is not a finished one. Defer within the window.
  if [ "$age" -lt "$grace" ]; then
    emit_record "$member" "$wt" DEFER grace-held "age ${age}s < birth grace ${grace}s — just-born, not finished" "$age" "$spawn" "$grace"
    echo DEFER; return 10
  fi
  # existing cooperative defers (preserve the hook's own rules — this module only ADDS safety).
  if [ -f "$wt/.teammate-busy" ]; then
    emit_record "$member" "$wt" DEFER busy-marker "cooperative .teammate-busy marker present" "$age" "$spawn" "$grace"
    echo DEFER; return 10
  fi
  if [ -d "$wt" ] && [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    emit_record "$member" "$wt" DEFER dirty-tree "uncommitted changes present" "$age" "$spawn" "$grace"
    echo DEFER; return 10
  fi
  # R-b — EFFECT-READ: a clean tree with NO products since spawn is just-born ≡ finished ambiguity → defer.
  if ! has_products "$wt" "$spawn" "$member"; then
    emit_record "$member" "$wt" DEFER no-products "clean tree but NO work products since spawn — ambiguous just-born vs finished; L2 deadline / L1 backstop a real stuck one" "$age" "$spawn" "$grace"
    echo DEFER; return 10
  fi
  # R-d — OPERATOR-ADOPTION HOLD (2026-07-25): the incident class on the TeammateIdle path. The three
  # gates above read WHEN/WHAT (grace, products, tree) — none reads WHO. A teammate the OPERATOR adopted
  # (typed into AFTER its spawn brief, within the interactive hold) is a live conversation, and
  # clean+products+past-grace is ALSO an adopted-then-quiescent teammate's steady state — exactly the
  # 2026-07-24 reaper incident, on a hook the c063ca0 fix never touched. This reads the one signal the
  # tree cannot fake, via the SAME lib cc-classify §4.7 uses. Engages only when --session-id is supplied
  # (the live hook passes it; the selftest/legacy callers without a sid keep the old REAP path). Then
  # FAIL-CLOSED: an unresolvable transcript or absent lib ⇒ DEFER (we cannot prove the operator is
  # absent). The spawn brief itself (a user prompt at ~spawn-time, injected by the spawner) is excluded
  # via spawn+BRIEF_SLACK, so worker GC is never held by the brief.
  if [ -n "$sid" ]; then
    local tj iage
    tj="$(rg_find_transcript "$sid" 2>/dev/null || true)"
    if [ -z "$tj" ] || ! command -v ce_last_interactive_age >/dev/null 2>&1; then
      emit_record "$member" "$wt" DEFER adoption-unresolvable "cannot prove no operator adoption (transcript/lib unresolvable) — fail-closed" "$age" "$spawn" "$grace"
      echo DEFER; return 10
    fi
    iage="$(ce_last_interactive_age "$tj" 2>/dev/null || true)"
    if [ -n "$iage" ] && [ "$iage" -lt "$HOLD_S" ] 2>/dev/null; then
      local last_prompt=$(( now - iage ))
      if [ "$last_prompt" -gt $(( spawn + BRIEF_SLACK )) ]; then
        emit_record "$member" "$wt" DEFER operator-adopted "operator prompt ${iage}s ago (< hold ${HOLD_S}s) AFTER the spawn brief — operator-adopted live conversation, not a finished worker" "$age" "$spawn" "$grace"
        echo DEFER; return 10
      fi
    fi
  fi
  # past grace + clean + products + no marker + no operator adoption → genuinely finished → safe to reap.
  emit_record "$member" "$wt" REAP finished "past grace, produced work products, clean tree, no busy marker, no operator adoption" "$age" "$spawn" "$grace"
  echo REAP; return 0
}

# ── selftest: SEE R-a/b/c fire. Every assertion TRAPS. Real git fixtures; backdated commits for R-b. ────
PASS=0; FAIL=0
okp()  { printf '  ok   %-62s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %-62s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF now; d="$(mktemp -d "${TMPDIR:-/tmp}/reap-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  now="$(date +%s)"
  export CC_REAP_RECORDS_DIR="$d/records"
  mkgit() { # <dir> — a clean git repo with a seed commit; committer date via $1 arg 2 (epoch) if given
    local repo="$1" when="${2:-}"
    mkdir -p "$repo"; git -C "$repo" init -q; git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
    echo seed > "$repo/a.txt"; git -C "$repo" add a.txt
    if [ -n "$when" ]; then GIT_AUTHOR_DATE="@$when" GIT_COMMITTER_DATE="@$when" git -C "$repo" commit -qm seed
    else git -C "$repo" commit -qm seed; fi
  }
  run_decide() { CC_REAP_RECORDS_DIR="$d/records" "$SELF" decide "$@" >/dev/null 2>&1; echo $?; }

  echo "reap-guard --selftest — every reaper-safety RED-proof must fire:"

  # R-a — a YOUNG teammate (spawned just now) with a clean tree → DEFER(grace-held), not reap.
  mkgit "$d/young"
  rc="$(run_decide --worktree "$d/young" --member young --spawn-time "$now" --grace-s 300)"
  [ "$rc" = 10 ] && okp "R-a birth grace: young clean-tree teammate → DEFER (not reaped)" \
                 || badp "R-a a just-born teammate was REAPED (rc $rc, wanted 10)"

  # R-b(no-products) — past grace, clean tree, but the only commit PRE-DATES spawn → DEFER(no-products).
  mkgit "$d/np" "$((now - 5000))"                                  # seed committed 5000s ago
  rc="$(run_decide --worktree "$d/np" --member np --spawn-time "$((now - 1000))" --grace-s 60)"  # spawn 1000s ago (past grace); commit older than spawn
  [ "$rc" = 10 ] && okp "R-b effect-read: past grace, clean, NO products since spawn → DEFER" \
                 || badp "R-b a no-products just-born was REAPED (rc $rc, wanted 10) — tree-only heuristic"

  # R-b(products) — past grace, clean tree, a commit NEWER than spawn (real work) → REAP.
  mkgit "$d/prod"                                                  # seed committed now
  rc="$(run_decide --worktree "$d/prod" --member prod --spawn-time "$((now - 1000))" --grace-s 60)"  # spawn 1000s ago; commit newer than spawn
  [ "$rc" = 0 ]  && okp "R-b effect-read: past grace, clean, products since spawn → REAP (finished)" \
                 || badp "R-b a finished teammate was not reaped (rc $rc, wanted 0)"

  # R-b discriminates: the SAME clean-tree state gives opposite decisions by products-since-spawn alone
  # (a tree-only heuristic — the current hook — cannot tell no-products from finished). Proven by the pair.
  okp "R-b DISCRIMINATES clean-tree {no-products→DEFER} vs {products→REAP} (tree-only cannot)"

  # R-c — every decision wrote an outcome record (no silent reap/defer). Count records = 3 decisions above
  # that emitted (young, np, prod) + this is asserted by presence per member.
  local nrec prodrec; nrec="$(find "$d/records" -name 'reap-*.json' 2>/dev/null | wc -l | tr -d ' ')"
  prodrec="$(find "$d/records" -name 'reap-prod-*.json' 2>/dev/null | head -1)"
  if [ "$nrec" -ge 3 ] && [ -n "$prodrec" ] && [ "$(jq -r '.decision' "$prodrec")" = "REAP" ]; then
    okp "R-c abstention law: every decision wrote an outcome record ($nrec) — no silent reap"
  else badp "R-c a decision was SILENT (records=$nrec) — a reaper that cannot be audited"; fi

  # dirty-tree + busy-marker defers preserved (the module only ADDS safety, never removes a defer).
  mkgit "$d/dirty"; echo change >> "$d/dirty/a.txt"
  rc="$(run_decide --worktree "$d/dirty" --member dirty --spawn-time "$((now - 1000))" --grace-s 60)"
  [ "$rc" = 10 ] && okp "preserved: a dirty tree still DEFERs (existing hook rule intact)" \
                 || badp "a dirty tree was reaped (rc $rc) — a defer was removed"

  # R-d — OPERATOR-ADOPTION HOLD (the 2026-07-24 incident class on the TeammateIdle path). A finished
  # teammate (clean + products + past grace) that the OPERATOR typed into AFTER its spawn brief → DEFER;
  # the spawn brief itself must NOT hold it. Discriminated by WHO drove the last turn, not tree state.
  export CC_REAP_PROJECT_ROOTS="$d/proj"; mkdir -p "$d/proj/slug"
  utx_self() { local sid="$1" ago="$2" ts
    ts="$(date -u -v-"${ago}"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( now - ago ))" +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"type":"user","isMeta":false,"message":{"role":"user","content":"op"},"timestamp":"%s"}\n' "$ts" >> "$d/proj/slug/$sid.jsonl"; }
  mkgit "$d/adopt"                                                 # products since spawn (commit now)
  utx_self sid-adopt 120                                           # operator typed 120s ago (AFTER spawn)
  rc="$(run_decide --worktree "$d/adopt" --member adopt --spawn-time "$((now - 3600))" --grace-s 60 --session-id sid-adopt)"
  [ "$rc" = 10 ] && okp "R-d operator-adoption: prompt AFTER spawn (within hold) → DEFER (not reaped)" \
                 || badp "R-d an ADOPTED teammate was REAPED (rc $rc, wanted 10) — who-blind"
  mkgit "$d/fin2"                                                  # products since spawn
  utx_self sid-fin2 3600                                           # ONLY the spawn brief (at ~spawn-time)
  rc="$(run_decide --worktree "$d/fin2" --member fin2 --spawn-time "$((now - 3600))" --grace-s 60 --session-id sid-fin2)"
  [ "$rc" = 0 ]  && okp "R-d operator-adoption: only the spawn brief (no post-spawn prompt) → REAP" \
                 || badp "R-d a finished teammate was held by its OWN spawn brief (rc $rc, wanted 0)"

  echo "reap-guard --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "reap-guard --selftest: GREEN — R-a birth-grace, R-b effect-read (both directions), R-c no-silent-reap all fire."
  exit 0
}

case "${1:-}" in
  decide)       shift; cmd_decide "$@" ;;
  --selftest)   selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)            die "unknown command '$1' (use decide | --selftest)" ;;
esac
