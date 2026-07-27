#!/usr/bin/env bash
# ship-land.sh — the ENTIRE claude-infrastructure landing pipeline as ONE fail-closed
# script (was prose in .claude/commands/ship.md a model could skip or paraphrase).
#
#   scripts/ship-land.sh [--trunk <branch>] [--dry-run]
#
# INVARIANT (land-gate serialization fix, 2026-07-25): the GATE proves the FINAL rebased
# tree green; the LOCK covers ONLY the race window (fetch-compare → push → content-verify —
# the 2026-07-11 anti-drop guarantee). The full gate runs UNLOCKED and therefore in PARALLEL
# across concurrent landing sessions; the machine-wide mutex is held for seconds, not the
# full-suite duration (pre-fix: N concurrent landers serialized at ~N × suite-time, observed
# 40-min queues).
#
# Pipeline (fail-closed at every step):
#   preflight (OUTSIDE lock): shared-checkout refusal · dirty-tree refusal ·
#     escalation-scan (destructive SQL / credential patterns ⇒ PARK a decision packet,
#     exit 3, never auto-land) · safety backup ref
#   → optimistic rounds, up to SHIP_LAND_GATE_ROUNDS (default 3), each:
#       UNLOCKED: `git fetch` → `git rebase` (conflict ⇒ exit 5) → FULL GATE on the rebased
#       tree (shellcheck + `bash -n` + py_compile for changed shell/python INCLUDING
#       extensionless by shebang, then the test-hermeticity ratchet, then bats; red ⇒ exit 6);
#       record (GATE_BASE = origin/<trunk>,
#       GATE_HEAD = HEAD) — the exact tree the gate proved green. --dry-run stops here
#       (a dry run never takes the lock).
#       → land-lock'd child (serialized machine-wide per repo via land-lock.sh):
#         last-moment `git fetch` → CAS check: origin/<trunk> still == GATE_BASE AND
#         HEAD still == GATE_HEAD? If NOT (a sibling landed mid-gate): release the lock,
#         exit 42 (internal STALE-GATE code), and the outer loop re-rebases + RE-GATES the
#         new final tree UNLOCKED (the re-gate fires IFF origin moved in the window). If
#         yes: the gated tree IS the pushed tree → `git push HEAD:<trunk>` (non-ff ⇒
#         exit 7) → land-verify.sh (content-verify, IN the lock, after the push) → on a
#         content-drop, BOUNDED AUTO-RETRY + ROLLBACK (T-P9-7): re-fetch + rebase onto the
#         moved trunk + re-gate (in-lock — rare incident-recovery path) + re-push, up to
#         SHIP_LAND_VERIFY_RETRIES times; a retry rebase-conflict rolls back
#         (rebase --abort) ⇒ exit 5, retries exhausted (still not intact) ⇒ clean tree +
#         exit 8 → stranded-sweep (exit 1 ⇒ REVIEW verdict, surfaced, never auto-recovered)
#         → self-attesting land.log line {verify,sweep,esc_scan,sid}.
#   → rounds exhausted (sustained contention — every unlocked gate was invalidated by a
#     sibling land): GUARANTEED-PROGRESS FALLBACK — rebase + full gate INSIDE the lock (the
#     pre-fix behavior; a held mutex stops further pipeline movement, so this terminates).
#     SHIP_LAND_GATE_ROUNDS=0 skips the optimistic rounds entirely (the kill switch back to
#     the pre-fix always-in-lock behavior).
#
# WHY the stale path re-runs the FULL gate (not a delta-scoped subset): green(our tree) +
# green(sibling's landed tree) does NOT imply green(our tree rebased onto theirs) — semantic
# conflicts need no file overlap, and this repo's tests read docs/prose too, so no
# changed-path test map is conservatively sufficient. The full gate on the final tree is the
# only provably-sufficient re-check; the fix is WHERE it runs (unlocked), never WHETHER.
#
# --dry-run stops after the gate (no push, no lock). Exit codes: 0 landed · 2 preflight
# refusal · 3 escalation PARK · 4 shared-checkout refusal · 5 rebase conflict (initial OR an
# auto-retry rebase, the latter rolled back) · 6 gate red · 7 push non-ff · 8 content-verify
# failed after exhausting the bounded auto-retries · 9 GATE-KILLED. (42 is INTERNAL — locked
# child → outer-loop stale-gate signal; it never escapes ship-land.)
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
# GATE SCOPE (scripts/gate-policy.sh; env SHIP_LAND_GATE_SCOPE overrides it, and a missing or
# corrupt policy file falls back to `full` — narrowing is never the failure mode):
#   full    `bats tests/` every land (the pre-scoping behavior; SHIP_LAND_GATE_SCOPE=full is the
#           KILL SWITCH — byte-identical to before scoping).
#   shadow  full suite still decides; gate-select.sh runs alongside for observability only.
#   scoped  run only the suites gate-select.sh maps to the landing range, each as its OWN
#           `bats <file>` (per-file attribution). Selector says FULL ⇒ full suite; missing or
#           non-executable selector ⇒ FULL (fail-closed); selects nothing ⇒ lint-only land.
#           A failing NON-direct suite gets ONE exoneration re-run in a fresh TMPDIR — green on
#           retry ⇒ logged to postland/flakes.jsonl and the land continues; a DIRECT suite of the
#           change never gets exonerated (intermittence in changed code is a finding, not a flake).
#           A scoped run NEVER advances the gate-green marker (it cannot make the full-suite claim
#           its consumers read it as) — boundary-handoff / wrap-ledger then degrade correctly.
#   The test-hermeticity ratchet is OUTSIDE this scope machinery on purpose — it runs on every
#   land in every mode, before bats, because selection can never reach it (a new tests/*.bats maps
#   to itself, never to the ratchet) and because its subject is a whole-tree property, not a
#   changed-path one. See run_gate.
#   Three more ways scoped degrades to FULL, all fail-closed: a red `gate-select.sh lint` (the
#   suite map is untrustworthy — but lint NEVER blocks a land), an INERT post-land net (stamps
#   exist yet the newest green one is older than POSTLAND_MAX_STAMP_AGE_H — absence-is-loud; no
#   stamps at all = not adopted yet, no guard), and a stale-gate re-round, which hands the
#   selector a SECOND range (FIRST_BASE..new base) so the union covers what siblings landed
#   while we gated — the composed tree's only novelty.
#
# Env overrides (mostly for tests): SHIP_LAND_SHARED_CHECKOUT · SHIP_LAND_SESSION_BRANCH_RE
# · SHIP_LAND_ALLOW_SHARED=1 · SHIP_LAND_ESC_RE · SHIP_LAND_DECISIONS_DIR · LAND_LOG ·
# LAND_LOCK_DIR (see land-lock.sh) · SHIP_LAND_VERIFY_RETRIES (default 2; 0 = single-shot,
# the pre-T-P9-7 kill switch — one push, one verify, no auto-retry) ·
# SHIP_LAND_GATE_ROUNDS (default 3; 0 = gate fully in-lock, the pre-optimistic kill switch) ·
# SHIP_LAND_GATE_SCOPE / SHIP_LAND_GATE_POLICY / SHIP_LAND_GATE_SELECT (see GATE SCOPE above) ·
# SHIP_LAND_HERM_LINT (test-hermeticity ratchet path; default the landing tree's own
# scripts/test-hermeticity-lint.sh — see run_gate) ·
# POSTLAND_DIR (flake + post-land queue + stamps dir) · POSTLAND_VERIFY=off (skip the post-land
# spawn) · POSTLAND_STALENESS_GUARD=off · POSTLAND_MAX_STAMP_AGE_H (24) ·
# CC_GATE_MAX_LOAD / CC_GATE_ADMIT_MAX_WAIT / CC_GATE_ADMIT_POLL (admission control; 0|off = the
# kill switch).
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
STRANDED_SWEEP="${SCRIPT_DIR}/stranded-sweep.sh"
GATE_MANIFEST="${SCRIPT_DIR}/gate-manifest.sh"
GATE_SELECT="${SHIP_LAND_GATE_SELECT:-${SCRIPT_DIR}/gate-select.sh}"

