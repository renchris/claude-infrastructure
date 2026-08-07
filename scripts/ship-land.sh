#!/usr/bin/env bash
# ship-land.sh — the ENTIRE claude-infrastructure landing pipeline as ONE fail-closed script
# (was prose in .claude/commands/ship.md a model could skip or paraphrase).
#
#   scripts/ship-land.sh [--trunk <branch>] [--dry-run]
#
# v2 — THE INVERSION (docs/plans/LAND_PIPELINE_V2.md §1/§4.1). The full corpus NEVER runs
# per-land. v1 proved the whole suite before every push; measured, that frame cannot work on
# this box — 144 suites × ~43 lands/day × 12+ concurrent writers, no quiet window by
# construction, P(gate green) ≈ 2.3% at n=126 — and EVERY mitigation fed the contention it
# guarded (unlocked parallel gates ⇒ N concurrent corpora; admission sleeping ⇒ ~2h/run and
# five gates starving below their own load ceiling; the in-lock fallback ⇒ a 3h36m lock holder
# and a multi-day jam). So the verdict MOVED: a LAND carries only work that is O(diff) and
# bounded by WALL-CLOCK, never by load; the FULL suite runs once, post-land, batched, in the
# background band, by the singleton verifier (postland-verify.sh), which owns the gate-green
# marker and auto-reverts a red trunk; and DEPLOY — not land — waits for the green verdict.
#
# Pipeline (fail-closed at every step):
#   preflight (OUTSIDE lock): shared-checkout refusal · dirty-tree refusal · escalation-scan
#     (destructive SQL / credentials ⇒ PARK a decision packet, exit 3, never auto-land) ·
#     safety backup ref
#   → optimistic rounds, up to SHIP_LAND_GATE_ROUNDS (default 3), each:
#       UNLOCKED: fetch → rebase (conflict ⇒ exit 5) → GATE on the rebased tree, which is ONLY:
#       lint (shellcheck, `bash -n`, py_compile) on CHANGED files (extensionless by shebang too) ·
#       test-hermeticity ratchet · wall-clock time-bomb ratchet · SMOKE (below). Red ⇒ exit 6.
#       Record (GATE_BASE = origin/<trunk>, GATE_HEAD = HEAD) — the exact tree gated.
#       --dry-run stops here (a dry run never takes the lock).
#       → land-lock'd child (serialized machine-wide per repo via land-lock.sh): last-moment
#         fetch → CAS: origin/<trunk> still == GATE_BASE AND HEAD still == GATE_HEAD? NO ⇒
#         release the lock, exit 42 (INTERNAL stale-gate signal) and the outer loop re-rebases
#         + re-gates UNLOCKED (statics+smoke — seconds, not a second corpus). YES ⇒ the gated
#         tree IS the pushed tree → `git push HEAD:<trunk>` (non-ff ⇒ exit 7) → land-verify.sh
#         (content-verify, IN the lock, after the push) → on a content-drop, BOUNDED AUTO-RETRY
#         + ROLLBACK (T-P9-7) up to SHIP_LAND_VERIFY_RETRIES times; a retry rebase-conflict
#         rolls back (rebase --abort) ⇒ exit 5, retries exhausted ⇒ clean tree + exit 8 →
#         stranded-sweep (exit 1 ⇒ REVIEW, surfaced, never auto-recovered) → self-attesting
#         land.log line.
#   → rounds exhausted (sustained contention): in-lock re-gate of STATICS ONLY. NOTHING HEAVY
#     MAY EVER ENTER THE LOCK, in EITHER lane — the lock covers the race window (a 5-15s hold),
#     never a proof. SHIP_LAND_GATE_ROUNDS=0 goes straight there. Both in-lock gate call sites
#     (this fallback and the content-drop recovery re-gate) are covered structurally: run_gate
#     refuses to start any suite while IN_LAND_LOCK=1, so the ban cannot be forgotten at a call site.
#
# THE OPTIMISTIC ROUNDS SURVIVE v2, but only because a re-gate now costs SECONDS. Their v1
# economics were indefensible on the measurements: 26.4h of accumulated lock-WAIT bought 79s of
# actual work, and ~30% of rounds were invalidated by a sibling landing mid-gate — each
# invalidation paying for a whole second corpus, unlocked but still 20-53 min of machine. The
# rounds were never a throughput trick; they exist so the LOCK covers only the CAS race window.
# With statics+smoke behind them a stale-gate re-round is seconds, so that 30% re-round rate stops
# being the dominant cost and becomes a rounding error. Keep the rounds; they are now cheap.
#
# SMOKE — the land's only test work, and the highest-value seconds in the pipeline. The
# `gate-select.sh --direct` suites of THIS diff MINUS the HOST suites named in
# scripts/host-suites.manifest (§4.2.2 — those assert the LIVE layer and are owned by the
# post-deploy check; letting one back in through the smoke rebuilds the bootstrap circle one lane
# over), one process per suite, under ONE TOTAL wall budget SHIP_LAND_SMOKE_BUDGET_S (default
# 120s), `nice`d, each child bounded by `timeout -k 10` against the shared deadline. Three rules,
# each paying for a named v1 failure:
#   RED BLOCKS (exit 6)  a named `not ok` in a direct suite is a verdict about YOUR diff.
#   CUT PROCEEDS         a cut / budget kill earned NO verdict, and a non-verdict must never
#                        block a land (R6): recorded to flakes.jsonl, attested smoke:"partial",
#                        the verifier decides. Smoke therefore NEVER yields exit 9.
#   SHED = SKIP          at 1-min load ≥ CC_GATE_MAX_LOAD (default 8) the smoke is SKIPPED
#                        ENTIRELY, never waited (R7). Waiting WAS the amplifier; shedding defers
#                        to the net, never to a queue. Fail-OPEN: an unreadable sensor runs the
#                        (bounded) smoke rather than inventing a skip.
#
# A land makes NO full-suite claim: GATE_EFFECTIVE_FULL is 0 always — in BOTH lanes — so
# stamp_gate_green self-noops and gate-green advances ONLY via the verifier (§4.2). Two writers
# for one marker is strictly worse than a stale one.
#
# --dry-run stops after the gate (no push, no lock). Exit codes: 0 landed · 2 preflight refusal ·
# 3 escalation PARK · 4 shared-checkout refusal · 5 rebase conflict (initial OR an auto-retry
# rebase, the latter rolled back) · 6 GATE RED · 7 push non-ff · 8 content-verify failed after
# exhausting the bounded auto-retries · 9 GATE-KILLED (now rare — only LANE=v1's corpus can earn
# it). 42 is INTERNAL (locked child → outer-loop stale-gate signal); it never escapes ship-land.
#
# 6 vs 9 — a VERDICT vs a NON-VERDICT, and the distinction is load-bearing (backlog 9c5d0ba74e79):
# 6 says "the gate ran and this tree is red" — a claim about YOUR CODE, actionable, do not retry
# unchanged. 9 says the suite died to a signal (or exited naming no failing test) and therefore
# proved NOTHING — a claim about the MACHINE. Nothing is pushed either way and gate-green is never
# advanced, so 9 is still fail-closed; what changes is that a retry is the CORRECT response to 9
# and the wrong one to 6. Collapsing them into 6 is what let a load spike read as a code failure
# and drove the 2026-07-26 kill → "RED" → re-block → dispatcher-retry runaway (f8e40b4c577d).
#
# TRAILER CONVENTION (ownership-decidable sweep, T-P9-4): a session's commits should
# carry a `Session-Id: <CLAUDE_CODE_SESSION_ID>` trailer so `stranded-sweep.sh --mine
# <sid>` can recover only own-drops. ship-land stamps land.log with the sid (a
# post-hoc commit trailer is impossible), and adds the trailer to any commit IT makes.
#
# land.log schema (growth is safe — its only reader is a raw tail): `gate_scope` now carries the
# LANE ("fast"|"v1"), plus smoke:"green|red|partial|skipped|none", smoke_n, smoke_s, and
# net:"live|inert|none". The verifier's liveness is ATTESTED, never a control-flow input: a land
# that cannot see a live net WARNS and lands anyway — degrading to a corpus is precisely the
# fail-closed-amplifier class v2 exists to delete (R7).
#
# UNION SCOPE survives: a stale-gate re-round hands the selector a SECOND range
# (FIRST_BASE..new base) so the smoke covers what siblings landed while we gated — the composed
# tree's only novelty. The two ratchets sit OUTSIDE selection on purpose (a new tests/*.bats maps
# to itself, never to the ratchet) and run on every land in every lane; see run_gate.
#
# KILL SWITCH: SHIP_LAND_LANE=v1 restores the v1 full-corpus gate for one release (default
# `fast`) — except the never-in-lock invariant, which binds in both. SHIP_LAND_GATE_SCOPE is
# still parsed for back-compat but decides nothing in the fast lane.
#
# Env overrides (mostly for tests): SHIP_LAND_LANE · SHIP_LAND_SMOKE_BUDGET_S ·
# SHIP_LAND_SMOKE_NICE · SHIP_LAND_TIMEOUT_BIN (set-but-EMPTY ⇒ unbounded children) ·
# CC_GATE_MAX_LOAD (0|off ⇒ never shed) · SHIP_LAND_SHARED_CHECKOUT · SHIP_LAND_SESSION_BRANCH_RE
# · SHIP_LAND_ALLOW_SHARED=1 · SHIP_LAND_ESC_RE (EFFECT class — exemptible) ·
# SHIP_LAND_ESC_RE_SECRET (DISCLOSURE class — never exemptible) · SHIP_LAND_ESC_EXEMPT_FILE
# (default scripts/esc-exempt.manifest) · SHIP_LAND_DECISIONS_DIR · LAND_LOG ·
# LAND_LOCK_DIR (see land-lock.sh) · SHIP_LAND_VERIFY_RETRIES (default 2; 0 = single-shot,
# the pre-T-P9-7 kill switch) · SHIP_LAND_GATE_ROUNDS (default 3; 0 = straight to the in-lock
# statics re-gate) · SHIP_LAND_GATE_SCOPE / SHIP_LAND_GATE_POLICY / SHIP_LAND_GATE_SELECT ·
# SHIP_LAND_HERM_LINT · SHIP_LAND_WALL_LINT (ratchet paths; default the landing tree's own) ·
# SHIP_LAND_HOST_MANIFEST (host-suite partition; default the landing tree's own, §4.2.2) ·
# SHIP_LAND_GATE_HOME_ISO · POSTLAND_DIR (flake + post-land queue + stamps dir) ·
# POSTLAND_VERIFY=off (skip the post-land spawn) · POSTLAND_STALENESS_GUARD=off ·
# POSTLAND_MAX_STAMP_AGE_H (24).
#
# bash 3.2-safe (no declare -A / mapfile; empty-array expansion guarded under `set -u`).
# `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

# SELF/SCRIPT_DIR resolve THROUGH symlinks — load-bearing, not hygiene. ~/.claude/scripts/ is a
# REAL directory of PER-FILE symlinks into the checkout, so an unresolved `dirname "$0"` made a
# LIVE-PATH land look for its siblings in ~/.claude/scripts/ — where a BRAND-NEW tracked file has
# no symlink yet (the deploy ff-sync does not create them; backlog d83b624354af / 761a546f939c).
# gate-select.sh + gate-policy.sh were exactly that: landed on origin/main, unlinked live. So a
# live-path land silently lost BOTH the scoped default (policy unsourced ⇒ `full`) and the
# selector ⇒ the "missing/not executable — treating as FULL (fail-closed)" branch below, running
# the whole ~1630-test suite on EVERY land, unserialized across every landing worktree. That is
# the amplifier in the 2026-07-26 machine-wide gate runaway (backlog f8e40b4c577d), and it is why
# the degradation looked INTERMITTENT: `./scripts/ship-land.sh` from a worktree found its sibling
# and went scoped; the same land via the live symlink went FULL. Same bug family as
# deploy-parity-assert.sh (816015ecb30b). macOS `readlink` has no -f on older bases ⇒ manual loop.
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [[ -L "$p" ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR="$(dirname "$SELF")"
LAND_LOCK="${SCRIPT_DIR}/land-lock.sh"
LAND_VERIFY="${SCRIPT_DIR}/land-verify.sh"
BACKUP_REAP="${SCRIPT_DIR}/ship-backup-reap.sh"
STRANDED_SWEEP="${SCRIPT_DIR}/stranded-sweep.sh"
GATE_MANIFEST="${SCRIPT_DIR}/gate-manifest.sh"
GATE_SELECT="${SHIP_LAND_GATE_SELECT:-${SCRIPT_DIR}/gate-select.sh}"

# ---- LANE: which gate this land runs (v2 default `fast`; `v1` is the kill switch) ----------
# The lane is the ONE switch that decides whether a corpus can enter a land at all. Default
# `fast` = statics + ratchets + bounded direct-suite smoke. `v1` restores the pre-inversion
# full-corpus gate for one release — an ENV switch, not a revert, because a revert would itself
# need the gate (the bootstrap deadlock this plan exists to escape).
LANE="${SHIP_LAND_LANE:-fast}"
case "$LANE" in
  fast|v1) ;;
  *) echo "✗ ship-land: unknown SHIP_LAND_LANE '$LANE' (want fast|v1)" >&2; exit 2 ;;
esac

# ---- gate scope (committed policy file; env always wins) --------------------
# BACK-COMPAT ONLY in v2, and deliberately INERT: the scope machinery chose between
# full/scoped/shadow CORPUS runs, and neither lane consults it any more — the fast lane runs no
# corpus at all, and LANE=v1 runs the WHOLE corpus regardless of the value (a scoped v1 land would
# be a third semantic to keep alive for a kill switch that exists for one release). It is still
# read and still VALIDATED so an operator's committed policy file or existing env cannot turn a
# land into a hard exit-2 on an unrelated flag, and so the value stays legible to anything that
# greps it. Hardcoded `full` fallback preserved for the same reason: it never narrows.
GATE_POLICY="${SHIP_LAND_GATE_POLICY:-${SCRIPT_DIR}/gate-policy.sh}"
# shellcheck source=/dev/null
[[ -r "$GATE_POLICY" ]] && . "$GATE_POLICY"
SCOPE="${SHIP_LAND_GATE_SCOPE:-${SHIP_LAND_GATE_SCOPE_DEFAULT:-full}}"
case "$SCOPE" in
  full|scoped|shadow) ;;
  *) echo "✗ ship-land: unknown SHIP_LAND_GATE_SCOPE '$SCOPE' (want full|scoped|shadow)" >&2; exit 2 ;;
esac
# What the gate ACTUALLY did. Seeded from the env because the locked phase is a separate
# process (re-exec'd under land-lock) that, in CAS mode, does not re-run the gate — without the
# handoff its land.log line would understate the run as n/a. INTERNAL vars, not a UI.
# GATE_EFFECTIVE_FULL is 0 by construction in v2 (a land makes no full-suite claim, in EITHER
# lane) — it survives only so stamp_gate_green keeps ONE place that decides, and so a v1-era
# env handoff cannot resurrect the claim.
GATE_EFFECTIVE_FULL=0
SELECTED_N="${SHIP_LAND_SELECTED_N:--1}"                   # suites the gate RAN (-1 = n/a)
ATTEST_HEAD="?"; ATTEST_BASE="?"; ATTEST_TREE="?"
# UNION SCOPE: on a stale-gate re-round the composed tree's ONLY novelty is what siblings landed
# while we gated, so the selector is given that trunk delta as a SECOND range. FIRST_BASE anchors
# it (the base our first gate ran against); seeded from the env for the in-lock fallback child.
FIRST_BASE="${SHIP_LAND_FIRST_BASE:-}"
EXTRA_RANGE=""
# GATE VERDICT vs NON-VERDICT (backlog 9c5d0ba74e79 / f8e40b4c577d). run_gate returns 1 for BOTH
# "the tree is red" and "the run died without earning a verdict"; these two flags separate them so
# the exit code can. GATE_RED wins a mixed run — a named failure is strictly more informative than
# a kill, and must never be softened into a retryable non-verdict.
GATE_RED=0        # ≥1 check produced a REAL verdict and it was red
GATE_KILLED=0     # ≥1 bats run died to a signal / produced no attributable failure

# ---- SMOKE + NET state (attested, seeded across the locked re-exec like SELECTED_N) ---------
SMOKE_STATE="${SHIP_LAND_SMOKE_STATE:-none}"   # green | red | partial | skipped | none
SMOKE_N="${SHIP_LAND_SMOKE_N:-0}"              # direct suites the smoke actually RAN
SMOKE_S="${SHIP_LAND_SMOKE_S:-0}"              # wall seconds the smoke spent
NET_STATE="${SHIP_LAND_NET_STATE:-none}"       # live | inert | none — ATTESTED, never enforced
SMOKE_DEADLINE=""                              # non-empty ⇒ gate_bats bounds every child by it