# ---- gate scope (committed policy file; env always wins) --------------------
# Hardcoded `full` fallback: an absent/corrupt policy file degrades SAFE (never narrows).
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
# handoff its land.log line would understate a scoped run as n/a. INTERNAL vars, not a UI.
GATE_EFFECTIVE_FULL="${SHIP_LAND_GATE_EFFECTIVE_FULL:-1}"  # 1 ⇒ full suite PROVED (gate-green may advance)
SELECTED_N="${SHIP_LAND_SELECTED_N:--1}"                   # suites selected (-1 = n/a: full/shadow run)
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

ESC_RE_DEFAULT='DROP[[:space:]]+TABLE|DROP[[:space:]]+COLUMN|DROP[[:space:]]+DATABASE|DROP[[:space:]]+SCHEMA|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM|ALTER[[:space:]]+TABLE[[:space:]].+[[:space:]]DROP|-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
# NOTE: auth/session/navigation code lands are ALSO escalation-worthy (operator ruling),
# but this repo's normal churn is full of those words — a substring scan would self-park
# every land. Keep the default to high-signal destructive-SQL / credential patterns and
# let a repo extend it via SHIP_LAND_ESC_RE. (Surfaced to the lead as a design tradeoff.)

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

esc_scan() {  # $1=range → prints matched escalation lines (empty ⇒ clean). FAIL CLOSED: if grep cannot
              # evaluate the pattern (rc≥2: invalid regex, or an option-like $re), emit a synthetic hit
              # so the caller PARKS. The one fail-closed landing rail must NEVER read a malformed
              # SHIP_LAND_ESC_RE as clean. `--` stops an $re beginning with `-` being parsed as an option;
              # the explicit rc capture (not `|| true`) stops rc 2 being swallowed as rc 1 (no match).
  local range="$1" re body out rc
  re="${SHIP_LAND_ESC_RE:-$ESC_RE_DEFAULT}"
  body="$(git diff "$range" 2>/dev/null | grep -E '^[-+]' | grep -Ev '^(\+\+\+|---) ' || true)"
  out="$(printf '%s\n' "$body" | grep -inE -- "$re")"; rc=$?
  if [[ "$rc" -ge 2 ]]; then
    printf 'ESC-SCAN-ERROR: grep rc=%s — SHIP_LAND_ESC_RE uninterpretable (invalid regex / option-like); failing closed, PARK\n' "$rc"
    return 0
  fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

write_decision_packet() {  # $1=id $2=branch $3=range $4=hits
  local id="$1" branch="$2" range="$3" hits="$4" dir
  dir="${SHIP_LAND_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
  mkdir -p "$dir" 2>/dev/null || true
  ID="$id" BRANCH="$branch" RANGE="$range" HITS="$hits" SID="${CLAUDE_CODE_SESSION_ID:-}" \
    python3 - "$dir/$id.json" <<'PY'
import json, os, sys
pkt = {
    "id": os.environ["ID"],
    "class": "B",
    "what_plain": ("ship-land refused to auto-land branch %r: the landing range %r contains an "
                   "escalation-surface pattern (destructive SQL / credential). Auto-landing "
                   "destructive or security-sensitive changes is disallowed; a human must review "
                   "and land." % (os.environ["BRANCH"], os.environ["RANGE"])),
    "options": ["review the flagged lines and land manually via /ship",
                "amend the commit to remove the escalation pattern, then re-run",
                "veto — do not land"],
    "recommendation": "review the flagged lines and land manually if correct",
    "default_if_no_veto": None,
    "staged": True,
    "session_id": os.environ.get("SID", ""),
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
  # replayable (which tree was gated) and gate_scope/selected_n make "was this a full-suite
  # proof?" answerable per land — the denominator flake-rate claims need.
  local log; log="${LAND_LOG:-$HOME/.claude/land.log}"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '{"ts":"%s","tool":"ship-land","repo":"%s","branch":"%s","sid":"%s","verify":"%s","sweep":"%s","esc_scan":"%s","exit":%s,"head":"%s","base":"%s","tree":"%s","gate_scope":"%s","selected_n":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "${CLAUDE_CODE_SESSION_ID:-}" \
    "$1" "$2" "$3" "$4" \
    "${ATTEST_HEAD:-?}" "${ATTEST_BASE:-?}" "${ATTEST_TREE:-?}" "${SCOPE}" "${SELECTED_N:--1}" \
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

postland_net_live() {  # 0 = trust the post-land net (or it is not adopted yet) / 1 = INERT
  # ABSENCE IS LOUD. A scoped land is only safe because the FULL suite is re-proven off the
  # critical path. If the net HAS run here (stamps exist) but its newest green stamp has gone
  # cold, the net is inert and this land must NOT narrow. No stamps dir / no green stamp yet ⇒
  # the net simply is not adopted (the bootstrap land) — never brick that.
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
  [[ "$age" -lt "$max" ]] && return 0
  echo "⚠ gate[scoped]: post-land net appears INERT — newest green stamp is ${age}h old (max ${max}h). Degrading this land to the FULL gate. (kill switch: POSTLAND_STALENESS_GUARD=off)" >&2
  return 1
}

# ---- admission control: bounded, fail-OPEN load shedding --------------------
# WHY: nothing in the land path deferred on load — loadavg was RECORDED for forensics only
# (here and postland-verify.sh). So every landing worktree started its FULL suite at once; the
# kernel starved/killed them; the cuts were misread as RED; the reblocks made the dispatcher
# retry. Fail-closed was AMPLIFYING the contention it guards (backlog f8e40b4c577d). CUT ≠ RED
# (below) stops a cut from LYING; this stops the cut happening. They are complements, not
# alternatives — the re-run below is only evidence if the environment actually changed.
# CONTRACT — all four are load-bearing:
#   bounded      never waits longer than CC_GATE_ADMIT_MAX_WAIT, then PROCEEDS (a land must never
#                be starved by a busy box; shedding is a courtesy, not a gate).
#   overridable  CC_GATE_MAX_LOAD (ceiling) · CC_GATE_ADMIT_MAX_WAIT · CC_GATE_ADMIT_POLL;
#                CC_GATE_MAX_LOAD=0|off is the kill switch.
#   fail-OPEN    unreadable sensor or non-numeric ceiling ⇒ return immediately. A broken load
#                sensor must never block a land — that would be a new fail-closed amplifier.
#   lock-free    NEVER called while the land-lock is held. The gate sits OUTSIDE the lock BY
#                DESIGN (190c839, for the CAS push window); waiting inside it would serialize
#                every lander behind one sleep and convert a load problem into a deadlock-shaped
#                one. main_locked sets IN_LAND_LOCK=1 and this becomes a no-op there.
IN_LAND_LOCK="${IN_LAND_LOCK:-0}"
gate_admit() {  # $1=what — defer the start of an expensive suite until load falls below a ceiling
  local what="${1:-suite}" max budget step waited=0 load jit total spent
  [[ "$IN_LAND_LOCK" = "1" ]] && return 0
  max="${CC_GATE_MAX_LOAD:-8}"; budget="${CC_GATE_ADMIT_MAX_WAIT:-600}"; step="${CC_GATE_ADMIT_POLL:-15}"
  [[ "$max" = "0" || "$max" = "off" ]] && return 0
  case "$max" in ''|*[!0-9.]*) return 0 ;; esac                      # ceiling: numeric (awk-compared)
  case "$budget$step" in ''|*[!0-9]*) return 0 ;; esac               # waits: INTEGER seconds
  [[ "$step" -gt 0 ]] || return 0                                    # a 0 poll would spin ⇒ fail OPEN
  # RUN-WIDE CEILING. The per-call bound was written for a caller that ran it twice; the per-suite
  # runner calls it once per corpus PLUS once per failing suite's re-run, so a 600s per-call bound
  # MULTIPLIES — 126 suites × 600s is 21 h of "bounded" waiting. Every bound must cover the failure
  # mode it bounds. Fail-OPEN like the rest of this function: a non-integer total falls back to the
  # default rather than blocking, and once the run-wide budget is spent, shedding simply stops.
  total="${CC_GATE_ADMIT_TOTAL_WAIT:-1200}"
  case "$total" in ''|*[!0-9]*) total=1200 ;; esac
  spent="${GATE_ADMIT_SPENT:-0}"
  if [[ "$spent" -ge "$total" ]]; then
    if [[ "${GATE_ADMIT_CAPPED:-0}" != "1" ]]; then
      GATE_ADMIT_CAPPED=1
      echo "▶ gate: run-wide admission budget ${total}s spent — no further shedding this run (override CC_GATE_ADMIT_TOTAL_WAIT)" >&2
    fi
    return 0
  fi
  [[ $(( total - spent )) -lt "$budget" ]] && budget=$(( total - spent ))
  while [[ "$waited" -lt "$budget" ]]; do
    load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
    [[ -n "$load" ]] || { GATE_ADMIT_SPENT=$(( spent + waited )); return 0; }   # sensor ⇒ fail OPEN
    if awk -v l="$load" -v m="$max" 'BEGIN{exit !(l+0 < m+0)}'; then
      GATE_ADMIT_SPENT=$(( spent + waited ))
      [[ "$waited" -gt 0 ]] && echo "✓ gate: admitted after ${waited}s (load $load < $max) — starting $what" >&2
      return 0
    fi
    [[ "$waited" -eq 0 ]] && echo "⏸ gate: DEFERRING $what — load $load ≥ ceiling $max (waiting up to ${budget}s; override CC_GATE_MAX_LOAD / CC_GATE_ADMIT_MAX_WAIT, 0=off)" >&2
    # JITTER is load-bearing, not polish: without it every lander that deferred at the same moment
    # also WAKES at the same moment and they all start their suites together — a fresh thundering
    # herd precisely when load dips. Spreading the restarts lets the first waker in while the rest
    # re-observe the load it just created.
    jit=$(( RANDOM % 8 ))
    sleep "$(( step + jit ))"; waited=$(( waited + step + jit ))
  done
  GATE_ADMIT_SPENT=$(( spent + waited ))
  echo "▶ gate: admission budget ${budget}s exhausted (load $load ≥ $max) — proceeding anyway with $what (bounded by design)" >&2
  return 0
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
# which is simply wrong — bats masks the signal (see run_bats_all), so a SIGKILLed suite surfaces
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
# The isolation is applied at gate_bats — the single chokepoint BOTH the monolithic run_bats_all
# and the per-suite run_scoped_suite already funnel through — so ship-land's OWN bookkeeping
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
# CC_GATE_MAX_LOAD is FORCED to 0 rather than unset: a test must never sit in admission control,
# which would stall the gate up to CC_GATE_ADMIT_MAX_WAIT per call (and gate_admit is a no-op
# under the lock anyway). Only LANDER tuning is scrubbed — a test that wants any of these sets it
# itself, per-test, which is unaffected.
# SHIP_LAND_FULL_PER_SUITE joins the scrub list for exactly the same reason: it is LANDER tuning,
# and tests/ship-land.bats asserts against BOTH runner modes. Left unscrubbed, an operator landing
# with the kill switch on would bleed `off` into every fixture pipeline in that suite, so the
# per-suite tests would silently exercise the monolith and go red on a tree that is fine — the
# ROUNDS=0 defect verbatim, on the flag this very change introduces.
gate_bats() {  # run bats with the operator's lander tuning scrubbed; args pass through verbatim
  # …and under the isolated $HOME when gate_home_setup got one. THE chokepoint: both run_bats_all
  # (monolithic) and run_scoped_suite (per-suite, incl. its exoneration re-run) reach bats only
  # through here, so isolation covers every path without either of them knowing about it.
  # An EMPTY GATE_HOME passes HOME through untouched — that is the fail-open branch, not a bug.
  local homeenv=()
  [[ -n "${GATE_HOME:-}" ]] && homeenv=(HOME="$GATE_HOME")
  env -u SHIP_LAND_GATE_ROUNDS -u SHIP_LAND_VERIFY_RETRIES -u SHIP_LAND_GATE_SCOPE \
      -u LAND_LOCK_WAIT -u LAND_LOCK_TTL -u SHIP_LAND_FULL_PER_SUITE \
      CC_GATE_MAX_LOAD=0 ${homeenv[@]+"${homeenv[@]}"} bats "$@"
}

run_bats_all() {  # $1=newline-list of DIRECT suites — the FULL corpus, one process per suite
  # PHASE 1 of docs/plans/GATE_ARCHITECTURE_PLAN.md. SAME suites, SAME verdict rule; what changes
  # is BLAST RADIUS. The governing law, MLE'd over all 55 real gate runs with a suite count
  # (~/.claude/land.log): P(gate green) = (1-q)^n at q=2.94% PER SUITE — n=1 → 2/2 green,
  # n=126 → 1/39 green, 5.0e5x more likely than a constant per-run model. So `n` is the lever.
  # `bats tests/` handed all 126 files to ONE bats-exec-suite for 20-53 min, so a kill at suite 120
  # lost all 126 and was attested exit:6 RED. Per suite, a kill costs ONE suite and run_scoped_suite
  # re-runs it in a fresh TMPDIR — the mechanism that already absorbed 5 signal-kills
  # (flakes.jsonl: 3x `exit 137`, 2x `Terminated: 15`) without redding a gate.
  # Measured retry-failure rate 17% ⇒ q_eff 0.49% ⇒ P(green|n=126) 2.3% → 49.9% (21.5x), at a
  # measured +3.0% wall time (bats startup 0.46s x 126 = 58s on a 1957s run).
  # A DIRECT suite is still never exonerated and GATE_EFFECTIVE_FULL stays 1, so the full-suite
  # claim is unchanged. This COMPOSES with the CUT≠RED body below (c605a2e) and gate_admit — the
  # monolithic path keeps both; neither is replaced.
  # KILL SWITCH — an env flag, NOT a revert: a revert would itself need the gate, which is the
  # bootstrap deadlock this whole plan exists to escape.
  if [[ "${SHIP_LAND_FULL_PER_SUITE:-on}" != "off" ]]; then
    local _direct="${1:-}" _f _n=0 _red=0 _killed=0 _srv
    echo "→ gate: bats tests/ — full corpus, one process per suite (SHIP_LAND_FULL_PER_SUITE=off restores the monolith)" >&2
    gate_admit "the FULL bats suite (per-suite)"
    for _f in tests/*.bats; do
      [[ -e "$_f" ]] || continue
      _n=$(( _n + 1 ))
      _srv=0; run_scoped_suite "$_f" "$_direct" || _srv=$?
      case "$_srv" in
        0) ;;
        2) _killed=$(( _killed + 1 )) ;;
        *) _red=$(( _red + 1 )) ;;
      esac
    done
    if [[ "$_n" -eq 0 ]]; then
      echo "✗ gate: no suites matched tests/*.bats — refusing to claim green on an empty corpus" >&2
      GATE_RED=1; return 1
    fi
    if [[ "$_red" -eq 0 && "$_killed" -eq 0 ]]; then
      echo "✓ gate: FULL corpus green — $_n suites, one process each" >&2; return 0
    fi
    # NO FAIL-FAST, deliberately. The loop must finish the corpus so "did ANY suite name a real
    # failure?" is answerable from evidence. Stopping at the first CUT would report a non-verdict
    # (exit 9 ⇒ "retry when the box is quieter") for a corpus that also contained a genuine red —
    # the dispatcher would then retry a tree that is actually broken, which is f8e40b4c577d in
    # miniature. Finishing costs wall time on an already-doomed run and buys every failing suite
    # named in ONE cycle instead of one per 20-minute gate.
    if [[ "$_killed" -gt 0 ]]; then
      GATE_KILLED=1
      echo "⛔ gate: GATE-KILLED — $_killed of $_n suite(s) were cut TWICE with ZERO 'not ok'; they earned no verdict. Free a stuck gate with scripts/gate-cleanup.sh (worktree-scoped), never a bare pkill." >&2
    fi
    if [[ "$_red" -gt 0 ]]; then
      GATE_RED=1
      echo "✗ gate: bats RED — $_red of $_n suite(s) failed" >&2
    fi
    return 1
  fi
  echo "→ gate: bats tests/ (monolithic — SHIP_LAND_FULL_PER_SUITE=off)" >&2
  # CUT ≠ RED. bats exits non-zero for BOTH a real `not ok` and a death by signal (a peer's
  # kill, a starved fork, a truncated stream) — and the second case reports ZERO `not ok`.
  # Branching on the exit code alone turned every machine-wide cut into a false "gate RED"
  # (exit 6): measured 2026-07-26, 21 of 39 attested gate-REDs fired in 7 same-second clusters
  # spanning 2-4 DIFFERENT worktrees — synchronization no genuine test failure can produce —
  # and all 21 were FULL-tier runs. run_scoped_suite (:252) already absorbs exactly this via one
  # fresh-TMPDIR re-run; FULL mode had no such appeal, which is why it failed 33 of its 34 runs.
  #
  # NOT by exit code: bats's own pipeline masks the signal. `bats:517-524` runs
  # `exec bats-exec-suite | bats_test_count_validator | formatter` under `set -o pipefail`
  # (`bats:501`), and the validator returns 1 on a truncated TAP — so under pipefail the
  # rightmost non-zero wins and a SIGKILLed suite surfaces as plain `1`, never 137/143.
  # The TAP BODY is the only honest discriminator.
  local log rc notok td rc2
  gate_admit "the FULL bats suite"
  log="$(mktemp)"
  echo "→ gate: bats tests/" >&2
  gate_bats tests/ 2>&1 | tee "$log" >&2; rc="${PIPESTATUS[0]}"
  if [[ "$rc" -eq 0 ]]; then rm -f "$log"; return 0; fi
  notok="$(grep -c '^not ok' "$log" 2>/dev/null || true)"; notok="${notok:-0}"
  if [[ "$notok" -gt 0 ]]; then
    echo "✗ gate: bats RED — $notok failing test(s)" >&2
    rm -f "$log"; GATE_RED=1; return 1
  fi
  echo "↻ gate: bats exited $rc with ZERO 'not ok' — CUT, not RED. One re-run in a fresh TMPDIR…" >&2
  record_gate_cut "$rc" "$log"
  rm -f "$log"
  # SHED BEFORE THE RE-RUN. Re-running under the same sustained load that cut the first run is not
  # a retry, it is the same experiment — and the postland retry ladder made exactly this mistake,
  # convicting six suites that pass cleanly on a quiet box.
  gate_admit "the FULL bats re-run"
  # CAPTURE THE RE-RUN'S TAP TOO. Without it the two ways a re-run can fail are indistinguishable —
  # hence the pre-existing "RED (or cut twice)", which handed the caller a guess at precisely the
  # moment the answer decides what to do next. Same discriminator as the first run: the TAP body.
  td="$(mktemp -d)"; log="$(mktemp)"
  TMPDIR="$td" gate_bats tests/ 2>&1 | tee "$log" >&2; rc2="${PIPESTATUS[0]}"
  rm -rf "$td" 2>/dev/null || true
  if [[ "$rc2" -eq 0 ]]; then
    rm -f "$log"
    echo "✓ gate: FULL suite green on re-run — the first run was cut, not red." >&2
    return 0
  fi
  notok="$(grep -c '^not ok' "$log" 2>/dev/null || true)"; notok="${notok:-0}"
  if [[ "$notok" -gt 0 ]]; then
    rm -f "$log"
    echo "✗ gate: bats RED — $notok failing test(s) on the re-run (the first run was cut)" >&2
    GATE_RED=1; return 1
  fi
  record_gate_cut "$rc2" "$log"
  rm -f "$log"
  GATE_KILLED=1
  echo "⛔ gate: GATE-KILLED — cut TWICE (exit $rc then $rc2, ZERO 'not ok' both times). The suite never earned a verdict, so this is NOT a red and NOT evidence about your tree: nothing is pushed and gate-green is untouched. Re-run /ship when the box is quieter, and free a stuck gate with scripts/gate-cleanup.sh (worktree-scoped), never a bare pkill." >&2
  return 1
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
  local f="$1" direct="$2" td rc1 rc2 fdir log sig notok1 notok2
  # tee (not capture-then-print): the failing run stays LIVE on stderr while its output is kept,
  # so the ledger can record WHAT failed — a bare "it flaked" line is unactionable.
  log="$(mktemp)"
  gate_bats "$f" 2>&1 | tee "$log" >&2; rc1="${PIPESTATUS[0]}"
  if [[ "$rc1" -eq 0 ]]; then rm -f "$log"; return 0; fi
  sig="$(grep -m1 -aE '^not ok|Terminated|Killed|signal|timed? ?out' "$log" 2>/dev/null | sed 's/["\]//g' | cut -c1-160)"
  [[ -z "$sig" ]] && sig="exit $rc1"
  notok1="$(grep -c '^not ok' "$log" 2>/dev/null || true)"; notok1="${notok1:-0}"
  rm -f "$log"
  if [[ "$notok1" -gt 0 ]]; then
    echo "↻ gate: $f RED — $notok1 failing test(s); one exoneration re-run in a fresh TMPDIR…" >&2
  else
    echo "↻ gate: $f exited $rc1 with ZERO 'not ok' — CUT, not RED. One re-run in a fresh TMPDIR…" >&2
  fi
  # SHED FIRST: a re-run under the SAME sustained load that failed the first one is the same
  # experiment, not a retry — the exoneration only means something if the environment changed.
  gate_admit "exoneration re-run of $f"
  # CAPTURE THE RE-RUN'S TAP TOO — c605a2e's own lesson, applied to the per-file runner. Without
  # it "failed twice" cannot say WHICH twice, and a cut-then-real-failure would be handed to the
  # caller as a retryable non-verdict at exactly the moment the answer decides what to do next.
  td="$(mktemp -d)"; log="$(mktemp)"
  TMPDIR="$td" gate_bats "$f" 2>&1 | tee "$log" >&2; rc2="${PIPESTATUS[0]}"
  rm -rf "$td" 2>/dev/null || true
  if [[ "$rc2" -ne 0 ]]; then
    notok2="$(grep -c '^not ok' "$log" 2>/dev/null || true)"; notok2="${notok2:-0}"
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
  if printf '%s\n' "$direct" | grep -qxF -- "$f"; then
    echo "✗ gate: bats RED: $f — pass-on-retry in a DIRECT suite of this change; intermittence in changed code is a finding, not a flake." >&2
    return 1
  fi
  fdir="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
  mkdir -p "$fdir" 2>/dev/null || true
  printf '{"ts":"%s","file":"%s","sha":"%s","phase":"land-gate","outcome":"pass-on-retry","signal":"%s","loadavg":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$f" "$(git rev-parse --short HEAD 2>/dev/null || echo '?')" \
    "$sig" "$(uptime 2>/dev/null | sed 's/.*averages*: //' | awk -F'[, ]+' '{print $1}')" \
    >> "$fdir/flakes.jsonl" 2>/dev/null || true
  echo "✓ gate[scoped]: $f EXONERATED (green on re-run, not a direct suite) — logged to flakes.jsonl" >&2
  return 0
}

stamp_gate_green() {  # gate-green asserts "the FULL suite proved THIS tree" — its consumers
  # (boundary-handoff.sh:122, wrap-ledger.sh:79) read it exactly that way, so a SCOPED run must
  # leave the marker STALE rather than overstate; stale ⇒ they degrade correctly (abstain / n/a).
  if [[ "${GATE_EFFECTIVE_FULL:-1}" != "1" ]]; then
    echo "→ gate[$SCOPE]: gate-green NOT advanced — a scoped run cannot make the full-suite claim." >&2
    return 0
  fi
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green" 2>/dev/null || true
}

run_gate() {  # $1=range → 0 green / 1 red
  local range="$1" p rc=0 HERM_LINT
  GATE_EFFECTIVE_FULL=1; SELECTED_N=-1; GATE_RED=0; GATE_KILLED=0
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
      own="$(git diff --name-only "$range" -- 'tests/*.bats' 2>/dev/null || true)"
      [[ -n "$own" ]] && echo "→ gate: hermeticity own-scope — blocking on $(printf '%s\n' "$own" | grep -c .) suite(s) in this land's diff; others advisory." >&2
    fi
    echo "→ gate: test-hermeticity ratchet (before bats — seconds, and it names the file)" >&2
    if ! CC_HERM_OWN="$own" "$HERM_LINT" tests >&2; then
      echo "✗ gate: test-hermeticity RED — a bats suite THIS LAND CHANGES runs against the operator's live ~/." >&2
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

  if [[ -d tests ]] && ls tests/*.bats >/dev/null 2>&1; then
    local sel="" n direct f rbase srv
    # UNION SCOPE: FIRST_BASE..<this range's base> is the trunk delta siblings landed since our
    # FIRST gate — empty on round 1, non-empty on every stale-gate re-round / in-lock fallback /
    # post-drop re-gate. Derived from the range so all three gate call sites get it for free.
    rbase="${range%%..*}"
    if [[ -n "$FIRST_BASE" && "$FIRST_BASE" != "$rbase" ]]; then EXTRA_RANGE="$FIRST_BASE..$rbase"; else EXTRA_RANGE=""; fi
    if [[ "$SCOPE" != "full" ]]; then
      if [[ ! -x "$GATE_SELECT" ]]; then
        echo "⚠ gate[$SCOPE]: selector '$GATE_SELECT' missing/not executable — treating as FULL (fail-closed)." >&2
        sel="FULL"
      elif [[ "$SCOPE" = "scoped" ]] && ! "$GATE_SELECT" lint >/dev/null 2>&1; then
        # A red map lint means the selection is untrustworthy, NOT that the land is bad: force
        # FULL (~2s of extra proof), never block. Lint red must never be a landing failure.
        echo "⚠ gate[scoped]: suite-map lint RED — selection untrustworthy; running the FULL gate for this land." >&2
        sel="FULL"
      elif [[ "$SCOPE" = "scoped" ]] && ! postland_net_live; then
        sel="FULL"
      else
        sel="$("$GATE_SELECT" "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null)"
      fi
    fi
    if [[ "$SCOPE" = "shadow" ]]; then
      if [[ "$sel" = "FULL" ]]; then n="all"; else n="$(printf '%s' "$sel" | grep -c '[^[:space:]]' || true)"; fi
      echo "→ gate[shadow]: would select $n suites" >&2
    fi
    if [[ "$SCOPE" != "scoped" || "$sel" = "FULL" ]]; then
      # DIRECT suites matter in FULL mode too now that FULL runs per-suite: run_scoped_suite must
      # never exonerate a suite belonging to THIS change (intermittence in code you are landing is
      # a FINDING, not a flake). Same --direct call the scoped branch makes below; best-effort —
      # an empty list simply means "exonerate nothing is unknown", which is the safe direction.
      direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
      gate_home_setup
      run_bats_all "$direct" || rc=1
    elif [[ -z "${sel//[[:space:]]/}" ]]; then
      echo "→ gate[scoped]: selector picked 0 suites — skipping bats (lint-only land)" >&2
      GATE_EFFECTIVE_FULL=0; SELECTED_N=0
    else
      # --direct MIRRORS the selection's ranges (operator ruling): the composed tree is what we
      # push, so a sibling-mapped suite is direct to THIS land too and must not be exonerated.
      direct="$("$GATE_SELECT" --direct "$range" ${EXTRA_RANGE:+"$EXTRA_RANGE"} 2>/dev/null || true)"
      GATE_EFFECTIVE_FULL=0; SELECTED_N=0
      # ONE clone for the whole selection, not one per suite — and deliberately NOT hoisted above
      # the 0-suite branch: a lint-only land must keep paying zero for a proof it never runs.
      gate_home_setup
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        SELECTED_N=$(( SELECTED_N + 1 ))
        # The SCOPED tier gets the same honest split as FULL. Before this it discarded the
        # distinction: any failure left GATE_RED/GATE_KILLED at 0, so gate_nonzero_code's else
        # branch reported a signal-killed scoped land as exit 6 "your code is broken". The two
        # tiers must not disagree about what a cut is (c605a2e's premise); this is the half of
        # that promise the scoped path never actually kept.
        srv=0; run_scoped_suite "$f" "$direct" || srv=$?
        if [[ "$srv" -eq 2 ]]; then GATE_KILLED=1; rc=1
        elif [[ "$srv" -ne 0 ]]; then GATE_RED=1; rc=1; fi
      done <<< "$sel"
      echo "→ gate[scoped]: ran $SELECTED_N selected suite(s) — gate-green stays where it was." >&2
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
  echo "→ ship-land[unlocked]: fetch + rebase + FULL gate — no lock held; concurrent landers gate in parallel" >&2
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

  # P0-1 gate-green producer: the gate ran GREEN on HEAD, so mark it — boundary-handoff.sh:122 fires its
  # "handoff before auto-compact eats the DoD" advisory only when gate-green == HEAD on a clean tree.
  # Before this, the sole gate-green writers were test fixtures, so boundary abstained 100% in production
  # (the FM1(b) advisory sat inert). Path matches wrap-ledger.sh:79 + boundary-handoff.sh:118 (readers).
  # Fires on the green path for BOTH --dry-run (proven-green, unpushed) and a real land — but
  # ONLY when the run proved the FULL suite (stamp_gate_green enforces that).
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
  # We hold the land-lock from here on ⇒ admission control becomes a NO-OP (see gate_admit):
  # sleeping under the lock would serialize every other lander behind this one's wait.
  IN_LAND_LOCK=1
  # CAS mode ($3/$4 non-empty): the full gate already ran GREEN, UNLOCKED, on exactly
  # (HEAD=GATE_HEAD, base=GATE_BASE). Hold the lock only for fetch-compare → push →
  # content-verify — the 2026-07-11 race window. A moved origin/HEAD ⇒ exit 42 (stale
  # gate, INTERNAL): the outer loop re-gates the new final tree unlocked.
  # FULL mode ($3/$4 empty — SHIP_LAND_GATE_ROUNDS=0 kill switch, or optimistic rounds
  # exhausted under sustained contention): rebase + full gate INSIDE the lock (pre-fix
  # behavior) — guaranteed progress, since a held mutex stops further pipeline movement.
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
    # P0-1 gate-green producer (see unlocked_reconcile_and_gate for the full rationale).
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
  # A scoped land proved only the selected suites, so the FULL suite is re-proven off the critical
  # path: queue the landed head and hand it to postland-verify.sh. start_new_session is MANDATORY —
  # nohup/disown children share our process group and are reaped by the harness's group SIGKILL.
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
  git branch -f "ship/backup-$(git rev-parse --short HEAD)" HEAD >/dev/null 2>&1 || true

  # --- optimistic rounds: FULL gate UNLOCKED (parallel across sessions); the lock holds
  #     ONLY fetch-compare → push → content-verify. A stale gate (exit 42: a sibling
  #     landed mid-gate) releases the lock and re-gates the new final tree out here. ---
  local ROUNDS round rc
  ROUNDS="${SHIP_LAND_GATE_ROUNDS:-3}"
  round=0
  while [[ "$round" -lt "$ROUNDS" ]]; do
    round=$(( round + 1 ))
    unlocked_reconcile_and_gate "$TRUNK" "$DRY_RUN"   # exits on 5/6/dry-run/nothing-to-land
    export SHIP_LAND_GATE_EFFECTIVE_FULL="$GATE_EFFECTIVE_FULL" SHIP_LAND_SELECTED_N="$SELECTED_N" \
           SHIP_LAND_FIRST_BASE="$FIRST_BASE"
    "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "$GATE_BASE" "$GATE_HEAD"
    rc=$?
    [[ "$rc" -ne 42 ]] && exit "$rc"   # landed (0) or a real failure (incl. land-lock's 75) — propagate
    echo "↻ ship-land: optimistic round ${round}/${ROUNDS} invalidated (sibling land mid-gate) — re-gating the new final tree unlocked." >&2
  done

  # --- rounds exhausted (sustained contention) or SHIP_LAND_GATE_ROUNDS=0: guaranteed
  #     progress — rebase + full gate INSIDE the lock (pre-fix behavior; a held mutex
  #     stops further pipeline movement, so this round cannot be invalidated). ---
  [[ "$ROUNDS" -gt 0 ]] && echo "→ ship-land: ${ROUNDS} optimistic round(s) exhausted — falling back to the in-lock full gate (guaranteed progress)." >&2
  exec "$LAND_LOCK" -- "$SELF" __locked "$TRUNK" "$DRY_RUN" "" ""
}

# ---- dispatch --------------------------------------------------------------

if [[ "${1:-}" = "__locked" ]]; then
  shift
  main_locked "$@"     # always exits internally
else
  main_outer "$@"      # exec's the locked child, or exits on a preflight refusal
fi