# ---- bounding every child of the smoke -------------------------------------
# R5: every step bounded by an ABSOLUTE-PATH timeout(1), and the bound must cover the failure mode
# it bounds. PATH alone is not enough — a land can run under launchd (no Homebrew on PATH), which
# is exactly where coreutils installs timeout(1). Same resolution ladder as postland-verify.sh /
# bin/it2-wrapper. `-k 10` + no `--foreground` ⇒ its own process group ⇒ the whole bats tree dies,
# not just the wrapper (the unbounded-fork class that hung gates for five days).
_resolve_timeout() {
  local c
  for c in "$(command -v timeout 2>/dev/null || true)" \
           "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout \
           /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [[ -n "$c" && -x "$c" ]]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
# UNSET ⇒ resolve one. SET (including set to EMPTY) ⇒ honored verbatim, so SHIP_LAND_TIMEOUT_BIN=
# genuinely disables bounding — `${VAR:-}` cannot tell unset from set-empty, and a seam that cannot
# turn a thing OFF is not a seam. No timeout(1) anywhere ⇒ children run UNBOUNDED (the budget then
# only bites between suites); never a refusal to land.
if [[ -n "${SHIP_LAND_TIMEOUT_BIN+set}" ]]; then TIMEOUT_BIN="$SHIP_LAND_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_timeout || true)"; fi
NICE_BIN="$(command -v nice 2>/dev/null || true)"

# ---- the escalation surface, as TWO classes ---------------------------------
# The two halves of the old single regex answer different questions, so they cannot share a scope:
#
#   EFFECT class (destructive SQL) — "could auto-landing this DESTROY durable data?" Only meaningful
#     where the statement can EXECUTE against a store of record, so it is EXEMPTIBLE per path by the
#     declared manifest below (scripts/esc-exempt.manifest).
#   DISCLOSURE class (credential material) — "does this commit LEAK a secret?" A private key is
#     exactly as leaked in a markdown doc as in code, so this class scans EVERY changed file and is
#     never exemptible by anything.
#
# Collapsing them is what made this rail useless: measured over its whole life (land.log, 506 clean
# / 11 hit, 9 packets) its precision was ZERO — 4 parks were a rebuildable-cache retention GC, 3
# were docs describing the defect, 1 was the classifier matching its own test corpus. An alarm that
# only ever fires on benign input carries the same zero bits as one that cannot fire, and it trains
# the operator to rubber-stamp the packet class meant to stop a real destructive land. The
# exemption rationale, the measured population and the deliberate NON-entries live in the manifest.
ESC_RE_EFFECT_DEFAULT='DROP[[:space:]]+TABLE|DROP[[:space:]]+COLUMN|DROP[[:space:]]+DATABASE|DROP[[:space:]]+SCHEMA|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].+[[:space:]]DROP'
ESC_RE_SECRET_DEFAULT='-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
ESC_EXEMPT_FILE_DEFAULT='scripts/esc-exempt.manifest'
# NOTE: auth/session/navigation code lands are ALSO escalation-worthy (operator ruling),
# but this repo's normal churn is full of those words — a substring scan would self-park
# every land. Keep the default to high-signal destructive-SQL / credential patterns and
# let a repo extend it via SHIP_LAND_ESC_RE (which overrides the EFFECT class — the
# exemptible one — precisely because that is the class an app repo needs to widen; the
# DISCLOSURE class has its own SHIP_LAND_ESC_RE_SECRET and defaults to never-exempt).

# ---- helpers ---------------------------------------------------------------

is_shell_file() {  # *.sh/*.bash OR a shell shebang (portable — no GNU \b)
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
}

is_python_file() {  # *.py OR a python shebang (the extensionless-glob-miss fix)
  case "$1" in *.py) return 0 ;; esac
  [[ -f "$1" ]] || return 1
  head -1 "$1" 2>/dev/null | grep -qiE '^#!.*python'
}

esc_exempt_path() {  # $1=repo-relative path $2=newline-separated patterns → 0 iff DECLARED exempt
  local p="$1" pats="$2" pat
  [[ -n "$pats" ]] || return 1
  while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    # shellcheck disable=SC2053  # the RHS is a PATTERN on purpose (so `*` crosses `/`), not a literal
    if [[ "$p" == $pat ]]; then return 0; fi
  done <<< "$pats"
  return 1
}

esc_exempt_patterns() {  # $1=base rev → the declared EFFECT-class patterns (empty ⇒ nothing is exempt)
  # Read from the BASE revision, never the working tree, and that is the whole anti-self-exemption
  # mechanism: an entry added inside the landing range is INERT for the land that adds it, so a
  # change can never widen the exemption set and rely on the widening in one move. Enforced by
  # construction rather than by review, so a sloppily-reviewed widening cannot take effect either.
  # It also dissolves the bootstrap circle a park-on-touch rule would create — introducing this
  # manifest at all would be a "widening" and the rail's own first land could never happen.
  local base="$1" f
  f="${SHIP_LAND_ESC_EXEMPT_FILE:-$ESC_EXEMPT_FILE_DEFAULT}"
  git show "$base:$f" </dev/null 2>/dev/null \
    | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

esc_match() {  # $1=file $2=diff-body $3=regex $4=class → prints `<file>: <class>: <line>` per hit.
               # FAIL CLOSED: if grep cannot evaluate the pattern (rc≥2: invalid regex, or an
               # option-like $re), emit a synthetic hit so the caller PARKS. The one fail-closed
               # landing rail must NEVER read a malformed pattern as clean. `--` stops an $re
               # beginning with `-` being parsed as an option; the explicit rc capture (not
               # `|| true`) stops rc 2 being swallowed as rc 1 (no match).
  local f="$1" body="$2" re="$3" cls="$4" out rc ln
  out="$(printf '%s\n' "$body" | grep -inE -- "$re")"; rc=$?
  if [[ "$rc" -ge 2 ]]; then
    printf '%s: %s: ESC-SCAN-ERROR: grep rc=%s — pattern uninterpretable (invalid regex / option-like); failing closed, PARK\n' \
      "$f" "$cls" "$rc"
    return 0
  fi
  [[ -n "$out" ]] || return 0
  while IFS= read -r ln; do
    [[ -n "$ln" ]] && printf '%s: %s: %s\n' "$f" "$cls" "$ln"
  done <<< "$out"
  return 0
}

esc_scan() {  # $1=range → prints matched escalation lines (empty ⇒ clean), each attributed to its FILE.
              # Per-file is not cosmetic: the old whole-range pipe reported diff-relative line numbers
              # ("3913:+<the row-delete>") that name no file at all, so the packet could not be reviewed
              # without re-deriving the diff — and per-path exemption is impossible without knowing
              # the path. The DISCLOSURE class runs over every file; the EFFECT class is skipped only
              # where the declared manifest says no durable store can be reached.
  local range="$1" re_eff re_sec pats exempt_f list f body rc base
  re_eff="${SHIP_LAND_ESC_RE:-$ESC_RE_EFFECT_DEFAULT}"
  re_sec="${SHIP_LAND_ESC_RE_SECRET:-$ESC_RE_SECRET_DEFAULT}"
  base="${range%%..*}"
  pats="$(esc_exempt_patterns "$base")"
  exempt_f="${SHIP_LAND_ESC_EXEMPT_FILE:-$ESC_EXEMPT_FILE_DEFAULT}"
  # NUL-delimited enumeration, and it is load-bearing rather than tidy: `--name-only` QUOTES a
  # non-ASCII path ("docs/caf\303\251.md"), and feeding that quoted form back as a pathspec matches
  # nothing — the file's diff would come back empty and the scan would skip it ENTIRELY, i.e. the one
  # fail-closed landing rail would fail OPEN on any non-ASCII filename. `-z` emits raw bytes with no
  # quoting, so no path can hide. Via a temp file, not a pipe, so git's rc stays checkable (a pipeline
  # would hand us grep's rc) and no child can steal the loop's stdin.
  list="$(mktemp 2>/dev/null)" || {
    printf 'ESC-SCAN-ERROR: mktemp failed — cannot enumerate the range; failing closed, PARK\n'; return 0; }
  git -c core.quotePath=false diff --name-only -z "$range" </dev/null >"$list" 2>/dev/null; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$list"
    printf 'ESC-SCAN-ERROR: git diff --name-only rc=%s — cannot enumerate the range; failing closed, PARK\n' "$rc"
    return 0
  fi
  while IFS= read -r -d '' f; do
    [[ -n "$f" ]] || continue
    # </dev/null on every child: this loop is fed by a herestring, and a git that read stdin would
    # eat the remaining file list (the silent-truncation class that makes a security scan pass).
    body="$(git diff "$range" -- "$f" </dev/null 2>/dev/null | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ' || true)"
    [[ -n "$body" ]] || continue
    esc_match "$f" "$body" "$re_sec" secret            # (1) DISCLOSURE — every file, never exemptible
    if [[ "$f" == "$exempt_f" ]]; then                 # (2) the TRUST ROOT changed → surfaced, LOUD
      # Deliberately NOT a hit: base-read has already made these entries inert for this land, so
      # parking here would add no security and would make the manifest's own first land impossible.
      # It is still announced, because a widening the operator never saw is the thing to avoid.
      printf '⚠ ship-land: the EFFECT-class exemption set (%s) changed in this range. Entries added here are INERT for this land (read from %s); they take effect from the NEXT land.\n' \
        "$f" "${base:0:12}" >&2
    fi
    if esc_exempt_path "$f" "$pats"; then continue; fi  # (3) EFFECT — declared no-durable-store paths
    esc_match "$f" "$body" "$re_eff" effect
  done < "$list"
  rm -f "$list"
  return 0
}

# Write the park packet in cc-decide's CANONICAL schema. This writer bypasses `cc-decide open`
# (no cc-decide dependency inside the lander's fail-closed escalation path), so it must carry the
# schema itself — every field below has a consumer, and an omitted key is a SILENT drop, never an
# error, because every consumer's predicate is a jq `select`:
#   status            — `.status == "open"` gates cc-decide list --open, autonomy-sweep's paging,
#                       cc-digest's count and operator-readout's board. Omitting it made 6 parked
#                       land-blocks invisible to ALL FOUR (the defect this schema fixes).
#   veto_deadline: "" — load-bearing, and NOT cosmetic: cc-decide expire-sweep fires on
#                       `.veto_deadline != "" and .veto_deadline < now`, and in jq a MISSING key is
#                       `null`, for which BOTH halves are true (`null != ""`, and `null` sorts before
#                       every string). A packet with `status:"open"` but no deadline would therefore
#                       be auto-fired to `expired-actioned` against a null default — silently closing
#                       a land-block no human ever saw. The empty string is what makes it never fire.
#   class: "C"        — HARD-BLOCK/human-only: waits, has NO default. `cc-decide open`'s own
#                       fail-closed gate REFUSES class-B without both --default and --deadline, so
#                       the previous "B" was a class this packet could not have been created with
#                       through the front door; C is also the class operator-readout renders on the
#                       operator board.
#   created           — operator-readout orders the board's class-C rows oldest-first.
# session_sid / staged_artifact_path use the canonical NAMES (not session_id / staged) so the
# board's own jq finds them. `matched` is additive evidence — schema GROWTH is safe here.
write_decision_packet() {  # $1=id $2=branch $3=range $4=hits
  local id="$1" branch="$2" range="$3" hits="$4" dir
  dir="${SHIP_LAND_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
  mkdir -p "$dir" 2>/dev/null || true
  ID="$id" BRANCH="$branch" RANGE="$range" HITS="$hits" SID="${CLAUDE_CODE_SESSION_ID:-}" \
  CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    python3 - "$dir/$id.json" <<'PY'
import json, os, sys
pkt = {
    "id": os.environ["ID"],
    "created": os.environ.get("CREATED", ""),
    "class": "C",
    "what_plain": ("ship-land refused to auto-land branch %r: the landing range %r contains an "
                   "escalation-surface pattern. Auto-landing destructive or security-sensitive "
                   "changes is disallowed; a human must review and land. Each matched line below is "
                   "prefixed `<file>: <class>:` — `secret` = credential material (never exemptible, "
                   "in any file); `effect` = destructive SQL against a path not declared as "
                   "cache-only; `exempt-manifest` = the exemption set itself changed, so review the "
                   "widening. A benign `effect` hit on a rebuildable local cache is a missing entry "
                   "in scripts/esc-exempt.manifest, not a reason to land past this."
                   % (os.environ["BRANCH"], os.environ["RANGE"])),
    "options": ["review the flagged lines and land manually via /ship",
                "amend the commit to remove the escalation pattern, then re-run",
                "if the hit is `effect` on a rebuildable local cache: declare the path in "
                "scripts/esc-exempt.manifest (with its reason), land that alone, then re-run",
                "veto — do not land"],
    "recommendation": "review the flagged lines and land manually if correct",
    "default_if_no_veto": "",
    "veto_deadline": "",
    "staged_artifact_path": "",
    "route_around_taken": "",
    "status": "open",
    "session_sid": os.environ.get("SID", ""),
    "matched": [ln for ln in os.environ["HITS"].strip().splitlines() if ln][:20],
}
with open(sys.argv[1], "w") as f:
    json.dump(pkt, f, indent=2)
print(sys.argv[1])
PY
}

attest_refs() {  # $1=base — pin the gated/landed IDENTITY for the next attest_land line
  ATTEST_BASE="${1:-?}"
  ATTEST_HEAD="$(git rev-parse HEAD 2>/dev/null || echo '?')"
  ATTEST_TREE="$(git rev-parse 'HEAD^{tree}' 2>/dev/null || echo '?')"
}

attest_land() {  # $1=verify $2=sweep $3=esc $4=exit — self-attesting land.log line
  # Schema GROWTH is safe: land.log's only reader is a raw tail. head/base/tree make a line
  # replayable (which tree was gated); gate_scope now carries the LANE, and smoke/smoke_n/smoke_s
  # + net make "what did this land actually prove, and was the net alive to prove the rest?"
  # answerable per land — the §7 acceptance read (p50/p99, zero exit-9) comes from exactly here.
  local log; log="${LAND_LOG:-$HOME/.claude/land.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"ship-land","repo":"%s","branch":"%s","sid":"%s","verify":"%s","sweep":"%s","esc_scan":"%s","exit":%s,"head":"%s","base":"%s","tree":"%s","gate_scope":"%s","selected_n":%s,"smoke":"%s","smoke_n":%s,"smoke_s":%s,"net":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "${CLAUDE_CODE_SESSION_ID:-}" \
    "$1" "$2" "$3" "$4" \
    "${ATTEST_HEAD:-?}" "${ATTEST_BASE:-?}" "${ATTEST_TREE:-?}" "${LANE}" "${SELECTED_N:--1}" \
    "${SMOKE_STATE:-none}" "${SMOKE_N:-0}" "${SMOKE_S:-0}" "${NET_STATE:-none}" \
    >> "$log" 2>/dev/null || true
}

rollback_clean() {  # T-P9-7: abort any in-progress rebase so ship-land never exits on a wedged tree.
  # A no-op (harmless non-zero, suppressed) when no rebase is in progress — so it also serves as the
  # clean-tree guarantee on the retry-exhaustion path where nothing was mid-flight. Our commits and
  # the ship/backup-* ref are left intact either way; rollback undoes only a half-applied replay.
  git rebase --abort >/dev/null 2>&1 || true
}

detect_trunk() {
  local t
  t="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [[ -z "$t" ]] && t="main"
  printf '%s' "$t"
}

postland_net_live() {  # sets NET_STATE=live|inert|none. ALWAYS returns 0 — never blocks a land.
  # ABSENCE IS LOUD, but loudness is the whole remedy (v2). v1 read an inert net as "do not
  # narrow" and DEGRADED THE LAND TO THE FULL CORPUS — a fail-closed path picking the MORE
  # expensive action, i.e. the amplifier law (R7) in its purest form: the net is inert precisely
  # when the box is wedged, and the response was to add 40 minutes of bats per land to a wedged
  # box. v2 keeps the detection and drops the escalation: WARN on stderr, attest net:"inert", and
  # LAND. Correctness is not lost — the land never claimed the full suite in the first place; what
  # an inert net costs is verification LATENCY, which R9's freshness alarm surfaces to the
  # operator (cc-blockers / operator-readout), where a human can act on it.
  # No stamps dir / no green stamp yet ⇒ the net simply is not adopted (the bootstrap land).
  NET_STATE="none"
  [[ "${POSTLAND_STALENESS_GUARD:-on}" = "off" ]] && return 0
  local dir age max newest=0 m p
  dir="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}/stamps"
  [[ -d "$dir" ]] || return 0
  # A stamp is GREEN by CONTENT ("verdict":"green"), not by filename — the naming is T3's to
  # choose and must not be a hidden coupling. Newest green stamp's mtime is the liveness clock.
  while IFS= read -r p; do
    grep -qs '"verdict"[[:space:]]*:[[:space:]]*"green"' "$p" || continue
    m="$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null || echo 0)"
    [[ "$m" -gt "$newest" ]] && newest="$m"
  done < <(find "$dir" -type f 2>/dev/null)
  [[ "$newest" -gt 0 ]] || return 0
  max="${POSTLAND_MAX_STAMP_AGE_H:-24}"
  age=$(( ( $(date +%s) - newest ) / 3600 ))
  if [[ "$age" -lt "$max" ]]; then NET_STATE="live"; return 0; fi
  NET_STATE="inert"
  echo "⚠ ship-land: the post-land VERIFIER looks INERT — newest GREEN stamp is ${age}h old (max ${max}h). This land PROCEEDS (a land never made the full-suite claim), but nothing is re-proving the trunk: check that com.claude.postland-verify is loaded (launchctl list) and that its stamps dir is advancing. Attested net:\"inert\". (kill switch: POSTLAND_STALENESS_GUARD=off)" >&2
  return 0
}

# ---- load shedding: a PURE PREDICATE now — shed = SKIP, never WAIT ----------
# WHAT WAS HERE: gate_admit, a bounded SLEEP loop that deferred an expensive suite until loadavg
# fell below a ceiling. It is deleted, not tuned, because waiting is the amplifier itself (R7):
#   * a bound written per-call MULTIPLIED across a per-suite loop (postland slept ~2h/run;
#     600s × ~12 calls, backlog 60ec4c2d86d4);
#   * five concurrent gates sat at load 16-18 waiting for a ceiling of 8 while THEIR OWN corpora
#     were the load — self-starvation below their own threshold, a deadlock in all but name;
#   * and every waiter that finally timed out ran the corpus ANYWAY, so the wait bought nothing
#     but latency. A fail-closed path must never pick the MORE expensive action.
# v2 keeps the sensor and drops the queue: at/above the ceiling the smoke is SKIPPED ENTIRELY and
# the post-land verifier proves the tree instead. Shedding now defers to the NET, not to a sleep.
#
# FAIL-OPEN, unchanged in spirit: an unreadable sensor, a non-numeric ceiling, or the kill switch
# (CC_GATE_MAX_LOAD=0|off) all answer "not above the ceiling" ⇒ the smoke RUNS. That is safe here
# in a way it was not for gate_admit: the thing it admits is now bounded by an absolute wall
# budget (≤120s, nice'd), so a broken sensor can cost latency but can never restore the corpus.
#
# IN_LAND_LOCK survives the deletion with a bigger job: it is the structural enforcement of
# "nothing heavy may EVER enter the land-lock" (see run_gate) — the invariant the v1 in-lock full
# gate broke, producing a 3h36m lock holder and the multi-day land jam.
IN_LAND_LOCK="${IN_LAND_LOCK:-0}"
load_above_ceiling() {  # 0 = at/above the ceiling (SHED) · 1 = below it, sensor broken, or off
  local max load
  max="${CC_GATE_MAX_LOAD:-8}"
  [[ "$max" = "0" || "$max" = "off" ]] && return 1            # kill switch: never shed
  case "$max" in ''|*[!0-9.]*) return 1 ;; esac               # non-numeric ceiling ⇒ fail OPEN
  load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
  case "${load:-}" in ''|*[!0-9.]*) return 1 ;; esac          # unreadable sensor ⇒ fail OPEN
  awk -v l="$load" -v m="$max" 'BEGIN{exit !(l+0 >= m+0)}'
}

# ---- GATE-KILLED: signal death is a THIRD state, never RED -------------------
# WHY (backlog 9c5d0ba74e79, observed live): a gate ran green through 1359 tests, then
# `bats tests/ Killed: 9`, and ship-land printed "gate: bats RED / not pushing". A real red and a
# dead carrier were BYTE-INDISTINGUISHABLE in the output, so the retry read as flaky tests instead
# of "we ran out of machine". That misreading is the middle link of the 2026-07-26 runaway
# (f8e40b4c577d): kills → "RED" → lands fail → items re-block → the dispatcher retries → more load
# → more kills. And the killers were PEERS: worktree-UNSCOPED `pkill -9 -f bats-core/bats` matches
# every concurrent session's gate machine-wide (a0718a5d78b3) — see scripts/gate-cleanup.sh.
# A killed run earned NO verdict, so it must not push, must not stamp gate-green, and must not be
# reported as evidence about the tree. It exits 9, distinct from 6.
#
# The DETECTION below is trunk's, not this branch's: an earlier draft here keyed on `rc > 128`,
# which is simply wrong — bats masks the signal (see run_scoped_suite), so a SIGKILLed suite surfaces
# as plain `1`. The TAP body is the only honest discriminator, and that half was already landed by
# a sibling working the same incident. What this branch adds on top is (a) the twice-cut case,
# which trunk could not decide because it did not capture the re-run's TAP (its own message says
# "RED (or cut twice)"), and (b) a distinct EXIT CODE for the non-verdict, so the caller learns
# "retry when quieter" instead of "your code is broken".
# ---- per-gate $HOME isolation: the gate proves the TREE, not the desk's state ----------------
# WHY (GATE_ARCHITECTURE_PLAN §4, "honest coupling"): 109 of 126 suites are grandfathered
# non-hermetic (scripts/test-hermeticity-lint.sh) — they READ and WRITE the operator's live
# ~/.claude while ~40 sessions mutate it. Today that buys intermittence. The moment a content-
# addressed proof CACHE lands (Phase 2b) it buys something strictly worse: a green produced under
# cross-talk gets KEYED and REPLAYED, so a transient false green becomes a DURABLE one. Isolation
# is therefore the correctness PRECONDITION for that cache, and it is only that — §2 measured
# hermeticity as NOT the driver of gate flakiness (no enrichment, wrong failure shape, 2-point
# ceiling), so this change makes no claim on `q` and none on P(green). Do not re-litigate it here.
#
# MECHANISM: APFS clonefile, measured on this box, not designed in the abstract. `cp -Rc` copies by
# REFERENCE — the whole 2.1 GB / 18.8k-file ~/.claude clones in ~9 s at ZERO space cost, ~/.reso in
# ~1.2 s (`diskutil info /` ⇒ APFS; $HOME and $TMPDIR are both on /dev/disk3s5, and clonefile is
# same-volume). Every top-level entry the clone list does NOT name is SYMLINKED to the real one, so
# every path that resolves today still resolves — an ABSENT path would manufacture a false RED,
# the one outcome this must never cause. Isolation is thus bounded and honest: writes to ~/.claude
# and ~/.reso are contained; writes THROUGH a symlinked entry are not, and were not before either.
# (Deliberate non-goal: the exoneration re-run reuses the same clone rather than taking a fresh
# one. A per-suite clone would cost ~10 s per failing suite to buy a cleanliness the live-$HOME
# status quo never had.)
#
# FAIL OPEN, ALWAYS. Any failure — no mktemp, no clonefile, an unreadable file mid-copy — drops
# isolation and runs the gate exactly as it runs today. A broken clone must never block a land;
# that would make this a new fail-closed amplifier, the precise defect class §1 is about.
# GATE_HOME_ISOLATED records which happened, so Phase 2b can refuse to CACHE a non-isolated green
# rather than inherit the lie. SHIP_LAND_GATE_HOME_ISO: `off` = kill switch · `on` = force even for
# a fixture pipeline under bats · unset/`auto` = isolate real lands only (see gate_home_setup).
#
# The isolation is applied at gate_bats — the single chokepoint every runner (the v2 smoke, the
# v1-lane corpus, and run_scoped_suite's re-run) funnels through — so ship-land's OWN bookkeeping
# (record_gate_cut / run_scoped_suite writing $HOME/.claude/autonomy/postland/flakes.jsonl) still
# lands in the operator's REAL ledger. Isolating that too would silently delete the flake
# denominator at teardown.
GATE_HOME=""            # non-empty ⇒ the gate's bats children run under this cloned $HOME
# EXPORTED, not local: the cacheability of a green is a fact about the RUN, so it must be legible
# to whatever decides to key it — Phase 2b's cache writer, and today the suites and the operator.
export GATE_HOME_ISOLATED=0    # 1 = isolated (a Phase-2b proof from this run is cacheable) · 0 = fell open

gate_home_teardown() {  # idempotent · NEVER fails · refuses to remove anything it did not create
  local d="${GATE_HOME:-}"
  GATE_HOME=""; export GATE_HOME_ISOLATED=0
  [[ -n "$d" ]] || return 0
  # The dir is a symlink FARM over the operator's real $HOME, so this `rm -rf` is one bad variable
  # away from the worst possible outcome. Two independent brakes: `rm -rf` unlinks symlinks and
  # never follows them (so it cannot reach ~/Library, ~/Development, ~/.claude-secondary …), AND
  # the name guard below means a GATE_HOME we did not mint removes nothing at all.
  case "$d" in
    */gate-home.??????) [[ -d "$d" ]] && { rm -rf "$d" 2>/dev/null || true; } ;;
    *) echo "⚠ gate: refusing to remove an unrecognized \$HOME-isolation dir '$d' (left in place)." >&2 ;;
  esac
  return 0
}

gate_home_setup() {     # NEVER returns non-zero — isolation is best-effort BY CONTRACT
  local root dest entry name clone_list
  gate_home_teardown    # re-entrant: run_gate is called again on every stale-gate re-round
  if [[ "${SHIP_LAND_GATE_HOME_ISO:-auto}" = "off" ]]; then
    echo "⚠ gate: \$HOME isolation OFF (SHIP_LAND_GATE_HOME_ISO=off) — bats runs against the live ~/, so a green here is NOT cacheable." >&2
    return 0
  fi
  # NOT A REAL LAND ⇒ nothing to isolate. A ship-land invoked from inside bats is a FIXTURE
  # pipeline: the suite driving it already sandboxed everything it asserts on, and its gate's
  # verdict is an assertion target, not a claim about the operator's repo. Measured, not guessed —
  # tests/ship-land.bats drives 50 such pipelines and tests/land-gate-cas.bats 11, so cloning for
  # each took that suite from 115 s to >8 min, and inside a real FULL gate the same suites would
  # have added ~10 min of pure waste. This also covers the NESTED case for free (a fixture pipeline
  # running under an outer gate is already inside that gate's clone). `=on` forces isolation
  # anyway — that is how tests/gate-home-isolation.bats exercises the real thing.
  if [[ -n "${BATS_TEST_TMPDIR:-}${BATS_SUITE_TMPDIR:-}" && "${SHIP_LAND_GATE_HOME_ISO:-auto}" != "on" ]]; then
    echo "→ gate: \$HOME isolation skipped — fixture pipeline under bats (force with SHIP_LAND_GATE_HOME_ISO=on)." >&2
    return 0
  fi
  root="${SHIP_LAND_GATE_HOME_ROOT:-${TMPDIR:-/tmp}}"
  clone_list="${SHIP_LAND_GATE_HOME_CLONE:-.claude .reso}"
  # Reap clones orphaned by a SIGKILLed gate — 83% of observed gate deaths are kills (§2), and a
  # killed shell runs no EXIT trap. Bounded at 8 h, ~9× the longest observed gate (3217 s), so a
  # live sibling's clone can never be caught by it.
  find "$root" -mindepth 1 -maxdepth 1 -type d -name 'gate-home.??????' -mmin +480 -exec rm -rf {} + 2>/dev/null || true
  dest="$(mktemp -d "${root%/}/gate-home.XXXXXX" 2>/dev/null)" || dest=""
  if [[ -z "$dest" || ! -d "$dest" ]]; then
    echo "⚠ gate: could not create a \$HOME-isolation dir under '$root' — running against the live ~/ (fail-open)." >&2
    return 0
  fi
  # 1. SYMLINK every top-level entry of $HOME we are not cloning: ~/.gitconfig (one suite commits
  #    with no local identity), ~/.zshrc, ~/.config, the sibling ~/.claude-* account trees (4.1 GB
  #    — cloning those would cost more than the gate saves). Links are free and preserve resolution.
  while IFS= read -r entry; do
    name="${entry##*/}"
    case " $clone_list " in *" $name "*) continue ;; esac
    ln -s "$entry" "$dest/$name" 2>/dev/null || true
  done < <(find "$HOME" -mindepth 1 -maxdepth 1 2>/dev/null)
  # 2. CLONE the mutation surface. A PARTIAL clone is worse than none — it is isolated but missing
  #    read state, which is how you manufacture a false RED — so any error drops isolation whole.
  for name in $clone_list; do    # deliberate word-split: clone_list is a space-separated list
    [[ -e "$HOME/$name" ]] || continue
    if ! cp -Rc "$HOME/$name" "$dest/$name" 2>/dev/null; then
      echo "⚠ gate: APFS clone of ~/$name failed — running against the live ~/ (fail-open). A green from this run is NOT cacheable." >&2
      GATE_HOME="$dest"; gate_home_teardown
      return 0
    fi
  done
  GATE_HOME="$dest"; export GATE_HOME_ISOLATED=1
  # EXIT only. Trapping INT/TERM would swallow them (a handler without a re-raise turns Ctrl-C into
  # "keep going"), and the reaper above already covers the signal-death case this script actually
  # sees. There is no other EXIT trap in this file; adding one must compose with this.
  trap gate_home_teardown EXIT
  echo "→ gate: \$HOME isolated — APFS clone of ${clone_list// /, } at $dest (bats mutations cannot reach the operator's live ~/)." >&2
  return 0
}

# ---- gate env hygiene: tuning THIS land must never change the VERDICT -------
# Found by landing this very branch with the remedy ship.md itself recommends for lock starvation
# (SHIP_LAND_GATE_ROUNDS=0, plus a raised LAND_LOCK_WAIT): a tests/ship-land.bats that is 46/46
# green went RED — 7 CAS / unlocked-gate / lock-hold tests, and since they are DIRECT suites of
# this change the flake-exoneration correctly refused to absolve them, so the land exited 6 on a
# tree that was never broken. Cause: these knobs are plain env vars, so every bats subprocess
# INHERITS them, and those particular tests assert the very behaviour the knobs change.
# Controlled three-way, all on the same tree:
#     clean env      + free lock              → 46 ok /  0 not ok   (the truth)
#     ROUNDS=0       + free lock              → 45 ok /  1 not ok
#     ROUNDS=0       + held lock + contention →         7 not ok  (×2 re-runs = 14)
# That is a fail-closed degradation manufacturing a VERDICT about the tree out of a fact about
# the operator's flags — the same class as CUT ≠ RED (f8e40b4c577d), and worse, it fires on the
# documented escape hatch, so the fix for starvation caused a false red for anyone who took it.
# CC_GATE_MAX_LOAD is FORCED to 0 rather than unset, and in v2 that matters MORE, not less: 0 is
# the never-shed kill switch, so a fixture pipeline's smoke always runs. Left inherited, whether a
# nested pipeline smoked at all would depend on the ambient load of the box the suite happens to
# run on — a test verdict decided by `uptime`, which is the same class of defect as the rest of
# this paragraph. Only LANDER tuning is scrubbed — a test that wants any of these (including a
# deliberate shed) sets it itself, per-test, which is unaffected.
# SHIP_LAND_LANE and SHIP_LAND_SMOKE_BUDGET_S join the scrub list for exactly the same reason, and
# the lane is the sharpest case yet: tests/ship-land.bats asserts fast-lane semantics, so an
# operator landing with the kill switch on (SHIP_LAND_LANE=v1) would bleed `v1` into all ~50
# fixture pipelines in that suite and red a tree that is fine — the ROUNDS=0 defect verbatim, on
# the flag this very change introduces. SHIP_LAND_TIMEOUT_BIN likewise: an operator's set-empty
# (bounding OFF) must not silently unbound a fixture's children. (SHIP_LAND_FULL_PER_SUITE was
# scrubbed here for the same reason until v2 deleted the monolithic runner it selected; the entry
# went with the flag, the precedent it set did not.)
gate_bats() {  # run bats with the operator's lander tuning scrubbed; args pass through verbatim
  # …and under the isolated $HOME when gate_home_setup got one. THE chokepoint: the smoke runner,
  # the v1 corpus runner, and every exoneration re-run reach bats only through here, so isolation
  # AND the smoke's wall bound cover every path without any caller knowing about them.
  # An EMPTY GATE_HOME passes HOME through untouched — that is the fail-open branch, not a bug.
  #
  # THE BOUND IS RECOMPUTED PER CALL, from the shared absolute SMOKE_DEADLINE — not handed down as
  # a per-suite budget. A per-call budget is what multiplied gate_admit into 21h of "bounded"
  # waiting; one deadline for the whole phase cannot multiply no matter how many children run
  # (run_scoped_suite alone calls this twice per suite). A deadline already passed still yields a
  # 1s bound rather than an unbounded child: the caller's loop stops starting suites, and anything
  # already inside dies fast and honestly as a CUT.
  #
  # STDIN IS /dev/null, AND THIS IS THE ONE PLACE THAT DECIDES IT (2026-08-06). A land can be fired
  # by launchd or the desk, so this process's stdin is whatever the caller handed it.
  # CORRECTED same day: this said "routinely a pipe with no writer that never EOFs" and blamed
  # launchd. MEASURED — launchd hands its children /dev/null already (a RunAtLoad probe read its own
  # `lsof -d 0`). The exposure is the DESK/AGENT path instead, and it is the larger one: a Claude
  # Code session's fd 0 is a unix SOCKET whose reader never sees EOF (rc 124, measured). Nothing
  # below changes — only the named source of the bad stdin was wrong.
  # bats does not read stdin, but it INHERITS it into every test, and a suite that stubs a
  # stdin-consuming binary with an unconditional `cat` then waits for an EOF that is not coming.
  # 5e460544 is that defect measured: tests/handoff-fire-kitty.bats' osascript stub drained
  # unconditionally — correct for `osascript - …` (script ON stdin), a forever-hang for
  # `osascript -e …` (script in ARGV, stdin merely inherited). stdin=/dev/null → 34/34 in <1s;
  # stdin=an open pipe with a live writer → rc 124, wedged.
  # The polarity is why it must be fixed HERE: a hand-run gets a stdin that EOFs, so it is green by
  # hand and hangs only on the automated path, and a hung gate looks exactly like a slow one.
  # 5e460544 fixed three stubs; this covers the CLASS — all 290 suites were screened under a no-EOF
  # stdin and none depends on inherited stdin, so every suite written later is immunised too.
  # Being THE chokepoint is what makes one redirect enough: the smoke runner, the v1 corpus runner
  # and every exoneration re-run reach bats only through here. No caller pipes into gate_bats
  # (they pipe its OUTPUT — run_scoped_suite tees), so nothing loses a stdin it was using.
  local homeenv=() pre=() rem
  [[ -n "${GATE_HOME:-}" ]] && homeenv=(HOME="$GATE_HOME")
  if [[ -n "${SMOKE_DEADLINE:-}" ]]; then
    if [[ -n "$TIMEOUT_BIN" && -x "$TIMEOUT_BIN" ]]; then
      rem=$(( SMOKE_DEADLINE - $(date +%s) ))
      [[ "$rem" -lt 1 ]] && rem=1
      pre=("$TIMEOUT_BIN" -k 10 "$rem")     # outermost ⇒ it owns the process group it kills
    fi
    # nice'd (§4.1): the smoke only runs below the load ceiling, so this costs ~nothing, and it
    # keeps a land from being the thing that pushes an interactive box over.
    [[ -n "$NICE_BIN" && -x "$NICE_BIN" ]] && pre+=("$NICE_BIN" -n "${SHIP_LAND_SMOKE_NICE:-10}")
  fi
  ${pre[@]+"${pre[@]}"} \
  env -u SHIP_LAND_GATE_ROUNDS -u SHIP_LAND_VERIFY_RETRIES -u SHIP_LAND_GATE_SCOPE \
      -u LAND_LOCK_WAIT -u LAND_LOCK_TTL \
      -u SHIP_LAND_LANE -u SHIP_LAND_SMOKE_BUDGET_S -u SHIP_LAND_TIMEOUT_BIN \
      CC_GATE_MAX_LOAD=0 ${homeenv[@]+"${homeenv[@]}"} bats "$@" </dev/null
}

run_corpus() {  # $1=newline-list of DIRECT suites — the WHOLE corpus, one process per suite.
                # LANE=v1 ONLY. Unreachable in the default fast lane, by construction.
  # THIS IS THE KILL SWITCH, not a tier. v2's whole finding is that the corpus cannot run
  # per-land at this volume — see the header. It survives as one env flag away rather than a
  # revert because a revert would itself need the gate (the bootstrap deadlock).
  # What is GONE with the monolithic branch it replaces: `bats tests/` handed all 126 files to ONE
  # bats-exec-suite for 20-53 min, so a kill at suite 120 lost all 126 and attested exit:6 RED.
  # Per suite (GATE_ARCHITECTURE_PLAN Phase 1, MLE over 55 real runs: P(green) = (1-q)^n,
  # q=2.94%/suite ⇒ 2.3% at n=126 → 49.9% with the fresh-TMPDIR re-run) a kill costs ONE suite.
  # The monolith had no such appeal and failed 33 of its 34 runs; it is deleted, not kept.
  local direct="${1:-}" f n=0 red=0 killed=0 srv
  echo "→ gate[v1]: bats tests/ — full corpus, one process per suite (SHIP_LAND_LANE kill switch)" >&2
  for f in tests/*.bats; do
    [[ -e "$f" ]] || continue
    n=$(( n + 1 ))
    srv=0; run_scoped_suite "$f" "$direct" || srv=$?
    case "$srv" in
      0) ;;
      2) killed=$(( killed + 1 )) ;;
      *) red=$(( red + 1 )) ;;
    esac
  done
  SELECTED_N="$n"
  if [[ "$n" -eq 0 ]]; then
    echo "✗ gate[v1]: no suites matched tests/*.bats — refusing to claim green on an empty corpus" >&2
    GATE_RED=1; return 1
  fi
  if [[ "$red" -eq 0 && "$killed" -eq 0 ]]; then
    echo "✓ gate[v1]: FULL corpus green — $n suites, one process each" >&2; return 0
  fi
  # NO FAIL-FAST, deliberately. The loop must finish the corpus so "did ANY suite name a real
  # failure?" is answerable from evidence. Stopping at the first CUT would report a non-verdict
  # (exit 9 ⇒ "retry when the box is quieter") for a corpus that also contained a genuine red —
  # the dispatcher would then retry a tree that is actually broken, which is f8e40b4c577d in
  # miniature. Finishing costs wall time on an already-doomed run and buys every failing suite
  # named in ONE cycle instead of one per 20-minute gate.
  if [[ "$killed" -gt 0 ]]; then
    GATE_KILLED=1
    echo "⛔ gate[v1]: GATE-KILLED — $killed of $n suite(s) were cut TWICE with ZERO 'not ok'; they earned no verdict. Free a stuck gate with scripts/gate-cleanup.sh (worktree-scoped), never a bare pkill." >&2
  fi
  if [[ "$red" -gt 0 ]]; then
    GATE_RED=1
    echo "✗ gate[v1]: bats RED — $red of $n suite(s) failed" >&2
  fi
  return 1
}

filter_host_suites() {  # $1=newline list of suites → the same list minus HOST suites
  # THE PARTITION BINDS THE LAND LANE TOO (LAND_PIPELINE_V2 §4.2.2). scripts/host-suites.manifest
  # names the suites whose real subject is the LIVE ~/.claude layer, not the tree: the verifier
  # runs tests/*.bats MINUS this set, and the deploy lane runs exactly this set POST-deploy,
  # against the layer they actually assert. That partition is what kills the bootstrap circle —
  # and it is worthless if the same suites can re-enter through the SMOKE.
  # They can, easily: a host suite becomes a DIRECT suite of any land that touches it, and the v2
  # bootstrap land is precisely such a land. Measured on this box while writing it:
  # tests/deploy-parity.bats test 8 is TRUE-red (the live layer is missing a symlink), so an
  # unfiltered smoke would exit 6 on a land whose TREE is fine, for a live-layer fact the tree
  # cannot control. That is the bootstrap circle resurfacing one lane over.
  # Read from the TREE BEING LANDED, repo-root-relative — same rule as the two ratchets: the tree
  # is judged by the manifest it SHIPS, so a land that legitimately adds a host suite is judged by
  # its own new list. Missing/unreadable/empty manifest ⇒ NO filtering (the pre-adoption state,
  # and the safe direction: we run more, we never silently run less than the author expects).
  local list="$1" manifest pats kept before after
  manifest="${SHIP_LAND_HOST_MANIFEST:-scripts/host-suites.manifest}"
  [[ -r "$manifest" ]] || { printf '%s\n' "$list"; return 0; }
  pats="$(mktemp 2>/dev/null)" || { printf '%s\n' "$list"; return 0; }
  # Format (frozen contract): one tests/<name>.bats per line · `#` comments and blank lines
  # ignored · trailing whitespace tolerated. An unparseable line simply fails to match anything.
  grep -vE '^[[:space:]]*(#|$)' "$manifest" 2>/dev/null | sed 's/[[:space:]]*$//' > "$pats"
  if [[ ! -s "$pats" ]]; then rm -f "$pats"; printf '%s\n' "$list"; return 0; fi
  before="$(printf '%s\n' "$list" | grep -c . || true)"
  kept="$(printf '%s\n' "$list" | grep -vxF -f "$pats" || true)"
  rm -f "$pats"
  after="$(printf '%s\n' "$kept" | grep -c . || true)"
  [[ "$after" -lt "$before" ]] && \
    echo "→ gate: smoke excluded $(( before - after )) direct suite(s) — host suite, the post-deploy check owns it (they assert the LIVE layer, which this tree cannot control)." >&2
  printf '%s\n' "$kept"
  return 0
}

run_smoke() {  # $1=range → 0 = PROCEED · 1 = RED (a named failure in a direct suite)
               # sets SMOKE_STATE / SMOKE_N / SMOKE_S; never sets GATE_KILLED (see below).
  # THE LAND'S ONLY TEST WORK (§4.1): the `--direct` suites of THIS diff — the ones a change can
  # actually break in a way statics cannot see — under ONE TOTAL wall budget. Everything else is
  # the verifier's job now. Worst case here is bounded by construction: ≤ SHIP_LAND_SMOKE_BUDGET_S,
  # or zero when the box is busy.
  #
  # SMOKE NEVER YIELDS EXIT 9. run_scoped_suite still distinguishes a cut (rc 2) from a named
  # failure (rc 1) — that split is load-bearing and stays — but at THIS layer a non-verdict is not
  # escalated to GATE_KILLED, because a non-verdict must never block a land (R6/§4.1): the corpus
  # behind us will re-prove the tree, and turning "the box was busy" into a failed land is exactly
  # the kill→"RED"→re-block→retry runaway (f8e40b4c577d). It becomes smoke:"partial" and lands.
  local range="$1" direct budget start f n=0 red=0 cut=0 srv
  SMOKE_STATE="none"; SMOKE_N=0; SMOKE_S=0; SMOKE_DEADLINE=""
  ls tests/*.bats >/dev/null 2>&1 || return 0

  # STRUCTURAL: nothing heavy may EVER run under the land-lock. Not a policy an author can forget —
  # the check lives here, at the only place that could start a suite. v1's in-lock full gate is the
  # 3h36m lock holder and the multi-day jam; the lock exists for the CAS race window alone.
  if [[ "$IN_LAND_LOCK" = "1" ]]; then
    echo "→ gate[locked]: statics + ratchets only — no bats inside the land-lock (v2 invariant)." >&2
    return 0
  fi

  if [[ ! -x "$GATE_SELECT" ]]; then
    # v1 read this as FULL (fail-closed toward a 40-minute corpus). In v2 "fail-closed toward more
    # proof" IS the amplifier: the selector is missing exactly on the live-symlink path where a
    # brand-new tracked file has no symlink yet, i.e. on the busiest boxes. No selection ⇒ no
    # smoke; the verifier still proves the tree, and the land is not punished for a deploy gap.
    echo "⚠ gate: selector '$GATE_SELECT' missing/not executable — no smoke this land; the post-land verifier proves this tree." >&2
    return 0
  fi
  direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
  if [[ "$direct" = "FULL" ]]; then
    # FULL is the selector's own fail-closed answer ("I could not decide"). It can no longer mean
    # "run everything", so its honest v2 reading is "this selection is untrustworthy" ⇒ no smoke.
    echo "⚠ gate: selector answered FULL (its fail-closed 'cannot decide') — no direct-suite smoke this land; the verifier proves the tree." >&2
    return 0
  fi
  direct="$(printf '%s\n' "$direct" | grep -v '^[[:space:]]*$' || true)"
  # BEFORE the emptiness check on purpose: a land whose every direct suite is a host suite is a
  # lint-only land as far as the smoke is concerned, and must take that branch (and its zero cost)
  # rather than a separate one.
  direct="$(filter_host_suites "$direct" | grep -v '^[[:space:]]*$' || true)"
  if [[ -z "$direct" ]]; then
    echo "→ gate: smoke — 0 direct suite(s) map to this range (lint-only land)." >&2
    return 0
  fi

  if load_above_ceiling; then
    SMOKE_STATE="skipped"
    echo "⏭ gate: smoke SKIPPED — 1-min load is at/above the ceiling ${CC_GATE_MAX_LOAD:-8}. Shedding is a SKIP, never a wait (waiting is what starved five gates below their own ceiling); the post-land verifier proves this tree. Override: CC_GATE_MAX_LOAD=0." >&2
    return 0
  fi

  budget="${SHIP_LAND_SMOKE_BUDGET_S:-120}"
  case "$budget" in ''|*[!0-9]*) budget=120 ;; esac      # non-integer ⇒ the default, never unbounded
  start="$(date +%s)"
  [[ "$budget" -gt 0 ]] && SMOKE_DEADLINE=$(( start + budget ))
  echo "→ gate: smoke — $(printf '%s\n' "$direct" | grep -c .) direct suite(s), ≤${budget}s total, one process each" >&2
  # ONE clone for the whole smoke (not one per suite): the direct suites are as non-hermetic as any
  # other, so they still get the isolated $HOME. Fail-open by contract — see gate_home_setup.
  gate_home_setup
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -e "$f" ]] || continue                            # a suite deleted by this very land
    if [[ -n "$SMOKE_DEADLINE" && "$(date +%s)" -ge "$SMOKE_DEADLINE" ]]; then
      cut=1
      echo "⏱ gate: smoke budget ${budget}s exhausted — remaining suite(s) not started, land PROCEEDS (attested smoke:\"partial\"; the verifier is the net). Override: SHIP_LAND_SMOKE_BUDGET_S." >&2
      break
    fi
    n=$(( n + 1 ))
    srv=0; run_scoped_suite "$f" "$direct" || srv=$?
    case "$srv" in
      0) ;;
      2) cut=1 ;;                                        # cut twice / bound fired ⇒ NO verdict
      *) red=$(( red + 1 )) ;;                           # a named `not ok` ⇒ a verdict
    esac
  done <<< "$direct"
  SMOKE_S=$(( $(date +%s) - start ))
  SMOKE_N="$n"
  SMOKE_DEADLINE=""
  gate_home_teardown

  if [[ "$red" -gt 0 ]]; then
    SMOKE_STATE="red"; GATE_RED=1
    echo "✗ gate: smoke RED — $red of $n direct suite(s) named a failure. This is a VERDICT about your diff (O(diff), reproducible): fix it, do not retry unchanged." >&2
    return 1
  fi
  if [[ "$cut" -eq 1 ]]; then
    SMOKE_STATE="partial"
    echo "⚠ gate: smoke PARTIAL — $n direct suite(s) attempted in ${SMOKE_S}s, not all earned a verdict (cut or budget). A non-verdict never blocks a land; the post-land verifier decides." >&2
    return 0
  fi
  SMOKE_STATE="green"
  echo "✓ gate: smoke green — $n direct suite(s) in ${SMOKE_S}s." >&2
  return 0
}

record_gate_cut() {  # $1=rc $2=logfile [$3=file — default the whole corpus] — a CUT must be
                     # LEGIBLE, never silently a "flake". Per-suite mode names the actual file,
                     # so the ledger says WHICH suite ran out of machine rather than "tests/".
  local fdir sig file="${3:-tests/}"
  fdir="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
  mkdir -p "$fdir" 2>/dev/null || true
  sig="$(grep -m1 -aE 'Terminated|Killed|signal' "$2" 2>/dev/null | sed 's/["\]//g' | cut -c1-160)"
  [[ -z "$sig" ]] && sig="exit $1 / notok=0"
  printf '{"ts":"%s","file":"%s","sha":"%s","phase":"land-gate","outcome":"cut-not-red","signal":"%s","loadavg":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$file" "$(git rev-parse --short HEAD 2>/dev/null || echo '?')" \
    "$sig" "$(uptime 2>/dev/null | sed 's/.*averages*: //' | awk -F'[, ]+' '{print $1}')" \
    >> "$fdir/flakes.jsonl" 2>/dev/null || true
}

tap_plan() {  # $1=log → the TAP plan count bats printed (`1..N`), or "" if it never printed one.
  # bats prints the plan only AFTER gathering the file's tests, so a plan is evidence about how
  # many tests this file was found to hold — which is exactly what a truncated harness gets wrong.
  sed -n 's/^1\.\.\([0-9][0-9]*\).*$/\1/p' "$1" 2>/dev/null | head -1
}

tap_named_failures() {  # $1=log $2=known test count ("" or 0 ⇒ unknown) $3=suite file (for the
                        # message) → the `not ok` lines that are VERDICTS ABOUT THE SUITE, with
                        # bats' own harness artifacts discarded.
  # THE HOLE THIS CLOSES (2026-08-06, reproduced landing 81d6b958adc5). c605a2e's discriminator —
  # "exited non-zero with ZERO 'not ok' ⇒ CUT, not RED" — is right in principle, and a truncated
  # bats run DEFEATS IT BY EMITTING A `not ok`. bats-core's collector aborts with a fixed literal:
  #
  #     bats-gather-tests:285   printf "1..1\nnot ok 1 bats-gather-tests\n"        (>&2)
  #
  # fired from its EXIT trap on ANY non-zero gather exit — a signal mid-gather, a vanished
  # $BATS_RUN_TMPDIR trace file. `bats-gather-tests` is bats' own internal command, never a test in
  # any suite, and that `1..1` is a constant with nothing to do with how many tests the file holds.
  # Measured instance: the 120s budget killed tests/cc-reaper.bats (88 tests, 132s standalone,
  # GREEN on that tree), the exoneration re-run's gather was cut, and the manufactured `not ok` was
  # read as "the re-run named a failure" ⇒ exit 6, "a VERDICT about your diff: fix it, do not retry
  # unchanged". Nothing about the diff had failed. It is the same 6-vs-9 conflation LAND_PIPELINE_V2
  # was built to remove (f8e40b4c577d / 9c5d0ba74e79) in a narrower form: not a cut with NO signal,
  # but a cut that MANUFACTURES one — which is worse, because the zero-not-ok rule cannot see it.
  #
  # TWO LEGS, and they are cut separately so neither can hide the other's regression:
  local log="$1" known="${2:-0}" f="${3:-the suite}" n plan
  n="$(grep -c '^not ok' "$log" 2>/dev/null || true)"; n="${n:-0}"
  [[ "$n" -eq 0 ]] && { printf '0\n'; return 0; }
  # LEG A — THE COLLECTOR NAMING ITSELF. Exact upstream literal, and gated on being the SOLE
  # `not ok`: the gather aborts before any test runs, so this line can never legitimately share a
  # run with real per-test verdicts. Anything alongside it stays a verdict (the safe direction).
  if [[ "$n" -eq 1 ]] && grep -qE '^not ok [0-9]+ bats-gather-tests[[:space:]]*$' "$log" 2>/dev/null; then
    echo "⚠ gate: $f — discarding 1 'not ok': it names bats' own collector (bats-gather-tests), not a test in this suite. The gather was cut before it could enumerate the file; that line is a HARNESS ARTIFACT, not a verdict." >&2
    printf '0\n'; return 0
  fi
  # LEG B — THE PLAN CONTRADICTS THE FILE'S OWN SIZE. A run claiming this file holds fewer tests
  # than another run of the SAME file just proved it holds never gathered them, so no per-test line
  # in it can be trusted. Version-independent, so it still holds if upstream renames leg A's literal.
  # THE COUNT COMES FROM AN OBSERVED PLAN, NEVER A STATIC PARSE OF THE .bats SOURCE — measured, not
  # assumed: `grep -c '^@test'` OVER-counts on 3 of this corpus's 299 suites (git-identity-lint 30
  # vs 17, bats-shellcheck-lint 28 vs 24, qos-chokepoint 43 vs 40), because those suites write
  # FIXTURE .bats files in heredocs with `@test` at column 0 and bats does not count those. An
  # over-count fires this leg on a HEALTHY plan and demotes a real RED to a cut — the one direction
  # this split must never fail in. Two plans for one file cannot disagree unless a run is broken.
  plan="$(tap_plan "$log")"
  if [[ -n "$plan" && "$known" -gt 0 && "$plan" -lt "$known" ]]; then
    echo "⚠ gate: $f — discarding $n 'not ok': this run planned $plan test(s) for a file just proven to hold $known. A plan that contradicts the file's own size proves the harness never gathered it; nothing it printed is a verdict." >&2
    printf '0\n'; return 0
  fi
  printf '%s\n' "$n"
}

run_scoped_suite() {  # $1=suite file $2=newline-list of DIRECT suites
                      # → 0 green · 1 RED (a named failure) · 2 KILLED (cut twice — NO verdict)
  # FLAKE EXONERATION: a suite that fails and then passes on ONE re-run in a fresh TMPDIR was
  # environmental (tmp collision / load), UNLESS it is a DIRECT suite of this change —
  # intermittence in code you are landing is a FINDING, not a flake. Never silent: every
  # exoneration is appended to postland/flakes.jsonl for the flake-rate denominator.
  #
  # RETURN 2 = KILLED is Phase 1's one design step (docs/plans/GATE_ARCHITECTURE_PLAN.md §3).
  # This function is now the FULL tier's runner too, so collapsing "cut twice" into the same 1
  # that means "a test failed" would silently undo c605a2e: the caller could no longer exit 9,
  # and every machine-wide cut would go back to reading as "your code is broken" — the middle
  # link of the 2026-07-26 runaway (kills → "RED" → lands fail → items re-block → the dispatcher
  # retries → more load → more kills). The two tiers now share ONE discriminator, so they cannot
  # disagree about what a cut is.
  # DISCRIMINATOR = c605a2e's, unchanged: the TAP BODY, never the exit code. bats masks the
  # signal (bats:517-524 pipes bats-exec-suite through bats_test_count_validator under pipefail),
  # so a SIGKILLed suite surfaces as plain `1`, never 137/143.
  # PRECEDENCE: a named `not ok` in EITHER run outranks a cut in the other — a verdict always
  # beats a non-verdict, and softening a real failure into "retry when quieter" is the one
  # direction this split must never fail in.
  local f="$1" direct="$2" td rc1 rc2 fdir log sig notok1 notok2 plan1 plan2 known
  # tee (not capture-then-print): the failing run stays LIVE on stderr while its output is kept,
  # so the ledger can record WHAT failed — a bare "it flaked" line is unactionable.
  log="$(mktemp)"
  gate_bats "$f" 2>&1 | tee "$log" >&2; rc1="${PIPESTATUS[0]}"
  if [[ "$rc1" -eq 0 ]]; then rm -f "$log"; return 0; fi
  sig="$(grep -m1 -aE '^not ok|Terminated|Killed|signal|timed? ?out' "$log" 2>/dev/null | sed 's/["\]//g' | cut -c1-160)"
  [[ -z "$sig" ]] && sig="exit $rc1"
  plan1="$(tap_plan "$log")"
  notok1="$(tap_named_failures "$log" "" "$f")"     # leg B is inert here: nothing to compare to yet
  if [[ "$notok1" -gt 0 ]]; then
    rm -f "$log"
    echo "↻ gate: $f RED — $notok1 failing test(s); one exoneration re-run in a fresh TMPDIR…" >&2
  elif [[ -n "${SMOKE_DEADLINE:-}" && "$(date +%s)" -ge "$SMOKE_DEADLINE" ]]; then
    # THE BUDGET IS ALREADY SPENT ⇒ DO NOT RE-RUN AT ALL, and this is the structural half of the
    # fix above. gate_bats floors an already-passed deadline at a 1s bound (deliberately: nothing
    # may start unbounded). A 1s bats is not an exoneration attempt — it is a GUARANTEED second
    # cut, and, per leg A, a cut that can manufacture a `not ok` out of its own truncated gather.
    # That is the generator: the smoke budget kills a suite, and the re-run it triggers is the
    # thing that mints the false verdict. There is no budget left to earn a verdict with, so say
    # that instead of spending a fork to learn it. Strictly better than what it replaces — the old
    # path reached this same rc 2 in the good case and exit 6 in the bad one.
    record_gate_cut "$rc1" "$log" "$f"
    rm -f "$log"
    echo "⛔ gate: GATE-KILLED: $f — cut by the smoke budget (exit $rc1, ZERO 'not ok') with the budget SPENT: an exoneration re-run gets gate_bats' 1s floor bound, which cannot earn a verdict and can manufacture one. It is NOT a red and NOT evidence about your tree. Override: SHIP_LAND_SMOKE_BUDGET_S." >&2
    return 2
  else
    rm -f "$log"
    echo "↻ gate: $f exited $rc1 with ZERO 'not ok' — CUT, not RED. One re-run in a fresh TMPDIR…" >&2
  fi
  # NO SHED-BEFORE-RETRY. v1 slept here until load fell below a ceiling, on the theory that a
  # re-run under the same sustained load is the same experiment, not a retry. True — and yet the
  # sleep was strictly worse than the weak retry: it is what multiplied a per-call bound across a
  # per-suite loop into hours of "bounded" waiting, and the smoke's ONE wall budget is now the
  # thing that must not be spent on sleeping. The environment change v1 wanted is delivered
  # structurally instead: a fresh TMPDIR here, and load shedding as a SKIP of the whole smoke.
  # CAPTURE THE RE-RUN'S TAP TOO — c605a2e's own lesson, applied to the per-file runner. Without
  # it "failed twice" cannot say WHICH twice, and a cut-then-real-failure would be handed to the
  # caller as a retryable non-verdict at exactly the moment the answer decides what to do next.
  td="$(mktemp -d)"; log="$(mktemp)"
  TMPDIR="$td" gate_bats "$f" 2>&1 | tee "$log" >&2; rc2="${PIPESTATUS[0]}"
  rm -rf "$td" 2>/dev/null || true
  if [[ "$rc2" -ne 0 ]]; then
    # THE KNOWN COUNT IS THE LARGER OF THE TWO PLANS — the only run that can be wrong about a
    # file's size is one that failed to gather it, and gathering cannot invent tests.
    plan2="$(tap_plan "$log")"
    known="${plan1:-0}"; [[ "${plan2:-0}" -gt "$known" ]] && known="$plan2"
    notok2="$(tap_named_failures "$log" "$known" "$f")"
    if [[ "$notok1" -eq 0 && "$notok2" -gt 0 ]]; then
      rm -f "$log"
      echo "✗ gate: bats RED: $f — $notok2 failing test(s) on the re-run (the first run was cut)" >&2
      return 1
    fi
    if [[ "$notok1" -gt 0 || "$notok2" -gt 0 ]]; then
      rm -f "$log"; echo "✗ gate: bats RED: $f (failed twice)" >&2; return 1
    fi
    record_gate_cut "$rc2" "$log" "$f"
    rm -f "$log"
    echo "⛔ gate: GATE-KILLED: $f — cut TWICE (exit $rc1 then $rc2, ZERO 'not ok' both times). It never earned a verdict, so it is NOT a red and NOT evidence about your tree." >&2
    return 2
  fi
  rm -f "$log"
  # THE DIRECT CARVE-OUT, and it is keyed on `notok1` — a NAMED failure in the first run — not on
  # "the first run was non-zero". Its rule is "intermittence in code you are landing is a FINDING,
  # not a flake", and a CUT is not intermittence: the first run earned no verdict at all (a peer's
  # pkill, a starved fork, our own wall bound firing at rc 124), so there is nothing to convict.
  # v1 conflated the two and got away with it because only a minority of suites were ever direct.
  # v2 cannot: the SMOKE passes its own suite list as the direct set, so EVERY smoke suite is
  # direct, and the per-child `timeout` deliberately manufactures cuts on a slow-but-green suite.
  # Unkeyed, this branch would turn "the box was busy for 30s" into exit 6 on a green tree — R6's
  # "a non-verdict is never a red" broken at the exact point v2 made it most likely to fire.
  # A named failure that vanishes on re-run is STILL red here; that fence is untouched.
  if [[ "$notok1" -gt 0 ]] && printf '%s\n' "$direct" | grep -qxF -- "$f"; then
    echo "✗ gate: bats RED: $f — pass-on-retry in a DIRECT suite of this change; intermittence in changed code is a finding, not a flake." >&2
    return 1
  fi
  fdir="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
  mkdir -p "$fdir" 2>/dev/null || true
  printf '{"ts":"%s","file":"%s","sha":"%s","phase":"land-gate","outcome":"pass-on-retry","signal":"%s","loadavg":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$f" "$(git rev-parse --short HEAD 2>/dev/null || echo '?')" \
    "$sig" "$(uptime 2>/dev/null | sed 's/.*averages*: //' | awk -F'[, ]+' '{print $1}')" \
    >> "$fdir/flakes.jsonl" 2>/dev/null || true
  echo "✓ gate: $f EXONERATED (green on re-run; ${notok1:-0} named failure(s) in the first run) — logged to flakes.jsonl" >&2
  return 0
}

stamp_gate_green() {  # gate-green asserts "the FULL suite proved THIS tree" — its consumers
  # (boundary-handoff.sh:122, wrap-ledger.sh:79) read it exactly that way, so a run that did not
  # prove it must leave the marker STALE rather than overstate; stale ⇒ they degrade correctly
  # (abstain / n/a).
  # IN v2 THIS IS ALWAYS THE NO-OP BRANCH — GATE_EFFECTIVE_FULL is pinned to 0 (§4.1), because the
  # land never runs the full suite and the verifier is now the marker's single writer (§4.2). The
  # function survives, and its call sites survive, so there is exactly ONE place where "may a land
  # claim the full suite?" is decided, and it answers no out loud on every land. Deleting it would
  # scatter that decision back across three call sites the next time someone is tempted.
  if [[ "${GATE_EFFECTIVE_FULL:-0}" != "1" ]]; then
    echo "→ gate[$LANE]: gate-green NOT advanced — a land makes no full-suite claim; the post-land verifier owns that marker." >&2
    return 0
  fi
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green" 2>/dev/null || true
}

run_gate() {  # $1=range → 0 green / 1 red
  local range="$1" p rc=0 HERM_LINT SELFPATH_LINT
  # GATE_EFFECTIVE_FULL is pinned at 0: a land makes no full-suite claim in EITHER lane, so
  # stamp_gate_green self-noops and the verifier stays the marker's only writer (§4.2).
  GATE_EFFECTIVE_FULL=0; SELECTED_N=-1; GATE_RED=0; GATE_KILLED=0
  local shellfiles=() pyfiles=()
  while IFS= read -r -d '' p; do
    [[ -z "$p" ]] && continue
    # skip paths removed at HEAD: git diff --name-only lists deletions, but linting the now-absent
    # path (shellcheck / py_compile) exits non-zero → gate RED, blocking EVERY file-removal land
    # (the deleted-*.sh gate, backlog b452/1bc4). -e mirrors the repo-root-relative resolution the
    # linters below already rely on (gate runs at repo root on a clean HEAD).
    [[ -e "$p" ]] || continue
    is_shell_file "$p" && shellfiles+=("$p")
    is_python_file "$p" && pyfiles+=("$p")
  done < <(git diff --name-only -z "$range" 2>/dev/null)

  if [[ ${#shellfiles[@]} -gt 0 ]]; then
    echo "→ gate: shellcheck + bash -n on ${#shellfiles[@]} shell file(s)" >&2
    shellcheck "${shellfiles[@]}" >&2 || { echo "✗ gate: shellcheck RED" >&2; rc=1; GATE_RED=1; }
    for p in "${shellfiles[@]}"; do
      bash -n "$p" 2>&1 >&2 || { echo "✗ gate: bash -n RED: $p" >&2; rc=1; GATE_RED=1; }
    done
  fi
  if [[ ${#pyfiles[@]} -gt 0 ]]; then
    echo "→ gate: py_compile on ${#pyfiles[@]} python file(s) (incl. extensionless-by-shebang)" >&2
    python3 -m py_compile "${pyfiles[@]}" >&2 || { echo "✗ gate: py_compile RED" >&2; rc=1; GATE_RED=1; }
  fi

  # ── test-hermeticity ratchet — BEFORE the bats block, in EVERY scope (~1s) ──────────────────
  # The ratchet already existed, but ONLY as tests/test-hermeticity-lint.bats, which made it
  # post-hoc detection rather than a landing gate. Two independent holes let a leak land twice in
  # one session (cc-relogin.bats → 469e654, handoff-selfclose-teammate-gate.bats → 828816d), each
  # a 2-line fix whose whole cost was detection latency and fleet-wide blast radius:
  #   1. SCOPE. The committed default is `scoped`, and gate-select maps that suite from exactly one
  #      edge — scripts/test-hermeticity-lint.sh. So ADDING tests/foo.bats never selects the
  #      ratchet (verified: gate-select on 828816d picks 58 suites, not this one). The author's own
  #      land could not see the breach it was creating.
  #   2. POSITION. In a FULL run it sits at test ~1706 of ~1707, and a full gate that gets
  #      SIGKILLed by machine-wide contention dies long before reaching it.
  # So the leak landed, and every LATER lander whose gate did reach 1706 paid a ~40-minute gate to
  # be told about someone else's file. Running the lint here inverts that: scope-independent, ~1s,
  # and it names the file to the session that wrote it — un-landable at the source instead of
  # fleet-blocking after the fact.
  #
  # Resolved repo-root-relative, NOT from SCRIPT_DIR: the tree being landed must be gated by its
  # OWN ratchet + allowlist (a land that legitimately deletes an allowlist line is then judged by
  # the script it ships). A repo with no ratchet has nothing to enforce; deleting ours stays loud
  # via tests/test-hermeticity-lint.bats, which execs it by path.
  #
  # FAIL-FAST (return, not rc=1-and-continue) is deliberate and not merely about latency: a suite
  # that does not fixture $HOME reads AND writes the operator's live ~/, so every other result in
  # the same bats run is contaminated. There is no value in spending 40 minutes collecting them.
  HERM_LINT="${SHIP_LAND_HERM_LINT:-scripts/test-hermeticity-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$HERM_LINT" ]]; then
    # OWN-SCOPE (2026-07-27, GATE_ARCHITECTURE_PLAN §9). The paragraph above is the ORIGINAL
    # rationale and it was correct until Phase 2a: an unfixtured suite contaminated the run, so
    # stopping the whole corpus was right. `d9b934ee` now clones $HOME per gate, so a leak dirties
    # the CLONE. What remained was a fleet-wide hard stop with no upside — measured this session, a
    # DOCS-ONLY land was refused by five leaking suites it does not touch. The ratchet still binds
    # absolutely on suites THIS land changes (its actual rule: do not ADD a leak); everything else
    # is reported and stepped over. Whole-tree strictness is still enforced off the critical path
    # by the postland net, which passes no own-set.
    local own=""
    if [[ "${SHIP_LAND_HERM_OWN_SCOPE:-on}" != "off" ]]; then
      # Basenames are matched, so a path form is fine. Failure to resolve the range yields an EMPTY
      # own-set, which the lint treats as STRICT — the fail-closed direction, never fail-open.
      #
      # THE PATHSPEC IS THE GATE'S SCOPE, and it must list every population the lint judges. It was
      # `tests/*.bats` alone until rule 4 (embedded selftests) landed, whose population is the TOOL
      # files below. Left unwidened, a land that adds a colliding selftest to bin/ produces an
      # own-set that does not contain it, the lint reports it `collides?` — advisory — and the land
      # goes through: the rule would have been detection, never a gate (memory:
      # enforcement-must-live-at-the-chokepoint). A docs-only land still yields an EMPTY own-set and
      # still blocks on nothing, so the fix measured for GATE_ARCHITECTURE_PLAN §9 is preserved.
      own="$(git diff --name-only "$range" -- 'tests/*.bats' 'bin/*' 'scripts/*.sh' 'hooks/*.sh' 2>/dev/null || true)"
      [[ -n "$own" ]] && echo "→ gate: hermeticity own-scope — blocking on $(printf '%s\n' "$own" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: test-hermeticity ratchet (before bats — seconds, and it names the file)" >&2
    local herm_rc=0
    CC_HERM_OWN="$own" "$HERM_LINT" tests >&2 || herm_rc=$?
    # 2 is the lint's NON-VERDICT: a predicate that could not run, or a scan that found nothing to
    # judge. It says NOTHING about this tree, so it must not be dressed up as one — that is the
    # exact conflation gate_nonzero_code() exists to keep apart, and the lint's own message ends
    # "do not 'fix' any suite on it". Routing it to GATE_KILLED yields the retryable 9; before rule
    # 4 the only exit-2 paths were an unusable scan dir and a killed predicate, and both landed here
    # as "✗ RED — fix the file named above" with no file named.
    if (( herm_rc == 2 )); then
      echo "⛔ gate: test-hermeticity could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with the files named above (if any). Re-run /ship when the box is quieter." >&2
      GATE_KILLED=1
      return 1
    fi
    if (( herm_rc != 0 )); then
      echo "✗ gate: test-hermeticity RED — something THIS LAND CHANGES runs against ambient state:" >&2
      echo "  a bats suite on the operator's live ~/, or an embedded selftest on a scratch path that" >&2
      echo "  is the same string on every run (so two concurrent runs collide). See the line above." >&2
      echo "  Not running bats: an unfixtured suite mutates live state, so the whole run's results" >&2
      echo "  would be untrustworthy. Fix the file named above (2 lines), then re-run /ship." >&2
      # A REAL verdict, never a non-verdict: the ratchet names a file and is deterministic, so it
      # must exit 6 (fix your tree) and never 9 (GATE-KILLED, "re-run when the box is quieter").
      # Without this flag a bats CUT elsewhere in the same run could soften it into a retryable 9.
      GATE_RED=1
      return 1
    fi
  fi

  # ── wall-clock time-bomb ratchet (GATE_ARCHITECTURE_PLAN §9) ──────────────────────────────────
  # Same shape and same own-scope contract as the hermeticity ratchet above, for the second
  # DETERMINISTIC blocker class: a fixture that seeds a FUTURE absolute date silently changes
  # meaning as the clock advances and takes the fleet's gate down on a calendar boundary with no
  # code change (2026-07-27T00:00Z, four tests, every lander). Cheap (a grep over tests/), names the
  # file, and deterministic — so like the ratchet it is a REAL verdict: exit 6, never a retryable 9.
  WALL_LINT="${SHIP_LAND_WALL_LINT:-scripts/test-walltime-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$WALL_LINT" ]]; then
    local wown=""
    if [[ "${SHIP_LAND_WALL_OWN_SCOPE:-on}" != "off" ]]; then
      wown="$(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)"
    fi
    echo "→ gate: wall-clock time-bomb ratchet (future absolute dates in fixtures)" >&2
    if ! CC_WALLTIME_OWN="$wown" "$WALL_LINT" tests >&2; then
      echo "✗ gate: wall-clock RED — a fixture THIS LAND CHANGES seeds a future absolute date." >&2
      echo "  Seed relative to now instead; the file and dates are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── git-identity escape ratchet (2026-08-05) ──────────────────────────────────────────────────
  # Same own-scope contract as the two ratchets above, for a blocker class whose blast radius is the
  # widest of the three: `git -C ""` is a documented NO-OP, so a fixture doing
  # `git -C "$dir" config user.email t@t` with `$dir` empty writes the TEST identity into whatever
  # repo the process is standing in. This checkout is ~100 linked worktrees over ONE .git/config, so
  # a single such call re-authors every session on the box — 9 commits on this trunk and 214 on
  # reso-management-app are authored `t <t@t>` (docs/research/git-identity-leak-2026-08-05.md).
  #
  # It belongs HERE for the reason the hermeticity ratchet documents: enforced only by its own suite
  # it is post-hoc DETECTION, and gate-select maps that suite from exactly one edge — the lint —
  # so ADDING a fixture never selects it and the author's own land cannot see the breach it creates
  # (memory: enforcement-must-live-at-the-chokepoint). Sub-second, scope-independent, and it names
  # file and line to the session that wrote them.
  #
  # Deterministic and it names a file, so like its siblings it is a REAL verdict — exit 6, never a
  # retryable 9; exit 2 is its NON-VERDICT and must not be dressed up as a claim about the tree.
  GITID_LINT="${SHIP_LAND_GITID_LINT:-scripts/git-identity-lint.sh}"
  if [[ -x "$GITID_LINT" ]]; then
    local gown=""
    if [[ "${SHIP_LAND_GITID_OWN_SCOPE:-on}" != "off" ]]; then
      # The pathspec must list every population the lint judges, or a land that adds an escaping
      # write to bin/ produces an own-set without it, the lint reports it `identity?` — advisory —
      # and the land goes through: the rule would be detection, never a gate. Same widening the
      # hermeticity block took when rule 4 landed. A docs-only land still yields an EMPTY own-set
      # and still blocks on nothing.
      gown="$(git diff --name-only "$range" -- 'tests/*.bats' 'scripts/*.sh' 'bin/*' 2>/dev/null || true)"
      [[ -n "$gown" ]] && echo "→ gate: git-identity own-scope — blocking on $(printf '%s\n' "$gown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: git-identity escape ratchet (a fixture identity that can land in the caller's repo)" >&2
    local gitid_rc=0
    CC_GITID_OWN="$gown" "$GITID_LINT" >&2 || gitid_rc=$?
    if (( gitid_rc == 2 )); then
      echo "⛔ gate: git-identity-lint could not RUN (exit 2) — a NON-VERDICT, not a claim about your tree." >&2
      echo "  Nothing is wrong with the files named above (if any). Re-run /ship when the box is quieter." >&2
      GATE_KILLED=1
      return 1
    fi
    if (( gitid_rc != 0 )); then
      echo "✗ gate: git-identity RED — a file THIS LAND CHANGES can write its test identity into the" >&2
      echo "  caller's repo. ~100 worktrees here share ONE .git/config, so that re-authors every" >&2
      echo "  session on the box. Guard the ARGUMENT (\"\${1:?}\" or a literal suffix) — for the no-\`-C\`" >&2
      echo "  shape a \`||\`-chain alone is inert, because an empty path makes the cd SUCCEED." >&2
      echo "  The file, the line, and the accepted forms are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── UTC timestamp-contract ratchet (a15/M4) ───────────────────────────────────────────────────
  # Third deterministic blocker class, same own-scope contract as the two ratchets above. A stamp
  # whose format ends in a literal `Z` ASSERTS UTC; if its `date` call has no -u it carries local
  # time, and since every consumer here compares stamps against a `date -u` baseline (lexically in
  # jq, numerically after epoch conversion) one such producer shifts every downstream age gate by the
  # TZ offset. That is not hypothetical: cc-reaper's log() did exactly this and faked a "reaper
  # DORMANT" alarm against a reaper that had just run (fixed in b4e3c355).
  #
  # It belongs HERE and not only in its own bats suite for the reason the hermeticity ratchet
  # documents: a lint enforced solely by its own suite is post-hoc DETECTION, and gate-select will
  # not pick that suite up when the edited file is a producer rather than the lint. At the gate it is
  # scope-independent, sub-second, and names the file to the session that wrote it.
  #
  # --selftest runs alongside the scan: this lint's fixtures replay the real scar line byte-for-byte,
  # so it cannot scan itself (see the self-exclusion in lint_dir) and the selftest is what proves the
  # detector still discriminates. A ratchet whose own discrimination is unverified is not a gate.
  UTC_LINT="${SHIP_LAND_UTC_LINT:-scripts/utc-stamp-lint.sh}"
  if [[ -x "$UTC_LINT" ]]; then
    local uown=""
    if [[ "${SHIP_LAND_UTC_OWN_SCOPE:-on}" != "off" ]]; then
      # Paths are matched relative to the scan root, which is how the lint reports them.
      uown="$(git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*' 2>/dev/null | sed 's:^[^/]*/::' || true)"
      [[ -n "$uown" ]] && echo "→ gate: utc-stamp own-scope — blocking on $(printf '%s\n' "$uown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: UTC timestamp-contract ratchet (a Z suffix from a non-UTC clock)" >&2
    if ! "$UTC_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: utc-stamp-lint --selftest FAILED — the detector no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_UTC_OWN="$uown" "$UTC_LINT" >&2; then
      echo "✗ gate: UTC-stamp RED — a file THIS LAND CHANGES stamps a literal Z from a local clock." >&2
      echo "  Add -u to the date call (or emit %z instead of Z); the file and lines are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── bats dead-assertion ratchet (2026-07-31) ──────────────────────────────────────────────────
  # Fourth deterministic blocker class, same own-scope contract as the ratchets above. An assertion
  # errexit cannot reach is a silent no-op — the check runs, its false result is discarded, and the
  # test passes — because bats exempts `[[ ]]`, `(( ))` and `! cmd` from errexit in any position but
  # the body's last.
  #
  # It belongs HERE, and the corpus proved why four times in five hours. The ratchet already exists,
  # but only as tests/bats-assert-liveness.bats, which is REPO-WIDE: one non-final `[[ ]]` from any
  # session reds the entire corpus, and a red corpus means no GREEN stamp, which means deploy-live
  # has no cursor and the LIVE LAYER STALLS FOR EVERYONE until someone notices and sweeps. Detection
  # is post-land and ~3.2h away while the damage is immediate and global — and with trunk at ~15
  # commits/h, ~23-48 commits land inside a single verify window, so the sweep races the next
  # violation. On 2026-07-31 the ratchet went red four separate times (23 assertions, then 2, 6, 2),
  # each from a commit that landed while an earlier sweep was still in flight. That is a treadmill,
  # and moving the check to the chokepoint is what ends it: unlandable beats detected-later.
  #
  # Names file and line, deterministic — so like the ratchets above it is a REAL verdict: exit 6,
  # never a retryable 9.
  DEAD_LINT="${SHIP_LAND_DEAD_LINT:-scripts/bats-assert-liveness.py}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -f "$DEAD_LINT" ]]; then
    local dfind=""
    local -a dscan=()
    if [[ "${SHIP_LAND_DEAD_OWN_SCOPE:-on}" != "off" ]]; then
      # SCANS THE DIFF, NOT THE CORPUS — and the distinction is not academic. Measured on this box:
      # the whole-tree scan is 0.82s in the FOREGROUND but 20.3s in the Darwin background band this
      # gate actually runs in (a 25x tax, a one-way ratchet children inherit); restricted to a land's
      # own files it is 0.6s in-band. Sizing an always-run check by its idle cost is how it becomes
      # an off switch under load, which is the failure this whole ratchet exists to stop repeating.
      #
      # Own scope is also the fairness rule every ratchet above carries: a land answers for the files
      # it touches. Blocking on a pre-existing finding elsewhere would make one session's violation
      # every session's gridlock — the exact shared-fate failure being fixed, moved to the gate.
      while IFS= read -r f; do
        [[ -n "$f" && -f "$f" ]] && dscan+=("$f")   # a suite this land DELETES has nothing to scan
      done < <(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)
    else
      dscan=(tests/*.bats)
    fi
    if [[ ${#dscan[@]} -gt 0 ]]; then
      echo "→ gate: bats dead-assertion ratchet (${#dscan[@]} changed suite(s))" >&2
      # `|| true`: a missing python3 or an unreadable file yields NO verdict, never a fabricated one.
      dfind="$(python3 "$DEAD_LINT" --format text "${dscan[@]}" 2>/dev/null || true)"
      if [[ -n "$dfind" ]]; then
        printf '%s\n' "$dfind" >&2
        echo "✗ gate: dead-assertion RED — a test THIS LAND CHANGES asserts something errexit cannot reach." >&2
        echo "  Revive it:  python3 scripts/bats-assert-liveness-fix.py <file>" >&2
        echo "  Use the fixer, not a hand-edit: the right form is PER CLASS. A uniform ' || false' is" >&2
        echo "  WRONG for the whole 'A && <never-succeeds>' family — 'A && false' and its far commoner" >&2
        echo "  brace spelling 'A && { echo diag; false; }' — where BOTH branches then reach the" >&2
        echo "  appended false. The fixer rewrites those to '! A || <same RHS>', and DECLINES (exit 2," >&2
        echo "  line named, file untouched) rather than guess at a shape it cannot prove. A decline is" >&2
        echo "  YOUR hand-edit: verify it in BOTH directions with a mutant, never by the analyzer alone." >&2
        GATE_RED=1
        return 1
      fi
    fi
  fi

  # ── script-dir resolution ratchet (backlog ba715c49d522) ──────────────────────────────────────
  # Same own-scope contract as the ratchets above, guarding the seam THIS SCRIPT was the victim of.
  #
  # ~/.claude/{scripts,hooks,bin}/ are real directories of PER-FILE SYMLINKS into the checkout, so
  # through the live layer `dirname "$0"/..` is ~/.claude — which has no tests/, no docs/, no .git. A
  # script deriving its repo root that way does not fail; it reads the WRONG TREE or silently no-ops.
  # This gate ran the full ~1630-test suite on every live-path land for exactly that reason
  # (f8e40b4c577d): GATE_SELECT resolved to ~/.claude/scripts/gate-select.sh, which had no symlink
  # yet, so the selector went missing and the policy went unsourced ⇒ "treating as FULL (fail-closed)"
  # on every land, unserialized across every landing worktree. That is the amplifier in the
  # 2026-07-26 machine-wide gate runaway, and it is why the degradation looked INTERMITTENT: run from
  # a worktree this script found its siblings and went scoped; run through the live symlink it did
  # not. deploy-parity-assert.sh (816015ecb30b) and test-hermeticity-lint.sh had the same shape.
  #
  # It belongs at the gate and not only in its own suite for the reason the ratchets above document:
  # a lint enforced solely by its own suite is post-hoc DETECTION, and gate-select will not pick that
  # suite up when the edited file is a PRODUCER rather than the lint (memory:
  # enforcement-must-live-at-the-chokepoint). Sub-second, scope-independent, and it names the file to
  # the session that wrote it — while the alternative is a bug that only ever shows up in production,
  # on the live path, to someone who did not write it.
  #
  # The 26 files carrying the shape today are grandfathered BY PATH and all latent; the rule binds
  # only on new code. Own-scope keeps one author's omission from becoming every author's outage.
  SELFPATH_LINT="${SHIP_LAND_SELFPATH_LINT:-scripts/self-path-lint.sh}"
  if [[ -x "$SELFPATH_LINT" ]]; then
    local spown=""
    if [[ "${SHIP_LAND_SELFPATH_OWN_SCOPE:-on}" != "off" ]]; then
      # This lint scans from the repo ROOT and reports repo-relative paths, so the diff needs no
      # component strip (unlike the utc own-set above, which is layer-relative).
      spown="$(git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*' 2>/dev/null || true)"
      [[ -n "$spown" ]] && echo "→ gate: self-path own-scope — blocking on $(printf '%s\n' "$spown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: script-dir resolution ratchet (a repo root derived from an unresolved \$0)" >&2
    if ! "$SELFPATH_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: self-path-lint --selftest FAILED — the detector no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_SELFPATH_OWN="$spown" "$SELFPATH_LINT" >&2; then
      echo "✗ gate: self-path RED — a file THIS LAND CHANGES derives a path via '..' from an" >&2
      echo "  unresolved \$0/\$BASH_SOURCE. Resolve the symlinks first (_resolve_self above); the" >&2
      echo "  file and lines are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── Unattended-PATH ratchet (bare-name binaries on launchd + hook paths, 2026-08-06) ──────────
  # A bare command name resolves against whatever PATH the caller has. In the operator's shell that
  # is a rich PATH with Homebrew on it, so the code always looks right; on a launchd job or a hook
  # fired inside a spawned session the name may not exist, and the 127 is usually unchecked. Worst
  # available polarity: GREEN where a human tests it, DEAD where it runs. It recurred five times as
  # instances (e6de2e15's four sites, the bare-kitty fix behind bin/cc-kitty-bin) before anyone
  # asserted the invariant — fixing instances is O(n) forever, asserting it is O(1).
  #
  # It belongs at the gate rather than only in its own suite for the reason the ratchets above
  # document: gate-select picks suites by the files a land touches, so a land ADDING a hook would
  # never select tests/unattended-path-lint.bats (memory: enforcement-must-live-at-the-chokepoint).
  # ~6s, scope-independent, and it names the file to the session that wrote it — while the
  # alternative is a no-op actuator or a fabricated instrument reading that shows up only in
  # production, on the scheduled path, to someone who did not write it.
  #
  # The 16 sites carrying the shape today are grandfathered BY FILE+BINARY, so the rule binds only on
  # new code; own-scope keeps one author's omission from becoming every author's outage.
  UNATTENDED_LINT="${SHIP_LAND_UNATTENDED_LINT:-scripts/unattended-path-lint.sh}"
  if [[ -x "$UNATTENDED_LINT" ]] && { [[ -d hooks ]] || [[ -d launchd ]]; }; then
    local upown=""
    if [[ "${SHIP_LAND_UNATTENDED_OWN_SCOPE:-on}" != "off" ]]; then
      # This lint scans from the repo ROOT and reports repo-relative paths, so the diff needs no
      # component strip. The pathspec must list every population the lint judges, or a land that adds
      # a bare-name call to one of them produces an own-set without it and the finding degrades to
      # advisory.
      # 'tests/*' is here because the lint gained a THIRD population — the bats corpus the two
      # scheduled runners execute. Omitting it would be the exact degradation the paragraph above
      # warns of: a land adding a bare /sbin-only binary to a .bats file would build an own-set
      # without that file, the finding would drop to advisory, and it would land — which is how the
      # bare `md5` in cc-queue.bats C12 passed vacuously on every scheduled run.
      upown="$(git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*' 'launchd/*' 'tests/*' 2>/dev/null || true)"
      [[ -n "$upown" ]] && echo "→ gate: unattended-path own-scope — blocking on $(printf '%s\n' "$upown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: bare-name binaries on unattended paths (launchd jobs + hooks + the bats corpus)" >&2
    if ! "$UNATTENDED_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so" >&2
      echo "  its clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_UNATTENDED_OWN="$upown" "$UNATTENDED_LINT" >&2; then
      echo "✗ gate: unattended-path RED — a file THIS LAND CHANGES invokes a binary by bare name that" >&2
      echo "  is unreachable on the PATH it will actually run with. Resolve it absolutely, or harden" >&2
      echo "  PATH at the top of the file; the file, line and binary are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── Permission-gate ratchet (UNBOUNDED gates on the actuation paths, 2026-08-07) ──────────────
  # A gate that refuses is a STANDING STATE, and a standing state generates no event, so nobody is
  # told. deploy-live's green-stamp gate — `no GREEN stamp in the newest N commits ⇒ die` — was a
  # sound predicate that, once the verifier stopped stamping, emitted 545 IDENTICAL refusals and
  # froze the live layer for days while every one of them read as normal. The fix (dcf2f11a) did not
  # loosen the predicate; it gave it a CLOCK.
  #
  # The class reproduces because the blame is asymmetric (inertness-generator-2026-08-07 §2.3): an
  # advance that breaks something has an author — the gate that let it through — while a refusal
  # that strands 104 commits has none, so every individual author is correct to add one more
  # "proceed only if X holds". §6 F3 predicts it keeps happening "unless a land-chokepoint lint
  # forbids new affirmative-permission predicates on actuation paths"; §9 narrowed the law after the
  # deploy lane's reply, because some gates must exist: no gate may be UNBOUNDED, and every
  # affirmative-permission predicate must carry a finite budget whose expiry converts the standing
  # state into an EVENT (advance+page, escalate, or revert).
  #
  # It belongs at the gate rather than only in its own suite for the reason the ratchets above
  # document: gate-select picks suites by the files a land touches, so a land ADDING a gate to a
  # brand-new scripts/deploy-*.sh would never select tests/permission-gate-lint.bats (memory:
  # enforcement-must-live-at-the-chokepoint). Membership is by GLOB for the same reason — the
  # reproduction is NEW gates in NEW files, and a hand-maintained list would have to be edited by
  # the very person adding one.
  #
  # The ratchet is a PER-FILE COUNT, not a path allowlist: a path allowlist would exempt this file
  # wholesale, and with it every new gate leg anyone adds to it — including this one. Own-scope
  # keeps one author's undeclared gate from becoming every author's hard stop.
  PERMGATE_LINT="${SHIP_LAND_PERMGATE_LINT:-scripts/permission-gate-lint.sh}"
  if [[ -x "$PERMGATE_LINT" ]]; then
    local pgown=""
    if [[ "${SHIP_LAND_PERMGATE_OWN_SCOPE:-on}" != "off" ]]; then
      # This lint scans from the repo ROOT and reports repo-relative paths, so the diff needs no
      # component strip. The pathspec must cover every population the lint judges (its actuation
      # globs today are install.sh and scripts/*) — a land that adds a gate to a file this pathspec
      # misses would build an own-set without it, the finding would drop to advisory, and it would
      # land. If CC_PERMGATE_SET ever reaches another directory, widen this line in the same diff.
      pgown="$(git diff --name-only "$range" -- 'install.sh' 'scripts/*' 2>/dev/null || true)"
      [[ -n "$pgown" ]] && echo "→ gate: permission-gate own-scope — blocking on $(printf '%s\n' "$pgown" | grep -c .) file(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: unbounded permission gates on the actuation paths (install · deploy · land)" >&2
    if ! "$PERMGATE_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: permission-gate-lint --selftest FAILED — the detector no longer discriminates, so" >&2
      echo "  its clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_PERMGATE_OWN="$pgown" "$PERMGATE_LINT" >&2; then
      echo "✗ gate: permission-gate RED — a file THIS LAND CHANGES gained a guard-refusal on an" >&2
      echo "  actuation path with no declared bound (or its ratchet line is stale). Give the gate a" >&2
      echo "  budget whose expiry converts the standing state into an EVENT, then declare it with a" >&2
      echo "  \`gate_bounded: <what expires, and into what>\` marker; the lines are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── Chromium-bundle ratchet (operator-reported Dock strobe, 2026-07-30) ───────────────────────
  # The full playwright Chromium.app bundle checks in with LaunchServices on EVERY launch even
  # under --headless, so the Dock paints a launching-app tile for the ~1.3s each process lives. A
  # per-shot screenshot loop therefore strobes the operator's Dock for the whole run — which is
  # exactly what scripts/banner-shots.sh did. Measured against a 0-launch idle baseline of 0:
  # full bundle x20 -> 22 app CHECKINs / 24s; chrome-headless-shell x20 -> 0 CHECKINs / 5s.
  #
  # It belongs at the gate rather than only in its own suite for the reason the ratchets above
  # document: gate-select picks suites by the files a land touches, so a NEW screenshot script
  # would never select tests/chromium-bundle-lint.bats (memory:
  # enforcement-must-live-at-the-chokepoint). This class is invisible to every other check —
  # nothing is slow, nothing is red, no test fails; it shows up only as an annoyance on the
  # operator's own screen, which is how it survives.
  #
  # --selftest runs alongside the scan, same contract as the siblings: a ratchet whose own
  # discrimination is unverified is not a gate.
  CHROMIUM_LINT="${SHIP_LAND_CHROMIUM_LINT:-scripts/chromium-bundle-lint.sh}"
  if [[ -x "$CHROMIUM_LINT" ]]; then
    local cbown=""
    if [[ "${SHIP_LAND_CHROMIUM_OWN_SCOPE:-on}" != "off" ]]; then
      cbown="$(git diff --name-only "$range" -- 'bin/*' 'hooks/*' 'scripts/*' 'tools/*' 2>/dev/null || true)"
    fi
    echo "→ gate: chromium-bundle ratchet (a headless screenshot path launching the full app bundle)" >&2
    if ! "$CHROMIUM_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: chromium-bundle-lint --selftest FAILED — the detector no longer discriminates," >&2
      echo "  so its clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_CHROMIUM_OWN="$cbown" "$CHROMIUM_LINT" >&2; then
      echo "✗ gate: chromium-bundle RED — a file THIS LAND CHANGES takes screenshots through the" >&2
      echo "  full Chromium.app bundle, which strobes the operator's Dock once per launch. Use" >&2
      echo "  resolve_headless_chrome from scripts/lib/cc-common.sh; the file is named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── .bats shellcheck ratchet (backlog 19a44d4e2e75) ───────────────────────────────────────────
  # Fifth deterministic blocker class, same own-scope contract as the four above — with one
  # difference that is the whole point: the own-set is LINE-scoped, not file-scoped.
  #
  # The hole it closes: is_shell_file() above matches `*.sh|*.bash` or a shell shebang, and a bats
  # file's shebang is `#!/usr/bin/env bats`. It matches neither arm, so this gate has never linted a
  # single one of the 189 suites — the COVERAGE mechanism behind the 226 dead assertions
  # (docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md). The debt was not merely present, it was
  # structurally invisible.
  #
  # Why not simply widen is_shell_file(), which is what the item prescribed: `bash -n` FAILS ON ALL
  # 189 SUITES (`@test "x" { … }` is not bash — "syntax error near unexpected token `}'"), and every
  # is_shell_file() match is handed to BOTH shellcheck and `bash -n` above. Widening the predicate
  # turns the gate red for every land that touches a test file. The two tools do not share a domain,
  # so bats gets its own pass rather than a wider predicate.
  #
  # Why LINE-scoped where the siblings are file-scoped: 143 of 189 suites carry a finding today, so
  # blocking on the FILES in a diff would refuse roughly one land in three over inherited debt — the
  # fleet-wide hard stop own-scope exists to prevent. A file-level grandfather would instead exempt
  # those files forever, so a NEW finding in one would never fire. Per-line expresses the strictest
  # rule that is still free: you may not add a finding on a line you wrote. The lint derives the
  # own-set itself (`--own-lines <range>`) so the diff parsing lives in one tested place.
  #
  # --selftest runs alongside the scan, for the reason the UTC ratchet documents: a ratchet whose own
  # discrimination is unverified is not a gate. Its abort control replays a real prose-comment line
  # byte-for-byte and asserts that file's genuine defect goes UNSEEN.
  SC_BATS_LINT="${SHIP_LAND_BATS_SC_LINT:-scripts/bats-shellcheck-lint.sh}"
  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1 && [[ -x "$SC_BATS_LINT" ]] \
     && command -v shellcheck >/dev/null 2>&1; then
    local bown=""
    if [[ "${SHIP_LAND_BATS_SC_OWN_SCOPE:-on}" != "off" ]]; then
      # Failure to resolve the range yields an EMPTY own-set, which means "I wrote no line" ⇒
      # nothing blocks. That is the correct degradation HERE and the opposite of the siblings':
      # their strict fallback is free because their corpus is clean, whereas a strict whole-tree
      # run of this lint is 164 findings, i.e. a guaranteed outage on every land.
      bown="$("$SC_BATS_LINT" --own-lines "$range" 2>/dev/null || true)"
      [[ -n "$bown" ]] && echo "→ gate: bats-shellcheck own-scope — blocking on $(printf '%s\n' "$bown" | grep -c .) changed line(s); pre-existing findings advisory." >&2
    fi
    echo "→ gate: .bats shellcheck ratchet (this gate never linted a test file before)" >&2
    if ! "$SC_BATS_LINT" --selftest >/dev/null 2>&1; then
      echo "✗ gate: bats-shellcheck-lint --selftest FAILED — the lint no longer discriminates, so its" >&2
      echo "  clean verdict would mean nothing. Fix the lint before landing." >&2
      GATE_RED=1
      return 1
    fi
    if ! CC_BATS_SC_OWN="$bown" "$SC_BATS_LINT" tests >&2; then
      echo "✗ gate: bats-shellcheck RED — a line THIS LAND WROTE carries a shellcheck finding," >&2
      echo "  or a suite it touches aborts shellcheck entirely. Both are named above." >&2
      GATE_RED=1
      return 1
    fi
  fi

  # ── the test phase — SMOKE in the fast lane, the whole corpus only under the v1 kill switch ──
  # NOT gated on the statics rc above: an already-red land still runs the smoke, so the author gets
  # the lint error AND the failing test in ONE cycle. Same reasoning as run_corpus's no-fail-fast —
  # ≤120s on an already-doomed run buys every finding named at once instead of one per round-trip.
  local rbase direct
  # UNION SCOPE: FIRST_BASE..<this range's base> is the trunk delta siblings landed since our
  # FIRST gate — empty on round 1, non-empty on every stale-gate re-round / post-drop re-gate.
  # Derived from the range so every gate call site gets it for free.
  rbase="${range%%..*}"
  if [[ -n "$FIRST_BASE" && "$FIRST_BASE" != "$rbase" ]]; then EXTRA_RANGE="$FIRST_BASE..$rbase"; else EXTRA_RANGE=""; fi

  # The verifier's liveness is measured and ATTESTED here, and it decides NOTHING — see
  # postland_net_live for why v1's "inert ⇒ run the full corpus" was the amplifier itself.
  postland_net_live

  if ls tests/*.bats >/dev/null 2>&1; then
    if [[ "$LANE" = "v1" ]]; then
      if [[ "$IN_LAND_LOCK" = "1" ]]; then
        # The never-in-lock invariant binds in BOTH lanes. The kill switch restores the v1 PROOF,
        # never the v1 lock pathology (a 3h36m holder while every other lander queued behind it).
        echo "→ gate[v1/locked]: statics + ratchets only — no bats inside the land-lock, in either lane." >&2
      else
        direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
        [[ "$direct" = "FULL" ]] && direct=""   # "cannot decide" ⇒ exonerate nothing is unknown
        gate_home_setup
        run_corpus "$direct" || rc=1
      fi
    else
      run_smoke "$range" || rc=1
      SELECTED_N="$SMOKE_N"
    fi
  fi
  # Unconditional, and BEFORE the return so it runs on red and on GATE-KILLED alike — the EXIT trap
  # is only the backstop for a mid-gate `exit`. Both are no-ops when isolation fell open.
  gate_home_teardown
  return "$rc"
}

gate_nonzero_code() {  # $1=optional context → prints the operator line on stderr, echoes 6 or 9
  # THE SPLIT that 9c5d0ba74e79 asked for: a red is a claim ABOUT THE TREE; a kill is a claim about
  # the MACHINE. Same exit code for both taught every caller — the dispatcher included — to treat
  # "we ran out of machine" as "your code is broken", which is how a load spike turned into a
  # re-block/retry loop. GATE_RED wins a mixed run: a named failure outranks a non-verdict.
  if [[ "${GATE_KILLED:-0}" = "1" && "${GATE_RED:-0}" != "1" ]]; then
    echo "⛔ ship-land: GATE-KILLED${1:+ $1} — the gate died without earning a verdict, so this is NOT a red and NOT evidence about your tree. Nothing pushed; gate-green untouched; branch + backup ref intact. Re-run /ship when the box is quieter (exit 9)." >&2
    printf '9'
  else
    echo "✗ ship-land: GATE RED${1:+ $1} — not pushing." >&2
    printf '6'
  fi
}

# ---- unlocked reconcile + gate (one optimistic round; parallel across sessions) ----

unlocked_reconcile_and_gate() {  # $1=trunk $2=dry_run → sets GATE_BASE/GATE_HEAD globals;
                                 # exits internally on rebase-conflict(5) / gate-red(6) /
                                 # nothing-to-land(0) / --dry-run(0).
  local TRUNK="$1" DRY_RUN="$2"
  echo "→ ship-land[unlocked]: fetch + rebase + gate (statics + ratchets + bounded smoke) — no lock held" >&2
  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: fetch failed — using local origin/$TRUNK" >&2

  if ! git rebase "origin/$TRUNK" >&2; then
    echo "✗ ship-land: rebase onto origin/$TRUNK hit a conflict — resolve it, then re-run /ship. Rebase left in progress; backup ref intact." >&2
    exit 5
  fi

  GATE_BASE="$(git rev-parse "origin/$TRUNK")"
  [[ -z "$FIRST_BASE" ]] && FIRST_BASE="$GATE_BASE"   # round 1 anchors the union scope

  if [[ -z "$(git rev-list "$GATE_BASE..HEAD" 2>/dev/null)" ]]; then
    echo "✓ ship-land: nothing to land (origin/$TRUNK already contains HEAD)."
    exit 0
  fi

  if ! run_gate "$GATE_BASE..HEAD"; then
    local code; code="$(gate_nonzero_code)"
    # Post-fix gate-REDs were invisible in land.log (only the locked phase attested), leaving
    # flake-rate / gate-health claims without a denominator. Attest the outcome, then exit.
    # exit 9 attests as 9, so a land.log reader can subtract non-verdicts from the red denominator.
    attest_refs "$GATE_BASE"
    attest_land "n/a" "n/a" "clean" "$code"
    exit "$code"
  fi

  # gate-green: the call survives, the claim does not. stamp_gate_green self-noops in v2 (a land
  # proves no full suite), so this line's job is to say so ONCE, out loud, on the green path — the
  # marker's producer is the verifier now (§4.2), and boundary-handoff.sh:122 / wrap-ledger.sh:79
  # read it from there. See stamp_gate_green for why it is kept rather than deleted.
  stamp_gate_green

  if [[ "$DRY_RUN" = "1" ]]; then
    echo "→ ship-land --dry-run: reconciled onto origin/$TRUNK + gate GREEN; STOPPING before push (no lock taken — a dry run never queues a real land)."
    echo "  would push HEAD ($(git rev-parse --short HEAD)) → origin/$TRUNK:"
    git diff --stat "$GATE_BASE..HEAD"
    exit 0
  fi

  GATE_HEAD="$(git rev-parse HEAD)"
}

# ---- locked phase (re-exec'd under land-lock) ------------------------------

main_locked() {
  # We hold the land-lock from here on ⇒ IN_LAND_LOCK=1, which run_gate reads as its structural
  # ban on starting ANY bats suite (either lane). Everything under the lock is O(seconds).
  IN_LAND_LOCK=1
  # CAS mode ($3/$4 non-empty): the gate already ran GREEN, UNLOCKED, on exactly
  # (HEAD=GATE_HEAD, base=GATE_BASE). Hold the lock only for fetch-compare → push →
  # content-verify — the 2026-07-11 race window. A moved origin/HEAD ⇒ exit 42 (stale
  # gate, INTERNAL): the outer loop re-gates the new final tree unlocked.
  # FALLBACK mode ($3/$4 empty — SHIP_LAND_GATE_ROUNDS=0, or the optimistic rounds exhausted
  # under sustained contention): rebase + re-gate INSIDE the lock, but STATICS + RATCHETS ONLY.
  # v1 ran the full corpus here, and that is the single worst thing this script ever did: a held
  # machine-wide mutex plus a 20-53 min corpus produced a 3h36m lock holder while every other
  # lander queued behind it (and, when the corpus hung, a multi-day jam). Guaranteed progress is
  # still guaranteed — a held mutex stops further pipeline movement, so this round terminates —
  # it just no longer costs the fleet an hour to get it.
  local TRUNK="$1" DRY_RUN="$2" GATE_BASE="${3:-}" GATE_HEAD="${4:-}"
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

  echo "→ ship-land[locked]: last-moment fetch origin/$TRUNK" >&2
  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: fetch failed — using local origin/$TRUNK" >&2

  local LAND_BASE
  if [[ -n "$GATE_BASE" ]]; then
    local now_base now_head
    now_base="$(git rev-parse "origin/$TRUNK" 2>/dev/null || echo '?')"
    now_head="$(git rev-parse HEAD 2>/dev/null || echo '?')"
    if [[ "$now_base" != "$GATE_BASE" || "$now_head" != "$GATE_HEAD" ]]; then
      echo "↻ ship-land[locked]: STALE GATE — origin/$TRUNK or HEAD moved during the unlocked gate (base ${GATE_BASE:0:7}→${now_base:0:7}, head ${GATE_HEAD:0:7}→${now_head:0:7}). Releasing the lock; re-reconciling + re-gating the new final tree unlocked." >&2
      exit 42
    fi
    LAND_BASE="$GATE_BASE"
  else
    if ! git rebase "origin/$TRUNK" >&2; then
      echo "✗ ship-land: rebase onto origin/$TRUNK hit a conflict — resolve it, then re-run /ship. Rebase left in progress; backup ref intact." >&2
      exit 5
    fi

    LAND_BASE="$(git rev-parse "origin/$TRUNK")"
    if [[ -z "$(git rev-list "$LAND_BASE..HEAD" 2>/dev/null)" ]]; then
      echo "✓ ship-land: nothing to land (origin/$TRUNK already contains HEAD)."
      exit 0
    fi

    if ! run_gate "$LAND_BASE..HEAD"; then
      local code; code="$(gate_nonzero_code)"
      exit "$code"
    fi
    # Self-noops in v2 — see stamp_gate_green / unlocked_reconcile_and_gate.
    stamp_gate_green

    if [[ "$DRY_RUN" = "1" ]]; then
      echo "→ ship-land --dry-run: reconciled onto origin/$TRUNK + gate GREEN; STOPPING before push."
      echo "  would push HEAD ($(git rev-parse --short HEAD)) → origin/$TRUNK:"
      git diff --stat "$LAND_BASE..HEAD"
      exit 0
    fi
  fi

  # --- push + content-verify, with bounded auto-retry + rollback on a concurrent drop (T-P9-7) ---
  # A push can 'succeed' yet have its content dropped from the trunk by a concurrent rebase-land (the
  # 2026-07-11 incident class → land-verify FAIL). Rather than strand the operator on manual recovery
  # (the old bare exit-8), auto-reconcile onto the moved trunk (re-fetch + rebase + re-gate) and
  # re-push, up to SHIP_LAND_VERIFY_RETRIES times. Fail-closed + bounded:
  #   * an auto-retry rebase CONFLICT rolls back (git rebase --abort — never strand a half-applied tree)
  #     and exits 5 — UNLIKE the first rebase at the top of the pipeline, which is left in progress for a
  #     human who ran /ship interactively; an autonomous retry has no human to resolve it, so it rolls back.
  #   * exhausting the retries guarantees a clean, committed tree (backup ref ship/backup-* intact) → exit 8.
  # Scope: retry is triggered ONLY by a verify-fail. The FIRST push keeps its original semantics — a non-ff
  # there is a sibling beating us before we landed at all ⇒ exit 7, no retry. SHIP_LAND_VERIFY_RETRIES=0
  # restores the pre-T-P9-7 single-shot behavior (the kill switch).
  local MAX_RETRIES; MAX_RETRIES="${SHIP_LAND_VERIFY_RETRIES:-2}"
  local attempt=0 LANDED_HEAD

  attest_refs "$LAND_BASE"
  LANDED_HEAD="$(git rev-parse HEAD)"
  if ! git push origin "HEAD:$TRUNK" >&2; then
    echo "✗ ship-land: push to origin/$TRUNK REJECTED (non-fast-forward — a sibling beat you inside the window). Re-run /ship to re-fetch+rebase+re-verify. Backup ref intact." >&2
    exit 7
  fi

  while :; do
    git fetch origin "$TRUNK" 2>/dev/null || true
    if "$LAND_VERIFY" "$LAND_BASE..$LANDED_HEAD" "origin/$TRUNK" "$LANDED_HEAD"; then
      break   # ✓ every landed path present + content-identical on the trunk — landed for real
    fi

    # CONTENT-VERIFY FAILED — the push 'succeeded' but the content is not intact on the trunk.
    if [[ "$attempt" -ge "$MAX_RETRIES" ]]; then
      echo "✗ ship-land: post-push CONTENT-VERIFY FAILED after ${attempt} auto-retry attempt(s) — your paths are NOT intact on origin/$TRUNK (a concurrent rebase-land keeps dropping content — the 2026-07-11 incident class). Tree left clean; backup ref ship/backup-* holds your commit; recover + re-land." >&2
      rollback_clean
      attest_land "FAIL" "n/a" "clean" 8
      exit 8
    fi
    attempt=$(( attempt + 1 ))
    echo "↻ ship-land: content-verify failed (concurrent drop) — auto-retry ${attempt}/${MAX_RETRIES}: re-fetch + rebase onto origin/$TRUNK + re-gate + re-push…" >&2

    # reconcile onto the moved trunk (origin/$TRUNK is fresh from the loop-top fetch).
    if ! git rebase "origin/$TRUNK" >&2; then
      rollback_clean
      echo "✗ ship-land: auto-retry rebase onto origin/$TRUNK hit a conflict — rolled back to a clean tree; backup ref ship/backup-* intact. Resolve the conflict and re-run /ship." >&2
      attest_land "n/a" "n/a" "clean" 5
      exit 5
    fi
    LAND_BASE="$(git rev-parse "origin/$TRUNK")"
    attest_refs "$LAND_BASE"
    if [[ -z "$(git rev-list "$LAND_BASE..HEAD" 2>/dev/null)" ]]; then
      echo "✓ ship-land: after reconcile, origin/$TRUNK already contains HEAD — the drop self-healed (a sibling landed our content)."
      attest_land "ok" "n/a" "clean" 0
      exit 0
    fi
    if ! run_gate "$LAND_BASE..HEAD"; then
      local code; code="$(gate_nonzero_code "on the re-reconciled range")"
      echo "  (backup ref ship/backup-* intact — not re-pushing)" >&2
      attest_land "n/a" "n/a" "clean" "$code"
      exit "$code"
    fi
    stamp_gate_green

    attest_refs "$LAND_BASE"
    LANDED_HEAD="$(git rev-parse HEAD)"
    if ! git push origin "HEAD:$TRUNK" >&2; then
      # a sibling advanced trunk again inside the retry window — reconcilable. The next loop iteration's
      # verify fails (our head is not on the trunk) and drives another bounded reconcile; the attempt
      # counter still terminates a persistently-rejecting remote.
      echo "↻ ship-land: re-push non-ff inside the retry window — reconciling again next round." >&2
    fi
  done

  # --- discharge the rollback ref (STRANDED_EXPOSURE_2026-07-26 §8.2) ---
  # THE ONLY PLACE THIS REF MAY BE DELETED, and it is reachable only past the `break` above — i.e.
  # only once land-verify has proven this head's content is on the trunk. That is exactly the
  # ref's release condition: it exists to roll back a land that went wrong, and this land did not.
  # Left undeleted (the behaviour until now) every SUCCESSFUL land permanently added a branch
  # pinning the PRE-rebase commits, whose patch-ids no dedupe can collapse onto their landed twins —
  # so the "stranded" exposure metric grew monotonically with landing volume, 70 of 81 orphan-
  # carrying branches being these refs. The reaper re-proves the ref's OWN content against
  # $LANDED_HEAD before deleting (never against origin/$TRUNK, which a sibling can advance under
  # us), and KEEPS it on any doubt.
  # Ordered before the sweep purely as hygiene — the sweep walks every ref in refs/heads, so a ref
  # whose purpose is already discharged should not be in that walk. It is NOT a correctness fix for
  # the sweep: stranded-sweep only reports a commit whose paths are ALL absent from the trunk, so it
  # would not have flagged a ref we just landed.
  # `|| true` is load-bearing: a land that has already content-verified must never be turned red by
  # its own cleanup. Kill switch: SHIP_BACKUP_REAP=off.
  if [[ -n "${SHIP_LAND_BACKUP_REF:-}" && -x "$BACKUP_REAP" ]]; then
    "$BACKUP_REAP" reap "$SHIP_LAND_BACKUP_REF" "$LANDED_HEAD" || true
  fi

  local sweep_out sweep_rc sweep_field
  sweep_out="$("$STRANDED_SWEEP" "$TRUNK" 2>&1)"; sweep_rc=$?
  if [[ "$sweep_rc" -eq 0 ]]; then
    sweep_field="clean"
    echo "✓ ship-land: stranded-sweep clean."
  else
    sweep_field="review"
    echo "⚠ ship-land: stranded-sweep flags commit(s) for REVIEW — peer WIP is expected on a multi-session box; recover ONLY your own dropped work, NEVER cherry-pick peer WIP onto $TRUNK:" >&2
    printf '%s\n' "$sweep_out" >&2
  fi

  attest_land "ok" "$sweep_field" "clean" 0

  # --- post-land verification (async, detached) ---
  # THE HANDOFF OF THE VERDICT, and in v2 it carries the whole correctness argument: this land
  # proved statics + a smoke over its own diff and nothing more, so the FULL suite is re-proven
  # off the critical path — queue the landed head and hand it to postland-verify.sh. This kick is
  # the FAST path (a fresh land is verified in seconds, not at the next tick); the launchd
  # StartInterval is only the backstop for a land that died before reaching this line.
  # start_new_session is MANDATORY — nohup/disown children share our process group and are reaped
  # by the harness's group SIGKILL.
  # Guarded: absent verifier (or POSTLAND_VERIFY=off) is a no-op, never a land failure.
  if [[ "${POSTLAND_VERIFY:-on}" != "off" && -x "$SCRIPT_DIR/postland-verify.sh" ]]; then
    local pdir; pdir="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
    mkdir -p "$pdir" 2>/dev/null || true
    printf '%s\n' "$LANDED_HEAD" > "$pdir/queue" 2>/dev/null || true
    python3 -c 'import subprocess,sys; subprocess.Popen([sys.argv[1],"--run-if-needed"],start_new_session=True)' \
      "$SCRIPT_DIR/postland-verify.sh" 2>/dev/null || true
  fi

  echo "✓ ship-land: LANDED $(git rev-parse --short "$LANDED_HEAD") → origin/$TRUNK; content-verified; sweep=$sweep_field."
  exit 0
}

# ---- outer phase (preflight → launch locked child) -------------------------

main_outer() {
  local DRY_RUN=0 TRUNK=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --trunk) TRUNK="${2:-}"; shift 2 ;;
      --trunk=*) TRUNK="${1#--trunk=}"; shift ;;
      -h|--help) sed -n '2,30p' "$SELF"; exit 0 ;;
      *) echo "✗ ship-land: unknown argument '$1'" >&2; exit 2 ;;
    esac
  done
  [[ -z "$TRUNK" ]] && TRUNK="$(detect_trunk)"

  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  local TOP; TOP="$(cd "$REPO_ROOT" && pwd -P)"

  # --- shared-checkout refusal (G-P9-4, in code) ---
  local SHARED; SHARED="${SHIP_LAND_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
  [[ -d "$SHARED" ]] && SHARED="$(cd "$SHARED" && pwd -P)"
  local SESSION_RE; SESSION_RE="${SHIP_LAND_SESSION_BRANCH_RE:-^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+}"
  if [[ "$TOP" = "$SHARED" ]]; then
    if [[ "$BRANCH" =~ ^(main|master|develop|production|prod|release) ]]; then
      echo "✗ ship-land: REFUSING to land from the shared checkout ($SHARED) on protected branch '$BRANCH'. This is the $(basename "$SHARED") symlink source and often sits on a foreign session's branch; landing here risks landing onto a branch you did not create / being rebase-dropped. Re-run from a dedicated worktree (claude -w <name>)." >&2
      exit 4
    elif [[ "$BRANCH" =~ $SESSION_RE ]] || [[ "${SHIP_LAND_ALLOW_SHARED:-0}" = "1" ]]; then
      echo "⚠ ship-land: landing from the shared checkout on session branch '$BRANCH' (allowed). Prefer a dedicated worktree." >&2
    else
      echo "✗ ship-land: REFUSING to land from the shared checkout ($SHARED) on non-session branch '$BRANCH'. Re-run from a dedicated worktree, or set SHIP_LAND_ALLOW_SHARED=1 if you own this branch." >&2
      exit 4
    fi
  fi

  # --- dirty-tree refusal ---
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "✗ ship-land: working tree has uncommitted changes — commit the in-scope work first (explicit paths, never a blind add -A), then land. Refusing to land a dirty tree." >&2
    git status --short >&2
    exit 2
  fi

  git fetch origin "$TRUNK" 2>/dev/null || echo "⚠ ship-land: preflight fetch failed — using local origin/$TRUNK" >&2
  # UNION-SCOPE anchor: the trunk tip our FIRST gate will run against. Every later round unions
  # FIRST_BASE..<that round's base> into the selection — the delta siblings landed while we gated.
  FIRST_BASE="$(git rev-parse "origin/$TRUNK" 2>/dev/null || echo '')"
  local BASE RANGE
  BASE="$(git merge-base "origin/$TRUNK" HEAD 2>/dev/null || true)"
  if [[ -z "$BASE" ]]; then
    echo "✗ ship-land: cannot find a merge-base with origin/$TRUNK — is '$TRUNK' the right trunk? (use --trunk)" >&2
    exit 2
  fi
  RANGE="$BASE..HEAD"
  if [[ -z "$(git rev-list "$RANGE" 2>/dev/null)" ]]; then
    echo "✓ ship-land: nothing to land (origin/$TRUNK already contains HEAD)."
    exit 0
  fi

  # --- escalation-scan (blast-radius cap, T-P9-6) → PARK, never auto-land ---
  local hits; hits="$(esc_scan "$RANGE")"
  if [[ -n "$hits" ]]; then
    local id; id="shipland-esc-$(git rev-parse --short HEAD)"
    local pkt; pkt="$(write_decision_packet "$id" "$BRANCH" "$RANGE" "$hits")"
    echo "⛔ ship-land: escalation-surface pattern in the landing range — PARKED for human review, NOT auto-landed." >&2
    printf '%s\n' "$hits" | sed 's/^/    /' >&2
    echo "  decision packet: ${pkt:-$id}" >&2
    attest_land "n/a" "n/a" "hit" 3
    exit 3
  fi

  # --- P6 gate-batching backstop (T-P7-7) — SURFACE auto-stamped in-class ratifications in the
  #     landing range for EARLY-VETO. The dual of esc_scan: esc_scan PARKS out-of-class escalation
  #     surfaces; this only SURFACES in-class auto-ratifications (`Ratified-By: ... pre-signed class`).
  #     Non-blocking by contract (never changes the exit code) — a review channel, not a gate. ---
  [[ -x "$GATE_MANIFEST" ]] && "$GATE_MANIFEST" backstop "$RANGE" || true

  # --- safety backup ref (rollback point) ---
  # EXPORTED, not just written: the locked child is the process that learns whether the land
  # succeeded, and it cannot recompute this name — by the time it holds a verdict HEAD has been
  # rebased, so `rev-parse --short HEAD` there names a different commit. Exporting at the write site
  # covers BOTH exec paths below (the optimistic-round loop and the statics-only fallback) without
  # either of them having to know about it. The ref is discharged by ship-backup-reap.sh on the
  # content-verified success path; every failure path leaves it intact, which is its whole purpose.
  SHIP_LAND_BACKUP_REF="ship/backup-$(git rev-parse --short HEAD)"
  export SHIP_LAND_BACKUP_REF
  git branch -f "$SHIP_LAND_BACKUP_REF" HEAD >/dev/null 2>&1 || true

  # --- optimistic rounds: the gate runs UNLOCKED (parallel across sessions); the lock holds
  #     ONLY fetch-compare → push → content-verify. A stale gate (exit 42: a sibling
  #     landed mid-gate) releases the lock and re-gates the new final tree out here — and in v2
  #     that re-gate is statics + ratchets + smoke (seconds), never a second corpus. ---
  local ROUNDS round rc
  ROUNDS="${SHIP_LAND_GATE_ROUNDS:-3}"
  round=0
  while [[ "$round" -lt "$ROUNDS" ]]; do
    round=$(( round + 1 ))
    unlocked_reconcile_and_gate "$TRUNK" "$DRY_RUN"   # exits on 5/6/dry-run/nothing-to-land
    # HAND THE GATE'S FACTS TO THE LOCKED CHILD. It is a separate process and, in CAS mode, does
    # not re-run the gate — without this its land.log line would attest a smoke that it never saw.
    export SHIP_LAND_GATE_EFFECTIVE_FULL="$GATE_EFFECTIVE_FULL" SHIP_LAND_SELECTED_N="$SELECTED_N" \
           SHIP_LAND_FIRST_BASE="$FIRST_BASE" \
           SHIP_LAND_SMOKE_STATE="$SMOKE_STATE" SHIP_LAND_SMOKE_N="$SMOKE_N" \
           SHIP_LAND_SMOKE_S="$SMOKE_S" SHIP_LAND_NET_STATE="$NET_STATE"
    "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "$GATE_BASE" "$GATE_HEAD"
    rc=$?
    [[ "$rc" -ne 42 ]] && exit "$rc"   # landed (0) or a real failure (incl. land-lock's 75) — propagate
    echo "↻ ship-land: optimistic round ${round}/${ROUNDS} invalidated (sibling land mid-gate) — re-gating the new final tree unlocked." >&2
  done

  # --- rounds exhausted (sustained contention) or SHIP_LAND_GATE_ROUNDS=0: guaranteed
  #     progress — rebase + re-gate INSIDE the lock, STATICS + RATCHETS ONLY (run_gate refuses to
  #     start bats when IN_LAND_LOCK=1, in either lane). A held mutex stops further pipeline
  #     movement, so this round cannot be invalidated; the difference from v1 is that it now
  #     costs seconds instead of the 3h36m lock hold that jammed the fleet. ---
  [[ "$ROUNDS" -gt 0 ]] && echo "→ ship-land: ${ROUNDS} optimistic round(s) exhausted — falling back to the in-lock STATICS-only re-gate (guaranteed progress; nothing heavy enters the lock)." >&2
  exec "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "" ""
}

# ---- dispatch --------------------------------------------------------------

if [[ "${1:-}" = "__locked" ]]; then
  shift
  main_locked "$@"     # always exits internally
else
  main_outer "$@"      # exec's the locked child, or exits on a preflight refusal
fi
